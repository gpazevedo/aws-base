"""
vector Service

S3 Vector Embeddings Service - Generate and store embeddings using Amazon Bedrock
"""

import json
import os
import time
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from typing import Any

import boto3
import httpx
from botocore.exceptions import ClientError
from fastapi import APIRouter, FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from common import (
    configure_logging,
    configure_tracing,
    get_logger,
    LoggingMiddleware,
    health_check_simple,
    HealthResponse,
    ServiceInfo,
    InterServiceResponse,
)

# =============================================================================
# Configuration
# =============================================================================

SERVICE_NAME = "vector"
SERVICE_VERSION = "1.0.0"
START_TIME = time.time()  # Unix timestamp for uptime calculation

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# S3 Vector configuration (from Terraform environment variables)
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "amazon.titan-embed-text-v2:0")
VECTOR_BUCKET_NAME = os.getenv("VECTOR_BUCKET_NAME", "")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# =============================================================================
# Logging and Tracing Setup
# =============================================================================

configure_logging(log_level=LOG_LEVEL)

# Get logger with service context
logger = get_logger(__name__).bind(
    service=SERVICE_NAME,
    environment=ENVIRONMENT,
)

# Note: Tracing is automatically configured via ADOT Lambda Layer
# The ADOT layer provides automatic instrumentation for:
# - AWS SDK calls (boto3)
# - HTTP requests (httpx, requests)
# - Database calls
# - FastAPI endpoints
# No manual configure_tracing() needed when using ADOT layer
logger.info("service_initialized", adot_layer="enabled")


# =============================================================================
# AWS Clients
# =============================================================================


class AWSClients:
    """Lazy-loaded AWS clients for S3 and Bedrock."""

    _bedrock = None
    _s3 = None

    @property
    def bedrock(self):
        if self._bedrock is None:
            self._bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)
        return self._bedrock

    @property
    def s3(self):
        if self._s3 is None:
            self._s3 = boto3.client("s3", region_name=AWS_REGION)
        return self._s3


aws_clients = AWSClients()


# =============================================================================
# Pydantic Models
# =============================================================================


class EmbeddingRequest(BaseModel):
    """Request to generate embedding."""

    text: str = Field(..., description="Text to generate embedding for", min_length=1)
    store_in_s3: bool = Field(default=False, description="Store embedding in S3")
    embedding_id: str | None = Field(default=None, description="ID for S3 storage")


class EmbeddingResponse(BaseModel):
    """Response with generated embedding."""

    embedding: list[float]
    dimension: int
    model: str
    text_length: int
    processing_time_ms: float
    stored_in_s3: bool = False
    s3_key: str | None = None


class StoreEmbeddingRequest(BaseModel):
    """Request to store embedding in S3."""

    embedding_id: str = Field(..., description="Unique ID for the embedding")
    text: str = Field(..., description="Original text")
    embedding: list[float] = Field(..., description="Embedding vector")
    metadata: dict[str, Any] | None = Field(default=None, description="Additional metadata")


class StoreEmbeddingResponse(BaseModel):
    """Response after storing embedding."""

    success: bool
    s3_key: str
    bucket: str


class RetrieveEmbeddingResponse(BaseModel):
    """Response with retrieved embedding."""

    embedding_id: str
    text: str
    embedding: list[float]
    dimension: int
    metadata: dict[str, Any]


class DeleteEmbeddingResponse(BaseModel):
    """Response after deleting embedding."""

    success: bool
    embedding_id: str
    message: str


# =============================================================================
# Application Lifecycle
# =============================================================================


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Manage application lifespan with proper resource cleanup.

    This modern FastAPI pattern replaces the deprecated @app.on_event decorators.
    Resources are initialized on startup and cleaned up on shutdown.
    """
    logger.info(
        "service_starting",
        service=SERVICE_NAME,
        version=SERVICE_VERSION,
        environment=ENVIRONMENT,
    )

    # Initialize shared HTTP client for inter-service communication
    app.state.http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(30.0),
        limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
    )

    yield

    # Cleanup
    logger.info("service_stopping", service=SERVICE_NAME)
    await app.state.http_client.aclose()


# =============================================================================
# FastAPI Application
# =============================================================================

app = FastAPI(
    title=f"{SERVICE_NAME} Service",
    description="S3Vector service",
    version=SERVICE_VERSION,
    lifespan=lifespan,
    root_path=f"/{SERVICE_NAME}",  # API Gateway path prefix - helps with OpenAPI docs
)

# Add middleware
app.add_middleware(LoggingMiddleware)


# =============================================================================
# Routing Strategy
# =============================================================================
# For services deployed with API Gateway path prefix (e.g., /api3/*):
# - API Gateway sends full path including prefix to Lambda
# - We need to handle both root paths and prefixed paths
# - Use FastAPI router to handle the prefix

# Create router for service endpoints
router = APIRouter()


@router.get("/health", response_model=HealthResponse)
async def health_check():
    """Simple health check endpoint"""
    return await health_check_simple(SERVICE_NAME, SERVICE_VERSION, START_TIME)


@router.get("/status", response_model=ServiceInfo)
async def status():
    """Detailed service status"""
    return ServiceInfo(
        name=SERVICE_NAME,
        version=SERVICE_VERSION,
        environment=ENVIRONMENT,
        description="S3Vector service",
    )


@router.get("/")
async def root():
    """Root endpoint"""
    logger.info("root_endpoint_called")
    return {
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "message": f"Welcome to {SERVICE_NAME} service",
    }


# Mount router at both root and service prefix to handle API Gateway routing
# This allows the service to work whether accessed at "/" or "/SERVICE_NAME/"
app.include_router(router)  # For root-level access
app.include_router(router, prefix=f"/{SERVICE_NAME}")  # For prefixed access


# =============================================================================
# Embedding Endpoints
# =============================================================================


@app.post("/embeddings/generate", response_model=EmbeddingResponse, tags=["Embeddings"])
async def generate_embedding(request: EmbeddingRequest) -> EmbeddingResponse:
    """Generate embedding using Amazon Bedrock Titan model."""
    logger.info(
        "generating_embedding", text_length=len(request.text), store_in_s3=request.store_in_s3
    )

    start_time = time.time()

    try:
        # Invoke Bedrock model
        body = json.dumps({"inputText": request.text})

        response = aws_clients.bedrock.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=body,
        )

        result = json.loads(response["body"].read())
        embedding = result["embedding"]
        processing_time = (time.time() - start_time) * 1000

        logger.info(
            "embedding_generated",
            model=BEDROCK_MODEL_ID,
            dimension=len(embedding),
            processing_time_ms=round(processing_time, 2),
        )

        # Optionally store in S3
        s3_key = None
        if request.store_in_s3:
            if not request.embedding_id:
                raise HTTPException(
                    status_code=400, detail="embedding_id required when store_in_s3=true"
                )

            s3_key = f"embeddings/{request.embedding_id}.json"
            await store_embedding_in_s3(request.embedding_id, request.text, embedding, {})
            logger.info("embedding_stored_in_s3", s3_key=s3_key)

        return EmbeddingResponse(
            embedding=embedding,
            dimension=len(embedding),
            model=BEDROCK_MODEL_ID,
            text_length=len(request.text),
            processing_time_ms=round(processing_time, 2),
            stored_in_s3=request.store_in_s3,
            s3_key=s3_key,
        )

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        logger.error("bedrock_error", error_code=error_code, error=str(e))
        raise HTTPException(status_code=503, detail=f"Bedrock error: {error_code}") from e
    except Exception as e:
        logger.exception("embedding_generation_failed", error=str(e))
        raise HTTPException(
            status_code=500, detail=f"Failed to generate embedding: {str(e)}"
        ) from e


@app.post("/embeddings/store", response_model=StoreEmbeddingResponse, tags=["Embeddings"])
async def store_embedding(request: StoreEmbeddingRequest) -> StoreEmbeddingResponse:
    """Store embedding in S3."""
    if not VECTOR_BUCKET_NAME:
        raise HTTPException(status_code=503, detail="S3 bucket not configured")

    logger.info(
        "storing_embedding", embedding_id=request.embedding_id, dimension=len(request.embedding)
    )

    try:
        s3_key = f"embeddings/{request.embedding_id}.json"
        await store_embedding_in_s3(
            request.embedding_id, request.text, request.embedding, request.metadata or {}
        )

        logger.info("embedding_stored", s3_key=s3_key)

        return StoreEmbeddingResponse(
            success=True, s3_key=s3_key, bucket=VECTOR_BUCKET_NAME
        )

    except Exception as e:
        logger.exception("embedding_store_failed", embedding_id=request.embedding_id, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to store embedding: {str(e)}") from e


@app.get(
    "/embeddings/{embedding_id}", response_model=RetrieveEmbeddingResponse, tags=["Embeddings"]
)
async def retrieve_embedding(embedding_id: str) -> RetrieveEmbeddingResponse:
    """Retrieve embedding from S3."""
    if not VECTOR_BUCKET_NAME:
        raise HTTPException(status_code=503, detail="S3 bucket not configured")

    logger.info("retrieving_embedding", embedding_id=embedding_id)

    try:
        s3_key = f"embeddings/{embedding_id}.json"
        response = aws_clients.s3.get_object(Bucket=VECTOR_BUCKET_NAME, Key=s3_key)

        data = json.loads(response["Body"].read())

        logger.info(
            "embedding_retrieved", embedding_id=embedding_id, dimension=len(data["embedding"])
        )

        return RetrieveEmbeddingResponse(
            embedding_id=data["id"],
            text=data["text"],
            embedding=data["embedding"],
            dimension=data["dimension"],
            metadata=data.get("metadata", {}),
        )

    except aws_clients.s3.exceptions.NoSuchKey:
        raise HTTPException(status_code=404, detail=f"Embedding not found: {embedding_id}")
    except Exception as e:
        logger.exception("embedding_retrieval_failed", embedding_id=embedding_id, error=str(e))
        raise HTTPException(
            status_code=500, detail=f"Failed to retrieve embedding: {str(e)}"
        ) from e


@app.delete(
    "/embeddings/{embedding_id}", response_model=DeleteEmbeddingResponse, tags=["Embeddings"]
)
async def delete_embedding(embedding_id: str) -> DeleteEmbeddingResponse:
    """Delete embedding from S3."""
    if not VECTOR_BUCKET_NAME:
        raise HTTPException(status_code=503, detail="S3 bucket not configured")

    logger.info("deleting_embedding", embedding_id=embedding_id)

    try:
        s3_key = f"embeddings/{embedding_id}.json"

        # Check if embedding exists before deleting
        try:
            aws_clients.s3.head_object(Bucket=VECTOR_BUCKET_NAME, Key=s3_key)
        except ClientError as e:
            if e.response["Error"]["Code"] == "404":
                raise HTTPException(status_code=404, detail=f"Embedding not found: {embedding_id}")
            raise  # Re-raise other ClientErrors

        # Delete the embedding
        aws_clients.s3.delete_object(Bucket=VECTOR_BUCKET_NAME, Key=s3_key)

        logger.info("embedding_deleted", embedding_id=embedding_id, s3_key=s3_key)

        return DeleteEmbeddingResponse(
            success=True,
            embedding_id=embedding_id,
            message=f"Embedding {embedding_id} successfully deleted",
        )

    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        logger.exception("embedding_deletion_failed", embedding_id=embedding_id, error=str(e))
        raise HTTPException(
            status_code=500, detail=f"Failed to delete embedding: {str(e)}"
        ) from e


async def store_embedding_in_s3(
    embedding_id: str, text: str, embedding: list[float], metadata: dict[str, Any]
) -> None:
    """Store embedding in S3."""
    document = {
        "id": embedding_id,
        "text": text,
        "embedding": embedding,
        "dimension": len(embedding),
        "metadata": metadata,
        "created_at": datetime.now(UTC).isoformat(),
    }

    aws_clients.s3.put_object(
        Bucket=VECTOR_BUCKET_NAME,
        Key=f"embeddings/{embedding_id}.json",
        Body=json.dumps(document),
        ContentType="application/json",
    )


# =============================================================================
# Inter-Service Communication Endpoints
# =============================================================================


@app.get("/inter-service", response_model=InterServiceResponse, tags=["Service Integration"])
async def call_service(
    service_url: str = Query(
        ...,
        description="Full URL of the service endpoint to call (e.g., https://example.com/health)",
    ),
) -> InterServiceResponse:
    """
    Call another service's endpoint and return the response.

    This endpoint demonstrates service-to-service communication by calling
    any provided service URL and returning what it received.
    Uses the shared HTTP client from app.state for connection pooling.

    Args:
        service_url: Full URL of the service endpoint to call (query parameter)

    Returns:
        InterServiceResponse: The response from the target service including
                             status code, response time, and the full response body

    Raises:
        HTTPException: If the target service is unreachable or returns an error

    Example:
        GET /inter-service?service_url=https://example.com/health
    """
    start_time = time.time()

    logger.info("calling_external_service", target_url=service_url)

    try:
        # Use shared HTTP client from app.state (initialized in lifespan)
        response = await app.state.http_client.get(service_url)
        response_time = (time.time() - start_time) * 1000  # Convert to ms

        logger.info(
            "external_service_response",
            target_url=service_url,
            status_code=response.status_code,
            response_time_ms=round(response_time, 2),
        )

        # Return the response regardless of status code
        return InterServiceResponse(
            service_response=response.json(),
            status_code=response.status_code,
            response_time_ms=round(response_time, 2),
            target_url=service_url,
        )
    except httpx.RequestError as e:
        logger.error(
            "external_service_request_error",
            target_url=service_url,
            error=str(e),
        )
        raise HTTPException(
            status_code=503,
            detail=f"Failed to reach service at {service_url}: {str(e)}",
        ) from e
    except Exception as e:
        logger.exception(
            "external_service_unexpected_error",
            target_url=service_url,
            error=str(e),
        )
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error calling service at {service_url}: {str(e)}",
        ) from e


# =============================================================================
# Lambda Handler
# =============================================================================

# Mangum adapter to run FastAPI on AWS Lambda
# Python 3.14 compatibility: Explicitly manage event loop for Lambda

try:
    import asyncio
    from mangum import Mangum

    def handler(event, context):
        """
        AWS Lambda handler with Python 3.14 asyncio compatibility.

        Python 3.14 removed the implicit event loop from asyncio.get_event_loop().
        We need to explicitly create and set an event loop for Mangum to work.

        Performance optimization: HTTP client is reused across warm Lambda invocations
        when the event loop is the same. If the loop changes, the client is recreated
        to avoid "bound to a different event loop" errors.
        """
        # Get or create event loop - reuse existing loop from warm container if available
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            # No running loop - create and set a new one
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)

        # Store the loop ID to detect when Lambda creates a new loop
        current_loop_id = id(asyncio.get_event_loop())

        # Initialize or recreate HTTP client if loop changed
        if (
            not hasattr(app.state, "http_client")
            or not hasattr(app.state, "_loop_id")
            or app.state._loop_id != current_loop_id
        ):
            # Clean up old client if it exists
            if hasattr(app.state, "http_client"):
                try:
                    # Close old client (async operation, so run in the current loop)
                    asyncio.get_event_loop().run_until_complete(app.state.http_client.aclose())
                except Exception:
                    pass  # Ignore errors from closing stale client

            # Create new HTTP client bound to current event loop
            app.state.http_client = httpx.AsyncClient(
                timeout=httpx.Timeout(30.0),
                limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
            )
            app.state._loop_id = current_loop_id

        # Create Mangum handler with the app (lifespan="off" to avoid double initialization)
        mangum_handler = Mangum(app, lifespan="off")
        return mangum_handler(event, context)

        # Note: Event loop and HTTP client are NOT closed here
        # They will be reused across Lambda invocations when the loop stays the same
        # Lambda runtime will clean them up when the container is terminated

    logger.info("lambda_handler_configured")
except ImportError:
    logger.warning("mangum_not_installed", msg="Lambda handler not available")
    handler = None


# =============================================================================
# Development Server
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    logger.info("starting_dev_server", port=8000)
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_config=None,  # Use our custom logging
    )

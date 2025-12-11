"""S3 Vector Service - Amazon Bedrock Titan embeddings generation and S3 storage."""

import asyncio
import json
import os
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from typing import Any

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from mangum import Mangum
from pydantic import BaseModel, Field
from shared import (
    BaseAWSSettings,
    FullServiceSettings,
    LoggingMiddleware,
    StatusResponse,
    configure_logging,
    configure_tracing,
    get_logger,
    liveness_probe_simple,
    readiness_probe_simple,
)

# =============================================================================
# Configuration
# =============================================================================


class Settings(FullServiceSettings, BaseAWSSettings):
    """Application settings loaded from environment variables."""

    # Service configuration (inherited from FullServiceSettings)
    service_name: str = "s3vector"
    service_version: str = "1.0.0"

    # AWS Configuration (inherited from BaseAWSSettings, extended here)
    bedrock_model_id: str = "amazon.titan-embed-text-v2:0"
    vector_bucket_name: str = ""


settings = Settings()

# Track application startup time
START_TIME = time.time()


# =============================================================================
# Logging Configuration
# =============================================================================

configure_logging(log_level=settings.log_level)
logger = get_logger(__name__)

logger.info(
    "module_initialization",
    service_name=settings.service_name,
    service_version=settings.service_version,
    is_lambda=bool(os.getenv("AWS_LAMBDA_FUNCTION_NAME")),
)


# =============================================================================
# AWS Clients
# =============================================================================


class AWSClients:
    """Lazy-loaded AWS clients."""

    _bedrock = None
    _s3 = None

    @property
    def bedrock(self):
        if self._bedrock is None:
            self._bedrock = boto3.client("bedrock-runtime", region_name=settings.aws_region)
        return self._bedrock

    @property
    def s3(self):
        if self._s3 is None:
            self._s3 = boto3.client("s3", region_name=settings.aws_region)
        return self._s3


aws_clients = AWSClients()


# =============================================================================
# Application Lifespan
# =============================================================================


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Manage application lifespan."""
    logger.info("lifespan_startup_begin", is_lambda=bool(os.getenv("AWS_LAMBDA_FUNCTION_NAME")))

    configure_tracing(
        service_name=settings.service_name,
        service_version=settings.service_version,
        environment=settings.environment,
        app=app,
    )

    logger.info(
        "application_startup",
        service=settings.service_name,
        version=settings.service_version,
        environment=settings.environment,
        bedrock_model=settings.bedrock_model_id,
        vector_bucket=settings.vector_bucket_name or "not_configured",
    )

    yield

    logger.info("application_shutdown", service=settings.service_name)


# =============================================================================
# FastAPI Application
# =============================================================================

app = FastAPI(
    title="S3 Vector Service",
    description="Amazon Bedrock Titan embeddings generation and S3 vector storage",
    version=settings.service_version,
    root_path="/s3vector" if os.getenv("AWS_LAMBDA_FUNCTION_NAME") else "",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
    lifespan=lifespan,
)

# Add logging middleware from shared library
app.add_middleware(LoggingMiddleware)


# =============================================================================
# Pydantic Models
# =============================================================================


class HealthResponse(BaseModel):
    """Health check response."""

    status: str
    timestamp: str
    uptime_seconds: float
    version: str
    bedrock_configured: bool
    s3_configured: bool


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


# =============================================================================
# Health Check Endpoints
# =============================================================================


@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check() -> HealthResponse:
    """Comprehensive health check."""
    uptime = time.time() - START_TIME
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(UTC).isoformat(),
        uptime_seconds=round(uptime, 2),
        version=settings.service_version,
        bedrock_configured=bool(settings.bedrock_model_id),
        s3_configured=bool(settings.vector_bucket_name),
    )


@app.get("/liveness", response_model=StatusResponse, tags=["Health"])
async def liveness_probe() -> StatusResponse:
    """Kubernetes-style liveness probe."""
    return await liveness_probe_simple()


@app.get("/readiness", response_model=StatusResponse, tags=["Health"])
async def readiness_probe() -> StatusResponse:
    """Kubernetes-style readiness probe."""
    # Check if required services are configured
    if not settings.vector_bucket_name:
        raise HTTPException(status_code=503, detail="S3 bucket not configured")

    return await readiness_probe_simple()


# =============================================================================
# Embedding Generation Endpoints
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
            modelId=settings.bedrock_model_id,
            contentType="application/json",
            accept="application/json",
            body=body,
        )

        result = json.loads(response["body"].read())
        embedding = result["embedding"]
        processing_time = (time.time() - start_time) * 1000

        logger.info(
            "embedding_generated",
            model=settings.bedrock_model_id,
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
            model=settings.bedrock_model_id,
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
    if not settings.vector_bucket_name:
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
            success=True, s3_key=s3_key, bucket=settings.vector_bucket_name
        )

    except Exception as e:
        logger.exception("embedding_store_failed", embedding_id=request.embedding_id, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to store embedding: {str(e)}") from e


@app.get(
    "/embeddings/{embedding_id}", response_model=RetrieveEmbeddingResponse, tags=["Embeddings"]
)
async def retrieve_embedding(embedding_id: str) -> RetrieveEmbeddingResponse:
    """Retrieve embedding from S3."""
    if not settings.vector_bucket_name:
        raise HTTPException(status_code=503, detail="S3 bucket not configured")

    logger.info("retrieving_embedding", embedding_id=embedding_id)

    try:
        s3_key = f"embeddings/{embedding_id}.json"
        response = aws_clients.s3.get_object(Bucket=settings.vector_bucket_name, Key=s3_key)

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


# =============================================================================
# Helper Functions
# =============================================================================


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
        Bucket=settings.vector_bucket_name,
        Key=f"embeddings/{embedding_id}.json",
        Body=json.dumps(document),
        ContentType="application/json",
    )


# =============================================================================
# Lambda Handler
# =============================================================================


def handler(event, context):
    """
    AWS Lambda handler with Python 3.14 asyncio compatibility.

    Python 3.14 removed the implicit event loop from asyncio.get_event_loop().
    We need to explicitly create and set an event loop for Mangum to work.

    Performance optimization: Event loop is NOT closed to allow reuse across
    warm Lambda invocations. Lambda runtime will clean up when container terminates.
    """
    # Get or create event loop - reuse existing loop from warm container if available
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        # No running loop - create and set a new one
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    # Create Mangum handler with the app (lifespan="off" to avoid double initialization)
    mangum_handler = Mangum(app, lifespan="off")
    return mangum_handler(event, context)

    # Note: Event loop is NOT closed here for better performance
    # It will be reused across Lambda invocations
    # Lambda runtime will clean it up when the container is terminated


# =============================================================================
# Local Development Server
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")

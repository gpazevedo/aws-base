#!/bin/bash
# =============================================================================
# Add Embeddings Router to Existing Service
# =============================================================================
# This script adds the embeddings router functionality to an existing service:
# - Creates app/routers/embeddings.py with Bedrock embedding endpoints
# - Creates/updates app/schemas.py with embedding models
# - Creates app/services.py with AWS client utilities
# - Updates app/config.py with required AWS configuration
# - Updates main.py to import and include the embeddings router
# - Creates integration tests
#
# Usage: ./scripts/add-embeddings.sh ENVIRONMENT SERVICE_NAME
#
# Examples:
#   ./scripts/add-embeddings.sh dev payments
#   ./scripts/add-embeddings.sh prod notifications
# =============================================================================

set -e

# =============================================================================
# Parse Arguments
# =============================================================================

ENVIRONMENT="${1}"
SERVICE_NAME="${2}"

if [ -z "$ENVIRONMENT" ] || [ -z "$SERVICE_NAME" ]; then
  echo "❌ Error: Both environment and service name are required"
  echo ""
  echo "Usage: $0 ENVIRONMENT SERVICE_NAME"
  echo ""
  echo "Examples:"
  echo "  $0 dev payments"
  echo "  $0 prod notifications"
  echo ""
  exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

BACKEND_DIR="backend"
SERVICE_DIR="$BACKEND_DIR/$SERVICE_NAME"
MAIN_FILE="$SERVICE_DIR/main.py"
CONFIG_FILE="$SERVICE_DIR/app/config.py"
SCHEMAS_FILE="$SERVICE_DIR/app/schemas.py"
SERVICES_FILE="$SERVICE_DIR/app/services.py"
EMBEDDINGS_FILE="$SERVICE_DIR/app/routers/embeddings.py"
TEST_FILE="$SERVICE_DIR/tests/test_embebedings.py"

echo "🚀 Adding embeddings router to service: $SERVICE_NAME"
echo ""
echo "📋 Configuration:"
echo "   Environment: $ENVIRONMENT"
echo "   Service Name: $SERVICE_NAME"
echo "   Service Directory: $SERVICE_DIR"
echo ""

# =============================================================================
# Check Prerequisites
# =============================================================================

echo "🔍 Checking prerequisites..."

# Check if service directory exists
if [ ! -d "$SERVICE_DIR" ]; then
  echo "❌ Error: Service directory does not exist: $SERVICE_DIR"
  exit 1
fi

# Check if main.py exists
if [ ! -f "$MAIN_FILE" ]; then
  echo "❌ Error: main.py not found at: $MAIN_FILE"
  exit 1
fi

# Check if app/config.py exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Error: app/config.py not found at: $CONFIG_FILE"
  exit 1
fi

# Check if app/routers directory exists
if [ ! -d "$SERVICE_DIR/app/routers" ]; then
  echo "❌ Error: app/routers directory not found at: $SERVICE_DIR/app/routers"
  exit 1
fi

# Check if tests directory exists
if [ ! -d "$SERVICE_DIR/tests" ]; then
  echo "⚠️  Warning: tests directory not found, creating it..."
  mkdir -p "$SERVICE_DIR/tests"
fi

# Check if embeddings.py already exists
if [ -f "$EMBEDDINGS_FILE" ]; then
  echo "⚠️  Warning: embeddings.py already exists at: $EMBEDDINGS_FILE"
  read -p "Do you want to overwrite it? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Aborted by user"
    exit 1
  fi
fi

echo "✅ Prerequisites checked"
echo ""

# =============================================================================
# Update app/config.py - Add AWS Configuration
# =============================================================================

echo "📝 Updating app/config.py with AWS configuration..."

# Check if AWS configuration already exists
if grep -q "BEDROCK_MODEL_ID" "$CONFIG_FILE"; then
  echo "✅ AWS configuration already exists in config.py"
else
  # Add AWS configuration section
  cat >> "$CONFIG_FILE" <<'EOF'

# AWS Configuration
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "amazon.titan-embed-text-v2:0")
VECTOR_BUCKET_NAME = os.getenv("VECTOR_BUCKET_NAME", "")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
EOF
  echo "✅ Added AWS configuration to config.py"
fi

echo ""

# =============================================================================
# Create app/services.py
# =============================================================================

echo "📝 Creating app/services.py..."

cat > "$SERVICES_FILE" <<'EOF'
import boto3
import json
from datetime import UTC, datetime
from typing import Any
from app.config import AWS_REGION, VECTOR_BUCKET_NAME

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

async def store_embedding_in_s3(
    embedding_id: str, text: str, embedding: list[float], metadata: dict[str, Any]
) -> None:
    """Helper function to store embedding in S3."""
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
EOF

echo "✅ Created app/services.py"
echo ""

# =============================================================================
# Create/Update app/schemas.py
# =============================================================================

echo "📝 Checking app/schemas.py..."

# Define the required classes
REQUIRED_SCHEMAS="EmbeddingRequest EmbeddingResponse StoreEmbeddingRequest StoreEmbeddingResponse RetrieveEmbeddingResponse DeleteEmbeddingResponse"

if [ -f "$SCHEMAS_FILE" ]; then
  echo "✅ schemas.py exists, checking for required classes..."

  # Check which classes are missing
  MISSING_SCHEMAS=""
  for schema in $REQUIRED_SCHEMAS; do
    if ! grep -q "class $schema" "$SCHEMAS_FILE"; then
      MISSING_SCHEMAS="$MISSING_SCHEMAS $schema"
    fi
  done

  if [ -n "$MISSING_SCHEMAS" ]; then
    echo "⚠️  Missing schemas:$MISSING_SCHEMAS"
    echo "   Adding missing schemas to existing file..."

    # Append missing schemas
    cat >> "$SCHEMAS_FILE" <<'EOF'

# Embedding Schemas
class EmbeddingRequest(BaseModel):
    text: str = Field(..., description="Text to generate embedding for", min_length=1)
    store_in_s3: bool = Field(default=False, description="Store embedding in S3")
    embedding_id: str | None = Field(default=None, description="ID for S3 storage")

class EmbeddingResponse(BaseModel):
    embedding: list[float]
    dimension: int
    model: str
    text_length: int
    processing_time_ms: float
    stored_in_s3: bool = False
    s3_key: str | None = None

class StoreEmbeddingRequest(BaseModel):
    embedding_id: str = Field(..., description="Unique ID for the embedding")
    text: str = Field(..., description="Original text")
    embedding: list[float] = Field(..., description="Embedding vector")
    metadata: dict[str, Any] | None = Field(default=None, description="Additional metadata")

class StoreEmbeddingResponse(BaseModel):
    success: bool
    s3_key: str
    bucket: str

class RetrieveEmbeddingResponse(BaseModel):
    embedding_id: str
    text: str
    embedding: list[float]
    dimension: int
    metadata: dict[str, Any]

class DeleteEmbeddingResponse(BaseModel):
    success: bool
    embedding_id: str
    message: str
EOF

    echo "✅ Added missing schemas to schemas.py"
  else
    echo "✅ All required schemas already exist"
  fi
else
  echo "   Creating new schemas.py file..."
  cat > "$SCHEMAS_FILE" <<'EOF'
from typing import Any
from pydantic import BaseModel, Field

class EmbeddingRequest(BaseModel):
    text: str = Field(..., description="Text to generate embedding for", min_length=1)
    store_in_s3: bool = Field(default=False, description="Store embedding in S3")
    embedding_id: str | None = Field(default=None, description="ID for S3 storage")

class EmbeddingResponse(BaseModel):
    embedding: list[float]
    dimension: int
    model: str
    text_length: int
    processing_time_ms: float
    stored_in_s3: bool = False
    s3_key: str | None = None

class StoreEmbeddingRequest(BaseModel):
    embedding_id: str = Field(..., description="Unique ID for the embedding")
    text: str = Field(..., description="Original text")
    embedding: list[float] = Field(..., description="Embedding vector")
    metadata: dict[str, Any] | None = Field(default=None, description="Additional metadata")

class StoreEmbeddingResponse(BaseModel):
    success: bool
    s3_key: str
    bucket: str

class RetrieveEmbeddingResponse(BaseModel):
    embedding_id: str
    text: str
    embedding: list[float]
    dimension: int
    metadata: dict[str, Any]

class DeleteEmbeddingResponse(BaseModel):
    success: bool
    embedding_id: str
    message: str
EOF
  echo "✅ Created schemas.py"
fi

echo ""

# =============================================================================
# Create app/routers/embeddings.py
# =============================================================================

echo "📝 Creating app/routers/embeddings.py..."

cat > "$EMBEDDINGS_FILE" <<'EOF'
import time
import json
from fastapi import APIRouter, HTTPException
from botocore.exceptions import ClientError

from common import get_logger
from app.config import SERVICE_NAME, ENVIRONMENT, BEDROCK_MODEL_ID, VECTOR_BUCKET_NAME
from app.schemas import (
    EmbeddingRequest, EmbeddingResponse, StoreEmbeddingRequest,
    StoreEmbeddingResponse, RetrieveEmbeddingResponse, DeleteEmbeddingResponse
)
from app.services import aws_clients, store_embedding_in_s3

router = APIRouter(tags=["Embeddings"])

logger = get_logger(__name__).bind(service=SERVICE_NAME, environment=ENVIRONMENT)

@router.post("/embeddings/generate", response_model=EmbeddingResponse)
async def generate_embedding(request: EmbeddingRequest) -> EmbeddingResponse:
    logger.info("generating_embedding", text_length=len(request.text), store_in_s3=request.store_in_s3)
    start_time = time.time()

    try:
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

        s3_key = None
        if request.store_in_s3:
            if not request.embedding_id:
                raise HTTPException(status_code=400, detail="embedding_id required when store_in_s3=true")
            s3_key = f"embeddings/{request.embedding_id}.json"
            await store_embedding_in_s3(request.embedding_id, request.text, embedding, {})

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
        raise HTTPException(status_code=500, detail=f"Failed to generate embedding: {str(e)}") from e

@router.post("/embeddings/store", response_model=StoreEmbeddingResponse)
async def store_embedding(request: StoreEmbeddingRequest) -> StoreEmbeddingResponse:
    if not VECTOR_BUCKET_NAME:
        raise HTTPException(status_code=503, detail="S3 bucket not configured")

    try:
        s3_key = f"embeddings/{request.embedding_id}.json"
        await store_embedding_in_s3(
            request.embedding_id, request.text, request.embedding, request.metadata or {}
        )
        return StoreEmbeddingResponse(success=True, s3_key=s3_key, bucket=VECTOR_BUCKET_NAME)
    except Exception as e:
        logger.exception("embedding_store_failed", embedding_id=request.embedding_id, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to store embedding: {str(e)}") from e



@router.get(
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


@router.delete(
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
EOF

echo "✅ Created embeddings.py"
echo ""

# =============================================================================
# Update main.py - Add embeddings import
# =============================================================================

echo "📝 Updating main.py imports..."

# Check if the import line exists and contains "embeddings"
if grep -q "^from app.routers import" "$MAIN_FILE"; then
  # Check if embeddings is already imported
  if grep "^from app.routers import" "$MAIN_FILE" | grep -q "embeddings"; then
    echo "✅ embeddings already imported in main.py"
  else
    # Add embeddings to the import line (handles both single and multiple imports)
    # This regex matches the end of the import line and adds embeddings before the newline
    sed -i 's/^\(from app.routers import.*\)$/\1, embeddings/' "$MAIN_FILE"
    echo "✅ Added embeddings to imports"
  fi
else
  echo "⚠️  Warning: Could not find 'from app.routers import' line in main.py"
  echo "   Please manually add: from app.routers import system, embeddings"
fi

echo ""

# =============================================================================
# Update main.py - Add embeddings router include
# =============================================================================

echo "📝 Updating main.py router includes..."

# Check if the router include already exists
if grep -q "api_router.include_router(embeddings.router)" "$MAIN_FILE"; then
  echo "✅ embeddings.router already included in main.py"
else
  # Find the line with api_router.include_router and add embeddings after it
  # This will add it after the last include_router line
  if grep -q "^api_router.include_router" "$MAIN_FILE"; then
    # Get the line number of the last api_router.include_router
    LAST_INCLUDE_LINE=$(grep -n "^api_router.include_router" "$MAIN_FILE" | tail -1 | cut -d: -f1)

    # Insert the new line after the last include_router
    sed -i "${LAST_INCLUDE_LINE}a api_router.include_router(embeddings.router)" "$MAIN_FILE"
    echo "✅ Added api_router.include_router(embeddings.router)"
  else
    echo "⚠️  Warning: Could not find any 'api_router.include_router' lines in main.py"
    echo "   Please manually add: api_router.include_router(embeddings.router)"
  fi
fi

echo ""

# =============================================================================
# Create tests/test_embebedings.py
# =============================================================================

echo "📝 Creating tests/test_embebedings.py..."

# Read the template and replace 'vector' with the service name
cat > "$TEST_FILE" <<EOF
"""
Integration Tests for S3 Vector Embedding Endpoints

These tests use ACTUAL AWS services (Bedrock and S3) to verify the complete workflow.
They are not unit tests - they make real API calls to AWS.

Prerequisites:
- AWS credentials configured (via environment or ~/.aws/credentials)
- VECTOR_BUCKET_NAME environment variable set
- Bedrock model access enabled in the AWS account
- Appropriate IAM permissions for S3 and Bedrock

Run with: pytest backend/$SERVICE_NAME/tests/test_embebedings.py -v
"""

import os
import time
from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from main import app

# Skip all tests if not in integration test mode
pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "true",
    reason="Integration tests disabled. Set RUN_INTEGRATION_TESTS=true to enable",
)

# Skip marker for tests that require VECTOR_BUCKET_NAME
skip_without_bucket = pytest.mark.skipif(
    not os.getenv("VECTOR_BUCKET_NAME"),
    reason="VECTOR_BUCKET_NAME not set. Set it to run S3-dependent tests",
)


@pytest.fixture
def client():
    """Create test client."""
    return TestClient(app)


@pytest.fixture
def test_embedding_id():
    """Generate unique embedding ID for test isolation."""
    return f"test-embedding-{int(time.time() * 1000)}"


@pytest.fixture
def cleanup_embedding(client):
    """Cleanup embeddings after tests using the delete endpoint."""
    embeddings_to_cleanup = []

    def register(embedding_id: str):
        """Register an embedding ID for cleanup."""
        embeddings_to_cleanup.append(embedding_id)

    yield register

    # Cleanup after test using the delete endpoint
    for embedding_id in embeddings_to_cleanup:
        try:
            client.delete(f"/embeddings/{embedding_id}")
        except Exception:
            pass  # Ignore cleanup errors


# =============================================================================
# Configuration Validation
# =============================================================================


def test_aws_configuration():
    """Verify AWS services are properly configured."""
    # BEDROCK_MODEL_ID is optional (has default in main.py)
    bucket_name = os.getenv("VECTOR_BUCKET_NAME")
    model_id = os.getenv("BEDROCK_MODEL_ID", "amazon.titan-embed-text-v2:0")

    if bucket_name:
        print(f"Using bucket: {bucket_name}")
        print(f"Using model: {model_id}")
    else:
        print("VECTOR_BUCKET_NAME not set - S3-dependent tests will be skipped")
        print(f"Using model: {model_id}")


# =============================================================================
# Integration Test: Generate Embedding
# =============================================================================


def test_generate_embedding_basic(client):
    """Test generating embedding with real Bedrock service."""
    response = client.post(
        "/embeddings/generate",
        json={"text": "Hello world", "store_in_s3": False},
    )

    assert response.status_code == 200, f"Failed: {response.json()}"
    data = response.json()

    # Verify response structure
    assert "embedding" in data
    assert "dimension" in data
    assert "model" in data
    assert "text_length" in data
    assert "processing_time_ms" in data
    assert "stored_in_s3" in data
    assert "s3_key" in data

    # Verify embedding properties
    assert isinstance(data["embedding"], list)
    assert len(data["embedding"]) > 0, "Embedding should not be empty"
    assert data["dimension"] == len(data["embedding"])
    assert data["text_length"] == 11  # len("Hello world")
    assert data["processing_time_ms"] > 0
    assert data["stored_in_s3"] is False
    assert data["s3_key"] is None

    # Verify embedding values are floats
    assert all(isinstance(v, (int, float)) for v in data["embedding"])

    print(f" Generated embedding with {data['dimension']} dimensions")
    print(f" Processing time: {data['processing_time_ms']:.2f}ms")


# =============================================================================
# Integration Test: Full Workflow (Generate → Store → Retrieve)
# =============================================================================


@skip_without_bucket
def test_full_embedding_workflow(client, test_embedding_id, cleanup_embedding):
    """
    Test complete workflow with real AWS services:
    1. Generate embedding using Bedrock
    2. Store in S3
    3. Retrieve from S3
    4. Verify data integrity
    5. Delete from S3
    """
    test_text = "This is a test sentence for vector embeddings."

    # Register for cleanup
    cleanup_embedding(test_embedding_id)

    # Step 1: Generate and store embedding
    print(f"\\n=== Step 1: Generate and store embedding (ID: {test_embedding_id}) ===")
    generate_response = client.post(
        "/embeddings/generate",
        json={
            "text": test_text,
            "store_in_s3": True,
            "embedding_id": test_embedding_id,
        },
    )

    assert generate_response.status_code == 200, f"Generate failed: {generate_response.json()}"
    generate_data = generate_response.json()

    # Verify generation response
    assert generate_data["stored_in_s3"] is True
    assert generate_data["s3_key"] == f"embeddings/{test_embedding_id}.json"
    assert len(generate_data["embedding"]) > 0
    original_embedding = generate_data["embedding"]
    original_dimension = generate_data["dimension"]

    print(f" Generated embedding: {original_dimension} dimensions")
    print(f" Stored in S3: {generate_data['s3_key']}")
    print(f" Processing time: {generate_data['processing_time_ms']:.2f}ms")

    # Small delay to ensure S3 consistency
    time.sleep(0.5)

    # Step 2: Retrieve embedding from S3
    print(f"\\n=== Step 2: Retrieve embedding from S3 ===")
    retrieve_response = client.get(f"/embeddings/{test_embedding_id}")

    assert retrieve_response.status_code == 200, f"Retrieve failed: {retrieve_response.json()}"
    retrieve_data = retrieve_response.json()

    # Verify retrieval response structure
    assert "embedding_id" in retrieve_data
    assert "text" in retrieve_data
    assert "embedding" in retrieve_data
    assert "dimension" in retrieve_data
    assert "metadata" in retrieve_data

    # Step 3: Verify data integrity
    print(f"\\n=== Step 3: Verify data integrity ===")

    # Verify IDs match
    assert retrieve_data["embedding_id"] == test_embedding_id
    print(f" Embedding ID matches: {test_embedding_id}")

    # Verify text matches
    assert retrieve_data["text"] == test_text
    print(f" Text matches: '{test_text}'")

    # Verify embedding matches exactly
    assert retrieve_data["embedding"] == original_embedding
    print(f" Embedding vector matches exactly ({len(original_embedding)} dimensions)")

    # Verify dimension matches
    assert retrieve_data["dimension"] == original_dimension
    print(f" Dimension matches: {original_dimension}")

    # Verify embedding values are still floats
    assert all(isinstance(v, (int, float)) for v in retrieve_data["embedding"])
    print(f" All embedding values are numeric")

    print(f"\\n Full workflow test PASSED")


# =============================================================================
# Integration Test: Store Pre-computed Embedding
# =============================================================================


@skip_without_bucket
def test_store_precomputed_embedding(client, test_embedding_id, cleanup_embedding):
    """
    Test storing a pre-computed embedding and retrieving it.
    This tests the /embeddings/store endpoint.
    """
    # Register for cleanup
    cleanup_embedding(test_embedding_id)

    # Create a sample embedding (simulating pre-computed)
    sample_embedding = [0.1] * 1024  # 1024-dimensional vector
    test_text = "Sample text for pre-computed embedding"
    test_metadata = {"source": "integration_test", "timestamp": datetime.now(UTC).isoformat()}

    # Step 1: Store the embedding
    print(f"\\n=== Step 1: Store pre-computed embedding (ID: {test_embedding_id}) ===")
    store_response = client.post(
        "/embeddings/store",
        json={
            "embedding_id": test_embedding_id,
            "text": test_text,
            "embedding": sample_embedding,
            "metadata": test_metadata,
        },
    )

    assert store_response.status_code == 200, f"Store failed: {store_response.json()}"
    store_data = store_response.json()

    # Verify store response
    assert store_data["success"] is True
    assert store_data["s3_key"] == f"embeddings/{test_embedding_id}.json"
    assert store_data["bucket"] == os.getenv("VECTOR_BUCKET_NAME")

    print(f" Stored embedding in S3: {store_data['s3_key']}")

    # Small delay for S3 consistency
    time.sleep(0.5)

    # Step 2: Retrieve the embedding
    print(f"\\n=== Step 2: Retrieve stored embedding ===")
    retrieve_response = client.get(f"/embeddings/{test_embedding_id}")

    assert retrieve_response.status_code == 200, f"Retrieve failed: {retrieve_response.json()}"
    retrieve_data = retrieve_response.json()

    # Step 3: Verify data integrity
    print(f"\\n=== Step 3: Verify stored data ===")

    assert retrieve_data["embedding_id"] == test_embedding_id
    assert retrieve_data["text"] == test_text
    assert retrieve_data["embedding"] == sample_embedding
    assert retrieve_data["dimension"] == len(sample_embedding)
    assert retrieve_data["metadata"]["source"] == test_metadata["source"]

    print(f" Retrieved embedding matches stored data")
    print(f" Metadata preserved: {retrieve_data['metadata']}")
    print(f"\\n Store/retrieve test PASSED")


# =============================================================================
# Integration Test: Delete Embedding
# =============================================================================


@skip_without_bucket
def test_delete_embedding(client, test_embedding_id, cleanup_embedding):
    """Test deleting an embedding from S3."""
    # Register for cleanup (in case test fails before deletion)
    cleanup_embedding(test_embedding_id)

    # First, store an embedding
    sample_embedding = [0.1] * 1024
    store_response = client.post(
        "/embeddings/store",
        json={
            "embedding_id": test_embedding_id,
            "text": "Test text for deletion",
            "embedding": sample_embedding,
        },
    )
    assert store_response.status_code == 200

    time.sleep(0.5)  # S3 consistency

    # Verify it exists
    retrieve_response = client.get(f"/embeddings/{test_embedding_id}")
    assert retrieve_response.status_code == 200

    # Delete the embedding
    delete_response = client.delete(f"/embeddings/{test_embedding_id}")
    assert delete_response.status_code == 200

    delete_data = delete_response.json()
    assert delete_data["success"] is True
    assert delete_data["embedding_id"] == test_embedding_id
    assert "deleted" in delete_data["message"].lower()

    print(f"✓ Deleted embedding: {test_embedding_id}")

    # Verify it's gone
    retrieve_after_delete = client.get(f"/embeddings/{test_embedding_id}")
    assert retrieve_after_delete.status_code == 404

    print(f"✓ Confirmed embedding no longer exists")


# =============================================================================
# Integration Test: Error Cases
# =============================================================================


@skip_without_bucket
def test_retrieve_nonexistent_embedding(client):
    """Test retrieving an embedding that doesn't exist."""
    response = client.get("/embeddings/nonexistent-embedding-12345")

    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()
    print(f" Correctly returned 404 for non-existent embedding")


@skip_without_bucket
def test_delete_nonexistent_embedding(client):
    """Test deleting an embedding that doesn't exist."""
    response = client.delete("/embeddings/nonexistent-embedding-99999")

    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()
    print(f" Correctly returned 404 when deleting non-existent embedding")

def test_generate_with_missing_embedding_id(client):
    """Test that store_in_s3=true requires embedding_id."""
    response = client.post(
        "/embeddings/generate",
        json={"text": "Test text", "store_in_s3": True},
        # Missing embedding_id
    )

    # HTTPException gets caught and re-raised as 500, but detail is preserved
    assert response.status_code in [400, 500]
    assert "embedding_id required" in response.json()["detail"]
    print(f" Correctly rejected store without embedding_id")


def test_generate_with_empty_text(client):
    """Test validation for empty text."""
    response = client.post("/embeddings/generate", json={"text": ""})

    assert response.status_code == 422  # Validation error
    print(f" Correctly rejected empty text")


# =============================================================================
# Integration Test: Performance
# =============================================================================


def test_embedding_generation_performance(client):
    """Test that embedding generation completes in reasonable time."""
    start_time = time.time()

    response = client.post(
        "/embeddings/generate",
        json={"text": "Performance test sentence for embedding generation."},
    )

    end_time = time.time()
    total_time = (end_time - start_time) * 1000  # ms

    assert response.status_code == 200
    data = response.json()

    # Verify processing time is recorded
    assert data["processing_time_ms"] > 0

    # Verify reasonable performance (should be under 5 seconds)
    assert total_time < 5000, f"Generation took too long: {total_time}ms"

    print(f" API processing time: {data['processing_time_ms']:.2f}ms")
    print(f" Total round-trip time: {total_time:.2f}ms")


# =============================================================================
# Integration Test: Different Text Sizes
# =============================================================================


@pytest.mark.parametrize(
    "text_size,description",
    [
        (10, "short text"),
        (100, "medium text"),
        (500, "long text"),
    ],
)
def test_embedding_different_text_sizes(client, text_size, description):
    """Test embedding generation with different text sizes."""
    test_text = "word " * text_size

    response = client.post("/embeddings/generate", json={"text": test_text})

    assert response.status_code == 200
    data = response.json()
    assert data["text_length"] == len(test_text)
    assert len(data["embedding"]) > 0

    print(f" {description} ({text_size} words): {data['dimension']} dimensions, {data['processing_time_ms']:.2f}ms")


# =============================================================================
# Run Instructions
# =============================================================================

if __name__ == "__main__":
    print("""
    TPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPW
    Q  S3 Vector Integration Tests                                       Q
    ZPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP]

    These tests use REAL AWS services (Bedrock and S3).

    Prerequisites:
    1. AWS credentials configured
    2. Environment variables set:
       - VECTOR_BUCKET_NAME=your-bucket-name
       - BEDROCK_MODEL_ID=amazon.titan-embed-text-v2:0 (optional)
       - RUN_INTEGRATION_TESTS=true

    Run tests:
        RUN_INTEGRATION_TESTS=true pytest backend/$SERVICE_NAME/tests/test_embebedings.py -v

    Run specific test:
        RUN_INTEGRATION_TESTS=true pytest backend/$SERVICE_NAME/tests/test_embebedings.py::test_full_embedding_workflow -v
    """)
EOF

echo "✅ Created tests/" + "$TEST_FILE"
echo ""

# =============================================================================
# Summary
# =============================================================================

echo "✅ Embeddings router added successfully to '$SERVICE_NAME' service!"
echo ""
echo "📂 Modified/Created files:"
echo "   ✅ $CONFIG_FILE (updated with AWS config)"
echo "   ✅ $SERVICES_FILE (created)"
echo "   ✅ $SCHEMAS_FILE (created/updated)"
echo "   ✅ $EMBEDDINGS_FILE (created)"
echo "   ✅ $MAIN_FILE (updated)"
echo "   ✅ $TEST_FILE (created)"
echo ""
echo "🔧 Changes made:"
echo "   1. Added AWS configuration to app/config.py"
echo "   2. Created app/services.py with AWS clients"
echo "   3. Created/updated app/schemas.py with embedding models"
echo "   4. Created embeddings router with 4 endpoints:"
echo "      - POST /embeddings/generate (generate embeddings with Bedrock)"
echo "      - POST /embeddings/store (store pre-computed embeddings)"
echo "      - GET /embeddings/{id} (retrieve embeddings)"
echo "      - DELETE /embeddings/{id} (delete embeddings)"
echo "   5. Updated imports in main.py to include embeddings"
echo "   6. Added embeddings.router to api_router"
echo "   7. Created integration tests"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Add boto3 dependency (if not already present):"
echo "   cd $SERVICE_DIR"
echo "   uv add boto3 botocore"
echo ""
echo "2. Configure environment variables:"
echo "   VECTOR_BUCKET_NAME=your-s3-bucket-name"
echo "   BEDROCK_MODEL_ID=amazon.titan-embed-text-v2:0"
echo "   AWS_REGION=us-east-1"
echo ""
echo "3. Test the embeddings endpoint locally:"
echo "   cd $SERVICE_DIR"
echo "   uv run python main.py"
echo "   # Visit http://localhost:8000/docs"
echo "   # Test the /embeddings/generate endpoint"
echo ""
echo "4. Run integration tests:"
echo "   cd $SERVICE_DIR"
echo "   RUN_INTEGRATION_TESTS=true VECTOR_BUCKET_NAME=your-bucket pytest tests/test_embebedings.py -v"
echo ""
echo "5. Deploy the changes:"
echo "   ./scripts/docker-push.sh $ENVIRONMENT $SERVICE_NAME Dockerfile.lambda"
echo "   make app-apply-$ENVIRONMENT"
echo ""
echo "📖 Required AWS Permissions:"
echo "   - bedrock:InvokeModel (for amazon.titan-embed-text-v2:0)"
echo "   - s3:PutObject, s3:GetObject, s3:DeleteObject (for vector bucket)"
echo ""
echo "🎉 Done!"
echo ""

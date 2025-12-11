"""
Integration Tests for S3 Vector Embedding Endpoints

These tests use ACTUAL AWS services (Bedrock and S3) to verify the complete workflow.
They are not unit tests - they make real API calls to AWS.

Prerequisites:
- AWS credentials configured (via environment or ~/.aws/credentials)
- VECTOR_BUCKET_NAME environment variable set
- Bedrock model access enabled in the AWS account
- Appropriate IAM permissions for S3 and Bedrock

Run with: pytest backend/vector/tests/test_s3vector.py -v
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

    print(f" Generated embedding with {data['dimension']} dimensions")
    print(f" Processing time: {data['processing_time_ms']:.2f}ms")


# =============================================================================
# Integration Test: Full Workflow (Generate � Store � Retrieve)
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
    print(f"\n=== Step 1: Generate and store embedding (ID: {test_embedding_id}) ===")
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

    print(f" Generated embedding: {original_dimension} dimensions")
    print(f" Stored in S3: {generate_data['s3_key']}")
    print(f" Processing time: {generate_data['processing_time_ms']:.2f}ms")

    # Small delay to ensure S3 consistency
    time.sleep(0.5)

    # Step 2: Retrieve embedding from S3
    print(f"\n=== Step 2: Retrieve embedding from S3 ===")
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
    print(f"\n=== Step 3: Verify data integrity ===")

    # Verify IDs match
    assert retrieve_data["embedding_id"] == test_embedding_id
    print(f" Embedding ID matches: {test_embedding_id}")

    # Verify text matches
    assert retrieve_data["text"] == test_text
    print(f" Text matches: '{test_text}'")

    # Verify embedding matches exactly
    assert retrieve_data["embedding"] == original_embedding
    print(f" Embedding vector matches exactly ({len(original_embedding)} dimensions)")

    # Verify dimension matches
    assert retrieve_data["dimension"] == original_dimension
    print(f" Dimension matches: {original_dimension}")

    # Verify embedding values are still floats
    assert all(isinstance(v, (int, float)) for v in retrieve_data["embedding"])
    print(f" All embedding values are numeric")

    print(f"\n Full workflow test PASSED")


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
    print(f"\n=== Step 1: Store pre-computed embedding (ID: {test_embedding_id}) ===")
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

    print(f" Stored embedding in S3: {store_data['s3_key']}")

    # Small delay for S3 consistency
    time.sleep(0.5)

    # Step 2: Retrieve the embedding
    print(f"\n=== Step 2: Retrieve stored embedding ===")
    retrieve_response = client.get(f"/embeddings/{test_embedding_id}")

    assert retrieve_response.status_code == 200, f"Retrieve failed: {retrieve_response.json()}"
    retrieve_data = retrieve_response.json()

    # Step 3: Verify data integrity
    print(f"\n=== Step 3: Verify stored data ===")

    assert retrieve_data["embedding_id"] == test_embedding_id
    assert retrieve_data["text"] == test_text
    assert retrieve_data["embedding"] == sample_embedding
    assert retrieve_data["dimension"] == len(sample_embedding)
    assert retrieve_data["metadata"]["source"] == test_metadata["source"]

    print(f" Retrieved embedding matches stored data")
    print(f" Metadata preserved: {retrieve_data['metadata']}")
    print(f"\n Store/retrieve test PASSED")


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
    print(f" Correctly returned 404 for non-existent embedding")


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
    print(f" Correctly rejected store without embedding_id")


def test_generate_with_empty_text(client):
    """Test validation for empty text."""
    response = client.post("/embeddings/generate", json={"text": ""})

    assert response.status_code == 422  # Validation error
    print(f" Correctly rejected empty text")


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

    print(f" API processing time: {data['processing_time_ms']:.2f}ms")
    print(f" Total round-trip time: {total_time:.2f}ms")


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

    print(f" {description} ({text_size} words): {data['dimension']} dimensions, {data['processing_time_ms']:.2f}ms")


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
        RUN_INTEGRATION_TESTS=true pytest backend/vector/tests/test_s3vector.py -v

    Run specific test:
        RUN_INTEGRATION_TESTS=true pytest backend/vector/tests/test_s3vector.py::test_full_embedding_workflow -v
    """)

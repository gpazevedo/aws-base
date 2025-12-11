# vector Service

S3 Vector Embeddings Service - Generate and store vector embeddings using Amazon Bedrock and S3

## Quick Start

### Development

```bash
# Install dependencies
uv sync

# Run development server
uv run python main.py

# Visit http://localhost:8000
# API docs: http://localhost:8000/docs
```

### Testing

```bash
# Run tests
uv run pytest

# Run with coverage
uv run pytest --cov
```

## API Endpoints

### Standard Endpoints

- `GET /health` - Health check
- `GET /status` - Service status
- `GET /` - Root endpoint

### Embedding Endpoints

- `POST /embeddings/generate` - Generate embeddings using Amazon Bedrock
- `POST /embeddings/store` - Store pre-computed embeddings in S3
- `GET /embeddings/{id}` - Retrieve embedding from S3
- `DELETE /embeddings/{id}` - Delete embedding from S3

## Environment Variables

See `.env.example` for all available environment variables.

### Required Variables

- `SERVICE_NAME` - Service identifier
- `ENVIRONMENT` - Environment (dev, test, prod)
- `PROJECT_NAME` - Project name (set by Terraform)
- `API_GATEWAY_URL` - API Gateway URL (set by Terraform)

### S3 Vector Storage Variables

- `VECTOR_BUCKET_NAME` - S3 bucket for storing embeddings (set by Terraform)
- `BEDROCK_MODEL_ID` - Amazon Bedrock model ID (default: `amazon.titan-embed-text-v2:0`)
- `AWS_REGION` - AWS region (default: `us-east-1`)

## Deployment

```bash
# Build and push Docker image
# The script automatically handles CodeArtifact authentication
./scripts/docker-push.sh dev vector Dockerfile.lambda

# Deploy infrastructure
make app-init-dev app-apply-dev
```

**Note:** The build script automatically detects and configures CodeArtifact authentication when needed.

## Using agsys-common Library

This service uses the agsys-common library from CodeArtifact for:
- ✅ Structured logging (`configure_logging`, `get_logger`)
- ✅ OpenTelemetry tracing (`configure_tracing`)
- ✅ Request logging middleware (`LoggingMiddleware`)
- ✅ Health check utilities (`health_check_simple`)
- ✅ Inter-service API calls (`ServiceAPIClient`)

The library is installed from AWS CodeArtifact during build.

See [docs/SHARED-LIBRARY.md](../../docs/SHARED-LIBRARY.md) for details.

## Inter-Service Communication

```python
from shared import ServiceAPIClient, get_service_url

async with ServiceAPIClient(service_name="vector") as client:
    url = get_service_url("other-service")
    response = await client.get(f"{url}/endpoint")
```

See [docs/API-KEYS-QUICKSTART.md](../../docs/API-KEYS-QUICKSTART.md) for API key setup.

## S3 Vector Embeddings

This service provides endpoints for generating and managing vector embeddings using Amazon Bedrock and S3.

### Features

- ✅ Generate embeddings using Amazon Bedrock Titan Embed Text v2
- ✅ Store embeddings in S3 with metadata
- ✅ Retrieve embeddings by ID
- ✅ Delete embeddings from S3
- ✅ 1024-dimensional embeddings
- ✅ Automatic S3 bucket configuration via Terraform

### Example Usage

**Generate and store embedding:**

```bash
curl -X POST "https://api-url/embeddings/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "This is a test sentence",
    "store_in_s3": true,
    "embedding_id": "doc-123"
  }'
```

**Retrieve embedding:**

```bash
curl "https://api-url/embeddings/doc-123"
```

**Delete embedding:**

```bash
curl -X DELETE "https://api-url/embeddings/doc-123"
```

### Integration Tests

The service includes comprehensive integration tests that use real AWS services (Bedrock and S3).

See [README_TESTS.md](README_TESTS.md) for:

- ✅ 13 integration tests covering all workflows
- ✅ Bedrock-only tests (no S3 bucket required)
- ✅ Full S3 workflow tests (with bucket configured)
- ✅ Performance testing
- ✅ Error handling validation

**Run tests:**

```bash
# Run Bedrock-only tests (no S3 bucket required)
RUN_INTEGRATION_TESTS=true uv run pytest tests/test_s3vector.py -v

# Run all tests including S3 tests
RUN_INTEGRATION_TESTS=true \
VECTOR_BUCKET_NAME=your-bucket-name \
uv run pytest tests/test_s3vector.py -v
```

## Documentation

- [README_TESTS.md](README_TESTS.md) - Integration test documentation
- [docs/S3-VECTOR-STORAGE.md](../../docs/S3-VECTOR-STORAGE.md) - S3 vector storage setup guide
- [docs/CREATE-SERVICE-QUICKSTART.md](../../docs/CREATE-SERVICE-QUICKSTART.md) - Service creation guide

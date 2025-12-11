# Create Service Quick Start

Create a complete Lambda or App Runner service in 30 seconds

---

## The Fast Way

### Lambda Service (for APIs, event processing, scheduled tasks)

```bash
./scripts/create-lambda-service.sh myservice "My awesome service"
```

### App Runner Service (for long-running web apps, high concurrency)

```bash
./scripts/create-apprunner-service.sh web "Web service"
```

That's it! Everything is set up automatically.

## What Gets Created

Both scripts create similar structures with deployment-specific differences.

### Lambda Service Structure

```text
backend/myservice/
├── main.py                 # FastAPI app with Mangum for Lambda
├── pyproject.toml          # uv project configuration
├── uv.lock                 # Dependency lock file
├── .env.example            # Environment variables template
├── .gitignore              # Git ignore rules
├── Dockerfile.lambda       # Lambda container image
├── README.md               # Service documentation
├── pytest.ini              # Test configuration
└── tests/
    ├── __init__.py
    └── test_main.py        # Basic tests
```

### App Runner Service Structure

```text
backend/web/
├── main.py                 # FastAPI app (port 8080)
├── pyproject.toml          # uv project configuration
├── uv.lock                 # Dependency lock file
├── .env.example            # Environment variables template
├── .gitignore              # Git ignore rules
├── Dockerfile.apprunner    # App Runner container image with ADOT
├── README.md               # Service documentation
├── pytest.ini              # Test configuration
└── tests/
    ├── __init__.py
    └── test_main.py        # Basic tests
```

### Terraform Configuration (prompted)

**Lambda:**

```text
terraform/
├── lambda-myservice.tf     # Service infrastructure
└── api-gateway.tf          # Updated with integration
```

**App Runner:**

```text
terraform/
├── apprunner-web.tf        # Service infrastructure
└── api-gateway.tf          # Updated with integration (optional)
```

### Dependencies (automatically installed)

**Common dependencies:**

- ✅ `agsys-common>=0.0.1,<1.0.0` (from CodeArtifact)
- ✅ `fastapi` + `uvicorn`
- ✅ `boto3` (AWS SDK)
- ✅ `pydantic` + `pydantic-settings`
- ✅ `httpx` (async HTTP client)
- ✅ `structlog` (structured logging)
- ✅ OpenTelemetry packages
- ✅ `pytest` + `pytest-asyncio` (dev)

**Lambda-specific:**

- ✅ `mangum` (ASGI adapter for Lambda)

**App Runner-specific:**

- ✅ `python-dotenv` (environment management)

## Immediate Next Steps

### Lambda Service

#### 1. Start Lambda Development

```bash
cd backend/myservice
uv run python main.py
```

Visit:

- <http://localhost:8000> - Service root
- <http://localhost:8000/docs> - Interactive API docs
- <http://localhost:8000/health> - Health check

#### 2. Run Lambda Tests

```bash
cd backend/myservice
uv run pytest
```

#### 3. Deploy Lambda Service

```bash
# Build and push Docker image (automatically handles CodeArtifact authentication)
./scripts/docker-push.sh dev myservice Dockerfile.lambda

# Deploy infrastructure
make app-init-dev app-apply-dev
```

### App Runner Service

#### 1. Start App Runner Development

```bash
cd backend/web
uv run python main.py
```

Visit:

- <http://localhost:8080> - Service root (note: port 8080)
- <http://localhost:8080/docs> - Interactive API docs
- <http://localhost:8080/health> - Health check

#### 2. Run App Runner Tests

```bash
cd backend/web
uv run pytest
```

#### 3. Deploy App Runner Service

```bash
# Build and push Docker image (automatically handles CodeArtifact authentication)
./scripts/docker-push.sh dev web Dockerfile.apprunner

# Deploy infrastructure
make app-init-dev app-apply-dev
```

## What's Already Configured

### ✅ agsys-common Library from CodeArtifact

The service automatically includes the `agsys-common` library from your private AWS CodeArtifact repository:

- **Package name**: `agsys-common` (published version of the shared library)
- **Version constraint**: `>=0.0.1,<1.0.0`
- **Import path**: `from common import ...` (not `from shared`)
- **Authentication**: Automatic 12-hour tokens via `configure-codeartifact.sh`
- **Docker builds**: Automatic authentication via `docker-push.sh`

**Key features provided:**

- Structured logging (`configure_logging`, `get_logger`)
- OpenTelemetry tracing (`configure_tracing`)
- Request logging middleware (`LoggingMiddleware`)
- Health check utilities (`health_check_simple`)
- Inter-service API calls (`ServiceAPIClient`)

### ✅ Structured Logging

```python
logger.info("user_created", user_id=123, email="user@example.com")
```

### ✅ Health Checks

```python
# GET /health - Simple health check
# GET /status - Detailed status
```

### ✅ Request Logging

Automatic logging of all HTTP requests with:

- Request ID
- Method, path, status
- Duration
- Client info

### ✅ OpenTelemetry Tracing

```bash
# Enable with environment variable
ENABLE_TRACING=true
```

### ✅ Inter-Service Communication

```python
from common import ServiceAPIClient, get_service_url

async with ServiceAPIClient(service_name="myservice") as client:
    url = get_service_url("other-service")
    response = await client.get(f"{url}/endpoint")
```

### ✅ Error Handling

```python
from common import get_logger

logger = get_logger(__name__)

try:
    # Your code
    pass
except Exception as e:
    logger.error("operation_failed", error=str(e), exc_info=True)
    raise
```

## Usage Examples

### Lambda Service Examples

**Basic service:**

```bash
./scripts/create-lambda-service.sh payments
```

Creates: `backend/payments/`

**With description:**

```bash
./scripts/create-lambda-service.sh notifications "Email and SMS notification service"
```

**Skip Terraform setup:**

```bash
./scripts/create-lambda-service.sh worker
# Answer 'n' when prompted for Terraform setup
```

### App Runner Service Examples

**Basic service:**

```bash
./scripts/create-apprunner-service.sh web
```

Creates: `backend/web/`

**With description:**

```bash
./scripts/create-apprunner-service.sh admin "Admin dashboard with real-time updates"
```

**Skip Terraform setup:**

```bash
./scripts/create-apprunner-service.sh portal
# Answer 'n' when prompted for Terraform setup
```

## File Contents

### main.py

The generated `main.py` includes:

1. **Configuration** - Environment variables, logging, tracing
2. **FastAPI App** - With lifecycle management
3. **Health Endpoints** - `/health` and `/status`
4. **Lambda Handler** - For AWS Lambda deployment
5. **Dev Server** - For local development

### Example Endpoint

Add business logic easily:

```python
from pydantic import BaseModel

class ProcessRequest(BaseModel):
    data: str

@app.post("/process")
async def process_data(request: ProcessRequest):
    logger.info("processing_data", data=request.data)

    # Your business logic
    result = do_something(request.data)

    return {"status": "success", "result": result}
```

### tests/test_main.py

Basic tests are included:

```python
def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
```

Add more tests as needed!

## Customization

### Environment Variables

Edit `.env.example`:

```bash
# Your custom variables
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
EXTERNAL_API_KEY=...
```

### Dependencies

Add more packages:

```bash
cd backend/myservice

# Production dependency
uv add sqlalchemy

# Development dependency
uv add --dev black
```

### Dockerfile

Customize `Dockerfile.lambda` for your needs:

```dockerfile
# Add system packages
RUN yum install -y your-package

# Add build steps
RUN uv run python scripts/build.py
```

## Advanced Features

### Call Other Services

```python
from common import ServiceAPIClient

async def call_api_service():
    async with ServiceAPIClient(service_name="myservice") as client:
        # API key automatically injected
        response = await client.get(
            "https://api-gateway/other-service/endpoint"
        )
        return response.json()
```

### Custom Logging

```python
from common import get_logger

logger = get_logger(__name__)

# Structured logging
logger.info("order_created",
    order_id=123,
    user_id=456,
    total=99.99,
    items=3
)

# With context
logger.bind(request_id="abc123").info("processing_request")
```

### Distributed Tracing

```python
from common import configure_tracing

# Enable tracing at startup
configure_tracing(
    service_name="myservice",
    service_version="1.0.0",
    environment="production"
)

# Traces are automatically collected for:
# - HTTP requests (FastAPI)
# - Database queries (if using supported drivers)
# - Inter-service calls (ServiceAPIClient)
```

## Troubleshooting

### "uv: command not found"

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### "Service already exists"

The script checks if the directory exists and will abort if found.

### Tests failing

```bash
cd backend/myservice

# Check dependencies
uv sync

# Run with verbose output
uv run pytest -v

# Check specific test
uv run pytest tests/test_main.py::test_health_check -v
```

### Import errors

```bash
# Verify CodeArtifact is configured
cd backend/myservice

# Check if agsys-common is installed
uv pip list | grep agsys-common

# If missing, reinstall
uv add "agsys-common>=0.0.1,<1.0.0"
```

### CodeArtifact authentication issues

```bash
# Configure CodeArtifact authentication (from project root)
source <(./scripts/configure-codeartifact.sh)

# Verify configuration
echo $UV_INDEX_URL

# If the token expired (12-hour lifetime), reconfigure
./scripts/configure-codeartifact.sh
```

## What This Script Does

1. ✅ Validates service name
2. ✅ Creates service directory
3. ✅ Initializes uv project
4. ✅ Configures CodeArtifact authentication
5. ✅ Installs agsys-common from CodeArtifact
6. ✅ Adds all dependencies
7. ✅ Creates FastAPI application
8. ✅ Sets up tests
9. ✅ Creates Dockerfile with CodeArtifact support
10. ✅ Generates documentation
11. ✅ (Optional) Runs Terraform setup

**Total time: ~30 seconds**

## Lambda vs App Runner - Which to Choose?

| Feature | Lambda | App Runner |
|---------|--------|------------|
| **Best For** | APIs, event processing, scheduled tasks | Long-running apps, WebSockets, high concurrency |
| **Port** | Not needed (API Gateway invokes) | Port 8080 (mandatory) |
| **Cold Start** | Yes (optimized with provisioned concurrency) | No (always warm) |
| **Max Timeout** | 15 minutes | No limit |
| **Scaling** | Automatic (0 to thousands) | Configurable (min/max instances) |
| **Cost Model** | Pay per request | Pay for running instances |
| **ADOT Setup** | Lambda Layer (automatic) | Container installation (manual) |
| **Architecture** | arm64 (Graviton2) | amd64 (x86_64) |

### When to Use Lambda

```bash
./scripts/create-lambda-service.sh api "REST API service"
./scripts/create-lambda-service.sh processor "Event processor"
./scripts/create-lambda-service.sh scheduler "Scheduled job"
```

### When to Use App Runner

```bash
./scripts/create-apprunner-service.sh web "Web frontend"
./scripts/create-apprunner-service.sh admin "Admin dashboard"
./scripts/create-apprunner-service.sh websocket "WebSocket server"
```

## Time Comparison

### Before (Manual)

1. Create directory ⏱️ 1 min
2. Set up uv project ⏱️ 2 min
3. Install dependencies ⏱️ 3 min
4. Copy boilerplate code ⏱️ 5 min
5. Set up logging/tracing ⏱️ 5 min
6. Create tests ⏱️ 3 min
7. Write Dockerfile ⏱️ 5 min
8. Configure Terraform ⏱️ 10 min

**Total: ~35 minutes**

### After (Automated)

```bash
# Lambda service
./scripts/create-lambda-service.sh myservice

# Or App Runner service
./scripts/create-apprunner-service.sh web
```

**Total: ~30 seconds** ⚡

## S3 Vector Storage Integration

Both Lambda and App Runner services can be automatically configured with S3 vector storage and Amazon Bedrock embeddings support.

### Prerequisites

Enable S3 vector storage in bootstrap:

```bash
# Edit bootstrap/terraform.tfvars
enable_s3vector = true
bucket_suffixes = ["vector-embeddings"]  # Add more as needed

# Apply bootstrap changes
cd bootstrap
terraform apply
```

### Lambda Service with S3 Vector Storage

When creating the Terraform configuration, specify which buckets to use:

```bash
# During service creation, when prompted for Terraform setup
./scripts/create-lambda-service.sh embeddings "Embedding generation service"
# Answer 'y' to Terraform setup

# The setup script calls:
./scripts/setup-terraform-lambda.sh embeddings true "vector-embeddings"
```

**Manual Terraform setup with S3 vectors:**

```bash
# Single bucket
./scripts/setup-terraform-lambda.sh myservice true "vector-embeddings"

# Multiple buckets
./scripts/setup-terraform-lambda.sh myservice true "vector-embeddings,vector-cache"
```

**What gets configured:**

- ✅ IAM policies for S3 vector access
- ✅ IAM policies for Bedrock invocation
- ✅ Environment variables: `VECTOR_BUCKET_NAME`, `BEDROCK_MODEL_ID`
- ✅ Bootstrap remote state data source

### App Runner Service with S3 Vector Storage

```bash
# During service creation, when prompted for Terraform setup
./scripts/create-apprunner-service.sh search "Vector search service"
# Answer 'y' to Terraform setup

# The setup script calls:
./scripts/setup-terraform-apprunner.sh search "vector-embeddings"
```

**Manual Terraform setup with S3 vectors:**

```bash
# Single bucket
./scripts/setup-terraform-apprunner.sh web "vector-embeddings"

# Multiple buckets
./scripts/setup-apprunner.sh web "vector-embeddings,vector-cache,vector-docs"
```

**What gets configured:**

- ✅ IAM policies for S3 vector access
- ✅ IAM policies for Bedrock invocation
- ✅ Environment variables (single bucket): `VECTOR_BUCKET_NAME`, `BEDROCK_MODEL_ID`
- ✅ Environment variables (multiple buckets): `VECTOR_EMBEDDINGS_BUCKET`, `VECTOR_CACHE_BUCKET`, etc.
- ✅ Bootstrap remote state data source

### Environment Variables

**Single bucket configuration:**

```python
VECTOR_BUCKET_NAME = "gustavo-vector-embeddings"
BEDROCK_MODEL_ID = "amazon.titan-embed-text-v2:0"
```

**Multiple buckets configuration:**

```python
VECTOR_EMBEDDINGS_BUCKET = "gustavo-vector-embeddings"
VECTOR_CACHE_BUCKET = "gustavo-vector-cache"
VECTOR_DOCS_BUCKET = "gustavo-vector-docs"
BEDROCK_MODEL_ID = "amazon.titan-embed-text-v2:0"
```

### Add Embedding Endpoints to Your Service

After creating your service with S3 vector support, add the embedding functionality to your `main.py`.

#### Step 1: Update Imports

Add these imports at the top of your `main.py`:

```python
import json
from datetime import UTC, datetime
from typing import Any

import boto3
from botocore.exceptions import ClientError
from pydantic import BaseModel, Field
```

#### Step 2: Add Configuration Variables

After the existing environment variables section:

```python
# S3 Vector configuration (from Terraform environment variables)
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "amazon.titan-embed-text-v2:0")
VECTOR_BUCKET_NAME = os.getenv("VECTOR_BUCKET_NAME", "")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
```

#### Step 3: Add AWS Clients

After the logging setup, add lazy-loaded AWS clients:

```python
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
```

#### Step 4: Add Pydantic Models

```python
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
```

#### Step 5: Add Embedding Endpoints

Add these three endpoints (you can add them after the existing router setup):

```python
@app.post("/embeddings/generate", response_model=EmbeddingResponse, tags=["Embeddings"])
async def generate_embedding(request: EmbeddingRequest) -> EmbeddingResponse:
    """Generate embedding using Amazon Bedrock Titan model."""
    logger.info("generating_embedding", text_length=len(request.text), store_in_s3=request.store_in_s3)
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

        # Optionally store in S3
        s3_key = None
        if request.store_in_s3:
            if not request.embedding_id:
                raise HTTPException(status_code=400, detail="embedding_id required when store_in_s3=true")

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
        raise HTTPException(status_code=500, detail=f"Failed to generate embedding: {str(e)}") from e


@app.post("/embeddings/store", response_model=StoreEmbeddingResponse, tags=["Embeddings"])
async def store_embedding(request: StoreEmbeddingRequest) -> StoreEmbeddingResponse:
    """Store embedding in S3."""
    if not VECTOR_BUCKET_NAME:
        raise HTTPException(status_code=503, detail="S3 bucket not configured")

    logger.info("storing_embedding", embedding_id=request.embedding_id, dimension=len(request.embedding))

    try:
        s3_key = f"embeddings/{request.embedding_id}.json"
        await store_embedding_in_s3(request.embedding_id, request.text, request.embedding, request.metadata or {})
        logger.info("embedding_stored", s3_key=s3_key)

        return StoreEmbeddingResponse(success=True, s3_key=s3_key, bucket=VECTOR_BUCKET_NAME)

    except Exception as e:
        logger.exception("embedding_store_failed", embedding_id=request.embedding_id, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to store embedding: {str(e)}") from e


@app.get("/embeddings/{embedding_id}", response_model=RetrieveEmbeddingResponse, tags=["Embeddings"])
async def retrieve_embedding(embedding_id: str) -> RetrieveEmbeddingResponse:
    """Retrieve embedding from S3."""
    if not VECTOR_BUCKET_NAME:
        raise HTTPException(status_code=503, detail="S3 bucket not configured")

    logger.info("retrieving_embedding", embedding_id=embedding_id)

    try:
        s3_key = f"embeddings/{embedding_id}.json"
        response = aws_clients.s3.get_object(Bucket=VECTOR_BUCKET_NAME, Key=s3_key)
        data = json.loads(response["Body"].read())

        logger.info("embedding_retrieved", embedding_id=embedding_id, dimension=len(data["embedding"]))

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
        raise HTTPException(status_code=500, detail=f"Failed to retrieve embedding: {str(e)}") from e


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
```

#### Complete Example

See [backend/vector/main.py](../backend/vector/main.py) for a complete working implementation created with:

```bash
./scripts/create-lambda-service.sh vector "S3Vector service"
# Then added the S3 vector embedding endpoints
```

**Additional references:**

- [S3-VECTOR-STORAGE.md](S3-VECTOR-STORAGE.md) - Full S3 vector setup guide
- [backend/s3vector/main.py](../backend/s3vector/main.py) - Original reference implementation

## See Also

- [SHARED-LIBRARY.md](SHARED-LIBRARY.md) - Shared library documentation
- [API-KEYS-QUICKSTART.md](API-KEYS-QUICKSTART.md) - API key setup
- [S3-VECTOR-STORAGE.md](S3-VECTOR-STORAGE.md) - S3 vector storage guide
- [ADDING-SERVICES.md](ADDING-SERVICES.md) - Manual service setup
- [INSTALLATION.md](INSTALLATION.md) - Development environment setup

---

**Ready to build?** Run the script and start coding! 🚀

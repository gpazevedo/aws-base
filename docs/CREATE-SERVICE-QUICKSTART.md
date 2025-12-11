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

- ✅ `shared` library (editable mode)
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
# Build Docker image (arm64 for Lambda)
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
# Build Docker image (amd64 for App Runner)
./scripts/docker-push.sh dev web Dockerfile.apprunner

# Deploy infrastructure
make app-init-dev app-apply-dev
```

## What's Already Configured

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
from shared import ServiceAPIClient, get_service_url

async with ServiceAPIClient(service_name="myservice") as client:
    url = get_service_url("other-service")
    response = await client.get(f"{url}/endpoint")
```

### ✅ Error Handling

```python
from shared import get_logger

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
from shared import ServiceAPIClient

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
from shared import get_logger

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
from shared import configure_tracing

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

### "Shared library not found"

Ensure `backend/shared/` exists. This should be part of your template.

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
# Reinstall shared library
cd backend/myservice
uv remove shared
uv add --editable ../shared
```

## What This Script Does

1. ✅ Validates service name
2. ✅ Creates service directory
3. ✅ Initializes uv project
4. ✅ Installs shared library (editable)
5. ✅ Adds all dependencies
6. ✅ Creates FastAPI application
7. ✅ Sets up tests
8. ✅ Creates Dockerfile
9. ✅ Generates documentation
10. ✅ (Optional) Runs Terraform setup

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

## See Also

- [SHARED-LIBRARY.md](SHARED-LIBRARY.md) - Shared library documentation
- [API-KEYS-QUICKSTART.md](API-KEYS-QUICKSTART.md) - API key setup
- [ADDING-SERVICES.md](ADDING-SERVICES.md) - Manual service setup
- [INSTALLATION.md](INSTALLATION.md) - Development environment setup

---

**Ready to build?** Run the script and start coding! 🚀

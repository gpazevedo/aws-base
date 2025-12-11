# Shared Library Documentation

**Version**: 1.0.0

Common code shared across all backend services (API, Runner, S3Vector, etc.).

---

## Quick Start

### Install

```bash
cd backend/your-service
uv add --editable ../shared
```

### Basic Usage

```python
from shared import configure_logging, get_logger, ServiceAPIClient

# Configure logging once at startup
configure_logging(log_level="INFO")
logger = get_logger(__name__)

# Use structured logging
logger.info("service_started", version="1.0.0")

# Call other services
client = ServiceAPIClient(service_name="api")
response = await client.get("https://api-gateway/runner/health")
```

---

## Modules

### 1. API Client (`api_client.py`)

**Inter-service communication with automatic API key injection**

```python
from shared import ServiceAPIClient, get_service_url

# Initialize client
client = ServiceAPIClient(service_name="api")

# Call another service
url = get_service_url("s3vector")
response = await client.post(
    f"{url}/embeddings/generate",
    json={"text": "hello"}
)

# Context manager (auto cleanup)
async with ServiceAPIClient(service_name="api") as client:
    response = await client.get(url)
```

**Features**:
- Auto-retrieves API key from Secrets Manager
- Caches API key for performance
- Injects `x-api-key` header automatically
- Supports GET, POST, PUT, DELETE

---

### 2. Logging (`logging.py`)

**Structured logging with structlog**

```python
from shared import configure_logging, get_logger

# Configure once at startup
configure_logging(
    log_level="INFO",
    format_json=True  # False for console-friendly output
)

# Get logger
logger = get_logger(__name__)

# Log with context
logger.info("request_received", method="GET", path="/health")
logger.error("database_error", error=str(e), retries=3)
```

**Output** (JSON):
```json
{"event": "request_received", "method": "GET", "path": "/health", "timestamp": "2025-12-06T10:30:00Z"}
```

---

### 3. Tracing (`tracing.py`)

**OpenTelemetry configuration**

```python
from shared import configure_tracing, get_tracer

# Configure at startup
configure_tracing(
    service_name="api",
    service_version="1.0.0",
    environment="dev",
    app=app  # Optional FastAPI app
)

# Get tracer
tracer = get_tracer(__name__)

# Create spans
with tracer.start_as_current_span("process_data"):
    # Your code here
    pass
```

**Features**:
- Auto-disabled in tests and Lambda (uses ADOT Layer)
- Instruments FastAPI and HTTPX automatically
- Sends traces to OTLP collector

---

### 4. Middleware (`middleware.py`)

**FastAPI middleware for request logging**

```python
from shared import LoggingMiddleware, logging_middleware

# Option 1: Class-based
app.add_middleware(LoggingMiddleware)

# Option 2: Function-based
@app.middleware("http")
async def log_requests(request, call_next):
    return await logging_middleware(request, call_next)
```

**Logs**:
- Request start (method, path, client IP)
- Request completion (status code, duration)
- Adds context to all logs during request

---

### 5. Models (`models.py`)

**Shared Pydantic models**

```python
from shared import HealthResponse, StatusResponse, ErrorResponse

# Health check
@app.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(
        status="healthy",
        timestamp="2025-12-06T10:30:00Z",
        uptime_seconds=123.45,
        version="1.0.0"
    )

# Status
@app.get("/liveness", response_model=StatusResponse)
async def liveness():
    return StatusResponse(status="alive")
```

**Available models**:
- `HealthResponse` - Health check data
- `StatusResponse` - Simple status
- `GreetingRequest/Response` - Greeting endpoints
- `ErrorResponse` - Error details
- `InterServiceResponse` - Inter-service call results
- `ServiceInfo` - Service metadata

---

### 6. Settings (`settings.py`)

**Base settings classes**

```python
from shared import BaseServiceSettings, BaseTracingSettings, BaseAWSSettings

# Option 1: Combine what you need
class MySettings(BaseServiceSettings, BaseTracingSettings):
    database_url: str = "postgresql://..."

# Option 2: Use everything
from shared import FullServiceSettings

class MySettings(FullServiceSettings):
    my_custom_field: str = "value"

# Use settings
settings = MySettings(
    service_name="api",
    service_version="1.0.0"
)
```

**Base fields**:
- `BaseServiceSettings`: service_name, service_version, environment, log_level, http_timeout
- `BaseTracingSettings`: enable_tracing, otlp_endpoint
- `BaseAWSSettings`: aws_region
- `FullServiceSettings`: All of the above

---

### 7. Health Checks (`health.py`)

**Health check utilities**

```python
from shared import health_check_simple, liveness_probe_simple, readiness_probe_simple
import time

START_TIME = time.time()

# Simple health check
@app.get("/health")
async def health():
    return await health_check_simple("1.0.0", START_TIME)

# Liveness
@app.get("/liveness")
async def liveness():
    return await liveness_probe_simple()

# Readiness
@app.get("/readiness")
async def readiness():
    return await readiness_probe_simple()
```

**Advanced** (with custom checks):
```python
from shared import create_readiness_endpoint

def check_database():
    return db.is_connected()

@app.get("/readiness")
async def readiness():
    return create_readiness_endpoint(check_database)()
```

---

## Complete Example

**Minimal service using shared library**:

```python
# service/main.py
import time
from fastapi import FastAPI
from shared import (
    configure_logging,
    configure_tracing,
    get_logger,
    LoggingMiddleware,
    health_check_simple,
    liveness_probe_simple,
    FullServiceSettings,
    ServiceAPIClient,
    get_service_url,
)

# Settings
class Settings(FullServiceSettings):
    pass

settings = Settings(service_name="api", service_version="1.0.0")
START_TIME = time.time()

# Configure logging and tracing
configure_logging(log_level=settings.log_level)
logger = get_logger(__name__)

# FastAPI app
app = FastAPI(title=f"{settings.service_name} Service")
app.add_middleware(LoggingMiddleware)

# Configure tracing after app creation
configure_tracing(
    service_name=settings.service_name,
    service_version=settings.service_version,
    environment=settings.environment,
    app=app,
)

# Health endpoints
@app.get("/health")
async def health():
    return await health_check_simple(settings.service_version, START_TIME)

@app.get("/liveness")
async def liveness():
    return await liveness_probe_simple()

# Business logic endpoints
client = ServiceAPIClient(service_name=settings.service_name)

@app.post("/generate-embedding")
async def generate_embedding(text: str):
    """Call s3vector service to generate embedding."""
    s3vector_url = get_service_url("s3vector")
    response = await client.post(
        f"{s3vector_url}/embeddings/generate",
        json={"text": text}
    )
    return response.json()

# Cleanup
@app.on_event("shutdown")
async def shutdown():
    await client.aclose()
```

---

## Environment Variables

Required for services using the shared library:

```bash
# Required for ServiceAPIClient
PROJECT_NAME=fin-advisor
ENVIRONMENT=dev
API_GATEWAY_URL=https://abc123.execute-api.us-east-1.amazonaws.com/dev

# Optional (have defaults)
LOG_LEVEL=INFO
AWS_REGION=us-east-1
ENABLE_TRACING=true
OTLP_ENDPOINT=http://localhost:4317
```

---

## Dependencies

Core dependencies (included in shared library):

```toml
# HTTP client
httpx>=0.27.0

# AWS SDK
boto3>=1.35.0
botocore>=1.35.0

# Data validation
pydantic>=2.9.0
pydantic-settings>=2.6.0

# Structured logging
structlog>=24.4.0

# OpenTelemetry
opentelemetry-api>=1.27.0
opentelemetry-sdk>=1.27.0
```

---

## File Structure

```
backend/shared/
├── shared/
│   ├── __init__.py          # Convenient imports
│   ├── api_client.py        # Inter-service communication
│   ├── logging.py           # Structured logging
│   ├── tracing.py           # OpenTelemetry setup
│   ├── middleware.py        # FastAPI middleware
│   ├── models.py            # Pydantic models
│   ├── settings.py          # Base settings classes
│   └── health.py            # Health check utilities
├── pyproject.toml           # Dependencies
└── README.md                # Basic info
```

---

## Migration Guide

### Before (without shared library)

```python
# 500+ lines of duplicated code in each service:
# - Logging configuration (~30 lines)
# - Tracing configuration (~70 lines)
# - Middleware (~30 lines)
# - Health checks (~60 lines)
# - Models (~50 lines)
# - Settings (~40 lines)
```

### After (with shared library)

```python
# ~150 lines of service-specific code
from shared import (
    configure_logging,
    configure_tracing,
    LoggingMiddleware,
    health_check_simple,
    FullServiceSettings,
)

# Use shared components
configure_logging()
configure_tracing(...)
app.add_middleware(LoggingMiddleware)
```

**Result**: ~70% code reduction per service

---

## Testing

```bash
cd backend/shared

# Run tests (when added)
uv run pytest

# Type checking
pyright shared/

# Import test
python -c "from shared import ServiceAPIClient; print('OK')"
```

---

## Related Documentation

- [PER-SERVICE-API-KEYS.md](PER-SERVICE-API-KEYS.md) - API key setup
- [API-KEYS-QUICKSTART.md](API-KEYS-QUICKSTART.md) - Quick reference
- [terraform/examples/service-api-key-iam.tf](../terraform/examples/service-api-key-iam.tf) - IAM examples
- [terraform/examples/service-environment-variables.tf](../terraform/examples/service-environment-variables.tf) - Env var examples

---

## Next Steps

1. ✅ Shared library implemented
2. ⏭️ Migrate existing services to use shared library
3. ⏭️ Add unit tests for shared library
4. ⏭️ Add more utility functions as needed

**Questions?** See examples in each module's docstrings or check existing services.

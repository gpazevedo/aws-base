# agsys-common

Common library for agsys backend services. **~70% code reduction per service.**

Published to AWS CodeArtifact for centralized dependency management.

## Installation

### From CodeArtifact (Production)

```bash
# Configure CodeArtifact authentication
source <(./scripts/configure-codeartifact.sh)

# Install the package
cd backend/your-service
uv add "agsys-common>=0.0.1,<1.0.0"
```

### Local Development (Editable)

For rapid development and testing local changes:

```bash
cd backend/your-service
uv add --editable ../../agsys/common
```

## Quick Start

```python
from common import (
    configure_logging,
    get_logger,
    ServiceAPIClient,
    health_check_simple,
)

# Logging
configure_logging(log_level="INFO")
logger = get_logger(__name__)
logger.info("service_started", version="1.0.0")

# Health check
@app.get("/health")
async def health():
    return await health_check_simple("1.0.0", START_TIME)

# Call other services
async with ServiceAPIClient(service_name="api") as client:
    response = await client.get(url)
```

## Modules

| Module | Purpose | Example |
|--------|---------|---------|
| `api_client` | Inter-service calls with auto API key | `ServiceAPIClient(service_name="api")` |
| `logging` | Structured logging | `configure_logging()` |
| `tracing` | OpenTelemetry setup | `configure_tracing(...)` |
| `middleware` | Request logging | `app.add_middleware(LoggingMiddleware)` |
| `models` | Pydantic models | `HealthResponse`, `StatusResponse` |
| `settings` | Base settings classes | `class Settings(FullServiceSettings)` |
| `health` | Health check utilities | `health_check_simple()` |

## Environment Variables

```bash
# Required for ServiceAPIClient
PROJECT_NAME=your-project
ENVIRONMENT=dev
API_GATEWAY_URL=https://...

# Optional
LOG_LEVEL=INFO
AWS_REGION=us-east-1
ENABLE_TRACING=true
```

## Documentation

See **[docs/SHARED-LIBRARY.md](../../docs/SHARED-LIBRARY.md)** for complete documentation with examples.

## What's Included

✅ API client with auto API key injection
✅ Structured logging (structlog)
✅ OpenTelemetry tracing
✅ FastAPI middleware
✅ Common Pydantic models
✅ Base settings classes
✅ Health check utilities

**Before**: 500+ lines of boilerplate per service
**After**: 150 lines of business logic

---

📖 **Full Docs**: [SHARED-LIBRARY.md](../../docs/SHARED-LIBRARY.md)
🔑 **API Keys**: [PER-SERVICE-API-KEYS.md](../../docs/PER-SERVICE-API-KEYS.md)

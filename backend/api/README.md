# api Service

api service

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

- `GET /health` - Health check
- `GET /status` - Service status
- `GET /` - Root endpoint

## Environment Variables

See `.env.example` for all available environment variables.

Required:
- `SERVICE_NAME` - Service identifier
- `ENVIRONMENT` - Environment (dev, test, prod)
- `PROJECT_NAME` - Project name (set by Terraform)
- `API_GATEWAY_URL` - API Gateway URL (set by Terraform)

## Deployment

```bash
# Build and push Docker image
# The script automatically handles CodeArtifact authentication
./scripts/docker-push.sh dev api Dockerfile.lambda

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

async with ServiceAPIClient(service_name="api") as client:
    url = get_service_url("other-service")
    response = await client.get(f"{url}/endpoint")
```

See [docs/API-KEYS-QUICKSTART.md](../../docs/API-KEYS-QUICKSTART.md) for API key setup.

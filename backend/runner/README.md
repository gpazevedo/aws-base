# AppRunner Service

A FastAPI-based service designed to run on AWS App Runner that demonstrates service-to-service communication by calling the API service.

## Features

- **Full FastAPI Implementation**: All standard endpoints including health checks, liveness, and readiness probes
- **Service-to-Service Communication**: Calls the API service health endpoint and returns the response
- **Async Support**: Uses uvicorn for proper async/await handling
- **Production Ready**: Includes comprehensive health checks, error handling, and OpenAPI documentation
- **Test Coverage**: 87.64% test coverage with pytest

## Endpoints

### Health Check Endpoints
- `GET /health` - Comprehensive health check with uptime and version info
- `GET /liveness` - Kubernetes-style liveness probe
- `GET /readiness` - Readiness probe that checks API service connectivity

### API Integration
- `GET /api-health` - Calls the API service `/health` endpoint and returns the response

### General Endpoints
- `GET /` - Root endpoint with welcome message
- `GET /greet?name=World` - Greeting endpoint (GET)
- `POST /greet` - Greeting endpoint (POST with JSON body)
- `GET /error` - Test error handling
- `GET /docs` - Swagger UI documentation
- `GET /redoc` - ReDoc documentation
- `GET /openapi.json` - OpenAPI schema

## Configuration

The service uses environment variables for configuration. Copy `.env.example` to `.env` and update:

```bash
# Required
API_SERVICE_URL=http://localhost:8000

# Optional (with defaults)
SERVICE_NAME=runner
SERVICE_VERSION=0.1.0
HTTP_TIMEOUT=30.0
HTTP_MAX_RETRIES=3
```

## Local Development

### Setup

```bash
# Install dependencies
uv sync

# Install with test dependencies
uv sync --extra test
```

### Run the Service

```bash
# Option 1: Using uv
uv run python main.py

# Option 2: Using uvicorn directly
uv run uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

The service will be available at `http://localhost:8080`

### Run Tests

```bash
# Run all tests
uv run pytest -v

# Run with coverage report
uv run pytest -v --cov=. --cov-report=term-missing
```

## Docker Deployment

Build and run using the AppRunner Dockerfile:

```bash
# Build for ARM64 (production) NOT AVAILABLE ON AWS
docker build --platform=linux/arm64 \
  --build-arg SERVICE_FOLDER=runner \
  -f ../Dockerfile.apprunner \
  -t runner:arm64 \
  ..

# Build for AMD64 (local testing)
docker build --platform=linux/amd64 \
  --build-arg SERVICE_FOLDER=runner \
  -f ../Dockerfile.apprunner \
  -t runner:amd64 \
  ..

# Run locally
docker run -p 8080:8080 \
  -e API_SERVICE_URL=http://host.docker.internal:8000 \
  runner:amd64
```

## AWS Deployment

### Deploy to App Runner

1. Push the Docker image to ECR:
```bash
./scripts/docker-push.sh dev apprunner Dockerfile.apprunner
```

2. Configure environment variables in App Runner:
- `API_SERVICE_URL`: URL of the API service (from API Gateway or direct endpoint)

3. Deploy using Terraform (update terraform configurations to include the apprunner service)

## API Service Communication

The AppRunner service communicates with the API service through the `/api-health` endpoint:

```bash
# Example request
curl http://localhost:8080/api-health

# Example response
{
  "api_response": {
    "status": "healthy",
    "timestamp": "2025-11-22T00:00:00Z",
    "uptime_seconds": 123.45,
    "version": "0.1.0"
  },
  "status_code": 200,
  "response_time_ms": 45.67
}
```

## Architecture

```
┌─────────────┐         HTTP         ┌─────────────┐
│   Client    │ ────────────────────>│  AppRunner  │
└─────────────┘                      │   Service   │
                                     └──────┬──────┘
                                            │
                                            │ HTTP
                                            v
                                     ┌─────────────┐
                                     │     API     │
                                     │   Service   │
                                     └─────────────┘
```

## Dependencies

- **fastapi**: Web framework
- **uvicorn**: ASGI server
- **httpx**: Async HTTP client for service-to-service communication
- **pydantic**: Data validation
- **pydantic-settings**: Environment variable management

## Development

- Python 3.14+
- Uses `uv` for dependency management
- Follows async/await patterns throughout
- All async code uses uvicorn for proper execution

## Testing

The test suite covers:
- All health check endpoints
- Service-to-service communication structure
- Error handling
- OpenAPI documentation availability
- Request/response validation

Run tests with:
```bash
uv run pytest -v
```

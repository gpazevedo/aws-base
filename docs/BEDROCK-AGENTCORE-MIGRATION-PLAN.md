# AWS Bedrock AgentCore Migration Plan

## Executive Summary

This document outlines the migration strategy for transitioning our backend services from a traditional microservices architecture to AWS Bedrock AgentCore-based AI agents. This analysis evaluates which functions in the shared library can be eliminated, which need radical changes, and which remain relevant.

## What is AWS Bedrock AgentCore?

[Amazon Bedrock AgentCore](https://aws.amazon.com/blogs/aws/introducing-amazon-bedrock-agentcore-securely-deploy-and-operate-ai-agents-at-any-scale/) is AWS's agentic platform to build, deploy, and operate highly capable AI agents securely at scale using any framework and model – with no infrastructure management required.

### Key AgentCore Services (2025)

| Service | Purpose | Impact on Our Architecture |
|---------|---------|---------------------------|
| **Runtime** | Secure, serverless agent deployment and invocation | Replaces Lambda/App Runner orchestration |
| **Gateway** | Unified tool access and connections | Replaces custom API Gateway + inter-service calls |
| **Memory** | Intelligent context retention across sessions | New capability (episodic memory) |
| **Identity** | Seamless authentication across AWS and 3rd-party | Simplifies/eliminates Secrets Manager usage |
| **Observability** | Built-in monitoring and debugging | Replaces custom OpenTelemetry setup |
| **Evaluations** | 13 pre-built quality evaluation systems | New capability for agent quality |
| **Policy** | Fine-grained control over agent actions | New governance capability |
| **Browser & Code Interpreter** | Enhanced agent capabilities | New tooling |

### AgentCore Runtime

**Purpose**: Serverless execution environment for AI agents

**Key Features**:
- [InvokeAgent API](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-invoke-agent.html) for agent invocation
- Binary payloads up to 100 MB
- Streaming responses with real-time chunks
- Automatic session management
- Trace enablement for debugging
- No infrastructure provisioning needed

**How It Works**:
```python
# AgentCore Runtime replaces Lambda/App Runner
import boto3

runtime_client = boto3.client('bedrock-agent-runtime')

response = runtime_client.invoke_agent(
    agentId='AGENT12345',
    agentAliasId='TSTALIASID',
    sessionId='user-session-123',
    enableTrace=True,
    inputText='Analyze my portfolio'
)

# Streaming response
for event in response['completion']:
    if 'chunk' in event:
        print(event['chunk']['bytes'].decode('utf-8'))
```

**Replaces**:
- AWS Lambda function management
- App Runner service configuration
- Custom deployment pipelines
- Container image builds (for App Runner)
- Cold start optimization

### AgentCore Identity

**Purpose**: Unified authentication and authorization for agents

**Key Features**:
- Seamless AWS service authentication
- Third-party service integration
- Automatic credential management
- No manual secret rotation
- Built-in permission boundaries

**How It Works**:
- Agents automatically authenticate to AWS services using IAM roles
- Third-party credentials managed via AgentCore Identity configuration
- Tools inherit authentication context from agent
- No manual API key passing required

**Replaces**:
- Custom ServiceAPIClient with manual API key management
- AWS Secrets Manager for inter-service authentication
- Manual credential injection in requests
- API key caching logic
- Secrets Manager IAM policies

**Example**:
```python
# Before (with ServiceAPIClient)
from shared import ServiceAPIClient

async with ServiceAPIClient(service_name="api") as client:
    # Manual API key retrieval from Secrets Manager
    # Manual header injection
    response = await client.get(f"{base_url}/runner/health")

# After (with AgentCore Identity)
# No code needed - agent automatically authenticated
# Tools can call AWS services directly without credentials
```

## Current Shared Library Architecture

Our shared library (`backend/shared/`) provides:

```
shared/
├── api_client.py      # Inter-service HTTP calls with API key injection
├── logging.py         # Structured logging (structlog)
├── tracing.py         # OpenTelemetry distributed tracing
├── middleware.py      # FastAPI request logging middleware
├── models.py          # Common Pydantic models
├── settings.py        # Base settings classes
└── health.py          # Health check utilities
```

**Lines of Code**: ~650 lines
**Purpose**: Reduce boilerplate from 500+ lines per service to 150 lines

## Migration Analysis by Module

### 🗑️ ELIMINATE: Functions No Longer Needed

#### 1. `api_client.py` - ServiceAPIClient (100% Elimination)

**Current Implementation**: 263 lines
- Custom HTTP client with automatic API key retrieval from Secrets Manager
- Manual header injection with `x-api-key`
- Connection pooling and timeout management
- Cache management for API keys
- boto3 Secrets Manager integration

**Why Eliminate**:

**AgentCore Runtime** + **AgentCore Identity** combination completely eliminates the need:

1. **AgentCore Runtime**: Agents invoke each other via AgentCore, not HTTP
2. **AgentCore Identity**: Authentication handled automatically
3. **AgentCore Gateway**: Tool connections managed by platform

**Before (Current)**:
```python
# 263 lines of custom code in api_client.py

class ServiceAPIClient:
    def __init__(self, service_name, project_name, environment):
        self.service_name = service_name
        self.secrets_client = boto3.client("secretsmanager")
        self._cached_api_key = None

    def get_api_key(self):
        # Retrieve from Secrets Manager
        secret_name = f"{project_name}/{environment}/{service_name}/api-key"
        response = self.secrets_client.get_secret_value(SecretId=secret_name)
        return response["SecretString"]

    async def get(self, url, headers=None):
        # Inject API key
        headers = headers or {}
        headers["x-api-key"] = self.get_api_key()
        # Make request
        return await self._async_client.get(url, headers=headers)

# Usage in service
async with ServiceAPIClient(service_name="api") as client:
    response = await client.get(f"{base_url}/runner/health")
```

**After (AgentCore)**:
```python
# Zero lines of code needed

# Agents communicate via AgentCore Runtime
# Agent A invokes Agent B automatically
# Authentication via AgentCore Identity - automatic
# No manual HTTP calls, no API keys, no Secrets Manager
```

**Infrastructure Changes**:
- ❌ **Remove**: Secrets Manager secrets for API keys
- ❌ **Remove**: IAM policies for `secretsmanager:GetSecretValue`
- ❌ **Remove**: API Gateway custom API keys
- ❌ **Remove**: `httpx` dependency
- ❌ **Remove**: boto3 Secrets Manager client code
- ✅ **Add**: AgentCore agent definitions
- ✅ **Add**: AgentCore Identity configuration
- ✅ **Add**: AgentCore Gateway tool connections

**Cost Impact**:
- **Save**: $1.60/month (Secrets Manager secrets)
- **Save**: $0.05/month (Secrets Manager API calls)
- **Save**: API Gateway request costs
- **Add**: AgentCore Runtime invocation costs (pricing TBD)

**Migration Path**:
1. Define agents in AgentCore (replace services)
2. Configure AgentCore Identity for authentication
3. Set up AgentCore Gateway for tool access
4. Remove all `ServiceAPIClient` usage from code
5. Delete `api_client.py` entirely
6. Remove Secrets Manager Terraform resources
7. Remove Secrets Manager IAM policies

**Files Affected**:
- Delete: `backend/shared/api_client.py` (263 lines)
- Update: `backend/*/main.py` (remove ServiceAPIClient imports)
- Update: `terraform/api-gateway.tf` (remove API keys)
- Delete: `terraform/modules/api-gateway-shared/` (API key management)
- Update: Lambda/AppRunner IAM policies (remove Secrets Manager)

---

#### 2. `tracing.py` - OpenTelemetry Configuration (90% Elimination)

**Current Implementation**: 133 lines
- Manual OpenTelemetry TracerProvider setup
- Custom OTLP exporter configuration
- FastAPI and HTTPx instrumentation
- Resource and span processor management
- Environment detection (Lambda vs local)

**Why Eliminate (90%)**:

**AgentCore Observability** provides built-in tracing:
- Automatic metrics: session count, latency, duration, token usage, error rates
- OpenTelemetry-compatible format natively
- CloudWatch Transaction Search integration
- Trace ID propagation automatic
- No manual instrumentation needed

**Before (Current)**:
```python
# 133 lines in tracing.py

def configure_tracing(
    service_name, service_version, environment,
    otlp_endpoint="http://localhost:4317",
    enable_tracing=True,
    app=None
):
    # Create resource
    resource = Resource.create({
        "service.name": f"{service_name}-{environment}",
        "service.version": service_version,
        "deployment.environment": environment,
    })

    # Configure OTLP exporter
    otlp_exporter = OTLPSpanExporter(
        endpoint=otlp_endpoint,
        insecure=True,
    )

    # Set up tracer provider
    provider = TracerProvider(resource=resource)
    processor = BatchSpanProcessor(otlp_exporter)
    provider.add_span_processor(processor)
    trace.set_tracer_provider(provider)

    # Instrument HTTPX and FastAPI
    HTTPXClientInstrumentor().instrument()
    if app:
        FastAPIInstrumentor.instrument_app(app)

# Usage
configure_tracing(
    service_name="api",
    service_version="1.0.0",
    environment="dev",
    app=app
)
```

**After (AgentCore)**:
```python
# ~13 lines minimal tracing.py (keep get_tracer for custom spans)

from opentelemetry import trace

def get_tracer(name: str) -> trace.Tracer:
    """Get tracer for custom span creation in agent tools."""
    return trace.get_tracer(name)

# AgentCore handles everything else automatically
# Enable in agent invocation:
runtime_client.invoke_agent(
    agentId='AGENT123',
    agentAliasId='ALIAS456',
    sessionId=session_id,
    enableTrace=True,  # Built-in tracing with AgentCore Observability
    inputText=prompt
)
```

**What Remains** (10%):
- `get_tracer()` function for custom business logic spans
- Custom span creation for specific tool operations
- Optional manual instrumentation for complex workflows

**Infrastructure Changes**:
- ❌ **Remove**: ADOT Lambda Layer
- ❌ **Remove**: Custom OTLP endpoint configuration
- ❌ **Remove**: `OTLP_ENDPOINT` environment variable
- ❌ **Remove**: `ENABLE_TRACING` environment variable
- ❌ **Remove**: OpenTelemetry dependencies (mostly)
- ✅ **Add**: CloudWatch Transaction Search setup (one-time)
- ✅ **Add**: AgentCore Observability configuration

**Cost Impact**:
- **Neutral**: CloudWatch metrics similar costs
- **Save**: Simplified maintenance

**Migration Path**:
1. Enable AgentCore Observability for agents
2. Set up CloudWatch Transaction Search (one-time)
3. Remove `configure_tracing()` calls from all services
4. Keep minimal `get_tracer()` for custom spans
5. Remove ADOT Lambda Layer from Terraform
6. Archive 90% of `tracing.py`

---

### 🔄 RADICALLY CHANGE: Functions Needing Major Redesign

#### 3. `middleware.py` - LoggingMiddleware (70% Change)

**Current Implementation**: 99 lines
- FastAPI middleware for request/response logging
- Manual duration tracking
- structlog context binding for correlation
- Request start/completion logging

**Why Change**:

**AgentCore Runtime** changes the paradigm:
- **Before**: FastAPI apps with HTTP endpoints → middleware logs requests
- **After**: Agents invoked via AgentCore Runtime → no HTTP middleware
- **AgentCore Observability** captures agent invocations automatically
- Need different logging approach for agent tool execution

**Before (Current)**:
```python
# 99 lines in middleware.py

class LoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()

        structlog.contextvars.bind_contextvars(
            path=request.url.path,
            method=request.method,
            client_ip=request.client.host
        )

        logger.info("request_started", path=request.url.path)
        response = await call_next(request)
        duration = time.time() - start_time

        logger.info(
            "request_completed",
            status_code=response.status_code,
            duration_seconds=duration
        )
        return response

# Usage
app.add_middleware(LoggingMiddleware)
```

**After (Agent Tool Logging)**:
```python
# New: agent_logging.py (~50 lines)

def log_agent_step(
    step_name: str,
    agent_id: str = None,
    session_id: str = None,
    inputs: dict = None,
    outputs: dict = None,
    duration: float = None,
    success: bool = True,
    error: str = None
):
    """Log individual agent tool execution steps."""
    logger.info(
        "agent_tool_execution",
        step=step_name,
        agent_id=agent_id,
        session_id=session_id,
        inputs=inputs,
        outputs=outputs,
        duration_seconds=duration,
        success=success,
        error=error
    )

def log_agent_invocation(
    agent_id: str,
    session_id: str,
    input_text: str,
    trace_id: str = None
):
    """Log agent invocation for correlation."""
    logger.info(
        "agent_invoked",
        agent_id=agent_id,
        session_id=session_id,
        input_text=input_text[:100],  # Truncate for privacy
        trace_id=trace_id
    )

# Usage in agent tool
from shared import log_agent_step

def analyze_portfolio_tool(params):
    start = time.time()
    try:
        result = perform_analysis(params)
        log_agent_step(
            step_name="analyze_portfolio",
            inputs=params,
            outputs=result,
            duration=time.time() - start,
            success=True
        )
        return result
    except Exception as e:
        log_agent_step(
            step_name="analyze_portfolio",
            inputs=params,
            duration=time.time() - start,
            success=False,
            error=str(e)
        )
        raise
```

**What Changes**:
- Remove: FastAPI middleware concept
- Remove: HTTP request/response logging
- Add: Agent tool execution logging
- Add: Session correlation logging
- Keep: Structured logging with context

**Migration Path**:
1. Create new `agent_logging.py` module
2. Replace middleware usage with tool-level logging
3. Update all tools to log execution
4. Add session/trace correlation
5. Archive old `middleware.py`

---

#### 4. `settings.py` - Service Settings (50% Change)

**Current Implementation**: 101 lines
- `BaseServiceSettings` - service name, version, environment, log level
- `BaseTracingSettings` - OTLP endpoint, enable_tracing
- `BaseAWSSettings` - AWS region
- `FullServiceSettings` - combines all above
- HTTP client settings (timeout)

**Why Change**:

**AgentCore Runtime** changes configuration paradigm:
- **Before**: Service-level config (timeouts, versions, endpoints)
- **After**: Agent-level config defined in AgentCore, tool-level config in code
- **AgentCore Identity**: No API_GATEWAY_URL, no service name needed

**Before (Current)**:
```python
# 101 lines in settings.py

class BaseServiceSettings(BaseSettings):
    service_name: str = Field(..., description="Service name")
    service_version: str = Field(default="1.0.0")
    environment: str = Field(default="dev")
    log_level: str = Field(default="INFO")
    http_timeout: float = Field(default=30.0)

class BaseTracingSettings(BaseSettings):
    enable_tracing: bool = Field(default=True)
    otlp_endpoint: str = Field(default="http://localhost:4317")

class BaseAWSSettings(BaseSettings):
    aws_region: str = Field(default="us-east-1")

class FullServiceSettings(
    BaseServiceSettings,
    BaseTracingSettings,
    BaseAWSSettings
):
    pass

# Usage
settings = FullServiceSettings(service_name="api")
```

**After (Agent Tool Settings)**:
```python
# Simplified: settings.py (~60 lines)

class BaseAgentToolSettings(BaseSettings):
    """Base settings for agent tool execution."""

    # Environment (still needed)
    environment: str = Field(default="dev")
    log_level: str = Field(default="INFO")
    aws_region: str = Field(default="us-east-1")

    # Runtime context (passed from AgentCore)
    agent_id: str | None = Field(default=None)
    session_id: str | None = Field(default=None)
    trace_id: str | None = Field(default=None)

# Agent configuration moved to AgentCore definition
# No service_name, service_version, http_timeout needed

class BedrockAgentConfig(BaseModel):
    """Configuration for Bedrock agent (used in Terraform/SDK)."""

    agent_name: str
    description: str
    instruction: str  # Agent prompt
    model_id: str = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    temperature: float = 0.7
    max_tokens: int = 4096

# Usage
tool_settings = BaseAgentToolSettings()
# Agent config in Terraform, not Python
```

**What Changes**:
- Remove: `service_name`, `service_version` (agent-level now)
- Remove: `http_timeout` (no HTTP clients)
- Remove: `enable_tracing`, `otlp_endpoint` (AgentCore handles)
- Keep: `environment`, `log_level`, `aws_region`
- Add: `agent_id`, `session_id`, `trace_id` (runtime context)
- Add: `BedrockAgentConfig` for Terraform/SDK usage

**Migration Path**:
1. Create `BaseAgentToolSettings` class
2. Create `BedrockAgentConfig` class
3. Update services to use tool settings
4. Move agent config to Terraform
5. Remove old service settings classes

---

### ✅ KEEP UNCHANGED: Functions That Remain Relevant

#### 5. `logging.py` - Structured Logging (Keep 95%)

**Current Implementation**: 74 lines
- `configure_logging()` - sets up structlog with JSON output
- `get_logger()` - returns configured logger
- ISO timestamps and log levels
- CloudWatch-compatible JSON format

**Why Keep**:

**AgentCore Observability** provides high-level metrics but NOT application-specific logging:
- **AgentCore logs**: agent invocations, tool calls, token usage, latency
- **Our logs**: business events, data transformations, custom metrics, debugging
- Structured logs essential for troubleshooting tool implementations

**Usage Remains Same**:
```python
from shared import configure_logging, get_logger

configure_logging(log_level="INFO")
logger = get_logger(__name__)

# In agent tool function
logger.info(
    "processing_user_query",
    user_id=123,
    query_type="financial_analysis",
    portfolio_value=1000000
)
```

**Minor Updates Needed**:
- Add agent context fields (agent_id, session_id, trace_id)
- Update examples for agent tool usage
- Remove service middleware references from docs

**Migration Path**:
1. Keep `logging.py` 95% unchanged
2. Add convenience function for agent context:
   ```python
   def bind_agent_context(agent_id, session_id, trace_id=None):
       structlog.contextvars.bind_contextvars(
           agent_id=agent_id,
           session_id=session_id,
           trace_id=trace_id
       )
   ```
3. Update documentation with agent examples

---

#### 6. `models.py` - Pydantic Models (Keep 80%)

**Current Implementation**: 78 lines
- `HealthResponse`, `StatusResponse` - health checks
- `GreetingRequest`, `GreetingResponse` - example models
- `ErrorResponse` - error handling
- `InterServiceResponse` - inter-service calls
- `ServiceInfo` - service metadata

**Why Keep**:

Agent tools still need data validation and structured I/O:
- Tool input validation
- Tool output structuring
- Consistent error responses
- Type safety

**What Changes**:
- ❌ Remove: `InterServiceResponse` (no HTTP inter-service calls with AgentCore)
- ❌ Remove: `ServiceInfo` (replaced by agent metadata)
- ✅ Keep: `ErrorResponse` (tools can fail)
- ✅ Keep: `HealthResponse` (for tool health checks)
- ✅ Add: Agent-specific base models

**New Models**:
```python
# Add to models.py

class AgentToolInput(BaseModel):
    """Base class for agent tool inputs."""
    trace_id: str | None = Field(None, description="Trace correlation ID")
    session_id: str | None = Field(None, description="Session ID")

class AgentToolOutput(BaseModel):
    """Base class for agent tool outputs."""
    success: bool = Field(..., description="Tool execution success")
    error: str | None = Field(None, description="Error message if failed")
    result: dict | None = Field(None, description="Tool result data")

class AgentSessionContext(BaseModel):
    """Agent session context."""
    agent_id: str
    session_id: str
    user_id: str | None = None
    trace_id: str | None = None
```

**Migration Path**:
1. Remove inter-service models (`InterServiceResponse`, `ServiceInfo`)
2. Add agent base models
3. Update tool implementations to use new models
4. Keep error and health models

---

#### 7. `health.py` - Health Checks (Keep 40%)

**Current Implementation**: 157 lines
- `create_health_endpoint()` - comprehensive health check
- `create_liveness_endpoint()` - K8s liveness
- `create_readiness_endpoint()` - K8s readiness
- Simplified variants for direct use

**Why Change (60%)** and Keep (40%):

**AgentCore Runtime** doesn't expose HTTP endpoints:
- Agents don't have `/health` endpoints
- No Kubernetes-style liveness/readiness probes
- **BUT**: Agent tools may need dependency health checks

**What to Keep**:
```python
# Simplified health.py for agent tools (~60 lines)

async def check_tool_dependencies(
    tool_name: str,
    dependencies: list[Callable] = None
) -> dict:
    """
    Check health of an agent tool and its dependencies.

    Args:
        tool_name: Name of the tool
        dependencies: List of async functions that check dependencies

    Returns:
        Health status dict
    """
    health = {
        "tool": tool_name,
        "status": "healthy",
        "timestamp": datetime.now(UTC).isoformat(),
        "dependencies": {}
    }

    if dependencies:
        for dep_check in dependencies:
            try:
                await dep_check()
                health["dependencies"][dep_check.__name__] = "healthy"
            except Exception as e:
                health["dependencies"][dep_check.__name__] = f"unhealthy: {e}"
                health["status"] = "degraded"

    return health

# Usage in agent tool
async def check_database():
    """Check if database is accessible."""
    # Database connection check
    pass

async def check_s3_access():
    """Check if S3 bucket is accessible."""
    # S3 access check
    pass

health_status = await check_tool_dependencies(
    tool_name="portfolio_analyzer",
    dependencies=[check_database, check_s3_access]
)
```

**What to Remove**:
- FastAPI endpoint creation functions
- HTTP-based health checks
- Liveness/readiness probes

**Migration Path**:
1. Simplify to tool-level health checks
2. Remove FastAPI-specific functions
3. Add dependency validation helpers
4. Keep core health checking logic

---

## Infrastructure Changes

### Current Architecture (Pre-Migration)

```
┌─────────────────────────────────────────────────────────┐
│                     API Gateway                          │
│  ┌──────────┬──────────┬──────────┬──────────┐          │
│  │ /api     │ /chat    │ /s3vector│ /runner  │          │
│  │ + API Key│ + API Key│ + API Key│ + API Key│          │
│  └────┬─────┴────┬─────┴────┬─────┴────┬─────┘          │
└───────┼──────────┼──────────┼──────────┼────────────────┘
        │          │          │          │
        ▼          ▼          ▼          ▼
   ┌────────┐ ┌────────┐ ┌────────┐ ┌─────────┐
   │Lambda  │ │Lambda  │ │Lambda  │ │AppRunner│
   │  API   │ │  Chat  │ │S3Vector│ │ Runner  │
   │        │ │        │ │        │ │         │
   │ FastAPI│ │ FastAPI│ │ FastAPI│ │ FastAPI │
   └───┬────┘ └───┬────┘ └───┬────┘ └────┬────┘
       │          │          │           │
       └──────────┴──────────┴───────────┘
                     │
       ┌─────────────▼──────────────┐
       │    Secrets Manager         │
       │  (Service API Keys)        │
       └────────────────────────────┘
                     │
              ┌──────▼────────┐
              │ Shared Library│
              │ (650 lines)   │
              │ - api_client  │
              │ - tracing     │
              │ - middleware  │
              │ - settings    │
              └───────────────┘
```

### Target Architecture (Post-Migration with AgentCore)

```
┌────────────────────────────────────────────────────────────┐
│          AWS Bedrock AgentCore Platform                     │
│                                                              │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐  │
│  │   Runtime    │  │   Identity    │  │  Observability  │  │
│  │  (Invoke)    │  │    (Auth)     │  │   (Metrics)     │  │
│  │              │  │               │  │                 │  │
│  │ - InvokeAgent│  │ - AWS Auth    │  │ - Sessions      │  │
│  │ - Session Mgmt│  │ - 3rd-party   │  │ - Latency       │  │
│  │ - Streaming  │  │ - No Secrets  │  │ - Tokens        │  │
│  └──────┬───────┘  └───────┬───────┘  │ - Errors        │  │
│         │                  │          │ - Traces        │  │
│  ┌──────▼──────────────────▼─────┐    └─────────────────┘  │
│  │        Gateway                │                          │
│  │   (Tool Connections)          │                          │
│  │ - No HTTP calls needed        │                          │
│  │ - Agent-to-agent built-in     │                          │
│  └───────────────────────────────┘                          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Memory (Session Context)                  │ │
│  │  - Episodic memory across invocations                  │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────┬───────────────────────────────────────────┘
                   │
           ┌───────▼────────┐
           │  Agent Tools   │
           │  (Simplified)  │
           │  (~200 lines)  │
           │                │
           │ - logging      │
           │ - models       │
           │ - health       │
           │ - agent_logging│
           └────────────────┘
```

**Key Differences**:

| Component | Before (Current) | After (AgentCore) |
|-----------|------------------|-------------------|
| **Execution** | Lambda (3) + App Runner (1) | AgentCore Runtime |
| **API Gateway** | Custom REST API with API keys | AgentCore Gateway |
| **Authentication** | Secrets Manager + manual injection | AgentCore Identity (automatic) |
| **Tracing** | Custom OpenTelemetry setup | AgentCore Observability (built-in) |
| **Inter-service** | HTTP calls via ServiceAPIClient | AgentCore agent-to-agent |
| **Memory** | None (stateless) | AgentCore Memory (episodic) |
| **Shared Library** | 650 lines | ~200 lines |

---

## Shared Library Transformation Summary

### Functions to Eliminate (40% of code)

| Module | Lines | Status | Replaced By |
|--------|-------|--------|-------------|
| `api_client.py` | 263 | ❌ **DELETE** | AgentCore Runtime + Identity + Gateway |
| `tracing.py` | 120 | ❌ **DELETE** (90%) | AgentCore Observability |
| **Subtotal** | **383** → **13** | | **370 lines eliminated** |

**Reason**: AgentCore Runtime handles agent invocation, AgentCore Identity handles authentication, AgentCore Gateway handles tool connections, AgentCore Observability handles tracing.

### Functions to Radically Change (30% of code)

| Module | Lines | Status | New Implementation |
|--------|-------|--------|-------------------|
| `middleware.py` | 99 | 🔄 **TRANSFORM** | → `agent_logging.py` (~50 lines) |
| `settings.py` | 101 | 🔄 **TRANSFORM** | → Tool settings (~60 lines) |
| **Subtotal** | **200** → **110** | | **90 lines saved** |

**Reason**: No FastAPI middleware in agents; settings paradigm shifts from service-level to tool-level.

### Functions to Keep (30% of code)

| Module | Lines | Status | Changes |
|--------|-------|--------|---------|
| `logging.py` | 74 | ✅ **KEEP** (95%) | +5 lines (agent context) |
| `models.py` | 78 | ✅ **KEEP** (80%) | -20 lines (remove inter-service), +15 lines (agent models) |
| `health.py` | 157 | ✅ **KEEP** (40%) | -97 lines (remove FastAPI endpoints) |
| `tracing.py` | 13 | ✅ **KEEP** (10%) | Just `get_tracer()` |
| **Subtotal** | **322** → **137** | | **185 lines saved** |

**Reason**: Core utilities (logging, models, health) still needed for tool implementation.

### New Modules Required

| Module | Lines | Purpose |
|--------|-------|---------|
| `agent_logging.py` | ~50 | Agent tool execution logging |
| `agent_tools.py` | ~30 | Base classes for agent tools |
| **Subtotal** | **~80** | |

---

### Final Shared Library Structure

```
shared/
├── __init__.py              # Updated exports
├── logging.py               # ✅ Keep (~79 lines) - structured logging
├── models.py                # ✅ Keep (~73 lines) - Pydantic models
├── settings.py              # 🔄 Transform (~60 lines) - tool settings
├── health.py                # ✅ Keep (~60 lines) - tool health checks
├── agent_logging.py         # 🆕 New (~50 lines) - agent step logging
├── agent_tools.py           # 🆕 New (~30 lines) - tool base classes
├── tracing.py               # ✅ Keep minimal (~13 lines) - get_tracer
└── README.md

DELETED:
├── api_client.py            # ❌ 263 lines - AgentCore replaces
└── middleware.py            # ❌ 99 lines - No FastAPI needed

BEFORE: 650 lines
AFTER:  ~365 lines
REDUCTION: 44% fewer lines (285 lines eliminated)
```

---

## Migration Timeline

### Phase 1: AgentCore Readiness (1 week)

**Goal**: Prepare for AgentCore migration

1. **Learn AgentCore**:
   - Review AgentCore documentation
   - Understand Runtime, Identity, Gateway, Observability
   - Complete AgentCore tutorial
2. **Infrastructure Prep**:
   - Enable AgentCore in AWS account
   - Set up CloudWatch Transaction Search
   - Create test agent in console
3. **Pilot Service Selection**:
   - Choose `s3vector` for pilot (simplest, isolated)
   - Document current functionality
   - Define success criteria

### Phase 2: Pilot Migration - s3vector (2 weeks)

**Goal**: Migrate one service to validate approach

1. **Create AgentCore Agent**:
   - Define agent with instruction/prompt
   - Configure model (Claude 3.5 Sonnet)
   - Set up tools (embedding generation)
2. **Configure AgentCore Services**:
   - Runtime: Set up agent invocation
   - Identity: Configure AWS service access
   - Gateway: Connect to S3, Bedrock
   - Observability: Enable tracing
3. **Update Shared Library** (minimal):
   - Create `agent_logging.py`
   - Create `agent_tools.py`
   - Keep `logging.py`, `models.py`, `health.py`
4. **Test & Validate**:
   - Invoke agent via InvokeAgent API
   - Verify tool execution
   - Check CloudWatch metrics
   - Compare costs

**Success Criteria**:
- Agent responds to prompts correctly
- Tools execute successfully
- Observability data visible
- Latency acceptable (< 2x current)
- Cost within budget

### Phase 3: Shared Library Refactoring (1 week)

**Goal**: Complete shared library transformation

1. **Finalize New Modules**:
   - `agent_logging.py` - agent step logging
   - `agent_tools.py` - base tool classes
   - `BaseAgentToolSettings` - tool configuration
2. **Update Existing Modules**:
   - Simplify `health.py` → tool health checks
   - Add agent context to `logging.py`
   - Add agent models to `models.py`
   - Remove inter-service models
3. **Delete Obsolete Code**:
   - Archive `api_client.py` (263 lines)
   - Archive `middleware.py` (99 lines)
   - Archive 90% of `tracing.py` (120 → 13 lines)
4. **Documentation**:
   - Update README with agent examples
   - Create migration guide
   - Document new patterns

### Phase 4: Remaining Services (3 weeks)

**Goal**: Migrate all services to AgentCore

**Week 1: Migrate `api` Service**
1. Define agent for API service
2. Convert endpoints to tools
3. Configure Gateway connections
4. Test invocation

**Week 2: Migrate `chat` Service**
1. Define agent for chat service
2. Leverage AgentCore Memory for context
3. Multi-turn conversation support
4. Test conversation flow

**Week 3: Migrate `runner` Service**
1. Define agent for runner service
2. Replace App Runner with AgentCore Runtime
3. Test complex workflows
4. Performance validation

### Phase 5: Multi-Agent Orchestration (1 week)

**Goal**: Set up agent collaboration

1. **Supervisor Agent**:
   - Create supervisor for complex workflows
   - Route requests to specialized agents
   - Handle multi-step tasks
2. **Agent Communication**:
   - Configure agent-to-agent connections
   - Test collaboration workflows
   - Validate error handling
3. **Policy & Evaluations**:
   - Set up AgentCore Policy controls
   - Configure quality evaluations
   - Test governance rules

### Phase 6: Infrastructure Cleanup (1 week)

**Goal**: Remove old infrastructure

1. **Terraform Changes**:
   - Remove API Gateway resources
   - Remove Lambda functions
   - Remove App Runner service
   - Remove Secrets Manager secrets for API keys
   - Remove Secrets Manager IAM policies
   - Add AgentCore Terraform resources
2. **Validation**:
   - Verify no orphaned resources
   - Check cost reduction
   - Confirm observability working

### Phase 7: Production Deployment (1 week)

**Goal**: Deploy to production

1. **Blue-Green Deployment**:
   - Deploy AgentCore to production
   - Route 10% traffic → monitor
   - Gradually increase to 100%
2. **Monitoring**:
   - Watch CloudWatch metrics
   - Check error rates
   - Validate latency
   - Monitor costs
3. **Rollback Plan**:
   - Keep old infrastructure for 1 week
   - Quick rollback if issues
   - Decommission after validation

**Total Timeline**: 10 weeks

---

## Cost Analysis

### Current Monthly Costs (Estimated)

| Service | Usage | Cost |
|---------|-------|------|
| Lambda (3 functions) | 100K invocations, 512MB, 5s avg | $5 |
| App Runner | 1 service, 1GB, 50% utilization | $30 |
| API Gateway | 100K requests | $0.35 |
| **Secrets Manager** | **4 secrets** | **$1.60** |
| X-Ray | 100K traces | $0.00 (free tier) |
| CloudWatch Logs | 10GB ingestion | $5 |
| **Total Current** | | **$41.95** |

### Projected AgentCore Costs

| Service | Usage | Cost |
|---------|-------|------|
| AgentCore Runtime | 100K agent invocations | Included in model costs |
| **Model Token Usage** | Claude 3.5 Sonnet, ~500 tokens avg input, ~200 output | **$35-50** |
| AgentCore Observability | Metrics, traces | Included |
| AgentCore Gateway | Tool connections | Included |
| AgentCore Identity | Authentication | Included |
| AgentCore Memory | 1K sessions, 100KB avg | $? (preview pricing TBD) |
| CloudWatch Logs | 5GB ingestion (reduced) | $2.50 |
| **Total Projected** | | **$40-55** |

**Cost Impact Analysis**:

✅ **Eliminated**:
- Lambda compute: -$5
- App Runner: -$30
- API Gateway: -$0.35
- Secrets Manager: -$1.60
- **Savings: $36.95**

❌ **Added**:
- Model token usage: +$35-50
- AgentCore services: Included in model costs
- **Added Costs: $35-50**

📊 **Net Impact**: Similar costs (~$40-55 vs $42), but with significantly more capabilities (Memory, Evaluations, Policy)

**Variables**:
- Token usage can vary significantly based on:
  - Prompt complexity
  - Agent reasoning steps
  - Tool call frequency
  - Response length
- AgentCore Memory pricing TBD (preview)
- Potential for optimization via prompt engineering

---

## Risk Assessment

### High Risk

1. **AgentCore Preview Status**
   - **Risk**: Service in preview, not GA
   - **Impact**: Pricing changes, feature changes, SLA not guaranteed
   - **Mitigation**:
     - Wait for GA before production
     - Run parallel architecture during preview
     - Budget buffer for pricing changes

2. **Token Cost Unpredictability**
   - **Risk**: Agentic workflows can consume significantly more tokens than expected
   - **Impact**: 10x cost increase possible if not monitored
   - **Mitigation**:
     - Implement strict token budgets per agent
     - Monitor token usage daily
     - Circuit breakers for runaway agents
     - Prompt optimization

### Medium Risk

3. **Architectural Paradigm Shift**
   - **Risk**: Team unfamiliar with agentic architecture
   - **Impact**: Longer development time, bugs, suboptimal implementations
   - **Mitigation**:
     - Training sessions on AgentCore
     - Pilot with simple service first
     - Pair programming during migration
     - Code reviews focused on patterns

4. **Observability Gaps**
   - **Risk**: AgentCore Observability may not capture all business-critical metrics
   - **Impact**: Reduced debugging capability
   - **Mitigation**:
     - Keep shared logging library
     - Supplement with custom metrics
     - Test observability in pilot phase

### Low Risk

5. **Performance Variance**
   - **Risk**: Latency may differ from Lambda/App Runner
   - **Impact**: User experience degradation
   - **Mitigation**:
     - Benchmark in pilot phase
     - Set performance SLOs
     - Load testing before production

6. **Vendor Lock-in**
   - **Risk**: Deeper AWS integration harder to reverse
   - **Impact**: Migration to other cloud difficult
   - **Mitigation**:
     - Abstract agent logic with clean interfaces
     - Document dependencies clearly
     - Consider multi-cloud strategy long-term

---

## Decision Framework

### Should We Migrate to AgentCore?

**✅ Migrate If**:
- [x] Services are AI/LLM workflows (financial analysis, chat, recommendations)
- [x] Need sophisticated agent collaboration
- [x] Want to reduce infrastructure management overhead
- [x] Value built-in observability and governance
- [ ] AgentCore reaches GA with acceptable pricing ⏳

**❌ Don't Migrate If**:
- [ ] Services are traditional CRUD APIs
- [ ] Strict latency requirements (< 100ms)
- [ ] Need full control over infrastructure
- [ ] AgentCore pricing significantly exceeds current costs
- [ ] Require on-premises deployment

### Recommended Strategy for fin-advisor

**Phase 1 (Now - Q1 2025)**: Wait & Learn
- Monitor AgentCore GA announcement
- Study documentation and best practices
- Refactor shared library in preparation

**Phase 2 (Q2 2025)**: Pilot with s3vector
- Migrate simplest service to validate approach
- Measure costs, performance, complexity
- Update shared library

**Phase 3 (Q3 2025)**: Full Migration
- If pilot successful, migrate remaining services
- Leverage multi-agent collaboration
- Implement Memory for chat service

**Phase 4 (Q4 2025)**: Production Optimization
- Fine-tune prompts for cost optimization
- Implement Policy controls
- Leverage Evaluations for quality

---

## Conclusion

### Shared Library Transformation

| Aspect | Before | After | Change |
|--------|--------|-------|--------|
| **Total Lines** | 650 | ~365 | **-44%** |
| **Modules** | 7 | 7 (2 new, 2 deleted) | Restructured |
| **Eliminated** | - | 40% (api_client, tracing) | -370 lines |
| **Transformed** | - | 30% (middleware → agent_logging, settings) | Redesigned |
| **Kept** | - | 30% (logging, models, health) | Minor updates |

### AgentCore Services Impact

| AgentCore Service | Replaces | LOC Saved |
|-------------------|----------|-----------|
| **Runtime** | Lambda + App Runner orchestration | N/A (infrastructure) |
| **Identity** | ServiceAPIClient + Secrets Manager | -263 lines |
| **Gateway** | Custom API Gateway + inter-service HTTP | -263 lines |
| **Observability** | Custom OpenTelemetry setup | -120 lines |
| **Memory** | No current equivalent | New capability |
| **Evaluations** | No current equivalent | New capability |
| **Policy** | No current equivalent | New capability |

### Key Takeaways

1. **api_client.py (263 lines) → Eliminated**
   - AgentCore Runtime + Identity + Gateway replace entirely
   - No more manual HTTP clients, API keys, Secrets Manager

2. **tracing.py (133 lines) → 90% Eliminated**
   - AgentCore Observability provides built-in tracing
   - Keep minimal `get_tracer()` for custom spans

3. **middleware.py (99 lines) → Transformed to agent_logging.py (50 lines)**
   - FastAPI middleware → agent tool logging
   - New paradigm for observability

4. **settings.py (101 lines) → Transformed (60 lines)**
   - Service settings → tool settings
   - Agent config moves to AgentCore definitions

5. **Core Utilities → Kept**
   - `logging.py` - Still essential for business logic
   - `models.py` - Still needed for data validation
   - `health.py` - Simplified for tool health checks

### Strategic Recommendation

**For fin-advisor Project**:

✅ **Recommended**: Gradual migration to AgentCore

**Rationale**:
- Your services (api, chat, s3vector, runner) are AI/financial advisory workflows → ideal for AgentCore
- AgentCore eliminates 44% of shared library code
- Significant infrastructure simplification (no Lambda, App Runner, API Gateway management)
- Gain advanced capabilities (Memory, Evaluations, Policy)
- Cost similar (~$40-55 vs $42 currently)

**Timeline**: 10 weeks total
- Week 1: Preparation
- Weeks 2-3: Pilot (s3vector)
- Week 4: Shared library refactoring
- Weeks 5-7: Migrate remaining services
- Week 8: Multi-agent orchestration
- Week 9: Infrastructure cleanup
- Week 10: Production deployment

**Risks to Manage**:
- AgentCore preview status (wait for GA)
- Token cost monitoring (strict budgets)
- Team training (new paradigm)

**Expected Benefits**:
- 44% less shared library code to maintain
- No infrastructure management overhead
- Built-in observability, memory, evaluations
- Simplified authentication (no Secrets Manager)
- Enhanced AI capabilities

---

## Sources

- [New Amazon Bedrock AgentCore Capabilities](https://www.aboutamazon.com/news/aws/aws-amazon-bedrock-agent-core-ai-agents)
- [Introducing Amazon Bedrock AgentCore](https://aws.amazon.com/blogs/aws/introducing-amazon-bedrock-agentcore-securely-deploy-and-operate-ai-agents-at-any-scale/)
- [InvokeAgent API Reference](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_agent-runtime_InvokeAgent.html)
- [Invoke an AgentCore Runtime Agent](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-invoke-agent.html)
- [AgentCore Observability Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability.html)
- [View Observability Data for AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-view.html)
- [Multi-Agent Collaboration](https://aws.amazon.com/about-aws/whats-new/2025/03/amazon-bedrock-multi-agent-collaboration/)
- [Build Trustworthy AI Agents with AgentCore Observability](https://aws.amazon.com/blogs/machine-learning/build-trustworthy-ai-agents-with-amazon-bedrock-agentcore-observability/)

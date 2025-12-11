# VSCode Python Development Setup

This document explains the VSCode configuration for the fin-advisor backend Python services.

## Overview

The project has multiple Python services that share a common library:
- `backend/api/` - API service (Lambda)
- `backend/runner/` - Runner service (AppRunner)
- `backend/s3vector/` - S3 Vector service (Lambda)
- `backend/shared/` - Shared library

## Configuration Files

### 1. `.vscode/settings.json`

Configures Python language server (Pylance) and editor settings:

```json
{
    // Python analysis paths - tells Pylance where to find modules
    "python.analysis.extraPaths": [
        "${workspaceFolder}/backend/shared",
        "${workspaceFolder}/backend/api",
        "${workspaceFolder}/backend/runner",
        "${workspaceFolder}/backend/s3vector"
    ],

    // Enable auto-imports from shared library
    "python.analysis.autoImportCompletions": true,
    "python.analysis.autoSearchPaths": true,

    // Type checking level
    "python.analysis.typeCheckingMode": "basic",

    // Formatting with Ruff
    "[python]": {
        "editor.defaultFormatter": "charliermarsh.ruff",
        "editor.formatOnSave": true,
        "editor.codeActionsOnSave": {
            "source.fixAll": "explicit",
            "source.organizeImports": "explicit"
        }
    }
}
```

**What this does:**
- Enables IntelliSense for imports from `shared` library
- Auto-suggests imports as you type
- Formats code on save using Ruff
- Organizes imports automatically

### 2. `pyrightconfig.json`

Configures Pyright type checker with separate execution environments:

```json
{
  "include": ["backend/api", "backend/runner", "backend/s3vector", "backend/shared"],
  "executionEnvironments": [
    {
      "root": "backend/api",
      "pythonVersion": "3.14",
      "extraPaths": ["backend/shared"],
      "venv": "backend/api/.venv"
    }
    // ... similar for runner, s3vector, shared
  ]
}
```

**What this does:**
- Each service has its own virtual environment
- All services can import from `backend/shared`
- Type checking works across service boundaries
- Reports missing imports as errors

### 3. `.vscode/launch.json`

Debug configurations for running services:

```json
{
  "configurations": [
    {
      "name": "API Service",
      "type": "debugpy",
      "module": "uvicorn",
      "args": ["main:app", "--reload", "--port", "8000"],
      "cwd": "${workspaceFolder}/backend/api",
      "env": {
        "PYTHONPATH": "${workspaceFolder}/backend/shared:${env:PYTHONPATH}"
      }
    }
    // ... similar for runner (8001), s3vector (8002)
  ]
}
```

**What this does:**
- Run/debug services directly from VSCode
- Sets PYTHONPATH to include shared library
- Each service runs on different port (8000, 8001, 8002)
- Supports breakpoints and step debugging

## Usage

### IntelliSense and Auto-Imports

When writing code in any service:

```python
# Type "from shared" and VSCode will suggest:
from shared import ServiceAPIClient, configure_logging

# Or just start typing the function name:
configure_logging  # VSCode suggests the import automatically
```

### Running Services

1. **From Debug Menu:**
   - Press `F5` or click Debug → Start Debugging
   - Select configuration: "API Service", "Runner Service", or "S3Vector Service"
   - Service starts with debugger attached

2. **Setting Breakpoints:**
   - Click left margin in code editor
   - Red dot appears
   - Debugger pauses when line is hit

3. **Multiple Services:**
   - Start first service (e.g., API on port 8000)
   - Click "Run → Start Debugging" again
   - Select second service (e.g., Runner on port 8001)
   - Both run simultaneously

### Running Tests

1. **Test Explorer:**
   - Click Testing icon in sidebar
   - VSCode discovers all `test_*.py` files
   - Click play button to run tests
   - Green checkmark = pass, red X = fail

2. **Debug Single Test:**
   - Use configuration "Python: Pytest Current File"
   - Open test file
   - Press `F5` to debug all tests in file

### Type Checking

VSCode continuously checks types as you code:

- **Green squiggle:** Warning (e.g., missing type stub)
- **Red squiggle:** Error (e.g., missing import, type mismatch)
- Hover for details
- Press `Ctrl+.` for quick fixes

## Troubleshooting

### Import Not Found

**Problem:** `Import "shared" could not be resolved`

**Solutions:**
1. Reload VSCode window: `Ctrl+Shift+P` → "Developer: Reload Window"
2. Check Python interpreter: Bottom-left status bar should show Python 3.14
3. Verify `.venv` exists: `ls backend/api/.venv`
4. Install shared library in editable mode:
   ```bash
   cd backend/api
   source .venv/bin/activate
   pip install -e ../shared
   ```

### Type Checking Errors

**Problem:** Pyright shows errors but code runs fine

**Solutions:**
1. Check `pyrightconfig.json` includes your service
2. Verify `extraPaths` includes `backend/shared`
3. Restart Pylance: `Ctrl+Shift+P` → "Pylance: Restart Server"

### Debugger Won't Start

**Problem:** "Module not found" when starting debugger

**Solutions:**
1. Check virtual environment is activated
2. Verify PYTHONPATH in launch configuration
3. Install dependencies: `cd backend/api && pip install -e .`

### Auto-Import Not Working

**Problem:** VSCode doesn't suggest imports from shared library

**Solutions:**
1. Check `python.analysis.extraPaths` in settings.json
2. Enable auto-imports: `python.analysis.autoImportCompletions: true`
3. Index workspace: `Ctrl+Shift+P` → "Python: Clear Cache and Reload Window"

## Environment Variables

Services need these environment variables (set in `.env` or launch.json):

```bash
# Required
SERVICE_NAME=api              # or "runner", "s3vector"
PROJECT_NAME=fin-advisor
ENVIRONMENT=dev               # or "test", "prod"

# Optional
LOG_LEVEL=INFO                # or "DEBUG", "WARNING", "ERROR"
AWS_REGION=us-east-1
ENABLE_TRACING=true
OTLP_ENDPOINT=http://localhost:4317
```

## Best Practices

### 1. Use Virtual Environments

Each service should have its own `.venv`:

```bash
cd backend/api
python3.14 -m venv .venv
source .venv/bin/activate
pip install -e .
pip install -e ../shared
```

### 2. Install Shared Library in Editable Mode

This allows changes to shared library to be immediately reflected:

```bash
pip install -e ../shared
```

### 3. Keep Settings Synchronized

When adding new services:
1. Add to `pyrightconfig.json` executionEnvironments
2. Add to `.vscode/settings.json` extraPaths
3. Add debug configuration to `.vscode/launch.json`

### 4. Use Type Hints

VSCode's IntelliSense works best with type hints:

```python
from shared import ServiceAPIClient

# Good - VSCode knows the return type
async def get_data() -> dict:
    client = ServiceAPIClient("api")
    return await client.get("/endpoint")

# Better - VSCode knows exact structure
from shared.models import HealthResponse

async def health() -> HealthResponse:
    return HealthResponse(status="healthy", ...)
```

## Required VSCode Extensions

Install these extensions for full functionality:

1. **Python** (`ms-python.python`)
   - Language support, debugging, IntelliSense

2. **Pylance** (`ms-python.vscode-pylance`)
   - Fast type checking and IntelliSense

3. **Ruff** (`charliermarsh.ruff`)
   - Linting and formatting

4. **Python Debugger** (`ms-python.debugpy`)
   - Debugging support

Install via:
```bash
code --install-extension ms-python.python
code --install-extension ms-python.vscode-pylance
code --install-extension charliermarsh.ruff
code --install-extension ms-python.debugpy
```

## Summary

The VSCode setup provides:
- ✅ IntelliSense for shared library imports
- ✅ Auto-import suggestions
- ✅ Type checking across services
- ✅ One-click debugging for each service
- ✅ Test discovery and execution
- ✅ Auto-formatting on save
- ✅ Multi-service development support

All configuration is project-specific and committed to Git, so every developer gets the same experience.

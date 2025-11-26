# Pre-Commit Hooks Documentation

## Overview

Automated code quality enforcement using **Ruff** (formatting + linting) and **Pyright** (type checking) with pre-commit hooks.

---

## 🛠️ Tools Used

| Tool | Purpose | Version | Speed |
|------|---------|---------|-------|
| **Ruff** | Format + Lint | Latest | 10-100x faster than Black/Flake8 |
| **Pyright** | Type Check | Latest | Fast, accurate |
| **pre-commit** | Git Hooks | Latest | Manages hooks |

### Why These Tools?

**Ruff** (replaces Black + Flake8 + isort + pyupgrade + more):
- ✅ All-in-one: formatting AND linting
- ✅ 10-100x faster than traditional tools
- ✅ Auto-fixes most issues
- ✅ Written in Rust, actively maintained by Astral (makers of uv)
- ✅ Compatible with Black formatting style

**Pyright** (vs mypy):
- ✅ Faster than mypy
- ✅ Better error messages
- ✅ Official Microsoft type checker
- ✅ Used by VS Code's Python extension
- ✅ Better support for modern Python features

---

## 🚀 Quick Start

### One-Time Setup

```bash
# Install pre-commit hooks
make setup-pre-commit

# This will:
# 1. Create pyproject.toml (if needed)
# 2. Install uv dependencies
# 3. Install git hooks
# 4. Run initial check on all files
```

### Daily Usage

Pre-commit hooks run **automatically** on every commit:

```bash
# Write code
vim src/my_module.py

# Commit (hooks run automatically)
git add src/my_module.py
git commit -m "Add new feature"

# Hooks run:
# ✓ Ruff formatting
# ✓ Ruff linting (auto-fix)
# ✓ Pyright type checking
# ✓ General file checks

# If issues found and auto-fixed:
git add src/my_module.py  # Re-stage fixed files
git commit -m "Add new feature"
```

---

## 📋 What Gets Checked

### On Every Commit

**Python Files:**
1. **Ruff Linting** - Checks for:
   - Code style (PEP 8)
   - Common bugs
   - Complexity issues
   - Import sorting
   - Modernization opportunities
   - Performance anti-patterns
   - **Auto-fixes** most issues

2. **Ruff Formatting** - Enforces:
   - Consistent code style
   - 100 character line length
   - Double quotes
   - Proper spacing

3. **Pyright Type Checking** - Verifies:
   - Type annotations
   - Type consistency
   - Missing types
   - Invalid type usage
   - **Note:** For backend services (multi-venv projects), a custom hook runs `make typecheck` instead

**All Files:**
4. **General Checks**:
   - Remove trailing whitespace
   - Fix end-of-file newlines
   - Check YAML/TOML/JSON syntax
   - Prevent large files (>1MB)
   - Detect merge conflicts
   - Detect private keys

**Terraform Files:**
5. **Terraform Formatting**:
   - Format `.tf` files
   - Validate syntax

---

## 🎯 Manual Commands

### Code Quality

```bash
# Check code quality (no changes)
make lint

# Auto-fix issues
make lint-fix

# Type check
make typecheck

# Run tests
make test

# Format code
make format-python

# Run all pre-commit hooks manually
make pre-commit-all
```

### Detailed Commands

```bash
# Ruff linting only
uv run ruff check src/ tests/

# Ruff with auto-fix
uv run ruff check --fix src/ tests/

# Ruff formatting only
uv run ruff format src/ tests/

# Pyright type checking
uv run pyright src/

# Run pre-commit on specific files
uv run pre-commit run --files src/main.py

# Update pre-commit hooks to latest versions
make pre-commit-update
```

---

## 📐 Ruff Rules Enabled

### Full Rule Set

```python
[tool.ruff.lint]
select = [
    "E",     # pycodestyle errors
    "W",     # pycodestyle warnings
    "F",     # pyflakes
    "I",     # isort (import sorting)
    "N",     # pep8-naming
    "UP",    # pyupgrade (modern Python)
    "B",     # flake8-bugbear (bugs)
    "C4",    # flake8-comprehensions
    "SIM",   # flake8-simplify
    "TCH",   # flake8-type-checking
    "PTH",   # flake8-use-pathlib
    "RUF",   # Ruff-specific rules
    "PERF",  # Performance anti-patterns
    "FURB",  # refurb (modernization)
]
```

**What This Catches:**
- ✅ Syntax errors
- ✅ Unused imports/variables
- ✅ Undefined names
- ✅ Import sorting issues
- ✅ Naming convention violations
- ✅ Outdated Python syntax (e.g., `typing.List` → `list`)
- ✅ Common bugs (mutable defaults, etc.)
- ✅ Inefficient comprehensions
- ✅ Overly complex conditions
- ✅ Performance issues
- ✅ Code that can be simplified

**Auto-Fixed:**
- ✅ Import sorting
- ✅ Unused imports
- ✅ Code formatting
- ✅ Outdated syntax
- ✅ Simplifiable code

---

## 🔍 Type Checking with Pyright

### Configuration

```toml
[tool.pyright]
pythonVersion = "3.13"
typeCheckingMode = "standard"  # Options: off, basic, standard, strict
```

### What Gets Checked

- ✅ Missing type annotations on function parameters
- ✅ Missing return type annotations
- ✅ Type mismatches
- ✅ Invalid type operations
- ✅ Unused imports/variables
- ✅ Optional access without checks
- ✅ Incompatible types in assignments

### Basic Example

```python
# ❌ Fails type checking
def greet(name):  # Missing type annotation
    return f"Hello, {name}"

# ✅ Passes type checking
def greet(name: str) -> str:
    return f"Hello, {name}"
```

### Multi-Service Type Checking

**For projects with multiple backend services** (each with isolated venvs), this project uses a **custom pre-commit hook** that intelligently type-checks only the services you've modified:

#### How It Works

1. **Detects changes**: Analyzes which backend services have modified Python files
2. **Runs per-service**: Executes `make typecheck SERVICE=<name>` for each affected service
3. **Uses isolated venvs**: Each service's type checking runs in its own virtual environment
4. **Scales automatically**: Works with any number of services without configuration changes

#### Example

```bash
# Modify api service
vim backend/api/main.py

# On commit, pre-commit automatically runs:
# → Type checking backend service: api
# → make typecheck SERVICE=api
# → ✅ Type check passed for service: api

# Modify multiple services
vim backend/api/main.py backend/runner/main.py

# On commit, pre-commit runs both:
# → Type checking backend service: api
# → ✅ Type check passed for service: api
# → Type checking backend service: runner
# → ✅ Type check passed for service: runner
```

#### Manual Type Check

```bash
# Check specific service
make typecheck SERVICE=api
make typecheck SERVICE=runner

# Check all services (manual approach)
make typecheck SERVICE=api && make typecheck SERVICE=runner
```

#### Implementation Details

The custom hook is defined in [`.pre-commit-hooks/typecheck-backend.sh`](../.pre-commit-hooks/typecheck-backend.sh) and configured in [`.pre-commit-config.yaml`](../.pre-commit-config.yaml):

```yaml
# Custom hook: Type check backend services with isolated venvs
- repo: local
  hooks:
    - id: typecheck-backend
      name: Type check backend services
      entry: .pre-commit-hooks/typecheck-backend.sh
      language: script
      types: [python]
      files: ^backend/.*\.py$
```

**Why this approach?**

- ✅ **Efficient**: Only type-checks services that changed
- ✅ **Accurate**: Each service uses its own venv with correct dependencies
- ✅ **Scalable**: Automatically handles new services
- ✅ **Fast**: Parallel service checking when multiple services change

---

## 🛡️ Skip Hooks (Emergency Only)

### Skip All Hooks

```bash
# Emergency commits only!
git commit --no-verify -m "Hotfix"
```

### Skip Specific Hook

```bash
# Skip only type checking (still runs Ruff)
SKIP=pyright git commit -m "WIP: incomplete types"
```

### Temporary Disable

```bash
# Uninstall hooks
uv run pre-commit uninstall

# Re-install later
make setup-pre-commit
```

---

## 🔧 Configuration Files

### .pre-commit-config.yaml

Defines which hooks run:
- Ruff (lint + format)
- Pyright (type check)
- General file checks
- Terraform formatting

### pyproject.toml

Configures tool behavior:
- `[tool.ruff]` - Ruff settings
- `[tool.ruff.lint]` - Rule selection
- `[tool.ruff.format]` - Formatting style
- `[tool.pyright]` - Type checking settings
- `[tool.pytest.ini_options]` - Test configuration

---

## 📊 Example Workflow

### Scenario: Adding a New Feature

```bash
# 1. Write code
cat > src/api.py <<EOF
from typing import Dict

def get_user(id):  # Missing type annotation
    return {"id": id, "name": "Alice"}
EOF

# 2. Attempt commit
git add src/api.py
git commit -m "Add get_user function"

# Pre-commit runs:
# ✓ Ruff format - No changes needed
# ✓ Ruff lint - Auto-adds import sorting
# ✗ Pyright - Error: Missing type on 'id' parameter

# Fix automatically shown:
# def get_user(id: int) -> Dict[str, str | int]:

# 3. Fix type issue
vim src/api.py  # Add type: id: int

# 4. Commit again
git add src/api.py
git commit -m "Add get_user function"

# ✓ All hooks pass!
```

---

## 🎨 Formatting Style

### Ruff Format (Black-compatible)

```python
# Automatic formatting applied:

# Before
x=1+2

# After
x = 1 + 2

# Before
my_list = [ 1,2,3,4,5 ]

# After
my_list = [1, 2, 3, 4, 5]

# Line length: 100 characters max
very_long_function_call(
    argument1, argument2, argument3, argument4
)  # Automatically wrapped
```

---

## 🐛 Troubleshooting

### "command not found: uv"

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Add to PATH
export PATH="$HOME/.local/bin:$PATH"
```

### "No module named 'pre_commit'"

```bash
# Install dependencies
cd /path/to/project
make setup-pre-commit
```

### "Pyright not found"

```bash
# Reinstall dev dependencies
uv sync --dev
```

### Hooks Taking Too Long

```bash
# Update hooks (may include performance improvements)
make pre-commit-update

# Or skip slow hooks temporarily
SKIP=pyright git commit -m "Quick fix"
```

### False Positives

Add to `pyproject.toml`:

```toml
[tool.ruff.lint]
ignore = [
    "E501",  # Line too long (if you disagree with a rule)
]

[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["S101"]  # Allow assert in tests
```

---

## 📈 CI/CD Integration

Pre-commit hooks also run in GitHub Actions:

```yaml
# .github/workflows/test.yml
- name: Run pre-commit
  run: uv run pre-commit run --all-files

# Or individual tools:
- name: Lint
  run: uv run ruff check src/

- name: Type check
  run: uv run pyright src/
```

---

## 🔄 Updating Hooks

```bash
# Update to latest versions
make pre-commit-update

# Review changes
git diff .pre-commit-config.yaml

# Test updated hooks
make pre-commit-all
```

---

## 📚 Additional Resources

- [Ruff Documentation](https://docs.astral.sh/ruff/)
- [Ruff Rules](https://docs.astral.sh/ruff/rules/)
- [Pyright Documentation](https://microsoft.github.io/pyright/)
- [Pre-commit Documentation](https://pre-commit.com/)
- [uv Documentation](https://docs.astral.sh/uv/)

---

## ✅ Summary

**Pre-commit hooks provide:**
- ✅ Consistent code style (Ruff format)
- ✅ Bug detection (Ruff lint)
- ✅ Type safety (Pyright)
- ✅ Auto-fixes for most issues
- ✅ Fast feedback (runs locally before push)
- ✅ CI/CD ready (same tools in GitHub Actions)

**One-time setup:**
```bash
make setup-pre-commit
```

**Then forget about it** - hooks run automatically on every commit! 🎉

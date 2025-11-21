# Release Please - Automated Release Management

## Overview

This project uses [release-please](https://github.com/googleapis/release-please) by Google to automate version management and changelog generation. Release Please automates CHANGELOG generation, version bumps, and GitHub releases by parsing your git history based on [Conventional Commits](https://www.conventionalcommits.org/).

---

## ⚙️ Setup Required

### Creating a Personal Access Token (PAT)

GitHub Actions' default `GITHUB_TOKEN` cannot create pull requests. You need to create a Personal Access Token (PAT) with the necessary permissions.

**Steps:**

1. **Generate a Fine-Grained Personal Access Token:**
   - Go to **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens**
   - Click **Generate new token**
   - Configure the token:
     - **Name**: `Release Please Token`
     - **Expiration**: Choose appropriate duration (90 days recommended)
     - **Repository access**: Select "Only select repositories" and choose this repository
     - **Permissions**:
       - **Contents**: Read and write
       - **Pull requests**: Read and write
       - **Metadata**: Read-only (automatically selected)

2. **Add Token as Repository Secret:**
   - Go to your repository's **Settings** → **Secrets and variables** → **Actions**
   - Click **New repository secret**
   - **Name**: `RELEASE_PLEASE_TOKEN`
   - **Value**: Paste your generated token
   - Click **Add secret**

3. **Verify Setup:**
   - The workflow in `.github/workflows/release-please.yml` is configured to use this token
   - If the token is not set, it will fall back to `GITHUB_TOKEN` (which cannot create PRs)

**Alternative: Use GitHub App (Advanced)**

For organizations, consider using a [GitHub App](https://github.com/googleapis/release-please-action#github-app-authentication) instead of a PAT for better security and no expiration concerns.

---

## 🎯 What is Release Please?

**Release Please** is a GitHub Action that:

- ✅ **Automates versioning** - Bumps versions based on commit messages
- ✅ **Generates CHANGELOGs** - Creates beautiful, categorized changelogs
- ✅ **Creates GitHub Releases** - Publishes releases with release notes
- ✅ **Manages release PRs** - Opens/updates a release PR with pending changes
- ✅ **Follows SemVer** - Respects Semantic Versioning (major.minor.patch)
- ✅ **Zero configuration** - Works out of the box with sensible defaults

---

## 🔄 How It Works

### The Workflow

```
1. Developer commits with conventional format
   └─> feat: add user authentication
   └─> fix: resolve database connection issue

2. Release Please analyzes commits
   └─> feat = minor version bump (0.1.0 → 0.2.0)
   └─> fix = patch version bump (0.2.0 → 0.2.1)

3. Release Please opens/updates a Release PR
   └─> Updates CHANGELOG.md
   └─> Updates version in pyproject.toml (for Python projects)
   └─> Groups commits by type (Features, Bug Fixes, etc.)

4. Maintainer reviews and merges Release PR
   └─> Release Please creates a GitHub Release
   └─> Tags the release (e.g., v0.2.1)
   └─> Publishes release notes
```

### Visual Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Developer Workflow                                         │
│                                                             │
│  1. Write code                                              │
│  2. Commit with conventional format:                        │
│     git commit -m "feat: add Lambda timeout configuration"  │
│  3. Push to main branch                                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Release Please (Automated)                                 │
│                                                             │
│  1. Detects new commits on main                             │
│  2. Analyzes commit messages                                │
│  3. Determines version bump (major/minor/patch)             │
│  4. Opens/Updates "Release PR"                              │
│     - Updates CHANGELOG.md                                  │
│     - Updates version files                                 │
│     - Groups commits by type                                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Maintainer Action                                          │
│                                                             │
│  1. Review Release PR                                       │
│  2. Merge when ready to release                             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Release Please Creates Release                             │
│                                                             │
│  1. Creates Git tag (e.g., v1.2.3)                          │
│  2. Creates GitHub Release with notes                       │
│  3. Closes Release PR                                       │
│  4. Workflow creates major/minor tags (v1, v1.2)            │
└─────────────────────────────────────────────────────────────┘
```

---

## 📝 Conventional Commits

Release Please requires commits to follow the **Conventional Commits** specification.

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Commit Types and Version Bumps

| Type | Description | Version Bump | Visible in Changelog |
|------|-------------|--------------|---------------------|
| `feat` | New feature | **MINOR** (0.1.0 → 0.2.0) | ✅ Features |
| `fix` | Bug fix | **PATCH** (0.1.0 → 0.1.1) | ✅ Bug Fixes |
| `perf` | Performance improvement | **PATCH** | ✅ Performance |
| `revert` | Revert previous commit | **PATCH** | ✅ Reverts |
| `docs` | Documentation only | **PATCH** | ✅ Documentation |
| `refactor` | Code refactoring | **PATCH** | ✅ Refactoring |
| `style` | Code style changes | **PATCH** | ❌ Hidden |
| `test` | Add/update tests | **PATCH** | ❌ Hidden |
| `build` | Build system changes | **PATCH** | ❌ Hidden |
| `ci` | CI/CD changes | **PATCH** | ❌ Hidden |
| `chore` | Other changes | **PATCH** | ❌ Hidden |

### Breaking Changes (MAJOR version bump)

To trigger a **MAJOR** version bump (1.0.0 → 2.0.0), add `BREAKING CHANGE:` in the commit footer:

```bash
feat: migrate to new authentication system

This changes the authentication API significantly.

BREAKING CHANGE: The old /auth/login endpoint is removed. Use /v2/auth/login instead.
```

Or use the `!` suffix:

```bash
feat!: migrate to new authentication system
```

---

## ✍️ Commit Message Examples

### Good Examples

```bash
# Feature (minor version bump)
feat: add DynamoDB table encryption
feat(lambda): add timeout configuration option
feat(bootstrap): support multiple AWS regions

# Bug fix (patch version bump)
fix: resolve S3 bucket naming collision
fix(terraform): correct IAM policy for Lambda execution
fix(docs): update broken links in README

# Breaking change (major version bump)
feat!: change default Lambda runtime to Python 3.13
feat: migrate to Terraform 1.6

BREAKING CHANGE: Terraform 1.6+ is now required

# Documentation
docs: add release-please documentation
docs(readme): update quick start guide

# Refactoring
refactor: simplify Terraform module structure
refactor(bootstrap): extract VPC configuration to separate file

# Performance
perf: optimize Docker image build time
perf(lambda): reduce cold start by 50ms

# Tests (hidden from changelog)
test: add unit tests for Lambda handler
test(terraform): add validation tests

# CI/CD (hidden from changelog)
ci: add release-please workflow
ci: update GitHub Actions to v4

# Chores (hidden from changelog)
chore: update dependencies
chore(deps): bump boto3 to 1.28.0
```

### Bad Examples (❌ Avoid)

```bash
# Too vague
fix: fix bug
update: update code

# Not following convention
Add new feature for authentication
Fixed the Lambda timeout issue
Updated README

# Missing type
add DynamoDB support
resolve connection issue
```

---

## 🚀 Using Release Please

### 1. Write Code and Commit

```bash
# Make your changes
git add .

# Commit with conventional format
git commit -m "feat: add CloudWatch dashboard for Lambda metrics"

# Push to main branch (or merge PR to main)
git push origin main
```

### 2. Release Please Creates/Updates Release PR

After pushing to `main`, Release Please will:

1. **Analyze commits** since last release
2. **Open or update** a "Release PR" (titled: `chore(main): release X.Y.Z`)
3. **Update CHANGELOG.md** with categorized commits
4. **Update version** in `pyproject.toml`

**Example Release PR:**

```
Title: chore(main): release 1.2.0

Changes:
✅ Updated CHANGELOG.md
✅ Updated pyproject.toml (version: 1.1.0 → 1.2.0)

Commits included:
• feat: add CloudWatch dashboard for Lambda metrics
• fix: resolve IAM policy attachment race condition
• docs: update deployment guide
```

### 3. Review and Merge Release PR

As a maintainer:

1. **Review** the Release PR
   - Check CHANGELOG.md is accurate
   - Verify version bump is correct
   - Ensure all commits are included

2. **Merge** the Release PR when ready to release
   - This triggers the actual release

3. **Release Please creates**:
   - Git tag (e.g., `v1.2.0`)
   - GitHub Release with release notes
   - Major/minor version tags (e.g., `v1`, `v1.2`)

### 4. Check the Release

Visit your GitHub repository's [Releases](https://github.com/your-org/your-repo/releases) page to see:

- **Release notes** (auto-generated from commits)
- **CHANGELOG** (grouped by commit type)
- **Assets** (if configured)

---

## 🛠️ Configuration

### Workflow Configuration

The workflow is located at `.github/workflows/release-please.yml`.

#### Key Configuration Options

```yaml
release-type: python
# Options: python, node, terraform, simple, rust, go, java, etc.

package-name: aws-base-python
# Used in CHANGELOG and release titles

changelog-types: |
  # Customize which commit types appear in CHANGELOG
  # and how they're grouped
```

#### Supported Release Types

| Release Type | Language/Framework | Version File Updated |
|-------------|-------------------|---------------------|
| `python` | Python | `pyproject.toml`, `setup.py` |
| `node` | Node.js | `package.json` |
| `terraform` | Terraform | N/A |
| `simple` | Generic | `version.txt` |
| `rust` | Rust | `Cargo.toml` |
| `go` | Go | N/A |

### Advanced Configuration

Create `.release-please-manifest.json` for advanced configuration:

```json
{
  ".": "1.0.0"
}
```

Create `release-please-config.json` for customization:

```json
{
  "release-type": "python",
  "package-name": "aws-base-python",
  "bump-minor-pre-major": true,
  "bump-patch-for-minor-pre-major": true,
  "changelog-sections": [
    {"type": "feat", "section": "Features"},
    {"type": "fix", "section": "Bug Fixes"},
    {"type": "perf", "section": "Performance Improvements"}
  ],
  "extra-files": [
    "VERSION"
  ]
}
```

---

## 📊 Changelog Example

Here's what an auto-generated CHANGELOG.md looks like:

```markdown
# Changelog

## [1.2.0](https://github.com/org/repo/compare/v1.1.0...v1.2.0) (2024-01-15)

### Features

* add CloudWatch dashboard for Lambda metrics ([a1b2c3d](https://github.com/org/repo/commit/a1b2c3d))
* support multiple AWS regions in bootstrap ([e4f5g6h](https://github.com/org/repo/commit/e4f5g6h))

### Bug Fixes

* resolve IAM policy attachment race condition ([i7j8k9l](https://github.com/org/repo/commit/i7j8k9l))
* correct S3 bucket naming in outputs ([m0n1o2p](https://github.com/org/repo/commit/m0n1o2p))

### Documentation

* update deployment guide with new examples ([q3r4s5t](https://github.com/org/repo/commit/q3r4s5t))

## [1.1.0](https://github.com/org/repo/compare/v1.0.0...v1.1.0) (2024-01-10)

### Features

* add App Runner support ([u6v7w8x](https://github.com/org/repo/commit/u6v7w8x))
```

---

## 🏷️ Version Tagging

Our workflow creates **three types of tags** for each release:

### 1. Full Version Tag (Immutable)

```
v1.2.3
```

Created by Release Please. Never moves.

### 2. Minor Version Tag (Movable)

```
v1.2
```

Always points to the latest patch in the v1.2.x series.

**Example:**
- Release v1.2.0 → creates/moves `v1.2` tag
- Release v1.2.1 → moves `v1.2` tag to v1.2.1
- Release v1.2.2 → moves `v1.2` tag to v1.2.2

### 3. Major Version Tag (Movable)

```
v1
```

Always points to the latest release in the v1.x.x series.

**Example:**
- Release v1.0.0 → creates/moves `v1` tag
- Release v1.2.3 → moves `v1` tag to v1.2.3
- Release v2.0.0 → creates/moves `v2` tag (v1 stays on v1.2.3)

### Benefits

This tagging strategy allows users to:

```bash
# Pin to exact version (recommended for production)
git clone --branch v1.2.3 https://github.com/org/repo.git

# Use latest patch in v1.2 series (get bug fixes)
git clone --branch v1.2 https://github.com/org/repo.git

# Use latest in v1 series (get features + bug fixes)
git clone --branch v1 https://github.com/org/repo.git
```

---

## 🔍 Troubleshooting

### Release PR Not Created

**Problem**: Pushed to main but no Release PR appeared.

**Solutions**:

1. **Check PAT token is configured**:
   ```
   Error: "GitHub Actions is not permitted to create or approve pull requests"
   ```

   **Solution**: You need to set up a `RELEASE_PLEASE_TOKEN` secret. See the [Setup Required](#️-setup-required) section above.

   The default `GITHUB_TOKEN` provided by GitHub Actions cannot create pull requests for security reasons. You must use a Personal Access Token (PAT) with appropriate permissions.

2. **Check commit format**:
   ```bash
   # Bad (no type)
   git log -1 --pretty=%B
   # Output: "add new feature"

   # Good
   # Output: "feat: add new feature"
   ```

3. **Verify workflow ran**:
   - Go to Actions tab in GitHub
   - Check if "Release Please" workflow ran
   - Review logs for errors

4. **Check if release is needed**:
   - Release Please only creates PRs if there are releasable commits
   - Commits like `chore:`, `ci:`, `test:` don't trigger releases by default

### Release PR Not Creating Release

**Problem**: Merged Release PR but no GitHub Release created.

**Solutions**:

1. **Check workflow permissions**:
   ```yaml
   permissions:
     contents: write      # Required
     pull-requests: write # Required
   ```

2. **Verify branch protection**:
   - Release Please needs to create tags
   - Check branch protection rules don't block tag creation

3. **Check workflow logs**:
   - Go to Actions tab
   - Find the workflow run after merging Release PR
   - Review "Run release-please" step

### Wrong Version Bump

**Problem**: Expected minor bump, got patch (or vice versa).

**Solution**: Check commit message format:

```bash
# This triggers PATCH (0.1.0 → 0.1.1)
fix: correct typo

# This triggers MINOR (0.1.0 → 0.2.0)
feat: add new feature

# This triggers MAJOR (0.1.0 → 1.0.0)
feat!: breaking change
# or
feat: breaking change

BREAKING CHANGE: This breaks existing API
```

### Multiple Release PRs

**Problem**: Multiple Release PRs open at the same time.

**Solution**: Close old Release PRs. Release Please will create a fresh one with all commits.

### Changelog Missing Commits

**Problem**: Some commits don't appear in CHANGELOG.

**Possible reasons**:

1. **Commit type is hidden**:
   - `test:`, `build:`, `ci:`, `chore:`, `style:` are hidden by default
   - Check `changelog-types` in workflow configuration

2. **Commit is after last release**:
   - Only commits since last release appear
   - Check: `git log v1.0.0..HEAD` (replace v1.0.0 with your last release)

3. **Commit format invalid**:
   - Release Please ignores non-conventional commits
   - Use `git log --oneline` to verify format

---

## 🎯 Best Practices

### 1. Use Conventional Commits Consistently

**Good workflow**:
```bash
# Configure git to use a commit template
cat > ~/.gitmessage << EOF
# Type: feat, fix, docs, style, refactor, perf, test, chore
# <type>(<scope>): <subject>
#
# <body>
#
# <footer>
EOF

git config --global commit.template ~/.gitmessage
```

### 2. Scope Your Commits

Add scope for better organization:

```bash
feat(lambda): add timeout configuration
fix(terraform): correct IAM policy
docs(readme): update installation steps
```

**Scopes for this project**:
- `bootstrap` - Bootstrap infrastructure
- `lambda` - Lambda-related changes
- `apprunner` - App Runner changes
- `eks` - EKS cluster changes
- `terraform` - Terraform configuration
- `docs` - Documentation
- `ci` - CI/CD workflows
- `scripts` - Shell scripts

### 3. Write Descriptive Commit Messages

```bash
# Bad
feat: update

# Good
feat(lambda): add CloudWatch Logs retention configuration

Adds a new variable `lambda_logs_retention_days` to control how long
Lambda function logs are retained in CloudWatch Logs.

Closes #42
```

### 4. Group Related Changes

Use scopes to group related commits in CHANGELOG:

```
### Features

#### Lambda
* add timeout configuration
* add memory size variable

#### Bootstrap
* support multiple AWS regions
* add optional VPC creation
```

### 5. Review Release PRs Before Merging

Before merging a Release PR:

- ✅ Verify CHANGELOG.md is accurate
- ✅ Check version bump is correct
- ✅ Ensure all commits are included
- ✅ Test the changes locally
- ✅ Update documentation if needed

### 6. Don't Edit CHANGELOG.md Manually

Let Release Please manage CHANGELOG.md. If you need to edit:

1. Make changes in the Release PR
2. Commit with `chore(changelog): <description>`
3. Push to the Release PR branch

### 7. Use Breaking Changes Sparingly

Only use `BREAKING CHANGE:` for actual breaking changes:

```bash
# This is a breaking change (changes API)
feat!: change Lambda function URL format

BREAKING CHANGE: Lambda URLs now use /v2/ prefix

# This is NOT a breaking change (backward compatible)
feat: add new optional parameter to Lambda configuration
```

---

## 🔗 Integration with CI/CD

### Trigger Deployments on Release

Update your deployment workflows to trigger on release:

```yaml
name: Deploy to Production

on:
  release:
    types: [published]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: |
          echo "Deploying version ${{ github.event.release.tag_name }}"
          # Your deployment steps
```

### Use Release Tags in Docker

```yaml
- name: Build Docker image
  run: |
    docker build -t myapp:${{ github.event.release.tag_name }} .
    docker build -t myapp:latest .
```

### Conditional Workflows

```yaml
- name: Deploy to staging (pre-release)
  if: github.event.release.prerelease
  run: # Deploy to staging

- name: Deploy to production (stable release)
  if: ${{ !github.event.release.prerelease }}
  run: # Deploy to production
```

---

## 📚 Additional Resources

### Official Documentation

- [Release Please GitHub](https://github.com/googleapis/release-please)
- [Release Please Action](https://github.com/googleapis/release-please-action)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Semantic Versioning](https://semver.org/)

### Related Project Documentation

- [Main README](../README.md) - Project overview
- [Terraform Bootstrap Guide](TERRAFORM-BOOTSTRAP.md) - Infrastructure setup
- [Scripts Documentation](SCRIPTS.md) - Automation scripts
- [Pre-commit Hooks](PRE-COMMIT.md) - Code quality

### Commit Message Helpers

- [Commitizen](https://github.com/commitizen/cz-cli) - Interactive commit message helper
- [Commitlint](https://github.com/conventional-changelog/commitlint) - Lint commit messages
- [Husky](https://github.com/typicode/husky) - Git hooks for enforcing conventions

---

## 📊 Quick Reference

### Commit Type Cheat Sheet

```bash
feat:     New feature                    → MINOR bump
fix:      Bug fix                        → PATCH bump
perf:     Performance improvement        → PATCH bump
docs:     Documentation only             → PATCH bump
refactor: Code refactoring              → PATCH bump
style:    Code style (no logic change)   → PATCH bump (hidden)
test:     Add/update tests               → PATCH bump (hidden)
build:    Build system changes           → PATCH bump (hidden)
ci:       CI/CD changes                  → PATCH bump (hidden)
chore:    Other changes                  → PATCH bump (hidden)

BREAKING CHANGE: or !                    → MAJOR bump
```

### Common Workflows

```bash
# Make a feature release
git commit -m "feat: add new authentication system"
git push origin main
# → Release Please creates v0.2.0

# Make a bug fix release
git commit -m "fix: resolve memory leak in Lambda"
git push origin main
# → Release Please creates v0.2.1

# Make a breaking change release
git commit -m "feat!: migrate to Python 3.13"
git push origin main
# → Release Please creates v1.0.0
```

---

## ✅ Summary

**Release Please provides**:

✅ **Automated versioning** based on commit messages
✅ **Generated CHANGELOGs** with categorized commits
✅ **GitHub Releases** with beautiful release notes
✅ **SemVer compliance** without manual intervention
✅ **Conventional Commits** enforcement
✅ **Zero maintenance** after initial setup

**Developer workflow**:

1. Write code
2. Commit with conventional format: `feat: add feature`
3. Push to main
4. Review Release PR
5. Merge Release PR
6. Release Please handles the rest!

**Benefits**:

- 📝 Never manually write CHANGELOG.md again
- 🎯 Consistent version numbering
- 🚀 Faster releases
- 📊 Better visibility into changes
- 🔄 Automated release process

---

**Questions?** Check the [troubleshooting section](#-troubleshooting) or open an issue.

**Happy releasing! 🎉**

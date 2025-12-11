# Changelog

All notable changes to agsys-common will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Migrated from local editable install to AWS CodeArtifact
- Renamed package from `shared` to `agsys-common`
- Moved from `backend/shared/` to `agsys/common/`
- Changed imports from `from shared import` to `from common import`

## [0.0.1] - 2025-12-11

### Added
- Initial release to AWS CodeArtifact
- API client with automatic API key injection
- Structured logging with structlog
- OpenTelemetry distributed tracing
- FastAPI middleware for request logging
- Common Pydantic models (HealthResponse, StatusResponse, etc.)
- Base settings classes (BaseServiceSettings, FullServiceSettings)
- Health check utilities

### Documentation
- Added installation instructions for CodeArtifact
- Added LICENSE (MIT)
- Added MANIFEST.in for package distribution
- Updated README with CodeArtifact usage

[Unreleased]: https://github.com/gpazevedo/agsys-common/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/gpazevedo/agsys-common/releases/tag/v0.0.1

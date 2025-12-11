#!/bin/bash
# =============================================================================
# Build agsys-common Library Package
# =============================================================================
# This script builds the agsys-common library into distributable packages
# (wheel and source distribution) that can be published to CodeArtifact.
#
# Usage:
#   ./scripts/build-common-library.sh
#
# Output:
#   - agsys/common/dist/agsys_common-VERSION-py3-none-any.whl
#   - agsys/common/dist/agsys-common-VERSION.tar.gz
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building agsys-common library package...${NC}"

# Navigate to package directory
cd agsys/common

# Verify pyproject.toml exists
if [ ! -f "pyproject.toml" ]; then
    echo -e "${RED}Error: pyproject.toml not found in agsys/common/${NC}"
    exit 1
fi

# Get version from pyproject.toml
VERSION=$(grep '^version = ' pyproject.toml | cut -d'"' -f2)
echo -e "${BLUE}Package version: ${VERSION}${NC}"

# Clean previous builds
echo -e "${BLUE}Cleaning previous builds...${NC}"
rm -rf dist/ build/ *.egg-info/

# Install/upgrade build tools using uv
echo -e "${BLUE}Ensuring build tools are installed...${NC}"
uv tool install build --quiet 2>/dev/null || uv tool upgrade build --quiet 2>/dev/null || true

# Build the package
echo -e "${BLUE}Building package distributions...${NC}"
uv tool run --from build pyproject-build --sdist --wheel --outdir dist/

# Verify build artifacts
if [ ! -d "dist" ] || [ -z "$(ls -A dist 2>/dev/null)" ]; then
    echo -e "${RED}Error: Build failed - no distributions created${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Package built successfully${NC}"
echo ""
echo -e "${BLUE}Distributions created:${NC}"
ls -lh dist/

# Show package contents
echo ""
echo -e "${BLUE}Package contents (first 30 files):${NC}"
TAR_FILE=$(ls dist/*.tar.gz 2>/dev/null | head -1)
if [ -n "$TAR_FILE" ]; then
    tar -tzf "$TAR_FILE" | head -30
fi

# Show package metadata
echo ""
echo -e "${BLUE}Package metadata:${NC}"
WHEEL_FILE=$(ls dist/*.whl 2>/dev/null | head -1)
if [ -n "$WHEEL_FILE" ]; then
    python -m zipfile -l "$WHEEL_FILE" | grep -E "(METADATA|PKG-INFO)" | head -5
fi

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo -e "Next step: Publish to CodeArtifact with ${YELLOW}./scripts/publish-common-library.sh${NC}"

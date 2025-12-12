#!/bin/bash
# =============================================================================
# Bump agsys-common Library Version
# =============================================================================
# This script updates the version number in both pyproject.toml and __init__.py
# following semantic versioning rules.
#
# Usage:
#   ./scripts/bump-common-version.sh [major|minor|patch|prerelease]
#
# Examples:
#   ./scripts/bump-common-version.sh patch      # 0.0.1 -> 0.0.2
#   ./scripts/bump-common-version.sh minor      # 0.0.1 -> 0.1.0
#   ./scripts/bump-common-version.sh major      # 0.0.1 -> 1.0.0
#   ./scripts/bump-common-version.sh prerelease # 0.1.0 -> 0.1.0a1 (or increment existing)
#
# Semantic Versioning Strategy:
#   - Dev/Testing: Use pre-release versions (0.1.0a1, 0.1.0b1, 0.1.0rc1)
#   - Production: Use stable versions (0.1.0, 1.0.0)
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get version type from argument
VERSION_TYPE="${1:-}"

if [[ ! "$VERSION_TYPE" =~ ^(major|minor|patch|prerelease)$ ]]; then
    echo -e "${RED}Usage: $0 [major|minor|patch|prerelease]${NC}"
    echo ""
    echo "Examples:"
    echo "  $0 patch       # Increment patch version (0.0.1 -> 0.0.2)"
    echo "  $0 minor       # Increment minor version (0.0.1 -> 0.1.0)"
    echo "  $0 major       # Increment major version (0.0.1 -> 1.0.0)"
    echo "  $0 prerelease  # Add/increment pre-release (0.1.0 -> 0.1.0a1 or 0.1.0a1 -> 0.1.0a2)"
    exit 1
fi

PYPROJECT="agsys/common/pyproject.toml"
INIT_FILE="agsys/common/__init__.py"

# Check if files exist
if [ ! -f "$PYPROJECT" ]; then
    echo -e "${RED}Error: $PYPROJECT not found${NC}"
    exit 1
fi

if [ ! -f "$INIT_FILE" ]; then
    echo -e "${RED}Error: $INIT_FILE not found${NC}"
    exit 1
fi

# Get current version
CURRENT_VERSION=$(grep '^version = ' "$PYPROJECT" | cut -d'"' -f2)
echo -e "${BLUE}Current version: ${CURRENT_VERSION}${NC}"

# Parse version components
# Handle pre-release versions (e.g., 1.2.0a1, 1.2.0b1, 1.2.0rc1)
if [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(a|b|rc)?([0-9]+)?$ ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    PRERELEASE_TYPE="${BASH_REMATCH[4]}"
    PRERELEASE_NUM="${BASH_REMATCH[5]}"
else
    echo -e "${RED}Error: Invalid version format: $CURRENT_VERSION${NC}"
    exit 1
fi

# Calculate new version based on type
case "$VERSION_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        PRERELEASE_TYPE=""
        PRERELEASE_NUM=""
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        PRERELEASE_TYPE=""
        PRERELEASE_NUM=""
        ;;
    patch)
        if [ -n "$PRERELEASE_TYPE" ]; then
            # If current version is pre-release, upgrade to stable
            PRERELEASE_TYPE=""
            PRERELEASE_NUM=""
        else
            # Otherwise increment patch
            PATCH=$((PATCH + 1))
        fi
        ;;
    prerelease)
        if [ -n "$PRERELEASE_TYPE" ]; then
            # Increment existing pre-release number
            PRERELEASE_NUM=$((PRERELEASE_NUM + 1))
        else
            # Add alpha pre-release
            PRERELEASE_TYPE="a"
            PRERELEASE_NUM="1"
        fi
        ;;
esac

# Construct new version string
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
if [ -n "$PRERELEASE_TYPE" ]; then
    NEW_VERSION="${NEW_VERSION}${PRERELEASE_TYPE}${PRERELEASE_NUM}"
fi

echo -e "${GREEN}New version: ${NEW_VERSION}${NC}"

# Confirm with user
read -p "Update version to ${NEW_VERSION}? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Version update cancelled${NC}"
    exit 0
fi

# Update pyproject.toml
echo -e "${BLUE}Updating ${PYPROJECT}...${NC}"
sed -i "s/^version = .*/version = \"$NEW_VERSION\"/" "$PYPROJECT"

# Update __init__.py
echo -e "${BLUE}Updating ${INIT_FILE}...${NC}"
sed -i "s/^__version__ = .*/__version__ = \"$NEW_VERSION\"/" "$INIT_FILE"

echo ""
echo -e "${GREEN}✓ Version updated successfully${NC}"
echo -e "${BLUE}Files updated:${NC}"
echo "  - $PYPROJECT"
echo "  - $INIT_FILE"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review changes: git diff"
echo "  2. Build package: ./scripts/build-common-library.sh"
echo "  3. Publish to CodeArtifact: ./scripts/publish-common-library.sh"
echo "  4. Commit changes: git add $PYPROJECT $INIT_FILE"
echo "  5. Create tag: git tag v${NEW_VERSION}"

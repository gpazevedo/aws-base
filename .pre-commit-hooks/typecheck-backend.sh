#!/usr/bin/env bash
# =============================================================================
# Custom Pre-Commit Hook: Type Check Backend Services
# =============================================================================
# This hook runs 'make typecheck' for backend services that have changed files.
# It automatically detects which services need type checking based on modified files.
# =============================================================================

set -e

# Get the list of changed files
CHANGED_FILES="$@"

# Track which services need type checking
SERVICES_TO_CHECK=()

# Check each changed file
for file in $CHANGED_FILES; do
  # Check if file is in backend directory and extract service name
  if [[ $file =~ ^backend/([^/]+)/.*\.py$ ]]; then
    SERVICE="${BASH_REMATCH[1]}"

    # Add to list if not already present
    if [[ ! " ${SERVICES_TO_CHECK[@]} " =~ " ${SERVICE} " ]]; then
      SERVICES_TO_CHECK+=("$SERVICE")
    fi
  fi
done

# Exit if no services need checking
if [ ${#SERVICES_TO_CHECK[@]} -eq 0 ]; then
  echo "No backend Python services changed, skipping type check"
  exit 0
fi

# Run type check for each affected service
EXIT_CODE=0
for service in "${SERVICES_TO_CHECK[@]}"; do
  echo "Type checking backend service: $service"

  # Check if service directory exists
  if [ ! -d "backend/$service" ]; then
    echo "Warning: Service directory backend/$service not found, skipping"
    continue
  fi

  # Run type check
  if ! make typecheck SERVICE="$service"; then
    EXIT_CODE=1
    echo "❌ Type check failed for service: $service"
  else
    echo "✅ Type check passed for service: $service"
  fi
done

exit $EXIT_CODE

#!/bin/bash

# Run ONLY the deployment tests, not all tests with "test_multiplayer" prefix

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  Deployment Tests Only"
echo "=========================================="

# Ensure godot is in PATH
export PATH="$HOME/bin:$PATH"

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${YELLOW}Running ONLY deployment tests...${NC}"
echo ""

# Run GUT with directory limited to ONLY test_multiplayer_deployment.gd
godot --path "$PROJECT_ROOT" \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -ginclude_subdirs=false \
  -gselect=test_multiplayer_deployment.gd

TEST_RESULT=$?

echo ""
echo "=========================================="
if [ $TEST_RESULT -eq 0 ]; then
    echo -e "  ${GREEN}✓ Tests Passed${NC}"
else
    echo -e "  ${RED}✗ Tests Failed${NC}"
fi
echo "=========================================="

exit $TEST_RESULT

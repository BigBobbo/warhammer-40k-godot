#!/bin/bash

# Multiplayer Integration Test Runner
# Runs multiplayer tests using GUT framework

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Warhammer 40K Multiplayer Test Runner"
echo "=========================================="

# Ensure godot is in PATH
export PATH="$HOME/bin:$PATH"

# Check if godot exists
if ! command -v godot &> /dev/null; then
    echo -e "${RED}ERROR: godot command not found${NC}"
    echo "Please ensure godot is installed and in your PATH"
    echo "Expected location: \$HOME/bin/godot"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found godot: $(which godot)"

# Get project root (parent of tests directory)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo -e "${GREEN}✓${NC} Project root: $PROJECT_ROOT"

# Check if we're in the right directory
if [ ! -f "$PROJECT_ROOT/project.godot" ]; then
    echo -e "${RED}ERROR: project.godot not found in $PROJECT_ROOT${NC}"
    exit 1
fi

# Ensure test directories exist
mkdir -p "$PROJECT_ROOT/tests/saves"
mkdir -p "$HOME/Library/Application Support/Godot/app_userdata/40k/test_screenshots"

echo -e "${GREEN}✓${NC} Test directories ready"

# Parse command line arguments
TEST_FILE=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            TEST_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo ""
            echo "Usage: ./run_multiplayer_tests.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -f, --file <filename>    Run specific test file"
            echo "  -v, --verbose            Enable verbose output"
            echo "  -h, --help               Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run_multiplayer_tests.sh                              # Run all multiplayer tests"
            echo "  ./run_multiplayer_tests.sh -f test_multiplayer_deployment.gd   # Run specific test"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}ERROR: Unknown option $1${NC}"
            exit 1
            ;;
    esac
done

# Build GUT command
GUT_CMD=(
    godot
    --path "$PROJECT_ROOT"
    -s addons/gut/gut_cmdln.gd
    -gdir=res://tests/integration/
    -gprefix=test_multiplayer
)

# Add specific test if requested
if [ -n "$TEST_FILE" ]; then
    echo -e "${YELLOW}Running specific test:${NC} $TEST_FILE"
    GUT_CMD+=(-gtest="$TEST_FILE")
else
    echo -e "${YELLOW}Running all multiplayer integration tests${NC}"
fi

# Add verbosity
if [ "$VERBOSE" = true ]; then
    GUT_CMD+=(-gverbose)
fi

echo ""
echo "Command: ${GUT_CMD[*]}"
echo ""
echo "=========================================="
echo "  Starting Tests..."
echo "=========================================="
echo ""

# Run the tests
"${GUT_CMD[@]}"

TEST_RESULT=$?

echo ""
echo "=========================================="
if [ $TEST_RESULT -eq 0 ]; then
    echo -e "  ${GREEN}✓ All Tests Passed${NC}"
else
    echo -e "  ${RED}✗ Tests Failed${NC}"
    echo ""
    echo "To debug failures:"
    echo "  1. Check screenshots in: ~/Library/Application Support/Godot/app_userdata/40k/test_screenshots/"
    echo "  2. Check logs in: ~/Library/Application Support/Godot/app_userdata/40k/logs/"
    echo "  3. Re-run with -v for verbose output"
fi
echo "=========================================="

exit $TEST_RESULT
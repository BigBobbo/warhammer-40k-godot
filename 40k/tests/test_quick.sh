#!/bin/bash

# Quick test script to verify multiplayer instances can launch and connect
# This is simpler than running full GUT tests - just launches two instances manually

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Quick Multiplayer Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Ensure godot is in PATH
export PATH="$HOME/bin:$PATH"

# Get absolute path to project
PROJECT_PATH="/Users/robertocallaghan/Documents/claude/godotv2/40k"

if [ ! -f "$PROJECT_PATH/project.godot" ]; then
    echo -e "${RED}ERROR: project.godot not found at $PROJECT_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found project at: $PROJECT_PATH"
echo ""

# Check if godot exists
if ! command -v godot &> /dev/null; then
    echo -e "${RED}ERROR: godot command not found${NC}"
    echo "Please ensure godot is installed and in your PATH"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found godot: $(which godot)"
echo ""

echo -e "${YELLOW}Launching HOST instance...${NC}"
godot --path "$PROJECT_PATH" --test-mode --auto-host --position=100,100 &
HOST_PID=$!
echo -e "${GREEN}✓${NC} Host launched (PID: $HOST_PID)"
echo ""

echo -e "${YELLOW}Waiting 5 seconds for host to initialize...${NC}"
sleep 5

echo -e "${YELLOW}Launching CLIENT instance...${NC}"
godot --path "$PROJECT_PATH" --test-mode --auto-join --position=900,100 &
CLIENT_PID=$!
echo -e "${GREEN}✓${NC} Client launched (PID: $CLIENT_PID)"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Two game windows should now be visible!${NC}"
echo ""
echo "Check that:"
echo "  • Host window shows: 40k Test - Host"
echo "  • Client window shows: 40k Test - Client"
echo "  • Both windows navigated to multiplayer lobby"
echo "  • Connection established (check console output)"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop both instances${NC}"
echo -e "${BLUE}========================================${NC}"

# Wait for Ctrl+C
trap "echo ''; echo 'Cleaning up...'; kill $HOST_PID $CLIENT_PID 2>/dev/null; exit 0" INT

# Wait for processes
wait $HOST_PID $CLIENT_PID 2>/dev/null
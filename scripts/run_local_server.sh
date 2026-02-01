#!/bin/bash
# Run local WebSocket server for development testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PORT=${PORT:-9080}
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_PROJECT="$PROJECT_DIR/40k"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Warhammer 40K Local Server${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check for Godot
if ! command -v godot &> /dev/null; then
    # Try common macOS locations
    if [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
        GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
    elif [ -x "$HOME/bin/godot" ]; then
        GODOT="$HOME/bin/godot"
    else
        echo -e "${RED}Error: Godot not found in PATH${NC}"
        echo "Please install Godot or add it to your PATH"
        exit 1
    fi
else
    GODOT="godot"
fi

echo -e "${YELLOW}Using Godot: $GODOT${NC}"
echo -e "${YELLOW}Project: $GODOT_PROJECT${NC}"
echo -e "${YELLOW}Port: $PORT${NC}"
echo ""

# Create local server config
echo -e "${GREEN}Creating local server config...${NC}"
cat > "$GODOT_PROJECT/server_config.local.json" << EOF
{
    "server_url": "ws://localhost:$PORT"
}
EOF

echo -e "${GREEN}Starting server on port $PORT...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Run the server
cd "$GODOT_PROJECT"
$GODOT --headless --path . --main-scene res://server/server.tscn --port $PORT

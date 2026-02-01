#!/bin/bash
# Run a local client that connects to the local WebSocket server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SERVER_URL=${SERVER_URL:-"ws://localhost:9080"}
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_PROJECT="$PROJECT_DIR/40k"
CLIENT_ID=${1:-$(date +%s)}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Warhammer 40K Local Client${NC}"
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
echo -e "${YELLOW}Server URL: $SERVER_URL${NC}"
echo -e "${YELLOW}Client ID: $CLIENT_ID${NC}"
echo ""

# Create local server config
echo -e "${GREEN}Creating local server config...${NC}"
cat > "$GODOT_PROJECT/server_config.local.json" << EOF
{
    "server_url": "$SERVER_URL"
}
EOF

echo -e "${GREEN}Starting client...${NC}"
echo ""

# Run the client
cd "$GODOT_PROJECT"
$GODOT --path . --window-title "40K Client $CLIENT_ID"

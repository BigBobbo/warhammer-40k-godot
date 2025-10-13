#!/bin/bash

# Test script for debug mode drag fix

echo "=== Debug Mode Drag Fix Test ==="
echo ""
echo "This test will verify that debug mode model dragging works correctly."
echo ""

# Find the log directory
LOG_DIR="$HOME/Library/Application Support/Godot/app_userdata/40k/logs"
if [ ! -d "$LOG_DIR" ]; then
    echo "Warning: Log directory not found at $LOG_DIR"
    echo "Logs will be written but may not be accessible"
fi

# Start Godot
export PATH="$HOME/bin:$PATH"

echo "Starting Godot..."
echo ""
echo "Test Steps:"
echo "1. Load a game or start a new game"
echo "2. Press 9 to enter debug mode"
echo "   - You should see 'DEBUG MODE ACTIVE' overlay"
echo "   - Tokens should have yellow/orange styling"
echo "3. Click and drag any model"
echo "   - Ghost visual should appear during drag"
echo "   - Ghost should have correct shape and size"
echo "4. Release mouse to drop model"
echo "   - Model should move to new position"
echo "   - Visual should update on board"
echo "5. Press 9 again to exit debug mode"
echo "   - Overlay should disappear"
echo "   - Tokens should return to normal colors"
echo ""
echo "For multiplayer testing:"
echo "6. Host a game from one terminal"
echo "7. Join from another terminal"
echo "8. Press 9 on host to enter debug mode"
echo "   - Client should see overlay appear"
echo "9. Drag a model on host"
echo "   - Client should see the model move"
echo "10. Press 9 on client to enter debug mode"
echo "11. Drag a model on client"
echo "   - Host should see the model move"
echo ""

# Launch Godot
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot project.godot

echo ""
echo "Test complete. Check logs at:"
echo "$LOG_DIR"

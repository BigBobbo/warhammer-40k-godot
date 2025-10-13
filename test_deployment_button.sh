#!/bin/bash

# Test script for deployment button issue
# This script will:
# 1. Launch Godot
# 2. Wait for log file to be created
# 3. Monitor the log file for key events

echo "======================================"
echo "Deployment Button Test Script"
echo "======================================"
echo ""
echo "Instructions:"
echo "1. This script will launch Godot"
echo "2. Play the game and deploy all units"
echo "3. Try to click the 'End Deployment' button"
echo "4. The script will show relevant log entries"
echo "5. Press Ctrl+C when done to see the analysis"
echo ""
echo "Press Enter to start..."
read

# Export PATH to include Godot
export PATH="$HOME/bin:$PATH"

# Get the log directory
LOG_DIR="$HOME/Library/Application Support/Godot/app_userdata/40k/logs"

echo "Monitoring log directory: $LOG_DIR"
echo ""

# Get the most recent log file before starting
BEFORE_COUNT=$(ls -1 "$LOG_DIR"/debug_*.log 2>/dev/null | wc -l | tr -d ' ')

# Launch Godot in background
echo "Launching Godot..."
godot &
GODOT_PID=$!

# Wait for new log file to appear
echo "Waiting for log file to be created..."
sleep 3

# Find the newest log file
AFTER_COUNT=$(ls -1 "$LOG_DIR"/debug_*.log 2>/dev/null | wc -l | tr -d ' ')

if [ "$AFTER_COUNT" -gt "$BEFORE_COUNT" ]; then
    LOG_FILE=$(ls -t "$LOG_DIR"/debug_*.log | head -1)
    echo "Found log file: $LOG_FILE"
    echo ""
    echo "======================================"
    echo "Monitoring for key events..."
    echo "Deploy all units and try to click 'End Deployment'"
    echo "Press Ctrl+C when done"
    echo "======================================"
    echo ""

    # Monitor the log file for deployment-related events
    tail -f "$LOG_FILE" | while read line; do
        # Highlight important lines
        if echo "$line" | grep -q -i "all_deployed\|button.*disabled\|BUTTON.*CLICKED\|End Deployment\|update_ui.*DEPLOYMENT\|models_placed_changed\|Phase button configured"; then
            echo ">>> $line"
        fi
    done
else
    echo "ERROR: No new log file created!"
    echo "Please check if Godot is installed and working"
fi

# Cleanup on exit
trap "kill $GODOT_PID 2>/dev/null; echo ''; echo 'Test stopped.'" EXIT

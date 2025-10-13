#!/bin/bash

# Script to check the latest Godot log file for deployment button issues

LOG_DIR="$HOME/Library/Application Support/Godot/app_userdata/40k/logs"

# Find the most recent log file
LATEST_LOG=$(ls -t "$LOG_DIR"/debug_*.log 2>/dev/null | head -1)

if [ -z "$LATEST_LOG" ]; then
    echo "ERROR: No log files found in $LOG_DIR"
    exit 1
fi

echo "======================================"
echo "Latest log file: $LATEST_LOG"
echo "======================================"
echo ""

echo "=== ALL DEPLOYMENT BUTTON RELATED EVENTS ==="
echo ""
cat "$LATEST_LOG" | grep -i "all_deployed\|button.*disabled\|BUTTON.*CLICKED\|End Deployment\|update_ui.*DEPLOYMENT\|models_placed_changed\|Phase button configured\|Phase action button"

echo ""
echo ""
echo "=== BUTTON CONNECTION VERIFICATION ==="
echo ""
cat "$LATEST_LOG" | grep -i "VERIFICATION\|connected"

echo ""
echo ""
echo "=== PHASE TRANSITIONS ==="
echo ""
cat "$LATEST_LOG" | grep -i "update_ui_for_phase\|UPDATE UI FOR PHASE"

echo ""
echo ""
echo "=== To view full log file, run: ==="
echo "cat '$LATEST_LOG'"

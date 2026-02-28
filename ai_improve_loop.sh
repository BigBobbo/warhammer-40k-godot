#!/bin/bash
# AI Improvement Loop
# Runs Claude Code repeatedly to iterate on AI until a unit is destroyed.
# Usage: caffeinate -dims ./ai_improve_loop.sh
# Stop with Ctrl+C

set -e

MAX_ITERATIONS=20
ITERATION=0
LOG_DIR="/Users/robertocallaghan/Library/Application Support/Godot/app_userdata/40k/logs"
PROJECT_DIR="/Users/robertocallaghan/Documents/claude/godotv2"
LOOP_LOG="$PROJECT_DIR/ai_loop_log.txt"

PROMPT='In the current game when AI plays AI neither army ever manages to kill any of the opponents units. This is unexpected. Think hard about how to improve the AI. For the Ork player make them more aggressive and willing to take risks in the hopes of destroying some of the enemy units.
Look at the AI_IMPROVEMENT.md doc and see what improvements have been made recently for context.
Play an AI vs AI match and observe the outputs.
After each match think hard about how to improve the AI, update the code and add a summary of your findings to the AI_IMPROVEMENT.md doc.
Use the search and destroy deployment zones as they has both armies closer to each other increasing the likelihood of attacks.
IMPORTANT: At the end of your session, grep the game log for "UNIT DESTROYED" or "Model killed" or "models destroyed" and report whether any units/models were killed. Write a one-line summary to ai_loop_status.txt with either "KILLS_FOUND: <details>" or "NO_KILLS: <summary of what you changed>".'

# Colors for console output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}AI IMPROVEMENT LOOP${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Goal: Get AI to destroy at least one enemy unit     ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_status() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $1${NC}"
}

print_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $1${NC}"
}

print_banner
echo "=== AI Improvement Loop Started at $(date) ===" >> "$LOOP_LOG"
print_status "Loop started. Max iterations: $MAX_ITERATIONS"
print_status "Full output logged to: ai_loop_log.txt"
echo ""

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
    ITERATION=$((ITERATION + 1))
    ITER_START=$(date +%s)

    echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}  ITERATION $ITERATION / $MAX_ITERATIONS${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"

    echo "" >> "$LOOP_LOG"
    echo "========================================" >> "$LOOP_LOG"
    echo "  ITERATION $ITERATION / $MAX_ITERATIONS" >> "$LOOP_LOG"
    echo "  Started: $(date)" >> "$LOOP_LOG"
    echo "========================================" >> "$LOOP_LOG"

    # Clear the status file before each run
    rm -f "$PROJECT_DIR/ai_loop_status.txt"

    # Record the newest log file BEFORE the game runs
    BEFORE_LOG=$(ls -t "$LOG_DIR"/debug_*.log 2>/dev/null | head -1)

    # Run Claude with the prompt (output goes to log only, not console)
    print_status "Launching Claude Code session..."
    print_status "  - Reading AI_IMPROVEMENT.md for context"
    print_status "  - Analyzing and updating AI code"
    print_status "  - Running AI vs AI match (Search and Destroy)"
    print_status "  - This may take several minutes..."
    echo ""

    cd "$PROJECT_DIR"
    claude -p \
        --dangerously-skip-permissions \
        --model opus \
        "$PROMPT" >> "$LOOP_LOG" 2>&1 || true

    ITER_END=$(date +%s)
    ITER_DURATION=$(( ITER_END - ITER_START ))
    ITER_MINS=$(( ITER_DURATION / 60 ))
    ITER_SECS=$(( ITER_DURATION % 60 ))

    echo "" >> "$LOOP_LOG"
    echo "--- Iteration $ITERATION completed at $(date) ---" >> "$LOOP_LOG"

    print_status "Iteration $ITERATION finished (${ITER_MINS}m ${ITER_SECS}s)"

    # Show what Claude reported
    if [ -f "$PROJECT_DIR/ai_loop_status.txt" ]; then
        STATUS=$(cat "$PROJECT_DIR/ai_loop_status.txt")
        echo "Claude status: $STATUS" >> "$LOOP_LOG"
        print_status "Claude reports: $STATUS"
        if echo "$STATUS" | grep -qi "KILLS_FOUND"; then
            echo ""
            print_success "UNITS WERE KILLED ON ITERATION $ITERATION!"
            print_success "Details: $STATUS"
            echo ""
            echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║  GOAL ACHIEVED! AI successfully destroyed a unit!    ║${NC}"
            echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
            echo "SUCCESS! Units were killed on iteration $ITERATION!" >> "$LOOP_LOG"
            exit 0
        fi
    else
        print_error "Claude did not write a status file for this iteration"
    fi

    # Check game logs directly
    KILL_FOUND=false
    for LOG_FILE in $(ls -t "$LOG_DIR"/debug_*.log 2>/dev/null | head -5); do
        if [ -n "$BEFORE_LOG" ] && [ "$LOG_FILE" = "$BEFORE_LOG" ]; then
            break
        fi
        if grep -qi "UNIT DESTROYED\|Model killed\|models destroyed\|casualties.*[1-9]" "$LOG_FILE" 2>/dev/null; then
            echo "KILL DETECTED in log: $LOG_FILE" >> "$LOOP_LOG"
            grep -i "UNIT DESTROYED\|Model killed\|models destroyed" "$LOG_FILE" | tail -5 >> "$LOOP_LOG"
            KILL_FOUND=true
            break
        fi
    done

    if [ "$KILL_FOUND" = true ]; then
        echo ""
        print_success "KILL DETECTED IN GAME LOGS on iteration $ITERATION!"
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  GOAL ACHIEVED! AI successfully destroyed a unit!    ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
        echo "SUCCESS! Units were killed on iteration $ITERATION!" >> "$LOOP_LOG"
        exit 0
    fi

    print_error "No kills detected this iteration"

    # Show summary of iterations so far
    echo ""
    print_status "Progress: $ITERATION/$MAX_ITERATIONS iterations complete | No kills yet"
    print_status "Starting next iteration in 5 seconds..."
    echo ""

    sleep 5
done

echo ""
print_error "Reached maximum iterations ($MAX_ITERATIONS) without achieving unit kills."
print_status "Check AI_IMPROVEMENT.md for the changes made across all iterations."
echo "Reached maximum iterations ($MAX_ITERATIONS) without achieving unit kills." >> "$LOOP_LOG"
exit 1

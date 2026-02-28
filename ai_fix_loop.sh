#!/bin/bash
# AI Competitive Improvement Loop
# Spawns a fresh Claude Code instance per iteration to avoid context exhaustion.
# Tracks wins, VP, and kills across iterations. Exits when both armies meet all criteria.
# Usage: caffeinate -dims ./ai_fix_loop.sh
# Stop with Ctrl+C

set -euo pipefail

MAX_ITERATIONS=50
ITERATION=0
PROJECT_DIR="/Users/robertocallaghan/Documents/claude/godotv2"
PROMPT_FILE="$PROJECT_DIR/ai_fix_loop_prompt.md"
LOOP_LOG="$PROJECT_DIR/ai_fix_loop_log.txt"
STATUS_FILE="$PROJECT_DIR/ai_loop_status.txt"
TRACKER_FILE="$PROJECT_DIR/ai_loop_tracker.json"
ITER_LOG_DIR="$PROJECT_DIR/ai_fix_loop_iterations"

# ── Success Criteria ──────────────────────────────────────────────────
REQUIRED_WINS=3          # Each player must win at least this many games
REQUIRED_VP=60           # Both players must score this many VP in qualifying games
REQUIRED_KILLS=5         # At least this many units destroyed in qualifying games

# ── Tracked State ─────────────────────────────────────────────────────
P1_QUALIFYING_WINS=0     # Games where P1 won AND both scored 60+ VP AND 5+ kills
P2_QUALIFYING_WINS=0     # Games where P2 won AND both scored 60+ VP AND 5+ kills
TOTAL_GAMES=0
TOTAL_STALLS=0

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}AI COMPETITIVE IMPROVEMENT LOOP${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Goal: Both players win ${REQUIRED_WINS}+ qualifying games                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Qualifying = both score ${REQUIRED_VP}+ VP, ${REQUIRED_KILLS}+ units destroyed              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Each iteration = fresh Claude Code instance                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOOP_LOG"
}

print_status()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $1"; }
print_success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $1${NC}"; }
print_error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $1${NC}"; }
print_metric()  { echo -e "${MAGENTA}[$(date '+%H:%M:%S')]   $1${NC}"; }

cleanup_godot() {
    pkill -f "godot.*--test-mode.*--ai-vs-ai" 2>/dev/null || true
    sleep 2
}

print_scoreboard() {
    echo ""
    echo -e "${CYAN}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}SCOREBOARD${NC}                                                  ${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  Games played: ${TOTAL_GAMES}    Stalls: ${TOTAL_STALLS}                               ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}                                                              ${CYAN}│${NC}"

    # P1 status
    if [ "$P1_QUALIFYING_WINS" -ge "$REQUIRED_WINS" ]; then
        echo -e "${CYAN}│${NC}  ${GREEN}P1 Custodes qualifying wins: ${P1_QUALIFYING_WINS}/${REQUIRED_WINS} ✓${NC}                       ${CYAN}│${NC}"
    else
        echo -e "${CYAN}│${NC}  ${YELLOW}P1 Custodes qualifying wins: ${P1_QUALIFYING_WINS}/${REQUIRED_WINS}${NC}                         ${CYAN}│${NC}"
    fi

    # P2 status
    if [ "$P2_QUALIFYING_WINS" -ge "$REQUIRED_WINS" ]; then
        echo -e "${CYAN}│${NC}  ${GREEN}P2 Orks qualifying wins:     ${P2_QUALIFYING_WINS}/${REQUIRED_WINS} ✓${NC}                       ${CYAN}│${NC}"
    else
        echo -e "${CYAN}│${NC}  ${YELLOW}P2 Orks qualifying wins:     ${P2_QUALIFYING_WINS}/${REQUIRED_WINS}${NC}                         ${CYAN}│${NC}"
    fi

    echo -e "${CYAN}│${NC}                                                              ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  Qualifying: both score ${REQUIRED_VP}+ VP, ${REQUIRED_KILLS}+ units destroyed           ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

check_goal_met() {
    if [ "$P1_QUALIFYING_WINS" -ge "$REQUIRED_WINS" ] && [ "$P2_QUALIFYING_WINS" -ge "$REQUIRED_WINS" ]; then
        return 0
    fi
    return 1
}

save_tracker() {
    cat > "$TRACKER_FILE" << JSONEOF
{
  "p1_qualifying_wins": $P1_QUALIFYING_WINS,
  "p2_qualifying_wins": $P2_QUALIFYING_WINS,
  "total_games": $TOTAL_GAMES,
  "total_stalls": $TOTAL_STALLS,
  "required_wins": $REQUIRED_WINS,
  "required_vp": $REQUIRED_VP,
  "required_kills": $REQUIRED_KILLS,
  "iterations_completed": $ITERATION,
  "last_updated": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "games": [$(cat "$TRACKER_FILE.games" 2>/dev/null || echo "")]
  }
JSONEOF
}

load_tracker() {
    if [ -f "$TRACKER_FILE" ]; then
        # Extract values using grep+sed (portable, no jq dependency)
        P1_QUALIFYING_WINS=$(grep '"p1_qualifying_wins"' "$TRACKER_FILE" | sed 's/[^0-9]//g' || echo "0")
        P2_QUALIFYING_WINS=$(grep '"p2_qualifying_wins"' "$TRACKER_FILE" | sed 's/[^0-9]//g' || echo "0")
        TOTAL_GAMES=$(grep '"total_games"' "$TRACKER_FILE" | sed 's/[^0-9]//g' || echo "0")
        TOTAL_STALLS=$(grep '"total_stalls"' "$TRACKER_FILE" | sed 's/[^0-9]//g' || echo "0")
        ITERATION=$(grep '"iterations_completed"' "$TRACKER_FILE" | sed 's/[^0-9]//g' || echo "0")

        # Default to 0 if extraction failed
        P1_QUALIFYING_WINS=${P1_QUALIFYING_WINS:-0}
        P2_QUALIFYING_WINS=${P2_QUALIFYING_WINS:-0}
        TOTAL_GAMES=${TOTAL_GAMES:-0}
        TOTAL_STALLS=${TOTAL_STALLS:-0}
        ITERATION=${ITERATION:-0}

        print_status "Resumed from tracker: P1=${P1_QUALIFYING_WINS} wins, P2=${P2_QUALIFYING_WINS} wins, ${TOTAL_GAMES} games, iteration ${ITERATION}"
    fi
}

append_game_record() {
    local winner="$1" p1_vp="$2" p2_vp="$3" kills="$4" p1_sec="$5" p2_sec="$6" qualifying="$7" iter="$8"
    local record="{\"iteration\":${iter},\"winner\":\"${winner}\",\"p1_vp\":${p1_vp},\"p2_vp\":${p2_vp},\"kills\":${kills},\"p1_secondaries\":${p1_sec},\"p2_secondaries\":${p2_sec},\"qualifying\":${qualifying}}"

    if [ -f "$TRACKER_FILE.games" ] && [ -s "$TRACKER_FILE.games" ]; then
        # Append with comma separator
        echo ",${record}" >> "$TRACKER_FILE.games"
    else
        echo "${record}" > "$TRACKER_FILE.games"
    fi
}

# ── Setup ─────────────────────────────────────────────────────────────
mkdir -p "$ITER_LOG_DIR"
touch "$TRACKER_FILE.games" 2>/dev/null || true
print_banner

# Load previous state if resuming
load_tracker

# Check if already done
if check_goal_met; then
    print_success "Goal already met from previous runs!"
    print_scoreboard
    exit 0
fi

echo "================================================================" >> "$LOOP_LOG"
echo "  AI Competitive Loop Started/Resumed at $(date)" >> "$LOOP_LOG"
echo "  P1 wins: $P1_QUALIFYING_WINS, P2 wins: $P2_QUALIFYING_WINS" >> "$LOOP_LOG"
echo "  Max iterations: $MAX_ITERATIONS" >> "$LOOP_LOG"
echo "================================================================" >> "$LOOP_LOG"

print_status "Max iterations: $MAX_ITERATIONS"
print_status "Per-iteration logs: $ITER_LOG_DIR/"
print_status "Tracker: $TRACKER_FILE"
print_scoreboard

# Read the prompt file
if [ ! -f "$PROMPT_FILE" ]; then
    print_error "Prompt file not found: $PROMPT_FILE"
    exit 1
fi
PROMPT=$(cat "$PROMPT_FILE")

# ── Main Loop ─────────────────────────────────────────────────────────
while [ $ITERATION -lt $MAX_ITERATIONS ]; do
    ITERATION=$((ITERATION + 1))
    ITER_START=$(date +%s)
    ITER_LOGFILE="$ITER_LOG_DIR/iteration_${ITERATION}_$(date '+%Y%m%d_%H%M%S').txt"

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  ITERATION $ITERATION / $MAX_ITERATIONS — $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

    log "──────────────────────────────────────────────"
    log "ITERATION $ITERATION / $MAX_ITERATIONS"
    log "──────────────────────────────────────────────"

    # Clean up before starting
    print_status "Killing any leftover godot processes..."
    cleanup_godot

    # Clear status file
    rm -f "$STATUS_FILE"

    # Save tracker so Claude can read it
    save_tracker

    # ── Launch Claude Code ────────────────────────────────────────────
    print_status "Spawning fresh Claude Code instance (iteration $ITERATION)..."
    print_status "  Output → $ITER_LOGFILE"
    print_status "  This will take several minutes..."
    echo ""

    cd "$PROJECT_DIR"
    claude -p \
        --dangerously-skip-permissions \
        --model opus \
        --verbose \
        "$PROMPT" > "$ITER_LOGFILE" 2>&1 || {
        EXITCODE=$?
        log "Claude exited with code $EXITCODE"
        print_error "Claude exited with code $EXITCODE"
    }

    # ── Post-iteration Analysis ───────────────────────────────────────
    ITER_END=$(date +%s)
    ITER_DURATION=$(( ITER_END - ITER_START ))
    ITER_MINS=$(( ITER_DURATION / 60 ))
    ITER_SECS=$(( ITER_DURATION % 60 ))

    log "Iteration $ITERATION completed in ${ITER_MINS}m ${ITER_SECS}s"
    print_status "Iteration $ITERATION finished (${ITER_MINS}m ${ITER_SECS}s)"

    # Kill any godot processes Claude may have left running
    cleanup_godot

    # ── Parse Status File ─────────────────────────────────────────────
    if [ -f "$STATUS_FILE" ]; then
        log "Status file contents:"
        log "$(cat "$STATUS_FILE")"

        # Parse each GAME: line
        while IFS= read -r line; do
            if echo "$line" | grep -q "^GAME:"; then
                TOTAL_GAMES=$((TOTAL_GAMES + 1))

                # Extract fields
                WINNER=$(echo "$line" | grep -o 'winner=[^ ]*' | cut -d= -f2 || echo "UNKNOWN")
                P1_VP=$(echo "$line" | grep -o 'p1_vp=[^ ]*' | cut -d= -f2 || echo "0")
                P2_VP=$(echo "$line" | grep -o 'p2_vp=[^ ]*' | cut -d= -f2 || echo "0")
                KILLS=$(echo "$line" | grep -o 'kills=[^ ]*' | cut -d= -f2 || echo "0")
                P1_SEC=$(echo "$line" | grep -o 'p1_secondaries=[^ ]*' | cut -d= -f2 || echo "0")
                P2_SEC=$(echo "$line" | grep -o 'p2_secondaries=[^ ]*' | cut -d= -f2 || echo "0")

                # Default to 0 if empty
                P1_VP=${P1_VP:-0}
                P2_VP=${P2_VP:-0}
                KILLS=${KILLS:-0}
                P1_SEC=${P1_SEC:-0}
                P2_SEC=${P2_SEC:-0}

                print_status "Game result: Winner=${WINNER} P1_VP=${P1_VP} P2_VP=${P2_VP} Kills=${KILLS} P1_Sec=${P1_SEC} P2_Sec=${P2_SEC}"

                # Check if this is a qualifying game
                QUALIFYING=false
                if [ "$P1_VP" -ge "$REQUIRED_VP" ] 2>/dev/null && \
                   [ "$P2_VP" -ge "$REQUIRED_VP" ] 2>/dev/null && \
                   [ "$KILLS" -ge "$REQUIRED_KILLS" ] 2>/dev/null; then
                    QUALIFYING=true
                    print_success "QUALIFYING GAME! (Both ${REQUIRED_VP}+ VP, ${REQUIRED_KILLS}+ kills)"

                    if [ "$WINNER" = "P1" ]; then
                        P1_QUALIFYING_WINS=$((P1_QUALIFYING_WINS + 1))
                        print_success "P1 Custodes qualifying win #${P1_QUALIFYING_WINS}"
                    elif [ "$WINNER" = "P2" ]; then
                        P2_QUALIFYING_WINS=$((P2_QUALIFYING_WINS + 1))
                        print_success "P2 Orks qualifying win #${P2_QUALIFYING_WINS}"
                    else
                        print_status "Qualifying game but no clear winner (draw or unknown)"
                    fi
                else
                    print_status "Non-qualifying:"
                    [ "$P1_VP" -lt "$REQUIRED_VP" ] 2>/dev/null && print_metric "P1 VP ${P1_VP} < ${REQUIRED_VP} required"
                    [ "$P2_VP" -lt "$REQUIRED_VP" ] 2>/dev/null && print_metric "P2 VP ${P2_VP} < ${REQUIRED_VP} required"
                    [ "$KILLS" -lt "$REQUIRED_KILLS" ] 2>/dev/null && print_metric "Kills ${KILLS} < ${REQUIRED_KILLS} required"
                fi

                append_game_record "$WINNER" "$P1_VP" "$P2_VP" "$KILLS" "$P1_SEC" "$P2_SEC" "$QUALIFYING" "$ITERATION"
                log "Game: winner=$WINNER p1_vp=$P1_VP p2_vp=$P2_VP kills=$KILLS qualifying=$QUALIFYING"

            elif echo "$line" | grep -q "^STALL:"; then
                TOTAL_STALLS=$((TOTAL_STALLS + 1))
                print_error "Stall reported: $line"
                log "Stall: $line"

            elif echo "$line" | grep -q "^SUMMARY:"; then
                SUMMARY=$(echo "$line" | sed 's/^SUMMARY: //')
                print_status "Summary: $SUMMARY"
                log "Summary: $SUMMARY"
            fi
        done < "$STATUS_FILE"
    else
        print_error "No status file written this iteration"
        log "No status file written"

        if [ -f "$ITER_LOGFILE" ]; then
            log "Last 20 lines of iteration output:"
            log "$(tail -20 "$ITER_LOGFILE" 2>/dev/null || echo "(could not read)")"
        fi
    fi

    # ── Save Tracker ──────────────────────────────────────────────────
    save_tracker

    # ── Print Scoreboard ──────────────────────────────────────────────
    print_scoreboard

    # ── Check if Goal Met ─────────────────────────────────────────────
    if check_goal_met; then
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                                                                ║${NC}"
        echo -e "${GREEN}║   GOAL ACHIEVED on iteration $ITERATION!                                ║${NC}"
        echo -e "${GREEN}║                                                                ║${NC}"
        echo -e "${GREEN}║   P1 Custodes: ${P1_QUALIFYING_WINS} qualifying wins                              ║${NC}"
        echo -e "${GREEN}║   P2 Orks:     ${P2_QUALIFYING_WINS} qualifying wins                              ║${NC}"
        echo -e "${GREEN}║                                                                ║${NC}"
        echo -e "${GREEN}║   Both armies can win competitive games with ${REQUIRED_VP}+ VP            ║${NC}"
        echo -e "${GREEN}║   and ${REQUIRED_KILLS}+ units destroyed!                                      ║${NC}"
        echo -e "${GREEN}║                                                                ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        log "SUCCESS! Goal achieved on iteration $ITERATION. P1=${P1_QUALIFYING_WINS} P2=${P2_QUALIFYING_WINS}"
        exit 0
    fi

    # ── Guidance for next iteration ───────────────────────────────────
    if [ "$P1_QUALIFYING_WINS" -lt "$REQUIRED_WINS" ] && [ "$P2_QUALIFYING_WINS" -ge "$REQUIRED_WINS" ]; then
        print_status "P2 Orks have enough wins. Focus next iteration on improving P1 Custodes."
    elif [ "$P2_QUALIFYING_WINS" -lt "$REQUIRED_WINS" ] && [ "$P1_QUALIFYING_WINS" -ge "$REQUIRED_WINS" ]; then
        print_status "P1 Custodes have enough wins. Focus next iteration on improving P2 Orks."
    fi

    echo ""
    print_status "Iterations: $ITERATION/$MAX_ITERATIONS"
    if [ $ITERATION -lt $MAX_ITERATIONS ]; then
        print_status "Next iteration in 5 seconds... (Ctrl+C to stop)"
        sleep 5
    fi
done

# ── Loop Exhausted ────────────────────────────────────────────────────
echo ""
print_error "Reached maximum iterations ($MAX_ITERATIONS) without achieving goal."
print_scoreboard
print_status "Check AI_STALL_FIXES.md and $ITER_LOG_DIR/ for details."
log "Reached maximum iterations. P1=${P1_QUALIFYING_WINS}/${REQUIRED_WINS} P2=${P2_QUALIFYING_WINS}/${REQUIRED_WINS}"
exit 1

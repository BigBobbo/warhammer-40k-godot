#!/usr/bin/env bash
###############################################################################
# run_audit_tasks.sh — Automated ABILITIES_AUDIT.md task runner using Claude Code
#
# Parses open tasks from ABILITIES_AUDIT.md Priority Recommendations, loops
# through them one-by-one, launching a fresh Claude Code session for each.
# Claude implements the task, updates the audit file, commits, and merges to
# main before the next task starts.
#
# Tasks are numbered 1-35 under priority headers (P0-P3).
# Task IDs use the format P{priority}-{number} (e.g. P0-1, P1-8, P2-19).
#
# Designed to run locally on macOS.
#
# Usage:
#   ./run_audit_tasks.sh [options]
#
# Options:
#   --dry-run            Show tasks that would be processed without executing
#   --start-from ID      Start from a specific task ID (e.g. P0-1, P1-8)
#   --priority N         Only run tasks from priority N (0-3)
#   --max-tasks N        Stop after processing N tasks
#   --skip ID[,ID,...]   Skip specific task IDs (comma-separated)
#   --skip-failed        Skip tasks that previously failed (from state file)
#   --resume             Resume from last incomplete task in state file
#   --list               List all open tasks and exit
#   --no-merge           Skip merging to main (leave on feature branch)
#   --model MODEL        Claude model to use (default: sonnet)
#   --timeout SECS       Max seconds per task before killing (default: 1800)
#   --help               Show this help
#
###############################################################################
set -euo pipefail

# Prevent git from opening an interactive editor for merge commits
export GIT_MERGE_AUTOEDIT=no

# ─── Configuration ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
AUDIT_FILE="$PROJECT_DIR/ABILITIES_AUDIT.md"
STATE_FILE="$PROJECT_DIR/.audit_runner_state"
STOP_FILE="$PROJECT_DIR/.audit_runner_stop"
LOG_DIR="$PROJECT_DIR/.audit_logs"
MAIN_BRANCH="main"
CLAUDE_MODEL="sonnet"
TASK_TIMEOUT=21600  # seconds (6 hours)

# CLI flags
DRY_RUN=false
START_FROM=""
TIER_FILTER=""
MAX_TASKS=0
SKIP_IDS=""
SKIP_FAILED=false
RESUME=false
LIST_ONLY=false
NO_MERGE=false

# Runtime state
TASKS_PROCESSED=0
TASKS_SUCCEEDED=0
TASKS_FAILED=0
CURRENT_TASK_ID=""

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── Helpers ─────────────────────────────────────────────────────────────────
log()      { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${NC} $*"; }
log_err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✗${NC} $*"; }
log_task() { echo -e "${BOLD}${BLUE}[$(date '+%H:%M:%S')] ▶${NC} $*"; }

die() { log_err "$@"; exit 1; }

# Recursively kill a process and all its descendants
kill_process_tree() {
    local pid="$1"
    local sig="${2:-TERM}"
    # Find children before killing the parent
    local children
    children=$(pgrep -P "$pid" 2>/dev/null || true)
    for child in $children; do
        kill_process_tree "$child" "$sig"
    done
    kill -"$sig" "$pid" 2>/dev/null || true
}

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \?//'
    sed -n '/^# Options:/,/^#\{2,\}/p' "$0" | sed 's/^# \?//' | head -n -1
    exit 0
}

# ─── CLI Argument Parsing ────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)      DRY_RUN=true ;;
            --start-from)   START_FROM="$2"; shift ;;
            --priority)     TIER_FILTER="$2"; shift ;;
            --tier)         TIER_FILTER="$2"; shift ;;
            --max-tasks)    MAX_TASKS="$2"; shift ;;
            --skip)         SKIP_IDS="$2"; shift ;;
            --skip-failed)  SKIP_FAILED=true ;;
            --resume)       RESUME=true ;;
            --list)         LIST_ONLY=true ;;
            --no-merge)     NO_MERGE=true ;;
            --model)        CLAUDE_MODEL="$2"; shift ;;
            --timeout)      TASK_TIMEOUT="$2"; shift ;;
            --help|-h)      usage ;;
            *)              die "Unknown option: $1 (use --help)" ;;
        esac
        shift
    done
}

# ─── State Management ────────────────────────────────────────────────────────

# State file format: one line per task attempt
#   TASK_ID|STATUS|TIMESTAMP|BRANCH
# STATUS: success, failed, skipped

save_state() {
    local task_id="$1" status="$2" branch="${3:-}"
    echo "${task_id}|${status}|$(date -u '+%Y-%m-%dT%H:%M:%SZ')|${branch}" >> "$STATE_FILE"
}

get_last_incomplete() {
    # Returns the task ID after the last successfully completed task
    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return
    fi
    local last_success
    last_success=$(grep '|success|' "$STATE_FILE" 2>/dev/null | tail -1 | cut -d'|' -f1)
    echo "$last_success"
}

was_task_completed() {
    local task_id="$1"
    if [[ ! -f "$STATE_FILE" ]]; then
        return 1
    fi
    grep -q "^${task_id}|success|" "$STATE_FILE" 2>/dev/null
}

# Returns comma-separated list of task IDs that have failed/merge_failed but no success
get_failed_task_ids() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return
    fi
    # Get all task IDs that failed or merge_failed
    local failed_ids
    failed_ids=$(grep -E '\|(failed|merge_failed)\|' "$STATE_FILE" 2>/dev/null | cut -d'|' -f1 | sort -u)
    # Exclude any that also have a success entry
    local result=""
    for tid in $failed_ids; do
        if ! grep -q "^${tid}|success|" "$STATE_FILE" 2>/dev/null; then
            if [[ -n "$result" ]]; then
                result="${result},${tid}"
            else
                result="$tid"
            fi
        fi
    done
    echo "$result"
}

# ─── Task Parsing ────────────────────────────────────────────────────────────

# Extracts all open tasks from ABILITIES_AUDIT.md Priority Recommendations.
# Tasks are numbered lines under ### P{n} headers, e.g.:
#   ### P0 — Critical (abilities that claim to work but don't)
#   1. **Fix ChargePhase to check advance_and_charge flag** — Martial Inspiration
#
# Output format: TASK_ID<TAB>TASK_TITLE
# Task IDs are constructed as P{priority}-{number} (e.g. P0-1, P1-8)
parse_all_tasks() {
    local current_priority=""

    while IFS= read -r line; do
        # Detect priority header: ### P0, ### P1, ### P2, ### P3
        if printf '%s' "$line" | grep -qE '^### P[0-9]'; then
            current_priority=$(printf '%s' "$line" | grep -oE 'P[0-9]' | head -1 | sed 's/P//')
            continue
        fi

        # Skip if we haven't found a priority header yet
        [[ -z "$current_priority" ]] && continue

        # Stop if we hit a section break (next ## or ---)
        if printf '%s' "$line" | grep -qE '^(## |---)'; then
            break
        fi

        # Match numbered task lines: "1. **Task title** — description"
        if printf '%s' "$line" | grep -qE '^[0-9]+\. \*\*'; then
            # Skip DONE tasks
            if printf '%s' "$line" | grep -qE '\*\*DONE\*\*|~~.*~~'; then
                continue
            fi

            local task_num task_title task_id
            task_num=$(printf '%s' "$line" | grep -oE '^[0-9]+')
            task_id="P${current_priority}-${task_num}"
            # Extract the full line minus the leading number and period
            task_title=$(printf '%s' "$line" | sed 's/^[0-9]*\. //')
            printf '%s\t%s\n' "$task_id" "$task_title"
        fi
    done < "$AUDIT_FILE"
}

# Extracts the full context for a given task from ABILITIES_AUDIT.md.
# Task ID format: P{priority}-{number} (e.g. P0-1, P1-8)
# Returns: the priority header, the task line itself, and all related
# sections from earlier in the file that provide background context.
get_task_context() {
    local task_id="$1"

    # Parse priority and task number from ID
    local priority task_num
    priority=$(echo "$task_id" | sed 's/P\([0-9]\)-.*/\1/')
    task_num=$(echo "$task_id" | sed 's/P[0-9]-//')

    # Find the priority header text
    local priority_header
    priority_header=$(grep -E "^### P${priority} " "$AUDIT_FILE" | head -1)

    # Find the task line itself
    local task_line
    task_line=$(awk "
        /^### P${priority} / { in_section=1; next }
        in_section && /^### P[0-9]/ { in_section=0 }
        in_section && /^(## |---)/ { in_section=0 }
        in_section && /^${task_num}\. / { print; exit }
    " "$AUDIT_FILE")

    if [[ -z "$task_line" ]]; then
        echo "Task ${task_id} not found in audit file."
        return
    fi

    # Extract key terms from the task to find related context sections.
    # Look for ability names, unit names, or system names mentioned in the task.
    local related_context=""

    # Always include the Broken Pipeline section for P0 tasks (they're about broken flags)
    if [[ "$priority" == "0" ]]; then
        related_context+=$(awk '
            /^## Broken Pipeline/ { found=1 }
            found && /^---/ { found=0 }
            found { print }
        ' "$AUDIT_FILE")
        related_context+=$'\n\n'
    fi

    # Include the relevant unit gap tables by scanning for ability/unit names in the task line
    # Check each faction section for mentions of terms in the task
    for section in "Orks — Unit Ability Gaps" "Adeptus Custodes — Unit Ability Gaps" "Space Marines — Unit Ability Gaps" "Faction Abilities" "Core Abilities Audit" "Once Per Battle"; do
        local section_escaped
        section_escaped=$(printf '%s' "$section" | sed 's/[.*+?^${}()|[\]\\]/\\&/g')
        # Check if any key terms from the task line appear in this section
        local section_content
        section_content=$(awk -v sec="$section" '
            $0 ~ "^## " sec { found=1; next }
            found && /^---/ { found=0 }
            found && /^## / { found=0 }
            found { print }
        ' "$AUDIT_FILE")

        if [[ -n "$section_content" ]]; then
            related_context+="## ${section}"$'\n'
            related_context+="$section_content"$'\n\n'
        fi
    done

    # Build the full context
    echo "TASK: ${task_id}"
    echo "${priority_header}"
    echo ""
    echo "Task: ${task_line}"
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "RELATED CONTEXT FROM ABILITIES_AUDIT.md"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "$related_context"
}

# Get the priority number from a task ID (P0-1 -> 0, P1-8 -> 1, etc.)
get_tier() {
    local task_id="$1"
    echo "$task_id" | grep -oE '^P[0-9]' | sed 's/P//'
}

# ─── Branch Management ───────────────────────────────────────────────────────

sanitize_branch_name() {
    local task_id="$1"
    local title="$2"
    # Create a short, clean branch name from task ID and title
    local slug
    slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)
    echo "audit/${task_id}/${slug}"
}

create_feature_branch() {
    local branch_name="$1"
    log "Creating branch: ${branch_name}"

    # Make sure we're on main and up to date
    git -C "$PROJECT_DIR" checkout "$MAIN_BRANCH" 2>/dev/null
    git -C "$PROJECT_DIR" pull --no-edit origin "$MAIN_BRANCH" 2>/dev/null || true

    # If the branch already exists (stale from a previous failed run), delete it
    # so we get a clean start from main
    if git -C "$PROJECT_DIR" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        log_warn "Deleting stale branch: ${branch_name}"
        git -C "$PROJECT_DIR" branch -D "$branch_name" 2>/dev/null || true
    fi

    # Create and switch to the fresh feature branch
    git -C "$PROJECT_DIR" checkout -b "$branch_name"
}

merge_to_main() {
    local branch_name="$1"
    local task_id="$2"

    log "Merging ${branch_name} into ${MAIN_BRANCH}..."

    # Check if there are any commits on this branch that aren't on main
    local commits_ahead
    commits_ahead=$(git -C "$PROJECT_DIR" rev-list "${MAIN_BRANCH}..${branch_name}" --count 2>/dev/null || echo "0")

    if [[ "$commits_ahead" -eq 0 ]]; then
        log_warn "No new commits on ${branch_name} — nothing to merge"
        return 1
    fi

    git -C "$PROJECT_DIR" checkout "$MAIN_BRANCH"
    if git -C "$PROJECT_DIR" merge "$branch_name" --no-ff -m "Merge audit task ${task_id}: ${branch_name}"; then
        log_ok "Merged ${branch_name} into ${MAIN_BRANCH} (${commits_ahead} commits)"
        # Delete the feature branch
        git -C "$PROJECT_DIR" branch -d "$branch_name" 2>/dev/null || true
        return 0
    else
        log_err "Merge conflict! Aborting merge for ${task_id}"
        git -C "$PROJECT_DIR" merge --abort 2>/dev/null || true
        git -C "$PROJECT_DIR" checkout "$MAIN_BRANCH" 2>/dev/null || true
        return 1
    fi
}

# ─── Claude Code Invocation ──────────────────────────────────────────────────

build_prompt() {
    local task_id="$1"
    local task_title="$2"
    local task_context="$3"

    cat <<PROMPT_EOF
You are working on a Warhammer 40k tabletop game implemented in Godot 4.4 (GDScript).
Your job is to implement one specific ability task from the project's ABILITIES_AUDIT.md.

═══════════════════════════════════════════════════════
TASK: ${task_id} — ${task_title}
═══════════════════════════════════════════════════════

Full task details from the audit:
---
${task_context}
---

═══════════════════════════════════════════════════════
INSTRUCTIONS
═══════════════════════════════════════════════════════

1. READ the relevant source files mentioned in the task details above.
   Understand the existing code patterns before making changes.
   Key files to check:
   - 40k/autoloads/UnitAbilityManager.gd (ABILITY_EFFECTS table, ability application)
   - 40k/autoloads/FactionAbilityManager.gd (faction abilities like Oath of Moment)
   - 40k/autoloads/EffectPrimitives.gd (effect flag system)
   - 40k/phases/ChargePhase.gd (charge eligibility checks)
   - 40k/phases/ShootingPhase.gd (shooting eligibility checks)
   - 40k/phases/FightPhase.gd (fight phase logic)
   - 40k/autoloads/RulesEngine.gd (combat resolution, rerolls, saves)
   - 40k/armies/*.json (unit data with abilities)

2. IMPLEMENT the required changes:
   - Follow existing code style and patterns in the codebase
   - Do NOT remove debugging logs (project rule)
   - Keep changes focused — only implement what this task requires
   - Reference the 10th Edition core rules at https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
   - Reference specific unit datasheets on wahapedia when implementing unit-specific abilities
   - Reference Godot 4.4 docs at https://docs.godotengine.org/en/4.4/
   - Be careful not to introduce regressions in other phases
   - Ensure any new logic has consistent behavior across both the interactive
     resolution path and auto-resolve path in RulesEngine.gd (if applicable)

3. UPDATE ABILITIES_AUDIT.md to reflect completion:
   a. In the Priority Recommendations section, append **DONE** to the task line
      (e.g., change "1. **Fix ChargePhase...**" to "1. **Fix ChargePhase...** — **DONE**")
   b. Update the Summary table: decrement the relevant count
   c. If the task fixed an item in the "Implementation Status of ABILITY_EFFECTS Table",
      update the "Actually Working" column to reflect the new status

4. COMMIT all changes with a clear message in this format:
      Implement ${task_id}: <short description>

      <brief explanation of what was changed and why>

5. Do NOT push — the runner script handles that.

═══════════════════════════════════════════════════════
IMPORTANT NOTES
═══════════════════════════════════════════════════════
- The project path is the current working directory
- If a task depends on another task, implement what you can and note any
  limitations. Do NOT skip the task entirely.
- If a task references specific line numbers, verify them first — they may have
  shifted since the audit was written.
- For abilities that need army JSON changes AND code changes, do both.
- For abilities marked as "simplified" that need fixing, update both the
  ABILITY_EFFECTS entry and the EffectPrimitives flag handling.
PROMPT_EOF
}

run_claude() {
    local prompt="$1"
    local log_file="$2"
    local exit_code=0

    log "Launching Claude Code session (timeout: ${TASK_TIMEOUT}s)..."

    # Use --print mode with --dangerously-skip-permissions for full automation.
    # This gives Claude access to all tools without interactive permission prompts.
    #
    # For a safer (but slower) alternative that prompts for each tool use, remove
    # --dangerously-skip-permissions and use --allowedTools instead:
    #   claude --print --allowedTools "Read" "Write" "Edit" "Glob" "Grep" \
    #          "Bash(git status:*)" "Bash(git add:*)" "Bash(git commit:*)" \
    #          --model "$CLAUDE_MODEL" -p "$prompt"

    # Write prompt to temp file to avoid shell escaping issues
    local prompt_file
    prompt_file=$(mktemp)
    echo "$prompt" > "$prompt_file"

    # Run claude in a background subshell so we can enforce a timeout
    (
        claude --print \
            --dangerously-skip-permissions \
            --model "$CLAUDE_MODEL" \
            --verbose \
            -p "$(cat "$prompt_file")" \
            2>&1 | tee "$log_file"
    ) &
    local claude_pid=$!

    # Poll until completion or timeout, printing progress updates
    local elapsed=0
    local poll_interval=5
    local status_interval=30  # print status every 30s
    local last_status=0
    local last_log_size=0
    while kill -0 "$claude_pid" 2>/dev/null; do
        if [[ "$elapsed" -ge "$TASK_TIMEOUT" ]]; then
            log_err "TIMEOUT: Claude session exceeded ${TASK_TIMEOUT}s — killing process tree"
            kill_process_tree "$claude_pid"
            # Give processes a moment to die, then SIGKILL stragglers
            sleep 2
            kill_process_tree "$claude_pid" "KILL"
            wait "$claude_pid" 2>/dev/null || true
            rm -f "$prompt_file"
            return 1
        fi

        # Print progress update every status_interval seconds
        if [[ $((elapsed - last_status)) -ge "$status_interval" && "$elapsed" -gt 0 ]]; then
            local mins=$((elapsed / 60))
            local secs=$((elapsed % 60))
            local remaining=$(( (TASK_TIMEOUT - elapsed) / 60 ))
            local cur_log_size=0
            if [[ -f "$log_file" ]]; then
                cur_log_size=$(wc -c < "$log_file" 2>/dev/null | tr -d ' ')
            fi

            # Count child processes (godot tests, etc.)
            local child_count
            child_count=$(pgrep -P "$claude_pid" 2>/dev/null | wc -l | tr -d ' ')

            # Build status line
            local activity=""
            if [[ "$cur_log_size" -gt "$last_log_size" ]]; then
                activity="output growing"
            elif [[ "$child_count" -gt 0 ]]; then
                # Check if any godot tests are running
                local godot_test
                godot_test=$(pgrep -lf "godot.*--headless" 2>/dev/null | grep -oE 'test_[a-z_]+' | tail -1 || true)
                if [[ -n "$godot_test" ]]; then
                    activity="running ${godot_test}"
                else
                    activity="${child_count} subprocess(es) active"
                fi
            else
                activity="waiting for output"
            fi

            printf "  ${CYAN}⏳ [%dm%02ds elapsed, %dm remaining] %s${NC}\n" \
                "$mins" "$secs" "$remaining" "$activity"

            last_log_size="$cur_log_size"
            last_status="$elapsed"
        fi

        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
    done

    wait "$claude_pid" 2>/dev/null || exit_code=$?

    rm -f "$prompt_file"

    if [[ $exit_code -ne 0 ]]; then
        log_err "Claude exited with code ${exit_code}"
        return 1
    fi

    # Verify that claude actually made changes
    local changes
    changes=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    local staged
    staged=$(git -C "$PROJECT_DIR" diff --cached --stat 2>/dev/null | wc -l | tr -d ' ')
    local new_commits
    new_commits=$(git -C "$PROJECT_DIR" log "${MAIN_BRANCH}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$changes" -eq 0 && "$staged" -eq 0 && "$new_commits" -eq 0 ]]; then
        log_warn "Claude session completed but no changes were made"
        return 1
    fi

    # If there are uncommitted changes, commit them (claude should have committed, but safety net)
    if [[ "$changes" -gt 0 || "$staged" -gt 0 ]]; then
        log_warn "Found uncommitted changes — creating safety commit"
        git -C "$PROJECT_DIR" add -A
        git -C "$PROJECT_DIR" commit -m "Auto-commit: remaining changes from ${CURRENT_TASK_ID}" || true
    fi

    log_ok "Claude session completed with changes"
    return 0
}

# ─── Single Task Execution ───────────────────────────────────────────────────

run_single_task() {
    local task_id="$1"
    local task_title="$2"
    local current_num="${3:-0}"
    local total_num="${4:-0}"
    CURRENT_TASK_ID="$task_id"

    local tier
    tier=$(get_tier "$task_id")

    local progress=""
    if [[ "$total_num" -gt 0 ]]; then
        local remaining=$((total_num - current_num + 1))
        progress=" [${current_num}/${total_num} — ${remaining} remaining]"
    fi

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    log_task "TASK ${task_id} (Priority ${tier})${progress}"
    echo -e "  ${task_title}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"

    # Skip if already completed
    if was_task_completed "$task_id"; then
        log "Already completed (in state file) — skipping"
        return 0
    fi

    # Get full context
    local task_context
    task_context=$(get_task_context "$task_id")

    if [[ -z "$task_context" || "$task_context" == *"not found"* ]]; then
        log_err "Could not extract task context for ${task_id}"
        save_state "$task_id" "failed" ""
        return 1
    fi

    # Create branch
    local branch_name
    branch_name=$(sanitize_branch_name "$task_id" "$task_title")

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would create branch: ${branch_name}"
        log "[DRY RUN] Would launch Claude Code for task ${task_id}"
        echo ""
        echo "Task context:"
        echo "$task_context"
        echo ""
        return 0
    fi

    create_feature_branch "$branch_name"

    # Build prompt
    local prompt
    prompt=$(build_prompt "$task_id" "$task_title" "$task_context")

    # Create log file
    mkdir -p "$LOG_DIR"
    local log_file="${LOG_DIR}/${task_id}_$(date '+%Y%m%d_%H%M%S').log"

    # Run Claude
    if run_claude "$prompt" "$log_file"; then
        log_ok "Task ${task_id} implementation complete"

        if [[ "$NO_MERGE" == true ]]; then
            log "Skipping merge (--no-merge flag)"
            save_state "$task_id" "success" "$branch_name"
        else
            if merge_to_main "$branch_name" "$task_id"; then
                save_state "$task_id" "success" "$branch_name"
                TASKS_SUCCEEDED=$((TASKS_SUCCEEDED + 1))
            else
                log_err "Merge failed for ${task_id} — branch preserved: ${branch_name}"
                save_state "$task_id" "merge_failed" "$branch_name"
                git -C "$PROJECT_DIR" checkout "$MAIN_BRANCH" 2>/dev/null || true
                TASKS_FAILED=$((TASKS_FAILED + 1))
                return 1
            fi
        fi
    else
        log_err "Claude session failed for ${task_id}"
        save_state "$task_id" "failed" "$branch_name"
        git -C "$PROJECT_DIR" checkout "$MAIN_BRANCH" 2>/dev/null || true
        TASKS_FAILED=$((TASKS_FAILED + 1))
        return 1
    fi

    TASKS_PROCESSED=$((TASKS_PROCESSED + 1))
    return 0
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    # Sanity checks
    [[ -f "$AUDIT_FILE" ]] || die "ABILITIES_AUDIT.md not found at: ${AUDIT_FILE}"
    command -v claude >/dev/null 2>&1 || die "Claude Code CLI not found. Install: npm install -g @anthropic-ai/claude-code"
    command -v git >/dev/null 2>&1 || die "git not found"

    # Prevent macOS from sleeping while the runner is active.
    # -d = prevent display sleep, -i = prevent idle sleep, -s = prevent system sleep
    if command -v caffeinate >/dev/null 2>&1; then
        caffeinate -dis -w $$ &
        CAFFEINATE_PID=$!
        trap 'kill $CAFFEINATE_PID 2>/dev/null || true' EXIT
        log "Sleep prevention active (caffeinate PID: ${CAFFEINATE_PID})"
    else
        log_warn "caffeinate not found — laptop may sleep during long runs"
    fi

    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   ABILITIES AUDIT TASK RUNNER — Claude Code          ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Parse all open tasks
    local tasks_raw
    tasks_raw=$(parse_all_tasks)

    if [[ -z "$tasks_raw" ]]; then
        log_ok "No open tasks found in ABILITIES_AUDIT.md — all done!"
        exit 0
    fi

    # Apply filters
    local tasks_filtered=""
    local found_start=false
    [[ -z "$START_FROM" ]] && found_start=true

    # If --skip-failed, merge failed task IDs into SKIP_IDS
    if [[ "$SKIP_FAILED" == true ]]; then
        local failed_ids
        failed_ids=$(get_failed_task_ids)
        if [[ -n "$failed_ids" ]]; then
            if [[ -n "$SKIP_IDS" ]]; then
                SKIP_IDS="${SKIP_IDS},${failed_ids}"
            else
                SKIP_IDS="$failed_ids"
            fi
            log "Skipping previously failed tasks: ${failed_ids}"
        else
            log "No previously failed tasks to skip"
        fi
    fi

    # If --resume, find where we left off
    if [[ "$RESUME" == true ]]; then
        local last_done
        last_done=$(get_last_incomplete)
        if [[ -n "$last_done" ]]; then
            START_FROM="$last_done"
            found_start=false
            log "Resuming after last completed task: ${last_done}"
        fi
    fi

    while IFS=$'\t' read -r task_id task_title; do
        [[ -z "$task_id" ]] && continue

        # --start-from: skip until we find (and pass) the start task
        if [[ "$found_start" == false ]]; then
            if [[ "$task_id" == "$START_FROM" ]]; then
                found_start=true
                # If resuming, skip the start task itself (it was already done)
                if [[ "$RESUME" == true ]]; then
                    continue
                fi
            else
                continue
            fi
        fi

        # --tier filter
        if [[ -n "$TIER_FILTER" ]]; then
            local tier
            tier=$(get_tier "$task_id")
            if [[ "$tier" != "$TIER_FILTER" ]]; then
                continue
            fi
        fi

        # --skip filter
        if [[ -n "$SKIP_IDS" ]]; then
            if echo ",$SKIP_IDS," | grep -q ",${task_id},"; then
                continue
            fi
        fi

        tasks_filtered+="${task_id}"$'\t'"${task_title}"$'\n'
    done <<< "$tasks_raw"

    # Count tasks
    local task_count
    task_count=$(printf '%s' "$tasks_filtered" | grep -c '\S' || true)

    if [[ "$task_count" -eq 0 ]]; then
        log_ok "No tasks match the current filters"
        exit 0
    fi

    # Apply --max-tasks
    if [[ "$MAX_TASKS" -gt 0 && "$task_count" -gt "$MAX_TASKS" ]]; then
        task_count="$MAX_TASKS"
    fi

    log "Found ${task_count} open task(s) to process"
    echo ""

    # ── List mode ──
    if [[ "$LIST_ONLY" == true ]]; then
        echo -e "${BOLD}Open Tasks:${NC}"
        echo ""
        local idx=0
        while IFS=$'\t' read -r -u 3 task_id task_title; do
            [[ -z "$task_id" ]] && continue
            idx=$((idx + 1))
            if [[ "$MAX_TASKS" -gt 0 && "$idx" -gt "$MAX_TASKS" ]]; then
                break
            fi
            local tier
            tier=$(get_tier "$task_id")
            local color="$NC"
            case "$tier" in
                0) color="$RED" ;;
                1) color="$YELLOW" ;;
                2) color="$BLUE" ;;
                3) color="$CYAN" ;;
            esac
            printf "  ${color}%3d. [%s] %s${NC}\n" "$idx" "$task_id" "$task_title"
        done 3<<< "$tasks_filtered"
        echo ""
        exit 0
    fi

    # ── Dry run summary ──
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would process ${task_count} task(s):"
        echo ""
    fi

    # ── Main processing loop ──
    # NOTE: We use fd 3 so that commands inside the loop (especially claude)
    # cannot consume the task list via stdin.
    local processed=0
    while IFS=$'\t' read -r -u 3 task_id task_title; do
        [[ -z "$task_id" ]] && continue

        if [[ -f "$STOP_FILE" ]]; then
            log_warn "Stop file detected (${STOP_FILE}) — exiting after previous task"
            rm -f "$STOP_FILE"
            break
        fi

        if [[ "$MAX_TASKS" -gt 0 && "$processed" -ge "$MAX_TASKS" ]]; then
            log "Reached --max-tasks limit (${MAX_TASKS})"
            break
        fi

        run_single_task "$task_id" "$task_title" "$((processed + 1))" "$task_count" || {
            log_warn "Task ${task_id} failed — continuing to next task"
        }

        processed=$((processed + 1))

    done 3<<< "$tasks_filtered"

    # ── Summary ──
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD} SUMMARY${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "  Tasks processed: ${TASKS_PROCESSED}"
    echo -e "  ${GREEN}Succeeded:${NC}       ${TASKS_SUCCEEDED}"
    echo -e "  ${RED}Failed:${NC}          ${TASKS_FAILED}"
    echo -e "  Logs:            ${LOG_DIR}/"
    echo -e "  State:           ${STATE_FILE}"
    echo ""

    if [[ "$TASKS_FAILED" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"

#!/bin/bash
# Script to run Phase 2 Important PRPs sequentially with clean context between each
# Each PRP is executed in a fresh Claude session to ensure clean context
#
# Usage: ./run_phase2_prps.sh [--dry-run] [--single PRP-XXX]

set -e

PRP_DIR="/Users/robertocallaghan/Documents/claude/godotv2/docs/PRP/shooting_phase/phase2_important"
PROJECT_DIR="/Users/robertocallaghan/Documents/claude/godotv2"
LOG_DIR="$PROJECT_DIR/logs/prp_runs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXECUTE_PRP_CMD="$PROJECT_DIR/.claude/commands/execute-prp.md"

# Create log directory
mkdir -p "$LOG_DIR"

# Define PRPs in order (sorted by PRP number)
PRPS=(
    "PRP-010_lethal_hits.md"
    "PRP-011_sustained_hits.md"
    "PRP-012_devastating_wounds.md"
    "PRP-013_blast_keyword.md"
    "PRP-014_torrent_keyword.md"
    "PRP-015_melta_keyword.md"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
SINGLE_PRP=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --single)
            SINGLE_PRP="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  Phase 2 Important PRPs Runner${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "Log directory: ${LOG_DIR}"
echo -e "Timestamp: ${TIMESTAMP}"
if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
fi
echo ""

# Track results
declare -a RESULTS
PASS_COUNT=0
FAIL_COUNT=0

# Read the execute-prp command template (strip the $ARGUMENTS placeholder line)
EXECUTE_PRP_INSTRUCTIONS=$(cat "$EXECUTE_PRP_CMD" | sed 's/\$ARGUMENTS/[see PRP content below]/')

run_prp() {
    local prp_file="$1"
    local prp_number=$(echo "$prp_file" | grep -o 'PRP-[0-9]*')
    local log_file="$LOG_DIR/${TIMESTAMP}_${prp_number}.log"
    local prp_path="$PRP_DIR/$prp_file"

    echo -e "${YELLOW}----------------------------------------${NC}"
    echo -e "${YELLOW}Starting: $prp_file${NC}"
    echo -e "${YELLOW}Log: $log_file${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"

    # Check if PRP file exists
    if [ ! -f "$prp_path" ]; then
        echo -e "${RED}ERROR: PRP file not found: $prp_path${NC}"
        RESULTS+=("$prp_number: SKIPPED (file not found)")
        ((FAIL_COUNT++))
        return 1
    fi

    # Read the PRP content
    local prp_content=$(cat "$prp_path")

    # Build the prompt that combines instructions + PRP content
    local prompt="Execute the following PRP (Product Requirement Prompt).

## PRP File: $prp_path

## PRP Content:
$prp_content

---

Follow the execution process defined in your system prompt to implement this PRP.
After implementation, run the validation steps and create/run integration tests.
Report completion status when done."

    if $DRY_RUN; then
        echo -e "${BLUE}[DRY RUN] Would execute:${NC}"
        echo "(cd $PROJECT_DIR && claude -p --append-system-prompt <instructions> <prompt>)"
        echo ""
        echo "PRP: $prp_file"
        echo "Log would be saved to: $log_file"
        RESULTS+=("$prp_number: DRY RUN")
        return 0
    fi

    # Run Claude with the execute-prp instructions as system prompt
    # Each invocation starts a fresh session (no --continue)
    # Note: --dangerously-skip-permissions requires explicit opt-in, so we don't use it
    # The user will need to accept permissions or use allowedTools in settings
    # We run in a subshell with cd to set the working directory
    if (cd "$PROJECT_DIR" && claude -p \
        --append-system-prompt "$EXECUTE_PRP_INSTRUCTIONS" \
        "$prompt") \
        2>&1 | tee "$log_file"; then

        # Check log for success indicators
        if grep -q "All acceptance criteria met" "$log_file" || \
           grep -q "implementation complete" "$log_file" || \
           grep -q "PRP.*complete" "$log_file"; then
            echo -e "${GREEN}✓ Completed: $prp_number${NC}"
            RESULTS+=("$prp_number: PASSED")
            ((PASS_COUNT++))
        else
            echo -e "${YELLOW}⚠ Completed with warnings: $prp_number (check log)${NC}"
            RESULTS+=("$prp_number: CHECK LOG")
            ((PASS_COUNT++))
        fi
    else
        echo -e "${RED}✗ Failed: $prp_number${NC}"
        RESULTS+=("$prp_number: FAILED")
        ((FAIL_COUNT++))
    fi

    echo ""
    echo -e "${BLUE}Waiting 5 seconds before next PRP...${NC}"
    sleep 5
}

validate_integration_tests() {
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}  Validating All Integration Tests${NC}"
    echo -e "${BLUE}======================================${NC}"

    local test_log="$LOG_DIR/${TIMESTAMP}_integration_tests.log"

    if $DRY_RUN; then
        echo -e "${BLUE}[DRY RUN] Would run integration tests${NC}"
        return 0
    fi

    # Run all integration tests
    echo "Running integration tests..."

    export PATH="$HOME/bin:$PATH"
    if $HOME/bin/godot --headless \
        --path "$PROJECT_DIR/40k" \
        -s addons/gut/gut_cmdln.gd \
        -gdir res://tests/integration/ \
        -gprefix test_ \
        -gsuffix .gd \
        -gexit \
        2>&1 | tee "$test_log"; then
        echo -e "${GREEN}✓ Integration tests passed${NC}"
    else
        echo -e "${RED}✗ Integration tests had failures - check log: $test_log${NC}"
    fi
}

# Filter PRPs if --single was specified
if [ -n "$SINGLE_PRP" ]; then
    FILTERED_PRPS=()
    for prp in "${PRPS[@]}"; do
        if [[ "$prp" == *"$SINGLE_PRP"* ]]; then
            FILTERED_PRPS+=("$prp")
        fi
    done
    if [ ${#FILTERED_PRPS[@]} -eq 0 ]; then
        echo -e "${RED}No PRP matching '$SINGLE_PRP' found${NC}"
        exit 1
    fi
    PRPS=("${FILTERED_PRPS[@]}")
fi

# Main execution
echo -e "${BLUE}PRPs to execute (${#PRPS[@]} total):${NC}"
for prp in "${PRPS[@]}"; do
    echo "  - $prp"
done
echo ""

# Ask for confirmation (skip in dry-run mode)
if ! $DRY_RUN; then
    read -p "Start executing PRPs? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Run each PRP
for prp in "${PRPS[@]}"; do
    run_prp "$prp"
done

# Run integration test validation
validate_integration_tests

# Print summary
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "Results:"
for result in "${RESULTS[@]}"; do
    if [[ $result == *"PASSED"* ]]; then
        echo -e "  ${GREEN}$result${NC}"
    elif [[ $result == *"FAILED"* ]] || [[ $result == *"SKIPPED"* ]]; then
        echo -e "  ${RED}$result${NC}"
    else
        echo -e "  ${YELLOW}$result${NC}"
    fi
done
echo ""
echo -e "Total: ${GREEN}$PASS_COUNT passed${NC}, ${RED}$FAIL_COUNT failed${NC}"
echo -e "Logs saved to: $LOG_DIR"

#!/bin/bash
# Validation gate used by the `do-task` agent.
#
# Runs the headless GDScript regression suite. Exits 0 if every test passes,
# 1 otherwise. Stdout is the captured output of the runner so the agent can
# read failure details and decide whether the task is implemented correctly.
#
# Usage: bash .claude/scripts/run_validation.sh
#
# Honored env vars:
#   VALIDATION_SKIP=1   → skip the run, print a clear notice, exit 1
#                         (forces the agent to mark the task blocked rather
#                          than silently passing without proof)

set -o pipefail

if [ "${VALIDATION_SKIP:-0}" = "1" ]; then
    echo "VALIDATION_SKIP=1 set — refusing to run; treat task as unverified." >&2
    exit 1
fi

export PATH="$HOME/bin:$PATH"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$REPO_ROOT/40k/tests/run_pretrigger_tests.sh"

if [ ! -x "$RUNNER" ]; then
    echo "Validation runner not found or not executable: $RUNNER" >&2
    exit 1
fi

bash "$RUNNER"

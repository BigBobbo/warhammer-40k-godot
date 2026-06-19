#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PreToolUse gate: a task may NOT be marked complete on headless-only evidence.
#
# Per CLAUDE.md's feature-validation rule, anything with a UI affordance is not
# verified until a WINDOWED scenario drives the player path against the running
# UI via the addons/godot_mcp bridge. Headless GDScript tests are necessary but
# NOT sufficient. This hook enforces that at the commit chokepoint.
#
# It fires on `git commit` Bash calls. If the staged changes flip any task to a
# completed state — `**Status:** DONE` or a `| DONE |` table cell in ISSUES.md,
# or a `[x]` checkbox in .llm/*todo*.md — the commit is BLOCKED unless EITHER:
#   (a) a windowed scenario JSON is staged in the same commit
#       (40k/tests/scenarios/**/*.json), proving a UI-driven check exists, OR
#   (b) the staged ISSUES.md additions carry an explicit, auditable
#       justification token for a no-UI change:
#           VERIFIED: pure-state (no UI affordance) — <reason>
#
# Headless-only (just a tests/test_*.gd) with no scenario and no justification
# fails by design.
#
# Contract: stdin = PreToolUse JSON event. Exit 0 = allow. Exit 2 = block
# (stderr is shown to the model). Any internal error fails OPEN (exit 0) so the
# gate can never wedge the workflow — it only ever ADDS a check.
# ---------------------------------------------------------------------------
set -uo pipefail

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

# Parse tool name + "is this a git commit" flag. NOTE: python program comes
# from -c so stdin stays free to carry $input (piping into `python3 - <<EOF`
# does NOT work — the heredoc becomes the program and stdin is empty).
parsed="$(printf '%s' "$input" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print("\t"); sys.exit(0)
t=d.get("tool_name","")
ti=d.get("tool_input",{})
c=ti.get("command","") if isinstance(ti,dict) else ""
print(t + "\t" + ("1" if "git commit" in c else "0"))' 2>/dev/null || printf '\t')"

tool="${parsed%%$'\t'*}"
is_commit="${parsed##*$'\t'}"

[ "$tool" = "Bash" ] || exit 0
[ "$is_commit" = "1" ] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] || exit 0
cd "$ROOT" 2>/dev/null || exit 0

# Added lines (leading +, excluding the +++ file header) in the tracking files.
# NB: pass each pathspec separately and only when present — a non-existent
# pathspec (e.g. no .llm dir) makes `git diff` fail and emit nothing.
added="$( {
  git diff --cached -U0 -- ISSUES.md 2>/dev/null
  [ -e .llm ] && git diff --cached -U0 -- .llm 2>/dev/null
} | grep -E '^\+' | grep -vE '^[+][+][+]' || true )"
[ -n "$added" ] || exit 0

# Did this commit mark anything COMPLETE?
marks_done="$(printf '%s\n' "$added" | grep -iE '\*\*Status:\*\* *DONE|\| *DONE *\||\[x\]' || true)"
[ -n "$marks_done" ] || exit 0

# Evidence (a): a windowed scenario JSON staged this commit.
scenario_staged="$(git diff --cached --name-only 2>/dev/null | grep -E 'tests/scenarios/.*\.json$' || true)"

# Evidence (b): an explicit pure-state / no-UI justification in the added lines.
justified="$(printf '%s\n' "$added" | grep -iE 'VERIFIED: *pure-state' || true)"

if [ -n "$scenario_staged" ] || [ -n "$justified" ]; then
  exit 0
fi

# Block.
{
  echo "BLOCKED by verify-windowed-gate: this commit marks a task DONE without windowed/MCP evidence."
  echo
  echo "Completion markers staged in this commit:"
  printf '%s\n' "$marks_done" | sed 's/^[+]*/    /' | head -8
  echo
  echo "Per CLAUDE.md, a feature with a UI affordance is NOT verified until a windowed"
  echo "scenario drives the player path against the running UI via the godot_mcp bridge."
  echo "Headless GDScript tests do not satisfy this gate."
  echo
  echo "To proceed, do ONE of:"
  echo "  (a) Stage a windowed scenario that exercises it, in the SAME commit:"
  echo "      40k/tests/scenarios/sp/<id>.json  (run it: bash 40k/tests/run_scenarios.sh <path>)"
  echo "  (b) If it is genuinely a pure-state / no-UI change (RulesEngine math, save"
  echo "      round-trip, autoload state), add an explicit justification line to the"
  echo "      ISSUES.md entry, exactly:"
  echo "      VERIFIED: pure-state (no UI affordance) — <why no windowed check applies>"
} >&2
exit 2

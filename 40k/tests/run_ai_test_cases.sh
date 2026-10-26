#!/bin/bash
# Re-check saved AI test cases (made with "Good call" / "Bad call" on the K
# suggestion breakdown card — see scripts/AISuggestionTestCases.gd).
#
# Each case is a game state + what the AI suggested + your verdict:
#   good → PASS while the AI still makes the same choice
#   bad  → PASS once the AI chooses differently; FAIL while it repeats it
#
# Usage:
#   bash 40k/tests/run_ai_test_cases.sh                 # every case in
#        <godot-userdata>/40k/ai_test_cases/ and 40k/tests/ai_cases/
#   bash 40k/tests/run_ai_test_cases.sh path/to/case.json [...]
#   bash 40k/tests/run_ai_test_cases.sh --compare <git-ref> [case.json ...]
#        Run every case on this working tree AND on <git-ref> (e.g. main,
#        HEAD~3, a commit) and report, per case, whether the AI's choice
#        changed between the two versions — old pick vs new pick and their
#        top-scored options — plus each version's PASS/FAIL. The other
#        version is checked out into a temporary git worktree (its first run
#        imports the project, which takes a few minutes).
#
# Each case runs as a windowed scenario (tests/run_scenarios.sh): the case's
# save is staged as a fixture, the AI is asked for a suggestion at the case's
# difficulty, and the signature is compared. Nothing is executed.
#
# Exit codes: 0 all pass (compare: on this tree), 1 at least one failed,
# 2 no cases found / setup error.

set -u
cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
export PATH="$HOME/bin:$PATH"

COMPARE_REF=""
if [ "${1:-}" = "--compare" ]; then
    COMPARE_REF="${2:-}"
    [ -z "$COMPARE_REF" ] && { echo "--compare needs a git ref (e.g. main)"; exit 2; }
    shift 2
fi

USERDATA="$HOME/.local/share/godot/app_userdata/40k"
if [ ! -d "$USERDATA" ] && [ -d "$HOME/Library/Application Support/Godot/app_userdata/40k" ]; then
    USERDATA="$HOME/Library/Application Support/Godot/app_userdata/40k"
fi

CASES=()
if [ "$#" -gt 0 ]; then
    for c in "$@"; do CASES+=("$(cd "$(dirname "$c")" && pwd)/$(basename "$c")"); done
else
    for f in "$USERDATA"/ai_test_cases/*.json tests/ai_cases/*.json; do
        [ -f "$f" ] && CASES+=("$(cd "$(dirname "$f")" && pwd)/$(basename "$f")")
    done
fi
if [ "${#CASES[@]}" -eq 0 ]; then
    echo "No AI test cases found (looked in $USERDATA/ai_test_cases/ and 40k/tests/ai_cases/)."
    echo "Make one: press K in a game, then 'Good call' or 'Bad call' on the card."
    exit 2
fi

# run_set <project-dir> <label> → writes $USERDATA/ai_case_results_<label>.json
run_set() {
    local proj="$1" label="$2"
    local gen="$USERDATA/ai_case_scenarios_$label"
    mkdir -p "$gen" "$USERDATA/saves"
    rm -f "$gen"/*.json
    local scen=()
    for case_abs in "${CASES[@]}"; do
        local save_file id
        save_file="$(dirname "$case_abs")/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["save_file"])' "$case_abs")"
        id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$case_abs")"
        if [ ! -f "$save_file" ]; then
            echo "SKIP $id — save file missing: $save_file" >&2
            continue
        fi
        cp "$save_file" "$USERDATA/saves/ai_case_${id}.w40ksave"
        python3 - "$case_abs" "$id" "$gen/ai_case_${id}.json" <<'PY'
import json, sys
case_path, cid, out = sys.argv[1:4]
call = 'ResourceLoader.load("res://scripts/AISuggestionTestCases.gd").%s(%s)'
json.dump({
    "id": "ai_case_" + cid,
    "covers": ["ai.test_case"],
    "fixture": "ai_case_" + cid,
    "description": "Saved AI test case " + cid,
    "steps": [
        {"act": "wait_seconds", "seconds": 0.8},
        {"act": "execute_script", "script": call % ("check_case_json", json.dumps(case_path))},
        {"act": "execute_script", "script": call % ("check_case", json.dumps(case_path)) + ".pass", "equals": True},
    ],
}, open(out, "w"), indent=2)
PY
        scen+=("$gen/ai_case_${id}.json")
    done
    [ "${#scen[@]}" -eq 0 ] && return 2
    (cd "$proj" && bash tests/run_scenarios.sh "${scen[@]}") > "$gen/run.log" 2>&1
    python3 - "$USERDATA/test_results/scenarios" "$USERDATA/ai_case_results_$label.json" "${scen[@]}" <<'PY'
import json, os, sys
res_dir, out, scen = sys.argv[1], sys.argv[2], sys.argv[3:]
results = {}
for sp in scen:
    sid = json.load(open(sp))["id"]
    rp = os.path.join(res_dir, sid + ".json")
    r = {"pass": False, "detail": "no result (see run.log)"}
    if os.path.exists(rp):
        steps = json.load(open(rp)).get("steps", [])
        raw = next((s.get("actual") for s in steps if s.get("step") == 1), None)
        try:
            r = json.loads(raw) if isinstance(raw, str) else r
        except Exception:
            r = {"pass": False, "detail": str(raw)}
        r["pass"] = bool(steps) and all(s.get("pass", False) for s in steps)
    results[sid] = r
json.dump(results, open(out, "w"), indent=2)
PY
}

if [ -z "$COMPARE_REF" ]; then
    run_set "$PROJECT_DIR" "current" || { echo "No runnable cases."; exit 2; }
    python3 - "$USERDATA/ai_case_results_current.json" <<'PY'
import json, sys
res = json.load(open(sys.argv[1]))
fails = sum(0 if r.get("pass") else 1 for r in res.values())
print("AI test cases (%d):" % len(res))
for sid, r in res.items():
    print("  %s %s" % ("PASS" if r.get("pass") else "FAIL", r.get("detail", sid)))
print("%d passed, %d failed" % (len(res) - fails, fails))
sys.exit(1 if fails else 0)
PY
    exit $?
fi

# --- compare mode ---------------------------------------------------------
REPO_ROOT="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel)"
REL="${PROJECT_DIR#$REPO_ROOT/}"
WT="$USERDATA/ai_compare_worktree"
git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1
rm -rf "$WT"
if ! git -C "$REPO_ROOT" worktree add --detach "$WT" "$COMPARE_REF" >/dev/null 2>&1; then
    echo "Could not check out '$COMPARE_REF' into a worktree."; exit 2
fi
OTHER="$WT/$REL"
# The other version may predate the checker / runner: use this tree's copies.
cp "$PROJECT_DIR/scripts/AISuggestionTestCases.gd" "$OTHER/scripts/"
cp "$PROJECT_DIR/tests/run_scenarios.sh" "$OTHER/tests/run_scenarios.sh" 2>/dev/null
echo "Importing $COMPARE_REF (first run only takes a few minutes)…"
(cd "$OTHER" && godot --headless --import >/dev/null 2>&1)

echo "Running ${#CASES[@]} case(s) on $COMPARE_REF…"
run_set "$OTHER" "ref"
echo "Running ${#CASES[@]} case(s) on this working tree…"
run_set "$PROJECT_DIR" "current"
git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1

python3 - "$USERDATA/ai_case_results_ref.json" "$USERDATA/ai_case_results_current.json" "$COMPARE_REF" <<'PY'
import json, sys
ref, cur, name = json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), sys.argv[3]
changed = 0
fails = 0
print("\nAI version comparison: %s  →  this working tree  (%d case(s))\n" % (name, len(cur)))
for sid in cur:
    a, b = ref.get(sid, {}), cur[sid]
    same = a.get("current_signature") == b.get("current_signature")
    changed += 0 if same else 1
    fails += 0 if b.get("pass") else 1
    print("%s %s   [%s: %s → now: %s]" % ("=" if same else "≠", sid,
          name, "PASS" if a.get("pass") else "FAIL", "PASS" if b.get("pass") else "FAIL"))
    if same:
        print("    same choice: %s" % b.get("now_description", ""))
    else:
        print("    %s: %s" % (name, a.get("now_description", "(no result)")))
        print("    now:  %s" % b.get("now_description", "(no result)"))
    for label, r in ((name, a), ("now", b)):
        opts = r.get("now_options", [])
        if opts and not same:
            print("      %s options: %s" % (label, " | ".join(
                ("*" if o.get("picked") else "") + "%s (%.2f)" % (o.get("option", ""), o.get("score", 0)) for o in opts)))
print("\n%d of %d case(s) changed choice; %d failing on this tree." % (changed, len(cur), fails))
sys.exit(1 if fails else 0)
PY
exit $?

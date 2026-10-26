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
#
# Each case runs as a windowed scenario (tests/run_scenarios.sh): the case's
# save is staged as a fixture, the AI is asked for a suggestion at the case's
# difficulty, and the signature is compared. Nothing is executed.
#
# Exit codes: 0 all pass, 1 at least one failed, 2 no cases found.

set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/bin:$PATH"

USERDATA="$HOME/.local/share/godot/app_userdata/40k"
if [ ! -d "$USERDATA" ] && [ -d "$HOME/Library/Application Support/Godot/app_userdata/40k" ]; then
    USERDATA="$HOME/Library/Application Support/Godot/app_userdata/40k"
fi

CASES=()
if [ "$#" -gt 0 ]; then
    CASES=("$@")
else
    for f in "$USERDATA"/ai_test_cases/*.json tests/ai_cases/*.json; do
        [ -f "$f" ] && CASES+=("$f")
    done
fi
if [ "${#CASES[@]}" -eq 0 ]; then
    echo "No AI test cases found (looked in $USERDATA/ai_test_cases/ and 40k/tests/ai_cases/)."
    echo "Make one: press K in a game, then 'Good call' or 'Bad call' on the card."
    exit 2
fi

GEN_DIR="$USERDATA/ai_case_scenarios"
mkdir -p "$GEN_DIR" "$USERDATA/saves"
rm -f "$GEN_DIR"/*.json
SCENARIOS=()
for case_json in "${CASES[@]}"; do
    case_abs="$(cd "$(dirname "$case_json")" && pwd)/$(basename "$case_json")"
    save_file="$(dirname "$case_abs")/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["save_file"])' "$case_abs")"
    id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$case_abs")"
    if [ ! -f "$save_file" ]; then
        echo "SKIP $id — save file missing: $save_file"
        continue
    fi
    cp "$save_file" "$USERDATA/saves/ai_case_${id}.w40ksave"
    python3 - "$case_abs" "$id" "$GEN_DIR/ai_case_${id}.json" <<'PY'
import json, sys
case_path, cid, out = sys.argv[1:4]
check = 'ResourceLoader.load("res://scripts/AISuggestionTestCases.gd").check_case(%s)' % json.dumps(case_path)
json.dump({
    "id": "ai_case_" + cid,
    "covers": ["ai.test_case"],
    "fixture": "ai_case_" + cid,
    "description": "Saved AI test case " + cid,
    "steps": [
        {"act": "wait_seconds", "seconds": 0.8},
        {"act": "execute_script", "script": check + ".detail"},
        {"act": "execute_script", "script": check + ".pass", "equals": True},
    ],
}, open(out, "w"), indent=2)
PY
    SCENARIOS+=("$GEN_DIR/ai_case_${id}.json")
done

[ "${#SCENARIOS[@]}" -eq 0 ] && { echo "No runnable cases."; exit 2; }

bash tests/run_scenarios.sh "${SCENARIOS[@]}" > "$GEN_DIR/run.log" 2>&1
RC=$?

echo "AI test cases (${#SCENARIOS[@]}):"
python3 - "$USERDATA/test_results/scenarios" "${SCENARIOS[@]}" <<'PY'
import json, os, sys
res_dir, scen = sys.argv[1], sys.argv[2:]
fails = 0
for sp in scen:
    sid = json.load(open(sp))["id"]
    rp = os.path.join(res_dir, sid + ".json")
    if not os.path.exists(rp):
        print("  ERROR %s — no result (see ai_case_scenarios/run.log)" % sid); fails += 1; continue
    steps = json.load(open(rp)).get("steps", [])
    detail = next((str(s.get("actual")) for s in steps if s.get("step") == 1), "")
    ok = bool(steps) and all(s.get("pass", False) for s in steps)
    fails += 0 if ok else 1
    print("  %s %s" % ("PASS" if ok else "FAIL", detail or sid))
print("%d passed, %d failed" % (len(scen) - fails, fails))
PY
exit $RC

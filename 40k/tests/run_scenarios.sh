#!/bin/bash
# Batch-run scenarios. By default runs every *.json under tests/scenarios/sp/.
#
# Usage:
#   bash 40k/tests/run_scenarios.sh                # all sp scenarios
#   bash 40k/tests/run_scenarios.sh --all          # sp + mp scenarios
#   bash 40k/tests/run_scenarios.sh --visual       # only design-guidelines visual scenarios
#   bash 40k/tests/run_scenarios.sh --e11          # the 11e windowed suite (ISS-063)
#   bash 40k/tests/run_scenarios.sh --changed-only # only scenarios whose
#                                                  # 'covers' tags overlap
#                                                  # with files changed since
#                                                  # main (used by pre-commit)
#   bash 40k/tests/run_scenarios.sh path/to/x.json [path/to/y.json ...]
#
# Exit codes:
#   0 — all scenarios passed
#   1 — at least one assertion failed
#   2 — infra error (no scenarios found, etc.)
#   3 — regression detected: passing-count fell below tests/scenarios/visual/_baseline.json
#       (only emitted when at least one visual/* scenario was in the batch)

set -e

cd "$(dirname "$0")/.."
export PATH="$HOME/bin:$PATH"

# Ensure committed test fixtures are present where SaveLoadManager.load_game
# resolves them. load_game reads res://saves/ (== 40k/saves/, which is
# gitignored), but the fixtures are committed under tests/saves/. Copy any
# that are missing so a windowed scenario can load its fixture from a fresh
# checkout. -n never clobbers an existing (e.g. freshly generated) save.
# Ensure committed test fixtures are present AND CURRENT where
# SaveLoadManager.load_game resolves them. This used to be `cp -n`, which
# never overwrites — and that is a rot vector the PM-F3 rot-guard caught in
# the wild: after the 2026-08-21 fixture rebuild, a container restored an
# older user-data snapshot and `cp -n` happily kept the STALE boards in
# saves/ (and SaveLoadManager's non-destructive legacy copy kept them in
# user://saves) while the repo held the rebuilt ones. Checksum-compare and
# copy on difference, into BOTH resolution locations, so the committed
# fixture always wins.
mkdir -p saves
USER_SAVES="$HOME/.local/share/godot/app_userdata/40k/saves"
mkdir -p "$USER_SAVES"
for src in tests/saves/*.w40ksave tests/saves/*.meta; do
    [ -f "$src" ] || continue
    base="$(basename "$src")"
    for dstdir in saves "$USER_SAVES"; do
        if ! cmp -s "$src" "$dstdir/$base" 2>/dev/null; then
            cp "$src" "$dstdir/$base"
        fi
    done
done

MODE="${1:---sp}"
SCENARIOS=()
FULL_SUITE_RUN=0  # only set to 1 when running a documented full-suite mode

if [ "$MODE" = "--all" ]; then
    SCENARIOS=($(find tests/scenarios/sp tests/scenarios/mp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
    FULL_SUITE_RUN=1
elif [ "$MODE" = "--sp" ] || [ -z "$MODE" ]; then
    SCENARIOS=($(find tests/scenarios/sp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
    FULL_SUITE_RUN=1
elif [ "$MODE" = "--mp" ]; then
    SCENARIOS=($(find tests/scenarios/mp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
elif [ "$MODE" = "--e11" ]; then
    # ISS-063: the 11e windowed suite — every scenario that drives the
    # edition-11 rules templates through the real UI (these also run in
    # the default --sp batch; this mode is the focused gate).
    SCENARIOS=($(grep -l '"edition": 11' tests/scenarios/sp/*.json 2>/dev/null | sort))
elif [ "$MODE" = "--visual" ]; then
    SCENARIOS=($(find tests/scenarios/visual -maxdepth 1 -name "T*_*.json" 2>/dev/null | sort))
    FULL_SUITE_RUN=1
elif [ "$MODE" = "--changed-since" ]; then
    # CI mode: scenarios whose own JSON changed since <ref>, plus scenarios
    # whose `covers` tags match a changed path (same heuristic as
    # --changed-only, but against a committed range instead of the working
    # tree, which is always clean in CI).
    REF="${2:?--changed-since needs a git ref}"
    CHANGED=$(git diff --name-only "$REF"...HEAD 2>/dev/null || git diff --name-only "$REF" HEAD)
    CHANGED_LC=$(echo "$CHANGED" | tr '[:upper:]' '[:lower:]')
    for s in $(find tests/scenarios/sp tests/scenarios/mp tests/scenarios/visual -maxdepth 1 -name "*.json" 2>/dev/null | sort); do
        case "$(basename "$s")" in _*) continue ;; esac
        INCLUDE=0
        if echo "$CHANGED" | grep -qxF "40k/$s"; then
            INCLUDE=1
        else
            COVERS_LINE=$(grep -E '"covers"' "$s" | head -1)
            for tag in $(echo "$COVERS_LINE" | grep -oE '"[a-zA-Z0-9_.]+"' | tr -d '"'); do
                segment=$(echo "$tag" | cut -d. -f1)
                if [ ${#segment} -ge 4 ] && echo "$CHANGED_LC" | grep -qF "$segment"; then
                    INCLUDE=1
                    break
                fi
            done
        fi
        [ $INCLUDE -eq 1 ] && SCENARIOS+=("$s")
    done
    if [ ${#SCENARIOS[@]} -eq 0 ]; then
        echo "[run_scenarios] no scenarios match changes since $REF; nothing to run"
        exit 0
    fi
elif [ "$MODE" = "--changed-only" ]; then
    # Pre-commit / changed-files mode: pick scenarios whose `covers` tags
    # overlap with any path-fragment in the changed file list. Crude but
    # sufficient — we lean on coverage tags being descriptive.
    CHANGED=$(git diff --cached --name-only 2>/dev/null)
    if [ -z "$CHANGED" ]; then
        CHANGED=$(git diff --name-only 2>/dev/null)
    fi
    if [ -z "$CHANGED" ]; then
        echo "[run_scenarios] no changes detected; running full sp suite"
        SCENARIOS=($(find tests/scenarios/sp -maxdepth 1 -name "*.json" 2>/dev/null | sort))
    else
        # Build a lowercase changed-files string to grep against `covers` tags
        CHANGED_LC=$(echo "$CHANGED" | tr '[:upper:]' '[:lower:]')
        for s in $(find tests/scenarios -maxdepth 2 -name "*.json"); do
            COVERS_LINE=$(grep -E '"covers"' "$s" | head -1)
            # If any covers tag's primary segment (before first .) matches any
            # changed-file path fragment, include this scenario.
            INCLUDE=0
            for tag in $(echo "$COVERS_LINE" | grep -oE '"[a-zA-Z0-9_.]+"' | tr -d '"'); do
                segment=$(echo "$tag" | cut -d. -f1)
                if echo "$CHANGED_LC" | grep -qF "$segment"; then
                    INCLUDE=1
                    break
                fi
            done
            if [ $INCLUDE -eq 1 ]; then
                SCENARIOS+=("$s")
            fi
        done
        if [ ${#SCENARIOS[@]} -eq 0 ]; then
            echo "[run_scenarios] no scenarios match changed files; nothing to run"
            exit 0
        fi
    fi
else
    # Treat all positional args as scenario paths
    SCENARIOS=("$@")
fi

if [ ${#SCENARIOS[@]} -eq 0 ]; then
    echo "[run_scenarios] no scenarios found"
    exit 2
fi

# Rules edition for scenarios WITHOUT an "edition" field: the harness default
# is 11e; WH40K_TEST_EDITION=10 is the explicit legacy opt-in (a scenario's own
# field always wins). Every results JSON records the edition it ran.
if [ -n "${WH40K_TEST_EDITION:-}" ] && ! [[ "$WH40K_TEST_EDITION" =~ ^1[01]$ ]]; then
    echo "WH40K_TEST_EDITION must be 10 or 11 (got '$WH40K_TEST_EDITION')"
    exit 2
fi
echo "Rules edition for fieldless scenarios: ${WH40K_TEST_EDITION:-11 (harness default)}"

# CI sharding: SCENARIO_SHARD=i/n keeps every n-th scenario starting at i.
if [ -n "${SCENARIO_SHARD:-}" ]; then
    if ! [[ "$SCENARIO_SHARD" =~ ^[0-9]+/[0-9]+$ ]]; then
        echo "SCENARIO_SHARD must look like i/n (got '$SCENARIO_SHARD')"
        exit 2
    fi
    SHARD_I=${SCENARIO_SHARD%/*}
    SHARD_N=${SCENARIO_SHARD#*/}
    SELECTED=()
    for i in "${!SCENARIOS[@]}"; do
        if [ $((i % SHARD_N)) -eq "$SHARD_I" ]; then
            SELECTED+=("${SCENARIOS[$i]}")
        fi
    done
    SCENARIOS=("${SELECTED[@]}")
    FULL_SUITE_RUN=0  # a shard is not the full suite (baseline count check)
    echo "Shard $SCENARIO_SHARD: ${#SCENARIOS[@]} scenario(s)"
fi

# Known failures (pre-existing, tracked): one scenario id per line in
# tests/scenarios/_known_failures.txt (override with SCENARIO_KNOWN_FAILURES),
# optional "# reason". A listed scenario that fails is XFAIL and does not fail
# the batch; a listed scenario that PASSES is XPASS — a warning, or a failure
# with SCENARIO_STRICT_XPASS=1 (it must be delisted). Anything else that fails
# fails the batch, as before.
KNOWN_FILE="${SCENARIO_KNOWN_FAILURES:-tests/scenarios/_known_failures.txt}"
KNOWN_IDS=" "
if [ -f "$KNOWN_FILE" ]; then
    KNOWN_IDS=" $(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$KNOWN_FILE" | grep -v '^$' | tr '\n' ' ') "
fi
XFAILED=0
XPASSED=0
XPASS_IDS=()
SUMMARY_FILE="${SCENARIO_SUMMARY_FILE:-}"

echo "================================================"
echo "Batch scenario run: ${#SCENARIOS[@]} scenario(s)"
echo "================================================"

# BUILDER-E2E: a scenario with "builder_e2e": "server/tests/<script>.mjs" is
# the game half of a browser Army Builder end-to-end. Before it runs, start a
# throwaway relay server, run that builder half against it (Playwright drives
# the builder page and saves the army to the cloud), and point
# res://server_config.json at the relay for this scenario only — every other
# scenario keeps the default CloudStorage endpoint. Needs node, the server's
# npm deps and a Playwright Chromium (CI installs them; see scenarios.yml).
# Env: E2E_PORT (default 19690), E2E_SHOT_DIR (builder screenshots + log).
E2E_CFG="server_config.json"
E2E_SRV_PID=""
E2E_DIR=""
builder_e2e_stop() {
    if [ -n "$E2E_SRV_PID" ]; then
        kill "$E2E_SRV_PID" 2>/dev/null || true
        wait "$E2E_SRV_PID" 2>/dev/null || true
    fi
    if [ -n "$E2E_DIR" ]; then
        rm -f "$E2E_CFG"
        rm -rf "$E2E_DIR"
    fi
    E2E_SRV_PID=""
    E2E_DIR=""
}
builder_e2e_start() {
    local script="$1" sid="$2"
    local port="${E2E_PORT:-19690}"
    local shots="${E2E_SHOT_DIR:-$HOME/.local/share/godot/app_userdata/40k/test_results/scenarios}"
    if [ -e "$E2E_CFG" ]; then
        echo "    builder_e2e: refusing to overwrite an existing 40k/$E2E_CFG"
        return 1
    fi
    if ! command -v node > /dev/null 2>&1; then
        echo "    builder_e2e: node not found (needs node + server npm deps + Playwright Chromium)"
        return 1
    fi
    mkdir -p "$shots"
    E2E_DIR="$(mktemp -d)"
    (cd ../server && PORT="$port" DB_PATH="$E2E_DIR/e2e.db" exec node relay-server.js) > "$E2E_DIR/relay.log" 2>&1 &
    E2E_SRV_PID=$!
    local up=0
    for _ in $(seq 1 50); do
        if curl -sf "http://localhost:$port/api/health" > /dev/null 2>&1; then
            up=1
            break
        fi
        sleep 0.2
    done
    if [ $up -eq 0 ]; then
        echo "    builder_e2e: relay server did not come up on :$port"
        tail -20 "$E2E_DIR/relay.log" | sed 's/^/      /'
        return 1
    fi
    echo "    builder_e2e: $script against http://localhost:$port"
    if ! (cd .. && E2E_BASE="http://localhost:$port" E2E_SHOT_DIR="$shots" node "$script") > "$shots/${sid}_builder.log" 2>&1; then
        echo "    builder_e2e: builder half FAILED (log: $shots/${sid}_builder.log)"
        tail -20 "$shots/${sid}_builder.log" | sed 's/^/      /'
        return 1
    fi
    tail -3 "$shots/${sid}_builder.log" | sed 's/^/      /'
    printf '{"api_url": "http://localhost:%s"}\n' "$port" > "$E2E_CFG"
}
trap builder_e2e_stop EXIT

PASSED=0
FAILED=0
FAILED_IDS=()

for s in "${SCENARIOS[@]}"; do
    SCENARIO_ID=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$s" | head -1 | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
    echo ""
    echo "------------------------------------------------"
    echo "[$((PASSED + FAILED + 1))/${#SCENARIOS[@]}] $SCENARIO_ID"
    echo "    $s"
    echo "------------------------------------------------"

    # Macros activate window once per run on Mac
    if [ "$(uname)" = "Darwin" ]; then
        osascript -e 'tell application "Godot" to activate' 2>/dev/null || true
    fi

    # SCEN-TIMEOUT: a scenario that never exits used to block the whole batch
    # with output indistinguishable from a slow one. Scenarios legitimately run
    # 2-3 minutes (several script `wait_seconds` in a row), so the cap is
    # generous — it exists to bound a hang, not to police pace. Raise it with
    # SCENARIO_TIMEOUT for a deliberately long scenario.
    BUILDER_E2E=$(grep -oE '"builder_e2e"[[:space:]]*:[[:space:]]*"[^"]*"' "$s" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
    E2E_SETUP_OK=1
    if [ -n "$BUILDER_E2E" ] && ! builder_e2e_start "$BUILDER_E2E" "$SCENARIO_ID"; then
        E2E_SETUP_OK=0
    fi
    if [ $E2E_SETUP_OK -eq 0 ]; then
        EXIT_CODE=1
    elif timeout "${SCENARIO_TIMEOUT:-600}" godot --path . --scenario-file="$s" 2>&1 | tee /tmp/scenario_run_${SCENARIO_ID}.log | grep -E "^\[ScenarioRunner\]|PASS|FAIL|=== "; then
        EXIT_CODE=${PIPESTATUS[0]}
    else
        EXIT_CODE=${PIPESTATUS[0]}
    fi
    builder_e2e_stop
    # The pipeline's own status is grep's, so a hang that printed some lines
    # used to be reported as a plain FAIL — check godot's status either way.
    if [ "$EXIT_CODE" = "124" ]; then
        echo "    TIMED OUT after ${SCENARIO_TIMEOUT:-600}s — this is a HANG, not a failed"
        echo "    assertion. Full log: /tmp/scenario_run_${SCENARIO_ID}.log"
    fi

    IS_KNOWN=0
    [[ "$KNOWN_IDS" == *" $SCENARIO_ID "* ]] && IS_KNOWN=1
    if [ $EXIT_CODE -eq 0 ]; then
        PASSED=$((PASSED + 1))
        if [ $IS_KNOWN -eq 1 ]; then
            XPASSED=$((XPASSED + 1))
            XPASS_IDS+=("$SCENARIO_ID")
            echo "  -> PASS (XPASS: listed in $KNOWN_FILE — delist it)"
            STATUS=xpass
        else
            echo "  -> PASS"
            STATUS=pass
        fi
    elif [ $IS_KNOWN -eq 1 ]; then
        XFAILED=$((XFAILED + 1))
        echo "  -> XFAIL (exit $EXIT_CODE; known failure, $KNOWN_FILE)"
        STATUS=xfail
    else
        FAILED=$((FAILED + 1))
        FAILED_IDS+=("$SCENARIO_ID")
        echo "  -> FAIL (exit $EXIT_CODE)"
        STATUS=fail
    fi
    if [ -n "$SUMMARY_FILE" ]; then
        printf "%s\t%s\t%s\t%s\n" "$SCENARIO_ID" "$s" "$EXIT_CODE" "$STATUS" >> "$SUMMARY_FILE"
    fi
done

echo ""
echo "================================================"
echo "Scenario suite: $PASSED passed, $FAILED failed across ${#SCENARIOS[@]} scenarios"
echo "Known failures: $XFAILED xfail, $XPASSED xpass ($KNOWN_FILE)"
if [ $FAILED -gt 0 ]; then
    echo "Failed: ${FAILED_IDS[*]}"
fi
if [ $XPASSED -gt 0 ]; then
    echo "XPASS (listed as known failures but passed — delist): ${XPASS_IDS[*]}"
    if [ "${SCENARIO_STRICT_XPASS:-0}" = "1" ]; then
        FAILED=$((FAILED + XPASSED))
    fi
fi
echo "================================================"

# ----------------------------------------------------------------------------
# Visual-scenario post-processing (T02)
#
# If any tests/scenarios/visual/T##_*.json was in this batch:
#   1) Copy captured screenshots from the user:// results dir into
#      40k/test_results/design_guidelines/T##/ for stable review locations.
#   2) Compare PASSED against _baseline.json.count and exit 3 if it dropped.
# ----------------------------------------------------------------------------

VISUAL_RAN=0
for s in "${SCENARIOS[@]}"; do
    if [[ "$s" == *"tests/scenarios/visual/T"*"_"*".json" ]]; then
        VISUAL_RAN=1
        break
    fi
done

if [ $VISUAL_RAN -eq 1 ]; then
    USER_RESULTS_DIR="$HOME/.local/share/godot/app_userdata/40k/test_results/scenarios"
    if [ ! -d "$USER_RESULTS_DIR" ]; then
        # macOS
        USER_RESULTS_DIR="$HOME/Library/Application Support/Godot/app_userdata/40k/test_results/scenarios"
    fi

    DEST_BASE="test_results/design_guidelines"
    mkdir -p "$DEST_BASE"

    for s in "${SCENARIOS[@]}"; do
        if [[ "$s" != *"tests/scenarios/visual/T"*"_"*".json" ]]; then
            continue
        fi
        SCENARIO_ID=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$s" | head -1 | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
        TASK_ID=$(echo "$SCENARIO_ID" | grep -oE '^T[0-9]+')
        if [ -z "$TASK_ID" ]; then
            continue
        fi
        TASK_DIR="$DEST_BASE/$TASK_ID"
        mkdir -p "$TASK_DIR"
        if [ -d "$USER_RESULTS_DIR" ]; then
            # Copy this scenario's PNGs + results JSON
            for f in "$USER_RESULTS_DIR/${SCENARIO_ID}"_*.png "$USER_RESULTS_DIR/${SCENARIO_ID}.json"; do
                if [ -f "$f" ]; then
                    cp "$f" "$TASK_DIR/" 2>/dev/null || true
                fi
            done

            # Extract pixel_diff entries to a dedicated diff_report.json for
            # reviewers who want the numbers without the full step transcript.
            RESULT_JSON="$USER_RESULTS_DIR/${SCENARIO_ID}.json"
            if [ -f "$RESULT_JSON" ] && command -v python3 >/dev/null 2>&1; then
                python3 - "$RESULT_JSON" "$TASK_DIR/diff_report.json" <<'PY' 2>/dev/null || true
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)
diffs = [s for s in data.get("steps", []) if s.get("act") == "pixel_diff"]
report = {
    "scenario_id": data.get("scenario_id"),
    "pixel_diff_steps": diffs,
    "summary": {
        "step_count": len(diffs),
        "all_passed": all(s.get("pass", False) for s in diffs),
    }
}
with open(dst, "w") as f:
    json.dump(report, f, indent=2)
PY
            fi

            echo "[run_scenarios] copied artifacts to $TASK_DIR/"
        else
            echo "[run_scenarios] WARNING: user-results dir not found ($USER_RESULTS_DIR); skipping copy for $SCENARIO_ID"
        fi
    done

    # Baseline regression check. Only meaningful on full-suite runs — an
    # individual-scenario invocation runs N < baseline by construction and
    # would always trip the check.
    if [ $FULL_SUITE_RUN -eq 1 ]; then
        BASELINE_FILE="tests/scenarios/visual/_baseline.json"
        if [ -f "$BASELINE_FILE" ]; then
            BASELINE_COUNT=$(grep -oE '"count"[[:space:]]*:[[:space:]]*[0-9]+' "$BASELINE_FILE" | head -1 | grep -oE '[0-9]+')
            if [ -n "$BASELINE_COUNT" ]; then
                echo "[run_scenarios] baseline count: $BASELINE_COUNT  passing: $PASSED"
                if [ "$PASSED" -lt "$BASELINE_COUNT" ]; then
                    echo "[run_scenarios] REGRESSION: passing ($PASSED) < baseline ($BASELINE_COUNT)"
                    exit 3
                fi
            fi
        fi
    else
        echo "[run_scenarios] (skipping baseline regression check — not a full-suite run)"
    fi
fi

exit $([ $FAILED -eq 0 ] && echo 0 || echo 1)

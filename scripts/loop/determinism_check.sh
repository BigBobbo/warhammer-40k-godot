#!/bin/bash
# Determinism check for the visual-regression loop.
#
# Runs a scenario windowed twice with per-step screenshots enabled, then
# PHASH-compares each pair of frames. A non-zero Hamming distance between
# the two runs of the same step means the scenario isn't deterministic
# under the RNG seed it claims to use — typically a real bug (animation
# without a seed, tween jitter, unsorted iteration in a dictionary
# walk) that will cause golden-diff flakes downstream.
#
# Usage:
#   bash scripts/loop/determinism_check.sh <scenario-json-path>
#
# Exit codes:
#   0  every step's two screenshots have Hamming distance == 0
#   1  at least one step drifted between runs
#   2  misuse / scenario failed to run
#
set -e

SCENARIO_PATH="$1"
if [ -z "$SCENARIO_PATH" ] || [ ! -f "$SCENARIO_PATH" ]; then
    echo "usage: $0 <scenario-json-path>"
    exit 2
fi

cd "$(git rev-parse --show-toplevel)"
export PATH="$HOME/bin:$PATH"

SCENARIO_ID=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$SCENARIO_PATH" \
              | head -1 | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
USER_DIR="$HOME/.local/share/godot/app_userdata/40k"
RESULTS_DIR="$USER_DIR/test_results/scenarios"
PRESERVE_PATH="${SCENARIO_PATH#40k/}"

RUN1_DIR=$(mktemp -d -t loop_det1_XXXXXX)
RUN2_DIR=$(mktemp -d -t loop_det2_XXXXXX)
trap "rm -rf $RUN1_DIR $RUN2_DIR" EXIT

echo "[determinism] scenario:    $SCENARIO_ID"
echo "[determinism] run1 dir:    $RUN1_DIR"
echo "[determinism] run2 dir:    $RUN2_DIR"

_run_once() {
    local target_dir="$1"
    rm -f "$RESULTS_DIR/${SCENARIO_ID}_step_"*.png 2>/dev/null || true
    export SCENARIO_SCREENSHOT_EVERY_STEP=1
    xvfb-run -a godot --path 40k --scenario-file="$PRESERVE_PATH" \
        > "$target_dir/scenario.log" 2>&1
    local exit_code=$?
    cp "$RESULTS_DIR/${SCENARIO_ID}_step_"*.png "$target_dir/" 2>/dev/null || true
    cp "$RESULTS_DIR/${SCENARIO_ID}.json" "$target_dir/" 2>/dev/null || true
    return $exit_code
}

echo ""
echo "[determinism] run 1/2"
if ! _run_once "$RUN1_DIR"; then
    echo "[determinism] HALT run 1 scenario failed; tail of log:"
    tail -20 "$RUN1_DIR/scenario.log"
    exit 2
fi

echo "[determinism] run 2/2"
if ! _run_once "$RUN2_DIR"; then
    echo "[determinism] HALT run 2 scenario failed; tail of log:"
    tail -20 "$RUN2_DIR/scenario.log"
    exit 2
fi

echo ""
echo "[determinism] comparing per-step frames"
python3 - "$RUN1_DIR" "$RUN2_DIR" <<'PYEOF'
import os, sys, subprocess
try:
    from PIL import Image
    import imagehash
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet",
                           "--user", "Pillow", "imagehash"])
    from PIL import Image
    import imagehash

run1, run2 = sys.argv[1], sys.argv[2]
shots1 = sorted(f for f in os.listdir(run1) if f.endswith(".png"))
shots2 = sorted(f for f in os.listdir(run2) if f.endswith(".png"))
if shots1 != shots2:
    only1 = sorted(set(shots1) - set(shots2))
    only2 = sorted(set(shots2) - set(shots1))
    print(f"[determinism] FAIL run produced different file sets")
    if only1: print(f"  only in run 1: {only1[:5]}")
    if only2: print(f"  only in run 2: {only2[:5]}")
    sys.exit(1)

drifted = []
max_d = 0
for name in shots1:
    h1 = imagehash.phash(Image.open(os.path.join(run1, name)))
    h2 = imagehash.phash(Image.open(os.path.join(run2, name)))
    d = h1 - h2
    if d > max_d:
        max_d = d
    if d > 0:
        drifted.append((name, d))

print(f"[determinism] frames compared: {len(shots1)}")
print(f"[determinism] max hamming:     {max_d}")
if drifted:
    print(f"[determinism] DRIFTED steps:")
    for name, d in drifted[:10]:
        print(f"  {name}  hamming={d}")
    sys.exit(1)
print(f"[determinism] OK every frame identical across runs")
PYEOF

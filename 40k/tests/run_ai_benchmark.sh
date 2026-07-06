#!/bin/bash
# AI-vs-AI benchmark: play N full games headless and report win rate / VP
# differential. Use it to verify an AI change actually wins more games, or to
# compare parameter profiles (AIDecisionMaker load_player_profile format).
#
# Usage:
#   bash 40k/tests/run_ai_benchmark.sh [GAMES] [FIXTURE] [P1_PROFILE] [P2_PROFILE]
#
#   GAMES       number of games (default 3)
#   FIXTURE     save fixture to start from (default audit_baseline_postdeploy —
#               Custodes P1 vs Orks P2, round 1 Command, post-deployment)
#   P1_PROFILE / P2_PROFILE  optional parameter-override JSON paths
#
# Env overrides: BENCH_DIFFICULTY (default 1=Normal), BENCH_TIME_SCALE (3),
#   BENCH_MAX_SECONDS (600), BENCH_SEED_BASE (1000)
#
# Output: per-game JSON under <godot-userdata>/test_results/bench/ + an
# aggregated bench_report.json/md, summary printed to stdout.

set -u

GAMES="${1:-3}"
FIXTURE="${2:-audit_baseline_postdeploy}"
P1_PROFILE="${3:-}"
P2_PROFILE="${4:-}"
DIFFICULTY="${BENCH_DIFFICULTY:-1}"
TIME_SCALE="${BENCH_TIME_SCALE:-3}"
MAX_SECONDS="${BENCH_MAX_SECONDS:-600}"
SEED_BASE="${BENCH_SEED_BASE:-1000}"

cd "$(dirname "$0")/.."
export PATH="$HOME/bin:$PATH"

# Fixtures live in tests/saves but load from saves/
mkdir -p saves
cp -n tests/saves/*.w40ksave saves/ 2>/dev/null || true

# Resolve the userdata dir for this platform (where user:// lands)
USERDATA=$(godot --headless --path . --quit-after 1 2>/dev/null >/dev/null; echo "$HOME/.local/share/godot/app_userdata/40k")
if [ "$(uname)" = "Darwin" ]; then
    USERDATA="$HOME/Library/Application Support/Godot/app_userdata/40k"
fi
BENCH_DIR="$USERDATA/test_results/bench"
mkdir -p "$BENCH_DIR"

STAMP=$(date +%Y%m%d_%H%M%S)
echo "================================================================"
echo "AI benchmark: $GAMES game(s), fixture=$FIXTURE, difficulty=$DIFFICULTY"
echo "profiles: P1='${P1_PROFILE:-default}' P2='${P2_PROFILE:-default}'"
echo "================================================================"

RESULTS=()
for i in $(seq 1 "$GAMES"); do
    SEED=$((SEED_BASE + i))
    OUT_REL="test_results/bench/${STAMP}_game_${i}.json"
    echo "--- game $i/$GAMES (seed $SEED) ---"
    ARGS=(--headless --path . -- --ai-benchmark
        "--bench-fixture=$FIXTURE" "--bench-seed=$SEED"
        "--bench-out=$OUT_REL" "--bench-difficulty=$DIFFICULTY"
        "--bench-time-scale=$TIME_SCALE" "--bench-max-seconds=$MAX_SECONDS")
    [ -n "$P1_PROFILE" ] && ARGS+=("--bench-p1-profile=$P1_PROFILE")
    [ -n "$P2_PROFILE" ] && ARGS+=("--bench-p2-profile=$P2_PROFILE")

    timeout $((MAX_SECONDS + 120)) godot "${ARGS[@]}" 2>&1 | grep -E "^\[AIBench\]" | tail -4
    RESULTS+=("$BENCH_DIR/${STAMP}_game_${i}.json")
done

# Aggregate
python3 - "$BENCH_DIR/${STAMP}_report" "${RESULTS[@]}" <<'PYEOF'
import json, sys

report_base, paths = sys.argv[1], sys.argv[2:]
games = []
for p in paths:
    try:
        games.append(json.load(open(p)))
    except Exception as e:
        games.append({"status": "missing", "note": str(e), "path": p})

completed = [g for g in games if g.get("status") == "completed"]
stalled = [g for g in games if g.get("status") in ("stalled", "error", "missing")]
p1_wins = sum(1 for g in completed if g.get("winner") == 1)
p2_wins = sum(1 for g in completed if g.get("winner") == 2)
draws = sum(1 for g in completed if g.get("winner") == 0)
diffs = [g.get("vp_diff_p2_minus_p1", 0) for g in completed]
avg_diff = sum(diffs) / len(diffs) if diffs else 0.0

summary = {
    "games": len(games), "completed": len(completed), "stalled_or_error": len(stalled),
    "p1_wins": p1_wins, "p2_wins": p2_wins, "draws": draws,
    "avg_vp_diff_p2_minus_p1": round(avg_diff, 2),
    "per_game": [
        {"seed": g.get("seed"), "status": g.get("status"), "winner": g.get("winner"),
         "vp_p1": g.get("vp", {}).get("player1", {}).get("total"),
         "vp_p2": g.get("vp", {}).get("player2", {}).get("total"),
         "rounds": g.get("battle_round"), "actions": g.get("actions_taken"),
         "wall_seconds": round(g.get("wall_seconds", 0), 1), "note": g.get("note", "")}
        for g in games],
}
json.dump(summary, open(report_base + ".json", "w"), indent=2)

lines = ["# AI benchmark report", "",
         f"Games: {summary['games']} (completed {summary['completed']}, stalled/error {summary['stalled_or_error']})",
         f"P1 wins: {p1_wins}  P2 wins: {p2_wins}  Draws: {draws}",
         f"Avg VP diff (P2-P1): {summary['avg_vp_diff_p2_minus_p1']}", "",
         "| seed | status | winner | VP P1 | VP P2 | rounds | actions | wall s | note |",
         "|---|---|---|---|---|---|---|---|---|"]
for g in summary["per_game"]:
    lines.append("| {seed} | {status} | {winner} | {vp_p1} | {vp_p2} | {rounds} | {actions} | {wall_seconds} | {note} |".format(**g))
open(report_base + ".md", "w").write("\n".join(lines) + "\n")

print()
print("\n".join(lines))
print(f"\nreport: {report_base}.md")
PYEOF

echo "================================================================"

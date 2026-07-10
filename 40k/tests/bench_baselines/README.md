# AI benchmark baselines

Committed snapshots of AI-vs-AI benchmark soaks (`tests/run_ai_benchmark.sh`),
so any AI change can be judged against a known reference instead of vibes.

## Workflow

1. Run a soak on the candidate build (two lanes, same seeds, both difficulties):

   ```bash
   BENCH_DIFFICULTY=1 BENCH_MAX_SECONDS=420 BENCH_SEED_BASE=2000 bash 40k/tests/run_ai_benchmark.sh 10
   BENCH_DIFFICULTY=2 BENCH_MAX_SECONDS=420 BENCH_SEED_BASE=2000 bash 40k/tests/run_ai_benchmark.sh 10
   ```

   Reports land in `<godot-userdata>/test_results/bench/<stamp>_report.{json,md}`.

2. Compare against the newest file in this directory:
   - **Stall count is a hard gate** — any new `stalled`/`error` game is a
     regression to root-cause (the seed reproduces it deterministically:
     dice AND secondary-deck draws are seeded).
   - Win rate / average VP differential are directional — with 10 games per
     lane, treat swings under ~2 games or ~10 VP as noise.

3. When a deliberate AI change shifts the numbers, commit the new report here
   as `YYYY-MM-DD_<label>.md` (copy the generated markdown, add a header
   noting the commit hash and what changed) so the history of AI strength is
   in the repo.

## Fixture

`audit_baseline_postdeploy` — Adeptus Custodes (P1) vs Orks (P2), round 1
Command phase, post-deployment, Take and Hold / Search and Destroy. P1 wins
most games at both difficulties in current baselines; the interesting signals
are the stall count, the P2 VP trend, and cross-difficulty deltas.

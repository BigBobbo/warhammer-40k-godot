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

## The frozen baseline (B0, 2026-08)

Everything above compares a candidate against **today's** build. That answers
"did this change help?" and cannot answer "is the AI better than it was?" —
the reference moves with the code.

`40k/data/ai_profiles/baseline_2026_08.json` pins an opponent that never
improves: an explicit value for all 238 manifest parameters, tagged
`ai-baseline-2026-08` at `333f23f`. Measure against it with
`tools/ai_lab/vs_baseline.py`, and read
`2026-08_frozen_baseline.md` for the A/A reference numbers, the self-test,
and the re-freeze policy.

**When to re-freeze:** only at a genuine milestone — a profile that cleared
`gate_candidate.py`, or a structural change that makes the old baseline
unrepresentative of anything anyone would play. **Never edit a freeze in
place, and never delete one.** A new freeze is a new file, a new tag and a new
report; the ladder (margin against 2026-08 rising release over release) is the
whole point of having one, and it evaporates the moment a freeze is edited.


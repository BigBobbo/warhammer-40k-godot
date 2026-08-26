# LLM Commander harness

Runs seeded AI-vs-AI games under `PlanSimulator` while an external LLM
("the commander") rewrites one seat's standing earmarks every battle
round, injected mid-game over the MCP bridge. **Zero engine changes** —
the whole mechanism is `AIDecisionMaker.set_player_plan()` plus
`Engine.time_scale` control from outside.

Design, recon evidence and the measurement protocol live in
`.llm/llm-commander-experiment.md`. Results:
`40k/tests/bench_baselines/2026-08-26_llm_commander.md`.

## Prerequisites

- The game running windowed with the MCP bridge up
  (`godot --path 40k --rendering-method gl_compatibility`, bridge on
  127.0.0.1:9080).
- `claude` CLI on PATH (the brain calls `claude -p --model <model>`).

## Usage

```bash
python3 commander.py --seat 1 --seeds 5001-5006 --label arm_c1
python3 commander.py --seat 2 --seeds 5001-5006 --label arm_c2
python3 commander.py --seat 1 --seeds 5001 --label pilot
```

One process per arm; one `PlanSimulator.start({games:1, seed_base:N})`
per seed (proven seed-deterministic across repeated in-process calls).
Every event — snapshot sizes, raw directives, sanitizer drops, injection
readbacks, per-game verification — is journaled to
`runs/<stamp>_<label>.jsonl`.

## How a round is commanded

1. Watcher polls round/phase/active player (bridge `execute_script`).
2. Near the commanded seat's COMMAND phase (opponent's CHARGE/FIGHT, or
   the deployment tail for round 1) → `Engine.time_scale = 1.0` so the
   sub-second phase can't slip between polls.
3. On catching COMMAND → `Engine.time_scale = 0.0`. This is a true
   freeze: AI pacing is delta-driven, nothing divides by delta, and the
   bridge polls its socket per rendered frame, delta-free (all verified;
   up to ~2 in-flight actions land after the freeze, then full stasis —
   measured outcome-neutral: a frozen A/A game reproduces the anchor
   margin exactly).
4. Snapshot (`snapshot.gd`, ~4KB: VP/CP, per-objective OC computed with
   `MissionManager.model_in_objective_range`, per-unit state), then
   `brain.py` → `claude -p` → JSON directive → sanitize → inject via
   `set_player_plan`. Consumed when the seat's movement phase builds its
   assignment (COMMAND precedes MOVEMENT, so same turn).
5. Unfreeze to time_scale 10. Freeze budget ≤ ~65s (brain timeout 60s,
   keep-previous fallback) — safely under the engine's hard-coded 90s
   wall-clock stall watchdog.

## Verification per game

The run row records `with_earmark` / `movement_records` — movement
decision records whose context carries a consumed earmark — plus
margin/status/stalls from the `user://plan_sim_results/` summary. A game
with zero consumed earmarks after injections is a failed game, not
evidence.

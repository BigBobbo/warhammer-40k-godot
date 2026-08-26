# LLM Commander experiment — plan and protocol (2026-08-26)

The question this answers, raised while dissecting the Custodes negative
result (`40k/tests/bench_baselines/2026-08-26_auric_vice.md`): static plans
lost because they are rigid — so does a **turn-adaptive commander** that
rewrites the standing directives every battle round from live game state
beat the no-plan formula? This is the C2b "BattlePlan reviewed each command
phase" slot from `.llm/ai-overhaul-todo.md`, with an LLM as the reviewer,
run **entirely from outside the engine** over the MCP bridge — zero engine
changes.

## Architecture (every piece recon-verified against source, key ones live)

```
commander.py (external, python)
  │ polls GameState round/phase/active_player via bridge (1s wall)
  │ at the commanded seat's COMMAND phase each round:
  ├─ freeze:    Engine.time_scale = 0.0        (AI pacing is delta-driven →
  │             fully stops; MCP bridge polls per-frame, delta-free → alive)
  ├─ snapshot:  compact commander view (~4KB JSON: VP/CP, per-objective
  │             OC+holder via MissionManager.model_in_objective_range,
  │             per-unit alive/wounds/centroid/reserve/engaged)
  ├─ brain:     `claude -p --model claude-sonnet-5` → JSON earmark directive
  │             (~23s measured; 60s timeout → keep previous directives)
  ├─ inject:    AIDecisionMaker.set_player_plan(seat, {name, earmarks})
  │             (static, no validation, read live; auto-match cannot shadow
  │             it; consumed when the next movement phase builds its
  │             assignment — command phase precedes movement, so directives
  │             land in the same player turn)
  └─ unfreeze:  Engine.time_scale = <sim's configured value>
```

Games run under `PlanSimulator.start({games: 1, seed_base: <seed>, ...})`
per seed — proven clean and seed-deterministic across repeated in-process
calls (`tests/test_plan_simulator.gd` asserts identical outcomes for
back-to-back same-seed runs; per-game seed = seed_base + index applied to
all four RNG channels after a full reset).

## Load-bearing facts (from the recon workflow, file:line in its journal)

- `AIDecisionMaker.set_player_plan(player, dict)` — static var storage,
  verbatim, no validation; earmarks-only subset is fine; `_resolve_plan_for`
  checks the explicit plan before the auto-match flag on every call.
- Earmark HOLD targets are **global** objective ids (seat 2's home is
  literally `obj_home_2`); unit ids resolve through
  `PlanManager.resolve_unit_id` (live ids work verbatim for either seat).
- Injecting during the seat's own movement phase is too late for that
  phase (assignment already built) → intervene at its command phase.
- `Engine.time_scale = 0.0` is a true freeze (nothing divides by delta);
  the bridge stays responsive (probed empirically). Use 0.0, never 0.01
  (AI still acts at 0.01). Avoid bridge commands that await scaled timers
  while frozen (`wait_seconds` etc.).
- **Stall limit: 90s wall-clock, hard-coded** (`DEFAULT_STALL_SECONDS` →
  GameWatcher local). A freeze stretch over ~90s marks the game stalled.
  Budget: freeze ≤75s; brain timeout 60s with keep-previous fallback.
  PlanSimulator sets time_scale once per run and never fights a mid-game
  change.
- Plans are wiped between games (`configure → clear_all_plans`) → the
  harness re-injects every round of every game anyway.
- Completion detection: `is_running()` flip; results JSON per run in
  `user://plan_sim_results/` (headline margin sign = P1 − P2).

## Measurement protocol

Matchup: custodes_lions mirror, hammer_anvil / take_and_hold_mirror_1 /
take_and_hold, difficulty 1, time_scale 10 — identical to the static-plan
experiment, so its **A/A anchor transfers**: P1 +10.0 ± 29.1, per-seed
margins [−20, +4, +64, −22, +10, +24] for seeds 5001–5006 (engine code
unchanged since; verified by an anchor spot-check, see below).

- **Anchor spot-check** (before any commander game): re-run A/A seed 5001
  (`games:1`), assert margin == −20. Proves determinism transfers across
  the container rebuild; if it fails, re-run the full A/A anchor.
- **Arm C1**: commander on seat 1, formula seat 2 — `games:1` × seeds
  5001–5006 (plan1/plan2 both "", commander injects seat 1 each round).
- **Arm C2**: commander on seat 2 — same seeds.
- Per game validity: status completed, no stall/timeout, ≥4 commander
  directives injected and confirmed consumed (readback `in_force`, and
  ≥1 movement decision record carrying a `plan_earmark`/`earmark` term).
  A game invalidated by a *harness* fault (bridge disconnect, brain crash)
  is re-run at the same seed and the fault logged; a game the engine
  stalls/times out on its own counts against the run and is reported.
- Analysis: seed-paired deltas vs the A/A anchor per arm; seat-cancelled
  effect = (C1_paired − C2_paired)/2 relative to anchor; win counts.
  Same honesty bar as the static-plan report: publish whatever the number
  is; ship nothing player-facing (this is an experiment harness).

## Commander brain contract

Input: system-style preamble (verb vocabulary + semantics as implemented:
HOLD +8 additive prior on that objective, PUSH_CENTER +6 on central,
HUNT_CHARACTERS +4 vs CHARACTERs, SCREEN withholds from objective passes;
one earmark per unit; released under 50% strength; scoring brackets and
seat orientation) + the JSON snapshot + previous round's directive + VP
trend. Output: strict JSON `{"earmarks": [...], "reasoning": "..."}`.
Harness sanitizes: unknown units/verbs/targets dropped (logged), one
earmark per unit, HOLD requires a live objective id. Latency measured
23s (claude-sonnet-5, 2026-08-26); every call + response + latency is
journaled per game for the report.

## Deliverables

1. `40k/tools/llm_commander/` — `commander.py` (orchestrator + watcher +
   injector), `brain.py` (claude -p wrapper), `snapshot.gd` (bridge
   snippet, live-verified), `README.md`.
2. Run journals (JSONL, one per game) under the tool's `runs/` (gitignored
   except the measured runs' copies archived with the report).
3. `40k/tests/bench_baselines/2026-08-26_llm_commander.md` — full numbers,
   verdict, and what it implies for C2b.
4. Playbook/roadmap notes; no changelog entry (dev tooling only).
5. Committed on `claude/plan-maker-todo-w0syuf`, PR to main, merged.

## Risks / known limits (stated up front)

- 6 games/arm resolves only ≥~15 VP effects (sd 14–40) — same resolution
  as the static-plan experiment it compares against.
- The commander model's calls are non-deterministic across runs; the
  *engine* stays seeded, so paired analysis holds per run but an exact
  re-run of a commander arm will differ. The journals preserve what was
  decided for audit.
- One commander model tested (claude-sonnet-5 via `claude -p`); the result
  is about *this* commander, not LLM commanders in general.
- Freeze/stall race: a brain call over ~75s risks a stall mark; mitigated
  by the 60s timeout + keep-previous fallback, and validity checks catch
  any slip.

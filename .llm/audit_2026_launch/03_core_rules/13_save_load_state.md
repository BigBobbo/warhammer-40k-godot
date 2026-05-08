# 03.13 — Save / Load State

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_13_save_load.md`

## Scope

Pure-state regression net. Headless verification is sufficient (no UI surface). Audit:
- Every autoload's persisted state round-trips through save → reload
- Per-unit flags (`battle_shocked`, `charged_this_turn`, `advanced_this_turn`, `fell_back_this_turn`, `disembarked_this_phase`, `oath_of_moment_target`, etc.)
- Stratagem usage counters (`stratagems_used_this_phase`, `_this_battle`, CP cap counters)
- Phase manager state (current phase, step, active player, round)
- Mission state (objective control, primary scored per turn, secondary statuses)
- Random number generator determinism — `T7-46`/`#348` open per memory; verify a save/restore preserves the seed and a re-played turn produces the same dice
- Detachment rule one-shot states (per-round Martial Mastery selection, Waaagh! used, etc.)
- Leader attachment relationships and detached-character status

## Codebase entry points

`40k/autoloads/StateSerializer.gd`, `40k/autoloads/GameState.gd`, `40k/autoloads/CloudStorage.gd`, every autoload that holds gameplay state. Existing tests under `40k/tests/test_save_*.gd`.

## Method

Headless. Use existing `40k/tests/run_pretrigger_tests.sh` and pre-trigger fixtures (`40k/saves/*_pretrigger.w40ksave`). For each pre-trigger save:
1. Load
2. Capture state snapshot
3. Save → reload → recapture
4. Diff the two snapshots; any non-empty diff is a finding

## Prior-audit overlap

- Standard fields (`state.units`, `state.players`, `state.meta`, unit flags) round-trip — verified 2026-05 (#338 open at file time, autoload-state pattern bug identified)
- Determinism property not tested via multi-run save/restore — open per memory; verify state of #348

## Output prose

Top 3 launch-blocker save/load gaps; top 3 silent-divergence cases (where a flag silently resets vs. should persist). Save-system regressions are catastrophic for player trust — this is one of the highest-priority audit surfaces for launch.

# PM-8a — SPIKE: two (three) back-to-back in-session AI games

**Date:** 2026-08-11
**Branch:** `claude/plan-maker-todo-w0syuf`
**Driver:** `40k/tests/spikes/pm8a_inline_reset_spike.gd`
**Task:** `.llm/plan-maker-todo.md` → PM-8a
**Question:** can this build run consecutive from-menu AI-vs-AI games in ONE
process with a clean state reset — the load-bearing unknown of the PM-8b/PM-9
simulator?

---

## VERDICT

**In-session reset is VIABLE.** Three consecutive from-menu AI-vs-AI games ran
to completion in one process, ~10–14 s each, with no stalls, no errors, correct
unit counts at every game start — **and two games seeded identically produced
byte-identical outcomes.**

That last clause is the load-bearing one, and it is **not** true with the reset
list the task text proposed. The proven reset list is below; PM-8b must
implement all of it.

```
game 1 (seed 8100): completed  round 5  205 actions  VP 35–66   11.4 s
game 2 (seed 8101): completed  round 5  264 actions  VP 55–37   14.0 s
game 3 (seed 8100): completed  round 5  205 actions  VP 35–66   10.4 s

determinism (game 1 vs game 3, same seed):
  {"same_seed": true, "identical": true, "mismatches": {},
   "first_action_divergence_index": -1}

stderr over the whole 3-game run:
  SCRIPT ERROR: 0
  "Lambda capture ... was freed": 0
  "Nonexistent function 'update_control'": 0
```

Game 2 at a different seed produced a genuinely different game (264 actions,
55–37), so the determinism result is not an artifact of the games collapsing
into one another.

Subprocess-per-game was not needed and is not recommended: the documented
`tests/helpers/GameInstance.gd` flakiness and the web export both rule it out,
and this spike shows it is unnecessary.

Run it with:

```bash
export PATH="$HOME/bin:$PATH"
godot --headless --path 40k -s tests/spikes/pm8a_inline_reset_spike.gd
# writes user://pm8a_spike_result.json
# env knobs: PM8A_GAMES, PM8A_SEEDS (csv), PM8A_TIME_SCALE, PM8A_OUT
```

---

## The proven reset list for PM-8b

Ordering is part of the answer: **stand the AI down, reset the autoloads, and
only then build the new game.** Resetting after the bootstrap wipes state the
bootstrap just populated (`StratagemManager.reset_for_new_game()` clears the
faction stratagems that applying the armies had just loaded).

| # | Step | Why — evidence |
|---|---|---|
| 1 | `AIPlayer.configure({1:"HUMAN",2:"HUMAN"})` **before** tearing the game down | Between games AIPlayer is still `enabled` with `_needs_evaluation`/`_ai_thinking` set. It keeps acting while the new game is assembled; Main's later `configure()` then wipes `_action_log`, hiding that it did. **Fixing only this moved the first action-trace divergence from index 0 to index 23.** |
| 2 | `StratagemManager.reset_for_new_game()` | Proven leak: `_usage_history` was 8/8 after game 1 and survived the bootstrap untouched. |
| 3 | `UnitAbilityManager.reset_for_new_game()` | No leak observed **in this army** (all once-per-battle counters stayed 0 — the 3-unit Custodes list never used one). Kept because the method has **no production caller at all**, so the risk is unproven rather than disproven. |
| 4 | `PhaseManager.reset()` **plus** `_last_round_started = -1` | `reset()` clears `game_ended` and the phase instance (both proven dirty: `game_ended` stayed `true` through the bootstrap). It does **not** clear `_last_round_started`, which stayed at 5. |
| 5 | Re-initialise **`FactionAbilityManager`**'s per-game dictionaries | **The determinism-breaker.** It has no reset entry point of any kind. `_active_mastery` / `_mastery_selected_round` carried game 1's values into game 2, so game 2 skipped `SELECT_MARTIAL_MASTERY` entirely and the whole game diverged from there. Fields: `_active_effects`, `_player_abilities`, `_waaagh_used`, `_waaagh_active`, `_boss_watchin_used`, `_plant_waaagh_banner_used`, `_player_detachment`, `_doctrines_used`, `_active_doctrine`, `_active_mastery`, `_mastery_selected_round`, `_loot_objective`, `_loot_objective_round`, `_da_kaptin_used_round`, `_bionik_workshop_results`, `_bionik_workshop_resolved`, `_razgit_redeploys_used`, `_razgit_resolved`, `_morks_kunnin_redeploys_used`, `_aao_status`. |
| 6 | `MissionManager`: clear `_units_alive_at_round_start` and `objectives_visual_refs` | `initialize_mission()` clears a lot but not these; both were still holding game 1's values at game 2's first live frame. |
| 7 | `MissionManager`: **disconnect the stale lambda receivers** on `objective_control_changed` / `objective_removed` | See "The lambda leak" below. Removed 105 ERROR lines. |
| 8 | `ActionLogger._initialize_session()` (+ clear `session_actions` / `action_sequence` / `initial_snapshot`), `GameEventLog.entries.clear()`, `ReplayManager.stop_recording()` | No reset entry points; unbounded growth across a long run. `ActionLogger.session_actions` was 257 and `GameEventLog.entries` 570 at game 2's bootstrap. |
| 9 | Seed a **fourth** RNG channel: the GLOBAL RNG, `seed(game_seed)` | The documented "seeding triple" (`RulesEngine.set_test_seed`, `SecondaryMissionManager.set_test_seed`, `AIDecisionMaker.set_ai_seed`) does not cover `Array.shuffle()` / `randi()` / `randf()`, which draw from the global generator. A fresh process starts that generator from a fixed default — which is exactly why two separate processes agreed — but its state carries over between in-session games. Seeding it changed game 2's outcome on its own, so it is a real channel. |

Steps 2–4 were the task text's candidates. **They are necessary but not
sufficient**: with only those, two same-seed games differed (205 vs 189 actions,
VP 35–66 vs 42–66).

---

## How the answer was reached (the experiments)

Each row is a run of the same driver; only the reset list changed.

| Experiment | Result |
|---|---|
| 3 games, seeds [8100, 8101, 8100], task-text resets only | All 3 completed. **Game 3 ≠ game 1** (189 actions / 42–66 vs 202 / 35–66). |
| **Control:** same seed 8100 in two *separate processes* | **Identical** (202 actions, 35–66, both runs). So the divergence is in-session leakage, not the driver's seeding and not wall-clock pacing. |
| 2 games, both seed 8100, in-session | Diverged the same way (189 / 42–66). One game of leakage is enough, and the leaked state is itself deterministic — the "second game" result is stable and repeatable. |
| + seed the global RNG | Outcome *changed* (194 / 34–54) but still ≠ game 1 → a real channel, not the whole story. |
| + AI quiesce before rebuild | First action-trace divergence moved from **index 0 → index 23**. Formations, roll-off, deployment and scout moves became identical. |
| + reset ordering (resets *before* bootstrap) | Divergence stayed at index 23, on a `SELECT_MARTIAL_MASTERY` / `USE_NEW_ORDERS` vs `REPLACE_SECONDARY_MISSION` split — pointing at FactionAbilityManager. |
| + FactionAbilityManager reset + steps 6–8 | **Identical.** 3 same-seed games: 205 actions, VP 35–66, `first_action_divergence_index: -1`. |

The instrument that made this tractable: the driver captures the first 60
entries of `AIPlayer._action_log` per game and reports the **index of the first
differing action**, so "these two games diverge" becomes "these two games
diverge at the second player's first COMMAND phase, on a faction-ability
decision". A whole-autoload size fingerprint
(`_autoload_fingerprint()`, every script-declared Array/Dictionary/bool/int on
17 autoloads) found the log/record leaks. It did **not** find the
FactionAbilityManager leak, because those are fixed-shape `{"1": …, "2": …}`
dictionaries whose *size* never changes — a blind spot worth knowing about.

---

## The lambda leak (separate bug, cosmetic but gate-breaking)

`Main._setup_objectives()` (`scripts/Main.gd:5186-5191`) connects a lambda to
the `MissionManager.objective_control_changed` autoload signal that **captures
the `ObjectiveVisual` scene node**:

```gdscript
MissionManager.objective_control_changed.connect(
    func(obj_id, controller, old_ctrl):
        if obj_id == obj.id:
            obj_visual.update_control(...)
```

MissionManager outlives the scene, so the connection does too. Measured
accumulation across three games: **5 → 10 → 15 receivers** (one per objective
per game). Every control change in game 2 then fired game 1's dead lambdas:

```
ERROR: Lambda capture at index 1 was freed. Passed "null" instead.
SCRIPT ERROR: Invalid call. Nonexistent function 'update_control' in base 'Nil'.
          at: <anonymous lambda> (res://scripts/Main.gd:5188)
```

35 + 7 in a 2-game run, **105 in a 3-game run — zero in game 1**.

It does not affect game logic (determinism holds with the errors present), but
it **does** break the project's `verify_delivery` / `read_debug_log` no-ERROR
gate, which PM-9's simulator UI will have to pass.

Fix used here, proven to take the count to 0: at reset time, disconnect every
**lambda** receiver on those signals (`Callable.is_custom()`), which
`Main._setup_objectives()` then re-creates for the new scene; named-method
connections from live autoloads are left alone. Note that the obvious guard —
`is_instance_valid(callable.get_object())` — does **not** work: a freed *receiver*
auto-disconnects, but a lambda's bound object outlives the scene while its
*captures* do not, so the connection looks healthy and Godot keeps calling it.
An unconditional `is_custom()` sweep is required. A tidier long-term fix is for
Main to disconnect on `_exit_tree`, but that is production code and out of PM-8a's
scope.

---

## Other notes for PM-8b

- **Speed.** ~10–14 s per game for a 3-unit/6-model Custodes mirror at
  `Engine.time_scale = 10`, running the *full* game (FORMATIONS → ROLL_OFF →
  DEPLOYMENT → 5 battle rounds). PM-9's ETA copy should be driven by the
  measured s/game after game 1, not by these numbers — real 2000-pt lists are
  far slower (bench baselines: ~2.5 min Custodes, ~8 min Orks).
- **A from-menu AI-vs-AI game works end to end.** This path is not covered by
  `AIBenchmarkRunner`, which is fixture-only and starts post-deployment. The AI
  handles FORMATIONS confirm, the deployment roll-off and the deployment phase
  unaided.
- **`ReplayManager.stop_recording()` does not clear `_recording_events` /
  `_recording_snapshots`** (231 / 24 still present at the next game's
  bootstrap). Harmless for determinism, but it is unbounded across a long run —
  PM-8b should clear them explicitly if it leaves `auto_record_ai` on.
- **Do not preload autoload-touching scripts from a `-s` driver.** Preloading
  `res://autoloads/GameState.gd` emits, at boot,
  `Compile Error: Identifier not found: Measurement` (DeploymentZoneData.gd:61)
  and `Identifier not found: GameState` (FactionPalettes.gd:202): autoload
  identifiers do not resolve while the `-s` script's preload graph is compiled,
  because autoloads enter the tree afterwards. Reach everything through
  `root.get_node_or_null()` / `load()` at run time, and defer the driver body
  with `create_timer(...).timeout.connect(...)`.
- **Not wired into `run_pretrigger_tests.sh`** — it plays whole games.

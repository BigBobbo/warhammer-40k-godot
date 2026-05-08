# 03.13 — Save / Load State

**Audit date:** 2026-05-06
**Method:** Headless GDScript round-trips against `40k/saves/{co,hi,ri}_pretrigger.w40ksave`
**Test:** `40k/tests/test_save_load_audit_roundtrip.gd` — 115 passed, 5 failed (each failure is an audit finding)
**Source-of-truth:** `SAVE_AUDIT.md`, prior audit `40k/test_results/audit_2026_05/AUDIT_REPORT.md`, autoload code under `40k/autoloads/`
**Scope:** pure-state round-trip — save → mutate live → reload → diff snapshot. No live MCP needed (per prompt).

---

## Audit row schema

| Rule | Source | Depth | Correctness | Evidence | Notes |
|---|---|:---:|:---:|---|---|

| `state.units` round-trip (positions, status, wounds, models[].alive, models[].current_wounds) | SAVE_AUDIT.md §1 | C/W | ✅ VERIFIED (regression spot-check) | `tests/test_save_load_audit_roundtrip.gd` lines 88–119 — all 26 units round-trip cleanly across all 3 pretrigger fixtures; sampled flags `moved/advanced/fell_back/charged_this_turn/battle_shocked/remained_stationary/fired_overwatch` all match across save→reload | Standard fields verified 2026-05; this run regression-confirms. |
| `state.players.{cp, vp, primary_vp, secondary_vp}` round-trip | SAVE_AUDIT.md §1 | W | ✅ VERIFIED (regression spot-check) | `tests/test_save_load_audit_roundtrip.gd` lines 81–86 — CP and VP for both players round-trip across all 3 fixtures | — |
| `state.meta.{phase, active_player, battle_round}` round-trip | SAVE_AUDIT.md §1 | W | ✅ VERIFIED (regression spot-check) | `tests/test_save_load_audit_roundtrip.gd` lines 71–79 — match across all 3 fixtures | — |
| `state.board.{terrain_layout, terrain_features}` round-trip | `GameState.gd:984-989`, `:1133-1148` | W | ✅ VERIFIED | terrain_layout=`layout_2` reloaded from JSON file path on load (path-preferred, dict fallback handles network-serialized variants) | `_restore_terrain_types` at `GameState.gd:1062-1104` handles `PackedVector2Array` round-trip from network JSON. |
| `state.secondary_missions` round-trip via `SecondaryMissionManager` | `GameState.gd:991-997`, `:1150-1157` | W | ✅ VERIFIED | `[GameState] Found secondary mission data in save, restoring` printed in test transcript; SecondaryMissionManager.get_save_data/load_save_data plumbed | — |
| `FactionAbilityManager` once-per-battle locks (Waaagh, Plant Banner, Mastery, Doctrines, Loot Objective, Da Kaptin, Bionik Workshop, Razgit) | `GameState.gd:999-1005`, `:1159-1166`; `FactionAbilityManager.gd:1932-1956` (get_state_for_save), `:1958-1981` (load_state) | W | ✅ VERIFIED (#338 fix regression-spot-check) | `test_audit_fixes_verification.gd:120-149` (in-memory round-trip) + `test_save_load_audit_roundtrip.gd` (whole-save round-trip via SaveLoadManager) — `waaagh_used` and `plant_waaagh_banner_used` survive disk round-trip on all 3 fixtures | #338 fix landed in PR #347. |
| `StratagemManager` once-per-battle/turn/phase usage_history + active_effects + faction stratagems | `GameState.gd:1007-1012`, `:1168-1174`; `StratagemManager.gd:2410-2416` (get_state_for_save), `:2418-2429` (load_state) | W | ✅ VERIFIED (#338 fix regression-spot-check) | `usage_history` round-trips on all 3 fixtures via `test_save_load_audit_roundtrip.gd` | #338 fix landed in PR #347. |
| `MeasuringTapeManager` measurements (when persistence enabled) | `GameState.gd:1023-1035`, `:1186-1195` | W | ✅ VERIFIED | gated by `measuring_tape_manager.save_measurements`; `[GameState] Measuring tape persistence disabled` log line confirms gate is honored when off | — |
| `ai_turn_history` (AIPlayer turn history) | `GameState.gd:1014-1020`, `:1176-1184` | W | ✅ VERIFIED (SAVE-7) | `get_turn_history()` plumbed to snapshot; restoration deferred to `Main._reinitialize_ai_after_load()` | SAVE-7 fix — only `_turn_history`. **See ❌ row below for the rest of AIPlayer state.** |
| **RNG seed survives save → reload** (#348 follow-up) | `RulesEngine.gd:516-517` (`test_mode_seed`, `_test_seed_counter` — class-static), `:557-562` (set/get test seed) | C only | ❌ ABSENT | `test_save_load_audit_roundtrip.gd` `_test_rng_seed_persistence`: set seed=12345, save, mutate to 99999, reload — final seed=**99999** (i.e., the last process-level mutation, not what was in the save) | **#348 carry-over confirmed:** memory item flagged this exact gap ("determinism property not multi-run save/restore tested"); the test now demonstrates it. The save snapshot has no `meta.rng_seed` field, and `RNGService.test_mode_seed` is a static var on the inner class — never written to the snapshot, never read on load. Replaying a turn after a save/reload will diverge from a continuous run with the same seed. |
| **`PhaseManager.game_ended` survives load** (autoload-state pattern bug) | `PhaseManager.gd:14` (member var), `:32` (cleared on `reset_for_new_game`), `:57-58` (cleared on `transition_to_phase(FORMATIONS)`); never written from `state.meta.game_ended` on `load_from_snapshot` | C only | 🐛 PRESENT BUT DIVERGES | `test_save_load_audit_roundtrip.gd` `_test_phase_manager_persistence`: take a baseline save (`meta.game_ended` either false or absent), set `PhaseManager.game_ended=true`, reload — `PhaseManager.game_ended` remains **true**. `Main.gd:7300, :7336, :7390, :7395` all gate behavior on `PhaseManager.game_ended`, so phase advancement is blocked in the loaded game. | **Same shape as #338**. PR #334 fixed the FORMATIONS path (`transition_to_phase(FORMATIONS)` clears it) but a save/load doesn't go through FORMATIONS — it goes through `GameState.load_from_snapshot()`, which never touches `PhaseManager.game_ended`. Save scumming a finished game silently corrupts the next game. |
| **`UnitAbilityManager` once-per-battle / once-per-round ability locks** | `UnitAbilityManager.gd:1432-1457` (member-vars: `_active_ability_effects`, `_applied_this_phase`, `_active_aura_effects`, `_once_per_battle_used`, `_once_per_round_used`, `_mekaniak_used_this_turn`, `_scatter_used_this_turn`); `UnitAbilityManager.gd:3747-3768` (get_state_for_save / load_state EXIST) | C only | ❌ ABSENT (NEVER WIRED) | `test_save_load_audit_roundtrip.gd` `_test_unit_ability_manager_wiring` — `GameState.create_snapshot()` does NOT include a `unit_ability_manager` key. `grep -rn "UnitAbilityManager.get_state_for_save"` in `40k/autoloads/` returns zero matches. | **Repeat of #338 pattern.** API present but no caller. Save/load drops once-per-battle ability usage (e.g. `Mekaniak`, `Da Jump`-style abilities, `Scatter` field) — save scumming resets them. **Add to GameState.gd:1012 alongside the other autoload calls; add restore at GameState.gd:1174.** |
| **`MissionManager` runtime mission state** | `MissionManager.gd:14-68, :606` member vars: `current_mission, objective_control_state, _sticky_objectives, _kills_this_round, _burned_objectives, _pending_burns, _ritual_objectives, _pending_rituals, _terraformed_objectives, _pending_terraforms, _vp_timeline, burn_in_progress, burned_objectives, removed_objectives, supply_drop_resolved_round_4, kills_per_round, character_claimed_objectives, _units_alive_at_round_start` | C only | ❌ ABSENT | `MissionManager` has NO `get_save_data` / `get_state_for_save` method (`test_save_load_audit_roundtrip.gd` `_test_mission_manager_persistence` confirms). `objective_control_state` is rebuilt every check via `check_objective_control()` so that's fine, but `_sticky_objectives`, `_burned_objectives`, `_kills_this_round`, `kills_per_round`, `supply_drop_resolved_round_4`, `_units_alive_at_round_start` are write-only state used for VP scoring math. | **Sticky objectives reset on save/load.** Per Wahapedia, sticky objectives stay sticky until conditions change — save scumming silently breaks this. Likewise: round-4 Supply Drop already-resolved flag (Crucible mission), kills-this-round counter for Bring it Down secondary, etc. Filing as new finding `SL-NEW-1`. |
| **`TurnManager` titanic skip turns** | `TurnManager.gd:15` `_titanic_skip_turns: Dictionary` | C only | ❌ ABSENT | `TurnManager` has no `get_state_for_save` / `load_state`. `_titanic_skip_turns` member var dropped on save. | When this dict is non-empty, a unit is mid-multi-turn skip (titanic-charge enforcement, etc.). Save scum to clear. Filing as `SL-NEW-2`. |
| **`AIPlayer` failed-deploy / pile-in / advance state** | `AIPlayer.gd:22-31` member vars: `_action_log, _failed_deploy_unit_ids, _failed_reinforcement_unit_ids, _failed_transport_ids, _pile_in_retry_units, _pending_advance_moves, _processing_turn, _current_phase_actions` | C only | ⚠️ PARTIAL | only `_turn_history` is saved (SAVE-7); the rest of in-process AI bookkeeping (failed-unit lists, advance roll pending) is dropped. AIPlayer's `reconfigure_ai_after_load()` re-init resets these, which is the desired behavior IF the save was taken at a clean phase boundary — but autosave can fire mid-AI-turn (SAVE_AUDIT §4.2) and the lists then go stale on reload. | SAVE-6 ("Prevent autosave during AI turn") is still open per `SAVE_AUDIT.md` §8 P1 list. AIPlayer state itself is intentional reset; the autosave-mid-turn protection is the missing piece. |
| Save format versioning + migration | `StateSerializer.gd:14-15` (`CURRENT_VERSION="1.1.0"`, `MINIMUM_MIGRATABLE_VERSION="1.0.0"`); migration registry `:43-47`; chained migration loop `:80-110` | W | ✅ VERIFIED | SAVE-3 closed (per `SAVE_AUDIT.md` §8); v1.0.0→v1.1.0 migration path present. Test `test_save_format_migration.gd` exists in repo. | — |
| `_validate_serialized_data` required-section check | `StateSerializer.gd:537-579` | W | ✅ VERIFIED | required: `_serialization, meta, board, units, players`; required meta: `game_id, turn_number, active_player, phase`. Validation runs on every `deserialize_game_state` call. | — |
| `_validate_unit_data` integrity check (SAVE-18) | `StateSerializer.gd:588-` | W | ✅ VERIFIED (regression spot-check) | SAVE-18 unit-data validation triggers on load, returns warnings (auto-repair) and errors. Saw it fire in test transcript: `SAVE-18 WARNING: Unit 'U_GHAZGHKULL_THRAKA_A' model[1]: VEHICLE/MONSTER unit has small base_mm (32) and no base_type`. | Warnings only — does not block load. Could be wired to gate load on errors >0 in future. |
| Cross-platform save path (`res://saves/` vs cloud) | `SaveLoadManager.gd:34-36, :63` | W | ✅ VERIFIED on desktop | desktop tested via fixture round-trips; cloud `save_exists()` always returns false on web — known SAVE-5 (per `SAVE_AUDIT.md` §2.5). | Not in scope for headless audit; flagged for completeness. |

---

## New audit findings (file as new issues)

### SL-NEW-1 — `MissionManager` runtime state not persisted (extends #338 pattern)

**Severity:** High
**Risk:** Save-scumming defeats VP / scoring rules tied to sticky objectives, supply-drop resolution, and per-round kill counters.

`MissionManager` holds 17+ gameplay-bearing member vars (lines 14-68 + 606 of `MissionManager.gd`) but has NO `get_save_data` / `load_save_data` / `get_state_for_save` API. The most critical:

- `_sticky_objectives` — Wahapedia sticky-objective rules require persistence across phases until the locking unit is destroyed.
- `_burned_objectives`, `removed_objectives`, `supply_drop_resolved_round_4` — Crucible-of-Battle mission state.
- `_kills_this_round`, `kills_per_round` — Bring it Down secondary objective scoring.
- `_units_alive_at_round_start` (line 606) — round-snapshot for VP math.
- `_ritual_objectives`, `_terraformed_objectives` and their `_pending_*` queues — terrain-modifying mission effects.

**Fix shape:** add `MissionManager.get_state_for_save() -> Dictionary` returning all the above, `load_state(data: Dictionary)` to restore. Wire into `GameState.create_snapshot()` (next to `faction_ability_manager` at lines 999-1012) and `GameState.load_from_snapshot()` (next to lines 1159-1174).

### SL-NEW-2 — `TurnManager._titanic_skip_turns` not persisted

**Severity:** Low (only used during titanic-class multi-turn lockouts)
**Risk:** Save-scum to clear a titanic charge skip-turn penalty.

`TurnManager` has only one member-var (`_titanic_skip_turns: Dictionary`, line 15) and no save API. Same fix shape as SL-NEW-1.

### SL-NEW-3 — `UnitAbilityManager.get_state_for_save()` exists but is NEVER called (regression of #338 pattern)

**Severity:** High
**Risk:** Once-per-battle / once-per-round unit ability locks (Mekaniak, scatter shield, ability-driven plasma overcharge tracking, etc.) reset on save/load. Save scumming defeats these usage limits.

`UnitAbilityManager.gd:3747-3768` defines `get_state_for_save()` and `load_state(data)` covering 7 dictionaries (`_active_ability_effects`, `_applied_this_phase`, `_once_per_battle_used`, `_once_per_round_used`, `_active_aura_effects`, `_mekaniak_used_this_turn`, `_scatter_used_this_turn`). The methods are correct — but no caller invokes them. The fix is identical to PR #347's #338 fix: 4 lines in `GameState.create_snapshot()` and 4 lines in `GameState.load_from_snapshot()`. **Direct extension of audit memory item `feedback_pin_tests_arent_live_validation` — the feature is "C" not "W".**

### SL-NEW-4 — `PhaseManager.game_ended` not synced from `meta.game_ended` on load (incomplete #330 fix)

**Severity:** Medium
**Risk:** Loading a save into a session whose previous game finished leaves `PhaseManager.game_ended=true`. All phase advancement in the loaded game is then blocked at `Main.gd:7300, :7336, :7390, :7395`.

PR #334 fixed `transition_to_phase(GameStateData.Phase.FORMATIONS)` to clear `game_ended` (`PhaseManager.gd:57-58`). But `SaveLoadManager._load_game_from_path()` does not transition to FORMATIONS — it calls `GameState.load_from_snapshot()` directly, which only touches `state` (the dictionary) and does not assign to `PhaseManager.game_ended`.

`state.meta.game_ended` IS in the saved snapshot (`PhaseManager.gd:277-278` writes it on `_handle_game_end`), so the fix is straightforward: at the end of `GameState.load_from_snapshot()`, do
```gdscript
var pm = get_node_or_null("/root/PhaseManager")
if pm:
    pm.game_ended = state.get("meta", {}).get("game_ended", false)
```

### SL-NEW-5 — RNG seed not persisted in save (extends #348)

**Severity:** Medium (testing/debug surface; player-facing impact: cheating via reload-for-favorable-dice in single-player only — multiplayer always passes explicit seeds)
**Risk:** A turn replayed after save/reload diverges from the same turn replayed continuously, even with identical user actions. Per memory item, this property was flagged at #348 close: "determinism property not tested via multi-run save/restore — game still functions; ... not tested per memory; verify."

`RulesEngine.gd:516-517` defines `test_mode_seed` and `_test_seed_counter` as `static var` on the inner `RNGService` class. Neither is written to the save snapshot. Process-level mutation of `set_test_seed(seed)` survives a load (because the static var is process-global), but the seed-from-the-save value cannot be restored because it isn't there.

**Fix shape:** if determinism-after-load is desired, save `{rng_seed, rng_counter}` into `state.meta` on snapshot creation, restore on `load_from_snapshot`. The spec for this lives outside the audit; flagging as the open determinism question from #348.

---

## Verified items already at L (do not refile)

These items were verified in `40k/test_results/audit_2026_05/AUDIT_REPORT.md` (Tier 5) and re-confirmed by this regression-spot-check run. **Do NOT refile — cite the existing PRs**:

- `state.units` round-trip (positions, status, model wounds, flags) — verified via 3-fixture round-trip pattern in `test_save_load_audit_roundtrip.gd`
- `state.players` round-trip (CP, VP, primary_vp, secondary_vp) — same
- `state.meta` round-trip (phase, active_player, battle_round, game_id, deployment_type) — same
- `FactionAbilityManager` round-trip (closed by PR #347 — issue #338) — verified
- `StratagemManager` round-trip (closed by PR #347 — issue #338) — verified
- `SecondaryMissionManager` round-trip — verified
- Save format migration v1.0.0 → v1.1.0 (closed SAVE-3) — present
- `_validate_unit_data` SAVE-18 — verified

---

## Top 3 launch-blocker save/load gaps

1. **MissionManager runtime state not persisted (`SL-NEW-1`)** — sticky objectives, supply-drop resolution, kill counters reset on save/load. **Direct rule violation** of Wahapedia sticky-objective semantics; affects every game saved mid-mission. P0 launch blocker for save/load reliability.
2. **`UnitAbilityManager` save-API exists but is never called (`SL-NEW-3`)** — same shape as the original #338 bug; once-per-battle / once-per-round ability locks reset on save/load. Save-scumming defeats unit-ability rate limits. P0 launch blocker (player-facing trust + correctness).
3. **`PhaseManager.game_ended` autoload state not restored (`SL-NEW-4`)** — incomplete #330 fix. If the user finished a game then loads a save, the loaded game is frozen because `game_ended=true` persists in the autoload. Recovery is to restart Godot. P1 — silent corruption that's hard to diagnose.

## Top 3 silent-divergence cases (where a flag silently resets vs. should persist)

1. **Sticky objectives reset on every load** (`SL-NEW-1`). UI shows nothing; player thinks objectives are still locked, but on the next `MissionManager.check_objective_control` they aren't. VP totals diverge silently from the rules.
2. **`_kills_this_round` resets to `{"1":0,"2":0}` on load** (`SL-NEW-1`). Bring it Down secondary scores recompute from the live unit list, not from the saved kill count. Saving and loading mid-round resets your secondary score for that round.
3. **RNG seed unrestorable** (`SL-NEW-5` / #348 carryover). A user setting a seed in test mode for reproducibility loses the determinism property the moment they save/load. Affects testing and AI-replay scenarios; not directly visible to a normal player but breaks replay/regression workflows.

---

## Test artifact

Headless test that produced this audit's evidence: `40k/tests/test_save_load_audit_roundtrip.gd`

Run:
```bash
export PATH="$HOME/bin:$PATH"
cd 40k
godot --headless --path . -s tests/test_save_load_audit_roundtrip.gd
```

Expected output (current state): **115 passed, 5 failed**. Each failure corresponds to one of the new findings above:
- `RNG seed is restored from save (expected: 12345 if persisted)` → SL-NEW-5
- `PhaseManager.game_ended is cleared on load` → SL-NEW-4
- `snapshot includes 'unit_ability_manager' key` → SL-NEW-3
- `MissionManager has get_save_data or get_state_for_save` → SL-NEW-1
- `TurnManager has get_state_for_save` → SL-NEW-2

When SL-NEW-1, SL-NEW-3, SL-NEW-4 are fixed via the same pattern as PR #347, this test should reach 120/120.

---

## Live validation note

LIVE-VALIDATION SKIPPED: per audit prompt and `13_save_load_state.md` scope ("Pure-state regression net. Headless verification is sufficient (no UI surface)"). Headless GDScript via `40k/tests/test_save_load_audit_roundtrip.gd` is the canonical validation surface for this audit.

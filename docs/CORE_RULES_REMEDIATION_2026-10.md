# Core-rules remediation — audit of e28e4f7 (2026-10-12)

Fixes for the five ranked live defects in the 2026-10-11 zero-context audit
handoff (pinned to `e28e4f70734dd8ac67233fb8187549a5f02fb5fb`). Each fix is
in the server-authoritative path (phase validator / RulesEngine) so human,
AI, automatic and multiplayer callers get the same result.

Regression net: `40k/tests/test_core_rules_audit_e28e4f7.gd` uses only APIs
that existed at e28e4f7, so it runs on both trees:

| Tree | Result |
|---|---|
| e28e4f7 (pre-fix) | 23 passed, **16 failed** — every defect below reproduces |
| this branch | **39 passed, 0 failed** |

## P0-2 — Mandatory fights (12.04) + the p.74 pass

- **Rule**: "Players resolve the following sequence until all eligible units
  have been selected to fight." Exception (p.74 *Eligible to fight, but
  unable to fight*): a player whose eligible units are ALL more than 5" from
  every enemy unit may pass; the Fight step ends if both pass in succession
  or one passes while the opponent has nothing eligible.
- **Was**: `END_FIGHT` always valid; confirming the warning dialog forfeited
  the ending player's remaining fights. `SKIP_UNIT` could also forfeit any
  unselected eligible unit.
- **Now**:
  - `FightPhase._validate_end_fight` rejects END_FIGHT in the Fight step unless
    the step is over or it is the selecting player's legal pass; also rejects
    it while 12.08 forced fights are pending.
  - `FightSequencer` tracks passes (`passed`, `can_pass`, `pass_selection`,
    `selectable_units`, `step_over`); a pass is not a forfeit — the passer is
    offered their units again once the opponent selects.
  - `FightPhase.get_end_fight_status()` is the single authority used by the
    validator, `get_available_actions`, `Main` (button label / toast /
    dialog), `FightController` (Pass button), `AIPlayer` and the multiplayer
    `GameManager.process_end_fight` path (a pass is delegated to the phase
    instead of ending the phase).
  - `SKIP_UNIT` in the Fight phase only ends the ACTIVE fighter's activation.
- **Evidence**: `tests/test_fight_phase_scope_end_fight_11e.gd` (34/34),
  scenarios `end_fight_mandatory_fights_11e`, `fight_pass_unable_to_fight_11e`.

## P1-5 — Every unit selected before the Move Units step ends (09.02)

- **Rule**: "every unit in their army will have been selected to make a move,
  even if it is to remain stationary"; Remain Stationary (09.04) is eligible
  for any unit.
- **Was**: END_MOVEMENT left untouched units unselected — no Remain Stationary
  flags, so [HEAVY] (24.16) and the indirect stationary band were lost.
- **Now**: `MovementPhase.get_units_requiring_selection()` is the single list
  (on-table, alive, not attached CHARACTER, not AIRCRAFT, not already
  moving/moved). END_MOVEMENT resolves each as Remain Stationary
  (`get_end_movement_remain_stationary_changes`, shared with the explicit
  REMAIN_STATIONARY action) in single-player and in the multiplayer
  `GameManager.process_end_movement` path. Design choice: the END_MOVEMENT
  press *is* the selection of Remain Stationary for the remaining units, so
  players are not forced to click every unit.
- **Evidence**: audit test section P1-5; scenario
  `end_movement_unselected_remain_stationary_11e`.

## P0-1 — Selected Indirect Shooting drives attack resolution (10.07)

- **Was**: the selected type never reached RulesEngine; indirect consequences
  were inferred from visibility, so a VISIBLE target was resolved as normal
  shooting (no cover, re-rolls allowed, BS instead of the 1-5 band).
- **Now**: `ShootingPhase` puts `shooting_type` in every resolver payload;
  `RulesEngine._stamp_shooting_type` copies it onto each assignment and
  `_indirect_consequences_apply` decides per attack (selected type at 11e;
  visibility only for 10e / callers without a type). Hit re-rolls — including
  the staged Command Re-roll (`reroll_hit_die`, `no_hit_rerolls`) — are
  refused. The hit-threshold display shows the real need
  (e.g. `6+ (indirect, cover)`).
- **Evidence**: audit test section P0-1 (RulesEngine + real ShootingPhase
  path); scenario `indirect_selected_visible_target_11e` (fails on e28e4f7,
  passes here).

## P1-3 — Automatic saves use 11e grouped allocation (05.03-05.04)

- **Was**: `ShootingPhase._auto_roll_saves` pre-assigned saves round-robin;
  two failed D1 saves on two W2 models wounded both (0 casualties).
- **Now**: at edition 11 it calls `RulesEngine.resolve_allocation_batch_11e`
  (the engine the interactive overlay uses) per batch, with the
  CasualtyPreference order and a working board so later batches see earlier
  damage. Two failed D1 saves now kill one W2 model.
- **Evidence**: audit test section P1-3.

## P1-4 — Emergency disembark placement (18.05)

- **Was**: survivors placed on a fixed ring around the transport centre —
  overlapping the hull, each other and enemy models; no destruction when no
  legal spot existed.
- **Now**: `RulesEngine._emergency_disembark_placements` searches a 0.5" grid
  nearest-first (edge-to-edge to the hull) filtered by: wholly within 6", not
  overlapping the transport / any model / walls & dense terrain, on the
  battlefield, outside engagement range; models are then placed greedily
  keeping coherency. Unplaceable models are destroyed and logged.
- **Evidence**: audit test section P1-4 (corner + wall + enemy screen, and a
  no-legal-spot case); scenario `emergency_disembark_legal_placement_11e`.

## Validation run (2026-10-12, this branch)

- Headless audit suite `40k/tests/run_pretrigger_tests.sh`: **2888 passed,
  0 failed across 123 tests** (includes the two new/rewritten test files).
- New windowed scenarios — all pass: `end_fight_mandatory_fights_11e` 38/38,
  `fight_pass_unable_to_fight_11e` 39/39,
  `end_movement_unselected_remain_stationary_11e` 19/19,
  `indirect_selected_visible_target_11e` 29/29 (fails 1 step on e28e4f7),
  `emergency_disembark_legal_placement_11e` 17/17.
- 42 existing windowed scenarios touching the changed paths were re-run.
  Updated because they relied on END_FIGHT skipping owed fights:
  `pile_in_button_label_bv8yue`, `auto_consolidate_closest_opponents`,
  `pad_fight_step_end_qrx689`, `iss064j_mission_action_sabotage_11e` (setup
  now marks the fights resolved; `iss064j` still has 11 failures that are
  pre-existing — 14 on e28e4f7). Failing identically on e28e4f7 (pre-existing,
  untouched): `auto_allocate_wounds_settings_ui`,
  `engaged_vehicle_confirm_split_11e`, `iss048_shooting_types_11e`,
  `iss15_indirect_band_11e`, `movement_auto_confirm`, `game_log_step_replay`,
  `game_log_switch_step_no_escape`, `tut_t6_krumpin_pad`,
  `tut_t6_wrong_fighter_backout`.
- Live MCP bridge gate (`verify_delivery`) in the Fight step: END_FIGHT and
  SKIP_UNIT on an owed fight both rejected server-side, no ERROR log lines —
  verdict PASS.
- Not run: the full 500-scenario sweep, full-game AI benchmark, two-process
  multiplayer (the multiplayer END_FIGHT / END_MOVEMENT paths were changed but
  only exercised single-player).

## Residual risk / not done

- The p.74 pass marks passed units as not having fought once the Fight step
  ends; a 12.08 forced fight against such a unit is not re-offered.
- Turn-timer expiry in the Fight phase sends END_FIGHT, which is now refused
  while fights are owed (by design — a timer cannot forfeit mandatory fights).
- Emergency-disembark placement is greedy (nearest-first per model); a
  cleverer packing could fit more models in very cramped spaces.
- Not addressed here: CI fail-closed work, full-game AI/multiplayer gates,
  content-support manifest, Surveil scoring, embark-after-Remain-Stationary.

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
- **Evidence**: `tests/test_fight_phase_scope_end_fight_11e.gd` (47/47),
  scenarios `end_fight_mandatory_fights_11e`, `fight_pass_unable_to_fight_11e`,
  two-process multiplayer run (below).

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

## Multiplayer follow-up (1.44.1) — validated with two real processes

`40k/tests/mp_two_process_core_rules.py` launches an ENet HOST and CLIENT
Godot process (separate `user://`, separate MCP bridge), loads a fixture on
the host, drives each peer through its own bridge (`NetworkIntegration.
route_action`, real button `pressed` signals) and compares the two peers'
GameState key-by-key after every step.

| Check (fixture) | e28e4f7 | 7822198 | this branch |
|---|---|---|---|
| Client "Finish Pile Ins" (END_FIGHT in 12.02) ends only its half (`co_pretrigger`) | phase skipped to Scoring | phase skipped to Scoring | PASS |
| Host END_FIGHT while the client must select is refused, nothing forfeited | — | phase already over | PASS |
| Client sees the Pass button from host data; client pass hands the pick over without forfeiting | — | FAIL | PASS |
| Host pass -> both passed -> Consolidate step (12.07) on both peers | — | FAIL | PASS |
| Client END_FIGHT with an owed fight: refused AND the client is told why | owed fight forfeited, phase ended | refused, no message | PASS |
| AFK timeout in the Fight step: no forfeit, timer re-armed, 2nd timeout charged to the selecting player | n/a | timer not re-armed | PASS |
| END_MOVEMENT by host / by client: Remain Stationary on both peers, states identical | — | PASS | PASS |
| Host and client GameState identical after load, pass, Consolidate, phase end, END_MOVEMENT | — | — | PASS |
| Client phase button follows the steps ("End Fight Phase" -> "Finish Consolidations") | — | stuck on "Finish Pile Ins" (screenshot) | PASS |

Root causes fixed:

- `GameManager.process_end_fight` short-circuited END_FIGHT to "phase
  complete" on the host's multiplayer path, so any END_FIGHT — including
  "Finish Pile Ins" — skipped every fight, the Consolidate step and the
  12.09 triggers. It now always delegates to `FightPhase`.
- A client's `FightSequencer` never sees the host's `mark_fought`, so it kept
  offering units that had fought. The host now stamps a turn-scoped
  `flags.fight_done_turn` (synced by diffs) that `eligible_to_fight` honours
  (`has_fought` is only cleared for the player whose turn starts, so it leaks
  into the opponent's turn and cannot be used).
- END_MOVEMENT / END_FIGHT were "deterministic" optimistic relay actions
  although host-only phase state decides them.
- The turn timer auto-sent END_FIGHT (now refused while fights are owed) and
  then sat stopped; it also charged the ACTIVE player when the opponent was
  the one selecting. It now submits only a legal p.74 pass, otherwise
  re-arms, and charges the selecting player.
- A host rejection of a client action was only logged; it is now toasted.
- The Remain Stationary diffs are shipped before the Shooting phase-enter
  sync, removing a false DESYNC report there.
- The client's FightPhase step fields are synced by NetworkManager directly,
  so `subphase_transition` never fired there and the client's phase button
  said "Finish Pile Ins" for the whole phase. NetworkManager now re-emits it
  right after each step-field update and before the matching `*_required`
  signal (the host's order — FightController hides the step panels on the
  transition and the `*_required` signal re-shows them; emitting it after
  hid the client's Fight-selection panel, caught by the two-process run).
- Game log: END_FIGHT was always logged "Ended Fight Phase", including a
  Pile In / Consolidate half and the p.74 pass. FightPhase now returns a
  step-specific `log_text` ("Finished Pile In (12.02)", "Passed: ... (p.74)",
  "Ended the Fight step (12.04)", "Finished Consolidation (12.07)") that
  GameEventLog and the replay log use. Single-player too; covered by
  test section J and `fight_pass_unable_to_fight_11e`.

Pre-existing, NOT fixed here (reproduces identically on e28e4f7):
`RulesEngine._ensure_loadout_resolved` lazily writes `_loadout_checked`,
`_loadout_version` and per-model `melee_loadout` / `ranged_loadout` into
GameState outside the diff stream, the first time a peer resolves a unit's
weapons. The host does so when the Fight step starts, so the client's ISS-015
hash check logs `DESYNC DETECTED` for the rest of the phase. The values are
derived deterministically from synced data (the client computes the same ones
when it needs them), so play is unaffected; the fix is to exclude those keys
from `compute_state_hash` or resolve loadouts for every unit at load on both
peers.

## Validation run (2026-10-12, this branch)

Head 92294b1 unless stated. "Base" = e28e4f7 run on the same machine.

- Headless audit suite `40k/tests/run_pretrigger_tests.sh`: **2907 passed,
  0 failed across 123 tests** (47a41a0: 2901 / 0; 7822198: 2888 / 0). The
  suite greps its output, so every test was also re-run with full logs: 14
  tests log compile-time `SCRIPT ERROR`s, all a cascade from autoload names in
  `FactionPalettes.gd`, `DeploymentZoneData.gd`, `AttackSequence.gd` and
  `UnitAbilityManager.gd` under `-s`; the error locations are identical on
  base for all 14 and none originates in a file this branch changes (the
  7822198 `FightSequencer` -> `Measurement` error is gone).
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
- Two-process multiplayer (`40k/tests/mp_two_process_core_rules.py`): **67
  passed, 0 failed** — see the multiplayer section above for what it covers
  and how e28e4f7 / 7822198 fail it.
- Multi-peer GUT suite (`40k/tests/run_multiplayer_tests.sh`, the CI
  "Multi-peer integration" job), run locally 3x per tree: base 9 / 11 / 11 and
  this branch 10 / 9 / 11 failing out of 39. The same 8 tests fail in every run
  on both trees (deployment single unit / outside zone / undo, client
  disconnect, the three `load_save(shooting_phase)` timeouts, the
  `sbid-` helper); the rest rotate on both trees (a harness race: the host
  re-enters Formations after the test's first deploy). Not caused here.
- AI full-game benchmark (`run_ai_benchmark.sh`, 5 games x 2 seat orders,
  `audit_baseline_postdeploy[_p2first]`, seeds 1001-1005 / 2001-2005): base,
  7822198 and 92294b1 all **10/10 completed, 0 stalls**; 92294b1 is
  identical to 7822198 game-for-game (same VP, rounds and action counts).
  The p2first fixture fails the benchmark's own fixture check (a "Strike
  Force" header row imported as a unit) — pre-existing data issue.
- Full windowed sweep, all 505 `tests/scenarios/sp/*.json`, 3 parallel
  shards: 7822198 **426 passed / 79 failed**; 47a41a0 **426 / 79**. The union
  of both failure sets plus the 9 scenarios started during a 1-minute window
  in which the sweep checkout was briefly edited (90 total) was re-run with
  ONE shard per tree, base and 92294b1 side by side under the same load:
  12 pass on both, 70 fail on both with identical counts, 5 fail on both with
  different counts (`iss064j` — its setup changed here — and 4 pad/tutorial
  scenarios), 1 fails only on base (`pad_m0_camera`), 2 fail only here:
  `pad_box_multi_select` (then 3/3 passes on BOTH trees run alone) and
  `tut_t3_get_movin_pad` (154/0 twice run alone). The 3-shard failures that
  pass alone are load-sensitive (pad input timing, tutorial steps, an AI
  charge finishing before the scenario's first assertion).
- Fight / game-log scenarios (90 that load the Fight phase or touch
  FightPhase / FightController / the game log) on 92294b1: **83 passed,
  7 failed** — all 7 also fail on base (`374_headwoppa_devastating_wounds`,
  `game_log_step_replay`, `iss064j_mission_action_sabotage_11e`,
  `pad_fight_attack_reticle`, `stompa_gets_to_fight_11e`,
  `tut_t6_krumpin_pad`, `tut_t6_wrong_fighter_backout`).
- Live MCP bridge gate (`verify_delivery`) in the Fight step: END_FIGHT and
  SKIP_UNIT on an owed fight both rejected server-side, no ERROR log lines —
  verdict PASS.
- CI on 92294b1: headless audit, GUT suite, code quality, coverage, AI damage
  math and reachability green. The windowed-scenario job is cancelled by its
  30-minute timeout (as on main); multi-peer integration fails as above;
  `loop-prefilter.yml` fails at 0 s on every push, main included.

Scenarios failing on BOTH base and this branch in that side-by-side run (75 —
pre-existing, or load-sensitive on both trees):
`374_headwoppa_devastating_wounds`, `374_panoptispex_ignores_cover`,
`374_supa_cybork_fnp`, `387_waaagh_energy_eadbanger`,
`85b_rolloff_dramatic`, `85d_rolloff_vs_ai`, `85e_first_turn_rolloff`,
`85f_first_turn_vs_ai`, `auto_allocate_wounds_settings_ui`,
`charge_base_contact_enforced`, `charge_cannot_end_on_wall`,
`charge_hover_stats_dwell`, `charge_infantry_through_ruins`,
`charge_over_ruin_corner_succeeds`, `charge_reroll_keep_default_button`,
`click_select_shooter_shooting`, `custodian_charge_congested_ovals`,
`disembark_rotated_border_stale_controller`,
`engaged_vehicle_confirm_split_11e`, `game_log_step_replay`,
`game_log_switch_step_no_escape`, `grenade_unit_picker_display_names`,
`infantry_enters_ruin_wall`, `infantry_tall_ruin_traversal`,
`iss047c_ability_choice_prompts_11e`, `iss048_shooting_types_11e`,
`iss052b_gone_to_ground_11e`, `iss064b_primary_disposition_11e`,
`iss064d_triangulate_prompt_11e`, `iss064e_decoy_prompt_11e`,
`iss064f_condemn_prompt_11e`, `iss064h_card_action_visibility_11e`,
`iss064i_relic_setup_prompt_11e`, `iss064j_mission_action_sabotage_11e`,
`iss065b_plunder_action_11e`, `iss067_scout_reserves_deploy_11e`,
`iss074_aircraft_reserve_cycle_11e`, `iss15_hidden_shot_stamp_11e`,
`iss15_indirect_band_11e`, `move_ghosts_above_range_circles`,
`movement_auto_confirm`, `movement_embarked_select_pans_to_transport`,
`pad_charge_snap_cursor_active`, `pad_deploy_reposition_placed_model`,
`pad_deploy_reposition_rotate_model`, `pad_fight_attack_reticle`,
`pad_group_move_all`, `pad_group_move_fall_back`, `pad_m0_menu_nav`,
`pad_m2_shooting_native`, `pad_m2_unit_cycle`, `pad_m3_carry_deploy`,
`pad_m3_carry_move`, `pad_move_carry_hop_swap`,
`pad_reinforcement_formation_row`, `pad_reinforcement_no_move_menu`,
`reinforcement_no_overlap`, `scout_drag_then_end_phase_persists`,
`scout_end_phase_action_commits_staged`,
`scout_invalid_move_snaps_back_nested`, `split_fire_per_model`,
`split_fire_spinbox_commit`, `stompa_gets_to_fight_11e`,
`terrain_11e_layouts`, `tut_full_course_chain_pad`, `tut_t1_basics`,
`tut_t1_basics_pad`, `tut_t1_lock_it_in_start_glyph`,
`tut_t1_pad_ack_button`, `tut_t4_dakka_pad`, `tut_t4_dakka_reassign_pad`,
`tut_t5_ere_we_go_pad`, `tut_t6_krumpin_pad`,
`tut_t6_wrong_fighter_backout`, `tut_t7_runnin_da_show_pad`.

## Residual risk / not done

- The p.74 pass marks passed units as not having fought once the Fight step
  ends; a 12.08 forced fight against such a unit is not re-offered.
- Turn-timer expiry in the Fight step submits only a legal p.74 pass; while
  fights are owed it submits nothing and re-arms (a timer cannot forfeit
  mandatory fights) — the second consecutive timeout ends the game.
- Emergency-disembark placement is greedy (nearest-first per model); a
  cleverer packing could fit more models in very cramped spaces.
- Not addressed here: CI fail-closed work, full-game AI/multiplayer gates,
  content-support manifest, Surveil scoring, embark-after-Remain-Stationary.
- Pre-existing, found while validating, not fixed here: the lazy loadout
  cache behind the multiplayer `DESYNC DETECTED` log in the Fight phase (see
  the multiplayer section), the 8 always-failing multi-peer GUT tests, the
  75 scenarios above, the broken `loop-prefilter.yml`, and the CI windowed
  job's 30-minute timeout (it never reaches this branch's scenarios).

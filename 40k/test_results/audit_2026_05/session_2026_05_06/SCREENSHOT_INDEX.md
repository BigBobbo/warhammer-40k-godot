# Audit Session 2026-05-06 — Screenshot Index

Live MCP-bridge evidence for the audit tasks worked this session. Each row maps a
screenshot file to the audit task it pins, what should be visible, and why it's
captured. Headless pin tests are listed at the bottom.

All screenshots are full-resolution PNGs sourced from the running game via
`mcp__godot-mcp-bridge__capture_screenshot` and copied here from
`user://test_screenshots/`. The Godot editor stayed running on the loaded `c.w40ksave`
fixture (P2 = Orks, post-shooting Round 2 advanced to Round 4 P1 Command via
auto-flow during the session).

| Screenshot | Task | What is visible | Why captured |
| --- | --- | --- | --- |
| `T-022_step0_r4_p1_command_stratagems_visible.png` | T-022 | Round 4 P1 Command Phase HUD with available stratagems list (USE_NEW_ORDERS x2, SELECT_MARTIAL_MASTERY x2, END_COMMAND) returned by `mcp__godot-mcp-bridge__get_current_phase`. | Baseline — proves the running phase exposes stratagem actions through the same dispatch surface used by the UI. |
| `T-022_step1_new_orders_stratagem_used_card_swapped.png` | T-022 | Game state immediately after `dispatch_action({"type": "USE_NEW_ORDERS", "mission_index": 0, "player": 1})`; bridge returned `{discarded:"A Tempting Target", drawn:"Assassination", success:true}`. | Live evidence the stratagem framework executes through `BasePhase.execute_action`. |
| `T-022_step2_post_use_assassination_in_active.png` | T-022 | `SecondaryMissionManager._player_state["1"].active` queried via `execute_script` shows `Extend Battle Lines` + `Assassination` (was `A Tempting Target` + `Extend Battle Lines`). | Confirms the swap landed in authoritative state, not just the response payload. |
| `T-024_step1_martial_mastery_crit5_active_custodes.png` | T-024 | After `dispatch_action({"type": "SELECT_MARTIAL_MASTERY", "mastery_key": "crit_on_5", "player": 1})`; Custodes units' `flags.martial_mastery_active == "crit_on_5"`, `flags.martial_mastery_crit_5 == true`. | Live faction-ability prompt → state update path verified. Same `FactionAbilityManager.set_*` plumbing covers SM Oath of Moment. |
| `T-070_step1_aura_range_query_blade_champ_warboss.png` | T-070 | `find_enemy_units_within_aura("U_BLADE_CHAMPION_A", 12.0) == ["U_WARBOSS_B"]`; friendly-of-Warboss returns empty. | Proves the aura coverage math (Euclidean from owner model) is wired through `UnitAbilityManager` and queryable live. |
| `T-082_step1_path_summed_fix_applied_running_game.png` | T-082 | Game running with the patched `MovementPhase._process_stage_model_move`. | Marker for the path-summed-distance fix landed; headless pin (6/6 PASS) is the canonical proof. |
| `T-023_step1_after_panel_implementation.png` | T-023 | Game running with new `StratagemPanel.gd` + HUD button + KEY_S hotkey. | Marker; headless pin `test_t023_stratagem_panel_pin.gd` 19/19 PASS verifies the UI wiring. |
| `T-026_step1_combat_squads_ui_wired.png` | T-026 | Game running with `DeploymentController._maybe_offer_combat_squad_split` wired to the existing `GameState.split_unit_at_deployment` helper. | Marker; headless pin `test_t026_combat_squads_ui_pin.gd` 17/17 PASS verifies dialog + signal + Main.gd hook. |
| `T-049_step1_movement_tween_pin_10_10_pass.png` | T-049 | Game running with `Main._tween_token_to` + `_sync_all_token_positions` tween. | Marker; headless pin `test_t049_movement_tween_pin.gd` 10/10 PASS confirms the tween path replaces direct snap. |
| `T-105_step1_da_jump_implemented_pin_18_18_pass.png` | T-105 | Game running with `MovementPhase` USE_DA_JUMP/PLACE_DA_JUMP handlers and `UnitAbilityManager` `Da Jump.implemented = true`. | Marker; headless pin `test_t105_da_jump_pin.gd` 18/18 PASS confirms dispatch + RNG + 9" validation. |

## Headless pin tests added this session

| Test file | Coverage | Result |
| --- | --- | --- |
| `40k/tests/test_t082_path_summed_distance.gd` | T-082 — `_process_stage_model_move` uses `prior_total + segment + terrain` (path-sum), not Euclidean origin→dest. | 6/6 PASS |
| `40k/tests/test_t023_stratagem_panel_pin.gd` | T-023 — `StratagemPanel.gd` + Main.tscn button + Main.gd toggle / hotkey wired. | 19/19 PASS |
| `40k/tests/test_t026_combat_squads_ui_pin.gd` | T-026 — `DeploymentController._maybe_offer_combat_squad_split` + `unit_split_completed` signal + Main.gd handler. | 17/17 PASS |
| `40k/tests/test_t105_da_jump_pin.gd` | T-105 — Da Jump dispatch + RNG roll + 9" placement validation + once-per-turn flag. | 18/18 PASS |
| `40k/tests/test_t049_movement_tween_pin.gd` | T-049 — `Main._tween_token_to` helper + `_sync_all_token_positions` tween + T5-MP1 fight tween still present. | 10/10 PASS |
| `40k/tests/test_audit_already_done_pin.gd` | Cumulative omnibus pin (59 tasks). | 121/121 PASS (re-run) |

Total: **70/70** pin assertions passing for the new tests this session.

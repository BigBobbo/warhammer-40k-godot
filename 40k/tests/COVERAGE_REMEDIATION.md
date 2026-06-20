# Coverage-matrix remediation — windowed scenario coverage

_Generated 2026-06-19 · branch `claude/tender-franklin-vvyb5b` · verified at commit `28088acc`_

## Summary

`check_coverage.py` (the CI **Coverage matrix validation** gate) was failing with **90 errors**: 45 committed windowed scenarios declared 75 distinct `covers` tags that had **no matching tile** in `coverage.json`. This is now resolved — `check_coverage.py` exits 0.

Crucially, the debt was **not** a bookkeeping oversight. Root-causing the scenarios revealed they could not run at all from a clean checkout (see below), so they could never have been verified in CI or by anyone but the original author. Every tile registered here is backed by a scenario that was **driven live through the real UI via the `addons/godot_mcp` bridge and passed** on this machine (38 in the main batch + 7 after the second fixture recovery = **45/45 green**).

## Root cause found & fixed: missing test fixtures (fresh-checkout reproducibility bug)

The windowed scenarios load named save fixtures via `res://saves/` (== `40k/saves/`, which is **gitignored**). **22 fixtures** referenced by committed scenarios lived only in that gitignored directory and were never committed to `tests/saves/` (the location `run_scenarios.sh` copies into `res://saves/` at startup). On a clean clone the scenarios aborted with `[ScenarioRunner] FATAL: fixture load failed: <name>` before running a single step.

**Fix:** recovered all 22 fixtures from git history (commit `d9f2a85b`) into `tests/saves/` (commits `86de34c3`, `28088acc`). After recovery all 45 scenarios run and pass from a clean checkout.

| Failure (live, reproduced) | Root cause | Fix | Status |
|---|---|---|---|
| 13 scenarios `FATAL: fixture load failed: audit_367_warlord / audit_372_charge_modifier / audit_374_kunnin / audit_386_deadly_demise / …` | 21 `audit_*`/`test_*` fixtures only in gitignored `40k/saves/` | recovered from history → `tests/saves/` | ✅ all pass |
| 7 scenarios `FATAL: fixture load failed: New Game` | `New Game.w40ksave` likewise uncommitted | recovered from history → `tests/saves/` | ✅ all pass |

## Verification methodology (per tile)

Each tile was registered **only** after its backing scenario passed a live run (`godot --scenario-file=…` via the MCP bridge), which: drives the real UI / real engine actions, asserts `actual==expected` per step, and captures screenshots of the effect. Independent spot-check: the roll-off (real Roll-button click → dice settle → winner) and split-fire (real token click → picker dialog) features were re-viewed from their captured screenshots to confirm a genuine rendered effect (not a blank marker).

Tiles carry a **`fidelity`** field recording how strongly each is verified against the bar *‘a human can see and act’*:

- **CLICK** (17 tiles): Real input — a human clicks the actual button / presses the actual key (proves wiring + handler + visible effect)
- **HANDLER** (30 tiles): Real handler + live node assertion + screenshot — the exact handler a UI element invokes, with the visible effect captured (proves the player sees the effect)
- **RULES** (28 tiles): Engine/template dispatch + GameState assertion — rules-tier (project methodology permits headless for rules/movetypes/autoload internals)

## Registered tiles by fidelity

### CLICK — 17 tiles

| tile id | backing scenario | what is verified |
|---|---|---|
| `ai.AIPlayer.roll_off_suppressed` | `85d_rolloff_vs_ai` | AI does not auto-resolve the mutual roll-off while a human is present. |
| `deployment.first_turn_roll_off` | `85e_first_turn_rolloff` | Post-deployment 'Determine First Turn' roll-off driven via real Roll+Continue clicks; winner takes first turn. |
| `phases.ScoutPhase.UI.confirm_button_persists_position_to_state` | `scout_confirm_button_writes_state` | Clicking the REAL Confirm button (pressed signal -> _on_scout_confirm_pressed -> CONFIRM_SCOUT_MOVE) writes staged positions into GameState. |
| `phases.ScoutPhase.UI.confirm_works_after_reselect_clears_active_unit` | `scout_confirm_after_reselect` | After re-selecting a scout unit clears _scout_active_unit_id, the REAL Confirm button still commits staged positions to GameState. |
| `phases.ScoutPhase.UI.unit_list_selection_enables_drag` | `scout_unit_list_selection_enables_drag` | Selecting a scout unit from the right-panel list wires scout state (confirm button shown/connected) and the REAL Confirm commits; no fall-through to movement branch. |
| `phases.ScoutPhase.UI.unit_selection_from_panel_enables_drag` | `scout_unit_selection_enables_drag` | Selecting a scout unit via the stats panel sets _scout_active_unit_id and enables drag; REAL Confirm commits. |
| `phases.ScoutPhase.e2e.real_drag_confirm_persists_to_state_through_movement` | `scout_real_drag_confirm_persists_e2e` | E2E: interactive deploy -> real scout drag handlers -> REAL Confirm button click -> positions persist into GameState and the on-board token, through to the movement phase. |
| `phases.ShootingPhase.assign_target_split` | `split_fire_spinbox_commit` | Typed split amount commits to a per-model assignment via the real OK button. |
| `rules.11e.allocation_groups.batch_saves` | `iss045_allocation_groups` | 11e 05.04: confirming batch-rolls saves per group (Boyz first), verified by casualty counts. |
| `rules.11e.allocation_groups.character_last` | `iss045_allocation_groups` | 11e 05.03: order that puts the attached CHARACTER before the bodyguard is rejected (Confirm disabled). |
| `scripts.AllocationGroupOverlay.order_choice` | `iss045_allocation_groups` | AllocationGroupOverlay: real Up/Down click reorders groups; Confirm disabled while CHARACTER is before Boyz (real click asserts .disabled). |
| `shooting.split_fire_picker_ui` | `split_fire_spinbox_commit` | REAL left-click on an enemy token opens the Split Fire picker; REAL keystroke types the amount (update_on_text_changed tracks each keystroke). |
| `ui.RollOffDialog.RollButton` | `85b_rolloff_dramatic` | RollOffDialog Roll button (real click) resolves the deployment roll-off. |
| `ui.RollOffDialog.acknowledge_required` | `85d_rolloff_vs_ai` | Human must click the real Continue button to acknowledge before the roll-off completes. |
| `ui.RollOffDialog.animated_dice` | `85b_rolloff_dramatic` | RollOffDialog shows dramatic animated dice; verified by clicking the real Roll button and observing the settled winner + screenshot. |
| `ui.RollOffDialog.first_turn_context` | `85e_first_turn_rolloff` | RollOffDialog in first-turn context shows no Deploy-choice buttons (winner just takes the turn). |
| `ui.RollOffDialog.shown_vs_ai` | `85d_rolloff_vs_ai` | Vs AI, the dramatic RollOffDialog is shown to the human (not auto-resolved). |

### HANDLER — 30 tiles

| tile id | backing scenario | what is verified |
|---|---|---|
| `Main._sync_all_token_positions.handles_nested_deployment_tokens` | `scout_invalid_move_snaps_back_nested` | _sync_all_token_positions correctly handles nested (wrapper->TokenVisual) deployment tokens. |
| `autoloads.RulesEngine.get_eligible_shooter_models` | `split_fire_per_model` | RulesEngine.get_eligible_shooter_models returns the bearers eligible to split onto a target. |
| `autoloads.SettingsService.set_auto_allocate_wounds` | `auto_allocate_wounds` | SettingsService.set_auto_allocate_wounds(true) is honoured by the overlay. |
| `deployment.formation_mode.same_unit_tight_then_single` | `regression_single_after_tight_same_unit` | Fully place a unit in TIGHT then switch to SINGLE: set_formation_mode no longer creates a data-less invisible ghost; subsequent click still works. |
| `deployment.formation_mode.single_after_partial_tight` | `regression_single_after_partial_tight` | Place 1 in SINGLE, switch TIGHT (place 2), switch back SINGLE: no invisible ghost spawned and clicks still place (get_placed_count progresses). |
| `deployment.model_type_picker.unit_card_placement` | `screenshot_model_type_picker_unit_card` | Deploying a multi-model-type unit (Lootas) renders the Select-Model-Type picker inside the right-hand unit card (has_model_type_picker true + screenshot). |
| `deployment.search_and_destroy` | `main_menu_defaults` | HONEST SCOPE: only asserts the deployment dropdown DEFAULTS to 'Search and Destroy'; does not exercise S&D deployment logic. |
| `mainmenu.defaults` | `main_menu_defaults` | MainMenu boots with terrain defaulting to 'CA2025 02 Layout' and deployment to 'Search and Destroy' (live OptionButton widgets). |
| `movement.advance_distance_circle` | `move_range_advance_grows` | The per-model reach circle grows to the advanced cap (base6+advance4=10in) in place when the advance roll raises the cap. |
| `movement.per_model_move_range_circle` | `move_range_per_model_circle` | Reach overlay is per-picked-up-model (8 dash segments + 1 label), anchored at the model, not a unit-wide bubble. |
| `phases.MovementPhase.BEGIN_ADVANCE` | `move_range_advance_live` | BEGIN_ADVANCE dispatched live; pauses awaiting command-reroll decision. |
| `phases.MovementPhase.DECLINE_COMMAND_REROLL` | `move_range_advance_live` | DECLINE_COMMAND_REROLL resolves the advance roll and emits unit_move_begun -> MovementController move cap updates. |
| `phases.MovementPhase.UI.advance_refreshes_range_overlay` | `move_range_advance_grows` | _update_movement_display_with_advance redraws the SAME MoveRangeVisual overlay to the new radius (asserted radius + label + screenshot). |
| `phases.MovementPhase.UI.move_range_overlay` | `move_range_per_model_circle` | _show_model_range_overlay / _clear_move_range_overlay draw and clear the MoveRangeVisual on pickup/drop. |
| `phases.PhaseManager.formations_to_rolloff` | `85c_newgame_reaches_rolloff` | Completing Formations (CONFIRM_FORMATIONS both players) transitions the live phase to ROLL_OFF (3). |
| `phases.ScoutPhase.UI.invalid_move_snaps_back_nested_token` | `scout_invalid_move_snaps_back_nested` | Invalid scout confirm shows a toast and _sync_all_token_positions rolls the NESTED deployment token's visual back to state pos. |
| `phases.ScoutPhase.e2e.drag_then_end_phase_commits_staged_move` | `scout_drag_then_end_phase_persists` | Real scout drag handlers (motion+release) stage moves; ending the phase via the real phase-action button commits them (token + state at moved pos). |
| `scripts.Main._open_settings_menu` | `auto_allocate_wounds_settings_ui` | Main._open_settings_menu() (the Escape-key path) creates the live settings menu. |
| `scripts.SettingsMenu.gameplay_tab` | `auto_allocate_wounds_settings_ui` | SettingsMenu Gameplay tab builds and contains the 'Computer allocates wounds' checkbox (asserted exists/visible/labelled + screenshot). |
| `scripts.WoundAllocationOverlay._start_wound_allocation` | `wound_alloc_overkill_skips_when_wiped` | WoundAllocationOverlay._start_wound_allocation drives manual allocation via real model-click. |
| `scripts.WoundAllocationOverlay.auto_allocate` | `auto_allocate_wounds` | WoundAllocationOverlay auto-allocates all wounds when the setting is ON. |
| `scripts.WoundAllocationOverlay.overkill_completes_when_unit_wiped` | `wound_alloc_overkill_skips_when_wiped` | Overkill regression: once the unit is wiped, the overlay completes instead of freezing waiting for an impossible board click. |
| `settings.auto_allocate_wounds` | `auto_allocate_wounds` | auto_allocate_wounds setting ON: overlay auto-resolves saves instead of waiting for board clicks (verified via real save-resolution entry point + casualty count). |
| `terrain.parse_test` | `main_menu_defaults` | HONEST SCOPE: only asserts the terrain dropdown DEFAULTS to the layout_parse_test option; does not exercise terrain parsing itself. |
| `ui.RollOffDialog.appears_in_new_game` | `85c_newgame_reaches_rolloff` | In a new game the RollOffDialog becomes visible on reaching the pre-deployment roll-off (asserted visible + screenshot). |
| `ui.log.grouped_dice_icons` | `dice_grouped_log_render` | Dice render GROUPED (one icon per value + xN), asserted via dice_row_has_visual + screenshot. |
| `ui.log.inline_dice_graphics` | `dice_grouped_log_render` | GameLogPanel combat card renders rolls as graphical DiceRowVisual nodes (not BBCode text), via the real _create_card / roll_recorded path. |
| `ui.log.simple_card_dice` | `dice_icons_simple_cards` | p1/p2_action simple cards (advance/charge/battle-shock) show grouped die icons; single die shows no xN (screenshot). |
| `ui.shooting.resolution_log_dice_icons` | `resolution_log_dice_icons` | ShootingController.dice_log_display renders inline grouped d6 icons via DiceFaceIcons/add_image (number arrays dropped from parsed text; screenshot). |
| `visual.board_style.grass_texture_loads` | `board_grass_texture_loads` | Default 'grass' board style loads its 128x128 tiled texture via the resource system on the live BoardBackground material; survives a grass->felt->grass switch (screenshot). |

### RULES — 28 tiles

| tile id | backing scenario | what is verified |
|---|---|---|
| `autoloads.AIPlayer.11e` | `iss062_ai_11e` | AI-vs-AI at ed.11 progresses through phases/turns under 11e template gating (forward-progress asserted). |
| `autoloads.TransportManager` | `iss058_disembark_11e` | TransportManager tracks embarked unit and disembark eligibility. |
| `iss064.no_double_hazard` | `iss064_fallback_single_hazard_11e` | CONFIRM_UNIT_MOVE does not re-apply hazards at ed.11 (alive count unchanged after begin). |
| `iss065.at_half_strength` | `iss065_at_half_battleshock_11e` | is_at_half_strength_combined drives the ed.11 trigger (sole trigger at exactly 5/10). |
| `iss067.scout_reserves` | `iss067_scout_reserves_11e` | Deploying a reserve scout into its DZ sets the unit DEPLOYED (status 2). |
| `movement.terrain.infantry_tall_ruin_traversal` | `infantry_tall_ruin_traversal` | INFANTRY may stage a move into a tall ruin; BEGIN_NORMAL_MOVE+STAGE_MODEL_MOVE accepted (no phantom climb cost). |
| `movement.terrain.no_phantom_climb_cost` | `infantry_tall_ruin_traversal` | _get_vertical_climb_cost returns 0 for INFANTRY (regression: full terrain height no longer added). |
| `movetypes.ChargeMove11e` | `iss049_charge_11e` | ChargeMove11e template: select-after-roll, 12in declare veto, selectable=within 12in AND within roll. |
| `movetypes.DisembarkMove` | `iss058_disembark_11e` | DisembarkMove template enforces tactical/combat set-up distances. |
| `movetypes.FallBackMove.modes` | `iss040_movement_11e` | FallBackMove ordered_retreat vs desperate_escape modes (desperate rolls hazards). |
| `movetypes.IngressMove` | `iss060_ingress_11e` | IngressMove template enforces 6in-from-edge + 9in-from-enemy and stamps reinforcement flags. |
| `movetypes.MoveTypes.available_for` | `iss040_movement_11e` | MoveTypes.available_for gates which move actions a unit is offered. |
| `phases.ChargePhase.11e_charge_flow` | `iss049_charge_11e` | Ed.11 charge flow: declare with empty targets is legal (11.02), roll computes selectable targets, apply rejects out-of-range target. |
| `phases.CommandPhase.battle_shock` | `iss065_at_half_battleshock_11e` | CommandPhase queues battle-shock tests; at-exactly-half-strength triggers at ed.11 (08.03) but not ed.10. |
| `phases.FightPhase.11e_sequencer` | `iss050_fight_11e` | Ed.11 FightPhase defers selection to FightSequencer (12.04): alternation starts with active player; out-of-turn select refused. |
| `phases.MovementPhase.11e_disembark` | `iss058_disembark_11e` | Ed.11 disembark modes (18.04): stationary transport forces TACTICAL 3in (4in rejected); COMBAT fallback accepts 6in + hazard + battle-shock. |
| `phases.MovementPhase.11e_ingress` | `iss060_ingress_11e` | Ed.11 ingress (20.04): mid-board placement rejected; edge placement >8in from enemies succeeds with arrived_from_reserves + no_moves_until_charge. |
| `phases.MovementPhase.11e_move_types` | `iss040_movement_11e` | At ed.11 MovementPhase offers MoveType templates; offering flips live when engagement changes (advance<->fall back). |
| `phases.MovementPhase.fall_back_desperate_escape` | `iss064_fallback_single_hazard_11e` | Battle-shocked fall-back applies 06.03 desperate-escape hazards once at BEGIN_FALL_BACK. |
| `phases.ScoutPhase.CONFIRM_SCOUT_MOVE.position_writes_to_state` | `scout_confirm_persists_to_state` | CONFIRM_SCOUT_MOVE action commits staged positions into GameState.units[].models[].position and survives into the movement phase snapshot. |
| `phases.ScoutPhase.END_SCOUT_PHASE.commits_staged_moves_directly` | `scout_end_phase_action_commits_staged` | END_SCOUT_PHASE action (AI/MCP path) commits staged scout moves into GameState (token at moved pos after transition). |
| `phases.ScoutPhase.END_SCOUT_PHASE.rejects_when_staged_invalid` | `scout_end_phase_rejects_invalid_staged` | END_SCOUT_PHASE rejects an incoherent staged config and leaves the phase SCOUT so the player can fix it. |
| `phases.ScoutPhase.reserves_deploy_11e` | `iss067_scout_reserves_11e` | Ed.11 (24.31): a Scout unit in strategic reserves is offered SCOUT_RESERVES_DEPLOY in the Scout phase. |
| `phases.ShootingPhase.11e_shooting_types` | `iss048_shooting_types_11e` | At ed.11 ShootingPhase drives ShootingType templates; engaged VEHICLE falls back to CLOSE-QUARTERS when NORMAL requested. |
| `rules.FightSequencer` | `iss050_fight_11e` | FightSequencer picks next selecting player and allows the overrun case (charged-but-disengaged still selectable, 12.06). |
| `scripts.AIDecisionMaker.11e_legality` | `iss062_ai_11e` | AIDecisionMaker proposes only 11e-legal actions (no validation-failure spam). |
| `shootingtypes.CloseQuartersShooting` | `iss048_shooting_types_11e` | CloseQuartersShooting (10.06) lets an engaged M/V fire at its engager. |
| `shootingtypes.ShootingTypes.available_for` | `iss048_shooting_types_11e` | ShootingTypes.available_for filters selectable shooting types by engagement. |

## Honest scope notes (not over-claimed)

- `terrain.parse_test`, `deployment.search_and_destroy` (via `main_menu_defaults`): the scenario only asserts the main-menu **dropdowns default** to these options — it does **not** exercise terrain parsing or Search-and-Destroy deployment logic. Tile descriptions say so.

- **RULES**-fidelity tiles verify the engine/template layer (the action is accepted and the rule holds), per the project methodology that permits headless verification for rules/movetypes/autoload internals. The player-facing UI affordances for the 11e features are validated separately by the e11 windowed suite and the ISS-066/068/069/071/073/074 windowed scenarios from PR #477; this tier does not by itself prove a literal human click reaches each rule.

## Residual / out of scope

- `check_coverage.py` still prints **102 staleness warnings** for **pre-existing** tiles whose `last_verified_commit` is `HEAD` or an old SHA. These are warnings (non-fatal; the gate exits 0) and predate this work. Not addressed here to keep the change scoped to the failing gate.

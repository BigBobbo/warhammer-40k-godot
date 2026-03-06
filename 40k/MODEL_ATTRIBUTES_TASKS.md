# Per-Model Loadout & Model Attributes Implementation Tasks

> Source: Full codebase audit of deployment, shooting, melee, damage, abilities, transport, army loading, and save/load systems.
> Goal: Enable units with heterogeneous models (different weapons, stats, base sizes) such as Lootas with mixed deffguns/kustom mega-blastas and a Spanner, with user choice of which model to deploy.

---

## Phase 0: Bug Fixes

### MA-34: Fix Battlewagon rendering as small circular base instead of large rectangle
- [x] Investigate why the Battlewagon model from the army JSON is displaying with a small circular base when deployed, despite the JSON specifying `"base_type": "rectangular"` and `"base_dimensions": {"length": 180, "width": 110}`
- [x] Trace the data flow from army JSON load through ArmyListManager, GameState, DeploymentController, and into TokenVisual/GhostVisual to identify where `base_type` and `base_dimensions` are being lost or ignored
- [x] Check if `Measurement.create_base_shape()` (Measurement.gd:60-84) receives the correct model dict with `base_type`/`base_dimensions` fields intact, or if it falls through to the default circular base
- [x] Check if StateSerializer validation (lines ~748-755) or any other processing step strips or fails to preserve the `base_type` and `base_dimensions` fields
- [x] Check if TokenVisual and GhostVisual correctly read `base_type` from the model data when creating the visual representation, or if they only use `base_mm` and assume circular
- [x] Fix the root cause so that the Battlewagon (and any other vehicle with a rectangular or oval base) renders with the correct base shape and dimensions
- [x] Verify other non-circular base models (if any exist in army JSONs) also render correctly
- **Files**: ArmyListManager.gd, StateSerializer.gd, Measurement.gd, TokenVisual.gd, GhostVisual.gd, DeploymentController.gd, army JSON files (orks.json, ORK_test.json, Orks_2000.json)
- **Validation**: Deploy the Battlewagon. It renders with a large rectangular base (~180mm x 110mm) rather than a small circle. Ghost visual during placement also shows the rectangular shape. Distances measured from the Battlewagon use edge-to-edge rectangular math. Other units with circular bases are unaffected.

### MA-35: Fix unable to select units for transport embarkation
- [x] Investigate why clicking on units in the transport embarkation UI does not register selection, even though the option is visible
- [x] Trace the transport embark flow: after deploying a TRANSPORT unit, the DeploymentTransportDialog should appear allowing the user to select which units to embark
- [x] Check DeploymentTransportDialog for click handling issues — button signals, input blocking, z-order/layering problems, or modal dialog consuming input
- [x] Check if the clickable elements (buttons, list items) have correct mouse filter settings and are not obscured by invisible overlays or other UI nodes
- [x] Check TransportManager embark validation — the selection may be silently rejected if validation fails (capacity, keyword restrictions, unit status)
- [x] Verify the issue in both single-player and multiplayer contexts
- [x] Fix the root cause so that units can be selected and embarked into transports during deployment
- **Files**: DeploymentTransportDialog.gd (or equivalent transport embark UI), DeploymentController.gd (transport embark flow), TransportManager.gd (embark validation)
- **Validation**: Deploy a Battlewagon (or other TRANSPORT unit). Transport embark dialog appears. Click on an eligible unit to embark — it is selected and embarked successfully. Capacity updates correctly. Ineligible units are greyed out or show a reason. Dialog can be dismissed without embarking if desired.

### MA-36: Fix ESC key not opening menu during shooting phase
- [ ] Investigate why pressing ESC during the shooting phase does not open the game menu (pause/settings), when it works in other phases
- [ ] Check ShootingController.gd for input handling that may be consuming or blocking the ESC key event (e.g., `_unhandled_input`, `_input`, or `ui_cancel` action handling)
- [ ] Check if ESC is being intercepted to cancel a weapon selection, target selection, or other shooting UI state instead of propagating to the menu
- [ ] Check if any modal dialog or overlay active during shooting (WeaponOrderDialog, NextWeaponDialog, etc.) is swallowing the ESC input
- [ ] Verify how ESC is handled in other phases (deployment, movement, charge, fight) for comparison
- [ ] Fix so that ESC opens the game menu during the shooting phase, or if ESC is used for cancelling shooting actions, ensure the menu is still accessible (e.g., ESC cancels action first, second ESC opens menu, or menu is accessible via a different path)
- **Files**: ShootingController.gd, WeaponOrderDialog.gd, NextWeaponDialog.gd, Main.gd (or wherever the pause menu input is handled)
- **Validation**: During the shooting phase with no dialog open, press ESC — game menu opens. If a weapon/target selection is active, ESC cancels that selection first; pressing ESC again opens the menu. Menu is accessible in all shooting sub-states (unit selection, target selection, weapon ordering, between weapon resolutions).

### MA-37: Fix army JSON parsing only creating one model for multi-model squads
- [x] Investigate the army JSON upload/parsing pipeline to identify why squads with multiple models (e.g., Burna Boyz in Orks_2000.json) are only producing a single model entry in the `models` array
- [x] Check the unit_composition field (e.g., `"description": "5 Burna Boyz"`) — determine if the parser reads this to know how many models to create, or if it relies on the models array being pre-populated in the JSON
- [x] Check if the issue is in the JSON itself (models array only has 1 entry) or in the loading pipeline (ArmyListManager strips/truncates the array)
- [x] If the JSON is generated by an external tool or upload process, trace that tool's logic for populating the models array from the unit_composition data
- [x] Fix the root cause so that multi-model squads have the correct number of model entries, each with appropriate wounds, base_mm, and other fields
- [x] Audit other units across all army JSON files (orks.json, Orks_2000.json, space_marines.json, etc.) for the same issue — any unit where unit_composition says N models but the models array has fewer
- **Files**: Army JSON files (Orks_2000.json and others), ArmyListManager.gd, any army import/upload tooling
- **Validation**: Load Orks_2000 army. Burna Boyz unit has the correct number of models matching its unit_composition (e.g., 5 models for "5 Burna Boyz"). Each model has correct wounds, base_mm, and alive status. Deploy the unit — all models are placeable. Other multi-model squads across all armies also have correct model counts.

### MA-38: Fix movement range using strict less-than instead of less-than-or-equal
- [ ] Investigate movement validation logic to find where the movement distance check uses `<` (strict less-than) instead of `<=` (less-than-or-equal) against the model's Move characteristic
- [ ] Per 10th Edition core rules, a model can move "up to" its Move characteristic in inches — this means a model with M6" can move exactly 6" (less than or equal to 6)
- [ ] Check MovementController/MovementPhase for the distance comparison that rejects or flags moves at exactly the max distance
- [ ] Check if the issue is in the validation check, the visual indicator (showing red at exactly max range), or both
- [ ] Fix the comparison to use `<=` so that moving exactly the Move characteristic value is allowed
- [ ] Verify the same fix applies to Advance moves (Move + D6"), charge moves, pile-in, and consolidate distances if they share the same comparison logic
- **Files**: MovementController.gd (or equivalent movement script), RulesEngine.gd (if movement validation lives there), any movement phase scripts
- **Validation**: Unit with M6" moves exactly 6.0" — move is accepted (green indicator, not rejected). Moving 6.01" is rejected. Same for Advance: if rolled a 3 on D6, moving exactly 9" (6+3) is accepted. Charge, pile-in (3"), and consolidate (3") also accept moves at exactly their max distance.

### MA-39: Fix "A Tempting Target" secondary mission implementation
- [x] Research the exact rules for "A Tempting Target" from Chapter Approved 2025-26 (https://wahapedia.ru/wh40k10ed/the-rules/chapter-approved-2025-26/) — confirm: when it is drawn, which player selects the objective, what restrictions apply to the selection (e.g., must be in No Man's Land), when it scores, what the VP values are, and any edge cases
- [x] Audit the current implementation in SecondaryMissionManager.gd — check `_check_tempting_target()`, `resolve_tempting_target()`, and the When Drawn handler to see if they match the actual rules
- [x] Verify opponent selection flow: when this card is drawn, the opposing player (not the card holder) must choose an objective. Check that TemptingTargetDialog.gd correctly prompts the right player and that the selection is properly stored
- [x] Verify the selected objective is clearly communicated to both players — there should be a persistent visual indicator on the board (e.g., highlighted objective marker, icon, or label) showing which objective was chosen, visible throughout the game
- [x] Verify scoring timing: check whether the mission scores at the end of the card holder's turn, end of opponent's turn, or another timing, and confirm the code evaluates at the correct phase
- [x] Verify the scoring condition itself: confirm what "controlling" the tempting target means and that the check correctly evaluates objective control
- [x] Check multiplayer: ensure the opponent selection dialog works correctly over the network, the selected objective syncs to both clients, and the visual indicator appears for both players
- [x] Check AI: ensure AIPlayer handles the opponent selection correctly when AI is the opposing player (auto-selects a valid objective)
- [x] Fix any discrepancies found between the rules and the current implementation
- **Files**: SecondaryMissionManager.gd, SecondaryMissionData.gd, TemptingTargetDialog.gd, ScoringController.gd, MissionManager.gd, AIPlayer.gd
- **Validation**: Draw "A Tempting Target". Opposing player is prompted to select an objective (only valid objectives shown). Selected objective is visually marked on the board for both players. Scoring evaluates at the correct phase per the rules. VP awarded correctly when conditions are met. Works in both single-player (AI selects) and multiplayer (remote player selects via dialog).

### MA-40: Fix "Marked for Death" secondary mission implementation
- [x] Research the exact rules for "Marked for Death" from Chapter Approved 2025-26 (https://wahapedia.ru/wh40k10ed/the-rules/chapter-approved-2025-26/) — confirm: when it is drawn, the two-step selection process (opponent picks Alpha targets, card holder picks Gamma target), what restrictions apply to unit selection, when it scores, VP values for destroying Alpha vs Gamma targets, and any edge cases
- [x] Audit the current implementation in SecondaryMissionManager.gd — check `_check_alpha_target_destroyed()`, `_check_gamma_target_destroyed()`, `resolve_marked_for_death()`, and the When Drawn handler to see if they match the actual rules
- [x] Verify the two-step opponent/player selection flow:
  - Step 1: When the card is drawn, the opposing player selects units as Alpha targets (confirm how many and any restrictions on which units are eligible)
  - Step 2: The card holder then selects one unit as the Gamma target from among the Alpha targets or from a different pool (confirm the exact rule)
- [x] Check that MarkedForDeathDialog.gd correctly implements both selection steps, prompting the right player at each step
- [x] Verify selected targets are clearly communicated to both players — there should be persistent visual indicators on the board (e.g., icons, labels, or colored markers on the targeted units) showing which units are Alpha targets and which is the Gamma target, visible throughout the game
- [x] Verify scoring timing: confirm when "Marked for Death" scores (end of turn, when unit destroyed, etc.) and that the code evaluates at the correct phase
- [x] Verify scoring conditions: confirm VP awarded for destroying Alpha targets vs the Gamma target and that the checks correctly detect unit destruction
- [x] Check multiplayer: ensure the two-step selection dialog works over the network — opponent selects first, then card holder selects, selections sync to both clients, visual indicators appear for both players
- [x] Check AI: ensure AIPlayer handles both the opponent selection (picking Alpha targets) and card holder selection (picking Gamma target) correctly with reasonable choices
- [x] Fix any discrepancies found between the rules and the current implementation
- **Files**: SecondaryMissionManager.gd, SecondaryMissionData.gd, MarkedForDeathDialog.gd, ScoringController.gd, MissionManager.gd, AIPlayer.gd
- **Validation**: Draw "Marked for Death". Opposing player is prompted to select Alpha target units (only valid units shown). Card holder is then prompted to select Gamma target. Selected units are visually marked on the board with distinct indicators for Alpha vs Gamma. Scoring evaluates at the correct time per the rules. Correct VP awarded when Alpha or Gamma targets are destroyed. Works in single-player (AI handles both selection roles) and multiplayer (each player selects via dialog over network).

### MA-41: Fix keyboard input leaking through save/load panel text input
- [x] Investigate why typing into the save name text field in the save/load panel causes game actions (camera panning, hotkeys, unit actions, etc.) to fire in the background
- [x] The root cause is likely that the LineEdit/TextEdit does not consume keyboard input events, allowing them to propagate to the game's `_unhandled_input()` or `_input()` handlers
- [x] Check if the save/load panel sets focus on the text input field when opened — without focus, key events won't be captured by the LineEdit
- [x] Check if the game's input handlers (Main.gd, camera controller, phase controllers) check whether a GUI control has focus before processing key events (e.g., `get_viewport().gui_get_focus_owner() != null`)
- [x] Fix by either: (a) ensuring the save/load panel's text input grabs focus and consumes key events, (b) adding a guard in the game's input handlers to skip processing when a text input has focus, or (c) both
- [x] Verify the fix also applies to any other text input fields in the game (e.g., player name entry, chat input in multiplayer) if they exist
- **Files**: SaveLoadPanel.gd (or equivalent save/load UI script), Main.gd (camera/input handling), any scripts with `_unhandled_input` or `_input` that process key events
- **Validation**: Open save/load panel. Click into the save name text field. Type a name — letters appear in the text field only, camera does not pan, no game actions triggered. Press Enter to confirm save. Close panel — keyboard controls resume working normally. If other text inputs exist, they also consume keyboard input correctly.

### MA-42: Block active player actions while reactive stratagem decision is pending
- [ ] Investigate the current reactive stratagem flow (Fire Overwatch, Rapid Ingress, Counter-Offensive, Heroic Intervention, etc.) — the game notifies the non-active player they can use a reactive stratagem but does not block the active player from continuing
- [ ] Implement a blocking/pause mechanism: when a reactive stratagem prompt is shown to the non-active player, the active player's input should be disabled (no movement, shooting, charges, or other actions) until the non-active player responds
- [ ] Add a visible indicator for the active player showing they are waiting for the opponent's stratagem decision (e.g., "Waiting for opponent..." overlay or message)
- [ ] Implement a 5-second auto-decline timer: if the non-active player does not click a decision within 5 seconds, automatically select "No" / decline the stratagem and unblock the active player
- [ ] Show a countdown timer on the stratagem prompt so the non-active player knows how long they have to decide
- [ ] Ensure AI opponents respond immediately (or near-immediately) rather than waiting for the timer, since the AI decision is instant
- [ ] Verify this works for all reactive stratagems: Fire Overwatch, Rapid Ingress, Counter-Offensive, Heroic Intervention, and any others
- [ ] Verify multiplayer: the blocking state syncs correctly — active player sees "waiting" on their client, non-active player sees the stratagem prompt on theirs, and unblocking happens when either a decision is made or the timer expires
- [ ] Ensure the timer resets/cancels correctly if the non-active player clicks a response before it expires
- [ ] Edge case: if multiple reactive stratagems could trigger at the same point (e.g., both Overwatch and Heroic Intervention), handle them sequentially — block until all pending decisions are resolved
- **Files**: StratagemManager.gd, PhaseManager.gd (or equivalent turn flow controller), Main.gd, NetworkManager.gd, AIPlayer.gd, any reactive stratagem UI/dialog scripts
- **Validation**: Active player declares a charge. Non-active player is prompted to use Fire Overwatch. Active player cannot proceed (input blocked, "Waiting for opponent..." shown). Non-active player clicks "Yes" or "No" — active player is unblocked. If non-active player does nothing for 5 seconds, auto-declines and active player is unblocked. AI opponent responds immediately without waiting for timer. Works correctly in multiplayer with both clients staying in sync.

### MA-43: Remove "Opponents Actions" panel and ensure game log covers all its content
- [ ] Identify the "Opponents Actions" panel — find the UI node/script responsible for it and catalogue everything it currently displays (opponent movement, shooting results, charge declarations, stratagem usage, etc.)
- [ ] Compare the panel's content against what is already recorded in the game log — identify any information shown only in the "Opponents Actions" panel that is not in the game log
- [ ] For any missing information, add it to the game log so nothing is lost when the panel is removed
- [ ] Remove the "Opponents Actions" panel entirely — delete the UI node, scene, and script
- [ ] Verify the right-hand panel is no longer obscured or overlapped by the removed panel
- [ ] Clean up any signals, references, or update calls to the removed panel across the codebase
- **Files**: The "Opponents Actions" panel script/scene (identify exact file), Main.gd or HUD script (where the panel is instantiated/shown), game log script (to add any missing log entries)
- **Validation**: Play a game against the AI. The "Opponents Actions" panel no longer appears. All opponent actions (movement, shooting, charges, stratagems, etc.) are visible in the game log. The right-hand panel is fully visible and not obscured. No errors or warnings related to the removed panel in the logs.

---

## Phase 1: Data Schema & Army Loading

### MA-1: Add `model_profiles` to unit meta schema
- [ ] Define `model_profiles` dictionary structure in unit `meta`:
  ```json
  "model_profiles": {
    "loota_deffgun": {
      "label": "Loota (Deffgun)",
      "stats_override": {},
      "weapons": ["Deffgun", "Close combat weapon"],
      "transport_slots": 1
    }
  }
  ```
- [ ] Each profile has: `label` (display name), `stats_override` (dict of stat deltas over unit base stats), `weapons` (array of weapon names referencing `meta.weapons`), `transport_slots` (int, default 1)
- [ ] Units without `model_profiles` continue to work unchanged (all models share all weapons)
- **Files**: Army JSON files (orks.json as first example)
- **Validation**: Load army with `model_profiles`, verify `meta.model_profiles` dict is accessible via `GameState.get_unit(unit_id).meta.model_profiles`

### MA-2: Add `model_type` field to individual models
- [ ] Each model in `unit.models[]` gains a `model_type` string field referencing a key in `meta.model_profiles`
- [ ] Models without `model_type` (null or absent) use legacy behavior (all weapons)
- [ ] Create example Lootas unit in orks.json: 8x loota_deffgun, 2x loota_kmb, 1x spanner with different BS via `stats_override`
- **Files**: Army JSON files, ArmyListManager.gd (processing)
- **Validation**: Load army, iterate `unit.models`, confirm each model's `model_type` matches a key in `meta.model_profiles`

### MA-3: ArmyListManager processes and validates model_profiles on load
- [ ] In `_process_army_data()`, verify that every model's `model_type` references an existing profile key (log error if not)
- [ ] Verify every weapon name in each profile's `weapons` array exists in `meta.weapons` (log warning if not)
- [ ] Ensure `model_profiles` dict is preserved through load pipeline (not stripped or mutated)
- [ ] Backward compat: units without `model_profiles` skip all new validation
- **Files**: ArmyListManager.gd (lines ~387-489)
- **Validation**: Load army with valid profiles (no errors), load army with invalid `model_type` reference (error logged), load army with missing weapon name in profile (warning logged), load old army without profiles (no errors)

### MA-4: StateSerializer validation for model_type
- [ ] In `_validate_unit_data()` model loop (~lines 687-762), add validation for `model_type` field:
  - If `model_profiles` exists on unit meta, warn if model has no `model_type`
  - Warn if `model_type` references nonexistent profile key
  - Auto-repair: if `model_profiles` has exactly 1 key and `model_type` is missing, set it to that key
- [ ] Ensure `model_type` (string) serializes/deserializes without special handling
- [ ] Add save migration: old saves without `model_type` on models load with `model_type = null` (no crash)
- **Files**: StateSerializer.gd (lines ~537-846)
- **Validation**: Save game with model_type models, reload, verify model_type preserved. Load old save without model_type, verify no crash and null/absent model_type. Intentionally corrupt model_type to invalid key, verify warning logged and graceful handling.

### MA-5: Create test army JSON with heterogeneous unit
- [ ] Add a Lootas unit to orks.json (or a test army file) with:
  - 8 models: `model_type: "loota_deffgun"` — Deffgun (Heavy D3, BS5+, S8, AP-1, D2)
  - 2 models: `model_type: "loota_kmb"` — Kustom mega-blasta (Assault 1, BS5+, S9, AP-2, D[D6], Hazardous)
  - 1 model: `model_type: "spanner"` — Kustom mega-blasta, BS4+ via stats_override, different base_mm if applicable
- [ ] Add a simpler heterogeneous unit (e.g., Intercessor Squad with Sergeant having different melee weapon) for Space Marines testing
- [ ] Verify both units load without errors
- **Files**: 40k/armies/orks.json (or new test army), 40k/armies/space_marines.json
- **Validation**: Both units load, `GameState.get_unit()` returns correct model_profiles and model_type on each model

---

## Phase 2: Core Weapon Assignment

### MA-6: Update `get_unit_weapons()` for per-model profiles
- [ ] In `get_unit_weapons()` (RulesEngine.gd:3390-3451), add branch:
  - If `meta.model_profiles` exists, look up each alive model's `model_type` → profile → `weapons` array
  - Map weapon names to weapon IDs via `_generate_weapon_id()`
  - Only assign weapons listed in that model's profile
  - If model has no `model_type` or no `model_profiles` on unit, fall back to current behavior (all weapons)
- [ ] Ensure attached character weapons still use composite IDs (lines 3427-3449 unchanged)
- **Files**: RulesEngine.gd
- **Validation**: Call `get_unit_weapons()` on Lootas unit. Verify deffgun models return only deffgun weapon ID, mega-blasta models return only mega-blasta weapon ID, spanner returns mega-blasta. Call on unit without profiles, verify unchanged behavior. Call on unit with attached character, verify composite IDs still work.

### MA-7: Update `get_unit_melee_weapons()` for per-model profiles
- [ ] In `get_unit_melee_weapons()` (RulesEngine.gd:7360-7395), add same per-model profile lookup
- [ ] Each model's melee weapons come from their profile's `weapons` array filtered to `type == "Melee"`
- [ ] Fallback to current behavior when no `model_profiles`
- **Files**: RulesEngine.gd
- **Validation**: Unit with Nob (power klaw) + Boyz (choppa) returns correct melee weapons per model. Unit without profiles returns same weapons for all models.

### MA-8: Update weapon filter functions for per-model profiles
- [ ] Update `get_pistol_weapons()` (RulesEngine.gd:3587-3623) to filter per-model
- [ ] Update `get_assault_weapons()` (RulesEngine.gd:3636-3653) to filter per-model
- [ ] Update `get_heavy_weapons()` (RulesEngine.gd:3672-3689) to filter per-model
- [ ] Update `get_rapid_fire_weapons()` (RulesEngine.gd:5110-5180) to filter per-model
- [ ] Update `get_torrent_weapons()` (RulesEngine.gd:4873-4890) to filter per-model
- [ ] All functions: if no `model_profiles`, fall back to current behavior
- **Files**: RulesEngine.gd
- **Validation**: For Lootas, `get_heavy_weapons()` returns deffgun only for deffgun models (Heavy keyword), `get_assault_weapons()` returns mega-blasta only for kmb/spanner models (Assault keyword). Models without the weapon keyword return empty.

### MA-9: Unify overwatch weapon assembly with new per-model path
- [ ] `_build_overwatch_weapon_assignments()` (RulesEngine.gd:856-908) already reads `model.get("weapons", [])` per model
- [ ] Align this to use the same profile-based lookup as `get_unit_weapons()` so both paths produce consistent results
- [ ] Extract a shared helper: `_get_model_weapon_ids(unit, model, weapon_type_filter)` used by both `get_unit_weapons()` and overwatch
- **Files**: RulesEngine.gd
- **Validation**: Fire overwatch with Lootas unit. Verify 8 models fire deffguns and 3 models (2 kmb + 1 spanner) fire mega-blastas in separate assignments.

---

## Phase 3: Per-Model Stats in Combat Resolution

### MA-10: Per-model BS in ranged hit resolution
- [ ] In `_resolve_shooting_assignment()` (~RulesEngine.gd:1270) and `_resolve_shooting_assignment_auto()` (~RulesEngine.gd:1847+), BS is currently read from weapon profile: `weapon_profile.get("bs", 4)`
- [ ] Add check: if model has `model_type` with `stats_override.ballistic_skill`, use that instead
- [ ] Implementation approach: since attacks are rolled per-model in the loop (lines 1224-1239), look up the model's BS override at roll time
- [ ] If no override, use weapon profile BS (existing behavior)
- **Files**: RulesEngine.gd
- **Validation**: Lootas spanner (BS4+) should hit on 4+ while regular Lootas (BS5+) hit on 5+. Create test: fire Lootas, verify spanner's hits use BS4+ threshold.

### MA-11: Per-model WS in melee hit resolution
- [ ] In `_resolve_melee_assignment()` (~RulesEngine.gd:6516), WS is read from weapon profile: `weapon_profile.get("ws", 4)`
- [ ] Add same override logic as MA-10: check model's `stats_override.weapon_skill`
- [ ] Melee attack loop (~lines 6464-6505) already iterates per model — add per-model WS lookup there
- **Files**: RulesEngine.gd
- **Validation**: Unit with Nob (WS3+) and Boyz (WS4+) resolves correct hit thresholds per model. Verify with test.

### MA-12: Per-model save characteristics in wound allocation
- [ ] In `prepare_save_resolution()` (~RulesEngine.gd:7556-7569), model save profiles are built from unit-level stats
- [ ] Add `stats_override` merge: for each model, if it has a `model_type` with `stats_override.save`, use that instead of unit save
- [ ] Also handle per-model `invuln` override if present in `stats_override`
- [ ] Pass through to `model_save_profiles` used by WoundAllocationOverlay
- **Files**: RulesEngine.gd
- **Validation**: Unit with MEGA ARMOUR model (save 2+) and regular model (save 5+) shows correct save values in wound allocation UI. Test both interactive and auto-resolve paths.

### MA-13: Per-model wounds from stats_override
- [ ] If `stats_override` contains `wounds`, ensure model's max wounds uses that value
- [ ] Currently `model["wounds"]` is set from JSON — this may be sufficient if JSON is authored correctly
- [ ] Add validation: if `model_profiles` has `wounds` in `stats_override`, verify model JSON `wounds` field matches
- [ ] Document that `model["wounds"]` in JSON should match the profile's effective wounds value
- **Files**: ArmyListManager.gd (validation), documentation
- **Validation**: Model with stats_override.wounds = 3 has correct max wounds. Wargear bonus (e.g., Praesidium Shield +1W) stacks correctly on top of profile wounds.

### MA-14: Rapid Fire bonus per-weapon-per-model
- [ ] In shooting resolution (~RulesEngine.gd:1246), Rapid Fire bonus is `models_in_half_range * rapid_fire_value`
- [ ] This counts ALL models in half range, but with per-model weapons, only models that actually have the RF weapon should count
- [ ] Fix: when computing `models_in_half_range`, filter to models present in the current assignment's `model_ids`
- [ ] Same fix needed in auto-resolve path (~RulesEngine.gd:1862)
- **Files**: RulesEngine.gd
- **Validation**: Unit with 5 bolter models and 5 plasma models. Only bolter models count for bolt rifle RF bonus. Only plasma models count for plasma gun RF bonus (if RF). Verify with mixed-weapon unit.

---

## Phase 4: Deployment Model Selection

### MA-15: Model type picker UI during deployment
- [ ] When `begin_deploy()` is called for a unit with `model_profiles` containing >1 distinct `model_type` among unplaced models, show a model type selector panel
- [ ] Panel shows each remaining model type with its `label` and count of unplaced models of that type
- [ ] Clicking a type selects the next model of that type as the one to place
- [ ] If only 1 type remains, auto-select it (no panel shown)
- [ ] If unit has no `model_profiles`, deployment works exactly as before
- **Files**: DeploymentController.gd (new state tracking), new UI panel scene
- **Validation**: Deploy Lootas unit. Panel shows "Loota (Deffgun) x8", "Loota (Mega-blasta) x2", "Spanner x1". Select Spanner, place it. Panel updates to show "Spanner x0" (greyed out). Select deffgun type, place 8 times. Auto-selects mega-blasta type for final 2. Deploy unit without profiles — no panel shown.

### MA-16: Update deployment model_idx to support non-sequential placement
- [ ] Currently `model_idx` increments 0, 1, 2... placing models in array order
- [ ] With model selection, user might place m11 (spanner) first, then m1-m8, then m9-m10
- [ ] Change placement to track `current_model_to_place` as a model array index selected by the picker
- [ ] `_get_unplaced_model_indices()` (~line 1713) still works (returns indices where position is null)
- [ ] Update `temp_positions` and `temp_rotations` indexing to work with non-sequential placement
- **Files**: DeploymentController.gd
- **Validation**: Place models in arbitrary order (spanner first, then deffguns, then mega-blastas). All positions saved correctly. Coherency checks work. Confirm deployment succeeds.

### MA-17: Update ghost visual to show model type info
- [ ] During placement, ghost visual should display the model type label (e.g., "Spanner") near the cursor or on the ghost
- [ ] Use a small Label node attached to the ghost showing `model_profiles[model_type].label`
- [ ] If no `model_profiles`, no label shown (existing behavior)
- **Files**: GhostVisual.gd, DeploymentController.gd
- **Validation**: While placing a Spanner model, ghost shows "Spanner" label. While placing deffgun Loota, ghost shows "Loota (Deffgun)". No label on units without profiles.

### MA-18: Update formation deployment for mixed base sizes
- [ ] `calculate_spread_formation()` (~DeploymentController.gd:1722) and `calculate_tight_formation()` (~line 1761) use first model's `base_mm` for all
- [ ] With heterogeneous units, models may have different base sizes
- [ ] Fix: use each model's actual `base_mm` when calculating spacing
- [ ] For spread: ensure 2" coherency edge-to-edge, accounting for different radii
- [ ] For tight: use base-touching distance, accounting for different radii
- **Files**: DeploymentController.gd
- **Validation**: Formation with 40mm Nob and 32mm Boyz spaces correctly. Spread formation maintains 2" coherency. Tight formation has bases touching. No overlap.

### MA-19: Combined deployment (character + bodyguard) with model types
- [ ] Combined deployment already tracks `combined_models[i] = {unit_id, model_idx, model_data}`
- [ ] Extend to include `model_type` for display purposes
- [ ] Model picker should show character models as their own type group (e.g., "Warboss x1" alongside bodyguard types)
- [ ] Character models should always be placeable (no type restriction)
- **Files**: DeploymentController.gd
- **Validation**: Deploy Warboss attached to Nobz. Picker shows "Warboss x1" and "Nob x5". Can place in any order. All models placed correctly with correct unit_id associations.

---

## Phase 5: Token Visuals & Model Identity

### MA-20: Show model type on deployed tokens
- [ ] TokenVisual currently shows model_number (array index) on the base
- [ ] Add optional short label or distinct color/icon per model type
- [ ] Option A: Show first letter(s) of model type label (e.g., "S" for Spanner, "D" for Deffgun, "K" for KMB)
- [ ] Option B: Use a colored ring around the base per model type (configurable per profile)
- [ ] If no `model_profiles`, show model_number as before
- **Files**: TokenVisual.gd
- **Validation**: Deployed Lootas unit shows visual distinction between deffgun, mega-blasta, and spanner models. Players can tell models apart at a glance. Units without profiles unchanged.

### MA-21: Show model type in wound allocation UI
- [ ] In WoundAllocationOverlay, when player selects which model takes a wound, display model type label alongside model ID
- [ ] Add `model_type` field to save profiles in `prepare_save_resolution()` (~RulesEngine.gd:7556)
- [ ] WoundAllocationOverlay reads `model_type` from profile and shows label (e.g., "Loota (Deffgun) - m3" or "Spanner - m11")
- **Files**: RulesEngine.gd (prepare_save_resolution), WoundAllocationOverlay.gd
- **Validation**: Take wounds on Lootas unit. Wound allocation UI shows model type labels. Player can distinguish which model type they're allocating wounds to. Units without profiles show model IDs only (existing behavior).

### MA-22: Show model type in casualty reporting
- [ ] When models die, log messages and any casualty summary should include model type
- [ ] Update death logging to include profile label: "Spanner (m11) destroyed" instead of "m11 destroyed"
- [ ] If secondary mission hooks track kills, include model type info
- **Files**: RulesEngine.gd (damage application), WoundAllocationOverlay.gd
- **Validation**: Kill a Spanner model. Log shows "Spanner (m11) destroyed". Kill a deffgun Loota. Log shows "Loota (Deffgun) (m3) destroyed". Units without profiles show "m3 destroyed" as before.

### MA-23: UnitStatsPanel shows model composition breakdown
- [ ] UnitStatsPanel (unit info display) should show model composition when `model_profiles` exists
- [ ] Display: "8x Loota (Deffgun), 2x Loota (Mega-blasta), 1x Spanner" with alive/dead counts
- [ ] Show each profile's weapons and stats overrides
- **Files**: UnitStatsPanel.gd
- **Validation**: Select Lootas unit. Stats panel shows breakdown by model type with weapon info. Shows alive counts. After casualties, counts update. Units without profiles show existing display.

---

## Phase 6: Transport & Special Rules

### MA-24: Transport capacity respects per-model transport_slots
- [ ] Add `transport_slots` field to model profiles (default 1)
- [ ] In TransportManager capacity counting (~lines 154-174), multiply each model by its profile's `transport_slots`
- [ ] MEGA ARMOUR models should have `transport_slots: 2` in their profile
- [ ] Embark validation uses slot-aware count
- **Files**: TransportManager.gd, army JSON files
- **Validation**: Battlewagon with 22 capacity. Embark 10 regular Boyz (10 slots) + 5 Meganobz (10 slots) = 20 slots. Attempt to embark 1 more Meganob (2 slots) — fails with "Insufficient capacity". Embark 2 more regular Boyz (2 slots) — succeeds. Unit without profiles counts 1 per model as before.

### MA-25: Pistol mutual exclusivity per-model
- [ ] Pistol validation (~RulesEngine.gd:2823-2841) currently checks unit-wide
- [ ] Change to per-model: Model A with only pistols can fire pistols while Model B with only bolter fires bolter in same phase
- [ ] If a single model has both pistol and non-pistol weapons in its profile, it must choose one category (not both)
- **Files**: RulesEngine.gd
- **Validation**: Unit with sergeant (bolt pistol + bolt rifle) and marines (bolt rifle only). Sergeant fires bolt pistol, marines fire bolt rifle — allowed. Sergeant tries to fire both bolt pistol AND bolt rifle — rejected. All marines fire bolt rifles — allowed.

### MA-26: Weapon ownership validation in shooting
- [ ] Weapon validation (~RulesEngine.gd:2765-2779) currently checks if weapon exists on unit's weapon list
- [ ] Update to verify the specific models in an assignment actually have that weapon via their profile
- [ ] Reject assignments where model_ids include models that don't own the weapon
- **Files**: RulesEngine.gd
- **Validation**: Attempt to assign deffgun to a mega-blasta model — rejected with error. Assign deffgun to deffgun models — accepted. Assign mega-blasta to spanner — accepted. Unit without profiles allows all weapons to all models.

---

## Phase 7: Ability & Effect Integration

### MA-27: Add per-model stat lookup helper
- [ ] Create `RulesEngine.get_model_effective_stats(unit, model) -> Dictionary` helper
- [ ] Returns unit base stats merged with model's `stats_override` from its profile
- [ ] Used by hit resolution (BS/WS), save resolution, wound allocation, and any future per-model stat checks
- [ ] Returns base unit stats if no `model_type` or no `model_profiles`
- **Files**: RulesEngine.gd
- **Validation**: Call with deffgun Loota model → returns unit base stats. Call with Spanner model → returns base stats with BS overridden to 4. Call with model without model_type → returns unit base stats. Call with unit without model_profiles → returns unit base stats.

### MA-28: Per-model FNP (stretch goal)
- [ ] `get_unit_fnp()` (~RulesEngine.gd:8317-8330) returns single FNP for unit
- [ ] Add `get_model_fnp(unit, model)` that checks model profile `stats_override.fnp` first, then falls back to unit FNP
- [ ] Update `roll_feel_no_pain()` to accept per-model FNP value
- [ ] Only needed if/when a unit with mixed FNP models is added
- **Files**: RulesEngine.gd
- **Validation**: Unit where one model type has FNP 5+ and another has none. Wound allocation rolls FNP only for the model type that has it. Other model type takes full damage.

### MA-29: Ability weapon targeting filter (stretch goal)
- [ ] Some abilities say "add 2 to Attacks of bolt rifles equipped by models in this unit"
- [ ] Add optional `target_weapon_names` field to ability effect definitions
- [ ] When applying attack bonuses, filter to only models whose profile includes the named weapon
- [ ] Currently all abilities apply unit-wide — this would be a new filtering layer
- **Files**: UnitAbilityManager.gd, EffectPrimitives.gd
- **Validation**: Ability "+2 attacks to bolt rifles". Unit has 5 bolt rifle models and 1 plasma model. Only bolt rifle models get +2 attacks. Plasma model unaffected. Ability without target_weapon_names applies to all as before.

---

## Phase 8: Testing & Validation

### MA-30: Unit tests for per-model weapon assignment
- [ ] Test `get_unit_weapons()` with model_profiles unit → each model gets correct weapons
- [ ] Test `get_unit_weapons()` without model_profiles → all models get all weapons (regression)
- [ ] Test `get_unit_melee_weapons()` with model_profiles
- [ ] Test `get_unit_weapons()` with attached character on profiled unit → character weapons use composite IDs
- [ ] Test weapon filter functions (pistol, assault, heavy, rapid fire, torrent) with profiled unit
- **Files**: New test file `tests/test_model_profiles.gd`
- **Validation**: All tests pass. No regression in existing weapon assignment tests.

### MA-31: Unit tests for per-model combat resolution
- [ ] Test shooting with mixed BS (spanner BS4+ vs loota BS5+) → correct hit thresholds
- [ ] Test melee with mixed WS → correct hit thresholds
- [ ] Test Rapid Fire bonus only counts models with RF weapon
- [ ] Test per-model save characteristics in wound allocation
- [ ] Test Hazardous weapon resolution with mixed weapons (only kmb models risk hazardous)
- [ ] Test one-shot tracking with per-model weapons
- **Files**: New test file `tests/test_model_profiles.gd`
- **Validation**: All tests pass with correct per-model stat usage.

### MA-32: Integration test with full game flow
- [ ] Load Orks army with Lootas (heterogeneous unit)
- [ ] Deploy Lootas using model picker — place models in non-sequential order
- [ ] Verify token visuals distinguish model types
- [ ] Shoot with Lootas — 8 deffgun models fire deffguns, 3 models fire mega-blastas, separate assignments
- [ ] Take casualties — wound allocation UI shows model type labels
- [ ] Remove spanner model — verify it's correctly tracked as dead
- [ ] Save game, reload — model_type preserved, weapon assignments correct
- [ ] Verify in multiplayer: remote player sees correct model types and weapon assignments
- **Files**: Manual test / integration test script
- **Validation**: Full flow completes without errors. Weapon assignments match model profiles. Save/load round-trips correctly. Model type visible throughout.

### MA-33: Backward compatibility regression tests
- [ ] Load all existing army JSONs (space_marines.json, orks.json, adeptus_custodes.json) — no errors
- [ ] All units without model_profiles behave identically to before
- [ ] Load old save files without model_type — no crashes, models load with null model_type
- [ ] Shooting, melee, deployment, wound allocation all work for non-profiled units
- [ ] Existing Godot test suite passes with no regressions
- **Files**: Existing test files, manual testing
- **Validation**: All existing tests pass. All existing armies load. Old saves load without error.

---

## Implementation Order

```
Phase 0: MA-34, MA-35, MA-36, MA-37, MA-38, MA-39, MA-40, MA-41, MA-42, MA-43 (bug fixes, no dependencies)
Phase 1: MA-1 → MA-2 → MA-3 → MA-4 → MA-5
Phase 2: MA-6 → MA-7 → MA-8 → MA-9
Phase 3: MA-10 → MA-11 → MA-12 → MA-13 → MA-14 → MA-27
Phase 4: MA-15 → MA-16 → MA-17 → MA-18 → MA-19
Phase 5: MA-20 → MA-21 → MA-22 → MA-23
Phase 6: MA-24 → MA-25 → MA-26
Phase 7: MA-28 → MA-29 (stretch goals)
Phase 8: MA-30 → MA-31 → MA-32 → MA-33 (testing throughout)
```

Dependencies:
- Phase 0 has no dependencies and should be done first
- Phase 2 requires Phase 1 (data schema must exist before weapon assignment reads it)
- Phase 3 requires Phase 2 (per-model weapons must work before per-model stats in combat)
- Phase 4 requires Phase 1 (data schema must exist for deployment UI)
- Phase 5 requires Phase 1 (model_type must exist for display)
- Phase 6 requires Phase 2 (per-model weapons for pistol/transport logic)
- Phase 8 runs alongside all phases (test each phase as completed)
- MA-27 (stat helper) should be built early in Phase 3 and used by MA-10, MA-11, MA-12

## Key Files Reference

| File | Primary Changes |
|------|----------------|
| Army JSON files (orks.json, space_marines.json) | Add model_profiles to meta, model_type to models |
| ArmyListManager.gd | Validate model_profiles and model_type on load |
| StateSerializer.gd | Validate model_type, migration for old saves |
| RulesEngine.gd | get_unit_weapons, get_unit_melee_weapons, weapon filters, BS/WS override, save profiles, rapid fire fix, pistol per-model, weapon validation, stat helper |
| DeploymentController.gd | Model picker UI, non-sequential placement, formation mixed bases |
| GhostVisual.gd | Show model type label during placement |
| TokenVisual.gd | Show model type distinction on deployed tokens |
| WoundAllocationOverlay.gd | Show model type in casualty selection |
| UnitStatsPanel.gd | Show model composition breakdown |
| TransportManager.gd | Per-model transport_slots capacity |
| UnitAbilityManager.gd | Weapon-targeted ability filtering (stretch) |
| EffectPrimitives.gd | Weapon-targeted effect filtering (stretch) |
| tests/test_model_profiles.gd | New test file for all per-model tests |

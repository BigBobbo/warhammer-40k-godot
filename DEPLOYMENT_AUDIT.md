# Deployment Phase Audit Report

## Overview

This audit compares the current deployment phase implementation against the official Warhammer 40,000 10th Edition core rules (Chapter Approved 2025-26). The focus is on the online multiplayer experience.

---

## What's Implemented (Working Well)

### Core Deployment Loop
- **Alternating deployment**: Players alternate deploying one unit at a time (`TurnManager.check_deployment_alternation()` in `40k/autoloads/TurnManager.gd:68`)
- **Deployment zone validation**: Models must be wholly within their player's zone. Supports circular, oval, and rectangular bases (`DeploymentPhase._validate_model_position()` in `40k/phases/DeploymentPhase.gd:119`)
- **Model overlap detection**: Shape-aware collision prevents models from overlapping (`DeploymentPhase._position_overlaps_existing_models_shape()` in `40k/phases/DeploymentPhase.gd:774`)
- **Wall/terrain collision**: Models cannot be placed overlapping walls (`40k/phases/DeploymentPhase.gd:146`)

### Transport Embarkation During Deployment
- Transport capacity validation with keyword restrictions (`DeploymentPhase._validate_embark_units_deployment()` in `40k/phases/DeploymentPhase.gd:168`)
- Dialog-based embark UI that prompts after deploying a transport (`DeploymentController._show_transport_embark_dialog()` in `40k/scripts/DeploymentController.gd:398`)
- Embarked units are correctly marked as DEPLOYED and skip individual placement

### Character Attachment During Deployment
- Leader ability validation against `can_lead` keywords (`DeploymentPhase._validate_attach_character_deployment()` in `40k/phases/DeploymentPhase.gd:391`)
- Dialog prompts when deploying a bodyguard unit that has attachable characters
- Characters are automatically placed adjacent to their bodyguard

### Multiplayer Synchronization
- Deployment actions route through `NetworkIntegration.route_action()` for multiplayer sync
- Optimistic execution for `DEPLOY_UNIT`, `EMBARK_UNITS_DEPLOYMENT`, and `ATTACH_CHARACTER_DEPLOYMENT` actions (`NetworkManager.gd:42-58`)
- Turn-based input blocking prevents deploying when it's not your turn (`DeploymentController.gd:52-53`)
- Host validates all actions before broadcasting to clients

### UI & Interaction
- Formation modes (SINGLE, SPREAD, TIGHT) with ghost previews
- Rotation controls (Q/E keys, mouse wheel) for non-circular bases
- Model repositioning via Shift+click
- Unit coherency warnings (non-blocking) and hard enforcement on confirm

---

## Missing Rules (Compared to 10th Edition)

### 1. Pre-Battle Sequence — Declare Battle Formations — IMPLEMENTED
**Rule**: Before deployment, each player must secretly declare:
- Which Leaders are attached to which Bodyguard units
- Which units start embarked in Transports
- Which units are placed in Strategic Reserves

Both players reveal simultaneously, then deployment begins.

**Status**: **Implemented.** `FormationsPhase.gd` handles the full "Declare Battle Formations" step. Each player declares leader attachments, transport embarkations, and reserves. The phase auto-skips if no declarations are possible. Multiplayer sync via GameState diffs. Both players must confirm before proceeding to deployment.

### 2. Strategic Reserves — IMPLEMENTED
**Rule**: Up to half the units in your army (by count and by points) can start in Reserves. These units arrive from Turn 2 onwards. Units not arriving by end of Round 3 count as destroyed.

**Status**: **Implemented.** `UnitStatus.IN_RESERVES` added to `GameState.gd:8`. Validation enforces reserves point cap and unit count cap (`DeploymentPhase._validate_place_in_reserves()`). Full multiplayer sync support. Updated to 50% points and 50% units per Chapter Approved 2025-26 rules.

### 3. Deep Strike — IMPLEMENTED
**Rule**: Units with the Deep Strike ability can be placed in Reserves during the Declare Battle Formations step. During the Reinforcements step of a Movement phase, they can be set up anywhere on the battlefield >9" from all enemy models.

**Status**: **Implemented.** Full multiplayer sync support.

### 4. Infiltrators — IMPLEMENTED
**Rule**: If every model in a unit has the Infiltrators ability, the unit can be set up anywhere on the battlefield that is >9" from the enemy deployment zone and >9" from all enemy models.

**Status**: **Implemented.** Full server-side and client-side validation.

### 5. Scout Moves — IMPLEMENTED
**Rule**: After deployment is complete but before the first battle round, units with `Scout X"` can make a Normal Move of up to X inches, ending >9" from enemy models. The player who takes the first turn moves their Scout units first.

**Status**: **Implemented.** `ScoutPhase.gd` handles the full Scout Moves sub-phase between deployment and Turn 1. Units with Scout ability get a mini-movement phase with their designated range, must end >9" from enemy models. Player going first moves first. Phase auto-skips if no Scout units exist. Tests in `test_scout_moves.gd`.

### 6. Determine First Turn / Attacker-Defender Roll-Off — IMPLEMENTED
**Rule**: After deployment, players roll off. The winner decides who takes the first turn.

**Status**: **Implemented.** `RollOffPhase.gd` handles the dice roll-off after deployment. Each player rolls 1D6, winner chooses to go first or second. Re-roll on ties. Tests in `test_roll_off_phase.gd`. Phase sequence: Deployment → Scout → Roll-Off → Command.

### 7. Deployment Map Variety — IMPLEMENTED
**Status**: **Implemented.** Five deployment map types available: Hammer and Anvil, Dawn of War, Search and Destroy, Sweeping Engagement, and Crucible of Battle.

### 8. TITANIC Unit Deployment — Not Implemented
**Rule**: When a player sets up a TITANIC unit, they skip their next turn to set up a unit. This represents the extra time needed to position a massive model.

**Current Implementation**: No TITANIC deployment skip logic exists. TITANIC keyword is referenced in other contexts (movement, LoS) but not in deployment alternation.

**Impact**: Low — affects only armies with TITANIC units, but is a rules-accurate penalty for fielding them.

**Recommendation**: In `TurnManager.check_deployment_alternation()` or `DeploymentPhase._process_deploy_unit()`, detect if the just-deployed unit has the TITANIC keyword and skip the deploying player's next turn to deploy.

### 9. Reserves Destroyed if Not Arrived by Round 3 — IMPLEMENTED
**Rule**: Any Reserves units that have not arrived on the battlefield by the end of the third battle round count as destroyed.

**Status**: **Implemented.** `ScoringPhase._destroy_remaining_reserves()` runs at end of Round 3 (when Player 2's turn ends). Finds all units with `IN_RESERVES` status plus any units embarked in reserves transports. Marks all models as dead, reports to `SecondaryMissionManager` and `MissionManager` for VP scoring. Notifications via `GameEventLog` (per-player entries) and `ToastManager` (warning toast listing all destroyed units).

### 10. Mission Selection
**Rule**: 10th Edition has multiple mission types with different primary objectives and deployment configurations.

**Current Implementation**: Only "Take and Hold" with 5 static objectives (`MissionManager.gd`).

**Impact**: Low-Medium for deployment specifically, but high for overall game replayability.

### 11. Fortification Deployment — IMPLEMENTED
**Status**: **Implemented.** `GameState.unit_is_fortification()` checks for the FORTIFICATION keyword. Fortifications blocked from reserves. `[FORT]` tag in deployment list.

---

## Coherency Enforcement — RESOLVED

**Status**: **Fixed.** `_is_unit_coherent()` performs a hard check on `confirm()`. Deployment blocked with red error toast if coherency is violated.

---

## Quality of Life Improvements

### 1. On-Screen Toast Notifications — RESOLVED
**Status**: **Fixed.** `ToastManager` autoload with error/warning/success/info variants.

### 2. Deployment Progress Indicator — RESOLVED
**Status**: **Fixed.** Progress bar panel showing "Player X: X/Y units deployed" with player-colored progress bars.

### 3. "Waiting for Opponent" State in Multiplayer — RESOLVED
**Status**: **Fixed.** Prominent overlay with live turn timer countdown and pulse animation.

### 4. Undo Last Model Placement
**Issue**: The current undo (`DeploymentController.undo()` at line 315) resets the entire unit — all placed models are cleared and `temp_positions` is refilled with `null`. There's no way to undo just the last model placement.

**Recommendation**: Add a per-model undo (e.g., pressing `Ctrl+Z` removes only the most recently placed model by decrementing `model_idx` and clearing the last entry in `temp_positions`). Keep the full-unit reset as a separate "Reset" button.

### 5. Auto-Zoom to Deployment Zone — IMPLEMENTED
**Status**: **Implemented.** `Main.gd` auto-zooms to the active player's deployment zone on phase entry and on turn switch (`_auto_zoom_tween` with smooth cubic easing). Triggered by `deployment_side_changed` signal.

### 6. Deployment Zone Edge Highlighting — IMPLEMENTED
**Status**: **Implemented.** `DeploymentZoneVisual.gd` with animated dashed borders, multi-layer pulsing glow, corner markers, and zone depth labels.

### 7. Unit Base Preview on Hover — IMPLEMENTED
**Status**: **Implemented.** `_setup_deploy_hover_tooltip()` in `Main.gd` creates a tooltip panel showing unit base info on hover in the deployment list.

### 8. Deployment Summary Before Ending Phase — IMPLEMENTED
**Status**: **Implemented.** `DeploymentSummaryDialog.gd` shows deployed units, transports, attached characters, and reserves with explicit confirmation.

### 9. Measuring Tool During Deployment
**Issue**: A measuring tape tool exists (`MeasuringTapeManager`) but there is no visible button or clear keybind to activate it during deployment specifically.

**Recommendation**: Ensure the measuring tape is easily accessible during deployment (visible button or tooltip showing the keybind).

### 10. Replay/History of Opponent's Deployment
**Issue**: In multiplayer, when the opponent deploys a unit, the local player may miss it. There is no camera pan or notification on opponent deployment.

**Recommendation**: When the opponent deploys a unit:
- Briefly pan the camera to show where the unit was placed
- Show a notification: "[Unit Name] deployed at [zone area]"
- Add a deployment log panel showing the order of all deployments

### 11. Coherency Distance Display During Placement
**Issue**: The coherency check uses edge-to-edge distances, but this distance is never shown to the player during placement. When placing a model near the 2" coherency boundary, the player has to guess.

**Recommendation**: Display the distance from the ghost model to the nearest placed model in real-time (e.g., a small floating label next to the ghost showing "1.8\"" in green or "2.3\"" in red).

### 12. Keyboard Shortcut Reference During Deployment
**Issue**: Deployment has several keybinds (Q/E for rotation, Shift+click for repositioning, mouse wheel for rotation) but there is no on-screen reference.

**Recommendation**: Show a small "Controls" panel or tooltip during deployment listing available shortcuts. Could be a toggleable overlay (e.g., press `?` to show/hide).

---

## Visual Improvements

### 1. Deployment Phase Transition Animation — IMPLEMENTED
**Status**: **Implemented.** `PhaseTransitionBanner.gd` shows animated banner for all phase transitions including DEPLOYMENT, SCOUT, ROLL OFF, etc. Slides in from top, holds, slides out with gothic-themed styling.

### 2. Unit Placement Animation
**Issue**: When a model is placed, it appears instantly via `_spawn_preview_token()`.

**Recommendation**: Add a brief drop-in animation (scale from 0 to 1 or fade-in over 0.2s) when a model is placed. This gives tactile feedback and makes the deployment feel more deliberate.

### 3. Player Turn Indicator Enhancement
**Issue**: Active player is shown as a text badge. In multiplayer, it can be easy to miss whose turn it is.

**Recommendation**:
- Add a prominent colored border around the screen edge matching the active player's color (blue/red)
- Flash the border briefly when turns swap
- Add an audio cue (optional) when it becomes your turn

### 4. Deployment Zone Theming
**Issue**: Zones are flat color overlays.

**Recommendation**: Add subtle deployment-themed textures or patterns within the zones (e.g., diagonal hatching, military-style markers).

### 5. Ghost Visual Enhancement
**Issue**: Ghost previews are functional but basic.

**Recommendation**:
- Add a subtle pulsing effect to the ghost to draw attention
- Show a connecting line from the ghost to the nearest placed model (helps with coherency)
- Display the distance from the ghost to the nearest friendly model in inches (see QoL #11)

### 6. Coherency Visualization
**Issue**: Coherency is only communicated via a text warning and a toast.

**Recommendation**: Draw faint 2" radius circles around placed models (coherency range). Color them green when the next model would be in coherency range, red when it would be out of range.

### 7. Token Visual Improvement — Unit Name Labels
**Issue**: Deployed model tokens show colored circles with a model number, but no unit name.

**Recommendation**: Add a small unit name label that appears on hover over a deployed token, or show the unit name as a tiny label beneath each token cluster.

### 8. Opponent Deployment Zone Dimming
**Issue**: During your deployment turn, the opponent's deployment zone looks the same as yours.

**Recommendation**: Dim or desaturate the opponent's deployment zone when it's your turn. The opponent zone pulsing during "waiting" state is already implemented, but active dimming during the player's own turn is not.

---

## Multiplayer-Specific Issues

### 1. `ATTACH_CHARACTER_DEPLOYMENT` Not in DETERMINISTIC_ACTIONS — RESOLVED
**Status**: **Fixed.**

### 2. Disconnect Handling During Deployment
**Issue**: `NetworkManager._on_peer_disconnected()` calls `get_tree().quit()` on any disconnect. This is overly aggressive for the deployment phase.

**Recommendation**: Show a reconnection dialog instead. Allow a grace period for the opponent to reconnect. If they don't reconnect, offer the option to save the game state or continue in single-player mode.

### 3. SWITCH_PLAYER Action Validation Gap — RESOLVED
**Status**: **Fixed.**

### 4. Race Condition: Embark/Attach Actions After Player Switch
**Issue**: The deployment action triggers a player switch before embark/attach actions arrive in multiplayer. Current mitigation checks `transport.owner` instead of `active_player`, which is correct but fragile.

**Recommendation**: Add a comment documenting this design decision. Consider batching the deploy + embark/attach into a single composite action for atomicity.

### 5. Turn Timer UI During Deployment — IMPLEMENTED
**Status**: **Implemented.** Turn timer countdown is shown in the HUD bar via `_on_turn_timer_warning()` connected to `NetworkManager.turn_timer_warning`. The "waiting for opponent" overlay also includes a live countdown.

### 6. Game Over on Timeout is Too Punitive
**Issue**: When turn timeout fires, the other player immediately wins. During deployment — where players are carefully arranging many models — 90 seconds may not be enough for large armies.

**Recommendation**: Consider (a) longer timeout during deployment specifically, (b) warnings at 60s and 30s remaining, or (c) auto-placing remaining units rather than ending the game.

### 7. Web Relay Deployment State Sync
**Issue**: In web relay mode, the initial state is sent after a 0.5-second delay. Guest may briefly see default army configuration.

**Recommendation**: Add a "Waiting for game state..." loading screen on the guest side.

---

## Code Quality Observations

### 1. Duplicate Geometry Functions
**Issue**: Both `DeploymentPhase.gd` and `DeploymentController.gd` contain their own implementations of `_circle_wholly_in_polygon()`, `_point_to_line_distance()`, and `_shape_wholly_in_polygon()`.

**Recommendation**: Consolidate into `Measurement.gd`.

### 2. `_all_units_deployed()` Uses Direct GameState Access
**Issue**: `DeploymentPhase._all_units_deployed()` accesses `GameState.state` directly bypassing the snapshot architecture.

**Recommendation**: Refresh the snapshot in `_process_deploy_unit()` after applying changes.

---

## Summary Priority Matrix

| Issue | Priority | Effort | Category | Status |
|-------|----------|--------|----------|--------|
| On-screen toast notifications | **High** | Low | QoL | **DONE** |
| Coherency enforcement (not just warning) | **High** | Low | Rules | **DONE** |
| `ATTACH_CHARACTER_DEPLOYMENT` optimistic exec | **High** | Low | Multiplayer | **DONE** |
| Deployment progress indicator | **Medium** | Low | QoL | **DONE** |
| Pre-battle formation declarations | **High** | Medium | Rules | **DONE** |
| Strategic Reserves | **High** | High | Rules | **DONE** |
| Deep Strike | **High** | High | Rules | **DONE** |
| SWITCH_PLAYER validation gap | **High** | Low | Multiplayer | **DONE** |
| Turn timer UI for multiplayer | **High** | Low | Multiplayer | **DONE** |
| Determine First Turn roll-off | **Medium** | Medium | Rules | **DONE** |
| Infiltrators | **Medium** | Medium | Rules | **DONE** |
| Scout Moves | **Medium** | Medium | Rules | **DONE** |
| Auto-zoom to deployment zone | **Medium** | Low | QoL | **DONE** |
| Deployment summary before ending | **Medium** | Low | QoL | **DONE** |
| Unit base preview on hover | **Medium** | Low | QoL | **DONE** |
| Deployment zone edge highlighting | **Low** | Low | Visual | **DONE** |
| Phase transition animation | **Low** | Low | Visual | **DONE** |
| Deployment map variety | **Low** | Medium | Rules | **DONE** |
| Fortification deployment | **Low** | Low | Rules | **DONE** |
| Reserves cap fixed (25% → 50% points + 50% units) | **High** | Low | Rules | **DONE** |
| Reserves destroyed after Round 3 | **Medium** | Low | Rules | **DONE** |
| TITANIC deployment skip | **Low** | Low | Rules | Open |
| Per-model undo | **Medium** | Low | QoL | Open |
| Coherency distance display | **Medium** | Low | QoL | Open |
| Measuring tool accessibility | **Low** | Low | QoL | Open |
| Opponent deployment notifications (MP) | **Medium** | Medium | QoL/MP | Open |
| Keyboard shortcut reference | **Low** | Low | QoL | Open |
| Player turn screen-edge indicator | **Medium** | Low | Visual | Open |
| Unit placement animation | **Low** | Low | Visual | Open |
| Coherency visualization circles | **Low** | Low | Visual | Open |
| Ghost visual enhancement | **Low** | Low | Visual | Open |
| Deployment zone theming | **Low** | Low | Visual | Open |
| Token unit name labels | **Low** | Low | Visual | Open |
| Opponent zone dimming | **Low** | Low | Visual | Open |
| Disconnect handling (graceful) | **Medium** | Medium | Multiplayer | Open |
| Web relay state sync loading screen | **Medium** | Low | Multiplayer | Open |
| Timeout too punitive during deployment | **Medium** | Low | Multiplayer | Open |
| Race condition: embark after player switch | **Medium** | Low | Multiplayer | Open |
| Duplicate geometry functions | **Low** | Low | Code Quality | Open |
| Snapshot staleness in `_all_units_deployed()` | **Low** | Low | Code Quality | Open |
| Mission selection | **Low** | High | Rules | Open |

---

## Audit Revision History

| Date | Changes |
|------|---------|
| Initial | First audit: core rules comparison, QoL recommendations, visual improvements, multiplayer issues |
| Update 1 | Coherency enforcement, toast notifications, `ATTACH_CHARACTER_DEPLOYMENT` optimistic exec marked DONE |
| Update 2 | Deployment progress indicator marked DONE. Added: SWITCH_PLAYER validation detail, race condition analysis, turn timer UI gap, web relay sync issue, game-over timeout concern, duplicate geometry observation, snapshot staleness observation, Fortification deployment gap, coherency distance display, keyboard shortcut reference, token unit name labels, opponent zone dimming. |
| Update 3 | **Strategic Reserves + Deep Strike marked DONE.** Full multiplayer sync support. |
| Update 4 | **Infiltrators marked DONE.** Full server-side and client-side validation. |
| Update 5 | **Major revision.** Marked newly-implemented items as DONE: Scout Moves (`ScoutPhase.gd`), Roll-Off Phase (`RollOffPhase.gd`), Formations Phase (`FormationsPhase.gd`), Auto-Zoom, Phase Transition Banner, Deployment Summary Dialog, Unit Base Hover Tooltip, Turn Timer UI. Added new gaps: TITANIC deployment skip (not implemented), Reserves cap incorrect (25% → should be 50% per CA 2025-26), Reserves not destroyed after Round 3. Removed outdated recommendations section. Cleaned up resolved items. |

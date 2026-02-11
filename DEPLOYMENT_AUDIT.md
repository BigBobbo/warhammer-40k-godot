# Deployment Phase Audit Report

## Overview

This audit compares the current deployment phase implementation against the official Warhammer 40,000 10th Edition core rules. The focus is on the online multiplayer experience.

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
- Optimistic execution for `DEPLOY_UNIT` and `EMBARK_UNITS_DEPLOYMENT` actions (`NetworkManager.gd:42-58`)
- Turn-based input blocking prevents deploying when it's not your turn (`DeploymentController.gd:52-53`)
- Host validates all actions before broadcasting to clients

### UI & Interaction
- Formation modes (SINGLE, SPREAD, TIGHT) with ghost previews
- Rotation controls (Q/E keys, mouse wheel) for non-circular bases
- Model repositioning via Shift+click
- Unit coherency warnings (non-blocking)

---

## Missing Rules (Compared to 10th Edition)

### 1. Pre-Battle Sequence — Declare Battle Formations
**Rule**: Before deployment, each player must secretly write down:
- Which Leaders are attached to which Bodyguard units
- Which units start embarked in Transports
- Which units are placed in Strategic Reserves

Then both players simultaneously reveal their choices.

**Current Implementation**: Characters and transports are resolved *during* deployment via dialogs that pop up after placing a unit. There is no pre-deployment declaration step. This means a player can see what the opponent deploys before deciding whether to attach a leader or embark units.

**Impact**: Medium — changes the strategic depth of deployment decisions. In online multiplayer, this matters because seeing the opponent's placement before declaring formations is a meaningful advantage.

**Recommendation**: Add a "Declare Battle Formations" step before the deployment loop begins. Each player selects leader attachments, transport embarkations, and reserves declarations on a configuration screen, then both are locked in before any models hit the table.

### 2. Strategic Reserves
**Rule**: Up to 25% of total army points can be placed in Strategic Reserves (off-table). These units arrive from Turn 2 onwards:
- Turn 2: Within 6" of any battlefield edge, not in opponent's deployment zone
- Turn 3+: Within 6" of any battlefield edge (including opponent's deployment zone)
- Must be >9" from enemy models
- Units not arriving by end of game count as destroyed

**Current Implementation**: Not implemented. All units must be deployed on the table during deployment.

**Impact**: High — Strategic Reserves are a core mechanic that many army lists rely on. Without them, certain units (especially glass cannons, flanking units) lose their intended playstyle.

**Recommendation**: Add a reserves declaration step in the pre-battle sequence. Track reserved units in `GameState` with a new status (e.g., `UnitStatus.IN_RESERVES`). During the Movement phase's Reinforcements step, allow placing reserve units within the rules above.

### 3. Deep Strike
**Rule**: Units with the Deep Strike ability can be placed in Reserves during the Declare Battle Formations step. During the Reinforcements step of a Movement phase, they can be set up anywhere on the battlefield >9" from all enemy models.

**Current Implementation**: Not implemented. Referenced as out-of-scope in `INITIAL.md`.

**Impact**: High — Deep Strike is one of the most common and impactful deployment abilities in 40k. Many datasheets rely on it.

**Recommendation**: Implement alongside Strategic Reserves. Units with `DEEP_STRIKE` keyword should have an option during battle formation declarations to go into reserves. Their placement during reinforcements follows different zone rules than Strategic Reserves (anywhere on the board vs. edge-only).

### 4. Infiltrators
**Rule**: If every model in a unit has the Infiltrators ability, the unit can be set up anywhere on the battlefield that is >9" from the enemy deployment zone and >9" from all enemy models.

**Current Implementation**: Not implemented.

**Impact**: Medium-High — Infiltrators change the deployment dynamic significantly. Units like Nurglings, Lictors, and many forward-deploy units depend on this.

**Recommendation**: During deployment, if a unit has the `INFILTRATORS` keyword, allow placement anywhere outside the 9" exclusion zones rather than restricting to the player's deployment zone. This should be relatively straightforward — modify `_validate_model_position()` in `DeploymentPhase.gd` to use a different zone polygon for infiltrating units.

### 5. Scout Moves
**Rule**: After deployment is complete but before the first battle round, units with `Scout X"` can make a Normal Move of up to X inches, ending >9" from enemy models. The player who takes the first turn moves their Scout units first. Dedicated Transports inherit Scout if all embarked models have it.

**Current Implementation**: Not implemented.

**Impact**: Medium — Scout moves create an important pre-game tactical layer. Many lists depend on early board control through Scout moves.

**Recommendation**: Add a "Scout Moves" sub-phase between deployment and the first Command phase. Units with the Scout keyword get a mini-movement phase with their designated range.

### 6. Determine First Turn / Attacker-Defender Roll-Off
**Rule**: After deployment, players roll off. The winner decides who takes the first turn. The player who goes first is the Attacker; the other is the Defender.

**Current Implementation**: Player 1 always starts and is hardcoded as the Defender (`TurnManager._handle_deployment_phase_start()` at `40k/autoloads/TurnManager.gd:104`). There is no roll-off mechanic.

**Impact**: Medium — Going first vs second is a major strategic decision in 40k. In competitive play, the roll-off and choice can decide games.

**Recommendation**: After deployment ends, present a roll-off UI (animated dice roll). The winner is prompted to choose first or second turn. This affects who gets Scout moves first and the Attacker/Defender designation.

### 7. Deployment Map Variety
**Rule**: 10th Edition uses multiple deployment maps (Dawn of War, Hammer and Anvil, Search and Destroy, Crucible of Battle, etc.) depending on the mission.

**Current Implementation**: Only Dawn of War is implemented. Zones are hardcoded in `GameState._get_dawn_of_war_zone_1_coords()` (`40k/autoloads/GameState.gd:204-218`).
- Player 1: `(0,0)` to `(44,12)` (12" deep strip)
- Player 2: `(0,48)` to `(44,60)` (12" deep strip)

**Impact**: Medium — Different deployment maps create variety and affect list building. Playing Dawn of War every game gets repetitive.

**Recommendation**: Add at least the core deployment maps:
- **Hammer and Anvil**: Zones on the short edges (24" deep on a 44"-wide board)
- **Search and Destroy**: Diagonal quarters
- **Crucible of Battle**: L-shaped zones

Store deployment map data as configuration rather than hardcoded coordinates.

### 8. Mission Selection
**Rule**: 10th Edition has multiple mission types with different primary objectives and deployment configurations.

**Current Implementation**: Only "Take and Hold" with 5 static objectives (`MissionManager.gd`).

**Impact**: Low-Medium for deployment specifically, but high for overall game replayability.

---

## Coherency Enforcement Gap

**Rule**: Units MUST be set up in unit coherency. For 2-6 model units, every model must be within 2" of at least one other model. For 7+ model units, every model must be within 2" of at least two other models.

**Current Implementation**: Coherency is checked and a yellow warning toast is shown (`DeploymentController._check_coherency_warning()` at `40k/scripts/DeploymentController.gd:838`), but placement is **not blocked**. A player can confirm a deployment that violates coherency.

**Impact**: Medium — Allowing incoherent deployments is technically a rules violation. In competitive play this should be enforced.

**Recommendation**: Make coherency a hard requirement for confirming deployment. Move the check into the `confirm()` method and block confirmation if coherency is violated. Keep the real-time warning for feedback during placement.

---

## Quality of Life Improvements

### 1. On-Screen Toast Notifications (Currently Console-Only)
**Issue**: `_show_toast()` in `DeploymentController.gd:1029` only prints to the console. Players get no visual feedback when placement fails.

**Recommendation**: Implement an on-screen toast notification system. Display error messages (red) and warnings (yellow) as temporary floating labels near the cursor or at the top of the screen. This is critical for multiplayer where players can't see the console.

### 2. Deployment Progress Indicator
**Issue**: There's no clear indicator showing how many units each player has left to deploy.

**Recommendation**: Add a deployment progress bar or counter to the HUD, e.g., "Player 1: 3/7 units deployed | Player 2: 2/5 units deployed". This helps both players understand the deployment tempo.

### 3. "Waiting for Opponent" State in Multiplayer
**Issue**: When it's the opponent's turn to deploy in multiplayer, the local player has limited feedback about what's happening.

**Recommendation**: Show a prominent "Waiting for [Opponent Faction] to deploy..." overlay. Optionally, show a subtle animation on the opponent's deployment zone to indicate activity. Consider showing a timer or activity indicator.

### 4. Undo Last Model Placement
**Issue**: The current undo (`DeploymentController.undo()` at line 314) resets the entire unit — all placed models are cleared. There's no way to undo just the last model placement.

**Recommendation**: Add a per-model undo (e.g., pressing `Ctrl+Z` removes only the most recently placed model). Keep the full-unit reset as a separate "Reset" button.

### 5. Auto-Zoom to Deployment Zone
**Issue**: The camera starts zoomed out to show the full 44"×60" board (`view_zoom = 0.3` in `Main.gd:97`). Players must manually zoom into their deployment zone.

**Recommendation**: When a player's turn begins, auto-zoom and pan the camera to center on their deployment zone. Add a quick-nav button "Go to My Zone" for manual reset. During the opponent's turn, optionally show their zone.

### 6. Deployment Zone Edge Highlighting
**Issue**: Deployment zones are 15% alpha solid fills with a white border only when "active." It can be hard to tell exactly where the zone boundary is.

**Recommendation**:
- Add a dashed or animated border to the active deployment zone (pulsing glow)
- Show distance markers (e.g., "12 inches" label) on the zone boundary
- Highlight the no-man's-land between zones to make the layout clearer
- Consider a subtle grid overlay within the deployment zone to help with spacing

### 7. Unit Base Preview on Hover
**Issue**: When hovering over the unit list before selecting a unit to deploy, there's no preview of the unit's base size or model count.

**Recommendation**: When hovering over a unit in the list, show a tooltip or inline preview showing base size, model count, and any special deployment rules (e.g., "Transport — 12 capacity", "CHARACTER — can attach to Bodyguard").

### 8. Deployment Summary Before Ending Phase
**Issue**: Clicking "End Deployment" immediately transitions to the Command phase. There's no confirmation or summary.

**Recommendation**: Show a deployment summary dialog before ending the phase:
- List all deployed units with positions
- Show any units in transports
- Show attached characters
- Flag any potential issues (coherency warnings, etc.)
- Require explicit confirmation ("Confirm and Start Game" / "Go Back")

### 9. Measuring Tool During Deployment
**Issue**: While a measuring tape tool exists in the codebase, its availability and usefulness during deployment is unclear.

**Recommendation**: Ensure the measuring tape is easily accessible during deployment (keyboard shortcut or always-visible button). Players need to measure distances for coherency, spacing, and planning engagement ranges.

### 10. Replay/History of Opponent's Deployment
**Issue**: In multiplayer, when the opponent deploys a unit, the local player may miss it if they were looking elsewhere on the board.

**Recommendation**: When the opponent deploys a unit:
- Briefly pan the camera to show where the unit was placed
- Show a notification: "[Unit Name] deployed at [zone area]"
- Add a deployment log panel showing the order of all deployments

---

## Visual Improvements

### 1. Deployment Phase Transition Animation
**Issue**: Phase transitions are instant with no visual feedback.

**Recommendation**: Add a brief phase banner animation (e.g., "DEPLOYMENT PHASE" text sweeping across the screen, similar to the tabletop game's phase markers).

### 2. Unit Placement Animation
**Issue**: When a model is placed, it appears instantly.

**Recommendation**: Add a brief drop-in animation (scale from 0 to 1 or fade-in over 0.2s) when a model is placed. This gives tactile feedback and makes the deployment feel more deliberate.

### 3. Player Turn Indicator Enhancement
**Issue**: Active player is shown as a text badge. In the heat of multiplayer, it can be easy to miss whose turn it is.

**Recommendation**:
- Add a prominent colored border around the screen edge matching the active player's color (blue/red)
- Flash the border briefly when turns swap
- Add an audio cue (optional) when it becomes your turn

### 4. Deployment Zone Theming
**Issue**: Zones are flat color overlays.

**Recommendation**: Add subtle deployment-themed textures or patterns within the zones (e.g., diagonal hatching, military-style markers). This helps distinguish deployment zones from the regular board while feeling thematic.

### 5. Ghost Visual Enhancement
**Issue**: Ghost previews are functional but basic.

**Recommendation**:
- Add a subtle pulsing effect to the ghost to draw attention
- Show a connecting line from the ghost to the nearest placed model (helps with coherency)
- Display the distance from the ghost to the nearest friendly model in inches

### 6. Coherency Visualization
**Issue**: Coherency is only communicated via a text warning.

**Recommendation**: Draw faint 2" radius circles around placed models (coherency range). Color them green when the next model would be in coherency range, red when it would be out of range. This gives intuitive visual feedback about valid placement areas.

---

## Multiplayer-Specific Issues

### 1. `ATTACH_CHARACTER_DEPLOYMENT` Not in DETERMINISTIC_ACTIONS
**Issue**: In `NetworkManager.gd:42-58`, `ATTACH_CHARACTER_DEPLOYMENT` is NOT listed in the `DETERMINISTIC_ACTIONS` array, while `EMBARK_UNITS_DEPLOYMENT` IS listed. This means character attachment doesn't benefit from optimistic execution in multiplayer — there will be a round-trip delay before the attachment is visually confirmed on the client.

**Recommendation**: Add `"ATTACH_CHARACTER_DEPLOYMENT"` to the `DETERMINISTIC_ACTIONS` array. Character attachment is deterministic (no dice rolls).

### 2. Disconnect Handling During Deployment
**Issue**: `NetworkManager._on_peer_disconnected()` (line 1412-1422) calls `get_tree().quit()` on any disconnect. This is overly aggressive for the deployment phase.

**Recommendation**: Show a reconnection dialog instead. Allow a grace period for the opponent to reconnect. If they don't reconnect, offer the option to save the game state or continue in single-player mode.

### 3. SWITCH_PLAYER Action Validation Gap
**Issue**: `_validate_switch_player_action()` in `DeploymentPhase.gd:151` only checks if the current player has undeployed units. It does NOT verify that the `new_player` field in the action is valid (e.g., that it's the correct next player).

**Recommendation**: Validate that `action.new_player` is `3 - current_player` (i.e., the expected next player).

---

## Summary Priority Matrix

| Issue | Priority | Effort | Category |
|-------|----------|--------|----------|
| On-screen toast notifications | **High** | Low | QoL |
| Coherency enforcement (not just warning) | **High** | Low | Rules |
| Pre-battle formation declarations | **High** | Medium | Rules |
| Strategic Reserves | **High** | High | Rules |
| Deep Strike | **High** | High | Rules |
| `ATTACH_CHARACTER_DEPLOYMENT` optimistic exec | **High** | Low | Multiplayer |
| Deployment progress indicator | **Medium** | Low | QoL |
| Determine First Turn roll-off | **Medium** | Medium | Rules |
| Infiltrators | **Medium** | Medium | Rules |
| Auto-zoom to deployment zone | **Medium** | Low | QoL |
| Per-model undo | **Medium** | Low | QoL |
| Deployment summary before ending | **Medium** | Low | QoL |
| Player turn screen-edge indicator | **Medium** | Low | Visual |
| Scout Moves | **Medium** | Medium | Rules |
| Opponent deployment notifications | **Medium** | Medium | QoL/MP |
| Disconnect handling (graceful) | **Medium** | Medium | Multiplayer |
| Deployment map variety | **Low** | Medium | Rules |
| Phase transition animation | **Low** | Low | Visual |
| Unit placement animation | **Low** | Low | Visual |
| Coherency visualization circles | **Low** | Low | Visual |
| Zone edge highlighting | **Low** | Low | Visual |
| Mission selection | **Low** | High | Rules |

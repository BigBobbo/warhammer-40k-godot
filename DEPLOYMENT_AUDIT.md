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

### 1. Pre-Battle Sequence — Declare Battle Formations
**Rule**: Before deployment, each player must secretly write down:
- Which Leaders are attached to which Bodyguard units
- Which units start embarked in Transports
- Which units are placed in Strategic Reserves

Then both players simultaneously reveal their choices.

**Current Implementation**: Characters and transports are resolved *during* deployment via dialogs that pop up after placing a unit. There is no pre-deployment declaration step. This means a player can see what the opponent deploys before deciding whether to attach a leader or embark units.

**Impact**: Medium — changes the strategic depth of deployment decisions. In online multiplayer, this matters because seeing the opponent's placement before declaring formations is a meaningful advantage.

**Recommendation**: Add a "Declare Battle Formations" step before the deployment loop begins. Each player selects leader attachments, transport embarkations, and reserves declarations on a configuration screen, then both are locked in before any models hit the table.

### 2. Strategic Reserves — IMPLEMENTED
**Rule**: Up to 25% of total army points can be placed in Strategic Reserves (off-table). These units arrive from Turn 2 onwards:
- Turn 2: Within 6" of any battlefield edge, not in opponent's deployment zone
- Turn 3+: Within 6" of any battlefield edge (including opponent's deployment zone)
- Must be >9" from enemy models
- Units not arriving by end of game count as destroyed

**Status**: **Implemented.** `UnitStatus.IN_RESERVES` added to `GameState.gd:8`. During deployment, any unit can be placed into Strategic Reserves via the "Strategic Reserves" button in the right panel (`Main.gd`). Validation enforces the 25% army point cap (`DeploymentPhase._validate_place_in_reserves()`). The `PLACE_IN_RESERVES` action is routed through `NetworkIntegration` for multiplayer sync. During the Movement phase (Turn 2+), reserve units appear in the unit list with `[SR]` tags and can be placed on the battlefield via `PLACE_REINFORCEMENT` action. Placement validation enforces: >9" from enemies, within 6" of board edge, and no opponent deployment zone on Turn 2 (`MovementPhase._validate_place_reinforcement()`). Deployment progress indicator shows reserve counts. All units deployed or in reserves triggers deployment completion.

### 3. Deep Strike — IMPLEMENTED
**Rule**: Units with the Deep Strike ability can be placed in Reserves during the Declare Battle Formations step. During the Reinforcements step of a Movement phase, they can be set up anywhere on the battlefield >9" from all enemy models.

**Status**: **Implemented.** Units with the Deep Strike ability (detected via `GameState.unit_has_deep_strike()`) show `[DS]` tags in the deployment unit list and have a "Deep Strike (Reserves)" button. The `PLACE_IN_RESERVES` action tracks `reserve_type: "deep_strike"` vs `"strategic_reserves"`. During Movement phase reinforcements, Deep Strike units can be placed anywhere on the board >9" from enemies (no board-edge restriction). The deployment controller enters `is_reinforcement_mode` with ghost validation showing valid/invalid placement based on enemy proximity. Army data already defines Deep Strike as an ability (e.g., `adeptus_custodes.json`) and is read by `GameState.unit_has_deep_strike()`.

### 4. Infiltrators
**Rule**: If every model in a unit has the Infiltrators ability, the unit can be set up anywhere on the battlefield that is >9" from the enemy deployment zone and >9" from all enemy models.

**Current Implementation**: Not implemented. No code searches or acts on an `INFILTRATORS` keyword or ability.

**Impact**: Medium-High — Infiltrators change the deployment dynamic significantly. Units like Nurglings, Lictors, and many forward-deploy units depend on this.

**Recommendation**: During deployment, if a unit has the `INFILTRATORS` keyword, allow placement anywhere outside the 9" exclusion zones rather than restricting to the player's deployment zone. This should be relatively straightforward — modify `_validate_model_position()` in `DeploymentPhase.gd` to use a different zone polygon for infiltrating units.

### 5. Scout Moves
**Rule**: After deployment is complete but before the first battle round, units with `Scout X"` can make a Normal Move of up to X inches, ending >9" from enemy models. The player who takes the first turn moves their Scout units first. Dedicated Transports inherit Scout if all embarked models have it.

**Current Implementation**: Not implemented. No code references Scout moves anywhere in the phases or controllers.

**Impact**: Medium — Scout moves create an important pre-game tactical layer. Many lists depend on early board control through Scout moves.

**Recommendation**: Add a "Scout Moves" sub-phase between deployment and the first Command phase. Units with the Scout keyword get a mini-movement phase with their designated range.

### 6. Determine First Turn / Attacker-Defender Roll-Off
**Rule**: After deployment, players roll off. The winner decides who takes the first turn. The player who goes first is the Attacker; the other is the Defender.

**Current Implementation**: Player 1 always starts and is hardcoded as the Defender (`TurnManager._handle_deployment_phase_start()` at `40k/autoloads/TurnManager.gd:104`). There is no roll-off mechanic. The deployment progress indicator labels already reference "Defender" and "Attacker" (`Main.gd:217,235`), but these are static strings, not computed from a roll-off result.

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

### 9. Fortification Deployment
**Rule**: Fortification units are set up in your deployment zone during the Declare Battle Formations step. They cannot be placed in reserves and have specific placement rules (must be wholly within deployment zone, cannot overlap other terrain or units).

**Current Implementation**: Not implemented. No fortification-specific handling exists.

**Impact**: Low — Fortifications are relatively niche in competitive play.

**Recommendation**: Low priority, but if fortification datasheets are added to army lists, add placement validation that enforces their specific rules (cannot reserve, must be on table).

---

## Coherency Enforcement Gap — RESOLVED

**Rule**: Units MUST be set up in unit coherency. For 2-6 model units, every model must be within 2" of at least one other model. For 7+ model units, every model must be within 2" of at least two other models.

**Status**: **Fixed.** `_is_unit_coherent()` (`DeploymentController.gd:900`) now performs a hard check at the top of `confirm()`. Deployment is blocked with a red error toast if coherency is violated. The real-time yellow warning during placement is preserved for feedback.

---

## Quality of Life Improvements

### 1. On-Screen Toast Notifications — RESOLVED
**Status**: **Fixed.** `ToastManager` autoload (`40k/autoloads/ToastManager.gd`) provides a global on-screen toast system with error (red), warning (yellow), success (green), and info (white) variants. `DeploymentController._show_toast()` and `Main.gd` both route through `ToastManager`. Styled as dark panels with colored borders, fade-in/fade-out animations, max 5 stacked toasts.

### 2. Deployment Progress Indicator — RESOLVED
**Status**: **Fixed.** `Main._setup_deployment_progress_indicator()` (`40k/scripts/Main.gd:182`) creates a styled progress bar panel showing "Player 1 (Defender): X/Y units deployed" and "Player 2 (Attacker): X/Y units deployed". Uses `WhiteDwarfTheme` styling with player-colored progress bars. Updates via `_update_deployment_progress()` which reads `GameState.get_deployment_progress()`. Visible only during the deployment phase (`Main.gd:3097-3100`).

### 3. "Waiting for Opponent" State in Multiplayer
**Issue**: When it's the opponent's turn to deploy in multiplayer, the local player sees "Waiting for Player X to deploy..." in the unit list (`Main.gd:1784`), but this is a passive text item in the right panel. There is no prominent overlay or activity indicator.

**Recommendation**: Show a prominent "Waiting for [Opponent Faction] to deploy..." overlay or banner. Optionally, show a subtle animation on the opponent's deployment zone to indicate activity. Consider showing a timer or activity indicator tied to the 90-second turn timeout (`NetworkManager.TURN_TIMEOUT_SECONDS = 90.0`).

### 4. Undo Last Model Placement
**Issue**: The current undo (`DeploymentController.undo()` at line 315) resets the entire unit — all placed models are cleared and `temp_positions` is refilled with `null`. There's no way to undo just the last model placement.

**Recommendation**: Add a per-model undo (e.g., pressing `Ctrl+Z` removes only the most recently placed model by decrementing `model_idx` and clearing the last entry in `temp_positions`). Keep the full-unit reset as a separate "Reset" button.

### 5. Auto-Zoom to Deployment Zone
**Issue**: The camera starts zoomed out to show the full 44"x60" board (`view_zoom = 0.3` in `Main.gd:105`). Players must manually zoom into their deployment zone.

**Recommendation**: When a player's turn begins, auto-zoom and pan the camera to center on their deployment zone. Add a quick-nav button "Go to My Zone" for manual reset. During the opponent's turn, optionally show their zone. The `Main.gd:125` comment references camera controls (WASD/arrows, +/-, F to focus on P2 zone) but no auto-zoom on turn change exists.

### 6. Deployment Zone Edge Highlighting
**Issue**: Deployment zones are 15% alpha solid fills with a white border only when "active." It can be hard to tell exactly where the zone boundary is.

**Recommendation**:
- Add a dashed or animated border to the active deployment zone (pulsing glow)
- Show distance markers (e.g., "12 inches" label) on the zone boundary
- Highlight the no-man's-land between zones to make the layout clearer
- Consider a subtle grid overlay within the deployment zone to help with spacing

### 7. Unit Base Preview on Hover
**Issue**: When hovering over the unit list before selecting a unit to deploy, there's no preview of the unit's base size or model count. The unit list shows `"[Name] ([N] models)"` but no base size or special rules.

**Recommendation**: When hovering over a unit in the list, show a tooltip or inline preview showing base size, model count, and any special deployment rules (e.g., "Transport — 12 capacity", "CHARACTER — can attach to Bodyguard", "Deep Strike available").

### 8. Deployment Summary Before Ending Phase
**Issue**: Clicking "End Deployment" (`Main._on_end_deployment_pressed()` at `Main.gd:2194`) immediately routes an `END_DEPLOYMENT` action through `NetworkIntegration.route_action()` which transitions directly to the Command phase. There's no confirmation or summary screen.

**Recommendation**: Show a deployment summary dialog before ending the phase:
- List all deployed units with positions
- Show any units in transports
- Show attached characters
- Flag any potential issues (coherency warnings, etc.)
- Require explicit confirmation ("Confirm and Start Game" / "Go Back")

### 9. Measuring Tool During Deployment
**Issue**: A measuring tape tool exists (`MeasuringTapeManager` at `40k/autoloads/MeasuringTapeManager.gd`) with proper distance calculation via `Measurement.distance_inches()`. However, there is no visible button or clear keybind to activate it during deployment specifically.

**Recommendation**: Ensure the measuring tape is easily accessible during deployment (visible button or tooltip showing the keybind). Players need to measure distances for coherency, spacing, and planning engagement ranges.

### 10. Replay/History of Opponent's Deployment
**Issue**: In multiplayer, when the opponent deploys a unit, the local player may miss it if they were looking elsewhere on the board. There is no camera pan or notification on opponent deployment.

**Recommendation**: When the opponent deploys a unit:
- Briefly pan the camera to show where the unit was placed
- Show a notification: "[Unit Name] deployed at [zone area]"
- Add a deployment log panel showing the order of all deployments

### 11. Coherency Distance Display During Placement
**Issue**: The coherency check (`DeploymentController._check_coherency_warning()` at line 846) uses `Measurement.model_to_model_distance_inches()` for edge-to-edge distances, but this distance is never shown to the player during placement. When placing a model near the 2" coherency boundary, the player has to guess.

**Recommendation**: Display the distance from the ghost model to the nearest placed model in real-time (e.g., a small floating label next to the ghost showing "1.8\"" in green or "2.3\"" in red). This would make coherency-valid placement intuitive rather than trial-and-error.

### 12. Keyboard Shortcut Reference During Deployment
**Issue**: Deployment has several keybinds (Q/E for rotation, Shift+click for repositioning, mouse wheel for rotation, formation mode presumably mapped somewhere) but there is no on-screen reference. New players or returning players have no way to discover these controls without reading code.

**Recommendation**: Show a small "Controls" panel or tooltip during deployment listing available shortcuts. Could be a toggleable overlay (e.g., press `?` to show/hide).

---

## Visual Improvements

### 1. Deployment Phase Transition Animation
**Issue**: Phase transitions are instant with no visual feedback.

**Recommendation**: Add a brief phase banner animation (e.g., "DEPLOYMENT PHASE" text sweeping across the screen, similar to the tabletop game's phase markers).

### 2. Unit Placement Animation
**Issue**: When a model is placed, it appears instantly via `_spawn_preview_token()` in `DeploymentController.gd:774`.

**Recommendation**: Add a brief drop-in animation (scale from 0 to 1 or fade-in over 0.2s) when a model is placed. This gives tactile feedback and makes the deployment feel more deliberate.

### 3. Player Turn Indicator Enhancement
**Issue**: Active player is shown as a text badge (`active_player_badge` Label in `Main.gd:15`). In the heat of multiplayer, it can be easy to miss whose turn it is.

**Recommendation**:
- Add a prominent colored border around the screen edge matching the active player's color (blue/red)
- Flash the border briefly when turns swap
- Add an audio cue (optional) when it becomes your turn

### 4. Deployment Zone Theming
**Issue**: Zones are flat color overlays (Polygon2D nodes `P1Zone` and `P2Zone` in `Main.tscn`).

**Recommendation**: Add subtle deployment-themed textures or patterns within the zones (e.g., diagonal hatching, military-style markers). This helps distinguish deployment zones from the regular board while feeling thematic.

### 5. Ghost Visual Enhancement
**Issue**: Ghost previews are functional but basic (`GhostVisual.gd` creates a semi-transparent preview with validity coloring).

**Recommendation**:
- Add a subtle pulsing effect to the ghost to draw attention
- Show a connecting line from the ghost to the nearest placed model (helps with coherency)
- Display the distance from the ghost to the nearest friendly model in inches (see QoL #11)

### 6. Coherency Visualization
**Issue**: Coherency is only communicated via a text warning and a toast.

**Recommendation**: Draw faint 2" radius circles around placed models (coherency range). Color them green when the next model would be in coherency range, red when it would be out of range. This gives intuitive visual feedback about valid placement areas.

### 7. Token Visual Improvement — Unit Name Labels
**Issue**: Deployed model tokens (`TokenVisual.gd`) show colored circles with a model number, but no unit name. When multiple units of the same type are deployed, it's hard to tell which token belongs to which unit.

**Recommendation**: Add a small unit name label that appears on hover over a deployed token, or show the unit name as a tiny label beneath each token cluster. In multiplayer, this helps both players identify what's been deployed where.

### 8. Opponent Deployment Zone Dimming
**Issue**: During your deployment turn, the opponent's deployment zone looks the same as yours. There's no visual cue directing attention to your own zone.

**Recommendation**: Dim or desaturate the opponent's deployment zone when it's your turn. Brighten/highlight your own zone. Reverse when it's the opponent's turn. This creates a clear visual focus area.

---

## Multiplayer-Specific Issues

### 1. `ATTACH_CHARACTER_DEPLOYMENT` Not in DETERMINISTIC_ACTIONS — RESOLVED
**Status**: **Fixed.** `"ATTACH_CHARACTER_DEPLOYMENT"` added to `DETERMINISTIC_ACTIONS` in `NetworkManager.gd:47`. Character attachment now benefits from optimistic execution like `EMBARK_UNITS_DEPLOYMENT`.

### 2. Disconnect Handling During Deployment
**Issue**: `NetworkManager._on_peer_disconnected()` (`NetworkManager.gd:1485-1495`) calls `get_tree().quit()` on any disconnect. This is overly aggressive for the deployment phase.

**Recommendation**: Show a reconnection dialog instead. Allow a grace period for the opponent to reconnect. If they don't reconnect, offer the option to save the game state or continue in single-player mode. The `SaveLoadManager` autoload already supports saving game state, so this is feasible.

### 3. SWITCH_PLAYER Action Validation Gap — RESOLVED
**Status**: **Fixed.** `_validate_switch_player_action()` in `DeploymentPhase.gd:151` now validates that `action.new_player` matches the expected next player (`3 - current_player`). Invalid values are rejected with a descriptive error message.

### 4. Race Condition: Embark/Attach Actions After Player Switch
**Issue**: In `DeploymentController._complete_deployment()` (`DeploymentController.gd:431`), the deployment action is sent first, which triggers `TurnManager.check_deployment_alternation()` to switch the active player. Then embark/attach actions are sent. In multiplayer with network latency, the embark action may arrive *after* the turn has switched, potentially causing validation to fail because `_validate_embark_units_deployment()` checks against `transport_owner` rather than `active_player`.

**Current Mitigation**: The embark validation (`DeploymentPhase.gd:213`) already accounts for this by checking against `transport.get("owner", 0)` instead of the active player. However, the attach validation (`DeploymentPhase.gd:412`) similarly uses `bodyguard_owner`. This design is correct but fragile — any future refactor that adds active-player checks to these validators could break multiplayer.

**Recommendation**: Add a comment documenting this design decision. Consider batching the deploy + embark/attach into a single composite action for atomicity.

### 5. No Turn Timer UI During Deployment
**Issue**: `NetworkManager` has a 90-second turn timer (`TURN_TIMEOUT_SECONDS = 90.0` at `NetworkManager.gd:68`) that calls `_on_turn_timeout()` when expired, ending the game. However, there is no visible countdown for either player during deployment.

**Recommendation**: Display the turn timer in the HUD during multiplayer deployment. Show it prominently when time is running low (e.g., last 15 seconds turn red, optional pulse/flash). This prevents surprise game-overs and creates healthy time pressure.

### 6. Game Over on Timeout is Too Punitive
**Issue**: When `_on_turn_timeout()` fires (`NetworkManager.gd:1407-1415`), the other player immediately wins. During deployment — where players are carefully arranging many models — 90 seconds may not be enough for large armies, and an automatic loss is disproportionate.

**Recommendation**: Consider either (a) longer timeout during deployment specifically, (b) a warning at 60s and 30s remaining, or (c) auto-placing remaining units in a default formation rather than ending the game. At minimum, show a countdown so the player can act.

### 7. Web Relay Deployment State Sync
**Issue**: In web relay mode (`NetworkManager.web_relay_mode = true`), the initial state is sent after a 0.5-second delay (`Main.gd:98`). If the guest player loads faster than expected, they may briefly see the default army configuration before the host's state arrives.

**Recommendation**: Add a "Waiting for game state..." loading screen on the guest side that only dismisses once the host's initial state is received and applied.

---

## Code Quality Observations

### 1. Duplicate Geometry Functions
**Issue**: Both `DeploymentPhase.gd` and `DeploymentController.gd` contain their own implementations of `_circle_wholly_in_polygon()`, `_point_to_line_distance()`, and `_shape_wholly_in_polygon()`. These are nearly identical — the controller version adds debug prints (`DeploymentController.gd:948-1012`).

**Recommendation**: Consolidate into a single source of truth. Either delegate from the controller to the phase, or move these geometry utilities into `Measurement.gd` (which already handles distance calculations). This reduces maintenance burden and prevents subtle divergence.

### 2. Excessive Debug Logging
**Issue**: `DeploymentController.gd` has extensive `print()` statements throughout (e.g., lines 132-141 in `begin_deploy()`, lines 722-754 in `_create_ghost()`, lines 948-1011 in `_shape_wholly_in_polygon()`). These are useful during development but create substantial console noise in production, especially during multiplayer where both players generate logs.

**Note**: Per project instructions, debug logs should not be removed unless specifically asked. This observation is for awareness — the logs are not causing bugs but do impact readability of console output.

### 3. `_all_units_deployed()` Uses Direct GameState Access
**Issue**: `DeploymentPhase._all_units_deployed()` (`DeploymentPhase.gd:588`) accesses `GameState.state` directly with a comment saying "CRITICAL: Use GameState directly instead of game_state_snapshot — The snapshot may be stale." This bypasses the snapshot architecture that other methods use.

**Recommendation**: This is a pragmatic workaround for a real bug, but the root cause is that the phase's local snapshot isn't being updated after each action. Consider refreshing the snapshot in `_process_deploy_unit()` after applying changes, which would allow `_all_units_deployed()` to safely use the snapshot.

---

## Summary Priority Matrix

| Issue | Priority | Effort | Category | Status |
|-------|----------|--------|----------|--------|
| On-screen toast notifications | **High** | Low | QoL | **DONE** |
| Coherency enforcement (not just warning) | **High** | Low | Rules | **DONE** |
| `ATTACH_CHARACTER_DEPLOYMENT` optimistic exec | **High** | Low | Multiplayer | **DONE** |
| Deployment progress indicator | **Medium** | Low | QoL | **DONE** |
| Pre-battle formation declarations | **High** | Medium | Rules | Open |
| Strategic Reserves | **High** | High | Rules | **DONE** |
| Deep Strike | **High** | High | Rules | **DONE** |
| SWITCH_PLAYER validation gap | **High** | Low | Multiplayer | **DONE** |
| Turn timer UI for multiplayer | **High** | Low | Multiplayer | Open |
| Determine First Turn roll-off | **Medium** | Medium | Rules | Open |
| Infiltrators | **Medium** | Medium | Rules | Open |
| Auto-zoom to deployment zone | **Medium** | Low | QoL | Open |
| Per-model undo | **Medium** | Low | QoL | Open |
| Deployment summary before ending | **Medium** | Low | QoL | Open |
| Coherency distance display | **Medium** | Low | QoL | Open |
| Player turn screen-edge indicator | **Medium** | Low | Visual | Open |
| Scout Moves | **Medium** | Medium | Rules | Open |
| Opponent deployment notifications | **Medium** | Medium | QoL/MP | Open |
| Disconnect handling (graceful) | **Medium** | Medium | Multiplayer | Open |
| Web relay state sync loading screen | **Medium** | Low | Multiplayer | Open |
| Timeout too punitive during deployment | **Medium** | Low | Multiplayer | Open |
| Race condition: embark after player switch | **Medium** | Low | Multiplayer | Open |
| Keyboard shortcut reference | **Low** | Low | QoL | Open |
| Unit name labels on tokens | **Low** | Low | Visual | Open |
| Opponent zone dimming | **Low** | Low | Visual | Open |
| Deployment map variety | **Low** | Medium | Rules | Open |
| Phase transition animation | **Low** | Low | Visual | Open |
| Unit placement animation | **Low** | Low | Visual | Open |
| Coherency visualization circles | **Low** | Low | Visual | Open |
| Zone edge highlighting | **Low** | Low | Visual | Open |
| Duplicate geometry functions | **Low** | Low | Code Quality | Open |
| Mission selection | **Low** | High | Rules | Open |
| Fortification deployment | **Low** | Low | Rules | Open |
| Game over timeout too punitive | **Low** | Low | Multiplayer | Open |

---

## Recommended Next Items

### Immediate (Low Effort, High Value)

1. **SWITCH_PLAYER Validation Gap** — One-line fix in `DeploymentPhase._validate_switch_player_action()` to verify `action.new_player == 3 - current_player`. Prevents potential multiplayer exploits.

2. **Turn Timer UI** — Display the 90-second countdown during multiplayer deployment. The timer already exists in `NetworkManager`; this just needs a UI element wired to it. Prevents surprise game-overs.

### Short-Term (Medium Effort, High Value)

3. **Pre-Battle Formation Declarations** — This is the largest rules gap that affects competitive fairness. Implement a pre-deployment screen where both players simultaneously declare leader attachments, transport embarkations, and reserves.

4. **Determine First Turn Roll-Off** — Add a dice roll-off after deployment to determine who goes first. Ties into the Attacker/Defender designation already referenced in the deployment progress indicator labels.

### Medium-Term (High Effort, High Value)

5. **Strategic Reserves + Deep Strike** — **DONE.** Implemented `UnitStatus.IN_RESERVES`, `PLACE_IN_RESERVES` action during deployment, `PLACE_REINFORCEMENT` action during movement. Full multiplayer sync support. See items 2 and 3 above for details.

6. **Infiltrators** — Units with the Infiltrators ability should be deployable anywhere >9" from enemy deployment zone and >9" from enemies. Requires modifying `_validate_model_position()` in `DeploymentPhase.gd` to use the whole board (minus exclusion zones) instead of the deployment zone for infiltrating units.

---

## Audit Revision History

| Date | Changes |
|------|---------|
| Initial | First audit: core rules comparison, QoL recommendations, visual improvements, multiplayer issues |
| Update 1 | Coherency enforcement, toast notifications, `ATTACH_CHARACTER_DEPLOYMENT` optimistic exec marked DONE |
| Update 2 | Deployment progress indicator marked DONE. Added: SWITCH_PLAYER validation detail, race condition analysis, turn timer UI gap, web relay sync issue, game-over timeout concern, duplicate geometry observation, snapshot staleness observation, Fortification deployment gap, coherency distance display, keyboard shortcut reference, token unit name labels, opponent zone dimming. Updated code references to current line numbers. Revised priority matrix and recommended next items. |
| Update 3 | **Strategic Reserves + Deep Strike marked DONE.** Added `UnitStatus.IN_RESERVES` to GameState enum. Implemented `PLACE_IN_RESERVES` action in DeploymentPhase with 25% point cap validation. Implemented `PLACE_REINFORCEMENT` action in MovementPhase with >9" enemy distance, board-edge (SR) and anywhere (DS) placement validation. Added reserves UI: "Place in Reserves" / "Deep Strike (Reserves)" button during deployment, `[DS]`/`[SR]` tags in unit lists, reinforcements section in movement phase unit list. Updated deployment progress to show reserve counts. Added `is_reinforcement_mode` to DeploymentController for ghost validation. Added to NetworkManager DETERMINISTIC_ACTIONS and exempt_actions. Updated GameManager routing. Full multiplayer sync support. |

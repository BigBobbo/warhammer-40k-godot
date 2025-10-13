# PRP: Complete Multiplayer Phase 1 Integration - Connect Game Phases to NetworkManager

## Issue Reference
**GitHub Issue**: #89 (Continuation - Phase 1 Completion)
**Feature**: Complete multiplayer action synchronization by integrating game phases with NetworkManager
**Confidence Level**: 8/10
**Dependencies**: Issue #96 (Game start sync - COMPLETE), Issue #89 initial NetworkManager implementation (COMPLETE)

## Executive Summary

The NetworkManager infrastructure from Issue #89 is **implemented but not connected** to the game logic. Currently, when players take actions (deploy units, move models, shoot, etc.), these actions only affect their local GameState and are **NOT synchronized** across the network. This PRP completes Phase 1 by integrating the existing action flow with NetworkManager.

### Current State
✅ **NetworkManager exists** with full RPC infrastructure
✅ **Game phases use action pattern** (execute_action → process_action → apply_state_changes)
❌ **Actions are NOT routed through NetworkManager** (single-player only)

### Goal
Route all game actions through `NetworkManager.submit_action()` to enable multiplayer synchronization.

---

## Problem Statement

### Current Action Flow (Single-Player Only)
```
Controller → Phase.execute_action() → Phase.process_action() →
PhaseManager.apply_state_changes() → GameState.state modified (LOCAL ONLY)
```

**Example**: When host deploys a unit in `DeploymentController.gd:306`:
```gdscript
var result = phase_manager.current_phase_instance.execute_action(deployment_action)
```
This only updates the host's GameState. The client never sees it.

### Required Action Flow (Multiplayer)
```
Controller → NetworkManager.submit_action() →
[HOST] validate + GameManager.apply_action() + broadcast_result.rpc() →
[CLIENT] receives broadcast → GameManager.apply_result() → Both synchronized
```

---

## Root Cause Analysis

### Why Multiplayer Isn't Working

According to PRP v4 (lines 903-911), Phase 1 implementation checklist includes:
- ✅ Create NetworkManager.gd
- ✅ Implement connection methods
- ✅ Implement submit_action() routing
- ✅ Implement RPC methods
- ✅ Create lobby UI
- ❌ **MISSING: "Route game actions through NetworkManager"**

### What Was Implemented vs. What's Missing

**NetworkManager.gd has everything needed** (lines 103-153):
- `submit_action(action)` - Routes actions to host/client correctly
- `_send_action_to_host.rpc()` - Client sends actions to host
- `_broadcast_result.rpc()` - Host broadcasts results to clients
- `validate_action()` - 4-layer validation system
- Integration with GameManager for action processing

**BUT**: Game phases never call `NetworkManager.submit_action()`!

### The Disconnect

Looking at the code:
1. **GameManager.gd** (lines 8-13) can process actions and generate diffs
2. **NetworkManager.gd** (lines 103-125) routes actions through GameManager
3. **BasePhase.gd** (lines 68-94) has execute_action() that processes actions
4. **Controllers** (e.g., DeploymentController.gd:306) call phase.execute_action() directly

**The problem**: Controllers → Phase.execute_action() bypasses NetworkManager entirely!

---

## Context and Research Findings

### Existing Infrastructure Analysis

#### 1. NetworkManager (40k/autoloads/NetworkManager.gd)

**Submit Action Method** (lines 103-125):
```gdscript
func submit_action(action: Dictionary) -> void:
	if not is_networked():
		# Single player mode - apply directly via GameManager
		game_manager.apply_action(action)
		return

	if is_host():
		# Host validates and applies
		var peer_id = 1
		var validation = validate_action(action, peer_id)
		if not validation.valid:
			push_error("NetworkManager: Host action rejected: %s" % validation.reason)
			return

		# Execute via GameManager
		var result = game_manager.apply_action(action)
		if result.success:
			# Broadcast the result to client
			_broadcast_result.rpc(result)
	else:
		# Client sends to host
		_send_action_to_host.rpc_id(1, action)
```

**Key Points**:
- Handles offline/host/client modes automatically
- Validates actions on host
- Broadcasts results with diffs already computed
- Uses GameManager for actual state changes

#### 2. GameManager (40k/autoloads/GameManager.gd)

**Action Processing** (lines 8-48):
```gdscript
func apply_action(action: Dictionary) -> Dictionary:
	var result = process_action(action)
	if result["success"]:
		apply_result(result)
		action_history.append(action)
	return result

func apply_result(result: Dictionary) -> void:
	if not result["success"]:
		return

	for diff in result["diffs"]:
		apply_diff(diff)

	if result.has("log_text"):
		emit_signal("action_logged", result["log_text"])

	emit_signal("result_applied", result)
```

**Currently Supports**:
- `DEPLOY_UNIT` action type (lines 22-48)
- Generates diffs (state change descriptions)
- Can be extended for other action types

**Missing**: Movement, Shooting, Charge, Fight, and other action types

#### 3. Phase Action System (40k/phases/BasePhase.gd)

**Existing Action Flow** (lines 68-94):
```gdscript
func execute_action(action: Dictionary) -> Dictionary:
	var validation = validate_action(action)
	if not validation.valid:
		return {"success": false, "errors": validation.errors}

	var result = process_action(action)
	if result.success:
		if result.has("changes") and result.changes is Array:
			PhaseManager.apply_state_changes(result.changes)

		emit_signal("action_taken", action)

		if _should_complete_phase():
			emit_signal("phase_completed")

	return result
```

**Action Types Per Phase**:

**DeploymentPhase** (lines 143-148):
- `DEPLOY_UNIT` - Place unit models on board

**MovementPhase** (lines 118-147):
- `BEGIN_NORMAL_MOVE`, `BEGIN_ADVANCE`, `BEGIN_FALL_BACK`
- `SET_MODEL_DEST`, `STAGE_MODEL_MOVE`, `CONFIRM_UNIT_MOVE`
- `UNDO_LAST_MODEL_MOVE`, `RESET_UNIT_MOVE`
- `REMAIN_STATIONARY`, `LOCK_MOVEMENT_MODE`
- `SET_ADVANCE_BONUS`, `END_MOVEMENT`
- `DISEMBARK_UNIT`, `CONFIRM_DISEMBARK`

**ShootingPhase**, **ChargePhase**, **FightPhase**: Similar patterns (not exhaustively listed)

#### 4. Controllers (40k/scripts/)

**Example: DeploymentController.gd** (lines 286-327):
```gdscript
func confirm() -> void:
	var deployment_action = {
		"type": "DEPLOY_UNIT",
		"unit_id": unit_id,
		"model_positions": model_positions,
		"model_rotations": temp_rotations,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"player": GameState.get_active_player(),
		"timestamp": Time.get_unix_time_from_system()
	}

	# CURRENT: Calls phase directly
	var result = phase_manager.current_phase_instance.execute_action(deployment_action)

	# NEEDED: Route through NetworkManager
	# var result = NetworkManager.submit_action(deployment_action)
```

**Other Controllers Follow Same Pattern**:
- MovementController.gd - Movement actions
- ShootingController.gd - Shooting actions
- ChargeController.gd - Charge actions
- FightController.gd - Fight actions

---

## Implementation Strategy

### Design Philosophy

**Minimal Disruption Principle**: The existing action system works perfectly for single-player. We need to:
1. Keep the existing phase action system intact
2. Add a thin multiplayer routing layer
3. Ensure backward compatibility with single-player

### Architecture Decision: Two Approaches Considered

#### Approach A: Controller-Level Routing (SELECTED ✅)
**Route actions at the controller level before they reach phases.**

```gdscript
# In controllers (e.g., DeploymentController.gd)
func confirm() -> void:
	var deployment_action = { ... }

	# NEW: Route through NetworkManager if networked
	if NetworkManager.is_networked():
		NetworkManager.submit_action(deployment_action)
	else:
		# Existing single-player path
		phase_manager.current_phase_instance.execute_action(deployment_action)
```

**Pros**:
- Minimal code changes (one if/else per controller action)
- Phases remain pure (no network knowledge)
- Clear separation of concerns
- Easy to test offline mode

**Cons**:
- Must update all controllers (8 files)
- Duplicate routing logic in each controller

#### Approach B: Phase-Level Routing
**Add networking logic inside BasePhase.execute_action().**

**Pros**:
- Single point of change (BasePhase.gd)
- All phases inherit automatically

**Cons**:
- Violates separation of concerns (phases shouldn't know about networking)
- Harder to test phases in isolation
- Complicates phase logic

**Decision: Use Approach A** - Better architecture, clearer responsibilities

---

### Integration Pattern

We'll create a helper method in a new `NetworkIntegration` utility to avoid code duplication:

```gdscript
# New file: 40k/utils/NetworkIntegration.gd
class_name NetworkIntegration

# Route an action through the appropriate channel (network or local)
static func route_action(action: Dictionary) -> Dictionary:
	# Add player and timestamp if not present
	if not action.has("player"):
		action["player"] = GameState.get_active_player()
	if not action.has("timestamp"):
		action["timestamp"] = Time.get_unix_time_from_system()

	# Check if multiplayer is active
	var network_manager = Engine.get_main_loop().root.get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked():
		print("[NetworkIntegration] Routing action through NetworkManager: ", action.get("type"))
		network_manager.submit_action(action)
		# In multiplayer, the result comes back via RPC
		# For now, return a pending result
		return {"success": true, "pending": true}
	else:
		print("[NetworkIntegration] Executing action locally: ", action.get("type"))
		# Single-player path - execute through phase directly
		var phase_manager = Engine.get_main_loop().root.get_node("/root/PhaseManager")
		if phase_manager and phase_manager.current_phase_instance:
			return phase_manager.current_phase_instance.execute_action(action)
		return {"success": false, "error": "No phase instance available"}
```

Then controllers simply call:
```gdscript
var result = NetworkIntegration.route_action(deployment_action)
```

---

## Implementation Tasks (In Order)

### Phase 0: Preparation (1 day)
1. **Create NetworkIntegration utility**
   - File: `40k/utils/NetworkIntegration.gd`
   - Single responsibility: Route actions to network or local execution
   - ~50 lines of code

2. **Update GameManager to support all action types**
   - Currently only supports `DEPLOY_UNIT`
   - Add processing for: Movement, Shooting, Charge, Fight actions
   - Match phase action types

3. **Create unit tests for NetworkIntegration**
   - File: `40k/tests/network/test_network_integration.gd`
   - Test offline routing (goes to phase)
   - Test online routing (goes to NetworkManager)

### Phase 1: Deployment Phase Integration (2-3 days)
4. **Update DeploymentController**
   - File: `40k/scripts/DeploymentController.gd:306`
   - Replace: `phase.execute_action()` with `NetworkIntegration.route_action()`
   - Test: Host deploys unit, client sees it

5. **Extend GameManager for DEPLOY_UNIT**
   - Already exists! Just verify it works
   - File: `40k/autoloads/GameManager.gd:22-48`

6. **Test deployment synchronization**
   - Manual test: Two instances, host deploys, client sees models
   - Verify positions, rotations, status all sync

### Phase 2: Movement Phase Integration (3-4 days)
7. **Update MovementController**
   - File: `40k/scripts/MovementController.gd`
   - Find all `execute_action()` calls
   - Replace with `NetworkIntegration.route_action()`
   - ~10-15 action points to update

8. **Extend GameManager for movement actions**
   - Add: `process_move_unit()`, `process_advance()`, `process_fall_back()`
   - Generate appropriate diffs for position updates
   - Handle advance dice rolls (use NetworkManager RNG seeds)

9. **Test movement synchronization**
   - Manual test: Host moves unit, client sees positions update
   - Verify coherency, distances, all models sync

### Phase 3: Combat Phases Integration (4-5 days)
10. **Update ShootingController**
    - File: `40k/scripts/ShootingController.gd`
    - Route shooting actions through NetworkIntegration

11. **Update ChargeController**
    - File: `40k/scripts/ChargeController.gd`
    - Route charge actions through NetworkIntegration

12. **Update FightController**
    - File: `40k/scripts/FightController.gd`
    - Route fight actions through NetworkIntegration

13. **Extend GameManager for combat actions**
    - Add: `process_shoot()`, `process_charge()`, `process_fight()`
    - Handle dice rolls with deterministic seeds
    - Generate wound/damage diffs

14. **Test combat synchronization**
    - Manual test: Full combat sequence syncs between players
    - Verify dice rolls, wounds, model deaths sync

### Phase 4: Other Phases Integration (2-3 days)
15. **Update CommandController**
    - File: `40k/scripts/CommandController.gd`
    - Route command phase actions

16. **Update ScoringController**
    - File: `40k/scripts/ScoringController.gd`
    - Route scoring actions

17. **Update DisembarkController** (if has actions)
    - File: `40k/scripts/DisembarkController.gd`
    - Route disembarkation actions

18. **Extend GameManager for remaining actions**
    - Add handlers for command, scoring, transport actions

### Phase 5: Testing & Validation (3-4 days)
19. **Create comprehensive integration tests**
    - Full game flow: Deploy → Move → Shoot → Charge → Fight → Score
    - Verify both players see identical state at each step

20. **Test edge cases**
    - Client disconnects mid-action
    - Invalid actions rejected
    - Turn timer enforcement
    - Rapid action submission

21. **Performance testing**
    - Action latency < 200ms
    - No desync after 10-turn game
    - Memory usage acceptable

22. **Create manual test checklist**
    - Document step-by-step multiplayer testing procedure
    - Include expected vs. actual results

---

## Implementation Blueprint

### File: 40k/utils/NetworkIntegration.gd (NEW)

```gdscript
extends Node
class_name NetworkIntegration

## NetworkIntegration - Utility for routing game actions through multiplayer or local execution
##
## This class provides a single entry point for all game actions, automatically
## routing them through NetworkManager if multiplayer is active, or executing
## them locally for single-player games.

# Route an action through the appropriate channel (network or local)
static func route_action(action: Dictionary) -> Dictionary:
	"""
	Routes a game action through the appropriate execution path.

	In multiplayer mode:
	  - Actions are sent through NetworkManager for validation and synchronization
	  - Host validates and broadcasts results
	  - Clients send to host for processing

	In single-player mode:
	  - Actions are executed directly through the phase system

	Args:
		action: Dictionary with keys:
			- type: String (required) - Action type (e.g., "DEPLOY_UNIT")
			- player: int (optional) - Player ID, added automatically if missing
			- timestamp: float (optional) - Unix timestamp, added automatically if missing
			- ... other action-specific fields

	Returns:
		Dictionary with keys:
			- success: bool - Whether action succeeded
			- pending: bool (multiplayer only) - True if waiting for network response
			- error: String (optional) - Error message if failed
			- errors: Array (optional) - Validation errors if failed
	"""

	# Validate action has required fields
	if not action.has("type"):
		push_error("[NetworkIntegration] Action missing required 'type' field")
		return {"success": false, "error": "Action missing 'type' field"}

	# Add player and timestamp if not present
	if not action.has("player"):
		action["player"] = GameState.get_active_player()
	if not action.has("timestamp"):
		action["timestamp"] = Time.get_unix_time_from_system()

	# Get NetworkManager reference
	var network_manager = Engine.get_main_loop().root.get_node_or_null("/root/NetworkManager")

	# Check if multiplayer is active
	if network_manager and network_manager.is_networked():
		print("[NetworkIntegration] Routing action through NetworkManager: ", action.get("type"))

		# Route through network layer
		network_manager.submit_action(action)

		# In multiplayer, the result comes back asynchronously via RPC
		# The action will be executed when the RPC arrives
		# For now, return a pending status
		return {"success": true, "pending": true, "message": "Action submitted to network"}

	else:
		# Single-player mode - execute through phase directly
		print("[NetworkIntegration] Executing action locally: ", action.get("type"))
		var phase_manager = Engine.get_main_loop().root.get_node_or_null("/root/PhaseManager")

		if not phase_manager:
			push_error("[NetworkIntegration] PhaseManager not found")
			return {"success": false, "error": "PhaseManager not available"}

		if not phase_manager.current_phase_instance:
			push_error("[NetworkIntegration] No active phase instance")
			return {"success": false, "error": "No active phase"}

		# Execute action through phase
		var result = phase_manager.current_phase_instance.execute_action(action)
		return result

# Check if multiplayer mode is active
static func is_multiplayer_active() -> bool:
	var network_manager = Engine.get_main_loop().root.get_node_or_null("/root/NetworkManager")
	return network_manager != null and network_manager.is_networked()

# Get current player (for action construction)
static func get_current_player() -> int:
	return GameState.get_active_player()
```

### Update Example: DeploymentController.gd

**Before** (lines 286-327):
```gdscript
func confirm() -> void:
	var deployment_action = {
		"type": "DEPLOY_UNIT",
		"unit_id": unit_id,
		"model_positions": model_positions,
		"model_rotations": temp_rotations,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"player": GameState.get_active_player(),
		"timestamp": Time.get_unix_time_from_system()
	}

	# Execute through PhaseManager
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance and phase_manager.current_phase_instance.has_method("execute_action"):
			var result = phase_manager.current_phase_instance.execute_action(deployment_action)
			if result.success:
				print("[DeploymentController] Deployment successful")
			else:
				print("[DeploymentController] Deployment failed")
				push_error("Deployment failed: " + str(result.get("error", "Unknown error")))
```

**After** (minimal change):
```gdscript
func confirm() -> void:
	var deployment_action = {
		"type": "DEPLOY_UNIT",
		"unit_id": unit_id,
		"model_positions": model_positions,
		"model_rotations": temp_rotations,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"player": GameState.get_active_player(),
		"timestamp": Time.get_unix_time_from_system()
	}

	# Route through NetworkIntegration (handles multiplayer and single-player)
	var result = NetworkIntegration.route_action(deployment_action)

	if result.success:
		if result.get("pending", false):
			print("[DeploymentController] Deployment submitted to network")
		else:
			print("[DeploymentController] Deployment successful")
	else:
		print("[DeploymentController] Deployment failed: ", result.get("error", "Unknown"))
		push_error("Deployment failed: " + str(result.get("error", "Unknown error")))
```

**Changes**:
1. Line 302: Remove PhaseManager check
2. Line 306: Replace `phase_manager.current_phase_instance.execute_action()` with `NetworkIntegration.route_action()`
3. Lines 307-313: Update result handling for pending state

---

## GameManager Extensions

### Required Action Type Support

Currently GameManager only supports `DEPLOY_UNIT`. We need to add:

```gdscript
# 40k/autoloads/GameManager.gd

func process_action(action: Dictionary) -> Dictionary:
	match action["type"]:
		"DEPLOY_UNIT":
			return process_deploy_unit(action)

		# Movement actions
		"BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK":
			return process_begin_move(action)
		"CONFIRM_UNIT_MOVE":
			return process_confirm_move(action)
		"REMAIN_STATIONARY":
			return process_remain_stationary(action)

		# Combat actions
		"SELECT_TARGET":
			return process_select_target(action)
		"RESOLVE_ATTACKS":
			return process_resolve_attacks(action)
		"ALLOCATE_WOUNDS":
			return process_allocate_wounds(action)

		# Charge actions
		"DECLARE_CHARGE":
			return process_declare_charge(action)
		"ROLL_CHARGE":
			return process_roll_charge(action)

		# Fight actions
		"SELECT_FIGHT_TARGET":
			return process_fight_target(action)
		"RESOLVE_FIGHT":
			return process_resolve_fight(action)

		_:
			return {"success": false, "error": "Unknown action type: " + action["type"]}

# Movement action processors
func process_begin_move(action: Dictionary) -> Dictionary:
	var unit_id = action["unit_id"]
	var move_type = action.get("move_type", "NORMAL")

	var diffs = []
	diffs.append({
		"op": "set",
		"path": "units.%s.movement_state.active" % unit_id,
		"value": true
	})
	diffs.append({
		"op": "set",
		"path": "units.%s.movement_state.type" % unit_id,
		"value": move_type
	})

	return {
		"success": true,
		"diffs": diffs,
		"log_text": "Started %s move for unit %s" % [move_type, unit_id]
	}

func process_confirm_move(action: Dictionary) -> Dictionary:
	var unit_id = action["unit_id"]
	var model_positions = action["model_positions"]

	var diffs = []
	for i in range(model_positions.size()):
		var pos = model_positions[i]
		if pos != null:
			diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})

	diffs.append({
		"op": "set",
		"path": "units.%s.movement_state.complete" % unit_id,
		"value": true
	})

	return {
		"success": true,
		"diffs": diffs,
		"log_text": "Completed move for unit %s" % unit_id
	}

# ... Add similar processors for combat, charge, fight actions
```

---

## Testing Strategy

### Unit Tests

**File: 40k/tests/network/test_network_integration.gd**

```gdscript
extends GutTest

func test_route_action_offline():
	# Ensure NetworkManager is offline
	var network_manager = NetworkManager.new()
	network_manager.network_mode = NetworkManager.NetworkMode.OFFLINE
	add_child_autofree(network_manager)

	var action = {"type": "DEPLOY_UNIT", "unit_id": "U1"}
	var result = NetworkIntegration.route_action(action)

	assert_true(result.success, "Offline action should succeed")
	assert_false(result.get("pending", false), "Offline action should not be pending")

func test_route_action_online_as_host():
	var network_manager = NetworkManager.new()
	network_manager.network_mode = NetworkManager.NetworkMode.HOST
	var game_manager = GameManager.new()
	network_manager.game_manager = game_manager
	add_child_autofree(network_manager)
	add_child_autofree(game_manager)

	var action = {"type": "DEPLOY_UNIT", "unit_id": "U1", "player": 1}
	var result = NetworkIntegration.route_action(action)

	assert_true(result.success, "Online host action should succeed")
	assert_true(result.get("pending", false), "Online action should be pending")

func test_action_missing_type_fails():
	var action = {"unit_id": "U1"}  # Missing type
	var result = NetworkIntegration.route_action(action)

	assert_false(result.success, "Action without type should fail")
	assert_has_key(result, "error", "Should have error message")
```

### Integration Tests

**Manual Test Procedure**:

1. **Setup**:
   ```bash
   # Terminal 1: Host
   godot --position 0,0 40k/project.godot

   # Terminal 2: Client
   godot --position 800,0 40k/project.godot
   ```

2. **Test Deployment Sync**:
   - Host: Create game, wait for client
   - Client: Join at 127.0.0.1:7777
   - Host: Click "Start Game"
   - Both: Should see Main scene
   - Host: Deploy a unit (e.g., Custodes Guard)
   - **Expected**: Client sees unit models appear at same positions
   - **Verify**: Unit status changes from UNDEPLOYED → DEPLOYED on both

3. **Test Movement Sync**:
   - Host: Select a unit, move models
   - **Expected**: Client sees models moving in real-time
   - Host: Confirm move
   - **Expected**: Client sees final positions locked in

4. **Test Combat Sync**:
   - Host: Enter shooting phase, select unit, select target
   - **Expected**: Client sees selection highlights
   - Host: Roll to hit, roll to wound, allocate wounds
   - **Expected**: Client sees dice results, wound markers

5. **Test Turn Switching**:
   - Host: Complete all phases
   - **Expected**: Turn switches to Player 2 (client)
   - Client: Now able to take actions
   - **Expected**: Host sees client's actions

### Validation Gates

```bash
# Test compilation
export PATH="$HOME/bin:$PATH"
godot --headless --check-only 40k/project.godot

# Run all network tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/

# Run integration tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/network/test_network_integration.gd

# Verify NetworkIntegration is used in controllers
grep -r "NetworkIntegration.route_action" 40k/scripts/*Controller.gd

# Verify no direct phase.execute_action calls remain in controllers
grep -r "execute_action" 40k/scripts/*Controller.gd | grep -v "has_method"

# Should find 0 matches (all should use NetworkIntegration now)
```

---

## Error Handling Strategy

### Edge Cases

1. **Action submitted while disconnecting**:
   ```gdscript
   # In NetworkIntegration.route_action()
   if network_manager and network_manager.is_networked():
   	if not multiplayer.multiplayer_peer or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
   		return {"success": false, "error": "Network connection lost"}
   	network_manager.submit_action(action)
   ```

2. **Invalid action rejected by host**:
   - NetworkManager already handles this with `_reject_action.rpc()`
   - Client sees rejection, can retry or show error to user

3. **Phase not ready for action**:
   ```gdscript
   # In GameManager.process_action()
   if not _validate_phase_for_action(action):
   	return {"success": false, "error": "Action not valid in current phase"}
   ```

4. **RNG seed not available** (client tries to roll dice):
   ```gdscript
   # In combat action processors
   if is_networked() and not is_host():
   	return {"success": false, "error": "Only host can roll dice in multiplayer"}
   ```

---

## Performance Considerations

### Network Traffic

**Action Size Estimates**:
- Deploy action: ~200 bytes (unit_id + positions array)
- Move action: ~150 bytes (unit_id + destination)
- Combat action: ~300 bytes (attacker + defender + dice results)

**Optimizations**:
1. Don't send full state, only diffs
2. Batch multiple model moves into single action where possible
3. Compress position arrays (use floats, not Vector2 objects)

### Latency Impact

**Expected latencies**:
- Local network: 10-50ms action → result
- Internet: 50-200ms action → result

**UX Considerations**:
1. Show "Submitting..." indicator for pending actions
2. Disable rapid re-submission (debounce)
3. Show "Waiting for opponent..." during their turn

---

## Documentation References

### Godot Networking
- **High-level Multiplayer**: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- **RPC Best Practices**: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html#rpc-functions

### Related Code
- **NetworkManager**: 40k/autoloads/NetworkManager.gd (Infrastructure already exists)
- **GameManager**: 40k/autoloads/GameManager.gd (Action processor)
- **BasePhase**: 40k/phases/BasePhase.gd (Phase action system)
- **PhaseManager**: 40k/autoloads/PhaseManager.gd (apply_state_changes)

### Previous PRPs
- **Issue #89 v4**: PRPs/gh_issue_89_multiplayer_FINAL_v4s.md (Original architecture)
- **Issue #96**: PRPs/gh_issue_96_multiplayer-start-sync.md (Game start sync)

---

## Implementation Checklist

### Phase 0: Preparation
- [ ] Create `40k/utils/` directory
- [ ] Create `NetworkIntegration.gd` utility class
- [ ] Create `test_network_integration.gd` unit tests
- [ ] Run tests to verify utility works offline

### Phase 1: Deployment (MVP)
- [ ] Update `DeploymentController.confirm()` to use NetworkIntegration
- [ ] Verify `GameManager.process_deploy_unit()` exists and works
- [ ] Manual test: Host deploys, client sees it
- [ ] Manual test: Client deploys (after turn switch), host sees it

### Phase 2: Movement
- [ ] Find all `execute_action()` calls in MovementController
- [ ] Replace with `NetworkIntegration.route_action()`
- [ ] Extend GameManager for movement action types
- [ ] Manual test: Movement syncs between players

### Phase 3: Combat
- [ ] Update ShootingController
- [ ] Update ChargeController
- [ ] Update FightController
- [ ] Extend GameManager for combat actions
- [ ] Manual test: Full combat sequence syncs

### Phase 4: Other Phases
- [ ] Update CommandController
- [ ] Update ScoringController
- [ ] Update DisembarkController (if needed)
- [ ] Extend GameManager for remaining actions

### Phase 5: Testing
- [ ] Full game integration test (2 players, complete game)
- [ ] Performance test (latency < 200ms)
- [ ] Edge case testing (disconnects, invalid actions)
- [ ] Create manual test documentation

---

## Success Criteria

### MVP Must-Haves (Phase 1 Complete)
1. ✅ Deployment actions sync between players
2. ✅ Both players see units deployed at same positions
3. ✅ Turn switching works after deployment
4. ✅ Single-player mode still works (backward compatible)

### Full Phase 1 Complete
1. ✅ All phase actions route through NetworkManager
2. ✅ GameManager supports all action types
3. ✅ Full game playable multiplayer (deploy → move → shoot → fight → score)
4. ✅ Both players see identical game state throughout
5. ✅ Action latency < 200ms on local network
6. ✅ No desyncs after 10-turn game
7. ✅ Existing tests still pass

### Performance Targets
- Action submission → result: < 200ms (local network)
- Memory overhead: < 5MB additional
- No noticeable FPS drop during network sync

---

## Timeline Estimate

**Single Developer**:
- Phase 0 (Preparation): 1 day
- Phase 1 (Deployment MVP): 2-3 days
- Phase 2 (Movement): 3-4 days
- Phase 3 (Combat): 4-5 days
- Phase 4 (Other Phases): 2-3 days
- Phase 5 (Testing): 3-4 days
- **Total: 15-20 days** (~3-4 weeks)

**Team of 2**:
- One person: Controllers (Phases 1-4)
- One person: GameManager extensions
- **Total: 10-12 days** (~2 weeks)

**Critical Path**: Controllers → GameManager → Testing (sequential)

---

## Known Risks

### High Risk 🔴
1. **GameManager Action Coverage**
   - Risk: Missing action types cause errors
   - Mitigation: Start with deployment (already working), add incrementally

2. **Async Action Handling**
   - Risk: UI expects immediate result, gets "pending" in multiplayer
   - Mitigation: Update controllers to handle pending state gracefully

### Medium Risk 🟡
1. **Backward Compatibility**
   - Risk: Breaking single-player mode
   - Mitigation: NetworkIntegration checks if networked before routing

2. **Performance Degradation**
   - Risk: Network calls slow down game
   - Mitigation: Profile before/after, optimize if needed

### Low Risk 🟢
1. **Controller Count**
   - Risk: Updating 8 controllers is tedious
   - Mitigation: NetworkIntegration utility minimizes per-controller changes

---

## Future Enhancements (Post-Phase 1)

1. **Action Buffering**: Queue actions if network is slow
2. **Optimistic UI Updates**: Show action locally, rollback if rejected
3. **Action Compression**: Reduce network payload size
4. **Reconnection Support**: Resume game after disconnect
5. **Spectator Mode**: Allow observers to watch games
6. **Replay System**: Save/replay action sequences

---

## Conclusion

This PRP completes the Phase 1 integration by connecting the existing, well-designed action system to the existing, well-designed NetworkManager. The solution is:

- **Minimal**: One utility class, small changes to controllers
- **Clean**: Clear separation between networking and game logic
- **Backward Compatible**: Single-player continues to work
- **Testable**: Each component can be tested in isolation
- **Incremental**: Deploy → Movement → Combat → Other (ship MVP early)

**Confidence Score: 8/10**

High confidence because:
- ✅ Both systems (phases and NetworkManager) already exist and work
- ✅ Just need to connect them with thin routing layer
- ✅ Clear implementation path with incremental milestones
- ✅ Can test each phase independently before moving to next

Reduced from 10/10 due to:
- ⚠️ GameManager extensions need testing with all action types
- ⚠️ Async result handling in controllers needs careful UI updates
- ⚠️ Full integration testing required to catch edge cases

**The infrastructure is 90% done. This PRP completes the last 10% to make multiplayer actually work.**

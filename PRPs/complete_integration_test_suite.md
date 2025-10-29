# PRP: Complete Integration Test Suite for Warhammer 40k Godot Game

## Executive Summary

Complete the multiplayer integration testing suite for the Warhammer 40k game. The test infrastructure is 100% implemented, but only deployment tests exist (10 tests, 0% passing). This PRP covers fixing the deployment test blockers and implementing the remaining 49 tests across all game phases (Movement, Shooting, Charge, Fight, Transitions, Full Game).

**Current Status**: Phase 1 Infrastructure Complete (100%) → Implementation Phase Begins
**Target**: All 59 tests implemented and passing across 7 test phases

## Problem Statement

### Current State

**✅ Completed (100%)**:
- Test infrastructure (`MultiplayerIntegrationTest`, `GameInstance`, `LogMonitor`, `TestModeHandler`)
- Deployment test file with 10 test functions
- 5 deployment test save files
- Command-based action simulation system
- GameManager methods: `deploy_unit()`, `undo_last_action()`, `complete_deployment()` (already exist!)

**🔴 Critical Blockers (Phase 1)**:
1. **Game Auto-Start Issue**: Game instances don't properly enter Deployment phase when started via TestModeHandler
2. **Phase Initialization**: `get_game_state()` returns phase != "Deployment" after auto-start
3. **Network Sync Verification**: Need to verify deployment actions sync across host/client

**⚠️ Remaining Work**:
- 49 tests unimplemented (Phases 2-7)
- 28 test save files to create
- 18 TestModeHandler action handlers to implement

### Why This Matters

Without passing integration tests:
- Cannot verify multiplayer synchronization works correctly
- Risk of introducing bugs when adding new features
- No confidence that game state stays consistent between players
- Manual testing is time-consuming and error-prone

## Context and Research Findings

### Test Infrastructure Architecture

**File**: `40k/tests/helpers/MultiplayerIntegrationTest.gd`
- Base class for all multiplayer tests (extends GutTest)
- Manages host and client `GameInstance` processes
- Provides `simulate_host_action()` and `simulate_client_action()`
- Uses command file system for inter-process communication

**File**: `40k/tests/helpers/GameInstance.gd`
- Wraps a Godot process launched with test mode flags
- Handles window positioning (side-by-side for visual debugging)
- Generates command files that TestModeHandler reads
- Waits for result files with timeout handling

**File**: `40k/autoloads/TestModeHandler.gd`
- Autoload that runs in test game instances
- Polls `test_commands/commands/` directory every 100ms
- Executes commands via action handlers (e.g., `_handle_deploy_unit()`)
- Writes results to `test_commands/results/` directory
- Already implements 4 action handlers:
  - `load_save` → Line 401-466
  - `deploy_unit` → Line 468-527
  - `undo_deployment` → Line 529-561
  - `complete_deployment` → Line 563-600
  - `get_game_state` → Line 602-661

### Game Architecture Overview

**Autoloads**:
- `GameState` - Single source of truth for game state (dictionary-based)
- `GameManager` - Processes actions, applies diffs, emits signals
- `PhaseManager` - Manages phase transitions, instantiates phase scripts
- `TestModeHandler` - Test automation layer (only active in test mode)

**Phase System**:
- Each phase is a script extending `BasePhase`
- Phases have `enter_phase()`, `exit_phase()`, `execute_action()` methods
- Phase instances created dynamically by PhaseManager
- Current phase validation happens in phase's `execute_action()`

**Action Flow**:
```
Test Script → Command File → TestModeHandler → GameManager.apply_action()
  → Phase.execute_action() → GameManager.apply_diff() → GameState.state update
  → Result File → Test Script
```

### External References

- **Warhammer 40k 10th Edition Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
  - Phase sequencing rules
  - Turn structure (Command → Movement → Shooting → Charge → Fight → Scoring)
  - Alternating activation in Fight Phase

- **Godot 4.4 Testing Documentation**: https://docs.godotengine.org/en/4.4/
  - Scene tree access in test environments
  - Process management for integration tests

- **GUT Framework**: https://gut.readthedocs.io/en/latest/
  - Used for the test runner and assertions
  - Provides `before_each()`, `after_each()` lifecycle

## Critical Blockers Analysis

### Blocker 1: Game Auto-Start in Test Mode

**File**: `40k/autoloads/TestModeHandler.gd` (Lines 131-174)

**Current Behavior**:
- `_schedule_auto_host()` is called when `--auto-host` flag is present
- Automatically navigates: Main Menu → Multiplayer Lobby → Host Game → Start Game
- Waits for client connection before starting game
- Game should transition to Deployment phase after starting

**Potential Issues**:
1. **Scene Transition Timing**: Game might not be fully loaded when TestModeHandler checks phase
2. **Phase Initialization**: PhaseManager might not be transitioning to Deployment phase automatically
3. **GameState Not Synced**: GameState might initialize with default phase but not trigger PhaseManager

**Investigation Needed**:
- Check if `PhaseManager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)` is called on game start
- Verify `GameState.get_current_phase()` returns correct value
- Check if Main.gd or Game.gd has initialization logic that needs to run

**Solution Approach**:
1. Add debug logging to track phase initialization sequence
2. Ensure PhaseManager initializes to Deployment when game starts
3. Add explicit phase check with retry logic in TestModeHandler

### Blocker 2: Network Sync for Actions

**File**: `40k/autoloads/NetworkManager.gd`

**Requirement**: When host executes an action (e.g., deploy_unit), client must receive and apply the same state changes.

**Current Architecture**:
- GameManager applies action → generates diffs
- NetworkManager syncs diffs via RPC calls
- Client receives diffs → applies to local GameState

**Verification Strategy**:
1. After action on host, query both host and client game states
2. Compare critical fields (unit positions, status, phase)
3. Assert states match within timeout (1-2 seconds)

**Test Pattern** (from test_multiplayer_deployment.gd:110-115):
```gdscript
# Wait for sync
await wait_for_seconds(1.0)

# Verify unit deployed on both clients
var host_state_after = host_instance.get_game_state()
var client_state_after = client_instance.get_game_state()
# Check that both clients see the deployed unit
```

### Blocker 3: Save File Loading in Test Mode

**File**: `40k/autoloads/TestModeHandler.gd` (Lines 401-466)

**Current Implementation**: `_handle_load_save()` already exists
- Calls `SaveLoadManager.load_game(path)`
- Waits 0.5s for load to complete
- Verifies units loaded via `GameState.state.units.size()`

**Potential Issues**:
- Save file path resolution (test saves vs regular saves)
- Save file format compatibility
- GameState not fully initialized when load is called

**Verification**: Load deployment_start.w40ksave and check:
1. GameState.state.units is populated
2. Units have correct owner (1 or 2)
3. Phase is DEPLOYMENT
4. Board setup is correct

## Implementation Blueprint

### Phase 1: Fix Deployment Test Blockers (Priority 1 - CRITICAL)

#### Task 1.1: Debug Game Auto-Start Phase Initialization

**File**: `40k/autoloads/TestModeHandler.gd`

**Approach**:
1. Add extensive logging to track phase initialization
2. After `_on_start_game_button_pressed()`, wait for game scene to fully load
3. Explicitly verify PhaseManager has transitioned to Deployment
4. Add retry logic with timeout

**Pseudocode**:
```gdscript
# In _schedule_auto_host() after starting game
await get_tree().create_timer(3.0).timeout  # Increased wait time

# Verify phase initialization
var phase_manager = get_node_or_null("/root/PhaseManager")
if not phase_manager:
    push_error("PhaseManager not found after game start")
    return

var max_retries = 10
var retry_count = 0
while retry_count < max_retries:
    var current_phase = GameState.get_current_phase()
    if current_phase == GameStateData.Phase.DEPLOYMENT:
        print("TestModeHandler: Game successfully in Deployment phase")
        break

    print("TestModeHandler: Waiting for Deployment phase (attempt %d/%d)" % [retry_count+1, max_retries])
    await get_tree().create_timer(0.5).timeout
    retry_count += 1

if retry_count >= max_retries:
    push_error("TestModeHandler: Game failed to enter Deployment phase")
```

**Validation**:
```bash
# Run basic connection test
cd 40k
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gfile=test_multiplayer_deployment.gd \
  -gtest=test_basic_multiplayer_connection \
  -gexit 2>&1 | grep -E "PASSED|FAILED|current_phase"
```

**Success Criteria**:
- Test output shows "current_phase: Deployment"
- `test_basic_multiplayer_connection` passes
- No errors about missing PhaseManager or GameState

#### Task 1.2: Verify TestModeHandler Action Handlers

**File**: `40k/autoloads/TestModeHandler.gd` (Lines 468-527)

**Current Implementation**: `_handle_deploy_unit()` already exists
- Validates unit_id and position parameters
- Gets GameManager autoload
- Checks current phase is DEPLOYMENT
- Calls `GameManager.deploy_unit(unit_id, position)`
- Returns success/failure result

**Verification Steps**:
1. Confirm GameManager.deploy_unit() exists (✅ Already confirmed in GameManager.gd:640-681)
2. Test that deploy_unit is called and returns bool
3. Verify state changes are applied

**Edge Cases to Test**:
- Unit doesn't exist → Should return `{"success": false, "error": "UNIT_NOT_FOUND"}`
- Invalid position → Should validate deployment zone
- Unit already deployed → Should handle gracefully

**Test Command**:
```bash
cd 40k
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gtest=test_deployment_single_unit \
  -gexit 2>&1 | grep -E "success=|PASSED|FAILED"
```

#### Task 1.3: Add Network Sync Verification

**File**: `40k/tests/helpers/MultiplayerIntegrationTest.gd` (Add helper method)

**New Method**:
```gdscript
func verify_unit_synced(unit_id: String, timeout: float = 2.0) -> bool:
	"""
	Verify that a unit's state is synced between host and client
	Returns true if positions/status match, false otherwise
	"""
	var start_time = Time.get_ticks_msec() / 1000.0

	while (Time.get_ticks_msec() / 1000.0) - start_time < timeout:
		var host_state = await simulate_host_action("get_game_state", {})
		var client_state = await simulate_client_action("get_game_state", {})

		if not host_state.get("success") or not client_state.get("success"):
			await wait_for_seconds(0.2)
			continue

		var host_units = host_state.get("data", {}).get("units", {})
		var client_units = client_state.get("data", {}).get("units", {})

		if not host_units.has(unit_id) or not client_units.has(unit_id):
			await wait_for_seconds(0.2)
			continue

		# Compare key fields
		var host_unit = host_units[unit_id]
		var client_unit = client_units[unit_id]

		if host_unit.get("status") == client_unit.get("status"):
			print("[Test] Unit %s synced successfully" % unit_id)
			return true

		await wait_for_seconds(0.2)

	print("[Test] Unit %s failed to sync within %.1fs" % [unit_id, timeout])
	return false
```

**Usage in Tests**:
```gdscript
# After deployment action
var result = await simulate_host_action("deploy_unit", {
	"unit_id": "unit_p1_1",
	"position": {"x": 5.0, "y": 5.0}
})
assert_true(result.get("success"), "Deployment should succeed")

# Verify sync
var synced = await verify_unit_synced("unit_p1_1", 2.0)
assert_true(synced, "Unit should sync to client within 2 seconds")
```

### Phase 2: Movement Tests (10 tests, 6 save files, 4 action handlers)

#### File Creation: test_multiplayer_movement.gd

**Template** (based on test_multiplayer_deployment.gd):
```gdscript
extends MultiplayerIntegrationTest

# Movement Phase Multiplayer Integration Tests

func test_movement_basic_advance():
	"""
	Test: Move a unit 6" forward in Movement phase

	Setup: movement_start.w40ksave (units deployed, ready to move)
	Action: Host moves unit 6" (within M characteristic)
	Verify: Unit moves, position syncs, flags updated
	"""
	await launch_host_and_client("movement_start")
	await wait_for_connection()
	await wait_for_seconds(2.0)

	# Simulate movement action
	var result = await simulate_host_action("move_unit", {
		"unit_id": "unit_p1_1",
		"destination": {"x": 10.0, "y": 5.0},
		"movement_type": "NORMAL"
	})

	assert_true(result.get("success"), "Movement should succeed")
	await wait_for_seconds(1.0)

	# Verify unit moved on both clients
	var synced = await verify_unit_synced("unit_p1_1")
	assert_true(synced, "Unit position should sync")

# Additional 9 tests following similar pattern...
```

#### Test Save Files (6 required)

**Creation Strategy**: Use existing game + manual save
1. Launch game normally
2. Deploy all units
3. Complete deployment for both players
4. Save game → `movement_start.w40ksave`
5. Repeat with variations (terrain, enemies nearby, etc.)

**Required Saves**:
```
40k/tests/saves/
├── movement_start.w40ksave              # Units deployed, Movement phase
├── movement_nearly_complete.w40ksave   # Most units moved, few remaining
├── movement_multi_model_unit.w40ksave  # 10-model unit for coherency tests
├── movement_with_terrain.w40ksave      # Difficult terrain on board
├── movement_with_enemies.w40ksave      # Enemy units nearby
└── movement_in_engagement.w40ksave     # Units within engagement range
```

#### TestModeHandler Action Handlers (4 required)

**File**: `40k/autoloads/TestModeHandler.gd`

**Handler 1: `_handle_move_unit`** (Lines ~670-730)
```gdscript
func _handle_move_unit(params: Dictionary) -> Dictionary:
	"""
	Move a unit to a destination position

	Parameters:
		- unit_id: String - ID of unit to move
		- destination: {x: float, y: float} - Target position
		- movement_type: String - "NORMAL", "ADVANCE", or "FALL_BACK"
	"""
	print("TestModeHandler: Handling move_unit action")

	var unit_id = params.get("unit_id", "")
	var destination = params.get("destination", {})
	var movement_type = params.get("movement_type", "NORMAL")

	if unit_id.is_empty():
		return {"success": false, "message": "Missing unit_id", "error": "MISSING_PARAMETER"}

	if not destination.has("x") or not destination.has("y"):
		return {"success": false, "message": "Missing destination coordinates", "error": "MISSING_PARAMETER"}

	# Get GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return {"success": false, "message": "GameManager not found", "error": "GAME_MANAGER_NOT_FOUND"}

	# Build action dictionary
	var action_type = ""
	match movement_type:
		"NORMAL":
			action_type = "BEGIN_NORMAL_MOVE"
		"ADVANCE":
			action_type = "BEGIN_ADVANCE"
		"FALL_BACK":
			action_type = "BEGIN_FALL_BACK"
		_:
			return {"success": false, "message": "Invalid movement_type: " + movement_type, "error": "INVALID_PARAMETER"}

	# Begin movement
	var begin_result = game_manager.apply_action({
		"type": action_type,
		"unit_id": unit_id
	})

	if not begin_result.get("success", false):
		return {"success": false, "message": "Failed to begin move: " + begin_result.get("error", ""), "error": "BEGIN_MOVE_FAILED"}

	# Move all models to destination (simplified for testing)
	var unit = GameState.get_unit(unit_id)
	if not unit:
		return {"success": false, "message": "Unit not found after begin move", "error": "UNIT_NOT_FOUND"}

	var models = unit.get("models", [])
	var dest_vector = Vector2(destination["x"], destination["y"])

	for i in range(models.size()):
		# For testing, move all models to the same position
		# In real game, formation would be maintained
		var stage_result = game_manager.apply_action({
			"type": "STAGE_MODEL_MOVE",
			"unit_id": unit_id,
			"model_index": i,
			"position": dest_vector
		})

		if not stage_result.get("success", false):
			return {"success": false, "message": "Failed to stage model move", "error": "STAGE_MOVE_FAILED"}

	# Confirm movement
	var confirm_result = game_manager.apply_action({
		"type": "CONFIRM_UNIT_MOVE",
		"unit_id": unit_id
	})

	if confirm_result.get("success", false):
		return {
			"success": true,
			"message": "Unit moved successfully",
			"data": {
				"unit_id": unit_id,
				"destination": destination,
				"movement_type": movement_type
			}
		}
	else:
		return {"success": false, "message": "Failed to confirm move: " + confirm_result.get("error", ""), "error": "CONFIRM_MOVE_FAILED"}
```

**Handler 2: `_handle_advance_unit`** (Similar to move_unit, but sets advance flag)
**Handler 3: `_handle_fall_back_unit`** (Similar to move_unit, for fall back action)
**Handler 4: `_handle_end_movement_phase`** (Triggers phase transition)

```gdscript
func _handle_end_movement_phase(params: Dictionary) -> Dictionary:
	"""End the movement phase and transition to shooting"""
	print("TestModeHandler: Handling end_movement_phase action")

	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		return {"success": false, "message": "GameManager not found", "error": "GAME_MANAGER_NOT_FOUND"}

	var result = game_manager.apply_action({"type": "END_MOVEMENT"})

	if result.get("success", false):
		# Wait for phase transition
		await get_tree().create_timer(0.5).timeout

		var new_phase = GameState.get_current_phase()
		var phase_name = _phase_enum_to_string(new_phase)

		return {
			"success": true,
			"message": "Movement phase ended",
			"data": {"new_phase": phase_name}
		}
	else:
		return {"success": false, "message": "Failed to end movement phase", "error": "END_PHASE_FAILED"}
```

**Helper Method** (add to TestModeHandler):
```gdscript
func _phase_enum_to_string(phase: int) -> String:
	"""Convert GameStateData.Phase enum to string"""
	var game_state = get_node_or_null("/root/GameState")
	if not game_state:
		return "Unknown"

	match phase:
		game_state.Phase.DEPLOYMENT: return "Deployment"
		game_state.Phase.COMMAND: return "Command"
		game_state.Phase.MOVEMENT: return "Movement"
		game_state.Phase.SHOOTING: return "Shooting"
		game_state.Phase.CHARGE: return "Charge"
		game_state.Phase.FIGHT: return "Fight"
		game_state.Phase.SCORING: return "Scoring"
		game_state.Phase.MORALE: return "Morale"
		_: return "Unknown"
```

**Action Routing** (update `_execute_command` in TestModeHandler):
```gdscript
func _execute_command(command: Dictionary) -> Dictionary:
	var action = command["action"]
	var params = command.get("parameters", {})

	match action:
		# Existing actions
		"load_save": return _handle_load_save(params)
		"deploy_unit": return _handle_deploy_unit(params)
		"undo_deployment": return _handle_undo_deployment(params)
		"complete_deployment": return _handle_complete_deployment(params)
		"get_game_state": return _handle_get_game_state(params)

		# New movement actions
		"move_unit": return _handle_move_unit(params)
		"advance_unit": return _handle_advance_unit(params)
		"fall_back_unit": return _handle_fall_back_unit(params)
		"end_movement_phase": return _handle_end_movement_phase(params)

		_:
			return {
				"success": false,
				"message": "Unknown action: " + action,
				"error": "UNKNOWN_ACTION"
			}
```

### Phase 3-7: Remaining Test Phases

Following the same pattern as Movement tests:

**Phase 3: Shooting Tests** (12 tests, 9 save files, 5 action handlers)
- Action handlers: `select_shooting_unit`, `select_shooting_target`, `resolve_shooting`, `declare_overwatch`, `end_shooting_phase`
- Key test: Full attack sequence with hit/wound/save rolls

**Phase 4: Charge Tests** (7 tests, 4 save files, 3 action handlers)
- Action handlers: `declare_charge`, `roll_charge_distance`, `end_charge_phase`
- Key test: 2D6 charge roll, move into engagement range

**Phase 5: Fight Tests** (12 tests, 9 save files, 6 action handlers)
- Action handlers: `select_fight_unit`, `pile_in`, `resolve_fight`, `consolidate`, `heroic_intervention`, `end_fight_phase`
- Key test: Alternating unit selection between players

**Phase 6: Phase Transition Tests** (6 tests, reuse existing saves)
- No new action handlers needed
- Test full phase cycle: Deployment → Command → Movement → ... → Scoring

**Phase 7: Full Game Smoke Tests** (2 tests, 1 save file)
- Test: Complete one full game round (all phases for both players)
- Test: Three complete rounds with performance monitoring

## Validation Gates

### Godot-Specific Testing Commands

```bash
# Run single test
cd 40k
export PATH="$HOME/bin:$PATH"
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gtest=test_basic_multiplayer_connection \
  -gexit

# Run all deployment tests
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gfile=test_multiplayer_deployment.gd \
  -gexit

# Run all integration tests (full suite)
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gexit

# Run with output filtering (useful for debugging)
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gtest=test_deployment_single_unit \
  -gexit 2>&1 | grep -E "PASSED|FAILED|success=|message="
```

### Success Criteria by Phase

**Phase 1 (Deployment) - MVP Goal**:
- ✅ All 10 deployment tests passing
- ✅ 0 flaky tests (tests pass consistently)
- ✅ Average test execution time < 60 seconds per test
- ✅ Network sync verified (actions appear on both clients within 1 second)

**Phase 2 (Movement)**:
- ✅ All 10 movement tests passing
- ✅ Coherency validation working
- ✅ Terrain interaction working

**Phases 3-5 (Shooting, Charge, Fight)**:
- ✅ All phase-specific tests passing
- ✅ Combat resolution working
- ✅ Dice rolls synchronized

**Phases 6-7 (Transitions, Smoke Tests)**:
- ✅ Full phase cycle works
- ✅ Multi-round games stable
- ✅ No memory leaks or performance degradation

### Performance Benchmarks

```
Individual Test: < 60 seconds
Phase Test Suite: < 5 minutes
Full Test Suite: < 30 minutes
Flake Rate: < 5%
Pass Rate: > 95%
```

## Implementation Order (Task Checklist)

### Week 1: Fix Deployment Test Blockers

**Day 1-2**:
- [ ] Task 1.1: Debug game auto-start phase initialization
- [ ] Add logging to track phase initialization sequence
- [ ] Verify PhaseManager transitions to Deployment on game start
- [ ] Add retry logic in TestModeHandler
- [ ] Run test: `test_basic_multiplayer_connection` should PASS

**Day 3**:
- [ ] Task 1.2: Verify TestModeHandler action handlers
- [ ] Test deploy_unit handler with valid/invalid inputs
- [ ] Add edge case handling
- [ ] Run test: `test_deployment_single_unit` should PASS

**Day 4**:
- [ ] Task 1.3: Add network sync verification
- [ ] Implement `verify_unit_synced()` helper method
- [ ] Update all deployment tests to verify sync
- [ ] Run all 10 deployment tests → target: 10/10 passing

**Day 5**:
- [ ] Fix any remaining deployment test failures
- [ ] Document lessons learned
- [ ] Commit deployment test fixes
- [ ] Update OUTSTANDING_WORK.md with progress

### Week 2-3: Movement Tests

**Day 6-7**:
- [ ] Create `tests/integration/test_multiplayer_movement.gd`
- [ ] Copy template from deployment tests
- [ ] Implement 10 test functions (stubs first)

**Day 8-9**:
- [ ] Create 6 movement test save files manually
- [ ] Verify saves load correctly
- [ ] Document save file creation process

**Day 10-12**:
- [ ] Implement 4 TestModeHandler action handlers for movement
- [ ] Test each handler individually
- [ ] Update `_execute_command()` routing

**Day 13-14**:
- [ ] Run movement tests, fix failures
- [ ] Verify network sync for movement actions
- [ ] Target: 10/10 movement tests passing

### Week 4-6: Shooting, Charge, Fight Tests

**Shooting (Days 15-21)**:
- [ ] Create test file with 12 test functions
- [ ] Create 9 shooting save files
- [ ] Implement 5 action handlers
- [ ] Run and fix tests → target: 12/12 passing

**Charge (Days 22-26)**:
- [ ] Create test file with 7 test functions
- [ ] Create 4 charge save files
- [ ] Implement 3 action handlers
- [ ] Run and fix tests → target: 7/7 passing

**Fight (Days 27-33)**:
- [ ] Create test file with 12 test functions
- [ ] Create 9 fight save files
- [ ] Implement 6 action handlers
- [ ] Handle alternating player selection
- [ ] Run and fix tests → target: 12/12 passing

### Week 7: Transitions and Smoke Tests

**Day 34-36**:
- [ ] Create `test_multiplayer_phase_transitions.gd`
- [ ] Implement 6 phase transition tests
- [ ] Run tests → target: 6/6 passing

**Day 37-40**:
- [ ] Create `test_multiplayer_full_game.gd`
- [ ] Implement 2 smoke tests (1 round, 3 rounds)
- [ ] Add performance monitoring
- [ ] Run tests → target: 2/2 passing

**Day 41-42**:
- [ ] Run full test suite (all 59 tests)
- [ ] Fix any flaky tests
- [ ] Document final results
- [ ] Update all status documents

## Risk Assessment and Mitigation

### High Risk Items

**Risk 1: Network Synchronization Bugs**
- **Issue**: Actions work locally but don't sync across network
- **Impact**: Tests pass but real multiplayer doesn't work
- **Mitigation**:
  - Add explicit sync verification to every test
  - Log all RPC calls with timestamps
  - Add network latency simulation (optional but recommended)

**Risk 2: Test Environment Instability**
- **Issue**: Tests pass/fail randomly (flaky tests)
- **Impact**: Loss of confidence in test results
- **Mitigation**:
  - Add retry logic with clear failure messages
  - Increase wait times for network operations
  - Use fixed random seeds for dice rolls (deterministic testing)

**Risk 3: Save File Corruption**
- **Issue**: Game updates break old save files
- **Impact**: Tests fail for wrong reasons
- **Mitigation**:
  - Version save files in filename (e.g., `movement_start_v1.w40ksave`)
  - Add save file validation before tests run
  - Regenerate saves when game data structures change

### Medium Risk Items

**Risk 4: Action Handler Complexity**
- **Issue**: Some actions require multiple steps (e.g., moving multi-model units)
- **Impact**: Handlers become too complex, hard to maintain
- **Mitigation**:
  - Keep handlers simple, delegate to GameManager
  - Document each handler's parameters and behavior
  - Add helper methods for common patterns

**Risk 5: Test Execution Time**
- **Issue**: 59 tests taking too long to run
- **Impact**: Developers won't run tests locally
- **Mitigation**:
  - Optimize wait times (use minimum necessary)
  - Run tests in parallel (separate process per test file)
  - Add quick smoke test suite (subset of critical tests)

## External Resources

### Godot Resources
- **Godot 4.4 Documentation**: https://docs.godotengine.org/en/4.4/
- **GUT Framework**: https://gut.readthedocs.io/en/latest/
- **Godot Multiplayer**: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html

### Warhammer 40k Rules
- **Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
  - Phase sequencing
  - Turn structure
  - Combat resolution

### Testing Best Practices
- Martin Fowler on Integration Testing: https://martinfowler.com/bliki/IntegrationTest.html
- Google Testing Blog: https://testing.googleblog.com/

## Quality Checklist

Before marking this PRP as complete:

- [ ] All 59 tests implemented
- [ ] All tests passing consistently (>95% pass rate)
- [ ] All test save files created and documented
- [ ] All TestModeHandler action handlers implemented
- [ ] Network sync verified for all action types
- [ ] Test execution time within benchmarks
- [ ] Flake rate < 5%
- [ ] Documentation updated (TESTING_GUIDE.md, OUTSTANDING_WORK.md)
- [ ] Code review completed
- [ ] CI/CD integration ready (optional)

## Confidence Score

**Confidence Level**: 7/10

**Reasoning**:
- ✅ **High Confidence**: Test infrastructure is solid, well-designed, already working
- ✅ **High Confidence**: GameManager methods already exist (deploy_unit, undo_last_action, complete_deployment)
- ✅ **High Confidence**: Pattern is established (deployment tests show how to structure tests)
- ⚠️ **Medium Confidence**: Network sync might reveal edge cases not covered by tests
- ⚠️ **Medium Confidence**: Phase initialization bug needs investigation
- ⚠️ **Medium Confidence**: Creating 28 test save files is manual and time-consuming

**Why 7/10 instead of 9/10**:
- Need to debug phase initialization issue before confident tests will pass
- Network sync verification pattern not yet validated in practice
- Large number of save files to create manually (error-prone)

**To reach 9/10**:
- Fix phase initialization blocker first (increases confidence in architecture)
- Validate one complete test phase (Movement) to prove pattern works
- Automate save file creation (scripted army deployment + save)

## Summary

This PRP provides a complete roadmap to finish the integration test suite. The infrastructure is excellent and the pattern is clear. The main challenges are:
1. **Immediate**: Fix phase initialization so tests can run
2. **Short-term**: Implement action handlers following the established pattern
3. **Medium-term**: Create test save files (manual but straightforward)
4. **Long-term**: Verify network sync and fix edge cases

**Estimated Total Time**:
- Aggressive (full-time): 7-8 weeks
- Realistic (part-time): 16-18 weeks

**Next Actions**:
1. Start with Phase 1 blockers (game auto-start)
2. Get first deployment test passing
3. Build momentum with remaining deployment tests
4. Expand to movement tests once pattern validated

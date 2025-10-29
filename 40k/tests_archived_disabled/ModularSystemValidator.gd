extends Node

# ModularSystemValidator - Comprehensive testing and validation for the modular phase system
# Run this script to verify that all components are working correctly

signal validation_completed(results: Dictionary)
signal test_failed(test_name: String, error: String)

var validation_results: Dictionary = {}
var current_test_count: int = 0
var total_tests: int = 0

func _ready() -> void:
	print("=== Modular System Validator ===")
	print("Testing modular phase system components...")
	run_all_tests()

func run_all_tests() -> void:
	validation_results = {
		"timestamp": Time.get_unix_time_from_system(),
		"tests_passed": 0,
		"tests_failed": 0,
		"test_results": {},
		"overall_status": "UNKNOWN"
	}
	
	var tests = [
		"test_autoload_availability",
		"test_gamestate_basic_functionality", 
		"test_gamestate_serialization",
		"test_phase_manager_initialization",
		"test_phase_transitions",
		"test_action_logger_functionality",
		"test_state_serializer",
		"test_replay_manager",
		"test_save_load_manager",
		"test_deployment_phase",
		"test_turn_manager_integration",
		"test_phase_stubs",
		"test_backwards_compatibility",
		"test_performance_benchmarks",
		"test_state_integrity"
	]
	
	total_tests = tests.size()
	current_test_count = 0
	
	for test_name in tests:
		run_test(test_name)
	
	_finalize_results()

func run_test(test_name: String) -> void:
	current_test_count += 1
	print("Running test %d/%d: %s" % [current_test_count, total_tests, test_name])
	
	var result = {"passed": false, "message": "", "details": {}}
	
	match test_name:
		"test_autoload_availability":
			result = test_autoload_availability()
		"test_gamestate_basic_functionality":
			result = test_gamestate_basic_functionality()
		"test_gamestate_serialization":
			result = test_gamestate_serialization()
		"test_phase_manager_initialization":
			result = test_phase_manager_initialization()
		"test_phase_transitions":
			result = test_phase_transitions()
		"test_action_logger_functionality":
			result = test_action_logger_functionality()
		"test_state_serializer":
			result = test_state_serializer()
		"test_replay_manager":
			result = test_replay_manager()
		"test_save_load_manager":
			result = test_save_load_manager()
		"test_deployment_phase":
			result = test_deployment_phase()
		"test_turn_manager_integration":
			result = test_turn_manager_integration()
		"test_phase_stubs":
			result = test_phase_stubs()
		"test_backwards_compatibility":
			result = test_backwards_compatibility()
		"test_performance_benchmarks":
			result = test_performance_benchmarks()
		"test_state_integrity":
			result = test_state_integrity()
		_:
			result = {"passed": false, "message": "Unknown test: " + test_name, "details": {}}
	
	validation_results.test_results[test_name] = result
	
	if result.passed:
		validation_results.tests_passed += 1
		print("  ✅ PASSED: %s" % result.message)
	else:
		validation_results.tests_failed += 1
		print("  ❌ FAILED: %s" % result.message)
		emit_signal("test_failed", test_name, result.message)

# Individual test implementations
func test_autoload_availability() -> Dictionary:
	var missing_autoloads = []
	var required_autoloads = [
		"GameState", "ActionLogger", "StateSerializer", 
		"ReplayManager", "SaveLoadManager", "PhaseManager", "TurnManager"
	]
	
	for autoload_name in required_autoloads:
		if not Engine.has_singleton(autoload_name):
			missing_autoloads.append(autoload_name)
	
	if missing_autoloads.size() == 0:
		return {"passed": true, "message": "All required autoloads available", "details": {"autoloads": required_autoloads}}
	else:
		return {"passed": false, "message": "Missing autoloads: " + str(missing_autoloads), "details": {"missing": missing_autoloads}}

func test_gamestate_basic_functionality() -> Dictionary:
	try:
		# Test basic GameState operations
		var initial_turn = GameState.get_turn_number()
		var initial_phase = GameState.get_current_phase()
		var initial_player = GameState.get_active_player()
		
		# Test state modification
		GameState.set_active_player(2)
		if GameState.get_active_player() != 2:
			return {"passed": false, "message": "Failed to set active player", "details": {}}
		
		# Test snapshot creation
		var snapshot = GameState.create_snapshot()
		if snapshot.is_empty() or not snapshot.has("meta"):
			return {"passed": false, "message": "Failed to create valid snapshot", "details": {}}
		
		# Test validation
		var validation = GameState.validate_state()
		if not validation.valid:
			return {"passed": false, "message": "State validation failed: " + str(validation.errors), "details": validation}
		
		# Restore initial state
		GameState.set_active_player(initial_player)
		
		return {"passed": true, "message": "GameState basic functionality working", "details": {"snapshot_size": snapshot.size()}}
	except:
		return {"passed": false, "message": "Exception in GameState basic functionality test", "details": {}}

func test_gamestate_serialization() -> Dictionary:
	try:
		var original_state = GameState.create_snapshot()
		var serialized = StateSerializer.serialize_game_state(original_state)
		
		if serialized.is_empty():
			return {"passed": false, "message": "Failed to serialize game state", "details": {}}
		
		var deserialized = StateSerializer.deserialize_game_state(serialized)
		if deserialized.is_empty():
			return {"passed": false, "message": "Failed to deserialize game state", "details": {}}
		
		# Basic comparison - ensure key sections exist
		var required_sections = ["meta", "board", "units", "players"]
		for section in required_sections:
			if not deserialized.has(section):
				return {"passed": false, "message": "Missing section after deserialization: " + section, "details": {}}
		
		return {"passed": true, "message": "GameState serialization working", "details": {"serialized_length": serialized.length()}}
	except:
		return {"passed": false, "message": "Exception in GameState serialization test", "details": {}}

func test_phase_manager_initialization() -> Dictionary:
	try:
		if not PhaseManager:
			return {"passed": false, "message": "PhaseManager not available", "details": {}}
		
		var current_phase = PhaseManager.get_current_phase()
		var phase_instance = PhaseManager.get_current_phase_instance()
		
		if phase_instance == null:
			return {"passed": false, "message": "No active phase instance", "details": {}}
		
		if not phase_instance.has_method("validate_action"):
			return {"passed": false, "message": "Phase instance missing required methods", "details": {}}
		
		return {"passed": true, "message": "PhaseManager initialized correctly", "details": {"current_phase": str(current_phase)}}
	except:
		return {"passed": false, "message": "Exception in PhaseManager initialization test", "details": {}}

func test_phase_transitions() -> Dictionary:
	try:
		var initial_phase = PhaseManager.get_current_phase()
		
		# Test transition to movement phase
		PhaseManager.transition_to_phase(GameStateData.Phase.MOVEMENT)
		await get_tree().process_frame  # Allow signals to process
		
		var new_phase = PhaseManager.get_current_phase()
		if new_phase != GameStateData.Phase.MOVEMENT:
			return {"passed": false, "message": "Failed to transition to movement phase", "details": {"expected": GameStateData.Phase.MOVEMENT, "actual": new_phase}}
		
		# Test transition back to deployment
		PhaseManager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
		await get_tree().process_frame
		
		var final_phase = PhaseManager.get_current_phase()
		if final_phase != GameStateData.Phase.DEPLOYMENT:
			return {"passed": false, "message": "Failed to transition back to deployment", "details": {}}
		
		return {"passed": true, "message": "Phase transitions working", "details": {"tested_transitions": 2}}
	except:
		return {"passed": false, "message": "Exception in phase transition test", "details": {}}

func test_action_logger_functionality() -> Dictionary:
	try:
		if not ActionLogger:
			return {"passed": false, "message": "ActionLogger not available", "details": {}}
		
		var initial_count = ActionLogger.get_all_session_actions().size()
		
		# Test logging an action
		var test_action = {
			"type": "TEST_ACTION",
			"player": 1,
			"timestamp": Time.get_unix_time_from_system()
		}
		
		ActionLogger.log_action(test_action)
		
		var actions_after = ActionLogger.get_all_session_actions()
		if actions_after.size() != initial_count + 1:
			return {"passed": false, "message": "Action not logged correctly", "details": {"before": initial_count, "after": actions_after.size()}}
		
		var logged_action = actions_after[-1]
		if not logged_action.has("_log_metadata"):
			return {"passed": false, "message": "Action metadata not added", "details": {}}
		
		return {"passed": true, "message": "ActionLogger functionality working", "details": {"actions_logged": actions_after.size()}}
	except:
		return {"passed": false, "message": "Exception in ActionLogger test", "details": {}}

func test_state_serializer() -> Dictionary:
	try:
		if not StateSerializer:
			return {"passed": false, "message": "StateSerializer not available", "details": {}}
		
		var test_state = {"test": "data", "number": 42, "array": [1, 2, 3]}
		var serialized = StateSerializer.serialize_game_state(test_state)
		
		if serialized.is_empty():
			return {"passed": false, "message": "Failed to serialize test state", "details": {}}
		
		var deserialized = StateSerializer.deserialize_game_state(serialized)
		if deserialized.is_empty():
			return {"passed": false, "message": "Failed to deserialize test state", "details": {}}
		
		# Test round-trip validation
		var validation = StateSerializer.validate_current_state()
		if not validation.serialization_successful:
			return {"passed": false, "message": "Serialization round-trip failed", "details": validation}
		
		return {"passed": true, "message": "StateSerializer working correctly", "details": validation}
	except:
		return {"passed": false, "message": "Exception in StateSerializer test", "details": {}}

func test_replay_manager() -> Dictionary:
	try:
		if not ReplayManager:
			return {"passed": false, "message": "ReplayManager not available", "details": {}}
		
		# Test loading replay from ActionLogger
		var load_success = ReplayManager.load_replay_from_action_logger()
		if not load_success:
			return {"passed": false, "message": "Failed to load replay from ActionLogger", "details": {}}
		
		var is_loaded = ReplayManager.is_replay_loaded()
		if not is_loaded:
			return {"passed": false, "message": "Replay not marked as loaded", "details": {}}
		
		var stats = ReplayManager.get_replay_statistics()
		if not stats.has("total_actions"):
			return {"passed": false, "message": "Invalid replay statistics", "details": stats}
		
		return {"passed": true, "message": "ReplayManager working correctly", "details": stats}
	except:
		return {"passed": false, "message": "Exception in ReplayManager test", "details": {}}

func test_save_load_manager() -> Dictionary:
	try:
		if not SaveLoadManager:
			return {"passed": false, "message": "SaveLoadManager not available", "details": {}}
		
		# Test quick save
		var save_success = SaveLoadManager.quick_save()
		if not save_success:
			return {"passed": false, "message": "Quick save failed", "details": {}}
		
		# Modify state slightly
		var original_player = GameState.get_active_player()
		GameState.set_active_player(3 - original_player)
		
		# Test quick load
		var load_success = SaveLoadManager.quick_load()
		if not load_success:
			return {"passed": false, "message": "Quick load failed", "details": {}}
		
		# Verify state was restored
		var restored_player = GameState.get_active_player()
		if restored_player != original_player:
			return {"passed": false, "message": "State not properly restored", "details": {"expected": original_player, "actual": restored_player}}
		
		return {"passed": true, "message": "SaveLoadManager working correctly", "details": {"save_load_successful": true}}
	except:
		return {"passed": false, "message": "Exception in SaveLoadManager test", "details": {}}

func test_deployment_phase() -> Dictionary:
	try:
		# Ensure we're in deployment phase
		PhaseManager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
		await get_tree().process_frame
		
		var phase_instance = PhaseManager.get_current_phase_instance()
		if not phase_instance:
			return {"passed": false, "message": "No deployment phase instance", "details": {}}
		
		# Test action validation
		var test_action = {
			"type": "DEPLOY_UNIT",
			"unit_id": "U_INTERCESSORS_A",
			"model_positions": [Vector2(100, 100)]
		}
		
		var validation = phase_instance.validate_action(test_action)
		if not validation.has("valid"):
			return {"passed": false, "message": "Invalid validation response", "details": validation}
		
		# Test available actions
		var available_actions = phase_instance.get_available_actions()
		if not available_actions is Array:
			return {"passed": false, "message": "Available actions not returned as array", "details": {}}
		
		return {"passed": true, "message": "DeploymentPhase working correctly", "details": {"available_actions": available_actions.size()}}
	except:
		return {"passed": false, "message": "Exception in DeploymentPhase test", "details": {}}

func test_turn_manager_integration() -> Dictionary:
	try:
		if not TurnManager:
			return {"passed": false, "message": "TurnManager not available", "details": {}}
		
		var game_status = TurnManager.get_game_status()
		if not game_status.has("turn") or not game_status.has("phase"):
			return {"passed": false, "message": "Invalid game status", "details": game_status}
		
		var current_phase = TurnManager.get_current_phase()
		var current_turn = TurnManager.get_current_turn()
		
		if current_phase < 0 or current_turn < 1:
			return {"passed": false, "message": "Invalid turn/phase values", "details": {"turn": current_turn, "phase": current_phase}}
		
		return {"passed": true, "message": "TurnManager integration working", "details": game_status}
	except:
		return {"passed": false, "message": "Exception in TurnManager integration test", "details": {}}

func test_phase_stubs() -> Dictionary:
	try:
		var phases_to_test = [
			GameStateData.Phase.MOVEMENT,
			GameStateData.Phase.SHOOTING,
			GameStateData.Phase.CHARGE,
			GameStateData.Phase.FIGHT,
			GameStateData.Phase.MORALE
		]
		
		var failed_phases = []
		
		for phase in phases_to_test:
			PhaseManager.transition_to_phase(phase)
			await get_tree().process_frame
			
			var instance = PhaseManager.get_current_phase_instance()
			if not instance:
				failed_phases.append(str(phase) + " (no instance)")
				continue
			
			if not instance.has_method("validate_action") or not instance.has_method("get_available_actions"):
				failed_phases.append(str(phase) + " (missing methods)")
				continue
		
		# Return to deployment phase
		PhaseManager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
		await get_tree().process_frame
		
		if failed_phases.size() > 0:
			return {"passed": false, "message": "Failed phase stubs: " + str(failed_phases), "details": {"failed": failed_phases}}
		
		return {"passed": true, "message": "All phase stubs working", "details": {"tested_phases": phases_to_test.size()}}
	except:
		return {"passed": false, "message": "Exception in phase stubs test", "details": {}}

func test_backwards_compatibility() -> Dictionary:
	try:
		# Test that old BoardState still exists and has expected methods
		if not BoardState:
			return {"passed": false, "message": "BoardState not available (backwards compatibility)", "details": {}}
		
		var has_required_methods = (
			BoardState.has_method("get_undeployed_units_for_player") and
			BoardState.has_method("all_units_deployed") and
			BoardState.has_method("get_deployment_zone_for_player")
		)
		
		if not has_required_methods:
			return {"passed": false, "message": "BoardState missing required methods", "details": {}}
		
		# Test that GameManager still exists
		if not GameManager:
			return {"passed": false, "message": "GameManager not available (backwards compatibility)", "details": {}}
		
		return {"passed": true, "message": "Backwards compatibility maintained", "details": {"boardstate_available": true, "gamemanager_available": true}}
	except:
		return {"passed": false, "message": "Exception in backwards compatibility test", "details": {}}

func test_performance_benchmarks() -> Dictionary:
	try:
		var start_time = Time.get_ticks_msec()
		
		# Test GameState snapshot performance
		var snapshot_start = Time.get_ticks_msec()
		for i in range(100):
			GameState.create_snapshot()
		var snapshot_time = Time.get_ticks_msec() - snapshot_start
		
		# Test serialization performance
		var serialize_start = Time.get_ticks_msec()
		var state = GameState.create_snapshot()
		for i in range(10):
			StateSerializer.serialize_game_state(state)
		var serialize_time = Time.get_ticks_msec() - serialize_start
		
		var total_time = Time.get_ticks_msec() - start_time
		
		var performance_data = {
			"snapshot_time_ms": snapshot_time,
			"serialize_time_ms": serialize_time,
			"total_test_time_ms": total_time
		}
		
		# Check for reasonable performance (arbitrary thresholds)
		if snapshot_time > 1000 or serialize_time > 5000:
			return {"passed": false, "message": "Performance below acceptable thresholds", "details": performance_data}
		
		return {"passed": true, "message": "Performance benchmarks acceptable", "details": performance_data}
	except:
		return {"passed": false, "message": "Exception in performance test", "details": {}}

func test_state_integrity() -> Dictionary:
	try:
		# Test that state modifications are consistent
		var initial_state = GameState.create_snapshot()
		var initial_turn = GameState.get_turn_number()
		var initial_player = GameState.get_active_player()
		
		# Make some modifications
		GameState.set_active_player(2)
		GameState.advance_turn()
		
		# Check that changes are reflected
		var new_turn = GameState.get_turn_number()
		var new_player = GameState.get_active_player()
		
		if new_turn != initial_turn + 1:
			return {"passed": false, "message": "Turn advancement not working", "details": {"expected": initial_turn + 1, "actual": new_turn}}
		
		if new_player != 2:
			return {"passed": false, "message": "Player change not working", "details": {"expected": 2, "actual": new_player}}
		
		# Test state validation
		var validation = GameState.validate_state()
		if not validation.valid:
			return {"passed": false, "message": "State integrity compromised", "details": validation}
		
		# Restore initial state
		GameState.load_from_snapshot(initial_state)
		
		return {"passed": true, "message": "State integrity maintained", "details": validation}
	except:
		return {"passed": false, "message": "Exception in state integrity test", "details": {}}

func _finalize_results() -> void:
	var success_rate = float(validation_results.tests_passed) / float(total_tests) * 100.0
	
	if validation_results.tests_failed == 0:
		validation_results.overall_status = "PASS"
	elif success_rate >= 80.0:
		validation_results.overall_status = "MOSTLY_PASS"
	else:
		validation_results.overall_status = "FAIL"
	
	print("\n=== Validation Results ===")
	print("Tests Passed: %d/%d (%.1f%%)" % [validation_results.tests_passed, total_tests, success_rate])
	print("Tests Failed: %d" % validation_results.tests_failed)
	print("Overall Status: %s" % validation_results.overall_status)
	
	if validation_results.tests_failed > 0:
		print("\nFailed Tests:")
		for test_name in validation_results.test_results:
			var result = validation_results.test_results[test_name]
			if not result.passed:
				print("  - %s: %s" % [test_name, result.message])
	
	emit_signal("validation_completed", validation_results)

# Utility method to run validation from code
func run_validation() -> Dictionary:
	run_all_tests()
	return validation_results
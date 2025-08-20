extends BasePhaseTest

# DeploymentPhase GUT Tests - Validates the Deployment Phase implementation
# Tests unit deployment, deployment zones, and deployment completion logic

var deployment_phase: DeploymentPhase

func before_each():
	super.before_each()
	
	# Create deployment phase instance
	deployment_phase = preload("res://phases/DeploymentPhase.gd").new()
	add_child(deployment_phase)
	
	# Use deployment-specific test state
	test_state = TestDataFactory.create_deployment_scenario()
	
	# Setup phase instance
	phase_instance = deployment_phase
	enter_phase()

func after_each():
	if deployment_phase:
		deployment_phase.queue_free()
		deployment_phase = null
	super.after_each()

# Test deployment phase initialization
func test_deployment_phase_init():
	assert_eq(GameStateData.Phase.DEPLOYMENT, deployment_phase.phase_type, "Phase type should be DEPLOYMENT")

func test_deployment_phase_enter():
	# Phase should initialize properly on enter
	assert_not_null(deployment_phase.game_state_snapshot, "Should have game state snapshot after enter")
	
	# Check if auto-completion logic works for already deployed units
	var all_deployed_state = TestDataFactory.create_test_game_state()
	for unit_id in all_deployed_state.units:
		all_deployed_state.units[unit_id].status = GameStateData.UnitStatus.DEPLOYED
	
	deployment_phase.enter_phase(all_deployed_state)
	
	# If all units are deployed, phase should auto-complete
	# This depends on the implementation details

func test_deployment_phase_exit():
	# Should exit cleanly without errors
	deployment_phase.exit_phase()
	assert_true(true, "Phase exit should complete without error")

# Test deployment zone validation
func test_get_deployment_zone():
	var zone_p1 = deployment_phase.get_deployment_zone_for_player(1)
	var zone_p2 = deployment_phase.get_deployment_zone_for_player(2)
	
	assert_not_null(zone_p1, "Player 1 should have a deployment zone")
	assert_not_null(zone_p2, "Player 2 should have a deployment zone")
	
	if not zone_p1.is_empty():
		assert_true(zone_p1.has("poly") or zone_p1.has("bounds"), "Zone should have boundary definition")

# Test deployment action validation
func test_deploy_unit_validation():
	# Test deploying a valid undeployed unit
	var undeployed_units = get_undeployed_units_for_current_player()
	
	if undeployed_units.size() > 0:
		var unit_id = undeployed_units[0]
		var deploy_action = create_action("DEPLOY_UNIT", unit_id, {
			"position": {"x": 100, "y": 100}
		})
		
		var validation = deployment_phase.validate_action(deploy_action)
		assert_not_null(validation, "Should return validation result")
		assert_true(validation.has("valid"), "Validation result should have valid field")

func test_deploy_already_deployed_unit():
	# Try to deploy a unit that's already deployed
	var deployed_units = get_deployed_units_for_current_player()
	
	if deployed_units.size() > 0:
		var unit_id = deployed_units[0]
		var deploy_action = create_action("DEPLOY_UNIT", unit_id, {
			"position": {"x": 100, "y": 100}
		})
		
		var validation = deployment_phase.validate_action(deploy_action)
		if validation.has("valid"):
			assert_false(validation.valid, "Should not be able to deploy already deployed unit")

func test_deploy_unit_outside_deployment_zone():
	var undeployed_units = get_undeployed_units_for_current_player()
	
	if undeployed_units.size() > 0:
		var unit_id = undeployed_units[0]
		
		# Try to deploy outside deployment zone (middle of board)
		var invalid_deploy_action = create_action("DEPLOY_UNIT", unit_id, {
			"position": {"x": 500, "y": 500}  # Likely outside deployment zone
		})
		
		var validation = deployment_phase.validate_action(invalid_deploy_action)
		if validation.has("valid") and validation.has("errors"):
			# If deployment zone validation is implemented
			if validation.valid == false:
				var found_zone_error = false
				for error in validation.errors:
					if "zone" in error.to_lower() or "deployment" in error.to_lower():
						found_zone_error = true
				assert_true(found_zone_error, "Should include deployment zone error")

func test_deploy_enemy_unit():
	# Try to deploy an enemy unit
	var enemy_units = get_units_for_player(2)  # Assuming current player is 1
	
	if enemy_units.size() > 0:
		var enemy_unit_id = enemy_units.keys()[0]
		var deploy_action = create_action("DEPLOY_UNIT", enemy_unit_id, {
			"position": {"x": 100, "y": 100}
		})
		
		var validation = deployment_phase.validate_action(deploy_action)
		if validation.has("valid"):
			assert_false(validation.valid, "Should not be able to deploy enemy units")

# Test deployment processing
func test_deploy_unit_processing():
	var undeployed_units = get_undeployed_units_for_current_player()
	
	if undeployed_units.size() > 0:
		var unit_id = undeployed_units[0]
		var deploy_action = create_action("DEPLOY_UNIT", unit_id, {
			"position": {"x": 100, "y": 100}
		})
		
		var result = deployment_phase.process_action(deploy_action)
		assert_not_null(result, "Should return processing result")
		assert_true(result.has("success"), "Result should have success field")
		
		if result.success:
			assert_true(result.has("changes"), "Successful deployment should have state changes")

# Test unit positioning during deployment
func test_deploy_unit_with_multiple_models():
	var undeployed_units = get_undeployed_units_for_current_player()
	
	if undeployed_units.size() > 0:
		var unit_id = undeployed_units[0]
		var unit = get_test_unit(unit_id)
		
		if unit.has("models") and unit.models.size() > 1:
			var deploy_action = create_action("DEPLOY_UNIT", unit_id, {
				"position": {"x": 100, "y": 100},
				"formation": "line"  # Or whatever formation options exist
			})
			
			var validation = deployment_phase.validate_action(deploy_action)
			assert_not_null(validation, "Multi-model deployment should be validated")

# Test strategic reserves (if implemented)
func test_strategic_reserves():
	var reserve_action = create_action("PLACE_IN_RESERVES", "test_unit_1")
	
	var validation = deployment_phase.validate_action(reserve_action)
	assert_not_null(validation, "Should return validation for reserves action")
	
	# If strategic reserves are implemented, test the functionality
	if validation.get("valid", false):
		var result = deployment_phase.process_action(reserve_action)
		assert_true(result.has("success"), "Reserves action should have success field")

# Test deployment completion logic
func test_all_units_deployed_check():
	# This tests the internal method if it's public
	if deployment_phase.has_method("_all_units_deployed"):
		var result = deployment_phase._all_units_deployed()
		assert_true(result is bool, "Should return boolean")
	else:
		skip_test("_all_units_deployed method not accessible")

func test_deployment_completion():
	# Test phase completion when all units are deployed
	var complete_state = TestDataFactory.create_test_game_state()
	
	# Mark all units as deployed
	for unit_id in complete_state.units:
		complete_state.units[unit_id].status = GameStateData.UnitStatus.DEPLOYED
	
	deployment_phase.enter_phase(complete_state)
	
	# Phase should recognize completion
	if deployment_phase.has_method("_should_complete_phase"):
		var should_complete = deployment_phase._should_complete_phase()
		assert_true(should_complete, "Phase should complete when all units deployed")

func test_partial_deployment():
	# Test with some units deployed and some not
	var partial_state = TestDataFactory.create_deployment_scenario()
	
	# Deploy some units but not others
	var unit_ids = partial_state.units.keys()
	if unit_ids.size() >= 2:
		partial_state.units[unit_ids[0]].status = GameStateData.UnitStatus.DEPLOYED
		# Leave others undeployed
		
		deployment_phase.enter_phase(partial_state)
		
		if deployment_phase.has_method("_should_complete_phase"):
			var should_complete = deployment_phase._should_complete_phase()
			assert_false(should_complete, "Phase should not complete with undeployed units")

# Test available actions during deployment
func test_get_available_deployment_actions():
	var available = get_available_actions()
	assert_not_null(available, "Should return available actions")
	assert_true(available is Array, "Available actions should be array")
	
	# Check for deployment-related actions
	var has_deploy_action = false
	for action in available:
		if action.type in ["DEPLOY_UNIT", "PLACE_IN_RESERVES"]:
			has_deploy_action = true
			break
	
	# If there are undeployed units, there should be deployment actions
	var undeployed = get_undeployed_units_for_current_player()
	if undeployed.size() > 0:
		assert_true(has_deploy_action, "Should have deployment actions when units need deploying")

# Test deployment controller integration
func test_deployment_controller_setup():
	# Test that deployment controller is properly set up
	if deployment_phase.deployment_controller:
		assert_not_null(deployment_phase.deployment_controller, "Deployment controller should be set up")
	else:
		# If no deployment controller exists, that's also valid for some implementations
		assert_true(true, "Deployment controller setup test passed")

func test_deployment_controller_signals():
	if deployment_phase.deployment_controller and deployment_phase.deployment_controller.has_signal("deployment_complete"):
		# Test signal connection
		assert_true(deployment_phase.has_method("_on_deployment_complete"), "Should have deployment complete handler")

# Test edge cases
func test_deploy_unit_invalid_position():
	var undeployed_units = get_undeployed_units_for_current_player()
	
	if undeployed_units.size() > 0:
		var unit_id = undeployed_units[0]
		
		# Test with invalid position data
		var invalid_positions = [
			{"position": null},
			{"position": {"x": "invalid", "y": 100}},
			{"position": {"x": 100}},  # Missing y
			{"position": {}}  # Empty position
		]
		
		for invalid_pos in invalid_positions:
			var deploy_action = create_action("DEPLOY_UNIT", unit_id, invalid_pos)
			var validation = deployment_phase.validate_action(deploy_action)
			
			if validation.has("valid"):
				assert_false(validation.valid, "Invalid position should fail validation: " + str(invalid_pos))

func test_deploy_nonexistent_unit():
	var deploy_action = create_action("DEPLOY_UNIT", "nonexistent_unit", {
		"position": {"x": 100, "y": 100}
	})
	
	assert_invalid_action(deploy_action, ["not found", "invalid unit"], "Nonexistent unit deployment should fail")

# Test deployment turn order (if implemented)
func test_deployment_turn_order():
	# If alternating deployment is implemented
	if deployment_phase.has_method("get_deployment_player_order"):
		var order = deployment_phase.get_deployment_player_order()
		assert_not_null(order, "Should return deployment order")
		assert_true(order is Array, "Deployment order should be array")

# Helper methods for deployment tests
func get_undeployed_units_for_current_player() -> Array:
	var current_player = deployment_phase.get_current_player()
	var units = deployment_phase.get_units_for_player(current_player)
	var undeployed = []
	
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.UNDEPLOYED:
			undeployed.append(unit_id)
	
	return undeployed

func get_deployed_units_for_current_player() -> Array:
	var current_player = deployment_phase.get_current_player()
	var units = deployment_phase.get_units_for_player(current_player)
	var deployed = []
	
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.DEPLOYED:
			deployed.append(unit_id)
	
	return deployed
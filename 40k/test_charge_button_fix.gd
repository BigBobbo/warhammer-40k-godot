#!/usr/bin/env godot
# Test script to verify charge buttons remain visible after first unit charges
extends SceneTree

func _ready():
	print("Testing charge button visibility fix...")
	
	# Initialize game state
	var game_state = load("res://scripts/GameState.gd").new()
	var phase_manager = load("res://autoloads/PhaseManager.gd").new()
	
	# Create test scenario with units that can charge
	var test_state = {
		"meta": {"current_phase": "CHARGE", "active_player": 1, "turn_number": 1},
		"units": {
			"unit1": {
				"id": "unit1",
				"owner": 1,
				"meta": {"name": "Test Unit 1"},
				"models": [{"id": "m1", "alive": true, "position": {"x": 100, "y": 100}}]
			},
			"unit2": {
				"id": "unit2", 
				"owner": 1,
				"meta": {"name": "Test Unit 2"},
				"models": [{"id": "m2", "alive": true, "position": {"x": 200, "y": 100}}]
			},
			"enemy1": {
				"id": "enemy1",
				"owner": 2,
				"meta": {"name": "Enemy Unit"},
				"models": [{"id": "e1", "alive": true, "position": {"x": 300, "y": 100}}]
			}
		},
		"board": {"deployment_zones": []}
	}
	
	# Initialize ChargePhase
	var charge_phase = load("res://phases/ChargePhase.gd").new()
	charge_phase.phase_type = GameStateData.Phase.CHARGE
	charge_phase.enter_phase(test_state)
	
	print("Initial eligible charge units: ", charge_phase.get_eligible_charge_units())
	print("Initial completed charges: ", charge_phase.get_completed_charges())
	
	# Simulate first unit completing a charge
	var complete_action = {
		"type": "COMPLETE_UNIT_CHARGE",
		"actor_unit_id": "unit1"
	}
	
	print("\nProcessing COMPLETE_UNIT_CHARGE for unit1...")
	var result = charge_phase.execute_action(complete_action)
	print("Result: ", result)
	
	print("After first charge - Eligible units: ", charge_phase.get_eligible_charge_units())
	print("After first charge - Completed charges: ", charge_phase.get_completed_charges())
	
	# Verify unit2 is still eligible
	var remaining_eligible = charge_phase.get_eligible_charge_units()
	if remaining_eligible.has("unit2"):
		print("SUCCESS: unit2 can still charge after unit1 completed")
	else:
		print("FAILURE: unit2 cannot charge after unit1 completed")
	
	# Test second unit selection
	var select_action = {
		"type": "SELECT_CHARGE_UNIT",
		"actor_unit_id": "unit2"
	}
	
	print("\nProcessing SELECT_CHARGE_UNIT for unit2...")
	var select_result = charge_phase.execute_action(select_action)
	print("Result: ", select_result)
	
	if select_result.get("success", false):
		print("SUCCESS: Can select second unit for charge")
	else:
		print("FAILURE: Cannot select second unit for charge")
	
	print("\n=== CHARGE BUTTON VISIBILITY FIX TEST COMPLETE ===")
	print("The UI container cleanup code has been removed from ChargeController._handle_mouse_release()")
	print("This should prevent charge buttons from disappearing after the first unit charges.")
	
	# Exit the test
	quit()
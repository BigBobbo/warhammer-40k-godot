extends GutTest

# Integration test for complete melee combat flow
# Tests the fixes from GitHub Issue #32 in a full combat scenario

var test_game_state: GameStateData
var fight_phase: FightPhase
var fight_controller: FightController

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	test_game_state = GameStateData.new()
	fight_phase = FightPhase.new()
	fight_controller = FightController.new()
	
	# Setup test board state
	_setup_test_combat_scenario()

func after_each():
	if fight_controller:
		fight_controller.free()
	if fight_phase:
		fight_phase.free()
	if test_game_state:
		test_game_state.free()

func test_full_melee_combat_display():
	# Test complete melee combat from selection to dice display
	var fight_controller = _setup_fight_controller()
	var fight_phase = _setup_test_fight_phase()
	
	# Simulate complete combat sequence
	var success = _simulate_combat_sequence(fight_controller, fight_phase)
	
	assert_true(success, "Combat sequence should complete successfully")
	
	# Verify dice display shows proper results
	if fight_controller.dice_log_display:
		var dice_log_text = fight_controller.dice_log_display.get_parsed_text()
		assert_true("hit" in dice_log_text.to_lower(), "Dice log should contain hit information")
		assert_true("wound" in dice_log_text.to_lower(), "Dice log should contain wound information")

func test_melee_dice_integration():
	# Test that melee dice results are properly formatted and displayed
	fight_controller.set_phase(fight_phase)
	
	# Create test dice data matching our new format
	var test_hit_data = {
		"context": "hit_roll_melee",
		"rolls_raw": [3, 6, 2, 5, 4],
		"successes": 4,
		"target": 3,
		"weapon": "chainsword",
		"total_attacks": 5
	}
	
	var test_wound_data = {
		"context": "wound_roll", 
		"rolls_raw": [4, 6, 3, 5],
		"successes": 3,
		"target": 4,
		"weapon": "chainsword",
		"strength": 4,
		"toughness": 5
	}
	
	var test_save_data = {
		"context": "armor_save",
		"rolls_raw": [2, 5, 4],
		"successes": 1,
		"failures": 2,
		"target": 5,
		"weapon": "chainsword",
		"ap": -1,
		"original_save": 6
	}
	
	# Test that controller handles dice results without errors
	fight_controller._on_dice_rolled(test_hit_data)
	fight_controller._on_dice_rolled(test_wound_data)
	fight_controller._on_dice_rolled(test_save_data)
	
	# Verify log display was updated
	if fight_controller.dice_log_display:
		var log_text = fight_controller.dice_log_display.get_parsed_text()
		assert_gt(log_text.length(), 0, "Dice log should have content")
		assert_true("Chainsword" in log_text, "Should display weapon name")
		assert_true("4/5 hits" in log_text, "Should display hit ratio")

func test_debug_mode_integration():
	# Test debug mode toggle integration
	fight_controller.set_phase(fight_phase)
	
	# Test initial debug mode state
	assert_false(fight_phase.melee_debug_mode, "Debug mode should be off initially")
	
	# Simulate debug mode toggle
	fight_controller._on_debug_mode_toggled(true)
	assert_true(fight_phase.melee_debug_mode, "Debug mode should be enabled")
	
	# Test debug logging works
	fight_phase.log_melee_debug("Test debug message")
	
	# Toggle off
	fight_controller._on_debug_mode_toggled(false)
	assert_false(fight_phase.melee_debug_mode, "Debug mode should be disabled")

func test_weapon_grouping_display():
	# Test that duplicate weapons are properly grouped in display
	fight_controller.set_phase(fight_phase)
	
	# Create test data for same weapon used multiple times
	var test_hit_data1 = {
		"context": "hit_roll_melee",
		"rolls_raw": [4, 6],
		"successes": 2,
		"target": 3,
		"weapon": "chainsword",
		"total_attacks": 2
	}
	
	var test_hit_data2 = {
		"context": "hit_roll_melee", 
		"rolls_raw": [3, 5, 2],
		"successes": 2,
		"target": 3,
		"weapon": "chainsword",
		"total_attacks": 3
	}
	
	# Process multiple attacks with same weapon
	fight_controller._on_dice_rolled(test_hit_data1)
	fight_controller._on_dice_rolled(test_hit_data2)
	
	if fight_controller.dice_log_display:
		var log_text = fight_controller.dice_log_display.get_parsed_text()
		# Should see both attack sequences for the same weapon
		var chainsword_mentions = log_text.count("Chainsword")
		assert_ge(chainsword_mentions, 2, "Should show multiple chainsword attacks")

func test_mathhammer_prediction_display():
	# Test mathhammer prediction display format
	fight_controller.set_phase(fight_phase)
	
	var prediction_data = {
		"context": "mathhammer_prediction",
		"message": "Mathhammer Predictions:\nChainsword → Ork Boyz: 2.3 expected wounds\nTotal: 2.3 wounds"
	}
	
	fight_controller._on_dice_rolled(prediction_data)
	
	if fight_controller.dice_log_display:
		var log_text = fight_controller.dice_log_display.get_parsed_text()
		assert_true("Mathhammer" in log_text, "Should display mathhammer prediction")
		assert_true("expected wounds" in log_text, "Should show wound expectation")

func test_resolution_start_display():
	# Test resolution start message display
	fight_controller.set_phase(fight_phase)
	
	var resolution_data = {
		"context": "resolution_start",
		"message": "Beginning melee combat resolution..."
	}
	
	fight_controller._on_dice_rolled(resolution_data)
	
	if fight_controller.dice_log_display:
		var log_text = fight_controller.dice_log_display.get_parsed_text()
		assert_true("Beginning melee combat" in log_text, "Should display resolution start message")

# Helper functions

func _setup_test_combat_scenario():
	# Create a basic combat scenario with Space Marines vs Orks
	var board_state = {
		"units": {
			"space_marine_tactical": {
				"meta": {
					"name": "Tactical Squad",
					"stats": {
						"weapon_skill": 3,
						"strength": 4,
						"toughness": 4,
						"wounds": 2,
						"attacks": 2,
						"leadership": 7,
						"save": 3
					}
				},
				"models": [
					{
						"id": "0",
						"alive": true,
						"wounds": 2,
						"position": {"x": 100, "y": 100}
					}
				],
				"owner": 1
			},
			"ork_boyz": {
				"meta": {
					"name": "Ork Boyz",
					"stats": {
						"weapon_skill": 5,
						"strength": 4,
						"toughness": 5,
						"wounds": 1,
						"attacks": 2,
						"leadership": 6,
						"save": 6
					}
				},
				"models": [
					{
						"id": "0",
						"alive": true,
						"wounds": 1,
						"position": {"x": 125, "y": 100}
					}
				],
				"owner": 2
			}
		}
	}
	
	test_game_state.update_state(board_state)

func _setup_fight_controller() -> FightController:
	var controller = FightController.new()
	
	# Create minimal UI structure for testing
	controller.dice_log_display = RichTextLabel.new()
	controller.dice_log_display.bbcode_enabled = true
	
	return controller

func _setup_test_fight_phase() -> FightPhase:
	var phase = FightPhase.new()
	phase.game_state_snapshot = test_game_state.get_state()
	return phase

func _simulate_combat_sequence(controller: FightController, phase: FightPhase) -> bool:
	# Simplified combat sequence simulation
	try:
		# Setup phase connection
		controller.set_phase(phase)
		
		# Simulate unit selection
		var select_action = {
			"type": "SELECT_FIGHTER",
			"unit_id": "space_marine_tactical"
		}
		var result = phase.process_action(select_action)
		
		if not result.get("success", false):
			return false
		
		# Simulate attack assignment
		var attack_action = {
			"type": "ASSIGN_ATTACKS",
			"unit_id": "space_marine_tactical",
			"payload": {
				"target_unit_id": "ork_boyz",
				"weapon_id": "chainsword",
				"model_ids": ["0"]
			}
		}
		result = phase.process_action(attack_action)
		
		if not result.get("success", false):
			return false
		
		# Simulate attack confirmation
		var confirm_action = {
			"type": "CONFIRM_AND_RESOLVE_ATTACKS"
		}
		result = phase.process_action(confirm_action)
		
		if not result.get("success", false):
			return false
		
		# Simulate dice rolling
		var dice_action = {
			"type": "ROLL_DICE"
		}
		result = phase.process_action(dice_action)
		
		return result.get("success", false)
		
	except:
		return false
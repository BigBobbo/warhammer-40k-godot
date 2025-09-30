extends GutTest

# Test melee dice display format and functionality
# Tests the fixes from GitHub Issue #32

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

func test_melee_dice_format():
	# Test dice result format matches expected structure
	var rng = RulesEngine.RNGService.new()
	var action = _create_test_melee_action()
	var board = _create_test_board_state()
	
	var result = RulesEngine.resolve_melee_attacks(action, board, rng)
	
	assert_true(result.success, "Melee resolution should succeed")
	assert_gt(result.dice.size(), 0, "Should have dice results")
	
	# Check hit roll format
	var hit_result = null
	for dice_entry in result.dice:
		if dice_entry.context == "hit_roll_melee":
			hit_result = dice_entry
			break
	
	assert_not_null(hit_result, "Should have hit roll result")
	assert_eq(hit_result.context, "hit_roll_melee")
	assert_true(hit_result.has("rolls_raw"), "Should have rolls_raw field")
	assert_true(hit_result.has("successes"), "Should have successes field")
	assert_true(hit_result.has("target"), "Should have target field")
	assert_true(hit_result.has("weapon"), "Should have weapon field")
	assert_true(hit_result.has("total_attacks"), "Should have total_attacks field")
	
	# Verify data types
	assert_true(hit_result.rolls_raw is Array, "rolls_raw should be Array")
	assert_true(hit_result.successes is int, "successes should be int")
	assert_true(hit_result.target is int, "target should be int")
	assert_true(hit_result.total_attacks is int, "total_attacks should be int")

func test_wound_roll_format():
	# Test wound roll dice format
	var rng = RulesEngine.RNGService.new()
	var action = _create_test_melee_action()
	var board = _create_test_board_state()
	
	var result = RulesEngine.resolve_melee_attacks(action, board, rng)
	
	# Find wound roll result
	var wound_result = null
	for dice_entry in result.dice:
		if dice_entry.context == "wound_roll":
			wound_result = dice_entry
			break
	
	if wound_result:  # Only test if there were hits that led to wound rolls
		assert_eq(wound_result.context, "wound_roll")
		assert_true(wound_result.has("rolls_raw"), "Should have rolls_raw field")
		assert_true(wound_result.has("successes"), "Should have successes field")
		assert_true(wound_result.has("target"), "Should have target field")
		assert_true(wound_result.has("weapon"), "Should have weapon field")
		assert_true(wound_result.has("strength"), "Should have strength field")
		assert_true(wound_result.has("toughness"), "Should have toughness field")

func test_save_roll_format():
	# Test armor save dice format
	var rng = RulesEngine.RNGService.new()
	var action = _create_test_melee_action()
	var board = _create_test_board_state()
	
	var result = RulesEngine.resolve_melee_attacks(action, board, rng)
	
	# Find save roll result
	var save_result = null
	for dice_entry in result.dice:
		if dice_entry.context == "armor_save":
			save_result = dice_entry
			break
	
	if save_result:  # Only test if there were wounds that led to save rolls
		assert_eq(save_result.context, "armor_save")
		assert_true(save_result.has("rolls_raw"), "Should have rolls_raw field")
		assert_true(save_result.has("successes"), "Should have successes field")
		assert_true(save_result.has("failures"), "Should have failures field")
		assert_true(save_result.has("target"), "Should have target field")
		assert_true(save_result.has("weapon"), "Should have weapon field")
		assert_true(save_result.has("ap"), "Should have ap field")
		assert_true(save_result.has("original_save"), "Should have original_save field")

func test_debug_mode_toggle():
	var fight_phase = FightPhase.new()
	
	# Test initial state
	assert_false(fight_phase.melee_debug_mode, "Debug mode should be off by default")
	
	# Test enabling debug mode
	fight_phase.set_melee_debug_mode(true)
	assert_true(fight_phase.melee_debug_mode, "Debug mode should be enabled")
	
	# Test disabling debug mode
	fight_phase.set_melee_debug_mode(false)
	assert_false(fight_phase.melee_debug_mode, "Debug mode should be disabled")

func test_dice_rolls_contain_proper_data():
	# Test that rolls_raw contains actual dice results
	var rng = RulesEngine.RNGService.new()
	var action = _create_test_melee_action()
	var board = _create_test_board_state()
	
	var result = RulesEngine.resolve_melee_attacks(action, board, rng)
	
	# Check hit roll data
	var hit_result = null
	for dice_entry in result.dice:
		if dice_entry.context == "hit_roll_melee":
			hit_result = dice_entry
			break
	
	assert_not_null(hit_result, "Should have hit roll result")
	assert_gt(hit_result.rolls_raw.size(), 0, "Should have actual dice rolls")
	
	# Verify dice rolls are valid (1-6)
	for roll in hit_result.rolls_raw:
		assert_ge(roll, 1, "Dice roll should be at least 1")
		assert_le(roll, 6, "Dice roll should be at most 6")
	
	# Verify successes calculation
	var expected_successes = 0
	for roll in hit_result.rolls_raw:
		if roll >= hit_result.target:
			expected_successes += 1
	
	assert_eq(hit_result.successes, expected_successes, "Successes should match manual count")

# Helper functions to create test data
func _create_test_melee_action() -> Dictionary:
	return {
		"type": "FIGHT",
		"actor_unit_id": "test_space_marine",
		"payload": {
			"assignments": [
				{
					"attacker": "test_space_marine",
					"target": "test_ork",
					"weapon": "chainsword",
					"models": ["0"]
				}
			]
		}
	}

func _create_test_board_state() -> Dictionary:
	return {
		"units": {
			"test_space_marine": {
				"meta": {
					"name": "Test Space Marine",
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
			"test_ork": {
				"meta": {
					"name": "Test Ork",
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

func _create_test_weapon_profiles() -> Dictionary:
	return {
		"chainsword": {
			"name": "Chainsword",
			"type": "Melee",
			"range": "Melee",
			"attacks": 3,
			"weapon_skill": 3,
			"strength": 4,
			"ap": -1,
			"damage": 1
		}
	}
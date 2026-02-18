extends "res://addons/gut/test.gd"

# Tests for the HAZARDOUS weapon keyword implementation (T2-3)
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k 10e rules:
# After attacking with a Hazardous weapon, roll D6 per weapon fired.
# On a 1: CHARACTER/VEHICLE/MONSTER takes 3 mortal wounds, other models are slain.

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node
var game_state: Node

func before_each():
	# Verify autoloads are available
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return

	# Get actual autoload singletons
	rules_engine = AutoloadHelper.get_rules_engine()
	game_state = AutoloadHelper.get_game_state()

	assert_not_null(rules_engine, "RulesEngine autoload must be available")
	assert_not_null(game_state, "GameState autoload must be available")

# ==========================================
# is_hazardous_weapon() Tests — Built-in Weapon Profiles
# ==========================================

func test_is_hazardous_returns_true_for_hazardous_plasma():
	"""Test that hazardous_plasma is recognized as Hazardous"""
	var result = rules_engine.is_hazardous_weapon("hazardous_plasma")
	assert_true(result, "hazardous_plasma should be recognized as a Hazardous weapon")

func test_is_hazardous_returns_true_for_hazardous_rapid_fire():
	"""Test that hazardous_rapid_fire is recognized as Hazardous"""
	var result = rules_engine.is_hazardous_weapon("hazardous_rapid_fire")
	assert_true(result, "hazardous_rapid_fire should be recognized as a Hazardous weapon")

func test_is_hazardous_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT Hazardous"""
	var result = rules_engine.is_hazardous_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be Hazardous")

func test_is_hazardous_returns_false_for_lascannon():
	"""Test that lascannon is NOT Hazardous"""
	var result = rules_engine.is_hazardous_weapon("lascannon")
	assert_false(result, "lascannon should NOT be Hazardous")

func test_is_hazardous_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.is_hazardous_weapon("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# is_hazardous_weapon() Tests — Board Weapon with special_rules
# ==========================================

func test_is_hazardous_from_special_rules():
	"""Test that Hazardous is detected from special_rules string (army list format)"""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"id": "plasma_incinerator",
						"name": "Plasma Incinerator",
						"range": "24",
						"attacks": "2",
						"ballistic_skill": "3",
						"strength": "7",
						"ap": "-2",
						"damage": "1",
						"special_rules": "Hazardous, Rapid Fire 1",
						"keywords": []
					}]
				}
			}
		}
	}
	var result = rules_engine.is_hazardous_weapon("plasma_incinerator", board)
	assert_true(result, "Weapon with 'Hazardous' in special_rules should be detected")

func test_is_hazardous_case_insensitive():
	"""Test that Hazardous detection is case-insensitive"""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"id": "test_haz",
						"name": "Test Haz",
						"range": "24",
						"attacks": "1",
						"ballistic_skill": "3",
						"strength": "7",
						"ap": "-2",
						"damage": "1",
						"special_rules": "HAZARDOUS",
						"keywords": []
					}]
				}
			}
		}
	}
	var result = rules_engine.is_hazardous_weapon("test_haz", board)
	assert_true(result, "HAZARDOUS (uppercase) in special_rules should be detected")

# ==========================================
# resolve_hazardous_check() Tests — No Hazardous
# ==========================================

func test_resolve_hazardous_check_returns_false_for_non_hazardous_weapon():
	"""Test that non-hazardous weapons return hazardous_triggered = false"""
	var board = _create_test_board_with_unit("test_unit", 3)
	var rng = RulesEngine.RNGService.new(42)
	var result = rules_engine.resolve_hazardous_check("test_unit", "bolt_rifle", 3, board, rng)
	assert_false(result.hazardous_triggered, "Non-hazardous weapon should not trigger")

# ==========================================
# resolve_hazardous_check() Tests — Hazardous rolls
# ==========================================

func test_resolve_hazardous_check_rolls_d6_per_model():
	"""Test that Hazardous check rolls one D6 per model that fired"""
	var board = _create_test_board_with_unit("test_unit", 3)
	var rng = RulesEngine.RNGService.new(42)
	var result = rules_engine.resolve_hazardous_check("test_unit", "hazardous_plasma", 3, board, rng)
	# Should have rolled 3 dice (one per model)
	assert_eq(result.rolls.size(), 3, "Should roll 3 D6 for 3 models that fired")

func test_resolve_hazardous_check_safe_when_no_ones():
	"""Test that Hazardous check is safe when no 1s are rolled"""
	# Use a seed that produces no 1s
	var board = _create_test_board_with_unit("test_unit", 1)
	# We need to find a seed that doesn't roll a 1
	var safe_seed = _find_seed_with_no_ones(1, 100)
	var rng = RulesEngine.RNGService.new(safe_seed)
	var result = rules_engine.resolve_hazardous_check("test_unit", "hazardous_plasma", 1, board, rng)
	assert_false(result.hazardous_triggered, "No 1s rolled should mean safe")
	assert_eq(result.ones_rolled, 0, "Should have zero ones")

func test_resolve_hazardous_check_triggers_on_roll_of_1():
	"""Test that Hazardous check triggers when a 1 is rolled"""
	var board = _create_test_board_with_unit("test_unit", 1)
	# Find a seed that rolls a 1
	var bad_seed = _find_seed_with_ones(1, 100)
	var rng = RulesEngine.RNGService.new(bad_seed)
	var result = rules_engine.resolve_hazardous_check("test_unit", "hazardous_plasma", 1, board, rng)
	assert_true(result.hazardous_triggered, "Rolling a 1 should trigger Hazardous")
	assert_gt(result.ones_rolled, 0, "Should have at least one 1 rolled")

# ==========================================
# resolve_hazardous_check() Tests — CHARACTER/VEHICLE/MONSTER = 3 MW
# ==========================================

func test_hazardous_character_takes_3_mortal_wounds():
	"""Test that CHARACTER unit takes 3 mortal wounds per 1 rolled"""
	var board = _create_test_board_with_character_unit("char_unit", 1, 4)  # 1 model, 4 wounds
	var bad_seed = _find_seed_with_ones(1, 100)
	var rng = RulesEngine.RNGService.new(bad_seed)
	var result = rules_engine.resolve_hazardous_check("char_unit", "hazardous_plasma", 1, board, rng)
	assert_true(result.hazardous_triggered, "Should trigger on CHARACTER")
	# Should have diffs that apply damage
	assert_gt(result.diffs.size(), 0, "CHARACTER should receive mortal wound diffs")
	# Check dice log contains mortal_wounds damage type
	var found_mw_dice = false
	for dice in result.dice:
		if dice.get("context", "") == "hazardous_damage":
			assert_eq(dice.get("damage_type", ""), "mortal_wounds", "Damage type should be mortal_wounds for CHARACTER")
			assert_eq(dice.get("mortal_wounds", 0), 3, "Should be 3 mortal wounds per 1")
			found_mw_dice = true
	assert_true(found_mw_dice, "Should have hazardous_damage dice entry")

func test_hazardous_vehicle_takes_3_mortal_wounds():
	"""Test that VEHICLE unit takes 3 mortal wounds per 1 rolled"""
	var board = _create_test_board_with_keyword_unit("veh_unit", 1, 10, ["VEHICLE"])
	var bad_seed = _find_seed_with_ones(1, 100)
	var rng = RulesEngine.RNGService.new(bad_seed)
	var result = rules_engine.resolve_hazardous_check("veh_unit", "hazardous_plasma", 1, board, rng)
	assert_true(result.hazardous_triggered, "Should trigger on VEHICLE")
	var found_mw_dice = false
	for dice in result.dice:
		if dice.get("context", "") == "hazardous_damage":
			assert_eq(dice.get("damage_type", ""), "mortal_wounds", "Damage type should be mortal_wounds for VEHICLE")
			found_mw_dice = true
	assert_true(found_mw_dice, "Should have hazardous_damage dice entry")

func test_hazardous_monster_takes_3_mortal_wounds():
	"""Test that MONSTER unit takes 3 mortal wounds per 1 rolled"""
	var board = _create_test_board_with_keyword_unit("mon_unit", 1, 8, ["MONSTER"])
	var bad_seed = _find_seed_with_ones(1, 100)
	var rng = RulesEngine.RNGService.new(bad_seed)
	var result = rules_engine.resolve_hazardous_check("mon_unit", "hazardous_plasma", 1, board, rng)
	assert_true(result.hazardous_triggered, "Should trigger on MONSTER")
	var found_mw_dice = false
	for dice in result.dice:
		if dice.get("context", "") == "hazardous_damage":
			assert_eq(dice.get("damage_type", ""), "mortal_wounds", "Damage type should be mortal_wounds for MONSTER")
			found_mw_dice = true
	assert_true(found_mw_dice, "Should have hazardous_damage dice entry")

# ==========================================
# resolve_hazardous_check() Tests — Other models = 1 model slain
# ==========================================

func test_hazardous_non_character_loses_model():
	"""Test that non-CHARACTER/VEHICLE/MONSTER unit loses 1 model per 1 rolled"""
	var board = _create_test_board_with_unit("reg_unit", 5)  # 5 infantry models
	var bad_seed = _find_seed_with_ones(1, 100)
	var rng = RulesEngine.RNGService.new(bad_seed)
	var result = rules_engine.resolve_hazardous_check("reg_unit", "hazardous_plasma", 1, board, rng)
	assert_true(result.hazardous_triggered, "Should trigger on regular unit")
	# Check dice log contains slay_model damage type
	var found_slay_dice = false
	for dice in result.dice:
		if dice.get("context", "") == "hazardous_damage":
			assert_eq(dice.get("damage_type", ""), "slay_model", "Damage type should be slay_model for regular unit")
			found_slay_dice = true
	assert_true(found_slay_dice, "Should have hazardous_damage dice entry")
	# Should have a diff that kills a model
	var found_death_diff = false
	for diff in result.diffs:
		if diff.get("path", "").ends_with(".alive") and diff.get("value", true) == false:
			found_death_diff = true
	assert_true(found_death_diff, "Should have a diff that kills a model")

# ==========================================
# resolve_hazardous_check() Tests — Dice log
# ==========================================

func test_hazardous_check_produces_dice_log():
	"""Test that Hazardous check always produces a dice log entry"""
	var board = _create_test_board_with_unit("test_unit", 2)
	var rng = RulesEngine.RNGService.new(42)
	var result = rules_engine.resolve_hazardous_check("test_unit", "hazardous_plasma", 2, board, rng)
	# Should always have at least one dice entry (the hazardous_check context)
	var found_check_dice = false
	for dice in result.dice:
		if dice.get("context", "") == "hazardous_check":
			found_check_dice = true
			assert_eq(dice.get("weapon_id", ""), "hazardous_plasma", "Dice should reference correct weapon")
			assert_eq(dice.get("models_checked", 0), 2, "Should show 2 models checked")
	assert_true(found_check_dice, "Should have hazardous_check dice entry")

# ==========================================
# Integration Test — resolve_shoot with Hazardous
# ==========================================

func test_resolve_shoot_includes_hazardous_check():
	"""Test that resolve_shoot auto-resolve includes Hazardous check"""
	var board = _create_shooting_test_board()
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "shooter",
		"payload": {
			"assignments": [{
				"model_ids": ["m1"],
				"weapon_id": "hazardous_plasma",
				"target_unit_id": "target"
			}]
		}
	}
	var rng = RulesEngine.RNGService.new(42)
	var result = rules_engine.resolve_shoot(action, board, rng)
	assert_true(result.success, "Shooting should succeed")
	# Should have hazardous_check dice in the result
	var found_haz = false
	for dice in result.dice:
		if dice.get("context", "") == "hazardous_check":
			found_haz = true
	assert_true(found_haz, "resolve_shoot should include hazardous_check dice")

func test_resolve_shoot_until_wounds_passes_hazardous_data():
	"""Test that resolve_shoot_until_wounds passes hazardous weapon data for ShootingPhase"""
	var board = _create_shooting_test_board()
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "shooter",
		"payload": {
			"assignments": [{
				"model_ids": ["m1"],
				"weapon_id": "hazardous_plasma",
				"target_unit_id": "target"
			}]
		}
	}
	var rng = RulesEngine.RNGService.new(42)
	var result = rules_engine.resolve_shoot_until_wounds(action, board, rng)
	assert_true(result.success, "Shooting should succeed")
	# Should have hazardous_weapons data in result
	assert_true(result.has("hazardous_weapons"), "Should have hazardous_weapons in result")
	assert_eq(result.hazardous_weapons.size(), 1, "Should have 1 hazardous weapon entry")
	assert_eq(result.hazardous_weapons[0].weapon_id, "hazardous_plasma", "Should reference correct weapon")

# ==========================================
# Helper Functions
# ==========================================

func _create_test_board_with_unit(unit_id: String, model_count: int) -> Dictionary:
	"""Create a test board with a regular infantry unit"""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"wounds_current": 1,
			"wounds_max": 1,
			"position": {"x": 100 + i * 30, "y": 100}
		})
	return {
		"units": {
			unit_id: {
				"owner": 1,
				"meta": {
					"name": "Test Infantry",
					"keywords": ["INFANTRY"],
					"weapons": []
				},
				"models": models
			}
		}
	}

func _create_test_board_with_character_unit(unit_id: String, model_count: int, wounds: int) -> Dictionary:
	"""Create a test board with a CHARACTER unit"""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"wounds_current": wounds,
			"wounds_max": wounds,
			"position": {"x": 100 + i * 30, "y": 100}
		})
	return {
		"units": {
			unit_id: {
				"owner": 1,
				"meta": {
					"name": "Test Character",
					"keywords": ["CHARACTER", "INFANTRY"],
					"weapons": []
				},
				"models": models
			}
		}
	}

func _create_test_board_with_keyword_unit(unit_id: String, model_count: int, wounds: int, keywords: Array) -> Dictionary:
	"""Create a test board with a unit having specific keywords"""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"wounds_current": wounds,
			"wounds_max": wounds,
			"position": {"x": 100 + i * 30, "y": 100}
		})
	return {
		"units": {
			unit_id: {
				"owner": 1,
				"meta": {
					"name": "Test Unit",
					"keywords": keywords,
					"weapons": []
				},
				"models": models
			}
		}
	}

func _create_shooting_test_board() -> Dictionary:
	"""Create a board with a shooter and a target for full shooting resolution tests"""
	return {
		"units": {
			"shooter": {
				"owner": 1,
				"meta": {
					"name": "Test Shooter",
					"keywords": ["INFANTRY"],
					"weapons": []
				},
				"models": [{
					"id": "m1",
					"alive": true,
					"wounds_current": 1,
					"wounds_max": 1,
					"position": {"x": 100, "y": 100}
				}]
			},
			"target": {
				"owner": 2,
				"meta": {
					"name": "Test Target",
					"keywords": ["INFANTRY"],
					"toughness": 4,
					"save": 3,
					"weapons": []
				},
				"models": [
					{"id": "t1", "alive": true, "wounds_current": 1, "wounds_max": 1, "position": {"x": 200, "y": 100}},
					{"id": "t2", "alive": true, "wounds_current": 1, "wounds_max": 1, "position": {"x": 230, "y": 100}},
					{"id": "t3", "alive": true, "wounds_current": 1, "wounds_max": 1, "position": {"x": 260, "y": 100}}
				]
			}
		}
	}

func _find_seed_with_no_ones(dice_count: int, max_attempts: int) -> int:
	"""Find an RNG seed that produces no 1s when rolling dice_count D6"""
	for seed_val in range(max_attempts):
		var test_rng = RulesEngine.RNGService.new(seed_val)
		var rolls = test_rng.roll_d6(dice_count)
		var has_one = false
		for roll in rolls:
			if roll == 1:
				has_one = true
				break
		if not has_one:
			return seed_val
	return 99  # Fallback - unlikely to all be 1s

func _find_seed_with_ones(dice_count: int, max_attempts: int) -> int:
	"""Find an RNG seed that produces at least one 1 when rolling dice_count D6"""
	for seed_val in range(max_attempts):
		var test_rng = RulesEngine.RNGService.new(seed_val)
		var rolls = test_rng.roll_d6(dice_count)
		for roll in rolls:
			if roll == 1:
				return seed_val
	return 0  # Fallback

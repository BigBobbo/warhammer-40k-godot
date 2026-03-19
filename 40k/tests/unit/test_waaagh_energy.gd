extends "res://addons/gut/test.gd"

# Tests for the Waaagh! Energy ability (Weirdboy)
# While leading a unit, add +1S and +1D to the 'Eadbanger weapon per 5 models
# in the led unit (rounded down). At 10+ models, the weapon gains [HAZARDOUS].

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# Helper: Build board with Weirdboy + bodyguard
# ==========================================

func _make_weirdboy_board(bodyguard_model_count: int, weapon_name: String = "'Eadbanger") -> Dictionary:
	"""Create a board with a Weirdboy (CHARACTER) attached to a bodyguard unit."""
	var bodyguard_models = []
	for i in range(bodyguard_model_count):
		bodyguard_models.append({
			"alive": true,
			"current_wounds": 1,
			"wounds": 1,
			"position": {"x": 100 + i * 30, "y": 100}
		})

	return {
		"units": {
			"weirdboy_unit": {
				"owner": 1,
				"attached_to": "boyz_unit",
				"models": [{
					"alive": true,
					"current_wounds": 4,
					"wounds": 4,
					"position": {"x": 50, "y": 100}
				}],
				"meta": {
					"name": "Weirdboy",
					"stats": {
						"toughness": 5,
						"save": 6,
						"wounds": 4
					},
					"abilities": ["Waaagh! Energy"],
					"weapons": [{
						"name": weapon_name,
						"type": "Ranged",
						"range": "24",
						"attacks": "1",
						"ballistic_skill": "4",
						"strength": "6",
						"ap": "-3",
						"damage": "1",
						"special_rules": "precision, psychic"
					}],
					"keywords": ["INFANTRY", "CHARACTER", "PSYKER", "ORKS"]
				}
			},
			"boyz_unit": {
				"owner": 1,
				"models": bodyguard_models,
				"attachment_data": {
					"attached_characters": ["weirdboy_unit"]
				},
				"meta": {
					"name": "Boyz",
					"stats": {
						"toughness": 5,
						"save": 5,
						"wounds": 1
					},
					"keywords": ["INFANTRY", "ORKS"]
				}
			},
			"target_unit": {
				"owner": 2,
				"models": [
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 300, "y": 100}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 330, "y": 100}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 360, "y": 100}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 390, "y": 100}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 420, "y": 100}}
				],
				"meta": {
					"name": "Test Target",
					"stats": {
						"toughness": 4,
						"save": 3,
						"wounds": 2
					},
					"keywords": ["INFANTRY"]
				}
			}
		}
	}

func _make_standalone_weirdboy_board() -> Dictionary:
	"""Create a board with a standalone Weirdboy (not attached to any unit)."""
	return {
		"units": {
			"weirdboy_unit": {
				"owner": 1,
				"models": [{
					"alive": true,
					"current_wounds": 4,
					"wounds": 4,
					"position": {"x": 50, "y": 100}
				}],
				"meta": {
					"name": "Weirdboy",
					"stats": {
						"toughness": 5,
						"save": 6,
						"wounds": 4
					},
					"abilities": ["Waaagh! Energy"],
					"weapons": [{
						"name": "'Eadbanger",
						"type": "Ranged",
						"range": "24",
						"attacks": "1",
						"ballistic_skill": "4",
						"strength": "6",
						"ap": "-3",
						"damage": "1",
						"special_rules": "precision, psychic"
					}],
					"keywords": ["INFANTRY", "CHARACTER", "PSYKER", "ORKS"]
				}
			},
			"target_unit": {
				"owner": 2,
				"models": [
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 300, "y": 100}}
				],
				"meta": {
					"name": "Test Target",
					"stats": {"toughness": 4, "save": 3, "wounds": 2},
					"keywords": ["INFANTRY"]
				}
			}
		}
	}

# ==========================================
# get_waaagh_energy_bonus() Tests
# ==========================================

func test_bonus_with_5_models():
	"""5 models in led unit should give +1S/+1D."""
	var board = _make_weirdboy_board(5)
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "'Eadbanger", board)
	assert_false(result.is_empty(), "Should return bonus data")
	assert_eq(result.strength_bonus, 1, "5 models → +1 strength")
	assert_eq(result.damage_bonus, 1, "5 models → +1 damage")
	assert_false(result.hazardous, "5 models → NOT hazardous")
	assert_eq(result.model_count, 5)

func test_bonus_with_10_models():
	"""10 models in led unit should give +2S/+2D and HAZARDOUS."""
	var board = _make_weirdboy_board(10)
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "'Eadbanger", board)
	assert_false(result.is_empty(), "Should return bonus data")
	assert_eq(result.strength_bonus, 2, "10 models → +2 strength")
	assert_eq(result.damage_bonus, 2, "10 models → +2 damage")
	assert_true(result.hazardous, "10 models → HAZARDOUS")

func test_bonus_with_15_models():
	"""15 models in led unit should give +3S/+3D and HAZARDOUS."""
	var board = _make_weirdboy_board(15)
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "'Eadbanger", board)
	assert_eq(result.strength_bonus, 3, "15 models → +3 strength")
	assert_eq(result.damage_bonus, 3, "15 models → +3 damage")
	assert_true(result.hazardous, "15 models → HAZARDOUS")

func test_bonus_with_4_models():
	"""4 models in led unit should give no bonus (floor(4/5) = 0)."""
	var board = _make_weirdboy_board(4)
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "'Eadbanger", board)
	assert_true(result.is_empty(), "4 models → no bonus (floor(4/5)=0)")

func test_bonus_with_7_models():
	"""7 models in led unit should give +1S/+1D (floor(7/5) = 1)."""
	var board = _make_weirdboy_board(7)
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "'Eadbanger", board)
	assert_eq(result.strength_bonus, 1, "7 models → +1 strength (floor(7/5)=1)")
	assert_eq(result.damage_bonus, 1, "7 models → +1 damage")
	assert_false(result.hazardous, "7 models → NOT hazardous")

func test_no_bonus_for_non_eadbanger_weapon():
	"""Non-'Eadbanger weapons should not get the bonus."""
	var board = _make_weirdboy_board(10)
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "Weirdboy staff", board)
	assert_true(result.is_empty(), "Weirdboy staff should not get Waaagh! Energy bonus")

func test_no_bonus_without_ability():
	"""Unit without Waaagh! Energy ability should not get the bonus."""
	var board = _make_weirdboy_board(10)
	board.units.weirdboy_unit.meta.abilities = ["Some Other Ability"]
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "'Eadbanger", board)
	assert_true(result.is_empty(), "Unit without Waaagh! Energy should not get bonus")

func test_no_bonus_when_standalone():
	"""Standalone Weirdboy (not attached) should not get the bonus."""
	var board = _make_standalone_weirdboy_board()
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "'Eadbanger", board)
	assert_true(result.is_empty(), "Standalone Weirdboy should not get bonus (not leading)")

func test_bonus_with_dict_ability_format():
	"""Waaagh! Energy should work when abilities are in Dictionary format."""
	var board = _make_weirdboy_board(10)
	board.units.weirdboy_unit.meta.abilities = [{"name": "Waaagh! Energy"}]
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "'Eadbanger", board)
	assert_false(result.is_empty(), "Should work with Dictionary-format abilities")
	assert_eq(result.strength_bonus, 2, "10 models → +2 strength")

func test_bonus_counts_only_alive_models():
	"""Dead models in the bodyguard unit should not count."""
	var board = _make_weirdboy_board(10)
	# Kill 5 models
	for i in range(5):
		board.units.boyz_unit.models[i].alive = false
	var unit = board.units.weirdboy_unit
	var result = RulesEngine.get_waaagh_energy_bonus(unit, "'Eadbanger", board)
	assert_eq(result.strength_bonus, 1, "5 alive models → +1 strength")
	assert_eq(result.damage_bonus, 1, "5 alive models → +1 damage")
	assert_false(result.hazardous, "5 alive models → NOT hazardous")

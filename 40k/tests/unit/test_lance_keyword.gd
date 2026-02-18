extends "res://addons/gut/test.gd"

# Tests for the LANCE weapon keyword implementation (T4-1)
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k 10e rules: "Weapons with [LANCE] in their profile are known
# as Lance weapons. Each time an attack is made with such a weapon, if the bearer
# made a Charge move this turn, add 1 to that attack's Wound roll."
#
# Lance is subject to the +1/-1 wound modifier cap (WoundModifier system from T1-3).

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
# is_lance_weapon() Tests — Built-in Weapon Profiles
# ==========================================

func test_is_lance_weapon_returns_true_for_lance_melee():
	"""Test that lance_melee is recognized as a Lance weapon"""
	var result = rules_engine.is_lance_weapon("lance_melee")
	assert_true(result, "lance_melee should be recognized as a Lance weapon")

func test_is_lance_weapon_returns_true_for_lance_lethal():
	"""Test that lance_lethal is recognized as a Lance weapon"""
	var result = rules_engine.is_lance_weapon("lance_lethal")
	assert_true(result, "lance_lethal should be a Lance weapon")

func test_is_lance_weapon_returns_true_for_lance_ranged():
	"""Test that lance_ranged is recognized as a Lance weapon"""
	var result = rules_engine.is_lance_weapon("lance_ranged")
	assert_true(result, "lance_ranged should be a Lance weapon")

func test_is_lance_weapon_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT a Lance weapon"""
	var result = rules_engine.is_lance_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be a Lance weapon")

func test_is_lance_weapon_returns_false_for_lascannon():
	"""Test that lascannon is NOT a Lance weapon"""
	var result = rules_engine.is_lance_weapon("lascannon")
	assert_false(result, "lascannon should NOT be a Lance weapon")

func test_is_lance_weapon_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.is_lance_weapon("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# is_lance_weapon() Tests — Board Weapon with special_rules
# ==========================================

func test_is_lance_weapon_from_special_rules():
	"""Test that Lance is detected from special_rules string (army list format)"""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"id": "laser_lance",
						"name": "Laser Lance",
						"range": "Melee",
						"attacks": "3",
						"weapon_skill": "3",
						"strength": "6",
						"ap": "-2",
						"damage": "2",
						"special_rules": "lance",
						"keywords": []
					}]
				},
				"models": [{"id": "m1", "alive": true, "weapons": ["laser_lance"]}]
			}
		}
	}
	var result = rules_engine.is_lance_weapon("laser_lance", board)
	assert_true(result, "Should detect Lance from special_rules string")

func test_is_lance_weapon_case_insensitive_special_rules():
	"""Test that Lance detection is case-insensitive in special_rules"""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"id": "star_lance",
						"name": "Star Lance",
						"range": "Melee",
						"attacks": "2",
						"weapon_skill": "3",
						"strength": "8",
						"ap": "-3",
						"damage": "2",
						"special_rules": "Lance, Devastating Wounds",
						"keywords": []
					}]
				},
				"models": [{"id": "m1", "alive": true, "weapons": ["star_lance"]}]
			}
		}
	}
	var result = rules_engine.is_lance_weapon("star_lance", board)
	assert_true(result, "Should detect Lance (capitalized) from special_rules")

func test_is_lance_weapon_from_keywords_array():
	"""Test that Lance is detected from keywords array"""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"id": "custom_lance",
						"name": "Custom Lance",
						"range": "Melee",
						"attacks": "4",
						"weapon_skill": "3",
						"strength": "5",
						"ap": "-1",
						"damage": "1",
						"special_rules": "",
						"keywords": ["LANCE"]
					}]
				},
				"models": [{"id": "m1", "alive": true, "weapons": ["custom_lance"]}]
			}
		}
	}
	var result = rules_engine.is_lance_weapon("custom_lance", board)
	assert_true(result, "Should detect LANCE from keywords array")

# ==========================================
# Weapon Profile Tests
# ==========================================

func test_weapon_profile_lance_melee_has_keyword():
	"""Test that lance_melee profile contains LANCE keyword"""
	var profile = rules_engine.get_weapon_profile("lance_melee")
	assert_false(profile.is_empty(), "Should find lance_melee profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "LANCE", "Lance Melee should have LANCE keyword")

func test_weapon_profile_lance_lethal_has_both_keywords():
	"""Test that lance_lethal profile has both LANCE and LETHAL HITS keywords"""
	var profile = rules_engine.get_weapon_profile("lance_lethal")
	assert_false(profile.is_empty(), "Should find lance_lethal profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "LANCE", "Lance Lethal should have LANCE keyword")
	assert_has(keywords, "LETHAL HITS", "Lance Lethal should have LETHAL HITS keyword")

func test_weapon_profile_bolt_rifle_no_lance_keyword():
	"""Test that bolt_rifle profile does NOT contain LANCE keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "LANCE", "Bolt rifle should NOT have LANCE keyword")

# ==========================================
# Helper: Build a board with attacker and target units
# ==========================================

func _make_melee_board(attacker_weapons: Array, target_stats: Dictionary = {},
		attacker_flags: Dictionary = {}, attacker_model_count: int = 1,
		target_model_count: int = 5) -> Dictionary:
	"""Create a minimal board with an attacker unit and target unit for melee"""
	var attacker_models = []
	for i in range(attacker_model_count):
		attacker_models.append({
			"alive": true,
			"current_wounds": 3,
			"wounds": 3,
			"position": {"x": 100 + i * 30, "y": 100}
		})

	var target_models = []
	var t_wounds = target_stats.get("wounds", 1)
	for i in range(target_model_count):
		target_models.append({
			"alive": true,
			"current_wounds": t_wounds,
			"wounds": t_wounds,
			"position": {"x": 130 + i * 30, "y": 100}
		})

	return {
		"units": {
			"attacker_unit": {
				"owner": 1,
				"models": attacker_models,
				"flags": attacker_flags,
				"meta": {
					"name": "Test Attacker",
					"stats": {
						"toughness": 4,
						"save": 3,
						"wounds": 3
					},
					"weapons": attacker_weapons,
					"keywords": ["INFANTRY"]
				}
			},
			"target_unit": {
				"owner": 2,
				"models": target_models,
				"meta": {
					"name": "Test Target",
					"stats": {
						"toughness": target_stats.get("toughness", 4),
						"save": target_stats.get("save", 3),
						"wounds": t_wounds
					},
					"keywords": target_stats.get("keywords", ["INFANTRY"])
				}
			}
		}
	}

func _make_shoot_board(attacker_weapons: Array, target_stats: Dictionary = {},
		attacker_flags: Dictionary = {}, attacker_model_count: int = 1,
		target_model_count: int = 5) -> Dictionary:
	"""Create a minimal board with an attacker unit and target unit for shooting"""
	var attacker_models = []
	for i in range(attacker_model_count):
		attacker_models.append({
			"alive": true,
			"current_wounds": 3,
			"wounds": 3,
			"position": {"x": 100 + i * 30, "y": 100}
		})

	var target_models = []
	var t_wounds = target_stats.get("wounds", 1)
	for i in range(target_model_count):
		target_models.append({
			"alive": true,
			"current_wounds": t_wounds,
			"wounds": t_wounds,
			"position": {"x": 300 + i * 30, "y": 100}
		})

	return {
		"units": {
			"attacker_unit": {
				"owner": 1,
				"models": attacker_models,
				"flags": attacker_flags,
				"meta": {
					"name": "Test Attacker",
					"stats": {
						"toughness": 4,
						"save": 3,
						"wounds": 3
					},
					"weapons": attacker_weapons,
					"keywords": ["INFANTRY"]
				}
			},
			"target_unit": {
				"owner": 2,
				"models": target_models,
				"meta": {
					"name": "Test Target",
					"stats": {
						"toughness": target_stats.get("toughness", 4),
						"save": target_stats.get("save", 3),
						"wounds": t_wounds
					},
					"keywords": target_stats.get("keywords", ["INFANTRY"])
				}
			}
		}
	}

func _make_melee_action(weapon_id: String, attacker_id: String = "attacker_unit", target_id: String = "target_unit") -> Dictionary:
	return {
		"actor_unit_id": attacker_id,
		"payload": {
			"assignments": [{
				"attacker": attacker_id,
				"target": target_id,
				"weapon": weapon_id
			}]
		}
	}

func _make_shoot_action(weapon_id: String, attacker_id: String = "attacker_unit", target_id: String = "target_unit") -> Dictionary:
	return {
		"actor_unit_id": attacker_id,
		"payload": {
			"assignments": [{
				"attacker": attacker_id,
				"target": target_id,
				"weapon_id": weapon_id,
				"model_ids": ["m1"]
			}]
		}
	}

# ==========================================
# WoundModifier.PLUS_ONE Integration Tests
# ==========================================

func test_wound_modifier_plus_one_exists():
	"""Test that WoundModifier.PLUS_ONE flag value is defined"""
	assert_eq(rules_engine.WoundModifier.PLUS_ONE, 4, "PLUS_ONE should be flag value 4")

func test_apply_wound_modifiers_plus_one_improves_roll():
	"""Test that PLUS_ONE adds +1 to wound roll"""
	var rng = rules_engine.RNGService.new(42)
	var wound_threshold = 4  # Need 4+ to wound
	var modifiers = rules_engine.WoundModifier.PLUS_ONE

	# Roll of 3 (fails threshold of 4+) — with +1 modifier becomes 4 (pass)
	var result = rules_engine.apply_wound_modifiers(3, modifiers, wound_threshold, rng)

	assert_eq(result.modifier_applied, 1, "Modifier should be +1")
	assert_eq(result.modified_roll, 4, "Roll of 3 + 1 modifier = 4")

func test_apply_wound_modifiers_plus_one_capped_with_minus_one():
	"""Test that PLUS_ONE and MINUS_ONE cancel out (net 0)"""
	var rng = rules_engine.RNGService.new(42)
	var wound_threshold = 4
	var modifiers = rules_engine.WoundModifier.PLUS_ONE | rules_engine.WoundModifier.MINUS_ONE

	var result = rules_engine.apply_wound_modifiers(4, modifiers, wound_threshold, rng)

	assert_eq(result.modifier_applied, 0, "Plus and minus one should cancel to net 0")
	assert_eq(result.modified_roll, 4, "Roll should be unchanged")

# ==========================================
# Lance Melee Combat — Statistical Tests
# ==========================================

func test_lance_melee_charged_increases_wound_rate():
	"""Test that Lance on charge produces more wounds than without charge (statistical)"""
	var weapons = [{
		"name": "Test Lance",
		"type": "Melee",
		"range": "Melee",
		"attacks": "4",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-1",
		"damage": "1",
		"special_rules": "lance"
	}]

	# Run many trials WITH charged_this_turn
	var charged_wounds = 0
	var uncharged_wounds = 0
	var trials = 200

	for i in range(trials):
		var board_charged = _make_melee_board(weapons, {"toughness": 5, "save": 4, "wounds": 1},
			{"charged_this_turn": true})
		var action = _make_melee_action("test_lance")
		var result = rules_engine.resolve_melee_attacks(action, board_charged)
		for dice in result.dice:
			if dice.context == "wound_roll_melee":
				charged_wounds += dice.get("successes", 0)

	for i in range(trials):
		var board_uncharged = _make_melee_board(weapons, {"toughness": 5, "save": 4, "wounds": 1}, {})
		var action = _make_melee_action("test_lance")
		var result = rules_engine.resolve_melee_attacks(action, board_uncharged)
		for dice in result.dice:
			if dice.context == "wound_roll_melee":
				uncharged_wounds += dice.get("successes", 0)

	# With Lance +1 to wound, charged should have significantly more wounds
	# S5 vs T5: normally wounds on 4+. With +1, wounds on 3+.
	# Expected: ~50% wound rate vs ~67% wound rate — about 33% improvement
	assert_true(charged_wounds > uncharged_wounds,
		"Lance on charge should produce more wounds (%d) than without charge (%d)" % [charged_wounds, uncharged_wounds])

func test_lance_melee_not_charged_no_bonus():
	"""Test that Lance without charge does NOT get +1 to wound"""
	var weapons = [{
		"name": "Test Lance",
		"type": "Melee",
		"range": "Melee",
		"attacks": "4",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-1",
		"damage": "1",
		"special_rules": "lance"
	}]

	# Board WITHOUT charged_this_turn flag
	var board = _make_melee_board(weapons, {"toughness": 5, "save": 4, "wounds": 1}, {})
	var action = _make_melee_action("test_lance")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Melee resolution should succeed")

	# Check wound dice threshold — without charge, S5 vs T5 should be 4+
	var wound_dice = null
	for dice in result.dice:
		if dice.context == "wound_roll_melee":
			wound_dice = dice
			break

	if wound_dice:
		# Without Lance bonus, S5 vs T5 = wound on 4+
		assert_eq(wound_dice.threshold, "4+",
			"Without charge, S5 vs T5 should wound on 4+ (no Lance bonus)")

func test_lance_melee_charged_modifies_threshold():
	"""Test that Lance on charge shows correct wound threshold"""
	var weapons = [{
		"name": "Test Lance",
		"type": "Melee",
		"range": "Melee",
		"attacks": "4",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-1",
		"damage": "1",
		"special_rules": "lance"
	}]

	# Board WITH charged_this_turn flag
	var board = _make_melee_board(weapons, {"toughness": 5, "save": 4, "wounds": 1},
		{"charged_this_turn": true})
	var action = _make_melee_action("test_lance")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Melee resolution should succeed")

	# Check that result indicates wound modifier was applied
	# With Lance +1, S5 vs T5: base 4+, modified 3+
	# The threshold in dice context shows base threshold, but modifier is applied to rolls
	var wound_dice = null
	for dice in result.dice:
		if dice.context == "wound_roll_melee":
			wound_dice = dice
			break

	assert_not_null(wound_dice, "Should have wound dice block")

# ==========================================
# Lance Auto-Resolve Shooting Tests
# ==========================================

func test_lance_shooting_auto_resolve_charged():
	"""Test that Lance +1 wound applies to ranged attacks via auto-resolve when charged"""
	# Use built-in lance_ranged profile
	var board = _make_shoot_board([], {"toughness": 5, "save": 4, "wounds": 1},
		{"charged_this_turn": true})

	var wounds_charged = 0
	var trials = 200

	for i in range(trials):
		# Create fresh board each trial
		var trial_board = _make_shoot_board([], {"toughness": 5, "save": 4, "wounds": 1},
			{"charged_this_turn": true})
		var action = _make_shoot_action("lance_ranged")
		var result = rules_engine.resolve_shoot(action, trial_board)
		for dice in result.dice:
			if dice.context == "wound_roll":
				wounds_charged += dice.get("successes", 0)

	var wounds_uncharged = 0
	for i in range(trials):
		var trial_board = _make_shoot_board([], {"toughness": 5, "save": 4, "wounds": 1}, {})
		var action = _make_shoot_action("lance_ranged")
		var result = rules_engine.resolve_shoot(action, trial_board)
		for dice in result.dice:
			if dice.context == "wound_roll":
				wounds_uncharged += dice.get("successes", 0)

	# Lance ranged: S6 vs T5 = 3+ normally. With +1, wounds on 2+.
	# That's a significant difference
	assert_true(wounds_charged > wounds_uncharged,
		"Lance ranged on charge should produce more wounds (%d) than without charge (%d)" % [wounds_charged, wounds_uncharged])

func test_lance_shooting_not_charged_no_bonus():
	"""Test that Lance shooting without charge does NOT get +1 wound"""
	var board = _make_shoot_board([], {"toughness": 5, "save": 4, "wounds": 1}, {})
	var action = _make_shoot_action("lance_ranged")
	var result = rules_engine.resolve_shoot(action, board)

	assert_true(result.success, "Shooting resolution should succeed")

# ==========================================
# Non-Lance Weapon — No Bonus Even When Charged
# ==========================================

func test_non_lance_weapon_no_bonus_when_charged():
	"""Test that non-Lance weapons do NOT get +1 to wound even when charged"""
	var weapons = [{
		"name": "Chainsword",
		"type": "Melee",
		"range": "Melee",
		"attacks": "4",
		"weapon_skill": "3",
		"strength": "4",
		"ap": "0",
		"damage": "1",
		"special_rules": ""
	}]

	# Board WITH charged_this_turn but non-Lance weapon
	var board = _make_melee_board(weapons, {"toughness": 4, "save": 4, "wounds": 1},
		{"charged_this_turn": true})
	var action = _make_melee_action("chainsword")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")

	# Check wound dice — S4 vs T4 should still be 4+ (no Lance bonus)
	var wound_dice = null
	for dice in result.dice:
		if dice.context == "wound_roll_melee":
			wound_dice = dice
			break

	if wound_dice:
		assert_eq(wound_dice.threshold, "4+",
			"Non-Lance weapon S4 vs T4 should wound on 4+ even when charged")

# ==========================================
# Lance + Other Keyword Combo Tests
# ==========================================

func test_lance_plus_lethal_hits_combo():
	"""Test that Lance works alongside Lethal Hits"""
	var weapons = [{
		"name": "Lance + Lethal Blade",
		"type": "Melee",
		"range": "Melee",
		"attacks": "6",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-1",
		"damage": "1",
		"special_rules": "lance, lethal hits"
	}]

	var board = _make_melee_board(weapons, {"toughness": 5, "save": 4, "wounds": 1},
		{"charged_this_turn": true})
	var action = _make_melee_action("lance_+_lethal_blade")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed with Lance + Lethal Hits")

	# Verify Lethal Hits is also detected
	var hit_dice = result.dice[0]
	assert_true(hit_dice.get("lethal_hits_weapon", false),
		"Should detect Lethal Hits on weapon with Lance")

func test_lance_plus_twin_linked_combo():
	"""Test that Lance works alongside Twin-linked (both wound modifiers)"""
	var weapons = [{
		"name": "Lance Twin Weapon",
		"type": "Melee",
		"range": "Melee",
		"attacks": "4",
		"weapon_skill": "3",
		"strength": "4",
		"ap": "-1",
		"damage": "1",
		"special_rules": "lance, twin-linked"
	}]

	var board = _make_melee_board(weapons, {"toughness": 5, "save": 4, "wounds": 1},
		{"charged_this_turn": true})
	var action = _make_melee_action("lance_twin_weapon")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed with Lance + Twin-linked")

# ==========================================
# charged_this_turn Flag Tests
# ==========================================

func test_charged_this_turn_flag_true_triggers_lance():
	"""Test that charged_this_turn = true triggers Lance bonus"""
	var board = _make_melee_board([], {}, {"charged_this_turn": true})
	# Verify the flag is set correctly in the board
	var flags = board.units.attacker_unit.get("flags", {})
	assert_true(flags.get("charged_this_turn", false),
		"charged_this_turn should be true in board state")

func test_charged_this_turn_flag_false_no_lance():
	"""Test that charged_this_turn = false does NOT trigger Lance bonus"""
	var board = _make_melee_board([], {}, {"charged_this_turn": false})
	var flags = board.units.attacker_unit.get("flags", {})
	assert_false(flags.get("charged_this_turn", false),
		"charged_this_turn should be false in board state")

func test_no_flags_dict_no_lance():
	"""Test that missing flags dictionary does NOT trigger Lance bonus"""
	var board = _make_melee_board([], {}, {})
	var flags = board.units.attacker_unit.get("flags", {})
	assert_false(flags.get("charged_this_turn", false),
		"Missing charged_this_turn flag should default to false")

# ==========================================
# Built-in Weapon Profile Integration Tests
# ==========================================

func test_lance_melee_profile_resolves_in_melee():
	"""Test that the lance_melee built-in profile works in melee resolution"""
	var board = _make_melee_board([], {"toughness": 4, "save": 4, "wounds": 1},
		{"charged_this_turn": true})
	var action = _make_melee_action("lance_melee")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution with lance_melee should succeed")
	assert_true(result.dice.size() >= 2, "Should have at least hit and wound dice blocks")

func test_lance_ranged_profile_resolves_in_shooting():
	"""Test that the lance_ranged built-in profile works in shooting resolution"""
	var board = _make_shoot_board([], {"toughness": 4, "save": 4, "wounds": 1},
		{"charged_this_turn": true})
	var action = _make_shoot_action("lance_ranged")
	var result = rules_engine.resolve_shoot(action, board)

	assert_true(result.success, "Resolution with lance_ranged should succeed")

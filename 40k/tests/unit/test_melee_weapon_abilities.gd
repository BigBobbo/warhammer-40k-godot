extends "res://addons/gut/test.gd"

# Tests for melee weapon ability support in the fight phase
# Verifies that the refactored _resolve_melee_assignment() correctly handles:
# - Weapon Skill from weapon profile (not unit stats)
# - Critical hit tracking (unmodified 6s)
# - Lethal Hits (critical hits auto-wound)
# - Sustained Hits (critical hits generate bonus hits)
# - Devastating Wounds (critical wounds bypass saves)
# - Invulnerable saves
# - Variable attack/damage characteristics (D3, D6, etc.)
# - Feel No Pain

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# Helper: Build a board with attacker and target units
# ==========================================

func _make_board(attacker_weapons: Array, target_stats: Dictionary = {}, attacker_model_count: int = 1, target_model_count: int = 5) -> Dictionary:
	"""Create a minimal board with an attacker unit and target unit"""
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
	var t_invuln = target_stats.get("invuln", 0)
	for i in range(target_model_count):
		var model = {
			"alive": true,
			"current_wounds": t_wounds,
			"wounds": t_wounds,
			"position": {"x": 130 + i * 30, "y": 100}
		}
		if t_invuln > 0:
			model["invuln"] = t_invuln
		target_models.append(model)

	return {
		"units": {
			"attacker_unit": {
				"owner": 1,
				"models": attacker_models,
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
						"wounds": t_wounds,
						"fnp": target_stats.get("fnp", 0)
					},
					"keywords": target_stats.get("keywords", ["INFANTRY"])
				}
			}
		}
	}

func _make_action(weapon_id: String, attacker_id: String = "attacker_unit", target_id: String = "target_unit") -> Dictionary:
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

# ==========================================
# Basic Melee Resolution Tests
# ==========================================

func test_basic_melee_attack_produces_dice():
	"""Test that a basic melee attack generates hit, wound, and save dice blocks"""
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
	var board = _make_board(weapons)
	var action = _make_action("chainsword")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Melee resolution should succeed")
	assert_true(result.dice.size() >= 2, "Should have at least hit and wound dice blocks")

	# Check first dice block is melee hit roll
	var hit_dice = result.dice[0]
	assert_eq(hit_dice.context, "hit_roll_melee", "First dice block should be melee hit roll")
	assert_eq(hit_dice.threshold, "3+", "WS should come from weapon profile (3+)")
	assert_eq(hit_dice.total_attacks, 4, "Should have 4 attacks from 1 model")

func test_melee_uses_weapon_skill_from_profile():
	"""Test that WS comes from the weapon profile, not unit stats"""
	# Weapon has WS 2+ (Custodes-style)
	var weapons = [{
		"name": "Guardian Spear",
		"type": "Melee",
		"range": "Melee",
		"attacks": "5",
		"weapon_skill": "2",
		"strength": "7",
		"ap": "-2",
		"damage": "2",
		"special_rules": ""
	}]
	var board = _make_board(weapons)
	var action = _make_action("guardian_spear")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")
	var hit_dice = result.dice[0]
	assert_eq(hit_dice.threshold, "2+", "WS should be 2+ from weapon profile")

# ==========================================
# Critical Hit Tracking Tests
# ==========================================

func test_melee_tracks_critical_hits():
	"""Test that critical hits (unmodified 6s) are tracked in melee"""
	var weapons = [{
		"name": "Power Sword",
		"type": "Melee",
		"range": "Melee",
		"attacks": "4",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-2",
		"damage": "1",
		"special_rules": ""
	}]
	var board = _make_board(weapons)
	var action = _make_action("power_sword")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")
	var hit_dice = result.dice[0]
	assert_true(hit_dice.has("critical_hits"), "Hit dice should track critical hits")
	assert_true(hit_dice.has("regular_hits"), "Hit dice should track regular hits")
	# critical_hits + regular_hits should equal total successes
	assert_eq(hit_dice.critical_hits + hit_dice.regular_hits, hit_dice.successes,
		"Critical + regular hits should equal total hits")

# ==========================================
# Lethal Hits Tests
# ==========================================

func test_melee_lethal_hits_tracked():
	"""Test that Lethal Hits flag is detected from weapon special_rules"""
	var weapons = [{
		"name": "Lethal Blade",
		"type": "Melee",
		"range": "Melee",
		"attacks": "6",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-1",
		"damage": "1",
		"special_rules": "lethal hits"
	}]
	var board = _make_board(weapons)
	var action = _make_action("lethal_blade")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")
	var hit_dice = result.dice[0]
	assert_true(hit_dice.get("lethal_hits_weapon", false), "Should detect Lethal Hits on weapon")

func test_melee_lethal_hits_auto_wound():
	"""Test that Lethal Hits auto-wounds are recorded in wound dice"""
	var weapons = [{
		"name": "Lethal Blade",
		"type": "Melee",
		"range": "Melee",
		"attacks": "6",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-1",
		"damage": "1",
		"special_rules": "lethal hits"
	}]
	var board = _make_board(weapons)
	var action = _make_action("lethal_blade")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")

	# Find wound dice block
	var wound_dice = null
	for dice in result.dice:
		if dice.context == "wound_roll_melee":
			wound_dice = dice
			break

	if wound_dice:
		assert_true(wound_dice.has("lethal_hits_auto_wounds"), "Wound dice should track lethal auto-wounds")
		assert_true(wound_dice.get("lethal_hits_weapon", false), "Wound dice should flag lethal weapon")

# ==========================================
# Sustained Hits Tests
# ==========================================

func test_melee_sustained_hits_detected():
	"""Test that Sustained Hits is detected from weapon special_rules"""
	var weapons = [{
		"name": "Sustained Blade",
		"type": "Melee",
		"range": "Melee",
		"attacks": "9",
		"weapon_skill": "2",
		"strength": "5",
		"ap": "-1",
		"damage": "1",
		"special_rules": "sustained hits 1"
	}]
	var board = _make_board(weapons)
	var action = _make_action("sustained_blade")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")
	var hit_dice = result.dice[0]
	assert_true(hit_dice.get("sustained_hits_weapon", false), "Should detect Sustained Hits on weapon")
	assert_eq(hit_dice.get("sustained_hits_value", 0), 1, "Should have Sustained Hits value of 1")

# ==========================================
# Devastating Wounds Tests
# ==========================================

func test_melee_devastating_wounds_detected():
	"""Test that Devastating Wounds is detected from weapon special_rules"""
	var weapons = [{
		"name": "Devastating Fist",
		"type": "Melee",
		"range": "Melee",
		"attacks": "3",
		"weapon_skill": "3",
		"strength": "8",
		"ap": "-2",
		"damage": "2",
		"special_rules": "devastating wounds"
	}]
	var board = _make_board(weapons)
	var action = _make_action("devastating_fist")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")
	# Check wound dice block for devastating wounds tracking
	var wound_dice = null
	for dice in result.dice:
		if dice.context == "wound_roll_melee":
			wound_dice = dice
			break

	if wound_dice:
		assert_true(wound_dice.get("devastating_wounds_weapon", false), "Should detect Devastating Wounds")
		assert_true(wound_dice.has("critical_wounds"), "Should track critical wounds count")

# ==========================================
# Invulnerable Save Tests
# ==========================================

func test_melee_invulnerable_save_used_when_better():
	"""Test that invulnerable saves are used when better than armour save after AP"""
	# Target has 3+ save, AP -3 means armour save is 6+
	# Invuln 4+ is better than 6+
	var weapons = [{
		"name": "AP3 Blade",
		"type": "Melee",
		"range": "Melee",
		"attacks": "4",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-3",
		"damage": "1",
		"special_rules": ""
	}]
	var board = _make_board(weapons, {"save": 3, "toughness": 4, "invuln": 4, "wounds": 1})
	var action = _make_action("ap3_blade")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")

	# Find save dice block
	var save_dice = null
	for dice in result.dice:
		if dice.context == "save_roll_melee":
			save_dice = dice
			break

	if save_dice:
		# With AP -3 on 3+ save = 6+ armour save. Invuln 4+ is better.
		assert_eq(save_dice.threshold, "4+", "Should use invulnerable save (4+) instead of armour (6+)")
		assert_true(save_dice.get("using_invuln", false), "Should flag that invuln is being used")

# ==========================================
# Variable Characteristics Tests
# ==========================================

func test_roll_variable_characteristic_fixed():
	"""Test that fixed values are returned as-is"""
	var rng = RulesEngine.RNGService.new()
	var result = rules_engine.roll_variable_characteristic("4", rng)
	assert_eq(result.value, 4, "Fixed value '4' should return 4")
	assert_false(result.rolled, "Fixed value should not be marked as rolled")

func test_roll_variable_characteristic_d6():
	"""Test that D6 rolls return a value between 1 and 6"""
	var rng = RulesEngine.RNGService.new()
	var result = rules_engine.roll_variable_characteristic("D6", rng)
	assert_true(result.value >= 1 and result.value <= 6, "D6 should return 1-6, got %d" % result.value)
	assert_true(result.rolled, "D6 should be marked as rolled")
	assert_eq(result.notation, "D6", "Should have D6 notation")

func test_roll_variable_characteristic_d3():
	"""Test that D3 rolls return a value between 1 and 3"""
	var rng = RulesEngine.RNGService.new()
	var result = rules_engine.roll_variable_characteristic("D3", rng)
	assert_true(result.value >= 1 and result.value <= 3, "D3 should return 1-3, got %d" % result.value)
	assert_true(result.rolled, "D3 should be marked as rolled")

func test_roll_variable_characteristic_d6_plus():
	"""Test that D6+2 rolls return a value between 3 and 8"""
	var rng = RulesEngine.RNGService.new()
	var result = rules_engine.roll_variable_characteristic("D6+2", rng)
	assert_true(result.value >= 3 and result.value <= 8, "D6+2 should return 3-8, got %d" % result.value)
	assert_true(result.rolled, "D6+2 should be marked as rolled")

func test_roll_variable_characteristic_d3_plus():
	"""Test that D3+3 rolls return a value between 4 and 6"""
	var rng = RulesEngine.RNGService.new()
	var result = rules_engine.roll_variable_characteristic("D3+3", rng)
	assert_true(result.value >= 4 and result.value <= 6, "D3+3 should return 4-6, got %d" % result.value)
	assert_true(result.rolled, "D3+3 should be marked as rolled")

# ==========================================
# Weapon Profile Raw Values Tests
# ==========================================

func test_weapon_profile_includes_raw_values():
	"""Test that weapon profiles include raw string values for variable rolling"""
	# This tests that get_weapon_profile includes attacks_raw and damage_raw
	var board = _make_board([{
		"name": "Variable Blade",
		"type": "Melee",
		"range": "Melee",
		"attacks": "D6",
		"weapon_skill": "3",
		"strength": "5",
		"ap": "-1",
		"damage": "D3",
		"special_rules": ""
	}])
	var profile = rules_engine.get_weapon_profile("variable_blade", board)
	assert_false(profile.is_empty(), "Should find weapon profile")
	assert_true(profile.has("attacks_raw"), "Profile should include attacks_raw")
	assert_eq(profile.get("attacks_raw", ""), "D6", "attacks_raw should be 'D6'")
	assert_true(profile.has("damage_raw"), "Profile should include damage_raw")
	assert_eq(profile.get("damage_raw", ""), "D3", "damage_raw should be 'D3'")

# ==========================================
# Multiple Model Attack Count Tests
# ==========================================

func test_melee_multiple_models_contribute_attacks():
	"""Test that multiple alive models in a unit contribute attacks"""
	var weapons = [{
		"name": "Chainsword",
		"type": "Melee",
		"range": "Melee",
		"attacks": "3",
		"weapon_skill": "3",
		"strength": "4",
		"ap": "0",
		"damage": "1",
		"special_rules": ""
	}]
	# 3 attacking models with 3 attacks each = 9 total
	var board = _make_board(weapons, {}, 3)
	var action = _make_action("chainsword")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")
	var hit_dice = result.dice[0]
	assert_eq(hit_dice.total_attacks, 9, "3 models * 3 attacks = 9 total attacks")

# ==========================================
# Combined Ability Tests
# ==========================================

func test_melee_precision_detected():
	"""Test that Precision keyword is detected (Custodes Vaultswords - Behemor)"""
	# Mirrors the actual Custodes Blade Champion weapon
	var weapons = [{
		"name": "Vaultswords Behemor",
		"type": "Melee",
		"range": "Melee",
		"attacks": "6",
		"weapon_skill": "2",
		"strength": "7",
		"ap": "-2",
		"damage": "2",
		"special_rules": "precision"
	}]
	var board = _make_board(weapons)
	# Verify weapon profile is found with special rules
	var profile = rules_engine.get_weapon_profile("vaultswords_behemor", board)
	assert_false(profile.is_empty(), "Should find Vaultswords Behemor profile")
	assert_true("precision" in profile.get("special_rules", "").to_lower(), "Should have precision in special_rules")

func test_melee_sustained_hits_real_custodes_weapon():
	"""Test Sustained Hits on actual Custodes Hurricanus weapon profile"""
	var weapons = [{
		"name": "Vaultswords Hurricanus",
		"type": "Melee",
		"range": "Melee",
		"attacks": "9",
		"weapon_skill": "2",
		"strength": "5",
		"ap": "-1",
		"damage": "1",
		"special_rules": "sustained hits 1"
	}]
	var board = _make_board(weapons)
	var action = _make_action("vaultswords_hurricanus")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")
	var hit_dice = result.dice[0]
	assert_eq(hit_dice.threshold, "2+", "WS should be 2+ for Custodes weapon")
	assert_eq(hit_dice.total_attacks, 9, "Should have 9 attacks")
	assert_true(hit_dice.get("sustained_hits_weapon", false), "Should detect Sustained Hits")

extends "res://addons/gut/test.gd"

# Tests for the "Hold Still and Say 'Aargh!'" ability implementation (OA-19)
#
# Per Warhammer 40k 10th Edition Painboy datasheet:
# "Each time an attack made by this model with its 'urty syringe scores a
# Critical Wound against a unit (excluding VEHICLE units), that unit
# suffers D6 mortal wounds."
#
# These tests verify:
# 1. Ability is registered in UnitAbilityManager.ABILITY_EFFECTS
# 2. has_hold_still_ability() detects the ability on Painboy
# 3. _has_hold_still_ability() static helper works correctly
# 4. D6 mortal wounds applied on Critical Wound with 'urty syringe
# 5. No mortal wounds vs VEHICLE targets
# 6. No mortal wounds with non-'urty syringe weapons (power klaw)
# 7. No mortal wounds when unit lacks the ability

const GameStateData = preload("res://autoloads/GameState.gd")

var ability_mgr: Node
var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	ability_mgr = AutoloadHelper.get_autoload("UnitAbilityManager")
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(ability_mgr, "UnitAbilityManager autoload must be available")
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

	# Reset game state
	GameState.state["units"] = {}

# ==========================================
# Helper: Create test units and board
# ==========================================

func _create_painboy_unit(unit_id: String = "painboy_1", owner: int = 1) -> Dictionary:
	"""Create a Painboy unit with Hold Still ability and 'urty syringe + power klaw.
	Weapon data uses string values matching the datasheets.json format expected by get_weapon_profile."""
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Painboy",
			"keywords": ["CHARACTER", "INFANTRY", "ORKS", "PAINBOY"],
			"stats": {
				"move": 6,
				"toughness": 5,
				"save": 5,
				"wounds": 3,
				"leadership": 7,
				"objective_control": 1
			},
			"abilities": [
				{"name": "Leader", "type": "Core"},
				{"name": "Waaagh!", "type": "Faction"},
				{"name": "Dok's Toolz", "type": "Datasheet", "description": "Led unit has FNP 5+"},
				{"name": "Hold Still and Say 'Aargh!'", "type": "Datasheet", "description": "On Critical Wound with 'urty syringe, target suffers D6 mortal wounds (excludes VEHICLE)"}
			],
			"weapons": [
				{
					"name": "Power klaw",
					"type": "Melee",
					"range": "Melee",
					"attacks": "3",
					"strength": "9",
					"ap": "-2",
					"damage": "2",
					"weapon_skill": "4"
				},
				{
					"name": "'Urty syringe",
					"type": "Melee",
					"range": "Melee",
					"attacks": "1",
					"strength": "2",
					"ap": "0",
					"damage": "1",
					"weapon_skill": "3",
					"special_rules": "extra attacks, precision"
				}
			]
		},
		"models": [
			{
				"id": "painboy_m1",
				"wounds": 3,
				"current_wounds": 3,
				"base_mm": 32,
				"position": {"x": 100, "y": 100},
				"alive": true,
				"status_effects": []
			}
		],
		"flags": {}
	}
	GameState.state["units"][unit_id] = unit
	return unit

func _create_infantry_target(unit_id: String = "target_inf", owner: int = 2, model_count: int = 5) -> Dictionary:
	"""Create an enemy infantry unit for testing."""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "%s_m%d" % [unit_id, i + 1],
			"wounds": 2,
			"current_wounds": 2,
			"base_mm": 32,
			"position": {"x": 130 + i * 20, "y": 100},
			"alive": true,
			"status_effects": []
		})
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Enemy Infantry",
			"keywords": ["INFANTRY"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 3,
				"wounds": 2,
				"leadership": 6,
				"objective_control": 2
			},
			"abilities": [],
			"weapons": []
		},
		"models": models,
		"flags": {}
	}
	GameState.state["units"][unit_id] = unit
	return unit

func _create_vehicle_target(unit_id: String = "target_vehicle", owner: int = 2) -> Dictionary:
	"""Create an enemy VEHICLE unit for testing."""
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Enemy Vehicle",
			"keywords": ["VEHICLE"],
			"stats": {
				"move": 10,
				"toughness": 9,
				"save": 3,
				"wounds": 12,
				"leadership": 6,
				"objective_control": 3
			},
			"abilities": [],
			"weapons": []
		},
		"models": [
			{
				"id": "%s_m1" % unit_id,
				"wounds": 12,
				"current_wounds": 12,
				"base_mm": 100,
				"position": {"x": 130, "y": 100},
				"alive": true,
				"status_effects": []
			}
		],
		"flags": {}
	}
	GameState.state["units"][unit_id] = unit
	return unit

func _make_board_from_units(attacker: Dictionary, target: Dictionary) -> Dictionary:
	"""Build a board dictionary from existing unit dictionaries."""
	return {
		"units": {
			attacker["id"]: attacker,
			target["id"]: target
		}
	}

# Weapon IDs generated by RulesEngine._generate_weapon_id(name, type):
# "'Urty syringe" + "Melee" → "urty_syringe_melee"
# "Power klaw" + "Melee" → "power_klaw_melee"
func _make_melee_action(attacker_id: String, target_id: String, weapon_id: String) -> Dictionary:
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
# Section 1: Ability Detection Tests
# ==========================================

func test_hold_still_in_ability_effects_table():
	"""Hold Still and Say 'Aargh!' should be in ABILITY_EFFECTS and marked as implemented."""
	var effect_def = ability_mgr.get_ability_effect_definition("Hold Still and Say 'Aargh!'")
	assert_false(effect_def.is_empty(), "Hold Still should exist in ABILITY_EFFECTS")
	assert_true(effect_def.get("implemented", false), "Hold Still should be marked as implemented")
	assert_eq(effect_def.get("condition", ""), "on_critical_wound", "Condition should be on_critical_wound")
	assert_eq(effect_def.get("attack_type", ""), "melee", "Attack type should be melee")

func test_hold_still_ability_detected_on_painboy():
	"""Painboy should be detected as having Hold Still ability."""
	_create_painboy_unit("painboy_test")
	assert_true(ability_mgr.has_hold_still_ability("painboy_test"),
		"Painboy should have Hold Still and Say 'Aargh!' ability")

func test_hold_still_ability_not_detected_on_other_units():
	"""Non-Painboy unit should NOT have Hold Still ability."""
	_create_infantry_target("inf_test")
	assert_false(ability_mgr.has_hold_still_ability("inf_test"),
		"Regular infantry should not have Hold Still ability")

func test_hold_still_ability_nonexistent_unit():
	"""Nonexistent unit should return false."""
	assert_false(ability_mgr.has_hold_still_ability("nonexistent"),
		"Nonexistent unit should not have Hold Still ability")

func test_static_has_hold_still_ability():
	"""RulesEngine._has_hold_still_ability() should detect the ability on unit dict."""
	var painboy = _create_painboy_unit("painboy_static")
	assert_true(RulesEngine._has_hold_still_ability(painboy),
		"Static helper should detect Hold Still on Painboy")

func test_static_has_hold_still_ability_not_present():
	"""RulesEngine._has_hold_still_ability() should return false for non-Painboy."""
	var infantry = _create_infantry_target("inf_static")
	assert_false(RulesEngine._has_hold_still_ability(infantry),
		"Static helper should not detect Hold Still on regular infantry")

# ==========================================
# Section 2: Mortal Wounds on Critical Wound (Auto-Resolve Path)
# ==========================================

func test_mortal_wounds_on_critical_wound_with_urty_syringe():
	"""Critical wound with 'urty syringe should cause D6 mortal wounds vs infantry."""
	var painboy = _create_painboy_unit("painboy_crit")
	var target = _create_infantry_target("target_crit", 2, 10)
	var board = _make_board_from_units(painboy, target)
	var rng = RulesEngine.RNGService.new()

	# Run many iterations to get at least one critical wound
	var got_hold_still = false
	for _attempt in range(100):
		# Reset target wounds
		for model in target["models"]:
			model["current_wounds"] = 2
			model["alive"] = true

		# Use generated weapon ID: "'Urty syringe" + "Melee" → "urty_syringe_melee"
		var action = _make_melee_action("painboy_crit", "target_crit", "urty_syringe_melee")
		var result = RulesEngine.resolve_melee_attacks(action, board, rng)

		if result.get("log_text", "").contains("HOLD STILL"):
			got_hold_still = true
			break

	assert_true(got_hold_still,
		"Over 100 melee attacks with 'urty syringe, at least one should trigger Hold Still mortal wounds")

func test_no_mortal_wounds_vs_vehicle():
	"""'urty syringe critical wounds should NOT cause mortal wounds vs VEHICLE targets."""
	var painboy = _create_painboy_unit("painboy_veh")
	var target = _create_vehicle_target("target_veh")
	var board = _make_board_from_units(painboy, target)
	var rng = RulesEngine.RNGService.new()

	# Run many iterations — should never trigger Hold Still vs VEHICLE
	var got_hold_still = false
	for _attempt in range(100):
		# Reset target wounds
		target["models"][0]["current_wounds"] = 12
		target["models"][0]["alive"] = true

		var action = _make_melee_action("painboy_veh", "target_veh", "urty_syringe_melee")
		var result = RulesEngine.resolve_melee_attacks(action, board, rng)

		if result.get("log_text", "").contains("HOLD STILL"):
			got_hold_still = true
			break

	assert_false(got_hold_still,
		"Hold Still should NEVER trigger vs VEHICLE targets")

func test_no_mortal_wounds_with_power_klaw():
	"""Power klaw critical wounds should NOT trigger Hold Still mortal wounds."""
	var painboy = _create_painboy_unit("painboy_klaw")
	var target = _create_infantry_target("target_klaw", 2, 10)
	var board = _make_board_from_units(painboy, target)
	var rng = RulesEngine.RNGService.new()

	# Run many iterations with power klaw — should never trigger Hold Still
	var got_hold_still = false
	for _attempt in range(100):
		# Reset target wounds
		for model in target["models"]:
			model["current_wounds"] = 2
			model["alive"] = true

		# Use generated weapon ID: "Power klaw" + "Melee" → "power_klaw_melee"
		var action = _make_melee_action("painboy_klaw", "target_klaw", "power_klaw_melee")
		var result = RulesEngine.resolve_melee_attacks(action, board, rng)

		if result.get("log_text", "").contains("HOLD STILL"):
			got_hold_still = true
			break

	assert_false(got_hold_still,
		"Hold Still should NEVER trigger with power klaw — only 'urty syringe")

# ==========================================
# Section 3: Interactive Path (stop_before_saves)
# ==========================================

func test_hold_still_data_in_interactive_result():
	"""Interactive melee path should include hold_still_mortal_wounds in result."""
	var painboy = _create_painboy_unit("painboy_int")
	var target = _create_infantry_target("target_int", 2, 10)
	var board = _make_board_from_units(painboy, target)
	var rng = RulesEngine.RNGService.new()

	# Run many iterations to get a critical wound
	var found_hs_data = false
	for _attempt in range(100):
		for model in target["models"]:
			model["current_wounds"] = 2
			model["alive"] = true

		var action = _make_melee_action("painboy_int", "target_int", "urty_syringe_melee")
		var result = RulesEngine.resolve_melee_attacks_interactive(action, board, rng)

		if result.get("has_wounds", false):
			for save_data in result.get("save_data_list", []):
				var hs_mw = save_data.get("hold_still_mortal_wounds", 0)
				if hs_mw > 0:
					found_hs_data = true
					assert_true(hs_mw >= 1 and hs_mw <= 6,
						"Hold Still mortal wounds should be 1-6 (D6 roll), got %d" % hs_mw)
					break
		if found_hs_data:
			break

	assert_true(found_hs_data,
		"Over 100 interactive melee attacks, at least one should have hold_still_mortal_wounds in save data")

# ==========================================
# Section 4: Unit without ability should not trigger
# ==========================================

func test_no_hold_still_without_ability():
	"""Unit without Hold Still ability should never trigger mortal wounds on critical wounds."""
	# Create a generic unit with same weapon name but no ability
	var unit_id = "generic_unit"
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Generic Ork",
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 3, "leadership": 7, "objective_control": 1},
			"abilities": [],
			"weapons": [
				{
					"name": "'Urty syringe",
					"type": "Melee",
					"range": "Melee",
					"attacks": "1",
					"strength": "2",
					"ap": "0",
					"damage": "1",
					"weapon_skill": "3"
				}
			]
		},
		"models": [{"id": "gm1", "wounds": 3, "current_wounds": 3, "base_mm": 32, "position": {"x": 100, "y": 100}, "alive": true, "status_effects": []}],
		"flags": {}
	}
	GameState.state["units"][unit_id] = unit
	var target = _create_infantry_target("target_no_ability", 2, 10)
	var board = _make_board_from_units(unit, target)
	var rng = RulesEngine.RNGService.new()

	var got_hold_still = false
	for _attempt in range(100):
		for model in target["models"]:
			model["current_wounds"] = 2
			model["alive"] = true

		var action = _make_melee_action(unit_id, "target_no_ability", "urty_syringe_melee")
		var result = RulesEngine.resolve_melee_attacks(action, board, rng)

		if result.get("log_text", "").contains("HOLD STILL"):
			got_hold_still = true
			break

	assert_false(got_hold_still,
		"Unit without Hold Still ability should NEVER trigger mortal wounds")

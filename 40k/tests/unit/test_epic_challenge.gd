extends "res://addons/gut/test.gd"

# Tests for EPIC CHALLENGE stratagem implementation
#
# EPIC CHALLENGE (Core – Epic Deed Stratagem, 1 CP)
# - WHEN: Fight phase, when a CHARACTER unit from your army is selected to fight.
# - TARGET: One CHARACTER model in your unit.
# - EFFECT: Until end of phase, all melee attacks made by that model have the [PRECISION] ability.
# - RESTRICTION: Once per phase.
#
# PRECISION: Attacks that score a Critical Hit can be allocated to CHARACTER models
# in the target unit (bypassing normal allocation).
#
# These tests verify:
# 1. StratagemManager definition and validation for Epic Challenge
# 2. CP deduction when used
# 3. Once-per-phase restriction
# 4. CHARACTER keyword required
# 5. Effect flag set on target unit
# 6. Effect flag cleared at end of phase
# 7. RulesEngine has_precision() detects weapon-inherent PRECISION
# 8. RulesEngine has_effect_precision_melee() detects stratagem flag
# 9. RulesEngine PRECISION damage allocation targets CHARACTER models
# 10. Edge cases (no CP, battle-shocked, non-CHARACTER)

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_unit(id: String, model_count: int, owner: int = 1, keywords: Array = ["INFANTRY"], save: int = 3, toughness: int = 4, wounds: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": wounds,
			"current_wounds": wounds,
			"base_mm": 32,
			"position": {"x": 100 + i * 20, "y": 100},
			"alive": true,
			"status_effects": []
		})
	return {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Unit %s" % id,
			"keywords": keywords,
			"stats": {
				"move": 6,
				"toughness": toughness,
				"save": save,
				"wounds": wounds,
				"leadership": 7,
				"objective_control": 1
			},
			"weapons": [],
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _setup_fight_scenario() -> void:
	"""Set up a basic fight scenario: Player 1 fights with a CHARACTER unit."""
	GameState.state.meta.phase = GameStateData.Phase.FIGHT
	GameState.state.meta.active_player = 1
	GameState.state.meta.battle_round = 2

	# Player 1 (attacker) CHARACTER unit - eligible for Epic Challenge
	var character_unit = _create_unit("U_CHARACTER", 1, 1, ["INFANTRY", "CHARACTER"], 2, 5, 6)
	character_unit.meta.weapons = [{
		"name": "Power Sword",
		"type": "Melee",
		"range": "Melee",
		"attacks": "5",
		"weapon_skill": "2",
		"strength": "5",
		"ap": "-3",
		"damage": "2",
		"special_rules": ""
	}]
	GameState.state.units["U_CHARACTER"] = character_unit

	# Player 1 (attacker) non-CHARACTER unit - not eligible for Epic Challenge
	var infantry_unit = _create_unit("U_INFANTRY", 5, 1, ["INFANTRY"], 3, 4, 1)
	GameState.state.units["U_INFANTRY"] = infantry_unit

	# Player 2 (defender) unit - target with a character leader attached
	var defender = _create_unit("U_DEFENDER", 5, 2, ["INFANTRY"], 4, 4, 1)
	GameState.state.units["U_DEFENDER"] = defender

	# Player 2 CHARACTER target unit
	var char_defender = _create_unit("U_DEFENDER_CHAR", 3, 2, ["INFANTRY", "CHARACTER"], 3, 4, 3)
	GameState.state.units["U_DEFENDER_CHAR"] = char_defender

	# Give both players CP
	GameState.state.players["1"]["cp"] = 5
	GameState.state.players["2"]["cp"] = 5

	StratagemManager.reset_for_new_game()

func before_each():
	GameState.state.units.clear()
	StratagemManager.reset_for_new_game()


# ==========================================
# Section 1: Stratagem Definitions
# ==========================================

func test_epic_challenge_definition_loaded():
	"""Epic Challenge stratagem should be loaded with correct properties."""
	var strat = StratagemManager.get_stratagem("epic_challenge")
	assert_false(strat.is_empty(), "Epic Challenge should be loaded")
	assert_eq(strat.name, "EPIC CHALLENGE")
	assert_eq(strat.cp_cost, 1)
	assert_eq(strat.timing.turn, "either")
	assert_eq(strat.timing.phase, "fight")
	assert_eq(strat.timing.trigger, "fighter_selected")

func test_epic_challenge_effects():
	"""Epic Challenge should have grant_keyword PRECISION effect."""
	var strat = StratagemManager.get_stratagem("epic_challenge")
	assert_eq(strat.effects.size(), 1, "Should have 1 effect")

	var effect = strat.effects[0]
	assert_eq(effect.type, "grant_keyword", "Effect type should be grant_keyword")
	assert_eq(effect.keyword, "PRECISION", "Should grant PRECISION keyword")
	assert_eq(effect.scope, "melee", "Scope should be melee")

func test_epic_challenge_restriction():
	"""Epic Challenge should have once-per-phase restriction."""
	var strat = StratagemManager.get_stratagem("epic_challenge")
	assert_eq(strat.restrictions.once_per, "phase", "Should be once per phase")


# ==========================================
# Section 2: Validation
# ==========================================

func test_can_use_epic_challenge_on_character():
	"""Player should be able to use Epic Challenge on CHARACTER unit."""
	_setup_fight_scenario()

	var result = StratagemManager.is_epic_challenge_available(1, "U_CHARACTER")
	assert_true(result.available, "Should be available for CHARACTER unit: %s" % result.get("reason", ""))

func test_cannot_use_epic_challenge_on_non_character():
	"""Cannot use Epic Challenge on non-CHARACTER unit."""
	_setup_fight_scenario()

	var result = StratagemManager.is_epic_challenge_available(1, "U_INFANTRY")
	assert_false(result.available, "Should not be available for non-CHARACTER unit")
	assert_string_contains(result.reason, "CHARACTER")

func test_cannot_use_epic_challenge_with_zero_cp():
	"""Cannot use Epic Challenge with 0 CP."""
	_setup_fight_scenario()
	GameState.state.players["1"]["cp"] = 0

	var result = StratagemManager.is_epic_challenge_available(1, "U_CHARACTER")
	assert_false(result.available, "Should not be available with 0 CP")

func test_cannot_use_epic_challenge_twice_per_phase():
	"""Epic Challenge once-per-phase restriction."""
	_setup_fight_scenario()

	# First use should succeed
	var result1 = StratagemManager.use_stratagem(1, "epic_challenge", "U_CHARACTER")
	assert_true(result1.success, "First use should succeed")

	# Second use in same phase should fail
	var result2 = StratagemManager.is_epic_challenge_available(1, "U_CHARACTER")
	assert_false(result2.available, "Second use should be blocked (once per phase)")

func test_cannot_use_epic_challenge_on_battle_shocked():
	"""Battle-shocked units cannot use Epic Challenge."""
	_setup_fight_scenario()
	GameState.state.units["U_CHARACTER"]["flags"]["battle_shocked"] = true

	var result = StratagemManager.is_epic_challenge_available(1, "U_CHARACTER")
	assert_false(result.available, "Should not be available for battle-shocked unit")


# ==========================================
# Section 3: Effect Application
# ==========================================

func test_epic_challenge_sets_precision_flag():
	"""Using Epic Challenge should set effect_precision_melee flag on the unit."""
	_setup_fight_scenario()

	var result = StratagemManager.use_stratagem(1, "epic_challenge", "U_CHARACTER")
	assert_true(result.success, "Use should succeed")

	var unit = GameState.get_unit("U_CHARACTER")
	var flags = unit.get("flags", {})
	assert_true(flags.get("effect_precision_melee", false), "Should have effect_precision_melee flag")

func test_epic_challenge_deducts_cp():
	"""Using Epic Challenge should deduct 1 CP."""
	_setup_fight_scenario()

	StratagemManager.use_stratagem(1, "epic_challenge", "U_CHARACTER")
	assert_eq(GameState.state.players["1"]["cp"], 4, "CP should be deducted from 5 to 4")

func test_epic_challenge_active_effect_tracked():
	"""StratagemManager should track active effect for the unit."""
	_setup_fight_scenario()

	StratagemManager.use_stratagem(1, "epic_challenge", "U_CHARACTER")

	var effects = StratagemManager.get_active_effects_for_unit("U_CHARACTER")
	assert_eq(effects.size(), 1, "Should have 1 active effect")
	assert_eq(effects[0].stratagem_id, "epic_challenge")

func test_epic_challenge_has_active_effect():
	"""has_active_effect should return true for grant_keyword effect."""
	_setup_fight_scenario()

	StratagemManager.use_stratagem(1, "epic_challenge", "U_CHARACTER")

	assert_true(StratagemManager.has_active_effect("U_CHARACTER", "grant_keyword"), "Should detect grant_keyword effect")


# ==========================================
# Section 4: Effect Expiry
# ==========================================

func test_epic_challenge_flag_cleared_on_phase_end():
	"""Epic Challenge flag should be cleared when the fight phase ends."""
	_setup_fight_scenario()

	StratagemManager.use_stratagem(1, "epic_challenge", "U_CHARACTER")

	# Verify flag is set
	var flags_before = GameState.get_unit("U_CHARACTER").get("flags", {})
	assert_true(flags_before.get("effect_precision_melee", false), "Flag should be set before phase end")

	# Simulate phase end
	StratagemManager.on_phase_end(GameStateData.Phase.FIGHT)

	# Flag should be cleared
	var flags_after = GameState.get_unit("U_CHARACTER").get("flags", {})
	assert_false(flags_after.get("effect_precision_melee", false), "Flag should be cleared after phase end")


# ==========================================
# Section 5: RulesEngine PRECISION Detection
# ==========================================

func test_has_precision_from_weapon_special_rules():
	"""RulesEngine.has_precision should detect PRECISION from weapon special_rules."""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"name": "Vaultswords Behemor",
						"type": "Melee",
						"special_rules": "precision"
					}]
				}
			}
		}
	}
	assert_true(RulesEngine.has_precision("vaultswords_behemor", board), "Should detect precision from special_rules")

func test_has_precision_negative():
	"""RulesEngine.has_precision should return false for weapons without PRECISION."""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"name": "Power Sword",
						"type": "Melee",
						"special_rules": "lethal hits"
					}]
				}
			}
		}
	}
	assert_false(RulesEngine.has_precision("power_sword", board), "Should not detect precision")

func test_has_effect_precision_melee():
	"""RulesEngine.has_effect_precision_melee should detect stratagem flag."""
	var unit_with_flag = {"flags": {"effect_precision_melee": true}}
	var unit_without_flag = {"flags": {}}
	var unit_no_flags = {}

	assert_true(RulesEngine.has_effect_precision_melee(unit_with_flag), "Should detect flag")
	assert_false(RulesEngine.has_effect_precision_melee(unit_without_flag), "Should not detect when flag absent")
	assert_false(RulesEngine.has_effect_precision_melee(unit_no_flags), "Should not detect when no flags dict")


# ==========================================
# Section 6: RulesEngine CHARACTER Model Detection
# ==========================================

func test_find_character_model_indices_unit_keyword():
	"""Should find all alive models when unit has CHARACTER keyword."""
	var unit = {
		"meta": {"keywords": ["INFANTRY", "CHARACTER"]},
		"models": [
			{"alive": true},
			{"alive": true},
			{"alive": false},
			{"alive": true}
		]
	}
	var indices = RulesEngine._find_character_model_indices(unit)
	assert_eq(indices.size(), 3, "Should find 3 alive models")
	assert_has(indices, 0)
	assert_has(indices, 1)
	assert_has(indices, 3)

func test_find_character_model_indices_no_character():
	"""Should return empty when unit has no CHARACTER keyword."""
	var unit = {
		"meta": {"keywords": ["INFANTRY"]},
		"models": [
			{"alive": true},
			{"alive": true}
		]
	}
	var indices = RulesEngine._find_character_model_indices(unit)
	assert_eq(indices.size(), 0, "Should find no CHARACTER models in non-CHARACTER unit")

func test_find_character_model_indices_model_keyword():
	"""Should find models with CHARACTER keyword at model level (attached leaders)."""
	var unit = {
		"meta": {"keywords": ["INFANTRY"]},
		"models": [
			{"alive": true, "keywords": ["CHARACTER"]},
			{"alive": true, "keywords": []},
			{"alive": true, "keywords": []},
			{"alive": true, "keywords": ["CHARACTER"]},
			{"alive": false, "keywords": ["CHARACTER"]}
		]
	}
	var indices = RulesEngine._find_character_model_indices(unit)
	assert_eq(indices.size(), 2, "Should find 2 alive CHARACTER models")
	assert_has(indices, 0)
	assert_has(indices, 3)


# ==========================================
# Section 7: RulesEngine PRECISION Integration
# ==========================================

func _make_precision_board(attacker_weapons: Array, attacker_flags: Dictionary = {}, attacker_keywords: Array = ["INFANTRY", "CHARACTER"], target_keywords: Array = ["INFANTRY", "CHARACTER"]) -> Dictionary:
	"""Create a board for PRECISION testing with CHARACTER models."""
	var attacker_models = [{
		"alive": true,
		"current_wounds": 6,
		"wounds": 6,
		"position": {"x": 100, "y": 100}
	}]

	# Target has 3 models: one with CHARACTER keyword, two regular
	var target_models = [
		{"alive": true, "current_wounds": 3, "wounds": 3, "position": {"x": 130, "y": 100}},
		{"alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 150, "y": 100}},
		{"alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 170, "y": 100}}
	]

	return {
		"units": {
			"attacker_unit": {
				"owner": 1,
				"models": attacker_models,
				"meta": {
					"name": "Test Character",
					"stats": {"toughness": 5, "save": 2, "wounds": 6},
					"weapons": attacker_weapons,
					"keywords": attacker_keywords
				},
				"flags": attacker_flags
			},
			"target_unit": {
				"owner": 2,
				"models": target_models,
				"meta": {
					"name": "Target Unit",
					"stats": {"toughness": 4, "save": 4, "wounds": 1},
					"keywords": target_keywords
				}
			}
		}
	}

func test_precision_detected_in_melee_resolution():
	"""When stratagem flag is set, PRECISION should be detected during melee resolution."""
	var weapons = [{
		"name": "Power Sword",
		"type": "Melee",
		"attacks": "5",
		"weapon_skill": "2",
		"strength": "5",
		"ap": "-3",
		"damage": "1",
		"special_rules": ""
	}]

	var board = _make_precision_board(weapons, {"effect_precision_melee": true})
	var action = {
		"actor_unit_id": "attacker_unit",
		"payload": {
			"assignments": [{
				"attacker": "attacker_unit",
				"target": "target_unit",
				"weapon": "power_sword"
			}]
		}
	}

	var rng = RNGService.new()
	var result = RulesEngine.resolve_melee_attacks(action, board, rng)
	assert_true(result.success, "Resolution should succeed")

	# Check that PRECISION was tracked in dice data
	var has_precision_flag = false
	for dice in result.dice:
		if dice.get("precision_weapon", false):
			has_precision_flag = true
			break
	assert_true(has_precision_flag, "Dice data should track precision_weapon flag")

func test_precision_from_weapon_special_rules_in_resolution():
	"""When weapon has precision special rule, it should be detected."""
	var weapons = [{
		"name": "Vaultswords Behemor",
		"type": "Melee",
		"attacks": "6",
		"weapon_skill": "2",
		"strength": "7",
		"ap": "-2",
		"damage": "2",
		"special_rules": "precision"
	}]

	var board = _make_precision_board(weapons, {})  # No stratagem flag
	var action = {
		"actor_unit_id": "attacker_unit",
		"payload": {
			"assignments": [{
				"attacker": "attacker_unit",
				"target": "target_unit",
				"weapon": "vaultswords_behemor"
			}]
		}
	}

	var rng = RNGService.new()
	var result = RulesEngine.resolve_melee_attacks(action, board, rng)
	assert_true(result.success, "Resolution should succeed")

	# Check that PRECISION was tracked
	var has_precision_flag = false
	for dice in result.dice:
		if dice.get("precision_weapon", false):
			has_precision_flag = true
			break
	assert_true(has_precision_flag, "Weapon's own precision should be detected")


# ==========================================
# Section 8: PRECISION Damage Allocation
# ==========================================

func test_apply_damage_to_character_models():
	"""_apply_damage_to_character_models should target CHARACTER model indices."""
	var models = [
		{"alive": true, "current_wounds": 3, "wounds": 3},  # CHARACTER (index 0)
		{"alive": true, "current_wounds": 1, "wounds": 1},  # Regular
		{"alive": true, "current_wounds": 1, "wounds": 1},  # Regular
	]

	var character_indices = [0]
	var result = RulesEngine._apply_damage_to_character_models("test_unit", 2, models, character_indices, {})

	assert_eq(result.damage_applied, 2, "Should apply 2 damage")
	assert_eq(result.casualties, 0, "CHARACTER model has 3 wounds, should survive 2 damage")
	assert_eq(models[0].current_wounds, 1, "CHARACTER model should have 1 wound remaining")
	assert_eq(models[1].current_wounds, 1, "Regular model should be untouched")

func test_apply_damage_to_character_kills():
	"""Precision damage should kill CHARACTER model when damage exceeds wounds."""
	var models = [
		{"alive": true, "current_wounds": 2, "wounds": 3},  # CHARACTER (wounded)
		{"alive": true, "current_wounds": 1, "wounds": 1},
	]

	var character_indices = [0]
	var result = RulesEngine._apply_damage_to_character_models("test_unit", 3, models, character_indices, {})

	assert_eq(result.casualties, 1, "CHARACTER should die")
	assert_false(models[0].alive, "CHARACTER model should be dead")
	assert_eq(models[1].current_wounds, 1, "Regular model should be untouched")

func test_precision_damage_stops_when_characters_dead():
	"""Precision damage should stop when all CHARACTER models are dead."""
	var models = [
		{"alive": true, "current_wounds": 1, "wounds": 1},  # CHARACTER
		{"alive": true, "current_wounds": 1, "wounds": 1},  # Regular
	]

	var character_indices = [0]
	# Apply 5 damage, but only 1 wound on CHARACTER
	var result = RulesEngine._apply_damage_to_character_models("test_unit", 5, models, character_indices, {})

	assert_eq(result.damage_applied, 1, "Should only apply 1 damage to CHARACTER")
	assert_eq(result.casualties, 1, "CHARACTER should die")
	assert_true(models[1].alive, "Regular model should NOT be affected by precision damage")


# ==========================================
# Section 9: Full Integration
# ==========================================

func test_epic_challenge_full_flow():
	"""Test full flow: use stratagem -> flag set -> RulesEngine detects it."""
	_setup_fight_scenario()

	# Use Epic Challenge
	var strat_result = StratagemManager.use_stratagem(1, "epic_challenge", "U_CHARACTER")
	assert_true(strat_result.success, "Stratagem use should succeed")

	# Verify flag
	var unit = GameState.get_unit("U_CHARACTER")
	assert_true(unit.get("flags", {}).get("effect_precision_melee", false), "Flag should be set")

	# Verify RulesEngine detects it
	assert_true(RulesEngine.has_effect_precision_melee(unit), "RulesEngine should detect stratagem flag")

	# Verify CP was deducted
	assert_eq(GameState.state.players["1"]["cp"], 4, "CP should be 4 after use")

	# Verify once-per-phase
	var check2 = StratagemManager.is_epic_challenge_available(1, "U_CHARACTER")
	assert_false(check2.available, "Should not be available again this phase")


# ==========================================
# Section 10: Edge Cases
# ==========================================

func test_epic_challenge_for_nonexistent_unit():
	"""Epic Challenge check for nonexistent unit should return unavailable."""
	_setup_fight_scenario()

	var result = StratagemManager.is_epic_challenge_available(1, "NONEXISTENT")
	assert_false(result.available, "Should not be available for nonexistent unit")

func test_precision_no_character_in_target():
	"""When target has no CHARACTER models, PRECISION has no special effect."""
	var weapons = [{
		"name": "Power Sword",
		"type": "Melee",
		"attacks": "5",
		"weapon_skill": "2",
		"strength": "5",
		"ap": "-3",
		"damage": "1",
		"special_rules": ""
	}]

	# Target has no CHARACTER keyword
	var board = _make_precision_board(weapons, {"effect_precision_melee": true}, ["INFANTRY", "CHARACTER"], ["INFANTRY"])
	var action = {
		"actor_unit_id": "attacker_unit",
		"payload": {
			"assignments": [{
				"attacker": "attacker_unit",
				"target": "target_unit",
				"weapon": "power_sword"
			}]
		}
	}

	# This should succeed without errors even though target has no CHARACTER models
	var rng = RNGService.new()
	var result = RulesEngine.resolve_melee_attacks(action, board, rng)
	assert_true(result.success, "Should succeed even when target has no CHARACTER models")

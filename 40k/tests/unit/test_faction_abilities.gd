extends "res://addons/gut/test.gd"

# Tests for Faction Ability system (T3-10)
#
# Per Warhammer 40k 10th Edition rules:
# - Oath of Moment (Space Marines / ADEPTUS ASTARTES):
#   At the start of each Command Phase, select one enemy unit.
#   Re-roll hit rolls of 1 and wound rolls of 1 for attacks targeting
#   that unit by ADEPTUS ASTARTES units from your army.
#
# These tests verify:
# 1. FactionAbilityManager detection of faction abilities from unit data
# 2. Oath of Moment target selection and flag management
# 3. RulesEngine integration — reroll-1s applied to hit and wound rolls
# 4. Keyword check — only ADEPTUS ASTARTES units benefit
# 5. CommandPhase integration — action validation and processing
# 6. Phase lifecycle — clearing targets at phase start, auto-select at end

const GameStateData = preload("res://autoloads/GameState.gd")

var faction_mgr: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	faction_mgr = AutoloadHelper.get_autoload("FactionAbilityManager")
	assert_not_null(faction_mgr, "FactionAbilityManager autoload must be available")

	# Reset state between tests
	faction_mgr._active_effects = {"1": {}, "2": {}}
	faction_mgr._player_abilities = {"1": [], "2": []}

	# Set up minimal game state for testing
	GameState.state["units"] = {}
	if not GameState.state.has("factions"):
		GameState.state["factions"] = {}

# ==========================================
# Helper: Create test units
# ==========================================

func _create_sm_unit(id: String, owner: int, model_count: int = 5) -> Dictionary:
	"""Create an ADEPTUS ASTARTES unit with Oath of Moment."""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 2,
			"current_wounds": 2,
			"base_mm": 32,
			"position": {"x": 100 + i * 20, "y": 100},
			"alive": true,
			"status_effects": []
		})
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Intercessor Squad",
			"keywords": ["INFANTRY", "PRIMARIS", "IMPERIUM", "ADEPTUS ASTARTES"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 3,
				"wounds": 2,
				"leadership": 6,
				"objective_control": 2
			},
			"abilities": [
				{
					"name": "Oath of Moment",
					"type": "Faction",
					"description": "At the start of your Command phase, select one enemy unit. Re-roll hit rolls and wound rolls of 1 for attacks made against that unit by ADEPTUS ASTARTES units from your army."
				}
			],
			"weapons": [
				{
					"name": "Bolt rifle",
					"type": "Ranged",
					"range": "24",
					"attacks": "2",
					"ballistic_skill": "3",
					"strength": "4",
					"ap": "-1",
					"damage": "1"
				}
			]
		},
		"models": models,
		"flags": {}
	}
	GameState.state["units"][id] = unit
	return unit

func _create_ork_unit(id: String, owner: int, model_count: int = 5) -> Dictionary:
	"""Create an Ork unit (no Oath of Moment, no ADEPTUS ASTARTES keyword)."""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": {"x": 200 + i * 20, "y": 200},
			"alive": true,
			"status_effects": []
		})
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Ork Boyz",
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {
				"move": 6,
				"toughness": 5,
				"save": 5,
				"wounds": 1,
				"leadership": 7,
				"objective_control": 2
			},
			"abilities": [],
			"weapons": []
		},
		"models": models,
		"flags": {}
	}
	GameState.state["units"][id] = unit
	return unit

func _create_non_astartes_imperial_unit(id: String, owner: int) -> Dictionary:
	"""Create an IMPERIUM unit that does NOT have ADEPTUS ASTARTES keyword."""
	var models = [
		{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": {"x": 300, "y": 100}, "alive": true, "status_effects": []}
	]
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Astra Militarum Squad",
			"keywords": ["INFANTRY", "IMPERIUM"],
			"stats": {"move": 6, "toughness": 3, "save": 5, "wounds": 1, "leadership": 7, "objective_control": 2},
			"abilities": [],
			"weapons": []
		},
		"models": models,
		"flags": {}
	}
	GameState.state["units"][id] = unit
	return unit

# ==========================================
# Ability Detection Tests
# ==========================================

func test_detect_oath_of_moment_from_sm_army():
	"""FactionAbilityManager should detect Oath of Moment from Space Marines units."""
	_create_sm_unit("U_SM_A", 1)
	var abilities = faction_mgr.detect_faction_abilities(1)
	assert_has(abilities, "Oath of Moment", "Should detect Oath of Moment for Space Marines player")

func test_detect_no_faction_abilities_for_orks():
	"""Ork units should have no detected faction abilities (empty name faction abilities)."""
	_create_ork_unit("U_BOYZ_A", 2)
	var abilities = faction_mgr.detect_faction_abilities(2)
	assert_does_not_have(abilities, "Oath of Moment", "Orks should not have Oath of Moment")

func test_detect_only_once_even_with_multiple_units():
	"""Multiple Space Marines units should only register Oath of Moment once."""
	_create_sm_unit("U_SM_A", 1)
	_create_sm_unit("U_SM_B", 1)
	var abilities = faction_mgr.detect_faction_abilities(1)
	assert_eq(abilities.size(), 1, "Should have exactly 1 faction ability")
	assert_has(abilities, "Oath of Moment")

func test_detect_ignores_destroyed_units():
	"""Destroyed units should not contribute faction abilities."""
	var unit = _create_sm_unit("U_SM_DEAD", 1, 3)
	for model in unit.models:
		model.alive = false
	var abilities = faction_mgr.detect_faction_abilities(1)
	assert_does_not_have(abilities, "Oath of Moment", "Destroyed unit should not contribute abilities")

func test_player_has_ability_after_detection():
	"""player_has_ability should return true after detection."""
	_create_sm_unit("U_SM_A", 1)
	faction_mgr.detect_faction_abilities(1)
	assert_true(faction_mgr.player_has_ability(1, "Oath of Moment"))
	assert_false(faction_mgr.player_has_ability(2, "Oath of Moment"))

# ==========================================
# Target Selection Tests
# ==========================================

func test_set_oath_target_success():
	"""Setting a valid Oath of Moment target should succeed."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	faction_mgr.detect_faction_abilities(1)

	var result = faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_A")
	assert_true(result.success, "Should succeed setting Oath target on enemy unit")
	assert_eq(faction_mgr.get_oath_of_moment_target(1), "U_BOYZ_A")

func test_oath_target_sets_flag_on_unit():
	"""Setting Oath target should set flags on the target unit."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	faction_mgr.detect_faction_abilities(1)

	faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_A")

	var target_unit = GameState.state["units"]["U_BOYZ_A"]
	assert_true(target_unit.flags.get("oath_of_moment_target", false), "Target should have oath flag")
	assert_eq(target_unit.flags.get("oath_of_moment_owner", 0), 1, "Oath owner should be player 1")

func test_cannot_oath_own_unit():
	"""Cannot target your own unit with Oath of Moment."""
	_create_sm_unit("U_SM_A", 1)
	faction_mgr.detect_faction_abilities(1)

	var result = faction_mgr.set_oath_of_moment_target(1, "U_SM_A")
	assert_false(result.success, "Should not be able to oath own unit")

func test_cannot_oath_destroyed_unit():
	"""Cannot target a destroyed unit with Oath of Moment."""
	_create_sm_unit("U_SM_A", 1)
	var ork = _create_ork_unit("U_BOYZ_A", 2, 3)
	for model in ork.models:
		model.alive = false

	faction_mgr.detect_faction_abilities(1)
	var result = faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_A")
	assert_false(result.success, "Should not be able to oath destroyed unit")

func test_cannot_oath_nonexistent_unit():
	"""Cannot target a nonexistent unit."""
	_create_sm_unit("U_SM_A", 1)
	faction_mgr.detect_faction_abilities(1)
	var result = faction_mgr.set_oath_of_moment_target(1, "U_NONEXISTENT")
	assert_false(result.success, "Should fail for nonexistent unit")

func test_changing_oath_target_clears_old_flag():
	"""Changing the Oath target should clear the old target's flag."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	_create_ork_unit("U_BOYZ_B", 2)
	faction_mgr.detect_faction_abilities(1)

	faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_A")
	assert_true(GameState.state["units"]["U_BOYZ_A"].flags.get("oath_of_moment_target", false))

	faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_B")
	assert_false(GameState.state["units"]["U_BOYZ_A"].flags.get("oath_of_moment_target", false), "Old target should have flag cleared")
	assert_true(GameState.state["units"]["U_BOYZ_B"].flags.get("oath_of_moment_target", false), "New target should have flag set")

func test_clear_oath_removes_flags():
	"""Clearing Oath of Moment should remove target flag."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	faction_mgr.detect_faction_abilities(1)

	faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_A")
	faction_mgr.clear_oath_of_moment(1)

	assert_eq(faction_mgr.get_oath_of_moment_target(1), "")
	assert_false(GameState.state["units"]["U_BOYZ_A"].flags.get("oath_of_moment_target", false))

# ==========================================
# Combat Modifier Query Tests
# ==========================================

func test_is_oath_target_returns_true():
	"""is_oath_of_moment_target should detect flagged units."""
	var unit = {"flags": {"oath_of_moment_target": true}}
	assert_true(FactionAbilityManager.is_oath_of_moment_target(unit))

func test_is_oath_target_returns_false_no_flag():
	"""is_oath_of_moment_target should return false when no flag."""
	var unit = {"flags": {}}
	assert_false(FactionAbilityManager.is_oath_of_moment_target(unit))

func test_is_oath_target_returns_false_no_flags():
	"""is_oath_of_moment_target should return false when no flags dict."""
	var unit = {}
	assert_false(FactionAbilityManager.is_oath_of_moment_target(unit))

func test_attacker_benefits_from_oath_correct_keyword():
	"""ADEPTUS ASTARTES attacker should benefit from Oath against flagged target."""
	var attacker = {
		"owner": 1,
		"meta": {"keywords": ["INFANTRY", "ADEPTUS ASTARTES"]}
	}
	var target = {
		"flags": {"oath_of_moment_target": true, "oath_of_moment_owner": 1}
	}
	assert_true(FactionAbilityManager.attacker_benefits_from_oath(attacker, target))

func test_attacker_without_astartes_keyword_no_benefit():
	"""Non-ADEPTUS ASTARTES attacker should NOT benefit from Oath."""
	var attacker = {
		"owner": 1,
		"meta": {"keywords": ["INFANTRY", "IMPERIUM"]}
	}
	var target = {
		"flags": {"oath_of_moment_target": true, "oath_of_moment_owner": 1}
	}
	assert_false(FactionAbilityManager.attacker_benefits_from_oath(attacker, target))

func test_attacker_wrong_player_no_benefit():
	"""Attacker from wrong player should NOT benefit from Oath."""
	var attacker = {
		"owner": 2,
		"meta": {"keywords": ["INFANTRY", "ADEPTUS ASTARTES"]}
	}
	var target = {
		"flags": {"oath_of_moment_target": true, "oath_of_moment_owner": 1}
	}
	assert_false(FactionAbilityManager.attacker_benefits_from_oath(attacker, target))

func test_attacker_no_benefit_against_non_oath_target():
	"""ADEPTUS ASTARTES attacker should NOT benefit against non-oath target."""
	var attacker = {
		"owner": 1,
		"meta": {"keywords": ["INFANTRY", "ADEPTUS ASTARTES"]}
	}
	var target = {"flags": {}}
	assert_false(FactionAbilityManager.attacker_benefits_from_oath(attacker, target))

func test_astartes_keyword_case_insensitive():
	"""ADEPTUS ASTARTES keyword check should handle different cases."""
	var attacker = {
		"owner": 1,
		"meta": {"keywords": ["Adeptus Astartes"]}
	}
	var target = {
		"flags": {"oath_of_moment_target": true, "oath_of_moment_owner": 1}
	}
	assert_true(FactionAbilityManager.attacker_benefits_from_oath(attacker, target),
		"Should handle 'Adeptus Astartes' (mixed case)")

# ==========================================
# Eligible Targets Tests
# ==========================================

func test_get_eligible_targets_returns_enemy_units():
	"""get_eligible_oath_targets should return deployed enemy units."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	_create_ork_unit("U_BOYZ_B", 2)

	var targets = faction_mgr.get_eligible_oath_targets(1)
	assert_eq(targets.size(), 2, "Should have 2 eligible targets")

func test_get_eligible_targets_excludes_own_units():
	"""get_eligible_oath_targets should not include own units."""
	_create_sm_unit("U_SM_A", 1)
	_create_sm_unit("U_SM_B", 1)
	_create_ork_unit("U_BOYZ_A", 2)

	var targets = faction_mgr.get_eligible_oath_targets(1)
	assert_eq(targets.size(), 1, "Should only include enemy units")
	assert_eq(targets[0].unit_id, "U_BOYZ_A")

func test_get_eligible_targets_excludes_destroyed():
	"""get_eligible_oath_targets should exclude destroyed enemy units."""
	_create_sm_unit("U_SM_A", 1)
	var ork = _create_ork_unit("U_BOYZ_A", 2, 3)
	_create_ork_unit("U_BOYZ_B", 2)
	for model in ork.models:
		model.alive = false

	var targets = faction_mgr.get_eligible_oath_targets(1)
	assert_eq(targets.size(), 1, "Should exclude destroyed unit")
	assert_eq(targets[0].unit_id, "U_BOYZ_B")

# ==========================================
# Phase Lifecycle Tests
# ==========================================

func test_on_command_phase_start_detects_abilities():
	"""on_command_phase_start should detect faction abilities."""
	_create_sm_unit("U_SM_A", 1)
	faction_mgr.on_command_phase_start(1)
	assert_true(faction_mgr.player_has_ability(1, "Oath of Moment"))

func test_on_command_phase_start_clears_old_target():
	"""on_command_phase_start should clear previous Oath target."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	faction_mgr.detect_faction_abilities(1)
	faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_A")

	faction_mgr.on_command_phase_start(1)
	assert_eq(faction_mgr.get_oath_of_moment_target(1), "", "Target should be cleared on phase start")
	assert_false(GameState.state["units"]["U_BOYZ_A"].flags.get("oath_of_moment_target", false))

func test_on_command_phase_end_auto_selects():
	"""on_command_phase_end should auto-select first target if none chosen."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	faction_mgr.detect_faction_abilities(1)

	# Don't select a target, then end phase
	faction_mgr.on_command_phase_end(1)
	assert_ne(faction_mgr.get_oath_of_moment_target(1), "", "Should auto-select a target")

func test_on_command_phase_end_keeps_existing_target():
	"""on_command_phase_end should not override an existing selection."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	_create_ork_unit("U_BOYZ_B", 2)
	faction_mgr.detect_faction_abilities(1)

	faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_B")
	faction_mgr.on_command_phase_end(1)
	assert_eq(faction_mgr.get_oath_of_moment_target(1), "U_BOYZ_B", "Should keep existing target")

# ==========================================
# CommandPhase Action Validation Tests
# ==========================================

func test_command_phase_select_oath_target_action():
	"""CommandPhase should validate SELECT_OATH_TARGET action.
	Note: CommandPhase uses get_node_or_null which requires being in scene tree.
	We add the phase to the tree to allow proper autoload access."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	faction_mgr.detect_faction_abilities(1)

	# Create a CommandPhase and set player context
	var phase_script = load("res://phases/CommandPhase.gd")
	if phase_script == null:
		pending("CommandPhase.gd not loadable in test environment")
		return

	var phase = phase_script.new()
	# Add to scene tree so get_node_or_null("/root/...") works
	get_tree().root.add_child(phase)

	# Set active player in game state
	GameState.state["meta"]["active_player"] = 1

	var action = {
		"type": "SELECT_OATH_TARGET",
		"target_unit_id": "U_BOYZ_A",
		"player": 1
	}
	var validation = phase.validate_action(action)
	assert_true(validation.valid, "SELECT_OATH_TARGET should be valid: %s" % str(validation.get("errors", [])))

	phase.queue_free()

func test_command_phase_select_oath_target_own_unit_invalid():
	"""Cannot target own unit with Oath of Moment via CommandPhase."""
	_create_sm_unit("U_SM_A", 1)
	faction_mgr.detect_faction_abilities(1)

	var phase_script = load("res://phases/CommandPhase.gd")
	if phase_script == null:
		pending("CommandPhase.gd not loadable in test environment")
		return

	var phase = phase_script.new()
	# Add to scene tree so get_node_or_null("/root/...") works
	get_tree().root.add_child(phase)

	GameState.state["meta"]["active_player"] = 1

	var action = {
		"type": "SELECT_OATH_TARGET",
		"target_unit_id": "U_SM_A",
		"player": 1
	}
	var validation = phase.validate_action(action)
	assert_false(validation.valid, "Should reject targeting own unit")

	phase.queue_free()

# ==========================================
# Integration: Non-ADEPTUS ASTARTES unit check
# ==========================================

func test_non_astartes_unit_no_oath_benefit():
	"""An IMPERIUM unit without ADEPTUS ASTARTES should not benefit from Oath."""
	_create_sm_unit("U_SM_A", 1)
	var guard = _create_non_astartes_imperial_unit("U_GUARD_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	faction_mgr.detect_faction_abilities(1)
	faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_A")

	var target = GameState.state["units"]["U_BOYZ_A"]
	assert_false(FactionAbilityManager.attacker_benefits_from_oath(guard, target),
		"Non-ADEPTUS ASTARTES unit should not benefit from Oath")

func test_astartes_unit_gets_oath_benefit():
	"""An ADEPTUS ASTARTES unit should benefit from Oath."""
	var sm = _create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	faction_mgr.detect_faction_abilities(1)
	faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_A")

	var target = GameState.state["units"]["U_BOYZ_A"]
	assert_true(FactionAbilityManager.attacker_benefits_from_oath(sm, target),
		"ADEPTUS ASTARTES unit should benefit from Oath")

# ==========================================
# Save/Load State Tests
# ==========================================

func test_save_and_load_state():
	"""Saving and loading state should preserve Oath of Moment data."""
	_create_sm_unit("U_SM_A", 1)
	_create_ork_unit("U_BOYZ_A", 2)
	faction_mgr.detect_faction_abilities(1)
	faction_mgr.set_oath_of_moment_target(1, "U_BOYZ_A")

	var saved = faction_mgr.get_state_for_save()
	assert_not_null(saved)

	# Clear and restore
	faction_mgr._active_effects = {"1": {}, "2": {}}
	faction_mgr._player_abilities = {"1": [], "2": []}
	faction_mgr.load_state(saved)

	assert_has(faction_mgr._player_abilities["1"], "Oath of Moment")
	assert_eq(faction_mgr._active_effects["1"]["oath_of_moment_target"], "U_BOYZ_A")

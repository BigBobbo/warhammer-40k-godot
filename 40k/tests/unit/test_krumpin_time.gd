extends "res://addons/gut/test.gd"

# Tests for the KRUMPIN' TIME ability implementation (OA-17)
#
# Per Warhammer 40k 10th Edition rules (Meganobz datasheet):
# While Waaagh! is active, models in this unit have Feel No Pain 5+.
#
# This means:
# - FNP 5+ granted when Waaagh! is activated
# - FNP 5+ removed when Waaagh! deactivates
# - Does not stack with other FNP sources (use better value)
#
# These tests verify:
# 1. Ability is registered in UnitAbilityManager.ABILITY_EFFECTS with correct properties
# 2. FNP 5+ flag is set when Waaagh! activates for units with Krumpin' Time
# 3. FNP 5+ flag is cleared when Waaagh! deactivates
# 4. Non-stacking: better (lower) FNP from another source is preserved
# 5. RulesEngine.get_unit_fnp() returns correct value when FNP is active

const GameStateData = preload("res://autoloads/GameState.gd")

var faction_mgr: Node
var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	faction_mgr = AutoloadHelper.get_autoload("FactionAbilityManager")
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(faction_mgr, "FactionAbilityManager autoload must be available")
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

	# Reset Waaagh! state
	faction_mgr._waaagh_used = {"1": false, "2": false}
	faction_mgr._waaagh_active = {"1": false, "2": false}

	# Set up minimal game state with Meganobz unit
	GameState.state["units"] = {}
	if not GameState.state.has("factions"):
		GameState.state["factions"] = {}
	GameState.state["factions"]["2"] = "Orks"
	faction_mgr._player_abilities["2"] = ["Waaagh!"]

func _create_meganobz_unit(unit_id: String = "U_MEGANOBZ_A", owner: int = 2) -> Dictionary:
	"""Create a Meganobz unit with Waaagh! and Krumpin' Time abilities."""
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Meganobz",
			"keywords": ["INFANTRY", "MEGA ARMOUR", "ORKS", "MEGANOBZ"],
			"stats": {"move": 5, "toughness": 6, "save": 2, "wounds": 3, "leadership": 7, "objective_control": 1},
			"abilities": [
				{"name": "Waaagh!", "type": "Faction"},
				{"name": "Krumpin' Time", "type": "Datasheet", "description": "FNP 5+ while Waaagh! is active"}
			]
		},
		"flags": {},
		"models": [
			{"id": "m1", "wounds": 3, "current_wounds": 3, "base_mm": 40, "position": {"x": 100, "y": 100}, "alive": true, "status_effects": []},
			{"id": "m2", "wounds": 3, "current_wounds": 3, "base_mm": 40, "position": {"x": 140, "y": 100}, "alive": true, "status_effects": []},
			{"id": "m3", "wounds": 3, "current_wounds": 3, "base_mm": 40, "position": {"x": 180, "y": 100}, "alive": true, "status_effects": []}
		]
	}
	GameState.state["units"][unit_id] = unit
	return unit

func _create_ork_unit_without_krumpin(unit_id: String = "U_BOYZ_A", owner: int = 2) -> Dictionary:
	"""Create a regular Ork unit with Waaagh! but WITHOUT Krumpin' Time."""
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Boyz",
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1, "leadership": 7, "objective_control": 2},
			"abilities": [
				{"name": "Waaagh!", "type": "Faction"}
			]
		},
		"flags": {},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": {"x": 200, "y": 200}, "alive": true, "status_effects": []}
		]
	}
	GameState.state["units"][unit_id] = unit
	return unit

# ==========================================
# UnitAbilityManager Registration Tests
# ==========================================

func test_krumpin_time_in_ability_effects():
	"""Krumpin' Time should be registered in UnitAbilityManager.ABILITY_EFFECTS."""
	var ability_def = UnitAbilityManager.ABILITY_EFFECTS.get("Krumpin' Time", {})
	assert_false(ability_def.is_empty(), "Krumpin' Time must exist in ABILITY_EFFECTS")
	assert_true(ability_def.get("implemented", false), "Krumpin' Time must be marked as implemented")
	assert_eq(ability_def.get("condition", ""), "waaagh_active", "Krumpin' Time condition should be waaagh_active")
	assert_eq(ability_def.get("target", ""), "unit", "Krumpin' Time target should be unit")
	assert_eq(ability_def.get("attack_type", ""), "all", "Krumpin' Time attack_type should be all")

func test_krumpin_time_effects_definition():
	"""Krumpin' Time effect should be grant_fnp with value 5."""
	var ability_def = UnitAbilityManager.ABILITY_EFFECTS.get("Krumpin' Time", {})
	var effects = ability_def.get("effects", [])
	assert_eq(effects.size(), 1, "Should have exactly one effect")
	assert_eq(effects[0].get("type", ""), "grant_fnp", "Effect type should be grant_fnp")
	assert_eq(effects[0].get("value", 0), 5, "FNP value should be 5")

# ==========================================
# Waaagh! Activation — FNP Applied
# ==========================================

func test_waaagh_applies_fnp_to_meganobz():
	"""Activating Waaagh! should grant FNP 5+ to Meganobz with Krumpin' Time."""
	var unit = _create_meganobz_unit()
	faction_mgr.activate_waaagh(2)

	var fnp = unit.get("flags", {}).get("effect_fnp", 0)
	assert_eq(fnp, 5, "Meganobz should have FNP 5+ after Waaagh! activation")
	assert_eq(unit["flags"].get("effect_fnp_source", ""), "Krumpin' Time",
		"FNP source should be Krumpin' Time")

func test_waaagh_does_not_apply_fnp_to_non_krumpin_units():
	"""Activating Waaagh! should NOT grant FNP to units without Krumpin' Time."""
	var boyz = _create_ork_unit_without_krumpin()
	faction_mgr.activate_waaagh(2)

	var fnp = boyz.get("flags", {}).get("effect_fnp", 0)
	assert_eq(fnp, 0, "Boyz (without Krumpin' Time) should NOT have FNP after Waaagh!")

func test_rules_engine_fnp_after_waaagh():
	"""RulesEngine.get_unit_fnp should return 5 for Meganobz with active Waaagh!."""
	var unit = _create_meganobz_unit()
	faction_mgr.activate_waaagh(2)

	var fnp = RulesEngine.get_unit_fnp(unit)
	assert_eq(fnp, 5, "get_unit_fnp should return 5 for Meganobz with Krumpin' Time and active Waaagh!")

# ==========================================
# Waaagh! Deactivation — FNP Removed
# ==========================================

func test_waaagh_deactivation_clears_fnp():
	"""Deactivating Waaagh! should remove FNP 5+ from Meganobz."""
	var unit = _create_meganobz_unit()
	faction_mgr.activate_waaagh(2)

	# Verify FNP is set
	assert_eq(unit["flags"].get("effect_fnp", 0), 5, "FNP should be 5 while Waaagh! active")

	# Deactivate
	faction_mgr.deactivate_waaagh(2)

	var fnp = unit.get("flags", {}).get("effect_fnp", 0)
	assert_eq(fnp, 0, "FNP should be cleared after Waaagh! deactivation")

func test_rules_engine_fnp_after_waaagh_deactivation():
	"""RulesEngine.get_unit_fnp should return 0 after Waaagh! deactivates."""
	var unit = _create_meganobz_unit()
	faction_mgr.activate_waaagh(2)
	faction_mgr.deactivate_waaagh(2)

	var fnp = RulesEngine.get_unit_fnp(unit)
	assert_eq(fnp, 0, "get_unit_fnp should return 0 after Waaagh! deactivation for Meganobz")

# ==========================================
# Non-Stacking Tests
# ==========================================

func test_fnp_does_not_overwrite_better_value():
	"""If a unit already has FNP 4+ from another source, Krumpin' Time (5+) should not overwrite it."""
	var unit = _create_meganobz_unit()
	# Pre-set a better FNP from another source (e.g. Painboy)
	unit["flags"]["effect_fnp"] = 4
	unit["flags"]["effect_fnp_source"] = "Dok's Toolz"

	faction_mgr.activate_waaagh(2)

	# The better (lower) value from Dok's Toolz should be preserved
	assert_eq(unit["flags"].get("effect_fnp", 0), 4,
		"Better FNP 4+ from Dok's Toolz should not be overwritten by Krumpin' Time 5+")
	assert_eq(unit["flags"].get("effect_fnp_source", ""), "Dok's Toolz",
		"Source should remain Dok's Toolz when it provides better FNP")

func test_fnp_deactivation_does_not_clear_other_source():
	"""Deactivating Waaagh! should NOT clear FNP from another source (e.g. Dok's Toolz)."""
	var unit = _create_meganobz_unit()
	# Pre-set FNP from another source
	unit["flags"]["effect_fnp"] = 4
	unit["flags"]["effect_fnp_source"] = "Dok's Toolz"

	faction_mgr.activate_waaagh(2)
	faction_mgr.deactivate_waaagh(2)

	# Dok's Toolz FNP should survive Waaagh! deactivation
	assert_eq(unit["flags"].get("effect_fnp", 0), 4,
		"FNP from Dok's Toolz should survive Waaagh! deactivation")
	assert_eq(unit["flags"].get("effect_fnp_source", ""), "Dok's Toolz",
		"FNP source Dok's Toolz should survive Waaagh! deactivation")

func test_get_unit_fnp_uses_better_value_base_stats():
	"""When unit has base FNP in stats AND effect FNP, get_unit_fnp returns the better (lower) one."""
	var unit = _create_meganobz_unit()
	# Give base stats FNP 6+
	unit["meta"]["stats"]["fnp"] = 6
	# Activate Waaagh! to get effect_fnp 5+
	faction_mgr.activate_waaagh(2)

	var fnp = RulesEngine.get_unit_fnp(unit)
	assert_eq(fnp, 5, "get_unit_fnp should return 5 (better of base 6+ and effect 5+)")

func test_waaagh_applies_fnp_when_same_value_present():
	"""If unit has FNP 5+ from another source, Waaagh! applies its own 5+ (same value is ok)."""
	var unit = _create_meganobz_unit()
	unit["flags"]["effect_fnp"] = 5
	unit["flags"]["effect_fnp_source"] = "Dok's Toolz"

	faction_mgr.activate_waaagh(2)

	# Both are 5+, Krumpin' Time should overwrite since 5 <= 5
	assert_eq(unit["flags"].get("effect_fnp", 0), 5, "FNP should remain 5")

# ==========================================
# No FNP Without Waaagh! Tests
# ==========================================

func test_no_fnp_without_waaagh():
	"""Meganobz should NOT have FNP when Waaagh! is not active."""
	var unit = _create_meganobz_unit()

	var fnp = RulesEngine.get_unit_fnp(unit)
	assert_eq(fnp, 0, "Meganobz should have no FNP without Waaagh! active")

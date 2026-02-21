extends SceneTree

# Test AI Ability Awareness (AI-GAP-4)
# Verifies that AIAbilityAnalyzer correctly reads abilities, detects leader bonuses,
# identifies "Fall Back and X" abilities, and computes offensive/defensive multipliers.
# Also verifies that AIDecisionMaker integrates ability awareness into scoring.
# Run with: godot --headless --script tests/unit/test_ai_ability_awareness.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")
const AIAbilityAnalyzer = preload("res://scripts/AIAbilityAnalyzer.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Ability Awareness Tests (AI-GAP-4) ===\n")
	_run_tests()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _assert_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	var diff = abs(actual - expected)
	if diff <= tolerance:
		_pass_count += 1
		print("PASS: %s (got %.4f, expected %.4f)" % [message, actual, expected])
	else:
		_fail_count += 1
		print("FAIL: %s (got %.4f, expected %.4f, diff %.4f > tolerance %.4f)" % [message, actual, expected, diff, tolerance])

func _run_tests():
	# Ability parsing tests
	test_get_ability_names_string_format()
	test_get_ability_names_dict_format()
	test_get_ability_names_mixed_format()
	test_get_ability_names_skips_core()
	test_unit_has_ability()
	test_unit_has_ability_containing()

	# Leader bonus detection tests
	test_leader_bonuses_no_leader()
	test_leader_bonuses_plus_one_hit_melee()
	test_leader_bonuses_reroll_hits_ranged()
	test_leader_bonuses_fnp_from_leader()
	test_leader_bonuses_cover_from_leader()
	test_leader_bonuses_multiple_effects()

	# Fall Back and X detection tests
	test_fall_back_and_charge_from_leader()
	test_fall_back_and_charge_from_flags()
	test_fall_back_and_shoot_none()
	test_fall_back_and_charge_from_description()

	# Advance and X detection tests
	test_advance_and_charge_from_leader()
	test_advance_and_shoot_from_flags()

	# Defensive ability detection tests
	test_fnp_from_stats()
	test_fnp_from_flags()
	test_fnp_best_of_both()
	test_fnp_damage_multiplier()
	test_stealth_from_abilities()
	test_stealth_from_flags()
	test_lone_operative_detection()
	test_lone_operative_protection()

	# Offensive/defensive multiplier tests
	test_offensive_multiplier_ranged_no_bonuses()
	test_offensive_multiplier_ranged_with_hit_bonus()
	test_offensive_multiplier_ranged_with_reroll()
	test_offensive_multiplier_melee_with_hit_and_wound()
	test_defensive_multiplier_no_abilities()
	test_defensive_multiplier_with_fnp()
	test_defensive_multiplier_with_stealth()

	# Comprehensive profile test
	test_unit_ability_profile()

	# Integration tests: AIDecisionMaker scoring with abilities
	test_shooting_score_reduced_by_target_fnp()
	test_shooting_score_reduced_by_target_stealth()
	test_shooting_score_penalized_by_defensive_buff_cover()
	test_shooting_score_penalized_by_defensive_buff_stealth()
	test_shooting_score_penalized_by_defensive_buff_invuln()
	test_melee_damage_reduced_by_target_fnp()
	test_charge_score_boosted_by_melee_leader()

	# T7-11: Deadly Demise detection tests
	test_deadly_demise_detection()
	test_deadly_demise_value_d3()
	test_deadly_demise_value_d6()
	test_deadly_demise_not_present()
	test_is_unit_doomed()
	test_is_unit_not_doomed()

	# T7-11: Lone Operative protection helpers
	test_lone_operative_movement_helper()

	# T7-11: Enhanced profile includes new fields
	test_profile_includes_deadly_demise()

	# T7-11: Oath of Moment prefers leader targets
	test_oath_prefers_leader_with_buffs()

	# T7-11: Charge score boosted for doomed Deadly Demise vehicles
	test_charge_score_boosted_by_deadly_demise()

# =========================================================================
# Helpers
# =========================================================================

func _create_test_snapshot() -> Dictionary:
	return {
		"battle_round": 2,
		"board": {
			"objectives": [],
			"terrain_features": [],
			"deployment_zones": []
		},
		"units": {}
	}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2,
		name: String = "Test Unit", num_models: int = 1, keywords: Array = ["INFANTRY"],
		weapons: Array = [], toughness: int = 4, save_val: int = 3,
		wounds: int = 2, invuln: int = 0, flags: Dictionary = {},
		abilities: Array = [], attachment_data: Dictionary = {}) -> void:
	var models = []
	for i in range(num_models):
		var model = {
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": 32,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + i * 40, pos.y),
			"wounds": wounds,
			"current_wounds": wounds
		}
		if invuln > 0:
			model["invuln"] = invuln
		models.append(model)
	var stats = {
		"move": 6,
		"toughness": toughness,
		"save": save_val,
		"wounds": wounds,
		"leadership": 6,
		"objective_control": 2
	}
	var unit_dict = {
		"id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": name,
			"stats": stats,
			"keywords": keywords,
			"weapons": weapons,
			"abilities": abilities
		},
		"models": models,
		"flags": flags
	}
	if not attachment_data.is_empty():
		unit_dict["attachment_data"] = attachment_data
	snapshot.units[unit_id] = unit_dict

func _make_ranged_weapon(wname: String = "Bolt rifle", bs: int = 3,
		strength: int = 4, ap: int = 1, damage: int = 1, attacks: int = 2,
		weapon_range: int = 24) -> Dictionary:
	return {
		"name": wname,
		"type": "Ranged",
		"ballistic_skill": str(bs),
		"strength": str(strength),
		"ap": "-%d" % ap if ap > 0 else "0",
		"damage": str(damage),
		"attacks": str(attacks),
		"range": str(weapon_range),
		"special_rules": ""
	}

func _make_melee_weapon(wname: String = "Power sword", ws: int = 3,
		strength: int = 5, ap: int = 2, damage: int = 1, attacks: int = 3) -> Dictionary:
	return {
		"name": wname,
		"type": "Melee",
		"weapon_skill": str(ws),
		"strength": str(strength),
		"ap": "-%d" % ap if ap > 0 else "0",
		"damage": str(damage),
		"attacks": str(attacks),
		"range": "Melee",
		"special_rules": ""
	}

# =========================================================================
# Tests: Ability parsing
# =========================================================================

func test_get_ability_names_string_format():
	var unit = {"meta": {"abilities": ["Stealth", "Lone Operative"]}}
	var names = AIAbilityAnalyzer.get_ability_names(unit)
	_assert(names.size() == 2, "get_ability_names with strings returns 2 abilities (got %d)" % names.size())
	_assert("Stealth" in names, "get_ability_names includes 'Stealth'")
	_assert("Lone Operative" in names, "get_ability_names includes 'Lone Operative'")

func test_get_ability_names_dict_format():
	var unit = {"meta": {"abilities": [
		{"name": "Might is Right", "type": "Datasheet", "description": "+1 to melee hit rolls"},
		{"name": "Da Biggest and da Best", "type": "Datasheet", "description": "+4 attacks"}
	]}}
	var names = AIAbilityAnalyzer.get_ability_names(unit)
	_assert(names.size() == 2, "get_ability_names with dicts returns 2 abilities (got %d)" % names.size())
	_assert("Might is Right" in names, "get_ability_names includes 'Might is Right'")

func test_get_ability_names_mixed_format():
	var unit = {"meta": {"abilities": [
		"Stealth",
		{"name": "Might is Right", "type": "Datasheet", "description": "..."}
	]}}
	var names = AIAbilityAnalyzer.get_ability_names(unit)
	_assert(names.size() == 2, "get_ability_names with mixed format returns 2 (got %d)" % names.size())

func test_get_ability_names_skips_core():
	var unit = {"meta": {"abilities": [
		{"name": "Core", "type": "Core"},
		{"name": "Core", "type": "Faction"},
		{"name": "Might is Right", "type": "Datasheet", "description": "..."}
	]}}
	var names = AIAbilityAnalyzer.get_ability_names(unit)
	_assert(names.size() == 1, "get_ability_names skips Core entries (got %d)" % names.size())
	_assert("Might is Right" in names, "get_ability_names includes non-Core ability")

func test_unit_has_ability():
	var unit = {"meta": {"abilities": [
		{"name": "Stealth", "type": "Datasheet"},
		{"name": "Might is Right", "type": "Datasheet"}
	]}}
	_assert(AIAbilityAnalyzer.unit_has_ability(unit, "Stealth"), "unit_has_ability detects Stealth")
	_assert(not AIAbilityAnalyzer.unit_has_ability(unit, "Lone Operative"), "unit_has_ability returns false for missing ability")

func test_unit_has_ability_containing():
	var unit = {"meta": {"abilities": [
		{"name": "One Scalpel Short", "type": "Datasheet", "description": "eligible to charge after falling back"}
	]}}
	_assert(AIAbilityAnalyzer.unit_has_ability_containing(unit, "fall back"), "unit_has_ability_containing detects 'fall back' in description")
	_assert(AIAbilityAnalyzer.unit_has_ability_containing(unit, "charge"), "unit_has_ability_containing detects 'charge' in description")
	_assert(not AIAbilityAnalyzer.unit_has_ability_containing(unit, "shoot"), "unit_has_ability_containing returns false for 'shoot'")

# =========================================================================
# Tests: Leader bonus detection
# =========================================================================

func test_leader_bonuses_no_leader():
	var unit = {"meta": {"abilities": []}, "attachment_data": {}}
	var all_units = {}
	var bonuses = AIAbilityAnalyzer.get_leader_bonuses("u1", unit, all_units)
	_assert(not bonuses["has_leader"], "No leader bonuses when no characters attached")
	_assert(bonuses["hit_bonus_melee"] == 0, "No melee hit bonus without leader")

func test_leader_bonuses_plus_one_hit_melee():
	# Warboss has "Might is Right" — +1 to melee hit rolls for led unit
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "warboss", 2, Vector2(0, 0), "Warboss", 1,
		["CHARACTER", "INFANTRY"], [], 5, 4, 6, 0, {},
		[{"name": "Might is Right", "type": "Datasheet", "description": "+1 to melee Hit rolls"}])
	_add_unit(snapshot, "boyz", 2, Vector2(100, 0), "Boyz", 5,
		["INFANTRY"], [], 4, 5, 1, 0, {},
		[], {"attached_characters": ["warboss"]})

	var bonuses = AIAbilityAnalyzer.get_leader_bonuses("boyz", snapshot.units["boyz"], snapshot.units)
	_assert(bonuses["has_leader"], "Leader detected")
	_assert(bonuses["hit_bonus_melee"] == 1, "Might is Right gives +1 melee hit (got %d)" % bonuses["hit_bonus_melee"])
	_assert(bonuses["hit_bonus_ranged"] == 0, "Might is Right does not affect ranged (got %d)" % bonuses["hit_bonus_ranged"])

func test_leader_bonuses_reroll_hits_ranged():
	# Big Mek has "More Dakka" — reroll hit rolls of 1 (ranged)
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "bigmek", 2, Vector2(0, 0), "Big Mek", 1,
		["CHARACTER", "INFANTRY"], [], 5, 3, 5, 0, {},
		[{"name": "More Dakka", "type": "Datasheet", "description": "Re-roll ranged Hit rolls of 1"}])
	_add_unit(snapshot, "meganobz", 2, Vector2(100, 0), "Meganobz", 3,
		["INFANTRY"], [], 5, 3, 3, 0, {},
		[], {"attached_characters": ["bigmek"]})

	var bonuses = AIAbilityAnalyzer.get_leader_bonuses("meganobz", snapshot.units["meganobz"], snapshot.units)
	_assert(bonuses["has_leader"], "Leader detected")
	_assert(bonuses["reroll_hits_ranged"] == "ones", "More Dakka gives reroll hits ones ranged (got '%s')" % bonuses["reroll_hits_ranged"])
	_assert(bonuses["reroll_hits_melee"] == "none", "More Dakka does not affect melee rerolls (got '%s')" % bonuses["reroll_hits_melee"])

func test_leader_bonuses_fnp_from_leader():
	# Painboy has "Dok's Toolz" — FNP 5+ for led unit
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "painboy", 2, Vector2(0, 0), "Painboy", 1,
		["CHARACTER", "INFANTRY"], [], 4, 5, 4, 0, {},
		[{"name": "Dok's Toolz", "type": "Datasheet", "description": "FNP 5+"}])
	_add_unit(snapshot, "boyz", 2, Vector2(100, 0), "Boyz", 10,
		["INFANTRY"], [], 4, 5, 1, 0, {},
		[], {"attached_characters": ["painboy"]})

	var bonuses = AIAbilityAnalyzer.get_leader_bonuses("boyz", snapshot.units["boyz"], snapshot.units)
	_assert(bonuses["has_fnp"] == 5, "Dok's Toolz gives FNP 5+ to led unit (got %d)" % bonuses["has_fnp"])

func test_leader_bonuses_cover_from_leader():
	# Boss Snikrot has "Red Skull Kommandos" — cover for led unit
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "snikrot", 2, Vector2(0, 0), "Boss Snikrot", 1,
		["CHARACTER", "INFANTRY"], [], 5, 4, 5, 0, {},
		[{"name": "Red Skull Kommandos", "type": "Datasheet", "description": "Benefit of Cover"}])
	_add_unit(snapshot, "kommandos", 2, Vector2(100, 0), "Kommandos", 5,
		["INFANTRY"], [], 4, 5, 1, 0, {},
		[], {"attached_characters": ["snikrot"]})

	var bonuses = AIAbilityAnalyzer.get_leader_bonuses("kommandos", snapshot.units["kommandos"], snapshot.units)
	_assert(bonuses["has_cover"], "Red Skull Kommandos grants cover to led unit")

func test_leader_bonuses_multiple_effects():
	# Ghazghkull has "Prophet of Da Great Waaagh!" — +1 hit AND +1 wound (melee)
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "ghaz", 2, Vector2(0, 0), "Ghazghkull", 1,
		["CHARACTER", "INFANTRY"], [], 6, 2, 12, 4, {},
		[{"name": "Prophet of Da Great Waaagh!", "type": "Datasheet", "description": "+1 Hit and Wound melee"}])
	_add_unit(snapshot, "meganobz", 2, Vector2(100, 0), "Meganobz", 3,
		["INFANTRY"], [], 5, 3, 3, 0, {},
		[], {"attached_characters": ["ghaz"]})

	var bonuses = AIAbilityAnalyzer.get_leader_bonuses("meganobz", snapshot.units["meganobz"], snapshot.units)
	_assert(bonuses["hit_bonus_melee"] == 1, "Prophet gives +1 melee hit (got %d)" % bonuses["hit_bonus_melee"])
	_assert(bonuses["wound_bonus_melee"] == 1, "Prophet gives +1 melee wound (got %d)" % bonuses["wound_bonus_melee"])
	_assert(bonuses["hit_bonus_ranged"] == 0, "Prophet does not affect ranged hit (got %d)" % bonuses["hit_bonus_ranged"])

# =========================================================================
# Tests: Fall Back and X detection
# =========================================================================

func test_fall_back_and_charge_from_leader():
	# Mad Dok Grotsnik has "One Scalpel Short of a Medpack" — fall back and charge
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "grotsnik", 2, Vector2(0, 0), "Mad Dok Grotsnik", 1,
		["CHARACTER", "INFANTRY"], [], 5, 5, 5, 0, {},
		[{"name": "One Scalpel Short of a Medpack", "type": "Datasheet",
		  "description": "Eligible to charge after falling back"}])
	_add_unit(snapshot, "boyz", 2, Vector2(100, 0), "Boyz", 10,
		["INFANTRY"], [], 4, 5, 1, 0, {},
		[], {"attached_characters": ["grotsnik"]})

	var result = AIAbilityAnalyzer.can_fall_back_and_charge("boyz", snapshot.units["boyz"], snapshot.units)
	_assert(result, "Unit with Grotsnik can Fall Back and Charge")

func test_fall_back_and_charge_from_flags():
	# Unit has the effect flag set (by UnitAbilityManager during movement phase)
	var unit = {
		"id": "u1",
		"meta": {"abilities": []},
		"flags": {"effect_fall_back_and_charge": true},
		"attachment_data": {}
	}
	var result = AIAbilityAnalyzer.can_fall_back_and_charge("u1", unit, {})
	_assert(result, "Unit with effect_fall_back_and_charge flag can Fall Back and Charge")

func test_fall_back_and_shoot_none():
	# Unit without any fall back abilities
	var unit = {
		"id": "u1",
		"meta": {"abilities": [{"name": "Stealth", "type": "Datasheet"}]},
		"flags": {},
		"attachment_data": {}
	}
	var result = AIAbilityAnalyzer.can_fall_back_and_shoot("u1", unit, {})
	_assert(not result, "Unit without FB+Shoot ability cannot Fall Back and Shoot")

func test_fall_back_and_charge_from_description():
	# Unit with a description-based fall back and charge (not in lookup table)
	var unit = {
		"id": "u1",
		"meta": {"abilities": [
			{"name": "Unknown Ability", "type": "Datasheet",
			 "description": "This unit can fall back and still charge in the same turn"}
		]},
		"flags": {},
		"attachment_data": {}
	}
	var result = AIAbilityAnalyzer.can_fall_back_and_charge("u1", unit, {})
	_assert(result, "Unit with description-based Fall Back and Charge is detected")

# =========================================================================
# Tests: Advance and X detection
# =========================================================================

func test_advance_and_charge_from_leader():
	# Blade Champion has "Martial Inspiration" — advance and charge
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "champion", 2, Vector2(0, 0), "Blade Champion", 1,
		["CHARACTER", "INFANTRY"], [], 5, 2, 6, 4, {},
		[{"name": "Martial Inspiration", "type": "Datasheet",
		  "description": "Once per battle advance and charge"}])
	_add_unit(snapshot, "custodians", 2, Vector2(100, 0), "Custodian Guard", 3,
		["INFANTRY"], [], 6, 2, 3, 4, {},
		[], {"attached_characters": ["champion"]})

	var result = AIAbilityAnalyzer.can_advance_and_charge("custodians", snapshot.units["custodians"], snapshot.units)
	_assert(result, "Unit with Blade Champion can Advance and Charge")

func test_advance_and_shoot_from_flags():
	var unit = {
		"id": "u1",
		"meta": {"abilities": []},
		"flags": {"effect_advance_and_shoot": true},
		"attachment_data": {}
	}
	var result = AIAbilityAnalyzer.can_advance_and_shoot("u1", unit, {})
	_assert(result, "Unit with effect_advance_and_shoot flag can Advance and Shoot")

# =========================================================================
# Tests: Defensive ability detection
# =========================================================================

func test_fnp_from_stats():
	var unit = {"meta": {"stats": {"fnp": 5}}, "flags": {}}
	var fnp = AIAbilityAnalyzer.get_unit_fnp(unit)
	_assert(fnp == 5, "FNP from stats = 5 (got %d)" % fnp)

func test_fnp_from_flags():
	var unit = {"meta": {"stats": {}}, "flags": {"effect_fnp": 6}}
	var fnp = AIAbilityAnalyzer.get_unit_fnp(unit)
	_assert(fnp == 6, "FNP from flags = 6 (got %d)" % fnp)

func test_fnp_best_of_both():
	# Stats say FNP 6+, flags say FNP 5+ — should use 5+
	var unit = {"meta": {"stats": {"fnp": 6}}, "flags": {"effect_fnp": 5}}
	var fnp = AIAbilityAnalyzer.get_unit_fnp(unit)
	_assert(fnp == 5, "FNP best of stats(6) and flags(5) = 5 (got %d)" % fnp)

func test_fnp_damage_multiplier():
	# FNP 5+ means 2/6 chance to ignore each wound -> 4/6 = 0.667 damage gets through
	var mult = AIAbilityAnalyzer.get_fnp_damage_multiplier(5)
	_assert_approx(mult, 4.0 / 6.0, 0.01, "FNP 5+ damage multiplier = 4/6")

	# FNP 6+ means 1/6 chance to ignore -> 5/6 = 0.833
	mult = AIAbilityAnalyzer.get_fnp_damage_multiplier(6)
	_assert_approx(mult, 5.0 / 6.0, 0.01, "FNP 6+ damage multiplier = 5/6")

	# No FNP = 1.0
	mult = AIAbilityAnalyzer.get_fnp_damage_multiplier(0)
	_assert_approx(mult, 1.0, 0.001, "No FNP damage multiplier = 1.0")

func test_stealth_from_abilities():
	var unit = {"meta": {"abilities": [{"name": "Stealth", "type": "Datasheet"}]}, "flags": {}}
	_assert(AIAbilityAnalyzer.has_stealth(unit), "Stealth detected from abilities")

func test_stealth_from_flags():
	var unit = {"meta": {"abilities": []}, "flags": {"effect_stealth": true}}
	_assert(AIAbilityAnalyzer.has_stealth(unit), "Stealth detected from effect flags")

func test_lone_operative_detection():
	var unit = {"meta": {"abilities": [{"name": "Lone Operative", "type": "Datasheet"}]}}
	_assert(AIAbilityAnalyzer.has_lone_operative(unit), "Lone Operative detected")

	var no_lo = {"meta": {"abilities": [{"name": "Stealth", "type": "Datasheet"}]}}
	_assert(not AIAbilityAnalyzer.has_lone_operative(no_lo), "Lone Operative not detected without it")

func test_lone_operative_protection():
	# Standalone unit with Lone Operative — protected
	var unit_protected = {
		"meta": {"abilities": [{"name": "Lone Operative", "type": "Datasheet"}]},
		"attachment_data": {},
		"attached_to": null
	}
	_assert(AIAbilityAnalyzer.is_lone_operative_protected(unit_protected), "Standalone Lone Operative is protected")

	# Lone Operative attached to another unit — NOT protected
	var unit_attached = {
		"meta": {"abilities": [{"name": "Lone Operative", "type": "Datasheet"}]},
		"attachment_data": {"attached_characters": ["char_1"]},
		"attached_to": null
	}
	_assert(not AIAbilityAnalyzer.is_lone_operative_protected(unit_attached), "Attached Lone Operative is not protected")

# =========================================================================
# Tests: Offensive/defensive multipliers
# =========================================================================

func test_offensive_multiplier_ranged_no_bonuses():
	var unit = {"id": "u1", "meta": {"abilities": []}, "attachment_data": {}}
	var mult = AIAbilityAnalyzer.get_offensive_multiplier_ranged("u1", unit, {})
	_assert_approx(mult, 1.0, 0.001, "Offensive multiplier ranged = 1.0 with no bonuses")

func test_offensive_multiplier_ranged_with_hit_bonus():
	var snapshot = _create_test_snapshot()
	# Kaptin Badrukk: reroll all ranged hits
	_add_unit(snapshot, "badrukk", 2, Vector2(0, 0), "Badrukk", 1,
		["CHARACTER"], [], 5, 4, 5, 0, {},
		[{"name": "Flashiest Gitz", "type": "Datasheet", "description": "Reroll ranged hits"}])
	_add_unit(snapshot, "flashgitz", 2, Vector2(100, 0), "Flash Gitz", 5,
		["INFANTRY"], [], 4, 4, 2, 0, {},
		[], {"attached_characters": ["badrukk"]})

	var mult = AIAbilityAnalyzer.get_offensive_multiplier_ranged("flashgitz", snapshot.units["flashgitz"], snapshot.units)
	_assert(mult > 1.0, "Offensive multiplier ranged > 1.0 with Flashiest Gitz (got %.2f)" % mult)
	_assert(mult >= 1.30, "Flashiest Gitz (reroll all hits) gives >= 1.30 multiplier (got %.2f)" % mult)

func test_offensive_multiplier_ranged_with_reroll():
	var snapshot = _create_test_snapshot()
	# Big Mek: reroll hit rolls of 1 (ranged)
	_add_unit(snapshot, "bigmek", 2, Vector2(0, 0), "Big Mek", 1,
		["CHARACTER"], [], 5, 3, 5, 0, {},
		[{"name": "More Dakka", "type": "Datasheet", "description": "Reroll ranged Hit 1s"}])
	_add_unit(snapshot, "meganobz", 2, Vector2(100, 0), "Meganobz", 3,
		["INFANTRY"], [], 5, 3, 3, 0, {},
		[], {"attached_characters": ["bigmek"]})

	var mult = AIAbilityAnalyzer.get_offensive_multiplier_ranged("meganobz", snapshot.units["meganobz"], snapshot.units)
	_assert(mult > 1.0, "Offensive multiplier ranged > 1.0 with More Dakka (got %.2f)" % mult)
	_assert_approx(mult, 1.10, 0.02, "More Dakka (reroll ones) gives ~1.10 multiplier")

func test_offensive_multiplier_melee_with_hit_and_wound():
	var snapshot = _create_test_snapshot()
	# Ghazghkull: +1 hit + +1 wound (melee)
	_add_unit(snapshot, "ghaz", 2, Vector2(0, 0), "Ghazghkull", 1,
		["CHARACTER"], [], 6, 2, 12, 4, {},
		[{"name": "Prophet of Da Great Waaagh!", "type": "Datasheet", "description": "+1 hit and wound melee"}])
	_add_unit(snapshot, "meganobz", 2, Vector2(100, 0), "Meganobz", 3,
		["INFANTRY"], [], 5, 3, 3, 0, {},
		[], {"attached_characters": ["ghaz"]})

	var mult = AIAbilityAnalyzer.get_offensive_multiplier_melee("meganobz", snapshot.units["meganobz"], snapshot.units)
	# +1 hit = ~1.25, +1 wound = ~1.20, combined = ~1.50
	_assert(mult > 1.3, "Offensive multiplier melee > 1.3 with Ghazghkull bonuses (got %.2f)" % mult)
	_assert(mult < 2.0, "Offensive multiplier melee < 2.0 (reasonable range, got %.2f)" % mult)

func test_defensive_multiplier_no_abilities():
	var unit = {"id": "u1", "meta": {"abilities": [], "stats": {}}, "flags": {}, "attachment_data": {}}
	var mult = AIAbilityAnalyzer.get_defensive_multiplier("u1", unit, {})
	_assert_approx(mult, 1.0, 0.001, "Defensive multiplier = 1.0 with no abilities")

func test_defensive_multiplier_with_fnp():
	var unit = {"id": "u1", "meta": {"abilities": [], "stats": {"fnp": 5}}, "flags": {}, "attachment_data": {}}
	var mult = AIAbilityAnalyzer.get_defensive_multiplier("u1", unit, {})
	# FNP 5+ means 2/6 of wounds ignored -> effective HP multiplier = 1 / (4/6) = 1.5
	_assert(mult > 1.3, "Defensive multiplier > 1.3 with FNP 5+ (got %.2f)" % mult)
	_assert_approx(mult, 1.5, 0.1, "Defensive multiplier ~1.5 with FNP 5+")

func test_defensive_multiplier_with_stealth():
	var unit = {"id": "u1", "meta": {"abilities": [{"name": "Stealth", "type": "Datasheet"}], "stats": {}}, "flags": {}, "attachment_data": {}}
	var mult = AIAbilityAnalyzer.get_defensive_multiplier("u1", unit, {})
	_assert(mult > 1.0, "Defensive multiplier > 1.0 with Stealth (got %.2f)" % mult)
	_assert_approx(mult, 1.15, 0.05, "Defensive multiplier ~1.15 with Stealth")

# =========================================================================
# Tests: Comprehensive profile
# =========================================================================

func test_unit_ability_profile():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "painboy", 2, Vector2(0, 0), "Painboy", 1,
		["CHARACTER"], [], 4, 5, 4, 0, {},
		[{"name": "Dok's Toolz", "type": "Datasheet", "description": "FNP 5+"}])
	_add_unit(snapshot, "boyz", 2, Vector2(100, 0), "Boyz", 10,
		["INFANTRY"], [_make_melee_weapon("Choppa", 4, 4, 1, 1, 2)],
		4, 5, 1, 0, {},
		[{"name": "Get Da Good Bitz", "type": "Datasheet", "description": "Sticky objectives"}],
		{"attached_characters": ["painboy"]})

	var profile = AIAbilityAnalyzer.get_unit_ability_profile("boyz", snapshot.units["boyz"], snapshot.units)
	_assert(profile["leader_bonuses"]["has_leader"], "Profile shows leader present")
	_assert(profile["has_fnp"] == 5, "Profile shows FNP 5+ from leader (got %d)" % profile["has_fnp"])
	_assert("Get Da Good Bitz" in profile["abilities"], "Profile lists unit's own abilities")
	_assert(profile["defensive_mult"] > 1.0, "Profile defensive multiplier > 1.0 (got %.2f)" % profile["defensive_mult"])

# =========================================================================
# Tests: Integration with AIDecisionMaker scoring
# =========================================================================

func test_shooting_score_reduced_by_target_fnp():
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Lascannon", 3, 12, 3, 6, 1, 48)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	# Target without FNP
	_add_unit(snapshot, "target_no_fnp", 2, Vector2(400, 0), "Target", 1, ["INFANTRY"], [], 4, 3, 2, 0, {})
	# Target with FNP 5+
	_add_unit(snapshot, "target_fnp5", 2, Vector2(400, 100), "Target FNP", 1, ["INFANTRY"], [], 4, 3, 2, 0, {},
		[], {})
	snapshot.units["target_fnp5"]["meta"]["stats"]["fnp"] = 5

	var shooter = snapshot.units["shooter"]
	var score_no_fnp = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_no_fnp"], snapshot, shooter)
	var score_with_fnp = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_fnp5"], snapshot, shooter)

	_assert(score_with_fnp < score_no_fnp,
		"Shooting score lower with target FNP 5+ (no_fnp=%.2f, with_fnp=%.2f)" % [score_no_fnp, score_with_fnp])

func test_shooting_score_reduced_by_target_stealth():
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Heavy bolter", 4, 5, 1, 2, 3, 36)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	# Target without Stealth
	_add_unit(snapshot, "target_no_stealth", 2, Vector2(400, 0), "Target", 3, ["INFANTRY"], [], 4, 3, 1, 0, {})
	# Target with Stealth
	_add_unit(snapshot, "target_stealth", 2, Vector2(400, 100), "Target Stealth", 3, ["INFANTRY"], [], 4, 3, 1, 0, {},
		[{"name": "Stealth", "type": "Datasheet"}])

	var shooter = snapshot.units["shooter"]
	var score_no_stealth = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_no_stealth"], snapshot, shooter)
	var score_with_stealth = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_stealth"], snapshot, shooter)

	_assert(score_with_stealth < score_no_stealth,
		"Shooting score lower with target Stealth (no_stealth=%.2f, with_stealth=%.2f)" % [score_no_stealth, score_with_stealth])

func test_shooting_score_penalized_by_defensive_buff_cover():
	# T7-49: Targets with effect-granted cover (Go to Ground / Smokescreen) should score lower
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Heavy bolter", 4, 5, 1, 2, 3, 36)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	# Target without defensive buff
	_add_unit(snapshot, "target_no_buff", 2, Vector2(400, 0), "Target", 3, ["INFANTRY"], [], 4, 3, 1, 0, {})
	# Target with effect-granted cover (e.g. Go to Ground / Smokescreen)
	_add_unit(snapshot, "target_buff", 2, Vector2(400, 100), "Target Buffed", 3, ["INFANTRY"], [], 4, 3, 1, 0,
		{"effect_cover": true})

	var shooter = snapshot.units["shooter"]
	var score_no_buff = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_no_buff"], snapshot, shooter)
	var score_with_buff = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_buff"], snapshot, shooter)

	_assert(score_with_buff < score_no_buff,
		"T7-49: Shooting score lower with target effect_cover (no_buff=%.2f, with_buff=%.2f)" % [score_no_buff, score_with_buff])

func test_shooting_score_penalized_by_defensive_buff_stealth():
	# T7-49: Targets with effect-granted stealth (Smokescreen) should score lower
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Heavy bolter", 4, 5, 1, 2, 3, 36)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	# Target without defensive buff
	_add_unit(snapshot, "target_no_buff", 2, Vector2(400, 0), "Target", 3, ["INFANTRY"], [], 4, 3, 1, 0, {})
	# Target with effect-granted stealth (e.g. Smokescreen)
	_add_unit(snapshot, "target_buff", 2, Vector2(400, 100), "Target Buffed", 3, ["INFANTRY"], [], 4, 3, 1, 0,
		{"effect_stealth": true})

	var shooter = snapshot.units["shooter"]
	var score_no_buff = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_no_buff"], snapshot, shooter)
	var score_with_buff = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_buff"], snapshot, shooter)

	_assert(score_with_buff < score_no_buff,
		"T7-49: Shooting score lower with target effect_stealth (no_buff=%.2f, with_buff=%.2f)" % [score_no_buff, score_with_buff])

func test_shooting_score_penalized_by_defensive_buff_invuln():
	# T7-49: Targets with effect-granted invuln (Go to Ground 6++) should score lower
	var snapshot = _create_test_snapshot()
	var weapon = _make_ranged_weapon("Heavy bolter", 4, 5, 1, 2, 3, 36)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon])
	# Target without defensive buff
	_add_unit(snapshot, "target_no_buff", 2, Vector2(400, 0), "Target", 3, ["INFANTRY"], [], 4, 3, 1, 0, {})
	# Target with effect-granted invulnerable save (e.g. Go to Ground 6++)
	_add_unit(snapshot, "target_buff", 2, Vector2(400, 100), "Target Buffed", 3, ["INFANTRY"], [], 4, 3, 1, 0,
		{"effect_invuln": 6})

	var shooter = snapshot.units["shooter"]
	var score_no_buff = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_no_buff"], snapshot, shooter)
	var score_with_buff = AIDecisionMaker._score_shooting_target(weapon, snapshot.units["target_buff"], snapshot, shooter)

	_assert(score_with_buff < score_no_buff,
		"T7-49: Shooting score lower with target effect_invuln (no_buff=%.2f, with_buff=%.2f)" % [score_no_buff, score_with_buff])

func test_melee_damage_reduced_by_target_fnp():
	# Melee weapon against target with FNP should deal less expected damage
	var snapshot = _create_test_snapshot()
	var melee = _make_melee_weapon("Power fist", 3, 8, 3, 2, 3)

	_add_unit(snapshot, "attacker", 1, Vector2(0, 0), "Attacker", 1, ["INFANTRY"], [melee])
	_add_unit(snapshot, "defender_no_fnp", 2, Vector2(100, 0), "Defender", 1, ["INFANTRY"], [], 4, 3, 2, 0, {})
	_add_unit(snapshot, "defender_fnp", 2, Vector2(100, 100), "Defender FNP", 1, ["INFANTRY"], [], 4, 3, 2, 0, {})
	snapshot.units["defender_fnp"]["meta"]["stats"]["fnp"] = 5

	var dmg_no_fnp = AIDecisionMaker._estimate_melee_damage(
		snapshot.units["attacker"], snapshot.units["defender_no_fnp"])
	var dmg_with_fnp = AIDecisionMaker._estimate_melee_damage(
		snapshot.units["attacker"], snapshot.units["defender_fnp"])

	_assert(dmg_with_fnp < dmg_no_fnp,
		"Melee damage lower with target FNP 5+ (no_fnp=%.2f, with_fnp=%.2f)" % [dmg_no_fnp, dmg_with_fnp])

func test_charge_score_boosted_by_melee_leader():
	# Charge target scoring should be higher when the charger has melee leader bonuses
	var snapshot = _create_test_snapshot()
	var melee = _make_melee_weapon("Choppa", 4, 4, 1, 1, 2)

	# Unit without leader
	_add_unit(snapshot, "boyz_alone", 1, Vector2(0, 0), "Boyz Alone", 5,
		["INFANTRY"], [melee], 4, 5, 1, 0, {}, [], {})

	# Unit with Warboss leader (+1 melee hit)
	_add_unit(snapshot, "warboss", 1, Vector2(0, 100), "Warboss", 1,
		["CHARACTER"], [], 5, 4, 6, 0, {},
		[{"name": "Might is Right", "type": "Datasheet", "description": "+1 melee hit"}])
	_add_unit(snapshot, "boyz_led", 1, Vector2(0, 100), "Boyz Led", 5,
		["INFANTRY"], [melee], 4, 5, 1, 0, {},
		[], {"attached_characters": ["warboss"]})

	# Enemy target
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5,
		["INFANTRY"], [], 4, 3, 1, 0, {})

	var score_alone = AIDecisionMaker._score_charge_target(
		snapshot.units["boyz_alone"], snapshot.units["target"], snapshot, 1)
	var score_led = AIDecisionMaker._score_charge_target(
		snapshot.units["boyz_led"], snapshot.units["target"], snapshot, 1)

	_assert(score_led > score_alone,
		"Charge score higher with Warboss leader (alone=%.2f, led=%.2f)" % [score_alone, score_led])

# =========================================================================
# T7-11: Deadly Demise detection tests
# =========================================================================

func test_deadly_demise_detection():
	var unit = {"meta": {"abilities": [
		{"name": "Deadly Demise D3", "type": "Datasheet", "description": "When destroyed, roll D3 mortal wounds"}
	]}}
	_assert(AIAbilityAnalyzer.has_deadly_demise(unit), "T7-11: Deadly Demise detected from ability name")

func test_deadly_demise_value_d3():
	var unit = {"meta": {"abilities": [
		{"name": "Deadly Demise D3", "type": "Datasheet", "description": "Roll D3 mortal wounds"}
	]}}
	var val = AIAbilityAnalyzer.get_deadly_demise_value(unit)
	_assert(val == 3, "T7-11: Deadly Demise D3 returns value 3 (got %d)" % val)

func test_deadly_demise_value_d6():
	var unit = {"meta": {"abilities": [
		{"name": "Deadly Demise D6", "type": "Datasheet", "description": "Roll D6 mortal wounds"}
	]}}
	var val = AIAbilityAnalyzer.get_deadly_demise_value(unit)
	_assert(val == 6, "T7-11: Deadly Demise D6 returns value 6 (got %d)" % val)

func test_deadly_demise_not_present():
	var unit = {"meta": {"abilities": [
		{"name": "Stealth", "type": "Datasheet"}
	]}}
	_assert(not AIAbilityAnalyzer.has_deadly_demise(unit), "T7-11: Deadly Demise not detected on non-DD unit")
	var val = AIAbilityAnalyzer.get_deadly_demise_value(unit)
	_assert(val == 0, "T7-11: Non-DD unit returns value 0 (got %d)" % val)

func test_is_unit_doomed():
	# Single-model vehicle with 1/12 wounds remaining
	var unit = {"models": [
		{"id": "m1", "alive": true, "wounds": 12, "current_wounds": 2}
	]}
	_assert(AIAbilityAnalyzer.is_unit_doomed(unit), "T7-11: Vehicle with 2/12 wounds is doomed")

func test_is_unit_not_doomed():
	# Vehicle with 8/12 wounds remaining
	var unit = {"models": [
		{"id": "m1", "alive": true, "wounds": 12, "current_wounds": 8}
	]}
	_assert(not AIAbilityAnalyzer.is_unit_doomed(unit), "T7-11: Vehicle with 8/12 wounds is not doomed")

# =========================================================================
# T7-11: Lone Operative movement helper tests
# =========================================================================

func test_lone_operative_movement_helper():
	# Test that AIDecisionMaker helper correctly computes safe positions
	var centroid = Vector2(800, 600)
	var enemies = {}
	# Place an enemy within 10" (too close)
	enemies["e1"] = {
		"id": "e1", "owner": 2,
		"models": [{"id": "m1", "alive": true, "position": Vector2(800, 200), "base_mm": 32}],
		"meta": {"name": "Enemy", "stats": {"move": 6}}
	}
	var objectives = [Vector2(400, 400)]
	var safe_pos = AIDecisionMaker._get_lone_operative_safe_position(
		centroid, 6.0, enemies, objectives, objectives[0]
	)
	_assert(safe_pos != Vector2.INF, "T7-11: Lone Operative safe position found when enemy is close")
	# The safe position should be further from the enemy than the current position
	if safe_pos != Vector2.INF:
		var current_enemy_dist = centroid.distance_to(Vector2(800, 200))
		var new_enemy_dist = safe_pos.distance_to(Vector2(800, 200))
		_assert(new_enemy_dist > current_enemy_dist,
			"T7-11: Safe position is further from enemy (was %.1f\", now %.1f\")" % [
				current_enemy_dist / 40.0, new_enemy_dist / 40.0])

# =========================================================================
# T7-11: Profile includes Deadly Demise fields
# =========================================================================

func test_profile_includes_deadly_demise():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "vehicle", 2, Vector2(200, 200), "Battlewagon", 1,
		["VEHICLE"], [], 12, 3, 16, 0, {},
		[{"name": "Deadly Demise D6", "type": "Datasheet", "description": "D6 mortal wounds"}])
	# Set wounds low to make it doomed
	snapshot.units["vehicle"]["models"][0]["current_wounds"] = 3

	var profile = AIAbilityAnalyzer.get_unit_ability_profile("vehicle", snapshot.units["vehicle"], snapshot.units)
	_assert(profile["has_deadly_demise"], "T7-11: Profile shows has_deadly_demise for vehicle")
	_assert(profile["deadly_demise_value"] == 6, "T7-11: Profile shows DD value 6 (got %d)" % profile["deadly_demise_value"])
	_assert(profile["is_doomed"], "T7-11: Profile shows is_doomed for low-health vehicle")

# =========================================================================
# T7-11: Oath of Moment prefers leader targets with buffs
# =========================================================================

func test_oath_prefers_leader_with_buffs():
	var snapshot = _create_test_snapshot()
	# Regular infantry unit
	_add_unit(snapshot, "regular", 2, Vector2(400, 0), "Regular Infantry", 5,
		["INFANTRY"], [_make_ranged_weapon("Lasgun", 4, 3, 0, 1, 1, 24)], 3, 5, 1, 0, {}, [])
	snapshot.units["regular"]["meta"]["points"] = "100"
	# Leader character with "while leading" ability
	_add_unit(snapshot, "leader", 2, Vector2(600, 0), "Captain", 1,
		["CHARACTER", "INFANTRY"], [_make_melee_weapon("Power Sword", 2, 5, 3, 2, 5)],
		4, 3, 5, 4, {},
		[{"name": "Rites of Battle", "type": "Datasheet", "description": "While this model is leading a unit, re-roll hit rolls of 1"}])
	snapshot.units["leader"]["meta"]["points"] = "100"
	snapshot.units["leader"]["attachment_data"] = {"attached_characters": []}
	snapshot.units["leader"]["attached_to"] = "bodyguard_squad"

	# Add a friendly shooter for the AI
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "AI Shooter", 5,
		["INFANTRY"], [_make_ranged_weapon("Bolt Rifle", 3, 4, 1, 1, 2, 24)], 4, 3, 2, 0, {}, [])

	var oath_actions = [
		{"type": "SELECT_OATH_TARGET", "target_unit_id": "regular"},
		{"type": "SELECT_OATH_TARGET", "target_unit_id": "leader"}
	]

	var result = AIDecisionMaker._select_oath_of_moment_target(snapshot, oath_actions, 1)
	_assert(result.get("type") == "SELECT_OATH_TARGET",
		"T7-11: Oath selects a target when leader and regular are available")
	# The leader (with while-leading buffs and CHARACTER keyword) should be preferred
	_assert(result.get("target_unit_id") == "leader",
		"T7-11: Oath prefers leader character with while-leading buffs (got %s)" % result.get("target_unit_id", ""))

# =========================================================================
# T7-11: Charge score boosted by Deadly Demise on doomed vehicles
# =========================================================================

func test_charge_score_boosted_by_deadly_demise():
	var snapshot = _create_test_snapshot()
	var melee = _make_melee_weapon("Deff Rolla", 3, 9, 2, 2, 6)

	# Doomed vehicle WITH Deadly Demise
	_add_unit(snapshot, "dd_vehicle", 1, Vector2(0, 0), "Battlewagon DD", 1,
		["VEHICLE"], [melee], 12, 3, 16, 0, {},
		[{"name": "Deadly Demise D6", "type": "Datasheet", "description": "D6 mortal wounds"}])
	snapshot.units["dd_vehicle"]["models"][0]["current_wounds"] = 3  # Doomed

	# Same vehicle WITHOUT Deadly Demise
	_add_unit(snapshot, "no_dd_vehicle", 1, Vector2(0, 100), "Battlewagon", 1,
		["VEHICLE"], [melee], 12, 3, 16, 0, {}, [])
	snapshot.units["no_dd_vehicle"]["models"][0]["current_wounds"] = 3  # Also doomed

	# Enemy target
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5,
		["INFANTRY"], [], 4, 3, 1, 0, {})

	var score_dd = AIDecisionMaker._score_charge_target(
		snapshot.units["dd_vehicle"], snapshot.units["target"], snapshot, 1)
	var score_no_dd = AIDecisionMaker._score_charge_target(
		snapshot.units["no_dd_vehicle"], snapshot.units["target"], snapshot, 1)

	_assert(score_dd > score_no_dd,
		"T7-11: Charge score higher for doomed Deadly Demise vehicle (dd=%.2f, no_dd=%.2f)" % [score_dd, score_no_dd])

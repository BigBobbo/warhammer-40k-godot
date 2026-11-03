extends SceneTree

# Test AI Weapon-Target Efficiency Matching
# Verifies that the AI correctly classifies weapons and targets, and applies
# efficiency multipliers to prefer appropriate weapon-target pairings:
# - Anti-tank weapons vs vehicles/monsters
# - Anti-infantry weapons vs hordes
# - Penalizing multi-damage weapons on single-wound models
# Run with: godot --headless --script tests/unit/test_ai_weapon_efficiency.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Weapon-Target Efficiency Matching Tests ===\n")
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
		print("PASS: %s (got %.3f, expected %.3f)" % [message, actual, expected])
	else:
		_fail_count += 1
		print("FAIL: %s (got %.3f, expected %.3f, diff %.4f > tolerance %.4f)" % [message, actual, expected, diff, tolerance])

func _run_tests():
	# Weapon role classification
	test_classify_lascannon_as_anti_tank()
	test_classify_bolt_rifle_as_anti_infantry()
	test_classify_heavy_bolter_as_general_purpose()
	test_classify_anti_vehicle_keyword_weapon()
	test_classify_anti_infantry_keyword_weapon()
	test_classify_torrent_weapon_as_anti_infantry()
	test_classify_high_attacks_low_damage_as_anti_infantry()

	# Target type classification
	test_classify_vehicle_target()
	test_classify_monster_target()
	test_classify_horde_target()
	test_classify_elite_target()
	test_classify_high_toughness_no_keyword_as_vehicle()
	test_classify_small_1w_squad_as_horde()
	test_classify_large_2w_squad_as_horde()

	# Damage parsing
	test_parse_average_damage_fixed()
	test_parse_average_damage_d3()
	test_parse_average_damage_d6()
	test_parse_average_damage_d3_plus_1()
	test_parse_average_damage_d6_plus_1()

	# Efficiency multiplier
	test_efficiency_anti_tank_vs_vehicle()
	test_efficiency_anti_tank_vs_horde()
	test_efficiency_anti_infantry_vs_horde()
	test_efficiency_anti_infantry_vs_vehicle()
	test_efficiency_general_purpose_is_neutral()
	test_efficiency_multi_damage_on_1w_models_penalized()
	test_efficiency_d2_on_1w_models_moderate_penalty()
	test_efficiency_anti_keyword_bonus()

	# T7-7: Damage waste penalty specifics
	test_d1_weapon_no_waste_penalty()
	test_waste_penalty_not_applied_to_multi_wound_targets()

	# Integration: estimate_weapon_damage includes efficiency
	test_lascannon_prefers_vehicle_over_grots()
	test_bolt_rifle_prefers_infantry_over_vehicle()
	test_multi_damage_waste_penalty_in_estimate()

	# Integration: focus fire plan respects efficiency
	test_focus_fire_assigns_lascannon_to_vehicle()

	# Name helpers
	test_weapon_role_names()
	test_target_type_names()

# =========================================================================
# Helper: Create test data
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
		uname: String = "Test Unit", num_models: int = 1, keywords: Array = ["INFANTRY"],
		weapons: Array = [], toughness: int = 4, save_val: int = 3,
		wounds: int = 2, oc: int = 2) -> void:
	var models = []
	for i in range(num_models):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": 32,
			"base_type": "circular",
			"base_dimensions": {},
			"position": Vector2(pos.x + i * 40, pos.y),
			"wounds": wounds,
			"current_wounds": wounds
		})
	snapshot.units[unit_id] = {
		"id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": uname,
			"stats": {
				"move": 6,
				"toughness": toughness,
				"save": save_val,
				"wounds": wounds,
				"leadership": 6,
				"objective_control": oc
			},
			"keywords": keywords,
			"weapons": weapons
		},
		"models": models,
		"flags": {}
	}

func _make_ranged_weapon(wname: String = "Bolt rifle", bs: int = 3,
		strength: int = 4, ap: int = 1, damage: int = 1, attacks: int = 2,
		weapon_range: int = 24, special_rules: String = "") -> Dictionary:
	var w = {
		"name": wname,
		"type": "Ranged",
		"ballistic_skill": str(bs),
		"strength": str(strength),
		"ap": "-%d" % ap if ap > 0 else "0",
		"damage": str(damage),
		"attacks": str(attacks),
		"range": str(weapon_range),
	}
	if special_rules != "":
		w["special_rules"] = special_rules
	return w

func _make_ranged_weapon_str_damage(wname: String, bs: int, strength: int,
		ap: int, damage_str: String, attacks_str: String,
		weapon_range: int = 48, special_rules: String = "") -> Dictionary:
	var w = {
		"name": wname,
		"type": "Ranged",
		"ballistic_skill": str(bs),
		"strength": str(strength),
		"ap": "-%d" % ap if ap > 0 else "0",
		"damage": damage_str,
		"attacks": attacks_str,
		"range": str(weapon_range),
	}
	if special_rules != "":
		w["special_rules"] = special_rules
	return w

func _reset_focus_fire_state() -> void:
	AIDecisionMaker._focus_fire_plan_built = false
	AIDecisionMaker._focus_fire_plan.clear()

# =========================================================================
# Tests: _classify_weapon_role
# =========================================================================

func test_classify_lascannon_as_anti_tank():
	# Lascannon: S12 AP-3 D6+1 — classic anti-tank
	var lascannon = _make_ranged_weapon_str_damage("Lascannon", 3, 12, 3, "D6+1", "1")
	var role = AIDecisionMaker._classify_weapon_role(lascannon)
	_assert(role == AIDecisionMaker.WeaponRole.ANTI_TANK,
		"Lascannon (S12 AP-3 D6+1) classified as ANTI_TANK (got %s)" % AIDecisionMaker._weapon_role_name(role))

func test_classify_bolt_rifle_as_anti_infantry():
	# Bolt rifle: S4 AP-1 D1 A2 — classic anti-infantry
	var bolt_rifle = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	var role = AIDecisionMaker._classify_weapon_role(bolt_rifle)
	_assert(role == AIDecisionMaker.WeaponRole.ANTI_INFANTRY,
		"Bolt rifle (S4 AP-1 D1) classified as ANTI_INFANTRY (got %s)" % AIDecisionMaker._weapon_role_name(role))

func test_classify_heavy_bolter_as_general_purpose():
	# Heavy bolter: S5 AP-1 D2 A3 — somewhere in between
	var heavy_bolter = _make_ranged_weapon("Heavy bolter", 4, 5, 1, 2, 3, 36)
	var role = AIDecisionMaker._classify_weapon_role(heavy_bolter)
	# Heavy bolter should be general purpose or anti-infantry — it is S5 AP-1 D2
	# S5 <= 5 (anti-inf +1), AP-1 <= 1 (anti-inf +1), D2 not <= 1 (no anti-inf +2),
	# not >= 3 (no anti-tank +2). So anti_infantry_score = 2, anti_tank_score = 0.
	# Attacks=3, D2 > 1.5 so no extra anti-inf. Total anti-inf = 2 < 3.
	# Result: GENERAL_PURPOSE
	_assert(role == AIDecisionMaker.WeaponRole.GENERAL_PURPOSE,
		"Heavy bolter (S5 AP-1 D2) classified as GENERAL_PURPOSE (got %s)" % AIDecisionMaker._weapon_role_name(role))

func test_classify_anti_vehicle_keyword_weapon():
	# Zzap gun: has "anti-vehicle 4+" special rule
	var zzap = _make_ranged_weapon_str_damage("Zzap gun", 5, 9, 3, "5", "1", 36, "anti-vehicle 4+")
	var role = AIDecisionMaker._classify_weapon_role(zzap)
	_assert(role == AIDecisionMaker.WeaponRole.ANTI_TANK,
		"Zzap gun with anti-vehicle 4+ classified as ANTI_TANK (got %s)" % AIDecisionMaker._weapon_role_name(role))

func test_classify_anti_infantry_keyword_weapon():
	# Kombi-weapon: has "anti-infantry 4+" special rule
	var kombi = _make_ranged_weapon("Kombi-weapon", 5, 4, 0, 1, 1, 24, "anti-infantry 4+, devastating wounds, rapid fire 1")
	var role = AIDecisionMaker._classify_weapon_role(kombi)
	_assert(role == AIDecisionMaker.WeaponRole.ANTI_INFANTRY,
		"Kombi-weapon with anti-infantry 4+ classified as ANTI_INFANTRY (got %s)" % AIDecisionMaker._weapon_role_name(role))

func test_classify_torrent_weapon_as_anti_infantry():
	# Flamer: S4 AP0 D1 A1, torrent — auto-hit, anti-infantry
	var flamer = _make_ranged_weapon("Flamer", 0, 4, 0, 1, 1, 12, "torrent")
	var role = AIDecisionMaker._classify_weapon_role(flamer)
	_assert(role == AIDecisionMaker.WeaponRole.ANTI_INFANTRY,
		"Flamer with torrent classified as ANTI_INFANTRY (got %s)" % AIDecisionMaker._weapon_role_name(role))

func test_classify_high_attacks_low_damage_as_anti_infantry():
	# Assault cannon: S6 AP0 D1 A6 — lots of shots, low damage
	var assault_cannon = _make_ranged_weapon("Assault cannon", 3, 6, 0, 1, 6, 24)
	var role = AIDecisionMaker._classify_weapon_role(assault_cannon)
	# S6 > 5 (no anti-inf +1 for S), AP0 <= 1 (+1), D1 (+2), A6 >= 4 and D1 <= 1.5 (+1) = 4
	_assert(role == AIDecisionMaker.WeaponRole.ANTI_INFANTRY,
		"Assault cannon (S6 AP0 D1 A6) classified as ANTI_INFANTRY (got %s)" % AIDecisionMaker._weapon_role_name(role))

# =========================================================================
# Tests: _classify_target_type
# =========================================================================

func test_classify_vehicle_target():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "tank", 2, Vector2(0, 0), "Leman Russ", 1, ["VEHICLE", "IMPERIUM"], [], 11, 3, 13)
	var target_type = AIDecisionMaker._classify_target_type(snapshot.units["tank"])
	_assert(target_type == AIDecisionMaker.TargetType.VEHICLE_MONSTER,
		"VEHICLE keyword target classified as VEHICLE_MONSTER")

func test_classify_monster_target():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "monster", 2, Vector2(0, 0), "Carnifex", 1, ["MONSTER", "TYRANIDS"], [], 9, 3, 8)
	var target_type = AIDecisionMaker._classify_target_type(snapshot.units["monster"])
	_assert(target_type == AIDecisionMaker.TargetType.VEHICLE_MONSTER,
		"MONSTER keyword target classified as VEHICLE_MONSTER")

func test_classify_horde_target():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "horde", 2, Vector2(0, 0), "Ork Boyz", 17, ["INFANTRY", "ORKS"], [], 5, 5, 1)
	var target_type = AIDecisionMaker._classify_target_type(snapshot.units["horde"])
	_assert(target_type == AIDecisionMaker.TargetType.HORDE,
		"17 models with 1W classified as HORDE")

func test_classify_elite_target():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "elite", 2, Vector2(0, 0), "Terminators", 5, ["INFANTRY", "TERMINATOR"], [], 5, 2, 3)
	var target_type = AIDecisionMaker._classify_target_type(snapshot.units["elite"])
	_assert(target_type == AIDecisionMaker.TargetType.ELITE,
		"5 models with 3W classified as ELITE")

func test_classify_high_toughness_no_keyword_as_vehicle():
	var snapshot = _create_test_snapshot()
	# Very tough single model with no VEHICLE/MONSTER keyword but high T and W
	_add_unit(snapshot, "big", 2, Vector2(0, 0), "Big Thing", 1, ["INFANTRY"], [], 10, 2, 12)
	var target_type = AIDecisionMaker._classify_target_type(snapshot.units["big"])
	_assert(target_type == AIDecisionMaker.TargetType.VEHICLE_MONSTER,
		"T10 12W single model classified as VEHICLE_MONSTER even without keyword")

func test_classify_small_1w_squad_as_horde():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "squad", 2, Vector2(0, 0), "Guardsmen", 10, ["INFANTRY"], [], 3, 5, 1)
	var target_type = AIDecisionMaker._classify_target_type(snapshot.units["squad"])
	_assert(target_type == AIDecisionMaker.TargetType.HORDE,
		"10 models with 1W classified as HORDE")

func test_classify_large_2w_squad_as_horde():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "squad", 2, Vector2(0, 0), "Intercessors", 10, ["INFANTRY"], [], 4, 3, 2)
	var target_type = AIDecisionMaker._classify_target_type(snapshot.units["squad"])
	_assert(target_type == AIDecisionMaker.TargetType.HORDE,
		"10 models with 2W classified as HORDE (large squad)")

# =========================================================================
# Tests: _parse_average_damage
# =========================================================================

func test_parse_average_damage_fixed():
	var dmg = AIDecisionMaker._parse_average_damage("3")
	_assert_approx(dmg, 3.0, 0.01, "Fixed damage '3' parses to 3.0")

func test_parse_average_damage_d3():
	var dmg = AIDecisionMaker._parse_average_damage("D3")
	_assert_approx(dmg, 2.0, 0.01, "D3 damage averages to 2.0")

func test_parse_average_damage_d6():
	var dmg = AIDecisionMaker._parse_average_damage("D6")
	_assert_approx(dmg, 3.5, 0.01, "D6 damage averages to 3.5")

func test_parse_average_damage_d3_plus_1():
	var dmg = AIDecisionMaker._parse_average_damage("D3+1")
	_assert_approx(dmg, 3.0, 0.01, "D3+1 damage averages to 3.0")

func test_parse_average_damage_d6_plus_1():
	var dmg = AIDecisionMaker._parse_average_damage("D6+1")
	_assert_approx(dmg, 4.5, 0.01, "D6+1 damage averages to 4.5")

# =========================================================================
# Tests: _calculate_efficiency_multiplier
# =========================================================================

func test_efficiency_anti_tank_vs_vehicle():
	var lascannon = _make_ranged_weapon_str_damage("Lascannon", 3, 12, 3, "D6+1", "1")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "tank", 2, Vector2(0, 0), "Tank", 1, ["VEHICLE"], [], 10, 3, 12)
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(lascannon, snapshot.units["tank"])
	_assert(eff > 1.0, "Anti-tank weapon vs vehicle gets bonus (got %.2f)" % eff)

func test_efficiency_anti_tank_vs_horde():
	var lascannon = _make_ranged_weapon_str_damage("Lascannon", 3, 12, 3, "D6+1", "1")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "grots", 2, Vector2(0, 0), "Gretchin", 10, ["INFANTRY"], [], 2, 7, 1)
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(lascannon, snapshot.units["grots"])
	_assert(eff < 1.0, "Anti-tank weapon vs 1W horde gets penalty (got %.2f)" % eff)

func test_efficiency_anti_infantry_vs_horde():
	var bolt_rifle = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "horde", 2, Vector2(0, 0), "Boyz", 10, ["INFANTRY"], [], 5, 5, 1)
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(bolt_rifle, snapshot.units["horde"])
	_assert(eff >= 1.0, "Anti-infantry weapon vs horde gets bonus or neutral (got %.2f)" % eff)

func test_efficiency_anti_infantry_vs_vehicle():
	var bolt_rifle = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "tank", 2, Vector2(0, 0), "Tank", 1, ["VEHICLE"], [], 10, 3, 12)
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(bolt_rifle, snapshot.units["tank"])
	_assert(eff < 1.0, "Anti-infantry weapon vs vehicle gets penalty (got %.2f)" % eff)

func test_efficiency_general_purpose_is_neutral():
	# Heavy bolter is general purpose
	var heavy_bolter = _make_ranged_weapon("Heavy bolter", 4, 5, 1, 2, 3, 36)
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(0, 0), "Marines", 5, ["INFANTRY"], [], 4, 3, 2)
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(heavy_bolter, snapshot.units["target"])
	_assert_approx(eff, 1.0, 0.01, "General purpose weapon vs elite is neutral")

func test_efficiency_multi_damage_on_1w_models_penalized():
	# D6+1 damage (avg 4.5) on 1W models — heavy waste
	# T7-7: ANTI_TANK vs HORDE = POOR_MATCH (0.6) × DAMAGE_WASTE_PENALTY_HEAVY (0.4) = 0.24
	# Both role mismatch AND damage waste penalty apply together
	var lascannon = _make_ranged_weapon_str_damage("Lascannon", 3, 12, 3, "D6+1", "1")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "grots", 2, Vector2(0, 0), "Gretchin", 10, ["INFANTRY"], [], 2, 7, 1)
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(lascannon, snapshot.units["grots"])
	# Role penalty (0.6) × Heavy waste penalty (0.4) = 0.24
	_assert(eff < 0.3, "Lascannon vs 1W horde has combined role + waste penalty (got %.2f, expect ~0.24)" % eff)

func test_efficiency_d2_on_1w_models_moderate_penalty():
	# D2 weapon on 1W models — moderate waste
	# T7-7: Autocannon (S7 AP-1 D2) is GENERAL_PURPOSE. GP vs HORDE = neutral (1.0),
	# but damage waste penalty for D2 vs 1W = DAMAGE_WASTE_PENALTY_MODERATE (0.7).
	# Total efficiency = 1.0 × 0.7 = 0.7
	var autocannon = _make_ranged_weapon("Autocannon", 4, 7, 1, 2, 2, 48)
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "grots", 2, Vector2(0, 0), "Gretchin", 10, ["INFANTRY"], [], 2, 7, 1)

	# Verify efficiency multiplier includes waste penalty
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(autocannon, snapshot.units["grots"])
	_assert_approx(eff, 0.7, 0.01, "D2 GENERAL_PURPOSE vs 1W horde: efficiency = 1.0 × 0.7 waste penalty")

	# Also verify wound overflow cap still works in damage estimate
	_add_unit(snapshot, "shooter", 1, Vector2(0, 200), "Shooter", 1, ["INFANTRY"], [autocannon])
	var dmg_vs_1w = AIDecisionMaker._estimate_weapon_damage(autocannon, snapshot.units["grots"], snapshot, snapshot.units["shooter"])
	# Wound overflow caps D2 to 1 per hit, then efficiency 0.7 further reduces
	_assert(dmg_vs_1w < 1.0, "D2 weapon vs 1W target has reduced damage from wound overflow cap + waste penalty (got %.3f)" % dmg_vs_1w)

func test_efficiency_anti_keyword_bonus():
	# Kombi-weapon with anti-infantry 4+ vs INFANTRY target
	var kombi = _make_ranged_weapon("Kombi-weapon", 5, 4, 0, 1, 1, 24, "anti-infantry 4+, devastating wounds")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "infantry", 2, Vector2(0, 0), "Marines", 5, ["INFANTRY"], [], 4, 3, 2)
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(kombi, snapshot.units["infantry"])
	_assert(eff > 1.0, "Weapon with matching anti-keyword gets bonus (got %.2f)" % eff)

# =========================================================================
# Tests: T7-7 damage waste penalty specifics
# =========================================================================

func test_d1_weapon_no_waste_penalty():
	# Bolt rifle (D1) vs 1W horde — no waste, should be unpenalized
	var bolt_rifle = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "horde", 2, Vector2(0, 0), "Boyz", 10, ["INFANTRY"], [], 5, 5, 1)
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(bolt_rifle, snapshot.units["horde"])
	# ANTI_INFANTRY vs HORDE = PERFECT_MATCH (1.4), D1 means no waste penalty
	_assert_approx(eff, AIDecisionMaker.EFFICIENCY_PERFECT_MATCH, 0.01,
		"D1 weapon vs 1W horde: no waste penalty, pure role bonus (got %.2f)" % eff)

func test_waste_penalty_not_applied_to_multi_wound_targets():
	# D6+1 damage weapon (avg 4.5) vs 3W targets — no waste penalty (target has multiple wounds)
	var lascannon = _make_ranged_weapon_str_damage("Lascannon", 3, 12, 3, "D6+1", "1")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "terminators", 2, Vector2(0, 0), "Terminators", 5, ["INFANTRY"], [], 5, 2, 3)
	var eff = AIDecisionMaker._calculate_efficiency_multiplier(lascannon, snapshot.units["terminators"])
	# ANTI_TANK vs ELITE = GOOD_MATCH (1.15), no waste penalty since WPM = 3
	_assert_approx(eff, AIDecisionMaker.EFFICIENCY_GOOD_MATCH, 0.01,
		"D6+1 weapon vs 3W targets: no waste penalty (got %.2f)" % eff)

# =========================================================================
# Tests: Integration with _estimate_weapon_damage
# =========================================================================

func test_lascannon_prefers_vehicle_over_grots():
	var snapshot = _create_test_snapshot()
	var lascannon = _make_ranged_weapon_str_damage("Lascannon", 3, 12, 3, "6", "1", 48)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [lascannon])
	_add_unit(snapshot, "tank", 2, Vector2(800, 0), "Tank", 1, ["VEHICLE"], [], 10, 3, 12)
	_add_unit(snapshot, "grots", 2, Vector2(800, 200), "Gretchin", 10, ["INFANTRY"], [], 2, 7, 1)

	var dmg_vs_tank = AIDecisionMaker._estimate_weapon_damage(lascannon, snapshot.units["tank"], snapshot, snapshot.units["shooter"])
	var dmg_vs_grots = AIDecisionMaker._estimate_weapon_damage(lascannon, snapshot.units["grots"], snapshot, snapshot.units["shooter"])

	# Raw damage vs grots might be higher (easy to wound T2), but efficiency should flip it
	_assert(dmg_vs_tank > dmg_vs_grots,
		"Lascannon eff-adjusted damage vs tank (%.2f) > vs grots (%.2f)" % [dmg_vs_tank, dmg_vs_grots])

func test_bolt_rifle_prefers_infantry_over_vehicle():
	var snapshot = _create_test_snapshot()
	var bolt_rifle = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 5, ["INFANTRY"], [bolt_rifle])
	_add_unit(snapshot, "infantry", 2, Vector2(400, 0), "Boyz", 10, ["INFANTRY"], [], 5, 5, 1)
	_add_unit(snapshot, "tank", 2, Vector2(400, 200), "Tank", 1, ["VEHICLE"], [], 10, 3, 12)

	var dmg_vs_infantry = AIDecisionMaker._estimate_weapon_damage(bolt_rifle, snapshot.units["infantry"], snapshot, snapshot.units["shooter"])
	var dmg_vs_tank = AIDecisionMaker._estimate_weapon_damage(bolt_rifle, snapshot.units["tank"], snapshot, snapshot.units["shooter"])

	_assert(dmg_vs_infantry > dmg_vs_tank,
		"Bolt rifle eff-adjusted damage vs infantry (%.2f) > vs tank (%.2f)" % [dmg_vs_infantry, dmg_vs_tank])

func test_multi_damage_waste_penalty_in_estimate():
	var snapshot = _create_test_snapshot()
	# D2 damage weapon — classified as ANTI_TANK (S7 >= 7: +2, AP-2 >= 2: +1 = score 3)
	var d2_weapon = _make_ranged_weapon_str_damage("Plasma gun", 3, 7, 2, "2", "1", 24)

	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [d2_weapon])
	_add_unit(snapshot, "1w_target", 2, Vector2(400, 0), "1W Guys", 10, ["INFANTRY"], [], 4, 5, 1)
	_add_unit(snapshot, "2w_target", 2, Vector2(400, 200), "2W Guys", 5, ["INFANTRY"], [], 4, 3, 2)

	var dmg_vs_1w = AIDecisionMaker._estimate_weapon_damage(d2_weapon, snapshot.units["1w_target"], snapshot, snapshot.units["shooter"])
	var dmg_vs_2w = AIDecisionMaker._estimate_weapon_damage(d2_weapon, snapshot.units["2w_target"], snapshot, snapshot.units["shooter"])

	# T7-7: D2 on 1W targets gets both wound overflow cap AND waste penalty.
	# vs 1W: ANTI_TANK vs HORDE (0.6) × waste moderate (0.7) = 0.42 efficiency
	# vs 2W: ANTI_TANK vs ELITE (1.15) × no waste = 1.15 efficiency
	# Despite 1W target having worse save, the penalties should make 2W target preferred
	print("  Info: D2 weapon vs 1W = %.3f (eff 0.42), vs 2W = %.3f (eff 1.15)" % [dmg_vs_1w, dmg_vs_2w])
	_assert(dmg_vs_2w > dmg_vs_1w,
		"D2 weapon prefers 2W target (%.3f) over 1W target (%.3f) due to waste penalty" % [dmg_vs_2w, dmg_vs_1w])

# =========================================================================
# Tests: Integration with focus fire plan
# =========================================================================

func test_focus_fire_assigns_lascannon_to_vehicle():
	_reset_focus_fire_state()
	var snapshot = _create_test_snapshot()

	var bolt_rifle = _make_ranged_weapon("Bolt rifle", 3, 4, 1, 1, 2, 24)
	var lascannon = _make_ranged_weapon_str_damage("Lascannon", 3, 12, 3, "6", "1", 48)

	# Squad A has bolt rifles, Squad B has lascannon + bolt rifles
	_add_unit(snapshot, "squad_a", 1, Vector2(0, 0), "Tactical Squad", 5, ["INFANTRY"], [bolt_rifle])
	_add_unit(snapshot, "squad_b", 1, Vector2(0, 100), "Devastators", 1, ["INFANTRY"], [lascannon, bolt_rifle])

	# Enemies: a vehicle and an infantry horde
	_add_unit(snapshot, "tank", 2, Vector2(800, 0), "Battlewagon", 1, ["VEHICLE", "ORKS"], [], 10, 3, 16)
	_add_unit(snapshot, "boyz", 2, Vector2(800, 200), "Boyz", 10, ["INFANTRY", "ORKS"], [], 5, 5, 1)

	var plan = AIDecisionMaker._build_focus_fire_plan(snapshot, ["squad_a", "squad_b"], 1)

	# Check that the lascannon is assigned to the tank, not the boyz
	var lascannon_target = ""
	if plan.has("squad_b"):
		for assignment in plan["squad_b"]:
			var wid = assignment.get("weapon_id", "")
			if "lascannon" in wid.to_lower():
				lascannon_target = assignment.get("target_unit_id", "")
				break

	# The lascannon should prefer the tank due to efficiency matching
	_assert(lascannon_target == "tank",
		"Lascannon assigned to tank (vehicle) not boyz (horde) — got target: %s" % lascannon_target)

# =========================================================================
# Tests: Name helpers
# =========================================================================

func test_weapon_role_names():
	_assert(AIDecisionMaker._weapon_role_name(AIDecisionMaker.WeaponRole.ANTI_TANK) == "Anti-Tank",
		"ANTI_TANK role name is 'Anti-Tank'")
	_assert(AIDecisionMaker._weapon_role_name(AIDecisionMaker.WeaponRole.ANTI_INFANTRY) == "Anti-Infantry",
		"ANTI_INFANTRY role name is 'Anti-Infantry'")
	_assert(AIDecisionMaker._weapon_role_name(AIDecisionMaker.WeaponRole.GENERAL_PURPOSE) == "General",
		"GENERAL_PURPOSE role name is 'General'")

func test_target_type_names():
	_assert(AIDecisionMaker._target_type_name(AIDecisionMaker.TargetType.VEHICLE_MONSTER) == "Vehicle/Monster",
		"VEHICLE_MONSTER type name is 'Vehicle/Monster'")
	_assert(AIDecisionMaker._target_type_name(AIDecisionMaker.TargetType.ELITE) == "Elite",
		"ELITE type name is 'Elite'")
	_assert(AIDecisionMaker._target_type_name(AIDecisionMaker.TargetType.HORDE) == "Horde",
		"HORDE type name is 'Horde'")

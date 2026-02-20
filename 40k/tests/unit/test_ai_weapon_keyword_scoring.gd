extends SceneTree

# Test AI Weapon Keyword Awareness in Target Scoring (SHOOT-5)
# Verifies that the AI correctly accounts for weapon keywords when scoring targets:
# - Blast: bonus attacks vs large units
# - Rapid Fire: bonus attacks at half range
# - Melta: bonus damage at half range
# - Anti-keyword: improved wound probability vs matching keywords
# - Torrent: auto-hit (p_hit = 1.0)
# - Sustained Hits: extra hits on critical hit rolls
# - Lethal Hits: critical hits auto-wound
# - Devastating Wounds: critical wounds bypass saves
# Run with: godot --headless --script tests/unit/test_ai_weapon_keyword_scoring.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Weapon Keyword Scoring Tests (SHOOT-5) ===\n")
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
		print("FAIL: %s (got %.4f, expected %.4f, diff %.5f > tolerance %.5f)" % [message, actual, expected, diff, tolerance])

func _assert_greater(actual: float, threshold: float, message: String) -> void:
	if actual > threshold:
		_pass_count += 1
		print("PASS: %s (%.4f > %.4f)" % [message, actual, threshold])
	else:
		_fail_count += 1
		print("FAIL: %s (%.4f NOT > %.4f)" % [message, actual, threshold])

func _run_tests():
	# --- Parsing helpers ---
	test_parse_rapid_fire_value()
	test_parse_melta_value()
	test_parse_anti_keyword_data()
	test_parse_sustained_hits_value_fixed()
	test_parse_sustained_hits_value_dice()
	test_is_within_half_range()

	# --- Torrent ---
	test_torrent_sets_p_hit_to_one()
	test_torrent_weapon_scores_higher_than_same_bs_weapon()

	# --- Blast ---
	test_blast_bonus_attacks_vs_large_unit()
	test_blast_no_bonus_vs_small_unit()
	test_blast_correct_per_5_model_scaling()
	test_blast_5_model_threshold()
	test_blast_weapon_prefers_large_unit()

	# --- Rapid Fire ---
	test_rapid_fire_bonus_at_half_range()
	test_rapid_fire_no_bonus_beyond_half_range()
	test_rapid_fire_fallback_when_unknown_distance()

	# --- Melta ---
	test_melta_bonus_damage_at_half_range()
	test_melta_no_bonus_beyond_half_range()

	# --- Anti-keyword ---
	test_anti_infantry_improves_wound_prob_vs_infantry()
	test_anti_keyword_no_effect_vs_non_matching()
	test_anti_vehicle_improves_wound_prob_vs_vehicle()

	# --- Sustained Hits ---
	test_sustained_hits_increases_expected_damage()

	# --- Lethal Hits ---
	test_lethal_hits_increases_expected_damage()

	# --- Devastating Wounds ---
	test_devastating_wounds_increases_expected_damage()

	# --- Combined keywords ---
	test_anti_infantry_plus_devastating_wounds_combo()
	test_blast_plus_torrent_combo()
	test_rapid_fire_plus_sustained_hits_combo()

	# --- Integration: _score_shooting_target uses keywords ---
	test_score_shooting_target_torrent_vs_normal()
	test_score_shooting_target_blast_vs_horde()
	test_estimate_weapon_damage_uses_keywords()

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

# =========================================================================
# Tests: Parsing helpers
# =========================================================================

func test_parse_rapid_fire_value():
	_assert(AIDecisionMaker._parse_rapid_fire_value("rapid fire 1") == 1,
		"Parse 'rapid fire 1' returns 1")
	_assert(AIDecisionMaker._parse_rapid_fire_value("rapid fire 2") == 2,
		"Parse 'rapid fire 2' returns 2")
	_assert(AIDecisionMaker._parse_rapid_fire_value("anti-infantry 4+, devastating wounds, rapid fire 1") == 1,
		"Parse rapid fire from combined rules returns 1")
	_assert(AIDecisionMaker._parse_rapid_fire_value("torrent") == 0,
		"Parse rapid fire from unrelated rules returns 0")
	_assert(AIDecisionMaker._parse_rapid_fire_value("") == 0,
		"Parse rapid fire from empty string returns 0")

func test_parse_melta_value():
	_assert(AIDecisionMaker._parse_melta_value("melta 2") == 2,
		"Parse 'melta 2' returns 2")
	_assert(AIDecisionMaker._parse_melta_value("melta 4") == 4,
		"Parse 'melta 4' returns 4")
	_assert(AIDecisionMaker._parse_melta_value("blast") == 0,
		"Parse melta from unrelated rules returns 0")

func test_parse_anti_keyword_data():
	var data = AIDecisionMaker._parse_anti_keyword_data("anti-infantry 4+")
	_assert(data.size() == 1, "Parse anti-infantry 4+ returns 1 entry")
	if data.size() > 0:
		_assert(data[0]["keyword"] == "INFANTRY", "Anti-keyword is INFANTRY")
		_assert(data[0]["threshold"] == 4, "Anti-keyword threshold is 4")

	var multi = AIDecisionMaker._parse_anti_keyword_data("anti-vehicle 4+, anti-infantry 2+")
	_assert(multi.size() == 2, "Parse multi anti-keywords returns 2 entries")

	var none = AIDecisionMaker._parse_anti_keyword_data("torrent, blast")
	_assert(none.size() == 0, "Parse non-anti rules returns 0 entries")

func test_parse_sustained_hits_value_fixed():
	_assert_approx(AIDecisionMaker._parse_sustained_hits_value("sustained hits 1"), 1.0, 0.01,
		"Parse 'sustained hits 1' returns 1.0")
	_assert_approx(AIDecisionMaker._parse_sustained_hits_value("sustained hits 2"), 2.0, 0.01,
		"Parse 'sustained hits 2' returns 2.0")
	_assert_approx(AIDecisionMaker._parse_sustained_hits_value("torrent"), 0.0, 0.01,
		"Parse unrelated rules returns 0.0")

func test_parse_sustained_hits_value_dice():
	_assert_approx(AIDecisionMaker._parse_sustained_hits_value("sustained hits d3"), 2.0, 0.01,
		"Parse 'sustained hits d3' returns 2.0 (avg of D3)")
	_assert_approx(AIDecisionMaker._parse_sustained_hits_value("sustained hits d6"), 3.5, 0.01,
		"Parse 'sustained hits d6' returns 3.5 (avg of D6)")

func test_is_within_half_range():
	_assert(AIDecisionMaker._is_within_half_range(5.0, 24.0) == 1,
		"5 inches at 24 range is within half range")
	_assert(AIDecisionMaker._is_within_half_range(12.0, 24.0) == 1,
		"12 inches at 24 range is exactly half range (within)")
	_assert(AIDecisionMaker._is_within_half_range(13.0, 24.0) == -1,
		"13 inches at 24 range is NOT within half range")
	_assert(AIDecisionMaker._is_within_half_range(-1.0, 24.0) == 0,
		"Unknown distance returns 0")
	_assert(AIDecisionMaker._is_within_half_range(5.0, 0.0) == 0,
		"Zero weapon range returns 0")

# =========================================================================
# Tests: Torrent
# =========================================================================

func test_torrent_sets_p_hit_to_one():
	var flamer = _make_ranged_weapon("Flamer", 4, 4, 0, 1, 1, 12, "torrent")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Ork Boyz", 5, ["INFANTRY"], [], 5, 5, 1)
	var target = snapshot.units["target"]

	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		flamer, target,
		1.0, 0.5, 0.5, 0.5, 1.0,  # base values
		4, 5, 5, 0, 0,
		6.0, 12.0
	)
	_assert_approx(mods["p_hit"], 1.0, 0.001,
		"Torrent sets p_hit to 1.0")

func test_torrent_weapon_scores_higher_than_same_bs_weapon():
	# Compare a torrent flamer vs a non-torrent weapon with same stats
	var flamer = _make_ranged_weapon("Flamer", 4, 4, 0, 1, 1, 12, "torrent")
	var normal = _make_ranged_weapon("Laspistol", 4, 4, 0, 1, 1, 12, "")

	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [flamer, normal])
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 4, 5, 1)

	var score_torrent = AIDecisionMaker._score_shooting_target(flamer, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	var score_normal = AIDecisionMaker._score_shooting_target(normal, snapshot.units["target"], snapshot, snapshot.units["shooter"])

	_assert_greater(score_torrent, score_normal,
		"Torrent weapon scores higher than equivalent non-torrent weapon")

# =========================================================================
# Tests: Blast
# =========================================================================

func test_blast_bonus_attacks_vs_large_unit():
	var blast_weapon = _make_ranged_weapon("Frag missile", 3, 4, 0, 1, 2, 48, "blast")
	var snapshot = _create_test_snapshot()
	# 8 models = floor(8/5) = +1 attack from Blast (10th ed)
	_add_unit(snapshot, "horde", 2, Vector2(400, 0), "Horde", 8, ["INFANTRY"], [], 4, 5, 1)

	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		blast_weapon, snapshot.units["horde"],
		2.0, 0.667, 0.5, 0.5, 1.0,
		4, 4, 5, 0, 0,
		10.0, 48.0
	)
	_assert_approx(mods["attacks"], 3.0, 0.01,
		"Blast adds +1 attack vs 8-model unit (2 -> 3)")

func test_blast_no_bonus_vs_small_unit():
	var blast_weapon = _make_ranged_weapon("Frag missile", 3, 4, 0, 1, 2, 48, "blast")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "small", 2, Vector2(400, 0), "Small Unit", 3, ["INFANTRY"], [], 4, 5, 1)

	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		blast_weapon, snapshot.units["small"],
		2.0, 0.667, 0.5, 0.5, 1.0,
		4, 4, 5, 0, 0,
		10.0, 48.0
	)
	_assert_approx(mods["attacks"], 2.0, 0.01,
		"Blast adds no bonus attacks vs 3-model unit")

func test_blast_correct_per_5_model_scaling():
	# 10th ed Blast: +1 per 5 models. 15 models = floor(15/5) = +3
	var blast_weapon = _make_ranged_weapon("Frag missile", 3, 4, 0, 1, 2, 48, "blast")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "big_horde", 2, Vector2(400, 0), "Big Horde", 15, ["INFANTRY"], [], 4, 5, 1)

	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		blast_weapon, snapshot.units["big_horde"],
		2.0, 0.667, 0.5, 0.5, 1.0,
		4, 4, 5, 0, 0,
		10.0, 48.0
	)
	# 2 base + 3 blast (15/5) = 5
	_assert_approx(mods["attacks"], 5.0, 0.01,
		"Blast adds +3 attacks vs 15-model unit (2 -> 5)")

func test_blast_5_model_threshold():
	# Exactly 5 models should get +1 from Blast (floor(5/5) = 1)
	var blast_weapon = _make_ranged_weapon("Frag missile", 3, 4, 0, 1, 2, 48, "blast")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "squad5", 2, Vector2(400, 0), "Squad of 5", 5, ["INFANTRY"], [], 4, 5, 1)

	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		blast_weapon, snapshot.units["squad5"],
		2.0, 0.667, 0.5, 0.5, 1.0,
		4, 4, 5, 0, 0,
		10.0, 48.0
	)
	# 2 base + 1 blast (5/5) = 3
	_assert_approx(mods["attacks"], 3.0, 0.01,
		"Blast adds +1 attack vs exactly 5-model unit (2 -> 3)")

	# 4 models should get NO bonus
	var snapshot2 = _create_test_snapshot()
	_add_unit(snapshot2, "squad4", 2, Vector2(400, 0), "Squad of 4", 4, ["INFANTRY"], [], 4, 5, 1)
	var mods2 = AIDecisionMaker._apply_weapon_keyword_modifiers(
		blast_weapon, snapshot2.units["squad4"],
		2.0, 0.667, 0.5, 0.5, 1.0,
		4, 4, 5, 0, 0,
		10.0, 48.0
	)
	_assert_approx(mods2["attacks"], 2.0, 0.01,
		"Blast adds no bonus vs 4-model unit")

func test_blast_weapon_prefers_large_unit():
	var blast_weapon = _make_ranged_weapon("Frag missile", 3, 4, 0, 1, 2, 48, "blast")
	var snapshot = _create_test_snapshot()
	# Positions within range (48" = 1920 px, but using close positions)
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [blast_weapon])
	_add_unit(snapshot, "big", 2, Vector2(400, 0), "Big Squad", 10, ["INFANTRY"], [], 4, 5, 1)
	_add_unit(snapshot, "small", 2, Vector2(400, 100), "Small Squad", 3, ["INFANTRY"], [], 4, 5, 1)

	var score_big = AIDecisionMaker._score_shooting_target(blast_weapon, snapshot.units["big"], snapshot, snapshot.units["shooter"])
	var score_small = AIDecisionMaker._score_shooting_target(blast_weapon, snapshot.units["small"], snapshot, snapshot.units["shooter"])

	_assert_greater(score_big, score_small,
		"Blast weapon scores large unit higher than small unit")

# =========================================================================
# Tests: Rapid Fire
# =========================================================================

func test_rapid_fire_bonus_at_half_range():
	var rf_weapon = _make_ranged_weapon("Boltgun", 3, 4, 0, 1, 2, 24, "rapid fire 1")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 4, 5, 1)

	# 5 inches = within half range of 24" weapon (half = 12")
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		rf_weapon, snapshot.units["target"],
		2.0, 0.667, 0.5, 0.5, 1.0,
		4, 4, 5, 0, 0,
		5.0, 24.0  # 5 inches, well within half range
	)
	_assert_approx(mods["attacks"], 3.0, 0.01,
		"Rapid Fire 1 adds +1 attack at half range (2 -> 3)")

func test_rapid_fire_no_bonus_beyond_half_range():
	var rf_weapon = _make_ranged_weapon("Boltgun", 3, 4, 0, 1, 2, 24, "rapid fire 1")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 4, 5, 1)

	# 20 inches = beyond half range of 24" weapon
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		rf_weapon, snapshot.units["target"],
		2.0, 0.667, 0.5, 0.5, 1.0,
		4, 4, 5, 0, 0,
		20.0, 24.0
	)
	_assert_approx(mods["attacks"], 2.0, 0.01,
		"Rapid Fire 1 adds no bonus beyond half range")

func test_rapid_fire_fallback_when_unknown_distance():
	var rf_weapon = _make_ranged_weapon("Boltgun", 3, 4, 0, 1, 2, 24, "rapid fire 1")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 4, 5, 1)

	# -1 distance = unknown
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		rf_weapon, snapshot.units["target"],
		2.0, 0.667, 0.5, 0.5, 1.0,
		4, 4, 5, 0, 0,
		-1.0, 24.0
	)
	# Expected: 2.0 + 1 * 0.5 = 2.5
	_assert_approx(mods["attacks"], 2.5, 0.01,
		"Rapid Fire 1 applies probability-weighted bonus for unknown distance (2.5)")

# =========================================================================
# Tests: Melta
# =========================================================================

func test_melta_bonus_damage_at_half_range():
	var melta = _make_ranged_weapon_str_damage("Multi-melta", 3, 9, 4, "D6", "2", 24, "melta 2")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Tank", 1, ["VEHICLE"], [], 11, 3, 13)

	# At half range (6 inches for 24" weapon = within half range of 12")
	var base_damage = 3.5  # average of D6
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		melta, snapshot.units["target"],
		2.0, 0.667, 0.833, 0.5, base_damage,
		9, 11, 3, 4, 0,
		6.0, 24.0
	)
	_assert_approx(mods["damage"], base_damage + 2.0, 0.01,
		"Melta 2 adds +2 damage at half range (3.5 -> 5.5)")

func test_melta_no_bonus_beyond_half_range():
	var melta = _make_ranged_weapon_str_damage("Multi-melta", 3, 9, 4, "D6", "2", 24, "melta 2")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Tank", 1, ["VEHICLE"], [], 11, 3, 13)

	var base_damage = 3.5
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		melta, snapshot.units["target"],
		2.0, 0.667, 0.833, 0.5, base_damage,
		9, 11, 3, 4, 0,
		20.0, 24.0  # Beyond half range
	)
	_assert_approx(mods["damage"], base_damage, 0.01,
		"Melta 2 adds no bonus beyond half range")

# =========================================================================
# Tests: Anti-keyword
# =========================================================================

func test_anti_infantry_improves_wound_prob_vs_infantry():
	# Anti-infantry 4+: critical wounds on 4+ vs INFANTRY (instead of just 6+)
	var kombi = _make_ranged_weapon("Kombi", 3, 4, 0, 1, 1, 24, "anti-infantry 4+")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Infantry", 5, ["INFANTRY"], [], 4, 5, 1)

	# Base p_wound for S4 vs T4 = 0.5 (4+)
	var base_p_wound = 0.5
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		kombi, snapshot.units["target"],
		1.0, 0.667, base_p_wound, 0.5, 1.0,
		4, 4, 5, 0, 0,
		10.0, 24.0
	)
	# Anti 4+: p_crit = (7-4)/6 = 0.5
	# new_p_wound = (1-0.5)*0.5 + 0.5 = 0.75
	_assert_approx(mods["p_wound"], 0.75, 0.01,
		"Anti-infantry 4+ improves p_wound from 0.5 to 0.75 vs INFANTRY")

func test_anti_keyword_no_effect_vs_non_matching():
	# Anti-infantry should not affect wounding against VEHICLE
	var kombi = _make_ranged_weapon("Kombi", 3, 4, 0, 1, 1, 24, "anti-infantry 4+")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Tank", 1, ["VEHICLE"], [], 11, 3, 13)

	var base_p_wound = AIDecisionMaker._wound_probability(4, 11)  # S4 vs T11 = 6+
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		kombi, snapshot.units["target"],
		1.0, 0.667, base_p_wound, 0.5, 1.0,
		4, 11, 3, 0, 0,
		10.0, 24.0
	)
	_assert_approx(mods["p_wound"], base_p_wound, 0.001,
		"Anti-infantry has no effect vs VEHICLE target")

func test_anti_vehicle_improves_wound_prob_vs_vehicle():
	# Anti-vehicle 4+
	var weapon = _make_ranged_weapon_str_damage("Zzap gun", 5, 9, 3, "5", "1", 36, "anti-vehicle 4+")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(400, 0), "Tank", 1, ["VEHICLE"], [], 11, 3, 13)

	var base_p_wound = AIDecisionMaker._wound_probability(9, 11)  # S9 vs T11 = 5+ = 2/6
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		weapon, snapshot.units["target"],
		1.0, 0.5, base_p_wound, 0.5, 5.0,
		9, 11, 3, 3, 0,
		15.0, 36.0
	)
	# Anti 4+: p_crit = (7-4)/6 = 0.5
	# new_p_wound = (1-0.5)*base + 0.5 = 0.5 * (2/6) + 0.5 = 0.1667 + 0.5 = 0.6667
	_assert_approx(mods["p_wound"], 0.6667, 0.01,
		"Anti-vehicle 4+ improves p_wound from %.3f to ~0.667 vs VEHICLE" % base_p_wound)

# =========================================================================
# Tests: Sustained Hits
# =========================================================================

func test_sustained_hits_increases_expected_damage():
	var weapon_sh = _make_ranged_weapon("Guardian spear", 2, 4, 1, 1, 4, 24, "sustained hits 1")
	var weapon_no = _make_ranged_weapon("Basic gun", 2, 4, 1, 1, 4, 24, "")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon_sh, weapon_no])
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 4, 3, 1)

	var score_sh = AIDecisionMaker._score_shooting_target(weapon_sh, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	var score_no = AIDecisionMaker._score_shooting_target(weapon_no, snapshot.units["target"], snapshot, snapshot.units["shooter"])

	_assert_greater(score_sh, score_no,
		"Sustained Hits 1 weapon scores higher than same weapon without it")

# =========================================================================
# Tests: Lethal Hits
# =========================================================================

func test_lethal_hits_increases_expected_damage():
	var weapon_lh = _make_ranged_weapon("Lethal gun", 3, 4, 1, 1, 2, 24, "lethal hits")
	var weapon_no = _make_ranged_weapon("Normal gun", 3, 4, 1, 1, 2, 24, "")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon_lh, weapon_no])
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 8, 3, 3)

	var score_lh = AIDecisionMaker._score_shooting_target(weapon_lh, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	var score_no = AIDecisionMaker._score_shooting_target(weapon_no, snapshot.units["target"], snapshot, snapshot.units["shooter"])

	_assert_greater(score_lh, score_no,
		"Lethal Hits weapon scores higher than same weapon without it (especially vs tough targets)")

# =========================================================================
# Tests: Devastating Wounds
# =========================================================================

func test_devastating_wounds_increases_expected_damage():
	var weapon_dw = _make_ranged_weapon("Devastating gun", 3, 4, 0, 1, 2, 24, "devastating wounds")
	var weapon_no = _make_ranged_weapon("Normal gun", 3, 4, 0, 1, 2, 24, "")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [weapon_dw, weapon_no])
	# Well-armoured target where bypassing saves matters most
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 4, 2, 2)

	var score_dw = AIDecisionMaker._score_shooting_target(weapon_dw, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	var score_no = AIDecisionMaker._score_shooting_target(weapon_no, snapshot.units["target"], snapshot, snapshot.units["shooter"])

	_assert_greater(score_dw, score_no,
		"Devastating Wounds weapon scores higher vs well-armoured target")

# =========================================================================
# Tests: Combined keywords
# =========================================================================

func test_anti_infantry_plus_devastating_wounds_combo():
	# This is a classic Ork kombi-weapon: anti-infantry 4+, devastating wounds, rapid fire 1
	var kombi = _make_ranged_weapon("Kombi-weapon", 5, 4, 0, 1, 1, 24, "anti-infantry 4+, devastating wounds, rapid fire 1")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [kombi])
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Infantry", 10, ["INFANTRY"], [], 4, 4, 1)

	# At close range (5 inches = within half range for RF bonus)
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		kombi, snapshot.units["target"],
		1.0, AIDecisionMaker._hit_probability(5), AIDecisionMaker._wound_probability(4, 4),
		1.0 - AIDecisionMaker._save_probability(4, 0, 0), 1.0,
		4, 4, 4, 0, 0,
		5.0, 24.0
	)
	# Rapid fire 1 at half range: attacks 1 + 1 = 2
	_assert_approx(mods["attacks"], 2.0, 0.01,
		"Combo: Rapid Fire 1 adds +1 attack at half range")
	# Anti-infantry 4+ should improve wound probability
	_assert_greater(mods["p_wound"], 0.5,
		"Combo: Anti-infantry 4+ improves wound probability above base 0.5")

func test_blast_plus_torrent_combo():
	# A Torrent + Blast weapon (e.g. heavy flamer with blast)
	var weapon = _make_ranged_weapon("Blast Flamer", 4, 5, 1, 1, 6, 12, "torrent, blast")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Horde", 8, ["INFANTRY"], [], 4, 5, 1)

	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		weapon, snapshot.units["target"],
		6.0, 0.5, 0.667, 0.5, 1.0,
		5, 4, 5, 1, 0,
		5.0, 12.0
	)
	_assert_approx(mods["p_hit"], 1.0, 0.001,
		"Torrent + Blast: p_hit is 1.0")
	_assert_approx(mods["attacks"], 7.0, 0.01,
		"Torrent + Blast: +1 attack from Blast vs 8-model unit (6 -> 7)")

func test_rapid_fire_plus_sustained_hits_combo():
	# Rapid Fire 1 + Sustained Hits 1
	var weapon = _make_ranged_weapon("Special boltgun", 3, 4, 1, 1, 2, 24, "rapid fire 1, sustained hits 1")
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 4, 4, 1)

	# At half range
	var p_hit = AIDecisionMaker._hit_probability(3)  # 4/6
	var mods = AIDecisionMaker._apply_weapon_keyword_modifiers(
		weapon, snapshot.units["target"],
		2.0, p_hit, 0.5, 0.5, 1.0,
		4, 4, 4, 1, 0,
		5.0, 24.0
	)
	# RF1 at half range: 2 + 1 = 3 base attacks
	# Sustained Hits 1: multiplier = (p_hit + 1/6 * 1) / p_hit = (4/6 + 1/6) / (4/6) = 5/4 = 1.25
	# Final attacks: 3 * 1.25 = 3.75
	_assert_approx(mods["attacks"], 3.75, 0.05,
		"Rapid Fire 1 + Sustained Hits 1 at half range: 2 -> 3 (RF) * 1.25 (SH) = 3.75")

# =========================================================================
# Tests: Integration with _score_shooting_target and _estimate_weapon_damage
# =========================================================================

func test_score_shooting_target_torrent_vs_normal():
	# A torrent flamer should score much higher than a non-torrent weapon with same stats
	var torrent = _make_ranged_weapon("Flamer", 4, 4, 0, 1, 6, 12, "torrent")
	var normal = _make_ranged_weapon("Autogun", 4, 4, 0, 1, 6, 12, "")

	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [torrent, normal])
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 4, 5, 1)

	var score_t = AIDecisionMaker._score_shooting_target(torrent, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	var score_n = AIDecisionMaker._score_shooting_target(normal, snapshot.units["target"], snapshot, snapshot.units["shooter"])

	# Torrent has p_hit=1.0 vs normal with p_hit = (7-4)/6 = 0.5
	# So torrent should be exactly 2x the normal score
	_assert_greater(score_t, score_n * 1.5,
		"Torrent weapon scores at least 1.5x higher in _score_shooting_target")

func test_score_shooting_target_blast_vs_horde():
	var blast = _make_ranged_weapon("Frag missile", 3, 4, 0, 1, 3, 48, "blast")
	var normal = _make_ranged_weapon("Krak missile", 3, 4, 0, 1, 3, 48, "")

	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [blast, normal])
	_add_unit(snapshot, "horde", 2, Vector2(400, 0), "Big Horde", 12, ["INFANTRY"], [], 4, 5, 1)

	var score_blast = AIDecisionMaker._score_shooting_target(blast, snapshot.units["horde"], snapshot, snapshot.units["shooter"])
	var score_normal = AIDecisionMaker._score_shooting_target(normal, snapshot.units["horde"], snapshot, snapshot.units["shooter"])

	# Blast adds +2 attacks vs 12-model horde: floor(12/5) = 2 (3 base + 2 = 5)
	_assert_greater(score_blast, score_normal,
		"Blast weapon scores higher vs 12-model horde in _score_shooting_target")

func test_estimate_weapon_damage_uses_keywords():
	# Verify _estimate_weapon_damage also uses keyword modifiers
	var torrent = _make_ranged_weapon("Flamer", 4, 4, 0, 1, 6, 12, "torrent")
	var normal = _make_ranged_weapon("Autogun", 4, 4, 0, 1, 6, 12, "")

	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "shooter", 1, Vector2(0, 0), "Shooter", 1, ["INFANTRY"], [torrent, normal])
	_add_unit(snapshot, "target", 2, Vector2(200, 0), "Target", 5, ["INFANTRY"], [], 4, 5, 1)

	var dmg_t = AIDecisionMaker._estimate_weapon_damage(torrent, snapshot.units["target"], snapshot, snapshot.units["shooter"])
	var dmg_n = AIDecisionMaker._estimate_weapon_damage(normal, snapshot.units["target"], snapshot, snapshot.units["shooter"])

	_assert_greater(dmg_t, dmg_n,
		"Torrent weapon has higher _estimate_weapon_damage than same stats without torrent")

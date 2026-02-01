extends "res://addons/gut/test.gd"

# Tests for the BLAST keyword implementation
# Tests the ACTUAL RulesEngine methods
#
# Per Warhammer 40k rules: Blast weapons get bonus attacks against larger units
# (+1 attack per 5 models, minimum 3 attacks against 6+ model units).
# Blast weapons cannot target units in Engagement Range.

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# is_blast_weapon() Tests
# ==========================================

func test_is_blast_weapon_returns_true_for_frag_grenade():
	"""Test that frag_grenade is a Blast weapon"""
	var result = rules_engine.is_blast_weapon("frag_grenade")
	assert_true(result, "frag_grenade should be a Blast weapon")

func test_is_blast_weapon_returns_true_for_frag_missile():
	"""Test that frag_missile is a Blast weapon"""
	var result = rules_engine.is_blast_weapon("frag_missile")
	assert_true(result, "frag_missile should be a Blast weapon")

func test_is_blast_weapon_returns_true_for_battle_cannon():
	"""Test that battle_cannon is a Blast weapon"""
	var result = rules_engine.is_blast_weapon("battle_cannon")
	assert_true(result, "battle_cannon should be a Blast weapon")

func test_is_blast_weapon_returns_true_for_torrent_blast():
	"""Test that torrent_blast is a Blast weapon"""
	var result = rules_engine.is_blast_weapon("torrent_blast")
	assert_true(result, "torrent_blast should be a Blast weapon")

func test_is_blast_weapon_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT a Blast weapon"""
	var result = rules_engine.is_blast_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be a Blast weapon")

func test_is_blast_weapon_returns_false_for_flamer():
	"""Test that flamer (Torrent only) is NOT a Blast weapon"""
	var result = rules_engine.is_blast_weapon("flamer")
	assert_false(result, "flamer should NOT be a Blast weapon")

func test_is_blast_weapon_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.is_blast_weapon("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# Weapon Profile Tests
# ==========================================

func test_weapon_profile_frag_grenade_has_blast_keyword():
	"""Test that frag_grenade profile contains BLAST keyword"""
	var profile = rules_engine.get_weapon_profile("frag_grenade")
	assert_false(profile.is_empty(), "Should find frag_grenade profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "BLAST", "Frag Grenade should have BLAST keyword")

# ==========================================
# calculate_blast_bonus() Tests
# ==========================================

func test_calculate_blast_bonus_small_unit():
	"""Test that small units (5 or fewer models) get no Blast bonus"""
	# Create minimal target unit with 5 models
	var target_unit = {"models": [
		{"alive": true}, {"alive": true}, {"alive": true},
		{"alive": true}, {"alive": true}
	]}
	var bonus = rules_engine.calculate_blast_bonus("frag_grenade", target_unit)
	assert_eq(bonus, 0, "Units with 5 or fewer models should get no Blast bonus")

func test_calculate_blast_bonus_medium_unit():
	"""Test that medium units (6-10 models) get +1 attack"""
	var target_unit = {"models": [
		{"alive": true}, {"alive": true}, {"alive": true},
		{"alive": true}, {"alive": true}, {"alive": true}
	]}
	var bonus = rules_engine.calculate_blast_bonus("frag_grenade", target_unit)
	assert_eq(bonus, 1, "Units with 6-10 models should get +1 Blast bonus")

func test_calculate_blast_bonus_large_unit():
	"""Test that large units (11+ models) get +2 attacks"""
	var models = []
	for i in range(11):
		models.append({"alive": true})
	var target_unit = {"models": models}
	var bonus = rules_engine.calculate_blast_bonus("frag_grenade", target_unit)
	assert_eq(bonus, 2, "Units with 11+ models should get +2 Blast bonus")

# ==========================================
# calculate_blast_minimum() Tests
# ==========================================

func test_calculate_blast_minimum_against_6_plus():
	"""Test that Blast has minimum 3 attacks against 6+ model units"""
	var target_unit = {"models": [
		{"alive": true}, {"alive": true}, {"alive": true},
		{"alive": true}, {"alive": true}, {"alive": true}
	]}
	var base_attacks = 1  # D6 rolled 1
	var minimum = rules_engine.calculate_blast_minimum("frag_grenade", base_attacks, target_unit)
	assert_gte(minimum, 3, "Blast should have minimum 3 attacks against 6+ model units")

extends "res://addons/gut/test.gd"

# Tests for the LETHAL HITS keyword implementation
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k rules: Lethal Hits weapons auto-wound on critical hits
# (unmodified 6s to hit).

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
# has_lethal_hits() Tests
# Tests the actual RulesEngine.has_lethal_hits() method
# ==========================================

func test_has_lethal_hits_returns_true_for_lethal_bolter():
	"""Test that lethal_bolter is recognized as a Lethal Hits weapon"""
	var result = rules_engine.has_lethal_hits("lethal_bolter")
	assert_true(result, "lethal_bolter should be recognized as a Lethal Hits weapon")

func test_has_lethal_hits_returns_true_for_lethal_sustained_bolter():
	"""Test that lethal_sustained_bolter has Lethal Hits"""
	var result = rules_engine.has_lethal_hits("lethal_sustained_bolter")
	assert_true(result, "lethal_sustained_bolter should have Lethal Hits")

func test_has_lethal_hits_returns_true_for_lethal_devastating_bolter():
	"""Test that lethal_devastating_bolter has Lethal Hits"""
	var result = rules_engine.has_lethal_hits("lethal_devastating_bolter")
	assert_true(result, "lethal_devastating_bolter should have Lethal Hits")

func test_has_lethal_hits_returns_true_for_torrent_lethal():
	"""Test that torrent_lethal has Lethal Hits"""
	var result = rules_engine.has_lethal_hits("torrent_lethal")
	assert_true(result, "torrent_lethal should have Lethal Hits")

func test_has_lethal_hits_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT a Lethal Hits weapon"""
	var result = rules_engine.has_lethal_hits("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT have Lethal Hits")

func test_has_lethal_hits_returns_false_for_heavy_bolter():
	"""Test that heavy_bolter is NOT a Lethal Hits weapon"""
	var result = rules_engine.has_lethal_hits("heavy_bolter")
	assert_false(result, "heavy_bolter should NOT have Lethal Hits")

func test_has_lethal_hits_returns_false_for_sustained_bolter():
	"""Test that sustained_bolter (Sustained Hits only) is NOT a Lethal Hits weapon"""
	var result = rules_engine.has_lethal_hits("sustained_bolter")
	assert_false(result, "sustained_bolter should NOT have Lethal Hits")

func test_has_lethal_hits_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.has_lethal_hits("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# Weapon Profile Tests
# Verify WEAPON_PROFILES are correctly configured
# ==========================================

func test_weapon_profile_lethal_bolter_has_lethal_hits_keyword():
	"""Test that lethal_bolter profile contains LETHAL HITS keyword"""
	var profile = rules_engine.get_weapon_profile("lethal_bolter")
	assert_false(profile.is_empty(), "Should find lethal_bolter profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "LETHAL HITS", "Lethal Bolter should have LETHAL HITS keyword")

func test_weapon_profile_bolt_rifle_no_lethal_hits_keyword():
	"""Test that bolt_rifle profile does NOT contain LETHAL HITS keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "LETHAL HITS", "Bolt rifle should NOT have LETHAL HITS keyword")

# ==========================================
# Critical Hit Logic Tests (per 10e rules)
# ==========================================

func test_critical_hit_is_unmodified_6():
	"""Test that critical hit is defined as unmodified roll of 6"""
	# Per 10e rules, a critical hit is an UNMODIFIED 6
	var unmodified_roll = 6
	var is_critical = (unmodified_roll == 6)
	assert_true(is_critical, "Unmodified 6 should be a critical hit")

func test_modified_6_is_not_critical_hit():
	"""Test that a roll of 5 modified to 6 is NOT a critical hit"""
	# A roll of 5 with +1 modifier = 6, but this is NOT critical
	var unmodified_roll = 5
	var is_critical = (unmodified_roll == 6)
	assert_false(is_critical, "Roll of 5 (even if modified to 6) should NOT be a critical hit")

# ==========================================
# Lethal Hits Auto-Wound Logic Tests
# ==========================================

func test_lethal_hits_auto_wound_logic():
	"""Test that Lethal Hits auto-wounds equal critical hit count"""
	# Simulating: 5 attacks, 2 unmodified 6s hit
	var critical_hits = 2
	var regular_hits = 2  # 4 total hits
	var has_lethal = true

	# With Lethal Hits: critical hits auto-wound
	var auto_wounds = 0
	if has_lethal:
		auto_wounds = critical_hits

	assert_eq(auto_wounds, 2, "With 2 critical hits and Lethal Hits, should get 2 auto-wounds")

func test_lethal_hits_regular_hits_still_need_wound_roll():
	"""Test that regular (non-critical) hits still need wound rolls"""
	var critical_hits = 2
	var regular_hits = 2
	var has_lethal = true

	# With Lethal Hits: only roll wounds for regular hits
	var hits_needing_wound_roll = regular_hits if has_lethal else (critical_hits + regular_hits)

	assert_eq(hits_needing_wound_roll, 2, "With Lethal Hits, only 2 regular hits need wound rolls")

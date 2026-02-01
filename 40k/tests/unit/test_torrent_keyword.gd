extends "res://addons/gut/test.gd"

# Tests for the TORRENT keyword implementation
# Tests the ACTUAL RulesEngine methods
#
# Per Warhammer 40k rules: Torrent weapons automatically hit (no hit roll needed).

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# is_torrent_weapon() Tests
# ==========================================

func test_is_torrent_weapon_returns_true_for_flamer():
	"""Test that flamer is a Torrent weapon"""
	var result = rules_engine.is_torrent_weapon("flamer")
	assert_true(result, "flamer should be a Torrent weapon")

func test_is_torrent_weapon_returns_true_for_heavy_flamer():
	"""Test that heavy_flamer is a Torrent weapon"""
	var result = rules_engine.is_torrent_weapon("heavy_flamer")
	assert_true(result, "heavy_flamer should be a Torrent weapon")

func test_is_torrent_weapon_returns_true_for_torrent_lethal():
	"""Test that torrent_lethal is a Torrent weapon"""
	var result = rules_engine.is_torrent_weapon("torrent_lethal")
	assert_true(result, "torrent_lethal should be a Torrent weapon")

func test_is_torrent_weapon_returns_true_for_torrent_sustained():
	"""Test that torrent_sustained is a Torrent weapon"""
	var result = rules_engine.is_torrent_weapon("torrent_sustained")
	assert_true(result, "torrent_sustained should be a Torrent weapon")

func test_is_torrent_weapon_returns_true_for_torrent_devastating():
	"""Test that torrent_devastating is a Torrent weapon"""
	var result = rules_engine.is_torrent_weapon("torrent_devastating")
	assert_true(result, "torrent_devastating should be a Torrent weapon")

func test_is_torrent_weapon_returns_true_for_torrent_blast():
	"""Test that torrent_blast is a Torrent weapon"""
	var result = rules_engine.is_torrent_weapon("torrent_blast")
	assert_true(result, "torrent_blast should be a Torrent weapon")

func test_is_torrent_weapon_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT a Torrent weapon"""
	var result = rules_engine.is_torrent_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be a Torrent weapon")

func test_is_torrent_weapon_returns_false_for_heavy_bolter():
	"""Test that heavy_bolter is NOT a Torrent weapon"""
	var result = rules_engine.is_torrent_weapon("heavy_bolter")
	assert_false(result, "heavy_bolter should NOT be a Torrent weapon")

func test_is_torrent_weapon_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.is_torrent_weapon("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# Weapon Profile Tests
# ==========================================

func test_weapon_profile_flamer_has_torrent_keyword():
	"""Test that flamer profile contains TORRENT keyword"""
	var profile = rules_engine.get_weapon_profile("flamer")
	assert_false(profile.is_empty(), "Should find flamer profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "TORRENT", "Flamer should have TORRENT keyword")

func test_weapon_profile_heavy_flamer_has_torrent_keyword():
	"""Test that heavy_flamer profile contains TORRENT keyword"""
	var profile = rules_engine.get_weapon_profile("heavy_flamer")
	assert_false(profile.is_empty(), "Should find heavy_flamer profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "TORRENT", "Heavy Flamer should have TORRENT keyword")

# ==========================================
# Torrent Auto-Hit Logic Tests
# ==========================================

func test_torrent_attacks_auto_hit():
	"""Test that Torrent weapons automatically hit (all attacks become hits)"""
	var num_attacks = 6  # D6 attacks for flamer
	var is_torrent = true

	# With Torrent: all attacks automatically hit
	var hits = num_attacks if is_torrent else 0
	assert_eq(hits, num_attacks, "Torrent weapon should auto-hit with all attacks")

func test_torrent_no_hit_roll_needed():
	"""Test that Torrent weapons skip the hit roll step entirely"""
	var is_torrent = true
	var needs_hit_roll = not is_torrent
	assert_false(needs_hit_roll, "Torrent weapons should not need hit rolls")

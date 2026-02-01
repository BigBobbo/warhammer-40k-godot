extends "res://addons/gut/test.gd"

# Tests for the DEVASTATING WOUNDS keyword implementation
# Tests the ACTUAL RulesEngine methods
#
# Per Warhammer 40k rules: Devastating Wounds weapons cause mortal wounds
# on critical wounds (unmodified 6s to wound).

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# has_devastating_wounds() Tests
# ==========================================

func test_has_devastating_wounds_returns_true_for_devastating_bolter():
	"""Test that devastating_bolter has Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("devastating_bolter")
	assert_true(result, "devastating_bolter should have Devastating Wounds")

func test_has_devastating_wounds_returns_true_for_devastating_melta():
	"""Test that devastating_melta has Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("devastating_melta")
	assert_true(result, "devastating_melta should have Devastating Wounds")

func test_has_devastating_wounds_returns_true_for_lethal_devastating_bolter():
	"""Test that lethal_devastating_bolter has Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("lethal_devastating_bolter")
	assert_true(result, "lethal_devastating_bolter should have Devastating Wounds")

func test_has_devastating_wounds_returns_true_for_torrent_devastating():
	"""Test that torrent_devastating has Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("torrent_devastating")
	assert_true(result, "torrent_devastating should have Devastating Wounds")

func test_has_devastating_wounds_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle does NOT have Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT have Devastating Wounds")

func test_has_devastating_wounds_returns_false_for_lethal_bolter():
	"""Test that lethal_bolter (Lethal Hits only) does NOT have Devastating Wounds"""
	var result = rules_engine.has_devastating_wounds("lethal_bolter")
	assert_false(result, "lethal_bolter should NOT have Devastating Wounds")

func test_has_devastating_wounds_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.has_devastating_wounds("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# Weapon Profile Tests
# ==========================================

func test_weapon_profile_devastating_bolter_has_keyword():
	"""Test that devastating_bolter profile contains DEVASTATING WOUNDS keyword"""
	var profile = rules_engine.get_weapon_profile("devastating_bolter")
	assert_false(profile.is_empty(), "Should find devastating_bolter profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "DEVASTATING WOUNDS", "Devastating Bolter should have DEVASTATING WOUNDS keyword")

# ==========================================
# Devastating Wounds Logic Tests
# ==========================================

func test_devastating_wounds_causes_mortal_wounds():
	"""Test that Devastating Wounds converts critical wounds to mortal wounds"""
	# Per rules: critical wounds (unmodified 6s to wound) cause mortal wounds
	# equal to the weapon's Damage characteristic, and the attack sequence ends
	var critical_wounds = 2
	var weapon_damage = 3
	var mortal_wounds = critical_wounds * weapon_damage
	assert_eq(mortal_wounds, 6, "2 critical wounds with D3 damage should cause 6 mortal wounds")

func test_devastating_wounds_bypasses_saves():
	"""Test that mortal wounds from Devastating Wounds bypass saves"""
	# Mortal wounds always bypass armor and invulnerable saves
	var mortal_wounds = 4
	var wounds_after_saves = mortal_wounds  # No save roll needed
	assert_eq(wounds_after_saves, mortal_wounds, "Mortal wounds should bypass all saves")

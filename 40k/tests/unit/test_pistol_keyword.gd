extends "res://addons/gut/test.gd"

# Tests for the PISTOL keyword implementation
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k rules: Units with PISTOL weapons can shoot while in
# Engagement Range, but can only target units they are in Engagement Range with.

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
# is_pistol_weapon() Tests
# Tests the actual RulesEngine.is_pistol_weapon() method
# ==========================================

func test_is_pistol_weapon_returns_true_for_plasma_pistol():
	"""Test that plasma_pistol is recognized as a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("plasma_pistol")
	assert_true(result, "plasma_pistol should be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_true_for_slugga():
	"""Test that slugga is recognized as a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("slugga")
	assert_true(result, "slugga should be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_false_for_shoota():
	"""Test that shoota (Assault weapon) is NOT a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("shoota")
	assert_false(result, "shoota should NOT be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_false_for_heavy_bolter():
	"""Test that heavy_bolter (Heavy weapon) is NOT a Pistol weapon"""
	var result = rules_engine.is_pistol_weapon("heavy_bolter")
	assert_false(result, "heavy_bolter should NOT be recognized as a Pistol weapon")

func test_is_pistol_weapon_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.is_pistol_weapon("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# Weapon Profile Tests
# Verify WEAPON_PROFILES are correctly configured
# ==========================================

func test_weapon_profile_plasma_pistol_has_pistol_keyword():
	"""Test that plasma_pistol profile contains PISTOL keyword"""
	var profile = rules_engine.get_weapon_profile("plasma_pistol")
	assert_false(profile.is_empty(), "Should find plasma_pistol profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "PISTOL", "Plasma Pistol should have PISTOL keyword")

func test_weapon_profile_slugga_has_pistol_keyword():
	"""Test that slugga profile contains PISTOL keyword"""
	var profile = rules_engine.get_weapon_profile("slugga")
	assert_false(profile.is_empty(), "Should find slugga profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "PISTOL", "Slugga should have PISTOL keyword")

func test_weapon_profile_bolt_rifle_no_pistol_keyword():
	"""Test that bolt_rifle profile does NOT contain PISTOL keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "PISTOL", "Bolt rifle should NOT have PISTOL keyword")

# ==========================================
# unit_has_pistol_weapons() Tests
# ==========================================

func test_unit_has_pistol_weapons_intercessors():
	"""Test that Intercessors unit has Pistol weapons (plasma_pistol on sergeant)"""
	var result = rules_engine.unit_has_pistol_weapons("U_INTERCESSORS_A")
	assert_true(result, "Intercessors (U_INTERCESSORS_A) should have Pistol weapons")

func test_unit_has_pistol_weapons_ork_boyz():
	"""Test that Ork Boyz unit has Pistol weapons (slugga)"""
	var result = rules_engine.unit_has_pistol_weapons("U_BOYZ_A")
	assert_true(result, "Ork Boyz (U_BOYZ_A) should have Pistol weapons (slugga)")

func test_unit_has_no_pistol_weapons_gretchin():
	"""Test that Gretchin unit does NOT have Pistol weapons"""
	var result = rules_engine.unit_has_pistol_weapons("U_GRETCHIN_A")
	assert_false(result, "Gretchin should NOT have Pistol weapons")

func test_unit_has_pistol_weapons_unknown_unit():
	"""Test that unknown unit returns false"""
	var result = rules_engine.unit_has_pistol_weapons("NONEXISTENT_UNIT")
	assert_false(result, "Unknown unit should return false")

# ==========================================
# get_unit_pistol_weapons() Tests
# ==========================================

func test_get_unit_pistol_weapons_intercessors():
	"""Test that we can get the pistol weapons for Intercessors"""
	var weapons = rules_engine.get_unit_pistol_weapons("U_INTERCESSORS_A")
	assert_false(weapons.is_empty(), "Intercessors should have pistol weapons")
	# The sergeant (m5) should have plasma_pistol
	var has_pistol = false
	for model_id in weapons:
		for weapon_id in weapons[model_id]:
			if weapon_id == "plasma_pistol":
				has_pistol = true
				break
	assert_true(has_pistol, "Should find plasma_pistol in Intercessors weapons")

func test_get_unit_pistol_weapons_gretchin_empty():
	"""Test that Gretchin have no pistol weapons"""
	var weapons = rules_engine.get_unit_pistol_weapons("U_GRETCHIN_A")
	assert_true(weapons.is_empty(), "Gretchin should have no pistol weapons")

# ==========================================
# Pistol + Other Keywords Tests
# ==========================================

func test_slugga_has_both_pistol_and_assault():
	"""Test that slugga has both PISTOL and ASSAULT keywords"""
	var is_pistol = rules_engine.is_pistol_weapon("slugga")
	var is_assault = rules_engine.is_assault_weapon("slugga")
	assert_true(is_pistol, "slugga should be a Pistol weapon")
	assert_true(is_assault, "slugga should also be an Assault weapon")

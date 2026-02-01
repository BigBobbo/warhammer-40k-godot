extends "res://addons/gut/test.gd"

# Tests for the HEAVY keyword implementation
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k rules: Units with HEAVY weapons get +1 to hit if they
# remained stationary this turn.
#
# NOTE: RulesEngine.UNIT_WEAPONS doesn't include a unit with heavy weapons,
# so we test is_heavy_weapon() directly using weapon profiles.

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
# is_heavy_weapon() Tests
# Tests the actual RulesEngine.is_heavy_weapon() method
# ==========================================

func test_is_heavy_weapon_returns_true_for_heavy_bolter():
	"""Test that heavy_bolter is recognized as a Heavy weapon"""
	var result = rules_engine.is_heavy_weapon("heavy_bolter")
	assert_true(result, "heavy_bolter should be recognized as a Heavy weapon")

func test_is_heavy_weapon_returns_true_for_lascannon():
	"""Test that lascannon is recognized as a Heavy weapon"""
	var result = rules_engine.is_heavy_weapon("lascannon")
	assert_true(result, "lascannon should be recognized as a Heavy weapon")

func test_is_heavy_weapon_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT a Heavy weapon"""
	var result = rules_engine.is_heavy_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be recognized as a Heavy weapon")

func test_is_heavy_weapon_returns_false_for_shoota():
	"""Test that shoota (Assault weapon) is NOT a Heavy weapon"""
	var result = rules_engine.is_heavy_weapon("shoota")
	assert_false(result, "shoota should NOT be recognized as a Heavy weapon")

func test_is_heavy_weapon_returns_false_for_plasma_pistol():
	"""Test that plasma_pistol (Pistol weapon) is NOT a Heavy weapon"""
	var result = rules_engine.is_heavy_weapon("plasma_pistol")
	assert_false(result, "plasma_pistol should NOT be recognized as a Heavy weapon")

func test_is_heavy_weapon_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.is_heavy_weapon("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# Weapon Profile Tests
# Verify WEAPON_PROFILES are correctly configured
# ==========================================

func test_weapon_profile_heavy_bolter_has_heavy_keyword():
	"""Test that heavy_bolter profile contains HEAVY keyword"""
	var profile = rules_engine.get_weapon_profile("heavy_bolter")
	assert_false(profile.is_empty(), "Should find heavy_bolter profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "HEAVY", "Heavy Bolter should have HEAVY keyword")

func test_weapon_profile_lascannon_has_heavy_keyword():
	"""Test that lascannon profile contains HEAVY keyword"""
	var profile = rules_engine.get_weapon_profile("lascannon")
	assert_false(profile.is_empty(), "Should find lascannon profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "HEAVY", "Lascannon should have HEAVY keyword")

func test_weapon_profile_bolt_rifle_no_heavy_keyword():
	"""Test that bolt_rifle profile does NOT contain HEAVY keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "HEAVY", "Bolt rifle should NOT have HEAVY keyword")

# ==========================================
# unit_has_heavy_weapons() Tests
# NOTE: Currently no units in UNIT_WEAPONS have heavy weapons assigned
# ==========================================

func test_unit_has_no_heavy_weapons_intercessors():
	"""Test that Intercessors unit does NOT have Heavy weapons"""
	var result = rules_engine.unit_has_heavy_weapons("U_INTERCESSORS_A")
	assert_false(result, "Intercessors should NOT have Heavy weapons")

func test_unit_has_no_heavy_weapons_ork_boyz():
	"""Test that Ork Boyz unit does NOT have Heavy weapons"""
	var result = rules_engine.unit_has_heavy_weapons("U_BOYZ_A")
	assert_false(result, "Ork Boyz should NOT have Heavy weapons")

func test_unit_has_no_heavy_weapons_gretchin():
	"""Test that Gretchin unit does NOT have Heavy weapons"""
	var result = rules_engine.unit_has_heavy_weapons("U_GRETCHIN_A")
	assert_false(result, "Gretchin should NOT have Heavy weapons")

func test_unit_has_heavy_weapons_unknown_unit():
	"""Test that unknown unit returns false"""
	var result = rules_engine.unit_has_heavy_weapons("NONEXISTENT_UNIT")
	assert_false(result, "Unknown unit should return false")

# ==========================================
# get_unit_heavy_weapons() Tests
# ==========================================

func test_get_unit_heavy_weapons_intercessors_empty():
	"""Test that Intercessors have no heavy weapons"""
	var weapons = rules_engine.get_unit_heavy_weapons("U_INTERCESSORS_A")
	assert_true(weapons.is_empty(), "Intercessors should have no heavy weapons")

func test_get_unit_heavy_weapons_boyz_empty():
	"""Test that Ork Boyz have no heavy weapons"""
	var weapons = rules_engine.get_unit_heavy_weapons("U_BOYZ_A")
	assert_true(weapons.is_empty(), "Ork Boyz should have no heavy weapons")

# ==========================================
# Heavy vs Other Keywords Tests
# ==========================================

func test_heavy_and_assault_are_mutually_exclusive_in_profiles():
	"""Test that weapons don't have both HEAVY and ASSAULT keywords"""
	# Heavy bolter should be HEAVY but not ASSAULT
	var is_heavy = rules_engine.is_heavy_weapon("heavy_bolter")
	var is_assault = rules_engine.is_assault_weapon("heavy_bolter")
	assert_true(is_heavy, "Heavy bolter should be Heavy")
	assert_false(is_assault, "Heavy bolter should NOT be Assault")

	# Shoota should be ASSAULT but not HEAVY
	is_heavy = rules_engine.is_heavy_weapon("shoota")
	is_assault = rules_engine.is_assault_weapon("shoota")
	assert_false(is_heavy, "Shoota should NOT be Heavy")
	assert_true(is_assault, "Shoota should be Assault")

func test_heavy_and_pistol_are_mutually_exclusive_in_profiles():
	"""Test that weapons don't have both HEAVY and PISTOL keywords"""
	# Heavy bolter should be HEAVY but not PISTOL
	var is_heavy = rules_engine.is_heavy_weapon("heavy_bolter")
	var is_pistol = rules_engine.is_pistol_weapon("heavy_bolter")
	assert_true(is_heavy, "Heavy bolter should be Heavy")
	assert_false(is_pistol, "Heavy bolter should NOT be Pistol")

	# Plasma pistol should be PISTOL but not HEAVY
	is_heavy = rules_engine.is_heavy_weapon("plasma_pistol")
	is_pistol = rules_engine.is_pistol_weapon("plasma_pistol")
	assert_false(is_heavy, "Plasma pistol should NOT be Heavy")
	assert_true(is_pistol, "Plasma pistol should be Pistol")

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

func test_is_heavy_weapon_returns_true_for_bolt_rifle():
	"""11e: bolt rifle is Assault + Heavy"""
	var result = rules_engine.is_heavy_weapon("bolt_rifle")
	assert_true(result, "bolt_rifle should be recognized as a Heavy weapon in 11e")

func test_is_heavy_weapon_returns_false_for_lascannon():
	"""11e: lascannon lost the Heavy keyword"""
	var result = rules_engine.is_heavy_weapon("lascannon")
	assert_false(result, "lascannon should NOT be a Heavy weapon in 11e")

func test_is_heavy_weapon_returns_false_for_heavy_bolter():
	"""11e: heavy bolter is Assault + Sustained Hits 1, not Heavy"""
	var result = rules_engine.is_heavy_weapon("heavy_bolter")
	assert_false(result, "heavy_bolter should NOT be a Heavy weapon in 11e")

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

func test_weapon_profile_bolt_rifle_has_heavy_keyword():
	"""11e: bolt rifle profile contains HEAVY keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "HEAVY", "Bolt rifle should have HEAVY keyword in 11e")

func test_weapon_profile_lascannon_no_heavy_keyword():
	"""11e: lascannon profile has no weapon keywords"""
	var profile = rules_engine.get_weapon_profile("lascannon")
	assert_false(profile.is_empty(), "Should find lascannon profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "HEAVY", "Lascannon should NOT have HEAVY keyword in 11e")

func test_weapon_profile_heavy_bolter_no_heavy_keyword():
	"""11e: heavy bolter profile is Assault + Sustained Hits 1, not Heavy"""
	var profile = rules_engine.get_weapon_profile("heavy_bolter")
	assert_false(profile.is_empty(), "Should find heavy_bolter profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "HEAVY", "Heavy bolter should NOT have HEAVY keyword in 11e")

# ==========================================
# unit_has_heavy_weapons() Tests
# NOTE: Currently no units in UNIT_WEAPONS have heavy weapons assigned
# ==========================================

func test_unit_has_heavy_weapons_intercessors():
	"""11e: bolt rifles are Heavy, so Intercessors DO have Heavy weapons"""
	var result = rules_engine.unit_has_heavy_weapons("U_INTERCESSORS_A")
	assert_true(result, "Intercessors should have Heavy weapons in 11e (bolt rifle)")

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

func test_get_unit_heavy_weapons_intercessors():
	"""11e: Intercessor bolt rifles are Heavy"""
	var weapons = rules_engine.get_unit_heavy_weapons("U_INTERCESSORS_A")
	assert_false(weapons.is_empty(), "Intercessors should have heavy weapons in 11e")

func test_get_unit_heavy_weapons_boyz_empty():
	"""Test that Ork Boyz have no heavy weapons"""
	var weapons = rules_engine.get_unit_heavy_weapons("U_BOYZ_A")
	assert_true(weapons.is_empty(), "Ork Boyz should have no heavy weapons")

# ==========================================
# Heavy vs Other Keywords Tests
# ==========================================

func test_heavy_assault_combination_11e():
	"""11e allows Assault + Heavy on one weapon (bolt rifle); heavy bolter is Assault-only"""
	# Bolt rifle carries BOTH keywords in 11e
	var is_heavy = rules_engine.is_heavy_weapon("bolt_rifle")
	var is_assault = rules_engine.is_assault_weapon("bolt_rifle")
	assert_true(is_heavy, "Bolt rifle should be Heavy in 11e")
	assert_true(is_assault, "Bolt rifle should be Assault in 11e")

	# Heavy bolter is Assault (+ Sustained Hits 1) but not Heavy
	is_heavy = rules_engine.is_heavy_weapon("heavy_bolter")
	is_assault = rules_engine.is_assault_weapon("heavy_bolter")
	assert_false(is_heavy, "Heavy bolter should NOT be Heavy in 11e")
	assert_true(is_assault, "Heavy bolter should be Assault in 11e")

func test_heavy_and_pistol_are_mutually_exclusive_in_profiles():
	"""Heavy and Pistol don't mix on the same profile (bolt rifle vs plasma pistol)"""
	# Bolt rifle is Heavy but not Pistol
	var is_heavy = rules_engine.is_heavy_weapon("bolt_rifle")
	var is_pistol = rules_engine.is_pistol_weapon("bolt_rifle")
	assert_true(is_heavy, "Bolt rifle should be Heavy in 11e")
	assert_false(is_pistol, "Bolt rifle should NOT be Pistol")

	# Plasma pistol should be PISTOL but not HEAVY
	is_heavy = rules_engine.is_heavy_weapon("plasma_pistol")
	is_pistol = rules_engine.is_pistol_weapon("plasma_pistol")
	assert_false(is_heavy, "Plasma pistol should NOT be Heavy")
	assert_true(is_pistol, "Plasma pistol should be Pistol")

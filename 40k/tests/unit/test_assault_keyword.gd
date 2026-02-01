extends "res://addons/gut/test.gd"

# Tests for the ASSAULT keyword implementation
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k rules: Units with ASSAULT weapons can shoot after Advancing,
# but with a -1 penalty to hit rolls.

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
# is_assault_weapon() Tests
# Tests the actual RulesEngine.is_assault_weapon() method
# ==========================================

func test_is_assault_weapon_returns_true_for_shoota():
	"""Test that shoota is recognized as an Assault weapon"""
	var result = rules_engine.is_assault_weapon("shoota")
	assert_true(result, "shoota should be recognized as an Assault weapon")

func test_is_assault_weapon_returns_true_for_slugga():
	"""Test that slugga is recognized as an Assault weapon (has both PISTOL and ASSAULT)"""
	var result = rules_engine.is_assault_weapon("slugga")
	assert_true(result, "slugga should be recognized as an Assault weapon")

func test_is_assault_weapon_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT an Assault weapon"""
	var result = rules_engine.is_assault_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be recognized as an Assault weapon")

func test_is_assault_weapon_returns_false_for_grot_blasta():
	"""Test that grot_blasta is NOT an Assault weapon"""
	var result = rules_engine.is_assault_weapon("grot_blasta")
	assert_false(result, "grot_blasta should NOT be recognized as an Assault weapon")

func test_is_assault_weapon_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.is_assault_weapon("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# is_pistol_weapon() Tests (for weapons with multiple keywords)
# ==========================================

func test_slugga_has_both_pistol_and_assault():
	"""Test that slugga has both PISTOL and ASSAULT keywords"""
	var is_pistol = rules_engine.is_pistol_weapon("slugga")
	var is_assault = rules_engine.is_assault_weapon("slugga")
	assert_true(is_pistol, "slugga should be a Pistol weapon")
	assert_true(is_assault, "slugga should also be an Assault weapon")

func test_shoota_has_only_assault():
	"""Test that shoota has only ASSAULT keyword (not PISTOL)"""
	var is_pistol = rules_engine.is_pistol_weapon("shoota")
	var is_assault = rules_engine.is_assault_weapon("shoota")
	assert_false(is_pistol, "shoota should NOT be a Pistol weapon")
	assert_true(is_assault, "shoota should be an Assault weapon")

# ==========================================
# unit_has_assault_weapons() Tests
# Tests the actual RulesEngine.unit_has_assault_weapons() method
# ==========================================

func test_unit_has_assault_weapons_ork_boyz():
	"""Test that Ork Boyz unit has Assault weapons (slugga and shoota)"""
	var result = rules_engine.unit_has_assault_weapons("U_BOYZ_A")
	assert_true(result, "Ork Boyz (U_BOYZ_A) should have Assault weapons")

func test_unit_has_no_assault_weapons_intercessors():
	"""Test that Intercessors unit does NOT have Assault weapons (only bolt_rifle)"""
	var result = rules_engine.unit_has_assault_weapons("U_INTERCESSORS_A")
	assert_false(result, "Intercessors should NOT have Assault weapons (bolt_rifle is not Assault)")

func test_unit_has_no_assault_weapons_gretchin():
	"""Test that Gretchin unit does NOT have Assault weapons"""
	var result = rules_engine.unit_has_assault_weapons("U_GRETCHIN_A")
	assert_false(result, "Gretchin should NOT have Assault weapons")

func test_unit_has_assault_weapons_unknown_unit():
	"""Test that unknown unit returns false"""
	var result = rules_engine.unit_has_assault_weapons("NONEXISTENT_UNIT")
	assert_false(result, "Unknown unit should return false")

# ==========================================
# get_unit_assault_weapons() Tests
# ==========================================

func test_get_unit_assault_weapons_ork_boyz():
	"""Test that we can get the assault weapons for Ork Boyz"""
	var weapons = rules_engine.get_unit_assault_weapons("U_BOYZ_A")
	assert_false(weapons.is_empty(), "Ork Boyz should have assault weapons")
	# The weapons should include shoota and slugga
	var has_assault_weapon = false
	for model_id in weapons:
		for weapon_id in weapons[model_id]:
			if weapon_id == "shoota" or weapon_id == "slugga":
				has_assault_weapon = true
				break
	assert_true(has_assault_weapon, "Should find shoota or slugga in assault weapons")

func test_get_unit_assault_weapons_intercessors_empty():
	"""Test that Intercessors have no assault weapons"""
	var weapons = rules_engine.get_unit_assault_weapons("U_INTERCESSORS_A")
	assert_true(weapons.is_empty(), "Intercessors should have no assault weapons")

# ==========================================
# Weapon Profile Tests
# Verify WEAPON_PROFILES are correctly configured
# ==========================================

func test_weapon_profile_shoota_has_assault_keyword():
	"""Test that shoota profile contains ASSAULT keyword"""
	var profile = rules_engine.get_weapon_profile("shoota")
	assert_false(profile.is_empty(), "Should find shoota profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "ASSAULT", "Shoota should have ASSAULT keyword")

func test_weapon_profile_bolt_rifle_no_assault_keyword():
	"""Test that bolt_rifle profile does NOT contain ASSAULT keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "ASSAULT", "Bolt rifle should NOT have ASSAULT keyword")

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

func test_is_assault_weapon_returns_true_for_bolt_rifle():
	"""11e: bolt rifle is Assault + Heavy"""
	var result = rules_engine.is_assault_weapon("bolt_rifle")
	assert_true(result, "bolt_rifle should be recognized as an Assault weapon in 11e")

func test_is_assault_weapon_returns_false_for_slugga():
	"""11e: slugga is Pistol-only (10e's extra Assault keyword dropped)"""
	var result = rules_engine.is_assault_weapon("slugga")
	assert_false(result, "slugga should NOT be an Assault weapon in 11e")

func test_is_assault_weapon_returns_false_for_shoota():
	"""11e: shoota is Rapid Fire 1, no longer Assault"""
	var result = rules_engine.is_assault_weapon("shoota")
	assert_false(result, "shoota should NOT be an Assault weapon in 11e")

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

func test_slugga_is_pistol_only():
	"""11e: slugga is a Pistol without the 10e Assault keyword"""
	var is_pistol = rules_engine.is_pistol_weapon("slugga")
	var is_assault = rules_engine.is_assault_weapon("slugga")
	assert_true(is_pistol, "slugga should be a Pistol weapon")
	assert_false(is_assault, "slugga should NOT be an Assault weapon in 11e")

func test_bolt_rifle_assault_not_pistol():
	"""11e: bolt rifle is Assault (+Heavy) but not a Pistol"""
	var is_pistol = rules_engine.is_pistol_weapon("bolt_rifle")
	var is_assault = rules_engine.is_assault_weapon("bolt_rifle")
	assert_false(is_pistol, "bolt_rifle should NOT be a Pistol weapon")
	assert_true(is_assault, "bolt_rifle should be an Assault weapon in 11e")

# ==========================================
# unit_has_assault_weapons() Tests
# Tests the actual RulesEngine.unit_has_assault_weapons() method
# ==========================================

func test_unit_has_no_assault_weapons_ork_boyz():
	"""11e: boyz sluggas/shootas are Pistol / Rapid Fire — no Assault weapons"""
	var result = rules_engine.unit_has_assault_weapons("U_BOYZ_A")
	assert_false(result, "Ork Boyz (U_BOYZ_A) should NOT have Assault weapons in 11e")

func test_unit_has_assault_weapons_intercessors():
	"""11e: bolt rifles are Assault, so Intercessors have Assault weapons"""
	var result = rules_engine.unit_has_assault_weapons("U_INTERCESSORS_A")
	assert_true(result, "Intercessors should have Assault weapons in 11e (bolt rifle)")

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

func test_get_unit_assault_weapons_intercessors():
	"""11e: Intercessor bolt rifles are the placeholder Assault exemplar"""
	var weapons = rules_engine.get_unit_assault_weapons("U_INTERCESSORS_A")
	assert_false(weapons.is_empty(), "Intercessors should have assault weapons")
	var has_assault_weapon = false
	for model_id in weapons:
		for weapon_id in weapons[model_id]:
			if weapon_id == "bolt_rifle":
				has_assault_weapon = true
				break
	assert_true(has_assault_weapon, "Should find bolt_rifle in assault weapons")

func test_get_unit_assault_weapons_boyz_empty():
	"""11e: Boyz have no Assault weapons (Pistol slugga, Rapid Fire shoota)"""
	var weapons = rules_engine.get_unit_assault_weapons("U_BOYZ_A")
	assert_true(weapons.is_empty(), "Boyz should have no assault weapons in 11e")

# ==========================================
# Weapon Profile Tests
# Verify WEAPON_PROFILES are correctly configured
# ==========================================

func test_weapon_profile_bolt_rifle_has_assault_keyword():
	"""11e: bolt rifle profile contains ASSAULT keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "ASSAULT", "Bolt rifle should have ASSAULT keyword in 11e")

func test_weapon_profile_shoota_no_assault_keyword():
	"""11e: shoota profile does NOT contain ASSAULT (it is Rapid Fire 1)"""
	var profile = rules_engine.get_weapon_profile("shoota")
	assert_false(profile.is_empty(), "Should find shoota profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "ASSAULT", "Shoota should NOT have ASSAULT keyword in 11e")

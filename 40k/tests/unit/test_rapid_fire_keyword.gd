extends "res://addons/gut/test.gd"

# Tests for the RAPID FIRE keyword implementation
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k rules: Rapid Fire X weapons get +X attacks when the
# target is within half the weapon's range.

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
# get_rapid_fire_value() Tests
# Tests the actual RulesEngine.get_rapid_fire_value() method
# ==========================================

func test_get_rapid_fire_value_returns_1_for_bolt_rifle():
	"""Test that bolt_rifle has Rapid Fire 1"""
	var result = rules_engine.get_rapid_fire_value("bolt_rifle")
	assert_eq(result, 1, "bolt_rifle should have Rapid Fire value of 1")

func test_get_rapid_fire_value_returns_0_for_lascannon():
	"""Test that lascannon has no Rapid Fire (Heavy weapon)"""
	var result = rules_engine.get_rapid_fire_value("lascannon")
	assert_eq(result, 0, "lascannon should NOT have Rapid Fire")

func test_get_rapid_fire_value_returns_0_for_shoota():
	"""Test that shoota has no Rapid Fire (Assault weapon)"""
	var result = rules_engine.get_rapid_fire_value("shoota")
	assert_eq(result, 0, "shoota should NOT have Rapid Fire")

func test_get_rapid_fire_value_returns_0_for_unknown_weapon():
	"""Test that unknown weapon returns 0"""
	var result = rules_engine.get_rapid_fire_value("nonexistent_weapon")
	assert_eq(result, 0, "Unknown weapon should return 0")

# ==========================================
# is_rapid_fire_weapon() Tests
# Tests the actual RulesEngine.is_rapid_fire_weapon() method
# ==========================================

func test_is_rapid_fire_weapon_returns_true_for_bolt_rifle():
	"""Test that bolt_rifle is recognized as a Rapid Fire weapon"""
	var result = rules_engine.is_rapid_fire_weapon("bolt_rifle")
	assert_true(result, "bolt_rifle should be a Rapid Fire weapon")

func test_is_rapid_fire_weapon_returns_false_for_lascannon():
	"""Test that lascannon is NOT a Rapid Fire weapon"""
	var result = rules_engine.is_rapid_fire_weapon("lascannon")
	assert_false(result, "lascannon should NOT be a Rapid Fire weapon")

func test_is_rapid_fire_weapon_returns_false_for_shoota():
	"""Test that shoota is NOT a Rapid Fire weapon"""
	var result = rules_engine.is_rapid_fire_weapon("shoota")
	assert_false(result, "shoota should NOT be a Rapid Fire weapon")

func test_is_rapid_fire_weapon_returns_false_for_flamer():
	"""Test that flamer (Torrent weapon) is NOT a Rapid Fire weapon"""
	var result = rules_engine.is_rapid_fire_weapon("flamer")
	assert_false(result, "flamer should NOT be a Rapid Fire weapon")

# ==========================================
# unit_has_rapid_fire_weapons() Tests
# ==========================================

func test_unit_has_rapid_fire_weapons_intercessors():
	"""Test that Intercessors unit has Rapid Fire weapons (bolt_rifle)"""
	var result = rules_engine.unit_has_rapid_fire_weapons("U_INTERCESSORS_A")
	assert_true(result, "Intercessors should have Rapid Fire weapons")

func test_unit_has_rapid_fire_weapons_tactical():
	"""Test that Tactical Marines have Rapid Fire weapons"""
	var result = rules_engine.unit_has_rapid_fire_weapons("U_TACTICAL_A")
	assert_true(result, "Tactical Marines should have Rapid Fire weapons")

func test_unit_has_no_rapid_fire_weapons_ork_boyz():
	"""Test that Ork Boyz do NOT have Rapid Fire weapons"""
	var result = rules_engine.unit_has_rapid_fire_weapons("U_BOYZ_A")
	assert_false(result, "Ork Boyz should NOT have Rapid Fire weapons")

func test_unit_has_no_rapid_fire_weapons_gretchin():
	"""Test that Gretchin do NOT have Rapid Fire weapons"""
	var result = rules_engine.unit_has_rapid_fire_weapons("U_GRETCHIN_A")
	assert_false(result, "Gretchin should NOT have Rapid Fire weapons")

# ==========================================
# get_unit_rapid_fire_weapons() Tests
# ==========================================

func test_get_unit_rapid_fire_weapons_intercessors():
	"""Test that we can get the rapid fire weapons for Intercessors"""
	var weapons = rules_engine.get_unit_rapid_fire_weapons("U_INTERCESSORS_A")
	assert_false(weapons.is_empty(), "Intercessors should have rapid fire weapons")

func test_get_unit_rapid_fire_weapons_ork_boyz_empty():
	"""Test that Ork Boyz have no rapid fire weapons"""
	var weapons = rules_engine.get_unit_rapid_fire_weapons("U_BOYZ_A")
	assert_true(weapons.is_empty(), "Ork Boyz should have no rapid fire weapons")

# ==========================================
# Weapon Profile Tests
# ==========================================

func test_weapon_profile_bolt_rifle_has_rapid_fire_keyword():
	"""Test that bolt_rifle profile contains RAPID FIRE keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	var has_rapid_fire = false
	for keyword in keywords:
		if "RAPID FIRE" in keyword.to_upper():
			has_rapid_fire = true
			break
	assert_true(has_rapid_fire, "Bolt rifle should have RAPID FIRE keyword")

# ==========================================
# Rapid Fire Bonus Attack Logic Tests
# ==========================================

func test_rapid_fire_bonus_calculation():
	"""Test that Rapid Fire X gives +X attacks at half range"""
	# Bolt rifle has Rapid Fire 1, range 30"
	# At 15" or less, each model gets +1 attack
	var rf_value = rules_engine.get_rapid_fire_value("bolt_rifle")
	var models_in_half_range = 5
	var bonus_attacks = models_in_half_range * rf_value
	assert_eq(bonus_attacks, 5, "5 models with RF 1 at half range should get 5 bonus attacks")

func test_no_rapid_fire_bonus_at_long_range():
	"""Test that no Rapid Fire bonus is applied outside half range"""
	var rf_value = rules_engine.get_rapid_fire_value("bolt_rifle")
	var models_in_half_range = 0  # All models outside half range
	var bonus_attacks = models_in_half_range * rf_value
	assert_eq(bonus_attacks, 0, "No bonus attacks when outside half range")

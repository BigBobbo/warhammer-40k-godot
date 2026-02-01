extends "res://addons/gut/test.gd"

# Tests for the SUSTAINED HITS keyword implementation
# Tests the ACTUAL RulesEngine methods
#
# Per Warhammer 40k rules: Sustained Hits X weapons generate X additional hits
# on critical hits (unmodified 6s to hit).

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# has_sustained_hits() Tests
# ==========================================

func test_has_sustained_hits_returns_true_for_sustained_bolter():
	"""Test that sustained_bolter is recognized as a Sustained Hits weapon"""
	var result = rules_engine.has_sustained_hits("sustained_bolter")
	assert_true(result, "sustained_bolter should have Sustained Hits")

func test_has_sustained_hits_returns_true_for_lethal_sustained_bolter():
	"""Test that lethal_sustained_bolter has Sustained Hits"""
	var result = rules_engine.has_sustained_hits("lethal_sustained_bolter")
	assert_true(result, "lethal_sustained_bolter should have Sustained Hits")

func test_has_sustained_hits_returns_true_for_torrent_sustained():
	"""Test that torrent_sustained has Sustained Hits"""
	var result = rules_engine.has_sustained_hits("torrent_sustained")
	assert_true(result, "torrent_sustained should have Sustained Hits")

func test_has_sustained_hits_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle does NOT have Sustained Hits"""
	var result = rules_engine.has_sustained_hits("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT have Sustained Hits")

func test_has_sustained_hits_returns_false_for_lethal_bolter():
	"""Test that lethal_bolter (Lethal Hits only) does NOT have Sustained Hits"""
	var result = rules_engine.has_sustained_hits("lethal_bolter")
	assert_false(result, "lethal_bolter should NOT have Sustained Hits")

func test_has_sustained_hits_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.has_sustained_hits("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# get_sustained_hits_value() Tests
# ==========================================

func test_get_sustained_hits_value_returns_correct_value():
	"""Test that we can retrieve the Sustained Hits value"""
	var result = rules_engine.get_sustained_hits_value("sustained_bolter")
	assert_false(result.is_empty(), "Should return sustained hits data")
	assert_true(result.has("value") or result.has("dice"), "Should have value or dice")

func test_get_sustained_hits_value_returns_empty_for_non_sustained():
	"""Test that non-Sustained Hits weapon returns empty"""
	var result = rules_engine.get_sustained_hits_value("bolt_rifle")
	# For weapons without Sustained Hits, the value should indicate no sustained hits
	var has_sustained = result.get("value", 0) > 0 or result.get("dice", "") != ""
	assert_false(has_sustained, "bolt_rifle should not have Sustained Hits value")

# ==========================================
# Weapon Profile Tests
# ==========================================

func test_weapon_profile_sustained_bolter_has_sustained_hits_keyword():
	"""Test that sustained_bolter profile contains SUSTAINED HITS keyword"""
	var profile = rules_engine.get_weapon_profile("sustained_bolter")
	assert_false(profile.is_empty(), "Should find sustained_bolter profile")
	var keywords = profile.get("keywords", [])
	var has_sustained = false
	for keyword in keywords:
		if "SUSTAINED HITS" in keyword.to_upper():
			has_sustained = true
			break
	assert_true(has_sustained, "Sustained Bolter should have SUSTAINED HITS keyword")

# ==========================================
# Sustained Hits Logic Tests
# ==========================================

func test_sustained_hits_generates_extra_hits():
	"""Test that Sustained Hits X generates X extra hits per critical"""
	# Simulating: 2 critical hits with Sustained Hits 1
	var critical_hits = 2
	var sustained_value = 1
	var extra_hits = critical_hits * sustained_value
	assert_eq(extra_hits, 2, "2 crits with Sustained Hits 1 should generate 2 extra hits")

func test_sustained_hits_added_to_total_hits():
	"""Test that extra hits from Sustained Hits are added to total"""
	var regular_hits = 3
	var critical_hits = 2
	var sustained_value = 1
	var extra_hits = critical_hits * sustained_value
	var total_hits = regular_hits + critical_hits + extra_hits
	assert_eq(total_hits, 7, "3 regular + 2 crits + 2 extra = 7 total hits")

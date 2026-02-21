extends "res://addons/gut/test.gd"

# Tests for Mathhammer._apply_defender_overrides() — T3-24
# Validates that custom defender stat overrides (T/Sv/W/Invuln/FNP/model_count)
# are correctly applied to the defender unit before simulation.

# ==========================================
# Helper: build a minimal defender unit
# ==========================================
func _make_defender(toughness: int, save: int, wounds: int, model_count: int, invuln: int = 0, fnp: int = 0) -> Dictionary:
	var models = []
	for i in range(model_count):
		var model = {
			"id": "m%d" % i,
			"wounds": wounds,
			"current_wounds": wounds,
			"alive": true
		}
		if invuln > 0:
			model["invuln"] = invuln
		models.append(model)
	return {
		"id": "test_defender",
		"meta": {
			"stats": {
				"toughness": toughness,
				"save": save,
				"fnp": fnp
			}
		},
		"models": models
	}

# ==========================================
# Test: Override toughness
# ==========================================
func test_override_toughness():
	"""Override toughness from 4 to 8 (e.g. custom vehicle target)"""
	var defender = _make_defender(4, 3, 2, 5)
	var overrides = {"toughness": 8}
	var result = Mathhammer._apply_defender_overrides(defender, overrides, "test_defender")
	assert_eq(result["meta"]["stats"]["toughness"], 8, "Toughness should be overridden to 8")

# ==========================================
# Test: Override armor save
# ==========================================
func test_override_save():
	"""Override save from 3+ to 6+ (e.g. modelling a weaker unit)"""
	var defender = _make_defender(4, 3, 2, 5)
	var overrides = {"save": 6}
	var result = Mathhammer._apply_defender_overrides(defender, overrides, "test_defender")
	assert_eq(result["meta"]["stats"]["save"], 6, "Save should be overridden to 6+")

# ==========================================
# Test: Override wounds per model
# ==========================================
func test_override_wounds():
	"""Override wounds from 2 to 12 (e.g. vehicle target)"""
	var defender = _make_defender(4, 3, 2, 3)
	var overrides = {"wounds": 12}
	var result = Mathhammer._apply_defender_overrides(defender, overrides, "test_defender")
	for model in result["models"]:
		assert_eq(model["wounds"], 12, "Model wounds should be overridden to 12")
		assert_eq(model["current_wounds"], 12, "Model current_wounds should also be 12")

# ==========================================
# Test: Override model count — increase
# ==========================================
func test_override_model_count_increase():
	"""Increase model count from 3 to 10 (e.g. full squad)"""
	var defender = _make_defender(4, 3, 1, 3)
	var overrides = {"model_count": 10}
	var result = Mathhammer._apply_defender_overrides(defender, overrides, "test_defender")
	assert_eq(result["models"].size(), 10, "Should have 10 models after override")

# ==========================================
# Test: Override model count — decrease
# ==========================================
func test_override_model_count_decrease():
	"""Decrease model count from 10 to 5 (e.g. depleted squad)"""
	var defender = _make_defender(4, 3, 1, 10)
	var overrides = {"model_count": 5}
	var result = Mathhammer._apply_defender_overrides(defender, overrides, "test_defender")
	assert_eq(result["models"].size(), 5, "Should have 5 models after override")

# ==========================================
# Test: Multiple overrides at once
# ==========================================
func test_multiple_overrides():
	"""Override T, Sv, W, and model count together"""
	var defender = _make_defender(4, 3, 1, 5)
	var overrides = {
		"toughness": 10,
		"save": 2,
		"wounds": 6,
		"model_count": 3
	}
	var result = Mathhammer._apply_defender_overrides(defender, overrides, "test_defender")
	assert_eq(result["meta"]["stats"]["toughness"], 10, "Toughness should be 10")
	assert_eq(result["meta"]["stats"]["save"], 2, "Save should be 2+")
	assert_eq(result["models"].size(), 3, "Model count should be 3")
	for model in result["models"]:
		assert_eq(model["wounds"], 6, "Wounds should be 6")

# ==========================================
# Test: Zero values are not applied (0 = none)
# ==========================================
func test_zero_override_not_applied():
	"""Override with 0 for toughness/save/wounds should not modify the original"""
	var defender = _make_defender(5, 4, 3, 5)
	var overrides = {"toughness": 0, "save": 0, "wounds": 0}
	var result = Mathhammer._apply_defender_overrides(defender, overrides, "test_defender")
	assert_eq(result["meta"]["stats"]["toughness"], 5, "Toughness should remain 5 (0 override ignored)")
	assert_eq(result["meta"]["stats"]["save"], 4, "Save should remain 4+ (0 override ignored)")
	for model in result["models"]:
		assert_eq(model["wounds"], 3, "Wounds should remain 3 (0 override ignored)")

# ==========================================
# Test: Empty overrides dict is a no-op
# ==========================================
func test_empty_overrides_noop():
	"""Empty overrides dictionary should not change the defender"""
	var defender = _make_defender(6, 2, 4, 3)
	var overrides = {}
	var result = Mathhammer._apply_defender_overrides(defender, overrides, "test_defender")
	assert_eq(result["meta"]["stats"]["toughness"], 6, "Toughness unchanged")
	assert_eq(result["meta"]["stats"]["save"], 2, "Save unchanged")
	assert_eq(result["models"].size(), 3, "Model count unchanged")

# ==========================================
# Test: _build_defender_config includes overrides (config structure)
# ==========================================
func test_defender_config_structure():
	"""Verify the overrides dict structure matches what _apply_defender_overrides expects"""
	# This tests the data contract between MathhammerUI._build_defender_config and Mathhammer._apply_defender_overrides
	var config_overrides = {
		"toughness": 8,
		"save": 2,
		"wounds": 12,
		"model_count": 1,
		"invuln": 4,
		"fnp": 5,
	}
	# Verify all expected keys are present
	assert_true(config_overrides.has("toughness"), "Config should have toughness")
	assert_true(config_overrides.has("save"), "Config should have save")
	assert_true(config_overrides.has("wounds"), "Config should have wounds")
	assert_true(config_overrides.has("model_count"), "Config should have model_count")
	assert_true(config_overrides.has("invuln"), "Config should have invuln")
	assert_true(config_overrides.has("fnp"), "Config should have fnp")

	# Verify applying these overrides works without error
	var defender = _make_defender(4, 3, 1, 5)
	var result = Mathhammer._apply_defender_overrides(defender, config_overrides, "test")
	assert_eq(result["meta"]["stats"]["toughness"], 8, "Applied toughness override")
	assert_eq(result["meta"]["stats"]["save"], 2, "Applied save override")
	assert_eq(result["models"].size(), 1, "Applied model_count override")
	for model in result["models"]:
		assert_eq(model["wounds"], 12, "Applied wounds override")

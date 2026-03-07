extends "res://addons/gut/test.gd"

# Tests for MA-6: get_unit_weapons() per-model profile support
#
# Validates that:
# 1. Units with model_profiles assign per-model weapons based on model_type
# 2. Units without model_profiles still assign all weapons to all models (regression)
# 3. Attached character weapons still use composite IDs
# 4. Dead models are excluded from weapon assignment

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# Helper to build a board with units
func _make_board(units: Dictionary) -> Dictionary:
	return {"units": units}

# ==========================================
# Per-model profile tests (Lootas-like unit)
# ==========================================

func _make_lootas_unit() -> Dictionary:
	return {
		"id": "U_LOOTAS",
		"meta": {
			"name": "Lootas",
			"weapons": [
				{"name": "Deffgun", "type": "Ranged", "range": "48", "attacks": "2", "strength": "8", "ap": "-1", "damage": "2"},
				{"name": "Kustom mega-blasta", "type": "Ranged", "range": "24", "attacks": "3", "strength": "9", "ap": "-2", "damage": "D6"},
				{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2", "strength": "4", "ap": "0", "damage": "1"}
			],
			"model_profiles": {
				"loota_deffgun": {
					"label": "Loota (Deffgun)",
					"weapons": ["Deffgun", "Close combat weapon"]
				},
				"loota_kmb": {
					"label": "Loota (Kustom Mega-blasta)",
					"weapons": ["Kustom mega-blasta", "Close combat weapon"]
				},
				"spanner": {
					"label": "Spanner",
					"weapons": ["Kustom mega-blasta", "Close combat weapon"]
				}
			}
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_deffgun"},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_deffgun"},
			{"id": "m3", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_kmb"},
			{"id": "m4", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "spanner"},
			{"id": "m5", "wounds": 1, "current_wounds": 1, "alive": false, "model_type": "loota_deffgun"}
		]
	}

func test_deffgun_models_get_only_deffgun():
	"""Deffgun models should only get the deffgun ranged weapon."""
	var unit = _make_lootas_unit()
	var board = _make_board({"U_LOOTAS": unit})
	var result = RulesEngine.get_unit_weapons("U_LOOTAS", board)

	var deffgun_id = RulesEngine._generate_weapon_id("Deffgun", "Ranged")
	var kmb_id = RulesEngine._generate_weapon_id("Kustom mega-blasta", "Ranged")

	# m1 is loota_deffgun - should have deffgun only
	assert_true(result.has("m1"), "m1 should be in results")
	assert_true(deffgun_id in result["m1"], "m1 (deffgun model) should have deffgun weapon")
	assert_false(kmb_id in result["m1"], "m1 (deffgun model) should NOT have kustom mega-blasta")

func test_kmb_models_get_only_kmb():
	"""KMB models should only get the kustom mega-blasta ranged weapon."""
	var unit = _make_lootas_unit()
	var board = _make_board({"U_LOOTAS": unit})
	var result = RulesEngine.get_unit_weapons("U_LOOTAS", board)

	var deffgun_id = RulesEngine._generate_weapon_id("Deffgun", "Ranged")
	var kmb_id = RulesEngine._generate_weapon_id("Kustom mega-blasta", "Ranged")

	# m3 is loota_kmb - should have KMB only
	assert_true(result.has("m3"), "m3 should be in results")
	assert_true(kmb_id in result["m3"], "m3 (kmb model) should have kustom mega-blasta")
	assert_false(deffgun_id in result["m3"], "m3 (kmb model) should NOT have deffgun")

func test_spanner_gets_kmb():
	"""Spanner model should get kustom mega-blasta (per profile)."""
	var unit = _make_lootas_unit()
	var board = _make_board({"U_LOOTAS": unit})
	var result = RulesEngine.get_unit_weapons("U_LOOTAS", board)

	var deffgun_id = RulesEngine._generate_weapon_id("Deffgun", "Ranged")
	var kmb_id = RulesEngine._generate_weapon_id("Kustom mega-blasta", "Ranged")

	# m4 is spanner - should have KMB only
	assert_true(result.has("m4"), "m4 should be in results")
	assert_true(kmb_id in result["m4"], "m4 (spanner) should have kustom mega-blasta")
	assert_false(deffgun_id in result["m4"], "m4 (spanner) should NOT have deffgun")

func test_dead_models_excluded():
	"""Dead models should not appear in weapon assignments."""
	var unit = _make_lootas_unit()
	var board = _make_board({"U_LOOTAS": unit})
	var result = RulesEngine.get_unit_weapons("U_LOOTAS", board)

	# m5 is dead - should not be in results
	assert_false(result.has("m5"), "Dead model m5 should NOT be in results")

func test_melee_weapons_excluded():
	"""Melee weapons should not appear in get_unit_weapons results (ranged only)."""
	var unit = _make_lootas_unit()
	var board = _make_board({"U_LOOTAS": unit})
	var result = RulesEngine.get_unit_weapons("U_LOOTAS", board)

	var ccw_id = RulesEngine._generate_weapon_id("Close combat weapon", "Melee")

	# No model should have close combat weapon (it's Melee, not Ranged)
	for model_id in result:
		assert_false(ccw_id in result[model_id], "Model %s should not have melee weapon in ranged results" % model_id)

# ==========================================
# Fallback/regression tests (no model_profiles)
# ==========================================

func _make_basic_unit() -> Dictionary:
	return {
		"id": "U_BASIC",
		"meta": {
			"name": "Basic Squad",
			"weapons": [
				{"name": "Bolt rifle", "type": "Ranged", "range": "30", "attacks": "2", "strength": "4", "ap": "-1", "damage": "1"},
				{"name": "Bolt pistol", "type": "Ranged", "range": "12", "attacks": "1", "strength": "4", "ap": "0", "damage": "1"},
				{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "3", "strength": "4", "ap": "0", "damage": "1"}
			]
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "alive": true},
			{"id": "m2", "wounds": 2, "current_wounds": 2, "alive": true},
			{"id": "m3", "wounds": 2, "current_wounds": 2, "alive": true}
		]
	}

func test_no_profiles_all_models_get_all_ranged_weapons():
	"""Without model_profiles, all alive models should get all ranged weapons."""
	var unit = _make_basic_unit()
	var board = _make_board({"U_BASIC": unit})
	var result = RulesEngine.get_unit_weapons("U_BASIC", board)

	var bolt_rifle_id = RulesEngine._generate_weapon_id("Bolt rifle", "Ranged")
	var bolt_pistol_id = RulesEngine._generate_weapon_id("Bolt pistol", "Ranged")

	assert_eq(result.size(), 3, "All 3 alive models should have weapon entries")
	for model_id in result:
		assert_true(bolt_rifle_id in result[model_id], "Model %s should have bolt rifle" % model_id)
		assert_true(bolt_pistol_id in result[model_id], "Model %s should have bolt pistol" % model_id)

func test_no_profiles_melee_excluded():
	"""Without model_profiles, melee weapons should still be excluded."""
	var unit = _make_basic_unit()
	var board = _make_board({"U_BASIC": unit})
	var result = RulesEngine.get_unit_weapons("U_BASIC", board)

	var ccw_id = RulesEngine._generate_weapon_id("Close combat weapon", "Melee")
	for model_id in result:
		assert_false(ccw_id in result[model_id], "Model %s should not have melee weapon" % model_id)

# ==========================================
# model_profiles exists but model has no model_type (fallback)
# ==========================================

func test_model_without_type_falls_back_to_all_weapons():
	"""A model with no model_type in a unit that has model_profiles should get all ranged weapons."""
	var unit = {
		"id": "U_MIXED",
		"meta": {
			"name": "Mixed Unit",
			"weapons": [
				{"name": "WeaponA", "type": "Ranged", "range": "24", "attacks": "1", "strength": "4", "ap": "0", "damage": "1"},
				{"name": "WeaponB", "type": "Ranged", "range": "24", "attacks": "2", "strength": "5", "ap": "-1", "damage": "1"}
			],
			"model_profiles": {
				"type_a": {"label": "Type A", "weapons": ["WeaponA"]}
			}
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "type_a"},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true}
		]
	}
	var board = _make_board({"U_MIXED": unit})
	var result = RulesEngine.get_unit_weapons("U_MIXED", board)

	var wa_id = RulesEngine._generate_weapon_id("WeaponA", "Ranged")
	var wb_id = RulesEngine._generate_weapon_id("WeaponB", "Ranged")

	# m1 has type_a profile - should only have WeaponA
	assert_true(wa_id in result["m1"], "m1 (type_a) should have WeaponA")
	assert_false(wb_id in result["m1"], "m1 (type_a) should NOT have WeaponB")

	# m2 has no model_type - should get all weapons (fallback)
	assert_true(wa_id in result["m2"], "m2 (no type) should have WeaponA")
	assert_true(wb_id in result["m2"], "m2 (no type) should have WeaponB")

# ==========================================
# Attached character tests
# ==========================================

func test_attached_character_uses_composite_ids():
	"""Attached character weapons should use composite IDs (char_id:model_id)."""
	var main_unit = {
		"id": "U_MAIN",
		"meta": {
			"name": "Main Squad",
			"weapons": [
				{"name": "Bolt rifle", "type": "Ranged", "range": "30", "attacks": "2", "strength": "4", "ap": "-1", "damage": "1"}
			]
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "alive": true}
		],
		"attachment_data": {
			"attached_characters": ["U_CHAR"]
		}
	}
	var char_unit = {
		"id": "U_CHAR",
		"meta": {
			"name": "Character",
			"weapons": [
				{"name": "Storm bolter", "type": "Ranged", "range": "24", "attacks": "2", "strength": "4", "ap": "0", "damage": "1"}
			]
		},
		"models": [
			{"id": "c1", "wounds": 4, "current_wounds": 4, "alive": true}
		]
	}
	var board = _make_board({"U_MAIN": main_unit, "U_CHAR": char_unit})
	var result = RulesEngine.get_unit_weapons("U_MAIN", board)

	var bolt_rifle_id = RulesEngine._generate_weapon_id("Bolt rifle", "Ranged")
	var storm_bolter_id = RulesEngine._generate_weapon_id("Storm bolter", "Ranged")

	# Main unit model should have bolt rifle
	assert_true(result.has("m1"), "Main model m1 should be in results")
	assert_true(bolt_rifle_id in result["m1"], "m1 should have bolt rifle")

	# Character should use composite ID
	var composite_id = "U_CHAR:c1"
	assert_true(result.has(composite_id), "Character model should use composite ID: %s" % composite_id)
	assert_true(storm_bolter_id in result[composite_id], "Character should have storm bolter")

func test_attached_character_on_profiled_unit():
	"""Attached character on a unit with model_profiles should still use composite IDs."""
	var main_unit = _make_lootas_unit()
	main_unit["attachment_data"] = {
		"attached_characters": ["U_CHAR"]
	}
	var char_unit = {
		"id": "U_CHAR",
		"meta": {
			"name": "Character",
			"weapons": [
				{"name": "Big choppa", "type": "Melee", "range": "Melee", "attacks": "3", "strength": "7", "ap": "-1", "damage": "2"},
				{"name": "Slugga", "type": "Ranged", "range": "12", "attacks": "1", "strength": "4", "ap": "0", "damage": "1"}
			]
		},
		"models": [
			{"id": "c1", "wounds": 4, "current_wounds": 4, "alive": true}
		]
	}
	var board = _make_board({"U_LOOTAS": main_unit, "U_CHAR": char_unit})
	var result = RulesEngine.get_unit_weapons("U_LOOTAS", board)

	var slugga_id = RulesEngine._generate_weapon_id("Slugga", "Ranged")
	var composite_id = "U_CHAR:c1"

	# Character should use composite ID with only ranged weapon (slugga)
	assert_true(result.has(composite_id), "Character model should use composite ID")
	assert_true(slugga_id in result[composite_id], "Character should have slugga")
	assert_eq(result[composite_id].size(), 1, "Character should only have 1 ranged weapon (slugga)")

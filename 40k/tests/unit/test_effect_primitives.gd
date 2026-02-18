extends "res://addons/gut/test.gd"

# Tests for EffectPrimitives - Data-driven effect system
#
# EffectPrimitives provides the core effect library used by both stratagems
# and abilities to apply, query, and clear game effects.
#
# These tests verify:
# 1. Effect type constants are defined correctly
# 2. apply_effects() generates correct diffs for persistent effects
# 3. apply_effects() returns empty for instant effects
# 4. clear_effects() removes the correct flags from unit dictionaries
# 5. Query helpers (has_effect_*, get_effect_value) correctly read unit flags
# 6. get_flag_names_for_effects() returns correct flag names
# 7. grant_keyword effect correctly maps keywords to flags
# 8. grant_precision with different scopes
# 9. clear_all_effect_flags() removes all effect_ prefixed flags
# 10. is_instant_effect() / is_persistent_effect() classification
# 11. Integration with stratagem effect definitions


# ==========================================
# Helpers
# ==========================================

func _make_unit(flags: Dictionary = {}) -> Dictionary:
	return {
		"meta": {"name": "Test Unit", "keywords": ["INFANTRY"]},
		"models": [{"alive": true, "wounds": 2, "current_wounds": 2}],
		"flags": flags,
		"owner": 1
	}


# ==========================================
# Section 1: Effect Type Constants
# ==========================================

func test_effect_type_constants_defined():
	"""All core effect type constants should be non-empty strings."""
	assert_eq(EffectPrimitivesData.GRANT_INVULN, "grant_invuln")
	assert_eq(EffectPrimitivesData.GRANT_COVER, "grant_cover")
	assert_eq(EffectPrimitivesData.GRANT_STEALTH, "grant_stealth")
	assert_eq(EffectPrimitivesData.GRANT_FNP, "grant_fnp")
	assert_eq(EffectPrimitivesData.GRANT_KEYWORD, "grant_keyword")
	assert_eq(EffectPrimitivesData.GRANT_PRECISION, "grant_precision")
	assert_eq(EffectPrimitivesData.MORTAL_WOUNDS, "mortal_wounds")
	assert_eq(EffectPrimitivesData.REROLL_LAST_ROLL, "reroll_last_roll")
	assert_eq(EffectPrimitivesData.FIGHT_NEXT, "fight_next")
	assert_eq(EffectPrimitivesData.AUTO_PASS_SHOCK, "auto_pass_battle_shock")
	assert_eq(EffectPrimitivesData.OVERWATCH_SHOOT, "overwatch_shoot")
	assert_eq(EffectPrimitivesData.COUNTER_CHARGE, "counter_charge")

func test_flag_name_constants_defined():
	"""All flag name constants should start with 'effect_'."""
	assert_true(EffectPrimitivesData.FLAG_INVULN.begins_with("effect_"))
	assert_true(EffectPrimitivesData.FLAG_COVER.begins_with("effect_"))
	assert_true(EffectPrimitivesData.FLAG_STEALTH.begins_with("effect_"))
	assert_true(EffectPrimitivesData.FLAG_FNP.begins_with("effect_"))
	assert_true(EffectPrimitivesData.FLAG_PRECISION_MELEE.begins_with("effect_"))
	assert_true(EffectPrimitivesData.FLAG_PRECISION_RANGED.begins_with("effect_"))
	assert_true(EffectPrimitivesData.FLAG_LETHAL_HITS.begins_with("effect_"))
	assert_true(EffectPrimitivesData.FLAG_SUSTAINED_HITS.begins_with("effect_"))
	assert_true(EffectPrimitivesData.FLAG_DEVASTATING_WOUNDS.begins_with("effect_"))
	assert_true(EffectPrimitivesData.FLAG_IGNORES_COVER.begins_with("effect_"))


# ==========================================
# Section 2: apply_effects() — Persistent Effects
# ==========================================

func test_apply_grant_invuln():
	"""grant_invuln effect should set effect_invuln flag with value."""
	var effects = [{"type": "grant_invuln", "value": 6}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1, "Should produce 1 diff")
	assert_eq(diffs[0].op, "set")
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_invuln")
	assert_eq(diffs[0].value, 6)

func test_apply_grant_cover():
	"""grant_cover effect should set effect_cover flag to true."""
	var effects = [{"type": "grant_cover"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_cover")
	assert_eq(diffs[0].value, true)

func test_apply_grant_stealth():
	"""grant_stealth effect should set effect_stealth flag to true."""
	var effects = [{"type": "grant_stealth"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_stealth")
	assert_eq(diffs[0].value, true)

func test_apply_multiple_effects():
	"""Multiple effects should produce multiple diffs (Go to Ground pattern)."""
	var effects = [
		{"type": "grant_invuln", "value": 6},
		{"type": "grant_cover"}
	]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_INFANTRY")

	assert_eq(diffs.size(), 2, "Should produce 2 diffs")
	assert_eq(diffs[0].path, "units.U_INFANTRY.flags.effect_invuln")
	assert_eq(diffs[0].value, 6)
	assert_eq(diffs[1].path, "units.U_INFANTRY.flags.effect_cover")
	assert_eq(diffs[1].value, true)

func test_apply_smokescreen_pattern():
	"""Smokescreen effects (cover + stealth) should produce 2 diffs."""
	var effects = [
		{"type": "grant_cover"},
		{"type": "grant_stealth"}
	]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_SMOKE")

	assert_eq(diffs.size(), 2)
	assert_eq(diffs[0].path, "units.U_SMOKE.flags.effect_cover")
	assert_eq(diffs[1].path, "units.U_SMOKE.flags.effect_stealth")

func test_apply_grant_fnp():
	"""grant_fnp effect should set effect_fnp flag with value."""
	var effects = [{"type": "grant_fnp", "value": 5}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_fnp")
	assert_eq(diffs[0].value, 5)

func test_apply_plus_one_hit():
	"""plus_one_hit effect should set flag."""
	var effects = [{"type": "plus_one_hit"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_plus_one_hit")

func test_apply_worsen_ap():
	"""worsen_ap effect should set flag with value."""
	var effects = [{"type": "worsen_ap", "value": 1}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_worsen_ap")
	assert_eq(diffs[0].value, 1)

func test_apply_crit_hit_on():
	"""crit_hit_on effect should set flag with threshold value."""
	var effects = [{"type": "crit_hit_on", "value": 5}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_crit_hit_on")
	assert_eq(diffs[0].value, 5)


# ==========================================
# Section 3: apply_effects() — grant_keyword
# ==========================================

func test_apply_grant_keyword_precision_melee():
	"""grant_keyword PRECISION melee should set effect_precision_melee flag."""
	var effects = [{"type": "grant_keyword", "keyword": "PRECISION", "scope": "melee"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_CHAR")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_CHAR.flags.effect_precision_melee")
	assert_eq(diffs[0].value, true)

func test_apply_grant_keyword_precision_ranged():
	"""grant_keyword PRECISION ranged should set effect_precision_ranged flag."""
	var effects = [{"type": "grant_keyword", "keyword": "PRECISION", "scope": "ranged"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_CHAR")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_CHAR.flags.effect_precision_ranged")
	assert_eq(diffs[0].value, true)

func test_apply_grant_keyword_lethal_hits():
	"""grant_keyword LETHAL HITS should set effect_lethal_hits flag."""
	var effects = [{"type": "grant_keyword", "keyword": "LETHAL HITS", "scope": "all"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_lethal_hits")

func test_apply_grant_keyword_sustained_hits():
	"""grant_keyword SUSTAINED HITS should set effect_sustained_hits flag."""
	var effects = [{"type": "grant_keyword", "keyword": "SUSTAINED HITS", "scope": "all"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_sustained_hits")

func test_apply_grant_keyword_devastating_wounds():
	"""grant_keyword DEVASTATING WOUNDS should set effect_devastating_wounds flag."""
	var effects = [{"type": "grant_keyword", "keyword": "DEVASTATING WOUNDS", "scope": "all"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_devastating_wounds")

func test_apply_grant_keyword_ignores_cover():
	"""grant_keyword IGNORES COVER should set effect_ignores_cover flag."""
	var effects = [{"type": "grant_keyword", "keyword": "IGNORES COVER", "scope": "all"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_ignores_cover")

func test_apply_grant_keyword_unknown():
	"""grant_keyword with unknown keyword should produce no diffs."""
	var effects = [{"type": "grant_keyword", "keyword": "UNKNOWN_ABILITY", "scope": "all"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0, "Unknown keyword should produce no diffs")


# ==========================================
# Section 4: apply_effects() — grant_precision shortcut
# ==========================================

func test_apply_grant_precision_melee():
	"""grant_precision with melee scope should set melee precision flag only."""
	var effects = [{"type": "grant_precision", "scope": "melee"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_precision_melee")

func test_apply_grant_precision_ranged():
	"""grant_precision with ranged scope should set ranged precision flag only."""
	var effects = [{"type": "grant_precision", "scope": "ranged"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_precision_ranged")

func test_apply_grant_precision_all():
	"""grant_precision with 'all' scope should set both melee and ranged precision flags."""
	var effects = [{"type": "grant_precision", "scope": "all"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 2, "Should set both melee and ranged precision")
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_precision_melee")
	assert_eq(diffs[1].path, "units.U_TEST.flags.effect_precision_ranged")


# ==========================================
# Section 5: apply_effects() — Instant Effects (should be skipped)
# ==========================================

func test_apply_instant_mortal_wounds_returns_empty():
	"""Instant effect mortal_wounds should not produce diffs."""
	var effects = [{"type": "mortal_wounds", "dice": 6, "threshold": 4}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0, "Instant effects should produce no diffs")

func test_apply_instant_reroll_returns_empty():
	"""Instant effect reroll_last_roll should not produce diffs."""
	var effects = [{"type": "reroll_last_roll"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0)

func test_apply_instant_fight_next_returns_empty():
	"""Instant effect fight_next should not produce diffs."""
	var effects = [{"type": "fight_next"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0)

func test_apply_instant_auto_pass_shock_returns_empty():
	"""Instant effect auto_pass_battle_shock should not produce diffs."""
	var effects = [{"type": "auto_pass_battle_shock"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0)

func test_apply_instant_overwatch_returns_empty():
	"""Instant effect overwatch_shoot should not produce diffs."""
	var effects = [{"type": "overwatch_shoot", "hit_on": 6}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0)

func test_apply_instant_counter_charge_returns_empty():
	"""Instant effect counter_charge should not produce diffs."""
	var effects = [{"type": "counter_charge"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0)

func test_apply_unknown_effect_returns_empty():
	"""Unknown effect type should produce no diffs."""
	var effects = [{"type": "totally_unknown_effect"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0)

func test_apply_mixed_persistent_and_instant():
	"""Mixed persistent + instant effects should only produce diffs for persistent ones."""
	var effects = [
		{"type": "grant_cover"},
		{"type": "mortal_wounds", "dice": 6, "threshold": 4},
		{"type": "grant_stealth"}
	]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 2, "Only persistent effects produce diffs")
	assert_eq(diffs[0].path, "units.U_TEST.flags.effect_cover")
	assert_eq(diffs[1].path, "units.U_TEST.flags.effect_stealth")


# ==========================================
# Section 6: clear_effects()
# ==========================================

func test_clear_grant_invuln():
	"""clear_effects should remove effect_invuln flag."""
	var flags = {"effect_invuln": 6, "effect_cover": true, "other_flag": true}
	var effects = [{"type": "grant_invuln", "value": 6}]

	EffectPrimitivesData.clear_effects(effects, "U_TEST", flags)

	assert_false(flags.has("effect_invuln"), "Invuln flag should be cleared")
	assert_true(flags.has("effect_cover"), "Other effect flags should remain")
	assert_true(flags.has("other_flag"), "Non-effect flags should remain")

func test_clear_go_to_ground_effects():
	"""clear_effects for Go to Ground should remove both invuln and cover."""
	var flags = {"effect_invuln": 6, "effect_cover": true}
	var effects = [
		{"type": "grant_invuln", "value": 6},
		{"type": "grant_cover"}
	]

	EffectPrimitivesData.clear_effects(effects, "U_TEST", flags)

	assert_false(flags.has("effect_invuln"))
	assert_false(flags.has("effect_cover"))

func test_clear_smokescreen_effects():
	"""clear_effects for Smokescreen should remove cover and stealth."""
	var flags = {"effect_cover": true, "effect_stealth": true}
	var effects = [
		{"type": "grant_cover"},
		{"type": "grant_stealth"}
	]

	EffectPrimitivesData.clear_effects(effects, "U_TEST", flags)

	assert_false(flags.has("effect_cover"))
	assert_false(flags.has("effect_stealth"))

func test_clear_epic_challenge_effects():
	"""clear_effects for Epic Challenge (grant_keyword) should remove precision flag."""
	var flags = {"effect_precision_melee": true}
	var effects = [{"type": "grant_keyword", "keyword": "PRECISION", "scope": "melee"}]

	EffectPrimitivesData.clear_effects(effects, "U_TEST", flags)

	assert_false(flags.has("effect_precision_melee"))

func test_clear_grant_precision_melee():
	"""clear_effects for grant_precision melee should remove melee flag."""
	var flags = {"effect_precision_melee": true}
	var effects = [{"type": "grant_precision", "scope": "melee"}]

	EffectPrimitivesData.clear_effects(effects, "U_TEST", flags)

	assert_false(flags.has("effect_precision_melee"))

func test_clear_grant_precision_all():
	"""clear_effects for grant_precision all should remove both flags."""
	var flags = {"effect_precision_melee": true, "effect_precision_ranged": true}
	var effects = [{"type": "grant_precision", "scope": "all"}]

	EffectPrimitivesData.clear_effects(effects, "U_TEST", flags)

	assert_false(flags.has("effect_precision_melee"))
	assert_false(flags.has("effect_precision_ranged"))

func test_clear_instant_effect_noop():
	"""Clearing instant effects should not affect flags."""
	var flags = {"effect_cover": true}
	var effects = [{"type": "mortal_wounds", "dice": 6, "threshold": 4}]

	EffectPrimitivesData.clear_effects(effects, "U_TEST", flags)

	assert_true(flags.has("effect_cover"), "Flags should be untouched by instant effect clear")

func test_clear_missing_flags_safe():
	"""Clearing effects that aren't set should not error."""
	var flags = {}
	var effects = [
		{"type": "grant_invuln", "value": 6},
		{"type": "grant_cover"},
		{"type": "grant_stealth"}
	]

	# Should not throw an error
	EffectPrimitivesData.clear_effects(effects, "U_TEST", flags)
	assert_eq(flags.size(), 0, "Flags dict should still be empty")


# ==========================================
# Section 7: clear_all_effect_flags()
# ==========================================

func test_clear_all_effect_flags():
	"""clear_all_effect_flags should remove all effect_ prefixed flags."""
	var flags = {
		"effect_invuln": 6,
		"effect_cover": true,
		"effect_stealth": true,
		"battle_shocked": false,
		"has_shot": true
	}

	EffectPrimitivesData.clear_all_effect_flags(flags)

	assert_false(flags.has("effect_invuln"))
	assert_false(flags.has("effect_cover"))
	assert_false(flags.has("effect_stealth"))
	assert_true(flags.has("battle_shocked"), "Non-effect flags should remain")
	assert_true(flags.has("has_shot"), "Non-effect flags should remain")

func test_clear_all_effect_flags_empty():
	"""clear_all_effect_flags on empty dict should not error."""
	var flags = {}
	EffectPrimitivesData.clear_all_effect_flags(flags)
	assert_eq(flags.size(), 0)


# ==========================================
# Section 8: Query Helpers
# ==========================================

func test_has_effect_invuln():
	"""has_effect_invuln should detect invuln flag."""
	var unit_with = _make_unit({"effect_invuln": 6})
	var unit_without = _make_unit({})

	assert_true(EffectPrimitivesData.has_effect_invuln(unit_with))
	assert_false(EffectPrimitivesData.has_effect_invuln(unit_without))

func test_get_effect_invuln():
	"""get_effect_invuln should return the save threshold value."""
	var unit = _make_unit({"effect_invuln": 5})
	assert_eq(EffectPrimitivesData.get_effect_invuln(unit), 5)

	var unit_none = _make_unit({})
	assert_eq(EffectPrimitivesData.get_effect_invuln(unit_none), 0)

func test_has_effect_cover():
	"""has_effect_cover should detect cover flag."""
	assert_true(EffectPrimitivesData.has_effect_cover(_make_unit({"effect_cover": true})))
	assert_false(EffectPrimitivesData.has_effect_cover(_make_unit({})))

func test_has_effect_stealth():
	"""has_effect_stealth should detect stealth flag."""
	assert_true(EffectPrimitivesData.has_effect_stealth(_make_unit({"effect_stealth": true})))
	assert_false(EffectPrimitivesData.has_effect_stealth(_make_unit({})))

func test_has_effect_precision_melee():
	"""has_effect_precision_melee should detect melee precision flag."""
	assert_true(EffectPrimitivesData.has_effect_precision_melee(_make_unit({"effect_precision_melee": true})))
	assert_false(EffectPrimitivesData.has_effect_precision_melee(_make_unit({})))

func test_has_effect_precision_ranged():
	"""has_effect_precision_ranged should detect ranged precision flag."""
	assert_true(EffectPrimitivesData.has_effect_precision_ranged(_make_unit({"effect_precision_ranged": true})))
	assert_false(EffectPrimitivesData.has_effect_precision_ranged(_make_unit({})))

func test_has_effect_fnp():
	"""has_effect_fnp should detect FNP flag."""
	assert_true(EffectPrimitivesData.has_effect_fnp(_make_unit({"effect_fnp": 5})))
	assert_false(EffectPrimitivesData.has_effect_fnp(_make_unit({})))

func test_get_effect_fnp():
	"""get_effect_fnp should return FNP threshold."""
	assert_eq(EffectPrimitivesData.get_effect_fnp(_make_unit({"effect_fnp": 4})), 4)
	assert_eq(EffectPrimitivesData.get_effect_fnp(_make_unit({})), 0)

func test_has_any_effect_flag():
	"""has_any_effect_flag should detect any effect_ prefixed flag."""
	assert_true(EffectPrimitivesData.has_any_effect_flag(_make_unit({"effect_cover": true})))
	assert_false(EffectPrimitivesData.has_any_effect_flag(_make_unit({"battle_shocked": true})))
	assert_false(EffectPrimitivesData.has_any_effect_flag(_make_unit({})))

func test_query_unit_with_no_flags_dict():
	"""Query helpers should handle units with no flags dict gracefully."""
	var unit = {"meta": {"name": "Test"}, "models": []}
	assert_false(EffectPrimitivesData.has_effect_invuln(unit))
	assert_eq(EffectPrimitivesData.get_effect_invuln(unit), 0)
	assert_false(EffectPrimitivesData.has_effect_cover(unit))
	assert_false(EffectPrimitivesData.has_effect_stealth(unit))


# ==========================================
# Section 9: get_flag_names_for_effects()
# ==========================================

func test_get_flag_names_for_go_to_ground():
	"""Flag names for Go to Ground effects should include invuln and cover."""
	var effects = [
		{"type": "grant_invuln", "value": 6},
		{"type": "grant_cover"}
	]
	var flags = EffectPrimitivesData.get_flag_names_for_effects(effects)

	assert_true("effect_invuln" in flags, "Should include invuln flag")
	assert_true("effect_cover" in flags, "Should include cover flag")
	assert_eq(flags.size(), 2)

func test_get_flag_names_for_smokescreen():
	"""Flag names for Smokescreen effects should include cover and stealth."""
	var effects = [
		{"type": "grant_cover"},
		{"type": "grant_stealth"}
	]
	var flags = EffectPrimitivesData.get_flag_names_for_effects(effects)

	assert_true("effect_cover" in flags)
	assert_true("effect_stealth" in flags)

func test_get_flag_names_for_epic_challenge():
	"""Flag names for Epic Challenge (grant_keyword PRECISION melee) should include precision flag."""
	var effects = [{"type": "grant_keyword", "keyword": "PRECISION", "scope": "melee"}]
	var flags = EffectPrimitivesData.get_flag_names_for_effects(effects)

	assert_true("effect_precision_melee" in flags)

func test_get_flag_names_excludes_instant():
	"""Flag names for instant effects should be empty."""
	var effects = [
		{"type": "mortal_wounds", "dice": 6, "threshold": 4},
		{"type": "reroll_last_roll"},
		{"type": "fight_next"}
	]
	var flags = EffectPrimitivesData.get_flag_names_for_effects(effects)

	assert_eq(flags.size(), 0, "Instant effects should have no flag names")


# ==========================================
# Section 10: Effect Classification
# ==========================================

func test_is_instant_effect():
	"""is_instant_effect should identify instant effect types."""
	assert_true(EffectPrimitivesData.is_instant_effect("mortal_wounds"))
	assert_true(EffectPrimitivesData.is_instant_effect("mortal_wounds_toughness_based"))
	assert_true(EffectPrimitivesData.is_instant_effect("reroll_last_roll"))
	assert_true(EffectPrimitivesData.is_instant_effect("fight_next"))
	assert_true(EffectPrimitivesData.is_instant_effect("overwatch_shoot"))
	assert_true(EffectPrimitivesData.is_instant_effect("counter_charge"))
	assert_true(EffectPrimitivesData.is_instant_effect("auto_pass_battle_shock"))
	assert_true(EffectPrimitivesData.is_instant_effect("arrive_from_reserves"))
	assert_true(EffectPrimitivesData.is_instant_effect("discard_and_draw_secondary"))

func test_is_not_instant_effect():
	"""is_instant_effect should return false for persistent effect types."""
	assert_false(EffectPrimitivesData.is_instant_effect("grant_invuln"))
	assert_false(EffectPrimitivesData.is_instant_effect("grant_cover"))
	assert_false(EffectPrimitivesData.is_instant_effect("grant_stealth"))
	assert_false(EffectPrimitivesData.is_instant_effect("grant_keyword"))
	assert_false(EffectPrimitivesData.is_instant_effect("plus_one_hit"))

func test_is_persistent_effect():
	"""is_persistent_effect should identify persistent effect types."""
	assert_true(EffectPrimitivesData.is_persistent_effect("grant_invuln"))
	assert_true(EffectPrimitivesData.is_persistent_effect("grant_cover"))
	assert_true(EffectPrimitivesData.is_persistent_effect("grant_stealth"))
	assert_true(EffectPrimitivesData.is_persistent_effect("grant_keyword"))
	assert_true(EffectPrimitivesData.is_persistent_effect("grant_precision"))
	assert_true(EffectPrimitivesData.is_persistent_effect("plus_one_hit"))
	assert_true(EffectPrimitivesData.is_persistent_effect("worsen_ap"))

func test_is_not_persistent_effect():
	"""is_persistent_effect should return false for instant effects."""
	assert_false(EffectPrimitivesData.is_persistent_effect("mortal_wounds"))
	assert_false(EffectPrimitivesData.is_persistent_effect("reroll_last_roll"))
	assert_false(EffectPrimitivesData.is_persistent_effect("fight_next"))


# ==========================================
# Section 11: get_all_persistent_flag_names()
# ==========================================

func test_get_all_persistent_flag_names():
	"""get_all_persistent_flag_names should return all possible flag names."""
	var all_flags = EffectPrimitivesData.get_all_persistent_flag_names()

	assert_true(all_flags.size() > 0, "Should return non-empty array")
	assert_true("effect_invuln" in all_flags)
	assert_true("effect_cover" in all_flags)
	assert_true("effect_stealth" in all_flags)
	assert_true("effect_fnp" in all_flags)
	assert_true("effect_precision_melee" in all_flags)
	assert_true("effect_precision_ranged" in all_flags)
	assert_true("effect_lethal_hits" in all_flags)
	assert_true("effect_sustained_hits" in all_flags)
	assert_true("effect_devastating_wounds" in all_flags)
	assert_true("effect_ignores_cover" in all_flags)
	assert_true("effect_plus_one_hit" in all_flags)
	assert_true("effect_minus_one_hit" in all_flags)
	assert_true("effect_worsen_ap" in all_flags)
	assert_true("effect_minus_damage" in all_flags)


# ==========================================
# Section 12: Integration with Stratagem Definitions
# ==========================================

func test_go_to_ground_stratagem_effects_via_apply():
	"""The actual Go to Ground stratagem effect definitions should apply correctly."""
	# These are the exact effects from StratagemManager's go_to_ground definition
	var effects = [
		{"type": "grant_invuln", "value": 6},
		{"type": "grant_cover"}
	]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_INFANTRY_A")

	assert_eq(diffs.size(), 2)
	# Verify invuln diff
	assert_eq(diffs[0].op, "set")
	assert_eq(diffs[0].path, "units.U_INFANTRY_A.flags.effect_invuln")
	assert_eq(diffs[0].value, 6)
	# Verify cover diff
	assert_eq(diffs[1].op, "set")
	assert_eq(diffs[1].path, "units.U_INFANTRY_A.flags.effect_cover")
	assert_eq(diffs[1].value, true)

func test_smokescreen_stratagem_effects_via_apply():
	"""The actual Smokescreen stratagem effect definitions should apply correctly."""
	var effects = [
		{"type": "grant_cover"},
		{"type": "grant_stealth"}
	]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_SMOKE_A")

	assert_eq(diffs.size(), 2)
	assert_eq(diffs[0].path, "units.U_SMOKE_A.flags.effect_cover")
	assert_eq(diffs[1].path, "units.U_SMOKE_A.flags.effect_stealth")

func test_epic_challenge_stratagem_effects_via_apply():
	"""The actual Epic Challenge stratagem effect definitions should apply correctly."""
	var effects = [{"type": "grant_keyword", "keyword": "PRECISION", "scope": "melee"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_CHARACTER_A")

	assert_eq(diffs.size(), 1)
	assert_eq(diffs[0].path, "units.U_CHARACTER_A.flags.effect_precision_melee")
	assert_eq(diffs[0].value, true)

func test_grenade_stratagem_effects_via_apply():
	"""Grenade stratagem (instant mortal wounds) should produce no diffs."""
	var effects = [{"type": "mortal_wounds", "dice": 6, "threshold": 4}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0, "Grenade is instant, no persistent flags")

func test_command_reroll_effects_via_apply():
	"""Command Re-roll (instant reroll) should produce no diffs."""
	var effects = [{"type": "reroll_last_roll"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0, "Command Re-roll is instant, no persistent flags")

func test_counter_offensive_effects_via_apply():
	"""Counter-Offensive (instant fight order) should produce no diffs."""
	var effects = [{"type": "fight_next"}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0, "Counter-Offensive is instant, no persistent flags")

func test_fire_overwatch_effects_via_apply():
	"""Fire Overwatch (instant shooting) should produce no diffs."""
	var effects = [{"type": "overwatch_shoot", "hit_on": 6}]
	var diffs = EffectPrimitivesData.apply_effects(effects, "U_TEST")

	assert_eq(diffs.size(), 0, "Fire Overwatch is instant, no persistent flags")


# ==========================================
# Section 13: Round-trip (apply then clear)
# ==========================================

func test_apply_then_clear_go_to_ground():
	"""Applying then clearing Go to Ground effects should restore original state."""
	var unit_flags = {}
	var effects = [
		{"type": "grant_invuln", "value": 6},
		{"type": "grant_cover"}
	]

	# Simulate applying (set flags manually as diffs would)
	unit_flags["effect_invuln"] = 6
	unit_flags["effect_cover"] = true
	assert_eq(unit_flags.size(), 2)

	# Clear
	EffectPrimitivesData.clear_effects(effects, "U_TEST", unit_flags)
	assert_eq(unit_flags.size(), 0, "All effect flags should be cleared")

func test_apply_then_clear_preserves_non_effect_flags():
	"""Clearing effects should not remove non-effect flags."""
	var unit_flags = {
		"effect_invuln": 6,
		"effect_cover": true,
		"battle_shocked": false,
		"has_shot": true,
		"advanced": false
	}
	var effects = [
		{"type": "grant_invuln", "value": 6},
		{"type": "grant_cover"}
	]

	EffectPrimitivesData.clear_effects(effects, "U_TEST", unit_flags)

	assert_false(unit_flags.has("effect_invuln"), "Effect flag should be cleared")
	assert_false(unit_flags.has("effect_cover"), "Effect flag should be cleared")
	assert_true(unit_flags.has("battle_shocked"), "Non-effect flag should remain")
	assert_true(unit_flags.has("has_shot"), "Non-effect flag should remain")
	assert_true(unit_flags.has("advanced"), "Non-effect flag should remain")

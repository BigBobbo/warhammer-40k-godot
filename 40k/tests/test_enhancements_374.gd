extends SceneTree

# Issue #374: validate that the 8 P0 enhancements (4 Shield Host +
# 4 War Horde) are registered in UnitAbilityManager.ABILITY_EFFECTS
# with correct effect primitives, and that the new PLUS_MOVE,
# PLUS_STRENGTH_MELEE flag plumbing emits diffs via apply_effects.
# Run via: godot --headless --path 40k --script tests/test_enhancements_374.gd

func _initialize():
	call_deferred("_run_tests")

func _run_tests():
	print("=== Issue #374: P0 enhancement registry + primitive validation ===")
	var failures := 0
	failures += _test_all_8_registered()
	failures += _test_panoptispex_grants_ignores_cover()
	failures += _test_hall_of_armouries_grants_strength_and_damage()
	failures += _test_follow_me_ladz_grants_plus_move()
	failures += _test_headwoppa_grants_devastating_wounds()
	failures += _test_kunnin_but_brutal_grants_fallback_eligibility()
	failures += _test_supa_cybork_grants_fnp_4()
	failures += _test_auric_mantle_marked_listbuild_only()
	failures += _test_castellans_mark_marked_pregame_only()
	failures += _test_plus_move_flag_diff_emitted()
	failures += _test_plus_strength_melee_flag_diff_emitted()
	if failures == 0:
		print("\n[OK] all #374 validations passed")
		quit(0)
	else:
		print("\n[FAIL] %d validation(s) failed" % failures)
		quit(1)

func _get_ability_manager():
	if root != null and root.has_node("UnitAbilityManager"):
		return root.get_node("UnitAbilityManager")
	return null

func _test_all_8_registered() -> int:
	print("\n-- 8 P0 enhancements in ABILITY_EFFECTS --")
	var mgr = _get_ability_manager()
	if mgr == null:
		print("[FAIL] UnitAbilityManager autoload missing")
		return 1
	var fails := 0
	var names = [
		"Auric Mantle", "Castellan's Mark", "From the Hall of Armouries", "Panoptispex",
		"Follow Me Ladz", "Headwoppa's Killchoppa", "Kunnin' But Brutal", "Supa-Cybork Body",
	]
	for name in names:
		if not mgr.ABILITY_EFFECTS.has(name):
			print("[FAIL] ABILITY_EFFECTS missing entry for '%s'" % name)
			fails += 1
		else:
			var entry = mgr.ABILITY_EFFECTS[name]
			if entry.get("condition", "") != "enhancement":
				print("[FAIL] '%s' has condition='%s', expected 'enhancement'" % [name, entry.get("condition", "")])
				fails += 1
	if fails == 0:
		print("  [OK] all 8 enhancement entries registered with condition=enhancement")
	return fails

func _has_effect_type(effects: Array, type_name: String) -> bool:
	for e in effects:
		if e.get("type", "") == type_name:
			return true
	return false

func _test_panoptispex_grants_ignores_cover() -> int:
	print("\n-- Panoptispex effect = grant_ignores_cover --")
	var mgr = _get_ability_manager()
	var entry = mgr.ABILITY_EFFECTS.get("Panoptispex", {})
	if not _has_effect_type(entry.get("effects", []), EffectPrimitivesData.GRANT_IGNORES_COVER):
		print("[FAIL] Panoptispex missing grant_ignores_cover, got %s" % str(entry))
		return 1
	if not entry.get("implemented", false):
		print("[FAIL] Panoptispex marked implemented:false")
		return 1
	print("  [OK]")
	return 0

func _test_hall_of_armouries_grants_strength_and_damage() -> int:
	print("\n-- From the Hall of Armouries effects = plus_strength_melee + plus_damage --")
	var mgr = _get_ability_manager()
	var entry = mgr.ABILITY_EFFECTS.get("From the Hall of Armouries", {})
	var effs = entry.get("effects", [])
	if not _has_effect_type(effs, EffectPrimitivesData.PLUS_STRENGTH_MELEE):
		print("[FAIL] missing plus_strength_melee, got %s" % str(effs))
		return 1
	if not _has_effect_type(effs, EffectPrimitivesData.PLUS_DAMAGE):
		print("[FAIL] missing plus_damage, got %s" % str(effs))
		return 1
	print("  [OK]")
	return 0

func _test_follow_me_ladz_grants_plus_move() -> int:
	print("\n-- Follow Me Ladz effect = plus_move value=2 --")
	var mgr = _get_ability_manager()
	var entry = mgr.ABILITY_EFFECTS.get("Follow Me Ladz", {})
	for e in entry.get("effects", []):
		if e.get("type", "") == EffectPrimitivesData.PLUS_MOVE and int(e.get("value", 0)) == 2:
			print("  [OK]")
			return 0
	print("[FAIL] missing plus_move value=2, got %s" % str(entry.get("effects", [])))
	return 1

func _test_headwoppa_grants_devastating_wounds() -> int:
	print("\n-- Headwoppa's Killchoppa effect = grant_devastating_wounds --")
	var mgr = _get_ability_manager()
	var entry = mgr.ABILITY_EFFECTS.get("Headwoppa's Killchoppa", {})
	if not _has_effect_type(entry.get("effects", []), EffectPrimitivesData.GRANT_DEVASTATING_WOUNDS):
		print("[FAIL] missing grant_devastating_wounds, got %s" % str(entry))
		return 1
	print("  [OK]")
	return 0

func _test_kunnin_but_brutal_grants_fallback_eligibility() -> int:
	print("\n-- Kunnin' But Brutal effects = fall_back_and_shoot + fall_back_and_charge --")
	var mgr = _get_ability_manager()
	var entry = mgr.ABILITY_EFFECTS.get("Kunnin' But Brutal", {})
	var effs = entry.get("effects", [])
	if not _has_effect_type(effs, EffectPrimitivesData.FALL_BACK_AND_SHOOT):
		print("[FAIL] missing fall_back_and_shoot, got %s" % str(effs))
		return 1
	if not _has_effect_type(effs, EffectPrimitivesData.FALL_BACK_AND_CHARGE):
		print("[FAIL] missing fall_back_and_charge, got %s" % str(effs))
		return 1
	print("  [OK]")
	return 0

func _test_supa_cybork_grants_fnp_4() -> int:
	print("\n-- Supa-Cybork Body effect = set_effect_fnp value=4 --")
	var mgr = _get_ability_manager()
	var entry = mgr.ABILITY_EFFECTS.get("Supa-Cybork Body", {})
	for e in entry.get("effects", []):
		if e.get("type", "") == "set_effect_fnp" and int(e.get("value", 0)) == 4:
			print("  [OK]")
			return 0
	print("[FAIL] missing set_effect_fnp value=4, got %s" % str(entry.get("effects", [])))
	return 1

func _test_auric_mantle_marked_listbuild_only() -> int:
	print("\n-- Auric Mantle implemented:false (list-build mutation, not runtime flag) --")
	var mgr = _get_ability_manager()
	var entry = mgr.ABILITY_EFFECTS.get("Auric Mantle", {})
	if entry.get("implemented", true):
		print("[FAIL] expected implemented:false, got %s" % str(entry))
		return 1
	# But the entry should still carry a plus_wounds effect for documentation.
	if not _has_effect_type(entry.get("effects", []), EffectPrimitivesData.PLUS_WOUNDS):
		print("[FAIL] expected plus_wounds effect, got %s" % str(entry))
		return 1
	print("  [OK]")
	return 0

func _test_castellans_mark_marked_pregame_only() -> int:
	print("\n-- Castellan's Mark implemented:false (pre-game redeploy action) --")
	var mgr = _get_ability_manager()
	var entry = mgr.ABILITY_EFFECTS.get("Castellan's Mark", {})
	if entry.get("implemented", true):
		print("[FAIL] expected implemented:false, got %s" % str(entry))
		return 1
	print("  [OK]")
	return 0

func _test_plus_move_flag_diff_emitted() -> int:
	print("\n-- apply_effects([plus_move value=2]) emits effect_plus_move=2 diff --")
	var diffs = EffectPrimitivesData.apply_effects([{"type": EffectPrimitivesData.PLUS_MOVE, "value": 2}], "U_TEST")
	for d in diffs:
		if String(d.get("path", "")).ends_with(".flags.effect_plus_move") and int(d.get("value", 0)) == 2:
			print("  [OK]")
			return 0
	print("[FAIL] expected effect_plus_move=2 diff, got %s" % str(diffs))
	return 1

func _test_plus_strength_melee_flag_diff_emitted() -> int:
	print("\n-- apply_effects([plus_strength_melee value=1]) emits effect_plus_strength_melee=1 diff --")
	var diffs = EffectPrimitivesData.apply_effects([{"type": EffectPrimitivesData.PLUS_STRENGTH_MELEE, "value": 1}], "U_TEST")
	for d in diffs:
		if String(d.get("path", "")).ends_with(".flags.effect_plus_strength_melee") and int(d.get("value", 0)) == 1:
			print("  [OK]")
			return 0
	print("[FAIL] expected effect_plus_strength_melee=1 diff, got %s" % str(diffs))
	return 1

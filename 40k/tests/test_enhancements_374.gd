extends SceneTree

# Issue #374: the P0 enhancement rows of UnitAbilityManager.ABILITY_EFFECTS.
# Both halves are retired: the 4 Shield Host rows (Auric Mantle, Castellan's
# Mark, From the Hall of Armouries, Panoptispex) with the 10e detachment in
# WP-C46, and the 4 War Horde rows (Follow Me Ladz, Headwoppa's Killchoppa,
# Kunnin' But Brutal, Supa-Cybork Body) in WP-O5 — the codex War Horde
# enhancements (Headwoppa's Killchoppa +1 AP after charging, Da Boss is
# Watchin', Kunnin' But Brutal, Follow Me Ladz) run through
# scripts/codex/orks/OrkEnhancements11e.gd and Supa-Cybork Body is not a
# codex enhancement. All 8 are pinned ABSENT here; the PLUS_MOVE /
# PLUS_STRENGTH_MELEE flag plumbing the issue introduced stays live.
# Run via: godot --headless --path 40k --script tests/test_enhancements_374.gd

func _initialize():
	call_deferred("_run_tests")

func _run_tests():
	print("=== Issue #374: P0 enhancement registry + primitive validation ===")
	var failures := 0
	failures += _test_war_horde_entries_retired()
	failures += _test_shield_host_entries_retired()
	failures += _test_codex_module_owns_war_horde()
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

func _test_war_horde_entries_retired() -> int:
	print("\n-- 10e War Horde enhancement rows retired (WP-O5) --")
	var mgr = _get_ability_manager()
	if mgr == null:
		print("[FAIL] UnitAbilityManager autoload missing")
		return 1
	var fails := 0
	for name in ["Follow Me Ladz", "Headwoppa's Killchoppa", "Kunnin' But Brutal", "Supa-Cybork Body"]:
		if mgr.ABILITY_EFFECTS.has(name):
			print("[FAIL] retired 10e row '%s' still in ABILITY_EFFECTS" % name)
			fails += 1
	if fails == 0:
		print("  [OK] the codex War Horde enhancements run through OrkEnhancements11e.gd")
	return fails

func _test_shield_host_entries_retired() -> int:
	print("\n-- 10e Shield Host enhancement rows retired (WP-C46) --")
	var mgr = _get_ability_manager()
	var fails := 0
	for name in ["Auric Mantle", "Castellan's Mark", "From the Hall of Armouries", "Panoptispex"]:
		if mgr.ABILITY_EFFECTS.has(name):
			print("[FAIL] retired 10e row '%s' still in ABILITY_EFFECTS" % name)
			fails += 1
	if fails == 0:
		print("  [OK] codex enhancements of the same names run through CustodesEnhancements.gd")
	return fails

func _test_codex_module_owns_war_horde() -> int:
	print("\n-- the codex War Horde enhancements are in OrkEnhancements11e (WP-O5) --")
	var e = load("res://scripts/codex/orks/OrkEnhancements11e.gd")
	var fails := 0
	for name in ["Follow Me Ladz", "Headwoppa's Killchoppa", "Kunnin' But Brutal", "Da Boss is Watchin'"]:
		var slug: String = e.slug_of_name(name)
		if slug == "" or str(e.DETACHMENT.get(slug, "")) != "war horde":
			print("[FAIL] '%s' is not a War Horde enhancement of the codex module (slug '%s')" % [name, slug])
			fails += 1
	if e.slug_of_name("Supa-Cybork Body") != "":
		print("[FAIL] Supa-Cybork Body is not a codex enhancement")
		fails += 1
	if fails == 0:
		print("  [OK]")
	return fails

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

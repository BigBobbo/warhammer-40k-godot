extends SceneTree

# Issue #375: validate the parser branches and primitive plumbing for the
# P0 detachment stratagems that previously fell through to "custom:unmapped".
# Run via: godot --headless --path 40k --script tests/test_p0_stratagems_375.gd

func _initialize():
	call_deferred("_run_tests")

func _run_tests():
	print("=== Issue #375: P0 detachment stratagem parser/primitive validation ===")
	var failures := 0
	failures += _test_avenge_the_fallen_parses()
	failures += _test_ere_we_go_advance_and_charge_parses()
	failures += _test_mob_rule_parses()
	failures += _test_vigilance_eternal_parses()
	failures += _test_careen_parses()
	failures += _test_orks_is_never_beaten_parses()
	failures += _test_ard_as_nails_parses()
	failures += _test_unbridled_carnage_parses()
	failures += _test_primitive_constants_registered()
	failures += _test_swing_back_flag_in_effect_map()
	if failures == 0:
		print("\n[OK] all #375 validations passed")
		quit(0)
	else:
		print("\n[FAIL] %d validation(s) failed" % failures)
		quit(1)

func _get_loader():
	return FactionStratagemLoaderData.new()

func _has_effect(effects: Array, type_name: String) -> bool:
	for e in effects:
		if e.get("type", "") == type_name:
			return true
	return false

func _find_effect(effects: Array, type_name: String) -> Dictionary:
	for e in effects:
		if e.get("type", "") == type_name:
			return e
	return {}

func _test_avenge_the_fallen_parses() -> int:
	print("\n-- AVENGE THE FALLEN: 'add 1/2 to the Attacks characteristic of melee' --")
	var l = _get_loader()
	var text = "Until the end of the phase, add 1 to the Attacks characteristic of melee weapons equipped by models in that unit. If your unit is Below Half-strength, until the end of the phase, add 2 to the Attacks characteristic of those melee weapons instead."
	var effects = l._map_effects(text)
	var pa = _find_effect(effects, EffectPrimitivesData.PLUS_ATTACKS)
	if pa.is_empty():
		print("[FAIL] expected PLUS_ATTACKS effect, got %s" % str(effects))
		return 1
	if int(pa.get("value", 0)) != 2:
		print("[FAIL] expected PLUS_ATTACKS.value=2 (max from regex), got %s" % str(pa))
		return 1
	if String(pa.get("scope", "")) != "melee":
		print("[FAIL] expected scope=melee, got %s" % str(pa))
		return 1
	print("  [OK] PLUS_ATTACKS value=2 scope=melee")
	return 0

func _test_ere_we_go_advance_and_charge_parses() -> int:
	print("\n-- 'ERE WE GO: 'add 2 to Advance and Charge rolls' -> PLUS_CHARGE 2 --")
	var l = _get_loader()
	var effects = l._map_effects("Until the end of the turn, add 2 to Advance and Charge rolls made for your unit.")
	var pc = _find_effect(effects, EffectPrimitivesData.PLUS_CHARGE)
	if pc.is_empty() or int(pc.get("value", 0)) != 2:
		print("[FAIL] expected PLUS_CHARGE.value=2, got %s" % str(effects))
		return 1
	print("  [OK] PLUS_CHARGE value=2")
	return 0

func _test_mob_rule_parses() -> int:
	print("\n-- MOB RULE: 'is no longer Battle-shocked' -> REMOVE_BATTLE_SHOCK --")
	var l = _get_loader()
	var effects = l._map_effects("Select one friendly Battle-shocked Orks Infantry unit within 6 inches of that MOB unit. That ORKS INFANTRY unit is no longer Battle-shocked.")
	if not _has_effect(effects, EffectPrimitivesData.REMOVE_BATTLE_SHOCK):
		print("[FAIL] expected REMOVE_BATTLE_SHOCK, got %s" % str(effects))
		return 1
	print("  [OK] REMOVE_BATTLE_SHOCK")
	return 0

func _test_vigilance_eternal_parses() -> int:
	print("\n-- VIGILANCE ETERNAL: sticky objective marker -> STICKY_OBJECTIVE_CONTROL --")
	var l = _get_loader()
	var effects = l._map_effects("That objective marker remains under your control even if you have no models within range of it, until your opponent controls it at the start or end of any turn.")
	if not _has_effect(effects, EffectPrimitivesData.STICKY_OBJECTIVE_CONTROL):
		print("[FAIL] expected STICKY_OBJECTIVE_CONTROL, got %s" % str(effects))
		return 1
	print("  [OK] STICKY_OBJECTIVE_CONTROL")
	return 0

func _test_careen_parses() -> int:
	print("\n-- CAREEN!: 'Normal or Fall Back move ... before its Deadly Demise' -> DEADLY_DEMISE_MOVE --")
	var l = _get_loader()
	var effects = l._map_effects("Your unit can make a Normal or Fall Back move before its Deadly Demise ability is resolved.")
	if not _has_effect(effects, EffectPrimitivesData.DEADLY_DEMISE_MOVE):
		print("[FAIL] expected DEADLY_DEMISE_MOVE, got %s" % str(effects))
		return 1
	print("  [OK] DEADLY_DEMISE_MOVE")
	return 0

func _test_orks_is_never_beaten_parses() -> int:
	print("\n-- ORKS IS NEVER BEATEN: 'do not remove ... can fight after' -> SWING_BACK_BEFORE_REMOVE --")
	var l = _get_loader()
	var effects = l._map_effects("each time a model in your unit is destroyed, if that model has not fought this phase, do not remove it from play. The destroyed model can fight after the attacking model's unit has finished making attacks, and is then removed from play.")
	if not _has_effect(effects, EffectPrimitivesData.SWING_BACK_BEFORE_REMOVE):
		print("[FAIL] expected SWING_BACK_BEFORE_REMOVE, got %s" % str(effects))
		return 1
	print("  [OK] SWING_BACK_BEFORE_REMOVE")
	return 0

func _test_ard_as_nails_parses() -> int:
	print("\n-- 'ARD AS NAILS: 'subtract 1 from the Wound roll' -> MINUS_ONE_WOUND --")
	var l = _get_loader()
	var effects = l._map_effects("Until the end of the phase, each time an attack targets your unit, subtract 1 from the Wound roll.")
	if not _has_effect(effects, EffectPrimitivesData.MINUS_ONE_WOUND):
		print("[FAIL] expected MINUS_ONE_WOUND, got %s" % str(effects))
		return 1
	print("  [OK] MINUS_ONE_WOUND")
	return 0

func _test_unbridled_carnage_parses() -> int:
	print("\n-- UNBRIDLED CARNAGE: 'unmodified hit roll of 5+' -> CRIT_HIT_ON 5 --")
	var l = _get_loader()
	var effects = l._map_effects("each time a model in your unit makes a melee attack, an unmodified hit roll of 5+ scores a Critical Hit.")
	var crit = _find_effect(effects, EffectPrimitivesData.CRIT_HIT_ON)
	if crit.is_empty() or int(crit.get("value", 0)) != 5:
		print("[FAIL] expected CRIT_HIT_ON value=5, got %s" % str(effects))
		return 1
	print("  [OK] CRIT_HIT_ON value=5")
	return 0

func _test_primitive_constants_registered() -> int:
	print("\n-- new primitive constants present in EffectPrimitivesData --")
	var fails := 0
	for name in ["REMOVE_BATTLE_SHOCK", "STICKY_OBJECTIVE_CONTROL", "DEADLY_DEMISE_MOVE", "SWING_BACK_BEFORE_REMOVE"]:
		if not name in EffectPrimitivesData:
			print("[FAIL] EffectPrimitivesData.%s missing" % name)
			fails += 1
	if fails == 0:
		print("  [OK] all 4 new primitive constants registered")
	return fails

func _test_swing_back_flag_in_effect_map() -> int:
	print("\n-- SWING_BACK_BEFORE_REMOVE registered in _EFFECT_FLAG_MAP --")
	# Apply effect to a synthetic unit and check the diff sets the flag.
	var diffs = EffectPrimitivesData.apply_effects([{"type": EffectPrimitivesData.SWING_BACK_BEFORE_REMOVE}], "U_TEST")
	var found = false
	for d in diffs:
		if String(d.get("path", "")).ends_with(".flags.effect_swing_back_before_remove") and d.get("value") == true:
			found = true
			break
	if not found:
		print("[FAIL] expected effect_swing_back_before_remove diff, got %s" % str(diffs))
		return 1
	print("  [OK] flag diff emitted: effect_swing_back_before_remove=true")
	return 0

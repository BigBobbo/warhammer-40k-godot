extends SceneTree

# Issue #372: validate that the charge-roll +N parser and PLUS_CHARGE primitive
# work as expected. Run via: godot --headless --script tests/test_charge_modifier_372.gd

func _initialize():
	print("=== Issue #372: charge-roll modifier validation ===")
	var failures = 0
	failures += _test_parser()
	failures += _test_primitive_apply()
	failures += _test_resolve_path_math()

	if failures == 0:
		print("\n[OK] all #372 validations passed")
		quit(0)
	else:
		print("\n[FAIL] %d validation(s) failed" % failures)
		quit(1)

func _test_parser() -> int:
	print("\n-- _map_effects parser --")
	var loader = FactionStratagemLoaderData.new()
	var fails = 0

	var cases = [
		# [input_text, expected_type, expected_value]
		["add 2 to that Charge roll", "plus_charge", 2],
		["add 1 to its charge roll", "plus_charge", 1],
		["add 3 to the Charge roll", "plus_charge", 3],
		["+2 to charge", "plus_charge", 2],
		["re-roll the Charge roll", "reroll_charge", null],
		["re-roll its charge roll", "reroll_charge", null],
	]
	for c in cases:
		var effects = loader._map_effects(c[0])
		var found = false
		var found_value = null
		for e in effects:
			if e.get("type", "") == c[1]:
				found = true
				found_value = e.get("value", null)
				break
		if not found:
			print("[FAIL] '%s' → no %s found, got %s" % [c[0], c[1], str(effects)])
			fails += 1
		elif c[2] != null and found_value != c[2]:
			print("[FAIL] '%s' → %s value mismatch: got %s expected %s" % [c[0], c[1], str(found_value), str(c[2])])
			fails += 1
		else:
			print("[OK]   '%s' → %s%s" % [c[0], c[1], "" if c[2] == null else (" value=%d" % c[2])])
	return fails

func _test_primitive_apply() -> int:
	print("\n-- EffectPrimitives apply/clear --")
	var fails = 0

	# Verify constants
	if not EffectPrimitivesData.PLUS_CHARGE == "plus_charge":
		print("[FAIL] PLUS_CHARGE constant"); fails += 1
	else:
		print("[OK]   PLUS_CHARGE = %s" % EffectPrimitivesData.PLUS_CHARGE)
	if not EffectPrimitivesData.FLAG_PLUS_CHARGE == "effect_plus_charge":
		print("[FAIL] FLAG_PLUS_CHARGE constant"); fails += 1
	else:
		print("[OK]   FLAG_PLUS_CHARGE = %s" % EffectPrimitivesData.FLAG_PLUS_CHARGE)

	# Verify get_effect_plus_charge helper reads the flag
	var unit = {"flags": {"effect_plus_charge": 2}}
	var bonus = EffectPrimitivesData.get_effect_plus_charge(unit)
	if bonus != 2:
		print("[FAIL] get_effect_plus_charge returned %d expected 2" % bonus); fails += 1
	else:
		print("[OK]   get_effect_plus_charge({flag:2}) = 2")

	var unit_no_flag = {"flags": {}}
	var bonus_zero = EffectPrimitivesData.get_effect_plus_charge(unit_no_flag)
	if bonus_zero != 0:
		print("[FAIL] get_effect_plus_charge no-flag returned %d expected 0" % bonus_zero); fails += 1
	else:
		print("[OK]   get_effect_plus_charge({}) = 0")

	# Verify _EFFECT_FLAG_MAP has entry by checking get_flag_names_for_effects
	var effects = [{"type": "plus_charge", "value": 2}]
	var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
	if "effect_plus_charge" not in flag_names:
		print("[FAIL] get_flag_names_for_effects: %s does not contain effect_plus_charge" % str(flag_names)); fails += 1
	else:
		print("[OK]   get_flag_names_for_effects([plus_charge]) contains effect_plus_charge")

	return fails

func _test_resolve_path_math() -> int:
	print("\n-- _resolve_charge_roll math (integration sanity) --")
	# Pure-math check: simulate the bonus addition that _resolve_charge_roll does.
	# Ensures (rolled 2D6) + bonus = expected final total.
	var fails = 0
	var rolled = 7  # base 2D6 sum
	var bonus = EffectPrimitivesData.get_effect_plus_charge({"flags": {"effect_plus_charge": 2}})
	var total = rolled + bonus
	if total != 9:
		print("[FAIL] 7 + bonus(2) = %d expected 9" % total); fails += 1
	else:
		print("[OK]   7 (2D6) + 2 ('ERE WE GO) = 9 final charge total")
	return fails

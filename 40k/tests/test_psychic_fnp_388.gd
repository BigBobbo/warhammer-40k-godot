extends SceneTree

# Issue #388: validate _profile_is_psychic helper + FNP-vs-psychic gate.
# Run: godot --headless --path . --script tests/test_psychic_fnp_388.gd

func _initialize():
	print("=== Issue #388: PSYCHIC weapon detection + FNP gate ===")
	var fails = 0
	var rules = load("res://autoloads/RulesEngine.gd")

	# Test 1: _profile_is_psychic detects "psychic" in special_rules
	if not rules._profile_is_psychic({"special_rules": "psychic", "type": "Ranged"}):
		print("[FAIL] _profile_is_psychic({special_rules:'psychic'}) = false"); fails += 1
	else:
		print("[OK]   psychic in special_rules detected")

	if not rules._profile_is_psychic({"special_rules": "precision, psychic", "type": "Ranged"}):
		print("[FAIL] _profile_is_psychic compound special_rules failed"); fails += 1
	else:
		print("[OK]   compound 'precision, psychic' detected")

	if rules._profile_is_psychic({"special_rules": "rapid fire 1", "type": "Ranged"}):
		print("[FAIL] _profile_is_psychic non-psychic returned true"); fails += 1
	else:
		print("[OK]   non-psychic special_rules ignored")

	if not rules._profile_is_psychic({"keywords": ["PSYCHIC"], "type": "Melee"}):
		print("[FAIL] _profile_is_psychic keyword variant failed"); fails += 1
	else:
		print("[OK]   PSYCHIC keyword detected")

	# Test 2: get_unit_fnp_for_attack with is_psychic=true reads psychic_mortal flag
	var unit = {"flags": {"effect_fnp_psychic_mortal": 3}}
	var fnp_psychic = rules.get_unit_fnp_for_attack(unit, true)
	if fnp_psychic != 3:
		print("[FAIL] get_unit_fnp_for_attack(daughters, psychic=true) = %d" % fnp_psychic); fails += 1
	else:
		print("[OK]   get_unit_fnp_for_attack(daughters, psychic=true) = 3")

	var fnp_nonpsychic = rules.get_unit_fnp_for_attack(unit, false)
	if fnp_nonpsychic != 0:
		print("[FAIL] get_unit_fnp_for_attack(daughters, psychic=false) = %d" % fnp_nonpsychic); fails += 1
	else:
		print("[OK]   get_unit_fnp_for_attack(daughters, psychic=false) = 0 (no unconditional)")

	if fails == 0:
		print("\n[OK] all #388 validations passed")
		quit(0)
	else:
		print("\n[FAIL] %d validation(s) failed" % fails)
		quit(1)

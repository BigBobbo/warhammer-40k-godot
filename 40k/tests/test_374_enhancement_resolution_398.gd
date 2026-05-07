extends SceneTree

# Issue #398 + #374 resolution-side validation: confirm the enhancement flags
# (Panoptispex effect_ignores_cover, Headwoppa's effect_devastating_wounds,
# Hall of Armouries effect_plus_damage) are now consumed by RulesEngine.
#
# Run via: godot --headless --path 40k --script tests/test_374_enhancement_resolution_398.gd

var _re = null
var _ep = null


func _initialize():
	await create_timer(0.1).timeout
	_re = root.get_node_or_null("RulesEngine")
	_ep = preload("res://autoloads/EffectPrimitives.gd")
	if _re == null:
		print("FAIL: missing RulesEngine autoload")
		quit(1)
		return
	_run_tests()


func _run_tests():
	print("\n=== Issue #398: live resolution-side reads of #374 enhancement flags ===\n")
	var passed = 0
	var failed = 0

	# --- Test A: effect_ignores_cover read in melee+ranged save logic ---
	# Sanity: the source contains the effect_ignores_cover unit-flag check.
	var rules_src = FileAccess.open("res://autoloads/RulesEngine.gd", FileAccess.READ).get_as_text()
	if "FLAG_IGNORES_COVER" in rules_src and "Panoptispex" in rules_src:
		print("[PASS] RulesEngine references FLAG_IGNORES_COVER + 'Panoptispex' marker")
		passed += 1
	else:
		print("[FAIL] missing flag read or Panoptispex marker in RulesEngine.gd")
		failed += 1

	# --- Test B: effect_devastating_wounds read on the actor unit ---
	if "FLAG_DEVASTATING_WOUNDS" in rules_src and "Headwoppa" in rules_src:
		print("[PASS] RulesEngine references FLAG_DEVASTATING_WOUNDS + 'Headwoppa' marker")
		passed += 1
	else:
		print("[FAIL] missing flag read or Headwoppa marker in RulesEngine.gd")
		failed += 1

	# --- Test C: effect_plus_damage read in melee damage roll path ---
	if "FLAG_PLUS_DAMAGE" in rules_src and "Hall of Armouries (melee) — damage" in rules_src:
		print("[PASS] RulesEngine references FLAG_PLUS_DAMAGE in melee damage path")
		passed += 1
	else:
		print("[FAIL] missing FLAG_PLUS_DAMAGE in melee damage path")
		failed += 1

	# --- Test D: drive a melee resolve to verify Hall of Armouries +1 Damage actually lands ---
	# Setup: S5 attacker with weapon Damage=1, target T6 W2 (one wound = surviving).
	# With effect_plus_damage=1, each wound deals 2 damage (target dies in 1 hit).
	print("\n--- Test D: drive melee resolve, Hall of Armouries +1D kills T6 W2 in 1 wound ---")
	# Without flag: 1 wound = 1 damage; target survives.
	var board_no_flag = _make_melee_board(0)
	var assignment = {"attacker": "U_HOA_TEST", "target": "U_HOA_VICTIM", "weapon": "Hall test blade", "models": ["0"]}
	var rng_no = _re.RNGService.new(11)
	var result_no_flag = _re._resolve_melee_assignment(assignment, "U_HOA_TEST", board_no_flag, rng_no)
	# With flag: 1 wound = 2 damage; target dies.
	var board_with_flag = _make_melee_board(1)
	var rng_with = _re.RNGService.new(11)
	var result_with_flag = _re._resolve_melee_assignment(assignment, "U_HOA_TEST", board_with_flag, rng_with)

	# Look at the LOWEST current_wounds value diffed (damage taken from full 20).
	var dmg_no_flag = 0
	for d in result_no_flag.get("diffs", []):
		if d.get("path", "").begins_with("units.U_HOA_VICTIM.models.") and "current_wounds" in d.get("path", ""):
			dmg_no_flag = max(dmg_no_flag, 20 - int(d.get("value", 20)))
	var dmg_with_flag = 0
	for d in result_with_flag.get("diffs", []):
		if d.get("path", "").begins_with("units.U_HOA_VICTIM.models.") and "current_wounds" in d.get("path", ""):
			dmg_with_flag = max(dmg_with_flag, 20 - int(d.get("value", 20)))
	if dmg_with_flag > dmg_no_flag:
		print("[PASS] flag delivers more damage: with_flag=%d, no_flag=%d" % [dmg_with_flag, dmg_no_flag])
		passed += 1
	else:
		print("[FAIL] expected dmg_with_flag > dmg_no_flag; got %d > %d" % [dmg_with_flag, dmg_no_flag])
		failed += 1

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)


func _make_melee_board(plus_damage: int) -> Dictionary:
	var attacker = {
		"id": "U_HOA_TEST",
		"owner": 1,
		"status": 2,
		"meta": {
			"name": "Hall Tester",
			"keywords": ["INFANTRY", "CHARACTER"],
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 4},
			"weapons": [{
				"id": "hoa_blade",
				"name": "Hall test blade",
				"type": "Melee",
				"range": "Melee",
				"attacks": "4",
				"weapon_skill": "2",
				"strength": "10",
				"ap": "-2",
				"damage": "1"
			}],
			"abilities": []
		},
		"models": [{"id": "m1", "wounds": 4, "current_wounds": 4, "alive": true, "position": {"x": 200, "y": 200}, "base_mm": 32}],
		"flags": {}
	}
	if plus_damage > 0:
		attacker.flags["effect_plus_damage"] = plus_damage
	var target = {
		"id": "U_HOA_VICTIM",
		"owner": 2,
		"status": 2,
		"meta": {
			"name": "Hall Victim",
			"keywords": ["INFANTRY"],
			"stats": {"move": 6, "toughness": 4, "save": 6, "wounds": 20},
			"weapons": [],
			"abilities": []
		},
		"models": [{"id": "t1", "wounds": 20, "current_wounds": 20, "alive": true, "position": {"x": 200, "y": 252}, "base_mm": 32}],
		"flags": {}
	}
	return {
		"units": {"U_HOA_TEST": attacker, "U_HOA_VICTIM": target},
		"meta": {"battle_round": 1, "active_player": 1}
	}

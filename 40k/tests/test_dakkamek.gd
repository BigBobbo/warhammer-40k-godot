extends SceneTree

# Speedwaaagh! Dakkamek (Mek): when the bearer uses its Mekaniak ability, the
# selected Vehicle's ranged weapons gain [RAPID FIRE 1] until the start of the
# next turn. Modelled as a dakkamek_rapid_fire flag on the vehicle, read in the
# shooting resolution's Rapid Fire step (both the staged and auto-resolve paths)
# and cleared with the Mekaniak buff.
#
# Proven by shooting a non-Rapid-Fire weapon (bolt_rifle, A2) from within half
# range: the flag adds +1 attack per model.
#
# Run: godot --headless --path 40k --script tests/test_dakkamek.gd

var _passed = 0
var _failed = 0


func _initialize():
	await create_timer(0.2).timeout
	_run()
	print("\n=== RESULTS: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[PASS] %s" % label)
		_passed += 1
	else:
		print("[FAIL] %s" % label)
		_failed += 1


func _board(shooter_flags: Dictionary) -> Dictionary:
	var shooters = []
	for i in range(4):
		shooters.append({"id": "ms%d" % i, "position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 60, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var targets = []
	for i in range(4):
		targets.append({"id": "mt%d" % i, "position": {"x": 300.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 4, "save": 4}})
	return {"units": {
		"U_SHOOTER": {"id": "U_SHOOTER", "owner": 1,
			"meta": {"keywords": ["VEHICLE", "ORKS"], "stats": {"toughness": 8, "save": 3, "wounds": 10}, "abilities": []},
			"flags": shooter_flags, "models": shooters},
		"U_TARGET": {"id": "U_TARGET", "owner": 2,
			"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 2}, "abilities": []},
			"flags": {}, "models": targets}
	}, "meta": {"phase": 8, "active_player": 1, "battle_round": 1}}


func _attacks(flags: Dictionary, seed_val: int) -> int:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{"weapon_id": "bolt_rifle", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1", "ms2", "ms3"]}]}}
	var res = rules.resolve_shoot(action, _board(flags), rng)
	# Count total to-hit dice rolled = total attacks made (record uses rolls_raw).
	var n := 0
	for d in res.get("dice", []):
		if "to_hit" in str(d.get("context", "")):
			var raw = d.get("rolls_raw", d.get("rolls_modified", []))
			n += int(raw.size())
	return n


func _run():
	# bolt_rifle is A2 with no Rapid Fire; 4 shooters in half range -> 8 base attacks.
	var base = _attacks({}, 20)
	var with_dakkamek = _attacks({"dakkamek_rapid_fire": true}, 20)
	print("  attacks: base=%d  dakkamek=%d" % [base, with_dakkamek])
	_check("baseline: 4 shooters x A2 = 8 attacks", base == 8)
	_check("Dakkamek grants RAPID FIRE 1: +1 attack per model in half range (8 -> 12)",
		with_dakkamek == base + 4)

	# A native Rapid Fire weapon shouldn't be double-counted (flag only fills in when < 1).
	# (Sanity: with no flag and a plain weapon, no rapid fire.)
	_check("no flag -> no rapid fire bonus", _attacks({}, 20) == 8)

	# The Mekaniak trigger only grants Dakkamek when the Mek bears the enhancement.
	# Verify the detection gate that MovementPhase uses (it appends the
	# dakkamek_rapid_fire change beside the already-validated mekaniak_buffed one).
	var GS = root.get_node("GameState")
	GS.state["units"] = {
		"U_MEK": {"id": "U_MEK", "owner": 1, "meta": {"name": "Big Mek", "keywords": ["CHARACTER", "MEK"],
			"enhancements": ["Dakkamek"]}, "flags": {}, "models": []},
		"U_MEK_PLAIN": {"id": "U_MEK_PLAIN", "owner": 1, "meta": {"name": "Mek", "keywords": ["CHARACTER", "MEK"],
			"enhancements": []}, "flags": {}, "models": []},
	}
	var mp = load("res://phases/MovementPhase.gd").new()
	mp.game_state_snapshot = GS.state
	root.add_child(mp)
	_check("Mek with Dakkamek is detected", mp._unit_has_enhancement("U_MEK", "Dakkamek"))
	_check("Mek without Dakkamek is not", not mp._unit_has_enhancement("U_MEK_PLAIN", "Dakkamek"))
	mp.queue_free()

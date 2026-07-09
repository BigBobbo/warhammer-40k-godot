extends SceneTree

# Speedwaaagh! MOBILE DAKKASTORM: mark one enemy unit; until end of phase, each
# attack from the user's SPEED FREEKS/TRUKK units targeting it gets +2 Strength.
# Modelled as a mobile_dakkastorm_marked flag on the enemy, read in the ranged
# Strength step (both shooting paths) gated on attacker keyword + owner.
#
# Proven by shooting bolt_rifle (S4) vs a T5 target: +2 S improves the wound
# roll, so a SPEED FREEKS shooter lands more wounds when the enemy is marked —
# but a non-Speed-Freeks shooter does not.
#
# Run: godot --headless --path 40k --script tests/test_mobile_dakkastorm.gd

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


func _sum_wounds(result: Dictionary) -> int:
	var total := 0
	for d in result.get("dice", []):
		if "wound" in str(d.get("context", "")).to_lower() and d.has("successes"):
			total += int(d.get("successes", 0))
	return total


func _board(shooter_keywords: Array, marked: bool) -> Dictionary:
	var shooters = []
	for i in range(10):
		shooters.append({"id": "ms%d" % i, "position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 40, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var targets = []
	for i in range(1):
		targets.append({"id": "mt%d" % i, "position": {"x": 200.0, "y": 0.0},
			"base_mm": 60, "base_type": "circular", "alive": true, "wounds": 20, "current_wounds": 20,
			"stats": {"toughness": 5, "save": 3}})
	var tflags := {}
	if marked:
		tflags["mobile_dakkastorm_marked"] = true
	return {"units": {
		"U_SHOOTER": {"id": "U_SHOOTER", "owner": 1,
			"meta": {"keywords": shooter_keywords, "stats": {"toughness": 5, "save": 6, "wounds": 1}, "abilities": []},
			"flags": {}, "models": shooters},
		"U_ENEMY": {"id": "U_ENEMY", "owner": 2,
			"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 5, "save": 3, "wounds": 20}, "abilities": []},
			"flags": tflags, "models": targets}
	}, "meta": {"phase": 8, "active_player": 1, "battle_round": 1}}


func _shoot(shooter_keywords: Array, marked: bool, seed_val: int) -> int:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{"weapon_id": "bolt_rifle", "target_unit_id": "U_ENEMY",
			"model_ids": ["ms0","ms1","ms2","ms3","ms4","ms5","ms6","ms7","ms8","ms9"]}]}}
	return _sum_wounds(rules.resolve_shoot(action, _board(shooter_keywords, marked), rng))


func _run():
	var seeds = [11, 42, 77]

	print("=== SPEED FREEKS shooter: +2 S vs a marked enemy (bolt_rifle S4 vs T5) ===")
	var sf_better := 0
	for s in seeds:
		var off = _shoot(["SPEED FREEKS", "ORKS"], false, s)
		var on = _shoot(["SPEED FREEKS", "ORKS"], true, s)
		print("  seed %d: wounds unmarked=%d marked=%d" % [s, off, on])
		if on > off:
			sf_better += 1
		_check("seed %d: mark does not reduce wounds" % s, on >= off)
	_check("Speed Freeks land more wounds vs a marked enemy on most seeds", sf_better >= 2)

	print("\n=== non-Speed-Freeks shooter: mark has no effect (keyword gate) ===")
	for s in seeds:
		var off = _shoot(["INFANTRY", "ORKS"], false, s)
		var on = _shoot(["INFANTRY", "ORKS"], true, s)
		_check("seed %d: non-Speed-Freeks unaffected by the mark" % s, on == off)

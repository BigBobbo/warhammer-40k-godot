extends SceneTree

# ISS-042 (step 1): edition-aware coherency check.
# 10e: 2" of >=1 model (>=2 when 7+ models). 11e 03.03: 2" of one AND
# within 9" of EVERY other model.
#
# Usage: godot --headless --path . -s tests/test_iss042_coherency_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _m(id: String, x_inches: float) -> Dictionary:
	return {"id": id, "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": 200 + x_inches * 40.0, "y": 200}}

func _unit(models: Array) -> Dictionary:
	return {"models": models}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss042_coherency_11e ===\n")
	# 32mm base ~0.63" radius; edge gap = center gap - 1.26".
	# Chain spacing 2.5" centers => ~1.24" edge gaps (coherent links).
	var chain := []
	for i in range(4):
		chain.append(_m("c%d" % i, i * 2.5))

	print("-- 10e --")
	GameConstants.edition = 10
	var r = AttackSequence.check_unit_coherency(_unit(chain))
	_check("10e: 2.5\"-center chain of 4 coherent", r.coherent, str(r))
	# 10e RAW quirk: per-model neighbor checks allow a unit to split into
	# two "islands" — each model has a neighbor, so RAW says coherent. The
	# 11e 9" envelope (03.03) is what closes this hole.
	var split = [_m("a", 0.0), _m("b", 1.0), _m("c", 10.0), _m("d", 11.0)]
	r = AttackSequence.check_unit_coherency(_unit(split))
	_check("10e RAW: split islands count as coherent (documented quirk)", r.coherent, str(r))
	GameConstants.edition = 11
	r = AttackSequence.check_unit_coherency(_unit(split))
	_check("11e: the same split unit is INcoherent via the 9-inch envelope", not r.coherent, str(r))
	GameConstants.edition = 10
	var seven := []
	for i in range(7):
		seven.append(_m("s%d" % i, i * 2.5))
	r = AttackSequence.check_unit_coherency(_unit(seven))
	_check("10e: 7-model straight chain breaks the 2-neighbor rule at the ends",
		not r.coherent and "s0" in r.offenders, str(r))

	print("\n-- 11e (03.03) --")
	GameConstants.edition = 11
	r = AttackSequence.check_unit_coherency(_unit(chain))
	_check("11e: chain of 4 within 9\" envelope coherent (ends 7.5\" apart)", r.coherent, str(r))
	var long_chain := []
	for i in range(6):
		long_chain.append(_m("l%d" % i, i * 2.4))  # ends 12\" apart centers
	r = AttackSequence.check_unit_coherency(_unit(long_chain))
	_check("11e: linked chain whose ends exceed 9\" is INcoherent (envelope)",
		not r.coherent and ("l0" in r.offenders and "l5" in r.offenders), str(r))
	GameConstants.edition = 10
	r = AttackSequence.check_unit_coherency(_unit(long_chain.slice(0, 6)))
	# 10e has no envelope: 6-model chain with 1.14\" edge links and only 1
	# neighbor needed... 6 models < 7 so 1 neighbor suffices -> coherent
	_check("10e: the same long chain IS coherent (no envelope rule)", r.coherent, str(r))

	_check("single model always coherent",
		AttackSequence.check_unit_coherency(_unit([_m("solo", 0)])).coherent)

	print("\n-- end-of-turn enforcement (03.03 Regaining Coherency) --")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var prev_state = gs.state.duplicate(true)
	gs.initialize_default_state()
	var split_models = [_m("k0", 0.0), _m("k1", 1.0), _m("k2", 12.0)]
	gs.state["units"] = {"U_SPLIT": {"id": "U_SPLIT", "owner": 1, "flags": {},
		"meta": {"name": "Split", "keywords": ["INFANTRY"], "stats": {}},
		"models": split_models}}
	GameConstants.edition = 11
	pm.run_turn_ending_hooks(1)
	var u = gs.state["units"]["U_SPLIT"]
	var alive_after := 0
	for m in u.models:
		if m.get("alive", true):
			alive_after += 1
	var coh_after = AttackSequence.check_unit_coherency(u)
	_check("11e: minimal removal — the isolated straggler goes, pair stays",
		alive_after == 2 and coh_after.coherent,
		"alive=%d coherent=%s" % [alive_after, str(coh_after)])
	_check("removed model destroyed (alive=false, wounds 0)",
		u.models[2].get("alive", true) == false and int(u.models[2].get("current_wounds", 1)) == 0)
	# Edition 10: untouched
	gs.state["units"]["U_SPLIT"]["models"] = [_m("k0", 0.0), _m("k1", 1.0), _m("k2", 12.0)]
	GameConstants.edition = 10
	pm.run_turn_ending_hooks(1)
	var alive10 := 0
	for m in gs.state["units"]["U_SPLIT"].models:
		if m.get("alive", true):
			alive10 += 1
	_check("10e: no end-of-turn removal", alive10 == 3)
	gs.state = prev_state

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

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

	print("\n-- 19.03 attached unit: coherency is judged on the WHOLE Attached unit --")
	# User report 2026-08-03: a Custodian Guard squad led by a Blade Champion was
	# flagged out of coherency at End of Turn even though nothing had been moved
	# by hand. The straggler was within 2" of the CHARACTER, so the pile-in /
	# consolidate validators (which merge the Attached unit per 19.03) approved
	# the move — but the End of Turn hook measured the bodyguard ALONE and
	# demanded a removal.
	GameConstants.edition = 11
	# 32mm bases => edge gap = centre gap - 1.26". Bodyguard m1..m4 form a block
	# ending at 3.6"; m5 sits at 7.2", i.e. 2.34" edge from its nearest SQUADMATE
	# (out of coherency measured alone) but 0.74" edge from the Blade Champion
	# at 5.2", which is itself 0.34" edge from m4 — a legal 19.03 chain.
	gs.state["units"] = {
		"U_GUARD": {
			"id": "U_GUARD", "owner": 1, "flags": {},
			"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY"], "stats": {}},
			"attachment_data": {"attached_characters": ["U_CHAMPION"]},
			"models": [_m("m1", 0.0), _m("m2", 1.2), _m("m3", 2.4), _m("m4", 3.6), _m("m5", 7.2)],
		},
		"U_CHAMPION": {
			"id": "U_CHAMPION", "owner": 1, "flags": {}, "attached_to": "U_GUARD",
			"meta": {"name": "Blade Champion", "keywords": ["INFANTRY", "CHARACTER"], "stats": {}},
			"models": [_m("m1", 5.2)],
		},
	}
	var bodyguard_alone = AttackSequence.check_unit_coherency(gs.state["units"]["U_GUARD"])
	_check("regression pin: measured ALONE the bodyguard looks incoherent (the reported bug)",
		not bodyguard_alone.coherent and "m5" in bodyguard_alone.offenders, str(bodyguard_alone))
	var grp = AttackSequence.coherency_group_ids("U_GUARD", gs.state["units"])
	_check("coherency_group_ids(bodyguard) = [bodyguard, character]",
		grp == ["U_GUARD", "U_CHAMPION"], str(grp))
	_check("coherency_group_ids(attached character) resolves to the same group",
		AttackSequence.coherency_group_ids("U_CHAMPION", gs.state["units"]) == ["U_GUARD", "U_CHAMPION"])
	var attached = AttackSequence.check_attached_unit_coherency("U_GUARD", gs.state["units"])
	_check("19.03: the Attached unit IS coherent — the character bridges the gap",
		attached.coherent, str(attached))
	_check("the standalone reading still records m5 (the disagreement is logged, not acted on)",
		"U_GUARD|m5" in attached.solo_offenders and not ("U_GUARD|m5" in attached.merged_offenders),
		str(attached))
	_check("attached check merges every component's models (5 + 1)",
		int(attached.model_count) == 6, str(attached.model_count))
	pm.run_turn_ending_hooks(1)
	var guard_alive := 0
	for m in gs.state["units"]["U_GUARD"].models:
		if m.get("alive", true):
			guard_alive += 1
	_check("End of Turn destroys NOTHING for a coherent Attached unit", guard_alive == 5,
		"alive=%d" % guard_alive)

	# ...and it still catches a genuinely stranded model: push m5 out past the
	# character's reach too.
	gs.state["units"]["U_GUARD"]["models"][4] = _m("m5", 9.0)
	var stranded = AttackSequence.check_attached_unit_coherency("U_GUARD", gs.state["units"])
	_check("19.03: a model out of reach of the character too IS still an offender",
		not stranded.coherent
			and stranded.offenders.size() == 1
			and stranded.offenders[0].unit_id == "U_GUARD"
			and stranded.offenders[0].model_id == "m5",
		str(stranded))
	pm.run_turn_ending_hooks(1)
	_check("End of Turn removes the genuinely stranded model (and only it)",
		gs.state["units"]["U_GUARD"].models[4].get("alive", true) == false
			and gs.state["units"]["U_GUARD"].models[0].get("alive", true) == true
			and gs.state["units"]["U_CHAMPION"].models[0].get("alive", true) == true)

	# The mirror-image false positive: a long mob whose leader stands off one
	# end. The mob satisfies the 9" envelope on its own (MovementPhase validates
	# it exactly that way and put the models there), but folding the leader in
	# adds a model the far end is >9" from. Measured on the audit_374_kunnin
	# save this condemned three whole Boyz mobs — 43 models the game had just
	# approved. The merged reading alone must NOT destroy them.
	var mob_models := []
	for i in range(7):
		mob_models.append(_m("b%d" % i, i * 1.6))  # ends 9.6" apart centres => 8.34" edge, inside the envelope
	gs.state["units"] = {
		"U_MOB": {
			"id": "U_MOB", "owner": 1, "flags": {},
			"meta": {"name": "Boyz", "keywords": ["INFANTRY"], "stats": {}},
			"attachment_data": {"attached_characters": ["U_WARBOSS"]},
			"models": mob_models,
		},
		"U_WARBOSS": {
			"id": "U_WARBOSS", "owner": 1, "flags": {}, "attached_to": "U_MOB",
			"meta": {"name": "Warboss", "keywords": ["INFANTRY", "CHARACTER"], "stats": {}},
			"models": [_m("m1", -1.4)],  # off the near end: 11" centres from b6 => 9.74" edge, outside it
		},
	}
	var mob = AttackSequence.check_attached_unit_coherency("U_MOB", gs.state["units"])
	_check("the leader standing off one end breaks the merged 9\" envelope",
		mob.merged_offenders.size() > 0, str(mob.merged_offenders))
	_check("...but the mob is coherent on its own, so nothing is destroyed",
		mob.coherent and mob.solo_offenders.is_empty(), str(mob))
	pm.run_turn_ending_hooks(1)
	var mob_alive := 0
	for m in gs.state["units"]["U_MOB"].models:
		if m.get("alive", true):
			mob_alive += 1
	_check("End of Turn leaves the whole mob alive", mob_alive == 7, "alive=%d" % mob_alive)

	print("\n-- measurement tolerance parity with the UI helpers --")
	# Every coherency affordance the player sees (movement ghost, deployment
	# circle, pile-in helper) allows 2" + Measurement.DISTANCE_TOLERANCE_INCHES.
	# The engine check used a bare 2", so a model auto-snapped to exactly 2.0"
	# could render "in range" and still be destroyed at End of Turn.
	# Autoloads are not compile-time identifiers in a bare `godot -s` run.
	var meas = root.get_node("/root/Measurement")
	var tol_gap: float = 2.0 + 1.26 + meas.DISTANCE_TOLERANCE_INCHES * 0.6  # centers: 2" edge gap + 32mm bases
	var edge_pair = _unit([_m("t0", 0.0), _m("t1", tol_gap)])
	_check("engine accepts what Measurement.is_within_coherency accepts",
		AttackSequence.check_unit_coherency(edge_pair).coherent
			== meas.is_within_coherency(edge_pair.models[0], edge_pair.models[1]),
		"engine=%s ui=%s" % [str(AttackSequence.check_unit_coherency(edge_pair).coherent),
			str(meas.is_within_coherency(edge_pair.models[0], edge_pair.models[1]))])
	_check("a clearly-too-far pair is still incoherent",
		not AttackSequence.check_unit_coherency(_unit([_m("f0", 0.0), _m("f1", 5.0)])).coherent)

	gs.state = prev_state

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

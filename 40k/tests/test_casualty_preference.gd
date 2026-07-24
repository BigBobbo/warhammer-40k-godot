extends SceneTree

# CASUALTY PREFERENCE (2026-07): smart defender casualty ordering for
# auto-allocation (AI defenders + the computer-allocates setting).
# Coverage:
#   A) proximity: models closest to the enemy die first
#   B) value: sergeant-type + special-weapon carriers are the last picks,
#      even when they stand closest to the enemy
#   C) objective control: models keeping a contested marker die last, and
#      the coherency guard removes end models before bridge models
#   D) positionless boards degrade to value-only ordering (no crash)
#   E) engine integration: resolve_allocation_batch_11e kills the
#      computed order's bases; engine_auto_preference gates on AI defender
#
# Usage: godot --headless --path . -s tests/test_casualty_preference.gd

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
	create_timer(0.1).timeout.connect(_run_tests)

func _model(id: String, x, y, extra: Dictionary = {}) -> Dictionary:
	var m = {"id": id, "alive": true, "wounds": 1, "current_wounds": 1,
		"base_mm": 32, "base_type": "circular",
		"position": null if x == null else {"x": float(x), "y": float(y)}}
	for k in extra:
		m[k] = extra[k]
	return m

func _enemy_unit(id: String, positions: Array, oc: int = 2) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append(_model("e%d" % (i + 1), positions[i][0], positions[i][1]))
	return {"id": id, "owner": 1, "flags": {},
		"meta": {"name": id, "keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 3, "wounds": 2, "objective_control": oc}},
		"models": models}

func _state_with(units: Dictionary, objectives: Array = []) -> Dictionary:
	return {"units": units, "board": {"objectives": objectives},
		"meta": {}, "players": {"1": {"cp": 3}, "2": {"cp": 3}}}

func _save_data(wounds: int, target_id: String) -> Dictionary:
	return {
		"target_unit_id": target_id, "target_unit_name": target_id,
		"shooter_unit_id": "U_ENEMY", "weapon_name": "Test Cannon",
		"wounds_to_save": wounds, "total_wounds": wounds,
		"ap": -10, "damage": 1, "damage_raw": "1", "base_save": 5,
		"is_psychic": false, "has_devastating_wounds": false, "devastating_wounds": 0,
		"melta_bonus": 0,
	}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_casualty_preference ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	_check("RulesEngine autoload present", rules != null)
	var edition_before = GameConstants.edition
	GameConstants.edition = 11

	# ── A) proximity: closest to the enemy dies first ──────────────────
	print("-- A) closest models die first --")
	var boyz_models = []
	for i in range(5):
		# a 1.5"-spaced line; the enemy stands to the RIGHT (x=760) so m5
		# (x=540) is the closest and m1 (x=300) the farthest
		boyz_models.append(_model("m%d" % (i + 1), 300 + i * 60, 400))
	var boyz = {"id": "U_BOYZ", "owner": 2, "flags": {},
		"meta": {"name": "Boyz", "keywords": ["INFANTRY"],
			"stats": {"toughness": 5, "save": 5, "wounds": 1, "objective_control": 2}},
		"models": boyz_models}
	var state_a = _state_with({"U_BOYZ": boyz, "U_ENEMY": _enemy_unit("U_ENEMY", [[760, 400]])})
	var order_a = CasualtyPreference.compute_preferred_targets(boyz, state_a)
	_check("die-first order is closest-first [4,3,2,1,0]",
		str(order_a) == str([4, 3, 2, 1, 0]), str(order_a))

	# ── B) sergeant + special weapon protected despite proximity ───────
	print("\n-- B) sergeant / special weapon are the last picks --")
	var profiles = {
		"squad_sergeant": {"label": "Sergeant", "weapons": ["Boltgun", "Power fist"]},
		"gunner": {"label": "Gunner", "weapons": ["Plasma gun"]},
		"trooper": {"label": "Trooper", "weapons": ["Boltgun"]},
	}
	# tight 2D clump (everyone within 2" of everyone: coherency never binds);
	# the SERGEANT is nearest the enemy, the gunner next — value must win.
	var sq_models = [
		_model("s1", 460, 400, {"model_type": "squad_sergeant"}),
		_model("g1", 410, 430, {"model_type": "gunner"}),
		_model("t1", 410, 370, {"model_type": "trooper"}),
		_model("t2", 360, 400, {"model_type": "trooper"}),
		_model("t3", 310, 400, {"model_type": "trooper"}),
	]
	var squad = {"id": "U_SQUAD", "owner": 2, "flags": {},
		"meta": {"name": "Squad", "keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 3, "wounds": 2, "objective_control": 2},
			"model_profiles": profiles},
		"models": sq_models}
	var state_b = _state_with({"U_SQUAD": squad, "U_ENEMY": _enemy_unit("U_ENEMY", [[600, 400]])})
	var order_b = CasualtyPreference.compute_preferred_targets(squad, state_b)
	_check("troopers die first (t1 closest first)", str(order_b.slice(0, 3)) == str([2, 3, 4]), str(order_b))
	_check("special-weapon gunner is second-last", int(order_b[3]) == 1, str(order_b))
	_check("sergeant is the very last pick", int(order_b[4]) == 0, str(order_b))

	# ── C) objective holders die last; coherency never splits the unit ─
	print("\n-- C) objective control + coherency guard --")
	# chain from the objective (800,400) toward the enemy (900,400):
	# m1..m3 (760/700/640) are inside control range of the marker; the
	# marker is CONTESTED (enemy OC 2 in range too) so they carry the unit's
	# control. m4..m6 (580/520/460) are plain chaff.
	var chain_models = []
	var xs = [760, 700, 640, 580, 520, 460]
	for i in range(xs.size()):
		chain_models.append(_model("m%d" % (i + 1), xs[i], 400))
	var chain = {"id": "U_CHAIN", "owner": 2, "flags": {},
		"meta": {"name": "Chain", "keywords": ["INFANTRY"],
			"stats": {"toughness": 5, "save": 5, "wounds": 1, "objective_control": 2}},
		"models": chain_models}
	var objectives = [{"id": "obj_test", "position": {"x": 800.0, "y": 400.0}, "radius_mm": 40.0}]
	var state_c = _state_with({"U_CHAIN": chain, "U_ENEMY": _enemy_unit("U_ENEMY", [[900, 400]])}, objectives)
	var order_c = CasualtyPreference.compute_preferred_targets(chain, state_c)
	# chaff first — and after m4 (580) dies, removing m5 (520) would strand
	# m6 (460) out of coherency, so the guard takes the END model m6 first.
	_check("chaff dies first, end-before-bridge [3,5,4]",
		str(order_c.slice(0, 3)) == str([3, 5, 4]), str(order_c))
	var tail_c = order_c.slice(3, 6)
	tail_c.sort()
	_check("objective holders are the last three", str(tail_c) == str([0, 1, 2]), str(order_c))
	var sim_remaining = [0, 1, 2, 3, 4, 5]
	var never_split = true
	for k in range(order_c.size() - 2):
		sim_remaining.erase(int(order_c[k]))
		var subset = []
		for idx in sim_remaining:
			subset.append(chain_models[idx])
		if not AttackSequence.check_unit_coherency({"models": subset}).get("coherent", false):
			never_split = false
			break
	_check("sequential removal keeps survivors coherent at every step", never_split)

	# ── D) positionless board: value-only order, no crash ──────────────
	print("\n-- D) positionless models degrade gracefully --")
	var blind_models = [
		_model("b1", null, null, {"model_type": "trooper"}),
		_model("b2", null, null, {"model_type": "squad_sergeant"}),
		_model("b3", null, null, {"model_type": "trooper"}),
	]
	var blind = {"id": "U_BLIND", "owner": 2, "flags": {},
		"meta": {"name": "Blind", "keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 3, "wounds": 2, "objective_control": 2},
			"model_profiles": profiles},
		"models": blind_models}
	var order_d = CasualtyPreference.compute_preferred_targets(blind, _state_with({"U_BLIND": blind}))
	_check("all models ordered", order_d.size() == 3, str(order_d))
	_check("sergeant last even without positions", int(order_d[2]) == 1, str(order_d))

	# ── E) engine integration ──────────────────────────────────────────
	print("\n-- E) resolve_allocation_batch_11e consumes the order --")
	var state_e = _state_with({"U_BOYZ": boyz, "U_ENEMY": _enemy_unit("U_ENEMY", [[760, 400]])})
	var pref_e = CasualtyPreference.compute_preferred_targets(boyz, state_e)
	var batch = rules.resolve_allocation_batch_11e(_save_data(2, "U_BOYZ"), [], state_e,
		rules.RNGService.new(7), {"forced_save_rolls": [1, 1], "preferred_targets": pref_e})
	_check("2 casualties", int(batch.casualties) == 2, str(batch.casualties))
	_check("the two CLOSEST bases died [4,3]",
		str(batch.models_destroyed) == str([4, 3]), str(batch.models_destroyed))

	var ai = root.get_node_or_null("AIPlayer")
	_check("AIPlayer autoload present", ai != null)
	if ai != null:
		var auto_off = CasualtyPreference.engine_auto_preference(boyz, state_e)
		_check("engine_auto_preference is [] for a human defender", auto_off.is_empty(), str(auto_off))
		var enabled_before = ai.enabled
		var players_before = ai.ai_players.duplicate()
		ai.enabled = true
		ai.ai_players[2] = true
		var auto_on = CasualtyPreference.engine_auto_preference(boyz, state_e)
		_check("engine_auto_preference computes for an AI defender",
			str(auto_on) == str([4, 3, 2, 1, 0]), str(auto_on))
		ai.enabled = enabled_before
		ai.ai_players = players_before

	GameConstants.edition = edition_before
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

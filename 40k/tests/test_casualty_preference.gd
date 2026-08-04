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
#   F) terrain-hosted objectives (11e 14.01): the hosting AREA is the
#      objective — a model on the area is protected even when outside the
#      marker radius, and a model inside the radius but OFF the area is not
#   G) coherency DOMINATES the soft score: an already-stranded model is the
#      first casualty (it repairs the unit) even when it is the sergeant
#   H) 19.03: an attached CHARACTER counts as coherency context — the pick
#      that keeps the squad linked through its leader wins, both for the raw
#      target unit (engine auto-resolve) and the folded allocation unit (the
#      overlay's auto mode), and the leader is still the last model picked
#   I) the incremental evaluator agrees with AttackSequence's rule reading
#      for every candidate removal (no drift from the shared 03.03 source)
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

	# ── F) terrain-hosted objective (11e 14.01): area beats radius ──────
	print("\n-- F) terrain-hosted objective uses the hosting area --")
	var tm = root.get_node_or_null("TerrainManager")
	_check("TerrainManager autoload present", tm != null)
	if tm != null:
		var tf_before = tm.terrain_features
		# hosting area: 600..900 × 300..500 around the marker at (800,400).
		tm.terrain_features = [{
			"id": "area_test", "piece_class": "area",
			"polygon": PackedVector2Array([
				Vector2(600, 300), Vector2(900, 300), Vector2(900, 500), Vector2(600, 500)]),
		}]
		# A (idx0): ON the area but OUTSIDE the 3.79" marker radius —
		#   protected ONLY under accurate 14.01 area logic.
		# B (idx1): INSIDE the marker radius but OFF the area — NOT in range
		#   under 14.01 (the area IS the objective), so it is plain chaff.
		# C (idx2): far chaff, on neither.
		var area_models = [
			_model("A", 610, 400),
			_model("B", 950, 400),
			_model("C", 400, 400),
		]
		var area_unit = {"id": "U_AREA", "owner": 2, "flags": {},
			"meta": {"name": "AreaUnit", "keywords": ["INFANTRY"],
				"stats": {"toughness": 5, "save": 5, "wounds": 1, "objective_control": 2}},
			"models": area_models}
		# enemy stands ON the area too (contests it) and is closest to A, so
		# proximity + charge denial actively pull A forward — only the
		# terrain-hosted protection can rank A last.
		var state_f = _state_with(
			{"U_AREA": area_unit, "U_ENEMY": _enemy_unit("U_ENEMY", [[700, 450]])},
			[{"id": "obj_area", "position": {"x": 800.0, "y": 400.0}, "radius_mm": 40.0}])
		var order_f = CasualtyPreference.compute_preferred_targets(area_unit, state_f)
		_check("model ON the area (outside marker radius) dies LAST",
			int(order_f[2]) == 0, str(order_f))
		_check("model inside radius but OFF the area is unprotected chaff",
			int(order_f[0]) == 1, str(order_f))
		_check("full order is [B, C, A]", str(order_f) == str([1, 2, 0]), str(order_f))
		tm.terrain_features = tf_before

	# ── G) coherency dominates: kill the stranded model first ──────────
	print("\n-- G) an already-stranded model is the first casualty --")
	# A chain of three troopers plus a SERGEANT stranded 7.5" off the end
	# (0 squadmates within 2"): 03.03 destroys him at End of Turn whatever we
	# do, so spending an incoming wound on him is free — and it leaves the
	# survivors coherent. The old "first candidate that does not WORSEN
	# coherency" rule took a trooper instead and the unit lost two models.
	var strand_models = [
		_model("t1", 400, 400, {"model_type": "trooper"}),
		_model("t2", 500, 400, {"model_type": "trooper"}),
		_model("t3", 600, 400, {"model_type": "trooper"}),
		_model("sgt", 900, 400, {"model_type": "squad_sergeant"}),
	]
	var strand = {"id": "U_STRAND", "owner": 2, "flags": {},
		"meta": {"name": "Strandy", "keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 3, "wounds": 1, "objective_control": 2}},
		"models": strand_models}
	var state_g = _state_with({"U_STRAND": strand, "U_ENEMY": _enemy_unit("U_ENEMY", [[1200, 400]])})
	var pre_g = AttackSequence.check_unit_coherency(strand)
	_check("setup: the sergeant starts OUT of coherency",
		not pre_g.coherent and "sgt" in pre_g.offenders, str(pre_g))
	var order_g = CasualtyPreference.compute_preferred_targets(strand, state_g)
	_check("the stranded sergeant dies first despite his keep score",
		int(order_g[0]) == 3, str(order_g))
	var survivors_g = []
	for i in [0, 1, 2]:
		survivors_g.append(strand_models[i])
	_check("removing him leaves the survivors coherent",
		AttackSequence.check_unit_coherency({"models": survivors_g}).coherent)

	# ── H) 19.03: the attached CHARACTER is coherency context ──────────
	print("\n-- H) attached leader counts when picking casualties --")
	# Squad strung out into two pairs, bridged ONLY by the attached leader:
	#   g1  g2   [L]   g3  g4     (2.5" centre spacing = 1.24" edge)
	# g2 and g3 are 3.74" apart, so measured ALONE the squad is two islands;
	# 19.03 makes the leader a mate of both, which is why nothing is out of
	# coherency right now. The enemy sits under g2, so g2 is the cheapest
	# model by score — but killing g2 strands g1 for real. g1 is the pick.
	var att_guard_models = [
		_model("g1", 460, 400), _model("g2", 560, 400),
		_model("g3", 760, 400), _model("g4", 860, 400),
	]
	var att_guard = {"id": "U_GUARD", "owner": 2, "flags": {},
		"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY"],
			"stats": {"toughness": 6, "save": 2, "wounds": 3, "objective_control": 2}},
		"attachment_data": {"attached_characters": ["U_LEADER"]},
		"models": att_guard_models}
	var att_leader = {"id": "U_LEADER", "owner": 2, "flags": {}, "attached_to": "U_GUARD",
		"meta": {"name": "Blade Champion", "keywords": ["INFANTRY", "CHARACTER"],
			"stats": {"toughness": 6, "save": 2, "wounds": 5, "objective_control": 1}},
		"models": [_model("L", 660, 400)]}
	var state_h = _state_with({"U_GUARD": att_guard, "U_LEADER": att_leader,
		"U_ENEMY": _enemy_unit("U_ENEMY", [[560, 700]])})
	var att_units = state_h.units
	_check("setup: nothing is out of coherency while the leader bridges the squad",
		AttackSequence.check_attached_unit_coherency("U_GUARD", att_units).coherent)
	# The discriminator: measured WITHOUT the leader, killing g1 and killing g2
	# look equally bad (each strands the other's islandmate), so a leader-blind
	# picker falls through to the keep score and takes g2 — the one that really
	# does strand a model. With the leader in the reading only g2 breaks.
	var _solo_after = func(dead: int) -> int:
		var subset := []
		for i in range(att_guard_models.size()):
			if i != dead:
				subset.append(att_guard_models[i])
		return AttackSequence.check_unit_coherency({"models": subset}).offenders.size()
	var _attached_after = func(dead: int) -> int:
		var was = att_guard_models[dead].get("alive", true)
		att_guard_models[dead]["alive"] = false
		var n: int = AttackSequence.check_attached_unit_coherency("U_GUARD", att_units).offenders.size()
		att_guard_models[dead]["alive"] = was
		return n
	_check("setup: leader-blind, killing g1 and killing g2 score the same (1 offender each)",
		_solo_after.call(0) == 1 and _solo_after.call(1) == 1,
		"g1=%d g2=%d" % [_solo_after.call(0), _solo_after.call(1)])
	_check("setup: leader-aware, only killing g2 actually breaks coherency",
		_attached_after.call(0) == 0 and _attached_after.call(1) == 1,
		"g1=%d g2=%d" % [_attached_after.call(0), _attached_after.call(1)])
	var order_h = CasualtyPreference.compute_preferred_targets(att_guard, state_h)
	_check("the pick that keeps everyone linked wins over the cheapest model (g1, not g2)",
		int(order_h[0]) == 0, str(order_h))
	# What the engine will actually do once that model is gone.
	att_guard_models[0]["alive"] = false
	_check("after the pick the whole Attached unit is still coherent",
		AttackSequence.check_attached_unit_coherency("U_GUARD", att_units).coherent,
		str(AttackSequence.check_attached_unit_coherency("U_GUARD", att_units).offenders))
	att_guard_models[0]["alive"] = true

	# Same board through the OVERLAY's shape: the folded allocation unit, where
	# the leader's model is a candidate too (and 05.04 keeps him last).
	var folded = rules._build_attached_allocation_unit_11e("U_GUARD", state_h).unit
	_check("folded allocation unit carries all 5 models", folded.models.size() == 5, str(folded.models.size()))
	var order_h2 = CasualtyPreference.compute_preferred_targets(folded, state_h, {"defender_player": 2})
	_check("folded unit reaches the same first pick", int(order_h2[0]) == 0, str(order_h2))
	_check("the attached CHARACTER is still the very last pick (05.04)",
		int(order_h2[4]) == 4, str(order_h2))

	# ── I) the fast evaluator matches the shared rule reading ──────────
	print("\n-- I) incremental evaluator == AttackSequence's 03.03 reading --")
	var cm = CasualtyPreference._build_coherency_model(att_guard, state_h)
	var drift = []
	for i in range(att_guard_models.size()):
		var fast: int = cm.offenders_without(i)
		var was = att_guard_models[i].get("alive", true)
		att_guard_models[i]["alive"] = false
		var slow: int = AttackSequence.check_attached_unit_coherency("U_GUARD", att_units).offenders.size()
		att_guard_models[i]["alive"] = was
		if fast != slow:
			drift.append("kill %d: fast=%d slow=%d" % [i, fast, slow])
	_check("every candidate removal agrees with check_attached_unit_coherency",
		drift.is_empty(), str(drift))

	var ai = root.get_node_or_null("AIPlayer")
	_check("AIPlayer autoload present", ai != null)
	if ai != null:
		# "Computer allocates wounds" persists to user://settings.cfg, and the
		# windowed scenarios flip it — pin it OFF here rather than inheriting
		# whatever the last run on this machine left behind.
		var ss = root.get_node_or_null("SettingsService")
		var auto_setting_before = ss.get_auto_allocate_wounds() if ss != null else false
		if ss != null:
			ss.set_auto_allocate_wounds(false)
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
		# The 'Computer allocates wounds' setting also reaches a HUMAN defender.
		if ss != null:
			ss.set_auto_allocate_wounds(true)
			var human_auto = CasualtyPreference.engine_auto_preference(boyz, state_e)
			_check("engine_auto_preference computes for a human who delegated allocation",
				str(human_auto) == str([4, 3, 2, 1, 0]), str(human_auto))
			ss.set_auto_allocate_wounds(auto_setting_before)

	GameConstants.edition = edition_before
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

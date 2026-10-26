extends SceneTree

# Behavioral regressions for the core-rules audit of commit e28e4f7 (handoff
# 2026-10-11). Each section reproduces one ranked defect through the REAL
# server-side pipeline (phase execute_action / RulesEngine resolvers) and
# asserts the legal 11th-edition outcome. Only APIs that already existed at
# e28e4f7 are used, so the same file runs against the pre-fix tree and shows
# exactly which assertions the fixes turned green.
#
#   P0-2  Fight 12.04  — END_FIGHT cannot forfeit mandatory fights.
#   P1-5  Move 09.02   — every unit is selected before the Move Units step
#                        ends; an unselected unit remains stationary (09.04).
#   P0-1  Shoot 10.07  — the SELECTED indirect shooting type drives cover,
#                        no hit re-rolls and the 1-5 fail band (visible target).
#   P1-3  Saves 05.03-05.04 — automatic saves allocate through the 11e
#                        grouped allocation (damage stays on a wounded model).
#   P1-4  Transport 18.05 — emergency disembark only places models legally
#                        (on the board, off terrain/models, wholly within 6",
#                        out of engagement range) and destroys the rest.
#
# Usage: godot --headless --path . -s tests/test_core_rules_audit_e28e4f7.gd

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

# 40px = 1"; a 25mm base has a ~19.7px radius.
func _unit(id: String, owner: int, x: float, y: float, flags: Dictionary = {}, keywords: Array = ["INFANTRY"], n_models: int = 1, wounds: int = 2) -> Dictionary:
	var models: Array = []
	for i in range(n_models):
		models.append({"id": "m%d" % i, "alive": true, "wounds": wounds, "current_wounds": wounds,
			"base_mm": 25, "base_type": "circular", "position": {"x": x + i * 45.0, "y": y}})
	return {"id": id, "owner": owner, "status": 2, "flags": flags,
		"meta": {"name": id, "keywords": keywords, "stats": {"move": 6, "wounds": wounds, "toughness": 4, "save": 7, "objective_control": 1}, "weapons": []},
		"models": models}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_core_rules_audit_e28e4f7 ===")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	_section_fight(gs, pm)
	_section_movement(gs, pm)
	_section_indirect(gs, pm)
	_section_auto_saves(gs, pm)
	_section_emergency_disembark(gs, pm)

	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()

# ---------------------------------------------------------------------------
# P0-2 — 12.04: "Players resolve the following sequence until all eligible
# units have been selected to fight". END_FIGHT may not forfeit them.
func _section_fight(gs, pm) -> void:
	print("\n-- P0-2: END_FIGHT while both players still owe a fight --")
	gs.state["units"] = {
		"U_ORK": _unit("U_ORK", 1, 500, 500),
		"U_PROS": _unit("U_PROS", 2, 560, 500),
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10
	pm.transition_to_phase(10)
	var fp = pm.get_current_phase_instance()
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})
	var offered := false
	for a in fp.get_available_actions():
		if a.get("type", "") == "END_FIGHT":
			offered = true
	_check("END_FIGHT is not offered while eligible fights remain", not offered)
	var r = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("END_FIGHT is rejected while eligible fights remain", not r.get("success", false), str(r))
	_check("the ending player's engaged unit is NOT marked as fought",
		fp.sequencer_11e.eligible_to_fight("U_ORK", gs.state))
	_check("the opponent's engaged unit is NOT marked as fought",
		fp.sequencer_11e.eligible_to_fight("U_PROS", gs.state))
	_check("the Fight step is still running (no jump to Consolidate)",
		fp.consolidation_step_11e == fp.ConsolidationStep11e.NOT_STARTED)

# ---------------------------------------------------------------------------
# P1-5 — 09.02: "every unit in their army will have been selected to make a
# move, even if it is to remain stationary". A unit the player never touched
# must end the step having remained stationary (09.04) — e.g. it keeps
# [HEAVY] (24.16) instead of being treated as never having been selected.
func _section_movement(gs, pm) -> void:
	print("\n-- P1-5: END_MOVEMENT with an unselected unit --")
	gs.state["units"] = {
		"U_IDLE": _unit("U_IDLE", 1, 300, 300),
		"U_MOVED": _unit("U_MOVED", 1, 600, 300, {"moved": true, "moved_max_inches": 6.0}),
		"U_ENEMY": _unit("U_ENEMY", 2, 1500, 1500),
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 7
	pm.transition_to_phase(7)
	var mp = pm.get_current_phase_instance()
	var r = mp.execute_action({"type": "END_MOVEMENT", "player": 1})
	_check("END_MOVEMENT succeeds", r.get("success", false), str(r))
	var idle_flags: Dictionary = gs.state.units["U_IDLE"].get("flags", {})
	_check("the unselected unit was selected to move (flags.moved)", idle_flags.get("moved", false), str(idle_flags))
	_check("the unselected unit remained stationary (09.04)", idle_flags.get("remained_stationary", false), str(idle_flags))
	_check("[HEAVY] applies to the stationary unit (24.16)",
		ModifierStack.heavy_applies_11e(gs.state.units["U_IDLE"], gs.state), str(idle_flags))
	var moved_flags: Dictionary = gs.state.units["U_MOVED"].get("flags", {})
	_check("a unit that already moved is not re-flagged as stationary",
		not moved_flags.get("remained_stationary", false), str(moved_flags))
	_check("enemy units are untouched", not gs.state.units["U_ENEMY"].get("flags", {}).get("moved", false))

# ---------------------------------------------------------------------------
# P0-1 — 10.07: "Each time an [INDIRECT FIRE] weapon makes an attack: the
# target has the benefit of cover ... You cannot re-roll hit rolls ... An
# unmodified hit roll of 1-5 fails, unless your unit remained stationary"
# — these follow the SELECTED shooting type, so they apply against a VISIBLE
# target too.
func _indirect_board(mortar_flags: Dictionary) -> Dictionary:
	# Mortar (1360,400) -> Foe (1360,1000): open ground on the boot layout
	# (take_and_hold_mirror_1), the foe is visible. (x mirrored 1760 - x when
	# the 11e layouts were rotated to the official orientation.)
	return {"units": {
		"U_MORTAR": {"id": "U_MORTAR", "owner": 1, "status": 2, "flags": mortar_flags,
			"meta": {"name": "Mortar Team", "keywords": ["INFANTRY"],
				"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 2},
				"weapons": [{"name": "Mortar", "type": "Ranged", "range": "48",
					"attacks": "12", "ballistic_skill": "4", "strength": "4",
					"ap": "0", "damage": "1", "special_rules": "indirect fire"}]},
			"models": [{"id": "m0", "alive": true, "wounds": 2, "current_wounds": 2,
				"base_mm": 32, "base_type": "circular", "position": {"x": 1360, "y": 400}}]},
		"U_FOE": {"id": "U_FOE", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Foe", "keywords": ["INFANTRY"],
				"stats": {"move": 6, "toughness": 4, "save": 5, "wounds": 1}},
			"models": [
				{"id": "f0", "alive": true, "wounds": 1, "current_wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": {"x": 1360, "y": 1000}},
				{"id": "f1", "alive": true, "wounds": 1, "current_wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": {"x": 1320, "y": 1000}}]},
	}, "terrain_features": [], "meta": {"active_player": 1, "phase": 8}, "players": {"1": {"cp": 0}, "2": {"cp": 0}}}

func _to_hit_block(result: Dictionary) -> Dictionary:
	for d in result.get("dice", []):
		if d.get("context", "") == "to_hit":
			return d
	return {}

func _count_at_least(rolls: Array, at_least: int) -> int:
	var n := 0
	for r in rolls:
		if int(r) >= at_least:
			n += 1
	return n

func _section_indirect(gs, pm) -> void:
	print("\n-- P0-1: selected Indirect Shooting against a VISIBLE target --")
	var rules = root.get_node("RulesEngine")
	var moved := {"moved": true, "moved_max_inches": 6.0}
	var b = _indirect_board(moved)
	_check("geometry: the target is visible to the mortar", rules._has_los_to_target_unit("U_MORTAR", "U_FOE", b))
	var seed := 7
	var expected: Array = rules.RNGService.new(seed).roll_d6(12)
	_check("seed stream distinguishes 4+ from 6s (%s)" % str(expected), _count_at_least(expected, 4) != _count_at_least(expected, 6))
	var assignment = {"weapon_id": "Mortar", "target_unit_id": "U_FOE", "model_ids": ["m0"]}
	# Control: normal shooting (type not indirect) at the visible target — BS 4+.
	var res_n = rules.resolve_shoot_until_wounds({"actor_unit_id": "U_MORTAR",
		"payload": {"assignments": [assignment.duplicate()], "shooting_type": "normal"}}, b, rules.RNGService.new(seed))
	var th_n = _to_hit_block(res_n)
	_check("control — normal shooting: 4+ hits (%d)" % _count_at_least(expected, 4),
		int(th_n.get("successes", -1)) == _count_at_least(expected, 4), str(th_n))
	# Indirect selected, unit moved: unmodified 1-5 fail -> only 6s hit.
	var res_i = rules.resolve_shoot_until_wounds({"actor_unit_id": "U_MORTAR",
		"payload": {"assignments": [assignment.duplicate()], "shooting_type": "indirect"}}, b, rules.RNGService.new(seed))
	var th_i = _to_hit_block(res_i)
	_check("indirect selected + moved: only unmodified 6s hit (%d)" % _count_at_least(expected, 6),
		int(th_i.get("successes", -1)) == _count_at_least(expected, 6), str(th_i))
	# Hit re-rolls are prohibited.
	var b_rr = _indirect_board({"moved": true, "moved_max_inches": 6.0, "effect_reroll_hits": "failed"})
	var res_rr = rules.resolve_shoot_until_wounds({"actor_unit_id": "U_MORTAR",
		"payload": {"assignments": [assignment.duplicate()], "shooting_type": "indirect"}}, b_rr, rules.RNGService.new(seed))
	var th_rr = _to_hit_block(res_rr)
	_check("indirect selected: a re-roll-hits effect does NOT re-roll",
		(th_rr.get("rerolls", []) as Array).is_empty(), str(th_rr.get("rerolls")))
	# Stationary + visible (the shooter is a friendly unit that sees it):
	# 1-3 fail, and the target has the benefit of cover — BS 4 worsened to
	# 5+ (13.08), so 5s and 6s hit.
	var b_st = _indirect_board({"moved": true, "remained_stationary": true, "moved_max_inches": 0.0})
	var res_st = rules.resolve_shoot_until_wounds({"actor_unit_id": "U_MORTAR",
		"payload": {"assignments": [assignment.duplicate()], "shooting_type": "indirect"}}, b_st, rules.RNGService.new(seed))
	var th_st = _to_hit_block(res_st)
	_check("indirect selected + stationary: cover worsens BS to 5+ (%d hits)" % _count_at_least(expected, 5),
		int(th_st.get("successes", -1)) == _count_at_least(expected, 5), str(th_st))

	print("\n-- P0-1: the ShootingPhase forwards the selected type to the resolver --")
	gs.state["units"] = b.units.duplicate(true)
	gs.state["terrain_features"] = []
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 8
	pm.transition_to_phase(8)
	var sp = pm.get_current_phase_instance()
	var r_sel = sp.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_MORTAR", "player": 1,
		"payload": {"shooting_type": "indirect"}})
	_check("SELECT_SHOOTER with indirect succeeds", r_sel.get("success", false), str(r_sel.get("errors", r_sel.get("error", ""))))
	_check("indirect is the active shooting type", sp.active_shooting_type == "indirect", sp.active_shooting_type)
	var r_as = sp.execute_action({"type": "ASSIGN_TARGET", "actor_unit_id": "U_MORTAR", "player": 1,
		"payload": {"weapon_id": "Mortar", "target_unit_id": "U_FOE", "model_ids": ["m0"]}})
	_check("ASSIGN_TARGET succeeds", r_as.get("success", false), str(r_as.get("errors", r_as.get("error", ""))))
	var r_cf = sp.execute_action({"type": "CONFIRM_TARGETS", "actor_unit_id": "U_MORTAR", "player": 1,
		"payload": {"rng_seed": seed}})
	_check("CONFIRM_TARGETS succeeds", r_cf.get("success", false), str(r_cf.get("errors", r_cf.get("error", ""))))
	# Single-player: CONFIRM_TARGETS opens the step-by-step roll dialog;
	# start it (the player's "Roll" click) and read the paused hit stage.
	var r_seq = sp.execute_action({"type": "RESOLVE_WEAPON_SEQUENCE", "actor_unit_id": "U_MORTAR", "player": 1,
		"payload": {"weapon_order": r_cf.get("confirmed_assignments", []), "fast_roll": false}})
	_check("RESOLVE_WEAPON_SEQUENCE succeeds", r_seq.get("success", false), str(r_seq.get("errors", r_seq.get("error", ""))))
	var hc: Dictionary = sp.resolution_state.get("staged_hit_context", {})
	var raw: Array = hc.get("hit_rolls", [])
	_check("phase rolled 12 hit dice", raw.size() == 12, str(sp.resolution_state.keys()))
	_check("phase path: only unmodified 6s hit (%d of %s)" % [_count_at_least(raw, 6), str(raw)],
		raw.size() == 12 and int(hc.get("hits", -1)) - int(hc.get("sustained_bonus_hits", 0)) == _count_at_least(raw, 6),
		"hits=%s" % str(hc.get("hits")))
	_check("phase path: the staged Command Re-roll of a hit die is refused",
		not rules.reroll_hit_die(hc, 0, rules.RNGService.new(1)).get("success", true))

# ---------------------------------------------------------------------------
# P1-3 — 05.04: "if a model in the current allocation group has lost one or
# more wounds, it must be selected" — two failed D1 saves against two
# identical W2 / Sv7+ models put both points of damage on the SAME model:
# one casualty. Driven through the automatic (AI / computer-allocates)
# defender path ShootingPhase._auto_roll_saves.
func _section_auto_saves(gs, pm) -> void:
	print("\n-- P1-3: automatic save allocation (two failed D1 saves, two W2 models) --")
	var rules = root.get_node("RulesEngine")
	gs.state["units"] = {
		"U_GUN": {"id": "U_GUN", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Gunners", "keywords": ["INFANTRY"],
				"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1},
				"weapons": [{"name": "Bolter", "type": "Ranged", "range": "24",
					"attacks": "2", "ballistic_skill": "3", "strength": "4",
					"ap": "0", "damage": "1", "special_rules": ""}]},
			"models": [{"id": "g0", "alive": true, "wounds": 1, "current_wounds": 1,
				"base_mm": 32, "base_type": "circular", "position": {"x": 400, "y": 400}}]},
		"U_W2": {"id": "U_W2", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Two-Wound Squad", "keywords": ["INFANTRY"],
				"stats": {"move": 6, "toughness": 4, "save": 7, "wounds": 2}},
			"models": [
				{"id": "a0", "alive": true, "wounds": 2, "current_wounds": 2,
					"base_mm": 32, "base_type": "circular", "position": {"x": 400, "y": 900}},
				{"id": "a1", "alive": true, "wounds": 2, "current_wounds": 2,
					"base_mm": 32, "base_type": "circular", "position": {"x": 450, "y": 900}}]},
	}
	gs.state["terrain_features"] = []
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 8
	pm.transition_to_phase(8)
	var sp = pm.get_current_phase_instance()
	var wprofile = rules.get_weapon_profile("Bolter", gs.state)
	var save_data = rules.prepare_save_resolution(2, "U_W2", "U_GUN", wprofile, gs.state)
	_check("save data prepared for 2 wounds", int(save_data.get("wounds_to_save", 0)) == 2, str(save_data.keys()))
	var res = sp._auto_roll_saves([save_data])
	var dead := 0
	var wound_values: Dictionary = {}
	for d in res.get("changes", []):
		var path = str(d.get("path", ""))
		if path.begins_with("units.U_W2.models.") and path.ends_with(".alive") and d.get("value") == false:
			dead += 1
		if path.begins_with("units.U_W2.models.") and path.ends_with(".current_wounds"):
			wound_values[path] = d.get("value")
	_check("both points of damage land on one model -> exactly 1 casualty (got %d)" % dead,
		dead == 1 and int(res.get("casualties", -1)) == 1, "changes=%s" % str(res.get("changes", [])))
	_check("the surviving model is unwounded (damage was not spread)",
		not wound_values.values().has(1), str(wound_values))

# ---------------------------------------------------------------------------
# P1-4 — 18.05: "Set up each model in your unit wholly within the set-up
# distance [6"] of that TRANSPORT, and as close as possible to that TRANSPORT.
# Each model that cannot be set up in this way is destroyed." Set up (03.02):
# on the battlefield, no overlaps, unengaged, in coherency.
func _disembark_board(transport_pos: Vector2, enemy_models: Array, n_embarked: int) -> Dictionary:
	var emb_models: Array = []
	for i in range(n_embarked):
		emb_models.append({"id": "e%d" % i, "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": 32, "base_type": "circular", "position": null})
	return {"units": {
		"U_RHINO": {"id": "U_RHINO", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Rhino", "keywords": ["VEHICLE", "TRANSPORT"], "stats": {"wounds": 10, "toughness": 9, "save": 3}},
			"transport_data": {"capacity": 12, "embarked_units": ["U_SQUAD"]},
			"models": [{"id": "t0", "alive": false, "wounds": 10, "current_wounds": 0,
				"base_mm": 60, "base_type": "circular", "position": {"x": transport_pos.x, "y": transport_pos.y}}]},
		"U_SQUAD": {"id": "U_SQUAD", "owner": 1, "status": 2, "embarked_in": "U_RHINO", "flags": {},
			"meta": {"name": "Tactical Squad", "keywords": ["INFANTRY"], "stats": {"wounds": 1, "toughness": 4, "save": 3}},
			"models": emb_models},
		"U_SCREEN": {"id": "U_SCREEN", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Screen", "keywords": ["INFANTRY"], "stats": {"wounds": 1, "toughness": 4, "save": 5}},
			"models": enemy_models},
	}, "meta": {}}

func _apply_set_diffs(board: Dictionary, diffs: Array) -> void:
	for d in diffs:
		if str(d.get("op", "")) != "set":
			continue
		var parts = str(d.get("path", "")).split(".")
		if parts.size() == 5 and parts[0] == "units" and parts[2] == "models":
			board.units[parts[1]].models[int(parts[3])][parts[4]] = d.get("value")
		elif parts.size() == 3 and parts[0] == "units":
			board.units[parts[1]][parts[2]] = d.get("value")

func _section_emergency_disembark(gs, pm) -> void:
	print("\n-- P1-4: emergency disembark at a board corner, enemy screen + wall nearby --")
	var rules = root.get_node("RulesEngine")
	var meas = root.get_node("Measurement")
	var terrain = root.get_node("TerrainManager")
	var prev_terrain: Array = terrain.terrain_features.duplicate(true)
	# A wall 3" to the right of the transport, running vertically.
	var t_pos := Vector2(80, 80)
	terrain.terrain_features = [{"id": "wall_test", "type": "ruins", "height_category": "tall",
		"polygon": PackedVector2Array([Vector2(196, 0), Vector2(204, 0), Vector2(204, 400), Vector2(196, 400)]),
		"walls": [{"start": Vector2(200, 0), "end": Vector2(200, 400)}]}]
	# Enemy screen: a line of models 4.5" below the transport centre.
	var screen: Array = []
	for i in range(5):
		screen.append({"id": "s%d" % i, "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": 32, "base_type": "circular", "position": {"x": 20.0 + i * 45.0, "y": t_pos.y + 180.0}})
	var board = _disembark_board(t_pos, screen, 10)
	var t0 := Time.get_ticks_msec()
	var res = rules.resolve_transport_destruction("U_RHINO", board, rules.RNGService.new(3))
	var elapsed := Time.get_ticks_msec() - t0
	print("    resolve_transport_destruction took %d ms" % elapsed)
	_apply_set_diffs(board, res.get("all_diffs", []))
	var transport_model: Dictionary = board.units["U_RHINO"].models[0].duplicate()
	transport_model["alive"] = true
	var squad: Array = board.units["U_SQUAD"].models
	var placed: Array = []
	for m in squad:
		if m.get("alive", true) and m.get("position", null) != null:
			var pm2 = m.duplicate()
			var p = pm2.position
			pm2["position"] = Vector2(float(p.x), float(p.y))
			placed.append(pm2)
	print("    placed %d survivor(s); destroyed %d" % [placed.size(), int(res.get("total_models_destroyed", 0))])
	_check("at least one model was set up", placed.size() > 0)
	var off_board := 0
	var overlap_transport := 0
	var overlap_models := 0
	var not_within_6 := 0
	var engaged := 0
	var on_wall := 0
	var no_coherency_link := 0
	for i in range(placed.size()):
		var m = placed[i]
		if meas.model_outside_board(m.position, m):
			off_board += 1
		if meas.models_overlap(m, transport_model):
			overlap_transport += 1
		for j in range(i + 1, placed.size()):
			if meas.models_overlap(m, placed[j]):
				overlap_models += 1
		if meas.model_edge_to_point_distance_px(transport_model, m.position) + meas.base_extent_px(m) > meas.inches_to_px(6.0) + 0.5:
			not_within_6 += 1
		for e in screen:
			var ee = e.duplicate()
			ee["position"] = Vector2(e.position.x, e.position.y)
			if meas.is_in_engagement_range_shape_aware(m, ee) or meas.models_overlap(m, ee):
				engaged += 1
		if meas.model_overlaps_any_wall(m, ["INFANTRY"]):
			on_wall += 1
		if placed.size() > 1:
			var linked := false
			for j in range(placed.size()):
				if j != i and meas.model_to_model_distance_inches(m, placed[j]) <= 2.01:
					linked = true
			if not linked:
				no_coherency_link += 1
	_check("no model set up off the battlefield (%d)" % off_board, off_board == 0)
	_check("no model overlaps the destroyed transport (%d)" % overlap_transport, overlap_transport == 0)
	_check("no two disembarked models overlap (%d)" % overlap_models, overlap_models == 0)
	_check("every model wholly within 6\" of the transport (%d outside)" % not_within_6, not_within_6 == 0)
	_check("no model within engagement range of the enemy screen (%d)" % engaged, engaged == 0)
	_check("no model set up on the wall (%d)" % on_wall, on_wall == 0)
	_check("the unit is in coherency (%d unlinked)" % no_coherency_link, no_coherency_link == 0)
	var unaccounted := 0
	for m in squad:
		if m.get("alive", true) and m.get("position", null) == null:
			unaccounted += 1
	_check("every surviving model is either set up or destroyed (%d left in limbo)" % unaccounted, unaccounted == 0)
	var nearest := 9999.0
	for m in placed:
		nearest = min(nearest, meas.model_to_model_distance_inches(m, transport_model))
	_check("as close as possible: the nearest model is set up within 0.5\" of the hull (%.2f\")" % nearest, nearest <= 0.5)

	print("\n-- P1-4: no legal position within 6\" -> the models are destroyed --")
	# Enemy models on a 2" grid all around the transport: every spot within 6"
	# overlaps one or is within 2" engagement range of one.
	var swarm: Array = []
	var c := Vector2(800, 800)
	var k := 0
	for gy in range(-5, 6):
		for gx in range(-5, 6):
			var pos := c + Vector2(gx * 80.0, gy * 80.0)
			if pos.distance_to(c) < 80.0:
				continue  # the transport's own footprint
			swarm.append({"id": "w%d" % k, "alive": true, "wounds": 1, "current_wounds": 1,
				"base_mm": 32, "base_type": "circular", "position": {"x": pos.x, "y": pos.y}})
			k += 1
	terrain.terrain_features = []
	var board2 = _disembark_board(c, swarm, 4)
	var res2 = rules.resolve_transport_destruction("U_RHINO", board2, rules.RNGService.new(3))
	_apply_set_diffs(board2, res2.get("all_diffs", []))
	var alive_after := 0
	for m in board2.units["U_SQUAD"].models:
		if m.get("alive", true):
			alive_after += 1
	_check("every model with no legal set-up spot is destroyed (%d still alive)" % alive_after, alive_after == 0)

	terrain.terrain_features = prev_terrain

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

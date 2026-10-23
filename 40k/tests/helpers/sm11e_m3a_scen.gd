extends RefCounted
## Helpers for the WP-M3a windowed scenarios (tests/scenarios/sp/sm11e_<slug>.json)
## — Codex: Space Marines (11e) generic detachment stratagems (SMCodex11e.gd).
##
## Called from `execute_script` steps, e.g.
##   load("res://tests/helpers/sm11e_m3a_scen.gd").setup(1, {})
## Only SETUP privileges (the seven detachments, unit placement, terrain, flags
## not under test) and phase actions the panels send live here; every
## stratagem decision in the scenarios is a real click on the StratagemDialog /
## StratagemChoiceDialog / the reactive-move panel / the S panel + target picker.
##
## Fixtures: tests/saves/sm11e_m3a_active (P1 Space Marines active vs P2 Orks)
## and sm11e_m3a_reactive (P1 Orks active vs P2 Space Marines) — layout in
## tests/helpers/gen_sm11e_m3a_fixtures.gd.

const PX := 40.0
const DETS := ["Gladius Task Force", "Ironstorm Spearhead", "Stormlance Task Force", "Gauntlet Task Force",
	"Phobos Shadow Force", "Tacticus Attack Force", "Phobos Shock Force"]


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _n(name: String) -> Node:
	return _root().get_node_or_null(name)


static func gs():
	return _n("GameState")


static func phase():
	return _n("PhaseManager").get_current_phase_instance()


static func main() -> Node:
	return (Engine.get_main_loop() as SceneTree).current_scene


## Setup privileges: the Space Marine player gets the seven WP-M3a detachments
## (stratagems reloaded), auto wound allocation, opts.cp = {player: cp},
## opts.flags = {uid: {flag: value}}. Returns the detachments.
static func setup(player: int, opts: Dictionary = {}) -> String:
	var g = gs()
	g.state["factions"][str(player)].merge({"detachment": DETS[0], "detachments": DETS.duplicate()}, true)
	_n("StratagemManager").load_faction_stratagems_for_player(player)
	_n("SettingsService").set("auto_allocate_wounds", true)
	var cps: Dictionary = opts.get("cp", {})
	for p in cps:
		g.state.players[str(p)]["cp"] = int(cps[p])
	var fl: Dictionary = opts.get("flags", {})
	for uid in fl:
		for k in fl[uid]:
			g.state.units[uid]["flags"][k] = fl[uid][k]
	refresh()
	print("[sm11e scen] setup: P%d detachments %s opts %s" % [player, str(DETS), str(opts)])
	return "%d detachments" % g.state.factions[str(player)].get("detachments", []).size()


static func refresh() -> void:
	var m = main()
	if m != null and m.has_method("_recreate_unit_visuals"):
		m._recreate_unit_visuals()


static func sid(player: int, csv: String) -> String:
	for s in _n("StratagemManager").get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) == csv:
			return str(s.id)
	return ""


static func window_id() -> String:
	var ph = phase()
	if ph == null or not ph.has_pending_stratagem_window():
		return ""
	return str(ph.get_pending_stratagem_window().get("window_id", ""))


static func decider() -> int:
	return int(phase().get_pending_stratagem_window_decider())


static func offered(stratagem_id: String) -> Array:
	var ph = phase()
	if ph == null or not ph.has_pending_stratagem_window():
		return []
	for o in ph.get_pending_stratagem_window().get("offers", []):
		if str(o.get("stratagem_id", "")) == stratagem_id:
			return o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))
	return []


static func flag(uid: String, key: String) -> Variant:
	return gs().state.units[uid].get("flags", {}).get(key, null)


static func unit(uid: String) -> Dictionary:
	return gs().state.units.get(uid, {})


static func codex():
	return load("res://scripts/codex/space_marines/SMCodex11e.gd")


static func common():
	return load("res://scripts/codex/space_wolves/SWCommon.gd")


static func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p


## Shift a unit rigidly by (dx, dy) inches (setup privilege).
static func shift(uid: String, dx: float, dy: float) -> bool:
	for m in gs().state.units[uid].models:
		if m.get("position") != null:
			var p := _pos(m)
			m["position"] = {"x": p.x + dx * PX, "y": p.y + dy * PX}
	refresh()
	return true


## A dense ruin under a unit (setup privilege) — 13.09: its INFANTRY models are hidden.
static func ruin_under(uid: String) -> bool:
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for m in gs().state.units[uid].models:
		var p := _pos(m)
		minp = Vector2(minf(minp.x, p.x), minf(minp.y, p.y))
		maxp = Vector2(maxf(maxp.x, p.x), maxf(maxp.y, p.y))
	var c := (minp + maxp) / 2.0
	var w := maxp.x - minp.x + 4.0 * PX
	var h := maxp.y - minp.y + 4.0 * PX
	var poly := PackedVector2Array([Vector2(c.x - w / 2, c.y - h / 2), Vector2(c.x + w / 2, c.y - h / 2),
		Vector2(c.x + w / 2, c.y + h / 2), Vector2(c.x - w / 2, c.y + h / 2)])
	var tm = _n("TerrainManager")
	tm.terrain_features = [{"id": "sm11e_scen_ruin", "type": "ruins", "polygon": poly, "height_category": "tall"}]
	if tm.has_signal("terrain_loaded"):
		tm.emit_signal("terrain_loaded", tm.terrain_features)
	return load("res://scripts/codex/space_marines/SMCodexACombat.gd").unit_is_hidden(uid)


## Stage a rigid move of the unit by (dx, dy) inches and optionally confirm
## (STAGE_MODEL_MOVE / CONFIRM_UNIT_MOVE — the actions a drag + Confirm send).
static func move(uid: String, dx: float, dy: float, confirm: bool = true) -> Variant:
	var d := Vector2(dx, dy)
	var ph = phase()
	var entries: Array = []
	for m in gs().state.units[uid].models:
		if m.get("alive", true) and m.get("position") != null:
			entries.append(m)
	entries.sort_custom(func(a, b): return _pos(a).dot(d) > _pos(b).dot(d))
	for m in entries:
		var dest: Vector2 = _pos(m) + d * PX
		var r = ph.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": uid, "payload": {"model_id": str(m.id), "dest": [dest.x, dest.y]}})
		if not r.get("success", false):
			return "stage %s: %s" % [m.id, str(r.get("error", r.get("errors", "")))]
	if not confirm:
		return true
	var c: Dictionary = ph.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": uid, "payload": {}})
	print("[sm11e scen] move %s by (%.1f, %.1f)\": %s" % [uid, dx, dy, str(c.get("success", false))])
	return true if c.get("success", false) else "confirm: " + str(c.get("error", c.get("errors", "")))


## Every ranged weapon of `shooter` that can target `target` (the AI's /
## auto-shoot atomic SHOOT payload).
static func shoot(shooter: String, target: String) -> Variant:
	var re = _n("RulesEngine")
	var board: Dictionary = gs().create_snapshot()
	var weapons: Array = re.get_eligible_targets(shooter, board).get(target, {}).get("weapons_in_range", [])
	var per := {}
	var uw: Dictionary = re.get_unit_weapons(shooter, board)
	for mid in uw:
		for wid in uw[mid]:
			if wid in weapons:
				if not per.has(wid):
					per[wid] = []
				per[wid].append(mid)
	var asg: Array = []
	for wid in per:
		asg.append({"weapon_id": wid, "target_unit_id": target, "model_ids": per[wid]})
	if asg.is_empty():
		return "%s cannot target %s" % [shooter, target]
	var r: Dictionary = phase().execute_action({"type": "SHOOT", "actor_unit_id": shooter,
		"player": int(unit(shooter).owner), "payload": {"assignments": asg}})
	print("[sm11e scen] SHOOT %s -> %s: %s" % [shooter, target, str(r.get("success", false))])
	return true if r.get("success", false) else str(r.get("error", r.get("errors", "failed")))


## ASSIGN_TARGET + CONFIRM_TARGETS for one weapon of the shooter (the shooting
## panel's actions); the defender's reactive dialog may then open.
static func assign_and_confirm(player: int, uid: String, tid: String) -> Variant:
	var re = _n("RulesEngine")
	var board: Dictionary = gs().create_snapshot()
	var weapons: Array = re.get_eligible_targets(uid, board).get(tid, {}).get("weapons_in_range", [])
	if weapons.is_empty():
		return "%s cannot target %s" % [uid, tid]
	var wid := str(weapons[0])
	var model_ids: Array = []
	var w = re.get_unit_weapons(uid, board)
	for mid in w:
		if wid in w[mid]:
			model_ids.append(str(mid))
	var ph = phase()
	var r: Dictionary = ph.execute_action({"type": "ASSIGN_TARGET", "actor_unit_id": uid, "player": player,
		"payload": {"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}})
	if not r.get("success", false):
		return "assign: " + str(r.get("error", r.get("errors", "")))
	r = ph.execute_action({"type": "CONFIRM_TARGETS", "player": player})
	print("[sm11e scen] ASSIGN+CONFIRM %s (%s) -> %s: %s" % [uid, wid, tid, str(r.get("success", false))])
	return true if r.get("success", false) else "confirm: " + str(r.get("error", r.get("errors", "")))


## Decline (with the window action the dialog's Decline sends) every pending
## window that is not `player`'s.
static func decline_others(player: int) -> int:
	var n := 0
	var ph = phase()
	while ph.has_pending_stratagem_window() and int(ph.get_pending_stratagem_window().get("player", 0)) != player and n < 6:
		var w: Dictionary = ph.get_pending_stratagem_window()
		ph.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1
	return n


## Belt-and-braces after the real clicks: decline any prompt not under test
## that is still waiting (Fire Overwatch / Command Re-roll / ...) with the
## phase action its dialog sends.
static func settle() -> Array:
	var ph = phase()
	var done: Array = []
	if ph == null:
		return done
	for _i in range(6):
		if ("_awaiting_fire_overwatch" in ph and ph._awaiting_fire_overwatch) or ("_awaiting_overwatch_decision" in ph and ph._awaiting_overwatch_decision):
			ph.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": int(ph._fire_overwatch_player)})
			done.append("fire_overwatch")
		elif "_awaiting_reroll_decision" in ph and ph._awaiting_reroll_decision:
			ph.execute_action({"type": "DECLINE_COMMAND_REROLL"})
			done.append("command_reroll")
		elif "_awaiting_krump_and_run" in ph and ph._awaiting_krump_and_run:
			ph.execute_action({"type": "DECLINE_KRUMP_AND_RUN"})
			done.append("krump_and_run")
		elif "_awaiting_scatter" in ph and ph._awaiting_scatter:
			ph.execute_action({"type": "DECLINE_SCATTER"})
			done.append("scatter")
		else:
			break
	if not done.is_empty():
		print("[sm11e scen] settle (action fallback): %s" % str(done))
	return done


## Every eligible unit counts as having fought, then the phase reaches its
## Consolidate step (setup privilege: the fights are not under test).
static func to_consolidation() -> bool:
	var ph = phase()
	for uid in gs().state.units:
		if ph.sequencer_11e.eligible_to_fight(uid, gs().state):
			ph.sequencer_11e.mark_fought(uid, gs().state)
	for _i in range(4):
		if int(ph.consolidation_step_11e) == int(ph.ConsolidationStep11e.ACTIVE):
			break
		ph.execute_action({"type": "END_FIGHT", "player": int(gs().get_active_player())})
	return int(ph.consolidation_step_11e) == int(ph.ConsolidationStep11e.ACTIVE)


static func alive(uid: String) -> int:
	var n := 0
	for m in gs().state.units[uid].models:
		if m.get("alive", true):
			n += 1
	return n


static func wounds(uid: String) -> int:
	var n := 0
	for m in gs().state.units[uid].models:
		if m.get("alive", true):
			n += int(m.get("current_wounds", m.get("wounds", 1)))
	return n


## The last dice block of `context`.
static func dice(context: String) -> Dictionary:
	var out := {}
	for b in phase().dice_log:
		if typeof(b) == TYPE_DICTIONARY and str(b.get("context", "")) == context:
			out = b
	print("[sm11e scen] dice[%s] = %s" % [context, str(out).substr(0, 600)])
	return out


## True when a resolved dice block of `context` names `source` in its modifier ledger.
static func ledger_names(context: String, source: String) -> bool:
	for b in phase().dice_log:
		if typeof(b) == TYPE_DICTIONARY and str(b.get("context", "")) == context:
			for e in b.get("modifier_ledger", []):
				if str(e.get("source", "")) == source:
					return true
	return false


static func log_count(needle: String) -> int:
	return int(_n("ScenarioRunner").event_log_count_containing(needle))


## Frame the camera on a board point (inches) at zoom z.
static func frame(x_in: float, y_in: float, z: float = 1.4) -> bool:
	var m = main()
	if m == null or not ("camera" in m) or m.camera == null:
		return false
	var focus := Vector2(x_in, y_in) * PX
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	m.camera.position = focus
	m.camera.zoom = Vector2(z, z)
	m.view_zoom = z
	m.view_offset = focus - vp / (2.0 * z)
	m.update_view_transform()
	return true


## A root dialog with no stable name (DisembarkDialog) found by its script.
static func dialog_by_script(file: String) -> Node:
	for child in _root().get_children():
		var scr = child.get_script()
		if scr != null and str(scr.resource_path).ends_with(file) and child is Window and (child as Window).visible:
			return child
	return null

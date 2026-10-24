extends RefCounted
## Helpers for the WP-M2b windowed scenarios (tests/scenarios/sp/sm11e_det_*.json,
## sm11e_enh_*.json) — Codex: Space Marines (11e) generic detachments group B
## (scripts/codex/space_marines/SMDetachmentsB.gd).
##
## Called from `execute_script` steps:
##   load("res://tests/helpers/sm11e_m2b_scen.gd").setup({...})
## Only SETUP privileges (CP, placement, attachments, wounds, doctrine state —
## each scenario's description lists the ones it uses) and the phase actions
## the panels send live here; the rule under test is exercised through the
## real UI / phase flow.

const PX := 40.0


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


static func det():
	return load("res://scripts/codex/space_marines/SMDetachmentsB.gd")


static func unit(uid: String) -> Dictionary:
	return gs().state.units.get(uid, {})


## Setup privileges. opts: cp = {player: cp}, active = player, round = n,
## dets = [names] (P1), attach = {char: bodyguard}, place = {uid: [x, y]}
## (centroid, inches), wound = {uid: current_wounds of model 0},
## kill = {uid: n models}, doctrine = "assault"|..., stats = {uid: {k: v}},
## enh = {uid: [names]}, flags = {uid: {k: v}}.
static func setup(opts: Dictionary = {}) -> bool:
	var g = gs()
	_n("SettingsService").set("auto_allocate_wounds", true)
	for p in opts.get("cp", {}):
		g.state.players[str(p)]["cp"] = int(opts.cp[p])
	if opts.has("active"):
		g.state.meta["active_player"] = int(opts.active)
	if opts.has("round"):
		g.state.meta["battle_round"] = int(opts.round)
	if opts.has("dets"):
		g.state.factions["1"]["detachment"] = str(opts.dets[0])
		g.state.factions["1"]["detachments"] = opts.dets.duplicate()
	if opts.has("faction"):
		g.state.factions["1"]["name"] = str(opts.faction)
	for cid in opts.get("attach", {}):
		var bid := str(opts.attach[cid])
		g.state.units[cid]["attached_to"] = bid
		g.state.units[bid]["attachment_data"] = {"attached_characters": [cid]}
	for uid in opts.get("place", {}):
		move_to(str(uid), float(opts.place[uid][0]), float(opts.place[uid][1]))
	for uid in opts.get("wound", {}):
		g.state.units[uid].models[0]["current_wounds"] = int(opts.wound[uid])
	for uid in opts.get("kill", {}):
		var n := int(opts.kill[uid])
		var ms: Array = g.state.units[uid].models.duplicate()
		ms.reverse()  # the last models first (the fixture's far end)
		for m in ms:
			if n <= 0:
				break
			m["alive"] = false
			m["current_wounds"] = 0
			n -= 1
	for uid in opts.get("stats", {}):
		for k in opts.stats[uid]:
			g.state.units[uid].meta.stats[k] = opts.stats[uid][k]
	for uid in opts.get("enh", {}):
		g.state.units[uid].meta["enhancements"] = opts.enh[uid].duplicate()
	for uid in opts.get("flags", {}):
		for k in opts.flags[uid]:
			g.state.units[uid]["flags"][k] = opts.flags[uid][k]
	if opts.has("doctrine"):
		g.state.factions["1"]["sw11e_doctrine"] = str(opts.doctrine)
	if opts.has("doctrines_used"):
		g.state.factions["1"]["sw11e_doctrines_used"] = opts.doctrines_used.duplicate()
	if opts.has("reserves"):
		for uid in opts.reserves:
			g.state.units[uid]["status"] = g.UnitStatus.IN_RESERVES
			g.state.units[uid]["reserve_type"] = "deep_strike"
			for m in g.state.units[uid].models:
				m["position"] = null
	refresh()
	print("[sm11e m2b scen] setup %s" % str(opts))
	return true


static func refresh() -> void:
	var m = main()
	if m != null and m.has_method("_recreate_unit_visuals"):
		m._recreate_unit_visuals()


static func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p


## Shift a unit rigidly so its centroid sits at (x, y) inches.
static func move_to(uid: String, x: float, y: float) -> bool:
	var c := Vector2.ZERO
	var n := 0
	for m in gs().state.units[uid].models:
		if m.get("position") != null:
			c += _pos(m)
			n += 1
	if n == 0:
		return false
	var d: Vector2 = Vector2(x, y) * PX - c / float(n)
	for m in gs().state.units[uid].models:
		if m.get("position") != null:
			var p := _pos(m)
			m["position"] = {"x": p.x + d.x, "y": p.y + d.y}
	return true


## The last dice block of `context` in the phase dice log ({} = none).
static func dice(context: String) -> Dictionary:
	var out := {}
	var ph = phase()
	if ph == null or not ("dice_log" in ph):
		return out
	for b in ph.dice_log:
		if typeof(b) == TYPE_DICTIONARY and str(b.get("context", "")) == context:
			out = b
	print("[sm11e m2b scen] dice[%s] = %s" % [context, str(out).substr(0, 700)])
	return out


## True when a dice block of `context` names `source` in its modifier ledger.
static func ledger_has(context: String, source: String) -> bool:
	var ph = phase()
	for b in ph.dice_log:
		if typeof(b) != TYPE_DICTIONARY or str(b.get("context", "")) != context:
			continue
		for e in b.get("modifier_ledger", []):
			if str(e.get("source", "")).contains(source):
				print("[sm11e m2b scen] ledger[%s] has %s: %s" % [context, source, str(e)])
				return true
	return false


## SHOOT with every weapon of `shooter` that can reach `target` (optionally
## only weapons whose id contains `contains`) — the shooting panel's SHOOT.
static func shoot(shooter: String, target: String, contains: String = "") -> Variant:
	var re = _n("RulesEngine")
	var board: Dictionary = gs().create_snapshot()
	var weapons: Array = re.get_eligible_targets(shooter, board).get(target, {}).get("weapons_in_range", [])
	var per := {}
	var uw: Dictionary = re.get_unit_weapons(shooter, board)
	for mid in uw:
		for wid in uw[mid]:
			if wid in weapons and (contains == "" or str(wid).contains(contains)):
				if not per.has(wid):
					per[wid] = []
				per[wid].append(mid)
	var asg: Array = []
	for wid in per:
		asg.append({"weapon_id": wid, "target_unit_id": target, "model_ids": per[wid]})
	if asg.is_empty():
		return "%s cannot target %s (%s)" % [shooter, target, str(weapons)]
	var r: Dictionary = phase().execute_action({"type": "SHOOT", "actor_unit_id": shooter,
		"player": int(unit(shooter).owner), "payload": {"assignments": asg}})
	print("[sm11e m2b scen] SHOOT %s -> %s (%s): %s" % [shooter, target, str(per.keys()), str(r.get("success", false))])
	return true if r.get("success", false) else str(r.get("error", r.get("errors", "failed")))


static func log_count(needle: String) -> int:
	return int(_n("ScenarioRunner").event_log_count_containing(needle))


## ERROR lines in this session's debug log (0 = clean).
static func error_lines() -> int:
	var dl = _n("DebugLogger")
	dl._flush_buffer()
	var f = FileAccess.open(dl.get_log_file_path(), FileAccess.READ)
	if f == null:
		return -1
	var n := 0
	var bad: Array = []
	while not f.eof_reached():
		var l := f.get_line()
		if l.contains("[ERROR"):
			n += 1
			bad.append(l)
	print("[sm11e m2b log] ", dl.get_real_log_file_path(), " ERROR lines = ", n, " ", bad.slice(0, 3))
	return n


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


## Show the Game Log panel's Dice Log tab (screenshots of the dice).
static func show_dice_tab() -> bool:
	var m = main()
	for n in m.find_children("*", "", true, false):
		if n.get("_tab_dice_button") != null:
			var b = n.get("_tab_dice_button")
			if b is BaseButton:
				b.emit_signal("pressed")
				return true
	return false

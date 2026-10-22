extends RefCounted
## Helpers for the WP-S3 windowed scenarios (tests/scenarios/sp/sw11e_<slug>.json)
## — Codex: Space Marines (11e) Space Wolves detachment stratagems.
##
## Called from `execute_script` steps, e.g.
##   load("res://tests/helpers/sw11e_s3_scen.gd").setup(1, {})
## Only SETUP privileges (the three detachments, unit placement, flags not
## under test) and phase actions the panels send live here; every stratagem
## decision in the scenarios is a real click on the StratagemDialog / the
## reactive-move panel / the S panel + target picker.

const PX := 40.0
const DETS := ["Saga of the Great Wolf", "Champions of Fenris", "Saga of the Beastslayer"]


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


## Setup privileges: the Space Wolves player gets all three Space Wolves
## detachments (stratagems reloaded), auto wound allocation, opts.cp =
## {player: cp}, opts.flags = {uid: {flag: value}}. Returns the detachments.
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
	print("[sw11e scen] setup: P%d detachments %s opts %s" % [player, str(DETS), str(opts)])
	return " + ".join(PackedStringArray(g.state.factions[str(player)].get("detachments", [])))


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


static func keywords(uid: String) -> Array:
	return unit(uid).get("meta", {}).get("keywords", [])


static func codex():
	return load("res://scripts/codex/space_wolves/SWCodex11e.gd")


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
	print("[sw11e scen] SHOOT %s -> %s: %s" % [shooter, target, str(r.get("success", false))])
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
	print("[sw11e scen] ASSIGN+CONFIRM %s (%s) -> %s: %s" % [uid, wid, tid, str(r.get("success", false))])
	return true if r.get("success", false) else "confirm: " + str(r.get("error", r.get("errors", "")))


## Decline (with the window action the dialog's Decline sends) every pending
## window that is not `player`'s — e.g. the active Ork player's post-shot
## windows that open before the Space Wolves player's enemy_has_shot.
static func decline_others(player: int) -> int:
	var n := 0
	var ph = phase()
	while ph.has_pending_stratagem_window() and int(ph.get_pending_stratagem_window().get("player", 0)) != player and n < 6:
		var w: Dictionary = ph.get_pending_stratagem_window()
		ph.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1
	return n


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

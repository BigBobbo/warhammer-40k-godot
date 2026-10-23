extends RefCounted
## Helpers for the WP-M3b windowed scenarios (tests/scenarios/sp/sm11e_<slug>.json)
## — Codex: Space Marines (11e) stratagems of the eight WP-M2b generic
## detachments (SMCodexB.gd). Built on tests/helpers/sw11e_s3_scen.gd (WP-S3)
## plus the move / charge / prompt helpers of cus11e_c5_scen.gd (WP-C5).
##
## Called from `execute_script` steps, e.g.
##   load("res://tests/helpers/sm11e_m3b_scen.gd").setup(1, {})
## Only SETUP privileges (the detachments, unit placement, flags / doctrine
## not under test) and the phase actions the panels send live here; every
## stratagem decision in the scenarios is a real click on the StratagemDialog /
## its secondary pick / the reactive-move panel.

const PX := 40.0
const DETS := ["Terminator Storm Force", "Assault Brethren", "Gravis Linebreaker Force", "Devastator Brethren",
	"Gravis Siege Force", "Tactical Brethren", "Ironclad Champions", "Tacticus Firestorm Force"]


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


## Setup privileges: the Space Marines player gets the eight WP-M2b generic
## detachments (stratagems reloaded), auto wound allocation, opts.cp =
## {player: cp}, opts.flags = {uid: {flag: value}}, opts.doctrine = the army
## combat doctrine (SWCommon state key sw11e_doctrine). Returns the detachments.
static func setup(player: int, opts: Dictionary = {}) -> String:
	var g = gs()
	g.state["factions"][str(player)].merge({"detachment": DETS[0], "detachments": DETS.duplicate()}, true)
	_n("StratagemManager").load_faction_stratagems_for_player(player)
	_n("SettingsService").set("auto_allocate_wounds", true)
	var cps: Dictionary = opts.get("cp", {})
	for p in cps:
		g.state.players[str(p)]["cp"] = int(cps[p])
	if opts.has("doctrine"):
		g.state["factions"][str(player)]["sw11e_doctrine"] = str(opts.doctrine)
	var fl: Dictionary = opts.get("flags", {})
	for uid in fl:
		for k in fl[uid]:
			g.state.units[uid]["flags"][k] = fl[uid][k]
	refresh()
	print("[sm11e m3b scen] setup: P%d detachments %s opts %s" % [player, str(DETS), str(opts)])
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
	return load("res://scripts/codex/space_marines/SMCodexB.gd")


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
	print("[sm11e m3b scen] SHOOT %s -> %s: %s" % [shooter, target, str(r.get("success", false))])
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
	print("[sm11e m3b scen] ASSIGN+CONFIRM %s (%s) -> %s: %s" % [uid, wid, tid, str(r.get("success", false))])
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


## Move a unit rigidly so its centroid is at (x, y) inches (setup privilege).
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
	refresh()
	return true


## The movement panel's drag + Confirm Move: STAGE_MODEL_MOVE every model by
## (dx, dy) inches, then CONFIRM_UNIT_MOVE.
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
	print("[sm11e m3b scen] move %s by (%.1f, %.1f)\": %s" % [uid, dx, dy, str(c.get("success", false))])
	return true if c.get("success", false) else "confirm: " + str(c.get("error", c.get("errors", "")))


## The charge tools: DECLARE_CHARGE, CHARGE_ROLL (seeded), decline re-roll
## prompts, then the engine's charge-move solver (APPLY_CHARGE_MOVE). Returns
## true when the unit ends engaged with the target.
static func charge(player: int, uid: String, target: String, roll_seed: int = 11) -> Variant:
	var ph = phase()
	var r: Dictionary = ph.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": uid, "player": player, "payload": {"target_unit_ids": [target]}})
	if not r.get("success", false):
		return "declare: " + str(r.get("error", r.get("errors", "")))
	if ph.has_pending_stratagem_window():
		var w: Dictionary = ph.get_pending_stratagem_window()
		ph.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
	r = ph.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": uid, "player": player, "payload": {"rng_seed": roll_seed}})
	if not r.get("success", false):
		return "roll: " + str(r.get("error", r.get("errors", "")))
	if "awaiting_ability_reroll" in ph and ph.awaiting_ability_reroll:
		ph.execute_action({"type": "DECLINE_ABILITY_REROLL", "actor_unit_id": uid, "player": player})
	if "awaiting_reroll_decision" in ph and ph.awaiting_reroll_decision:
		ph.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": uid, "player": player})
	var dist := int(ph.pending_charges.get(uid, {}).get("distance", 0))
	var ai = load("res://scripts/AIDecisionMaker.gd")
	var mv: Dictionary = ai._compute_charge_move(gs().create_snapshot(), uid, dist, [target], player)
	if str(mv.get("type", "")) != "APPLY_CHARGE_MOVE":
		return "no charge move for a roll of %d" % dist
	mv["player"] = player
	r = NetworkIntegration.route_action(mv)
	print("[sm11e m3b scen] charge %s -> %s: roll %d, %s" % [uid, target, dist, str(r.get("success", false))])
	return true if r.get("success", false) else "apply: " + str(r.get("error", r.get("errors", "")))


## Give the prompt dialogs that have no stable root name (Fire Overwatch) one.
static func tag_prompts() -> Array:
	var tagged: Array = []
	for child in _root().get_children():
		var scr = child.get_script()
		if scr == null or not (child is Window) or not (child as Window).visible:
			continue
		var path := str(scr.resource_path)
		if path.ends_with("FireOverwatchDialog.gd"):
			child.name = "FireOverwatchDialog"
			for sub in child.get_children():
				if sub is VBoxContainer:
					sub.name = "Content"
					break
			tagged.append("FireOverwatchDialog")
	return tagged


## Belt-and-braces: decline any prompt not under test still waiting (Fire
## Overwatch / Command Re-roll / ability re-roll) with its phase action.
static func settle() -> Array:
	var ph = phase()
	var done: Array = []
	if ph == null:
		return done
	for _i in range(6):
		if ("_awaiting_fire_overwatch" in ph and ph._awaiting_fire_overwatch) or ("_awaiting_overwatch_decision" in ph and ph._awaiting_overwatch_decision):
			ph.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": int(ph._fire_overwatch_player)})
			done.append("fire_overwatch")
		elif "awaiting_fire_overwatch" in ph and ph.awaiting_fire_overwatch:
			ph.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": 3 - int(gs().get_active_player())})
			done.append("fire_overwatch")
		elif "_awaiting_reroll_decision" in ph and ph._awaiting_reroll_decision:
			ph.execute_action({"type": "DECLINE_COMMAND_REROLL"})
			done.append("command_reroll")
		elif "awaiting_reroll_decision" in ph and ph.awaiting_reroll_decision:
			ph.execute_action({"type": "DECLINE_COMMAND_REROLL", "player": int(gs().get_active_player())})
			done.append("command_reroll")
		elif "awaiting_ability_reroll" in ph and ph.awaiting_ability_reroll:
			ph.execute_action({"type": "DECLINE_ABILITY_REROLL", "player": int(gs().get_active_player())})
			done.append("ability_reroll")
		else:
			break
	return done


## Decline (with the window action the dialog's Decline sends) every pending
## window before `window_id` — e.g. the shooter's own unit_selected_to_shoot
## window that the atomic SHOOT opens before its post-shot windows.
static func decline_until_window(window_id: String) -> int:
	var n := 0
	var ph = phase()
	while ph.has_pending_stratagem_window() and str(ph.get_pending_stratagem_window().get("window_id", "")) != window_id and n < 8:
		var w: Dictionary = ph.get_pending_stratagem_window()
		ph.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1
	return n


## Attack-batch modifiers the engine aggregator returns for attacker -> target.
static func mods(attacker: String, target: String, melee: bool) -> Dictionary:
	return _n("RulesEngine").ork11e_ab_mods(unit(attacker), unit(target), {}, melee, gs().state)


## Close every open popup Window (setup privilege before a screenshot).
static func close_popups() -> bool:
	for c in _root().get_children():
		if c is Window and c != _root() and str(c.name) != "StratagemDialog":
			c.hide()
			c.queue_free()
	return true

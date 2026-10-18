extends RefCounted
## Helpers for the WP-C5 windowed scenarios (tests/scenarios/sp/cus11e_<slug>.json)
## — Codex: Adeptus Custodes (11e) stratagems.
##
## Called from `execute_script` steps, e.g.
##   load("res://tests/helpers/cus11e_c5_scen.gd").setup(1, "Null Maiden Vigil", {})
## Only SETUP privileges (detachment flip, unit placement, flags not under test)
## and phase actions the panels send live here; every stratagem decision in the
## scenarios is a real click on the StratagemDialog / picker / S panel.

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


## Setup privileges: the Custodes player's detachment (stratagems reloaded),
## auto wound allocation, Trajann's Moment Shackle spent (its Fight-phase-start
## prompt is not under test) unless opts.keep_shackle, the Custodes unreadied,
## opts.cp = {player: cp}, opts.flags = {uid: {flag: value}}.
static func setup(player: int, det: String, opts: Dictionary = {}) -> String:
	var g = gs()
	g.state["factions"][str(player)].merge({"detachment": det}, true)
	_n("StratagemManager").load_faction_stratagems_for_player(player)
	_n("SettingsService").set("auto_allocate_wounds", true)
	if not bool(opts.get("keep_shackle", false)) and g.state.units.has("U_TRAJANN_A"):
		g.state.units["U_TRAJANN_A"]["flags"]["moment_shackle_used"] = true
	for uid in g.state.units:
		var f = g.state.units[uid].get("flags", null)
		if f is Dictionary:
			f.erase("cus11e_readied")
	var cps: Dictionary = opts.get("cp", {})
	for p in cps:
		g.state.players[str(p)]["cp"] = int(cps[p])
	var fl: Dictionary = opts.get("flags", {})
	for uid in fl:
		for k in fl[uid]:
			g.state.units[uid]["flags"][k] = fl[uid][k]
	refresh()
	print("[cus11e scen] setup: P%d detachment %s opts %s" % [player, det, str(opts)])
	return str(g.state.factions[str(player)].get("detachment", ""))


static func refresh() -> void:
	var m = main()
	if m != null and m.has_method("_recreate_unit_visuals"):
		m._recreate_unit_visuals()


## Place a unit like the fixture generator: rows of `cols` models centred on
## cx, the front rank's edge on front_y (inches), rows growing in `dir` (+1 = +y).
static func place(uid: String, cx: float, front_y: float, cols: int = 3, dir: int = 1) -> bool:
	var models: Array = gs().state.units[uid].get("models", [])
	var n := models.size()
	if n == 0:
		return false
	var r := 0.0
	for m in models:
		var mm := float(m.get("base_mm", 32))
		var dims = m.get("base_dimensions", null)
		if typeof(dims) == TYPE_DICTIONARY and not dims.is_empty():
			mm = maxf(float(dims.get("length", mm)), float(dims.get("width", mm)))
		r = maxf(r, mm / 25.4 / 2.0)
	var cell := r * 2.0 + 0.25
	cols = maxi(1, mini(cols, n))
	for i in range(n):
		var row := i / cols
		var col := i % cols
		var in_row := mini(cols, n - row * cols)
		var x := cx + (float(col) - float(in_row - 1) / 2.0) * cell
		var y := front_y + float(dir) * (r + float(row) * cell)
		models[i]["position"] = {"x": x * PX, "y": y * PX}
		models[i]["rotation"] = 0.0
	refresh()
	return true


## Put a unit into Strategic Reserves / deep strike (off the board).
static func to_reserves(uid: String, reserve_type: String = "deep_strike") -> bool:
	var u: Dictionary = gs().state.units[uid]
	u["status"] = gs().UnitStatus.IN_RESERVES
	u["reserve_type"] = reserve_type
	for m in u.models:
		m["position"] = null
	refresh()
	return true


static func weapon(uid: String, contains: String = "") -> String:
	var w = _n("RulesEngine").get_unit_weapons(uid, gs().state)
	for mid in w:
		for wid in w[mid]:
			if str(wid).ends_with("_melee"):
				continue
			if contains == "" or contains.to_lower() in str(wid).to_lower():
				return str(wid)
	return ""


static func assignment(uid: String, wid: String, tid: String) -> Dictionary:
	var model_ids: Array = []
	var w = _n("RulesEngine").get_unit_weapons(uid, gs().state)
	for mid in w:
		if wid in w[mid]:
			model_ids.append(str(mid))
	return {"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}


## The atomic SHOOT the shooting panel's auto-resolve sends.
static func shoot(player: int, uid: String, tid: String, contains: String = "", seed_val: int = 7) -> Variant:
	var wid := weapon(uid, contains)
	if wid == "":
		return "no weapon matching '%s' on %s" % [contains, uid]
	var r: Dictionary = phase().execute_action({"type": "SHOOT", "actor_unit_id": uid, "player": player,
		"payload": {"assignments": [assignment(uid, wid, tid)], "rng_seed": seed_val}})
	print("[cus11e scen] SHOOT %s (%s) -> %s: %s" % [uid, wid, tid, str(r.get("success", false))])
	return true if r.get("success", false) else str(r.get("error", r.get("errors", "failed")))


## The unit's longest-ranged ranged weapon.
static func longest_weapon(uid: String) -> String:
	var best := ""
	var best_r := -1
	var w = _n("RulesEngine").get_unit_weapons(uid, gs().state)
	for mid in w:
		for wid in w[mid]:
			if str(wid).ends_with("_melee"):
				continue
			var r := int(str(_n("RulesEngine").get_weapon_profile(str(wid), gs().state).get("range", "0")).to_int())
			if r > best_r:
				best_r = r
				best = str(wid)
	return best


## ASSIGN_TARGET + CONFIRM_TARGETS (the interactive shooting panel's actions).
## contains == "" -> the longest-ranged weapon.
static func assign_and_confirm(player: int, uid: String, tid: String, contains: String = "") -> Variant:
	var wid := weapon(uid, contains) if contains != "" else longest_weapon(uid)
	if wid == "":
		return "no weapon matching '%s' on %s (weapons: %s)" % [contains, uid, str(_n("RulesEngine").get_unit_weapons(uid, gs().state))]
	var ph = phase()
	var a = assignment(uid, wid, tid)
	var r: Dictionary = ph.execute_action({"type": "ASSIGN_TARGET", "actor_unit_id": uid, "player": player, "payload": a})
	if not r.get("success", false):
		return "assign: " + str(r.get("error", r.get("errors", "")))
	r = ph.execute_action({"type": "CONFIRM_TARGETS", "player": player})
	print("[cus11e scen] ASSIGN+CONFIRM %s (%s) -> %s: %s" % [uid, wid, tid, str(r.get("success", false))])
	return true if r.get("success", false) else "confirm: " + str(r.get("error", r.get("errors", "")))


static func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p


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
	print("[cus11e scen] move %s by (%.1f, %.1f)\": %s" % [uid, dx, dy, str(c.get("success", false))])
	return true if c.get("success", false) else "confirm: " + str(c.get("error", c.get("errors", "")))


static func window_id() -> String:
	var ph = phase()
	if ph == null or not ph.has_pending_stratagem_window():
		return ""
	return str(ph.get_pending_stratagem_window().get("window_id", ""))


static func decider() -> int:
	return int(phase().get_pending_stratagem_window_decider())


static func flag(uid: String, key: String) -> Variant:
	return gs().state.units[uid].get("flags", {}).get(key, null)


## The last dice block of `context` (optionally of `uid`'s attack).
static func dice(context: String, uid: String = "") -> Dictionary:
	var out := {}
	for b in phase().dice_log:
		if typeof(b) != TYPE_DICTIONARY or str(b.get("context", "")) != context:
			continue
		if uid != "":
			var who := str(b.get("attacker_unit_id", b.get("unit_id", b.get("actor_unit_id", uid))))
			if who != uid:
				continue
		out = b
	print("[cus11e scen] dice[%s %s] = %s" % [context, uid, str(out).substr(0, 600)])
	return out


static func alive(uid: String) -> int:
	var n := 0
	for m in gs().state.units[uid].models:
		if m.get("alive", true):
			n += 1
	return n


static func codex():
	return load("res://scripts/codex/custodes/CustodesCodex11e.gd")


static func unit(uid: String) -> Dictionary:
	return gs().state.units.get(uid, {})


## Hit-roll effects of the codex on one batch (live state).
static func hit_fx(attacker: String, target: String, melee: bool) -> Dictionary:
	return codex().hit_roll_effects(unit(attacker), unit(target), melee, gs().state)


static func wound_fx(attacker: String, target: String, melee: bool, s: int, t: int) -> Dictionary:
	return codex().wound_roll_effects(unit(attacker), unit(target), melee, s, t)


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
	refresh()
	return true


static func charge_roll(uid: String) -> Dictionary:
	var out := {}
	for d in phase().dice_log:
		if typeof(d) == TYPE_DICTIONARY and str(d.get("context", "")) == "charge_roll" and str(d.get("unit_id", "")) == uid:
			out = d
	print("[cus11e scen] charge_roll[%s] = %s" % [uid, str(out)])
	return out


## Give the prompt dialogs that have no stable root name (Fire Overwatch) one,
## so a scenario can REAL-click their Decline: /root/FireOverwatchDialog/Content/Buttons/DeclineButton.
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
	if not tagged.is_empty():
		print("[cus11e scen] tagged prompts: %s" % str(tagged))
	return tagged


## Belt-and-braces after the real clicks: decline any prompt not under test
## that is still waiting (Fire Overwatch / Command Re-roll / Krump and Run /
## Scatter / ability re-roll) with the phase action its dialog sends.
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
		elif "_awaiting_krump_and_run" in ph and ph._awaiting_krump_and_run:
			ph.execute_action({"type": "DECLINE_KRUMP_AND_RUN"})
			done.append("krump_and_run")
		elif "_awaiting_scatter" in ph and ph._awaiting_scatter:
			ph.execute_action({"type": "DECLINE_SCATTER"})
			done.append("scatter")
		else:
			break
	if not done.is_empty():
		print("[cus11e scen] settle (action fallback): %s" % str(done))
	return done


static func log_count(needle: String) -> int:
	return int(_n("ScenarioRunner").event_log_count_containing(needle))

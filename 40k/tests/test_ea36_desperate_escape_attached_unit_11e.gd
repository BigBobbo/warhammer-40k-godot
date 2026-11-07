extends SceneTree

# EA-36 (11e 09.07 BEFORE MOVING / 09.07.01 Commentary, 19.01, 06.02, 06.03):
#   09.07: "Desperate Escape: ... Make a hazard roll for each model in your
#          unit (06.03)." 09.07.01: "Must make one hazard roll for each model
#          in that unit."
#   19.01: "An attached unit is a single unit for all rules purposes."
#   06.02: mortal wounds are resolved one at a time, non-CHARACTER models
#          first, "until either all of them have been inflicted or that unit is
#          destroyed".
#   06.03: "... or 3 mortal wounds instead if each model in that unit is a
#          MONSTER/VEHICLE model".
#
# Before the fix FallBackMove.before_moving counted (and 06.03 judged) only the
# bodyguard's own models, and the mortal wounds were allocated inside the
# bodyguard dict only — an attached leader made no hazard roll and could never
# take a hazard mortal wound.
#
# Drives the REAL MovementPhase BEGIN_FALL_BACK and the FallBackMove template.
#
# Usage: godot --headless --path . -s tests/test_ea36_desperate_escape_attached_unit_11e.gd

var passed := 0
var failed := 0
var _ran := false

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

func _m(id: String, x: float, y: float, w: int, base: int = 32) -> Dictionary:
	return {"id": id, "alive": true, "wounds": w, "current_wounds": w, "base_mm": base, "base_type": "circular", "position": {"x": x, "y": y}}

func _unit(id: String, owner: int, name: String, kws: Array, models: Array, wounds: int, shocked: bool = false) -> Dictionary:
	return {"id": id, "owner": owner, "status": 2, "flags": {"battle_shocked": shocked}, "status_effects": {"battle_shocked": shocked},
		"meta": {"name": name, "keywords": kws, "abilities": [],
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": wounds, "leadership": 6, "objective_control": 2}},
		"models": models, "weapons": [], "attachment_data": {}}

## 5 Intercessors (W2) led by a Captain (W5), engaged with one Boy to the south.
func _intercessors_and_captain(shocked: bool) -> Dictionary:
	var bg := []
	for i in range(5):
		bg.append(_m("m%d" % i, 400.0 + 60.0 * i, 1000.0, 2))
	var u := {
		"U_INT": _unit("U_INT", 1, "Intercessors", ["INFANTRY", "IMPERIUM"], bg, 2, shocked),
		"U_CAP": _unit("U_CAP", 1, "Captain", ["INFANTRY", "CHARACTER", "IMPERIUM"], [_m("m0", 520.0, 940.0, 5, 40)], 5, shocked),
		"U_EN": _unit("U_EN", 2, "Boyz", ["INFANTRY", "ORKS"], [_m("e0", 400.0, 1060.0, 1)], 1)}
	u.U_INT.attachment_data = {"attached_characters": ["U_CAP"]}
	u.U_CAP["attached_to"] = "U_INT"
	return u

func _phase_with(gs, pm, base_state: Dictionary, units: Dictionary):
	gs.state = base_state.duplicate(true)
	gs.state["units"] = units
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 7
	pm.transition_to_phase(7)
	return pm.get_current_phase_instance()

func _rolls(phase, uid: String) -> Array:
	return phase.active_moves.get(uid, {}).get("desperate_escape_ctx", {}).get("hazard", {}).get("rolls", [])

func _alive(gs, uid: String) -> int:
	var n := 0
	for m in gs.state.units[uid].models:
		if m.get("alive", true):
			n += 1
	return n

func _run_tests():
	if _ran:
		return
	_ran = true
	print("\n=== test_ea36_desperate_escape_attached_unit_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var tm = root.get_node_or_null("TerrainManager")
	var rules = root.get_node_or_null("RulesEngine")
	if gs == null or pm == null or tm == null or rules == null:
		_check("autoloads reachable", false)
		_finish()
		return
	var prev_edition: int = GameConstants.edition
	var prev_terrain: Array = tm.terrain_features.duplicate(true)
	var prev_state: Dictionary = gs.state.duplicate(true)
	var base_state: Dictionary = gs.state.duplicate(true)
	tm.terrain_features = []
	base_state["board"]["terrain"] = []
	GameConstants.edition = 11
	var phase

	print("-- one hazard roll per model of the whole Attached unit --")
	for shocked in [false, true]:
		phase = _phase_with(gs, pm, base_state, _intercessors_and_captain(shocked))
		rules.set_test_seed(11)
		var payload := {} if shocked else {"fall_back_mode": "desperate_escape"}
		var r: Dictionary = phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_INT", "player": 1, "payload": payload})
		var mode := str(phase.active_moves.get("U_INT", {}).get("fall_back_mode", ""))
		_check("%s: 5 Intercessors + their Captain make SIX hazard rolls" % ("battle-shocked (forced)" if shocked else "unshocked (chosen)"),
			r.get("success", false) and mode == "desperate_escape" and _rolls(phase, "U_INT").size() == 6,
			"begin=%s mode=%s rolls=%s" % [str(r.get("success")), mode, str(_rolls(phase, "U_INT"))])

	print("\n-- the template: counts and the 06.03 MONSTER/VEHICLE test, per model --")
	var fb = MoveTypes.get_type("fall_back")
	var board := {"units": _intercessors_and_captain(false)}
	rules.set_test_seed(2)
	var ctx: Dictionary = fb.before_moving("U_INT", board, rules.make_rng(), {"mode": "desperate_escape"})
	_check("before_moving: 6 rolls for the Attached unit", ctx.get("hazard", {}).get("rolls", []).size() == 6, str(ctx))
	board.units.U_INT.models[4]["alive"] = false
	board.units.U_CAP.models[0]["alive"] = true
	ctx = fb.before_moving("U_INT", board, rules.make_rng(), {"mode": "desperate_escape"})
	_check("... only alive models roll (4 Intercessors + the Captain = 5)", ctx.get("hazard", {}).get("rolls", []).size() == 5, str(ctx.get("hazard", {})))
	# A VEHICLE bodyguard led by an INFANTRY character: not every model is a
	# MONSTER/VEHICLE model, so a failed roll is 1 mortal wound, not 3.
	var veh := {"units": {
		"U_GUNZ": _unit("U_GUNZ", 1, "Mek Gunz", ["VEHICLE", "ORKS"], [_m("m0", 400, 1000, 6, 60), _m("m1", 480, 1000, 6, 60)], 6),
		"U_MEK": _unit("U_MEK", 1, "Mek", ["INFANTRY", "CHARACTER", "ORKS"], [_m("m0", 440, 1080, 4)], 4)}}
	veh.units.U_GUNZ.attachment_data = {"attached_characters": ["U_MEK"]}
	veh.units.U_MEK["attached_to"] = "U_GUNZ"
	ctx = fb.before_moving("U_GUNZ", veh, rules.make_rng(), {"mode": "desperate_escape"})
	_check("VEHICLE bodyguard + INFANTRY leader: 3 rolls, 1 mortal wound per failure (not every model is MONSTER/VEHICLE)",
		ctx.get("hazard", {}).get("rolls", []).size() == 3 and int(ctx.get("hazard", {}).get("per_model_mw", 0)) == 1, str(ctx.get("hazard", {})))
	veh.units.U_GUNZ.attachment_data = {"attached_characters": []}
	veh.units.U_MEK.erase("attached_to")
	ctx = fb.before_moving("U_GUNZ", veh, rules.make_rng(), {"mode": "desperate_escape"})
	_check("control: the same VEHICLE unit on its own: 2 rolls, 3 mortal wounds per failure",
		ctx.get("hazard", {}).get("rolls", []).size() == 2 and int(ctx.get("hazard", {}).get("per_model_mw", 0)) == 3, str(ctx.get("hazard", {})))

	print("\n-- 06.02: the mortal wounds are pooled across the Attached unit --")
	var has_cas: bool = "static func hazard_casualties" in str(load("res://scripts/rules/movetypes/FallBackMove.gd").source_code)
	_check("FallBackMove.hazard_casualties exists", has_cas)
	var small := func() -> Dictionary:
		var u := {"U_BG": _unit("U_BG", 1, "Bodyguard", ["INFANTRY"], [_m("m0", 400, 1000, 1), _m("m1", 460, 1000, 1)], 1),
			"U_LDR": _unit("U_LDR", 1, "Leader", ["INFANTRY", "CHARACTER"], [_m("m0", 430, 940, 4, 40)], 4),
			"U_EN": _unit("U_EN", 2, "Boyz", ["INFANTRY"], [_m("e0", 400, 1060, 1)], 1)}
		u.U_BG.attachment_data = {"attached_characters": ["U_LDR"]}
		u.U_LDR["attached_to"] = "U_BG"
		return u
	if has_cas:
		var FB = load("res://scripts/rules/movetypes/FallBackMove.gd")
		var cas: Dictionary = FB.hazard_casualties("U_BG", 4, {"units": small.call()}, "desperate_escape")
		var ldr_w := -1
		var bg_dead := 0
		for d in cas.get("diffs", []):
			if str(d.path) == "units.U_LDR.models.0.current_wounds":
				ldr_w = int(d.value)
			if str(d.path).begins_with("units.U_BG.models.") and str(d.path).ends_with(".alive") and d.value == false:
				bg_dead += 1
		_check("4 mortal wounds vs 2 x W1 bodyguard + a W4 leader: both bodyguard models die, then the leader drops to 2 wounds",
			bg_dead == 2 and ldr_w == 2 and int(cas.get("applied", 0)) == 4 and int(cas.get("lost", -1)) == 0, str(cas))
		cas = FB.hazard_casualties("U_BG", 1, {"units": small.call()}, "desperate_escape")
		var touched_leader := false
		for d in cas.get("diffs", []):
			if str(d.path).begins_with("units.U_LDR."):
				touched_leader = true
		_check("1 mortal wound goes to a non-CHARACTER model first", not touched_leader and cas.get("destroyed", []).size() == 1, str(cas))
	# End to end through BEGIN_FALL_BACK: find a seed whose 3 rolls all fail (3
	# MW): the bodyguard dies and the leader loses one wound. Before the fix the
	# leader rolled no die (2 rolls: at most 2 MW) and took none.
	var found := false
	for s in range(1, 600):
		phase = _phase_with(gs, pm, base_state, small.call())
		rules.set_test_seed(s)
		phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_BG", "player": 1, "payload": {"fall_back_mode": "desperate_escape"}})
		var hz: Dictionary = phase.active_moves.get("U_BG", {}).get("desperate_escape_ctx", {}).get("hazard", {})
		if int(hz.get("failures", 0)) >= 3:
			found = true
			_check("BEGIN_FALL_BACK (seed %d, rolls %s): 3 failures = 3 MW — both bodyguard models destroyed, the leader on 3 wounds" % [s, str(hz.get("rolls", []))],
				_alive(gs, "U_BG") == 0 and int(gs.state.units.U_LDR.models[0].current_wounds) == 3 and gs.state.units.U_LDR.models[0].alive,
				"bg alive=%d leader=%s" % [_alive(gs, "U_BG"), str(gs.state.units.U_LDR.models[0])])
			break
	_check("found a seed where all three hazard rolls fail (needs the leader's roll)", found)
	# The movement panel and game log name the attached models.
	phase = _phase_with(gs, pm, base_state, _intercessors_and_captain(false))
	rules.set_test_seed(4)
	phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_INT", "player": 1, "payload": {"fall_back_mode": "desperate_escape"}})
	var dl: Array = phase.get_dice_log()
	_check("the dice log entry names the attached leader ('Desperate Escape (Intercessors (+1 attached))', 6 rolls)",
		not dl.is_empty() and "(+1 attached)" in str(dl.back().get("type", "")) and dl.back().get("rolls", []).size() == 6,
		str(dl.back() if not dl.is_empty() else {}))

	tm.terrain_features = prev_terrain
	gs.state = prev_state
	GameConstants.edition = prev_edition
	rules.set_test_seed(-1)
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

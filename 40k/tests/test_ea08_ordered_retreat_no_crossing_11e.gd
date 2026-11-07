extends SceneTree

# EA-08 (11e 09.07 FALL-BACK MOVE, 09.02.02 Selecting Modes, 03.01):
#   03.01: "Each time you move a model, unless otherwise stated: ... Its base
#          cannot be moved through enemy models."
#   09.07 WHILE MOVING: "Desperate Escape: Each model that is moved can be
#          moved through enemy models."
#   09.02.02: conditions "labelled with a mode name only apply if you selected
#          that mode"; "ordered retreat is not mandatory, so you could select
#          desperate escape instead".
#
# Before the fix every 11e fall-back - Ordered Retreat included - could move
# straight through enemy models: MovementPhase only path-checked NORMAL /
# ADVANCE moves, and no UI or action let an unshocked unit choose Desperate
# Escape.
#
# Drives the REAL MovementPhase (STAGE_MODEL_MOVE - what the drag UI and the AI
# send - SET_MODEL_DEST, CONFIRM_UNIT_MOVE, the new SET_FALL_BACK_MODE) on an
# open board (TerrainManager's default layout is cleared).
#
# Geometry: 32 mm bases (radius 25.197 px, base contact = 50.394 px apart), 40
# px per inch, 11e engagement range 2" = 80 px edge to edge.
#
# Usage: godot --headless --path . -s tests/test_ea08_ordered_retreat_no_crossing_11e.gd

var passed := 0
var failed := 0
var _ran := false

const ERR_OR := "Ordered Retreat cannot move through enemy models — choose Desperate Escape to move through them (09.07)"
const ERR_ENEMY := "Cannot move through enemy models during Normal Move or Advance"
const ERR_MV := "Cannot move through Monster or Vehicle models"
const CONTACT_32 := 50.394  # 2 x 32 mm base radius in px

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

func _unit(id: String, owner: int, kws: Array, positions: Array, base_mm: int = 32, wounds: int = 1, name: String = "", shocked: bool = false) -> Dictionary:
	var models := []
	var i := 0
	for p in positions:
		models.append({"id": "m%d" % i, "alive": true, "wounds": wounds, "current_wounds": wounds,
			"base_mm": base_mm, "base_type": "circular", "position": {"x": p.x, "y": p.y}})
		i += 1
	return {"id": id, "owner": owner, "status": 2, "flags": {"battle_shocked": shocked},
		"status_effects": {"battle_shocked": shocked},
		"meta": {"name": name if name != "" else id, "keywords": kws, "abilities": [],
			"stats": {"move": 8, "toughness": 4, "save": 3, "wounds": wounds, "leadership": 6, "objective_control": 1}},
		"models": models, "weapons": [], "attachment_data": {}}

func _attach(units: Dictionary, char_id: String, bg_id: String) -> void:
	units[bg_id]["attachment_data"] = {"attached_characters": [char_id]}
	units[char_id]["attached_to"] = bg_id

## Seed a fresh Movement phase with `units`, P1 active. Returns the phase.
func _phase_with(gs, pm, base_state: Dictionary, units: Dictionary):
	gs.state = base_state.duplicate(true)
	gs.state["units"] = units
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 7
	pm.transition_to_phase(7)
	return pm.get_current_phase_instance()

func _begin_fb(phase, unit_id: String, mode: String = "") -> Dictionary:
	var payload := {}
	if mode != "":
		payload["fall_back_mode"] = mode
	return phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": unit_id, "player": 1, "payload": payload})

func _stage(phase, actor: String, model_id: String, dest: Vector2, execute: bool = false, source_unit: String = "") -> Dictionary:
	var payload := {"model_id": model_id, "dest": [dest.x, dest.y], "rotation": 0.0}
	if source_unit != "" and source_unit != actor:
		payload["model_source_unit_id"] = source_unit
	var action := {"type": "STAGE_MODEL_MOVE", "actor_unit_id": actor, "player": 1, "payload": payload}
	return phase.execute_action(action) if execute else phase.validate_action(action)

func _smd(phase, actor: String, model_id: String, dest: Vector2) -> Dictionary:
	return phase._validate_set_model_dest({"actor_unit_id": actor, "payload": {"model_id": model_id, "dest": [dest.x, dest.y]}})

## One-model mover U_FB at `from`, one enemy unit U_EN (keywords en_kws) with
## models at en_pos; begins a fall back in `mode` ("" = engine default) and
## validates a drop at `dest` through both live validators.
func _case(gs, pm, base_state, from: Vector2, en_pos: Array, dest: Vector2, mode: String = "", mover_kws: Array = ["INFANTRY"], en_kws: Array = ["INFANTRY"], en_base: int = 32) -> Dictionary:
	var phase = _phase_with(gs, pm, base_state, {
		"U_FB": _unit("U_FB", 1, mover_kws, [from], 32, 1, "Retreaters"),
		"U_EN": _unit("U_EN", 2, en_kws, en_pos, en_base, 1, "Blockers")})
	var begin := _begin_fb(phase, "U_FB", mode)
	var md: Dictionary = phase.active_moves.get("U_FB", {})
	return {"phase": phase, "begin": begin, "fb_mode": str(md.get("fall_back_mode", "")),
		"stage": _stage(phase, "U_FB", "m0", dest), "smd": _smd(phase, "U_FB", "m0", dest)}

func _both_valid(r: Dictionary) -> bool:
	return r.stage.get("valid", false) and r.smd.get("valid", false)

func _both_refused_with(r: Dictionary, msg: String) -> bool:
	return (not r.stage.get("valid", true)) and (not r.smd.get("valid", true)) \
		and msg in r.stage.get("errors", []) and msg in r.smd.get("errors", [])

func _brief(r: Dictionary) -> String:
	return "mode=%s stage=%s smd=%s" % [str(r.get("fb_mode", "")), str(r.stage), str(r.smd)]

func _pos(gs, unit_id: String, idx: int = 0) -> Vector2:
	var p = gs.state.get("units", {}).get(unit_id, {}).get("models", [{}])[idx].get("position", {})
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	return Vector2.INF

func _errors_have(r: Dictionary, parts: Array) -> bool:
	var errs: Array = r.get("errors", [])
	if r.has("error"):
		errs = errs + [str(r.error)]
	for e in errs:
		var all_in := true
		for part in parts:
			if not str(part) in str(e):
				all_in = false
				break
		if all_in:
			return true
	return false

func _hazard_rolls(phase, unit_id: String) -> Array:
	return phase.active_moves.get(unit_id, {}).get("desperate_escape_ctx", {}).get("hazard", {}).get("rolls", [])

func _run_tests():
	if _ran:
		return
	_ran = true
	print("\n=== test_ea08_ordered_retreat_no_crossing_11e ===\n")
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
	var r: Dictionary
	var phase

	# Mover at (400,1000); an enemy 60 px north of it (9.6 px edge gap: engaged).
	# (400,800) is 140 px from the enemy (2.24" edge to edge: unengaged).
	var from := Vector2(400, 1000)
	var north := [Vector2(400, 940)]
	var through := Vector2(400, 800)

	print("-- 09.07: Ordered Retreat cannot move through enemy models --")
	r = _case(gs, pm, base_state, from, north, through)
	_check("an unshocked unit's fall-back defaults to Ordered Retreat", r.fb_mode == "ordered_retreat", _brief(r))
	_check("Ordered Retreat straight through an enemy model is refused (STAGE + SET_MODEL_DEST)", _both_refused_with(r, ERR_OR), _brief(r))
	r = _case(gs, pm, base_state, from, north, through, "desperate_escape")
	_check("Desperate Escape through the same enemy model is legal (WHILE MOVING)", r.fb_mode == "desperate_escape" and _both_valid(r), _brief(r))

	print("\n-- base contact is not moving through (charge snaps, float positions) --")
	var contact := [Vector2(400, 1000 + CONTACT_32)]
	r = _case(gs, pm, base_state, from, contact, Vector2(400, 900))
	_check("Ordered Retreat straight away from an enemy in exact base contact is legal", _both_valid(r), _brief(r))
	r = _case(gs, pm, base_state, from, [Vector2(400, 1000 + CONTACT_32 - 0.4)], Vector2(400, 900))
	_check("... and from 0.4 px of overlap (what a charge snap can leave)", _both_valid(r), _brief(r))
	r = _case(gs, pm, base_state, from, contact, Vector2(560, 1000))
	_check("Ordered Retreat sideways along base contact is legal", _both_valid(r), _brief(r))
	r = _case(gs, pm, base_state, from, [Vector2(400, 1030)], Vector2(400, 880))
	_check("a set-up that left the bases deeply overlapped: moving away is legal", _both_valid(r), _brief(r))
	r = _case(gs, pm, base_state, from, [Vector2(400, 1030)], Vector2(400, 1180))
	_check("... moving on through the overlapped enemy model is refused", _both_refused_with(r, ERR_OR), _brief(r))

	print("\n-- enemy MONSTER/VEHICLE models --")
	# 60 mm VEHICLE: radius 47.24 px; contact with a 32 mm base = 72.44 px.
	r = _case(gs, pm, base_state, from, [Vector2(400, 1000 - 72.44 - 10.0)], Vector2(400, 760), "", ["INFANTRY"], ["VEHICLE"], 60)
	_check("Ordered Retreat through an enemy VEHICLE is refused", not r.stage.get("valid", true) and not r.smd.get("valid", true), _brief(r))
	r = _case(gs, pm, base_state, from, [Vector2(400, 1000 - 72.44 - 10.0)], Vector2(400, 760), "desperate_escape", ["INFANTRY"], ["VEHICLE"], 60)
	_check("Desperate Escape through an enemy VEHICLE is legal ('each model ... can be moved through enemy models')", _both_valid(r), _brief(r))
	r = _case(gs, pm, base_state, from, [Vector2(400, 1000 + 72.44)], Vector2(400, 860), "", ["INFANTRY"], ["VEHICLE"], 60)
	_check("Ordered Retreat straight away from an enemy VEHICLE in exact base contact is legal", _both_valid(r), _brief(r))

	print("\n-- 23.02: \"Each time a unit makes any type of move, its models can be moved through AIRCRAFT models\" --")
	# The Boy north of the mover engages it; an enemy Dakkajet (its keywords:
	# AIRCRAFT and VEHICLE, 60 mm) stands 20 px south of it. A fall-back 260 px
	# straight south passes through the Dakkajet and ends unengaged (95 px clear).
	var jet_kws := ["AIRCRAFT", "DAKKAJET", "FLY", "ORKS", "SPEED FREEKS", "VEHICLE"]
	var plain_kws := ["DAKKAJET", "ORKS", "SPEED FREEKS", "VEHICLE"]
	var jet_pos := Vector2(400, 1000 + 25.197 + 47.244 + 20.0)
	for kws in [jet_kws, plain_kws]:
		var is_air: bool = "AIRCRAFT" in kws
		phase = _phase_with(gs, pm, base_state, {
			"U_FB": _unit("U_FB", 1, ["INFANTRY"], [from], 32, 1, "Retreaters"),
			"U_EN": _unit("U_EN", 2, ["INFANTRY"], north, 32, 1, "Blockers"),
			"U_JET": _unit("U_JET", 2, kws, [jet_pos], 60, 12, "Dakkajet")})
		_begin_fb(phase, "U_FB")
		r = {"fb_mode": str(phase.active_moves.get("U_FB", {}).get("fall_back_mode", "")),
			"stage": _stage(phase, "U_FB", "m0", Vector2(400, 1260)), "smd": _smd(phase, "U_FB", "m0", Vector2(400, 1260))}
		if is_air:
			_check("Ordered Retreat through an enemy AIRCRAFT model (a Dakkajet) is legal", r.fb_mode == "ordered_retreat" and _both_valid(r), _brief(r))
		else:
			_check("control: the same VEHICLE without the AIRCRAFT keyword still blocks the Ordered Retreat",
				not r.stage.get("valid", true) and not r.smd.get("valid", true), _brief(r))
	# A normal move (8") 300 px straight south through an enemy AIRCRAFT model
	# 140 px away (not engaged), ending 110 px clear of it.
	for kws in [jet_kws, plain_kws]:
		var is_air2: bool = "AIRCRAFT" in kws
		phase = _phase_with(gs, pm, base_state, {
			"U_FB": _unit("U_FB", 1, ["INFANTRY"], [from], 32, 1, "Movers"),
			"U_JET": _unit("U_JET", 2, kws, [Vector2(400, 1140)], 32, 12, "Dakkajet")})
		phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_FB", "player": 1, "payload": {}})
		r = {"stage": _stage(phase, "U_FB", "m0", Vector2(400, 1300)), "smd": _smd(phase, "U_FB", "m0", Vector2(400, 1300))}
		if is_air2:
			_check("a normal move through an enemy AIRCRAFT model is legal (any type of move)", _both_valid(r), _brief(r))
		else:
			_check("control: a normal move through the same model without AIRCRAFT is refused",
				not r.stage.get("valid", true) and not r.smd.get("valid", true), _brief(r))

	print("\n-- controls: what does not change --")
	r = _case(gs, pm, base_state, from, north, through, "", ["INFANTRY", "FLY"])
	_check("a FLY unit's Ordered Retreat may still pass over enemy models (pre-existing FLY exemption)", _both_valid(r), _brief(r))
	phase = _phase_with(gs, pm, base_state, {
		"U_FB": _unit("U_FB", 1, ["INFANTRY"], [from], 32, 1, "Movers"),
		"U_EN": _unit("U_EN", 2, ["INFANTRY"], [Vector2(400, 860)], 32, 1, "Blockers")})
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_FB", "player": 1, "payload": {}})
	r = {"stage": _stage(phase, "U_FB", "m0", Vector2(400, 700)), "smd": _smd(phase, "U_FB", "m0", Vector2(400, 700))}
	_check("a normal move through an enemy keeps its own refusal text", _both_refused_with(r, ERR_ENEMY), _brief(r))
	r = _case(gs, pm, base_state, from, north, Vector2(400, 1015))
	_check("a fall-back must still end unengaged", not r.stage.get("valid", true) and _errors_have(r.stage, ["Fall Back must end outside engagement range"]), _brief(r))
	GameConstants.edition = 10
	r = _case(gs, pm, base_state, from, north, through)
	_check("10e: a fall-back may still move through enemy models (its desperate escape tests are made at confirm)", _both_valid(r), _brief(r))
	GameConstants.edition = 11

	print("\n-- choosing Desperate Escape after Fall Back began (SET_FALL_BACK_MODE) --")
	var two_model := func() -> Dictionary:
		return {"U_FB": _unit("U_FB", 1, ["INFANTRY"], [from, Vector2(460, 1000)], 32, 1, "Retreaters"),
			"U_EN": _unit("U_EN", 2, ["INFANTRY"], north, 32, 1, "Blockers")}
	phase = _phase_with(gs, pm, base_state, two_model.call())
	_begin_fb(phase, "U_FB")
	r = phase.validate_action({"type": "SET_FALL_BACK_MODE", "actor_unit_id": "U_FB", "player": 1, "payload": {"fall_back_mode": "desperate_escape"}})
	_check("SET_FALL_BACK_MODE ordered_retreat -> desperate_escape is accepted before any model moved", r.get("valid", false), str(r))
	rules.set_test_seed(5)
	var gel = root.get_node_or_null("GameEventLog")
	var log_before: int = gel.get_all_entries().size() if gel != null and gel.has_method("get_all_entries") else -1
	var dice_before: int = phase.get_dice_log().size()
	var set_r: Dictionary = phase.execute_action({"type": "SET_FALL_BACK_MODE", "actor_unit_id": "U_FB", "player": 1, "payload": {"fall_back_mode": "desperate_escape"}})
	var rolls_after_set: Array = _hazard_rolls(phase, "U_FB").duplicate()
	_check("... executed: the move is now a Desperate Escape with one hazard roll per model (2)",
		set_r.get("success", false) and str(phase.active_moves.U_FB.get("fall_back_mode", "")) == "desperate_escape" and rolls_after_set.size() == 2,
		"set=%s mode=%s rolls=%s" % [str(set_r.get("success", set_r.get("errors"))), str(phase.active_moves.get("U_FB", {}).get("fall_back_mode", "")), str(rolls_after_set)])
	_check("... the hazard rolls are on the movement dice log", phase.get_dice_log().size() > dice_before
		and str(phase.get_dice_log().back().get("type", "")).begins_with("Desperate Escape") and phase.get_dice_log().back().get("rolls", []) == rolls_after_set,
		str(phase.get_dice_log().back() if not phase.get_dice_log().is_empty() else {}))
	var logged := false
	if gel != null and gel.has_method("get_all_entries"):
		var entries: Array = gel.get_all_entries()
		for i in range(maxi(0, log_before), entries.size()):
			if "Desperate Escape: Retreaters makes 2 hazard roll(s)" in str(entries[i].get("text", "")):
				logged = true
	_check("... and in the game log ('Desperate Escape: Retreaters makes 2 hazard roll(s) ...')", logged)
	var alive_after_set := 0
	for m in gs.state.units.U_FB.models:
		if m.get("alive", true):
			alive_after_set += 1
	if alive_after_set > 0:
		var live_mid := "m0" if gs.state.units.U_FB.models[0].get("alive", true) else "m1"
		var live_from: Vector2 = _pos(gs, "U_FB", 0 if live_mid == "m0" else 1)
		r = _stage(phase, "U_FB", live_mid, Vector2(live_from.x, 800))
		_check("... and the model may now move through the enemy model", r.get("valid", false), str(r))
	r = phase.validate_action({"type": "SET_FALL_BACK_MODE", "actor_unit_id": "U_FB", "player": 1, "payload": {"fall_back_mode": "ordered_retreat"}})
	_check("back to Ordered Retreat is refused once the hazard rolls are made", not r.get("valid", true) and _errors_have(r, ["hazard rolls have been made"]), str(r))
	# Reset Unit + Fall Back again: the hazard rolls are not made a second time.
	phase.execute_action({"type": "RESET_UNIT_MOVE", "actor_unit_id": "U_FB", "player": 1, "payload": {}})
	var alive_before_rebegin := 0
	for m in gs.state.units.U_FB.models:
		if m.get("alive", true):
			alive_before_rebegin += 1
	rules.set_test_seed(99)
	var rb: Dictionary = _begin_fb(phase, "U_FB", "ordered_retreat")
	var alive_after_rebegin := 0
	for m in gs.state.units.U_FB.models:
		if m.get("alive", true):
			alive_after_rebegin += 1
	_check("Reset Unit then Fall Back again: still a Desperate Escape, the same hazard rolls, no new casualties",
		rb.get("success", false) and str(phase.active_moves.get("U_FB", {}).get("fall_back_mode", "")) == "desperate_escape"
		and _hazard_rolls(phase, "U_FB") == rolls_after_set and alive_after_rebegin == alive_before_rebegin,
		"begin=%s mode=%s rolls=%s (were %s) alive %d -> %d" % [str(rb.get("success")), str(phase.active_moves.get("U_FB", {}).get("fall_back_mode", "")),
			str(_hazard_rolls(phase, "U_FB")), str(rolls_after_set), alive_before_rebegin, alive_after_rebegin])
	# Refusals.
	phase = _phase_with(gs, pm, base_state, two_model.call())
	_begin_fb(phase, "U_FB")
	_stage(phase, "U_FB", "m1", Vector2(460, 1100), true)
	r = phase.validate_action({"type": "SET_FALL_BACK_MODE", "actor_unit_id": "U_FB", "player": 1, "payload": {"fall_back_mode": "desperate_escape"}})
	_check("refused once a model has moved as an Ordered Retreat (Reset Unit first)", not r.get("valid", true) and _errors_have(r, ["Reset Unit first"]), str(r))
	phase = _phase_with(gs, pm, base_state, two_model.call())
	r = phase.validate_action({"type": "SET_FALL_BACK_MODE", "actor_unit_id": "U_FB", "player": 1, "payload": {"fall_back_mode": "desperate_escape"}})
	_check("refused when the unit is not making a fall-back move", not r.get("valid", true), str(r))
	GameConstants.edition = 10
	phase = _phase_with(gs, pm, base_state, two_model.call())
	_begin_fb(phase, "U_FB")
	r = phase.validate_action({"type": "SET_FALL_BACK_MODE", "actor_unit_id": "U_FB", "player": 1, "payload": {"fall_back_mode": "desperate_escape"}})
	_check("10e: no fall-back modes to select", not r.get("valid", true), str(r))
	GameConstants.edition = 11
	# A battle-shocked unit's Desperate Escape: Reset + Fall Back does not re-roll.
	var shocked_units := {"U_FB": _unit("U_FB", 1, ["INFANTRY"], [from, Vector2(460, 1000), Vector2(520, 1000)], 32, 1, "Shaken", true),
		"U_EN": _unit("U_EN", 2, ["INFANTRY"], north, 32, 1, "Blockers")}
	phase = _phase_with(gs, pm, base_state, shocked_units)
	rules.set_test_seed(3)
	_begin_fb(phase, "U_FB")
	var first_rolls: Array = _hazard_rolls(phase, "U_FB").duplicate()
	phase.execute_action({"type": "RESET_UNIT_MOVE", "actor_unit_id": "U_FB", "player": 1, "payload": {}})
	rules.set_test_seed(77)
	_begin_fb(phase, "U_FB")
	_check("battle-shocked: re-beginning the fall-back after Reset Unit keeps its first hazard rolls (no second set)",
		first_rolls.size() == 3 and _hazard_rolls(phase, "U_FB") == first_rolls,
		"first=%s again=%s" % [str(first_rolls), str(_hazard_rolls(phase, "U_FB"))])

	print("\n-- End This Unit's Move: the models it carries are path-checked too --")
	# Attached unit: one bodyguard model (engaged with a Boy to its south) and an
	# attached CHARACTER 80 px east of it. Another Boy stands in the character's
	# northward lane. The bodyguard is staged 240 px north (its own lane is
	# clear); confirming would carry the character by the same delta straight
	# through that Boy.
	var carry_units := func(shocked: bool) -> Dictionary:
		var u := {"U_BG": _unit("U_BG", 1, ["INFANTRY"], [from], 32, 1, "Bodyguard", shocked),
			"U_CHAR": _unit("U_CHAR", 1, ["INFANTRY", "CHARACTER"], [Vector2(480, 1000)], 32, 4, "Captain", shocked),
			"U_EN": _unit("U_EN", 2, ["INFANTRY"], [Vector2(400, 1060), Vector2(480, 900)], 32, 1, "Boyz")}
		_attach(u, "U_CHAR", "U_BG")
		return u
	phase = _phase_with(gs, pm, base_state, carry_units.call(false))
	_begin_fb(phase, "U_BG")
	var c_stage: Dictionary = _stage(phase, "U_BG", "m0", Vector2(400, 760), true)
	r = phase.validate_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	_check("Ordered Retreat: End This Unit's Move is refused - the unstaged CHARACTER would be carried through an enemy model",
		c_stage.get("success", false) and not r.get("valid", true) and _errors_have(r, ["Captain cannot follow Bodyguard through enemy models"]),
		"stage=%s confirm=%s" % [str(c_stage.get("success")), str(r)])
	var c_exec: Dictionary = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	_check("... executed, nothing moves: the CHARACTER stays put",
		not c_exec.get("success", true) and _pos(gs, "U_CHAR").distance_to(Vector2(480, 1000)) < 0.5,
		"confirm=%s char=%s" % [str(c_exec.get("success", c_exec.get("errors"))), str(_pos(gs, "U_CHAR"))])
	phase = _phase_with(gs, pm, base_state, carry_units.call(false))
	rules.set_test_seed(1)
	_begin_fb(phase, "U_BG", "desperate_escape")
	var de_alive := 0
	for uid in ["U_BG", "U_CHAR"]:
		for m in gs.state.units[uid].models:
			if m.get("alive", true):
				de_alive += 1
	if gs.state.units.U_BG.models[0].get("alive", true) and gs.state.units.U_CHAR.models[0].get("alive", true):
		_stage(phase, "U_BG", "m0", Vector2(400, 760), true)
		r = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
		_check("Desperate Escape: the same move confirms and carries the CHARACTER through the enemy model",
			r.get("success", false) and _pos(gs, "U_CHAR").distance_to(Vector2(480, 760)) < 0.5,
			"confirm=%s char=%s" % [str(r.get("success", r.get("errors"))), str(_pos(gs, "U_CHAR"))])
	else:
		_check("Desperate Escape carry case: seed 1 left both models alive (fixture)", false, "alive=%d" % de_alive)

	print("\n-- the AI never confirms a partial fall-back that leaves a model engaged --")
	# AIPlayer._try_stage_and_confirm stages each planned destination and used
	# to confirm whatever staged. m0's way out (north) crosses the Boy that
	# engages it, so as an Ordered Retreat it cannot stage — confirming m1 alone
	# would leave m0 engaged (09.07 AFTER MOVING: "Your unit must be unengaged").
	var ai = root.get_node_or_null("AIPlayer")
	if ai != null and ai.has_method("_try_stage_and_confirm"):
		phase = _phase_with(gs, pm, base_state, two_model.call())
		_begin_fb(phase, "U_FB")
		var ai_r: String = str(ai._try_stage_and_confirm(1, "U_FB", {"m0": [400.0, 800.0], "m1": [460.0, 1100.0]}, "EA-08 test", {}, "Retreaters"))
		_check("Ordered Retreat with a model whose way out crosses an enemy: the AI resets instead of confirming (staging_failed)",
			ai_r == "staging_failed" and not bool(gs.state.units.U_FB.get("flags", {}).get("moved", false))
			and _pos(gs, "U_FB", 0).distance_to(from) < 0.5 and _pos(gs, "U_FB", 1).distance_to(Vector2(460, 1000)) < 0.5,
			"result=%s moved=%s m0=%s m1=%s" % [ai_r, str(gs.state.units.U_FB.get("flags", {}).get("moved", false)), str(_pos(gs, "U_FB", 0)), str(_pos(gs, "U_FB", 1))])
		# Control: the model that fails to stage (past the 8" cap) is not engaged —
		# the partial fall-back is legal and still confirmed.
		phase = _phase_with(gs, pm, base_state, {
			"U_FB": _unit("U_FB", 1, ["INFANTRY"], [from, Vector2(460, 1000), Vector2(520, 1000)], 32, 1, "Retreaters"),
			"U_EN": _unit("U_EN", 2, ["INFANTRY"], north, 32, 1, "Blockers")})
		_begin_fb(phase, "U_FB")
		ai_r = str(ai._try_stage_and_confirm(1, "U_FB", {"m0": [400.0, 1100.0], "m1": [460.0, 1100.0], "m2": [520.0, 1400.0]}, "EA-08 control", {}, "Retreaters"))
		_check("control: a partial fall-back whose unstaged model is not engaged is still confirmed",
			ai_r == "success" and bool(gs.state.units.U_FB.get("flags", {}).get("moved", false)) and not rules.is_unit_engaged("U_FB", gs.state),
			"result=%s engaged=%s" % [ai_r, str(rules.is_unit_engaged("U_FB", gs.state))])
	else:
		_check("AIPlayer._try_stage_and_confirm reachable", false)

	print("\n-- the shared helpers (out-of-phase fall-backs use them too) --")
	# (guarded: calling a missing static would abort the whole test run)
	var has_mt: bool = "static func path_crosses_enemy_models" in str(load("res://scripts/rules/movetypes/MoveType.gd").source_code)
	_check("MoveType.path_crosses_enemy_models exists", has_mt)
	if has_mt:
		var board := {"units": {
			"U_A": _unit("U_A", 1, ["INFANTRY"], [from], 32),
			"U_E": _unit("U_E", 2, ["INFANTRY"], [Vector2(400, 1000 + CONTACT_32)], 32)}}
		var mover: Dictionary = board.units.U_A.models[0]
		var MT = load("res://scripts/rules/movetypes/MoveType.gd")
		_check("helper: exact base contact, moving away: not through", not MT.path_crosses_enemy_models(board, 1, mover, from, Vector2(400, 900)))
		_check("helper: moving through the enemy model: through", MT.path_crosses_enemy_models(board, 1, mover, from, Vector2(400, 1200)))
		_check("helper: friendly models never block", not MT.path_crosses_enemy_models(board, 2, mover, from, Vector2(400, 1200)))
		board.units.U_E.meta.keywords = ["AIRCRAFT", "VEHICLE", "FLY"]
		_check("helper: an enemy AIRCRAFT model never blocks (23.02)", not MT.path_crosses_enemy_models(board, 1, mover, from, Vector2(400, 1200)))

	tm.terrain_features = prev_terrain
	gs.state = prev_state
	GameConstants.edition = prev_edition
	rules.set_test_seed(-1)
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

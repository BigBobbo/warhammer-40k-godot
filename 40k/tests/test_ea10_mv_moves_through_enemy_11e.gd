extends SceneTree

# EA-10 (11e 17.01 MOVING MONSTERS AND VEHICLES): "Each time you make a normal
# or advance move with a unit, MONSTER/VEHICLE models in that unit can be moved
# through friendly and enemy models (excluding other MONSTER/VEHICLE models)."
#
# Before the fix MovementPhase._path_crosses_enemy_bases had no 17.01
# exemption, so every normal / advance path of a non-FLY MONSTER/VEHICLE
# through enemy infantry was refused ("Cannot move through enemy models during
# Normal Move or Advance").
#
# Drives the REAL MovementPhase validators (STAGE_MODEL_MOVE — the action the
# drag UI and the AI send — and SET_MODEL_DEST) plus the reactive-move
# translation check, on an open board (TerrainManager's default 44-feature
# layout is cleared: it would charge a non-INFANTRY mover a +6" climb).
#
# Board: mover at (400,1000); a 5-model enemy screen at y=780 (52 px apart, no
# base fits through); drop point (400,560) = 11" north, 2.9" clear of the
# screen at both ends (11e engagement range is 2").
#
# Usage: godot --headless --path . -s tests/test_ea10_mv_moves_through_enemy_11e.gd

var passed := 0
var failed := 0
var _ran := false

const ERR_ENEMY := "Cannot move through enemy models during Normal Move or Advance"

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

func _unit(id: String, owner: int, kws: Array, positions: Array, base_mm: int, move: float = 12.0) -> Dictionary:
	var models := []
	var i := 0
	for p in positions:
		models.append({"id": "m%d" % i, "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": base_mm, "base_type": "circular", "position": {"x": p.x, "y": p.y}})
		i += 1
	return {"id": id, "owner": owner, "status": 2, "flags": {},
		"meta": {"name": id, "keywords": kws, "abilities": [],
			"stats": {"move": move, "toughness": 9, "save": 3, "wounds": 10, "objective_control": 2}},
		"models": models, "weapons": [], "attachment_data": {}}

func _screen(y: float) -> Array:
	return [Vector2(296, y), Vector2(348, y), Vector2(400, y), Vector2(452, y), Vector2(504, y)]

## Seed a fresh Movement phase with `units`, P1 active. Returns the phase.
func _phase_with(gs, pm, base_state: Dictionary, units: Dictionary):
	gs.state = base_state.duplicate(true)
	gs.state["units"] = units
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 7
	pm.transition_to_phase(7)
	return pm.get_current_phase_instance()

## Begin the mover's move (`begin` action), then validate a drop at `dest`
## through both live validators. Returns {stage, smd, mode}.
func _drop(phase, dest: Vector2, begin: String = "BEGIN_NORMAL_MOVE") -> Dictionary:
	phase.execute_action({"type": begin, "actor_unit_id": "U_MOVER", "player": 1, "payload": {}})
	if not phase.active_moves.has("U_MOVER"):
		# an advance can pause on the Command Re-roll offer
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": "U_MOVER", "player": 1, "payload": {}})
	var stage: Dictionary = phase.validate_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_MOVER", "player": 1,
		"payload": {"model_id": "m0", "dest": [dest.x, dest.y], "rotation": 0.0}})
	var smd: Dictionary = phase._validate_set_model_dest({"actor_unit_id": "U_MOVER",
		"payload": {"model_id": "m0", "dest": [dest.x, dest.y]}})
	return {"stage": stage, "smd": smd, "mode": str(phase.active_moves.get("U_MOVER", {}).get("mode", ""))}

func _case(gs, pm, base_state, mover_kws: Array, mover_base: int, blocker_kws: Array, blocker_pos: Array, blocker_base: int, dest: Vector2, begin: String = "BEGIN_NORMAL_MOVE") -> Dictionary:
	var phase = _phase_with(gs, pm, base_state, {
		"U_MOVER": _unit("U_MOVER", 1, mover_kws, [Vector2(400, 1000)], mover_base),
		"U_SCREEN": _unit("U_SCREEN", 2, blocker_kws, blocker_pos, blocker_base, 6.0)})
	return _drop(phase, dest, begin)

func _both_valid(r: Dictionary) -> bool:
	return r.stage.get("valid", false) and r.smd.get("valid", false)

func _both_refused_with(r: Dictionary, msg: String) -> bool:
	return (not r.stage.get("valid", true)) and (not r.smd.get("valid", true)) \
		and msg in r.stage.get("errors", []) and msg in r.smd.get("errors", [])

## A synthetic Attached unit (no shipped datasheet pairs a MONSTER/VEHICLE with
## a non-M/V unit today; 17.01 is worded per model): bodyguard `bg_kws` with two
## models either side of the attached CHARACTER `char_kws`, all behind the enemy
## screen. Returns the phase with the bodyguard's normal move begun.
func _attached_phase(gs, pm, base_state, bg_kws: Array, bg_base: int, char_kws: Array, char_base: int):
	var bg := _unit("U_BG", 1, bg_kws, [Vector2(270, 1000), Vector2(530, 1000)], bg_base)
	bg["attachment_data"] = {"attached_characters": ["U_CHAR"]}
	var chu := _unit("U_CHAR", 1, char_kws + ["CHARACTER"], [Vector2(400, 1000)], char_base)
	chu["attached_to"] = "U_BG"
	var phase = _phase_with(gs, pm, base_state, {"U_BG": bg, "U_CHAR": chu,
		"U_SCREEN": _unit("U_SCREEN", 2, ["INFANTRY"], _screen(780), 32, 6.0)})
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	return phase

func _stage_attached(phase, model_id: String, source_unit: String, dest: Vector2) -> Dictionary:
	var payload := {"model_id": model_id, "dest": [dest.x, dest.y], "rotation": 0.0}
	if source_unit != "U_BG":
		payload["model_source_unit_id"] = source_unit
	return phase.validate_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": payload})

func _run_tests():
	if _ran:
		return
	_ran = true
	print("\n=== test_ea10_mv_moves_through_enemy_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var tm = root.get_node_or_null("TerrainManager")
	if gs == null or pm == null or tm == null:
		_check("autoloads reachable", false)
		_finish()
		return
	var prev_edition: int = GameConstants.edition
	var prev_terrain: Array = tm.terrain_features.duplicate(true)
	var base_state: Dictionary = gs.state.duplicate(true)
	var prev_state: Dictionary = gs.state.duplicate(true)
	tm.terrain_features = []
	base_state["board"]["terrain"] = []
	GameConstants.edition = 11
	var far := Vector2(400, 560)
	var r: Dictionary

	print("-- 17.01: MONSTER/VEHICLE normal / advance moves pass enemy non-MONSTER/VEHICLE models --")
	r = _case(gs, pm, base_state, ["VEHICLE"], 100, ["INFANTRY"], _screen(780), 32, far)
	_check("VEHICLE normal move through an enemy INFANTRY screen is legal (STAGE + SET_MODEL_DEST)", _both_valid(r), str(r))
	r = _case(gs, pm, base_state, ["MONSTER"], 100, ["INFANTRY"], _screen(780), 32, far)
	_check("MONSTER normal move through an enemy INFANTRY screen is legal", _both_valid(r), str(r))
	r = _case(gs, pm, base_state, ["VEHICLE"], 100, ["INFANTRY"], _screen(780), 32, far, "BEGIN_ADVANCE")
	_check("VEHICLE advance through an enemy INFANTRY screen is legal (mode %s)" % r.mode, r.mode == "ADVANCE" and _both_valid(r), str(r))
	r = _case(gs, pm, base_state, ["VEHICLE", "TITANIC"], 100, ["INFANTRY"], _screen(780), 32, far)
	_check("TITANIC VEHICLE normal move through enemy INFANTRY is legal (17.01 covers every M/V model)", _both_valid(r), str(r))
	r = _case(gs, pm, base_state, ["Vehicle"], 100, ["INFANTRY"], _screen(780), 32, far)
	_check("the MONSTER/VEHICLE keyword test is case-insensitive ('Vehicle')", _both_valid(r), str(r))
	# Executed end to end: stage the drop, then CONFIRM_UNIT_MOVE (End This
	# Unit's Move) — the VEHICLE ends on the far side of the screen.
	var ex_phase = _phase_with(gs, pm, base_state, {
		"U_MOVER": _unit("U_MOVER", 1, ["VEHICLE"], [Vector2(400, 1000)], 100),
		"U_SCREEN": _unit("U_SCREEN", 2, ["INFANTRY"], _screen(780), 32, 6.0)})
	ex_phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_MOVER", "player": 1, "payload": {}})
	var ex_stage: Dictionary = ex_phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_MOVER", "player": 1,
		"payload": {"model_id": "m0", "dest": [far.x, far.y], "rotation": 0.0}})
	var ex_confirm: Dictionary = ex_phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_MOVER", "player": 1, "payload": {}})
	var ex_pos = gs.state.get("units", {}).get("U_MOVER", {}).get("models", [{}])[0].get("position", {})
	var ex_at: Vector2 = ex_pos if ex_pos is Vector2 else (Vector2(float(ex_pos.get("x", 0.0)), float(ex_pos.get("y", 0.0))) if ex_pos is Dictionary else Vector2.ZERO)
	_check("a staged VEHICLE move through the screen confirms and ends past it (STAGE_MODEL_MOVE + CONFIRM_UNIT_MOVE executed)",
		ex_stage.get("success", false) and ex_confirm.get("success", false) and ex_at.distance_to(far) < 0.5,
		"stage=%s confirm=%s at=%s" % [str(ex_stage.get("success")), str(ex_confirm.get("success", ex_confirm.get("errors"))), str(ex_at)])

	print("\n-- controls: what 17.01 does NOT allow --")
	r = _case(gs, pm, base_state, ["INFANTRY"], 32, ["INFANTRY"], _screen(780), 32, far)
	_check("INFANTRY still cannot move through enemy models (03.01)", _both_refused_with(r, ERR_ENEMY), str(r))
	r = _case(gs, pm, base_state, ["VEHICLE"], 100, ["VEHICLE"], [Vector2(400, 780)], 60, far)
	_check("VEHICLE cannot move through an enemy VEHICLE ('excluding other MONSTER/VEHICLE models')", not r.stage.get("valid", true) and not r.smd.get("valid", true), str(r))
	r = _case(gs, pm, base_state, ["VEHICLE"], 100, ["MONSTER"], [Vector2(400, 780)], 60, far)
	_check("VEHICLE cannot move through an enemy MONSTER", not r.stage.get("valid", true) and not r.smd.get("valid", true), str(r))
	r = _case(gs, pm, base_state, ["VEHICLE"], 100, ["INFANTRY"], _screen(780), 32, Vector2(400, 780 - 25.2 - 40 - 78.74))
	_check("VEHICLE through the screen must still end unengaged (09.05 AFTER MOVING)", _both_refused_with(r, "Cannot end within engagement range"), str(r))
	r = _case(gs, pm, base_state, ["VEHICLE"], 100, ["INFANTRY"], [Vector2(400, 700)], 32, Vector2(400, 720))
	_check("VEHICLE cannot end on an enemy model", not r.stage.get("valid", true) and not r.smd.get("valid", true), str(r))
	r = _case(gs, pm, base_state, ["VEHICLE", "SUPER-HEAVY WALKER"], 100, ["VEHICLE"], [Vector2(400, 780)], 60, far)
	_check("24.35 unchanged: SUPER-HEAVY WALKER passes an enemy non-TITANIC VEHICLE", _both_valid(r), str(r))
	r = _case(gs, pm, base_state, ["VEHICLE", "SUPER-HEAVY WALKER"], 100, ["VEHICLE", "TITANIC"], [Vector2(400, 780)], 60, far)
	_check("24.35 unchanged: SUPER-HEAVY WALKER is still blocked by an enemy TITANIC model", not r.stage.get("valid", true), str(r))

	print("\n-- per model (Attached units), through the real STAGE_MODEL_MOVE --")
	# VEHICLE bodyguard + an attached INFANTRY CHARACTER — the shipped shape is
	# a Mek / Big Mek (INFANTRY) leading Mek Gunz (VEHICLE): only the VEHICLE
	# models may drive through the screen.
	var phase = _attached_phase(gs, pm, base_state, ["VEHICLE"], 100, ["INFANTRY"], 32)
	r = {"stage": _stage_attached(phase, "m1", "U_BG", Vector2(530, 560))}
	_check("a VEHICLE bodyguard's model may move through the enemy screen", r.stage.get("valid", false), str(r))
	r = {"stage": _stage_attached(phase, "m0", "U_CHAR", far)}
	_check("its attached INFANTRY CHARACTER's model may not (judged on its own unit, not the bodyguard's)",
		not r.stage.get("valid", true) and ERR_ENEMY in r.stage.get("errors", []), str(r))
	# INFANTRY bodyguard + an attached MONSTER CHARACTER (synthetic: no shipped
	# M/V CHARACTER can lead): the reverse. Only the enemy-crossing verdict is
	# asserted for the MONSTER: its STAGE_MODEL_MOVE is still refused by the
	# separate MONSTER/VEHICLE crossing check, which skips only the bodyguard's
	# own models, so an attached M/V character blocks its own path (not EA-10).
	phase = _attached_phase(gs, pm, base_state, ["INFANTRY"], 32, ["MONSTER"], 100)
	r = {"stage": _stage_attached(phase, "m1", "U_BG", Vector2(530, 560))}
	_check("an INFANTRY bodyguard's model may not move through the enemy screen", not r.stage.get("valid", true) and ERR_ENEMY in r.stage.get("errors", []), str(r))
	r = {"stage": _stage_attached(phase, "m0", "U_CHAR", far)}
	_check("its attached MONSTER CHARACTER's path is not refused for crossing enemy models (STAGE_MODEL_MOVE passes the model's own unit)",
		not ERR_ENEMY in r.stage.get("errors", []), str(r))

	print("\n-- the helper: per model, per mode --")
	phase = _attached_phase(gs, pm, base_state, ["INFANTRY"], 32, ["MONSTER"], 100)
	var has_helper: bool = phase.has_method("_mv1701_moves_through_models")
	_check("MovementPhase has _mv1701_moves_through_models", has_helper)
	if has_helper:
		var ch_model: Dictionary = phase._get_model_in_unit("U_CHAR", "m0")
		var bg_model: Dictionary = phase._get_model_in_unit("U_BG", "m1")
		_check("an attached MONSTER character's model gets 17.01 (judged on its own unit)",
			phase._mv1701_moves_through_models("U_BG", "U_CHAR"))
		_check("its INFANTRY bodyguard's models do not", not phase._mv1701_moves_through_models("U_BG"))
		_check("helper: the MONSTER character's path through the enemy screen is clear",
			not phase._path_crosses_enemy_bases(Vector2(400, 1000), far, "U_BG", ch_model, "U_CHAR"))
		_check("helper: a bodyguard model's path through the same screen is blocked",
			phase._path_crosses_enemy_bases(Vector2(530, 1000), Vector2(530, 560), "U_BG", bg_model))
		phase.active_moves["U_BG"]["mode"] = "FALL_BACK"
		_check("17.01 is normal/advance only: no exemption on a fall-back", not phase._mv1701_moves_through_models("U_BG", "U_CHAR"))
		phase.active_moves["U_BG"]["mode"] = "NORMAL"
		var fly_phase = _phase_with(gs, pm, base_state, {
			"U_MOVER": _unit("U_MOVER", 1, ["VEHICLE", "FLY"], [Vector2(400, 1000)], 100),
			"U_SCREEN": _unit("U_SCREEN", 2, ["INFANTRY"], _screen(780), 32, 6.0)})
		fly_phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_MOVER", "player": 1, "payload": {}})
		_check("a FLY VEHICLE that has not taken to the skies still gets 17.01 (no FLY gate in the predicate)",
			fly_phase._mv1701_moves_through_models("U_MOVER"))
		GameConstants.edition = 10
		_check("10e: no 17.01 exemption", not fly_phase._mv1701_moves_through_models("U_MOVER"))
		GameConstants.edition = 11

	print("\n-- reactive normal move (Codex: Orks 11e follow-up, AI translation) --")
	for kws in [["VEHICLE"], ["INFANTRY"]]:
		var rp = _phase_with(gs, pm, base_state, {
			"U_RV": _unit("U_RV", 2, kws, [Vector2(400, 1000)], 100 if "VEHICLE" in kws else 32),
			"U_P1SCREEN": _unit("U_P1SCREEN", 1, ["INFANTRY"], _screen(780), 32, 6.0)})
		rp._reactive_move_owner = 2
		rp._ork11e_setup_reactive_active_move("U_RV", 12.0, "test")
		var entries := [{"uid": "U_RV", "model": rp._get_model_in_unit("U_RV", "m0"), "pos": Vector2(400, 1000)}]
		var ok: bool = rp._ork11e_translation_legal("U_RV", rp.active_moves["U_RV"], entries, {"U_RV": true}, Vector2(0, -440), 12.0)
		if "VEHICLE" in kws:
			_check("a reactive VEHICLE normal move through the enemy screen is legal", ok)
		else:
			_check("a reactive INFANTRY normal move through the enemy screen is still refused", not ok)
		rp._reactive_move_owner = 0
		rp.active_moves.erase("U_RV")

	print("\n-- 10e sensitivity --")
	GameConstants.edition = 10
	r = _case(gs, pm, base_state, ["VEHICLE"], 100, ["INFANTRY"], _screen(780), 32, far)
	_check("10e: a VEHICLE still cannot move through enemy INFANTRY", _both_refused_with(r, ERR_ENEMY), str(r))

	GameConstants.edition = prev_edition
	tm.terrain_features = prev_terrain
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== test_ea10_mv_moves_through_enemy_11e: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

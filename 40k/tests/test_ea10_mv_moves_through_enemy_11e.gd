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
# Review fixes (EA-10 review, same file):
#  1. An attached MONSTER/VEHICLE CHARACTER no longer blocks its own path (or
#     its bodyguard's): _path_crosses_monster_vehicle_bases skipped only the
#     bodyguard unit, so the character's own base overlapped the first path
#     sample and every STAGE_MODEL_MOVE of that model was refused with "Cannot
#     move through Monster or Vehicle models". The engine's shipped leader data
#     (40k/data/Datasheets_leader.csv + 40kdc/leaderAttachments.json) does let
#     M/V CHARACTERs lead — Beastboss on Squigosaur / Mozrog Skragbad ->
#     Squighog Boyz, Hive Tyrant -> Tyrant Guard, Old One Eye -> Carnifexes,
#     Morvenn Vahl -> Paragon Warsuits — so the shapes below are the shipped
#     keyword sets and bases. (The 11e Orks faction pack v1.2 export in
#     .llm/codex_11e_wahapedia/orks gives the Squigosaur and Mozrog no Leader
#     ability, so that Ork row may be stale data; the engine still accepts the
#     attachment, so its move has to work.)
#  2. 17.01 FAQ: "While making a move type other than a normal / advance move,
#     can my MONSTER/VEHICLE unit move through friendly units? A: Yes." — a
#     VEHICLE falling back through a friendly VEHICLE was refused.
#  3. End This Unit's Move carried an attached INFANTRY CHARACTER through the
#     enemy models 17.01 let its VEHICLE bodyguard pass (and left it engaged):
#     CONFIRM_UNIT_MOVE now gives every model it moves without a stage of its
#     own the per-model path and engagement checks STAGE_MODEL_MOVE gives.
#
# Drives the REAL MovementPhase validators (STAGE_MODEL_MOVE — the action the
# drag UI and the AI send — SET_MODEL_DEST and CONFIRM_UNIT_MOVE) plus the
# reactive-move translation check, on an open board (TerrainManager's default
# 44-feature layout is cleared: it would charge a non-INFANTRY mover a +6"
# climb).
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
const ERR_MV := "Cannot move through Monster or Vehicle models"

# Shipped keyword sets / bases (40k/data/40kdc/units.json, 11th edition launch).
const SQUIGHOG_KWS := ["MOUNTED", "BEAST SNAGGA", "EXPLOSIVES", "MOBILE", "SQUIGHOG BOYZ", "ORKS"]
const SQUIGOSAUR_KWS := ["MONSTER", "CHARACTER", "BEAST SNAGGA", "WARBOSS", "BEASTBOSS ON SQUIGOSAUR", "ORKS"]
const SQUIGHOG_BASE := {"base_type": "oval", "base_dimensions": {"length": 42, "width": 75}}  # oval 75 x 42 mm
const CARNIFEX_KWS := ["MONSTER", "GREAT DEVOURER", "CARNIFEXES", "TYRANIDS"]
const OLD_ONE_EYE_KWS := ["MONSTER", "CHARACTER", "EPIC HERO", "GREAT DEVOURER", "OLD ONE EYE", "TYRANIDS"]
const CARNIFEX_BASE := {"base_type": "oval", "base_dimensions": {"length": 70, "width": 105}}  # oval 105 x 70 mm

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

func _unit(id: String, owner: int, kws: Array, positions: Array, base_mm: int, move: float = 12.0, name: String = "", base_extra: Dictionary = {}) -> Dictionary:
	var models := []
	var i := 0
	for p in positions:
		var m := {"id": "m%d" % i, "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": base_mm, "base_type": "circular", "position": {"x": p.x, "y": p.y}}
		m.merge(base_extra, true)
		models.append(m)
		i += 1
	return {"id": id, "owner": owner, "status": 2, "flags": {},
		"meta": {"name": name if name != "" else id, "keywords": kws, "abilities": [],
			"stats": {"move": move, "toughness": 9, "save": 3, "wounds": 10, "objective_control": 2}},
		"models": models, "weapons": [], "attachment_data": {}}

func _screen(y: float) -> Array:
	return [Vector2(296, y), Vector2(348, y), Vector2(400, y), Vector2(452, y), Vector2(504, y)]

## Write the attachment both ways (bodyguard's forward list + the character's
## back-pointer), as CharacterAttachmentManager.attach_character does.
func _attach(units: Dictionary, char_id: String, bg_id: String) -> void:
	units[bg_id]["attachment_data"] = {"attached_characters": [char_id]}
	units[char_id]["attached_to"] = bg_id

## The shipped Beastboss on Squigosaur (MONSTER CHARACTER, 80 mm) leading
## Squighog Boyz (MOUNTED, oval 75 x 42 mm): two Squighogs either side of the
## Squigosaur, behind the screen.
func _squigosaur_units(owner: int) -> Dictionary:
	var units := {
		"U_SQB": _unit("U_SQB", owner, SQUIGHOG_KWS, [Vector2(250, 1000), Vector2(560, 1000)], 75, 12.0, "Squighog Boyz", SQUIGHOG_BASE),
		"U_BB": _unit("U_BB", owner, SQUIGOSAUR_KWS, [Vector2(400, 1000)], 80, 12.0, "Beastboss on Squigosaur")}
	_attach(units, "U_BB", "U_SQB")
	return units

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

## An Attached unit behind the enemy screen: bodyguard `bg_kws` with two models
## either side of the attached CHARACTER `char_kws`. The shipped VEHICLE +
## INFANTRY CHARACTER shape is a Mek / Big Mek (INFANTRY) leading Mek Gunz
## (VEHICLE). Returns the phase with the bodyguard's normal move begun.
func _attached_phase(gs, pm, base_state, bg_kws: Array, bg_base: int, char_kws: Array, char_base: int):
	var units := {"U_BG": _unit("U_BG", 1, bg_kws, [Vector2(270, 1000), Vector2(530, 1000)], bg_base),
		"U_CHAR": _unit("U_CHAR", 1, char_kws + ["CHARACTER"], [Vector2(400, 1000)], char_base),
		"U_SCREEN": _unit("U_SCREEN", 2, ["INFANTRY"], _screen(780), 32, 6.0)}
	_attach(units, "U_CHAR", "U_BG")
	var phase = _phase_with(gs, pm, base_state, units)
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	return phase

func _stage(phase, actor: String, model_id: String, source_unit: String, dest: Vector2, execute: bool = false) -> Dictionary:
	var payload := {"model_id": model_id, "dest": [dest.x, dest.y], "rotation": 0.0}
	if source_unit != actor:
		payload["model_source_unit_id"] = source_unit
	var action := {"type": "STAGE_MODEL_MOVE", "actor_unit_id": actor, "player": 1, "payload": payload}
	return phase.execute_action(action) if execute else phase.validate_action(action)

func _stage_attached(phase, model_id: String, source_unit: String, dest: Vector2) -> Dictionary:
	return _stage(phase, "U_BG", model_id, source_unit, dest)

func _pos(gs, unit_id: String, idx: int = 0) -> Vector2:
	var p = gs.state.get("units", {}).get(unit_id, {}).get("models", [{}])[idx].get("position", {})
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	return Vector2.INF

func _errors_have(r: Dictionary, parts: Array) -> bool:
	for e in r.get("errors", []):
		var all_in := true
		for part in parts:
			if not str(part) in str(e):
				all_in = false
				break
		if all_in:
			return true
	return false

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
	var phase

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
	var ex_at: Vector2 = _pos(gs, "U_MOVER")
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
	# VEHICLE bodyguard + an attached INFANTRY CHARACTER (the shipped Mek Gunz +
	# Mek shape): only the VEHICLE models may drive through the screen.
	phase = _attached_phase(gs, pm, base_state, ["VEHICLE"], 100, ["INFANTRY"], 32)
	r = _stage_attached(phase, "m1", "U_BG", Vector2(530, 560))
	_check("a VEHICLE bodyguard's model may move through the enemy screen", r.get("valid", false), str(r))
	r = _stage_attached(phase, "m0", "U_CHAR", far)
	_check("its attached INFANTRY CHARACTER's model may not (judged on its own unit, not the bodyguard's)",
		not r.get("valid", true) and ERR_ENEMY in r.get("errors", []), str(r))
	# The shipped MONSTER CHARACTER shape: Beastboss on Squigosaur leading
	# Squighog Boyz (MOUNTED). Before the review fix every STAGE_MODEL_MOVE of
	# the Squigosaur was refused — its own base blocked it.
	var sq_units := _squigosaur_units(1)
	sq_units["U_SCREEN"] = _unit("U_SCREEN", 2, ["INFANTRY"], _screen(780), 32, 6.0)
	var sq_free: Dictionary = sq_units.duplicate(true)
	sq_free["U_SQB"]["attachment_data"] = {"attached_characters": []}
	sq_free["U_BB"].erase("attached_to")
	_phase_with(gs, pm, base_state, sq_free)
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	if cam != null:
		print("  INFO: CharacterAttachmentManager.can_attach(Beastboss on Squigosaur -> Squighog Boyz) = %s (the shipped leader data accepts the pairing)" % str(cam.can_attach("U_BB", "U_SQB")))
	phase = _phase_with(gs, pm, base_state, sq_units.duplicate(true))
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SQB", "player": 1, "payload": {}})
	r = _stage(phase, "U_SQB", "m0", "U_SQB", Vector2(250, 560))
	_check("a Squighog Boy (MOUNTED) may not move through the enemy screen", not r.get("valid", true) and ERR_ENEMY in r.get("errors", []), str(r))
	r = _stage(phase, "U_SQB", "m0", "U_BB", far)
	_check("the attached Beastboss on Squigosaur (MONSTER CHARACTER) moves through the enemy INFANTRY screen (17.01; its own base no longer blocks it)",
		r.get("valid", false), str(r))
	r = _stage(phase, "U_SQB", "m0", "U_BB", Vector2(400, 1080))
	_check("the attached Squigosaur moves 2\" in open ground (was refused: '%s')" % ERR_MV, r.get("valid", false), str(r))
	# MONSTER CHARACTER + MONSTER bodyguard (the shipped Old One Eye ->
	# Carnifexes pairing): the two components never block each other's paths
	# (19.01: one unit), but another friendly MONSTER still blocks a normal move.
	var oe_units := {
		"U_CARNI": _unit("U_CARNI", 1, CARNIFEX_KWS, [Vector2(400, 1220), Vector2(650, 1000)], 105, 12.0, "Carnifexes", CARNIFEX_BASE),
		"U_OOE": _unit("U_OOE", 1, OLD_ONE_EYE_KWS, [Vector2(400, 1000)], 105, 12.0, "Old One Eye", CARNIFEX_BASE),
		"U_OTHER": _unit("U_OTHER", 1, ["MONSTER"], [Vector2(650, 700)], 60, 12.0, "Other Monster")}
	_attach(oe_units, "U_OOE", "U_CARNI")
	phase = _phase_with(gs, pm, base_state, oe_units)
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CARNI", "player": 1, "payload": {}})
	r = _stage(phase, "U_CARNI", "m0", "U_CARNI", Vector2(400, 780))
	_check("a Carnifex's path across its own attached Old One Eye is not blocked (same Attached unit)", r.get("valid", false), str(r))
	r = _stage(phase, "U_CARNI", "m0", "U_OOE", Vector2(400, 1440))
	_check("Old One Eye's path across its own Carnifex is not blocked (nor by its own base)", r.get("valid", false), str(r))
	r = _stage(phase, "U_CARNI", "m1", "U_CARNI", Vector2(650, 560))
	_check("a friendly MONSTER of another unit still blocks a normal move (17.01 'excluding other MONSTER/VEHICLE models')",
		not r.get("valid", true) and ERR_MV in r.get("errors", []), str(r))

	print("\n-- the helper: per model, per mode --")
	phase = _phase_with(gs, pm, base_state, sq_units.duplicate(true))
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SQB", "player": 1, "payload": {}})
	var has_helper: bool = phase.has_method("_mv1701_moves_through_models")
	_check("MovementPhase has _mv1701_moves_through_models", has_helper)
	if has_helper:
		var ch_model: Dictionary = phase._get_model_in_unit("U_BB", "m0")
		var bg_model: Dictionary = phase._get_model_in_unit("U_SQB", "m0")
		_check("an attached MONSTER character's model gets 17.01 (judged on its own unit)",
			phase._mv1701_moves_through_models("U_SQB", "U_BB"))
		_check("its MOUNTED bodyguard's models do not", not phase._mv1701_moves_through_models("U_SQB"))
		_check("helper: the MONSTER character's path through the enemy screen is clear",
			not phase._path_crosses_enemy_bases(Vector2(400, 1000), far, "U_SQB", ch_model, "U_BB"))
		# (the 5-argument form — the moved model's own unit — is the review fix)
		var mv_takes_model_unit: bool = phase.get_method_argument_count("_path_crosses_monster_vehicle_bases") >= 5
		_check("helper: the MONSTER character's path is not blocked by its own base (MONSTER/VEHICLE check)",
			mv_takes_model_unit and not phase.callv("_path_crosses_monster_vehicle_bases", [Vector2(400, 1000), Vector2(400, 1080), "U_SQB", ch_model, "U_BB"]))
		_check("helper: a bodyguard model's path through the same screen is blocked",
			phase._path_crosses_enemy_bases(Vector2(250, 1000), Vector2(250, 560), "U_SQB", bg_model))
		phase.active_moves["U_SQB"]["mode"] = "FALL_BACK"
		_check("17.01 is normal/advance only: no exemption on a fall-back", not phase._mv1701_moves_through_models("U_SQB", "U_BB"))
		phase.active_moves["U_SQB"]["mode"] = "NORMAL"
		var fly_phase = _phase_with(gs, pm, base_state, {
			"U_MOVER": _unit("U_MOVER", 1, ["VEHICLE", "FLY"], [Vector2(400, 1000)], 100),
			"U_SCREEN": _unit("U_SCREEN", 2, ["INFANTRY"], _screen(780), 32, 6.0)})
		fly_phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_MOVER", "player": 1, "payload": {}})
		_check("a FLY VEHICLE that has not taken to the skies still gets 17.01 (no FLY gate in the predicate)",
			fly_phase._mv1701_moves_through_models("U_MOVER"))
		GameConstants.edition = 10
		_check("10e: no 17.01 exemption", not fly_phase._mv1701_moves_through_models("U_MOVER"))
		GameConstants.edition = 11

	print("\n-- 17.01 FAQ: other move types pass friendly units --")
	# A VEHICLE engaged with an enemy model falls back (Ordered Retreat) through
	# a friendly VEHICLE. 03.01 lets a model be moved through friendly models;
	# the FAQ confirms it for a MONSTER/VEHICLE on any move but a normal /
	# advance one (17.01's "excluding other MONSTER/VEHICLE models").
	var fb_units := func(blocker_owner: int, foe: bool) -> Dictionary:
		var u := {"U_FB": _unit("U_FB", 1, ["VEHICLE"], [Vector2(400, 1000)], 60, 12.0, "Falling-back Vehicle"),
			"U_BLOCK": _unit("U_BLOCK", blocker_owner, ["VEHICLE"], [Vector2(400, 850)], 60, 12.0, "Blocking Vehicle")}
		if foe:
			u["U_FOE"] = _unit("U_FOE", 2, ["INFANTRY"], [Vector2(400, 1090)], 32, 6.0, "Engaging Infantry")
		return u
	phase = _phase_with(gs, pm, base_state, fb_units.call(1, true))
	var fb_begin: Dictionary = phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_FB", "player": 1,
		"payload": {"fall_back_mode": "ordered_retreat"}})
	var fb_md: Dictionary = phase.active_moves.get("U_FB", {})
	_check("the engaged VEHICLE begins an Ordered Retreat fall-back",
		fb_begin.get("success", false) and str(fb_md.get("mode", "")) == "FALL_BACK" and str(fb_md.get("fall_back_mode", "")) == "ordered_retreat",
		"begin=%s mode=%s fb_mode=%s" % [str(fb_begin.get("success", fb_begin.get("errors"))), str(fb_md.get("mode", "")), str(fb_md.get("fall_back_mode", ""))])
	r = _stage(phase, "U_FB", "m0", "U_FB", Vector2(400, 640))
	_check("its fall-back through a FRIENDLY VEHICLE is legal (17.01 FAQ)", r.get("valid", false), str(r))
	var fb_ex: Dictionary = _stage(phase, "U_FB", "m0", "U_FB", Vector2(400, 640), true)
	var fb_conf: Dictionary = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_FB", "player": 1, "payload": {}})
	_check("... and executes: staged and confirmed, the VEHICLE ends past the friendly VEHICLE, unengaged",
		fb_ex.get("success", false) and fb_conf.get("success", false) and _pos(gs, "U_FB").distance_to(Vector2(400, 640)) < 0.5
		and not root.get_node("RulesEngine").is_unit_engaged("U_FB", gs.state),
		"stage=%s confirm=%s at=%s" % [str(fb_ex.get("success")), str(fb_conf.get("success", fb_conf.get("errors"))), str(_pos(gs, "U_FB"))])
	phase = _phase_with(gs, pm, base_state, fb_units.call(2, true))
	phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_FB", "player": 1, "payload": {"fall_back_mode": "ordered_retreat"}})
	r = _stage(phase, "U_FB", "m0", "U_FB", Vector2(400, 640))
	_check("an ENEMY VEHICLE still blocks the same fall-back", not r.get("valid", true) and ERR_MV in r.get("errors", []), str(r))
	phase = _phase_with(gs, pm, base_state, fb_units.call(1, false))
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_FB", "player": 1, "payload": {}})
	r = _stage(phase, "U_FB", "m0", "U_FB", Vector2(400, 640))
	_check("a NORMAL move through the friendly VEHICLE is still refused (17.01: 'excluding other MONSTER/VEHICLE models')",
		not r.get("valid", true) and ERR_MV in r.get("errors", []), str(r))
	var has_faq: bool = phase.has_method("_mv1701_faq_moves_through_friendly")
	_check("MovementPhase has _mv1701_faq_moves_through_friendly", has_faq)
	if has_faq:
		_check("helper: no FAQ pass on a normal move", not phase._mv1701_faq_moves_through_friendly("U_FB"))
		phase.active_moves["U_FB"]["mode"] = "SURGE"  # helper-level: a surge move is another 'other move type'
		_check("helper: a VEHICLE's surge move passes friendly units", phase._mv1701_faq_moves_through_friendly("U_FB"))
		_check("helper: ... and the friendly VEHICLE no longer blocks its path",
			not phase._path_crosses_monster_vehicle_bases(Vector2(400, 1000), Vector2(400, 640), "U_FB", phase._get_model_in_unit("U_FB", "m0")))
		GameConstants.edition = 10
		_check("helper: 10e: no FAQ pass", not phase._mv1701_faq_moves_through_friendly("U_FB"))
		GameConstants.edition = 11
	phase = _phase_with(gs, pm, base_state, {"U_INF": _unit("U_INF", 1, ["INFANTRY"], [Vector2(400, 1000)], 32)})
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_INF", "player": 1, "payload": {}})
	if has_faq:
		phase.active_moves["U_INF"]["mode"] = "SURGE"
		_check("helper: the FAQ is for MONSTER/VEHICLE models only (INFANTRY: no pass)", not phase._mv1701_faq_moves_through_friendly("U_INF"))

	print("\n-- End This Unit's Move: models nobody staged get the per-model checks --")
	# VEHICLE bodyguard (one 60 mm model) staged through the screen; its attached
	# INFANTRY CHARACTER, left behind it, is NOT staged. The confirm used to
	# carry it by the bodyguard's delta straight through a screen Boy and leave
	# it engaged.
	var carry_units := func(char_pos: Vector2, screen: bool) -> Dictionary:
		var u := {"U_BG": _unit("U_BG", 1, ["VEHICLE"], [Vector2(400, 1000)], 60, 12.0, "Mek Gunz"),
			"U_CHAR": _unit("U_CHAR", 1, ["INFANTRY", "CHARACTER"], [char_pos], 32, 12.0, "Mek")}
		if screen:
			u["U_SCREEN"] = _unit("U_SCREEN", 2, ["INFANTRY"], _screen(780), 32, 6.0, "Boyz")
		_attach(u, "U_CHAR", "U_BG")
		return u
	phase = _phase_with(gs, pm, base_state, carry_units.call(Vector2(400, 1075), true))
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	var c_stage: Dictionary = _stage(phase, "U_BG", "m0", "U_BG", Vector2(400, 600), true)
	_check("the VEHICLE bodyguard stages through the screen (17.01)", c_stage.get("success", false), str(c_stage))
	r = phase.validate_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	_check("End This Unit's Move is refused: the unstaged INFANTRY CHARACTER cannot follow through the enemy models",
		not r.get("valid", true) and _errors_have(r, ["Mek cannot follow Mek Gunz through enemy models", "move Mek around them"]), str(r))
	var c_exec: Dictionary = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	_check("... executed, the confirm fails and nothing moves: the CHARACTER stays put, the bodyguard's move stays open and staged",
		not c_exec.get("success", true) and _pos(gs, "U_CHAR").distance_to(Vector2(400, 1075)) < 0.5
		and _pos(gs, "U_BG").distance_to(Vector2(400, 1000)) < 0.5
		and not bool(gs.state.units.U_BG.get("flags", {}).get("moved", false))
		and phase.active_moves.get("U_BG", {}).get("staged_moves", []).size() == 1,
		"confirm=%s char=%s bg=%s" % [str(c_exec.get("success", c_exec.get("errors"))), str(_pos(gs, "U_CHAR")), str(_pos(gs, "U_BG"))])
	# Not soft-locked: reset, move the bodyguard where the CHARACTER can follow.
	phase.execute_action({"type": "RESET_UNIT_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	_stage(phase, "U_BG", "m0", "U_BG", Vector2(480, 1000), true)
	var c_ok: Dictionary = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	_check("control: after a reset, a move the CHARACTER can follow confirms and carries it by the same delta",
		c_ok.get("success", false) and _pos(gs, "U_CHAR").distance_to(Vector2(480, 1075)) < 0.5,
		"confirm=%s char=%s" % [str(c_ok.get("success", c_ok.get("errors"))), str(_pos(gs, "U_CHAR"))])
	# No crossing, but the carry would leave the CHARACTER engaged (09.05).
	var eng_units: Dictionary = carry_units.call(Vector2(520, 950), false)
	eng_units["U_E"] = _unit("U_E", 2, ["INFANTRY"], [Vector2(520, 760)], 32, 6.0, "Lone Boy")
	phase = _phase_with(gs, pm, base_state, eng_units)
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	var e_stage: Dictionary = _stage(phase, "U_BG", "m0", "U_BG", Vector2(400, 900), true)
	r = phase.validate_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_BG", "player": 1, "payload": {}})
	_check("refused when the carried CHARACTER would end within engagement range (the bodyguard itself ends 2.8\" away)",
		e_stage.get("success", false) and not r.get("valid", true) and _errors_have(r, ["Mek would end within engagement range"]), "stage=%s confirm=%s" % [str(e_stage.get("success")), str(r)])
	# The mirror: only the MONSTER CHARACTER is staged, through the screen; the
	# MOUNTED bodyguard would follow its delta through the same Boyz.
	phase = _phase_with(gs, pm, base_state, sq_units.duplicate(true))
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SQB", "player": 1, "payload": {}})
	var m_stage: Dictionary = _stage(phase, "U_SQB", "m0", "U_BB", far, true)
	r = phase.validate_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_SQB", "player": 1, "payload": {}})
	_check("only the Squigosaur staged through the screen: its MOUNTED bodyguard cannot follow it through the enemy models",
		m_stage.get("success", false) and not r.get("valid", true) and _errors_have(r, ["Squighog Boyz cannot follow Beastboss on Squigosaur through enemy models"]),
		"stage=%s confirm=%s" % [str(m_stage.get("success", m_stage.get("errors"))), str(r)])

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
	# The Attached unit with the MONSTER CHARACTER, as the reactive unit (P2):
	# a 3" translation in open ground was refused (the Squigosaur's own base).
	var rp2_units := _squigosaur_units(2)
	rp2_units["U_P1FAR"] = _unit("U_P1FAR", 1, ["INFANTRY"], [Vector2(1500, 300)], 32, 6.0)  # P1 must have a unit, or the Movement phase is skipped
	var rp2 = _phase_with(gs, pm, base_state, rp2_units)
	rp2._reactive_move_owner = 2
	rp2._ork11e_setup_reactive_active_move("U_SQB", 12.0, "test")
	var r_entries := []
	for key in rp2.active_moves["U_SQB"]["original_positions"]:
		var parts: PackedStringArray = str(key).split(":")
		r_entries.append({"uid": parts[0], "model": rp2._get_model_in_unit(parts[0], parts[parts.size() - 1]), "pos": rp2.active_moves["U_SQB"]["original_positions"][key]})
	var r_ok: bool = rp2._ork11e_translation_legal("U_SQB", rp2.active_moves["U_SQB"], r_entries, {"U_SQB": true, "U_BB": true}, Vector2(0, -120), 12.0)
	_check("a reactive 3\" normal move of Squighog Boyz led by the Squigosaur, in open ground, is legal (%d models)" % r_entries.size(), r_ok and r_entries.size() == 3)
	rp2._reactive_move_owner = 0
	rp2.active_moves.erase("U_SQB")

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

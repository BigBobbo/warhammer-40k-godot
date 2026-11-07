extends SceneTree

# 06.01 UNIT VISIBLE ("If one or more models in a unit are visible to the
# observing model, that unit is visible") + 19.01 ("An attached unit is a single
# unit for all rules purposes") on the TARGET side of shooting.
#
# Regression: _check_target_visibility, explain_target_ineligibility and
# unit_sight_line only looped over the bodyguard dict's models. The engine keeps
# an attached CHARACTER as its own unit dict (skipped as a target), so its models
# never counted: with every bodyguard model hidden beyond detection range, a
# leader standing in plain sight did not make the Attached unit a target (and
# validate_shoot refused the shot). 13.09's keyword test is judged per model from
# its own component (19.03): an attached non-INFANTRY leader in the same terrain
# is not hidden even though its bodyguard is.
#
# Regression 2 (sections E-H): the PER-MODEL shooter check
# (get_eligible_shooter_models — the resolve-time filter, the split-fire picker
# and build_snap_assignments_11e) still measured the bodyguard dict alone, so an
# Attached unit visible / in range only through its leader was offered and
# validated as a target, then every shooting model was dropped: no attacks, and
# a FIRE OVERWATCH spent its 1CP for nothing. 04.02 "each target must be:
# Visible to the model that has that weapon ... Within range of that weapon"
# (FAQ: the visible model and the in-range model may be different models). The
# same check now applies the 13.09 gate per pair: a model beyond a hidden
# model's detection range does not see it.
#
# Usage: godot --headless --path . -s tests/test_hidden_attached_target_11e.gd

## GameStateData.Phase.MOVEMENT — a literal: naming the class here compiles
## GameState.gd before the autoloads exist (spurious compile errors).
const PHASE_MOVEMENT := 7

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure
var GS = null
var RE = null
var TM = null
var CAM = null
var MEAS = null

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _initialize() -> void:
	await create_timer(0.3).timeout
	_run()
	if not _completed:
		failed += 1
		print("  FAIL: the run aborted before its last check (see the SCRIPT ERROR above)")
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

func _model(id: String, x: float, y: float, wounds: int = 1) -> Dictionary:
	return {"id": id, "alive": true, "wounds": wounds, "current_wounds": wounds,
		"base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}}

## Shooter (36" gun) at x=400; bodyguard in a LIGHT area 17" away (hidden,
## beyond 15" detection); the leader at x=leader_x.
func _setup(leader_kws: Array, leader_x: float) -> void:
	for uid in GS.state.units.keys():
		GS.state.units.erase(uid)
	TM.terrain_features = [
		{"id": "light_area", "type": "barricade", "polygon": _rect(1200, 1000, 200, 200), "height_category": "low"},
	]
	GS.state.units["U_SHOOT"] = {"id": "U_SHOOT", "owner": 2, "status": 2, "flags": {},
		"meta": {"name": "Shooter", "keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 5, "wounds": 1, "move": 6},
			"weapons": [{"name": "Test gun", "type": "Ranged", "range": "36",
				"attacks": "2", "ballistic_skill": "4", "strength": "4", "ap": "0",
				"damage": "1", "keywords": [], "special_rules": ""}]},
		"models": [_model("s0", 400.0, 1000.0)]}
	GS.state.units["U_BG"] = {"id": "U_BG", "owner": 1, "status": 2, "flags": {},
		"meta": {"name": "Guard Squad", "keywords": ["INFANTRY", "CUSTODIAN GUARD"],
			"stats": {"toughness": 6, "save": 2, "wounds": 3, "move": 6}},
		"models": [_model("b0", 1140.0, 980.0, 3), _model("b1", 1140.0, 1020.0, 3)]}
	GS.state.units["U_LDR"] = {"id": "U_LDR", "owner": 1, "status": 2, "flags": {}, "attached_to": null,
		"meta": {"name": "Leader", "keywords": leader_kws,
			"leader_data": {"can_lead": ["CUSTODIAN GUARD"]},
			"stats": {"toughness": 6, "save": 2, "wounds": 6, "move": 6}},
		"models": [_model("l0", leader_x, 1000.0, 6)]}

func _weapon_id(board: Dictionary) -> String:
	var uw: Dictionary = RE.get_unit_weapons("U_SHOOT", board)
	for k in uw:
		for w in uw[k]:
			return str(w)
	return ""

func _validate(board: Dictionary) -> Dictionary:
	return RE.validate_shoot({"type": "SHOOT", "actor_unit_id": "U_SHOOT", "payload": {"assignments": [
		{"weapon_id": _weapon_id(board), "target_unit_id": "U_BG", "model_ids": ["s0"]}]}}, board)

## Generic layout: `shooters` / `bg` / `leader` are [[id, x, y], ...]; the
## shooter's gun has `gun_range` and 2 attacks per model; U_LDR (if any) is
## attached to U_BG; U_BG is INFANTRY.
func _setup_layout(terrain: Array, gun_range: String, shooters: Array, bg: Array, leader: Array, leader_kws: Array = ["CHARACTER", "INFANTRY"]) -> void:
	for uid in GS.state.units.keys():
		GS.state.units.erase(uid)
	TM.terrain_features = terrain
	var sm: Array = []
	for s in shooters:
		sm.append(_model(s[0], s[1], s[2]))
	GS.state.units["U_SHOOT"] = {"id": "U_SHOOT", "owner": 2, "status": 2, "flags": {},
		"meta": {"name": "Shooter", "keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 5, "wounds": 1, "move": 6},
			"weapons": [{"name": "Test gun", "type": "Ranged", "range": gun_range,
				"attacks": "2", "ballistic_skill": "2", "strength": "8", "ap": "0",
				"damage": "1", "keywords": [], "special_rules": ""}]},
		"models": sm}
	var bm: Array = []
	for b in bg:
		bm.append(_model(b[0], b[1], b[2], 3))
	GS.state.units["U_BG"] = {"id": "U_BG", "owner": 1, "status": 2, "flags": {},
		"meta": {"name": "Guard Squad", "keywords": ["INFANTRY", "CUSTODIAN GUARD"],
			"stats": {"toughness": 6, "save": 6, "wounds": 3, "move": 6}},
		"models": bm}
	if leader.is_empty():
		return
	var lm: Array = []
	for l in leader:
		lm.append(_model(l[0], l[1], l[2], 6))
	GS.state.units["U_LDR"] = {"id": "U_LDR", "owner": 1, "status": 2, "flags": {}, "attached_to": null,
		"meta": {"name": "Leader", "keywords": leader_kws,
			"leader_data": {"can_lead": ["CUSTODIAN GUARD"]},
			"stats": {"toughness": 6, "save": 6, "wounds": 6, "move": 6}},
		"models": lm}
	CAM.attach_character("U_LDR", "U_BG")

func _edge_in(a: Dictionary, b: Dictionary) -> float:
	return MEAS.px_to_inches(MEAS.model_to_model_distance_px(a, b))

func _hit_dice(res: Dictionary) -> int:
	var n := 0
	for d in res.get("dice", []):
		if str(d.get("context", "")) in ["to_hit", "auto_hit", "overwatch_to_hit"]:
			n += int(d.get("rolls_raw", d.get("rolls", [])).size())
	return n

## resolve_shoot of every listed shooter model at U_BG on a FRESH snapshot
## (resolve_shoot writes casualties into the board it is given).
func _resolve(model_ids: Array) -> Dictionary:
	var board: Dictionary = GS.create_snapshot()
	return RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": "U_SHOOT", "payload": {"assignments": [
		{"weapon_id": _weapon_id(board), "target_unit_id": "U_BG", "model_ids": model_ids}]}}, board, RE.RNGService.new(4242))

func _run() -> void:
	print("\n=== test_hidden_attached_target_11e ===")
	GS = root.get_node("GameState")
	RE = root.get_node("RulesEngine")
	TM = root.get_node("TerrainManager")
	CAM = root.get_node("CharacterAttachmentManager")
	MEAS = root.get_node("Measurement")
	var prev_terrain = TM.terrain_features.duplicate(true)
	var prev_units = GS.state.units.duplicate(true)
	GameConstants.edition = 11
	GS.state["meta"]["battle_round"] = 2
	GS.state["meta"]["active_player"] = 2
	GS.state["meta"]["first_turn_player"] = 1

	print("\n-- A. a leader in plain sight exposes its hidden bodyguard's Attached unit --")
	_setup(["CHARACTER", "INFANTRY"], 1040.0)  # leader 1.5" outside the light area
	var board: Dictionary = GS.create_snapshot()
	var lm: Dictionary = board.units["U_LDR"].models[0]
	var bm: Dictionary = board.units["U_BG"].models[0]
	var sm: Dictionary = board.units["U_SHOOT"].models[0]
	_check("setup: the bodyguard is hidden and beyond 15\" (%.1f\")" % MEAS.px_to_inches(MEAS.model_to_model_distance_px(sm, bm)),
		TM.is_model_hidden(bm, board.units["U_BG"]) and not TM.hidden_model_visible_to(bm, board.units["U_BG"], sm))
	_check("setup: the leader is outside the area, not hidden, visible", not TM.is_model_hidden(lm, board.units["U_LDR"])
		and TM.hidden_model_visible_to(lm, board.units["U_LDR"], sm))
	_check("control: the standalone leader is a legal target", RE.get_eligible_targets("U_SHOOT", board).has("U_LDR"))
	CAM.attach_character("U_LDR", "U_BG")
	board = GS.create_snapshot()
	_check("attached (attached_to = U_BG)", str(board.units["U_LDR"].get("attached_to", "")) == "U_BG")
	var elig: Dictionary = RE.get_eligible_targets("U_SHOOT", board)
	_check("the Attached unit (U_BG) is a legal target through its visible leader", elig.has("U_BG"), str(elig.keys()))
	_check("... the leader's own dict is still not a separate target", not elig.has("U_LDR"))
	var why: Dictionary = RE.explain_target_ineligibility("U_SHOOT", "U_BG", board)
	_check("explain_target_ineligibility agrees (code '')", str(why.get("code", "?")) == "", str(why))
	var v := _validate(board)
	_check("validate_shoot accepts the shot at U_BG", v.get("valid", false), str(v))
	_check("unit_sight_line sees the Attached unit (the leader)", RE.unit_sight_line("U_SHOOT", "U_BG", board, false).has_los)
	_check("_has_los_to_target_unit agrees", RE._has_los_to_target_unit("U_SHOOT", "U_BG", board))

	print("\n-- B. the leader inside the terrain too: the whole unit is hidden --")
	_setup(["CHARACTER", "INFANTRY"], 1180.0)
	CAM.attach_character("U_LDR", "U_BG")
	board = GS.create_snapshot()
	_check("leader hidden as well", TM.is_model_hidden(board.units["U_LDR"].models[0], board.units["U_LDR"]))
	elig = RE.get_eligible_targets("U_SHOOT", board)
	_check("no legal target", not elig.has("U_BG"), str(elig.keys()))
	why = RE.explain_target_ineligibility("U_SHOOT", "U_BG", board)
	_check("explain says Hidden", str(why.get("code", "")) == "hidden", str(why))
	_check("validate_shoot refuses", not _validate(board).get("valid", true))

	print("\n-- C. keywords per component (19.03): a MOUNTED leader in the same terrain is not hidden --")
	_setup(["CHARACTER", "MOUNTED"], 1180.0)
	CAM.attach_character("U_LDR", "U_BG")
	board = GS.create_snapshot()
	_check("the MOUNTED leader is not hidden (no INFANTRY/BEASTS/SWARM keyword)",
		not TM.is_model_hidden(board.units["U_LDR"].models[0], board.units["U_LDR"]))
	elig = RE.get_eligible_targets("U_SHOOT", board)
	_check("so the Attached unit is a legal target (its leader is visible at ~19\")", elig.has("U_BG"), str(elig.keys()))
	_check("explain agrees", str(RE.explain_target_ineligibility("U_SHOOT", "U_BG", board).get("code", "?")) == "")

	print("\n-- D. a leader beyond weapon range does not help; a wiped bodyguard drops the link (19.05) --")
	_setup(["CHARACTER", "INFANTRY"], 1040.0)
	GS.state.units["U_SHOOT"].meta.weapons[0]["range"] = "12"
	CAM.attach_character("U_LDR", "U_BG")
	board = GS.create_snapshot()
	why = RE.explain_target_ineligibility("U_SHOOT", "U_BG", board)
	_check("12\" gun: out of range of the whole Attached unit", str(why.get("code", "")) == "out_of_range", str(why))
	_setup(["CHARACTER", "INFANTRY"], 1040.0)
	CAM.attach_character("U_LDR", "U_BG")
	for m in GS.state.units["U_BG"].models:
		m["alive"] = false
	board = GS.create_snapshot()
	_check("bodyguard wiped: U_BG is not a target on the strength of the leader's model",
		not RE.get_eligible_targets("U_SHOOT", board).has("U_BG"))

	_section_leader_only_in_range()
	_section_leader_only_in_sight()
	_section_per_model_hidden_gate()
	_section_fire_overwatch_leader_only()

	TM.terrain_features = prev_terrain
	GS.state.units = prev_units
	GameConstants.edition = 10
	_completed = true

## E. 18" gun; the leader is 15.7" away, its bodyguard (1.8" behind him, in
## coherency) 18.7" — only the leader is within range (01.04.01: a unit is
## within a distance if one of its models is).
func _section_leader_only_in_range() -> void:
	print("\n-- E. only the leader is within range: the shooter still fires (04.02 / 19.01) --")
	_setup_layout([], "18", [["s0", 400.0, 1000.0]],
		[["b0", 1200.0, 980.0], ["b1", 1200.0, 1020.0]], [["l0", 1080.0, 1000.0]])
	var board: Dictionary = GS.create_snapshot()
	var s0: Dictionary = board.units["U_SHOOT"].models[0]
	var dl := _edge_in(s0, board.units["U_LDR"].models[0])
	var db := minf(_edge_in(s0, board.units["U_BG"].models[0]), _edge_in(s0, board.units["U_BG"].models[1]))
	_check("setup: leader within 18\" (%.2f\"), bodyguard beyond (%.2f\")" % [dl, db], dl <= 18.0 and db > 18.0)
	_check("the Attached unit is a legal target", RE.get_eligible_targets("U_SHOOT", board).has("U_BG"))
	_check("validate_shoot accepts it", _validate(board).get("valid", false))
	var esm: Dictionary = RE.get_eligible_shooter_models("U_SHOOT", _weapon_id(board), "U_BG", board)
	_check("get_eligible_shooter_models keeps s0", esm.eligible == ["s0"], "eligible=%s reasons=%s" % [esm.eligible, esm.reasons])
	_check("... measured to the leader (distance %.2f\")" % float(esm.distances.get("s0", -1.0)),
		absf(float(esm.distances.get("s0", -1.0)) - dl) < 0.01)
	var filt: Dictionary = RE.filter_eligible_model_ids(["s0"], "U_SHOOT", _weapon_id(board), "U_BG", board)
	_check("the resolve-time filter drops nobody", filt.kept == ["s0"] and filt.dropped.is_empty(), str(filt))
	var res: Dictionary = _resolve(["s0"])
	_check("resolve_shoot rolls the 2 attacks (%d hit dice)" % _hit_dice(res), _hit_dice(res) == 2, str(res.get("log_text", "")))
	board = GS.create_snapshot()
	var snap: Array = RE.build_snap_assignments_11e("U_SHOOT", "U_BG", board)
	_check("build_snap_assignments_11e fires s0 (snap shooting)",
		snap.size() == 1 and snap[0].get("model_ids", []) == ["s0"], str(snap))

## F. The bodyguard stands behind a dense (Solid) ruin wall; its leader, 1.7"
## away, is in plain sight.
func _section_leader_only_in_sight() -> void:
	print("\n-- F. only the leader is visible: the shooter still fires (04.02 / 06.01) --")
	_setup_layout([{"id": "wall", "type": "ruins", "polygon": _rect(790, 975, 20, 150), "height_category": "tall"}], "36",
		[["s0", 400.0, 1000.0]], [["b0", 1000.0, 980.0], ["b1", 1000.0, 1020.0]], [["l0", 1000.0, 1140.0]])
	var board: Dictionary = GS.create_snapshot()
	var s0: Dictionary = board.units["U_SHOOT"].models[0]
	var p0 := Vector2(400, 1000)
	_check("setup: the wall blocks both bodyguard models, the leader is in sight",
		not RE._check_line_of_sight(p0, Vector2(1000, 980), board, s0, board.units["U_BG"].models[0])
		and not RE._check_line_of_sight(p0, Vector2(1000, 1020), board, s0, board.units["U_BG"].models[1])
		and RE._check_line_of_sight(p0, Vector2(1000, 1140), board, s0, board.units["U_LDR"].models[0]))
	_check("the Attached unit is a legal target", RE.get_eligible_targets("U_SHOOT", board).has("U_BG"))
	var esm: Dictionary = RE.get_eligible_shooter_models("U_SHOOT", _weapon_id(board), "U_BG", board)
	_check("get_eligible_shooter_models keeps s0", esm.eligible == ["s0"], "eligible=%s reasons=%s" % [esm.eligible, esm.reasons])
	var res: Dictionary = _resolve(["s0"])
	_check("resolve_shoot rolls the 2 attacks (%d hit dice)" % _hit_dice(res), _hit_dice(res) == 2, str(res.get("log_text", "")))
	board = GS.create_snapshot()
	var targets: Array = RE.snap_shooting_targets_11e("U_SHOOT", board)
	_check("FIRE OVERWATCH would offer the Attached unit", targets.any(func(t): return str(t.get("unit_id", "")) == "U_BG"), str(targets))
	var snap: Array = RE.build_snap_assignments_11e("U_SHOOT", "U_BG", board)
	_check("... and build_snap_assignments_11e fires s0 at it",
		snap.size() == 1 and snap[0].get("model_ids", []) == ["s0"], str(snap))

## G. 13.09 per model ("Visible to the model that has that weapon", 04.02).
func _section_per_model_hidden_gate() -> void:
	print("\n-- G. a model beyond a hidden model's detection range does not see it (13.09, per model) --")
	# G1: a lone unit hidden in a light area; one shooter 12.7" away, one 17.7".
	_setup_layout([{"id": "light_area", "type": "barricade", "polygon": _rect(1200, 1000, 200, 200), "height_category": "low"}], "36",
		[["s_near", 620.0, 1000.0], ["s_far", 420.0, 1000.0]], [["b0", 1180.0, 980.0], ["b1", 1180.0, 1020.0]], [])
	var board: Dictionary = GS.create_snapshot()
	var bu: Dictionary = board.units["U_BG"]
	var near_m: Dictionary = board.units["U_SHOOT"].models[0]
	var far_m: Dictionary = board.units["U_SHOOT"].models[1]
	_check("setup: the squad is hidden; s_near within 15\" (%.1f\"), s_far beyond (%.1f\")" % [_edge_in(near_m, bu.models[0]), _edge_in(far_m, bu.models[0])],
		TM.is_model_hidden(bu.models[0], bu) and TM.is_model_hidden(bu.models[1], bu)
		and TM.hidden_model_visible_to(bu.models[0], bu, near_m) and not TM.hidden_model_visible_to(bu.models[0], bu, far_m)
		and not TM.hidden_model_visible_to(bu.models[1], bu, far_m))
	_check("the squad is a legal target (s_near sees it)", RE.get_eligible_targets("U_SHOOT", board).has("U_BG"))
	var esm: Dictionary = RE.get_eligible_shooter_models("U_SHOOT", _weapon_id(board), "U_BG", board)
	_check("only s_near may fire; s_far cannot see it (no_los)",
		esm.eligible == ["s_near"] and str(esm.reasons.get("s_far", "")) == "no_los", "eligible=%s reasons=%s" % [esm.eligible, esm.reasons])
	var res: Dictionary = _resolve(["s_near", "s_far"])
	_check("resolve_shoot rolls s_near's 2 attacks only (%d hit dice)" % _hit_dice(res), _hit_dice(res) == 2, str(res.get("log_text", "")))
	# G2: s0's only clear line is to the attached leader, hidden in a light
	# area 15.6" away; the bodyguard is behind a wall. s1 sees the bodyguard.
	_setup_layout([{"id": "wall", "type": "ruins", "polygon": _rect(790, 975, 20, 150), "height_category": "tall"},
		{"id": "light_area", "type": "barricade", "polygon": _rect(1040, 1130, 100, 100), "height_category": "low"}], "36",
		[["s0", 380.0, 1000.0], ["s1", 400.0, 1300.0]], [["b0", 1000.0, 980.0], ["b1", 1000.0, 1020.0]], [["l0", 1040.0, 1130.0]])
	board = GS.create_snapshot()
	var lu: Dictionary = board.units["U_LDR"]
	var s0: Dictionary = board.units["U_SHOOT"].models[0]
	_check("setup: s0 has a line only to the leader, who is hidden beyond 15\" (%.2f\")" % _edge_in(s0, lu.models[0]),
		TM.is_model_hidden(lu.models[0], lu) and not TM.hidden_model_visible_to(lu.models[0], lu, s0)
		and RE._check_line_of_sight(Vector2(380, 1000), Vector2(1040, 1130), board, s0, lu.models[0])
		and not RE._check_line_of_sight(Vector2(380, 1000), Vector2(1000, 980), board, s0, board.units["U_BG"].models[0])
		and not RE._check_line_of_sight(Vector2(380, 1000), Vector2(1000, 1020), board, s0, board.units["U_BG"].models[1]))
	_check("the Attached unit is a legal target (s1 sees the bodyguard)", RE.get_eligible_targets("U_SHOOT", board).has("U_BG"))
	esm = RE.get_eligible_shooter_models("U_SHOOT", _weapon_id(board), "U_BG", board)
	_check("s1 fires; s0 sees no model of the unit (no_los)",
		esm.eligible == ["s1"] and str(esm.reasons.get("s0", "")) == "no_los", "eligible=%s reasons=%s" % [esm.eligible, esm.reasons])

## H. The REAL FIRE OVERWATCH path (ork11e_orks_reactive): Custodian Guard A
## (24" spears) at Boyz B + their attached Warboss A, where only the Warboss is
## within 24" — the 1CP must buy attacks.
func _section_fire_overwatch_leader_only() -> void:
	print("\n-- H. FIRE OVERWATCH at an Attached unit only its leader brings within range --")
	var slm = root.get_node("SaveLoadManager")
	var ok: bool = slm.load_game_from_file_path("res://tests/saves/ork11e_orks_reactive.w40ksave")
	GameConstants.edition = 11
	_check("fixture loaded", ok)
	if not ok:
		return
	var keep := ["U_CUSTODIAN_GUARD_A", "U_BOYZ_B", "U_WARBOSS_A"]
	var units: Dictionary = {}
	for uid in keep:
		units[uid] = GS.state.units[uid]
	GS.state.units = units
	GS.state.board["objectives"] = []
	GS.state.meta["battle_round"] = 2
	GS.state.meta["active_player"] = 2  # the Orks move; Custodes (P1) may overwatch
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	TM.terrain_features = []
	var sm = root.get_node("StratagemManager")
	sm._usage_history = {"1": [], "2": []}
	var mm = root.get_node("MissionManager")
	mm.objective_control_state = {}
	mm.objective_contested_state = {}
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").auto_allocate_wounds = true
	var px := 40.0
	var i := 0
	for m in GS.state.units["U_CUSTODIAN_GUARD_A"].models:
		if m.get("alive", true):
			m["position"] = {"x": (20.0 + i * 1.8) * px, "y": 10.0 * px}
			i += 1
	var cg0: Dictionary = GS.state.units["U_CUSTODIAN_GUARD_A"].models[0]
	var wb: Dictionary = GS.state.units["U_WARBOSS_A"].models[0]
	wb["position"] = {"x": 20.0 * px, "y": 34.6 * px}
	wb["position"] = {"x": 20.0 * px, "y": (34.6 - (_edge_in(cg0, wb) - 23.0)) * px}  # ~23" from the Guard
	var wb_y: float = float(wb.position.y) / px
	var j := 0
	for m in GS.state.units["U_BOYZ_B"].models:
		if m.get("alive", true):
			m["position"] = {"x": (16.0 + j * 1.4) * px, "y": (wb_y + 2.4) * px}
			j += 1
	var d_w := INF
	var d_b := INF
	for cm in GS.state.units["U_CUSTODIAN_GUARD_A"].models:
		if not cm.get("alive", true):
			continue
		d_w = minf(d_w, _edge_in(cm, wb))
		for bm in GS.state.units["U_BOYZ_B"].models:
			if bm.get("alive", true):
				d_b = minf(d_b, _edge_in(cm, bm))
	_check("setup: Warboss within 24\" (%.2f\"), every Boy beyond (%.2f\")" % [d_w, d_b], d_w <= 24.0 and d_b > 24.0)
	var board: Dictionary = GS.create_snapshot()
	var snap: Array = RE.build_snap_assignments_11e("U_CUSTODIAN_GUARD_A", "U_BOYZ_B", board)
	_check("build_snap_assignments_11e is not empty", not snap.is_empty(), str(snap))
	var pm = root.get_node("PhaseManager")
	pm.transition_to_phase(PHASE_MOVEMENT)
	var phase = pm.get_current_phase_instance()
	var guard := 0
	while phase != null and phase.has_pending_stratagem_window() and guard < 6:
		var w0 = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w0.player), "window_id": str(w0.window_id)})
		guard += 1
	phase.execute_action({"type": "END_MOVEMENT", "player": 2})
	guard = 0
	while phase.has_pending_stratagem_window() and int(phase.get_pending_stratagem_window().player) == 2 and guard < 4:
		var w1 = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": str(w1.window_id)})
		guard += 1
	var offered := false
	if phase.has_pending_stratagem_window():
		for o in phase.get_pending_stratagem_window().get("offers", []):
			if str(o.get("stratagem_id", "")) == "fire_overwatch_11e":
				for t in o.get("targets", []):
					if str(t.get("unit_id", "")) == "U_CUSTODIAN_GUARD_A":
						offered = t.get("secondary", {}).get("options", []).any(func(x): return str(x.get("id", "")) == "U_BOYZ_B")
	_check("P1's movement_phase_end window offers FIRE OVERWATCH at Boyz B", offered)
	var res: Dictionary = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "movement_phase_end",
		"stratagem_id": "fire_overwatch_11e", "target_unit_id": "U_CUSTODIAN_GUARD_A", "context": {"secondary_id": "U_BOYZ_B"}})
	_check("FIRE OVERWATCH resolved", res.get("success", false), str(res.get("error", "")))
	_check("1CP spent (6 -> %d)" % int(GS.state.players["1"]["cp"]), int(GS.state.players["1"]["cp"]) == 5)
	_check("... and the Custodian Guard made attacks (%d hit dice)" % _hit_dice(res), _hit_dice(res) > 0,
		str(res.get("fire_overwatch_log_lines", [])))

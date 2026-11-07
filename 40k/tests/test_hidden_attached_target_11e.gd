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
# Usage: godot --headless --path . -s tests/test_hidden_attached_target_11e.gd

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

	TM.terrain_features = prev_terrain
	GS.state.units = prev_units
	GameConstants.edition = 10
	_completed = true

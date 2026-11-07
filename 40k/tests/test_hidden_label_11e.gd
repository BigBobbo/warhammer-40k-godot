extends SceneTree

# The 13.09 HIDDEN refusal text on the LoS overlay label and in the
# explain_target_ineligibility prose.
#
# Regressions:
#   ▪ A model is refused for Hidden only when its edge distance is STRICTLY
#     greater than the detection range, but the distance was printed with %.1f,
#     so 15.01" read 'only visible within 15" (closest 15.0")' — already close
#     enough, by the label's own words. Same for Lone Operative / Psychic Veil
#     ("must be within 18" (currently 18.0")"). RulesEngine.format_limit_and_beyond
#     now rounds the distance UP and the limit DOWN to 0.1".
#   ▪ The label's numbers belong to the closest pair with a CLEAR sight line,
#     while the overlay draws the nearest pair (possibly cut by a wall), so the
#     wording now describes the unit ("Hidden unit: seen within 15" (your best
#     LoS 16.8")") instead of reading as the drawn line's distance.
#   ▪ The label is drawn only inside _draw(); LoSDebugVisual.drawn_reason_labels
#     now records what was written, so tests and scenarios can assert it.
#
# Usage: godot --headless --path . -s tests/test_hidden_label_11e.gd

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure
var TM = null
var RE = null
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
	await _run()
	if not _completed:
		failed += 1
		print("  FAIL: the run aborted before its last check (see the SCRIPT ERROR above)")
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

## Shooter (40mm) placed so its base edge is exactly `edge_in` from a 32mm
## INFANTRY target hidden in a barricade (light) area.
func _board(edge_in: float) -> Dictionary:
	var t_model = {"id": "t1", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 400.0, "y": 400.0}}
	var cy: float = 400.0 + MEAS.base_radius_px(32) + MEAS.base_radius_px(40) + MEAS.inches_to_px(edge_in)
	var s_model = {"id": "s1", "alive": true, "base_mm": 40, "base_type": "circular", "position": {"x": 400.0, "y": cy}}
	return {"units": {
		"U_S": {"id": "U_S", "owner": 1, "flags": {}, "models": [s_model], "meta": {"name": "Guard", "display_name": "Guard", "keywords": ["INFANTRY"], "stats": {},
			"weapons": [{"id": "spear", "name": "spear", "type": "Ranged", "range": "24", "attacks": "1", "ballistic_skill": "2", "strength": "4", "ap": "0", "damage": "1"}], "abilities": []}},
		"U_T": {"id": "U_T", "owner": 2, "flags": {}, "models": [t_model], "meta": {"name": "Boyz", "display_name": "Boyz", "keywords": ["INFANTRY"], "stats": {}, "weapons": [], "abilities": []}}},
		"terrain_features": TM.terrain_features, "meta": {"phase": 8, "active_player": 1, "battle_round": 2}}

func _run() -> void:
	print("\n=== test_hidden_label_11e ===")
	TM = root.get_node("TerrainManager")
	RE = root.get_node("RulesEngine")
	MEAS = root.get_node("Measurement")
	var gs = root.get_node("GameState")
	gs.state["meta"]["battle_round"] = 2
	gs.state["meta"]["active_player"] = 1
	var prev_terrain = TM.terrain_features.duplicate(true)
	GameConstants.edition = 11

	print("\n-- A. format_limit_and_beyond: the printed distance is always beyond the printed limit --")
	var cases := [[15.0, 15.01, "15", "15.1"], [15.0, 15.04, "15", "15.1"], [15.0, 15.2, "15", "15.2"],
		[15.0, 15.0099990844727, "15", "15.1"], [12.0, 12.0000001, "12", "12.1"], [13.5, 13.51, "13.5", "13.6"],
		[18.0, 18.04, "18", "18.1"], [9.0, 16.75, "9", "16.8"], [15.0, 15.0, "15", "15.1"]]
	for c in cases:
		var got: Array = RE.format_limit_and_beyond(float(c[0]), float(c[1]))
		_check("limit %s, actual %s -> \"%s\" / \"%s\"" % [str(c[0]), str(c[1]), c[2], c[3]], got[0] == c[2] and got[1] == c[3], str(got))

	print("\n-- B. a hidden target just beyond 15\": prose, structured text and board label --")
	TM.terrain_features = [{"id": "barricade", "type": "barricade", "polygon": _rect(400, 400, 200, 200), "height_category": "low"}]
	var lv = load("res://scripts/LoSDebugVisual.gd").new()
	root.add_child(lv)
	for edge_in in [15.01, 15.04, 15.2]:
		RE.clear_los_memo()
		var board := _board(edge_in)
		var why: Dictionary = RE.explain_target_ineligibility("U_S", "U_T", board)
		var want := "15.1" if edge_in < 15.1 else "15.2"
		_check("%.2f\": refused for Hidden, closest printed %s\" (never 15.0\")" % [edge_in, want],
			str(why.get("code", "")) == "hidden" and str(why.get("closest_text", "")) == want and str(why.get("detection_text", "")) == "15", str(why))
		_check("%.2f\": the prose names the closest model with a CLEAR sight line" % edge_in,
			str(why.get("reason", "")).contains("visible only within 15\" detection range; your closest model with a clear sight line is %s\" away" % want), str(why.get("reason", "")))
		var line: Dictionary = lv._unit_pair_sight_line("U_S", "U_T", board.units["U_S"], board.units["U_T"], board, true, {}, true)
		var want_label := "Hidden unit: seen within 15\" (your best LoS %s\")" % want
		_check("%.2f\": board label '%s'" % [edge_in, want_label], str(line.get("label", "")) == want_label, str(line.get("label", "")))
		_check("... and it fits the label width (%d chars)" % want_label.length(), want_label.length() <= lv.OVERVIEW_REASON_MAX_CHARS)

	print("\n-- C. drawn_reason_labels records what _draw() actually wrote --")
	RE.clear_los_memo()
	var b2 := _board(16.8)
	var hl: Dictionary = lv._unit_pair_sight_line("U_S", "U_T", b2.units["U_S"], b2.units["U_T"], b2, true, {}, true)
	lv.debug_enabled = true
	lv.overview_lines = [hl]
	lv.queue_redraw()
	await process_frame
	await process_frame
	var drawn: Array = lv.drawn_reason_labels
	_check("the red Hidden line's label was drawn", drawn.size() == 1 and str(drawn[0].get("tgt", "")) == "U_T"
		and str(drawn[0].get("text", "")) == "Hidden unit: seen within 15\" (your best LoS 16.8\")" and str(drawn[0].get("verdict", "")) == "blocked", str(drawn))
	lv.overview_lines = []
	lv.queue_redraw()
	await process_frame
	await process_frame
	_check("cleared on the next draw", lv.drawn_reason_labels.is_empty(), str(lv.drawn_reason_labels))
	lv.queue_free()
	TM.terrain_features = prev_terrain
	GameConstants.edition = 10
	_completed = true

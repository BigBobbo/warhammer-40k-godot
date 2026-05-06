extends SceneTree

# T-082: movement distance must be path-summed across re-staged segments,
# not Euclidean origin→destination.
#
# Bug per AUDIT_REPORT MOVEMENT_PHASE_AUDIT 6.4: dragging A→B then B→C set
# total_distance_for_model = |AC|, not |AB|+|BC|. A player could exploit
# this to "teleport" around terrain by re-staging through a waypoint.
#
# Fix in MovementPhase._process_stage_model_move: total_distance_for_model
# now = prior_total + segment_distance + terrain_penalty (path-sum).
#
# Usage: godot --headless --path . -s tests/test_t082_path_summed_distance.gd

var passed := 0
var failed := 0

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

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t082_path_summed_distance ===\n")
	_test_source_uses_prior_total_not_euclidean()
	_finish()

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t

func _test_source_uses_prior_total_not_euclidean() -> void:
	print("\n-- T-082: _process_stage_model_move uses prior_total + segment, not Euclidean --")
	var src = _read("res://phases/MovementPhase.gd")
	_check("MovementPhase.gd readable", not src.is_empty())

	# The fix introduces 'prior_total' read from move_data.model_distances and
	# the path-sum line. The legacy Euclidean line should no longer appear in
	# _process_stage_model_move.
	var fix_marker_a = "var prior_total = move_data.model_distances.get(model_id, 0.0)"
	var fix_marker_b = "prior_total + distance_inches + terrain_penalty"
	_check("prior_total is read from model_distances", fix_marker_a in src,
		"path-sum fix not present in MovementPhase.gd")
	_check("total_distance_for_model = prior_total + segment + terrain", fix_marker_b in src,
		"path-sum sum line missing")

	# The Euclidean line `Measurement.distance_inches(original_pos, dest_vec)`
	# should NOT appear inside _process_stage_model_move's body anymore. Other
	# uses (e.g. CONFIRM_UNIT_MOVE, charge resolution) are fine.
	var stage_fn_idx = src.find("func _process_stage_model_move")
	var next_fn_idx = src.find("\nfunc ", stage_fn_idx + 1)
	var stage_body = src.substr(stage_fn_idx, next_fn_idx - stage_fn_idx) if stage_fn_idx >= 0 else ""
	_check("_process_stage_model_move body found", stage_fn_idx >= 0 and stage_body.length() > 100)
	_check("Euclidean origin→dest line removed from stage body",
		not "Measurement.distance_inches(original_pos, dest_vec)" in stage_body,
		"Euclidean line still present in _process_stage_model_move — fix incomplete")

	# Per-segment terrain penalty (current_pos → dest_vec), not whole-line.
	_check("terrain penalty uses current_pos (per-segment)",
		"_get_movement_terrain_penalty(current_pos, dest_vec, unit_id)" in stage_body,
		"terrain penalty should be per-segment for path-sum")

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

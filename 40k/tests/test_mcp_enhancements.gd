extends SceneTree

# Headless unit coverage for the godot-mcp addon enhancements:
#   * testing_handlers.categorize_log_lines / _classify_log_line
#   * testing_handlers _diff_entry (snapshot diffing)
#   * execute_script compiled multi-line path (return value)
#
# These are pure / tree-light helpers, so they are validated headless-only per
# the project gate (no UI affordance). The live bridge commands (read_debug_log,
# scene_snapshot, diff_snapshot, verify_delivery, chain_verify) wrap these and
# require a running game to exercise end-to-end.
#
# Run via: godot --headless --path 40k --script tests/test_mcp_enhancements.gd

const TestingHandlers := preload("res://addons/godot_mcp/handlers/testing_handlers.gd")

var _passed := 0
var _failed := 0


func _initialize():
	# One frame so the SceneTree root is fully attached (node paths resolve).
	await process_frame
	print("\n=== godot-mcp enhancements: headless helper tests ===\n")
	_test_log_categorization()
	_test_log_marker_format_fallback()
	_test_diff_entry()
	_test_compiled_execute()
	print("\n--- %d passed, %d failed ---" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("[PASS] %s" % label)
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _test_log_categorization() -> void:
	var lines := [
		"[2026-05-29 12:00:00] [INFO   ] DebugLogger initialized",
		"[2026-05-29 12:00:01] [WARNING] low ammo",
		"[2026-05-29 12:00:02] [ERROR  ] unit not found",
		"[2026-05-29 12:00:03] [DEBUG  ] tick",
		"",
		"plain unclassified line",
	]
	var summary := TestingHandlers.categorize_log_lines(lines)
	var counts: Dictionary = summary["counts"]
	_check("categorize: 1 error", counts["error"] == 1)
	_check("categorize: 1 warning", counts["warning"] == 1)
	_check("categorize: 1 info", counts["info"] == 1)
	_check("categorize: 1 debug", counts["debug"] == 1)
	_check("categorize: 1 other (blank skipped)", counts["other"] == 1)
	_check("categorize: error line captured", summary["errors"].size() == 1)
	_check("categorize: warning line captured", summary["warnings"].size() == 1)


func _test_log_marker_format_fallback() -> void:
	# Raw engine output (no DebugLogger brackets) should still classify.
	var lines := [
		"ERROR: Cannot open file 'x'.",
		"SCRIPT ERROR: Parse Error: boom",
		"WARNING: deprecated call",
		"random noise",
	]
	var summary := TestingHandlers.categorize_log_lines(lines)
	_check("fallback: 2 errors (ERROR: + SCRIPT ERROR)", summary["counts"]["error"] == 2)
	_check("fallback: 1 warning", summary["counts"]["warning"] == 1)
	_check("fallback: 1 other", summary["counts"]["other"] == 1)


func _test_diff_entry() -> void:
	var th = TestingHandlers.new()
	var before := {"type": "Node2D", "position": [10.0, 20.0], "visible": true,
		"props": {"hp": 5, "name": "a"}}
	var after := {"type": "Node2D", "position": [30.0, 20.0], "visible": false,
		"props": {"hp": 3, "name": "a"}}
	var d: Dictionary = th._diff_entry(before, after)
	_check("diff: position change detected", d.has("position"))
	_check("diff: visible change detected", d.has("visible"))
	_check("diff: type unchanged not reported", not d.has("type"))
	_check("diff: hp prop change detected", d.has("props") and d["props"].has("hp"))
	_check("diff: unchanged prop 'name' not reported", d.has("props") and not d["props"].has("name"))

	var same: Dictionary = th._diff_entry(before, before.duplicate(true))
	_check("diff: identical entries produce empty diff", same.is_empty())


func _test_compiled_execute() -> void:
	# Multi-line compiled snippet returns a value; node arg is the target.
	var th = TestingHandlers.new()
	var host_node := Node.new()
	root.add_child(host_node)  # host must live in the tree so get_node_or_null works
	th.host = host_node
	var res = th.execute_script({
		"code": "var total = 0\nfor i in range(5):\n\ttotal += i\nreturn total",
		"multiline": true,
		"node_path": "/root",
	})
	_check("compiled execute: status ok", res.get("status", "") == "ok")
	_check("compiled execute: sum(0..4) == 10", res.get("result", null) == 10)

	# `tree` binding: node/tree methods resolve through the params, not bare.
	var tree_res = th.execute_script({
		"code": "return tree.get_node_count() > 0",
		"multiline": true, "node_path": "/root",
	})
	_check("compiled execute: tree param usable", tree_res.get("status", "") == "ok" and tree_res.get("result", false) == true)

	var bad = th.execute_script({"code": "this is not valid gdscript ::", "multiline": true})
	_check("compiled execute: parse error surfaced", bad.get("status", "") == "error" and bad.get("error_type", "") == "parse")

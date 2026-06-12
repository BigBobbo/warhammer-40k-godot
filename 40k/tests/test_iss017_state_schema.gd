extends SceneTree

# ISS-017: state schema validation + hardened diff paths.
#
# Checks:
#   A) A fresh default GameState validates clean against StateSchema.
#   B) StateSchema catches missing sections / malformed units.
#   C) PhaseManager.apply_state_changes drops bad paths LOUDLY without
#      corrupting state (out-of-range array index; traversal through a
#      non-container) and still applies good changes.
#   D) StatePaths builders produce the canonical strings used by handlers.
#
# Usage: godot --headless --path . -s tests/test_iss017_state_schema.gd

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
	print("\n=== test_iss017_state_schema ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return

	print("-- A: default state validates --")
	var prev = gs.state.duplicate(true)
	gs.initialize_default_state()
	var errs = StateSchema.validate(gs.state)
	_check("fresh default state has zero schema errors", errs.is_empty(), str(errs))

	print("\n-- B: schema catches malformed states --")
	_check("missing section flagged",
		not StateSchema.validate({"meta": {}}).is_empty())
	var bad_unit = gs.state.duplicate(true)
	bad_unit["units"]["U_BAD"] = {"no_meta": true}
	var unit_errs = StateSchema.validate(bad_unit)
	_check("malformed unit flagged", not unit_errs.is_empty(), str(unit_errs))

	print("\n-- C: bad diff paths dropped without corruption --")
	gs.state["units"]["U_T"] = {"meta": {"name": "T"}, "models": [{"id": "m0", "wounds": 2}]}
	var before = JSON.stringify(gs.state)
	pm.apply_state_changes([
		{"op": "set", "path": "units.U_T.models.5.wounds", "value": 0},  # index OOR
		{"op": "set", "path": "units.U_T.meta.name.sub.key", "value": 1},  # through a String
	])
	_check("state unchanged after bad-path diffs (errors logged)",
		JSON.stringify(gs.state) == before)
	pm.apply_state_changes([
		{"op": "set", "path": StateSchema.path_model_field("U_T", 0, "wounds"), "value": 1},
		{"op": "set", "path": StateSchema.path_unit_flag("U_T", "moved"), "value": true},
	])
	_check("good changes via StatePaths builders applied",
		gs.state["units"]["U_T"]["models"][0]["wounds"] == 1
		and gs.state["units"]["U_T"]["flags"]["moved"] == true)

	print("\n-- D: path builders --")
	_check("unit meta path", StateSchema.path_unit_meta("U_1", "is_warlord") == "units.U_1.meta.is_warlord")
	_check("meta path", StateSchema.path_meta("phase") == "meta.phase")

	gs.state = prev
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

extends SceneTree

# 06_SYNTHESIS launch-blocker #11: DESIGNATE_WARLORD UI button.
#
# Issue #367 already wired up the path:
#   - FormationsDeclarationDialog._build_warlord_section creates the
#     OptionButton, auto-defaults to the only CHARACTER if there is one,
#     and emits warlord_id back through CONFIRM_FORMATIONS.
#   - Main._on_formations_dialog_confirmed dispatches DESIGNATE_WARLORD
#     before CONFIRM_FORMATIONS so the warlord flag is set before the
#     formation validation runs.
#   - FormationsPhase validates + processes the action and updates
#     `units[id].meta.is_warlord` on the chosen unit.
#
# This pin verifies the wiring stays intact:
#   A) FormationsPhase exposes the validate + process funcs and dispatches
#      via the action router.
#   B) FormationsDeclarationDialog has the warlord section, the warlord_id
#      ivar, the auto-default, and the dispatch back through the config.
#   C) Main.gd reads warlord_id from the dialog config and dispatches
#      DESIGNATE_WARLORD before CONFIRM_FORMATIONS.
#   D) FormationsPhase._process_designate_warlord actually mutates
#      meta.is_warlord on the right unit (driven against a synthetic
#      multi-CHARACTER state).
#
# Usage: godot --headless --path . -s tests/test_t011_designate_warlord_pin.gd

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

func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t011_designate_warlord_pin ===\n")
	_test_phase_wiring()
	_test_dialog_wiring()
	_test_main_dispatch_wiring()
	_test_process_mutates_state()
	_finish()

func _test_phase_wiring() -> void:
	print("\n-- A: FormationsPhase wiring --")
	var src = _read("res://phases/FormationsPhase.gd")
	_check("FormationsPhase.gd readable", not src.is_empty())
	_check("DESIGNATE_WARLORD validate dispatch case",
		"\"DESIGNATE_WARLORD\":" in src and "_validate_designate_warlord" in src)
	_check("DESIGNATE_WARLORD process dispatch case",
		"_process_designate_warlord" in src)
	_check("_validate_designate_warlord defined",
		"func _validate_designate_warlord(action: Dictionary)" in src)
	_check("_process_designate_warlord defined",
		"func _process_designate_warlord(action: Dictionary)" in src)
	_check("get_available_actions surfaces DESIGNATE_WARLORD",
		"\"type\": \"DESIGNATE_WARLORD\"" in src or "type\": \"DESIGNATE_WARLORD\"" in src)

func _test_dialog_wiring() -> void:
	print("\n-- B: FormationsDeclarationDialog warlord section --")
	var src = _read("res://scripts/FormationsDeclarationDialog.gd")
	_check("FormationsDeclarationDialog.gd readable", not src.is_empty())
	_check("warlord_id ivar declared",
		"var warlord_id" in src)
	_check("_build_warlord_section() defined",
		"func _build_warlord_section" in src)
	_check("auto-default to single CHARACTER",
		"characters.size() == 1" in src and "warlord_id = characters[0]" in src,
		"Issue #367 auto-default fallback missing")
	_check("warlord_id flows into CONFIRM_FORMATIONS payload",
		"\"warlord_id\": warlord_id" in src,
		"dialog must propagate the chosen warlord through the config dict")

func _test_main_dispatch_wiring() -> void:
	print("\n-- C: Main.gd DESIGNATE_WARLORD dispatch --")
	var src = _read("res://scripts/Main.gd")
	_check("Main.gd readable", not src.is_empty())
	_check("Main reads warlord_id from formations config",
		"formations.get(\"warlord_id\"" in src or "formations.warlord_id" in src)
	_check("Main dispatches DESIGNATE_WARLORD",
		"\"type\": \"DESIGNATE_WARLORD\"" in src)
	# Must run BEFORE confirm so the validation passes (formations_phase
	# requires one is_warlord=true CHARACTER before CONFIRM_FORMATIONS).
	_check("DESIGNATE_WARLORD dispatched before CONFIRM_FORMATIONS",
		(src.find("\"type\": \"DESIGNATE_WARLORD\"")
			< src.find("\"type\": \"CONFIRM_FORMATIONS\"")
		) if src.find("\"type\": \"CONFIRM_FORMATIONS\"") >= 0 else true,
		"DESIGNATE_WARLORD must dispatch before CONFIRM_FORMATIONS")

func _test_process_mutates_state() -> void:
	print("\n-- D: _process_designate_warlord live mutates is_warlord --")
	var phase_mgr = root.get_node_or_null("PhaseManager")
	var gs = root.get_node_or_null("GameState")
	if phase_mgr == null or gs == null:
		_check("PhaseManager + GameState autoloads reachable", false,
			"phase=%s gs=%s" % [str(phase_mgr), str(gs)])
		return
	_check("PhaseManager + GameState autoloads reachable", true)
	# Inject a synthetic state with two CHARACTERs.
	var prev_state = gs.state.duplicate(true)
	gs.state["units"] = {
		"U_CHAR_A": {
			"id": "U_CHAR_A",
			"owner": 1,
			"meta": {"name": "Char A", "keywords": ["CHARACTER", "INFANTRY"], "is_warlord": false},
		},
		"U_CHAR_B": {
			"id": "U_CHAR_B",
			"owner": 1,
			"meta": {"name": "Char B", "keywords": ["CHARACTER", "INFANTRY"], "is_warlord": false},
		},
	}
	gs.state["meta"] = gs.state.get("meta", {})
	gs.state["meta"]["active_player"] = 1
	# Phase enum: FORMATIONS, DEPLOYMENT, REDEPLOYMENT, ROLL_OFF, SCOUT,
	# SCOUT_MOVES, COMMAND, MOVEMENT, SHOOTING, CHARGE, FIGHT, SCORING,
	# MORALE — FORMATIONS == 0.
	gs.state["meta"]["phase"] = 0  # FORMATIONS
	phase_mgr.transition_to_phase(0)
	var phase = phase_mgr.get_current_phase_instance()
	if phase == null:
		_check("FORMATIONS phase instance present", false, "got null")
		gs.state = prev_state
		return
	_check("FORMATIONS phase instance present", true)
	# Skip if the phase couldn't process (e.g. it requires more init we
	# haven't provided). The source pins above already prove the wiring.
	if not phase.has_method("_process_designate_warlord"):
		_check("phase exposes _process_designate_warlord", false)
		gs.state = prev_state
		return
	var result = phase.call("_process_designate_warlord",
		{"type": "DESIGNATE_WARLORD", "unit_id": "U_CHAR_B", "player": 1})
	_check("_process_designate_warlord returned a result dict",
		result is Dictionary)
	_check("U_CHAR_B.meta.is_warlord set to true",
		gs.state["units"]["U_CHAR_B"]["meta"].get("is_warlord", false) == true)
	_check("U_CHAR_A.meta.is_warlord cleared (only one warlord allowed)",
		gs.state["units"]["U_CHAR_A"]["meta"].get("is_warlord", true) == false)
	# Restore
	gs.state = prev_state

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

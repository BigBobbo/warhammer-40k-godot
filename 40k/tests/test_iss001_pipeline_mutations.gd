extends SceneTree

# ISS-001: all in-game GameState mutations must flow through the action
# pipeline (phase handlers return diffs; PhaseManager.apply_state_changes
# applies them). Direct `GameState.state[...] = ...` writes are invisible to
# replay, undo, and multiplayer sync.
#
# This test enforces the rule two ways:
#   A) Static scan: no direct assignment into GameState.state[...] anywhere in
#      phases/, scripts/, autoloads/, dialogs/ outside the documented
#      pre-game-initialization whitelist (see GameState.gd header).
#   B) Behavioral:
#      B1. CONFIRM_FORMATIONS auto-designates the sole CHARACTER as Warlord
#          via diffs (was a mutation inside validation).
#      B2. REPAIR_FORMATION_ATTACHMENT (DeploymentPhase) repairs unlinked
#          leader attachments via diffs (was a direct write in
#          DeploymentController).
#
# Usage: godot --headless --path . -s tests/test_iss001_pipeline_mutations.gd

var passed := 0
var failed := 0

# Files allowed to write GameState.state directly (pre-game initialization
# only — must match the whitelist documented in GameState.gd).
const WRITE_WHITELIST = [
	"ArmyListManager.gd",
	"MultiplayerLobby.gd",
	"WebLobby.gd",
	"AIBenchmarkRunner.gd",
]

const SCAN_DIRS = ["res://phases", "res://scripts", "res://autoloads", "res://dialogs"]

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
	print("\n=== test_iss001_pipeline_mutations ===\n")
	_test_static_scan()
	_test_confirm_formations_auto_warlord()
	_test_repair_formation_attachment()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

# -- A: static scan ----------------------------------------------------------

func _test_static_scan() -> void:
	print("\n-- A: no direct GameState.state writes outside whitelist --")
	var rx = RegEx.new()
	# Matches `GameState.state[...][...] = value` (also += / -=) but not
	# comparisons (==) or reads.
	var err = rx.compile("GameState\\.state\\[.*\\]\\s*[+-]?=\\s*[^=]")
	_check("scan regex compiles", err == OK)
	var offenders = []
	for dir_path in SCAN_DIRS:
		_scan_dir(dir_path, rx, offenders)
	_check("no direct writes outside whitelist (%d dirs scanned)" % SCAN_DIRS.size(),
		offenders.is_empty(), ", ".join(offenders))

func _scan_dir(dir_path: String, rx: RegEx, offenders: Array) -> void:
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		var full = dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full, rx, offenders)
		elif entry.ends_with(".gd") and entry not in WRITE_WHITELIST:
			var f = FileAccess.open(full, FileAccess.READ)
			if f != null:
				var line_no = 0
				while not f.eof_reached():
					var line = f.get_line()
					line_no += 1
					if line.strip_edges().begins_with("#"):
						continue
					if rx.search(line) != null:
						offenders.append("%s:%d" % [full, line_no])
				f.close()
		entry = dir.get_next()
	dir.list_dir_end()

# -- B1: auto-warlord via diffs ----------------------------------------------

func _test_confirm_formations_auto_warlord() -> void:
	print("\n-- B1: CONFIRM_FORMATIONS auto-designates sole CHARACTER via diffs --")
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_check("GameState autoload reachable", false)
		return
	var prev_state = gs.state.duplicate(true)
	gs.state["units"] = {
		"U_CHAR_SOLO": {
			"id": "U_CHAR_SOLO",
			"owner": 1,
			"meta": {"name": "Solo Captain", "keywords": ["CHARACTER", "INFANTRY"], "is_warlord": false},
		},
		"U_GRUNTS": {
			"id": "U_GRUNTS",
			"owner": 1,
			"meta": {"name": "Grunts", "keywords": ["INFANTRY"]},
		},
	}
	gs.state["meta"] = gs.state.get("meta", {})
	gs.state["meta"]["active_player"] = 1

	var phase = load("res://phases/FormationsPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = gs.create_snapshot()
	var result = phase.execute_action({"type": "CONFIRM_FORMATIONS", "player": 1})
	_check("CONFIRM_FORMATIONS succeeded",
		result is Dictionary and result.get("success", false), str(result))
	var has_warlord_change = false
	for change in result.get("changes", []):
		if change.get("path", "") == "units.U_CHAR_SOLO.meta.is_warlord" and change.get("value") == true:
			has_warlord_change = true
	_check("auto-warlord present in result.changes (pipeline contract)", has_warlord_change,
		str(result.get("changes", [])))
	_check("U_CHAR_SOLO.meta.is_warlord applied to GameState",
		gs.state["units"]["U_CHAR_SOLO"]["meta"].get("is_warlord", false) == true)
	root.remove_child(phase)
	phase.free()
	gs.state = prev_state

# -- B2: attachment repair via diffs -----------------------------------------

func _test_repair_formation_attachment() -> void:
	print("\n-- B2: REPAIR_FORMATION_ATTACHMENT routes repair via diffs --")
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_check("GameState autoload reachable", false)
		return
	var prev_state = gs.state.duplicate(true)
	gs.state["units"] = {
		"U_BODYGUARD": {
			"id": "U_BODYGUARD",
			"owner": 1,
			"meta": {"name": "Boyz", "keywords": ["INFANTRY"]},
		},
		"U_LEADER": {
			"id": "U_LEADER",
			"owner": 1,
			"meta": {"name": "Warboss", "keywords": ["CHARACTER", "INFANTRY"]},
		},
	}
	gs.state["meta"] = gs.state.get("meta", {})
	gs.state["meta"]["formations_declared"] = true
	gs.state["meta"]["formations"] = {
		"1": {"leader_attachments": {"U_LEADER": "U_BODYGUARD"}, "transport_embarkations": {}, "reserves": []},
	}

	var phase = load("res://phases/DeploymentPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = gs.create_snapshot()
	var result = phase.execute_action({"type": "REPAIR_FORMATION_ATTACHMENT", "unit_id": "U_BODYGUARD", "player": 1})
	_check("REPAIR_FORMATION_ATTACHMENT succeeded",
		result is Dictionary and result.get("success", false), str(result))
	_check("repair carried in result.changes (pipeline contract)",
		result is Dictionary and result.get("changes", []).size() >= 2,
		str(result.get("changes", []) if result is Dictionary else []))
	var bg = gs.state["units"]["U_BODYGUARD"]
	_check("attachment_data.attached_characters applied",
		bg.get("attachment_data", {}).get("attached_characters", []) == ["U_LEADER"],
		str(bg.get("attachment_data", {})))
	_check("U_LEADER.attached_to applied",
		gs.state["units"]["U_LEADER"].get("attached_to", "") == "U_BODYGUARD")
	root.remove_child(phase)
	phase.free()
	gs.state = prev_state

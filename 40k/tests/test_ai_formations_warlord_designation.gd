extends SceneTree

# Regression net for the "AI freezes during Formations Phase" bug.
#
# Bug symptom: After the AI made the first leader attachment (e.g. Boss
# Snikrot to Kommandos) in an Orks-style army with two CHARACTER units,
# the game froze on "AI is thinking..." indefinitely.
#
# Root cause: AIDecisionMaker._decide_formations() did not pick
# DESIGNATE_WARLORD actions. With armies containing more than one CHARACTER
# (e.g. Orks with Boss Snikrot + Warboss), FormationsPhase's
# _validate_warlord_designation() requires exactly one CHARACTER to be
# is_warlord before CONFIRM_FORMATIONS will validate. Auto-designation only
# runs when there is exactly one CHARACTER, so the AI would attempt
# CONFIRM_FORMATIONS, validation would fail, and AIPlayer._execute_next_action's
# failure path had no handler for it — the watchdog kept retrying the same
# failing action.
#
# Fix:
# 1. AIDecisionMaker._decide_formations now picks DESIGNATE_WARLORD
#    (highest-points CHARACTER) before falling through to CONFIRM_FORMATIONS.
# 2. AIPlayer._execute_next_action now re-evaluates on any formations-phase
#    action failure so the AI can't silently loop.
#
# This is a *regression net* — it pins the code shape so future refactors
# don't silently remove the warlord-handling branch. Live behavior must be
# verified by running the formations phase with a multi-CHARACTER army.
#
# Usage: godot --headless --path . -s tests/test_ai_formations_warlord_designation.gd

var passed := 0
var failed := 0


func _init():
	create_timer(0.1).timeout.connect(_run)


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func _run() -> void:
	if passed > 0 or failed > 0:
		return
	print("\n=== test_ai_formations_warlord_designation ===\n")

	var dm_src = _read("res://scripts/AIDecisionMaker.gd")
	_check("AIDecisionMaker.gd readable", not dm_src.is_empty())

	# Pin 1: warlord_actions bucket exists in _decide_formations.
	_check("_decide_formations collects DESIGNATE_WARLORD into warlord_actions",
		'"DESIGNATE_WARLORD":\n\t\t\t\twarlord_actions.append(action)' in dm_src
		or "warlord_actions.append(action)" in dm_src,
		"DESIGNATE_WARLORD case missing from action-type match")

	# Pin 2: warlord designation is preferred before CONFIRM_FORMATIONS.
	# Check structural order: _evaluate_warlord_designation must appear before
	# the CONFIRM_FORMATIONS fallback in the source.
	var warlord_eval_pos = dm_src.find("_evaluate_warlord_designation(snapshot, warlord_actions")
	var confirm_pos = dm_src.find('"type": "CONFIRM_FORMATIONS"')
	_check("_evaluate_warlord_designation called before CONFIRM_FORMATIONS fallback",
		warlord_eval_pos != -1 and confirm_pos != -1 and warlord_eval_pos < confirm_pos,
		"warlord_eval_pos=%d confirm_pos=%d" % [warlord_eval_pos, confirm_pos])

	# Pin 3: _evaluate_warlord_designation function is defined.
	_check("_evaluate_warlord_designation function defined",
		"static func _evaluate_warlord_designation(" in dm_src)

	# Pin 4: AIPlayer's failure path re-evaluates on formations-phase action failures
	# so a validation failure can't stall the AI silently.
	var ai_src = _read("res://autoloads/AIPlayer.gd")
	_check("AIPlayer.gd readable", not ai_src.is_empty())
	_check("AIPlayer failure path handles CONFIRM_FORMATIONS",
		'"CONFIRM_FORMATIONS"' in ai_src
		and "_request_evaluation()" in ai_src,
		"missing CONFIRM_FORMATIONS retry in failure path")
	_check("AIPlayer failure path handles DESIGNATE_WARLORD",
		'"DESIGNATE_WARLORD"' in ai_src)

	_finish()


func _finish() -> void:
	print("\n=== Summary: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

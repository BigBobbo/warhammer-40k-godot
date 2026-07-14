extends SceneTree

# Integration regression for the reported Fight-phase bug:
#   "Playing Orks vs the AI's Custodes, the game popped up the 'who do you want
#    to allocate the Custodes' models' attacks to' dialog for ME (the human)."
#
# This drives the REAL FightController inside the live scene tree (so
# get_node_or_null("/root/AIPlayer") resolves and the real dialog-gate branch
# runs) with the real autoloads, and asserts that when the AI's unit is the
# active fighter, _on_attack_assignment_required takes the "Skipping dialog for
# AI player" branch and creates NO AttackAssignmentDialog node.
#
# Root cause / fix: current_fighter_owner was only refreshed in the human dialog
# paths, so after a human unit fought it stayed on the human's player number;
# _on_fighter_selected (which fires for every selection, including AI ones) now
# refreshes it from the selected unit's owner, so the is_ai_player() gate is
# correct for the AI's fighters.
#
# Headless is sufficient here: the bug's effect is whether a dialog NODE is
# created in the tree, which needs no GPU. (The full windowed UI cannot be
# exercised in the sandbox — sustained GL/X11 rendering is terminated — so the
# node-level assertion is the reproducible proof of the player-facing effect.)
#
# Usage: godot --headless --path 40k -s tests/integration/test_fight_ai_attack_dialog_suppressed.gd

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
	create_timer(0.1).timeout.connect(_run)

func _count_attack_dialogs() -> int:
	var n := 0
	for c in root.get_children():
		if c is AcceptDialog and str(c.name).begins_with("AttackAssignmentDialog"):
			n += 1
	return n

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_fight_ai_attack_dialog_suppressed ===\n")
	var gs = root.get_node_or_null("GameState")
	var ai = root.get_node_or_null("AIPlayer")
	if gs == null or ai == null:
		_check("autoloads present", false, "gs=%s ai=%s" % [gs, ai]); _finish(); return

	var prev_enabled = ai.enabled
	var prev_players = ai.ai_players.duplicate(true)
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}  # P1 human (Orks), P2 AI (Custodes)

	gs.state["units"] = {
		"U_ORK": {"id": "U_ORK", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Ork Boyz", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 500, "y": 500}}]},
		"U_CUST": {"id": "U_CUST", "owner": 2, "status": 2, "flags": {"charged_this_turn": true},
			"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 3}},
			"models": [{"id": "e0", "alive": true, "wounds": 3, "current_wounds": 3, "base_mm": 40, "base_type": "circular", "position": {"x": 548, "y": 500}}]},
	}
	gs.state["meta"]["active_player"] = 2

	var FC = load("res://scripts/FightController.gd")
	var fc = FC.new()
	fc.name = "TestFightController"
	root.add_child(fc)

	# The human's Ork unit fights first — the human dialog gate is correct here.
	# (We do NOT trigger the human attack-assignment dialog: its own 0.3s timer
	# would create a dialog later and pollute the AI dialog count below.)
	fc._on_fighter_selected("U_ORK")
	_check("owner is P1 while the human's Ork unit is the fighter",
		fc.current_fighter_owner == 1, "got %d" % fc.current_fighter_owner)

	# The AI's Custodes unit fights next. This is the reported bug: pre-fix the
	# owner stayed on P1, so this handler built the dialog for the human.
	fc._on_fighter_selected("U_CUST")
	_check("FIX: owner switches to the AI (P2) for the Custodes fighter",
		fc.current_fighter_owner == 2, "got %d" % fc.current_fighter_owner)

	var ai_before := _count_attack_dialogs()
	fc._on_attack_assignment_required("U_CUST", {})
	# Wait past the human path's 0.3s pre-dialog timer: with the fix the AI
	# branch returns synchronously and never schedules a dialog, so nothing is
	# created even after the wait. Without the fix the stale human owner would
	# fall through and (attempt to) build the dialog here.
	await create_timer(0.5).timeout
	_check("FIX: NO AttackAssignmentDialog is created for the AI's Custodes attacks",
		_count_attack_dialogs() == ai_before,
		"dialogs now=%d (was %d)" % [_count_attack_dialogs(), ai_before])

	fc.queue_free()
	ai.enabled = prev_enabled
	ai.ai_players = prev_players
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

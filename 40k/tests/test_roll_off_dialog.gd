extends SceneTree

# Validates the dramatic RollOffDialog: dice render with the rolled values,
# the animation settles into the correct mode, the winner is highlighted, and
# the winner is offered the deploy-order choice. Tie shows a Re-roll button.
#
# Usage: godot --headless --path . -s tests/test_roll_off_dialog.gd

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
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_roll_off_dialog ===\n")

	var dialog_script = load("res://dialogs/RollOffDialog.gd")
	_check("RollOffDialog.gd loads (parses)", dialog_script != null)
	if dialog_script == null:
		_finish()
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	root.add_child(dialog)
	dialog.setup(1)  # local player = 1

	# Awaiting-roll state exposes the Roll button.
	_check("RollButton present before rolling",
		dialog.find_child("RollButton", true, false) != null)

	# --- P1 wins 5 vs 3 -----------------------------------------------------
	dialog.show_result(5, 3, 1)
	await create_timer(1.4).timeout

	_check("After settle: P1 die shows 5",
		dialog._p1_die.value == 5, "value=%d" % dialog._p1_die.value)
	_check("After settle: P2 die shows 3",
		dialog._p2_die.value == 3, "value=%d" % dialog._p2_die.value)
	_check("Winner die (P1) highlighted as WINNER",
		dialog._p1_die.highlight == dialog._p1_die.Highlight.WINNER)
	_check("Loser die (P2) highlighted as LOSER",
		dialog._p2_die.highlight == dialog._p2_die.Highlight.LOSER)
	_check("Local winner offered Deploy First",
		dialog.find_child("DeployFirstButton", true, false) != null)
	_check("Local winner offered Go First (attacker)",
		dialog.find_child("DeploySecondButton", true, false) != null)

	# choice_made('first') must be emitted when "Go first (Attacker)" pressed.
	var got_choice := {"v": ""}
	dialog.choice_made.connect(func(c): got_choice.v = c)
	dialog.find_child("DeploySecondButton", true, false).emit_signal("pressed")
	_check("Go-first button emits choice_made('first')",
		got_choice.v == "first", "got=%s" % got_choice.v)

	# --- Tie 4 vs 4 ---------------------------------------------------------
	dialog.show_tie(4, 4)
	await create_timer(1.4).timeout
	_check("Tie: both dice show 4",
		dialog._p1_die.value == 4 and dialog._p2_die.value == 4)
	_check("Tie: Re-roll button present",
		dialog.find_child("RerollButton", true, false) != null)
	_check("Tie: dice highlighted as TIE",
		dialog._p1_die.highlight == dialog._p1_die.Highlight.TIE)

	dialog.queue_free()
	_finish()

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

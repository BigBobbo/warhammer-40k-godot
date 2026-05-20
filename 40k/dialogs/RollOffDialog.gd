extends AcceptDialog

# RollOffDialog - UI for the pre-deployment roll-off (issue #85)
#
# 10th edition: BEFORE deployment, both players roll a D6. The winner
# chooses to be the Attacker or the Defender:
#   - Defender deploys first (and takes the second turn)
#   - Attacker deploys second (and takes the first turn)
#
# This dialog presents both rolls and (for the winner only) two
# buttons: "Deploy First" and "Deploy Second". Wins emits
# `choice_made` with the action payload the host session dispatches.
#
# When the roll ties, the dialog shows the tied rolls and a single
# "Re-roll" button — the next ROLL_FOR_FIRST_TURN action is dispatched
# with no `dice_roll` override so the engine re-rolls.

signal roll_initiated()
signal choice_made(choice: String)  # "first" (deploy second) or "second" (deploy first)
signal reroll_requested()

enum Mode {
	AWAITING_ROLL,
	SHOWING_RESULT,
	SHOWING_TIE,
}

var _mode: int = Mode.AWAITING_ROLL
var _winner: int = 0
var _local_player: int = 0
var _p1_roll: int = 0
var _p2_roll: int = 0

# UI references built in _build_ui()
var _content_vbox: VBoxContainer
var _status_label: Label
var _result_label: RichTextLabel
var _button_bar: HBoxContainer


func _init() -> void:
	WhiteDwarfTheme.apply_to_dialog(self)


func setup(local_player: int) -> void:
	_local_player = local_player
	title = "Pre-deployment Roll-off"
	min_size = DialogConstants.SMALL
	get_ok_button().visible = false
	if not close_requested.is_connected(_on_close_requested):
		close_requested.connect(_on_close_requested)
	_build_ui()
	_refresh_for_mode()


func show_awaiting() -> void:
	_mode = Mode.AWAITING_ROLL
	_refresh_for_mode()


func show_result(p1_roll: int, p2_roll: int, winner: int) -> void:
	_p1_roll = p1_roll
	_p2_roll = p2_roll
	_winner = winner
	_mode = Mode.SHOWING_RESULT
	_refresh_for_mode()


func show_tie(p1_roll: int, p2_roll: int) -> void:
	_p1_roll = p1_roll
	_p2_roll = p2_roll
	_mode = Mode.SHOWING_TIE
	_refresh_for_mode()


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 12)
	add_child(_content_vbox)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_vbox.add_child(_status_label)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(WhiteDwarfTheme.WH_GOLD.r,
		WhiteDwarfTheme.WH_GOLD.g, WhiteDwarfTheme.WH_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_child(sep)

	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 40, 80)
	_content_vbox.add_child(_result_label)

	_button_bar = HBoxContainer.new()
	_button_bar.alignment = BoxContainer.ALIGNMENT_END
	_button_bar.add_theme_constant_override("separation", 12)
	_content_vbox.add_child(_button_bar)


func _refresh_for_mode() -> void:
	if _button_bar == null:
		return
	for child in _button_bar.get_children():
		child.queue_free()

	match _mode:
		Mode.AWAITING_ROLL:
			_status_label.text = "Both players roll a D6 to decide who deploys first."
			_result_label.text = "[i]The winner chooses to be Attacker or Defender:[/i]\n" + \
				"  • [b]Defender[/b] deploys first, takes the second turn\n" + \
				"  • [b]Attacker[/b] deploys second, takes the first turn"
			var roll_button := Button.new()
			roll_button.name = "RollButton"
			roll_button.text = "Roll for first turn"
			roll_button.pressed.connect(_on_roll_pressed)
			WhiteDwarfTheme.apply_primary_button(roll_button)
			_button_bar.add_child(roll_button)
		Mode.SHOWING_RESULT:
			_status_label.text = "Roll result"
			var p1_marker := " " if _p1_roll < _p2_roll else "✓"
			var p2_marker := " " if _p2_roll < _p1_roll else "✓"
			_result_label.text = (
				"[b]Player 1[/b] rolled [b]%d[/b] %s\n" % [_p1_roll, p1_marker] +
				"[b]Player 2[/b] rolled [b]%d[/b] %s\n" % [_p2_roll, p2_marker] +
				"\n[color=#D49761][b]Player %d wins the roll-off.[/b][/color]" % _winner
			)
			if _winner == _local_player:
				var first_button := Button.new()
				first_button.name = "DeployFirstButton"
				first_button.text = "Deploy first (Defender)"
				first_button.pressed.connect(_on_deploy_first_pressed)
				WhiteDwarfTheme.apply_primary_button(first_button)
				_button_bar.add_child(first_button)

				var second_button := Button.new()
				second_button.name = "DeploySecondButton"
				second_button.text = "Deploy second (Attacker)"
				second_button.pressed.connect(_on_deploy_second_pressed)
				WhiteDwarfTheme.apply_secondary_button(second_button)
				_button_bar.add_child(second_button)
			else:
				var waiting := Label.new()
				waiting.text = "Waiting for Player %d to choose..." % _winner
				waiting.add_theme_color_override("font_color",
					WhiteDwarfTheme.WH_BONE)
				_button_bar.add_child(waiting)
		Mode.SHOWING_TIE:
			_status_label.text = "Roll-off tied — must re-roll."
			_result_label.text = "[b]Player 1[/b] rolled [b]%d[/b]\n" % _p1_roll + \
				"[b]Player 2[/b] rolled [b]%d[/b]\n" % _p2_roll + \
				"\n[color=#9A1115][b]TIED at %d — re-roll required.[/b][/color]" % _p1_roll
			var reroll_button := Button.new()
			reroll_button.name = "RerollButton"
			reroll_button.text = "Re-roll"
			reroll_button.pressed.connect(_on_reroll_pressed)
			WhiteDwarfTheme.apply_primary_button(reroll_button)
			_button_bar.add_child(reroll_button)


# --- Signal handlers ---------------------------------------------------------

func _on_roll_pressed() -> void:
	emit_signal("roll_initiated")


func _on_deploy_first_pressed() -> void:
	# "Deploy first" = defender = CHOOSE_TURN_ORDER choice "second" (go
	# second in turn order). Map to the action contract the phase expects.
	emit_signal("choice_made", "second")


func _on_deploy_second_pressed() -> void:
	# "Deploy second" = attacker = CHOOSE_TURN_ORDER choice "first" (go
	# first in turn order).
	emit_signal("choice_made", "first")


func _on_reroll_pressed() -> void:
	emit_signal("reroll_requested")


func _on_close_requested() -> void:
	# Ignore close attempts — the roll-off must complete to proceed.
	pass

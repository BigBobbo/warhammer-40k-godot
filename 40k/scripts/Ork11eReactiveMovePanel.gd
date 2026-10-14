extends AcceptDialog

## Ork11eReactiveMovePanel — the human's controls for a reactive move that a
## Codex: Orks (11e) stratagem grants mid-Shooting phase (design §3.2):
##   GRAB IT            — normal move of up to 6", must end within range of an objective
##   GOADED INTO ACTION — surge move of up to D6" toward the closest enemy unit
##                        (riled up: one re-roll of the D6)
## ShootingPhase owns the move (ORK11E_REACTIVE_MOVE_* actions, validated by
## ReactiveMove11e); ShootingController creates this panel when the phase emits
## ork11e_reactive_move_started and routes board drags (drag the unit, or click
## where its centre should go) as ORK11E_REACTIVE_MOVE_STAGE. The panel is not
## exclusive, so the board stays usable behind it.
##
## Stable node paths (windowed scenarios):
##   /root/Ork11eReactiveMovePanel/Content/Header | Rule | Status
##   /root/Ork11eReactiveMovePanel/Content/Buttons/AutoButton | RerollButton |
##     ResetButton | SkipButton | ConfirmButton

var info: Dictionary = {}
var controller = null  # ShootingController (dispatches the actions)

var _header: Label
var _rule: Label
var _status: Label
var _auto: Button
var _reroll: Button
var _reset: Button
var _skip: Button
var _confirm: Button


func setup(p_info: Dictionary, p_controller) -> void:
	info = p_info
	controller = p_controller
	WhiteDwarfTheme.apply_to_dialog(self)
	title = "%s — Player %d" % [str(info.get("source", "Move")), int(info.get("player", 0))]
	exclusive = false
	get_ok_button().visible = false
	close_requested.connect(_on_close_requested)
	_build()
	refresh(info)


func _build() -> void:
	var content = VBoxContainer.new()
	content.name = "Content"
	content.custom_minimum_size = Vector2(620, 0)
	content.add_theme_constant_override("separation", 6)

	_header = Label.new()
	_header.name = "Header"
	_header.add_theme_font_size_override("font_size", 21)
	_header.add_theme_color_override("font_color", Color.YELLOW)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_header)

	_rule = Label.new()
	_rule.name = "Rule"
	_rule.add_theme_font_size_override("font_size", 16)
	_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_rule)

	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_font_size_override("font_size", 17)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)

	var buttons = HFlowContainer.new()
	buttons.name = "Buttons"
	_auto = _make_button(buttons, "AutoButton", "Auto-move", "ORK11E_REACTIVE_MOVE_AUTO")
	_reroll = _make_button(buttons, "RerollButton", "Re-roll D6", "ORK11E_REACTIVE_MOVE_REROLL")
	_reset = _make_button(buttons, "ResetButton", "Reset", "ORK11E_REACTIVE_MOVE_RESET")
	_skip = _make_button(buttons, "SkipButton", "Don't move", "ORK11E_REACTIVE_MOVE_SKIP")
	_confirm = _make_button(buttons, "ConfirmButton", "Confirm move", "ORK11E_REACTIVE_MOVE_CONFIRM")
	content.add_child(buttons)
	add_child(content)


func _make_button(parent: Control, node_name: String, text: String, action_type: String) -> Button:
	var b = Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(110, 32)
	b.pressed.connect(_on_action_pressed.bind(action_type))
	parent.add_child(b)
	return b


## Re-render from the phase's move info (ork11e_reactive_move_info()).
func refresh(p_info: Dictionary) -> void:
	if p_info.is_empty():
		return
	info = p_info
	var kind := str(info.get("kind", "normal"))
	var unit_name := str(info.get("unit_name", info.get("unit_id", "")))
	var max_in := float(info.get("max_inches", 0.0))
	_header.text = "%s — %s" % [str(info.get("source", "")), unit_name]
	if kind == "surge":
		_rule.text = "Surge move of up to %d\" (D6 = %d) toward the closest enemy unit, %s: each model must end engaged with it if possible, otherwise as close as possible, and the unit cannot end engaged with any other enemy unit. Auto-move places the models; you can drag the unit to adjust, then Confirm." % [
			int(max_in), int(info.get("roll", 0)), str(info.get("surge_target_name", "?"))]
	else:
		var end_txt := " — it must end within range of an objective" if str(info.get("end_condition", "")) == "within_objective_range" else ""
		_rule.text = "Normal move of up to %.0f\"%s, ending unengaged and in coherency. Drag the unit on the board (or click where its centre should go), or use Auto-move, then Confirm." % [max_in, end_txt]
	var valid := bool(info.get("valid", false))
	var moved := float(info.get("moved_inches", 0.0))
	var violations: Array = info.get("violations", [])
	if valid:
		_status.text = "Moved %.1f\" of %.0f\" — legal: Confirm to finish the move." % [moved, max_in]
		_status.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	elif moved < 0.05 and not violations.has("the unit would not be in coherency"):
		# Nothing staged yet: a neutral hint, not a red rule violation for a
		# move the player has not made (LIVE-6). A unit that is out of
		# coherency before moving still sees that, as it decides the move.
		_status.text = "Not moved yet — use Auto-move or drag the unit, then Confirm (up to %.0f\")." % max_in
		_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	else:
		_status.text = "Moved %.1f\" of %.0f\" — %s" % [moved, max_in, "; ".join(violations) if not violations.is_empty() else "not legal yet"]
		_status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	_confirm.disabled = not valid
	_reroll.visible = kind == "surge"
	_reroll.disabled = not bool(info.get("reroll_available", false))


func _on_action_pressed(action_type: String) -> void:
	if controller and controller.has_method("ork11e_dispatch_reactive_move_action"):
		controller.ork11e_dispatch_reactive_move_action({"type": action_type, "player": int(info.get("player", 0))})


func _on_close_requested() -> void:
	# The move must be answered (Confirm / Don't move): keep the panel up.
	call_deferred("popup")

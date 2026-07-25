extends PanelContainer

# TM4 first-launch nudge (PRPs/tutorial_system.md §1 principle 3): offer the
# tutorial ONCE to a fresh profile, then never again. Modelled on Into the
# Breach — asked once, dismissible, never forced, and the Tutorial button on
# the menu remains the permanent way in.
#
# Deliberately a Control (not an AcceptDialog): every dialog in this game is an
# embedded Window, which swallows outside input and cannot be reached by
# synthetic clicks, so a Window here would be both modal-feeling on a menu and
# untestable. Sibling of TutorialPickerPanel, same node-naming discipline so
# windowed scenarios can address it.

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

var _start_button: Button
var _dismiss_button: Button
var _body_label: RichTextLabel


func _ready() -> void:
	name = "TutorialNudge"
	visible = false
	WhiteDwarfThemeData.apply_to_panel(self)
	custom_minimum_size = Vector2(560, 0)
	z_index = 95
	_build_ui()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "NudgeTitle"
	title.text = "First time 'ere?"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(title)

	_body_label = RichTextLabel.new()
	_body_label.name = "NudgeBody"
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.add_theme_font_size_override("normal_font_size", 14)
	_body_label.add_theme_font_size_override("bold_font_size", 14)
	_body_label.add_theme_color_override("default_color", WhiteDwarfThemeData.WH_PARCHMENT)
	vbox.add_child(_body_label)

	vbox.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_dismiss_button = Button.new()
	_dismiss_button.name = "DismissNudgeButton"
	_dismiss_button.text = "Not now"
	WhiteDwarfThemeData.apply_secondary_button(_dismiss_button)
	_dismiss_button.pressed.connect(_on_dismiss)
	footer.add_child(_dismiss_button)

	_start_button = Button.new()
	_start_button.name = "StartTrainingButton"
	_start_button.text = "Show me da ropes"
	WhiteDwarfThemeData.apply_primary_button(_start_button)
	_start_button.pressed.connect(_on_start)
	footer.add_child(_start_button)


func open() -> void:
	# Device-aware copy: the pad build says what a pad player will actually do.
	var idm := get_node_or_null("/root/InputDeviceManager")
	var pad: bool = idm != null and idm.has_method("is_pad_active") and idm.is_pad_active()
	var how := "Press [b]Show me da ropes[/b]" if not pad else "Pick [b]Show me da ropes[/b]"
	_body_label.text = ("You know da rules — dis is just about da buttons. [b]Basic Trainin'[/b] is seven " \
		+ "short lessons (about half an hour all in), an' ya can play any one on its own.\n\n" \
		+ how + ", or grab it later from [b]Tutorial[/b] on da menu.")
	visible = true
	_apply_center()
	call_deferred("_apply_center")
	if _start_button != null:
		_start_button.grab_focus()


func _apply_center() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


# Either button retires the nudge for good — being asked twice is the failure
# mode this is designed around.
func _mark_seen() -> void:
	var mgr := get_node_or_null("/root/TutorialManager")
	if mgr != null and mgr.has_method("note_nudge_shown"):
		mgr.note_nudge_shown()
	visible = false


func _on_dismiss() -> void:
	_mark_seen()


func _on_start() -> void:
	_mark_seen()
	var mgr := get_node_or_null("/root/TutorialManager")
	if mgr != null:
		mgr.start_full_course()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_mark_seen()
		get_viewport().set_input_as_handled()

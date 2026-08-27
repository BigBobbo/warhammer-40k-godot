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
const TutorialScriptLib = preload("res://scripts/tutorial/TutorialScript.gd")

const PANEL_W := 560.0

var _start_button: Button
var _dismiss_button: Button
var _body_label: RichTextLabel
var _title_label: Label
var _scrim: ColorRect


func _ready() -> void:
	name = "TutorialNudge"
	visible = false
	_apply_spotlight_style()
	custom_minimum_size = Vector2(PANEL_W, 0)
	z_index = 95
	_build_ui()
	# The scrim is a sibling (created deferred: the parent is still inside
	# add_child while our _ready runs, so adding another child now would fail).
	call_deferred("_ensure_scrim")
	visibility_changed.connect(_sync_scrim)
	tree_exiting.connect(_free_scrim)
	# Belt and braces for the runaway-height case documented in _build_ui:
	# whenever the panel's
	# own minimum size settles (fonts finishing, the body re-wrapping, a UI
	# scale change), re-centre off the NEW value instead of leaving stale
	# offsets behind.
	minimum_size_changed.connect(_on_min_size_changed)


# The shared create_panel_style() background is the EXACT same near-black as
# the main menu's $Background (both 0.1/0.09/0.07), so with only a 2px border
# the nudge read as an accidental stray rectangle floating over the menu form.
# Give it its own elevated look instead: a visibly lighter warm surface, a
# heavier gold frame, and a soft gold halo (a black drop shadow is invisible
# on a near-black menu — the glow is what sells "deliberate popup" here).
func _apply_spotlight_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.145, 0.10, 1.0)
	style.border_color = WhiteDwarfThemeData.WH_GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(WhiteDwarfThemeData.WH_GOLD, 0.28)
	style.shadow_size = 18
	add_theme_stylebox_override("panel", style)


# Full-screen dim behind the panel so the menu recedes while the nudge is up.
# Purely visual: MOUSE_FILTER_IGNORE keeps the deliberately-non-modal design
# intact (menu buttons stay clickable, synthetic test clicks still land) and
# visibility is slaved to the panel's, so every open/dismiss path stays in sync.
func _ensure_scrim() -> void:
	if _scrim != null or get_parent() == null:
		return
	_scrim = ColorRect.new()
	_scrim.name = "NudgeScrim"
	_scrim.color = Color(0, 0, 0, 0.55)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.z_index = z_index - 1
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = visible
	get_parent().add_child(_scrim)


func _sync_scrim() -> void:
	if _scrim != null:
		_scrim.visible = visible


func _free_scrim() -> void:
	if _scrim != null and is_instance_valid(_scrim):
		_scrim.queue_free()
		_scrim = null


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

	_title_label = Label.new()
	_title_label.name = "NudgeTitle"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(_title_label)

	_body_label = RichTextLabel.new()
	_body_label.name = "NudgeBody"
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	# A fit_content RichTextLabel reports its minimum HEIGHT as the content
	# height at its CURRENT width. Before the panel has ever been laid out that
	# width is ~0, so the body wraps one character per line and the panel's
	# combined minimum size comes back thousands of pixels tall — which
	# _apply_center() then bakes into the centering offsets (observed: a
	# 560x4324 panel parked at y=-1622, its buttons far off-screen, and its
	# mouse_filter=STOP swallowing every click in a 560px-wide strip of the
	# main menu, including part of the Tutorial button). Pinning the wrap width
	# to the panel's content box means the very first measurement is the right
	# one. PANEL_W minus the 18px margins on both sides.
	_body_label.custom_minimum_size = Vector2(PANEL_W - 36, 0)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("normal_font_size", 18)
	_body_label.add_theme_font_size_override("bold_font_size", 18)
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
	WhiteDwarfThemeData.apply_primary_button(_start_button)
	_start_button.pressed.connect(_on_start)
	footer.add_child(_start_button)


func open() -> void:
	_ensure_scrim()
	# Device-aware copy: the pad build says what a pad player will actually do.
	# Voice per the Tutorial Language setting, resolved at open() time.
	var idm := get_node_or_null("/root/InputDeviceManager")
	var pad: bool = idm != null and idm.has_method("is_pad_active") and idm.is_pad_active()
	if TutorialScriptLib.is_orky():
		_title_label.text = "First time 'ere?"
		_start_button.text = "Show me da ropes"
		var how := "Press [b]Show me da ropes[/b]" if not pad else "Pick [b]Show me da ropes[/b]"
		_body_label.text = ("You know da rules — dis is just about da buttons. [b]Basic Trainin'[/b] is seven " \
			+ "short lessons (about half an hour all in), an' ya can play any one on its own.\n\n" \
			+ how + ", or grab it later from [b]Tutorial[/b] on da menu.")
	else:
		_title_label.text = "First time here?"
		_start_button.text = "Show me the ropes"
		var how := "Press [b]Show me the ropes[/b]" if not pad else "Pick [b]Show me the ropes[/b]"
		_body_label.text = ("You know the rules — this is just about the buttons. [b]Basic Training[/b] is seven " \
			+ "short lessons (about half an hour all in), and you can play any one on its own.\n\n" \
			+ how + ", or find it later under [b]Tutorial[/b] on the menu.")
	visible = true
	_apply_center()
	call_deferred("_apply_center")
	if _start_button != null:
		_start_button.grab_focus()


func _apply_center() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _on_min_size_changed() -> void:
	if visible:
		call_deferred("_apply_center")


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

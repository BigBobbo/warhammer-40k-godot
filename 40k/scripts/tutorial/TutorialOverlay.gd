extends CanvasLayer

# Tutorial overlay (PRPs/tutorial_system.md §5.1): the instructor card + soft
# spotlight ring. CanvasLayer 93 — above PadActionBar (92), below VirtualCursor
# (95) so the pad cursor stays visible, below ToastManager (100).
#
# The overlay never consumes _input (the pad input chain order is load-bearing,
# PadRouter.gd:76-80); all its controls are plain buttons the mouse or the
# virtual cursor can click. Colors come from UIConstants / WhiteDwarfTheme —
# no new hex literals (design guidelines §9).

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")
const UIConstantsData = preload("res://autoloads/UIConstants.gd")
const AnchorResolverLib = preload("res://scripts/tutorial/AnchorResolver.gd")

const CARD_TOP_OFFSET := 96.0
const CARD_BOTTOM_OFFSET := 132.0  # keeps clear of the pad hint bar
const ANCHOR_RERESOLVE_S := 0.5

var _spotlight: Control
var _card: PanelContainer
var _instructor_chip: Label
var _bark_label: Label
var _body_text: RichTextLabel
var _hint_label: Label
var _progress_label: Label
var _continue_button: Button
var _skip_button: Button
var _exit_button: Button
var _next_button: Button
var _menu_button: Button

var _anchor_spec: Dictionary = {}
var _anchor_node: Node = null
var _anchor_rect: Rect2 = Rect2()
var _anchor_ok: bool = false
var _spotlight_mode: String = "none"
var _reresolve_accum: float = 0.0
var _card_at_bottom: bool = false
var _dim_strips: Array = []


func _ready() -> void:
	layer = 93
	_build()
	visible = false
	set_process(false)


func _mgr() -> Node:
	return get_node_or_null("/root/TutorialManager")


# ------------------------------------------------------------------ build ---

func _build() -> void:
	_spotlight = Control.new()
	_spotlight.name = "Spotlight"
	_spotlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spotlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_spotlight.draw.connect(_draw_spotlight)
	add_child(_spotlight)

	# Strict-mode dimmer: four ColorRect strips framing the anchor cutout.
	# mouse_filter STOP means stray pointer input outside the hole is
	# swallowed; input inside the hole passes to the game untouched
	# (PRPs/tutorial_system.md §4.3). Built BEFORE the card so the card
	# stays on top and clickable.
	for i in range(4):
		var strip := ColorRect.new()
		strip.name = "DimStrip%d" % i
		strip.color = Color(WhiteDwarfThemeData.WH_BLACK, 0.45)
		strip.mouse_filter = Control.MOUSE_FILTER_STOP
		strip.visible = false
		add_child(strip)
		_dim_strips.append(strip)

	_card = PanelContainer.new()
	_card.name = "InstructorCard"
	WhiteDwarfThemeData.apply_to_panel(_card)
	add_child(_card)

	# Stable node names throughout — windowed scenarios address these by path.
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	_instructor_chip = Label.new()
	_instructor_chip.name = "InstructorChip"
	_instructor_chip.text = "DA BOSS"
	_instructor_chip.add_theme_font_size_override("font_size", 12)
	_instructor_chip.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_BLACK)
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = WhiteDwarfThemeData.WH_GOLD
	chip_style.set_corner_radius_all(4)
	chip_style.content_margin_left = 8
	chip_style.content_margin_right = 8
	chip_style.content_margin_top = 2
	chip_style.content_margin_bottom = 2
	var chip_panel := PanelContainer.new()
	chip_panel.name = "ChipPanel"
	chip_panel.add_theme_stylebox_override("panel", chip_style)
	chip_panel.add_child(_instructor_chip)
	header.add_child(chip_panel)

	_bark_label = Label.new()
	_bark_label.name = "BarkLabel"
	_bark_label.add_theme_font_size_override("font_size", 17)
	_bark_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	_bark_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_bark_label)

	_body_text = RichTextLabel.new()
	_body_text.name = "BodyText"
	_body_text.bbcode_enabled = true
	_body_text.fit_content = true
	_body_text.scroll_active = false
	_body_text.custom_minimum_size = Vector2(560, 0)
	_body_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# >= 12px effective at 1280x800 (Steam Deck recommendation; PRP §4.3):
	# 15px at 1920x1080 canvas-items scaling ~= 10px physical on Deck before the
	# pad UI-scale boost (x1.2) SettingsService applies in pad mode.
	_body_text.add_theme_font_size_override("normal_font_size", 15)
	_body_text.add_theme_font_size_override("bold_font_size", 15)
	_body_text.add_theme_color_override("default_color", WhiteDwarfThemeData.WH_PARCHMENT)
	_body_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_body_text)

	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(560, 0)
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", UIConstantsData.MARGINAL_YELLOW)
	_hint_label.visible = false
	vbox.add_child(_hint_label)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)

	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.add_theme_color_override("font_color",
		Color(WhiteDwarfThemeData.WH_PARCHMENT, 0.6))
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_progress_label)

	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.text = "Continue"
	WhiteDwarfThemeData.apply_primary_button(_continue_button)
	_continue_button.pressed.connect(_on_continue_pressed)
	footer.add_child(_continue_button)

	_next_button = Button.new()
	_next_button.name = "NextLessonButton"
	_next_button.text = "Next Lesson"
	WhiteDwarfThemeData.apply_primary_button(_next_button)
	_next_button.visible = false
	_next_button.pressed.connect(func():
		_next_button.release_focus()
		var m := _mgr()
		if m: m.next_lesson())
	footer.add_child(_next_button)

	_menu_button = Button.new()
	_menu_button.name = "BackToMenuButton"
	_menu_button.text = "Back to Menu"
	WhiteDwarfThemeData.apply_secondary_button(_menu_button)
	_menu_button.visible = false
	_menu_button.pressed.connect(func():
		var m := _mgr()
		if m: m.exit_tutorial())
	footer.add_child(_menu_button)

	_skip_button = Button.new()
	_skip_button.name = "SkipStepButton"
	_skip_button.text = "Skip Step"
	WhiteDwarfThemeData.apply_secondary_button(_skip_button)
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.pressed.connect(func():
		var m := _mgr()
		if m: m.skip_step())
	footer.add_child(_skip_button)

	_exit_button = Button.new()
	_exit_button.name = "ExitTutorialButton"
	_exit_button.text = "Exit Tutorial"
	WhiteDwarfThemeData.apply_secondary_button(_exit_button)
	_exit_button.focus_mode = Control.FOCUS_NONE
	_exit_button.pressed.connect(func():
		var m := _mgr()
		if m: m.exit_tutorial())
	footer.add_child(_exit_button)

	_place_card(false)


func _place_card(at_bottom: bool) -> void:
	_card_at_bottom = at_bottom
	if at_bottom:
		_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
		_card.offset_bottom = -CARD_BOTTOM_OFFSET
		_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
		_card.offset_top = CARD_TOP_OFFSET
		_card.grow_vertical = Control.GROW_DIRECTION_END
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH


# ------------------------------------------------------------------- API ----

func show_step(view: Dictionary) -> void:
	visible = true
	set_process(true)
	_bark_label.text = str(view.get("bark", ""))
	_body_text.text = str(view.get("body", ""))
	_hint_label.visible = false
	_hint_label.text = ""
	_progress_label.text = str(view.get("progress", ""))
	_continue_button.visible = bool(view.get("ack", false))
	_next_button.visible = false
	_menu_button.visible = false
	_skip_button.visible = true
	_exit_button.visible = true
	_anchor_spec = view.get("anchor", {})
	_spotlight_mode = str(view.get("spotlight", "none"))
	_anchor_node = null
	_anchor_ok = false
	_reresolve_accum = ANCHOR_RERESOLVE_S  # resolve on next frame
	if _card_at_bottom:
		_place_card(false)
	var idm := get_node_or_null("/root/InputDeviceManager")
	if _continue_button.visible and idm != null and idm.is_pad_active():
		_continue_button.grab_focus()
	_spotlight.queue_redraw()


func show_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = true


func show_summary(view: Dictionary) -> void:
	visible = true
	set_process(true)
	_bark_label.text = str(view.get("bark", "PROPPA JOB!"))
	_body_text.text = str(view.get("body", ""))
	_hint_label.visible = false
	_progress_label.text = str(view.get("progress", ""))
	_continue_button.visible = false
	_skip_button.visible = false
	_exit_button.visible = false
	_next_button.visible = bool(view.get("has_next", false))
	_menu_button.visible = true
	_anchor_spec = {}
	_anchor_node = null
	_anchor_ok = false
	_spotlight_mode = "none"
	for strip in _dim_strips:
		strip.visible = false
	_place_card(false)
	var idm := get_node_or_null("/root/InputDeviceManager")
	if idm != null and idm.is_pad_active():
		if _next_button.visible:
			_next_button.grab_focus()
		else:
			_menu_button.grab_focus()
	_spotlight.queue_redraw()


func hide_all() -> void:
	visible = false
	set_process(false)
	_anchor_spec = {}
	_anchor_node = null
	_anchor_ok = false
	_spotlight_mode = "none"
	for strip in _dim_strips:
		strip.visible = false


func shake() -> void:
	if not visible:
		return
	var origin := _card.position
	var tween := create_tween()
	tween.tween_property(_card, "position:x", origin.x + 7.0, 0.05)
	tween.tween_property(_card, "position:x", origin.x - 7.0, 0.08)
	tween.tween_property(_card, "position:x", origin.x, 0.05)


# Exposed for windowed scenarios: what the player currently reads.
func current_body_text() -> String:
	return _body_text.text


func current_progress_text() -> String:
	return _progress_label.text


# --------------------------------------------------------------- process ----

func _process(delta: float) -> void:
	if _anchor_spec.is_empty():
		_anchor_ok = false
		_spotlight.queue_redraw()
		return
	_reresolve_accum += delta
	var node_valid: bool = _anchor_node != null and is_instance_valid(_anchor_node) \
		and (not (_anchor_node is CanvasItem) or (_anchor_node as CanvasItem).is_visible_in_tree())
	if node_valid:
		_anchor_rect = AnchorResolverLib.rect_for_node(_anchor_node, get_tree())
		_anchor_ok = _anchor_rect.size != Vector2.ZERO
	elif _reresolve_accum >= ANCHOR_RERESOLVE_S:
		_reresolve_accum = 0.0
		var res: Dictionary = AnchorResolverLib.resolve(_anchor_spec, get_tree())
		_anchor_ok = res.ok
		_anchor_node = res.node
		if res.ok:
			_anchor_rect = res.rect
	# Keep the card out of the way of what it points at (PRP §4.3).
	if _anchor_ok:
		var card_rect := _card.get_global_rect()
		if card_rect.grow(8).intersects(_anchor_rect) and not _card_at_bottom:
			_place_card(true)
		elif _card_at_bottom:
			var top_rect := Rect2(card_rect.position.x, CARD_TOP_OFFSET, card_rect.size.x, card_rect.size.y)
			if not top_rect.grow(8).intersects(_anchor_rect):
				_place_card(false)
	_update_dim_strips()
	_spotlight.queue_redraw()


func _update_dim_strips() -> void:
	var strict_on: bool = _spotlight_mode == "strict" and _anchor_ok
	for strip in _dim_strips:
		strip.visible = strict_on
	if not strict_on:
		return
	var vp := _spotlight.get_viewport_rect().size
	var hole := _anchor_rect.grow(10.0)
	# top / bottom / left / right frame around the hole
	_dim_strips[0].position = Vector2.ZERO
	_dim_strips[0].size = Vector2(vp.x, max(hole.position.y, 0.0))
	_dim_strips[1].position = Vector2(0, hole.end.y)
	_dim_strips[1].size = Vector2(vp.x, max(vp.y - hole.end.y, 0.0))
	_dim_strips[2].position = Vector2(0, max(hole.position.y, 0.0))
	_dim_strips[2].size = Vector2(max(hole.position.x, 0.0), hole.size.y)
	_dim_strips[3].position = Vector2(hole.end.x, max(hole.position.y, 0.0))
	_dim_strips[3].size = Vector2(max(vp.x - hole.end.x, 0.0), hole.size.y)


func _draw_spotlight() -> void:
	if not _anchor_ok or _spotlight_mode == "none":
		return
	# Soft ring (TM0 scope; "strict" renders the same ring until the dimmer
	# lands in TM1 — see PRPs/tutorial_system.md §6).
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * TAU / UIConstantsData.MOTION_PULSE_LOOP_S)
	var grow := 6.0 + 5.0 * pulse
	var color: Color = UIConstantsData.MARGINAL_YELLOW
	color.a = 0.45 + 0.4 * pulse
	_spotlight.draw_rect(_anchor_rect.grow(grow), color, false, 3.0)
	var inner: Color = UIConstantsData.MARGINAL_YELLOW
	inner.a = 0.18
	_spotlight.draw_rect(_anchor_rect.grow(2.0), inner, false, 1.5)


func _on_continue_pressed() -> void:
	_continue_button.release_focus()
	var m := _mgr()
	if m:
		m.ack()

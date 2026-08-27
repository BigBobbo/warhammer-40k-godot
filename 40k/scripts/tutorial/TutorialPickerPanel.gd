extends PanelContainer

# Lesson picker for the main menu (PRPs/tutorial_system.md §4.1): lists the
# Full Course plus each lesson with a completion checkmark, time estimate and
# a Start button. Pad-navigable (M0 pattern: focusable buttons + grab_focus on
# open; B/Esc closes via ui_cancel).

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")
const TutorialScriptLib = preload("res://scripts/tutorial/TutorialScript.gd")

var _rows_box: VBoxContainer
var _close_button: Button
var _first_play_button: Button = null
var _title_label: Label
var _subtitle_label: Label


const PANEL_W := 680.0

func _ready() -> void:
	name = "TutorialPicker"
	visible = false
	WhiteDwarfThemeData.apply_to_panel(self)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	custom_minimum_size = Vector2(PANEL_W, 0)
	z_index = 90
	_build_ui()
	# Same belt-and-braces as TutorialNudgePanel: whenever the panel's minimum
	# size settles (fonts, a language change re-wrapping the subtitle), re-centre
	# off the NEW value instead of leaving offsets baked from a stale one.
	minimum_size_changed.connect(_on_min_size_changed)


func _on_min_size_changed() -> void:
	if visible:
		call_deferred("_apply_center")


# Re-apply centered offsets AFTER the row list has rebuilt and layout has
# settled — applying the preset at open()-time uses the stale (pre-rebuild)
# minimum size and can park the panel off-screen once several lessons are
# installed.
func _apply_center() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _build_ui() -> void:
	# Stable node names — windowed scenarios address these by path.
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.name = "PickerTitle"
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Pin the wrap width (panel minus the 16px margins) so the very first
	# measurement after a text change is the right one. Unpinned, an autowrap
	# label mid-layout can report a one-word-per-line minimum height that
	# _apply_center() then bakes into the offsets — measured live: a 680x2395
	# picker parked at y=-657 with its Start buttons off the top of the screen,
	# the same runaway the nudge panel documents. The language toggle made this
	# reachable: setting a DIFFERENT subtitle on open() re-wraps, where the
	# fixed orky string used to early-return in set_text.
	_subtitle_label.custom_minimum_size = Vector2(PANEL_W - 32, 0)
	_subtitle_label.add_theme_font_size_override("font_size", 17)
	_subtitle_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	vbox.add_child(_subtitle_label)
	_apply_language_text()

	vbox.add_child(HSeparator.new())

	_rows_box = VBoxContainer.new()
	_rows_box.name = "LessonRows"
	_rows_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_rows_box)

	vbox.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_close_button = Button.new()
	_close_button.name = "ClosePickerButton"
	_close_button.text = "Close"
	WhiteDwarfThemeData.apply_secondary_button(_close_button)
	_close_button.pressed.connect(close)
	footer.add_child(_close_button)


# Header copy per the Tutorial Language setting — re-applied on every open()
# so a settings change lands without rebuilding the panel.
func _apply_language_text() -> void:
	if TutorialScriptLib.is_orky():
		_title_label.text = "Basic Trainin'"
		_subtitle_label.text = "You know da rules — learn da controls. Short lessons, replay any time."
	else:
		_title_label.text = "Basic Training"
		_subtitle_label.text = "You know the rules — learn the controls. Short lessons, replay any time."


func open() -> void:
	_apply_language_text()
	_rebuild_rows()
	visible = true
	call_deferred("_apply_center")
	if _first_play_button != null:
		_first_play_button.grab_focus()
	else:
		_close_button.grab_focus()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild_rows() -> void:
	for child in _rows_box.get_children():
		child.queue_free()
	_first_play_button = null

	var mgr := get_node_or_null("/root/TutorialManager")
	if mgr == null:
		return
	var lessons: Array = mgr.get_lessons()

	if lessons.size() > 1:
		_rows_box.add_child(_make_row(
			"full_course", "Full Course", "All lessons back-to-back, one battle",
			_course_minutes(lessons), false, func(): _launch(mgr, "", true)))

	for lesson in lessons:
		var lid := str(lesson.id)
		_rows_box.add_child(_make_row(
			lid, TutorialScriptLib.field(lesson, "title"),
			TutorialScriptLib.field(lesson, "subtitle"), int(lesson.est_minutes),
			mgr.is_completed(lid), func(): _launch(mgr, lid, false)))

	if lessons.is_empty():
		var empty := Label.new()
		empty.text = "No lessons installed."
		empty.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
		_rows_box.add_child(empty)


func _course_minutes(lessons: Array) -> int:
	var total := 0
	for l in lessons:
		total += int(l.est_minutes)
	return total


func _make_row(id: String, title: String, subtitle: String, minutes: int,
		completed: bool, on_play: Callable) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row_" + id
	row.add_theme_constant_override("separation", 10)

	var check := Label.new()
	check.text = "✓" if completed else "—"
	check.custom_minimum_size = Vector2(24, 0)
	check.add_theme_font_size_override("font_size", 20)
	check.add_theme_color_override("font_color",
		WhiteDwarfThemeData.WH_GOLD if completed else Color(WhiteDwarfThemeData.WH_PARCHMENT, 0.35))
	row.add_child(check)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 19)
	title_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	text_box.add_child(title_label)
	if subtitle != "":
		var sub_label := Label.new()
		sub_label.text = subtitle
		sub_label.add_theme_font_size_override("font_size", 16)
		sub_label.add_theme_color_override("font_color", Color(WhiteDwarfThemeData.WH_PARCHMENT, 0.6))
		text_box.add_child(sub_label)
	row.add_child(text_box)

	var est := Label.new()
	est.text = "≈%d min" % minutes
	est.add_theme_font_size_override("font_size", 16)
	est.add_theme_color_override("font_color", Color(WhiteDwarfThemeData.WH_PARCHMENT, 0.6))
	row.add_child(est)

	var play := Button.new()
	play.name = "Play_" + id
	play.text = "Start"
	WhiteDwarfThemeData.apply_primary_button(play)
	play.pressed.connect(on_play)
	row.add_child(play)
	if _first_play_button == null:
		_first_play_button = play

	return row


func _launch(mgr: Node, lesson_id: String, course: bool) -> void:
	close()
	if course:
		mgr.start_full_course()
	else:
		mgr.start_lesson(lesson_id)

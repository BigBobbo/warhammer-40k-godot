extends PanelContainer

# Lesson picker for the main menu (PRPs/tutorial_system.md §4.1): lists the
# Full Course plus each lesson with a completion checkmark, time estimate and
# a Start button. Pad-navigable (M0 pattern: focusable buttons + grab_focus on
# open; B/Esc closes via ui_cancel).

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

var _rows_box: VBoxContainer
var _close_button: Button
var _first_play_button: Button = null


func _ready() -> void:
	name = "TutorialPicker"
	visible = false
	WhiteDwarfThemeData.apply_to_panel(self)
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(680, 0)
	z_index = 90

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

	var title := Label.new()
	title.name = "PickerTitle"
	title.text = "Basic Trainin'"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "You know da rules — learn da controls. Short lessons, replay any time."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	vbox.add_child(subtitle)

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


func open() -> void:
	_rebuild_rows()
	visible = true
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
			lid, str(lesson.title), str(lesson.subtitle), int(lesson.est_minutes),
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
	check.add_theme_font_size_override("font_size", 16)
	check.add_theme_color_override("font_color",
		WhiteDwarfThemeData.WH_GOLD if completed else Color(WhiteDwarfThemeData.WH_PARCHMENT, 0.35))
	row.add_child(check)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	text_box.add_child(title_label)
	if subtitle != "":
		var sub_label := Label.new()
		sub_label.text = subtitle
		sub_label.add_theme_font_size_override("font_size", 12)
		sub_label.add_theme_color_override("font_color", Color(WhiteDwarfThemeData.WH_PARCHMENT, 0.6))
		text_box.add_child(sub_label)
	row.add_child(text_box)

	var est := Label.new()
	est.text = "≈%d min" % minutes
	est.add_theme_font_size_override("font_size", 12)
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

extends AcceptDialog
class_name FixedMissionSelectionDialog

# FixedMissionSelectionDialog - Allows a player to select 2 fixed secondary missions
# before the game starts. Fixed missions remain active the entire game and can be
# scored multiple times (up to 20VP per mission card).

const SecondaryMissionData = preload("res://scripts/data/SecondaryMissionData.gd")

signal missions_selected(player: int, mission_ids: Array)
signal selection_cancelled()

var _player: int = 0
var _selected_missions: Array = []  # Array of mission ID strings
var _mission_checkboxes: Dictionary = {}  # mission_id -> CheckBox
var _confirm_button: Button = null
var _status_label: Label = null

func setup(player: int) -> void:
	_player = player
	_selected_missions.clear()

	title = "Select Fixed Secondary Missions - Player %d" % player

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	# Connect close to cancel
	close_requested.connect(_on_cancel_pressed)

	_build_ui()

func _build_ui() -> void:
	min_size = Vector2(600, 520)

	var main_container = VBoxContainer.new()
	main_container.name = "MainContainer"
	main_container.custom_minimum_size = Vector2(580, 0)

	# Header
	var header = Label.new()
	header.text = "FIXED SECONDARY MISSIONS"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Instructions
	var instructions = Label.new()
	instructions.text = "Select exactly 2 secondary missions. These will remain active for the entire battle\nand can be scored multiple times (up to 20VP per mission)."
	instructions.add_theme_font_size_override("font_size", 11)
	instructions.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(instructions)

	main_container.add_child(HSeparator.new())

	# Scrollable mission list
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.add_child(scroll)

	var mission_list = VBoxContainer.new()
	mission_list.name = "MissionList"
	mission_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_list.add_theme_constant_override("separation", 4)
	scroll.add_child(mission_list)

	# Group missions by category
	var all_missions = SecondaryMissionData.get_all_missions()
	var categories = {}
	for mission_id in all_missions:
		var mission = all_missions[mission_id]
		var category = mission.get("category", "Other")
		if category not in categories:
			categories[category] = []
		categories[category].append(mission)

	# Sort categories alphabetically
	var sorted_categories = categories.keys()
	sorted_categories.sort()

	for category in sorted_categories:
		# Category header
		var cat_label = Label.new()
		cat_label.text = category
		cat_label.add_theme_font_size_override("font_size", 14)
		cat_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
		mission_list.add_child(cat_label)

		# Sort missions within category by number
		var missions = categories[category]
		missions.sort_custom(func(a, b): return a.get("number", 0) < b.get("number", 0))

		for mission in missions:
			_add_mission_row(mission_list, mission)

		mission_list.add_child(HSeparator.new())

	main_container.add_child(HSeparator.new())

	# Status label
	_status_label = Label.new()
	_status_label.text = "Select 2 missions (0/2 selected)"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(_status_label)

	# Button row
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 20)
	main_container.add_child(button_container)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 35)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	button_container.add_child(cancel_btn)

	_confirm_button = Button.new()
	_confirm_button.text = "Confirm Selection"
	_confirm_button.custom_minimum_size = Vector2(160, 35)
	_confirm_button.disabled = true
	_confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(_confirm_button)

	add_child(main_container)

func _add_mission_row(parent: VBoxContainer, mission: Dictionary) -> void:
	"""Add a mission with checkbox, name, and brief description."""
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var checkbox = CheckBox.new()
	checkbox.name = "Check_%s" % mission["id"]
	checkbox.toggled.connect(_on_mission_toggled.bind(mission["id"]))
	row.add_child(checkbox)
	_mission_checkboxes[mission["id"]] = checkbox

	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 0)
	row.add_child(info_vbox)

	# Mission name
	var name_label = Label.new()
	name_label.text = mission.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	info_vbox.add_child(name_label)

	# VP conditions (compact)
	var scoring = mission.get("scoring", {})
	var conditions = scoring.get("conditions", [])
	var vp_parts = []
	for c in conditions:
		vp_parts.append("%dVP" % c.get("vp", 0))
	var timing_text = _get_timing_display(scoring.get("when", ""))

	var detail_label = Label.new()
	detail_label.text = "%s  |  %s  |  %s" % [", ".join(vp_parts), timing_text, mission.get("description", "")]
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(detail_label)

func _on_mission_toggled(toggled_on: bool, mission_id: String) -> void:
	if toggled_on:
		if _selected_missions.size() >= 2:
			# Already have 2 selected - uncheck this one
			_mission_checkboxes[mission_id].set_pressed_no_signal(false)
			print("FixedMissionSelectionDialog: Cannot select more than 2 missions")
			return
		_selected_missions.append(mission_id)
	else:
		_selected_missions.erase(mission_id)

	_update_status()

func _update_status() -> void:
	var count = _selected_missions.size()
	if _status_label:
		if count == 2:
			var names = []
			for mid in _selected_missions:
				var m = SecondaryMissionData.get_mission_by_id(mid)
				names.append(m.get("name", mid))
			_status_label.text = "Ready: %s" % " + ".join(names)
			_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		else:
			_status_label.text = "Select 2 missions (%d/2 selected)" % count
			_status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))

	if _confirm_button:
		_confirm_button.disabled = (count != 2)

func _on_confirm_pressed() -> void:
	if _selected_missions.size() != 2:
		return
	print("FixedMissionSelectionDialog: Player %d selected fixed missions: %s" % [_player, str(_selected_missions)])
	emit_signal("missions_selected", _player, _selected_missions.duplicate())
	hide()
	queue_free()

func _on_cancel_pressed() -> void:
	print("FixedMissionSelectionDialog: Player %d cancelled fixed mission selection" % _player)
	emit_signal("selection_cancelled")
	hide()
	queue_free()

func _get_timing_display(timing: String) -> String:
	match timing:
		"end_of_your_turn":
			return "End of your turn"
		"end_of_either_turn":
			return "End of either turn"
		"end_of_opponent_turn":
			return "End of opponent's turn"
		"while_active":
			return "While active"
		_:
			return timing

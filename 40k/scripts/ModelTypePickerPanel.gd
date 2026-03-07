extends PanelContainer

# MA-15: Model type picker panel shown during deployment when a unit has
# multiple distinct model_types in its model_profiles.
# Allows the player to choose which model type to place next.

signal model_type_selected(type_key: String)

var type_buttons: Dictionary = {}  # type_key -> Button
var selected_type: String = ""
var _model_profiles: Dictionary = {}
var _btn_container: VBoxContainer

func _ready() -> void:
	# Style the panel
	WhiteDwarfTheme.apply_to_panel(self)

	# Use a CanvasLayer so the panel stays in screen space
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Title
	var title_label = Label.new()
	title_label.name = "Title"
	title_label.text = "Select Model Type"
	WhiteDwarfTheme.apply_to_label(title_label, true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Button container
	_btn_container = VBoxContainer.new()
	_btn_container.name = "ButtonContainer"
	_btn_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_btn_container)

func setup(model_profiles: Dictionary, models: Array, placed_indices: Array = []) -> void:
	_model_profiles = model_profiles

	# Clear existing buttons (guard against pre-_ready calls)
	if _btn_container:
		for child in _btn_container.get_children():
			child.queue_free()
	type_buttons.clear()
	selected_type = ""

	# Count unplaced models per type
	var type_counts = _count_unplaced_by_type(models, placed_indices)

	# Create a button for each type (preserve profile order)
	for type_key in model_profiles:
		var profile = model_profiles[type_key]
		var label_text = profile.get("label", type_key)
		var count = type_counts.get(type_key, 0)

		var btn = Button.new()
		btn.name = "Btn_" + type_key
		btn.text = "%s x%d" % [label_text, count]
		btn.disabled = count == 0
		btn.custom_minimum_size = Vector2(200, 0)
		WhiteDwarfTheme.apply_to_button(btn)
		btn.pressed.connect(_on_type_pressed.bind(type_key))

		type_buttons[type_key] = btn
		if _btn_container:
			_btn_container.add_child(btn)

	print("[ModelTypePickerPanel] setup complete: %d types" % model_profiles.size())

func update_counts(models: Array, placed_indices: Array) -> void:
	var type_counts = _count_unplaced_by_type(models, placed_indices)
	for type_key in type_buttons:
		var btn = type_buttons[type_key]
		var profile = _model_profiles.get(type_key, {})
		var label_text = profile.get("label", type_key)
		var count = type_counts.get(type_key, 0)
		btn.text = "%s x%d" % [label_text, count]
		btn.disabled = count == 0
	print("[ModelTypePickerPanel] counts updated: %s" % str(type_counts))

func highlight_selected(type_key: String) -> void:
	selected_type = type_key
	for key in type_buttons:
		var btn = type_buttons[key]
		if key == type_key and not btn.disabled:
			# Use pressed style for selected button
			var selected_style = StyleBoxFlat.new()
			selected_style.bg_color = WhiteDwarfTheme.WH_RED
			selected_style.border_color = WhiteDwarfTheme.WH_PARCHMENT
			selected_style.set_border_width_all(2)
			selected_style.set_corner_radius_all(3)
			selected_style.set_content_margin_all(8)
			btn.add_theme_stylebox_override("normal", selected_style)
		else:
			# Reset to default style
			if btn.disabled:
				btn.add_theme_stylebox_override("normal", WhiteDwarfTheme.create_button_disabled())
			else:
				btn.add_theme_stylebox_override("normal", WhiteDwarfTheme.create_button_normal())

func get_remaining_types(models: Array, placed_indices: Array) -> Array:
	var type_counts = _count_unplaced_by_type(models, placed_indices)
	var remaining = []
	for type_key in _model_profiles:
		if type_counts.get(type_key, 0) > 0:
			remaining.append(type_key)
	return remaining

func _count_unplaced_by_type(models: Array, placed_indices: Array) -> Dictionary:
	var counts = {}
	for i in range(models.size()):
		if i in placed_indices:
			continue
		var mt = models[i].get("model_type", "")
		if mt == "":
			continue
		counts[mt] = counts.get(mt, 0) + 1
	return counts

func _on_type_pressed(type_key: String) -> void:
	if type_buttons.has(type_key) and type_buttons[type_key].disabled:
		return
	print("[ModelTypePickerPanel] type selected: %s" % type_key)
	emit_signal("model_type_selected", type_key)

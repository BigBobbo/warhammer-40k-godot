extends PanelContainer
class_name UnitColorPickerPopup

# Popup color picker for changing a unit's token color in-game.
# Shows faction palette swatches in a grid with current color highlighted.

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

signal color_changed(unit_id: String, new_color: Color)

var _unit_id: String = ""
var _palette: Array = []


func setup(uid: String, popup_position: Vector2) -> void:
	_unit_id = uid
	name = "UnitColorPickerPopup"

	var unit = GameState.get_unit(uid)
	if unit.is_empty():
		queue_free()
		return

	var player = unit.get("owner", 1)
	var faction_name = GameState.state.get("factions", {}).get(str(player), {}).get("name", "")
	_palette = FactionPalettes.get_palette(faction_name)
	var current_color = GameState.get_unit_color(uid)

	# Style the panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	panel_style.border_color = WhiteDwarfThemeData.WH_GOLD
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", panel_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Choose Color"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(title)

	# Grid of color swatches
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	for color in _palette:
		var swatch = Button.new()
		swatch.custom_minimum_size = Vector2(28, 28)
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = color
		style_normal.corner_radius_top_left = 4
		style_normal.corner_radius_top_right = 4
		style_normal.corner_radius_bottom_left = 4
		style_normal.corner_radius_bottom_right = 4
		if current_color.is_equal_approx(color):
			style_normal.border_width_left = 2
			style_normal.border_width_right = 2
			style_normal.border_width_top = 2
			style_normal.border_width_bottom = 2
			style_normal.border_color = Color.WHITE
		swatch.add_theme_stylebox_override("normal", style_normal)
		swatch.add_theme_stylebox_override("hover", style_normal)
		swatch.add_theme_stylebox_override("pressed", style_normal)
		swatch.pressed.connect(_on_color_picked.bind(color))
		grid.add_child(swatch)

	# Position the popup
	position = popup_position
	z_index = 100

	# Close on click outside
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_color_picked(color: Color) -> void:
	GameState.set_unit_color(_unit_id, color)
	color_changed.emit(_unit_id, color)
	queue_free()


func _input(event: InputEvent) -> void:
	# Close popup on right-click or escape
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		# Close if clicking outside this popup
		if not get_global_rect().has_point(event.global_position):
			queue_free()

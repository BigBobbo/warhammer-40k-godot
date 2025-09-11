extends Node2D
class_name ObjectiveVisual

# ObjectiveVisual - Displays objective markers on the board with control indicators

var objective_data: Dictionary = {}
var control_indicator: Label
var objective_marker: Node2D
var base_circle: Line2D
var control_range_circle: Line2D

func setup(data: Dictionary) -> void:
	objective_data = data
	position = data.position
	name = data.id
	_create_visuals()
	
func _create_visuals() -> void:
	# Create objective marker container
	objective_marker = Node2D.new()
	objective_marker.name = "ObjectiveMarker"
	add_child(objective_marker)
	
	var radius_px = Measurement.mm_to_px(objective_data.radius_mm)
	
	# Base marker circle (40mm)
	base_circle = Line2D.new()
	base_circle.name = "BaseCircle"
	base_circle.width = 3.0
	base_circle.default_color = Color(0.7, 0.7, 0.7, 1.0)  # Gray
	base_circle.z_index = 1
	
	# Create circle points
	for i in range(33):
		var angle = i * TAU / 32
		base_circle.add_point(Vector2(cos(angle), sin(angle)) * radius_px)
	base_circle.closed = true
	objective_marker.add_child(base_circle)
	
	# Center cross marker
	var cross = Line2D.new()
	cross.name = "CenterCross"
	cross.width = 2.0
	cross.default_color = Color(0.6, 0.6, 0.6, 1.0)
	cross.add_point(Vector2(-radius_px * 0.5, 0))
	cross.add_point(Vector2(radius_px * 0.5, 0))
	objective_marker.add_child(cross)
	
	var cross2 = Line2D.new()
	cross2.name = "CenterCross2"
	cross2.width = 2.0
	cross2.default_color = Color(0.6, 0.6, 0.6, 1.0)
	cross2.add_point(Vector2(0, -radius_px * 0.5))
	cross2.add_point(Vector2(0, radius_px * 0.5))
	objective_marker.add_child(cross2)
	
	# Control range indicator (3" radius)
	control_range_circle = Line2D.new()
	control_range_circle.name = "ControlRange"
	control_range_circle.width = 2.0
	control_range_circle.default_color = Color(0.5, 0.5, 0.5, 0.4)  # Semi-transparent
	control_range_circle.z_index = 0
	
	var control_radius = Measurement.inches_to_px(3.0)
	for i in range(33):
		var angle = i * TAU / 32
		control_range_circle.add_point(Vector2(cos(angle), sin(angle)) * control_radius)
	control_range_circle.closed = true
	objective_marker.add_child(control_range_circle)
	
	# Control indicator label
	control_indicator = Label.new()
	control_indicator.name = "ControlIndicator"
	control_indicator.text = "Uncontrolled"
	control_indicator.add_theme_font_size_override("font_size", 12)
	control_indicator.position = Vector2(-40, -radius_px - 25)
	control_indicator.z_index = 10
	add_child(control_indicator)
	
	# Objective ID label
	var id_label = Label.new()
	id_label.name = "ObjectiveID"
	id_label.text = objective_data.id.replace("obj_", "").to_upper()
	id_label.add_theme_font_size_override("font_size", 10)
	id_label.position = Vector2(-15, -5)
	id_label.z_index = 10
	add_child(id_label)

func update_control(player: int) -> void:
	match player:
		0:
			control_indicator.text = "Contested"
			control_indicator.modulate = Color(1.0, 1.0, 0.5, 1.0)  # Yellow
			base_circle.default_color = Color(0.7, 0.7, 0.4, 1.0)  # Yellowish gray
			control_range_circle.default_color = Color(0.7, 0.7, 0.4, 0.4)
		1:
			control_indicator.text = "Player 1"
			control_indicator.modulate = Color(0.4, 0.6, 1.0, 1.0)  # Blue
			base_circle.default_color = Color(0.3, 0.5, 0.8, 1.0)  # Blue
			control_range_circle.default_color = Color(0.3, 0.5, 0.8, 0.4)
		2:
			control_indicator.text = "Player 2"
			control_indicator.modulate = Color(1.0, 0.4, 0.4, 1.0)  # Red
			base_circle.default_color = Color(0.8, 0.3, 0.3, 1.0)  # Red
			control_range_circle.default_color = Color(0.8, 0.3, 0.3, 0.4)
		_:
			control_indicator.text = "Uncontrolled"
			control_indicator.modulate = Color.WHITE
			base_circle.default_color = Color(0.7, 0.7, 0.7, 1.0)  # Gray
			control_range_circle.default_color = Color(0.5, 0.5, 0.5, 0.4)

func highlight(enabled: bool) -> void:
	if enabled:
		base_circle.width = 4.0
		control_range_circle.width = 3.0
		modulate.a = 1.0
	else:
		base_circle.width = 3.0
		control_range_circle.width = 2.0
		modulate.a = 0.9

func get_objective_id() -> String:
	return objective_data.get("id", "")

func get_position_inches() -> Vector2:
	return Vector2(
		Measurement.px_to_inches(position.x),
		Measurement.px_to_inches(position.y)
	)
extends Node2D
class_name ObjectiveVisual

# ObjectiveVisual - Displays objective markers on the board with control indicators
# Shows a single circle representing the full control range (3" + 20mm radius)

var objective_data: Dictionary = {}
var control_indicator: Label
var objective_marker: Node2D
var objective_circle: Line2D
var objective_polygon: Polygon2D

# Constants
const OBJECTIVE_RADIUS_INCHES = 3.78740157  # 3" + 20mm (0.78740157")

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
	
	# Calculate the full control radius (3" + 20mm)
	var control_radius = Measurement.inches_to_px(OBJECTIVE_RADIUS_INCHES)
	
	# Filled objective area for better visibility
	objective_polygon = Polygon2D.new()
	objective_polygon.name = "ObjectivePolygon"
	objective_polygon.color = Color(0.5, 0.5, 0.5, 0.25)  # Semi-transparent gray fill
	objective_polygon.z_index = 0
	
	# Create circle points for filled area
	var polygon_points = PackedVector2Array()
	for i in range(32):
		var angle = i * TAU / 32
		polygon_points.append(Vector2(cos(angle), sin(angle)) * control_radius)
	objective_polygon.polygon = polygon_points
	objective_marker.add_child(objective_polygon)
	
	# Objective circle outline
	objective_circle = Line2D.new()
	objective_circle.name = "ObjectiveCircle"
	objective_circle.width = 3.0
	objective_circle.default_color = Color(0.7, 0.7, 0.7, 1.0)  # Gray
	objective_circle.z_index = 1
	
	# Create circle points for outline
	for i in range(33):
		var angle = i * TAU / 32
		objective_circle.add_point(Vector2(cos(angle), sin(angle)) * control_radius)
	objective_circle.closed = true
	objective_marker.add_child(objective_circle)
	
	# Center marker - small cross to indicate exact center
	var center_marker = Line2D.new()
	center_marker.name = "CenterMarker"
	center_marker.width = 2.0
	center_marker.default_color = Color(0.6, 0.6, 0.6, 0.8)
	center_marker.z_index = 2
	var marker_size = 15.0  # Small cross at center
	center_marker.add_point(Vector2(-marker_size, 0))
	center_marker.add_point(Vector2(marker_size, 0))
	objective_marker.add_child(center_marker)
	
	var center_marker2 = Line2D.new()
	center_marker2.name = "CenterMarker2"
	center_marker2.width = 2.0
	center_marker2.default_color = Color(0.6, 0.6, 0.6, 0.8)
	center_marker2.z_index = 2
	center_marker2.add_point(Vector2(0, -marker_size))
	center_marker2.add_point(Vector2(0, marker_size))
	objective_marker.add_child(center_marker2)
	
	# Control indicator label
	control_indicator = Label.new()
	control_indicator.name = "ControlIndicator"
	control_indicator.text = "Uncontrolled"
	control_indicator.add_theme_font_size_override("font_size", 14)
	control_indicator.position = Vector2(-50, -control_radius - 30)
	control_indicator.z_index = 10
	add_child(control_indicator)
	
	# Objective ID label
	var id_label = Label.new()
	id_label.name = "ObjectiveID"
	id_label.text = objective_data.id.replace("obj_", "").to_upper()
	id_label.add_theme_font_size_override("font_size", 12)
	id_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	id_label.position = Vector2(-20, -8)
	id_label.z_index = 10
	add_child(id_label)

func update_control(player: int) -> void:
	match player:
		0:
			control_indicator.text = "Contested"
			control_indicator.modulate = Color(1.0, 1.0, 0.5, 1.0)  # Yellow
			objective_circle.default_color = Color(0.8, 0.8, 0.4, 1.0)  # Yellowish
			objective_polygon.color = Color(0.8, 0.8, 0.4, 0.25)  # Yellow fill
		1:
			control_indicator.text = "Player 1"
			control_indicator.modulate = Color(0.4, 0.6, 1.0, 1.0)  # Blue
			objective_circle.default_color = Color(0.3, 0.5, 0.9, 1.0)  # Blue
			objective_polygon.color = Color(0.3, 0.5, 0.9, 0.25)  # Blue fill
		2:
			control_indicator.text = "Player 2"
			control_indicator.modulate = Color(1.0, 0.4, 0.4, 1.0)  # Red
			objective_circle.default_color = Color(0.9, 0.3, 0.3, 1.0)  # Red
			objective_polygon.color = Color(0.9, 0.3, 0.3, 0.25)  # Red fill
		_:
			control_indicator.text = "Uncontrolled"
			control_indicator.modulate = Color.WHITE
			objective_circle.default_color = Color(0.7, 0.7, 0.7, 1.0)  # Gray
			objective_polygon.color = Color(0.5, 0.5, 0.5, 0.25)  # Gray fill

func highlight(enabled: bool) -> void:
	if enabled:
		objective_circle.width = 4.0
		modulate.a = 1.0
	else:
		objective_circle.width = 3.0
		modulate.a = 0.95

func get_objective_id() -> String:
	return objective_data.get("id", "")

func get_position_inches() -> Vector2:
	return Vector2(
		Measurement.px_to_inches(position.x),
		Measurement.px_to_inches(position.y)
	)

func get_control_radius_inches() -> float:
	return OBJECTIVE_RADIUS_INCHES
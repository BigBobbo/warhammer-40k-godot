extends Node2D
class_name ObjectiveVisual

# ObjectiveVisual - Displays objective markers on the board with control indicators
# Shows a single circle representing the full control range (3" + 20mm radius)
# Styled with parchment/bone tones for contrast against green felt board

var objective_data: Dictionary = {}
var control_indicator: Label
var objective_marker: Node2D
var objective_circle: Line2D
var objective_polygon: Polygon2D

# Constants
const OBJECTIVE_RADIUS_INCHES = 3.78740157  # 3" + 20mm (0.78740157")

# High-contrast color palette for objectives (visible against dark green board)
const OBJ_OUTLINE_COLOR = Color(1.0, 0.9, 0.6, 1.0)      # Bright gold outline
const OBJ_FILL_COLOR = Color(0.9, 0.85, 0.5, 0.45)       # Warm gold fill
const OBJ_CENTER_COLOR = Color(1.0, 0.95, 0.7, 1.0)      # Bright gold center marker
const OBJ_OUTER_GLOW_COLOR = Color(1.0, 0.9, 0.5, 0.2)   # Subtle outer glow

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

	# Outer glow ring for extra visibility
	var glow_ring = Polygon2D.new()
	glow_ring.name = "GlowRing"
	glow_ring.color = OBJ_OUTER_GLOW_COLOR
	glow_ring.z_index = -1
	var glow_points = PackedVector2Array()
	var glow_radius = control_radius + 6.0
	for i in range(32):
		var angle = i * TAU / 32
		glow_points.append(Vector2(cos(angle), sin(angle)) * glow_radius)
	glow_ring.polygon = glow_points
	objective_marker.add_child(glow_ring)

	# Filled objective area
	objective_polygon = Polygon2D.new()
	objective_polygon.name = "ObjectivePolygon"
	objective_polygon.color = OBJ_FILL_COLOR
	objective_polygon.z_index = 0

	# Create circle points for filled area
	var polygon_points = PackedVector2Array()
	for i in range(32):
		var angle = i * TAU / 32
		polygon_points.append(Vector2(cos(angle), sin(angle)) * control_radius)
	objective_polygon.polygon = polygon_points
	objective_marker.add_child(objective_polygon)

	# Objective circle outline - bright gold, thick
	objective_circle = Line2D.new()
	objective_circle.name = "ObjectiveCircle"
	objective_circle.width = 5.0
	objective_circle.default_color = OBJ_OUTLINE_COLOR
	objective_circle.z_index = 1

	# Create circle points for outline
	for i in range(33):
		var angle = i * TAU / 32
		objective_circle.add_point(Vector2(cos(angle), sin(angle)) * control_radius)
	objective_circle.closed = true
	objective_marker.add_child(objective_circle)

	# Center marker - larger cross to indicate exact center
	var marker_size = 22.0
	var center_marker = Line2D.new()
	center_marker.name = "CenterMarker"
	center_marker.width = 3.0
	center_marker.default_color = OBJ_CENTER_COLOR
	center_marker.z_index = 2
	center_marker.add_point(Vector2(-marker_size, 0))
	center_marker.add_point(Vector2(marker_size, 0))
	objective_marker.add_child(center_marker)

	var center_marker2 = Line2D.new()
	center_marker2.name = "CenterMarker2"
	center_marker2.width = 3.0
	center_marker2.default_color = OBJ_CENTER_COLOR
	center_marker2.z_index = 2
	center_marker2.add_point(Vector2(0, -marker_size))
	center_marker2.add_point(Vector2(0, marker_size))
	objective_marker.add_child(center_marker2)

	# Diagonal cross lines for extra visibility
	var diag_size = marker_size * 0.7
	var diag1 = Line2D.new()
	diag1.name = "DiagMarker1"
	diag1.width = 2.0
	diag1.default_color = Color(OBJ_CENTER_COLOR.r, OBJ_CENTER_COLOR.g, OBJ_CENTER_COLOR.b, 0.6)
	diag1.z_index = 2
	diag1.add_point(Vector2(-diag_size, -diag_size))
	diag1.add_point(Vector2(diag_size, diag_size))
	objective_marker.add_child(diag1)

	var diag2 = Line2D.new()
	diag2.name = "DiagMarker2"
	diag2.width = 2.0
	diag2.default_color = Color(OBJ_CENTER_COLOR.r, OBJ_CENTER_COLOR.g, OBJ_CENTER_COLOR.b, 0.6)
	diag2.z_index = 2
	diag2.add_point(Vector2(-diag_size, diag_size))
	diag2.add_point(Vector2(diag_size, -diag_size))
	objective_marker.add_child(diag2)

	# Control indicator label - larger and with outline for readability
	control_indicator = Label.new()
	control_indicator.name = "ControlIndicator"
	control_indicator.text = "Uncontrolled"
	control_indicator.add_theme_font_size_override("font_size", 16)
	control_indicator.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 1.0))
	control_indicator.add_theme_constant_override("outline_size", 3)
	control_indicator.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	control_indicator.position = Vector2(-55, -control_radius - 35)
	control_indicator.z_index = 10
	add_child(control_indicator)

	# Objective ID label - larger with outline
	var id_label = Label.new()
	id_label.name = "ObjectiveID"
	id_label.text = objective_data.id.replace("obj_", "").to_upper()
	id_label.add_theme_font_size_override("font_size", 15)
	id_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8, 1.0))
	id_label.add_theme_constant_override("outline_size", 3)
	id_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	id_label.position = Vector2(-25, -10)
	id_label.z_index = 10
	add_child(id_label)

func update_control(player: int) -> void:
	match player:
		0:
			control_indicator.text = "Contested"
			control_indicator.modulate = Color(1.0, 1.0, 0.5, 1.0)  # Yellow
			objective_circle.default_color = Color(1.0, 1.0, 0.4, 1.0)  # Bright yellow
			objective_polygon.color = Color(1.0, 1.0, 0.3, 0.4)  # Yellow fill
		1:
			control_indicator.text = "Player 1"
			control_indicator.modulate = Color(0.5, 0.7, 1.0, 1.0)  # Blue
			objective_circle.default_color = Color(0.4, 0.6, 1.0, 1.0)  # Bright blue
			objective_polygon.color = Color(0.3, 0.5, 1.0, 0.4)  # Blue fill
		2:
			control_indicator.text = "Player 2"
			control_indicator.modulate = Color(1.0, 0.4, 0.4, 1.0)  # Red
			objective_circle.default_color = Color(1.0, 0.3, 0.3, 1.0)  # Bright red
			objective_polygon.color = Color(1.0, 0.3, 0.3, 0.4)  # Red fill
		_:
			control_indicator.text = "Uncontrolled"
			control_indicator.modulate = Color.WHITE
			objective_circle.default_color = OBJ_OUTLINE_COLOR
			objective_polygon.color = OBJ_FILL_COLOR

func highlight(enabled: bool) -> void:
	if enabled:
		objective_circle.width = 7.0
		modulate.a = 1.0
	else:
		objective_circle.width = 5.0
		modulate.a = 1.0

func get_objective_id() -> String:
	return objective_data.get("id", "")

func get_position_inches() -> Vector2:
	return Vector2(
		Measurement.px_to_inches(position.x),
		Measurement.px_to_inches(position.y)
	)

func get_control_radius_inches() -> float:
	return OBJECTIVE_RADIUS_INCHES

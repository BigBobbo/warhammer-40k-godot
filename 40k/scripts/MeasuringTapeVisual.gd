extends Node2D

# MeasuringTapeVisual - Renders measurement lines with distance labels
# Shows persistent measurement lines that help players check distances
# Parchment/bone color scheme for White Dwarf battle report aesthetic

const LINE_COLOR = Color(1.0, 0.95, 0.8, 0.85)      # Parchment/bone
const PREVIEW_COLOR = Color(1.0, 0.85, 0.5, 0.5)     # Warm gold preview
const LINE_WIDTH = 2.0
const FONT_SIZE = 14
const LABEL_OFFSET = Vector2(10, -10)
const LABEL_BG_COLOR = Color(0.1, 0.08, 0.05, 0.85)  # Dark parchment
const LABEL_BG_PADDING = Vector2(4, 2)

var default_font: Font = null

func _ready() -> void:
	z_index = 15  # Above most game elements but below UI
	name = "MeasuringTapeVisual"

	# Create a basic font for labels
	# In Godot 4, we can use ThemeDB to get default font
	default_font = ThemeDB.fallback_font

	# Connect to manager signals
	if MeasuringTapeManager:
		MeasuringTapeManager.measurement_added.connect(_on_measurement_added)
		MeasuringTapeManager.measurements_cleared.connect(_on_measurements_cleared)

	print("[MeasuringTapeVisual] Initialized with z_index ", z_index)

func _draw() -> void:
	# Draw all stored measurements
	if MeasuringTapeManager:
		for measurement in MeasuringTapeManager.measurements:
			_draw_measurement(measurement, false)

		# Draw preview if measuring
		if MeasuringTapeManager.is_measuring and not MeasuringTapeManager.current_preview.is_empty():
			_draw_measurement(MeasuringTapeManager.current_preview, true)

func _draw_measurement(measurement: Dictionary, is_preview: bool = false) -> void:
	if not measurement.has("from") or not measurement.has("to"):
		return

	var color = PREVIEW_COLOR if is_preview else LINE_COLOR
	var width = LINE_WIDTH * 0.8 if is_preview else LINE_WIDTH

	var from_pos = measurement.from
	var to_pos = measurement.to
	var distance = measurement.get("distance", 0.0)

	# Draw the main line
	draw_line(from_pos, to_pos, color, width, true)

	# Draw endpoints
	draw_circle(from_pos, width * 2, color)
	draw_circle(to_pos, width * 2, color)

	# Draw arrowhead at the end
	_draw_arrowhead(from_pos, to_pos, color, width)

	# Draw distance label at midpoint
	if distance > 0.0:
		_draw_distance_label(from_pos, to_pos, distance, color)

	# Draw ruler ticks for non-preview lines
	if not is_preview and distance > 1.0:
		_draw_ruler_ticks(from_pos, to_pos, color, width)

func _draw_arrowhead(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var direction = (to - from).normalized()
	var arrow_size = 12.0
	var arrow_angle = 0.4

	var arrow_point1 = to - direction.rotated(arrow_angle) * arrow_size
	var arrow_point2 = to - direction.rotated(-arrow_angle) * arrow_size

	draw_line(to, arrow_point1, color, width, true)
	draw_line(to, arrow_point2, color, width, true)

func _draw_distance_label(from: Vector2, to: Vector2, distance: float, color: Color) -> void:
	var midpoint = (from + to) / 2
	var label_text = "%.1f\"" % distance

	# Calculate label position offset based on line angle
	var direction = (to - from).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)
	var label_pos = midpoint + perpendicular * 15

	if default_font:
		# Get text dimensions
		var text_size = default_font.get_string_size(
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT_SIZE
		)

		# Draw background rectangle
		var bg_rect = Rect2(
			label_pos - LABEL_BG_PADDING,
			text_size + LABEL_BG_PADDING * 2
		)
		draw_rect(bg_rect, LABEL_BG_COLOR, true)

		# Draw the text
		draw_string(
			default_font,
			label_pos,
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT_SIZE,
			color
		)

func _draw_ruler_ticks(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var direction = (to - from).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)
	var total_distance = from.distance_to(to)
	var inches = Measurement.px_to_inches(total_distance)

	# Draw tick marks at each inch
	for i in range(1, int(inches)):
		var tick_pos = from + direction * Measurement.inches_to_px(i)
		var tick_size = 8.0 if i % 6 == 0 else 5.0 if i % 3 == 0 else 3.0  # Longer ticks at 6" and 3"
		var tick_width = width * 0.5

		draw_line(
			tick_pos - perpendicular * tick_size,
			tick_pos + perpendicular * tick_size,
			color * 0.7,  # Slightly dimmer for ticks
			tick_width,
			true
		)

		# Add inch labels at major ticks (every 6 inches)
		if i % 6 == 0 and default_font:
			var tick_label = "%d\"" % i
			var label_offset = perpendicular * (tick_size + 10)
			draw_string(
				default_font,
				tick_pos + label_offset,
				tick_label,
				HORIZONTAL_ALIGNMENT_CENTER,
				-1,
				FONT_SIZE * 0.8,
				color * 0.7
			)

func _on_measurement_added(_measurement: Dictionary) -> void:
	queue_redraw()

func _on_measurements_cleared() -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	# Redraw if actively measuring to show preview
	if MeasuringTapeManager and MeasuringTapeManager.is_measuring:
		queue_redraw()

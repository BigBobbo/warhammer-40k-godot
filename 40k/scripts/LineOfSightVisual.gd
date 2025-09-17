extends Node2D

# LineOfSightVisual - Renders the Line of Sight visualization
# Shows which models can see the mouse cursor position when V key is held

# Visual settings
const TARGET_COLOR = Color(1.0, 1.0, 0.0, 0.8)  # Yellow for target position
const TARGET_RADIUS = 10.0
const LOS_LINE_COLOR = Color(0.0, 1.0, 0.0, 0.5)  # Semi-transparent green for LoS lines
const LOS_LINE_WIDTH = 2.0
const MODEL_HIGHLIGHT_COLOR = Color(0.0, 1.0, 0.0, 0.8)  # Bright green for models with LoS
const MODEL_HIGHLIGHT_WIDTH = 3.0
const FADE_DURATION = 0.2  # Seconds for fade in/out

# Optional grid visualization
const GRID_VISIBLE_COLOR = Color(0.0, 1.0, 0.0, 0.2)  # Very transparent green for visible areas
const SHOW_VISIBILITY_GRID = false  # Set to true to show grid of all positions that can see target

# State
var visible_models: Array = []  # Models that can see the target
var target_position: Vector2 = Vector2.ZERO  # Position being checked
var is_showing: bool = false
var fade_tween: Tween = null

func _ready() -> void:
	z_index = 14  # Above terrain (-8) and tokens (10), below measuring tape (15)
	name = "LineOfSightVisual"
	modulate.a = 0.0  # Start invisible

	# Connect to LineOfSightManager signals
	if LineOfSightManager:
		LineOfSightManager.los_visibility_changed.connect(_on_visibility_changed)
		LineOfSightManager.los_calculation_started.connect(_on_calculation_started)
		LineOfSightManager.los_calculation_ended.connect(_on_calculation_ended)
		LineOfSightManager.set_visual_node(self)

	print("[LineOfSightVisual] Initialized - Will show models that can see cursor position")

func _draw() -> void:
	if not is_showing or target_position == Vector2.ZERO:
		return

	# Draw target position indicator
	_draw_target_indicator()

	# Draw lines from models to target
	_draw_los_lines()

	# Highlight models that have LoS
	_draw_model_highlights()

	# Optional: Draw visibility grid
	if SHOW_VISIBILITY_GRID:
		_draw_visibility_grid()

func _draw_target_indicator() -> void:
	# Draw crosshair at target position (single point)
	var cross_size = 15.0
	draw_line(
		target_position - Vector2(cross_size, 0),
		target_position + Vector2(cross_size, 0),
		TARGET_COLOR,
		2.0
	)
	draw_line(
		target_position - Vector2(0, cross_size),
		target_position + Vector2(0, cross_size),
		TARGET_COLOR,
		2.0
	)

	# Draw small circle at center point
	draw_circle(target_position, 3.0, TARGET_COLOR)

	# Draw outer ring for visibility
	draw_arc(target_position, 8.0, 0, TAU, 16, TARGET_COLOR, 1.5)

func _draw_los_lines() -> void:
	# Draw lines from each model with LoS to the target
	for model_data in visible_models:
		var model_pos = model_data.position

		# Get the actual sight line points if available (from EnhancedLineOfSight)
		var sight_line = model_data.get("sight_line", [])
		var los_method = model_data.get("los_method", "unknown")

		# Draw the actual line of sight that was found
		if sight_line.size() >= 2:
			# Use actual sight line from enhanced checking (might be edge-to-edge)
			var from_point = sight_line[0]
			var to_point = sight_line[1]

			# Different colors for different LoS methods
			var line_color = LOS_LINE_COLOR
			if los_method == "edge_to_edge":
				line_color = Color(0.0, 0.8, 1.0, 0.5)  # Cyan for edge-to-edge

			draw_line(from_point, to_point, line_color, LOS_LINE_WIDTH)

			# Draw small indicators at the actual connection points
			draw_circle(from_point, 3.0, line_color)
			draw_circle(to_point, 2.0, line_color)

			# Draw arrow from actual sight line point
			_draw_arrow_at_model(from_point, to_point)
		else:
			# Fallback to simple center-to-center line
			draw_line(model_pos, target_position, LOS_LINE_COLOR, LOS_LINE_WIDTH)

			# Draw arrow from model center
			_draw_arrow_at_model(model_pos, target_position)

func _draw_arrow_at_model(model_pos: Vector2, target_pos: Vector2) -> void:
	# Draw a small arrow at the model pointing toward the target
	var direction = (target_pos - model_pos).normalized()
	var arrow_start = model_pos + direction * 30.0  # Start arrow 30px from model center
	var arrow_size = 10.0
	var arrow_angle = 0.4

	var arrow_point1 = arrow_start - direction.rotated(arrow_angle) * arrow_size
	var arrow_point2 = arrow_start - direction.rotated(-arrow_angle) * arrow_size

	draw_line(arrow_start, arrow_point1, LOS_LINE_COLOR, LOS_LINE_WIDTH)
	draw_line(arrow_start, arrow_point2, LOS_LINE_COLOR, LOS_LINE_WIDTH)

func _draw_model_highlights() -> void:
	# Highlight each model that has LoS
	for model_data in visible_models:
		var model_pos = model_data.position
		var radius = model_data.base_radius

		# Draw highlight ring around model
		draw_arc(model_pos, radius + 4, 0, TAU, 32, MODEL_HIGHLIGHT_COLOR, MODEL_HIGHLIGHT_WIDTH)

		# Draw player-colored inner ring
		var player_color = Color.BLUE if model_data.owner == 1 else Color.RED
		draw_arc(model_pos, radius + 2, 0, TAU, 32, player_color, 1.5)

		# Draw unit name label near the model
		if model_data.has("unit_name"):
			var font = ThemeDB.fallback_font
			var text = model_data.unit_name
			var text_pos = model_pos + Vector2(radius + 10, -5)

			# Draw background for text
			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var bg_rect = Rect2(text_pos - Vector2(2, text_size.y), text_size + Vector2(4, 4))
			draw_rect(bg_rect, Color(0, 0, 0, 0.7))

			# Draw text
			draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _draw_visibility_grid() -> void:
	# Optional: Draw a grid showing all positions that can see the target
	# This is computationally expensive, so it's off by default
	if not LineOfSightManager:
		return

	var grid = LineOfSightManager.calculate_visibility_grid_to_target(target_position)
	var grid_size = LineOfSightManager.grid_resolution

	for pos in grid:
		if grid[pos]:
			draw_rect(Rect2(pos, Vector2(grid_size, grid_size)), GRID_VISIBLE_COLOR)

func _on_visibility_changed(models: Array, target_pos: Vector2) -> void:
	visible_models = models
	target_position = target_pos

	if is_showing:
		queue_redraw()

	# Show count in console for debugging
	if visible_models.size() > 0:
		print("[LineOfSightVisual] ", visible_models.size(), " models can see position ", target_pos)

func _on_calculation_started() -> void:
	if not is_showing:
		is_showing = true
		_fade_in()

func _on_calculation_ended() -> void:
	if is_showing:
		is_showing = false
		visible_models.clear()
		target_position = Vector2.ZERO
		_fade_out()

func _fade_in() -> void:
	# Kill existing tween if any
	if fade_tween:
		fade_tween.kill()

	# Create new fade in tween
	fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION)
	fade_tween.tween_callback(func(): queue_redraw())

func _fade_out() -> void:
	# Kill existing tween if any
	if fade_tween:
		fade_tween.kill()

	# Create new fade out tween
	fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	fade_tween.tween_callback(func():
		queue_redraw()
		visible_models.clear()
		target_position = Vector2.ZERO
	)

# Helper function to get a summary of visibility
func get_visibility_summary() -> String:
	if visible_models.is_empty():
		return "No models have line of sight to this position"

	var summary = str(visible_models.size()) + " models can see this position:\n"
	var by_player = {1: [], 2: []}

	for model in visible_models:
		var owner = model.get("owner", 0)
		if owner in by_player:
			if not model.unit_name in by_player[owner]:
				by_player[owner].append(model.unit_name)

	for player in by_player:
		if by_player[player].size() > 0:
			summary += "Player " + str(player) + ": " + ", ".join(by_player[player]) + "\n"

	return summary
extends Node2D
## Dedicated board background renderer.
## Separated from BoardVisual so that a ShaderMaterial can be applied
## to the background without affecting borders, grid lines, or overlays.
## If the shader fails to compile, the plain draw_rect() still renders
## a solid green fallback — avoiding the blank-board bug from the
## previous ColorRect attempt.

var board_width: float = 1760.0
var board_height: float = 2400.0
var base_color: Color = Color(0.15, 0.35, 0.12, 1.0)

func setup(width: float, height: float) -> void:
	board_width = width
	board_height = height
	queue_redraw()

func apply_shader(shader: Shader, params: Dictionary = {}) -> void:
	var mat = ShaderMaterial.new()
	mat.shader = shader
	for key in params:
		mat.set_shader_parameter(key, params[key])
	material = mat
	queue_redraw()

func clear_shader() -> void:
	material = null
	queue_redraw()

func _draw() -> void:
	# Always draw the solid background rect — this is the fallback if the
	# shader is missing, fails to compile, or is deliberately cleared.
	draw_rect(Rect2(Vector2.ZERO, Vector2(board_width, board_height)), base_color)

extends Node2D

var board_width: float = 1760.0  # 44 inches
var board_height: float = 2400.0 # 60 inches

# Board surface style — swap shaders here to change the board look.
# Available: "grass", "felt", "none" (plain solid color)
var board_style: String = "grass"

var _background: Node2D = null

# Preload available board shaders
var _shaders: Dictionary = {
	"grass":  preload("res://shaders/grass_board.gdshader"),
	"mud":    preload("res://shaders/mud_board.gdshader"),
	"desert": preload("res://shaders/desert_board.gdshader"),
	"stone":  preload("res://shaders/stone_board.gdshader"),
	"felt":   preload("res://shaders/felt_texture.gdshader"),
}

# Preload grass textures for the texture-based grass shader
var _grass_basecolor: Texture2D = preload("res://textures/grass/Grass_08_basecolor.png")
var _grass_normal: Texture2D = preload("res://textures/grass/Grass_08_normal.png")

func _ready() -> void:
	z_index = -10
	board_width = SettingsService.get_board_width_px()
	board_height = SettingsService.get_board_height_px()
	# Use persisted board style from settings
	board_style = SettingsService.board_style
	_setup_background()
	# Listen for runtime board style changes from the settings menu
	SettingsService.board_style_changed.connect(_on_board_style_changed)

func _setup_background() -> void:
	var BoardBackground = preload("res://scripts/BoardBackground.gd")
	_background = BoardBackground.new()
	_background.name = "BoardBackground"
	_background.z_index = -1  # Behind borders & grid drawn by this node
	_background.setup(board_width, board_height)
	add_child(_background)
	set_board_style(board_style)

## Change the board surface at runtime.
## style: "grass", "felt", or "none"
func set_board_style(style: String) -> void:
	board_style = style
	if _background == null:
		return
	if style in _shaders:
		var params: Dictionary = {}
		if style == "grass":
			params["grass_texture"] = _grass_basecolor
			params["grass_normal"] = _grass_normal
		_background.apply_shader(_shaders[style], params)
		print("[BoardVisual] Board style set to: ", style)
	else:
		_background.clear_shader()
		print("[BoardVisual] Board style set to: none (solid color)")

func _draw() -> void:
	var board_rect = Rect2(Vector2.ZERO, Vector2(board_width, board_height))

	# Dark wood outer border
	draw_rect(board_rect, Color(0.35, 0.28, 0.15, 1.0), false, 4.0)

	# Inner gold accent border
	var inset_rect = Rect2(Vector2(4, 4), Vector2(board_width - 8, board_height - 8))
	draw_rect(inset_rect, Color(0.83, 0.59, 0.38, 0.6), false, 2.0)

	# Grid lines - muted green to complement felt
	var grid_color = Color(0.2, 0.45, 0.2, 0.2)
	var grid_spacing = Measurement.inches_to_px(6.0)

	var x = grid_spacing
	while x < board_width:
		draw_line(Vector2(x, 0), Vector2(x, board_height), grid_color, 1.0)
		x += grid_spacing

	var y = grid_spacing
	while y < board_height:
		draw_line(Vector2(0, y), Vector2(board_width, y), grid_color, 1.0)
		y += grid_spacing

func _on_board_style_changed(new_style: String) -> void:
	set_board_style(new_style)

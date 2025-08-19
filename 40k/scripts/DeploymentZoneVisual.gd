extends Polygon2D

var is_active: bool = false
var border_color: Color = Color.WHITE
var border_width: float = 3.0

func _ready() -> void:
	z_index = -5

func _draw() -> void:
	if not is_active:
		return
	
	# Draw border for active zone
	var points = polygon
	if points.size() < 2:
		return
	
	for i in range(points.size()):
		var p1 = points[i]
		var p2 = points[(i + 1) % points.size()]
		draw_line(p1, p2, border_color, border_width)

func set_active(active: bool) -> void:
	is_active = active
	queue_redraw()
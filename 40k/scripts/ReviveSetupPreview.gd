extends Node2D

## Board overlay for an auto-placed revive set-up (01.02.03), shown while the
## player confirms DELICIOUS EATING SQUIGS: one ring per revived model at the
## spot it will be set up, in board coordinates (lives in Main's GhostLayer).

const RING_COLOR := Color(0.35, 1.0, 0.45, 0.95)
const FILL_COLOR := Color(0.35, 1.0, 0.45, 0.25)

var markers: Array = []   # [{position: Vector2, radius: float}]


func set_markers(new_markers: Array) -> void:
	markers = new_markers
	z_index = 60
	queue_redraw()


func _draw() -> void:
	for mk in markers:
		var p: Vector2 = mk.get("position", Vector2.ZERO)
		var r: float = float(mk.get("radius", 20.0))
		draw_circle(p, r, FILL_COLOR)
		draw_arc(p, r, 0.0, TAU, 40, RING_COLOR, 3.0, true)
		draw_arc(p, r + 6.0, 0.0, TAU, 40, Color(RING_COLOR, 0.5), 2.0, true)

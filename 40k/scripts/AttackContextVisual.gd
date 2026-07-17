extends Node2D
class_name AttackContextVisual

## Board-space "who is attacking whom" context, shown while the defender
## resolves saves in AllocationGroupOverlay (shooting AND melee).
##
## Draws, in board coordinates:
##  - a pulsing red outline around every alive model of the ATTACKING unit,
##  - a steady gold outline around every alive model of the DEFENDING unit
##    (including attached-character models — callers pass the combined list),
##  - a dashed red arrow from the attacker's centroid to the defender's
##    centroid (skipped in base contact, where rings alone are clearer).
##
## Positions/radii arrive pre-converted to board px, so this script has NO
## autoload dependencies and keeps compiling in bare headless harness runs.

# White Dwarf palette (mirrors WhiteDwarfTheme / WoundAllocationBoardHighlights
# colors without importing them — parse-time isolation for headless runs).
const ATTACKER_COLOR := Color(0.85, 0.16, 0.16, 0.95)  # WH red — active threat
const TARGET_COLOR := Color(0.83, 0.59, 0.38, 0.95)    # WH gold — unit being hit
const RING_WIDTH := 3.0
const RING_GAP := 5.0          # px outside the base edge
const ARROW_HEAD_LEN := 16.0
const ARROW_MIN_DISTANCE := 60.0  # centroids closer than this (melee contact): no arrow

var attacker_marks: Array = []  # [{pos: Vector2, radius_px: float}, ...]
var target_marks: Array = []
var is_melee: bool = false

var _pulse_alpha: float = 1.0


func setup(p_attacker_marks: Array, p_target_marks: Array, p_is_melee: bool = false) -> void:
	attacker_marks = p_attacker_marks
	target_marks = p_target_marks
	is_melee = p_is_melee
	print("AttackContextVisual: setup — %d attacker mark(s), %d target mark(s), melee=%s" % [
		attacker_marks.size(), target_marks.size(), str(is_melee)])
	queue_redraw()


func _process(_delta: float) -> void:
	# Gentle ~1.5 Hz pulse so the attacker outline reads as the live threat.
	var t = Time.get_ticks_msec() / 1000.0
	_pulse_alpha = lerp(0.55, 1.0, (sin(t * 3.0) + 1.0) / 2.0)
	queue_redraw()


func _centroid(marks: Array) -> Vector2:
	if marks.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for m in marks:
		sum += m.pos
	return sum / marks.size()


func _draw() -> void:
	var attacker_color := ATTACKER_COLOR
	attacker_color.a *= _pulse_alpha
	for m in attacker_marks:
		draw_arc(m.pos, m.radius_px + RING_GAP, 0, TAU, 48, attacker_color, RING_WIDTH)
	for m in target_marks:
		draw_arc(m.pos, m.radius_px + RING_GAP, 0, TAU, 48, TARGET_COLOR, RING_WIDTH)

	if attacker_marks.is_empty() or target_marks.is_empty():
		return
	var from := _centroid(attacker_marks)
	var to := _centroid(target_marks)
	if from.distance_to(to) < ARROW_MIN_DISTANCE:
		return  # base contact (melee) — rings alone, an arrow would just clutter
	var dir := (to - from).normalized()
	# Pull the endpoints off the centroids so the arrow doesn't sit on bases.
	var start := from + dir * 24.0
	var head := to - dir * 24.0
	draw_dashed_line(start, head, attacker_color, RING_WIDTH, 14.0)
	draw_line(head, head + dir.rotated(PI * 0.86) * ARROW_HEAD_LEN, attacker_color, RING_WIDTH)
	draw_line(head, head + dir.rotated(-PI * 0.86) * ARROW_HEAD_LEN, attacker_color, RING_WIDTH)

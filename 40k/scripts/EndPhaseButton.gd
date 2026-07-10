extends Button

# T23/T27 — canonical End-Phase button (design guidelines §3/§4).
#
# One button, one position: every phase's "end phase" affordance is THIS
# node, anchored to the same bottom-right pixel offset in every phase.
# Phase panels must not ship their own end-phase controls.
#
# The reference offsets are measured from the viewport's bottom-right
# corner to this button's bottom-right corner, so t23_anchor_offset()
# returns (200, 60) exactly when the canonical placement is in effect.
# Scenarios T23_end_phase_position.json / T27_end_phase_refactor.json
# assert these values against live geometry — keep them in sync.

const REFERENCE_OFFSET_FROM_RIGHT := 200
const REFERENCE_OFFSET_FROM_BOTTOM := 60
const CANONICAL_SIZE := Vector2(200, 44)


# Anchor to the bottom-right corner at the canonical offset. Called from
# Main._restructure_ui_layout() after the button is reparented to Main.
func apply_canonical_placement() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_right = -REFERENCE_OFFSET_FROM_RIGHT
	offset_left = offset_right - CANONICAL_SIZE.x
	offset_bottom = -REFERENCE_OFFSET_FROM_BOTTOM
	offset_top = offset_bottom - CANONICAL_SIZE.y
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = CANONICAL_SIZE


# Live-geometry offset of this button's bottom-right corner from the
# viewport's bottom-right corner. Uses the rendered rect, not the
# configured offsets, so a mis-anchored button fails the assertion even
# if the constants above are correct.
func t23_anchor_offset() -> Vector2:
	var vp := get_viewport_rect().size
	var r := get_global_rect()
	return Vector2(vp.x - r.end.x, vp.y - r.end.y)

extends RefCounted
class_name PlacementClamp

## Keeps a placement point OUT of circular stand-off zones — the mirror image of
## the movement phase's over-range drag clamp
## (PhaseControllerBase.clamp_drag_to_budget).
##
## The drag clamp holds a model INSIDE a reach circle it must not leave. Deep
## Strike / Strategic Reserves / Rapid Ingress placement has the opposite
## problem: the model must stay OUTSIDE a 9" bubble around every enemy model,
## and landing the cursor exactly on that boundary by hand — especially with a
## thumbstick — is what players actually spend their time fighting. Given a
## cursor that has strayed inside, these helpers return the nearest point back
## outside, so the player aims roughly where they want and the model takes the
## closest legal spot.
##
## Geometry only. Whether the returned point is a LEGAL placement (board edge,
## Strategic-Reserves board-edge band, model overlap, walls) is the caller's
## business — see DeploymentController._clamped_placement_position, which
## re-runs the real validator on the result and falls back to the raw cursor
## whenever the pushed-out point would not actually be placeable. That gate is
## what makes the clamp safe: it can only ever change the outcome for a cursor
## position that is rejected today.

## One forbidden disc: the placed model's CENTRE may not enter it. `radius_px`
## already folds in the rule's stand-off plus both models' base radii, so the
## containment test is a plain centre-to-centre comparison — the same arithmetic
## the reinforcement validator does in inches.
static func make_bubble(center: Vector2, radius_px: float) -> Dictionary:
	return {"center": center, "radius_px": radius_px}


## How far (px) `pos` lies inside the deepest bubble it violates; 0.0 when the
## point is outside every bubble (touching a boundary exactly counts as outside,
## matching the validators' strict "< min distance" rejection).
static func penetration_px(pos: Vector2, bubbles: Array) -> float:
	var worst: float = 0.0
	for b in bubbles:
		var pen: float = float(b["radius_px"]) - pos.distance_to(b["center"])
		if pen > worst:
			worst = pen
	return worst


## How many boundary projections `escape` may take before giving up.
##
## One projection is enough for the common case (a single bubble, or several
## that do not overlap where the cursor is). Overlapping bubbles need more:
## pushing out of the deepest one can leave the point inside its neighbour, and
## the sequence then walks toward the corner where the two boundaries cross.
## That walk converges geometrically, so a handful of steps lands within a
## fraction of a pixel of the corner; the cap only exists so a pathological
## cluster cannot spin. A run that exhausts it returns a point that may still be
## inside a bubble — callers MUST re-check (see the class comment).
const MAX_ESCAPE_ITERATIONS: int = 16


## Nearest point to `pos` that is outside every bubble, pushed a further
## `margin_px` clear of the boundary it settles on.
##
## `margin_px` exists because the boundary is exactly the rejection threshold:
## a point landing mathematically ON the 9" ring is one float rounding away from
## measuring 8.999" and being rejected. A margin of a couple of pixels puts the
## model unambiguously outside at a distance no player can perceive.
static func escape(pos: Vector2, bubbles: Array, margin_px: float = 0.0, max_iterations: int = MAX_ESCAPE_ITERATIONS) -> Vector2:
	var p: Vector2 = pos
	for _iteration in range(max_iterations):
		# Always leave the bubble the point is deepest inside: that is the
		# constraint costing the most displacement, so resolving it first keeps
		# the walk heading for the nearest way out rather than shuffling along
		# whichever bubble happens to come first in the array.
		var worst_index: int = -1
		var worst_pen: float = 0.0
		for j in range(bubbles.size()):
			var b: Dictionary = bubbles[j]
			var pen: float = float(b["radius_px"]) + margin_px - p.distance_to(b["center"])
			if pen > worst_pen:
				worst_pen = pen
				worst_index = j
		if worst_index < 0:
			return p  # clear of everything

		var deepest: Dictionary = bubbles[worst_index]
		var center: Vector2 = deepest["center"]
		var dir: Vector2 = p - center
		if dir.length_squared() < 0.000001:
			# The point sits on the bubble's centre, so it has no direction of
			# its own to leave by. Use the direction the player originally
			# offered (their cursor), and only if that is the centre too — the
			# cursor is dead on an enemy model — fall back to an arbitrary ray.
			dir = pos - center
			if dir.length_squared() < 0.000001:
				dir = Vector2.UP
		p = center + dir.normalized() * (float(deepest["radius_px"]) + margin_px)
	return p

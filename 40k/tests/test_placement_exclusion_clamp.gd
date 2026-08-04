extends SceneTree

# Geometry tests for PlacementClamp — the Deep Strike / Reserves placement clamp
# that holds a drop OUTSIDE the 9" enemy exclusion bubbles (the inverse of the
# movement phase's over-range drag clamp, which holds a drag INSIDE its reach
# circle).
#
# Pure math, no window needed. The player-facing half — that the ghost, the
# click and the formation block all use this, and that the pushed-out point is
# re-validated before it is offered — is covered windowed by
# tests/scenarios/sp/deep_strike_exclusion_clamp.json.
#
# Usage: godot --headless --path 40k -s tests/test_placement_exclusion_clamp.gd

var passed := 0
var failed := 0

const PX_PER_INCH := 40.0
const MARGIN_PX := 2.0  # DeploymentController.EXCLUSION_CLAMP_MARGIN_INCHES * 40

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init() -> void:
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

var _ran := false

# A 9" stand-off bubble for a 32mm model placed near an enemy on a `base_mm` base
# — the same radius DeploymentController._placement_exclusion_bubbles builds.
func _bubble(x: float, y: float, base_mm: float = 32.0, standoff := 9.0) -> Dictionary:
	var model_r := (32.0 / 2.0) / 25.4
	var enemy_r := (base_mm / 2.0) / 25.4
	return PlacementClamp.make_bubble(Vector2(x, y), (standoff + model_r + enemy_r) * PX_PER_INCH)

func _edge_inches(p: Vector2, bubble: Dictionary) -> float:
	# How far outside the bubble's boundary `p` sits, in inches. 0 == exactly on
	# the 9" line; negative == illegal.
	return (p.distance_to(bubble["center"]) - float(bubble["radius_px"])) / PX_PER_INCH

func _run_tests() -> void:
	if _ran:
		return
	_ran = true
	print("\n=== PlacementClamp (Deep Strike exclusion clamp) ===\n")

	# ── Outside the zone: never touched ───────────────────────────────
	print("-- a legal aim is returned unchanged --")
	var one := [_bubble(600, 250, 100)]
	var far := Vector2(600, 1400)
	_check("penetration is 0 outside the bubble", PlacementClamp.penetration_px(far, one) == 0.0)
	_check("escape() returns the point untouched", PlacementClamp.escape(far, one, MARGIN_PX) == far)

	# A point exactly ON the boundary is outside it: the validators reject
	# "< 9 inches", so 9.000" is legal and must not be nudged.
	var on_ring := Vector2(600, 250) + Vector2(0, float(one[0]["radius_px"]))
	_check("a point on the boundary counts as outside", PlacementClamp.penetration_px(on_ring, one) == 0.0)

	# ── Inside one bubble: pushed straight out, on the near side ──────
	print("-- one bubble: nearest point out, along the player's own bearing --")
	var inside := Vector2(600, 500)  # 250px from the centre, bubble is ~464px
	_check("penetration reported", PlacementClamp.penetration_px(inside, one) > 200.0,
		"got %.1f" % PlacementClamp.penetration_px(inside, one))
	var out := PlacementClamp.escape(inside, one, MARGIN_PX)
	_check("pushed clear of the bubble", PlacementClamp.penetration_px(out, one) == 0.0)
	_check("kept the player's bearing (straight down)", absf(out.x - 600.0) < 0.01,
		"got x=%.3f" % out.x)
	_check("parked just outside the 9\" line, not deep in the open",
		_edge_inches(out, one[0]) > 0.0 and _edge_inches(out, one[0]) < 0.1,
		"edge=%.4f\"" % _edge_inches(out, one[0]))
	# The margin is what stops a float hair's-breadth from re-failing the check.
	_check("margin puts it strictly outside", out.distance_to(Vector2(600, 250)) > float(one[0]["radius_px"]))

	# ── Two overlapping bubbles: settles on the union boundary ────────
	print("-- overlapping bubbles: escapes BOTH, not just the deeper one --")
	var two := [_bubble(600, 250, 100), _bubble(400, 250, 60)]
	for aim in [Vector2(500, 400), Vector2(560, 560), Vector2(450, 600), Vector2(600, 300)]:
		var e := PlacementClamp.escape(aim, two, MARGIN_PX)
		_check("aim %s escapes every bubble" % str(aim), PlacementClamp.penetration_px(e, two) == 0.0,
			"left %.2fpx inside" % PlacementClamp.penetration_px(e, two))

	# ── A dense cluster still converges inside the iteration cap ──────
	print("-- a crowded gun line still resolves --")
	var line: Array = []
	for i in range(10):
		line.append(_bubble(200.0 + i * 80.0, 100.0, 40.0))
	for aim2 in [Vector2(600, 300), Vector2(400, 500), Vector2(900, 200), Vector2(250, 480)]:
		var e2 := PlacementClamp.escape(aim2, line, MARGIN_PX)
		_check("aim %s clears a 10-model line" % str(aim2), PlacementClamp.penetration_px(e2, line) == 0.0,
			"left %.2fpx inside" % PlacementClamp.penetration_px(e2, line))

	# ── Degenerate input: the cursor sitting on an enemy's base ───────
	print("-- cursor dead on an enemy model --")
	var dead_centre := PlacementClamp.escape(Vector2(600, 250), one, MARGIN_PX)
	_check("still lands outside the bubble", PlacementClamp.penetration_px(dead_centre, one) == 0.0)
	_check("did not return NaN", not is_nan(dead_centre.x) and not is_nan(dead_centre.y))

	print("-- no bubbles at all (no enemies on the table) --")
	_check("escape is a no-op", PlacementClamp.escape(Vector2(123, 456), [], MARGIN_PX) == Vector2(123, 456))
	_check("penetration is 0", PlacementClamp.penetration_px(Vector2(123, 456), []) == 0.0)

	# ── Bubble radius folds in BOTH bases ─────────────────────────────
	# A big model deep-striking has to stop further out than a small one, because
	# the 9" is measured edge-to-edge. Getting this wrong is how a clamp parks a
	# model on a line the validator then rejects.
	print("-- radius scales with the placed model's own base --")
	var small := _bubble(600, 250, 40, 9.0)
	var big_model_r := (100.0 / 2.0) / 25.4  # placing a 100mm model instead of 32mm
	var big := PlacementClamp.make_bubble(Vector2(600, 250), (9.0 + big_model_r + (40.0 / 2.0) / 25.4) * PX_PER_INCH)
	_check("bigger placed base -> bigger bubble", float(big["radius_px"]) > float(small["radius_px"]))
	var expected_delta := (big_model_r - (32.0 / 2.0) / 25.4) * PX_PER_INCH
	_check("difference is exactly the base-radius difference",
		absf((float(big["radius_px"]) - float(small["radius_px"])) - expected_delta) < 0.01)

	# Omni-scramblers push out to 12" instead of 9".
	var omni := _bubble(600, 250, 40, 12.0)
	_check("12\" Omni-scrambler bubble is 3\" wider",
		absf((float(omni["radius_px"]) - float(small["radius_px"])) - 3.0 * PX_PER_INCH) < 0.01)

	print("\n=== RESULT: %d passed, %d failed ===\n" % [passed, failed])
	quit(1 if failed > 0 else 0)

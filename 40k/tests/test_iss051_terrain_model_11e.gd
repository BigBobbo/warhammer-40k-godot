extends SceneTree

# ISS-051 (step 1): 11e terrain model — categories (13.03-13.05) and area
# queries over the runtime terrain pieces.
#
# Usage: godot --headless --path . -s tests/test_iss051_terrain_model_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss051_terrain_model_11e ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	if tm == null:
		_check("TerrainManager reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return
	var prev = tm.terrain_features.duplicate(true)

	print("-- categories (13.03-13.05) --")
	_check("ruins are dense", tm.category_of({"type": "ruins"}) == "dense")
	_check("woods are dense", tm.category_of({"type": "woods"}) == "dense")
	_check("barricades are light", tm.category_of({"type": "barricade"}) == "light")
	_check("craters are exposed", tm.category_of({"type": "crater"}) == "exposed")
	_check("explicit category overrides type",
		tm.category_of({"type": "ruins", "category": "light"}) == "light")

	print("\n-- heights --")
	_check("tall label -> 6\"", tm.height_inches_of({"height_category": "tall"}) == 6.0)
	_check("low label -> 1.5\"", tm.height_inches_of({"height_category": "low"}) == 1.5)
	_check("explicit height_inches wins",
		tm.height_inches_of({"height_category": "tall", "height_inches": 4.0}) == 4.0)

	print("\n-- area + crossing queries --")
	tm.terrain_features = [
		{"id": "ruin_a", "type": "ruins", "polygon": _rect(400, 400, 200, 200), "height_category": "tall"},
		{"id": "crater_b", "type": "crater", "polygon": _rect(900, 400, 100, 100), "height_category": "low"},
	]
	_check("point inside the ruin resolves its area",
		tm.area_at(Vector2(400, 400)).get("id", "") == "ruin_a")
	_check("open ground resolves no area", tm.area_at(Vector2(650, 800)).is_empty())
	var crossed = tm.features_crossing(Vector2(100, 400), Vector2(1100, 400))
	_check("segment across the board crosses both features",
		crossed.size() == 2, str(crossed.size()))

	print("\n-- obscured-between (13.10 center-line approximation) --")
	_check("both endpoints outside, dense between: obscured",
		tm.is_obscured_between(Vector2(100, 400), Vector2(700, 400)))
	_check("endpoint INSIDE the feature: not obscured by it",
		not tm.is_obscured_between(Vector2(400, 400), Vector2(700, 400)))
	_check("crossing only the EXPOSED crater: not obscured",
		not tm.is_obscured_between(Vector2(820, 400), Vector2(980, 400)))
	_check("clear line: not obscured",
		not tm.is_obscured_between(Vector2(100, 800), Vector2(1100, 800)))

	tm.terrain_features = prev
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

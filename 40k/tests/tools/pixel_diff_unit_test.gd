extends SceneTree

# Headless self-test for PixelDiff. Run via:
#
#   godot --headless --path 40k --script tests/tools/pixel_diff_unit_test.gd
#
# Exit code 0 if all assertions hold; 1 otherwise. No dependence on a windowed
# session or on the scenario harness — exercises the diff math directly by
# generating synthetic PNGs in /tmp.

const TMP_DIR := "/tmp/pixel_diff_unit_test"

var _failed := 0
var _passed := 0


func _init() -> void:
	# Need PixelDiff resolved. The class_name is registered globally at script
	# parse time; preload to be explicit and avoid load-order issues.
	var pd_script = load("res://tests/tools/pixel_diff.gd")
	if pd_script == null:
		print("[unit] FATAL: could not load pixel_diff.gd")
		quit(1)
		return

	_ensure_tmp_dir()

	# 1. Identical images -> 0%
	var solid_red := _make_image(64, 64, Color(1, 0, 0, 1))
	var path_a := "%s/red_a.png" % TMP_DIR
	var path_b := "%s/red_b.png" % TMP_DIR
	solid_red.save_png(path_a)
	solid_red.save_png(path_b)
	var r1 = pd_script.diff(path_a, path_b)
	_expect_no_error("identical images", r1)
	_expect_float_eq("identical images total_diff_pct", r1.get("total_diff_pct", -1.0), 0.0, 0.001)

	# 2. Solid black vs solid white -> > 95%
	var black := _make_image(64, 64, Color(0, 0, 0, 1))
	var white := _make_image(64, 64, Color(1, 1, 1, 1))
	var path_black := "%s/black.png" % TMP_DIR
	var path_white := "%s/white.png" % TMP_DIR
	black.save_png(path_black)
	white.save_png(path_white)
	var r2 = pd_script.diff(path_black, path_white)
	_expect_no_error("black vs white", r2)
	_expect_float_gt("black vs white total_diff_pct", r2.get("total_diff_pct", -1.0), 95.0)

	# 3. Region clipped to a known area
	var split := _make_split_image(64, 64)
	var path_split := "%s/split.png" % TMP_DIR
	split.save_png(path_split)
	# Left half is black, right half is white. So:
	#   black-only region (0,0,32,64) diffed against pure-black:  ~0%
	#   right-half region (32,0,32,64) diffed against pure-black: ~100%
	var regions := {
		"left_half": [0, 0, 32, 64],
		"right_half": [32, 0, 32, 64],
	}
	var r3 = pd_script.diff(path_black, path_split, regions)
	_expect_no_error("regioned diff", r3)
	var r3_regions: Dictionary = r3.get("regions", {})
	_expect_float_eq("left_half (matches black baseline)", r3_regions.get("left_half", -1.0), 0.0, 0.001)
	_expect_float_gt("right_half (diverges from black)", r3_regions.get("right_half", -1.0), 95.0)

	# 4. Size mismatch -> error
	var small := _make_image(32, 32, Color(1, 0, 0, 1))
	var path_small := "%s/small.png" % TMP_DIR
	small.save_png(path_small)
	var r4 = pd_script.diff(path_a, path_small)
	_expect_has_error("size mismatch detected", r4)

	# 5. Missing file -> error
	var r5 = pd_script.diff("%s/nonexistent.png" % TMP_DIR, path_a)
	_expect_has_error("missing file detected", r5)

	print("[unit] === pixel_diff: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _ensure_tmp_dir() -> void:
	var d := DirAccess.open("/tmp")
	if d == null:
		return
	d.make_dir_recursive("pixel_diff_unit_test")


func _make_image(w: int, h: int, color: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img


func _make_split_image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			if x < w / 2:
				img.set_pixel(x, y, Color(0, 0, 0, 1))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return img


func _expect_no_error(label: String, result: Dictionary) -> void:
	if result.has("error"):
		_fail(label, "got error: %s" % result["error"])
	else:
		_pass(label)


func _expect_has_error(label: String, result: Dictionary) -> void:
	if result.has("error"):
		_pass(label)
	else:
		_fail(label, "expected error, got %s" % str(result))


func _expect_float_eq(label: String, actual: float, expected: float, tol: float) -> void:
	if abs(actual - expected) <= tol:
		_pass(label)
	else:
		_fail(label, "expected %f ± %f, got %f" % [expected, tol, actual])


func _expect_float_gt(label: String, actual: float, threshold: float) -> void:
	if actual > threshold:
		_pass(label)
	else:
		_fail(label, "expected > %f, got %f" % [threshold, actual])


func _pass(label: String) -> void:
	_passed += 1
	print("[unit] PASS  %s" % label)


func _fail(label: String, detail: String) -> void:
	_failed += 1
	print("[unit] FAIL  %s — %s" % [label, detail])

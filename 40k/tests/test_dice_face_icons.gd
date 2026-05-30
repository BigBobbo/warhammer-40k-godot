extends SceneTree

# Headless test for DiceFaceIcons — the d6 face texture factory used to embed
# dice icons inline in RichTextLabel resolution logs.

const DiceFaceIconsScript := preload("res://scripts/DiceFaceIcons.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== DiceFaceIcons Test ===")
	_test_face_generation()
	_test_cache_reuse()
	_test_color_for()
	print("\n=== Result: %d passed / %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  PASS  %s" % name)
	else:
		_failed += 1
		print("  FAIL  %s — %s" % [name, detail])

func _test_face_generation() -> void:
	for v in range(1, 7):
		var tex = DiceFaceIconsScript.get_face(v, DiceFaceIconsScript.COLOR_NEUTRAL)
		_check("face %d produces a texture" % v, tex != null and tex is ImageTexture)
		_check("face %d is TEX_SIZE square" % v,
			tex.get_width() == DiceFaceIconsScript.TEX_SIZE and tex.get_height() == DiceFaceIconsScript.TEX_SIZE,
			"got %dx%d" % [tex.get_width(), tex.get_height()])

func _test_cache_reuse() -> void:
	var a = DiceFaceIconsScript.get_face(6, DiceFaceIconsScript.COLOR_CRITICAL)
	var b = DiceFaceIconsScript.get_face(6, DiceFaceIconsScript.COLOR_CRITICAL)
	_check("identical (value,color) returns cached instance", a == b)
	var c = DiceFaceIconsScript.get_face(6, DiceFaceIconsScript.COLOR_SUCCESS)
	_check("different color returns a different texture", a != c)

func _test_color_for() -> void:
	_check("6 -> critical gold", DiceFaceIconsScript.color_for(6, 3) == DiceFaceIconsScript.COLOR_CRITICAL)
	_check("1 -> fumble red", DiceFaceIconsScript.color_for(1, 3) == DiceFaceIconsScript.COLOR_FUMBLE)
	_check("4 vs 3+ -> success", DiceFaceIconsScript.color_for(4, 3) == DiceFaceIconsScript.COLOR_SUCCESS)
	_check("2 vs 3+ -> fail", DiceFaceIconsScript.color_for(2, 3) == DiceFaceIconsScript.COLOR_FAIL)
	_check("3 no threshold -> neutral", DiceFaceIconsScript.color_for(3, 0, false) == DiceFaceIconsScript.COLOR_NEUTRAL)

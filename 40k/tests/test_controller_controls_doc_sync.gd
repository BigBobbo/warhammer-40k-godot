extends SceneTree

# Drift-check for the Controller Controls Map (the source-of-truth doc).
#
# The doc's per-state button tables are generated from PadRouter's HINTS_*
# constants. This test asserts that the committed mirror
# `docs/controller_hint_sets.json` still matches those live constants exactly
# (glyph + label + order). If a hint set changes in code and the doc is not
# regenerated, this FAILS — so the documented controls only change when we
# intend them to, never by a silent drift.
#
# It also checks that every hint set the doc claims to render still exists in
# the code, that the HTML still names each set, and that every referenced
# screenshot file is present.
#
# Usage: godot --headless --path . -s tests/test_controller_controls_doc_sync.gd

const PAD_ROUTER := preload("res://autoloads/PadRouter.gd")

const JSON_PATH := "res://docs/controller_hint_sets.json"
const HTML_PATH := "res://docs/CONTROLLER_CONTROLS_MAP.html"
const SHOTS_DIR := "res://docs/controller_shots/"

# The hint sets the doc mirrors. Kept explicit (not reflected) so ADDING a new
# HINTS_* set in code also fails this test until the doc is updated to cover it.
const TRACKED_SETS := [
	"HINTS_BOARD", "HINTS_TARGETS", "HINTS_CHARGE_SELECT", "HINTS_CHARGE_READY",
	"HINTS_CHARGE_ROLL", "HINTS_CHARGE_MOVE", "HINTS_DEPLOY", "HINTS_FOCUS",
	"HINTS_CARRY", "HINTS_CARRY_MOVE", "HINTS_CARRY_GROUP", "HINTS_MENU",
	"HINTS_MOVE", "HINTS_MOVE_STAGED", "HINTS_MOVE_LOCKED", "HINTS_FIGHT",
]

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("\n=== test_controller_controls_doc_sync ===\n")

	# 1. Load the committed mirror JSON.
	var json_txt := _read(JSON_PATH)
	_check("controller_hint_sets.json present", json_txt != "", JSON_PATH)
	var data = JSON.parse_string(json_txt) if json_txt != "" else null
	_check("controller_hint_sets.json parses", data is Dictionary)

	# Explicit name -> live constant map. Referencing each constant directly
	# (rather than by string) means renaming/removing a HINTS_* set in code is a
	# compile-time break here too — the strongest possible drift signal.
	var code_sets := {
		"HINTS_BOARD": PAD_ROUTER.HINTS_BOARD,
		"HINTS_TARGETS": PAD_ROUTER.HINTS_TARGETS,
		"HINTS_CHARGE_SELECT": PAD_ROUTER.HINTS_CHARGE_SELECT,
		"HINTS_CHARGE_READY": PAD_ROUTER.HINTS_CHARGE_READY,
		"HINTS_CHARGE_ROLL": PAD_ROUTER.HINTS_CHARGE_ROLL,
		"HINTS_CHARGE_MOVE": PAD_ROUTER.HINTS_CHARGE_MOVE,
		"HINTS_DEPLOY": PAD_ROUTER.HINTS_DEPLOY,
		"HINTS_FOCUS": PAD_ROUTER.HINTS_FOCUS,
		"HINTS_CARRY": PAD_ROUTER.HINTS_CARRY,
		"HINTS_CARRY_MOVE": PAD_ROUTER.HINTS_CARRY_MOVE,
		"HINTS_CARRY_GROUP": PAD_ROUTER.HINTS_CARRY_GROUP,
		"HINTS_MENU": PAD_ROUTER.HINTS_MENU,
		"HINTS_MOVE": PAD_ROUTER.HINTS_MOVE,
		"HINTS_MOVE_STAGED": PAD_ROUTER.HINTS_MOVE_STAGED,
		"HINTS_MOVE_LOCKED": PAD_ROUTER.HINTS_MOVE_LOCKED,
		"HINTS_FIGHT": PAD_ROUTER.HINTS_FIGHT,
	}

	if data is Dictionary:
		# 2. Every tracked set matches the live PadRouter constant exactly.
		for set_name in TRACKED_SETS:
			var code_val = code_sets.get(set_name)
			_check("code has const %s" % set_name, code_val is Array, "not an Array on PadRouter")
			_check("doc mirrors %s" % set_name, data.has(set_name),
				"missing from controller_hint_sets.json — regenerate the doc")
			if code_val is Array and data.has(set_name):
				_check("%s matches code (glyph+label+order)" % set_name,
					_arrays_equal(code_val, data[set_name]),
					"code=%s  doc=%s" % [str(code_val), str(data[set_name])])

		# 3. No stale sets in the doc that no longer exist in code.
		for doc_set in data.keys():
			_check("doc set %s still exists in code" % doc_set,
				TRACKED_SETS.has(doc_set),
				"unknown/renamed hint set left in the doc")

	# 4. The HTML still names each tracked set (guards against the doc being
	#    gutted / a set silently dropped from the rendered tables).
	var html := _read(HTML_PATH)
	_check("CONTROLLER_CONTROLS_MAP.html present", html != "", HTML_PATH)
	for set_name in TRACKED_SETS:
		if html != "":
			_check("HTML references %s" % set_name, html.find(set_name) != -1,
				"the rendered doc no longer mentions this hint set")

	# 5. Every screenshot referenced by the HTML exists on disk.
	if html != "":
		for shot in _referenced_shots(html):
			_check("screenshot present: %s" % shot,
				FileAccess.file_exists(SHOTS_DIR + shot), SHOTS_DIR + shot)

	_finish()

func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var ea = a[i]
		var eb = b[i]
		if not (ea is Array) or not (eb is Array) or ea.size() != eb.size():
			return false
		for j in range(ea.size()):
			if str(ea[j]) != str(eb[j]):
				return false
	return true

func _referenced_shots(html: String) -> Array:
	var out: Array = []
	var needle := "controller_shots/"
	var from := 0
	while true:
		var idx := html.find(needle, from)
		if idx == -1:
			break
		var start := idx + needle.length()
		var end := html.find(".png", start)
		if end == -1:
			break
		var fn := html.substr(start, end - start) + ".png"
		if not out.has(fn):
			out.append(fn)
		from = end + 4
	return out

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("\nTo fix intentional control changes: re-dump PadRouter.HINTS_* and")
		print("regenerate docs/CONTROLLER_CONTROLS_MAP.html + controller_hint_sets.json.")
	quit(1 if failed > 0 else 0)

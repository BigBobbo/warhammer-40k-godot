extends SceneTree

# ISS-020: phases/controllers/dialogs must use RulesEngine's public API,
# never its underscore-private internals.
#
# Usage: godot --headless --path . -s tests/test_iss020_public_api.gd

var passed := 0
var failed := 0

const SCAN_DIRS = ["res://phases", "res://scripts", "res://dialogs"]

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

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss020_public_api ===\n")
	var rx = RegEx.new()
	var err = rx.compile("RulesEngine\\._")
	_check("lint regex compiles", err == OK)
	var offenders = []
	for dir_path in SCAN_DIRS:
		_scan_dir(dir_path, rx, offenders)
	_check("no private RulesEngine access outside RulesEngine (%d dirs)" % SCAN_DIRS.size(),
		offenders.is_empty(), ", ".join(offenders))

	# The public wrappers behave like the privates they front.
	var rules = root.get_node_or_null("RulesEngine")
	_check("generate_weapon_id works",
		rules != null and rules.generate_weapon_id("Big Shoota", "Ranged") != "")
	var unit = {"models": [{"id": "m1", "alive": true}]}
	_check("get_model_by_id works",
		rules.get_model_by_id(unit, "m1").get("id", "") == "m1")
	_check("get_model_by_id misses cleanly",
		rules.get_model_by_id(unit, "nope").is_empty())

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _scan_dir(dir_path: String, rx: RegEx, offenders: Array) -> void:
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		var full = dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full, rx, offenders)
		elif entry.ends_with(".gd"):
			var f = FileAccess.open(full, FileAccess.READ)
			if f != null:
				var line_no = 0
				while not f.eof_reached():
					var line = f.get_line()
					line_no += 1
					if line.strip_edges().begins_with("#") or line.strip_edges().begins_with("##"):
						continue
					if rx.search(line) != null:
						offenders.append("%s:%d" % [full, line_no])
				f.close()
		entry = dir.get_next()
	dir.list_dir_end()

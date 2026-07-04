extends SceneTree

# ISS-002: rule constants are centralized in GameConstants with an edition
# switch. Engagement range and coherency distances must come from
# GameConstants, never from local constants/literals, so the 11e migration
# (ER 1" -> 2", core rules 03.04) flips everywhere at once.
#
# Checks:
#   A) GameConstants values per edition (10 default; 11 flips ER to 2").
#   B) Measurement.is_in_engagement_range_shape_aware default argument is
#      edition-aware (1.5" gap: out of ER at edition 10, in ER at edition 11).
#   C) Static scan: no ENGAGEMENT_RANGE const re-declarations outside
#      GameConstants.gd.
#
# Usage: godot --headless --path . -s tests/test_iss002_game_constants.gd

var passed := 0
var failed := 0

const SCAN_DIRS = ["res://phases", "res://scripts", "res://autoloads", "res://dialogs"]

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
	print("\n=== test_iss002_game_constants ===\n")
	_test_edition_values()
	_test_measurement_default_is_edition_aware()
	_test_no_redeclared_constants()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

# -- A: edition values --------------------------------------------------------

func _test_edition_values() -> void:
	print("\n-- A: GameConstants edition values --")
	# The static default is 11 (11th edition only); the automated harness pins
	# GameConstants.edition to the legacy 10e baseline for this suite.
	_check("harness baseline edition is 10", GameConstants.edition == 10)
	_check("edition 10: engagement range 1.0\"",
		GameConstants.engagement_range_inches() == 1.0)
	_check("vertical engagement range 5.0\"",
		GameConstants.engagement_range_vertical_inches() == 5.0)
	_check("barricade engagement range 2.0\"",
		GameConstants.barricade_engagement_range_inches() == 2.0)
	_check("coherency distance 2.0\"",
		GameConstants.coherency_distance_inches() == 2.0)

	GameConstants.edition = 11
	_check("edition 11: engagement range 2.0\"",
		GameConstants.engagement_range_inches() == 2.0)
	_check("edition 11: coherency distance still 2.0\"",
		GameConstants.coherency_distance_inches() == 2.0)
	GameConstants.edition = 10
	_check("edition restored to 10 -> ER back to 1.0\"",
		GameConstants.engagement_range_inches() == 1.0)

# -- B: Measurement default flips with edition --------------------------------

func _test_measurement_default_is_edition_aware() -> void:
	print("\n-- B: shape-aware ER default follows the edition --")
	var measurement = root.get_node_or_null("Measurement")
	if measurement == null:
		_check("Measurement autoload reachable", false)
		return
	# Two 32mm circular bases, 1.5" apart edge-to-edge:
	# radius_px = 32 / 25.4 * 40 / 2 ~= 25.2; center distance = 60 + 2*radius.
	var radius_px = (32.0 / 25.4) * 40.0 / 2.0
	var m1 = {"position": Vector2(0, 0), "base_mm": 32}
	var m2 = {"position": Vector2(60.0 + 2.0 * radius_px, 0), "base_mm": 32}
	_check("edition 10: 1.5\" gap is OUT of engagement range",
		measurement.is_in_engagement_range_shape_aware(m1, m2) == false)
	GameConstants.edition = 11
	_check("edition 11: 1.5\" gap is IN engagement range",
		measurement.is_in_engagement_range_shape_aware(m1, m2) == true)
	GameConstants.edition = 10
	_check("explicit er_inches argument still honored (3.0\")",
		measurement.is_in_engagement_range_shape_aware(m1, m2, 3.0) == true)

# -- C: static scan ------------------------------------------------------------

func _test_no_redeclared_constants() -> void:
	print("\n-- C: no ENGAGEMENT_RANGE const re-declarations --")
	var rx = RegEx.new()
	var err = rx.compile("const\\s+\\w*ENGAGEMENT_RANGE\\w*\\s*[:=]")
	_check("scan regex compiles", err == OK)
	var offenders = []
	for dir_path in SCAN_DIRS:
		_scan_dir(dir_path, rx, offenders)
	_check("no re-declared engagement range constants (%d dirs scanned)" % SCAN_DIRS.size(),
		offenders.is_empty(), ", ".join(offenders))

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
		elif entry.ends_with(".gd") and entry != "GameConstants.gd":
			var f = FileAccess.open(full, FileAccess.READ)
			if f != null:
				var line_no = 0
				while not f.eof_reached():
					var line = f.get_line()
					line_no += 1
					if line.strip_edges().begins_with("#"):
						continue
					if rx.search(line) != null:
						offenders.append("%s:%d" % [full, line_no])
				f.close()
		entry = dir.get_next()
	dir.list_dir_end()

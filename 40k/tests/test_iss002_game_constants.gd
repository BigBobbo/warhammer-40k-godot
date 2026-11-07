extends SceneTree

# ISS-002: rule constants are centralized in GameConstants with an edition
# switch. Engagement range and coherency distances must come from
# GameConstants, never from local constants/literals, so the 11e migration
# (ER 1" -> 2", core rules 03.04) flips everywhere at once.
#
# Checks:
#   A) GameConstants values per edition (harness default 11; 10e via explicit
#      opt-in; 11 flips ER to 2").
#   B) Measurement.is_in_engagement_range_shape_aware default argument is
#      edition-aware (1.5" gap: out of ER at edition 10, in ER at edition 11).
#   C) Static scan: no ENGAGEMENT_RANGE const re-declarations outside
#      GameConstants.gd.
#   A2) Stand-off accessors (P0.2): scout / reinforcement / infiltrators are
#      8" at 11e and 9" at 10e, and ScoutPhase reads the scout accessor.
#   D) Static scan (P0.2, regression net only — not validation): no const/var
#      declaration whose name is a stand-off (enemy / standoff / infiltrat /
#      ds_clear) is assigned a literal 8.0 / 9.0 outside GameConstants.gd, and
#      no player-facing Scout / Infiltrators string in Main.gd hard-codes 9".
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
	_test_standoff_accessors()
	_test_measurement_default_is_edition_aware()
	_test_no_redeclared_constants()
	_test_no_redeclared_standoffs()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

# -- A: edition values --------------------------------------------------------

func _test_edition_values() -> void:
	print("\n-- A: GameConstants edition values --")
	# The static default is 11 (11th edition only) and the test harness now
	# defaults to it too (rules audit 9.2: the old silent 10e pin produced
	# false-green evidence). 10e is reachable only through an explicit opt-in.
	var settings = root.get_node_or_null("SettingsService")
	var env_ed := OS.get_environment("WH40K_TEST_EDITION").strip_edges()
	var expected_boot := 10 if env_ed == "10" else 11
	_check("harness boot edition is %d (WH40K_TEST_EDITION=%s)" % [expected_boot, env_ed if env_ed != "" else "<unset>"],
		GameConstants.edition == expected_boot, "got %d" % GameConstants.edition)
	if settings != null and settings.has_method("_resolve_harness_edition"):
		var saved_env := OS.get_environment("WH40K_TEST_EDITION")
		OS.set_environment("WH40K_TEST_EDITION", "")
		var r_default: Dictionary = settings._resolve_harness_edition()
		_check("harness default edition (no opt-in) is 11", int(r_default.edition) == 11, str(r_default))
		OS.set_environment("WH40K_TEST_EDITION", "10")
		var r_legacy: Dictionary = settings._resolve_harness_edition()
		_check("explicit WH40K_TEST_EDITION=10 opt-in resolves to 10", int(r_legacy.edition) == 10, str(r_legacy))
		OS.set_environment("WH40K_TEST_EDITION", saved_env)
	else:
		_check("SettingsService._resolve_harness_edition reachable", false)
	# The 10e constants below need 10e explicitly — never inherited.
	GameConstants.edition = 10
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

# -- A2: stand-off accessors (P0.2) -------------------------------------------

func _test_standoff_accessors() -> void:
	print("\n-- A2: stand-off accessors (11e 24.32 / 20.04 / 24.20) --")
	var ed0 := GameConstants.edition
	var sp = load("res://phases/ScoutPhase.gd").new()
	for ed in [11, 10]:
		GameConstants.edition = ed
		var want := 8.0 if ed >= 11 else 9.0
		_check("edition %d: scout_min_enemy_distance_inches() == %.0f\"" % [ed, want],
			GameConstants.scout_min_enemy_distance_inches() == want, str(GameConstants.scout_min_enemy_distance_inches()))
		_check("edition %d: reinforcement_min_enemy_distance_inches() == %.0f\"" % [ed, want],
			GameConstants.reinforcement_min_enemy_distance_inches() == want, str(GameConstants.reinforcement_min_enemy_distance_inches()))
		_check("edition %d: infiltrators_min_enemy_distance_inches() == %.0f\"" % [ed, want],
			GameConstants.infiltrators_min_enemy_distance_inches() == want, str(GameConstants.infiltrators_min_enemy_distance_inches()))
		_check("edition %d: ScoutPhase reads the scout accessor" % ed,
			sp._scout_min_enemy_distance_inches() == GameConstants.scout_min_enemy_distance_inches(),
			str(sp._scout_min_enemy_distance_inches()))
	_check("ScoutPhase no longer declares its own SCOUT_MIN_ENEMY_DISTANCE_INCHES",
		not ("SCOUT_MIN_ENEMY_DISTANCE_INCHES" in sp.get_script().get_script_constant_map()))
	sp.free()
	GameConstants.edition = ed0

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

# -- D: stand-off literals (P0.2) ----------------------------------------------
# A regression net, not validation: it catches the exact shapes that hid the
# 11e stand-offs for a whole edition — `const SCOUT_ENEMY_DIST_INCHES = 9.0`
# (AI scouts), `const SCOUT_MIN_ENEMY_DISTANCE_INCHES = 9.0` (ScoutPhase),
# `var min_enemy_dist_px = 9.0 * ...` / `var ds_clear_px = (9.0 * ...)` (AI
# reserves), `var enemy_px = m.inches_to_px(8.0)` (IngressMove) and
# `var infiltrate_min = 8.0 if ... else 9.0` (DeploymentPhase).
# Names: a stand-off word (enemy / standoff / infiltrat / ds_clear), but not a
# scoring coefficient (bonus / penalty / weight / score — e.g.
# MELEE_AGGRESSION_ENEMY_SEEK_BONUS = 8.0 is a score, not a distance rule).
# It must NOT hit GameState.SCOUT_DISTANCE_PATTERN or
# AIDecisionMaker.SCOUT_OBJ_DISTANCE_PENALTY (the first proposed regex did).
# scripts/codex is skipped: those files hold 11e datasheet values with their
# own rule text (e.g. Drop Pod Assault's 8"), not edition-switched core rules.

const STANDOFF_SCAN_SKIP_DIRS = ["res://scripts/codex"]

func _test_no_redeclared_standoffs() -> void:
	print("\n-- D: no hard-coded 8\"/9\" stand-off declarations (P0.2) --")
	var decl := RegEx.new()
	var e1 = decl.compile("^\\s*(?:static\\s+)?(?:const|var)\\s+(\\w+)\\s*(?::\\s*[\\w.]+\\s*)?:?=\\s*(.*)$")
	var name_rx := RegEx.new()
	var e2 = name_rx.compile("(?i)(enemy|standoff|stand_off|infiltrat|ds_clear)")
	var skip_rx := RegEx.new()
	var e3 = skip_rx.compile("(?i)(bonus|penalty|weight|score)")
	var lit_rx := RegEx.new()
	var e4 = lit_rx.compile("(?<![\\w.])[89]\\.0(?![\\w.])")
	_check("stand-off scan regexes compile", e1 == OK and e2 == OK and e3 == OK and e4 == OK)

	# Self-test: the scan flags every shape it exists for, and spares the
	# legitimate lines the first proposal tripped on.
	var must_flag := [
		"\tconst SCOUT_ENEMY_DIST_INCHES: float = 9.0",
		"const SCOUT_MIN_ENEMY_DISTANCE_INCHES: float = 9.0",
		"\tvar min_enemy_dist_px = 9.0 * PIXELS_PER_INCH + base_radius_px + 25.0  # 25px",
		"\tvar ds_clear_px = (9.0 * PIXELS_PER_INCH) - OBJECTIVE_CONTROL_RANGE_PX",
		"\tvar enemy_px = m.inches_to_px(8.0)",
		"\tvar infiltrate_min = 8.0 if GameConstants.edition >= 11 else 9.0",
		"\tvar scout_standoff := 9.0",
	]
	var must_pass := [
		"const SCOUT_DISTANCE_PATTERN: String = \"(?i)\\\\bscouts?\\\\s*(\\\\d+)\"",
		"const SCOUT_OBJ_DISTANCE_PENALTY: float = 0.3",
		"const MELEE_AGGRESSION_ENEMY_SEEK_BONUS: float = 8.0",
		"\tvar scout_standoff_in: float = GameConstants.scout_min_enemy_distance_inches()",
	]
	var self_ok := true
	for l in must_flag:
		if not _standoff_line_flagged(l, decl, name_rx, skip_rx, lit_rx):
			self_ok = false
			print("    self-test MISSED: %s" % l)
	for l in must_pass:
		if _standoff_line_flagged(l, decl, name_rx, skip_rx, lit_rx):
			self_ok = false
			print("    self-test FALSE POSITIVE: %s" % l)
	_check("stand-off scan self-test (%d regression shapes flagged, %d legit lines spared)" % [must_flag.size(), must_pass.size()], self_ok)

	var offenders := []
	for dir_path in SCAN_DIRS:
		_scan_standoffs(dir_path, decl, name_rx, skip_rx, lit_rx, offenders)
	_check("no stand-off declared as a literal 8.0/9.0 outside GameConstants.gd (%d dirs)" % SCAN_DIRS.size(),
		offenders.is_empty(), ", ".join(offenders))

	# Player-facing Scout / Infiltrators prompts (D9): Main.gd must read the
	# GameConstants accessors, never spell 9" (the 10e value) itself.
	var ui_offenders := []
	var f = FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	_check("scripts/Main.gd readable", f != null)
	if f != null:
		var n := 0
		while not f.eof_reached():
			var line = f.get_line()
			n += 1
			if line.strip_edges().begins_with("#"):
				continue
			var low = line.to_lower()
			if ("scout" in low or "infiltrat" in low) and (">9\\\"" in line or "up to 9\\\"" in line):
				ui_offenders.append("Main.gd:%d" % n)
		f.close()
	_check("no Scout/Infiltrators UI string in Main.gd hard-codes 9\"", ui_offenders.is_empty(), ", ".join(ui_offenders))

func _standoff_line_flagged(line: String, decl: RegEx, name_rx: RegEx, skip_rx: RegEx, lit_rx: RegEx) -> bool:
	if line.strip_edges().begins_with("#"):
		return false
	var m = decl.search(line)
	if m == null:
		return false
	var nm: String = m.get_string(1)
	var rhs: String = m.get_string(2)
	var hash_at := rhs.find("#")
	if hash_at >= 0:
		rhs = rhs.substr(0, hash_at)
	return name_rx.search(nm) != null and skip_rx.search(nm) == null and lit_rx.search(rhs) != null

func _scan_standoffs(dir_path: String, decl: RegEx, name_rx: RegEx, skip_rx: RegEx, lit_rx: RegEx, offenders: Array) -> void:
	if dir_path in STANDOFF_SCAN_SKIP_DIRS:
		return
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		var full = dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_standoffs(full, decl, name_rx, skip_rx, lit_rx, offenders)
		elif entry.ends_with(".gd") and entry != "GameConstants.gd":
			var f = FileAccess.open(full, FileAccess.READ)
			if f != null:
				var line_no = 0
				while not f.eof_reached():
					var line = f.get_line()
					line_no += 1
					if _standoff_line_flagged(line, decl, name_rx, skip_rx, lit_rx):
						offenders.append("%s:%d" % [full, line_no])
				f.close()
		entry = dir.get_next()
	dir.list_dir_end()

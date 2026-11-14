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
#   D2) Static scan (L4-4, regression net only — the windowed scenario
#      rules_text_standoff_8in_11e checks the rendered text): no string literal
#      in any scanned .gd file states an enemy stand-off as a literal 9"
#      (">9\" from enemies", "more than 9\" ... from enemy models",
#      "9\" exclusion"), the 10e value the Deployment banner, the Infiltrators /
#      Deep Strike exclusion labels, the reserves hint, the redeploy dialogs and
#      Settings showed for the whole of 11e.
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
	_test_ui_standoff_strings()
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

# -- D2: player-facing stand-off strings (L4-4) ---------------------------------
# A regression net, not validation (rules_text_standoff_8in_11e drives the
# rendered labels). Flags a string literal that bakes the enemy stand-off in as
# a literal 9" — the 10e value — instead of formatting the GameConstants
# accessor (scout / reinforcement / infiltrators: 11e 8", 10e 9"):
#   ">9\" from enemies"  "more than 9\" horizontally from enemy models"
#   "9\" exclusion"      "the 9\" enemy exclusion zone"
#   and, as section D already did for Main.gd, a Scout / Infiltrators literal
#   with ">9\"" or "up to 9\"".
# Spared (legitimate 9" rules, or not player-facing): comments and trailing
# comments, docstrings ("""..."""), 03.03 coherency ("within 9\" of every other
# model", "more than 9\" apart", ">9\" from another model in the unit"),
# ability / weapon ranges ("within 9\""), and the codex dirs (datasheet text
# with its own values, as STANDOFF_SCAN_SKIP_DIRS).
# UI_STANDOFF_PENDING lists known 11e-wrong literals OUTSIDE the L4-4 files,
# keyed by file + the exact literal, so an entry goes inert the moment its
# string is fixed (no line numbers to go stale, and it never hides a new
# offender in the same file).

const UI_STANDOFF_SKIP_DIRS = ["res://scripts/codex", "res://scripts/stratagems/ork_codex"]

## The files L4-4 fixed: each must be found and scanned (and, like every other
## scanned file, must have no offender).
const UI_STANDOFF_FIXED_FILES = [
	"res://scripts/Main.gd",
	"res://scripts/PhaseTransitionBanner.gd",
	"res://scripts/InfiltratorExclusionVisual.gd",
	"res://scripts/DeepStrikeExclusionVisual.gd",
	"res://scripts/ReservesData.gd",
	"res://scripts/ScoringController.gd",
	"res://scripts/SettingsMenu.gd",
]

const UI_STANDOFF_PENDING = {
	# Callidus Assassin ability description. The engine returns the unit through
	# the normal Reinforcements gate (8" at 11e); the 11e datasheet value is
	# unverified, so this one waits for a rules check.
	"res://autoloads/UnitAbilityManager.gd": ["End of Fight phase: Fall Back D6\\\" if in engagement. End of opponent's turn: vanish if not within 3\\\" of enemies, reappear next Movement phase >9\\\" from enemies."],
}

func _test_ui_standoff_strings() -> void:
	print("\n-- D2: no player-facing stand-off string hard-codes 9\" (L4-4) --")
	var rx := RegEx.new()
	var err := rx.compile("(?:(?<![\\d.])9\\\\\"\\s+(?:enemy\\s+)?exclusion)|(?:(?:>|more than\\s+)9\\\\\".{0,40}?\\bfrom\\s+(?:all\\s+|the\\s+|any\\s+)?enem)")
	_check("UI stand-off regex compiles", err == OK)
	if err != OK:
		return

	# Self-test: every shape this scan exists for is flagged (the eight 11e-wrong
	# strings L4-4 found, verbatim but for elisions), and the legitimate 9" text
	# around them is spared.
	var must_flag := [
		"\t\t\treturn \"Alternate placing units in your deployment zone. Infiltrators deploy anywhere >9\\\" from enemies.\"",
		"\tvar label_text = \"9\\\" exclusion\"",
		"\t\treturn \"Arrives anywhere more than 9\\\" horizontally from enemy models.\"",
		"\tdesc.text = \"%s ... Movement phase (more than 9\\\" from all enemies).\\n\\nThis ability can only be used once per battle.\" % unit_name",
		"\t_placement_clamp_checkbox = _add_checkbox_row(parent, \"Hold Deep Strike placement outside the 9\\\" exclusion zone\", \"_on_placement_clamp_toggled\")",
		"\tplacement_clamp_help.text = \"On: aiming a Deep Strike / Reserves / Infiltrators drop inside the 9\\\" enemy exclusion zone parks the model\"",
		"\t\t\t\t_show_toast(\"Infiltrators must be >9\\\" from enemy deployment zone\")",
		"\tstatus_label.text = \"Scout move: Drag models up to 6\\\" (must end >9\\\" from enemies)\"",
		"\t\treturn \"Units with Scouts can move up to 9\\\" before the first turn.\"",
	]
	var must_pass := [
		"\t\t\treturn \"Infiltrators deploy anywhere >%d\\\" from the enemy deployment zone and enemy units.\" % int(GameConstants.infiltrators_min_enemy_distance_inches())",
		"\treturn \"%d\\\" exclusion\" % int(_exclusion_distance_inches())",
		"\tvar msg = \"Cannot deploy: %d model(s) out of coherency. Every model must be within 2\\\" of at least one other model in the unit AND within 9\\\" of every other model in the unit.\" % bad",
		"\t\tmsg += \" Some models are more than 9\\\" apart — pull the unit closer together.\"",
		"\t\t\tmsg += \" — some are >9\\\" from another model in the unit\"",
		"\t\t\"description\": \"Attacks that target a unit within 9\\\" have +1 AP (Codex: Space Marines 11e, SMAbilitiesB).\"",
		"\t\treturn \"CO-ORDINATED STRIKE: that unit is not within 9\\\" of a battlefield edge\"",
		"\t# the old text: \">9\\\" from enemies\"",
		"\tprint(\"placed\")  # the old \">9\\\" from enemies\" text",
		"\t\"\"\"Show the exclusion bubbles; 10e said \">9\\\" from enemies\".\"\"\"",
	]
	var self_ok := true
	for l in must_flag:
		if not _ui_standoff_line_flagged(l, rx):
			self_ok = false
			print("    self-test MISSED: %s" % l)
	for l in must_pass:
		if _ui_standoff_line_flagged(l, rx):
			self_ok = false
			print("    self-test FALSE POSITIVE: %s" % l)
	_check("UI stand-off scan self-test (%d 9\" stand-off strings flagged, %d legitimate lines spared)" % [must_flag.size(), must_pass.size()], self_ok)

	var offenders := []
	var pending_hits := []
	var unbalanced := []
	var scanned := {}
	for dir_path in SCAN_DIRS:
		_scan_ui_standoffs(dir_path, rx, offenders, pending_hits, unbalanced, scanned)
	for p in UI_STANDOFF_FIXED_FILES:
		_check("%s found and scanned" % p, scanned.has(p))
	for h in pending_hits:
		print("    NOTE (pending, UI_STANDOFF_PENDING): %s" % h)
	_check("docstring tracking balanced in every scanned file", unbalanced.is_empty(), ", ".join(unbalanced))
	_check("no string literal states a 9\" enemy stand-off (%d files scanned, %d pending outside the L4-4 files)" % [scanned.size(), pending_hits.size()],
		offenders.is_empty(), ", ".join(offenders))

## The string literals on one source line (comment text excluded), escapes kept
## as written (a quote inside one reads \").
static func _source_string_literals(line: String) -> Array:
	var out: Array = []
	var i := 0
	var n := line.length()
	while i < n:
		var c := line[i]
		if c == "#":
			break
		if c == "\"" or c == "'":
			var j := i + 1
			var buf := ""
			while j < n and line[j] != c:
				if line[j] == "\\" and j + 1 < n:
					buf += line.substr(j, 2)
					j += 2
					continue
				buf += line[j]
				j += 1
			out.append(buf)
			i = j + 1
			continue
		i += 1
	return out

## One line, outside any docstring: does a literal on it bake in a 9" stand-off?
func _ui_standoff_line_flagged(line: String, rx: RegEx) -> bool:
	if line.strip_edges().begins_with("#") or "\"\"\"" in line:
		return false
	for lit in _source_string_literals(line):
		var s: String = lit
		if rx.search(s) != null:
			return true
		var low := s.to_lower()
		if ("scout" in low or "infiltrat" in low) and (">9\\\"" in s or "up to 9\\\"" in s):
			return true
	return false

func _scan_ui_standoffs(dir_path: String, rx: RegEx, offenders: Array, pending_hits: Array, unbalanced: Array, scanned: Dictionary) -> void:
	if dir_path in UI_STANDOFF_SKIP_DIRS:
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
				_scan_ui_standoffs(full, rx, offenders, pending_hits, unbalanced, scanned)
		elif entry.ends_with(".gd"):
			var f = FileAccess.open(full, FileAccess.READ)
			if f != null:
				scanned[full] = true
				var pend: Array = UI_STANDOFF_PENDING.get(full, [])
				var in_doc := false
				var line_no := 0
				while not f.eof_reached():
					var line = f.get_line()
					line_no += 1
					var tq: int = line.count("\"\"\"")
					if in_doc or tq > 0:
						# Docstring text is not player-facing.
						if tq % 2 == 1:
							in_doc = not in_doc
						continue
					if not _ui_standoff_line_flagged(line, rx):
						continue
					var known := false
					for lit in _source_string_literals(line):
						if lit in pend:
							known = true
					if known:
						pending_hits.append("%s:%d" % [full, line_no])
					else:
						offenders.append("%s:%d" % [full, line_no])
				f.close()
				if in_doc:
					unbalanced.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

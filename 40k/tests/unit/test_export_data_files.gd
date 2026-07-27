extends GutTest

# Guards the class of bug that made "Basic Trainin'" unplayable on itch.io and
# the Steam Deck while working perfectly from source: **data files that are not
# Godot resources are silently dropped from exported builds.**
#
# Every preset in export_presets.cfg uses export_filter="all_resources", which
# walks the EditorFileSystem and skips anything typed "TextFile"/"OtherFile".
# `.json` is a recognised resource extension (ResourceLoader reports it), so
# res://data/tutorials/lessons/*.json shipped fine — but `.w40ksave` and
# `.meta` are not, so res://data/tutorials/fixtures/* was missing from the PCK.
# TutorialManager._load_fixture() then fell through to the user:// save that a
# fresh install has never had, the lesson booted onto the main menu's
# leftover GameState, and the movement unit list the "PICK DA WAGON" step
# points at rendered as an empty black box with nothing to click.
#
# The same walk also dropped every res://data/*.csv, because those DO have
# `.import` metadata: the exporter follows the import and ships the generated
# resource, and the editor's default `csv_translation` importer never generates
# one. Exported builds therefore loaded 0 faction stratagems and 0 leader
# pairings. Only `importer="keep"` makes the exporter copy the raw file.
#
# No scenario or runtime test can catch either one — running from source, all
# these files exist. The only place the bug is visible is the export config, so
# that is what this asserts. Verified by exporting a real .pck before and after:
# 15 files went from absent to present.
#
# Reference: MovementController._refresh_unit_list, TutorialManager._load_fixture.

const PRESETS_PATH := "res://export_presets.cfg"
const LESSONS_DIR := "res://data/tutorials/lessons/"
const FIXTURES_DIR := "res://data/tutorials/fixtures/"
const DATA_DIR := "res://data/"

# Extensions Godot's resource walk does NOT recognise. A file with one of these
# only reaches an exported build via include_filter (or a keep-mode .import).
const NON_RESOURCE_EXTS := ["w40ksave", "meta", "csv"]


# ------------------------------------------------------------- helpers ----

# Mirror EditorExportPlatform's filter matching: the comma-separated globs are
# tested with matchn() against both the full res:// path and the path relative
# to the project root.
func _filter_matches(filter_csv: String, res_path: String) -> bool:
	var rel := res_path.replace("res://", "")
	for raw in filter_csv.split(",", false):
		var glob := raw.strip_edges()
		if glob == "":
			continue
		if res_path.matchn(glob) or rel.matchn(glob):
			return true
	return false


func _list_files(dir_path: String, ext: String) -> Array:
	var out := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.get_extension() == ext:
			out.append(dir_path + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _runnable_presets() -> Array:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS_PATH), OK, "export_presets.cfg must be readable")
	var out := []
	for section in cfg.get_sections():
		# Preset bodies are "preset.N"; their options live in "preset.N.options".
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		if not bool(cfg.get_value(section, "runnable", false)):
			continue
		out.append({
			"section": section,
			"name": str(cfg.get_value(section, "name", section)),
			"export_filter": str(cfg.get_value(section, "export_filter", "")),
			"include_filter": str(cfg.get_value(section, "include_filter", "")),
			"exclude_filter": str(cfg.get_value(section, "exclude_filter", "")),
		})
	return out


# ------------------------------------------------------ fixtures ship ----

func test_every_lesson_fixture_exists_on_disk():
	var lessons := _list_files(LESSONS_DIR, "json")
	assert_gt(lessons.size(), 0, "no lesson files found under %s" % LESSONS_DIR)
	var checked := 0
	for lesson_path_v in lessons:
		var lesson_path := str(lesson_path_v)
		var text := FileAccess.get_file_as_string(lesson_path)
		var parsed = JSON.parse_string(text)
		assert_true(parsed is Dictionary, "%s must parse as a Dictionary" % lesson_path)
		var boot: Dictionary = parsed.get("boot", {})
		if not boot.has("fixture"):
			continue  # config-booted lesson (T2) — nothing to ship
		var fixture := str(boot.fixture)
		if not fixture.ends_with(".w40ksave"):
			fixture += ".w40ksave"
		assert_true(FileAccess.file_exists(FIXTURES_DIR + fixture),
			"%s boots fixture '%s' which is not in %s" % [lesson_path, fixture, FIXTURES_DIR])
		checked += 1
	assert_gt(checked, 0, "expected at least one fixture-booted lesson")


func test_runnable_presets_ship_every_tutorial_fixture():
	var presets := _runnable_presets()
	assert_gt(presets.size(), 0, "expected at least one runnable export preset")
	var fixtures := _list_files(FIXTURES_DIR, "w40ksave") + _list_files(FIXTURES_DIR, "meta")
	assert_gt(fixtures.size(), 0, "no tutorial fixtures found under %s" % FIXTURES_DIR)

	for preset in presets:
		for path_v in fixtures:
			var path := str(path_v)
			assert_true(_filter_matches(preset.include_filter, path),
				("preset '%s' would ship an exported build WITHOUT %s — its extension is not a "
				+ "Godot resource, so export_filter='%s' skips it and include_filter='%s' does "
				+ "not add it back. That is the tutorial softlock: the lesson boots onto an "
				+ "empty GameState and the movement unit list has nothing in it.") % [
					preset.name, path, preset.export_filter, preset.include_filter])
			assert_false(_filter_matches(preset.exclude_filter, path),
				"preset '%s' excludes %s via exclude_filter='%s'" % [
					preset.name, path, preset.exclude_filter])


# ----------------------------------------------------------- CSVs ship ----

func test_data_csvs_are_keep_imported_so_they_ship():
	var csvs := _list_files(DATA_DIR, "csv")
	assert_gt(csvs.size(), 0, "no CSVs found under %s" % DATA_DIR)
	for csv_path_v in csvs:
		var csv_path := str(csv_path_v)
		var import_path := csv_path + ".import"
		assert_true(FileAccess.file_exists(import_path),
			("%s has no committed .import — the editor will regenerate it with the default "
			+ "csv_translation importer and the raw CSV will not reach exported builds.") % csv_path)
		var cfg := ConfigFile.new()
		assert_eq(cfg.load(import_path), OK, "%s must be readable" % import_path)
		assert_eq(str(cfg.get_value("remap", "importer", "")), "keep",
			("%s must pin importer=\"keep\". With any other importer the export ships the "
			+ "generated resource instead of the file, and FactionStratagemLoader / "
			+ "LeaderPairingsLoader read 0 rows in exported builds.") % import_path)


func test_runnable_presets_do_not_exclude_data_csvs():
	var csvs := _list_files(DATA_DIR, "csv")
	for preset in _runnable_presets():
		for csv_path_v in csvs:
			var csv_path := str(csv_path_v)
			assert_false(_filter_matches(preset.exclude_filter, csv_path),
				"preset '%s' excludes %s via exclude_filter='%s'" % [
					preset.name, csv_path, preset.exclude_filter])


# ------------------------------------------------------------ premise ----

# The reasoning above rests on which extensions Godot treats as resources. If a
# future engine version starts recognising .w40ksave (or stops recognising
# .json), this test's premise moved and the guards above need revisiting.
func test_non_resource_extension_premise_still_holds():
	var recognised := ResourceLoader.get_recognized_extensions_for_type("")
	assert_true(recognised.has("json"),
		"premise moved: .json is no longer a recognised resource extension, so the shipped "
		+ "lesson files need include_filter coverage too")
	for ext in NON_RESOURCE_EXTS:
		assert_false(recognised.has(ext),
			("premise moved: .%s is now a recognised resource extension — re-check whether "
			+ "include_filter / keep-imports are still the right mechanism") % ext)

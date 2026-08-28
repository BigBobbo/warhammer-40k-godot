extends GutTest

# Tutorial Language setting (Settings › Gameplay › Tutorial Language):
# every player-facing lesson string ships in two voices — plain-English base
# keys ("standard", the default) and *_orky twins (Da Boss's dialect, the
# original text). These tests pin the selection logic, the harness pin that
# keeps the windowed tut_* suite on its orky baseline, and the authoring
# contract across all seven shipped lesson files (an _orky key without a
# base twin would silently show orky text to standard-language players).

const TutorialScriptLib = preload("res://scripts/tutorial/TutorialScript.gd")
const LESSON_FILES := [
	"res://data/tutorials/lessons/T1_basics.json",
	"res://data/tutorials/lessons/T2_deployment.json",
	"res://data/tutorials/lessons/T3_movement.json",
	"res://data/tutorials/lessons/T4_shooting.json",
	"res://data/tutorials/lessons/T5_charge.json",
	"res://data/tutorials/lessons/T6_fight.json",
	"res://data/tutorials/lessons/T7_command.json",
]
# High-signal dialect markers that must never appear in a base (standard) key.
# " da " etc. are word-bounded by the padding; CALL DA WAAAGH! is the literal
# button label and legitimately keeps its spelling in both voices.
const ORKY_MARKERS := [" da ", " dat ", " dis ", " dey ", " wiv ", " ya ", " yer ", " an' ", " nuffin", "somefin'"]

var _saved_language: String
var _saved_pin: bool


func before_each():
	_saved_language = SettingsService.tutorial_language
	_saved_pin = SettingsService._tutorial_language_harness_pin


func after_each():
	# Direct writes on purpose: set_tutorial_language() would persist to the
	# container's settings.cfg and emit signals mid-suite.
	SettingsService.tutorial_language = _saved_language
	SettingsService._tutorial_language_harness_pin = _saved_pin


# ------------------------------------------------------------ selection ----

func test_field_lang_picks_voice_and_falls_back():
	var d = {"bark": "WELCOME!", "bark_orky": "OI, LISTEN UP!"}
	assert_eq(TutorialScriptLib.field_lang(d, "bark", false), "WELCOME!")
	assert_eq(TutorialScriptLib.field_lang(d, "bark", true), "OI, LISTEN UP!")
	# Missing variant falls back across voices rather than returning nothing.
	assert_eq(TutorialScriptLib.field_lang({"bark": "only base"}, "bark", true), "only base")
	assert_eq(TutorialScriptLib.field_lang({"bark_orky": "only orky"}, "bark", false), "only orky")
	assert_eq(TutorialScriptLib.field_lang({}, "bark", true, "dflt"), "dflt")


func test_body_for_device_lang_device_beats_voice():
	var step = {"prompt": {
		"kbm": "click it", "kbm_orky": "click it, ya git",
		"pad": "press it", "pad_orky": "squeeze it"}}
	assert_eq(TutorialScriptLib.body_for_device_lang(step, false, false), "click it")
	assert_eq(TutorialScriptLib.body_for_device_lang(step, false, true), "click it, ya git")
	assert_eq(TutorialScriptLib.body_for_device_lang(step, true, false), "press it")
	assert_eq(TutorialScriptLib.body_for_device_lang(step, true, true), "squeeze it")
	# A device key present only in one voice still wins over the other device:
	# an orky pad body beats a standard keyboard body for a pad player.
	var half = {"prompt": {"pad_orky": "orky pad only", "kbm": "standard kbm"}}
	assert_eq(TutorialScriptLib.body_for_device_lang(half, true, false), "orky pad only")
	assert_eq(TutorialScriptLib.body_for_device_lang(half, false, false), "standard kbm")


func test_is_orky_follows_setting_and_harness_pin():
	# The GUT run IS the automated harness, so the pin starts engaged; model
	# both states explicitly rather than depending on test order.
	SettingsService.tutorial_language = "standard"
	SettingsService._tutorial_language_harness_pin = true
	assert_eq(SettingsService.get_tutorial_language(), "orky",
		"harness pin must keep automated runs on the orky baseline")
	assert_true(TutorialScriptLib.is_orky())
	SettingsService._tutorial_language_harness_pin = false
	assert_eq(SettingsService.get_tutorial_language(), "standard")
	assert_false(TutorialScriptLib.is_orky())
	SettingsService.tutorial_language = "orky"
	assert_true(TutorialScriptLib.is_orky())


func test_set_tutorial_language_clears_pin_and_rejects_junk():
	SettingsService._tutorial_language_harness_pin = true
	SettingsService.set_tutorial_language("standard")
	assert_false(SettingsService._tutorial_language_harness_pin,
		"an explicit choice steps out from under the harness pin")
	assert_eq(SettingsService.get_tutorial_language(), "standard")
	SettingsService.set_tutorial_language("klingon")
	assert_eq(SettingsService.get_tutorial_language(), "standard",
		"invalid values must be refused")


# ------------------------------------------------- blocked-action wording ---

func test_blocked_instruction_speaks_both_voices():
	var saved_active = TutorialManager.active
	var saved_steps = TutorialManager._steps
	var saved_index = TutorialManager.current_step_index
	TutorialManager.active = true
	TutorialManager._steps = [{"id": "s", "prompt": {"text": "t"}, "allow": [], "done": {"ack": true}}]
	TutorialManager.current_step_index = 0
	SettingsService._tutorial_language_harness_pin = false
	SettingsService.tutorial_language = "standard"
	assert_string_contains(TutorialManager._blocked_instruction(), "the tutorial card")
	SettingsService.tutorial_language = "orky"
	assert_string_contains(TutorialManager._blocked_instruction(), "da tutorial card")
	TutorialManager.active = saved_active
	TutorialManager._steps = saved_steps
	TutorialManager.current_step_index = saved_index


# --------------------------------------------------- lesson-file contract ---

func _walk_language_pairs(d: Dictionary, path: String, problems: Array) -> void:
	for k in d.keys():
		var v = d[k]
		if typeof(v) == TYPE_DICTIONARY:
			_walk_language_pairs(v, "%s.%s" % [path, k], problems)
		elif typeof(v) == TYPE_ARRAY:
			for i in range(v.size()):
				if typeof(v[i]) == TYPE_DICTIONARY:
					_walk_language_pairs(v[i], "%s.%s[%d]" % [path, k, i], problems)
		if str(k).ends_with("_orky"):
			var base := str(k).trim_suffix("_orky")
			if not d.has(base):
				problems.append("%s.%s has no '%s' base twin" % [path, k, base])
		elif typeof(v) == TYPE_STRING and d.has(str(k) + "_orky"):
			# The base half of a translated pair must actually be standard.
			var padded := " " + str(v).replace("CALL DA WAAAGH!", "").to_lower() + " "
			for marker in ORKY_MARKERS:
				if padded.contains(marker):
					problems.append("%s.%s still reads orky (%s): %s" % [path, k, marker, str(v).left(60)])
					break


func test_shipped_lessons_carry_both_voices_cleanly():
	for lf in LESSON_FILES:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(lf))
		assert_eq(typeof(parsed), TYPE_DICTIONARY, "%s must parse" % lf)
		var problems: Array = []
		_walk_language_pairs(parsed, lf.get_file(), problems)
		assert_eq(problems.size(), 0, "%s: %s" % [lf.get_file(), ", ".join(PackedStringArray(problems))])
		# And the loader still validates the augmented file.
		var out = TutorialScriptLib.load_lesson(lf)
		assert_true(out.ok, "%s must validate: %s" % [lf, str(out.errors)])


func test_shipped_lessons_render_distinct_voices():
	# The welcome step of T1 must actually read differently per voice.
	var out = TutorialScriptLib.load_lesson("res://data/tutorials/lessons/T1_basics.json")
	assert_true(out.ok)
	var welcome: Dictionary = out.lesson.steps[0]
	var std := str(TutorialScriptLib.body_for_device_lang(welcome, false, false))
	var ork := str(TutorialScriptLib.body_for_device_lang(welcome, false, true))
	assert_string_contains(std, "Basic Training")
	assert_string_contains(ork, "Basic Trainin'")
	assert_ne(std, ork)
	assert_eq(TutorialScriptLib.field_lang(out.lesson, "title", false), "Scouting the Field")
	assert_eq(TutorialScriptLib.field_lang(out.lesson, "title", true), "Scoutin' da Field")

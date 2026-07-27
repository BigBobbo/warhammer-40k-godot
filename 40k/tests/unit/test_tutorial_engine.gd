extends GutTest

# Unit tests for the tutorial engine (PRPs/tutorial_system.md §5.5):
# lesson-file parsing/validation, device-adaptive token rendering, the
# action allow-list matcher, and progress-store round-trips. The windowed
# scenarios tut_t1_basics(.pad).json cover the live player path; these are
# the fast regression net underneath.

const TutorialScriptLib = preload("res://scripts/tutorial/TutorialScript.gd")

var _saved_active: bool
var _saved_lesson: Dictionary
var _saved_steps: Array
var _saved_index: int
var _saved_captured: Dictionary
var _saved_checklist: Array
var _saved_checklist_done: Dictionary


func before_each():
	_saved_active = TutorialManager.active
	_saved_lesson = TutorialManager.current_lesson
	_saved_steps = TutorialManager._steps
	_saved_index = TutorialManager.current_step_index
	_saved_captured = TutorialManager._captured
	_saved_checklist = TutorialManager._checklist
	_saved_checklist_done = TutorialManager._checklist_done


func after_each():
	TutorialManager.active = _saved_active
	TutorialManager.current_lesson = _saved_lesson
	TutorialManager._steps = _saved_steps
	TutorialManager.current_step_index = _saved_index
	TutorialManager._captured = _saved_captured
	TutorialManager._checklist = _saved_checklist
	TutorialManager._checklist_done = _saved_checklist_done


# ------------------------------------------------------------- parsing ----

func test_t1_lesson_file_parses_clean():
	var out = TutorialScriptLib.load_lesson("res://data/tutorials/lessons/T1_basics.json")
	assert_true(out.ok, "shipped T1 lesson must validate: %s" % str(out.errors))
	assert_eq(str(out.lesson.id), "t1_basics")
	assert_gt(out.lesson.steps.size(), 5)


func test_validate_rejects_missing_fields():
	var errors = TutorialScriptLib.validate({"title": "x"})
	assert_gt(errors.size(), 0, "missing id/boot/steps must fail validation")
	var joined = " ".join(errors)
	assert_string_contains(joined, "id")
	assert_string_contains(joined, "steps")


func test_validate_rejects_duplicate_step_ids():
	var lesson = {
		"id": "x", "title": "x", "boot": {"fixture": "f"},
		"steps": [
			{"id": "a", "prompt": {"text": "t"}, "done": {"ack": true}},
			{"id": "a", "prompt": {"text": "t"}, "done": {"ack": true}},
		],
	}
	var errors = TutorialScriptLib.validate(lesson)
	assert_string_contains(" ".join(errors), "duplicate")


# ------------------------------------------------------------ rendering ----

func test_render_glyph_token():
	var out = TutorialScriptLib.render_text("press {rb} now", true)
	assert_string_contains(out, "[b][RB][/b]")


func test_render_keybinding_token_uses_display_name():
	var expected = KeybindingManager.get_key_display_name("rotate_left")
	var out = TutorialScriptLib.render_text("rotate wiv {key:rotate_left}", false)
	assert_string_contains(out, "[b][%s][/b]" % expected)


func test_render_unknown_token_stays_visible():
	var out = TutorialScriptLib.render_text("wot is {bogus_token}?", false)
	assert_string_contains(out, "{bogus_token}")


func test_body_for_device_prefers_device_key():
	var step = {"prompt": {"kbm": "click it", "pad": "press it"}}
	assert_eq(TutorialScriptLib.body_for_device(step, true), "press it")
	assert_eq(TutorialScriptLib.body_for_device(step, false), "click it")
	var shared = {"prompt": {"text": "same everywhere"}}
	assert_eq(TutorialScriptLib.body_for_device(shared, true), "same everywhere")


# ------------------------------------------------------------ allow-list ---

func _arm_fake_step(allow) -> void:
	TutorialManager.active = true
	TutorialManager._steps = [{"id": "s", "prompt": {"text": "t"},
		"allow": allow, "done": {"ack": true}}]
	TutorialManager.current_step_index = 0


func test_gate_inactive_allows_everything():
	TutorialManager.active = false
	assert_true(TutorialManager.is_action_allowed({"type": "END_MOVEMENT"}))


func test_gate_blocks_unlisted_action():
	_arm_fake_step([])
	# Only meaningful while it's the tutorial player's turn.
	if GameState.get_active_player() != 1:
		pass_test("active player is not the tutorial player in this state")
		return
	assert_false(TutorialManager.is_action_allowed({"type": "END_MOVEMENT"}))


func test_gate_allows_listed_action_and_wildcard():
	if GameState.get_active_player() != 1:
		pass_test("active player is not the tutorial player in this state")
		return
	_arm_fake_step(["BEGIN_NORMAL_MOVE"])
	assert_true(TutorialManager.is_action_allowed({"type": "BEGIN_NORMAL_MOVE"}))
	assert_false(TutorialManager.is_action_allowed({"type": "BEGIN_ADVANCE"}))
	_arm_fake_step("*")
	assert_true(TutorialManager.is_action_allowed({"type": "ANYTHING_AT_ALL"}))


func test_gate_implicit_safe_prefix_always_passes():
	if GameState.get_active_player() != 1:
		pass_test("active player is not the tutorial player in this state")
		return
	_arm_fake_step([])
	assert_true(TutorialManager.is_action_allowed({"type": "DECLINE_COMMAND_REROLL"}),
		"DECLINE_* reactive actions must never be gated (soft-lock guard)")


# ------------------------------------------------------------- checklist ---
# The camera step used to advance on the FIRST camera input, so a player who
# tapped one arrow key never discovered the other three or the zoom. It now
# waits on a checklist: every item latches independently and `done.checklist`
# only fires when all of them are ticked.

func _fake_checklist_step(flags: Dictionary) -> Dictionary:
	# Predicates read a Dictionary held in TutorialManager._captured, which the
	# snippet host exposes as `captured` — no live camera needed.
	var items: Array = []
	for key in flags:
		items.append({
			"id": key,
			"label": key,
			"script": "return bool(captured[\"flags\"].get(\"%s\", false))" % key,
		})
	return {"id": "cl", "prompt": {"text": "t"}, "done": {"checklist": true},
		"checklist": {"label": "Try each:", "items": items}}


func test_checklist_waits_for_every_item():
	var flags := {"pan_up": false, "pan_down": false}
	var step := _fake_checklist_step(flags)
	TutorialManager._captured = {"flags": flags}
	TutorialManager._build_checklist(step)
	assert_eq(TutorialManager._checklist.size(), 2)
	assert_false(TutorialManager._checklist_complete(), "nothing used yet")

	flags["pan_up"] = true
	TutorialManager._poll_checklist()
	assert_true(TutorialManager.checklist_state().get("pan_up", false))
	assert_false(TutorialManager._checklist_complete(),
		"one input must NOT be enough — that is the bug this guards")

	flags["pan_down"] = true
	TutorialManager._poll_checklist()
	assert_true(TutorialManager._checklist_complete(), "all items used -> step may advance")
	assert_true(TutorialManager._eval_condition({"checklist": true}, "0"))


func test_checklist_ticks_stay_latched():
	# A pan is momentary: the predicate goes true while the key is held and the
	# tick must survive the key coming back up.
	var flags := {"pan_up": false}
	TutorialManager._captured = {"flags": flags}
	TutorialManager._build_checklist(_fake_checklist_step(flags))
	flags["pan_up"] = true
	TutorialManager._poll_checklist()
	flags["pan_up"] = false
	TutorialManager._poll_checklist()
	assert_true(TutorialManager._checklist_complete(), "a ticked item never un-ticks")


func test_checklist_rebuild_preserves_ticks():
	# Swapping keyboard <-> pad mid-step rebuilds the (device-labelled) list;
	# progress the player already made must not be thrown away.
	var flags := {"pan_up": false, "pan_down": false}
	var step := _fake_checklist_step(flags)
	TutorialManager._captured = {"flags": flags}
	TutorialManager._build_checklist(step)
	flags["pan_up"] = true
	TutorialManager._poll_checklist()
	TutorialManager._build_checklist(step, TutorialManager._checklist_done)
	assert_true(TutorialManager.checklist_state().get("pan_up", false))
	assert_false(TutorialManager.checklist_state().get("pan_down", true))


func test_t1_camera_step_requires_all_six_controls():
	var out = TutorialScriptLib.load_lesson("res://data/tutorials/lessons/T1_basics.json")
	assert_true(out.ok, "shipped T1 lesson must validate: %s" % str(out.errors))
	var camera_step := {}
	for step in out.lesson.steps:
		if str(step.get("id", "")) == "camera":
			camera_step = step
	assert_false(camera_step.is_empty(), "T1 must still have a 'camera' step")
	assert_true(bool(camera_step.get("done", {}).get("checklist", false)),
		"the camera step must gate on the checklist, not on any single nudge")
	var ids: Array = []
	for item in camera_step.get("checklist", {}).get("items", []):
		ids.append(str(item.get("id", "")))
	for wanted in ["pan_up", "pan_down", "pan_left", "pan_right", "zoom_in", "zoom_out"]:
		assert_true(ids.has(wanted), "camera checklist must cover '%s'" % wanted)


func test_validate_rejects_bad_checklist():
	var base := {"id": "x", "title": "x", "boot": {"fixture": "f"}}
	var no_items = base.duplicate(true)
	no_items["steps"] = [{"id": "a", "prompt": {"text": "t"},
		"done": {"checklist": true}, "checklist": {"items": []}}]
	assert_string_contains(" ".join(TutorialScriptLib.validate(no_items)), "non-empty")

	var no_checklist = base.duplicate(true)
	no_checklist["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"checklist": true}}]
	assert_string_contains(" ".join(TutorialScriptLib.validate(no_checklist)), "no 'checklist'")

	var no_script = base.duplicate(true)
	no_script["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"checklist": true},
		"checklist": {"items": [{"id": "i", "label": "l"}]}}]
	assert_string_contains(" ".join(TutorialScriptLib.validate(no_script)), "missing 'script'")


# -------------------------------------------------------------- progress ---

func test_progress_round_trip():
	var lesson_id := "unit_test_lesson"
	TutorialManager._progress.set_value("lessons", lesson_id + "_completed", true)
	assert_true(TutorialManager.is_completed(lesson_id))
	TutorialManager._progress.set_value("lessons", lesson_id + "_completed", false)
	assert_false(TutorialManager.is_completed(lesson_id))


func test_lessons_discovered_from_data_dir():
	TutorialManager._lessons_cache = []
	var lessons = TutorialManager.get_lessons()
	assert_gt(lessons.size(), 0, "T1 must be discoverable")
	assert_eq(str(lessons[0].id), "t1_basics")

extends SceneTree

# Tutorial multi-input checklist (the "'ave a look around" progression fix).
#
# The T1 camera step used to advance on the FIRST camera input the player
# happened to try, so anyone who tapped one key never discovered the other
# three pan directions or the zoom — the reported confusion on both Steam Deck
# and the itch.io build. The step now declares a `checklist`: each item latches
# independently and `done: {"checklist": true}` only fires once every item is
# ticked, with the outstanding ones rendered live on the instructor card.
#
# Checks:
#   A) TutorialScript.validate rejects mis-authored checklists (a `done
#      .checklist` with no items would complete the step instantly; an item
#      with no predicate could never tick).
#   B) The shipped T1 lesson gates its camera step on a checklist covering all
#      six suggested controls, and no longer on a single view-changed predicate.
#   C) TutorialManager latches each item once, refuses to complete until every
#      one is ticked, keeps ticks after the input stops, and preserves them
#      across a device-swap rebuild.
#   D) Main.gd latches real camera input per direction (and from the input, not
#      from the resulting view change — zoom clamps and board edges must not be
#      able to strand a player on an un-tickable box).
#
# The live player path is covered by the windowed scenarios
# tests/scenarios/sp/tut_t1_basics(.pad).json; this is the fast net underneath.
#
# Usage: godot --headless --path . -s tests/test_tutorial_checklist.gd

const TutorialScriptLib = preload("res://scripts/tutorial/TutorialScript.gd")

var passed := 0
var failed := 0


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


# Predicates read a Dictionary parked in TutorialManager._captured, which the
# snippet host exposes to step scripts as `captured` — no live camera needed.
func _fake_step(flag_names: Array) -> Dictionary:
	var items: Array = []
	for name in flag_names:
		items.append({
			"id": name,
			"label": name,
			"script": "return bool(captured[\"flags\"].get(\"%s\", false))" % name,
		})
	return {"id": "cl", "prompt": {"text": "t"}, "done": {"checklist": true},
		"checklist": {"label": "Try each:", "items": items}}


func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_tutorial_checklist ===\n")

	_test_validation()
	_test_shipped_t1_lesson()
	_test_closed_ack_steps()
	_test_latching()
	_test_main_gesture_latch()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


# A: authoring mistakes fail loudly instead of soft-locking or trivialising ----

func _test_validation():
	var base := {"id": "x", "title": "x", "boot": {"fixture": "f"}}

	var empty_items := base.duplicate(true)
	empty_items["steps"] = [{"id": "a", "prompt": {"text": "t"},
		"done": {"checklist": true}, "checklist": {"items": []}}]
	_check("validate rejects an empty checklist",
		" ".join(TutorialScriptLib.validate(empty_items)).contains("non-empty"))

	var no_checklist := base.duplicate(true)
	no_checklist["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"checklist": true}}]
	_check("validate rejects done.checklist with no checklist block",
		" ".join(TutorialScriptLib.validate(no_checklist)).contains("no 'checklist'"))

	var no_script := base.duplicate(true)
	no_script["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"checklist": true},
		"checklist": {"items": [{"id": "i", "label": "l"}]}}]
	_check("validate rejects a checklist item with no predicate",
		" ".join(TutorialScriptLib.validate(no_script)).contains("missing 'script'"))

	var dupe := base.duplicate(true)
	dupe["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"checklist": true},
		"checklist": {"items": [
			{"id": "i", "label": "l", "script": "return true"},
			{"id": "i", "label": "l", "script": "return true"}]}}]
	_check("validate rejects duplicate checklist item ids",
		" ".join(TutorialScriptLib.validate(dupe)).contains("duplicate checklist"))

	var good := base.duplicate(true)
	good["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"checklist": true},
		"checklist": {"items": [{"id": "i", "label": "l", "script": "return true"}]}}]
	_check("validate accepts a well-formed checklist",
		TutorialScriptLib.validate(good).is_empty(),
		str(TutorialScriptLib.validate(good)))


# B: the shipped lesson actually uses it ---------------------------------------

func _test_shipped_t1_lesson():
	var out: Dictionary = TutorialScriptLib.load_lesson("res://data/tutorials/lessons/T1_basics.json")
	_check("shipped T1 lesson validates", out.ok, str(out.errors))
	if not out.ok:
		return
	var camera := {}
	for step in out.lesson.get("steps", []):
		if str(step.get("id", "")) == "camera":
			camera = step
	_check("T1 still has a 'camera' step", not camera.is_empty())
	if camera.is_empty():
		return
	_check("camera step gates on the checklist, not on any single nudge",
		bool(camera.get("done", {}).get("checklist", false)))
	var ids: Array = []
	for item in camera.get("checklist", {}).get("items", []):
		ids.append(str(item.get("id", "")))
	for wanted in ["pan_up", "pan_down", "pan_left", "pan_right", "zoom_in", "zoom_out"]:
		_check("camera checklist covers '%s'" % wanted, ids.has(wanted), str(ids))
	# Entering the step must clear whatever the player did during an earlier
	# step, or a wanderer arrives with boxes pre-ticked and skips the lesson.
	_check("camera step resets the gesture latch on entry",
		str(camera.get("on_enter", {}).get("script", "")).contains("reset_camera_gestures"))


# B2: which ack steps may take the pad's buttons over -------------------------
#
# On a CLOSED ack step (done.ack + an empty allow-list) Ⓐ is rerouted to the
# card's Continue button and LB/RB stop cycling units — the whole point being
# that no board action could succeed there anyway (T1 step 7/13 "READ DA BAR!"
# was an unexplained dead end without it). That reasoning collapses the moment
# a step still allows actions: T7's sign-off is an ack step with allow "*",
# deliberately handing the board back, and taking Ⓐ there would break a step
# whose whole point is that the player is free again. This pins the
# distinction across every shipped lesson.

func _test_closed_ack_steps():
	var tm = root.get_node_or_null("/root/TutorialManager")
	if tm == null:
		_check("TutorialManager autoload present", false)
		return
	_check("a closed ack step (ack + empty allow) qualifies",
		tm._is_closed_ack_step({"done": {"ack": true}, "allow": []}))
	_check("an ack step with allow \"*\" does NOT qualify",
		not tm._is_closed_ack_step({"done": {"ack": true}, "allow": "*"}))
	_check("an ack step with a live allow-list does NOT qualify",
		not tm._is_closed_ack_step({"done": {"ack": true}, "allow": ["END_MOVEMENT"]}))
	_check("a non-ack step never qualifies",
		not tm._is_closed_ack_step({"done": {"action": {"type": "X"}}, "allow": []}))

	# Every shipped lesson: an ack step is claimed only when it really is closed.
	var dir := DirAccess.open("res://data/tutorials/lessons/")
	var files: Array = []
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				files.append(f)
	files.sort()
	_check("shipped lessons found", not files.is_empty(), str(files))
	var open_ack: Array = []
	var closed_ack := 0
	for f in files:
		var out: Dictionary = TutorialScriptLib.load_lesson("res://data/tutorials/lessons/" + f)
		if not out.ok:
			_check("lesson %s validates" % f, false, str(out.errors))
			continue
		for step in out.lesson.get("steps", []):
			if not tm._is_ack_step(step):
				continue
			if tm._is_closed_ack_step(step):
				closed_ack += 1
			else:
				open_ack.append("%s:%s" % [f, str(step.get("id", ""))])
	_check("the shipped lessons still have closed ack steps to protect",
		closed_ack > 0, str(closed_ack))
	_check("T7's sign-off is the only OPEN ack step (it re-opens the board)",
		open_ack == ["T7_command.json:wrap"], str(open_ack))


# C: the engine waits for every item ------------------------------------------

func _test_latching():
	var tm = root.get_node_or_null("/root/TutorialManager")
	if tm == null:
		_check("TutorialManager autoload present", false)
		return
	var saved_captured: Dictionary = tm._captured
	var saved_list: Array = tm._checklist
	var saved_done: Dictionary = tm._checklist_done

	var flags := {"pan_up": false, "pan_down": false}
	var step := _fake_step(["pan_up", "pan_down"])
	tm._captured = {"flags": flags}
	tm._build_checklist(step)
	_check("checklist builds one entry per item", tm._checklist.size() == 2, str(tm._checklist.size()))
	_check("nothing ticked before any input", not tm._checklist_complete())

	flags["pan_up"] = true
	tm._poll_checklist()
	_check("using one control ticks exactly that box",
		tm.checklist_state().get("pan_up", false) and not tm.checklist_state().get("pan_down", true))
	_check("one input does NOT complete the step (the reported bug)",
		not tm._checklist_complete())
	_check("done.checklist stays false while items are outstanding",
		not tm._eval_condition({"checklist": true}, "0"))

	# A pan is momentary — the tick must survive the key coming back up.
	flags["pan_up"] = false
	tm._poll_checklist()
	_check("a ticked item never un-ticks", tm.checklist_state().get("pan_up", false))

	# Device swap mid-step rebuilds the (differently labelled) list.
	tm._build_checklist(step, tm._checklist_done)
	_check("rebuild preserves ticks across a device swap",
		tm.checklist_state().get("pan_up", false) and not tm.checklist_state().get("pan_down", true))

	flags["pan_down"] = true
	tm._poll_checklist()
	_check("step completes once every item is ticked", tm._checklist_complete())
	_check("done.checklist fires only then", tm._eval_condition({"checklist": true}, "0"))

	tm._captured = saved_captured
	tm._checklist = saved_list
	tm._checklist_done = saved_done


# D: Main latches real camera input per direction ------------------------------

func _test_main_gesture_latch():
	var main_script = load("res://scripts/Main.gd")
	var main = main_script.new()
	_check("Main exposes the gesture latch API",
		main.has_method("camera_gesture_used") and main.has_method("note_camera_pan_gesture")
			and main.has_method("reset_camera_gestures"))

	main.note_camera_pan_gesture(Vector2(0, -1))
	_check("pan up latches pan_up only",
		main.camera_gesture_used("pan_up") and not main.camera_gesture_used("pan_down"))
	main.note_camera_pan_gesture(Vector2(1, 1))
	_check("a diagonal legitimately ticks both axes",
		main.camera_gesture_used("pan_right") and main.camera_gesture_used("pan_down"))
	_check("untouched directions stay untouched", not main.camera_gesture_used("pan_left"))
	main.note_camera_gesture("zoom_in")
	_check("zoom latches independently of pan", main.camera_gesture_used("zoom_in"))

	main.reset_camera_gestures()
	_check("reset clears every latch",
		not main.camera_gesture_used("pan_up") and not main.camera_gesture_used("zoom_in"))

	# Latched from the INPUT, not from the resulting view change: zoom clamps at
	# 0.1x/3.0x, and a player sitting at a limit must still be able to tick the
	# box off rather than be stranded on the step.
	var src: String = FileAccess.get_file_as_string("res://scripts/Main.gd")
	var zoom_in_at: int = src.find("is_action_pressed(\"zoom_in\")")
	var zoom_call_at: int = src.find("_zoom_about", zoom_in_at)
	var note_at: int = src.find("note_camera_gesture(\"zoom_in\")", zoom_in_at)
	_check("keyboard zoom_in latches before (and independently of) the clamped _zoom_about",
		zoom_in_at != -1 and note_at != -1 and note_at < zoom_call_at,
		"pressed=%d note=%d zoom_about=%d" % [zoom_in_at, note_at, zoom_call_at])

	main.free()

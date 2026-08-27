extends SceneTree

# T3 "Get Movin'" step 4 (boyz_move_after_disembark): the step never told the
# player the move has to be CONFIRMED.
#
# Reported: after the disembarked Boyz were dragged to their new spot the
# lesson just sat there. The step's done-gate has always been
# CONFIRM_UNIT_MOVE / flags.moved, but the pad body never mentioned the button
# at all and the mouse body buried it in a trailing clause — droppin' models
# looks finished, so players waited for a step that was waiting for them.
#
# The step now (a) names End This Unit's Move in BOTH device bodies, (b) carries
# a live checklist whose second box stays open until the move is locked in, and
# (c) declares `anchor_when` so the spotlight walks off the mob and onto the
# confirm button the moment any model has staged distance.
#
# Checks:
#   A) TutorialScript.validate rejects mis-authored anchor_when entries (one
#      with no predicate would own the ring forever; one with no anchor would
#      blank the spotlight — both strand the player worse than no feature).
#   B) The shipped T3 lesson says the confirm out loud on BOTH devices, in the
#      body AND on the checklist, and still exits via the any-tree rather than
#      the checklist (Remain Stationary must not soft-lock).
#   C) TutorialManager._live_anchor resolves the step's own anchor while no
#      entry is live and the entry's anchor once one is.
#
# The live player path (drag the mob -> ring jumps to the button -> click it)
# is covered by tests/scenarios/sp/tut_t3_get_movin(.pad).json; this is the
# fast net underneath.
#
# Usage: godot --headless --path . -s tests/test_tutorial_confirm_prompt.gd

const TutorialScriptLib = preload("res://scripts/tutorial/TutorialScript.gd")

const CONFIRM_BUTTON := "End This Unit's Move"
const CONFIRM_NODE := "/root/Main/HUD_Right/VBoxContainer/MovementScrollContainer/MovementPanel/Section4_Actions/ActionButtons/ConfirmMoveButton"

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


func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_tutorial_confirm_prompt ===\n")

	_test_anchor_when_validation()
	_test_shipped_t3_step()
	_test_live_anchor()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


# A: authoring mistakes fail loudly -------------------------------------------

func _test_anchor_when_validation():
	var base := {"id": "x", "title": "x", "boot": {"fixture": "f"}}

	var empty := base.duplicate(true)
	empty["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"ack": true},
		"anchor_when": []}]
	_check("validate rejects an empty anchor_when",
		" ".join(TutorialScriptLib.validate(empty)).contains("non-empty array"))

	var no_script := base.duplicate(true)
	no_script["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"ack": true},
		"anchor_when": [{"anchor": {"node": CONFIRM_NODE}}]}]
	_check("validate rejects an anchor_when entry with no predicate",
		" ".join(TutorialScriptLib.validate(no_script)).contains("missing 'script'"))

	var no_anchor := base.duplicate(true)
	no_anchor["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"ack": true},
		"anchor_when": [{"script": "return true"}]}]
	_check("validate rejects an anchor_when entry with no anchor",
		" ".join(TutorialScriptLib.validate(no_anchor)).contains("missing 'anchor' object"))

	var bad_spot := base.duplicate(true)
	bad_spot["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"ack": true},
		"anchor_when": [{"script": "return true", "anchor": {"node": CONFIRM_NODE},
			"spotlight": "blinding"}]}]
	_check("validate rejects a bad anchor_when spotlight",
		" ".join(TutorialScriptLib.validate(bad_spot)).contains("bad spotlight"))

	var good := base.duplicate(true)
	good["steps"] = [{"id": "a", "prompt": {"text": "t"}, "done": {"ack": true},
		"anchor_when": [{"script": "return true", "anchor": {"node": CONFIRM_NODE},
			"spotlight": "soft"}]}]
	_check("validate accepts a well-formed anchor_when",
		TutorialScriptLib.validate(good).is_empty(),
		str(TutorialScriptLib.validate(good)))


# B: the shipped step tells the player to confirm ------------------------------

func _test_shipped_t3_step():
	var out: Dictionary = TutorialScriptLib.load_lesson("res://data/tutorials/lessons/T3_movement.json")
	_check("shipped T3 lesson validates", out.ok, str(out.errors))
	if not out.ok:
		return
	var steps: Array = out.lesson.get("steps", [])
	var step := {}
	var index := -1
	for i in range(steps.size()):
		if str(steps[i].get("id", "")) == "boyz_move_after_disembark":
			step = steps[i]
			index = i
	_check("T3 still has the boyz_move_after_disembark step", not step.is_empty())
	if step.is_empty():
		return
	_check("it is still step four of Get Movin'", index == 3, "index %d" % index)

	# The whole point: BOTH device bodies name the button. The pad body used to
	# stop at "drops da lot".
	for dev in ["kbm", "pad"]:
		var body := str(step.get("prompt", {}).get(dev, ""))
		_check("the %s body names %s" % [dev, CONFIRM_BUTTON],
			body.contains(CONFIRM_BUTTON), body)
	_check("the pad body still advertises the D-pad grab-all reminder",
		str(step.prompt.pad).contains("{dpad}") and str(step.prompt.pad).contains("all 11"),
		str(step.prompt.pad))
	_check("the kbm body still advertises the select-all shortcut",
		str(step.prompt.kbm).contains("{key:select_all}"), str(step.prompt.kbm))
	for dev in ["kbm", "pad"]:
		_check("the %s hint leads with the un-locked move" % dev,
			str(step.get("hint", {}).get(dev, "")).contains(CONFIRM_BUTTON),
			str(step.get("hint", {}).get(dev, "")))

	# A standing on-screen reminder, not just one sentence the player scrolled past.
	var items: Array = step.get("checklist", {}).get("items", [])
	_check("the step carries a two-beat checklist", items.size() == 2, str(items.size()))
	var labels := ""
	for it in items:
		# Both voices of each label: the Tutorial Language setting picks one at
		# runtime, and the shift-beat reminder must exist in whichever is shown.
		for lk in ["label", "label_orky", "pad_label", "pad_label_orky"]:
			labels += str(it.get(lk, "")) + "|"
	_check("a checklist box names the confirm button", labels.contains(CONFIRM_BUTTON), labels)
	_check("the other box covers shifting the mob",
		labels.to_lower().contains("mob") or labels.to_lower().contains("squad"), labels)

	# Remain Stationary never ticks "Shift da mob", so gating the step on the
	# checklist would strand the player who legitimately does not move.
	_check("the step does NOT gate on the checklist",
		not step.get("done", {}).has("checklist"), str(step.get("done", {})))
	var done_types := str(step.get("done", {}))
	_check("the exit is still CONFIRM_UNIT_MOVE / REMAIN_STATIONARY / flags.moved",
		done_types.contains("CONFIRM_UNIT_MOVE") and done_types.contains("REMAIN_STATIONARY")
			and done_types.contains("flags.moved"), done_types)

	# And the ring follows the instruction once the models are down.
	var aw: Array = step.get("anchor_when", [])
	_check("the step declares an anchor_when", aw.size() == 1, str(aw.size()))
	if aw.is_empty():
		return
	_check("it re-points the spotlight at the confirm button",
		str(aw[0].get("anchor", {}).get("node", "")) == CONFIRM_NODE,
		str(aw[0].get("anchor", {})))
	_check("its predicate reads live staged distance, not GameState positions",
		str(aw[0].get("script", "")).contains("get_active_move_data"),
		str(aw[0].get("script", "")))


# C: the engine resolves the live anchor --------------------------------------

func _test_live_anchor():
	var tm = root.get_node_or_null("/root/TutorialManager")
	if tm == null:
		_check("TutorialManager autoload present", false)
		return
	var step := {
		"id": "s", "prompt": {"text": "t"}, "done": {"ack": true},
		"anchor": {"unit": "U_BOYZ_T"}, "spotlight": "soft",
		"anchor_when": [{"script": "return true", "anchor": {"node": CONFIRM_NODE},
			"spotlight": "strict"}],
	}
	var saved: int = tm._anchor_when_index

	tm._anchor_when_index = -1
	var fallback: Dictionary = tm._live_anchor(step)
	_check("no entry live -> the step's own anchor",
		str(fallback.anchor.get("unit", "")) == "U_BOYZ_T" and str(fallback.spotlight) == "soft",
		str(fallback))

	tm._anchor_when_index = 0
	var live: Dictionary = tm._live_anchor(step)
	_check("entry live -> the entry's anchor and spotlight",
		str(live.anchor.get("node", "")) == CONFIRM_NODE and str(live.spotlight) == "strict",
		str(live))

	# An index left over from a step that had entries must never be read against
	# a step that has none (or has fewer) — that would point the ring at nothing.
	var plain := {"id": "s2", "prompt": {"text": "t"}, "done": {"ack": true},
		"anchor": {"unit": "U_GRETCHIN"}, "spotlight": "none"}
	var safe: Dictionary = tm._live_anchor(plain)
	_check("a stale index falls back to the step's own anchor",
		str(safe.anchor.get("unit", "")) == "U_GRETCHIN", str(safe))

	# An entry with no anchor of its own inherits the step's rather than blanking.
	var inherit := step.duplicate(true)
	inherit["anchor_when"] = [{"script": "return true"}]
	tm._anchor_when_index = 0
	var inherited: Dictionary = tm._live_anchor(inherit)
	_check("an entry with no anchor falls back to the step's",
		str(inherited.anchor.get("unit", "")) == "U_BOYZ_T", str(inherited))

	tm._anchor_when_index = saved

extends RefCounted
class_name TutorialScript

# Lesson-file loader/validator + device-adaptive prompt rendering for the
# tutorial system (PRPs/tutorial_system.md §5.3). Lessons are JSON files under
# res://data/tutorials/lessons/.
#
# Prompt token vocabulary (rendered as bold bracketed chips in BBCode):
#   {a} {b} {x} {y} {lb} {rb} {lt} {rt} {ls} {rs} {l3} {r3} {dpad} {menu} {view}
#       -> pad button chip text from GlyphDB (e.g. [RB])
#   {key:<keybinding_id>} -> rebind-aware key name from KeybindingManager
#                            (never hardcode a key: audit X5 collisions)
#   {hint:<glyph_id>}     -> the LIVE label the pad hint bar currently pairs
#                            with that button (PadHintBar.label_for)
#
# NOTE: autoload singletons are not reachable from static funcs (same
# limitation GlyphDB documents), so KeybindingManager/PadHintBar are fetched
# through the MainLoop root.

const GlyphDB := preload("res://scripts/input/GlyphDB.gd")

const VALID_SPOTLIGHT := ["none", "soft", "strict"]
const VALID_DEVICE := ["any", "pad", "kbm"]
# Warn (not fail) above this body length — Fan's fewer-words rule (PRP §1.4).
const BODY_LENGTH_WARN := 220


static func load_lesson(path: String) -> Dictionary:
	var out := {"ok": false, "errors": [], "lesson": {}}
	if not FileAccess.file_exists(path):
		out.errors.append("lesson file not found: %s" % path)
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out.errors.append("cannot open lesson file: %s" % path)
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		out.errors.append("lesson is not a JSON object: %s" % path)
		return out
	var errors := validate(parsed)
	out.errors = errors
	out.ok = errors.is_empty()
	out.lesson = parsed
	return out


static func validate(lesson: Dictionary) -> Array:
	var errors: Array = []
	for field in ["id", "title", "boot", "steps"]:
		if not lesson.has(field):
			errors.append("missing required field '%s'" % field)
	if lesson.has("boot"):
		var boot = lesson.boot
		if typeof(boot) != TYPE_DICTIONARY:
			errors.append("'boot' must be an object")
		elif not boot.has("fixture") and not boot.has("config"):
			errors.append("'boot' needs 'fixture' or 'config'")
	var steps = lesson.get("steps", [])
	if typeof(steps) != TYPE_ARRAY or steps.is_empty():
		errors.append("'steps' must be a non-empty array")
		return errors
	var seen_ids := {}
	for i in range(steps.size()):
		var step = steps[i]
		var tag := "step %d" % i
		if typeof(step) != TYPE_DICTIONARY:
			errors.append("%s: not an object" % tag)
			continue
		var sid := str(step.get("id", ""))
		if sid == "":
			errors.append("%s: missing 'id'" % tag)
		elif seen_ids.has(sid):
			errors.append("%s: duplicate id '%s'" % [tag, sid])
		seen_ids[sid] = true
		if not step.has("prompt") or typeof(step.get("prompt")) != TYPE_DICTIONARY:
			errors.append("%s (%s): missing 'prompt' object" % [tag, sid])
		if not step.has("done") or typeof(step.get("done")) != TYPE_DICTIONARY:
			errors.append("%s (%s): missing 'done' condition" % [tag, sid])
		var spot := str(step.get("spotlight", "soft"))
		if not spot in VALID_SPOTLIGHT:
			errors.append("%s (%s): bad spotlight '%s'" % [tag, sid, spot])
		var dev := str(step.get("device", "any"))
		if not dev in VALID_DEVICE:
			errors.append("%s (%s): bad device '%s'" % [tag, sid, dev])
		var allow = step.get("allow", [])
		if typeof(allow) != TYPE_ARRAY and str(allow) != "*":
			errors.append("%s (%s): 'allow' must be an array or \"*\"" % [tag, sid])
		errors.append_array(_validate_checklist(step, tag, sid))
		errors.append_array(_validate_anchor_when(step, tag, sid))
		errors.append_array(_validate_rewind_when(step, tag, sid, steps, i))
		# Soft guidance: keep instructions short (warning only, never fatal).
		var prompt = step.get("prompt", {})
		if typeof(prompt) == TYPE_DICTIONARY:
			for k in ["kbm", "pad", "text", "kbm_orky", "pad_orky", "text_orky"]:
				if prompt.has(k) and str(prompt[k]).length() > BODY_LENGTH_WARN:
					print("TutorialScript: WARNING %s (%s) '%s' body is %d chars (> %d guideline)" % [
						tag, sid, k, str(prompt[k]).length(), BODY_LENGTH_WARN])
	return errors


# Multi-input steps: `checklist.items` is a list of {id, label, script} the
# player must satisfy one by one before the step advances. A `done.checklist`
# with no items would complete the step instantly, and an item with no predicate
# could never tick, so both are hard errors — a mis-authored checklist soft-locks
# or trivialises the lesson rather than failing loudly at runtime.
static func _validate_checklist(step: Dictionary, tag: String, sid: String) -> Array:
	var errors: Array = []
	var has_done_checklist: bool = bool(step.get("done", {}).get("checklist", false))
	if not step.has("checklist"):
		if has_done_checklist:
			errors.append("%s (%s): done.checklist set but step has no 'checklist'" % [tag, sid])
		return errors
	var spec = step.get("checklist")
	if typeof(spec) != TYPE_DICTIONARY:
		errors.append("%s (%s): 'checklist' must be an object" % [tag, sid])
		return errors
	var items = spec.get("items", [])
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		errors.append("%s (%s): 'checklist.items' must be a non-empty array" % [tag, sid])
		return errors
	var seen := {}
	for j in range((items as Array).size()):
		var item = items[j]
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("%s (%s): checklist item %d is not an object" % [tag, sid, j])
			continue
		var iid := str(item.get("id", ""))
		if iid == "":
			errors.append("%s (%s): checklist item %d missing 'id'" % [tag, sid, j])
		elif seen.has(iid):
			errors.append("%s (%s): duplicate checklist item id '%s'" % [tag, sid, iid])
		seen[iid] = true
		if str(item.get("script", "")) == "":
			errors.append("%s (%s): checklist item '%s' missing 'script'" % [tag, sid, iid])
		if str(item.get("label", "")) == "":
			errors.append("%s (%s): checklist item '%s' missing 'label'" % [tag, sid, iid])
		var idev := str(item.get("device", "any"))
		if not idev in VALID_DEVICE:
			errors.append("%s (%s): checklist item '%s' bad device '%s'" % [tag, sid, iid, idev])
	return errors


# Step-back trigger: `rewind_when` is {step: <earlier step id>, <condition>} and
# returns the lesson to that step when the player undoes what got them here (the
# live case: backing out of the Fight phase's attack panel to pick a different
# unit). The target must exist and must sit BEFORE this step — a forward or
# self-referencing target would skip the lesson on or spin it in place — and the
# entry needs a predicate, or the rewind would fire the instant the step opens.
static func _validate_rewind_when(step: Dictionary, tag: String, sid: String, steps: Array, index: int) -> Array:
	var errors: Array = []
	if not step.has("rewind_when"):
		return errors
	var spec = step.get("rewind_when")
	if typeof(spec) != TYPE_DICTIONARY or (spec as Dictionary).is_empty():
		errors.append("%s (%s): 'rewind_when' must be a non-empty object" % [tag, sid])
		return errors
	var target := str((spec as Dictionary).get("step", ""))
	if target == "":
		errors.append("%s (%s): rewind_when missing 'step' (the id to return to)" % [tag, sid])
	else:
		var target_index := -1
		for k in range(steps.size()):
			if typeof(steps[k]) == TYPE_DICTIONARY and str(steps[k].get("id", "")) == target:
				target_index = k
				break
		if target_index < 0:
			errors.append("%s (%s): rewind_when target step '%s' does not exist" % [tag, sid, target])
		elif target_index >= index:
			errors.append("%s (%s): rewind_when target '%s' must come BEFORE this step" % [tag, sid, target])
	var has_predicate := false
	for key in ["script", "state", "node_visible", "node_hidden", "phase", "any", "all"]:
		if (spec as Dictionary).has(key):
			has_predicate = true
			break
	if not has_predicate:
		errors.append("%s (%s): rewind_when needs a condition (script/state/node_visible/…)" % [tag, sid])
	return errors


# Conditional spotlight targets: `anchor_when` is an ordered list of
# {script, anchor, spotlight} and the first entry whose predicate is true owns
# the ring (TutorialManager._poll_anchor_when). An entry with no predicate would
# win forever and an entry with no anchor would blank the spotlight, so both are
# hard errors — a mis-authored entry silently strands the ring on the wrong
# control, which is exactly the confusion the feature exists to remove.
static func _validate_anchor_when(step: Dictionary, tag: String, sid: String) -> Array:
	var errors: Array = []
	if not step.has("anchor_when"):
		return errors
	var specs = step.get("anchor_when")
	if typeof(specs) != TYPE_ARRAY or (specs as Array).is_empty():
		errors.append("%s (%s): 'anchor_when' must be a non-empty array" % [tag, sid])
		return errors
	for j in range((specs as Array).size()):
		var entry = specs[j]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s (%s): anchor_when %d is not an object" % [tag, sid, j])
			continue
		if str(entry.get("script", "")) == "":
			errors.append("%s (%s): anchor_when %d missing 'script'" % [tag, sid, j])
		if typeof(entry.get("anchor", null)) != TYPE_DICTIONARY or (entry.get("anchor") as Dictionary).is_empty():
			errors.append("%s (%s): anchor_when %d missing 'anchor' object" % [tag, sid, j])
		var spot := str(entry.get("spotlight", "soft"))
		if not spot in VALID_SPOTLIGHT:
			errors.append("%s (%s): anchor_when %d bad spotlight '%s'" % [tag, sid, j, spot])
	return errors


# ---------------------------------------------------------- language --------
#
# Every player-facing lesson string exists in two voices: the plain-English
# base key ("bark", "kbm", "pad", "text", "title", "label", …) and an
# `<key>_orky` twin carrying Da Boss's dialect — the tutorial's original text,
# kept because players can opt back into it (Settings › Gameplay › Tutorial
# Language) and because the windowed tut_* scenarios pin its exact wording.
# Selection is best-effort per string: the wanted voice first, the other as
# fallback, so a step missing one variant still reads correctly for its device.

static func is_orky() -> bool:
	# Same root-fetch as _render_token: autoload singletons are not reachable
	# from static funcs. No SettingsService (headless -s runs) means standard.
	var root := _root()
	if root == null:
		return false
	var svc = root.get_node_or_null("SettingsService")
	if svc == null or not svc.has_method("get_tutorial_language"):
		return false
	return str(svc.get_tutorial_language()) == "orky"


# Language-aware single-field pick: d[key] / d[key + "_orky"] per the setting.
static func field(d: Dictionary, key: String, default_value: String = "") -> String:
	return field_lang(d, key, is_orky(), default_value)


static func field_lang(d: Dictionary, key: String, orky: bool, default_value: String = "") -> String:
	var candidates := [key + "_orky", key] if orky else [key, key + "_orky"]
	for k in candidates:
		if d.has(k):
			return str(d[k])
	return default_value


# The prompt body for the active device: prompt.pad on pad (falling back to
# prompt.text/kbm), prompt.kbm on mouse+keyboard (falling back to prompt.text).
# Device correctness outranks voice — a pad player is better served by an orky
# pad body than a plain-English keyboard one — so the device keys are walked in
# priority order and the voice is resolved per key.
static func body_for_device(step: Dictionary, pad_active: bool) -> String:
	return body_for_device_lang(step, pad_active, is_orky())


static func body_for_device_lang(step: Dictionary, pad_active: bool, orky: bool) -> String:
	var prompt: Dictionary = step.get("prompt", {})
	var device_keys := ["pad", "text", "kbm"] if pad_active else ["kbm", "text", "pad"]
	for k in device_keys:
		if prompt.has(k) or prompt.has(k + "_orky"):
			return field_lang(prompt, k, orky)
	return ""


# Replace glyph/key/hint tokens with bold bracketed chip text. BBCode in the
# source text (e.g. [b]...[/b], [i]...[/i]) passes through untouched.
static func render_text(text: String, pad_active: bool) -> String:
	var re := RegEx.new()
	re.compile("\\{([a-zA-Z0-9_]+?)(?::([a-zA-Z0-9_]+))?\\}")
	var result := ""
	var last := 0
	for m in re.search_all(text):
		result += text.substr(last, m.get_start() - last)
		result += _render_token(m.get_string(1), m.get_string(2), pad_active)
		last = m.get_end()
	result += text.substr(last)
	return result


static func _render_token(kind: String, arg: String, pad_active: bool) -> String:
	var root := _root()
	match kind:
		"key":
			var kbm = root.get_node_or_null("KeybindingManager") if root else null
			var key_name: String = kbm.get_key_display_name(arg) if kbm else arg
			return "[b][%s][/b]" % key_name
		"hint":
			var bar = root.get_node_or_null("PadHintBar") if root else null
			var label: String = bar.label_for(arg) if bar else ""
			if label == "":
				label = GlyphDB.glyph_text(arg)
			return "[b][%s][/b] %s" % [GlyphDB.glyph_text(arg), label]
		_:
			if GlyphDB.GLYPHS.has(kind):
				return "[b][%s][/b]" % GlyphDB.glyph_text(kind)
			# Unknown token: keep it visible so lesson authors notice.
			return "{%s}" % (kind if arg == "" else "%s:%s" % [kind, arg])
	# unreachable


static func _root() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null

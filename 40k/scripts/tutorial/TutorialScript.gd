extends RefCounted
class_name TutorialScript

# Lesson-file loader/validator + device-adaptive prompt rendering for the
# tutorial system (PRPs/tutorial_system.md §5.3). Lessons are JSON files under
# res://data/tutorials/lessons/.
#
# Prompt token vocabulary (rendered as bold bracketed chips in BBCode):
#   {a} {b} {x} {y} {lb} {rb} {lt} {rt} {ls} {rs} {l3} {dpad} {menu} {view}
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
		# Soft guidance: keep instructions short (warning only, never fatal).
		var prompt = step.get("prompt", {})
		if typeof(prompt) == TYPE_DICTIONARY:
			for k in ["kbm", "pad", "text"]:
				if prompt.has(k) and str(prompt[k]).length() > BODY_LENGTH_WARN:
					print("TutorialScript: WARNING %s (%s) '%s' body is %d chars (> %d guideline)" % [
						tag, sid, k, str(prompt[k]).length(), BODY_LENGTH_WARN])
	return errors


# The prompt body for the active device: prompt.pad on pad (falling back to
# prompt.text/kbm), prompt.kbm on mouse+keyboard (falling back to prompt.text).
static func body_for_device(step: Dictionary, pad_active: bool) -> String:
	var prompt: Dictionary = step.get("prompt", {})
	if pad_active:
		for k in ["pad", "text", "kbm"]:
			if prompt.has(k):
				return str(prompt[k])
	else:
		for k in ["kbm", "text", "pad"]:
			if prompt.has(k):
				return str(prompt[k])
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

extends RefCounted
class_name AISuggestionTestCases

# AISuggestionTestCases — turn a reviewed AI suggestion into a regression case.
#
# While reviewing the K breakdown card, the player marks the suggestion
# "Good call" or "Bad call" (with an optional note). That saves:
#   <dir>/<id>.w40ksave  — the exact game state (SaveLoadManager format)
#   <dir>/<id>.json      — format "wh40k_ai_test_case": the verdict, the note,
#                          and the SIGNATURE of what the AI suggested
# into user://ai_test_cases/. Copy a pair into res://tests/ai_cases/ to commit it.
#
# Re-checking (tests/run_ai_test_cases.sh, one windowed scenario per case):
#   verdict "good" → PASS while the AI still makes the same choice
#   verdict "bad"  → PASS once the AI makes a DIFFERENT choice (fixed);
#                    FAIL while it repeats the bad one
#
# A signature is the action type + the unit/target ids it acts on + which
# option the first decision record chose (its key, else its board position,
# else its description). Wording changes in descriptions therefore do not
# break movement cases, which match on the objective's position.

const FORMAT := "wh40k_ai_test_case"
const USER_DIR := "user://ai_test_cases/"
const REPO_DIR := "res://tests/ai_cases/"
const ID_FIELDS := ["unit_id", "actor_unit_id", "target_unit_id", "character_id", "bodyguard_id", "weapon_id", "stratagem_id"]


static func signature(decision: Dictionary) -> Dictionary:
	var sig := {"type": str(decision.get("type", ""))}
	for f in ID_FIELDS:
		if decision.has(f) and str(decision[f]) != "":
			sig[f] = str(decision[f])
	var payload = decision.get("payload", {})
	if payload is Dictionary and payload.get("target_unit_ids", []) is Array and not payload.get("target_unit_ids", []).is_empty():
		var t: Array = (payload.target_unit_ids as Array).duplicate()
		t.sort()
		sig["targets"] = ",".join(PackedStringArray(t))
	var records: Array = _main_records(decision)
	if not records.is_empty():
		var rec: Dictionary = records[0]
		var cands: Array = rec.get("candidates", [])
		var ci := int(rec.get("chosen_index", -1))
		if ci >= 0 and ci < cands.size():
			sig["decision"] = str(rec.get("decision_type", ""))
			sig["choice"] = _choice_id(cands[ci])
	return sig


# Side decisions weighed on the way to the real one (a stratagem the AI held,
# a free rule card) — not what a case is about.
const SIDE_RECORD_TYPES := ["proactive_stratagem", "window_rule", "rule_based", "disembark_check"]

static func _main_records(decision: Dictionary) -> Array:
	var out: Array = []
	for r in decision.get("_ai_decision_records", []):
		if not (str(r.get("decision_type", "")) in SIDE_RECORD_TYPES):
			out.append(r)
	return out


static func _choice_id(cand: Dictionary) -> String:
	if str(cand.get("key", "")) != "":
		return "key:" + str(cand.key)
	var pos = cand.get("pos", [])
	if pos is Array and pos.size() == 2:
		return "pos:%d,%d" % [roundi(float(pos[0])), roundi(float(pos[1]))]
	return "desc:" + str(cand.get("description", ""))


static func same_choice(a: Dictionary, b: Dictionary) -> bool:
	for k in a.keys():
		if str(a[k]) != str(b.get(k, "")):
			return false
	for k in b.keys():
		if not a.has(k):
			return false
	return true


static func save_case(decision: Dictionary, meta: Dictionary, verdict: String, note: String) -> Dictionary:
	"""Save the current game state + this suggestion as a test case.
	Returns {ok, id, json_path, save_path, error}."""
	if decision.is_empty():
		return {"ok": false, "error": "no suggestion to save"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_").replace("-", "")
	var id := "%s_%s_p%s_%s" % [stamp, str(meta.get("phase_name", "phase")).to_lower(), str(meta.get("player", 0)), verdict]
	var save_path := USER_DIR + id + ".w40ksave"
	var slm = Engine.get_main_loop().root.get_node_or_null("/root/SaveLoadManager")
	if slm == null or not slm._save_game_to_path(save_path, {"description": "AI test case " + id, "type": "ai_test_case"}):
		return {"ok": false, "error": "could not write the game state to " + save_path}
	var chosen_desc := ""
	var records: Array = _main_records(decision)
	if not records.is_empty():
		var rec: Dictionary = records[0]
		var ci := int(rec.get("chosen_index", -1))
		if ci >= 0 and ci < (rec.get("candidates", []) as Array).size():
			chosen_desc = str(rec.candidates[ci].get("description", ""))
	var case := {
		"format": FORMAT, "version": 1, "id": id,
		"created": Time.get_datetime_string_from_system(false, true),
		"game_version": _game_version(),
		"verdict": verdict, "note": note,
		"player": meta.get("player", 0), "phase_name": meta.get("phase_name", ""),
		"round": meta.get("round", 0), "difficulty": meta.get("difficulty", ""),
		"difficulty_level": int(meta.get("difficulty_level", -1)),
		# Saved while cycling the card to another unit: re-ask about that unit.
		"focus_unit_id": str(meta.get("focus_unit_id", "")),
		"suggestion": str(decision.get("_ai_description", decision.get("type", ""))),
		"chosen_option": chosen_desc,
		"signature": signature(decision),
		"save_file": id + ".w40ksave",
	}
	var json_path := USER_DIR + id + ".json"
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "could not write " + json_path}
	f.store_string(JSON.stringify(case, "  "))
	f.close()
	print("AISuggestionTestCases: saved %s case %s (%s)" % [verdict, id, case.suggestion])
	DebugLogger.info("AI test case saved", {"id": id, "verdict": verdict, "signature": case.signature})
	return {"ok": true, "id": id, "json_path": ProjectSettings.globalize_path(json_path),
		"save_path": ProjectSettings.globalize_path(save_path)}


static func check_case(json_path: String) -> Dictionary:
	"""Re-ask the AI in the CURRENT game state (the case's save must already be
	loaded) and judge it against the case. Returns {pass, verdict, detail, ...}."""
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return {"pass": false, "detail": "cannot read " + json_path}
	var case = JSON.parse_string(f.get_as_text())
	f.close()
	if not (case is Dictionary) or str(case.get("format", "")) != FORMAT:
		return {"pass": false, "detail": "not a %s file: %s" % [FORMAT, json_path]}
	var ai = Engine.get_main_loop().root.get_node_or_null("/root/AIPlayer")
	var decision: Dictionary = {}
	if ai:
		# Older AI versions (compare mode runs this checker against another
		# git ref) may not take a difficulty override.
		if ai.get_method_argument_count("request_suggestion") >= 2:
			decision = ai.request_suggestion(int(case.get("difficulty_level", -1)), str(case.get("focus_unit_id", "")))
		elif ai.get_method_argument_count("request_suggestion") >= 1:
			decision = ai.request_suggestion(int(case.get("difficulty_level", -1)))
		else:
			decision = ai.request_suggestion()
	var now := signature(decision)
	var was: Dictionary = case.get("signature", {})
	var same := same_choice(was, now)
	var verdict := str(case.get("verdict", "good"))
	var ok: bool = same if verdict == "good" else not same
	var detail := "%s case %s: AI %s — saved: %s | now: %s" % [
		verdict.to_upper(), str(case.get("id", "")),
		("still chooses the same" if same else "now chooses differently"),
		str(case.get("suggestion", "")), str(decision.get("_ai_description", decision.get("type", "(nothing)")))]
	if str(case.get("note", "")) != "":
		detail += " | note: " + str(case.note)
	print("AISuggestionTestCases: %s %s" % ["PASS" if ok else "FAIL", detail])
	return {"pass": ok, "verdict": verdict, "same": same, "detail": detail,
		"saved_signature": was, "current_signature": now,
		"now_description": str(decision.get("_ai_description", decision.get("type", ""))),
		"now_options": _top_options(decision, 4)}


static func _top_options(decision: Dictionary, n: int) -> Array:
	"""The main decision's best-scored options, for compare reports."""
	var out: Array = []
	var recs: Array = _main_records(decision)
	if recs.is_empty():
		return out
	var cands: Array = (recs[0].get("candidates", []) as Array).duplicate()
	var chosen := int(recs[0].get("chosen_index", -1))
	var picked: Dictionary = cands[chosen] if chosen >= 0 and chosen < cands.size() else {}
	cands.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	for c in cands.slice(0, n):
		out.append({"option": str(c.get("description", "")), "score": snappedf(float(c.get("score", 0.0)), 0.01),
			"picked": c == picked})
	return out


static func check_case_json(json_path: String) -> String:
	"""check_case as one JSON line — what the runner parses."""
	return JSON.stringify(check_case(json_path))


static func _game_version() -> String:
	var f := FileAccess.open("res://data/version_history.json", FileAccess.READ)
	if f == null:
		return ""
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary and d.get("releases", []) is Array and not d.releases.is_empty():
		return str(d.releases[0].get("version", ""))
	return ""

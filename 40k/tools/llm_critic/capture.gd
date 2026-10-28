# LLM critic capture — sent over the MCP bridge as one execute_script call
# (multiline). The bridge wraps this under `func _run(node, tree):`, so no
# func defs; straight-line code + return. critic.py substitutes __RUN_DIR__
# (a user:// path ending in "/") and __ID__ before sending.
#
# Asks the AI what it would do RIGHT NOW (AIPlayer.request_suggestion — the
# same call the K card makes, Competitive difficulty, pure preview: nothing is
# dispatched and the live AI's planning caches/RNG are restored), then saves
# the exact game state next to an AI test case JSON (AISuggestionTestCases
# format, verdict "pending") so a flagged decision can be loaded in-game and
# promoted to a regression case. Returns a compact review bundle.
# Positions are converted from board px to inches (px / 40), matching
# snapshot.gd.
var run_dir := "__RUN_DIR__"
var case_id := "__ID__"
var decision: Dictionary = AIPlayer.request_suggestion()
var meta: Dictionary = AIPlayer.last_suggestion_meta.duplicate(true)
if decision.is_empty():
	return {"skipped": "empty", "reason": str(meta.get("empty_reason", ""))}
var main_recs: Array = AISuggestionTestCases._main_records(decision)
if main_recs.is_empty():
	return {"skipped": "no_records", "type": str(decision.get("type", "")), "description": str(decision.get("_ai_description", ""))}
var rec: Dictionary = main_recs[0]
var cands: Array = rec.get("candidates", [])
if cands.size() < 2:
	return {"skipped": "single_option", "type": str(decision.get("type", "")), "description": str(decision.get("_ai_description", ""))}
# shot_prep.gd draws the board overlay for this exact decision.
tree.root.set_meta("llm_critic_decision", decision)
# Line of sight + distance from the acting unit to every enemy unit on the
# board, with the same predicate target eligibility uses (unit_sight_line).
var actor_id := str(decision.get("actor_unit_id", decision.get("unit_id", rec.get("unit_id", ""))))
var los := []
var snap_board: Dictionary = GameState.create_snapshot(false)
var actor_u = GameState.get_unit(actor_id)
if typeof(actor_u) == TYPE_DICTIONARY and not actor_u.is_empty():
	var actor_owner := int(actor_u.get("owner", 0))
	var centroid := func(u) -> Variant:
		var s := Vector2.ZERO
		var n := 0
		for mm in u.get("models", []):
			var pos = mm.get("position", null) if mm.get("alive", true) else null
			if pos is Vector2:
				s += pos
				n += 1
			elif pos is Dictionary and pos.has("x"):
				s += Vector2(float(pos.x), float(pos.y))
				n += 1
		return s / n if n > 0 else null
	var ac = centroid.call(actor_u)
	if ac != null:
		for uid in GameState.state.get("units", {}).keys():
			var u = GameState.state.units[uid]
			if int(u.get("owner", 0)) == actor_owner:
				continue
			var c = centroid.call(u)
			if c == null:
				continue
			var sl: Dictionary = RulesEngine.unit_sight_line(actor_id, uid, snap_board, false)
			los.append({"enemy": GameState.get_unit_display_name(uid), "id": uid,
				"has_los": bool(sl.get("has_los", false)),
				"centroid_dist_in": snappedf((ac as Vector2).distance_to(c) / 40.0, 0.1)})
var chosen_i := int(rec.get("chosen_index", -1))
var picked: Dictionary = cands[chosen_i] if chosen_i >= 0 and chosen_i < cands.size() else {}
var sorted_c: Array = cands.duplicate()
sorted_c.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
var options := []
for c in sorted_c.slice(0, 8):
	var o := {"option": str(c.get("description", "")), "score": snappedf(float(c.get("score", 0.0)), 0.01), "chosen": c == picked}
	var sb = c.get("score_breakdown", {})
	if sb is Dictionary and not sb.is_empty():
		var terms := {}
		for k in sb.keys():
			var v = sb[k]
			terms[k] = snappedf(float(v), 0.01) if (v is float or v is int) else v
		o["score_terms"] = terms
	var pos = c.get("pos", null)
	if pos is Array and pos.size() == 2:
		o["pos_in"] = [snappedf(float(pos[0]) / 40.0, 0.1), snappedf(float(pos[1]) / 40.0, 0.1)]
	options.append(o)
var ctx: Dictionary = (rec.get("context", {}) as Dictionary).duplicate(true)
var upos = ctx.get("unit_pos", null)
if upos is Array and upos.size() == 2:
	ctx["unit_pos_in"] = [snappedf(float(upos[0]) / 40.0, 0.1), snappedf(float(upos[1]) / 40.0, 0.1)]
	ctx.erase("unit_pos")
# Save the position + a pending test case (promoted to "bad" after review).
DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir))
var save_path := run_dir + case_id + ".w40ksave"
# The sim's game_config makes both seats AI, so on reload the AI would act
# before anyone could press K (or the case checker could re-ask), and the
# position would no longer be this decision. Save it as the K card sees it:
# the deciding seat HUMAN, the other AI, not a sim game. Restored right after.
var gc_meta: Dictionary = GameState.state.get("meta", {})
var gc_saved = (gc_meta.get("game_config", {}) as Dictionary).duplicate(true)
var gc: Dictionary = (gc_saved as Dictionary).duplicate(true)
var decider := int(meta.get("player", 0))
gc["player1_type"] = "HUMAN" if decider == 1 else "AI"
gc["player2_type"] = "HUMAN" if decider == 2 else "AI"
gc["plan_sim"] = false
gc_meta["game_config"] = gc
var saved_ok: bool = SaveLoadManager._save_game_to_path(save_path, {"description": "LLM critic " + case_id, "type": "ai_test_case"})
gc_meta["game_config"] = gc_saved
if not saved_ok:
	return {"error": "could not write " + save_path}
var case := {
	"format": AISuggestionTestCases.FORMAT, "version": 1, "id": case_id,
	"created": Time.get_datetime_string_from_system(false, true),
	"game_version": AISuggestionTestCases._game_version(),
	"verdict": "pending", "note": "",
	"player": meta.get("player", 0), "phase_name": meta.get("phase_name", ""),
	"round": meta.get("round", 0), "difficulty": meta.get("difficulty", ""),
	"difficulty_level": int(meta.get("difficulty_level", -1)),
	"focus_unit_id": str(meta.get("focus_unit_id", "")),
	"suggestion": str(decision.get("_ai_description", decision.get("type", ""))),
	"chosen_option": str(picked.get("description", "")),
	"signature": AISuggestionTestCases.signature(decision),
	"save_file": case_id + ".w40ksave",
	"source": "llm_critic",
}
var f := FileAccess.open(run_dir + case_id + ".json", FileAccess.WRITE)
f.store_string(JSON.stringify(case, "  "))
f.close()
DebugLogger.info("LLM critic captured suggestion", {"id": case_id, "phase": meta.get("phase_name", ""), "suggestion": case.suggestion})
return {
	"id": case_id,
	"player": meta.get("player", 0), "phase": meta.get("phase_name", ""), "round": meta.get("round", 0),
	"suggestion": case.suggestion,
	"action_type": str(decision.get("type", "")),
	"decision_type": str(rec.get("decision_type", "")),
	"unit_name": str(rec.get("unit_name", "")),
	"unit_id": str(rec.get("unit_id", "")),
	"context": ctx,
	"line_of_sight": los,
	"options": options,
	"options_total": cands.size(),
	"ai_reasoning": decision.get("_ai_thinking_steps", []),
	"case_json": ProjectSettings.globalize_path(run_dir + case_id + ".json"),
	"save_path": ProjectSettings.globalize_path(save_path),
}

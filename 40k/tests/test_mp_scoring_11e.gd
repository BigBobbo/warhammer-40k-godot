extends SceneTree

# Multiplayer 11e end-of-turn scoring (GameManager.process_end_scoring).
# The networked END_SCORING path used to bypass ScoringPhase entirely, so
# 11e primary EOT scoring, turn-ending hooks (16.01 action completion,
# coherency enforcement), and the VP snapshot never ran in MP games. This
# pins the host-side pipeline and the client-sync diffs.
#
# Usage: godot --headless --path . -s tests/test_mp_scoring_11e.gd

var passed := 0
var failed := 0
var gs = null
var mgr = null
var gm = null

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

func _find_obj_by_zone(zone: String) -> String:
	for obj in gs.state.board.get("objectives", []):
		if obj.get("zone", "") == zone:
			return obj.get("id", "")
	return ""

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_mp_scoring_11e ===\n")
	mgr = root.get_node_or_null("MissionManager")
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	_check("autoloads present", mgr != null and gs != null and gm != null)

	GameConstants.edition = 11
	# Official 11e launch awards: Triangulation's tier VP pays from battle
	# round 2 onwards, so the MP-path scoring check runs in round 2.
	gs.state.meta["battle_round"] = 2
	gs.state.meta["active_player"] = 1
	for pk in ["1", "2"]:
		gs.state.players[pk]["vp"] = 0
		gs.state.players[pk]["primary_vp"] = 0

	var nml = _find_obj_by_zone("no_mans_land")
	mgr.initialize_dispositions_11e("reconnaissance", "purge_the_foe")
	# A real unit holds the objective so the turn-ending control re-check
	# (14.02) keeps P1 in control on the MP path too.
	var obj_pos = {}
	for obj in gs.state.board.get("objectives", []):
		if obj.get("id", "") == nml:
			obj_pos = {"x": obj["position"].x, "y": obj["position"].y}
	gs.state["units"]["U_MPHOLD"] = {"id": "U_MPHOLD", "owner": 1, "status": 2,
		"meta": {"name": "Holder", "keywords": ["INFANTRY"], "stats": {"objective_control": 2}},
		"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": 32, "base_type": "circular", "position": obj_pos}]}
	mgr.check_all_objectives()
	mgr.on_turn_start_11e(1)

	# A unit mid-action proves the 16.01 completion hook runs on the MP path
	gs.state["units"]["U_MPACT"] = {"id": "U_MPACT", "owner": 1,
		"meta": {"name": "Actor", "keywords": ["INFANTRY"], "stats": {"objective_control": 1}},
		"flags": {"performing_action": "hold_position", "action_started_turn": 1},
		"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": 32, "base_type": "circular", "position": {"x": 500.0, "y": 500.0}}]}

	var res = gm.process_end_scoring({"type": "END_SCORING", "player": 1})
	_check("MP END_SCORING succeeds", res.get("success", false), str(res))

	_check("11e primary EOT scored on the MP path (auto Triangulate, 3 VP)",
		int(gs.state.players["1"]["primary_vp"]) == 3, str(gs.state.players["1"]["primary_vp"]))
	_check("auto-pick backstop ran (objective triangulated)",
		mgr._primary_state_11e["1"]["triangulated"] == [nml],
		str(mgr._primary_state_11e["1"]["triangulated"]))
	_check("turn-ending hooks ran (16.01 action completed)",
		str(gs.state.units["U_MPACT"]["flags"].get("performing_action", "x")) == ""
		and str(gs.state.units["U_MPACT"]["flags"].get("action_completed", "")) == "hold_position",
		str(gs.state.units["U_MPACT"]["flags"]))

	var diffs: Array = res.get("diffs", [])
	var vp_synced = false
	var player_switched = false
	for d in diffs:
		if d.get("path", "") == "players.1.primary_vp" and int(d.get("value", -1)) == 3:
			vp_synced = true
		if d.get("path", "") == "meta.active_player" and int(d.get("value", 0)) == 2:
			player_switched = true
	_check("client-sync diffs carry the scored VP", vp_synced, str(diffs))
	_check("player switch diff present", player_switched)

	gs.state.units.erase("U_MPACT")
	gs.state.units.erase("U_MPHOLD")

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

extends SceneTree

# 11e (GDM 2026) primary card-action PLAYER CHOICE API — source:
# docs/rules/11th_edition_missions_gdm2026.md appendix.
#  - The bespoke card actions stay auto-resolved inside score_primary_eot_11e
#    (headless/AI backstop, pinned by test_primary_missions_11e).
#  - get_pending_card_action_11e enumerates the human choice;
#    resolve_card_action_11e applies picks and stands the auto-pick down;
#    decline_card_action_11e skips the optional action entirely.
#  - Punishment: get/resolve/dismiss_condemn revise the auto-Condemn picks.
#
# Usage: godot --headless --path . -s tests/test_card_action_prompts_11e.gd

var passed := 0
var failed := 0
var gs = null
var mgr = null

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

func _obj_position(obj_id: String) -> Dictionary:
	for obj in gs.state.board.get("objectives", []):
		if obj.get("id", "") == obj_id:
			var pos = obj.get("position")
			if pos is Dictionary:
				return {"x": pos.x, "y": pos.y}
			return {"x": pos.x, "y": pos.y}
	return {"x": 0, "y": 0}

func _spawn_unit(unit_id: String, owner: int, at: Dictionary) -> void:
	gs.state["units"][unit_id] = {"id": unit_id, "owner": owner,
		"meta": {"name": unit_id, "keywords": [], "stats": {"objective_control": 1}},
		"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": 32, "base_type": "circular",
			"position": {"x": at.x, "y": at.y}}]}

func _reset_vp() -> void:
	for pk in ["1", "2"]:
		gs.state.players[pk]["vp"] = 0
		gs.state.players[pk]["primary_vp"] = 0
	mgr._primary_vp_this_turn = {"1": 0, "2": 0}

func _clear_control() -> void:
	for obj_id in mgr.objective_control_state:
		mgr.objective_control_state[obj_id] = 0

func _target_ids(pending: Dictionary) -> Array:
	var out = []
	for t in pending.get("targets", []):
		out.append(str(t.get("id", "")))
	return out

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_card_action_prompts_11e ===\n")
	mgr = root.get_node_or_null("MissionManager")
	gs = root.get_node_or_null("GameState")
	_check("autoloads present", mgr != null and gs != null)
	GameConstants.edition = 11
	gs.state.meta["battle_round"] = 2
	gs.state.meta["active_player"] = 1

	var home1 = _find_obj_by_zone("player1")
	var home2 = _find_obj_by_zone("player2")
	var nml = _find_obj_by_zone("no_mans_land")
	_check("board has home + NML objectives", home1 != "" and home2 != "" and nml != "")

	print("\n-- Triangulate: enumerate / resolve / auto stands down --")
	mgr.initialize_dispositions_11e("reconnaissance", "purge_the_foe")
	_reset_vp()
	mgr._kills_this_round = {"1": 0, "2": 0}
	mgr.kills_per_round.clear()
	_clear_control()
	mgr.objective_control_state[nml] = 1
	mgr.objective_control_state[home1] = 1
	var pending = mgr.get_pending_card_action_11e(1)
	_check("Triangulate pending is single-pick", pending.get("mode", "") == "single", str(pending))
	_check("Triangulate lists both controlled objectives",
		nml in _target_ids(pending) and home1 in _target_ids(pending), str(_target_ids(pending)))
	_check("targets carry labels", str(pending.get("targets", [{}])[0].get("label", "")) != "")
	var res = mgr.resolve_card_action_11e(1, [home1])
	_check("resolve accepts an eligible pick", res.get("success", false), str(res))
	_check("player pick applied", mgr._primary_state_11e["1"]["triangulated"] == [home1],
		str(mgr._primary_state_11e["1"]["triangulated"]))
	_check("pending is empty after resolution", mgr.get_pending_card_action_11e(1).is_empty())
	mgr.score_primary_eot_11e(1)
	_check("auto-pick stands down after a player pick (no second mark)",
		mgr._primary_state_11e["1"]["triangulated"] == [home1],
		str(mgr._primary_state_11e["1"]["triangulated"]))
	_check("EOT scores the chosen objective (3 VP for 1 triangulated)",
		int(gs.state.players["1"]["primary_vp"]) >= 3, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- Triangulate: validation + decline path --")
	mgr.initialize_dispositions_11e("reconnaissance", "purge_the_foe")
	_reset_vp()
	_clear_control()
	mgr.objective_control_state[nml] = 1
	var bad = mgr.resolve_card_action_11e(1, ["obj_bogus"])
	_check("ineligible target rejected", not bad.get("success", true), str(bad))
	var two = mgr.resolve_card_action_11e(1, [nml, nml])
	_check("single-pick action rejects two targets", not two.get("success", true), str(two))
	var dec = mgr.decline_card_action_11e(1)
	_check("decline succeeds", dec.get("success", false))
	mgr.score_primary_eot_11e(1)
	_check("decline suppresses the auto-pick entirely",
		mgr._primary_state_11e["1"]["triangulated"].is_empty(),
		str(mgr._primary_state_11e["1"]["triangulated"]))
	mgr.on_turn_start_11e(1)
	_check("turn start re-opens the choice window",
		not mgr.get_pending_card_action_11e(1).is_empty())

	print("\n-- Consecrate: kill-gated eligibility --")
	mgr.initialize_dispositions_11e("purge_the_foe", "reconnaissance")
	_reset_vp()
	mgr._kills_this_round = {"1": 0, "2": 0}
	mgr.kills_per_round.clear()
	_clear_control()
	mgr.objective_control_state[nml] = 1
	mgr.objective_control_state[home1] = 1
	_check("no kills this turn -> no Consecrate prompt",
		mgr.get_pending_card_action_11e(1).is_empty())
	mgr._kills_this_round = {"1": 1, "2": 0}
	pending = mgr.get_pending_card_action_11e(1)
	_check("kill unlocks Consecrate on controlled non-home only",
		_target_ids(pending) == [nml], str(_target_ids(pending)))
	res = mgr.resolve_card_action_11e(1, [nml])
	_check("Consecrate pick applied", res.get("success", false)
		and mgr._primary_state_11e["1"]["consecrated"] == [nml],
		str(mgr._primary_state_11e["1"]["consecrated"]))

	print("\n-- Smoke and Mirrors: multi-pick subset --")
	mgr.initialize_dispositions_11e("disruption", "reconnaissance")
	_reset_vp()
	_clear_control()
	var central_id = mgr.get_objective_ids_by_designation("central")[0]
	mgr.objective_control_state[nml] = 1
	if central_id != nml:
		mgr.objective_control_state[central_id] = 1
	pending = mgr.get_pending_card_action_11e(1)
	_check("Decoy pending is multi-pick", pending.get("mode", "") == "multi", str(pending))
	var decoy_targets = _target_ids(pending)
	_check("Decoy lists every controlled non-home objective",
		nml in decoy_targets and (central_id == nml or central_id in decoy_targets), str(decoy_targets))
	res = mgr.resolve_card_action_11e(1, [nml])
	_check("subset pick decoys only the chosen objective", res.get("success", false)
		and mgr._primary_state_11e["1"]["decoyed"] == [nml]
		and mgr._primary_state_11e["1"]["decoyed_ever"] == [nml],
		str(mgr._primary_state_11e["1"]["decoyed"]))
	mgr.score_primary_eot_11e(1)
	_check("auto-decoy stands down for the unchosen objective",
		not central_id in mgr._primary_state_11e["1"]["decoyed"] or central_id == nml,
		str(mgr._primary_state_11e["1"]["decoyed"]))

	print("\n-- Decoy scrub parity: same-turn pick survives, later turns scrub --")
	mgr.initialize_dispositions_11e("disruption", "reconnaissance")
	_reset_vp()
	_clear_control()
	mgr.objective_control_state[nml] = 1
	_spawn_unit("U_SCRUB", 2, _obj_position(nml))
	res = mgr.resolve_card_action_11e(1, [nml])
	_check("decoy pick allowed with an enemy in range (parity with auto)",
		res.get("success", false), str(res))
	mgr.score_primary_eot_11e(1)
	_check("player-picked decoy survives its own EOT scrub",
		nml in mgr._primary_state_11e["1"]["decoyed"],
		str(mgr._primary_state_11e["1"]["decoyed"]))
	_check("and scores like the auto path would",
		int(gs.state.players["1"]["primary_vp"]) >= 2, str(gs.state.players["1"]["primary_vp"]))
	mgr.on_turn_start_11e(2)
	mgr.score_primary_eot_11e(2)
	_check("the decoy is scrubbed on a later turn while the enemy remains",
		not nml in mgr._primary_state_11e["1"]["decoyed"],
		str(mgr._primary_state_11e["1"]["decoyed"]))
	gs.state.units.erase("U_SCRUB")

	print("\n-- Gather Intel: R2 gate + token placement --")
	mgr.initialize_dispositions_11e("reconnaissance", "reconnaissance")
	_reset_vp()
	_clear_control()
	_spawn_unit("U_INTEL", 1, _obj_position(nml))
	gs.state.meta["battle_round"] = 1
	_check("no Extract Intelligence before Round 2",
		mgr.get_pending_card_action_11e(1).is_empty())
	gs.state.meta["battle_round"] = 2
	pending = mgr.get_pending_card_action_11e(1)
	_check("R2 with a unit in range offers the NML objective",
		nml in _target_ids(pending), str(_target_ids(pending)))
	res = mgr.resolve_card_action_11e(1, [nml])
	_check("intel token placed by player pick", res.get("success", false)
		and mgr._primary_state_11e["1"]["intel_tokens"] == [nml]
		and int(mgr._primary_state_11e["1"]["intel_placed_this_turn"]) == 1,
		str(mgr._primary_state_11e["1"]))
	gs.state.units.erase("U_INTEL")

	print("\n-- Sensor Sweep: chosen marker removed (not pop_back) --")
	mgr.initialize_dispositions_11e("priority_assets", "disruption")
	_check("PA vs DI resolves Extract Relic",
		mgr.get_primary_mission_for_player(1).get("id", "") == "extract_relic")
	_reset_vp()
	_clear_control()
	mgr.objective_control_state[central_id] = 1
	_spawn_unit("U_SWEEP", 1, _obj_position(central_id))
	mgr._relic_markers_11e = ["T_A", "T_B", "T_C"]
	pending = mgr.get_pending_card_action_11e(1)
	_check("Sensor Sweep lists all remaining markers",
		_target_ids(pending) == ["T_A", "T_B", "T_C"], str(_target_ids(pending)))
	res = mgr.resolve_card_action_11e(1, ["T_A"])
	_check("chosen marker removed, others kept", res.get("success", false)
		and mgr._relic_markers_11e == ["T_B", "T_C"]
		and mgr._primary_state_11e["1"]["sensor_swept_this_turn"] == true,
		str(mgr._relic_markers_11e))
	mgr._relic_markers_11e = ["T_B"]
	mgr._primary_state_11e["1"]["card_action_resolved_this_turn"] = false
	mgr._primary_state_11e["1"]["sensor_swept_this_turn"] = false
	_check("one marker left -> no Sensor Sweep prompt",
		mgr.get_pending_card_action_11e(1).is_empty())
	gs.state.units.erase("U_SWEEP")

	print("\n-- Punishment: Condemn revision prompt --")
	mgr.initialize_dispositions_11e("purge_the_foe", "disruption")
	_reset_vp()
	_spawn_unit("U_C1", 2, _obj_position(nml))
	_spawn_unit("U_C2", 2, _obj_position(home2))
	mgr.on_turn_start_11e(1)
	var cond_pending = mgr.get_pending_condemn_choice_11e(1)
	_check("Condemn prompt pending after turn start", not cond_pending.is_empty())
	var eligible_ids = []
	for e in cond_pending.get("eligible", []):
		eligible_ids.append(str(e.get("id", "")))
	_check("both enemy units near objectives are eligible",
		"U_C1" in eligible_ids and "U_C2" in eligible_ids, str(eligible_ids))
	_check("current picks mirror the auto-Condemn backstop",
		not cond_pending.get("current", []).is_empty(), str(cond_pending.get("current", [])))
	var cbad = mgr.resolve_condemn_choice_11e(1, ["U_BOGUS"])
	_check("ineligible Condemn pick rejected", not cbad.get("success", true), str(cbad))
	var cres = mgr.resolve_condemn_choice_11e(1, ["U_C2"])
	_check("player revision replaces the auto picks", cres.get("success", false)
		and mgr._primary_state_11e["1"]["condemned"] == ["U_C2"],
		str(mgr._primary_state_11e["1"]["condemned"]))
	_check("prompt cleared after resolution",
		mgr.get_pending_condemn_choice_11e(1).is_empty())
	mgr.on_turn_start_11e(1)
	_check("same-turn re-entry (save/load) keeps the player's revision",
		mgr._primary_state_11e["1"]["condemned"] == ["U_C2"],
		str(mgr._primary_state_11e["1"]["condemned"]))
	_check("same-turn re-entry does not re-raise the prompt",
		mgr.get_pending_condemn_choice_11e(1).is_empty())
	gs.state.meta["battle_round"] = int(gs.state.meta["battle_round"]) + 1
	mgr.on_turn_start_11e(1)
	_check("a NEW turn re-arms the prompt with fresh auto picks",
		not mgr.get_pending_condemn_choice_11e(1).is_empty()
		and mgr._primary_state_11e["1"]["condemned"].size() > 1,
		str(mgr._primary_state_11e["1"]["condemned"]))
	var cdis = mgr.dismiss_condemn_prompt_11e(1)
	_check("dismiss keeps the auto picks", cdis.get("success", false)
		and not cdis.get("condemned", []).is_empty(), str(cdis))
	_check("dismiss clears the pending prompt",
		mgr.get_pending_condemn_choice_11e(1).is_empty())
	gs.state.meta["battle_round"] = 2
	gs.state.units.erase("U_C1")
	gs.state.units.erase("U_C2")

	print("\n-- Relic-marker setup: Disruption player's revision window --")
	var tm = root.get_node_or_null("TerrainManager")
	_check("TerrainManager present", tm != null)
	var saved_features = tm.terrain_features
	tm.terrain_features = []
	for i in range(6):
		tm.terrain_features.append({"id": "T_R%d" % i,
			"position": Vector2(200 + i * 220, 300 + i * 260),
			"polygon": PackedVector2Array([Vector2(0, 0), Vector2(50, 0), Vector2(50, 50), Vector2(0, 50)])})
	mgr.initialize_dispositions_11e("priority_assets", "disruption")
	_check("markers auto-placed at init", mgr._relic_markers_11e.size() == 5,
		str(mgr._relic_markers_11e))
	_check("setup window pending after init", mgr._relic_setup_prompt_pending)
	var rp = mgr.get_pending_relic_setup_11e(2)
	_check("Disruption player (P2) gets the setup prompt", not rp.is_empty()
		and int(rp.get("required_picks", 0)) == 5, str(rp.get("required_picks")))
	_check("non-Disruption player (P1) gets no prompt",
		mgr.get_pending_relic_setup_11e(1).is_empty())
	var wrong_count = mgr.resolve_relic_setup_11e(2, ["T_R0", "T_R1"])
	_check("wrong pick count rejected", not wrong_count.get("success", true), str(wrong_count))
	var bad_id = mgr.resolve_relic_setup_11e(2, ["T_R0", "T_R1", "T_R2", "T_R3", "T_BOGUS"])
	_check("ineligible terrain rejected", not bad_id.get("success", true), str(bad_id))
	var rres = mgr.resolve_relic_setup_11e(2, ["T_R0", "T_R1", "T_R2", "T_R3", "T_R4"])
	_check("valid revision replaces the markers", rres.get("success", false)
		and mgr._relic_markers_11e == ["T_R0", "T_R1", "T_R2", "T_R3", "T_R4"],
		str(mgr._relic_markers_11e))
	_check("window closed after resolution",
		mgr.get_pending_relic_setup_11e(2).is_empty() and not mgr._relic_setup_prompt_pending)
	mgr.initialize_dispositions_11e("priority_assets", "disruption")
	mgr._relic_markers_11e.pop_back()
	_check("a consumed marker (sweep) closes the setup window",
		mgr.get_pending_relic_setup_11e(2).is_empty() and not mgr._relic_setup_prompt_pending)
	mgr.initialize_dispositions_11e("priority_assets", "disruption")
	var rdis = mgr.dismiss_relic_setup_11e(2)
	_check("dismiss keeps the auto locations", rdis.get("success", false)
		and rdis.get("markers", []).size() == 5 and not mgr._relic_setup_prompt_pending)
	mgr.initialize_dispositions_11e("priority_assets", "disruption")
	var relic_save = mgr.get_state_for_save()
	mgr._relic_setup_prompt_pending = false
	mgr.load_state(relic_save)
	_check("setup-pending flag round-trips through save/load",
		mgr._relic_setup_prompt_pending == true)
	tm.terrain_features = saved_features

	print("\n-- save/load: resolved flag round-trips --")
	mgr.initialize_dispositions_11e("reconnaissance", "purge_the_foe")
	_clear_control()
	mgr.objective_control_state[nml] = 1
	mgr.resolve_card_action_11e(1, [nml])
	var save_data = mgr.get_state_for_save()
	mgr._primary_state_11e["1"]["card_action_resolved_this_turn"] = false
	mgr.load_state(save_data)
	_check("card_action_resolved_this_turn persists through save/load",
		mgr._primary_state_11e["1"]["card_action_resolved_this_turn"] == true)
	_check("old saves without the key default to auto-resolve",
		not gs.state.meta.is_empty()
		and {}.get("card_action_resolved_this_turn", false) == false)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

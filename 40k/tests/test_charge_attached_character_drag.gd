extends SceneTree

# Regression test for the "cannot drag the attached character in the Charge
# phase" bug (Custodian Guard + Blade Champion).
#
# The charge drag UI stages attached CHARACTER model moves under composite
# per_model_paths keys ("<char_unit_id>:<model_id>" — bare ids collide with the
# bodyguard's own "m1"). ChargePhase must:
#   1. accept + apply a manually dragged character path alongside the squad's,
#      and NOT auto-ride that character a second time,
#   2. reject composite keys that do not belong to the charging unit's
#      attached characters,
#   3. reject a character path that exceeds the rolled charge distance,
#   4. accept a charge satisfied by the character alone (bodyguard unmoved)
#      and still grant both units their charge flags,
#   5. keep auto-riding characters that were NOT dragged (existing behavior).
#
# Usage: godot --headless --path . -s tests/test_charge_attached_character_drag.gd

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
	create_timer(0.1).timeout.connect(_run_tests)

func _make_units(gs) -> void:
	# Bodyguard (Custodian Guard stand-in): owner 1, 1 model at (500,500)
	gs.state.units["U_BG"] = {
		"id": "U_BG", "owner": 1, "status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {}, "attached_to": null,
		"attachment_data": {"attached_characters": ["U_CHAR"]},
		"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY", "IMPERIUM"],
			"stats": {"move": 6}},
		"models": [{"id": "m1", "alive": true, "wounds": 3, "current_wounds": 3,
			"base_mm": 40, "base_type": "circular", "position": {"x": 500, "y": 500}}]
	}
	# Character (Blade Champion stand-in): owner 1, attached to U_BG, at (460,500)
	gs.state.units["U_CHAR"] = {
		"id": "U_CHAR", "owner": 1, "status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {}, "attached_to": "U_BG",
		"meta": {"name": "Blade Champion", "keywords": ["CHARACTER", "INFANTRY", "IMPERIUM"],
			"stats": {"move": 6}},
		"models": [{"id": "m1", "alive": true, "wounds": 5, "current_wounds": 5,
			"base_mm": 40, "base_type": "circular", "position": {"x": 460, "y": 500}}]
	}
	# Target (enemy): owner 2, 1 model at (700,500)
	gs.state.units["U_TGT"] = {
		"id": "U_TGT", "owner": 2, "status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {"name": "Painboy", "keywords": ["INFANTRY", "ORKS"],
			"stats": {"move": 5}},
		"models": [{"id": "m1", "alive": true, "wounds": 4, "current_wounds": 4,
			"base_mm": 32, "base_type": "circular", "position": {"x": 700, "y": 500}}]
	}

func _pos_x(pos) -> float:
	return pos.x if pos is Vector2 else pos.get("x", 0)

func _fresh_phase(gs):
	var cphase = load("res://phases/ChargePhase.gd").new()
	cphase.phase_type = GameStateData.Phase.CHARGE
	root.add_child(cphase)
	cphase.pending_charges["U_BG"] = {"targets": ["U_TGT"], "distance": 8, "dice_rolls": [4, 4]}
	return cphase

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_charge_attached_character_drag ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	_check("GameState present", gs != null)
	_check("PhaseManager present", pm != null)
	if gs == null or pm == null:
		quit(1)
		return

	GameConstants.edition = 11
	gs.set_active_player(1)
	# Clear default board terrain so charge endpoints don't trip the wall check.
	var tm = root.get_node_or_null("TerrainManager")
	if tm:
		tm.terrain_features = []

	# ── 1. Manually dragged character moves to ITS OWN endpoint ─────────
	print("-- manually dragged character applies exactly once --")
	_make_units(gs)
	var cphase = _fresh_phase(gs)
	# Bodyguard reaches base-to-base at x=643; character dragged to x=576
	# (behind the bodyguard: coherent, no overlap, ends closer to the target).
	var result = cphase._process_apply_charge_move({
		"actor_unit_id": "U_BG",
		"payload": {"per_model_paths": {
			"m1": [[500, 500], [643, 500]],
			"U_CHAR:m1": [[460, 500], [576, 500]],
		}}
	})
	_check("charge with dragged character succeeded", result.get("success", false), str(result))
	var changes = result.get("changes", [])
	var char_pos_changes := 0
	for ch in changes:
		if str(ch.get("path", "")).begins_with("units.U_CHAR.models") and str(ch.get("path", "")).ends_with("position"):
			char_pos_changes += 1
	_check("character position written exactly once (no auto-ride double-move)",
		char_pos_changes == 1, "changes=%s" % str(changes))
	pm.apply_state_changes(changes)
	_check("bodyguard at its dragged endpoint (x=643)",
		abs(_pos_x(gs.state.units["U_BG"].models[0].position) - 643) < 1.0,
		str(gs.state.units["U_BG"].models[0].position))
	_check("character at its DRAGGED endpoint (x=576), not the ride-along spot",
		abs(_pos_x(gs.state.units["U_CHAR"].models[0].position) - 576) < 1.0,
		str(gs.state.units["U_CHAR"].models[0].position))
	_check("character marked charged_this_turn",
		gs.state.units["U_CHAR"].get("flags", {}).get("charged_this_turn", false) == true)
	_check("character granted fights_first",
		gs.state.units["U_CHAR"].get("flags", {}).get("fights_first", false) == true)
	cphase.free()

	# ── 2. Composite key that is NOT an attached character is rejected ──
	print("\n-- foreign composite key rejects the whole move --")
	_make_units(gs)
	cphase = _fresh_phase(gs)
	result = cphase._process_apply_charge_move({
		"actor_unit_id": "U_BG",
		"payload": {"per_model_paths": {
			"m1": [[500, 500], [643, 500]],
			"U_TGT:m1": [[700, 500], [800, 500]],  # enemy unit — must not be movable
		}}
	})
	_check("foreign-key charge produced no changes", result.get("changes", []).is_empty(), str(result))
	_check("bodyguard did not move on rejected charge",
		abs(_pos_x(gs.state.units["U_BG"].models[0].position) - 500) < 0.001,
		str(gs.state.units["U_BG"].models[0].position))
	_check("enemy did not move on rejected charge",
		abs(_pos_x(gs.state.units["U_TGT"].models[0].position) - 700) < 0.001,
		str(gs.state.units["U_TGT"].models[0].position))
	cphase.free()

	# ── 3. Character path over the rolled distance is rejected ──────────
	print("\n-- character path exceeding the charge roll rejects the move --")
	_make_units(gs)
	cphase = _fresh_phase(gs)
	# 8" roll = 320px; character path 460→800 = 340px (8.5") — too far.
	result = cphase._process_apply_charge_move({
		"actor_unit_id": "U_BG",
		"payload": {"per_model_paths": {
			"m1": [[500, 500], [643, 500]],
			"U_CHAR:m1": [[460, 500], [800, 500]],
		}}
	})
	_check("over-distance character path produced no changes",
		result.get("changes", []).is_empty(), str(result))
	_check("character did not move on rejected charge",
		abs(_pos_x(gs.state.units["U_CHAR"].models[0].position) - 460) < 0.001,
		str(gs.state.units["U_CHAR"].models[0].position))
	cphase.free()

	# ── 4. Charge satisfied by the character alone ───────────────────────
	print("\n-- character alone reaching engagement range satisfies the charge --")
	_make_units(gs)
	cphase = _fresh_phase(gs)
	# Character 460→630: within ER of the target (edge gap ≈ 0.33"), coherent
	# with the unmoved bodyguard at 500 (edge gap ≈ 1.7"), ends closer.
	result = cphase._process_apply_charge_move({
		"actor_unit_id": "U_BG",
		"payload": {"per_model_paths": {
			"U_CHAR:m1": [[460, 500], [630, 500]],
		}}
	})
	_check("character-only charge succeeded", result.get("success", false), str(result))
	pm.apply_state_changes(result.get("changes", []))
	_check("character at its endpoint (x=630)",
		abs(_pos_x(gs.state.units["U_CHAR"].models[0].position) - 630) < 1.0,
		str(gs.state.units["U_CHAR"].models[0].position))
	_check("bodyguard stayed put (x=500)",
		abs(_pos_x(gs.state.units["U_BG"].models[0].position) - 500) < 0.001,
		str(gs.state.units["U_BG"].models[0].position))
	_check("bodyguard unit marked charged_this_turn",
		gs.state.units["U_BG"].get("flags", {}).get("charged_this_turn", false) == true)
	_check("character marked charged_this_turn (delta-less charge)",
		gs.state.units["U_CHAR"].get("flags", {}).get("charged_this_turn", false) == true)
	cphase.free()

	# ── 5. Undragged character still auto-rides (existing behavior) ─────
	print("\n-- undragged character still rides the squad's move --")
	_make_units(gs)
	# Start the character clear of the bodyguard (no base overlap, but inside
	# 2" coherency) so the rigid +143px translation lands on a legal spot with
	# no overlap nudge: 400,500 → ideal 543,500 (1" behind the bodyguard).
	gs.state.units["U_CHAR"].models[0].position = {"x": 400, "y": 500}
	cphase = _fresh_phase(gs)
	result = cphase._process_apply_charge_move({
		"actor_unit_id": "U_BG",
		"payload": {"per_model_paths": {"m1": [[500, 500], [643, 500]]}}
	})
	_check("bodyguard-only charge succeeded", result.get("success", false), str(result))
	pm.apply_state_changes(result.get("changes", []))
	_check("bodyguard applied its charge endpoint (x=643)",
		abs(_pos_x(gs.state.units["U_BG"].models[0].position) - 643) < 1.0,
		str(gs.state.units["U_BG"].models[0].position))
	_check("undragged character auto-rode the charge (+143px)",
		abs(_pos_x(gs.state.units["U_CHAR"].models[0].position) - 543) < 1.0,
		str(gs.state.units["U_CHAR"].models[0].position))
	cphase.free()

	# ── 6. Charge ending with the character OUT of coherency is rejected ─
	print("\n-- charge that would split the character off is rejected --")
	_make_units(gs)
	cphase = _fresh_phase(gs)
	# Character dragged 460→460 is not allowed (paths must move), so drag it
	# slightly toward the target but far from the squad's endpoint: the squad
	# jumps to 643 while the character only reaches 500 — edge gap 2.0"+ from
	# the bodyguard → unit coherency broken → whole move rejected.
	result = cphase._process_apply_charge_move({
		"actor_unit_id": "U_BG",
		"payload": {"per_model_paths": {
			"m1": [[500, 500], [643, 500]],
			"U_CHAR:m1": [[460, 500], [500, 430]],
		}}
	})
	_check("incoherent drag produced no changes", result.get("changes", []).is_empty(), str(result))
	_check("character did not move on incoherent charge",
		abs(_pos_x(gs.state.units["U_CHAR"].models[0].position) - 460) < 0.001,
		str(gs.state.units["U_CHAR"].models[0].position))
	cphase.free()

	for uid in ["U_BG", "U_CHAR", "U_TGT"]:
		gs.state.units.erase(uid)
	GameConstants.edition = 11
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

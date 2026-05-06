extends Node

# T-001 live test helper: position the Ork Warboss 8" south of the Custodes
# Blade Champion, clear all "cannot charge" flags, set active player to P2 (AI).
# Returns a status dict so the caller can verify.

static func setup(blade_champ_id: String = "U_BLADE_CHAMPION_A",
		warboss_id: String = "U_WARBOSS_B") -> Dictionary:
	var gs = Engine.get_main_loop().root.get_node("GameState")
	var bc = gs.state["units"].get(blade_champ_id, {})
	var wb = gs.state["units"].get(warboss_id, {})
	if bc.is_empty() or wb.is_empty():
		return {"ok": false, "error": "missing units"}
	# Position Warboss 8" (320 px) south of Blade Champion.
	var bc_pos = bc.models[0].position
	var bc_x = float(bc_pos.x) if bc_pos is Dictionary else bc_pos.x
	var bc_y = float(bc_pos.y) if bc_pos is Dictionary else bc_pos.y
	wb.models[0].position = {"x": bc_x, "y": bc_y + 320.0}
	# Clear flags that would block a charge.
	wb.flags = {"get_stuck_in": true}
	# Active player → P2.
	gs.state["meta"]["active_player"] = 2
	# Refresh phase snapshot if there's an active phase manager.
	var pm = Engine.get_main_loop().root.get_node_or_null("PhaseManager")
	if pm and pm.current_phase_instance:
		pm.current_phase_instance.game_state_snapshot = gs.state
	return {
		"ok": true,
		"warboss_pos": wb.models[0].position,
		"blade_champ_pos": bc_pos,
		"warboss_flags": wb.flags,
		"active_player": gs.state["meta"]["active_player"],
	}

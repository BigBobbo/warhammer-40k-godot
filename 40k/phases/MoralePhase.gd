extends BasePhase
class_name MoralePhase

const BasePhase = preload("res://phases/BasePhase.gd")


# MoralePhase - 10th Edition Morale Phase implementation
#
# In Warhammer 40k 10th Edition, the Morale Phase is a bookkeeping phase:
# - Battle-shock tests are taken in the Command Phase (handled by CommandPhase.gd)
# - Battle-shocked status auto-clears at the start of the owner's next Command Phase
# - The Morale Phase logs battle-shocked units and completes automatically
#
# There are NO separate morale tests or model removal in the 10e Morale Phase.
# The old 9th-edition mechanics (casualties + D6 vs Leadership, fleeing models)
# have been replaced by the Battle-shock system in CommandPhase.

func _init():
	phase_type = GameStateData.Phase.MORALE

func _on_phase_enter() -> void:
	log_phase_message("Entering Morale Phase (10th Edition)")

	# Log current battle-shock status for all active player's units
	_log_battle_shock_status()

	# In 10e, the Morale Phase has no active player decisions — auto-complete
	log_phase_message("Morale Phase complete (10e: no active mechanics in this phase)")
	emit_signal("phase_completed")

func _on_phase_exit() -> void:
	log_phase_message("Exiting Morale Phase")

func _log_battle_shock_status() -> void:
	# Report which units are currently battle-shocked for visibility
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	var shocked_units = []

	for unit_id in units:
		var unit = units[unit_id]

		# Skip destroyed units
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		var is_shocked = unit.get("flags", {}).get("battle_shocked", false)
		if is_shocked:
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			shocked_units.append(unit_name)
			log_phase_message("  Battle-shocked: %s (%s) — OC reduced to 0" % [unit_name, unit_id])

	if shocked_units.size() == 0:
		log_phase_message("No units are currently battle-shocked for player %d" % current_player)
	else:
		log_phase_message("%d unit(s) battle-shocked for player %d: %s" % [
			shocked_units.size(), current_player, ", ".join(shocked_units)
		])

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	match action_type:
		"END_MORALE":
			return {"valid": true, "errors": []}
		_:
			return {"valid": false, "errors": ["Unknown action type in Morale Phase: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"END_MORALE":
			return _process_end_morale(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

func _process_end_morale(_action: Dictionary) -> Dictionary:
	log_phase_message("Ending Morale Phase")
	emit_signal("phase_completed")
	return create_result(true, [])

func get_available_actions() -> Array:
	var current_player = get_current_player()

	# In 10e, the only action in the Morale Phase is to end it
	return [{
		"type": "END_MORALE",
		"description": "End Morale Phase",
		"player": current_player
	}]

func _should_complete_phase() -> bool:
	# Phase auto-completes on entry in 10e — no active mechanics
	# This is also called after process_action; returning false here because
	# phase_completed is emitted directly by _on_phase_enter and _process_end_morale
	return false

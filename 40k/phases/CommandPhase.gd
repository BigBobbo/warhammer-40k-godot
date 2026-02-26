extends BasePhase
class_name CommandPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# CommandPhase - Handles Command Phase including CP generation and Battle-shock tests
# Per 10th edition rules:
# 1. Generate Command Points (both players gain 1 CP)
# 2. Clear all battle_shocked flags at the start of the Command Phase
# 3. Identify units Below Half-strength
# 4. Each Below Half-strength unit takes a Battle-shock test (2D6 vs Leadership)
#    - INSANE BRAVERY stratagem can auto-pass a test (once per battle, 1 CP)
# 5. If the roll is below the unit's Leadership, the unit becomes Battle-shocked
# 6. Score primary objectives and end the phase

signal command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary)

# Track which units still need battle-shock tests this phase
var _units_needing_test: Array = []
var _units_tested: Array = []
var _units_auto_passed: Array = []  # Units that auto-passed via Insane Bravery
var _rng: RandomNumberGenerator
var _awaiting_reroll_decision: bool = false
var _reroll_pending_unit_id: String = ""
var _reroll_pending_roll: Dictionary = {}  # Stores {die1, die2, unit_id, leadership}

func _init():
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

func _on_phase_enter() -> void:
	phase_type = GameStateData.Phase.COMMAND
	var current_player = get_current_player()
	var battle_round = GameState.get_battle_round()
	print("CommandPhase: Entering command phase for player ", current_player)
	print("CommandPhase: Battle round ", battle_round)

	# Step 0a: Reset per-round kill tracking for Purge the Foe at start of each battle round
	if MissionManager and current_player == 1:
		MissionManager.reset_round_kills()

	# Step 0b: Initialize secondary mission decks on first command phase
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr and battle_round == 1 and current_player == 1:
		if not secondary_mgr.is_initialized(1):
			secondary_mgr.setup_tactical_deck(1)
			secondary_mgr.setup_tactical_deck(2)
			print("CommandPhase: Secondary mission decks initialized for both players")

	# Step 1: Generate Command Points
	# Per 10th edition rules, both players gain 1 CP at the start of each Command Phase
	_generate_command_points(current_player)

	# Step 2: Clear all battle_shocked flags for the current player's units
	_clear_battle_shocked_flags()

	# Step 3: Identify units below half-strength that need battle-shock tests
	_identify_units_needing_tests()

	# Step 4: Check objectives at start of command phase
	if MissionManager:
		MissionManager.check_all_objectives()

	# Step 5: Draw secondary mission cards (tactical mode)
	if secondary_mgr and secondary_mgr.is_initialized(current_player):
		secondary_mgr.on_turn_start(current_player)
		var drawn = secondary_mgr.draw_missions_to_hand(current_player)
		if drawn.size() > 0:
			print("CommandPhase: Player %d drew %d secondary mission card(s)" % [current_player, drawn.size()])
			for card in drawn:
				print("  - %s" % card["name"])

	# Step 6: Initialize faction abilities (Oath of Moment, etc.)
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_mgr:
		faction_mgr.on_command_phase_start(current_player)

	if _units_needing_test.size() == 0:
		print("CommandPhase: No units need battle-shock tests")
	else:
		print("CommandPhase: %d unit(s) need battle-shock tests" % _units_needing_test.size())

func _generate_command_points(active_player: int) -> void:
	var opponent = 1 if active_player == 2 else 2
	var changes = []

	# Active player gains 1 CP
	var active_cp = GameState.state.get("players", {}).get(str(active_player), {}).get("cp", 0)
	changes.append({
		"op": "set",
		"path": "players.%s.cp" % str(active_player),
		"value": active_cp + 1
	})

	# Opponent also gains 1 CP
	var opponent_cp = GameState.state.get("players", {}).get(str(opponent), {}).get("cp", 0)
	changes.append({
		"op": "set",
		"path": "players.%s.cp" % str(opponent),
		"value": opponent_cp + 1
	})

	# Apply via PhaseManager so changes propagate to network peers
	PhaseManager.apply_state_changes(changes)

	# Refresh our local snapshot to reflect the CP changes
	game_state_snapshot = GameState.create_snapshot()

	print("CommandPhase: Generated CP — Player %d: %d → %d, Player %d: %d → %d" % [
		active_player, active_cp, active_cp + 1,
		opponent, opponent_cp, opponent_cp + 1
	])

func _on_phase_exit() -> void:
	print("CommandPhase: Exiting command phase")
	_units_needing_test.clear()
	_units_tested.clear()
	_units_auto_passed.clear()
	_awaiting_reroll_decision = false
	_reroll_pending_unit_id = ""
	_reroll_pending_roll = {}

func _clear_battle_shocked_flags() -> void:
	# Per 10th edition: Clear battle-shocked status at the start of each Command Phase
	var current_player = get_current_player()
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != current_player:
			continue

		var was_shocked = unit.get("flags", {}).get("battle_shocked", false)
		if was_shocked:
			# Ensure flags dict exists before writing
			if not unit.has("flags"):
				unit["flags"] = {}
			unit["flags"]["battle_shocked"] = false
			print("CommandPhase: Cleared battle-shocked from %s" % unit_id)

	print("CommandPhase: Cleared battle-shocked flags for player %d" % current_player)

func _identify_units_needing_tests() -> void:
	_units_needing_test.clear()
	_units_tested.clear()

	var current_player = get_current_player()
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != current_player:
			continue

		# Skip destroyed units (no alive models)
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Skip undeployed units
		var status = unit.get("status", GameStateData.UnitStatus.UNDEPLOYED)
		if status == GameStateData.UnitStatus.UNDEPLOYED:
			continue

		# Check if unit is below half-strength
		if GameState.is_below_half_strength(unit):
			_units_needing_test.append(unit_id)
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			print("CommandPhase: %s (%s) is below half-strength - needs battle-shock test" % [unit_name, unit_id])

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()

	# If awaiting a reroll decision, only offer reroll actions
	if _awaiting_reroll_decision:
		var pending_name = _reroll_pending_roll.get("unit_name", _reroll_pending_unit_id)
		var pending_total = _reroll_pending_roll.get("roll_total", 0)
		var pending_ld = _reroll_pending_roll.get("leadership", 0)
		actions.append({
			"type": "USE_COMMAND_REROLL",
			"unit_id": _reroll_pending_unit_id,
			"description": "Command Re-roll battle-shock for %s (rolled %d vs Ld %d)" % [pending_name, pending_total, pending_ld],
			"player": current_player
		})
		actions.append({
			"type": "DECLINE_COMMAND_REROLL",
			"unit_id": _reroll_pending_unit_id,
			"description": "Decline re-roll for %s" % pending_name,
			"player": current_player
		})
		return actions

	# Offer battle-shock tests for units that haven't tested yet
	for unit_id in _units_needing_test:
		if unit_id in _units_tested:
			continue

		var unit = GameState.state.get("units", {}).get(unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var ld = unit.get("meta", {}).get("stats", {}).get("leadership", 7)

		actions.append({
			"type": "BATTLE_SHOCK_TEST",
			"unit_id": unit_id,
			"description": "Battle-shock test for %s (Ld %d)" % [unit_name, ld],
			"player": current_player
		})

		# Check if Insane Bravery is available for this unit
		var strat_manager = get_node_or_null("/root/StratagemManager")
		if strat_manager:
			var can_use = strat_manager.can_use_stratagem(current_player, "insane_bravery", unit_id)
			if can_use.can_use:
				actions.append({
					"type": "USE_STRATAGEM",
					"stratagem_id": "insane_bravery",
					"target_unit_id": unit_id,
					"description": "INSANE BRAVERY on %s (1 CP - auto-pass battle-shock)" % unit_name,
					"player": current_player
				})

	# Secondary mission actions (New Orders stratagem only - voluntary discard
	# happens at end of turn in the Scoring Phase, not during Command Phase)
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr and secondary_mgr.is_initialized(current_player):
		var active_missions = secondary_mgr.get_active_missions(current_player)

		# New Orders stratagem
		var strat_manager = get_node_or_null("/root/StratagemManager")
		if strat_manager and active_missions.size() > 0:
			var can_use = strat_manager.can_use_stratagem(current_player, "new_orders")
			if can_use.get("can_use", false) and secondary_mgr.get_deck_size(current_player) > 0:
				for i in range(active_missions.size()):
					actions.append({
						"type": "USE_NEW_ORDERS",
						"mission_index": i,
						"description": "New Orders: discard %s and draw new (1 CP)" % active_missions[i].get("name", "?"),
						"player": current_player
					})

	# Faction ability actions
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")

	# Waaagh! activation (Orks)
	if faction_mgr and faction_mgr.is_waaagh_available(current_player):
		actions.append({
			"type": "CALL_WAAAGH",
			"description": "WAAAGH! — Advance+Charge, +1 S/A melee, 5+ invuln (once per battle)",
			"player": current_player
		})

	# Oath of Moment target selection (Space Marines)
	if faction_mgr and faction_mgr.player_has_ability(current_player, "Oath of Moment"):
		var current_oath_target = faction_mgr.get_oath_of_moment_target(current_player)
		var eligible_targets = faction_mgr.get_eligible_oath_targets(current_player)

		if eligible_targets.size() > 0:
			for target_info in eligible_targets:
				var is_current = (target_info.unit_id == current_oath_target)
				actions.append({
					"type": "SELECT_OATH_TARGET",
					"target_unit_id": target_info.unit_id,
					"description": "Oath of Moment: %s%s" % [target_info.unit_name, " (current)" if is_current else ""],
					"player": current_player,
					"is_current_target": is_current
				})

	# Combat Doctrines selection (Space Marines — Gladius Task Force) (P2-27)
	if faction_mgr and faction_mgr.get_player_detachment(current_player) == "Gladius Task Force":
		var available_doctrines = faction_mgr.get_available_doctrines(current_player)
		var active_doctrine = faction_mgr.get_active_doctrine(current_player)
		if available_doctrines.size() > 0 and active_doctrine == "":
			for doctrine in available_doctrines:
				actions.append({
					"type": "SELECT_COMBAT_DOCTRINE",
					"doctrine_key": doctrine.key,
					"description": "Combat Doctrines: %s — %s" % [doctrine.display, doctrine.description],
					"player": current_player
				})
			# Allow skipping doctrine selection (no doctrine active this round)
			actions.append({
				"type": "SKIP_COMBAT_DOCTRINE",
				"description": "Skip Combat Doctrine selection (no doctrine active this round)",
				"player": current_player
			})

	# Martial Mastery selection (Adeptus Custodes — Shield Host) (P2-27)
	if faction_mgr and faction_mgr.is_martial_mastery_available(current_player):
		var mastery_options = faction_mgr.get_mastery_options()
		for option in mastery_options:
			actions.append({
				"type": "SELECT_MARTIAL_MASTERY",
				"mastery_key": option.key,
				"description": "%s — %s" % [option.display, option.description],
				"player": current_player
			})

	# P3-29: Grot Orderly — once per battle, return D3 destroyed Bodyguard models
	var ability_mgr_go = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr_go:
		var all_units_go = GameState.state.get("units", {})
		for unit_id in all_units_go:
			var unit = all_units_go[unit_id]
			if unit.get("owner", 0) != current_player:
				continue
			if not ability_mgr_go.has_grot_orderly(unit_id):
				continue
			# Check if the unit is deployed and alive
			if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
				continue
			var go_info = ability_mgr_go.get_grot_orderly_unit(unit_id)
			if go_info.get("eligible", false):
				var painboss_name = unit.get("meta", {}).get("name", unit_id)
				actions.append({
					"type": "USE_GROT_ORDERLY",
					"unit_id": unit_id,
					"bodyguard_unit_id": go_info.bodyguard_unit_id,
					"description": "Grot Orderly: %s returns up to D3 models to %s (%d destroyed)" % [
						painboss_name, go_info.bodyguard_unit_name, go_info.destroyed_count],
					"player": current_player
				})

	# Always allow ending command phase (but warn if tests remain)
	actions.append({
		"type": "END_COMMAND",
		"description": "End Command Phase",
		"player": current_player
	})

	return actions

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	var errors = []

	match action_type:
		"END_COMMAND":
			# END_COMMAND is always valid in command phase
			pass
		"BATTLE_SHOCK_TEST":
			errors = _validate_battle_shock_test(action)
		"USE_STRATAGEM":
			errors = _validate_use_stratagem(action)
		"USE_COMMAND_REROLL":
			if not _awaiting_reroll_decision:
				errors.append("Not awaiting a Command Re-roll decision")
		"DECLINE_COMMAND_REROLL":
			if not _awaiting_reroll_decision:
				errors.append("Not awaiting a Command Re-roll decision")
		"USE_NEW_ORDERS":
			errors = _validate_use_new_orders(action)
		"SELECT_OATH_TARGET":
			errors = _validate_select_oath_target(action)
		"CALL_WAAAGH":
			errors = _validate_call_waaagh(action)
		"SELECT_COMBAT_DOCTRINE":
			errors = _validate_select_combat_doctrine(action)
		"SKIP_COMBAT_DOCTRINE":
			pass  # Always valid
		"SELECT_MARTIAL_MASTERY":
			errors = _validate_select_martial_mastery(action)
		"USE_GROT_ORDERLY":
			errors = _validate_use_grot_orderly(action)
		"RESOLVE_MARKED_FOR_DEATH":
			errors = _validate_resolve_marked_for_death(action)
		"RESOLVE_TEMPTING_TARGET":
			errors = _validate_resolve_tempting_target(action)
		"DEBUG_MOVE":
			# Already validated by base class
			return {"valid": true, "errors": []}
		_:
			errors.append("Unknown action type: %s" % action_type)

	return {
		"valid": errors.size() == 0,
		"errors": errors
	}

func _validate_battle_shock_test(action: Dictionary) -> Array:
	var errors = []

	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		errors.append("Missing unit_id for battle-shock test")
		return errors

	# Unit must exist
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		errors.append("Unit not found: %s" % unit_id)
		return errors

	# Unit must belong to current player
	if unit.get("owner", 0) != get_current_player():
		errors.append("Unit %s does not belong to active player" % unit_id)

	# Unit must be in the needing-test list
	if unit_id not in _units_needing_test:
		errors.append("Unit %s does not need a battle-shock test" % unit_id)

	# Unit must not have already been tested this phase
	if unit_id in _units_tested:
		errors.append("Unit %s has already taken a battle-shock test this phase" % unit_id)

	return errors

func process_action(action: Dictionary) -> Dictionary:
	match action.get("type", ""):
		"END_COMMAND":
			return _handle_end_command()
		"BATTLE_SHOCK_TEST":
			return _handle_battle_shock_test(action)
		"USE_STRATAGEM":
			return _handle_use_stratagem(action)
		"USE_COMMAND_REROLL":
			return _handle_use_command_reroll(action)
		"DECLINE_COMMAND_REROLL":
			return _handle_decline_command_reroll(action)
		"USE_NEW_ORDERS":
			return _handle_use_new_orders(action)
		"SELECT_OATH_TARGET":
			return _handle_select_oath_target(action)
		"CALL_WAAAGH":
			return _handle_call_waaagh(action)
		"SELECT_COMBAT_DOCTRINE":
			return _handle_select_combat_doctrine(action)
		"SKIP_COMBAT_DOCTRINE":
			return _handle_skip_combat_doctrine(action)
		"SELECT_MARTIAL_MASTERY":
			return _handle_select_martial_mastery(action)
		"USE_GROT_ORDERLY":
			return _handle_use_grot_orderly(action)
		"RESOLVE_MARKED_FOR_DEATH":
			return _handle_resolve_marked_for_death(action)
		"RESOLVE_TEMPTING_TARGET":
			return _handle_resolve_tempting_target(action)
		_:
			return {"success": false, "error": "Unknown action type"}

func _handle_battle_shock_test(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var leadership = unit.get("meta", {}).get("stats", {}).get("leadership", 7)

	# Roll 2D6 (allow override for testing via dice_roll parameter)
	var die1: int
	var die2: int
	if action.has("dice_roll"):
		# Accept pre-set roll for deterministic testing
		var roll = action.get("dice_roll", [])
		die1 = roll[0] if roll.size() > 0 else _rng.randi_range(1, 6)
		die2 = roll[1] if roll.size() > 1 else _rng.randi_range(1, 6)
	else:
		die1 = _rng.randi_range(1, 6)
		die2 = _rng.randi_range(1, 6)

	var roll_total = die1 + die2
	var test_passed = roll_total >= leadership

	log_phase_message("Battle-shock test for %s: 2D6 = %d (%d + %d) vs Ld %d" % [unit_name, roll_total, die1, die2, leadership])

	# Check if Command Re-roll is available (only offer on failed tests)
	if not test_passed and not action.has("dice_roll"):
		var current_player = get_current_player()
		var strat_manager = get_node_or_null("/root/StratagemManager")
		if strat_manager:
			var reroll_check = strat_manager.is_command_reroll_available(current_player)
			if reroll_check.available:
				# Pause — offer Command Re-roll
				_awaiting_reroll_decision = true
				_reroll_pending_unit_id = unit_id
				_reroll_pending_roll = {
					"die1": die1,
					"die2": die2,
					"roll_total": roll_total,
					"leadership": leadership,
					"unit_id": unit_id,
					"unit_name": unit_name,
				}

				var context_text = "Need %d+ to pass (rolled %d)" % [leadership, roll_total]
				var roll_context = {
					"roll_type": "battle_shock_test",
					"original_rolls": [die1, die2],
					"total": roll_total,
					"unit_id": unit_id,
					"unit_name": unit_name,
					"context_text": context_text,
					"leadership": leadership,
				}

				print("CommandPhase: Command Re-roll available for %s battle-shock test — pausing for decision" % unit_name)
				emit_signal("command_reroll_opportunity", unit_id, current_player, roll_context)

				return {
					"success": true,
					"unit_id": unit_id,
					"unit_name": unit_name,
					"die1": die1,
					"die2": die2,
					"roll_total": roll_total,
					"leadership": leadership,
					"test_passed": false,
					"awaiting_reroll": true,
					"message": "%s FAILED battle-shock test (rolled %d vs Ld %d) — Command Re-roll available!" % [unit_name, roll_total, leadership]
				}

	# Resolve immediately (no reroll available or test passed)
	return _resolve_battle_shock_test(unit_id, die1, die2)

func _resolve_battle_shock_test(unit_id: String, die1: int, die2: int) -> Dictionary:
	"""Resolve a battle-shock test with the given dice. Called after initial roll or after reroll decision."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var leadership = unit.get("meta", {}).get("stats", {}).get("leadership", 7)
	var roll_total = die1 + die2
	var test_passed = roll_total >= leadership

	# Mark unit as tested
	if unit_id not in _units_tested:
		_units_tested.append(unit_id)

	# Apply battle-shocked flag if test failed
	if not test_passed:
		if not unit.has("flags"):
			unit["flags"] = {}
		unit["flags"]["battle_shocked"] = true

		print("CommandPhase: %s FAILED battle-shock test (rolled %d+%d=%d vs Ld %d) - now Battle-shocked!" % [
			unit_name, die1, die2, roll_total, leadership
		])
	else:
		print("CommandPhase: %s PASSED battle-shock test (rolled %d+%d=%d vs Ld %d)" % [
			unit_name, die1, die2, roll_total, leadership
		])

	var result = {
		"success": true,
		"unit_id": unit_id,
		"unit_name": unit_name,
		"die1": die1,
		"die2": die2,
		"roll_total": roll_total,
		"leadership": leadership,
		"test_passed": test_passed,
		"battle_shocked": not test_passed,
		"message": "%s %s battle-shock test (rolled %d vs Ld %d)" % [
			unit_name,
			"passed" if test_passed else "FAILED",
			roll_total,
			leadership
		]
	}

	# Log the test result to phase log
	var log_entry = {
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"die1": die1,
		"die2": die2,
		"roll_total": roll_total,
		"leadership": leadership,
		"passed": test_passed,
		"turn": GameState.get_battle_round()
	}
	GameState.add_action_to_phase_log(log_entry)

	return result

func _handle_use_command_reroll(action: Dictionary) -> Dictionary:
	"""Handle USE_COMMAND_REROLL for battle-shock test."""
	var unit_id = _reroll_pending_unit_id
	var old_roll = _reroll_pending_roll.duplicate()
	_awaiting_reroll_decision = false
	_reroll_pending_unit_id = ""
	_reroll_pending_roll = {}

	var unit_name = old_roll.get("unit_name", unit_id)
	var current_player = get_current_player()

	# Execute the stratagem (deduct CP, record usage)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var roll_context = {
			"roll_type": "battle_shock_test",
			"original_rolls": [old_roll.die1, old_roll.die2],
			"unit_name": unit_name,
		}
		var strat_result = strat_manager.execute_command_reroll(current_player, unit_id, roll_context)
		if not strat_result.success:
			print("CommandPhase: Command Re-roll failed: %s" % strat_result.get("error", ""))
			return _resolve_battle_shock_test(unit_id, old_roll.die1, old_roll.die2)

	# Re-roll 2D6
	var new_die1 = _rng.randi_range(1, 6)
	var new_die2 = _rng.randi_range(1, 6)
	var new_total = new_die1 + new_die2

	log_phase_message("COMMAND RE-ROLL: Battle-shock re-rolled from %d (%d+%d) → %d (%d+%d)" % [
		old_roll.roll_total, old_roll.die1, old_roll.die2, new_total, new_die1, new_die2
	])

	print("CommandPhase: COMMAND RE-ROLL — %s battle-shock re-rolled: %d → %d" % [
		unit_name, old_roll.roll_total, new_total
	])

	return _resolve_battle_shock_test(unit_id, new_die1, new_die2)

func _handle_decline_command_reroll(action: Dictionary) -> Dictionary:
	"""Handle DECLINE_COMMAND_REROLL for battle-shock test."""
	var unit_id = _reroll_pending_unit_id
	var old_roll = _reroll_pending_roll.duplicate()
	_awaiting_reroll_decision = false
	_reroll_pending_unit_id = ""
	_reroll_pending_roll = {}

	print("CommandPhase: Command Re-roll DECLINED for %s — resolving with original roll" % unit_id)

	return _resolve_battle_shock_test(unit_id, old_roll.die1, old_roll.die2)

# ============================================================================
# STRATAGEM HANDLING
# ============================================================================

func _validate_use_stratagem(action: Dictionary) -> Array:
	var errors = []
	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")

	if stratagem_id == "":
		errors.append("Missing stratagem_id")
		return errors

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		errors.append("StratagemManager not available")
		return errors

	var current_player = get_current_player()
	var validation = strat_manager.can_use_stratagem(current_player, stratagem_id, target_unit_id)
	if not validation.can_use:
		errors.append(validation.reason)

	# For Insane Bravery: target must need a battle-shock test and not have been tested yet
	if stratagem_id == "insane_bravery":
		if target_unit_id == "":
			errors.append("Insane Bravery requires a target unit")
		elif target_unit_id not in _units_needing_test:
			errors.append("Unit %s does not need a battle-shock test" % target_unit_id)
		elif target_unit_id in _units_tested:
			errors.append("Unit %s has already taken a battle-shock test this phase" % target_unit_id)

	return errors

func _handle_use_stratagem(action: Dictionary) -> Dictionary:
	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		return {"success": false, "error": "StratagemManager not available"}

	# Use the stratagem (validates, deducts CP, records usage)
	var result = strat_manager.use_stratagem(current_player, stratagem_id, target_unit_id)
	if not result.success:
		return result

	# Apply stratagem-specific effects
	match stratagem_id:
		"insane_bravery":
			return _apply_insane_bravery(target_unit_id, result)
		_:
			print("CommandPhase: Stratagem %s used but no phase-specific handler" % stratagem_id)
			return result

func _apply_insane_bravery(unit_id: String, strat_result: Dictionary) -> Dictionary:
	"""Apply Insane Bravery: auto-pass the battle-shock test for the target unit."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# Mark unit as tested (auto-passed)
	_units_tested.append(unit_id)
	_units_auto_passed.append(unit_id)

	# Unit passes automatically - no dice rolled, no battle-shocked flag set
	print("CommandPhase: %s AUTO-PASSED battle-shock test via INSANE BRAVERY!" % unit_name)

	# Log to phase log
	var log_entry = {
		"type": "BATTLE_SHOCK_TEST",
		"unit_id": unit_id,
		"die1": 0,
		"die2": 0,
		"roll_total": 0,
		"leadership": unit.get("meta", {}).get("stats", {}).get("leadership", 7),
		"passed": true,
		"auto_passed": true,
		"stratagem": "insane_bravery",
		"turn": GameState.get_battle_round()
	}
	GameState.add_action_to_phase_log(log_entry)

	return {
		"success": true,
		"unit_id": unit_id,
		"unit_name": unit_name,
		"die1": 0,
		"die2": 0,
		"roll_total": 0,
		"leadership": unit.get("meta", {}).get("stats", {}).get("leadership", 7),
		"test_passed": true,
		"battle_shocked": false,
		"auto_passed": true,
		"stratagem_used": "insane_bravery",
		"message": "%s AUTO-PASSED battle-shock test (INSANE BRAVERY - 1 CP)" % unit_name
	}

# ============================================================================
# FACTION ABILITIES — WAAAGH! (Orks)
# ============================================================================

func _validate_call_waaagh(action: Dictionary) -> Array:
	var errors = []
	var current_player = get_current_player()

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		errors.append("FactionAbilityManager not available")
		return errors

	if not faction_mgr.is_waaagh_available(current_player):
		errors.append("Waaagh! is not available (already used or not an Ork player)")

	return errors

func _handle_call_waaagh(action: Dictionary) -> Dictionary:
	var current_player = get_current_player()

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		return {"success": false, "error": "FactionAbilityManager not available"}

	var result = faction_mgr.activate_waaagh(current_player)

	if result.success:
		log_phase_message("WAAAGH! Player %d calls a Waaagh! — all Ork units gain advance+charge, +1 S/A melee, 5+ invuln!" % current_player)

		# Log to phase log
		var log_entry = {
			"type": "CALL_WAAAGH",
			"player": current_player,
			"turn": GameState.get_battle_round()
		}
		GameState.add_action_to_phase_log(log_entry)

	return result

# ============================================================================
# FACTION ABILITIES — OATH OF MOMENT
# ============================================================================

func _validate_select_oath_target(action: Dictionary) -> Array:
	var errors = []
	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()

	if target_unit_id == "":
		errors.append("Missing target_unit_id for Oath of Moment")
		return errors

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		errors.append("FactionAbilityManager not available")
		return errors

	if not faction_mgr.player_has_ability(current_player, "Oath of Moment"):
		errors.append("Player %d does not have Oath of Moment" % current_player)
		return errors

	# Target must be an enemy unit
	var target = GameState.state.get("units", {}).get(target_unit_id, {})
	if target.is_empty():
		errors.append("Target unit not found: %s" % target_unit_id)
		return errors

	if target.get("owner", 0) == current_player:
		errors.append("Cannot target own unit with Oath of Moment")

	# Target must have alive models
	var has_alive = false
	for model in target.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		errors.append("Target unit is destroyed")

	return errors

func _handle_select_oath_target(action: Dictionary) -> Dictionary:
	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		return {"success": false, "error": "FactionAbilityManager not available"}

	var result = faction_mgr.set_oath_of_moment_target(current_player, target_unit_id)

	if result.success:
		log_phase_message("OATH OF MOMENT: Player %d marks %s for destruction" % [
			current_player, result.get("target_name", target_unit_id)])

		# Log to phase log
		var log_entry = {
			"type": "SELECT_OATH_TARGET",
			"player": current_player,
			"target_unit_id": target_unit_id,
			"target_name": result.get("target_name", ""),
			"turn": GameState.get_battle_round()
		}
		GameState.add_action_to_phase_log(log_entry)

	return result

# ============================================================================
# DETACHMENT ABILITIES — COMBAT DOCTRINES (P2-27)
# ============================================================================

func _validate_select_combat_doctrine(action: Dictionary) -> Array:
	var errors = []
	var current_player = get_current_player()
	var doctrine_key = action.get("doctrine_key", "")

	if doctrine_key == "":
		errors.append("Missing doctrine_key for Combat Doctrine selection")
		return errors

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		errors.append("FactionAbilityManager not available")
		return errors

	if faction_mgr.get_player_detachment(current_player) != "Gladius Task Force":
		errors.append("Player %d is not using Gladius Task Force detachment" % current_player)
		return errors

	# Check doctrine hasn't been used
	var available = faction_mgr.get_available_doctrines(current_player)
	var found = false
	for d in available:
		if d.key == doctrine_key:
			found = true
			break
	if not found:
		errors.append("Doctrine '%s' is not available (already used or unknown)" % doctrine_key)

	# Check no doctrine is already active this phase
	if faction_mgr.get_active_doctrine(current_player) != "":
		errors.append("A Combat Doctrine is already active this phase")

	return errors

func _handle_select_combat_doctrine(action: Dictionary) -> Dictionary:
	var current_player = get_current_player()
	var doctrine_key = action.get("doctrine_key", "")

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		return {"success": false, "error": "FactionAbilityManager not available"}

	var result = faction_mgr.select_combat_doctrine(current_player, doctrine_key)

	if result.success:
		log_phase_message("COMBAT DOCTRINES: Player %d activates %s" % [
			current_player, result.get("doctrine_display", doctrine_key)])

		var log_entry = {
			"type": "SELECT_COMBAT_DOCTRINE",
			"player": current_player,
			"doctrine": doctrine_key,
			"doctrine_display": result.get("doctrine_display", ""),
			"turn": GameState.get_battle_round()
		}
		GameState.add_action_to_phase_log(log_entry)

	return result

func _handle_skip_combat_doctrine(_action: Dictionary) -> Dictionary:
	var current_player = get_current_player()
	log_phase_message("COMBAT DOCTRINES: Player %d skips doctrine selection this round" % current_player)

	var log_entry = {
		"type": "SKIP_COMBAT_DOCTRINE",
		"player": current_player,
		"turn": GameState.get_battle_round()
	}
	GameState.add_action_to_phase_log(log_entry)

	return {"success": true, "message": "No Combat Doctrine selected this round"}

# ============================================================================
# DETACHMENT ABILITIES — MARTIAL MASTERY (P2-27)
# ============================================================================

func _validate_select_martial_mastery(action: Dictionary) -> Array:
	var errors = []
	var current_player = get_current_player()
	var mastery_key = action.get("mastery_key", "")

	if mastery_key == "":
		errors.append("Missing mastery_key for Martial Mastery selection")
		return errors

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		errors.append("FactionAbilityManager not available")
		return errors

	if not faction_mgr.is_martial_mastery_available(current_player):
		errors.append("Martial Mastery is not available for player %d" % current_player)
		return errors

	var options = faction_mgr.get_mastery_options()
	var found = false
	for opt in options:
		if opt.key == mastery_key:
			found = true
			break
	if not found:
		errors.append("Unknown Martial Mastery option: %s" % mastery_key)

	return errors

func _handle_select_martial_mastery(action: Dictionary) -> Dictionary:
	var current_player = get_current_player()
	var mastery_key = action.get("mastery_key", "")

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr:
		return {"success": false, "error": "FactionAbilityManager not available"}

	var result = faction_mgr.select_martial_mastery(current_player, mastery_key)

	if result.success:
		log_phase_message("MARTIAL MASTERY: Player %d selects %s" % [
			current_player, result.get("mastery_display", mastery_key)])

		var log_entry = {
			"type": "SELECT_MARTIAL_MASTERY",
			"player": current_player,
			"mastery": mastery_key,
			"mastery_display": result.get("mastery_display", ""),
			"turn": GameState.get_battle_round()
		}
		GameState.add_action_to_phase_log(log_entry)

	return result

# ============================================================================
# P3-29: GROT ORDERLY (Painboss — return D3 destroyed Bodyguard models)
# ============================================================================

func _validate_use_grot_orderly(action: Dictionary) -> Array:
	var errors = []
	var unit_id = action.get("unit_id", "")
	var bodyguard_unit_id = action.get("bodyguard_unit_id", "")
	var current_player = get_current_player()

	if unit_id == "":
		errors.append("Missing unit_id for Grot Orderly")
		return errors

	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not ability_mgr:
		errors.append("UnitAbilityManager not available")
		return errors

	if not ability_mgr.has_grot_orderly(unit_id):
		errors.append("Unit %s does not have an available Grot Orderly ability" % unit_id)
		return errors

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.get("owner", 0) != current_player:
		errors.append("Unit %s does not belong to active player" % unit_id)

	var go_info = ability_mgr.get_grot_orderly_unit(unit_id)
	if not go_info.get("eligible", false):
		errors.append("Painboss's unit is not below starting strength — no models to return")

	return errors

func _handle_use_grot_orderly(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var bodyguard_unit_id = action.get("bodyguard_unit_id", "")
	var current_player = get_current_player()

	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not ability_mgr:
		return {"success": false, "error": "UnitAbilityManager not available"}

	var go_info = ability_mgr.get_grot_orderly_unit(unit_id)
	if not go_info.get("eligible", false):
		return {"success": false, "error": "Unit is not below starting strength"}

	bodyguard_unit_id = go_info.bodyguard_unit_id

	# Roll D3 to determine how many models to return
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var d3_roll = rng.randi_range(1, 3)
	var destroyed_count = go_info.destroyed_count
	var models_to_return = mini(d3_roll, destroyed_count)

	print("CommandPhase: Grot Orderly — rolled D3 = %d, returning %d model(s) to %s" % [d3_roll, models_to_return, bodyguard_unit_id])

	# Find destroyed models in the bodyguard unit and revive them
	var bodyguard_unit = GameState.state.get("units", {}).get(bodyguard_unit_id, {})
	var models = bodyguard_unit.get("models", [])
	var changes = []
	var returned = 0

	for i in range(models.size()):
		if returned >= models_to_return:
			break
		var model = models[i]
		if not model.get("alive", true):
			# Revive this model at full wounds
			var max_wounds = model.get("wounds", 1)
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [bodyguard_unit_id, i],
				"value": true
			})
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [bodyguard_unit_id, i],
				"value": max_wounds
			})
			returned += 1
			print("CommandPhase: Grot Orderly — returned model %s (index %d) with %d wounds" % [model.get("id", ""), i, max_wounds])

	# Apply changes
	if changes.size() > 0:
		PhaseManager.apply_state_changes(changes)

	# Mark Grot Orderly as used (once per battle)
	ability_mgr.mark_once_per_battle_used(unit_id, "Grot Orderly")

	var painboss_name = GameState.state.get("units", {}).get(unit_id, {}).get("meta", {}).get("name", unit_id)
	var bg_name = go_info.bodyguard_unit_name

	log_phase_message("GROT ORDERLY: %s returns %d model(s) to %s (rolled D3 = %d)" % [
		painboss_name, returned, bg_name, d3_roll])

	# Log to phase log
	var log_entry = {
		"type": "USE_GROT_ORDERLY",
		"player": current_player,
		"painboss_unit_id": unit_id,
		"bodyguard_unit_id": bodyguard_unit_id,
		"d3_roll": d3_roll,
		"models_returned": returned,
		"turn": GameState.get_battle_round()
	}
	GameState.add_action_to_phase_log(log_entry)

	return {
		"success": true,
		"unit_id": unit_id,
		"bodyguard_unit_id": bodyguard_unit_id,
		"d3_roll": d3_roll,
		"models_returned": returned,
		"message": "Grot Orderly: %s returned %d model(s) to %s (D3 = %d)" % [painboss_name, returned, bg_name, d3_roll]
	}

# ============================================================================
# NEW ORDERS STRATAGEM
# ============================================================================

func _validate_use_new_orders(action: Dictionary) -> Array:
	var errors = []
	var mission_index = action.get("mission_index", -1)
	var current_player = get_current_player()

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		errors.append("SecondaryMissionManager not available")
		return errors

	if not secondary_mgr.is_initialized(current_player):
		errors.append("Secondary missions not initialized for player %d" % current_player)
		return errors

	var active = secondary_mgr.get_active_missions(current_player)
	if mission_index < 0 or mission_index >= active.size():
		errors.append("Invalid mission index: %d (have %d active missions)" % [mission_index, active.size()])

	if secondary_mgr.get_deck_size(current_player) == 0:
		errors.append("Deck is empty — cannot draw a replacement")

	# Validate stratagem availability (CP, once-per-battle, etc.)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var can_use = strat_manager.can_use_stratagem(current_player, "new_orders")
		if not can_use.get("can_use", false):
			errors.append(can_use.get("reason", "Cannot use New Orders"))
	else:
		errors.append("StratagemManager not available")

	return errors

func _handle_use_new_orders(action: Dictionary) -> Dictionary:
	var mission_index = action.get("mission_index", -1)
	var current_player = get_current_player()

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		return {"success": false, "error": "SecondaryMissionManager not available"}

	# Record stratagem usage via StratagemManager
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var strat_result = strat_manager.use_stratagem(current_player, "new_orders")
		if not strat_result.get("success", false):
			return {"success": false, "error": strat_result.get("error", "Failed to use New Orders stratagem")}

	var result = secondary_mgr.use_new_orders(current_player, mission_index)

	if result.get("success", false):
		log_phase_message("Player %d used NEW ORDERS (1 CP): discarded %s, drew %s" % [
			current_player, result.get("discarded", "?"), result.get("drawn", "?")])

		# Log to phase log
		var log_entry = {
			"type": "USE_NEW_ORDERS",
			"player": current_player,
			"discarded": result.get("discarded", ""),
			"drawn": result.get("drawn", ""),
			"turn": GameState.get_battle_round()
		}
		GameState.add_action_to_phase_log(log_entry)

	return result

# ============================================================================
# SECONDARY MISSION INTERACTION RESOLUTION
# ============================================================================

func _validate_resolve_marked_for_death(action: Dictionary) -> Array:
	var errors = []
	var player = action.get("player", 0)
	var alpha_targets = action.get("alpha_targets", [])
	var gamma_target = action.get("gamma_target", "")

	if player == 0:
		errors.append("Missing player for RESOLVE_MARKED_FOR_DEATH")
		return errors

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		errors.append("SecondaryMissionManager not available")
		return errors

	# Check that the mission is actually pending interaction
	var player_key = str(player)
	var found_pending = false
	var state = secondary_mgr._player_state.get(player_key, {})
	for mission in state.get("active", []):
		if mission["id"] == "marked_for_death" and mission.get("pending_interaction", false):
			found_pending = true
			break
	if not found_pending:
		errors.append("No pending Marked for Death interaction for player %d" % player)
		return errors

	# Validate alpha targets are alive opponent units
	var opponent = 2 if player == 1 else 1
	var valid_unit_ids = secondary_mgr._get_opponent_units_on_battlefield(player)

	for target_id in alpha_targets:
		if target_id not in valid_unit_ids:
			errors.append("Alpha target %s is not a valid opponent unit" % target_id)

	# Validate gamma target (can be empty if no units remain)
	if gamma_target != "" and gamma_target not in valid_unit_ids:
		errors.append("Gamma target %s is not a valid opponent unit" % gamma_target)

	if gamma_target != "" and gamma_target in alpha_targets:
		errors.append("Gamma target cannot also be an alpha target")

	return errors

func _validate_resolve_tempting_target(action: Dictionary) -> Array:
	var errors = []
	var player = action.get("player", 0)
	var objective_id = action.get("objective_id", "")

	if player == 0:
		errors.append("Missing player for RESOLVE_TEMPTING_TARGET")
		return errors

	if objective_id == "":
		errors.append("Missing objective_id for RESOLVE_TEMPTING_TARGET")
		return errors

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		errors.append("SecondaryMissionManager not available")
		return errors

	# Check that the mission is actually pending interaction
	var player_key = str(player)
	var found_pending = false
	var state = secondary_mgr._player_state.get(player_key, {})
	for mission in state.get("active", []):
		if mission["id"] == "a_tempting_target" and mission.get("pending_interaction", false):
			found_pending = true
			break
	if not found_pending:
		errors.append("No pending A Tempting Target interaction for player %d" % player)
		return errors

	# Validate objective is in No Man's Land
	var all_objectives = GameState.state.get("board", {}).get("objectives", [])
	var found_in_nml = false
	for obj in all_objectives:
		if obj.get("id", "") == objective_id and obj.get("zone", "") == "no_mans_land":
			found_in_nml = true
			break
	if not found_in_nml:
		errors.append("Objective %s is not in No Man's Land" % objective_id)

	return errors

func _handle_resolve_marked_for_death(action: Dictionary) -> Dictionary:
	var player = action.get("player", 0)
	var alpha_targets = action.get("alpha_targets", [])
	var gamma_target = action.get("gamma_target", "")

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		return {"success": false, "error": "SecondaryMissionManager not available"}

	secondary_mgr.resolve_marked_for_death(player, alpha_targets, gamma_target)

	print("CommandPhase: Resolved Marked for Death for player %d — Alpha: %s, Gamma: %s" % [
		player, str(alpha_targets), gamma_target])

	# Log to phase log
	var log_entry = {
		"type": "RESOLVE_MARKED_FOR_DEATH",
		"player": player,
		"alpha_targets": alpha_targets,
		"gamma_target": gamma_target,
		"turn": GameState.get_battle_round()
	}
	GameState.add_action_to_phase_log(log_entry)

	return {
		"success": true,
		"message": "Marked for Death resolved — Alpha: %s, Gamma: %s" % [str(alpha_targets), gamma_target]
	}

func _handle_resolve_tempting_target(action: Dictionary) -> Dictionary:
	var player = action.get("player", 0)
	var objective_id = action.get("objective_id", "")

	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if not secondary_mgr:
		return {"success": false, "error": "SecondaryMissionManager not available"}

	secondary_mgr.resolve_tempting_target(player, objective_id)

	print("CommandPhase: Resolved A Tempting Target for player %d — Objective: %s" % [player, objective_id])

	# Log to phase log
	var log_entry = {
		"type": "RESOLVE_TEMPTING_TARGET",
		"player": player,
		"objective_id": objective_id,
		"turn": GameState.get_battle_round()
	}
	GameState.add_action_to_phase_log(log_entry)

	return {
		"success": true,
		"message": "A Tempting Target resolved — Objective: %s" % objective_id
	}

func _handle_end_command() -> Dictionary:
	var current_player = get_current_player()

	# Auto-resolve any remaining battle-shock tests
	var auto_resolved = []
	for unit_id in _units_needing_test:
		if unit_id not in _units_tested:
			var auto_result = _handle_battle_shock_test({"unit_id": unit_id})
			auto_resolved.append(auto_result)

	if auto_resolved.size() > 0:
		print("CommandPhase: Auto-resolved %d remaining battle-shock test(s)" % auto_resolved.size())

	# Auto-resolve faction abilities (Oath of Moment target selection)
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_mgr:
		faction_mgr.on_command_phase_end(current_player)

	# Warn about pending secondary mission interactions
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr:
		for p in [1, 2]:
			var player_key = str(p)
			var state = secondary_mgr._player_state.get(player_key, {})
			for mission in state.get("active", []):
				if mission.get("pending_interaction", false):
					print("CommandPhase: WARNING — Player %d has pending interaction for %s, auto-resolving" % [p, mission["name"]])
					_auto_resolve_pending_interaction(p, mission, secondary_mgr)

	# Apply sticky objective locks at end of Command phase
	# "Get Da Good Bitz" / "Objective Secured": if a unit with this ability is within range
	# of a controlled objective, that objective stays under your control until the opponent takes it.
	if MissionManager:
		MissionManager.apply_sticky_objectives(current_player)

	print("CommandPhase: Player %d ending command phase" % current_player)

	# Score primary objectives before ending phase
	if MissionManager:
		MissionManager.score_primary_objectives()

	# Emit phase completion signal to proceed to next phase
	emit_signal("phase_completed")

	return {
		"success": true,
		"message": "Command phase ended, objectives scored",
		"auto_resolved_tests": auto_resolved
	}

func _auto_resolve_pending_interaction(player: int, mission: Dictionary, secondary_mgr) -> void:
	"""Auto-resolve a pending secondary mission interaction when ending the phase."""
	var mission_id = mission.get("id", "")

	match mission_id:
		"marked_for_death":
			# Auto-select first available units as targets
			var opponent_units = secondary_mgr._get_opponent_units_on_battlefield(player)
			var alpha_count = min(3, max(0, opponent_units.size() - 1))
			var alpha_targets = opponent_units.slice(0, alpha_count)
			var gamma_target = opponent_units[alpha_count] if opponent_units.size() > alpha_count else ""
			secondary_mgr.resolve_marked_for_death(player, alpha_targets, gamma_target)
			print("CommandPhase: Auto-resolved Marked for Death — Alpha: %s, Gamma: %s" % [str(alpha_targets), gamma_target])

		"a_tempting_target":
			# Auto-select first NML objective
			var all_objectives = GameState.state.get("board", {}).get("objectives", [])
			for obj in all_objectives:
				if obj.get("zone", "") == "no_mans_land":
					secondary_mgr.resolve_tempting_target(player, obj.get("id", ""))
					print("CommandPhase: Auto-resolved A Tempting Target — Objective: %s" % obj.get("id", ""))
					return
			print("CommandPhase: WARNING — Could not auto-resolve A Tempting Target, no NML objectives found")

		_:
			print("CommandPhase: WARNING — Unknown pending interaction type for mission %s" % mission_id)

func _should_complete_phase() -> bool:
	# Don't auto-complete - phase completion will be triggered by END_COMMAND action
	return false

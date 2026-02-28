extends BasePhase
class_name FormationsPhase

const BasePhase = preload("res://phases/BasePhase.gd")

# FormationsPhase - Handles the "Declare Battle Formations" step before deployment
# Per 10e rules:
# - Before deployment, each player secretly declares:
#   1. Leader attachments (which CHARACTER attaches to which bodyguard)
#   2. Transport embarkations (which units start inside which transports)
#   3. Strategic Reserves / Deep Strike declarations
# - Both players reveal simultaneously, then deployment begins
#
# In single-player / hotseat mode, each player declares in turn (their choices hidden).
# The phase auto-skips if no declarations are possible (no characters, transports, or reserve-eligible units).

# Track declarations per player
var player_formations: Dictionary = {}  # player_number -> {leader_attachments, transport_embarkations, reserves}
var players_confirmed: Dictionary = {}  # player_number -> bool
var current_declaring_player: int = 1

func _init():
	phase_type = GameStateData.Phase.FORMATIONS

func _is_player_confirmed(player: int) -> bool:
	# Check both local state AND GameState (which is synced via diffs in multiplayer)
	if players_confirmed.get(player, false):
		return true
	# Fallback: check GameState for confirmation synced via network diffs
	var meta = GameState.state.get("meta", {})
	return meta.get("formations_p%d_confirmed" % player, false)

func _on_phase_enter() -> void:
	log_phase_message("Entering Declare Battle Formations Phase")
	player_formations.clear()
	players_confirmed.clear()

	# Initialize empty formations for both players
	var meta = GameState.state.get("meta", {})
	for player in [1, 2]:
		player_formations[player] = {
			"leader_attachments": {},  # character_id -> bodyguard_id
			"transport_embarkations": {},  # transport_id -> [unit_ids]
			"reserves": []  # [{unit_id: id, reserve_type: type}]
		}
		# Sync confirmation state from GameState (may have been set via network diffs)
		players_confirmed[player] = meta.get("formations_p%d_confirmed" % player, false)

	# Check if there's anything to declare for either player
	var p1_has_options = _player_has_declaration_options(1)
	var p2_has_options = _player_has_declaration_options(2)

	log_phase_message("Player 1 has declaration options: %s" % str(p1_has_options))
	log_phase_message("Player 2 has declaration options: %s" % str(p2_has_options))

	if not p1_has_options and not p2_has_options:
		log_phase_message("No formations to declare for either player, skipping phase")
		# Store empty formations and mark as declared directly via PhaseManager
		if get_parent() and get_parent().has_method("apply_state_changes"):
			var empty_formations = {}
			for p in [1, 2]:
				empty_formations[str(p)] = player_formations.get(p, {
					"leader_attachments": {},
					"transport_embarkations": {},
					"reserves": []
				})
			get_parent().apply_state_changes([
				{"op": "set", "path": "meta.formations", "value": empty_formations},
				{"op": "set", "path": "meta.formations_declared", "value": true}
			])
		call_deferred("_complete_phase")
		return

	# Start with Player 1
	current_declaring_player = 1
	GameState.set_active_player(current_declaring_player)
	log_phase_message("Player %d begins declaring formations" % current_declaring_player)

func _complete_phase() -> void:
	emit_signal("phase_completed")

func _on_phase_exit() -> void:
	log_phase_message("Exiting Formations Phase")

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	match action_type:
		"DECLARE_LEADER_ATTACHMENT":
			return _validate_declare_leader_attachment(action)
		"DECLARE_TRANSPORT_EMBARKATION":
			return _validate_declare_transport_embarkation(action)
		"DECLARE_RESERVES":
			return _validate_declare_reserves(action)
		"UNDECLARE_LEADER_ATTACHMENT":
			return _validate_undeclare_leader_attachment(action)
		"UNDECLARE_TRANSPORT_EMBARKATION":
			return _validate_undeclare_transport_embarkation(action)
		"UNDECLARE_RESERVES":
			return _validate_undeclare_reserves(action)
		"CONFIRM_FORMATIONS":
			return _validate_confirm_formations(action)
		"END_FORMATIONS":
			return _validate_end_formations(action)
		"DEBUG_MOVE":
			return {"valid": true}
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"DECLARE_LEADER_ATTACHMENT":
			return _process_declare_leader_attachment(action)
		"DECLARE_TRANSPORT_EMBARKATION":
			return _process_declare_transport_embarkation(action)
		"DECLARE_RESERVES":
			return _process_declare_reserves(action)
		"UNDECLARE_LEADER_ATTACHMENT":
			return _process_undeclare_leader_attachment(action)
		"UNDECLARE_TRANSPORT_EMBARKATION":
			return _process_undeclare_transport_embarkation(action)
		"UNDECLARE_RESERVES":
			return _process_undeclare_reserves(action)
		"CONFIRM_FORMATIONS":
			return _process_confirm_formations(action)
		"END_FORMATIONS":
			return _process_end_formations(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# ========================================
# Validation Methods
# ========================================

func _validate_declare_leader_attachment(action: Dictionary) -> Dictionary:
	var errors = []
	var character_id = action.get("character_id", "")
	var bodyguard_id = action.get("bodyguard_id", "")

	if character_id == "":
		errors.append("Missing character_id")
	if bodyguard_id == "":
		errors.append("Missing bodyguard_id")
	if errors.size() > 0:
		return {"valid": false, "errors": errors}

	var character = get_unit(character_id)
	var bodyguard = get_unit(bodyguard_id)

	if character.is_empty():
		errors.append("Character unit not found: " + character_id)
		return {"valid": false, "errors": errors}
	if bodyguard.is_empty():
		errors.append("Bodyguard unit not found: " + bodyguard_id)
		return {"valid": false, "errors": errors}

	# Must belong to declaring player
	var player = action.get("player", get_current_player())
	if character.get("owner", 0) != player:
		errors.append("Character does not belong to declaring player")
	if bodyguard.get("owner", 0) != player:
		errors.append("Bodyguard does not belong to declaring player")

	# Character must have CHARACTER keyword + leader_data
	var char_keywords = character.get("meta", {}).get("keywords", [])
	if "CHARACTER" not in char_keywords:
		errors.append("Unit is not a CHARACTER: " + character_id)
	var leader_data = character.get("meta", {}).get("leader_data", {})
	var can_lead = leader_data.get("can_lead", [])
	if can_lead.is_empty():
		errors.append("Character has no Leader ability: " + character_id)

	# Bodyguard must not be a CHARACTER
	var bg_keywords = bodyguard.get("meta", {}).get("keywords", [])
	if "CHARACTER" in bg_keywords:
		errors.append("Cannot attach to another CHARACTER unit")

	# Check keyword compatibility
	if can_lead.size() > 0:
		var has_match = false
		for lead_keyword in can_lead:
			if lead_keyword in bg_keywords:
				has_match = true
				break
		if not has_match:
			errors.append("Character cannot lead this unit type")

	# Check character not already declared as attached
	var formations = player_formations.get(player, {})
	var attachments = formations.get("leader_attachments", {})
	if attachments.has(character_id):
		errors.append("Character already declared as attached to: " + str(attachments[character_id]))

	# Check bodyguard doesn't already have too many characters
	# Boyz with 20 models and BODYGUARD ability can take 2 leaders (one must be WARBOSS)
	var existing_leaders_on_bg = []
	for char_id in attachments:
		if attachments[char_id] == bodyguard_id:
			existing_leaders_on_bg.append(char_id)

	if existing_leaders_on_bg.size() > 0:
		# Check if dual-leader is allowed (BODYGUARD ability + 20 models)
		var bg_abilities = bodyguard.get("meta", {}).get("abilities", [])
		var has_bodyguard_ability = false
		for ab in bg_abilities:
			if ab is Dictionary and ab.get("name", "").to_lower() == "bodyguard":
				has_bodyguard_ability = true
				break
			elif ab is String and ab.to_lower() == "bodyguard":
				has_bodyguard_ability = true
				break

		var model_count = bodyguard.get("models", []).size()
		var can_take_two = has_bodyguard_ability and model_count >= 20

		if not can_take_two or existing_leaders_on_bg.size() >= 2:
			errors.append("Bodyguard already has a character assigned: " + existing_leaders_on_bg[0])
		else:
			# Dual-leader: one must be a WARBOSS
			var existing_char = get_unit(existing_leaders_on_bg[0])
			var existing_kw = existing_char.get("meta", {}).get("keywords", [])
			var new_is_warboss = "WARBOSS" in char_keywords
			var existing_is_warboss = "WARBOSS" in existing_kw
			if not new_is_warboss and not existing_is_warboss:
				errors.append("Dual-leader attachment requires at least one WARBOSS model")
			else:
				print("FormationsPhase: Dual-leader attachment approved - %s joins %s on %s" % [character_id, existing_leaders_on_bg[0], bodyguard_id])

	# Check character is not declared as embarked or in reserves
	if _is_unit_declared_embarked(character_id, player):
		errors.append("Character is already declared as embarked in a transport")
	if _is_unit_declared_in_reserves(character_id, player):
		errors.append("Character is already declared as in reserves")

	return {"valid": errors.size() == 0, "errors": errors}

func _validate_declare_transport_embarkation(action: Dictionary) -> Dictionary:
	var errors = []
	var transport_id = action.get("transport_id", "")
	var unit_ids = action.get("unit_ids", [])

	if transport_id == "":
		errors.append("Missing transport_id")
	if unit_ids.is_empty():
		errors.append("No units specified for embarkation")
	if errors.size() > 0:
		return {"valid": false, "errors": errors}

	var transport = get_unit(transport_id)
	if transport.is_empty():
		errors.append("Transport not found: " + transport_id)
		return {"valid": false, "errors": errors}

	var player = action.get("player", get_current_player())
	if transport.get("owner", 0) != player:
		errors.append("Transport does not belong to declaring player")
		return {"valid": false, "errors": errors}

	if not transport.has("transport_data"):
		errors.append("Unit is not a transport: " + transport_id)
		return {"valid": false, "errors": errors}

	var capacity = transport.transport_data.get("capacity", 0)
	var capacity_keywords = transport.transport_data.get("capacity_keywords", [])

	# Validate each unit
	var total_models = 0
	for unit_id in unit_ids:
		var unit = get_unit(unit_id)
		if unit.is_empty():
			errors.append("Unit not found: " + unit_id)
			continue
		if unit.get("owner", 0) != player:
			errors.append("Unit does not belong to declaring player: " + unit_id)
			continue

		# Check keywords if required
		if capacity_keywords.size() > 0:
			var unit_keywords = unit.get("meta", {}).get("keywords", [])
			var has_keyword = false
			for kw in capacity_keywords:
				if kw in unit_keywords:
					has_keyword = true
					break
			if not has_keyword:
				errors.append("Unit missing required transport keyword: " + unit_id)
				continue

		# Check not already declared elsewhere
		if _is_unit_declared_attached(unit_id, player):
			errors.append("Unit already declared as a leader attachment: " + unit_id)
		if _is_unit_declared_in_reserves(unit_id, player):
			errors.append("Unit already declared in reserves: " + unit_id)
		if _is_unit_declared_embarked(unit_id, player):
			errors.append("Unit already declared as embarked: " + unit_id)

		# Count models for capacity
		var model_count = 0
		for model in unit.get("models", []):
			if model.get("alive", true):
				model_count += 1
		total_models += model_count

	# Check capacity
	# Also count any already-declared units in this transport
	var formations = player_formations.get(player, {})
	var existing_embarked = formations.get("transport_embarkations", {}).get(transport_id, [])
	var existing_models = 0
	for existing_unit_id in existing_embarked:
		var existing_unit = get_unit(existing_unit_id)
		for model in existing_unit.get("models", []):
			if model.get("alive", true):
				existing_models += 1

	if existing_models + total_models > capacity:
		errors.append("Exceeds transport capacity: %d + %d > %d" % [existing_models, total_models, capacity])

	return {"valid": errors.size() == 0, "errors": errors}

func _validate_declare_reserves(action: Dictionary) -> Dictionary:
	var errors = []
	var unit_id = action.get("unit_id", "")
	var reserve_type = action.get("reserve_type", "strategic_reserves")

	if unit_id == "":
		errors.append("Missing unit_id")
		return {"valid": false, "errors": errors}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}

	var player = action.get("player", get_current_player())
	if unit.get("owner", 0) != player:
		errors.append("Unit does not belong to declaring player")
		return {"valid": false, "errors": errors}

	# Deep Strike requires the ability
	if reserve_type == "deep_strike":
		if not GameState.unit_has_deep_strike(unit_id):
			errors.append("Unit does not have Deep Strike ability")

	# Check not already declared
	if _is_unit_declared_attached(unit_id, player):
		errors.append("Unit already declared as a leader attachment")
	if _is_unit_declared_embarked(unit_id, player):
		errors.append("Unit already declared as embarked")
	if _is_unit_declared_in_reserves(unit_id, player):
		errors.append("Unit already declared in reserves")

	# Check 25% reserves point cap
	var unit_points = unit.get("meta", {}).get("points", 0)
	var total_points = GameState.get_total_army_points(player)
	var max_reserves_points = int(total_points * 0.25)
	var current_reserves_points = _get_declared_reserves_points(player)

	if current_reserves_points + unit_points > max_reserves_points:
		errors.append("Exceeds 25%% reserves limit: %d + %d > %d (of %d total)" % [current_reserves_points, unit_points, max_reserves_points, total_points])

	return {"valid": errors.size() == 0, "errors": errors}

func _validate_undeclare_leader_attachment(action: Dictionary) -> Dictionary:
	var character_id = action.get("character_id", "")
	if character_id == "":
		return {"valid": false, "errors": ["Missing character_id"]}

	var player = action.get("player", get_current_player())
	var formations = player_formations.get(player, {})
	var attachments = formations.get("leader_attachments", {})

	if not attachments.has(character_id):
		return {"valid": false, "errors": ["Character not declared as attached"]}

	# Can't undeclare after confirming
	if _is_player_confirmed(player):
		return {"valid": false, "errors": ["Cannot modify formations after confirming"]}

	return {"valid": true, "errors": []}

func _validate_undeclare_transport_embarkation(action: Dictionary) -> Dictionary:
	var transport_id = action.get("transport_id", "")
	if transport_id == "":
		return {"valid": false, "errors": ["Missing transport_id"]}

	var player = action.get("player", get_current_player())
	var formations = player_formations.get(player, {})
	var embarkations = formations.get("transport_embarkations", {})

	if not embarkations.has(transport_id):
		return {"valid": false, "errors": ["Transport has no declared embarkations"]}

	if _is_player_confirmed(player):
		return {"valid": false, "errors": ["Cannot modify formations after confirming"]}

	return {"valid": true, "errors": []}

func _validate_undeclare_reserves(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}

	var player = action.get("player", get_current_player())
	if not _is_unit_declared_in_reserves(unit_id, player):
		return {"valid": false, "errors": ["Unit not declared in reserves"]}

	if _is_player_confirmed(player):
		return {"valid": false, "errors": ["Cannot modify formations after confirming"]}

	return {"valid": true, "errors": []}

func _validate_confirm_formations(action: Dictionary) -> Dictionary:
	var player = action.get("player", get_current_player())

	if _is_player_confirmed(player):
		return {"valid": false, "errors": ["Player already confirmed formations"]}

	return {"valid": true, "errors": []}

func _validate_end_formations(action: Dictionary) -> Dictionary:
	# Both players must have confirmed
	if not _is_player_confirmed(1):
		return {"valid": false, "errors": ["Player 1 has not confirmed formations"]}
	if not _is_player_confirmed(2):
		return {"valid": false, "errors": ["Player 2 has not confirmed formations"]}
	return {"valid": true, "errors": []}

# ========================================
# Process Methods
# ========================================

func _process_declare_leader_attachment(action: Dictionary) -> Dictionary:
	var character_id = action.get("character_id", "")
	var bodyguard_id = action.get("bodyguard_id", "")
	var player = action.get("player", get_current_player())

	player_formations[player]["leader_attachments"][character_id] = bodyguard_id

	var char_name = get_unit(character_id).get("meta", {}).get("name", character_id)
	var bg_name = get_unit(bodyguard_id).get("meta", {}).get("name", bodyguard_id)
	log_phase_message("Player %d declares: %s attached to %s" % [player, char_name, bg_name])

	return create_result(true, [])

func _process_declare_transport_embarkation(action: Dictionary) -> Dictionary:
	var transport_id = action.get("transport_id", "")
	var unit_ids = action.get("unit_ids", [])
	var player = action.get("player", get_current_player())

	if not player_formations[player]["transport_embarkations"].has(transport_id):
		player_formations[player]["transport_embarkations"][transport_id] = []
	player_formations[player]["transport_embarkations"][transport_id].append_array(unit_ids)

	var transport_name = get_unit(transport_id).get("meta", {}).get("name", transport_id)
	var unit_names = []
	for uid in unit_ids:
		unit_names.append(get_unit(uid).get("meta", {}).get("name", uid))
	log_phase_message("Player %d declares: %s embarked in %s" % [player, ", ".join(unit_names), transport_name])

	return create_result(true, [])

func _process_declare_reserves(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var reserve_type = action.get("reserve_type", "strategic_reserves")
	var player = action.get("player", get_current_player())

	player_formations[player]["reserves"].append({
		"unit_id": unit_id,
		"reserve_type": reserve_type
	})

	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"
	log_phase_message("Player %d declares: %s in %s" % [player, unit_name, type_label])

	return create_result(true, [])

func _process_undeclare_leader_attachment(action: Dictionary) -> Dictionary:
	var character_id = action.get("character_id", "")
	var player = action.get("player", get_current_player())

	player_formations[player]["leader_attachments"].erase(character_id)
	log_phase_message("Player %d undeclared leader attachment for %s" % [player, character_id])

	return create_result(true, [])

func _process_undeclare_transport_embarkation(action: Dictionary) -> Dictionary:
	var transport_id = action.get("transport_id", "")
	var player = action.get("player", get_current_player())

	player_formations[player]["transport_embarkations"].erase(transport_id)
	log_phase_message("Player %d undeclared transport embarkation for %s" % [player, transport_id])

	return create_result(true, [])

func _process_undeclare_reserves(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", get_current_player())

	var reserves = player_formations[player]["reserves"]
	for i in range(reserves.size()):
		if reserves[i].get("unit_id", "") == unit_id:
			reserves.remove_at(i)
			break

	log_phase_message("Player %d undeclared reserves for %s" % [player, unit_id])

	return create_result(true, [])

func _process_confirm_formations(action: Dictionary) -> Dictionary:
	var player = action.get("player", get_current_player())
	players_confirmed[player] = true

	log_phase_message("Player %d confirmed their battle formations" % player)

	var changes = []

	# Sync confirmation state to GameState via diffs so clients see it
	changes.append({
		"op": "set",
		"path": "meta.formations_p%d_confirmed" % player,
		"value": true
	})

	# If first player confirmed, switch to second player
	if player == current_declaring_player:
		var other_player = 3 - current_declaring_player
		if not _is_player_confirmed(other_player):
			current_declaring_player = other_player
			# Include active_player switch in diffs for network sync
			changes.append({
				"op": "set",
				"path": "meta.active_player",
				"value": other_player
			})
			log_phase_message("Switching to Player %d for declarations" % other_player)

	# If both confirmed, build and return all formation changes
	# (execute_action will apply them and _should_complete_phase triggers phase completion)
	if _is_player_confirmed(1) and _is_player_confirmed(2):
		log_phase_message("Both players confirmed — building formation changes")
		changes.append_array(_build_formation_changes())

	return create_result(true, changes)

func _process_end_formations(action: Dictionary) -> Dictionary:
	log_phase_message("Formations phase ending")
	emit_signal("phase_completed")
	return create_result(true, [])

# ========================================
# Helper Methods
# ========================================

func _player_has_declaration_options(player: int) -> bool:
	"""Check if a player has any formations they could declare."""
	# Check for characters with Leader ability
	var characters = GameState.get_characters_for_player(player)
	if characters.size() > 0:
		return true

	# Check for transports
	var transports = GameState.get_transports_for_player(player)
	if transports.size() > 0:
		return true

	# Check for units that could go into reserves (any unit can go into strategic reserves)
	var units = GameState.get_units_for_player(player)
	if units.size() > 1:  # Need at least 2 units (one to deploy, one for reserves)
		return true

	return false

func _is_unit_declared_attached(unit_id: String, player: int) -> bool:
	var formations = player_formations.get(player, {})
	return formations.get("leader_attachments", {}).has(unit_id)

func _is_unit_declared_embarked(unit_id: String, player: int) -> bool:
	var formations = player_formations.get(player, {})
	var embarkations = formations.get("transport_embarkations", {})
	for transport_id in embarkations:
		if unit_id in embarkations[transport_id]:
			return true
	return false

func _is_unit_declared_in_reserves(unit_id: String, player: int) -> bool:
	var formations = player_formations.get(player, {})
	for entry in formations.get("reserves", []):
		if entry.get("unit_id", "") == unit_id:
			return true
	return false

func _get_declared_reserves_points(player: int) -> int:
	var total = 0
	var formations = player_formations.get(player, {})
	for entry in formations.get("reserves", []):
		var unit = get_unit(entry.get("unit_id", ""))
		total += unit.get("meta", {}).get("points", 0)
	return total

func _build_formation_changes() -> Array:
	"""Build all formation state changes for both players.
	Returns the changes array so it can be included in the action result
	and synced through the normal network mechanism."""
	var changes = []

	for player in [1, 2]:
		var formations = player_formations[player]

		# Leader attachments
		for character_id in formations["leader_attachments"]:
			var bodyguard_id = formations["leader_attachments"][character_id]
			# Set attached_to on character
			changes.append({
				"op": "set",
				"path": "units.%s.attached_to" % character_id,
				"value": bodyguard_id
			})

			# Update bodyguard's attachment_data
			var bodyguard = get_unit(bodyguard_id)
			var current_attached = bodyguard.get("attachment_data", {}).get("attached_characters", []).duplicate()
			current_attached.append(character_id)
			changes.append({
				"op": "set",
				"path": "units.%s.attachment_data.attached_characters" % bodyguard_id,
				"value": current_attached
			})

			var char_name = get_unit(character_id).get("meta", {}).get("name", character_id)
			var bg_name = get_unit(bodyguard_id).get("meta", {}).get("name", bodyguard_id)
			log_phase_message("Applied: %s attached to %s" % [char_name, bg_name])

		# Transport embarkations
		for transport_id in formations["transport_embarkations"]:
			var unit_ids = formations["transport_embarkations"][transport_id]
			for unit_id in unit_ids:
				changes.append({
					"op": "set",
					"path": "units.%s.embarked_in" % unit_id,
					"value": transport_id
				})
			# Update transport's embarked_units list
			var transport = get_unit(transport_id)
			var current_embarked = transport.get("transport_data", {}).get("embarked_units", []).duplicate()
			current_embarked.append_array(unit_ids)
			changes.append({
				"op": "set",
				"path": "units.%s.transport_data.embarked_units" % transport_id,
				"value": current_embarked
			})

			var transport_name = get_unit(transport_id).get("meta", {}).get("name", transport_id)
			log_phase_message("Applied: %d units embarked in %s" % [unit_ids.size(), transport_name])

		# Reserves declarations
		for entry in formations["reserves"]:
			var unit_id = entry["unit_id"]
			var reserve_type = entry["reserve_type"]
			changes.append({
				"op": "set",
				"path": "units.%s.status" % unit_id,
				"value": GameStateData.UnitStatus.IN_RESERVES
			})
			changes.append({
				"op": "set",
				"path": "units.%s.reserve_type" % unit_id,
				"value": reserve_type
			})

			var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
			var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"
			log_phase_message("Applied: %s placed in %s" % [unit_name, type_label])

	# Store formations declarations in meta for reference
	var formations_data = {}
	for player in [1, 2]:
		formations_data[str(player)] = player_formations.get(player, {
			"leader_attachments": {},
			"transport_embarkations": {},
			"reserves": []
		})
	changes.append({
		"op": "set",
		"path": "meta.formations",
		"value": formations_data
	})
	changes.append({
		"op": "set",
		"path": "meta.formations_declared",
		"value": true
	})

	log_phase_message("All formations changes built successfully (%d diffs)" % changes.size())
	return changes

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()

	if _is_player_confirmed(current_player):
		# Already confirmed, check if we can end
		if _is_player_confirmed(1) and _is_player_confirmed(2):
			actions.append({
				"type": "END_FORMATIONS",
				"description": "End Formations Phase"
			})
		return actions

	# Available declarations for current player
	var formations = player_formations.get(current_player, {})

	# Leader attachment options
	var characters = GameState.get_characters_for_player(current_player)
	for char_id in characters:
		if not formations.get("leader_attachments", {}).has(char_id):
			var char_name = get_unit(char_id).get("meta", {}).get("name", char_id)
			var eligible = GameState.get_eligible_bodyguards_for_character(char_id)
			for bg_id in eligible:
				# Check how many leaders already assigned to this bodyguard
				var leaders_on_bg = []
				for existing_char_id in formations.get("leader_attachments", {}):
					if formations["leader_attachments"][existing_char_id] == bg_id:
						leaders_on_bg.append(existing_char_id)

				if leaders_on_bg.size() >= 1:
					# Check if dual-leader is allowed (BODYGUARD ability + 20 models)
					var bg_unit = get_unit(bg_id)
					var bg_abilities = bg_unit.get("meta", {}).get("abilities", [])
					var has_bodyguard_ability = false
					for ab in bg_abilities:
						if ab is Dictionary and ab.get("name", "").to_lower() == "bodyguard":
							has_bodyguard_ability = true
							break
						elif ab is String and ab.to_lower() == "bodyguard":
							has_bodyguard_ability = true
							break
					var bg_model_count = bg_unit.get("models", []).size()
					var can_dual = has_bodyguard_ability and bg_model_count >= 20

					if not can_dual or leaders_on_bg.size() >= 2:
						continue

					# Dual-leader requires one to be WARBOSS
					var char_unit = get_unit(char_id)
					var char_kw = char_unit.get("meta", {}).get("keywords", [])
					var existing_unit = get_unit(leaders_on_bg[0])
					var existing_kw = existing_unit.get("meta", {}).get("keywords", [])
					if "WARBOSS" not in char_kw and "WARBOSS" not in existing_kw:
						continue

				var bg_name = get_unit(bg_id).get("meta", {}).get("name", bg_id)
				actions.append({
					"type": "DECLARE_LEADER_ATTACHMENT",
					"character_id": char_id,
					"bodyguard_id": bg_id,
					"player": current_player,
					"description": "Attach %s to %s" % [char_name, bg_name]
				})

	# Undo attachments
	for char_id in formations.get("leader_attachments", {}):
		var char_name = get_unit(char_id).get("meta", {}).get("name", char_id)
		actions.append({
			"type": "UNDECLARE_LEADER_ATTACHMENT",
			"character_id": char_id,
			"player": current_player,
			"description": "Undo: %s attachment" % char_name
		})

	# Transport embarkation options — only offer if eligible units remain
	var transports = GameState.get_transports_for_player(current_player)
	for transport_id in transports:
		# Check if any non-embarked, non-attached units could fit in this transport
		var has_eligible_units = false
		var transport_data = get_unit(transport_id).get("transport_data", {})
		var capacity = transport_data.get("capacity", 0)
		var already_embarked_ids = formations.get("transport_embarkations", {}).get(transport_id, [])
		var already_embarked_count = 0
		for emb_id in already_embarked_ids:
			var emb_unit = get_unit(emb_id)
			for m in emb_unit.get("models", []):
				if m.get("alive", true):
					already_embarked_count += 1
		if already_embarked_count < capacity:
			var all_player_units = GameState.get_units_for_player(current_player)
			for uid in all_player_units:
				if uid == transport_id:
					continue
				if _is_unit_declared_attached(uid, current_player):
					continue
				if _is_unit_declared_embarked(uid, current_player):
					continue
				if _is_unit_declared_in_reserves(uid, current_player):
					continue
				has_eligible_units = true
				break
		if has_eligible_units:
			var transport_name = get_unit(transport_id).get("meta", {}).get("name", transport_id)
			actions.append({
				"type": "DECLARE_TRANSPORT_EMBARKATION",
				"transport_id": transport_id,
				"player": current_player,
				"description": "Embark units in %s" % transport_name
			})

	# Reserves options
	var units = GameState.get_units_for_player(current_player)
	for unit_id in units:
		if _is_unit_declared_attached(unit_id, current_player):
			continue
		if _is_unit_declared_embarked(unit_id, current_player):
			continue
		if _is_unit_declared_in_reserves(unit_id, current_player):
			continue
		var unit = units[unit_id]
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		if GameState.unit_has_deep_strike(unit_id):
			actions.append({
				"type": "DECLARE_RESERVES",
				"unit_id": unit_id,
				"reserve_type": "deep_strike",
				"player": current_player,
				"description": "Deep Strike %s" % unit_name
			})
		actions.append({
			"type": "DECLARE_RESERVES",
			"unit_id": unit_id,
			"reserve_type": "strategic_reserves",
			"player": current_player,
			"description": "Strategic Reserves %s" % unit_name
		})

	# Undo reserves
	for entry in formations.get("reserves", []):
		var unit_name = get_unit(entry["unit_id"]).get("meta", {}).get("name", entry["unit_id"])
		actions.append({
			"type": "UNDECLARE_RESERVES",
			"unit_id": entry["unit_id"],
			"player": current_player,
			"description": "Undo: %s reserves" % unit_name
		})

	# Confirm button
	actions.append({
		"type": "CONFIRM_FORMATIONS",
		"player": current_player,
		"description": "Confirm Battle Formations"
	})

	return actions

func _should_complete_phase() -> bool:
	return _is_player_confirmed(1) and _is_player_confirmed(2)

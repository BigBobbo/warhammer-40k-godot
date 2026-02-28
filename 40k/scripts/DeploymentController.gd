extends Node
# All classes (GameStateData, BaseShape, CircularBase, OvalBase) are available via class_name
# No preloads needed - using global class names to avoid web export reload issues

signal deployment_complete()
signal unit_confirmed()
signal models_placed_changed()
signal coherency_warning_changed(is_incoherent: bool, message: String)

var unit_id: String = ""
var model_idx: int = -1
var temp_positions: Array = []
var temp_rotations: Array = []  # Store rotations for each model
var token_layer: Node2D
var ghost_layer: Node2D
var ghost_sprite: Node2D = null
var placed_tokens: Array = []

# Formation deployment state
var formation_mode: String = "SINGLE"  # SINGLE, SPREAD, TIGHT
var formation_size: int = 5  # Models per formation group
var formation_preview_ghosts: Array = []  # Ghost visuals for formation
var formation_anchor_pos: Vector2  # Where user clicks to place formation
var formation_rotation: float = 0.0  # Rotation angle for formation (radians)

# Model repositioning state
var repositioning_model: bool = false
var reposition_model_index: int = -1
var reposition_start_pos: Vector2
var reposition_ghost: Node2D = null

# Throttle zone validation debug logging to avoid spam every frame
var _last_zone_debug_center: Vector2 = Vector2.INF

# Transport embark state
var pending_embark_units: Array = []  # Units to embark after deployment
var is_awaiting_embark_dialog: bool = false  # Waiting for transport embark dialog

# Character attachment state
var pending_attach_characters: Array = []  # Characters to attach after deployment
var is_awaiting_attach_dialog: bool = false  # Waiting for character attach dialog

# Combined deployment state (bodyguard + pre-declared attached characters)
var combined_models: Array = []  # [{unit_id, model_idx, model_data}, ...]
var is_combined_deployment: bool = false

# Reinforcement mode (Deep Strike / Strategic Reserves arrival)
var is_reinforcement_mode: bool = false

# Infiltrators mode (deploy anywhere >9" from enemy zone and enemy models)
var is_infiltrators_mode: bool = false

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)

func set_layers(tokens: Node2D, ghosts: Node2D) -> void:
	token_layer = tokens
	ghost_layer = ghosts

func _unhandled_input(event: InputEvent) -> void:
	if not is_placing():
		return

	# In multiplayer, block all input if it's not your turn
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		return

	# Check if we have ghosts to work with (unless repositioning)
	if not repositioning_model and not ghost_sprite and formation_preview_ghosts.is_empty():
		return

	# Handle clicks for formation placement
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var mouse_pos = _get_world_mouse_position()

				# Check for shift+click on deployed model for repositioning
				if Input.is_key_pressed(KEY_SHIFT):
					var deployed_model = _get_deployed_model_at_position(mouse_pos)
					if not deployed_model.is_empty():
						_start_model_repositioning(deployed_model)
						return

				# Handle repositioning end
				if repositioning_model:
					_end_model_repositioning(mouse_pos)
					return

				# Normal placement logic
				if formation_mode != "SINGLE":
					try_place_formation_at(mouse_pos)
				else:
					try_place_at(mouse_pos)
				return
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Cancel repositioning on right-click
			if repositioning_model:
				_cancel_model_repositioning()
				return

	elif event is InputEventMouseMotion:
		if repositioning_model:
			_update_model_repositioning(event.position)
			return

	# Handle Ctrl+Z for per-model undo during deployment
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Z and event.ctrl_pressed:
			if undo_last_model():
				get_viewport().set_input_as_handled()
			return

	# Handle rotation controls during deployment
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			# Rotate left
			if formation_mode == "SINGLE":
				# Rotate individual model ghost
				if ghost_sprite and ghost_sprite.has_method("rotate_by"):
					ghost_sprite.rotate_by(-PI/12)  # 15 degrees
			else:
				# Rotate formation
				formation_rotation -= PI/12  # 15 degrees counter-clockwise
		elif event.keycode == KEY_E:
			# Rotate right
			if formation_mode == "SINGLE":
				# Rotate individual model ghost
				if ghost_sprite and ghost_sprite.has_method("rotate_by"):
					ghost_sprite.rotate_by(PI/12)  # 15 degrees
			else:
				# Rotate formation
				formation_rotation += PI/12  # 15 degrees clockwise
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			# Rotate with mouse wheel
			if formation_mode == "SINGLE":
				if ghost_sprite and ghost_sprite.has_method("rotate_by"):
					ghost_sprite.rotate_by(PI/12)
			else:
				formation_rotation += PI/12
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if formation_mode == "SINGLE":
				if ghost_sprite and ghost_sprite.has_method("rotate_by"):
					ghost_sprite.rotate_by(-PI/12)
			else:
				formation_rotation -= PI/12

func begin_deploy(_unit_id: String) -> void:
	print("[DeploymentController] begin_deploy() called for unit: ", _unit_id)

	# In multiplayer, block deployment if it's not your turn
	var network_manager = get_node_or_null("/root/NetworkManager")
	print("[DeploymentController] NetworkManager found: ", network_manager != null)
	if network_manager:
		print("[DeploymentController] is_networked: ", network_manager.is_networked())
		print("[DeploymentController] is_local_player_turn: ", network_manager.is_local_player_turn())
		print("[DeploymentController] local_player: ", network_manager.get_local_player())
		print("[DeploymentController] active_player: ", GameState.get_active_player())

	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		print("[DeploymentController] Blocking deployment - not your turn")
		return

	unit_id = _unit_id
	model_idx = 0
	temp_positions.clear()
	temp_rotations.clear()
	combined_models.clear()
	is_combined_deployment = false
	var unit_data = GameState.get_unit(unit_id)

	# Check if this unit has pre-declared character attachments (from Formations phase)
	var attached_char_ids = unit_data.get("attachment_data", {}).get("attached_characters", [])
	if GameState.formations_declared() and attached_char_ids.size() > 0:
		is_combined_deployment = true
		print("[DeploymentController] Combined deployment: bodyguard %s + %d attached character(s)" % [_unit_id, attached_char_ids.size()])

		# Add bodyguard models first
		for i in range(unit_data["models"].size()):
			combined_models.append({
				"unit_id": _unit_id,
				"model_idx": i,
				"model_data": unit_data["models"][i]
			})

		# Then add character models
		for char_id in attached_char_ids:
			var char_data = GameState.get_unit(char_id)
			if char_data.is_empty():
				push_error("[DeploymentController] Attached character not found: %s" % char_id)
				continue
			for i in range(char_data["models"].size()):
				combined_models.append({
					"unit_id": char_id,
					"model_idx": i,
					"model_data": char_data["models"][i]
				})
			print("[DeploymentController] Added %d models from character %s" % [char_data["models"].size(), char_id])

		# Size temp arrays to fit all combined models
		temp_positions.resize(combined_models.size())
		temp_rotations.resize(combined_models.size())
		temp_rotations.fill(0.0)
		print("[DeploymentController] Combined deployment total models: %d" % combined_models.size())
	else:
		temp_positions.resize(unit_data["models"].size())
		temp_rotations.resize(unit_data["models"].size())
		temp_rotations.fill(0.0)

	formation_rotation = 0.0  # Reset formation rotation for new unit

	# Check if this unit has Infiltrators ability
	is_infiltrators_mode = GameState.unit_has_infiltrators(unit_id)
	if is_infiltrators_mode:
		print("[DeploymentController] Unit %s has Infiltrators - deploying in Infiltrators mode" % _unit_id)

	# Update through PhaseManager instead of BoardState
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance:
			# Set unit status to deploying in GameState
			phase_manager.apply_state_changes([{
				"op": "set",
				"path": "units.%s.status" % unit_id,
				"value": GameStateData.UnitStatus.DEPLOYING
			}])

	# Create appropriate ghosts based on formation mode
	if formation_mode == "SINGLE":
		_create_ghost()
	else:
		var remaining = _get_unplaced_model_indices()
		if not remaining.is_empty():
			_create_formation_ghosts(min(formation_size, remaining.size()))

func is_placing() -> bool:
	return unit_id != ""

func get_current_unit() -> String:
	return unit_id

func get_placed_count() -> int:
	var count = 0
	for pos in temp_positions:
		if pos != null:
			count += 1
	return count

func try_place_at(world_pos: Vector2) -> void:
	if not is_placing():
		return

	if model_idx >= temp_positions.size():
		return

	# Get model data - from combined_models for combined deployment, otherwise from unit
	var model_data: Dictionary
	var spawn_unit_id: String = unit_id
	var spawn_model_idx: int = model_idx
	if is_combined_deployment and model_idx < combined_models.size():
		var cm = combined_models[model_idx]
		model_data = cm["model_data"]
		spawn_unit_id = cm["unit_id"]
		spawn_model_idx = cm["model_idx"]
	else:
		var unit_data = GameState.get_unit(unit_id)
		model_data = unit_data["models"][model_idx]

	var active_player = GameState.get_active_player()
	var zone = BoardState.get_deployment_zone_for_player(active_player)

	# Get current rotation from ghost
	var rotation = 0.0
	if ghost_sprite and ghost_sprite.has_method("get_base_rotation"):
		rotation = ghost_sprite.get_base_rotation()

	# Check placement validity
	if is_reinforcement_mode:
		# Reinforcement mode: validate >9" from enemies, on the board
		if not _validate_reinforcement_position(world_pos, model_data, rotation):
			return
	elif is_infiltrators_mode:
		# Infiltrators mode: validate >9" from enemy zone and enemy models, on the board
		if not _validate_infiltrators_position(world_pos, model_data, rotation):
			return
	else:
		# Normal deployment: check if wholly within deployment zone based on shape
		var base_type = model_data.get("base_type", "circular")
		var is_in_zone = false

		if base_type == "circular":
			var radius_px = Measurement.base_radius_px(model_data["base_mm"])
			is_in_zone = _circle_wholly_in_polygon(world_pos, radius_px, zone)
		else:
			# For non-circular bases, use shape-aware validation
			is_in_zone = _shape_wholly_in_polygon(world_pos, model_data, rotation, zone)

		if not is_in_zone:
			_show_toast("Must be wholly within your deployment zone")
			return

	# Check for overlap with existing models
	if _overlaps_with_existing_models_shape(world_pos, model_data, rotation):
		_show_toast("Cannot overlap with existing models")
		return

	# Check for overlap with walls
	var test_model = model_data.duplicate()
	test_model["position"] = world_pos
	test_model["rotation"] = rotation
	if Measurement.model_overlaps_any_wall(test_model):
		_show_toast("Cannot overlap with walls")
		return

	# Store position and rotation (rotation already captured above)
	temp_positions[model_idx] = world_pos
	temp_rotations[model_idx] = rotation
	_spawn_preview_token(spawn_unit_id, spawn_model_idx, world_pos, rotation)
	model_idx += 1

	_check_coherency_warning()
	emit_signal("models_placed_changed")

	if model_idx < temp_positions.size():
		_update_ghost_for_next_model()

func try_place_formation_at(world_pos: Vector2) -> void:
	"""Place multiple models in formation at once"""
	if formation_mode == "SINGLE":
		try_place_at(world_pos)
		return

	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	var models_to_place = min(formation_size, remaining_indices.size())

	if models_to_place == 0:
		return

	# Calculate formation positions - get model data from combined or unit
	var first_model_data: Dictionary
	if is_combined_deployment and remaining_indices[0] < combined_models.size():
		first_model_data = combined_models[remaining_indices[0]]["model_data"]
	else:
		first_model_data = unit_data["models"][remaining_indices[0]]
	var base_mm = first_model_data["base_mm"]
	var positions = []

	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(world_pos, models_to_place, base_mm, formation_rotation)
		"TIGHT":
			positions = calculate_tight_formation(world_pos, models_to_place, base_mm, formation_rotation)

	# Validate all positions
	var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())
	var all_valid = true
	var error_msg = ""

	for i in range(positions.size()):
		var pos = positions[i]
		var idx = remaining_indices[i]
		var model: Dictionary
		if is_combined_deployment and idx < combined_models.size():
			model = combined_models[idx]["model_data"]
		else:
			model = unit_data["models"][idx]

		if not _validate_formation_position(pos, model, zone):
			all_valid = false
			error_msg = "Formation would place models outside deployment zone or overlapping"
			break

	if not all_valid:
		_show_toast(error_msg)
		return

	# Place all models
	for i in range(positions.size()):
		var idx = remaining_indices[i]
		temp_positions[idx] = positions[i]
		temp_rotations[idx] = 0.0
		var spawn_uid = unit_id
		var spawn_midx = idx
		if is_combined_deployment and idx < combined_models.size():
			spawn_uid = combined_models[idx]["unit_id"]
			spawn_midx = combined_models[idx]["model_idx"]
		_spawn_preview_token(spawn_uid, spawn_midx, positions[i], 0.0)

	# Update model_idx to next unplaced model
	if models_to_place < remaining_indices.size():
		model_idx = remaining_indices[models_to_place]
	else:
		model_idx = temp_positions.size()

	_check_coherency_warning()
	emit_signal("models_placed_changed")

	# Update or clear ghosts
	if model_idx < temp_positions.size():
		if formation_mode == "SINGLE":
			_update_ghost_for_next_model()
		else:
			_create_formation_ghosts(formation_size)
	else:
		_clear_formation_ghosts()
		_remove_ghost()

func undo_last_model() -> bool:
	"""Undo only the most recently placed model. Returns true if a model was undone, false if nothing to undo."""
	if not is_placing():
		return false

	# Find the last placed model by scanning backwards from model_idx
	var last_placed_idx = -1
	for i in range(model_idx - 1, -1, -1):
		if temp_positions[i] != null:
			last_placed_idx = i
			break

	if last_placed_idx == -1:
		print("[DeploymentController] undo_last_model: No placed models to undo")
		return false

	print("[DeploymentController] undo_last_model: Undoing model at index %d" % last_placed_idx)

	# Clear the position and rotation for this model
	temp_positions[last_placed_idx] = null
	temp_rotations[last_placed_idx] = 0.0

	# Remove the corresponding preview token
	var token_unit_id = unit_id
	var token_model_idx = last_placed_idx
	if is_combined_deployment and last_placed_idx < combined_models.size():
		token_unit_id = combined_models[last_placed_idx]["unit_id"]
		token_model_idx = combined_models[last_placed_idx]["model_idx"]
	var token_name = "Token_%s_%d" % [token_unit_id, token_model_idx]
	for i in range(placed_tokens.size() - 1, -1, -1):
		var token = placed_tokens[i]
		if is_instance_valid(token) and token.name == token_name:
			token.queue_free()
			placed_tokens.remove_at(i)
			break

	# Set model_idx back to this model so the ghost appears for it
	model_idx = last_placed_idx

	# Recreate ghost for the model we just undid
	if formation_mode == "SINGLE":
		_remove_ghost()
		_create_ghost()
	else:
		_clear_formation_ghosts()
		var remaining = _get_unplaced_model_indices()
		if not remaining.is_empty():
			_create_formation_ghosts(min(formation_size, remaining.size()))

	_check_coherency_warning()
	emit_signal("models_placed_changed")
	return true

func reset_unit() -> void:
	"""Reset the entire unit — clears all placed models and cancels deployment."""
	_clear_previews()
	temp_positions.fill(null)
	temp_rotations.fill(0.0)  # Reset rotations to default
	model_idx = 0

	# Update through PhaseManager instead of BoardState
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance:
			# If undoing reinforcement, restore to IN_RESERVES instead of UNDEPLOYED
			var restore_status = GameStateData.UnitStatus.IN_RESERVES if is_reinforcement_mode else GameStateData.UnitStatus.UNDEPLOYED
			phase_manager.apply_state_changes([{
				"op": "set",
				"path": "units.%s.status" % unit_id,
				"value": restore_status
			}])

	is_reinforcement_mode = false
	is_infiltrators_mode = false
	is_combined_deployment = false
	combined_models.clear()
	unit_id = ""
	_clear_formation_ghosts()  # Clear any formation ghosts
	_remove_ghost()
	emit_signal("coherency_warning_changed", false, "")

func undo() -> void:
	"""Legacy undo — calls reset_unit() for backward compatibility."""
	reset_unit()

func confirm() -> void:
	# Enforce unit coherency before allowing deployment
	if not _is_unit_coherent():
		_show_toast("Cannot deploy: unit is not in coherency (all models must be within 2\" of mates)", Color.RED)
		return

	# In reinforcement mode, skip embark/attach dialogs and go straight to placement
	if is_reinforcement_mode:
		_complete_deployment()
		return

	# If formations were declared pre-deployment, skip the interactive dialogs
	# The leader attachments and transport embarkations are already applied to GameState
	if GameState.formations_declared():
		DebugLogger.info("Formations pre-declared, skipping deploy-time dialogs", {
			"unit_id": unit_id
		})
		_complete_deployment()
		return

	# Check if this unit can have characters attached - show attach dialog FIRST
	if _has_attachable_characters(unit_id) and not is_awaiting_attach_dialog and not is_awaiting_embark_dialog:
		DebugLogger.info("Unit being deployed has attachable characters - showing attach dialog", {
			"unit_id": unit_id
		})
		is_awaiting_attach_dialog = true
		_show_character_attach_dialog()
		return  # Don't proceed with deployment yet - wait for dialog

	# Check if this is a transport - if so, show embark dialog FIRST
	if _is_transport(unit_id) and not is_awaiting_embark_dialog:
		DebugLogger.info("Transport being deployed - showing embark dialog before confirmation", {
			"unit_id": unit_id
		})
		is_awaiting_embark_dialog = true
		_show_transport_embark_dialog()
		return  # Don't proceed with deployment yet - wait for dialog

	# Proceed with actual deployment (called either directly for non-transports, or after embark dialog closes)
	_complete_deployment()

func _is_transport(unit_id: String) -> bool:
	var unit = GameState.get_unit(unit_id)
	return unit.has("transport_data") and unit.transport_data.get("capacity", 0) > 0

func _has_attachable_characters(p_unit_id: String) -> bool:
	var unit = GameState.get_unit(p_unit_id)
	if unit.is_empty():
		return false
	# Don't show attach dialog for CHARACTER units themselves
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "CHARACTER" in keywords:
		return false
	var player = unit.get("owner", 0)
	var attachable = CharacterAttachmentManager.get_attachable_characters(p_unit_id, player)
	return attachable.size() > 0

func _show_character_attach_dialog() -> void:
	DebugLogger.info("Creating character attach dialog", {"unit_id": unit_id})

	var dialog_script = load("res://scripts/CharacterAttachDialog.gd")
	var dialog = dialog_script.new()
	dialog.setup(unit_id)
	dialog.characters_selected.connect(_on_attach_characters_selected)

	# Add to scene tree and show
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _on_attach_characters_selected(character_ids: Array) -> void:
	DebugLogger.info("Character attach dialog closed", {
		"bodyguard_id": unit_id,
		"selected_characters": character_ids,
		"count": character_ids.size()
	})

	# Store characters to attach AFTER deployment completes
	pending_attach_characters = character_ids
	is_awaiting_attach_dialog = false

	# Now proceed — check if transport dialog is also needed
	confirm()

func _show_transport_embark_dialog() -> void:
	DebugLogger.info("Creating transport embark dialog", {"unit_id": unit_id})

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	dialog.setup(unit_id)
	dialog.units_selected.connect(_on_embark_units_selected)

	# Add to scene tree and show
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _on_embark_units_selected(unit_ids: Array) -> void:
	DebugLogger.info("Embark dialog closed", {
		"transport_id": unit_id,
		"selected_units": unit_ids,
		"count": unit_ids.size()
	})

	# Store units to embark AFTER deployment completes
	pending_embark_units = unit_ids
	is_awaiting_embark_dialog = false

	# Now proceed with actual deployment
	_complete_deployment()

func _complete_deployment() -> void:
	# In multiplayer, verify it's still our turn before submitting
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		print("[DeploymentController] ERROR: Attempted deployment when not your turn")
		push_error("Cannot deploy - not your turn")
		return

	# For combined deployments, split positions back into per-unit arrays
	var bodyguard_positions = []
	var bodyguard_rotations = []
	var char_positions_map = {}  # char_id -> [{pos, rotation}, ...]

	if is_combined_deployment:
		for i in range(combined_models.size()):
			var cm = combined_models[i]
			if cm["unit_id"] == unit_id:
				bodyguard_positions.append(temp_positions[i])
				bodyguard_rotations.append(temp_rotations[i])
			else:
				if not char_positions_map.has(cm["unit_id"]):
					char_positions_map[cm["unit_id"]] = []
				char_positions_map[cm["unit_id"]].append({
					"pos": temp_positions[i],
					"rotation": temp_rotations[i],
					"model_idx": cm["model_idx"]
				})
	else:
		for pos in temp_positions:
			bodyguard_positions.append(pos)
		bodyguard_rotations = temp_rotations.duplicate()

	# Note: Don't set "player" here - NetworkIntegration will add the correct local player ID
	# This ensures the action uses the actual local player, not just whoever's turn it is
	var deployment_action = {
		"type": "DEPLOY_UNIT",
		"unit_id": unit_id,
		"model_positions": bodyguard_positions,
		"model_rotations": bodyguard_rotations,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"timestamp": Time.get_unix_time_from_system()
	}

	# Route through NetworkIntegration (handles multiplayer and single-player)
	var result = NetworkIntegration.route_action(deployment_action)

	if result.success:
		if result.get("pending", false):
			print("[DeploymentController] Deployment submitted to network for unit: ", unit_id)
		else:
			print("[DeploymentController] Deployment successful for unit: ", unit_id)
			print("[DeploymentController] Action should trigger turn switch")

		# Handle embarkation if units were selected
		if pending_embark_units.size() > 0:
			print("[DeploymentController] ===== EMBARKATION TRIGGERED =====")
			print("[DeploymentController] Transport: %s, Units: %s" % [unit_id, str(pending_embark_units)])

			DebugLogger.info("Processing embarkation for selected units", {
				"transport_id": unit_id,
				"units_to_embark": pending_embark_units
			})

			# Check if we're in multiplayer mode (reuse network_manager from line 366)
			var is_networked = network_manager != null and network_manager.is_networked()

			print("[DeploymentController] NetworkManager found: %s, is_networked: %s" % [str(network_manager != null), str(is_networked)])

			if is_networked:
				# In multiplayer, send action for synchronization
				print("[DeploymentController] MULTIPLAYER MODE - sending embarkation action")
				_send_embarkation_action(unit_id, pending_embark_units)
			else:
				# In single-player, execute directly for immediate effect
				print("[DeploymentController] SINGLE-PLAYER MODE - processing embarkation directly")
				_process_embarkation(unit_id, pending_embark_units)

			pending_embark_units = []
			print("[DeploymentController] ===== EMBARKATION COMPLETE =====")
		else:
			print("[DeploymentController] No pending embark units (size: %d)" % pending_embark_units.size())

		# Handle combined deployment: place character models at their player-chosen positions
		if is_combined_deployment and char_positions_map.size() > 0:
			print("[DeploymentController] ===== COMBINED CHARACTER DEPLOYMENT =====")
			for char_id in char_positions_map:
				var char_model_data = char_positions_map[char_id]
				print("[DeploymentController] Placing %d models for character %s" % [char_model_data.size(), char_id])

				# Set each character model's position in GameState
				for entry in char_model_data:
					GameState.state.units[char_id].models[entry["model_idx"]].position = {
						"x": entry["pos"].x,
						"y": entry["pos"].y
					}
					print("[DeploymentController] Set character %s model %d at %s" % [char_id, entry["model_idx"], str(entry["pos"])])

				# Mark character unit as deployed
				if has_node("/root/PhaseManager"):
					var phase_manager = get_node("/root/PhaseManager")
					if phase_manager.current_phase_instance:
						phase_manager.apply_state_changes([{
							"op": "set",
							"path": "units.%s.status" % char_id,
							"value": GameStateData.UnitStatus.DEPLOYED
						}])
						print("[DeploymentController] Set status to DEPLOYED for combined character %s" % char_id)
			print("[DeploymentController] ===== COMBINED CHARACTER DEPLOYMENT COMPLETE =====")

		# Handle character attachment if characters were selected
		if pending_attach_characters.size() > 0:
			print("[DeploymentController] ===== CHARACTER ATTACHMENT TRIGGERED =====")
			print("[DeploymentController] Bodyguard: %s, Characters: %s" % [unit_id, str(pending_attach_characters)])

			DebugLogger.info("Processing character attachment for selected characters", {
				"bodyguard_id": unit_id,
				"characters_to_attach": pending_attach_characters
			})

			var is_networked = network_manager != null and network_manager.is_networked()

			if is_networked:
				print("[DeploymentController] MULTIPLAYER MODE - sending attachment action")
				_send_character_attachment_action(unit_id, pending_attach_characters)
			else:
				print("[DeploymentController] SINGLE-PLAYER MODE - processing attachment directly")
				_process_character_attachment(unit_id, pending_attach_characters)

			pending_attach_characters = []
			print("[DeploymentController] ===== CHARACTER ATTACHMENT COMPLETE =====")
		else:
			print("[DeploymentController] No pending attach characters (size: %d)" % pending_attach_characters.size())
	else:
		print("[DeploymentController] ERROR - Deployment failed for unit: ", unit_id)
		print("[DeploymentController] Errors: ", result.get("errors", []))
		push_error("Deployment failed: " + str(result.get("error", "Unknown error")))

	_finalize_tokens()
	_clear_previews()
	_remove_ghost()

	unit_id = ""
	model_idx = -1
	temp_positions.clear()
	temp_rotations.clear()  # Added to properly clear rotations
	combined_models.clear()
	is_combined_deployment = false
	is_infiltrators_mode = false

	emit_signal("coherency_warning_changed", false, "")
	emit_signal("unit_confirmed")

	if GameState.all_units_deployed():
		emit_signal("deployment_complete")

func _send_embarkation_action(transport_id: String, unit_ids: Array) -> void:
	"""Send embarkation action through network sync (multiplayer only)"""
	# Note: Don't set "player" here - NetworkIntegration will add the correct local player ID
	var embark_action = {
		"type": "EMBARK_UNITS_DEPLOYMENT",
		"transport_id": transport_id,
		"unit_ids": unit_ids,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"timestamp": Time.get_unix_time_from_system()
	}

	var result = NetworkIntegration.route_action(embark_action)

	if result.success:
		DebugLogger.info("Embarkation action sent successfully", {
			"transport_id": transport_id,
			"unit_count": unit_ids.size()
		})
	else:
		push_error("Embarkation action failed: " + str(result.get("error", "Unknown")))
		DebugLogger.error("Failed to send embarkation action", {
			"transport_id": transport_id,
			"unit_ids": unit_ids,
			"error": result.get("error", "Unknown")
		})

func _process_embarkation(transport_id: String, unit_ids: Array) -> void:
	"""Process embarkation directly (single-player mode)"""
	print("[DeploymentController] _process_embarkation called with transport: %s, units: %s" % [transport_id, str(unit_ids)])

	for unit_id in unit_ids:
		print("[DeploymentController] Processing embarkation for unit: %s" % unit_id)

		# Check if unit exists and is undeployed
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			push_error("[DeploymentController] Unit not found: %s" % unit_id)
			continue

		var unit_status = unit.get("status", -1)
		print("[DeploymentController] Unit %s status before embark: %d (0=UNDEPLOYED, 1=DEPLOYING, 2=DEPLOYED)" % [unit_id, unit_status])

		# Use TransportManager to handle the embarkation
		var can_embark_result = TransportManager.can_embark(unit_id, transport_id)
		print("[DeploymentController] Can embark? %s" % str(can_embark_result))

		if can_embark_result.valid:
			TransportManager.embark_unit(unit_id, transport_id)
			print("[DeploymentController] embark_unit() called successfully")
		else:
			push_error("[DeploymentController] Cannot embark %s: %s" % [unit_id, can_embark_result.reason])
			continue

		# Mark embarked units as deployed via PhaseManager
		if has_node("/root/PhaseManager"):
			var phase_manager = get_node("/root/PhaseManager")
			if phase_manager.current_phase_instance:
				phase_manager.apply_state_changes([{
					"op": "set",
					"path": "units.%s.status" % unit_id,
					"value": GameStateData.UnitStatus.DEPLOYED
				}])
				print("[DeploymentController] Set status to DEPLOYED for %s" % unit_id)

		# Verify embarkation
		unit = GameState.get_unit(unit_id)
		var embarked_in = unit.get("embarked_in", null)
		var final_status = unit.get("status", -1)
		print("[DeploymentController] After embark - embarked_in: %s, status: %d" % [str(embarked_in), final_status])

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("[DeploymentController] Embarked %s in %s" % [unit_name, transport_id])

func _send_character_attachment_action(bodyguard_id: String, character_ids: Array) -> void:
	"""Send character attachment action through network sync (multiplayer only)"""
	var attach_action = {
		"type": "ATTACH_CHARACTER_DEPLOYMENT",
		"bodyguard_id": bodyguard_id,
		"character_ids": character_ids,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"timestamp": Time.get_unix_time_from_system()
	}

	var result = NetworkIntegration.route_action(attach_action)

	if result.success:
		DebugLogger.info("Character attachment action sent successfully", {
			"bodyguard_id": bodyguard_id,
			"character_count": character_ids.size()
		})
	else:
		push_error("Character attachment action failed: " + str(result.get("error", "Unknown")))
		DebugLogger.error("Failed to send character attachment action", {
			"bodyguard_id": bodyguard_id,
			"character_ids": character_ids,
			"error": result.get("error", "Unknown")
		})

func _process_character_attachment(bodyguard_id: String, character_ids: Array) -> void:
	"""Process character attachment directly (single-player mode)"""
	print("[DeploymentController] _process_character_attachment called with bodyguard: %s, characters: %s" % [bodyguard_id, str(character_ids)])

	var bodyguard = GameState.get_unit(bodyguard_id)
	if bodyguard.is_empty():
		push_error("[DeploymentController] Bodyguard not found: %s" % bodyguard_id)
		return

	for char_id in character_ids:
		print("[DeploymentController] Processing attachment for character: %s" % char_id)

		var char_unit = GameState.get_unit(char_id)
		if char_unit.is_empty():
			push_error("[DeploymentController] Character unit not found: %s" % char_id)
			continue

		# Use CharacterAttachmentManager to handle the attachment
		var can_attach_result = CharacterAttachmentManager.can_attach(char_id, bodyguard_id)
		print("[DeploymentController] Can attach? %s" % str(can_attach_result))

		if can_attach_result.valid:
			CharacterAttachmentManager.attach_character(char_id, bodyguard_id)
			print("[DeploymentController] attach_character() called successfully")
		else:
			push_error("[DeploymentController] Cannot attach %s: %s" % [char_id, can_attach_result.reason])
			continue

		# Place character model adjacent to bodyguard formation
		_place_character_model_adjacent(char_id, bodyguard_id)

		# Mark character unit as deployed via PhaseManager
		if has_node("/root/PhaseManager"):
			var phase_manager = get_node("/root/PhaseManager")
			if phase_manager.current_phase_instance:
				phase_manager.apply_state_changes([{
					"op": "set",
					"path": "units.%s.status" % char_id,
					"value": GameStateData.UnitStatus.DEPLOYED
				}])
				print("[DeploymentController] Set status to DEPLOYED for character %s" % char_id)

		# Verify attachment
		char_unit = GameState.get_unit(char_id)
		var attached_to = char_unit.get("attached_to", null)
		var final_status = char_unit.get("status", -1)
		print("[DeploymentController] After attach - attached_to: %s, status: %d" % [str(attached_to), final_status])

		var char_name = char_unit.get("meta", {}).get("name", char_id)
		print("[DeploymentController] Attached %s to %s" % [char_name, bodyguard_id])

func _place_character_model_adjacent(char_id: String, bodyguard_id: String) -> void:
	"""Place character model(s) adjacent to the bodyguard formation"""
	var bodyguard = GameState.get_unit(bodyguard_id)
	var char_unit = GameState.get_unit(char_id)

	if bodyguard.is_empty() or char_unit.is_empty():
		return

	# Find the first bodyguard model position as reference
	var ref_pos = Vector2.ZERO
	for model in bodyguard.get("models", []):
		var pos = model.get("position", null)
		if pos != null:
			ref_pos = Vector2(pos.get("x", pos.x if pos is Vector2 else 0), pos.get("y", pos.y if pos is Vector2 else 0))
			break

	if ref_pos == Vector2.ZERO:
		print("[DeploymentController] WARNING: No bodyguard model positions found for adjacent placement")
		return

	# Place character models adjacent to the formation
	var char_models = char_unit.get("models", [])
	for i in range(char_models.size()):
		var model = char_models[i]
		var char_base_mm = model.get("base_mm", 40)
		var bg_base_mm = bodyguard.get("models", [{}])[0].get("base_mm", 32)

		# Offset: place just outside the first bodyguard model's base
		var offset_px = Measurement.base_radius_px(char_base_mm) + Measurement.base_radius_px(bg_base_mm) + 2
		var char_pos = ref_pos + Vector2(offset_px, 0)

		# Update character model position in GameState
		GameState.state.units[char_id].models[i].position = {"x": char_pos.x, "y": char_pos.y}
		print("[DeploymentController] Placed character model %d at %s" % [i, str(char_pos)])

func _create_ghost() -> void:
	print("[DeploymentController] _create_ghost() called")
	print("[DeploymentController] ghost_layer is null: ", ghost_layer == null)
	print("[DeploymentController] unit_id: ", unit_id)
	print("[DeploymentController] model_idx: ", model_idx)

	if ghost_sprite != null:
		ghost_sprite.queue_free()

	var GhostVisualScript = load("res://scripts/GhostVisual.gd")
	print("[DeploymentController] GhostVisual script loaded: ", GhostVisualScript != null)
	if GhostVisualScript == null:
		push_error("[DeploymentController] FAILED to load GhostVisual.gd!")
		return

	ghost_sprite = GhostVisualScript.new()
	print("[DeploymentController] ghost_sprite created: ", ghost_sprite != null)
	ghost_sprite.name = "GhostPreview"

	var unit_data = GameState.get_unit(unit_id)
	print("[DeploymentController] unit_data found: ", not unit_data.is_empty())

	# For combined deployments, use the combined model data
	if is_combined_deployment and model_idx < combined_models.size():
		var cm = combined_models[model_idx]
		var model_data = cm["model_data"]
		var cm_unit_data = GameState.get_unit(cm["unit_id"])
		print("[DeploymentController] combined model_data from unit %s: %s" % [cm["unit_id"], model_data.get("id", "unknown")])
		ghost_sprite.owner_player = cm_unit_data.get("owner", unit_data["owner"])
		ghost_sprite.set_model_data(model_data)
	elif model_idx < unit_data["models"].size():
		var model_data = unit_data["models"][model_idx]
		print("[DeploymentController] model_data: ", model_data.get("id", "unknown"))
		ghost_sprite.owner_player = unit_data["owner"]
		# Set the complete model data for shape handling
		ghost_sprite.set_model_data(model_data)

	if ghost_layer:
		ghost_layer.add_child(ghost_sprite)
		print("[DeploymentController] Ghost added to ghost_layer. Ghost visible: ", ghost_sprite.visible)
		print("[DeploymentController] ghost_layer child count: ", ghost_layer.get_child_count())
	else:
		push_error("[DeploymentController] ghost_layer is NULL - cannot add ghost!")

func _remove_ghost() -> void:
	if ghost_sprite != null:
		ghost_sprite.queue_free()
		ghost_sprite = null

func _update_ghost_for_next_model() -> void:
	if ghost_sprite == null:
		return

	# For combined deployments, use the combined model data
	if is_combined_deployment and model_idx < combined_models.size():
		var cm = combined_models[model_idx]
		var model_data = cm["model_data"]
		ghost_sprite.set_model_data(model_data)
		ghost_sprite.set_base_rotation(0.0)
		ghost_sprite.queue_redraw()
		return

	var unit_data = GameState.get_unit(unit_id)
	if model_idx < unit_data["models"].size():
		var model_data = unit_data["models"][model_idx]
		# Update model data for the next model
		ghost_sprite.set_model_data(model_data)
		# Reset rotation for new model
		ghost_sprite.set_base_rotation(0.0)
		ghost_sprite.queue_redraw()

func _spawn_preview_token(unit_id: String, model_index: int, pos: Vector2, rotation: float = 0.0) -> void:
	var token = _create_token_visual(unit_id, model_index, pos, true, rotation)
	placed_tokens.append(token)
	token_layer.add_child(token)

func _create_token_visual(unit_id: String, model_index: int, pos: Vector2, is_preview: bool = false, rotation: float = 0.0) -> Node2D:
	var token = Node2D.new()
	token.position = pos
	token.name = "Token_%s_%d" % [unit_id, model_index]

	var unit_data = GameState.get_unit(unit_id)
	var model_data = unit_data["models"][model_index].duplicate()
	# Add rotation to model data
	model_data["rotation"] = rotation
	var base_mm = model_data["base_mm"]
	var base_circle = load("res://scripts/TokenVisual.gd").new()
	base_circle.owner_player = unit_data["owner"]
	base_circle.is_preview = is_preview
	base_circle.model_number = model_index + 1
	# Set the complete model data for shape handling
	base_circle.set_model_data(model_data)

	# Set metadata for enhanced visual overlays (sprites, wound pips, etc.)
	var model_id = model_data.get("id", "m%d" % (model_index + 1))
	base_circle.set_meta("unit_id", unit_id)
	base_circle.set_meta("model_id", model_id)
	base_circle.queue_redraw()

	token.add_child(base_circle)

	return token

func _clear_previews() -> void:
	for token in placed_tokens:
		if is_instance_valid(token):
			token.queue_free()
	placed_tokens.clear()

func _finalize_tokens() -> void:
	for token in placed_tokens:
		if is_instance_valid(token):
			for child in token.get_children():
				if child.has_method("set_preview"):
					child.set_preview(false)
	placed_tokens.clear()

func _circle_wholly_in_polygon(center: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(center, polygon):
		return false
	
	for i in range(polygon.size()):
		var p1 = polygon[i]
		var p2 = polygon[(i + 1) % polygon.size()]
		var dist = _point_to_line_distance(center, p1, p2)
		if dist < radius:
			return false
	
	return true

func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	var line_len = line_vec.length()
	
	if line_len == 0:
		return point_vec.length()
	
	var t = max(0, min(1, point_vec.dot(line_vec) / (line_len * line_len)))
	var projection = line_start + t * line_vec
	
	return point.distance_to(projection)

func _check_coherency_warning() -> void:
	var unit_data = GameState.get_unit(unit_id)
	if unit_data.is_empty():
		emit_signal("coherency_warning_changed", false, "")
		return

	# Build list of placed model indices and their data
	var placed_indices = []
	for i in range(temp_positions.size()):
		if temp_positions[i] != null:
			placed_indices.append(i)

	if placed_indices.size() < 2:
		emit_signal("coherency_warning_changed", false, "")
		return

	# Per 10th edition: units with 2-6 models need each model within 2" of at least 1 other.
	# Units with 7+ models need each model within 2" of at least 2 others.
	var total_models = temp_positions.size()  # Use combined total for combined deployments
	var required_neighbors = 1 if total_models <= 6 else 2
	var incoherent_indices = []

	for i in placed_indices:
		# Get model data from combined_models or unit_data
		var model_i: Dictionary
		if is_combined_deployment and i < combined_models.size():
			model_i = combined_models[i]["model_data"].duplicate()
		else:
			model_i = unit_data["models"][i].duplicate()
		model_i["position"] = temp_positions[i]
		model_i["rotation"] = temp_rotations[i] if i < temp_rotations.size() else 0.0

		var neighbor_count = 0
		for j in placed_indices:
			if i == j:
				continue
			var model_j: Dictionary
			if is_combined_deployment and j < combined_models.size():
				model_j = combined_models[j]["model_data"].duplicate()
			else:
				model_j = unit_data["models"][j].duplicate()
			model_j["position"] = temp_positions[j]
			model_j["rotation"] = temp_rotations[j] if j < temp_rotations.size() else 0.0

			# Use edge-to-edge distance (shape-aware) instead of center-to-center
			var dist_inches = Measurement.model_to_model_distance_inches(model_i, model_j)
			if dist_inches <= 2.0:
				neighbor_count += 1
				if neighbor_count >= required_neighbors:
					break

		if neighbor_count < required_neighbors:
			incoherent_indices.append(i)

	if incoherent_indices.size() > 0:
		var rule_text = "within 2\" of %d+ model(s)" % required_neighbors
		var msg = "Coherency warning: %d model(s) not %s" % [incoherent_indices.size(), rule_text]
		print("[WARNING] %s" % msg)
		_show_toast(msg, Color.YELLOW)
		emit_signal("coherency_warning_changed", true, msg)
	else:
		emit_signal("coherency_warning_changed", false, "")

func _is_unit_coherent() -> bool:
	"""Check if the currently placed models satisfy unit coherency rules.
	Per 10e rules: 2-6 models = each within 2\" of at least 1 other;
	7+ models = each within 2\" of at least 2 others.
	Single-model units are always coherent."""
	var placed_positions = []
	for pos in temp_positions:
		if pos != null:
			placed_positions.append(pos)

	# Single model or empty — always coherent
	if placed_positions.size() <= 1:
		return true

	# Check all models are placed before enforcing
	var total_models = temp_positions.size()
	if placed_positions.size() < total_models:
		# Not all models placed yet — can't enforce coherency
		return true

	var required_neighbors = 1 if placed_positions.size() <= 6 else 2

	for pos in placed_positions:
		var neighbor_count = 0
		for other_pos in placed_positions:
			if pos != other_pos:
				var dist_inches = Measurement.distance_inches(pos, other_pos)
				if dist_inches <= 2.0:
					neighbor_count += 1
					if neighbor_count >= required_neighbors:
						break
		if neighbor_count < required_neighbors:
			return false

	return true

func _shape_wholly_in_polygon(center: Vector2, model_data: Dictionary, rotation: float, polygon: PackedVector2Array) -> bool:
	# Create the base shape
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	# For circular, use existing method
	if shape.get_type() == "circular":
		var circular = shape as CircularBase
		return _circle_wholly_in_polygon(center, circular.radius, polygon)

	# For non-circular shapes, we need to check multiple points around the edge
	var _should_log = center.distance_to(_last_zone_debug_center) > 1.0
	if _should_log:
		_last_zone_debug_center = center
		print("\n=== DEBUG: Zone Validation for %s ===" % shape.get_type())
		print("Center: ", center)
		print("Rotation: %.2f degrees (%.4f radians)" % [rad_to_deg(rotation), rotation])

	# Generate sample points around the shape's edge
	var sample_points = []

	if shape.get_type() == "oval":
		# For ovals, sample points around the ellipse perimeter
		var oval = shape as OvalBase
		var num_samples = 16  # Check 16 points around the ellipse
		if _should_log:
			print("Oval shape - length: %.2f, width: %.2f" % [oval.length, oval.width])

		for i in range(num_samples):
			var angle = (i * TAU) / num_samples
			# Points on ellipse: (a*cos(θ), b*sin(θ))
			var local_point = Vector2(
				oval.length * cos(angle),
				oval.width * sin(angle)
			)
			sample_points.append(local_point)
	elif shape.get_type() == "rectangular":
		# For rectangles, check the 4 corners
		var bounds = shape.get_bounds()
		var half_width = bounds.size.x / 2.0
		var half_height = bounds.size.y / 2.0

		sample_points = [
			Vector2(-half_width, -half_height),
			Vector2(half_width, -half_height),
			Vector2(half_width, half_height),
			Vector2(-half_width, half_height)
		]
	else:
		# Fallback: use bounding box corners
		var bounds = shape.get_bounds()
		var half_width = bounds.size.x / 2.0
		var half_height = bounds.size.y / 2.0

		sample_points = [
			Vector2(-half_width, -half_height),
			Vector2(half_width, -half_height),
			Vector2(half_width, half_height),
			Vector2(-half_width, half_height)
		]

	if _should_log:
		print("Checking %d sample points" % sample_points.size())

	# Transform sample points to world space and check if in polygon
	var point_idx = 0
	for local_point in sample_points:
		var world_point = shape.to_world_space(local_point, center, rotation)
		var in_poly = Geometry2D.is_point_in_polygon(world_point, polygon)

		if _should_log and (point_idx < 4 or not in_poly):  # Only print first 4 and failures
			print("Point %d: local=%s -> world=%s, in_polygon=%s" % [point_idx, local_point, world_point, in_poly])

		if not in_poly:
			print("❌ FAILED: Point outside polygon")
			return false

		point_idx += 1

	if _should_log:
		print("✅ SUCCESS: All %d points in polygon" % sample_points.size())
	return true

func _overlaps_with_existing_models_shape(pos: Vector2, model_data: Dictionary, rotation: float) -> bool:
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	# Check overlap with already placed models in current unit
	var unit_data = GameState.get_unit(unit_id)
	for i in range(temp_positions.size()):
		if temp_positions[i] != null:
			var other_model_data = unit_data["models"][i]
			var other_rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0
			if _shapes_overlap(pos, model_data, rotation, temp_positions[i], other_model_data, other_rotation):
				return true

	# Check overlap with all deployed models from all units
	var all_units = GameState.state.get("units", {})
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
			for model in other_unit["models"]:
				var model_position = model.get("position", null)
				if model_position:
					var other_pos = Vector2(model_position.x, model_position.y)
					var other_rotation = model.get("rotation", 0.0)
					if _shapes_overlap(pos, model_data, rotation, other_pos, model, other_rotation):
						return true

	return false

func _shapes_overlap(pos1: Vector2, model1: Dictionary, rot1: float, pos2: Vector2, model2: Dictionary, rot2: float) -> bool:
	# Use actual shape collision detection from BaseShape API
	var shape1 = Measurement.create_base_shape(model1)
	var shape2 = Measurement.create_base_shape(model2)

	if not shape1 or not shape2:
		return false

	# Use shape-aware collision (works for all shape combinations)
	return shape1.overlaps_with(shape2, pos1, rot1, pos2, rot2)

func _get_shape_max_extent(model_data: Dictionary) -> float:
	"""Get maximum extent of a model's base shape for spacing calculations"""
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		# Fallback to circular assumption
		return Measurement.base_radius_px(model_data.get("base_mm", 32))

	var bounds = shape.get_bounds()
	return max(bounds.size.x, bounds.size.y)

func _overlaps_with_existing_models(pos: Vector2, radius: float) -> bool:
	# Check overlap with already placed models in current unit
	for placed_pos in temp_positions:
		if placed_pos != null:
			var distance = pos.distance_to(placed_pos)
			var other_radius = radius  # Same unit, same base size
			if distance < (radius + other_radius):
				return true

	# Check overlap with all deployed models from all units
	var all_units = GameState.state.get("units", {})
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
			for model in other_unit["models"]:
				var model_position = model.get("position", null)
				if model_position != null:
					var model_pos = Vector2(model_position.get("x", 0), model_position.get("y", 0))
					var distance = pos.distance_to(model_pos)
					var other_radius = Measurement.base_radius_px(model["base_mm"])
					if distance < (radius + other_radius):
						return true
	
	return false

func _show_toast(message: String, color: Color = Color.RED) -> void:
	print("[%s] %s" % ["WARNING" if color == Color.YELLOW else "ERROR", message])
	# Show on-screen toast via ToastManager
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		if color == Color.YELLOW:
			toast_mgr.show_warning(message)
		else:
			toast_mgr.show_error(message)

func _dict_array_to_packed_vector2(dict_array: Array) -> PackedVector2Array:
	var packed = PackedVector2Array()
	for dict in dict_array:
		if dict is Dictionary and dict.has("x") and dict.has("y"):
			packed.append(Vector2(dict.x, dict.y))
	return packed

func _process(delta: float) -> void:
	if not is_placing():
		return

	var mouse_pos = _get_world_mouse_position()

	# Handle repositioning ghost updates (highest priority)
	if repositioning_model and reposition_ghost:
		reposition_ghost.position = mouse_pos
		var unit_data = GameState.get_unit(unit_id)
		var model_data = unit_data["models"][reposition_model_index]
		var is_valid = _validate_reposition(mouse_pos, model_data, reposition_model_index)
		reposition_ghost.set_validity(is_valid)
		return

	# Handle formation mode ghost updates
	if formation_mode != "SINGLE" and not formation_preview_ghosts.is_empty():
		_update_formation_ghost_positions(mouse_pos)
		return

	# Handle single mode ghost updates
	if ghost_sprite != null and model_idx < temp_positions.size():
		ghost_sprite.position = mouse_pos

		# Get model data - from combined_models for combined deployment, otherwise from unit
		var model_data: Dictionary
		if is_combined_deployment and model_idx < combined_models.size():
			model_data = combined_models[model_idx]["model_data"]
		else:
			var unit_data = GameState.get_unit(unit_id)
			model_data = unit_data["models"][model_idx]
		var active_player = GameState.get_active_player()

		# Get current rotation from ghost
		var rotation = 0.0
		if ghost_sprite.has_method("get_base_rotation"):
			rotation = ghost_sprite.get_base_rotation()

		var is_valid = false

		if is_reinforcement_mode:
			# Reinforcement mode: validate >9" from enemies instead of deployment zone
			is_valid = _validate_reinforcement_position(mouse_pos, model_data, rotation)
			# Also check model overlap
			if is_valid and _overlaps_with_existing_models_shape(mouse_pos, model_data, rotation):
				is_valid = false
		elif is_infiltrators_mode:
			# Infiltrators mode: validate >9" from enemy zone and enemy models
			is_valid = _validate_infiltrators_position(mouse_pos, model_data, rotation)
			# Also check model overlap
			if is_valid and _overlaps_with_existing_models_shape(mouse_pos, model_data, rotation):
				is_valid = false
		else:
			# Normal deployment: check deployment zone and model overlap
			var zone = BoardState.get_deployment_zone_for_player(active_player)
			var base_type = model_data.get("base_type", "circular")

			if base_type == "circular":
				var radius_px = Measurement.base_radius_px(model_data["base_mm"])
				is_valid = _circle_wholly_in_polygon(mouse_pos, radius_px, zone) and not _overlaps_with_existing_models(mouse_pos, radius_px)
			else:
				is_valid = _shape_wholly_in_polygon(mouse_pos, model_data, rotation, zone) and not _overlaps_with_existing_models_shape(mouse_pos, model_data, rotation)

		# Also check wall collision
		if is_valid:
			var test_model = model_data.duplicate()
			test_model["position"] = mouse_pos
			test_model["rotation"] = rotation
			if Measurement.model_overlaps_any_wall(test_model):
				is_valid = false

		if ghost_sprite.has_method("set_validity"):
			ghost_sprite.set_validity(is_valid)

func _get_world_mouse_position() -> Vector2:
	# Get the main scene to access the coordinate conversion
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("screen_to_world_position"):
		var screen_pos = get_viewport().get_mouse_position()
		return main_scene.screen_to_world_position(screen_pos)
	else:
		# Fallback to simple mouse position
		return get_viewport().get_mouse_position()

# Formation mode management
func set_formation_mode(mode: String) -> void:
	formation_mode = mode
	formation_rotation = 0.0  # Reset rotation when changing modes
	print("[DeploymentController] Formation mode set to: ", mode)

	# If we're currently placing, update the ghosts
	if is_placing():
		if mode == "SINGLE":
			_clear_formation_ghosts()
			if not ghost_sprite:
				_create_ghost()
		else:
			_remove_ghost()
			var remaining = _get_unplaced_model_indices()
			if not remaining.is_empty():
				_create_formation_ghosts(min(formation_size, remaining.size()))

func _get_unplaced_model_indices() -> Array:
	"""Get indices of models that haven't been placed yet"""
	var unplaced = []
	for i in range(temp_positions.size()):
		if temp_positions[i] == null:
			unplaced.append(i)
	return unplaced

# Formation calculation functions
func calculate_spread_formation(anchor_pos: Vector2, model_count: int, base_mm: int, rotation: float = 0.0) -> Array:
	"""Calculate positions for maximum spread (2 inch coherency)"""
	var positions = []

	# Get first model data to determine base type
	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	if remaining_indices.is_empty():
		return positions

	var model_data = unit_data["models"][remaining_indices[0]]
	var shape = Measurement.create_base_shape(model_data)

	# Use bounding box for spacing calculations
	var bounds = shape.get_bounds()
	var spacing_inches = 2.0  # Maximum coherency distance
	var spacing_px = Measurement.inches_to_px(spacing_inches)

	# For spacing, use the maximum dimension of the base
	var base_extent = max(bounds.size.x, bounds.size.y)
	var total_spacing = spacing_px + base_extent

	# Arrange in rows of 5
	var cols = min(5, model_count)
	var rows = ceil(model_count / 5.0)

	for i in range(model_count):
		var col = i % cols
		var row = floor(i / cols)
		var x_offset = (col - cols/2.0) * total_spacing
		var y_offset = row * total_spacing
		var base_pos = Vector2(x_offset, y_offset)

		# Apply rotation around origin, then translate to anchor
		var rotated_pos = base_pos.rotated(rotation)
		positions.append(anchor_pos + rotated_pos)

	return positions

func calculate_tight_formation(anchor_pos: Vector2, model_count: int, base_mm: int, rotation: float = 0.0) -> Array:
	"""Calculate positions for tight formation (bases touching)"""
	var positions = []

	# Get first model data to determine base type
	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	if remaining_indices.is_empty():
		return positions

	var model_data = unit_data["models"][remaining_indices[0]]
	var shape = Measurement.create_base_shape(model_data)

	# Use bounding box for spacing calculations
	var bounds = shape.get_bounds()

	# For tight formation, use actual dimensions plus minimal gap
	var base_extent = max(bounds.size.x, bounds.size.y)
	var spacing_px = base_extent + 1  # 1px gap to prevent overlap

	# Arrange in rows of 5
	var cols = min(5, model_count)
	var rows = ceil(model_count / 5.0)

	for i in range(model_count):
		var col = i % cols
		var row = floor(i / cols)
		var x_offset = (col - cols/2.0) * spacing_px
		var y_offset = row * spacing_px
		var base_pos = Vector2(x_offset, y_offset)

		# Apply rotation around origin, then translate to anchor
		var rotated_pos = base_pos.rotated(rotation)
		positions.append(anchor_pos + rotated_pos)

	return positions

# Formation ghost management
func _create_formation_ghosts(count: int) -> void:
	"""Create multiple ghost visuals for formation preview"""
	_clear_formation_ghosts()

	var unit_data = GameState.get_unit(unit_id)
	var remaining_models = _get_unplaced_model_indices()
	var models_to_place = min(count, remaining_models.size())

	for i in range(models_to_place):
		var model_index = remaining_models[i]
		var model_data: Dictionary
		if is_combined_deployment and model_index < combined_models.size():
			model_data = combined_models[model_index]["model_data"]
		else:
			model_data = unit_data["models"][model_index]
		var ghost = load("res://scripts/GhostVisual.gd").new()
		ghost.name = "FormationGhost_%d" % i
		ghost.owner_player = unit_data["owner"]
		ghost.set_model_data(model_data)
		ghost.modulate.a = 0.6  # Slightly transparent for formation ghosts
		ghost_layer.add_child(ghost)
		formation_preview_ghosts.append(ghost)

func _clear_formation_ghosts() -> void:
	"""Remove all formation ghost visuals"""
	for ghost in formation_preview_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	formation_preview_ghosts.clear()

func _update_formation_ghost_positions(mouse_pos: Vector2) -> void:
	"""Update positions of all formation ghosts"""
	if formation_preview_ghosts.is_empty():
		return

	var unit_data = GameState.get_unit(unit_id)
	var remaining_models = _get_unplaced_model_indices()
	if remaining_models.is_empty():
		return

	var first_model_data: Dictionary
	if is_combined_deployment and remaining_models[0] < combined_models.size():
		first_model_data = combined_models[remaining_models[0]]["model_data"]
	else:
		first_model_data = unit_data["models"][remaining_models[0]]
	var base_mm = first_model_data["base_mm"]

	var positions = []
	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(mouse_pos, formation_preview_ghosts.size(), base_mm, formation_rotation)
		"TIGHT":
			positions = calculate_tight_formation(mouse_pos, formation_preview_ghosts.size(), base_mm, formation_rotation)

	# Update ghost positions and validity
	var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())
	for i in range(formation_preview_ghosts.size()):
		var ghost = formation_preview_ghosts[i]
		if i < positions.size():
			ghost.position = positions[i]
			ghost.visible = true

			# Check validity for each ghost position
			var is_valid = _validate_formation_position(positions[i], first_model_data, zone)
			ghost.set_validity(is_valid)

func _validate_formation_position(pos: Vector2, model_data: Dictionary, zone: PackedVector2Array) -> bool:
	"""Validate a single position in a formation"""
	if is_infiltrators_mode:
		# In Infiltrators mode, use Infiltrators validation instead of zone check
		if not _validate_infiltrators_position(pos, model_data, 0.0):
			return false
		if _overlaps_with_existing_models_shape(pos, model_data, 0.0):
			return false
	else:
		var base_type = model_data.get("base_type", "circular")

		if base_type == "circular":
			var radius_px = Measurement.base_radius_px(model_data["base_mm"])
			if not _circle_wholly_in_polygon(pos, radius_px, zone):
				return false
			if _overlaps_with_existing_models(pos, radius_px):
				return false
		else:
			# For non-circular bases, use shape-aware validation
			if not _shape_wholly_in_polygon(pos, model_data, 0.0, zone):
				return false
			if _overlaps_with_existing_models_shape(pos, model_data, 0.0):
				return false

	# Check wall collision
	var test_model = model_data.duplicate()
	test_model["position"] = pos
	test_model["rotation"] = 0.0
	if Measurement.model_overlaps_any_wall(test_model):
		return false

	return true

# Model Repositioning Functions
func _get_deployed_model_at_position(world_pos: Vector2) -> Dictionary:
	"""Find deployed model from current unit at given position"""
	if unit_id == "" or temp_positions.is_empty():
		return {}

	var unit_data = GameState.get_unit(unit_id)
	for i in range(temp_positions.size()):
		if temp_positions[i] != null:  # Model is placed
			var model_pos = temp_positions[i]
			var model_data = unit_data["models"][i]
			var rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0

			# Use shape-aware hit detection
			var shape = Measurement.create_base_shape(model_data)
			if shape and shape.contains_point(world_pos, model_pos, rotation):
				return {
					"model_index": i,
					"position": model_pos,
					"model_data": model_data
				}

	return {}

func _start_model_repositioning(deployed_model: Dictionary) -> void:
	"""Begin repositioning a deployed model"""
	repositioning_model = true
	reposition_model_index = deployed_model.model_index
	reposition_start_pos = deployed_model.position

	print("Starting repositioning of model ", reposition_model_index)

	# Create ghost visual for repositioning
	var model_data = deployed_model.model_data
	reposition_ghost = load("res://scripts/GhostVisual.gd").new()
	reposition_ghost.name = "RepositionGhost"
	reposition_ghost.owner_player = GameState.get_active_player()
	reposition_ghost.set_model_data(model_data)
	ghost_layer.add_child(reposition_ghost)

	# Make the original token semi-transparent during repositioning
	for token in placed_tokens:
		if is_instance_valid(token) and token.name == "Token_%s_%d" % [unit_id, reposition_model_index]:
			token.modulate.a = 0.3  # Make original semi-transparent
			break

func _update_model_repositioning(mouse_pos: Vector2) -> void:
	"""Update ghost position during repositioning"""
	if not repositioning_model or not reposition_ghost:
		return

	var world_pos = _get_world_mouse_position()
	reposition_ghost.position = world_pos

	# Validate new position
	var unit_data = GameState.get_unit(unit_id)
	var model_data = unit_data["models"][reposition_model_index]
	var is_valid = _validate_reposition(world_pos, model_data, reposition_model_index)

	reposition_ghost.set_validity(is_valid)

func _validate_reposition(world_pos: Vector2, model_data: Dictionary, model_index: int) -> bool:
	"""Validate if repositioning is allowed at the given position"""
	var active_player = GameState.get_active_player()
	var rotation = temp_rotations[model_index] if model_index < temp_rotations.size() else 0.0

	if is_infiltrators_mode:
		# In Infiltrators mode, use Infiltrators validation instead of zone check
		if not _validate_infiltrators_position(world_pos, model_data, rotation):
			return false
	else:
		var zone = BoardState.get_deployment_zone_for_player(active_player)
		var base_type = model_data.get("base_type", "circular")

		# Check deployment zone
		var in_zone = false
		if base_type == "circular":
			var radius_px = Measurement.base_radius_px(model_data["base_mm"])
			in_zone = _circle_wholly_in_polygon(world_pos, radius_px, zone)
		else:
			in_zone = _shape_wholly_in_polygon(world_pos, model_data, rotation, zone)

		if not in_zone:
			return false

	# Check overlap (excluding the model being repositioned)
	return not _would_overlap_excluding_self(world_pos, model_data, model_index)

func _would_overlap_excluding_self(pos: Vector2, model_data: Dictionary, exclude_index: int) -> bool:
	"""Check for overlaps excluding the model being repositioned"""
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	# Check overlap with other models in current unit (excluding self)
	var unit_data = GameState.get_unit(unit_id)
	for i in range(temp_positions.size()):
		if i != exclude_index and temp_positions[i] != null:
			var other_model_data = unit_data["models"][i]
			var other_rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0
			var self_rotation = temp_rotations[exclude_index] if exclude_index < temp_rotations.size() else 0.0
			if _shapes_overlap(pos, model_data, self_rotation, temp_positions[i], other_model_data, other_rotation):
				return true

	# Check overlap with all deployed models from other units
	var all_units = GameState.state.get("units", {})
	for other_unit_id in all_units:
		if other_unit_id == unit_id:
			continue  # Skip current unit, already checked above

		var other_unit = all_units[other_unit_id]
		if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
			for model in other_unit["models"]:
				var model_position = model.get("position", null)
				if model_position:
					var other_pos = Vector2(model_position.x, model_position.y)
					var other_rotation = model.get("rotation", 0.0)
					var self_rotation = temp_rotations[exclude_index] if exclude_index < temp_rotations.size() else 0.0
					if _shapes_overlap(pos, model_data, self_rotation, other_pos, model, other_rotation):
						return true

	return false

func _end_model_repositioning(mouse_pos: Vector2) -> void:
	"""Complete model repositioning"""
	if not repositioning_model:
		return

	var world_pos = _get_world_mouse_position()
	var unit_data = GameState.get_unit(unit_id)
	var model_data = unit_data["models"][reposition_model_index]

	# Validate final position
	if _validate_reposition(world_pos, model_data, reposition_model_index):
		# Update position
		temp_positions[reposition_model_index] = world_pos

		# Update the token position
		for token in placed_tokens:
			if is_instance_valid(token) and token.name == "Token_%s_%d" % [unit_id, reposition_model_index]:
				token.position = world_pos
				token.modulate.a = 1.0  # Restore full opacity
				break

		print("Model ", reposition_model_index, " repositioned to ", world_pos)
		emit_signal("models_placed_changed")
		_check_coherency_warning()
	else:
		# Revert to original position
		for token in placed_tokens:
			if is_instance_valid(token) and token.name == "Token_%s_%d" % [unit_id, reposition_model_index]:
				token.modulate.a = 1.0  # Restore full opacity
				break
		_show_toast("Invalid position for repositioning")

	_cleanup_repositioning()

func _cancel_model_repositioning() -> void:
	"""Cancel model repositioning and restore original state"""
	if not repositioning_model:
		return

	# Restore original token opacity
	for token in placed_tokens:
		if is_instance_valid(token) and token.name == "Token_%s_%d" % [unit_id, reposition_model_index]:
			token.modulate.a = 1.0
			break

	_cleanup_repositioning()

func _validate_reinforcement_position(world_pos: Vector2, model_data: Dictionary, rotation: float) -> bool:
	"""Validate a reinforcement placement position (Deep Strike / Strategic Reserves)"""
	var px_per_inch = 40.0
	var board_width_px = GameState.state.board.size.width * px_per_inch
	var board_height_px = GameState.state.board.size.height * px_per_inch

	# Must be on the board
	if world_pos.x < 0 or world_pos.x > board_width_px or world_pos.y < 0 or world_pos.y > board_height_px:
		_show_toast("Must be on the battlefield")
		return false

	# Must be >9" from all enemy models (edge-to-edge)
	var active_player = GameState.get_active_player()
	var model_base_mm = model_data.get("base_mm", 32)
	var model_radius_inches = (model_base_mm / 2.0) / 25.4

	var enemy_positions = GameState.get_enemy_model_positions(active_player)
	for enemy in enemy_positions:
		var enemy_pos_px = Vector2(enemy.x, enemy.y)
		var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
		var dist_px = world_pos.distance_to(enemy_pos_px)
		var dist_inches = dist_px / px_per_inch
		var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
		if edge_dist < 9.0:
			_show_toast("Must be >9\" from enemy models (%.1f\")" % edge_dist)
			return false

	# Strategic Reserves: must be within 6" of a battlefield edge
	var unit = GameState.get_unit(unit_id)
	var reserve_type = unit.get("reserve_type", "strategic_reserves")
	if reserve_type == "strategic_reserves":
		var pos_inches_x = world_pos.x / px_per_inch
		var pos_inches_y = world_pos.y / px_per_inch
		var board_w = GameState.state.board.size.width
		var board_h = GameState.state.board.size.height
		var dist_to_edge = min(pos_inches_x, board_w - pos_inches_x, pos_inches_y, board_h - pos_inches_y)
		if dist_to_edge > 6.0:
			_show_toast("Strategic Reserves must be within 6\" of a board edge (%.1f\")" % dist_to_edge)
			return false

	# Omni-scramblers: cannot be set up within 12" of enemy units with Omni-scramblers
	var omni_positions = GameState.get_omni_scrambler_positions(active_player)
	for omni in omni_positions:
		var omni_pos_px = Vector2(omni.x, omni.y)
		var omni_radius_inches = (omni.base_mm / 2.0) / 25.4
		var dist_px = world_pos.distance_to(omni_pos_px)
		var dist_inches = dist_px / px_per_inch
		var edge_dist = dist_inches - model_radius_inches - omni_radius_inches
		if edge_dist < 12.0:
			_show_toast("Cannot deploy within 12\" of Omni-scramblers (%s) (%.1f\")" % [omni.get("unit_name", "unknown"), edge_dist])
			return false

	return true

func _validate_infiltrators_position(world_pos: Vector2, model_data: Dictionary, rotation: float) -> bool:
	"""Validate an Infiltrators deployment position: anywhere on the board, >9 inches from enemy deployment zone and >9 inches from enemy models"""
	var px_per_inch = 40.0
	var board_width_px = GameState.state.board.size.width * px_per_inch
	var board_height_px = GameState.state.board.size.height * px_per_inch

	# Must be on the board
	if world_pos.x < 0 or world_pos.x > board_width_px or world_pos.y < 0 or world_pos.y > board_height_px:
		_show_toast("Must be on the battlefield")
		return false

	var active_player = GameState.get_active_player()
	var model_base_mm = model_data.get("base_mm", 32)
	var model_radius_inches = (model_base_mm / 2.0) / 25.4

	# Must be >9" from enemy deployment zone
	var enemy_zone = GameState.get_enemy_deployment_zone(active_player)
	var enemy_zone_poly_inches = enemy_zone.get("poly", [])
	if enemy_zone_poly_inches.size() > 0:
		var enemy_zone_poly_pixels = PackedVector2Array()
		for coord in enemy_zone_poly_inches:
			if coord is Dictionary and coord.has("x") and coord.has("y"):
				enemy_zone_poly_pixels.append(Vector2(coord.x * px_per_inch, coord.y * px_per_inch))

		# Check if model center is inside enemy zone
		if Geometry2D.is_point_in_polygon(world_pos, enemy_zone_poly_pixels):
			_show_toast("Infiltrators must be >9\" from enemy deployment zone")
			return false

		# Find minimum distance from model center to any edge of the enemy zone
		var min_dist_px = INF
		for i in range(enemy_zone_poly_pixels.size()):
			var p1 = enemy_zone_poly_pixels[i]
			var p2 = enemy_zone_poly_pixels[(i + 1) % enemy_zone_poly_pixels.size()]
			var dist = _point_to_line_distance(world_pos, p1, p2)
			if dist < min_dist_px:
				min_dist_px = dist
		var edge_dist_inches = (min_dist_px / px_per_inch) - model_radius_inches
		if edge_dist_inches < 9.0:
			_show_toast("Infiltrators must be >9\" from enemy deployment zone (%.1f\")" % edge_dist_inches)
			return false

	# Must be >9" from all enemy models (edge-to-edge)
	var enemy_positions = GameState.get_enemy_model_positions(active_player)
	for enemy in enemy_positions:
		var enemy_pos_px = Vector2(enemy.x, enemy.y)
		var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
		var dist_px = world_pos.distance_to(enemy_pos_px)
		var dist_inches = dist_px / px_per_inch
		var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
		if edge_dist < 9.0:
			_show_toast("Infiltrators must be >9\" from enemy models (%.1f\")" % edge_dist)
			return false

	return true

func _cleanup_repositioning() -> void:
	"""Clean up repositioning state"""
	repositioning_model = false
	reposition_model_index = -1
	reposition_start_pos = Vector2.ZERO

	if reposition_ghost and is_instance_valid(reposition_ghost):
		reposition_ghost.queue_free()
		reposition_ghost = null

extends CanvasLayer

@onready var camera: Camera2D = $BoardRoot/Camera2D
@onready var board_view: Node2D = $BoardRoot/BoardView
@onready var deployment_zones: Node2D = $BoardRoot/DeploymentZones
@onready var p1_zone: Polygon2D = $BoardRoot/DeploymentZones/P1Zone
@onready var p2_zone: Polygon2D = $BoardRoot/DeploymentZones/P2Zone
@onready var token_layer: Node2D = $BoardRoot/TokenLayer
@onready var ghost_layer: Node2D = $BoardRoot/GhostLayer

@onready var phase_label: Label = $HUD_Bottom/HBoxContainer/PhaseLabel
@onready var active_player_badge: Label = $HUD_Bottom/HBoxContainer/ActivePlayerBadge
@onready var status_label: Label = $HUD_Bottom/HBoxContainer/StatusLabel
@onready var end_deployment_button: Button = $HUD_Bottom/HBoxContainer/EndDeploymentButton

@onready var unit_list: ItemList = $HUD_Right/VBoxContainer/UnitListPanel
@onready var unit_card: VBoxContainer = $HUD_Right/VBoxContainer/UnitCard
@onready var unit_name_label: Label = $HUD_Right/VBoxContainer/UnitCard/UnitNameLabel
@onready var keywords_label: Label = $HUD_Right/VBoxContainer/UnitCard/KeywordsLabel
@onready var models_label: Label = $HUD_Right/VBoxContainer/UnitCard/ModelsLabel
@onready var undo_button: Button = $HUD_Right/VBoxContainer/UnitCard/ButtonContainer/UndoButton
@onready var reset_button: Button = $HUD_Right/VBoxContainer/UnitCard/ButtonContainer/ResetButton
@onready var confirm_button: Button = $HUD_Right/VBoxContainer/UnitCard/ButtonContainer/ConfirmButton

var deployment_controller: Node
var movement_controller: Node
var shooting_controller: Node
var charge_controller: Node
var current_phase: GameStateData.Phase
var view_offset: Vector2 = Vector2.ZERO
var view_zoom: float = 1.0

func _ready() -> void:
	# Initialize view to show whole board
	view_zoom = 0.3
	view_offset = Vector2(0, 0)  # Start at top-left
	update_view_transform()
	
	# Camera controls: WASD/arrows to pan, +/- to zoom, F to focus on Player 2 zone
	
	board_view.queue_redraw()
	setup_deployment_zones()
	
	# Fix HUD layout to prevent overlap
	_fix_hud_layout()
	
	# Setup phase-specific controllers based on current phase
	current_phase = GameState.get_current_phase()
	await setup_phase_controllers()
	
	connect_signals()
	refresh_unit_list()
	update_ui()
	
	# Enable autosave (saves every 5 minutes)
	SaveLoadManager.enable_autosave()
	print("Quick Save/Load enabled: [ key to save, ] key (or F9) to load")

func _fix_hud_layout() -> void:
	# Prevent HUD_Right from overlapping with HUD_Bottom
	# HUD_Bottom is 100px tall, so HUD_Right should stop 100px from bottom
	var hud_right = get_node("HUD_Right")
	var hud_bottom = get_node("HUD_Bottom")
	
	if hud_right and hud_bottom:
		# Get the height of the bottom panel
		var bottom_height = 100.0  # This matches the offset_top = -100 in the scene
		
		# Adjust HUD_Right to not overlap with bottom panel
		hud_right.anchor_bottom = 1.0
		hud_right.offset_bottom = -bottom_height
		
		print("Fixed HUD layout: HUD_Right bottom offset set to -", bottom_height)
	
	# Adjust unit list to take less space, giving more room to phase panels
	var unit_list = get_node_or_null("HUD_Right/VBoxContainer/UnitListPanel")
	if unit_list:
		# Change from size_flags_vertical = 3 (expand/fill) to 0 (fixed size)
		unit_list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unit_list.custom_minimum_size = Vector2(0, 150)  # Fixed height of 150px
		print("Adjusted unit list: fixed height to 150px")

func setup_deployment_zones() -> void:
	var zone1 = BoardState.get_deployment_zone_for_player(1)
	var zone2 = BoardState.get_deployment_zone_for_player(2)
	
	p1_zone.polygon = zone1
	p2_zone.polygon = zone2
	
	update_deployment_zone_visibility()

func setup_phase_controllers() -> void:
	# Clean up existing controllers
	if deployment_controller:
		deployment_controller.queue_free()
		deployment_controller = null
	if movement_controller:
		movement_controller.queue_free()
		movement_controller = null
	if shooting_controller:
		shooting_controller.queue_free()
		shooting_controller = null
	if charge_controller:
		charge_controller.queue_free()
		charge_controller = null
	
	# Wait a frame for cleanup to complete before creating new controllers
	await get_tree().process_frame
	
	# Setup controller based on current phase
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			setup_deployment_controller()
		GameStateData.Phase.MOVEMENT:
			setup_movement_controller()
		GameStateData.Phase.SHOOTING:
			setup_shooting_controller()
		GameStateData.Phase.CHARGE:
			setup_charge_controller()
		_:
			print("No controller for phase: ", current_phase)

func setup_deployment_controller() -> void:
	deployment_controller = preload("res://scripts/DeploymentController.gd").new()
	deployment_controller.name = "DeploymentController"
	add_child(deployment_controller)
	deployment_controller.set_layers(token_layer, ghost_layer)

func setup_movement_controller() -> void:
	print("Setting up MovementController...")
	movement_controller = preload("res://scripts/MovementController.gd").new()
	movement_controller.name = "MovementController"
	add_child(movement_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a MovementPhase by checking for movement-specific signals or properties
		# We check for the phase_type property which should be set in MovementPhase
		var is_movement_phase = false
		if phase_instance.has_signal("unit_move_begun"):
			is_movement_phase = true
		elif phase_instance.get("phase_type") == GameStateData.Phase.MOVEMENT:
			is_movement_phase = true
			
		if is_movement_phase:
			movement_controller.set_phase(phase_instance)
			
			# Connect phase signals to movement controller
			if not phase_instance.unit_move_begun.is_connected(movement_controller._on_unit_move_begun):
				phase_instance.unit_move_begun.connect(movement_controller._on_unit_move_begun)
				print("Connected unit_move_begun signal")
			if phase_instance.has_signal("model_drop_committed"):
				if not phase_instance.model_drop_committed.is_connected(movement_controller._on_model_drop_committed):
					phase_instance.model_drop_committed.connect(movement_controller._on_model_drop_committed)
					print("Connected model_drop_committed signal")
			if phase_instance.has_signal("unit_move_confirmed"):
				if not phase_instance.unit_move_confirmed.is_connected(movement_controller._on_unit_move_confirmed):
					phase_instance.unit_move_confirmed.connect(movement_controller._on_unit_move_confirmed)
					print("Connected unit_move_confirmed signal")
			if phase_instance.has_signal("unit_move_reset"):
				if not phase_instance.unit_move_reset.is_connected(movement_controller._on_unit_move_reset):
					phase_instance.unit_move_reset.connect(movement_controller._on_unit_move_reset)
					print("Connected unit_move_reset signal")
		else:
			print("WARNING: Phase instance is not a MovementPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect movement controller signals
	if not movement_controller.move_action_requested.is_connected(_on_movement_action_requested):
		movement_controller.move_action_requested.connect(_on_movement_action_requested)
		print("Connected move_action_requested signal")
	if not movement_controller.ui_update_requested.is_connected(_on_movement_ui_update_requested):
		movement_controller.ui_update_requested.connect(_on_movement_ui_update_requested)
		print("Connected ui_update_requested signal")

func setup_shooting_controller() -> void:
	print("Setting up ShootingController...")
	shooting_controller = preload("res://scripts/ShootingController.gd").new()
	shooting_controller.name = "ShootingController"
	add_child(shooting_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a ShootingPhase
		var is_shooting_phase = false
		if phase_instance.has_signal("unit_selected_for_shooting"):
			is_shooting_phase = true
		elif phase_instance.get("phase_type") == GameStateData.Phase.SHOOTING:
			is_shooting_phase = true
		
		if is_shooting_phase:
			shooting_controller.set_phase(phase_instance)
			
			# Connect phase signals to shooting controller
			if not phase_instance.unit_selected_for_shooting.is_connected(shooting_controller._on_unit_selected_for_shooting):
				phase_instance.unit_selected_for_shooting.connect(shooting_controller._on_unit_selected_for_shooting)
				print("Connected unit_selected_for_shooting signal")
			if phase_instance.has_signal("targets_available"):
				if not phase_instance.targets_available.is_connected(shooting_controller._on_targets_available):
					phase_instance.targets_available.connect(shooting_controller._on_targets_available)
					print("Connected targets_available signal")
			if phase_instance.has_signal("shooting_resolved"):
				if not phase_instance.shooting_resolved.is_connected(shooting_controller._on_shooting_resolved):
					phase_instance.shooting_resolved.connect(shooting_controller._on_shooting_resolved)
					print("Connected shooting_resolved signal")
			if phase_instance.has_signal("dice_rolled"):
				if not phase_instance.dice_rolled.is_connected(shooting_controller._on_dice_rolled):
					phase_instance.dice_rolled.connect(shooting_controller._on_dice_rolled)
					print("Connected dice_rolled signal")
		else:
			print("WARNING: Phase instance is not a ShootingPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect shooting controller signals
	if not shooting_controller.shoot_action_requested.is_connected(_on_shooting_action_requested):
		shooting_controller.shoot_action_requested.connect(_on_shooting_action_requested)
		print("Connected shoot_action_requested signal")
	if not shooting_controller.ui_update_requested.is_connected(_on_shooting_ui_update_requested):
		shooting_controller.ui_update_requested.connect(_on_shooting_ui_update_requested)
		print("Connected ui_update_requested signal")

	# NEW: Ensure UI is updated after controller setup
	emit_signal("ui_update_requested")

func setup_charge_controller() -> void:
	print("Setting up ChargeController...")
	charge_controller = preload("res://scripts/ChargeController.gd").new()
	charge_controller.name = "ChargeController"
	add_child(charge_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a ChargePhase
		var is_charge_phase = false
		if phase_instance.has_signal("unit_selected_for_charge"):
			is_charge_phase = true
		elif phase_instance.get("phase_type") == GameStateData.Phase.CHARGE:
			is_charge_phase = true
		
		if is_charge_phase:
			charge_controller.set_phase(phase_instance)
			print("Connected ChargeController to ChargePhase")
		else:
			print("WARNING: Phase instance is not a ChargePhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect charge controller signals
	if not charge_controller.charge_action_requested.is_connected(_on_charge_action_requested):
		charge_controller.charge_action_requested.connect(_on_charge_action_requested)
		print("Connected charge_action_requested signal")
	if not charge_controller.ui_update_requested.is_connected(_on_charge_ui_update_requested):
		charge_controller.ui_update_requested.connect(_on_charge_ui_update_requested)
		print("Connected ui_update_requested signal")

func connect_signals() -> void:
	unit_list.item_selected.connect(_on_unit_selected)
	undo_button.pressed.connect(_on_undo_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	end_deployment_button.pressed.connect(_on_end_deployment_pressed)
	
	# Phase management signals
	PhaseManager.phase_changed.connect(_on_phase_changed)
	PhaseManager.phase_completed.connect(_on_phase_completed)
	
	TurnManager.deployment_side_changed.connect(_on_deployment_side_changed)
	TurnManager.deployment_phase_complete.connect(_on_deployment_complete)
	
	# Controller signals (if they exist)
	if deployment_controller:
		deployment_controller.unit_confirmed.connect(_on_unit_confirmed)
		deployment_controller.models_placed_changed.connect(_on_models_placed_changed)
	
	# Connect save/load signals
	SaveLoadManager.save_completed.connect(_on_save_completed)
	SaveLoadManager.load_completed.connect(_on_load_completed)
	SaveLoadManager.save_failed.connect(_on_save_failed)
	SaveLoadManager.load_failed.connect(_on_load_failed)
	

func _input(event: InputEvent) -> void:
	# Debug: Check for [ key directly for save
	if event is InputEventKey and event.pressed and event.keycode == KEY_BRACKETLEFT:
		print("[ KEY DETECTED DIRECTLY!")
		_perform_quick_save()
		get_viewport().set_input_as_handled()
		return
	
	# Debug: Check for ] key directly for load
	if event is InputEventKey and event.pressed and event.keycode == KEY_BRACKETRIGHT:
		print("] KEY DETECTED DIRECTLY!")
		_perform_quick_load()
		get_viewport().set_input_as_handled()
		return
	
	# Handle quick save/load
	if event.is_action_pressed("quick_save"):
		print("quick_save action detected!")
		_perform_quick_save()
		get_viewport().set_input_as_handled()
		return
		
	if event.is_action_pressed("quick_load"):
		_perform_quick_load()
		get_viewport().set_input_as_handled()
		return
	
	# Handle mouse clicks for placement - but only consume if we actually place something
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if deployment_controller and deployment_controller.is_placing():
			# Check if click is on the board area (not on UI)
			var ui_rect = get_viewport().get_visible_rect()
			var right_hud_rect = Rect2(ui_rect.size.x - 400, 0, 400, ui_rect.size.y)  # Right HUD area
			var bottom_hud_rect = Rect2(0, ui_rect.size.y - 100, ui_rect.size.x, 100)  # Bottom HUD area
			
			if not right_hud_rect.has_point(event.position) and not bottom_hud_rect.has_point(event.position):
				var world_pos = screen_to_world_position(event.position)
				deployment_controller.try_place_at(world_pos)
				get_viewport().set_input_as_handled()

func screen_to_world_position(screen_pos: Vector2) -> Vector2:
	# Convert screen position to world position using our transform
	var board_transform = $BoardRoot.transform
	return board_transform.affine_inverse() * screen_pos

func _process(delta: float) -> void:
	# View controls using BoardRoot transform
	var pan_speed = 800.0 * delta / view_zoom
	var view_changed = false
	
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		view_offset.y -= pan_speed
		view_changed = true
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		view_offset.y += pan_speed
		view_changed = true
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		view_offset.x -= pan_speed
		view_changed = true
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		view_offset.x += pan_speed
		view_changed = true
	
	# Zoom controls
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_PLUS):
		view_zoom *= 1.03
		view_zoom = clamp(view_zoom, 0.1, 3.0)
		view_changed = true
	if Input.is_key_pressed(KEY_MINUS):
		view_zoom *= 0.97
		view_zoom = clamp(view_zoom, 0.1, 3.0)
		view_changed = true
	
	# Focus commands
	if Input.is_key_pressed(KEY_F):
		focus_on_player2_zone()
		view_changed = true
	
	
	if view_changed:
		update_view_transform()

func reset_camera() -> void:
	camera.position = Vector2(
		SettingsService.get_board_width_px() / 2,
		SettingsService.get_board_height_px() / 2
	)
	camera.zoom = Vector2(0.3, 0.3)
	print("Camera reset to position: ", camera.position, " zoom: ", camera.zoom)

func update_view_transform() -> void:
	# Apply transform to BoardRoot to simulate camera movement
	var transform = Transform2D()
	transform = transform.scaled(Vector2(view_zoom, view_zoom))
	transform.origin = -view_offset * view_zoom
	$BoardRoot.transform = transform

func focus_on_player2_zone() -> void:
	var zone2 = BoardState.get_deployment_zone_for_player(2)
	if zone2.size() > 0:
		# Calculate center of the zone
		var center = Vector2.ZERO
		for point in zone2:
			center += point
		center /= zone2.size()
		
		view_offset = center - get_viewport().get_visible_rect().size / 2
		view_zoom = 0.8
		print("Focused view on Player 2 zone at: ", center)

func refresh_unit_list() -> void:
	unit_list.clear()
	var active_player = GameState.get_active_player()
	
	# Different list based on current phase
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			# Show undeployed units during deployment
			var units = GameState.get_undeployed_units_for_player(active_player)
			print("Refreshing unit list for deployment - found ", units.size(), " undeployed units")
			
			for unit_id in units:
				var unit_data = GameState.get_unit(unit_id)
				var unit_name = unit_data["meta"]["name"]
				var model_count = unit_data["models"].size()
				var display_text = "%s (%d models)" % [unit_name, model_count]
				unit_list.add_item(display_text)
				unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
		
		GameStateData.Phase.MOVEMENT:
			# Show deployed units during movement
			var all_units = GameState.get_units_for_player(active_player)
			var deployed_count = 0
			
			for unit_id in all_units:
				var unit = all_units[unit_id]
				# Render units that are deployed or have moved/acted
				var unit_status = unit.get("status", 0)
				if unit_status >= GameStateData.UnitStatus.DEPLOYED:
					var unit_name = unit.get("meta", {}).get("name", unit_id)
					var model_count = unit.get("models", []).size()
					var moved = unit.get("flags", {}).get("moved", false)
					var status = " [MOVED]" if moved else ""
					var display_text = "%s (%d models)%s" % [unit_name, model_count, status]
					unit_list.add_item(display_text)
					unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
					deployed_count += 1
			
			print("Refreshing unit list for movement - found ", deployed_count, " deployed units")
		
		_:
			# Default behavior for other phases
			var all_units = GameState.get_units_for_player(active_player)
			for unit_id in all_units:
				var unit = all_units[unit_id]
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				var model_count = unit.get("models", []).size()
				var display_text = "%s (%d models)" % [unit_name, model_count]
				unit_list.add_item(display_text)
				unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)

func update_ui() -> void:
	var active_player = GameState.get_active_player()
	var player_text = "Player %d (%s)" % [
		active_player,
		"Defender" if active_player == 1 else "Attacker"
	]
	active_player_badge.text = player_text
	
	# Phase-specific UI updates
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			if GameState.all_units_deployed():
				end_deployment_button.disabled = false
				status_label.text = "All units deployed! Click 'End Deployment' to continue."
			else:
				end_deployment_button.disabled = true
				if deployment_controller and deployment_controller.is_placing():
					var unit_id = deployment_controller.get_current_unit()
					var unit_data = GameState.get_unit(unit_id)
					var unit_name = unit_data["meta"]["name"]
					var placed = deployment_controller.get_placed_count()
					var total = unit_data["models"].size()
					status_label.text = "Placing: %s — %d/%d models" % [unit_name, placed, total]
				else:
					status_label.text = "Select a unit to deploy"
		
		GameStateData.Phase.MOVEMENT:
			if movement_controller and movement_controller.active_unit_id != "":
				if movement_controller.active_mode != "":
					status_label.text = "Drag models to move them"
				else:
					status_label.text = "Choose movement type (Normal/Advance/etc.)"
			else:
				status_label.text = "Select a unit to move"
			end_deployment_button.disabled = false
		
		_:
			status_label.text = "Phase: " + GameStateData.Phase.keys()[current_phase]
			end_deployment_button.disabled = false

func _on_unit_selected(index: int) -> void:
	if deployment_controller and deployment_controller.is_placing():
		return
	
	var unit_id = unit_list.get_item_metadata(index)
	
	# Handle unit selection based on current phase
	if current_phase == GameStateData.Phase.DEPLOYMENT and deployment_controller:
		deployment_controller.begin_deploy(unit_id)
		show_unit_card(unit_id)
		unit_list.visible = false
	elif current_phase == GameStateData.Phase.MOVEMENT and movement_controller:
		# Pass unit selection to MovementController
		movement_controller.active_unit_id = unit_id
		print("Selected unit for movement: ", unit_id)
		# Show movement options in the unit card
		show_unit_card(unit_id)
		update_movement_card_buttons()
		
		# AUTO-START NORMAL MOVE FOR EASIER TESTING
		# In production, user would click a movement type button
		print("Auto-starting Normal Move for easier testing...")
		var action = {
			"type": "BEGIN_NORMAL_MOVE",
			"actor_unit_id": unit_id,
			"payload": {}
		}
		_on_movement_action_requested(action)
		status_label.text = "Drag models to move them (Normal Move mode)"
	
	update_ui()

func show_unit_card(unit_id: String) -> void:
	var unit_data = GameState.get_unit(unit_id)
	unit_name_label.text = unit_data["meta"]["name"]
	keywords_label.text = "Keywords: " + ", ".join(unit_data["meta"]["keywords"])
	
	unit_card.visible = true
	update_unit_card_buttons()

func update_unit_card_buttons() -> void:
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			if deployment_controller:
				var placed = deployment_controller.get_placed_count()
				var current_unit_id = deployment_controller.get_current_unit()
				var unit_data = GameState.get_unit(current_unit_id)
				var total = unit_data["models"].size()
				
				models_label.text = "Models: %d/%d" % [placed, total]
				
				# Show buttons based on deployment progress
				undo_button.visible = placed > 0
				reset_button.visible = false  # No reset in deployment
				confirm_button.visible = placed == total
		
		GameStateData.Phase.MOVEMENT:
			update_movement_card_buttons()

func update_movement_card_buttons() -> void:
	if not movement_controller:
		return
	
	# Show movement buttons if there's an active move
	if movement_controller.active_unit_id != "":
		var unit_data = GameState.get_unit(movement_controller.active_unit_id)
		unit_name_label.text = unit_data.get("meta", {}).get("name", movement_controller.active_unit_id)
		
		# Show movement mode and cap
		var mode = movement_controller.active_mode
		var cap = movement_controller.move_cap_inches
		
		if mode != "":
			keywords_label.text = "Mode: %s" % mode
			models_label.text = "Move Cap: %.1f\" - Drag models to move" % cap
		else:
			keywords_label.text = "Select movement type:"
			models_label.text = "Normal Move / Advance / Fall Back"
		
		# Show/hide buttons based on move state
		# Try to get active_moves from the phase if it's a MovementPhase
		var has_model_moves = false
		if movement_controller.current_phase:
			# MovementPhase should have active_moves as a property
			if movement_controller.current_phase.get("active_moves") != null:
				var active_moves = movement_controller.current_phase.active_moves
				var move_data = active_moves.get(movement_controller.active_unit_id, {})
				has_model_moves = not move_data.get("model_moves", []).is_empty()
		
		undo_button.visible = has_model_moves
		reset_button.visible = has_model_moves
		confirm_button.visible = has_model_moves  # Can confirm if any moves made
		
		unit_card.visible = true
	else:
		# Hide unit card when no active move
		unit_card.visible = false
	
	# Update main status label
	update_ui()

func _on_undo_pressed() -> void:
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			if deployment_controller:
				deployment_controller.undo()
				unit_card.visible = false
				unit_list.visible = true
				update_ui()
		GameStateData.Phase.MOVEMENT:
			if movement_controller and movement_controller.active_unit_id != "":
				print("Undo button pressed for unit: ", movement_controller.active_unit_id)
				var action = {
					"type": "UNDO_LAST_MODEL_MOVE",
					"actor_unit_id": movement_controller.active_unit_id,
					"payload": {}
				}
				_on_movement_action_requested(action)

func _on_reset_pressed() -> void:
	match current_phase:
		GameStateData.Phase.MOVEMENT:
			if movement_controller and movement_controller.active_unit_id != "":
				print("Reset button pressed for unit: ", movement_controller.active_unit_id)
				var action = {
					"type": "RESET_UNIT_MOVE",
					"actor_unit_id": movement_controller.active_unit_id,
					"payload": {}
				}
				_on_movement_action_requested(action)

func _on_confirm_pressed() -> void:
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			if deployment_controller:
				deployment_controller.confirm()
		GameStateData.Phase.MOVEMENT:
			if movement_controller and movement_controller.active_unit_id != "":
				print("Confirm button pressed for unit: ", movement_controller.active_unit_id)
				var action = {
					"type": "CONFIRM_UNIT_MOVE",
					"actor_unit_id": movement_controller.active_unit_id,
					"payload": {}
				}
				_on_movement_action_requested(action)

func _on_unit_confirmed() -> void:
	unit_card.visible = false
	unit_list.visible = true
	refresh_unit_list()
	update_ui()

func _on_models_placed_changed() -> void:
	update_unit_card_buttons()
	update_ui()

func _on_deployment_side_changed(player: int) -> void:
	refresh_unit_list()
	update_ui()
	update_deployment_zone_visibility()

func _on_deployment_complete() -> void:
	status_label.text = "Deployment complete!"
	end_deployment_button.disabled = false

func _on_end_deployment_pressed() -> void:
	# Handle end of current phase
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			print("Ending deployment phase...")
			# Signal phase completion to PhaseManager
			var phase_instance = PhaseManager.get_current_phase_instance()
			if phase_instance:
				phase_instance.emit_signal("phase_completed")
				
		GameStateData.Phase.MOVEMENT:
			print("Ending movement phase...")
			var phase_instance = PhaseManager.get_current_phase_instance()
			if phase_instance:
				phase_instance.emit_signal("phase_completed")
				
		_:
			print("Ending phase: ", current_phase)
			var phase_instance = PhaseManager.get_current_phase_instance()
			if phase_instance:
				phase_instance.emit_signal("phase_completed")

func _perform_quick_save() -> void:
	print("========================================")
	print("QUICK SAVE TRIGGERED WITH [ KEY")
	print("========================================")
	print("Current game state meta: ", GameState.state.get("meta", {}))
	
	# Show immediate UI feedback
	_show_save_notification("Save debug started...", Color.YELLOW)
	
	# Debug: Run save system test
	_debug_save_system()
	
	var success = SaveLoadManager.quick_save()
	print("========================================")
	print("QUICK SAVE RESULT: ", success)
	print("========================================")
	if success:
		_show_save_notification("Game saved!", Color.GREEN)
	else:
		_show_save_notification("Save failed!", Color.RED)

func _debug_save_system():
	print("\n=== Quick Save Debug ===")
	
	# Check if save directory exists
	var dir = DirAccess.open("res://")
	if dir and dir.dir_exists("saves"):
		print("✅ saves directory exists")
	else:
		print("❌ saves directory missing")
	
	# Test GameState
	var snapshot = GameState.create_snapshot()
	print("GameState snapshot keys: ", snapshot.keys())
	print("GameState snapshot size: ", snapshot.size())
	
	# Test StateSerializer
	if StateSerializer:
		var serialized = StateSerializer.serialize_game_state(snapshot)
		print("Serialized data length: ", serialized.length())
		if serialized.length() > 0:
			print("✅ Serialization successful")
		else:
			print("❌ Serialization failed")
	else:
		print("❌ StateSerializer not available")
	
	print("=== Debug Complete ===\n")

func _perform_quick_load() -> void:
	print("========================================")
	print("QUICK LOAD TRIGGERED WITH ] KEY")
	print("========================================")
	print("Pre-load game state meta: ", GameState.state.get("meta", {}))
	
	# Show immediate UI feedback
	_show_save_notification("Loading...", Color.YELLOW)
	
	# Debug: Check if save file exists
	_debug_load_system()
	
	var success = SaveLoadManager.quick_load()
	print("========================================")
	print("QUICK LOAD RESULT: ", success)
	print("Post-load game state meta: ", GameState.state.get("meta", {}))
	print("========================================")
	
	if success:
		_show_save_notification("Game loaded!", Color.BLUE)
		
		# Update current phase
		current_phase = GameState.get_current_phase()
		print("Loaded phase: ", GameStateData.Phase.keys()[current_phase])
		
		# Sync BoardState with loaded GameState (for visual components)
		_sync_board_state_with_game_state()
		
		# Recreate phase controllers for the loaded phase
		await setup_phase_controllers()
		
		# NEW: Give controllers time to initialize before UI refresh
		await get_tree().process_frame
		
		# Refresh all UI elements
		refresh_unit_list()
		update_ui()
		update_ui_for_phase()
		update_deployment_zone_visibility()
		
		# Recreate visual tokens for deployed units
		_recreate_unit_visuals()
		
		# Notify PhaseManager of the loaded state
		if PhaseManager.has_method("transition_to_phase"):
			PhaseManager.transition_to_phase(current_phase)
	else:
		_show_save_notification("Load failed - No save found!", Color.RED)

func _sync_board_state_with_game_state() -> void:
	# Sync the legacy BoardState with the loaded GameState
	print("Syncing BoardState with loaded GameState...")
	
	var units = GameState.state.get("units", {})
	print("Loaded units count: ", units.size())
	
	# Update BoardState units (for legacy visual components)
	for unit_id in units:
		var unit = units[unit_id]
		if BoardState.units.has(unit_id):
			# Update existing unit
			BoardState.units[unit_id]["status"] = unit.get("status", BoardState.UnitStatus.UNDEPLOYED)
			BoardState.units[unit_id]["models"] = unit.get("models", [])
			print("Updated BoardState unit: ", unit_id, " status: ", unit.get("status", 0))
		else:
			# Add new unit to BoardState
			BoardState.units[unit_id] = unit
			print("Added new unit to BoardState: ", unit_id)

func _recreate_unit_visuals() -> void:
	# Clear existing tokens
	print("Clearing existing token visuals...")
	for child in token_layer.get_children():
		child.queue_free()
	
	# Wait a frame for queue_free to process
	await get_tree().process_frame
	
	# Recreate tokens for deployed units
	var units = GameState.state.get("units", {})
	var tokens_created = 0
	
	print("Recreating token visuals from ", units.size(), " units in GameState...")
	
	for unit_id in units:
		var unit = units[unit_id]
		print("  Processing unit ", unit_id, " - status: ", unit.get("status", 0))
		
		# Render units that are deployed or have moved/acted
		var status = unit.get("status", 0)
		if status >= GameStateData.UnitStatus.DEPLOYED:
			var models = unit.get("models", [])
			print("    Unit has ", models.size(), " models")
			
			for i in range(models.size()):
				var model = models[i]
				var pos = model.get("position")
				var model_id = model.get("id", "m%d" % (i+1))
				
				print("      Model ", model_id, " position: ", pos)
				
				if pos != null and model.get("alive", true):
					# Create visual token
					var token = _create_token_visual(unit_id, model)
					if token:
						token_layer.add_child(token)
						
						# Set position based on format
						var final_pos: Vector2
						if pos is Dictionary:
							final_pos = Vector2(pos.x, pos.y)
						else:
							final_pos = pos
							
						token.position = final_pos
						tokens_created += 1
						
						print("        Created token at ", final_pos)
				else:
					print("        Skipped model (no position or dead)")
	
	print("Recreated ", tokens_created, " unit tokens")

func _create_token_visual(unit_id: String, model: Dictionary) -> Node2D:
	# Use the existing TokenVisual class
	var token = preload("res://scripts/TokenVisual.gd").new()
	
	# Set properties
	var unit = GameState.get_unit(unit_id)
	token.owner_player = unit.get("owner", 1)
	token.radius = Measurement.base_radius_px(model.get("base_mm", 32))
	token.is_preview = false
	
	# Extract model number from ID (e.g., "m1" -> 1)
	var model_id = model.get("id", "m1")
	if model_id.begins_with("m"):
		token.model_number = model_id.substr(1).to_int()
	else:
		token.model_number = 1
	
	# Set metadata for charge movement and other controllers
	token.set_meta("unit_id", unit_id)
	token.set_meta("model_id", model_id)
	
	return token

func _debug_load_system():
	print("\n=== Quick Load Debug ===")
	
	# Check if save file exists
	var file_path = "res://saves/quicksave.w40ksave"
	if FileAccess.file_exists(file_path):
		print("✅ Quicksave file exists at: ", file_path)
		
		# Try to read the file
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			print("File size: ", content.length(), " bytes")
			
			# Try to parse it
			var json = JSON.new()
			var parse_result = json.parse(content)
			if parse_result == OK:
				var data = json.data
				print("✅ JSON parse successful")
				print("Save contains keys: ", data.keys())
				if data.has("state"):
					print("State meta: ", data["state"].get("meta", {}))
			else:
				print("❌ JSON parse failed: ", parse_result)
		else:
			print("❌ Could not open file for reading")
	else:
		print("❌ Quicksave file does not exist")
	
	# Check SaveLoadManager state
	if SaveLoadManager:
		print("✅ SaveLoadManager exists")
	else:
		print("❌ SaveLoadManager not available")
	
	print("=== Debug Complete ===\n")

func _show_save_notification(message: String, color: Color) -> void:
	# Simple notification using the status label temporarily
	var original_text = status_label.text
	var original_color = status_label.modulate
	
	status_label.text = message
	status_label.modulate = color
	
	# Create a timer to restore original text after 2 seconds
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.timeout.connect(func():
		status_label.text = original_text
		status_label.modulate = original_color
		timer.queue_free()
	)
	add_child(timer)
	timer.start()

func _on_save_completed(file_path: String, metadata: Dictionary) -> void:
	print("Save completed: %s" % file_path)

func _on_load_completed(file_path: String, metadata: Dictionary) -> void:
	print("Load completed: %s" % file_path)
	# Force UI refresh after loading
	call_deferred("_refresh_after_load")

func _on_save_failed(error: String) -> void:
	print("Save failed: %s" % error)

func _on_load_failed(error: String) -> void:
	print("Load failed: %s" % error)

func _refresh_after_load() -> void:
	# Completely refresh the UI to match loaded state
	refresh_unit_list()
	update_ui()
	update_deployment_zone_visibility()
	
	# Clear any active deployment
	if deployment_controller and deployment_controller.is_placing():
		deployment_controller.undo()

func update_deployment_zone_visibility() -> void:
	# Show the active player's zone more prominently
	var active_player = GameState.get_active_player()
	if active_player == 1:
		p1_zone.modulate = Color(0, 0, 1, 0.6)  # Brighter blue for active
		p2_zone.modulate = Color(1, 0, 0, 0.3)  # Visible red for inactive
		p1_zone.visible = true
		p2_zone.visible = true
		# Set active borders
		if p1_zone.has_method("set_active"):
			p1_zone.set_active(true)
			p1_zone.border_color = Color(0, 0.3, 1, 1)
		if p2_zone.has_method("set_active"):
			p2_zone.set_active(false)
	else:
		p1_zone.modulate = Color(0, 0, 1, 0.3)  # Visible blue for inactive
		p2_zone.modulate = Color(1, 0, 0, 0.6)  # Brighter red for active
		p1_zone.visible = true
		p2_zone.visible = true
		# Set active borders
		if p1_zone.has_method("set_active"):
			p1_zone.set_active(false)
		if p2_zone.has_method("set_active"):
			p2_zone.set_active(true)
			p2_zone.border_color = Color(1, 0.3, 0, 1)

# Phase management handlers
func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
	current_phase = new_phase
	print("Phase changed to: ", GameStateData.Phase.keys()[new_phase])
	print("Active player: ", GameState.get_active_player())
	
	await setup_phase_controllers()
	update_ui_for_phase()
	
	# Debug: Check what units are available
	if current_phase == GameStateData.Phase.MOVEMENT:
		# Need to wait a frame for the phase to set the active player
		await get_tree().process_frame
		var active_player = GameState.get_active_player()
		var units = GameState.get_units_for_player(active_player)
		print("Units available for player ", active_player, ":")
		for unit_id in units:
			var unit = units[unit_id]
			print("  - ", unit_id, " (status: ", unit.get("status", 0), ")")
		
		# Re-refresh the UI after player change
		refresh_unit_list()
		update_ui()

func _on_phase_completed(phase: GameStateData.Phase) -> void:
	print("Phase completed: ", GameStateData.Phase.keys()[phase])

func update_ui_for_phase() -> void:
	# Update UI based on current phase
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			phase_label.text = "Deployment Phase"
			end_deployment_button.visible = true
			end_deployment_button.text = "End Deployment"
			# Hide deployment zones during other phases
			p1_zone.visible = true
			p2_zone.visible = true
			# Hide movement action buttons during deployment
			_show_movement_action_buttons(false)
			
		GameStateData.Phase.MOVEMENT:
			phase_label.text = "Movement Phase"
			end_deployment_button.visible = true
			end_deployment_button.text = "End Movement"
			# Hide deployment zones during movement
			p1_zone.visible = false
			p2_zone.visible = false
			# Show movement action buttons
			_show_movement_action_buttons(true)
			
		GameStateData.Phase.SHOOTING:
			phase_label.text = "Shooting Phase"
			end_deployment_button.visible = true
			end_deployment_button.text = "End Shooting"
			
		GameStateData.Phase.CHARGE:
			phase_label.text = "Charge Phase"
			end_deployment_button.visible = true
			end_deployment_button.text = "End Charge"
			
		GameStateData.Phase.FIGHT:
			phase_label.text = "Fight Phase"
			end_deployment_button.visible = true
			end_deployment_button.text = "End Fight"
			
		GameStateData.Phase.MORALE:
			phase_label.text = "Morale Phase"
			end_deployment_button.visible = true
			end_deployment_button.text = "End Morale"
	
	refresh_unit_list()
	update_ui()

func _on_movement_action_requested(action: Dictionary) -> void:
	print("Main: Received movement action request: ", action.type)
	
	# Process movement action through the phase
	var phase_instance = PhaseManager.get_current_phase_instance()
	print("Main: Phase instance is: ", phase_instance)
	
	if phase_instance:
		print("Main: Phase instance class: ", phase_instance.get_class())
		print("Main: Phase has execute_action: ", phase_instance.has_method("execute_action"))
		
		if phase_instance.has_method("execute_action"):
			print("Main: Executing action through phase")
			var result = phase_instance.execute_action(action)
			print("Main: Action result: ", result)
			
			if result.get("success", false):
				print("Main: Movement action succeeded")
				
				# Handle different action types
				match action.type:
					"BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK":
						# Movement has begun, mode should be set in controller
						print("Movement mode initiated: ", action.type)
					"SET_MODEL_DEST":
						print("Main: Processing SET_MODEL_DEST - updating visuals for ", action.actor_unit_id, "/", action.payload.model_id)
						_update_model_visual(action.actor_unit_id, action.payload.model_id, action.payload.dest)
					"UNDO_LAST_MODEL_MOVE":
						print("Model move undone")
						_recreate_unit_visuals()
					"RESET_UNIT_MOVE":
						print("Unit movement reset")
						_recreate_unit_visuals()
					"CONFIRM_UNIT_MOVE":
						print("Unit movement confirmed")
						# Clear the active unit in controller
						if movement_controller:
							movement_controller.active_unit_id = ""
							movement_controller.active_mode = ""
				
				# Update UI after successful action
				update_movement_card_buttons()
			else:
				print("Movement action failed: ", result.get("error", "Unknown error"))
				if result.has("errors"):
					for error in result.errors:
						print("  - ", error)
				# Show error in status label
				status_label.text = "Error: " + result.get("error", "Action failed")
		else:
			print("Main: Phase instance doesn't have execute_action method!")
	else:
		print("Main: No phase instance!")

func _show_movement_action_buttons(show: bool) -> void:
	# Show or hide movement action buttons
	var movement_actions = get_node_or_null("HUD_Right/VBoxContainer/MovementActions")
	if movement_actions:
		movement_actions.visible = show
		print("Movement action buttons visibility set to: ", show)
	else:
		print("WARNING: MovementActions container not found!")
		# If it doesn't exist and we want to show it, make sure MovementController creates it
		if show and movement_controller:
			movement_controller._setup_right_panel()

func _on_movement_ui_update_requested() -> void:
	# Update UI when MovementController requests it
	if current_phase == GameStateData.Phase.MOVEMENT:
		update_movement_card_buttons()

func _on_shooting_action_requested(action: Dictionary) -> void:
	print("Main: Received shooting action request: ", action.get("type", ""))
	
	# Process shooting action through the phase
	var phase_instance = PhaseManager.get_current_phase_instance()
	
	if phase_instance and phase_instance.has_method("execute_action"):
		var result = phase_instance.execute_action(action)
		if result.has("success"):
			if result.success:
				print("Main: Shooting action succeeded")
				update_after_shooting_action()
			else:
				print("Main: Shooting action failed: ", result.get("error", "Unknown error"))
		else:
			print("Main: Unexpected result from shooting action")
	else:
		print("Main: No phase instance or execute_action method")

func _on_shooting_ui_update_requested() -> void:
	# Update UI when ShootingController requests it
	if current_phase == GameStateData.Phase.SHOOTING:
		update_ui()

func _on_charge_action_requested(action: Dictionary) -> void:
	print("Main: Received charge action request: ", action.get("type", ""))
	
	# Process charge action through the phase
	var phase_instance = PhaseManager.get_current_phase_instance()
	
	if phase_instance and phase_instance.has_method("execute_action"):
		var result = phase_instance.execute_action(action)
		if result.has("success"):
			if result.success:
				print("Main: Charge action succeeded")
				
				# Apply any state changes
				var changes = result.get("changes", [])
				if not changes.is_empty():
					PhaseManager.apply_state_changes(changes)
				
				# Update UI after successful action
				update_after_charge_action()
			else:
				print("Main: Charge action failed: ", result.get("error", "Unknown error"))
		else:
			print("Main: Unexpected result from charge action")
	else:
		print("Main: No phase instance or execute_action method")

func _on_charge_ui_update_requested() -> void:
	# Update UI when ChargeController requests it
	if current_phase == GameStateData.Phase.CHARGE:
		update_ui()

func update_after_charge_action() -> void:
	# Refresh visuals and UI after a charge action
	_recreate_unit_visuals()
	refresh_unit_list()
	update_ui()
	
	# Update charge controller state
	if charge_controller:
		charge_controller._refresh_ui()

func update_after_shooting_action() -> void:
	# Refresh visuals and UI after a shooting action
	_recreate_unit_visuals()  # This should handle dead model removal
	refresh_unit_list()
	update_ui()
	
	# Update shooting controller state
	if shooting_controller:
		shooting_controller._refresh_unit_list()

func _update_model_visual(unit_id: String, model_id: String, dest: Array) -> void:
	# Update the visual position of the model
	print("Updating visual for ", unit_id, "/", model_id, " to ", dest)
	
	# Wait a frame for the GameState to fully update
	await get_tree().process_frame
	
	# Recreate all unit visuals with updated positions
	_recreate_unit_visuals()

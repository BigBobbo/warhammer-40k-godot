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

var unit_stats_panel: Control
var mathhammer_ui: Control
var save_load_dialog: AcceptDialog
var deployment_controller: Node
var command_controller: Node
var movement_controller: Node
var shooting_controller: Node
var charge_controller: Node
var fight_controller: Node
var scoring_controller: Node
var current_phase: GameStateData.Phase
var view_offset: Vector2 = Vector2.ZERO
var view_zoom: float = 1.0

func _ready() -> void:
	# Check if we're coming from main menu or loading a save
	var from_menu = GameState.state.meta.has("from_menu") if GameState.state.has("meta") else false
	var from_save = GameState.state.meta.has("from_save") if GameState.state.has("meta") else false
	
	if not from_menu and not from_save:
		# Legacy path: direct load for testing
		print("Main: Direct load detected, initializing default state")
		GameState.initialize_default_state()
	else:
		if from_menu:
			print("Main: Loading from main menu with configuration")
		elif from_save:
			print("Main: Loading from saved game")
	
	# Initialize view to show whole board
	view_zoom = 0.3
	view_offset = Vector2(0, 0)  # Start at top-left
	update_view_transform()
	
	# Camera controls: WASD/arrows to pan, +/- to zoom, F to focus on Player 2 zone
	
	board_view.queue_redraw()
	setup_deployment_zones()
	
	# Setup objectives on the board
	_setup_objectives()
	
	# Move HUD_Bottom to top and create stats panel at bottom
	_restructure_ui_layout()
	
	# Fix HUD layout to prevent overlap
	_fix_hud_layout()
	
	# Setup Mathhammer UI
	_setup_mathhammer_ui()
	
	# Setup Save/Load Dialog
	_setup_save_load_dialog()
	
	# Setup Terrain
	_setup_terrain()
	
	# Setup Measuring Tape
	_setup_measuring_tape()
	
	# Setup phase-specific controllers based on current phase
	current_phase = GameState.get_current_phase()
	await setup_phase_controllers()
	
	connect_signals()
	refresh_unit_list()
	update_ui()
	
	# Enable autosave (saves every 5 minutes)
	SaveLoadManager.enable_autosave()
	print("Quick Save/Load enabled: [ key to save, ] key (or F9) to load")

func _restructure_ui_layout() -> void:
	# Move HUD_Bottom to top of screen
	var hud_bottom = get_node("HUD_Bottom")
	if hud_bottom:
		hud_bottom.anchor_top = 0.0
		hud_bottom.anchor_bottom = 0.0
		hud_bottom.offset_top = 0.0
		hud_bottom.offset_bottom = 100.0
		print("Moved HUD_Bottom to top of screen")
	
	# Create unit stats panel at bottom
	_setup_unit_stats_panel()

func _fix_hud_layout() -> void:
	# Adjust both left and right HUD panels for proper layout
	var hud_left = get_node("HUD_Left")
	var hud_right = get_node("HUD_Right")
	
	# Reserve space for the unit stats panel at bottom (40px collapsed, up to 300px expanded)
	var bottom_height = 300.0  # Max height when expanded
	var top_height = 100.0    # Space for top panel
	
	if hud_left:
		# Adjust HUD_Left to not overlap with panels
		hud_left.anchor_bottom = 1.0
		hud_left.offset_bottom = -bottom_height
		hud_left.anchor_top = 0.0
		hud_left.offset_top = top_height  # Leave space for top panel
		
		print("Fixed HUD layout: HUD_Left adjusted for new layout")
	
	if hud_right:
		# Adjust HUD_Right to not overlap with bottom panel
		hud_right.anchor_bottom = 1.0
		hud_right.offset_bottom = -bottom_height
		hud_right.anchor_top = 0.0
		hud_right.offset_top = top_height  # Leave space for top panel
		
		print("Fixed HUD layout: HUD_Right adjusted for new layout")
	
	# Adjust unit list to take less space, giving more room to phase panels
	var unit_list = get_node_or_null("HUD_Right/VBoxContainer/UnitListPanel")
	if unit_list:
		# Change from size_flags_vertical = 3 (expand/fill) to 0 (fixed size)
		unit_list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unit_list.custom_minimum_size = Vector2(0, 150)  # Fixed height of 150px
		print("Adjusted unit list: fixed height to 150px")

func _setup_unit_stats_panel() -> void:
	# UnitStatsPanel is now directly in the Main.tscn scene file
	print("Looking for UnitStatsPanel in scene...")
	unit_stats_panel = get_node_or_null("UnitStatsPanel")
	
	if unit_stats_panel:
		print("Found UnitStatsPanel in scene structure")
		
		# Connect to the unit_selected signal from the panel
		if unit_stats_panel.has_signal("unit_selected"):
			unit_stats_panel.unit_selected.connect(_on_unit_stats_panel_unit_selected)
			print("Connected to unit_selected signal from UnitStatsPanel")
		else:
			print("Warning: UnitStatsPanel does not have unit_selected signal")
		
		# Initialize the panel with current phase
		if unit_stats_panel.has_method("populate_unit_lists"):
			var phase_name = GameStateData.Phase.keys()[current_phase]
			unit_stats_panel.populate_unit_lists(phase_name)
			print("Initialized UnitStatsPanel unit lists for phase: ", phase_name)
	else:
		print("ERROR: UnitStatsPanel not found in scene! Check Main.tscn")

func _create_stats_panel_programmatically() -> PanelContainer:
	print("Creating unit stats panel with full UI structure...")
	
	var panel = PanelContainer.new()
	panel.name = "UnitStatsPanel"
	
	# Main VBox container
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	panel.add_child(vbox)
	
	# Header with toggle button
	var header = HBoxContainer.new()
	header.name = "Header"
	header.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(header)
	
	var toggle_button = Button.new()
	toggle_button.name = "ToggleButton"
	toggle_button.text = "▲ Unit Stats"
	toggle_button.custom_minimum_size = Vector2(120, 30)
	toggle_button.add_theme_font_size_override("font_size", 14)
	header.add_child(toggle_button)
	
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	# Scroll container for content
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.custom_minimum_size = Vector2(0, 260)
	vbox.add_child(scroll)
	
	# Content VBox
	var content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	
	# Keywords section
	var keywords_container = HBoxContainer.new()
	content.add_child(keywords_container)
	
	var keywords_title = Label.new()
	keywords_title.text = "Keywords: "
	keywords_title.add_theme_font_size_override("font_size", 12)
	keywords_container.add_child(keywords_title)
	
	var keywords_label = Label.new()
	keywords_label.name = "KeywordsLabel"
	keywords_label.text = "TEST KEYWORDS - Panel Working!"
	keywords_label.add_theme_font_size_override("font_size", 12)
	keywords_container.add_child(keywords_label)
	
	# Separator
	content.add_child(HSeparator.new())
	
	# Stats section
	var stats_container = VBoxContainer.new()
	content.add_child(stats_container)
	
	var stats_title = Label.new()
	stats_title.text = "UNIT STATS"
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_container.add_child(stats_title)
	
	var stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.text = "M6\" | T4 | Sv3+ | W2 | Ld6+ | OC2 (PROGRAMMATIC TEST)"
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_container.add_child(stats_label)
	
	# Separator
	content.add_child(HSeparator.new())
	
	# Weapons section
	var weapons_container = VBoxContainer.new()
	weapons_container.name = "WeaponsContainer"
	content.add_child(weapons_container)
	
	var weapons_title = Label.new()
	weapons_title.text = "WEAPONS"
	weapons_title.add_theme_font_size_override("font_size", 14)
	weapons_container.add_child(weapons_title)
	
	var weapons_test = Label.new()
	weapons_test.text = "✓ Toggle button should be visible above\n✓ This content should be visible\n✓ Panel should be at screen bottom"
	weapons_test.add_theme_font_size_override("font_size", 12)
	weapons_container.add_child(weapons_test)
	
	# Store collapsed state as a property of the panel
	panel.set_meta("is_collapsed", false)
	
	# Connect toggle button with proper state tracking
	toggle_button.pressed.connect(func():
		var is_collapsed = panel.get_meta("is_collapsed", false)
		is_collapsed = !is_collapsed
		panel.set_meta("is_collapsed", is_collapsed)
		print("Toggle clicked - collapsed: ", is_collapsed)
		
		# Update button text
		toggle_button.text = "▼ Unit Stats" if is_collapsed else "▲ Unit Stats"
		
		# Update content visibility
		scroll.visible = !is_collapsed
		print("Setting scroll visible to: ", !is_collapsed)
		
		# Set panel size immediately
		if is_collapsed:
			panel.custom_minimum_size.y = 40
			panel.offset_top = -40
			panel.size.y = 40
		else:
			panel.custom_minimum_size.y = 300
			panel.offset_top = -300
			panel.size.y = 300
		
		print("Set panel height to: ", panel.custom_minimum_size.y)
		print("Set panel offset to: ", panel.offset_top)
		print("Set panel size to: ", panel.size.y)
		
		# Force the panel to update its layout
		panel.set_deferred("size:y", panel.custom_minimum_size.y)
		
		# Debug output after a frame
		panel.get_tree().create_timer(0.1).timeout.connect(func():
			print("After update - Panel size: ", panel.size)
			print("After update - Panel offset_top: ", panel.offset_top)
			print("After update - Scroll visible: ", scroll.visible)
		)
	)
	
	# Add display_unit method to the panel for showing unit data
	panel.set_meta("display_unit", func(unit_data: Dictionary):
		print("Displaying unit data for: ", unit_data.get("id", "unknown"))
		
		# Update keywords
		if keywords_label and unit_data.has("meta"):
			var meta = unit_data["meta"]
			if meta.has("keywords"):
				keywords_label.text = ", ".join(meta["keywords"])
		
		# Update stats
		if stats_label and unit_data.has("meta"):
			var meta = unit_data["meta"]
			if meta.has("stats"):
				var stats = meta["stats"]
				stats_label.text = "M%d\" | T%d | Sv%d+ | W%d | Ld%d+ | OC%d" % [
					stats.get("move", 0),
					stats.get("toughness", 0),
					stats.get("save", 0),
					stats.get("wounds", 0),
					stats.get("leadership", 0),
					stats.get("objective_control", 0)
				]
		
		# Clear and update weapons
		for child in weapons_container.get_children():
			if child != weapons_title:
				child.queue_free()
		
		if unit_data.has("meta") and unit_data["meta"].has("weapons"):
			var weapons = unit_data["meta"]["weapons"]
			for weapon in weapons:
				var weapon_label = Label.new()
				var weapon_type = weapon.get("type", "Unknown")
				var weapon_name = weapon.get("name", "Unknown")
				var weapon_stats = ""
				
				if weapon_type == "Ranged":
					weapon_stats = "Range: %s\" | A: %s | BS: %s+ | S: %s | AP: %s | D: %s" % [
						weapon.get("range", "-"),
						weapon.get("attacks", "-"),
						weapon.get("ballistic_skill", "-"),
						weapon.get("strength", "-"),
						weapon.get("ap", "-"),
						weapon.get("damage", "-")
					]
				else:  # Melee
					weapon_stats = "Melee | A: %s | WS: %s+ | S: %s | AP: %s | D: %s" % [
						weapon.get("attacks", "-"),
						weapon.get("weapon_skill", "-"),
						weapon.get("strength", "-"),
						weapon.get("ap", "-"),
						weapon.get("damage", "-")
					]
				
				weapon_label.text = "• %s (%s): %s" % [weapon_name, weapon_type, weapon_stats]
				weapon_label.add_theme_font_size_override("font_size", 11)
				weapons_container.add_child(weapon_label)
		
		print("Unit data display updated")
	)
	
	print("Programmatic panel created with toggle functionality and display_unit method")
	return panel

func _setup_mathhammer_ui() -> void:
	# Create MathhhammerUI and add it to the left HUD
	print("Setting up Mathhammer UI...")
	
	# Create the MathhhammerUI instance using preload
	var MathhhammerUIClass = preload("res://scripts/MathhhammerUI.gd")
	mathhammer_ui = MathhhammerUIClass.new()
	mathhammer_ui.name = "MathhhammerUI"
	
	if mathhammer_ui:
		# Add to the left HUD VBox container 
		var hud_left_vbox = get_node("HUD_Left/VBoxContainer")
		if hud_left_vbox:
			# Add the Mathhammer UI to the left HUD
			hud_left_vbox.add_child(mathhammer_ui)
			print("Mathhammer UI added to left HUD")
		else:
			print("ERROR: Could not find HUD_Left/VBoxContainer!")
			return
		
		print("Mathhammer UI successfully integrated into left side of main UI")
	else:
		print("ERROR: Failed to create MathhhammerUI instance!")

func _setup_measuring_tape() -> void:
	print("Setting up measuring tape visual...")
	
	# Create measuring tape visual layer
	var measuring_tape_visual = preload("res://scripts/MeasuringTapeVisual.gd").new()
	measuring_tape_visual.name = "MeasuringTapeVisual"
	$BoardRoot.add_child(measuring_tape_visual)
	print("Added MeasuringTapeVisual to BoardRoot")
	print("Measuring Tape: Hold 't' and drag to measure, press 'y' to clear all measurements")
	
	# Add measuring tape save toggle to top HUD
	var hud_container = $HUD_Bottom/HBoxContainer
	if hud_container:
		# Add separator
		var separator = VSeparator.new()
		hud_container.add_child(separator)
		
		# Create measuring tape save toggle button
		var tape_save_button = CheckBox.new()
		tape_save_button.name = "MeasuringTapeSaveToggle"
		tape_save_button.text = "Save Measurements"
		tape_save_button.button_pressed = SettingsService.get_save_measurements()
		tape_save_button.toggled.connect(_on_measuring_tape_save_toggle)
		tape_save_button.tooltip_text = "Enable to persist measurement lines in save files"
		tape_save_button.add_theme_font_size_override("font_size", 12)
		hud_container.add_child(tape_save_button)
		
		print("Added measuring tape save toggle to HUD")

func _setup_terrain() -> void:
	print("Setting up terrain system...")
	
	# Create terrain visual layer
	var terrain_visual = preload("res://scripts/TerrainVisual.gd").new()
	terrain_visual.name = "TerrainVisual"
	$BoardRoot.add_child(terrain_visual)
	print("Added TerrainVisual to BoardRoot")
	
	# Add terrain toggle button to top HUD
	var hud_container = $HUD_Bottom/HBoxContainer
	if hud_container:
		# Add separator
		var separator = VSeparator.new()
		hud_container.add_child(separator)
		
		# Create terrain toggle button
		var terrain_button = Button.new()
		terrain_button.name = "TerrainToggleButton"
		terrain_button.text = "Toggle Terrain"
		terrain_button.toggle_mode = true
		terrain_button.button_pressed = true  # Start with terrain visible
		terrain_button.toggled.connect(_on_terrain_toggle)
		hud_container.add_child(terrain_button)
		
		# Create terrain info label
		var terrain_label = Label.new()
		terrain_label.name = "TerrainInfoLabel"
		terrain_label.text = "Terrain: Layout 2"
		terrain_label.add_theme_font_size_override("font_size", 12)
		hud_container.add_child(terrain_label)
		
		# Add LoS debug toggle button
		var los_button = Button.new()
		los_button.name = "LoSDebugButton"
		los_button.text = "LoS Debug (L)"
		los_button.toggle_mode = true
		los_button.button_pressed = true  # Start with debug on
		los_button.toggled.connect(func(pressed): _toggle_los_debug())
		hud_container.add_child(los_button)
		
		print("Added terrain UI controls to HUD")

func _on_terrain_toggle(pressed: bool) -> void:
	TerrainManager.set_terrain_visibility(pressed)
	print("Terrain visibility: ", pressed)

func _on_measuring_tape_save_toggle(pressed: bool) -> void:
	SettingsService.set_save_measurements(pressed)
	print("Measuring tape save persistence: ", pressed)
	if pressed:
		_show_toast("Measurements will be saved with game state")
	else:
		_show_toast("Measurements will NOT be saved")

func _setup_objectives() -> void:
	print("Setting up objectives on board...")
	
	# Create objectives container
	var objectives_container = Node2D.new()
	objectives_container.name = "Objectives"
	objectives_container.z_index = -8  # Between board and deployment zones
	$BoardRoot.add_child(objectives_container)
	
	if MissionManager:
		var objectives = GameState.state.board.get("objectives", [])
		print("Main: Creating visuals for %d objectives" % objectives.size())
		
		for obj in objectives:
			var obj_visual = preload("res://scripts/ObjectiveVisual.gd").new()
			obj_visual.setup(obj)
			objectives_container.add_child(obj_visual)
			
			# Store reference in MissionManager for easy access
			MissionManager.objectives_visual_refs[obj.id] = obj_visual
			
			# Connect to control changes
			MissionManager.objective_control_changed.connect(
				func(obj_id, controller):
					if obj_id == obj.id:
						obj_visual.update_control(controller)
			)
		
		# Do initial control check
		MissionManager.check_all_objectives()
		
		print("Main: Objectives setup complete")
	else:
		print("Main: MissionManager not available, skipping objectives")

func _toggle_los_debug() -> void:
	# Find LoS debug visual
	var los_debug = get_node_or_null("BoardRoot/LoSDebugVisual")
	if los_debug:
		los_debug.toggle_debug()
		print("LoS debug visualization: ", los_debug.debug_enabled)
		_show_toast("LoS Debug: " + ("ON" if los_debug.debug_enabled else "OFF"))
	else:
		print("LoS debug visual not found")

func _show_toast(message: String, duration: float = 2.0) -> void:
	# Show a temporary message on screen
	var toast = Label.new()
	toast.text = message
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_color", Color.YELLOW)
	toast.add_theme_color_override("font_shadow_color", Color.BLACK)
	toast.add_theme_constant_override("shadow_offset_x", 2)
	toast.add_theme_constant_override("shadow_offset_y", 2)
	
	# Position at top center
	var viewport_size = get_viewport().get_visible_rect().size
	toast.position = Vector2(viewport_size.x / 2 - 100, 150)
	
	add_child(toast)
	
	# Auto-remove after duration
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(toast):
		toast.queue_free()

func _setup_save_load_dialog() -> void:
	# Load and instantiate the SaveLoadDialog scene
	print("Setting up Save/Load Dialog...")
	
	var dialog_scene = preload("res://scenes/SaveLoadDialog.tscn")
	save_load_dialog = dialog_scene.instantiate()
	save_load_dialog.name = "SaveLoadDialog"
	
	# Add to scene tree
	add_child(save_load_dialog)
	
	# Connect dialog signals
	save_load_dialog.save_requested.connect(_on_save_requested)
	save_load_dialog.load_requested.connect(_on_load_requested)
	save_load_dialog.delete_requested.connect(_on_delete_requested)
	
	# Hide initially
	save_load_dialog.hide()
	
	print("Save/Load Dialog setup completed")

func setup_deployment_zones() -> void:
	var zone1 = BoardState.get_deployment_zone_for_player(1)
	var zone2 = BoardState.get_deployment_zone_for_player(2)
	
	p1_zone.polygon = zone1
	p2_zone.polygon = zone2
	
	update_deployment_zone_visibility()

func setup_phase_controllers() -> void:
	# ENHANCEMENT: Clear right panel before cleanup
	_clear_right_panel_phase_ui()
	
	# Clean up existing controllers
	if deployment_controller:
		deployment_controller.queue_free()
		deployment_controller = null
	if command_controller:
		command_controller.queue_free()
		command_controller = null
	if movement_controller:
		movement_controller.queue_free()
		movement_controller = null
	if shooting_controller:
		shooting_controller.queue_free()
		shooting_controller = null
	if charge_controller:
		charge_controller.queue_free()
		charge_controller = null
	if fight_controller:
		fight_controller.queue_free()
		fight_controller = null
	if scoring_controller:
		scoring_controller.queue_free()
		scoring_controller = null
	
	# Wait TWO frames for complete cleanup
	await get_tree().process_frame
	await get_tree().process_frame
	
	# ENHANCEMENT: Clear again after controller cleanup
	_clear_right_panel_phase_ui()
	
	# Setup controller based on current phase
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			setup_deployment_controller()
		GameStateData.Phase.COMMAND:
			setup_command_controller()
		GameStateData.Phase.MOVEMENT:
			setup_movement_controller()
		GameStateData.Phase.SHOOTING:
			setup_shooting_controller()
		GameStateData.Phase.CHARGE:
			setup_charge_controller()
		GameStateData.Phase.FIGHT:
			setup_fight_controller()
		GameStateData.Phase.SCORING:
			setup_scoring_controller()
		_:
			print("No controller for phase: ", current_phase)

func setup_deployment_controller() -> void:
	deployment_controller = preload("res://scripts/DeploymentController.gd").new()
	deployment_controller.name = "DeploymentController"
	add_child(deployment_controller)
	deployment_controller.set_layers(token_layer, ghost_layer)

func setup_command_controller() -> void:
	print("Setting up CommandController...")
	command_controller = preload("res://scripts/CommandController.gd").new()
	command_controller.name = "CommandController"
	add_child(command_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a CommandPhase
		var is_command_phase = false
		if phase_instance.get("phase_type") == GameStateData.Phase.COMMAND:
			is_command_phase = true
		
		if is_command_phase:
			command_controller.set_phase(phase_instance)
			print("Connected CommandController to CommandPhase")
		else:
			print("WARNING: Phase instance is not a CommandPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect command controller signals
	if not command_controller.command_action_requested.is_connected(_on_command_action_requested):
		command_controller.command_action_requested.connect(_on_command_action_requested)
		print("Connected command_action_requested signal")
	if not command_controller.ui_update_requested.is_connected(_on_command_ui_update_requested):
		command_controller.ui_update_requested.connect(_on_command_ui_update_requested)
		print("Connected ui_update_requested signal")

func setup_movement_controller() -> void:
	print("Setting up MovementController...")
	movement_controller = preload("res://scripts/MovementController.gd").new()
	movement_controller.name = "MovementController"
	add_child(movement_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a MovementPhase by checking for movement-specific signals or methods
		var is_movement_phase = false
		if phase_instance.has_signal("unit_move_begun"):
			is_movement_phase = true
		elif phase_instance.get("phase_type") == GameStateData.Phase.MOVEMENT:
			is_movement_phase = true
		elif phase_instance.has_method("_process_begin_normal_move"):
			# If it has movement-specific methods, treat it as MovementPhase
			is_movement_phase = true
		elif phase_instance.has_method("_validate_stage_model_move"):
			# Or if it has our new staged move methods
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
				# Also connect to Main for visual updates
				if not phase_instance.model_drop_committed.is_connected(_on_model_drop_committed):
					phase_instance.model_drop_committed.connect(_on_model_drop_committed)
					print("Connected model_drop_committed to Main for visual updates")
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

func setup_fight_controller() -> void:
	print("Setting up FightController...")
	fight_controller = preload("res://scripts/FightController.gd").new()
	fight_controller.name = "FightController"
	add_child(fight_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a FightPhase
		var is_fight_phase = false
		if phase_instance.has_signal("fighter_selected"):
			is_fight_phase = true
		elif phase_instance.get("phase_type") == GameStateData.Phase.FIGHT:
			is_fight_phase = true
		
		if is_fight_phase:
			fight_controller.set_phase(phase_instance)
			print("Connected FightController to FightPhase")
		else:
			print("WARNING: Phase instance is not a FightPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect fight controller signals
	if not fight_controller.fight_action_requested.is_connected(_on_fight_action_requested):
		fight_controller.fight_action_requested.connect(_on_fight_action_requested)
		print("Connected fight_action_requested signal")
	if not fight_controller.ui_update_requested.is_connected(_on_fight_ui_update_requested):
		fight_controller.ui_update_requested.connect(_on_fight_ui_update_requested)
		print("Connected ui_update_requested signal")

func setup_scoring_controller() -> void:
	print("Setting up ScoringController...")
	scoring_controller = preload("res://scripts/ScoringController.gd").new()
	scoring_controller.name = "ScoringController"
	add_child(scoring_controller)
	
	# Get the current phase instance from PhaseManager
	var phase_instance = PhaseManager.get_current_phase_instance()
	if phase_instance:
		print("Phase instance found: ", phase_instance.get_class())
		
		# Check if it's a ScoringPhase
		var is_scoring_phase = false
		if phase_instance.get("phase_type") == GameStateData.Phase.SCORING:
			is_scoring_phase = true
		
		if is_scoring_phase:
			scoring_controller.set_phase(phase_instance)
			print("Connected ScoringController to ScoringPhase")
		else:
			print("WARNING: Phase instance is not a ScoringPhase, skipping signal connections")
	else:
		print("WARNING: No phase instance found!")
	
	# Connect scoring controller signals
	if not scoring_controller.scoring_action_requested.is_connected(_on_scoring_action_requested):
		scoring_controller.scoring_action_requested.connect(_on_scoring_action_requested)
		print("Connected scoring_action_requested signal")
	if not scoring_controller.ui_update_requested.is_connected(_on_scoring_ui_update_requested):
		scoring_controller.ui_update_requested.connect(_on_scoring_ui_update_requested)
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
	# Debug mode toggle - highest priority
	if event is InputEventKey and event.pressed and event.keycode == KEY_9:
		print("Debug mode key (9) pressed!")
		DebugManager.toggle_debug_mode()
		get_viewport().set_input_as_handled()
		return
	
	# LoS debug toggle - KEY_L
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		print("LoS debug toggle key (L) pressed!")
		_toggle_los_debug()
		get_viewport().set_input_as_handled()
		return
	
	# Objective control check debug - KEY_O
	if event is InputEventKey and event.pressed and event.keycode == KEY_O:
		print("\n=== MANUAL OBJECTIVE CONTROL CHECK (O key pressed) ===")
		if MissionManager:
			MissionManager.check_all_objectives()
			var control_summary = MissionManager.get_objective_control_summary()
			print("Control Summary:")
			print("  Player 1 controlled: %d" % control_summary.player1_controlled)
			print("  Player 2 controlled: %d" % control_summary.player2_controlled)
			print("  Contested: %d" % control_summary.contested)
			print("\nObjective Status:")
			for obj_id in control_summary.objectives:
				var controller = control_summary.objectives[obj_id]
				var control_text = "Contested"
				if controller == 1:
					control_text = "Player 1"
				elif controller == 2:
					control_text = "Player 2"
				print("  %s: %s" % [obj_id, control_text])
		else:
			print("MissionManager not available!")
		print("=== END OBJECTIVE CONTROL CHECK ===\n")
		get_viewport().set_input_as_handled()
		return
	
	# Measuring Tape controls - 't' to measure, 'y' to clear
	if event is InputEventKey:
		# Start/stop measuring with 't' key
		if event.keycode == KEY_T:
			if event.pressed and not MeasuringTapeManager.is_measuring:
				var mouse_pos = get_viewport().get_mouse_position()
				var world_pos = screen_to_world_position(mouse_pos)
				MeasuringTapeManager.start_measurement(world_pos)
				get_viewport().set_input_as_handled()
			elif not event.pressed and MeasuringTapeManager.is_measuring:
				var mouse_pos = get_viewport().get_mouse_position()
				var world_pos = screen_to_world_position(mouse_pos)
				if MeasuringTapeManager.can_add_measurement():
					MeasuringTapeManager.complete_measurement(world_pos)
				else:
					print("Maximum number of measurements reached (10). Clear with 'y' key.")
					MeasuringTapeManager.cancel_measurement()
				get_viewport().set_input_as_handled()
			return
		
		# Clear all measurements with 'y' key
		if event.pressed and event.keycode == KEY_Y:
			MeasuringTapeManager.clear_all_measurements()
			print("All measurements cleared")
			get_viewport().set_input_as_handled()
			return
	
	# Update measurement preview while dragging
	if event is InputEventMouseMotion and MeasuringTapeManager.is_measuring:
		var world_pos = screen_to_world_position(event.position)
		MeasuringTapeManager.update_measurement(world_pos)
	
	# ESC key handling for save/load dialog
	# Only handle ESC if dialog is not visible (to avoid interfering with dialog input)
	if event.is_action_pressed("ui_cancel"):
		if save_load_dialog and not save_load_dialog.visible:
			_toggle_save_load_menu()
			get_viewport().set_input_as_handled()
			return
		elif save_load_dialog and save_load_dialog.visible:
			# Let the dialog handle ESC (it has dialog_close_on_escape = true)
			return
	
	# Don't process other input while dialog is open
	if save_load_dialog and save_load_dialog.visible:
		return
	
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
	# Update the new bottom panel unit lists (always visible for comparison)
	if unit_stats_panel and unit_stats_panel.has_method("populate_unit_lists"):
		var phase_name = GameStateData.Phase.keys()[current_phase]
		unit_stats_panel.populate_unit_lists(phase_name)
		print("Refreshed bottom panel unit lists for phase: ", phase_name)
	
	# Right panel unit list - phase-specific functionality
	unit_list.clear()
	var active_player = GameState.get_active_player()
	
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			# Show only undeployed units during deployment in right panel
			unit_list.visible = true
			var units = GameState.get_undeployed_units_for_player(active_player)
			print("Refreshing right panel unit list for deployment - found ", units.size(), " undeployed units")
			
			for unit_id in units:
				var unit_data = GameState.get_unit(unit_id)
				var unit_name = unit_data["meta"]["name"]
				var model_count = unit_data["models"].size()
				var display_text = "%s (%d models)" % [unit_name, model_count]
				unit_list.add_item(display_text)
				unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)
		
		GameStateData.Phase.MOVEMENT:
			# Show deployed units during movement in right panel
			unit_list.visible = true
			var all_units = GameState.get_units_for_player(active_player)
			var deployed_count = 0
			
			for unit_id in all_units:
				var unit = all_units[unit_id]
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
			
			print("Refreshing right panel unit list for movement - found ", deployed_count, " deployed units")
		
		GameStateData.Phase.SHOOTING:
			# Hide unit list during shooting phase - shooting controller handles its own UI
			unit_list.visible = false
			unit_list.clear()
			print("Refreshing right panel unit list for shooting - unit list hidden")
		
		GameStateData.Phase.CHARGE:
			# Hide unit list during charge phase - charge controller handles its own UI
			unit_list.visible = false
			unit_list.clear()
			print("Refreshing right panel unit list for charge - unit list hidden")
		
		GameStateData.Phase.FIGHT:
			# Hide unit list during fight phase - fight controller handles its own UI
			unit_list.visible = false
			unit_list.clear()
			print("Refreshing right panel unit list for fight - unit list hidden")
		
		_:
			# Default: show all units for active player in right panel
			unit_list.visible = true
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
	
	# Show detailed stats in bottom panel
	var unit_data = GameState.get_unit(unit_id)
	print("Main: Unit selected - ", unit_id)
	print("Main: Unit data available - ", unit_data != null)
	print("Main: Unit stats panel available - ", unit_stats_panel != null)
	
	if unit_data and unit_stats_panel:
		# Try the programmatic display_unit function stored as metadata
		var display_func = unit_stats_panel.get_meta("display_unit", null)
		if display_func:
			print("Main: Calling programmatic display_unit function")
			display_func.call(unit_data)
		elif unit_stats_panel.has_method("display_unit"):
			print("Main: Calling display_unit method")
			unit_stats_panel.display_unit(unit_data)
		else:
			print("Main: No display_unit method available!")
	
	# Handle unit selection based on current phase
	if current_phase == GameStateData.Phase.DEPLOYMENT and deployment_controller:
		deployment_controller.begin_deploy(unit_id)
		show_unit_card(unit_id)
		unit_list.visible = false
	elif current_phase == GameStateData.Phase.MOVEMENT and movement_controller:
		# Pass unit selection to MovementController
		movement_controller.active_unit_id = unit_id
		print("Selected unit for movement: ", unit_id)
		# REMOVED: show_unit_card(unit_id) - MovementController handles its own UI
		# REMOVED: update_movement_card_buttons() - MovementController handles its own UI
		
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

func _on_unit_stats_panel_unit_selected(unit_id: String, is_enemy: bool) -> void:
	var unit_data = GameState.get_unit(unit_id)
	if not unit_data:
		print("Main: Unit not found - ", unit_id)
		return
	
	print("Main: Unit selected from bottom panel - ", unit_id, " (enemy: ", is_enemy, ")")
	
	# Show the unit card with unit info (but not during movement phase)
	if current_phase != GameStateData.Phase.MOVEMENT:
		show_unit_card(unit_id)
	
	# Handle selection based on phase and unit ownership
	if not is_enemy:  # Player unit selected
		# Handle unit selection based on current phase
		if current_phase == GameStateData.Phase.DEPLOYMENT and deployment_controller:
			deployment_controller.begin_deploy(unit_id)
			unit_list.visible = false
		elif current_phase == GameStateData.Phase.MOVEMENT and movement_controller:
			# Pass unit selection to MovementController
			movement_controller.active_unit_id = unit_id
			print("Selected unit for movement: ", unit_id)
			# REMOVED: update_movement_card_buttons() - MovementController handles its own UI
			
			# AUTO-START NORMAL MOVE FOR EASIER TESTING
			print("Auto-starting Normal Move for easier testing...")
			var action = {
				"type": "BEGIN_NORMAL_MOVE",
				"actor_unit_id": unit_id,
				"payload": {}
			}
			_on_movement_action_requested(action)
			status_label.text = "Drag models to move them (Normal Move mode)"
	else:  # Enemy unit selected
		# For enemy units, just show the card for viewing
		print("Enemy unit selected for viewing: ", unit_id)
		# Could add additional enemy-specific functionality here
	
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
				var current_unit_id = deployment_controller.get_current_unit()
				if current_unit_id and current_unit_id != "":
					var unit_data = GameState.get_unit(current_unit_id)
					if unit_data and unit_data.has("models"):
						var placed = deployment_controller.get_placed_count()
						var total = unit_data["models"].size()
						
						models_label.text = "Models: %d/%d" % [placed, total]
						
						# Show buttons based on deployment progress
						undo_button.visible = placed > 0
						reset_button.visible = false  # No reset in deployment
						confirm_button.visible = placed == total
					else:
						# No active deployment, hide buttons
						undo_button.visible = false
						reset_button.visible = false
						confirm_button.visible = false
				else:
					# No unit being deployed, hide deployment buttons
					undo_button.visible = false
					reset_button.visible = false
					confirm_button.visible = false
		
		GameStateData.Phase.MOVEMENT:
			# CHANGE: Don't call update_movement_card_buttons() - MovementController manages its own UI
			unit_card.visible = false

func update_movement_card_buttons() -> void:
	if not movement_controller:
		return
	
	# EARLY EXIT: Don't show UnitCard during movement phase
	if current_phase == GameStateData.Phase.MOVEMENT:
		unit_card.visible = false
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
		
		# ENHANCEMENT: Clear UI before phase setup
		_clear_right_panel_phase_ui()
		
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

# Save/Load Dialog handlers
func _toggle_save_load_menu() -> void:
	if save_load_dialog.visible:
		save_load_dialog.hide()
		print("Save/Load dialog hidden")
	else:
		# Show the dialog and ensure it gets focus
		save_load_dialog.show_dialog()
		print("Save/Load dialog shown")

func _on_save_requested(save_name: String) -> void:
	print("Main: Save requested with name: ", save_name)
	
	# Create metadata with user description
	var user_description = save_name
	var metadata = {
		"type": "manual",
		"description": user_description
	}
	
	# Show saving notification
	_show_save_notification("Saving...", Color.YELLOW)
	
	# Perform save
	var success = SaveLoadManager.save_game(save_name, metadata)
	if not success:
		_show_save_notification("Save failed!", Color.RED)

func _on_load_requested(save_file: String) -> void:
	print("Main: Load requested for file: ", save_file)
	
	# Show loading notification
	_show_save_notification("Loading...", Color.YELLOW)
	
	# Perform load
	var success = SaveLoadManager.load_game(save_file)
	if success:
		_show_save_notification("Game loaded!", Color.BLUE)
		
		# ENHANCEMENT: Clear UI before phase setup
		_clear_right_panel_phase_ui()
		
		# Update current phase
		current_phase = GameState.get_current_phase()
		
		# Sync BoardState with loaded GameState
		_sync_board_state_with_game_state()
		
		# Recreate phase controllers for the loaded phase
		await setup_phase_controllers()
		
		# Give controllers time to initialize
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
		_show_save_notification("Load failed!", Color.RED)

func _on_delete_requested(save_file: String) -> void:
	print("Main: Delete requested for file: ", save_file)
	
	# Perform deletion
	var success = SaveLoadManager.delete_save_file(save_file)
	if success:
		_show_save_notification("Save deleted!", Color.ORANGE)
		print("Save file deleted successfully: ", save_file)
	else:
		_show_save_notification("Delete failed!", Color.RED)
		print("Failed to delete save file: ", save_file)

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
	# setup_phase_controllers() already handles right panel cleanup
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
			# Show unit list and unit card during deployment phase
			unit_list.visible = true
			unit_card.visible = true
			
		GameStateData.Phase.COMMAND:
			phase_label.text = "Command Phase"
			end_deployment_button.visible = false  # Command phase has its own "End Command Phase" button
			# Hide deployment zones during command phase
			p1_zone.visible = false
			p2_zone.visible = false
			# Hide movement action buttons during command
			_show_movement_action_buttons(false)
			# Hide unit list and unit card during command phase
			unit_list.visible = false
			unit_card.visible = false
			
		GameStateData.Phase.MOVEMENT:
			phase_label.text = "Movement Phase"
			end_deployment_button.visible = true
			end_deployment_button.text = "End Movement"
			# Hide deployment zones during movement
			p1_zone.visible = false
			p2_zone.visible = false
			# Show movement action buttons
			_show_movement_action_buttons(true)
			# Show unit list and unit card during movement phase
			unit_list.visible = true
			unit_card.visible = true
			
		GameStateData.Phase.SHOOTING:
			phase_label.text = "Shooting Phase"
			end_deployment_button.visible = true
			end_deployment_button.text = "End Shooting"
			# Hide unit list and unit card during shooting phase
			unit_list.visible = false
			unit_card.visible = false
			
		GameStateData.Phase.CHARGE:
			phase_label.text = "Charge Phase"
			# Hide main end button during charge phase - ChargeController handles its own End Charge Phase button
			end_deployment_button.visible = false
			# Hide unit list and unit card during charge phase
			unit_list.visible = false
			unit_card.visible = false
			
		GameStateData.Phase.FIGHT:
			phase_label.text = "Fight Phase"
			end_deployment_button.visible = false  # FightController handles its own "End Fight Phase" button
			
		GameStateData.Phase.SCORING:
			phase_label.text = "Scoring Phase"
			end_deployment_button.visible = false  # Scoring phase has its own "End Turn" button
			# Hide unit list and unit card during scoring phase
			unit_list.visible = false
			unit_card.visible = false
			
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
				
				# Update UI after successful action (state changes applied by BasePhase)
				update_after_charge_action()
			else:
				print("Main: Charge action failed: ", result.get("error", "Unknown error"))
				print("Main: Full charge action result: ", result)
		else:
			print("Main: Unexpected result from charge action")
	else:
		print("Main: No phase instance or execute_action method")

func _on_charge_ui_update_requested() -> void:
	# Update UI when ChargeController requests it
	if current_phase == GameStateData.Phase.CHARGE:
		update_ui()

func _on_fight_action_requested(action: Dictionary) -> void:
	print("Main: Received fight action request: ", action.get("type", ""))
	
	# Process fight action through the phase
	var phase_instance = PhaseManager.get_current_phase_instance()
	
	if phase_instance and phase_instance.has_method("execute_action"):
		var result = phase_instance.execute_action(action)
		if result.has("success"):
			if result.success:
				print("Main: Fight action succeeded")
				
				# Note: State changes are already applied by BasePhase.execute_action()
				# No need to apply them again here
				
				# Update UI after successful action
				update_after_fight_action()
			else:
				print("Main: Fight action failed: ", result.get("error", "Unknown error"))
		else:
			print("Main: Unexpected result from fight action")
	else:
		print("Main: No phase instance or execute_action method")

func _on_fight_ui_update_requested() -> void:
	# Update UI when FightController requests it
	if current_phase == GameStateData.Phase.FIGHT:
		update_ui()

func _on_scoring_action_requested(action: Dictionary) -> void:
	print("Main: Received scoring action request: ", action.get("type", ""))
	
	# Process scoring action through the phase
	var phase_instance = PhaseManager.get_current_phase_instance()
	
	if phase_instance and phase_instance.has_method("execute_action"):
		var result = phase_instance.execute_action(action)
		if result.has("success"):
			if result.success:
				print("Main: Scoring action succeeded")
				
				# Note: State changes are already applied by BasePhase.execute_action()
				# No need to apply them again here
				
				# Update UI after successful action
				update_after_scoring_action()
			else:
				print("Main: Scoring action failed: ", result.get("error", "Unknown error"))
		else:
			print("Main: Unexpected result from scoring action")
	else:
		print("Main: No phase instance or execute_action method")

func _on_command_action_requested(action: Dictionary) -> void:
	print("Main: Received command action request: ", action.get("type", ""))
	
	# Process command action through the phase
	var phase_instance = PhaseManager.get_current_phase_instance()
	
	if phase_instance and phase_instance.has_method("execute_action"):
		var result = phase_instance.execute_action(action)
		if result.has("success"):
			if result.success:
				print("Main: Command action succeeded")
				
				# Note: State changes are already applied by BasePhase.execute_action()
				# No need to apply them again here
				
				# Update UI after successful action
				update_after_command_action()
			else:
				print("Main: Command action failed: ", result.get("error", "Unknown error"))
		else:
			print("Main: Unexpected result from command action")
	else:
		print("Main: No phase instance or execute_action method")

func _on_command_ui_update_requested() -> void:
	# Update UI when CommandController requests it
	if current_phase == GameStateData.Phase.COMMAND:
		update_ui()

func update_after_command_action() -> void:
	# Refresh UI after a command action
	refresh_unit_list()
	update_ui()
	
	# Update command controller state
	if command_controller:
		command_controller._refresh_ui()

func _on_scoring_ui_update_requested() -> void:
	# Update UI when ScoringController requests it
	if current_phase == GameStateData.Phase.SCORING:
		update_ui()

func update_after_scoring_action() -> void:
	# Refresh UI after a scoring action (mainly for turn switching)
	refresh_unit_list()
	update_ui()
	
	# Update scoring controller state
	if scoring_controller:
		scoring_controller._refresh_ui()

func update_after_charge_action() -> void:
	print("DEBUG: update_after_charge_action called")
	
	# Refresh visuals and UI after a charge action
	_recreate_unit_visuals()
	refresh_unit_list()
	update_ui()
	
	# Update charge controller state
	if charge_controller:
		charge_controller._refresh_ui()
	
	print("DEBUG: Charge action visual update completed")

func update_after_fight_action() -> void:
	# Refresh visuals and UI after a fight action
	_recreate_unit_visuals()  # This should handle dead model removal
	refresh_unit_list()
	update_ui()
	
	# Update fight controller state
	if fight_controller:
		fight_controller._refresh_fight_sequence()

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

func _on_model_drop_committed(unit_id: String, model_id: String, dest_px: Vector2) -> void:
	# Handle visual updates for model drops (including staged moves)
	print("Main: Model drop committed for ", unit_id, "/", model_id, " at ", dest_px)
	
	# For staged moves, we want to move the visual token directly without updating GameState
	# Find the existing token in token_layer
	print("DEBUG: Looking for token in token_layer")
	if token_layer:
		print("DEBUG: Token layer found, searching for token with unit_id: ", unit_id, " and model_id: ", model_id)
		for child in token_layer.get_children():
			print("DEBUG: Child: ", child.name, ", has unit_id meta: ", child.has_meta("unit_id"), ", has model_id meta: ", child.has_meta("model_id"))
			if child.has_meta("unit_id"):
				print("DEBUG: Child unit_id: ", child.get_meta("unit_id"))
			if child.has_meta("model_id"):
				print("DEBUG: Child model_id: ", child.get_meta("model_id"))
			
			if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id and child.has_meta("model_id") and child.get_meta("model_id") == model_id:
				print("Moving token visual to ", dest_px)
				child.position = dest_px
				return
	else:
		print("DEBUG: token_layer not found!")
	
	print("Could not find token to move, falling back to full recreation")
	_update_model_visual(unit_id, model_id, [dest_px.x, dest_px.y])

func _clear_right_panel_phase_ui() -> void:
	"""Completely clear all phase-specific UI from right panel"""
	var container = get_node_or_null("HUD_Right/VBoxContainer")
	if not container:
		print("WARNING: Right panel VBoxContainer not found")
		return
	
	# List of known phase-specific UI elements to remove
	var phase_ui_patterns = [
		# Movement phase sections
		"Section1_UnitList", "Section2_UnitDetails", 
		"Section3_ModeSelection", "Section4_Actions",
		"MovementActions", "MovementPanel",
		
		# Shooting phase elements
		"ShootingPanel", "ShootingScrollContainer",
		"ShootingControls", "WeaponTree", "TargetBasket",
		
		# Charge phase elements
		"ChargePanel", "ChargeScrollContainer",
		"ChargeActions", "ChargeStatus",
		
		# Fight phase elements
		"FightPanel", "FightScrollContainer",
		"FightSequence", "FightActions",
		
		# Generic phase elements
		"PhasePanel", "PhaseControls", "PhaseActions"
	]
	
	# Remove all matching elements
	for pattern in phase_ui_patterns:
		var node = container.get_node_or_null(pattern)
		if node and is_instance_valid(node):
			print("Main: Removing phase UI element: ", pattern)
			container.remove_child(node)
			node.queue_free()
	
	# Also remove any unknown dynamic children (defensive)
	var children_to_check = container.get_children()
	for child in children_to_check:
		# Keep only persistent UI elements
		if child.name in ["UnitListPanel", "UnitCard"]:
			# These might be shown/hidden based on phase
			continue
		# Remove if it looks like phase-specific UI
		if "Section" in child.name or "Panel" in child.name or "Actions" in child.name:
			print("Main: Removing unrecognized phase UI: ", child.name)
			container.remove_child(child)
			child.queue_free()

func _debug_check_right_panel() -> void:
	"""Debug method to validate right panel state"""
	var container = get_node_or_null("HUD_Right/VBoxContainer")
	if not container:
		print("DEBUG: No VBoxContainer found")
		return
	
	print("DEBUG: Right panel children:")
	for child in container.get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
	
	# Check for wrong phase UI
	var current_phase_name = GameStateData.Phase.keys()[current_phase]
	print("DEBUG: Current phase: ", current_phase_name)
	
	# Flag any mismatched UI
	if current_phase != GameStateData.Phase.MOVEMENT:
		for section in ["Section1_UnitList", "Section2_UnitDetails", 
					   "Section3_ModeSelection", "Section4_Actions"]:
			if container.get_node_or_null(section):
				print("ERROR: Movement UI found in wrong phase!")
	
	if current_phase != GameStateData.Phase.SHOOTING:
		if container.get_node_or_null("ShootingPanel"):
			print("ERROR: Shooting UI found in wrong phase!")

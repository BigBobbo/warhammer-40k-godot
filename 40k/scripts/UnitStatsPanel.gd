extends PanelContainer

# Header references
@onready var toggle_button: Button = $VBox/Header/ToggleButton

# Main content container
@onready var main_content: HBoxContainer = $VBox/MainContent

# Player section references
@onready var player_units_list: ItemList = $VBox/MainContent/PlayerSection/PlayerUnitsPanel/VBoxContainer/PlayerUnitsList
@onready var player_stats_content: VBoxContainer = $VBox/MainContent/PlayerSection/PlayerStatsPanel/ScrollContainer/PlayerStatsContent
@onready var player_keywords_label: Label = $VBox/MainContent/PlayerSection/PlayerStatsPanel/ScrollContainer/PlayerStatsContent/PlayerKeywordsContainer/PlayerKeywordsLabel
@onready var player_stats_label: Label = $VBox/MainContent/PlayerSection/PlayerStatsPanel/ScrollContainer/PlayerStatsContent/PlayerStatsContainer/PlayerStatsLabel
@onready var player_weapons_container: VBoxContainer = $VBox/MainContent/PlayerSection/PlayerStatsPanel/ScrollContainer/PlayerStatsContent/PlayerWeaponsContainer
@onready var player_abilities_container: VBoxContainer = $VBox/MainContent/PlayerSection/PlayerStatsPanel/ScrollContainer/PlayerStatsContent/PlayerAbilitiesContainer
@onready var player_composition_container: VBoxContainer = $VBox/MainContent/PlayerSection/PlayerStatsPanel/ScrollContainer/PlayerStatsContent/PlayerCompositionContainer

# Enemy section references
@onready var enemy_units_list: ItemList = $VBox/MainContent/EnemySection/EnemyUnitsPanel/VBoxContainer/EnemyUnitsList
@onready var enemy_stats_content: VBoxContainer = $VBox/MainContent/EnemySection/EnemyStatsPanel/ScrollContainer/EnemyStatsContent
@onready var enemy_keywords_label: Label = $VBox/MainContent/EnemySection/EnemyStatsPanel/ScrollContainer/EnemyStatsContent/EnemyKeywordsContainer/EnemyKeywordsLabel
@onready var enemy_stats_label: Label = $VBox/MainContent/EnemySection/EnemyStatsPanel/ScrollContainer/EnemyStatsContent/EnemyStatsContainer/EnemyStatsLabel
@onready var enemy_weapons_container: VBoxContainer = $VBox/MainContent/EnemySection/EnemyStatsPanel/ScrollContainer/EnemyStatsContent/EnemyWeaponsContainer
@onready var enemy_abilities_container: VBoxContainer = $VBox/MainContent/EnemySection/EnemyStatsPanel/ScrollContainer/EnemyStatsContent/EnemyAbilitiesContainer
@onready var enemy_composition_container: VBoxContainer = $VBox/MainContent/EnemySection/EnemyStatsPanel/ScrollContainer/EnemyStatsContent/EnemyCompositionContainer

# Panel state
var is_collapsed: bool = true
var selected_player_unit: Dictionary = {}
var selected_enemy_unit: Dictionary = {}
var current_phase: String = ""
var tween: Tween

# Signals
signal unit_selected(unit_id: String, is_enemy: bool)

func _ready() -> void:
	print("UnitStatsPanel: _ready() called with 4-section layout")
	
	# Connect the toggle button
	if toggle_button:
		toggle_button.pressed.connect(_on_toggle_pressed)
		toggle_button.add_theme_font_size_override("font_size", 14)
		print("UnitStatsPanel: Toggle button connected")
	
	# Connect unit list selections
	if player_units_list:
		player_units_list.item_selected.connect(_on_player_unit_selected)
		print("UnitStatsPanel: Player units list connected")
	
	if enemy_units_list:
		enemy_units_list.item_selected.connect(_on_enemy_unit_selected)
		print("UnitStatsPanel: Enemy units list connected")
	
	# Start collapsed by default
	is_collapsed = true
	set_collapsed(true)
	
	# Update panel labels for player/enemy distinction
	_update_section_labels()

func _on_toggle_pressed() -> void:
	set_collapsed(!is_collapsed)

func set_collapsed(collapsed: bool) -> void:
	is_collapsed = collapsed
	print("UnitStatsPanel: Setting collapsed to ", collapsed)
	
	if main_content:
		main_content.visible = !collapsed
		print("UnitStatsPanel: Main content visible = ", !collapsed)
	
	if toggle_button:
		toggle_button.text = "▼ Unit Stats" if collapsed else "▲ Unit Stats"
		print("UnitStatsPanel: Toggle button text = ", toggle_button.text)
	
	# Animate panel height
	if tween:
		tween.kill()
	
	tween = create_tween()
	var target_height = 40 if collapsed else 300
	tween.tween_property(self, "custom_minimum_size:y", target_height, 0.3)
	
	# Also update the offset to expand upward
	var target_offset = -40 if collapsed else -300
	tween.parallel().tween_property(self, "offset_top", target_offset, 0.3)
	
	print("UnitStatsPanel: Target height = ", target_height, ", Target offset = ", target_offset)

func populate_unit_lists(phase: String) -> void:
	current_phase = phase
	print("UnitStatsPanel: Populating unit lists for phase: ", phase)
	
	var active_player = GameState.get_active_player()
	var enemy_player = 3 - active_player
	
	# Update section labels with player info
	_update_section_labels()
	
	# Populate player units
	_populate_list(player_units_list, active_player, phase, false)
	
	# Populate enemy units
	_populate_list(enemy_units_list, enemy_player, phase, true)

func _populate_list(list: ItemList, player: int, phase: String, is_enemy: bool) -> void:
	if not list:
		print("UnitStatsPanel: Warning - list is null for player ", player)
		return
	
	list.clear()
	
	# Get units based on phase and player
	var units = {}
	
	match phase:
		GameStateData.Phase.DEPLOYMENT:
			# Show undeployed units during deployment
			if not is_enemy:  # Only show undeployed units for active player
				var undeployed = GameState.get_undeployed_units_for_player(player)
				for unit_id in undeployed:
					units[unit_id] = GameState.get_unit(unit_id)
			else:
				# Enemy units are all visible even during deployment
				units = GameState.get_units_for_player(player)
		
		GameStateData.Phase.MOVEMENT:
			# Show deployed units during movement
			var all_units = GameState.get_units_for_player(player)
			for unit_id in all_units:
				var unit = all_units[unit_id]
				var unit_status = unit.get("status", 0)
				if unit_status >= GameStateData.UnitStatus.DEPLOYED:
					units[unit_id] = unit
		
		_:
			# Default: show all units
			units = GameState.get_units_for_player(player)
	
	# Add units to list
	for unit_id in units:
		var unit = units[unit_id]
		var display_text = _get_unit_display_text(unit, phase)
		var idx = list.add_item(display_text)
		list.set_item_metadata(idx, unit_id)
	
	var list_type = "player" if not is_enemy else "enemy"
	print("UnitStatsPanel: Populated ", units.size(), " units for ", list_type, " (player ", player, ")")

func _get_unit_display_text(unit: Dictionary, phase: String) -> String:
	var text = unit.get("meta", {}).get("name", unit.get("id", "Unknown"))
	var model_count = _count_active_models(unit)
	text += " (" + str(model_count) + " models)"
	
	# Add phase-specific status flags
	if phase == "MOVEMENT":
		var flags = unit.get("flags", {})
		if flags.get("moved", false):
			text += " [MOVED]"
		if flags.get("advanced", false):
			text += " [ADV]"
		if flags.get("fell_back", false):
			text += " [FELL BACK]"
	
	return text

func _count_active_models(unit: Dictionary) -> int:
	var count = 0
	var models = unit.get("models", [])
	for model in models:
		if model.get("alive", true):
			count += 1
	return count

func _on_player_unit_selected(index: int) -> void:
	if not player_units_list:
		return
	
	var unit_id = player_units_list.get_item_metadata(index)
	var unit_data = GameState.get_unit(unit_id)
	
	if unit_data:
		selected_player_unit = unit_data
		display_unit_stats(unit_data, player_stats_content, player_keywords_label, 
						   player_stats_label, player_weapons_container, 
						   player_abilities_container, player_composition_container)
		
		# Auto-expand if collapsed
		if is_collapsed:
			set_collapsed(false)
		
		# Emit signal for Main.gd integration
		emit_signal("unit_selected", unit_id, false)
		
		print("UnitStatsPanel: Player unit selected - ", unit_id)

func _on_enemy_unit_selected(index: int) -> void:
	if not enemy_units_list:
		return
	
	var unit_id = enemy_units_list.get_item_metadata(index)
	var unit_data = GameState.get_unit(unit_id)
	
	if unit_data:
		selected_enemy_unit = unit_data
		display_unit_stats(unit_data, enemy_stats_content, enemy_keywords_label,
						   enemy_stats_label, enemy_weapons_container,
						   enemy_abilities_container, enemy_composition_container)
		
		# Auto-expand if collapsed
		if is_collapsed:
			set_collapsed(false)
		
		# Emit signal for Main.gd integration
		emit_signal("unit_selected", unit_id, true)
		
		print("UnitStatsPanel: Enemy unit selected - ", unit_id)

func display_unit_stats(unit_data: Dictionary, content_container: VBoxContainer,
						keywords_label: Label, stats_label: Label,
						weapons_container: VBoxContainer, abilities_container: VBoxContainer,
						composition_container: VBoxContainer) -> void:
	
	if not unit_data.has("meta"):
		print("Warning: Unit data missing 'meta' field")
		return
	
	var meta = unit_data["meta"]
	
	# Display keywords
	if keywords_label and meta.has("keywords"):
		keywords_label.text = ", ".join(meta["keywords"])
	
	# Display stats
	if stats_label and meta.has("stats"):
		var stats = meta["stats"]
		stats_label.text = "M%d\" | T%d | Sv%d+ | W%d | Ld%d+ | OC%d" % [
			stats.get("move", 0),
			stats.get("toughness", 0),
			stats.get("save", 0),
			stats.get("wounds", 0),
			stats.get("leadership", 0),
			stats.get("objective_control", 0)
		]
	
	# Display weapons
	_create_weapons_tables(unit_data, weapons_container)
	
	# Display abilities
	_create_abilities_list(unit_data, abilities_container)
	
	# Display composition
	_create_composition_list(unit_data, composition_container)

# Backward compatibility for Main.gd
func display_unit(unit_data: Dictionary) -> void:
	# For backward compatibility, display in player section
	display_unit_stats(unit_data, player_stats_content, player_keywords_label,
					   player_stats_label, player_weapons_container,
					   player_abilities_container, player_composition_container)
	
	# Auto-expand
	if is_collapsed:
		set_collapsed(false)

func _create_weapons_tables(unit_data: Dictionary, weapons_container: VBoxContainer) -> void:
	# Clear existing
	for child in weapons_container.get_children():
		child.queue_free()
	
	if not unit_data.has("meta") or not unit_data["meta"].has("weapons"):
		return
	
	var weapons = unit_data["meta"]["weapons"]
	if weapons.is_empty():
		return
	
	# Separate weapons by type
	var ranged_weapons = []
	var melee_weapons = []
	
	for weapon in weapons:
		if weapon.get("type", "") == "Ranged":
			ranged_weapons.append(weapon)
		elif weapon.get("type", "") == "Melee":
			melee_weapons.append(weapon)
	
	# Create ranged weapons table
	if not ranged_weapons.is_empty():
		var ranged_label = Label.new()
		ranged_label.text = "RANGED WEAPONS"
		ranged_label.add_theme_font_size_override("font_size", 14)
		weapons_container.add_child(ranged_label)
		
		var ranged_grid = GridContainer.new()
		ranged_grid.columns = 7
		ranged_grid.add_theme_constant_override("h_separation", 10)
		ranged_grid.add_theme_constant_override("v_separation", 5)
		
		# Headers
		for header in ["Range", "A", "BS", "S", "AP", "D", "Abilities"]:
			var label = Label.new()
			label.text = header
			label.add_theme_font_size_override("font_size", 12)
			label.modulate = Color(0.8, 0.8, 1.0)  # Light blue tint
			ranged_grid.add_child(label)
		
		# Data rows
		for weapon in ranged_weapons:
			_add_weapon_row(ranged_grid, weapon, "ranged")
		
		weapons_container.add_child(ranged_grid)
		
		# Add spacing
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		weapons_container.add_child(spacer)
	
	# Create melee weapons table
	if not melee_weapons.is_empty():
		var melee_label = Label.new()
		melee_label.text = "MELEE WEAPONS"
		melee_label.add_theme_font_size_override("font_size", 14)
		weapons_container.add_child(melee_label)
		
		var melee_grid = GridContainer.new()
		melee_grid.columns = 7
		melee_grid.add_theme_constant_override("h_separation", 10)
		melee_grid.add_theme_constant_override("v_separation", 5)
		
		# Headers
		for header in ["Range", "A", "WS", "S", "AP", "D", "Abilities"]:
			var label = Label.new()
			label.text = header
			label.add_theme_font_size_override("font_size", 12)
			label.modulate = Color(1.0, 0.8, 0.8)  # Light red/pink tint
			melee_grid.add_child(label)
		
		# Data rows
		for weapon in melee_weapons:
			_add_weapon_row(melee_grid, weapon, "melee")
		
		weapons_container.add_child(melee_grid)

func _add_weapon_row(grid: GridContainer, weapon: Dictionary, type: String) -> void:
	var cells = []
	
	if type == "ranged":
		cells = [
			str(weapon.get("range", "")) + "\"" if weapon.get("range", "") != "" else "",
			str(weapon.get("attacks", "")),
			str(weapon.get("ballistic_skill", "")) + "+" if weapon.get("ballistic_skill", "") != "" else "",
			str(weapon.get("strength", "")),
			str(weapon.get("ap", "")),
			str(weapon.get("damage", "")),
			weapon.get("special_rules", "")
		]
	else:  # melee
		cells = [
			"Melee",
			str(weapon.get("attacks", "")),
			str(weapon.get("weapon_skill", "")) + "+" if weapon.get("weapon_skill", "") != "" else "",
			str(weapon.get("strength", "")),
			str(weapon.get("ap", "")),
			str(weapon.get("damage", "")),
			weapon.get("special_rules", "")
		]
	
	for cell_text in cells:
		var label = Label.new()
		label.text = str(cell_text)
		label.add_theme_font_size_override("font_size", 11)
		grid.add_child(label)

func _create_abilities_list(unit_data: Dictionary, abilities_container: VBoxContainer) -> void:
	# Clear existing
	for child in abilities_container.get_children():
		child.queue_free()
	
	if not unit_data.has("meta") or not unit_data["meta"].has("abilities"):
		return
	
	var abilities = unit_data["meta"]["abilities"]
	if abilities.is_empty():
		return
	
	var abilities_label = Label.new()
	abilities_label.text = "ABILITIES"
	abilities_label.add_theme_font_size_override("font_size", 14)
	abilities_container.add_child(abilities_label)
	
	for ability in abilities:
		var ability_container = VBoxContainer.new()
		
		var name_label = Label.new()
		name_label.text = "• " + ability.get("name", "Unknown")
		if ability.has("type"):
			name_label.text += " (" + ability.get("type", "") + ")"
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.modulate = Color(1.0, 1.0, 0.8)  # Slight yellow tint
		ability_container.add_child(name_label)
		
		if ability.has("description"):
			var desc_label = Label.new()
			desc_label.text = "  " + ability.get("description", "")
			desc_label.add_theme_font_size_override("font_size", 10)
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ability_container.add_child(desc_label)
		
		abilities_container.add_child(ability_container)

func _create_composition_list(unit_data: Dictionary, composition_container: VBoxContainer) -> void:
	# Clear existing
	for child in composition_container.get_children():
		child.queue_free()
	
	if not unit_data.has("meta") or not unit_data["meta"].has("unit_composition"):
		return
	
	var composition = unit_data["meta"]["unit_composition"]
	if composition.is_empty():
		return
	
	var comp_label = Label.new()
	comp_label.text = "UNIT COMPOSITION"
	comp_label.add_theme_font_size_override("font_size", 14)
	composition_container.add_child(comp_label)
	
	for comp_item in composition:
		var item_label = Label.new()
		item_label.text = "• " + comp_item.get("description", "Unknown")
		item_label.add_theme_font_size_override("font_size", 11)
		composition_container.add_child(item_label)
	
	# Also show model count from models array if available
	if unit_data.has("models"):
		var models = unit_data["models"]
		var alive_count = 0
		var total_count = models.size()
		
		for model in models:
			if model.get("alive", true):
				alive_count += 1
		
		var model_status = Label.new()
		model_status.text = "Models: %d/%d alive" % [alive_count, total_count]
		model_status.add_theme_font_size_override("font_size", 11)
		model_status.modulate = Color(0.8, 1.0, 0.8) if alive_count == total_count else Color(1.0, 0.8, 0.8)
		composition_container.add_child(model_status)

func _update_section_labels() -> void:
	var active_player = GameState.get_active_player()
	var enemy_player = 3 - active_player
	
	# Get faction names if available
	var player_faction = GameState.get_faction_name(active_player)
	var enemy_faction = GameState.get_faction_name(enemy_player)
	
	# Update the labels in the panels
	var player_label = get_node_or_null("VBox/MainContent/PlayerSection/PlayerUnitsPanel/VBoxContainer/Label")
	if player_label:
		player_label.text = "Player %d Units (%s)" % [active_player, player_faction]
	
	var enemy_label = get_node_or_null("VBox/MainContent/EnemySection/EnemyUnitsPanel/VBoxContainer/Label")
	if enemy_label:
		enemy_label.text = "Player %d Units (%s)" % [enemy_player, enemy_faction]

func _exit_tree() -> void:
	# Disconnect signals to prevent errors
	if player_units_list and player_units_list.item_selected.is_connected(_on_player_unit_selected):
		player_units_list.item_selected.disconnect(_on_player_unit_selected)
	
	if enemy_units_list and enemy_units_list.item_selected.is_connected(_on_enemy_unit_selected):
		enemy_units_list.item_selected.disconnect(_on_enemy_unit_selected)
	
	if toggle_button and toggle_button.pressed.is_connected(_on_toggle_pressed):
		toggle_button.pressed.disconnect(_on_toggle_pressed)
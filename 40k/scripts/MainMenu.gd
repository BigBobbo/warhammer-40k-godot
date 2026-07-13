extends Control

const FixedMissionSelectionDialogScript = preload("res://dialogs/FixedMissionSelectionDialog.gd")
const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

# MainMenu - Entry point for the game, allows configuration of mission and armies

@onready var terrain_dropdown: OptionButton = $ScrollContainer/MenuContainer/MissionSection/TerrainContainer/TerrainDropdown
@onready var mission_dropdown: OptionButton = $ScrollContainer/MenuContainer/MissionSection/MissionContainer/MissionDropdown
@onready var deployment_dropdown: OptionButton = $ScrollContainer/MenuContainer/MissionSection/DeploymentContainer/DeploymentDropdown
@onready var player1_type_dropdown: OptionButton = $ScrollContainer/MenuContainer/ArmySection/Player1TypeContainer/Player1TypeDropdown
@onready var player1_dropdown: OptionButton = $ScrollContainer/MenuContainer/ArmySection/Player1Container/Player1Dropdown
@onready var player2_type_dropdown: OptionButton = $ScrollContainer/MenuContainer/ArmySection/Player2TypeContainer/Player2TypeDropdown
@onready var player2_dropdown: OptionButton = $ScrollContainer/MenuContainer/ArmySection/Player2Container/Player2Dropdown
# T7-40: AI difficulty dropdowns (created dynamically, shown only when player type is AI)
var player1_difficulty_container: HBoxContainer = null
var player1_difficulty_dropdown: OptionButton = null
var player2_difficulty_container: HBoxContainer = null
var player2_difficulty_dropdown: OptionButton = null
# T7-36: AI speed dropdown (shown when any player is AI)
var ai_speed_container: HBoxContainer = null
var ai_speed_dropdown: OptionButton = null
# P2-85: Secondary mission mode selection (Fixed vs Tactical)
var secondary_mode_container: VBoxContainer = null
var p1_secondary_mode_dropdown: OptionButton = null
var p2_secondary_mode_dropdown: OptionButton = null
var p1_select_fixed_button: Button = null
var p2_select_fixed_button: Button = null
var _p1_fixed_mission_ids: Array = []
var _p2_fixed_mission_ids: Array = []
# 11e GDM 2026: Force Disposition selection (drives the primary mission pairing)
var disposition_container: VBoxContainer = null
var p1_disposition_dropdown: OptionButton = null
var p2_disposition_dropdown: OptionButton = null
# 11e: at 11th edition the primary mission and deployment zone are DERIVED from
# the Force Disposition matchup (+ chosen terrain variant), not player choices.
# Their dropdowns are hidden and replaced with read-only value labels that show
# exactly what will be used. Populated in _setup_derived_mission_displays().
var mission_value_label: Label = null
var deployment_value_label: Label = null
var _derived_displays_active: bool = false
@onready var start_button: Button = $ScrollContainer/MenuContainer/ButtonSection/StartButton
@onready var multiplayer_button: Button = $ScrollContainer/MenuContainer/ButtonSection/MultiplayerButton
@onready var load_button: Button = $ScrollContainer/MenuContainer/ButtonSection/LoadButton
@onready var replay_button: Button = $ScrollContainer/MenuContainer/ButtonSection/ReplayButton
@onready var settings_button: Button = $ScrollContainer/MenuContainer/ButtonSection/SettingsButton
@onready var quit_button: Button = $ScrollContainer/MenuContainer/ButtonSection/QuitButton

# Configuration options
# The legacy hand-made layouts (Chapter Approved 1-8, parse tests) were
# removed — the dropdown is populated from the converted official 11e
# layouts: the current Force-Disposition matchup's variants, falling back to
# the full official list (see _refresh_matchup_terrain_options).
var terrain_options = []

var mission_options = [
	{"id": "take_and_hold", "name": "Take and Hold"},
	{"id": "supply_drop", "name": "Supply Drop"},
	{"id": "purge_the_foe", "name": "Purge the Foe"},
	{"id": "linchpin", "name": "Linchpin"},
	{"id": "sites_of_power", "name": "Sites of Power"},
	{"id": "scorched_earth", "name": "Scorched Earth"},
	{"id": "the_ritual", "name": "The Ritual"},
	{"id": "terraform", "name": "Terraform"},
	{"id": "hidden_supplies", "name": "Hidden Supplies"},
]

var deployment_options = [
	{"id": "hammer_anvil", "name": "Hammer and Anvil"},
	{"id": "dawn_of_war", "name": "Dawn of War"},
	{"id": "search_and_destroy", "name": "Search and Destroy"},
	{"id": "sweeping_engagement", "name": "Sweeping Engagement"},
	{"id": "crucible_of_battle", "name": "Crucible of Battle"},
	{"id": "tipping_point", "name": "Tipping Point"}
]

# D5 (docs/40KDC_TERRAIN_MIGRATION_SPEC.md): the base terrain list above is
# fixed; the dropdown is rebuilt as base + the official 11e layouts for the
# currently selected Force-Disposition matchup (3 variants per pairing).
var _base_terrain_options: Array = []
var _matchup_layouts: Array = []

# Army options - dynamically populated from ArmyListManager
var army_options = []
# Army sort mode: "alphabetical" or "newest_first"
var army_sort_mode: String = "alphabetical"
var army_sort_container: HBoxContainer = null
var army_sort_dropdown: OptionButton = null

var save_load_dialog: PanelContainer

# SAVE-20: Save/load progress indicator
var _save_load_progress_overlay: PanelContainer = null
var _save_load_progress_label: Label = null
var _save_load_progress_pulse_tween: Tween = null

# Set when the Army Builder button opens the browser (windowed scenarios
# assert on it — the shell_open side effect itself is unobservable in-tree).
var last_army_builder_url: String = ""

# Cloud army loading state
var _waiting_for_cloud_armies: bool = false
var _cloud_army_fetch_pending: bool = false
var _pending_game_config: Dictionary = {}
var _cloud_fetch_count: int = 0  # How many cloud armies still need fetching

func _ready() -> void:
	print("MainMenu: Initializing main menu")

	# Ensure network state is clean when returning to menu (e.g. after leaving a multiplayer game)
	if NetworkManager.is_networked():
		print("MainMenu: Cleaning up stale network state")
		NetworkManager.disconnect_network()

	_apply_theme()
	_base_terrain_options = terrain_options.duplicate()
	_setup_dropdowns()
	_connect_signals()
	_setup_save_load_dialog()

	# Set defaults
	mission_dropdown.selected = 0
	deployment_dropdown.selected = _find_option_index(deployment_options, "search_and_destroy")

	# D5: list the default matchup's official 11e layouts in the terrain
	# dropdown and default to the first of them (the base list is empty now
	# that the legacy layouts are gone).
	_refresh_matchup_terrain_options(false)

	# Set default army selections based on available armies
	_set_default_army_selections()

	# Fetch cloud armies asynchronously
	_load_cloud_armies()

	# Apply theme to dynamically created dropdowns
	_apply_theme_to_dynamic_elements()

	# 40kdc dataset licensing credit (see data/40kdc/ATTRIBUTION.md)
	_create_data_attribution_credit()

	# Version badge + "What's New" summary (helps tell which build is running)
	_create_version_display()

	# M0 controller foundations: the menu must be drivable without a mouse —
	# something has to own focus for D-pad/stick navigation to work at all,
	# and the scroll view has to follow the focused control.
	$ScrollContainer.follow_focus = true
	start_button.grab_focus()

	print("MainMenu: Ready with default selections")

func _apply_theme() -> void:
	# Background: warm near-black to match WhiteDwarf theme
	var bg = $Background as ColorRect
	bg.color = WhiteDwarfThemeData.WH_BLACK

	# Title label: gold, large and prominent
	var title_label = $ScrollContainer/MenuContainer/TitleLabel as Label
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	if FactionPalettes:
		title_label.add_theme_font_override("font", FactionPalettes.FONT_CASLON)

	# Section headers
	var mission_label = $ScrollContainer/MenuContainer/MissionSection/MissionLabel as Label
	mission_label.add_theme_font_size_override("font_size", 16)
	mission_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)

	var army_label = $ScrollContainer/MenuContainer/ArmySection/ArmyLabel as Label
	army_label.add_theme_font_size_override("font_size", 16)
	army_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)

	# Separators: gold
	for sep_name in ["HSeparator", "HSeparator2", "HSeparator3"]:
		var sep = $ScrollContainer/MenuContainer.get_node(sep_name) as HSeparator
		sep.add_theme_color_override("separator", WhiteDwarfThemeData.WH_GOLD)

	# Field labels: parchment
	for label_node in [
		$ScrollContainer/MenuContainer/MissionSection/TerrainContainer/TerrainLabel,
		$ScrollContainer/MenuContainer/MissionSection/MissionContainer/MissionLabel,
		$ScrollContainer/MenuContainer/MissionSection/DeploymentContainer/DeploymentLabel,
		$ScrollContainer/MenuContainer/ArmySection/Player1TypeContainer/Player1TypeLabel,
		$ScrollContainer/MenuContainer/ArmySection/Player1Container/Player1Label,
		$ScrollContainer/MenuContainer/ArmySection/Player2TypeContainer/Player2TypeLabel,
		$ScrollContainer/MenuContainer/ArmySection/Player2Container/Player2Label,
	]:
		(label_node as Label).add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)

	# Scene-defined dropdowns
	for dropdown in [terrain_dropdown, mission_dropdown, deployment_dropdown,
			player1_type_dropdown, player1_dropdown, player2_type_dropdown, player2_dropdown]:
		WhiteDwarfThemeData.apply_to_button(dropdown)

	# Buttons — Start Game is primary, rest are secondary
	WhiteDwarfThemeData.apply_primary_button(start_button)
	for btn in [multiplayer_button, load_button, replay_button, settings_button, quit_button]:
		WhiteDwarfThemeData.apply_secondary_button(btn)

func _create_data_attribution_credit() -> void:
	"""License requirement (data/40kdc/ATTRIBUTION.md): publicly shipped builds
	must display a visible 'Powered by 40kdc-data' credit with a link to
	40kdc.alpacasoft.dev. Small, unobtrusive footer pinned to the bottom of
	the menu; clicking it opens the dataset site."""
	var credit := LinkButton.new()
	credit.name = "DataAttributionCredit"
	credit.text = "Powered by 40kdc-data — 40kdc.alpacasoft.dev"
	credit.uri = "https://40kdc.alpacasoft.dev"
	credit.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	credit.tooltip_text = "Dataset: @alpaca-software/40kdc-data (CC BY 4.0)"
	credit.focus_mode = Control.FOCUS_NONE
	credit.add_theme_font_size_override("font_size", 11)
	credit.add_theme_color_override("font_color", Color(WhiteDwarfThemeData.WH_PARCHMENT, 0.55))
	credit.add_theme_color_override("font_hover_color", WhiteDwarfThemeData.WH_GOLD)
	credit.add_theme_color_override("font_pressed_color", WhiteDwarfThemeData.WH_GOLD)
	# Bottom-center of the screen, 6 px above the edge
	credit.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 6)
	credit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(credit)
	print("MainMenu: 40kdc data attribution credit added")

func _create_version_display() -> void:
	"""Show the game version + a summary of the most recent changes at the bottom
	of the menu. Data comes from res://data/version_history.json via VersionInfo
	so it can be told at a glance which build is running (e.g. itch.io vs GitHub)."""
	var menu_container := $ScrollContainer/MenuContainer as VBoxContainer
	if menu_container == null:
		return

	# --- Compact version badge at the bottom of the menu ---
	var badge := Label.new()
	badge.name = "VersionBadge"
	badge.text = VersionInfo.get_version_badge()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	# add_child appends to the end of the VBox. Since _create_version_display()
	# is the last step of _ready(), the version info lands below the
	# Start/Load/Quit button section, at the very bottom of the menu.
	menu_container.add_child(badge)

	# --- "What's New" panel listing the latest release summary + changes ---
	var changes := VersionInfo.get_latest_changes()
	var summary := VersionInfo.get_latest_summary()
	if changes.is_empty() and summary.is_empty():
		return

	var panel := PanelContainer.new()
	panel.name = "WhatsNewPanel"
	WhiteDwarfThemeData.apply_to_panel(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var header := Label.new()
	header.name = "WhatsNewHeader"
	header.text = "What's New — v%s (%s)" % [VersionInfo.get_version(), VersionInfo.get_version_date()]
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(header)

	if not summary.is_empty():
		var summary_label := Label.new()
		summary_label.name = "WhatsNewSummary"
		summary_label.text = summary
		summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary_label.custom_minimum_size = Vector2(560, 0)
		summary_label.add_theme_font_size_override("font_size", 12)
		summary_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
		vbox.add_child(summary_label)

	for change in changes:
		var change_label := Label.new()
		change_label.text = "•  %s" % str(change)
		change_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		change_label.custom_minimum_size = Vector2(560, 0)
		change_label.add_theme_font_size_override("font_size", 12)
		change_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
		vbox.add_child(change_label)

	# Appended after the badge, so the "What's New" panel is the very last
	# element in the menu, directly below the version badge.
	menu_container.add_child(panel)

	print("MainMenu: Version display added at bottom (%s, %d changes)" % [VersionInfo.get_version(), changes.size()])

func _apply_theme_to_dynamic_elements() -> void:
	# Style dynamically created dropdowns and buttons
	for dropdown in [player1_difficulty_dropdown, player2_difficulty_dropdown, ai_speed_dropdown,
			p1_secondary_mode_dropdown, p2_secondary_mode_dropdown, army_sort_dropdown]:
		if dropdown:
			WhiteDwarfThemeData.apply_to_button(dropdown)

	for btn in [p1_select_fixed_button, p2_select_fixed_button]:
		if btn:
			WhiteDwarfThemeData.apply_to_button(btn)

	# Style dynamically created labels
	for container in [player1_difficulty_container, player2_difficulty_container, ai_speed_container, army_sort_container]:
		if container:
			for child in container.get_children():
				if child is Label:
					child.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)

	if secondary_mode_container:
		# Section label
		for child in secondary_mode_container.get_children():
			if child is Label:
				child.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
			elif child is HBoxContainer:
				for grandchild in child.get_children():
					if grandchild is Label:
						grandchild.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)

func _setup_dropdowns() -> void:
	# Populate terrain dropdown
	for option in terrain_options:
		terrain_dropdown.add_item(option.name)

	# Populate mission dropdown
	for option in mission_options:
		mission_dropdown.add_item(option.name)

	# Populate deployment dropdown
	for option in deployment_options:
		deployment_dropdown.add_item(option.name)

	# Populate player type dropdowns (Human / AI)
	player1_type_dropdown.add_item("Human")
	player1_type_dropdown.add_item("AI")
	player1_type_dropdown.selected = 0  # Default: Human
	player2_type_dropdown.add_item("Human")
	player2_type_dropdown.add_item("AI")
	player2_type_dropdown.selected = 1  # Default: AI (most common single-player setup)

	# T7-40: Create AI difficulty dropdowns
	_create_difficulty_dropdowns()

	# T7-36: Create AI speed dropdown
	_create_ai_speed_dropdown()

	# P2-85: Create secondary mission mode selection
	_create_secondary_mission_mode_ui()

	# 11e GDM 2026: Force Disposition selection (primary mission pairing)
	_create_disposition_ui()

	# 11e: replace the derived Primary Mission / Deployment dropdowns with
	# read-only value labels (they follow from the disposition matchup + terrain).
	_setup_derived_mission_displays()

	# Create army sort dropdown
	_create_army_sort_dropdown()

	# Browser army builder link + cloud army refresh
	_create_army_builder_row()

	# Dynamically populate army dropdowns from ArmyListManager
	_load_available_armies()
	_populate_army_dropdowns()

	print("MainMenu: Dropdowns populated with ", army_options.size(), " armies")

func _create_difficulty_dropdowns() -> void:
	"""T7-40: Create AI difficulty dropdown containers and insert them after the player type rows."""
	var army_section = $ScrollContainer/MenuContainer/ArmySection

	# --- Player 1 Difficulty ---
	player1_difficulty_container = HBoxContainer.new()
	player1_difficulty_container.name = "Player1DifficultyContainer"

	var p1_label = Label.new()
	p1_label.text = "P1 AI Difficulty:"
	p1_label.custom_minimum_size = Vector2(150, 0)
	player1_difficulty_container.add_child(p1_label)

	player1_difficulty_dropdown = OptionButton.new()
	player1_difficulty_dropdown.name = "Player1DifficultyDropdown"
	player1_difficulty_dropdown.custom_minimum_size = Vector2(300, 0)
	player1_difficulty_dropdown.add_item("Easy")
	player1_difficulty_dropdown.add_item("Normal")
	player1_difficulty_dropdown.add_item("Hard")
	player1_difficulty_dropdown.add_item("Competitive")
	player1_difficulty_dropdown.selected = 1  # Default: Normal
	player1_difficulty_container.add_child(player1_difficulty_dropdown)

	# Insert after Player1TypeContainer
	var p1_type_idx = _get_child_index(army_section, "Player1TypeContainer")
	army_section.add_child(player1_difficulty_container)
	if p1_type_idx >= 0:
		army_section.move_child(player1_difficulty_container, p1_type_idx + 1)

	# --- Player 2 Difficulty ---
	player2_difficulty_container = HBoxContainer.new()
	player2_difficulty_container.name = "Player2DifficultyContainer"

	var p2_label = Label.new()
	p2_label.text = "P2 AI Difficulty:"
	p2_label.custom_minimum_size = Vector2(150, 0)
	player2_difficulty_container.add_child(p2_label)

	player2_difficulty_dropdown = OptionButton.new()
	player2_difficulty_dropdown.name = "Player2DifficultyDropdown"
	player2_difficulty_dropdown.custom_minimum_size = Vector2(300, 0)
	player2_difficulty_dropdown.add_item("Easy")
	player2_difficulty_dropdown.add_item("Normal")
	player2_difficulty_dropdown.add_item("Hard")
	player2_difficulty_dropdown.add_item("Competitive")
	player2_difficulty_dropdown.selected = 1  # Default: Normal
	player2_difficulty_container.add_child(player2_difficulty_dropdown)

	# Insert after Player2TypeContainer
	var p2_type_idx = _get_child_index(army_section, "Player2TypeContainer")
	army_section.add_child(player2_difficulty_container)
	if p2_type_idx >= 0:
		army_section.move_child(player2_difficulty_container, p2_type_idx + 1)

	# Set initial visibility based on player type
	player1_difficulty_container.visible = (player1_type_dropdown.selected == 1)
	player2_difficulty_container.visible = (player2_type_dropdown.selected == 1)

	# Connect player type changes to toggle difficulty visibility
	player1_type_dropdown.item_selected.connect(_on_player1_type_changed)
	player2_type_dropdown.item_selected.connect(_on_player2_type_changed)

	print("MainMenu: AI difficulty dropdowns created")

func _find_option_index(options: Array, target_id: String) -> int:
	"""Return the index of the option with the given id, or 0 if not found."""
	for i in range(options.size()):
		if options[i].get("id", "") == target_id:
			return i
	return 0

func _get_child_index(parent: Node, child_name: String) -> int:
	"""Get the index of a child node by name."""
	for i in range(parent.get_child_count()):
		if parent.get_child(i).name == child_name:
			return i
	return -1

func _on_player1_type_changed(index: int) -> void:
	"""T7-40: Show/hide P1 difficulty dropdown based on player type."""
	if player1_difficulty_container:
		player1_difficulty_container.visible = (index == 1)  # 1 = AI
		print("MainMenu: Player 1 type changed to %s, difficulty visible: %s" % [
			"AI" if index == 1 else "Human", player1_difficulty_container.visible])
	_update_ai_speed_visibility()

func _on_player2_type_changed(index: int) -> void:
	"""T7-40: Show/hide P2 difficulty dropdown based on player type."""
	if player2_difficulty_container:
		player2_difficulty_container.visible = (index == 1)  # 1 = AI
		print("MainMenu: Player 2 type changed to %s, difficulty visible: %s" % [
			"AI" if index == 1 else "Human", player2_difficulty_container.visible])
	_update_ai_speed_visibility()

func _create_ai_speed_dropdown() -> void:
	"""T7-36: Create an AI speed dropdown in the army section, shown when any player is AI."""
	var army_section = $ScrollContainer/MenuContainer/ArmySection

	ai_speed_container = HBoxContainer.new()
	ai_speed_container.name = "AISpeedContainer"

	var speed_label = Label.new()
	speed_label.text = "AI Speed:"
	speed_label.custom_minimum_size = Vector2(150, 0)
	ai_speed_container.add_child(speed_label)

	ai_speed_dropdown = OptionButton.new()
	ai_speed_dropdown.name = "AISpeedDropdown"
	ai_speed_dropdown.custom_minimum_size = Vector2(300, 0)
	ai_speed_dropdown.add_item("Fast (0ms)")          # Index 0 = AISpeedPreset.FAST
	ai_speed_dropdown.add_item("Normal (200ms)")      # Index 1 = AISpeedPreset.NORMAL
	ai_speed_dropdown.add_item("Slow (500ms)")        # Index 2 = AISpeedPreset.SLOW
	ai_speed_dropdown.add_item("Step-by-step")        # Index 3 = AISpeedPreset.STEP_BY_STEP
	ai_speed_dropdown.selected = 1  # Default: Normal

	ai_speed_container.add_child(ai_speed_dropdown)

	# Insert at the end of ArmySection (after all player containers)
	army_section.add_child(ai_speed_container)

	# Set initial visibility
	_update_ai_speed_visibility()

	print("MainMenu: T7-36 AI speed dropdown created")

func _update_ai_speed_visibility() -> void:
	"""T7-36: Show/hide AI speed dropdown based on whether any player is AI."""
	if ai_speed_container:
		var any_ai = (player1_type_dropdown.selected == 1) or (player2_type_dropdown.selected == 1)
		ai_speed_container.visible = any_ai

func _create_secondary_mission_mode_ui() -> void:
	"""P2-85: Create secondary mission mode selection UI in the mission section."""
	var mission_section = $ScrollContainer/MenuContainer/MissionSection

	secondary_mode_container = VBoxContainer.new()
	secondary_mode_container.name = "SecondaryModeContainer"
	secondary_mode_container.add_theme_constant_override("separation", 6)
	mission_section.add_child(secondary_mode_container)

	# Section label
	var section_label = Label.new()
	section_label.text = "Secondary Missions:"
	section_label.custom_minimum_size = Vector2(150, 0)
	secondary_mode_container.add_child(section_label)

	# Player 1 row
	var p1_row = HBoxContainer.new()
	p1_row.add_theme_constant_override("separation", 8)
	secondary_mode_container.add_child(p1_row)

	var p1_label = Label.new()
	p1_label.text = "Player 1:"
	p1_label.custom_minimum_size = Vector2(80, 0)
	p1_row.add_child(p1_label)

	p1_secondary_mode_dropdown = OptionButton.new()
	p1_secondary_mode_dropdown.name = "P1SecondaryModeDropdown"
	p1_secondary_mode_dropdown.custom_minimum_size = Vector2(120, 0)
	p1_secondary_mode_dropdown.add_item("Tactical")   # Index 0
	p1_secondary_mode_dropdown.add_item("Fixed")       # Index 1
	p1_secondary_mode_dropdown.selected = 0
	p1_secondary_mode_dropdown.item_selected.connect(_on_p1_secondary_mode_changed)
	p1_row.add_child(p1_secondary_mode_dropdown)

	p1_select_fixed_button = Button.new()
	p1_select_fixed_button.text = "Select Missions..."
	p1_select_fixed_button.custom_minimum_size = Vector2(140, 0)
	p1_select_fixed_button.visible = false
	p1_select_fixed_button.pressed.connect(_on_p1_select_fixed_pressed)
	p1_row.add_child(p1_select_fixed_button)

	# Player 2 row
	var p2_row = HBoxContainer.new()
	p2_row.add_theme_constant_override("separation", 8)
	secondary_mode_container.add_child(p2_row)

	var p2_label = Label.new()
	p2_label.text = "Player 2:"
	p2_label.custom_minimum_size = Vector2(80, 0)
	p2_row.add_child(p2_label)

	p2_secondary_mode_dropdown = OptionButton.new()
	p2_secondary_mode_dropdown.name = "P2SecondaryModeDropdown"
	p2_secondary_mode_dropdown.custom_minimum_size = Vector2(120, 0)
	p2_secondary_mode_dropdown.add_item("Tactical")   # Index 0
	p2_secondary_mode_dropdown.add_item("Fixed")       # Index 1
	p2_secondary_mode_dropdown.selected = 0
	p2_secondary_mode_dropdown.item_selected.connect(_on_p2_secondary_mode_changed)
	p2_row.add_child(p2_secondary_mode_dropdown)

	p2_select_fixed_button = Button.new()
	p2_select_fixed_button.text = "Select Missions..."
	p2_select_fixed_button.custom_minimum_size = Vector2(140, 0)
	p2_select_fixed_button.visible = false
	p2_select_fixed_button.pressed.connect(_on_p2_select_fixed_pressed)
	p2_row.add_child(p2_select_fixed_button)

	print("MainMenu: P2-85 Secondary mission mode UI created")

func _create_disposition_ui() -> void:
	"""11e GDM 2026: per-player Force Disposition selection. The primary
	mission each player scores is their disposition paired against the
	opponent's (25-card table in PrimaryMissionData11e). Ignored at 10e."""
	var mission_section = $ScrollContainer/MenuContainer/MissionSection

	disposition_container = VBoxContainer.new()
	disposition_container.name = "DispositionContainer"
	disposition_container.add_theme_constant_override("separation", 6)
	mission_section.add_child(disposition_container)
	# The Force Disposition pairing is what a player actually chooses in 11e —
	# it drives the primary mission, terrain matchup and deployment. Put it at
	# the top of the Mission section (right after the "Mission Settings" header),
	# above the derived values it produces.
	var mission_label_idx = _get_child_index(mission_section, "MissionLabel")
	if mission_label_idx >= 0:
		mission_section.move_child(disposition_container, mission_label_idx + 1)

	var section_label = Label.new()
	section_label.text = "Force Disposition (11th Edition):"
	section_label.custom_minimum_size = Vector2(150, 0)
	disposition_container.add_child(section_label)

	for player in [1, 2]:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		disposition_container.add_child(row)

		var label = Label.new()
		label.text = "Player %d:" % player
		label.custom_minimum_size = Vector2(80, 0)
		row.add_child(label)

		var dropdown = OptionButton.new()
		dropdown.name = "P%dDispositionDropdown" % player
		dropdown.custom_minimum_size = Vector2(180, 0)
		for disp_id in PrimaryMissionData11e.DISPOSITIONS:
			dropdown.add_item(PrimaryMissionData11e.get_disposition_name(disp_id))
		dropdown.selected = 0
		# D5: the disposition pairing selects the official terrain layouts
		dropdown.item_selected.connect(_on_disposition_changed)
		row.add_child(dropdown)

		if player == 1:
			p1_disposition_dropdown = dropdown
		else:
			p2_disposition_dropdown = dropdown

	print("MainMenu: 11e Force Disposition UI created")

func _setup_derived_mission_displays() -> void:
	"""11e: the Primary Mission and Deployment Zone are not player choices —
	they are derived from the Force Disposition matchup and the chosen terrain
	variant. Hide their OptionButtons (kept as data-holders so config building
	is unchanged) and add read-only value labels in their place."""
	# Only official 11e matchup layouts make these values fully derived. If the
	# generated 11e index is missing (unexpected for a player build), leave the
	# original editable dropdowns so the menu still works.
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null or not tm.has_method("get_11e_layout_ids") or tm.get_11e_layout_ids().is_empty():
		print("MainMenu: no 11e layout index — keeping editable Mission/Deployment dropdowns")
		return
	_derived_displays_active = true

	# --- Primary Mission (per-player card from the disposition pairing) ---
	mission_dropdown.visible = false
	mission_value_label = Label.new()
	mission_value_label.name = "MissionValueLabel"
	mission_value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_value_label.custom_minimum_size = Vector2(300, 0)
	mission_value_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	mission_dropdown.get_parent().add_child(mission_value_label)

	# --- Deployment Zone (follows from the selected terrain variant) ---
	deployment_dropdown.visible = false
	deployment_value_label = Label.new()
	deployment_value_label.name = "DeploymentValueLabel"
	deployment_value_label.custom_minimum_size = Vector2(300, 0)
	deployment_value_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	deployment_dropdown.get_parent().add_child(deployment_value_label)

	print("MainMenu: 11e derived Mission/Deployment read-only displays created")

func _refresh_derived_mission_display() -> void:
	"""Update the read-only Primary Mission / Deployment labels to reflect the
	current Force Dispositions and the selected terrain variant's deployment."""
	if not _derived_displays_active:
		return

	if mission_value_label:
		var p1_disp = _get_selected_disposition(p1_disposition_dropdown)
		var p2_disp = _get_selected_disposition(p2_disposition_dropdown)
		var p1_card = _primary_card_name_for_player(p1_disp, p2_disp)
		var p2_card = _primary_card_name_for_player(p2_disp, p1_disp)
		# Each player scores their OWN disposition-vs-opponent card, so the two
		# players usually play different primaries — show both.
		if p1_card == p2_card:
			mission_value_label.text = p1_card
		else:
			mission_value_label.text = "Player 1: %s\nPlayer 2: %s" % [p1_card, p2_card]

	if deployment_value_label:
		var dep_name := "—"
		if deployment_dropdown.selected >= 0 and deployment_dropdown.selected < deployment_options.size():
			dep_name = str(deployment_options[deployment_dropdown.selected].name)
		deployment_value_label.text = dep_name

func _primary_card_name_for_player(own_disposition: String, opponent_disposition: String) -> String:
	"""Name of the primary mission card a player scores (own deck vs opponent)."""
	var card = PrimaryMissionData11e.get_card(own_disposition, opponent_disposition)
	return str(card.get("name", "—"))

## D5: rebuild the terrain dropdown as base layouts + the official 11e
## layouts of the currently selected Force-Disposition matchup.
## select_official=true (player changed a disposition) selects the matchup's
## variant 1 and snaps the deployment dropdown to its official pattern;
## select_official=false (boot) preserves the current selection so the
## first-run defaults and manual overrides stay intact.
func _refresh_matchup_terrain_options(select_official: bool) -> void:
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null or not tm.has_method("get_layouts_for_matchup"):
		return
	var p1_disp = _get_selected_disposition(p1_disposition_dropdown)
	var p2_disp = _get_selected_disposition(p2_disposition_dropdown)
	_matchup_layouts = tm.get_layouts_for_matchup(p1_disp, p2_disp)

	var selected_id = ""
	if terrain_dropdown.selected >= 0 and terrain_dropdown.selected < terrain_options.size():
		selected_id = terrain_options[terrain_dropdown.selected].id

	if _derived_displays_active and not _matchup_layouts.is_empty():
		# 11e: the disposition matchup fixes the terrain matchup; the player only
		# chooses which of the 3 official variants to play (each variant also
		# carries its own deployment pattern). Offer just those variants — the
		# legacy hand-made layouts are not part of an 11th-edition game.
		terrain_options = []
		for meta in _matchup_layouts:
			terrain_options.append({
				"id": str(meta.get("id", "")),
				"name": _terrain_variant_label(meta)
			})
	else:
		# Fallback (no official matchup layouts / 10e regression harness):
		# keep the base layouts plus any matchup layouts, all editable.
		terrain_options = _base_terrain_options.duplicate()
		for meta in _matchup_layouts:
			terrain_options.append({
				"id": str(meta.get("id", "")),
				"name": "11e: %s" % str(meta.get("name", meta.get("id", "")))
			})
		if terrain_options.is_empty():
			# No base layouts (legacy set removed) and no matchup — offer the
			# full official 11e list so the dropdown is never empty.
			for layout_id in tm.get_all_layout_ids():
				var meta_all = tm.get_layout_metadata(layout_id)
				terrain_options.append({
					"id": str(layout_id),
					"name": "11e: %s" % str(meta_all.get("name", layout_id))
				})
	terrain_dropdown.clear()
	for option in terrain_options:
		terrain_dropdown.add_item(option.name)

	var target_id = selected_id
	if (select_official or _derived_displays_active) and _matchup_layouts.size() > 0:
		# On a disposition change (or first-run in derived mode) default to the
		# matchup's variant 1 unless the old selection is still one of the
		# offered variants.
		if _find_option_index(terrain_options, selected_id) == 0 and (terrain_options.is_empty() or terrain_options[0].id != selected_id):
			target_id = str(_matchup_layouts[0].get("id", selected_id))
	terrain_dropdown.selected = _find_option_index(terrain_options, target_id)
	# Keep deployment (and its read-only label) in step with the chosen variant.
	if select_official or _derived_displays_active:
		_apply_layout_deployment_default()
	_refresh_derived_mission_display()
	var _sel_terrain_id = "<none>"
	if terrain_dropdown.selected >= 0 and terrain_dropdown.selected < terrain_options.size():
		_sel_terrain_id = terrain_options[terrain_dropdown.selected].id
	print("MainMenu: matchup %s vs %s -> %d official layouts (terrain: %s)" % [
		p1_disp, p2_disp, _matchup_layouts.size(), _sel_terrain_id])

## Short, informative name for one official 11e terrain variant. The matchup is
## already conveyed by the Force Disposition dropdowns, so surface the variant
## number plus the deployment it brings (variants differ by deployment).
func _terrain_variant_label(meta: Dictionary) -> String:
	var variant = int(meta.get("variant", 0))
	var recs: Array = meta.get("recommended_deployments", [])
	if recs.is_empty():
		return "Variant %d" % variant
	return "Variant %d (%s)" % [variant, _deployment_display_name(str(recs[0]))]

func _deployment_display_name(deployment_id: String) -> String:
	for option in deployment_options:
		if str(option.get("id", "")) == deployment_id:
			return str(option.get("name", deployment_id))
	return deployment_id

func _on_disposition_changed(_index: int) -> void:
	_refresh_matchup_terrain_options(true)

func _on_terrain_layout_selected(_index: int) -> void:
	_apply_layout_deployment_default()
	_refresh_derived_mission_display()

## D5: each official 11e layout card pairs with exactly one deployment
## pattern — follow it when such a layout is selected. Legacy layouts
## (several recommendations, player's choice) leave the dropdown alone.
func _apply_layout_deployment_default() -> void:
	if terrain_dropdown.selected < 0 or terrain_dropdown.selected >= terrain_options.size():
		return
	var layout_id = str(terrain_options[terrain_dropdown.selected].id)
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return
	var meta = tm.get_layout_metadata(layout_id)
	if str(meta.get("source", "")) != "gw-11e":
		return
	var recs: Array = meta.get("recommended_deployments", [])
	if recs.is_empty():
		return
	var idx = _find_option_index(deployment_options, str(recs[0]))
	if deployment_options[idx].get("id", "") == str(recs[0]) and deployment_dropdown.selected != idx:
		deployment_dropdown.selected = idx
		print("MainMenu: deployment defaulted to %s (official pattern for %s)" % [recs[0], layout_id])

func _get_selected_disposition(dropdown: OptionButton) -> String:
	if dropdown == null or dropdown.selected < 0 or dropdown.selected >= PrimaryMissionData11e.DISPOSITIONS.size():
		return "take_and_hold"
	return PrimaryMissionData11e.DISPOSITIONS[dropdown.selected]

func _on_p1_secondary_mode_changed(index: int) -> void:
	"""P2-85: Show/hide fixed mission select button for Player 1."""
	if p1_select_fixed_button:
		p1_select_fixed_button.visible = (index == 1)  # 1 = Fixed
	if index == 0:
		_p1_fixed_mission_ids.clear()
		_update_fixed_button_text(1)
	print("MainMenu: P1 secondary mode changed to %s" % ("Fixed" if index == 1 else "Tactical"))

func _on_p2_secondary_mode_changed(index: int) -> void:
	"""P2-85: Show/hide fixed mission select button for Player 2."""
	if p2_select_fixed_button:
		p2_select_fixed_button.visible = (index == 1)  # 1 = Fixed
	if index == 0:
		_p2_fixed_mission_ids.clear()
		_update_fixed_button_text(2)
	print("MainMenu: P2 secondary mode changed to %s" % ("Fixed" if index == 1 else "Tactical"))

func _on_p1_select_fixed_pressed() -> void:
	"""P2-85: Open fixed mission selection dialog for Player 1."""
	_show_fixed_mission_dialog(1)

func _on_p2_select_fixed_pressed() -> void:
	"""P2-85: Open fixed mission selection dialog for Player 2."""
	_show_fixed_mission_dialog(2)

func _show_fixed_mission_dialog(player: int) -> void:
	"""P2-85: Show FixedMissionSelectionDialog for the given player."""
	var dialog = FixedMissionSelectionDialogScript.new()
	add_child(dialog)
	dialog.setup(player)
	dialog.missions_selected.connect(_on_fixed_missions_selected)
	dialog.selection_cancelled.connect(_on_fixed_selection_cancelled.bind(player))
	dialog.popup_centered()

func _on_fixed_missions_selected(player: int, mission_ids: Array) -> void:
	"""P2-85: Handle confirmed fixed mission selection."""
	if player == 1:
		_p1_fixed_mission_ids = mission_ids
	else:
		_p2_fixed_mission_ids = mission_ids
	_update_fixed_button_text(player)
	print("MainMenu: Player %d fixed missions set: %s" % [player, str(mission_ids)])

func _on_fixed_selection_cancelled(player: int) -> void:
	"""P2-85: Handle cancelled fixed mission selection."""
	print("MainMenu: Player %d fixed mission selection cancelled" % player)

func _update_fixed_button_text(player: int) -> void:
	"""P2-85: Update the fixed mission button text to show selected missions."""
	var btn = p1_select_fixed_button if player == 1 else p2_select_fixed_button
	var ids = _p1_fixed_mission_ids if player == 1 else _p2_fixed_mission_ids
	if btn == null:
		return
	if ids.size() == 2:
		var SecondaryMissionData = preload("res://scripts/data/SecondaryMissionData.gd")
		var names = []
		for mid in ids:
			var m = SecondaryMissionData.get_mission_by_id(mid)
			names.append(m.get("name", mid))
		btn.text = "%s + %s" % [names[0], names[1]]
	else:
		btn.text = "Select Missions..."

func _load_available_armies() -> void:
	# Dynamically load available armies from ArmyListManager
	army_options.clear()

	if not ArmyListManager:
		print("MainMenu: Warning - ArmyListManager not available, using empty army list")
		return

	var available_armies = ArmyListManager.get_available_armies()

	if available_armies.is_empty():
		print("MainMenu: Warning - No armies found in armies/ directory")
		# Add a fallback option
		army_options.append({"id": "placeholder", "name": "No Armies Available", "date": "", "display": "No Armies Available"})
		return

	# Convert army IDs to display names with points
	for army_id in available_armies:
		var base_name = _format_army_name(army_id)
		var date_str = ArmyListManager.get_army_date(army_id)
		var points = ArmyListManager.get_army_points(army_id)
		var display_name = base_name
		if points > 0:
			display_name = "%s — %dpts" % [base_name, points]
		army_options.append({"id": army_id, "name": base_name, "date": date_str, "points": points, "display": display_name})

	# Sort based on current sort mode
	_sort_army_options()

	print("MainMenu: Loaded ", army_options.size(), " armies: ", army_options.map(func(a): return a.display))

func _format_army_name(army_id: String) -> String:
	# Convert army_id (e.g., "adeptus_custodes") to display name (e.g., "Adeptus Custodes")
	var words = army_id.split("_")
	var formatted_words = []

	for word in words:
		if word.is_empty():
			continue
		# Capitalize first letter of each word
		var capitalized = word[0].to_upper() + word.substr(1)
		formatted_words.append(capitalized)

	return " ".join(formatted_words)

func _format_date_display(date_str: String) -> String:
	"""Convert YYYY-MM-DD to a readable format like 'Mar 7, 2025'."""
	if date_str.is_empty():
		return ""
	var parts = date_str.split("-")
	if parts.size() != 3:
		return date_str
	var month_names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month_idx = parts[1].to_int() - 1
	if month_idx < 0 or month_idx >= 12:
		return date_str
	var day = parts[2].to_int()
	return "%s %d, %s" % [month_names[month_idx], day, parts[0]]

func _sort_army_options() -> void:
	"""Sort army_options based on current sort mode."""
	if army_sort_mode == "newest_first":
		army_options.sort_custom(func(a, b): return a.date > b.date)
	else:
		army_options.sort_custom(func(a, b): return a.name < b.name)

func _populate_army_dropdowns() -> void:
	"""Clear and repopulate army dropdowns from army_options."""
	player1_dropdown.clear()
	player2_dropdown.clear()
	for option in army_options:
		player1_dropdown.add_item(option.display)
		player2_dropdown.add_item(option.display)

func _create_army_sort_dropdown() -> void:
	"""Create a sort mode dropdown for army list ordering."""
	var army_section = $ScrollContainer/MenuContainer/ArmySection

	army_sort_container = HBoxContainer.new()
	army_sort_container.name = "ArmySortContainer"

	var sort_label = Label.new()
	sort_label.text = "Sort By:"
	sort_label.custom_minimum_size = Vector2(150, 0)
	army_sort_container.add_child(sort_label)

	army_sort_dropdown = OptionButton.new()
	army_sort_dropdown.name = "ArmySortDropdown"
	army_sort_dropdown.custom_minimum_size = Vector2(300, 0)
	army_sort_dropdown.add_item("Alphabetical")
	army_sort_dropdown.add_item("Newest First")
	army_sort_dropdown.selected = 0
	army_sort_dropdown.item_selected.connect(_on_army_sort_changed)
	army_sort_container.add_child(army_sort_dropdown)

	# Insert after the ArmyLabel (index 0 in ArmySection)
	army_section.add_child(army_sort_container)
	army_section.move_child(army_sort_container, 1)

	print("MainMenu: Army sort dropdown created")

func _create_army_builder_row() -> void:
	"""Row under the army sort dropdown: open the browser army builder (build /
	edit lists against the same cloud store these dropdowns read), and re-fetch
	cloud armies without restarting the game."""
	var army_section = $ScrollContainer/MenuContainer/ArmySection

	var container = HBoxContainer.new()
	container.name = "ArmyBuilderContainer"

	var row_label = Label.new()
	row_label.text = "Army Lists:"
	row_label.custom_minimum_size = Vector2(150, 0)
	container.add_child(row_label)

	var builder_button = Button.new()
	builder_button.name = "ArmyBuilderButton"
	builder_button.text = "Army Builder (browser)"
	builder_button.tooltip_text = "Build or edit army lists in your browser.\nLists saved to the cloud appear in these dropdowns."
	builder_button.custom_minimum_size = Vector2(220, 0)
	builder_button.pressed.connect(_on_army_builder_pressed)
	container.add_child(builder_button)

	var refresh_button = Button.new()
	refresh_button.name = "RefreshCloudArmiesButton"
	refresh_button.text = "Refresh Cloud Armies"
	refresh_button.tooltip_text = "Re-fetch the cloud army list (after saving from the Army Builder)."
	refresh_button.custom_minimum_size = Vector2(180, 0)
	refresh_button.pressed.connect(_on_refresh_cloud_armies_pressed)
	container.add_child(refresh_button)

	# Insert directly under the sort row (ArmyLabel = 0, sort = 1)
	army_section.add_child(container)
	army_section.move_child(container, 2)

	print("MainMenu: Army builder row created")

func _on_army_builder_pressed() -> void:
	var url = CloudStorage.base_url if CloudStorage else "http://localhost:9080"
	last_army_builder_url = url
	print("MainMenu: Opening army builder: ", url)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('%s', '_blank')" % url)
	else:
		var err = OS.shell_open(url)
		if err != OK:
			print("MainMenu: shell_open failed (%d) for %s" % [err, url])
			if ToastManager:
				ToastManager.show_error("Could not open browser — army builder is at %s" % url)
			return
	if ToastManager:
		ToastManager.show_toast("Army builder opened in your browser — use Refresh Cloud Armies after saving")

func _on_refresh_cloud_armies_pressed() -> void:
	print("MainMenu: Refreshing cloud armies")
	if ToastManager:
		ToastManager.show_toast("Refreshing cloud armies...")
	_load_cloud_armies()

func _on_army_sort_changed(index: int) -> void:
	"""Handle sort mode change."""
	var previous_p1_id = ""
	var previous_p2_id = ""
	if player1_dropdown.selected >= 0 and player1_dropdown.selected < army_options.size():
		previous_p1_id = army_options[player1_dropdown.selected].id
	if player2_dropdown.selected >= 0 and player2_dropdown.selected < army_options.size():
		previous_p2_id = army_options[player2_dropdown.selected].id

	army_sort_mode = "newest_first" if index == 1 else "alphabetical"
	_sort_army_options()
	_populate_army_dropdowns()

	# Restore selections
	_restore_dropdown_selection(player1_dropdown, previous_p1_id)
	_restore_dropdown_selection(player2_dropdown, previous_p2_id)

	print("MainMenu: Army sort changed to ", army_sort_mode)

func _set_default_army_selections() -> void:
	# Set intelligent defaults for army selections
	if army_options.is_empty():
		return

	# Try to find specific armies for defaults
	var player1_index = 0
	var player2_index = min(1, army_options.size() - 1)  # Different army if possible

	# Default matchup: the two newest base lists — Recon Stomps for
	# Player 1, Custodes Lions for Player 2
	for i in range(army_options.size()):
		if army_options[i].id == "recon_stomps":
			player1_index = i
		if army_options[i].id == "custodes_lions":
			player2_index = i

	player1_dropdown.selected = player1_index
	player2_dropdown.selected = player2_index

	print("MainMenu: Default armies set - Player 1: ", army_options[player1_index].name, ", Player 2: ", army_options[player2_index].name)

# ============================================================================
# Cloud Army Integration
# ============================================================================

func _load_cloud_armies() -> void:
	if not ArmyListManager:
		return
	# Callable on refresh too — only connect once.
	if not ArmyListManager.cloud_armies_loaded.is_connected(_on_cloud_armies_loaded):
		ArmyListManager.cloud_armies_loaded.connect(_on_cloud_armies_loaded)
	if not ArmyListManager.cloud_army_fetched.is_connected(_on_cloud_army_fetched):
		ArmyListManager.cloud_army_fetched.connect(_on_cloud_army_fetched)
	if not ArmyListManager.cloud_army_fetch_failed.is_connected(_on_cloud_army_fetch_failed):
		ArmyListManager.cloud_army_fetch_failed.connect(_on_cloud_army_fetch_failed)
	ArmyListManager.load_cloud_armies()

func _on_cloud_armies_loaded(cloud_armies: Array) -> void:
	if cloud_armies.is_empty():
		print("MainMenu: No cloud armies available")
		return

	# Save current selections before modifying dropdowns
	var p1_selected_id = ""
	var p2_selected_id = ""
	if player1_dropdown.selected >= 0 and player1_dropdown.selected < army_options.size():
		p1_selected_id = army_options[player1_dropdown.selected].id
	if player2_dropdown.selected >= 0 and player2_dropdown.selected < army_options.size():
		p2_selected_id = army_options[player2_dropdown.selected].id

	# Add cloud armies that aren't already in the dropdowns (locally or from a
	# previous fetch — this handler also runs on Refresh Cloud Armies).
	var existing_ids = []
	for option in army_options:
		existing_ids.append(option.id)
	var added_count = 0
	for cloud_name in cloud_armies:
		if cloud_name not in existing_ids:
			var base_name = _format_army_name(cloud_name) + " (Cloud)"
			var date_str = ArmyListManager.get_army_date(cloud_name)
			var display_name = base_name
			if not date_str.is_empty():
				display_name = "%s (%s)" % [base_name, _format_date_display(date_str)]
			army_options.append({"id": cloud_name, "name": base_name, "date": date_str, "display": display_name, "source": "cloud"})
			player1_dropdown.add_item(display_name)
			player2_dropdown.add_item(display_name)
			added_count += 1

	if added_count > 0:
		print("MainMenu: Added %d cloud armies to dropdowns" % added_count)

		# Restore selections
		_restore_dropdown_selection(player1_dropdown, p1_selected_id)
		_restore_dropdown_selection(player2_dropdown, p2_selected_id)

	# The newest base lists stay the default selections — cloud armies
	# are listed but never auto-selected over them.

func available_armies_ids() -> Array:
	var ids = []
	for option in army_options:
		if option.get("source", "local") == "local":
			ids.append(option.id)
	return ids

func _restore_dropdown_selection(dropdown: OptionButton, army_id: String) -> void:
	for i in range(army_options.size()):
		if army_options[i].id == army_id:
			dropdown.selected = i
			return

func _is_cloud_selection(army_id: String) -> bool:
	return ArmyListManager and ArmyListManager.is_cloud_army(army_id)

func _connect_signals() -> void:
	# D5: picking an official 11e layout snaps deployment to its pattern
	terrain_dropdown.item_selected.connect(_on_terrain_layout_selected)
	start_button.pressed.connect(_on_start_button_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_button_pressed)
	load_button.pressed.connect(_on_load_button_pressed)
	replay_button.pressed.connect(_on_replay_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

	# Hide quit button on web platform (not applicable)
	if OS.has_feature("web"):
		quit_button.visible = false
		print("MainMenu: Quit button hidden (web platform)")

	# Show/hide multiplayer button based on feature flag
	multiplayer_button.visible = FeatureFlags.is_multiplayer_available()
	print("MainMenu: Multiplayer button visible: ", multiplayer_button.visible)

	print("MainMenu: Signals connected")

func _setup_save_load_dialog() -> void:
	# Create save/load dialog
	var dialog_scene = load("res://scenes/SaveLoadDialog.tscn")
	if dialog_scene:
		save_load_dialog = dialog_scene.instantiate()
		add_child(save_load_dialog)
		save_load_dialog.load_requested.connect(_on_load_requested)
		print("MainMenu: Save/Load dialog setup complete")
	else:
		print("MainMenu: Warning - Could not load SaveLoadDialog.tscn")

func _on_start_button_pressed() -> void:
	print("MainMenu: Start button pressed")

	# Validate selections (ensure different armies if desired)
	if player1_dropdown.selected == player2_dropdown.selected:
		print("MainMenu: Warning - Both players have the same army selected")
		# For now, allow it but warn

	# Store configuration in GameState
	var p1_type = "AI" if player1_type_dropdown.selected == 1 else "HUMAN"
	var p2_type = "AI" if player2_type_dropdown.selected == 1 else "HUMAN"
	# T7-40: Get difficulty settings (dropdown index matches AIDifficultyConfig.Difficulty enum)
	var p1_difficulty = player1_difficulty_dropdown.selected if player1_difficulty_dropdown else 1
	var p2_difficulty = player2_difficulty_dropdown.selected if player2_difficulty_dropdown else 1
	# T7-36: Get AI speed setting (dropdown index matches AIPlayer.AISpeedPreset enum)
	var ai_speed = ai_speed_dropdown.selected if ai_speed_dropdown else 1
	# P2-85: Get secondary mission mode
	var p1_secondary_mode = "fixed" if p1_secondary_mode_dropdown and p1_secondary_mode_dropdown.selected == 1 else "tactical"
	var p2_secondary_mode = "fixed" if p2_secondary_mode_dropdown and p2_secondary_mode_dropdown.selected == 1 else "tactical"

	# P2-85: Validate fixed mission selections
	if p1_secondary_mode == "fixed" and _p1_fixed_mission_ids.size() != 2:
		print("MainMenu: Player 1 must select 2 fixed secondary missions before starting")
		_show_fixed_mission_dialog(1)
		return
	if p2_secondary_mode == "fixed" and _p2_fixed_mission_ids.size() != 2:
		print("MainMenu: Player 2 must select 2 fixed secondary missions before starting")
		_show_fixed_mission_dialog(2)
		return

	var config = {
		"terrain": terrain_options[terrain_dropdown.selected].id,
		"mission": mission_options[mission_dropdown.selected].id,
		"deployment": deployment_options[deployment_dropdown.selected].id,
		"player1_army": army_options[player1_dropdown.selected].id,
		"player2_army": army_options[player2_dropdown.selected].id,
		"player1_type": p1_type,
		"player2_type": p2_type,
		"player1_difficulty": p1_difficulty,
		"player2_difficulty": p2_difficulty,
		"ai_speed": ai_speed,
		"player1_secondary_mode": p1_secondary_mode,
		"player2_secondary_mode": p2_secondary_mode,
		"player1_fixed_missions": _p1_fixed_mission_ids.duplicate() if p1_secondary_mode == "fixed" else [],
		"player2_fixed_missions": _p2_fixed_mission_ids.duplicate() if p2_secondary_mode == "fixed" else [],
		"player1_disposition": _get_selected_disposition(p1_disposition_dropdown),
		"player2_disposition": _get_selected_disposition(p2_disposition_dropdown),
	}

	print("MainMenu: Starting game with config: ", config)

	# Check if any selected armies are cloud armies that need fetching
	var p1_is_cloud = _is_cloud_selection(config.player1_army)
	var p2_is_cloud = _is_cloud_selection(config.player2_army)

	if p1_is_cloud or p2_is_cloud:
		# Need to download cloud armies before starting
		start_button.disabled = true
		start_button.text = "Downloading armies..."
		_pending_game_config = config
		_cloud_fetch_count = 0

		if p1_is_cloud:
			_cloud_fetch_count += 1
			print("MainMenu: Fetching cloud army for Player 1: ", config.player1_army)
			ArmyListManager.fetch_cloud_army(config.player1_army, 1)

		if p2_is_cloud:
			_cloud_fetch_count += 1
			print("MainMenu: Fetching cloud army for Player 2: ", config.player2_army)
			ArmyListManager.fetch_cloud_army(config.player2_army, 2)
		return

	# No cloud armies - proceed immediately
	_initialize_game_with_config(config)

	# Transition to main game scene
	print("MainMenu: Transitioning to Main scene")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_cloud_army_fetched(_army_name: String, _army_data: Dictionary) -> void:
	_cloud_fetch_count -= 1
	print("MainMenu: Cloud army fetched, remaining: ", _cloud_fetch_count)

	if _cloud_fetch_count <= 0 and not _pending_game_config.is_empty():
		# All cloud armies downloaded, proceed with game start
		start_button.text = "Start Game"
		start_button.disabled = false

		var config = _pending_game_config
		_pending_game_config = {}
		_initialize_game_with_config(config)

		print("MainMenu: Transitioning to Main scene")
		get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_cloud_army_fetch_failed(army_name: String, error: String) -> void:
	print("MainMenu: Failed to download cloud army '%s': %s" % [army_name, error])
	_cloud_fetch_count = 0
	_pending_game_config = {}
	start_button.text = "Start Game"
	start_button.disabled = false

func _initialize_game_with_config(config: Dictionary) -> void:
	print("MainMenu: Initializing game state with configuration")
	
	# Clear any existing state first
	GameState.state.clear()

	# Initialize base game state with selected deployment type
	GameState.initialize_default_state(config.deployment)

	# Store configuration in game state BEFORE mission init — the 11e path in
	# MissionManager.initialize_mission reads the Force Dispositions from
	# meta.game_config (also re-stored below after army loading for clarity).
	GameState.state.meta["game_config"] = config

	# Apply terrain configuration
	if TerrainManager:
		TerrainManager.current_layout = config.terrain
		TerrainManager.load_terrain_layout(config.terrain)
		print("MainMenu: Terrain layout set to: ", config.terrain)
	
	# Initialize BoardState deployment zones to match selected deployment
	if BoardState:
		BoardState.initialize_deployment_zones(config.deployment)

	# Apply mission configuration — initialize MissionManager with selected mission
	if MissionManager:
		MissionManager.initialize_mission(config.mission)
		print("MainMenu: Mission initialized: ", config.mission)
	
	# Clear existing units before loading new armies
	GameState.state.units.clear()

	# Load Player 1 army (supports both local and cached cloud armies)
	if ArmyListManager:
		var player1_army = ArmyListManager.load_army_for_game(config.player1_army, 1)
		if not player1_army.is_empty():
			ArmyListManager.apply_army_to_game_state(player1_army, 1)
			print("MainMenu: Loaded ", config.player1_army, " for Player 1")
		else:
			print("MainMenu: Failed to load army for Player 1, using placeholder")
			GameState._initialize_placeholder_armies_player(1)

		# Load Player 2 army
		var player2_army = ArmyListManager.load_army_for_game(config.player2_army, 2)
		if not player2_army.is_empty():
			ArmyListManager.apply_army_to_game_state(player2_army, 2)
			print("MainMenu: Loaded ", config.player2_army, " for Player 2")
		else:
			print("MainMenu: Failed to load army for Player 2, using placeholder")
			GameState._initialize_placeholder_armies_player(2)
	else:
		print("MainMenu: ArmyListManager not available, using placeholder armies")
		GameState._initialize_placeholder_armies()
	
	# P2-85: Initialize fixed secondary missions if selected
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr:
		secondary_mgr.initialize_for_game()
		if config.get("player1_secondary_mode", "tactical") == "fixed":
			var p1_fixed = config.get("player1_fixed_missions", [])
			if p1_fixed.size() == 2:
				var result = secondary_mgr.setup_fixed_missions(1, p1_fixed)
				if result["success"]:
					print("MainMenu: Player 1 fixed missions initialized: %s" % str(p1_fixed))
				else:
					print("MainMenu: Failed to set up Player 1 fixed missions: %s" % result.get("error", ""))
		if config.get("player2_secondary_mode", "tactical") == "fixed":
			var p2_fixed = config.get("player2_fixed_missions", [])
			if p2_fixed.size() == 2:
				var result = secondary_mgr.setup_fixed_missions(2, p2_fixed)
				if result["success"]:
					print("MainMenu: Player 2 fixed missions initialized: %s" % str(p2_fixed))
				else:
					print("MainMenu: Failed to set up Player 2 fixed missions: %s" % result.get("error", ""))

	# Store configuration in game state for reference
	GameState.state.meta["game_config"] = config
	GameState.state.meta["from_menu"] = true

	print("MainMenu: Game initialization complete. Total units: ", GameState.state.units.size())

func _on_multiplayer_button_pressed() -> void:
	print("MainMenu: Multiplayer button pressed")
	# Transition to multiplayer lobby
	get_tree().change_scene_to_file("res://scenes/MultiplayerLobby.tscn")

func _on_load_button_pressed() -> void:
	print("MainMenu: Load button pressed")
	if save_load_dialog:
		save_load_dialog.show_dialog()
	else:
		print("MainMenu: Error - Save/Load dialog not available")

func _on_load_requested(save_file: String, owner_id: String = "") -> void:
	print("MainMenu: Load requested for file: ", save_file, " (owner_id: ", owner_id, ")")

	# Check if we're in multiplayer (shouldn't be from main menu, but safety check)
	if NetworkManager and NetworkManager.is_networked():
		print("MainMenu: Cannot load during active multiplayer session")
		return

	if not SaveLoadManager:
		print("MainMenu: SaveLoadManager not available")
		return

	if OS.has_feature("web"):
		# Web: async load - connect to signals, then trigger load
		if not SaveLoadManager.load_completed.is_connected(_on_cloud_load_completed):
			SaveLoadManager.load_completed.connect(_on_cloud_load_completed)
		if not SaveLoadManager.load_failed.is_connected(_on_cloud_load_failed):
			SaveLoadManager.load_failed.connect(_on_cloud_load_failed)
		# SAVE-20: Connect progress signals for cloud load
		if not SaveLoadManager.load_started.is_connected(_on_menu_load_started):
			SaveLoadManager.load_started.connect(_on_menu_load_started)
		if not SaveLoadManager.operation_progress.is_connected(_on_menu_save_load_progress):
			SaveLoadManager.operation_progress.connect(_on_menu_save_load_progress)
		SaveLoadManager.load_game(save_file, owner_id)
		print("MainMenu: Initiated async cloud load for: ", save_file)
	else:
		# Desktop: synchronous load
		var success = SaveLoadManager.load_game(save_file, owner_id)
		if success:
			print("MainMenu: Successfully loaded game: ", save_file)
			if GameState.state.meta:
				GameState.state.meta["from_save"] = true
				GameState.state.meta.erase("from_menu")
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
		else:
			print("MainMenu: Failed to load game: ", save_file)

func _on_cloud_load_completed(file_path: String, metadata: Dictionary) -> void:
	print("MainMenu: Cloud load completed: ", file_path)
	# SAVE-20: Dismiss progress indicator
	_dismiss_menu_progress()
	# Mark that we're loading from a save
	if GameState.state.meta:
		GameState.state.meta["from_save"] = true
		GameState.state.meta.erase("from_menu")
	# Transition to main game scene
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_cloud_load_failed(error: String) -> void:
	print("MainMenu: Cloud load failed: ", error)
	# SAVE-20: Dismiss progress indicator on failure
	_dismiss_menu_progress()

# SAVE-20: Progress indicator for main menu (cloud loads)
func _on_menu_load_started(_file_path: String) -> void:
	_show_menu_progress("Loading")

func _on_menu_save_load_progress(_stage: String, detail: String) -> void:
	if _save_load_progress_label and is_instance_valid(_save_load_progress_label):
		_save_load_progress_label.text = detail

func _show_menu_progress(operation: String) -> void:
	if _save_load_progress_overlay and is_instance_valid(_save_load_progress_overlay):
		return

	_save_load_progress_overlay = PanelContainer.new()
	_save_load_progress_overlay.name = "MenuProgressOverlay"
	_save_load_progress_overlay.anchor_left = 0.3
	_save_load_progress_overlay.anchor_right = 0.7
	_save_load_progress_overlay.anchor_top = 0.0
	_save_load_progress_overlay.anchor_bottom = 0.0
	_save_load_progress_overlay.offset_top = 8
	_save_load_progress_overlay.offset_bottom = 50
	_save_load_progress_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.06, 0.04, 0.92)
	bg_style.border_color = WhiteDwarfThemeData.WH_GOLD
	bg_style.set_border_width_all(2)
	bg_style.set_corner_radius_all(6)
	bg_style.set_content_margin_all(8)
	_save_load_progress_overlay.add_theme_stylebox_override("panel", bg_style)

	_save_load_progress_label = Label.new()
	_save_load_progress_label.text = operation + "..."
	_save_load_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_load_progress_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	_save_load_progress_label.add_theme_font_size_override("font_size", 18)
	_save_load_progress_overlay.add_child(_save_load_progress_label)

	add_child(_save_load_progress_overlay)
	_save_load_progress_overlay.z_index = 100

	# Pulse animation
	_save_load_progress_pulse_tween = create_tween().set_loops()
	_save_load_progress_pulse_tween.tween_property(_save_load_progress_label, "modulate", Color(1, 1, 1, 0.5), 0.8).set_trans(Tween.TRANS_SINE)
	_save_load_progress_pulse_tween.tween_property(_save_load_progress_label, "modulate", Color(1, 1, 1, 1.0), 0.8).set_trans(Tween.TRANS_SINE)

	print("MainMenu: SAVE-20 Progress indicator shown: %s" % operation)

func _dismiss_menu_progress() -> void:
	if not _save_load_progress_overlay or not is_instance_valid(_save_load_progress_overlay):
		_save_load_progress_overlay = null
		_save_load_progress_label = null
		return

	if _save_load_progress_pulse_tween:
		_save_load_progress_pulse_tween.kill()
		_save_load_progress_pulse_tween = null

	var fade_tween = create_tween()
	fade_tween.tween_property(_save_load_progress_overlay, "modulate", Color(1, 1, 1, 0), 0.3).set_trans(Tween.TRANS_SINE)
	fade_tween.tween_callback(_save_load_progress_overlay.queue_free)
	_save_load_progress_overlay = null
	_save_load_progress_label = null
	print("MainMenu: SAVE-20 Progress indicator dismissed")

# ============================================================================
# P3-111: Settings Menu
# ============================================================================

const SettingsMenuScript = preload("res://scripts/SettingsMenu.gd")

func _on_settings_button_pressed() -> void:
	print("MainMenu: Settings button pressed")
	var settings_menu = SettingsMenuScript.new()
	settings_menu.show_return_to_menu = false
	# Pad navigation: hand focus back when the overlay closes, otherwise the
	# D-pad goes dead until the player touches the mouse.
	settings_menu.settings_closed.connect(settings_button.grab_focus)
	add_child(settings_menu)

func _on_quit_button_pressed() -> void:
	print("MainMenu: Quit button pressed")
	get_tree().quit()

# ============================================================================
# Replay Browser
# ============================================================================

var replay_dialog: AcceptDialog = null

func _on_replay_button_pressed() -> void:
	print("MainMenu: Replay button pressed")
	_show_replay_browser()

func _show_replay_browser() -> void:
	"""Show a dialog listing available replays."""
	if not ReplayManager:
		print("MainMenu: ReplayManager not available")
		return

	var replays = ReplayManager.get_available_replays()
	print("MainMenu: Found %d replays" % replays.size())

	# Create or reuse dialog
	if replay_dialog and is_instance_valid(replay_dialog):
		replay_dialog.queue_free()

	replay_dialog = AcceptDialog.new()
	replay_dialog.title = "Watch Replays"
	replay_dialog.ok_button_text = "Close"
	replay_dialog.min_size = Vector2(650, 450)
	add_child(replay_dialog)

	# Build content
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 380)
	replay_dialog.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	if replays.is_empty():
		var no_replays_label = Label.new()
		no_replays_label.text = "No replays found.\n\nReplays are automatically saved during AI vs AI games.\nYou can also start recording from the game manually."
		no_replays_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(no_replays_label)
	else:
		for replay_entry in replays:
			var meta = replay_entry.get("meta", {})
			var file_path = replay_entry.get("file_path", "")

			# Create a row for each replay
			var row = PanelContainer.new()
			var row_style = StyleBoxFlat.new()
			row_style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
			row_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
			row_style.border_width_bottom = 1
			row_style.content_margin_left = 10
			row_style.content_margin_right = 10
			row_style.content_margin_top = 8
			row_style.content_margin_bottom = 8
			row.add_theme_stylebox_override("panel", row_style)
			vbox.add_child(row)

			var hbox = HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 12)
			row.add_child(hbox)

			# Info column
			var info_vbox = VBoxContainer.new()
			info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(info_vbox)

			# Title: factions
			var p1_faction = meta.get("player1_faction", "Player 1")
			var p2_faction = meta.get("player2_faction", "Player 2")
			var title_label = Label.new()
			title_label.text = "%s vs %s" % [p1_faction, p2_faction]
			title_label.add_theme_font_size_override("font_size", 16)
			info_vbox.add_child(title_label)

			# Subtitle: date, rounds, score
			var created_at = meta.get("created_at", 0)
			var date_str = _format_timestamp(created_at)
			var final_round = meta.get("final_round", "?")
			var final_score = meta.get("final_score", {})
			var p1_vp = final_score.get("p1_vp", 0)
			var p2_vp = final_score.get("p2_vp", 0)
			var total_events = meta.get("total_events", 0)
			var p1_type = meta.get("player1_type", "?")
			var p2_type = meta.get("player2_type", "?")

			var replay_status = meta.get("status", "complete")
			var status_label = "[Complete]" if replay_status == "complete" else "[In Progress]"

			var subtitle = Label.new()
			subtitle.text = "%s %s | %s vs %s | Round %s | Score: %d-%d | %d events" % [
				status_label, date_str, p1_type, p2_type, str(final_round), p1_vp, p2_vp, total_events]
			subtitle.add_theme_font_size_override("font_size", 12)
			var subtitle_color = Color(0.6, 0.6, 0.6) if replay_status == "complete" else Color(0.8, 0.7, 0.3)
			subtitle.add_theme_color_override("font_color", subtitle_color)
			info_vbox.add_child(subtitle)

			# Watch button
			var watch_btn = Button.new()
			watch_btn.text = "Watch"
			watch_btn.custom_minimum_size = Vector2(80, 35)
			watch_btn.pressed.connect(_on_replay_selected.bind(file_path))
			hbox.add_child(watch_btn)

			# Delete button
			var delete_btn = Button.new()
			delete_btn.text = "X"
			delete_btn.custom_minimum_size = Vector2(35, 35)
			delete_btn.tooltip_text = "Delete replay"
			delete_btn.pressed.connect(_on_replay_delete.bind(file_path))
			hbox.add_child(delete_btn)

	replay_dialog.popup_centered()

func _on_replay_selected(file_path: String) -> void:
	"""Load a replay and start playback."""
	print("MainMenu: Loading replay: %s" % file_path)

	if not ReplayManager:
		print("MainMenu: ReplayManager not available")
		return

	# Load the replay file
	var success = ReplayManager.load_replay_from_file(file_path)
	if not success:
		print("MainMenu: Failed to load replay: %s" % file_path)
		return

	# Apply the initial state to GameState
	ReplayManager.apply_initial_state()

	# Mark that we're entering replay mode
	GameState.state.meta["from_replay"] = true
	GameState.state.meta.erase("from_menu")
	GameState.state.meta.erase("from_save")

	# Close dialog and transition to Main scene in replay mode
	if replay_dialog:
		replay_dialog.hide()

	print("MainMenu: Transitioning to replay mode")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_replay_delete(file_path: String) -> void:
	"""Delete a replay file and refresh the browser."""
	print("MainMenu: Deleting replay: %s" % file_path)
	if ReplayManager:
		ReplayManager.delete_replay(file_path)
	# Refresh the dialog
	_show_replay_browser()

func _format_timestamp(unix_time: float) -> String:
	"""Format a Unix timestamp to a readable date string."""
	if unix_time <= 0:
		return "Unknown date"
	var dt = Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

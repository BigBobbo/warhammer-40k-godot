extends PanelContainer
class_name MathhammerUI

# Preload the Mathhammer class
const Mathhammer = preload("res://scripts/Mathhammer.gd")

# MathhammerUI - Statistical analysis panel for Warhammer 40k combat calculations
# Follows UnitStatsPanel patterns for consistent UI integration
# Provides Monte Carlo simulation interface and results visualization

# UI node references - created programmatically
var toggle_button: Button
var scroll_container: ScrollContainer
var content_container: VBoxContainer

# Main content sections
var unit_selector: VBoxContainer
var summary_panel: VBoxContainer
var distribution_panel: Control
var breakdown_panel: VBoxContainer
var rule_toggles_panel: VBoxContainer

# Control elements
var attacker_selector: OptionButton
var defender_selector: OptionButton
var weapon_selection_panel: VBoxContainer
var run_simulation_button: Button
var trials_spinbox: SpinBox
var phase_toggle: OptionButton  # Shooting/Melee phase selector

# Defender stats override controls
var defender_override_checkbox: CheckBox
var defender_override_panel: VBoxContainer
var override_toughness_spinbox: SpinBox
var override_save_spinbox: SpinBox
var override_wounds_spinbox: SpinBox
var override_invuln_spinbox: SpinBox
var override_fnp_spinbox: SpinBox
var override_model_count_spinbox: SpinBox

# Results display elements
var results_label: RichTextLabel
var histogram_display: Control
var breakdown_text: RichTextLabel

# State management
var is_collapsed: bool = true
var current_simulation_result: Mathhammer.SimulationResult
var available_units: Dictionary = {}
var selected_weapons: Dictionary = {}  # weapon_id -> {unit_id, attack_count, weapon_data}
var selected_attackers: Dictionary = {}  # unit_id -> selected state
var rule_toggles: Dictionary = {}
var auto_detected_rules: Dictionary = {}  # Tracks which rules were auto-detected from weapon/unit data
var tween: Tween

# Background thread for simulation (T3-25)
var _simulation_thread: Thread = null

# Signals
signal simulation_requested(config: Dictionary)
signal unit_selection_changed(attacker_id: String, defender_id: String)

func _ready() -> void:
	print("MathhammerUI: Initializing...")

	_setup_ui_structure()
	_setup_controls()
	_connect_signals()
	_populate_unit_selectors()
	_populate_rule_toggles()

	# Start collapsed following UnitStatsPanel pattern
	is_collapsed = true
	set_collapsed(false)  # Start expanded to show functionality

func _exit_tree() -> void:
	# Clean up background simulation thread on node removal (T3-25)
	if _simulation_thread != null and _simulation_thread.is_started():
		print("MathhammerUI: Waiting for simulation thread to finish before exit...")
		_simulation_thread.wait_to_finish()

func _setup_ui_structure() -> void:
	# Create the main UI structure programmatically if nodes don't exist
	if not toggle_button:
		_create_ui_structure()

func _create_ui_structure() -> void:
	# Set panel to use full height
	custom_minimum_size.y = 800
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Create main VBox
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "VBox"
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_vbox)
	
	# Header with toggle button
	var header = HBoxContainer.new()
	header.name = "Header"
	main_vbox.add_child(header)
	
	toggle_button = Button.new()
	toggle_button.name = "ToggleButton"
	toggle_button.text = "🎲 Mathhammer Analysis"
	header.add_child(toggle_button)
	
	# Scroll container for content
	scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer"
	scroll_container.custom_minimum_size = Vector2(400, 600)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll_container)
	
	# Content container
	content_container = VBoxContainer.new()
	content_container.name = "Content"
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(content_container)
	
	_create_content_sections()

func _create_content_sections() -> void:
	# Unit Selector Section
	unit_selector = VBoxContainer.new()
	unit_selector.name = "UnitSelector"
	unit_selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_selector.add_theme_constant_override("separation", 8)
	content_container.add_child(unit_selector)

	# Add some spacing between sections
	var section_spacer1 = Control.new()
	section_spacer1.custom_minimum_size.y = 20

	var selector_label = Label.new()
	selector_label.text = "Unit Selection"
	selector_label.add_theme_font_size_override("font_size", 16)
	unit_selector.add_child(selector_label)

	# Phase selector (Shooting/Melee)
	var phase_hbox = HBoxContainer.new()
	unit_selector.add_child(phase_hbox)
	var phase_label = Label.new()
	phase_label.text = "Phase:"
	phase_label.custom_minimum_size.x = 80
	phase_hbox.add_child(phase_label)
	phase_toggle = OptionButton.new()
	phase_toggle.add_item("Shooting")
	phase_toggle.set_item_metadata(0, "shooting")
	phase_toggle.add_item("Melee")
	phase_toggle.set_item_metadata(1, "fight")
	phase_toggle.selected = 0
	phase_hbox.add_child(phase_toggle)
	
	# Multiple attacker selection with checkboxes
	var attacker_label = Label.new()
	attacker_label.text = "Attackers (select multiple):"
	attacker_label.add_theme_font_size_override("font_size", 14)
	unit_selector.add_child(attacker_label)
	
	# Create a scrollable container for attacker checkboxes
	attacker_selector = OptionButton.new()  # Keep for compatibility, but hidden
	attacker_selector.visible = false
	unit_selector.add_child(attacker_selector)
	
	# Defender selection
	var defender_hbox = HBoxContainer.new()
	unit_selector.add_child(defender_hbox)
	var defender_label = Label.new()
	defender_label.text = "Defender:"
	defender_label.custom_minimum_size.x = 80
	defender_hbox.add_child(defender_label)
	defender_selector = OptionButton.new()
	defender_hbox.add_child(defender_selector)
	
	# Defender Stats Override Section
	var override_separator = HSeparator.new()
	unit_selector.add_child(override_separator)

	defender_override_checkbox = CheckBox.new()
	defender_override_checkbox.text = "Custom Defender Stats"
	defender_override_checkbox.tooltip_text = "Override defender T/Sv/W/Invuln/FNP with custom values"
	defender_override_checkbox.add_theme_font_size_override("font_size", 13)
	unit_selector.add_child(defender_override_checkbox)
	defender_override_checkbox.toggled.connect(_on_defender_override_toggled)

	defender_override_panel = VBoxContainer.new()
	defender_override_panel.name = "DefenderOverridePanel"
	defender_override_panel.add_theme_constant_override("separation", 4)
	defender_override_panel.visible = false  # Hidden until checkbox is toggled
	unit_selector.add_child(defender_override_panel)

	_create_defender_override_fields()

	# Weapon Selection Section
	var weapon_separator = HSeparator.new()
	unit_selector.add_child(weapon_separator)

	var weapon_label = Label.new()
	weapon_label.text = "Weapon Selection"
	weapon_label.add_theme_font_size_override("font_size", 14)
	unit_selector.add_child(weapon_label)
	
	weapon_selection_panel = VBoxContainer.new()
	weapon_selection_panel.name = "WeaponSelection"
	weapon_selection_panel.custom_minimum_size.y = 120
	weapon_selection_panel.add_theme_constant_override("separation", 4)
	unit_selector.add_child(weapon_selection_panel)
	
	# Trial count selection
	var trials_separator = HSeparator.new()
	unit_selector.add_child(trials_separator)
	
	var trials_hbox = HBoxContainer.new()
	unit_selector.add_child(trials_hbox)
	var trials_label = Label.new()
	trials_label.text = "Trials:"
	trials_label.custom_minimum_size.x = 80
	trials_hbox.add_child(trials_label)
	trials_spinbox = SpinBox.new()
	trials_spinbox.min_value = 100
	trials_spinbox.max_value = 100000
	trials_spinbox.value = 10000
	trials_spinbox.step = 100
	trials_hbox.add_child(trials_spinbox)
	
	# Run simulation button
	run_simulation_button = Button.new()
	run_simulation_button.text = "Run Simulation"
	unit_selector.add_child(run_simulation_button)
	
	# Add spacer before rule toggles
	content_container.add_child(section_spacer1)
	
	# Rule Toggles Section
	rule_toggles_panel = VBoxContainer.new()
	rule_toggles_panel.name = "RuleTogglesPanel"
	rule_toggles_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rule_toggles_panel.add_theme_constant_override("separation", 6)
	content_container.add_child(rule_toggles_panel)
	
	var rules_label = Label.new()
	rules_label.text = "Rule Modifiers"
	rules_label.add_theme_font_size_override("font_size", 16)
	rule_toggles_panel.add_child(rules_label)
	
	# Add spacer before results
	var section_spacer2 = Control.new()
	section_spacer2.custom_minimum_size.y = 20
	content_container.add_child(section_spacer2)
	
	# Summary Panel Section
	summary_panel = VBoxContainer.new()
	summary_panel.name = "SummaryPanel"
	summary_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary_panel.add_theme_constant_override("separation", 8)
	content_container.add_child(summary_panel)
	
	var summary_label = Label.new()
	summary_label.text = "Results Summary"
	summary_label.add_theme_font_size_override("font_size", 16)
	summary_panel.add_child(summary_label)
	
	results_label = RichTextLabel.new()
	results_label.custom_minimum_size = Vector2(350, 150)
	results_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_label.bbcode_enabled = true
	results_label.text = "Run a simulation to see results..."
	results_label.name = "InitialResultsLabel"
	summary_panel.add_child(results_label)
	
	# Add spacer before distribution
	var section_spacer3 = Control.new()
	section_spacer3.custom_minimum_size.y = 15
	content_container.add_child(section_spacer3)
	
	# Distribution Panel Section
	distribution_panel = Control.new()
	distribution_panel.name = "DistributionPanel"
	distribution_panel.custom_minimum_size = Vector2(350, 200)
	distribution_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(distribution_panel)
	
	histogram_display = Control.new()
	histogram_display.name = "HistogramDisplay"
	histogram_display.custom_minimum_size = Vector2(350, 150)
	distribution_panel.add_child(histogram_display)
	
	# Breakdown Panel Section
	breakdown_panel = VBoxContainer.new()
	breakdown_panel.name = "BreakdownPanel"
	content_container.add_child(breakdown_panel)
	
	var breakdown_label = Label.new()
	breakdown_label.text = "Detailed Breakdown"
	breakdown_label.add_theme_font_size_override("font_size", 16)
	breakdown_panel.add_child(breakdown_label)
	
	breakdown_text = RichTextLabel.new()
	breakdown_text.custom_minimum_size = Vector2(350, 100)
	breakdown_text.bbcode_enabled = true
	breakdown_text.text = "Detailed statistics will appear here after simulation..."
	breakdown_panel.add_child(breakdown_text)

func _setup_controls() -> void:
	# Configure trials spinbox
	if trials_spinbox:
		trials_spinbox.min_value = 100
		trials_spinbox.max_value = 100000
		trials_spinbox.value = 10000
		trials_spinbox.step = 100

func _connect_signals() -> void:
	if toggle_button:
		toggle_button.pressed.connect(_on_toggle_pressed)
	
	if run_simulation_button:
		run_simulation_button.pressed.connect(_on_run_simulation_pressed)
	
	if attacker_selector:
		attacker_selector.item_selected.connect(_on_attacker_selection_changed)

	if defender_selector:
		defender_selector.item_selected.connect(_on_unit_selection_changed)

	if phase_toggle:
		phase_toggle.item_selected.connect(_on_phase_changed)

func _on_toggle_pressed() -> void:
	set_collapsed(!is_collapsed)

func set_collapsed(collapsed: bool) -> void:
	is_collapsed = collapsed
	
	if scroll_container:
		scroll_container.visible = !collapsed
	
	if toggle_button:
		toggle_button.text = "🎲 Mathhammer Analysis ▼" if collapsed else "🎲 Mathhammer Analysis ▲"
	
	# Animate panel height following UnitStatsPanel pattern
	if tween:
		tween.kill()
	
	tween = create_tween()
	var target_height = 40 if collapsed else 400
	tween.tween_property(self, "custom_minimum_size:y", target_height, 0.3)
	
	# Animate offset to expand upward
	var target_offset = -40 if collapsed else -400
	tween.parallel().tween_property(self, "offset_top", target_offset, 0.3)

func _populate_unit_selectors() -> void:
	if not GameState:
		return
	
	available_units.clear()
	selected_attackers.clear()
	defender_selector.clear()
	
	# Clear existing attacker rows
	if unit_selector:
		# Find and remove existing attacker rows
		for child in unit_selector.get_children():
			if child.has_meta("is_attacker_row"):
				child.queue_free()
	
	# Get all units from current game state
	var all_units = GameState.state.get("units", {})
	
	# Create container for attacker checkboxes if not exists
	var attacker_container = unit_selector.get_node_or_null("AttackerContainer")
	if not attacker_container:
		attacker_container = VBoxContainer.new()
		attacker_container.name = "AttackerContainer"
		# Insert after the attacker label
		var insert_index = 2  # After title and "Attackers" label
		if unit_selector.get_child_count() > insert_index:
			unit_selector.add_child(attacker_container)
			unit_selector.move_child(attacker_container, insert_index)
		else:
			unit_selector.add_child(attacker_container)
	
	for unit_id in all_units:
		var unit = all_units[unit_id]
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var owner = unit.get("owner", 0)
		var display_name = "%s (Player %d)" % [unit_name, owner]
		
		available_units[unit_id] = {
			"name": unit_name,
			"display_name": display_name,
			"owner": owner,
			"has_ranged_weapons": _unit_has_ranged_weapons(unit)
		}
		
		# Create horizontal container for unit selection
		var unit_row = HBoxContainer.new()
		unit_row.set_meta("is_attacker_row", true)
		unit_row.set_meta("unit_id", unit_id)
		
		# Unit name label
		var unit_label = Label.new()
		unit_label.text = display_name
		unit_label.custom_minimum_size.x = 200
		unit_label.add_theme_font_size_override("font_size", 12)
		unit_row.add_child(unit_label)
		
		# Attack count spinbox
		var attack_spinbox = SpinBox.new()
		attack_spinbox.min_value = 0
		attack_spinbox.max_value = 10
		attack_spinbox.value = 0
		attack_spinbox.step = 1
		attack_spinbox.custom_minimum_size.x = 80
		attack_spinbox.add_theme_font_size_override("font_size", 11)
		
		# Connect value change signal
		attack_spinbox.value_changed.connect(_on_attacker_attack_count_changed.bind(unit_id))
		
		unit_row.add_child(attack_spinbox)
		
		# "attacks" label
		var attacks_label = Label.new()
		attacks_label.text = " attacks"
		attacks_label.add_theme_font_size_override("font_size", 11)
		unit_row.add_child(attacks_label)
		
		attacker_container.add_child(unit_row)
		selected_attackers[unit_id] = 0  # Store attack count instead of boolean
		
		# Add to defender dropdown
		defender_selector.add_item(display_name)
		defender_selector.set_item_metadata(defender_selector.get_item_count() - 1, unit_id)

func _unit_has_ranged_weapons(unit: Dictionary) -> bool:
	var weapons = unit.get("meta", {}).get("weapons", [])
	for weapon in weapons:
		if weapon.get("type", "") == "Ranged":
			return true
	return false

func _populate_rule_toggles() -> void:
	# Create common rule toggles with phase applicability
	# phase: "both" = always visible, "shooting" = shooting only, "melee" = melee only
	var common_rules = [
		{"id": "lethal_hits", "name": "Lethal Hits", "description": "6s to hit automatically wound", "phase": "both"},
		{"id": "sustained_hits", "name": "Sustained Hits", "description": "6s to hit generate extra hits", "phase": "both"},
		{"id": "twin_linked", "name": "Twin-linked", "description": "Re-roll all failed wound rolls (weapon keyword)", "phase": "both"},
		{"id": "devastating_wounds", "name": "Devastating Wounds", "description": "6s to wound become mortal wounds", "phase": "both"},
		{"id": "cover", "name": "Target in Cover", "description": "Defender has cover bonus", "phase": "shooting"},
		{"id": "hit_plus_1", "name": "+1 to Hit", "description": "Bonus to hit rolls", "phase": "both"},
		{"id": "wound_plus_1", "name": "+1 to Wound", "description": "Bonus to wound rolls", "phase": "both"},
		{"id": "save_plus_1", "name": "+1 to Save", "description": "Defender gets +1 to save rolls (capped at +1 per 10e rules)", "phase": "both"},
		{"id": "save_minus_1", "name": "-1 to Save", "description": "Defender gets -1 to save rolls (capped at -1 per 10e rules)", "phase": "both"},
		{"id": "torrent", "name": "Torrent", "description": "Auto-hit (no hit roll, no critical hits)", "phase": "shooting"},
		{"id": "reroll_hits_ones", "name": "Re-roll 1s to Hit", "description": "Re-roll hit rolls of 1 (e.g. Oath of Moment)", "phase": "both"},
		{"id": "reroll_hits_failed", "name": "Re-roll All Failed Hits", "description": "Re-roll all failed hit rolls", "phase": "both"},
		{"id": "reroll_wounds_ones", "name": "Re-roll 1s to Wound", "description": "Re-roll wound rolls of 1", "phase": "both"},
		{"id": "reroll_wounds_failed", "name": "Re-roll All Failed Wounds", "description": "Re-roll all failed wound rolls (e.g. Twin-linked ability)", "phase": "both"},
		{"id": "rapid_fire", "name": "Rapid Fire Range", "description": "+X attacks at half range (per model)", "phase": "shooting"},
		{"id": "lance_charged", "name": "Charged (Lance +1 Wound)", "description": "Unit charged this turn - Lance weapons get +1 to wound", "phase": "both"},
		{"id": "invuln_6", "name": "Invulnerable Save 6+", "description": "Defender has 6+ invulnerable save (ignores AP)", "phase": "both"},
		{"id": "invuln_5", "name": "Invulnerable Save 5+", "description": "Defender has 5+ invulnerable save (ignores AP)", "phase": "both"},
		{"id": "invuln_4", "name": "Invulnerable Save 4+", "description": "Defender has 4+ invulnerable save (ignores AP)", "phase": "both"},
		{"id": "invuln_3", "name": "Invulnerable Save 3+", "description": "Defender has 3+ invulnerable save (ignores AP)", "phase": "both"},
		{"id": "invuln_2", "name": "Invulnerable Save 2+", "description": "Defender has 2+ invulnerable save (ignores AP)", "phase": "both"},
		{"id": "anti_infantry_4", "name": "Anti-Infantry 4+", "description": "Critical wounds on 4+ vs INFANTRY targets", "phase": "both"},
		{"id": "anti_vehicle_4", "name": "Anti-Vehicle 4+", "description": "Critical wounds on 4+ vs VEHICLE targets", "phase": "both"},
		{"id": "anti_monster_4", "name": "Anti-Monster 4+", "description": "Critical wounds on 4+ vs MONSTER targets", "phase": "both"},
		{"id": "conversion_4", "name": "Conversion 4+", "description": "Critical hits on 4+ (assumes 12\"+ range to target)", "phase": "shooting"},
		{"id": "conversion_5", "name": "Conversion 5+", "description": "Critical hits on 5+ (assumes 12\"+ range to target)", "phase": "shooting"},
		{"id": "feel_no_pain_6", "name": "Feel No Pain 6+", "description": "Defender ignores wounds on 6+", "phase": "both"},
		{"id": "feel_no_pain_5", "name": "Feel No Pain 5+", "description": "Defender ignores wounds on 5+", "phase": "both"},
		{"id": "feel_no_pain_4", "name": "Feel No Pain 4+", "description": "Defender ignores wounds on 4+", "phase": "both"}
	]

	for rule in common_rules:
		var checkbox = CheckBox.new()
		checkbox.text = rule.name
		checkbox.tooltip_text = rule.description
		checkbox.set_meta("rule_phase", rule.get("phase", "both"))
		checkbox.set_meta("rule_id", rule.id)
		rule_toggles_panel.add_child(checkbox)

		# Connect signal with rule ID
		checkbox.toggled.connect(_on_rule_toggled.bind(rule.id))
		rule_toggles[rule.id] = false

	# Apply initial phase visibility
	_update_rule_toggles_for_phase()

func _update_rule_toggles_for_phase() -> void:
	var selected_phase = _get_selected_phase()
	var is_melee = selected_phase == "fight"

	for child in rule_toggles_panel.get_children():
		if child is CheckBox and child.has_meta("rule_phase"):
			var rule_phase = child.get_meta("rule_phase")
			if rule_phase == "both":
				child.visible = true
			elif rule_phase == "shooting":
				child.visible = not is_melee
			elif rule_phase == "melee":
				child.visible = is_melee

func _update_weapon_selection() -> void:
	# Clear existing weapon selection
	if not weapon_selection_panel:
		return
		
	for child in weapon_selection_panel.get_children():
		child.queue_free()
	
	selected_weapons.clear()
	
	# Check if any attackers have attacks > 0
	var has_selected_attackers = false
	for unit_id in selected_attackers:
		if selected_attackers[unit_id] > 0:
			has_selected_attackers = true
			break
	
	if not has_selected_attackers:
		var no_selection_label = Label.new()
		no_selection_label.text = "Set attacker attack counts above"
		no_selection_label.add_theme_font_size_override("font_size", 12)
		weapon_selection_panel.add_child(no_selection_label)
		return
	
	# Determine which weapon types to show based on selected phase
	var selected_phase = _get_selected_phase()
	var show_ranged = selected_phase == "shooting"
	var show_melee = selected_phase == "fight"

	# Create weapon entries with attack count spinboxes
	for unit_id in selected_attackers:
		if selected_attackers[unit_id] <= 0:
			continue

		var unit = GameState.get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var unit_weapons = unit.get("meta", {}).get("weapons", [])
		
		# Unit header
		var unit_header = Label.new()
		unit_header.text = "\n%s:" % unit_name
		unit_header.add_theme_font_size_override("font_size", 13)
		unit_header.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
		weapon_selection_panel.add_child(unit_header)
		
		for i in range(unit_weapons.size()):
			var weapon = unit_weapons[i]
			var weapon_type = weapon.get("type", "Unknown")

			# Filter weapons by selected phase
			if show_ranged and weapon_type.to_lower() != "ranged":
				continue
			if show_melee and weapon_type.to_lower() != "melee":
				continue

			var weapon_name = weapon.get("name", "Weapon %d" % (i + 1))
			var weapon_key = "%s_weapon_%d" % [unit_id, i]

			# Create weapon row container
			var weapon_row = HBoxContainer.new()
			weapon_selection_panel.add_child(weapon_row)
			
			# Weapon label with stats
			var weapon_stats = ""
			
			if weapon_type == "Ranged":
				weapon_stats = " [BS:%s+ S:%s AP:%s D:%s]" % [
					weapon.get("ballistic_skill", "4"),
					weapon.get("strength", "4"),
					weapon.get("ap", "0"),
					weapon.get("damage", "1")
				]
			else:
				weapon_stats = " [WS:%s+ S:%s AP:%s D:%s]" % [
					weapon.get("weapon_skill", "4"),
					weapon.get("strength", "4"),
					weapon.get("ap", "0"),
					weapon.get("damage", "1")
				]
			
			var weapon_label = Label.new()
			weapon_label.text = weapon_name + weapon_stats
			weapon_label.custom_minimum_size.x = 250
			weapon_label.add_theme_font_size_override("font_size", 11)
			weapon_row.add_child(weapon_label)
			
			# Attack count spinbox
			var attack_spinbox = SpinBox.new()
			attack_spinbox.min_value = 0
			attack_spinbox.max_value = 100
			
			# Parse base attacks from weapon
			var base_attacks = weapon.get("attacks", "1")
			var default_attacks = 1
			if base_attacks != null and typeof(base_attacks) == TYPE_STRING:
				if base_attacks.is_valid_int():
					default_attacks = int(base_attacks)
				elif base_attacks.begins_with("D"):
					default_attacks = 3  # Average for dice rolls
			elif typeof(base_attacks) == TYPE_INT:
				default_attacks = base_attacks
				
			attack_spinbox.value = default_attacks
			attack_spinbox.step = 1
			attack_spinbox.custom_minimum_size.x = 80
			attack_spinbox.add_theme_font_size_override("font_size", 11)
			
			# Connect value change signal
			attack_spinbox.value_changed.connect(_on_weapon_attack_count_changed.bind(weapon_key))
			
			weapon_row.add_child(attack_spinbox)
			
			# Add "attacks" label
			var attacks_label = Label.new()
			attacks_label.text = " attacks"
			attacks_label.add_theme_font_size_override("font_size", 11)
			weapon_row.add_child(attacks_label)
			
			# Store weapon data
			selected_weapons[weapon_key] = {
				"unit_id": unit_id,
				"attack_count": int(attack_spinbox.value),
				"weapon_data": weapon,
				"weapon_index": i
			}

	# Auto-detect weapon abilities from selected weapons and attacker units
	_auto_detect_weapon_rules()

func _auto_detect_weapon_rules() -> void:
	# Auto-detect weapon abilities from selected weapons' special_rules
	# and auto-enable the corresponding rule toggles in the UI

	# First, clear previously auto-detected attacker rules (uncheck them)
	var attacker_rule_prefixes_to_keep = ["invuln_", "feel_no_pain_"]
	for rule_id in auto_detected_rules.keys():
		if auto_detected_rules[rule_id]:
			# Don't clear defender-side rules here (handled by _auto_detect_defender_rules)
			var is_defender_rule = false
			for prefix in attacker_rule_prefixes_to_keep:
				if rule_id.begins_with(prefix):
					is_defender_rule = true
					break
			if not is_defender_rule:
				_set_rule_toggle(rule_id, false, false)
				auto_detected_rules.erase(rule_id)

	# Collect all special_rules from selected weapons
	var detected_rule_ids = {}
	for weapon_key in selected_weapons:
		var weapon_info = selected_weapons[weapon_key]
		if weapon_info.get("attack_count", 0) <= 0:
			continue
		var weapon_data = weapon_info.get("weapon_data", {})
		var special_rules = weapon_data.get("special_rules", "")
		if special_rules != "":
			var parsed_rules = MathhammerRuleModifiers._parse_weapon_special_rules(special_rules)
			for rule_id in parsed_rules:
				detected_rule_ids[rule_id] = true

	# Also extract unit-level abilities from selected attacker units
	for unit_id in selected_attackers:
		if selected_attackers[unit_id] <= 0:
			continue
		if not GameState:
			continue
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			continue
		# Faction-specific rules
		var keywords = unit.get("meta", {}).get("keywords", [])
		if "ORKS" in keywords:
			detected_rule_ids["waaagh_active"] = true

	# Auto-enable detected rules
	if not detected_rule_ids.is_empty():
		var detected_names = []
		for rule_id in detected_rule_ids:
			auto_detected_rules[rule_id] = true
			_set_rule_toggle(rule_id, true, true)
			detected_names.append(rule_id)
		print("MathhammerUI: Auto-detected weapon rules: %s" % str(detected_names))
	else:
		print("MathhammerUI: No weapon rules auto-detected from selected weapons")

func _auto_detect_defender_rules(defender_id: String) -> void:
	# Auto-detect defender abilities (invuln saves, FNP) from defender unit data
	if defender_id == "" or not GameState:
		return

	var unit = GameState.get_unit(defender_id)
	if unit.is_empty():
		return

	# Clear previously auto-detected defender rules
	var defender_rule_prefixes = ["invuln_", "feel_no_pain_"]
	for rule_id in auto_detected_rules.keys():
		var is_defender_rule = false
		for prefix in defender_rule_prefixes:
			if rule_id.begins_with(prefix):
				is_defender_rule = true
				break
		if is_defender_rule and auto_detected_rules[rule_id]:
			_set_rule_toggle(rule_id, false, false)
			auto_detected_rules.erase(rule_id)

	# Check model data for invulnerable saves
	var models = unit.get("models", [])
	if not models.is_empty():
		var invuln = models[0].get("invuln", 0)
		if typeof(invuln) == TYPE_STRING and invuln.is_valid_int():
			invuln = int(invuln)
		if invuln > 0 and invuln <= 6:
			var invuln_rule_id = "invuln_%d" % invuln
			if rule_toggles.has(invuln_rule_id):
				auto_detected_rules[invuln_rule_id] = true
				_set_rule_toggle(invuln_rule_id, true, true)
				print("MathhammerUI: Auto-detected defender invuln save: %s" % invuln_rule_id)

	# Check abilities for Feel No Pain
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_rules = MathhammerRuleModifiers._parse_ability_rules(ability)
		for rule_id in ability_rules:
			if rule_id.begins_with("feel_no_pain_"):
				auto_detected_rules[rule_id] = true
				_set_rule_toggle(rule_id, true, true)
				print("MathhammerUI: Auto-detected defender ability: %s" % rule_id)

func _set_rule_toggle(rule_id: String, enabled: bool, is_auto: bool) -> void:
	# Set a rule toggle checkbox and update the rule_toggles dictionary
	rule_toggles[rule_id] = enabled

	# Find and update the corresponding checkbox in the UI using rule_id metadata
	for child in rule_toggles_panel.get_children():
		if child is CheckBox and child.has_meta("rule_id") and child.get_meta("rule_id") == rule_id:
			# Block signals temporarily to avoid triggering _on_rule_toggled
			child.set_block_signals(true)
			child.button_pressed = enabled
			child.set_block_signals(false)
			# Update tooltip to indicate auto-detection
			if is_auto and enabled:
				var base_tooltip = child.tooltip_text
				if not base_tooltip.ends_with("[Auto-detected]"):
					child.tooltip_text = base_tooltip + " [Auto-detected]"
			elif not enabled:
				child.tooltip_text = child.tooltip_text.replace(" [Auto-detected]", "")
			break

func _on_weapon_attack_count_changed(value: float, weapon_key: String) -> void:
	if selected_weapons.has(weapon_key):
		selected_weapons[weapon_key]["attack_count"] = int(value)
		print("MathhammerUI: Weapon attack count changed - %s: %d" % [weapon_key, int(value)])

func _on_rule_toggled(rule_id: String, active: bool) -> void:
	rule_toggles[rule_id] = active
	# If user manually toggles a rule, clear its auto-detected status
	if auto_detected_rules.has(rule_id):
		auto_detected_rules.erase(rule_id)
		# Clean up tooltip using rule_id metadata
		for child in rule_toggles_panel.get_children():
			if child is CheckBox and child.has_meta("rule_id") and child.get_meta("rule_id") == rule_id:
				child.tooltip_text = child.tooltip_text.replace(" [Auto-detected]", "")
				break
	print("MathhammerUI: Rule toggle changed - %s: %s (manual)" % [rule_id, active])

func _get_selected_phase() -> String:
	if phase_toggle and phase_toggle.selected >= 0:
		return phase_toggle.get_item_metadata(phase_toggle.selected)
	return "shooting"

func _on_phase_changed(_index: int) -> void:
	var phase = _get_selected_phase()
	print("MathhammerUI: Phase changed to: %s" % phase)
	# Refresh weapon selection to show only relevant weapons for the phase
	_update_weapon_selection()
	# Update rule toggles visibility based on phase
	_update_rule_toggles_for_phase()

func _on_attacker_attack_count_changed(value: float, unit_id: String) -> void:
	selected_attackers[unit_id] = int(value)
	print("MathhammerUI: Attacker attack count changed - %s: %d" % [unit_id, int(value)])
	_update_weapon_selection()

func _on_attacker_toggled(unit_id: String, enabled: bool) -> void:
	# Legacy function for compatibility
	selected_attackers[unit_id] = 1 if enabled else 0
	print("MathhammerUI: Attacker toggled - %s: %s" % [unit_id, enabled])
	_update_weapon_selection()

func _on_attacker_selection_changed(_index: int) -> void:
	# Legacy function for compatibility
	pass

func _on_unit_selection_changed(_index: int) -> void:
	var attacker_id = ""
	var defender_id = ""

	if attacker_selector.selected >= 0:
		attacker_id = attacker_selector.get_item_metadata(attacker_selector.selected)

	if defender_selector.selected >= 0:
		defender_id = defender_selector.get_item_metadata(defender_selector.selected)

	# Auto-populate override fields with selected defender's actual stats
	_populate_override_from_defender(defender_id)

	# Auto-detect defender abilities (invuln saves, FNP)
	_auto_detect_defender_rules(defender_id)

	emit_signal("unit_selection_changed", attacker_id, defender_id)

func _create_defender_override_fields() -> void:
	# Helper to create a labeled spinbox row
	var fields = [
		{"label": "Toughness (T):", "min": 1, "max": 14, "default": 4, "field": "toughness"},
		{"label": "Armor Save (Sv):", "min": 2, "max": 7, "default": 3, "field": "save"},
		{"label": "Wounds (W):", "min": 1, "max": 30, "default": 1, "field": "wounds"},
		{"label": "Models:", "min": 1, "max": 30, "default": 1, "field": "model_count"},
		{"label": "Invuln Save:", "min": 0, "max": 6, "default": 0, "field": "invuln"},
		{"label": "Feel No Pain:", "min": 0, "max": 6, "default": 0, "field": "fnp"},
	]

	for field_def in fields:
		var row = HBoxContainer.new()
		var label = Label.new()
		label.text = field_def.label
		label.custom_minimum_size.x = 120
		label.add_theme_font_size_override("font_size", 12)
		row.add_child(label)

		var spinbox = SpinBox.new()
		spinbox.min_value = field_def.min
		spinbox.max_value = field_def.max
		spinbox.value = field_def.default
		spinbox.step = 1
		spinbox.custom_minimum_size.x = 80
		spinbox.add_theme_font_size_override("font_size", 11)
		row.add_child(spinbox)

		# Add hint for 0 = none fields
		if field_def.field == "invuln" or field_def.field == "fnp":
			var hint = Label.new()
			hint.text = " (0 = none)"
			hint.add_theme_font_size_override("font_size", 10)
			hint.add_theme_color_override("font_color", Color.GRAY)
			row.add_child(hint)

		defender_override_panel.add_child(row)

		# Store references to spinboxes
		match field_def.field:
			"toughness":
				override_toughness_spinbox = spinbox
			"save":
				override_save_spinbox = spinbox
			"wounds":
				override_wounds_spinbox = spinbox
			"model_count":
				override_model_count_spinbox = spinbox
			"invuln":
				override_invuln_spinbox = spinbox
			"fnp":
				override_fnp_spinbox = spinbox

	# Add note about overrides
	var note = Label.new()
	note.text = "Overrides replace defender's unit stats for simulation"
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color.GRAY)
	defender_override_panel.add_child(note)

func _on_defender_override_toggled(enabled: bool) -> void:
	print("MathhammerUI: Defender override toggled: %s" % enabled)
	defender_override_panel.visible = enabled
	# Auto-populate from selected defender when enabling
	if enabled and defender_selector.selected >= 0:
		var defender_id = defender_selector.get_item_metadata(defender_selector.selected)
		_populate_override_from_defender(defender_id)

func _populate_override_from_defender(defender_id: String) -> void:
	if defender_id == "" or not GameState:
		return
	var unit = GameState.get_unit(defender_id)
	if unit.is_empty():
		return
	var stats = unit.get("meta", {}).get("stats", {})
	var models = unit.get("models", [])

	if override_toughness_spinbox:
		override_toughness_spinbox.value = stats.get("toughness", 4)
	if override_save_spinbox:
		override_save_spinbox.value = stats.get("save", 3)
	if override_wounds_spinbox and not models.is_empty():
		override_wounds_spinbox.value = models[0].get("wounds", 1)
	if override_model_count_spinbox:
		override_model_count_spinbox.value = models.size()
	if override_invuln_spinbox and not models.is_empty():
		override_invuln_spinbox.value = models[0].get("invuln", 0)
	if override_fnp_spinbox:
		override_fnp_spinbox.value = stats.get("fnp", 0)

	print("MathhammerUI: Populated override fields from %s — T:%d Sv:%d+ W:%d Models:%d Invuln:%d FNP:%d" % [
		defender_id, int(override_toughness_spinbox.value), int(override_save_spinbox.value),
		int(override_wounds_spinbox.value), int(override_model_count_spinbox.value),
		int(override_invuln_spinbox.value), int(override_fnp_spinbox.value)])

func _on_run_simulation_pressed() -> void:
	var defender_id = ""
	
	if defender_selector.selected >= 0:
		defender_id = defender_selector.get_item_metadata(defender_selector.selected)
	
	if defender_id == "":
		_show_error("Please select a defender unit")
		return
	
	# Check that at least one attacker has attacks > 0
	var selected_attacker_ids = []
	for unit_id in selected_attackers:
		if selected_attackers[unit_id] > 0:
			selected_attacker_ids.append(unit_id)
	
	if selected_attacker_ids.is_empty():
		_show_error("Please set at least one attacker unit with attack count > 0")
		return
	
	# Check that selected attackers don't include the defender
	if defender_id in selected_attacker_ids:
		_show_error("Defender unit cannot also be an attacker")
		return
	
	# Check that at least one weapon has attacks > 0
	var has_active_weapon = false
	for weapon_key in selected_weapons:
		var weapon_data = selected_weapons[weapon_key]
		if weapon_data.get("attack_count", 0) > 0:
			has_active_weapon = true
			break
	
	if not has_active_weapon:
		_show_error("Please configure at least one weapon with attack count > 0")
		return
	
	# Build simulation configuration with multiple attackers
	var attackers = []
	for unit_id in selected_attacker_ids:
		var unit_attack_count = selected_attackers.get(unit_id, 0)
		print("MathhammerUI: Unit %s is making %d attacks" % [unit_id, unit_attack_count])
		
		# Add the unit multiple times based on attack count
		for i in range(unit_attack_count):
			var attacker_config = _build_attacker_config(unit_id)
			if not attacker_config.weapons.is_empty():
				attackers.append(attacker_config)
	
	if attackers.is_empty():
		_show_error("No valid attacker configurations found")
		return
	
	var config = {
		"trials": int(trials_spinbox.value),
		"attackers": attackers,
		"defender": _build_defender_config(defender_id),
		"rule_toggles": rule_toggles.duplicate(),
		"phase": _get_selected_phase()
	}
	
	# Validate configuration
	var validation = Mathhammer.validate_simulation_config(config)
	if not validation.valid:
		_show_error("Configuration error: " + "\n".join(validation.errors))
		return
	
	# Run simulation
	print("MathhammerUI: Running simulation with config: ", config)
	_run_simulation_async(config)

func _build_attacker_config(unit_id: String) -> Dictionary:
	var unit = GameState.get_unit(unit_id)
	var weapons = []
	var models = unit.get("models", [])
	
	# Find all weapons for this unit that have attack count > 0
	for weapon_key in selected_weapons:
		var weapon_data = selected_weapons[weapon_key]
		
		# Only include weapons belonging to this unit with attack count > 0
		if weapon_data.get("unit_id", "") == unit_id and weapon_data.get("attack_count", 0) > 0:
			# Build model IDs for this weapon
			var model_ids = []
			for model in models:
				model_ids.append(model.get("id", "m%d" % (model_ids.size() + 1)))
			
			# Get the actual weapon data to generate proper weapon ID
			var weapon_meta = weapon_data.get("weapon_data", {})
			var weapon_name = weapon_meta.get("name", "")
			
			# Generate weapon ID the same way RulesEngine does
			var weapon_id = weapon_name.to_lower()
			weapon_id = weapon_id.replace(" ", "_")
			weapon_id = weapon_id.replace("-", "_")
			weapon_id = weapon_id.replace("'", "")
			
			print("MathhammerUI: Using weapon '%s' with ID '%s' for %d attacks" % [weapon_name, weapon_id, weapon_data.get("attack_count", 1)])
			
			weapons.append({
				"weapon_id": weapon_id,
				"model_ids": model_ids,
				"attacks": weapon_data.get("attack_count", 1)
			})
	
	return {
		"unit_id": unit_id,
		"weapons": weapons
	}

func _build_defender_config(unit_id: String) -> Dictionary:
	var config = {
		"unit_id": unit_id
	}

	# Include custom defender stat overrides if enabled
	if defender_override_checkbox and defender_override_checkbox.button_pressed:
		config["overrides"] = {
			"toughness": int(override_toughness_spinbox.value),
			"save": int(override_save_spinbox.value),
			"wounds": int(override_wounds_spinbox.value),
			"model_count": int(override_model_count_spinbox.value),
			"invuln": int(override_invuln_spinbox.value),
			"fnp": int(override_fnp_spinbox.value),
		}
		print("MathhammerUI: Defender config with overrides: %s" % str(config))

	return config

func _run_simulation_async(config: Dictionary) -> void:
	# Clean up any previous thread before starting a new one
	if _simulation_thread != null and _simulation_thread.is_started():
		print("MathhammerUI: Waiting for previous simulation thread to finish...")
		_simulation_thread.wait_to_finish()

	run_simulation_button.disabled = true
	run_simulation_button.text = "Running..."

	# Run simulation on a background thread to avoid freezing the UI (T3-25)
	print("MathhammerUI: Starting simulation on background thread...")
	_simulation_thread = Thread.new()
	_simulation_thread.start(_simulation_thread_func.bind(config))

func _simulation_thread_func(config: Dictionary) -> void:
	# This runs on a background thread — no UI access allowed here
	print("MathhammerUI: Background thread started, running simulation...")
	var result = Mathhammer.simulate_combat(config)
	print("MathhammerUI: Background thread simulation complete, result type: %s" % typeof(result))
	# Defer UI update back to the main thread
	call_deferred("_on_simulation_completed", result)

func _on_simulation_completed(result: Mathhammer.SimulationResult) -> void:
	# This runs on the main thread via call_deferred — safe to update UI
	print("MathhammerUI: Simulation completed callback on main thread")

	# Join the background thread to clean up resources
	if _simulation_thread != null and _simulation_thread.is_started():
		_simulation_thread.wait_to_finish()
		print("MathhammerUI: Background thread joined successfully")

	current_simulation_result = result

	# Update UI with results
	print("MathhammerUI: About to display results...")
	_display_simulation_results(result)
	print("MathhammerUI: Results display completed")

	run_simulation_button.disabled = false
	run_simulation_button.text = "Run Simulation"

func _display_simulation_results(result: Mathhammer.SimulationResult) -> void:
	print("MathhammerUI: _display_simulation_results called")
	if not result:
		print("MathhammerUI: No result data provided")
		return
	
	print("MathhammerUI: Result has %d trials, %d detailed trials" % [result.trials_run, result.detailed_trials.size()])
	
	# Debug panel states BEFORE clearing
	print("MathhammerUI: Debugging panel states BEFORE...")
	print("MathhammerUI: summary_panel exists: %s" % str(summary_panel != null))
	print("MathhammerUI: breakdown_panel exists: %s" % str(breakdown_panel != null))
	if summary_panel:
		print("MathhammerUI: summary_panel visible: %s, child_count: %d" % [summary_panel.visible, summary_panel.get_child_count()])
	if breakdown_panel:
		print("MathhammerUI: breakdown_panel visible: %s, child_count: %d" % [breakdown_panel.visible, breakdown_panel.get_child_count()])
	
	# Clear existing results first, but don't hide the original label yet
	_clear_results_display()
	print("MathhammerUI: Cleared existing results")
	
	# Debug panel states AFTER clearing
	print("MathhammerUI: Debugging panel states AFTER clearing...")
	if summary_panel:
		print("MathhammerUI: summary_panel after clear - visible: %s, child_count: %d" % [summary_panel.visible, summary_panel.get_child_count()])
	if breakdown_panel:
		print("MathhammerUI: breakdown_panel after clear - visible: %s, child_count: %d" % [breakdown_panel.visible, breakdown_panel.get_child_count()])
	
	# Create comprehensive results display
	_create_detailed_results_display(result)
	print("MathhammerUI: Created detailed results display")
	
	# Debug final states
	print("MathhammerUI: Final debugging...")
	if summary_panel:
		print("MathhammerUI: summary_panel final child_count: %d" % summary_panel.get_child_count())
		for i in range(summary_panel.get_child_count()):
			var child = summary_panel.get_child(i)
			print("MathhammerUI: summary_panel child %d: %s (visible: %s)" % [i, child.name, child.visible])
	if breakdown_panel:
		print("MathhammerUI: breakdown_panel final child_count: %d" % breakdown_panel.get_child_count())
		for i in range(breakdown_panel.get_child_count()):
			var child = breakdown_panel.get_child(i)
			print("MathhammerUI: breakdown_panel child %d: %s (visible: %s)" % [i, child.name, child.visible])

func _create_histogram_bars(parent: VBoxContainer, result: Mathhammer.SimulationResult) -> void:
	# Visual graphical histogram — replaces old text-based _draw_simple_histogram (T5-MH1)
	if result.damage_distribution.is_empty() or result.trials_run == 0:
		return

	print("MathhammerUI: Creating visual histogram with %d damage values" % result.damage_distribution.size())

	# Sort damage keys numerically
	var sorted_damages = result.damage_distribution.keys()
	sorted_damages.sort_custom(func(a, b): return int(a) < int(b))

	# Calculate percentages and find max for scaling
	var max_percentage := 0.0
	var bar_data := []
	for damage_key in sorted_damages:
		var count = result.damage_distribution[damage_key]
		var pct = (float(count) / result.trials_run) * 100.0
		bar_data.append({"damage": damage_key, "percentage": pct})
		if pct > max_percentage:
			max_percentage = pct

	# If too many values, filter out very low probabilities to keep chart readable
	var max_bars := 25
	if bar_data.size() > max_bars:
		var filtered = bar_data.filter(func(d): return d.percentage >= 0.5)
		if filtered.size() > max_bars:
			filtered.sort_custom(func(a, b): return a.percentage > b.percentage)
			filtered = filtered.slice(0, max_bars)
			filtered.sort_custom(func(a, b): return int(a.damage) < int(b.damage))
		if not filtered.is_empty():
			bar_data = filtered

	# Create the histogram container
	var chart_container = VBoxContainer.new()
	chart_container.add_theme_constant_override("separation", 2)
	parent.add_child(chart_container)

	# Chart subtitle
	var chart_title = Label.new()
	chart_title.text = "Probability by Damage"
	chart_title.add_theme_font_size_override("font_size", 11)
	chart_title.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	chart_container.add_child(chart_title)

	# Max bar width in pixels
	var max_bar_width := 200.0

	for entry in bar_data:
		var bar_row = HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 4)
		chart_container.add_child(bar_row)

		# Damage value label (right-aligned, fixed width)
		var dmg_label = Label.new()
		dmg_label.text = str(entry.damage)
		dmg_label.custom_minimum_size.x = 30
		dmg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dmg_label.add_theme_font_size_override("font_size", 9)
		dmg_label.add_theme_color_override("font_color", Color.WHITE)
		bar_row.add_child(dmg_label)

		# Graphical bar (ColorRect with proportional width)
		var bar_width = (entry.percentage / max_percentage) * max_bar_width if max_percentage > 0 else 0.0
		bar_width = max(bar_width, 2.0)  # Minimum visible width

		var bar = ColorRect.new()
		bar.custom_minimum_size = Vector2(bar_width, 14)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bar.color = _get_histogram_bar_color(entry.percentage, max_percentage)
		bar_row.add_child(bar)

		# Percentage label
		var pct_label = Label.new()
		pct_label.text = "%.1f%%" % entry.percentage
		pct_label.custom_minimum_size.x = 45
		pct_label.add_theme_font_size_override("font_size", 9)
		pct_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
		bar_row.add_child(pct_label)

	# Separator before percentile stats
	var sep = HSeparator.new()
	chart_container.add_child(sep)

	print("MathhammerUI: Visual histogram created with %d bars" % bar_data.size())

func _get_histogram_bar_color(percentage: float, max_percentage: float) -> Color:
	# Color gradient: Red (low probability) -> Yellow (medium) -> Green (high probability)
	var ratio = percentage / max_percentage if max_percentage > 0 else 0.0
	var red = Color(0.9, 0.25, 0.2)
	var yellow = Color(0.95, 0.8, 0.2)
	var green = Color(0.3, 0.75, 0.3)
	if ratio < 0.5:
		return red.lerp(yellow, ratio * 2.0)
	else:
		return yellow.lerp(green, (ratio - 0.5) * 2.0)

func _clear_results_display() -> void:
	print("MathhammerUI: Clearing results display")
	# Clear all children from results panels except the titles
	if summary_panel:
		print("MathhammerUI: Summary panel has %d children" % summary_panel.get_child_count())
		for child in summary_panel.get_children():
			if child.name.begins_with("Results") or child.name == "InitialResultsLabel":
				print("MathhammerUI: Removing child: %s" % child.name)
				child.queue_free()
	
	if distribution_panel:
		for child in distribution_panel.get_children():
			if child.name.begins_with("DetailedResults"):
				child.queue_free()
	
	# Also hide/clear the breakdown_text placeholder
	if breakdown_text and is_instance_valid(breakdown_text):
		breakdown_text.visible = false
		print("MathhammerUI: Hidden breakdown_text placeholder")
	
	# Clear any existing detailed breakdowns from breakdown_panel
	if breakdown_panel:
		print("MathhammerUI: Breakdown panel has %d children" % breakdown_panel.get_child_count())
		for child in breakdown_panel.get_children():
			if child.name.begins_with("DetailedBreakdown") or child == breakdown_text:
				print("MathhammerUI: Removing breakdown child: %s" % child.name)
				child.queue_free()
	
	print("MathhammerUI: Finished clearing results display")

func _create_detailed_results_display(result: Mathhammer.SimulationResult) -> void:
	print("MathhammerUI: Creating detailed results display")
	# Create main results scroll container
	var results_scroll = ScrollContainer.new()
	results_scroll.name = "ResultsScroll"
	results_scroll.custom_minimum_size = Vector2(380, 300)
	results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	if not summary_panel:
		print("MathhammerUI: ERROR - summary_panel is null!")
		return
		
	summary_panel.add_child(results_scroll)
	print("MathhammerUI: Added results_scroll to summary_panel")
	
	var results_vbox = VBoxContainer.new()
	results_vbox.name = "ResultsVBox"
	results_vbox.add_theme_constant_override("separation", 15)
	results_scroll.add_child(results_vbox)
	print("MathhammerUI: Created results_vbox")
	
	# Overall Statistics Panel
	_create_overall_stats_panel(results_vbox, result)
	print("MathhammerUI: Created overall stats panel")
	
	# Weapon Breakdown Panel
	_create_weapon_breakdown_panel(results_vbox, result)
	print("MathhammerUI: Created weapon breakdown panel")
	
	# Damage Distribution Panel
	_create_damage_distribution_panel(results_vbox, result)
	print("MathhammerUI: Created damage distribution panel")
	
	# Also add the weapon breakdown to the separate breakdown_panel
	_populate_breakdown_panel(result)
	print("MathhammerUI: Populated breakdown panel")

func _create_overall_stats_panel(parent: VBoxContainer, result: Mathhammer.SimulationResult) -> void:
	print("MathhammerUI: Creating overall stats panel")
	var stats_panel = create_styled_panel("Overall Statistics", Color(0.2, 0.3, 0.5, 0.8))
	if not stats_panel:
		print("MathhammerUI: ERROR - failed to create stats_panel!")
		return
	print("MathhammerUI: About to add stats_panel to parent")
	print("MathhammerUI: stats_panel valid: %s" % str(stats_panel != null))
	print("MathhammerUI: parent valid: %s" % str(parent != null))
	print("MathhammerUI: parent type: %s" % parent.get_class() if parent else "null")
	print("MathhammerUI: parent child_count before: %d" % parent.get_child_count())
	parent.add_child(stats_panel)
	print("MathhammerUI: Added stats_panel to parent, parent child_count after: %d" % parent.get_child_count())

	var stats_content = stats_panel.get_meta("content_vbox")
	var stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 8)
	stats_content.add_child(stats_grid)
	
	# Add key statistics
	add_stat_row(stats_grid, "Trials Run:", "%d" % result.trials_run)
	add_stat_row(stats_grid, "Average Damage:", "%.2f wounds" % result.get_average_damage(), Color.YELLOW)
	add_stat_row(stats_grid, "Median Damage:", "%d wounds" % result.get_damage_percentile(0.5))
	add_stat_row(stats_grid, "Kill Probability:", "%.1f%%" % (result.kill_probability * 100), Color.RED)
	add_stat_row(stats_grid, "Expected Survivors:", "%.2f models" % result.expected_survivors, Color.GREEN)
	add_stat_row(stats_grid, "Damage Efficiency:", "%.1f%%" % (result.damage_efficiency * 100), Color.CYAN)

func _create_weapon_breakdown_panel(parent: VBoxContainer, result: Mathhammer.SimulationResult) -> void:
	if result.detailed_trials.is_empty():
		return
	
	var weapon_panel = create_styled_panel("Weapon Breakdown", Color(0.5, 0.2, 0.2, 0.8))
	parent.add_child(weapon_panel)
	var weapon_content = weapon_panel.get_meta("content_vbox")

	# Aggregate weapon stats
	var weapon_totals = {}
	for trial in result.detailed_trials:
		for weapon_id in trial.get("weapon_breakdown", {}):
			if not weapon_totals.has(weapon_id):
				weapon_totals[weapon_id] = {
					"attacks_made": 0,
					"hits": 0,
					"wounds": 0,
					"saves_failed": 0,
					"damage": 0,
					"weapon_name": trial.weapon_breakdown[weapon_id].weapon_name
				}
			var wb = trial.weapon_breakdown[weapon_id]
			weapon_totals[weapon_id].attacks_made += wb.attacks_made
			weapon_totals[weapon_id].hits += wb.hits
			weapon_totals[weapon_id].wounds += wb.wounds
			weapon_totals[weapon_id].saves_failed += wb.saves_failed
			weapon_totals[weapon_id].damage += wb.damage
	
	# Create weapon breakdown display
	var weapon_count = 0
	for weapon_id in weapon_totals:
		weapon_count += 1
		var stats = weapon_totals[weapon_id]
		
		# Calculate percentages
		var hit_rate = (float(stats.hits) / float(stats.attacks_made) * 100.0) if stats.attacks_made > 0 else 0.0
		var wound_rate = (float(stats.wounds) / float(stats.hits) * 100.0) if stats.hits > 0 else 0.0
		var unsaved_rate = (float(stats.saves_failed) / float(stats.wounds) * 100.0) if stats.wounds > 0 else 0.0
		var avg_damage_per_trial = float(stats.damage) / float(result.trials_run)
		
		# Create weapon subsection
		var weapon_section = create_weapon_section(weapon_count, stats.weapon_name, stats, hit_rate, wound_rate, unsaved_rate, avg_damage_per_trial, result.trials_run)
		weapon_content.add_child(weapon_section)

func _create_damage_distribution_panel(parent: VBoxContainer, result: Mathhammer.SimulationResult) -> void:
	var dist_panel = create_styled_panel("Damage Distribution", Color(0.2, 0.5, 0.2, 0.8))
	parent.add_child(dist_panel)
	var dist_content = dist_panel.get_meta("content_vbox")

	# Visual histogram bars (T5-MH1: graphical bars replace text bars)
	_create_histogram_bars(dist_content, result)

	# Percentile summary statistics
	var stats = result.statistical_summary
	var dist_grid = GridContainer.new()
	dist_grid.columns = 2
	dist_grid.add_theme_constant_override("h_separation", 20)
	dist_grid.add_theme_constant_override("v_separation", 6)
	dist_content.add_child(dist_grid)

	add_stat_row(dist_grid, "25th Percentile:", "%d wounds" % stats.get("percentile_25", 0))
	add_stat_row(dist_grid, "75th Percentile:", "%d wounds" % stats.get("percentile_75", 0))
	add_stat_row(dist_grid, "95th Percentile:", "%d wounds" % stats.get("percentile_95", 0))
	add_stat_row(dist_grid, "Maximum Damage:", "%d wounds" % stats.get("max_damage", 0))

func create_styled_panel(title: String, bg_color: Color) -> VBoxContainer:
	print("MathhammerUI: create_styled_panel called for title: %s" % title)
	var panel_container = VBoxContainer.new()
	panel_container.add_theme_constant_override("separation", 8)
	print("MathhammerUI: Created panel_container: %s" % str(panel_container != null))

	# Add background
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = bg_color
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 8
	style_box.content_margin_bottom = 8

	var panel_bg = PanelContainer.new()
	panel_bg.add_theme_stylebox_override("panel", style_box)
	panel_container.add_child(panel_bg)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 6)
	panel_bg.add_child(content_vbox)

	# Title
	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	content_vbox.add_child(title_label)

	# Store content_vbox reference so callers can add children inside the styled panel
	panel_container.set_meta("content_vbox", content_vbox)

	print("MathhammerUI: create_styled_panel returning panel_container with content_vbox inside")
	return panel_container

func _populate_breakdown_panel(result: Mathhammer.SimulationResult) -> void:
	print("MathhammerUI: _populate_breakdown_panel called")
	if not breakdown_panel:
		print("MathhammerUI: ERROR - No breakdown_panel found")
		return
	
	print("MathhammerUI: breakdown_panel exists, current child_count: %d" % breakdown_panel.get_child_count())
	
	# Clear the breakdown_text placeholder if it still exists
	if breakdown_text and is_instance_valid(breakdown_text):
		print("MathhammerUI: Removing old breakdown_text placeholder")
		breakdown_text.queue_free()
		breakdown_text = null
	
	# Create comprehensive breakdown display
	var breakdown_scroll = ScrollContainer.new()
	breakdown_scroll.name = "DetailedBreakdownScroll"
	breakdown_scroll.custom_minimum_size = Vector2(350, 300)
	breakdown_scroll.visible = true
	print("MathhammerUI: Created breakdown scroll container")
	breakdown_panel.add_child(breakdown_scroll)
	print("MathhammerUI: Added scroll container to breakdown_panel")
	
	var breakdown_vbox = VBoxContainer.new()
	breakdown_vbox.name = "BreakdownVBox"
	breakdown_vbox.add_theme_constant_override("separation", 10)
	breakdown_vbox.visible = true
	breakdown_scroll.add_child(breakdown_vbox)
	print("MathhammerUI: Created and added breakdown vbox")
	
	# Overall Stats Section
	print("MathhammerUI: Adding overall stats section to breakdown")
	_create_overall_stats_panel(breakdown_vbox, result)
	
	# Weapon Breakdown Section
	print("MathhammerUI: Adding weapon breakdown section to breakdown")
	_create_weapon_breakdown_panel(breakdown_vbox, result)
	
	# Damage Distribution Section
	print("MathhammerUI: Adding damage distribution section to breakdown")
	_create_damage_distribution_panel(breakdown_vbox, result)
	
	print("MathhammerUI: breakdown_panel final child_count after population: %d" % breakdown_panel.get_child_count())
	print("MathhammerUI: breakdown_scroll child_count: %d" % breakdown_scroll.get_child_count())
	print("MathhammerUI: breakdown_vbox child_count: %d" % breakdown_vbox.get_child_count())
	print("MathhammerUI: Added detailed breakdown to breakdown_panel")

func create_weapon_section(weapon_num: int, weapon_name: String, stats: Dictionary, hit_rate: float, wound_rate: float, unsaved_rate: float, avg_dmg: float, trials: int) -> VBoxContainer:
	var weapon_vbox = VBoxContainer.new()
	weapon_vbox.add_theme_constant_override("separation", 4)
	
	# Weapon header
	var header_label = Label.new()
	header_label.text = "[Weapon %d] %s" % [weapon_num, weapon_name]
	header_label.add_theme_font_size_override("font_size", 12)
	header_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	weapon_vbox.add_child(header_label)
	
	# Stats grid
	var weapon_grid = GridContainer.new()
	weapon_grid.columns = 2
	weapon_grid.add_theme_constant_override("h_separation", 15)
	weapon_grid.add_theme_constant_override("v_separation", 3)
	weapon_vbox.add_child(weapon_grid)
	
	add_stat_row(weapon_grid, "  Total Attacks:", "%d" % stats.attacks_made)
	add_stat_row(weapon_grid, "  Avg Attacks/Trial:", "%.1f" % (float(stats.attacks_made) / float(trials)))
	add_stat_row(weapon_grid, "  Hits:", "%d (%.1f%%)" % [stats.hits, hit_rate])
	add_stat_row(weapon_grid, "  Wounds:", "%d (%.1f%% of hits)" % [stats.wounds, wound_rate])
	add_stat_row(weapon_grid, "  Unsaved:", "%d (%.1f%% of wounds)" % [stats.saves_failed, unsaved_rate])
	add_stat_row(weapon_grid, "  Total Damage:", "%d wounds" % stats.damage)
	add_stat_row(weapon_grid, "  Avg Damage/Trial:", "%.2f wounds" % avg_dmg)
	
	# Add separator
	var separator = HSeparator.new()
	weapon_vbox.add_child(separator)
	
	return weapon_vbox

func add_stat_row(grid: GridContainer, label_text: String, value_text: String, value_color: Color = Color.WHITE) -> void:
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	grid.add_child(label)
	
	var value = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 10)
	value.add_theme_color_override("font_color", value_color)
	grid.add_child(value)

func _show_error(message: String) -> void:
	print("MathhammerUI Error: ", message)
	if results_label:
		results_label.text = "[color=red][b]Error:[/b] " + message + "[/color]"

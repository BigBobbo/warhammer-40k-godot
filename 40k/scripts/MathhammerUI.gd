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
var compare_weapons_button: Button
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

# Progress indicator UI elements (T5-MH7)
var _progress_container: VBoxContainer = null
var _progress_bar: ProgressBar = null
var _progress_label: Label = null

# Responsive sizing - viewport-relative panel dimensions (T5-MH6)
var _viewport_size: Vector2 = Vector2(1280, 1024)  # Fallback default

# Signals
signal simulation_requested(config: Dictionary)
signal unit_selection_changed(attacker_id: String, defender_id: String)

func _ready() -> void:
	print("MathhammerUI: Initializing...")

	_update_viewport_size()
	_setup_ui_structure()
	_setup_controls()
	_connect_signals()
	_populate_unit_selectors()
	_populate_rule_toggles()

	# Connect to viewport size changes for responsive layout (T5-MH6)
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	# Start collapsed following UnitStatsPanel pattern
	is_collapsed = true
	set_collapsed(false)  # Start expanded to show functionality

func _exit_tree() -> void:
	# Clean up background simulation thread on node removal (T3-25)
	if _simulation_thread != null and _simulation_thread.is_started():
		print("MathhammerUI: Waiting for simulation thread to finish before exit...")
		_simulation_thread.wait_to_finish()

# --- Responsive sizing helpers (T5-MH6) ---

func _update_viewport_size() -> void:
	var vp = get_viewport()
	if vp:
		_viewport_size = vp.get_visible_rect().size
		if _viewport_size.x < 1 or _viewport_size.y < 1:
			_viewport_size = Vector2(1280, 1024)
	print("MathhammerUI: Viewport size = %s" % str(_viewport_size))

func _get_panel_width() -> float:
	return _viewport_size.x * 0.32  # ~31-32% of viewport width

func _get_scroll_height() -> float:
	return _viewport_size.y * 0.58  # ~58% of viewport height

func _get_expanded_height() -> float:
	return _viewport_size.y * 0.39  # ~39% of viewport height for expanded panel

func _get_content_width() -> float:
	return _get_panel_width() * 0.88  # Content area slightly narrower than panel

func _get_results_scroll_height() -> float:
	return _viewport_size.y * 0.29  # ~29% of viewport height

func _get_breakdown_scroll_height() -> float:
	return _viewport_size.y * 0.29  # ~29% of viewport height

func _get_comparison_scroll_height() -> float:
	return _viewport_size.y * 0.39  # ~39% of viewport height

func _on_viewport_size_changed() -> void:
	_update_viewport_size()
	_apply_responsive_sizes()
	print("MathhammerUI: Viewport resized, updated layout to %s" % str(_viewport_size))

func _apply_responsive_sizes() -> void:
	# Update main structural sizes based on current viewport
	var panel_w = _get_panel_width()
	var scroll_h = _get_scroll_height()
	var content_w = _get_content_width()
	var expanded_h = _get_expanded_height()

	if scroll_container:
		scroll_container.custom_minimum_size = Vector2(panel_w, scroll_h)

	if not is_collapsed:
		custom_minimum_size.y = expanded_h

	# Update results/distribution/breakdown minimum sizes
	if results_label and is_instance_valid(results_label):
		results_label.custom_minimum_size = Vector2(content_w, _viewport_size.y * 0.15)

	if distribution_panel:
		distribution_panel.custom_minimum_size = Vector2(content_w, _viewport_size.y * 0.20)

	if histogram_display:
		histogram_display.custom_minimum_size = Vector2(content_w, _viewport_size.y * 0.15)

	if breakdown_text and is_instance_valid(breakdown_text):
		breakdown_text.custom_minimum_size = Vector2(content_w, _viewport_size.y * 0.10)

# --- End responsive sizing helpers ---

func _setup_ui_structure() -> void:
	# Create the main UI structure programmatically if nodes don't exist
	if not toggle_button:
		_create_ui_structure()

func _create_ui_structure() -> void:
	# Set panel to use viewport-relative height (T5-MH6)
	custom_minimum_size.y = _get_expanded_height()
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

	# Scroll container for content - viewport-relative sizing (T5-MH6)
	scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer"
	scroll_container.custom_minimum_size = Vector2(_get_panel_width(), _get_scroll_height())
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

	# Compare weapons button (T5-MH3)
	compare_weapons_button = Button.new()
	compare_weapons_button.text = "Compare Weapons"
	compare_weapons_button.tooltip_text = "Run separate simulations for each weapon and compare results side-by-side"
	unit_selector.add_child(compare_weapons_button)

	# Progress indicator — hidden until simulation starts (T5-MH7)
	_progress_container = VBoxContainer.new()
	_progress_container.name = "ProgressContainer"
	_progress_container.add_theme_constant_override("separation", 4)
	_progress_container.visible = false
	unit_selector.add_child(_progress_container)

	_progress_label = Label.new()
	_progress_label.text = "Simulating..."
	_progress_label.add_theme_font_size_override("font_size", 11)
	_progress_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	_progress_container.add_child(_progress_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.custom_minimum_size = Vector2(0, 18)
	_progress_bar.show_percentage = false
	_progress_container.add_child(_progress_bar)

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
	results_label.custom_minimum_size = Vector2(_get_content_width(), _viewport_size.y * 0.15)
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
	distribution_panel.custom_minimum_size = Vector2(_get_content_width(), _viewport_size.y * 0.20)
	distribution_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(distribution_panel)
	
	histogram_display = Control.new()
	histogram_display.name = "HistogramDisplay"
	histogram_display.custom_minimum_size = Vector2(_get_content_width(), _viewport_size.y * 0.15)
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
	breakdown_text.custom_minimum_size = Vector2(_get_content_width(), _viewport_size.y * 0.10)
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

	if compare_weapons_button:
		compare_weapons_button.pressed.connect(_on_compare_weapons_pressed)

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
	var expanded_h = _get_expanded_height()
	var target_height = 40 if collapsed else expanded_h
	tween.tween_property(self, "custom_minimum_size:y", target_height, 0.3)

	# Animate offset to expand upward
	var target_offset = -40 if collapsed else -expanded_h
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
	compare_weapons_button.disabled = true

	# Show progress indicator (T5-MH7)
	_show_progress("Simulating... 0 / %d trials" % int(config.get("trials", 10000)), 0.0)

	# Run simulation on a background thread to avoid freezing the UI (T3-25)
	print("MathhammerUI: Starting simulation on background thread...")
	_simulation_thread = Thread.new()
	_simulation_thread.start(_simulation_thread_func.bind(config))

func _simulation_thread_func(config: Dictionary) -> void:
	# This runs on a background thread — no UI access allowed here
	print("MathhammerUI: Background thread started, running simulation...")
	var progress_cb = _create_progress_callback()
	var result = Mathhammer.simulate_combat(config, progress_cb)
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

	# Hide progress indicator (T5-MH7)
	_hide_progress()

	current_simulation_result = result

	# Update UI with results
	print("MathhammerUI: About to display results...")
	_display_simulation_results(result)
	print("MathhammerUI: Results display completed")

	run_simulation_button.disabled = false
	run_simulation_button.text = "Run Simulation"
	compare_weapons_button.disabled = false

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

func _draw_simple_histogram(result: Mathhammer.SimulationResult) -> void:
	# For now, create a simple text-based histogram
	# TODO: Implement custom drawing for visual histogram
	
	var histogram_text = "[b]Damage Distribution[/b]\n"
	var sorted_damages = result.damage_distribution.keys()
	sorted_damages.sort_custom(func(a, b): return int(a) < int(b))
	
	for damage_key in sorted_damages:
		var count = result.damage_distribution[damage_key]
		var percentage = (float(count) / result.trials_run) * 100
		var bar_length = int(percentage / 2)  # Scale for display
		var bar = "■".repeat(bar_length)
		
		histogram_text += "%s damage: %s %.1f%%\n" % [damage_key, bar, percentage]
	
	# Create a label for histogram if it doesn't exist
	var histogram_label = histogram_display.get_node_or_null("HistogramLabel")
	if not histogram_label:
		histogram_label = RichTextLabel.new()
		histogram_label.name = "HistogramLabel"
		histogram_label.bbcode_enabled = true
		histogram_label.custom_minimum_size = Vector2(_get_content_width(), _viewport_size.y * 0.15)
		histogram_display.add_child(histogram_label)
	
	histogram_label.text = histogram_text

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
	results_scroll.custom_minimum_size = Vector2(_get_panel_width() * 0.95, _get_results_scroll_height())
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

	# Cumulative Probability Panel (T5-MH2)
	_create_cumulative_probability_panel(results_vbox, result)
	print("MathhammerUI: Created cumulative probability panel")

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

func _create_cumulative_probability_panel(parent: VBoxContainer, result: Mathhammer.SimulationResult) -> void:
	# T5-MH2: "X% chance of at least N wounds" cumulative probability table
	var reverse_cumulative = MathhammerResults.calculate_reverse_cumulative(result)
	if reverse_cumulative.is_empty():
		return

	var cumul_panel = create_styled_panel("Cumulative Probability", Color(0.4, 0.25, 0.5, 0.8))
	parent.add_child(cumul_panel)
	var cumul_content = cumul_panel.get_meta("content_vbox")

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Chance of dealing at least N wounds"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	cumul_content.add_child(subtitle)

	# Determine which rows to display — show all values if <= 20 entries,
	# otherwise show key thresholds to keep the table manageable
	var rows_to_display = []
	if reverse_cumulative.size() <= 20:
		rows_to_display = reverse_cumulative
	else:
		# Show a sensible subset: first, last, and evenly spaced entries
		# plus key probability thresholds (90%, 75%, 50%, 25%, 10%)
		var target_probs = [0.90, 0.75, 0.50, 0.25, 0.10]
		var threshold_damages = {}

		# Walk from highest damage down to find the highest damage at each threshold
		var sorted_desc = reverse_cumulative.duplicate()
		sorted_desc.reverse()
		for entry in sorted_desc:
			for target in target_probs:
				if entry.probability >= target and not threshold_damages.has(target):
					threshold_damages[target] = entry.damage

		# Collect unique damage values to show
		var damage_set = {}
		# Always include first (min) and last (max) entries
		damage_set[reverse_cumulative[0].damage] = true
		damage_set[reverse_cumulative[-1].damage] = true
		# Include probability threshold entries
		for target in threshold_damages:
			damage_set[threshold_damages[target]] = true
		# Include evenly spaced entries (max ~15 total rows)
		var step = max(1, reverse_cumulative.size() / 12)
		var idx = 0
		while idx < reverse_cumulative.size():
			damage_set[reverse_cumulative[idx].damage] = true
			idx += step

		# Build filtered display rows preserving ascending damage order
		for entry in reverse_cumulative:
			if damage_set.has(entry.damage):
				rows_to_display.append(entry)

	# Create the table using a GridContainer
	var table_grid = GridContainer.new()
	table_grid.columns = 2
	table_grid.add_theme_constant_override("h_separation", 20)
	table_grid.add_theme_constant_override("v_separation", 4)
	cumul_content.add_child(table_grid)

	# Table header
	var header_wounds = Label.new()
	header_wounds.text = "At Least"
	header_wounds.add_theme_font_size_override("font_size", 11)
	header_wounds.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	table_grid.add_child(header_wounds)

	var header_prob = Label.new()
	header_prob.text = "Probability"
	header_prob.add_theme_font_size_override("font_size", 11)
	header_prob.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	table_grid.add_child(header_prob)

	# Table rows with color-coding based on probability
	for entry in rows_to_display:
		var damage_val = entry.damage
		var prob = entry.probability

		# Color-code: green for high probability, yellow for medium, red for low
		var row_color: Color
		if prob >= 0.75:
			row_color = Color(0.4, 1.0, 0.4)  # Green
		elif prob >= 0.50:
			row_color = Color(0.7, 1.0, 0.3)  # Yellow-green
		elif prob >= 0.25:
			row_color = Color(1.0, 0.9, 0.3)  # Yellow
		elif prob >= 0.10:
			row_color = Color(1.0, 0.6, 0.3)  # Orange
		else:
			row_color = Color(1.0, 0.4, 0.4)  # Red

		var wound_label = Label.new()
		if damage_val == 1:
			wound_label.text = "%d wound" % damage_val
		else:
			wound_label.text = "%d wounds" % damage_val
		wound_label.add_theme_font_size_override("font_size", 10)
		wound_label.add_theme_color_override("font_color", Color.WHITE)
		table_grid.add_child(wound_label)

		var prob_label = Label.new()
		prob_label.text = "%.1f%%" % (prob * 100.0)
		prob_label.add_theme_font_size_override("font_size", 10)
		prob_label.add_theme_color_override("font_color", row_color)
		table_grid.add_child(prob_label)

	print("MathhammerUI: Cumulative probability table created with %d rows" % rows_to_display.size())

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
	breakdown_scroll.custom_minimum_size = Vector2(_get_content_width(), _get_breakdown_scroll_height())
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

	# Cumulative Probability Section (T5-MH2)
	print("MathhammerUI: Adding cumulative probability section to breakdown")
	_create_cumulative_probability_panel(breakdown_vbox, result)

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

# === T5-MH3: Multi-weapon side-by-side comparison ===

func _on_compare_weapons_pressed() -> void:
	var defender_id = ""
	if defender_selector.selected >= 0:
		defender_id = defender_selector.get_item_metadata(defender_selector.selected)

	if defender_id == "":
		_show_error("Please select a defender unit")
		return

	# Collect all active weapons (attack count > 0)
	var active_weapons = []
	for weapon_key in selected_weapons:
		var weapon_info = selected_weapons[weapon_key]
		if weapon_info.get("attack_count", 0) > 0:
			active_weapons.append({
				"weapon_key": weapon_key,
				"unit_id": weapon_info.unit_id,
				"weapon_data": weapon_info.weapon_data,
				"weapon_index": weapon_info.weapon_index,
				"attack_count": weapon_info.attack_count
			})

	if active_weapons.size() < 2:
		_show_error("Select at least 2 weapons with attacks > 0 to compare")
		return

	# Build individual simulation configs — one per weapon
	var configs = []
	for weapon_info in active_weapons:
		var unit_id = weapon_info.unit_id
		var unit = GameState.get_unit(unit_id)
		var models = unit.get("models", [])
		var model_ids = []
		for model in models:
			model_ids.append(model.get("id", "m%d" % model_ids.size()))

		var weapon_meta = weapon_info.weapon_data
		var weapon_name = weapon_meta.get("name", "")
		var weapon_id = weapon_name.to_lower().replace(" ", "_").replace("-", "_").replace("'", "")

		var config = {
			"trials": int(trials_spinbox.value),
			"attackers": [{
				"unit_id": unit_id,
				"weapons": [{
					"weapon_id": weapon_id,
					"model_ids": model_ids,
					"attacks": weapon_info.attack_count
				}]
			}],
			"defender": _build_defender_config(defender_id),
			"rule_toggles": rule_toggles.duplicate(),
			"phase": _get_selected_phase()
		}

		configs.append({
			"config": config,
			"weapon_name": weapon_name,
			"weapon_data": weapon_meta
		})

	print("MathhammerUI: Starting weapon comparison with %d weapons" % configs.size())
	_run_weapon_comparison_async(configs)

func _run_weapon_comparison_async(configs: Array) -> void:
	if _simulation_thread != null and _simulation_thread.is_started():
		print("MathhammerUI: Waiting for previous simulation thread to finish...")
		_simulation_thread.wait_to_finish()

	run_simulation_button.disabled = true
	compare_weapons_button.disabled = true
	compare_weapons_button.text = "Comparing..."

	# Show progress indicator for comparison (T5-MH7)
	_show_progress("Comparing weapons... 0 / %d" % configs.size(), 0.0)

	print("MathhammerUI: Starting weapon comparison on background thread...")
	_simulation_thread = Thread.new()
	_simulation_thread.start(_weapon_comparison_thread_func.bind(configs))

func _weapon_comparison_thread_func(configs: Array) -> void:
	print("MathhammerUI: Comparison thread started, running %d simulations..." % configs.size())
	var results = []
	var total_weapons = configs.size()
	for i in range(total_weapons):
		var entry = configs[i]
		print("MathhammerUI: Running comparison simulation %d/%d: %s" % [i + 1, total_weapons, entry.weapon_name])
		# Update progress for each weapon in comparison (T5-MH7)
		var pct = float(i) / float(total_weapons) * 100.0
		call_deferred("_update_progress", "Comparing: %s (%d/%d)" % [entry.weapon_name, i + 1, total_weapons], pct)
		var result = Mathhammer.simulate_combat(entry.config)
		results.append({
			"weapon_name": entry.weapon_name,
			"weapon_data": entry.weapon_data,
			"result": result
		})
	print("MathhammerUI: Comparison thread complete")
	call_deferred("_on_weapon_comparison_completed", results)

func _on_weapon_comparison_completed(results: Array) -> void:
	print("MathhammerUI: Weapon comparison completed on main thread")

	if _simulation_thread != null and _simulation_thread.is_started():
		_simulation_thread.wait_to_finish()
		print("MathhammerUI: Comparison background thread joined successfully")

	# Hide progress indicator (T5-MH7)
	_hide_progress()

	_display_comparison_results(results)

	run_simulation_button.disabled = false
	compare_weapons_button.disabled = false
	compare_weapons_button.text = "Compare Weapons"

func _display_comparison_results(results: Array) -> void:
	print("MathhammerUI: Displaying comparison results for %d weapons" % results.size())
	_clear_results_display()

	if not summary_panel:
		return

	# Create comparison scroll container
	var comparison_scroll = ScrollContainer.new()
	comparison_scroll.name = "ResultsScroll"
	comparison_scroll.custom_minimum_size = Vector2(_get_panel_width() * 0.95, _get_comparison_scroll_height())
	comparison_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary_panel.add_child(comparison_scroll)

	var comparison_vbox = VBoxContainer.new()
	comparison_vbox.add_theme_constant_override("separation", 15)
	comparison_scroll.add_child(comparison_vbox)

	# Title panel
	var title_panel = create_styled_panel("Weapon Comparison", Color(0.4, 0.3, 0.15, 0.8))
	comparison_vbox.add_child(title_panel)
	var title_content = title_panel.get_meta("content_vbox")

	var subtitle = Label.new()
	subtitle.text = "Each weapon simulated independently against the same target"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	title_content.add_child(subtitle)

	# Compute stats for each weapon
	var weapon_stats_list = []
	for entry in results:
		var result = entry.result as Mathhammer.SimulationResult
		var weapon_data = entry.weapon_data

		# Aggregate per-weapon stats from trials
		var total_attacks = 0
		var total_hits = 0
		var total_wounds = 0
		var total_unsaved = 0

		for trial in result.detailed_trials:
			total_attacks += trial.attacks_made
			total_hits += trial.hits
			total_wounds += trial.wounds
			total_unsaved += trial.saves_failed

		var hit_rate = (float(total_hits) / float(total_attacks) * 100.0) if total_attacks > 0 else 0.0
		var wound_rate = (float(total_wounds) / float(total_hits) * 100.0) if total_hits > 0 else 0.0
		var unsaved_rate = (float(total_unsaved) / float(total_wounds) * 100.0) if total_wounds > 0 else 0.0

		weapon_stats_list.append({
			"weapon_name": entry.weapon_name,
			"weapon_data": weapon_data,
			"avg_damage": result.get_average_damage(),
			"median_damage": result.get_damage_percentile(0.5),
			"kill_probability": result.kill_probability,
			"expected_survivors": result.expected_survivors,
			"damage_efficiency": result.damage_efficiency,
			"hit_rate": hit_rate,
			"wound_rate": wound_rate,
			"unsaved_rate": unsaved_rate,
			"result": result
		})

	# Find best values for highlighting
	var best_avg_damage = 0.0
	var best_kill_prob = 0.0
	for ws in weapon_stats_list:
		if ws.avg_damage > best_avg_damage:
			best_avg_damage = ws.avg_damage
		if ws.kill_probability > best_kill_prob:
			best_kill_prob = ws.kill_probability

	# Create weapon stat cards — one per weapon
	for i in range(weapon_stats_list.size()):
		var ws = weapon_stats_list[i]
		var weapon_data = ws.weapon_data

		var is_best_damage = ws.avg_damage >= best_avg_damage and best_avg_damage > 0
		var bg_color = Color(0.2, 0.4, 0.25, 0.8) if is_best_damage else Color(0.25, 0.3, 0.4, 0.8)

		var weapon_panel = create_styled_panel(ws.weapon_name, bg_color)
		comparison_vbox.add_child(weapon_panel)
		var weapon_content = weapon_panel.get_meta("content_vbox")

		# Weapon stats line
		var stats_text = ""
		if weapon_data.get("type", "") == "Ranged":
			stats_text = "BS:%s+ S:%s AP:%s D:%s" % [
				weapon_data.get("ballistic_skill", "4"),
				weapon_data.get("strength", "4"),
				weapon_data.get("ap", "0"),
				weapon_data.get("damage", "1")
			]
		else:
			stats_text = "WS:%s+ S:%s AP:%s D:%s" % [
				weapon_data.get("weapon_skill", "4"),
				weapon_data.get("strength", "4"),
				weapon_data.get("ap", "0"),
				weapon_data.get("damage", "1")
			]

		var stats_label = Label.new()
		stats_label.text = stats_text
		stats_label.add_theme_font_size_override("font_size", 10)
		stats_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
		weapon_content.add_child(stats_label)

		# Stats grid
		var grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 15)
		grid.add_theme_constant_override("v_separation", 4)
		weapon_content.add_child(grid)

		add_stat_row(grid, "Avg Damage:", "%.2f wounds" % ws.avg_damage,
			Color.YELLOW if is_best_damage else Color.WHITE)
		add_stat_row(grid, "Median Damage:", "%d wounds" % ws.median_damage)
		add_stat_row(grid, "Kill Probability:", "%.1f%%" % (ws.kill_probability * 100),
			Color.RED if ws.kill_probability >= best_kill_prob and best_kill_prob > 0 else Color.WHITE)
		add_stat_row(grid, "Expected Survivors:", "%.2f models" % ws.expected_survivors, Color.GREEN)
		add_stat_row(grid, "Damage Efficiency:", "%.1f%%" % (ws.damage_efficiency * 100), Color.CYAN)
		add_stat_row(grid, "Hit Rate:", "%.1f%%" % ws.hit_rate)
		add_stat_row(grid, "Wound Rate:", "%.1f%%" % ws.wound_rate)
		add_stat_row(grid, "Unsaved Rate:", "%.1f%%" % ws.unsaved_rate)

	# Add ranking summary
	_create_comparison_ranking(comparison_vbox, weapon_stats_list)

	# Also populate the breakdown panel with comparison data
	_populate_comparison_breakdown(results, weapon_stats_list)

	print("MathhammerUI: Comparison display complete")

func _create_comparison_ranking(parent: VBoxContainer, weapon_stats: Array) -> void:
	# Sort weapons by average damage (descending)
	var sorted_by_damage = weapon_stats.duplicate()
	sorted_by_damage.sort_custom(func(a, b): return a.avg_damage > b.avg_damage)

	var ranking_panel = create_styled_panel("Damage Ranking", Color(0.5, 0.4, 0.15, 0.8))
	parent.add_child(ranking_panel)
	var ranking_content = ranking_panel.get_meta("content_vbox")

	for i in range(sorted_by_damage.size()):
		var ws = sorted_by_damage[i]
		var rank_label = Label.new()
		rank_label.text = "#%d %s — %.2f avg dmg (%.1f%% kill)" % [
			i + 1, ws.weapon_name, ws.avg_damage, ws.kill_probability * 100]
		rank_label.add_theme_font_size_override("font_size", 11)

		if i == 0:
			rank_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))  # Gold
		elif i == 1:
			rank_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))  # Silver
		elif i == 2:
			rank_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.2))  # Bronze
		else:
			rank_label.add_theme_color_override("font_color", Color.WHITE)

		ranking_content.add_child(rank_label)

func _populate_comparison_breakdown(results: Array, weapon_stats_list: Array) -> void:
	# Populate the breakdown panel with per-weapon cumulative probability tables
	if not breakdown_panel:
		return

	# Clear the breakdown_text placeholder if it still exists
	if breakdown_text and is_instance_valid(breakdown_text):
		breakdown_text.queue_free()
		breakdown_text = null

	var breakdown_scroll = ScrollContainer.new()
	breakdown_scroll.name = "DetailedBreakdownScroll"
	breakdown_scroll.custom_minimum_size = Vector2(_get_content_width(), _get_breakdown_scroll_height())
	breakdown_scroll.visible = true
	breakdown_panel.add_child(breakdown_scroll)

	var breakdown_vbox = VBoxContainer.new()
	breakdown_vbox.name = "BreakdownVBox"
	breakdown_vbox.add_theme_constant_override("separation", 10)
	breakdown_scroll.add_child(breakdown_vbox)

	# Per-weapon cumulative probability tables
	for entry in results:
		var result = entry.result as Mathhammer.SimulationResult
		var weapon_name = entry.weapon_name

		# Create a mini cumulative probability section per weapon
		_create_cumulative_probability_panel(breakdown_vbox, result)

		# Rename the panel title to include weapon name
		var last_child = breakdown_vbox.get_child(breakdown_vbox.get_child_count() - 1)
		if last_child:
			var content_vbox = last_child.get_meta("content_vbox") if last_child.has_meta("content_vbox") else null
			if content_vbox and content_vbox.get_child_count() > 0:
				var title_label = content_vbox.get_child(0)
				if title_label is Label:
					title_label.text = "Cumulative Probability — %s" % weapon_name

	print("MathhammerUI: Populated comparison breakdown panel")

# --- Progress indicator helpers (T5-MH7) ---

# Create a Callable that the background thread can use to report progress.
# The callback uses call_deferred so it's safe from non-main threads.
func _create_progress_callback() -> Callable:
	return func(current_trial: int, total_trials: int) -> void:
		var pct = float(current_trial) / float(total_trials) * 100.0
		var text = "Simulating... %d / %d trials" % [current_trial, total_trials]
		call_deferred("_update_progress", text, pct)

func _show_progress(text: String, percentage: float) -> void:
	if _progress_container:
		_progress_container.visible = true
	if _progress_label:
		_progress_label.text = text
	if _progress_bar:
		_progress_bar.value = percentage
	print("MathhammerUI: Progress shown — %s (%.0f%%)" % [text, percentage])

func _update_progress(text: String, percentage: float) -> void:
	# Called on main thread via call_deferred from background thread
	if _progress_label:
		_progress_label.text = text
	if _progress_bar:
		_progress_bar.value = percentage

func _hide_progress() -> void:
	if _progress_container:
		_progress_container.visible = false
	if _progress_bar:
		_progress_bar.value = 0.0
	print("MathhammerUI: Progress hidden")

# --- End progress indicator helpers ---

func _show_error(message: String) -> void:
	print("MathhammerUI Error: ", message)
	if results_label:
		results_label.text = "[color=red][b]Error:[/b] " + message + "[/color]"

extends AcceptDialog

# SaveDialog - Interactive save resolution for defending player
# Phase 1 MVP: Auto-allocation + batch save rolling

signal saves_rolled(save_results: Dictionary)
signal save_complete()

# Save resolution data
var save_data: Dictionary = {}
var allocations: Array = []
var save_results: Dictionary = {}
var defender_player: int = 0  # Player who is defending (making saves)

# UI Nodes
var vbox: VBoxContainer
var attack_info_label: Label
var save_stats_label: Label
var model_grid_container: GridContainer
var dice_log_rich_text: RichTextLabel
var roll_button: Button
var apply_button: Button

func _ready() -> void:
	# Set dialog properties
	title = "Incoming Attack - Defend!"
	dialog_hide_on_ok = false

	# Set dialog size (Windows use min_size, not custom_minimum_size)
	min_size = Vector2(600, 500)

	# Hide default OK button, we'll use custom buttons
	get_ok_button().hide()

	# Create main container
	vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(580, 480)
	add_child(vbox)

	# Attack information section
	attack_info_label = Label.new()
	attack_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attack_info_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(attack_info_label)

	vbox.add_child(HSeparator.new())

	# Save stats section
	save_stats_label = Label.new()
	save_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(save_stats_label)

	vbox.add_child(HSeparator.new())

	# Model grid section
	var model_label = Label.new()
	model_label.text = "Model Allocation (Auto):"
	model_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(model_label)

	var model_scroll = ScrollContainer.new()
	model_scroll.set_custom_minimum_size(Vector2(560, 150))
	vbox.add_child(model_scroll)

	model_grid_container = GridContainer.new()
	model_grid_container.columns = 4
	model_scroll.add_child(model_grid_container)

	vbox.add_child(HSeparator.new())

	# Dice log section
	var log_label = Label.new()
	log_label.text = "Dice Log:"
	log_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(log_label)

	dice_log_rich_text = RichTextLabel.new()
	dice_log_rich_text.set_custom_minimum_size(Vector2(560, 100))
	dice_log_rich_text.bbcode_enabled = true
	dice_log_rich_text.scroll_following = true
	vbox.add_child(dice_log_rich_text)

	vbox.add_child(HSeparator.new())

	# Action buttons
	var button_hbox = HBoxContainer.new()
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_hbox)

	roll_button = Button.new()
	roll_button.text = "Roll All Saves"
	roll_button.pressed.connect(_on_roll_saves_pressed)
	button_hbox.add_child(roll_button)

	apply_button = Button.new()
	apply_button.text = "Apply Damage"
	apply_button.disabled = true
	apply_button.pressed.connect(_on_apply_damage_pressed)
	button_hbox.add_child(apply_button)

	print("SaveDialog initialized")

func setup(p_save_data: Dictionary, p_defender_player: int = 0) -> void:
	"""Setup the dialog with save resolution data from RulesEngine"""
	save_data = p_save_data
	defender_player = p_defender_player

	if not save_data.get("success", false):
		push_error("SaveDialog: Invalid save data received")
		return

	# Auto-allocate wounds following 10e rules
	allocations = RulesEngine.auto_allocate_wounds(
		save_data.wounds_to_save,
		save_data
	)

	# Update UI
	_update_attack_info()
	_update_save_stats()
	_update_model_display()
	_add_to_dice_log("Awaiting defender to roll saves...", Color.YELLOW)

func _update_attack_info() -> void:
	"""Display incoming attack information"""
	var attacker = save_data.get("shooter_unit_id", "Unknown")
	var weapon = save_data.get("weapon_name", "Unknown Weapon")
	var ap = save_data.get("ap", 0)
	var damage = save_data.get("damage", 1)
	var wounds = save_data.get("wounds_to_save", 0)

	var ap_text = str(ap) if ap >= 0 else str(ap)  # Display as -1, -2, etc.

	attack_info_label.text = "Attacker: %s\nWeapon: %s (AP%s, Damage %d)\nWounds to Save: %d" % [
		attacker, weapon, ap_text, damage, wounds
	]
	attack_info_label.modulate = Color(1.0, 0.8, 0.8)  # Light red tint

func _update_save_stats() -> void:
	"""Display save characteristics"""
	var unit_name = save_data.get("target_unit_name", "Unknown")
	var base_save = save_data.get("base_save", 7)

	# Get example save from first model (they may vary by cover/invuln)
	var profiles = save_data.get("model_save_profiles", [])
	if profiles.is_empty():
		save_stats_label.text = "No valid models to save!"
		return

	var example_profile = profiles[0]
	var save_needed = example_profile.get("save_needed", 7)
	var using_invuln = example_profile.get("using_invuln", false)
	var has_cover = example_profile.get("has_cover", false)

	var save_text = "Unit: %s\n" % unit_name
	save_text += "Base Save: %d+\n" % base_save

	if using_invuln:
		save_text += "Using Invulnerable Save: %d+\n" % example_profile.get("invuln_value", 7)
	else:
		save_text += "Modified Save: %d+" % save_needed
		if has_cover:
			save_text += " (includes +1 from cover)"
		save_text += "\n"

	save_stats_label.text = save_text

func _update_model_display() -> void:
	"""Display allocated models in a grid"""
	# Clear existing children
	for child in model_grid_container.get_children():
		child.queue_free()

	if allocations.is_empty():
		var no_alloc_label = Label.new()
		no_alloc_label.text = "No allocations made"
		model_grid_container.add_child(no_alloc_label)
		return

	# Group allocations by model to show how many wounds each gets
	var allocation_counts = {}
	for allocation in allocations:
		var model_id = allocation.model_id
		if not allocation_counts.has(model_id):
			allocation_counts[model_id] = 0
		allocation_counts[model_id] += 1

	# Display each allocated model
	for model_id in allocation_counts:
		var count = allocation_counts[model_id]

		# Find profile for this model
		var profile = null
		for p in save_data.model_save_profiles:
			if p.model_id == model_id:
				profile = p
				break

		if not profile:
			continue

		var model_panel = PanelContainer.new()
		model_panel.set_custom_minimum_size(Vector2(130, 60))

		var model_vbox = VBoxContainer.new()
		model_panel.add_child(model_vbox)

		var name_label = Label.new()
		name_label.text = str(model_id)
		if profile.is_wounded:
			name_label.text += " *"
			name_label.modulate = Color.ORANGE
		model_vbox.add_child(name_label)

		var hp_label = Label.new()
		hp_label.text = "HP: %d/%d" % [profile.current_wounds, profile.max_wounds]
		hp_label.add_theme_font_size_override("font_size", 10)
		model_vbox.add_child(hp_label)

		var wounds_label = Label.new()
		wounds_label.text = "Saves: %d" % count
		wounds_label.add_theme_font_size_override("font_size", 10)
		model_vbox.add_child(wounds_label)

		model_grid_container.add_child(model_panel)

func _on_roll_saves_pressed() -> void:
	"""Roll all saves using RulesEngine"""
	roll_button.disabled = true

	# Create RNG service
	var rng_service = RulesEngine.RNGService.new()

	# Roll saves
	save_results = RulesEngine.roll_saves_batch(
		allocations,
		save_data,
		rng_service
	)

	# Display results
	_display_save_results()

	# Enable apply button
	apply_button.disabled = false

	# Emit signal
	emit_signal("saves_rolled", save_results)

func _display_save_results() -> void:
	"""Display save roll results in dice log"""
	if not save_results.get("success", false):
		_add_to_dice_log("Error rolling saves!", Color.RED)
		return

	var results = save_results.get("save_results", [])
	var passed = 0
	var failed = 0

	for result in results:
		var model_id = result.model_id
		var roll = result.roll
		var needed = result.needed
		var saved = result.saved

		var result_text = "%s: Rolled %d vs %d+ - %s" % [
			model_id,
			roll,
			needed,
			"SAVED" if saved else "FAILED"
		]

		var color = Color.GREEN if saved else Color.RED
		_add_to_dice_log(result_text, color)

		if saved:
			passed += 1
		else:
			failed += 1

	# Summary
	_add_to_dice_log("", Color.WHITE)
	_add_to_dice_log("Summary: %d saved, %d failed" % [passed, failed], Color.YELLOW)

func _on_apply_damage_pressed() -> void:
	"""Apply damage and close dialog"""
	# Create APPLY_SAVES action with results
	# IMPORTANT: Use defender_player, NOT the active player (who is the attacker)
	var action = {
		"type": "APPLY_SAVES",
		"player": defender_player,
		"payload": {
			"save_results_list": [save_results]  # Wrap single result in array
		}
	}

	print("SaveDialog: Submitting APPLY_SAVES action with player=%d" % defender_player)

	# Submit action through NetworkManager
	NetworkManager.submit_action(action)

	emit_signal("save_complete")
	hide()
	queue_free()

func _add_to_dice_log(text: String, color: Color) -> void:
	"""Add colored text to dice log"""
	var color_hex = color.to_html(false)
	dice_log_rich_text.append_text("[color=#%s]%s[/color]\n" % [color_hex, text])

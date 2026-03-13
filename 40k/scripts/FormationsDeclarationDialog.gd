extends AcceptDialog

# FormationsDeclarationDialog - UI for declaring pre-battle formations
# Shows options for leader attachments, transport embarkations, and reserves
# Emits formations_confirmed signal with the player's choices

signal formations_confirmed(player: int, formations: Dictionary)

var declaring_player: int = 0

# Tracked declarations
var leader_attachments: Dictionary = {}  # character_id -> bodyguard_id
var transport_embarkations: Dictionary = {}  # transport_id -> [unit_ids]
var reserves: Array = []  # [{unit_id, reserve_type}]

# UI references
var scroll_container: ScrollContainer
var content_vbox: VBoxContainer
var summary_label: RichTextLabel

func _init():
	title = "Declare Battle Formations"
	min_size = Vector2(700, 750)
	WhiteDwarfTheme.apply_to_dialog(self)

func setup(player: int) -> void:
	declaring_player = player
	leader_attachments.clear()
	transport_embarkations.clear()
	reserves.clear()

	title = "Player %d — Declare Battle Formations" % player

	# Hide AcceptDialog's built-in OK button — we add our own inside the layout
	get_ok_button().visible = false

	# Build the UI (includes custom confirm/skip buttons)
	_build_ui()

func _build_ui() -> void:
	# Create a main vertical layout
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# Instruction label
	var instructions = Label.new()
	instructions.text = "Declare your battle formations before deployment begins.\nThese choices are locked in before either player deploys."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_font_size_override("font_size", 13)
	main_vbox.add_child(instructions)

	var separator = HSeparator.new()
	main_vbox.add_child(separator)

	# Scrollable content — fixed height that fills most of the dialog while
	# leaving room for summary + buttons below (dialog is 750px tall)
	scroll_container = ScrollContainer.new()
	scroll_container.custom_minimum_size = Vector2(680, 400)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll_container)

	content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 12)
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(content_vbox)

	# Build each section
	_build_leader_section()
	_build_transport_section()
	_build_reserves_section()

	# Summary section
	var summary_sep = HSeparator.new()
	main_vbox.add_child(summary_sep)

	summary_label = RichTextLabel.new()
	summary_label.custom_minimum_size = Vector2(680, 60)
	summary_label.bbcode_enabled = true
	summary_label.fit_content = true
	main_vbox.add_child(summary_label)

	_update_summary()

	# Custom confirm/skip buttons inside the layout (AcceptDialog's built-in buttons
	# get clipped outside the visible area, so we manage our own)
	var button_bar = HBoxContainer.new()
	button_bar.add_theme_constant_override("separation", 12)
	button_bar.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(button_bar)

	var skip_button = Button.new()
	skip_button.text = "Skip (No Declarations)"
	skip_button.pressed.connect(_on_canceled)
	button_bar.add_child(skip_button)

	var confirm_button = Button.new()
	confirm_button.text = "Confirm Formations"
	confirm_button.pressed.connect(_on_confirmed)
	button_bar.add_child(confirm_button)

func _build_leader_section() -> void:
	"""Build the leader attachment section."""
	var characters = GameState.get_characters_for_player(declaring_player)
	if characters.is_empty():
		return

	var section_label = Label.new()
	section_label.text = "LEADER ATTACHMENTS"
	section_label.add_theme_font_size_override("font_size", 14)
	section_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	content_vbox.add_child(section_label)

	var desc_label = Label.new()
	desc_label.text = "Assign CHARACTER leaders to bodyguard units:"
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_BONE)
	content_vbox.add_child(desc_label)

	for char_id in characters:
		var char_unit = GameState.get_unit(char_id)
		var char_name = char_unit.get("meta", {}).get("name", char_id)
		var eligible = GameState.get_eligible_bodyguards_for_character(char_id)

		if eligible.is_empty():
			continue

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		content_vbox.add_child(row)

		var char_label = Label.new()
		char_label.text = "%s →" % char_name
		char_label.custom_minimum_size = Vector2(200, 0)
		char_label.add_theme_font_size_override("font_size", 13)
		row.add_child(char_label)

		var option_button = OptionButton.new()
		option_button.add_item("(Unattached)", 0)
		option_button.set_item_metadata(0, "")

		var idx = 1
		for bg_id in eligible:
			var bg_unit = GameState.get_unit(bg_id)
			var bg_name = bg_unit.get("meta", {}).get("name", bg_id)
			var model_count = bg_unit.get("models", []).size()
			option_button.add_item("%s (%d models)" % [bg_name, model_count], idx)
			option_button.set_item_metadata(idx, bg_id)
			idx += 1

		option_button.custom_minimum_size = Vector2(300, 0)
		option_button.set_meta("character_id", char_id)
		option_button.item_selected.connect(_on_leader_option_changed.bind(option_button))
		row.add_child(option_button)

func _build_transport_section() -> void:
	"""Build the transport embarkation section."""
	var transports = GameState.get_transports_for_player(declaring_player)
	if transports.is_empty():
		return

	var sep = HSeparator.new()
	content_vbox.add_child(sep)

	var section_label = Label.new()
	section_label.text = "TRANSPORT EMBARKATION"
	section_label.add_theme_font_size_override("font_size", 14)
	section_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	content_vbox.add_child(section_label)

	var desc_label = Label.new()
	desc_label.text = "Select units to start embarked in transports:"
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_BONE)
	content_vbox.add_child(desc_label)

	for transport_id in transports:
		var transport = GameState.get_unit(transport_id)
		var transport_name = transport.get("meta", {}).get("name", transport_id)
		var capacity = transport.get("transport_data", {}).get("capacity", 0)
		var capacity_keywords = transport.get("transport_data", {}).get("capacity_keywords", [])

		var transport_label = Label.new()
		transport_label.text = "%s (Capacity: %d%s)" % [
			transport_name, capacity,
			" — %s only" % "/".join(capacity_keywords) if capacity_keywords.size() > 0 else ""
		]
		transport_label.add_theme_font_size_override("font_size", 13)
		transport_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
		content_vbox.add_child(transport_label)

		# Show checkboxes for eligible units
		var eligible_units = _get_transport_eligible_units(transport_id)
		var transport_container = VBoxContainer.new()
		transport_container.set_meta("transport_id", transport_id)
		transport_container.set_meta("capacity", capacity)
		content_vbox.add_child(transport_container)

		for unit_id in eligible_units:
			var unit = GameState.get_unit(unit_id)
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			var model_count = 0
			for model in unit.get("models", []):
				if model.get("alive", true):
					model_count += 1

			var checkbox = CheckBox.new()
			checkbox.text = "%s (%d models)" % [unit_name, model_count]
			checkbox.set_meta("unit_id", unit_id)
			checkbox.set_meta("model_count", model_count)
			checkbox.set_meta("transport_id", transport_id)
			checkbox.toggled.connect(_on_transport_checkbox_toggled.bind(checkbox))
			transport_container.add_child(checkbox)

func _build_reserves_section() -> void:
	"""Build the reserves declaration section.
	Characters attached to bodyguards are shown as part of the bodyguard entry.
	Unattached characters appear as independent entries."""
	var sep = HSeparator.new()
	sep.set_meta("reserves_section", true)
	content_vbox.add_child(sep)

	var section_label = Label.new()
	section_label.text = "STRATEGIC RESERVES / DEEP STRIKE"
	section_label.add_theme_font_size_override("font_size", 14)
	section_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	section_label.set_meta("reserves_section", true)
	content_vbox.add_child(section_label)

	var total_points = GameState.get_total_army_points(declaring_player)
	var max_reserves = int(total_points * 0.50)

	var desc_label = Label.new()
	desc_label.text = "Place units in reserves (max 50%% of army points = %d pts):" % max_reserves
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_BONE)
	desc_label.set_meta("reserves_section", true)
	content_vbox.add_child(desc_label)

	# Build a set of character IDs that are currently attached to bodyguards
	var attached_character_ids = {}
	for char_id in leader_attachments:
		attached_character_ids[char_id] = leader_attachments[char_id]

	var units = GameState.get_units_for_player(declaring_player)
	for unit_id in units:
		var unit = units[unit_id]
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var unit_points = unit.get("meta", {}).get("points", 0)
		var has_deep_strike = GameState.unit_has_deep_strike(unit_id)

		# Skip characters that are attached to a bodyguard (they go with their bodyguard)
		var keywords = unit.get("meta", {}).get("keywords", [])
		if "CHARACTER" in keywords and attached_character_ids.has(unit_id):
			continue

		# Skip transports (they need to be on the board)
		if unit.has("transport_data"):
			continue

		# Determine reserve type — if a unit OR any of its attached characters has deep strike, it's DS
		var combined_has_ds = has_deep_strike
		var combined_points = unit_points
		var attached_chars_text = ""

		# Check if this unit has any attached characters (bodyguard check)
		var attached_chars_on_this = []
		for char_id in leader_attachments:
			if leader_attachments[char_id] == unit_id:
				attached_chars_on_this.append(char_id)

		for char_id in attached_chars_on_this:
			var char_unit = GameState.get_unit(char_id)
			var char_name = char_unit.get("meta", {}).get("name", char_id)
			var char_points = char_unit.get("meta", {}).get("points", 0)
			combined_points += char_points
			if GameState.unit_has_deep_strike(char_id):
				combined_has_ds = true
			if attached_chars_text == "":
				attached_chars_text = " + %s (%d pts)" % [char_name, char_points]
			else:
				attached_chars_text += " + %s (%d pts)" % [char_name, char_points]

		var reserve_type_label = "Deep Strike" if combined_has_ds else "Strategic Reserves"

		var checkbox = CheckBox.new()
		if attached_chars_on_this.size() > 0:
			checkbox.text = "%s (%d pts)%s — %s" % [unit_name, unit_points, attached_chars_text, reserve_type_label]
		else:
			checkbox.text = "%s (%d pts) — %s" % [unit_name, unit_points, reserve_type_label]
		checkbox.set_meta("unit_id", unit_id)
		checkbox.set_meta("unit_points", combined_points)
		checkbox.set_meta("attached_character_ids", attached_chars_on_this)
		checkbox.set_meta("reserve_type", "deep_strike" if combined_has_ds else "strategic_reserves")
		checkbox.set_meta("reserves_section", true)
		checkbox.toggled.connect(_on_reserves_checkbox_toggled.bind(checkbox))
		content_vbox.add_child(checkbox)

func _get_transport_eligible_units(transport_id: String) -> Array:
	"""Get units that can embark in a transport."""
	var transport = GameState.get_unit(transport_id)
	var capacity_keywords = transport.get("transport_data", {}).get("capacity_keywords", [])
	var eligible = []

	var units = GameState.get_units_for_player(declaring_player)
	for unit_id in units:
		# Skip self
		if unit_id == transport_id:
			continue
		var unit = units[unit_id]
		# Skip other transports
		if unit.has("transport_data"):
			continue
		# Skip CHARACTERs (they attach, not embark)
		var keywords = unit.get("meta", {}).get("keywords", [])
		var leader_data = unit.get("meta", {}).get("leader_data", {})
		if "CHARACTER" in keywords and leader_data.get("can_lead", []).size() > 0:
			continue
		# Check keyword requirements
		if capacity_keywords.size() > 0:
			var has_keyword = false
			for kw in capacity_keywords:
				if kw in keywords:
					has_keyword = true
					break
			if not has_keyword:
				continue
		eligible.append(unit_id)

	return eligible

# ========================================
# Signal Handlers
# ========================================

func _on_leader_option_changed(index: int, option_button: OptionButton) -> void:
	var character_id = option_button.get_meta("character_id")
	var bodyguard_id = option_button.get_item_metadata(index)

	if bodyguard_id == "" or bodyguard_id == null:
		# Unattached
		leader_attachments.erase(character_id)
	else:
		# Check if this bodyguard is already assigned to another character
		for char_id in leader_attachments:
			if leader_attachments[char_id] == bodyguard_id and char_id != character_id:
				# Silently deselect the other character's assignment
				leader_attachments.erase(char_id)
				# Reset the other option button
				_reset_leader_option_for_character(char_id)
				break

		leader_attachments[character_id] = bodyguard_id

	# Remove any reserves declarations that are now invalid due to attachment changes
	# (e.g. character was in reserves independently but is now attached to a bodyguard)
	_sync_reserves_after_attachment_change()

	# Rebuild reserves section to reflect attachment changes
	_rebuild_reserves_section()

	_update_summary()

func _reset_leader_option_for_character(char_id: String) -> void:
	"""Reset an OptionButton for a character back to (Unattached)."""
	for child in content_vbox.get_children():
		if child is HBoxContainer:
			for sub_child in child.get_children():
				if sub_child is OptionButton and sub_child.has_meta("character_id"):
					if sub_child.get_meta("character_id") == char_id:
						sub_child.select(0)
						return

func _on_transport_checkbox_toggled(toggled_on: bool, checkbox: CheckBox) -> void:
	var transport_id = checkbox.get_meta("transport_id")
	var unit_id = checkbox.get_meta("unit_id")
	var model_count = checkbox.get_meta("model_count")

	if not transport_embarkations.has(transport_id):
		transport_embarkations[transport_id] = []

	if toggled_on:
		# Check capacity
		var transport = GameState.get_unit(transport_id)
		var capacity = transport.get("transport_data", {}).get("capacity", 0)
		var current_models = _get_embarked_model_count(transport_id)

		if current_models + model_count > capacity:
			checkbox.button_pressed = false
			print("FormationsDialog: Exceeds transport capacity (%d + %d > %d)" % [current_models, model_count, capacity])
			return

		# Check unit isn't already assigned elsewhere
		if _is_unit_in_use(unit_id):
			checkbox.button_pressed = false
			return

		transport_embarkations[transport_id].append(unit_id)
	else:
		transport_embarkations[transport_id].erase(unit_id)
		if transport_embarkations[transport_id].is_empty():
			transport_embarkations.erase(transport_id)

	_update_summary()

func _on_reserves_checkbox_toggled(toggled_on: bool, checkbox: CheckBox) -> void:
	var unit_id = checkbox.get_meta("unit_id")
	var reserve_type = checkbox.get_meta("reserve_type")
	var unit_points = checkbox.get_meta("unit_points")
	var attached_char_ids = checkbox.get_meta("attached_character_ids") if checkbox.has_meta("attached_character_ids") else []

	if toggled_on:
		# Check 50% point limit (Chapter Approved 2025-26)
		var total_points = GameState.get_total_army_points(declaring_player)
		var max_reserves = int(total_points * 0.50)
		var current_reserves = _get_declared_reserves_points()

		if current_reserves + unit_points > max_reserves:
			checkbox.button_pressed = false
			print("FormationsDialog: Exceeds 50%% reserves points limit (%d + %d > %d)" % [current_reserves, unit_points, max_reserves])
			return

		# Check unit isn't already assigned elsewhere
		if _is_unit_in_use(unit_id):
			checkbox.button_pressed = false
			return

		reserves.append({
			"unit_id": unit_id,
			"reserve_type": reserve_type,
			"attached_character_ids": attached_char_ids
		})
	else:
		for i in range(reserves.size()):
			if reserves[i].get("unit_id", "") == unit_id:
				reserves.remove_at(i)
				break

	_update_summary()

func _on_confirmed() -> void:
	var formations = {
		"leader_attachments": leader_attachments,
		"transport_embarkations": transport_embarkations,
		"reserves": reserves
	}
	emit_signal("formations_confirmed", declaring_player, formations)
	queue_free()

func _on_canceled() -> void:
	# Empty formations = skip
	emit_signal("formations_confirmed", declaring_player, {
		"leader_attachments": {},
		"transport_embarkations": {},
		"reserves": []
	})
	queue_free()

# ========================================
# Helper Methods
# ========================================

func _sync_reserves_after_attachment_change() -> void:
	"""Remove reserves entries for characters that are now attached to bodyguards.
	Attached characters will go with their bodyguard automatically."""
	var to_remove = []
	for i in range(reserves.size()):
		var entry_unit_id = reserves[i].get("unit_id", "")
		if leader_attachments.has(entry_unit_id):
			# This character is now attached — remove its independent reserves entry
			to_remove.append(i)
	# Remove in reverse order to maintain indices
	to_remove.reverse()
	for idx in to_remove:
		reserves.remove_at(idx)

func _rebuild_reserves_section() -> void:
	"""Remove and rebuild the reserves section to reflect attachment changes."""
	# Remove all existing reserves section UI elements
	var to_remove = []
	for child in content_vbox.get_children():
		if child.has_meta("reserves_section"):
			to_remove.append(child)
	for child in to_remove:
		content_vbox.remove_child(child)
		child.queue_free()

	# Rebuild
	_build_reserves_section()

	# Re-check any checkboxes that are still in the reserves array
	for child in content_vbox.get_children():
		if child is CheckBox and child.has_meta("reserves_section") and child.has_meta("unit_id"):
			var uid = child.get_meta("unit_id")
			for entry in reserves:
				if entry.get("unit_id", "") == uid:
					child.set_pressed_no_signal(true)
					break

func _get_embarked_model_count(transport_id: String) -> int:
	var total = 0
	for unit_id in transport_embarkations.get(transport_id, []):
		var unit = GameState.get_unit(unit_id)
		for model in unit.get("models", []):
			if model.get("alive", true):
				total += 1
	return total

func _get_declared_reserves_points() -> int:
	var total = 0
	for entry in reserves:
		var unit = GameState.get_unit(entry.get("unit_id", ""))
		total += unit.get("meta", {}).get("points", 0)
		# Include attached character points
		for char_id in entry.get("attached_character_ids", []):
			var char_unit = GameState.get_unit(char_id)
			total += char_unit.get("meta", {}).get("points", 0)
	return total

func _is_unit_in_use(unit_id: String) -> bool:
	"""Check if a unit is already declared in attachments, transport, or reserves."""
	if leader_attachments.has(unit_id):
		return true
	# Check if this unit is a bodyguard that has a character attached going to reserves with it
	for char_id in leader_attachments:
		if leader_attachments[char_id] == unit_id:
			# This unit has an attached character — but that doesn't make it "in use"
			pass
	for transport_id in transport_embarkations:
		if unit_id in transport_embarkations[transport_id]:
			return true
	for entry in reserves:
		if entry.get("unit_id", "") == unit_id:
			return true
		# Also check if this unit is an attached character going with a bodyguard
		var attached_chars = entry.get("attached_character_ids", [])
		if unit_id in attached_chars:
			return true
	return false

func _update_summary() -> void:
	if not summary_label:
		return

	var text = "[b]Summary:[/b]\n"

	# Leader attachments
	if leader_attachments.size() > 0:
		text += "[color=#%s]Leaders:[/color] " % WhiteDwarfTheme.gold_hex()
		var parts = []
		for char_id in leader_attachments:
			var char_name = GameState.get_unit(char_id).get("meta", {}).get("name", char_id)
			var bg_name = GameState.get_unit(leader_attachments[char_id]).get("meta", {}).get("name", leader_attachments[char_id])
			parts.append("%s → %s" % [char_name, bg_name])
		text += ", ".join(parts) + "\n"

	# Transport embarkations
	var total_embarked = 0
	for transport_id in transport_embarkations:
		total_embarked += transport_embarkations[transport_id].size()
	if total_embarked > 0:
		text += "[color=#%s]Transports:[/color] " % WhiteDwarfTheme.gold_hex()
		var parts = []
		for transport_id in transport_embarkations:
			var transport_name = GameState.get_unit(transport_id).get("meta", {}).get("name", transport_id)
			parts.append("%d unit(s) in %s" % [transport_embarkations[transport_id].size(), transport_name])
		text += ", ".join(parts) + "\n"

	# Reserves
	if reserves.size() > 0:
		text += "[color=#%s]Reserves:[/color] " % WhiteDwarfTheme.gold_hex()
		var parts = []
		var total_pts = 0
		for entry in reserves:
			var unit_name = GameState.get_unit(entry["unit_id"]).get("meta", {}).get("name", entry["unit_id"])
			var type_label = "DS" if entry["reserve_type"] == "deep_strike" else "SR"
			var entry_text = "%s [%s]" % [unit_name, type_label]
			total_pts += GameState.get_unit(entry["unit_id"]).get("meta", {}).get("points", 0)
			# Show attached characters
			for char_id in entry.get("attached_character_ids", []):
				var char_unit = GameState.get_unit(char_id)
				var char_name = char_unit.get("meta", {}).get("name", char_id)
				var char_pts = char_unit.get("meta", {}).get("points", 0)
				entry_text += " + %s" % char_name
				total_pts += char_pts
			parts.append(entry_text)
		var total_army = GameState.get_total_army_points(declaring_player)
		var max_pts = int(total_army * 0.50)
		text += ", ".join(parts) + " (%d/%d pts)\n" % [total_pts, max_pts]

	if leader_attachments.is_empty() and total_embarked == 0 and reserves.is_empty():
		text += "[i]No formations declared. All units will deploy individually.[/i]"

	summary_label.text = text

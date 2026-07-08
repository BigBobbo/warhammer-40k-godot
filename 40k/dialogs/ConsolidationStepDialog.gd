extends AcceptDialog
class_name ConsolidationStepDialog

# ConsolidationStepDialog — 11e 12.07 global Consolidate step.
# After all fighting, each player in turn (active player first) may make
# one consolidation move with each of their eligible units. This dialog
# lists the consolidating player's remaining eligible units: picking one
# opens the ConsolidateDialog + interactive movement; "End Consolidation"
# passes to the opponent (consolidation is OPTIONAL per unit at 11e).
#
# Node names are stable on purpose (Content/Consolidate_<unit_id>,
# Content/EndConsolidationButton) so windowed scenarios can click the
# same affordances a player sees.

signal consolidate_unit_chosen(unit_id: String)
signal end_consolidation(player: int)

var dialog_data: Dictionary = {}
var phase_reference = null

# Factory: build a ready-to-show dialog (script attached + UI built). The caller
# connects the signals, adds it to the tree, and calls popup_centered(). Shared
# by FightController and the windowed regression scenario so both exercise one
# construction path (and the autowrap-Label height guard in _build_ui).
static func create(data: Dictionary, phase) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.set_script(load("res://dialogs/ConsolidationStepDialog.gd"))
	dialog.name = "ConsolidationStepDialog"
	dialog.setup(data, phase)
	return dialog

func setup(data: Dictionary, phase) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	dialog_data = data
	phase_reference = phase
	title = "Consolidate Step — Player %d" % data.get("consolidating_player", 0)
	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var content = VBoxContainer.new()
	content.name = "Content"
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var player = dialog_data.get("consolidating_player", 0)
	var banner = Panel.new()
	banner.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 40)
	var player_color = Color.BLUE if player == 1 else Color.RED
	banner.add_theme_stylebox_override("panel", _create_colored_panel(player_color))
	var banner_label = Label.new()
	banner_label.text = "CONSOLIDATE STEP — PLAYER %d" % player
	banner_label.add_theme_font_size_override("font_size", 20)
	banner_label.add_theme_color_override("font_color", Color.WHITE)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_label)
	content.add_child(banner)

	var instructions = Label.new()
	instructions.text = "All fighting is resolved. Pick a unit to make its consolidation move (up to 3\"), or end your consolidation. Consolidating is optional — units you don't pick simply stay put."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Constrain the wrapped label's width so it reports a correct minimum HEIGHT.
	# An autowrap Label with no bounded width is measured at ~zero width while the
	# dialog pops up and returns a towering minimum height (~5500px), which inflates
	# the whole AcceptDialog to span/overflow the screen — the oversized embedded
	# window then renders as a black rectangle for the player.
	instructions.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 40, 0)
	instructions.add_theme_color_override("font_color", Color.YELLOW)
	content.add_child(instructions)
	content.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.name = "UnitScroll"
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 240)
	var unit_list = VBoxContainer.new()
	unit_list.name = "UnitList"

	var eligible: Dictionary = dialog_data.get("eligible_units", {})
	for unit_id in eligible:
		var info = eligible[unit_id]
		var mode = str(info.get("mode", ""))
		var mode_hint = ""
		match mode:
			"ongoing":
				mode_hint = "  [Ongoing — engaged: move closer to the enemy]"
			"engaging":
				mode_hint = "  [Engaging — enemy within 3\": may move into engagement]"
			"objective":
				mode_hint = "  [Objective — objective within 3\": may move onto it]"
			_:
				mode_hint = "  [No move possible from here]"
		var unit_button = Button.new()
		unit_button.name = "Consolidate_%s" % unit_id
		unit_button.text = "%s%s" % [info.get("name", unit_id), mode_hint]
		unit_button.pressed.connect(_on_unit_pressed.bind(unit_id))
		unit_list.add_child(unit_button)

	scroll.add_child(unit_list)
	content.add_child(scroll)
	content.add_child(HSeparator.new())

	var end_button = Button.new()
	end_button.name = "EndConsolidationButton"
	end_button.text = "End Consolidation (Player %d)" % player
	end_button.pressed.connect(_on_end_pressed)
	content.add_child(end_button)

	add_child(content)

	# The built-in OK button doubles as End Consolidation.
	get_ok_button().text = "End Consolidation"
	confirmed.connect(_on_end_pressed)

func _on_unit_pressed(unit_id: String) -> void:
	hide()
	# Release the stable node name before the deferred free so a replacement
	# picker can claim it without an auto-rename
	name = "StaleConsolidationStepDialog"
	emit_signal("consolidate_unit_chosen", unit_id)
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _on_end_pressed() -> void:
	hide()
	name = "StaleConsolidationStepDialog"
	emit_signal("end_consolidation", dialog_data.get("consolidating_player", 0))
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _create_colored_panel(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.2)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	return style

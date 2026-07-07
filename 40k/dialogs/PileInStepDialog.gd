extends AcceptDialog
class_name PileInStepDialog

# PileInStepDialog — 11e 12.02 global Pile In step.
# The fight phase OPENS with this step: each player in turn (active player
# first) may make one pile-in move with each of their eligible units
# (engaged, or charged this turn). Picking a unit opens the PileInDialog +
# interactive movement; "End Pile In" passes to the opponent (piling in is
# OPTIONAL per unit).
#
# Node names are stable on purpose (Content/PileIn_<unit_id>,
# Content/EndPileInButton) so windowed scenarios can click the same
# affordances a player sees.

signal pile_in_unit_chosen(unit_id: String)
signal end_pile_in(player: int)

var dialog_data: Dictionary = {}
var phase_reference = null

# Factory: build a ready-to-show dialog (script attached + UI built). The caller
# connects the signals, adds it to the tree, and calls popup_centered(). Shared
# by FightController and the windowed regression scenario so both exercise one
# construction path (and the autowrap-Label height guard in _build_ui).
static func create(data: Dictionary, phase) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.set_script(load("res://dialogs/PileInStepDialog.gd"))
	dialog.name = "PileInStepDialog"
	dialog.setup(data, phase)
	return dialog

func setup(data: Dictionary, phase) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	dialog_data = data
	phase_reference = phase
	title = "Pile In Step — Player %d" % data.get("piling_in_player", 0)
	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var content = VBoxContainer.new()
	content.name = "Content"
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var player = dialog_data.get("piling_in_player", 0)
	var banner = Panel.new()
	banner.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 40)
	var player_color = Color.BLUE if player == 1 else Color.RED
	banner.add_theme_stylebox_override("panel", _create_colored_panel(player_color))
	var banner_label = Label.new()
	banner_label.text = "PILE IN STEP — PLAYER %d" % player
	banner_label.add_theme_font_size_override("font_size", 20)
	banner_label.add_theme_color_override("font_color", Color.WHITE)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_label)
	content.add_child(banner)

	var instructions = Label.new()
	instructions.text = "The Fight phase opens with pile-ins. Pick a unit to make its pile-in move (up to 3\", each model closer to its pile-in target), or end your pile-in. Piling in is optional — units you don't pick simply stay put."
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
		var hint = "  [Engaged — every engaged enemy is a pile-in target]" if info.get("engaged", false) \
			else "  [Charged — pick enemy units within 5\" as targets]"
		var unit_button = Button.new()
		unit_button.name = "PileIn_%s" % unit_id
		unit_button.text = "%s%s" % [info.get("name", unit_id), hint]
		unit_button.pressed.connect(_on_unit_pressed.bind(unit_id))
		unit_list.add_child(unit_button)

	scroll.add_child(unit_list)
	content.add_child(scroll)
	content.add_child(HSeparator.new())

	var end_button = Button.new()
	end_button.name = "EndPileInButton"
	end_button.text = "End Pile In (Player %d)" % player
	end_button.pressed.connect(_on_end_pressed)
	content.add_child(end_button)

	add_child(content)

	# The built-in OK button doubles as End Pile In.
	get_ok_button().text = "End Pile In"
	confirmed.connect(_on_end_pressed)

func _on_unit_pressed(unit_id: String) -> void:
	hide()
	# Release the stable node name before the deferred free so a replacement
	# picker can claim it without an auto-rename
	name = "StalePileInStepDialog"
	emit_signal("pile_in_unit_chosen", unit_id)
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _on_end_pressed() -> void:
	hide()
	name = "StalePileInStepDialog"
	emit_signal("end_pile_in", dialog_data.get("piling_in_player", 0))
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

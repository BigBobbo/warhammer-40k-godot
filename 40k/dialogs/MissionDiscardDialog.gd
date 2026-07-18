extends AcceptDialog

# MissionDiscardDialog - Popup shown when ending a turn with active secondary missions
#
# Prompts the player to optionally discard a secondary mission for +1 CP
# before ending the Scoring phase. Lists all active secondary missions
# with discard buttons, or allows the player to skip and end without discarding.

signal mission_discard_requested(mission_index: int)
signal end_turn_without_discard()

# Max height for the mission list before it starts scrolling. Below this the
# scroll area shrinks to hug its content so the dialog doesn't leave a gap.
const MISSION_LIST_MAX_HEIGHT := 180.0

var active_missions: Array = []
var can_gain_cp: bool = false
var _mission_scroll: ScrollContainer = null
var _mission_list: VBoxContainer = null

# Factory: build a ready-to-show dialog (script attached + UI built). The caller
# connects the signals, adds it to the tree, and shows it (in-battle callers use
# DialogUtils.popup_at_bottom so the board stays visible). Shared by Main.gd and
# the windowed regression scenario so both exercise one path.
static func create(p_active_missions: Array, p_can_gain_cp: bool) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.set_script(load("res://dialogs/MissionDiscardDialog.gd"))
	dialog.name = "MissionDiscardDialog"
	dialog.setup(p_active_missions, p_can_gain_cp)
	return dialog

func setup(p_active_missions: Array, p_can_gain_cp: bool) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	active_missions = p_active_missions
	can_gain_cp = p_can_gain_cp

	title = "Discard a Secondary Mission?"
	# Keep the MEDIUM width, but let the height follow the content. The dialog is
	# short (a prompt, a fixed-height mission list, and one button), so pinning it
	# to the 400px MEDIUM height left a large empty gap at the bottom.
	min_size = Vector2(DialogConstants.MEDIUM.x, 0)

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "DISCARD FOR CP?"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	main_container.add_child(HSeparator.new())

	# Explanation
	var explain_label = Label.new()
	if can_gain_cp:
		explain_label.text = "You may discard one Secondary Mission to gain +1 CP.\nSelect a mission to discard, or end your turn without discarding."
	else:
		explain_label.text = "You may discard one Secondary Mission (bonus CP cap reached — no CP gained).\nSelect a mission to discard, or end your turn without discarding."
	explain_label.add_theme_font_size_override("font_size", 13)
	explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Constrain the wrapped label's width so it reports a correct minimum HEIGHT.
	# An autowrap Label with no width, measured while the dialog is popped up,
	# assumes ~zero width and returns a huge minimum height; with wrap_controls
	# that inflated the whole dialog to span the screen.
	explain_label.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 40, 0)
	main_container.add_child(explain_label)

	main_container.add_child(HSeparator.new())

	# Mission cards with discard buttons
	var scroll = ScrollContainer.new()
	var mission_list = VBoxContainer.new()
	mission_list.add_theme_constant_override("separation", 6)

	for i in range(active_missions.size()):
		var mission = active_missions[i]
		_add_mission_option(mission_list, mission, i)

	scroll.add_child(mission_list)
	# Fit the scroll area to its content, capped so a long list scrolls instead
	# of stretching the dialog. The previous fixed 180px height left an empty gap
	# below the list for the common 1-2 mission case. The final fit happens in
	# _ready() once the list is in the tree (its measured height is a few px
	# larger there); this pre-tree estimate just seeds a sensible size.
	_mission_scroll = scroll
	_mission_list = mission_list
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, _clamped_list_height())
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Bottom button - skip discarding
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var skip_button = Button.new()
	skip_button.text = "End Turn Without Discarding"
	skip_button.custom_minimum_size = Vector2(250, 40)
	skip_button.pressed.connect(_on_skip_pressed)
	button_container.add_child(skip_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _ready() -> void:
	# Re-fit the scroll to the list's real (in-tree) height, which is a few px
	# taller than the pre-tree estimate used while building. Runs before the
	# caller's popup call, so the dialog sizes correctly the first time and
	# short lists don't show a spurious scrollbar.
	if _mission_scroll and _mission_list:
		_mission_scroll.custom_minimum_size.y = _clamped_list_height()

func _clamped_list_height() -> float:
	# Mission list content height, capped so long lists scroll instead of growing
	# the dialog past the screen.
	if not _mission_list:
		return MISSION_LIST_MAX_HEIGHT
	return min(_mission_list.get_combined_minimum_size().y, MISSION_LIST_MAX_HEIGHT)

func _add_mission_option(parent: VBoxContainer, mission: Dictionary, index: int) -> void:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_color = Color(0.4, 0.35, 0.15)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	card.add_child(hbox)

	# Mission info (left side)
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label = Label.new()
	name_label.text = mission.get("name", "Unknown Mission")
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	name_label.add_theme_font_size_override("font_size", 13)
	info_vbox.add_child(name_label)

	var cat_label = Label.new()
	cat_label.text = mission.get("category", "").capitalize()
	cat_label.add_theme_font_size_override("font_size", 10)
	cat_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	info_vbox.add_child(cat_label)

	hbox.add_child(info_vbox)

	# Discard button (right side)
	var discard_btn = Button.new()
	var cp_label = "+1 CP" if can_gain_cp else "+0 CP (cap)"
	discard_btn.text = "Discard (%s)" % cp_label
	discard_btn.custom_minimum_size = Vector2(130, 36)
	discard_btn.add_theme_font_size_override("font_size", 12)
	discard_btn.add_theme_color_override("font_color", Color.GOLD)
	discard_btn.pressed.connect(_on_discard_pressed.bind(index))
	hbox.add_child(discard_btn)

func _on_discard_pressed(mission_index: int) -> void:
	print("MissionDiscardDialog: Player chose to discard mission index %d" % mission_index)
	emit_signal("mission_discard_requested", mission_index)
	hide()
	queue_free()

func _on_skip_pressed() -> void:
	print("MissionDiscardDialog: Player chose to end turn without discarding")
	emit_signal("end_turn_without_discard")
	hide()
	queue_free()

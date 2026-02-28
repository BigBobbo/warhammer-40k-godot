extends AcceptDialog
class_name TemptingTargetDialog

# TemptingTargetDialog - Single-step objective selection for A Tempting Target secondary mission
#
# When Player 1 draws A Tempting Target, Player 2 must select one objective
# in No Man's Land as the "Tempting Target". Player 1 scores VP by controlling it.

signal tempting_target_resolved(objective_id: String)

var nml_objectives: Array = []  # Array of { id, position, zone }
var opponent_player: int = 0

# UI references
var objective_list_container: VBoxContainer

func setup(opponent: int, objectives: Array) -> void:
	opponent_player = opponent
	nml_objectives = objectives

	title = "A Tempting Target — Player %d Selects Objective" % opponent
	min_size = DialogConstants.MEDIUM
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "A TEMPTING TARGET"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.ORANGE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Flavour text
	var flavour = Label.new()
	flavour.text = "Your opponent has drawn A Tempting Target.\nSelect one objective in No Man's Land to designate as the Tempting Target."
	flavour.add_theme_font_size_override("font_size", 12)
	flavour.add_theme_color_override("font_color", Color.GRAY)
	flavour.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(flavour)

	main_container.add_child(HSeparator.new())

	# Instruction
	var instruction = Label.new()
	instruction.text = "Select an objective:"
	instruction.add_theme_font_size_override("font_size", 14)
	instruction.add_theme_color_override("font_color", Color.CYAN)
	main_container.add_child(instruction)

	# Scroll container for objective list
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	objective_list_container = VBoxContainer.new()
	objective_list_container.name = "ObjectiveListContainer"
	scroll.add_child(objective_list_container)
	main_container.add_child(scroll)

	# Populate objectives
	_populate_objective_list()

	add_child(main_container)

func _populate_objective_list() -> void:
	for child in objective_list_container.get_children():
		objective_list_container.remove_child(child)
		child.queue_free()

	if nml_objectives.is_empty():
		var no_obj = Label.new()
		no_obj.text = "No objectives in No Man's Land."
		no_obj.add_theme_color_override("font_color", Color.RED)
		objective_list_container.add_child(no_obj)
		return

	for obj in nml_objectives:
		var obj_id = obj.get("id", "")
		var obj_pos = obj.get("position", {})
		var pos_text = ""
		if obj_pos.has("x") and obj_pos.has("y"):
			pos_text = " (%.0f\", %.0f\")" % [obj_pos.get("x", 0), obj_pos.get("y", 0)]

		var btn = Button.new()
		btn.text = "%s%s" % [obj_id.replace("obj_", "Objective ").to_upper(), pos_text]
		btn.custom_minimum_size = Vector2(410, 40)
		btn.pressed.connect(_on_objective_selected.bind(obj_id))
		objective_list_container.add_child(btn)

func _on_objective_selected(objective_id: String) -> void:
	print("TemptingTargetDialog: Objective selected: %s" % objective_id)
	emit_signal("tempting_target_resolved", objective_id)
	hide()
	queue_free()

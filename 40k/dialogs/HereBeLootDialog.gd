extends AcceptDialog
class_name HereBeLootDialog

# HereBeLootDialog - Objective selection for "Here Be Loot" detachment ability (OA-1)
#
# At the start of each battle round, the Freebooter Krew player selects one
# objective marker as the Loot Objective. ORKS INFANTRY/MOUNTED/WALKER units
# within range get Sustained Hits 1, and attacks targeting units near it also
# get Sustained Hits 1.

signal loot_objective_selected(player: int, objective_id: String)

var objectives: Array = []  # Array of { id, position, zone }
var selecting_player: int = 0

# UI references
var objective_list_container: VBoxContainer

func setup(player: int, available_objectives: Array) -> void:
	selecting_player = player
	objectives = available_objectives

	title = "Here Be Loot — Player %d Selects Loot Objective" % player
	min_size = DialogConstants.MEDIUM
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "HERE BE LOOT"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.0, 1.0, 0.2, 1.0))  # Orky green
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Flavour text
	var flavour = Label.new()
	flavour.text = "Da Kaptin's spotted sumfing shiny!\nSelect one objective marker as the Loot Objective.\nOrks near it get Sustained Hits 1, and attacks targeting units near it also get Sustained Hits 1."
	flavour.add_theme_font_size_override("font_size", 12)
	flavour.add_theme_color_override("font_color", Color.GRAY)
	flavour.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(flavour)

	main_container.add_child(HSeparator.new())

	# Instruction
	var instruction = Label.new()
	instruction.text = "Select a Loot Objective:"
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

	if objectives.is_empty():
		var no_obj = Label.new()
		no_obj.text = "No objectives available."
		no_obj.add_theme_color_override("font_color", Color.RED)
		objective_list_container.add_child(no_obj)
		return

	for obj in objectives:
		var obj_id = obj.get("id", "")
		var obj_pos = obj.get("position", {})
		var pos_text = ""
		if obj_pos is Vector2:
			pos_text = " (%.0f\", %.0f\")" % [obj_pos.x / 40.0, obj_pos.y / 40.0]
		elif obj_pos is Dictionary and obj_pos.has("x") and obj_pos.has("y"):
			pos_text = " (%.0f\", %.0f\")" % [obj_pos.get("x", 0) / 40.0, obj_pos.get("y", 0) / 40.0]
		var zone_text = ""
		var zone = obj.get("zone", "")
		if zone != "":
			zone_text = " [%s]" % zone.replace("_", " ").capitalize()

		var btn = Button.new()
		btn.text = "%s%s%s" % [obj_id.replace("obj_", "Objective ").to_upper(), pos_text, zone_text]
		btn.custom_minimum_size = Vector2(410, 40)
		btn.pressed.connect(_on_objective_selected.bind(obj_id))
		objective_list_container.add_child(btn)

func _on_objective_selected(objective_id: String) -> void:
	print("HereBeLootDialog: Player %d selected loot objective: %s" % [selecting_player, objective_id])
	emit_signal("loot_objective_selected", selecting_player, objective_id)
	hide()
	queue_free()

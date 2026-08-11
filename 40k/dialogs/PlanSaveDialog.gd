extends AcceptDialog
class_name PlanSaveDialog

# PM-5 — "Save as Plan" for the Plan Editor sandbox.
#
# Reads the laid-out board back through PlanRecorder and writes it to
# user://ai_plans/. The dialog deliberately does NOT close on a failed save:
# PlanManager refuses an invalid plan by design, and the author needs to see
# WHY on the same screen as the fields they would fix.
#
# Every control the player touches lives under the dialog's own VBox with a
# stable name — PlanNameEdit / PlanDescriptionEdit / PlanAuthorEdit /
# PlanSaveButton / PlanCancelButton / PlanSaveFeedback. AcceptDialog's built-in
# OK button is hidden instead of reused: its node path is auto-generated
# (@PanelContainer@123/@Button@456), so a windowed scenario cannot click it.

const PlanRecorderScript = preload("res://scripts/PlanRecorder.gd")

signal plan_saved(path: String)

var name_edit: LineEdit = null
var description_edit: LineEdit = null
var author_edit: LineEdit = null
var feedback_label: RichTextLabel = null

# Last save attempt, for scenarios and for the caller's toast.
var last_result: Dictionary = {}


func setup(default_name: String = "", default_author: String = "") -> void:
	title = "Save as Plan"
	# We close the dialog ourselves, only on success — otherwise a refused save
	# would vanish along with the error message explaining the refusal.
	dialog_hide_on_ok = false
	get_ok_button().visible = false

	var root := VBoxContainer.new()
	root.name = "PlanSaveRoot"
	root.add_theme_constant_override("separation", 8)
	root.custom_minimum_size = Vector2(520, 0)
	add_child(root)

	var blurb := Label.new()
	blurb.name = "PlanSaveBlurb"
	blurb.text = "Records the board as it stands: deployment order, every model's position, plus anything held in reserve, embarked or attached. Unit roles (intents) are added separately."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(500, 0)
	root.add_child(blurb)

	name_edit = _add_field(root, "Name", "PlanNameEdit", default_name,
		"Used for the filename — two plans with the same name overwrite each other.")
	description_edit = _add_field(root, "Description", "PlanDescriptionEdit", "",
		"Optional. What this plan is trying to do.")
	author_edit = _add_field(root, "Author", "PlanAuthorEdit", default_author, "Optional.")

	feedback_label = RichTextLabel.new()
	feedback_label.name = "PlanSaveFeedback"
	feedback_label.bbcode_enabled = true
	feedback_label.fit_content = true
	feedback_label.scroll_active = false
	feedback_label.custom_minimum_size = Vector2(500, 0)
	root.add_child(feedback_label)

	var actions := HBoxContainer.new()
	actions.name = "PlanSaveActions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)

	var cancel_button := Button.new()
	cancel_button.name = "PlanCancelButton"
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(hide)
	actions.add_child(cancel_button)

	var save_button := Button.new()
	save_button.name = "PlanSaveButton"
	save_button.text = "Save Plan"
	save_button.pressed.connect(_on_save_pressed)
	actions.add_child(save_button)

	# Enter in any field saves, matching what the hidden OK button would do.
	confirmed.connect(_on_save_pressed)


func _add_field(parent: Node, label_text: String, node_name: String, default_value: String, tooltip: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.name = node_name + "Row"
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)

	var edit := LineEdit.new()
	edit.name = node_name
	edit.text = default_value
	edit.tooltip_text = tooltip
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _on_save_pressed() -> void:
	var plan_name := name_edit.text.strip_edges() if name_edit else ""
	if plan_name.is_empty():
		_show_feedback(["A plan needs a name — it is also the filename."], [], false)
		return

	var terrain_pieces: Array = []
	var terrain_mgr = get_node_or_null("/root/TerrainManager")
	if terrain_mgr != null and "terrain_features" in terrain_mgr:
		terrain_pieces = terrain_mgr.terrain_features

	last_result = PlanRecorderScript.record_and_save(GameState.state, {
		"name": plan_name,
		"description": description_edit.text.strip_edges() if description_edit else "",
		"author": author_edit.text.strip_edges() if author_edit else "",
		"player": 1,
	}, terrain_pieces)

	var ok: bool = bool(last_result.get("success", false))
	_show_feedback(last_result.get("errors", []), last_result.get("warnings", []),
		ok, str(last_result.get("path", "")))

	if ok:
		emit_signal("plan_saved", str(last_result.get("path", "")))
		# Leave the dialog up for a beat so the author sees the path it wrote,
		# then close. A scenario reads `last_result` and does not have to wait.
		await get_tree().create_timer(1.2).timeout
		if is_inside_tree():
			hide()


func _show_feedback(errors: Array, warnings: Array, success: bool, path: String = "") -> void:
	if feedback_label == null:
		return
	var lines: Array[String] = []
	if success:
		lines.append("[color=#7CCB6B]Saved to %s[/color]" % path)
	for e in errors:
		lines.append("[color=#E06C6C]%s[/color]" % str(e))
	for w in warnings:
		lines.append("[color=#D9B44A]%s[/color]" % str(w))
	if lines.is_empty():
		feedback_label.text = ""
	else:
		feedback_label.text = "\n".join(lines)

extends AcceptDialog
class_name PlanBrowserDialog

# PM-7b — browse the AI plans on the search path.
#
# One row per plan: name, army, zone, terrain layout, author, and a validation
# badge straight from PlanValidator (via PlanManager.list_plans, which already
# validates every entry it returns).
#
# Shipped `res://` plans are listed but cannot be deleted or renamed: in an
# exported build they are inside the PCK, so there is no file to remove. The
# buttons are disabled for them rather than hidden, so the reason is visible
# (a hidden control just looks like a bug).
#
# Stable node names for windowed scenarios:
#   PlanBrowserTree / PlanBrowserDetail / PlanBrowserRenameEdit /
#   PlanBrowserRenameButton / PlanBrowserDeleteButton / PlanBrowserRefreshButton
#   PlanBrowserCloseButton / PlanBrowserStatus
# and the confirm step: PlanDeleteConfirm (a ConfirmationDialog).

const PlanManagerScript = preload("res://scripts/PlanManager.gd")

const COL_NAME := 0
const COL_ARMY := 1
const COL_ZONE := 2
const COL_LAYOUT := 3
const COL_STATUS := 4
const COL_SOURCE := 5

const VALID_COLOR := Color(0.49, 0.80, 0.42)
const INVALID_COLOR := Color(0.88, 0.42, 0.42)
const WARN_COLOR := Color(0.85, 0.71, 0.29)

var tree_ctl: Tree = null
var detail_label: RichTextLabel = null
var rename_edit: LineEdit = null
var rename_button: Button = null
var delete_button: Button = null
var status_label: Label = null
var confirm_dialog: ConfirmationDialog = null

# path -> entry, for the row currently selected.
var selected_path: String = ""
var _entries: Array = []


func setup() -> void:
	title = "AI Plans"
	get_ok_button().visible = false
	dialog_hide_on_ok = false

	var root := VBoxContainer.new()
	root.name = "PlanBrowserRoot"
	root.add_theme_constant_override("separation", 8)
	root.custom_minimum_size = Vector2(900, 0)
	add_child(root)

	tree_ctl = Tree.new()
	tree_ctl.name = "PlanBrowserTree"
	# A fixed height for the list, NOT SIZE_EXPAND_FILL: an expanding Tree makes
	# AcceptDialog grow to the full screen height at popup_centered() time and
	# pushes the action row off the bottom edge.
	tree_ctl.custom_minimum_size = Vector2(0, 300)
	tree_ctl.columns = 6
	tree_ctl.column_titles_visible = true
	tree_ctl.hide_root = true
	tree_ctl.select_mode = Tree.SELECT_ROW
	tree_ctl.set_column_title(COL_NAME, "Plan")
	tree_ctl.set_column_title(COL_ARMY, "Army")
	tree_ctl.set_column_title(COL_ZONE, "Deployment")
	tree_ctl.set_column_title(COL_LAYOUT, "Terrain")
	tree_ctl.set_column_title(COL_STATUS, "Status")
	tree_ctl.set_column_title(COL_SOURCE, "Where")
	tree_ctl.set_column_expand_ratio(COL_NAME, 3)
	tree_ctl.set_column_expand_ratio(COL_ARMY, 2)
	tree_ctl.set_column_expand_ratio(COL_ZONE, 2)
	tree_ctl.set_column_expand_ratio(COL_LAYOUT, 3)
	tree_ctl.set_column_expand_ratio(COL_STATUS, 2)
	tree_ctl.set_column_expand_ratio(COL_SOURCE, 1)
	tree_ctl.item_selected.connect(_on_row_selected)
	root.add_child(tree_ctl)

	detail_label = RichTextLabel.new()
	detail_label.name = "PlanBrowserDetail"
	detail_label.bbcode_enabled = true
	detail_label.fit_content = true
	detail_label.scroll_active = false
	detail_label.custom_minimum_size = Vector2(0, 70)
	root.add_child(detail_label)

	var actions := HBoxContainer.new()
	actions.name = "PlanBrowserActions"
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	var rename_label := Label.new()
	rename_label.text = "Rename to:"
	actions.add_child(rename_label)

	rename_edit = LineEdit.new()
	rename_edit.name = "PlanBrowserRenameEdit"
	rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_edit.placeholder_text = "New name"
	actions.add_child(rename_edit)

	rename_button = Button.new()
	rename_button.name = "PlanBrowserRenameButton"
	rename_button.text = "Rename"
	rename_button.pressed.connect(_on_rename_pressed)
	actions.add_child(rename_button)

	delete_button = Button.new()
	delete_button.name = "PlanBrowserDeleteButton"
	delete_button.text = "Delete"
	delete_button.pressed.connect(_on_delete_pressed)
	actions.add_child(delete_button)

	var refresh_button := Button.new()
	refresh_button.name = "PlanBrowserRefreshButton"
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh)
	actions.add_child(refresh_button)

	var close_button := Button.new()
	close_button.name = "PlanBrowserCloseButton"
	close_button.text = "Close"
	close_button.pressed.connect(hide)
	actions.add_child(close_button)

	status_label = Label.new()
	status_label.name = "PlanBrowserStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	root.add_child(status_label)

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.name = "PlanDeleteConfirm"
	confirm_dialog.title = "Delete plan"
	confirm_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(confirm_dialog)

	refresh()


# ============================================================
# Listing
# ============================================================

func refresh() -> void:
	if tree_ctl == null:
		return
	var previously := selected_path
	tree_ctl.clear()
	_entries = PlanManagerScript.list_plans()
	var root_item := tree_ctl.create_item()

	for entry in _entries:
		var meta_data: Dictionary = entry.get("metadata", {})
		var item := tree_ctl.create_item(root_item)
		item.set_text(COL_NAME, str(entry.get("name", "")))
		item.set_text(COL_ARMY, str(meta_data.get("army_file", "—")))
		item.set_text(COL_ZONE, str(meta_data.get("deployment_zone_id", "—")))
		var layout := str(meta_data.get("terrain_layout_id", ""))
		item.set_text(COL_LAYOUT, layout if layout != "" else "any")
		item.set_text(COL_SOURCE, "yours" if str(entry.get("source", "")) == "user" else "shipped")
		item.set_metadata(COL_NAME, str(entry.get("path", "")))

		var errors: Array = meta_data.get("errors", [])
		var warnings: Array = meta_data.get("warnings", [])
		if not bool(meta_data.get("valid", false)):
			item.set_text(COL_STATUS, "%d problem(s)" % errors.size())
			item.set_custom_color(COL_STATUS, INVALID_COLOR)
		elif not warnings.is_empty():
			item.set_text(COL_STATUS, "OK, %d note(s)" % warnings.size())
			item.set_custom_color(COL_STATUS, WARN_COLOR)
		else:
			item.set_text(COL_STATUS, "OK")
			item.set_custom_color(COL_STATUS, VALID_COLOR)

	selected_path = ""
	_select_path(previously)
	if selected_path == "":
		_update_detail({})
	_set_status("%d plan(s) — %d of your own." % [_entries.size(), _user_plan_count()])


func _user_plan_count() -> int:
	var n := 0
	for entry in _entries:
		if str(entry.get("source", "")) == "user":
			n += 1
	return n


func _select_path(path: String) -> void:
	if path == "":
		return
	var item := tree_ctl.get_root()
	if item == null:
		return
	item = item.get_first_child()
	while item != null:
		if str(item.get_metadata(COL_NAME)) == path:
			item.select(COL_NAME)
			_on_row_selected()
			return
		item = item.get_next()


func entry_for(path: String) -> Dictionary:
	for entry in _entries:
		if str(entry.get("path", "")) == path:
			return entry
	return {}


func row_count() -> int:
	return _entries.size()


# ============================================================
# Selection / actions
# ============================================================

func _on_row_selected() -> void:
	var item := tree_ctl.get_selected()
	if item == null:
		return
	selected_path = str(item.get_metadata(COL_NAME))
	var entry := entry_for(selected_path)
	_update_detail(entry)

	# Shipped plans live in the PCK in an export — there is no file to rewrite
	# or remove, so both actions are disabled (and say why) rather than hidden.
	var is_user: bool = str(entry.get("source", "")) == "user"
	rename_button.disabled = not is_user
	delete_button.disabled = not is_user
	rename_edit.editable = is_user
	rename_edit.text = str(entry.get("name", "")) if is_user else ""
	if is_user:
		_set_status("")
	else:
		_set_status("'%s' ships with the game — it can be used but not renamed or deleted." % str(entry.get("name", "")))


func _update_detail(entry: Dictionary) -> void:
	if detail_label == null:
		return
	if entry.is_empty():
		detail_label.text = "[i]Pick a plan to see its details.[/i]"
		return
	var meta_data: Dictionary = entry.get("metadata", {})
	var lines: Array[String] = []
	var author := str(meta_data.get("author", ""))
	var description := str(meta_data.get("description", ""))
	if description != "":
		lines.append(description)
	lines.append("[color=#B9B2A0]%s%s[/color]" % [
		("by %s · " % author) if author != "" else "", str(entry.get("path", ""))])
	for e in meta_data.get("errors", []):
		lines.append("[color=#E06C6C]%s[/color]" % str(e))
	for w in meta_data.get("warnings", []):
		lines.append("[color=#D9B44A]%s[/color]" % str(w))
	detail_label.text = "\n".join(lines)


func _on_rename_pressed() -> void:
	if selected_path == "":
		_set_status("Pick a plan first.")
		return
	var result: Dictionary = PlanManagerScript.rename_plan(selected_path, rename_edit.text)
	if not result.get("success", false):
		_set_status(str(result.get("error", "Rename failed.")))
		return
	selected_path = str(result.get("path", ""))
	refresh()
	_set_status("Renamed to '%s'." % rename_edit.text.strip_edges())


func _on_delete_pressed() -> void:
	if selected_path == "":
		_set_status("Pick a plan first.")
		return
	var entry := entry_for(selected_path)
	confirm_dialog.dialog_text = "Delete '%s'? This cannot be undone." % str(entry.get("name", selected_path))
	confirm_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if selected_path == "":
		return
	var doomed := selected_path
	var name := str(entry_for(doomed).get("name", doomed))
	if PlanManagerScript.delete_plan(doomed):
		selected_path = ""
		refresh()
		_set_status("Deleted '%s'." % name)
	else:
		_set_status("Could not delete '%s'." % name)


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text

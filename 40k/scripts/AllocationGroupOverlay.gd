extends Control
class_name AllocationGroupOverlay

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

## ISS-045 — the 11e defender allocation UI (core rules 05.03-05.04).
## Replaces WoundAllocationOverlay's per-wound click loop at edition ≥ 11:
## the defender divides the target into allocation groups ONCE per attack
## batch, orders them under the 05.03 constraints (validated live), then
## the save batch is rolled and damage applied lowest→highest
## automatically via RulesEngine.resolve_allocation_batch_11e.
##
## Contract mirrors WoundAllocationOverlay: instantiate, add to tree,
## `setup(save_data, defender_player)`, listen for
## `allocation_complete(summary)`. The overlay applies the outcome to
## GameState directly (single source of dice on the defending peer); the
## summary carries the same idempotent `set` diffs for the APPLY_SAVES
## action path.

signal allocation_complete(summary: Dictionary)

var save_data: Dictionary = {}
var defender_player: int = 0
var groups: Array = []
var order: Array = []  # group ids in the defender's chosen order
var rng_service = null  # RulesEngine.RNGService (lazy-typed: autoload ids are not compile-time resolvable in bare `godot -s` runs)
var batch_result: Dictionary = {}
var resolved: bool = false

# Lazy autoload lookups (same reason as above).
func _rules() -> Node:
	return get_node("/root/RulesEngine")


func _game_state() -> Node:
	return get_node("/root/GameState")


var dim: ColorRect = null
var panel: PanelContainer = null
var group_list: VBoxContainer = null
var error_label: Label = null
var confirm_button: Button = null
var result_panel: VBoxContainer = null
var result_label: RichTextLabel = null
var done_button: Button = null


# 24.28 [PRECISION] (audit #13): the ATTACKER's promotion pick — an
# OptionButton listing the visibility-gated eligible CHARACTER groups.
var precision_picker: OptionButton = null
var _precision_eligible: Array = []

func setup(p_save_data: Dictionary, p_defender_player: int) -> void:
	save_data = p_save_data
	defender_player = p_defender_player
	rng_service = _rules().make_rng()
	var target_unit_id = str(save_data.get("target_unit_id", ""))
	var virtual_unit = _rules()._build_attached_allocation_unit_11e(target_unit_id, _game_state().state).unit
	groups = Allocation.build_groups(virtual_unit)
	order = Allocation.default_order(groups)
	_build_ui()
	_rebuild_group_list()
	print("AllocationGroupOverlay: setup — %d group(s), %d wound(s) to save vs %s" % [
		groups.size(), int(save_data.get("wounds_to_save", 0)), target_unit_id])
	# 05.03: with a single group there is no order decision — resolve
	# immediately (the results panel still requires the Done click).
	if groups.size() <= 1:
		print("AllocationGroupOverlay: single allocation group — order is forced, auto-resolving")
		_on_confirm_pressed()


func _build_ui() -> void:
	name = "AllocationGroupOverlay"
	# Parent is Main (a CanvasLayer): anchors AND offsets must be applied
	# for the rect to fill the viewport (set_anchors_preset alone leaves
	# the size at 0x0).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 2000  # above the phase banner / HUD (UI_MODAL_Z)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# UI-CONSISTENCY: share the White Dwarf chrome with WeaponOrderDialog and
	# the other shooting dialogs. The theme cascades to every Button / Label /
	# OptionButton descendant (including the reorder rows rebuilt later), so the
	# wound-allocation window reads as the same UI as the weapon-order window.
	_WhiteDwarfTheme.apply_to_control_theme(self)

	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(560, 0)
	# Gothic gold-bordered parchment-dark panel + inner padding. Content margins
	# live on the stylebox (not a wrapper node) so the scenario node paths
	# Panel/VBox/... stay intact.
	var panel_style = _WhiteDwarfTheme.create_panel_style()
	panel_style.bg_color = Color(0.1, 0.09, 0.07, 0.97)
	panel_style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title = Label.new()
	title.name = "Title"
	title.text = "Allocate Attacks — %s" % str(save_data.get("target_unit_name", save_data.get("target_unit_id", "")))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_WhiteDwarfTheme.add_gold_separator(vbox)

	var info = Label.new()
	info.name = "Info"
	var dev_txt = ""
	if save_data.get("has_devastating_wounds", false) and int(save_data.get("devastating_wounds", 0)) > 0:
		dev_txt = " + %d devastating" % int(save_data.get("devastating_wounds", 0))
	info.text = "%s: %d wound(s) to save%s   AP %d   D %s" % [
		str(save_data.get("weapon_name", "Attack")),
		int(save_data.get("wounds_to_save", 0)), dev_txt,
		int(save_data.get("ap", 0)),
		str(save_data.get("damage_raw", save_data.get("damage", 1)))]
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	vbox.add_child(info)

	var hint = Label.new()
	hint.name = "Hint"
	hint.text = "Declare the allocation order (05.03). Damage is applied lowest save roll → highest against the current group."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(hint)

	# 24.28 [PRECISION]: attacker's promotion choice (visibility-gated).
	_precision_eligible = _rules().precision_eligible_groups_11e(save_data, _game_state().state)
	if not _precision_eligible.is_empty():
		var prec_label = Label.new()
		prec_label.name = "PrecisionLabel"
		prec_label.text = "PRECISION (24.28) — attacker may make a visible CHARACTER group the current allocation group:"
		prec_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prec_label.add_theme_font_size_override("font_size", 13)
		prec_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
		vbox.add_child(prec_label)
		precision_picker = OptionButton.new()
		precision_picker.name = "PrecisionPicker"
		precision_picker.add_item("No promotion", 0)
		for gi in range(_precision_eligible.size()):
			precision_picker.add_item("Promote %s" % str(_precision_eligible[gi].label), gi + 1)
		precision_picker.selected = 1  # default: promote the first eligible group
		vbox.add_child(precision_picker)

	_WhiteDwarfTheme.add_gold_separator(vbox)

	# Section label so the ordered rows read as "FIRING ORDER" does in the
	# weapon-order window.
	var order_label = Label.new()
	order_label.name = "OrderLabel"
	order_label.text = "ALLOCATION ORDER"
	order_label.add_theme_font_size_override("font_size", 13)
	order_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	vbox.add_child(order_label)

	group_list = VBoxContainer.new()
	group_list.name = "GroupList"
	group_list.add_theme_constant_override("separation", 4)
	vbox.add_child(group_list)

	error_label = Label.new()
	error_label.name = "ErrorLabel"
	error_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_RED)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.text = ""
	vbox.add_child(error_label)

	_WhiteDwarfTheme.add_gold_separator(vbox)

	confirm_button = Button.new()
	confirm_button.name = "ConfirmButton"
	confirm_button.text = "Confirm Order & Roll Saves"
	confirm_button.custom_minimum_size = Vector2(0, 42)
	confirm_button.pressed.connect(_on_confirm_pressed)
	_WhiteDwarfTheme.apply_primary_button(confirm_button)
	vbox.add_child(confirm_button)

	result_panel = VBoxContainer.new()
	result_panel.name = "ResultPanel"
	result_panel.add_theme_constant_override("separation", 8)
	result_panel.visible = false
	vbox.add_child(result_panel)

	result_label = RichTextLabel.new()
	result_label.name = "ResultLabel"
	result_label.bbcode_enabled = false
	result_label.fit_content = true
	result_label.custom_minimum_size = Vector2(520, 0)
	result_label.add_theme_color_override("default_color", _WhiteDwarfTheme.WH_PARCHMENT)
	result_panel.add_child(result_label)

	done_button = Button.new()
	done_button.name = "DoneButton"
	done_button.text = "Done"
	done_button.custom_minimum_size = Vector2(0, 42)
	done_button.pressed.connect(_on_done_pressed)
	_WhiteDwarfTheme.apply_primary_button(done_button)
	result_panel.add_child(done_button)


func _group_by_id(gid: String) -> Dictionary:
	for g in groups:
		if g.id == gid:
			return g
	return {}


func _group_label(g: Dictionary, order_index: int) -> String:
	var desc = "%d. " % (order_index + 1)
	if g.character:
		desc += "CHARACTER — "
	desc += "%d model(s)  W%d  Sv%s  InSv%s" % [
		g.model_indices.size(), g.w,
		("%d+" % g.sv) if g.sv < 7 else "-",
		("%d+" % g.insv) if g.insv > 0 else "-"]
	if g.has_wounded:
		desc += "  [wounded]"
	return desc


func _rebuild_group_list() -> void:
	for child in group_list.get_children():
		# Rename before the deferred free so replacement rows keep the
		# canonical Row<N>/Up<N>/Down<N> paths (scenarios click these).
		child.name = "_dying_row"
		child.queue_free()
	for i in range(order.size()):
		var g = _group_by_id(order[i])
		var row = HBoxContainer.new()
		row.name = "Row%d" % i
		var lbl = Label.new()
		lbl.name = "GroupLabel"
		lbl.text = _group_label(g, i)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var up = Button.new()
		up.name = "Up%d" % i
		up.text = "▲"
		up.disabled = i == 0
		up.pressed.connect(_on_move.bind(i, -1))
		row.add_child(up)
		var down = Button.new()
		down.name = "Down%d" % i
		down.text = "▼"
		down.disabled = i == order.size() - 1
		down.pressed.connect(_on_move.bind(i, 1))
		row.add_child(down)
		group_list.add_child(row)
	_validate_order()


func _on_move(index: int, delta: int) -> void:
	var j = index + delta
	if j < 0 or j >= order.size():
		return
	var tmp = order[index]
	order[index] = order[j]
	order[j] = tmp
	_rebuild_group_list()


func _validate_order() -> void:
	var check = Allocation.validate_order(groups, order)
	if check.valid:
		error_label.text = ""
		confirm_button.disabled = false
	else:
		error_label.text = "Illegal order: " + "; ".join(check.errors)
		confirm_button.disabled = true
	print("AllocationGroupOverlay: order %s valid=%s" % [str(order), str(check.valid)])


func _on_confirm_pressed() -> void:
	if resolved:
		return
	var check = Allocation.validate_order(groups, order)
	if not check.valid:
		print("AllocationGroupOverlay: confirm blocked — illegal order %s" % str(order))
		return
	resolved = true
	confirm_button.disabled = true
	# 24.28: carry the attacker's PRECISION promotion pick (or explicit
	# decline) into the engine; "" auto-picks / no-ops as appropriate.
	if precision_picker != null:
		var sel = precision_picker.selected
		if sel >= 1 and sel - 1 < _precision_eligible.size():
			save_data["precision_group_choice"] = str(_precision_eligible[sel - 1].id)
		else:
			save_data["precision_group_choice"] = ""
			save_data["has_precision"] = false  # attacker declined the promotion
	batch_result = _rules().resolve_allocation_batch_11e(save_data, order, _game_state().state, rng_service)
	_apply_diffs_to_gamestate(batch_result.get("diffs", []))
	var target_unit_id = str(save_data.get("target_unit_id", ""))
	if batch_result.get("casualties", 0) > 0:
		get_node("/root/CharacterAttachmentManager").check_bodyguard_destroyed(target_unit_id)
		get_node("/root/SecondaryMissionManager").check_and_report_unit_destroyed(target_unit_id)
	_refresh_board_visuals()
	_show_results()


func _apply_diffs_to_gamestate(diffs: Array) -> void:
	for diff in diffs:
		var parts = str(diff.get("path", "")).split(".")
		if parts.size() != 5 or parts[0] != "units" or parts[2] != "models":
			continue
		var unit_id = parts[1]
		var mi = int(parts[3])
		var field = parts[4]
		var unit = _game_state().state.get("units", {}).get(unit_id, {})
		var models = unit.get("models", [])
		if mi >= 0 and mi < models.size():
			models[mi][field] = diff.get("value")
			if field == "alive" and diff.get("value") == false:
				print("AllocationGroupOverlay: 💀 %s removed (unit %s, model %d)" % [
					_rules().get_model_display_label(models[mi], unit), unit_id, mi])


func _refresh_board_visuals() -> void:
	# Runtime-node form of the SceneRefs chokepoint: this overlay is also
	# compiled standalone by headless tests, where autoload identifiers
	# don't resolve at parse time.
	var refs = Engine.get_main_loop().root.get_node_or_null("SceneRefs")
	var main = refs.main() if refs != null else null
	if main and main.has_method("refresh_all_model_visuals"):
		main.refresh_all_model_visuals()


func _show_results() -> void:
	group_list.visible = false
	confirm_button.visible = false
	error_label.visible = false
	var lines: Array = []
	var rolls: Array = batch_result.get("save_rolls", []).duplicate()
	rolls.sort()
	lines.append("Save rolls (lowest first): %s" % str(rolls))
	lines.append("%d saved, %d failed — %d damage, %d model(s) destroyed" % [
		batch_result.get("saves_passed", 0), batch_result.get("saves_failed", 0),
		batch_result.get("damage_applied", 0), batch_result.get("casualties", 0)])
	for d in batch_result.get("dice", []):
		if d.get("context", "") == "devastating_wounds_11e":
			lines.append("Devastating wounds: %d crit(s) applied as mortal wounds (max one model each)" % d.get("crits", 0))
	result_label.text = "\n".join(lines)
	result_panel.visible = true
	print("AllocationGroupOverlay: resolved — %s" % "; ".join(lines))


func _on_done_pressed() -> void:
	var summary = batch_result.duplicate(true)
	summary["total_damage"] = summary.get("damage_applied", 0)
	summary["models_destroyed"] = summary.get("casualties", 0)
	summary["allocation_order"] = order
	emit_signal("allocation_complete", summary)
	queue_free()

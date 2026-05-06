extends AcceptDialog
class_name StratagemPanel

# T-023: Pre-game stratagems UI shell — list all eligible stratagems for the
# active phase / player with CP cost, faction/core/detachment grouping, and
# active state.
#
# Triggered from a HUD button (or the "S" hotkey). Iterates
# StratagemManager.stratagems and renders rows. Greyed-out for ineligible
# (off-phase, insufficient CP, once-per-X exhausted).

signal stratagem_use_requested(stratagem_id: String)

var _player: int = 1
var _phase_id: int = 0
var _list_container: VBoxContainer = null
var _empty_label: Label = null


func _ready() -> void:
	title = "Stratagems"
	min_size = Vector2(560, 480)
	get_ok_button().text = "Close"
	_build_ui()


func _build_ui() -> void:
	if _list_container != null:
		return
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 420)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	_list_container = vb
	_empty_label = Label.new()
	_empty_label.text = "No stratagems available."
	_empty_label.visible = false
	_list_container.add_child(_empty_label)


func populate(player: int, phase_id: int = -1) -> void:
	_player = player
	_phase_id = phase_id
	_build_ui()
	# Clear previous rows (keep _empty_label)
	for child in _list_container.get_children():
		if child == _empty_label:
			continue
		child.queue_free()

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager == null:
		_empty_label.text = "StratagemManager not available."
		_empty_label.visible = true
		return

	var cp = 0
	if strat_manager.has_method("get_player_cp"):
		cp = strat_manager.get_player_cp(player)
	title = "Stratagems — Player %d (%d CP)" % [player, cp]

	var stratagems_dict: Dictionary = strat_manager.get("stratagems")
	if stratagems_dict == null or stratagems_dict.is_empty():
		_empty_label.text = "No stratagems loaded."
		_empty_label.visible = true
		return
	_empty_label.visible = false

	# Group by source: core / faction / detachment.
	var groups = {"Core": [], "Faction": [], "Detachment": []}
	for sid in stratagems_dict.keys():
		var strat = stratagems_dict[sid]
		var source = strat.get("source", "Core")
		var bucket = "Core"
		var src_lower = String(source).to_lower()
		if "detachment" in src_lower:
			bucket = "Detachment"
		elif strat_manager.has_method("is_faction_stratagem") and strat_manager.is_faction_stratagem(sid):
			bucket = "Faction"
		groups[bucket].append(sid)

	for group_name in ["Core", "Faction", "Detachment"]:
		var ids = groups[group_name]
		if ids.is_empty():
			continue
		var header = Label.new()
		header.text = "── %s ──" % group_name
		header.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
		_list_container.add_child(header)
		for sid in ids:
			var strat = stratagems_dict[sid]
			# Ownership filter: faction stratagems only show for owning player.
			if strat_manager.has_method("get_stratagem_owner"):
				var owner_id = strat_manager.get_stratagem_owner(sid)
				if owner_id != 0 and owner_id != player:
					continue
			_list_container.add_child(_build_row(strat_manager, sid, strat, cp))


func _build_row(strat_manager: Node, sid: String, strat: Dictionary, current_cp: int) -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var validation = {"can_use": false, "reason": ""}
	if strat_manager.has_method("can_use_stratagem"):
		validation = strat_manager.can_use_stratagem(_player, sid)
	var can_use = bool(validation.get("can_use", false))

	var name_label = Label.new()
	var display = strat.get("name", sid)
	var cost = int(strat.get("cp_cost", strat.get("cost", 0)))
	name_label.text = "%s (%d CP)" % [display, cost]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var status_label = Label.new()
	if can_use:
		status_label.text = "ELIGIBLE"
		name_label.add_theme_color_override("font_color", Color(1, 1, 1))
		status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	else:
		var reason = String(validation.get("reason", "ineligible"))
		status_label.text = reason
		var grey = Color(0.55, 0.55, 0.55)
		name_label.add_theme_color_override("font_color", grey)
		status_label.add_theme_color_override("font_color", grey)
	status_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(status_label)

	var use_btn = Button.new()
	use_btn.text = "Use"
	use_btn.disabled = not can_use or current_cp < cost
	use_btn.pressed.connect(func(): emit_signal("stratagem_use_requested", sid))
	row.add_child(use_btn)

	return row


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and visible:
			hide()

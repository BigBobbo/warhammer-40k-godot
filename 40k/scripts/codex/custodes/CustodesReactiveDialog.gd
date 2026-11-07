extends AcceptDialog

## CustodesReactiveDialog — WP-G5 player UI for NO ESCAPE / SELFLESS SERVICE
## (charge: Roll -> pick targets -> the board's charge-move tools) and RAPID
## REACTIONS (weapon choice -> Roll Attacks -> results). Built by
## CustodesReactive.open_ui; every button sends a CUS11E_REACTIVE_* action
## through NetworkIntegration (CustodesReactive.submit). It reads the flow's
## state from the phase (CustodesReactive.info) each time it is shown.
##
## Node names (windowed scenarios): /root/Cus11eReactiveDialog/Content/
##   Header, Body, RollButton, RollResult, Targets/Target_<unit_id>,
##   Targets/Miss_<unit_id>, DeclareButton, FailButton,
##   Weapons/Weapon_<i>/Use, Weapons/Weapon_<i>/Profile, ShootButton,
##   SkipButton, Result, DoneButton

const Reactive = preload("res://scripts/codex/custodes/CustodesReactive.gd")

var _content: VBoxContainer = null
var _phase = null
var _info: Dictionary = {}


func _ready() -> void:
	title = "Adeptus Custodes — reactive stratagem"
	get_ok_button().visible = false
	exclusive = false
	unresizable = false
	min_size = Vector2i(560, 260)
	# The decision cannot be dismissed half-made: the window comes back.
	canceled.connect(_on_cancel)
	WhiteDwarfTheme.apply_to_dialog(self)


func _on_cancel() -> void:
	if bool(get_meta("showing_result", false)):
		queue_free()
		return
	call_deferred("popup_centered")


func _clear() -> void:
	if _content != null and is_instance_valid(_content):
		remove_child(_content)
		_content.queue_free()
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.custom_minimum_size = Vector2(540, 0)
	_content.add_theme_constant_override("separation", 8)
	add_child(_content)


func _label(node_name: String, text: String, size: int = 16, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_content.add_child(l)
	return l


func _button(node_name: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	_content.add_child(b)
	return b


## (Re)build the dialog for the phase's pending flow.
func show_for(phase) -> void:
	_phase = phase
	_info = Reactive.info(phase)
	if _info.is_empty():
		if not bool(get_meta("showing_result", false)):
			queue_free()
		return
	set_meta("showing_result", false)
	_clear()
	var source := str(_info.get("source", ""))
	_label("Header", source, 22, Color.GOLD)
	if str(_info.get("kind", "")) == "charge":
		_build_charge(source)
	else:
		_build_shoot(source)
	reset_size()
	if not visible:
		popup_centered()
	print("[CustodesReactiveDialog] shown: %s stage %s" % [source, str(_info.get("stage", ""))])


func _build_charge(source: String) -> void:
	var stage := str(_info.get("stage", ""))
	var unit_name := str(_info.get("unit_name", ""))
	var rule := str(_info.get("target_rule", ""))
	var cap_txt := " If the result is greater than 6, it is changed to 6." if int(_info.get("cap", 0)) > 0 else ""
	if stage == "roll":
		_label("Body", "Player %d: %s declares a charge.%s Charge targets: %s." % [
			int(_info.get("player", 0)), unit_name, cap_txt, rule])
		_button("RollButton", "Roll Charge (2D6)", func(): Reactive.submit({"type": Reactive.ACT_ROLL}))
		return
	var rolls: Array = _info.get("rolls", [])
	var roll_txt := "Charge roll: %d + %d = %d\"" % [int(rolls[0]) if rolls.size() > 0 else 0, int(rolls[1]) if rolls.size() > 1 else 0, int(_info.get("roll", 0))]
	if int(_info.get("uncapped", 0)) != int(_info.get("roll", 0)):
		roll_txt += " (%d, changed to 6)" % int(_info.get("uncapped", 0))
	_label("RollResult", roll_txt, 18, Color(0.6, 1.0, 0.6))
	_label("Body", "Select the charge target(s) for %s — %s. The charge move must end engaged with every target you select (and with no other enemy unit)." % [unit_name, rule])
	var box := VBoxContainer.new()
	box.name = "Targets"
	_content.add_child(box)
	for e in _info.get("selectable_labels", []):
		var cb := CheckBox.new()
		cb.name = "Target_%s" % str(e.unit_id)
		cb.text = "%s (%.1f\")" % [str(e.label), float(e.distance)]
		cb.toggled.connect(func(_on): _sync_declare())
		box.add_child(cb)
	for e in _info.get("near_misses", []):
		var mb := CheckBox.new()
		mb.name = "Miss_%s" % str(e.unit_id)
		mb.text = "%s (%.1f\" — beyond the roll)" % [str(e.label), float(e.distance)]
		mb.disabled = true
		box.add_child(mb)
	var declare := _button("DeclareButton", "Charge the selected target(s)", _on_declare)
	declare.disabled = true
	_button("FailButton", "Charge fails (don't move)", func(): Reactive.submit({"type": Reactive.ACT_FAIL}))


func _selected_targets() -> Array:
	var out: Array = []
	var box = _content.get_node_or_null("Targets")
	if box == null:
		return out
	for c in box.get_children():
		if c is CheckBox and str(c.name).begins_with("Target_") and c.button_pressed:
			out.append(str(c.name).substr(7))
	return out


func _sync_declare() -> void:
	var b = _content.get_node_or_null("DeclareButton")
	if b != null:
		b.disabled = _selected_targets().is_empty()


func _on_declare() -> void:
	var ids := _selected_targets()
	if ids.is_empty():
		return
	Reactive.submit({"type": Reactive.ACT_TARGETS, "payload": {"target_ids": ids}})


func _build_shoot(_source: String) -> void:
	_label("Body", "Player %d: %s shoots %s using normal shooting — it can only target that unit. Choose the weapons (one profile per weapon), then roll the attacks." % [
		int(_info.get("player", 0)), str(_info.get("unit_name", "")), str(_info.get("target_name", ""))])
	var box := VBoxContainer.new()
	box.name = "Weapons"
	_content.add_child(box)
	var i := 0
	for o in _info.get("options", []):
		var row := HBoxContainer.new()
		row.name = "Weapon_%d" % i
		row.set_meta("key", str(o.key))
		var cb := CheckBox.new()
		cb.name = "Use"
		cb.text = str(o.label)
		cb.button_pressed = true
		cb.custom_minimum_size = Vector2(330, 0)
		row.add_child(cb)
		var ob := OptionButton.new()
		ob.name = "Profile"
		for p in o.get("profiles", []):
			ob.add_item(str(p.name))
			ob.set_item_metadata(ob.item_count - 1, str(p.weapon_id))
		ob.disabled = ob.item_count <= 1
		row.add_child(ob)
		box.add_child(row)
		i += 1
	_button("ShootButton", "Roll Attacks", _on_shoot)
	_button("SkipButton", "Don't shoot", func(): Reactive.submit({"type": Reactive.ACT_SHOOT, "payload": {"weapons": []}}))


func _on_shoot() -> void:
	var picks: Array = []
	var box = _content.get_node_or_null("Weapons")
	if box == null:
		return
	for row in box.get_children():
		var cb = row.get_node_or_null("Use")
		var ob = row.get_node_or_null("Profile")
		if cb == null or not cb.button_pressed or ob == null or ob.item_count == 0:
			continue
		var idx: int = maxi(0, ob.selected)
		picks.append({"key": str(row.get_meta("key", "")), "weapon_id": str(ob.get_item_metadata(idx))})
	Reactive.submit({"type": Reactive.ACT_SHOOT, "payload": {"weapons": picks}})


## RAPID REACTIONS: the attacks are resolved — show what happened.
func show_result(summary: Dictionary) -> void:
	set_meta("showing_result", true)
	_clear()
	_label("Header", "RAPID REACTIONS — results", 22, Color.GOLD)
	_label("Result", str(summary.get("summary", "")), 17, Color(0.6, 1.0, 0.6))
	for line in summary.get("lines", []):
		_label("Line", str(line), 14, Color(0.85, 0.85, 0.85))
	_button("DoneButton", "Done", func(): queue_free())
	reset_size()
	if not visible:
		popup_centered()

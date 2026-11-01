extends PanelContainer
class_name LeftRosterStrip

# LeftRosterStrip — vertical card-per-unit strip on the left edge of the
# screen (T37, doc §8).
#
# Each unit gets a child PanelContainer named UnitCard_<unit_id> with a
# Label child (name + wound chip). Click selects the unit and pans the
# camera; double-click opens the datasheet (T39).
#
# Public API for scenarios:
#   active_filter : String  (T38 — "all", "can_act", "engaged", "below_half")
#   visible_unit_ids : Array  (T38 — filtered set)
#   refresh()
#   refresh_exhaustion() / is_card_exhausted(unit_id)  (T09)
#
# T09 (doc §8, exhaustion shading): a card whose unit has acted this phase
# (BasePhase.has_unit_acted_this_phase — moved, shot, charged, fought) swaps
# to a dimmer stylebox and dims like the unit's board tokens, until the phase
# ends. UnitExhaustionTracker calls refresh_exhaustion() after every action
# and phase change; "Can Act" (T38) lists exactly the cards that are not dim.
#
# Self-installs as /root/Main/LeftRoster.

const PANEL_WIDTH := 220.0

# T09: the dimmed card. The modulate matches the board token's
# (TokenVisual.T09_EXHAUSTION_MODULATE); the stylebox is darker than the
# default card panel (Godot's PanelContainer flat box, 0.1 grey at 0.6 alpha).
const T09_CARD_MODULATE_EXHAUSTED := Color(0.6, 0.6, 0.6, 1.0)
const T09_CARD_MODULATE_NORMAL := Color(1.0, 1.0, 1.0, 1.0)
const T09_CARD_BG_EXHAUSTED := Color(0.05, 0.05, 0.05, 0.6)

var active_filter: String = "all"
var visible_unit_ids: Array = []
var _vbox: VBoxContainer = null
var _t09_style_exhausted: StyleBoxFlat = null


func _ready() -> void:
	name = "LeftRoster"
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Hidden by default — HUD_Right already lists every unit, and the
	# left-edge strip was overlapping GameLogPanel. Press B (or hit the
	# toolbar toggle Main wires in _install_design_guidelines_overlays)
	# to bring it in. (Was L, but Main._input consumes L for the LoS
	# overlay before _unhandled_key_input ever runs, so an L binding here
	# can never fire.)
	visible = false
	_sync_viewport_size()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _sync_viewport_size):
		vp.connect("size_changed", _sync_viewport_size)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.name = "Cards"
	_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(_vbox)

	# Build cards on first frame so GameState is populated by SAL load.
	call_deferred("refresh")


func toggle_visible() -> void:
	visible = not visible
	if visible:
		# GameLogPanel is added after LeftRoster in Main._ready, so it
		# sits on top. Raise the roster when shown so its cards aren't
		# hidden behind the log.
		move_to_front()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	# Toggle roster strip (rebindable: toggle_roster_strip, default B)
	if k.pressed and not k.echo and KeybindingManager.matches_action(k, "toggle_roster_strip"):
		toggle_visible()
		get_viewport().set_input_as_handled()


func _sync_viewport_size() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	position = Vector2(0, 80)
	size = Vector2(PANEL_WIDTH, vp_size.y - 200.0)


func set_active_filter(f: String) -> void:
	active_filter = f
	refresh()


func refresh() -> void:
	for c in _vbox.get_children():
		# Detach before freeing: a rebuilt card added while its predecessor
		# still waits for queue_free would be auto-renamed (UnitCard_<id>2...),
		# and UnitCard_<id> would keep resolving to the dead card.
		_vbox.remove_child(c)
		c.queue_free()
	visible_unit_ids = []
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var units: Dictionary = gs.state.get("units", {})
	for uid in units:
		var u = units[uid]
		if typeof(u) != TYPE_DICTIONARY:
			continue
		if not _passes_filter(str(uid), u):
			continue
		visible_unit_ids.append(uid)
		var card := _make_card(uid, u)
		_vbox.add_child(card)


func _passes_filter(unit_id: String, unit: Dictionary) -> bool:
	match active_filter:
		"all":
			return true
		"can_act":
			# The cards that are not dim (T09): same "has acted this phase".
			return not _t09_unit_has_acted(unit_id)
		"engaged":
			return _unit_is_engaged(unit)
		"below_half":
			return _unit_below_half_wounds(unit)
		_:
			return true


func _unit_is_engaged(unit: Dictionary) -> bool:
	# T29-style center-to-center check vs every opposing unit, threshold 1".
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	var threshold_px: float = float(Measurement.PX_PER_INCH) * 1.0
	var threshold_sq: float = threshold_px * threshold_px
	var my_owner: int = int(unit.get("owner", unit.get("owner_player", 0)))
	for other_id in gs.state.get("units", {}):
		var other = gs.state.units[other_id]
		if typeof(other) != TYPE_DICTIONARY:
			continue
		if int(other.get("owner", other.get("owner_player", 0))) == my_owner:
			continue
		for ma in unit.get("models", []):
			var pa := _pos_of(ma)
			if pa == Vector2.INF:
				continue
			for mb in other.get("models", []):
				var pb := _pos_of(mb)
				if pb == Vector2.INF:
					continue
				if pa.distance_squared_to(pb) <= threshold_sq:
					return true
	return false


func _unit_below_half_wounds(unit: Dictionary) -> bool:
	var max_w: float = float(unit.get("meta", {}).get("stats", {}).get("wounds", 1))
	var total_current: float = 0.0
	var total_max: float = 0.0
	for m in unit.get("models", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		total_max += max_w
		total_current += float(m.get("current_wounds", max_w))
	if total_max <= 0.0:
		return false
	return total_current < total_max * 0.5


func _pos_of(m) -> Vector2:
	if typeof(m) != TYPE_DICTIONARY:
		return Vector2.INF
	var pos = m.get("position", null)
	if typeof(pos) == TYPE_VECTOR2:
		return pos
	if typeof(pos) == TYPE_DICTIONARY and pos.has("x") and pos.has("y"):
		return Vector2(float(pos.x), float(pos.y))
	return Vector2.INF


func _make_card(unit_id: String, unit: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "UnitCard_%s" % unit_id
	card.set_meta("unit_id", unit_id)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_gui_input.bind(unit_id))
	var lbl := Label.new()
	lbl.name = "Name"
	var unit_name: String = str(unit.get("meta", {}).get("name", unit_id))
	lbl.text = "%s (%d)" % [unit_name, unit.get("models", []).size()]
	lbl.add_theme_font_size_override("font_size", 16)
	card.add_child(lbl)
	_t09_apply_card_style(card, _t09_unit_has_acted(unit_id))
	return card


# T09: re-apply the dim state to every card (UnitExhaustionTracker calls this
# after each action and phase change). Under the "Can Act" filter the card
# set itself changes, so the strip is rebuilt.
func refresh_exhaustion() -> void:
	if _vbox == null:
		return
	if active_filter == "can_act":
		refresh()
		return
	for card in _vbox.get_children():
		if not card.has_meta("unit_id"):
			continue
		var exhausted := _t09_unit_has_acted(str(card.get_meta("unit_id")))
		if exhausted != bool(card.get_meta("t09_exhausted", false)):
			_t09_apply_card_style(card, exhausted)


# T09: whether unit_id's card currently shows the dimmed (acted) state.
func is_card_exhausted(unit_id: String) -> bool:
	if _vbox == null:
		return false
	var card = _vbox.get_node_or_null("UnitCard_%s" % unit_id)
	return card != null and bool(card.get_meta("t09_exhausted", false))


func _t09_unit_has_acted(unit_id: String) -> bool:
	var pm = get_node_or_null("/root/PhaseManager")
	if pm == null:
		return false
	var phase = pm.get("current_phase_instance")
	if phase == null or not is_instance_valid(phase) or not phase.has_method("has_unit_acted_this_phase"):
		return false
	return bool(phase.has_unit_acted_this_phase(unit_id))


# Exhausted: the darker panel + the token's dim modulate. Not exhausted: the
# card's default look (no override), exactly as T37 draws it.
func _t09_apply_card_style(card: PanelContainer, exhausted: bool) -> void:
	if exhausted:
		if _t09_style_exhausted == null:
			_t09_style_exhausted = StyleBoxFlat.new()
			_t09_style_exhausted.bg_color = T09_CARD_BG_EXHAUSTED
		card.add_theme_stylebox_override("panel", _t09_style_exhausted)
		card.modulate = T09_CARD_MODULATE_EXHAUSTED
	else:
		card.remove_theme_stylebox_override("panel")
		card.modulate = T09_CARD_MODULATE_NORMAL
	card.set_meta("t09_exhausted", exhausted)


func _on_card_gui_input(event: InputEvent, unit_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var m = get_parent()
	if mb.double_click:
		var ds = m.get_node_or_null("DatasheetModal") if m != null else null
		if ds != null:
			ds.open_for(unit_id)
		return
	# Single click: select + pan
	if m != null and m.has_method("fit_view_to_selection"):
		m.fit_view_to_selection(unit_id)


# T37 test seam.
func t37_synthesize_card_click(unit_id: String, double_click: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = double_click
	_on_card_gui_input(ev, unit_id)

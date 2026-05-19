extends PanelContainer

# PhaseBar — top-center HUD showing the six in-game-turn phases (T04).
#
# Pills are children named `PhasePill_<PHASE_NAME>` so assertions can address
# them by NodePath. Each pill modulates by state:
#   - active pill    -> active player's slot color (UIConstants)
#   - completed pill -> dim grey  Color(0.5, 0.5, 0.5, 1.0)
#   - future pill    -> alpha 0.4
#
# Self-installs into Main via a one-line instantiation in Main._ready().

const PHASES := [
	{"id": "COMMAND",  "value": 6},
	{"id": "MOVEMENT", "value": 7},
	{"id": "SHOOTING", "value": 8},
	{"id": "CHARGE",   "value": 9},
	{"id": "FIGHT",    "value": 10},
	{"id": "MORALE",   "value": 12},
]

const COMPLETED_COLOR := Color(0.5, 0.5, 0.5, 1.0)
const FUTURE_ALPHA := 0.4

const TOOLTIP_PAST   := "completed"
const TOOLTIP_FUTURE := "resolve current phase first"
const TOOLTIP_ACTIVE := "current phase"

var _pills_by_phase: Dictionary = {}
var _hbox: HBoxContainer = null

# T26: latest result of clicking a pill. One of "", "past_inert",
# "future_blocked", "active". Scenarios assert against this.
var last_pill_click_result: String = ""


func _ready() -> void:
	name = "PhaseBar"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_top = 8.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH

	_hbox = HBoxContainer.new()
	_hbox.name = "Pills"
	_hbox.add_theme_constant_override("separation", 8)
	add_child(_hbox)

	for entry in PHASES:
		var pill := _make_pill(entry.id)
		_hbox.add_child(pill)
		_pills_by_phase[int(entry.value)] = pill

	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null and pm.has_signal("phase_changed"):
		if not pm.is_connected("phase_changed", _on_phase_changed):
			pm.connect("phase_changed", _on_phase_changed)

	_refresh(_current_phase_value())


func _make_pill(phase_id: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "PhasePill_%s" % phase_id
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(_on_pill_gui_input.bind(phase_id))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	p.add_child(pad)
	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = phase_id.capitalize()
	pad.add_child(lbl)
	return p


func _phase_value_for_id(phase_id: String) -> int:
	for entry in PHASES:
		if entry.id == phase_id:
			return int(entry.value)
	return -1


func _classify_pill(phase_value: int) -> String:
	# Returns "past" | "active" | "future" given the pill's phase value and
	# the current active phase.
	var active := _current_phase_value()
	if active < 0 or phase_value == active:
		return "active"
	if phase_value < active:
		return "past"
	return "future"


func _on_pill_gui_input(event: InputEvent, phase_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var v := _phase_value_for_id(phase_id)
	var cls := _classify_pill(v)
	if cls == "past":
		last_pill_click_result = "past_inert"
	elif cls == "future":
		last_pill_click_result = "future_blocked"
	else:
		last_pill_click_result = "active"
	# NOTE: phase IS NOT changed on click. Past pills are inert; future
	# pills are blocked.


func _current_phase_value() -> int:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return -1
	return int(gs.state.get("meta", {}).get("phase", -1))


func _on_phase_changed(new_phase) -> void:
	_refresh(int(new_phase))


# Paint the bar based on the active phase value (enum int). Pills whose
# enum value is less than active_value are completed; equal is active;
# greater is future.
func _refresh(active_value: int) -> void:
	var active_color: Color = _active_player_color()
	for entry in PHASES:
		var v: int = int(entry.value)
		var pill: PanelContainer = _pills_by_phase.get(v, null)
		if pill == null:
			continue
		if active_value < 0:
			pill.modulate = Color(1, 1, 1, FUTURE_ALPHA)
			pill.tooltip_text = TOOLTIP_FUTURE
		elif v == active_value:
			pill.modulate = active_color
			pill.tooltip_text = TOOLTIP_ACTIVE
		elif v < active_value:
			pill.modulate = COMPLETED_COLOR
			pill.tooltip_text = TOOLTIP_PAST
		else:
			pill.modulate = Color(1, 1, 1, FUTURE_ALPHA)
			pill.tooltip_text = TOOLTIP_FUTURE


func _active_player_color() -> Color:
	var uic = get_node_or_null("/root/UIConstants")
	if uic == null:
		return Color(1, 1, 1, 1)
	var gs = get_node_or_null("/root/GameState")
	var active_player: int = 1
	if gs != null:
		active_player = int(gs.state.get("meta", {}).get("active_player", 1))
	return uic.FRIENDLY_PLAYER_TEAL if active_player == 1 else uic.ENEMY_PLAYER_MAGENTA

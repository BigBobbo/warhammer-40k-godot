extends HBoxContainer

# PhaseBar — the six-pill battle-phase tracker (T04, design guidelines doc §4:
# "Active pill glows in player color; completed pills dim; future pills
# disabled").
#
# One pill per battle phase, in turn order: Command → Movement → Shooting →
# Charge → Fight → Score. Score is the game's real sixth phase
# (GameStateData.Phase.SCORING). MORALE is a deprecated enum slot that
# PhaseManager.transition_to_phase remaps to COMMAND (ISS-034: battle-shock is
# part of the Command phase), so it gets no pill.
#
# Each pill is a PanelContainer named exactly "PhasePill_<PHASE>", where
# <PHASE> is the GameStateData.Phase key (PhasePill_COMMAND ... PhasePill_SCORING),
# so scenarios and tests can read it by path. A pill's state is carried on its
# `modulate`, which is what the player sees and what tests assert:
#   active    -> the active player's UIConstants slot colour
#                (UIConstants.player_slot_color: P1 TEAL, P2 MAGENTA)
#   completed -> COMPLETED_MODULATE == Color(0.5, 0.5, 0.5, 1.0)
#   future    -> FUTURE_MODULATE, alpha 0.4 ("disabled")
# Modulate multiplies the pill's own colours, so each state also gets its own
# pill style: the active pill is a solid chip with a glow, a completed pill is
# a solid grey chip, a future pill is a hollow outline. Completed and future
# pills therefore differ in shape as well as brightness. Every state keeps the
# same pill size, so the row never shifts when the phase advances.
#
# Placement: Main._setup_phase_strip() hosts the bar inside the bottom
# PhaseStrip (between the game log and the right-hand panel; that placement is
# pinned by tests/scenarios/visual/T_phase_strip_bottom.json), so a pill's path
# is /root/Main/PhaseStrip/PhaseBar/PhasePill_<PHASE>. The bar listens on
# PhaseManager.phase_changed itself; Main only decides whether the strip shows.

const WhiteDwarfThemeScript = preload("res://scripts/WhiteDwarfTheme.gd")
const UIConstantsScript = preload("res://autoloads/UIConstants.gd")
const PILL_FONT = preload("res://fonts/Rajdhani-Bold.ttf")

const PILL_PREFIX := "PhasePill_"

# Battle phases in turn order, and the word each pill shows.
const PHASE_ORDER := [
	GameStateData.Phase.COMMAND,
	GameStateData.Phase.MOVEMENT,
	GameStateData.Phase.SHOOTING,
	GameStateData.Phase.CHARGE,
	GameStateData.Phase.FIGHT,
	GameStateData.Phase.SCORING,
]
const PHASE_LABELS := {
	GameStateData.Phase.COMMAND: "Command",
	GameStateData.Phase.MOVEMENT: "Movement",
	GameStateData.Phase.SHOOTING: "Shooting",
	GameStateData.Phase.CHARGE: "Charge",
	GameStateData.Phase.FIGHT: "Fight",
	GameStateData.Phase.SCORING: "Score",
}

const STATE_ACTIVE := "active"
const STATE_COMPLETED := "completed"
const STATE_FUTURE := "future"

# Pill modulates (T04 contract). The active modulate is the player slot colour.
const COMPLETED_MODULATE := Color(0.5, 0.5, 0.5, 1.0)
const FUTURE_MODULATE := Color(1.0, 1.0, 1.0, 0.4)

# Pill colours BEFORE modulate (modulate multiplies them):
# - solid chips (active, completed) carry dark ink: white fill x slot colour =
#   the slot colour; 0.8 grey fill x 0.5 = a 0.4 grey chip. That is CIE
#   lightness L* 43, under both slot colours (TEAL 66, MAGENTA 54, and the
#   magenta's saturation reads brighter still), so the active pill stays the
#   brightest for either player while dark ink still reads at ~3.6:1.
# - a future pill is parchment ink and outline at 40% over the strip.
const ACTIVE_FILL := Color(1.0, 1.0, 1.0, 1.0)
const ACTIVE_GLOW := Color(1.0, 1.0, 1.0, 0.45)
const COMPLETED_FILL := Color(0.8, 0.8, 0.8, 1.0)
const CHIP_INK := Color(0.06, 0.05, 0.04, 1.0)
const FUTURE_INK := WhiteDwarfThemeScript.WH_PARCHMENT
const ARROW_COLOR := Color(WhiteDwarfThemeScript.WH_GOLD, 0.35)

# Geometry. At 16 px Rajdhani Bold a line is 21 px tall, which is the pill row
# Main's 30 px strip leaves above the PlayerTurnBorder.
const FONT_SIZE := 16
const PILL_PADDING_X := 12
const PILL_RADIUS := 10
const GLOW_SIZE := 4
const PILL_SEPARATION := 6

## The phase whose pill is lit (-1 before the first refresh, or outside the
## battle phases, when every pill shows as future).
var active_phase: int = -1
## The player whose slot colour lights the active pill.
var active_player: int = 1

var _pills: Dictionary = {}   # phase (int) -> PanelContainer
var _labels: Dictionary = {}  # phase (int) -> Label
var _styles: Dictionary = {}  # phase (int) -> StyleBoxFlat (one per pill)
var _states: Dictionary = {}  # phase (int) -> STATE_*


func _init() -> void:
	# Named before it enters the tree, so the pill paths are stable from the
	# moment Main adds the bar.
	name = "PhaseBar"
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never block board clicks
	add_theme_constant_override("separation", PILL_SEPARATION)
	_build_pills()


func _enter_tree() -> void:
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null and pm.has_signal("phase_changed") and not pm.phase_changed.is_connected(_on_phase_changed):
		pm.phase_changed.connect(_on_phase_changed)
	refresh()


func _exit_tree() -> void:
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null and pm.has_signal("phase_changed") and pm.phase_changed.is_connected(_on_phase_changed):
		pm.phase_changed.disconnect(_on_phase_changed)


## "PhasePill_<PHASE>" for a GameStateData.Phase value, e.g. PhasePill_COMMAND.
static func pill_name(phase: int) -> String:
	return PILL_PREFIX + String(GameStateData.Phase.keys()[phase])


func get_pill(phase: int) -> PanelContainer:
	return _pills.get(phase, null)


## STATE_ACTIVE / STATE_COMPLETED / STATE_FUTURE for a battle phase ("" for a
## phase that has no pill).
func pill_state(phase: int) -> String:
	return String(_states.get(phase, ""))


## The colour currently lighting the active pill: the active player's slot.
func active_color() -> Color:
	return _slot_color(active_player)


## Re-derive every pill from GameState. `phase` overrides the current phase:
## phase_changed passes its own argument, so the bar never lags the signal.
func refresh(phase: int = -1) -> void:
	var gs = get_node_or_null("/root/GameState") if is_inside_tree() else null
	if phase < 0 and gs != null:
		phase = int(gs.get_current_phase())
	var player: int = int(gs.get_active_player()) if gs != null else active_player
	apply_state(phase, player)


## Light the pills for `phase` with `player`'s slot colour. Pills before the
## active one are completed, pills after it are future. A phase outside the
## battle round (deployment, game over) lights nothing.
func apply_state(phase: int, player: int) -> void:
	active_phase = phase if PHASE_ORDER.has(phase) else -1
	active_player = player
	var active_idx: int = PHASE_ORDER.find(phase)
	var summary: Array = []
	for i in range(PHASE_ORDER.size()):
		var p: int = PHASE_ORDER[i]
		var state := STATE_FUTURE
		if active_idx >= 0 and i < active_idx:
			state = STATE_COMPLETED
		elif i == active_idx:
			state = STATE_ACTIVE
		_apply_pill_state(p, state)
		summary.append("%s=%s" % [String(GameStateData.Phase.keys()[p]), state])
	var phase_key: String = String(GameStateData.Phase.keys()[phase]) if phase >= 0 and phase < GameStateData.Phase.size() else str(phase)
	print("PhaseBar: phase=%s player=%d -> %s" % [phase_key, player, ", ".join(summary)])


func _on_phase_changed(new_phase) -> void:
	refresh(int(new_phase))


func _slot_color(player: int) -> Color:
	var uic = get_node_or_null("/root/UIConstants") if is_inside_tree() else null
	if uic != null and uic.has_method("player_slot_color"):
		return uic.player_slot_color(player)
	# No live autoload (a bare instance outside the tree): same slots, read
	# from the UIConstants script itself.
	return UIConstantsScript.FRIENDLY_PLAYER_TEAL if player == 1 else UIConstantsScript.ENEMY_PLAYER_MAGENTA


func _build_pills() -> void:
	# Every pill is as wide as the widest word, so pills line up evenly and a
	# state change can never resize one.
	var text_w := 0.0
	for p in PHASE_ORDER:
		text_w = maxf(text_w, PILL_FONT.get_string_size(PHASE_LABELS[p], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	text_w = ceilf(text_w)

	for i in range(PHASE_ORDER.size()):
		var p: int = PHASE_ORDER[i]
		if i > 0:
			var arrow := Label.new()
			arrow.name = "PhaseArrow_%d" % i
			arrow.text = "▸"
			arrow.add_theme_font_size_override("font_size", 14)
			arrow.add_theme_color_override("font_color", ARROW_COLOR)
			arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(arrow)

		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(PILL_RADIUS)
		style.content_margin_left = PILL_PADDING_X
		style.content_margin_right = PILL_PADDING_X
		style.content_margin_top = 0
		style.content_margin_bottom = 0

		var pill := PanelContainer.new()
		pill.name = pill_name(p)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pill.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.name = "Label"
		label.text = PHASE_LABELS[p]
		label.add_theme_font_override("font", PILL_FONT)
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(text_w, 0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(label)

		add_child(pill)
		_pills[p] = pill
		_labels[p] = label
		_styles[p] = style
		_apply_pill_state(p, STATE_FUTURE)


func _apply_pill_state(phase: int, state: String) -> void:
	var pill: PanelContainer = _pills[phase]
	var style: StyleBoxFlat = _styles[phase]
	var label: Label = _labels[phase]
	_states[phase] = state
	pill.set_meta("phase_state", state)
	match state:
		STATE_ACTIVE:
			pill.modulate = _slot_color(active_player)
			style.bg_color = ACTIVE_FILL
			style.set_border_width_all(0)
			style.shadow_color = ACTIVE_GLOW
			style.shadow_size = GLOW_SIZE
			label.add_theme_color_override("font_color", CHIP_INK)
		STATE_COMPLETED:
			pill.modulate = COMPLETED_MODULATE
			style.bg_color = COMPLETED_FILL
			style.set_border_width_all(0)
			style.shadow_size = 0
			label.add_theme_color_override("font_color", CHIP_INK)
		_:
			pill.modulate = FUTURE_MODULATE
			style.bg_color = Color(0, 0, 0, 0)
			style.border_color = FUTURE_INK
			style.set_border_width_all(1)
			style.shadow_size = 0
			label.add_theme_color_override("font_color", FUTURE_INK)

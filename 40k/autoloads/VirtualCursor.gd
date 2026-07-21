extends CanvasLayer

# M1 virtual cursor (PRPs/steam_deck_controller_support.md §5.1, milestone M1):
# the whole-game controller fallback. The left stick drives the REAL pointer —
# each frame the cursor position is applied with Input.warp_mouse() AND a
# synthetic InputEventMouseMotion is parsed, so every existing click / drag /
# hover path works unchanged, including handlers that hit-test the live OS
# pointer (§3.3 of the PRP; this is the production-proven recipe of the MCP
# select_unit handler). A/X synthesize left/right mouse buttons at the cursor.
#
# Mode discipline (avoids double-activation with focus navigation):
#   - stick deflection    -> CURSOR mode: A/X are consumed here as mouse
#                            clicks, so a focused button elsewhere can NOT
#                            also fire via ui_accept
#   - any D-pad press     -> FOCUS mode: cursor parks, A/B act as
#                            ui_accept/ui_cancel on the focused control
#   - a dialog popping up -> FOCUS mode (InputDeviceManager parks us after
#                            it focuses the dialog's confirm button)
#   - mouse/keyboard used -> cursor layer disabled entirely (KBM mode)
#
# Every warp/synthetic event is announced via
# InputDeviceManager.note_synthetic_mouse() so the device tracker does not
# mistake our own output (or the OS echo of warp_mouse) for real mouse use.

signal cursor_mode_changed(active: bool)

const BASE_SPEED := 1500.0  # px/s at full stick deflection (before response curve)
const CARRY_SPEED := 800.0  # px/s while carrying a model — precision over travel
const GLIDE_SPEED := 2200.0  # px/s for test-seam glides (deterministic)
const ARRIVE_EPSILON := 2.0

# P0 fine-control: R3 (pad_precision) held scales the cursor step down for
# pixel-work; magnetism eases the cursor toward the nearest selectable token
# when the player is fine-tuning near it (the continuous-board answer to the
# tile snapping grid tactics get for free).
const PRECISION_FACTOR := 0.32  # cursor speed multiplier while R3 is held
const SNAP_RADIUS := 34.0       # px: magnetism engages only within this of a token
const SNAP_EASE := 0.22         # eased fraction of the gap toward a token per frame

var _pos := Vector2.ZERO
var _cursor_active := false
var _initialized_pos := false
var _lmb_down := false
var _rmb_down := false
var _glide_target = null  # Vector2 while a test glide is in flight

var _ring: Node2D


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ring = CursorRing.new()
	_ring.visible = false
	add_child(_ring)
	InputDeviceManager.device_changed.connect(_on_device_changed)


func is_cursor_active() -> bool:
	return _cursor_active


# FOCUS-mode handoff: release any held synthetic buttons and hide the ring.
# Called on D-pad presses, dialog popups and KBM takeover.
func park() -> void:
	if _lmb_down:
		_emit_button(MOUSE_BUTTON_LEFT, false)
	if _rmb_down:
		_emit_button(MOUSE_BUTTON_RIGHT, false)
	_set_cursor_active(false)


# ============================================================================
# Per-frame movement (stick + glide share _move_cursor -> warp + motion synth)
# ============================================================================

func _process(delta: float) -> void:
	if not InputDeviceManager.is_pad_active():
		return

	if _glide_target != null:
		_set_cursor_active(true)
		var to_target: Vector2 = (_glide_target as Vector2) - _pos
		if to_target.length() <= ARRIVE_EPSILON:
			_move_cursor(to_target)  # final snap
			_glide_target = null
		else:
			var step = min(GLIDE_SPEED * delta, to_target.length())
			_move_cursor(to_target.normalized() * step)
		return

	if not InputMap.has_action("pad_cursor_left"):
		return
	var vec := Input.get_vector("pad_cursor_left", "pad_cursor_right", "pad_cursor_up", "pad_cursor_down")
	if vec != Vector2.ZERO:
		_set_cursor_active(true)
		# Precision modifier (R3 held): scale the whole step down for fine
		# placement / target picking (P0; Gears Tactics "Precision Mode").
		var precision := PRECISION_FACTOR if _precision_held() else 1.0
		# P1 controller option: cursor sensitivity (Settings › Controls).
		var sens: float = SettingsService.pad_cursor_sensitivity if SettingsService != null else 1.0
		if PadRouter.is_carrying():
			# Carrying a model: linear response with a lower ceiling — inch
			# budgets are small and precision beats travel speed.
			_move_cursor(vec * CARRY_SPEED * delta * precision * sens)
		else:
			# Quadratic response: gentle deflection = precision, full = speed.
			var rel := vec.normalized() * BASE_SPEED * vec.length() * vec.length() * delta * precision * sens
			# Magnetism (P0): ease toward the nearest selectable token while
			# fine-tuning near it so grabbing a unit doesn't need pixel-hunting.
			rel += _snap_assist(vec.length())
			_move_cursor(rel)


func _precision_held() -> bool:
	return InputMap.has_action("pad_precision") and Input.is_action_pressed("pad_precision")


# Magnetism (P0): a gentle pull toward the nearest selectable token when the
# player is fine-tuning near it — the continuous-board answer to the tile
# snapping grid tactics (Advance Wars, Into the Breach) get for free. Scene-
# agnostic: duck-typed against a battle scene that opts in via
# nearest_pad_snap_screen_pos(); menus (no such method) and model carry get no
# pull. The pull scales with (1 - deflection) AND fades to zero at the snap
# radius, so it never yanks on entry and can never drag the cursor off an
# intended empty-board click during fast travel.
func _snap_assist(deflection: float) -> Vector2:
	if PadRouter.is_carrying():
		return Vector2.ZERO
	# P1 controller option: players can turn magnetism off (Settings › Controls).
	if SettingsService != null and not SettingsService.pad_cursor_magnetism:
		return Vector2.ZERO
	var assist := clampf(1.0 - deflection, 0.0, 1.0)
	if assist <= 0.0:
		return Vector2.ZERO
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("nearest_pad_snap_screen_pos"):
		return Vector2.ZERO
	var target = scene.nearest_pad_snap_screen_pos(_pos, SNAP_RADIUS)
	if not (target is Vector2) or (target as Vector2) == Vector2.INF:
		return Vector2.ZERO
	var to_target: Vector2 = (target as Vector2) - _pos
	var dist := to_target.length()
	if dist < 1.0 or dist >= SNAP_RADIUS:
		return Vector2.ZERO
	var closeness := 1.0 - dist / SNAP_RADIUS  # 0 at the edge (smooth entry) → ~1 near centre
	return to_target * SNAP_EASE * assist * closeness


func _move_cursor(rel: Vector2) -> void:
	if not _initialized_pos:
		_pos = get_viewport().get_visible_rect().size / 2.0
		_initialized_pos = true
	var unclamped := _pos + rel
	_pos = unclamped.clamp(Vector2.ZERO, get_viewport().get_visible_rect().size)
	# Edge push: driving the cursor against the screen edge pans the camera
	# (standard RTS behaviour) so off-screen targets are reachable with the
	# stick alone.
	var overshoot := unclamped - _pos
	if overshoot != Vector2.ZERO:
		_edge_pan(overshoot.limit_length(30.0))
	InputDeviceManager.note_synthetic_mouse()
	# _pos (like the ring) lives in viewport / base-resolution "canvas" space — the
	# same space the camera renders the board into and that MovementController's
	# board_root.transform.affine_inverse() expects. Two separate coordinate hops
	# both need the viewport's screen transform, which at content scale != 1 (the
	# Steam Deck renders the 1920x1080 base onto a 1280x800 panel; the UI Scale
	# slider also drives content_scale_factor) is a pure scale:
	#   1. Input.warp_mouse() takes WINDOW pixels, so the OS pointer must go to
	#      st * _pos or it lands at the wrong physical spot.
	#   2. Input.parse_input_event() feeds the event through Godot's screen->canvas
	#      (stretch) transform — it applies st.affine_inverse() BEFORE _input /
	#      _unhandled_input see the event. So a raw event.position = _pos arrives
	#      at handlers as _pos / content_scale (the pickup hit-test then misses the
	#      model by that factor — the "A picks up but the model won't move" bug).
	#      Emit st * _pos so the delivered position resolves back to _pos, matching
	#      what a real mouse over the same pixel would deliver.
	# At content scale 1.0 (desktop / CI) st is the identity, so both are no-ops.
	var st := get_viewport().get_screen_transform()
	Input.warp_mouse(st * _pos)
	var motion := InputEventMouseMotion.new()
	motion.position = st * _pos
	motion.global_position = st * _pos
	motion.relative = st.basis_xform(rel)
	motion.button_mask = _current_button_mask()
	Input.parse_input_event(motion)
	_ring.position = _pos


func get_cursor_pos() -> Vector2:
	return _pos


# M3 carry seams (PadRouter): jump the pointer somewhere (activating cursor
# mode) and press/release the synthetic left button — both routed through the
# same warp+event pipeline as stick movement, so drag handlers can't tell the
# difference from a mouse.
func warp_to(screen_pos: Vector2) -> void:
	if not _initialized_pos:
		_pos = get_viewport().get_visible_rect().size / 2.0
		_initialized_pos = true
	_set_cursor_active(true)
	_move_cursor(screen_pos - _pos)


func set_left_button(pressed: bool) -> void:
	_emit_button(MOUSE_BUTTON_LEFT, pressed)


func _edge_pan(push: Vector2) -> void:
	# Duck-typed against the battle scene's camera model (view_offset in
	# screen px + update_view_transform, same as Main._process pan) so the
	# cursor layer stays scene-agnostic; menus simply have no camera.
	var scene := get_tree().current_scene
	if scene == null or not ("view_offset" in scene) or not scene.has_method("update_view_transform"):
		return
	var rot: float = scene.view_rotation if "view_rotation" in scene else 0.0
	scene.view_offset += push.rotated(-rot)
	scene.update_view_transform()


# ============================================================================
# Buttons: A/X -> left/right mouse at the cursor (CURSOR mode only)
# ============================================================================

func _input(event: InputEvent) -> void:
	if not InputDeviceManager.is_pad_active():
		return
	if event is InputEventJoypadButton:
		# D-pad hands control to focus navigation; do NOT consume — the same
		# press should also move focus so the transition costs nothing.
		# EXCEPT mid-carry: the carried model rides the cursor on a held
		# synthetic LMB, and park() releases that button — a D-pad press would
		# silently drop the model where it stands and desync PadRouter's carry
		# state (its A-drop/B-cancel/X-undo all misroute against a stale
		# carry_active). While a carry is live the router owns the cursor;
		# it makes the D-pad inert instead.
		if _cursor_active and event.pressed and event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			if PadRouter.is_carrying():
				return
			park()
			return
		if not _cursor_active:
			return
		match event.button_index:
			JOY_BUTTON_A:
				# During an M3 carry the router owns A (drop/cancel semantics);
				# a second synthetic LMB press mid-drag would confuse the drag
				# handlers.
				if PadRouter.is_carrying():
					return
				_emit_button(MOUSE_BUTTON_LEFT, event.pressed)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_X:
				# Mid-carry the router owns X too (Movement "Finish Model" —
				# drop + advance to the next un-placed model). A synthetic RMB
				# under a held model was never useful anyway: rotation is on
				# LB/RB, and a same-spot RMB tap rotates nothing.
				if PadRouter.is_carrying():
					return
				_emit_button(MOUSE_BUTTON_RIGHT, event.pressed)
				get_viewport().set_input_as_handled()


func _emit_button(button: MouseButton, pressed: bool) -> void:
	InputDeviceManager.note_synthetic_mouse()
	var ev := InputEventMouseButton.new()
	# See _move_cursor: emit in screen space so Godot's screen->canvas delivery
	# transform resolves the handler-visible position back to _pos. Emitting raw
	# _pos here is what made the synthetic pickup click land at _pos / content_scale
	# and miss the model at content scale != 1.
	var st := get_viewport().get_screen_transform()
	ev.position = st * _pos
	ev.global_position = st * _pos
	ev.button_index = button
	ev.pressed = pressed
	if button == MOUSE_BUTTON_LEFT:
		_lmb_down = pressed
	elif button == MOUSE_BUTTON_RIGHT:
		_rmb_down = pressed
	ev.button_mask = _current_button_mask()
	Input.parse_input_event(ev)


func _current_button_mask() -> int:
	var mask := 0
	if _lmb_down:
		mask |= MOUSE_BUTTON_MASK_LEFT
	if _rmb_down:
		mask |= MOUSE_BUTTON_MASK_RIGHT
	return mask


func _set_cursor_active(active: bool) -> void:
	if active == _cursor_active:
		return
	_cursor_active = active
	_ring.visible = active
	if active:
		_ring.position = _pos
	cursor_mode_changed.emit(active)


func _on_device_changed(mode: int) -> void:
	if mode != InputDeviceManager.InputMode.PAD:
		park()


# ============================================================================
# Test seam (windowed scenarios / MCP): deterministic glide through the SAME
# _move_cursor pipeline the stick uses — only the steering is synthetic.
# ============================================================================

func glide_to_screen(target: Vector2, timeout_s: float = 6.0) -> bool:
	# The glide is pad-layer input by definition; claim the mode so a scenario
	# whose very first act is a glide isn't gated out of _process.
	InputDeviceManager.claim_pad()
	_glide_target = target
	var elapsed := 0.0
	while _glide_target != null and elapsed < timeout_s:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	var arrived := _glide_target == null
	_glide_target = null
	return arrived


# Small ring drawn at the cursor so the pointer is findable on a TV/Deck
# screen even when the OS arrow is subtle. Colors from the UIConstants slot
# table (design guidelines §9).
class CursorRing:
	extends Node2D

	func _init() -> void:
		z_index = 4096

	func _draw() -> void:
		var c: Color = UIConstants.NEUTRAL_UI_PALE_WHITE
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, Color(c, 0.9), 2.0, true)
		draw_circle(Vector2.ZERO, 2.0, Color(c, 0.9))

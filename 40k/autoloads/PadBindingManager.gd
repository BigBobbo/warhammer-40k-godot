extends Node

# Controller layout manager ("PadBindings" autoload): the pad counterpart of
# KeybindingManager. The game's controller code (PadRouter, VirtualCursor, the
# fight dialogs) is written against the DEFAULT Deck/Xbox layout — A selects,
# B cancels, X skips, Y datasheet, bumpers cycle, Start ends the phase, View
# pauses, L3 hops models, R3 is the precision-cursor hold. This manager lets
# the player move those ROLES onto different physical buttons:
#
#   * Each role has a default button (the canonical layout above). Rebinding a
#     role to a button another role owns SWAPS the two roles — every role always
#     stays reachable on some button, which matters on a controller far more
#     than on a keyboard (there is no "just press a different key").
#   * Consumers translate incoming presses with canonical(button_index): the
#     physical button pressed is mapped back to the DEFAULT button of the role
#     it now carries, so every existing `match event.button_index:` keeps
#     working verbatim against the canonical constants.
#   * The InputMap halves of the scheme (ui_accept/ui_cancel focus presses,
#     pad_phase_action, pad_menu_action, pad_precision) are re-pointed in place
#     whenever a role moves, mirroring InputDeviceManager.apply_stick_swap.
#   * GlyphDB.glyph_text consults display_glyph() so the hint bar, tutorial
#     prompts and every glyph chip in the game show the button the role is
#     ACTUALLY on right now — a rebound layout is reflected everywhere at once.
#
# The D-pad, sticks, triggers and Steam Deck paddles are deliberately NOT
# rebindable: the D-pad drives Godot's native ui_* focus navigation, the
# sticks/triggers are axes with their own Settings options (swap sticks,
# sensitivity), and the paddles only exist when Steam Input forwards them.
#
# Save/load to user://pad_bindings.cfg using ConfigFile (same pattern as
# KeybindingManager / SettingsService).

signal pad_binding_changed(role_id: String)

const SAVE_PATH = "user://pad_bindings.cfg"

# Ordered for the Settings › Controller UI.
const ROLE_ORDER: Array[String] = [
	"pad_select",
	"pad_back",
	"pad_context",
	"pad_datasheet",
	"pad_prev_unit",
	"pad_next_unit",
	"pad_end_phase",
	"pad_pause",
	"pad_model_hop",
	"pad_precision_mode",
]

# Canonical hint-glyph id (as used in PadRouter.HINTS_* / GlyphDB) -> role.
const GLYPH_TO_ROLE := {
	"a": "pad_select",
	"b": "pad_back",
	"x": "pad_context",
	"y": "pad_datasheet",
	"lb": "pad_prev_unit",
	"rb": "pad_next_unit",
	"menu": "pad_end_phase",
	"view": "pad_pause",
	"l3": "pad_model_hop",
	"r3": "pad_precision_mode",
}

# Physical button -> short glyph label (Deck/Xbox naming, matching GlyphDB).
const BUTTON_LABELS := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "☰",
	JOY_BUTTON_BACK: "⧉",
	JOY_BUTTON_PADDLE1: "R4",
	JOY_BUTTON_PADDLE2: "L4",
	JOY_BUTTON_PADDLE3: "R5",
	JOY_BUTTON_PADDLE4: "L5",
	JOY_BUTTON_MISC1: "MISC",
	JOY_BUTTON_TOUCHPAD: "TOUCH",
}

# Longer names for the Settings rows / capture feedback.
const BUTTON_FULL_NAMES := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB (Left Bumper)",
	JOY_BUTTON_RIGHT_SHOULDER: "RB (Right Bumper)",
	JOY_BUTTON_LEFT_STICK: "L3 (Left Stick Click)",
	JOY_BUTTON_RIGHT_STICK: "R3 (Right Stick Click)",
	JOY_BUTTON_START: "☰ Menu (Start)",
	JOY_BUTTON_BACK: "⧉ View (Select)",
	JOY_BUTTON_PADDLE1: "R4 (Back Paddle)",
	JOY_BUTTON_PADDLE2: "L4 (Back Paddle)",
	JOY_BUTTON_PADDLE3: "R5 (Back Paddle)",
	JOY_BUTTON_PADDLE4: "L5 (Back Paddle)",
	JOY_BUTTON_MISC1: "Misc",
	JOY_BUTTON_TOUCHPAD: "Touchpad Click",
}

# The D-pad drives native focus navigation everywhere (menus, dialogs, panels)
# and Guide belongs to Steam — never capturable as a role button.
const RESERVED_BUTTONS := [
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_GUIDE,
]

# role_id -> { display_name, default_button, button }
var roles: Dictionary = {}

# physical button -> canonical (default) button of the role it carries.
# Defaults that lost their role map to JOY_BUTTON_INVALID (dead button).
var _canonical_map: Dictionary = {}


func _ready() -> void:
	_register_defaults()
	load_bindings()
	_rebuild_canonical_map()
	_apply_input_map()
	print("[PadBindings] Ready — %d controller roles registered" % roles.size())


func _register_defaults() -> void:
	_register("pad_select", "Select / Confirm / Place", JOY_BUTTON_A)
	_register("pad_back", "Back / Cancel / Undo Model", JOY_BUTTON_B)
	_register("pad_context", "Skip / Finish Model", JOY_BUTTON_X)
	_register("pad_datasheet", "Show Datasheet", JOY_BUTTON_Y)
	_register("pad_prev_unit", "Previous Unit / Rotate ⟲", JOY_BUTTON_LEFT_SHOULDER)
	_register("pad_next_unit", "Next Unit / Rotate ⟳", JOY_BUTTON_RIGHT_SHOULDER)
	_register("pad_end_phase", "End Phase / Confirm", JOY_BUTTON_START)
	_register("pad_pause", "Pause Menu", JOY_BUTTON_BACK)
	_register("pad_model_hop", "Next Model (stick click)", JOY_BUTTON_LEFT_STICK)
	_register("pad_precision_mode", "Precision Cursor (hold)", JOY_BUTTON_RIGHT_STICK)


func _register(role_id: String, display_name: String, default_button: int) -> void:
	roles[role_id] = {
		"display_name": display_name,
		"default_button": default_button,
		"button": default_button,
	}


# ============================================================================
# Query API
# ============================================================================

func get_role_ids() -> Array:
	return ROLE_ORDER.duplicate()


func get_role(role_id: String) -> Dictionary:
	return roles.get(role_id, {})


## The physical button currently assigned to a role.
func get_button(role_id: String) -> int:
	if not roles.has(role_id):
		return JOY_BUTTON_INVALID
	return roles[role_id].button


func is_modified(role_id: String) -> bool:
	if not roles.has(role_id):
		return false
	return roles[role_id].button != roles[role_id].default_button


func any_modified() -> bool:
	for role_id in roles:
		if is_modified(role_id):
			return true
	return false


func is_button_assignable(button: int) -> bool:
	return button >= 0 and button < JOY_BUTTON_MAX and not (button in RESERVED_BUTTONS)


## Translate a physical button press to the CANONICAL button whose role it now
## carries. Identity for buttons outside the role table (D-pad, paddles, …);
## JOY_BUTTON_INVALID for a default button whose role has moved elsewhere (so
## the vacated button goes dead instead of double-firing the old behavior).
func canonical(button: int) -> int:
	return _canonical_map.get(button, button)


## Short glyph label ("A", "RB", "☰", …) of the button a role currently sits on.
func button_label_for_role(role_id: String) -> String:
	return button_label(get_button(role_id))


func button_label(button: int) -> String:
	if BUTTON_LABELS.has(button):
		return BUTTON_LABELS[button]
	if button == JOY_BUTTON_INVALID:
		return "—"
	return "BTN%d" % button


func button_full_name(button: int) -> String:
	if BUTTON_FULL_NAMES.has(button):
		return BUTTON_FULL_NAMES[button]
	if button == JOY_BUTTON_INVALID:
		return "Unbound"
	return "Button %d" % button


## Called by GlyphDB.glyph_text: canonical hint-glyph id -> the label of the
## button its role is CURRENTLY on ("" when the id is not a role glyph, e.g.
## "dpad" / "ls" / "lt/rt" — the caller falls back to its static table).
func display_glyph(glyph_id: String) -> String:
	if not GLYPH_TO_ROLE.has(glyph_id):
		return ""
	return button_label_for_role(GLYPH_TO_ROLE[glyph_id])


# ============================================================================
# Rebinding
# ============================================================================

## Assign a role to a physical button. If another role already owns that
## button the two roles SWAP buttons, so the layout always stays complete.
## Returns the role that was swapped with (or "" when no swap happened / the
## assignment was rejected — check the return of is_button_assignable first
## for player-facing feedback).
func set_button(role_id: String, button: int) -> String:
	if not roles.has(role_id) or not is_button_assignable(button):
		return ""
	var old_button: int = roles[role_id].button
	if old_button == button:
		return ""
	var swapped_role := ""
	for other_id in roles:
		if other_id != role_id and roles[other_id].button == button:
			swapped_role = other_id
			roles[other_id].button = old_button
			break
	roles[role_id].button = button
	_rebuild_canonical_map()
	_apply_input_map()
	save_bindings()
	pad_binding_changed.emit(role_id)
	if swapped_role != "":
		pad_binding_changed.emit(swapped_role)
	print("[PadBindings] '%s' -> %s%s" % [role_id, button_label(button),
		("  (swapped with '%s')" % swapped_role) if swapped_role != "" else ""])
	return swapped_role


func reset_role(role_id: String) -> void:
	if not roles.has(role_id):
		return
	set_button(role_id, roles[role_id].default_button)


func reset_all() -> void:
	for role_id in roles:
		roles[role_id].button = roles[role_id].default_button
	_rebuild_canonical_map()
	_apply_input_map()
	save_bindings()
	for role_id in roles:
		pad_binding_changed.emit(role_id)
	print("[PadBindings] All controller roles reset to defaults")


func _rebuild_canonical_map() -> void:
	_canonical_map.clear()
	var owned: Dictionary = {}
	for role_id in roles:
		var r: Dictionary = roles[role_id]
		_canonical_map[r.button] = r.default_button
		owned[r.button] = true
	# A role default vacated for an out-of-table button (e.g. a paddle) must go
	# dead — identity would re-fire the role's behavior from its OLD button.
	for role_id in roles:
		var d: int = roles[role_id].default_button
		if not owned.has(d):
			_canonical_map[d] = JOY_BUTTON_INVALID


# ============================================================================
# InputMap re-pointing — the action-based half of the pad scheme.
# InputDeviceManager registers these actions at startup (autoload order puts
# it before this manager); here their joypad events follow the roles.
# ============================================================================

func _apply_input_map() -> void:
	_repoint_action("ui_accept", get_button("pad_select"))
	_repoint_action("ui_cancel", get_button("pad_back"))
	_repoint_action("pad_phase_action", get_button("pad_end_phase"))
	_repoint_action("pad_menu_action", get_button("pad_pause"))
	_repoint_action("pad_precision", get_button("pad_precision_mode"))


func _repoint_action(action: String, button: int) -> void:
	if not InputMap.has_action(action) or button == JOY_BUTTON_INVALID:
		return
	# Strip only the joypad-button events (keyboard events on ui_accept/ui_cancel
	# must survive), then bind the role's current button.
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			InputMap.action_erase_event(action, ev)
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = button as JoyButton
	InputMap.action_add_event(action, e)


# ============================================================================
# Persistence
# ============================================================================

func save_bindings() -> void:
	var cfg = ConfigFile.new()
	for role_id in roles:
		cfg.set_value(role_id, "button", roles[role_id].button)
	var err = cfg.save(SAVE_PATH)
	if err != OK:
		print("[PadBindings] Failed to save controller bindings: %s" % error_string(err))
	else:
		print("[PadBindings] Saved controller bindings to %s" % SAVE_PATH)


func load_bindings() -> void:
	var cfg = ConfigFile.new()
	var err = cfg.load(SAVE_PATH)
	if err != OK:
		print("[PadBindings] No saved controller bindings found, using defaults")
		return
	for role_id in roles:
		if cfg.has_section(role_id):
			var b: int = int(cfg.get_value(role_id, "button", roles[role_id].default_button))
			if is_button_assignable(b):
				roles[role_id].button = b
	# Sanity: two roles sharing one button (hand-edited/corrupt file) would make
	# canonical() ambiguous — on any duplicate, fall back to defaults wholesale.
	var seen: Dictionary = {}
	for role_id in roles:
		var b: int = roles[role_id].button
		if seen.has(b):
			print("[PadBindings] Duplicate button in saved layout — resetting to defaults")
			for rid in roles:
				roles[rid].button = roles[rid].default_button
			return
		seen[b] = true
	print("[PadBindings] Loaded controller bindings from %s" % SAVE_PATH)

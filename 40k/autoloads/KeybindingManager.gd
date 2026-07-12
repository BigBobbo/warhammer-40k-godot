extends Node

# Centralized keybinding manager — allows rebinding of keyboard shortcuts
# Save/load to user://keybindings.cfg using ConfigFile (same pattern as SettingsService)

signal binding_changed(action_id: String)

const SAVE_PATH = "user://keybindings.cfg"

# Binding definition: { display_name, category, key, modifiers (shift/ctrl/alt), default_key, default_modifiers }
# key uses Godot KEY_* constants, modifiers is a dict { shift: bool, ctrl: bool, alt: bool }
var bindings: Dictionary = {}

# Categories for UI grouping
const CATEGORY_CAMERA = "Camera"
const CATEGORY_GAMEPLAY = "Gameplay"
const CATEGORY_MODEL = "Model"
const CATEGORY_PANELS = "Panels & Overlays"
const CATEGORY_AI = "AI"
const CATEGORY_DEBUG = "Debug"
const CATEGORY_REPLAY = "Replay Playback"

func _ready() -> void:
	_register_defaults()
	load_bindings()
	print("[KeybindingManager] Ready — %d bindings registered" % bindings.size())

# ============================================================================
# Registration
# ============================================================================

func _register_defaults() -> void:
	# ── Camera / View ──
	_register("camera_pan_up", "Pan Up", CATEGORY_CAMERA, KEY_W, {}, KEY_UP)
	_register("camera_pan_down", "Pan Down", CATEGORY_CAMERA, KEY_S, {}, KEY_DOWN)
	_register("camera_pan_left", "Pan Left", CATEGORY_CAMERA, KEY_A, {}, KEY_LEFT)
	_register("camera_pan_right", "Pan Right", CATEGORY_CAMERA, KEY_D, {}, KEY_RIGHT)
	_register("zoom_in", "Zoom In", CATEGORY_CAMERA, KEY_EQUAL)
	_register("zoom_out", "Zoom Out", CATEGORY_CAMERA, KEY_MINUS)
	_register("rotate_board", "Rotate Board View", CATEGORY_CAMERA, KEY_V)
	_register("focus_p2_zone", "Focus P2 Zone", CATEGORY_CAMERA, KEY_F)
	_register("fit_view_board", "Fit View to Board", CATEGORY_CAMERA, KEY_F)
	_register("fit_view_selection", "Fit View to Selection", CATEGORY_CAMERA, KEY_F, {"shift": true})

	# ── Gameplay ──
	_register("toggle_deploy_zones", "Toggle Deploy Zones", CATEGORY_GAMEPLAY, KEY_Z)
	_register("toggle_terrain", "Toggle Terrain", CATEGORY_GAMEPLAY, KEY_G)
	_register("measuring_tape", "Measuring Tape (hold)", CATEGORY_GAMEPLAY, KEY_T)
	_register("clear_measurements", "Clear Measurements", CATEGORY_GAMEPLAY, KEY_Y)
	_register("quick_save", "Quick Save", CATEGORY_GAMEPLAY, KEY_BRACKETLEFT)
	_register("quick_load", "Quick Load", CATEGORY_GAMEPLAY, KEY_BRACKETRIGHT)
	# SAVE-16: Save slot shortcuts (Ctrl+1..5 to save, Shift+1..5 to load)
	_register("save_slot_1", "Save Slot 1", CATEGORY_GAMEPLAY, KEY_1, {"ctrl": true})
	_register("save_slot_2", "Save Slot 2", CATEGORY_GAMEPLAY, KEY_2, {"ctrl": true})
	_register("save_slot_3", "Save Slot 3", CATEGORY_GAMEPLAY, KEY_3, {"ctrl": true})
	_register("save_slot_4", "Save Slot 4", CATEGORY_GAMEPLAY, KEY_4, {"ctrl": true})
	_register("save_slot_5", "Save Slot 5", CATEGORY_GAMEPLAY, KEY_5, {"ctrl": true})
	_register("load_slot_1", "Load Slot 1", CATEGORY_GAMEPLAY, KEY_1, {"shift": true})
	_register("load_slot_2", "Load Slot 2", CATEGORY_GAMEPLAY, KEY_2, {"shift": true})
	_register("load_slot_3", "Load Slot 3", CATEGORY_GAMEPLAY, KEY_3, {"shift": true})
	_register("load_slot_4", "Load Slot 4", CATEGORY_GAMEPLAY, KEY_4, {"shift": true})
	_register("load_slot_5", "Load Slot 5", CATEGORY_GAMEPLAY, KEY_5, {"shift": true})
	_register("toggle_unit_labels", "Toggle Unit Labels", CATEGORY_GAMEPLAY, KEY_N)
	_register("toggle_aura_rings", "Toggle Aura Rings", CATEGORY_GAMEPLAY, KEY_A)
	_register("toggle_grid_overlay", "Toggle Tactical Grid", CATEGORY_GAMEPLAY, KEY_G)
	_register("ruler_tool", "Ruler Tool (Shift = private)", CATEGORY_GAMEPLAY, KEY_R)
	_register("threat_overlay", "Threat Overlay (hold)", CATEGORY_GAMEPLAY, KEY_TAB)
	_register("los_check", "Check Line of Sight (hold)", CATEGORY_GAMEPLAY, KEY_G)
	_register("los_debug", "Sight-Line Overlay (hold)", CATEGORY_GAMEPLAY, KEY_L)

	# Shooting phase (T5-UX12 → KeybindingManager registration 2026-05-05)
	# These were previously hardcoded keycode matches in ShootingController; promoting
	# them to registered actions makes them rebindable + listable in the overlay.
	_register("shoot_confirm_targets", "Confirm Targets (Shoot)", CATEGORY_GAMEPLAY, KEY_SPACE, {}, KEY_ENTER)
	_register("shoot_cancel_target", "Cancel Target (Shoot)", CATEGORY_GAMEPLAY, KEY_ESCAPE)
	_register("shoot_cycle_eligible_unit", "Cycle Eligible Shooter", CATEGORY_GAMEPLAY, KEY_TAB)
	_register("shoot_skip_unit", "Skip Active Shooter", CATEGORY_GAMEPLAY, KEY_N)
	_register("shoot_end_phase", "End Shooting Phase", CATEGORY_GAMEPLAY, KEY_E)

	# ── Model ──
	_register("rotate_left", "Rotate Model Left", CATEGORY_MODEL, KEY_Q)
	_register("rotate_right", "Rotate Model Right", CATEGORY_MODEL, KEY_E)
	_register("undo_deployment", "Undo Deployment", CATEGORY_MODEL, KEY_Z, {"ctrl": true})
	_register("select_all", "Select All", CATEGORY_MODEL, KEY_A, {"ctrl": true})

	# ── Panels & Overlays ──
	_register("toggle_army_panel", "Toggle Army Panel", CATEGORY_PANELS, KEY_U)
	_register("toggle_stratagem_panel", "Toggle Stratagems Panel", CATEGORY_PANELS, KEY_S)
	_register("toggle_missions_panel", "Toggle Missions Panel", CATEGORY_PANELS, KEY_M)
	_register("toggle_replay_panel", "Toggle AI Replay Panel", CATEGORY_PANELS, KEY_R)
	_register("toggle_chat_panel", "Toggle Chat Panel", CATEGORY_PANELS, KEY_T)
	_register("weapon_range_panel", "Toggle Weapon Range Panel", CATEGORY_PANELS, KEY_W)
	_register("datasheet_modal", "Open Unit Datasheet", CATEGORY_PANELS, KEY_I)
	_register("toggle_roster_strip", "Toggle Roster Strip", CATEGORY_PANELS, KEY_B)
	_register("toggle_mathhammer", "Toggle Mathhammer", CATEGORY_PANELS, KEY_H)
	_register("toggle_vp_timeline", "Toggle VP Timeline", CATEGORY_PANELS, KEY_V)
	_register("toggle_visual_style", "Cycle Unit Visual Style", CATEGORY_PANELS, KEY_8)
	_register("shortcut_overlay", "Deployment Shortcut Overlay", CATEGORY_PANELS, KEY_SLASH, {"shift": true})
	_register("hotkey_help", "Toggle Hotkey Help", CATEGORY_PANELS, KEY_SLASH, {"shift": true})
	_register("ai_suggestion", "AI Suggestion (hint)", CATEGORY_PANELS, KEY_K)

	# ── AI ──
	_register("ai_step_continue", "Step Continue", CATEGORY_AI, KEY_SPACE)
	_register("ai_speed_decrease", "Speed Decrease", CATEGORY_AI, KEY_COMMA)
	_register("ai_speed_increase", "Speed Increase", CATEGORY_AI, KEY_PERIOD)
	_register("ai_speed_cycle", "Speed Cycle", CATEGORY_AI, KEY_SLASH)
	_register("ai_export_log", "Export AI Decision Log", CATEGORY_AI, KEY_F10)

	# ── Debug ──
	_register("toggle_debug_mode", "Toggle Debug Mode", CATEGORY_DEBUG, KEY_9)
	_register("objective_check", "Objective Control Check", CATEGORY_DEBUG, KEY_O)
	_register("toggle_dev_tools", "Toggle Dev Tools", CATEGORY_DEBUG, KEY_D, {"shift": true})

	# ── Replay Playback (only active while a replay is loaded) ──
	_register("replay_play_pause", "Play / Pause", CATEGORY_REPLAY, KEY_SPACE)
	_register("replay_step_back", "Step Back", CATEGORY_REPLAY, KEY_LEFT)
	_register("replay_step_forward", "Step Forward", CATEGORY_REPLAY, KEY_RIGHT)
	_register("replay_speed", "Cycle Speed", CATEGORY_REPLAY, KEY_S)
	_register("replay_jump_start", "Jump to Start", CATEGORY_REPLAY, KEY_HOME)
	_register("replay_jump_end", "Jump to End", CATEGORY_REPLAY, KEY_END)

func _register(action_id: String, display_name: String, category: String, key: int, modifiers: Dictionary = {}, alt_key: int = 0) -> void:
	bindings[action_id] = {
		"display_name": display_name,
		"category": category,
		"key": key,
		"alt_key": alt_key,
		"shift": modifiers.get("shift", false),
		"ctrl": modifiers.get("ctrl", false),
		"alt": modifiers.get("alt", false),
		"meta": modifiers.get("meta", false),
		"default_key": key,
		"default_alt_key": alt_key,
		"default_shift": modifiers.get("shift", false),
		"default_ctrl": modifiers.get("ctrl", false),
		"default_alt": modifiers.get("alt", false),
		"default_meta": modifiers.get("meta", false),
	}

# ============================================================================
# Query API
# ============================================================================

## Check if an InputEventKey matches a registered action (for use in _input/_unhandled_input)
func matches_action(event: InputEventKey, action_id: String) -> bool:
	if not bindings.has(action_id):
		return false
	var b = bindings[action_id]
	# Check modifier requirements (strict: modifier state must match exactly)
	if b.shift != event.shift_pressed:
		return false
	if b.ctrl != event.ctrl_pressed:
		return false
	if b.alt != event.alt_pressed:
		return false
	if b.get("meta", false) != event.meta_pressed:
		return false
	# Check primary key or alt key
	if event.keycode == b.key:
		return true
	if b.alt_key != 0 and event.keycode == b.alt_key:
		return true
	return false

## Check if the key for a registered action is currently held down (for use in _process)
func is_action_pressed(action_id: String) -> bool:
	if not bindings.has(action_id):
		return false
	var b = bindings[action_id]
	# For held-key checks, verify modifiers if required
	if b.shift and not Input.is_key_pressed(KEY_SHIFT):
		return false
	if b.ctrl and not Input.is_key_pressed(KEY_CTRL):
		return false
	if b.alt and not Input.is_key_pressed(KEY_ALT):
		return false
	if b.get("meta", false) and not Input.is_key_pressed(KEY_META):
		return false
	# Check primary or alt key
	if Input.is_key_pressed(b.key):
		return true
	if b.alt_key != 0 and Input.is_key_pressed(b.alt_key):
		return true
	return false

## Get the display string for a binding (e.g. "Ctrl+Z", "Shift+/")
func get_key_display_name(action_id: String) -> String:
	if not bindings.has(action_id):
		return "???"
	var b = bindings[action_id]
	var parts: PackedStringArray = []
	if b.ctrl:
		parts.append("Ctrl")
	if b.shift:
		parts.append("Shift")
	if b.alt:
		parts.append("Alt")
	if b.get("meta", false):
		parts.append("Meta")
	parts.append(_keycode_to_string(b.key))
	var result = "+".join(parts)
	if b.alt_key != 0:
		result += " / " + _keycode_to_string(b.alt_key)
	return result

## Get just the primary key display (no alt key)
func get_primary_key_display(action_id: String) -> String:
	if not bindings.has(action_id):
		return "???"
	var b = bindings[action_id]
	var parts: PackedStringArray = []
	if b.ctrl:
		parts.append("Ctrl")
	if b.shift:
		parts.append("Shift")
	if b.alt:
		parts.append("Alt")
	if b.get("meta", false):
		parts.append("Meta")
	parts.append(_keycode_to_string(b.key))
	return "+".join(parts)

## Get alt key display, or empty string if none
func get_alt_key_display(action_id: String) -> String:
	if not bindings.has(action_id):
		return ""
	var b = bindings[action_id]
	if b.alt_key == 0:
		return ""
	return _keycode_to_string(b.alt_key)

## Get binding info dict for a given action
func get_binding(action_id: String) -> Dictionary:
	if bindings.has(action_id):
		return bindings[action_id]
	return {}

## Get all action IDs in a given category
func get_actions_in_category(category: String) -> Array:
	var result = []
	for action_id in bindings:
		if bindings[action_id].category == category:
			result.append(action_id)
	return result

## Get ordered list of categories
func get_categories() -> Array:
	return [CATEGORY_CAMERA, CATEGORY_GAMEPLAY, CATEGORY_MODEL, CATEGORY_PANELS, CATEGORY_AI, CATEGORY_DEBUG, CATEGORY_REPLAY]

# ============================================================================
# Rebinding
# ============================================================================

## Set the primary key binding for an action
func set_binding(action_id: String, key: int, shift: bool = false, ctrl: bool = false, alt: bool = false, meta: bool = false) -> void:
	if not bindings.has(action_id):
		return
	bindings[action_id].key = key
	bindings[action_id].shift = shift
	bindings[action_id].ctrl = ctrl
	bindings[action_id].alt = alt
	bindings[action_id].meta = meta
	save_bindings()
	binding_changed.emit(action_id)
	print("[KeybindingManager] Rebound '%s' to %s" % [action_id, get_key_display_name(action_id)])

## Set the alt key binding for an action (0 to clear)
func set_alt_binding(action_id: String, alt_key: int) -> void:
	if not bindings.has(action_id):
		return
	bindings[action_id].alt_key = alt_key
	save_bindings()
	binding_changed.emit(action_id)

## Reset a single binding to its default
func reset_binding(action_id: String) -> void:
	if not bindings.has(action_id):
		return
	var b = bindings[action_id]
	b.key = b.default_key
	b.alt_key = b.default_alt_key
	b.shift = b.default_shift
	b.ctrl = b.default_ctrl
	b.alt = b.default_alt
	b.meta = b.get("default_meta", false)
	save_bindings()
	binding_changed.emit(action_id)
	print("[KeybindingManager] Reset '%s' to default" % action_id)

## Reset all bindings to defaults
func reset_all() -> void:
	for action_id in bindings:
		var b = bindings[action_id]
		b.key = b.default_key
		b.alt_key = b.default_alt_key
		b.shift = b.default_shift
		b.ctrl = b.default_ctrl
		b.alt = b.default_alt
		b.meta = b.get("default_meta", false)
	save_bindings()
	for action_id in bindings:
		binding_changed.emit(action_id)
	print("[KeybindingManager] All bindings reset to defaults")

## Find conflicting action (same key+modifiers), returns action_id or ""
func find_conflict(action_id: String, key: int, shift: bool, ctrl: bool, alt: bool, meta: bool = false) -> String:
	for other_id in bindings:
		if other_id == action_id:
			continue
		var b = bindings[other_id]
		if b.key == key and b.shift == shift and b.ctrl == ctrl and b.alt == alt and b.get("meta", false) == meta:
			return other_id
	return ""

## Check if the binding differs from default
func is_modified(action_id: String) -> bool:
	if not bindings.has(action_id):
		return false
	var b = bindings[action_id]
	return b.key != b.default_key or b.alt_key != b.default_alt_key or b.shift != b.default_shift or b.ctrl != b.default_ctrl or b.alt != b.default_alt or b.get("meta", false) != b.get("default_meta", false)

# ============================================================================
# Persistence
# ============================================================================

func save_bindings() -> void:
	var cfg = ConfigFile.new()
	for action_id in bindings:
		var b = bindings[action_id]
		cfg.set_value(action_id, "key", b.key)
		cfg.set_value(action_id, "alt_key", b.alt_key)
		cfg.set_value(action_id, "shift", b.shift)
		cfg.set_value(action_id, "ctrl", b.ctrl)
		cfg.set_value(action_id, "alt", b.alt)
		cfg.set_value(action_id, "meta", b.get("meta", false))
	var err = cfg.save(SAVE_PATH)
	if err != OK:
		print("[KeybindingManager] Failed to save keybindings: %s" % error_string(err))
	else:
		print("[KeybindingManager] Saved keybindings to %s" % SAVE_PATH)

func load_bindings() -> void:
	var cfg = ConfigFile.new()
	var err = cfg.load(SAVE_PATH)
	if err != OK:
		print("[KeybindingManager] No saved keybindings found, using defaults")
		return
	for action_id in bindings:
		if cfg.has_section(action_id):
			bindings[action_id].key = cfg.get_value(action_id, "key", bindings[action_id].default_key)
			bindings[action_id].alt_key = cfg.get_value(action_id, "alt_key", bindings[action_id].default_alt_key)
			bindings[action_id].shift = cfg.get_value(action_id, "shift", bindings[action_id].default_shift)
			bindings[action_id].ctrl = cfg.get_value(action_id, "ctrl", bindings[action_id].default_ctrl)
			bindings[action_id].alt = cfg.get_value(action_id, "alt", bindings[action_id].default_alt)
			bindings[action_id].meta = cfg.get_value(action_id, "meta", bindings[action_id].get("default_meta", false))
	print("[KeybindingManager] Loaded keybindings from %s" % SAVE_PATH)

# ============================================================================
# Helpers
# ============================================================================

func _keycode_to_string(keycode: int) -> String:
	match keycode:
		KEY_SPACE: return "Space"
		KEY_QUESTION: return "?"
		KEY_COMMA: return ","
		KEY_PERIOD: return "."
		KEY_SLASH: return "/"
		KEY_MINUS: return "-"
		KEY_EQUAL: return "="
		KEY_BRACKETLEFT: return "["
		KEY_BRACKETRIGHT: return "]"
		KEY_UP: return "Up"
		KEY_DOWN: return "Down"
		KEY_LEFT: return "Left"
		KEY_RIGHT: return "Right"
		KEY_ESCAPE: return "Esc"
		KEY_TAB: return "Tab"
		KEY_ENTER: return "Enter"
		KEY_BACKSPACE: return "Backspace"
		KEY_DELETE: return "Delete"
		KEY_HOME: return "Home"
		KEY_END: return "End"
		KEY_PAGEUP: return "Page Up"
		KEY_PAGEDOWN: return "Page Down"
		KEY_SEMICOLON: return ";"
		KEY_APOSTROPHE: return "'"
		KEY_BACKSLASH: return "\\"
		KEY_QUOTELEFT: return "`"
		0: return "None"
		_:
			# For letter/number keys, use OS.get_keycode_string
			var s = OS.get_keycode_string(keycode)
			if s != "":
				return s
			return "Key(%d)" % keycode

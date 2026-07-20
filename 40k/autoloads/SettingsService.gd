extends Node

var px_per_inch: float = 40.0
var board_width_inches: float = 44.0
var board_height_inches: float = 60.0
var deployment_zone_depth_inches: float = 12.0

# Unit visual style: "letter" (colored base+letter), "enhanced" (gradient+sprites), "style_a" (silhouettes), "style_b" (faction glyphs), "classic" (plain)
var unit_visual_style: String = "letter"

# How a unit's custom/auto-assigned color is applied to its token in letter
# mode: "ring" (default) keeps a neutral base and draws the color only as a ring
# just inside the base perimeter, so the model art stays readable and squads are
# told apart by ring; "full" fills the whole base with the color (original look).
var unit_color_display_mode: String = "ring"

# Sprite directory for user-provided token art (Phase 2)
var sprite_directory: String = "user://sprites/"

# Retro visual mode: (deprecated — kept for save compatibility, no longer used)
var retro_mode: bool = false

# Save/Load Settings
var save_files_pretty_print: bool = true  # Human-readable by default
var save_files_compression: bool = true  # SAVE-17: Enabled — only compresses saves above size threshold

# Measuring Tape Settings
var save_measurements: bool = false  # Whether to persist measurement lines in saves

# P3-112: Autosave event settings
var autosave_on_round_end: bool = true      # Auto-save when a battle round completes
var autosave_on_phase_transition: bool = false  # Auto-save at every phase transition

# Phase-start named autosave — creates/overwrites a save named
# "<army1> vs <army2> - <phase>" at the start of each phase. On by default;
# players can turn it off from Settings → Gameplay. Works on web/itch.io.
var autosave_on_phase_start: bool = true

# P3-111: Audio settings
var master_volume: float = 1.0   # 0.0 to 1.0
var music_volume: float = 0.7    # 0.0 to 1.0
var sfx_volume: float = 1.0      # 0.0 to 1.0
var audio_muted: bool = false

# P3-111: Visual settings
var ui_scale: float = 1.0        # 0.5 to 2.0
var animation_speed: float = 1.0 # 0.25 to 3.0

# P0 Steam Deck legibility: while a controller is the active device, multiply the
# canvas content scale by PAD_UI_SCALE_BOOST so 11-13px HUD text clears the
# Deck's ~9px physical floor (the 1920x1080 base rendered onto the 1280x800 panel
# shrinks everything ~0.67x). KBM keeps content_scale = ui_scale unchanged.
# Toggleable so a desktop player using a gamepad on a big screen can turn it off.
var controller_text_boost: bool = true
const PAD_UI_SCALE_BOOST: float = 1.2

# P1 Steam Deck controller options (Settings › Controls › Controller). All are
# pad-only; mouse/keyboard is unaffected. Consumed by Main._process (camera pan),
# VirtualCursor (cursor speed + magnetism) and InputDeviceManager (stick swap).
var pad_invert_camera_y: bool = false
var pad_swap_sticks: bool = false          # cursor on the RIGHT stick, camera on the LEFT
var pad_camera_sensitivity: float = 1.0    # 0.3 to 2.0 — right-stick camera pan speed
var pad_cursor_sensitivity: float = 1.0    # 0.3 to 2.0 — virtual-cursor speed
var pad_cursor_magnetism: bool = true      # ease the cursor toward nearby tokens (P0 magnetism)

# Menu / panel scroll speed — fraction of Godot's default mouse-wheel / trackpad
# scroll distance applied to ScrollContainers and other scroll surfaces. 1.0 ==
# stock engine speed; lower == slower. Consumed by ScrollSpeedController.
var menu_scroll_speed: float = 0.4  # 0.1 to 1.0

# P3-111: Colorblind mode — "none", "protanopia", "deuteranopia", "tritanopia"
var colorblind_mode: String = "none"

# Unit label visibility — toggle the name text shown underneath models
var show_unit_labels: bool = true

# Terrain debug labels — when true, terrain pieces show their full internal id
# ("Ruins corner-short-11 (T)") plus the LoS-blocker badge. When false (player
# default) they show only a compact height glyph chip (T/M/L).
var terrain_debug_labels: bool = false

# Terrain scatter props — when true (default) terrain pieces render their
# decorative scatter sprites (ruins: crates + sandbags, woods: trees) and other
# cosmetic per-type details. When false the board shows only the terrain
# footprints, borders and walls, for a cleaner/less cluttered look.
var show_terrain_scatter: bool = true

# Terrain cover labels — the per-tile shield glyph chips (LB / +2 / +1) that
# TerrainCoverOverlay draws at the centroid of every terrain piece. Defaults OFF
# so the board is uncluttered; players who want the cover-type reference can turn
# it on via Settings > Visual.
var show_terrain_cover_labels: bool = false

# Gameplay settings
# When true, the computer automatically chooses which wounded/destroyed models
# are removed during wound allocation instead of prompting the local player.
# Per the core rules the *defending* player rolls saves and picks casualties —
# the defender-driven flow (AllocationGroupOverlay: roll saves, optional save
# Command Re-roll, click the bases to remove) is now the DEFAULT. This setting
# lets a player delegate all of that to the computer for faster play.
# Defaults OFF since the defender-control update (see
# AUTO_ALLOCATE_MIGRATION_KEY below, which retires older saved `true` values).
var auto_allocate_wounds: bool = false

# B3 (audit 2026-07): staged resolution pause policy — ONE setting shared by
# the shooting AND fight resolution docks (kept under its original
# "shooting_pause_policy" name for saved-settings compatibility) so both
# phases pause with the same rhythm:
#   "every_step" (default): pause at every hit/wound roll
#   "decisions":  pause only when a Command Re-roll is actually usable
#                 (CP available, not used this phase, and a failed die exists)
#   "never":      auto-continue the hit/wound pauses (the between-weapon
#                 pause and defender saves always remain)
var shooting_pause_policy: String = "every_step"

# Shooting phase "Select Shooter" list filter. When false (default) the list
# shows only units that have a genuine reason to act this phase — a unit with an
# eligible shooting target (in range + line of sight) or a mission action it can
# perform. Units that could technically shoot but have no target in range/LoS are
# hidden to declutter the list. When true, every unit that could shoot is listed
# regardless of whether it has a target. Toggled live from the shooting panel's
# "Show all units" checkbox (persisted here so the choice sticks between phases
# and sessions).
var shooting_show_all_units: bool = false

# Rules edition: 10 (10th edition) or 11 (11th edition core rules, now the
# default for players). Applied to GameConstants.edition at startup and whenever
# changed, so the whole rules engine plays the selected edition. Players can
# switch back to 10e via the main-menu "Rules Edition" dropdown (persisted here).
# (ISS-A0 / 11e migration go-live; default flipped to 11 per owner request.)
# NOTE: the automated test/scenario harness controls edition explicitly and
# keeps a 10e baseline — _ready() below does NOT apply this default there.
# Rules edition is no longer a player setting — the game is 11th edition
# only (the 10e data/code paths survive solely for the legacy regression
# suite and are pinned by the harness carve-out in _ready).

# Board texture style: "grass", "mud", "desert", "stone", "felt", "tilepack", "none"
var board_style: String = "grass"

# Ruins texture style: "concrete", "marble", "brick", "weathered_stone", "none"
var ruins_style: String = "concrete"

# P3-111: Signals for real-time setting changes
signal ui_scale_changed(new_scale: float)
signal animation_speed_changed(new_speed: float)
signal menu_scroll_speed_changed(new_speed: float)
signal colorblind_mode_changed(new_mode: String)
signal audio_settings_changed()
signal unit_labels_visibility_changed(visible: bool)
signal board_style_changed(new_style: String)
signal ruins_style_changed(new_style: String)
signal auto_allocate_wounds_changed(enabled: bool)
signal unit_style_changed(new_style: String)
signal unit_color_display_changed(new_mode: String)
signal terrain_debug_labels_changed(enabled: bool)
signal terrain_scatter_changed(enabled: bool)
signal terrain_cover_labels_changed(enabled: bool)
signal shooting_show_all_units_changed(show_all: bool)

# P3-111: Settings config file path
const SETTINGS_FILE_PATH: String = "user://settings.cfg"

# Defender-control update: marker key proving the config was saved after the
# auto_allocate_wounds default flipped to false (see _load_settings migration).
const AUTO_ALLOCATE_MIGRATION_KEY: String = "auto_allocate_wounds_defender_control"

func get_save_measurements() -> bool:
	return save_measurements

func set_save_measurements(enabled: bool) -> void:
	save_measurements = enabled
	# Update MeasuringTapeManager immediately
	if MeasuringTapeManager:
		MeasuringTapeManager.set_save_persistence(enabled)

func get_save_pretty_print() -> bool:
	return save_files_pretty_print

func set_save_pretty_print(enabled: bool) -> void:
	save_files_pretty_print = enabled
	# Update StateSerializer immediately
	if StateSerializer:
		StateSerializer.set_pretty_print(enabled)

func _is_automated_harness() -> bool:
	# True when running under the windowed-scenario runner (--scenario-file=…),
	# the headless GUT suite (gut_cmdln.gd), or a direct script run
	# (`godot -s tests/test_*.gd` — the audit-suite SceneTree tests). Those
	# harnesses set the rules edition explicitly and expect a 10e baseline, so
	# SettingsService must not apply the player's default (11e) over them.
	# A normal player/game launch never passes -s/--script, so it returns false.
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if typeof(a) != TYPE_STRING:
			continue
		if a.begins_with("--scenario-file=") or a.find("gut_cmdln") != -1:
			return true
		if a == "-s" or a == "--script":
			return true
	return false

func _ready() -> void:
	# P3-111: Load persisted settings before applying anything
	_load_settings()

	# The game is 11th edition only: every player launch runs at 11, no matter
	# what an old settings.cfg carried (pre-removal builds persisted a
	# rules_edition that could silently pin players to 10e).
	# EXCEPTION: the automated test/scenario harness keeps the historical 10e
	# baseline — scenarios/GUT tests control the edition explicitly, and the
	# ~70 fieldless legacy scenarios were authored against 10e. This carve-out
	# disappears when the 10e code paths are deleted.
	if _is_automated_harness():
		GameConstants.edition = 10
		print("[SettingsService] Automated harness — GameConstants.edition pinned to the legacy 10e test baseline")
	else:
		GameConstants.edition = 11
		print("[SettingsService] Rules edition: 11 (11th edition only)")

	# P3-111: Set up audio buses and apply saved audio settings
	_setup_audio_buses()
	_apply_audio_settings()

	# M0 controller foundations: the persisted UI Scale finally has a consumer.
	_apply_ui_scale()
	# P0 legibility: re-apply the scale whenever the active input device flips so
	# the controller text boost turns on/off live. Deferred because SettingsService
	# is an EARLIER autoload than InputDeviceManager — connecting inline here would
	# silently no-op (the InputDeviceManager singleton isn't instantiated yet).
	call_deferred("_connect_device_boost")

	# Initialize StateSerializer with settings
	if StateSerializer:
		StateSerializer.set_pretty_print(save_files_pretty_print)
		StateSerializer.set_compression_enabled(save_files_compression)

	# Initialize MeasuringTapeManager with settings
	if MeasuringTapeManager:
		MeasuringTapeManager.set_save_persistence(save_measurements)

	# P3-112: Initialize SaveLoadManager event autosave settings
	if SaveLoadManager:
		SaveLoadManager.set_autosave_on_round_end(autosave_on_round_end)
		SaveLoadManager.set_autosave_on_phase_transition(autosave_on_phase_transition)
		SaveLoadManager.set_autosave_on_phase_start(autosave_on_phase_start)

	print("[SettingsService] Ready — ui_scale=%.2f, animation_speed=%.2f, colorblind=%s" % [ui_scale, animation_speed, colorblind_mode])

func set_retro_mode(enabled: bool) -> void:
	retro_mode = enabled
	# Tokens in non-animating styles only redraw on interaction, so broadcast the
	# change or they keep rendering the previous style until hovered.
	unit_style_changed.emit(unit_visual_style)
	DebugLogger.info("[SettingsService] Retro mode %s (deprecated)" % ("enabled" if enabled else "disabled"))

func get_board_width_px() -> float:
	return board_width_inches * px_per_inch

func get_board_height_px() -> float:
	return board_height_inches * px_per_inch

func get_deployment_zone_depth_px() -> float:
	return deployment_zone_depth_inches * px_per_inch

# ============================================================================
# P3-111: Audio Bus Setup & Control
# ============================================================================

func _setup_audio_buses() -> void:
	# Ensure Master bus exists (index 0 is always Master)
	# Add Music and SFX buses if they don't exist
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
		print("[SettingsService] Created Music audio bus")

	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
		print("[SettingsService] Created SFX audio bus")

func _apply_audio_settings() -> void:
	var master_idx = AudioServer.get_bus_index("Master")
	var music_idx = AudioServer.get_bus_index("Music")
	var sfx_idx = AudioServer.get_bus_index("SFX")

	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_volume))
		AudioServer.set_bus_mute(master_idx, audio_muted)
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume))
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume))

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	var idx = AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(master_volume))
	audio_settings_changed.emit()
	_save_settings()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	var idx = AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(music_volume))
	audio_settings_changed.emit()
	_save_settings()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	var idx = AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(sfx_volume))
	audio_settings_changed.emit()
	_save_settings()

func set_audio_muted(muted: bool) -> void:
	audio_muted = muted
	var idx = AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, audio_muted)
	audio_settings_changed.emit()
	_save_settings()

# ============================================================================
# P3-111: Visual Settings
# ============================================================================

func set_ui_scale(value: float) -> void:
	ui_scale = clampf(value, 0.5, 2.0)
	_apply_ui_scale()
	ui_scale_changed.emit(ui_scale)
	_save_settings()
	print("[SettingsService] UI scale set to %.2f" % ui_scale)

func _apply_ui_scale() -> void:
	# With stretch mode canvas_items the whole canvas multiplies by the
	# window's content scale — this is what makes the UI Scale slider
	# actually resize the HUD (it was persisted but consumed by nothing).
	var w = get_window()
	if not w:
		return
	var factor := ui_scale
	# P0 Steam Deck legibility: boost the whole canvas while the pad is the
	# active device so small HUD text is readable on the 800p panel. Re-applied
	# on InputDeviceManager.device_changed so it flips live with the device.
	if _pad_text_boost_active():
		factor *= PAD_UI_SCALE_BOOST
	w.content_scale_factor = factor

func _pad_text_boost_active() -> bool:
	if not controller_text_boost:
		return false
	if InputDeviceManager == null or not InputDeviceManager.is_pad_active():
		return false
	# Never perturb the canvas scale during an automated windowed scenario — the
	# suite asserts content_scale / pixel positions at the base ui_scale (e.g.
	# pad_m0_camera). The boost is a real-play affordance; it is validated live
	# via the MCP bridge, not through the scenario runner.
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if typeof(a) == TYPE_STRING and a.begins_with("--scenario-file="):
			return false
	return true

func _connect_device_boost() -> void:
	# Runs one idle frame after _ready, by which point every autoload (including
	# InputDeviceManager) is instantiated and reachable via /root.
	var idm = get_node_or_null("/root/InputDeviceManager")
	if idm == null:
		return
	if not idm.device_changed.is_connected(_on_input_device_changed):
		idm.device_changed.connect(_on_input_device_changed)
	_apply_ui_scale()  # the active device may already be PAD by the time this fires
	_apply_pad_stick_swap()  # re-point the sticks per the saved preference

func _on_input_device_changed(_mode: int) -> void:
	# P0: KBM↔pad switch → re-apply so the controller text boost engages/clears.
	_apply_ui_scale()

func set_controller_text_boost(enabled: bool) -> void:
	controller_text_boost = enabled
	_apply_ui_scale()
	_save_settings()
	print("[SettingsService] Controller text boost: %s" % ("on" if enabled else "off"))

# --- P1 pad controller options ---------------------------------------------
func set_pad_invert_camera_y(enabled: bool) -> void:
	pad_invert_camera_y = enabled
	_save_settings()

func set_pad_camera_sensitivity(value: float) -> void:
	pad_camera_sensitivity = clampf(value, 0.3, 2.0)
	_save_settings()

func set_pad_cursor_sensitivity(value: float) -> void:
	pad_cursor_sensitivity = clampf(value, 0.3, 2.0)
	_save_settings()

func set_pad_cursor_magnetism(enabled: bool) -> void:
	pad_cursor_magnetism = enabled
	_save_settings()

func set_pad_swap_sticks(enabled: bool) -> void:
	pad_swap_sticks = enabled
	_apply_pad_stick_swap()
	_save_settings()

func _apply_pad_stick_swap() -> void:
	# Consumers read the cursor/camera stick actions by NAME, so re-pointing which
	# physical stick each is bound to (InputDeviceManager) is transparent to them.
	var idm = get_node_or_null("/root/InputDeviceManager")
	if idm != null and idm.has_method("apply_stick_swap"):
		idm.apply_stick_swap(pad_swap_sticks)

func set_animation_speed(value: float) -> void:
	animation_speed = clampf(value, 0.25, 3.0)
	animation_speed_changed.emit(animation_speed)
	_save_settings()
	print("[SettingsService] Animation speed set to %.2f" % animation_speed)

func set_menu_scroll_speed(value: float) -> void:
	menu_scroll_speed = clampf(value, 0.1, 1.0)
	# Apply live to the limiter if it's up (it also listens on the signal below).
	if ScrollSpeedController:
		ScrollSpeedController.menu_scroll_speed = menu_scroll_speed
	menu_scroll_speed_changed.emit(menu_scroll_speed)
	_save_settings()
	print("[SettingsService] menu_scroll_speed set to %.2f" % menu_scroll_speed)

func set_colorblind_mode(mode: String) -> void:
	if mode not in ["none", "protanopia", "deuteranopia", "tritanopia"]:
		print("[SettingsService] Invalid colorblind mode: %s" % mode)
		return
	colorblind_mode = mode
	colorblind_mode_changed.emit(colorblind_mode)
	_save_settings()
	print("[SettingsService] Colorblind mode set to %s" % colorblind_mode)

# P3-112: Autosave event settings
func set_autosave_on_round_end(enabled: bool) -> void:
	autosave_on_round_end = enabled
	if SaveLoadManager:
		SaveLoadManager.set_autosave_on_round_end(enabled)
	_save_settings()
	print("[SettingsService] autosave_on_round_end set to %s" % str(enabled))

func set_autosave_on_phase_transition(enabled: bool) -> void:
	autosave_on_phase_transition = enabled
	if SaveLoadManager:
		SaveLoadManager.set_autosave_on_phase_transition(enabled)
	_save_settings()
	print("[SettingsService] autosave_on_phase_transition set to %s" % str(enabled))

func set_autosave_on_phase_start(enabled: bool) -> void:
	autosave_on_phase_start = enabled
	if SaveLoadManager:
		SaveLoadManager.set_autosave_on_phase_start(enabled)
	_save_settings()
	print("[SettingsService] autosave_on_phase_start set to %s" % str(enabled))

func set_show_unit_labels(visible: bool) -> void:
	show_unit_labels = visible
	unit_labels_visibility_changed.emit(show_unit_labels)
	_save_settings()
	print("[SettingsService] show_unit_labels set to %s" % str(show_unit_labels))

func toggle_unit_labels() -> void:
	set_show_unit_labels(not show_unit_labels)

func set_board_style(style: String) -> void:
	var valid_styles = ["grass", "mud", "desert", "stone", "felt", "tilepack", "none"]
	if style not in valid_styles:
		print("[SettingsService] Invalid board style: %s" % style)
		return
	board_style = style
	board_style_changed.emit(board_style)
	_save_settings()
	print("[SettingsService] Board style set to %s" % style)

func set_ruins_style(style: String) -> void:
	var valid_styles = ["concrete", "marble", "brick", "weathered_stone", "none"]
	if style not in valid_styles:
		print("[SettingsService] Invalid ruins style: %s" % style)
		return
	ruins_style = style
	ruins_style_changed.emit(ruins_style)
	_save_settings()
	print("[SettingsService] Ruins style set to %s" % style)

func set_shooting_pause_policy(policy: String) -> void:
	if policy in ["every_step", "decisions", "never"]:
		shooting_pause_policy = policy
		_save_settings()
		print("[SettingsService] shooting_pause_policy set to %s" % policy)

func get_shooting_show_all_units() -> bool:
	return shooting_show_all_units

func set_shooting_show_all_units(show_all: bool) -> void:
	shooting_show_all_units = show_all
	shooting_show_all_units_changed.emit(shooting_show_all_units)
	_save_settings()
	print("[SettingsService] shooting_show_all_units set to %s" % str(show_all))

func get_auto_allocate_wounds() -> bool:
	return auto_allocate_wounds

func set_auto_allocate_wounds(enabled: bool) -> void:
	auto_allocate_wounds = enabled
	auto_allocate_wounds_changed.emit(auto_allocate_wounds)
	_save_settings()
	print("[SettingsService] auto_allocate_wounds set to %s" % str(enabled))

func set_unit_visual_style_setting(style: String) -> void:
	if style not in ["letter", "enhanced", "style_a", "style_b", "classic"]:
		print("[SettingsService] Invalid visual style: %s" % style)
		return
	unit_visual_style = style
	unit_style_changed.emit(unit_visual_style)
	_save_settings()
	print("[SettingsService] Unit visual style set to %s" % style)

func set_unit_color_display_mode(mode: String) -> void:
	if mode not in ["full", "ring"]:
		print("[SettingsService] Invalid unit color display mode: %s" % mode)
		return
	unit_color_display_mode = mode
	unit_color_display_changed.emit(unit_color_display_mode)
	_save_settings()
	print("[SettingsService] Unit color display mode set to %s" % mode)

func set_terrain_debug_labels(enabled: bool) -> void:
	terrain_debug_labels = enabled
	terrain_debug_labels_changed.emit(terrain_debug_labels)
	_save_settings()
	print("[SettingsService] terrain_debug_labels set to %s" % str(enabled))

func set_show_terrain_scatter(enabled: bool) -> void:
	show_terrain_scatter = enabled
	terrain_scatter_changed.emit(show_terrain_scatter)
	_save_settings()
	print("[SettingsService] show_terrain_scatter set to %s" % str(enabled))

func set_show_terrain_cover_labels(enabled: bool) -> void:
	show_terrain_cover_labels = enabled
	terrain_cover_labels_changed.emit(show_terrain_cover_labels)
	_save_settings()
	print("[SettingsService] show_terrain_cover_labels set to %s" % str(enabled))

# ============================================================================
# P3-111: Settings Persistence
# ============================================================================

func _save_settings() -> void:
	var config = ConfigFile.new()

	# Audio
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "muted", audio_muted)

	# Visual
	config.set_value("visual", "unit_visual_style", unit_visual_style)
	config.set_value("visual", "unit_color_display_mode", unit_color_display_mode)
	config.set_value("visual", "retro_mode", retro_mode)
	config.set_value("visual", "ui_scale", ui_scale)
	config.set_value("visual", "animation_speed", animation_speed)
	config.set_value("visual", "colorblind_mode", colorblind_mode)
	config.set_value("visual", "show_unit_labels", show_unit_labels)
	config.set_value("visual", "terrain_debug_labels", terrain_debug_labels)
	config.set_value("visual", "show_terrain_scatter", show_terrain_scatter)
	config.set_value("visual", "show_terrain_cover_labels", show_terrain_cover_labels)
	config.set_value("visual", "board_style", board_style)
	config.set_value("visual", "ruins_style", ruins_style)

	# Save/Load
	config.set_value("save_load", "pretty_print", save_files_pretty_print)
	config.set_value("save_load", "compression", save_files_compression)
	config.set_value("save_load", "save_measurements", save_measurements)
	config.set_value("save_load", "autosave_on_round_end", autosave_on_round_end)
	config.set_value("save_load", "autosave_on_phase_transition", autosave_on_phase_transition)
	config.set_value("save_load", "autosave_on_phase_start", autosave_on_phase_start)

	# Gameplay
	config.set_value("gameplay", "auto_allocate_wounds", auto_allocate_wounds)
	config.set_value("gameplay", "shooting_pause_policy", shooting_pause_policy)
	config.set_value("gameplay", "shooting_show_all_units", shooting_show_all_units)
	config.set_value("gameplay", AUTO_ALLOCATE_MIGRATION_KEY, true)

	# Controls
	config.set_value("controls", "menu_scroll_speed", menu_scroll_speed)
	config.set_value("controls", "controller_text_boost", controller_text_boost)
	config.set_value("controls", "pad_invert_camera_y", pad_invert_camera_y)
	config.set_value("controls", "pad_swap_sticks", pad_swap_sticks)
	config.set_value("controls", "pad_camera_sensitivity", pad_camera_sensitivity)
	config.set_value("controls", "pad_cursor_sensitivity", pad_cursor_sensitivity)
	config.set_value("controls", "pad_cursor_magnetism", pad_cursor_magnetism)

	var err = config.save(SETTINGS_FILE_PATH)
	if err != OK:
		print("[SettingsService] Failed to save settings: error %d" % err)
	else:
		print("[SettingsService] Settings saved to %s" % SETTINGS_FILE_PATH)

func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE_PATH)
	if err != OK:
		print("[SettingsService] No settings file found, using defaults")
		return

	# Audio
	master_volume = config.get_value("audio", "master_volume", 1.0)
	music_volume = config.get_value("audio", "music_volume", 0.7)
	sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
	audio_muted = config.get_value("audio", "muted", false)

	# Visual
	unit_visual_style = config.get_value("visual", "unit_visual_style", "letter")
	unit_color_display_mode = config.get_value("visual", "unit_color_display_mode", "ring")
	retro_mode = config.get_value("visual", "retro_mode", false)
	ui_scale = config.get_value("visual", "ui_scale", 1.0)
	animation_speed = config.get_value("visual", "animation_speed", 1.0)
	colorblind_mode = config.get_value("visual", "colorblind_mode", "none")
	show_unit_labels = config.get_value("visual", "show_unit_labels", true)
	terrain_debug_labels = config.get_value("visual", "terrain_debug_labels", false)
	show_terrain_scatter = config.get_value("visual", "show_terrain_scatter", true)
	show_terrain_cover_labels = config.get_value("visual", "show_terrain_cover_labels", false)
	board_style = config.get_value("visual", "board_style", "grass")
	ruins_style = config.get_value("visual", "ruins_style", "concrete")

	# Save/Load
	save_files_pretty_print = config.get_value("save_load", "pretty_print", true)
	save_files_compression = config.get_value("save_load", "compression", true)
	save_measurements = config.get_value("save_load", "save_measurements", false)
	autosave_on_round_end = config.get_value("save_load", "autosave_on_round_end", true)
	autosave_on_phase_transition = config.get_value("save_load", "autosave_on_phase_transition", false)
	autosave_on_phase_start = config.get_value("save_load", "autosave_on_phase_start", true)

	# Gameplay
	# Defender-control migration: configs written BEFORE the interactive
	# defender flow existed all carry the old `true` default the player never
	# chose. Retire that stored value once so everyone lands on the new
	# defender-rolls-their-own-saves default; a value saved AFTER the
	# migration marker exists is an explicit player choice and is respected.
	if config.get_value("gameplay", AUTO_ALLOCATE_MIGRATION_KEY, false):
		auto_allocate_wounds = config.get_value("gameplay", "auto_allocate_wounds", false)
	else:
		auto_allocate_wounds = false
		print("[SettingsService] auto_allocate_wounds migrated to the defender-control default (false)")

	shooting_pause_policy = str(config.get_value("gameplay", "shooting_pause_policy", "every_step"))
	shooting_show_all_units = config.get_value("gameplay", "shooting_show_all_units", false)

	# Controls
	menu_scroll_speed = clampf(config.get_value("controls", "menu_scroll_speed", 0.4), 0.1, 1.0)
	controller_text_boost = bool(config.get_value("controls", "controller_text_boost", true))
	pad_invert_camera_y = bool(config.get_value("controls", "pad_invert_camera_y", false))
	pad_swap_sticks = bool(config.get_value("controls", "pad_swap_sticks", false))
	pad_camera_sensitivity = clampf(config.get_value("controls", "pad_camera_sensitivity", 1.0), 0.3, 2.0)
	pad_cursor_sensitivity = clampf(config.get_value("controls", "pad_cursor_sensitivity", 1.0), 0.3, 2.0)
	pad_cursor_magnetism = bool(config.get_value("controls", "pad_cursor_magnetism", true))

	print("[SettingsService] Settings loaded from %s" % SETTINGS_FILE_PATH)
extends Node

var px_per_inch: float = 40.0
var board_width_inches: float = 44.0
var board_height_inches: float = 60.0
var deployment_zone_depth_inches: float = 12.0

# Unit visual style: "letter" (colored base+letter), "enhanced" (gradient+sprites), "style_a" (silhouettes), "style_b" (faction glyphs), "classic" (plain)
var unit_visual_style: String = "letter"

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

# P3-111: Audio settings
var master_volume: float = 1.0   # 0.0 to 1.0
var music_volume: float = 0.7    # 0.0 to 1.0
var sfx_volume: float = 1.0      # 0.0 to 1.0
var audio_muted: bool = false

# P3-111: Visual settings
var ui_scale: float = 1.0        # 0.5 to 2.0
var animation_speed: float = 1.0 # 0.25 to 3.0

# P3-111: Colorblind mode — "none", "protanopia", "deuteranopia", "tritanopia"
var colorblind_mode: String = "none"

# Unit label visibility — toggle the name text shown underneath models
var show_unit_labels: bool = true

# P3-111: Signals for real-time setting changes
signal ui_scale_changed(new_scale: float)
signal animation_speed_changed(new_speed: float)
signal colorblind_mode_changed(new_mode: String)
signal audio_settings_changed()
signal unit_labels_visibility_changed(visible: bool)

# P3-111: Settings config file path
const SETTINGS_FILE_PATH: String = "user://settings.cfg"

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

func _ready() -> void:
	# P3-111: Load persisted settings before applying anything
	_load_settings()

	# P3-111: Set up audio buses and apply saved audio settings
	_setup_audio_buses()
	_apply_audio_settings()

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

	print("[SettingsService] Ready — ui_scale=%.2f, animation_speed=%.2f, colorblind=%s" % [ui_scale, animation_speed, colorblind_mode])

func set_retro_mode(enabled: bool) -> void:
	retro_mode = enabled
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
	ui_scale_changed.emit(ui_scale)
	_save_settings()
	print("[SettingsService] UI scale set to %.2f" % ui_scale)

func set_animation_speed(value: float) -> void:
	animation_speed = clampf(value, 0.25, 3.0)
	animation_speed_changed.emit(animation_speed)
	_save_settings()
	print("[SettingsService] Animation speed set to %.2f" % animation_speed)

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

func set_show_unit_labels(visible: bool) -> void:
	show_unit_labels = visible
	unit_labels_visibility_changed.emit(show_unit_labels)
	_save_settings()
	print("[SettingsService] show_unit_labels set to %s" % str(show_unit_labels))

func toggle_unit_labels() -> void:
	set_show_unit_labels(not show_unit_labels)

func set_unit_visual_style_setting(style: String) -> void:
	if style not in ["letter", "enhanced", "style_a", "style_b", "classic"]:
		print("[SettingsService] Invalid visual style: %s" % style)
		return
	unit_visual_style = style
	_save_settings()
	print("[SettingsService] Unit visual style set to %s" % style)

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
	config.set_value("visual", "retro_mode", retro_mode)
	config.set_value("visual", "ui_scale", ui_scale)
	config.set_value("visual", "animation_speed", animation_speed)
	config.set_value("visual", "colorblind_mode", colorblind_mode)
	config.set_value("visual", "show_unit_labels", show_unit_labels)

	# Save/Load
	config.set_value("save_load", "pretty_print", save_files_pretty_print)
	config.set_value("save_load", "compression", save_files_compression)
	config.set_value("save_load", "save_measurements", save_measurements)
	config.set_value("save_load", "autosave_on_round_end", autosave_on_round_end)
	config.set_value("save_load", "autosave_on_phase_transition", autosave_on_phase_transition)

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
	retro_mode = config.get_value("visual", "retro_mode", false)
	ui_scale = config.get_value("visual", "ui_scale", 1.0)
	animation_speed = config.get_value("visual", "animation_speed", 1.0)
	colorblind_mode = config.get_value("visual", "colorblind_mode", "none")
	show_unit_labels = config.get_value("visual", "show_unit_labels", true)

	# Save/Load
	save_files_pretty_print = config.get_value("save_load", "pretty_print", true)
	save_files_compression = config.get_value("save_load", "compression", true)
	save_measurements = config.get_value("save_load", "save_measurements", false)
	autosave_on_round_end = config.get_value("save_load", "autosave_on_round_end", true)
	autosave_on_phase_transition = config.get_value("save_load", "autosave_on_phase_transition", false)

	print("[SettingsService] Settings loaded from %s" % SETTINGS_FILE_PATH)
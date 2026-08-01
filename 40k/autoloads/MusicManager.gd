extends Node

# MusicManager — background music + UI sound cues.
#
# Plays the procedurally-generated ambient beds (assets/audio/*.wav, made by
# tools/generate_audio.py — all original, no third-party licence) on loop,
# crossfading between the menu bed and the battle bed as the player moves
# between the main menu and a game. Music routes through the "Music" bus and
# UI cues through "SFX", so the existing Settings volume sliders finally
# control something.
#
# Autoloaded after SettingsService (which creates the buses). Silent under the
# scenario/benchmark harness and on the dummy audio driver.

const MENU_TRACK := "res://assets/audio/menu_theme.wav"
const BATTLE_TRACK := "res://assets/audio/battle_theme.wav"
const SFX := {
	"hover": "res://assets/audio/ui_hover.wav",
	"click": "res://assets/audio/ui_click.wav",
	"confirm": "res://assets/audio/ui_confirm.wav",
	"back": "res://assets/audio/ui_back.wav",
}

const FADE_TIME := 1.5
const MUSIC_HEADROOM_DB := -6.0  # beds sit under the UI, not over it

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active: AudioStreamPlayer      # currently-audible music player
var _sfx_player: AudioStreamPlayer
var _current_track := ""
var _fade_tween: Tween
var _enabled := true
var _sfx_streams := {}

func _ready() -> void:
	# No audio under the automated harness or a headless/dummy driver.
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if typeof(a) == TYPE_STRING and (a.begins_with("--scenario-file=") or a.begins_with("--ai-benchmark")):
			_enabled = false
	if AudioServer.get_bus_index("Music") == -1:
		_enabled = false
	if not _enabled:
		return

	_player_a = _make_music_player()
	_player_b = _make_music_player()
	_active = _player_a
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	add_child(_sfx_player)
	for key in SFX:
		var s = load(SFX[key])
		if s:
			_sfx_streams[key] = s

	# Follow scene changes: menu bed on MainMenu, battle bed in a game.
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_sync_to_current_scene")

func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p

func _load_looping(path: String) -> AudioStream:
	var stream = load(path)
	if stream is AudioStreamWAV:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		# loop_end is a FRAME index, not a sentinel — -1 makes the loop
		# zero-length and the bed stops instantly. Derive frames from the
		# stream's own length and mix rate so the whole track loops.
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream

func play_menu_music() -> void:
	_crossfade_to(MENU_TRACK)

func play_battle_music() -> void:
	_crossfade_to(BATTLE_TRACK)

func stop_music() -> void:
	if not _enabled:
		return
	_current_track = ""
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	for p in [_player_a, _player_b]:
		if p and p.playing:
			p.stop()

func _crossfade_to(track: String) -> void:
	if not _enabled or track == _current_track:
		return
	_current_track = track
	var stream = _load_looping(track)
	if stream == null:
		return
	var incoming := _player_b if _active == _player_a else _player_a
	var outgoing := _active
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(incoming, "volume_db", MUSIC_HEADROOM_DB, FADE_TIME)
	if outgoing and outgoing.playing:
		_fade_tween.tween_property(outgoing, "volume_db", -80.0, FADE_TIME)
		_fade_tween.chain().tween_callback(outgoing.stop)
	_active = incoming

func play_sfx(key: String) -> void:
	if not _enabled or not _sfx_streams.has(key):
		return
	_sfx_player.stream = _sfx_streams[key]
	_sfx_player.play()

# ---- scene tracking --------------------------------------------------------

func _sync_to_current_scene() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	_apply_for_scene(scene.name)

func _on_node_added(node: Node) -> void:
	# The root scene swaps wholesale on change_scene_to_*; catch the new root.
	if node.get_parent() == get_tree().root and node == get_tree().current_scene:
		call_deferred("_apply_for_scene", node.name)

func _apply_for_scene(scene_name: String) -> void:
	if "MainMenu" in scene_name:
		play_menu_music()
	elif "Main" in scene_name:
		play_battle_music()

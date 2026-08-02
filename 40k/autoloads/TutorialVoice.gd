extends Node

# TutorialVoice — the Ork narrator that reads the tutorial cards aloud.
#
# Clips are pre-rendered, not synthesised at runtime: tools/generate_tutorial_vo.py
# runs Piper + a SoX "ork" chain over the lesson files offline and writes
# assets/audio/vo/tutorial/<lesson>__<step>__<variant>.ogg plus
# data/tutorials/vo_manifest.json. This autoload only has to pick the right clip
# and play it, so there is no TTS dependency in the shipped game and no latency
# between the card appearing and the voice starting.
#
# Variants exist because the pad and keyboard bodies name different controls
# ("press I" vs "press the Y button"). A step whose two bodies read identically
# is generated once as "any"; lookup falls back to it.
#
# Wired from TutorialManager (_show_current_step / _complete_lesson / _teardown)
# rather than from the step_changed signal, because a mid-lesson device swap
# re-renders the card through refresh_prompt() WITHOUT changing the step index —
# and that swap is exactly when the spoken line has to change too.
#
# Routes through the "Voice" bus so Settings › Audio › Voice Volume controls it
# independently of music and UI cues.

const MANIFEST_PATH := "res://data/tutorials/vo_manifest.json"
const BUS := "Voice"

var _clips: Dictionary = {}          # clip_id -> manifest entry
var _player: AudioStreamPlayer
var _enabled := false                # set false by a missing manifest / dummy audio
# The clip belonging to the card on screen. Survives stop() — "Say It Again" has
# to work after the line has finished (or been cut), which is exactly when a
# player reaches for it.
var _current_clip := ""
# The clip already spoken UNPROMPTED for this card. Kept separate from "is the
# player still hearing it": a re-render must not restart a line the player has
# already sat through, and checking _player.playing instead would do just that
# for any re-render arriving after the audio ended.
var _auto_spoken := ""
var _last_missing := ""              # de-dupe the "no clip" log per step


func _ready() -> void:
	# NOT disabled under the windowed scenario harness, deliberately — unlike the
	# music beds, which have nothing to assert, the whole point of this autoload
	# is WHICH clip it picks, and a scenario cannot pin that against an autoload
	# that switches itself off when a scenario is what is running. Scenario runs
	# use the Dummy audio driver, so an enabled voice is silent there anyway.
	# The AI benchmark is excluded: it plays thousands of headless turns and never
	# shows a tutorial card, so the manifest read is pure waste.
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if typeof(a) == TYPE_STRING and a.begins_with("--ai-benchmark"):
			DebugLogger.info("TutorialVoice: disabled (AI benchmark)")
			return
	if not _load_manifest():
		return
	_player = AudioStreamPlayer.new()
	_player.name = "VoicePlayer"
	_player.bus = BUS if AudioServer.get_bus_index(BUS) != -1 else "Master"
	add_child(_player)
	_enabled = true
	DebugLogger.info("TutorialVoice: ready", {"clips": _clips.size(), "bus": _player.bus})


func _load_manifest() -> bool:
	if not FileAccess.file_exists(MANIFEST_PATH):
		DebugLogger.warn("TutorialVoice: no manifest at %s — voiceover off. Run "
			% MANIFEST_PATH + "tools/generate_tutorial_vo.py to build it.")
		return false
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		DebugLogger.warn("TutorialVoice: cannot open %s" % MANIFEST_PATH)
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		DebugLogger.warn("TutorialVoice: manifest is not a JSON object")
		return false
	var clips = parsed.get("clips", {})
	if typeof(clips) != TYPE_DICTIONARY or (clips as Dictionary).is_empty():
		DebugLogger.warn("TutorialVoice: manifest has no clips")
		return false
	_clips = clips
	return true


# ------------------------------------------------------------------- API ----

func is_available() -> bool:
	return _enabled


func is_speaking() -> bool:
	return _enabled and _player != null and _player.playing


func current_clip_id() -> String:
	return _current_clip


func clip_count() -> int:
	return _clips.size()


# Speak a step's card. `variant` is "kbm"/"pad"; falls back to the shared "any"
# clip when the step reads the same on both devices.
func speak_step(lesson_id: String, step_id: String, pad_active: bool) -> bool:
	var variant := "pad" if pad_active else "kbm"
	return _play(_resolve(lesson_id, step_id, variant))


func speak_summary(lesson_id: String) -> bool:
	return _play(_resolve(lesson_id, "_summary", "any"))


func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()


# Forget the card entirely — used when the tutorial itself goes away, so the
# next lesson does not inherit the last one's line.
func clear() -> void:
	stop()
	_current_clip = ""
	_auto_spoken = ""


# Re-play the line for the card on screen — the "Say It Again" button, and the
# reason a missed instruction never needs a lesson restart. Forced, so it works
# after the clip has finished or been cut.
func replay() -> bool:
	if not _enabled or _current_clip == "":
		return false
	return _play(_current_clip, true)


# Settings › Audio › Tutorial Voiceover. Turning it back ON speaks the card on
# screen straight away rather than staying silent until the next step — the
# player flipped the switch to hear the thing they are looking at, and nothing
# re-renders the card on a settings change.
func set_enabled(on: bool) -> void:
	if not on:
		stop()
		return
	if _current_clip != "":
		_play(_current_clip, true)


# ---------------------------------------------------------------- lookup ----

func _resolve(lesson_id: String, step_id: String, variant: String) -> String:
	for candidate in ["%s__%s__%s" % [lesson_id, step_id, variant],
			"%s__%s__any" % [lesson_id, step_id]]:
		if _clips.has(candidate):
			return candidate
	return ""


func _play(clip_id: String, force: bool = false) -> bool:
	if not _enabled:
		return false
	if not SettingsService.tutorial_voice_enabled:
		stop()
		return false
	if clip_id == "":
		return false
	# The same card can be re-rendered without being a new instruction (a device
	# swap that lands on a step whose two variants collapsed to one "any" clip).
	# Speaking again there would restart a line mid-sentence, or replay one the
	# player already heard — only an explicit replay() overrides this.
	if clip_id == _auto_spoken and not force:
		return true
	var entry = _clips.get(clip_id, {})
	var path := str(entry.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		if _last_missing != clip_id:
			_last_missing = clip_id
			DebugLogger.warn("TutorialVoice: clip file missing", {"clip": clip_id, "path": path})
		return false
	var stream = load(path)
	if stream == null:
		DebugLogger.warn("TutorialVoice: clip failed to load", {"clip": clip_id})
		return false
	_current_clip = clip_id
	_auto_spoken = clip_id
	_player.stream = stream
	_player.play()
	DebugLogger.debug("TutorialVoice: speaking", {"clip": clip_id, "seconds": entry.get("seconds", 0)})
	return true

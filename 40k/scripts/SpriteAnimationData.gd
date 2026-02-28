extends RefCounted
class_name SpriteAnimationData

# Holds frame data for a single named animation (e.g. "idle", "move", "attack", "death").
# Frames are Texture2D objects; playback is driven by TokenVisual._process().

var animation_name: String = "idle"
var frames: Array[Texture2D] = []
var fps: float = 4.0
var loop: bool = true

# Current playback state (per-instance, managed by TokenVisual)
var _current_frame: int = 0
var _frame_timer: float = 0.0


func _init(p_name: String = "idle", p_frames: Array[Texture2D] = [], p_fps: float = 4.0, p_loop: bool = true) -> void:
	animation_name = p_name
	frames = p_frames
	fps = p_fps
	loop = p_loop


func get_frame_count() -> int:
	return frames.size()


func get_current_texture() -> Texture2D:
	if frames.is_empty():
		return null
	return frames[clampi(_current_frame, 0, frames.size() - 1)]


func advance(delta: float) -> bool:
	# Advances the animation timer. Returns true if the frame changed.
	if frames.size() <= 1:
		return false

	_frame_timer += delta
	var frame_duration = 1.0 / fps
	if _frame_timer < frame_duration:
		return false

	_frame_timer -= frame_duration
	var old_frame = _current_frame
	_current_frame += 1

	if _current_frame >= frames.size():
		if loop:
			_current_frame = 0
		else:
			_current_frame = frames.size() - 1

	return _current_frame != old_frame


func reset() -> void:
	_current_frame = 0
	_frame_timer = 0.0


func is_finished() -> bool:
	# Only meaningful for non-looping animations
	if loop:
		return false
	return _current_frame >= frames.size() - 1

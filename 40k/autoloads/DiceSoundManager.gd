extends Node

# DiceSoundManager - Procedural dice roll sound effects
# Generates all sounds at runtime using AudioStreamWAV — no external assets needed.
# Sounds play on the "SFX" audio bus (set up by SettingsService).
#
# Sound types:
#   - roll_tick: short click for each cycling die frame during animation
#   - settle: percussive thud when a die lands on its final value
#   - critical_success: ascending chime for natural 6s
#   - critical_failure: low buzz for natural 1s
#   - result_success: brief positive tone when all dice finish (majority success)
#   - result_failure: brief negative tone when all dice finish (majority failure)

const SAMPLE_RATE := 22050
const SFX_BUS := "SFX"

# Cached AudioStreamWAV resources (generated once in _ready)
var _stream_roll_tick: AudioStreamWAV
var _stream_settle: AudioStreamWAV
var _stream_critical_success: AudioStreamWAV
var _stream_critical_failure: AudioStreamWAV
var _stream_result_success: AudioStreamWAV
var _stream_result_failure: AudioStreamWAV
# P3-126: Phase transition sound effects
var _stream_phase_transition: AudioStreamWAV
var _stream_phase_combat: AudioStreamWAV

# Pool of AudioStreamPlayer nodes for overlapping playback
var _player_pool: Array[AudioStreamPlayer] = []
const POOL_SIZE := 8
var _pool_index := 0

# Rate-limiting for rapid tick sounds
var _last_tick_time: float = 0.0
const MIN_TICK_INTERVAL := 0.04  # Max ~25 ticks/sec to avoid audio spam

func _ready() -> void:
	# Generate all sound streams procedurally
	_stream_roll_tick = _generate_roll_tick()
	_stream_settle = _generate_settle()
	_stream_critical_success = _generate_critical_success()
	_stream_critical_failure = _generate_critical_failure()
	_stream_result_success = _generate_result_success()
	_stream_result_failure = _generate_result_failure()
	# P3-126: Phase transition sounds
	_stream_phase_transition = _generate_phase_transition()
	_stream_phase_combat = _generate_phase_combat()

	# Create player pool
	for i in POOL_SIZE:
		var player = AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_player_pool.append(player)

	print("[DiceSoundManager] Ready — %d procedural streams generated, %d player pool" % [8, POOL_SIZE])

# ============================================================================
# Public API — called by DiceRollVisual
# ============================================================================

func play_roll_tick() -> void:
	"""Play a short click/tick sound during dice cycling animation."""
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_tick_time < MIN_TICK_INTERVAL:
		return
	_last_tick_time = now
	_play_stream(_stream_roll_tick, -8.0)  # Quieter for ticks

func play_settle() -> void:
	"""Play a percussive thud when a single die settles on its final value."""
	_play_stream(_stream_settle, -4.0)

func play_critical_success() -> void:
	"""Play an ascending chime for a natural 6 (critical hit)."""
	_play_stream(_stream_critical_success, -2.0)

func play_critical_failure() -> void:
	"""Play a low buzz for a natural 1 (fumble)."""
	_play_stream(_stream_critical_failure, -4.0)

func play_result_success() -> void:
	"""Play a brief positive tone when dice roll completes with good results."""
	_play_stream(_stream_result_success, -3.0)

func play_result_failure() -> void:
	"""Play a brief negative tone when dice roll completes with bad results."""
	_play_stream(_stream_result_failure, -3.0)

# ============================================================================
# P3-126: Phase Transition Sound API — called by PhaseTransitionBanner
# ============================================================================

func play_phase_transition() -> void:
	"""Play a brass-like fanfare whoosh for standard phase transitions."""
	_play_stream(_stream_phase_transition, -3.0)

func play_phase_combat() -> void:
	"""Play a more intense variant for combat phases (Shooting, Charge, Fight)."""
	_play_stream(_stream_phase_combat, -2.0)

# ============================================================================
# Playback
# ============================================================================

func _is_audio_muted() -> bool:
	var settings = Engine.get_main_loop().root.get_node_or_null("/root/SettingsService") if Engine.get_main_loop() else null
	return settings != null and settings.audio_muted

func _play_stream(stream: AudioStreamWAV, volume_db: float = 0.0) -> void:
	if not stream:
		return
	# Respect mute setting
	if _is_audio_muted():
		return

	var player = _player_pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE

	player.stream = stream
	player.volume_db = volume_db
	player.play()

# ============================================================================
# Procedural Sound Generation
# ============================================================================

func _generate_roll_tick() -> AudioStreamWAV:
	"""Short click — single cycle of noise with fast decay (~20ms)."""
	var duration := 0.02
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)  # 16-bit = 2 bytes per sample

	for i in samples:
		var t := float(i) / SAMPLE_RATE
		var envelope := maxf(0.0, 1.0 - t / duration)  # Linear decay
		# Mix a click (short burst of mid-frequency noise)
		var noise := randf_range(-1.0, 1.0)
		var click := sin(TAU * 2000.0 * t) * 0.5
		var sample_val := (noise * 0.3 + click * 0.7) * envelope
		var sample_int := clampi(int(sample_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_int)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream

func _generate_settle() -> AudioStreamWAV:
	"""Percussive thud — low frequency burst with fast decay (~60ms)."""
	var duration := 0.06
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / SAMPLE_RATE
		var envelope := maxf(0.0, 1.0 - t / duration) * maxf(0.0, 1.0 - t / duration)  # Squared decay
		# Low thud with some mid texture
		var low := sin(TAU * 120.0 * t) * 0.6
		var mid := sin(TAU * 400.0 * t) * 0.25
		var noise := randf_range(-1.0, 1.0) * 0.15
		var sample_val := (low + mid + noise) * envelope
		var sample_int := clampi(int(sample_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_int)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream

func _generate_critical_success() -> AudioStreamWAV:
	"""Ascending two-tone chime — bright and positive (~150ms)."""
	var duration := 0.15
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / SAMPLE_RATE
		var envelope := maxf(0.0, 1.0 - t / duration)
		# Two ascending tones: E5 (659Hz) then B5 (988Hz)
		var freq := 659.0 if t < 0.07 else 988.0
		var tone := sin(TAU * freq * t) * 0.5
		# Add a harmonic shimmer
		var harmonic := sin(TAU * freq * 2.0 * t) * 0.2
		var sample_val := (tone + harmonic) * envelope
		var sample_int := clampi(int(sample_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_int)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream

func _generate_critical_failure() -> AudioStreamWAV:
	"""Low descending buzz — ominous feeling (~120ms)."""
	var duration := 0.12
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / SAMPLE_RATE
		var envelope := maxf(0.0, 1.0 - t / duration)
		# Descending low tone with distortion
		var freq := lerpf(200.0, 80.0, t / duration)
		var tone := sin(TAU * freq * t) * 0.5
		# Square wave harmonics for buzzy feel
		var buzz: float = float(sign(sin(TAU * freq * 1.5 * t))) * 0.15
		var sample_val: float = (tone + buzz) * envelope
		var sample_int := clampi(int(sample_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_int)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream

func _generate_result_success() -> AudioStreamWAV:
	"""Brief positive confirmation — major chord arpeggio (~200ms)."""
	var duration := 0.2
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / SAMPLE_RATE
		var envelope := maxf(0.0, 1.0 - t / duration)
		# C major chord: C5(523), E5(659), G5(784) blended
		var c := sin(TAU * 523.0 * t) * 0.35
		var e := sin(TAU * 659.0 * t) * 0.3
		var g := sin(TAU * 784.0 * t) * 0.25
		var sample_val := (c + e + g) * envelope
		var sample_int := clampi(int(sample_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_int)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream

func _generate_result_failure() -> AudioStreamWAV:
	"""Brief negative tone — minor second dissonance (~180ms)."""
	var duration := 0.18
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / SAMPLE_RATE
		var envelope := maxf(0.0, 1.0 - t / duration)
		# Dissonant minor second: E4(330) + F4(349)
		var e := sin(TAU * 330.0 * t) * 0.4
		var f := sin(TAU * 349.0 * t) * 0.35
		var sample_val := (e + f) * envelope
		var sample_int := clampi(int(sample_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_int)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream

# P3-126: Phase transition sound generation

func _generate_phase_transition() -> AudioStreamWAV:
	"""Brass-like fanfare whoosh for standard phase transitions (~250ms).
	Uses layered sine tones with harmonics to create a short horn-like announcement."""
	var duration := 0.25
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / SAMPLE_RATE
		var norm_t := t / duration
		# Attack-sustain-release envelope: fast attack, brief sustain, smooth release
		var envelope: float
		if norm_t < 0.08:
			envelope = norm_t / 0.08  # Fast attack
		elif norm_t < 0.5:
			envelope = 1.0  # Sustain
		else:
			envelope = maxf(0.0, 1.0 - (norm_t - 0.5) / 0.5)  # Release
		# Brass-like layered tones: fundamental + overtones
		# G4 (392Hz) — regal, commanding
		var fundamental := sin(TAU * 392.0 * t) * 0.35
		# 2nd harmonic (octave) for brightness
		var h2 := sin(TAU * 784.0 * t) * 0.2
		# 3rd harmonic (fifth above octave) for brass character
		var h3 := sin(TAU * 1176.0 * t) * 0.1
		# Slight rising sweep for the "whoosh" feel
		var sweep_freq := lerpf(300.0, 450.0, norm_t)
		var sweep := sin(TAU * sweep_freq * t) * 0.15 * maxf(0.0, 1.0 - norm_t * 1.5)
		var sample_val := (fundamental + h2 + h3 + sweep) * envelope
		var sample_int := clampi(int(sample_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_int)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream

func _generate_phase_combat() -> AudioStreamWAV:
	"""Intense fanfare for combat phases (Shooting, Charge, Fight) (~300ms).
	Deeper, more aggressive with power-chord-like layering."""
	var duration := 0.3
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / SAMPLE_RATE
		var norm_t := t / duration
		# Attack-sustain-release envelope with sharper attack
		var envelope: float
		if norm_t < 0.05:
			envelope = norm_t / 0.05  # Very fast attack
		elif norm_t < 0.4:
			envelope = 1.0  # Sustain
		else:
			envelope = maxf(0.0, 1.0 - (norm_t - 0.4) / 0.6)  # Slower release
		# Power chord: root + fifth, lower and more aggressive
		# D4 (294Hz) — deep, martial
		var root := sin(TAU * 294.0 * t) * 0.35
		# A4 (440Hz) — the fifth
		var fifth := sin(TAU * 440.0 * t) * 0.25
		# Octave below for weight
		var sub := sin(TAU * 147.0 * t) * 0.2
		# 3rd harmonic for aggression
		var h3 := sin(TAU * 882.0 * t) * 0.1
		# Noise burst at the start for impact
		var noise_env := maxf(0.0, 1.0 - norm_t * 8.0)  # Fades fast
		var noise := randf_range(-1.0, 1.0) * 0.12 * noise_env
		var sample_val := (root + fifth + sub + h3 + noise) * envelope
		var sample_int := clampi(int(sample_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_int)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream

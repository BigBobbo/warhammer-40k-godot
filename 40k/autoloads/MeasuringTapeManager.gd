extends Node

# MeasuringTapeManager - Manages measurement lines for tactical distance checking
# Allows users to draw and persist multiple measurement lines on the board

signal measurement_added(measurement: Dictionary)
signal measurements_cleared()

var measurements: Array = []  # Array of measurement dictionaries
var is_measuring: bool = false
var measurement_start: Vector2 = Vector2.ZERO
var current_preview: Dictionary = {}  # Preview line while dragging
var save_measurements: bool = false  # Toggle for persistence

func _ready() -> void:
	# Initialize from settings
	if SettingsService:
		save_measurements = SettingsService.get_save_measurements()
		print("[MeasuringTapeManager] Initialized with save_persistence: ", save_measurements)
	else:
		print("[MeasuringTapeManager] Initialized (SettingsService not available)")

func start_measurement(start_pos: Vector2) -> void:
	is_measuring = true
	measurement_start = start_pos
	current_preview = {
		"from": start_pos,
		"to": start_pos,
		"distance": 0.0,
		"timestamp": Time.get_ticks_msec()
	}
	print("[MeasuringTapeManager] Started measurement at ", start_pos)

func update_measurement(current_pos: Vector2) -> void:
	if not is_measuring:
		return
	
	current_preview.to = current_pos
	current_preview.distance = Measurement.distance_inches(measurement_start, current_pos)

func complete_measurement(end_pos: Vector2) -> void:
	if not is_measuring:
		return
	
	var measurement = {
		"from": measurement_start,
		"to": end_pos,
		"distance": Measurement.distance_inches(measurement_start, end_pos),
		"timestamp": Time.get_ticks_msec()
	}
	
	measurements.append(measurement)
	emit_signal("measurement_added", measurement)
	print("[MeasuringTapeManager] Completed measurement: %.1f inches" % measurement.distance)
	
	is_measuring = false
	measurement_start = Vector2.ZERO
	current_preview = {}

func cancel_measurement() -> void:
	if not is_measuring:
		return
	
	is_measuring = false
	measurement_start = Vector2.ZERO
	current_preview = {}
	print("[MeasuringTapeManager] Measurement cancelled")

func clear_all_measurements() -> void:
	measurements.clear()
	emit_signal("measurements_cleared")
	print("[MeasuringTapeManager] All measurements cleared")

func get_save_data() -> Array:
	print("[MeasuringTapeManager] get_save_data called - persistence: %s, count: %d" % [save_measurements, measurements.size()])
	if not save_measurements or measurements.is_empty():
		return []
	
	var save_data = []
	for m in measurements:
		save_data.append({
			"from": {"x": m.from.x, "y": m.from.y},
			"to": {"x": m.to.x, "y": m.to.y},
			"distance": m.distance
		})
	
	print("[MeasuringTapeManager] Returning %d measurements for save" % save_data.size())
	return save_data

func load_save_data(data: Array) -> void:
	if data.is_empty():
		return
	
	measurements.clear()
	for m in data:
		measurements.append({
			"from": Vector2(m.from.x, m.from.y),
			"to": Vector2(m.to.x, m.to.y),
			"distance": m.distance,
			"timestamp": Time.get_ticks_msec()
		})
	
	emit_signal("measurement_added", {})  # Trigger redraw
	print("[MeasuringTapeManager] Loaded %d measurements from save" % measurements.size())

func set_save_persistence(enabled: bool) -> void:
	save_measurements = enabled
	print("[MeasuringTapeManager] Save persistence: ", enabled)

func get_measurement_count() -> int:
	return measurements.size()

# Limit maximum measurements for performance
const MAX_MEASUREMENTS = 10

func can_add_measurement() -> bool:
	return measurements.size() < MAX_MEASUREMENTS
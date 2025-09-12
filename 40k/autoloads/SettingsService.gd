extends Node

var px_per_inch: float = 40.0
var board_width_inches: float = 44.0
var board_height_inches: float = 60.0
var deployment_zone_depth_inches: float = 12.0

# Save/Load Settings
var save_files_pretty_print: bool = true  # Human-readable by default
var save_files_compression: bool = false  # Keep disabled for readability

# Measuring Tape Settings
var save_measurements: bool = false  # Whether to persist measurement lines in saves

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
	# Initialize StateSerializer with settings
	if StateSerializer:
		StateSerializer.set_pretty_print(save_files_pretty_print)
		StateSerializer.set_compression_enabled(save_files_compression)
	
	# Initialize MeasuringTapeManager with settings
	if MeasuringTapeManager:
		MeasuringTapeManager.set_save_persistence(save_measurements)

func get_board_width_px() -> float:
	return board_width_inches * px_per_inch

func get_board_height_px() -> float:
	return board_height_inches * px_per_inch

func get_deployment_zone_depth_px() -> float:
	return deployment_zone_depth_inches * px_per_inch
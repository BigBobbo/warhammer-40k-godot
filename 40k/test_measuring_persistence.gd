extends Node

# Test script to verify measuring tape persistence

func _ready():
	print("\n=== TESTING MEASURING TAPE PERSISTENCE ===\n")
	
	# Enable save persistence
	print("1. Enabling save persistence...")
	SettingsService.set_save_measurements(true)
	MeasuringTapeManager.set_save_persistence(true)
	print("   Persistence enabled: ", MeasuringTapeManager.save_measurements)
	
	# Create some test measurements
	print("\n2. Creating test measurements...")
	MeasuringTapeManager.start_measurement(Vector2(100, 100))
	MeasuringTapeManager.complete_measurement(Vector2(340, 100))  # 6 inches
	
	MeasuringTapeManager.start_measurement(Vector2(500, 500))
	MeasuringTapeManager.complete_measurement(Vector2(500, 740))  # 6 inches vertical
	
	print("   Created %d measurements" % MeasuringTapeManager.get_measurement_count())
	
	# Get save data
	print("\n3. Getting save data...")
	var save_data = MeasuringTapeManager.get_save_data()
	print("   Save data size: ", save_data.size())
	if not save_data.is_empty():
		print("   First measurement: ", save_data[0])
	
	# Simulate save
	print("\n4. Creating game snapshot...")
	var snapshot = GameState.create_snapshot()
	if snapshot.has("measuring_tape"):
		print("   ✓ Snapshot contains measuring_tape data")
		print("   Measurements in snapshot: ", snapshot["measuring_tape"].size())
	else:
		print("   ✗ Snapshot does NOT contain measuring_tape data!")
	
	# Clear measurements
	print("\n5. Clearing measurements...")
	MeasuringTapeManager.clear_all_measurements()
	print("   Current measurements: ", MeasuringTapeManager.get_measurement_count())
	
	# Load from snapshot
	print("\n6. Loading from snapshot...")
	GameState.load_from_snapshot(snapshot)
	print("   Measurements after load: ", MeasuringTapeManager.get_measurement_count())
	
	if MeasuringTapeManager.get_measurement_count() > 0:
		print("   ✓ PERSISTENCE WORKING!")
		for i in range(MeasuringTapeManager.measurements.size()):
			var m = MeasuringTapeManager.measurements[i]
			print("     Measurement %d: %.1f inches" % [i+1, m.distance])
	else:
		print("   ✗ PERSISTENCE NOT WORKING!")
	
	print("\n=== TEST COMPLETE ===\n")
	
	# Exit
	get_tree().quit()
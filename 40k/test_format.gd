extends Node

func _ready():
	# Wait for autoloads to initialize
	await get_tree().process_frame
	print("StateSerializer pretty_print status: ", StateSerializer.pretty_print)
	
	# Create test data and save it
	var test_state = {
		"_serialization": {"version": "1.0.0", "timestamp": Time.get_unix_time_from_system()},
		"meta": {"phase": 2, "turn_number": 1, "game_id": "test"}, 
		"units": {},
		"board": {},
		"players": {}
	}
	
	var serialized = StateSerializer.serialize_game_state(test_state)
	print("Serialized JSON preview (first 200 chars):")
	print(serialized.substr(0, 200))
	print("Contains newlines: ", serialized.contains("\n"))
	print("Contains tabs: ", serialized.contains("\t"))
	
	# Save to file for manual inspection
	var file = FileAccess.open("test_human_readable.json", FileAccess.WRITE)
	file.store_string(serialized)
	file.close()
	print("Test file saved as test_human_readable.json")
	
	get_tree().quit()


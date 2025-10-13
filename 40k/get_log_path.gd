extends Node

func _ready():
	if DebugLogger:
		print("====== LOG FILE LOCATION ======")
		print(DebugLogger.get_real_log_file_path())
		print("===============================")
	else:
		print("DebugLogger not found")
	get_tree().quit()

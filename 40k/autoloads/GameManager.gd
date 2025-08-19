extends Node

signal result_applied(result: Dictionary)
signal action_logged(log_text: String)

var action_history: Array = []

func apply_action(action: Dictionary) -> Dictionary:
	var result = process_action(action)
	if result["success"]:
		apply_result(result)
		action_history.append(action)
	return result

func process_action(action: Dictionary) -> Dictionary:
	match action["type"]:
		"DEPLOY_UNIT":
			return process_deploy_unit(action)
		_:
			return {"success": false, "error": "Unknown action type"}

func process_deploy_unit(action: Dictionary) -> Dictionary:
	var unit_id = action["unit_id"]
	var models = action["models"]
	var diffs = []
	
	for model in models:
		diffs.append({
			"op": "set",
			"path": "units.%s.models.%s.pos" % [unit_id, model["id"]],
			"value": model["pos"]
		})
	
	diffs.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": BoardState.UnitStatus.DEPLOYED
	})
	
	var unit_name = BoardState.units[unit_id]["meta"]["name"]
	var log_text = "Deployed %s (%d models) wholly within DZ." % [unit_name, models.size()]
	
	return {
		"success": true,
		"phase": "DEPLOYMENT",
		"diffs": diffs,
		"log_text": log_text
	}

func apply_result(result: Dictionary) -> void:
	if not result["success"]:
		return
	
	for diff in result["diffs"]:
		apply_diff(diff)
	
	if result.has("log_text"):
		emit_signal("action_logged", result["log_text"])
	
	emit_signal("result_applied", result)

func apply_diff(diff: Dictionary) -> void:
	var op = diff["op"]
	var path = diff["path"]
	var value = diff.get("value", null)
	
	match op:
		"set":
			set_value_at_path(path, value)

func set_value_at_path(path: String, value) -> void:
	var parts = path.split(".")
	if parts.is_empty():
		return
	
	var current = BoardState
	for i in range(parts.size() - 1):
		var part = parts[i]
		if current is Node:
			if part in current:
				current = current.get(part)
			else:
				return
		elif current is Dictionary:
			if current.has(part):
				current = current[part]
			else:
				return
		elif current is Array:
			var index = part.to_int()
			if index >= 0 and index < current.size():
				current = current[index]
			else:
				return
	
	var final_key = parts[-1]
	if current is Dictionary:
		current[final_key] = value
	elif current is Array:
		var index = final_key.to_int()
		if index >= 0 and index < current.size():
			current[index] = value
	elif current is Node:
		if final_key in current:
			current.set(final_key, value)

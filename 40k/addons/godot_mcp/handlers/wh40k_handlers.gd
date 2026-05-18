extends RefCounted

# WH40K-specific MCP tools.
#
# These commands assume the game's autoloads are present:
#   GameState, PhaseManager, TurnManager, RulesEngine, BoardState
#
# When an autoload is missing (e.g. the addon is enabled in another project)
# the handlers respond with a structured error rather than crashing.

var host: Node = null


# --- Board / overall state --------------------------------------------

func get_board_state(_params: Dictionary) -> Dictionary:
	var gs := _autoload("GameState")
	var pm := _autoload("PhaseManager")
	var tm := _autoload("TurnManager")
	if gs == null:
		return {"status": "error", "message": "GameState autoload not found"}

	var state: Dictionary = gs.state
	var meta: Dictionary = state.get("meta", {})
	var phase_name := _phase_name(meta.get("phase", -1))

	var summary := {
		"status": "ok",
		"phase": phase_name,
		"phase_id": meta.get("phase", -1),
		"battle_round": meta.get("battle_round", 0),
		"turn_number": meta.get("turn_number", 0),
		"active_player": meta.get("active_player", 0),
		"deployment_type": meta.get("deployment_type", ""),
		"players": {},
		"units": [],
		"board_size": state.get("board", {}).get("size", {}),
		"objectives": state.get("board", {}).get("objectives", []),
	}

	for pid in state.get("players", {}).keys():
		var p: Dictionary = state["players"][pid]
		summary["players"][str(pid)] = {
			"cp": p.get("cp", 0),
			"vp": p.get("vp", 0),
			"primary_vp": p.get("primary_vp", 0),
			"secondary_vp": p.get("secondary_vp", 0),
		}

	for uid in state.get("units", {}).keys():
		var unit: Dictionary = state["units"][uid]
		summary["units"].append(_unit_summary(uid, unit))

	if pm and pm.has_method("get_available_actions"):
		summary["available_actions"] = pm.get_available_actions()
	if tm and tm.has_method("get_game_status"):
		summary["game_status"] = tm.get_game_status()

	return summary


func get_unit_details(params: Dictionary) -> Dictionary:
	var gs := _autoload("GameState")
	if gs == null:
		return {"status": "error", "message": "GameState autoload not found"}
	var unit_id: String = params.get("unit_id", "")
	if unit_id == "" and params.has("unit_name"):
		unit_id = _resolve_unit_id(gs, params["unit_name"])
	if unit_id == "":
		return {"status": "error", "message": "Missing 'unit_id' or 'unit_name'"}
	var unit: Dictionary = gs.get_unit(unit_id) if gs.has_method("get_unit") else gs.state["units"].get(unit_id, {})
	if unit.is_empty():
		return {"status": "error", "message": "Unit not found: %s" % unit_id}

	var details := _unit_summary(unit_id, unit)
	details["meta"] = unit.get("meta", {})
	details["models"] = unit.get("models", [])
	details["weapons"] = unit.get("weapons", [])
	details["abilities"] = unit.get("abilities", [])
	details["status_effects"] = unit.get("status_effects", [])
	details["embarked_in"] = unit.get("embarked_in", null)
	details["attached_to"] = unit.get("attached_to", null)
	details["raw"] = unit
	return {"status": "ok", "unit": details}


func list_units(params: Dictionary) -> Dictionary:
	var gs := _autoload("GameState")
	if gs == null:
		return {"status": "error", "message": "GameState autoload not found"}
	var owner_filter = params.get("owner", null)
	var include_destroyed: bool = params.get("include_destroyed", false)
	var out := []
	for uid in gs.state.get("units", {}).keys():
		var unit: Dictionary = gs.state["units"][uid]
		if owner_filter != null and int(unit.get("owner", 0)) != int(owner_filter):
			continue
		if not include_destroyed and gs.has_method("is_unit_destroyed") and gs.is_unit_destroyed(uid):
			continue
		out.append(_unit_summary(uid, unit))
	return {"status": "ok", "units": out, "count": out.size()}


# --- Phase control ----------------------------------------------------

func get_current_phase(_params: Dictionary) -> Dictionary:
	var gs := _autoload("GameState")
	var pm := _autoload("PhaseManager")
	if gs == null:
		return {"status": "error", "message": "GameState autoload not found"}
	var phase_id: int = gs.state.get("meta", {}).get("phase", -1)
	var info := {
		"status": "ok",
		"phase_id": phase_id,
		"phase": _phase_name(phase_id),
		"active_player": gs.state.get("meta", {}).get("active_player", 0),
		"turn_number": gs.state.get("meta", {}).get("turn_number", 0),
		"battle_round": gs.state.get("meta", {}).get("battle_round", 0),
	}
	if pm and pm.has_method("get_available_actions"):
		info["available_actions"] = pm.get_available_actions()
	return info


func get_legal_actions(_params: Dictionary) -> Dictionary:
	# Return the list of contextually-valid actions the active player can take
	# right now. Each phase implements get_available_actions() returning rich
	# dicts (type, unit_id, description, etc.) — exactly the shapes that
	# dispatch_action expects. This lets the agent enumerate legal moves
	# instead of guessing action shapes and getting validation rejections.
	var pm := _autoload("PhaseManager")
	var gs := _autoload("GameState")
	if pm == null or gs == null:
		return {"status": "error", "message": "PhaseManager or GameState not found"}
	var phase_id: int = gs.state.get("meta", {}).get("phase", -1)
	var actions: Array = []
	if pm.has_method("get_available_actions"):
		actions = pm.get_available_actions()
	return {
		"status": "ok",
		"phase": _phase_name(phase_id),
		"phase_id": phase_id,
		"active_player": gs.state.get("meta", {}).get("active_player", 0),
		"count": actions.size(),
		"actions": _to_serializable(actions),
	}


func advance_phase(_params: Dictionary) -> Dictionary:
	var pm := _autoload("PhaseManager")
	if pm == null:
		return {"status": "error", "message": "PhaseManager autoload not found"}
	if pm.has_method("advance_to_next_phase"):
		pm.advance_to_next_phase()
	else:
		return {"status": "error", "message": "PhaseManager has no advance_to_next_phase()"}
	return get_current_phase({})


func transition_to_phase(params: Dictionary) -> Dictionary:
	var pm := _autoload("PhaseManager")
	var gs := _autoload("GameState")
	if pm == null or gs == null:
		return {"status": "error", "message": "PhaseManager or GameState not found"}
	var phase_arg = params.get("phase", null)
	if phase_arg == null:
		return {"status": "error", "message": "Missing 'phase'"}
	var phase_id := -1
	if typeof(phase_arg) == TYPE_INT or typeof(phase_arg) == TYPE_FLOAT:
		phase_id = int(phase_arg)
	else:
		phase_id = _phase_from_name(str(phase_arg))
	if phase_id < 0:
		return {"status": "error", "message": "Unknown phase: %s" % str(phase_arg)}
	pm.transition_to_phase(phase_id)
	return get_current_phase({})


# --- Unit interaction --------------------------------------------------

func select_unit(params: Dictionary) -> Dictionary:
	# Find the unit's token in the running scene and click it. This routes
	# through the actual UI rather than poking GameState directly, so any
	# selection logic / signals fire normally.
	var gs := _autoload("GameState")
	if gs == null:
		return {"status": "error", "message": "GameState autoload not found"}
	var unit_id: String = params.get("unit_id", "")
	if unit_id == "" and params.has("unit_name"):
		unit_id = _resolve_unit_id(gs, params["unit_name"])
	if unit_id == "":
		return {"status": "error", "message": "Missing 'unit_id' or 'unit_name'"}

	var token := _find_unit_token(unit_id)
	if token == null:
		return {
			"status": "error",
			"message": "No token found for unit %s. Token discovery looks for nodes named '%s' or with `unit_id` matching." % [unit_id, unit_id],
		}

	var screen_pos := _node2d_to_screen(token)
	if screen_pos == Vector2.INF:
		return {"status": "error", "message": "Could not project unit token to screen"}

	# Synthesize a click via Input — same path a human takes.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen_pos
	press.global_position = screen_pos
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)
	if host and host.get_tree():
		await host.get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = screen_pos
	release.global_position = screen_pos
	release.pressed = false
	Input.parse_input_event(release)
	if host and host.get_tree():
		await host.get_tree().process_frame

	var unit: Dictionary = gs.get_unit(unit_id) if gs.has_method("get_unit") else gs.state["units"].get(unit_id, {})
	return {
		"status": "ok",
		"unit_id": unit_id,
		"screen_position": [screen_pos.x, screen_pos.y],
		"unit": _unit_summary(unit_id, unit),
	}


# --- Action dispatch (movement / shooting / etc) ----------------------

func dispatch_action(params: Dictionary) -> Dictionary:
	# Sends a phase action through PhaseManager's current phase instance via
	# BasePhase.execute_action(), which is the same wrapper the UI uses:
	# validate -> process_action -> PhaseManager.apply_state_changes ->
	# refresh phase snapshot -> emit `action_taken`. Calling `process_action`
	# directly skips diff application and silently corrupts phase state.
	var pm := _autoload("PhaseManager")
	if pm == null:
		return {"status": "error", "message": "PhaseManager autoload not found"}
	var current = pm.get_current_phase_instance() if pm.has_method("get_current_phase_instance") else null
	if current == null:
		return {"status": "error", "message": "No active phase instance"}
	var action: Dictionary = params.get("action", {})
	if typeof(action) != TYPE_DICTIONARY or action.is_empty():
		return {"status": "error", "message": "Missing 'action' dict"}

	# JSON has no Vector2 so callers send positions as `[x, y]` arrays. Convert
	# the well-known position-shaped fields to Vector2 before phases see them
	# (typed `position: Vector2` parameters won't auto-coerce from Array and
	# silently fail validation).
	action = _normalize_action_positions(action)

	# Prefer execute_action when available (BasePhase). It returns the
	# process_action result on success, or {success: false, errors: [...]} on
	# validation failure — surface either as a structured response.
	if current.has_method("execute_action"):
		var result = current.execute_action(action)
		if typeof(result) == TYPE_DICTIONARY and result.get("success", true) == false:
			return {
				"status": "error",
				"message": "Phase rejected action: %s" % str(result.get("errors", [])),
				"result": _to_serializable(result),
			}
		return {"status": "ok", "result": _to_serializable(result)}

	# Fallback for phases that don't extend BasePhase: validate + process,
	# but note that diffs won't be applied to GameState in this branch.
	if current.has_method("validate_action"):
		var validation = current.validate_action(action)
		if typeof(validation) == TYPE_DICTIONARY and validation.get("valid", true) == false:
			return {
				"status": "error",
				"message": "Phase rejected action: %s" % str(validation.get("errors", [])),
				"validation": validation,
			}
	if current.has_method("process_action"):
		var result = current.process_action(action)
		return {"status": "ok", "result": _to_serializable(result)}
	return {"status": "error", "message": "Active phase has no execute_action() or process_action()"}


func _normalize_action_positions(action: Dictionary) -> Dictionary:
	# Convert JSON-friendly `[x, y]` arrays into Vector2 for the action fields
	# phases declare with Vector2 types. Returns a shallow copy to avoid
	# mutating the caller's dict.
	var out: Dictionary = action.duplicate(true)
	# Single-position fields
	for key in ["position", "destination", "dest", "target_position", "stage_position"]:
		if out.has(key):
			var v = _coerce_vector2(out[key])
			if v != null:
				out[key] = v
	# Array-of-positions fields
	if out.has("model_positions") and typeof(out["model_positions"]) == TYPE_ARRAY:
		var positions: Array = out["model_positions"]
		var converted: Array = []
		for p in positions:
			if p == null:
				converted.append(null)
			else:
				var v = _coerce_vector2(p)
				converted.append(v if v != null else p)
		out["model_positions"] = converted

	# movements dict — used by SWEEPING_ADVANCE, CONSOLIDATE, PILE_IN, etc.
	# Each entry is {model_index: position}; positions need Vector2 conversion.
	if out.has("movements") and typeof(out["movements"]) == TYPE_DICTIONARY:
		var movements: Dictionary = out["movements"]
		var converted_movements: Dictionary = {}
		for model_idx in movements:
			var v = _coerce_vector2(movements[model_idx])
			converted_movements[model_idx] = v if v != null else movements[model_idx]
		out["movements"] = converted_movements

	# #361: per_model_paths inside payload — used by APPLY_CHARGE_MOVE,
	# APPLY_HEROIC_INTERVENTION_MOVE, STAGE_MODEL_MOVE, etc. Each entry is a
	# {model_id: [pos, pos, ...]} dict; positions need Vector2 conversion or
	# Measurement.distance_polyline_px silently sums to 0.
	if out.has("payload") and typeof(out["payload"]) == TYPE_DICTIONARY:
		var payload: Dictionary = out["payload"]
		if payload.has("per_model_paths") and typeof(payload["per_model_paths"]) == TYPE_DICTIONARY:
			var paths: Dictionary = payload["per_model_paths"]
			var converted_paths: Dictionary = {}
			for model_id in paths:
				var path = paths[model_id]
				if typeof(path) == TYPE_ARRAY:
					var converted_path: Array = []
					for p in path:
						var v = _coerce_vector2(p)
						converted_path.append(v if v != null else p)
					converted_paths[model_id] = converted_path
				else:
					converted_paths[model_id] = path
			payload["per_model_paths"] = converted_paths
			out["payload"] = payload
	return out


func _coerce_vector2(value):
	# Accept Vector2 as-is; convert [x, y] arrays or {"x":_, "y":_} dicts.
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		var x = value[0]
		var y = value[1]
		if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and (typeof(y) == TYPE_INT or typeof(y) == TYPE_FLOAT):
			return Vector2(float(x), float(y))
	if typeof(value) == TYPE_DICTIONARY and value.has("x") and value.has("y"):
		var x = value["x"]
		var y = value["y"]
		if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and (typeof(y) == TYPE_INT or typeof(y) == TYPE_FLOAT):
			return Vector2(float(x), float(y))
	return null


func move_unit_to(params: Dictionary) -> Dictionary:
	# Convenience wrapper: build a STAGE_MODEL_MOVE / move action against
	# MovementPhase. Phase action shape is project-specific; this dispatches
	# whichever the project's MovementPhase expects via dispatch_action with
	# fallback heuristics.
	var unit_id: String = params.get("unit_id", "")
	if unit_id == "":
		return {"status": "error", "message": "Missing 'unit_id'"}
	var dest_x = params.get("dest_x", null)
	var dest_y = params.get("dest_y", null)
	var model_id = params.get("model_id", null)
	if dest_x == null or dest_y == null:
		return {"status": "error", "message": "Missing 'dest_x' or 'dest_y'"}

	# Hand off to dispatch_action with a movement-shaped payload. Projects
	# using a different action shape can call dispatch_action directly.
	var action := {
		"type": "MOVE_UNIT",
		"unit_id": unit_id,
		"dest": [float(dest_x), float(dest_y)],
	}
	if model_id != null:
		action["model_id"] = model_id
	return dispatch_action({"action": action})


# --- Helpers ----------------------------------------------------------

func _autoload(name: String) -> Node:
	if host == null or host.get_tree() == null:
		return null
	return host.get_tree().root.get_node_or_null(name)


func _phase_name(phase_id) -> String:
	# Mirrors GameStateData.Phase enum order.
	var names := [
		"FORMATIONS", "DEPLOYMENT", "REDEPLOYMENT", "ROLL_OFF",
		"SCOUT", "SCOUT_MOVES", "COMMAND", "MOVEMENT", "SHOOTING",
		"CHARGE", "FIGHT", "SCORING", "MORALE",
	]
	var i := int(phase_id)
	if i < 0 or i >= names.size():
		return "UNKNOWN(%d)" % i
	return names[i]


func _phase_from_name(name: String) -> int:
	var upper := name.to_upper()
	var names := [
		"FORMATIONS", "DEPLOYMENT", "REDEPLOYMENT", "ROLL_OFF",
		"SCOUT", "SCOUT_MOVES", "COMMAND", "MOVEMENT", "SHOOTING",
		"CHARGE", "FIGHT", "SCORING", "MORALE",
	]
	return names.find(upper)


func _unit_summary(uid: String, unit: Dictionary) -> Dictionary:
	var meta: Dictionary = unit.get("meta", {})
	var models: Array = unit.get("models", [])
	var alive_models := 0
	var total_wounds := 0
	var current_wounds := 0
	for m in models:
		if m.get("alive", true):
			alive_models += 1
		total_wounds += int(m.get("wounds", 0))
		current_wounds += int(m.get("current_wounds", m.get("wounds", 0)))
	return {
		"id": uid,
		"name": meta.get("display_name", meta.get("name", uid)),
		"owner": unit.get("owner", 0),
		"status": unit.get("status", -1),
		"flags": unit.get("flags", {}),
		"models_total": models.size(),
		"models_alive": alive_models,
		"wounds_total": total_wounds,
		"wounds_current": current_wounds,
	}


func _resolve_unit_id(gs: Node, target) -> String:
	# Accept either an exact id match or a case-insensitive display name match.
	var query := str(target)
	if gs.state["units"].has(query):
		return query
	var lower := query.to_lower()
	for uid in gs.state["units"].keys():
		var unit: Dictionary = gs.state["units"][uid]
		var name: String = unit.get("meta", {}).get("display_name", unit.get("meta", {}).get("name", uid))
		if str(name).to_lower() == lower:
			return uid
	return ""


func _find_unit_token(unit_id: String) -> Node2D:
	if host == null or host.get_tree() == null:
		return null
	var tree := host.get_tree()
	var roots := [tree.current_scene, tree.root]
	for r in roots:
		if r == null:
			continue
		var found := _search_node_by_unit_id(r, unit_id)
		if found:
			return found
	return null


func _search_node_by_unit_id(node: Node, unit_id: String) -> Node2D:
	if node is Node2D:
		# Match by exact name first (TokenLayer children are commonly named after unit_id).
		if node.name == unit_id:
			return node
		# Match by `unit_id` script property if present.
		if "unit_id" in node and str(node.get("unit_id")) == unit_id:
			return node
		if node.has_meta("unit_id") and str(node.get_meta("unit_id")) == unit_id:
			return node
	for child in node.get_children():
		var found := _search_node_by_unit_id(child, unit_id)
		if found:
			return found
	return null


func _node2d_to_screen(node: Node2D) -> Vector2:
	# Convert a Node2D's global position into the viewport's screen-space
	# coordinates (post-camera-transform).
	var viewport := node.get_viewport()
	if viewport == null:
		return Vector2.INF
	var canvas_xform := viewport.get_canvas_transform()
	return canvas_xform * node.global_position


func _to_serializable(value, _depth: int = 0):
	if _depth > 40:
		return "<MAX_DEPTH>"
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_DICTIONARY:
			var out := {}
			for k in value.keys():
				out[str(k)] = _to_serializable(value[k], _depth + 1)
			return out
		TYPE_ARRAY:
			var out_arr := []
			for v in value:
				out_arr.append(_to_serializable(v, _depth + 1))
			return out_arr
		TYPE_OBJECT:
			if value == null:
				return null
			return "<%s>" % value.get_class()
		_:
			return value

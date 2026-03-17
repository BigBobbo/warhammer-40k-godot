extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# TransportManager - Manages embark/disembark operations for transport units
# This autoload handles all transport-related logic and validation
# P3-32: Enhanced with MEGA ARMOUR capacity multipliers, JUMP PACK exclusions,
#         and destroyed transport handling (emergency disembark)

signal embark_requested(transport_id: String, unit_id: String)
signal disembark_requested(transport_id: String, unit_id: String)
signal embark_completed(transport_id: String, unit_id: String)
signal disembark_completed(unit_id: String)
signal transport_destroyed(transport_id: String, embarked_unit_ids: Array, results: Dictionary)

func _ready() -> void:
	print("TransportManager initialized")

# Check if a unit can embark into a transport
func can_embark(unit_id: String, transport_id: String) -> Dictionary:
	var unit = GameState.get_unit(unit_id)
	var transport = GameState.get_unit(transport_id)

	# Check if unit exists
	if not unit:
		return {"valid": false, "reason": "Unit not found"}

	# Check if transport exists and is a transport
	if not transport:
		return {"valid": false, "reason": "Transport not found"}

	if not transport.has("transport_data"):
		return {"valid": false, "reason": "Not a transport unit"}

	# Check if unit is already embarked
	if unit.get("embarked_in", null) != null:
		return {"valid": false, "reason": "Unit is already embarked"}

	# P3-32: Check excluded keywords (e.g., JUMP PACK cannot embark in Battlewagon)
	var excluded_keywords = transport.transport_data.get("excluded_keywords", [])
	if excluded_keywords.size() > 0 and _has_any_excluded_keyword(unit, excluded_keywords):
		return {"valid": false, "reason": "Unit has excluded keyword (%s cannot be transported)" % str(excluded_keywords)}

	# Check capacity (P3-32: now uses capacity multipliers for MEGA ARMOUR etc.)
	var current_count = _get_embarked_model_count(transport_id)
	var unit_model_count = _get_unit_capacity_cost(unit, transport)

	if current_count + unit_model_count > transport.transport_data.capacity:
		return {"valid": false, "reason": "Insufficient capacity (%d/%d)" % [current_count + unit_model_count, transport.transport_data.capacity]}

	# Check keywords if specified
	if transport.transport_data.has("capacity_keywords") and transport.transport_data.capacity_keywords.size() > 0:
		if not _has_required_keywords(unit, transport.transport_data.capacity_keywords):
			return {"valid": false, "reason": "Unit type cannot embark (requires %s keywords)" % str(transport.transport_data.capacity_keywords)}

	# Check if already disembarked this phase
	if unit.get("disembarked_this_phase", false):
		return {"valid": false, "reason": "Unit already disembarked this phase"}

	return {"valid": true}

# Check if a unit can disembark from its transport
func can_disembark(unit_id: String) -> Dictionary:
	var unit = GameState.get_unit(unit_id)
	print("TransportManager: can_disembark(%s) — unit found: %s" % [unit_id, str(unit != null and not unit.is_empty())])

	if not unit:
		print("TransportManager: can_disembark — unit not found in live GameState")
		return {"valid": false, "reason": "Unit not found"}

	var embarked_in = unit.get("embarked_in", null)
	print("TransportManager: can_disembark — unit embarked_in (live state): %s" % str(embarked_in))
	if not embarked_in:
		return {"valid": false, "reason": "Unit is not embarked"}

	var transport = GameState.get_unit(embarked_in)
	if not transport:
		print("TransportManager: can_disembark — transport %s not found in live GameState" % str(embarked_in))
		return {"valid": false, "reason": "Transport not found"}

	# Check if transport has advanced or fell back
	var transport_flags = transport.get("flags", {})
	print("TransportManager: can_disembark — transport flags: %s" % str(transport_flags))
	if transport_flags.get("advanced", false):
		return {"valid": false, "reason": "Cannot disembark from transport that Advanced"}

	if transport_flags.get("fell_back", false):
		return {"valid": false, "reason": "Cannot disembark from transport that Fell Back"}

	return {"valid": true}

# Embark a unit into a transport
func embark_unit(unit_id: String, transport_id: String) -> void:
	var validation = can_embark(unit_id, transport_id)
	if not validation.valid:
		print("Cannot embark: ", validation.reason)
		return

	# Directly modify GameState since we're an autoload
	var unit = GameState.get_unit(unit_id)
	var transport = GameState.get_unit(transport_id)

	# Set embarked status on unit
	unit["embarked_in"] = transport_id

	# Add unit to transport's embarked list
	if not transport.transport_data.has("embarked_units"):
		transport.transport_data["embarked_units"] = []
	transport.transport_data.embarked_units.append(unit_id)

	# Update GameState directly
	GameState.state.units[unit_id] = unit
	GameState.state.units[transport_id] = transport

	emit_signal("embark_completed", transport_id, unit_id)
	print("Unit %s embarked in transport %s" % [unit_id, transport_id])

# Disembark a unit from its transport at specified positions
func disembark_unit(unit_id: String, positions: Array) -> void:
	var unit = GameState.get_unit(unit_id)
	if not unit or not unit.get("embarked_in", null):
		print("Cannot disembark: unit not embarked")
		return

	var transport_id = unit.embarked_in
	var transport = GameState.get_unit(transport_id)
	if not transport:
		print("Cannot disembark: transport not found")
		return

	# Update positions for all models
	for i in range(min(positions.size(), unit.models.size())):
		if unit.models[i].alive:
			unit.models[i].position = {"x": positions[i].x, "y": positions[i].y}

	# Clear embark status
	unit["embarked_in"] = null
	unit["disembarked_this_phase"] = true

	# Ensure unit status is DEPLOYED
	unit["status"] = GameStateData.UnitStatus.DEPLOYED

	# Remove from transport's embarked units list
	var embarked_units = transport.transport_data.embarked_units.duplicate()
	embarked_units.erase(unit_id)
	transport.transport_data["embarked_units"] = embarked_units

	# Apply movement restrictions if transport has already moved
	if not unit.has("flags"):
		unit["flags"] = {}

	if transport.get("flags", {}).get("moved", false):
		unit.flags["cannot_move"] = true
		unit.flags["cannot_charge"] = true
		print("Transport has moved - disembarked unit cannot move or charge")
	else:
		# Ensure flags are clear if transport hasn't moved
		unit.flags["cannot_move"] = false
		unit.flags["cannot_charge"] = false
		print("Transport hasn't moved - disembarked unit can move normally")

	# Update GameState directly
	GameState.state.units[unit_id] = unit
	GameState.state.units[transport_id] = transport

	emit_signal("disembark_completed", unit_id)
	print("Unit %s disembarked from transport %s" % [unit_id, transport_id])

# P3-32: Get the capacity cost of a unit accounting for capacity multipliers
# (e.g., MEGA ARMOUR models count as 2 spaces each)
func _get_unit_capacity_cost(unit: Dictionary, transport: Dictionary) -> int:
	var multipliers = transport.transport_data.get("capacity_multipliers", {})
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var cost = 0

	if unit.has("models"):
		for model in unit.models:
			if model.get("alive", true):
				var model_cost = 1
				# Check if any keyword on this unit matches a capacity multiplier
				for kw in multipliers:
					if kw in unit_keywords:
						model_cost = multipliers[kw]
						break
				cost += model_cost

	return cost

# Get total number of models currently embarked in a transport (capacity-weighted)
func _get_embarked_model_count(transport_id: String) -> int:
	var transport = GameState.get_unit(transport_id)
	if not transport or not transport.has("transport_data"):
		return 0

	var count = 0
	for embarked_id in transport.transport_data.embarked_units:
		var unit = GameState.get_unit(embarked_id)
		if unit:
			count += _get_unit_capacity_cost(unit, transport)

	return count

# MA-24: Get transport slot count for a single model based on its profile
func _get_model_transport_slots(unit: Dictionary, model: Dictionary) -> int:
	var model_type = model.get("model_type", null)
	if model_type == null or model_type == "":
		return 1
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if model_profiles.is_empty():
		return 1
	var profile = model_profiles.get(model_type, {})
	return int(profile.get("transport_slots", 1))

# MA-24: Get total transport slot count for alive models in a unit (slot-aware)
func _get_alive_model_count(unit: Dictionary) -> int:
	var count = 0
	if unit.has("models"):
		var has_profiles = unit.get("meta", {}).get("model_profiles", {}).size() > 0
		for model in unit.models:
			if model.get("alive", true):
				if has_profiles:
					count += _get_model_transport_slots(unit, model)
				else:
					count += 1
	return count

# Check if unit has all required keywords
func _has_required_keywords(unit: Dictionary, required_keywords: Array) -> bool:
	if not unit.has("meta") or not unit.meta.has("keywords"):
		return false

	var unit_keywords = unit.meta.keywords
	for keyword in required_keywords:
		if not keyword in unit_keywords:
			return false

	return true

# P3-32: Check if unit has any excluded keywords (e.g., JUMP PACK)
func _has_any_excluded_keyword(unit: Dictionary, excluded_keywords: Array) -> bool:
	if not unit.has("meta") or not unit.meta.has("keywords"):
		return false

	var unit_keywords = unit.meta.keywords
	for excl_kw in excluded_keywords:
		if excl_kw in unit_keywords:
			print("TransportManager: Unit has excluded keyword '%s'" % excl_kw)
			return true
	return false

# Get available units that can embark in a transport
func get_embarkable_units(transport_id: String, player: int) -> Array:
	var embarkable = []
	var transport = GameState.get_unit(transport_id)

	if not transport or not transport.has("transport_data"):
		return embarkable

	# Get all units for the player
	for unit_id in GameState.state.units:
		var unit = GameState.state.units[unit_id]
		if unit.owner != player:
			continue

		# Skip transports themselves
		if unit.has("transport_data"):
			continue

		# Skip already embarked units
		if unit.get("embarked_in", null) != null:
			continue

		# Check if this unit can embark
		var validation = can_embark(unit_id, transport_id)
		if validation.valid:
			embarkable.append(unit)

	return embarkable

# Get units currently embarked in a transport
func get_embarked_units(transport_id: String) -> Array:
	var transport = GameState.get_unit(transport_id)
	if not transport or not transport.has("transport_data"):
		return []

	var embarked = []
	for unit_id in transport.transport_data.embarked_units:
		var unit = GameState.get_unit(unit_id)
		if unit:
			embarked.append(unit)

	return embarked

# Check if a transport has firing deck capability
func has_firing_deck(transport_id: String) -> bool:
	var transport = GameState.get_unit(transport_id)
	if not transport or not transport.has("transport_data"):
		return false

	return transport.transport_data.get("firing_deck", 0) > 0

# Get firing deck capacity
func get_firing_deck_capacity(transport_id: String) -> int:
	var transport = GameState.get_unit(transport_id)
	if not transport or not transport.has("transport_data"):
		return 0

	return transport.transport_data.get("firing_deck", 0)

# P3-32: Resolve destroyed transport — embarked units must emergency disembark
# Per 10e rules: Roll D6 for each disembarking model. On a 1, one model is destroyed.
# Disembarked units cannot declare charges or heroic intervention that turn.
# Returns a Dictionary with results for logging/display
func resolve_transport_destroyed(transport_id: String) -> Dictionary:
	var transport = GameState.get_unit(transport_id)
	if not transport or not transport.has("transport_data"):
		return {"triggered": false, "reason": "Not a transport"}

	var embarked_unit_ids = transport.transport_data.get("embarked_units", []).duplicate()
	if embarked_unit_ids.is_empty():
		print("TransportManager: P3-32 Transport %s destroyed with no embarked units" % transport_id)
		return {"triggered": false, "reason": "No embarked units"}

	var transport_name = transport.get("meta", {}).get("name", transport_id)
	print("TransportManager: P3-32 Transport %s (%s) destroyed with %d embarked unit(s)!" % [
		transport_name, transport_id, embarked_unit_ids.size()])

	var results = {
		"triggered": true,
		"transport_id": transport_id,
		"transport_name": transport_name,
		"per_unit": [],
		"total_casualties": 0,
		"diffs": []
	}

	# Process each embarked unit
	for unit_id in embarked_unit_ids:
		var unit = GameState.get_unit(unit_id)
		if not unit:
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var alive_models = []
		for i in range(unit.models.size()):
			if unit.models[i].get("alive", true):
				alive_models.append(i)

		# Roll D6 for each disembarking model — on a 1, one model is destroyed
		var casualties = 0
		var rolls = []
		for model_idx in alive_models:
			var roll = randi_range(1, 6)
			rolls.append(roll)
			if roll == 1:
				casualties += 1

		print("TransportManager: P3-32   %s (%s): %d models disembark, rolls: %s, casualties: %d" % [
			unit_name, unit_id, alive_models.size(), str(rolls), casualties])

		# Apply casualties — kill models from the end (non-leader models first per 10e)
		var models_killed = 0
		if casualties > 0:
			# Kill from back of the alive list (typically non-characters/leaders go last in list)
			var kill_indices = []
			for i in range(alive_models.size() - 1, -1, -1):
				if models_killed >= casualties:
					break
				kill_indices.append(alive_models[i])
				models_killed += 1

			for kill_idx in kill_indices:
				results.diffs.append({
					"op": "set",
					"path": "units.%s.models.%d.alive" % [unit_id, kill_idx],
					"value": false
				})
				results.diffs.append({
					"op": "set",
					"path": "units.%s.models.%d.current_wounds" % [unit_id, kill_idx],
					"value": 0
				})

		# Clear embark status — the unit is now disembarked
		results.diffs.append({
			"op": "set",
			"path": "units.%s.embarked_in" % unit_id,
			"value": null
		})
		results.diffs.append({
			"op": "set",
			"path": "units.%s.disembarked_this_phase" % unit_id,
			"value": true
		})

		# Disembarked from destroyed transport: cannot charge this turn
		results.diffs.append({
			"op": "set",
			"path": "units.%s.flags.cannot_charge" % unit_id,
			"value": true
		})
		results.diffs.append({
			"op": "set",
			"path": "units.%s.flags.cannot_move" % unit_id,
			"value": true
		})

		# Place surviving models near the transport's last position
		var transport_pos = _get_transport_center(transport)
		var surviving_count = 0
		for i in range(unit.models.size()):
			if unit.models[i].get("alive", true):
				# Check if this model was killed in the emergency disembark
				var was_killed = false
				for diff in results.diffs:
					if diff.path == "units.%s.models.%d.alive" % [unit_id, i] and diff.value == false:
						was_killed = true
						break
				if not was_killed:
					# Place surviving models in a circle around the transport position
					var angle = (surviving_count / max(float(alive_models.size()), 1.0)) * TAU
					var offset = Vector2(cos(angle), sin(angle)) * 50.0  # ~1.5" spread
					var pos = transport_pos + offset
					results.diffs.append({
						"op": "set",
						"path": "units.%s.models.%d.position" % [unit_id, i],
						"value": {"x": pos.x, "y": pos.y}
					})
					surviving_count += 1

		results.per_unit.append({
			"unit_id": unit_id,
			"unit_name": unit_name,
			"models_disembarked": alive_models.size(),
			"rolls": rolls,
			"casualties": casualties
		})
		results.total_casualties += casualties

	# Clear the transport's embarked units list
	results.diffs.append({
		"op": "set",
		"path": "units.%s.transport_data.embarked_units" % transport_id,
		"value": []
	})

	print("TransportManager: P3-32 Emergency disembark complete — %d total casualties" % results.total_casualties)
	emit_signal("transport_destroyed", transport_id, embarked_unit_ids, results)
	return results

# P3-32: Get transport center position for emergency disembark placement
func _get_transport_center(transport: Dictionary) -> Vector2:
	var center = Vector2.ZERO
	var count = 0
	for model in transport.get("models", []):
		if model.has("position") and model.position != null:
			center += Vector2(model.position.x, model.position.y)
			count += 1
	if count > 0:
		center /= count
	return center

# P3-32: Check if a destroyed unit is a transport with embarked units
func is_transport_with_embarked(unit_id: String) -> bool:
	var unit = GameState.get_unit(unit_id)
	if not unit or not unit.has("transport_data"):
		return false
	var embarked = unit.transport_data.get("embarked_units", [])
	return embarked.size() > 0

# P3-32: Get embarked unit IDs for a transport
func get_embarked_unit_ids(transport_id: String) -> Array:
	var transport = GameState.get_unit(transport_id)
	if not transport or not transport.has("transport_data"):
		return []
	return transport.transport_data.get("embarked_units", []).duplicate()

# Reset disembarked flags at the start of a new phase
func reset_disembark_flags() -> void:
	var any_reset = false
	for unit_id in GameState.state.units:
		var unit = GameState.state.units[unit_id]
		if unit.get("disembarked_this_phase", false):
			unit["disembarked_this_phase"] = false
			GameState.state.units[unit_id] = unit
			any_reset = true

	if any_reset:
		print("Reset disembark flags for new phase")

# P3-95: Centralized shape-aware distance checks for embark/disembark
# Both embark and disembark use Measurement.model_to_model_distance_inches()
# which handles circular, oval, and rectangular bases via iterative closest-point refinement.

# Check if a single model is within embark range (3") of a transport (shape-aware edge-to-edge)
func is_model_within_embark_range(model: Dictionary, transport: Dictionary, range_inches: float = 3.0) -> Dictionary:
	if transport.models.size() == 0:
		return {"within_range": false, "distance_inches": INF}
	var transport_model = transport.models[0]
	var dist_inches = Measurement.model_to_model_distance_inches(model, transport_model)
	return {"within_range": dist_inches <= range_inches, "distance_inches": dist_inches}

# Check if ALL alive models in a unit are within embark range of a transport
func is_unit_within_embark_range(unit: Dictionary, transport: Dictionary, range_inches: float = 3.0) -> Dictionary:
	if transport.models.size() == 0:
		return {"within_range": false, "reason": "Transport has no models"}
	var transport_model = transport.models[0]
	for model in unit.models:
		if not model.alive or model.position == null:
			continue
		var dist_inches = Measurement.model_to_model_distance_inches(model, transport_model)
		if dist_inches > range_inches:
			return {"within_range": false, "reason": "Model is %.1f\" from transport (max %.1f\")" % [dist_inches, range_inches]}
	return {"within_range": true}

# Check if a model placed at a given position would be within disembark range (3") of a transport
# Creates a temporary model dict with the proposed position for shape-aware measurement
func is_position_within_disembark_range(pos: Vector2, model: Dictionary, transport: Dictionary, range_inches: float = 3.0) -> Dictionary:
	if transport.models.size() == 0:
		return {"within_range": false, "distance_inches": INF}
	var transport_model = transport.models[0]
	var model_at_pos = model.duplicate()
	model_at_pos["position"] = {"x": pos.x, "y": pos.y}
	var dist_inches = Measurement.model_to_model_distance_inches(model_at_pos, transport_model)
	return {"within_range": dist_inches <= range_inches, "distance_inches": dist_inches}

# P1-60: Check if a destroyed unit is a transport with embarked units
func is_transport_with_embarked_units(unit_id: String) -> bool:
	var unit = GameState.get_unit(unit_id)
	if not unit or not unit.has("transport_data"):
		return false
	var embarked = unit.transport_data.get("embarked_units", [])
	return embarked.size() > 0

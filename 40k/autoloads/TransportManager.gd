extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# TransportManager - Manages embark/disembark operations for transport units
# This autoload handles all transport-related logic and validation

signal embark_requested(transport_id: String, unit_id: String)
signal disembark_requested(transport_id: String, unit_id: String)
signal embark_completed(transport_id: String, unit_id: String)
signal disembark_completed(unit_id: String)

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

	# Check capacity
	var current_count = _get_embarked_model_count(transport_id)
	var unit_model_count = _get_alive_model_count(unit)

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

	if not unit:
		return {"valid": false, "reason": "Unit not found"}

	if not unit.get("embarked_in", null):
		return {"valid": false, "reason": "Unit is not embarked"}

	var transport = GameState.get_unit(unit.embarked_in)
	if not transport:
		return {"valid": false, "reason": "Transport not found"}

	# Check if transport has advanced or fell back
	if transport.get("flags", {}).get("advanced", false):
		return {"valid": false, "reason": "Cannot disembark from transport that Advanced"}

	if transport.get("flags", {}).get("fell_back", false):
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

# Get total number of models currently embarked in a transport
func _get_embarked_model_count(transport_id: String) -> int:
	var transport = GameState.get_unit(transport_id)
	if not transport or not transport.has("transport_data"):
		return 0

	var count = 0
	for embarked_id in transport.transport_data.embarked_units:
		var unit = GameState.get_unit(embarked_id)
		if unit:
			count += _get_alive_model_count(unit)

	return count

# Get number of alive models in a unit
func _get_alive_model_count(unit: Dictionary) -> int:
	var count = 0
	if unit.has("models"):
		for model in unit.models:
			if model.get("alive", true):
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

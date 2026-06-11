class_name MoveTypes
extends RefCounted

## Registry of move-type instances (ISS-040). Phases ask
## `available_for(unit_id, board)` which moves a unit may select (09.02's
## Select Move Type step) and fetch instances by id to drive the template.

static var _registry: Dictionary = {}

static func _ensure() -> void:
	if _registry.is_empty():
		for mt in [RemainStationaryMove.new(), NormalMove.new(), AdvanceMove.new(), FallBackMove.new(), IngressMove.new(), SurgeMove.new(), DisembarkMove.new(), EmergencyDisembarkMove.new(), ChargeMove11e.new()]:
			_registry[mt.id] = mt

static func get_type(id: String) -> MoveType:
	_ensure()
	return _registry.get(id, null)

static func all_ids() -> Array:
	_ensure()
	return _registry.keys()

## The move types the unit is currently eligible to make, in rulebook
## presentation order (09.02).
static func available_for(unit_id: String, board: Dictionary) -> Array:
	_ensure()
	var out: Array = []
	for id in ["remain_stationary", "normal", "advance", "fall_back"]:
		var mt: MoveType = _registry[id]
		if mt.eligible(unit_id, board).eligible:
			out.append(id)
	return out

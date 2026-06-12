class_name ShootingTypes
extends RefCounted

## Registry of shooting-type instances (ISS-048). The phase asks
## `available_for(unit_id, board)` which types a unit may select
## (10.02's Select Shooting Type step) and fetches instances by id to
## enforce the WHILE constraints. Snap shooting (15.09) is granted by
## rules such as Fire Overwatch, never freely selectable.

static var _registry: Dictionary = {}

static func _ensure() -> void:
	if _registry.is_empty():
		for st in [NormalShooting.new(), AssaultShooting.new(), CloseQuartersShooting.new(), IndirectShooting.new(), SnapShooting.new()]:
			_registry[st.id] = st

static func get_type(id: String) -> ShootingType:
	_ensure()
	return _registry.get(id, null)

static func all_ids() -> Array:
	_ensure()
	return _registry.keys()

## The shooting types the unit may select, in rulebook presentation
## order (10.02). Snap is excluded (rule-granted only).
static func available_for(unit_id: String, board: Dictionary) -> Array:
	_ensure()
	var out: Array = []
	for id in ["normal", "assault", "close_quarters", "indirect"]:
		var st: ShootingType = _registry[id]
		if st.eligible(unit_id, board).eligible:
			out.append(id)
	return out

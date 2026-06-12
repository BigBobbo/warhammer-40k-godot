class_name StateSchema
extends RefCounted

## State shape validation + canonical diff-path builders (ISS-017).
##
## The game state is still a Dictionary (full typed migration is out of
## scope), but its required shape is now written down in one place and
## validated in tests and on load. Hand-typed magic path strings in phase
## handlers should migrate to the `path_*` builders below so a renamed key
## is a compile-visible change, not a silently-dropped diff
## (PhaseManager._set_state_value now also errors loudly on bad paths).

## Required top-level sections and their types.
const TOP_LEVEL := {
	"meta": TYPE_DICTIONARY,
	"board": TYPE_DICTIONARY,
	"units": TYPE_DICTIONARY,
	"players": TYPE_DICTIONARY,
	"factions": TYPE_DICTIONARY,
}

## Required meta fields and their types (int-likes accept float because
## JSON round-trips numbers as floats).
const META_FIELDS := {
	"turn_number": TYPE_INT,
	"battle_round": TYPE_INT,
	"active_player": TYPE_INT,
	"phase": TYPE_INT,
}


## Validate a state dict. Returns human-readable errors (empty = valid).
static func validate(state: Dictionary) -> Array:
	var errors: Array = []
	for key in TOP_LEVEL:
		if not state.has(key):
			errors.append("missing top-level section '%s'" % key)
		elif typeof(state[key]) != TOP_LEVEL[key]:
			errors.append("section '%s' has wrong type (%s)" % [key, type_string(typeof(state[key]))])
	var meta = state.get("meta", {})
	if meta is Dictionary:
		for key in META_FIELDS:
			if not meta.has(key):
				errors.append("missing meta.%s" % key)
			elif typeof(meta[key]) != META_FIELDS[key] and not (META_FIELDS[key] == TYPE_INT and typeof(meta[key]) == TYPE_FLOAT):
				errors.append("meta.%s has wrong type (%s)" % [key, type_string(typeof(meta[key]))])
	var units = state.get("units", {})
	if units is Dictionary:
		for unit_id in units:
			var unit = units[unit_id]
			if not unit is Dictionary:
				errors.append("unit '%s' is not a Dictionary" % unit_id)
				continue
			if not unit.get("meta", null) is Dictionary:
				errors.append("unit '%s' missing meta dict" % unit_id)
			if not unit.get("models", null) is Array:
				errors.append("unit '%s' missing models array" % unit_id)
	return errors


# ── Canonical diff-path builders ────────────────────────────────────

static func path_unit_meta(unit_id: String, field: String) -> String:
	return "units.%s.meta.%s" % [unit_id, field]

static func path_unit_flag(unit_id: String, flag: String) -> String:
	return "units.%s.flags.%s" % [unit_id, flag]

static func path_unit_field(unit_id: String, field: String) -> String:
	return "units.%s.%s" % [unit_id, field]

static func path_model_field(unit_id: String, model_index: int, field: String) -> String:
	return "units.%s.models.%d.%s" % [unit_id, model_index, field]

static func path_meta(field: String) -> String:
	return "meta.%s" % field

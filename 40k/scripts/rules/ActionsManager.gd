class_name ActionsManager
extends RefCounted

## The 11e ACTIONS system (ISS-057; core rules 16.00-16.01).
##
## Actions are data-defined battlefield tasks:
##   {id, name, starts: "shooting"|"movement"|..., units: {keywords: [...]},
##    use_limit: "once_per_turn"|"once_per_battle"|"",
##    completes: "end_of_turn"|"start_of_next_command"|...,
##    effect: Callable|String}
##
## STARTING (16.01) — a unit is eligible to start an action unless:
##   ▪ it is not on the battlefield
##   ▪ it is an AIRCRAFT or FORTIFICATION unit
##   ▪ it is battle-shocked
##   ▪ its OC characteristic is 0 or '-'
##   ▪ it is engaged (unless it is TITANIC)
##   ▪ it made an advance or fall-back move this turn
##   ▪ it started another action this turn
## Once started, until end of turn the unit is not eligible to shoot
## (excluding TITANIC) or declare a charge.
##
## COMPLETING — if the performing unit makes a move (other than pile-in or
## consolidation) or leaves the battlefield, the action does NOT complete;
## otherwise the effect triggers at the action's COMPLETES point.
##
## Per-unit action state lives in unit flags (pipeline-visible):
##   flags.performing_action = action id, flags.action_started_turn = N.

static var _definitions: Dictionary = {}
static var _use_counts: Dictionary = {}  # "<player>|<action_id>|<turn>" -> int


static func register_action(def: Dictionary) -> void:
	_definitions[str(def.get("id", ""))] = def

## Register the generic, army-agnostic 11e actions so the system is usable in
## live play even before a mission pack is provided (ISS-057 / PRD open q.3).
## These start in the Shooting phase (giving up shooting) and complete at end
## of turn — the canonical 16.01 shape. Mission packs can register more.
static func register_default_actions() -> void:
	register_action({
		"id": "hold_position",
		"name": "Hold Position",
		"starts": "shooting",
		"units": {"keywords": ["INFANTRY"]},
		"use_limit": "",
		"completes": "end_of_turn",
		"effect": "hold_position",
		"description": "Dig in on this position. The unit gives up shooting and cannot charge this turn; the action completes at the end of your turn.",
	})

static func _ensure_defaults() -> void:
	if _definitions.is_empty():
		register_default_actions()

## Actions the unit is eligible to START right now (registry ∩ eligibility ∩
## per-unit keyword filter ∩ use limit), each as {id, name, description}.
static func get_startable_actions(unit_id: String, board: Dictionary, player: int = -1, turn: int = -1) -> Array:
	_ensure_defaults()
	var out: Array = []
	if not can_start_action(unit_id, board).eligible:
		return out
	var unit = board.get("units", {}).get(unit_id, {})
	var unit_kws = unit.get("meta", {}).get("keywords", [])
	for action_id in _definitions:
		var def = _definitions[action_id]
		var ok := true
		for kw in def.get("units", {}).get("keywords", []):
			if not str(kw) in unit_kws:
				ok = false
				break
		if not ok:
			continue
		if def.get("use_limit", "") == "once_per_turn" and player >= 0 and turn >= 0:
			if _use_counts.get("%d|%s|%d" % [player, action_id, turn], 0) >= 1:
				continue
		# Mission-pack actions are restricted to the owning player and can
		# carry a contextual eligibility check (unit near an objective etc.)
		if not _mission_gate_ok(def, unit_id, unit, player):
			continue
		out.append({"id": action_id, "name": def.get("name", action_id), "description": def.get("description", "")})
	return out

## Mission-pack gate: per-definition owning player + contextual check
## delegated to MissionManager (e.g. "unit in range of an eligible
## objective"). Definitions without these fields are unrestricted.
static func _mission_gate_ok(def: Dictionary, unit_id: String, unit: Dictionary, player: int) -> bool:
	if def.has("player"):
		var owner = int(unit.get("owner", player))
		if int(def["player"]) != owner:
			return false
	if def.get("mission_check", "") != "":
		var mm = Engine.get_main_loop().root.get_node_or_null("/root/MissionManager")
		if mm == null or not mm.has_method("can_start_mission_action_11e"):
			return false
		if not mm.can_start_mission_action_11e(str(def["mission_check"]), unit_id, int(unit.get("owner", player))):
			return false
	return true

## Remove all registered actions whose id starts with the prefix (used by
## mission packs to re-register per game).
static func unregister_actions_by_prefix(prefix: String) -> void:
	for action_id in _definitions.keys():
		if str(action_id).begins_with(prefix):
			_definitions.erase(action_id)

static func get_action(id: String) -> Dictionary:
	return _definitions.get(id, {})

static func clear_registry() -> void:
	_definitions.clear()
	_use_counts.clear()


## 16.01 eligibility to START an action. Returns {eligible, reasons}.
static func can_start_action(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["actions are an 11e system"]}
	var unit = board.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"eligible": false, "reasons": ["unknown unit"]}
	var reasons: Array = []

	var on_field := false
	for m in unit.get("models", []):
		if m.get("alive", true) and m.get("position") != null:
			on_field = true
			break
	if not on_field:
		reasons.append("not on the battlefield")

	var keywords: Array = unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in keywords or "FORTIFICATION" in keywords:
		reasons.append("AIRCRAFT/FORTIFICATION units cannot start actions")

	var flags = unit.get("flags", {})
	if flags.get("battle_shocked", false):
		reasons.append("battle-shocked units are not eligible to start an action")

	var oc = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 0))
	if oc <= 0:
		reasons.append("OC characteristic is 0 or '-'")

	var titanic = "TITANIC" in keywords
	var rules = Engine.get_main_loop().root.get_node("/root/RulesEngine")
	if not titanic and rules.is_unit_engaged(unit_id, board):
		reasons.append("engaged units cannot start actions (unless TITANIC)")

	if flags.get("advanced", false) or flags.get("fell_back", false) or flags.get("cannot_start_action", false):
		reasons.append("made an advance or fall-back move this turn")

	if flags.get("performing_action", "") != "":
		reasons.append("already started an action this turn")

	return {"eligible": reasons.is_empty(), "reasons": reasons}


## Start an action: returns {success, changes (diffs), errors}. The
## shooting/charge locks are flags the phase eligibility checks consult.
static func start_action(unit_id: String, action_id: String, board: Dictionary, player: int, turn: int) -> Dictionary:
	_ensure_defaults()
	var def = get_action(action_id)
	if def.is_empty():
		return {"success": false, "errors": ["unknown action '%s'" % action_id], "changes": []}
	var elig = can_start_action(unit_id, board)
	if not elig.eligible:
		return {"success": false, "errors": elig.reasons, "changes": []}

	# Unit filter (e.g. INFANTRY only for the Deploy Device example)
	var unit = board.units[unit_id]
	for kw in def.get("units", {}).get("keywords", []):
		if not str(kw) in unit.get("meta", {}).get("keywords", []):
			return {"success": false, "errors": ["unit lacks required keyword %s" % kw], "changes": []}

	# Mission-pack restrictions (owning player + contextual eligibility)
	if not _mission_gate_ok(def, unit_id, unit, player):
		return {"success": false, "errors": ["%s is not available to this unit right now" % def.get("name", action_id)], "changes": []}

	# Use limit
	if def.get("use_limit", "") == "once_per_turn":
		var key = "%d|%s|%d" % [player, action_id, turn]
		if _use_counts.get(key, 0) >= 1:
			return {"success": false, "errors": ["%s already started this turn" % def.get("name", action_id)], "changes": []}
		_use_counts[key] = _use_counts.get(key, 0) + 1

	var titanic = "TITANIC" in unit.get("meta", {}).get("keywords", [])
	var changes = [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "performing_action"), "value": action_id},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "action_started_turn"), "value": turn},
		# 16.01: until end of turn — not eligible to declare a charge…
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "cannot_charge"), "value": true},
	]
	if not titanic:
		# …and not eligible to shoot (TITANIC units may still shoot).
		changes.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "cannot_shoot"), "value": true})
	return {"success": true, "errors": [], "changes": changes}


## Movement cancels an in-progress action (16.01 Completing), except
## pile-in and consolidation moves. Returns cancellation diffs ([] = none).
static func on_unit_moved(unit_id: String, unit: Dictionary, move_type_id: String) -> Array:
	if unit.get("flags", {}).get("performing_action", "") == "":
		return []
	if move_type_id in ["pile_in", "consolidation"]:
		return []
	return [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "performing_action"), "value": ""},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "action_failed"), "value": true},
	]


## Resolve actions whose COMPLETES trigger fired. Returns
## {completed: [{unit_id, action_id, effect}], changes (diffs)}.
static func complete_actions(trigger: String, board: Dictionary) -> Dictionary:
	var completed: Array = []
	var changes: Array = []
	for unit_id in board.get("units", {}):
		var unit = board.units[unit_id]
		var action_id = str(unit.get("flags", {}).get("performing_action", ""))
		if action_id == "":
			continue
		var def = get_action(action_id)
		if def.is_empty() or str(def.get("completes", "")) != trigger:
			continue
		# Battle-shock prevents completion (01.07).
		if unit.get("flags", {}).get("battle_shocked", false):
			changes.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "performing_action"), "value": ""})
			changes.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "action_failed"), "value": true})
			continue
		completed.append({"unit_id": unit_id, "action_id": action_id, "effect": def.get("effect", "")})
		changes.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "performing_action"), "value": ""})
		changes.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "action_completed"), "value": action_id})
	return {"completed": completed, "changes": changes}

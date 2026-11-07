extends BasePhase
class_name RedeploymentPhase

const BasePhase = preload("res://phases/BasePhase.gd")

# RedeploymentPhase - Handles pre-game redeployment between Deployment and Scout Moves
# Per Core Rules Updates:
# - Rules that allow players to redeploy certain units after both armies are deployed
#   (e.g. HURON BLACKHEART's Red Corsairs ability, Phantasm stratagem) are always
#   resolved after the Deploy Armies step and before the Determine First Turn step.
# - Players alternate resolving redeployment rules, starting with the Attacker.
# - When redeploying, normal deployment rules apply (including Infiltrators positioning).
# - Units are removed from the battlefield then set up again following standard setup rules.
#
# WP-G1 (Codex 11e gaps): a HUMAN player can use this step —
# scripts/RedeploymentController.gd lists the eligible units, re-places a unit
# with the DeploymentController ghost UI (dispatching the atomic REDEPLOY_UNIT
# below) or sends it to Strategic Reserves, skips, and hands over with
# END_REDEPLOYMENT_PHASE ("Done Redeploying"). Redeploy ENHANCEMENTS
# (Castellan's Mark, Kaptin's Hat, Razgit's Magik Map, ...:
# FactionAbilityManager.get_redeploy_enhancement) give up to three uses; a
# unit with a datasheet redeploy ability has its own. An Attached unit
# (bodyguard + leaders) is one unit: it is picked up and set up together.

const PX_PER_INCH: float = 40.0

# Track which units have completed their redeployment
var redeploy_units_pending: Dictionary = {}  # player -> [unit_ids]
var redeploy_units_completed: Array = []
var current_redeploy_player: int = 1  # Attacker goes first
var active_redeploy: Dictionary = {}  # unit_id -> redeploy_data (staged model positions)

func _init():
	phase_type = GameStateData.Phase.REDEPLOYMENT

func _on_phase_enter() -> void:
	log_phase_message("Entering Redeployment Phase")
	redeploy_units_pending.clear()
	redeploy_units_completed.clear()
	active_redeploy.clear()

	# WP-G1: the Attacker resolves redeployment first (core rules: "players
	# alternate resolving redeployment rules, starting with the Attacker").
	# meta.attacker is set by the pre-deployment RollOffPhase; fixtures and
	# saves without it fall back to Player 1.
	current_redeploy_player = _attacker_player()

	# Find all units with redeployment abilities for each player
	redeploy_units_pending[1] = _filter_redeploy_candidates(GameState.get_redeploy_units_for_player(1))
	redeploy_units_pending[2] = _filter_redeploy_candidates(GameState.get_redeploy_units_for_player(2))
	# A player whose enhancement has no uses left (e.g. a reloaded save) has
	# nothing to resolve with it.
	_drop_unusable_enhancement_units(1)
	_drop_unusable_enhancement_units(2)

	log_phase_message("Player 1 redeploy units: %s" % str(redeploy_units_pending[1]))
	log_phase_message("Player 2 redeploy units: %s" % str(redeploy_units_pending[2]))

	var total_redeploy = redeploy_units_pending[1].size() + redeploy_units_pending[2].size()

	if total_redeploy == 0:
		log_phase_message("No units with redeployment abilities found, skipping Redeployment phase")
		# Use call_deferred to avoid emitting signal during enter_phase
		call_deferred("_complete_phase")
		return

	# If the attacker has nothing to redeploy, the defender resolves theirs.
	if redeploy_units_pending.get(current_redeploy_player, []).size() == 0:
		log_phase_message("Attacker (Player %d) has no redeploy units, switching to Player %d" % [current_redeploy_player, 3 - current_redeploy_player])
		current_redeploy_player = 3 - current_redeploy_player
	GameState.set_active_player(current_redeploy_player)
	game_state_snapshot = GameState.create_snapshot()
	log_phase_message("Redeployment phase active - Player %d resolves first" % current_redeploy_player)

func _complete_phase() -> void:
	emit_signal("phase_completed")

func _on_phase_exit() -> void:
	log_phase_message("Exiting Redeployment Phase")
	active_redeploy.clear()

## WP-G1: the Attacker (meta.attacker from the deployment roll-off; 1 if unset).
func _attacker_player() -> int:
	var attacker := int(GameState.state.get("meta", {}).get("attacker", 0))
	return attacker if attacker == 1 or attacker == 2 else 1

## WP-G1: an attached CHARACTER is part of its bodyguard's Attached unit
## (11e 24.10): it is picked up and set up with that unit, never on its own,
## so it is not a separate candidate. When the CHARACTER carries a datasheet
## redeploy ability, its bodyguard (the Attached unit) is listed instead.
func _filter_redeploy_candidates(unit_ids: Array) -> Array:
	var out: Array = []
	for raw in unit_ids:
		var uid := str(raw)
		var u = GameState.get_unit(uid)
		if u.is_empty():
			continue
		var bg = u.get("attached_to", null)
		if bg != null and str(bg) != "":
			if GameState.unit_has_redeploy(uid) and not out.has(str(bg)) \
					and int(GameState.get_unit(str(bg)).get("status", 0)) == GameStateData.UnitStatus.DEPLOYED:
				out.append(str(bg))
			continue
		if not out.has(uid):
			out.append(uid)
	return out

## WP-G1: the unit and its attached CHARACTERs — picked up and set up together.
func _redeploy_group_unit_ids(unit_id: String) -> Array:
	var ids: Array = [unit_id]
	var unit = GameState.get_unit(unit_id)
	for cid in unit.get("attachment_data", {}).get("attached_characters", []):
		var c = GameState.get_unit(str(cid))
		if not c.is_empty() and str(c.get("attached_to", "")) == unit_id and not ids.has(str(cid)):
			ids.append(str(cid))
	return ids

## WP-G1: the alive models picked up with `unit_id`: [{unit_id, index, model}].
func _redeploy_group_models(unit_id: String) -> Array:
	var out: Array = []
	for uid in _redeploy_group_unit_ids(unit_id):
		var models: Array = GameState.get_unit(uid).get("models", [])
		for i in range(models.size()):
			if models[i].get("alive", true):
				out.append({"unit_id": uid, "index": i, "model": models[i]})
	return out

## WP-G1: true when the unit's redeploy comes from a datasheet ability of the
## unit or one of its attached CHARACTERs (its own rule, no enhancement use).
func _is_ability_redeploy(unit_id: String) -> bool:
	for uid in _redeploy_group_unit_ids(unit_id):
		if GameState.unit_has_redeploy(uid):
			return true
	return false

func _enhancement_uses_left(player: int) -> int:
	var fam = get_node_or_null("/root/FactionAbilityManager")
	if fam == null or not fam.has_razgit_magik_map(player):
		return 0
	return maxi(0, fam.get_razgit_redeploys_remaining(player))

## WP-G1: once a player's redeploy enhancement has no uses left, the units it
## alone made eligible drop out of that player's pending list, so the step
## moves on instead of waiting on choices the player can no longer make.
func _drop_unusable_enhancement_units(player: int) -> void:
	if _enhancement_uses_left(player) > 0:
		return
	var pending: Array = redeploy_units_pending.get(player, [])
	for i in range(pending.size() - 1, -1, -1):
		if not _is_ability_redeploy(str(pending[i])):
			log_phase_message("Player %d has no redeploy-enhancement uses left — %s keeps its position" % [player, pending[i]])
			pending.remove_at(i)

## WP-G1: shared pick-up checks for BEGIN_REDEPLOY / REDEPLOY_UNIT /
## SEND_TO_STRATEGIC_RESERVES.
func _validate_redeploy_candidate(unit_id: String) -> Array:
	if unit_id == "":
		return ["Missing unit_id"]
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return ["Unit not found: " + unit_id]
	var active_player = get_current_player()
	if int(unit.get("owner", 0)) != active_player:
		return ["Unit does not belong to active player"]
	var st := int(unit.get("status", 0))
	# DEPLOYING: the UI marks the unit while its models are being re-placed.
	if st != GameStateData.UnitStatus.DEPLOYED and st != GameStateData.UnitStatus.DEPLOYING:
		return ["Unit must be deployed to redeploy"]
	if unit_id in redeploy_units_completed:
		return ["Unit has already completed its redeployment"]
	if unit_id not in redeploy_units_pending.get(active_player, []):
		return ["Unit is not eligible for redeployment"]
	if not _is_ability_redeploy(unit_id) and _enhancement_uses_left(active_player) <= 0:
		return ["No redeploy-enhancement uses remaining (up to three units)"]
	return []

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	match action_type:
		"BEGIN_REDEPLOY":
			return _validate_begin_redeploy(action)
		"SET_REDEPLOY_MODEL_POS":
			return _validate_set_redeploy_model_pos(action)
		"CONFIRM_REDEPLOY":
			return _validate_confirm_redeploy(action)
		"REDEPLOY_UNIT":
			return _validate_redeploy_unit(action)
		"SKIP_REDEPLOY":
			return _validate_skip_redeploy(action)
		"SEND_TO_STRATEGIC_RESERVES":
			return _validate_send_to_reserves(action)
		"END_REDEPLOYMENT_PHASE":
			return _validate_end_redeployment_phase(action)
		"DEBUG_MOVE":
			return {"valid": true}
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"BEGIN_REDEPLOY":
			return _process_begin_redeploy(action)
		"SET_REDEPLOY_MODEL_POS":
			return _process_set_redeploy_model_pos(action)
		"CONFIRM_REDEPLOY":
			return _process_confirm_redeploy(action)
		"REDEPLOY_UNIT":
			return _process_redeploy_unit(action)
		"SKIP_REDEPLOY":
			return _process_skip_redeploy(action)
		"SEND_TO_STRATEGIC_RESERVES":
			return _process_send_to_reserves(action)
		"END_REDEPLOYMENT_PHASE":
			return _process_end_redeployment_phase(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# ========================================
# Validation Methods
# ========================================

func _validate_begin_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	var errors := _validate_redeploy_candidate(unit_id)
	if errors.is_empty() and active_redeploy.has(unit_id):
		errors.append("Unit already has a redeployment in progress")
	return {"valid": errors.is_empty(), "errors": errors}

## Staged flow (scripts / tests): one model at a time. `model_unit_id` names
## the attached CHARACTER a model belongs to (defaults to the unit itself).
func _validate_set_redeploy_model_pos(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	var model_id = str(action.get("model_id", ""))
	var dest = action.get("destination", null)

	if unit_id == "" or model_id == "":
		return {"valid": false, "errors": ["Missing unit_id or model_id"]}
	if dest == null:
		return {"valid": false, "errors": ["Missing destination"]}
	if not active_redeploy.has(unit_id):
		return {"valid": false, "errors": ["No active redeployment for unit: " + unit_id]}

	var model_unit_id = str(action.get("model_unit_id", unit_id))
	if not _redeploy_group_unit_ids(unit_id).has(model_unit_id):
		return {"valid": false, "errors": ["%s is not part of %s" % [model_unit_id, unit_id]]}
	var model := {}
	for m in GameState.get_unit(model_unit_id).get("models", []):
		if str(m.get("id", "")) == model_id:
			model = m
			break
	if model.is_empty():
		return {"valid": false, "errors": ["Model not found: " + model_id]}

	var errors := _validate_model_placement(unit_id, model, _coerce_pos(dest), float(action.get("rotation", model.get("rotation", 0.0))))
	return {"valid": errors.is_empty(), "errors": errors}

func _validate_confirm_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}
	if not active_redeploy.has(unit_id):
		return {"valid": false, "errors": ["No active redeployment for unit: " + unit_id]}
	var errors := _validate_group_placements(unit_id, _staged_placements(unit_id))
	return {"valid": errors.is_empty(), "errors": errors}

## WP-G1: atomic redeploy (the human UI path): every model of the unit and of
## its attached CHARACTERs in one action. placements:
## [{unit_id, model_id, x, y, rotation}], board px.
func _validate_redeploy_unit(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	var errors := _validate_redeploy_candidate(unit_id)
	if not errors.is_empty():
		return {"valid": false, "errors": errors}
	var placements = action.get("placements", [])
	if not (placements is Array) or placements.is_empty():
		return {"valid": false, "errors": ["Missing placements"]}
	errors = _validate_group_placements(unit_id, placements)
	return {"valid": errors.is_empty(), "errors": errors}

func _validate_skip_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	# Must belong to active player
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Must be in pending list
	var pending = redeploy_units_pending.get(get_current_player(), [])
	if unit_id not in pending:
		return {"valid": false, "errors": ["Unit is not eligible for redeployment"]}

	return {"valid": true, "errors": []}

func _validate_end_redeployment_phase(action: Dictionary) -> Dictionary:
	# Redeployment is OPTIONAL (Core Rules: rules that ALLOW players to redeploy
	# certain units). A player may always decline to redeploy any of their
	# remaining eligible units, so ending is always valid — units left pending
	# simply stay where they were deployed.
	#
	# Previously this returned invalid while ANY unit was pending, a soft-lock
	# for a human (audit P0). WP-G1: it ends the ACTIVE player's redeployments
	# ("Done Redeploying") and hands the step to the opponent when they still
	# have redeployments to resolve; the step ends once neither player has any
	# left (see _process_end_redeployment_phase).
	return {"valid": true, "errors": []}

# ---- WP-G1: placement validation (normal deployment rules) ----

func _coerce_pos(p) -> Vector2:
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	if p is Array and p.size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO

## One model's set-up under the normal deployment rules: on the battlefield,
## wholly within its deployment zone (Infiltrators instead: more than 8" (11e)
## / 9" (10e) from the enemy deployment zone and every enemy model), not on
## another unit's model, not through a wall its unit cannot cross. The models
## being picked up (the unit and its attached CHARACTERs) never block.
func _validate_model_placement(group_unit_id: String, model: Dictionary, pos: Vector2, rotation: float) -> Array:
	var errors: Array = []
	var unit = GameState.get_unit(group_unit_id)
	var owner := int(unit.get("owner", 0))
	var test_model: Dictionary = model.duplicate()
	test_model["position"] = pos
	test_model["rotation"] = rotation
	if Measurement.model_outside_board(pos, test_model):
		errors.append("Model cannot be placed off the board")
	if GameState.unit_has_infiltrators(group_unit_id):
		errors.append_array(_infiltrators_errors(owner, model, test_model, pos))
	else:
		var zone_poly := GameState.get_deployment_zone_poly_px(owner)
		if zone_poly.size() >= 3 and not Measurement.shape_wholly_in_polygon(pos, model, rotation, zone_poly):
			errors.append("Model must be wholly within your deployment zone")
	if _overlaps_other_units(group_unit_id, test_model, pos, rotation):
		errors.append("Model cannot overlap with other models")
	var kw: Array = unit.get("meta", {}).get("keywords", [])
	if Measurement.model_overlaps_any_wall(test_model, kw):
		errors.append("Model cannot overlap with walls this unit can't cross")
	return errors

func _infiltrators_errors(owner: int, model: Dictionary, test_model: Dictionary, pos: Vector2) -> Array:
	var standoff := 8.0 if GameConstants.edition >= 11 else 9.0
	var enemy_poly := GameState.get_deployment_zone_poly_px(3 - owner)
	if enemy_poly.size() >= 3:
		var r_px := Measurement.base_radius_px(int(model.get("base_mm", 32)))
		if Geometry2D.is_point_in_polygon(pos, enemy_poly):
			return ["Infiltrators must be more than %d\" from the enemy deployment zone" % int(standoff)]
		var min_px := INF
		for i in range(enemy_poly.size()):
			min_px = minf(min_px, Measurement.point_to_line_distance(pos, enemy_poly[i], enemy_poly[(i + 1) % enemy_poly.size()]))
		if (min_px - r_px) / PX_PER_INCH <= standoff:
			return ["Infiltrators must be more than %d\" from the enemy deployment zone" % int(standoff)]
	var units: Dictionary = GameState.state.get("units", {})
	for uid in units:
		var other = units[uid]
		if int(other.get("owner", 0)) == owner:
			continue
		var st := int(other.get("status", 0))
		if st != GameStateData.UnitStatus.DEPLOYED and st != GameStateData.UnitStatus.MOVED:
			continue
		for om in other.get("models", []):
			if not om.get("alive", true) or om.get("position", null) == null:
				continue
			if Measurement.model_to_model_distance_px(test_model, om) / PX_PER_INCH <= standoff:
				return ["Infiltrators must be more than %d\" from enemy models" % int(standoff)]
	return []

func _overlaps_other_units(group_unit_id: String, model: Dictionary, pos: Vector2, rotation: float) -> bool:
	if SettingsService.unit_skips_collision(group_unit_id):
		return false
	var shape = Measurement.create_base_shape(model)
	if shape == null:
		return false
	var group := _redeploy_group_unit_ids(group_unit_id)
	var units: Dictionary = GameState.state.get("units", {})
	for uid in units:
		if group.has(str(uid)) or SettingsService.unit_skips_collision(str(uid)):
			continue
		var u = units[uid]
		if u.get("embarked_in", null) != null:
			continue
		var st := int(u.get("status", 0))
		if st < GameStateData.UnitStatus.DEPLOYED or st == GameStateData.UnitStatus.IN_RESERVES:
			continue
		for om in u.get("models", []):
			if not om.get("alive", true) or om.get("position", null) == null:
				continue
			var other_shape = Measurement.create_base_shape(om)
			if other_shape and shape.overlaps_with(other_shape, pos, rotation, _coerce_pos(om.position), float(om.get("rotation", 0.0))):
				return true
	return false

## Every alive model of the unit and its attached CHARACTERs placed exactly
## once, each legally, no two overlapping, and the Attached unit in coherency.
func _validate_group_placements(unit_id: String, placements: Array) -> Array:
	var errors: Array = []
	var wanted := {}
	for g in _redeploy_group_models(unit_id):
		wanted["%s|%s" % [g.unit_id, str(g.model.get("id", ""))]] = g
	var seen := {}
	var placed: Array = []  # [{model, pos, rot}]
	for p in placements:
		if not (p is Dictionary):
			errors.append("Bad placement entry")
			continue
		var key := "%s|%s" % [str(p.get("unit_id", unit_id)), str(p.get("model_id", ""))]
		if not wanted.has(key):
			errors.append("Placement for a model that is not being redeployed: %s" % key)
			continue
		if seen.has(key):
			errors.append("Model placed twice: %s" % key)
			continue
		seen[key] = true
		var model: Dictionary = wanted[key].model
		var pos := _coerce_pos(p)
		var rot := float(p.get("rotation", model.get("rotation", 0.0)))
		for e in _validate_model_placement(unit_id, model, pos, rot):
			if not errors.has(e):
				errors.append(e)
		placed.append({"model": model, "pos": pos, "rot": rot})
	for key in wanted:
		if not seen.has(key):
			errors.append("Every model must be set up — missing %s" % key)
	# No two models of the unit on top of each other
	var overlap_found := false
	for i in range(placed.size()):
		if overlap_found:
			break
		var si = Measurement.create_base_shape(placed[i].model)
		if si == null:
			continue
		for j in range(i + 1, placed.size()):
			var sj = Measurement.create_base_shape(placed[j].model)
			if sj and si.overlaps_with(sj, placed[i].pos, placed[i].rot, placed[j].pos, placed[j].rot):
				errors.append("Models in the unit overlap each other")
				overlap_found = true
				break
	# Coherency of the whole (Attached) unit
	if placed.size() > 1:
		var models: Array = []
		for pl in placed:
			var m: Dictionary = pl.model.duplicate()
			m["position"] = {"x": pl.pos.x, "y": pl.pos.y}
			m["rotation"] = pl.rot
			m["alive"] = true
			models.append(m)
		var coh = AttackSequence.check_unit_coherency({"models": models})
		if not bool(coh.get("coherent", true)):
			errors.append("Unit coherency broken: every model must be within 2\" of another model and within 9\" of every model in the unit")
	return errors

func _staged_placements(unit_id: String) -> Array:
	var out: Array = []
	var staged: Dictionary = active_redeploy.get(unit_id, {}).get("staged_positions", {})
	var rots: Dictionary = active_redeploy.get(unit_id, {}).get("staged_rotations", {})
	for key in staged:
		var parts := str(key).split("|")
		var muid: String = parts[0] if parts.size() == 2 else unit_id
		var mid: String = parts[1] if parts.size() == 2 else str(key)
		var pos = staged[key]
		var entry := {"unit_id": muid, "model_id": mid, "x": float(pos.x), "y": float(pos.y)}
		if rots.has(key):
			entry["rotation"] = float(rots[key])
		out.append(entry)
	return out

# ========================================
# Process Methods
# ========================================

func _process_begin_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")

	active_redeploy[unit_id] = {
		"staged_positions": {},  # "<unit_id>|<model_id>" -> {x, y}
		"staged_rotations": {},
		"original_positions": {}  # model_id -> {x, y}
	}

	# Store original positions (for undo / reference)
	var unit = get_unit(unit_id)
	for model in unit.get("models", []):
		var pos = model.get("position", null)
		if pos != null:
			active_redeploy[unit_id]["original_positions"][model.id] = {
				"x": pos.get("x", 0) if pos is Dictionary else pos.x,
				"y": pos.get("y", 0) if pos is Dictionary else pos.y
			}

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Begin redeployment for %s" % unit_name)

	return create_result(true, [])

func _process_set_redeploy_model_pos(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	var model_id = str(action.get("model_id", ""))
	var dest = action.get("destination", null)

	if not active_redeploy.has(unit_id):
		return create_result(false, [], "No active redeployment for unit")

	var pos := _coerce_pos(dest)
	var key := "%s|%s" % [str(action.get("model_unit_id", unit_id)), model_id]
	active_redeploy[unit_id]["staged_positions"][key] = {"x": pos.x, "y": pos.y}
	if action.has("rotation"):
		active_redeploy[unit_id]["staged_rotations"][key] = float(action.rotation)

	return create_result(true, [])

func _process_confirm_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	if not active_redeploy.has(unit_id):
		return create_result(false, [], "No active redeployment for unit")
	var placements := _staged_placements(unit_id)
	active_redeploy.erase(unit_id)
	return _apply_redeploy(unit_id, placements, action)

func _process_redeploy_unit(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	active_redeploy.erase(unit_id)
	return _apply_redeploy(unit_id, action.get("placements", []), action)

## WP-G1: set the unit (and its attached CHARACTERs) up at the new positions,
## spend an enhancement use when that is what made it eligible, move on.
## `action` gets the game-log line (GameEventLog reads action._log_text).
func _apply_redeploy(unit_id: String, placements: Array, action: Dictionary) -> Dictionary:
	var unit = get_unit(unit_id)
	var player := int(unit.get("owner", 0))
	var uses_enhancement := not _is_ability_redeploy(unit_id)
	var changes: Array = []
	var index_of := {}
	for g in _redeploy_group_models(unit_id):
		index_of["%s|%s" % [g.unit_id, str(g.model.get("id", ""))]] = g
	for p in placements:
		var key := "%s|%s" % [str(p.get("unit_id", unit_id)), str(p.get("model_id", ""))]
		if not index_of.has(key):
			continue
		var g = index_of[key]
		var pos := _coerce_pos(p)
		changes.append({"op": "set", "path": "units.%s.models.%d.position" % [g.unit_id, g.index], "value": {"x": pos.x, "y": pos.y}})
		if p.has("rotation"):
			changes.append({"op": "set", "path": "units.%s.models.%d.rotation" % [g.unit_id, g.index], "value": float(p.rotation)})
	for uid in _redeploy_group_unit_ids(unit_id):
		changes.append({"op": "set", "path": "units.%s.status" % uid, "value": GameStateData.UnitStatus.DEPLOYED})

	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	_apply_changes_to_local_state(changes)

	_mark_redeploy_complete(unit_id)

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	var label := "Redeployment"
	if uses_enhancement and faction_mgr and faction_mgr.has_razgit_magik_map(player):
		faction_mgr.mark_razgit_redeploy_used(player)
		label = str(faction_mgr.get_redeploy_enhancement_name(player)).to_upper()
		_drop_unusable_enhancement_units(player)

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("%s: %s redeployed (%d models set up again)" % [label, unit_name, placements.size()])
	action["_log_text"] = "%s: %s redeployed (%d models set up again)" % [label, unit_name, placements.size()]

	_check_redeploy_progression()
	return create_result(true, changes)

func _process_skip_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")

	# If there's an active redeploy, clean it up
	if active_redeploy.has(unit_id):
		active_redeploy.erase(unit_id)

	# Mark unit as completed (skipped counts as completed)
	_mark_redeploy_complete(unit_id)

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Redeployment skipped for %s (unit stays in place)" % unit_name)
	action["_log_text"] = "%s keeps its position (not redeployed)" % unit_name

	# Check if we need to switch players or complete
	_check_redeploy_progression()

	return create_result(true, [])

func _process_end_redeployment_phase(action: Dictionary) -> Dictionary:
	# WP-G1: "Done Redeploying" — the ACTIVE player declines the rest of their
	# redeployments (those units keep their deployed positions). If the
	# opponent still has redeployments to resolve, the step passes to them
	# (core rules: players alternate); otherwise the step ends.
	var player := get_current_player()
	for unit_id in redeploy_units_pending.get(player, []):
		if not redeploy_units_completed.has(unit_id):
			redeploy_units_completed.append(unit_id)
	redeploy_units_pending[player] = []
	for unit_id in active_redeploy.keys():
		if int(get_unit(unit_id).get("owner", 0)) == player:
			active_redeploy.erase(unit_id)
	var other := 3 - player
	action["_log_text"] = "Done redeploying"
	if redeploy_units_pending.get(other, []).size() > 0:
		GameState.set_active_player(other)
		game_state_snapshot = GameState.create_snapshot()
		log_phase_message("Player %d is done redeploying — Player %d resolves their redeployments" % [player, other])
		return create_result(true, [])
	log_phase_message("Redeployment phase ending")
	redeploy_units_pending.clear()
	active_redeploy.clear()
	emit_signal("phase_completed")
	return create_result(true, [])

# ---- Send to Strategic Reserves (redeploy enhancements) ----
# Castellan's Mark / Kaptin's Hat / Razgit's Magik Map: "you can set those
# units up in strategic reserves, regardless of how many units are already in
# strategic reserves" — no reserves cap is checked here.

func _validate_send_to_reserves(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	var errors := _validate_redeploy_candidate(unit_id)
	if not errors.is_empty():
		return {"valid": false, "errors": errors}

	# Must be a redeploy-enhancement unit, not a unit with a native redeploy
	# ability (those rules only re-place the unit on the battlefield).
	if _is_ability_redeploy(unit_id):
		return {"valid": false, "errors": ["Only units redeployed with a redeploy enhancement can be set up in Strategic Reserves"]}

	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr or not faction_mgr.is_razgit_redeploy_available(get_current_player()):
		return {"valid": false, "errors": ["No enhancement redeployment slots remaining"]}

	return {"valid": true, "errors": []}

func _process_send_to_reserves(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", ""))
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = int(unit.get("owner", 0))

	# WP-G1: the unit (with its attached CHARACTERs) goes into STRATEGIC
	# RESERVES — status IN_RESERVES + reserve_type, exactly like a unit
	# declared into reserves, so it arrives from Strategic Reserves later. The
	# old code set UNDEPLOYED, which no reserves-arrival path ever lists.
	var changes = []
	for uid in _redeploy_group_unit_ids(unit_id):
		changes.append({"op": "set", "path": "units.%s.status" % uid, "value": GameStateData.UnitStatus.IN_RESERVES})
		changes.append({"op": "set", "path": "units.%s.reserve_type" % uid, "value": "strategic_reserves"})
		var models = GameState.get_unit(uid).get("models", [])
		for i in range(models.size()):
			changes.append({"op": "set", "path": "units.%s.models.%d.position" % [uid, i], "value": null})

	# Apply changes
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	_apply_changes_to_local_state(changes)

	# Mark the enhancement redeploy as used
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	var enh_label = "REDEPLOY ENHANCEMENT"
	if faction_mgr:
		faction_mgr.mark_razgit_redeploy_used(player)
		var enh_name = faction_mgr.get_redeploy_enhancement_name(player)
		if enh_name != "":
			enh_label = enh_name.to_upper()

	# Mark unit as completed
	_mark_redeploy_complete(unit_id)
	_drop_unusable_enhancement_units(player)

	log_phase_message("%s: %s sent to Strategic Reserves" % [enh_label, unit_name])

	# Check progression
	_check_redeploy_progression()

	return create_result(true, changes)

# ========================================
# Helper Methods
# ========================================

func _mark_redeploy_complete(unit_id: String) -> void:
	redeploy_units_completed.append(unit_id)

	# Remove from pending lists
	for player in redeploy_units_pending:
		var pending = redeploy_units_pending[player]
		var idx = pending.find(unit_id)
		if idx >= 0:
			pending.remove_at(idx)

func _check_redeploy_progression() -> void:
	"""Check if all redeploy for current player is done, and switch/complete accordingly.
	Phase completion is handled by BasePhase via _should_complete_phase()."""
	var current_player = get_current_player()
	var current_pending = redeploy_units_pending.get(current_player, [])

	if current_pending.size() == 0:
		# Current player is done with redeployment
		var other_player = 3 - current_player
		var other_pending = redeploy_units_pending.get(other_player, [])

		if other_pending.size() > 0:
			# Switch to other player for their redeployment
			GameState.set_active_player(other_player)
			# Update local snapshot
			game_state_snapshot = GameState.create_snapshot()
			log_phase_message("Player %d redeployment complete, switching to Player %d" % [current_player, other_player])
		else:
			# All redeployment done — BasePhase._should_complete_phase() will emit phase_completed
			log_phase_message("All redeployment complete")

## WP-G1: what the Redeployment step UI lists for `player`:
## {enhancement, uses_left, opponent_pending,
##  units: [{unit_id, name, label, models, ability, can_redeploy, can_reserve, infiltrators}]}
func get_redeploy_menu(player: int) -> Dictionary:
	var fam = get_node_or_null("/root/FactionAbilityManager")
	var enh_name := ""
	var enh_keywords: Array = []
	if fam and fam.has_razgit_magik_map(player):
		var entry: Dictionary = fam.get_redeploy_enhancement(player)
		enh_name = str(entry.get("name", ""))
		enh_keywords = entry.get("keywords", []).duplicate()
	var uses_left := _enhancement_uses_left(player)
	var rows: Array = []
	for raw in redeploy_units_pending.get(player, []):
		var uid := str(raw)
		var u = GameState.get_unit(uid)
		if u.is_empty():
			continue
		var ability := _is_ability_redeploy(uid)
		var names: Array = []
		for gid in _redeploy_group_unit_ids(uid):
			var gm: Dictionary = GameState.get_unit(str(gid)).get("meta", {})
			names.append(str(gm.get("display_name", gm.get("name", gid))))
		rows.append({
			"unit_id": uid,
			"name": names[0],
			"label": " + ".join(names),
			"models": _redeploy_group_models(uid).size(),
			"ability": ability,
			"can_redeploy": ability or uses_left > 0,
			"can_reserve": (not ability) and uses_left > 0,
			"infiltrators": GameState.unit_has_infiltrators(uid),
		})
	return {"enhancement": enh_name, "keywords": enh_keywords, "uses_left": uses_left, "units": rows,
		"opponent_pending": redeploy_units_pending.get(3 - player, []).size()}

func _apply_changes_to_local_state(changes: Array) -> void:
	for change in changes:
		_apply_single_change_to_local(change)
	# Also refresh from GameState to stay in sync
	game_state_snapshot = GameState.create_snapshot()

func _apply_single_change_to_local(change: Dictionary) -> void:
	match change.get("op", ""):
		"set":
			_set_local_value(change.path, change.value)

func _set_local_value(path: String, value) -> void:
	var parts = path.split(".")
	var current = game_state_snapshot

	for i in range(parts.size() - 1):
		var part = parts[i]
		if part.is_valid_int():
			var index = part.to_int()
			if current is Array and index >= 0 and index < current.size():
				current = current[index]
			else:
				return
		else:
			if current is Dictionary and current.has(part):
				current = current[part]
			else:
				return

	var final_key = parts[-1]
	if final_key.is_valid_int():
		var index = final_key.to_int()
		if current is Array and index >= 0 and index < current.size():
			current[index] = value
	else:
		if current is Dictionary:
			current[final_key] = value

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var pending = redeploy_units_pending.get(current_player, [])

	# OA-2: Check if Razgit's Magik Map redeployments remain
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	var razgit_remaining = 0
	if faction_mgr:
		razgit_remaining = faction_mgr.get_razgit_redeploys_remaining(current_player)

	for unit_id in pending:
		var unit = get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)

		# OA-2: Check if this is a Razgit's unit and if slots remain
		var is_razgit_unit = not _is_ability_redeploy(unit_id)
		if is_razgit_unit and razgit_remaining <= 0:
			# No Razgit's slots left, skip this unit
			continue

		# Can begin a redeploy
		if not active_redeploy.has(unit_id):
			actions.append({
				"type": "BEGIN_REDEPLOY",
				"unit_id": unit_id,
				"description": "Redeploy %s" % unit_name
			})

			# OA-2: Razgit's Magik Map / Encircling Hunter — offer sending to
			# Strategic Reserves
			if is_razgit_unit and faction_mgr and faction_mgr.has_razgit_magik_map(current_player):
				actions.append({
					"type": "SEND_TO_STRATEGIC_RESERVES",
					"unit_id": unit_id,
					"description": "%s: Send %s to Strategic Reserves" % [faction_mgr.get_redeploy_enhancement_name(current_player), unit_name]
				})

		# Can skip the redeploy
		actions.append({
			"type": "SKIP_REDEPLOY",
			"unit_id": unit_id,
			"description": "Skip redeployment for %s" % unit_name
		})

	# If there are active redeploys, offer confirm
	for unit_id in active_redeploy:
		var unit = get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		actions.append({
			"type": "CONFIRM_REDEPLOY",
			"unit_id": unit_id,
			"description": "Confirm redeployment for %s" % unit_name
		})

	# If all pending are done, offer end phase
	var total_pending = 0
	for player in redeploy_units_pending:
		total_pending += redeploy_units_pending[player].size()

	if total_pending == 0 and active_redeploy.size() == 0:
		actions.append({
			"type": "END_REDEPLOYMENT_PHASE",
			"description": "End Redeployment Phase"
		})

	return actions

func _should_complete_phase() -> bool:
	var total_pending = 0
	for player in redeploy_units_pending:
		total_pending += redeploy_units_pending[player].size()
	return total_pending == 0 and active_redeploy.size() == 0

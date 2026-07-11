extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# MissionManager - Handles mission objectives, control, and victory point scoring
# Supports multiple primary missions via MissionData registry

signal objective_control_changed(objective_id: String, controller: int, old_controller: int)
signal victory_points_scored(player: int, points: int, reason: String)
# 11e GDM card-action marker state changed (Triangulated/Decoy/traps/...)
# — board overlays and HUD panels refresh on this.
signal card_action_state_changed()
signal objective_removed(objective_id: String)
signal objective_burned(objective_id: String, player: int)
signal objective_burn_started(objective_id: String, player: int)
signal objective_burn_completed(objective_id: String, player: int)

var current_mission: Dictionary = {}
var objective_control_state: Dictionary = {} # objective_id -> controlling_player
# objective_id -> true when BOTH players have models in range with equal,
# nonzero OC (a genuine stand-off). Distinct from merely uncontrolled (nobody
# in range). Only meaningful while objective_control_state == 0 — lets the UI
# label the marker "CONTESTED" vs "Uncontrolled" honestly (mek-contested bug).
var objective_contested_state: Dictionary = {}
var objectives_visual_refs: Dictionary = {} # Store references to visual nodes

# Sticky objective tracking — objectives locked by abilities like "Get Da Good Bitz" / "Objective Secured"
# Key: objective_id, Value: { "player": int, "source_unit_id": String }
var _sticky_objectives: Dictionary = {}

# Kill tracking for Purge the Foe
var _kills_this_round: Dictionary = {"1": 0, "2": 0}  # player_key -> units destroyed this round

# Burn tracking for Scorched Earth — objectives burned and removed from play
# Key: objective_id, Value: { "player": int, "unit_id": String, "zone": String }
var _burned_objectives: Dictionary = {}

# Units that have been designated to burn an objective this turn (Shooting phase)
# Key: unit_id, Value: objective_id — resolves at end of Command phase
var _pending_burns: Dictionary = {}

# Ritual action tracking for The Ritual mission
# Key: objective_id, Value: { "player": int, "unit_id": String, "round_created": int }
var _ritual_objectives: Dictionary = {}

# Units performing ritual actions this turn (Shooting phase)
# Key: unit_id, Value: objective_id — action completes at end of turn
var _pending_rituals: Dictionary = {}

# Terraform tracking — objectives that have been terraformed by a player
# Key: objective_id, Value: player (1 or 2) who terraformed it
var _terraformed_objectives: Dictionary = {}

# Units performing terraform actions this turn (Shooting phase)
# Key: unit_id, Value: objective_id — action completes at end of turn
var _pending_terraforms: Dictionary = {}

# P3-128: VP timeline tracking — cumulative VP snapshots per round per player
# Structure: { round_number: { "1": {total, primary, secondary}, "2": {total, primary, secondary} } }
var _vp_timeline: Dictionary = {}

# --- Scorched Earth state (incoming branch) ---
# objective_id -> { "player": int, "started_round": int }
var burn_in_progress: Dictionary = {}
var burned_objectives: Array = []  # IDs of objectives that have been burned and removed

# --- Supply Drop state ---
var removed_objectives: Array = []  # IDs of NML objectives removed in later rounds
var supply_drop_resolved_round_4: bool = false

# --- Purge the Foe state ---
# Tracks unit kills per player per battle round: { round_str: { "1": count, "2": count } }
var kills_per_round: Dictionary = {}

# --- Sites of Power state ---
# Tracks which objectives have been claimed by a character: objective_id -> { "player": int, "claimed_round": int }
var character_claimed_objectives: Dictionary = {}

# --- 11e GDM 2026 Force Disposition primary missions ---
# player_key ("1"/"2") -> disposition id ("take_and_hold" | "purge_the_foe" |
# "reconnaissance" | "priority_assets" | "disruption")
var player_dispositions: Dictionary = {}
# player_key -> resolved primary mission card (own deck vs opponent disposition)
var player_primary_missions: Dictionary = {}
# player_key -> primary VP scored in the current turn window (15/turn cap)
var _primary_vp_this_turn: Dictionary = {"1": 0, "2": 0}
# player_key -> Array of objective ids controlled at the start of their turn
# (for "hold an objective you didn't start your turn with" conditions)
var _control_at_turn_start: Dictionary = {}
# One-shot guard so end-of-game conditions only score once
var _eog_primary_scored: bool = false
# Action-type components we've already warned about (log once per game)
var _warned_unimplemented_actions: Dictionary = {}
# Per-player marker/action state for the card mechanics (awards sourced
# from data/40kdc/missionCards.json). Auto-resolved backstop: the real cards
# let the player pick targets; we pick deterministically and the prompts let
# a human revise the picks.
# player_key -> { triangulated: [obj_id], consecrated: [obj_id],
#   decoyed: [obj_id], decoyed_ever: [obj_id], trapped: [terrain_id],
#   trapped_this_turn: [terrain_id], operation_markers: int,
#   intel_tokens: [obj_id], intel_placed_this_turn: int,
#   condemned: [unit_id], condemned_left_this_turn: bool,
#   sensor_swept_this_turn: bool }
var _primary_state_11e: Dictionary = {}
# Shared relic/operation markers for the Extract Relic / Locate and Deny
# pairing: terrain feature ids still carrying a marker
var _relic_markers_11e: Array = []
# The real card lets the DISRUPTION player choose the five marked areas at
# mission start; the auto-pick stands as backstop and a human DI player may
# revise it during their first Command phase while this is set.
var _relic_setup_prompt_pending: bool = false
# player_key (turn owner) -> {unit_id: true} units on the battlefield at
# the start of that player's turn (for left-battlefield / destroyed checks)
var _alive_at_turn_start_11e: Dictionary = {}

func _ready() -> void:
	print("MissionManager: Initializing mission system")
	initialize_default_mission()
	# ISS-055 (11e 14.02): "At the end of each phase and turn", determine
	# each player's level of control over every objective. Wired to the
	# phase machine; edition-gated so 10e keeps its event-driven updates.
	if has_node("/root/PhaseManager"):
		var pm = get_node("/root/PhaseManager")
		if pm.has_signal("phase_completed") and not pm.phase_completed.is_connected(_on_phase_completed_11e):
			pm.phase_completed.connect(_on_phase_completed_11e)
		if pm.has_signal("turn_ending") and not pm.turn_ending.is_connected(_on_turn_ending_11e):
			pm.turn_ending.connect(_on_turn_ending_11e)

func _on_phase_completed_11e(_phase) -> void:
	if GameConstants.edition >= 11:
		check_all_objectives()

func _on_turn_ending_11e(_player: int) -> void:
	if GameConstants.edition >= 11:
		check_all_objectives()

## ISS-055 (11e 14.03): public Secured-objective API. An objective secured
## by a player's army stays under their control — even with no units in
## range — until the opponent's level of control exceeds theirs at the end
## of a phase. Reuses the proven sticky-objective mechanism the faction
## abilities (Get da Good Bitz / Vigilance Eternal) already exercise.
func secure_objective(obj_id: String, player: int, source_unit_id: String = "") -> void:
	_sticky_objectives[obj_id] = {"player": player, "source_unit_id": source_unit_id}
	if objective_control_state.get(obj_id, 0) == 0:
		objective_control_state[obj_id] = player
	print("MissionManager: objective %s SECURED by player %d (14.03)" % [obj_id, player])

func is_objective_secured(obj_id: String) -> Dictionary:
	if _sticky_objectives.has(obj_id):
		return {"secured": true, "player": _sticky_objectives[obj_id].player}
	return {"secured": false, "player": 0}

func initialize_default_mission() -> void:
	# Check if a mission was specified in the game config
	var mission_id = _get_configured_mission_id()
	initialize_mission(mission_id)

func _get_configured_mission_id() -> String:
	var config = GameState.state.get("meta", {}).get("game_config", {})
	var mission_id = config.get("mission", "take_and_hold")
	print("MissionManager: Configured mission ID: %s" % mission_id)
	return mission_id

func initialize_mission(mission_id: String) -> void:
	# Load mission data from registry
	var mission_data = MissionData.get_mission(mission_id)
	if mission_data.is_empty():
		print("MissionManager: Unknown mission '%s', falling back to take_and_hold" % mission_id)
		mission_data = MissionData.get_mission("take_and_hold")
		mission_id = "take_and_hold"

	current_mission = mission_data.duplicate(true)

	# Also store scoring rules in a flat reference for compatibility
	if not current_mission.has("scoring_rules"):
		current_mission["scoring_rules"] = current_mission.get("scoring", {}).duplicate(true)

	# Reset mission-specific state
	burn_in_progress.clear()
	burned_objectives.clear()
	removed_objectives.clear()
	supply_drop_resolved_round_4 = false
	kills_per_round.clear()
	character_claimed_objectives.clear()

	# Initialize objectives based on deployment type
	var deployment_type = GameState.get_deployment_type()
	_setup_objectives_for_deployment(deployment_type)

	# Reset kill tracking
	_kills_this_round = {"1": 0, "2": 0}

	# Reset burn tracking
	_burned_objectives.clear()
	_pending_burns.clear()

	# P3-128: Reset VP timeline
	_vp_timeline.clear()

	# Reset ritual tracking
	_ritual_objectives.clear()
	_pending_rituals.clear()

	# Reset terraform tracking
	_terraformed_objectives.clear()
	_pending_terraforms.clear()

	# Store mission type in GameState meta for reference
	GameState.state.meta["mission_type"] = mission_id

	# 11e GDM 2026: primary missions come from the Force Disposition pairing
	# table instead of the shared 10e mission card. The 10e current_mission is
	# still initialized above (objectives, control tracking, UI compatibility);
	# only the SCORING dispatch is replaced at e11.
	if GameConstants.edition >= 11:
		var config = GameState.state.get("meta", {}).get("game_config", {})
		initialize_dispositions_11e(
			str(config.get("player1_disposition", "take_and_hold")),
			str(config.get("player2_disposition", "take_and_hold")))

	print("MissionManager: Initialized '%s' mission (scoring_type: %s)" % [current_mission.name, current_mission.scoring_type])

func _setup_objectives_for_deployment(deployment_type: String) -> void:
	# D3-a (docs/40KDC_TERRAIN_MIGRATION_SPEC.md): the converted official 11e
	# terrain layouts author their own objective markers (per-matchup
	# placement from the GW card). Prefer those when the loaded layout
	# carries them; legacy layouts fall back to the deployment-zone data.
	var objectives = []
	var tm_d3 = get_node_or_null("/root/TerrainManager")
	if tm_d3 != null and not tm_d3.layout_objectives.is_empty():
		for obj in tm_d3.layout_objectives:
			var pos = obj.get("position", [0, 0])
			objectives.append({
				"id": str(obj.get("id", "")),
				"position": Vector2(
					Measurement.inches_to_px(float(pos[0])),
					Measurement.inches_to_px(float(pos[1]))),
				"radius_mm": int(obj.get("radius_mm", 40)),
				"zone": str(obj.get("zone", "no_mans_land")),
				# 14.01: the terrain areas that ARE this objective (the
				# linked centre pair lists both areas).
				"source_pieces": obj.get("source_pieces", []).duplicate()
			})
		print("MissionManager: Using %d layout-sourced objectives from terrain layout '%s' (D3-a)" % [objectives.size(), tm_d3.current_layout])
	else:
		# Get objective positions from centralized data source (already in pixels)
		objectives = DeploymentZoneData.get_objectives_px(deployment_type)

	# Store objectives in GameState
	GameState.state.board["objectives"] = objectives

	# Initialize control state
	objective_control_state.clear()
	objective_contested_state.clear()
	_sticky_objectives.clear()
	for obj in objectives:
		objective_control_state[obj.id] = 0  # 0 = contested/uncontrolled

	# 11e GDM: Chapter Approved objective designations — Home (one per
	# deployment zone), Central (nearest the board centre), Expansion (the
	# remaining NML objectives). Assigned for all editions; only 11e reads it.
	_assign_objective_designations(objectives)

	print("MissionManager: Set up %d objectives for %s deployment" % [objectives.size(), deployment_type])
	for obj in objectives:
		print("  - %s at position %s (zone: %s, designation: %s)" % [obj.id, obj.position, obj.get("zone", "unknown"), obj.get("designation", "?")])

func _assign_objective_designations(objectives: Array) -> void:
	var board_size = GameState.state.get("board", {}).get("size", {})
	var center = Vector2(
		Measurement.inches_to_px(float(board_size.get("width", 44)) / 2.0),
		Measurement.inches_to_px(float(board_size.get("height", 60)) / 2.0))
	var central_id = ""
	var best_dist = INF
	for obj in objectives:
		if obj.get("zone", "") != "no_mans_land":
			obj["designation"] = "home"
			continue
		var pos = obj.get("position")
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		var d = pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			central_id = obj.get("id", "")
	for obj in objectives:
		if obj.get("zone", "") == "no_mans_land":
			obj["designation"] = "central" if obj.get("id", "") == central_id else "expansion"

func get_objective_designation(obj_id: String) -> String:
	return _get_objective_by_id(obj_id).get("designation", "")

func get_objective_ids_by_designation(designation: String) -> Array:
	var out = []
	for obj in GameState.state.board.get("objectives", []):
		if obj.get("designation", "") == designation:
			out.append(obj.get("id", ""))
	return out

# ============================================================
# OBJECTIVE CONTROL (shared by all missions)
# ============================================================

func check_all_objectives() -> void:
	var objectives = GameState.state.board.get("objectives", [])

	# If objectives are missing, reinitialize them
	if objectives.size() == 0:
		print("MissionManager: No objectives found, reinitializing...")
		var deployment_type = GameState.get_deployment_type()
		_setup_objectives_for_deployment(deployment_type)
		objectives = GameState.state.board.get("objectives", [])

	var units = GameState.state.get("units", {})

	print("MissionManager: Checking control for %d objectives with %d units" % [objectives.size(), units.size()])

	for obj in objectives:
		# Skip removed/burned objectives
		if obj.id in removed_objectives or obj.id in burned_objectives:
			continue

		print("\nChecking objective: %s at position %s" % [obj.id, obj.position])
		var old_contested = objective_contested_state.get(obj.id, false)
		var controller = _check_objective_control(obj, units)
		var old_controller = objective_control_state.get(obj.id, 0)
		var contested = objective_contested_state.get(obj.id, false)

		# Also fire on a contested-flag flip with an unchanged controller
		# (uncontrolled <-> genuinely contested, both controller 0) so the
		# board label stays honest.
		if controller != old_controller or contested != old_contested:
			objective_control_state[obj.id] = controller
			emit_signal("objective_control_changed", obj.id, controller, old_controller)
			print("MissionManager: %s control changed from %d to %d%s" % [obj.id, old_controller, controller, " (contested)" if contested else ""])

## ISS-055 / D3-a: the terrain areas hosting an objective (14.01: those
## areas ARE the objective). Layout-sourced objectives name their areas via
## source_pieces — the linked centre pair counts as ONE objective spanning
## both areas. Objectives without source_pieces (deployment-zone data, old
## saves) fall back to the single area containing the marker, if any.
func _objective_host_areas(objective: Dictionary) -> Array:
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return []
	var areas: Array = []
	for piece_id in objective.get("source_pieces", []):
		for piece in tm.terrain_features:
			if str(piece.get("id", "")) == str(piece_id) and str(piece.get("piece_class", "")) == "area":
				areas.append(piece)
				break
	if areas.is_empty() and tm.has_method("area_at"):
		var obj_pos = objective.position
		if obj_pos is Dictionary:
			obj_pos = Vector2(obj_pos.x, obj_pos.y)
		var hit = tm.area_at(obj_pos)
		if not hit.is_empty():
			areas.append(hit)
	return areas

## Shared "is this model within range of this objective" predicate — used by
## objective control, sticky-objective locking and nearest-objective lookup so
## they can never disagree.
## - Terrain-hosted objectives (11e 14.01, host_areas non-empty): the hosting
##   AREAS are the objective — a model is in range as soon as ANY part of its
##   base overlaps any of them (shape-aware; a base half on the area counts,
##   its centre point does not need to be inside — mek-contested bug).
## - Open ground (host_areas empty): any part of the base within the classic
##   3" + 20mm-marker-radius of the marker centre.
func _model_in_objective_range(model: Dictionary, objective: Dictionary, host_areas: Array) -> bool:
	if not host_areas.is_empty():
		for host_area in host_areas:
			if Measurement.model_overlaps_polygon(model, host_area.get("polygon", PackedVector2Array())):
				return true
		return false
	var obj_pos = objective.get("position", Vector2.ZERO)
	if obj_pos is Dictionary:
		obj_pos = Vector2(obj_pos.x, obj_pos.y)
	var control_radius = Measurement.inches_to_px(3.78740157)
	return Measurement.model_edge_to_point_distance_px(model, obj_pos) <= control_radius

## True when the objective is actively contested — both players have models in
## range with equal, nonzero OC — as opposed to merely uncontrolled (nobody in
## range). UI labels read this to avoid claiming "CONTESTED" over an empty or
## one-sided marker.
func is_objective_contested(obj_id: String) -> bool:
	return objective_control_state.get(obj_id, 0) == 0 and objective_contested_state.get(obj_id, false)

func _check_objective_control(objective: Dictionary, units: Dictionary) -> int:
	# Control radius is 3" + 20mm (radius of objective marker)
	# 20mm = 0.78740157 inches, so total is 3.78740157 inches
	var control_radius = Measurement.inches_to_px(3.78740157)
	var obj_pos = objective.position

	# 14.01: hoisted per-objective — the hosting terrain area(s), if any.
	var host_areas_11e: Array = []
	if GameConstants.edition >= 11:
		host_areas_11e = _objective_host_areas(objective)

	var player1_oc = 0
	var player2_oc = 0
	var units_in_range = []

	for unit_id in units:
		var unit = units[unit_id]
		var owner = unit.get("owner", 0)

		# Skip if unit has no OC value
		# OA-46: Check for OC override (Da Boss Iz Watchin' during Waaagh!)
		var oc_value = unit.get("flags", {}).get("effect_oc_override", 0)
		if oc_value == 0:
			oc_value = unit.get("meta", {}).get("stats", {}).get("objective_control", 0)
		# DAT'S OURS (Taktikal Brigade): additive OC bonus, applied on top of the
		# statline/override value (a base OC of 0 still controls nothing).
		if oc_value > 0:
			oc_value += int(unit.get("flags", {}).get(EffectPrimitivesData.FLAG_PLUS_OC, 0))
		if oc_value <= 0:
			print("  Skipping %s - no OC value (OC: %d)" % [unit_id, oc_value])
			continue

		# Check if unit is battle-shocked
		if unit.get("flags", {}).get("battle_shocked", false):
			print("  Skipping %s - battle shocked" % unit_id)
			continue

		# Check if unit has deployed status
		var status = unit.get("status", GameStateData.UnitStatus.UNDEPLOYED)
		if status == GameStateData.UnitStatus.UNDEPLOYED:
			print("  Skipping %s - not deployed (status: %d)" % [unit_id, status])
			continue

		print("  Checking unit %s (Player %d, OC: %d, %d models)" % [
			unit_id, owner, oc_value, unit.get("models", []).size()
		])

		# Check each model in the unit
		var unit_counted = false
		for model in unit.get("models", []):
			if unit_counted:
				break

			if not model.get("alive", true):
				continue

			var model_pos = model.get("position")
			if model_pos == null:
				continue

			# Convert position if needed
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.x, model_pos.y)

			# A model is within range of an objective if any part of its base
			# is within the control radius. Use shape-aware distance to correctly
			# handle oval and rectangular bases (not just circular).
			# ISS-055 (11e 14.01/14.02): if terrain area(s) host the
			# objective, those AREAS are the objective — a model is in range
			# while WITHIN any of them (not the marker radius). "Within" is
			# any part of the base overlapping the area (shape-aware), NOT the
			# centre point — a base half on the area counts (mek-contested
			# bug). The linked centre pair of the official layouts spans two
			# areas that count as one objective (source_pieces). Falls through
			# to the marker radius on open ground.
			if GameConstants.edition >= 11 and not host_areas_11e.is_empty():
				if _model_in_objective_range(model, objective, host_areas_11e):
					units_in_range.append("%s (Player %d, OC: %d, terrain objective)" % [unit_id, owner, oc_value])
					if owner == 1:
						player1_oc += oc_value
					elif owner == 2:
						player2_oc += oc_value
					unit_counted = true
					print("    -> Base overlaps the TERRAIN OBJECTIVE area (14.01)! Adding OC: %d for Player %d at %s" % [oc_value, owner, model_pos])
				continue

			var edge_distance = Measurement.model_edge_to_point_distance_px(model, obj_pos)
			var edge_distance_inches = Measurement.px_to_inches(edge_distance)

			# Debug log for each model checked
			print("  Model from %s at %s, edge_distance: %.1f\" (%.1fpx), control_radius: %.1fpx, base_type: %s from %s at %s" % [
				unit_id, model_pos, edge_distance_inches, edge_distance, control_radius, model.get("base_type", "circular"), objective.id, obj_pos
			])

			if edge_distance <= control_radius:
				units_in_range.append("%s (Player %d, OC: %d)" % [unit_id, owner, oc_value])
				if owner == 1:
					player1_oc += oc_value
				elif owner == 2:
					player2_oc += oc_value
				unit_counted = true  # Only count unit once
				print("    -> Within control range! Adding OC: %d for Player %d" % [oc_value, owner])

	# Log units in range if any
	if units_in_range.size() > 0:
		print("MissionManager: Units within control range (3.79\") of %s:" % objective.id)
		for unit_desc in units_in_range:
			print("  - %s" % unit_desc)
		print("  Total OC - Player 1: %d, Player 2: %d" % [player1_oc, player2_oc])

	# Determine controller based on OC
	var oc_controller = 0
	if player1_oc > player2_oc:
		oc_controller = 1
	elif player2_oc > player1_oc:
		oc_controller = 2

	# Genuinely contested = tied, nonzero OC from both sides. A 0-0 "tie"
	# (nobody in range) is merely uncontrolled. Sticky paths below may still
	# return a controller; is_objective_contested() guards on controller == 0.
	objective_contested_state[objective.get("id", "")] = (oc_controller == 0 and player1_oc > 0)

	# If a player actively controls via OC, that overrides any sticky lock
	# (opponent "controls it at the start or end of any turn" breaks sticky)
	if oc_controller > 0:
		# If the opponent now controls via OC, clear any sticky lock
		var obj_id = objective.get("id", "")
		if _sticky_objectives.has(obj_id) and _sticky_objectives[obj_id].player != oc_controller:
			print("MissionManager: Sticky lock on %s broken — Player %d now controls via OC" % [obj_id, oc_controller])
			_sticky_objectives.erase(obj_id)
		# Issue #392 VIGILANCE ETERNAL: also clear the per-unit flag for any
		# unit holding a sticky lock on this objective from the losing side.
		for unit_id in GameState.state.get("units", {}):
			var unit = GameState.state.units[unit_id]
			if unit.get("flags", {}).get("effect_sticky_objective_control", "") == obj_id and int(unit.get("owner", 0)) != oc_controller:
				unit.flags.erase("effect_sticky_objective_control")
				print("MissionManager: VIGILANCE ETERNAL flag cleared on %s — Player %d now controls %s" % [unit_id, oc_controller, obj_id])
		return oc_controller

	# No one has OC presence — check for sticky lock
	var obj_id = objective.get("id", "")
	if _sticky_objectives.has(obj_id):
		var sticky_data = _sticky_objectives[obj_id]
		var sticky_player = sticky_data.player
		var source_unit_id = sticky_data.source_unit_id

		# Verify the source unit is still alive on the battlefield.
		# ISS-055 (11e 14.03): an objective secured BY THE ARMY (empty
		# source_unit_id) persists regardless of any unit's survival — only
		# a greater enemy level of control breaks it.
		var source_unit = GameState.state.get("units", {}).get(source_unit_id, {})
		var source_alive = source_unit_id == ""
		for model in source_unit.get("models", []):
			if model.get("alive", true):
				source_alive = true
				break

		if source_alive:
			print("MissionManager: %s remains under Player %d control via sticky objective (source: %s)" % [obj_id, sticky_player, source_unit_id])
			return sticky_player
		else:
			print("MissionManager: Sticky lock on %s expired — source unit %s is destroyed" % [obj_id, source_unit_id])
			_sticky_objectives.erase(obj_id)

	# Issue #392 VIGILANCE ETERNAL: also honour the per-unit
	# effect_sticky_objective_control flag. Survives save/load even when the
	# in-memory _sticky_objectives dict is empty after a load.
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		var locked_obj_id = unit.get("flags", {}).get("effect_sticky_objective_control", "")
		if locked_obj_id != obj_id:
			continue
		var unit_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				unit_alive = true
				break
		if not unit_alive:
			continue
		var locking_player = int(unit.get("owner", 0))
		print("MissionManager: %s remains under Player %d control via VIGILANCE ETERNAL flag (source: %s)" % [obj_id, locking_player, unit_id])
		return locking_player

	return 0  # Contested or uncontrolled

# ============================================================================
# STICKY OBJECTIVES — "Get Da Good Bitz", "Objective Secured", etc.
# ============================================================================
# At the end of the Command phase, if a unit with a sticky objective ability
# is within range of an objective marker you control, that objective remains
# under your control even if you have no models within range, until the
# opponent controls it at the start or end of any turn.

func apply_sticky_objectives(player: int) -> void:
	"""Called at end of Command phase. Locks objectives controlled by the player
	where a unit with a sticky objective ability is within range."""
	var objectives = GameState.state.board.get("objectives", [])
	var units = GameState.state.get("units", {})

	var unit_ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not unit_ability_mgr:
		print("MissionManager: UnitAbilityManager not available — skipping sticky objectives")
		return

	for obj in objectives:
		var obj_id = obj.get("id", "")
		var controller = objective_control_state.get(obj_id, 0)

		# Only apply sticky to objectives the player currently controls
		if controller != player:
			continue

		# ISS-055 / 14.01: on terrain-hosted objectives (11e) "within range"
		# means on the hosting area(s), mirroring _check_objective_control.
		var host_areas: Array = []
		if GameConstants.edition >= 11:
			host_areas = _objective_host_areas(obj)

		# Check if any unit with sticky objective ability is within range
		for unit_id in units:
			var unit = units[unit_id]
			if unit.get("owner", 0) != player:
				continue

			# Check if unit has a sticky objective ability
			if not unit_ability_mgr.has_sticky_objectives_ability(unit_id):
				continue

			# Skip battle-shocked units (they don't contribute to OC or abilities)
			if unit.get("flags", {}).get("battle_shocked", false):
				continue

			# Check if any alive model is within range of the objective
			# (any part of the base overlapping counts — shape-aware for oval/rect bases)
			var unit_in_range = false
			for model in unit.get("models", []):
				if not model.get("alive", true):
					continue
				if model.get("position") == null:
					continue
				if _model_in_objective_range(model, obj, host_areas):
					unit_in_range = true
					break

			if unit_in_range:
				_sticky_objectives[obj_id] = {"player": player, "source_unit_id": unit_id}
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				print("MissionManager: Sticky objective — %s locked by %s (%s) for Player %d" % [obj_id, unit_name, unit_id, player])
				break  # Only need one qualifying unit per objective

func clear_sticky_objectives_for_player(player: int) -> void:
	"""Clear all sticky locks for a player. Called if needed for game reset."""
	var to_erase = []
	for obj_id in _sticky_objectives:
		if _sticky_objectives[obj_id].player == player:
			to_erase.append(obj_id)
	for obj_id in to_erase:
		_sticky_objectives.erase(obj_id)
	if to_erase.size() > 0:
		print("MissionManager: Cleared %d sticky objective(s) for Player %d" % [to_erase.size(), player])

func get_sticky_objectives() -> Dictionary:
	"""Get current sticky objective state (for save/load and debugging)."""
	return _sticky_objectives.duplicate(true)

# Issue #392: VIGILANCE ETERNAL stratagem — manual lock by stratagem use.
# Differs from `apply_sticky_objectives` which scans for units with the
# has_sticky_objectives_ability datasheet rule; this lets a stratagem set
# a single objective lock for the named unit.
func lock_objective_via_stratagem(obj_id: String, player: int, source_unit_id: String) -> bool:
	"""Lock an objective via a stratagem (e.g. VIGILANCE ETERNAL). Returns true if locked,
	false if obj_id is empty or the player doesn't currently control the objective."""
	if obj_id.is_empty():
		print("MissionManager: lock_objective_via_stratagem — empty obj_id, skipping")
		return false
	var current_controller = objective_control_state.get(obj_id, 0)
	if current_controller != player:
		print("MissionManager: lock_objective_via_stratagem — Player %d does not control %s (controller=%d)" % [player, obj_id, current_controller])
		return false
	_sticky_objectives[obj_id] = {"player": player, "source_unit_id": source_unit_id}
	print("MissionManager: VIGILANCE ETERNAL — locked %s under Player %d via %s" % [obj_id, player, source_unit_id])
	return true

func find_nearest_controlled_objective(unit_id: String) -> String:
	"""Find the objective_id of the nearest objective controlled by this unit's owner
	that has at least one alive model from the unit within control range. Returns ""
	if no qualifying objective is found."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return ""
	var owner = int(unit.get("owner", 0))
	var objectives = GameState.state.get("board", {}).get("objectives", [])
	var best_id = ""
	var best_distance = INF
	for obj in objectives:
		var obj_id = obj.get("id", "")
		if obj_id.is_empty():
			continue
		if objective_control_state.get(obj_id, 0) != owner:
			continue
		var obj_pos = obj.get("position")
		if obj_pos == null:
			continue
		if obj_pos is Dictionary:
			obj_pos = Vector2(obj_pos.x, obj_pos.y)
		# ISS-055 / 14.01: eligibility on terrain-hosted objectives (11e) is
		# base-on-area, mirroring _check_objective_control; candidates are
		# still ranked by distance to the marker point either way.
		var host_areas: Array = []
		if GameConstants.edition >= 11:
			host_areas = _objective_host_areas(obj)
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			if not _model_in_objective_range(model, obj, host_areas):
				continue
			var edge_distance = Measurement.model_edge_to_point_distance_px(model, obj_pos)
			if edge_distance < best_distance:
				best_distance = edge_distance
				best_id = obj_id
	return best_id

# ============================================================================
# PRIMARY SCORING — dispatches to mission-specific scoring logic
# ============================================================================

# ============================================================
# SCORING DISPATCH
# ============================================================

func score_primary_objectives() -> void:
	var battle_round = GameState.get_battle_round()
	var active_player = GameState.get_active_player()

	# 11e GDM 2026: score the active player's own disposition-paired card.
	# Command-phase conditions switch to end-of-turn scoring in Round 5, so
	# the Command-phase trigger is a no-op there (score_primary_eot_11e picks
	# them up instead).
	if GameConstants.edition >= 11 and not player_primary_missions.is_empty():
		if battle_round >= 5:
			print("MissionManager: 11e R5 — Command-phase primary scoring deferred to end of turn")
			return
		_score_primary_11e(active_player, battle_round, "command")
		return

	var start_round = current_mission.get("start_round", current_mission.get("scoring_rules", {}).get("start_round", 2))

	print("MissionManager: Checking primary scoring for Player %d in battle round %d (mission: %s)" % [active_player, battle_round, current_mission.name])

	# Check if scoring conditions are met
	if battle_round < start_round:
		print("MissionManager: No scoring before battle round %d" % start_round)
		return

	# Handle round-start events (objective removal for Supply Drop, burn completion for Scorched Earth)
	_process_round_start_events(battle_round, active_player)

	# Dispatch to mission-specific scoring
	var scoring_type = current_mission.get("scoring_type", "hold_objectives")
	match scoring_type:
		"hold_objectives":
			_score_hold_objectives(active_player, battle_round)
		"hold_and_kill":
			_score_hold_and_kill(active_player, battle_round)
		"supply_drop":
			_score_supply_drop(active_player, battle_round)
		"purge_the_foe":
			_score_purge_the_foe(active_player, battle_round)
		"sites_of_power":
			_score_sites_of_power(active_player, battle_round)
		"hold_and_burn":
			_score_hold_and_burn(active_player, battle_round)
		"ritual":
			_score_ritual(active_player, battle_round)
		"terraform":
			_score_terraform(active_player, battle_round)
		_:
			print("MissionManager: Unknown scoring type '%s', falling back to hold_objectives" % scoring_type)
			_score_hold_objectives(active_player, battle_round)

# ============================================================================
# TAKE AND HOLD / LINCHPIN / basic hold_objectives scoring
# ============================================================================

func _score_hold_objectives(active_player: int, _battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_obj = scoring_rules.get("vp_per_objective", 5)
	var center_bonus = scoring_rules.get("vp_center_bonus", 0)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 15)

	# Count controlled objectives (excluding removed/burned)
	var controlled_objectives = _get_controlled_objectives(active_player)

	var controlled_count = controlled_objectives.size()

	if controlled_count > 0:
		print("MissionManager: Player %d controls %d objectives: %s" % [active_player, controlled_count, controlled_objectives])
	else:
		print("MissionManager: Player %d controls no objectives" % active_player)

	# Calculate VP
	var vp_earned = controlled_count * vp_per_obj

	# Add center bonus if applicable (Linchpin)
	if center_bonus > 0 and "obj_center" in controlled_objectives:
		vp_earned += center_bonus
		print("MissionManager: Center objective bonus: +%d VP" % center_bonus)

	vp_earned = mini(vp_earned, max_per_turn)

	_apply_primary_vp(active_player, vp_earned, "Controlled %d objectives" % controlled_count)

# Alias for compatibility with incoming branch code
func _score_take_and_hold(active_player: int, battle_round: int) -> void:
	_score_hold_objectives(active_player, battle_round)

# ============================================================================
# PURGE THE FOE — hold objectives + destroy enemy units
# ============================================================================

func _score_hold_and_kill(active_player: int, _battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var hold_any_vp = scoring_rules.get("hold_any_vp", 4)
	var hold_more_vp = scoring_rules.get("hold_more_vp", 4)
	var kill_any_vp = scoring_rules.get("kill_any_vp", 4)
	var kill_more_vp = scoring_rules.get("kill_more_vp", 4)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 16)

	var opponent = 3 - active_player
	var vp_earned = 0
	var reasons = []

	# Holding component
	var player_objectives = _get_controlled_objectives(active_player).size()
	var opponent_objectives = _get_controlled_objectives(opponent).size()

	if player_objectives > 0:
		vp_earned += hold_any_vp
		reasons.append("holds %d objectives" % player_objectives)
	if player_objectives > opponent_objectives:
		vp_earned += hold_more_vp
		reasons.append("holds more than opponent")

	# Kill component — check both tracking systems
	var player_kills = _kills_this_round.get(str(active_player), 0)
	var opponent_kills = _kills_this_round.get(str(opponent), 0)

	# Also check the per-round kill tracking from incoming branch
	var round_key = str(_battle_round) if _battle_round > 0 else str(GameState.get_battle_round())
	var round_kills = kills_per_round.get(round_key, {})
	player_kills = max(player_kills, round_kills.get(str(active_player), 0))
	opponent_kills = max(opponent_kills, round_kills.get(str(opponent), 0))

	if player_kills > 0:
		vp_earned += kill_any_vp
		reasons.append("destroyed %d units" % player_kills)
	if player_kills > opponent_kills:
		vp_earned += kill_more_vp
		reasons.append("destroyed more than opponent")

	vp_earned = mini(vp_earned, max_per_turn)

	var reason_text = "; ".join(reasons) if reasons.size() > 0 else "No scoring conditions met"
	print("MissionManager: Purge the Foe - %s" % reason_text)
	_apply_primary_vp(active_player, vp_earned, reason_text)

# Alias for compatibility with incoming branch dispatch
func _score_purge_the_foe(active_player: int, battle_round: int) -> void:
	_score_hold_and_kill(active_player, battle_round)

# ============================================================================
# SUPPLY DROP — Only NML objectives score; remove one in Round 4
# ============================================================================

func _score_supply_drop(active_player: int, battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_obj = scoring_rules.get("vp_per_objective", 5)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 15)

	# Only count NML objectives (using helper method, respects removed_objectives)
	var controlled_nml = _get_controlled_nml_objectives(active_player)
	var controlled_count = controlled_nml.size()

	if controlled_count > 0:
		print("MissionManager: Supply Drop - Player %d controls %d NML objectives: %s" % [active_player, controlled_count, controlled_nml])
	else:
		print("MissionManager: Supply Drop - Player %d controls no NML objectives" % active_player)

	# Round 5 bonus: remaining NML objective is worth extra
	var removal_rules = current_mission.get("removal_rules", {})
	if battle_round >= 5 and controlled_count > 0:
		var bonus = removal_rules.get("round_5_bonus_vp", 10)
		var vp_earned = mini(controlled_count * vp_per_obj + bonus, max_per_turn)
		_apply_primary_vp(active_player, vp_earned, "Held %d supply drop objectives (+bonus)" % controlled_count)
	else:
		var vp_earned = mini(controlled_count * vp_per_obj, max_per_turn)
		_award_primary_vp(active_player, vp_earned, "Held %d supply drop objectives" % controlled_count)

func _process_round_start_events(battle_round: int, active_player: int) -> void:
	"""Handle round-start events like objective removal for Supply Drop."""
	if current_mission.get("scoring_type", "") == "supply_drop":
		_process_supply_drop_removal(battle_round, active_player)

func _process_supply_drop_removal(battle_round: int, active_player: int) -> void:
	"""Remove NML objectives at the start of round 4 for Supply Drop."""
	var removal_rules = current_mission.get("removal_rules", {})

	# Only process removal once, when the round's first-turn player scores in
	# round 4 (the start of round 4). NOT hardcoded to Player 1 — when the
	# roll-off gives Player 2 the first turn, round 4 begins on P2's turn.
	if battle_round == 4 and not supply_drop_resolved_round_4 and active_player == GameState.get_first_turn_player():
		var remove_count = removal_rules.get("round_4_remove_count", 1)
		var nml_objectives = _get_nml_objective_ids()

		# Remove objectives that haven't already been removed
		var available_for_removal = []
		for obj_id in nml_objectives:
			if obj_id not in removed_objectives:
				available_for_removal.append(obj_id)

		# Issue #329: route through RNGService so RNGService.test_mode_seed applies for deterministic tests
		var rng = RulesEngine.make_rng()
		for i in range(min(remove_count, available_for_removal.size())):
			# Pick randomly
			var idx = rng.randi_range(0, available_for_removal.size() - 1)
			var removed_id = available_for_removal[idx]
			available_for_removal.remove_at(idx)

			removed_objectives.append(removed_id)
			objective_control_state.erase(removed_id)

			print("MissionManager: Supply Drop - removed objective %s at start of round %d" % [removed_id, battle_round])
			emit_signal("objective_removed", removed_id)

		supply_drop_resolved_round_4 = true

# ============================================================
# KILL TRACKING — per-round tracking for Purge the Foe
# ============================================================

func record_unit_destroyed_detailed(destroyed_unit_owner: int, destroying_player: int) -> void:
	"""Called when a unit is destroyed. Tracks kills per round for Purge the Foe.
	Can be called externally from combat resolution code, or the mission manager
	can detect destroyed units via count_destroyed_units_this_round()."""
	var battle_round = str(GameState.get_battle_round())

	if not kills_per_round.has(battle_round):
		kills_per_round[battle_round] = {"1": 0, "2": 0}

	kills_per_round[battle_round][str(destroying_player)] += 1

	print("MissionManager: Recorded kill - Player %d destroyed Player %d's unit (Round %s total: %d)" % [
		destroying_player, destroyed_unit_owner, battle_round,
		kills_per_round[battle_round][str(destroying_player)]
	])

# Track which units were alive at the start of each round (for kill detection)
var _units_alive_at_round_start: Dictionary = {}  # round_str -> { unit_id: owner }

func snapshot_alive_units() -> void:
	"""Take a snapshot of alive units at the start of a round.
	Called at the beginning of Command phase to enable kill detection."""
	var battle_round = str(GameState.get_battle_round())
	var alive_units = {}
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		var has_alive_model = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive_model = true
				break
		if has_alive_model:
			alive_units[unit_id] = unit.get("owner", 0)

	_units_alive_at_round_start[battle_round] = alive_units
	print("MissionManager: Snapshot %d alive units at start of round %s" % [alive_units.size(), battle_round])

func count_destroyed_units_this_round() -> void:
	"""Compare current alive units to round-start snapshot to detect kills.
	Called during scoring to auto-detect unit destruction for Purge the Foe."""
	var battle_round = str(GameState.get_battle_round())
	var snapshot = _units_alive_at_round_start.get(battle_round, {})
	if snapshot.is_empty():
		return

	var units = GameState.state.get("units", {})

	for unit_id in snapshot:
		var unit = units.get(unit_id, {})
		if unit.is_empty():
			continue

		# Check if unit is now fully wiped
		var has_alive_model = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive_model = true
				break

		if not has_alive_model:
			var destroyed_owner = snapshot[unit_id]
			var destroying_player = 1 if destroyed_owner == 2 else 2

			# Only record if not already counted
			if not kills_per_round.has(battle_round):
				kills_per_round[battle_round] = {"1": 0, "2": 0}

			# Use a tracking set to avoid double-counting
			var key = "_%s_counted" % battle_round
			if not kills_per_round.has(key):
				kills_per_round[key] = []
			if unit_id not in kills_per_round[key]:
				kills_per_round[key].append(unit_id)
				kills_per_round[battle_round][str(destroying_player)] += 1
				print("MissionManager: Auto-detected kill - %s (Player %d) destroyed this round" % [unit_id, destroyed_owner])

# ============================================================
# SITES OF POWER SCORING
# ============================================================

func _score_sites_of_power(active_player: int, battle_round: int) -> void:
	var rules = current_mission.scoring_rules
	var total_vp = 0

	# Standard objective holding (same as Take and Hold base)
	var controlled_objectives = _get_controlled_objectives(active_player)
	var controlled_count = controlled_objectives.size()
	var hold_vp = min(controlled_count * rules.vp_per_objective, rules.max_vp_per_turn)
	total_vp += hold_vp

	# Check for character claims on NML objectives
	var objectives = GameState.state.board.get("objectives", [])
	var units = GameState.state.get("units", {})
	var control_radius = Measurement.inches_to_px(3.78740157)

	for obj in objectives:
		if obj.get("zone", "") != "no_mans_land":
			continue
		if obj.id in removed_objectives or obj.id in burned_objectives:
			continue

		# Check if active player has a CHARACTER within range
		var has_character_on_obj = _player_has_character_on_objective(active_player, obj, units, control_radius)

		if has_character_on_obj:
			var prev_claim = character_claimed_objectives.get(obj.id, {})
			if prev_claim.is_empty() or prev_claim.get("player", 0) != active_player:
				# First time claiming this objective
				character_claimed_objectives[obj.id] = {
					"player": active_player,
					"claimed_round": battle_round
				}
				total_vp += rules.character_claim_vp
				print("MissionManager: Player %d CHARACTER claimed %s (+%d VP)" % [active_player, obj.id, rules.character_claim_vp])
			else:
				# Character still holding from previous round
				total_vp += rules.character_hold_vp
				print("MissionManager: Player %d CHARACTER still on %s (+%d VP)" % [active_player, obj.id, rules.character_hold_vp])

	_award_primary_vp(active_player, total_vp, "Sites of Power: held %d obj, character claims active" % controlled_count)

func _player_has_character_on_objective(player: int, obj: Dictionary, units: Dictionary, control_radius: float) -> bool:
	"""Check if a player has a CHARACTER unit within range of an objective."""
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		var keywords = unit.get("meta", {}).get("keywords", [])
		if "CHARACTER" not in keywords:
			continue

		var status = unit.get("status", GameStateData.UnitStatus.UNDEPLOYED)
		if status == GameStateData.UnitStatus.UNDEPLOYED:
			continue

		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = model.get("position")
			if model_pos == null:
				continue
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.x, model_pos.y)

			if model_pos.distance_to(obj.position) <= control_radius:
				return true

	return false

# ============================================================
# SCORCHED EARTH — hold objectives + burn NML/enemy objectives for bonus VP
# ============================================================

func _score_hold_and_burn(active_player: int, _battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_obj = scoring_rules.get("vp_per_objective", 5)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 10)
	var burn_nml_vp = scoring_rules.get("burn_nml_vp", 5)
	var burn_enemy_vp = scoring_rules.get("burn_enemy_vp", 10)

	# Count controlled objectives (excluding removed/burned)
	var controlled_objectives = _get_controlled_objectives(active_player)
	var controlled_count = controlled_objectives.size()

	if controlled_count > 0:
		print("MissionManager: Scorched Earth - Player %d controls %d objectives: %s" % [active_player, controlled_count, controlled_objectives])
	else:
		print("MissionManager: Scorched Earth - Player %d controls no objectives" % active_player)

	# Base VP from holding objectives
	var vp_earned = controlled_count * vp_per_obj

	# Check for any burns that completed this turn and award bonus VP
	for obj_id in _burned_objectives:
		var burn_data = _burned_objectives[obj_id]
		if burn_data.get("player", 0) != active_player:
			continue
		# Determine the zone to calculate burn bonus
		var obj = _get_objective_by_id(obj_id)
		var zone = obj.get("zone", burn_data.get("zone", ""))
		if zone == "no_mans_land":
			vp_earned += burn_nml_vp
			print("MissionManager: Scorched Earth - Burn bonus for NML objective %s: +%d VP" % [obj_id, burn_nml_vp])
		elif zone != "" and zone != _get_player_home_zone(active_player):
			vp_earned += burn_enemy_vp
			print("MissionManager: Scorched Earth - Burn bonus for enemy objective %s: +%d VP" % [obj_id, burn_enemy_vp])

	vp_earned = mini(vp_earned, max_per_turn)
	_apply_primary_vp(active_player, vp_earned, "Scorched Earth: held %d objectives" % controlled_count)

func _get_player_home_zone(player: int) -> String:
	"""Return the deployment zone name for a player."""
	if player == 1:
		return "player1_zone"
	else:
		return "player2_zone"

# ============================================================
# THE RITUAL — Score VP by controlling NML objectives;
#              ritual actions can create new NML objectives
# ============================================================

func _score_ritual(active_player: int, _battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_nml = scoring_rules.get("vp_per_nml_objective", 5)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 15)

	# Only NML objectives score for The Ritual
	var controlled_nml = _get_controlled_nml_objectives(active_player)
	var controlled_count = controlled_nml.size()

	if controlled_count > 0:
		print("MissionManager: The Ritual - Player %d controls %d NML objectives: %s" % [active_player, controlled_count, controlled_nml])
	else:
		print("MissionManager: The Ritual - Player %d controls no NML objectives" % active_player)

	var vp_earned = mini(controlled_count * vp_per_nml, max_per_turn)
	_apply_primary_vp(active_player, vp_earned, "The Ritual: controlled %d NML objectives" % controlled_count)

# ============================================================
# TERRAFORM — Score VP for controlling objectives;
#             terraformed objectives give bonus VP
# ============================================================

func _score_terraform(active_player: int, _battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_controlled = scoring_rules.get("vp_per_controlled", 4)
	var max_control_vp = scoring_rules.get("max_control_vp_per_turn", 12)
	var vp_per_terraformed = scoring_rules.get("vp_per_terraformed", 1)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 15)

	# Base VP from controlling objectives
	var controlled_objectives = _get_controlled_objectives(active_player)
	var controlled_count = controlled_objectives.size()

	var control_vp = mini(controlled_count * vp_per_controlled, max_control_vp)

	if controlled_count > 0:
		print("MissionManager: Terraform - Player %d controls %d objectives: %s (+%d VP)" % [active_player, controlled_count, controlled_objectives, control_vp])
	else:
		print("MissionManager: Terraform - Player %d controls no objectives" % active_player)

	# Bonus VP for each terraformed objective (regardless of current control)
	var terraform_bonus = 0
	for obj_id in _terraformed_objectives:
		if _terraformed_objectives[obj_id] == active_player:
			terraform_bonus += vp_per_terraformed
			print("MissionManager: Terraform - Bonus for terraformed objective %s: +%d VP" % [obj_id, vp_per_terraformed])

	var vp_earned = mini(control_vp + terraform_bonus, max_per_turn)
	_apply_primary_vp(active_player, vp_earned, "Terraform: held %d objectives, %d terraformed" % [controlled_count, terraform_bonus])

# ============================================================
# 11e FORCE DISPOSITION PRIMARY MISSIONS
# ============================================================
# Awards sourced from data/40kdc/missionCards.json (official 11e launch
# dataset, effective 2026-06-20) via PrimaryMissionData11e. Each player
# scores their OWN card: their deck (disposition) paired against the
# opponent's disposition. Caps: 45 primary total, 15 per turn. Command
# conditions score at the end of your Command phase in R1-4 and switch to end
# of turn in R5. EOT conditions score every end of turn; EOG conditions score
# once when the game ends.

func initialize_dispositions_11e(p1_disposition: String, p2_disposition: String) -> void:
	if not PrimaryMissionData11e.is_valid_disposition(p1_disposition):
		print("MissionManager: 11e unknown disposition '%s' for P1, using take_and_hold" % p1_disposition)
		p1_disposition = "take_and_hold"
	if not PrimaryMissionData11e.is_valid_disposition(p2_disposition):
		print("MissionManager: 11e unknown disposition '%s' for P2, using take_and_hold" % p2_disposition)
		p2_disposition = "take_and_hold"

	player_dispositions = {"1": p1_disposition, "2": p2_disposition}
	player_primary_missions = {
		"1": PrimaryMissionData11e.get_card(p1_disposition, p2_disposition),
		"2": PrimaryMissionData11e.get_card(p2_disposition, p1_disposition),
	}
	_primary_vp_this_turn = {"1": 0, "2": 0}
	_control_at_turn_start = {}
	_eog_primary_scored = false
	_warned_unimplemented_actions = {}
	_primary_state_11e = {"1": _blank_primary_state_11e(), "2": _blank_primary_state_11e()}
	_alive_at_turn_start_11e = {}
	_setup_relic_markers_11e()
	_register_mission_actions_11e()

	GameState.state.meta["dispositions_11e"] = player_dispositions.duplicate(true)
	for pk in ["1", "2"]:
		var card = player_primary_missions[pk]
		print("MissionManager: 11e P%s disposition %s vs %s -> primary mission '%s'%s" % [
			pk, player_dispositions[pk], player_dispositions["2" if pk == "1" else "1"],
			card.get("name", "?"),
			" (approximate)" if card.get("approximate", false) else ""])

func _blank_primary_state_11e() -> Dictionary:
	return {
		"triangulated": [], "consecrated": [], "decoyed": [], "decoyed_ever": [],
		"trapped": [], "operation_markers": 0, "intel_tokens": [],
		# Death Trap official award: pays per terrain area trapped THIS TURN
		"trapped_this_turn": [],
		"intel_placed_this_turn": 0, "condemned": [],
		"condemned_left_this_turn": false, "sensor_swept_this_turn": false,
		# Decoys placed this turn are exempt from this turn's scrub: the card
		# removes a marker when an enemy ENDS A MOVE in range, which cannot
		# have happened after an end-of-turn placement.
		"decoyed_this_turn": [],
		# Player-prompt bookkeeping: once the owner resolves (or declines) their
		# card action for the turn, the deterministic auto-pick must stand down.
		"card_action_resolved_this_turn": false,
		# Punishment: a human owner may revise the auto-Condemn picks during
		# their Command phase while this is set.
		"condemn_prompt_pending": false,
		# Turn key ("R<round>P<player>") of the last answered Condemn prompt —
		# lets a save/load phase re-entry keep the player's revision instead
		# of re-running the auto pick over it.
		"condemn_resolved_turn": "",
		# Per-unit mission ACTIONS (16.01, started in the Shooting phase).
		# When the *_started flag is set the action path is authoritative for
		# that rule this turn (a failed action scores 0 — no fallback); when
		# unset the positional approximation scores as before (AI/headless).
		"sabotage_started_this_turn": false,
		"sabotaged_this_turn": [],
		"vanguard_started_this_turn": false,
		"vanguard_completed_this_turn": false,
		"intel_started_this_turn": false,
		"intel_units_this_turn": 0,
	}

## Extract Relic / Locate and Deny pairing: the Disruption player marks five
## terrain areas outside their deployment zone at the start of the mission.
## Auto-picked: the five terrain features farthest from the Disruption
## player's home objective (deterministic; flagged approximate).
func _setup_relic_markers_11e() -> void:
	_relic_markers_11e = []
	_relic_setup_prompt_pending = false
	var ids = [player_primary_missions.get("1", {}).get("id", ""),
		player_primary_missions.get("2", {}).get("id", "")]
	if not ("extract_relic" in ids or "locate_and_deny" in ids):
		return
	var di_player = 1 if player_dispositions.get("1", "") == "disruption" else 2
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null or tm.terrain_features.is_empty():
		print("MissionManager: 11e relic markers — no terrain features available")
		return
	var di_home_pos = null
	for obj in GameState.state.board.get("objectives", []):
		if obj.get("zone", "") == "player%d" % di_player:
			di_home_pos = obj.get("position")
			if di_home_pos is Dictionary:
				di_home_pos = Vector2(di_home_pos.x, di_home_pos.y)
			break
	# The real card marks terrain areas OUTSIDE the Disruption player's
	# deployment zone. Restrict the auto-pick to the same eligible set the
	# revision dialog offers, so the pre-checked count always meets the
	# required count (otherwise an auto-pick inside the DZ has no checkbox and
	# the player can never confirm the required number of markers).
	var eligible_ids := _relic_eligible_features_11e(di_player)
	var candidates = []
	for feature in tm.terrain_features:
		var fid = str(feature.get("id", ""))
		if not eligible_ids.is_empty() and not fid in eligible_ids:
			continue
		var fpos = feature.get("position", Vector2.ZERO)
		if fpos is Dictionary:
			fpos = Vector2(fpos.get("x", 0), fpos.get("y", 0))
		var dist = fpos.distance_to(di_home_pos) if di_home_pos != null else 0.0
		candidates.append({"id": fid, "dist": dist})
	candidates.sort_custom(func(a, b): return a["dist"] > b["dist"])
	for i in range(min(5, candidates.size())):
		_relic_markers_11e.append(candidates[i]["id"])
	# A human Disruption player may revise these picks in their first
	# Command phase (real card: their choice at mission start).
	_relic_setup_prompt_pending = not _relic_markers_11e.is_empty()
	print("MissionManager: 11e relic markers placed on %s" % str(_relic_markers_11e))

## Called at Command phase entry (after check_all_objectives) — opens the
## active player's per-turn VP window and snapshots start-of-turn control.
func on_turn_start_11e(player: int) -> void:
	if GameConstants.edition < 11:
		return
	var pk = str(player)
	_primary_vp_this_turn[pk] = 0
	_control_at_turn_start[pk] = _get_controlled_objectives(player)
	# Snapshot who is on the battlefield for left-battlefield / kill checks
	var alive = {}
	for unit_id in GameState.state.get("units", {}):
		if _unit_on_battlefield_11e(unit_id):
			alive[unit_id] = true
	_alive_at_turn_start_11e[pk] = alive
	# Per-turn marker-state resets (both players — the windows are per turn)
	for spk in _primary_state_11e:
		var st = _primary_state_11e[spk]
		st["intel_placed_this_turn"] = 0
		st["sensor_swept_this_turn"] = false
		st["condemned_left_this_turn"] = false
		st["card_action_resolved_this_turn"] = false
		st["condemn_prompt_pending"] = false
		st["decoyed_this_turn"] = []
		st["trapped_this_turn"] = []
		st["sabotage_started_this_turn"] = false
		st["sabotaged_this_turn"] = []
		st["vanguard_started_this_turn"] = false
		st["vanguard_completed_this_turn"] = false
		st["intel_started_this_turn"] = false
		st["intel_units_this_turn"] = 0
	# Punishment: auto-Condemn up to 3 enemy units in range of an objective as
	# the backstop (real card: player's choice, incl. units that killed
	# friendlies). A human owner can revise the picks via the Command-phase
	# Condemn prompt while condemn_prompt_pending is set. Skip when the
	# player already answered for THIS turn — a save/load re-enters the
	# Command phase and must not clobber their revision.
	if player_primary_missions.get(pk, {}).get("id", "") == "punishment":
		var turn_key = "R%dP%d" % [GameState.get_battle_round(), player]
		if _primary_state_11e[pk].get("condemn_resolved_turn", "") == turn_key:
			print("MissionManager: 11e Condemn already answered for %s — keeping %s" % [
				turn_key, str(_primary_state_11e[pk].get("condemned", []))])
		else:
			_auto_condemn_11e(player)
			if not _condemn_eligible_units_11e(player).is_empty():
				_primary_state_11e[pk]["condemn_prompt_pending"] = true
	refresh_card_action_visuals_11e()
	print("MissionManager: 11e turn start P%s — controls %s" % [pk, str(_control_at_turn_start[pk])])

func _unit_on_battlefield_11e(unit_id: String) -> bool:
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var emb = unit.get("embarked_in", null)
	if emb != null and str(emb) != "":
		return false
	for model in unit.get("models", []):
		if model.get("alive", true) and model.get("position") != null:
			return true
	return false

func _auto_condemn_11e(player: int) -> void:
	var pk = str(player)
	var st = _primary_state_11e.get(pk, {})
	var condemned = _condemn_eligible_units_11e(player).slice(0, 3)
	st["condemned"] = condemned
	if condemned.size() > 0:
		print("MissionManager: 11e Punishment — P%s condemns %s" % [pk, str(condemned)])

## Punishment eligibility: enemy units on the battlefield in range of an
## objective. (The card's second branch — units that destroyed a friendly
## unit the previous turn — needs per-unit kill attribution, which the
## engine doesn't track; still approximate.)
func _condemn_eligible_units_11e(player: int) -> Array:
	var opponent = 3 - player
	var control_radius = Measurement.inches_to_px(3.78740157)
	var eligible = []
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != opponent or not _unit_on_battlefield_11e(unit_id):
			continue
		if _unit_within_of_any_objective_11e(unit_id, control_radius):
			eligible.append(unit_id)
	return eligible

func _unit_within_of_any_objective_11e(unit_id: String, radius_px: float) -> bool:
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	for obj in GameState.state.board.get("objectives", []):
		var obj_pos = obj.get("position")
		if obj_pos is Dictionary:
			obj_pos = Vector2(obj_pos.x, obj_pos.y)
		for model in unit.get("models", []):
			if not model.get("alive", true) or model.get("position") == null:
				continue
			if Measurement.model_edge_to_point_distance_px(model, obj_pos) <= radius_px:
				return true
	return false

## End-of-turn primary scoring: auto-resolve card actions first, then EOT
## conditions, plus Command conditions in Round 5 (GDM: "C ... switches to
## end of turn in Round 5"). "End of ANY turn" conditions (eot_any) are also
## evaluated for the non-active player.
func score_primary_eot_11e(player: int) -> void:
	if GameConstants.edition < 11 or player_primary_missions.is_empty():
		return
	var battle_round = GameState.get_battle_round()
	_run_primary_auto_actions_11e(player, battle_round)
	_score_primary_11e(player, battle_round, "eot")
	_score_primary_11e(player, battle_round, "eot_any")
	if battle_round >= 5:
		_score_primary_11e(player, battle_round, "command")
	# Opponent's end-of-ANY-turn conditions (e.g. Punishment's Condemned check)
	var opponent = 3 - player
	_update_condemned_left_11e(opponent, player)
	_score_primary_11e(opponent, battle_round, "eot_any")

## Auto-resolve the active player's card action for this turn. The real
## cards let the player pick targets; we pick deterministically as the
## headless/AI backstop (the prompts let a human choose instead). Also
## scrubs decoy markers enemies reached.
func _run_primary_auto_actions_11e(player: int, battle_round: int) -> void:
	var pk = str(player)
	var st = _primary_state_11e.get(pk, {})
	if st.is_empty():
		return
	var card_id = player_primary_missions.get(pk, {}).get("id", "")
	var control_radius = Measurement.inches_to_px(3.78740157)

	# Decoy scrub (both players): a decoy is removed once an enemy unit is
	# within range of the objective (approximates "ends a move within range").
	# Markers placed THIS turn are exempt — no enemy move can have ended
	# after an end-of-turn placement (keeps the player-pick path scoring the
	# same as the auto path, which places after this scrub).
	for spk in _primary_state_11e:
		var owner = int(spk)
		var sst = _primary_state_11e[spk]
		var kept = []
		for obj_id in sst.get("decoyed", []):
			if obj_id in sst.get("decoyed_this_turn", []) \
					or not _enemy_unit_in_range_of_objective_11e(owner, obj_id, control_radius):
				kept.append(obj_id)
			else:
				print("MissionManager: 11e decoy on %s scrubbed (enemy in range)" % obj_id)
		sst["decoyed"] = kept

	# Stand down when the player already resolved (or declined) their card
	# action this turn via the prompt — their choice replaces the auto-pick.
	if st.get("card_action_resolved_this_turn", false):
		print("MissionManager: 11e card action already resolved by P%s this turn — auto-pick skipped" % pk)
	else:
		match card_id:
			"triangulation":
				# Triangulate: once per turn, an objective you control at EOT
				for obj_id in _get_controlled_objectives(player):
					if not obj_id in st["triangulated"]:
						st["triangulated"].append(obj_id)
						print("MissionManager: 11e Triangulated %s (P%s)" % [obj_id, pk])
						break
			"consecrate":
				# Killer unit becomes a Consecration unit; approximated as: a kill
				# this turn lets one friendly unit in range consecrate an eligible
				# (non-home, unconsecrated) objective at EOT.
				if _kills_this_turn_11e(player) >= 1:
					for obj_id in _get_controlled_objectives(player):
						if _is_home_objective_11e(obj_id, player) or obj_id in st["consecrated"]:
							continue
						st["consecrated"].append(obj_id)
						print("MissionManager: 11e Consecrated %s (P%s)" % [obj_id, pk])
						break
			"smoke_and_mirrors":
				# Decoy action: unlimited uses at end of turn on controlled
				# non-home objectives. Official "undecoyed" means never tagged
				# — the Decoyed tag never clears — so scrubbed markers cannot
				# be replenished by re-decoying (guard on decoyed_ever).
				if not st.has("decoyed_this_turn"):
					st["decoyed_this_turn"] = []
				for obj_id in _get_controlled_objectives(player):
					if _is_home_objective_11e(obj_id, player) or obj_id in st["decoyed_ever"]:
						continue
					st["decoyed"].append(obj_id)
					st["decoyed_this_turn"].append(obj_id)
					if not obj_id in st["decoyed_ever"]:
						st["decoyed_ever"].append(obj_id)
					print("MissionManager: 11e Decoyed %s (P%s)" % [obj_id, pk])
			"vital_link":
				var central = _get_central_objective_id_11e()
				if central != "" and objective_control_state.get(central, 0) == player:
					st["operation_markers"] = int(st.get("operation_markers", 0)) + 1
					print("MissionManager: 11e Vital Link operation marker %d placed (P%s)" % [st["operation_markers"], pk])
			"death_trap":
				# Booby Trap: once per turn, an untrapped terrain area containing
				# one of your models (eligibility simplified)
				var tm = get_node_or_null("/root/TerrainManager")
				if tm != null:
					for feature in tm.terrain_features:
						var fid = feature.get("id", "")
						if fid == "" or fid in st["trapped"]:
							continue
						if _player_model_in_terrain_11e(player, feature):
							st["trapped"].append(fid)
							if not st.has("trapped_this_turn"):
								st["trapped_this_turn"] = []
							st["trapped_this_turn"].append(fid)
							print("MissionManager: 11e Booby Trapped %s (P%s)" % [fid, pk])
							break
			"gather_intel":
				if battle_round >= 2:
					for obj in GameState.state.board.get("objectives", []):
						var obj_id = obj.get("id", "")
						if obj.get("zone", "") != "no_mans_land" or obj_id in st["intel_tokens"]:
							continue
						if _friendly_unit_in_range_of_objective_11e(player, obj_id, control_radius):
							st["intel_tokens"].append(obj_id)
							st["intel_placed_this_turn"] = int(st.get("intel_placed_this_turn", 0)) + 1
							print("MissionManager: 11e intel token on %s (P%s)" % [obj_id, pk])
			"extract_relic", "locate_and_deny":
				# Sensor Sweep: once per turn while >1 marker remains, needs a unit
				# in range of a controlled Central objective
				if _relic_markers_11e.size() > 1:
					var central2 = _get_central_objective_id_11e()
					if central2 != "" and objective_control_state.get(central2, 0) == player \
							and _friendly_unit_in_range_of_objective_11e(player, central2, control_radius):
						var removed = _relic_markers_11e.pop_back()
						st["sensor_swept_this_turn"] = true
						_relic_setup_prompt_pending = false
						print("MissionManager: 11e Sensor Sweep removed marker %s (P%s, %d left)" % [str(removed), pk, _relic_markers_11e.size()])

	# The active player's own Condemned check also runs at their EOT
	_update_condemned_left_11e(player, player)
	refresh_card_action_visuals_11e()

func _update_condemned_left_11e(card_owner: int, turn_owner: int) -> void:
	var pk = str(card_owner)
	var st = _primary_state_11e.get(pk, {})
	if st.is_empty() or st.get("condemned", []).is_empty():
		return
	var turn_snapshot = _alive_at_turn_start_11e.get(str(turn_owner), {})
	for unit_id in st["condemned"]:
		if turn_snapshot.has(unit_id) and not _unit_on_battlefield_11e(unit_id):
			st["condemned_left_this_turn"] = true
			print("MissionManager: 11e Condemned unit %s left the battlefield" % unit_id)
			return

# ============================================================
# 11e PER-UNIT MISSION ACTIONS (16.01, started in the Shooting phase)
# ============================================================
# Sabotage / Vanguard Operation / Extract Intelligence are real per-unit
# actions on the sourced cards: a unit gives up shooting to start one and
# it completes at end of turn. Registered into ActionsManager per game;
# when the owner USES the action, its rule scores from the action state
# for that turn; otherwise the positional approximation stands (AI and
# headless backstop). Secure Asset is intentionally NOT an action here —
# its modelled hold rule already equals the action outcome. Consecrate's
# killer-unit attribution needs per-unit kill tracking that doesn't exist
# yet, so it stays with the end-of-turn prompt approximation.

func _register_mission_actions_11e() -> void:
	ActionsManager.unregister_actions_by_prefix("mission_")
	if GameConstants.edition < 11:
		return
	for pk in ["1", "2"]:
		var player = int(pk)
		var card_id = player_primary_missions.get(pk, {}).get("id", "")
		match card_id:
			"sabotage":
				ActionsManager.register_action({
					"id": "mission_sabotage_p%s" % pk,
					"name": "Sabotage",
					"starts": "shooting",
					"units": {},
					"use_limit": "",
					"completes": "end_of_turn",
					"effect": "mission:sabotage",
					"mission_check": "sabotage",
					"player": player,
					"description": "Sabotage the objective this unit is on (non-home). Completes at end of turn: 3 VP per sabotaged objective (+2 in enemy territory).",
				})
			"vanguard_operation":
				ActionsManager.register_action({
					"id": "mission_vanguard_p%s" % pk,
					"name": "Vanguard Operation",
					"starts": "shooting",
					"units": {},
					"use_limit": "once_per_turn",
					"completes": "end_of_turn",
					"effect": "mission:vanguard",
					"mission_check": "vanguard",
					"player": player,
					"description": "Operate from a terrain area in your opponent's territory. Completes at end of turn if no enemy units are in that area: 4 VP.",
				})
			"gather_intel":
				ActionsManager.register_action({
					"id": "mission_extract_intel_p%s" % pk,
					"name": "Extract Intelligence",
					"starts": "shooting",
					"units": {},
					"use_limit": "",
					"completes": "end_of_turn",
					"effect": "mission:gather_intel",
					"mission_check": "gather_intel",
					"player": player,
					"description": "Extract intelligence at a No Man's Land objective (from Round 2). Completes at end of turn: 7 VP per unit that completed the action.",
				})
	print("MissionManager: 11e mission actions registered for the disposition cards")

## Contextual eligibility for the mission actions (ActionsManager gate).
func can_start_mission_action_11e(check_id: String, unit_id: String, player: int) -> bool:
	if GameConstants.edition < 11:
		return false
	var control_radius = Measurement.inches_to_px(3.78740157)
	match check_id:
		"sabotage":
			var obj_id = _nearest_objective_in_range_11e(unit_id, control_radius, "non_home", player)
			return obj_id != ""
		"vanguard":
			return _unit_terrain_area_in_enemy_territory_11e(unit_id, player) != ""
		"gather_intel":
			if GameState.get_battle_round() < 2:
				return false
			var st = _primary_state_11e.get(str(player), {})
			var obj_id = _nearest_objective_in_range_11e(unit_id, control_radius, "nml", player)
			return obj_id != "" and not obj_id in st.get("intel_tokens", [])
		_:
			return false

## ShootingPhase hook: a mission action was STARTED — from now the action
## path is authoritative for that rule this turn (a failed action scores 0).
func on_mission_action_started_11e(action_id: String, unit_id: String, player: int) -> void:
	var st = _primary_state_11e.get(str(player), {})
	if st.is_empty():
		return
	var def = ActionsManager.get_action(action_id)
	match str(def.get("effect", "")):
		"mission:sabotage":
			st["sabotage_started_this_turn"] = true
		"mission:vanguard":
			st["vanguard_started_this_turn"] = true
		"mission:gather_intel":
			st["intel_started_this_turn"] = true
			# The action IS this turn's Extract Intelligence choice — the
			# end-of-turn prompt/auto placement stands down.
			st["card_action_resolved_this_turn"] = true
	print("MissionManager: 11e mission action %s started by %s (P%d)" % [action_id, unit_id, player])

## PhaseManager hook: a mission action COMPLETED at end of turn (unit did
## not move, is not battle-shocked). Resolve its target from the unit's
## position now and write the scoring state.
func on_mission_action_completed_11e(unit_id: String, effect: String) -> void:
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var player = int(unit.get("owner", 0))
	var st = _primary_state_11e.get(str(player), {})
	if st.is_empty():
		return
	var control_radius = Measurement.inches_to_px(3.78740157)
	match effect:
		"mission:sabotage":
			var obj_id = _nearest_objective_in_range_11e(unit_id, control_radius, "non_home", player)
			if obj_id != "" and not obj_id in st.get("sabotaged_this_turn", []):
				st["sabotaged_this_turn"].append(obj_id)
				print("MissionManager: 11e Sabotage completed on %s by %s (P%d)" % [obj_id, unit_id, player])
		"mission:vanguard":
			var fid = _unit_terrain_area_in_enemy_territory_11e(unit_id, player)
			if fid != "":
				var tm = get_node_or_null("/root/TerrainManager")
				var enemy_inside = false
				if tm != null:
					for feature in tm.terrain_features:
						if feature.get("id", "") == fid:
							enemy_inside = _player_model_in_terrain_11e(3 - player, feature)
							break
				if not enemy_inside:
					st["vanguard_completed_this_turn"] = true
					print("MissionManager: 11e Vanguard Operation completed in %s by %s (P%d)" % [fid, unit_id, player])
		"mission:gather_intel":
			var obj_id = _nearest_objective_in_range_11e(unit_id, control_radius, "nml", player)
			if obj_id != "":
				if not obj_id in st.get("intel_tokens", []):
					st["intel_tokens"].append(obj_id)
				st["intel_units_this_turn"] = int(st.get("intel_units_this_turn", 0)) + 1
				print("MissionManager: 11e Extract Intelligence completed at %s by %s (P%d)" % [obj_id, unit_id, player])
	refresh_card_action_visuals_11e()

## Nearest objective within radius of any of the unit's models. Filters:
## "non_home" (not the acting player's home) or "nml" (No Man's Land only).
func _nearest_objective_in_range_11e(unit_id: String, radius_px: float, obj_filter: String, player: int) -> String:
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	var best_id = ""
	var best_dist = INF
	for obj in GameState.state.board.get("objectives", []):
		var obj_id = obj.get("id", "")
		if obj_filter == "non_home" and _is_home_objective_11e(obj_id, player):
			continue
		if obj_filter == "nml" and obj.get("zone", "") != "no_mans_land":
			continue
		var obj_pos = obj.get("position")
		if obj_pos is Dictionary:
			obj_pos = Vector2(obj_pos.x, obj_pos.y)
		for model in unit.get("models", []):
			if not model.get("alive", true) or model.get("position") == null:
				continue
			var d = Measurement.model_edge_to_point_distance_px(model, obj_pos)
			if d <= radius_px and d < best_dist:
				best_dist = d
				best_id = obj_id
	return best_id

## The terrain feature (id) in enemy territory that contains one of the
## unit's models, or "" — Vanguard Operation eligibility/completion.
func _unit_terrain_area_in_enemy_territory_11e(unit_id: String, player: int) -> String:
	var tm = get_node_or_null("/root/TerrainManager")
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if tm == null or secondary_mgr == null:
		return ""
	var enemy_zone = secondary_mgr._get_deployment_zone_polygon(3 - player)
	if enemy_zone.is_empty():
		return ""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	for feature in tm.terrain_features:
		var fpos = feature.get("position", Vector2.ZERO)
		if fpos is Dictionary:
			fpos = Vector2(fpos.get("x", 0), fpos.get("y", 0))
		if not Geometry2D.is_point_in_polygon(fpos, enemy_zone):
			continue
		var polygon = feature.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue
		for model in unit.get("models", []):
			if not model.get("alive", true) or model.get("position") == null:
				continue
			var pos = model.get("position")
			if pos is Dictionary:
				pos = Vector2(pos.x, pos.y)
			if Geometry2D.is_point_in_polygon(pos, polygon):
				return str(feature.get("id", ""))
	return ""

# ============================================================
# 11e CARD-ACTION STATE VISIBILITY (board badges + HUD summaries)
# ============================================================

## Push the marker state onto the objective visuals and notify overlays.
## Safe headless (no visual refs registered) — still emits the signal so
## HUD listeners stay in sync.
func refresh_card_action_visuals_11e() -> void:
	if GameConstants.edition >= 11 and not player_primary_missions.is_empty():
		var central = _get_central_objective_id_11e()
		for obj in GameState.state.board.get("objectives", []):
			var obj_id = obj.get("id", "")
			var vis = objectives_visual_refs.get(obj_id, null)
			if vis == null or not is_instance_valid(vis) or not vis.has_method("set_card_action_badges"):
				continue
			var badges = []
			for pk in ["1", "2"]:
				var st = _primary_state_11e.get(pk, {})
				if st.is_empty():
					continue
				if obj_id in st.get("triangulated", []):
					badges.append("TRIANGULATED (P%s)" % pk)
				if obj_id in st.get("consecrated", []):
					badges.append("CONSECRATED (P%s)" % pk)
				if obj_id in st.get("decoyed", []):
					badges.append("DECOY (P%s)" % pk)
				if obj_id in st.get("intel_tokens", []):
					badges.append("INTEL (P%s)" % pk)
				if obj_id == central and int(st.get("operation_markers", 0)) > 0:
					badges.append("OP MARKERS x%d (P%s)" % [int(st["operation_markers"]), pk])
			vis.set_card_action_badges(badges)
	emit_signal("card_action_state_changed")

## Badges for a terrain feature (Booby Traps + shared relic markers) —
## consumed by CardActionOverlay.
func get_terrain_badges_11e(feature_id: String) -> Array:
	var lines = []
	if GameConstants.edition < 11:
		return lines
	for pk in ["1", "2"]:
		if feature_id in _primary_state_11e.get(pk, {}).get("trapped", []):
			lines.append("BOOBY TRAP (P%s)" % pk)
	if feature_id in _relic_markers_11e:
		lines.append("OP MARKER")
	return lines

## Compact per-player marker summary for HUD panels. Empty when the player
## has no markers/picks in play.
func get_card_action_summary_11e(player: int) -> Array:
	var pk = str(player)
	var st = _primary_state_11e.get(pk, {})
	var out = []
	if GameConstants.edition < 11 or st.is_empty():
		return out
	var list_parts = [
		["Triangulated", st.get("triangulated", [])],
		["Consecrated", st.get("consecrated", [])],
		["Decoys", st.get("decoyed", [])],
		["Intel tokens", st.get("intel_tokens", [])],
		["Booby traps", st.get("trapped", [])],
	]
	for part in list_parts:
		var vals: Array = part[1]
		if not vals.is_empty():
			var strs = []
			for v in vals:
				strs.append(str(v))
			out.append("%s: %s" % [part[0], ", ".join(PackedStringArray(strs))])
	if int(st.get("operation_markers", 0)) > 0:
		out.append("Operation markers: %d" % int(st["operation_markers"]))
	var condemned: Array = st.get("condemned", [])
	if not condemned.is_empty():
		var names = []
		for uid in condemned:
			var unit = GameState.state.get("units", {}).get(uid, {})
			names.append(str(unit.get("meta", {}).get("name", uid)))
		out.append("Condemned: %s" % ", ".join(PackedStringArray(names)))
	var card_id = player_primary_missions.get(pk, {}).get("id", "")
	if card_id in ["extract_relic", "locate_and_deny"] and not _relic_markers_11e.is_empty():
		var marker_strs = []
		for m in _relic_markers_11e:
			marker_strs.append(str(m))
		out.append("Relic markers left: %s" % ", ".join(PackedStringArray(marker_strs)))
	return out

# ============================================================
# 11e CARD-ACTION PLAYER CHOICE (prompts; auto-resolve backstop)
# ============================================================
# The bespoke GDM card actions stay auto-resolved deterministically inside
# score_primary_eot_11e — that is the headless/AI backstop and the behavior
# every existing test pins. The interactive layer opts a HUMAN player into
# choosing instead: ScoringPhase's END_TURN gate queries
# get_pending_card_action_11e, the ScoringController dialog dispatches
# RESOLVE_CARD_ACTION / SKIP_CARD_ACTION, and resolve_card_action_11e
# applies the picks and stands the auto-pick down for the turn.
# (Vital Link is deliberately absent: its Operation Marker has no target
# choice — the Central objective is the only legal spot — so it stays
# fully automatic.)

## Enumerate the player's end-of-turn card-action choice. Returns {} when
## the card has no target choice, nothing is eligible right now, or the
## action was already resolved/declined this turn. Pure query — no mutation.
## Shape: { card_id, card_name, player, action_name, description,
##   mode: "single"|"multi", targets: [{id, label}] }
func get_pending_card_action_11e(player: int, battle_round: int = -1) -> Dictionary:
	if GameConstants.edition < 11 or player_primary_missions.is_empty():
		return {}
	var pk = str(player)
	var st = _primary_state_11e.get(pk, {})
	if st.is_empty() or st.get("card_action_resolved_this_turn", false):
		return {}
	if battle_round < 0:
		battle_round = GameState.get_battle_round()
	var card = player_primary_missions.get(pk, {})
	var card_id = card.get("id", "")
	var control_radius = Measurement.inches_to_px(3.78740157)
	var targets = []
	var pending = {
		"card_id": card_id,
		"card_name": card.get("name", "?"),
		"player": player,
		"mode": "single",
	}
	match card_id:
		"triangulation":
			pending["action_name"] = "Triangulate"
			pending["description"] = "Once per turn: apply the Triangulated descriptor to an objective you control (permanent)."
			for obj_id in _get_controlled_objectives(player):
				if not obj_id in st.get("triangulated", []):
					targets.append(_objective_target_entry_11e(obj_id))
		"consecrate":
			if _kills_this_turn_11e(player) < 1:
				return {}
			pending["action_name"] = "Consecrate"
			pending["description"] = "You destroyed a unit this turn: place a Consecrated marker (permanent) on a non-home objective you control."
			for obj_id in _get_controlled_objectives(player):
				if _is_home_objective_11e(obj_id, player) or obj_id in st.get("consecrated", []):
					continue
				targets.append(_objective_target_entry_11e(obj_id))
		"smoke_and_mirrors":
			pending["action_name"] = "Decoy"
			pending["description"] = "Unlimited uses: place Decoy markers on undecoyed non-home objectives you control. A decoyed objective keeps scoring; its marker is removed if an enemy unit reaches the objective."
			pending["mode"] = "multi"
			for obj_id in _get_controlled_objectives(player):
				if _is_home_objective_11e(obj_id, player) or obj_id in st.get("decoyed_ever", []):
					continue
				targets.append(_objective_target_entry_11e(obj_id))
		"death_trap":
			pending["action_name"] = "Booby Trap"
			pending["description"] = "Once per turn: trap an untrapped terrain area containing one of your models (2 VP this turn, +3 more if it holds an objective; kills in trapped terrain pay separately)."
			var tm = get_node_or_null("/root/TerrainManager")
			if tm != null:
				for feature in tm.terrain_features:
					var fid = feature.get("id", "")
					if fid == "" or fid in st.get("trapped", []):
						continue
					if _player_model_in_terrain_11e(player, feature):
						var label = str(fid)
						if _terrain_contains_objective_11e(tm, fid):
							label += " (holds an objective)"
						targets.append({"id": fid, "label": label})
		"gather_intel":
			if battle_round < 2:
				return {}
			pending["action_name"] = "Extract Intelligence"
			pending["description"] = "From Round 2: place intel tokens on No Man's Land objectives your units are in range of (7 VP each this turn)."
			pending["mode"] = "multi"
			for obj in GameState.state.board.get("objectives", []):
				var obj_id = obj.get("id", "")
				if obj.get("zone", "") != "no_mans_land" or obj_id in st.get("intel_tokens", []):
					continue
				if _friendly_unit_in_range_of_objective_11e(player, obj_id, control_radius):
					targets.append(_objective_target_entry_11e(obj_id))
		"extract_relic", "locate_and_deny":
			if _relic_markers_11e.size() <= 1:
				return {}
			var central = _get_central_objective_id_11e()
			if central == "" or objective_control_state.get(central, 0) != player \
					or not _friendly_unit_in_range_of_objective_11e(player, central, control_radius):
				return {}
			pending["action_name"] = "Sensor Sweep"
			pending["description"] = "Once per turn: remove one operation marker of your choice (markers stop being removable when one remains)."
			for marker_id in _relic_markers_11e:
				targets.append({"id": str(marker_id), "label": "Marker on %s" % str(marker_id)})
		_:
			return {}
	if targets.is_empty():
		return {}
	pending["targets"] = targets
	return pending

func _objective_target_entry_11e(obj_id: String) -> Dictionary:
	var obj = _get_objective_by_id(obj_id)
	var bits = []
	var designation = str(obj.get("designation", ""))
	if designation != "":
		bits.append(designation.capitalize())
	match str(obj.get("zone", "")):
		"no_mans_land":
			bits.append("No Man's Land")
		"player1":
			bits.append("P1 zone")
		"player2":
			bits.append("P2 zone")
	var label = obj_id
	if not bits.is_empty():
		label += " (%s)" % ", ".join(PackedStringArray(bits))
	return {"id": obj_id, "label": label}

## Apply the player's chosen targets for their card action this turn.
## Validates against the live pending enumeration; an empty pick list is a
## decline. Sets card_action_resolved_this_turn so the auto-pick stands down.
func resolve_card_action_11e(player: int, target_ids: Array) -> Dictionary:
	var pending = get_pending_card_action_11e(player)
	if pending.is_empty():
		return {"success": false, "error": "No pending card action for player %d" % player}
	var pk = str(player)
	var st = _primary_state_11e.get(pk, {})
	var valid_ids = []
	for t in pending.get("targets", []):
		valid_ids.append(str(t.get("id", "")))
	if pending.get("mode", "single") == "single" and target_ids.size() > 1:
		return {"success": false, "error": "%s allows only one target" % pending.get("action_name", "Card action")}
	var picks = []
	for tid in target_ids:
		var tid_s = str(tid)
		if not tid_s in valid_ids:
			return {"success": false, "error": "Ineligible target %s for %s" % [tid_s, pending.get("action_name", "card action")]}
		if not tid_s in picks:
			picks.append(tid_s)
	var card_id = pending.get("card_id", "")
	match card_id:
		"triangulation":
			for tid in picks:
				st["triangulated"].append(tid)
				print("MissionManager: 11e Triangulated %s (P%s, player choice)" % [tid, pk])
		"consecrate":
			for tid in picks:
				st["consecrated"].append(tid)
				print("MissionManager: 11e Consecrated %s (P%s, player choice)" % [tid, pk])
		"smoke_and_mirrors":
			if not st.has("decoyed_this_turn"):
				st["decoyed_this_turn"] = []
			for tid in picks:
				st["decoyed"].append(tid)
				st["decoyed_this_turn"].append(tid)
				if not tid in st["decoyed_ever"]:
					st["decoyed_ever"].append(tid)
				print("MissionManager: 11e Decoyed %s (P%s, player choice)" % [tid, pk])
		"death_trap":
			if not st.has("trapped_this_turn"):
				st["trapped_this_turn"] = []
			for tid in picks:
				st["trapped"].append(tid)
				st["trapped_this_turn"].append(tid)
				print("MissionManager: 11e Booby Trapped %s (P%s, player choice)" % [tid, pk])
		"gather_intel":
			for tid in picks:
				st["intel_tokens"].append(tid)
				st["intel_placed_this_turn"] = int(st.get("intel_placed_this_turn", 0)) + 1
				print("MissionManager: 11e intel token on %s (P%s, player choice)" % [tid, pk])
		"extract_relic", "locate_and_deny":
			for tid in picks:
				_relic_markers_11e.erase(tid)
				st["sensor_swept_this_turn"] = true
				_relic_setup_prompt_pending = false
				print("MissionManager: 11e Sensor Sweep removed marker %s (P%s, player choice, %d left)" % [tid, pk, _relic_markers_11e.size()])
		_:
			return {"success": false, "error": "Card %s has no resolvable action" % card_id}
	st["card_action_resolved_this_turn"] = true
	refresh_card_action_visuals_11e()
	return {"success": true, "card_id": card_id, "action_name": pending.get("action_name", ""), "applied": picks}

## Decline the optional card action for this turn: nothing is placed and
## the auto-pick stands down.
func decline_card_action_11e(player: int) -> Dictionary:
	var pk = str(player)
	var st = _primary_state_11e.get(pk, {})
	if st.is_empty():
		return {"success": false, "error": "No 11e primary state for player %d" % player}
	st["card_action_resolved_this_turn"] = true
	print("MissionManager: 11e P%s declined their card action this turn" % pk)
	return {"success": true, "applied": []}

## Punishment: the Command-phase prompt lets the human owner revise the
## auto-Condemn picks (which already stand as the backstop). Returns {}
## unless the prompt is still pending this turn.
func get_pending_condemn_choice_11e(player: int) -> Dictionary:
	if GameConstants.edition < 11:
		return {}
	var pk = str(player)
	var st = _primary_state_11e.get(pk, {})
	if st.is_empty() or not st.get("condemn_prompt_pending", false):
		return {}
	if player_primary_missions.get(pk, {}).get("id", "") != "punishment":
		return {}
	var eligible = []
	for unit_id in _condemn_eligible_units_11e(player):
		var unit = GameState.state.get("units", {}).get(unit_id, {})
		eligible.append({
			"id": unit_id,
			"label": unit.get("meta", {}).get("name", unit_id),
		})
	if eligible.is_empty():
		return {}
	return {
		"player": player,
		"card_id": "punishment",
		"card_name": player_primary_missions.get(pk, {}).get("name", "Punishment"),
		"action_name": "Condemn",
		"description": "Choose up to 3 enemy units in range of an objective to Condemn. 5 VP at the end of any turn in which a Condemned unit left the battlefield.",
		"max_picks": 3,
		"eligible": eligible,
		"current": st.get("condemned", []).duplicate(),
	}

func resolve_condemn_choice_11e(player: int, unit_ids: Array) -> Dictionary:
	var pending = get_pending_condemn_choice_11e(player)
	if pending.is_empty():
		return {"success": false, "error": "No pending Condemn choice for player %d" % player}
	if unit_ids.size() > 3:
		return {"success": false, "error": "Condemn allows at most 3 units"}
	var valid_ids = []
	for e in pending.get("eligible", []):
		valid_ids.append(str(e.get("id", "")))
	var picks = []
	for uid in unit_ids:
		var uid_s = str(uid)
		if not uid_s in valid_ids:
			return {"success": false, "error": "Unit %s is not eligible for Condemn" % uid_s}
		if not uid_s in picks:
			picks.append(uid_s)
	var pk = str(player)
	var st = _primary_state_11e.get(pk, {})
	st["condemned"] = picks
	st["condemn_prompt_pending"] = false
	st["condemn_resolved_turn"] = "R%dP%d" % [GameState.get_battle_round(), player]
	print("MissionManager: 11e Punishment — P%s condemns %s (player choice)" % [pk, str(picks)])
	refresh_card_action_visuals_11e()
	return {"success": true, "condemned": picks}

## Keep the auto-Condemn picks and dismiss the prompt for this turn.
func dismiss_condemn_prompt_11e(player: int) -> Dictionary:
	var pk = str(player)
	var st = _primary_state_11e.get(pk, {})
	if not st.is_empty():
		st["condemn_prompt_pending"] = false
		st["condemn_resolved_turn"] = "R%dP%d" % [GameState.get_battle_round(), player]
	return {"success": true, "condemned": st.get("condemned", []).duplicate()}

## Extract Relic / Locate and Deny setup: the DISRUPTION player chooses the
## five marked terrain areas (outside their deployment zone). The auto-pick
## stands as backstop; a human DI player may revise it during their first
## Command phase — until any Sensor Sweep consumes a marker.
func get_pending_relic_setup_11e(player: int) -> Dictionary:
	if GameConstants.edition < 11 or not _relic_setup_prompt_pending:
		return {}
	if player_dispositions.get(str(player), "") != "disruption":
		return {}
	var eligible_ids = _relic_eligible_features_11e(player)
	if eligible_ids.is_empty():
		return {}
	var required = min(5, eligible_ids.size())
	if _relic_markers_11e.size() < required:
		# A sweep already removed a marker — the setup window is closed.
		_relic_setup_prompt_pending = false
		return {}
	var eligible = []
	for fid in eligible_ids:
		eligible.append({"id": fid, "label": fid})
	return {
		"player": player,
		"action_name": "Mark Terrain Areas",
		"description": "As the Disruption player, choose the %d terrain areas outside your deployment zone that carry the operation markers." % required,
		"required_picks": required,
		"eligible": eligible,
		"current": _relic_markers_11e.duplicate(),
	}

func _relic_eligible_features_11e(di_player: int) -> Array:
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return []
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	var di_zone = secondary_mgr._get_deployment_zone_polygon(di_player) if secondary_mgr != null else PackedVector2Array()
	var out = []
	for feature in tm.terrain_features:
		var fid = str(feature.get("id", ""))
		if fid == "":
			continue
		var fpos = feature.get("position", Vector2.ZERO)
		if fpos is Dictionary:
			fpos = Vector2(fpos.get("x", 0), fpos.get("y", 0))
		if not di_zone.is_empty() and Geometry2D.is_point_in_polygon(fpos, di_zone):
			continue
		out.append(fid)
	return out

func resolve_relic_setup_11e(player: int, feature_ids: Array) -> Dictionary:
	var pending = get_pending_relic_setup_11e(player)
	if pending.is_empty():
		return {"success": false, "error": "No pending relic-marker setup for player %d" % player}
	var required = int(pending.get("required_picks", 5))
	var valid_ids = []
	for e in pending.get("eligible", []):
		valid_ids.append(str(e.get("id", "")))
	var picks = []
	for fid in feature_ids:
		var fid_s = str(fid)
		if not fid_s in valid_ids:
			return {"success": false, "error": "Terrain %s is not eligible for a marker" % fid_s}
		if not fid_s in picks:
			picks.append(fid_s)
	if picks.size() != required:
		return {"success": false, "error": "Exactly %d terrain areas must be marked (got %d)" % [required, picks.size()]}
	_relic_markers_11e = picks
	_relic_setup_prompt_pending = false
	print("MissionManager: 11e relic markers revised to %s (P%d choice)" % [str(picks), player])
	refresh_card_action_visuals_11e()
	return {"success": true, "markers": picks.duplicate()}

## Keep the auto-picked marker locations and close the setup window.
func dismiss_relic_setup_11e(_player: int) -> Dictionary:
	_relic_setup_prompt_pending = false
	return {"success": true, "markers": _relic_markers_11e.duplicate()}

## End-of-game primary scoring for both players (idempotent).
func score_primary_eog_11e() -> void:
	if GameConstants.edition < 11 or player_primary_missions.is_empty():
		return
	if _eog_primary_scored:
		return
	_eog_primary_scored = true
	var battle_round = GameState.get_battle_round()
	for player in [1, 2]:
		_score_primary_11e(player, battle_round, "eog")

func _score_primary_11e(player: int, battle_round: int, timing: String) -> void:
	var pk = str(player)
	var card = player_primary_missions.get(pk, {})
	if card.is_empty():
		print("MissionManager: 11e — no primary mission card for P%s" % pk)
		return

	var vp_total = 0
	var reasons = []
	var group_best = {}  # exclusive_group -> {"vp": int, "type": String}
	for rule in card.get("rules", []):
		if rule.get("when", "command") != timing:
			continue
		var window = rule.get("rounds", [])
		if window.size() == 2 and (battle_round < int(window[0]) or battle_round > int(window[1])):
			continue
		var vp = _evaluate_primary_rule_11e(player, rule, battle_round)
		var group = str(rule.get("exclusive_group", ""))
		if group != "":
			# Official OR tiers: rules sharing an exclusive_group resolve as
			# only-the-highest (e.g. Consecrate 3/6, Triangulation 3/6/10,
			# Reconnaissance Sweep quarters 3/6, Purge and Secure's kill pair).
			if vp > int(group_best.get(group, {}).get("vp", 0)):
				group_best[group] = {"vp": vp, "type": rule.get("type", "?")}
			continue
		if vp > 0:
			vp_total += vp
			reasons.append("%s +%d" % [rule.get("type", "?"), vp])
	for gkey in group_best:
		var best = group_best[gkey]
		if int(best.get("vp", 0)) > 0:
			vp_total += int(best["vp"])
			reasons.append("%s +%d (best tier)" % [best.get("type", "?"), best["vp"]])

	var reason = "%s (%s): %s" % [card.get("name", "?"), timing,
		"; ".join(reasons) if reasons.size() > 0 else "no conditions met"]
	print("MissionManager: 11e primary P%s R%d — %s" % [pk, battle_round, reason])
	_award_primary_vp_11e(player, vp_total, reason, timing)

func _evaluate_primary_rule_11e(player: int, rule: Dictionary, battle_round: int) -> int:
	var opponent = 3 - player
	match rule.get("type", ""):
		"hold_min":
			var count = _count_controlled_filtered_11e(player, rule)
			return rule.get("vp", 0) if count >= int(rule.get("min", 1)) else 0
		"per_objective":
			# require_hold_home: the official cumulative bonus rows only pay
			# while the player also controls their own home objective
			# (Battlefield Dominance award 3).
			if rule.get("require_hold_home", false):
				var own_home = _get_home_objective_id_11e(player)
				if own_home == "" or objective_control_state.get(own_home, 0) != player:
					return 0
			var count = _count_controlled_filtered_11e(player, rule)
			var vp_per = int(rule.get("vp_per", 0))
			var by_round = rule.get("vp_by_round", {})
			if not by_round.is_empty():
				vp_per = int(by_round.get(battle_round, by_round.get(str(battle_round), 0)))
			return count * vp_per
		"per_new_objective":
			# vp_per for EACH objective controlled now but not at the start of
			# the turn (Determined Acquisition award 1).
			var start_ctrl = _control_at_turn_start.get(str(player), [])
			var newly = 0
			for obj_id in _get_controlled_objectives(player):
				if obj_id in start_ctrl:
					continue
				if rule.get("exclude_home", false) and _is_home_objective_11e(obj_id, player):
					continue
				newly += 1
			return newly * int(rule.get("vp_per", 0))
		"hold_more":
			var mine = _get_controlled_objectives(player).size()
			var theirs = _get_controlled_objectives(opponent).size()
			return rule.get("vp", 0) if mine > theirs else 0
		"hold_enemy_home":
			return rule.get("vp", 0) if _controls_enemy_home_11e(player) else 0
		"hold_central":
			var central = _get_central_objective_id_11e()
			return rule.get("vp", 0) if central != "" and objective_control_state.get(central, 0) == player else 0
		"hold_central_plus_nml":
			var central2 = _get_central_objective_id_11e()
			if central2 == "" or objective_control_state.get(central2, 0) != player:
				return 0
			var other_nml = 0
			for obj_id in _get_controlled_nml_objectives(player):
				if obj_id != central2:
					other_nml += 1
			return rule.get("vp", 0) if other_nml >= 1 else 0
		"hold_new":
			var start_set = _control_at_turn_start.get(str(player), [])
			for obj_id in _get_controlled_objectives(player):
				if obj_id in start_set:
					continue
				if rule.get("exclude_home", false) and _is_home_objective_11e(obj_id, player):
					continue
				return rule.get("vp", 0)
			return 0
		"destroyed_min":
			return rule.get("vp", 0) if _kills_this_turn_11e(player) >= int(rule.get("min", 1)) else 0
		"destroyed_per_unit":
			return _kills_this_turn_11e(player) * int(rule.get("vp_per", 0))
		"killed_more_than_opponent_last_turn":
			var my_kills = _kills_this_turn_11e(player)
			# Opponent's most recent turn: same round if the opponent already
			# went this round (i.e. `player` takes the round's SECOND/last turn),
			# otherwise the previous round. NOT hardcoded to P2-second — when the
			# roll-off gives P2 the first turn, P1 takes the round's last turn.
			var opp_round = battle_round if GameState.is_last_turn_of_round(player) else battle_round - 1
			var opp_kills = int(kills_per_round.get(str(opp_round), {}).get(str(opponent), 0))
			return rule.get("vp", 0) if my_kills > opp_kills else 0
		"quarters":
			var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
			if secondary_mgr == null:
				return 0
			var params = {"count": int(rule.get("min", 3)), "min_distance_from_center": 6.0}
			return rule.get("vp", 0) if secondary_mgr._check_table_quarter_presence(player, params) else 0
		"triangulated_count":
			var n = _primary_state_11e.get(str(player), {}).get("triangulated", []).size()
			if rule.has("count_min"):
				# Official tier row: pays vp while the marker count is within
				# [count_min, count_max]; exclusive_group keeps only the best.
				if n >= int(rule.get("count_min", 1)) and n <= int(rule.get("count_max", 9999)):
					return rule.get("vp", 0)
				return 0
			# Legacy rule shape (pre-40kdc saves): hardcoded 3/6/10 tiering
			return 10 if n >= 3 else (6 if n == 2 else (3 if n == 1 else 0))
		"consecrated_count":
			var n2 = _primary_state_11e.get(str(player), {}).get("consecrated", []).size()
			if rule.has("count_min"):
				if n2 >= int(rule.get("count_min", 1)) and n2 <= int(rule.get("count_max", 9999)):
					return rule.get("vp", 0)
				return 0
			# Legacy rule shape (pre-40kdc saves): hardcoded 3/6 tiering
			return 6 if n2 >= 3 else (3 if n2 >= 1 else 0)
		"consecrated_enemy_home":
			var enemy_home = _get_home_objective_id_11e(3 - player)
			var consecrated = _primary_state_11e.get(str(player), {}).get("consecrated", [])
			return rule.get("vp", 0) if enemy_home != "" and enemy_home in consecrated else 0
		"condemned_left":
			return rule.get("vp", 0) if _primary_state_11e.get(str(player), {}).get("condemned_left_this_turn", false) else 0
		"sabotage_per_objective":
			var sab_st = _primary_state_11e.get(str(player), {})
			var total = 0
			if sab_st.get("sabotage_started_this_turn", false):
				# Player used the real per-unit action: only objectives a unit
				# completed Sabotage on score (a failed action scores 0).
				for obj_id in sab_st.get("sabotaged_this_turn", []):
					total += int(rule.get("vp_per", 3))
					if _objective_in_enemy_territory_11e(obj_id, player):
						total += int(rule.get("enemy_territory_bonus", 2))
				return total
			# Approximation backstop: auto-completed Sabotage on each
			# controlled non-home objective
			for obj_id in _get_controlled_objectives(player):
				if _is_home_objective_11e(obj_id, player):
					continue
				total += int(rule.get("vp_per", 3))
				if _objective_in_enemy_territory_11e(obj_id, player):
					total += int(rule.get("enemy_territory_bonus", 2))
			return total
		"central_operation_markers":
			var central3 = _get_central_objective_id_11e()
			if central3 == "" or objective_control_state.get(central3, 0) != player:
				return 0
			var markers = int(_primary_state_11e.get(str(player), {}).get("operation_markers", 0))
			return int(rule.get("vp", 2)) + markers * int(rule.get("vp_per_marker", 1))
		"destroyed_near_central":
			var central4 = _get_central_objective_id_11e()
			if central4 == "":
				return 0
			return rule.get("vp", 0) if _destroyed_enemy_near_objective_11e(player, central4) else 0
		"vanguard_terrain_area":
			var vg_st = _primary_state_11e.get(str(player), {})
			if vg_st.get("vanguard_started_this_turn", false):
				# Player used the real per-unit action this turn
				return rule.get("vp", 0) if vg_st.get("vanguard_completed_this_turn", false) else 0
			return rule.get("vp", 0) if _vanguard_area_held_11e(player) else 0
		"sensor_sweep_vp":
			return rule.get("vp", 0) if _primary_state_11e.get(str(player), {}).get("sensor_swept_this_turn", false) else 0
		"relic_final_marker":
			return rule.get("vp", 0) if _final_relic_marker_held_11e(player) else 0
		"decoyed_score":
			# Official: the Decoyed tag never clears, so every objective ever
			# decoyed keeps paying — the scrubbed marker list only matters for
			# the opponent's no_enemy_markers check (Surveil the Foe).
			var total2 = 0
			var d_st = _primary_state_11e.get(str(player), {})
			for obj_id in d_st.get("decoyed_ever", d_st.get("decoyed", [])):
				total2 += int(rule.get("vp_per", 2))
				if _objective_in_enemy_territory_11e(obj_id, player):
					total2 += int(rule.get("enemy_territory_bonus", 2))
			return total2
		"decoyed_total_eog":
			var ever = _primary_state_11e.get(str(player), {}).get("decoyed_ever", []).size()
			return rule.get("vp", 0) if ever >= int(rule.get("min", 4)) else 0
		"no_enemy_markers":
			var opp_st = _primary_state_11e.get(str(3 - player), {})
			return rule.get("vp", 0) if opp_st.get("decoyed", []).is_empty() else 0
		"intel_tokens_placed":
			var gi_st = _primary_state_11e.get(str(player), {})
			if gi_st.get("intel_started_this_turn", false):
				# Real card: 7 VP per UNIT that completed Extract Intelligence
				return int(gi_st.get("intel_units_this_turn", 0)) * int(rule.get("vp_per", 7))
			return int(gi_st.get("intel_placed_this_turn", 0)) * int(rule.get("vp_per", 7))
		"operation_markers_min":
			# Gather Intel EOG: min+ of your operation markers remain on the
			# battlefield. A player's markers are their intel tokens plus the
			# Vital Link marker counter (only one card is in play per player,
			# so the sum is that card's marker count).
			var om_st = _primary_state_11e.get(str(player), {})
			var marker_count = om_st.get("intel_tokens", []).size() + int(om_st.get("operation_markers", 0))
			return rule.get("vp", 0) if marker_count >= int(rule.get("min", 3)) else 0
		"intel_token_on_enemy_home":
			# Gather Intel EOG: one of your markers is within range of the
			# opponent's home objective. Tokens are keyed by objective id, so
			# the check is exact — but the placement wiring is NML-only, so it
			# cannot currently trigger (rule stays flagged approximate).
			var enemy_home_gi = _get_home_objective_id_11e(3 - player)
			var gi_tokens = _primary_state_11e.get(str(player), {}).get("intel_tokens", [])
			return rule.get("vp", 0) if enemy_home_gi != "" and enemy_home_gi in gi_tokens else 0
		"trapped_score":
			# Official: pays per terrain area trapped THIS TURN (+bonus when
			# the trapped area holds an objective). Pre-40kdc saves lack the
			# per-turn key and fall back to the old all-time list.
			var tm2 = get_node_or_null("/root/TerrainManager")
			var t_st = _primary_state_11e.get(str(player), {})
			var total3 = 0
			for fid in t_st.get("trapped_this_turn", t_st.get("trapped", [])):
				total3 += int(rule.get("vp_per", 2))
				if tm2 != null and _terrain_contains_objective_11e(tm2, fid):
					total3 += int(rule.get("objective_bonus", 3))
			return total3
		"destroyed_started_on_objective":
			return rule.get("vp", 0) if _destroyed_enemy_near_any_objective_11e(player) else 0
		"destroyed_in_terrain_area":
			return rule.get("vp", 0) if _destroyed_enemy_in_terrain_11e(player, rule.get("trapped_only", false)) else 0
		"no_enemy_wholly_in_my_dz":
			return rule.get("vp", 0) if not _enemy_wholly_in_my_dz_11e(player) else 0
		"action":
			var action_name = rule.get("action_name", "?")
			if not _warned_unimplemented_actions.has(action_name):
				_warned_unimplemented_actions[action_name] = true
				print("MissionManager: 11e primary action '%s' is not implemented yet — scores 0 (GDM source approximate)" % action_name)
			return 0
		_:
			print("MissionManager: 11e unknown primary rule type '%s'" % rule.get("type", ""))
			return 0

func _count_controlled_filtered_11e(player: int, rule: Dictionary) -> int:
	var exclude_home = rule.get("exclude_home", false)
	var zone_filter = rule.get("zone", "any")
	var opponent = 3 - player
	var count = 0
	for obj_id in _get_controlled_objectives(player):
		if exclude_home and _is_home_objective_11e(obj_id, player):
			continue
		if zone_filter != "any":
			var zone = _get_objective_by_id(obj_id).get("zone", "no_mans_land")
			var in_enemy = (zone == "player%d" % opponent)
			if zone_filter == "enemy_territory" and not in_enemy:
				continue
			if zone_filter == "not_enemy_territory" and in_enemy:
				continue
			if zone_filter == "nml" and zone != "no_mans_land":
				continue
		count += 1
	return count

func _is_home_objective_11e(obj_id: String, player: int) -> bool:
	return _get_objective_by_id(obj_id).get("zone", "") == "player%d" % player

func _controls_enemy_home_11e(player: int) -> bool:
	var opponent = 3 - player
	for obj in GameState.state.board.get("objectives", []):
		if obj.get("zone", "") == "player%d" % opponent \
				and objective_control_state.get(obj.get("id", ""), 0) == player:
			return true
	return false

func _get_central_objective_id_11e() -> String:
	# Prefer the Chapter Approved "central" designation; fall back to the
	# objective nearest the board centre.
	var centrals = get_objective_ids_by_designation("central")
	if centrals.size() > 0:
		return centrals[0]
	var board_size = GameState.state.get("board", {}).get("size", {})
	var center = Vector2(
		Measurement.inches_to_px(float(board_size.get("width", 44)) / 2.0),
		Measurement.inches_to_px(float(board_size.get("height", 60)) / 2.0))
	var best_id = ""
	var best_dist = INF
	for obj in GameState.state.board.get("objectives", []):
		var pos = obj.get("position")
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		if pos == null:
			continue
		var d = pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_id = obj.get("id", "")
	return best_id

func _get_home_objective_id_11e(player: int) -> String:
	for obj in GameState.state.board.get("objectives", []):
		if obj.get("zone", "") == "player%d" % player:
			return obj.get("id", "")
	return ""

## "In the opponent's territory" — the objective sits in the enemy
## deployment zone, or is the Central objective (per the Sabotage card
## text: the central objective counts).
func _objective_in_enemy_territory_11e(obj_id: String, player: int) -> bool:
	var obj = _get_objective_by_id(obj_id)
	if obj.get("zone", "") == "player%d" % (3 - player):
		return true
	return obj.get("designation", "") == "central"

func _friendly_unit_in_range_of_objective_11e(player: int, obj_id: String, radius_px: float) -> bool:
	return _any_unit_in_range_of_objective_11e(player, obj_id, radius_px)

func _enemy_unit_in_range_of_objective_11e(player: int, obj_id: String, radius_px: float) -> bool:
	return _any_unit_in_range_of_objective_11e(3 - player, obj_id, radius_px)

func _any_unit_in_range_of_objective_11e(owner: int, obj_id: String, radius_px: float) -> bool:
	var obj = _get_objective_by_id(obj_id)
	var obj_pos = obj.get("position")
	if obj_pos == null:
		return false
	if obj_pos is Dictionary:
		obj_pos = Vector2(obj_pos.x, obj_pos.y)
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != owner:
			continue
		for model in unit.get("models", []):
			if not model.get("alive", true) or model.get("position") == null:
				continue
			if Measurement.model_edge_to_point_distance_px(model, obj_pos) <= radius_px:
				return true
	return false

func _player_model_in_terrain_11e(player: int, feature: Dictionary) -> bool:
	var polygon = feature.get("polygon", PackedVector2Array())
	if polygon.is_empty():
		return false
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		for model in unit.get("models", []):
			if not model.get("alive", true) or model.get("position") == null:
				continue
			var pos = model.get("position")
			if pos is Dictionary:
				pos = Vector2(pos.x, pos.y)
			if Geometry2D.is_point_in_polygon(pos, polygon):
				return true
	return false

## Enemy units destroyed this turn (on the battlefield at the active
## player's turn start, fully dead now). Dead models keep their positions,
## which the location-conditioned kill checks below rely on.
func _destroyed_enemy_units_this_turn_11e(player: int) -> Array:
	var out = []
	var snapshot = _alive_at_turn_start_11e.get(str(GameState.get_active_player()), {})
	for unit_id in snapshot:
		var unit = GameState.state.get("units", {}).get(unit_id, {})
		if unit.is_empty() or int(unit.get("owner", 0)) != 3 - player:
			continue
		var any_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				any_alive = true
				break
		if not any_alive:
			out.append(unit_id)
	return out

func _destroyed_enemy_near_objective_11e(player: int, obj_id: String) -> bool:
	var control_radius = Measurement.inches_to_px(3.78740157)
	var obj = _get_objective_by_id(obj_id)
	var obj_pos = obj.get("position")
	if obj_pos == null:
		return false
	if obj_pos is Dictionary:
		obj_pos = Vector2(obj_pos.x, obj_pos.y)
	for unit_id in _destroyed_enemy_units_this_turn_11e(player):
		var unit = GameState.state.units[unit_id]
		for model in unit.get("models", []):
			if model.get("position") == null:
				continue
			if Measurement.model_edge_to_point_distance_px(model, obj_pos) <= control_radius:
				return true
	return false

func _destroyed_enemy_near_any_objective_11e(player: int) -> bool:
	for obj in GameState.state.board.get("objectives", []):
		if _destroyed_enemy_near_objective_11e(player, obj.get("id", "")):
			return true
	return false

func _destroyed_enemy_in_terrain_11e(player: int, trapped_only: bool = false) -> bool:
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return false
	# Death Trap: only kills inside terrain the player Booby Trapped count
	var trapped = _primary_state_11e.get(str(player), {}).get("trapped", []) if trapped_only else []
	for unit_id in _destroyed_enemy_units_this_turn_11e(player):
		var unit = GameState.state.units[unit_id]
		for model in unit.get("models", []):
			var pos = model.get("position")
			if pos == null:
				continue
			if pos is Dictionary:
				pos = Vector2(pos.x, pos.y)
			var terrain = tm.get_terrain_at_position(pos)
			if terrain.is_empty():
				continue
			if trapped_only and not str(terrain.get("id", "")) in trapped:
				continue
			return true
	return false

## Vanguard Operation: a friendly unit is inside a terrain area located in
## enemy territory (feature position inside the enemy deployment zone —
## approximation) with no enemy units in that area.
func _vanguard_area_held_11e(player: int) -> bool:
	var tm = get_node_or_null("/root/TerrainManager")
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if tm == null or secondary_mgr == null:
		return false
	var enemy_zone = secondary_mgr._get_deployment_zone_polygon(3 - player)
	if enemy_zone.is_empty():
		return false
	for feature in tm.terrain_features:
		var fpos = feature.get("position", Vector2.ZERO)
		if not Geometry2D.is_point_in_polygon(fpos, enemy_zone):
			continue
		if _player_model_in_terrain_11e(player, feature) and not _player_model_in_terrain_11e(3 - player, feature):
			return true
	return false

func _final_relic_marker_held_11e(player: int) -> bool:
	if _relic_markers_11e.size() != 1:
		return false
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return false
	for feature in tm.terrain_features:
		if feature.get("id", "") != _relic_markers_11e[0]:
			continue
		return _player_model_in_terrain_11e(player, feature) and not _player_model_in_terrain_11e(3 - player, feature)
	return false

func _terrain_contains_objective_11e(tm, feature_id: String) -> bool:
	for feature in tm.terrain_features:
		if feature.get("id", "") != feature_id:
			continue
		var polygon = feature.get("polygon", PackedVector2Array())
		for obj in GameState.state.board.get("objectives", []):
			var pos = obj.get("position")
			if pos is Dictionary:
				pos = Vector2(pos.x, pos.y)
			if not polygon.is_empty() and Geometry2D.is_point_in_polygon(pos, polygon):
				return true
	return false

func _enemy_wholly_in_my_dz_11e(player: int) -> bool:
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr == null:
		return false
	var my_zone = secondary_mgr._get_deployment_zone_polygon(player)
	if my_zone.is_empty():
		return false
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != 3 - player or not _unit_on_battlefield_11e(unit_id):
			continue
		if secondary_mgr._is_unit_wholly_in_zone(unit, my_zone):
			return true
	return false

func _kills_this_turn_11e(player: int) -> int:
	# Best available proxy: kills recorded for this player this battle round
	# (count_destroyed_units_this_round refreshes it before each scoring call).
	var battle_round = str(GameState.get_battle_round())
	var from_rounds = int(kills_per_round.get(battle_round, {}).get(str(player), 0))
	return max(from_rounds, int(_kills_this_round.get(str(player), 0)))

func _award_primary_vp_11e(player: int, vp_earned: int, reason: String, timing: String) -> void:
	if vp_earned <= 0:
		return
	var pk = str(player)
	if not GameState.state.players.has(pk):
		GameState.state.players[pk] = {}

	# 15 VP per-turn window (EOG scoring happens outside any turn — total cap only)
	if timing != "eog":
		var turn_so_far = int(_primary_vp_this_turn.get(pk, 0))
		var turn_room = PrimaryMissionData11e.MAX_PRIMARY_VP_PER_TURN_11E - turn_so_far
		if vp_earned > turn_room:
			print("MissionManager: 11e P%s primary clipped by 15/turn cap (%d -> %d)" % [pk, vp_earned, max(0, turn_room)])
			vp_earned = max(0, turn_room)

	# 45 VP total cap
	var primary_vp = int(GameState.state.players[pk].get("primary_vp", 0))
	var total_room = PrimaryMissionData11e.MAX_PRIMARY_VP_11E - primary_vp
	if vp_earned > total_room:
		print("MissionManager: 11e P%s primary clipped by 45 total cap (%d -> %d)" % [pk, vp_earned, max(0, total_room)])
		vp_earned = max(0, total_room)
	if vp_earned <= 0:
		return

	if timing != "eog":
		_primary_vp_this_turn[pk] = int(_primary_vp_this_turn.get(pk, 0)) + vp_earned
	GameState.state.players[pk]["primary_vp"] = primary_vp + vp_earned
	GameState.state.players[pk]["vp"] = int(GameState.state.players[pk].get("vp", 0)) + vp_earned
	emit_signal("victory_points_scored", player, vp_earned, reason)
	print("MissionManager: 11e P%s scored %d primary VP (%s) — primary total %d/45" % [
		pk, vp_earned, reason, primary_vp + vp_earned])

func get_primary_mission_for_player(player: int) -> Dictionary:
	return player_primary_missions.get(str(player), {}).duplicate(true)

# ============================================================
# HELPER METHODS
# ============================================================

func _get_controlled_objectives(player: int) -> Array:
	"""Get list of objective IDs controlled by a player (excluding removed/burned)."""
	var controlled = []
	for obj_id in objective_control_state:
		if obj_id in removed_objectives or obj_id in burned_objectives:
			continue
		if objective_control_state[obj_id] == player:
			controlled.append(obj_id)
	return controlled

func _get_controlled_nml_objectives(player: int) -> Array:
	"""Get NML objectives controlled by a player (for Supply Drop)."""
	var controlled = []
	var objectives = GameState.state.board.get("objectives", [])

	for obj in objectives:
		if obj.get("zone", "") != "no_mans_land":
			continue
		if obj.id in removed_objectives:
			continue
		if objective_control_state.get(obj.id, 0) == player:
			controlled.append(obj.id)
	return controlled

func _get_nml_objective_ids() -> Array:
	"""Get all no-man's-land objective IDs."""
	var nml_ids = []
	var objectives = GameState.state.board.get("objectives", [])
	for obj in objectives:
		if obj.get("zone", "") == "no_mans_land":
			nml_ids.append(obj.id)
	return nml_ids

func _get_objective_by_id(objective_id: String) -> Dictionary:
	"""Find an objective by its ID."""
	var objectives = GameState.state.board.get("objectives", [])
	for obj in objectives:
		if obj.id == objective_id:
			return obj
	return {}

func _award_primary_vp(player: int, vp_earned: int, reason: String) -> void:
	"""Award primary VP to a player, respecting max caps."""
	if vp_earned <= 0:
		print("MissionManager: Player %d scored 0 VP" % player)
		return

	var player_key = str(player)
	if not GameState.state.players.has(player_key):
		GameState.state.players[player_key] = {}

	var current_vp = GameState.state.players[player_key].get("vp", 0)
	var primary_vp = GameState.state.players[player_key].get("primary_vp", 0)

	# Cap at max primary VP
	var max_vp = current_mission.get("max_vp", 50)
	var new_primary_vp = min(primary_vp + vp_earned, max_vp)
	var actual_vp_earned = new_primary_vp - primary_vp

	if actual_vp_earned <= 0:
		print("MissionManager: Player %d at max primary VP (%d)" % [player, max_vp])
		return

	GameState.state.players[player_key]["vp"] = current_vp + actual_vp_earned
	GameState.state.players[player_key]["primary_vp"] = new_primary_vp

	emit_signal("victory_points_scored", player, actual_vp_earned, reason)

	print("MissionManager: Player %d scored %d VP (%s)" % [player, actual_vp_earned, reason])
	print("MissionManager: Player %d total VP: %d (Primary: %d)" % [player, current_vp + actual_vp_earned, new_primary_vp])

# Alias for HEAD's VP application function — delegates to _award_primary_vp
func _apply_primary_vp(active_player: int, vp_earned: int, reason: String) -> void:
	_award_primary_vp(active_player, vp_earned, reason)

func is_objective_active(objective_id: String) -> bool:
	"""Check if an objective is still active (not removed or burned)."""
	return objective_id not in removed_objectives and objective_id not in burned_objectives

func get_mission_type() -> String:
	"""Get the current mission type ID."""
	return current_mission.get("id", "take_and_hold")

func is_scorched_earth_mission() -> bool:
	"""Check if the current mission is Scorched Earth (hold_and_burn)."""
	return current_mission.get("id", "") == "scorched_earth" or current_mission.get("scoring_type", "") == "hold_and_burn"

func is_ritual_mission() -> bool:
	"""Check if the current mission is The Ritual."""
	return current_mission.get("id", "") == "the_ritual" or current_mission.get("scoring_type", "") == "ritual"

func is_terraform_mission() -> bool:
	"""Check if the current mission is Terraform."""
	return current_mission.get("id", "") == "terraform" or current_mission.get("scoring_type", "") == "terraform"

func score_end_of_game_burn_bonus() -> void:
	"""Award end-of-game bonus VP for burned objectives in Scorched Earth missions."""
	if not is_scorched_earth_mission():
		return
	# No bonus needed — burn VP is already awarded when objectives are burned during gameplay
	print("MissionManager: End-of-game burn bonus check (Scorched Earth) — no additional bonus to award")

# ============================================================
# SUMMARY / QUERY METHODS
# ============================================================

# ============================================================================
# KILL TRACKING — for Purge the Foe
# ============================================================================

## Call this when an enemy unit is destroyed during a battle round.
## Also updates per-round kill tracking for detailed kill detection.
func record_unit_destroyed(destroyed_by_player: int) -> void:
	var player_key = str(destroyed_by_player)
	_kills_this_round[player_key] = _kills_this_round.get(player_key, 0) + 1
	print("MissionManager: Player %d destroyed a unit (total this round: %d)" % [destroyed_by_player, _kills_this_round[player_key]])

	# Also update per-round tracking
	var battle_round = str(GameState.get_battle_round())
	if not kills_per_round.has(battle_round):
		kills_per_round[battle_round] = {"1": 0, "2": 0}
	kills_per_round[battle_round][player_key] = kills_per_round[battle_round].get(player_key, 0) + 1

## Reset kill counts at the start of each battle round.
func reset_round_kills() -> void:
	_kills_this_round = {"1": 0, "2": 0}
	print("MissionManager: Reset round kill counts")

# ============================================================================
# ACCESSORS
# ============================================================================

func get_current_mission_id() -> String:
	return current_mission.get("id", "take_and_hold")

func get_current_mission_name() -> String:
	return current_mission.get("name", "Take and Hold")

func get_objective_control_summary() -> Dictionary:
	var summary = {
		"objectives": {},
		"player1_controlled": 0,
		"player2_controlled": 0,
		"contested": 0
	}

	for obj_id in objective_control_state:
		if obj_id in removed_objectives or obj_id in burned_objectives:
			continue

		var controller = objective_control_state[obj_id]
		summary.objectives[obj_id] = controller

		match controller:
			1:
				summary.player1_controlled += 1
			2:
				summary.player2_controlled += 1
			_:
				summary.contested += 1

	return summary

func get_vp_summary() -> Dictionary:
	var p1_vp = GameState.state.players.get("1", {}).get("vp", 0)
	var p1_primary = GameState.state.players.get("1", {}).get("primary_vp", 0)
	var p1_secondary = GameState.state.players.get("1", {}).get("secondary_vp", 0)
	var p2_vp = GameState.state.players.get("2", {}).get("vp", 0)
	var p2_primary = GameState.state.players.get("2", {}).get("primary_vp", 0)
	var p2_secondary = GameState.state.players.get("2", {}).get("secondary_vp", 0)

	return {
		"player1": {
			"total": p1_vp,
			"primary": p1_primary,
			"secondary": p1_secondary,
		},
		"player2": {
			"total": p2_vp,
			"primary": p2_primary,
			"secondary": p2_secondary,
		}
	}

## P3-128: Record a VP snapshot for the current round (called from ScoringPhase at end of each player's turn)
func record_vp_snapshot(battle_round: int) -> void:
	var p1_data = GameState.state.players.get("1", {})
	var p2_data = GameState.state.players.get("2", {})
	_vp_timeline[battle_round] = {
		"1": {
			"total": p1_data.get("vp", 0),
			"primary": p1_data.get("primary_vp", 0),
			"secondary": p1_data.get("secondary_vp", 0),
		},
		"2": {
			"total": p2_data.get("vp", 0),
			"primary": p2_data.get("primary_vp", 0),
			"secondary": p2_data.get("secondary_vp", 0),
		},
	}
	print("MissionManager: P3-128 VP snapshot for round %d — P1: %d VP, P2: %d VP" % [
		battle_round,
		_vp_timeline[battle_round]["1"]["total"],
		_vp_timeline[battle_round]["2"]["total"],
	])

## P3-128: Get the full VP timeline for the chart
func get_vp_timeline() -> Dictionary:
	return _vp_timeline.duplicate(true)

func get_burn_state() -> Dictionary:
	"""Get current burn state for UI display."""
	return {
		"in_progress": burn_in_progress.duplicate(),
		"completed": burned_objectives.duplicate()
	}

func get_removed_objectives() -> Array:
	"""Get list of removed objective IDs (burned + supply drop removed)."""
	var all_removed = removed_objectives.duplicate()
	for obj_id in burned_objectives:
		if obj_id not in all_removed:
			all_removed.append(obj_id)
	return all_removed

# ============================================================================
# Issue #379: SAVE/LOAD SUPPORT
# ============================================================================
# Same pattern as PR #347 (FactionAbilityManager / StratagemManager).
# Without these, mid-game save/load drops sticky objectives, kill counters,
# burn state, supply-drop, ritual/terraform pending actions, etc.

func get_state_for_save() -> Dictionary:
	"""Return state data for save games. Covers all 17 runtime state vars."""
	return {
		"current_mission": current_mission.duplicate(true),
		"objective_control_state": objective_control_state.duplicate(true),
		"sticky_objectives": _sticky_objectives.duplicate(true),
		"kills_this_round": _kills_this_round.duplicate(true),
		"burned_objectives_meta": _burned_objectives.duplicate(true),
		"pending_burns": _pending_burns.duplicate(true),
		"ritual_objectives": _ritual_objectives.duplicate(true),
		"pending_rituals": _pending_rituals.duplicate(true),
		"terraformed_objectives": _terraformed_objectives.duplicate(true),
		"pending_terraforms": _pending_terraforms.duplicate(true),
		"vp_timeline": _vp_timeline.duplicate(true),
		"burn_in_progress": burn_in_progress.duplicate(true),
		"burned_objectives_arr": burned_objectives.duplicate(true),
		"removed_objectives": removed_objectives.duplicate(true),
		"supply_drop_resolved_round_4": supply_drop_resolved_round_4,
		"kills_per_round": kills_per_round.duplicate(true),
		"character_claimed_objectives": character_claimed_objectives.duplicate(true),
		"units_alive_at_round_start": _units_alive_at_round_start.duplicate(true),
		"player_dispositions": player_dispositions.duplicate(true),
		"player_primary_missions": player_primary_missions.duplicate(true),
		"primary_vp_this_turn": _primary_vp_this_turn.duplicate(true),
		"control_at_turn_start": _control_at_turn_start.duplicate(true),
		"eog_primary_scored": _eog_primary_scored,
		"primary_state_11e": _primary_state_11e.duplicate(true),
		"relic_markers_11e": _relic_markers_11e.duplicate(true),
		"relic_setup_prompt_pending": _relic_setup_prompt_pending,
		"alive_at_turn_start_11e": _alive_at_turn_start_11e.duplicate(true)
	}

func load_state(data: Dictionary) -> void:
	"""Restore state from save data."""
	current_mission = data.get("current_mission", current_mission)
	objective_control_state = data.get("objective_control_state", {})
	_sticky_objectives = data.get("sticky_objectives", {})
	_kills_this_round = data.get("kills_this_round", {"1": 0, "2": 0})
	_burned_objectives = data.get("burned_objectives_meta", {})
	_pending_burns = data.get("pending_burns", {})
	_ritual_objectives = data.get("ritual_objectives", {})
	_pending_rituals = data.get("pending_rituals", {})
	_terraformed_objectives = data.get("terraformed_objectives", {})
	_pending_terraforms = data.get("pending_terraforms", {})
	_vp_timeline = data.get("vp_timeline", {})
	burn_in_progress = data.get("burn_in_progress", {})
	burned_objectives = data.get("burned_objectives_arr", [])
	removed_objectives = data.get("removed_objectives", [])
	supply_drop_resolved_round_4 = data.get("supply_drop_resolved_round_4", false)
	kills_per_round = data.get("kills_per_round", {})
	character_claimed_objectives = data.get("character_claimed_objectives", {})
	_units_alive_at_round_start = data.get("units_alive_at_round_start", {})
	player_dispositions = data.get("player_dispositions", {})
	player_primary_missions = data.get("player_primary_missions", {})
	_primary_vp_this_turn = data.get("primary_vp_this_turn", {"1": 0, "2": 0})
	_control_at_turn_start = data.get("control_at_turn_start", {})
	_eog_primary_scored = data.get("eog_primary_scored", false)
	_primary_state_11e = data.get("primary_state_11e", {})
	_relic_markers_11e = data.get("relic_markers_11e", [])
	_relic_setup_prompt_pending = data.get("relic_setup_prompt_pending", false)
	_alive_at_turn_start_11e = data.get("alive_at_turn_start_11e", {})
	refresh_card_action_visuals_11e()
	print("MissionManager: Loaded state — %d sticky, %d burned, %d ritual" % [
		_sticky_objectives.size(), burned_objectives.size(), _ritual_objectives.size()
	])

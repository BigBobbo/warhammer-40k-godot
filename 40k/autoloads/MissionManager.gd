extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# MissionManager - Handles mission objectives, control, and victory point scoring
# Supports multiple primary missions via MissionData registry

signal objective_control_changed(objective_id: String, controller: int, old_controller: int)
signal victory_points_scored(player: int, points: int, reason: String)
signal objective_removed(objective_id: String)
signal objective_burned(objective_id: String, player: int)
signal objective_burn_started(objective_id: String, player: int)
signal objective_burn_completed(objective_id: String, player: int)

var current_mission: Dictionary = {}
var objective_control_state: Dictionary = {} # objective_id -> controlling_player
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

func _ready() -> void:
	print("MissionManager: Initializing mission system")
	initialize_default_mission()

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

	print("MissionManager: Initialized '%s' mission (scoring_type: %s)" % [current_mission.name, current_mission.scoring_type])

func _setup_objectives_for_deployment(deployment_type: String) -> void:
	# Get objective positions from centralized data source (already in pixels)
	var objectives = DeploymentZoneData.get_objectives_px(deployment_type)

	# Store objectives in GameState
	GameState.state.board["objectives"] = objectives

	# Initialize control state
	objective_control_state.clear()
	_sticky_objectives.clear()
	for obj in objectives:
		objective_control_state[obj.id] = 0  # 0 = contested/uncontrolled

	print("MissionManager: Set up %d objectives for %s deployment" % [objectives.size(), deployment_type])
	for obj in objectives:
		print("  - %s at position %s (zone: %s)" % [obj.id, obj.position, obj.get("zone", "unknown")])

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
		var controller = _check_objective_control(obj, units)
		var old_controller = objective_control_state.get(obj.id, 0)

		if controller != old_controller:
			objective_control_state[obj.id] = controller
			emit_signal("objective_control_changed", obj.id, controller, old_controller)
			print("MissionManager: %s control changed from %d to %d" % [obj.id, old_controller, controller])

func _check_objective_control(objective: Dictionary, units: Dictionary) -> int:
	# Control radius is 3" + 20mm (radius of objective marker)
	# 20mm = 0.78740157 inches, so total is 3.78740157 inches
	var control_radius = Measurement.inches_to_px(3.78740157)
	var obj_pos = objective.position

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

	# If a player actively controls via OC, that overrides any sticky lock
	# (opponent "controls it at the start or end of any turn" breaks sticky)
	if oc_controller > 0:
		# If the opponent now controls via OC, clear any sticky lock
		var obj_id = objective.get("id", "")
		if _sticky_objectives.has(obj_id) and _sticky_objectives[obj_id].player != oc_controller:
			print("MissionManager: Sticky lock on %s broken — Player %d now controls via OC" % [obj_id, oc_controller])
			_sticky_objectives.erase(obj_id)
		return oc_controller

	# No one has OC presence — check for sticky lock
	var obj_id = objective.get("id", "")
	if _sticky_objectives.has(obj_id):
		var sticky_data = _sticky_objectives[obj_id]
		var sticky_player = sticky_data.player
		var source_unit_id = sticky_data.source_unit_id

		# Verify the source unit is still alive on the battlefield
		var source_unit = GameState.state.get("units", {}).get(source_unit_id, {})
		var source_alive = false
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
	var control_radius = Measurement.inches_to_px(3.78740157)

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
				var model_pos = model.get("position")
				if model_pos == null:
					continue
				if model_pos is Dictionary:
					model_pos = Vector2(model_pos.x, model_pos.y)
				var edge_distance = Measurement.model_edge_to_point_distance_px(model, obj.position)
				if edge_distance <= control_radius:
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

# ============================================================================
# PRIMARY SCORING — dispatches to mission-specific scoring logic
# ============================================================================

# ============================================================
# SCORING DISPATCH
# ============================================================

func score_primary_objectives() -> void:
	var battle_round = GameState.get_battle_round()
	var active_player = GameState.get_active_player()
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

	# Only process removal once, when the first player scores in round 4
	if battle_round == 4 and not supply_drop_resolved_round_4 and active_player == 1:
		var remove_count = removal_rules.get("round_4_remove_count", 1)
		var nml_objectives = _get_nml_objective_ids()

		# Remove objectives that haven't already been removed
		var available_for_removal = []
		for obj_id in nml_objectives:
			if obj_id not in removed_objectives:
				available_for_removal.append(obj_id)

		for i in range(min(remove_count, available_for_removal.size())):
			# Pick randomly
			var idx = randi() % available_for_removal.size()
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

extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# MissionManager - Handles mission objectives, control, and victory point scoring
# Supports multiple primary missions: Take and Hold, Scorched Earth, Supply Drop,
# Purge the Foe, and Sites of Power.

signal objective_control_changed(objective_id: String, controller: int)
signal victory_points_scored(player: int, points: int, reason: String)
signal objective_removed(objective_id: String)
signal objective_burn_started(objective_id: String, player: int)
signal objective_burn_completed(objective_id: String, player: int)

var current_mission: Dictionary = {}
var objective_control_state: Dictionary = {} # objective_id -> controlling_player
var objectives_visual_refs: Dictionary = {} # Store references to visual nodes

# --- Scorched Earth state ---
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

func initialize_mission(mission_type: String) -> void:
	# Load mission definition from MissionData registry
	current_mission = MissionData.get_mission(mission_type)

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

	print("MissionManager: Initialized '%s' mission for %s deployment" % [current_mission.name, deployment_type])

func initialize_default_mission() -> void:
	# Check if GameState has a mission config stored (from MainMenu)
	var game_config = GameState.state.get("meta", {}).get("game_config", {})
	var mission_type = game_config.get("mission", "take_and_hold")
	initialize_mission(mission_type)

func _setup_objectives_for_deployment(deployment_type: String) -> void:
	# Get objective positions from centralized data source (already in pixels)
	var objectives = DeploymentZoneData.get_objectives_px(deployment_type)

	# Store objectives in GameState
	GameState.state.board["objectives"] = objectives

	# Initialize control state
	objective_control_state.clear()
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
			emit_signal("objective_control_changed", obj.id, controller)
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
		var oc_value = unit.get("meta", {}).get("stats", {}).get("objective_control", 0)
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

			# Check if within control range
			var distance = model_pos.distance_to(obj_pos)
			var distance_inches = Measurement.px_to_inches(distance)

			# Debug log for each model checked
			print("  Model from %s at %s, distance: %.1f\" (%.1fpx) from %s at %s" % [
				unit_id, model_pos, distance_inches, distance, objective.id, obj_pos
			])

			if distance <= control_radius:
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

	# Determine controller
	if player1_oc > player2_oc:
		return 1
	elif player2_oc > player1_oc:
		return 2
	else:
		return 0  # Contested or uncontrolled

# ============================================================
# SCORING DISPATCH
# ============================================================

func score_primary_objectives() -> void:
	var battle_round = GameState.get_battle_round()
	var active_player = GameState.get_active_player()

	print("MissionManager: Scoring '%s' for Player %d in battle round %d" % [current_mission.name, active_player, battle_round])

	# No scoring in Round 1 for any mission
	var start_round = current_mission.get("scoring_rules", {}).get("start_round", 2)
	if battle_round < start_round:
		print("MissionManager: No scoring before round %d" % start_round)
		return

	# Handle round-start events (objective removal for Supply Drop, burn completion for Scorched Earth)
	_process_round_start_events(battle_round, active_player)

	# Dispatch to mission-specific scoring
	var scoring_type = current_mission.get("scoring_type", "hold_objectives")
	match scoring_type:
		"hold_objectives":
			_score_take_and_hold(active_player, battle_round)
		"hold_and_burn":
			_score_scorched_earth(active_player, battle_round)
		"supply_drop":
			_score_supply_drop(active_player, battle_round)
		"purge_the_foe":
			_score_purge_the_foe(active_player, battle_round)
		"sites_of_power":
			_score_sites_of_power(active_player, battle_round)
		_:
			print("MissionManager: Unknown scoring type '%s', using take_and_hold" % scoring_type)
			_score_take_and_hold(active_player, battle_round)

# ============================================================
# TAKE AND HOLD SCORING
# ============================================================

func _score_take_and_hold(active_player: int, _battle_round: int) -> void:
	var controlled_objectives = _get_controlled_objectives(active_player)
	var controlled_count = controlled_objectives.size()

	if controlled_count > 0:
		print("MissionManager: Player %d controls %d objectives: %s" % [active_player, controlled_count, controlled_objectives])
	else:
		print("MissionManager: Player %d controls no objectives" % active_player)

	var rules = current_mission.scoring_rules
	var vp_earned = min(
		controlled_count * rules.vp_per_objective,
		rules.max_vp_per_turn
	)

	_award_primary_vp(active_player, vp_earned, "Controlled %d objectives" % controlled_count)

# ============================================================
# SCORCHED EARTH SCORING
# ============================================================

func _score_scorched_earth(active_player: int, battle_round: int) -> void:
	# Standard objective holding (lower cap: 10VP/turn)
	var controlled_objectives = _get_controlled_objectives(active_player)
	var controlled_count = controlled_objectives.size()

	var rules = current_mission.scoring_rules
	var hold_vp = min(
		controlled_count * rules.vp_per_objective,
		rules.max_vp_per_turn
	)

	_award_primary_vp(active_player, hold_vp, "Controlled %d objectives" % controlled_count)

	# Check for completed burns
	_process_burn_completions(active_player, battle_round)

func start_burn_action(objective_id: String, player: int) -> Dictionary:
	"""Start a burn action on an objective. Returns success/failure."""
	var battle_round = GameState.get_battle_round()
	var burn_rules = current_mission.get("burn_rules", {})

	if current_mission.get("scoring_type", "") != "hold_and_burn":
		return {"success": false, "reason": "Current mission does not support burning"}

	if battle_round < burn_rules.get("start_round", 2):
		return {"success": false, "reason": "Cannot burn before round %d" % burn_rules.start_round}

	if objective_id in burned_objectives:
		return {"success": false, "reason": "Objective already burned"}

	if burn_in_progress.has(objective_id):
		return {"success": false, "reason": "Burn already in progress on this objective"}

	# Check zone restrictions
	var obj = _get_objective_by_id(objective_id)
	if obj.is_empty():
		return {"success": false, "reason": "Objective not found"}

	var obj_zone = obj.get("zone", "no_mans_land")
	if obj_zone == "player%d" % player and not burn_rules.get("can_burn_home", false):
		return {"success": false, "reason": "Cannot burn your own home objective"}

	if obj_zone == "no_mans_land" and not burn_rules.get("can_burn_nml", true):
		return {"success": false, "reason": "Cannot burn no-man's-land objectives"}

	# Determine enemy home zone
	var enemy_player = 1 if player == 2 else 2
	if obj_zone == "player%d" % enemy_player and not burn_rules.get("can_burn_enemy_home", true):
		return {"success": false, "reason": "Cannot burn enemy home objective"}

	# Start the burn
	burn_in_progress[objective_id] = {
		"player": player,
		"started_round": battle_round
	}

	print("MissionManager: Player %d started burning %s (round %d)" % [player, objective_id, battle_round])
	emit_signal("objective_burn_started", objective_id, player)

	return {"success": true}

func _process_burn_completions(active_player: int, battle_round: int) -> void:
	"""Check and complete any burns. Burns complete at end of opponent's next turn."""
	var completed_burns = []
	var burn_rules = current_mission.get("burn_rules", {})

	for obj_id in burn_in_progress:
		var burn_data = burn_in_progress[obj_id]
		var burn_player = burn_data["player"]
		var burn_round = burn_data["started_round"]

		# A burn completes at the end of the opponent's next turn after it started.
		# Simplified: complete if we're in a later round than when it started
		# and the active player is the one who started the burn.
		if battle_round > burn_round and active_player == burn_player:
			completed_burns.append(obj_id)

	for obj_id in completed_burns:
		var burn_data = burn_in_progress[obj_id]
		var burn_player = burn_data["player"]

		# Determine bonus VP
		var obj = _get_objective_by_id(obj_id)
		var obj_zone = obj.get("zone", "no_mans_land")
		var bonus_vp = 0
		var enemy_player = 1 if burn_player == 2 else 2

		if obj_zone == "no_mans_land":
			bonus_vp = burn_rules.get("nml_burn_bonus_vp", 5)
		elif obj_zone == "player%d" % enemy_player:
			bonus_vp = burn_rules.get("enemy_home_burn_bonus_vp", 10)

		# Remove the objective
		burned_objectives.append(obj_id)
		burn_in_progress.erase(obj_id)
		objective_control_state.erase(obj_id)

		if bonus_vp > 0:
			_award_primary_vp(burn_player, bonus_vp, "Burned objective %s" % obj_id)

		print("MissionManager: Burn completed on %s by Player %d (+%d VP)" % [obj_id, burn_player, bonus_vp])
		emit_signal("objective_burn_completed", obj_id, burn_player)
		emit_signal("objective_removed", obj_id)

# ============================================================
# SUPPLY DROP SCORING
# ============================================================

func _score_supply_drop(active_player: int, battle_round: int) -> void:
	# Only score from no-man's-land objectives
	var nml_controlled = _get_controlled_nml_objectives(active_player)
	var controlled_count = nml_controlled.size()

	var rules = current_mission.scoring_rules
	var vp_per_obj = rules.vp_per_objective

	# Round 5 bonus: remaining NML objective is worth extra
	var removal_rules = current_mission.get("removal_rules", {})
	if battle_round >= 5 and controlled_count > 0:
		var bonus = removal_rules.get("round_5_bonus_vp", 10)
		var vp_earned = min(controlled_count * vp_per_obj + bonus, rules.max_vp_per_turn)
		_award_primary_vp(active_player, vp_earned, "Held %d supply drop objectives (+bonus)" % controlled_count)
	else:
		var vp_earned = min(controlled_count * vp_per_obj, rules.max_vp_per_turn)
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
# PURGE THE FOE SCORING
# ============================================================

func _score_purge_the_foe(active_player: int, battle_round: int) -> void:
	var rules = current_mission.scoring_rules
	var opponent = 1 if active_player == 2 else 2
	var total_vp = 0

	# Holding scoring: 4VP for holding any, 8VP if holding more than opponent
	var my_controlled = _get_controlled_objectives(active_player).size()
	var opp_controlled = _get_controlled_objectives(opponent).size()

	if my_controlled > 0:
		if my_controlled > opp_controlled:
			total_vp += rules.hold_more_vp
			print("MissionManager: Player %d holds more objectives (%d vs %d) -> +%d VP" % [active_player, my_controlled, opp_controlled, rules.hold_more_vp])
		else:
			total_vp += rules.hold_any_vp
			print("MissionManager: Player %d holds objectives (%d) -> +%d VP" % [active_player, my_controlled, rules.hold_any_vp])

	# Kill scoring: 4VP for killing any, 8VP if killed more than opponent
	var round_key = str(battle_round)
	var my_kills = kills_per_round.get(round_key, {}).get(str(active_player), 0)
	var opp_kills = kills_per_round.get(round_key, {}).get(str(opponent), 0)

	if my_kills > 0:
		if my_kills > opp_kills:
			total_vp += rules.kill_more_vp
			print("MissionManager: Player %d killed more units (%d vs %d) -> +%d VP" % [active_player, my_kills, opp_kills, rules.kill_more_vp])
		else:
			total_vp += rules.kill_any_vp
			print("MissionManager: Player %d killed units (%d) -> +%d VP" % [active_player, my_kills, rules.kill_any_vp])

	total_vp = min(total_vp, rules.max_vp_per_turn)
	_award_primary_vp(active_player, total_vp, "Purge: held %d obj, killed %d units" % [my_controlled, my_kills])

func record_unit_destroyed(destroyed_unit_owner: int, destroying_player: int) -> void:
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

func is_objective_active(objective_id: String) -> bool:
	"""Check if an objective is still active (not removed or burned)."""
	return objective_id not in removed_objectives and objective_id not in burned_objectives

func get_mission_type() -> String:
	"""Get the current mission type ID."""
	return current_mission.get("id", "take_and_hold")

# ============================================================
# SUMMARY / QUERY METHODS
# ============================================================

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
	var p2_vp = GameState.state.players.get("2", {}).get("vp", 0)
	var p2_primary = GameState.state.players.get("2", {}).get("primary_vp", 0)

	return {
		"player1": {
			"total": p1_vp,
			"primary": p1_primary
		},
		"player2": {
			"total": p2_vp,
			"primary": p2_primary
		}
	}

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

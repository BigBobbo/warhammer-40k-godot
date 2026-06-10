extends Node
class_name GameStateData

# Modular Game State for Warhammer 40k
# This class represents the complete game state that can be serialized and passed between phases

# NOTE: FIRST_TURN_ROLLOFF is intentionally appended LAST so existing phase
# int values (saved games, scenarios) are not renumbered. 10th edition has TWO
# pre-battle roll-offs: ROLL_OFF (pre-deployment) decides who DEPLOYS first
# (Attacker/Defender), and FIRST_TURN_ROLLOFF (after deployment) decides who
# TAKES the first turn. They are independent.
enum Phase { FORMATIONS, DEPLOYMENT, REDEPLOYMENT, ROLL_OFF, SCOUT, SCOUT_MOVES, COMMAND, MOVEMENT, SHOOTING, CHARGE, FIGHT, SCORING, MORALE, FIRST_TURN_ROLLOFF }
enum UnitStatus { UNDEPLOYED, DEPLOYING, DEPLOYED, MOVED, SHOT, CHARGED, FOUGHT, IN_RESERVES }

# 10e Core Rules: "The battle lasts five battle rounds."
const MAX_BATTLE_ROUNDS: int = 5

# The complete game state as a dictionary.
# MUTATION RULE (ISS-001): during a game, `state` must only be modified
# through the action pipeline — phase handlers return diffs and
# PhaseManager.apply_state_changes() applies them — or through GameState's
# own setters. Direct `GameState.state[...] = ...` writes are invisible to
# replay, undo, and multiplayer sync.
# Whitelisted exceptions (pre-game initialization only, before any actions):
#   - ArmyListManager.gd (army load populates units/factions)
#   - MultiplayerLobby.gd / WebLobby.gd (lobby resets meta before game start)
# Enforced by tests/test_iss001_pipeline_mutations.gd (static scan).
var state: Dictionary = {}

func _ready() -> void:
	initialize_default_state()

func initialize_default_state(deployment_type: String = "hammer_anvil") -> void:
	# Get deployment zones from centralized data source
	var deployment_zones = DeploymentZoneData.get_zones(deployment_type)

	# Initialize base state structure
	state = {
		"meta": {
			"game_id": generate_game_id(),
			"turn_number": 1,
			"battle_round": 1,  # Track battle rounds (1-5 in standard 40K)
			"active_player": 1,  # Player 1 should start
			"phase": Phase.FORMATIONS,
			"deployment_type": deployment_type,  # Track which deployment is in use
			"created_at": Time.get_unix_time_from_system(),
			"version": "1.1.0"
		},
		"board": {
			"size": {"width": 44, "height": 60},  # inches
			"deployment_zones": deployment_zones,
			"objectives": [],
			"terrain": [],
			"terrain_features": []  # Added for terrain system
		},
		"units": {},  # Start empty, will be populated by army loading
		"players": {
			"1": {"cp": 0, "vp": 0, "primary_vp": 0, "secondary_vp": 0, "bonus_cp_gained_this_round": 0},
			"2": {"cp": 0, "vp": 0, "primary_vp": 0, "secondary_vp": 0, "bonus_cp_gained_this_round": 0}
		},
		"factions": {},  # New field for faction data
		"unit_visuals": {},  # Maps unit_id -> {"color": "RRGGBB", "label": ""}
		"phase_log": [],
		"history": []
	}
	
	# Load default armies
	_load_default_armies()

	# Initialize terrain features from TerrainManager (autoload, not Engine singleton)
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager and terrain_manager.terrain_features.size() > 0:
		state.board["terrain_features"] = terrain_manager.terrain_features.duplicate(true)

func _load_default_armies() -> void:
	print("GameState: Loading default armies...")

	# Check if ArmyListManager autoload is available (it's a scene tree autoload, not an Engine singleton)
	var army_list_manager = get_node_or_null("/root/ArmyListManager")
	if not army_list_manager:
		print("GameState: ArmyListManager not available, falling back to placeholder armies")
		_initialize_placeholder_armies()
		return

	# Try to load test army for Player 1 (Adeptus Custodes)
	var player1_army = army_list_manager.load_army_list("adeptus_custodes", 1)
	if not player1_army.is_empty():
		print("GameState: Loading Adeptus Custodes army for Player 1")
		army_list_manager.apply_army_to_game_state(player1_army, 1)
	else:
		print("GameState: Failed to load Adeptus Custodes, trying Space Marines for Player 1")
		player1_army = army_list_manager.load_army_list("space_marines", 1)
		if not player1_army.is_empty():
			army_list_manager.apply_army_to_game_state(player1_army, 1)
		else:
			print("GameState: Failed to load Space Marines, using placeholder for Player 1")
			_initialize_placeholder_armies_player(1)

	# Load opponent army (Orks for Player 2)
	var player2_army = army_list_manager.load_army_list("orks", 2)
	if not player2_army.is_empty():
		print("GameState: Loading Orks army for Player 2")
		army_list_manager.apply_army_to_game_state(player2_army, 2)
	else:
		print("GameState: Failed to load Orks, using placeholder for Player 2")
		_initialize_placeholder_armies_player(2)
	
	print("GameState: Army loading complete. Total units: ", state.units.size())

func _initialize_placeholder_armies() -> void:
	print("GameState: Initializing placeholder armies for both players")
	_initialize_placeholder_armies_player(1)
	_initialize_placeholder_armies_player(2)

func _initialize_placeholder_armies_player(player: int) -> void:
	print("GameState: Initializing placeholder army for player ", player)
	
	if player == 1:
		# Space Marines placeholder units
		state.units["U_INTERCESSORS_A"] = {
			"id": "U_INTERCESSORS_A",
			"squad_id": "U_INTERCESSORS_A",
			"owner": 1,
			"status": UnitStatus.UNDEPLOYED,
			"meta": {
				"name": "Intercessor Squad",
				"keywords": ["INFANTRY", "PRIMARIS", "IMPERIUM", "ADEPTUS ASTARTES"],
				"stats": {"move": 6, "toughness": 4, "save": 3}
			},
			"models": [
				{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m3", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m4", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m5", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
			]
		}
		
		state.units["U_TACTICAL_A"] = {
			"id": "U_TACTICAL_A",
			"squad_id": "U_TACTICAL_A",
			"owner": 1,
			"status": UnitStatus.UNDEPLOYED,
			"meta": {
				"name": "Tactical Squad",
				"keywords": ["INFANTRY", "IMPERIUM", "ADEPTUS ASTARTES"],
				"stats": {"move": 6, "toughness": 4, "save": 3}
			},
			"models": [
				{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m3", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m4", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m5", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
			]
		}
		
		state.factions["1"] = {"name": "Space Marines", "points": 0}
		
	else:  # player == 2
		# Ork placeholder units
		state.units["U_BOYZ_A"] = {
			"id": "U_BOYZ_A",
			"squad_id": "U_BOYZ_A",
			"owner": 2,
			"status": UnitStatus.UNDEPLOYED,
			"meta": {
				"name": "Boyz",
				"keywords": ["INFANTRY", "MOB", "ORKS"],
				"stats": {"move": 6, "toughness": 5, "save": 6}
			},
			"models": [
				{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m3", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m4", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m5", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m6", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m7", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m8", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m9", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
				{"id": "m10", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
			]
		}
		
		state.units["U_GRETCHIN_A"] = {
			"id": "U_GRETCHIN_A",
			"squad_id": "U_GRETCHIN_A",
			"owner": 2,
			"status": UnitStatus.UNDEPLOYED,
			"meta": {
				"name": "Gretchin",
				"keywords": ["INFANTRY", "GROTS", "ORKS"],
				"stats": {"move": 5, "toughness": 3, "save": 7}
			},
			"models": [
				{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
				{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
				{"id": "m3", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
				{"id": "m4", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
				{"id": "m5", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []}
			]
		}
		
		state.factions["2"] = {"name": "Orks", "points": 0}

func generate_game_id() -> String:
	var uuid = "%08x-%04x-%04x-%04x-%012x" % [
		randi(),
		randi() & 0xFFFF,
		randi() & 0xFFFF | 0x4000,
		randi() & 0x3FFF | 0x8000,
		randi() << 32 | randi()
	]
	return uuid

func get_deployment_type() -> String:
	return state.get("meta", {}).get("deployment_type", "hammer_anvil")

# State Access Methods
func get_current_phase() -> Phase:
	return state["meta"]["phase"]

func get_active_player() -> int:
	return state["meta"]["active_player"]

func get_faction_name(player: int) -> String:
	if state.has("factions") and state.factions.has(str(player)):
		return state.factions[str(player)].get("name", "Player " + str(player))
	return "Player " + str(player)

func get_turn_number() -> int:
	return state["meta"]["turn_number"]

func is_unit_destroyed(unit_id: String) -> bool:
	"""Check if a unit has been fully destroyed (all models dead)."""
	var unit = state["units"].get(unit_id, {})
	if unit.is_empty():
		return true
	var models = unit.get("models", [])
	if models.is_empty():
		return true
	for model in models:
		if model.get("alive", true):
			return false
	return true

func get_units_for_player(player: int, include_destroyed: bool = false) -> Dictionary:
	var player_units = {}
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player:
			if not include_destroyed and is_unit_destroyed(unit_id):
				continue
			player_units[unit_id] = unit
	return player_units

func get_unit(unit_id: String) -> Dictionary:
	return state["units"].get(unit_id, {})

func get_unit_display_name(unit_id: String) -> String:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return unit_id
	var meta = unit.get("meta", {})
	return meta.get("display_name", meta.get("name", unit_id))

func get_undeployed_units_for_player(player: int) -> Array:
	var undeployed = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player and unit["status"] == UnitStatus.UNDEPLOYED:
			# Skip characters attached to a bodyguard (they deploy with their bodyguard)
			if unit.get("attached_to", null) != null:
				continue
			# Skip units embarked in transports (they deploy with their transport)
			if unit.get("embarked_in", null) != null:
				continue
			undeployed.append(unit_id)
	return undeployed

func has_undeployed_units(player: int) -> bool:
	return get_undeployed_units_for_player(player).size() > 0

func all_units_deployed() -> bool:
	var undeployed_list = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		# Skip units that are embarked (they're deployed when inside a transport)
		if unit.get("embarked_in", null) != null:
			continue
		# Skip units that are attached to a bodyguard (they're deployed with their bodyguard)
		if unit.get("attached_to", null) != null:
			continue
		# Skip units in reserves (they're off-table, handled during reinforcements)
		if unit["status"] == UnitStatus.IN_RESERVES:
			continue
		if unit["status"] == UnitStatus.UNDEPLOYED:
			undeployed_list.append(unit_id + " (player " + str(unit.get("owner", 0)) + ")")

	var all_deployed = undeployed_list.size() == 0
	if not all_deployed:
		print("GameState: ⚠️ all_units_deployed check - Undeployed units: ", undeployed_list)

	return all_deployed

func get_deployment_progress(player: int) -> Dictionary:
	var deployed = 0
	var in_reserves = 0
	var total = 0
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] != player:
			continue
		# Skip units that are embarked or attached (they deploy with their transport/bodyguard)
		if unit.get("embarked_in", null) != null:
			continue
		if unit.get("attached_to", null) != null:
			continue
		total += 1
		if unit["status"] == UnitStatus.IN_RESERVES:
			in_reserves += 1
			deployed += 1  # Reserves count as "handled" for deployment completion
		elif unit["status"] != UnitStatus.UNDEPLOYED:
			deployed += 1
	return {"deployed": deployed, "total": total, "in_reserves": in_reserves}

func get_deployment_zone_for_player(player: int) -> Dictionary:
	for zone in state["board"]["deployment_zones"]:
		if zone["player"] == player:
			return zone
	return {}

# Pre-Battle Formations Helpers
func get_characters_for_player(player: int) -> Array:
	"""Get all CHARACTER units with Leader ability for a player."""
	var characters = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] != player:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		if "CHARACTER" not in keywords:
			continue
		var leader_data = unit.get("meta", {}).get("leader_data", {})
		var can_lead = leader_data.get("can_lead", [])
		if can_lead.is_empty():
			continue
		characters.append(unit_id)
	return characters

func get_transports_for_player(player: int) -> Array:
	"""Get all transport units for a player."""
	var transports = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] != player:
			continue
		if unit.has("transport_data"):
			transports.append(unit_id)
	return transports

func get_eligible_bodyguards_for_character(character_id: String) -> Array:
	"""Get all units a CHARACTER can lead based on keyword matching."""
	var character = get_unit(character_id)
	if character.is_empty():
		return []
	var leader_data = character.get("meta", {}).get("leader_data", {})
	var can_lead = leader_data.get("can_lead", [])
	if can_lead.is_empty():
		return []
	var char_owner = character.get("owner", 0)
	var eligible = []
	for unit_id in state["units"]:
		if unit_id == character_id:
			continue
		var unit = state["units"][unit_id]
		if unit.get("owner", 0) != char_owner:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		# Bodyguard must not be a CHARACTER
		if "CHARACTER" in keywords:
			continue
		# Must have a matching keyword (case-insensitive to handle inconsistent casing
		# between can_lead values and unit keywords across army list files)
		var has_match = false
		var upper_keywords = []
		for kw in keywords:
			upper_keywords.append(str(kw).to_upper())
		for lead_kw in can_lead:
			if str(lead_kw).to_upper() in upper_keywords:
				has_match = true
				break
		if has_match:
			eligible.append(unit_id)
	return eligible

func formations_declared() -> bool:
	"""Check if formations have been declared (pre-battle step completed)."""
	return state.get("meta", {}).get("formations_declared", false)

func get_leader_attachments_for_player(player: int) -> Dictionary:
	"""Get leader attachment declarations for a player from formations data."""
	var formations = state.get("meta", {}).get("formations", {})
	var player_data = formations.get(str(player), {})
	return player_data.get("leader_attachments", {})

func get_reserves_declarations_for_player(player: int) -> Array:
	"""Get reserves declarations for a player from formations data."""
	var formations = state.get("meta", {}).get("formations", {})
	var player_data = formations.get(str(player), {})
	return player_data.get("reserves", [])

func is_unit_pre_declared_attached(unit_id: String) -> bool:
	"""Check if a unit was declared as attached during formations phase."""
	var formations = state.get("meta", {}).get("formations", {})
	for player_key in formations:
		var player_data = formations[player_key]
		if player_data.get("leader_attachments", {}).has(unit_id):
			return true
	return false

func is_unit_pre_declared_in_reserves(unit_id: String) -> bool:
	"""Check if a unit was declared as in reserves during formations phase."""
	var formations = state.get("meta", {}).get("formations", {})
	for player_key in formations:
		var player_data = formations[player_key]
		for entry in player_data.get("reserves", []):
			if entry.get("unit_id", "") == unit_id:
				return true
	return false

# Character Attachment Helpers
func is_character(unit_id: String) -> bool:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	var keywords = unit.get("meta", {}).get("keywords", [])
	return "CHARACTER" in keywords

func get_attached_characters(unit_id: String) -> Array:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []
	return unit.get("attachment_data", {}).get("attached_characters", [])

func is_attached(unit_id: String) -> bool:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	return unit.get("attached_to", null) != null

# Strategic Reserves / Deep Strike Helpers
func get_reserves_for_player(player: int) -> Array:
	var reserves = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player and unit["status"] == UnitStatus.IN_RESERVES:
			reserves.append(unit_id)
	return reserves

func has_reserves(player: int) -> bool:
	return get_reserves_for_player(player).size() > 0

func unit_has_ability(unit_id: String, ability_name: String) -> bool:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") == ability_name:
			return true
	return false

func unit_has_deep_strike(unit_id: String) -> bool:
	return unit_has_ability(unit_id, "Deep Strike")

func unit_has_infiltrators(unit_id: String) -> bool:
	return unit_has_ability(unit_id, "Infiltrators")

func unit_is_fortification(unit_id: String) -> bool:
	"""Check if a unit has the FORTIFICATION keyword. Fortifications cannot be placed in reserves."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	var keywords = unit.get("meta", {}).get("keywords", [])
	for kw in keywords:
		if kw.to_upper() == "FORTIFICATION":
			return true
	return false

func _unit_has_scout_own(unit_id: String) -> bool:
	"""Check if a unit itself (not inherited) has the Scout ability.
	Issue #389: also check description for the Scouts text — defends against
	mis-tagged ability entries where name is "Core" or similar instead of
	"Scouts". Current Custodes roster JSONs already have name:"Scouts" so
	the primary check works; this is defense-in-depth."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var name = ""
		var description = ""
		if ability is String:
			name = ability
		elif ability is Dictionary:
			name = ability.get("name", "")
			description = ability.get("description", "")
		if name.to_lower().begins_with("scout"):
			return true
		# Issue #389 fallback: detect "Scouts X\"" in the description text
		# even when the name field is mis-tagged.
		if "scouts " in description.to_lower() and "scouts x" in description.to_lower():
			return true
	return false

func _get_scout_distance_from_abilities(abilities: Array) -> float:
	"""Extract Scout distance from an abilities array. Returns 0.0 if no Scout ability found."""
	for ability in abilities:
		var name = ""
		var value = 0
		if ability is String:
			name = ability
		elif ability is Dictionary:
			name = ability.get("name", "")
			value = ability.get("value", 0)
		if name.to_lower().begins_with("scout"):
			# If value is explicitly set, use it
			if value > 0:
				return float(value)
			# Try to parse distance from name, e.g. "Scout 6\"" or "Scout 6"
			var regex = RegEx.new()
			regex.compile("(?i)scout\\s+(\\d+)")
			var result = regex.search(name)
			if result:
				return float(result.get_string(1))
			# Default Scout distance is 6"
			return 6.0
	return 0.0

func unit_has_scout(unit_id: String) -> bool:
	"""Check if a unit has the Scout ability (any variant like 'Scout 6\"').
	Per Balance Dataslate: Dedicated Transports can inherit Scout from embarked units
	if all embarked models have the Scout ability. Scout distance can exceed Move characteristic
	as long as it does not exceed X\"."""
	# Check the unit's own abilities first
	if _unit_has_scout_own(unit_id):
		return true
	# Check if this is a Dedicated Transport that inherits Scout from embarked units
	return _transport_inherits_scout(unit_id)

func _transport_inherits_scout(unit_id: String) -> bool:
	"""Check if a transport inherits Scout from its embarked units.
	Per Balance Dataslate: DEDICATED TRANSPORT models can make use of a Scouts X\" ability
	that a unit starting the battle embarked within that transport has, provided only models
	with this ability are embarked within that Dedicated Transport."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	# Must be a transport with embarked units
	if not unit.has("transport_data"):
		return false
	var embarked_ids = unit.get("transport_data", {}).get("embarked_units", [])
	if embarked_ids.is_empty():
		return false
	# All embarked units must have Scout ability
	for embarked_id in embarked_ids:
		if not _unit_has_scout_own(embarked_id):
			print("ScoutInheritance: Transport %s - embarked unit %s does NOT have Scout, inheritance blocked" % [unit_id, embarked_id])
			return false
	print("ScoutInheritance: Transport %s inherits Scout from %d embarked unit(s)" % [unit_id, embarked_ids.size()])
	return true

func get_scout_distance(unit_id: String) -> float:
	"""Get the Scout move distance in inches for a unit. Returns 0.0 if unit has no Scout ability.
	For transports inheriting Scout, uses the smallest Scout distance among embarked units."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return 0.0
	# Check own abilities first
	var own_abilities = unit.get("meta", {}).get("abilities", [])
	var own_distance = _get_scout_distance_from_abilities(own_abilities)
	if own_distance > 0.0:
		return own_distance
	# Check inherited from embarked units (use smallest distance)
	if unit.has("transport_data"):
		var embarked_ids = unit.get("transport_data", {}).get("embarked_units", [])
		if not embarked_ids.is_empty():
			var min_distance = INF
			var all_have_scout = true
			for embarked_id in embarked_ids:
				var embarked_unit = get_unit(embarked_id)
				if embarked_unit.is_empty():
					all_have_scout = false
					break
				var embarked_abilities = embarked_unit.get("meta", {}).get("abilities", [])
				var dist = _get_scout_distance_from_abilities(embarked_abilities)
				if dist <= 0.0:
					all_have_scout = false
					break
				min_distance = min(min_distance, dist)
			if all_have_scout and min_distance < INF:
				return min_distance
	return 0.0

func get_scout_range(unit_id: String) -> float:
	"""Alias for get_scout_distance() for compatibility."""
	return get_scout_distance(unit_id)

func get_scout_units_for_player(player: int) -> Array:
	"""Get all deployed units with the Scout ability for a given player.
	Per Balance Dataslate: Dedicated Transports can inherit Scout from embarked units."""
	var scout_units = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] != player:
			continue
		# Only deployed units can make Scout moves (not reserves, not embarked)
		if unit.get("status", 0) != UnitStatus.DEPLOYED:
			continue
		if unit.get("embarked_in", null) != null:
			continue
		if unit.get("attached_to", null) != null:
			continue
		if unit_has_scout(unit_id):
			scout_units.append(unit_id)
	return scout_units

func unit_has_redeploy(unit_id: String) -> bool:
	"""Check if a unit has a redeployment ability (e.g. from datasheet or detachment rules).
	Per Core Rules Updates, redeployment abilities are resolved after Deploy Armies,
	before Determine First Turn. Players alternate resolving them, starting with the Attacker."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var name = ""
		if ability is String:
			name = ability
		elif ability is Dictionary:
			name = ability.get("name", "")
		# Match known redeployment ability names
		if name.to_lower().contains("redeploy") or name == "Phantasm" or name == "Red Corsairs":
			return true
	return false

func get_redeploy_units_for_player(player: int) -> Array:
	"""Get all deployed units with a redeployment ability for a given player.
	Per Core Rules Updates, redeployment occurs after Deploy Armies, before Determine First Turn.
	Also includes units eligible via Razgit's Magik Map enhancement (OA-2)."""
	var redeploy_units = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] != player:
			continue
		# Only deployed units can redeploy (not reserves, not embarked)
		if unit.get("status", 0) != UnitStatus.DEPLOYED:
			continue
		if unit.get("embarked_in", null) != null:
			continue
		if unit_has_redeploy(unit_id):
			redeploy_units.append(unit_id)

	# OA-2: Add units eligible via Razgit's Magik Map enhancement
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_mgr and faction_mgr.has_razgit_magik_map(player):
		var razgit_units = faction_mgr.get_razgit_eligible_units(player)
		for ru in razgit_units:
			var uid = ru.get("unit_id", "")
			if uid != "" and uid not in redeploy_units:
				redeploy_units.append(uid)
				print("GameState: Razgit's Magik Map — %s eligible for redeployment" % ru.get("unit_name", uid))

	return redeploy_units

func get_enemy_deployment_zone(player: int) -> Dictionary:
	"""Get the enemy's deployment zone for a given player (for Infiltrators >9 inch check)"""
	var enemy_player = 3 - player
	return get_deployment_zone_for_player(enemy_player)

func get_total_army_points(player: int) -> int:
	var total = 0
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player:
			total += unit.get("meta", {}).get("points", 0)
	return total

func get_reserves_points(player: int) -> int:
	var total = 0
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player and unit["status"] == UnitStatus.IN_RESERVES:
			total += unit.get("meta", {}).get("points", 0)
	return total

func get_total_unit_count(player: int) -> int:
	var count = 0
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player:
			count += 1
	return count

func get_reserves_unit_count(player: int) -> int:
	var count = 0
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player and unit["status"] == UnitStatus.IN_RESERVES:
			count += 1
	return count

func get_enemy_model_positions(player: int) -> Array:
	"""Get all enemy model positions (for >9 inch distance checks)"""
	var positions = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player:
			continue
		if unit["status"] != UnitStatus.DEPLOYED and unit["status"] != UnitStatus.MOVED:
			continue
		for model in unit.get("models", []):
			var pos = model.get("position", null)
			if pos != null and model.get("alive", true):
				positions.append({"x": pos.get("x", pos.x if pos is Vector2 else 0), "y": pos.get("y", pos.y if pos is Vector2 else 0), "base_mm": model.get("base_mm", 32)})
	return positions

func get_omni_scrambler_positions(deploying_player: int) -> Array:
	"""Get all model positions of enemy units with Omni-scramblers ability (for 12\" deep strike denial).
	Returns array of { x, y, base_mm, unit_name } for units belonging to the opponent of deploying_player."""
	var positions = []
	for uid in state["units"]:
		var unit = state["units"][uid]
		# Omni-scramblers are on the opponent's units — they block the deploying player
		if unit["owner"] == deploying_player:
			continue
		if unit["status"] != UnitStatus.DEPLOYED and unit["status"] != UnitStatus.MOVED:
			continue
		# Check if unit has Omni-scramblers ability
		var has_omni = false
		var abilities = unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			var name = ""
			if ability is String:
				name = ability
			elif ability is Dictionary:
				name = ability.get("name", "")
			if name == "Omni-scramblers":
				has_omni = true
				break
		if not has_omni:
			continue
		var unit_name = unit.get("meta", {}).get("name", uid)
		for model in unit.get("models", []):
			var pos = model.get("position", null)
			if pos != null and model.get("alive", true):
				positions.append({
					"x": pos.get("x", pos.x if pos is Vector2 else 0),
					"y": pos.get("y", pos.y if pos is Vector2 else 0),
					"base_mm": model.get("base_mm", 32),
					"unit_name": unit_name
				})
	if positions.size() > 0:
		print("GameState: Found %d Omni-scrambler model positions blocking player %d deep strike" % [positions.size(), deploying_player])
	return positions

# T-026: Combat Squads / Patrol Squad — split a 10-model unit into two
# 5-model halves at deployment. Returns the new sibling unit's id, or "" on
# failure. Does NOT itself drive the UI prompt — DeploymentController must
# offer the choice and call this helper when accepted.
#
# Constraints:
#  - Only callable when source unit has exactly 10 alive models in UNDEPLOYED state.
#  - Only callable when source unit's meta.abilities contains "Combat Squads"
#    or "Patrol Squad".
#  - Source unit retains models 0..4; new sibling unit inherits models 5..9
#    (renamed m1..m5 to keep ids unique within each unit).
#  - Both halves keep the source unit's meta verbatim (same datasheet, weapons,
#    keywords, abilities). Faction and owner copied. Status remains UNDEPLOYED
#    so deployment alternation includes both halves.
#  - Returns the new sibling unit_id on success.
func split_unit_at_deployment(source_unit_id: String) -> String:
	var source = get_unit(source_unit_id)
	if source.is_empty():
		push_error("split_unit_at_deployment: unit %s not found" % source_unit_id)
		return ""
	# Eligibility: must have one of the splitting abilities.
	var abilities = source.get("meta", {}).get("abilities", [])
	var has_split = false
	for ab in abilities:
		var ab_name = ""
		if ab is String:
			ab_name = ab
		elif ab is Dictionary:
			ab_name = ab.get("name", "")
		if ab_name in ["Combat Squads", "Patrol Squad"]:
			has_split = true
			break
	if not has_split:
		push_error("split_unit_at_deployment: %s lacks Combat Squads / Patrol Squad ability" % source_unit_id)
		return ""
	# Status must be UNDEPLOYED.
	if int(source.get("status", 0)) != UnitStatus.UNDEPLOYED:
		push_error("split_unit_at_deployment: %s status is not UNDEPLOYED (got %s)" % [source_unit_id, str(source.get("status"))])
		return ""
	# Must have exactly 10 alive models.
	var models = source.get("models", [])
	var alive_count = 0
	for m in models:
		if m.get("alive", true):
			alive_count += 1
	if alive_count != 10:
		push_error("split_unit_at_deployment: %s has %d alive models, must be exactly 10" % [source_unit_id, alive_count])
		return ""
	# Build the sibling unit. Deep-copy the meta so subsequent mutation of the
	# source's model list doesn't bleed across.
	var sibling_id = "%s_SPLIT" % source_unit_id
	var idx_suffix = 1
	while state["units"].has(sibling_id):
		sibling_id = "%s_SPLIT%d" % [source_unit_id, idx_suffix]
		idx_suffix += 1
	var sibling = _deep_copy_dict(source)
	sibling["id"] = sibling_id
	sibling["squad_id"] = sibling_id
	# Sibling takes models 5..9 of the source, re-numbered.
	var sibling_models = []
	var i = 0
	for m in models.slice(5, 10):
		i += 1
		var new_model = _deep_copy_dict(m) if m is Dictionary else m
		new_model["id"] = "m%d" % i
		sibling_models.append(new_model)
	sibling["models"] = sibling_models
	# Source unit keeps models 0..4 with their existing ids.
	source["models"] = models.slice(0, 5)
	# Mark the split on both halves so downstream code can inspect.
	source["split_from_combat_squads"] = true
	sibling["split_from_combat_squads"] = true
	sibling["split_sibling_of"] = source_unit_id
	source["split_sibling_id"] = sibling_id
	# Update the meta name for clarity in unit lists.
	var base_name = source.get("meta", {}).get("name", source_unit_id)
	source["meta"]["display_name"] = "%s (Combat Squad A)" % base_name
	sibling["meta"]["display_name"] = "%s (Combat Squad B)" % base_name
	# Attach to GameState.
	state["units"][sibling_id] = sibling
	print("GameState: T-026 split %s into %s + %s (5+5 models)" % [source_unit_id, source_unit_id, sibling_id])
	return sibling_id

func get_combined_models(unit_id: String) -> Array:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []
	var models = unit.get("models", []).duplicate()
	var attached_chars = get_attached_characters(unit_id)
	for char_id in attached_chars:
		var char_unit = get_unit(char_id)
		if not char_unit.is_empty():
			for model in char_unit.get("models", []):
				var combined_model = model.duplicate()
				combined_model["source_unit_id"] = char_id
				combined_model["is_character"] = true
				models.append(combined_model)
	return models

# State Modification Methods
func set_phase(new_phase: Phase) -> void:
	state["meta"]["phase"] = new_phase

func set_active_player(player: int) -> void:
	state["meta"]["active_player"] = player

func advance_turn() -> void:
	state["meta"]["turn_number"] += 1

# Battle Round Management Methods
func get_battle_round() -> int:
	return state["meta"].get("battle_round", 1)

func advance_battle_round() -> void:
	state["meta"]["battle_round"] = get_battle_round() + 1
	print("GameState: Advanced to battle round ", get_battle_round())

func is_game_complete() -> bool:
	if state.get("meta", {}).get("game_ended", false):
		return true
	return get_battle_round() > MAX_BATTLE_ROUNDS

# CP Cap — Per core rules FAQ:
# "Outside of the 1CP players gain at the start of the Command phase,
#  each player can only gain a total of 1CP per battle round, regardless of the source."
const BONUS_CP_CAP_PER_ROUND: int = 1

func get_bonus_cp_gained_this_round(player: int) -> int:
	"""How many non-automatic CP has this player gained in the current battle round."""
	return state.get("players", {}).get(str(player), {}).get("bonus_cp_gained_this_round", 0)

func can_gain_bonus_cp(player: int) -> bool:
	"""Check if a player can still gain non-automatic CP this battle round."""
	return get_bonus_cp_gained_this_round(player) < BONUS_CP_CAP_PER_ROUND

func record_bonus_cp_gained(player: int, amount: int = 1) -> void:
	"""Record that a player gained non-automatic CP. Call AFTER applying the CP change."""
	var current = get_bonus_cp_gained_this_round(player)
	state["players"][str(player)]["bonus_cp_gained_this_round"] = current + amount
	print("GameState: Player %d bonus CP gained this round: %d -> %d (cap: %d)" % [
		player, current, current + amount, BONUS_CP_CAP_PER_ROUND])

func reset_bonus_cp_tracking() -> void:
	"""Reset bonus CP tracking for both players at the start of a new battle round."""
	for p in ["1", "2"]:
		if state.get("players", {}).has(p):
			state["players"][p]["bonus_cp_gained_this_round"] = 0
	print("GameState: Reset bonus CP gained tracking for new battle round")

# Battle-shock: Below Half-Strength Check
# Per 10th edition rules:
# - Multi-model unit: fewer than half its starting models alive
# - Single-model unit: fewer than half its starting wounds remaining
# - Attached units: combine bodyguard + attached character models for starting strength
func is_below_half_strength(unit: Dictionary) -> bool:
	var models = unit.get("models", [])
	if models.size() == 0:
		return false

	var total_models = models.size()
	var alive_models = 0
	for model in models:
		if model.get("alive", true):
			alive_models += 1

	# If all models are dead, the unit is destroyed (not below half strength - it's gone)
	if alive_models == 0:
		return false

	if total_models == 1:
		# Single-model unit: check wounds
		var model = models[0]
		var max_wounds = model.get("wounds", 1)
		var current_wounds = model.get("current_wounds", max_wounds)
		# Below half: current_wounds * 2 < max_wounds
		return current_wounds * 2 < max_wounds
	else:
		# Multi-model unit: check alive count
		# Below half: alive_models * 2 < total_models
		return alive_models * 2 < total_models

# Battle-shock: Below Half-Strength Check for attached units (by unit_id)
# Per 10th edition rules, when a character is attached to a bodyguard unit,
# the combined unit's starting strength is the sum of all models.
# E.g., a Warboss (1 model) attached to 10 Boyz = starting strength 11.
func is_below_half_strength_combined(unit_id: String) -> bool:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false

	var attached_chars = get_attached_characters(unit_id)
	if attached_chars.size() == 0:
		# No attached characters — use standard check
		return is_below_half_strength(unit)

	# Combined unit: count all models (bodyguard + attached characters)
	var total_models = unit.get("models", []).size()
	var alive_models = 0
	for model in unit.get("models", []):
		if model.get("alive", true):
			alive_models += 1

	for char_id in attached_chars:
		var char_unit = get_unit(char_id)
		if char_unit.is_empty():
			continue
		for model in char_unit.get("models", []):
			total_models += 1
			if model.get("alive", true):
				alive_models += 1

	# If all models are dead, the unit is destroyed
	if alive_models == 0:
		return false

	# Combined units are always multi-model (bodyguard + character >= 2)
	# Below half: alive_models * 2 < total_models
	print("GameState: is_below_half_strength_combined(%s): %d alive / %d total (attached chars: %s)" % [unit_id, alive_models, total_models, str(attached_chars)])
	return alive_models * 2 < total_models

func add_action_to_phase_log(action: Dictionary) -> void:
	state["phase_log"].append(action)

func commit_phase_log_to_history() -> void:
	if state["phase_log"].size() > 0:
		var phase_entry = {
			"turn": state["meta"].get("battle_round", 1),
			"phase": state["meta"]["phase"],
			"actions": state["phase_log"].duplicate()
		}
		state["history"].append(phase_entry)
		state["phase_log"].clear()

# Create a deep copy of the current state
func create_snapshot() -> Dictionary:
	# Create base snapshot
	var snapshot = _deep_copy_dict(state)
	
	# Add terrain features and layout name from TerrainManager (autoload, not Engine singleton)
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager:
		if terrain_manager.current_layout != "":
			snapshot.board["terrain_layout"] = terrain_manager.current_layout
		if terrain_manager.terrain_features.size() > 0:
			snapshot.board["terrain_features"] = terrain_manager.terrain_features.duplicate(true)

	# Add secondary mission state from SecondaryMissionManager (autoload)
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if secondary_mgr:
		var secondary_data = secondary_mgr.get_save_data()
		if not secondary_data.is_empty():
			snapshot["secondary_missions"] = secondary_data
			print("[GameState] Adding secondary mission state to snapshot")

	# Issue #338: Add FactionAbilityManager state (once-per-battle locks,
	# doctrines, masteries, enhancements, banner). Without this, save/load
	# drops these and lets save-scumming defeat usage restrictions.
	var faction_ability_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_ability_mgr:
		snapshot["faction_ability_manager"] = faction_ability_mgr.get_state_for_save()
		print("[GameState] Adding FactionAbilityManager state to snapshot")

	# Issue #338: Add StratagemManager usage history and active effects.
	# Without this, once-per-battle/turn/phase stratagem locks reset on load.
	var stratagem_mgr = get_node_or_null("/root/StratagemManager")
	if stratagem_mgr and stratagem_mgr.has_method("get_state_for_save"):
		snapshot["stratagem_manager"] = stratagem_mgr.get_state_for_save()
		print("[GameState] Adding StratagemManager state to snapshot")

	# Issue #379: Add MissionManager state (sticky objectives, kill counters,
	# burn/ritual/terraform tracking, supply-drop, VP timeline). Without this,
	# mid-game save/load drops mission-bearing state.
	var mission_mgr = get_node_or_null("/root/MissionManager")
	if mission_mgr and mission_mgr.has_method("get_state_for_save"):
		snapshot["mission_manager"] = mission_mgr.get_state_for_save()
		print("[GameState] Adding MissionManager state to snapshot")

	# Issue #380: Add UnitAbilityManager state (once-per-battle locks etc.).
	# The methods existed but were never wired through GameState's snapshot.
	var unit_ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if unit_ability_mgr and unit_ability_mgr.has_method("get_state_for_save"):
		snapshot["unit_ability_manager"] = unit_ability_mgr.get_state_for_save()
		print("[GameState] Adding UnitAbilityManager state to snapshot")

	# SAVE-7: Add AI turn history to snapshot
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.enabled:
		var turn_history = ai_player.get_turn_history()
		if not turn_history.is_empty():
			snapshot["ai_turn_history"] = turn_history
			print("[GameState] SAVE-7 Adding %d AI turn history entries to snapshot" % turn_history.size())

	# Add measuring tape data if persistence is enabled (autoload, not Engine singleton)
	var measuring_tape_manager = get_node_or_null("/root/MeasuringTapeManager")
	if measuring_tape_manager:
		if measuring_tape_manager.save_measurements:
			var tape_data = measuring_tape_manager.get_save_data()
			if not tape_data.is_empty():
				snapshot["measuring_tape"] = tape_data
				print("[GameState] Adding %d measurements to snapshot" % tape_data.size())
			else:
				print("[GameState] No measurements to save (empty data)")
		else:
			print("[GameState] Measuring tape persistence disabled")
	else:
		print("[GameState] MeasuringTapeManager not available")
	
	return snapshot

func _deep_copy_dict(dict: Dictionary) -> Dictionary:
	var copy = {}
	for key in dict:
		var value = dict[key]
		if value is Dictionary:
			copy[key] = _deep_copy_dict(value)
		elif value is Array:
			copy[key] = _deep_copy_array(value)
		else:
			copy[key] = value
	return copy

func _deep_copy_array(array: Array) -> Array:
	var copy = []
	for item in array:
		if item is Dictionary:
			copy.append(_deep_copy_dict(item))
		elif item is Array:
			copy.append(_deep_copy_array(item))
		else:
			copy.append(item)
	return copy

func _restore_terrain_types(terrain_features: Array) -> Array:
	"""Restore Godot types (Vector2, PackedVector2Array) from dict format
	that may have been serialized over network JSON."""
	var restored = []
	for feature in terrain_features:
		var f = feature.duplicate(true) if feature is Dictionary else feature
		if not f is Dictionary:
			restored.append(f)
			continue

		# Restore polygon: array of {"x":..,"y":..} -> PackedVector2Array
		var polygon_data = f.get("polygon", null)
		if polygon_data is Array and polygon_data.size() > 0:
			if polygon_data[0] is Dictionary and polygon_data[0].has("x"):
				var packed = PackedVector2Array()
				for pt in polygon_data:
					packed.append(Vector2(pt.get("x", 0), pt.get("y", 0)))
				f["polygon"] = packed

		# Restore position: {"x":..,"y":..} -> Vector2
		var pos = f.get("position", null)
		if pos is Dictionary and pos.has("x"):
			f["position"] = Vector2(pos.get("x", 0), pos.get("y", 0))

		# Restore size: {"x":..,"y":..} -> Vector2
		var sz = f.get("size", null)
		if sz is Dictionary and sz.has("x"):
			f["size"] = Vector2(sz.get("x", 0), sz.get("y", 0))

		# Restore wall start/end: {"x":..,"y":..} -> Vector2
		var walls = f.get("walls", [])
		for i in range(walls.size()):
			var wall = walls[i]
			if wall is Dictionary:
				var ws = wall.get("start", null)
				if ws is Dictionary and ws.has("x"):
					wall["start"] = Vector2(ws.get("x", 0), ws.get("y", 0))
				var we = wall.get("end", null)
				if we is Dictionary and we.has("x"):
					wall["end"] = Vector2(we.get("x", 0), we.get("y", 0))

		restored.append(f)
	return restored

# Load state from a snapshot
func load_from_snapshot(snapshot: Dictionary) -> void:
	state = _deep_copy_dict(snapshot)

	# SAVE/LOAD FIX: Ensure formation metadata exists for backwards compatibility with old saves.
	# If the saved phase is past FORMATIONS and formation flags are missing, infer they were completed.
	if state.has("meta"):
		var meta = state["meta"]
		var saved_phase = meta.get("phase", Phase.FORMATIONS)
		if saved_phase > Phase.FORMATIONS:
			if not meta.has("formations_declared"):
				print("[GameState] Old save missing formations_declared — inferring true (phase is past FORMATIONS)")
				meta["formations_declared"] = true
			if not meta.has("formations_p1_confirmed"):
				print("[GameState] Old save missing formations_p1_confirmed — inferring true")
				meta["formations_p1_confirmed"] = true
			if not meta.has("formations_p2_confirmed"):
				print("[GameState] Old save missing formations_p2_confirmed — inferring true")
				meta["formations_p2_confirmed"] = true
			if not meta.has("formations"):
				print("[GameState] Old save missing formations data — setting empty defaults")
				meta["formations"] = {
					"1": {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []},
					"2": {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []}
				}

	# Load terrain features if present (autoload, not Engine singleton)
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if state.has("board") and terrain_manager:
		var terrain_layout = state.board.get("terrain_layout", "")
		var terrain_features = state.board.get("terrain_features", [])

		if terrain_layout != "":
			# Preferred path: reload terrain from JSON layout file
			# This avoids issues with PackedVector2Array/Vector2 serialization over network
			print("[GameState] Reloading terrain from layout: ", terrain_layout)
			terrain_manager.load_terrain_layout(terrain_layout)
		elif terrain_features.size() > 0:
			# Fallback: restore terrain features from snapshot data
			# Convert any dict-format Vector2/polygon data back to Godot types
			var restored_features = _restore_terrain_types(terrain_features)
			terrain_manager.terrain_features = restored_features
			terrain_manager.emit_signal("terrain_loaded", terrain_manager.terrain_features)

	# Load secondary mission state if present (autoload)
	var secondary_mgr = get_node_or_null("/root/SecondaryMissionManager")
	if state.has("secondary_missions") and secondary_mgr:
		print("[GameState] Found secondary mission data in save, restoring")
		secondary_mgr.load_save_data(state["secondary_missions"])
	else:
		if state.has("secondary_missions"):
			print("[GameState] Has secondary_missions but SecondaryMissionManager not available")

	# Issue #338: Restore FactionAbilityManager state if present.
	# Guarded by has() so old save files (without this key) still load with defaults.
	var faction_ability_mgr = get_node_or_null("/root/FactionAbilityManager")
	if state.has("faction_ability_manager") and faction_ability_mgr:
		print("[GameState] Found FactionAbilityManager data in save, restoring")
		faction_ability_mgr.load_state(state["faction_ability_manager"])
	elif state.has("faction_ability_manager"):
		print("[GameState] Has faction_ability_manager but FactionAbilityManager not available")

	# Issue #338: Restore StratagemManager state if present.
	var stratagem_mgr = get_node_or_null("/root/StratagemManager")
	if state.has("stratagem_manager") and stratagem_mgr and stratagem_mgr.has_method("load_state"):
		print("[GameState] Found StratagemManager data in save, restoring")
		stratagem_mgr.load_state(state["stratagem_manager"])
	elif state.has("stratagem_manager"):
		print("[GameState] Has stratagem_manager but StratagemManager not available")

	# Issue #379: Restore MissionManager state if present.
	var mission_mgr = get_node_or_null("/root/MissionManager")
	if state.has("mission_manager") and mission_mgr and mission_mgr.has_method("load_state"):
		print("[GameState] Found MissionManager data in save, restoring")
		mission_mgr.load_state(state["mission_manager"])
	elif state.has("mission_manager"):
		print("[GameState] Has mission_manager but MissionManager not available")

	# Issue #380: Restore UnitAbilityManager state if present.
	var unit_ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if state.has("unit_ability_manager") and unit_ability_mgr and unit_ability_mgr.has_method("load_state"):
		print("[GameState] Found UnitAbilityManager data in save, restoring")
		unit_ability_mgr.load_state(state["unit_ability_manager"])
	elif state.has("unit_ability_manager"):
		print("[GameState] Has unit_ability_manager but UnitAbilityManager not available")

	# SAVE-7: Restore AI turn history if present
	var ai_player = get_node_or_null("/root/AIPlayer")
	if state.has("ai_turn_history") and ai_player:
		print("[GameState] SAVE-7 Found %d AI turn history entries in save, will restore after AI reconfigure" % state["ai_turn_history"].size())
		# Defer restoration — reconfigure_ai_after_load() clears _turn_history,
		# so we store it in state for Main._reinitialize_ai_after_load() to pick up.
		# The data stays in state["ai_turn_history"] for the post-load flow to use.
	elif state.has("ai_turn_history"):
		print("[GameState] Has ai_turn_history but AIPlayer not available")

	# Load measuring tape data if present (autoload, not Engine singleton)
	var measuring_tape_manager = get_node_or_null("/root/MeasuringTapeManager")
	if state.has("measuring_tape") and measuring_tape_manager:
		print("[GameState] Found measuring tape data in save, loading %d measurements" % state["measuring_tape"].size())
		measuring_tape_manager.load_save_data(state["measuring_tape"])
	else:
		if state.has("measuring_tape"):
			print("[GameState] Has measuring_tape but MeasuringTapeManager not available")
		else:
			print("[GameState] No measuring_tape data in save")

# Validation
func validate_state() -> Dictionary:
	var errors = []
	
	# Check required keys
	var required_keys = ["meta", "board", "units", "players", "phase_log", "history"]
	for key in required_keys:
		if not state.has(key):
			errors.append("Missing required key: " + key)
	
	# Check meta structure
	if state.has("meta"):
		var meta_keys = ["game_id", "turn_number", "active_player", "phase"]
		for key in meta_keys:
			if not state["meta"].has(key):
				errors.append("Missing meta key: " + key)
	
	var is_valid = errors.size() == 0
	return {
		"valid": is_valid,
		"errors": errors
	}

# --- Unit Visuals (letter-mode color/label storage) ---

func _ensure_unit_visuals() -> void:
	if not state.has("unit_visuals"):
		state["unit_visuals"] = {}

func set_unit_color(unit_id: String, color: Color) -> void:
	_ensure_unit_visuals()
	if not state["unit_visuals"].has(unit_id):
		state["unit_visuals"][unit_id] = {"color": "", "label": ""}
	state["unit_visuals"][unit_id]["color"] = color.to_html(false)
	print("[GameState] Set unit %s color to %s" % [unit_id, color.to_html(false)])

func get_unit_color(unit_id: String) -> Color:
	_ensure_unit_visuals()
	var visuals = state["unit_visuals"].get(unit_id, {})
	var hex = visuals.get("color", "")
	if hex != "" and hex is String:
		return Color.from_string(hex, Color.TRANSPARENT)
	return Color.TRANSPARENT

func set_unit_label(unit_id: String, label: String) -> void:
	_ensure_unit_visuals()
	if not state["unit_visuals"].has(unit_id):
		state["unit_visuals"][unit_id] = {"color": "", "label": ""}
	state["unit_visuals"][unit_id]["label"] = label
	print("[GameState] Set unit %s label to '%s'" % [unit_id, label])

func get_unit_label(unit_id: String) -> String:
	_ensure_unit_visuals()
	var visuals = state["unit_visuals"].get(unit_id, {})
	return visuals.get("label", "")

func get_used_colors_for_player(player: int) -> Array:
	_ensure_unit_visuals()
	var colors: Array = []
	for uid in state["unit_visuals"]:
		var unit = get_unit(uid)
		if unit.get("owner", 0) == player:
			var hex = state["unit_visuals"][uid].get("color", "")
			if hex != "":
				colors.append(Color.from_string(hex, Color.TRANSPARENT))
	return colors

func auto_assign_unit_color(unit_id: String) -> Color:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return Color(0.4, 0.4, 0.4)
	var player = unit.get("owner", 1)
	var faction_name = state.get("factions", {}).get(str(player), {}).get("name", "")
	var used = get_used_colors_for_player(player)
	var color = FactionPalettes.get_auto_color(faction_name, used)
	set_unit_color(unit_id, color)
	return color

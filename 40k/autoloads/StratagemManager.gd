extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# StratagemManager - Central authority for stratagem validation, tracking, and execution
#
# Responsibilities:
# - Load and store stratagem definitions (Core stratagems + faction/detachment)
# - Track CP spending per player
# - Track usage restrictions (once per battle, once per turn, once per phase)
# - Validate whether a stratagem can be used (correct phase, timing, CP, target)
# - Provide available stratagems at any trigger point
# - Apply stratagem effects to game state

signal stratagem_used(player: int, stratagem_id: String, target_unit_id: String)
signal stratagem_available(player: int, stratagem_id: String, trigger: String)

# ============================================================================
# STRATAGEM DATA MODEL
# ============================================================================

# All loaded stratagem definitions keyed by id
var stratagems: Dictionary = {}

# Usage tracking per player: { "1": { "battle": [...], "turn_2": [...], "phase_command_2": [...] } }
var _usage_history: Dictionary = {
	"1": [],
	"2": []
}

# Active effects currently applied (cleared at appropriate times)
# Each entry: { "stratagem_id": String, "player": int, "target_unit_id": String,
#               "effects": Array, "expires": String, "applied_turn": int, "applied_phase": int }
var active_effects: Array = []

# Faction stratagem tracking: which faction stratagem IDs belong to each player
# { "1": ["faction_sm_gladius_storm_of_fire", ...], "2": ["faction_ork_war_horde_unbridled_carnage", ...] }
var _player_faction_stratagems: Dictionary = {
	"1": [],
	"2": []
}

# Faction stratagem loader instance
var _faction_loader: FactionStratagemLoaderData = null

func _ready() -> void:
	_load_core_stratagems()
	_init_faction_loader()
	print("StratagemManager: Loaded %d core stratagems" % stratagems.size())

func _init_faction_loader() -> void:
	"""Initialize the faction stratagem loader and load faction code mappings."""
	_faction_loader = FactionStratagemLoaderData.new()
	_faction_loader.load_faction_codes()

# ============================================================================
# STRATAGEM DEFINITIONS
# ============================================================================

func _load_core_stratagems() -> void:
	# Core stratagems available to all armies (10th Edition)
	# These are hardcoded for now; faction stratagems will be loaded from data later

	stratagems["insane_bravery"] = {
		"id": "insane_bravery",
		"name": "INSANE BRAVERY",
		"type": "Core – Epic Deed Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "your",           # "your", "opponent", "either"
			"phase": "command",        # Phase when it can be used
			"trigger": "before_battle_shock_test"  # Specific trigger point
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["needs_battle_shock_test"]
		},
		"effects": [
			{"type": "auto_pass_battle_shock"}
		],
		"restrictions": {
			"once_per": "battle",   # null, "turn", "phase", "battle"
		},
		"description": "Your unit automatically passes that Battle-shock test.",
		"when_text": "Battle-shock step of your Command phase, just before you take a Battle-shock test for a unit from your army.",
		"target_text": "That unit from your army.",
		"effect_text": "Your unit automatically passes that Battle-shock test.",
		"restriction_text": "You cannot use this Stratagem more than once per battle."
	}

	stratagems["command_re_roll"] = {
		"id": "command_re_roll",
		"name": "COMMAND RE-ROLL",
		"type": "Core – Battle Tactic Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "either",
			"phase": "any",
			"trigger": "after_roll"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": []
		},
		"effects": [
			{"type": "reroll_last_roll"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "You re-roll that roll, test or saving throw.",
		"when_text": "Any phase, just after you make a roll for a unit from your army.",
		"target_text": "That unit or model from your army.",
		"effect_text": "You re-roll that roll, test or saving throw.",
		"restriction_text": ""
	}

	stratagems["go_to_ground"] = {
		"id": "go_to_ground",
		"name": "GO TO GROUND",
		"type": "Core – Battle Tactic Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "opponent",
			"phase": "shooting",
			"trigger": "after_target_selected"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["keyword:INFANTRY", "is_target_of_attack"]
		},
		"effects": [
			{"type": "grant_invuln", "value": 6},
			{"type": "grant_cover"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Until the end of the phase, all models in your unit have a 6+ invulnerable save and have the Benefit of Cover.",
		"when_text": "Your opponent's Shooting phase, just after an enemy unit has selected its targets.",
		"target_text": "One INFANTRY unit from your army that was selected as the target.",
		"effect_text": "Until the end of the phase, all models in your unit have a 6+ invulnerable save and have the Benefit of Cover.",
		"restriction_text": ""
	}

	stratagems["smokescreen"] = {
		"id": "smokescreen",
		"name": "SMOKESCREEN",
		"type": "Core – Wargear Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "opponent",
			"phase": "shooting",
			"trigger": "after_target_selected"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["keyword:SMOKE", "is_target_of_attack"]
		},
		"effects": [
			{"type": "grant_cover"},
			{"type": "grant_stealth"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Until the end of the phase, all models in your unit have the Benefit of Cover and the Stealth ability.",
		"when_text": "Your opponent's Shooting phase, just after an enemy unit has selected its targets.",
		"target_text": "One SMOKE unit from your army that was selected as the target.",
		"effect_text": "Until the end of the phase, all models in your unit have the Benefit of Cover and the Stealth ability.",
		"restriction_text": ""
	}

	stratagems["epic_challenge"] = {
		"id": "epic_challenge",
		"name": "EPIC CHALLENGE",
		"type": "Core – Epic Deed Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "either",
			"phase": "fight",
			"trigger": "fighter_selected"
		},
		"target": {
			"type": "model",
			"owner": "friendly",
			"conditions": ["keyword:CHARACTER", "in_engagement_range"]
		},
		"effects": [
			{"type": "grant_keyword", "keyword": "PRECISION", "scope": "melee"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Until the end of the phase, all melee attacks made by that model have the [PRECISION] ability.",
		"when_text": "Fight phase, when a CHARACTER unit from your army is selected to fight.",
		"target_text": "One CHARACTER model in your unit.",
		"effect_text": "Until the end of the phase, all melee attacks made by that model have the [PRECISION] ability.",
		"restriction_text": ""
	}

	stratagems["grenade"] = {
		"id": "grenade",
		"name": "GRENADE",
		"type": "Core – Wargear Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "your",
			"phase": "shooting",
			"trigger": "shooting_phase_active"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["keyword:GRENADES", "not_advanced", "not_fell_back", "not_shot", "not_in_engagement"]
		},
		"effects": [
			{"type": "mortal_wounds", "dice": 6, "threshold": 4}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Roll six D6: for each 4+, that enemy unit suffers 1 mortal wound.",
		"when_text": "Your Shooting phase.",
		"target_text": "One GRENADES unit from your army.",
		"effect_text": "Select one enemy unit within 8\" and visible. Roll six D6: for each 4+, that enemy unit suffers 1 mortal wound.",
		"restriction_text": ""
	}

	stratagems["tank_shock"] = {
		"id": "tank_shock",
		"name": "TANK SHOCK",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "your",
			"phase": "charge",
			"trigger": "after_charge_move"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["keyword:VEHICLE", "charged_this_turn"]
		},
		"effects": [
			{"type": "mortal_wounds_toughness_based", "threshold": 5, "max": 6}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Roll D6 equal to the Vehicle's Toughness. For each 5+, the enemy unit suffers 1 mortal wound (max 6).",
		"when_text": "Your Charge phase, just after a VEHICLE unit ends a Charge move.",
		"target_text": "That VEHICLE unit.",
		"effect_text": "Select one enemy unit within Engagement Range. Roll D6 equal to Toughness; for each 5+, 1 mortal wound (max 6).",
		"restriction_text": ""
	}

	stratagems["fire_overwatch"] = {
		"id": "fire_overwatch",
		"name": "FIRE OVERWATCH",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "opponent",
			"phase": "movement_or_charge",
			"trigger": "enemy_move_or_charge"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["within_24_of_enemy", "eligible_to_shoot"]
		},
		"effects": [
			{"type": "overwatch_shoot", "hit_on": 6}
		],
		"restrictions": {
			"once_per": "turn",
		},
		"description": "Your unit can shoot that enemy unit, but only hit on unmodified 6s.",
		"when_text": "Your opponent's Movement or Charge phase.",
		"target_text": "One unit from your army within 24\" of that enemy unit.",
		"effect_text": "Your unit can shoot that enemy unit as if it were your Shooting phase. Only unmodified 6s hit.",
		"restriction_text": "Once per turn."
	}

	stratagems["heroic_intervention"] = {
		"id": "heroic_intervention",
		"name": "HEROIC INTERVENTION",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 2,
		"timing": {
			"turn": "opponent",
			"phase": "charge",
			"trigger": "after_enemy_charge_move"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["within_6_of_charging_enemy", "not_in_engagement_range"]
		},
		"effects": [
			{"type": "counter_charge", "no_fights_first": true}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Your unit declares a charge targeting only that enemy unit, but does not gain the Fights First ability.",
		"when_text": "Your opponent's Charge phase, just after an enemy unit ends a Charge move.",
		"target_text": "One unit from your army within 6\" of that enemy unit and not within Engagement Range of any enemy units.",
		"effect_text": "Your unit now declares a charge that targets only that enemy unit, then makes a charge roll. It cannot be selected to fight in the Fights First step.",
		"restriction_text": "Cannot select a VEHICLE unit unless it has the WALKER keyword. Once per phase."
	}

	stratagems["counter_offensive"] = {
		"id": "counter_offensive",
		"name": "COUNTER-OFFENSIVE",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 2,
		"timing": {
			"turn": "either",
			"phase": "fight",
			"trigger": "after_enemy_fought"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["in_engagement_range", "not_fought_this_phase"]
		},
		"effects": [
			{"type": "fight_next"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Your unit fights next.",
		"when_text": "Fight phase, just after an enemy unit has fought.",
		"target_text": "One unit from your army in Engagement Range that has not fought this phase.",
		"effect_text": "Your unit fights next.",
		"restriction_text": ""
	}

	stratagems["new_orders"] = {
		"id": "new_orders",
		"name": "NEW ORDERS",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "your",
			"phase": "command",
			"trigger": "end_of_command_phase"
		},
		"target": {
			"type": "secondary_mission",
			"owner": "friendly",
			"conditions": []
		},
		"effects": [
			{"type": "discard_and_draw_secondary"}
		],
		"restrictions": {
			"once_per": "battle",
		},
		"description": "Discard one of your active Secondary Mission cards and draw a new one.",
		"when_text": "End of your Command phase.",
		"target_text": "One of your active Secondary Mission cards.",
		"effect_text": "Discard that Secondary Mission card. Then draw one card from your Secondary Mission deck.",
		"restriction_text": "You can only use this Stratagem once per battle."
	}

	stratagems["rapid_ingress"] = {
		"id": "rapid_ingress",
		"name": "RAPID INGRESS",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "opponent",
			"phase": "movement",
			"trigger": "end_of_enemy_movement"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["in_reserves"]
		},
		"effects": [
			{"type": "arrive_from_reserves"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Your unit arrives on the battlefield as if it were the Reinforcements step.",
		"when_text": "End of your opponent's Movement phase.",
		"target_text": "One unit from your army that is in Reserves.",
		"effect_text": "Your unit can arrive on the battlefield as if it were the Reinforcements step of your Movement phase.",
		"restriction_text": "Cannot arrive in a battle round it normally wouldn't be able to."
	}

# ============================================================================
# FACTION STRATAGEM LOADING
# ============================================================================

func load_faction_stratagems_for_player(player: int) -> void:
	"""
	Load faction stratagems for a player based on their army's faction and detachment.
	Called after armies are loaded into GameState.
	"""
	if _faction_loader == null:
		_init_faction_loader()

	var faction_data = GameState.state.get("factions", {}).get(str(player), {})
	var faction_name = faction_data.get("name", "")
	var detachment_name = faction_data.get("detachment", "")

	if faction_name == "" or faction_name == "Unknown":
		print("StratagemManager: No faction data for player %d, skipping faction stratagems" % player)
		return

	print("StratagemManager: Loading faction stratagems for player %d — %s / %s" % [player, faction_name, detachment_name])

	var faction_strats = _faction_loader.load_faction_stratagems(faction_name, detachment_name)

	# Clear any previously loaded faction stratagems for this player
	_clear_player_faction_stratagems(player)

	# Add faction stratagems to the main stratagems dictionary
	var loaded_count = 0
	var implemented_count = 0
	for strat in faction_strats:
		var strat_id = strat.get("id", "")
		if strat_id == "":
			continue

		stratagems[strat_id] = strat
		_player_faction_stratagems[str(player)].append(strat_id)
		loaded_count += 1
		if strat.get("implemented", false):
			implemented_count += 1

	print("StratagemManager: Loaded %d faction stratagems for player %d (%d mechanically implemented)" % [loaded_count, player, implemented_count])

func load_all_faction_stratagems() -> void:
	"""Load faction stratagems for both players. Call after armies are loaded."""
	load_faction_stratagems_for_player(1)
	load_faction_stratagems_for_player(2)

func _clear_player_faction_stratagems(player: int) -> void:
	"""Remove previously loaded faction stratagems for a player."""
	var player_key = str(player)
	if _player_faction_stratagems.has(player_key):
		for strat_id in _player_faction_stratagems[player_key]:
			stratagems.erase(strat_id)
		_player_faction_stratagems[player_key] = []

func is_faction_stratagem(stratagem_id: String) -> bool:
	"""Check if a stratagem is a faction-specific stratagem (not Core)."""
	return stratagem_id.begins_with("faction_")

func get_stratagem_owner(stratagem_id: String) -> int:
	"""
	Get which player owns a faction stratagem. Returns 0 if it's a Core stratagem
	(available to both) or if the stratagem is unknown.
	"""
	if not is_faction_stratagem(stratagem_id):
		return 0  # Core stratagems are available to all

	for player_key in _player_faction_stratagems:
		if stratagem_id in _player_faction_stratagems[player_key]:
			return int(player_key)

	return 0

func get_faction_stratagems_for_player(player: int) -> Array:
	"""Get all faction stratagem definitions loaded for a player."""
	var result: Array = []
	var player_key = str(player)
	if _player_faction_stratagems.has(player_key):
		for strat_id in _player_faction_stratagems[player_key]:
			if stratagems.has(strat_id):
				result.append(stratagems[strat_id])
	return result

func get_implemented_faction_stratagems_for_player(player: int) -> Array:
	"""Get only mechanically implemented faction stratagems for a player."""
	var result: Array = []
	for strat in get_faction_stratagems_for_player(player):
		if strat.get("implemented", false):
			result.append(strat)
	return result

# ============================================================================
# VALIDATION
# ============================================================================

func can_use_stratagem(player: int, stratagem_id: String, target_unit_id: String = "", context: Dictionary = {}) -> Dictionary:
	"""
	Check if a player can use a specific stratagem right now.
	Returns { "can_use": bool, "reason": String }
	"""
	if not stratagems.has(stratagem_id):
		return {"can_use": false, "reason": "Unknown stratagem: %s" % stratagem_id}

	var strat = stratagems[stratagem_id]

	# Check player ownership for faction stratagems
	if is_faction_stratagem(stratagem_id):
		var owner = get_stratagem_owner(stratagem_id)
		if owner != 0 and owner != player:
			return {"can_use": false, "reason": "This stratagem belongs to player %d" % owner}
		# Check if stratagem is mechanically implemented
		if not strat.get("implemented", false):
			return {"can_use": false, "reason": "%s is not yet mechanically implemented" % strat.name}

	# Check CP (account for possible Strategic Mastery discount)
	var effective_cost = strat.cp_cost
	if target_unit_id != "" and effective_cost > 0:
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr and ability_mgr.has_strategic_mastery(target_unit_id):
			if not ability_mgr.is_once_per_round_used(player, "Strategic Mastery"):
				effective_cost = maxi(effective_cost - 1, 0)
	var player_cp = _get_player_cp(player)
	if player_cp < effective_cost:
		return {"can_use": false, "reason": "Not enough CP (need %d, have %d)" % [effective_cost, player_cp]}

	# Check usage restrictions
	var restriction_check = _check_usage_restriction(player, stratagem_id, strat)
	if not restriction_check.can_use:
		return restriction_check

	# Check battle-shocked (battle-shocked units can't be targeted by friendly stratagems)
	# Exception: Insane Bravery explicitly allows targeting battle-shocked units
	if target_unit_id != "" and stratagem_id != "insane_bravery":
		var unit = GameState.get_unit(target_unit_id)
		if not unit.is_empty() and unit.get("flags", {}).get("battle_shocked", false):
			return {"can_use": false, "reason": "Battle-shocked units cannot be targeted by Stratagems"}

	return {"can_use": true, "reason": ""}

func _check_usage_restriction(player: int, stratagem_id: String, strat: Dictionary) -> Dictionary:
	"""Check once-per restrictions for a stratagem."""
	var restriction = strat.get("restrictions", {}).get("once_per", null)
	if restriction == null:
		return {"can_use": true, "reason": ""}

	var player_history = _usage_history.get(str(player), [])
	var current_turn = GameState.get_battle_round()
	var current_phase = GameState.get_current_phase()

	match restriction:
		"battle":
			# Check if this stratagem was ever used this battle
			for usage in player_history:
				if usage.stratagem_id == stratagem_id:
					return {"can_use": false, "reason": "%s can only be used once per battle" % strat.name}
		"turn":
			# Check if used this turn
			for usage in player_history:
				if usage.stratagem_id == stratagem_id and usage.turn == current_turn:
					return {"can_use": false, "reason": "%s can only be used once per turn" % strat.name}
		"phase":
			# Check if used this phase (same turn + same phase)
			for usage in player_history:
				if usage.stratagem_id == stratagem_id and usage.turn == current_turn and usage.phase == current_phase:
					return {"can_use": false, "reason": "%s can only be used once per phase" % strat.name}

	return {"can_use": true, "reason": ""}

# ============================================================================
# USAGE / EXECUTION
# ============================================================================

func _safe_apply_state_changes(diffs: Array) -> void:
	"""Apply state changes via PhaseManager if available, otherwise apply directly."""
	if PhaseManager != null:
		PhaseManager.apply_state_changes(diffs)
	else:
		# Fallback: apply diffs directly to GameState (for tests where PhaseManager isn't loaded)
		for diff in diffs:
			if diff.get("op", "") == "set":
				var parts = diff.path.split(".")
				var current = GameState.state
				for i in range(parts.size() - 1):
					var part = parts[i]
					if current is Dictionary:
						if not current.has(part):
							current[part] = {}
						current = current[part]
				var final_key = parts[-1]
				if current is Dictionary:
					current[final_key] = diff.value

func use_stratagem(player: int, stratagem_id: String, target_unit_id: String = "", context: Dictionary = {}) -> Dictionary:
	"""
	Use a stratagem. Validates, deducts CP, records usage, and returns effect data.
	Returns { "success": bool, "effects": Array, "diffs": Array, "message": String }
	"""
	# Validate
	var validation = can_use_stratagem(player, stratagem_id, target_unit_id, context)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": []}

	var strat = stratagems[stratagem_id]
	var diffs = []

	# Calculate effective CP cost (check for Strategic Mastery discount)
	var effective_cp_cost = strat.cp_cost
	var strategic_mastery_applied = false
	if target_unit_id != "" and effective_cp_cost > 0:
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr and ability_mgr.has_strategic_mastery(target_unit_id):
			if not ability_mgr.is_once_per_round_used(player, "Strategic Mastery"):
				effective_cp_cost = maxi(effective_cp_cost - 1, 0)
				strategic_mastery_applied = true
				ability_mgr.mark_once_per_round_used(player, "Strategic Mastery")
				print("StratagemManager: Strategic Mastery reduces CP cost of %s by 1 (was %d, now %d)" % [strat.name, strat.cp_cost, effective_cp_cost])

	# Deduct CP
	var current_cp = _get_player_cp(player)
	var new_cp = current_cp - effective_cp_cost
	diffs.append({
		"op": "set",
		"path": "players.%s.cp" % str(player),
		"value": new_cp
	})

	# Record usage
	var usage_record = {
		"stratagem_id": stratagem_id,
		"player": player,
		"target_unit_id": target_unit_id,
		"turn": GameState.get_battle_round(),
		"phase": GameState.get_current_phase(),
		"timestamp": Time.get_unix_time_from_system()
	}
	_usage_history[str(player)].append(usage_record)

	# Apply the CP diff immediately
	_safe_apply_state_changes(diffs)

	var cost_msg = "%d CP" % effective_cp_cost
	if strategic_mastery_applied:
		cost_msg += " (reduced from %d by Strategic Mastery)" % strat.cp_cost
	print("StratagemManager: Player %d used %s on %s (cost %s, %d -> %d)" % [
		player, strat.name, target_unit_id if target_unit_id != "" else "N/A",
		cost_msg, current_cp, new_cp
	])

	# Log to phase log
	GameState.add_action_to_phase_log({
		"type": "STRATAGEM_USED",
		"stratagem_id": stratagem_id,
		"stratagem_name": strat.name,
		"player": player,
		"target_unit_id": target_unit_id,
		"cp_cost": effective_cp_cost,
		"original_cp_cost": strat.cp_cost,
		"strategic_mastery_discount": strategic_mastery_applied,
		"turn": GameState.get_battle_round()
	})

	# Apply stratagem-specific effects to game state (unit flags for RulesEngine)
	var effect_diffs = _apply_stratagem_effects(stratagem_id, target_unit_id, strat)
	if not effect_diffs.is_empty():
		_safe_apply_state_changes(effect_diffs)
		diffs.append_array(effect_diffs)

	# Track active effect for duration management
	add_active_effect({
		"stratagem_id": stratagem_id,
		"player": player,
		"target_unit_id": target_unit_id,
		"effects": strat.effects,
		"expires": "end_of_phase",
		"applied_turn": GameState.get_battle_round(),
		"applied_phase": GameState.get_current_phase()
	})

	# Emit signal
	emit_signal("stratagem_used", player, stratagem_id, target_unit_id)

	return {
		"success": true,
		"effects": strat.effects,
		"diffs": diffs,
		"message": "Used %s" % strat.name
	}

# ============================================================================
# QUERIES
# ============================================================================

func get_available_stratagems_for_trigger(player: int, trigger: String, context: Dictionary = {}) -> Array:
	"""
	Get all stratagems a player could use at a specific trigger point.
	Returns array of stratagem definitions that pass validation.
	"""
	var available = []

	for strat_id in stratagems:
		var strat = stratagems[strat_id]

		# Check trigger matches
		if strat.timing.trigger != trigger:
			continue

		# Check turn timing
		var active_player = GameState.get_active_player()
		var is_your_turn = (player == active_player)
		match strat.timing.turn:
			"your":
				if not is_your_turn:
					continue
			"opponent":
				if is_your_turn:
					continue
			"either":
				pass  # Always available

		# Check phase
		var current_phase = GameState.get_current_phase()
		var phase_name = _phase_to_string(current_phase)
		if strat.timing.phase != "any" and strat.timing.phase != phase_name:
			# Also check compound phases like "movement_or_charge"
			if "_or_" in strat.timing.phase:
				var valid_phases = strat.timing.phase.split("_or_")
				if phase_name not in valid_phases:
					continue
			else:
				continue

		# Check if can be used (CP, restrictions)
		var target_unit_id = context.get("target_unit_id", "")
		var validation = can_use_stratagem(player, strat_id, target_unit_id, context)
		if validation.can_use:
			available.append(strat)

	return available

func get_stratagem(stratagem_id: String) -> Dictionary:
	"""Get a stratagem definition by ID."""
	return stratagems.get(stratagem_id, {})

func get_player_cp(player: int) -> int:
	"""Public accessor for player CP."""
	return _get_player_cp(player)

# ============================================================================
# TURN/PHASE LIFECYCLE
# ============================================================================

func on_phase_start(phase: int) -> void:
	"""Called when a new phase starts. Clears phase-scoped active effects."""
	_clear_expired_effects("end_of_phase")
	print("StratagemManager: Phase %s started, cleared phase-scoped effects" % _phase_to_string(phase))

func on_phase_end(phase: int) -> void:
	"""Called when a phase ends."""
	_clear_expired_effects("end_of_phase")

func on_turn_start(player: int) -> void:
	"""Called when a new turn starts for a player."""
	_clear_expired_effects("end_of_turn")
	print("StratagemManager: Turn started for player %d, cleared turn-scoped effects" % player)

func on_battle_round_start(round_number: int) -> void:
	"""Called at the start of a new battle round."""
	print("StratagemManager: Battle round %d started" % round_number)

# ============================================================================
# ACTIVE EFFECTS
# ============================================================================

func add_active_effect(effect: Dictionary) -> void:
	"""Add an active stratagem effect that lasts for a duration."""
	active_effects.append(effect)

func get_active_effects_for_unit(unit_id: String) -> Array:
	"""Get all active stratagem effects targeting a specific unit."""
	var effects = []
	for effect in active_effects:
		if effect.get("target_unit_id", "") == unit_id:
			effects.append(effect)
	return effects

func has_active_effect(unit_id: String, effect_type: String) -> bool:
	"""Check if a unit has a specific active effect."""
	for effect in active_effects:
		if effect.get("target_unit_id", "") == unit_id:
			for e in effect.get("effects", []):
				if e.get("type", "") == effect_type:
					return true
	return false

func _clear_expired_effects(expiry_type: String) -> void:
	"""Remove effects that have expired. Also clears unit flags set by expired stratagems."""
	var remaining = []
	for effect in active_effects:
		if effect.get("expires", "") != expiry_type:
			remaining.append(effect)
		else:
			# Clear unit flags for this expired effect
			var unit_id = effect.get("target_unit_id", "")
			var strat_id = effect.get("stratagem_id", "")
			if unit_id != "":
				_clear_stratagem_flags(unit_id, strat_id)
	active_effects = remaining

# ============================================================================
# STRATAGEM EFFECT APPLICATION
# ============================================================================

func _apply_stratagem_effects(_stratagem_id: String, target_unit_id: String, strat: Dictionary) -> Array:
	"""
	Apply stratagem effects to unit flags in game state using EffectPrimitives.
	Returns an array of diffs that set the appropriate flags.
	These flags are read by RulesEngine during combat resolution.
	"""
	var effects = strat.get("effects", [])
	var diffs = EffectPrimitivesData.apply_effects(effects, target_unit_id)

	if not diffs.is_empty():
		var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
		print("StratagemManager: Applied %s effects to %s (flags: %s)" % [strat.name, target_unit_id, str(flag_names)])

	return diffs

func _clear_stratagem_flags(unit_id: String, stratagem_id: String) -> void:
	"""Clear stratagem-specific flags from a unit when the effect expires."""
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var flags = unit.get("flags", {})
	var strat = stratagems.get(stratagem_id, {})
	var effects = strat.get("effects", [])

	EffectPrimitivesData.clear_effects(effects, unit_id, flags)
	print("StratagemManager: Cleared %s flags from %s" % [stratagem_id, unit_id])

func get_grenade_eligible_units(player: int) -> Array:
	"""
	Get units that can use the GRENADE stratagem for the given player.
	Requirements: GRENADES keyword, not advanced, not fell back, not shot, not in engagement.
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Check if grenade stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "grenade")
	if not validation.can_use:
		return eligible

	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		var flags = unit.get("flags", {})
		var keywords = unit.get("meta", {}).get("keywords", [])

		# Check GRENADES keyword
		var has_grenades = false
		for kw in keywords:
			if kw.to_upper() == "GRENADES":
				has_grenades = true
				break
		if not has_grenades:
			continue

		# Check exclusions
		if flags.get("advanced", false):
			continue
		if flags.get("fell_back", false):
			continue
		if flags.get("has_shot", false):
			continue
		if flags.get("in_engagement", false):
			continue
		if flags.get("battle_shocked", false):
			continue

		# Must be deployed/moved
		var status = unit.get("status", 0)
		if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
			continue

		# Check if unit has alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func execute_grenade(player: int, grenade_unit_id: String, target_unit_id: String) -> Dictionary:
	"""
	Execute the GRENADE stratagem: roll 6D6, each 4+ deals 1 mortal wound to target.
	Handles CP deduction, usage tracking, dice rolling, and mortal wound application.
	Returns { success: bool, diffs: Array, dice_rolls: Array, mortal_wounds: int,
	          casualties: int, message: String }
	"""
	# Validate
	var validation = can_use_stratagem(player, "grenade", grenade_unit_id)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": [], "dice_rolls": [], "mortal_wounds": 0, "casualties": 0}

	var strat = stratagems["grenade"]
	var diffs = []

	# Deduct CP
	var current_cp = _get_player_cp(player)
	var new_cp = current_cp - strat.cp_cost
	diffs.append({
		"op": "set",
		"path": "players.%s.cp" % str(player),
		"value": new_cp
	})

	# Record usage
	var usage_record = {
		"stratagem_id": "grenade",
		"player": player,
		"target_unit_id": grenade_unit_id,
		"turn": GameState.get_battle_round(),
		"phase": GameState.get_current_phase(),
		"timestamp": Time.get_unix_time_from_system()
	}
	_usage_history[str(player)].append(usage_record)

	# Apply CP diff
	_safe_apply_state_changes(diffs)

	print("StratagemManager: Player %d used GRENADE with %s targeting %s (cost %d CP, %d -> %d)" % [
		player, grenade_unit_id, target_unit_id, strat.cp_cost, current_cp, new_cp
	])

	# Log to phase log
	GameState.add_action_to_phase_log({
		"type": "STRATAGEM_USED",
		"stratagem_id": "grenade",
		"stratagem_name": strat.name,
		"player": player,
		"target_unit_id": grenade_unit_id,
		"enemy_target_unit_id": target_unit_id,
		"cp_cost": strat.cp_cost,
		"turn": GameState.get_battle_round()
	})

	# Roll 6D6
	var rng = RulesEngine.RNGService.new()
	var rolls = rng.roll_d6(6)

	# Count successes (4+)
	var mortal_wounds = 0
	for roll in rolls:
		if roll >= 4:
			mortal_wounds += 1

	print("StratagemManager: GRENADE rolled %s — %d mortal wound(s)" % [str(rolls), mortal_wounds])

	# Apply mortal wounds to the enemy target
	var mw_diffs = []
	var casualties = 0
	if mortal_wounds > 0:
		var board = GameState.create_snapshot()
		var mw_result = RulesEngine.apply_mortal_wounds(target_unit_id, mortal_wounds, board, rng)
		mw_diffs = mw_result.get("diffs", [])
		casualties = mw_result.get("casualties", 0)

		if not mw_diffs.is_empty():
			_safe_apply_state_changes(mw_diffs)
			diffs.append_array(mw_diffs)

		print("StratagemManager: GRENADE applied %d mortal wounds to %s (%d casualties)" % [mortal_wounds, target_unit_id, casualties])

	# Mark the grenade unit as having shot (it uses its shooting for this phase)
	var shot_diff = {
		"op": "set",
		"path": "units.%s.flags.has_shot" % grenade_unit_id,
		"value": true
	}
	_safe_apply_state_changes([shot_diff])
	diffs.append(shot_diff)

	# Track active effect (no persistent flags needed for grenade - it's instant)
	add_active_effect({
		"stratagem_id": "grenade",
		"player": player,
		"target_unit_id": grenade_unit_id,
		"effects": strat.effects,
		"expires": "end_of_phase",
		"applied_turn": GameState.get_battle_round(),
		"applied_phase": GameState.get_current_phase()
	})

	# Emit signal
	emit_signal("stratagem_used", player, "grenade", grenade_unit_id)

	# Log mortal wound results to phase log
	var target_unit = GameState.get_unit(target_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	var grenade_unit = GameState.get_unit(grenade_unit_id)
	var grenade_name = grenade_unit.get("meta", {}).get("name", grenade_unit_id)

	GameState.add_action_to_phase_log({
		"type": "GRENADE_RESULT",
		"player": player,
		"grenade_unit_id": grenade_unit_id,
		"grenade_unit_name": grenade_name,
		"target_unit_id": target_unit_id,
		"target_unit_name": target_name,
		"rolls": rolls,
		"mortal_wounds": mortal_wounds,
		"casualties": casualties
	})

	return {
		"success": true,
		"diffs": diffs,
		"dice_rolls": rolls,
		"mortal_wounds": mortal_wounds,
		"casualties": casualties,
		"message": "%s threw GRENADE at %s: rolled %s — %d mortal wound(s), %d casualt%s" % [
			grenade_name, target_name, str(rolls), mortal_wounds, casualties,
			"y" if casualties == 1 else "ies"
		]
	}

func is_epic_challenge_available(player: int, unit_id: String) -> Dictionary:
	"""
	Check if Epic Challenge stratagem is available for a fighter unit.
	The unit must contain a CHARACTER keyword to be eligible.
	Returns { available: bool, reason: String }
	"""
	# Check if the stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "epic_challenge", unit_id)
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}

	# Check CHARACTER keyword on the unit
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return {"available": false, "reason": "Unit not found"}

	var keywords = unit.get("meta", {}).get("keywords", [])
	var has_character = false
	for kw in keywords:
		if kw.to_upper() == "CHARACTER":
			has_character = true
			break

	if not has_character:
		return {"available": false, "reason": "Unit does not have CHARACTER keyword"}

	# Check unit is not battle-shocked
	var flags = unit.get("flags", {})
	if flags.get("battle_shocked", false):
		return {"available": false, "reason": "Battle-shocked units cannot use Stratagems"}

	return {"available": true, "reason": ""}

func is_command_reroll_available(player: int) -> Dictionary:
	"""
	Check if Command Re-roll is available for a player in the current phase.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "command_re_roll")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

func execute_command_reroll(player: int, unit_id: String, roll_context: Dictionary) -> Dictionary:
	"""
	Execute the Command Re-roll stratagem: deduct CP, record usage, signal.
	The actual re-rolling of dice is handled by the calling phase.
	roll_context should contain: { roll_type, original_rolls, unit_name }
	Returns { success: bool, diffs: Array, message: String }
	"""
	var validation = can_use_stratagem(player, "command_re_roll", unit_id)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": []}

	# Use the standard use_stratagem flow for CP deduction and usage tracking
	var result = use_stratagem(player, "command_re_roll", unit_id)
	if not result.success:
		return result

	var roll_type = roll_context.get("roll_type", "unknown")
	var original_rolls = roll_context.get("original_rolls", [])
	var unit_name = roll_context.get("unit_name", unit_id)

	print("StratagemManager: COMMAND RE-ROLL executed by player %d on %s (%s roll: %s)" % [
		player, unit_name, roll_type, str(original_rolls)
	])

	# Log the reroll to phase log
	GameState.add_action_to_phase_log({
		"type": "COMMAND_REROLL",
		"player": player,
		"unit_id": unit_id,
		"unit_name": unit_name,
		"roll_type": roll_type,
		"original_rolls": original_rolls,
		"turn": GameState.get_battle_round()
	})

	return {
		"success": true,
		"diffs": result.get("diffs", []),
		"message": "COMMAND RE-ROLL used on %s (%s)" % [unit_name, roll_type]
	}

func is_counter_offensive_available(player: int) -> Dictionary:
	"""
	Check if Counter-Offensive stratagem is available for a player.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "counter_offensive")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

func get_counter_offensive_eligible_units(player: int, units_that_fought: Array, game_state_snapshot: Dictionary) -> Array:
	"""
	Get units eligible for Counter-Offensive for a given player.
	Requirements: owned by player, in engagement range, not fought this phase, not battle-shocked.
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Check if the stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "counter_offensive")
	if not validation.can_use:
		return eligible

	var all_units = game_state_snapshot.get("units", {})
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue

		# Must not have already fought this phase
		if unit_id in units_that_fought:
			continue

		# Must not be battle-shocked
		var flags = unit.get("flags", {})
		if flags.get("battle_shocked", false):
			continue

		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Must be in engagement range of at least one enemy
		var in_engagement = false
		var unit_owner = int(unit.get("owner", 0))
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if int(other_unit.get("owner", 0)) == unit_owner:
				continue
			if _units_in_engagement_range(unit, other_unit):
				in_engagement = true
				break

		if not in_engagement:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func _units_in_engagement_range(unit1: Dictionary, unit2: Dictionary) -> bool:
	"""Check if any model from unit1 is within 1\" of any model from unit2."""
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])

	for model1 in models1:
		if not model1.get("alive", true):
			continue
		var pos1_data = model1.get("position", {})
		if pos1_data == null:
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue
			var pos2_data = model2.get("position", {})
			if pos2_data == null:
				continue

			if Measurement.is_in_engagement_range_shape_aware(model1, model2, 1.0):
				return true

	return false

func is_tank_shock_available(player: int) -> Dictionary:
	"""
	Check if Tank Shock stratagem is available for a player.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "tank_shock")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

func get_tank_shock_eligible_targets(vehicle_unit_id: String, game_state_snapshot: Dictionary) -> Array:
	"""
	Get enemy units within Engagement Range (1") of a VEHICLE unit that just charged.
	Returns array of { unit_id: String, unit_name: String, model_count: int }
	"""
	var eligible = []
	var vehicle_unit = game_state_snapshot.get("units", {}).get(vehicle_unit_id, {})
	if vehicle_unit.is_empty():
		return eligible

	var vehicle_owner = int(vehicle_unit.get("owner", 0))
	var all_units = game_state_snapshot.get("units", {})

	for unit_id in all_units:
		var unit = all_units[unit_id]
		# Must be an enemy unit
		if int(unit.get("owner", 0)) == vehicle_owner:
			continue

		# Must have alive models
		var alive_count = 0
		for model in unit.get("models", []):
			if model.get("alive", true):
				alive_count += 1
		if alive_count == 0:
			continue

		# Must be within Engagement Range (1") of the vehicle
		if _units_in_engagement_range(vehicle_unit, unit):
			eligible.append({
				"unit_id": unit_id,
				"unit_name": unit.get("meta", {}).get("name", unit_id),
				"model_count": alive_count
			})

	return eligible

func execute_tank_shock(player: int, vehicle_unit_id: String, target_unit_id: String) -> Dictionary:
	"""
	Execute the TANK SHOCK stratagem: roll D6 equal to Vehicle's Toughness (max 6),
	each 5+ deals 1 mortal wound to the target enemy unit.
	Handles CP deduction, usage tracking, dice rolling, and mortal wound application.
	Returns { success: bool, diffs: Array, dice_rolls: Array, mortal_wounds: int,
	          casualties: int, toughness: int, dice_count: int, message: String }
	"""
	# Validate
	var validation = can_use_stratagem(player, "tank_shock", vehicle_unit_id)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": [], "dice_rolls": [], "mortal_wounds": 0, "casualties": 0, "toughness": 0, "dice_count": 0}

	var strat = stratagems["tank_shock"]
	var diffs = []

	# Get vehicle toughness
	var vehicle_unit = GameState.get_unit(vehicle_unit_id)
	var toughness = int(vehicle_unit.get("meta", {}).get("toughness", 4))
	var dice_count = mini(toughness, 6)  # Max 6 dice

	# Deduct CP
	var current_cp = _get_player_cp(player)
	var new_cp = current_cp - strat.cp_cost
	diffs.append({
		"op": "set",
		"path": "players.%s.cp" % str(player),
		"value": new_cp
	})

	# Record usage
	var usage_record = {
		"stratagem_id": "tank_shock",
		"player": player,
		"target_unit_id": vehicle_unit_id,
		"turn": GameState.get_battle_round(),
		"phase": GameState.get_current_phase(),
		"timestamp": Time.get_unix_time_from_system()
	}
	_usage_history[str(player)].append(usage_record)

	# Apply CP diff
	_safe_apply_state_changes(diffs)

	var vehicle_name = vehicle_unit.get("meta", {}).get("name", vehicle_unit_id)
	print("StratagemManager: Player %d used TANK SHOCK with %s (T%d, %dD6) targeting %s (cost %d CP, %d -> %d)" % [
		player, vehicle_name, toughness, dice_count, target_unit_id, strat.cp_cost, current_cp, new_cp
	])

	# Log to phase log
	GameState.add_action_to_phase_log({
		"type": "STRATAGEM_USED",
		"stratagem_id": "tank_shock",
		"stratagem_name": strat.name,
		"player": player,
		"target_unit_id": vehicle_unit_id,
		"enemy_target_unit_id": target_unit_id,
		"cp_cost": strat.cp_cost,
		"turn": GameState.get_battle_round()
	})

	# Roll D6 equal to Toughness (max 6)
	var rng = RulesEngine.RNGService.new()
	var rolls = rng.roll_d6(dice_count)

	# Count successes (5+)
	var mortal_wounds = 0
	for roll in rolls:
		if roll >= 5:
			mortal_wounds += 1

	print("StratagemManager: TANK SHOCK rolled %dD6 %s — %d mortal wound(s)" % [dice_count, str(rolls), mortal_wounds])

	# Apply mortal wounds to the enemy target
	var mw_diffs = []
	var casualties = 0
	if mortal_wounds > 0:
		var board = GameState.create_snapshot()
		var mw_result = RulesEngine.apply_mortal_wounds(target_unit_id, mortal_wounds, board, rng)
		mw_diffs = mw_result.get("diffs", [])
		casualties = mw_result.get("casualties", 0)

		if not mw_diffs.is_empty():
			_safe_apply_state_changes(mw_diffs)
			diffs.append_array(mw_diffs)

		print("StratagemManager: TANK SHOCK applied %d mortal wounds to %s (%d casualties)" % [mortal_wounds, target_unit_id, casualties])

	# Track active effect (no persistent flags needed — instant effect)
	add_active_effect({
		"stratagem_id": "tank_shock",
		"player": player,
		"target_unit_id": vehicle_unit_id,
		"effects": strat.effects,
		"expires": "end_of_phase",
		"applied_turn": GameState.get_battle_round(),
		"applied_phase": GameState.get_current_phase()
	})

	# Emit signal
	emit_signal("stratagem_used", player, "tank_shock", vehicle_unit_id)

	# Log mortal wound results to phase log
	var target_unit = GameState.get_unit(target_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

	GameState.add_action_to_phase_log({
		"type": "TANK_SHOCK_RESULT",
		"player": player,
		"vehicle_unit_id": vehicle_unit_id,
		"vehicle_unit_name": vehicle_name,
		"target_unit_id": target_unit_id,
		"target_unit_name": target_name,
		"toughness": toughness,
		"dice_count": dice_count,
		"rolls": rolls,
		"mortal_wounds": mortal_wounds,
		"casualties": casualties
	})

	return {
		"success": true,
		"diffs": diffs,
		"dice_rolls": rolls,
		"mortal_wounds": mortal_wounds,
		"casualties": casualties,
		"toughness": toughness,
		"dice_count": dice_count,
		"message": "%s used TANK SHOCK on %s: rolled %dD6 (T%d) %s — %d mortal wound(s), %d casualt%s" % [
			vehicle_name, target_name, dice_count, toughness, str(rolls), mortal_wounds, casualties,
			"y" if casualties == 1 else "ies"
		]
	}

func is_fire_overwatch_available(player: int) -> Dictionary:
	"""
	Check if Fire Overwatch stratagem is available for a player.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "fire_overwatch")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

func get_fire_overwatch_eligible_units(player: int, enemy_unit_id: String, game_state_snapshot: Dictionary) -> Array:
	"""
	Get units eligible to Fire Overwatch for a given player against an enemy unit.
	Requirements (10e rules):
	  - Owned by player
	  - Within 24\" of the enemy unit
	  - Not battle-shocked
	  - Has alive models
	  - Eligible to shoot (has ranged weapons, not in engagement range)
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Check if the stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "fire_overwatch")
	if not validation.can_use:
		return eligible

	var all_units = game_state_snapshot.get("units", {})
	var enemy_unit = all_units.get(enemy_unit_id, {})
	if enemy_unit.is_empty():
		return eligible

	for unit_id in all_units:
		var unit = all_units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue

		# Must not be battle-shocked
		var flags = unit.get("flags", {})
		if flags.get("battle_shocked", false):
			continue

		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Must NOT already be in engagement range of any enemy unit (can't shoot while in melee)
		var in_engagement = false
		var unit_owner = int(unit.get("owner", 0))
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if int(other_unit.get("owner", 0)) == unit_owner:
				continue
			if _units_in_engagement_range(unit, other_unit):
				in_engagement = true
				break
		if in_engagement:
			continue

		# Must have at least one ranged weapon
		var has_ranged_weapon = _unit_has_ranged_weapons(unit)
		if not has_ranged_weapon:
			continue

		# Must be within 24" of the enemy unit
		var within_24 = _unit_within_distance_of_unit(unit, enemy_unit, 24.0)
		if not within_24:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func _unit_has_ranged_weapons(unit: Dictionary) -> bool:
	"""Check if a unit has any ranged weapons (non-melee)."""
	var weapons = unit.get("meta", {}).get("weapons", [])
	for weapon in weapons:
		var weapon_type = weapon.get("type", "").to_lower()
		# A weapon is ranged if it's not a melee weapon
		if weapon_type != "melee":
			return true
		# Also check the range field - if range > 0, it's ranged
		var weapon_range = weapon.get("range", "")
		if weapon_range is String and weapon_range != "" and weapon_range != "Melee":
			return true
		elif weapon_range is int and weapon_range > 0:
			return true
		elif weapon_range is float and weapon_range > 0.0:
			return true
	return false

func is_heroic_intervention_available(player: int) -> Dictionary:
	"""
	Check if Heroic Intervention stratagem is available for a player.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "heroic_intervention")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

func get_heroic_intervention_eligible_units(player: int, charging_enemy_unit_id: String, game_state_snapshot: Dictionary) -> Array:
	"""
	Get units eligible for Heroic Intervention for a given player after an enemy charge.
	Requirements:
	  - Owned by player
	  - Within 6" of the charging enemy unit
	  - Not already in engagement range of any enemy unit
	  - Not battle-shocked
	  - Has alive models
	  - Not a VEHICLE (unless it has WALKER keyword)
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Check if the stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "heroic_intervention")
	if not validation.can_use:
		return eligible

	var all_units = game_state_snapshot.get("units", {})
	var charging_unit = all_units.get(charging_enemy_unit_id, {})
	if charging_unit.is_empty():
		return eligible

	for unit_id in all_units:
		var unit = all_units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue

		# Must not be battle-shocked
		var flags = unit.get("flags", {})
		if flags.get("battle_shocked", false):
			continue

		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Check VEHICLE restriction: cannot select VEHICLE unless it has WALKER keyword
		var keywords = unit.get("meta", {}).get("keywords", [])
		var is_vehicle = false
		var is_walker = false
		for kw in keywords:
			var kw_upper = kw.to_upper()
			if kw_upper == "VEHICLE":
				is_vehicle = true
			if kw_upper == "WALKER":
				is_walker = true
		if is_vehicle and not is_walker:
			continue

		# Must NOT already be in engagement range of any enemy unit
		var in_engagement = false
		var unit_owner = int(unit.get("owner", 0))
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if int(other_unit.get("owner", 0)) == unit_owner:
				continue
			if _units_in_engagement_range(unit, other_unit):
				in_engagement = true
				break
		if in_engagement:
			continue

		# Must be within 6" of the charging enemy unit
		var within_6 = _unit_within_distance_of_unit(unit, charging_unit, 6.0)
		if not within_6:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func _unit_within_distance_of_unit(unit1: Dictionary, unit2: Dictionary, distance_inches: float) -> bool:
	"""Check if any model from unit1 is within the given distance (in inches) of any model from unit2."""
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])

	for model1 in models1:
		if not model1.get("alive", true):
			continue
		var pos1_data = model1.get("position", {})
		if pos1_data == null:
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue
			var pos2_data = model2.get("position", {})
			if pos2_data == null:
				continue

			var dist = Measurement.model_to_model_distance_inches(model1, model2)
			if dist <= distance_inches:
				return true

	return false

func get_reactive_stratagems_for_shooting(defending_player: int, target_unit_ids: Array) -> Array:
	"""
	Get reactive stratagems available to the defending player during opponent's shooting.
	Checks both Core stratagems (Go to Ground, Smokescreen) and faction stratagems
	that trigger on after_target_selected during opponent's shooting phase.
	Returns array of { stratagem: Dictionary, eligible_units: Array[String] }
	"""
	var results = []

	# Check Go to Ground (INFANTRY targets)
	var gtg_eligible_units = []
	for unit_id in target_unit_ids:
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			continue
		if unit.get("owner", 0) != defending_player:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		var has_infantry = false
		for kw in keywords:
			if kw.to_upper() == "INFANTRY":
				has_infantry = true
				break
		if has_infantry:
			gtg_eligible_units.append(unit_id)

	if not gtg_eligible_units.is_empty():
		var validation = can_use_stratagem(defending_player, "go_to_ground")
		if validation.can_use:
			results.append({
				"stratagem": stratagems["go_to_ground"],
				"eligible_units": gtg_eligible_units
			})

	# Check Smokescreen (SMOKE keyword targets)
	var smoke_eligible_units = []
	for unit_id in target_unit_ids:
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			continue
		if unit.get("owner", 0) != defending_player:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		var has_smoke = false
		for kw in keywords:
			if kw.to_upper() == "SMOKE":
				has_smoke = true
				break
		if has_smoke:
			smoke_eligible_units.append(unit_id)

	if not smoke_eligible_units.is_empty():
		var validation = can_use_stratagem(defending_player, "smokescreen")
		if validation.can_use:
			results.append({
				"stratagem": stratagems["smokescreen"],
				"eligible_units": smoke_eligible_units
			})

	# Check faction stratagems that trigger on after_target_selected in shooting phase
	results.append_array(_get_faction_reactive_stratagems(defending_player, target_unit_ids, "after_target_selected", "shooting"))

	return results

func _get_faction_reactive_stratagems(defending_player: int, target_unit_ids: Array, trigger: String, phase: String) -> Array:
	"""
	Get faction stratagems that trigger reactively when target units are attacked.
	Checks each faction stratagem's target conditions against the target units.
	Returns array of { stratagem: Dictionary, eligible_units: Array[String] }
	"""
	var results: Array = []

	for strat_id in _player_faction_stratagems.get(str(defending_player), []):
		if not stratagems.has(strat_id):
			continue
		var strat = stratagems[strat_id]

		# Must be implemented
		if not strat.get("implemented", false):
			continue

		# Must match trigger
		if strat.timing.get("trigger", "") != trigger:
			continue

		# Must be usable on opponent's turn
		if strat.timing.get("turn", "") != "opponent" and strat.timing.get("turn", "") != "either":
			continue

		# Must match phase (or be "any" or compound)
		var strat_phase = strat.timing.get("phase", "")
		if strat_phase != "any" and strat_phase != phase:
			if "_or_" in strat_phase:
				if phase not in strat_phase.split("_or_"):
					continue
			else:
				continue

		# Can we use this stratagem at all? (CP, restrictions)
		var validation = can_use_stratagem(defending_player, strat_id)
		if not validation.can_use:
			continue

		# Check which target units match this stratagem's target conditions
		var eligible_units: Array = []
		var target_conditions = strat.get("target", {})
		var context = {"is_target_of_attack": true}

		for unit_id in target_unit_ids:
			var unit = GameState.get_unit(unit_id)
			if unit.is_empty():
				continue
			if unit.get("owner", 0) != defending_player:
				continue

			if FactionStratagemLoaderData.unit_matches_target(unit, target_conditions, context):
				eligible_units.append(unit_id)

		if not eligible_units.is_empty():
			results.append({
				"stratagem": strat,
				"eligible_units": eligible_units
			})

	return results

func get_reactive_stratagems_for_fight(defending_player: int, target_unit_ids: Array) -> Array:
	"""
	Get reactive stratagems available to the defending player during fight phase.
	Checks both Core stratagems and faction stratagems that trigger on
	after_target_selected during fight phase.
	Returns array of { stratagem: Dictionary, eligible_units: Array[String] }
	"""
	var results = []

	# Check faction stratagems that trigger on after_target_selected in fight phase
	results.append_array(_get_faction_reactive_stratagems(defending_player, target_unit_ids, "after_target_selected", "fight"))

	# Also check for shooting_or_fight phase stratagems
	results.append_array(_get_faction_reactive_stratagems(defending_player, target_unit_ids, "after_target_selected", "shooting_or_fight"))

	return results

func get_proactive_stratagems_for_phase(player: int, phase: String, available_units: Array) -> Array:
	"""
	Get proactive faction stratagems a player can use during their active phase.
	Checks for stratagems like STORM OF FIRE (your shooting phase, shooter_selected)
	or UNBRIDLED CARNAGE (fight phase, fighter_selected).
	Returns array of { stratagem: Dictionary, eligible_units: Array[String] }
	"""
	var results: Array = []
	var trigger = ""

	match phase:
		"shooting":
			trigger = "shooter_selected"
		"fight":
			trigger = "fighter_selected"
		_:
			return results

	for strat_id in _player_faction_stratagems.get(str(player), []):
		if not stratagems.has(strat_id):
			continue
		var strat = stratagems[strat_id]

		if not strat.get("implemented", false):
			continue

		if strat.timing.get("trigger", "") != trigger:
			continue

		# Must be usable on your turn
		if strat.timing.get("turn", "") != "your" and strat.timing.get("turn", "") != "either":
			continue

		# Must match phase
		var strat_phase = strat.timing.get("phase", "")
		if strat_phase != "any" and strat_phase != phase:
			if "_or_" in strat_phase:
				if phase not in strat_phase.split("_or_"):
					continue
			else:
				continue

		var validation = can_use_stratagem(player, strat_id)
		if not validation.can_use:
			continue

		# Check which units match target conditions
		var eligible_units: Array = []
		var target_conditions = strat.get("target", {})

		for unit_id in available_units:
			var unit = GameState.get_unit(unit_id)
			if unit.is_empty():
				continue
			if unit.get("owner", 0) != player:
				continue
			if FactionStratagemLoaderData.unit_matches_target(unit, target_conditions):
				eligible_units.append(unit_id)

		if not eligible_units.is_empty():
			results.append({
				"stratagem": strat,
				"eligible_units": eligible_units
			})

	return results

# ============================================================================
# FIRE OVERWATCH — Execution
# ============================================================================

# Alias for backward-compatibility with tests that use the shorter name
func get_overwatch_eligible_units(player: int, enemy_unit_id: String, game_state_snapshot: Dictionary) -> Array:
	return get_fire_overwatch_eligible_units(player, enemy_unit_id, game_state_snapshot)

func execute_fire_overwatch(player: int, shooter_unit_id: String, target_unit_id: String, game_state_snapshot: Dictionary) -> Dictionary:
	"""
	Execute the Fire Overwatch stratagem: shooting at the target with hit-on-6-only.
	Handles CP deduction, usage tracking, overwatch shooting resolution.
	Returns { success: bool, diffs: Array, shooting_result: Dictionary, message: String }
	"""
	var validation = can_use_stratagem(player, "fire_overwatch", shooter_unit_id)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": [], "shooting_result": {}}

	# Use the standard use_stratagem flow for CP deduction and usage tracking
	var result = use_stratagem(player, "fire_overwatch", shooter_unit_id)
	if not result.success:
		return {"success": false, "error": result.get("error", "Failed"), "diffs": [], "shooting_result": {}}

	var shooter_unit = GameState.get_unit(shooter_unit_id)
	var shooter_name = shooter_unit.get("meta", {}).get("name", shooter_unit_id)
	var target_unit = GameState.get_unit(target_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

	print("StratagemManager: FIRE OVERWATCH — %s (player %d) fires at %s" % [shooter_name, player, target_name])

	# Build an action for RulesEngine.resolve_overwatch_shooting()
	var board = GameState.create_snapshot()
	var rng = RulesEngine.RNGService.new()
	var shooting_result = RulesEngine.resolve_overwatch_shooting(shooter_unit_id, target_unit_id, board, rng)

	# Apply the diffs from shooting
	var shooting_diffs = shooting_result.get("diffs", [])
	if not shooting_diffs.is_empty():
		_safe_apply_state_changes(shooting_diffs)

	# Log the overwatch to phase log
	GameState.add_action_to_phase_log({
		"type": "FIRE_OVERWATCH",
		"player": player,
		"shooter_unit_id": shooter_unit_id,
		"shooter_unit_name": shooter_name,
		"target_unit_id": target_unit_id,
		"target_unit_name": target_name,
		"hits": shooting_result.get("total_hits", 0),
		"wounds": shooting_result.get("total_wounds", 0),
		"damage": shooting_result.get("total_damage", 0),
		"casualties": shooting_result.get("total_casualties", 0),
		"turn": GameState.get_battle_round()
	})

	return {
		"success": true,
		"diffs": shooting_diffs,
		"shooting_result": shooting_result,
		"message": "FIRE OVERWATCH: %s shot at %s — %d hit(s), %d wound(s), %d damage, %d casualt%s" % [
			shooter_name, target_name,
			shooting_result.get("total_hits", 0),
			shooting_result.get("total_wounds", 0),
			shooting_result.get("total_damage", 0),
			shooting_result.get("total_casualties", 0),
			"y" if shooting_result.get("total_casualties", 0) == 1 else "ies"
		]
	}

func _is_within_range(unit1: Dictionary, unit2: Dictionary, range_inches: float) -> bool:
	"""Check if any alive model from unit1 is within range_inches of any alive model from unit2."""
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])

	for model1 in models1:
		if not model1.get("alive", true):
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue

			var distance = Measurement.model_to_model_distance_inches(model1, model2)
			if distance <= range_inches:
				return true

	return false

func _is_unit_in_engagement_range(unit: Dictionary, all_units: Dictionary, owner: int) -> bool:
	"""Check if any model in unit is within engagement range (1\") of any enemy model."""
	var models = unit.get("models", [])

	for model in models:
		if not model.get("alive", true):
			continue

		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if int(other_unit.get("owner", 0)) == owner:
				continue  # Skip friendly units

			for other_model in other_unit.get("models", []):
				if not other_model.get("alive", true):
					continue

				if Measurement.is_in_engagement_range_shape_aware(model, other_model, 1.0):
					return true

	return false

# ============================================================================
# HELPERS
# ============================================================================

func _get_player_cp(player: int) -> int:
	return GameState.state.get("players", {}).get(str(player), {}).get("cp", 0)

func _phase_to_string(phase: int) -> String:
	match phase:
		GameStateData.Phase.DEPLOYMENT: return "deployment"
		GameStateData.Phase.ROLL_OFF: return "roll_off"
		GameStateData.Phase.COMMAND: return "command"
		GameStateData.Phase.MOVEMENT: return "movement"
		GameStateData.Phase.SHOOTING: return "shooting"
		GameStateData.Phase.CHARGE: return "charge"
		GameStateData.Phase.FIGHT: return "fight"
		GameStateData.Phase.SCORING: return "scoring"
		GameStateData.Phase.MORALE: return "morale"
		_: return "unknown"

func reset_for_new_game() -> void:
	"""Reset all tracking for a new game."""
	_usage_history = {"1": [], "2": []}
	active_effects.clear()
	# Clear faction stratagems (they'll be reloaded when armies are set up)
	_clear_player_faction_stratagems(1)
	_clear_player_faction_stratagems(2)
	print("StratagemManager: Reset for new game")

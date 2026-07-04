extends Node

const SecondaryMissionData = preload("res://scripts/data/SecondaryMissionData.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

# SecondaryMissionManager - Manages the secondary mission system for Chapter Approved 2025-26
# Handles deck building, card drawing, discarding, scoring, and VP tracking
# Supports both Tactical Missions mode (draw from deck) and Fixed Missions mode
# (select 2 missions before game, they remain active and can score multiple times).

signal mission_drawn(player: int, mission_id: String)
signal mission_achieved(player: int, mission_id: String, vp_earned: int)
signal mission_discarded(player: int, mission_id: String, reason: String)
signal secondary_vp_scored(player: int, vp: int, mission_id: String)
signal deck_depleted(player: int)
signal when_drawn_requires_interaction(player: int, mission_id: String, interaction_type: String, details: Dictionary)
signal missions_drawn_for_review(player: int, drawn_missions: Array)

# VP caps per Chapter Approved 2025-26
const MAX_SECONDARY_VP = 40
const MAX_COMBINED_VP = 90  # primary + secondary + challenger combined
const MAX_ACTIVE_MISSIONS = 2
# 11e (GDM 2026): 45 VP secondary total, 15 VP per turn, no hand limit
# (source: docs/rules/11th_edition_missions_gdm2026.md).
const MAX_SECONDARY_VP_11E = 45
const MAX_SECONDARY_VP_PER_TURN_11E = 15
const MAX_VP_PER_FIXED_CARD_11E = 20  # GDM sourced: 20 VP max from each fixed card per game
const CARDS_DRAWN_PER_TURN_11E = 2
const MAX_FIXED_MISSION_VP = 20  # Max VP per individual fixed mission card
# 11e official: a tactical secondary card scores at most 5 VP per scoring
# (fixed-mode cards use their printed per-award caps instead).
const MAX_VP_PER_TACTICAL_SCORING_11E = 5

# Per-player secondary mission state
var _player_state: Dictionary = {
	"1": _create_default_player_state(),
	"2": _create_default_player_state(),
}

# Tracks units destroyed this turn for kill-based missions
var _units_destroyed_this_turn: Array = []

# Tracks objective control at start of turn for objective-based missions
var _objective_control_at_turn_start: Dictionary = {}

# Tracks actions being performed for action-based missions
var _active_actions: Dictionary = {
	"1": [],  # Array of ongoing action dicts
	"2": [],
}

# Track "while_active" VP accumulated per card this scoring window
var _while_active_vp_this_window: Dictionary = {}

var _rng: RandomNumberGenerator

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	print("SecondaryMissionManager: Initialized")

static func _create_default_player_state() -> Dictionary:
	return {
		"mode": "tactical",  # "tactical" or "fixed"
		"deck": [],          # Array of mission IDs (shuffled for tactical)
		"active": [],        # Array of active mission dicts (max 2)
		"discard": [],       # Array of discarded mission IDs
		"secondary_vp": 0,   # Total secondary VP scored
		"secondary_vp_this_turn": 0,  # 11e: 15/turn cap window
		"vp_by_mission": {},  # 11e fixed mode: 20 VP cap per fixed card
		"initialized": false,
	}

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize_for_game() -> void:
	"""Initialize secondary missions for both players at game start."""
	_player_state = {
		"1": _create_default_player_state(),
		"2": _create_default_player_state(),
	}
	_units_destroyed_this_turn.clear()
	_objective_control_at_turn_start.clear()
	_active_actions = {"1": [], "2": []}
	_while_active_vp_this_window.clear()
	print("SecondaryMissionManager: Reset for new game")

func setup_tactical_deck(player: int) -> void:
	"""Build and shuffle a tactical mission deck for the specified player."""
	var player_key = str(player)
	var state = _player_state[player_key]

	# Get the edition's 18-card tactical deck (11e: GDM 2026 deck)
	var deck_ids = SecondaryMissionData.get_mission_ids_for_deck_11e() \
		if GameConstants.edition >= 11 else SecondaryMissionData.get_mission_ids_for_deck(false)

	# T16-1: For AI players, filter out missions the army literally cannot score
	# This prevents the AI from wasting CP and turns cycling through impossible missions
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		var removed = _filter_unachievable_missions_for_ai(deck_ids, player)
		if removed > 0:
			print("SecondaryMissionManager: [AI-DECK] Filtered %d unachievable missions from Player %d deck (%d remaining)" % [removed, player, deck_ids.size()])

	# Shuffle
	_shuffle_array(deck_ids)

	state["deck"] = deck_ids
	state["mode"] = "tactical"
	state["active"] = []
	state["discard"] = []
	state["secondary_vp"] = 0
	state["initialized"] = true

	print("SecondaryMissionManager: Built tactical deck for Player %d (%d cards)" % [player, deck_ids.size()])

func setup_fixed_missions(player: int, mission_ids: Array) -> Dictionary:
	"""Set up fixed secondary missions for a player. Fixed missions stay active
	the entire game and can be scored multiple times (up to 20VP per mission).
	mission_ids: Array of exactly 2 mission ID strings."""
	# 11e (GDM 2026): only the four fixed-eligible cards may be taken as
	# Fixed — Assassination, A Grievous Blow, Bring it Down, Engage on
	# All Fronts.
	if GameConstants.edition >= 11:
		var eligible = SecondaryMissionData.get_fixed_eligible_11e()
		for mid in mission_ids:
			if not str(mid) in eligible:
				return {"success": false, "error": "%s is not fixed-eligible in 11e (choose from %s)" % [str(mid), str(eligible)]}
	if mission_ids.size() != 2:
		return {"success": false, "error": "Must select exactly 2 fixed missions (got %d)" % mission_ids.size()}

	# Validate mission IDs
	for mid in mission_ids:
		var mission_data = SecondaryMissionData.get_mission_by_id(mid)
		if mission_data.is_empty():
			return {"success": false, "error": "Unknown mission ID: %s" % mid}

	# Check for duplicates
	if mission_ids[0] == mission_ids[1]:
		return {"success": false, "error": "Cannot select the same mission twice"}

	var player_key = str(player)
	var state = _player_state[player_key]

	# Create active missions from the selected IDs
	state["active"] = []
	for mid in mission_ids:
		var mission_data = SecondaryMissionData.get_mission_by_id(mid)
		var active_mission = _create_active_mission(mission_data)
		state["active"].append(active_mission)
		emit_signal("mission_drawn", player, mid)

	state["deck"] = []  # No deck in fixed mode
	state["discard"] = []
	state["mode"] = "fixed"
	state["secondary_vp"] = 0
	state["initialized"] = true

	print("SecondaryMissionManager: Set up fixed missions for Player %d: %s, %s" % [
		player, state["active"][0]["name"], state["active"][1]["name"]])

	return {"success": true}

func is_fixed_mode(player: int) -> bool:
	"""Check if player is using fixed secondary missions mode."""
	return _player_state[str(player)].get("mode", "tactical") == "fixed"

func get_mode(player: int) -> String:
	"""Get the secondary mission mode for a player ('tactical' or 'fixed')."""
	return _player_state[str(player)].get("mode", "tactical")

func _filter_unachievable_missions_for_ai(deck_ids: Array, player: int) -> int:
	"""T16-1: Remove missions from deck that the player's army literally cannot score.
	Returns the number of removed missions."""
	var removed_count = 0

	# No missions are automatically removed — difficulty alone is not a reason to filter.
	# The AI should use its evaluation logic (_assess_* functions) to decide whether to
	# keep or discard missions during gameplay, not pre-filter them from the deck.
	return removed_count

# ============================================================================
# CARD DRAWING
# ============================================================================

func draw_missions_to_hand(player: int, draw_count: int = 0) -> Array:
	"""
	Draw secondary mission cards for the player.
	draw_count = 0: the normal turn draw — 11e draws exactly
	CARDS_DRAWN_PER_TURN_11E cards (no hand limit); 10e fills the hand up to
	MAX_ACTIVE_MISSIONS. Called at the start of Command Phase.
	draw_count > 0: draw exactly that many cards regardless of the turn-draw
	rules — used by 1-for-1 swaps (replace_drawn_mission, New Orders), which
	previously drew a full 11e turn draw (2 cards) for a single discard and
	inflated the hand.
	Returns array of newly drawn mission dicts.
	"""
	var player_key = str(player)
	var state = _player_state[player_key]

	if not state["initialized"]:
		push_warning("SecondaryMissionManager: Player %d deck not initialized" % player)
		return []

	var drawn = []
	# 11e (GDM 2026): draw TWO cards each turn with NO hand limit;
	# 10e: fill the hand up to MAX_ACTIVE_MISSIONS.
	var draws_remaining_11e := CARDS_DRAWN_PER_TURN_11E if draw_count <= 0 else draw_count
	while ((draw_count > 0 and draws_remaining_11e > 0)
			or (draw_count <= 0 and GameConstants.edition >= 11 and draws_remaining_11e > 0)
			or (draw_count <= 0 and GameConstants.edition < 11 and state["active"].size() < MAX_ACTIVE_MISSIONS)) \
			and state["deck"].size() > 0:
		var mission_id = state["deck"].pop_front()
		var mission_data = SecondaryMissionData.get_mission_by_id(mission_id)

		if mission_data.is_empty():
			push_warning("SecondaryMissionManager: Unknown mission ID in deck: %s" % mission_id)
			continue

		# Check "When Drawn" conditions
		var when_drawn_result = _handle_when_drawn(player, mission_data)

		if when_drawn_result["action"] == "shuffle_back":
			# Put it back in the deck and shuffle
			state["deck"].append(mission_id)
			_shuffle_array(state["deck"])
			print("SecondaryMissionManager: Player %d shuffled %s back into deck" % [player, mission_data["name"]])
			# Draw another card instead
			continue
		elif when_drawn_result["action"] == "discard_and_draw":
			# Discard it and draw a new one
			state["discard"].append(mission_id)
			print("SecondaryMissionManager: Player %d discarded %s (when drawn condition)" % [player, mission_data["name"]])
			emit_signal("mission_discarded", player, mission_id, "when_drawn_condition")
			continue
		elif when_drawn_result["action"] == "requires_interaction":
			# Card needs opponent interaction before it can be fully activated
			# Add to active but mark as pending interaction
			var active_mission = _create_active_mission(mission_data)
			active_mission["pending_interaction"] = true
			active_mission["interaction_type"] = when_drawn_result.get("interaction_type", "")
			active_mission["interaction_details"] = when_drawn_result.get("details", {})
			state["active"].append(active_mission)
			drawn.append(active_mission)
			emit_signal("mission_drawn", player, mission_id)
			emit_signal("when_drawn_requires_interaction", player, mission_id,
				active_mission["interaction_type"], active_mission["interaction_details"])
			print("SecondaryMissionManager: Player %d drew %s (requires interaction)" % [player, mission_data["name"]])
			draws_remaining_11e -= 1
			continue

		# Normal draw - add to active missions
		var active_mission = _create_active_mission(mission_data)
		state["active"].append(active_mission)
		drawn.append(active_mission)
		draws_remaining_11e -= 1
		emit_signal("mission_drawn", player, mission_id)
		print("SecondaryMissionManager: Player %d drew %s" % [player, mission_data["name"]])

	if state["deck"].size() == 0 and state["active"].size() < MAX_ACTIVE_MISSIONS:
		emit_signal("deck_depleted", player)
		print("SecondaryMissionManager: Player %d deck is depleted!" % player)

	return drawn

func _handle_when_drawn(player: int, mission_data: Dictionary) -> Dictionary:
	"""Process when-drawn conditions. Returns action to take.
	The when-drawn block is edition-resolved: cards shared between editions
	may carry an 11e-specific override under "when_drawn_11e"."""
	var when_drawn = SecondaryMissionData.get_when_drawn(mission_data)
	if when_drawn.is_empty():
		return {"action": "add_to_active"}

	var condition = when_drawn.get("condition", "")
	var effect = when_drawn.get("effect", "")
	var battle_round = GameState.get_battle_round()

	match condition:
		"first_battle_round":
			if battle_round == 1:
				if effect == SecondaryMissionData.EFFECT_MANDATORY_SHUFFLE_BACK:
					return {"action": "shuffle_back"}
				elif effect == SecondaryMissionData.EFFECT_SHUFFLE_BACK:
					# Optional shuffle back - for now, auto-shuffle back in round 1
					# TODO: Could add UI choice here
					return {"action": "shuffle_back"}
			return {"action": "add_to_active"}

		"no_enemy_infantry_starting_strength_13_plus":
			if not _has_enemy_infantry_13_plus(player):
				return {"action": "discard_and_draw"}
			return {"action": "add_to_active"}

		"no_enemy_monster_or_vehicle":
			if not _has_enemy_monster_or_vehicle(player):
				return {"action": "discard_and_draw"}
			return {"action": "add_to_active"}

		"fewer_than_3_units_or_incursion":
			if _count_player_units_on_battlefield(player) < 3:
				return {"action": "discard_and_draw"}
			return {"action": "add_to_active"}

		"opponent_selects_units":
			# Marked for Death - needs opponent interaction
			var opponent = 2 if player == 1 else 1
			var opponent_units = _get_opponent_units_on_battlefield(player)
			if opponent_units.size() == 0:
				return {"action": "discard_and_draw"}
			return {
				"action": "requires_interaction",
				"interaction_type": "opponent_selects_units",
				"details": when_drawn.get("details", {}),
			}

		"opponent_selects_objective":
			# A Tempting Target - opponent picks an objective in NML
			# Check that NML objectives actually exist before requiring interaction
			var nml_objectives = _get_no_mans_land_objectives()
			if nml_objectives.is_empty():
				print("SecondaryMissionManager: No NML objectives for A Tempting Target — discarding and drawing again")
				return {"action": "discard_and_draw"}
			return {
				"action": "requires_interaction",
				"interaction_type": "opponent_selects_objective",
				"details": when_drawn.get("details", {}),
			}

		"no_enemy_model_wounds_10_plus":
			# 11e Bring it Down: replace (discard and redraw) if the opponent
			# has no unit containing a model with W10+ on the battlefield.
			var min_wounds = int(when_drawn.get("details", {}).get("min_wounds", 10))
			if not _has_enemy_model_with_wounds(player, min_wounds):
				return {"action": "discard_and_draw"}
			return {"action": "add_to_active"}

		"no_enemy_unit_13_plus_models":
			# 11e A Grievous Blow: replace (discard and redraw) if the opponent
			# has no unit with a Starting Strength of min_models+ models.
			var min_models = int(when_drawn.get("details", {}).get("min_models", 13))
			if not _has_enemy_unit_with_models(player, min_models):
				return {"action": "discard_and_draw"}
			return {"action": "add_to_active"}

		"other_mission_active":
			# 11e Plunder/Cleanse mutual redraw: if the named mission is
			# already active for this player, shuffle this card back in and
			# draw again.
			var other_id = str(when_drawn.get("details", {}).get("mission_id", ""))
			if other_id != "":
				for m in _player_state[str(player)]["active"]:
					if m.get("id", "") == other_id:
						print("SecondaryMissionManager: Player %d has %s active — shuffling %s back (mutual redraw)" % [player, other_id, mission_data.get("id", "?")])
						return {"action": "shuffle_back"}
			return {"action": "add_to_active"}

	return {"action": "add_to_active"}

func _create_active_mission(mission_data: Dictionary) -> Dictionary:
	"""Create an active mission instance from mission data. The scoring block
	is edition-resolved (shared cards carry official 11e awards under
	"scoring_11e")."""
	return {
		"id": mission_data["id"],
		"name": mission_data["name"],
		"number": mission_data["number"],
		"category": mission_data["category"],
		"scoring": SecondaryMissionData.get_scoring(mission_data),
		"requires_action": mission_data["requires_action"],
		"action": mission_data["action"],
		"vp_scored": 0,  # VP scored from this specific card instance
		"achieved": false,
		"pending_interaction": false,
		"interaction_type": "",
		"interaction_details": {},
		# Mission-specific tracking
		"mission_data": {},  # e.g., alpha/gamma targets for Marked for Death
	}

# ============================================================================
# NEW ORDERS STRATAGEM
# ============================================================================

func use_new_orders(player: int, mission_index: int) -> Dictionary:
	"""
	Discard one active mission and draw a new one (New Orders stratagem).
	CP deduction is handled by StratagemManager (called by CommandPhase before this).
	mission_index: 0 or 1 (which active mission to discard)
	Not available in Fixed mission mode.
	Returns result dict.
	"""
	var player_key = str(player)
	var state = _player_state[player_key]

	# Fixed missions cannot be swapped with New Orders
	if state.get("mode", "tactical") == "fixed":
		return {"success": false, "error": "New Orders is not available in Fixed mission mode"}

	if mission_index < 0 or mission_index >= state["active"].size():
		return {"success": false, "error": "Invalid mission index"}

	if state["deck"].size() == 0:
		return {"success": false, "error": "Deck is empty, cannot draw replacement"}

	# Discard the selected mission
	var discarded = state["active"][mission_index]
	state["active"].remove_at(mission_index)
	state["discard"].append(discarded["id"])
	emit_signal("mission_discarded", player, discarded["id"], "new_orders")
	print("SecondaryMissionManager: Player %d used New Orders to discard %s" % [player, discarded["name"]])

	# Draw a replacement
	# New Orders is a 1-for-1 swap — draw exactly one card.
	var drawn = draw_missions_to_hand(player, 1)

	return {
		"success": true,
		"discarded": discarded["name"],
		"drawn": drawn[0]["name"] if drawn.size() > 0 else "none (deck depleted)",
	}

# ============================================================================
# REPLACE DRAWN MISSION (spend 1 CP to swap a newly drawn mission)
# ============================================================================

func replace_drawn_mission(player: int, mission_index: int) -> Dictionary:
	"""
	Replace one active mission by putting it back into the deck and drawing a new one.
	Costs 1 CP (CP deduction handled by caller).
	The replaced mission goes back into the deck (shuffled in), not the discard pile.
	Not available in Fixed mission mode.
	Returns result dict with success status, replaced mission name, and new mission name.
	"""
	var player_key = str(player)
	var state = _player_state[player_key]

	# Fixed missions cannot be replaced
	if state.get("mode", "tactical") == "fixed":
		return {"success": false, "error": "Mission replacement is not available in Fixed mission mode"}

	if mission_index < 0 or mission_index >= state["active"].size():
		return {"success": false, "error": "Invalid mission index"}

	if state["deck"].size() == 0:
		return {"success": false, "error": "Deck is empty, cannot draw replacement"}

	# Remove the selected mission from active
	var replaced = state["active"][mission_index]
	state["active"].remove_at(mission_index)
	var replaced_id = replaced["id"]

	emit_signal("mission_discarded", player, replaced_id, "replaced_back_to_deck")
	print("SecondaryMissionManager: Player %d put %s back into deck" % [player, replaced["name"]])

	# Shuffle the deck WITHOUT the replaced card first, then draw.
	# This guarantees the replacement cannot be the same mission.
	# After drawing, we insert the replaced card back and re-shuffle.
	_shuffle_array(state["deck"])

	# Draw exactly ONE replacement (replaced card is NOT in the deck yet).
	# A plain turn-draw here would deal 2 cards at 11e and inflate the hand.
	var drawn = draw_missions_to_hand(player, 1)

	# Now put the replaced card back into the deck and shuffle
	state["deck"].append(replaced_id)
	_shuffle_array(state["deck"])
	print("SecondaryMissionManager: Player %d — %s returned to deck after drawing replacement" % [player, replaced["name"]])

	return {
		"success": true,
		"replaced": replaced["name"],
		"replaced_id": replaced_id,
		"drawn": drawn[0]["name"] if drawn.size() > 0 else "none (deck depleted)",
		"drawn_mission": drawn[0] if drawn.size() > 0 else {},
	}

# ============================================================================
# VOLUNTARY DISCARD
# ============================================================================

func voluntary_discard(player: int, mission_index: int) -> Dictionary:
	"""
	Voluntarily discard an active mission at end of turn.
	If it's the player's turn, they gain 1 CP.
	Not available in Fixed mission mode.
	"""
	var player_key = str(player)
	var state = _player_state[player_key]

	# Fixed missions cannot be voluntarily discarded
	if state.get("mode", "tactical") == "fixed":
		return {"success": false, "error": "Fixed missions cannot be discarded"}

	if mission_index < 0 or mission_index >= state["active"].size():
		return {"success": false, "error": "Invalid mission index"}

	var discarded = state["active"][mission_index]
	state["active"].remove_at(mission_index)
	state["discard"].append(discarded["id"])

	# Clear visual indicators if this was A Tempting Target or Marked for Death
	if discarded["id"] == "a_tempting_target":
		var target_id = discarded.get("mission_data", {}).get("tempting_target_id", "")
		if target_id != "":
			_clear_tempting_target_visual(target_id)
	elif discarded["id"] == "marked_for_death":
		var mfd_data = discarded.get("mission_data", {})
		_clear_mfd_target_visuals(mfd_data.get("alpha_targets", []), mfd_data.get("gamma_target", ""))

	# Grant 1 CP if it's the player's turn (subject to bonus CP cap per battle round)
	var cp_gained = 0
	if GameState.get_active_player() == player:
		if GameState.can_gain_bonus_cp(player):
			var current_cp = GameState.state.get("players", {}).get(str(player), {}).get("cp", 0)
			var changes = [{
				"op": "set",
				"path": "players.%s.cp" % str(player),
				"value": current_cp + 1,
			}]
			PhaseManager.apply_state_changes(changes)
			GameState.record_bonus_cp_gained(player)
			cp_gained = 1
			print("SecondaryMissionManager: Player %d gained 1 CP for voluntary discard" % player)
		else:
			print("SecondaryMissionManager: Player %d CP gain blocked — bonus CP cap reached this battle round" % player)

	emit_signal("mission_discarded", player, discarded["id"], "voluntary")
	print("SecondaryMissionManager: Player %d voluntarily discarded %s" % [player, discarded["name"]])

	return {
		"success": true,
		"discarded": discarded["name"],
		"cp_gained": cp_gained,
	}

# ============================================================================
# SCORING
# ============================================================================

func score_secondary_missions_for_player(player: int) -> Array:
	"""
	Evaluate and score all active secondary missions for a player.
	Called at end of player's turn (for end_of_your_turn missions)
	or at end of either player's turn (for end_of_either_turn missions).
	Returns array of scoring results.
	"""
	var player_key = str(player)
	var state = _player_state[player_key]
	var results = []
	var active_player = GameState.get_active_player()
	var battle_round = GameState.get_battle_round()

	for i in range(state["active"].size() - 1, -1, -1):
		var mission = state["active"][i]

		# Skip missions pending interaction
		if mission.get("pending_interaction", false):
			continue

		var scoring = mission["scoring"]
		var when = scoring.get("when", "")

		# Check timing
		var should_score = false
		match when:
			SecondaryMissionData.TIMING_END_OF_YOUR_TURN:
				should_score = (active_player == player)
			SecondaryMissionData.TIMING_END_OF_EITHER_TURN:
				should_score = true
			SecondaryMissionData.TIMING_END_OF_OPPONENT_TURN:
				should_score = (active_player != player)
			SecondaryMissionData.TIMING_WHILE_ACTIVE:
				# While-active missions are scored via events (unit destruction etc.)
				# At end of turn we just finalize the accumulated VP
				should_score = false

		if not should_score:
			continue

		# Check min round
		if battle_round < scoring.get("min_round", 1):
			continue

		# Evaluate conditions (highest matching VP wins)
		var vp_earned = _evaluate_mission_conditions(player, mission)

		if vp_earned > 0:
			# In fixed mode, cap VP per individual mission card at MAX_FIXED_MISSION_VP
			if state.get("mode", "tactical") == "fixed":
				var mission_remaining = MAX_FIXED_MISSION_VP - mission["vp_scored"]
				if mission_remaining <= 0:
					print("SecondaryMissionManager: Player %d fixed mission %s already at %dVP cap" % [player, mission["name"], MAX_FIXED_MISSION_VP])
					continue
				vp_earned = mini(vp_earned, mission_remaining)

			var actual_vp = _award_secondary_vp(player, vp_earned, mission["id"])
			if actual_vp > 0:
				mission["vp_scored"] += actual_vp
				# In tactical mode, mark as achieved for discard; in fixed mode, keep active
				if state.get("mode", "tactical") != "fixed":
					mission["achieved"] = true
				results.append({
					"mission_id": mission["id"],
					"mission_name": mission["name"],
					"vp_earned": actual_vp,
				})
				emit_signal("secondary_vp_scored", player, actual_vp, mission["id"])
				emit_signal("mission_achieved", player, mission["id"], actual_vp)
				print("SecondaryMissionManager: Player %d scored %d VP from %s" % [player, actual_vp, mission["name"]])

	# Discard achieved missions (only in tactical mode — fixed missions stay active)
	if state.get("mode", "tactical") != "fixed":
		_discard_achieved_missions(player)

	return results

func _evaluate_mission_conditions(player: int, mission: Dictionary) -> int:
	"""
	Evaluate the scoring conditions for a mission and return the VP to award.

	Official 11e award semantics (also backwards-compatible with 10e data):
	- "mode": "fixed"|"tactical" — the condition only applies when the player
	  is using that secondary-mission approach; mode-less applies to both.
	- "timing": "your_turn"|"opponent_turn" — per-condition turn restriction
	  (used by cards whose awards differ by whose turn is ending).
	- "min_round": per-condition battle-round gate.
	- Non-cumulative conditions compete: the highest value wins (this covers
	  the dataset's exclusive_group tiers). "cumulative": true conditions add
	  on top of the exclusive winner.
	- "per_count": true conditions score vp * count (count via
	  _count_condition), clamped to "vp_max" when present.
	- 11e tactical mode: a card scores at most 5 VP per scoring.
	"""
	var scoring = mission["scoring"]
	var conditions = scoring.get("conditions", [])
	var player_mode = _player_state[str(player)].get("mode", "tactical")
	var is_your_turn = (GameState.get_active_player() == player)
	var battle_round = GameState.get_battle_round()
	var mission_name = mission.get("name", mission.get("id", "unknown"))

	var best_exclusive := 0
	var cumulative_total := 0

	for condition in conditions:
		var check = condition.get("check", "")
		var cond_mode = str(condition.get("mode", ""))
		if cond_mode != "" and cond_mode != player_mode:
			continue
		var cond_timing = str(condition.get("timing", ""))
		if cond_timing == "your_turn" and not is_your_turn:
			continue
		if cond_timing == "opponent_turn" and is_your_turn:
			continue
		if battle_round < int(condition.get("min_round", 1)):
			continue

		var value = _evaluate_condition_value(player, condition, mission)
		if value > 0:
			print("SecondaryMissionManager: [SCORING] P%d '%s' condition '%s' PASSED — worth %d VP%s" % [
				player, mission_name, check, value, " (cumulative)" if condition.get("cumulative", false) else ""])
		else:
			print("SecondaryMissionManager: [SCORING] P%d '%s' condition '%s' FAILED (would give up to %d VP)" % [
				player, mission_name, check, condition.get("vp", 0)])

		if condition.get("cumulative", false):
			cumulative_total += value
		else:
			best_exclusive = maxi(best_exclusive, value)

	var total = best_exclusive + cumulative_total

	# 11e: tactical cards are capped at 5 VP per scoring (they score once and
	# are then discarded); fixed cards use their printed award caps.
	if total > 0 and GameConstants.edition >= 11 and player_mode == "tactical" \
			and total > MAX_VP_PER_TACTICAL_SCORING_11E:
		print("SecondaryMissionManager: [SCORING] P%d '%s' clipped from %d to %d VP (11e tactical per-scoring cap)" % [
			player, mission_name, total, MAX_VP_PER_TACTICAL_SCORING_11E])
		total = MAX_VP_PER_TACTICAL_SCORING_11E

	return total

func _evaluate_condition_value(player: int, condition: Dictionary, mission: Dictionary) -> int:
	"""Compute the VP value of a single condition: flat vp for boolean checks,
	vp * count (clamped to vp_max) for per_count checks."""
	var check = condition.get("check", "")
	var params = condition.get("params", {})
	var vp = int(condition.get("vp", 0))

	if condition.get("per_count", false):
		var count = _count_condition(player, check, params, mission)
		var value = vp * count
		var vp_max = int(condition.get("vp_max", 0))
		if vp_max > 0:
			value = mini(value, vp_max)
		return value

	return vp if _check_condition(player, check, params, mission) else 0

func _check_condition(player: int, check: String, params: Dictionary, mission: Dictionary) -> bool:
	"""Route to the appropriate condition checker."""
	match check:
		# Positional checks
		"units_wholly_in_opponent_deployment_zone":
			return _check_units_in_opponent_zone(player, params)
		"presence_in_table_quarters":
			return _check_table_quarter_presence(player, params)
		"units_within_center_no_enemies_within":
			return _check_area_denial(player, params)
		"more_units_wholly_in_no_mans_land_than_opponent":
			return _check_display_of_might(player, params)

		# Objective control checks
		"control_objectives_opponent_controlled_at_start":
			return _check_storm_hostile_objective(player, params)
		"opponent_controlled_no_objectives_at_start_and_you_control_new":
			return _check_storm_hostile_alt(player, params)
		"control_objectives_in_own_deployment_zone":
			return _check_own_zone_objectives(player, params)
		"control_objectives_in_no_mans_land":
			return _check_nml_objectives(player, params)
		"control_tempting_target":
			return _check_tempting_target(player, mission)
		"control_own_zone_and_nml_objectives":
			return _check_extend_battle_lines(player, params)

		# Kill-based checks
		"character_models_destroyed_this_turn":
			return _check_characters_destroyed_this_turn(player, params)
		"all_enemy_characters_destroyed":
			return _check_all_enemy_characters_destroyed(player)
		"enemy_unit_destroyed":
			return _check_enemy_unit_destroyed_this_turn(player)
		"infantry_starting_strength_13_plus_destroyed_this_turn":
			return _check_infantry_horde_destroyed(player, params)
		"monster_or_vehicle_destroyed_this_turn":
			return _check_monster_vehicle_destroyed(player, params)
		"alpha_target_destroyed_this_turn":
			return _check_alpha_target_destroyed(player, mission, params)
		"no_alpha_destroyed_but_gamma_destroyed_this_turn":
			return _check_gamma_target_destroyed(player, mission)
		"enemy_unit_destroyed_within_objective_range":
			return _check_overwhelming_force(player)

		# Action-based checks
		"locus_established_within_center":
			return _check_locus_center(player, params)
		"locus_established_in_opponent_deployment_zone":
			return _check_locus_opponent_zone(player)
		"objectives_cleansed":
			return _check_objectives_cleansed(player, params)
		"teleport_homer_deployed_not_in_opponent_zone":
			return _check_teleport_homer(player, false, params)
		"teleport_homer_deployed_in_opponent_zone":
			return _check_teleport_homer(player, true, params)

		# 11e (GDM 2026) deck checks
		"high_value_unit_destroyed_this_turn":
			return _check_high_value_unit_destroyed(player, params)
		"holds_enemy_home_objective":
			return _check_enemy_home_objective(player)
		"objectives_held_since_turn_start":
			return _check_objectives_held_since_turn_start(player, params)
		"units_near_board_edges":
			return _check_units_near_board_edges(player, params)
		"unit_outside_own_dz":
			return _check_unit_outside_own_dz(player, params)
		"unit_outside_own_territory":
			return _check_unit_outside_own_territory(player, params)
		"units_recovered_assets":
			return _check_recovered_assets(player, params)

		# 11e (official launch data) checks
		"no_enemy_units_wholly_in_own_deployment_zone":
			return _check_no_enemy_wholly_in_own_dz(player)
		"action_completed_this_turn":
			return _check_objectives_cleansed(player, params)

		_:
			push_warning("SecondaryMissionManager: Unknown condition check: %s" % check)
			return false

func _count_condition(player: int, check: String, params: Dictionary, _mission: Dictionary) -> int:
	"""Route per-count (vp_per) condition checks. Each returns HOW MANY times
	the award's 'per' criterion was met; the caller multiplies by the
	condition's vp and clamps to vp_max."""
	match check:
		"enemy_units_destroyed_this_turn":
			return _count_enemy_units_destroyed(player, params)
		"enemy_units_destroyed_near_objective_this_turn":
			var p = params.duplicate()
			p["near_objective"] = true
			return _count_enemy_units_destroyed(player, p)
		"enemy_units_13_plus_destroyed_this_turn":
			var p13 = params.duplicate()
			if not p13.has("min_models"):
				p13["min_models"] = 13
			return _count_enemy_units_destroyed(player, p13)
		"enemy_character_models_destroyed_this_turn":
			return _count_enemy_character_models_destroyed(player, params)
		"enemy_models_wounds_10_plus_destroyed_this_turn":
			return _count_enemy_models_destroyed_with_wounds(player, int(params.get("min_wounds", 10)))
		"units_wholly_in_opponent_deployment_zone":
			return _count_units_in_opponent_zone(player, params)
		"guarded_objectives":
			return _count_guarded_objectives(player, params)
		_:
			push_warning("SecondaryMissionManager: Unknown count condition check: %s" % check)
			return 0

# ============================================================================
# CONDITION CHECKERS - POSITIONAL
# ============================================================================

func _check_units_in_opponent_zone(player: int, params: Dictionary) -> bool:
	"""Check how many units are wholly within opponent's deployment zone."""
	var required = params.get("count", 1)
	var qualifying_count = _count_units_in_opponent_zone(player, params)
	print("SecondaryMissionManager: [BEL-CHECK] P%d — %d/%d units in opponent zone" % [player, qualifying_count, required])
	return qualifying_count >= required

func _count_units_in_opponent_zone(player: int, params: Dictionary) -> int:
	"""Count units wholly within the opponent's deployment zone (11e Behind
	Enemy Lines scores 3 VP per such unit)."""
	var exclude = params.get("exclude", [])
	var opponent = 2 if player == 1 else 1
	var opponent_zone = _get_deployment_zone_polygon(opponent)

	if opponent_zone.is_empty():
		print("SecondaryMissionManager: [BEL-CHECK] P%d — opponent zone polygon is empty!" % player)
		return 0

	var qualifying_count = 0
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if _is_unit_excluded(unit, exclude):
			continue
		var in_zone = _is_unit_wholly_in_zone(unit, opponent_zone)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		if in_zone:
			qualifying_count += 1
			print("SecondaryMissionManager: [BEL-CHECK] P%d %s IS wholly in opponent zone" % [player, unit_name])

	return qualifying_count

func _check_table_quarter_presence(player: int, params: Dictionary) -> bool:
	"""Check presence in table quarters (>6\" from center)."""
	var required = params.get("count", 1)
	var min_dist = params.get("min_distance_from_center", 6.0)
	var exclude = params.get("exclude", [])

	var board_width = GameState.state.get("board", {}).get("size", {}).get("width", 44)
	var board_height = GameState.state.get("board", {}).get("size", {}).get("height", 60)
	var center_x = board_width / 2.0
	var center_y = board_height / 2.0

	# Define quarters: TL, TR, BL, BR
	var quarters_with_presence = 0
	var quarter_bounds = [
		{"min_x": 0, "max_x": center_x, "min_y": 0, "max_y": center_y},          # TL
		{"min_x": center_x, "max_x": board_width, "min_y": 0, "max_y": center_y}, # TR
		{"min_x": 0, "max_x": center_x, "min_y": center_y, "max_y": board_height},          # BL
		{"min_x": center_x, "max_x": board_width, "min_y": center_y, "max_y": board_height}, # BR
	]

	var units = GameState.state.get("units", {})
	var min_dist_px = Measurement.inches_to_px(min_dist)
	var center_px = Vector2(Measurement.inches_to_px(center_x), Measurement.inches_to_px(center_y))

	for quarter in quarter_bounds:
		var has_presence = false
		var q_min = Vector2(Measurement.inches_to_px(quarter["min_x"]), Measurement.inches_to_px(quarter["min_y"]))
		var q_max = Vector2(Measurement.inches_to_px(quarter["max_x"]), Measurement.inches_to_px(quarter["max_y"]))

		for unit_id in units:
			if has_presence:
				break
			var unit = units[unit_id]
			if unit.get("owner", 0) != player:
				continue
			if _is_unit_excluded(unit, exclude):
				continue
			# Check if unit is wholly within this quarter AND >6" from center
			if _is_unit_wholly_in_rect(unit, q_min, q_max) and _is_unit_far_from_point(unit, center_px, min_dist_px):
				has_presence = true

		if has_presence:
			quarters_with_presence += 1

	return quarters_with_presence >= required

func _check_area_denial(player: int, params: Dictionary) -> bool:
	"""Check units within center range and no enemies within enemy range."""
	var friendly_range = params.get("friendly_range", 3.0)
	var enemy_range = params.get("enemy_range", 3.0)
	var exclude = params.get("exclude", [])

	var board_width = GameState.state.get("board", {}).get("size", {}).get("width", 44)
	var board_height = GameState.state.get("board", {}).get("size", {}).get("height", 60)
	var center_px = Vector2(Measurement.inches_to_px(board_width / 2.0), Measurement.inches_to_px(board_height / 2.0))
	var friendly_range_px = Measurement.inches_to_px(friendly_range)
	var enemy_range_px = Measurement.inches_to_px(enemy_range)

	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})

	# Check if any friendly unit is within friendly_range of center
	var has_friendly = false
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if _is_unit_excluded(unit, exclude):
			continue
		if _has_model_within_range(unit, center_px, friendly_range_px):
			has_friendly = true
			break

	if not has_friendly:
		return false

	# Check no enemies within enemy_range of center
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		if _has_model_within_range(unit, center_px, enemy_range_px):
			return false

	return true

func _check_display_of_might(player: int, params: Dictionary = {}) -> bool:
	"""Check if player has more units wholly in NML than opponent.
	11e passes exclude: [Battle-shocked, Aircraft]; 10e passes nothing."""
	var exclude = params.get("exclude", [])
	var opponent = 2 if player == 1 else 1
	var player_count = _count_units_wholly_in_nml(player, exclude)
	var opponent_count = _count_units_wholly_in_nml(opponent, exclude)
	return player_count > opponent_count

# ============================================================================
# CONDITION CHECKERS - OBJECTIVE CONTROL
# ============================================================================

func _check_storm_hostile_objective(player: int, params: Dictionary) -> bool:
	"""Check if player controls objectives that opponent controlled at start of turn.
	Also counts objectives that were contested (0) at start but are now player-controlled,
	since capturing contested objectives is a valid 'storm' action."""
	var required = params.get("count", 1)
	var count = 0

	for obj_id in MissionManager.objective_control_state:
		var current_controller = MissionManager.objective_control_state[obj_id]
		var start_controller = _objective_control_at_turn_start.get(obj_id, 0)
		var opponent = 2 if player == 1 else 1

		# Count if: player now controls AND (opponent controlled at start OR was contested at start)
		if current_controller == player and start_controller != player:
			count += 1
			print("SecondaryMissionManager: [STORM] Player %d captured objective %s (was %d, now %d)" % [player, obj_id, start_controller, current_controller])

	return count >= required

func _check_storm_hostile_alt(player: int, params: Dictionary) -> bool:
	"""Alt condition: opponent controlled no objectives at start AND you control new ones.
	Per rules, this triggers when opponent had 0 objectives at turn start and you capture at least 1."""
	var min_round = params.get("min_round", 1)
	if GameState.get_battle_round() < min_round:
		return false

	var opponent = 2 if player == 1 else 1

	# Check opponent controlled no objectives at start
	for obj_id in _objective_control_at_turn_start:
		if _objective_control_at_turn_start[obj_id] == opponent:
			return false

	# Check you control at least 1 you didn't at start
	for obj_id in MissionManager.objective_control_state:
		var current = MissionManager.objective_control_state[obj_id]
		var start = _objective_control_at_turn_start.get(obj_id, 0)
		if current == player and start != player:
			print("SecondaryMissionManager: [STORM-ALT] Player %d captured objective %s (opponent had 0 at start)" % [player, obj_id])
			return true

	return false

func _check_own_zone_objectives(player: int, params: Dictionary) -> bool:
	"""Check if player controls objectives in their own deployment zone."""
	var required = params.get("count", 1)
	var count = 0
	var objectives = GameState.state.board.get("objectives", [])
	var player_zone = "player%d" % player

	for obj in objectives:
		var zone = obj.get("zone", "")
		if zone == player_zone:
			var controller = MissionManager.objective_control_state.get(obj["id"], 0)
			if controller == player:
				count += 1

	return count >= required

func _check_nml_objectives(player: int, params: Dictionary) -> bool:
	"""Check if player controls objectives in No Man's Land."""
	var required = params.get("count", 1)
	var count = 0
	var objectives = GameState.state.board.get("objectives", [])

	for obj in objectives:
		if obj.get("zone", "") == "no_mans_land":
			var controller = MissionManager.objective_control_state.get(obj["id"], 0)
			if controller == player:
				count += 1

	return count >= required

func _check_tempting_target(player: int, mission: Dictionary) -> bool:
	"""Check if player controls the Tempting Target objective."""
	var target_obj_id = mission.get("mission_data", {}).get("tempting_target_id", "")
	if target_obj_id == "":
		return false
	var controller = MissionManager.objective_control_state.get(target_obj_id, 0)
	return controller == player

func _check_extend_battle_lines(player: int, params: Dictionary) -> bool:
	"""Check if player controls objectives in own zone AND NML."""
	var own_required = params.get("own_zone_count", 1)
	var nml_required = params.get("nml_count", 1)
	return _check_own_zone_objectives(player, {"count": own_required}) and _check_nml_objectives(player, {"count": nml_required})

# ============================================================================
# CONDITION CHECKERS - KILL-BASED
# ============================================================================

func _check_characters_destroyed_this_turn(player: int, params: Dictionary) -> bool:
	"""Check if enemy CHARACTER models were destroyed this turn."""
	var required = params.get("count", 1)
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if int(destroyed.get("owner", 0)) == player:
			continue  # a player never scores for losing their own characters
		if destroyed.get("is_character", false):
			count += 1
	return count >= required

func _check_all_enemy_characters_destroyed(player: int) -> bool:
	"""Check if ALL enemy CHARACTER models have been destroyed."""
	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		var is_char = false
		for kw in keywords:
			if kw.to_upper() == "CHARACTER":
				is_char = true
				break
		if not is_char:
			continue

		# Check if any models are still alive
		for model in unit.get("models", []):
			if model.get("alive", true):
				return false

	return true

func _check_enemy_unit_destroyed_this_turn(_player: int) -> bool:
	"""Check if any enemy unit was destroyed this turn."""
	return _units_destroyed_this_turn.size() > 0

func _check_infantry_horde_destroyed(_player: int, params: Dictionary) -> bool:
	"""Check if INFANTRY units with starting strength 13+ were destroyed."""
	var required = params.get("count", 1)
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("is_infantry", false) and destroyed.get("starting_strength", 0) >= 13:
			count += 1
	return count >= required

func _check_monster_vehicle_destroyed(_player: int, params: Dictionary) -> bool:
	"""Check if MONSTER or VEHICLE units were destroyed this turn."""
	var required = params.get("count", 1)
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("is_monster", false) or destroyed.get("is_vehicle", false):
			count += 1
	return count >= required

func _check_alpha_target_destroyed(_player: int, mission: Dictionary, params: Dictionary) -> bool:
	"""Check if any Marked for Death alpha targets were destroyed this turn."""
	var alpha_targets = mission.get("mission_data", {}).get("alpha_targets", [])
	var required = params.get("count", 1)
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("unit_id", "") in alpha_targets:
			count += 1
	return count >= required

func _check_gamma_target_destroyed(_player: int, mission: Dictionary) -> bool:
	"""Check if gamma target destroyed but no alpha targets destroyed."""
	var alpha_targets = mission.get("mission_data", {}).get("alpha_targets", [])
	var gamma_target = mission.get("mission_data", {}).get("gamma_target", "")

	# Check no alpha destroyed
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("unit_id", "") in alpha_targets:
			return false

	# Check gamma destroyed
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("unit_id", "") == gamma_target:
			return true

	return false

func _check_overwhelming_force(_player: int) -> bool:
	"""Check if enemy units near objectives were destroyed."""
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("was_near_objective", false):
			return true
	return false

# ============================================================================
# COUNT-BASED CHECKERS — 11e official vp_per awards (value = vp * count)
# ============================================================================

func _count_enemy_units_destroyed(player: int, params: Dictionary) -> int:
	"""Count enemy units destroyed this turn. Optional filters:
	min_models (starting strength threshold, e.g. A Grievous Blow 13+) and
	near_objective (Overwhelming Force)."""
	var min_models = int(params.get("min_models", 0))
	var near_objective = bool(params.get("near_objective", false))
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if int(destroyed.get("owner", 0)) == player:
			continue
		if min_models > 0 and int(destroyed.get("starting_strength", 0)) < min_models:
			continue
		if near_objective and not destroyed.get("was_near_objective", false):
			continue
		count += 1
	return count

func _count_enemy_character_models_destroyed(player: int, params: Dictionary) -> int:
	"""Count enemy CHARACTER models destroyed this turn (11e Assassination).
	Optional min_wounds filters to models with W>=N (the W4+ bonus row)."""
	var min_wounds = int(params.get("min_wounds", 0))
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if int(destroyed.get("owner", 0)) == player:
			continue
		if not destroyed.get("is_character", false):
			continue
		count += _count_destroyed_models_with_wounds(destroyed, min_wounds)
	return count

func _count_enemy_models_destroyed_with_wounds(player: int, min_wounds: int) -> int:
	"""Count enemy MODELS with W>=min_wounds destroyed this turn (11e Bring
	it Down scores per 10+W model)."""
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if int(destroyed.get("owner", 0)) == player:
			continue
		count += _count_destroyed_models_with_wounds(destroyed, min_wounds)
	return count

func _count_destroyed_models_with_wounds(destroyed: Dictionary, min_wounds: int) -> int:
	"""How many models of a destroyed unit had a Wounds characteristic of
	min_wounds or more (0 = all models). Uses the per-model wound stats
	recorded at destruction time; falls back to unit-level info for records
	that predate model_wounds."""
	var model_wounds = destroyed.get("model_wounds", [])
	if model_wounds is Array and model_wounds.size() > 0:
		var n = 0
		for w in model_wounds:
			if int(w) >= min_wounds:
				n += 1
		return n
	# Fallback (older save data): approximate from unit-level stats.
	if min_wounds <= 0:
		return int(destroyed.get("starting_strength", 0))
	if int(destroyed.get("max_model_wounds", 0)) >= min_wounds:
		return int(destroyed.get("starting_strength", 1))
	return 0

## Burden of Trust (guard selection auto-resolved): every objective the
## player controls counts as guarded — controlling an objective implies a
## friendly unit within range of it acting as the guard.
func _count_guarded_objectives(player: int, _params: Dictionary) -> int:
	var count = 0
	for obj_id in MissionManager.objective_control_state:
		if MissionManager.objective_control_state.get(obj_id, 0) == player:
			count += 1
	return count

# ============================================================================
# CONDITION CHECKERS - ACTION-BASED (stubs for future implementation)
# ============================================================================

func _check_locus_center(player: int, _params: Dictionary) -> bool:
	"""Check if a locus was established within 6\" of center."""
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == "Establish Locus" and action.get("completed", false):
			if action.get("location", "") == "center":
				return true
	return false

func _check_locus_opponent_zone(player: int) -> bool:
	"""Check if a locus was established in opponent's deployment zone."""
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == "Establish Locus" and action.get("completed", false):
			if action.get("location", "") == "opponent_zone":
				return true
	return false

func _check_objectives_cleansed(player: int, params: Dictionary) -> bool:
	"""Check if objectives were cleansed/looted this turn. The 11e Plunder
	card reuses this check with its own action name."""
	var required = params.get("count", 1)
	var wanted_action = str(params.get("action_name", "Cleanse"))
	var count = 0
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == wanted_action and action.get("completed", false):
			count += 1
	return count >= required

func _check_teleport_homer(player: int, in_opponent_zone: bool, params: Dictionary = {}) -> bool:
	"""Check if a teleport homer (or 11e Beacon) was deployed."""
	var wanted_homer = str(params.get("action_name", "Deploy Teleport Homer"))
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == wanted_homer and action.get("completed", false):
			if in_opponent_zone:
				return action.get("location", "") == "opponent_zone"
			else:
				return action.get("location", "") != "opponent_zone"
	return false

func _check_recovered_assets(player: int, params: Dictionary) -> bool:
	"""Check if assets were recovered."""
	var required = params.get("count", 2)
	var count = 0
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == "Recover Assets" and action.get("completed", false):
			count += 1
	return count >= required

# ============================================================================
# VP MANAGEMENT
# ============================================================================

func _award_secondary_vp(player: int, vp: int, mission_id: String) -> int:
	"""Award secondary VP, respecting caps. Returns actual VP awarded."""
	var player_key = str(player)
	var state = _player_state[player_key]
	var current_secondary = state["secondary_vp"]

	# Cap at the edition's secondary total (11e GDM 2026: 45; 10e: 40)
	var vp_cap := MAX_SECONDARY_VP_11E if GameConstants.edition >= 11 else MAX_SECONDARY_VP
	var available = vp_cap - current_secondary
	var actual_vp = mini(vp, available)

	if actual_vp <= 0:
		print("SecondaryMissionManager: Player %d at secondary VP cap (%d)" % [player, vp_cap])
		return 0

	# 11e: additionally capped at 15 secondary VP per turn
	if GameConstants.edition >= 11:
		var turn_available = MAX_SECONDARY_VP_PER_TURN_11E - int(state.get("secondary_vp_this_turn", 0))
		actual_vp = mini(actual_vp, turn_available)
		if actual_vp <= 0:
			print("SecondaryMissionManager: Player %d at per-turn secondary VP cap (%d)" % [player, MAX_SECONDARY_VP_PER_TURN_11E])
			return 0

	# 11e Fixed mode (GDM sourced): each fixed card can score at most 20 VP
	# over the game
	if GameConstants.edition >= 11 and state.get("mode", "tactical") == "fixed":
		var by_mission = state.get("vp_by_mission", {})
		var card_available = MAX_VP_PER_FIXED_CARD_11E - int(by_mission.get(mission_id, 0))
		actual_vp = mini(actual_vp, card_available)
		if actual_vp <= 0:
			print("SecondaryMissionManager: Player %d fixed card %s at its 20 VP cap" % [player, mission_id])
			return 0

	# Also check combined cap
	var primary_vp = GameState.state.get("players", {}).get(player_key, {}).get("primary_vp", 0)
	var combined_available = MAX_COMBINED_VP - primary_vp - current_secondary
	actual_vp = mini(actual_vp, combined_available)

	if actual_vp <= 0:
		print("SecondaryMissionManager: Player %d at combined VP cap (%d)" % [player, MAX_COMBINED_VP])
		return 0

	# Award VP
	state["secondary_vp"] += actual_vp
	state["secondary_vp_this_turn"] = int(state.get("secondary_vp_this_turn", 0)) + actual_vp
	if not state.has("vp_by_mission"):
		state["vp_by_mission"] = {}
	state["vp_by_mission"][mission_id] = int(state["vp_by_mission"].get(mission_id, 0)) + actual_vp

	# Update GameState total VP
	var total_vp = GameState.state.get("players", {}).get(player_key, {}).get("vp", 0)
	var changes = [
		{
			"op": "set",
			"path": "players.%s.vp" % player_key,
			"value": total_vp + actual_vp,
		},
		{
			"op": "set",
			"path": "players.%s.secondary_vp" % player_key,
			"value": state["secondary_vp"],
		},
	]
	PhaseManager.apply_state_changes(changes)

	print("SecondaryMissionManager: Player %d awarded %d secondary VP from %s (total secondary: %d)" % [
		player, actual_vp, mission_id, state["secondary_vp"]])

	return actual_vp

func _discard_achieved_missions(player: int) -> void:
	"""Discard missions that were achieved this turn."""
	var player_key = str(player)
	var state = _player_state[player_key]
	var remaining = []

	for mission in state["active"]:
		if mission["achieved"]:
			state["discard"].append(mission["id"])
			# Clear visual indicators if this was A Tempting Target or Marked for Death
			if mission["id"] == "a_tempting_target":
				var target_id = mission.get("mission_data", {}).get("tempting_target_id", "")
				if target_id != "":
					_clear_tempting_target_visual(target_id)
			elif mission["id"] == "marked_for_death":
				var mfd_data = mission.get("mission_data", {})
				_clear_mfd_target_visuals(mfd_data.get("alpha_targets", []), mfd_data.get("gamma_target", ""))
			print("SecondaryMissionManager: Player %d achieved and discarded %s" % [player, mission["name"]])
		else:
			remaining.append(mission)

	state["active"] = remaining

# ============================================================================
# CONDITION CHECKERS — 11e (GDM 2026) deck
# ============================================================================

## A Grievous Blow (approx.): an enemy unit worth min_points+ points, or
## containing a model with min_wounds+ starting wounds, was destroyed this turn.
func _check_high_value_unit_destroyed(player: int, params: Dictionary) -> bool:
	# GDM sourced text: A Grievous Blow targets units with a Starting
	# Strength of 13+ models (min_models). The points/wounds params remain
	# for any card that wants a value-based threshold.
	var min_models = int(params.get("min_models", 0))
	var min_points = int(params.get("min_points", 0))
	var min_wounds = int(params.get("min_wounds", 0))
	for destroyed in _units_destroyed_this_turn:
		if int(destroyed.get("owner", 0)) == player:
			continue
		if min_models > 0 and int(destroyed.get("starting_strength", 0)) >= min_models:
			return true
		if min_points > 0 and int(destroyed.get("points", 0)) >= min_points:
			return true
		if min_wounds > 0 and int(destroyed.get("max_model_wounds", 0)) >= min_wounds:
			return true
	return false

## Forward Position (11e official): the player controls the objective in the
## OPPONENT's deployment zone (their home objective), OR one or more
## Expansion objectives.
func _check_enemy_home_objective(player: int) -> bool:
	var opponent = 3 - player
	var opponent_zone = "player%d" % opponent
	for obj in GameState.state.get("board", {}).get("objectives", []):
		if obj.get("zone", "") == opponent_zone:
			if MissionManager.objective_control_state.get(obj["id"], 0) == player:
				return true
	if MissionManager.has_method("get_objective_ids_by_designation"):
		var expansions = MissionManager.get_objective_ids_by_designation("expansion")
		for obj_id in expansions:
			if MissionManager.objective_control_state.get(obj_id, 0) == player:
				return true
	return false

## Burden of Trust (approx.): count objectives the player controlled at the
## START of the turn and still controls now.
func _check_objectives_held_since_turn_start(player: int, params: Dictionary) -> bool:
	var required = int(params.get("count", 1))
	var count = 0
	for obj_id in _objective_control_at_turn_start:
		if _objective_control_at_turn_start[obj_id] == player \
				and MissionManager.objective_control_state.get(obj_id, 0) == player:
			count += 1
	return count >= required

## Outflank (11e official): units with every alive model within edge_inches
## of a battlefield edge.
## params.count — require N qualifying units;
## params.outside_own_territory — qualifying units must not be within the
##   player's territory (approximated as their board half, see
##   _get_own_territory_rect);
## params.opposite_edges — the official 5 VP tier: 2+ qualifying units within
##   edge_inches of OPPOSITE (parallel) battlefield edges, at least one of
##   them not within the player's territory;
## params.min_edges — legacy: qualifying units on N DISTINCT edges.
func _check_units_near_board_edges(player: int, params: Dictionary) -> bool:
	var required = int(params.get("count", 1))
	var min_edges = int(params.get("min_edges", 0))
	var opposite_edges = bool(params.get("opposite_edges", false))
	var require_outside_territory = bool(params.get("outside_own_territory", false))
	var edge_in = float(params.get("edge_inches", 6.0))
	var exclude = params.get("exclude", [])
	var board_w_px = Measurement.inches_to_px(float(GameState.state.get("board", {}).get("size", {}).get("width", 44)))
	var board_h_px = Measurement.inches_to_px(float(GameState.state.get("board", {}).get("size", {}).get("height", 60)))
	var edge_px = Measurement.inches_to_px(edge_in)
	var territory_rect = {}
	if require_outside_territory or opposite_edges:
		territory_rect = _get_own_territory_rect(player)
	var qualifying = []  # [{edges: {left/right/top/bottom}, outside: bool}]
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if "Battle-shocked" in exclude and unit.get("flags", {}).get("battle_shocked", false):
			continue
		if _unit_has_excluded_keyword(unit, exclude):
			continue
		var any_alive = false
		var all_near_edge = true
		var unit_edges = {}
		for m in unit.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			any_alive = true
			var pos = m["position"]
			var px = float(pos.x) if not (pos is Dictionary) else float(pos.get("x", 0))
			var py = float(pos.y) if not (pos is Dictionary) else float(pos.get("y", 0))
			var model_edges = {}
			if px <= edge_px:
				model_edges["left"] = true
			if py <= edge_px:
				model_edges["top"] = true
			if px >= board_w_px - edge_px:
				model_edges["right"] = true
			if py >= board_h_px - edge_px:
				model_edges["bottom"] = true
			if model_edges.is_empty():
				all_near_edge = false
				break
			for e in model_edges:
				unit_edges[e] = true
		if any_alive and all_near_edge:
			var outside = territory_rect.is_empty() or not _is_unit_partly_in_rect(unit, territory_rect)
			qualifying.append({"edges": unit_edges, "outside": outside})

	if opposite_edges:
		# 5 VP tier: two units within range of opposite (parallel) edges,
		# at least one of the pair not within the player's territory.
		for pair in [["left", "right"], ["top", "bottom"]]:
			for i in range(qualifying.size()):
				if not qualifying[i]["edges"].has(pair[0]):
					continue
				for j in range(qualifying.size()):
					if i == j or not qualifying[j]["edges"].has(pair[1]):
						continue
					if qualifying[i]["outside"] or qualifying[j]["outside"]:
						return true
		return false

	var count = 0
	var edges_hit = {}
	for q in qualifying:
		if require_outside_territory and not q["outside"]:
			continue
		count += 1
		for e in q["edges"]:
			edges_hit[e] = true
	if min_edges > 0:
		return edges_hit.size() >= min_edges
	return count >= required

## Beacon (sourced, pick auto-resolved): a friendly unit is alive on the
## battlefield with every model outside the player's own deployment zone.
func _check_unit_outside_own_dz(player: int, params: Dictionary) -> bool:
	var exclude = params.get("exclude", [])
	var own_zone = _get_deployment_zone_polygon(player)
	if own_zone.is_empty():
		return false
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if "Battle-shocked" in exclude and unit.get("flags", {}).get("battle_shocked", false):
			continue
		var any_alive = false
		var any_inside = false
		for m in unit.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			any_alive = true
			var pos = m["position"]
			if pos is Dictionary:
				pos = Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
			if Geometry2D.is_point_in_polygon(pos, own_zone):
				any_inside = true
				break
		if any_alive and not any_inside:
			return true
	return false

## Beacon 5 VP tier (official). "Your territory" is approximated as the
## player's board half (see _get_own_territory_rect): a friendly unit is
## alive on the battlefield with no model within that half.
func _check_unit_outside_own_territory(player: int, params: Dictionary) -> bool:
	var exclude = params.get("exclude", [])
	var rect = _get_own_territory_rect(player)
	if rect.is_empty():
		return false
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if _is_unit_excluded(unit, exclude):
			continue
		var any_alive_positioned = false
		for m in unit.get("models", []):
			if m.get("alive", true) and m.get("position") != null:
				any_alive_positioned = true
				break
		if any_alive_positioned and not _is_unit_partly_in_rect(unit, rect):
			return true
	return false

## Defend Stronghold (11e) bonus row: no enemy unit is wholly within the
## player's deployment zone.
func _check_no_enemy_wholly_in_own_dz(player: int) -> bool:
	var own_zone = _get_deployment_zone_polygon(player)
	if own_zone.is_empty():
		return false
	var opponent = 2 if player == 1 else 1
	for unit_id in GameState.state.get("units", {}):
		var unit = GameState.state.units[unit_id]
		if int(unit.get("owner", 0)) != opponent:
			continue
		if _is_unit_excluded(unit, []):
			continue  # undeployed / destroyed units cannot contest the zone
		if _is_unit_wholly_in_zone(unit, own_zone):
			return false
	return true

## Approximation of "your territory" (11e Outflank / Beacon): the board half
## containing the player's deployment zone, split along the axis where the
## DZ centroid deviates most from the board centre. Diagonal deployment
## layouts are approximated by their dominant axis.
func _get_own_territory_rect(player: int) -> Dictionary:
	var zone = _get_deployment_zone_polygon(player)
	if zone.is_empty():
		return {}
	var board_w = Measurement.inches_to_px(float(GameState.state.get("board", {}).get("size", {}).get("width", 44)))
	var board_h = Measurement.inches_to_px(float(GameState.state.get("board", {}).get("size", {}).get("height", 60)))
	var centroid = Vector2.ZERO
	for p in zone:
		centroid += p
	centroid /= zone.size()
	var center = Vector2(board_w / 2.0, board_h / 2.0)
	var d = centroid - center
	if abs(d.x) >= abs(d.y):
		if d.x <= 0:
			return {"min": Vector2(0, 0), "max": Vector2(center.x, board_h)}
		return {"min": Vector2(center.x, 0), "max": Vector2(board_w, board_h)}
	if d.y <= 0:
		return {"min": Vector2(0, 0), "max": Vector2(board_w, center.y)}
	return {"min": Vector2(0, center.y), "max": Vector2(board_w, board_h)}

func _is_unit_partly_in_rect(unit: Dictionary, rect: Dictionary) -> bool:
	"""True if ANY alive model of the unit is within the rect ("within" in
	40k terms — any part of the unit)."""
	if rect.is_empty():
		return false
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			continue
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		if pos.x >= rect["min"].x and pos.x <= rect["max"].x \
				and pos.y >= rect["min"].y and pos.y <= rect["max"].y:
			return true
	return false

# ============================================================================
# EVENT HOOKS - Called by other systems to track game events
# ============================================================================

func on_turn_start(player: int) -> void:
	"""Called at the start of a player's turn. Snapshot objective control."""
	_units_destroyed_this_turn.clear()
	# 11e: the 15 VP/turn secondary window resets for both players (either
	# player can score at either turn's end).
	for pk in _player_state:
		_player_state[pk]["secondary_vp_this_turn"] = 0
	_while_active_vp_this_window.clear()
	_objective_control_at_turn_start = MissionManager.objective_control_state.duplicate()
	# Clear completed actions from previous turn
	_active_actions[str(player)].clear()
	print("SecondaryMissionManager: Turn start for Player %d - snapshot objectives" % player)

func on_unit_destroyed(destroyed_unit: Dictionary) -> void:
	"""
	Called when a unit is destroyed. Records info for kill-based missions.
	destroyed_unit should contain: unit_id, owner, keywords, starting_strength, wounds, was_near_objective
	"""
	_units_destroyed_this_turn.append(destroyed_unit)

	var unit_name = destroyed_unit.get("unit_name", destroyed_unit.get("unit_id", "unknown"))
	print("SecondaryMissionManager: Recorded unit destruction: %s" % unit_name)

	# Check "while_active" missions immediately for both players
	for p in [1, 2]:
		if destroyed_unit.get("owner", 0) == p:
			continue  # Skip the owner - they don't score for their own destruction
		_check_while_active_missions(p, destroyed_unit)

func _check_while_active_missions(player: int, destroyed_unit: Dictionary) -> void:
	"""Check while_active missions after a unit destruction event."""
	var player_key = str(player)
	var state = _player_state[player_key]

	for mission in state["active"]:
		if mission.get("pending_interaction", false):
			continue

		var scoring = mission["scoring"]
		if scoring.get("when", "") != SecondaryMissionData.TIMING_WHILE_ACTIVE:
			continue

		var max_vp = scoring.get("max_vp_per_score", 999)
		var window_key = "%s_%s" % [player_key, mission["id"]]
		var accumulated = _while_active_vp_this_window.get(window_key, 0)

		if accumulated >= max_vp:
			continue  # Already hit cap for this scoring window

		for condition in scoring.get("conditions", []):
			var check = condition.get("check", "")
			var vp = condition.get("vp", 0)

			var matches = false
			match check:
				"enemy_unit_destroyed":
					matches = true
				"enemy_bodyguard_or_non_character_unit_destroyed":
					matches = not destroyed_unit.get("is_character", false) or destroyed_unit.get("is_bodyguard", false)
				"enemy_unit_destroyed_within_objective_range":
					matches = destroyed_unit.get("was_near_objective", false)

			if matches:
				var remaining = max_vp - accumulated
				var award = mini(vp, remaining)
				# In fixed mode, also cap by per-mission VP limit
				if state.get("mode", "tactical") == "fixed":
					var mission_remaining = MAX_FIXED_MISSION_VP - mission["vp_scored"]
					award = mini(award, mission_remaining)
				if award > 0:
					var actual = _award_secondary_vp(player, award, mission["id"])
					if actual > 0:
						mission["vp_scored"] += actual
						_while_active_vp_this_window[window_key] = accumulated + actual
						emit_signal("secondary_vp_scored", player, actual, mission["id"])
						print("SecondaryMissionManager: Player %d scored %d VP (while active) from %s" % [player, actual, mission["name"]])

func on_action_completed(player: int, action_data: Dictionary) -> void:
	"""Called when a unit completes an action (for action-based missions)."""
	_active_actions[str(player)].append(action_data)
	print("SecondaryMissionManager: Player %d completed action: %s" % [player, action_data.get("action_name", "")])

func check_and_report_unit_destroyed(unit_id: String) -> void:
	"""
	Check if ALL models in a unit are dead. If so, build a destroyed_unit dict
	and call on_unit_destroyed(). Deduplicates via _units_destroyed_this_turn.
	Also recursively checks attached characters (they may have died too).
	"""
	# Dedup: skip if already reported this turn
	for already in _units_destroyed_this_turn:
		if already.get("unit_id", "") == unit_id:
			return

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return

	# Check if ALL models are dead
	var models = unit.get("models", [])
	if models.is_empty():
		return

	for model in models:
		if model.get("alive", true):
			return  # At least one model still alive — not destroyed

	# Unit is fully destroyed — build info dict
	var keywords = unit.get("meta", {}).get("keywords", [])
	var upper_keywords = []
	for kw in keywords:
		upper_keywords.append(kw.to_upper())

	var starting_strength = models.size()
	var owner = unit.get("owner", 0)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# MA-22: Collect model type labels for destroyed unit
	var model_type_labels: Array = []
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	for model in models:
		var mt = model.get("model_type", "")
		if mt != "" and model_profiles.has(mt):
			var label = model_profiles[mt].get("label", mt)
			if label not in model_type_labels:
				model_type_labels.append(label)

	var max_model_wounds := 0
	# Per-model Wounds characteristics — 11e Bring it Down / Assassination
	# score per destroyed MODEL over a wounds threshold.
	var model_wounds: Array = []
	for m in models:
		var w := int(m.get("wounds", 1))
		model_wounds.append(w)
		max_model_wounds = maxi(max_model_wounds, w)
	var destroyed_dict = {
		"unit_id": unit_id,
		"unit_name": unit_name,
		"owner": owner,
		"keywords": keywords,
		"points": int(unit.get("meta", {}).get("points", 0)),
		"max_model_wounds": max_model_wounds,
		"model_wounds": model_wounds,
		"starting_strength": starting_strength,
		"is_character": "CHARACTER" in upper_keywords,
		"is_infantry": "INFANTRY" in upper_keywords,
		"is_monster": "MONSTER" in upper_keywords,
		"is_vehicle": "VEHICLE" in upper_keywords,
		"is_bodyguard": unit.get("attachment_data", {}).get("attached_characters", []).size() > 0 or "BODYGUARD" in upper_keywords,
		"was_near_objective": _check_unit_near_any_objective(unit),
		"model_types": model_type_labels,  # MA-22: Model type labels in destroyed unit
	}

	# MA-22: Include model types in destruction log if available
	var type_info = ""
	if not model_type_labels.is_empty():
		type_info = " [types: %s]" % ", ".join(model_type_labels)
	print("SecondaryMissionManager: Unit %s (%s) fully destroyed!%s Reporting..." % [unit_id, unit_name, type_info])
	on_unit_destroyed(destroyed_dict)

	# Recursively check attached characters — when a bodyguard dies, characters
	# may have been killed too (or detached and killed separately)
	var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
	for char_id in attached_chars:
		check_and_report_unit_destroyed(char_id)

func _check_unit_near_any_objective(unit: Dictionary) -> bool:
	"""Check if any model in the unit (alive or dead) is within 3\" of any objective."""
	var objectives = GameState.state.get("board", {}).get("objectives", [])
	if objectives.is_empty():
		return false

	var range_px = Measurement.inches_to_px(3.0)

	for obj in objectives:
		var obj_pos = obj.get("position", null)
		if obj_pos == null:
			continue
		if obj_pos is Dictionary:
			obj_pos = Vector2(obj_pos.x, obj_pos.y)

		for model in unit.get("models", []):
			var pos = model.get("position", null)
			if pos == null:
				continue
			if pos is Dictionary:
				pos = Vector2(pos.x, pos.y)
			# Any part of the model's base overlapping counts
			var model_base_radius = Measurement.base_radius_px(model.get("base_mm", 32))
			if pos.distance_to(obj_pos) <= range_px + model_base_radius:
				return true

	return false

# ============================================================================
# INTERACTION RESOLUTION
# ============================================================================

func resolve_marked_for_death(player: int, alpha_targets: Array, gamma_target: String) -> void:
	"""Resolve Marked for Death interaction - set the alpha and gamma targets."""
	var player_key = str(player)
	var state = _player_state[player_key]

	for mission in state["active"]:
		if mission["id"] == "marked_for_death" and mission.get("pending_interaction", false):
			mission["mission_data"]["alpha_targets"] = alpha_targets
			mission["mission_data"]["gamma_target"] = gamma_target
			mission["pending_interaction"] = false
			print("SecondaryMissionManager: Marked for Death resolved - Alpha: %s, Gamma: %s" % [str(alpha_targets), gamma_target])
			# Set visual flags on targeted units
			_mark_mfd_target_visuals(alpha_targets, gamma_target, player)
			return

func resolve_tempting_target(player: int, objective_id: String) -> void:
	"""Resolve A Tempting Target interaction - set the target objective."""
	var player_key = str(player)
	var state = _player_state[player_key]

	for mission in state["active"]:
		if mission["id"] == "a_tempting_target" and mission.get("pending_interaction", false):
			mission["mission_data"]["tempting_target_id"] = objective_id
			mission["pending_interaction"] = false
			print("SecondaryMissionManager: A Tempting Target resolved - Objective: %s" % objective_id)
			# Mark the objective visually on the board
			_mark_tempting_target_visual(objective_id, player)
			return

func _mark_tempting_target_visual(objective_id: String, player: int) -> void:
	"""Mark an objective on the board as the Tempting Target for the given player."""
	var obj_visual = MissionManager.objectives_visual_refs.get(objective_id, null)
	if obj_visual and obj_visual is ObjectiveVisual:
		obj_visual.set_tempting_target(true, player)
	else:
		print("SecondaryMissionManager: Could not find ObjectiveVisual for %s to mark as Tempting Target" % objective_id)

func _clear_tempting_target_visual(objective_id: String) -> void:
	"""Remove the Tempting Target visual indicator from an objective."""
	var obj_visual = MissionManager.objectives_visual_refs.get(objective_id, null)
	if obj_visual and obj_visual is ObjectiveVisual:
		obj_visual.set_tempting_target(false)

func _mark_mfd_target_visuals(alpha_targets: Array, gamma_target: String, _player: int) -> void:
	"""Set 'marked_for_death' flag on targeted units for visual indicators."""
	for unit_id in alpha_targets:
		var unit = GameState.state.get("units", {}).get(unit_id, {})
		if not unit.is_empty():
			if not unit.has("flags"):
				unit["flags"] = {}
			unit["flags"]["marked_for_death"] = "alpha"
			print("SecondaryMissionManager: Marked unit %s as Alpha target" % unit_id)

	if gamma_target != "":
		var unit = GameState.state.get("units", {}).get(gamma_target, {})
		if not unit.is_empty():
			if not unit.has("flags"):
				unit["flags"] = {}
			unit["flags"]["marked_for_death"] = "gamma"
			print("SecondaryMissionManager: Marked unit %s as Gamma target" % gamma_target)

func _clear_mfd_target_visuals(alpha_targets: Array, gamma_target: String) -> void:
	"""Remove 'marked_for_death' flag from previously targeted units."""
	var all_targets = alpha_targets.duplicate()
	if gamma_target != "":
		all_targets.append(gamma_target)

	for unit_id in all_targets:
		var unit = GameState.state.get("units", {}).get(unit_id, {})
		if not unit.is_empty() and unit.has("flags"):
			unit["flags"].erase("marked_for_death")

func _restore_mfd_target_visuals() -> void:
	"""Re-apply Marked for Death visual flags after loading save data."""
	for player_key in _player_state:
		var state = _player_state[player_key]
		for mission in state.get("active", []):
			if mission.get("id", "") == "marked_for_death":
				var mdata = mission.get("mission_data", {})
				var alpha = mdata.get("alpha_targets", [])
				var gamma = mdata.get("gamma_target", "")
				if not alpha.is_empty() or gamma != "":
					_mark_mfd_target_visuals(alpha, gamma, int(player_key))

# ============================================================================
# QUERIES
# ============================================================================

func get_active_missions(player: int) -> Array:
	"""Get the active secondary missions for a player."""
	return _player_state[str(player)]["active"].duplicate(true)

func get_secondary_vp(player: int) -> int:
	"""Get total secondary VP for a player."""
	return _player_state[str(player)]["secondary_vp"]

func get_deck_size(player: int) -> int:
	"""Get remaining cards in deck."""
	return _player_state[str(player)]["deck"].size()

func get_discard_size(player: int) -> int:
	"""Get number of discarded cards."""
	return _player_state[str(player)]["discard"].size()

func is_initialized(player: int) -> bool:
	"""Check if player's secondary missions are set up."""
	return _player_state[str(player)]["initialized"]

func evaluate_mission_progress(player: int) -> Array:
	"""Evaluate current progress for all active secondary missions without scoring.
	Returns array of mission progress dicts:
	[{
		"mission_id": String,
		"mission_name": String,
		"vp_scored": int,
		"conditions": [{
			"check": String,
			"vp": int,
			"met": bool,
			"description": String,
		}],
		"best_vp_available": int,  # Highest VP condition currently met (0 if none)
	}]
	"""
	var player_key = str(player)
	var state = _player_state[player_key]
	var progress_list = []

	for mission in state["active"]:
		if mission.get("pending_interaction", false):
			progress_list.append({
				"mission_id": mission["id"],
				"mission_name": mission.get("name", "Unknown"),
				"vp_scored": mission.get("vp_scored", 0),
				"conditions": [],
				"best_vp_available": 0,
				"pending_interaction": true,
			})
			continue

		var scoring = mission.get("scoring", {})
		var conditions = scoring.get("conditions", [])
		var player_mode = state.get("mode", "tactical")
		var condition_results = []
		var best_exclusive = 0
		var cumulative_total = 0

		for condition in conditions:
			var check = condition.get("check", "")
			var params = condition.get("params", {})
			var vp = condition.get("vp", 0)
			# Mode-split awards (11e fixed/tactical) only show/score for the
			# player's current approach.
			var cond_mode = str(condition.get("mode", ""))
			if cond_mode != "" and cond_mode != player_mode:
				continue
			var value = _evaluate_condition_value(player, condition, mission)
			var met = value > 0

			condition_results.append({
				"check": check,
				"vp": vp,
				"met": met,
				"value": value,
				"description": _humanize_condition(check, params),
			})

			if condition.get("cumulative", false):
				cumulative_total += value
			elif value > best_exclusive:
				best_exclusive = value

		var best_vp = best_exclusive + cumulative_total

		progress_list.append({
			"mission_id": mission["id"],
			"mission_name": mission.get("name", "Unknown"),
			"vp_scored": mission.get("vp_scored", 0),
			"conditions": condition_results,
			"best_vp_available": best_vp,
			"pending_interaction": false,
		})

	return progress_list

func _humanize_condition(check: String, params: Dictionary) -> String:
	"""Convert a condition check ID into human-readable text."""
	match check:
		"units_wholly_in_opponent_deployment_zone":
			var count = params.get("count", 1)
			return "%d+ units in opponent's deployment zone" % count
		"presence_in_table_quarters":
			var count = params.get("count", 1)
			return "Presence in %d+ table quarters" % count
		"units_within_center_no_enemies_within":
			var fr = params.get("friendly_range", 6.0)
			var er = params.get("enemy_range", 6.0)
			if er < fr:
				return "Unit within %d\" of center, no enemies within %d\"" % [int(fr), int(er)]
			return "Unit within %d\" of center, no enemies within %d\"" % [int(fr), int(er)]
		"more_units_wholly_in_no_mans_land_than_opponent":
			return "More units in NML than opponent"
		"control_objectives_opponent_controlled_at_start":
			var count = params.get("count", 1)
			return "Control %d+ opponent's objectives" % count
		"opponent_controlled_no_objectives_at_start_and_you_control_new":
			return "Capture objective (opponent had none)"
		"control_objectives_in_own_deployment_zone":
			var count = params.get("count", 1)
			return "Control %d+ own zone objectives" % count
		"control_objectives_in_no_mans_land":
			var count = params.get("count", 1)
			return "Control %d+ NML objectives" % count
		"control_tempting_target":
			return "Control the tempting target"
		"control_own_zone_and_nml_objectives":
			return "Control own zone + NML objectives"
		"character_models_destroyed_this_turn":
			var count = params.get("count", 1)
			return "%d+ CHARACTER destroyed this turn" % count
		"all_enemy_characters_destroyed":
			return "All enemy CHARACTERs destroyed"
		"enemy_unit_destroyed":
			return "Enemy unit destroyed"
		"infantry_starting_strength_13_plus_destroyed_this_turn":
			var count = params.get("count", 1)
			return "%d+ large INFANTRY destroyed" % count
		"monster_or_vehicle_destroyed_this_turn":
			var count = params.get("count", 1)
			return "%d+ MONSTER/VEHICLE destroyed" % count
		"alpha_target_destroyed_this_turn":
			return "Alpha target destroyed"
		"no_alpha_destroyed_but_gamma_destroyed_this_turn":
			return "Gamma target destroyed (no alpha)"
		"enemy_unit_destroyed_within_objective_range":
			return "Enemy near objective destroyed"
		"locus_established_within_center":
			return "Locus established near center"
		"locus_established_in_opponent_deployment_zone":
			return "Locus in opponent's zone"
		"objectives_cleansed":
			var count = params.get("count", 1)
			return "%d+ objectives cleansed" % count
		"teleport_homer_deployed_in_opponent_zone":
			return "Homer in opponent's zone"
		"teleport_homer_deployed_not_in_opponent_zone":
			return "Homer deployed (not opponent zone)"
		"units_recovered_assets":
			return "Assets recovered"
		"enemy_units_destroyed_this_turn":
			return "Per enemy unit destroyed this turn"
		"enemy_units_destroyed_near_objective_this_turn":
			return "Per enemy unit destroyed near an objective"
		"enemy_character_models_destroyed_this_turn":
			var min_w = int(params.get("min_wounds", 0))
			if min_w > 0:
				return "Per enemy CHARACTER (W%d+) destroyed" % min_w
			return "Per enemy CHARACTER model destroyed"
		"enemy_models_wounds_10_plus_destroyed_this_turn":
			return "Per enemy model (W%d+) destroyed" % int(params.get("min_wounds", 10))
		"enemy_units_13_plus_destroyed_this_turn":
			return "Per enemy unit (%d+ models) destroyed" % int(params.get("min_models", 13))
		"guarded_objectives":
			return "Per objective you guard (control)"
		"no_enemy_units_wholly_in_own_deployment_zone":
			return "No enemy units wholly in your DZ"
		"holds_enemy_home_objective":
			return "Control opponent's home / an expansion objective"
		"units_near_board_edges":
			if params.get("opposite_edges", false):
				return "Units near opposite battlefield edges"
			return "Unit near a battlefield edge, outside your territory"
		"unit_outside_own_dz":
			return "Beacon unit outside your deployment zone"
		"unit_outside_own_territory":
			return "Beacon unit outside your territory"
		"action_completed_this_turn":
			return "%s action completed this turn" % str(params.get("action_name", "Mission"))
		_:
			return check.replace("_", " ").capitalize()

func get_action_missions_for_player(player: int) -> Array:
	"""Get active missions that require a shooting-phase action (e.g. Establish Locus, Cleanse, Deploy Teleport Homer).
	Returns array of mission dicts with requires_action: true and action.phase == 'shooting'."""
	var result = []
	var active = _player_state[str(player)]["active"]
	for mission in active:
		if mission.get("requires_action", false):
			var action_info = mission.get("action", {})
			if action_info.get("phase", "") == "shooting":
				result.append(mission)
	return result

func get_vp_summary() -> Dictionary:
	"""Get VP summary for both players including secondary VP."""
	return {
		"player1": {
			"secondary_vp": _player_state["1"]["secondary_vp"],
			"active_count": _player_state["1"]["active"].size(),
			"deck_remaining": _player_state["1"]["deck"].size(),
			"mode": _player_state["1"].get("mode", "tactical"),
		},
		"player2": {
			"secondary_vp": _player_state["2"]["secondary_vp"],
			"active_count": _player_state["2"]["active"].size(),
			"deck_remaining": _player_state["2"]["deck"].size(),
			"mode": _player_state["2"].get("mode", "tactical"),
		},
	}

# ============================================================================
# GEOMETRY HELPERS
# ============================================================================

func _get_deployment_zone_polygon(player: int) -> PackedVector2Array:
	"""Get the deployment zone polygon for a player (in pixels)."""
	var zones = GameState.state.get("board", {}).get("deployment_zones", [])
	for zone in zones:
		if zone.get("player", 0) == player:
			var poly = PackedVector2Array()
			for point in zone.get("poly", []):
				poly.append(Vector2(
					Measurement.inches_to_px(point.get("x", 0)),
					Measurement.inches_to_px(point.get("y", 0))
				))
			return poly
	return PackedVector2Array()

func _unit_has_excluded_keyword(unit: Dictionary, exclusions: Array) -> bool:
	"""Keyword-only exclusion check (e.g. AIRCRAFT), without the status /
	alive-model filtering of _is_unit_excluded. 'Battle-shocked' entries are
	flag-based and handled by callers."""
	var keywords = unit.get("meta", {}).get("keywords", [])
	for excl in exclusions:
		if excl == "Battle-shocked":
			continue
		for kw in keywords:
			if kw.to_upper() == str(excl).to_upper():
				return true
	return false

func _is_unit_excluded(unit: Dictionary, exclusions: Array) -> bool:
	"""Check if a unit should be excluded based on keywords/flags."""
	var keywords = unit.get("meta", {}).get("keywords", [])
	var flags = unit.get("flags", {})

	for excl in exclusions:
		if excl == "Battle-shocked" and flags.get("battle_shocked", false):
			return true
		for kw in keywords:
			if kw.to_upper() == excl.to_upper():
				return true

	# Also exclude non-deployed units
	var status = unit.get("status", GameStateData.UnitStatus.UNDEPLOYED)
	if status == GameStateData.UnitStatus.UNDEPLOYED:
		return true

	# Exclude units with no alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		return true

	return false

func _is_unit_wholly_in_zone(unit: Dictionary, zone_polygon: PackedVector2Array) -> bool:
	"""Check if ALL alive models in a unit are within a polygon."""
	if zone_polygon.is_empty():
		return false

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			return false
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		if not Geometry2D.is_point_in_polygon(pos, zone_polygon):
			return false

	return true

func _is_unit_wholly_in_rect(unit: Dictionary, rect_min: Vector2, rect_max: Vector2) -> bool:
	"""Check if ALL alive models are within a rectangle."""
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			return false
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		if pos.x < rect_min.x or pos.x > rect_max.x or pos.y < rect_min.y or pos.y > rect_max.y:
			return false
	return true

func _is_unit_far_from_point(unit: Dictionary, point: Vector2, min_distance: float) -> bool:
	"""Check if ALL alive models' base edges are farther than min_distance from a point."""
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			return false
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		var base_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		var edge_dist = max(0.0, pos.distance_to(point) - base_radius)
		if edge_dist <= min_distance:
			return false
	return true

func _has_model_within_range(unit: Dictionary, point: Vector2, max_range: float) -> bool:
	"""Check if ANY alive model's base edge is within range of a point.
	Range is measured from closest part of the base, not center."""
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			continue
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		var base_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		var edge_dist = max(0.0, pos.distance_to(point) - base_radius)
		if edge_dist <= max_range:
			return true
	return false

func _count_units_wholly_in_nml(player: int, exclude: Array = []) -> int:
	"""Count units wholly within No Man's Land."""
	# NML is the area between both deployment zones
	# For simplicity, use the NML definition based on deployment type
	var units = GameState.state.get("units", {})
	var p1_zone = _get_deployment_zone_polygon(1)
	var p2_zone = _get_deployment_zone_polygon(2)
	var count = 0

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if _is_unit_excluded(unit, exclude):
			continue
		# Unit is in NML if wholly NOT in either deployment zone
		var in_p1 = false
		var in_p2 = false
		var all_models_valid = true

		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var pos = model.get("position")
			if pos == null:
				all_models_valid = false
				break
			if pos is Dictionary:
				pos = Vector2(pos.x, pos.y)
			if not p1_zone.is_empty() and Geometry2D.is_point_in_polygon(pos, p1_zone):
				in_p1 = true
			if not p2_zone.is_empty() and Geometry2D.is_point_in_polygon(pos, p2_zone):
				in_p2 = true

		if all_models_valid and not in_p1 and not in_p2:
			count += 1

	return count

# ============================================================================
# UNIT QUERY HELPERS
# ============================================================================

func _has_enemy_infantry_13_plus(player: int) -> bool:
	"""Check if opponent has any INFANTRY with starting strength 13+."""
	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		var is_infantry = false
		for kw in keywords:
			if kw.to_upper() == "INFANTRY":
				is_infantry = true
				break
		if not is_infantry:
			continue
		var starting_strength = unit.get("models", []).size()
		if starting_strength >= 13:
			return true

	return false

func _has_enemy_model_with_wounds(player: int, min_wounds: int) -> bool:
	"""11e Bring it Down when-drawn: does the opponent have any unit on the
	battlefield containing an alive model with W >= min_wounds?"""
	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.UNDEPLOYED:
			continue
		for model in unit.get("models", []):
			if model.get("alive", true) and int(model.get("wounds", 1)) >= min_wounds:
				return true
	return false

func _has_enemy_unit_with_models(player: int, min_models: int) -> bool:
	"""11e A Grievous Blow when-drawn: does the opponent have any unit on the
	battlefield with a Starting Strength of min_models or more (any keyword,
	unlike the 10e INFANTRY-only Cull the Horde check)?"""
	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.UNDEPLOYED:
			continue
		if unit.get("models", []).size() < min_models:
			continue
		for model in unit.get("models", []):
			if model.get("alive", true):
				return true
	return false

func _has_enemy_monster_or_vehicle(player: int) -> bool:
	"""Check if opponent has any MONSTER or VEHICLE units on the battlefield."""
	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.UNDEPLOYED:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		for kw in keywords:
			var upper = kw.to_upper()
			if upper == "MONSTER" or upper == "VEHICLE":
				return true

	return false

func _count_player_units_on_battlefield(player: int) -> int:
	"""Count units from a player on the battlefield."""
	var count = 0
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.UNDEPLOYED:
			continue
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if has_alive:
			count += 1
	return count

func _get_opponent_units_on_battlefield(player: int) -> Array:
	"""Get list of opponent unit IDs on the battlefield."""
	var opponent = 2 if player == 1 else 1
	var result = []
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.UNDEPLOYED:
			continue
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if has_alive:
			result.append(unit_id)
	return result

func _get_no_mans_land_objectives() -> Array:
	"""Get list of objectives in No Man's Land."""
	var result = []
	var all_objectives = GameState.state.get("board", {}).get("objectives", [])
	for obj in all_objectives:
		if obj.get("zone", "") == "no_mans_land":
			result.append(obj)
	return result

# ============================================================================
# SAVE / LOAD
# ============================================================================

func get_save_data() -> Dictionary:
	"""Return secondary mission state for save file persistence."""
	return {
		"player_state": _player_state.duplicate(true),
		"units_destroyed_this_turn": _units_destroyed_this_turn.duplicate(true),
		"objective_control_at_turn_start": _objective_control_at_turn_start.duplicate(true),
		"active_actions": _active_actions.duplicate(true),
	}

func load_save_data(data: Dictionary) -> void:
	"""Restore secondary mission state from save file."""
	if data.is_empty():
		return
	if data.has("player_state"):
		_player_state = data["player_state"].duplicate(true)
		print("SecondaryMissionManager: Restored player_state from save")
	if data.has("units_destroyed_this_turn"):
		_units_destroyed_this_turn = data["units_destroyed_this_turn"].duplicate(true)
	if data.has("objective_control_at_turn_start"):
		_objective_control_at_turn_start = data["objective_control_at_turn_start"].duplicate(true)
	if data.has("active_actions"):
		_active_actions = data["active_actions"].duplicate(true)
	# Restore visual indicators after load
	_restore_tempting_target_visuals()
	_restore_mfd_target_visuals()

func _restore_tempting_target_visuals() -> void:
	"""Re-apply Tempting Target visual indicators after loading save data."""
	for player_key in _player_state:
		var state = _player_state[player_key]
		for mission in state.get("active", []):
			if mission.get("id", "") == "a_tempting_target":
				var target_id = mission.get("mission_data", {}).get("tempting_target_id", "")
				if target_id != "":
					_mark_tempting_target_visual(target_id, int(player_key))

# ============================================================================
# UTILITY
# ============================================================================

func _shuffle_array(arr: Array) -> void:
	"""Fisher-Yates shuffle."""
	for i in range(arr.size() - 1, 0, -1):
		var j = _rng.randi_range(0, i)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp

extends "res://addons/gut/test.gd"

# Tests for BOARDIN' RUSH stratagem implementation (OA-5)
#
# Per Warhammer 40k 10th Edition — Freebooter Krew:
# - BOARDIN' RUSH (Battle Tactic Stratagem, 1 CP)
# - WHEN: Your Movement phase.
# - TARGET: One ORKS unit from your army that has not been selected to move this phase.
# - EFFECT: Until the end of the phase, each time your unit Advances, do not make
#   an Advance roll. Instead, add 6" to the Move characteristic of models in your unit.
#
# These tests verify:
# 1. StratagemManager marks Boardin' Rush as implemented (custom handler)
# 2. Using the stratagem sets effect_boardin_rush flag on the target unit
# 3. MovementPhase._process_begin_advance() skips the D6 roll when flag is set
# 4. The advance uses flat +6" instead of a random roll
# 5. Flag is cleared at end of phase

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_ork_unit(id: String, model_count: int = 5, owner: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": {"x": 500 + i * 40, "y": 500},
			"alive": true,
			"status_effects": []
		})
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Ork Boyz %s" % id,
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {
				"move": 6,
				"toughness": 5,
				"save": 5,
				"wounds": 1,
				"leadership": 7,
				"objective_control": 2
			},
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _setup_game_state_for_movement(unit_id: String = "U_ORK_BOYZ_A") -> Dictionary:
	"""Set up GameState with an Ork unit ready for Movement phase."""
	var unit = _create_ork_unit(unit_id, 5, 1)
	GameState.state.units[unit_id] = unit
	GameState.state.meta.phase = GameStateData.Phase.MOVEMENT
	GameState.state.meta.active_player = 1
	GameState.state.players["1"]["cp"] = 3
	return unit

func _find_boardin_rush_stratagem_id() -> String:
	"""Find the Boardin' Rush stratagem ID from loaded stratagems."""
	for strat_id in StratagemManager.stratagems:
		var strat = StratagemManager.stratagems[strat_id]
		if strat.get("name", "").to_upper() == "BOARDIN' RUSH":
			return strat_id
	return ""

func _load_freebooter_stratagems():
	"""Load Freebooter Krew stratagems for player 1."""
	# Set up player 1 as Orks / Freebooter Krew
	if not GameState.state.has("players"):
		GameState.state["players"] = {"1": {"cp": 3}, "2": {"cp": 3}}
	# Load faction stratagems using the loader
	var loader = FactionStratagemLoaderData.new()
	loader.load_faction_codes()
	var strats = loader.load_faction_stratagems("Orks", "Freebooter Krew")
	for strat in strats:
		StratagemManager.stratagems[strat.id] = strat
		if not StratagemManager._player_faction_stratagems.has("1"):
			StratagemManager._player_faction_stratagems["1"] = []
		StratagemManager._player_faction_stratagems["1"].append(strat.id)
	# Mark custom implementations
	StratagemManager._mark_custom_implemented_stratagems(1)


# ==========================================
# Section 1: Stratagem Registration
# ==========================================

func test_boardin_rush_loaded_from_csv():
	"""Boardin' Rush should be loadable from the Freebooter Krew CSV data."""
	var loader = FactionStratagemLoaderData.new()
	loader.load_faction_codes()
	var strats = loader.load_faction_stratagems("Orks", "Freebooter Krew")
	var found = false
	for s in strats:
		if "BOARDIN" in s.name.to_upper():
			found = true
			assert_eq(s.cp_cost, 1, "CP cost should be 1")
			assert_eq(s.timing.turn, "your", "Should be your turn only")
			assert_eq(s.timing.phase, "movement", "Should be movement phase")
	assert_true(found, "Should find BOARDIN' RUSH in Freebooter Krew stratagems")

func test_boardin_rush_marked_as_implemented():
	"""After _mark_custom_implemented_stratagems, Boardin' Rush should be implemented=true."""
	_load_freebooter_stratagems()
	var strat_id = _find_boardin_rush_stratagem_id()
	assert_ne(strat_id, "", "Should find Boardin' Rush stratagem ID")
	if strat_id != "":
		var strat = StratagemManager.stratagems[strat_id]
		assert_true(strat.get("implemented", false), "Boardin' Rush should be marked as implemented")


# ==========================================
# Section 2: Effect Application
# ==========================================

func test_apply_effects_sets_boardin_rush_flag():
	"""Using Boardin' Rush should set effect_boardin_rush flag on target unit."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_movement()
	var unit_id = "U_ORK_BOYZ_A"

	var strat_id = _find_boardin_rush_stratagem_id()
	assert_ne(strat_id, "", "Should find Boardin' Rush stratagem ID")
	if strat_id == "":
		return

	var result = StratagemManager.use_stratagem(1, strat_id, unit_id)
	assert_true(result.get("success", false), "Stratagem use should succeed")

	# Check the flag was set
	var flags = GameState.state.units[unit_id].get("flags", {})
	assert_true(flags.get("effect_boardin_rush", false), "effect_boardin_rush flag should be set")

func test_boardin_rush_deducts_cp():
	"""Using Boardin' Rush should deduct 1 CP."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_movement()
	var unit_id = "U_ORK_BOYZ_A"
	GameState.state.players["1"]["cp"] = 5

	var strat_id = _find_boardin_rush_stratagem_id()
	if strat_id == "":
		assert_true(false, "Should find Boardin' Rush stratagem ID")
		return

	var cp_before = GameState.state.players["1"]["cp"]
	StratagemManager.use_stratagem(1, strat_id, unit_id)
	var cp_after = GameState.state.players["1"]["cp"]
	assert_eq(cp_before - cp_after, 1, "Should deduct 1 CP")


# ==========================================
# Section 3: Flag Cleanup
# ==========================================

func test_clear_stratagem_flags_removes_boardin_rush():
	"""Clearing Boardin' Rush should remove the effect_boardin_rush flag."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_movement()
	var unit_id = "U_ORK_BOYZ_A"

	var strat_id = _find_boardin_rush_stratagem_id()
	if strat_id == "":
		assert_true(false, "Should find Boardin' Rush stratagem ID")
		return

	# Apply the stratagem
	StratagemManager.use_stratagem(1, strat_id, unit_id)

	# Verify flag is set
	var flags = GameState.state.units[unit_id].get("flags", {})
	assert_true(flags.get("effect_boardin_rush", false), "Flag should be set before clear")

	# Manually call the clear function
	StratagemManager._clear_stratagem_flags(unit_id, strat_id)

	# Verify flag is removed
	flags = GameState.state.units[unit_id].get("flags", {})
	assert_false(flags.get("effect_boardin_rush", false), "Flag should be cleared after cleanup")


# ==========================================
# Section 4: Movement Phase Integration
# ==========================================

func test_advance_with_boardin_rush_uses_flat_6():
	"""When effect_boardin_rush is set, advance should use flat +6 instead of D6."""
	var unit = _setup_game_state_for_movement()
	var unit_id = "U_ORK_BOYZ_A"

	# Set the Boardin' Rush flag directly (simulating stratagem already used)
	GameState.state.units[unit_id].flags["effect_boardin_rush"] = true

	# Create a MovementPhase instance
	var phase = preload("res://phases/MovementPhase.gd").new()
	add_child(phase)

	# Process the advance action
	var action = {
		"type": "BEGIN_ADVANCE",
		"actor_unit_id": unit_id,
		"payload": {}
	}
	var result = phase.process_action(action)

	# The result should succeed
	assert_true(result.get("success", false), "Advance action should succeed")

	# Check the move cap — should be M + 6 = 6 + 6 = 12
	var move_data = phase.active_moves.get(unit_id, {})
	assert_eq(int(move_data.get("move_cap_inches", 0)), 12, "Move cap should be M6 + 6 = 12\"")

	# The advance_roll stored should be 6 (flat)
	assert_eq(move_data.get("advance_roll", 0), 6, "Advance roll should be flat 6")

	# Should NOT have awaiting_reroll (no dice to reroll)
	assert_false(result.get("result_extra", {}).get("awaiting_reroll", false),
		"Should not offer reroll for flat advance")

	phase.queue_free()

func test_advance_without_boardin_rush_rolls_normally():
	"""Without effect_boardin_rush, advance should use normal D6 roll."""
	var unit = _setup_game_state_for_movement()
	var unit_id = "U_ORK_BOYZ_A"

	# Do NOT set the flag — normal advance
	var phase = preload("res://phases/MovementPhase.gd").new()
	add_child(phase)

	var action = {
		"type": "BEGIN_ADVANCE",
		"actor_unit_id": unit_id,
		"payload": {}
	}
	var result = phase.process_action(action)
	assert_true(result.get("success", false), "Advance action should succeed")

	# The move cap could be anything from M+1 to M+6 (D6 roll)
	var move_data = phase.active_moves.get(unit_id, {})
	var move_cap = int(move_data.get("move_cap_inches", 0))
	assert_true(move_cap >= 7 and move_cap <= 12,
		"Normal advance move cap should be between 7 and 12 (M6 + D6), got %d" % move_cap)

	phase.queue_free()

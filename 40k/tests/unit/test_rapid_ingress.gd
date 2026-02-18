extends "res://addons/gut/test.gd"

# Tests for RAPID INGRESS stratagem implementation (T4-7)
#
# RAPID INGRESS (Core – Strategic Ploy Stratagem, 1 CP)
# - WHEN: End of your opponent's Movement phase.
# - TARGET: One unit from your army that is in Reserves.
# - EFFECT: Your unit can arrive on the battlefield as if it were the
#           Reinforcements step of your Movement phase.
# - RESTRICTION: Cannot arrive in a battle round it normally wouldn't be able to.
#                Once per phase.
#
# These tests verify:
# 1. StratagemManager has rapid_ingress defined correctly
# 2. Eligible unit detection (units in reserves)
# 3. CP deduction (1 CP)
# 4. Battle round restriction (>= 2)
# 5. Once-per-phase restriction
# 6. Correct timing (opponent's movement phase)

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_reserve_unit(id: String, model_count: int, owner: int = 2, reserve_type: String = "strategic_reserves") -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": null,
			"alive": true,
			"status_effects": [],
			"weapons": []
		})
	return {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.IN_RESERVES,
		"reserve_type": reserve_type,
		"meta": {
			"name": "Reserve Unit %s" % id,
			"keywords": ["INFANTRY"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 3,
				"wounds": 1,
				"leadership": 7,
				"objective_control": 1
			},
			"weapons": [],
			"abilities": []
		},
		"models": models,
		"flags": {}
	}


# ==========================================
# Tests
# ==========================================

func test_rapid_ingress_stratagem_defined():
	"""Verify the rapid_ingress stratagem is defined in StratagemManager."""
	var strat = StratagemManager.get_stratagem("rapid_ingress")
	assert_false(strat.is_empty(), "rapid_ingress stratagem should be defined")
	assert_eq(strat.id, "rapid_ingress")
	assert_eq(strat.name, "RAPID INGRESS")
	assert_eq(strat.cp_cost, 1)
	assert_eq(strat.timing.turn, "opponent")
	assert_eq(strat.timing.phase, "movement")
	assert_eq(strat.timing.trigger, "end_of_enemy_movement")
	assert_eq(strat.restrictions.once_per, "phase")

func test_rapid_ingress_target_conditions():
	"""Verify the rapid_ingress target requires units in reserves."""
	var strat = StratagemManager.get_stratagem("rapid_ingress")
	assert_eq(strat.target.owner, "friendly")
	assert_true(strat.target.conditions.has("in_reserves"))

func test_rapid_ingress_effect_type():
	"""Verify the rapid_ingress effect is arrive_from_reserves."""
	var strat = StratagemManager.get_stratagem("rapid_ingress")
	assert_eq(strat.effects.size(), 1)
	assert_eq(strat.effects[0].type, "arrive_from_reserves")

func test_rapid_ingress_can_use_with_cp():
	"""Verify can_use_stratagem succeeds when player has enough CP."""
	# Set player 2 to have 2 CP
	GameState.state.players["2"]["cp"] = 2
	# Set active player to 1 (so player 2 is the opponent — correct timing for rapid_ingress)
	GameState.state.meta.active_player = 1
	GameState.state.meta.phase = GameStateData.Phase.MOVEMENT
	GameState.state.meta.battle_round = 2

	# Reset usage history
	StratagemManager._usage_history = {"1": [], "2": []}

	var result = StratagemManager.can_use_stratagem(2, "rapid_ingress")
	assert_true(result.can_use, "Should be able to use rapid_ingress with enough CP: %s" % result.get("reason", ""))

func test_rapid_ingress_cannot_use_without_cp():
	"""Verify can_use_stratagem fails when player has 0 CP."""
	GameState.state.players["2"]["cp"] = 0
	GameState.state.meta.active_player = 1
	GameState.state.meta.phase = GameStateData.Phase.MOVEMENT

	var result = StratagemManager.can_use_stratagem(2, "rapid_ingress")
	assert_false(result.can_use, "Should not be able to use rapid_ingress with 0 CP")
	assert_string_contains(result.reason, "CP")

func test_rapid_ingress_cp_deduction():
	"""Verify using rapid_ingress deducts 1 CP."""
	GameState.state.players["2"]["cp"] = 3
	GameState.state.meta.active_player = 1
	GameState.state.meta.phase = GameStateData.Phase.MOVEMENT
	GameState.state.meta.battle_round = 2
	StratagemManager._usage_history = {"1": [], "2": []}

	var result = StratagemManager.use_stratagem(2, "rapid_ingress", "test_unit")
	assert_true(result.success, "use_stratagem should succeed")
	assert_eq(GameState.state.players["2"]["cp"], 2, "CP should be deducted from 3 to 2")

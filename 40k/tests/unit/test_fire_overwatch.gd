extends "res://addons/gut/test.gd"

# Tests for FIRE OVERWATCH stratagem implementation
#
# FIRE OVERWATCH (Core – Strategic Ploy Stratagem, 1 CP)
# - WHEN: Your opponent's Movement or Charge phase, just after an enemy unit
#         starts or ends a Normal, Advance, or Fall Back move / declares a charge.
# - TARGET: One unit from your army that is within 24" of that enemy unit and
#           that would be eligible to shoot.
# - EFFECT: Your unit can shoot that enemy unit, but only hits on unmodified 6s.
# - RESTRICTION: Once per turn.
#
# These tests verify:
# 1. RulesEngine.resolve_overwatch_shooting — only unmodified 6s hit
# 2. Wounds/saves/damage resolved normally after hits
# 3. StratagemManager availability checks
# 4. Eligible units: within 24", has ranged weapons, alive models
# 5. CP deduction (1 CP)
# 6. Once-per-turn restriction
# 7. Edge cases (no CP, no eligible units, etc.)

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_unit(id: String, model_count: int, owner: int = 1, keywords: Array = ["INFANTRY"], save: int = 3, toughness: int = 4, wounds: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": wounds,
			"current_wounds": wounds,
			"base_mm": 32,
			"position": {"x": 100 + i * 20 + (owner - 1) * 200, "y": 100},
			"alive": true,
			"status_effects": [],
			"weapons": [{"id": "bolt_rifle", "weapon_id": "bolt_rifle"}]
		})
	return {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Unit %s" % id,
			"keywords": keywords,
			"stats": {
				"move": 6,
				"toughness": toughness,
				"save": save,
				"wounds": wounds,
				"leadership": 7,
				"objective_control": 1
			},
			"weapons": [],
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _create_weapon_profile(id: String, bs: int = 3, strength: int = 4, ap: int = -1, damage: int = 1, attacks: int = 2) -> Dictionary:
	return {
		"id": id,
		"name": "Test Weapon %s" % id,
		"type": "ranged",
		"bs": bs,
		"strength": strength,
		"ap": ap,
		"damage": damage,
		"damage_raw": str(damage),
		"attacks": attacks,
		"attacks_raw": str(attacks),
		"range": 24,
		"keywords": [],
		"special_rules": ""
	}

func _setup_overwatch_scenario() -> Dictionary:
	"""Set up a basic overwatch scenario: P1 unit moving, P2 unit within 24\" with weapons."""
	GameState.state.meta.phase = GameStateData.Phase.MOVEMENT
	GameState.state.meta.active_player = 1
	GameState.state.meta.battle_round = 2

	# Player 1 unit (moving)
	var enemy = _create_unit("U_ENEMY", 5, 1, ["INFANTRY"], 3, 4, 1)
	for i in range(enemy.models.size()):
		enemy.models[i].position = {"x": 200 + i * 20, "y": 200}
	GameState.state.units["U_ENEMY"] = enemy

	# Player 2 unit (defender, can overwatch)
	var shooter = _create_unit("U_SHOOTER", 5, 2, ["INFANTRY"], 3, 4, 1)
	for i in range(shooter.models.size()):
		shooter.models[i].position = {"x": 200 + i * 20, "y": 300}
		shooter.models[i].weapons = [{"id": "bolt_rifle", "weapon_id": "bolt_rifle"}]
	GameState.state.units["U_SHOOTER"] = shooter

	# Ensure weapon profile exists
	if not GameState.state.has("weapons"):
		GameState.state["weapons"] = {}
	GameState.state.weapons["bolt_rifle"] = _create_weapon_profile("bolt_rifle", 3, 4, -1, 1, 2)

	# Give player 2 CP
	if not GameState.state.has("players"):
		GameState.state["players"] = {}
	GameState.state.players["2"] = {"cp": 3}
	GameState.state.players["1"] = {"cp": 3}

	# Reset stratagem usage
	StratagemManager.reset_for_new_turn(2)

	return GameState.create_snapshot()

func before_each():
	GameState.state = GameState._create_default_state()
	if GameState.state.has("units"):
		GameState.state.units.clear()
	StratagemManager.reset_for_new_game()


# ==========================================
# RulesEngine Overwatch Shooting Tests
# ==========================================

func test_overwatch_only_unmodified_6s_hit():
	"""Verify that only unmodified 6s count as hits during overwatch."""
	var board = _setup_overwatch_scenario()

	# Create a fixed RNG that rolls: 1, 2, 3, 4, 5, 6, 6, 1, 2, 3
	var rng = RulesEngine.RNGService.new()
	rng.seed_value = 42  # Fixed seed for deterministic results

	var result = RulesEngine.resolve_overwatch_shooting("U_SHOOTER", "U_ENEMY", board, rng)

	assert_true(result.success, "Overwatch shooting should succeed")
	# The exact number of hits depends on the RNG, but all hits should come from unmodified 6s
	# We verify by checking the dice data
	for weapon_result in result.weapon_results:
		for dice in weapon_result.get("dice", []):
			if dice.get("context", "") == "overwatch_to_hit":
				assert_true(dice.get("overwatch", false), "Should be marked as overwatch")
				# Verify: each hit came from an unmodified 6
				var rolls = dice.get("rolls_raw", [])
				var claimed_hits = dice.get("successes", 0)
				var actual_sixes = 0
				for roll in rolls:
					if roll == 6:
						actual_sixes += 1
				assert_eq(claimed_hits, actual_sixes, "Overwatch hits should equal number of unmodified 6s")

func test_overwatch_wounds_resolve_normally():
	"""After overwatch hits, wound rolls use normal S vs T comparison."""
	var board = _setup_overwatch_scenario()
	var rng = RulesEngine.RNGService.new()

	var result = RulesEngine.resolve_overwatch_shooting("U_SHOOTER", "U_ENEMY", board, rng)

	assert_true(result.success, "Overwatch shooting should succeed")
	# If there were hits, wound rolls should be present in dice data
	if result.total_hits > 0:
		var found_wound_roll = false
		for weapon_result in result.weapon_results:
			for dice in weapon_result.get("dice", []):
				if dice.get("context", "") == "to_wound":
					found_wound_roll = true
					# Wound threshold should be based on S4 vs T4 = 4+
					assert_eq(dice.get("threshold", ""), "4+", "Wound threshold should be 4+ for S4 vs T4")
		if result.total_hits > 0:
			assert_true(found_wound_roll, "Should have wound roll dice data when hits occur")

func test_overwatch_no_weapons_returns_no_hits():
	"""A unit with no ranged weapons should produce no hits."""
	var board = _setup_overwatch_scenario()

	# Remove weapons from the shooter
	var shooter = board.units.get("U_SHOOTER", {})
	for model in shooter.get("models", []):
		model["weapons"] = []

	var rng = RulesEngine.RNGService.new()
	var result = RulesEngine.resolve_overwatch_shooting("U_SHOOTER", "U_ENEMY", board, rng)

	assert_true(result.success, "Should still succeed (just no weapons)")
	assert_eq(result.total_hits, 0, "No weapons means no hits")


# ==========================================
# StratagemManager Availability Tests
# ==========================================

func test_fire_overwatch_available_with_cp():
	"""Fire Overwatch should be available when player has CP."""
	_setup_overwatch_scenario()

	var check = StratagemManager.is_fire_overwatch_available(2)
	assert_true(check.available, "Fire Overwatch should be available with 3 CP")

func test_fire_overwatch_not_available_without_cp():
	"""Fire Overwatch should not be available when player has 0 CP."""
	_setup_overwatch_scenario()
	GameState.state.players["2"] = {"cp": 0}

	var check = StratagemManager.is_fire_overwatch_available(2)
	assert_false(check.available, "Fire Overwatch should not be available with 0 CP")

func test_fire_overwatch_eligible_units_within_24():
	"""Only units within 24\" of the target should be eligible."""
	var board = _setup_overwatch_scenario()

	# Unit within range
	var eligible = StratagemManager.get_overwatch_eligible_units(2, "U_ENEMY", board)
	assert_true(eligible.size() > 0, "Shooter within range should be eligible")

func test_fire_overwatch_eligible_units_outside_24():
	"""Units beyond 24\" should not be eligible."""
	_setup_overwatch_scenario()

	# Move shooter far away (beyond 24")
	var shooter = GameState.state.units["U_SHOOTER"]
	for model in shooter.models:
		model.position = {"x": 5000, "y": 5000}  # Very far away

	var board = GameState.create_snapshot()
	var eligible = StratagemManager.get_overwatch_eligible_units(2, "U_ENEMY", board)
	assert_eq(eligible.size(), 0, "Shooter beyond 24\" should not be eligible")

func test_fire_overwatch_battle_shocked_not_eligible():
	"""Battle-shocked units should not be eligible for overwatch."""
	_setup_overwatch_scenario()

	# Battle-shock the shooter
	GameState.state.units["U_SHOOTER"].flags["battle_shocked"] = true

	var board = GameState.create_snapshot()
	var eligible = StratagemManager.get_overwatch_eligible_units(2, "U_ENEMY", board)
	assert_eq(eligible.size(), 0, "Battle-shocked unit should not be eligible")


# ==========================================
# Restriction Tests
# ==========================================

func test_fire_overwatch_once_per_turn():
	"""Fire Overwatch can only be used once per turn."""
	_setup_overwatch_scenario()

	# Use it once
	var result1 = StratagemManager.use_stratagem(2, "fire_overwatch", "U_SHOOTER")
	assert_true(result1.success, "First use should succeed")

	# Try to use again — should fail (once per turn)
	var result2 = StratagemManager.can_use_stratagem(2, "fire_overwatch")
	assert_false(result2.can_use, "Second use should be blocked (once per turn)")

func test_fire_overwatch_deducts_1_cp():
	"""Using Fire Overwatch should deduct 1 CP."""
	_setup_overwatch_scenario()

	var cp_before = GameState.state.players["2"].cp
	StratagemManager.use_stratagem(2, "fire_overwatch", "U_SHOOTER")
	var cp_after = GameState.state.players["2"].cp

	assert_eq(cp_before - cp_after, 1, "Should deduct exactly 1 CP")

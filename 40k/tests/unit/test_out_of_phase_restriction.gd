extends "res://addons/gut/test.gd"

# Tests for P1-59: Out-of-Phase Rules Restriction
#
# Per 10th Edition core rules: "When using out-of-phase rules to perform an action
# as if it were one of your phases, you cannot use any other rules that are normally
# triggered in that phase."
#
# Example: Fire Overwatch lets you shoot during opponent's Movement/Charge phase,
# but you cannot use any shooting-phase-specific abilities (Sentinel Storm,
# Sanctified Flames) or shooting-phase stratagems (Grenade, faction stratagems)
# during that overwatch action.
#
# These tests verify:
# 1. StratagemManager out-of-phase flag set/clear behavior
# 2. Phase-specific stratagems blocked during out-of-phase actions
# 3. Phase-agnostic stratagems (Command Re-roll, phase:"any") still allowed
# 4. Fire Overwatch itself still usable (it initiated the action)
# 5. Flag properly resets after out-of-phase action completes

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

func _setup_basic_state() -> void:
	"""Set up minimal game state for stratagem tests."""
	# Clear existing units
	if GameState.state.has("units"):
		GameState.state.units.clear()
	GameState.state.meta.phase = GameStateData.Phase.MOVEMENT
	GameState.state.meta.active_player = 1
	GameState.state.meta.battle_round = 2

	# Create units for both players
	GameState.state.units["U_MOVER"] = _create_unit("U_MOVER", 5, 1)
	GameState.state.units["U_SHOOTER"] = _create_unit("U_SHOOTER", 5, 2, ["INFANTRY", "GRENADES"])

	# Give both players CP
	if not GameState.state.has("players"):
		GameState.state["players"] = {}
	GameState.state.players["1"] = {"cp": 5}
	GameState.state.players["2"] = {"cp": 5}

	StratagemManager.reset_for_new_game()

func before_each():
	_setup_basic_state()
	# Ensure out-of-phase flag is clear
	StratagemManager.set_out_of_phase_active(false)


# ==========================================
# Flag Set/Clear Tests
# ==========================================

func test_out_of_phase_flag_initially_false():
	"""Out-of-phase flag should default to false."""
	assert_false(StratagemManager.is_out_of_phase_active(),
		"Out-of-phase flag should be false by default")

func test_set_out_of_phase_active():
	"""Setting out-of-phase flag should work correctly."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	assert_true(StratagemManager.is_out_of_phase_active(),
		"Out-of-phase flag should be true after setting")
	assert_eq(StratagemManager.get_out_of_phase_unit_id(), "U_SHOOTER",
		"Out-of-phase unit ID should be set")

func test_clear_out_of_phase_active():
	"""Clearing out-of-phase flag should reset all tracking."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")
	StratagemManager.set_out_of_phase_active(false)

	assert_false(StratagemManager.is_out_of_phase_active(),
		"Out-of-phase flag should be false after clearing")
	assert_eq(StratagemManager.get_out_of_phase_unit_id(), "",
		"Out-of-phase unit ID should be empty after clearing")

func test_reset_for_new_game_clears_out_of_phase():
	"""reset_for_new_game should clear the out-of-phase flag."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")
	StratagemManager.reset_for_new_game()

	assert_false(StratagemManager.is_out_of_phase_active(),
		"reset_for_new_game should clear out-of-phase flag")


# ==========================================
# Stratagem Blocking Tests
# ==========================================

func test_phase_specific_stratagem_blocked_during_out_of_phase():
	"""Phase-specific stratagems (like Grenade) should be blocked during out-of-phase."""
	# Grenade has timing.phase = "shooting" — it's a shooting-phase stratagem
	# During Fire Overwatch (an out-of-phase shooting action), it should be blocked
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	var result = StratagemManager.can_use_stratagem(2, "grenade", "U_SHOOTER")
	assert_false(result.can_use,
		"Grenade stratagem should be blocked during out-of-phase action")
	assert_true(result.reason.find("out-of-phase") != -1,
		"Reason should mention out-of-phase restriction: %s" % result.reason)

func test_command_reroll_allowed_during_out_of_phase():
	"""Command Re-roll (phase:'any') should still be usable during out-of-phase actions."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	var result = StratagemManager.can_use_stratagem(2, "command_re_roll")
	assert_true(result.can_use,
		"Command Re-roll should be allowed during out-of-phase action (phase:'any')")

func test_fire_overwatch_not_blocked_by_own_flag():
	"""Fire Overwatch stratagem itself should not be blocked by the out-of-phase flag."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	var result = StratagemManager.can_use_stratagem(2, "fire_overwatch")
	# Fire Overwatch might fail for other reasons (once per turn, etc.)
	# but NOT because of the out-of-phase restriction
	if result.can_use:
		assert_true(true, "Fire Overwatch is allowed during out-of-phase (good)")
	else:
		assert_true(result.reason.find("out-of-phase") == -1,
			"If Fire Overwatch is blocked, it should NOT be due to out-of-phase restriction: %s" % result.reason)

func test_go_to_ground_blocked_during_out_of_phase():
	"""Go to Ground (phase:'shooting') should be blocked during out-of-phase."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	var result = StratagemManager.can_use_stratagem(2, "go_to_ground", "U_SHOOTER")
	assert_false(result.can_use,
		"Go to Ground should be blocked during out-of-phase action")

func test_smokescreen_blocked_during_out_of_phase():
	"""Smokescreen (phase:'shooting') should be blocked during out-of-phase."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	var result = StratagemManager.can_use_stratagem(2, "smokescreen", "U_SHOOTER")
	assert_false(result.can_use,
		"Smokescreen should be blocked during out-of-phase action")

func test_epic_challenge_blocked_during_out_of_phase():
	"""Epic Challenge (phase:'fight') should be blocked during out-of-phase."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	var result = StratagemManager.can_use_stratagem(2, "epic_challenge", "U_SHOOTER")
	assert_false(result.can_use,
		"Epic Challenge should be blocked during out-of-phase action")

func test_tank_shock_blocked_during_out_of_phase():
	"""Tank Shock (phase:'charge') should be blocked during out-of-phase."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	var result = StratagemManager.can_use_stratagem(2, "tank_shock", "U_SHOOTER")
	assert_false(result.can_use,
		"Tank Shock should be blocked during out-of-phase action")

func test_stratagems_unblocked_after_clearing_flag():
	"""After clearing out-of-phase flag, all stratagems should be available again."""
	# First verify blocking is active
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")
	var blocked_result = StratagemManager.can_use_stratagem(2, "grenade", "U_SHOOTER")
	assert_false(blocked_result.can_use, "Grenade should be blocked while out-of-phase is active")

	# Now clear it
	StratagemManager.set_out_of_phase_active(false)

	# Now the same stratagem should NOT be blocked for out-of-phase reasons
	var result = StratagemManager.can_use_stratagem(2, "grenade", "U_SHOOTER")
	# May fail for other reasons (wrong phase, etc.) but NOT for out-of-phase
	if not result.can_use:
		assert_true(result.reason.find("out-of-phase") == -1,
			"After clearing flag, should not block for out-of-phase: %s" % result.reason)
	else:
		assert_true(true, "Grenade is allowed after clearing out-of-phase flag (good)")

func test_bypass_context_allows_stratagem_during_out_of_phase():
	"""Passing bypass_out_of_phase_check in context should skip the check."""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	# Without bypass, grenade should be blocked
	var blocked = StratagemManager.can_use_stratagem(2, "grenade", "U_SHOOTER")
	assert_false(blocked.can_use, "Grenade should be blocked without bypass")

	# With bypass, should not be blocked for out-of-phase reasons
	var result = StratagemManager.can_use_stratagem(2, "grenade", "U_SHOOTER", {"bypass_out_of_phase_check": true})
	if not result.can_use:
		assert_true(result.reason.find("out-of-phase") == -1,
			"With bypass flag, should not block for out-of-phase: %s" % result.reason)
	else:
		assert_true(true, "Grenade is allowed with bypass context (good)")


# ==========================================
# Integration: Reactive Stratagems Gated
# ==========================================

func test_reactive_shooting_stratagems_blocked_during_out_of_phase():
	"""
	get_reactive_stratagems_for_shooting() should return nothing during out-of-phase
	because the individual can_use_stratagem checks should fail.
	"""
	StratagemManager.set_out_of_phase_active(true, 2, "U_SHOOTER")

	# Set up a scenario where Go to Ground would normally be available
	GameState.state.meta.phase = GameStateData.Phase.SHOOTING
	GameState.state.meta.active_player = 1  # Opponent is shooting

	var results = StratagemManager.get_reactive_stratagems_for_shooting(2, ["U_SHOOTER"])
	assert_eq(results.size(), 0,
		"No reactive stratagems should be available during out-of-phase action")

extends "res://addons/gut/test.gd"

# Tests for T4-10: Mission Selection Variety
# Verifies MissionData registry, MissionManager multi-mission support,
# and correct scoring dispatch for different primary missions.

const GameStateData = preload("res://autoloads/GameState.gd")

var game_state: Node
var mission_manager: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	game_state = AutoloadHelper.get_game_state()
	mission_manager = get_node_or_null("/root/MissionManager")
	assert_not_null(game_state, "GameState autoload must be available")
	assert_not_null(mission_manager, "MissionManager autoload must be available")

# ==========================================
# 1. MissionData Registry Tests
# ==========================================

func test_mission_data_has_all_missions():
	"""Verify all expected missions are defined in MissionData."""
	var expected = [
		"take_and_hold", "supply_drop", "purge_the_foe",
		"scorched_earth", "the_ritual", "sites_of_power",
		"terraform", "linchpin", "hidden_supplies"
	]
	var all_ids = MissionData.get_all_mission_ids()
	for mission_id in expected:
		assert_true(mission_id in all_ids, "MissionData should contain '%s'" % mission_id)

func test_mission_data_get_mission_returns_valid():
	"""Verify get_mission returns valid data for known mission."""
	var mission = MissionData.get_mission("take_and_hold")
	assert_false(mission.is_empty(), "take_and_hold mission should not be empty")
	assert_eq(mission.id, "take_and_hold", "Mission id should match")
	assert_eq(mission.name, "Take and Hold", "Mission name should match")
	assert_eq(mission.scoring_type, "hold_objectives", "Scoring type should be hold_objectives")
	assert_eq(mission.start_round, 2, "Start round should be 2")
	assert_eq(mission.max_vp, 50, "Max VP should be 50")

func test_mission_data_get_unknown_returns_empty():
	"""Verify get_mission returns empty dict for unknown mission."""
	var mission = MissionData.get_mission("nonexistent_mission")
	assert_true(mission.is_empty(), "Unknown mission should return empty dict")

func test_mission_data_purge_the_foe_structure():
	"""Verify Purge the Foe has correct scoring structure."""
	var mission = MissionData.get_mission("purge_the_foe")
	assert_false(mission.is_empty(), "purge_the_foe should exist")
	assert_eq(mission.scoring_type, "hold_and_kill", "Scoring type should be hold_and_kill")
	assert_true(mission.scoring.has("hold_any_vp"), "Should have hold_any_vp")
	assert_true(mission.scoring.has("kill_any_vp"), "Should have kill_any_vp")
	assert_true("kill_tracking" in mission.special_rules, "Should have kill_tracking special rule")

func test_mission_data_supply_drop_structure():
	"""Verify Supply Drop has correct scoring structure."""
	var mission = MissionData.get_mission("supply_drop")
	assert_false(mission.is_empty(), "supply_drop should exist")
	assert_eq(mission.scoring_type, "supply_drop", "Scoring type should be supply_drop")
	assert_eq(mission.objectives_used, "no_mans_land", "Should only use NML objectives")
	assert_true("nml_only_scoring" in mission.special_rules, "Should have nml_only_scoring")
	assert_true("objective_removal" in mission.special_rules, "Should have objective_removal")

func test_mission_data_linchpin_structure():
	"""Verify Linchpin has center bonus."""
	var mission = MissionData.get_mission("linchpin")
	assert_false(mission.is_empty(), "linchpin should exist")
	assert_eq(mission.scoring_type, "hold_objectives", "Scoring type should be hold_objectives")
	assert_true(mission.scoring.has("vp_center_bonus"), "Should have vp_center_bonus")
	assert_gt(mission.scoring.vp_center_bonus, 0, "Center bonus should be > 0")
	assert_true("center_bonus" in mission.special_rules, "Should have center_bonus special rule")

func test_mission_data_display_name():
	"""Verify display name lookup."""
	assert_eq(MissionData.get_display_name("take_and_hold"), "Take and Hold")
	assert_eq(MissionData.get_display_name("purge_the_foe"), "Purge the Foe")
	assert_eq(MissionData.get_display_name("nonexistent"), "nonexistent")

func test_mission_data_has_special_rule():
	"""Verify special rule checking."""
	assert_true(MissionData.has_special_rule("purge_the_foe", "kill_tracking"), "Purge should have kill_tracking")
	assert_false(MissionData.has_special_rule("take_and_hold", "kill_tracking"), "Take and Hold should not have kill_tracking")

func test_mission_data_all_missions_have_required_fields():
	"""Verify all missions have required fields."""
	var all_ids = MissionData.get_all_mission_ids()
	for mission_id in all_ids:
		var m = MissionData.get_mission(mission_id)
		assert_true(m.has("id"), "Mission '%s' should have 'id'" % mission_id)
		assert_true(m.has("name"), "Mission '%s' should have 'name'" % mission_id)
		assert_true(m.has("scoring_type"), "Mission '%s' should have 'scoring_type'" % mission_id)
		assert_true(m.has("start_round"), "Mission '%s' should have 'start_round'" % mission_id)
		assert_true(m.has("max_vp"), "Mission '%s' should have 'max_vp'" % mission_id)
		assert_true(m.has("scoring"), "Mission '%s' should have 'scoring'" % mission_id)
		assert_true(m.has("special_rules"), "Mission '%s' should have 'special_rules'" % mission_id)

# ==========================================
# 2. MissionManager Initialization Tests
# ==========================================

func test_initialize_take_and_hold():
	"""Verify MissionManager can initialize Take and Hold."""
	game_state.state.meta["game_config"] = {"mission": "take_and_hold"}
	mission_manager.initialize_mission("take_and_hold")
	assert_eq(mission_manager.get_current_mission_id(), "take_and_hold")
	assert_eq(mission_manager.get_current_mission_name(), "Take and Hold")

func test_initialize_purge_the_foe():
	"""Verify MissionManager can initialize Purge the Foe."""
	mission_manager.initialize_mission("purge_the_foe")
	assert_eq(mission_manager.get_current_mission_id(), "purge_the_foe")
	assert_eq(mission_manager.get_current_mission_name(), "Purge the Foe")
	assert_eq(mission_manager.current_mission.scoring_type, "hold_and_kill")

func test_initialize_supply_drop():
	"""Verify MissionManager can initialize Supply Drop."""
	mission_manager.initialize_mission("supply_drop")
	assert_eq(mission_manager.get_current_mission_id(), "supply_drop")
	assert_eq(mission_manager.get_current_mission_name(), "Supply Drop")
	assert_eq(mission_manager.current_mission.scoring_type, "supply_drop")

func test_initialize_linchpin():
	"""Verify MissionManager can initialize Linchpin."""
	mission_manager.initialize_mission("linchpin")
	assert_eq(mission_manager.get_current_mission_id(), "linchpin")
	assert_eq(mission_manager.get_current_mission_name(), "Linchpin")

func test_initialize_all_missions():
	"""Verify all registered missions can be initialized without error."""
	var all_ids = MissionData.get_all_mission_ids()
	for mission_id in all_ids:
		mission_manager.initialize_mission(mission_id)
		assert_eq(mission_manager.get_current_mission_id(), mission_id,
				  "Current mission should be '%s' after initialization" % mission_id)

func test_unknown_mission_falls_back_to_take_and_hold():
	"""Verify unknown mission ID falls back to Take and Hold."""
	mission_manager.initialize_mission("nonexistent_mission_xyz")
	assert_eq(mission_manager.get_current_mission_id(), "take_and_hold",
			  "Unknown mission should fall back to take_and_hold")

# ==========================================
# 3. Kill Tracking Tests
# ==========================================

func test_kill_tracking_records():
	"""Verify kill tracking increments correctly."""
	mission_manager.initialize_mission("purge_the_foe")
	mission_manager.reset_round_kills()
	assert_eq(mission_manager._kills_this_round["1"], 0, "P1 kills should start at 0")
	assert_eq(mission_manager._kills_this_round["2"], 0, "P2 kills should start at 0")

	mission_manager.record_unit_destroyed(1)
	assert_eq(mission_manager._kills_this_round["1"], 1, "P1 kills should be 1 after recording")

	mission_manager.record_unit_destroyed(1)
	assert_eq(mission_manager._kills_this_round["1"], 2, "P1 kills should be 2 after second recording")

	mission_manager.record_unit_destroyed(2)
	assert_eq(mission_manager._kills_this_round["2"], 1, "P2 kills should be 1")

func test_kill_tracking_resets():
	"""Verify kill tracking resets correctly."""
	mission_manager.initialize_mission("purge_the_foe")
	mission_manager.record_unit_destroyed(1)
	mission_manager.record_unit_destroyed(2)
	mission_manager.reset_round_kills()
	assert_eq(mission_manager._kills_this_round["1"], 0, "P1 kills should be 0 after reset")
	assert_eq(mission_manager._kills_this_round["2"], 0, "P2 kills should be 0 after reset")

# ==========================================
# 4. Mission Meta Stored in GameState
# ==========================================

func test_mission_type_stored_in_gamestate_meta():
	"""Verify mission type is saved to GameState meta."""
	mission_manager.initialize_mission("supply_drop")
	var stored = game_state.state.meta.get("mission_type", "")
	assert_eq(stored, "supply_drop", "GameState meta should store mission_type")

# ==========================================
# 5. Scoring Dispatch Tests
# ==========================================

func test_scoring_does_not_crash_for_any_mission():
	"""Verify score_primary_objectives() doesn't crash for any mission type."""
	var all_ids = MissionData.get_all_mission_ids()
	for mission_id in all_ids:
		mission_manager.initialize_mission(mission_id)
		# Set up minimal state for scoring
		game_state.state.meta["battle_round"] = 2
		game_state.state.meta["active_player"] = 1
		# This should not crash for any mission type
		mission_manager.score_primary_objectives()
		# If we get here, no crash occurred
		assert_true(true, "score_primary_objectives did not crash for '%s'" % mission_id)

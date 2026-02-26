extends SceneTree

# Test script for SecondaryMissionManager deck mechanics + New Orders stratagem
# Run: godot --headless --script res://tests/test_secondary_missions.gd

const SecondaryMissionData = preload("res://scripts/data/SecondaryMissionData.gd")

var _pass_count = 0
var _fail_count = 0

func _init():
	print("=== Secondary Mission & New Orders Tests ===\n")

	test_mission_data()
	test_deck_building()
	test_card_categories()
	test_mission_scoring_structure()
	test_when_drawn_conditions()
	test_new_orders_stratagem_definition()
	test_secondary_mission_manager_init()
	test_new_orders_flow()
	test_voluntary_discard_flow()
	test_command_phase_integration()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED!")
	else:
		print("ALL TESTS PASSED!")
	quit()

func assert_eq(actual, expected, description: String) -> void:
	if actual == expected:
		_pass_count += 1
		print("  PASS: %s" % description)
	else:
		_fail_count += 1
		print("  FAIL: %s (expected %s, got %s)" % [description, str(expected), str(actual)])

func assert_true(condition: bool, description: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % description)
	else:
		_fail_count += 1
		print("  FAIL: %s" % description)

func assert_not_empty(value, description: String) -> void:
	var is_empty = false
	if value is Dictionary:
		is_empty = value.is_empty()
	elif value is Array:
		is_empty = value.is_empty()
	elif value is String:
		is_empty = value.is_empty()
	else:
		is_empty = (value == null)

	if not is_empty:
		_pass_count += 1
		print("  PASS: %s" % description)
	else:
		_fail_count += 1
		print("  FAIL: %s (was empty)" % description)

# ============================================================================
# 1. Mission Data Tests
# ============================================================================

func test_mission_data():
	print("--- 1. Mission Data Tests ---")

	# Total missions count
	var all = SecondaryMissionData.get_all_missions()
	assert_true(all.size() >= 18, "At least 18 missions defined (got %d)" % all.size())

	# Check specific cards exist and have required fields
	var bel = SecondaryMissionData.get_mission_by_id("behind_enemy_lines")
	assert_not_empty(bel, "Behind Enemy Lines exists")
	assert_eq(bel.get("number", 0), 1, "Behind Enemy Lines is card 1")
	assert_eq(bel.get("category", ""), "Shadow Operations", "Behind Enemy Lines category")
	assert_true(bel.has("scoring"), "Behind Enemy Lines has scoring")
	assert_true(bel.has("when_drawn"), "Behind Enemy Lines has when_drawn")

	var no_prisoners = SecondaryMissionData.get_mission_by_id("no_prisoners")
	assert_not_empty(no_prisoners, "No Prisoners exists")
	assert_eq(no_prisoners.get("scoring", {}).get("when", ""), SecondaryMissionData.TIMING_WHILE_ACTIVE, "No Prisoners is while_active scoring")

	var assassination = SecondaryMissionData.get_mission_by_id("assassination")
	assert_not_empty(assassination, "Assassination exists")
	assert_eq(assassination.get("scoring", {}).get("when", ""), SecondaryMissionData.TIMING_END_OF_EITHER_TURN, "Assassination scored end of either turn")

	# Invalid ID returns empty dict
	var invalid = SecondaryMissionData.get_mission_by_id("nonexistent")
	assert_eq(invalid.size(), 0, "Invalid ID returns empty dict")

	# All missions have required fields
	var required_fields = ["id", "name", "number", "category", "scoring"]
	for mission_id in all:
		var mission = all[mission_id]
		for field in required_fields:
			assert_true(mission.has(field), "%s has field '%s'" % [mission_id, field])

# ============================================================================
# 2. Deck Building Tests
# ============================================================================

func test_deck_building():
	print("\n--- 2. Deck Building Tests ---")

	# get_mission_ids_for_deck returns all mission IDs for a tactical deck
	var ids = SecondaryMissionData.get_mission_ids_for_deck(false)
	assert_true(ids.size() >= 18, "Standard deck has at least 18 card IDs (got %d)" % ids.size())

	# Each ID is a valid mission
	for mission_id in ids:
		var mission = SecondaryMissionData.get_mission_by_id(mission_id)
		assert_not_empty(mission, "Deck card '%s' has valid mission data" % mission_id)

	# No duplicate IDs in deck
	var unique_ids = {}
	for id in ids:
		unique_ids[id] = true
	assert_eq(unique_ids.size(), ids.size(), "No duplicate IDs in deck")

# ============================================================================
# 3. Card Categories Tests
# ============================================================================

func test_card_categories():
	print("\n--- 3. Card Categories Tests ---")

	# Test get_missions_by_category
	var shadow_ops = SecondaryMissionData.get_missions_by_category("Shadow Operations")
	assert_true(shadow_ops.size() > 0, "Shadow Operations category has missions")

	var purge = SecondaryMissionData.get_missions_by_category("Purge the Enemy")
	assert_true(purge.size() > 0, "Purge the Enemy category has missions")

	var battlefield = SecondaryMissionData.get_missions_by_category("Battlefield Supremacy")
	assert_true(battlefield.size() > 0, "Battlefield Supremacy category has missions")

	var strategic = SecondaryMissionData.get_missions_by_category("Strategic Conquests")
	assert_true(strategic.size() > 0, "Strategic Conquests category has missions")

	# Empty category returns empty
	var empty = SecondaryMissionData.get_missions_by_category("nonexistent_category")
	assert_eq(empty.size(), 0, "Nonexistent category returns empty array")

# ============================================================================
# 4. Mission Scoring Structure Tests
# ============================================================================

func test_mission_scoring_structure():
	print("\n--- 4. Mission Scoring Structure Tests ---")

	var all = SecondaryMissionData.get_all_missions()

	for mission_id in all:
		var mission = all[mission_id]
		var scoring = mission.get("scoring", {})

		# All missions have a timing
		var when = scoring.get("when", "")
		assert_true(when != "", "%s has scoring timing" % mission_id)

		# All missions have conditions
		var conditions = scoring.get("conditions", [])
		assert_true(conditions.size() > 0, "%s has scoring conditions" % mission_id)

		# All conditions have a check and vp
		for condition in conditions:
			assert_true(condition.has("check"), "%s condition has 'check'" % mission_id)
			assert_true(condition.has("vp"), "%s condition has 'vp'" % mission_id)
			assert_true(condition.get("vp", 0) > 0, "%s condition VP > 0" % mission_id)

	# Specific scoring values
	var bel = SecondaryMissionData.get_mission_by_id("behind_enemy_lines")
	var bel_conditions = bel.get("scoring", {}).get("conditions", [])
	# First condition (highest) should be 5 VP for 2 units
	assert_eq(bel_conditions[0].get("vp", 0), 5, "Behind Enemy Lines max VP = 5")
	assert_eq(bel_conditions[1].get("vp", 0), 2, "Behind Enemy Lines min VP = 2")

# ============================================================================
# 5. When-Drawn Conditions Tests
# ============================================================================

func test_when_drawn_conditions():
	print("\n--- 5. When-Drawn Conditions Tests ---")

	# Behind Enemy Lines has mandatory shuffle back in round 1
	var bel = SecondaryMissionData.get_mission_by_id("behind_enemy_lines")
	var when_drawn = bel.get("when_drawn", {})
	assert_eq(when_drawn.get("condition", ""), "first_battle_round", "Behind Enemy Lines shuffles back in round 1")
	assert_eq(when_drawn.get("effect", ""), SecondaryMissionData.EFFECT_MANDATORY_SHUFFLE_BACK, "Behind Enemy Lines mandatory shuffle back")

	# Bring it Down discards if no enemy monster/vehicle
	var bid = SecondaryMissionData.get_mission_by_id("bring_it_down")
	var bid_when = bid.get("when_drawn", {})
	assert_eq(bid_when.get("condition", ""), "no_enemy_monster_or_vehicle", "Bring it Down checks for enemy monsters/vehicles")

	# Marked for Death requires opponent interaction
	var mfd = SecondaryMissionData.get_mission_by_id("marked_for_death")
	var mfd_when = mfd.get("when_drawn", {})
	assert_eq(mfd_when.get("condition", ""), "opponent_selects_units", "Marked for Death requires opponent unit selection")

	# A Tempting Target requires opponent objective selection
	var att = SecondaryMissionData.get_mission_by_id("a_tempting_target")
	var att_when = att.get("when_drawn", {})
	assert_eq(att_when.get("condition", ""), "opponent_selects_objective", "A Tempting Target requires opponent objective selection")

	# Some missions have no when-drawn conditions
	var engage = SecondaryMissionData.get_mission_by_id("engage_on_all_fronts")
	var engage_when = engage.get("when_drawn", {})
	assert_true(engage_when.is_empty(), "Engage on All Fronts has no when-drawn condition")

# ============================================================================
# 6. New Orders Stratagem Definition Tests
# ============================================================================

func test_new_orders_stratagem_definition():
	print("\n--- 6. New Orders Stratagem Definition Tests ---")

	# Load StratagemManager to check stratagem definitions
	var strat_script = load("res://autoloads/StratagemManager.gd")
	assert_true(strat_script != null, "StratagemManager.gd loads successfully")

	# Instantiate to access stratagems
	var strat_mgr = strat_script.new()
	strat_mgr._define_stratagems()

	# Check New Orders exists
	var new_orders = strat_mgr.stratagems.get("new_orders", {})
	assert_not_empty(new_orders, "New Orders stratagem is defined")

	# CP cost
	assert_eq(new_orders.get("cp_cost", 0), 1, "New Orders costs 1 CP")

	# Timing
	var timing = new_orders.get("timing", {})
	assert_eq(timing.get("turn", ""), "your", "New Orders is used on your turn")
	assert_eq(timing.get("phase", ""), "command", "New Orders is used in Command phase")

	# Restriction
	var restrictions = new_orders.get("restrictions", {})
	assert_eq(restrictions.get("once_per", ""), "battle", "New Orders is once per battle")

	# Effect
	var effects = new_orders.get("effects", [])
	assert_true(effects.size() > 0, "New Orders has effects defined")
	assert_eq(effects[0].get("type", ""), "discard_and_draw_secondary", "New Orders effect is discard_and_draw_secondary")

	# Target type
	var target = new_orders.get("target", {})
	assert_eq(target.get("type", ""), "secondary_mission", "New Orders targets secondary missions")

	# Clean up
	strat_mgr.free()

# ============================================================================
# 7. SecondaryMissionManager Initialization Tests
# ============================================================================

func test_secondary_mission_manager_init():
	print("\n--- 7. SecondaryMissionManager Init Tests ---")

	# Create a fresh manager instance
	var mgr_script = load("res://autoloads/SecondaryMissionManager.gd")
	assert_true(mgr_script != null, "SecondaryMissionManager.gd loads successfully")

	var mgr = mgr_script.new()

	# Not initialized by default
	assert_true(not mgr.is_initialized(1), "Player 1 not initialized by default")
	assert_true(not mgr.is_initialized(2), "Player 2 not initialized by default")

	# Setup tactical deck
	mgr.setup_tactical_deck(1)
	assert_true(mgr.is_initialized(1), "Player 1 initialized after setup_tactical_deck")
	assert_true(not mgr.is_initialized(2), "Player 2 still not initialized")

	# Deck should have 18 cards
	assert_eq(mgr.get_deck_size(1), 18, "Player 1 deck has 18 cards after init")
	assert_eq(mgr.get_discard_size(1), 0, "Player 1 discard is empty after init")
	assert_eq(mgr.get_secondary_vp(1), 0, "Player 1 has 0 secondary VP after init")

	# Active missions should be empty (not drawn yet)
	var active = mgr.get_active_missions(1)
	assert_eq(active.size(), 0, "Player 1 has 0 active missions before draw")

	# Setup player 2
	mgr.setup_tactical_deck(2)
	assert_true(mgr.is_initialized(2), "Player 2 initialized after setup_tactical_deck")
	assert_eq(mgr.get_deck_size(2), 18, "Player 2 deck has 18 cards after init")

	# VP summary
	var summary = mgr.get_vp_summary()
	assert_eq(summary.player1.secondary_vp, 0, "VP summary shows 0 for P1")
	assert_eq(summary.player2.secondary_vp, 0, "VP summary shows 0 for P2")
	assert_eq(summary.player1.deck_remaining, 18, "VP summary shows 18 deck for P1")

	# initialize_for_game resets everything
	mgr.initialize_for_game()
	assert_true(not mgr.is_initialized(1), "Player 1 not initialized after reset")

	mgr.free()

# ============================================================================
# 8. New Orders Flow Tests
# ============================================================================

func test_new_orders_flow():
	print("\n--- 8. New Orders Flow Tests ---")

	var mgr_script = load("res://autoloads/SecondaryMissionManager.gd")
	var mgr = mgr_script.new()

	# Setup and manually add active missions for testing
	mgr.setup_tactical_deck(1)

	# Simulate having 2 active missions by manipulating internal state
	var state = mgr._player_state["1"]
	var first_id = state["deck"].pop_front()
	var second_id = state["deck"].pop_front()

	var first_data = SecondaryMissionData.get_mission_by_id(first_id)
	var second_data = SecondaryMissionData.get_mission_by_id(second_id)

	state["active"] = [
		mgr._create_active_mission(first_data),
		mgr._create_active_mission(second_data),
	]

	var initial_deck_size = mgr.get_deck_size(1)
	var initial_active_count = mgr.get_active_missions(1).size()
	assert_eq(initial_active_count, 2, "Player 1 starts with 2 active missions")

	# Use New Orders to discard first mission and draw a new one
	var result = mgr.use_new_orders(1, 0)
	assert_true(result.get("success", false), "New Orders succeeded")
	assert_not_empty(result.get("discarded", ""), "New Orders reports discarded mission name")

	# After New Orders: still 2 active (1 discarded + 1 drawn), deck shrunk by 1
	var new_active = mgr.get_active_missions(1)
	assert_eq(new_active.size(), 2, "Still have 2 active missions after New Orders")

	# The discarded mission should be in the discard pile
	assert_true(mgr.get_discard_size(1) >= 1, "Discard pile has at least 1 card")

	# Deck should be smaller
	assert_true(mgr.get_deck_size(1) < initial_deck_size, "Deck is smaller after New Orders draw")

	# Invalid index
	var bad_result = mgr.use_new_orders(1, 99)
	assert_true(not bad_result.get("success", true), "New Orders fails with invalid index")

	mgr.free()

# ============================================================================
# 9. Voluntary Discard Flow Tests
# ============================================================================

func test_voluntary_discard_flow():
	print("\n--- 9. Voluntary Discard Flow Tests ---")

	var mgr_script = load("res://autoloads/SecondaryMissionManager.gd")
	var mgr = mgr_script.new()

	mgr.setup_tactical_deck(1)

	# Manually add an active mission
	var state = mgr._player_state["1"]
	var mission_id = state["deck"].pop_front()
	var mission_data = SecondaryMissionData.get_mission_by_id(mission_id)
	state["active"] = [mgr._create_active_mission(mission_data)]

	assert_eq(mgr.get_active_missions(1).size(), 1, "Player has 1 active mission")

	# Voluntary discard (note: CP gain requires GameState which isn't available in this test)
	var result = mgr.voluntary_discard(1, 0)
	assert_true(result.get("success", false), "Voluntary discard succeeded")
	assert_not_empty(result.get("discarded", ""), "Voluntary discard reports mission name")

	# Mission removed from active
	assert_eq(mgr.get_active_missions(1).size(), 0, "Active missions empty after discard")

	# Mission added to discard pile
	assert_true(mgr.get_discard_size(1) >= 1, "Discard pile has the discarded card")

	# Invalid index
	var bad_result = mgr.voluntary_discard(1, 0)
	assert_true(not bad_result.get("success", true), "Voluntary discard fails on empty active list")

	mgr.free()

# ============================================================================
# 10. Command Phase Integration Tests
# ============================================================================

func test_command_phase_integration():
	print("\n--- 10. Command Phase Integration Tests ---")

	# Test that CommandPhase can be loaded and has the correct action types
	var phase_script = load("res://phases/CommandPhase.gd")
	assert_true(phase_script != null, "CommandPhase.gd loads successfully")

	# Test that the phase handles these action types in process_action
	# (We verify by checking the source has these handlers)
	var source = phase_script.source_code
	assert_true(source.find("USE_NEW_ORDERS") != -1, "CommandPhase handles USE_NEW_ORDERS action")
	assert_true(source.find("RESOLVE_MARKED_FOR_DEATH") != -1, "CommandPhase handles RESOLVE_MARKED_FOR_DEATH")
	assert_true(source.find("RESOLVE_TEMPTING_TARGET") != -1, "CommandPhase handles RESOLVE_TEMPTING_TARGET")

	# Voluntary discard should NOT be in CommandPhase — it belongs in ScoringPhase (end of turn)
	assert_true(source.find("VOLUNTARY_DISCARD") == -1, "CommandPhase does NOT offer voluntary discard (moved to ScoringPhase)")

	# Test that validate_action covers secondary mission types
	assert_true(source.find("_validate_use_new_orders") != -1, "CommandPhase validates New Orders")

	# Test that secondary mission deck init happens on phase entry
	assert_true(source.find("setup_tactical_deck") != -1, "CommandPhase initializes tactical decks")
	assert_true(source.find("draw_missions_to_hand") != -1, "CommandPhase draws missions to hand")

	# Test that get_available_actions offers New Orders (but NOT voluntary discard)
	assert_true(source.find("USE_NEW_ORDERS") != -1, "CommandPhase offers New Orders action")

	# Test CommandController has UI for secondary missions
	var controller_script = load("res://scripts/CommandController.gd")
	assert_true(controller_script != null, "CommandController.gd loads successfully")

	var ctrl_source = controller_script.source_code
	assert_true(ctrl_source.find("_setup_secondary_missions_section") != -1, "CommandController has secondary missions UI")
	assert_true(ctrl_source.find("_add_new_orders_button") != -1, "CommandController has New Orders button")
	assert_true(ctrl_source.find("_add_mission_card_ui") != -1, "CommandController has mission card UI")
	assert_true(ctrl_source.find("_on_voluntary_discard_pressed") == -1, "CommandController does NOT have discard button (moved to ScoringPhase)")
	assert_true(ctrl_source.find("_on_new_orders_pressed") != -1, "CommandController handles New Orders button")

	# Test ScoringPhase scores secondary missions
	var scoring_script = load("res://phases/ScoringPhase.gd")
	assert_true(scoring_script != null, "ScoringPhase.gd loads successfully")

	var scoring_source = scoring_script.source_code
	assert_true(scoring_source.find("score_secondary_missions_for_player") != -1, "ScoringPhase scores secondary missions")
	assert_true(scoring_source.find("DISCARD_SECONDARY") != -1, "ScoringPhase offers voluntary discard at end of turn")
	assert_true(scoring_source.find("voluntary_discard") != -1, "ScoringPhase handles voluntary discard")

	# Test that dialogs exist for mission interactions
	var mfd_dialog = load("res://dialogs/MarkedForDeathDialog.gd")
	assert_true(mfd_dialog != null, "MarkedForDeathDialog.gd exists")

	var tt_dialog = load("res://dialogs/TemptingTargetDialog.gd")
	assert_true(tt_dialog != null, "TemptingTargetDialog.gd exists")

	print("\n  All command phase integration points verified!")

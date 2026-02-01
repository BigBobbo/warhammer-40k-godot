extends "res://addons/gut/test.gd"
const GameStateData = preload("res://autoloads/GameState.gd")

# test_mission_scoring.gd - Unit tests for mission scoring system
# Tests objective placement, control calculation, and VP scoring

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Reset game state for each test
	GameState.initialize_default_state()
	
	# Ensure MissionManager is initialized
	if MissionManager:
		MissionManager.initialize_default_mission()

func test_objective_placement():
	# Test that 5 objectives are placed correctly for Strike Force deployment
	var objectives = GameState.state.board.get("objectives", [])
	assert_eq(objectives.size(), 5, "Should have 5 objectives for Strike Force")
	
	# Check center objective position (22", 30")
	var center = objectives[0]
	assert_eq(center.id, "obj_center", "First objective should be center")
	var expected_center = Vector2(Measurement.inches_to_px(22), Measurement.inches_to_px(30))
	assert_eq(center.position, expected_center, "Center objective at correct position")
	
	# Check top-left objective (10", 14")
	var tl = objectives[1]
	assert_eq(tl.id, "obj_tl", "Second objective should be top-left")
	var expected_tl = Vector2(Measurement.inches_to_px(10), Measurement.inches_to_px(14))
	assert_eq(tl.position, expected_tl, "Top-left objective at correct position")
	
	# Check all objectives have 40mm radius
	for obj in objectives:
		assert_eq(obj.radius_mm, 40, "All objectives should be 40mm")

func test_objective_control_uncontrolled():
	# Test that objectives start uncontrolled
	MissionManager.check_all_objectives()
	
	for obj_id in MissionManager.objective_control_state:
		assert_eq(MissionManager.objective_control_state[obj_id], 0, 
				   "Objective %s should start uncontrolled" % obj_id)

func test_objective_control_single_unit():
	# Place a unit near the center objective
	var test_unit = {
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 2}},
		"models": [
			{"position": Vector2(Measurement.inches_to_px(22), Measurement.inches_to_px(30)), "alive": true}
		],
		"flags": {}
	}
	GameState.state.units["TEST_UNIT"] = test_unit
	
	# Check objectives
	MissionManager.check_all_objectives()
	
	# Center should be controlled by Player 1
	assert_eq(MissionManager.objective_control_state["obj_center"], 1,
			  "Center objective should be controlled by Player 1")
	
	# Other objectives should remain uncontrolled
	assert_eq(MissionManager.objective_control_state["obj_tl"], 0,
			  "Top-left objective should remain uncontrolled")

func test_objective_control_contested():
	# Place units from both players near the center objective
	var p1_unit = {
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 2}},
		"models": [
			{"position": Vector2(Measurement.inches_to_px(22), Measurement.inches_to_px(30)), "alive": true}
		],
		"flags": {}
	}
	
	var p2_unit = {
		"owner": 2,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 2}},
		"models": [
			{"position": Vector2(Measurement.inches_to_px(22.5), Measurement.inches_to_px(30)), "alive": true}
		],
		"flags": {}
	}
	
	GameState.state.units["P1_UNIT"] = p1_unit
	GameState.state.units["P2_UNIT"] = p2_unit
	
	MissionManager.check_all_objectives()
	
	# Center should be contested (0)
	assert_eq(MissionManager.objective_control_state["obj_center"], 0,
			  "Center objective should be contested with equal OC")

func test_objective_control_higher_oc_wins():
	# Place units with different OC values
	var p1_unit = {
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 1}},
		"models": [
			{"position": Vector2(Measurement.inches_to_px(22), Measurement.inches_to_px(30)), "alive": true}
		],
		"flags": {}
	}
	
	var p2_unit = {
		"owner": 2,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 3}},  # Higher OC
		"models": [
			{"position": Vector2(Measurement.inches_to_px(22.5), Measurement.inches_to_px(30)), "alive": true}
		],
		"flags": {}
	}
	
	GameState.state.units["P1_UNIT"] = p1_unit
	GameState.state.units["P2_UNIT"] = p2_unit
	
	MissionManager.check_all_objectives()
	
	# Player 2 should control with higher OC
	assert_eq(MissionManager.objective_control_state["obj_center"], 2,
			  "Player 2 should control with higher OC (3 vs 1)")

func test_objective_control_range():
	# Test that units must be within 3.78740157" (3" + 20mm) to control
	var center_pos = Vector2(Measurement.inches_to_px(22), Measurement.inches_to_px(30))
	var control_radius = 3.78740157  # 3" + 20mm
	
	# Unit just inside control range
	var inside_unit = {
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 2}},
		"models": [
			{"position": center_pos + Vector2(Measurement.inches_to_px(control_radius - 0.1), 0), "alive": true}
		],
		"flags": {}
	}
	
	# Unit just outside control range
	var outside_unit = {
		"owner": 2,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 2}},
		"models": [
			{"position": center_pos + Vector2(Measurement.inches_to_px(control_radius + 0.1), 0), "alive": true}
		],
		"flags": {}
	}
	
	GameState.state.units["INSIDE"] = inside_unit
	GameState.state.units["OUTSIDE"] = outside_unit
	
	MissionManager.check_all_objectives()
	
	# Player 1 should control (inside range)
	assert_eq(MissionManager.objective_control_state["obj_center"], 1,
			  "Only units within 3.78740157\" should control")

func test_battle_shocked_no_control():
	# Test that battle-shocked units have OC = 0
	var test_unit = {
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 5}},
		"models": [
			{"position": Vector2(Measurement.inches_to_px(22), Measurement.inches_to_px(30)), "alive": true}
		],
		"flags": {"battle_shocked": true}  # Battle-shocked
	}
	
	GameState.state.units["SHOCKED"] = test_unit
	
	MissionManager.check_all_objectives()
	
	# Objective should remain uncontrolled
	assert_eq(MissionManager.objective_control_state["obj_center"], 0,
			  "Battle-shocked units should not control objectives")

func test_vp_scoring_no_scoring_round_1():
	# Set battle round 1
	GameState.state.meta.battle_round = 1
	GameState.state.meta.active_player = 1
	
	# Control some objectives
	MissionManager.objective_control_state = {
		"obj_center": 1,
		"obj_tl": 1,
		"obj_tr": 1
	}
	
	# Try to score
	MissionManager.score_primary_objectives()
	
	# Should not score in round 1
	var p1_vp = GameState.state.players["1"].get("vp", 0)
	assert_eq(p1_vp, 0, "No VP should be scored in battle round 1")

func test_vp_scoring_basic():
	# Set battle round 2+
	GameState.state.meta.battle_round = 2
	GameState.state.meta.active_player = 1
	
	# Initialize player VP
	GameState.state.players["1"] = {"vp": 0, "primary_vp": 0}
	
	# Control 2 objectives
	MissionManager.objective_control_state = {
		"obj_center": 1,
		"obj_tl": 1,
		"obj_tr": 0,
		"obj_bl": 2,
		"obj_br": 0
	}
	
	MissionManager.score_primary_objectives()
	
	# Should score 10 VP (2 objectives * 5 VP each)
	var p1_vp = GameState.state.players["1"].get("vp", 0)
	assert_eq(p1_vp, 10, "Should score 10 VP for 2 objectives")

func test_vp_scoring_cap_per_turn():
	# Set battle round 2
	GameState.state.meta.battle_round = 2
	GameState.state.meta.active_player = 1
	
	# Initialize player VP
	GameState.state.players["1"] = {"vp": 0, "primary_vp": 0}
	
	# Control all 5 objectives
	MissionManager.objective_control_state = {
		"obj_center": 1,
		"obj_tl": 1,
		"obj_tr": 1,
		"obj_bl": 1,
		"obj_br": 1
	}
	
	MissionManager.score_primary_objectives()
	
	# Should cap at 15 VP per turn
	var p1_vp = GameState.state.players["1"].get("vp", 0)
	assert_eq(p1_vp, 15, "Should cap at 15 VP per turn even with 5 objectives")

func test_vp_scoring_total_cap():
	# Test that primary VP caps at 50 total
	GameState.state.meta.battle_round = 5
	GameState.state.meta.active_player = 1
	
	# Player already has 45 primary VP
	GameState.state.players["1"] = {"vp": 45, "primary_vp": 45}
	
	# Control 3 objectives (would be 15 VP)
	MissionManager.objective_control_state = {
		"obj_center": 1,
		"obj_tl": 1,
		"obj_tr": 1,
		"obj_bl": 0,
		"obj_br": 0
	}
	
	MissionManager.score_primary_objectives()
	
	# Should only score 5 VP to reach cap of 50
	var p1_vp = GameState.state.players["1"].get("vp", 0)
	var p1_primary = GameState.state.players["1"].get("primary_vp", 0)
	assert_eq(p1_vp, 50, "Total VP should be 50")
	assert_eq(p1_primary, 50, "Primary VP should cap at 50")

func test_unit_counts_once():
	# Test that each unit only counts once even with multiple models in range
	var test_unit = {
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 2}},
		"models": [
			{"position": Vector2(Measurement.inches_to_px(22), Measurement.inches_to_px(30)), "alive": true},
			{"position": Vector2(Measurement.inches_to_px(22.5), Measurement.inches_to_px(30)), "alive": true},
			{"position": Vector2(Measurement.inches_to_px(21.5), Measurement.inches_to_px(30)), "alive": true}
		],
		"flags": {}
	}
	
	GameState.state.units["MULTI_MODEL"] = test_unit
	
	MissionManager.check_all_objectives()
	
	# Should only count unit OC once
	assert_eq(MissionManager.objective_control_state["obj_center"], 1,
			  "Unit should only count once regardless of models in range")
	
	# Verify by adding opposing unit with same OC
	var p2_unit = {
		"owner": 2,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"stats": {"objective_control": 2}},
		"models": [
			{"position": Vector2(Measurement.inches_to_px(22), Measurement.inches_to_px(29.5)), "alive": true}
		],
		"flags": {}
	}
	
	GameState.state.units["P2_SINGLE"] = p2_unit
	
	MissionManager.check_all_objectives()
	
	# Should be contested (both have OC 2)
	assert_eq(MissionManager.objective_control_state["obj_center"], 0,
			  "Should be contested with equal OC (2 vs 2)")

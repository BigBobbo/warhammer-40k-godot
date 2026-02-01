extends "res://addons/gut/test.gd"
const GameStateData = preload("res://autoloads/GameState.gd")

# Test overlap detection for models in movement phase

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	gut.p("Setting up test...")

func after_each():
	gut.p("Cleaning up test...")

func test_models_overlap_circular_bases():
	# Test overlap detection for circular bases
	var model1 = {
		"position": Vector2(0, 0),
		"base_mm": 32,
		"base_type": "circular"
	}

	var model2 = {
		"position": Vector2(20, 0),  # Less than combined radii
		"base_mm": 32,
		"base_type": "circular"
	}

	assert_true(Measurement.models_overlap(model1, model2),
		"Models with 32mm bases at 20px apart should overlap")

	# Test non-overlapping models
	model2["position"] = Vector2(100, 0)  # Far apart
	assert_false(Measurement.models_overlap(model1, model2),
		"Models far apart should not overlap")

	# Test edge case - exactly touching
	var radius1 = Measurement.base_radius_px(32)
	var radius2 = Measurement.base_radius_px(32)
	model2["position"] = Vector2(radius1 + radius2, 0)
	assert_false(Measurement.models_overlap(model1, model2),
		"Models exactly touching should not overlap")

func test_models_overlap_rectangular_bases():
	# Test overlap detection for rectangular bases
	var model1 = {
		"position": Vector2(0, 0),
		"base_mm": 70,
		"base_type": "rectangular",
		"base_dimensions": {"length": 70, "width": 35},
		"rotation": 0.0
	}

	var model2 = {
		"position": Vector2(50, 0),  # Would overlap
		"base_mm": 70,
		"base_type": "rectangular",
		"base_dimensions": {"length": 70, "width": 35},
		"rotation": 0.0
	}

	assert_true(Measurement.models_overlap(model1, model2),
		"Rectangular bases too close should overlap")

	# Test no overlap when separated
	model2["position"] = Vector2(100, 0)  # Far enough apart
	assert_false(Measurement.models_overlap(model1, model2),
		"Rectangular bases far apart should not overlap")

	# Test with rotation - overlapping
	model2["position"] = Vector2(50, 0)
	model2["rotation"] = PI / 2  # 90 degrees
	assert_true(Measurement.models_overlap(model1, model2),
		"Rotated rectangular bases should still detect overlap")

	# Test edge case - exactly touching (no overlap)
	var length_px = Measurement.mm_to_px(70)
	model2["position"] = Vector2(length_px, 0)
	model2["rotation"] = 0.0
	assert_false(Measurement.models_overlap(model1, model2),
		"Rectangular bases exactly touching should not overlap")

func test_models_overlap_mixed_bases():
	# Test overlap between different base types
	var circular_model = {
		"position": Vector2(0, 0),
		"base_mm": 40,
		"base_type": "circular"
	}

	var oval_model = {
		"position": Vector2(30, 0),
		"base_mm": 60,
		"base_type": "oval",
		"base_dimensions": {"length": 60, "width": 35},
		"rotation": 0.0
	}

	assert_true(Measurement.models_overlap(circular_model, oval_model),
		"Mixed base types should detect overlap correctly")

func test_movement_phase_overlap_validation():
	# Test that MovementPhase prevents overlapping moves
	var phase = MovementPhase.new()

	# Setup mock game state
	phase.game_state_snapshot = {
		"units": {
			"unit1": {
				"owner": 1,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"models": [
					{"id": "m1", "position": {"x": 0, "y": 0}, "base_mm": 32, "alive": true},
					{"id": "m2", "position": {"x": 100, "y": 0}, "base_mm": 32, "alive": true}
				]
			}
		}
	}

	# Begin a move
	phase.active_moves["unit1"] = {
		"mode": "NORMAL",
		"move_cap_inches": 6.0,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {},
		"model_distances": {}
	}

	# Try to stage a move that would overlap
	var action = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit1",
		"payload": {
			"model_id": "m1",
			"dest": [100, 0]  # Same position as m2
		}
	}

	var validation = phase.validate_action(action)
	assert_false(validation.valid, "Move to overlapping position should be invalid")
	assert_has(validation.errors[0], "Cannot end move on top of another model",
		"Error message should mention overlap")

func test_movement_phase_allows_non_overlapping():
	# Test that valid non-overlapping moves are allowed
	var phase = MovementPhase.new()

	# Setup mock game state
	phase.game_state_snapshot = {
		"units": {
			"unit1": {
				"owner": 1,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"models": [
					{"id": "m1", "position": {"x": 0, "y": 0}, "base_mm": 32, "alive": true},
					{"id": "m2", "position": {"x": 100, "y": 0}, "base_mm": 32, "alive": true}
				]
			}
		}
	}

	# Begin a move
	phase.active_moves["unit1"] = {
		"mode": "NORMAL",
		"move_cap_inches": 6.0,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {"m1": Vector2(0, 0)},
		"model_distances": {}
	}

	# Try to stage a valid move
	var action = {
		"type": "STAGE_MODEL_MOVE",
		"actor_unit_id": "unit1",
		"payload": {
			"model_id": "m1",
			"dest": [0, 50]  # Safe distance away
		}
	}

	var validation = phase.validate_action(action)
	assert_true(validation.valid, "Non-overlapping move should be valid")

func test_position_as_dictionary():
	# Test that overlap detection works with positions as Dictionaries
	var model1 = {
		"position": {"x": 0, "y": 0},
		"base_mm": 25,
		"base_type": "circular"
	}

	var model2 = {
		"position": {"x": 15, "y": 0},
		"base_mm": 25,
		"base_type": "circular"
	}

	assert_true(Measurement.models_overlap(model1, model2),
		"Should handle position as Dictionary")

extends "res://addons/gut/test.gd"
const GameStateData = preload("res://autoloads/GameState.gd")

# Test suite for the Transport system functionality
# Tests embark/disembark mechanics, capacity checks, and firing deck

var test_transport: Dictionary
var test_unit: Dictionary
var test_large_unit: Dictionary

func before_each() -> void:
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Create test transport with capacity
	test_transport = {
		"id": "TRANSPORT_1",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Transport",
			"keywords": ["VEHICLE", "TRANSPORT"]
		},
		"models": [
			{"id": "m1", "wounds": 10, "current_wounds": 10, "base_mm": 100, "position": {"x": 500, "y": 500}, "alive": true}
		],
		"transport_data": {
			"capacity": 10,
			"capacity_keywords": ["INFANTRY"],
			"embarked_units": [],
			"firing_deck": 5
		},
		"embarked_in": null,
		"disembarked_this_phase": false,
		"flags": {}
	}

	# Create test infantry unit that can embark
	test_unit = {
		"id": "UNIT_1",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Infantry",
			"keywords": ["INFANTRY"]
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": {"x": 450, "y": 450}, "alive": true},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": {"x": 460, "y": 450}, "alive": true},
			{"id": "m3", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": {"x": 470, "y": 450}, "alive": true},
			{"id": "m4", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": {"x": 480, "y": 450}, "alive": true},
			{"id": "m5", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": {"x": 490, "y": 450}, "alive": true}
		],
		"embarked_in": null,
		"disembarked_this_phase": false,
		"flags": {}
	}

	# Create large unit that exceeds capacity
	test_large_unit = {
		"id": "LARGE_UNIT_1",
		"owner": 1,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Large Infantry",
			"keywords": ["INFANTRY"]
		},
		"models": [],
		"embarked_in": null,
		"disembarked_this_phase": false,
		"flags": {}
	}

	# Add 15 models to large unit (exceeds capacity of 10)
	for i in range(15):
		test_large_unit.models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": {"x": 400 + i * 10, "y": 400},
			"alive": true
		})

	# Set up GameState with test units
	GameState.state = {
		"units": {
			"TRANSPORT_1": test_transport,
			"UNIT_1": test_unit,
			"LARGE_UNIT_1": test_large_unit
		}
	}

# Test: Can embark validation

func test_can_embark_valid_unit() -> void:
	# Unit should be able to embark in transport with sufficient capacity
	var result = TransportManager.can_embark("UNIT_1", "TRANSPORT_1")
	assert_true(result.valid, "Unit should be able to embark")

func test_can_embark_insufficient_capacity() -> void:
	# Large unit should not be able to embark due to insufficient capacity
	var result = TransportManager.can_embark("LARGE_UNIT_1", "TRANSPORT_1")
	assert_false(result.valid, "Large unit should not be able to embark")
	assert_true(result.reason.contains("capacity"), "Should mention capacity in reason")

func test_can_embark_wrong_keywords() -> void:
	# Unit without required keywords should not be able to embark
	test_unit.meta.keywords = ["MONSTER"]  # Not INFANTRY
	GameState.state.units["UNIT_1"] = test_unit

	var result = TransportManager.can_embark("UNIT_1", "TRANSPORT_1")
	assert_false(result.valid, "Unit with wrong keywords should not be able to embark")
	assert_true(result.reason.contains("keywords"), "Should mention keywords in reason")

func test_can_embark_already_embarked() -> void:
	# Unit that is already embarked cannot embark again
	test_unit.embarked_in = "OTHER_TRANSPORT"
	GameState.state.units["UNIT_1"] = test_unit

	var result = TransportManager.can_embark("UNIT_1", "TRANSPORT_1")
	assert_false(result.valid, "Already embarked unit should not be able to embark")
	assert_true(result.reason.contains("already embarked"), "Should mention already embarked in reason")

func test_can_embark_disembarked_this_phase() -> void:
	# Unit that disembarked this phase cannot re-embark
	test_unit.disembarked_this_phase = true
	GameState.state.units["UNIT_1"] = test_unit

	var result = TransportManager.can_embark("UNIT_1", "TRANSPORT_1")
	assert_false(result.valid, "Unit that disembarked this phase should not be able to embark")
	assert_true(result.reason.contains("disembarked this phase"), "Should mention disembarked this phase in reason")

# Test: Embark unit

func test_embark_unit_success() -> void:
	# Embark the unit
	TransportManager.embark_unit("UNIT_1", "TRANSPORT_1")

	# Check unit is marked as embarked
	var unit = GameState.get_unit("UNIT_1")
	assert_eq(unit.embarked_in, "TRANSPORT_1", "Unit should be embarked in transport")

	# Check transport has unit in embarked list
	var transport = GameState.get_unit("TRANSPORT_1")
	assert_true("UNIT_1" in transport.transport_data.embarked_units, "Transport should have unit in embarked list")

func test_embark_multiple_units() -> void:
	# Create another small unit
	var unit2 = test_unit.duplicate(true)
	unit2.id = "UNIT_2"
	GameState.state.units["UNIT_2"] = unit2

	# Embark both units
	TransportManager.embark_unit("UNIT_1", "TRANSPORT_1")
	TransportManager.embark_unit("UNIT_2", "TRANSPORT_1")

	# Check both are embarked
	var transport = GameState.get_unit("TRANSPORT_1")
	assert_eq(transport.transport_data.embarked_units.size(), 2, "Transport should have 2 embarked units")
	assert_true("UNIT_1" in transport.transport_data.embarked_units)
	assert_true("UNIT_2" in transport.transport_data.embarked_units)

	# Check total capacity is tracked correctly
	var model_count = TransportManager._get_embarked_model_count("TRANSPORT_1")
	assert_eq(model_count, 10, "Total embarked models should be 10")

# Test: Can disembark validation

func test_can_disembark_not_embarked() -> void:
	# Unit that is not embarked cannot disembark
	var result = TransportManager.can_disembark("UNIT_1")
	assert_false(result.valid, "Non-embarked unit should not be able to disembark")
	assert_true(result.reason.contains("not embarked"), "Should mention not embarked in reason")

func test_can_disembark_transport_advanced() -> void:
	# Setup: embark unit first
	TransportManager.embark_unit("UNIT_1", "TRANSPORT_1")

	# Transport has advanced
	test_transport.flags["advanced"] = true
	GameState.state.units["TRANSPORT_1"] = test_transport

	var result = TransportManager.can_disembark("UNIT_1")
	assert_false(result.valid, "Cannot disembark from transport that Advanced")
	assert_true(result.reason.contains("Advanced"), "Should mention Advanced in reason")

func test_can_disembark_transport_fell_back() -> void:
	# Setup: embark unit first
	TransportManager.embark_unit("UNIT_1", "TRANSPORT_1")

	# Transport has fallen back
	test_transport.flags["fell_back"] = true
	GameState.state.units["TRANSPORT_1"] = test_transport

	var result = TransportManager.can_disembark("UNIT_1")
	assert_false(result.valid, "Cannot disembark from transport that Fell Back")
	assert_true(result.reason.contains("Fell Back"), "Should mention Fell Back in reason")

func test_can_disembark_valid() -> void:
	# Setup: embark unit first
	TransportManager.embark_unit("UNIT_1", "TRANSPORT_1")

	var result = TransportManager.can_disembark("UNIT_1")
	assert_true(result.valid, "Should be able to disembark normally")

# Test: Disembark unit

func test_disembark_unit_success() -> void:
	# Setup: embark unit first
	TransportManager.embark_unit("UNIT_1", "TRANSPORT_1")

	# Define disembark positions (within 3" of transport)
	var positions = [
		Vector2(520, 520),
		Vector2(530, 520),
		Vector2(540, 520),
		Vector2(550, 520),
		Vector2(560, 520)
	]

	# Disembark the unit
	TransportManager.disembark_unit("UNIT_1", positions)

	# Check unit is no longer embarked
	var unit = GameState.get_unit("UNIT_1")
	assert_null(unit.embarked_in, "Unit should not be embarked anymore")
	assert_true(unit.disembarked_this_phase, "Unit should be marked as disembarked this phase")

	# Check transport no longer has unit
	var transport = GameState.get_unit("TRANSPORT_1")
	assert_false("UNIT_1" in transport.transport_data.embarked_units, "Transport should not have unit in embarked list")

	# Check model positions were updated
	for i in range(positions.size()):
		var model_pos = unit.models[i].position
		assert_eq(model_pos.x, positions[i].x, "Model %d X position should be updated" % i)
		assert_eq(model_pos.y, positions[i].y, "Model %d Y position should be updated" % i)

func test_disembark_movement_restrictions() -> void:
	# Setup: embark unit first
	TransportManager.embark_unit("UNIT_1", "TRANSPORT_1")

	# Transport has moved
	test_transport.flags["moved"] = true
	GameState.state.units["TRANSPORT_1"] = test_transport

	# Disembark the unit
	var positions = [Vector2(520, 520), Vector2(530, 520), Vector2(540, 520), Vector2(550, 520), Vector2(560, 520)]
	TransportManager.disembark_unit("UNIT_1", positions)

	# Check unit has movement restrictions
	var unit = GameState.get_unit("UNIT_1")
	assert_true(unit.flags.get("cannot_move", false), "Disembarked unit should not be able to move")
	assert_true(unit.flags.get("cannot_charge", false), "Disembarked unit should not be able to charge")

# Test: Firing deck

func test_has_firing_deck() -> void:
	assert_true(TransportManager.has_firing_deck("TRANSPORT_1"), "Transport should have firing deck")
	assert_eq(TransportManager.get_firing_deck_capacity("TRANSPORT_1"), 5, "Firing deck capacity should be 5")

func test_no_firing_deck() -> void:
	# Remove firing deck
	test_transport.transport_data.firing_deck = 0
	GameState.state.units["TRANSPORT_1"] = test_transport

	assert_false(TransportManager.has_firing_deck("TRANSPORT_1"), "Transport should not have firing deck")
	assert_eq(TransportManager.get_firing_deck_capacity("TRANSPORT_1"), 0, "Firing deck capacity should be 0")

# Test: Get embarkable units

func test_get_embarkable_units() -> void:
	var embarkable = TransportManager.get_embarkable_units("TRANSPORT_1", 1)

	# Should include UNIT_1 but not LARGE_UNIT_1
	assert_eq(embarkable.size(), 1, "Should have 1 embarkable unit")
	assert_eq(embarkable[0].id, "UNIT_1", "UNIT_1 should be embarkable")

func test_get_embarked_units() -> void:
	# Embark a unit
	TransportManager.embark_unit("UNIT_1", "TRANSPORT_1")

	var embarked = TransportManager.get_embarked_units("TRANSPORT_1")
	assert_eq(embarked.size(), 1, "Should have 1 embarked unit")
	assert_eq(embarked[0].id, "UNIT_1", "UNIT_1 should be embarked")

# Test: Reset disembark flags

func test_reset_disembark_flags() -> void:
	# Mark units as disembarked
	test_unit.disembarked_this_phase = true
	GameState.state.units["UNIT_1"] = test_unit

	# Reset flags
	TransportManager.reset_disembark_flags()

	# Check flag is cleared
	var unit = GameState.get_unit("UNIT_1")
	assert_false(unit.disembarked_this_phase, "Disembark flag should be reset")

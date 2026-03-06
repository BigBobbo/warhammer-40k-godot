extends "res://addons/gut/test.gd"

# Test transport embark dialog for MA-35: Fix unable to select units for transport embarkation

const GameStateData = preload("res://autoloads/GameState.gd")

var _saved_units: Dictionary = {}

func before_each():
	AutoloadHelper.verify_autoloads_available()
	# Save existing game state units and clear for clean test
	_saved_units = GameState.state.units.duplicate()
	GameState.state.units.clear()

func after_each():
	# Restore original game state
	GameState.state.units = _saved_units

func _create_transport_unit(player: int) -> String:
	var unit_id = "test_transport"
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": player,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {
			"name": "Test Battlewagon",
			"keywords": ["VEHICLE", "TRANSPORT", "ORKS"],
			"stats": {"move": 10, "toughness": 10, "save": 3},
			"abilities": []
		},
		"models": [
			{"id": "m1", "wounds": 16, "current_wounds": 16, "base_mm": 170, "position": null, "alive": true, "status_effects": []}
		],
		"transport_data": {
			"capacity": 12,
			"capacity_keywords": ["ORKS", "INFANTRY"],
			"embarked_units": [],
			"firing_deck": 0
		},
		"embarked_in": null,
		"disembarked_this_phase": false,
		"attached_to": null,
		"attachment_data": {"attached_characters": []}
	}
	GameState.state.units[unit_id] = unit
	return unit_id

func _create_infantry_unit(player: int, unit_id: String, unit_name: String, model_count: int = 5) -> String:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": null,
			"alive": true,
			"status_effects": []
		})
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": player,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {
			"name": unit_name,
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {"move": 6, "toughness": 5, "save": 5}
		},
		"models": models,
		"embarked_in": null,
		"disembarked_this_phase": false,
		"attached_to": null,
		"attachment_data": {"attached_characters": []}
	}
	GameState.state.units[unit_id] = unit
	return unit_id

func test_dialog_creates_checkboxes_for_eligible_units():
	var transport_id = _create_transport_unit(2)
	var infantry1_id = _create_infantry_unit(2, "test_boyz_1", "Boyz Squad 1", 5)
	var infantry2_id = _create_infantry_unit(2, "test_boyz_2", "Boyz Squad 2", 10)

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	add_child(dialog)
	dialog.setup(transport_id)

	assert_eq(dialog.available_units.size(), 2, "Should find 2 eligible infantry units")
	assert_eq(dialog.checkboxes.size(), 2, "Should create 2 checkboxes")
	assert_true(dialog.checkboxes.has(infantry1_id), "Should have checkbox for boyz 1")
	assert_true(dialog.checkboxes.has(infantry2_id), "Should have checkbox for boyz 2")
	assert_eq(dialog.capacity, 12, "Transport capacity should be 12")

	dialog.queue_free()

func test_dialog_filters_ineligible_units():
	var transport_id = _create_transport_unit(2)
	var infantry_id = _create_infantry_unit(2, "test_boyz_1", "Boyz Squad", 5)

	# Create ineligible unit (wrong player, wrong keywords)
	GameState.state.units["test_marine_1"] = {
		"id": "test_marine_1", "squad_id": "test_marine_1", "owner": 1,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {"name": "Marine Squad", "keywords": ["INFANTRY", "SPACE MARINES"], "stats": {}},
		"models": [{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []}],
		"embarked_in": null, "disembarked_this_phase": false,
		"attached_to": null, "attachment_data": {"attached_characters": []}
	}

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	add_child(dialog)
	dialog.setup(transport_id)

	assert_eq(dialog.available_units.size(), 1, "Should find only 1 eligible unit")
	assert_true(dialog.checkboxes.has(infantry_id), "Should have checkbox for orks boyz")

	dialog.queue_free()

func test_checkbox_toggle_updates_selection():
	var transport_id = _create_transport_unit(2)
	var infantry_id = _create_infantry_unit(2, "test_boyz_1", "Boyz Squad", 5)

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	add_child(dialog)
	dialog.setup(transport_id)

	assert_true(dialog.checkboxes.has(infantry_id), "Checkbox should exist")

	var checkbox = dialog.checkboxes[infantry_id]
	assert_false(checkbox.button_pressed, "Checkbox should start unchecked")

	# Programmatically toggle ON
	checkbox.button_pressed = true

	assert_true(infantry_id in dialog.selected_units, "Unit should be in selected list after toggle")
	assert_eq(dialog.current_model_count, 5, "Model count should be 5 after selecting 5-model unit")

	# Toggle OFF
	checkbox.button_pressed = false
	assert_false(infantry_id in dialog.selected_units, "Unit should be removed from selected list")
	assert_eq(dialog.current_model_count, 0, "Model count should be 0 after deselecting")

	dialog.queue_free()

func test_capacity_enforcement():
	var transport_id = _create_transport_unit(2)
	var infantry1_id = _create_infantry_unit(2, "test_boyz_1", "Boyz Squad 1", 10)
	var infantry2_id = _create_infantry_unit(2, "test_boyz_2", "Boyz Squad 2", 5)

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	add_child(dialog)
	dialog.setup(transport_id)

	# Select first unit (10 models, fits in 12 capacity)
	dialog.checkboxes[infantry1_id].button_pressed = true
	assert_eq(dialog.current_model_count, 10, "Should have 10 models embarked")

	# Try selecting second unit (5 models, would exceed 12 capacity)
	dialog.checkboxes[infantry2_id].button_pressed = true
	assert_false(dialog.checkboxes[infantry2_id].button_pressed, "Checkbox should be reverted - exceeds capacity")
	assert_eq(dialog.current_model_count, 10, "Model count should still be 10")
	assert_false(infantry2_id in dialog.selected_units, "Second unit should NOT be selected")

	dialog.queue_free()

func test_confirm_emits_selected_units():
	var transport_id = _create_transport_unit(2)
	var infantry_id = _create_infantry_unit(2, "test_boyz_1", "Boyz Squad", 5)

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	add_child(dialog)
	dialog.setup(transport_id)

	# Use a dictionary to capture signal data (GDScript lambdas capture refs for dicts)
	var result = {"units": []}
	dialog.units_selected.connect(func(ids): result.units = ids)

	# Select a unit
	dialog.checkboxes[infantry_id].button_pressed = true

	# Simulate confirm
	dialog._on_confirm_pressed()

	assert_eq(result.units.size(), 1, "Should emit 1 selected unit")
	if result.units.size() > 0:
		assert_eq(result.units[0], infantry_id, "Should emit the correct unit ID")

func test_skip_emits_empty_array():
	var transport_id = _create_transport_unit(2)
	_create_infantry_unit(2, "test_boyz_1", "Boyz Squad", 5)

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	add_child(dialog)
	dialog.setup(transport_id)

	var result = {"units": null}
	dialog.units_selected.connect(func(ids): result.units = ids)

	dialog._on_skip_pressed()

	assert_not_null(result.units, "Should emit signal on skip")
	if result.units != null:
		assert_eq(result.units.size(), 0, "Should emit empty array on skip")

func test_dialog_setup_is_synchronous_when_node_ready():
	var transport_id = _create_transport_unit(2)
	_create_infantry_unit(2, "test_boyz_1", "Boyz Squad", 5)

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	add_child(dialog)

	assert_true(dialog.is_node_ready(), "Dialog should be ready after add_child")

	dialog.setup(transport_id)

	assert_eq(dialog.checkboxes.size(), 1, "Checkboxes should be created synchronously when node is ready")
	assert_eq(dialog.unit_container.get_child_count(), 1, "unit_container should have children immediately")

	dialog.queue_free()

func test_dialog_filters_deployed_units():
	var transport_id = _create_transport_unit(2)
	var infantry_id = _create_infantry_unit(2, "test_boyz_1", "Boyz Squad", 5)

	# Mark infantry as deployed
	GameState.state.units[infantry_id].status = GameStateData.UnitStatus.DEPLOYED

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	add_child(dialog)
	dialog.setup(transport_id)

	assert_eq(dialog.available_units.size(), 0, "Deployed units should be filtered out")

	dialog.queue_free()

func test_dialog_filters_transport_units():
	var transport_id = _create_transport_unit(2)

	# Create another transport (should not be eligible for embarking)
	GameState.state.units["test_transport_2"] = {
		"id": "test_transport_2", "squad_id": "test_transport_2", "owner": 2,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {"name": "Trukk", "keywords": ["VEHICLE", "TRANSPORT", "ORKS"], "stats": {}},
		"models": [{"id": "m1", "wounds": 10, "current_wounds": 10, "base_mm": 100, "position": null, "alive": true, "status_effects": []}],
		"transport_data": {"capacity": 6, "capacity_keywords": [], "embarked_units": [], "firing_deck": 0},
		"embarked_in": null, "disembarked_this_phase": false,
		"attached_to": null, "attachment_data": {"attached_characters": []}
	}

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	add_child(dialog)
	dialog.setup(transport_id)

	assert_eq(dialog.available_units.size(), 0, "Transport units should be filtered out")

	dialog.queue_free()

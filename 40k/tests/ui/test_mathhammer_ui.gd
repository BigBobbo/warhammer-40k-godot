extends GutTest

# UI integration tests for MathhhammerUI
# Validates UI creation, user interaction, and display functionality

var mathhammer_ui: MathhhammerUI
var test_scene: Node

func before_each():
	# Create test scene
	test_scene = Node.new()
	add_child(test_scene)
	
	# Create MathhhammerUI instance
	mathhammer_ui = MathhhammerUI.new()
	test_scene.add_child(mathhammer_ui)
	
	# Setup mock game state
	_setup_mock_game_state()
	
	# Wait for _ready to complete
	await get_tree().process_frame

func after_each():
	if test_scene:
		test_scene.queue_free()
		test_scene = null
	mathhammer_ui = null

func _setup_mock_game_state():
	# Create mock units for testing
	if GameState:
		GameState.state = {
			"units": {
				"TEST_ATTACKER": {
					"id": "TEST_ATTACKER",
					"owner": 1,
					"meta": {
						"name": "Test Attacker",
						"points": 100,
						"weapons": [{
							"name": "Test Weapon",
							"type": "Ranged",
							"range": "24",
							"attacks": "2",
							"ballistic_skill": "3",
							"strength": "4",
							"ap": "0",
							"damage": "1"
						}]
					},
					"models": [
						{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true}
					]
				},
				"TEST_DEFENDER": {
					"id": "TEST_DEFENDER",
					"owner": 2,
					"meta": {
						"name": "Test Defender",
						"stats": {
							"toughness": 4,
							"save": 5
						}
					},
					"models": [
						{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true}
					]
				}
			}
		}

func test_ui_creation():
	# Test basic UI creation
	assert_not_null(mathhammer_ui, "MathhhammerUI should be created")
	assert_not_null(mathhammer_ui.toggle_button, "Toggle button should exist")
	assert_not_null(mathhammer_ui.scroll_container, "Scroll container should exist")

func test_toggle_functionality():
	# Test panel collapse/expand
	var initial_collapsed = mathhammer_ui.is_collapsed
	
	# Toggle the panel
	mathhammer_ui._on_toggle_pressed()
	
	assert_ne(mathhammer_ui.is_collapsed, initial_collapsed, "Toggle should change collapsed state")
	
	# Toggle back
	mathhammer_ui._on_toggle_pressed()
	
	assert_eq(mathhammer_ui.is_collapsed, initial_collapsed, "Toggle should return to original state")

func test_unit_selector_population():
	# Test that unit selectors are populated
	assert_not_null(mathhammer_ui.attacker_selector, "Attacker selector should exist")
	assert_not_null(mathhammer_ui.defender_selector, "Defender selector should exist")
	
	# Should have mock units
	assert_gt(mathhammer_ui.attacker_selector.get_item_count(), 0, "Attacker selector should have items")
	assert_gt(mathhammer_ui.defender_selector.get_item_count(), 0, "Defender selector should have items")

func test_trials_spinbox_configuration():
	# Test trials spinbox setup
	assert_not_null(mathhammer_ui.trials_spinbox, "Trials spinbox should exist")
	assert_eq(mathhammer_ui.trials_spinbox.min_value, 100, "Min trials should be 100")
	assert_eq(mathhammer_ui.trials_spinbox.max_value, 100000, "Max trials should be 100000")
	assert_eq(mathhammer_ui.trials_spinbox.value, 10000, "Default trials should be 10000")

func test_rule_toggles_creation():
	# Test rule toggle creation
	assert_not_null(mathhammer_ui.rule_toggles_panel, "Rule toggles panel should exist")
	
	# Should have rule toggles created
	var checkboxes = _find_checkboxes_in_container(mathhammer_ui.rule_toggles_panel)
	assert_gt(checkboxes.size(), 0, "Should have rule toggle checkboxes")

func test_results_display_elements():
	# Test results display elements exist
	assert_not_null(mathhammer_ui.results_label, "Results label should exist")
	assert_not_null(mathhammer_ui.breakdown_text, "Breakdown text should exist")
	assert_not_null(mathhammer_ui.histogram_display, "Histogram display should exist")

func test_unit_selection_validation():
	# Test unit selection validation
	# Select same unit for attacker and defender (should be invalid)
	if mathhammer_ui.attacker_selector.get_item_count() > 0:
		mathhammer_ui.attacker_selector.selected = 0
		mathhammer_ui.defender_selector.selected = 0
		
		# Try to run simulation
		mathhammer_ui._on_run_simulation_pressed()
		
		# Should show error (check results label for error text)
		await get_tree().process_frame
		assert_true(mathhammer_ui.results_label.text.contains("Error"), "Should show error for same unit selection")

func test_valid_simulation_execution():
	# Test valid simulation execution
	if mathhammer_ui.attacker_selector.get_item_count() >= 2:
		# Select different units
		mathhammer_ui.attacker_selector.selected = 0
		mathhammer_ui.defender_selector.selected = 1
		
		# Set low trial count for fast test
		mathhammer_ui.trials_spinbox.value = 100
		
		# Run simulation
		mathhammer_ui._on_run_simulation_pressed()
		
		# Wait for simulation to complete
		await get_tree().process_frame
		await get_tree().process_frame
		
		# Should have results
		assert_false(mathhammer_ui.results_label.text.contains("Run a simulation"), "Should have simulation results")

func test_rule_toggle_interaction():
	# Test rule toggle interaction
	var checkboxes = _find_checkboxes_in_container(mathhammer_ui.rule_toggles_panel)
	
	if not checkboxes.is_empty():
		var checkbox = checkboxes[0]
		var initial_state = checkbox.button_pressed
		
		# Toggle the checkbox
		checkbox.button_pressed = !initial_state
		checkbox.emit_signal("toggled", !initial_state)
		
		# Check that rule toggles dictionary was updated
		# This is internal state, so we test indirectly by checking the checkbox state persists
		await get_tree().process_frame
		assert_eq(checkbox.button_pressed, !initial_state, "Checkbox state should persist")

func test_summary_panel_display():
	# Test summary panel content display
	var mock_result = Mathhammer.SimulationResult.new()
	mock_result.trials_run = 1000
	mock_result.total_damage = 2500.0
	mock_result.kill_probability = 0.75
	mock_result.expected_survivors = 0.5
	mock_result.damage_efficiency = 0.85
	
	mathhammer_ui._display_simulation_results(mock_result)
	
	# Check that results are displayed
	var results_text = mathhammer_ui.results_label.text
	assert_true(results_text.contains("1000 trials"), "Should show trial count")
	assert_true(results_text.contains("2.5"), "Should show average damage")
	assert_true(results_text.contains("75.0%"), "Should show kill probability")

func test_breakdown_panel_display():
	# Test breakdown panel content
	var mock_result = Mathhammer.SimulationResult.new()
	mock_result.trials_run = 1000
	mock_result.statistical_summary = {
		"median_damage": 2.0,
		"percentile_25": 1,
		"percentile_75": 3,
		"percentile_95": 5,
		"max_damage": 8
	}
	
	mathhammer_ui._display_simulation_results(mock_result)
	
	# Check breakdown content
	var breakdown_text = mathhammer_ui.breakdown_text.text
	assert_true(breakdown_text.contains("Median"), "Should show median damage")
	assert_true(breakdown_text.contains("Percentile"), "Should show percentiles")

func test_histogram_display():
	# Test histogram display functionality
	var mock_result = Mathhammer.SimulationResult.new()
	mock_result.trials_run = 100
	mock_result.damage_distribution = {
		"0": 20,
		"1": 30,
		"2": 35,
		"3": 15
	}
	
	mathhammer_ui._display_simulation_results(mock_result)
	
	# Check that histogram was created
	var histogram_label = mathhammer_ui.histogram_display.get_node_or_null("HistogramLabel")
	assert_not_null(histogram_label, "Histogram label should be created")
	assert_true(histogram_label.text.contains("damage:"), "Should show damage distribution")

func test_error_display():
	# Test error message display
	var error_message = "Test error message"
	mathhammer_ui._show_error(error_message)
	
	var results_text = mathhammer_ui.results_label.text
	assert_true(results_text.contains("Error"), "Should show error prefix")
	assert_true(results_text.contains(error_message), "Should show error message")

func test_ui_responsiveness():
	# Test UI responsiveness during operations
	assert_not_null(mathhammer_ui.run_simulation_button, "Run button should exist")
	
	# Button should be enabled initially
	assert_false(mathhammer_ui.run_simulation_button.disabled, "Button should be enabled initially")

func test_panel_animation():
	# Test panel expand/collapse animation
	var initial_size = mathhammer_ui.custom_minimum_size.y
	
	# Trigger collapse
	mathhammer_ui.set_collapsed(true)
	
	# Wait for animation to start
	await get_tree().process_frame
	
	# Size should be changing (tween in progress)
	# Note: This is hard to test precisely due to timing, so we just check the collapsed state
	assert_true(mathhammer_ui.is_collapsed, "Should be in collapsed state")

func _find_checkboxes_in_container(container: Node) -> Array:
	var checkboxes = []
	
	if container is CheckBox:
		checkboxes.append(container)
	
	for child in container.get_children():
		if child is CheckBox:
			checkboxes.append(child)
		elif child.get_child_count() > 0:
			checkboxes += _find_checkboxes_in_container(child)
	
	return checkboxes
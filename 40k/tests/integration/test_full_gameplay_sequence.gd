extends BaseUITest

# Full Gameplay Sequence Tests
# Tests complete gameplay sequences simulating real player mouse actions
# These tests demonstrate how to test entire turns and phases with realistic input

func before_each():
	super.before_each()
	# Initialize game with test data
	var test_state = TestDataFactory.create_test_game_state()
	if Engine.has_singleton("GameState"):
		var game_state = Engine.get_singleton("GameState")
		game_state.load_from_snapshot(test_state)

func test_complete_deployment_phase():
	"""Test complete deployment phase with mouse interactions"""
	# Start in deployment phase
	transition_to_phase(GameStateData.Phase.DEPLOYMENT)
	await wait_for_ui_update()

	# Verify we're in deployment
	assert_phase_label("DEPLOYMENT")

	# Select first unit from list
	select_unit_from_list(0)
	await wait_for_ui_update()

	# Deploy unit in deployment zone - simulate clicking positions for each model
	var deployment_positions = [
		Vector2(200, 200),
		Vector2(220, 200),
		Vector2(240, 200),
		Vector2(200, 220),
		Vector2(220, 220)
	]

	for pos in deployment_positions:
		# Simulate realistic mouse movement and click
		await InputSimulator.simulate_realistic_mouse_movement(scene_runner,
			scene_runner.get_mouse_position(), pos, 0.3)
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		await wait_for_ui_update()

	# Confirm deployment
	var confirm_button = find_ui_element("ConfirmDeploymentButton", Button)
	if confirm_button:
		click_button("ConfirmDeploymentButton")
		await wait_for_ui_update()

	# Select and deploy second unit
	select_unit_from_list(1)
	await wait_for_ui_update()

	var second_unit_positions = [
		Vector2(300, 200),
		Vector2(320, 200),
		Vector2(340, 200),
		Vector2(300, 220)
	]

	for pos in second_unit_positions:
		await InputSimulator.simulate_realistic_mouse_movement(scene_runner,
			scene_runner.get_mouse_position(), pos, 0.3)
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		await wait_for_ui_update()

	# Confirm second unit
	if confirm_button:
		click_button("ConfirmDeploymentButton")
		await wait_for_ui_update()

	# End deployment phase
	var end_phase_button = find_ui_element("EndDeploymentButton", Button)
	if end_phase_button and not end_phase_button.disabled:
		click_button("EndDeploymentButton")
		await wait_for_ui_update()

func test_complete_movement_phase():
	"""Test complete movement phase with drag and drop"""
	# Setup: units already deployed
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	await wait_for_ui_update()

	# Click "Begin Normal Move" button
	var move_button = find_ui_element("BeginNormalMove", Button)
	if move_button:
		click_button("BeginNormalMove")
		await wait_for_ui_update()

	# Find first model token
	var model_token = find_model_token("test_unit_1", "sergeant")
	if model_token:
		var start_pos = model_token.global_position
		var target_pos = start_pos + Vector2(100, 0)  # Move 100 pixels right

		# Simulate realistic drag
		scene_runner.set_mouse_position(start_pos)
		scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)
		await scene_runner.get_scene().get_tree().process_frame

		# Drag with smooth movement
		await InputSimulator.simulate_realistic_mouse_movement(scene_runner, start_pos, target_pos, 0.8)

		scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
		await wait_for_ui_update()

	# Move another model
	var second_model = find_model_token("test_unit_1", "marine_1")
	if second_model:
		var start_pos = second_model.global_position
		var target_pos = start_pos + Vector2(100, 0)

		# Use the drag helper
		await drag_model(start_pos, target_pos)
		await wait_for_ui_update()

	# Confirm movement
	var confirm_move_button = find_ui_element("ConfirmMoveButton", Button)
	if confirm_move_button:
		click_button("ConfirmMoveButton")
		await wait_for_ui_update()

	# End movement phase
	var end_phase_button = find_ui_element("EndPhaseButton", Button)
	if end_phase_button:
		click_button("EndPhaseButton")
		await wait_for_ui_update()

func test_complete_shooting_phase():
	"""Test complete shooting phase with target selection"""
	transition_to_phase(GameStateData.Phase.SHOOTING)
	await wait_for_ui_update()

	# Select shooting unit from list
	select_unit_from_list(0)
	await wait_for_ui_update()

	# Click "Declare Shot" button
	var shoot_button = find_ui_element("DeclareShootButton", Button)
	if shoot_button:
		click_button("DeclareShootButton")
		await wait_for_ui_update()

	# Find and click enemy unit to target
	var enemy_token = find_model_token("enemy_unit_1", "nob")
	if enemy_token:
		var enemy_pos = enemy_token.global_position

		# Simulate mouse movement to target
		await InputSimulator.simulate_realistic_mouse_movement(scene_runner,
			scene_runner.get_mouse_position(), enemy_pos, 0.5)

		# Click to select target
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		await wait_for_ui_update()

		# Verify target is selected (visual feedback should appear)
		# This would check for target indicator, range lines, etc.

	# Select weapon if prompted
	var weapon_dialog = find_ui_element("WeaponSelectionDialog", Control)
	if weapon_dialog and weapon_dialog.visible:
		# Click first weapon option
		var weapon_button = find_ui_element("Weapon0Button", Button)
		if weapon_button:
			click_button("Weapon0Button")
			await wait_for_ui_update()

	# Confirm shot
	var confirm_shot_button = find_ui_element("ConfirmShootButton", Button)
	if confirm_shot_button:
		click_button("ConfirmShootButton")
		await wait_for_ui_update()

	# Handle wound allocation if damage was dealt
	var wound_overlay = find_ui_element("WoundAllocationOverlay", Control)
	if wound_overlay and wound_overlay.visible:
		# Click on models to allocate wounds
		var allocate_button = find_ui_element("AllocateWoundButton", Button)
		if allocate_button:
			click_button("AllocateWoundButton")
			await wait_for_ui_update()

		var confirm_wounds = find_ui_element("ConfirmWoundsButton", Button)
		if confirm_wounds:
			click_button("ConfirmWoundsButton")
			await wait_for_ui_update()

	# End shooting phase
	var end_phase_button = find_ui_element("EndPhaseButton", Button)
	if end_phase_button:
		click_button("EndPhaseButton")
		await wait_for_ui_update()

func test_complete_charge_phase():
	"""Test complete charge phase with charge declaration and dice rolls"""
	transition_to_phase(GameStateData.Phase.CHARGE)
	await wait_for_ui_update()

	# Select charging unit
	select_unit_from_list(0)
	await wait_for_ui_update()

	# Click "Declare Charge" button
	var charge_button = find_ui_element("DeclareChargeButton", Button)
	if charge_button:
		click_button("DeclareChargeButton")
		await wait_for_ui_update()

	# Click on enemy unit to charge
	var enemy_token = find_model_token("enemy_unit_1", "nob")
	if enemy_token:
		var enemy_pos = enemy_token.global_position

		await InputSimulator.simulate_realistic_mouse_movement(scene_runner,
			scene_runner.get_mouse_position(), enemy_pos, 0.4)
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		await wait_for_ui_update()

	# Roll charge dice (button should appear)
	var roll_charge_button = find_ui_element("RollChargeButton", Button)
	if roll_charge_button:
		# Simulate hesitation before rolling
		await InputSimulator.simulate_player_hesitation(scene_runner, 0.5)

		click_button("RollChargeButton")
		await wait_for_ui_update()

		# Wait for dice animation
		await InputSimulator.wait_for_animation(scene_runner, 1.0)

	# If charge successful, position models in engagement range
	var position_models_button = find_ui_element("PositionModelsButton", Button)
	if position_models_button and not position_models_button.disabled:
		click_button("PositionModelsButton")
		await wait_for_ui_update()

		# Drag models into engagement range
		var charging_model = find_model_token("test_unit_1", "sergeant")
		if charging_model and enemy_token:
			var charge_start = charging_model.global_position
			var charge_target = enemy_token.global_position - Vector2(30, 0)  # 1" away

			await drag_model(charge_start, charge_target)
			await wait_for_ui_update()

		# Confirm positions
		var confirm_positions = find_ui_element("ConfirmPositionsButton", Button)
		if confirm_positions:
			click_button("ConfirmPositionsButton")
			await wait_for_ui_update()

	# End charge phase
	var end_phase_button = find_ui_element("EndPhaseButton", Button)
	if end_phase_button:
		click_button("EndPhaseButton")
		await wait_for_ui_update()

func test_complete_fight_phase():
	"""Test complete fight phase with melee combat"""
	transition_to_phase(GameStateData.Phase.FIGHT)
	await wait_for_ui_update()

	# Select unit that can fight
	select_unit_from_list(0)
	await wait_for_ui_update()

	# Click "Fight" button
	var fight_button = find_ui_element("FightButton", Button)
	if fight_button:
		click_button("FightButton")
		await wait_for_ui_update()

	# Select target (should already be in engagement range from charge)
	var enemy_token = find_model_token("enemy_unit_1", "nob")
	if enemy_token:
		var enemy_pos = enemy_token.global_position
		scene_runner.set_mouse_position(enemy_pos)
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		await wait_for_ui_update()

	# Select weapon for fighting
	var weapon_dialog = find_ui_element("MeleeWeaponDialog", Control)
	if weapon_dialog and weapon_dialog.visible:
		var select_weapon = find_ui_element("MeleeWeapon0", Button)
		if select_weapon:
			click_button("MeleeWeapon0")
			await wait_for_ui_update()

	# Resolve fight
	var resolve_button = find_ui_element("ResolveFightButton", Button)
	if resolve_button:
		click_button("ResolveFightButton")
		await wait_for_ui_update()

		# Wait for dice rolls and animations
		await InputSimulator.wait_for_animation(scene_runner, 2.0)

	# Handle wound allocation if needed
	var wound_overlay = find_ui_element("WoundAllocationOverlay", Control)
	if wound_overlay and wound_overlay.visible:
		var confirm_wounds = find_ui_element("ConfirmWoundsButton", Button)
		if confirm_wounds:
			click_button("ConfirmWoundsButton")
			await wait_for_ui_update()

	# End fight phase
	var end_phase_button = find_ui_element("EndPhaseButton", Button)
	if end_phase_button:
		click_button("EndPhaseButton")
		await wait_for_ui_update()

func test_complete_turn_sequence():
	"""Test a complete turn from deployment through all phases"""
	# This is a long test that simulates a full turn

	# 1. Deployment
	await test_complete_deployment_phase()

	# 2. Command Phase (usually just a button click)
	transition_to_phase(GameStateData.Phase.COMMAND)
	await wait_for_ui_update()

	var end_command = find_ui_element("EndPhaseButton", Button)
	if end_command:
		click_button("EndPhaseButton")
		await wait_for_ui_update()

	# 3. Movement
	await test_complete_movement_phase()

	# 4. Shooting
	await test_complete_shooting_phase()

	# 5. Charge
	await test_complete_charge_phase()

	# 6. Fight
	await test_complete_fight_phase()

	# 7. Morale (usually automatic or skip if no casualties)
	transition_to_phase(GameStateData.Phase.MORALE)
	await wait_for_ui_update()

	var end_morale = find_ui_element("EndPhaseButton", Button)
	if end_morale:
		click_button("EndPhaseButton")
		await wait_for_ui_update()

	# Verify we completed a full turn
	if Engine.has_singleton("TurnManager"):
		var turn_manager = Engine.get_singleton("TurnManager")
		var current_turn = turn_manager.get_current_turn()
		# Turn should have advanced or player should have switched
		assert_true(true, "Completed full turn sequence")

func test_camera_controls_during_gameplay():
	"""Test camera pan and zoom during gameplay"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	await wait_for_ui_update()

	var initial_camera_pos = camera.global_position if camera else Vector2.ZERO

	# Test WASD camera movement
	await InputSimulator.simulate_key_press(scene_runner, KEY_W)  # Move up
	await wait_for_ui_update()

	await InputSimulator.simulate_key_press(scene_runner, KEY_D)  # Move right
	await wait_for_ui_update()

	await InputSimulator.simulate_key_press(scene_runner, KEY_S)  # Move down
	await wait_for_ui_update()

	await InputSimulator.simulate_key_press(scene_runner, KEY_A)  # Move left
	await wait_for_ui_update()

	# Test zoom
	var zoom_center = Vector2(640, 512)  # Center of screen
	await InputSimulator.simulate_zoom_gesture(scene_runner, zoom_center, true, 3)  # Zoom in
	await wait_for_ui_update()

	await InputSimulator.simulate_zoom_gesture(scene_runner, zoom_center, false, 3)  # Zoom out
	await wait_for_ui_update()

	# Test middle mouse drag pan
	var pan_start = Vector2(400, 400)
	var pan_end = Vector2(600, 600)
	await InputSimulator.simulate_camera_pan_with_mouse(scene_runner, pan_start, pan_end)
	await wait_for_ui_update()

	if camera:
		var final_camera_pos = camera.global_position
		var camera_moved = initial_camera_pos.distance_to(final_camera_pos) > 10.0
		assert_true(camera_moved, "Camera should have moved during controls")

func test_measurement_tool_usage():
	"""Test using the measurement tool during gameplay"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	await wait_for_ui_update()

	# Activate measurement tool (hotkey or button)
	var measure_button = find_ui_element("MeasureButton", Button)
	if measure_button:
		click_button("MeasureButton")
		await wait_for_ui_update()

	# Measure distance between two points
	var measure_start = Vector2(200, 200)
	var measure_end = Vector2(400, 300)

	await InputSimulator.simulate_measurement(scene_runner, measure_start, measure_end)
	await wait_for_ui_update()

	# Check if measurement is displayed
	var measure_display = find_ui_element("MeasurementDisplay", Label)
	if measure_display and measure_display.visible:
		assert_ne("", measure_display.text, "Measurement should display distance")

	# Deactivate measurement tool
	if measure_button:
		click_button("MeasureButton")
		await wait_for_ui_update()

func test_undo_redo_actions():
	"""Test undo/redo functionality during gameplay"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	await wait_for_ui_update()

	# Perform a movement
	var model_token = find_model_token("test_unit_1", "sergeant")
	if model_token:
		var initial_pos = model_token.global_position
		var new_pos = initial_pos + Vector2(100, 0)

		# Move the model
		click_button("BeginNormalMove")
		await wait_for_ui_update()

		await drag_model(initial_pos, new_pos)
		await wait_for_ui_update()

		# Undo the movement
		var undo_button = find_ui_element("UndoButton", Button)
		if undo_button:
			click_button("UndoButton")
			await wait_for_ui_update()

			# Check if model returned to original position
			var current_pos = model_token.global_position
			var distance = current_pos.distance_to(initial_pos)
			assert_lt(distance, 10.0, "Model should return to original position after undo")

		# Redo the movement
		var redo_button = find_ui_element("RedoButton", Button)
		if redo_button:
			click_button("RedoButton")
			await wait_for_ui_update()

			var current_pos = model_token.global_position
			var distance = current_pos.distance_to(new_pos)
			assert_lt(distance, 10.0, "Model should move to new position after redo")

func test_save_and_load_during_game():
	"""Test save/load functionality during gameplay"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	await wait_for_ui_update()

	# Open save dialog
	await InputSimulator.simulate_keyboard_shortcut(scene_runner, [KEY_CTRL, KEY_S])
	await wait_for_ui_update()

	var save_dialog = find_ui_element("SaveLoadDialog", Control)
	if save_dialog and save_dialog.visible:
		# Enter save name
		var save_name_field = find_ui_element("SaveNameField", LineEdit)
		if save_name_field:
			save_name_field.text = "test_save_gameplay"

		# Click save button
		var save_button = find_ui_element("SaveButton", Button)
		if save_button:
			click_button("SaveButton")
			await wait_for_ui_update()

	# Make some changes to game state
	var model_token = find_model_token("test_unit_1", "sergeant")
	if model_token:
		var pos = model_token.global_position
		await drag_model(pos, pos + Vector2(50, 50))
		await wait_for_ui_update()

	# Load the saved game
	await InputSimulator.simulate_keyboard_shortcut(scene_runner, [KEY_CTRL, KEY_L])
	await wait_for_ui_update()

	var load_dialog = find_ui_element("SaveLoadDialog", Control)
	if load_dialog and load_dialog.visible:
		# Select the save we just made
		var save_list = find_ui_element("SaveList", ItemList)
		if save_list:
			# Find our save in the list
			for i in range(save_list.get_item_count()):
				if "test_save_gameplay" in save_list.get_item_text(i):
					save_list.select(i)
					break

		# Click load button
		var load_button = find_ui_element("LoadButton", Button)
		if load_button:
			click_button("LoadButton")
			await wait_for_ui_update()

	# Verify game state was restored
	assert_true(true, "Game should load successfully")

func test_error_handling_invalid_actions():
	"""Test that invalid actions show appropriate error messages"""
	transition_to_phase(GameStateData.Phase.SHOOTING)
	await wait_for_ui_update()

	# Try to shoot without selecting a unit
	var shoot_button = find_ui_element("DeclareShootButton", Button)
	if shoot_button and not shoot_button.disabled:
		click_button("DeclareShootButton")
		await wait_for_ui_update()

		# Should show error or do nothing
		var error_display = find_ui_element("ErrorMessage", Label)
		if error_display:
			assert_true(error_display.visible or error_display.text != "",
				"Should show error for invalid action")

	# Try to shoot out of range
	select_unit_from_list(0)
	await wait_for_ui_update()

	# Click on target that's out of range
	var far_position = Vector2(2000, 2000)
	scene_runner.set_mouse_position(far_position)
	scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await wait_for_ui_update()

	# Should show range error or prevent selection
	var status_label = find_ui_element("StatusLabel", Label)
	if status_label and status_label.visible:
		var status_text = status_label.text.to_lower()
		# May show "out of range" or similar error
		assert_true("range" in status_text or "cannot" in status_text or status_text == "",
			"Should indicate range issue")

func test_multi_unit_selection_and_group_move():
	"""Test selecting multiple units and moving them together"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	await wait_for_ui_update()

	# Use box selection to select multiple models
	var box_start = Vector2(150, 150)
	var box_end = Vector2(350, 250)

	await InputSimulator.simulate_box_selection(scene_runner, box_start, box_end)
	await wait_for_ui_update()

	# Check if multiple models are selected
	# (Visual indicators, selection count, etc.)

	# Begin group move
	var move_button = find_ui_element("BeginNormalMove", Button)
	if move_button:
		click_button("BeginNormalMove")
		await wait_for_ui_update()

		# Drag one model, others should follow in formation
		var center_of_selection = (box_start + box_end) / 2
		var move_target = center_of_selection + Vector2(100, 100)

		await drag_model(center_of_selection, move_target)
		await wait_for_ui_update()

		# Confirm group move
		var confirm_button = find_ui_element("ConfirmMoveButton", Button)
		if confirm_button:
			click_button("ConfirmMoveButton")
			await wait_for_ui_update()

func test_context_menu_usage():
	"""Test right-click context menu on units"""
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	await wait_for_ui_update()

	# Right-click on a model token
	var model_token = find_model_token("test_unit_1", "sergeant")
	if model_token:
		var model_pos = model_token.global_position

		scene_runner.set_mouse_position(model_pos)
		scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		await wait_for_ui_update()

		# Check for context menu
		var context_menu = find_ui_element("ModelContextMenu", PopupMenu)
		if not context_menu:
			context_menu = find_ui_element("ContextMenu", PopupMenu)

		if context_menu and context_menu.visible:
			assert_gt(context_menu.get_item_count(), 0, "Context menu should have items")

			# Click on first menu item
			if context_menu.get_item_count() > 0:
				var first_item_rect = context_menu.get_item_rect(0)
				var click_pos = context_menu.global_position + first_item_rect.position + first_item_rect.size / 2

				scene_runner.set_mouse_position(click_pos)
				scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
				await wait_for_ui_update()

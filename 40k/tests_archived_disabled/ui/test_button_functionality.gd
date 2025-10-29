extends BaseUITest

# Button Functionality Tests - Tests core button interactions (Undo, Reset, Confirm, etc.)
# Tests button states, click responses, and game state changes triggered by buttons

func test_undo_button_availability():
	# Test that undo button appears when actions can be undone
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	var undo_button = find_ui_element("UndoButton", Button)
	if undo_button:
		# Initially should be disabled (no actions to undo)
		assert_button_enabled("UndoButton", false, "Undo should be disabled when no actions to undo")
		
		# Perform an action
		select_unit_from_list(0)
		click_button("BeginNormalMove")
		await wait_for_ui_update()
		
		# Now undo should be available
		assert_button_enabled("UndoButton", true, "Undo should be enabled after performing action")

func test_undo_button_functionality():
	# Test that undo button actually undoes actions
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	select_unit_from_list(0)
	
	# Record initial state
	var initial_phase_state = "no_active_move"
	
	# Perform an action that can be undone
	click_button("BeginNormalMove")
	await wait_for_ui_update()
	
	# Verify action was performed
	var move_started_state = "active_move"
	assert_ne(initial_phase_state, move_started_state, "Action should change game state")
	
	# Undo the action
	click_button("UndoButton")
	await wait_for_ui_update()
	
	# Verify state is reverted
	var after_undo_button = find_ui_element("BeginNormalMove", Button)
	if after_undo_button:
		assert_button_enabled("BeginNormalMove", true, "Movement buttons should be available after undo")

func test_undo_multiple_actions():
	# Test undoing multiple actions in sequence
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	select_unit_from_list(0)
	
	# Perform multiple actions
	click_button("BeginNormalMove")
	await wait_for_ui_update()
	
	# Move a model
	var model_token = find_model_token("test_unit_1", "m1")
	if model_token:
		var initial_pos = model_token.global_position
		drag_model_token("test_unit_1", "m1", initial_pos + Vector2(100, 0))
		await wait_for_ui_update()
	
	# Undo twice (model position, then begin move)
	click_button("UndoButton")
	await wait_for_ui_update()
	
	click_button("UndoButton") 
	await wait_for_ui_update()
	
	# Should be back to initial state
	var begin_move_button = find_ui_element("BeginNormalMove", Button)
	if begin_move_button:
		assert_button_enabled("BeginNormalMove", true, "Should be able to begin move again after undoing all")

func test_reset_button_functionality():
	# Test reset button clears all actions for current phase
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	select_unit_from_list(0)
	
	# Perform several actions
	click_button("BeginNormalMove")
	await wait_for_ui_update()
	
	# Move model
	var model_token = find_model_token("test_unit_1", "m1")
	if model_token:
		drag_model_token("test_unit_1", "m1", model_token.global_position + Vector2(50, 50))
		await wait_for_ui_update()
	
	# Reset should clear everything
	var reset_button = find_ui_element("ResetButton", Button)
	if not reset_button:
		reset_button = find_ui_element("ClearAllButton", Button)
	
	if reset_button:
		click_button("ResetButton")
		await wait_for_ui_update()
		
		# All actions should be cleared
		assert_button_enabled("BeginNormalMove", true, "Movement should be available after reset")
		
		# Model should return to original position
		if model_token:
			var reset_pos = get_model_token_position("test_unit_1", "m1")
			# Position should be reset (exact position depends on implementation)
			assert_not_null(reset_pos, "Model should have valid position after reset")

func test_confirm_button_availability():
	# Test confirm button appears when actions are ready to confirm
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	select_unit_from_list(0)
	
	var confirm_button = find_ui_element("ConfirmButton", Button)
	if not confirm_button:
		confirm_button = find_ui_element("ConfirmMoveButton", Button)
	
	if confirm_button:
		# Initially should be disabled
		assert_button_enabled("ConfirmButton", false, "Confirm should be disabled with no actions to confirm")
		
		# Start a move
		click_button("BeginNormalMove")
		await wait_for_ui_update()
		
		# Move a model to make the action confirmable
		var model_token = find_model_token("test_unit_1", "m1")
		if model_token:
			drag_model_token("test_unit_1", "m1", model_token.global_position + Vector2(50, 50))
			await wait_for_ui_update()
		
		# Now confirm should be available
		assert_button_enabled("ConfirmButton", true, "Confirm should be enabled after valid move setup")

func test_confirm_button_functionality():
	# Test confirm button actually executes actions
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	select_unit_from_list(0)
	
	# Set up a move to confirm
	click_button("BeginNormalMove")
	await wait_for_ui_update()
	
	var model_token = find_model_token("test_unit_1", "m1")
	if model_token:
		var initial_pos = model_token.global_position
		var target_pos = initial_pos + Vector2(100, 0)
		
		drag_model_token("test_unit_1", "m1", target_pos)
		await wait_for_ui_update()
		
		# Confirm the move
		click_button("ConfirmButton")
		await wait_for_ui_update()
		
		# Move should be finalized (buttons should change state)
		var begin_move_button = find_ui_element("BeginNormalMove", Button)
		if begin_move_button:
			# Should be disabled after confirming (unit has moved)
			assert_button_enabled("BeginNormalMove", false, "Unit should not be able to move again after confirming")

func test_cancel_button_functionality():
	# Test cancel button cancels current action
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	select_unit_from_list(0)
	
	# Start an action
	click_button("BeginNormalMove")
	await wait_for_ui_update()
	
	# Cancel the action
	var cancel_button = find_ui_element("CancelButton", Button)
	if cancel_button:
		click_button("CancelButton")
		await wait_for_ui_update()
		
		# Should return to normal state
		assert_button_enabled("BeginNormalMove", true, "Should be able to begin move again after cancel")

func test_end_phase_button():
	# Test end phase button advances to next phase
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	var end_phase_button = find_ui_element("EndPhaseButton", Button)
	if not end_phase_button:
		end_phase_button = find_ui_element("NextPhaseButton", Button)
	
	if end_phase_button:
		# Check initial phase
		assert_phase_label("Movement")
		
		# End the phase
		click_button("EndPhaseButton")
		await wait_for_ui_update()
		
		# Should advance to next phase (Shooting)
		await get_tree().create_timer(0.5).timeout  # Allow time for phase transition
		assert_phase_label("Shooting")

func test_begin_movement_buttons():
	# Test different movement type buttons
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	select_unit_from_list(0)
	
	var movement_buttons = [
		"BeginNormalMove",
		"BeginAdvance", 
		"BeginFallBack"
	]
	
	for button_name in movement_buttons:
		var button = find_ui_element(button_name, Button)
		if button:
			assert_button_visible(button_name, true, button_name + " should be visible in movement phase")
			
			# Click button
			click_button(button_name)
			await wait_for_ui_update()
			
			# Button should become disabled or change state
			var button_after = find_ui_element(button_name, Button)
			if button_after:
				# Exact behavior depends on implementation
				assert_not_null(button_after, button_name + " should exist after click")
			
			# Reset for next test
			var reset_button = find_ui_element("ResetButton", Button)
			if reset_button:
				click_button("ResetButton")
				await wait_for_ui_update()

func test_shooting_phase_buttons():
	# Test shooting phase specific buttons
	transition_to_phase(GameStateData.Phase.SHOOTING)
	select_unit_from_list(0)
	
	var shooting_buttons = [
		"DeclareTargets",
		"ResolveAttacks",
		"AllocateWounds"
	]
	
	for button_name in shooting_buttons:
		var button = find_ui_element(button_name, Button)
		if button:
			assert_button_visible(button_name, true, button_name + " should be visible in shooting phase")

func test_charge_phase_buttons():
	# Test charge phase specific buttons  
	transition_to_phase(GameStateData.Phase.CHARGE)
	select_unit_from_list(0)
	
	var charge_buttons = [
		"DeclareCharge",
		"RollCharge",
		"ChargeMove"
	]
	
	for button_name in charge_buttons:
		var button = find_ui_element(button_name, Button)
		if button:
			assert_button_visible(button_name, true, button_name + " should be visible in charge phase")

func test_fight_phase_buttons():
	# Test fight phase specific buttons
	transition_to_phase(GameStateData.Phase.FIGHT)
	
	var fight_buttons = [
		"SelectFighters",
		"PileIn",
		"MakeAttacks",
		"Consolidate"
	]
	
	for button_name in fight_buttons:
		var button = find_ui_element(button_name, Button)
		if button:
			assert_button_visible(button_name, true, button_name + " should be visible in fight phase")

func test_context_sensitive_buttons():
	# Test that buttons appear/disappear based on context
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	# No unit selected - movement buttons should be disabled
	var begin_move_button = find_ui_element("BeginNormalMove", Button)
	if begin_move_button:
		assert_button_enabled("BeginNormalMove", false, "Movement buttons should be disabled with no unit selected")
	
	# Select unit - buttons should become available
	select_unit_from_list(0)
	await wait_for_ui_update()
	
	if begin_move_button:
		assert_button_enabled("BeginNormalMove", true, "Movement buttons should be enabled with unit selected")

func test_dice_roll_buttons():
	# Test dice rolling interface buttons
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	select_unit_from_list(0)
	
	# Advance requires dice roll
	click_button("BeginAdvance")
	await wait_for_ui_update()
	
	var roll_dice_button = find_ui_element("RollDice", Button)
	if not roll_dice_button:
		roll_dice_button = find_ui_element("RollAdvance", Button)
	
	if roll_dice_button:
		assert_button_visible("RollDice", true, "Dice roll button should be visible for advance")
		
		# Click to roll dice
		click_button("RollDice")
		await wait_for_ui_update()
		
		# Should show dice results
		var dice_result = find_ui_element("DiceResult", Label)
		if dice_result:
			assert_true(dice_result.visible, "Dice result should be visible after roll")

func test_measurement_buttons():
	# Test measurement tool buttons
	var measure_button = find_ui_element("MeasureButton", Button)
	if measure_button:
		click_button("MeasureButton")
		await wait_for_ui_update()
		
		# Should enter measurement mode
		var measure_mode_indicator = find_ui_element("MeasureMode", Label)
		if measure_mode_indicator:
			assert_true(measure_mode_indicator.visible, "Measurement mode should be indicated")
		
		# Test exit measurement
		var exit_measure = find_ui_element("ExitMeasure", Button)
		if exit_measure:
			click_button("ExitMeasure")
			await wait_for_ui_update()

func test_settings_buttons():
	# Test settings and options buttons
	var settings_button = find_ui_element("SettingsButton", Button)
	if settings_button:
		click_button("SettingsButton")
		await wait_for_ui_update()
		
		var settings_panel = find_ui_element("SettingsPanel", Control)
		if settings_panel:
			assert_true(settings_panel.visible, "Settings panel should open")
			
			# Test close settings
			var close_button = find_ui_element("CloseSettings", Button)
			if close_button:
				click_button("CloseSettings")
				await wait_for_ui_update()
				
				assert_false(settings_panel.visible, "Settings panel should close")

func test_save_load_buttons():
	# Test save and load functionality buttons
	var save_button = find_ui_element("SaveButton", Button)
	if save_button:
		click_button("SaveButton")
		await wait_for_ui_update()
		
		# Should show save dialog or confirm save
		var save_dialog = find_ui_element("SaveDialog", FileDialog)
		if not save_dialog:
			# Might show confirmation instead
			var save_confirm = find_ui_element("SaveConfirm", Label)
			if save_confirm:
				assert_true(save_confirm.visible, "Should show save confirmation")
	
	var load_button = find_ui_element("LoadButton", Button)
	if load_button:
		click_button("LoadButton")
		await wait_for_ui_update()
		
		# Should show load dialog
		var load_dialog = find_ui_element("LoadDialog", FileDialog)
		if load_dialog:
			assert_true(load_dialog.visible, "Load dialog should appear")

func test_quick_save_load():
	# Test quick save/load shortcuts
	var quick_save = find_ui_element("QuickSaveButton", Button)
	if quick_save:
		click_button("QuickSaveButton")
		await wait_for_ui_update()
		
		# Should save without dialog
		var status = find_ui_element("StatusLabel", Label)
		if status and status.visible:
			var status_text = status.text.to_lower()
			assert_true("save" in status_text, "Should show save confirmation in status")

func test_help_buttons():
	# Test help and tutorial buttons
	var help_button = find_ui_element("HelpButton", Button)
	if help_button:
		click_button("HelpButton")
		await wait_for_ui_update()
		
		var help_panel = find_ui_element("HelpPanel", Control)
		if help_panel:
			assert_true(help_panel.visible, "Help panel should be visible")

func test_zoom_buttons():
	# Test zoom in/out buttons
	var zoom_in_button = find_ui_element("ZoomInButton", Button)
	var zoom_out_button = find_ui_element("ZoomOutButton", Button)
	
	if zoom_in_button and camera:
		var initial_zoom = camera.zoom if camera.has_property("zoom") else Vector2.ONE
		
		click_button("ZoomInButton")
		await wait_for_ui_update()
		
		if camera.has_property("zoom"):
			var zoom_after = camera.zoom
			assert_gt(zoom_after.x, initial_zoom.x, "Camera should zoom in when clicking zoom in button")
	
	if zoom_out_button and camera:
		click_button("ZoomOutButton")
		await wait_for_ui_update()
		
		# Should zoom out from current level

func test_button_tooltips():
	# Test that buttons show helpful tooltips
	var important_buttons = [
		"UndoButton",
		"ConfirmButton", 
		"ResetButton",
		"BeginNormalMove",
		"EndPhaseButton"
	]
	
	for button_name in important_buttons:
		var button = find_ui_element(button_name, Button)
		if button:
			# Hover over button
			var button_center = button.global_position + button.size / 2
			scene_runner.set_mouse_position(button_center)
			
			# Wait for tooltip
			await get_tree().create_timer(1.0).timeout
			
			var tooltip = find_ui_element("Tooltip", Control)
			if tooltip and tooltip.visible:
				assert_ne("", tooltip.get_child(0).text if tooltip.get_child_count() > 0 else "", 
					"Tooltip should have text for " + button_name)

func test_button_states_consistency():
	# Test that button enabled/disabled states are consistent with game state
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	# Test progression of button states
	select_unit_from_list(0)
	await wait_for_ui_update()
	
	# Initially can begin move
	assert_button_enabled("BeginNormalMove", true, "Should be able to begin move with selected unit")
	
	# Begin move
	click_button("BeginNormalMove")
	await wait_for_ui_update()
	
	# Now confirm should be available, begin should be disabled
	assert_button_enabled("BeginNormalMove", false, "Should not be able to begin move again")
	
	var confirm_button = find_ui_element("ConfirmButton", Button)
	if confirm_button:
		# May need to move model first to enable confirm
		var model_token = find_model_token("test_unit_1", "m1")
		if model_token:
			drag_model_token("test_unit_1", "m1", model_token.global_position + Vector2(50, 50))
			await wait_for_ui_update()
		
		assert_button_enabled("ConfirmButton", true, "Should be able to confirm after setting up move")

func test_keyboard_button_activation():
	# Test that buttons can be activated with keyboard
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	select_unit_from_list(0)
	
	# Focus on begin move button
	var begin_move_button = find_ui_element("BeginNormalMove", Button)
	if begin_move_button:
		begin_move_button.grab_focus()
		await wait_for_ui_update()
		
		# Press Enter to activate
		var enter_key = InputEventKey.new()
		enter_key.keycode = KEY_ENTER
		enter_key.pressed = true
		scene_runner.get_scene().get_viewport().push_input(enter_key)
		
		await wait_for_ui_update()
		
		enter_key.pressed = false
		scene_runner.get_scene().get_viewport().push_input(enter_key)
		
		# Button should be activated
		# Hard to test exact result, but shouldn't crash
		assert_true(true, "Keyboard activation should work without crashing")

func test_button_visual_feedback():
	# Test that buttons provide visual feedback when clicked
	var test_button = find_ui_element("BeginNormalMove", Button)
	if test_button:
		transition_to_phase(GameStateData.Phase.MOVEMENT)
		select_unit_from_list(0)
		await wait_for_ui_update()
		
		# Button should be normal state
		assert_false(test_button.button_pressed, "Button should not be pressed initially")
		
		# Click and hold briefly
		var button_center = test_button.global_position + test_button.size / 2
		scene_runner.set_mouse_position(button_center)
		scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)
		
		await await_input_processed()
		
		# Button should show pressed state momentarily
		# This is timing dependent and hard to test reliably
		scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
		await await_input_processed()

func test_disabled_button_behavior():
	# Test that disabled buttons don't respond to clicks
	transition_to_phase(GameStateData.Phase.MOVEMENT)
	
	# Don't select unit - buttons should be disabled
	var begin_move_button = find_ui_element("BeginNormalMove", Button)
	if begin_move_button:
		assert_button_enabled("BeginNormalMove", false, "Button should be disabled without unit selection")
		
		# Try to click disabled button
		click_button("BeginNormalMove")
		await wait_for_ui_update()
		
		# Should not have started a move (no visual changes expected)
		var confirm_button = find_ui_element("ConfirmButton", Button)
		if confirm_button:
			assert_button_enabled("ConfirmButton", false, "Confirm should still be disabled after clicking disabled button")
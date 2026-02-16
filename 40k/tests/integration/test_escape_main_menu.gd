extends SceneTree

# Integration test: Verifies that pressing Escape during gameplay shows the
# SaveLoadDialog with a "Main Menu" button, and clicking it returns to MainMenu.
#
# Run with: godot --headless --path 40k -s tests/integration/test_escape_main_menu.gd

var _passed := 0
var _failed := 0
var _main_node: Node = null

func _initialize():
	_run_test.call_deferred()

func _run_test():
	print("\n=== Integration Test: Escape Menu -> Main Menu ===\n")

	# Step 1: Change to the Main game scene
	print("[Step 1] Loading Main.tscn...")
	var err = change_scene_to_file("res://scenes/Main.tscn")
	if err != OK:
		_fail("Failed to load Main.tscn: error %d" % err)
		_finish()
		return

	# Wait for scene to fully load and initialize
	await create_timer(3.0).timeout

	_main_node = current_scene
	if not _main_node:
		_fail("current_scene is null after loading Main.tscn")
		_finish()
		return
	_pass("Main.tscn loaded, current_scene = '%s'" % _main_node.name)

	# Step 2: Find the SaveLoadDialog
	print("[Step 2] Checking SaveLoadDialog exists...")
	var save_load_dialog = _main_node.get_node_or_null("SaveLoadDialog")
	if not save_load_dialog:
		# It might need more time to set up
		await create_timer(1.0).timeout
		save_load_dialog = _main_node.get_node_or_null("SaveLoadDialog")

	if not save_load_dialog:
		_fail("SaveLoadDialog node not found in Main scene")
		_finish()
		return
	_pass("SaveLoadDialog found in Main scene")

	# Step 3: Verify dialog is initially hidden
	print("[Step 3] Checking dialog is initially hidden...")
	if save_load_dialog.visible:
		_fail("SaveLoadDialog should be hidden initially")
	else:
		_pass("SaveLoadDialog is hidden initially")

	# Step 4: Simulate pressing Escape by calling _toggle_save_load_menu
	print("[Step 4] Simulating Escape key (toggle save/load menu)...")
	if _main_node.has_method("_toggle_save_load_menu"):
		_main_node._toggle_save_load_menu()
		await create_timer(0.5).timeout

		if save_load_dialog.visible:
			_pass("SaveLoadDialog is now visible after toggle")
		else:
			_fail("SaveLoadDialog should be visible after toggle")
	else:
		_fail("Main scene doesn't have _toggle_save_load_menu method")
		_finish()
		return

	# Step 5: Check Main Menu button exists
	print("[Step 5] Checking MainMenuButton exists in dialog...")
	var main_menu_btn = save_load_dialog.get_node_or_null("VBoxContainer/LoadSection/LoadButtonContainer/MainMenuButton")
	if main_menu_btn:
		_pass("MainMenuButton found with text: '%s'" % main_menu_btn.text)
	else:
		_fail("MainMenuButton not found in SaveLoadDialog")
		_finish()
		return

	# Step 6: Press the Main Menu button
	print("[Step 6] Pressing Main Menu button...")
	main_menu_btn.emit_signal("pressed")
	await create_timer(0.5).timeout

	# Step 7: Find and verify the confirmation dialog
	print("[Step 7] Checking confirmation dialog appeared...")
	var confirmation: ConfirmationDialog = null
	for child in current_scene.get_children():
		if child is ConfirmationDialog:
			confirmation = child
			break

	if confirmation:
		_pass("Confirmation dialog appeared: '%s'" % confirmation.dialog_text)
		if "unsaved progress" in confirmation.dialog_text:
			_pass("Confirmation warns about unsaved progress")
		else:
			_fail("Confirmation text should mention 'unsaved progress'")
	else:
		_fail("No ConfirmationDialog found after pressing Main Menu button")
		_finish()
		return

	# Step 8: Confirm the dialog (accept returning to main menu)
	print("[Step 8] Confirming return to Main Menu...")
	confirmation.emit_signal("confirmed")
	await create_timer(2.0).timeout

	# Step 9: Verify we're back at MainMenu
	print("[Step 9] Verifying scene changed to MainMenu...")
	var new_scene = current_scene
	if new_scene and new_scene.name == "MainMenu":
		_pass("Successfully returned to MainMenu scene!")
	elif new_scene:
		_fail("Expected MainMenu scene, got: '%s'" % new_scene.name)
	else:
		_fail("current_scene is null after confirming")

	_finish()

func _pass(msg: String):
	_passed += 1
	print("  PASS: %s" % msg)

func _fail(msg: String):
	_failed += 1
	print("  FAIL: %s" % msg)

func _finish():
	print("\n=== Results: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit(_failed)

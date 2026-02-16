extends "res://addons/gut/test.gd"

# Tests for the "Main Menu" button in the SaveLoadDialog
# Verifies:
# 1. The MainMenuButton node exists in the scene
# 2. The main_menu_requested signal is defined
# 3. Pressing the button shows a confirmation dialog with warning text
# 4. Confirming the dialog emits main_menu_requested

var dialog: Node = null
var signal_received: bool = false

func before_each():
	signal_received = false
	var scene = preload("res://scenes/SaveLoadDialog.tscn")
	dialog = scene.instantiate()
	add_child(dialog)

func after_each():
	if dialog and is_instance_valid(dialog):
		# Clean up any confirmation dialogs on the dialog's parent
		var parent = dialog.get_parent()
		if parent:
			for child in parent.get_children():
				if child is ConfirmationDialog:
					child.queue_free()
		dialog.queue_free()
		dialog = null

func _find_confirmation_dialog() -> ConfirmationDialog:
	# The confirmation gets added to the dialog's parent (this test node)
	var parent = dialog.get_parent()
	if parent:
		for child in parent.get_children():
			if child is ConfirmationDialog:
				return child
	return null

func test_main_menu_button_exists():
	var btn = dialog.get_node_or_null("VBoxContainer/LoadSection/LoadButtonContainer/MainMenuButton")
	assert_not_null(btn, "MainMenuButton node should exist in the dialog")
	assert_eq(btn.text, "Main Menu", "Button text should be 'Main Menu'")

func test_main_menu_signal_defined():
	# Check the signal exists by verifying we can connect to it
	var callable = Callable(self, "_on_main_menu_signal")
	var err = dialog.main_menu_requested.connect(callable)
	assert_eq(err, OK, "Should be able to connect to main_menu_requested signal")
	dialog.main_menu_requested.disconnect(callable)

func test_main_menu_button_shows_confirmation():
	# Wait for _ready to complete (it has an await inside)
	await get_tree().process_frame
	await get_tree().process_frame

	# Show the dialog first
	dialog.popup_centered()
	await get_tree().process_frame

	var btn = dialog.get_node_or_null("VBoxContainer/LoadSection/LoadButtonContainer/MainMenuButton")
	assert_not_null(btn, "MainMenuButton should exist")

	# Press the button
	btn.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame

	# Look for the ConfirmationDialog
	var confirmation = _find_confirmation_dialog()
	assert_not_null(confirmation, "A ConfirmationDialog should appear when Main Menu button is pressed")
	if confirmation:
		assert_true(confirmation.dialog_text.contains("unsaved progress"), "Confirmation should warn about unsaved progress")

func test_confirming_emits_signal():
	# Wait for _ready to complete (it has an await inside)
	await get_tree().process_frame
	await get_tree().process_frame

	# Connect to the signal
	dialog.main_menu_requested.connect(_on_main_menu_signal)

	# Show the dialog
	dialog.popup_centered()
	await get_tree().process_frame

	var btn = dialog.get_node_or_null("VBoxContainer/LoadSection/LoadButtonContainer/MainMenuButton")
	btn.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame

	# Find and confirm the confirmation dialog
	var confirmation = _find_confirmation_dialog()
	assert_not_null(confirmation, "ConfirmationDialog should exist")
	if confirmation:
		confirmation.emit_signal("confirmed")
		await get_tree().process_frame
		await get_tree().process_frame

	assert_true(signal_received, "main_menu_requested signal should be emitted after confirming")

func _on_main_menu_signal():
	signal_received = true

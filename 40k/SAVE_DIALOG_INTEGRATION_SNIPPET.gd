# Save Dialog Integration Snippet
# Add this code to ShootingController.gd or Main.gd to complete Phase 1 MVP

# ===== OPTION 1: Add to ShootingController._ready() =====
func _ready():
	# ... existing code ...

	# Connect to shooting phase for save resolution
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if phase_manager:
		# We need to get the phase instance when it's created
		# This might require connecting to a phase_changed signal
		phase_manager.phase_changed.connect(_on_phase_changed)

func _on_phase_changed(new_phase_type: GameStateData.Phase):
	"""Connect to shooting phase when it becomes active"""
	if new_phase_type == GameStateData.Phase.SHOOTING:
		var phase_manager = get_node("/root/PhaseManager")
		var shooting_phase = phase_manager.get_current_phase_instance()

		if shooting_phase and not shooting_phase.saves_required.is_connected(_on_saves_required):
			shooting_phase.saves_required.connect(_on_saves_required)
			print("ShootingController: Connected to saves_required signal")

func _on_saves_required(save_data_list: Array):
	"""Show SaveDialog when defender needs to make saves"""
	print("ShootingController: Saves required for %d targets" % save_data_list.size())

	if save_data_list.is_empty():
		print("ShootingController: Warning - empty save data list")
		return

	# For Phase 1 MVP: Handle first save data only
	# (Multiple simultaneous targets handled in Phase 2)
	var save_data = save_data_list[0]

	# Load SaveDialog script
	var save_dialog_script = preload("res://scripts/SaveDialog.gd")
	var dialog = save_dialog_script.new()

	# Setup with save data
	dialog.setup(save_data)

	# Add to scene tree
	get_tree().root.add_child(dialog)

	# Show dialog
	dialog.popup_centered()

	print("ShootingController: SaveDialog shown for %s" % save_data.get("target_unit_name", "Unknown"))

# ===== OPTION 2: Add to Main.gd _ready() (if no ShootingController) =====
func _ready():
	# ... existing code ...

	# Connect to PhaseManager for save resolution
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if phase_manager:
		phase_manager.phase_changed.connect(_on_phase_changed_for_saves)

func _on_phase_changed_for_saves(new_phase_type: GameStateData.Phase):
	"""Connect to shooting phase for interactive saves"""
	if new_phase_type == GameStateData.Phase.SHOOTING:
		var phase_manager = get_node("/root/PhaseManager")
		var shooting_phase = phase_manager.get_current_phase_instance()

		if shooting_phase and not shooting_phase.saves_required.is_connected(_show_save_dialog):
			shooting_phase.saves_required.connect(_show_save_dialog)

func _show_save_dialog(save_data_list: Array):
	"""Display SaveDialog for defender to make saves"""
	if save_data_list.is_empty():
		return

	# Create and show dialog for first target
	var save_dialog_script = preload("res://scripts/SaveDialog.gd")
	var dialog = save_dialog_script.new()
	dialog.setup(save_data_list[0])
	add_child(dialog)
	dialog.popup_centered()

# ===== OPTION 3: Minimal - Just add to any node that's always active =====
# This can even go in an autoload if you create one for UI management

extends Node

func _ready():
	# Wait for scene tree to be ready
	await get_tree().process_frame

	# Find PhaseManager and connect
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if phase_manager:
		phase_manager.phase_changed.connect(func(phase_type):
			if phase_type == GameStateData.Phase.SHOOTING:
				var sp = phase_manager.get_current_phase_instance()
				if sp:
					sp.saves_required.connect(func(save_data_list):
						if not save_data_list.is_empty():
							var dialog = preload("res://scripts/SaveDialog.gd").new()
							dialog.setup(save_data_list[0])
							get_tree().root.add_child(dialog)
							dialog.popup_centered()
					)
		)

# ===== TESTING VERIFICATION =====
# After adding one of the above options:
# 1. Run the game
# 2. Enter shooting phase
# 3. Select a unit to shoot
# 4. Assign targets and confirm
# 5. You should see:
#    - "ShootingPhase: Awaiting defender to make saves..." in console
#    - SaveDialog popup appear
#    - Attack information displayed
#    - Model allocation grid shown
# 6. Click "Roll All Saves"
# 7. Should see dice results in log
# 8. Click "Apply Damage"
# 9. Dialog should close
# 10. Damage should be applied to target unit
# 11. Shooting should continue normally

# ===== TROUBLESHOOTING =====
# If dialog doesn't appear:
# - Check console for "saves_required" signal emission
# - Verify PhaseManager exists at /root/PhaseManager
# - Check that shooting_phase.saves_required signal is properly connected
# - Use print() statements to debug signal flow

# If action fails:
# - Check NetworkManager is receiving APPLY_SAVES action
# - Verify payload contains save_results_list
# - Check ShootingPhase._process_apply_saves() is being called
# - Look for validation errors in console

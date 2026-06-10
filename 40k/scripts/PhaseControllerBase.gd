class_name PhaseControllerBase
extends Node2D

## Shared base for the per-phase UI controllers (ISS-005):
## DeploymentController, MovementController, ShootingController,
## ChargeController, FightController.
##
## Owns the common UI-reference lookup that every controller used to
## copy-paste. Subclasses override the hooks:
##   _on_ui_references_ready() — extra setup once refs are resolved
##   _setup_bottom_hud()       — phase-specific HUD_Bottom contents
##   _setup_right_panel()      — phase-specific HUD_Right contents
##
## Further consolidation (signal registry, per-phase UI container, input
## gating) lands with ISS-013 / ISS-018 / ISS-008 on top of this base.

var board_view: Node2D
var hud_bottom: Control
var hud_right: Control


func _setup_ui_references() -> void:
	# Get references to UI nodes
	board_view = get_node_or_null("/root/Main/BoardRoot/BoardView")
	hud_bottom = get_node_or_null("/root/Main/HUD_Bottom")
	hud_right = get_node_or_null("/root/Main/HUD_Right")

	_on_ui_references_ready()

	if hud_bottom:
		_setup_bottom_hud()
	if hud_right:
		_setup_right_panel()


## Override for controller-specific setup that must run after the UI
## references are resolved but before the HUD sections are built.
func _on_ui_references_ready() -> void:
	pass


## Override to build the phase-specific HUD_Bottom contents.
func _setup_bottom_hud() -> void:
	pass


## Override to build the phase-specific HUD_Right contents.
func _setup_right_panel() -> void:
	pass


func get_board_root() -> Node:
	return get_node_or_null("/root/Main/BoardRoot")


# ── ISS-013: phase signal registry ──────────────────────────────────
# Subclasses declare the phase signals they consume; attach/detach connect
# and disconnect them symmetrically. This replaces both the per-signal
# reconnect-guard blocks in set_phase and the manual per-signal disconnect
# blocks in Main's phase teardown.

var _attached_phase = null


## Override: {signal_name (String): handler (Callable)} for every phase
## signal this controller consumes. Signals missing on the phase instance
## are skipped (some are phase-variant specific).
func phase_signal_map() -> Dictionary:
	return {}


## Connect this controller's declared signals to the phase. Re-attaching is
## safe: any previous attachment is detached first, and existing duplicate
## connections are cleared before connecting.
func attach_phase(phase) -> void:
	detach_phase()
	_attached_phase = phase
	if phase == null:
		return
	var map := phase_signal_map()
	var connected := 0
	for sig in map:
		if not phase.has_signal(sig):
			continue
		if phase.is_connected(sig, map[sig]):
			phase.disconnect(sig, map[sig])
		phase.connect(sig, map[sig])
		connected += 1
	print("[%s] attach_phase: connected %d/%d phase signals (instance %d)" % [name, connected, map.size(), get_instance_id()])


## Disconnect every declared signal from the previously attached phase.
## Safe to call repeatedly and during teardown.
func detach_phase() -> void:
	if _attached_phase != null and is_instance_valid(_attached_phase):
		var map := phase_signal_map()
		var disconnected := 0
		for sig in map:
			if _attached_phase.has_signal(sig) and _attached_phase.is_connected(sig, map[sig]):
				_attached_phase.disconnect(sig, map[sig])
				disconnected += 1
		if disconnected > 0:
			print("[%s] detach_phase: disconnected %d phase signals (instance %d)" % [name, disconnected, get_instance_id()])
	_attached_phase = null

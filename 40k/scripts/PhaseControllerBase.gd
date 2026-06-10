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

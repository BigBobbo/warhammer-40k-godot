extends Node

# UnitExhaustionTracker — T09 (design doc §8, exhaustion shading).
#
# "Units that have completed their action this phase go grayscale on the strip
# and on the board": every token of a unit that has acted this phase dims to
# TokenVisual.T09_EXHAUSTION_MODULATE and its roster card (LeftRosterStrip)
# swaps to a dimmer stylebox, until the phase ends.
#
# The phases decide who has acted (BasePhase.has_unit_acted_this_phase — moved,
# shot, charged, fought) and emit BasePhase.unit_acted_in_phase(unit_id) when
# that answer flips to true. This node binds to the current phase instance's
# signal and re-syncs the board and the strip on:
#   - unit_acted_in_phase        the flip (single player / host)
#   - phase_action_taken         every other action (safety net)
#   - GameManager.result_applied a network client: the host's diffs land here,
#                                and the client's phase never runs execute_action
#   - phase_changed              rebind to the new phase; everything resets
# Tokens rebuilt mid-phase (Main._recreate_unit_visuals) pick their state up in
# TokenVisual._ready().
#
# Public state for scenarios:
#   acted_unit_ids : Array    units the current phase reports as acted (sorted)
#   last_acted_unit_id : String / acted_signal_count : int
#                             the unit_acted_in_phase signals received
#   refresh()                 re-sync now
#
# Installed as /root/Main/UnitExhaustionTracker by
# Main._install_design_guidelines_overlays.

var acted_unit_ids: Array = []
var last_acted_unit_id: String = ""
var acted_signal_count: int = 0

var _bound_phase: Node = null


func _ready() -> void:
	name = "UnitExhaustionTracker"
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null:
		if not pm.phase_changed.is_connected(_on_phase_changed):
			pm.phase_changed.connect(_on_phase_changed)
		if not pm.phase_action_taken.is_connected(_on_phase_action_taken):
			pm.phase_action_taken.connect(_on_phase_action_taken)
	var gm = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("result_applied") and not gm.result_applied.is_connected(_on_result_applied):
		gm.result_applied.connect(_on_result_applied)
	_bind_current_phase()
	call_deferred("refresh")


func _bind_current_phase() -> void:
	var pm = get_node_or_null("/root/PhaseManager")
	var phase = pm.get("current_phase_instance") if pm != null else null
	if phase == _bound_phase:
		return
	if _bound_phase != null and is_instance_valid(_bound_phase) \
			and _bound_phase.unit_acted_in_phase.is_connected(_on_unit_acted_in_phase):
		_bound_phase.unit_acted_in_phase.disconnect(_on_unit_acted_in_phase)
	_bound_phase = null
	if phase != null and is_instance_valid(phase) and phase.has_signal("unit_acted_in_phase"):
		phase.unit_acted_in_phase.connect(_on_unit_acted_in_phase)
		_bound_phase = phase


func _on_phase_changed(_new_phase) -> void:
	_bind_current_phase()
	refresh()


func _on_unit_acted_in_phase(unit_id: String) -> void:
	last_acted_unit_id = unit_id
	acted_signal_count += 1
	DebugLogger.info("[UnitExhaustionTracker] T09: %s acted this phase — dimming its tokens and roster card" % unit_id)
	refresh()


func _on_phase_action_taken(_action: Dictionary) -> void:
	refresh()


func _on_result_applied(_result: Dictionary) -> void:
	# A client's phase instance can change under us (phase sync), so rebind first.
	_bind_current_phase()
	refresh()


## Re-derive every token's and roster card's dim state from the current phase.
func refresh() -> void:
	var pm = get_node_or_null("/root/PhaseManager")
	var phase = pm.get("current_phase_instance") if pm != null else null
	if phase != null and is_instance_valid(phase) and phase.has_method("get_units_acted_this_phase"):
		acted_unit_ids = phase.get_units_acted_this_phase()
	else:
		acted_unit_ids = []
	var main = get_parent()
	if main == null:
		return
	var layer = main.get_node_or_null("BoardRoot/TokenLayer")
	if layer != null:
		for child in layer.get_children():
			# Flat tokens carry the TokenVisual script themselves; deployment
			# wrappers hold it as a child (Main._resolve_token_meta_node).
			if child.has_method("refresh_exhaustion"):
				child.refresh_exhaustion()
				continue
			for grandchild in child.get_children():
				if grandchild.has_method("refresh_exhaustion"):
					grandchild.refresh_exhaustion()
	var roster = main.get_node_or_null("LeftRoster")
	if roster != null and roster.has_method("refresh_exhaustion"):
		roster.refresh_exhaustion()

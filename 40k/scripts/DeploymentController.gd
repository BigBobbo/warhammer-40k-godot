extends PhaseControllerBase
# All classes (GameStateData, BaseShape, CircularBase, OvalBase) are available via class_name
# No preloads needed - using global class names to avoid web export reload issues

signal deployment_complete()
signal unit_confirmed()
signal models_placed_changed()
signal coherency_warning_changed(is_incoherent: bool, message: String)
# T-026: emitted after a Combat Squads / Patrol Squad split so the host UI
# can refresh the undeployed list and re-route the click to either half.
signal unit_split_completed(source_unit_id: String, sibling_unit_id: String)

var unit_id: String = ""
var model_idx: int = -1
var temp_positions: Array = []
var temp_rotations: Array = []  # Store rotations for each model
var placement_order: Array = []  # MA-16: Track order of model placement for non-sequential undo
# Rotation carry-over: when the player rotates a model during deployment, the
# NEXT model in the same unit starts at that same rotation instead of snapping
# back to the default enemy-facing. Reset per unit in begin_deploy(). Stays null
# until the first model is placed, so the first model keeps the auto-face default.
var _last_deploy_rotation = null  # float (radians) or null
var token_layer: Node2D
var ghost_layer: Node2D
var ghost_sprite: Node2D = null
var placed_tokens: Array = []

# Formation deployment state
var formation_mode: String = "SINGLE"  # SINGLE, SPREAD, TIGHT
var formation_size: int = 5  # Models per formation group
var formation_preview_ghosts: Array = []  # Ghost visuals for formation
var formation_anchor_pos: Vector2  # Where user clicks to place formation
var formation_rotation: float = 0.0  # Rotation angle for formation (radians)

# Model repositioning state
var repositioning_model: bool = false
# Count of repositions that actually COMMITTED (a lift that passed validation and
# landed). Lets an observer distinguish "picked a model up" from "moved it and
# dropped it somewhere legal" — the T2 tutorial's nudge step ticks its two
# checklist boxes off exactly that difference. A cancelled or rejected drop does
# not count.
var reposition_commits: int = 0
var reposition_model_index: int = -1
var reposition_start_pos: Vector2
var reposition_ghost: Node2D = null

# Coherency distance display label (floating near ghost during placement)
var coherency_distance_label: Label = null

# Coherency visualization circles around placed models (DEPLOY-VIS-5)
var coherency_circles: Array = []

# Transport embark state
var pending_embark_units: Array = []  # Units to embark after deployment
var is_awaiting_embark_dialog: bool = false  # Waiting for transport embark dialog

# Character attachment state
var pending_attach_characters: Array = []  # Characters to attach after deployment
var is_awaiting_attach_dialog: bool = false  # Waiting for character attach dialog

# Combined deployment state (bodyguard + pre-declared attached characters)
var combined_models: Array = []  # [{unit_id, model_idx, model_data}, ...]
var is_combined_deployment: bool = false

# Reinforcement mode (Deep Strike / Strategic Reserves arrival)
var is_reinforcement_mode: bool = false
# P2-80: Override placement type (when DS unit from SR chooses DS rules)
var reinforcement_placement_type: String = ""

# Infiltrators mode (deploy anywhere >9" from enemy zone and enemy models)
var is_infiltrators_mode: bool = false

# Stand-off distances enforced during placement, edge-to-edge in inches. Named
# so the validators below and the exclusion-clamp bubble builder cannot drift
# apart: the clamp parks the ghost exactly on one of these boundaries, so if it
# measured a different distance from the validator it would park the model on a
# line the click then rejects.
# The two enemy stand-offs are EDITION-DEPENDENT (11e dropped both from 9" to
# 8" — 20.04 Ingress Move and 24.20 Infiltrators), so they are functions rather
# than consts: baked in as 9.0 they silently disagreed with the validators that
# actually judge the placement (MovementPhase / DeploymentPhase both read
# GameConstants), and the UI spent all of 11e refusing legal 8-9" placements.
func _reinforcement_enemy_standoff_inches() -> float:
	return GameConstants.reinforcement_min_enemy_distance_inches()

func _infiltrators_enemy_standoff_inches() -> float:
	return GameConstants.infiltrators_min_enemy_distance_inches()

const OMNI_SCRAMBLER_STANDOFF_INCHES: float = 12.0

## 20.04 SET-UP DISTANCE — how far from a battlefield edge a Strategic Reserves
## unit may arrive. "Wholly within", so it is the whole base that must fit,
## not the centre dot (see _wholly_within_setup_distance_of_edge).
const RESERVES_SETUP_DISTANCE_INCHES: float = 6.0

# How far past the stand-off boundary a clamped ghost is parked. The boundary IS
# the rejection threshold, so landing mathematically on it risks measuring a
# hair under and being rejected; this matches the game's own float-comparison
# tolerance (Measurement.DISTANCE_TOLERANCE_INCHES — not referenced directly
# because an autoload lookup is not a constant expression), a safe and, at 2 px,
# invisible amount of daylight.
const EXCLUSION_CLAMP_MARGIN_INCHES: float = 0.05

# When the straight push out of the exclusion zone lands somewhere unusable —
# almost always a model already placed on the same stretch of the 9" ring, which
# is exactly what happens while walking a whole unit along the boundary — search
# outwards from it and take the nearest spot that IS usable.
#
# The search is sized in BASE WIDTHS, not in fractions of the push: a shallow
# aim only needs nudging a few pixels to clear the ring, but getting around the
# model already standing there always costs a base width whether the push was
# 5 px or 500. Steps go sideways along the boundary (both ways, so a queue can
# build in either direction) and straight back from it.
const EXCLUSION_CLAMP_SIDE_STEPS: Array = [1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0]
const EXCLUSION_CLAMP_BACK_STEPS: Array = [1.0, 2.0]
# One step, as a fraction of the placed model's own base extent. Just over one
# base guarantees a step actually clears a same-size neighbour.
const EXCLUSION_CLAMP_STEP_BASES: float = 1.05
# Ceiling on validator calls per clamp so a crowded board cannot make the
# per-frame ghost update expensive.
const EXCLUSION_CLAMP_MAX_CANDIDATE_TESTS: int = 12

# Scout reserves mode (11e 24.31: a Scout unit in Strategic Reserves may be set
# up wholly within its own deployment zone). Reuses the normal "wholly within
# DZ" placement validation but, like reinforcement mode, emits unit_confirmed on
# confirm so Main can dispatch SCOUT_RESERVES_DEPLOY instead of a normal deploy.
var is_scout_reserves_mode: bool = false

# MA-15: Model type picker state
var has_model_type_picker: bool = false
var selected_model_type: String = ""
var model_type_picker_panel: Node = null
var model_type_picker_canvas: CanvasLayer = null

# Infiltrator exclusion boundary visual
var infiltrator_exclusion_visual: Node2D = null

# MA-19: Combined deployment model profiles for picker
var _combined_profiles: Dictionary = {}

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)

func _exit_tree() -> void:
	# MEM-13: the model-type picker CanvasLayer is parented to /root (it must
	# outdraw the HUD), so it survives this controller unless freed here — a
	# picker left open when the deployment phase ended leaked past the game
	# scene, even into the main menu.
	_hide_model_type_picker()

func set_layers(tokens: Node2D, ghosts: Node2D) -> void:
	token_layer = tokens
	ghost_layer = ghosts

func _unhandled_input(event: InputEvent) -> void:
	if not is_placing():
		return

	# In multiplayer, block all input if it's not your turn
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		return

	# Check if we have ghosts to work with (unless repositioning).
	# A ghost is NOT required for the session to be interactive: once every model
	# of the unit is down there is no ghost left, but Shift+click repositioning,
	# Ctrl+Z undo and the rotate keys must all still work while the unit sits
	# waiting on Confirm — so only bail when nothing has been placed either.
	if not repositioning_model and not ghost_sprite and formation_preview_ghosts.is_empty() and get_placed_count() == 0:
		return

	# Handle clicks for formation placement
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var mouse_pos = _get_world_mouse_position()

				# Check for shift+click on deployed model for repositioning
				if Input.is_key_pressed(KEY_SHIFT):
					var deployed_model = _get_deployed_model_at_position(mouse_pos)
					if not deployed_model.is_empty():
						_start_model_repositioning(deployed_model)
						return

				# Handle repositioning end
				if repositioning_model:
					_end_model_repositioning(mouse_pos)
					return

				# Normal placement logic
				if formation_mode != "SINGLE":
					try_place_formation_at(mouse_pos)
				else:
					try_place_at(mouse_pos)
				return
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Cancel repositioning on right-click
			if repositioning_model:
				_cancel_model_repositioning()
				return

	elif event is InputEventMouseMotion:
		if repositioning_model:
			_update_model_repositioning(event.position)
			return

	# Handle Ctrl+Z for per-model undo during deployment
	if event is InputEventKey and event.pressed:
		if KeybindingManager.matches_action(event, "undo_deployment"):
			if undo_last_model():
				get_viewport().set_input_as_handled()
			return

	# Handle rotation controls during deployment
	if event is InputEventKey and event.pressed:
		if KeybindingManager.matches_action(event, "rotate_left"):
			_rotate_active_ghost(-PI/12)  # 15 degrees counter-clockwise
		elif KeybindingManager.matches_action(event, "rotate_right"):
			_rotate_active_ghost(PI/12)  # 15 degrees clockwise
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			# Rotate with mouse wheel
			_rotate_active_ghost(PI/12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_rotate_active_ghost(-PI/12)

func _rotate_active_ghost(angle: float) -> void:
	"""Apply one rotation step to whatever the player is actually aiming right
	now. Before this, every rotate input (Q/E, the mouse wheel and the pad's
	R3+LB/RB) went unconditionally to ghost_sprite — so while a placed model was
	lifted for repositioning the player watched the NEXT model's ghost spin
	instead of the model in hand, and the lifted model dropped at its old facing
	(reported 2026-07-30). A lift is always a single model, whatever the
	formation mode is, so it takes priority over the formation branch."""
	if repositioning_model:
		if reposition_ghost and reposition_ghost.has_method("rotate_by"):
			reposition_ghost.rotate_by(angle)
		return
	if formation_mode == "SINGLE":
		# Rotate individual model ghost
		if ghost_sprite and ghost_sprite.has_method("rotate_by"):
			ghost_sprite.rotate_by(angle)
	else:
		# Rotate formation
		formation_rotation += angle

func begin_deploy(_unit_id: String) -> void:
	print("[DeploymentController] begin_deploy() called for unit: ", _unit_id)

	# In multiplayer, block deployment if it's not your turn
	var network_manager = get_node_or_null("/root/NetworkManager")
	print("[DeploymentController] NetworkManager found: ", network_manager != null)
	if network_manager:
		print("[DeploymentController] is_networked: ", network_manager.is_networked())
		print("[DeploymentController] is_local_player_turn: ", network_manager.is_local_player_turn())
		print("[DeploymentController] local_player: ", network_manager.get_local_player())
		print("[DeploymentController] active_player: ", GameState.get_active_player())

	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		print("[DeploymentController] Blocking deployment - not your turn")
		return

	# T-026: offer Combat Squads / Patrol Squad split before deployment for an
	# eligible undeployed 10-model unit. Skips if user previously declined this
	# session for this unit, or if the unit was already split.
	if _maybe_offer_combat_squad_split(_unit_id):
		# A dialog is open; defer the actual deploy to the dialog's callbacks.
		return

	unit_id = _unit_id
	model_idx = 0
	temp_positions.clear()
	temp_rotations.clear()
	_last_deploy_rotation = null  # Reset rotation carry-over for the new unit
	placement_order.clear()  # MA-16: Reset placement order tracking
	combined_models.clear()
	is_combined_deployment = false
	_combined_profiles.clear()
	var unit_data = GameState.get_unit(unit_id)

	# Check if this unit has pre-declared character attachments (from Formations phase)
	var attached_char_ids = unit_data.get("attachment_data", {}).get("attached_characters", [])
	print("[DeploymentController] formations_declared=%s, attached_characters=%s, attached_to=%s" % [
		str(GameState.formations_declared()),
		str(attached_char_ids),
		str(unit_data.get("attached_to", null))
	])

	# Defensive state repair: if formations were declared but attachment_data wasn't applied,
	# check meta.formations for unlinked attachments and repair the per-unit state
	if GameState.formations_declared() and attached_char_ids.size() == 0:
		var formations_meta = GameState.state.get("meta", {}).get("formations", {})
		var owner = unit_data.get("owner", unit_data.get("meta", {}).get("player", 0))
		var player_formations = formations_meta.get(str(owner), {})
		var leader_attachments = player_formations.get("leader_attachments", {})
		# Check if any character is declared attached to this unit
		var needs_repair = false
		for char_id in leader_attachments:
			if leader_attachments[char_id] == _unit_id:
				needs_repair = true
				break
		if needs_repair:
			print("[DeploymentController] STATE REPAIR: dispatching REPAIR_FORMATION_ATTACHMENT for bodyguard %s" % _unit_id)
			# ISS-001: route the repair through the action pipeline (DeploymentPhase
			# returns diffs) instead of writing GameState from the UI layer, so the
			# repair is recorded for replay/undo and synced in multiplayer. On a
			# multiplayer client this may resolve asynchronously via host broadcast;
			# this selection then proceeds un-combined, same as the pre-repair state.
			var repair_result = NetworkIntegration.route_action({
				"type": "REPAIR_FORMATION_ATTACHMENT",
				"unit_id": _unit_id
			})
			if repair_result is Dictionary and not repair_result.get("success", false) and not repair_result.get("pending", false):
				push_error("[DeploymentController] STATE REPAIR failed for %s: %s" % [_unit_id, str(repair_result)])
			unit_data = GameState.get_unit(unit_id)
			attached_char_ids = unit_data.get("attachment_data", {}).get("attached_characters", [])
			for char_id in attached_char_ids:
				print("[DeploymentController] STATE REPAIR: Set %s.attached_to = %s" % [char_id, _unit_id])

	setup_placement_models(_unit_id)

	formation_rotation = 0.0  # Reset formation rotation for new unit
	# Reset to SINGLE so controller state matches the UI (the formation buttons
	# in Main are recreated per-unit with "Single" pre-pressed; without this
	# reset the controller would still think TIGHT/SPREAD is active and
	# clicking the already-pressed "Single" button wouldn't fire any signal).
	formation_mode = "SINGLE"

	# MA-15/MA-19: Check if model type picker should be shown
	setup_model_type_picker()

	# Check if this unit has Infiltrators ability
	is_infiltrators_mode = GameState.unit_has_infiltrators(unit_id)
	if is_infiltrators_mode:
		print("[DeploymentController] Unit %s has Infiltrators - deploying in Infiltrators mode" % _unit_id)
		_show_infiltrator_exclusion()

	# Update through PhaseManager instead of BoardState
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance:
			# Set unit status to deploying in GameState
			phase_manager.apply_state_changes([{
				"op": "set",
				"path": "units.%s.status" % unit_id,
				"value": GameStateData.UnitStatus.DEPLOYING
			}])

	# MA-15: If model type picker is active, try auto-select or wait for user pick
	if has_model_type_picker:
		if not _try_auto_select_model_type():
			# Multiple types remain — wait for user to pick, no ghost yet
			model_idx = temp_positions.size()  # Sentinel: prevents ghost/placement
			print("[DeploymentController] MA-15: Waiting for model type selection")
			return

	# Create appropriate ghosts based on formation mode
	if formation_mode == "SINGLE":
		_create_ghost()
	else:
		var remaining = _get_unplaced_model_indices()
		if not remaining.is_empty():
			_create_formation_ghosts(min(formation_size, remaining.size()))

# Size the placement buffers for `p_unit_id` and, when it leads attached
# CHARACTERs, fold their models into the SAME session so the player places the
# whole Attached unit (bodyguard + leader) — 11e 24.10: an Attached unit is a
# single unit and is set up as one. Shared by deployment (begin_deploy) and by
# the movement-phase set-ups in Main (reserves arrival / Rapid Ingress), which
# previously sized the buffers off the bodyguard's models alone — that is why a
# Deep Striking squad with a leader only ever offered the squad's models and the
# leader got teleported next to them by the phase handler.
#
# `only_reserves_characters` restricts the fold-in to characters still
# IN_RESERVES: a reinforcement arrival brings in only the models that are
# actually arriving, whereas at deployment every attached character is off the
# table anyway. Returns true when a combined list was built.
func setup_placement_models(p_unit_id: String, only_reserves_characters: bool = false) -> bool:
	temp_positions.clear()
	temp_rotations.clear()
	combined_models.clear()
	is_combined_deployment = false
	_combined_profiles.clear()

	var unit_data = GameState.get_unit(p_unit_id)
	if unit_data.is_empty():
		return false

	var attached_char_ids: Array = []
	for char_id in unit_data.get("attachment_data", {}).get("attached_characters", []):
		var char_data = GameState.get_unit(char_id)
		if char_data.is_empty():
			push_error("[DeploymentController] Attached character not found: %s" % char_id)
			continue
		if only_reserves_characters and int(char_data.get("status", 0)) != GameStateData.UnitStatus.IN_RESERVES:
			# Already on the battlefield — it is not arriving with this set-up.
			print("[DeploymentController] Skipping attached character %s (not in reserves)" % char_id)
			continue
		attached_char_ids.append(char_id)

	# Reserves arrivals do not depend on formations_declared(): the attachment is
	# already live on the unit by then (it is what put the character in reserves).
	if attached_char_ids.size() > 0 and (only_reserves_characters or GameState.formations_declared()):
		is_combined_deployment = true
		print("[DeploymentController] Combined placement: bodyguard %s + %d attached character(s)" % [p_unit_id, attached_char_ids.size()])

		# MA-19: Build combined model profiles for picker and add model_type to entries
		var bg_profiles = unit_data.get("meta", {}).get("model_profiles", {})
		var has_bg_profiles = bg_profiles.size() > 0
		var bg_type_key = "bg_" + p_unit_id

		# Copy bodyguard profiles or create synthetic one
		if has_bg_profiles:
			for key in bg_profiles:
				_combined_profiles[key] = bg_profiles[key]
		else:
			var bg_name = unit_data.get("meta", {}).get("name", "Bodyguard")
			_combined_profiles[bg_type_key] = {"label": bg_name}

		# Add bodyguard models first (with model_type)
		for i in range(unit_data["models"].size()):
			var model = unit_data["models"][i]
			var mt = model.get("model_type", "")
			var model_data_entry = model
			if mt == "":
				# No model_type - use synthetic bodyguard type
				mt = bg_type_key
				model_data_entry = model.duplicate()
				model_data_entry["model_type"] = mt
			combined_models.append({
				"unit_id": p_unit_id,
				"model_idx": i,
				"model_data": model_data_entry,
				"model_type": mt
			})

		# Then add character models (with synthetic model_type)
		for char_id in attached_char_ids:
			var char_data = GameState.get_unit(char_id)
			var char_name = char_data.get("meta", {}).get("name", "Character")
			var char_type_key = "char_" + char_id
			_combined_profiles[char_type_key] = {"label": char_name, "is_character": true}
			for i in range(char_data["models"].size()):
				var char_model = char_data["models"][i].duplicate()
				char_model["model_type"] = char_type_key
				combined_models.append({
					"unit_id": char_id,
					"model_idx": i,
					"model_data": char_model,
					"model_type": char_type_key
				})
			print("[DeploymentController] Added %d models from character %s (%s)" % [char_data["models"].size(), char_id, char_name])

		# Size temp arrays to fit all combined models
		temp_positions.resize(combined_models.size())
		temp_rotations.resize(combined_models.size())
		temp_rotations.fill(0.0)
		print("[DeploymentController] Combined placement total models: %d" % combined_models.size())
		return true

	temp_positions.resize(unit_data["models"].size())
	temp_rotations.resize(unit_data["models"].size())
	temp_rotations.fill(0.0)
	return false

# MA-15/MA-19: (re)build the model-type picker for the current placement session.
# Split out of begin_deploy so the movement-phase set-ups get the same picker —
# a combined arrival needs it to let the player choose "place the leader next".
func setup_model_type_picker() -> void:
	has_model_type_picker = false
	selected_model_type = ""
	_hide_model_type_picker()

	if is_combined_deployment:
		# MA-19: Show picker for combined placement (character + bodyguard types)
		if _combined_profiles.size() > 1:
			var effective_models = _get_effective_models()
			var distinct_types = _get_distinct_unplaced_types(effective_models, [])
			if distinct_types.size() > 1:
				has_model_type_picker = true
				_show_model_type_picker(_combined_profiles, effective_models)
				print("[DeploymentController] MA-19: Combined placement picker shown with %d types" % distinct_types.size())
		return

	# MA-15: Non-combined placement with model_profiles
	var unit_data = GameState.get_unit(unit_id)
	if unit_data.is_empty():
		return
	var model_profiles = unit_data.get("meta", {}).get("model_profiles", {})
	if model_profiles.size() > 1:
		var distinct_types = _get_distinct_unplaced_types(unit_data["models"], [])
		if distinct_types.size() > 1:
			has_model_type_picker = true
			_show_model_type_picker(model_profiles, unit_data["models"])
			print("[DeploymentController] MA-15: Model type picker shown with %d types" % distinct_types.size())

var _split_declined_units: Dictionary = {}
var _pending_split_unit_id: String = ""


func _maybe_offer_combat_squad_split(p_unit_id: String) -> bool:
	# Returns true if we showed a confirm dialog (caller should defer the deploy).
	if _split_declined_units.has(p_unit_id):
		return false
	var unit = GameState.get_unit(p_unit_id)
	if unit.is_empty():
		return false
	if unit.get("split_from_combat_squads", false):
		return false  # already a half — don't re-offer
	if int(unit.get("status", 0)) != GameStateData.UnitStatus.UNDEPLOYED:
		return false
	var alive = 0
	for m in unit.get("models", []):
		if m.get("alive", true):
			alive += 1
	if alive != 10:
		return false
	var splittable = false
	for ab in unit.get("meta", {}).get("abilities", []):
		var ab_name = ab if ab is String else (ab.get("name", "") if ab is Dictionary else "")
		if ab_name in ["Combat Squads", "Patrol Squad"]:
			splittable = true
			break
	if not splittable:
		return false

	var dialog = ConfirmationDialog.new()
	dialog.title = "Split Unit?"
	var unit_name = unit.get("meta", {}).get("name", p_unit_id)
	dialog.dialog_text = "%s can be split into two 5-model squads (Combat Squads / Patrol Squad).\nSplit before deployment?" % unit_name
	dialog.get_ok_button().text = "Split"
	dialog.get_cancel_button().text = "Deploy as 10"
	# Wire up handlers BEFORE showing
	_pending_split_unit_id = p_unit_id
	dialog.confirmed.connect(_on_combat_squad_split_confirmed.bind(p_unit_id, dialog))
	dialog.canceled.connect(_on_combat_squad_split_declined.bind(p_unit_id, dialog))
	# Find a suitable parent so the dialog renders on top
	var parent = get_tree().current_scene if get_tree() else null
	if parent == null:
		parent = self
	parent.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	return true


func _on_combat_squad_split_confirmed(p_unit_id: String, dialog: ConfirmationDialog) -> void:
	if dialog and is_instance_valid(dialog):
		dialog.queue_free()
	if _pending_split_unit_id != p_unit_id:
		return
	_pending_split_unit_id = ""
	var sibling_id = GameState.split_unit_at_deployment(p_unit_id)
	if sibling_id == "":
		print("[DeploymentController] T-026 split failed for %s" % p_unit_id)
		return
	emit_signal("unit_split_completed", p_unit_id, sibling_id)
	# Don't auto-deploy either half — return control to the host UI so the user
	# can pick which half to deploy first.


func _on_combat_squad_split_declined(p_unit_id: String, dialog: ConfirmationDialog) -> void:
	if dialog and is_instance_valid(dialog):
		dialog.queue_free()
	_split_declined_units[p_unit_id] = true
	_pending_split_unit_id = ""
	# Re-enter begin_deploy now that the user has declined the split — unless
	# the player meanwhile started placing a different unit (DEPLOY-CYCLE keeps
	# the unit list selectable while this dialog is open).
	if unit_id == "":
		begin_deploy(p_unit_id)


func is_placing() -> bool:
	return unit_id != ""

func get_current_unit() -> String:
	return unit_id

func get_placed_count() -> int:
	var count = 0
	for pos in temp_positions:
		if pos != null:
			count += 1
	return count

func get_total_model_count() -> int:
	if is_combined_deployment:
		return combined_models.size()
	return temp_positions.size()

func try_place_at(world_pos: Vector2) -> void:
	if not is_placing():
		return

	if model_idx >= temp_positions.size():
		return

	# Get model data - from combined_models for combined deployment, otherwise from unit
	var model_data: Dictionary
	var spawn_unit_id: String = unit_id
	var spawn_model_idx: int = model_idx
	if is_combined_deployment and model_idx < combined_models.size():
		var cm = combined_models[model_idx]
		model_data = cm["model_data"]
		spawn_unit_id = cm["unit_id"]
		spawn_model_idx = cm["model_idx"]
	else:
		var unit_data = GameState.get_unit(unit_id)
		model_data = unit_data["models"][model_idx]

	var active_player = GameState.get_active_player()
	var zone = BoardState.get_deployment_zone_for_player(active_player)

	# Get current rotation from ghost
	var rotation = 0.0
	if ghost_sprite and ghost_sprite.has_method("get_base_rotation"):
		rotation = ghost_sprite.get_base_rotation()

	# Deep Strike / Infiltrators: drop where the ghost was being previewed, which
	# for a click aimed inside an exclusion bubble is the nearest legal spot just
	# outside it rather than the illegal point itself. Same call the per-frame
	# preview makes (_process), so preview and drop cannot disagree; a no-op for
	# every position that is placeable as aimed.
	world_pos = _clamped_placement_position(world_pos, model_data, rotation)

	# Issue #87: no part of any model's base may extend off the
	# battlefield. Applies to all placement modes (normal / reinforcement /
	# infiltrators) — normal deployment zones are already on-board so this
	# is a safety net, but reinforcement and infiltrators modes can place
	# anywhere the rule allows, including the board edge.
	var edge_check_model: Dictionary = model_data.duplicate()
	edge_check_model["rotation"] = rotation
	if Measurement.model_outside_board(world_pos, edge_check_model):
		_show_toast("Models cannot be placed off the board")
		return

	# Check placement validity
	if is_reinforcement_mode:
		# Reinforcement mode: validate >9" from enemies, on the board
		if not _validate_reinforcement_position(world_pos, model_data, rotation):
			return
	elif is_infiltrators_mode:
		# Infiltrators mode: validate >9" from enemy zone and enemy models, on the board
		if not _validate_infiltrators_position(world_pos, model_data, rotation):
			return
	else:
		# Normal deployment: check if wholly within deployment zone based on shape
		var base_type = model_data.get("base_type", "circular")
		var is_in_zone = false

		if base_type == "circular":
			var radius_px = Measurement.base_radius_px(model_data["base_mm"])
			is_in_zone = _circle_wholly_in_polygon(world_pos, radius_px, zone)
		else:
			# For non-circular bases, use shape-aware validation
			is_in_zone = _shape_wholly_in_polygon(world_pos, model_data, rotation, zone)

		if not is_in_zone:
			_show_toast("Must be wholly within your deployment zone")
			return

	# Check for overlap with existing models
	if _overlaps_with_existing_models_shape(world_pos, model_data, rotation):
		_show_toast("Cannot overlap with existing models")
		return

	# Check for overlap with walls, honoring the deploying unit's traversal keywords
	# (e.g. INFANTRY can pass through ruin walls in 10e).
	var test_model = model_data.duplicate()
	test_model["position"] = world_pos
	test_model["rotation"] = rotation
	if Measurement.model_overlaps_any_wall(test_model, _get_deploying_unit_keywords(model_idx)):
		_show_toast("Cannot overlap with walls this unit can't cross")
		return

	# Store position and rotation (rotation already captured above)
	temp_positions[model_idx] = world_pos
	temp_rotations[model_idx] = rotation
	# Carry this rotation over to the next model so, e.g., rotating the first
	# model 90° makes every following model start off at that same 90°.
	_last_deploy_rotation = rotation
	placement_order.append(model_idx)  # MA-16: Track placement order for non-sequential undo
	_spawn_preview_token(spawn_unit_id, spawn_model_idx, world_pos, rotation)

	# MA-15: Advance to next model — type-aware if picker is active
	if has_model_type_picker:
		_advance_model_type_placement()
	else:
		model_idx += 1

	_check_coherency_warning()
	emit_signal("models_placed_changed")

	if model_idx < temp_positions.size():
		_update_ghost_for_next_model()
	else:
		# Every model is down — there is no next model to preview, so drop the
		# ghost (the formation path at try_place_formation_at already does this).
		# _process stops updating ghost_sprite once model_idx runs off the end, so
		# leaving it alive froze a full-strength ghost on top of the last model
		# placed. It then sat there for the rest of the session, and a following
		# Shift+click / pad-L3 reposition made it obvious: the lifted model
		# appeared to still be at its old spot, and it was the thing that rotated.
		_remove_ghost()

func try_place_formation_at(world_pos: Vector2) -> void:
	"""Place multiple models in formation at once"""
	if formation_mode == "SINGLE":
		try_place_at(world_pos)
		return

	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	var models_to_place = min(formation_size, remaining_indices.size())

	if models_to_place == 0:
		return

	# MA-18: Build model data array for all models being placed (supports mixed base sizes)
	var formation_model_data: Array = []
	for i in range(models_to_place):
		var idx = remaining_indices[i]
		if is_combined_deployment and idx < combined_models.size():
			formation_model_data.append(combined_models[idx]["model_data"])
		else:
			formation_model_data.append(unit_data["models"][idx])
	var base_mm = formation_model_data[0]["base_mm"]
	var positions = []
	var formation_rotations = []  # Per-model rotations (for oval/rectangular in tight formation)

	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(world_pos, models_to_place, base_mm, formation_rotation, formation_model_data)
			formation_rotations.resize(positions.size())
			formation_rotations.fill(0.0)
		"TIGHT":
			var result = calculate_tight_formation(world_pos, models_to_place, base_mm, formation_rotation, formation_model_data)
			positions = result["positions"]
			formation_rotations = result["rotations"]

	# Validate all positions
	var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())

	# Same exclusion-zone clamp the formation preview applied, so a block aimed
	# slightly inside the 9" bubble drops where its ghosts were shown — pressed
	# up against the boundary — instead of being rejected. A no-op whenever the
	# block is already clear of it (_clamped_formation_anchor returns the anchor
	# untouched unless every model ends up legal).
	var clamped_anchor = _clamped_formation_anchor(world_pos, positions, formation_model_data, formation_rotations, zone)
	if clamped_anchor != world_pos:
		var anchor_shift = clamped_anchor - world_pos
		for i in range(positions.size()):
			positions[i] = positions[i] + anchor_shift

	var all_valid = true
	var error_msg = ""

	for i in range(positions.size()):
		var pos = positions[i]
		var idx = remaining_indices[i]
		var model: Dictionary
		if is_combined_deployment and idx < combined_models.size():
			model = combined_models[idx]["model_data"]
		else:
			model = unit_data["models"][idx]

		var validate_rot = formation_rotations[i] if i < formation_rotations.size() else 0.0
		# Issue #87 parity with the single-model try_place_at(): no part of any
		# base may extend off the battlefield. Applies to all modes — normal
		# deployment zones are already inset so this is a safety net there, but
		# for reinforcement (Deep Strike / Strategic Reserves, which arrive within
		# 6" of a board edge) and infiltrators the zone check is bypassed, so this
		# is the ONLY edge guard. The per-mode validators below only test the
		# model centre, not the full base footprint.
		var edge_model: Dictionary = model.duplicate()
		edge_model["rotation"] = validate_rot
		if Measurement.model_outside_board(pos, edge_model):
			all_valid = false
			error_msg = "Models cannot be placed off the board"
			break
		if not _validate_formation_position(pos, model, zone, validate_rot):
			all_valid = false
			# _validate_formation_position already surfaced the specific reason
			# (e.g. ">9\" from enemy models") via its own toast; the fallback text
			# must not claim "deployment zone" in reinforcement/infiltrator modes
			# where placement is not zone-constrained.
			if is_reinforcement_mode or is_infiltrators_mode:
				error_msg = "Formation placement is not legal here"
			else:
				error_msg = "Formation would place models outside deployment zone or overlapping"
			break

	if not all_valid:
		_show_toast(error_msg)
		return

	# Place all models
	for i in range(positions.size()):
		var idx = remaining_indices[i]
		var model_rot = formation_rotations[i] if i < formation_rotations.size() else 0.0
		temp_positions[idx] = positions[i]
		temp_rotations[idx] = model_rot
		placement_order.append(idx)  # MA-16: Track placement order for non-sequential undo
		var spawn_uid = unit_id
		var spawn_midx = idx
		if is_combined_deployment and idx < combined_models.size():
			spawn_uid = combined_models[idx]["unit_id"]
			spawn_midx = combined_models[idx]["model_idx"]
		_spawn_preview_token(spawn_uid, spawn_midx, positions[i], model_rot)

	# Update model_idx to next unplaced model
	if models_to_place < remaining_indices.size():
		model_idx = remaining_indices[models_to_place]
	else:
		model_idx = temp_positions.size()

	_check_coherency_warning()
	emit_signal("models_placed_changed")

	# Update or clear ghosts
	if model_idx < temp_positions.size():
		if formation_mode == "SINGLE":
			_update_ghost_for_next_model()
		else:
			_create_formation_ghosts(formation_size)
	else:
		_clear_formation_ghosts()
		_remove_ghost()

func undo_last_model() -> bool:
	"""Undo only the most recently placed model. Returns true if a model was undone, false if nothing to undo."""
	if not is_placing():
		return false

	# MA-16: Use placement_order to find the most recently placed model
	# This supports non-sequential placement (e.g., placing spanner at idx 10 before grots at idx 0-7)
	var last_placed_idx = -1
	if placement_order.size() > 0:
		last_placed_idx = placement_order.back()
	else:
		# Fallback: scan all positions for any placed model
		for i in range(temp_positions.size() - 1, -1, -1):
			if temp_positions[i] != null:
				last_placed_idx = i
				break

	if last_placed_idx == -1:
		print("[DeploymentController] undo_last_model: No placed models to undo")
		return false

	print("[DeploymentController] undo_last_model: Undoing model at index %d" % last_placed_idx)

	# MA-16: Remove from placement order tracking
	if placement_order.size() > 0 and placement_order.back() == last_placed_idx:
		placement_order.pop_back()
	else:
		# Fallback: remove the index from wherever it appears
		var order_idx = placement_order.find(last_placed_idx)
		if order_idx >= 0:
			placement_order.remove_at(order_idx)

	# Clear the position and rotation for this model
	temp_positions[last_placed_idx] = null
	temp_rotations[last_placed_idx] = 0.0

	# Remove the corresponding preview token
	var token_unit_id = unit_id
	var token_model_idx = last_placed_idx
	if is_combined_deployment and last_placed_idx < combined_models.size():
		token_unit_id = combined_models[last_placed_idx]["unit_id"]
		token_model_idx = combined_models[last_placed_idx]["model_idx"]
	var token_name = "Token_%s_%d" % [token_unit_id, token_model_idx]
	for i in range(placed_tokens.size() - 1, -1, -1):
		var token = placed_tokens[i]
		if is_instance_valid(token) and token.name == token_name:
			token.queue_free()
			placed_tokens.remove_at(i)
			break

	# DEPLOY-VIS-5: Remove the corresponding coherency circle
	if last_placed_idx < coherency_circles.size():
		var circle = coherency_circles[last_placed_idx]
		if is_instance_valid(circle):
			circle.queue_free()
		coherency_circles.remove_at(last_placed_idx)

	# Set model_idx back to this model so the ghost appears for it
	model_idx = last_placed_idx

	# MA-15/MA-19: Update model type picker after undo
	if has_model_type_picker:
		_update_model_type_picker()
		# Set selected type to the undone model's type
		var effective_models = _get_effective_models()
		var undone_model = effective_models[last_placed_idx] if last_placed_idx < effective_models.size() else {}
		var undone_type = undone_model.get("model_type", "")
		if undone_type != "":
			selected_model_type = undone_type
			if model_type_picker_panel:
				model_type_picker_panel.highlight_selected(undone_type)

	# Recreate ghost for the model we just undid
	if formation_mode == "SINGLE":
		_remove_ghost()
		_create_ghost()
	else:
		_clear_formation_ghosts()
		var remaining = _get_unplaced_model_indices()
		if not remaining.is_empty():
			_create_formation_ghosts(min(formation_size, remaining.size()))

	_check_coherency_warning()
	emit_signal("models_placed_changed")
	return true

func reset_unit() -> void:
	"""Reset the entire unit — clears all placed models and cancels deployment."""
	_clear_previews()
	temp_positions.fill(null)
	temp_rotations.fill(0.0)  # Reset rotations to default
	_last_deploy_rotation = null  # Reset rotation carry-over
	placement_order.clear()  # MA-16: Reset placement order tracking
	model_idx = 0

	# Update through PhaseManager instead of BoardState
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance:
			# If undoing reinforcement or scout-reserves placement, restore to
			# IN_RESERVES instead of UNDEPLOYED.
			var restore_status = GameStateData.UnitStatus.IN_RESERVES if (is_reinforcement_mode or is_scout_reserves_mode) else GameStateData.UnitStatus.UNDEPLOYED
			phase_manager.apply_state_changes([{
				"op": "set",
				"path": "units.%s.status" % unit_id,
				"value": restore_status
			}])

	is_reinforcement_mode = false
	reinforcement_placement_type = ""  # P2-80: Clear placement type override
	is_scout_reserves_mode = false
	is_infiltrators_mode = false
	_hide_infiltrator_exclusion()
	is_combined_deployment = false
	combined_models.clear()
	_combined_profiles.clear()  # MA-19
	# MA-15: Clean up model type picker
	has_model_type_picker = false
	selected_model_type = ""
	_hide_model_type_picker()
	unit_id = ""
	formation_mode = "SINGLE"  # Match UI default so next unit starts cleanly
	_clear_formation_ghosts()  # Clear any formation ghosts
	_remove_ghost()  # Also removes coherency distance label
	emit_signal("coherency_warning_changed", false, "")

func undo() -> void:
	"""Legacy undo — calls reset_unit() for backward compatibility."""
	reset_unit()

func confirm() -> void:
	# Enforce unit coherency before allowing deployment
	if not _is_unit_coherent():
		_show_toast(_coherency_failure_message(), Color.RED)
		return

	# In reinforcement OR scout-reserves mode, emit signal BEFORE clearing state
	# so Main can collect positions and dispatch the appropriate action.
	if is_reinforcement_mode or is_scout_reserves_mode:
		print("[DeploymentController] Reserve confirm — emitting unit_confirmed (positions still available)")
		emit_signal("unit_confirmed")
		# Clean up after Main has collected positions (signal is synchronous)
		_finalize_tokens()
		_clear_previews()
		_remove_ghost()
		unit_id = ""
		model_idx = -1
		temp_positions.clear()
		temp_rotations.clear()
		placement_order.clear()  # MA-16: Clear placement order tracking
		is_reinforcement_mode = false
		reinforcement_placement_type = ""
		is_scout_reserves_mode = false
		# A reserves arrival can be a COMBINED set-up (bodyguard + attached
		# characters); clear it here too so the next session never reads a stale
		# combined list through get_total_model_count() / _get_effective_models().
		is_combined_deployment = false
		combined_models.clear()
		_combined_profiles.clear()
		# MA-15: Clean up model type picker
		has_model_type_picker = false
		selected_model_type = ""
		_hide_model_type_picker()
		emit_signal("coherency_warning_changed", false, "")
		return

	# If formations were declared pre-deployment, skip the interactive dialogs
	# The leader attachments and transport embarkations are already applied to GameState
	if GameState.formations_declared():
		DebugLogger.info("Formations pre-declared, skipping deploy-time dialogs", {
			"unit_id": unit_id
		})
		_complete_deployment()
		return

	# Check if this unit can have characters attached - show attach dialog FIRST
	if _has_attachable_characters(unit_id) and not is_awaiting_attach_dialog and not is_awaiting_embark_dialog:
		DebugLogger.info("Unit being deployed has attachable characters - showing attach dialog", {
			"unit_id": unit_id
		})
		is_awaiting_attach_dialog = true
		_show_character_attach_dialog()
		return  # Don't proceed with deployment yet - wait for dialog

	# Check if this is a transport - if so, show embark dialog FIRST
	if _is_transport(unit_id) and not is_awaiting_embark_dialog:
		DebugLogger.info("Transport being deployed - showing embark dialog before confirmation", {
			"unit_id": unit_id
		})
		is_awaiting_embark_dialog = true
		_show_transport_embark_dialog()
		return  # Don't proceed with deployment yet - wait for dialog

	# Proceed with actual deployment (called either directly for non-transports, or after embark dialog closes)
	_complete_deployment()

func _is_transport(unit_id: String) -> bool:
	var unit = GameState.get_unit(unit_id)
	return unit.has("transport_data") and unit.transport_data.get("capacity", 0) > 0

func _has_attachable_characters(p_unit_id: String) -> bool:
	var unit = GameState.get_unit(p_unit_id)
	if unit.is_empty():
		return false
	# Don't show attach dialog for CHARACTER units themselves
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "CHARACTER" in keywords:
		return false
	var player = unit.get("owner", 0)
	var attachable = CharacterAttachmentManager.get_attachable_characters(p_unit_id, player)
	return attachable.size() > 0

func _show_character_attach_dialog() -> void:
	DebugLogger.info("Creating character attach dialog", {"unit_id": unit_id})

	var dialog_script = load("res://scripts/CharacterAttachDialog.gd")
	var dialog = dialog_script.new()
	dialog.characters_selected.connect(_on_attach_characters_selected)

	# Add to scene tree FIRST so _ready() runs before setup()
	get_tree().root.add_child(dialog)
	dialog.setup(unit_id)
	DialogUtils.popup_at_bottom(dialog)

func _on_attach_characters_selected(character_ids: Array) -> void:
	DebugLogger.info("Character attach dialog closed", {
		"bodyguard_id": unit_id,
		"selected_characters": character_ids,
		"count": character_ids.size()
	})

	# Store characters to attach AFTER deployment completes
	pending_attach_characters = character_ids
	is_awaiting_attach_dialog = false

	# Now proceed — check if transport dialog is also needed
	confirm()

func _show_transport_embark_dialog() -> void:
	DebugLogger.info("Creating transport embark dialog", {"unit_id": unit_id})

	var dialog_script = load("res://scripts/TransportEmbarkDialog.gd")
	var dialog = dialog_script.new()
	dialog.units_selected.connect(_on_embark_units_selected)

	# Add to scene tree FIRST so _ready() runs before setup()
	get_tree().root.add_child(dialog)
	dialog.setup(unit_id)
	DialogUtils.popup_at_bottom(dialog)

func _on_embark_units_selected(unit_ids: Array) -> void:
	DebugLogger.info("Embark dialog closed", {
		"transport_id": unit_id,
		"selected_units": unit_ids,
		"count": unit_ids.size()
	})

	# Store units to embark AFTER deployment completes
	pending_embark_units = unit_ids
	is_awaiting_embark_dialog = false

	# Now proceed with actual deployment
	_complete_deployment()

func _complete_deployment() -> void:
	# In multiplayer, verify it's still our turn before submitting
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_networked() and not network_manager.is_local_player_turn():
		print("[DeploymentController] ERROR: Attempted deployment when not your turn")
		push_error("Cannot deploy - not your turn")
		return

	# For combined deployments, split positions back into per-unit arrays
	var bodyguard_positions = []
	var bodyguard_rotations = []
	var char_positions_map = {}  # char_id -> [{pos, rotation}, ...]

	if is_combined_deployment:
		for i in range(combined_models.size()):
			var cm = combined_models[i]
			if cm["unit_id"] == unit_id:
				bodyguard_positions.append(temp_positions[i])
				bodyguard_rotations.append(temp_rotations[i])
			else:
				if not char_positions_map.has(cm["unit_id"]):
					char_positions_map[cm["unit_id"]] = []
				char_positions_map[cm["unit_id"]].append({
					"pos": temp_positions[i],
					"rotation": temp_rotations[i],
					"model_idx": cm["model_idx"]
				})
	else:
		for pos in temp_positions:
			bodyguard_positions.append(pos)
		bodyguard_rotations = temp_rotations.duplicate()

	# P2-43: Bundle deploy + embark/attach into a single COMPOSITE_DEPLOY action
	# to fix race condition where embark/attach actions arrive after player switch
	# in multiplayer. The composite action is processed atomically so the turn
	# switch only happens after all sub-actions complete.
	var has_embark = pending_embark_units.size() > 0
	var has_combined_chars = is_combined_deployment and char_positions_map.size() > 0
	var has_attach = pending_attach_characters.size() > 0

	if has_embark or has_attach or has_combined_chars:
		print("[DeploymentController] ===== COMPOSITE DEPLOY (P2-43) =====")
		print("[DeploymentController] Building atomic composite action for unit: %s" % unit_id)
		print("[DeploymentController] has_embark=%s, has_combined_chars=%s, has_attach=%s" % [str(has_embark), str(has_combined_chars), str(has_attach)])

		# Build the composite action with all sub-actions bundled
		var composite_action = {
			"type": "COMPOSITE_DEPLOY",
			"unit_id": unit_id,
			"model_positions": bodyguard_positions,
			"model_rotations": bodyguard_rotations,
			"phase": GameStateData.Phase.DEPLOYMENT,
			"timestamp": Time.get_unix_time_from_system()
		}

		# Include embark data if transport units were selected
		if has_embark:
			composite_action["embark_data"] = {
				"transport_id": unit_id,
				"unit_ids": pending_embark_units.duplicate()
			}
			print("[DeploymentController] Included embark_data: transport=%s, units=%s" % [unit_id, str(pending_embark_units)])

		# Include combined character positions if this is a combined deployment
		if has_combined_chars:
			var char_positions_serialized = {}
			for char_id in char_positions_map:
				var entries = []
				for entry in char_positions_map[char_id]:
					entries.append({
						"x": entry["pos"].x,
						"y": entry["pos"].y,
						"rotation": entry["rotation"],
						"model_idx": entry["model_idx"]
					})
				char_positions_serialized[char_id] = entries
			composite_action["combined_char_data"] = char_positions_serialized
			print("[DeploymentController] Included combined_char_data for %d characters" % char_positions_map.size())

		# Include character attachment data if characters were selected
		if has_attach:
			composite_action["attach_data"] = {
				"bodyguard_id": unit_id,
				"character_ids": pending_attach_characters.duplicate()
			}
			print("[DeploymentController] Included attach_data: bodyguard=%s, characters=%s" % [unit_id, str(pending_attach_characters)])

		# Route the single atomic action through NetworkIntegration
		var result = NetworkIntegration.route_action(composite_action)

		if result.success:
			if result.get("pending", false):
				print("[DeploymentController] Composite deployment submitted to network for unit: %s" % unit_id)
			else:
				print("[DeploymentController] Composite deployment successful for unit: %s" % unit_id)
		else:
			print("[DeploymentController] ERROR - Composite deployment failed for unit: ", unit_id)
			print("[DeploymentController] Errors: ", result.get("errors", []))
			push_error("Composite deployment failed: " + str(result.get("error", "Unknown error")))

		pending_embark_units = []
		pending_attach_characters = []
		print("[DeploymentController] ===== COMPOSITE DEPLOY COMPLETE =====")

	else:
		# Simple deployment with no embark/attach — use standard DEPLOY_UNIT action
		# Note: Don't set "player" here - NetworkIntegration will add the correct local player ID
		# This ensures the action uses the actual local player, not just whoever's turn it is
		var deployment_action = {
			"type": "DEPLOY_UNIT",
			"unit_id": unit_id,
			"model_positions": bodyguard_positions,
			"model_rotations": bodyguard_rotations,
			"phase": GameStateData.Phase.DEPLOYMENT,
			"timestamp": Time.get_unix_time_from_system()
		}

		# Route through NetworkIntegration (handles multiplayer and single-player)
		var result = NetworkIntegration.route_action(deployment_action)

		if result.success:
			if result.get("pending", false):
				print("[DeploymentController] Deployment submitted to network for unit: ", unit_id)
			else:
				print("[DeploymentController] Deployment successful for unit: ", unit_id)
				print("[DeploymentController] Action should trigger turn switch")
		else:
			print("[DeploymentController] ERROR - Deployment failed for unit: ", unit_id)
			print("[DeploymentController] Errors: ", result.get("errors", []))
			push_error("Deployment failed: " + str(result.get("error", "Unknown error")))

	_finalize_tokens()
	_clear_previews()
	_remove_ghost()

	unit_id = ""
	model_idx = -1
	temp_positions.clear()
	temp_rotations.clear()  # Added to properly clear rotations
	placement_order.clear()  # MA-16: Clear placement order tracking
	combined_models.clear()
	is_combined_deployment = false
	_combined_profiles.clear()  # MA-19
	is_infiltrators_mode = false
	# MA-15: Clean up model type picker
	has_model_type_picker = false
	selected_model_type = ""
	_hide_model_type_picker()
	_hide_infiltrator_exclusion()

	emit_signal("coherency_warning_changed", false, "")
	emit_signal("unit_confirmed")

	if GameState.all_units_deployed():
		emit_signal("deployment_complete")

func _send_embarkation_action(transport_id: String, unit_ids: Array) -> void:
	"""Send embarkation action through network sync (multiplayer only)"""
	# Note: Don't set "player" here - NetworkIntegration will add the correct local player ID
	var embark_action = {
		"type": "EMBARK_UNITS_DEPLOYMENT",
		"transport_id": transport_id,
		"unit_ids": unit_ids,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"timestamp": Time.get_unix_time_from_system()
	}

	var result = NetworkIntegration.route_action(embark_action)

	if result.success:
		DebugLogger.info("Embarkation action sent successfully", {
			"transport_id": transport_id,
			"unit_count": unit_ids.size()
		})
	else:
		push_error("Embarkation action failed: " + str(result.get("error", "Unknown")))
		DebugLogger.error("Failed to send embarkation action", {
			"transport_id": transport_id,
			"unit_ids": unit_ids,
			"error": result.get("error", "Unknown")
		})

func _process_embarkation(transport_id: String, unit_ids: Array) -> void:
	"""Process embarkation directly (single-player mode)"""
	print("[DeploymentController] _process_embarkation called with transport: %s, units: %s" % [transport_id, str(unit_ids)])

	for unit_id in unit_ids:
		print("[DeploymentController] Processing embarkation for unit: %s" % unit_id)

		# Check if unit exists and is undeployed
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			push_error("[DeploymentController] Unit not found: %s" % unit_id)
			continue

		var unit_status = unit.get("status", -1)
		print("[DeploymentController] Unit %s status before embark: %d (0=UNDEPLOYED, 1=DEPLOYING, 2=DEPLOYED)" % [unit_id, unit_status])

		# Use TransportManager to handle the embarkation
		var can_embark_result = TransportManager.can_embark(unit_id, transport_id)
		print("[DeploymentController] Can embark? %s" % str(can_embark_result))

		if can_embark_result.valid:
			TransportManager.embark_unit(unit_id, transport_id)
			print("[DeploymentController] embark_unit() called successfully")
		else:
			push_error("[DeploymentController] Cannot embark %s: %s" % [unit_id, can_embark_result.reason])
			continue

		# Mark embarked units as deployed via PhaseManager
		if has_node("/root/PhaseManager"):
			var phase_manager = get_node("/root/PhaseManager")
			if phase_manager.current_phase_instance:
				phase_manager.apply_state_changes([{
					"op": "set",
					"path": "units.%s.status" % unit_id,
					"value": GameStateData.UnitStatus.DEPLOYED
				}])
				print("[DeploymentController] Set status to DEPLOYED for %s" % unit_id)

		# Verify embarkation
		unit = GameState.get_unit(unit_id)
		var embarked_in = unit.get("embarked_in", null)
		var final_status = unit.get("status", -1)
		print("[DeploymentController] After embark - embarked_in: %s, status: %d" % [str(embarked_in), final_status])

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("[DeploymentController] Embarked %s in %s" % [unit_name, transport_id])

func _send_character_attachment_action(bodyguard_id: String, character_ids: Array) -> void:
	"""Send character attachment action through network sync (multiplayer only)"""
	var attach_action = {
		"type": "ATTACH_CHARACTER_DEPLOYMENT",
		"bodyguard_id": bodyguard_id,
		"character_ids": character_ids,
		"phase": GameStateData.Phase.DEPLOYMENT,
		"timestamp": Time.get_unix_time_from_system()
	}

	var result = NetworkIntegration.route_action(attach_action)

	if result.success:
		DebugLogger.info("Character attachment action sent successfully", {
			"bodyguard_id": bodyguard_id,
			"character_count": character_ids.size()
		})
	else:
		push_error("Character attachment action failed: " + str(result.get("error", "Unknown")))
		DebugLogger.error("Failed to send character attachment action", {
			"bodyguard_id": bodyguard_id,
			"character_ids": character_ids,
			"error": result.get("error", "Unknown")
		})

func _process_character_attachment(bodyguard_id: String, character_ids: Array) -> void:
	"""Process character attachment directly (single-player mode)"""
	print("[DeploymentController] _process_character_attachment called with bodyguard: %s, characters: %s" % [bodyguard_id, str(character_ids)])

	var bodyguard = GameState.get_unit(bodyguard_id)
	if bodyguard.is_empty():
		push_error("[DeploymentController] Bodyguard not found: %s" % bodyguard_id)
		return

	for char_id in character_ids:
		print("[DeploymentController] Processing attachment for character: %s" % char_id)

		var char_unit = GameState.get_unit(char_id)
		if char_unit.is_empty():
			push_error("[DeploymentController] Character unit not found: %s" % char_id)
			continue

		# Use CharacterAttachmentManager to handle the attachment
		var can_attach_result = CharacterAttachmentManager.can_attach(char_id, bodyguard_id)
		print("[DeploymentController] Can attach? %s" % str(can_attach_result))

		if can_attach_result.valid:
			CharacterAttachmentManager.attach_character(char_id, bodyguard_id)
			print("[DeploymentController] attach_character() called successfully")
		else:
			push_error("[DeploymentController] Cannot attach %s: %s" % [char_id, can_attach_result.reason])
			continue

		# Place character model adjacent to bodyguard formation
		_place_character_model_adjacent(char_id, bodyguard_id)

		# Mark character unit as deployed via PhaseManager
		if has_node("/root/PhaseManager"):
			var phase_manager = get_node("/root/PhaseManager")
			if phase_manager.current_phase_instance:
				phase_manager.apply_state_changes([{
					"op": "set",
					"path": "units.%s.status" % char_id,
					"value": GameStateData.UnitStatus.DEPLOYED
				}])
				print("[DeploymentController] Set status to DEPLOYED for character %s" % char_id)

		# Verify attachment
		char_unit = GameState.get_unit(char_id)
		var attached_to = char_unit.get("attached_to", null)
		var final_status = char_unit.get("status", -1)
		print("[DeploymentController] After attach - attached_to: %s, status: %d" % [str(attached_to), final_status])

		var char_name = char_unit.get("meta", {}).get("name", char_id)
		print("[DeploymentController] Attached %s to %s" % [char_name, bodyguard_id])

func _place_character_model_adjacent(char_id: String, bodyguard_id: String) -> void:
	"""Place character model(s) adjacent to the bodyguard formation"""
	var bodyguard = GameState.get_unit(bodyguard_id)
	var char_unit = GameState.get_unit(char_id)

	if bodyguard.is_empty() or char_unit.is_empty():
		return

	# Find the first bodyguard model position as reference
	var ref_pos = Vector2.ZERO
	for model in bodyguard.get("models", []):
		var pos = model.get("position", null)
		if pos != null:
			ref_pos = Vector2(pos.get("x", pos.x if pos is Vector2 else 0), pos.get("y", pos.y if pos is Vector2 else 0))
			break

	if ref_pos == Vector2.ZERO:
		print("[DeploymentController] WARNING: No bodyguard model positions found for adjacent placement")
		return

	# Place character models adjacent to the formation
	var char_models = char_unit.get("models", [])
	for i in range(char_models.size()):
		var model = char_models[i]
		var char_base_mm = model.get("base_mm", 40)
		var bg_base_mm = bodyguard.get("models", [{}])[0].get("base_mm", 32)

		# Offset: place just outside the first bodyguard model's base
		var offset_px = Measurement.base_radius_px(char_base_mm) + Measurement.base_radius_px(bg_base_mm) + 2
		var char_pos = ref_pos + Vector2(offset_px, 0)

		# Update character model position in GameState
		GameState.state.units[char_id].models[i].position = {"x": char_pos.x, "y": char_pos.y}
		print("[DeploymentController] Placed character model %d at %s" % [i, str(char_pos)])

func _initial_deploy_rotation_for(owner_player: int) -> float:
	# The rotation a freshly-shown ghost should start at. Once the player has
	# placed (and possibly rotated) a model this unit, carry that rotation over to
	# the next model; otherwise fall back to the default enemy-facing so the very
	# first model still auto-faces the opponent.
	if _last_deploy_rotation != null:
		return _last_deploy_rotation
	return BoardState.get_default_facing_for_player(owner_player)

func _create_ghost() -> void:
	print("[DeploymentController] _create_ghost() called")
	print("[DeploymentController] ghost_layer is null: ", ghost_layer == null)
	print("[DeploymentController] unit_id: ", unit_id)
	print("[DeploymentController] model_idx: ", model_idx)

	if ghost_sprite != null:
		ghost_sprite.queue_free()

	var GhostVisualScript = load("res://scripts/GhostVisual.gd")
	print("[DeploymentController] GhostVisual script loaded: ", GhostVisualScript != null)
	if GhostVisualScript == null:
		push_error("[DeploymentController] FAILED to load GhostVisual.gd!")
		return

	ghost_sprite = GhostVisualScript.new()
	print("[DeploymentController] ghost_sprite created: ", ghost_sprite != null)
	ghost_sprite.name = "GhostPreview"

	var unit_data = GameState.get_unit(unit_id)
	print("[DeploymentController] unit_data found: ", not unit_data.is_empty())

	# For combined deployments, use the combined model data
	if is_combined_deployment and model_idx < combined_models.size():
		var cm = combined_models[model_idx]
		var model_data = cm["model_data"]
		var cm_unit_data = GameState.get_unit(cm["unit_id"])
		print("[DeploymentController] combined model_data from unit %s: %s" % [cm["unit_id"], model_data.get("id", "unknown")])
		ghost_sprite.owner_player = cm_unit_data.get("owner", unit_data["owner"])
		ghost_sprite.set_model_data(model_data)
		ghost_sprite.set_meta("unit_id", cm["unit_id"])
		# MA-17: Set model type label on ghost
		ghost_sprite.set_model_type_label(_get_model_type_label(model_data, cm_unit_data))
	elif model_idx < unit_data["models"].size():
		var model_data = unit_data["models"][model_idx]
		print("[DeploymentController] model_data: ", model_data.get("id", "unknown"))
		ghost_sprite.owner_player = unit_data["owner"]
		# Set the complete model data for shape handling
		ghost_sprite.set_model_data(model_data)
		ghost_sprite.set_meta("unit_id", unit_id)
		# MA-17: Set model type label on ghost
		ghost_sprite.set_model_type_label(_get_model_type_label(model_data, unit_data))

	# Default facing: orient the model toward the opponent's board edge so its
	# sprite faces the enemy instead of just pointing "up". After the first model
	# is placed, this inherits the player's last-applied rotation instead. The
	# player can still rotate freely, which overwrites this default.
	ghost_sprite.set_base_rotation(_initial_deploy_rotation_for(ghost_sprite.owner_player))

	if ghost_layer:
		ghost_layer.add_child(ghost_sprite)
		print("[DeploymentController] Ghost added to ghost_layer. Ghost visible: ", ghost_sprite.visible)
		print("[DeploymentController] ghost_layer child count: ", ghost_layer.get_child_count())
	else:
		push_error("[DeploymentController] ghost_layer is NULL - cannot add ghost!")

func _remove_ghost() -> void:
	if ghost_sprite != null:
		ghost_sprite.queue_free()
		ghost_sprite = null
	_remove_coherency_distance_label()

func _create_coherency_distance_label() -> void:
	if coherency_distance_label != null:
		return
	coherency_distance_label = Label.new()
	coherency_distance_label.name = "CoherencyDistanceLabel"
	coherency_distance_label.z_index = 25  # Above ghost (z_index 20)
	coherency_distance_label.add_theme_font_size_override("font_size", 18)
	coherency_distance_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	coherency_distance_label.add_theme_constant_override("shadow_offset_x", 1)
	coherency_distance_label.add_theme_constant_override("shadow_offset_y", 1)
	coherency_distance_label.visible = false
	if ghost_layer:
		ghost_layer.add_child(coherency_distance_label)

func _remove_coherency_distance_label() -> void:
	if coherency_distance_label != null:
		coherency_distance_label.queue_free()
		coherency_distance_label = null

func _update_coherency_distance_display(ghost_pos: Vector2, ghost_model_data: Dictionary, ghost_rotation: float) -> void:
	"""Update the floating coherency distance label near the ghost model."""
	# Determine which ghost to update (reposition ghost or main ghost)
	var active_ghost = reposition_ghost if (repositioning_model and reposition_ghost) else ghost_sprite

	# Only show when there are placed models to measure against
	var has_placed_models = false
	for pos in temp_positions:
		if pos != null:
			has_placed_models = true
			break

	if not has_placed_models:
		if coherency_distance_label != null:
			coherency_distance_label.visible = false
		if active_ghost and active_ghost.has_method("clear_nearest_model"):
			active_ghost.clear_nearest_model()
		return

	# Create the label if it doesn't exist
	if coherency_distance_label == null:
		_create_coherency_distance_label()

	# Build a temporary model dict for the ghost
	var ghost_model = ghost_model_data.duplicate()
	ghost_model["position"] = ghost_pos
	ghost_model["rotation"] = ghost_rotation

	# Find nearest placed model distance (edge-to-edge, shape-aware)
	var unit_data = GameState.get_unit(unit_id)
	var min_distance_inches = INF
	var nearest_pos: Vector2 = Vector2.ZERO

	for i in range(temp_positions.size()):
		if temp_positions[i] == null:
			continue
		# Skip the model being repositioned (it's at the ghost position, not its stored position)
		if repositioning_model and i == reposition_model_index:
			continue
		# Build placed model dict
		var placed_model: Dictionary
		if is_combined_deployment and i < combined_models.size():
			placed_model = combined_models[i]["model_data"].duplicate()
		else:
			placed_model = unit_data["models"][i].duplicate()
		placed_model["position"] = temp_positions[i]
		placed_model["rotation"] = temp_rotations[i] if i < temp_rotations.size() else 0.0

		var dist = Measurement.model_to_model_distance_inches(ghost_model, placed_model)
		if dist < min_distance_inches:
			min_distance_inches = dist
			nearest_pos = temp_positions[i]

	if min_distance_inches == INF:
		coherency_distance_label.visible = false
		if active_ghost and active_ghost.has_method("clear_nearest_model"):
			active_ghost.clear_nearest_model()
		return

	# Update ghost with nearest model info for connecting line
	if active_ghost and active_ghost.has_method("set_nearest_model"):
		active_ghost.set_nearest_model(nearest_pos, min_distance_inches)

	# Update label text and color
	var is_in_coherency = min_distance_inches <= GameConstants.coherency_distance_inches() + Measurement.DISTANCE_TOLERANCE_INCHES
	coherency_distance_label.text = "%.1f\"" % min_distance_inches
	if is_in_coherency:
		coherency_distance_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))  # Green
	else:
		coherency_distance_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))  # Red

	# Position the label offset from the ghost (above and to the right)
	coherency_distance_label.position = ghost_pos + Vector2(20, -30)
	coherency_distance_label.visible = true

func _update_ghost_for_next_model() -> void:
	if ghost_sprite == null:
		return

	# For combined deployments, use the combined model data
	if is_combined_deployment and model_idx < combined_models.size():
		var cm = combined_models[model_idx]
		var model_data = cm["model_data"]
		ghost_sprite.set_model_data(model_data)
		# Keep the ghost's unit_id in sync so the facing sprite resolves for the
		# model actually being placed (bodyguard vs attached character).
		ghost_sprite.set_meta("unit_id", cm["unit_id"])
		# Carry over the last-applied rotation (falls back to the default
		# enemy-facing before any model in this unit has been placed).
		ghost_sprite.set_base_rotation(_initial_deploy_rotation_for(ghost_sprite.owner_player))
		ghost_sprite.queue_redraw()
		return

	var unit_data = GameState.get_unit(unit_id)
	if model_idx < unit_data["models"].size():
		var model_data = unit_data["models"][model_idx]
		# Update model data for the next model
		ghost_sprite.set_model_data(model_data)
		# Carry over the last-applied rotation (falls back to the default
		# enemy-facing before any model in this unit has been placed).
		ghost_sprite.set_base_rotation(_initial_deploy_rotation_for(ghost_sprite.owner_player))
		ghost_sprite.queue_redraw()

func _spawn_preview_token(unit_id: String, model_index: int, pos: Vector2, rotation: float = 0.0) -> void:
	var token = _create_token_visual(unit_id, model_index, pos, true, rotation)
	placed_tokens.append(token)
	token_layer.add_child(token)
	# Drop-in animation: scale from 0 to 1 over 0.2s for tactile feedback
	token.scale = Vector2.ZERO
	var tween = token.create_tween()
	tween.tween_property(token, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	print("[DeploymentController] Drop-in animation started for token %s model %d" % [unit_id, model_index])

	# DEPLOY-VIS-5: Add coherency circle around the placed model
	_spawn_coherency_circle(unit_id, model_index, pos)

func _spawn_coherency_circle(p_unit_id: String, model_index: int, pos: Vector2) -> void:
	"""DEPLOY-VIS-5: Spawn a faint 2\" coherency range circle around a placed model."""
	var unit_data = GameState.get_unit(p_unit_id)
	if unit_data.is_empty():
		return
	var model_data = unit_data["models"][model_index]
	var base_radius = Measurement.base_radius_px(model_data["base_mm"])

	var circle = load("res://scripts/CoherencyCircleVisual.gd").new()
	circle.position = pos
	circle.name = "CoherencyCircle_%d" % coherency_circles.size()
	circle.setup(base_radius)
	coherency_circles.append(circle)
	if token_layer:
		token_layer.add_child(circle)
	print("[DeploymentController] Spawned coherency circle at %s (base_radius=%.1f)" % [str(pos), base_radius])

func _clear_coherency_circles() -> void:
	"""DEPLOY-VIS-5: Remove all coherency visualization circles."""
	for circle in coherency_circles:
		if is_instance_valid(circle):
			circle.queue_free()
	coherency_circles.clear()

func _update_coherency_circles() -> void:
	"""DEPLOY-VIS-5: Update coherency circle colors based on ghost position.
	Green if the ghost (next model to place) would be within 2\" coherency range
	of that placed model, red if out of range."""
	if coherency_circles.is_empty():
		return

	# Get ghost position and model data
	var ghost_pos: Vector2 = Vector2.ZERO
	var ghost_model_data: Dictionary = {}
	var ghost_rotation: float = 0.0
	var has_ghost: bool = false

	if repositioning_model and reposition_ghost:
		ghost_pos = reposition_ghost.position
		var unit_data = GameState.get_unit(unit_id)
		ghost_model_data = unit_data["models"][reposition_model_index]
		if reposition_ghost.has_method("get_base_rotation"):
			ghost_rotation = reposition_ghost.get_base_rotation()
		has_ghost = true
	elif ghost_sprite != null and model_idx < temp_positions.size():
		ghost_pos = ghost_sprite.position
		if is_combined_deployment and model_idx < combined_models.size():
			ghost_model_data = combined_models[model_idx]["model_data"]
		else:
			var unit_data = GameState.get_unit(unit_id)
			if not unit_data.is_empty() and model_idx < unit_data["models"].size():
				ghost_model_data = unit_data["models"][model_idx]
		if ghost_sprite.has_method("get_base_rotation"):
			ghost_rotation = ghost_sprite.get_base_rotation()
		has_ghost = not ghost_model_data.is_empty()

	if not has_ghost:
		# No ghost visible (all models placed) — show coherency status between placed models
		_update_coherency_circles_static()
		return

	# Build ghost model dict for distance measurement
	var ghost_model = ghost_model_data.duplicate()
	ghost_model["position"] = ghost_pos
	ghost_model["rotation"] = ghost_rotation

	var unit_data = GameState.get_unit(unit_id)
	if unit_data.is_empty():
		return

	# Update each circle: green if ghost is within 2" edge-to-edge of that placed model
	for i in range(coherency_circles.size()):
		if i >= temp_positions.size() or temp_positions[i] == null:
			continue
		if not is_instance_valid(coherency_circles[i]):
			continue
		# Skip repositioning model's circle
		if repositioning_model and i == reposition_model_index:
			coherency_circles[i].visible = false
			continue
		coherency_circles[i].visible = true

		# Build placed model dict
		var placed_model: Dictionary
		if is_combined_deployment and i < combined_models.size():
			placed_model = combined_models[i]["model_data"].duplicate()
		else:
			placed_model = unit_data["models"][i].duplicate()
		placed_model["position"] = temp_positions[i]
		placed_model["rotation"] = temp_rotations[i] if i < temp_rotations.size() else 0.0

		var dist = Measurement.model_to_model_distance_inches(ghost_model, placed_model)
		coherency_circles[i].set_in_range(dist <= GameConstants.coherency_distance_inches() + Measurement.DISTANCE_TOLERANCE_INCHES)

func _update_coherency_circles_static() -> void:
	"""DEPLOY-VIS-5: When no ghost is active, show coherency status between placed models.
	A model's circle is green when it satisfies the unit's 11e coherency requirement
	(within 2\" of at least one other model AND within 9\" of every other model) and red
	when it does not. Uses the same _compute_coherency_status() as the confirm-time
	enforcement so the visual and the deploy gate never disagree — e.g. a model that is
	touching a neighbour but is more than 9\" from a far-flung mate now correctly shows red."""
	if coherency_circles.is_empty():
		return
	var status = _compute_coherency_status()
	if status["unit_empty"]:
		return
	var incoherent_indices = status["incoherent_indices"]

	for i in range(coherency_circles.size()):
		if i >= temp_positions.size() or temp_positions[i] == null:
			continue
		if not is_instance_valid(coherency_circles[i]):
			continue
		coherency_circles[i].visible = true

		# A lone placed model is always coherent
		if status["placed_count"] <= 1:
			coherency_circles[i].set_in_range(true)
			continue

		coherency_circles[i].set_in_range(not (i in incoherent_indices))

func _create_token_visual(unit_id: String, model_index: int, pos: Vector2, is_preview: bool = false, rotation: float = 0.0) -> Node2D:
	var token = Node2D.new()
	token.position = pos
	token.name = "Token_%s_%d" % [unit_id, model_index]

	var unit_data = GameState.get_unit(unit_id)
	var model_data = unit_data["models"][model_index].duplicate()
	# Add rotation to model data
	model_data["rotation"] = rotation
	var base_mm = model_data["base_mm"]
	var base_circle = load("res://scripts/TokenVisual.gd").new()
	base_circle.owner_player = unit_data["owner"]
	base_circle.is_preview = is_preview
	base_circle.model_number = model_index + 1
	# Set the complete model data for shape handling
	base_circle.set_model_data(model_data)

	# Set metadata for enhanced visual overlays (sprites, wound pips, etc.)
	var model_id = model_data.get("id", "m%d" % (model_index + 1))
	base_circle.set_meta("unit_id", unit_id)
	base_circle.set_meta("model_id", model_id)
	base_circle.queue_redraw()

	token.add_child(base_circle)

	return token

func _clear_previews() -> void:
	for token in placed_tokens:
		if is_instance_valid(token):
			token.queue_free()
	placed_tokens.clear()
	_clear_coherency_circles()

func _finalize_tokens() -> void:
	# Placement previews are wrapper Node2Ds ("Token_<unit>_<idx>") holding the
	# meta-carrying TokenVisual as a child, so pre-confirm code (undo /
	# repositioning) can address them by name. Everything OUTSIDE this
	# controller — board hover tooltip, right-click context menu, movement /
	# charge / scout visual sync — walks token_layer's DIRECT children and
	# expects unit_id/model_id meta on the token itself (the flat shape
	# Main._create_token_visual and _on_ai_unit_deployed produce). Leaving the
	# wrappers behind on confirm made every player-deployed unit invisible to
	# those systems while AI-deployed / save-loaded units worked (reported as:
	# hover tooltip and right-click color menu dead on own models only).
	# On confirm, promote each inner TokenVisual to a flat token_layer child at
	# the wrapper's position and drop the wrapper.
	for token in placed_tokens:
		if not is_instance_valid(token):
			continue
		var promoted := false
		for child in token.get_children():
			if child.has_method("set_preview"):
				child.set_preview(false)
			if not promoted and child.has_meta("unit_id") and token_layer and is_instance_valid(token_layer):
				var world_pos: Vector2 = token.position
				token.remove_child(child)
				token_layer.add_child(child)
				child.position = world_pos
				promoted = true
		token.queue_free()
	placed_tokens.clear()
	_clear_coherency_circles()

# Delegated to Measurement.gd (single source of truth)
func _circle_wholly_in_polygon(center: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	return Measurement.circle_wholly_in_polygon(center, radius, polygon)

func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	return Measurement.point_to_line_distance(point, line_start, line_end)

func _coherency_model_at(index: int, unit_data: Dictionary) -> Dictionary:
	"""Build a positioned model dict for coherency math from the temp placement
	buffers, honouring combined (multi-profile) deployments. Sets a unique index-based
	id and alive=true so AttackSequence.check_unit_coherency's offender list maps
	cleanly back to model indices for the visuals."""
	var model: Dictionary
	if is_combined_deployment and index < combined_models.size():
		model = combined_models[index]["model_data"].duplicate()
	else:
		model = unit_data["models"][index].duplicate()
	model["position"] = temp_positions[index]
	model["rotation"] = temp_rotations[index] if index < temp_rotations.size() else 0.0
	model["alive"] = true
	model["id"] = "coh_%d" % index
	return model

func _compute_coherency_status() -> Dictionary:
	"""Single source of truth for deployment coherency over the currently-placed
	temp models. Delegates to AttackSequence.check_unit_coherency() so deployment
	matches every other phase.

	11th edition (core rules 03.03): a unit of 2+ models is in coherency only while EVERY model is
	  • within 2\" horizontally / 5\" vertically of at least ONE other model in the unit, AND
	  • within 9\" horizontally / 5\" vertically of EVERY other model in the unit (the envelope).

	Returns {unit_empty, placed_count, total_models, incoherent_indices,
	spread_violation, isolation_violation}."""
	var unit_data = GameState.get_unit(unit_id)

	var placed_indices = []
	for i in range(temp_positions.size()):
		if temp_positions[i] != null:
			placed_indices.append(i)

	var status = {
		"unit_empty": unit_data.is_empty(),
		"placed_count": placed_indices.size(),
		"total_models": temp_positions.size(),
		"incoherent_indices": [],
		"spread_violation": false,    # 11e 9" envelope broken (models too far apart)
		"isolation_violation": false, # a model has no mate within 2"
	}
	if unit_data.is_empty() or placed_indices.size() < 2:
		return status

	# Build a synthetic unit from the temp positions and ask the canonical checker.
	var synthetic_models: Array = []
	var id_to_index := {}
	for i in placed_indices:
		var m = _coherency_model_at(i, unit_data)
		id_to_index[m["id"]] = i
		synthetic_models.append(m)

	var result = AttackSequence.check_unit_coherency({"models": synthetic_models})
	for offender in result.get("offenders", []):
		if id_to_index.has(offender):
			status["incoherent_indices"].append(id_to_index[offender])

	# Classify WHY (informational only — the verdict above is authoritative) so the
	# player-facing message can name the specific broken condition. Mirrors the
	# thresholds check_unit_coherency uses.
	if not result.get("coherent", true):
		var coh_px = Measurement.inches_to_px(GameConstants.coherency_distance_inches())
		var envelope_px = Measurement.inches_to_px(GameConstants.coherency_envelope_inches())
		for a in range(synthetic_models.size()):
			var neighbors = 0
			for b in range(synthetic_models.size()):
				if a == b:
					continue
				var d = Measurement.model_to_model_distance_px(synthetic_models[a], synthetic_models[b])
				if d <= coh_px:
					neighbors += 1
				if d > envelope_px:
					status["spread_violation"] = true
			if neighbors < 1:
				status["isolation_violation"] = true
	return status

func _coherency_failure_message() -> String:
	"""Player-facing explanation of why deployment coherency failed. States the full 11e
	rule (2\" to a mate AND 9\" to every model) and names whichever condition is broken."""
	var status = _compute_coherency_status()
	var bad = status["incoherent_indices"].size()
	var msg = "Cannot deploy: %d model(s) out of coherency. Every model must be within 2\" of at least one other model in the unit AND within 9\" of every other model in the unit." % bad
	if status["spread_violation"]:
		msg += " Some models are more than 9\" apart — pull the unit closer together."
	elif status["isolation_violation"]:
		msg += " Some models are more than 2\" from their nearest mate."
	return msg

func _check_coherency_warning() -> void:
	var status = _compute_coherency_status()
	if status["unit_empty"] or status["placed_count"] < 2:
		emit_signal("coherency_warning_changed", false, "")
		return

	var incoherent_indices = status["incoherent_indices"]
	if incoherent_indices.size() > 0:
		var msg = "Coherency warning: %d model(s) out of coherency" % incoherent_indices.size()
		if status["spread_violation"]:
			msg += " — some are >9\" from another model in the unit"
		elif status["isolation_violation"]:
			msg += " — some are >2\" from any mate"
		print("[WARNING] %s" % msg)
		_show_toast(msg, Color.YELLOW)
		emit_signal("coherency_warning_changed", true, msg)
	else:
		emit_signal("coherency_warning_changed", false, "")

func _is_unit_coherent() -> bool:
	"""Check if the currently placed models satisfy unit coherency rules (11e 03.03):
	every model within 2\" horizontally / 5\" vertically of at least one other model AND
	within 9\" of every other model in the unit. Single-model units are always coherent.
	Coherency is only enforced once every model in the unit is placed.
	Distance is measured edge-to-edge (nearest base edge to nearest base edge)."""
	var status = _compute_coherency_status()
	if status["unit_empty"]:
		return true

	# Single model (or none) placed — always coherent
	if status["placed_count"] <= 1:
		return true

	# Not all models placed yet — can't enforce coherency
	if status["placed_count"] < status["total_models"]:
		return true

	return status["incoherent_indices"].is_empty()

func _shape_wholly_in_polygon(center: Vector2, model_data: Dictionary, rotation: float, polygon: PackedVector2Array) -> bool:
	return Measurement.shape_wholly_in_polygon(center, model_data, rotation, polygon)

func _overlaps_with_existing_models_shape(pos: Vector2, model_data: Dictionary, rotation: float) -> bool:
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	# Check overlap with already placed models in current unit.
	# Index-safe for combined placements: temp_positions is indexed by the
	# COMBINED list (bodyguard + attached characters), which is longer than
	# unit_data["models"] — reading the bodyguard array at a character's index
	# threw once any model was placed after the leader (undo / type picker).
	var unit_data = GameState.get_unit(unit_id)
	var unit_models = unit_data.get("models", [])
	for i in range(temp_positions.size()):
		if temp_positions[i] != null:
			var other_model_data: Dictionary
			if is_combined_deployment and i < combined_models.size():
				other_model_data = combined_models[i]["model_data"]
			elif i < unit_models.size():
				other_model_data = unit_models[i]
			else:
				continue
			var other_rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0
			if _shapes_overlap(pos, model_data, rotation, temp_positions[i], other_model_data, other_rotation):
				return true

	# Check overlap with all deployed models from all units
	var all_units = GameState.state.get("units", {})
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
			for model in other_unit["models"]:
				var model_position = model.get("position", null)
				if model_position:
					var other_pos = Vector2(model_position.x, model_position.y)
					var other_rotation = model.get("rotation", 0.0)
					if _shapes_overlap(pos, model_data, rotation, other_pos, model, other_rotation):
						return true

	return false

func _shapes_overlap(pos1: Vector2, model1: Dictionary, rot1: float, pos2: Vector2, model2: Dictionary, rot2: float) -> bool:
	# Use actual shape collision detection from BaseShape API
	var shape1 = Measurement.create_base_shape(model1)
	var shape2 = Measurement.create_base_shape(model2)

	if not shape1 or not shape2:
		return false

	# Use shape-aware collision (works for all shape combinations)
	return shape1.overlaps_with(shape2, pos1, rot1, pos2, rot2)

func _get_shape_max_extent(model_data: Dictionary) -> float:
	"""Get maximum extent of a model's base shape for spacing calculations"""
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		# Fallback to circular assumption
		return Measurement.base_radius_px(model_data.get("base_mm", 32))

	var bounds = shape.get_bounds()
	return max(bounds.size.x, bounds.size.y)

func _overlaps_with_existing_models(pos: Vector2, radius: float) -> bool:
	# Check overlap with already placed models in current unit
	for placed_pos in temp_positions:
		if placed_pos != null:
			var distance = pos.distance_to(placed_pos)
			var other_radius = radius  # Same unit, same base size
			if distance < (radius + other_radius):
				return true

	# Check overlap with all deployed models from all units
	var all_units = GameState.state.get("units", {})
	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
			for model in other_unit["models"]:
				var model_position = model.get("position", null)
				if model_position != null:
					var model_pos = Vector2(model_position.get("x", 0), model_position.get("y", 0))
					var distance = pos.distance_to(model_pos)
					var other_radius = Measurement.base_radius_px(model["base_mm"])
					if distance < (radius + other_radius):
						return true
	
	return false

func _get_deploying_unit_keywords(index: int = -1) -> Array:
	if unit_id == "":
		return []
	# Combined placement: the model at `index` may belong to an attached
	# CHARACTER, whose traversal keywords (e.g. INFANTRY vs JUMP PACK) can
	# differ from the bodyguard squad's.
	if index >= 0 and is_combined_deployment and index < combined_models.size():
		var owner_id = str(combined_models[index]["unit_id"])
		return GameState.get_unit(owner_id).get("meta", {}).get("keywords", [])
	return GameState.get_unit(unit_id).get("meta", {}).get("keywords", [])

func _show_toast(message: String, color: Color = Color.RED) -> void:
	print("[%s] %s" % ["WARNING" if color == Color.YELLOW else "ERROR", message])
	# Show on-screen toast via ToastManager
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		if color == Color.YELLOW:
			toast_mgr.show_warning(message)
		else:
			toast_mgr.show_error(message)

func _dict_array_to_packed_vector2(dict_array: Array) -> PackedVector2Array:
	var packed = PackedVector2Array()
	for dict in dict_array:
		if dict is Dictionary and dict.has("x") and dict.has("y"):
			packed.append(Vector2(dict.x, dict.y))
	return packed

func _process(delta: float) -> void:
	if not is_placing():
		return

	var mouse_pos = _get_world_mouse_position()

	# Handle repositioning ghost updates (highest priority)
	if repositioning_model and reposition_ghost:
		var model_data = _reposition_model_data(reposition_model_index)
		var rot = 0.0
		if reposition_ghost.has_method("get_base_rotation"):
			rot = reposition_ghost.get_base_rotation()
		# A lifted model gets the same exclusion-zone clamp as a fresh drop, so
		# nudging one up against the 9" line works the same way placing it did.
		var lifted_pos = _clamped_placement_position(mouse_pos, model_data, rot, reposition_model_index)
		reposition_ghost.position = lifted_pos
		if reposition_ghost.has_method("set_clamp_origin"):
			if lifted_pos.is_equal_approx(mouse_pos):
				reposition_ghost.set_clamp_origin(null, "")
			else:
				reposition_ghost.set_clamp_origin(mouse_pos, _placement_clamp_label())
		var is_valid = _validate_reposition(lifted_pos, model_data, reposition_model_index, true)
		reposition_ghost.set_validity(is_valid)
		# Show coherency distance during repositioning too
		_update_coherency_distance_display(lifted_pos, model_data, rot)
		_update_coherency_circles()
		return

	# Handle formation mode ghost updates
	if formation_mode != "SINGLE" and not formation_preview_ghosts.is_empty():
		_update_formation_ghost_positions(mouse_pos)
		# Hide coherency distance and connecting line in formation mode (multiple ghosts)
		if coherency_distance_label != null:
			coherency_distance_label.visible = false
		for fg in formation_preview_ghosts:
			if fg and fg.has_method("clear_nearest_model"):
				fg.clear_nearest_model()
		_update_coherency_circles()
		return

	# Handle single mode ghost updates
	if ghost_sprite != null and model_idx < temp_positions.size():
		# Get model data - from combined_models for combined deployment, otherwise from unit
		var model_data: Dictionary
		if is_combined_deployment and model_idx < combined_models.size():
			model_data = combined_models[model_idx]["model_data"]
		else:
			var unit_data = GameState.get_unit(unit_id)
			model_data = unit_data["models"][model_idx]
		var active_player = GameState.get_active_player()

		# Get current rotation from ghost
		var rotation = 0.0
		if ghost_sprite.has_method("get_base_rotation"):
			rotation = ghost_sprite.get_base_rotation()

		# Hold the ghost outside the Deep Strike / Infiltrators exclusion zone
		# rather than letting it drift in and turn red. try_place_at() applies
		# the SAME clamp to the click, so what the player sees previewed is
		# exactly where the model lands.
		var ghost_pos = _clamped_placement_position(mouse_pos, model_data, rotation)
		ghost_sprite.position = ghost_pos
		if ghost_sprite.has_method("set_clamp_origin"):
			if ghost_pos.is_equal_approx(mouse_pos):
				ghost_sprite.set_clamp_origin(null, "")
			else:
				ghost_sprite.set_clamp_origin(mouse_pos, _placement_clamp_label())

		var is_valid = false

		if is_reinforcement_mode:
			# Reinforcement mode: validate >9" from enemies instead of deployment zone.
			# silent=true — this is the per-frame ghost-colour check; a failure just
			# reddens the ghost, it must NOT stack a toast every frame (the click in
			# try_place_at surfaces the reason).
			is_valid = _validate_reinforcement_position(ghost_pos, model_data, rotation, true)
			# Also check model overlap
			if is_valid and _overlaps_with_existing_models_shape(ghost_pos, model_data, rotation):
				is_valid = false
		elif is_infiltrators_mode:
			# Infiltrators mode: validate >9" from enemy zone and enemy models
			# (silent per-frame — see the reinforcement branch above).
			is_valid = _validate_infiltrators_position(ghost_pos, model_data, rotation, true)
			# Also check model overlap
			if is_valid and _overlaps_with_existing_models_shape(ghost_pos, model_data, rotation):
				is_valid = false
		else:
			# Normal deployment: check deployment zone and model overlap
			var zone = BoardState.get_deployment_zone_for_player(active_player)
			var base_type = model_data.get("base_type", "circular")

			if base_type == "circular":
				var radius_px = Measurement.base_radius_px(model_data["base_mm"])
				is_valid = _circle_wholly_in_polygon(mouse_pos, radius_px, zone) and not _overlaps_with_existing_models_shape(mouse_pos, model_data, rotation)
			else:
				is_valid = _shape_wholly_in_polygon(mouse_pos, model_data, rotation, zone) and not _overlaps_with_existing_models_shape(mouse_pos, model_data, rotation)

		# Also check wall collision, honoring the deploying unit's traversal keywords.
		if is_valid:
			var test_model = model_data.duplicate()
			test_model["position"] = ghost_pos
			test_model["rotation"] = rotation
			if Measurement.model_overlaps_any_wall(test_model, _get_deploying_unit_keywords(model_idx)):
				is_valid = false

		if ghost_sprite.has_method("set_validity"):
			ghost_sprite.set_validity(is_valid)

		# Update coherency distance display near ghost — measured from where the
		# ghost actually IS, which a clamped placement moves off the cursor.
		_update_coherency_distance_display(ghost_pos, model_data, rotation)

	# DEPLOY-VIS-5: Update coherency circle colors based on ghost position
	_update_coherency_circles()

func _get_world_mouse_position() -> Vector2:
	# Get the main scene to access the coordinate conversion
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("screen_to_world_position"):
		var screen_pos = get_viewport().get_mouse_position()
		return main_scene.screen_to_world_position(screen_pos)
	else:
		# Fallback to simple mouse position
		return get_viewport().get_mouse_position()

# Formation mode management
func set_formation_mode(mode: String) -> void:
	formation_mode = mode
	formation_rotation = 0.0  # Reset rotation when changing modes
	print("[DeploymentController] Formation mode set to: ", mode)

	# If we're currently placing, update the ghosts
	if is_placing():
		if mode == "SINGLE":
			_clear_formation_ghosts()
			# If a previous TIGHT/SPREAD placement filled the unit (or left
			# model_idx pointing at an already-placed slot), the cached
			# model_idx is stale. _create_ghost() needs a valid index to
			# attach model_data, otherwise the ghost is added to the layer
			# with no shape and _process skips its position updates — the
			# user sees no ghost and clicks fall through.
			var remaining = _get_unplaced_model_indices()
			if remaining.is_empty():
				_remove_ghost()
				return
			if model_idx >= temp_positions.size() or temp_positions[model_idx] != null:
				model_idx = remaining[0]
			if not ghost_sprite:
				_create_ghost()
		else:
			_remove_ghost()
			var remaining = _get_unplaced_model_indices()
			if not remaining.is_empty():
				_create_formation_ghosts(min(formation_size, remaining.size()))

func _get_unplaced_model_indices() -> Array:
	"""Get indices of models that haven't been placed yet"""
	var unplaced = []
	for i in range(temp_positions.size()):
		if temp_positions[i] == null:
			unplaced.append(i)
	return unplaced

# Formation calculation functions
func calculate_spread_formation(anchor_pos: Vector2, model_count: int, base_mm: int, rotation: float = 0.0, model_data_array: Array = []) -> Array:
	"""Calculate positions for maximum spread (2 inch coherency)
	MA-18: Supports mixed base sizes via model_data_array. Each model's actual base
	extent is used for spacing so edge-to-edge coherency of 2\" is maintained."""
	var positions = []

	# MA-18: Build per-model base extents from model_data_array or fall back to uniform
	var base_extents = []
	if model_data_array.size() == model_count:
		for md in model_data_array:
			var shape = Measurement.create_base_shape(md)
			var bounds = shape.get_bounds()
			base_extents.append(max(bounds.size.x, bounds.size.y))
	else:
		# Fallback: use first model's data for all (backward compat)
		var unit_data = GameState.get_unit(unit_id)
		var remaining_indices = _get_unplaced_model_indices()
		if remaining_indices.is_empty():
			return positions
		var first_md: Dictionary
		if is_combined_deployment and remaining_indices[0] < combined_models.size():
			first_md = combined_models[remaining_indices[0]]["model_data"]
		else:
			first_md = unit_data["models"][remaining_indices[0]]
		var shape = Measurement.create_base_shape(first_md)
		var bounds = shape.get_bounds()
		var extent = max(bounds.size.x, bounds.size.y)
		for i in range(model_count):
			base_extents.append(extent)

	var coherency_px = Measurement.inches_to_px(2.0)  # 2" coherency edge-to-edge

	# Arrange in rows of 5
	var cols = min(5, model_count)

	# MA-18: Compute cumulative x positions per row, accounting for different radii
	# Between model i and model i+1: center distance = extent_i/2 + coherency + extent_{i+1}/2
	for i in range(model_count):
		var col = i % cols
		var row = floor(i / cols)

		# Calculate x offset: accumulate from col 0 to this col within the same row
		var row_start = int(row) * cols
		var x_pos = 0.0
		for c in range(col):
			var idx_prev = row_start + c
			var idx_curr = row_start + c + 1
			x_pos += base_extents[idx_prev] / 2.0 + coherency_px + base_extents[idx_curr] / 2.0

		# Calculate y offset: accumulate from row 0 to this row
		var y_pos = 0.0
		for r in range(row):
			# Use spacing based on model at same col in adjacent rows (or first col as reference)
			var idx_above = r * cols + min(col, cols - 1)
			var idx_curr = (r + 1) * cols + min(col, cols - 1)
			if idx_above < model_count and idx_curr < model_count:
				y_pos += base_extents[idx_above] / 2.0 + coherency_px + base_extents[idx_curr] / 2.0
			else:
				# Fallback for incomplete rows
				y_pos += base_extents[min(idx_above, model_count - 1)] / 2.0 + coherency_px + base_extents[min(idx_curr, model_count - 1)] / 2.0

		# Center the row horizontally: compute total row width
		var row_model_count = min(cols, model_count - row_start)
		var row_total_width = 0.0
		for c in range(row_model_count - 1):
			var idx_a = row_start + c
			var idx_b = row_start + c + 1
			row_total_width += base_extents[idx_a] / 2.0 + coherency_px + base_extents[idx_b] / 2.0

		var x_offset = x_pos - row_total_width / 2.0
		var base_pos = Vector2(x_offset, y_pos)

		# Apply rotation around origin, then translate to anchor
		var rotated_pos = base_pos.rotated(rotation)
		positions.append(anchor_pos + rotated_pos)

	return positions

func calculate_tight_formation(anchor_pos: Vector2, model_count: int, base_mm: int, rotation: float = 0.0, model_data_array: Array = []) -> Dictionary:
	"""Calculate positions for tight formation (bases touching).
	Returns {"positions": Array[Vector2], "rotations": Array[float]}
	For oval/rectangular bases, models are rotated 90 degrees so the longer axis
	points north-south, allowing them to fit closer together side by side.
	MA-18: Supports mixed base sizes via model_data_array. Each model's actual base
	extent is used so bases are touching with a minimal 1px gap."""
	var positions = []
	var model_rotations = []

	# MA-18: Build per-model base extents from model_data_array or fall back to uniform
	var base_extents = []
	var unit_data = GameState.get_unit(unit_id)
	var remaining_indices = _get_unplaced_model_indices()
	if remaining_indices.is_empty():
		return {"positions": positions, "rotations": model_rotations}

	# Determine base type from first model for elongated base handling
	var first_model_data: Dictionary
	if is_combined_deployment and remaining_indices[0] < combined_models.size():
		first_model_data = combined_models[remaining_indices[0]]["model_data"]
	else:
		first_model_data = unit_data["models"][remaining_indices[0]]
	var base_type = first_model_data.get("base_type", "circular")
	var is_elongated = base_type == "oval" or base_type == "rectangular"

	if model_data_array.size() == model_count:
		for md in model_data_array:
			var shape = Measurement.create_base_shape(md)
			var bounds = shape.get_bounds()
			base_extents.append(max(bounds.size.x, bounds.size.y))
	else:
		# Fallback: use first model's data for all (backward compat)
		var shape = Measurement.create_base_shape(first_model_data)
		var bounds = shape.get_bounds()
		var extent = max(bounds.size.x, bounds.size.y)
		for i in range(model_count):
			base_extents.append(extent)

	# For oval/rectangular bases, rotate 90 degrees so longer axis points north-south
	var per_model_rotation = PI / 2.0 if is_elongated else 0.0

	if is_elongated:
		# After 90-degree rotation, the shorter dimension (width) is horizontal
		# and the longer dimension (length) is vertical
		var first_shape = Measurement.create_base_shape(first_model_data)
		var first_bounds = first_shape.get_bounds()
		var x_spacing = first_bounds.size.y + 1  # width becomes horizontal after rotation
		var y_spacing = first_bounds.size.x + 1  # length becomes vertical after rotation
		var cols = min(5, model_count)

		for i in range(model_count):
			var col = i % cols
			var row = floor(i / cols)
			var x_offset = (col - cols/2.0) * x_spacing
			var y_offset = row * y_spacing
			var base_pos = Vector2(x_offset, y_offset)

			var rotated_pos = base_pos.rotated(rotation)
			positions.append(anchor_pos + rotated_pos)
			model_rotations.append(per_model_rotation + rotation)
	else:
		var gap_px = 1  # 1px gap to prevent overlap
		var cols = min(5, model_count)

		# MA-18: Compute cumulative positions per row, accounting for different radii
		for i in range(model_count):
			var col = i % cols
			var row = floor(i / cols)

			var row_start = int(row) * cols
			var x_pos = 0.0
			for c in range(col):
				var idx_prev = row_start + c
				var idx_curr = row_start + c + 1
				x_pos += base_extents[idx_prev] / 2.0 + gap_px + base_extents[idx_curr] / 2.0

			var y_pos = 0.0
			for r in range(row):
				var idx_above = r * cols + min(col, cols - 1)
				var idx_curr = (r + 1) * cols + min(col, cols - 1)
				if idx_above < model_count and idx_curr < model_count:
					y_pos += base_extents[idx_above] / 2.0 + gap_px + base_extents[idx_curr] / 2.0
				else:
					y_pos += base_extents[min(idx_above, model_count - 1)] / 2.0 + gap_px + base_extents[min(idx_curr, model_count - 1)] / 2.0

			var row_model_count = min(cols, model_count - row_start)
			var row_total_width = 0.0
			for c in range(row_model_count - 1):
				var idx_a = row_start + c
				var idx_b = row_start + c + 1
				row_total_width += base_extents[idx_a] / 2.0 + gap_px + base_extents[idx_b] / 2.0

			var x_offset = x_pos - row_total_width / 2.0
			var base_pos = Vector2(x_offset, y_pos)

			# Apply rotation around origin, then translate to anchor
			var rotated_pos = base_pos.rotated(rotation)
			positions.append(anchor_pos + rotated_pos)
			model_rotations.append(0.0)

	return {"positions": positions, "rotations": model_rotations}

# Formation ghost management
func _create_formation_ghosts(count: int) -> void:
	"""Create multiple ghost visuals for formation preview"""
	_clear_formation_ghosts()

	var unit_data = GameState.get_unit(unit_id)
	var remaining_models = _get_unplaced_model_indices()
	var models_to_place = min(count, remaining_models.size())

	for i in range(models_to_place):
		var model_index = remaining_models[i]
		var model_data: Dictionary
		if is_combined_deployment and model_index < combined_models.size():
			model_data = combined_models[model_index]["model_data"]
		else:
			model_data = unit_data["models"][model_index]
		var ghost = load("res://scripts/GhostVisual.gd").new()
		ghost.name = "FormationGhost_%d" % i
		ghost.owner_player = unit_data["owner"]
		ghost.set_model_data(model_data)
		# Stamp which unit this formation slot belongs to (combined deploys mix
		# units) so GhostVisual can resolve the model's facing sprite. Without the
		# unit_id meta, _draw_ghost_model_art() bails and only the base outline +
		# letter/arrow render — the single-placement ghost sets this too.
		var fm_unit_id = unit_id
		if is_combined_deployment and model_index < combined_models.size():
			fm_unit_id = combined_models[model_index]["unit_id"]
		ghost.set_meta("unit_id", fm_unit_id)
		# MA-17: Set model type label on formation ghosts
		var fm_unit_data = GameState.get_unit(fm_unit_id)
		ghost.set_model_type_label(_get_model_type_label(model_data, fm_unit_data))
		ghost.modulate.a = 0.6  # Slightly transparent for formation ghosts
		ghost_layer.add_child(ghost)
		formation_preview_ghosts.append(ghost)

func _clear_formation_ghosts() -> void:
	"""Remove all formation ghost visuals"""
	for ghost in formation_preview_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	formation_preview_ghosts.clear()

func _update_formation_ghost_positions(mouse_pos: Vector2) -> void:
	"""Update positions of all formation ghosts"""
	if formation_preview_ghosts.is_empty():
		return

	var unit_data = GameState.get_unit(unit_id)
	var remaining_models = _get_unplaced_model_indices()
	if remaining_models.is_empty():
		return

	# MA-18: Build model data array for all formation ghosts (supports mixed base sizes)
	var ghost_count = formation_preview_ghosts.size()
	var formation_model_data: Array = []
	for i in range(ghost_count):
		if i < remaining_models.size():
			var idx = remaining_models[i]
			if is_combined_deployment and idx < combined_models.size():
				formation_model_data.append(combined_models[idx]["model_data"])
			else:
				formation_model_data.append(unit_data["models"][idx])
	var base_mm = formation_model_data[0]["base_mm"] if not formation_model_data.is_empty() else 32

	var positions = []
	var ghost_rotations = []  # Per-model rotations for oval/rectangular in tight formation
	match formation_mode:
		"SPREAD":
			positions = calculate_spread_formation(mouse_pos, formation_preview_ghosts.size(), base_mm, formation_rotation, formation_model_data)
			ghost_rotations.resize(positions.size())
			ghost_rotations.fill(0.0)
		"TIGHT":
			var result = calculate_tight_formation(mouse_pos, formation_preview_ghosts.size(), base_mm, formation_rotation, formation_model_data)
			positions = result["positions"]
			ghost_rotations = result["rotations"]

	# Update ghost positions and validity
	var zone = BoardState.get_deployment_zone_for_player(GameState.get_active_player())

	# Hold the whole block outside the Deep Strike / Infiltrators exclusion zone.
	# try_place_formation_at() re-derives the same shifted anchor, so the drop
	# lands on the previewed block.
	var clamped_anchor = _clamped_formation_anchor(mouse_pos, positions, formation_model_data, ghost_rotations, zone)
	if clamped_anchor != mouse_pos:
		var shift = clamped_anchor - mouse_pos
		for i in range(positions.size()):
			positions[i] = positions[i] + shift

	for i in range(formation_preview_ghosts.size()):
		var ghost = formation_preview_ghosts[i]
		if i < positions.size():
			ghost.position = positions[i]
			ghost.visible = true

			# Apply per-model rotation for oval/rectangular bases in tight formation
			var model_rot = ghost_rotations[i] if i < ghost_rotations.size() else 0.0
			ghost.set_base_rotation(model_rot)

			# MA-18: Use each model's actual data for validation
			var model_data_for_validation = formation_model_data[i] if i < formation_model_data.size() else formation_model_data[0]
			# silent=true — per-frame formation-ghost colour check; a failure just
			# reddens the ghosts instead of stacking a toast per model per frame
			# (the click path in try_place_formation_at surfaces the reason).
			var is_valid = _validate_formation_position(positions[i], model_data_for_validation, zone, model_rot, true)
			ghost.set_validity(is_valid)

func _validate_formation_position(pos: Vector2, model_data: Dictionary, zone: PackedVector2Array, model_rotation: float = 0.0, silent: bool = false) -> bool:
	"""Validate a single position in a formation. silent=true suppresses the
	reinforcement/infiltrator failure toasts — the per-frame formation-ghost
	colour check passes it so hovering an illegal drop just reddens the ghosts
	instead of stacking a toast per model per frame; the click path (formation
	placement) leaves it false so a rejected drop still explains why."""
	if is_reinforcement_mode:
		# Reinforcement (Deep Strike / Strategic Reserves): reinforcements arrive
		# across the whole battlefield, NOT the owning player's deployment zone,
		# so validate against the reinforcement rules (>9" from enemies, on the
		# board, Strategic-Reserves board-edge, Omni-scramblers) instead of the
		# zone check. Mirrors the single-model path in try_place_at()/_process();
		# without this branch a formation dropped in a legal Deep Strike spot
		# would be falsely rejected as "outside deployment zone".
		if not _validate_reinforcement_position(pos, model_data, model_rotation, silent):
			return false
		if _overlaps_with_existing_models_shape(pos, model_data, model_rotation):
			return false
	elif is_infiltrators_mode:
		# In Infiltrators mode, use Infiltrators validation instead of zone check
		if not _validate_infiltrators_position(pos, model_data, model_rotation, silent):
			return false
		if _overlaps_with_existing_models_shape(pos, model_data, model_rotation):
			return false
	else:
		var base_type = model_data.get("base_type", "circular")

		if base_type == "circular":
			var radius_px = Measurement.base_radius_px(model_data["base_mm"])
			if not _circle_wholly_in_polygon(pos, radius_px, zone):
				return false
			if _overlaps_with_existing_models_shape(pos, model_data, model_rotation):
				return false
		else:
			# For non-circular bases, use shape-aware validation
			if not _shape_wholly_in_polygon(pos, model_data, model_rotation, zone):
				return false
			if _overlaps_with_existing_models_shape(pos, model_data, model_rotation):
				return false

	# Check wall collision, honoring the deploying unit's traversal keywords.
	var test_model = model_data.duplicate()
	test_model["position"] = pos
	test_model["rotation"] = model_rotation
	if Measurement.model_overlaps_any_wall(test_model, _get_deploying_unit_keywords()):
		return false

	return true

# Model Repositioning Functions

func _reposition_model_data(index: int) -> Dictionary:
	"""Model data for a staged placement slot. temp_positions is indexed over the
	COMBINED roster during a combined deployment (bodyguard models followed by the
	attached characters'), so unit_data["models"][index] is the wrong array —
	and out of range past the bodyguard's own model count."""
	var models = _get_effective_models()
	if index < 0 or index >= models.size():
		return {}
	return models[index]


func _preview_token_name_for(index: int) -> String:
	"""Name of the preview token spawned for a staged placement slot. Combined
	deployments spawn tokens under the OWNING unit's id and that unit's own model
	index (see try_place_at), so "Token_<current unit>_<combined index>" misses an
	attached character's token entirely — leaving it behind at the old spot when
	the model was repositioned."""
	var tok_unit_id := unit_id
	var tok_model_idx := index
	if is_combined_deployment and index < combined_models.size():
		tok_unit_id = combined_models[index]["unit_id"]
		tok_model_idx = combined_models[index]["model_idx"]
	return "Token_%s_%d" % [tok_unit_id, tok_model_idx]


func _find_preview_token(index: int) -> Node2D:
	var token_name := _preview_token_name_for(index)
	for token in placed_tokens:
		if is_instance_valid(token) and token.name == token_name:
			return token
	return null


func _apply_preview_token_rotation(token: Node2D, rot: float) -> void:
	"""Re-face an already-spawned preview token. The rotation is baked into the
	inner TokenVisual's model_data at spawn time (_create_token_visual), so
	moving the wrapper Node2D is not enough — the visual has to be re-fed."""
	if token == null or not is_instance_valid(token):
		return
	for child in token.get_children():
		if child.has_method("set_model_data") and "model_data" in child:
			var md: Dictionary = (child.model_data as Dictionary).duplicate()
			md["rotation"] = rot
			child.set_model_data(md)
			child.queue_redraw()


func _set_placement_ghosts_visible(visible_state: bool) -> void:
	"""Show/hide the ghosts that preview the NEXT placement. _process stops
	updating them while a model is lifted, so leaving them visible parked a
	frozen ghost on the board at whatever point the lift began — which is
	exactly the spot the player just picked a model up from."""
	if ghost_sprite and is_instance_valid(ghost_sprite):
		ghost_sprite.visible = visible_state
	for fg in formation_preview_ghosts:
		if fg and is_instance_valid(fg):
			fg.visible = visible_state


func _get_deployed_model_at_position(world_pos: Vector2) -> Dictionary:
	"""Find deployed model from current unit at given position"""
	if unit_id == "" or temp_positions.is_empty():
		return {}

	for i in range(temp_positions.size()):
		if temp_positions[i] != null:  # Model is placed
			var model_pos = temp_positions[i]
			var model_data = _reposition_model_data(i)
			if model_data.is_empty():
				continue
			var rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0

			# Use shape-aware hit detection
			var shape = Measurement.create_base_shape(model_data)
			if shape and shape.contains_point(world_pos, model_pos, rotation):
				return {
					"model_index": i,
					"position": model_pos,
					"model_data": model_data
				}

	return {}

func _start_model_repositioning(deployed_model: Dictionary) -> void:
	"""Begin repositioning a deployed model"""
	repositioning_model = true
	reposition_model_index = deployed_model.model_index
	reposition_start_pos = deployed_model.position

	print("Starting repositioning of model ", reposition_model_index)

	# Create ghost visual for repositioning
	var model_data = deployed_model.model_data
	reposition_ghost = load("res://scripts/GhostVisual.gd").new()
	reposition_ghost.name = "RepositionGhost"
	reposition_ghost.owner_player = GameState.get_active_player()
	reposition_ghost.set_model_data(model_data)
	# Stamp the unit so the ghost resolves the facing sprite (matches the
	# single-placement ghost); without unit_id meta only the outline draws.
	reposition_ghost.set_meta("unit_id", unit_id)
	# MA-17: Set model type label on reposition ghost
	var repo_unit_data = GameState.get_unit(unit_id)
	reposition_ghost.set_model_type_label(_get_model_type_label(model_data, repo_unit_data))
	# Pick the model up at the facing it is currently sitting at, not at 0 — the
	# lift is a nudge, so it must not silently un-rotate an angled model, and the
	# player rotates on from here (see _rotate_active_ghost).
	reposition_ghost.set_base_rotation(temp_rotations[reposition_model_index] if reposition_model_index < temp_rotations.size() else 0.0)
	ghost_layer.add_child(reposition_ghost)

	# The next-placement ghosts stop tracking the cursor while a model is in hand
	# — hide them so they don't sit frozen at the pick-up point looking like the
	# model never left.
	_set_placement_ghosts_visible(false)

	# Make the original token semi-transparent during repositioning
	var orig_token := _find_preview_token(reposition_model_index)
	if orig_token:
		orig_token.modulate.a = 0.3  # Make original semi-transparent

func _update_model_repositioning(mouse_pos: Vector2) -> void:
	"""Update ghost position during repositioning"""
	if not repositioning_model or not reposition_ghost:
		return

	var world_pos = _get_world_mouse_position()
	reposition_ghost.position = world_pos

	# Validate new position. silent=true — runs on every mouse-motion event to
	# recolour the ghost; a failure must not stack a toast per motion (the drop
	# in _end_model_repositioning surfaces the reason).
	var model_data = _reposition_model_data(reposition_model_index)
	var is_valid = _validate_reposition(world_pos, model_data, reposition_model_index, true)

	reposition_ghost.set_validity(is_valid)

func _reposition_rotation_for(model_index: int) -> float:
	"""The facing to validate/commit a lifted model at: the LIVE ghost rotation
	while it is in hand (the player can rotate mid-lift), the stored staged
	rotation otherwise. Reading temp_rotations unconditionally validated the
	drop against the model's pre-lift facing, so a rotated oval could be dropped
	somewhere its actual footprint does not fit."""
	if repositioning_model and reposition_ghost and is_instance_valid(reposition_ghost) \
			and model_index == reposition_model_index and reposition_ghost.has_method("get_base_rotation"):
		return reposition_ghost.get_base_rotation()
	return temp_rotations[model_index] if model_index < temp_rotations.size() else 0.0

func _validate_reposition(world_pos: Vector2, model_data: Dictionary, model_index: int, silent: bool = false) -> bool:
	"""Validate if repositioning is allowed at the given position. silent=true
	suppresses the Infiltrators failure toasts for the per-frame reposition-ghost
	colour check; the drop path leaves it false."""
	if model_data.is_empty():
		return false
	var active_player = GameState.get_active_player()
	var rotation = _reposition_rotation_for(model_index)

	if is_reinforcement_mode:
		# Reinforcement (Deep Strike / Strategic Reserves / Rapid Ingress): the
		# unit is arriving across the whole battlefield, so the same rules the
		# initial drop is judged by apply to a lift-and-nudge of one of its
		# models. Without this branch the else-branch below measured a lifted
		# Deep Strike model against the player's own DEPLOYMENT ZONE, so it
		# could only ever be dropped back inside it — nudging a model that had
		# just been legally placed mid-board was impossible.
		if not _validate_reinforcement_position(world_pos, model_data, rotation, silent):
			return false
	elif is_infiltrators_mode:
		# In Infiltrators mode, use Infiltrators validation instead of zone check
		if not _validate_infiltrators_position(world_pos, model_data, rotation, silent):
			return false
	else:
		var zone = BoardState.get_deployment_zone_for_player(active_player)
		var base_type = model_data.get("base_type", "circular")

		# Check deployment zone
		var in_zone = false
		if base_type == "circular":
			var radius_px = Measurement.base_radius_px(model_data["base_mm"])
			in_zone = _circle_wholly_in_polygon(world_pos, radius_px, zone)
		else:
			in_zone = _shape_wholly_in_polygon(world_pos, model_data, rotation, zone)

		if not in_zone:
			return false

	# Check overlap (excluding the model being repositioned)
	return not _would_overlap_excluding_self(world_pos, model_data, model_index)

func _would_overlap_excluding_self(pos: Vector2, model_data: Dictionary, exclude_index: int) -> bool:
	"""Check for overlaps excluding the model being repositioned"""
	var shape = Measurement.create_base_shape(model_data)
	if not shape:
		return false

	# Check overlap with other models in current unit (excluding self)
	var self_rotation = _reposition_rotation_for(exclude_index)
	for i in range(temp_positions.size()):
		if i != exclude_index and temp_positions[i] != null:
			var other_model_data = _reposition_model_data(i)
			if other_model_data.is_empty():
				continue
			var other_rotation = temp_rotations[i] if i < temp_rotations.size() else 0.0
			if _shapes_overlap(pos, model_data, self_rotation, temp_positions[i], other_model_data, other_rotation):
				return true

	# Check overlap with all deployed models from other units
	var all_units = GameState.state.get("units", {})
	for other_unit_id in all_units:
		if other_unit_id == unit_id:
			continue  # Skip current unit, already checked above

		var other_unit = all_units[other_unit_id]
		if other_unit["status"] == GameStateData.UnitStatus.DEPLOYED:
			for model in other_unit["models"]:
				var model_position = model.get("position", null)
				if model_position:
					var other_pos = Vector2(model_position.x, model_position.y)
					var other_rotation = model.get("rotation", 0.0)
					if _shapes_overlap(pos, model_data, self_rotation, other_pos, model, other_rotation):
						return true

	return false

func _end_model_repositioning(mouse_pos: Vector2) -> void:
	"""Complete model repositioning"""
	if not repositioning_model:
		return

	var world_pos = _get_world_mouse_position()
	var model_data = _reposition_model_data(reposition_model_index)
	# The facing the player is holding the model at — rotating mid-lift is part
	# of the nudge, so the drop has to commit it, not throw it away.
	var drop_rotation := _reposition_rotation_for(reposition_model_index)
	# Same clamp the lifted ghost was previewing with, so the model lands where
	# the player saw it hovering (a no-op outside the exclusion zone).
	world_pos = _clamped_placement_position(world_pos, model_data, drop_rotation, reposition_model_index)
	var token := _find_preview_token(reposition_model_index)

	# Validate final position
	if _validate_reposition(world_pos, model_data, reposition_model_index):
		# Update position and facing
		temp_positions[reposition_model_index] = world_pos
		if reposition_model_index < temp_rotations.size():
			temp_rotations[reposition_model_index] = drop_rotation
		# Same carry-over rule as try_place_at: the last facing the player applied
		# becomes the default for the next model of this unit.
		_last_deploy_rotation = drop_rotation

		# Update the token position + facing
		if token:
			token.position = world_pos
			token.modulate.a = 1.0  # Restore full opacity
			_apply_preview_token_rotation(token, drop_rotation)

		# DEPLOY-VIS-5: Update coherency circle position after repositioning
		if reposition_model_index < coherency_circles.size():
			var circle = coherency_circles[reposition_model_index]
			if is_instance_valid(circle):
				circle.position = world_pos

		print("Model ", reposition_model_index, " repositioned to ", world_pos, " rot ", drop_rotation)
		reposition_commits += 1
		emit_signal("models_placed_changed")
		_check_coherency_warning()
	else:
		# Revert to original position
		if token:
			token.modulate.a = 1.0  # Restore full opacity
		_show_toast("Invalid position for repositioning")

	_cleanup_repositioning()

func _cancel_model_repositioning() -> void:
	"""Cancel model repositioning and restore original state"""
	if not repositioning_model:
		return

	# Restore original token opacity (position and facing were never touched)
	var token := _find_preview_token(reposition_model_index)
	if token:
		token.modulate.a = 1.0

	_cleanup_repositioning()

# --- Pad entry points for model repositioning -------------------------------
# Repositioning an already-placed model was a mouse-only affordance: Shift+click
# picks the model up, mouse-move drags it, click drops it, right-click cancels.
# A controller has no Shift and no right-click while placing, so a pad player who
# put a model a few millimetres off had to undo the model (X) — or the whole unit
# (B) — and re-place. These wrap the existing mouse flow so PadRouter can drive
# the identical state machine from L3 / A / B; the drop and cancel paths are the
# mouse ones untouched (A already arrives as a synthesized left-click through
# VirtualCursor, which _unhandled_input routes to _end_model_repositioning).

func is_repositioning() -> bool:
	return repositioning_model


func pad_begin_reposition_at_cursor() -> bool:
	"""Pick up the already-placed model under the virtual cursor (pad L3 — the
	counterpart to mouse Shift+click). Returns false when the press was not
	spent, so the caller can fall through to L3's other meanings.

	Only models of the unit currently being placed are eligible: the hit-test
	walks temp_positions, which is this session's staged placement, so a
	confirmed unit's models are never picked up by mistake."""
	if not is_placing() or repositioning_model:
		return false
	var deployed_model = _get_deployed_model_at_position(_get_world_mouse_position())
	if deployed_model.is_empty():
		# Nothing under the cursor. Say so rather than failing silently — L3 is
		# a no-op in this phase otherwise, so a bare press would look broken.
		if get_placed_count() > 0:
			_show_toast("Point at a placed model to move it", Color.YELLOW)
		return false
	_start_model_repositioning(deployed_model)
	return true


func pad_cancel_reposition() -> bool:
	"""Drop the lifted model back where it came from (pad B — the counterpart to
	the mouse right-click cancel)."""
	if not repositioning_model:
		return false
	_cancel_model_repositioning()
	return true

# ── Exclusion-zone placement clamp ──────────────────────────────────
# The inverse of the movement phase's over-range drag clamp: instead of holding
# a model INSIDE a circle it may not leave, this holds a Deep Strike / Strategic
# Reserves / Rapid Ingress placement OUTSIDE the 9" bubbles it may not enter.
# Aim the cursor slightly too close and the ghost stops on the boundary instead
# of turning red, so squeezing a drop to exactly 9" no longer means landing the
# cursor on an invisible line by hand (impossible on a thumbstick, fiddly on a
# mouse).
#
# SAFETY PROPERTY: the clamp only ever moves a position that is inside a
# stand-off bubble — i.e. one the click path rejects outright today — and only
# to a point the real validator accepts. Anything that places successfully now
# places identically, at the very same coordinates.

func _placement_clamp_active() -> bool:
	"""Whether placements should be held outside the exclusion zone. Always on
	for the pad (a thumbstick cannot hit a 1-pixel boundary), otherwise the
	player's setting. Mirrors PhaseControllerBase.drag_clamp_active()."""
	var idm = get_node_or_null("/root/InputDeviceManager")
	if idm != null and idm.has_method("is_pad_active") and idm.is_pad_active():
		return true
	var settings = get_node_or_null("/root/SettingsService")
	if settings == null:
		return false
	return bool(settings.get("placement_clamp_to_exclusion"))

func _placement_exclusion_bubbles(model_data: Dictionary) -> Array:
	"""The forbidden discs this placement's CENTRE must stay out of, in board px.
	Each radius is the rule's stand-off plus both base radii, so it encodes
	exactly the edge-to-edge test the matching validator runs."""
	var bubbles: Array = []
	if not (is_reinforcement_mode or is_infiltrators_mode):
		return bubbles

	var px_per_inch: float = 40.0
	var model_radius_inches: float = (float(model_data.get("base_mm", 32)) / 2.0) / 25.4
	# Same trap as _validate_reinforcement_position: under Rapid Ingress the
	# placing player is the NON-active one, and bubbles drawn around the wrong
	# army would park the clamped ghost on a boundary the click then rejects.
	var placing_player: int = _placement_owner()

	var enemy_standoff: float = _reinforcement_enemy_standoff_inches() if is_reinforcement_mode else _infiltrators_enemy_standoff_inches()
	for enemy in GameState.get_enemy_model_positions(placing_player):
		var enemy_radius_inches: float = (float(enemy.base_mm) / 2.0) / 25.4
		var radius_inches: float = enemy_standoff + model_radius_inches + enemy_radius_inches
		bubbles.append(PlacementClamp.make_bubble(Vector2(enemy.x, enemy.y), radius_inches * px_per_inch))

	# Omni-scramblers push reinforcements out to 12". Infiltrators are not
	# subject to it (its validator does not check it either), so the bubble set
	# stays a faithful mirror of whichever validator will judge the result.
	if is_reinforcement_mode:
		for omni in GameState.get_omni_scrambler_positions(placing_player):
			var omni_radius_inches: float = (float(omni.base_mm) / 2.0) / 25.4
			var radius_inches: float = OMNI_SCRAMBLER_STANDOFF_INCHES + model_radius_inches + omni_radius_inches
			bubbles.append(PlacementClamp.make_bubble(Vector2(omni.x, omni.y), radius_inches * px_per_inch))

	return bubbles

func _placement_position_is_legal(pos: Vector2, model_data: Dictionary, rotation: float, exclude_index: int = -1) -> bool:
	"""Every gate try_place_at() applies, in the same order and silently. The
	clamp offers a position only if this says the click would accept it.
	`exclude_index` is the staged model being lifted for repositioning, which
	must not be treated as an obstacle to itself."""
	var edge_model: Dictionary = model_data.duplicate()
	edge_model["rotation"] = rotation
	if Measurement.model_outside_board(pos, edge_model):
		return false

	if is_reinforcement_mode:
		if not _validate_reinforcement_position(pos, model_data, rotation, true):
			return false
	elif is_infiltrators_mode:
		if not _validate_infiltrators_position(pos, model_data, rotation, true):
			return false
	else:
		return false

	if exclude_index >= 0:
		if _would_overlap_excluding_self(pos, model_data, exclude_index):
			return false
	elif _overlaps_with_existing_models_shape(pos, model_data, rotation):
		return false

	var test_model: Dictionary = model_data.duplicate()
	test_model["position"] = pos
	test_model["rotation"] = rotation
	# Index-aware like try_place_at's own wall check: in a combined placement the
	# model in hand may belong to an attached CHARACTER whose traversal keywords
	# differ from the squad's, and the clamp has to judge walls exactly as the
	# click will. A lift supplies the staged slot it is holding; a fresh drop is
	# on model_idx.
	var keyword_index: int = exclude_index if exclude_index >= 0 else model_idx
	if Measurement.model_overlaps_any_wall(test_model, _get_deploying_unit_keywords(keyword_index)):
		return false

	return true

func _clamped_placement_position(world_pos: Vector2, model_data: Dictionary, rotation: float, exclude_index: int = -1) -> Vector2:
	"""Hold `world_pos` outside the placement exclusion zone, or return it
	untouched when it is already outside — or when nothing legal is reachable by
	pushing it out, so the ghost stays red under the cursor and the click still
	explains itself exactly as before. `exclude_index` is the staged model being
	lifted for repositioning (it must not block its own new home)."""
	if not (is_reinforcement_mode or is_infiltrators_mode):
		return world_pos
	if not _placement_clamp_active():
		return world_pos

	var bubbles: Array = _placement_exclusion_bubbles(model_data)
	if bubbles.is_empty():
		return world_pos
	# Outside every bubble already: the player is placing legally (or is being
	# stopped by something this clamp has no business moving them for, like the
	# board edge). Costs one distance test per enemy model and is the case
	# almost every frame.
	if PlacementClamp.penetration_px(world_pos, bubbles) <= 0.0:
		return world_pos

	var margin_px: float = EXCLUSION_CLAMP_MARGIN_INCHES * 40.0
	var pushed: Vector2 = PlacementClamp.escape(world_pos, bubbles, margin_px)
	if _placement_position_is_legal(pushed, model_data, rotation, exclude_index):
		return pushed

	# Straight out is blocked — nearly always by a model of this same unit already
	# standing on that stretch of the boundary. Step along the boundary to either
	# side of it, and back away from it, and take whichever free spot ends up
	# closest to where the player actually pointed.
	var push_vector: Vector2 = pushed - world_pos
	if push_vector.length_squared() < 0.000001:
		return world_pos
	var out_dir: Vector2 = push_vector.normalized()
	var along: Vector2 = Vector2(-out_dir.y, out_dir.x)  # tangent to the ring
	var step_px: float = maxf(_get_shape_max_extent(model_data) * EXCLUSION_CLAMP_STEP_BASES, 12.0)

	var candidates: Array = []
	for side in EXCLUSION_CLAMP_SIDE_STEPS:
		candidates.append(pushed + along * (float(side) * step_px))
	for back in EXCLUSION_CLAMP_BACK_STEPS:
		candidates.append(pushed + out_dir * (float(back) * step_px))
	# Re-escape every one: stepping sideways along one bubble's ring can walk
	# straight into a neighbouring bubble, and a candidate that is not even
	# outside the exclusion zone is not worth a validator call.
	for i in range(candidates.size()):
		candidates[i] = PlacementClamp.escape(candidates[i], bubbles, margin_px)

	candidates.sort_custom(func(a, b): return world_pos.distance_squared_to(a) < world_pos.distance_squared_to(b))

	var tests: int = 0
	for candidate in candidates:
		if tests >= EXCLUSION_CLAMP_MAX_CANDIDATE_TESTS:
			break
		tests += 1
		if _placement_position_is_legal(candidate, model_data, rotation, exclude_index):
			return candidate

	# Nothing legal nearby — leave the player's own aim alone.
	return world_pos

func _clamped_formation_anchor(anchor: Vector2, positions: Array, model_data_array: Array, rotations: Array, zone: PackedVector2Array) -> Vector2:
	"""Group edition of the clamp: shift a whole formation just far enough that
	EVERY model clears the exclusion zone, keeping the block's shape and facing
	intact. The formation layout is a pure translation of its anchor, so moving
	the anchor moves the block — the same trick
	MovementController._clamp_group_drag_vector uses to hold a dragged formation
	inside its move budget.

	All-or-nothing, like the drop it previews: if the shifted block is not
	legal in full, the anchor is returned untouched and the ghosts redden
	exactly as they do today."""
	if not (is_reinforcement_mode or is_infiltrators_mode):
		return anchor
	if not _placement_clamp_active():
		return anchor
	if positions.is_empty():
		return anchor

	# Bubble radii fold in the placed model's own base, so a formation of mixed
	# bases needs a set per base size. Cached because that is nearly always one
	# set shared by every model in the block.
	var bubbles_by_base: Dictionary = {}
	var bubbles_for := func(index: int) -> Array:
		var md: Dictionary = model_data_array[index] if index < model_data_array.size() else {}
		var key: int = int(md.get("base_mm", 32))
		if not bubbles_by_base.has(key):
			bubbles_by_base[key] = _placement_exclusion_bubbles(md)
		return bubbles_by_base[key]

	var offsets: Array = []
	for pos in positions:
		offsets.append(pos - anchor)

	var margin_px: float = EXCLUSION_CLAMP_MARGIN_INCHES * 40.0
	var shift: Vector2 = Vector2.ZERO
	for _iteration in range(PlacementClamp.MAX_ESCAPE_ITERATIONS):
		# Move by whichever model is worst off; the rest are re-measured next
		# round, so a shift that drags someone else into a bubble is corrected
		# rather than shipped.
		var worst_push: Vector2 = Vector2.ZERO
		var worst_len: float = 0.0
		for i in range(positions.size()):
			var bubbles: Array = bubbles_for.call(i)
			if bubbles.is_empty():
				continue
			var p: Vector2 = anchor + shift + offsets[i]
			if PlacementClamp.penetration_px(p, bubbles) <= 0.0:
				continue
			var push: Vector2 = PlacementClamp.escape(p, bubbles, margin_px) - p
			var push_len: float = push.length()
			if push_len > worst_len:
				worst_len = push_len
				worst_push = push
		if worst_len <= 0.0:
			break
		shift += worst_push

	if shift == Vector2.ZERO:
		return anchor

	for i in range(positions.size()):
		var candidate: Vector2 = anchor + shift + offsets[i]
		var md: Dictionary = model_data_array[i] if i < model_data_array.size() else {}
		var rot: float = float(rotations[i]) if i < rotations.size() else 0.0
		var edge_model: Dictionary = md.duplicate()
		edge_model["rotation"] = rot
		if Measurement.model_outside_board(candidate, edge_model):
			return anchor
		if not _validate_formation_position(candidate, md, zone, rot, true):
			return anchor

	return anchor + shift

func _placement_clamp_label() -> String:
	"""Caption for the tether drawn from the cursor to a held ghost."""
	var standoff: float = _reinforcement_enemy_standoff_inches() if is_reinforcement_mode else _infiltrators_enemy_standoff_inches()
	return "held at %.0f\"" % standoff

## Base radius (inches) of the model currently queued for placement — the one
## the next click will drop. Read by StrategicReservesZoneVisual so the band it
## paints is the region that model's CENTRE may legally occupy, and it keeps up
## as the player switches model type mid-unit.
func current_placement_base_radius_inches() -> float:
	var md := current_placement_model_data()
	return (float(md.get("base_mm", 32)) / 2.0) / 25.4

## The model dict the next placement click will consume (combined-deployment
## aware). Empty when nothing is queued.
func current_placement_model_data() -> Dictionary:
	if model_idx < 0:
		return {}
	if is_combined_deployment and model_idx < combined_models.size():
		return combined_models[model_idx].get("model_data", {})
	var unit_data := GameState.get_unit(unit_id)
	var models: Array = unit_data.get("models", [])
	if model_idx < models.size():
		return models[model_idx]
	return {}

## The player whose unit is being placed. NOT interchangeable with
## GameState.get_active_player(): Rapid Ingress runs this same reinforcement
## placement mode for the NON-active player (MovementPhase sets
## _rapid_ingress_player = defending_player), so anything that resolves
## "enemies" or "your opponent" from the active player is measuring against the
## wrong army there. Falls back to the active player only when the unit is
## unknown (nothing is being placed).
func _placement_owner() -> int:
	var u := GameState.get_unit(unit_id)
	if u.has("owner"):
		return int(u.get("owner"))
	return GameState.get_active_player()

## 20.04: "Set up your unit WHOLLY within the set-up distance of one or more
## battlefield edges". Wholly — so the whole base has to fit inside the 6" band
## of at least one edge, not just the centre dot. Measuring the centre let a
## base hang up to its own radius past the line (2" for a 100mm oval).
##
## Implemented as a containment test against each edge's band rather than as
## "centre distance <= 6 - radius" so rotated oval and rectangular bases are
## handled by the same shape code every other zone check uses.
func _wholly_within_setup_distance_of_edge(world_pos: Vector2, model_data: Dictionary, rotation: float) -> bool:
	for band in _setup_distance_bands():
		if Measurement.shape_wholly_in_polygon(world_pos, model_data, rotation, band):
			return true
	return false

## The four 6" edge bands, in board px. Each spans the full length of its edge,
## so a model in a corner is simply inside two of them.
func _setup_distance_bands() -> Array:
	var w: float = float(GameState.state.board.size.width) * 40.0
	var h: float = float(GameState.state.board.size.height) * 40.0
	var b: float = RESERVES_SETUP_DISTANCE_INCHES * 40.0
	return [
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, b), Vector2(0, b)]),
		PackedVector2Array([Vector2(0, h - b), Vector2(w, h - b), Vector2(w, h), Vector2(0, h)]),
		PackedVector2Array([Vector2(0, 0), Vector2(b, 0), Vector2(b, h), Vector2(0, h)]),
		PackedVector2Array([Vector2(w - b, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - b, h)]),
	]

func _validate_reinforcement_position(world_pos: Vector2, model_data: Dictionary, rotation: float, silent: bool = false) -> bool:
	"""Validate a reinforcement placement position (Deep Strike / Strategic Reserves).
	silent=true suppresses the failure toasts — the per-frame ghost-colour check
	(_process) passes it so hovering an illegal spot just reddens the ghost instead
	of stacking a new toast every frame; the click path (try_place_at) leaves it
	false so a rejected placement still explains why."""
	var px_per_inch = 40.0
	var board_width_px = GameState.state.board.size.width * px_per_inch
	var board_height_px = GameState.state.board.size.height * px_per_inch

	# Must be on the board
	if world_pos.x < 0 or world_pos.x > board_width_px or world_pos.y < 0 or world_pos.y > board_height_px:
		if not silent:
			_show_toast("Must be on the battlefield")
		return false

	# 20.04: "more than 8" horizontally from all enemy units" (11e; 9" at 10e),
	# measured base edge to base edge.
	var unit = GameState.get_unit(unit_id)
	# The placing player is NOT always the active player: a Rapid Ingress reuses
	# this same reinforcement mode while the OTHER player holds the turn, so
	# reading get_active_player() here resolved "enemies" to the ARRIVING
	# player's own models and measured the stand-off against the wrong army.
	var placing_player := _placement_owner()
	var enemy_standoff := _reinforcement_enemy_standoff_inches()
	var model_base_mm = model_data.get("base_mm", 32)
	var model_radius_inches = (model_base_mm / 2.0) / 25.4

	var enemy_positions = GameState.get_enemy_model_positions(placing_player)
	for enemy in enemy_positions:
		var enemy_pos_px = Vector2(enemy.x, enemy.y)
		var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
		var dist_px = world_pos.distance_to(enemy_pos_px)
		var dist_inches = dist_px / px_per_inch
		var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
		if edge_dist < enemy_standoff:
			if not silent:
				_show_toast("Must be >%.0f\" from enemy models (%.1f\")" % [enemy_standoff, edge_dist])
			return false

	# Strategic Reserves: must be set up WHOLLY within 6" of a battlefield edge
	# P2-80: Use reinforcement_placement_type override if set, otherwise use unit's reserve_type
	var reserve_type = unit.get("reserve_type", "strategic_reserves")
	var placement_type = reinforcement_placement_type if reinforcement_placement_type != "" else reserve_type
	if placement_type == "strategic_reserves":
		if not _wholly_within_setup_distance_of_edge(world_pos, model_data, rotation):
			if not silent:
				var pos_inches_x = world_pos.x / px_per_inch
				var pos_inches_y = world_pos.y / px_per_inch
				var board_w = GameState.state.board.size.width
				var board_h = GameState.state.board.size.height
				var centre_dist = min(pos_inches_x, board_w - pos_inches_x, pos_inches_y, board_h - pos_inches_y)
				_show_toast("Strategic Reserves must be set up wholly within %.0f\" of a board edge (base reaches %.1f\")" % [
					RESERVES_SETUP_DISTANCE_INCHES, centre_dist + model_radius_inches])
			return false

		# 11e 20.04 INGRESS MOVE — "Before the Third Battle Round: while doing
		# so, no models can be set up within your opponent's deployment zone."
		# MovementPhase has always rejected this on confirm, but this validator
		# did not, so the ghost stayed green, the models dropped, and the player
		# only found out after placing the whole unit. The band along the
		# opponent's board edge is the obvious trap: it is within 6" of a
		# battlefield edge, so every other check here passes it.
		#
		# "within" (not "wholly within") — any part of the base inside the zone
		# counts, so this is base-aware rather than a centre-point test.
		if GameState.ingress_opponent_dz_ban_applies(GameState.get_battle_round(), false):
			# "Your opponent" is the opponent of the ARRIVING unit's owner (see
			# _placement_owner) — again not the active player under Rapid Ingress.
			var opponent_zone_px = GameState.get_deployment_zone_poly_px(3 - placing_player)
			var dz_probe := model_data.duplicate()
			dz_probe["position"] = world_pos
			dz_probe["rotation"] = rotation
			if Measurement.model_overlaps_polygon(dz_probe, opponent_zone_px):
				if not silent:
					_show_toast("Strategic Reserves cannot arrive in the opponent's deployment zone before battle round 3")
				return false

	# Omni-scramblers: cannot be set up within 12" of enemy units with Omni-scramblers
	var omni_positions = GameState.get_omni_scrambler_positions(placing_player)
	for omni in omni_positions:
		var omni_pos_px = Vector2(omni.x, omni.y)
		var omni_radius_inches = (omni.base_mm / 2.0) / 25.4
		var dist_px = world_pos.distance_to(omni_pos_px)
		var dist_inches = dist_px / px_per_inch
		var edge_dist = dist_inches - model_radius_inches - omni_radius_inches
		if edge_dist < OMNI_SCRAMBLER_STANDOFF_INCHES:
			if not silent:
				_show_toast("Cannot deploy within 12\" of Omni-scramblers (%s) (%.1f\")" % [omni.get("unit_name", "unknown"), edge_dist])
			return false

	return true

func _validate_infiltrators_position(world_pos: Vector2, model_data: Dictionary, rotation: float, silent: bool = false) -> bool:
	"""Validate an Infiltrators deployment position (24.20): anywhere on the board
	more than the stand-off (11e 8", 10e 9") from the enemy deployment zone and
	from all enemy models.
	silent=true suppresses the failure toasts for the per-frame ghost-colour check
	(see _validate_reinforcement_position); the click path leaves it false."""
	var infiltrate_standoff := _infiltrators_enemy_standoff_inches()
	var px_per_inch = 40.0
	var board_width_px = GameState.state.board.size.width * px_per_inch
	var board_height_px = GameState.state.board.size.height * px_per_inch

	# Must be on the board
	if world_pos.x < 0 or world_pos.x > board_width_px or world_pos.y < 0 or world_pos.y > board_height_px:
		if not silent:
			_show_toast("Must be on the battlefield")
		return false

	var active_player = GameState.get_active_player()
	var model_base_mm = model_data.get("base_mm", 32)
	var model_radius_inches = (model_base_mm / 2.0) / 25.4

	# Must be >9" from enemy deployment zone
	var enemy_zone = GameState.get_enemy_deployment_zone(active_player)
	var enemy_zone_poly_inches = enemy_zone.get("poly", [])
	if enemy_zone_poly_inches.size() > 0:
		var enemy_zone_poly_pixels = PackedVector2Array()
		for coord in enemy_zone_poly_inches:
			if coord is Dictionary and coord.has("x") and coord.has("y"):
				enemy_zone_poly_pixels.append(Vector2(coord.x * px_per_inch, coord.y * px_per_inch))

		# Check if model center is inside enemy zone
		if Geometry2D.is_point_in_polygon(world_pos, enemy_zone_poly_pixels):
			if not silent:
				_show_toast("Infiltrators must be >9\" from enemy deployment zone")
			return false

		# Find minimum distance from model center to any edge of the enemy zone
		var min_dist_px = INF
		for i in range(enemy_zone_poly_pixels.size()):
			var p1 = enemy_zone_poly_pixels[i]
			var p2 = enemy_zone_poly_pixels[(i + 1) % enemy_zone_poly_pixels.size()]
			var dist = _point_to_line_distance(world_pos, p1, p2)
			if dist < min_dist_px:
				min_dist_px = dist
		var edge_dist_inches = (min_dist_px / px_per_inch) - model_radius_inches
		if edge_dist_inches < infiltrate_standoff:
			if not silent:
				_show_toast("Infiltrators must be >%.0f\" from enemy deployment zone (%.1f\")" % [infiltrate_standoff, edge_dist_inches])
			return false

	# Must be >9" from all enemy models (edge-to-edge)
	var enemy_positions = GameState.get_enemy_model_positions(active_player)
	for enemy in enemy_positions:
		var enemy_pos_px = Vector2(enemy.x, enemy.y)
		var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
		var dist_px = world_pos.distance_to(enemy_pos_px)
		var dist_inches = dist_px / px_per_inch
		var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
		if edge_dist < infiltrate_standoff:
			if not silent:
				_show_toast("Infiltrators must be >%.0f\" from enemy models (%.1f\")" % [infiltrate_standoff, edge_dist])
			return false

	return true

func _show_infiltrator_exclusion() -> void:
	"""Show the 9-inch exclusion boundary visual around the enemy deployment zone."""
	_hide_infiltrator_exclusion()  # Clean up any existing visual
	var active_player = GameState.get_active_player()
	var enemy_zone = GameState.get_enemy_deployment_zone(active_player)
	var enemy_zone_poly = enemy_zone.get("poly", [])
	if enemy_zone_poly.size() < 3:
		return
	infiltrator_exclusion_visual = load("res://scripts/InfiltratorExclusionVisual.gd").new()
	if ghost_layer:
		ghost_layer.add_child(infiltrator_exclusion_visual)
	else:
		push_error("[DeploymentController] ghost_layer is NULL - cannot add infiltrator exclusion visual!")
		return
	infiltrator_exclusion_visual.show_exclusion(enemy_zone_poly)

func _hide_infiltrator_exclusion() -> void:
	"""Hide and remove the infiltrator exclusion boundary visual."""
	if infiltrator_exclusion_visual and is_instance_valid(infiltrator_exclusion_visual):
		infiltrator_exclusion_visual.hide_exclusion()
		infiltrator_exclusion_visual.queue_free()
		infiltrator_exclusion_visual = null

func _cleanup_repositioning() -> void:
	"""Clean up repositioning state"""
	repositioning_model = false
	reposition_model_index = -1
	reposition_start_pos = Vector2.ZERO

	if reposition_ghost and is_instance_valid(reposition_ghost):
		reposition_ghost.queue_free()
		reposition_ghost = null

	# The next-placement ghosts start tracking the cursor again from the next
	# _process tick — bring them back (hidden in _start_model_repositioning).
	_set_placement_ghosts_visible(true)

# ── MA-15/MA-19: Model type picker methods ───────────────────────────

func _get_effective_models() -> Array:
	"""MA-19: Get the effective models array for picker operations.
	For combined deployment, returns model_data dicts from combined_models.
	For normal deployment, returns unit_data['models']."""
	if is_combined_deployment:
		var models = []
		for cm in combined_models:
			models.append(cm["model_data"])
		return models
	var unit_data = GameState.get_unit(unit_id)
	if unit_data.is_empty():
		return []
	return unit_data["models"]

func _get_effective_profiles() -> Dictionary:
	"""MA-19: Get the effective model profiles for picker operations."""
	if is_combined_deployment:
		return _combined_profiles
	var unit_data = GameState.get_unit(unit_id)
	if unit_data.is_empty():
		return {}
	return unit_data.get("meta", {}).get("model_profiles", {})

func _get_distinct_unplaced_types(models: Array, placed_indices: Array) -> Array:
	"""Get list of distinct model_type values among unplaced models."""
	var types = {}
	for i in range(models.size()):
		if i in placed_indices:
			continue
		var mt = models[i].get("model_type", "")
		if mt != "":
			types[mt] = true
	return types.keys()

func _get_placed_indices() -> Array:
	"""Get indices of models that have been placed (non-null temp_positions)."""
	var placed = []
	for i in range(temp_positions.size()):
		if temp_positions[i] != null:
			placed.append(i)
	return placed

func _show_model_type_picker(model_profiles: Dictionary, models: Array) -> void:
	"""Create and display the model type picker panel inside the right-hand unit card,
	next to the Deploy Formation controls."""
	_hide_model_type_picker()

	var PickerScript = load("res://scripts/ModelTypePickerPanel.gd")
	model_type_picker_panel = PickerScript.new()
	model_type_picker_panel.name = "ModelTypePickerPanel"

	# Try to host the picker inside the right-hand unit card (next to FormationControls).
	# Fall back to a screen-space CanvasLayer if the unit card isn't available.
	var unit_card = _get_unit_card_node()
	if unit_card:
		unit_card.add_child(model_type_picker_panel)
		# Place the picker immediately after the FormationControls row if present.
		var formation_controls = unit_card.get_node_or_null("FormationControls")
		if formation_controls:
			var target_idx = formation_controls.get_index() + 1
			unit_card.move_child(model_type_picker_panel, target_idx)
	else:
		model_type_picker_canvas = CanvasLayer.new()
		model_type_picker_canvas.name = "ModelTypePickerCanvas"
		model_type_picker_canvas.layer = 10
		get_tree().root.add_child(model_type_picker_canvas)
		model_type_picker_canvas.add_child(model_type_picker_panel)
		model_type_picker_panel.position = Vector2(20, 200)

	# Setup with current data
	var placed = _get_placed_indices()
	model_type_picker_panel.setup(model_profiles, models, placed)

	# Connect selection signal
	model_type_picker_panel.model_type_selected.connect(_on_model_type_selected)

	print("[DeploymentController] MA-15: Model type picker shown (parented to %s)" % ("UnitCard" if unit_card else "CanvasLayer"))

func _get_unit_card_node() -> Node:
	"""Locate the right-hand UnitCard VBox in the Main scene, if available."""
	var main_scene = get_tree().current_scene
	if main_scene == null:
		return null
	return main_scene.get_node_or_null("HUD_Right/VBoxContainer/UnitCard")

func _hide_model_type_picker() -> void:
	"""Remove the model type picker panel."""
	if model_type_picker_panel and is_instance_valid(model_type_picker_panel):
		model_type_picker_panel.queue_free()
		model_type_picker_panel = null
	if model_type_picker_canvas and is_instance_valid(model_type_picker_canvas):
		model_type_picker_canvas.queue_free()
		model_type_picker_canvas = null

func _update_model_type_picker() -> void:
	"""Update the picker panel counts based on current placement state."""
	if not model_type_picker_panel or not is_instance_valid(model_type_picker_panel):
		return
	var effective_models = _get_effective_models()
	if effective_models.is_empty():
		return
	var placed = _get_placed_indices()
	model_type_picker_panel.update_counts(effective_models, placed)

func _on_model_type_selected(type_key: String) -> void:
	"""Handle user selecting a model type from the picker."""
	print("[DeploymentController] MA-15: Model type selected: %s" % type_key)
	selected_model_type = type_key

	# Highlight the selected type in the panel
	if model_type_picker_panel and is_instance_valid(model_type_picker_panel):
		model_type_picker_panel.highlight_selected(type_key)

	# Find the first unplaced model of this type
	var effective_models = _get_effective_models()
	if effective_models.is_empty():
		return

	var next_idx = _find_next_unplaced_of_type(effective_models, type_key)
	if next_idx < 0:
		print("[DeploymentController] MA-15: No unplaced models of type %s" % type_key)
		return

	model_idx = next_idx
	print("[DeploymentController] MA-15: Set model_idx to %d for type %s" % [model_idx, type_key])

	# Create/update ghost for this model
	if formation_mode == "SINGLE":
		_remove_ghost()
		_create_ghost()
	else:
		_clear_formation_ghosts()
		var remaining = _get_unplaced_model_indices()
		if not remaining.is_empty():
			_create_formation_ghosts(min(formation_size, remaining.size()))

# Start a picker-enabled session on the FIRST unplaced model rather than
# pausing for a type choice. The movement-phase set-ups (reserves arrival /
# Rapid Ingress) use this so placement is live the moment the session opens —
# the player places the squad in order and can click the picker to jump to the
# leader. Without it, has_model_type_picker with no selected type parks
# model_idx on the "waiting for a pick" sentinel and no ghost appears.
func preselect_first_model_type() -> void:
	if not has_model_type_picker:
		return
	var effective_models = _get_effective_models()
	for i in range(effective_models.size()):
		if i < temp_positions.size() and temp_positions[i] != null:
			continue
		var mt = str(effective_models[i].get("model_type", ""))
		if mt == "":
			continue
		selected_model_type = mt
		model_idx = i
		if model_type_picker_panel and is_instance_valid(model_type_picker_panel):
			model_type_picker_panel.highlight_selected(mt)
		print("[DeploymentController] Placement starts on model %d (type %s)" % [i, mt])
		return

func _get_model_type_label(model_data: Dictionary, unit_data: Dictionary) -> String:
	"""MA-17/MA-19: Get the display label for a model's type from model_profiles.
	Returns empty string if no model_profiles or model has no model_type.
	For combined deployment, also checks _combined_profiles for character types."""
	var model_type = model_data.get("model_type", "")
	if model_type == "":
		return ""
	# MA-19: Check combined profiles first for combined deployment
	if is_combined_deployment and _combined_profiles.has(model_type):
		return _combined_profiles[model_type].get("label", "")
	var model_profiles = unit_data.get("meta", {}).get("model_profiles", {})
	if model_profiles.is_empty():
		return ""
	var profile = model_profiles.get(model_type, {})
	return profile.get("label", "")

func _find_next_unplaced_of_type(models: Array, type_key: String) -> int:
	"""Find the index of the first unplaced model with the given model_type."""
	for i in range(models.size()):
		if temp_positions[i] != null:
			continue
		if models[i].get("model_type", "") == type_key:
			return i
	return -1

func _try_auto_select_model_type() -> bool:
	"""If only one model type has unplaced models, auto-select it. Returns true if auto-selected."""
	var effective_models = _get_effective_models()
	if effective_models.is_empty():
		return false

	var placed = _get_placed_indices()
	var remaining_types = _get_distinct_unplaced_types(effective_models, placed)

	if remaining_types.size() == 1:
		# Auto-select the only remaining type
		var auto_type = remaining_types[0]
		print("[DeploymentController] MA-15: Auto-selecting sole remaining type: %s" % auto_type)
		selected_model_type = auto_type

		# Highlight in picker
		if model_type_picker_panel and is_instance_valid(model_type_picker_panel):
			model_type_picker_panel.highlight_selected(auto_type)
			model_type_picker_panel.update_counts(effective_models, placed)

		# Set model_idx to first unplaced of this type
		var next_idx = _find_next_unplaced_of_type(effective_models, auto_type)
		if next_idx >= 0:
			model_idx = next_idx
			return true

	if remaining_types.size() == 0:
		# All models placed
		model_idx = temp_positions.size()
		return true

	return false

func _advance_model_type_placement() -> void:
	"""After placing a model, advance to the next model of the same type or wait for picker."""
	var effective_models = _get_effective_models()
	if effective_models.is_empty():
		return

	# Update the picker panel
	_update_model_type_picker()

	# Try to find next unplaced model of the same type
	var next_idx = _find_next_unplaced_of_type(effective_models, selected_model_type)
	if next_idx >= 0:
		model_idx = next_idx
		print("[DeploymentController] MA-15: Next model of type %s at index %d" % [selected_model_type, model_idx])
		return

	# No more of this type — check remaining types
	var placed = _get_placed_indices()
	var remaining_types = _get_distinct_unplaced_types(effective_models, placed)

	if remaining_types.size() == 0:
		# All models placed
		model_idx = temp_positions.size()
		print("[DeploymentController] MA-15: All models placed")
		_remove_ghost()
		return

	if remaining_types.size() == 1:
		# Auto-select the last remaining type
		var auto_type = remaining_types[0]
		print("[DeploymentController] MA-15: Auto-selecting last type: %s" % auto_type)
		selected_model_type = auto_type
		if model_type_picker_panel and is_instance_valid(model_type_picker_panel):
			model_type_picker_panel.highlight_selected(auto_type)
		next_idx = _find_next_unplaced_of_type(effective_models, auto_type)
		if next_idx >= 0:
			model_idx = next_idx
			return

	# Multiple types remain — pause placement, wait for user to pick
	model_idx = temp_positions.size()  # Sentinel: prevents ghost/placement
	selected_model_type = ""
	_remove_ghost()
	print("[DeploymentController] MA-15: Type exhausted, waiting for user to select next type")

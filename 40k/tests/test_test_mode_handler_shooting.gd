extends SceneTree

# Verifies the shooting-phase action handlers added to TestModeHandler.gd.
#
# Background: f67b1ee added three multi-peer integration tests
# (test_multiplayer_dice_log_sync, test_multiplayer_save_dialog_retry,
# test_multiplayer_shooting_visuals) that need to drive shooting actions
# across the wire. TestModeHandler previously only handled deployment
# actions; this test pins the shooting handlers — select_shooter,
# assign_target, clear_assignment, confirm_targets,
# complete_shooting_for_unit, use_grenade_stratagem — that the integration
# tests now lean on.
#
# What this test pins:
#   1. Each handler validates its required params up-front and returns a
#      MISSING_PARAMETER error dict with success=false when a param is
#      missing. (Doesn't even need a phase instance to fail closed.)
#   2. Each handler refuses to dispatch if the active phase is not a
#      ShootingPhase, returning INVALID_PHASE.
#   3. Each handler returns the standard {success, result, message} shape
#      when dispatch succeeds.
#   4. Each handler builds the right action payload shape — SELECT_SHOOTER /
#      CLEAR_ASSIGNMENT / CONFIRM_TARGETS / COMPLETE_SHOOTING_FOR_UNIT use
#      `actor_unit_id` (+ payload.weapon_id where relevant); ASSIGN_TARGET
#      nests target/weapon/model_ids inside `payload`; USE_GRENADE_STRATAGEM
#      uses `grenade_unit_id` + `target_unit_id` directly on the action root.
#   5. Real side effects on the phase / GameState happen via the dispatched
#      execute_action call:
#        - clear_assignment: removes the matching entry from pending_assignments
#        - confirm_targets: pending_assignments empties, confirmed_assignments
#          fills (for the simple no-reactive-stratagem path)
#        - complete_shooting_for_unit: active_shooter_id clears, unit added
#          to units_that_shot
#
# Usage: godot --headless --path . -s tests/test_test_mode_handler_shooting.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	# Defer the actual test until autoloads have run their _ready (next idle frame).
	root.connect("ready", Callable(self, "_run_tests"))
	# Belt-and-suspenders: also call after one process tick.
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return  # already ran
	print("\n=== test_test_mode_handler_shooting ===\n")

	_test_handler_registration()
	_test_missing_param_errors()
	_test_invalid_phase_when_no_phase_instance()
	_test_invalid_phase_when_active_phase_not_shooting()
	_test_clear_assignment_dispatches_and_mutates_phase()
	_test_confirm_targets_dispatches_and_mutates_phase()
	_test_complete_shooting_for_unit_dispatches_and_mutates_phase()
	_test_select_shooter_dispatches_with_correct_action_shape()
	_test_assign_target_dispatches_with_correct_payload_shape()
	_test_use_grenade_stratagem_dispatches_with_correct_action_shape()
	_test_handler_return_shape_is_consistent()

	_finish()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _new_shooting_phase():
	"""Build a fresh ShootingPhase with a minimal unit snapshot so get_unit()
	calls in handlers don't blow up on missing data."""
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	# Provide a minimal snapshot — units optional but safer.
	phase.game_state_snapshot = {
		"units": {
			"U_SHOOTER": {"meta": {"name": "Shooter Squad"}, "owner": 1, "models": []},
			"U_TARGET": {"meta": {"name": "Target Squad"}, "owner": 2, "models": []}
		}
	}
	return phase

func _install_phase(phase) -> Dictionary:
	"""Install `phase` as PhaseManager.current_phase_instance, returning a
	dict with the prior phase so it can be restored afterwards."""
	var phase_manager = root.get_node("PhaseManager")
	var prior = phase_manager.current_phase_instance
	phase_manager.add_child(phase)
	phase_manager.current_phase_instance = phase
	return {"prior": prior, "phase_manager": phase_manager, "phase": phase}

func _restore_phase(install_state: Dictionary) -> void:
	install_state.phase_manager.current_phase_instance = install_state.prior
	install_state.phase.queue_free()

# ---------------------------------------------------------------------------
# 1. Handler registration: every shooting action verb must be reachable
#    through TestModeHandler._execute_command. If a verb falls through to
#    UNKNOWN_ACTION, the multi-peer tests will silently skip the action.
# ---------------------------------------------------------------------------
func _test_handler_registration() -> void:
	print("\n-- handler registration --")
	var test_handler = root.get_node("TestModeHandler")
	_check("TestModeHandler autoload present", test_handler != null)
	if test_handler == null:
		return

	# Each handler should be a callable method.
	var expected = [
		"_handle_select_shooter",
		"_handle_assign_target",
		"_handle_clear_assignment",
		"_handle_confirm_targets",
		"_handle_complete_shooting_for_unit",
		"_handle_use_grenade_stratagem",
		"_get_active_shooting_phase"
	]
	for method_name in expected:
		_check("TestModeHandler has %s" % method_name,
			test_handler.has_method(method_name),
			"method missing — multi-peer tests will skip this verb")

# ---------------------------------------------------------------------------
# 2. Missing required params: each handler must return success=false with
#    error == "MISSING_PARAMETER" when its required params are absent. This
#    is fail-closed behavior — the multi-peer tests rely on it to surface
#    contract bugs in the test harness, not the production code.
# ---------------------------------------------------------------------------
func _test_missing_param_errors() -> void:
	print("\n-- missing-param error responses --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	# select_shooter requires actor_unit_id
	var r = await test_handler._execute_command({"action": "select_shooter", "parameters": {}})
	_check("select_shooter missing actor_unit_id → success=false",
		r.get("success") == false,
		"got %s" % str(r))
	_check("select_shooter missing actor_unit_id → error=MISSING_PARAMETER",
		r.get("error") == "MISSING_PARAMETER",
		"got '%s'" % str(r.get("error", "")))

	# assign_target requires actor_unit_id + target_unit_id + weapon_id
	r = await test_handler._execute_command({"action": "assign_target", "parameters": {}})
	_check("assign_target missing actor_unit_id → MISSING_PARAMETER",
		r.get("success") == false and r.get("error") == "MISSING_PARAMETER")
	r = await test_handler._execute_command({"action": "assign_target",
		"parameters": {"actor_unit_id": "U_X"}})
	_check("assign_target missing target_unit_id → MISSING_PARAMETER",
		r.get("success") == false and r.get("error") == "MISSING_PARAMETER")
	r = await test_handler._execute_command({"action": "assign_target",
		"parameters": {"actor_unit_id": "U_X", "target_unit_id": "U_Y"}})
	_check("assign_target missing weapon_id → MISSING_PARAMETER",
		r.get("success") == false and r.get("error") == "MISSING_PARAMETER")

	# clear_assignment requires actor_unit_id
	r = await test_handler._execute_command({"action": "clear_assignment", "parameters": {}})
	_check("clear_assignment missing actor_unit_id → MISSING_PARAMETER",
		r.get("success") == false and r.get("error") == "MISSING_PARAMETER")

	# confirm_targets requires actor_unit_id
	r = await test_handler._execute_command({"action": "confirm_targets", "parameters": {}})
	_check("confirm_targets missing actor_unit_id → MISSING_PARAMETER",
		r.get("success") == false and r.get("error") == "MISSING_PARAMETER")

	# complete_shooting_for_unit requires actor_unit_id
	r = await test_handler._execute_command({"action": "complete_shooting_for_unit", "parameters": {}})
	_check("complete_shooting_for_unit missing actor_unit_id → MISSING_PARAMETER",
		r.get("success") == false and r.get("error") == "MISSING_PARAMETER")

	# use_grenade_stratagem requires actor_unit_id + target_unit_id
	r = await test_handler._execute_command({"action": "use_grenade_stratagem", "parameters": {}})
	_check("use_grenade_stratagem missing actor_unit_id → MISSING_PARAMETER",
		r.get("success") == false and r.get("error") == "MISSING_PARAMETER")
	r = await test_handler._execute_command({"action": "use_grenade_stratagem",
		"parameters": {"actor_unit_id": "U_X"}})
	_check("use_grenade_stratagem missing target_unit_id → MISSING_PARAMETER",
		r.get("success") == false and r.get("error") == "MISSING_PARAMETER")

# ---------------------------------------------------------------------------
# 3. INVALID_PHASE when no phase instance is set on PhaseManager.
#    NO_PHASE_INSTANCE is the more specific code; INVALID_PHASE means the
#    active phase is not ShootingPhase. They're distinct so the multi-peer
#    tests can tell "didn't enter phase yet" from "entered the wrong phase".
# ---------------------------------------------------------------------------
func _test_invalid_phase_when_no_phase_instance() -> void:
	print("\n-- INVALID_PHASE when no phase instance --")
	var test_handler = root.get_node("TestModeHandler")
	var phase_manager = root.get_node("PhaseManager")
	if test_handler == null or phase_manager == null:
		return

	var prior = phase_manager.current_phase_instance
	phase_manager.current_phase_instance = null

	var r = await test_handler._execute_command({
		"action": "select_shooter",
		"parameters": {"actor_unit_id": "U_X"}
	})
	_check("select_shooter with no phase → success=false",
		r.get("success") == false,
		"got %s" % str(r))
	_check("select_shooter with no phase → error=NO_PHASE_INSTANCE",
		r.get("error") == "NO_PHASE_INSTANCE",
		"got '%s'" % str(r.get("error", "")))

	# Restore.
	phase_manager.current_phase_instance = prior

# ---------------------------------------------------------------------------
# 4. INVALID_PHASE when the active phase is something other than ShootingPhase.
#    We install a MovementPhase and assert each shooting handler refuses to
#    dispatch.
# ---------------------------------------------------------------------------
func _test_invalid_phase_when_active_phase_not_shooting() -> void:
	print("\n-- INVALID_PHASE when active phase is not ShootingPhase --")
	var test_handler = root.get_node("TestModeHandler")
	var phase_manager = root.get_node("PhaseManager")
	if test_handler == null or phase_manager == null:
		return

	# Install a MovementPhase.
	var MovementPhaseScript = load("res://phases/MovementPhase.gd")
	if MovementPhaseScript == null:
		_check("MovementPhase.gd loadable", false, "could not load MovementPhase script")
		return
	var movement_phase = MovementPhaseScript.new()
	var prior = phase_manager.current_phase_instance
	phase_manager.add_child(movement_phase)
	phase_manager.current_phase_instance = movement_phase

	var verbs := [
		{"action": "select_shooter", "params": {"actor_unit_id": "U_X"}},
		{"action": "assign_target", "params": {"actor_unit_id": "U_X", "target_unit_id": "U_Y", "weapon_id": "W"}},
		{"action": "clear_assignment", "params": {"actor_unit_id": "U_X", "weapon_id": "W"}},
		{"action": "confirm_targets", "params": {"actor_unit_id": "U_X"}},
		{"action": "complete_shooting_for_unit", "params": {"actor_unit_id": "U_X"}},
		{"action": "use_grenade_stratagem", "params": {"actor_unit_id": "U_X", "target_unit_id": "U_Y"}}
	]
	for v in verbs:
		var r = await test_handler._execute_command({"action": v.action, "parameters": v.params})
		_check("%s on MovementPhase → success=false" % v.action,
			r.get("success") == false,
			"got %s" % str(r))
		_check("%s on MovementPhase → error=INVALID_PHASE" % v.action,
			r.get("error") == "INVALID_PHASE",
			"got '%s'" % str(r.get("error", "")))

	# Cleanup
	phase_manager.current_phase_instance = prior
	movement_phase.queue_free()

# ---------------------------------------------------------------------------
# 5. clear_assignment dispatches and mutates pending_assignments on the phase.
#    _validate_clear_assignment only requires weapon_id non-empty, so this is
#    the easiest happy-path to drive end-to-end without setting up real units.
# ---------------------------------------------------------------------------
func _test_clear_assignment_dispatches_and_mutates_phase() -> void:
	print("\n-- clear_assignment dispatches + mutates phase --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var phase = _new_shooting_phase()
	var install = _install_phase(phase)

	# Pre-populate two pending assignments. The handler should remove the one
	# matching the supplied weapon_id and leave the other.
	phase.active_shooter_id = "U_SHOOTER"
	phase.pending_assignments = [
		{"weapon_id": "W_BOLTGUN", "target_unit_id": "U_TARGET", "model_ids": ["m1"]},
		{"weapon_id": "W_PLASMA",  "target_unit_id": "U_TARGET", "model_ids": ["m2"]}
	]

	var r = await test_handler._execute_command({
		"action": "clear_assignment",
		"parameters": {"actor_unit_id": "U_SHOOTER", "weapon_id": "W_BOLTGUN"}
	})

	_check("clear_assignment success=true",
		r.get("success") == true,
		"got %s" % str(r))
	_check("clear_assignment carries result dict",
		r.has("result") and r.get("result", {}).has("success"),
		"got %s" % str(r.get("result", {})))
	_check("clear_assignment carries message string",
		typeof(r.get("message", "")) == TYPE_STRING and not r.get("message", "").is_empty())
	_check("phase.pending_assignments now has 1 entry (W_PLASMA)",
		phase.pending_assignments.size() == 1
			and phase.pending_assignments[0].get("weapon_id") == "W_PLASMA",
		"got %s" % str(phase.pending_assignments))

	# weapon_id inference: when omitted, handler should fall back to the most
	# recent pending_assignments entry's weapon_id. The remaining one is
	# W_PLASMA, so a no-weapon-id call should clear it.
	r = await test_handler._execute_command({
		"action": "clear_assignment",
		"parameters": {"actor_unit_id": "U_SHOOTER"}
	})
	_check("clear_assignment without weapon_id falls back to last pending",
		r.get("success") == true and phase.pending_assignments.is_empty(),
		"got %s, pending=%s" % [str(r), str(phase.pending_assignments)])

	# After all are cleared, a no-weapon-id call should fail-closed.
	r = await test_handler._execute_command({
		"action": "clear_assignment",
		"parameters": {"actor_unit_id": "U_SHOOTER"}
	})
	_check("clear_assignment with no pending + no weapon_id → MISSING_PARAMETER",
		r.get("success") == false and r.get("error") == "MISSING_PARAMETER",
		"got %s" % str(r))

	_restore_phase(install)

# ---------------------------------------------------------------------------
# 6. confirm_targets dispatches and mutates phase state.
#    _validate_confirm_targets requires pending_assignments non-empty, then
#    _process_confirm_targets merges/moves them into confirmed_assignments
#    and clears pending. We install pending state directly to skip the
#    upstream validation.
# ---------------------------------------------------------------------------
func _test_confirm_targets_dispatches_and_mutates_phase() -> void:
	print("\n-- confirm_targets dispatches + mutates phase --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var phase = _new_shooting_phase()
	var install = _install_phase(phase)

	phase.active_shooter_id = "U_SHOOTER"
	phase.pending_assignments = [
		{"weapon_id": "W_BOLTGUN", "target_unit_id": "U_TARGET", "model_ids": ["m1"]}
	]
	# Empty confirmed at start.
	_check("phase.confirmed_assignments starts empty",
		phase.confirmed_assignments.is_empty())

	var r = await test_handler._execute_command({
		"action": "confirm_targets",
		"parameters": {"actor_unit_id": "U_SHOOTER"}
	})
	_check("confirm_targets dispatched (handler returned a dict)",
		r != null and r.has("success"))
	_check("confirm_targets carries result dict",
		r.has("result") and r.get("result", {}).has("success"))

	# After dispatch, pending should be empty and confirmed should contain
	# the moved-over assignment. (This holds even if the broader process
	# returned a "reactive stratagem opportunity" branch — confirmed gets
	# populated before that branch is checked.)
	_check("phase.pending_assignments cleared after confirm",
		phase.pending_assignments.is_empty(),
		"got %s" % str(phase.pending_assignments))
	_check("phase.confirmed_assignments has at least 1 entry after confirm",
		phase.confirmed_assignments.size() >= 1,
		"got %s" % str(phase.confirmed_assignments))

	# Empty-pending validation still fail-closed.
	phase.pending_assignments = []
	phase.confirmed_assignments = []
	r = await test_handler._execute_command({
		"action": "confirm_targets",
		"parameters": {"actor_unit_id": "U_SHOOTER"}
	})
	_check("confirm_targets with no pending → handler returns success=false from phase",
		r.get("success") == false,
		"got %s" % str(r))

	_restore_phase(install)

# ---------------------------------------------------------------------------
# 7. complete_shooting_for_unit dispatches and mutates phase state.
#    Validator requires action.actor_unit_id == phase.active_shooter_id.
#    Process clears active_shooter_id and appends to units_that_shot.
# ---------------------------------------------------------------------------
func _test_complete_shooting_for_unit_dispatches_and_mutates_phase() -> void:
	print("\n-- complete_shooting_for_unit dispatches + mutates phase --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var phase = _new_shooting_phase()
	var install = _install_phase(phase)

	phase.active_shooter_id = "U_SHOOTER"
	phase.units_that_shot = []

	var r = await test_handler._execute_command({
		"action": "complete_shooting_for_unit",
		"parameters": {"actor_unit_id": "U_SHOOTER"}
	})

	_check("complete_shooting_for_unit success=true",
		r.get("success") == true,
		"got %s" % str(r))
	_check("phase.active_shooter_id cleared",
		phase.active_shooter_id == "",
		"got '%s'" % str(phase.active_shooter_id))
	_check("phase.units_that_shot now contains U_SHOOTER",
		"U_SHOOTER" in phase.units_that_shot,
		"got %s" % str(phase.units_that_shot))

	# Mismatched actor (validator should reject).
	phase.active_shooter_id = "U_OTHER"
	r = await test_handler._execute_command({
		"action": "complete_shooting_for_unit",
		"parameters": {"actor_unit_id": "U_SHOOTER"}
	})
	_check("complete_shooting_for_unit with wrong actor → success=false",
		r.get("success") == false,
		"got %s" % str(r))
	_check("U_OTHER NOT marked as having shot when actor mismatch",
		"U_OTHER" not in phase.units_that_shot,
		"got %s" % str(phase.units_that_shot))

	_restore_phase(install)

# ---------------------------------------------------------------------------
# 8. select_shooter dispatches the right action shape.
#    The validator is heavyweight — requires real unit data, eligible
#    targets, etc. — so the happy-path will fail validation here. What we
#    pin is that the handler reaches phase.execute_action with the correct
#    type/actor_unit_id keys (no "actor_unit_id missing" or "Unknown action
#    type" errors out of the validator).
# ---------------------------------------------------------------------------
func _test_select_shooter_dispatches_with_correct_action_shape() -> void:
	print("\n-- select_shooter dispatches with correct action shape --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var phase = _new_shooting_phase()
	var install = _install_phase(phase)

	# Hook validate_action via signal to capture the action shape.
	var captured_actions: Array = []
	var capture := func(action):
		captured_actions.append(action)
	phase.action_taken.connect(capture)

	# Synthesize a unit that _can_unit_shoot would accept but
	# _has_eligible_targets would reject — simplest happy-validate-fail-process
	# path. Doesn't matter; we just need to verify the action dict reaches
	# validate_action with the correct shape. We assert by inspecting what
	# the validator complains about. If the action shape is wrong we'd see
	# "Missing actor_unit_id" or "Unknown action type"; the correct shape
	# will surface "Unit not found" / "Unit cannot shoot" / "no eligible
	# targets" depending on data.
	var r = await test_handler._execute_command({
		"action": "select_shooter",
		"parameters": {"actor_unit_id": "U_TOTALLY_NEW_UNIT"}
	})
	_check("select_shooter dispatched (handler returned dict with success key)",
		r != null and r.has("success"))
	# The validator should reject with "Unit not found" — meaning the handler
	# did pass actor_unit_id through correctly. If we'd built the action
	# wrongly, we'd get "Missing actor_unit_id" instead.
	var errors_str = str(r.get("result", {}).get("errors", []))
	_check("select_shooter validator saw the actor_unit_id (no 'Missing actor_unit_id' error)",
		not errors_str.contains("Missing actor_unit_id"),
		"errors: %s" % errors_str)
	_check("select_shooter validator did not return 'Unknown action type'",
		not errors_str.contains("Unknown action type"),
		"errors: %s" % errors_str)

	phase.action_taken.disconnect(capture)
	_restore_phase(install)

# ---------------------------------------------------------------------------
# 9. assign_target dispatches with payload nested under "payload".
#    _validate_assign_target reads action.payload.weapon_id /
#    payload.target_unit_id / payload.model_ids — if the handler doesn't nest
#    these, the validator will return "Missing weapon_id or target_unit_id".
#    That's the failure mode this test pins against.
# ---------------------------------------------------------------------------
func _test_assign_target_dispatches_with_correct_payload_shape() -> void:
	print("\n-- assign_target dispatches with correct payload shape --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var phase = _new_shooting_phase()
	var install = _install_phase(phase)
	phase.active_shooter_id = "U_SHOOTER"  # required by _validate_assign_target

	var r = await test_handler._execute_command({
		"action": "assign_target",
		"parameters": {
			"actor_unit_id": "U_SHOOTER",
			"target_unit_id": "U_TARGET",
			"weapon_id": "W_BOLTGUN",
			"model_ids": ["m1"]
		}
	})

	_check("assign_target dispatched (handler returned dict)",
		r != null and r.has("success"))
	# Even though the deeper RulesEngine.validate_shoot likely rejects (no
	# real unit data), the early "Missing weapon_id or target_unit_id" check
	# in _validate_assign_target should pass because the handler nested the
	# payload correctly.
	var errors_str = str(r.get("result", {}).get("errors", []))
	_check("assign_target payload reached validator with weapon_id+target_unit_id",
		not errors_str.contains("Missing weapon_id or target_unit_id"),
		"errors: %s -- payload may not be nested correctly in handler" % errors_str)
	_check("assign_target validator did not fail with 'No shooter selected'",
		not errors_str.contains("No shooter selected"),
		"errors: %s" % errors_str)
	_check("assign_target validator did not return 'Unknown action type'",
		not errors_str.contains("Unknown action type"),
		"errors: %s" % errors_str)

	_restore_phase(install)

# ---------------------------------------------------------------------------
# 10. use_grenade_stratagem dispatches with grenade_unit_id + target_unit_id
#     on the action root (NOT inside payload). _validate_use_grenade_stratagem
#     reads action.grenade_unit_id and action.target_unit_id directly. If the
#     handler routes them under "payload" instead, we'd get "Missing
#     grenade_unit_id" — that's the failure mode this test pins against.
# ---------------------------------------------------------------------------
func _test_use_grenade_stratagem_dispatches_with_correct_action_shape() -> void:
	print("\n-- use_grenade_stratagem dispatches with correct action shape --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var phase = _new_shooting_phase()
	var install = _install_phase(phase)

	var r = await test_handler._execute_command({
		"action": "use_grenade_stratagem",
		"parameters": {
			"actor_unit_id": "U_SHOOTER",
			"target_unit_id": "U_TARGET"
		}
	})

	_check("use_grenade_stratagem dispatched (handler returned dict)",
		r != null and r.has("success"))
	var errors_str = str(r.get("result", {}).get("errors", []))
	_check("use_grenade_stratagem reached validator with grenade_unit_id",
		not errors_str.contains("Missing grenade_unit_id"),
		"errors: %s -- handler may have nested grenade_unit_id under payload" % errors_str)
	_check("use_grenade_stratagem reached validator with target_unit_id",
		not errors_str.contains("Missing target_unit_id"),
		"errors: %s" % errors_str)
	_check("use_grenade_stratagem validator did not return 'Unknown action type'",
		not errors_str.contains("Unknown action type"),
		"errors: %s" % errors_str)

	_restore_phase(install)

# ---------------------------------------------------------------------------
# 11. Handler return-shape contract: every successful handler returns a
#     Dictionary with success/result/message keys. The multi-peer tests'
#     assertion blocks rely on this shape — drift breaks them silently.
# ---------------------------------------------------------------------------
func _test_handler_return_shape_is_consistent() -> void:
	print("\n-- handler return shape is {success, result, message} --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var phase = _new_shooting_phase()
	var install = _install_phase(phase)
	phase.active_shooter_id = "U_SHOOTER"
	phase.pending_assignments = [
		{"weapon_id": "W_BOLTGUN", "target_unit_id": "U_TARGET", "model_ids": ["m1"]}
	]

	var r = await test_handler._execute_command({
		"action": "clear_assignment",
		"parameters": {"actor_unit_id": "U_SHOOTER", "weapon_id": "W_BOLTGUN"}
	})

	_check("return dict has success key (Bool)",
		r.has("success") and typeof(r.get("success")) == TYPE_BOOL,
		"got type %d" % typeof(r.get("success")))
	_check("return dict has result key (Dictionary)",
		r.has("result") and typeof(r.get("result")) == TYPE_DICTIONARY,
		"got type %d" % typeof(r.get("result")))
	_check("return dict has message key (String)",
		r.has("message") and typeof(r.get("message")) == TYPE_STRING,
		"got type %d" % typeof(r.get("message")))
	_check("message is non-empty",
		not r.get("message", "").is_empty(),
		"got '%s'" % str(r.get("message", "")))

	_restore_phase(install)

# ---------------------------------------------------------------------------
# Finalize
# ---------------------------------------------------------------------------
func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

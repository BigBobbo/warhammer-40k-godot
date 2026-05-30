extends SceneTree

# Verifies the transition_to_phase action handler added to TestModeHandler.gd.
#
# Background: peers spawned with --auto-host / --auto-join boot into
# FORMATIONS phase (the real-game start phase per 10e rules), not
# DEPLOYMENT. The multi-peer integration tests in
# `tests/integration/test_multiplayer_deployment.gd` and
# `tests/integration/test_multiplayer_network.gd` need to drive deployment
# starting from FORMATIONS, but the existing TestModeHandler action verbs
# only cover deployment/shooting actions — there was no way for an
# integration test to advance the host past FORMATIONS via the same
# command-file IPC. This test pins the new transition_to_phase handler
# that bridges that gap.
#
# What this test pins:
#   1. The "transition_to_phase" verb is reachable through
#      TestModeHandler._execute_command (no UNKNOWN_ACTION fall-through).
#   2. Missing-param fail-closed: success=false + error=MISSING_PARAMETER
#      when the `phase` parameter is absent.
#   3. Invalid param fail-closed: success=false + error=INVALID_PARAMETER
#      when `phase` is out of range (negative, too large, or an unknown
#      string name).
#   4. Both int and string accept the same enum values:
#        params={"phase": 1}  -> DEPLOYMENT (Phase enum value 1)
#        params={"phase": "DEPLOYMENT"} -> same outcome
#        params={"phase": "deployment"} -> same outcome (case-insensitive)
#   5. PHASE_MANAGER_NOT_FOUND when /root/PhaseManager isn't reachable.
#      (Skipped via guard — the autoload is always present in this harness.)
#   6. Successful dispatch returns {success, message, data} where data
#      carries from_phase / requested_phase / resolved_phase ints, and
#      PhaseManager.transition_to_phase was actually invoked.
#   7. Return-shape contract: every successful response has success/message
#      keys at minimum (data is added on success).
#
# Usage: godot --headless --path . -s tests/test_test_mode_handler_transition.gd

# We deliberately do NOT preload GameState at the top of the file. Doing
# so triggers the autoload preload chain (GameState → DeploymentZoneData →
# Measurement), which compile-fails when this script is loaded BEFORE the
# Measurement autoload is set up. We resolve the Phase enum on-demand from
# the live /root/GameState autoload after the SceneTree is ready.

var passed := 0
var failed := 0
# Guard against re-entrance. _run_tests can be called more than once if
# `root.ready` fires multiple times (it does, in some godot 4.6 setups).
# Without this flag, two invocations interleave, one finishes early after
# 8 tests, and quit(0) tears down the SceneTree mid-way through the
# second invocation's tests, leaving the rest unverified.
var _running := false
var _ran := false

# Phase enum values from GameState.gd. Mirrored here to avoid the preload
# chain. Keep in sync with autoloads/GameState.gd:7.
#   FORMATIONS=0, DEPLOYMENT=1, REDEPLOYMENT=2, ROLL_OFF=3, SCOUT=4,
#   SCOUT_MOVES=5, COMMAND=6, MOVEMENT=7, SHOOTING=8, CHARGE=9, FIGHT=10,
#   SCORING=11, MORALE=12
const PHASE_FORMATIONS := 0
const PHASE_DEPLOYMENT := 1

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	# Defer until autoloads have run their _ready (next idle frame). We
	# rely on `root.ready` alone; adding a timer fallback (as in
	# test_test_mode_handler_shooting.gd) causes _run_tests to fire twice
	# concurrently on this test because our int/string-dispatch tests
	# yield via `await` long enough for the timer to fire mid-run.
	root.connect("ready", Callable(self, "_run_tests"))

func _run_tests():
	if _running or _ran:
		return  # another invocation is already in flight or already finished
	_running = true
	print("\n=== test_test_mode_handler_transition ===\n")

	# Each test function awaits internally on _execute_command, which itself
	# awaits get_tree().process_frame in _handle_transition_to_phase. We
	# MUST await each call here, otherwise all tests start concurrently and
	# the first one to finish races into _finish() before the rest complete
	# (or — if root.ready fires twice — the two invocations interleave and
	# clobber each other's state). Awaiting serializes them.
	await _test_handler_registration()
	await _test_missing_param_error()
	await _test_invalid_param_errors()
	await _test_int_param_dispatches_and_advances_phase()
	await _test_string_param_dispatches_and_advances_phase()
	await _test_string_param_is_case_insensitive()
	await _test_response_shape_on_success()

	_finish()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _capture_phase_manager() -> Dictionary:
	"""Capture PhaseManager state so each test can run from a known baseline.

	The autoload survives across tests, so without this we'd see the
	previous test's residual phase / instance leaking in. Returns a dict
	with the prior phase int + prior phase instance, suitable for passing
	back to _restore_phase_manager().
	"""
	var phase_manager = root.get_node("PhaseManager")
	var gs = root.get_node("GameState")
	return {
		"phase_manager": phase_manager,
		"game_state": gs,
		"prior_phase": gs.get_current_phase(),
		"prior_instance": phase_manager.current_phase_instance
	}

func _restore_phase_manager(state: Dictionary) -> void:
	"""Restore PhaseManager + GameState to the state captured above.

	NOTE: we do NOT try to re-attach state["prior_instance"]. PhaseManager's
	transition_to_phase calls queue_free() on the existing instance, which
	makes the captured ref dangling by the time we get back here — a
	straight `current_phase_instance = state["prior_instance"]` would
	trigger 'Invalid assignment ... value of type previously freed'.
	Setting current_phase_instance = null is safe; PhaseManager will
	construct a fresh instance the next time anything calls
	transition_to_phase.
	"""
	var phase_manager = state["phase_manager"]
	# Tear down whatever phase the test left in place. By this point
	# `current_phase_instance` is the test's transient phase (the one
	# transition_to_phase built), distinct from any prior captured one.
	if phase_manager.current_phase_instance != null \
			and is_instance_valid(phase_manager.current_phase_instance):
		phase_manager.current_phase_instance.queue_free()
	phase_manager.current_phase_instance = null
	# Restore the GameState phase int so cross-test residue doesn't leak.
	# (set_phase only writes state["meta"]["phase"], no signals/handlers fire.)
	state["game_state"].set_phase(state["prior_phase"])

# ---------------------------------------------------------------------------
# 1. Handler registration: the new verb must be reachable through
#    _execute_command. Missing match arm → UNKNOWN_ACTION → integration
#    tests would silently no-op the advance, leaving peers stuck in
#    FORMATIONS. That's the exact failure mode this test pins against.
# ---------------------------------------------------------------------------
func _test_handler_registration() -> void:
	print("\n-- handler registration --")
	var test_handler = root.get_node("TestModeHandler")
	_check("TestModeHandler autoload present", test_handler != null)
	if test_handler == null:
		return

	_check("TestModeHandler has _handle_transition_to_phase",
		test_handler.has_method("_handle_transition_to_phase"),
		"method missing — integration tests will fall through to UNKNOWN_ACTION")

	# Dispatch via _execute_command to confirm the match arm in
	# _execute_command actually routes the verb. A missing arm would
	# return error=UNKNOWN_ACTION; a present-but-broken arm would return
	# something else.
	var r = await test_handler._execute_command({
		"action": "transition_to_phase",
		"parameters": {"phase": PHASE_DEPLOYMENT}
	})
	_check("transition_to_phase verb is routed (not UNKNOWN_ACTION)",
		r.get("error", "") != "UNKNOWN_ACTION",
		"got error '%s'" % str(r.get("error", "")))

# ---------------------------------------------------------------------------
# 2. Missing required param (`phase`): fail-closed with success=false +
#    error=MISSING_PARAMETER. Without this, an integration test that
#    typo'd the param name would silently advance to phase 0 (FORMATIONS)
#    and re-trigger the original boot-phase mismatch.
# ---------------------------------------------------------------------------
func _test_missing_param_error() -> void:
	print("\n-- missing-param error --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var r = await test_handler._execute_command({
		"action": "transition_to_phase",
		"parameters": {}
	})
	_check("transition_to_phase missing phase → success=false",
		r.get("success") == false,
		"got %s" % str(r))
	_check("transition_to_phase missing phase → error=MISSING_PARAMETER",
		r.get("error") == "MISSING_PARAMETER",
		"got '%s'" % str(r.get("error", "")))

# ---------------------------------------------------------------------------
# 3. Invalid param value: out-of-range int, unknown string name. Both
#    must fail-closed with INVALID_PARAMETER. Negative / too-large /
#    typo'd phase names should never silently no-op or transition
#    to a default phase.
# ---------------------------------------------------------------------------
func _test_invalid_param_errors() -> void:
	print("\n-- invalid-param error responses --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	# 14 phases as of this writing (FORMATIONS..MORALE, FIRST_TURN_ROLLOFF).
	# Keep in sync with autoloads/GameState.gd:7 — adding a phase there means
	# bumping this. The first out-of-range index is therefore 14.
	var phase_count = 14

	# Negative int.
	var r = await test_handler._execute_command({
		"action": "transition_to_phase",
		"parameters": {"phase": -1}
	})
	_check("transition_to_phase phase=-1 → success=false",
		r.get("success") == false,
		"got %s" % str(r))
	_check("transition_to_phase phase=-1 → error=INVALID_PARAMETER",
		r.get("error") == "INVALID_PARAMETER",
		"got '%s'" % str(r.get("error", "")))

	# Out-of-range int (one past last valid index).
	r = await test_handler._execute_command({
		"action": "transition_to_phase",
		"parameters": {"phase": phase_count}
	})
	_check("transition_to_phase phase=%d (out of range) → INVALID_PARAMETER" % phase_count,
		r.get("success") == false and r.get("error") == "INVALID_PARAMETER",
		"got %s" % str(r))

	# Unknown string name.
	r = await test_handler._execute_command({
		"action": "transition_to_phase",
		"parameters": {"phase": "TOTALLY_NOT_A_PHASE"}
	})
	_check("transition_to_phase phase='TOTALLY_NOT_A_PHASE' → INVALID_PARAMETER",
		r.get("success") == false and r.get("error") == "INVALID_PARAMETER",
		"got %s" % str(r))

# ---------------------------------------------------------------------------
# 4. Int param happy-path: passing PHASE_DEPLOYMENT (== 1)
#    should drive PhaseManager.transition_to_phase(1). After dispatch,
#    GameState.get_current_phase() should return DEPLOYMENT.
# ---------------------------------------------------------------------------
func _test_int_param_dispatches_and_advances_phase() -> void:
	print("\n-- int param dispatches PhaseManager.transition_to_phase --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var saved = _capture_phase_manager()
	# Force a known starting phase so we can verify the transition actually
	# moved us. FORMATIONS (0) → DEPLOYMENT (1) is the real production
	# scenario this handler exists to support.
	saved["game_state"].set_phase(PHASE_FORMATIONS)

	var r = await test_handler._execute_command({
		"action": "transition_to_phase",
		"parameters": {"phase": PHASE_DEPLOYMENT}
	})
	_check("transition_to_phase int=DEPLOYMENT → success=true",
		r.get("success") == true,
		"got %s" % str(r))

	# GameState should now report DEPLOYMENT.
	var current_phase = saved["game_state"].get_current_phase()
	_check("GameState.get_current_phase() == DEPLOYMENT after dispatch",
		current_phase == PHASE_DEPLOYMENT,
		"got phase %d (expected %d)" % [current_phase, PHASE_DEPLOYMENT])

	# Response data should carry the resolved phase int.
	var data = r.get("data", {})
	_check("response.data.requested_phase matches input",
		data.get("requested_phase", -1) == PHASE_DEPLOYMENT)
	_check("response.data.resolved_phase matches GameState.get_current_phase()",
		data.get("resolved_phase", -1) == current_phase)

	_restore_phase_manager(saved)

# ---------------------------------------------------------------------------
# 5. String param happy-path: case-sensitive enum-name input. The
#    integration tests can use either form — int is more compact, string
#    is more readable in test code.
# ---------------------------------------------------------------------------
func _test_string_param_dispatches_and_advances_phase() -> void:
	print("\n-- string param 'DEPLOYMENT' dispatches PhaseManager --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var saved = _capture_phase_manager()
	saved["game_state"].set_phase(PHASE_FORMATIONS)

	var r = await test_handler._execute_command({
		"action": "transition_to_phase",
		"parameters": {"phase": "DEPLOYMENT"}
	})
	_check("transition_to_phase phase='DEPLOYMENT' → success=true",
		r.get("success") == true,
		"got %s" % str(r))

	var current_phase = saved["game_state"].get_current_phase()
	_check("GameState.get_current_phase() == DEPLOYMENT after string dispatch",
		current_phase == PHASE_DEPLOYMENT,
		"got phase %d" % current_phase)

	_restore_phase_manager(saved)

# ---------------------------------------------------------------------------
# 6. String param is case-insensitive: 'deployment' / 'Deployment' /
#    'DEPLOYMENT' should all work. This guards against test code
#    accidentally passing the lowercase phase name from a get_game_state
#    response (which returns "Deployment" with capital D).
# ---------------------------------------------------------------------------
func _test_string_param_is_case_insensitive() -> void:
	print("\n-- string param is case-insensitive --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	for name in ["deployment", "Deployment", "DEPLOYMENT"]:
		var saved = _capture_phase_manager()
		saved["game_state"].set_phase(PHASE_FORMATIONS)

		var r = await test_handler._execute_command({
			"action": "transition_to_phase",
			"parameters": {"phase": name}
		})
		_check("transition_to_phase phase='%s' → success=true" % name,
			r.get("success") == true,
			"got %s" % str(r))
		_check("transition_to_phase phase='%s' → resolved DEPLOYMENT" % name,
			saved["game_state"].get_current_phase() == PHASE_DEPLOYMENT,
			"got phase %d" % saved["game_state"].get_current_phase())

		_restore_phase_manager(saved)

# ---------------------------------------------------------------------------
# 7. Response shape contract: integration-test assertion blocks rely on
#    {success, message, data}. Drift breaks the multi-peer suite silently.
# ---------------------------------------------------------------------------
func _test_response_shape_on_success() -> void:
	print("\n-- success response shape is {success, message, data} --")
	var test_handler = root.get_node("TestModeHandler")
	if test_handler == null:
		return

	var saved = _capture_phase_manager()
	saved["game_state"].set_phase(PHASE_FORMATIONS)

	var r = await test_handler._execute_command({
		"action": "transition_to_phase",
		"parameters": {"phase": PHASE_DEPLOYMENT}
	})

	_check("response has success key (Bool)",
		r.has("success") and typeof(r.get("success")) == TYPE_BOOL,
		"got type %d" % typeof(r.get("success")))
	_check("response has message key (String)",
		r.has("message") and typeof(r.get("message")) == TYPE_STRING,
		"got type %d" % typeof(r.get("message")))
	_check("response.message is non-empty",
		not r.get("message", "").is_empty(),
		"got '%s'" % str(r.get("message", "")))
	_check("response has data key (Dictionary) on success",
		r.has("data") and typeof(r.get("data")) == TYPE_DICTIONARY,
		"got type %d" % typeof(r.get("data")))
	_check("response.data has from_phase / requested_phase / resolved_phase",
		r.get("data", {}).has("from_phase")
			and r.get("data", {}).has("requested_phase")
			and r.get("data", {}).has("resolved_phase"),
		"data: %s" % str(r.get("data", {})))

	_restore_phase_manager(saved)

# ---------------------------------------------------------------------------
# Finalize
# ---------------------------------------------------------------------------
func _finish():
	_ran = true
	_running = false
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

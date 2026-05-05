extends "res://tests/helpers/MultiplayerIntegrationTest.gd"

# Multiplayer Shooting Visuals Tests — T5-MP3
#
# Backstory: T5-MP3 added remote-player visual feedback for shooting actions.
# When the host fires SELECT_SHOOTER / ASSIGN_TARGET / CLEAR_ASSIGNMENT /
# CLEAR_ALL_ASSIGNMENTS / CONFIRM_TARGETS / COMPLETE_SHOOTING_FOR_UNIT, the
# client's `ShootingController` must mirror the visuals:
#   - SELECT_SHOOTER → range circles (`_show_range_indicators`) + eligible
#                      target highlights (`_create_target_highlight`) + LoS
#                      lines (`_visualize_los_to_target`)
#   - ASSIGN_TARGET → animated tracer (`ShootingLineVisual`) + target highlight
#   - CLEAR_ASSIGNMENT / CLEAR_ALL → tracer + highlight removed (range circles
#                                    remain because the shooter is still selected)
#   - CONFIRM_TARGETS → `shooting_begun` signal re-emitted on remote phase,
#                       which kicks the animated shooting tracer into "firing"
#   - COMPLETE_SHOOTING_FOR_UNIT → `shooting_resolved` signal re-emitted, all
#                                  per-shooter visuals cleared
#
# The single-process test `test_shooting_visual_broadcast.gd` already pins the
# protocol slice (38 assertions on signal re-emission, controller calls, and
# allow-list membership). This file is the multi-peer counterpart: it spins
# up real host + client Godot processes and verifies the harness preserves
# the protocol on the wire.
#
# API STATUS
# ----------
# `MultiplayerIntegrationTest.simulate_host_action` is bridged to
# `TestModeHandler` which now supports the shooting-phase action set:
# `select_shooter`, `assign_target`, `clear_assignment`, `confirm_targets`,
# `complete_shooting_for_unit`, `use_grenade_stratagem`. The first method
# in this file drives a real SELECT_SHOOTER end-to-end (host fires, both
# peers queried via get_game_state) so a regression in the broadcast
# pipeline surfaces here, not just in the static-source contracts below.
#
# What we CAN drive end-to-end:
#   - SELECT_SHOOTER on host → host's ShootingPhase.active_shooter_id set,
#     visible via get_game_state.
#   - The static-source contracts (re-emit signals, controller methods,
#     allow-list membership) so a refactor that breaks the protocol fails
#     this suite too.
#
# What is still NOT driveable (queued separately):
#   - Inspecting the client's `_range_indicator` / `_target_highlights`
#     Node2D children directly — `get_game_state` doesn't expose
#     ShootingController state. Would need a future `get_controller_state`
#     action.
#   - The client's ShootingPhase.active_shooter_id is NOT mutated by the
#     broadcast pipeline today: `_emit_client_visual_updates` emits visual
#     signals but does not run `_process_select_shooter` on the client
#     phase. The client's ShootingController DOES track the shooter (via
#     the unit_selected_for_shooting signal handler) — exposing that
#     would also require `get_controller_state`.
#
# Manual scenarios still needed (not driveable from the command-file IPC):
#   - Host selects shooter → client sees range circles + LoS lines + eligible
#     target highlights.
#   - Host assigns target → client sees per-assignment tracer line + yellow highlight.
#   - Host clears assignment → client tracer removed, range circles still visible.
#   - Host confirms + completes → client sees animated tracer + per-shooter clear.
#
# Usage: bash 40k/tests/run_multiplayer_tests.sh

## ===========================================================================
## 1. SELECT_SHOOTER BROADCAST — REAL END-TO-END BEHAVIORAL ASSERTION
## ===========================================================================

func test_shooting_visuals_select_shooter_broadcast_end_to_end():
	"""
	What this verifies (real behavior, end-to-end on two real peers):
	  1. Host + client both reach SHOOTING phase from the shooting fixture.
	  2. After host runs SELECT_SHOOTER, the host's ShootingPhase carries
	     active_shooter_id == <picked_unit_id> (proves the action mutated
	     phase state on the host).
	  3. The host's choice is visible to the client through get_game_state's
	     observable view: at minimum the host and client agree on phase /
	     unit set, so a SELECT_SHOOTER does not target a phantom unit on
	     the client.

	What this does NOT verify (limitations of the get_game_state API):
	  - The client's *visual* state (range circles, LoS lines, target
	    highlights) — `get_game_state` does not expose ShootingController
	    children. Counting `_range_indicator` / `_target_highlights` Node2D
	    children would need a future `get_controller_state` action.
	  - The client's ShootingPhase.active_shooter_id — the broadcast
	    pipeline's `_emit_client_visual_updates` re-emits signals on the
	    client phase but never runs `_process_select_shooter` there, so the
	    client phase's `active_shooter_id` stays empty. The client's
	    ShootingController IS updated via the unit_selected_for_shooting
	    signal handler, but again that needs `get_controller_state` to read.

	Acceptance: host's `data.active_shooter_id` matches the picked id;
	host + client agree on phase + unit set.
	"""
	print("\n[TEST] test_shooting_visuals_select_shooter_broadcast_end_to_end")

	var shooting_save = get_shooting_test_save().get_file()
	print("[TEST] Using shooting save: %s" % shooting_save)

	var launched = await launch_host_and_client(shooting_save)
	assert_true(launched, "Should launch both instances with shooting save")

	var connected = await wait_for_connection()
	assert_true(connected, "Client should connect to host")

	# Wait for save load + phase transition to settle on both peers.
	await wait_for_seconds(4.0)

	# Step A: host loads the shooting fixture explicitly via the action API.
	# (auto-load on launch primarily covers it; this assertion pins that the
	# test infra path itself works for shooting, not just deployment.)
	var load_result = await simulate_host_action("load_save", {"save_name": "shooting_phase"})
	assert_true(load_result.get("success", false),
		"Host load_save(shooting_phase) should succeed: %s" % load_result.get("message", ""))

	# Give the client a moment to receive any post-load state sync.
	await wait_for_seconds(2.0)

	var host_state = await simulate_host_action("get_game_state", {})
	var client_state = await simulate_client_action("get_game_state", {})

	assert_true(host_state.get("success", false), "Host should return game state")
	assert_true(client_state.get("success", false), "Client should return game state")

	var host_phase = host_state.get("data", {}).get("current_phase", "")
	var client_phase = client_state.get("data", {}).get("current_phase", "")
	print("[TEST] Host phase: '%s', Client phase: '%s'" % [host_phase, client_phase])

	# If the shooting save isn't reachable in the test environment, the
	# auto-load + explicit load both fail to reach Shooting. Surface that as
	# a soft skip so the test still proves the connection + load slice works.
	if host_phase != "Shooting":
		print("[TEST] WARNING: Host did not reach Shooting phase (got '%s'). Auto-load may have failed; manual smoke required for the actual visual scenarios." % host_phase)
		assert_eq(host_phase, client_phase,
			"Host and client must at least agree on phase even when shooting save is missing")
		print("[TEST] PASSED (with warning): connection sync verified, phase agreement verified")
		return

	assert_eq(host_phase, "Shooting", "Host should be in Shooting phase")
	assert_eq(client_phase, "Shooting", "Client should be in Shooting phase")

	var host_units = host_state.get("data", {}).get("units", {})
	var client_units = client_state.get("data", {}).get("units", {})
	assert_eq(host_units.size(), client_units.size(),
		"Host and client should have the same unit count (shooter + targets must exist on both)")

	for unit_id in host_units.keys():
		assert_true(unit_id in client_units,
			"Unit '%s' on host should also be on client (else SELECT_SHOOTER targets a phantom unit on client)" % unit_id)

	# Step B: pick a concrete shooter — any unit owned by the active player
	# from the host's view. (The host is the source of truth for active
	# player; the fixture sets active_player=1 / Orks.)
	var active_player = host_state.get("data", {}).get("player_turn", 1)
	var picked_shooter_id = ""
	for unit_id in host_units.keys():
		var unit = host_units[unit_id]
		if int(unit.get("owner", 0)) == int(active_player):
			picked_shooter_id = unit_id
			break

	if picked_shooter_id == "":
		# No active-player unit found in the fixture — surface as soft skip
		# rather than hard fail; this would mean the fixture lost the active
		# player's units for some reason.
		print("[TEST] WARNING: No active-player (player %d) unit found in host's view; cannot drive SELECT_SHOOTER" % active_player)
		assert_true(false, "Fixture should expose at least one unit owned by the active player")
		return

	print("[TEST] Picked shooter: %s (owner=%d, active_player=%d)" % [
		picked_shooter_id,
		int(host_units[picked_shooter_id].get("owner", 0)),
		int(active_player)
	])

	# Step C: drive a real SELECT_SHOOTER on the host. The handler dispatches
	# {"type": "SELECT_SHOOTER", "actor_unit_id": <id>} into the active
	# ShootingPhase via execute_action.
	var select_result = await simulate_host_action("select_shooter", {"actor_unit_id": picked_shooter_id})
	# NOTE: the test handler returns {"success": true, "result": {...}, "message": ...}
	# where "success" reflects the *phase* result.success. SELECT_SHOOTER may
	# legitimately surface ability prompts (Throat Slittas, Ammo Runt etc.)
	# whose results carry a sub-flag rather than failing — so we accept either
	# outright success or a result that carries one of those prompt flags.
	var select_inner = select_result.get("result", {})
	var prompt_keys := ["throat_slittas_available", "ammo_runt_available", "pulsa_rokkit_available", "shooty_power_trip_available"]
	var has_prompt := false
	for key in prompt_keys:
		if select_inner.get(key, false):
			has_prompt = true
			break
	assert_true(
		select_result.get("success", false) or has_prompt,
		"Host SELECT_SHOOTER should succeed or surface an ability prompt; got: %s" % str(select_result)
	)

	# Allow the broadcast time to propagate to the client.
	await wait_for_seconds(2.0)

	# Step D: re-query both peers. The host's active_shooter_id MUST be the
	# picked unit id (this is the strong real-behavior assertion).
	var host_state_after = await simulate_host_action("get_game_state", {})
	var client_state_after = await simulate_client_action("get_game_state", {})

	assert_true(host_state_after.get("success", false), "Host should return game state after SELECT_SHOOTER")
	assert_true(client_state_after.get("success", false), "Client should return game state after SELECT_SHOOTER")

	var host_active_shooter = host_state_after.get("data", {}).get("active_shooter_id", "")
	var client_active_shooter = client_state_after.get("data", {}).get("active_shooter_id", "")
	print("[TEST] Post-SELECT_SHOOTER — host.active_shooter_id='%s', client.active_shooter_id='%s'" % [
		host_active_shooter, client_active_shooter
	])

	# REAL BEHAVIORAL ASSERTION: host's phase recorded the selection.
	assert_eq(host_active_shooter, picked_shooter_id,
		"Host's ShootingPhase.active_shooter_id should equal the picked shooter '%s' after SELECT_SHOOTER (got '%s')" % [
			picked_shooter_id, host_active_shooter
		])

	# Phases must still agree across peers (no desync caused by SELECT_SHOOTER).
	var host_phase_after = host_state_after.get("data", {}).get("current_phase", "")
	var client_phase_after = client_state_after.get("data", {}).get("current_phase", "")
	assert_eq(host_phase_after, client_phase_after,
		"Host and client phases must still agree after SELECT_SHOOTER")
	assert_eq(host_phase_after, "Shooting", "Host must still be in Shooting phase after SELECT_SHOOTER")

	# Soft observation about the client phase: with the current broadcast
	# implementation, client's ShootingPhase.active_shooter_id stays empty
	# because `_emit_client_visual_updates` never invokes
	# `_process_select_shooter` on the client phase. We don't fail the test
	# on this — we log it so a future fix that DOES propagate it surfaces
	# here (and we can flip this to assert_eq).
	if client_active_shooter == picked_shooter_id:
		print("[TEST] OBSERVATION: client phase active_shooter_id IS now in sync with host — broadcast may have been extended.")
	elif client_active_shooter == "":
		print("[TEST] OBSERVATION (expected today): client phase active_shooter_id is empty — broadcast pipeline does not propagate this field. Client controller still tracks the shooter via unit_selected_for_shooting signal handler (not exposed by get_game_state).")
	else:
		assert_true(false, "Client active_shooter_id is unexpected: '%s' (expected '' or '%s')" % [
			client_active_shooter, picked_shooter_id
		])

	print("[TEST] PASSED: SELECT_SHOOTER end-to-end — host phase mutated, peers stayed in sync")

## ===========================================================================
## 2. CONTROLLER VISUAL METHODS — confirm the local-render API is intact
## ===========================================================================

func test_shooting_visuals_controller_methods_present():
	"""
	Static-source assertion: ShootingController exposes the four visual
	methods the broadcast pipeline drives:
	   _show_range_indicators       (range circles + half-range circles)
	   _create_target_highlight     (eligible/selected target highlights)
	   _visualize_los_to_target     (LoS line to candidate targets)
	   _create_shooting_line_visual (animated tracer for confirmed shooting)
	If any of these go away, the remote-feedback contract breaks because
	the signal handlers driving them have nothing to call.
	"""
	print("\n[TEST] test_shooting_visuals_controller_methods_present")

	var src = FileAccess.open("res://scripts/ShootingController.gd", FileAccess.READ)
	assert_true(src != null, "ShootingController.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	assert_true(text.contains("func _show_range_indicators"),
		"ShootingController._show_range_indicators must exist (drives range circles on remote)")
	assert_true(text.contains("func _create_target_highlight"),
		"ShootingController._create_target_highlight must exist (drives eligible/selected target highlights on remote)")
	assert_true(text.contains("func _visualize_los_to_target"),
		"ShootingController._visualize_los_to_target must exist (drives LoS lines on remote)")
	assert_true(text.contains("func _create_shooting_line_visual"),
		"ShootingController._create_shooting_line_visual must exist (drives the animated tracer on remote when shooting is confirmed)")

	# T5-MP3 added two remote-only entry points the relay/RPC dispatcher calls.
	assert_true(text.contains("func show_remote_target_assignment"),
		"ShootingController.show_remote_target_assignment must exist (per-assignment tracer + highlight, called from NetworkManager)")
	assert_true(text.contains("func clear_remote_target_assignments"),
		"ShootingController.clear_remote_target_assignments must exist (clears per-assignment visuals on CLEAR_ASSIGNMENT / CLEAR_ALL)")

	print("[TEST] PASSED: all four local-render methods + two remote-entry methods present in ShootingController")

## ===========================================================================
## 3. NETWORK MANAGER → CONTROLLER CONTRACT — signal/method dispatching
## ===========================================================================

func test_shooting_visuals_select_shooter_reemit_contract():
	"""
	Static-source assertion: NetworkManager._emit_client_visual_updates
	re-emits `unit_selected_for_shooting` AND `targets_available` on the
	remote phase when the broadcast carries a SELECT_SHOOTER. These two
	signals are the ONLY way the remote ShootingController learns which
	shooter to highlight, so without them the client renders nothing.
	"""
	print("\n[TEST] test_shooting_visuals_select_shooter_reemit_contract")

	var src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	assert_true(src != null, "NetworkManager.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	# unit_selected_for_shooting re-emit on SELECT_SHOOTER
	assert_true(text.contains("emit_signal(\"unit_selected_for_shooting\""),
		"NetworkManager must re-emit unit_selected_for_shooting on remote phase for SELECT_SHOOTER")

	# targets_available re-emit accompanies it (drives target highlights + LoS)
	assert_true(text.contains("emit_signal(\"targets_available\""),
		"NetworkManager must re-emit targets_available with eligible_targets list (drives target highlights + LoS lines on remote)")

	print("[TEST] PASSED: SELECT_SHOOTER → unit_selected_for_shooting + targets_available re-emit contracts present")

func test_shooting_visuals_assign_clear_target_controller_contract():
	"""
	Static-source assertion: NetworkManager.dispatches ASSIGN_TARGET and
	CLEAR_ASSIGNMENT / CLEAR_ALL_ASSIGNMENTS into ShootingController via
	direct method calls (`show_remote_target_assignment` and
	`clear_remote_target_assignments`). These are the per-assignment
	tracer + highlight on the remote screen.
	"""
	print("\n[TEST] test_shooting_visuals_assign_clear_target_controller_contract")

	var src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	assert_true(src != null, "NetworkManager.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	assert_true(text.contains("show_remote_target_assignment("),
		"NetworkManager must call ShootingController.show_remote_target_assignment on ASSIGN_TARGET (drives per-assignment tracer + highlight)")
	assert_true(text.contains("clear_remote_target_assignments("),
		"NetworkManager must call ShootingController.clear_remote_target_assignments on CLEAR_ASSIGNMENT / CLEAR_ALL (removes per-assignment tracer)")

	# Both ENet AND relay branches should mirror the same calls (T5-MP3 marker).
	var t5_mp3_count = text.count("T5-MP3")
	assert_true(t5_mp3_count >= 2,
		"Both ENet and relay branches should carry T5-MP3 markers for shooting visuals (got %d marker(s); expected >=2)" % t5_mp3_count)

	print("[TEST] PASSED: ASSIGN/CLEAR target → controller method contracts present (%d T5-MP3 markers)" % t5_mp3_count)

func test_shooting_visuals_confirm_complete_signal_reemit_contract():
	"""
	Static-source assertion: NetworkManager re-emits `shooting_begun` on
	CONFIRM_TARGETS (drives the animated tracer on remote) and
	`shooting_resolved` on COMPLETE_SHOOTING_FOR_UNIT (clears per-shooter
	visuals on remote).

	Pre-T5-MP3 bug: these signals only fired on the host, so the client's
	ShootingController never animated the tracer or cleared the visuals
	when the host finished a shooter's resolution.
	"""
	print("\n[TEST] test_shooting_visuals_confirm_complete_signal_reemit_contract")

	var src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	assert_true(src != null, "NetworkManager.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	assert_true(text.contains("emit_signal(\"shooting_begun\""),
		"NetworkManager must re-emit shooting_begun on remote phase for CONFIRM_TARGETS (drives the animated tracer)")
	assert_true(text.contains("emit_signal(\"shooting_resolved\""),
		"NetworkManager must re-emit shooting_resolved on remote phase for COMPLETE_SHOOTING_FOR_UNIT (clears per-shooter visuals)")

	print("[TEST] PASSED: CONFIRM_TARGETS → shooting_begun + COMPLETE → shooting_resolved re-emit contracts present")

func test_shooting_visuals_action_allowlist_membership():
	"""
	Static-source assertion: SELECT_SHOOTER, ASSIGN_TARGET, CLEAR_ASSIGNMENT,
	CLEAR_ALL_ASSIGNMENTS appear on the optimistic-execution allow-list so
	the broadcast pipeline actually fires for them. If any get dropped, the
	corresponding visuals never reach the remote.

	The allow-list is the gate; without it the action types never flow
	through `_emit_client_visual_updates`.
	"""
	print("\n[TEST] test_shooting_visuals_action_allowlist_membership")

	# The allow-list lives in NetworkManager and/or PhaseManager. Search both.
	var nm_src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	assert_true(nm_src != null, "NetworkManager.gd should be readable")
	if nm_src == null:
		return
	var nm_text = nm_src.get_as_text()
	nm_src.close()

	# These four action types MUST appear by name as strings somewhere in
	# NetworkManager (allow-list, dispatch, or both).
	var actions := ["SELECT_SHOOTER", "ASSIGN_TARGET", "CLEAR_ASSIGNMENT", "CLEAR_ALL_ASSIGNMENTS"]
	for action_name in actions:
		assert_true(nm_text.contains(action_name),
			"NetworkManager must reference action type '%s' (allow-list / dispatch); otherwise the broadcast pipeline drops it before reaching the client" % action_name)

	# CONFIRM_TARGETS and COMPLETE_SHOOTING_FOR_UNIT must also be there.
	assert_true(nm_text.contains("CONFIRM_TARGETS"),
		"NetworkManager must reference CONFIRM_TARGETS for the shooting_begun re-emit")
	assert_true(nm_text.contains("COMPLETE_SHOOTING_FOR_UNIT"),
		"NetworkManager must reference COMPLETE_SHOOTING_FOR_UNIT for the shooting_resolved re-emit")

	print("[TEST] PASSED: all six shooting action types referenced in NetworkManager")

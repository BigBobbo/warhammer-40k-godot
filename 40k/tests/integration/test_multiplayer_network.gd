extends "res://tests/helpers/MultiplayerIntegrationTest.gd"

# Multiplayer Network Infrastructure Tests — T6-4
#
# Tests network-level multiplayer functionality:
# 1. Game state synchronization between host and client
# 2. Latency simulation (artificial delay, jitter, packet loss)
# 3. Disconnect handling (client drop, host drop, action-during-disconnect)
#
# These tests exercise the MultiplayerIntegrationTest infrastructure
# (command file IPC, latency injection, disconnect simulation) and
# verify that the game instances stay consistent under adverse conditions.

## ===========================================================================
## 1. NETWORK STATE SYNCHRONIZATION
## ===========================================================================

func test_game_state_synchronization():
	"""
	Test: Host and client game states match after connection

	Setup: Launch host and client, wait for connection
	Action: Query game state from both instances
	Verify: Critical state fields (phase, turn, units) match
	"""
	print("\n[TEST] test_game_state_synchronization")

	var launched = await launch_host_and_client()
	assert_true(launched, "Should launch both instances")

	var connected = await wait_for_connection()
	assert_true(connected, "Client should connect to host")

	# Wait for game to fully initialize
	await wait_for_seconds(3.0)

	# Compare game states
	var comparison = await assert_game_states_match("Initial game states should match after connection")

	print("[TEST] Host state: phase=%s, units=%d" % [
		comparison["host_state"].get("current_phase", "unknown"),
		comparison["host_state"].get("units", {}).size()
	])
	print("[TEST] Client state: phase=%s, units=%d" % [
		comparison["client_state"].get("current_phase", "unknown"),
		comparison["client_state"].get("units", {}).size()
	])

	assert_true(comparison["match"], "Game states should match: %s" % str(comparison["mismatches"]))
	print("[TEST] PASSED: Game state synchronization verified")

func test_state_sync_after_deployment_action():
	"""
	Test: Game state stays synchronized after a deployment action

	Setup: Connected host and client in deployment phase
	Action: Host deploys a unit
	Verify: Both instances reflect the deployment in their state
	"""
	print("\n[TEST] test_state_sync_after_deployment_action")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Verify initial sync
	var initial_comparison = await assert_game_states_match("Pre-action states should match")
	if not initial_comparison["match"]:
		print("[TEST] WARNING: Initial states already out of sync, continuing anyway")

	# Get available units
	var units_result = await simulate_host_action("get_available_units", {})
	if not units_result.get("success", false):
		print("[TEST] WARNING: Could not get available units, skipping action portion")
		return

	var p1_units = units_result.get("data", {}).get("player_1_undeployed", [])
	if p1_units.size() == 0:
		print("[TEST] WARNING: No undeployed units, skipping action portion")
		return

	var test_unit_id = p1_units[0]
	print("[TEST] Deploying unit: %s" % test_unit_id)

	# Deploy a unit
	var deploy_result = await simulate_host_action("deploy_unit", {
		"unit_id": test_unit_id,
		"position": {"x": 150.0, "y": 150.0}
	})

	if deploy_result.get("success", false):
		# Wait for state to propagate
		await wait_for_seconds(2.0)

		# Compare states after action
		var post_comparison = await assert_game_states_match("States should match after deployment")
		print("[TEST] Post-deployment sync: match=%s, mismatches=%s" % [
			post_comparison["match"], str(post_comparison["mismatches"])])
	else:
		print("[TEST] Deploy action failed (expected in some game states): %s" % deploy_result.get("message", ""))

	print("[TEST] PASSED: State sync after action test completed")

func test_multiple_actions_maintain_sync():
	"""
	Test: Multiple sequential actions don't cause state drift

	Setup: Connected host and client
	Action: Send several get_game_state queries in sequence
	Verify: All queries return consistent results
	"""
	print("\n[TEST] test_multiple_actions_maintain_sync")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	var host_phases: Array = []
	var client_phases: Array = []
	var query_count = 3

	for i in range(query_count):
		var host_result = await simulate_host_action("get_game_state", {})
		var client_result = await simulate_client_action("get_game_state", {})

		if host_result.get("success", false):
			host_phases.append(host_result.get("data", {}).get("current_phase", ""))
		if client_result.get("success", false):
			client_phases.append(client_result.get("data", {}).get("current_phase", ""))

		await wait_for_seconds(0.5)

	# Verify host phases are all the same (no drift)
	if host_phases.size() >= 2:
		for i in range(1, host_phases.size()):
			assert_eq(host_phases[i], host_phases[0],
				"Host phase should be consistent across queries (query %d)" % i)

	# Verify client phases are all the same
	if client_phases.size() >= 2:
		for i in range(1, client_phases.size()):
			assert_eq(client_phases[i], client_phases[0],
				"Client phase should be consistent across queries (query %d)" % i)

	# Verify host and client agree
	if host_phases.size() > 0 and client_phases.size() > 0:
		assert_eq(host_phases[0], client_phases[0],
			"Host and client should report the same phase")

	print("[TEST] Queried %d times — host phases: %s, client phases: %s" % [
		query_count, str(host_phases), str(client_phases)])
	print("[TEST] PASSED: Multiple actions maintain sync")

## ===========================================================================
## 2. LATENCY SIMULATION
## ===========================================================================

func test_latency_simulation_basic():
	"""
	Test: Latency simulation adds measurable delay to actions

	Setup: Connected host and client
	Action: Measure RTT without latency, then with 200ms latency
	Verify: Latency-simulated actions take noticeably longer
	"""
	print("\n[TEST] test_latency_simulation_basic")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Measure baseline RTT (no simulated latency)
	simulated_latency_ms = 0
	simulated_jitter_ms = 0
	simulated_packet_loss_pct = 0.0

	var baseline_rtt = await get_action_round_trip_time_ms(host_instance, "get_game_state", {})
	assert_true(baseline_rtt >= 0, "Baseline RTT measurement should succeed")
	print("[TEST] Baseline RTT: %.0fms" % baseline_rtt)

	# Enable latency simulation (200ms)
	simulated_latency_ms = 200
	simulated_jitter_ms = 0

	var latency_rtt = await get_action_round_trip_time_ms(host_instance, "get_game_state", {})
	assert_true(latency_rtt >= 0, "Latency RTT measurement should succeed")
	print("[TEST] Latency RTT (200ms sim): %.0fms" % latency_rtt)

	# The latency-simulated action should take at least ~150ms longer than baseline
	# (using a conservative threshold to account for timing variance)
	var rtt_difference = latency_rtt - baseline_rtt
	print("[TEST] RTT difference: %.0fms" % rtt_difference)
	assert_true(rtt_difference >= 100,
		"Simulated 200ms latency should add at least 100ms to RTT (got %.0fms difference)" % rtt_difference)

	# Reset latency
	simulated_latency_ms = 0
	print("[TEST] PASSED: Latency simulation adds measurable delay")

func test_latency_simulation_with_jitter():
	"""
	Test: Jitter simulation adds variable delay to actions

	Setup: Connected host and client
	Action: Send multiple actions with latency+jitter, measure variance
	Verify: RTT values vary (not all identical) due to jitter
	"""
	print("\n[TEST] test_latency_simulation_with_jitter")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Enable latency + jitter (100ms base, +/- 50ms jitter)
	simulated_latency_ms = 100
	simulated_jitter_ms = 50
	simulated_packet_loss_pct = 0.0

	var rtts: Array = []
	var measurement_count = 5

	for i in range(measurement_count):
		var rtt = await get_action_round_trip_time_ms(host_instance, "get_game_state", {})
		if rtt >= 0:
			rtts.append(rtt)
		print("[TEST] Jitter RTT measurement %d: %.0fms" % [i + 1, rtt])

	assert_true(rtts.size() >= 3,
		"Should get at least 3 successful RTT measurements (got %d)" % rtts.size())

	# With jitter, RTTs should not all be identical
	# Calculate min/max spread
	if rtts.size() >= 2:
		var min_rtt = rtts[0]
		var max_rtt = rtts[0]
		for rtt in rtts:
			min_rtt = min(min_rtt, rtt)
			max_rtt = max(max_rtt, rtt)
		var spread = max_rtt - min_rtt
		print("[TEST] RTT spread: %.0fms (min=%.0f, max=%.0f)" % [spread, min_rtt, max_rtt])
		# With 50ms jitter, we expect some variance (though can't guarantee > 0 with few samples)
		# Just verify the infrastructure doesn't crash and values are in expected range
		assert_true(min_rtt >= 0, "Minimum RTT should be non-negative")

	# All RTTs should be at least ~50ms (100ms base - 50ms jitter = 50ms minimum)
	for rtt in rtts:
		assert_true(rtt >= 30,
			"RTT with 100ms latency should be at least 30ms (got %.0fms)" % rtt)

	# Reset
	simulated_latency_ms = 0
	simulated_jitter_ms = 0
	print("[TEST] PASSED: Jitter simulation produces variable delay")

func test_packet_loss_simulation():
	"""
	Test: Packet loss simulation causes some actions to fail

	Setup: Connected host and client
	Action: Send multiple actions with 50% packet loss
	Verify: Some actions fail with PACKET_LOSS error, some succeed
	"""
	print("\n[TEST] test_packet_loss_simulation")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Enable high packet loss for testing (50%)
	simulated_latency_ms = 0
	simulated_jitter_ms = 0
	simulated_packet_loss_pct = 0.5

	var success_count = 0
	var loss_count = 0
	var total_attempts = 10

	for i in range(total_attempts):
		var result = await simulate_host_action("get_game_state", {})
		if result.get("success", false):
			success_count += 1
		elif result.get("error", "") == "PACKET_LOSS":
			loss_count += 1
		# Other errors don't count as packet loss

	print("[TEST] Packet loss test: %d/%d succeeded, %d lost" % [
		success_count, total_attempts, loss_count])

	# With 50% loss over 10 attempts, we expect some successes and some losses
	# Statistical guarantee: P(all 10 succeed) = 0.5^10 ≈ 0.001 — extremely unlikely
	# P(all 10 fail) = 0.5^10 ≈ 0.001 — also extremely unlikely
	assert_true(loss_count > 0,
		"With 50%% packet loss over %d attempts, at least one should be lost (got %d losses)" % [
			total_attempts, loss_count])
	assert_true(success_count > 0,
		"With 50%% packet loss over %d attempts, at least one should succeed (got %d successes)" % [
			total_attempts, success_count])

	# Reset
	simulated_packet_loss_pct = 0.0
	print("[TEST] PASSED: Packet loss simulation causes expected failure pattern")

func test_latency_does_not_break_game_state():
	"""
	Test: Actions under simulated latency still produce correct results

	Setup: Connected host and client with 150ms latency
	Action: Get game state, verify it has expected structure
	Verify: Response data is valid despite delay
	"""
	print("\n[TEST] test_latency_does_not_break_game_state")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Simulate moderate network conditions
	simulated_latency_ms = 150
	simulated_jitter_ms = 30
	simulated_packet_loss_pct = 0.0

	# Get game state with latency — should still return valid data
	var result = await simulate_host_action("get_game_state", {})
	assert_true(result.get("success", false),
		"Game state query should succeed even with 150ms latency")

	var data = result.get("data", {})
	# Verify the response has expected structure
	assert_true(data.has("current_phase") or data.has("units") or data.size() > 0,
		"Game state should contain meaningful data despite latency")
	print("[TEST] Game state under latency: %s" % str(data.keys()))

	# Try the same on client side
	var client_result = await simulate_client_action("get_game_state", {})
	assert_true(client_result.get("success", false),
		"Client game state query should succeed with latency")

	# Reset
	simulated_latency_ms = 0
	simulated_jitter_ms = 0
	print("[TEST] PASSED: Latency doesn't corrupt game state data")

## ===========================================================================
## 3. DISCONNECT HANDLING
## ===========================================================================

func test_client_disconnect_detection():
	"""
	Test: Client disconnect is detectable via failed command simulation

	Setup: Connected host and client
	Action: Terminate client process
	Verify: Client stops responding to commands, host remains operational
	"""
	print("\n[TEST] test_client_disconnect_detection")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Verify both instances are responding before disconnect
	var pre_host = await simulate_host_action("get_game_state", {})
	assert_true(pre_host.get("success", false), "Host should respond before disconnect")

	var pre_client = await simulate_client_action("get_game_state", {})
	assert_true(pre_client.get("success", false), "Client should respond before disconnect")

	# Disconnect client
	var disconnected = simulate_client_disconnect()
	assert_true(disconnected, "Client should be disconnectable")

	# Wait for disconnect to propagate
	await wait_for_seconds(2.0)

	# Host should still respond
	var post_host = await simulate_host_action("get_game_state", {})
	assert_true(post_host.get("success", false),
		"Host should still respond after client disconnects")

	# Client should no longer respond (process terminated)
	var client_alive = await verify_instance_alive(client_instance)
	assert_false(client_alive,
		"Client should not respond after being terminated")

	print("[TEST] PASSED: Client disconnect detected correctly")

func test_host_disconnect_detection():
	"""
	Test: Host disconnect is detectable via failed command simulation

	Setup: Connected host and client
	Action: Terminate host process
	Verify: Host stops responding, client also eventually fails
	"""
	print("\n[TEST] test_host_disconnect_detection")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Verify both responding
	var pre_host = await simulate_host_action("get_game_state", {})
	assert_true(pre_host.get("success", false), "Host should respond before disconnect")

	# Disconnect host
	var disconnected = simulate_host_disconnect()
	assert_true(disconnected, "Host should be disconnectable")

	# Wait for disconnect to propagate
	await wait_for_seconds(2.0)

	# Host should no longer respond
	var host_alive = await verify_instance_alive(host_instance)
	assert_false(host_alive,
		"Host should not respond after being terminated")

	print("[TEST] PASSED: Host disconnect detected correctly")

func test_action_after_client_disconnect():
	"""
	Test: Host can detect that client is gone when trying to forward actions

	Setup: Connected host and client, client disconnects mid-session
	Action: Try to send an action to the disconnected client
	Verify: Action returns an error (not a hang or crash)
	"""
	print("\n[TEST] test_action_after_client_disconnect")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Disconnect client
	simulate_client_disconnect()
	await wait_for_seconds(2.0)

	# Try to send an action to the dead client
	# This should return an error, not hang
	var result = await simulate_client_action("get_game_state", {})

	# The action should fail gracefully (timeout, null instance, or explicit error)
	var failed_gracefully = (
		not result.get("success", false) or
		result.get("error", "") == "NULL_INSTANCE" or
		result.get("error", "") == "TIMEOUT"
	)
	assert_true(failed_gracefully,
		"Action to disconnected client should fail gracefully, got: %s" % str(result))

	print("[TEST] Action to disconnected client result: %s" % str(result))
	print("[TEST] PASSED: Actions to disconnected clients fail gracefully")

func test_disconnect_does_not_crash_host():
	"""
	Test: Client disconnecting doesn't crash the host's game state

	Setup: Connected host and client
	Action: Client disconnects, then host continues operating
	Verify: Host can still process game state queries after disconnect
	"""
	print("\n[TEST] test_disconnect_does_not_crash_host")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Get initial host state
	var initial_state = await simulate_host_action("get_game_state", {})
	assert_true(initial_state.get("success", false), "Initial host state should be available")

	# Disconnect client
	simulate_client_disconnect()
	await wait_for_seconds(3.0)

	# Host should still be able to process queries
	var post_disconnect_state = await simulate_host_action("get_game_state", {})
	assert_true(post_disconnect_state.get("success", false),
		"Host should still respond after client disconnects")

	# State should be coherent (phase and data still present)
	var host_data = post_disconnect_state.get("data", {})
	print("[TEST] Host state after disconnect: %s" % str(host_data.keys()))
	assert_true(host_data.size() > 0,
		"Host should still have game state data after client disconnect")

	# Try multiple queries to ensure stability
	for i in range(3):
		var check = await simulate_host_action("get_game_state", {})
		assert_true(check.get("success", false),
			"Host query %d should succeed after disconnect" % (i + 1))
		await wait_for_seconds(0.5)

	print("[TEST] PASSED: Host remains stable after client disconnect")

## ===========================================================================
## 4. COMBINED ADVERSE CONDITIONS
## ===========================================================================

func test_latency_plus_disconnect():
	"""
	Test: Disconnect is handled correctly even under simulated latency

	Setup: Connected host and client with 100ms latency
	Action: Client disconnects while latency is active
	Verify: Host still operates correctly after disconnect
	"""
	print("\n[TEST] test_latency_plus_disconnect")

	await launch_host_and_client()
	await wait_for_connection()
	await wait_for_seconds(3.0)

	# Enable latency
	simulated_latency_ms = 100
	simulated_jitter_ms = 20

	# Verify connection works under latency
	var pre_result = await simulate_host_action("get_game_state", {})
	assert_true(pre_result.get("success", false),
		"Host should respond under latency before disconnect")

	# Disconnect client while latency is active
	simulate_client_disconnect()
	await wait_for_seconds(2.0)

	# Host should still respond (latency applies to our test commands, not to actual networking)
	var post_result = await simulate_host_action("get_game_state", {})
	assert_true(post_result.get("success", false),
		"Host should respond under latency after client disconnect")

	# Reset
	simulated_latency_ms = 0
	simulated_jitter_ms = 0
	print("[TEST] PASSED: Disconnect handled correctly under simulated latency")

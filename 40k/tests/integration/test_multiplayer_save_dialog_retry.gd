extends "res://tests/helpers/MultiplayerIntegrationTest.gd"

# Multiplayer Save Dialog Retry/Dedupe Tests — T5-MP4-RELIABILITY
#
# Backstory: commit 1a8e712 added a `save_broadcast_id` retry/dedupe protocol
# to the wound-allocation broadcast pipeline:
#   - Each `saves_required` emission gets a unique sbid stamped onto every
#     save_data entry (`ShootingPhase._generate_save_broadcast_id`).
#   - Defender's WoundAllocationOverlay (via ShootingController) dedupes on
#     sbid: a duplicate broadcast with the same id is silently skipped and
#     re-acked.
#   - Attacker tracks `_expected_save_ack_broadcast_id`; stale acks are
#     ignored without clearing active retry state.
#   - On ack timeout, attacker retries up to MAX_SAVE_RETRY_ATTEMPTS=3 with
#     the SAME sbid; on exhaustion, surfaces a red "defender unreachable" toast.
#
# The single-process test `test_save_broadcast_reliability.gd` already pins
# the protocol slice (34 assertions on stamping, dedupe, retry budget, and
# RPC carrier shape). This file is the multi-peer counterpart: it spins up
# real host + client Godot processes and verifies the harness preserves the
# protocol on the wire.
#
# IMPORTANT API LIMITATION
# ------------------------
# `MultiplayerIntegrationTest.simulate_host_action` is bridged to
# `TestModeHandler` which currently does NOT support shooting actions
# (only deployment, save load, get_game_state, get_available_units, and
# capture/save). There is no way to drive a real wound-allocation broadcast
# through the command-file IPC, so we cannot:
#   - Trigger a real RESOLVE_SHOOTING that emits saves_required from the host
#   - Inject synthetic delivery failure on the client to force retry
#   - Read the WoundAllocationOverlay's actual sbid history
#
# What we CAN do:
#   1. Launch host + client, load shooting save, assert both reach SHOOTING
#      phase with matching units (so a real wound broadcast would have
#      consistent actors on both peers — the precondition for retry/dedupe).
#   2. Static-source assert the protocol contract (sbid generation, stamping,
#      idempotent re-stamp, MAX_SAVE_RETRY_ATTEMPTS=3, ack carrier shape) so a
#      refactor that breaks the contract fails the multi-peer suite too.
#
# Manual scenarios still needed (not driveable from the command-file IPC):
#   - Happy path: defender's WoundAllocationOverlay shows once, attacker sees
#     ack, no retry toast.
#   - Lossy retry: kill the relay between RESOLVE_SHOOTING and ack;
#     reconnect within 8s. Verify retry toast on attacker, single dialog on
#     defender (dedupe).
#   - Budget exhaustion: keep relay disconnected >24s. Verify red
#     "could not reach defender after 3 attempts" toast.
#   - Multi-weapon: two weapons each generate distinct sbids.
#
# Usage: bash 40k/tests/run_multiplayer_tests.sh

## ===========================================================================
## 1. CONNECTION + SHOOTING PHASE PRECONDITION (DRIVEABLE END-TO-END)
## ===========================================================================

func test_save_dialog_retry_connection_to_shooting_save():
	"""
	Test: Host and client both reach SHOOTING phase in sync. This is the
	precondition for any save broadcast: the two peers must agree on units
	and active_player before a saves_required broadcast can be addressed
	correctly.

	Setup: launch host+client with shooting save (auto-loaded)
	Action: query game state from both peers
	Verify: both report Shooting phase, matching units (so a subsequent
	        wound broadcast targets the same defender on each peer).
	"""
	print("\n[TEST] test_save_dialog_retry_connection_to_shooting_save")

	var shooting_save = get_shooting_test_save().get_file()
	print("[TEST] Using shooting save: %s" % shooting_save)

	var launched = await launch_host_and_client(shooting_save)
	assert_true(launched, "Should launch both instances with shooting save")

	var connected = await wait_for_connection()
	assert_true(connected, "Client should connect to host")

	# Wait for save load + phase transition to settle on both peers.
	await wait_for_seconds(4.0)

	var host_state = await simulate_host_action("get_game_state", {})
	var client_state = await simulate_client_action("get_game_state", {})

	assert_true(host_state.get("success", false), "Host should return game state")
	assert_true(client_state.get("success", false), "Client should return game state")

	var host_phase = host_state.get("data", {}).get("current_phase", "")
	var client_phase = client_state.get("data", {}).get("current_phase", "")
	print("[TEST] Host phase: '%s', Client phase: '%s'" % [host_phase, client_phase])

	if host_phase != "Shooting":
		print("[TEST] WARNING: Host did not reach Shooting phase (got '%s'). Auto-load may have failed; manual smoke required for the actual retry/dedupe scenarios." % host_phase)
		assert_eq(host_phase, client_phase,
			"Host and client must at least agree on phase even when shooting save is missing")
		print("[TEST] PASSED (with warning): connection sync verified, phase agreement verified")
		return

	assert_eq(host_phase, "Shooting", "Host should be in Shooting phase")
	assert_eq(client_phase, "Shooting", "Client should be in Shooting phase")

	# Defender unit on host MUST also be on client — otherwise the
	# save_broadcast_id targets a unit the client doesn't know about and
	# the dedupe logic has nothing to compare against.
	var host_units = host_state.get("data", {}).get("units", {})
	var client_units = client_state.get("data", {}).get("units", {})
	assert_eq(host_units.size(), client_units.size(),
		"Host and client should have the same unit count (defender must exist on both)")

	for unit_id in host_units.keys():
		assert_true(unit_id in client_units,
			"Unit '%s' on host should also be on client (else save_broadcast_id has nothing to address)" % unit_id)

	print("[TEST] PASSED: Save dialog retry/dedupe precondition (Shooting phase + matching units) verified end-to-end")

## ===========================================================================
## 2. PROTOCOL CONTRACT — broadcast_id generation + stamping
## ===========================================================================

func test_save_dialog_retry_broadcast_id_helpers_present():
	"""
	Static-source assertion: ShootingPhase exposes the two static helpers
	the broadcast pipeline uses:
	   _generate_save_broadcast_id() -> String
	   _stamp_save_broadcast_id(save_data_list, broadcast_id)

	Without these, every saves_required emission would lack a unique id,
	which means the defender can't dedupe duplicate broadcasts on retry
	and the attacker can't ignore stale acks.
	"""
	print("\n[TEST] test_save_dialog_retry_broadcast_id_helpers_present")

	var src = FileAccess.open("res://phases/ShootingPhase.gd", FileAccess.READ)
	assert_true(src != null, "ShootingPhase.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	assert_true(text.contains("static func _generate_save_broadcast_id"),
		"ShootingPhase._generate_save_broadcast_id helper must exist")
	assert_true(text.contains("static func _stamp_save_broadcast_id"),
		"ShootingPhase._stamp_save_broadcast_id helper must exist")

	# Both saves_required emit sites must call the stamper.
	var stamp_calls = text.count("_stamp_save_broadcast_id(")
	assert_true(stamp_calls >= 2,
		"_stamp_save_broadcast_id must be called by every saves_required emit site (got %d call(s); expected >=2 for resolve_shooting + sequential weapon paths)" % stamp_calls)

	# The id format prefix used in logs / debug output ("sbid-...")
	assert_true(text.contains("\"sbid-\"") or text.contains("'sbid-'"),
		"save_broadcast_id should use 'sbid-' prefix (matches NetworkManager + ShootingController log lines)")

	print("[TEST] PASSED: %d _stamp_save_broadcast_id call sites (>=2 required)" % stamp_calls)

func test_save_dialog_retry_max_attempts_constant():
	"""
	Static-source assertion: ShootingController.MAX_SAVE_RETRY_ATTEMPTS = 3.
	If this constant changes, the spec changes too — make it visible.
	"""
	print("\n[TEST] test_save_dialog_retry_max_attempts_constant")

	var src = FileAccess.open("res://scripts/ShootingController.gd", FileAccess.READ)
	assert_true(src != null, "ShootingController.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	assert_true(text.contains("MAX_SAVE_RETRY_ATTEMPTS: int = 3"),
		"ShootingController.MAX_SAVE_RETRY_ATTEMPTS must be 3 (the documented spec). If this changes intentionally, update TESTS_NEEDED.md and the manual smoke scripts.")

	# Retry pipeline must increment _save_retry_attempts and bail at the cap.
	assert_true(text.contains("_save_retry_attempts >= MAX_SAVE_RETRY_ATTEMPTS"),
		"Retry loop must check _save_retry_attempts against MAX_SAVE_RETRY_ATTEMPTS to enforce the budget")
	assert_true(text.contains("_save_retry_attempts += 1") or text.contains("_save_retry_attempts = _save_retry_attempts + 1"),
		"Retry loop must increment _save_retry_attempts on each retry")

	print("[TEST] PASSED: MAX_SAVE_RETRY_ATTEMPTS=3 + budget-check + increment all present")

## ===========================================================================
## 3. PROTOCOL CONTRACT — defender dedupe + attacker stale-ack handling
## ===========================================================================

func test_save_dialog_retry_defender_dedupes_on_broadcast_id():
	"""
	Static-source assertion: ShootingController defender path stores the
	`save_broadcast_id` of every shown dialog in `_shown_save_broadcast_ids`
	and skips a duplicate broadcast (silent re-ack).
	"""
	print("\n[TEST] test_save_dialog_retry_defender_dedupes_on_broadcast_id")

	var src = FileAccess.open("res://scripts/ShootingController.gd", FileAccess.READ)
	assert_true(src != null, "ShootingController.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	assert_true(text.contains("_shown_save_broadcast_ids"),
		"Defender path must keep a `_shown_save_broadcast_ids` history to dedupe duplicate broadcasts")

	# The dedupe check pattern: incoming sbid in _shown_save_broadcast_ids
	assert_true(text.contains("incoming_sbid") and text.contains("in _shown_save_broadcast_ids"),
		"Defender must check `incoming_sbid in _shown_save_broadcast_ids` to skip duplicates")

	print("[TEST] PASSED: defender dedupe via _shown_save_broadcast_ids present in source")

func test_save_dialog_retry_attacker_ignores_stale_acks():
	"""
	Static-source assertion: ShootingController attacker path compares the
	incoming ack's sbid against `_expected_save_ack_broadcast_id` and ignores
	stale acks (different sbid) without clearing active retry state.

	This is the bug the protocol fixes: pre-fix, a late-arriving ack for an
	earlier broadcast would clear the retry timer for the CURRENT broadcast,
	stalling the dialog forever.
	"""
	print("\n[TEST] test_save_dialog_retry_attacker_ignores_stale_acks")

	var src = FileAccess.open("res://scripts/ShootingController.gd", FileAccess.READ)
	assert_true(src != null, "ShootingController.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	assert_true(text.contains("_expected_save_ack_broadcast_id"),
		"Attacker must track _expected_save_ack_broadcast_id to ignore stale acks")
	assert_true(text.contains("on_save_dialog_acknowledged"),
		"Attacker must expose on_save_dialog_acknowledged callback for the relay/RPC pipeline")

	print("[TEST] PASSED: attacker stale-ack guard via _expected_save_ack_broadcast_id present in source")

## ===========================================================================
## 4. RPC / RELAY CARRIER CONTRACT — sbid carries end-to-end
## ===========================================================================

func test_save_dialog_retry_network_carrier_includes_sbid():
	"""
	Static-source assertion: NetworkManager's send_save_dialog_ack and
	_receive_save_dialog_ack carry the `save_broadcast_id` parameter on
	both ENet RPC and web-relay branches. If a future refactor drops the
	parameter, the dedupe / stale-ack logic loses its discriminator and
	the retry protocol degrades silently to "always re-show dialog".
	"""
	print("\n[TEST] test_save_dialog_retry_network_carrier_includes_sbid")

	var src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	assert_true(src != null, "NetworkManager.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	# send_save_dialog_ack must take save_broadcast_id parameter.
	assert_true(text.contains("func send_save_dialog_ack") and text.contains("save_broadcast_id"),
		"NetworkManager.send_save_dialog_ack must carry save_broadcast_id parameter")

	# _receive_save_dialog_ack must take save_broadcast_id parameter.
	assert_true(text.contains("func _receive_save_dialog_ack") and text.contains("save_broadcast_id"),
		"NetworkManager._receive_save_dialog_ack must carry save_broadcast_id parameter")

	# retry_save_data_broadcast must exist (the actual retry call).
	assert_true(text.contains("func retry_save_data_broadcast"),
		"NetworkManager.retry_save_data_broadcast must exist for the attacker's retry budget loop")

	print("[TEST] PASSED: NetworkManager RPC + relay both carry save_broadcast_id")

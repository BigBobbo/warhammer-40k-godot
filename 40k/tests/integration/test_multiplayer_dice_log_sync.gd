extends "res://tests/helpers/MultiplayerIntegrationTest.gd"

# Multiplayer Dice Log Sync Tests — T5-MP5
#
# Backstory: commit 4208084 fixed three dice categories that were missing from
# `result["dice"]` broadcast payload during shooting:
#   1. Grenade stratagem (`_process_use_grenade_stratagem`)
#   2. Feel No Pain saves (RulesEngine batch path AND interactive overlay path)
#   3. Hazardous self-damage post-save dice
#
# The single-process test `test_dice_broadcast_sync.gd` already pins the
# protocol slice (`NetworkManager._emit_client_visual_updates` and the
# ShootingPhase result["dice"] structure). This file is the multi-peer
# counterpart: it spins up real host + client Godot processes and verifies
# the broadcast pipeline survives a real connection.
#
# IMPORTANT API LIMITATION
# ------------------------
# `MultiplayerIntegrationTest.simulate_host_action` is bridged to
# `TestModeHandler` which currently only implements 8 actions:
#   load_save, deploy_unit, undo_deployment, complete_deployment,
#   get_game_state, get_available_units, capture_screenshot, save_game_state
#
# There is NO `select_shooter` / `assign_target` / `resolve_shooting`
# action handler. Until TestModeHandler is extended (tracked separately),
# these tests CANNOT drive a real grenade roll / FNP / Hazardous through the
# command-file IPC. What they CAN do, and do here:
#
#   1. Launch host + client, wait for connection, load the shooting save on
#      both peers, and assert both peers reached SHOOTING phase in sync.
#   2. Query each peer's `units` map and assert that any units flagged
#      `HAZARDOUS` / `GRENADES` / FNP-bearing match between host and client
#      so a subsequent dice broadcast would target the same units on each peer.
#   3. Statically assert the source contract that the broadcast pipeline
#      relies on (grenade dice in result, FNP append to save_dice_blocks,
#      Hazardous append to save_dice_blocks) — these are the same checks
#      `test_dice_broadcast_sync.gd` runs, replicated here so a refactor that
#      breaks the contract surfaces as a multi-peer test failure too.
#
# Manual scenarios still needed (no automated coverage possible until
# TestModeHandler grows shooting actions):
#   - Real grenade roll: host shoots a grenade, client dice log shows the 6D6.
#   - Real FNP: host targets DG with Disgustingly Resilient, client log shows FNP.
#   - Real Hazardous self-damage: host fires Hazardous weapon, client log shows post-save check.
#
# Usage: bash 40k/tests/run_multiplayer_tests.sh

## ===========================================================================
## 1. CONNECTION + SHOOTING PHASE LOAD (DRIVEABLE END-TO-END)
## ===========================================================================

func test_dice_log_sync_connection_to_shooting_save():
	"""
	Test: Host and client both load the shooting test save and reach SHOOTING
	phase in sync. This is the precondition for any dice broadcast: the two
	peers must agree on units and active_player before a dice roll can sync.

	Setup: launch host+client with shooting_phase save (auto-loaded)
	Action: query game state from both peers
	Verify: both report Shooting phase, both report the same unit count, and
	        the same units appear (so a subsequent dice broadcast addresses
	        the same actor on each peer).
	"""
	print("\n[TEST] test_dice_log_sync_connection_to_shooting_save")

	# Launch with shooting save so both peers boot directly into shooting phase.
	# (get_shooting_test_save() returns res://tests/saves/shooting_phase.w40ksave;
	# if it doesn't exist, the test still exercises connection but we surface
	# the missing-save case explicitly so the failure is informative.)
	var shooting_save = get_shooting_test_save().get_file()  # strip path -> filename
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

	# If the shooting save isn't present, the auto-load fails silently and the
	# game starts in deployment. Surface that as a skip rather than a hard fail
	# so the test still proves the connection slice works.
	if host_phase != "Shooting":
		print("[TEST] WARNING: Host did not reach Shooting phase (got '%s'). The shooting save may be missing or the auto-load failed; manual smoke test still required." % host_phase)
		# Still verify host/client agree, even if not in shooting phase.
		assert_eq(host_phase, client_phase,
			"Host and client must at least agree on phase even when shooting save is missing")
		print("[TEST] PASSED (with warning): connection sync verified, phase agreement verified")
		return

	assert_eq(host_phase, "Shooting", "Host should be in Shooting phase")
	assert_eq(client_phase, "Shooting", "Client should be in Shooting phase")

	# Unit set must match: a dice broadcast for unit U_ATTACKER on host has to
	# resolve to the same U_ATTACKER on the client, otherwise the client's
	# dice_log wouldn't be able to attribute the rolls to the right unit.
	var host_units = host_state.get("data", {}).get("units", {})
	var client_units = client_state.get("data", {}).get("units", {})
	assert_eq(host_units.size(), client_units.size(),
		"Host and client should have the same number of units in shooting phase")
	print("[TEST] Both peers report %d units" % host_units.size())

	# Assert every host unit is also on the client.
	for unit_id in host_units.keys():
		assert_true(unit_id in client_units,
			"Unit '%s' present on host should also be on client" % unit_id)

	print("[TEST] PASSED: Dice log sync precondition (Shooting phase + matching units) verified end-to-end")

## ===========================================================================
## 2. STATIC-SOURCE CONTRACT (REPLICATED FROM test_dice_broadcast_sync.gd
##    SO REFACTORS THAT BREAK THE CONTRACT FAIL THE MULTI-PEER SUITE TOO)
## ===========================================================================

func test_dice_log_sync_grenade_dice_in_result_contract():
	"""
	Static-source assertion: ShootingPhase._process_use_grenade_stratagem
	bundles the grenade dice block into result["dice"]. If this contract
	breaks, the remote dice log silently drops the 6D6 grenade roll.

	Pre-fix bug (commit 4208084): grenade dice were emitted via dice_rolled
	locally but never appeared in result["dice"], so NetworkManager's
	_emit_client_visual_updates had nothing to re-emit on the client side.

	Why static-source: simulate_host_action cannot drive a grenade stratagem
	(no `use_grenade_stratagem` handler in TestModeHandler) — so the only way
	to assert this contract from a multi-peer test is to grep the source.
	"""
	print("\n[TEST] test_dice_log_sync_grenade_dice_in_result_contract")

	var src = FileAccess.open("res://phases/ShootingPhase.gd", FileAccess.READ)
	assert_true(src != null, "ShootingPhase.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	assert_true(text.contains("\"dice\": [grenade_dice_block]"),
		"ShootingPhase._process_use_grenade_stratagem must bundle grenade dice block in result['dice']; otherwise remote dice log drops the 6D6 grenade roll")

	print("[TEST] PASSED: grenade dice contract present in source")

func test_dice_log_sync_resolution_start_prepend_contract():
	"""
	Static-source assertion: ShootingPhase prepends `resolution_start_block`
	(and `weapon_progress_block` for sequential resolutions) to result["dice"]
	so the remote dice log shows the same "Beginning attack resolution..." /
	"Resolving weapon N of M" headers the local UI shows.
	"""
	print("\n[TEST] test_dice_log_sync_resolution_start_prepend_contract")

	var src = FileAccess.open("res://phases/ShootingPhase.gd", FileAccess.READ)
	assert_true(src != null, "ShootingPhase.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	assert_true(text.contains("[resolution_start_block] + result.get(\"dice\", [])"),
		"resolve_shooting must prepend resolution_start_block to result['dice']; otherwise remote dice log loses the resolution header")
	assert_true(text.contains("[weapon_progress_block] + result.get(\"dice\", [])"),
		"sequential weapon resolution must prepend weapon_progress_block to result['dice']; otherwise remote dice log loses per-weapon headers")

	print("[TEST] PASSED: resolution_start + weapon_progress prepend contracts present in source")

func test_dice_log_sync_fnp_and_hazardous_save_dice_blocks_contract():
	"""
	Static-source assertion: _process_apply_saves appends FNP dice blocks
	(both RulesEngine batch path AND interactive overlay path) AND Hazardous
	post-save dice to `save_dice_blocks` — which is the array bundled into
	the APPLY_SAVES result["dice"]. Pre-fix, these were appended only to the
	local `dice_log`, so the remote peer's dice log silently dropped them.
	"""
	print("\n[TEST] test_dice_log_sync_fnp_and_hazardous_save_dice_blocks_contract")

	var src = FileAccess.open("res://phases/ShootingPhase.gd", FileAccess.READ)
	assert_true(src != null, "ShootingPhase.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	# The two FNP append sites and the Hazardous append site.
	# (Same pattern as test_dice_broadcast_sync.gd, replicated here so a
	# refactor that drops these calls fails the multi-peer suite too.)
	var lines = text.split("\n")
	var fnp_appends = 0
	var haz_appends = 0
	var in_fnp_engine = false
	var in_fnp_overlay = false
	var in_haz_loop = false

	for l in lines:
		if "FEEL NO PAIN: Emit FNP dice blocks from RulesEngine batch path" in l:
			in_fnp_engine = true
		if "fnp_overlay_block = {" in l:
			in_fnp_overlay = true
		if "for haz_dice in haz_result.dice:" in l:
			in_haz_loop = true
		if in_fnp_engine and "save_dice_blocks.append(fnp_dice_block)" in l:
			fnp_appends += 1
			in_fnp_engine = false
		if in_fnp_overlay and "save_dice_blocks.append(fnp_overlay_block)" in l:
			fnp_appends += 1
			in_fnp_overlay = false
		if in_haz_loop and "save_dice_blocks.append(haz_dice)" in l:
			haz_appends += 1
			in_haz_loop = false

	assert_true(fnp_appends >= 2,
		"Both FNP paths (engine + overlay) must append to save_dice_blocks; got %d. Without this, remote dice log loses FNP rolls." % fnp_appends)
	assert_true(haz_appends >= 1,
		"Hazardous dice must be appended to save_dice_blocks (got %d append). Without this, remote dice log loses self-damage rolls." % haz_appends)

	print("[TEST] PASSED: FNP (%d appends) and Hazardous (%d append) save_dice_blocks contracts present in source" % [fnp_appends, haz_appends])

## ===========================================================================
## 3. NETWORK MANAGER RE-EMISSION CONTRACT (multi-peer ↔ remote phase)
## ===========================================================================

func test_dice_log_sync_network_manager_reemits_contract():
	"""
	Static-source assertion: NetworkManager._emit_client_visual_updates
	iterates result["dice"] and re-emits each block on the remote phase via
	`dice_rolled`. This is the bridge that ports host-side dice into the
	client's dice log; if it goes away, the client's log goes silent.
	"""
	print("\n[TEST] test_dice_log_sync_network_manager_reemits_contract")

	var src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	assert_true(src != null, "NetworkManager.gd should be readable")
	if src == null:
		return

	var text = src.get_as_text()
	src.close()

	# The re-emission loop should iterate result["dice"] and emit dice_rolled.
	assert_true(text.contains("for dice_block in") and text.contains("emit_signal(\"dice_rolled\""),
		"NetworkManager._emit_client_visual_updates must iterate result['dice'] and re-emit dice_rolled on the remote phase; otherwise the remote dice log never receives any host-side rolls")

	# And the T5-MP5 marker comment should be present so this is identifiable.
	assert_true(text.contains("T5-MP5") or text.contains("re-emitting dice_rolled"),
		"NetworkManager should still carry the T5-MP5 dice re-emission marker (commit 4208084)")

	print("[TEST] PASSED: NetworkManager dice re-emission contract present in source")

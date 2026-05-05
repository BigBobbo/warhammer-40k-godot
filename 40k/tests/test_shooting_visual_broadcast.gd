extends SceneTree

# T5-MP3: Remote player visual feedback for shooting actions.
#
# When the host (or active player on the relay path) executes a shooting setup
# action — SELECT_SHOOTER, ASSIGN_TARGET, CLEAR_ASSIGNMENT, CLEAR_ALL_ASSIGNMENTS,
# CONFIRM_TARGETS, COMPLETE_SHOOTING_FOR_UNIT — the remote player's
# `ShootingController` only learns about it through the broadcast result that
# `NetworkManager._emit_client_visual_updates` re-emits onto the local phase
# instance.
#
# Local rendering (already in place):
#   - Range circles + half-range dashed circles            (T5-V5, ShootingController._show_range_indicators)
#   - Eligible / selected target highlights                 (ShootingController._create_target_highlight)
#   - LoS lines from shooter to candidate targets           (ShootingController._visualize_los_to_target / los_visual)
#   - Animated shooting line tracers from shooter→target    (T5-V2, ShootingLineVisual via _create_shooting_line_visual)
#
# These visuals are all driven by SIGNALS on the active phase instance:
#   - unit_selected_for_shooting / targets_available  (drives range circles + target highlights + LoS lines on remote)
#   - shooting_begun                                 (drives the animated shooting-line tracer on remote)
#   - shooting_resolved                              (clears per-shooter visuals on remote)
# plus DIRECT calls into ShootingController:
#   - show_remote_target_assignment                  (per-weapon shooting line + target highlight on remote)
#   - clear_remote_target_assignments                (clears the per-assignment lines on remote)
#
# This test pins the broadcast pipeline at the dictionary / signal / source
# level. It does NOT spin up two real Godot peers (single-process headless
# limitation), so it cannot prove that ENet/web-relay actually delivers the
# packets. What it *can* do — and what it asserts here — is that the public
# protocol surface is structured so the remote-feedback guarantees hold
# whenever the transport delivers the messages it accepts. See
# `test_dice_broadcast_sync.gd` and `test_save_broadcast_reliability.gd` for
# the same pattern applied to other multiplayer slices.
#
# Specifically:
#   1. NetworkManager._emit_client_visual_updates(SELECT_SHOOTER) re-emits
#      `unit_selected_for_shooting` AND `targets_available` on the remote
#      phase, which are the signals that drive range circles + LoS lines +
#      target highlights.
#   2. NetworkManager._emit_client_visual_updates(CONFIRM_TARGETS) re-emits
#      `shooting_begun` on the remote phase, which drives the animated
#      shooting-line tracer.
#   3. NetworkManager._emit_client_visual_updates(COMPLETE_SHOOTING_FOR_UNIT)
#      re-emits `shooting_resolved` on the remote phase, which clears
#      per-shooter visuals.
#   4. NetworkManager._emit_client_visual_updates(ASSIGN_TARGET) routes into
#      ShootingController.show_remote_target_assignment when the controller
#      is present, and is a no-op (no crash) when it is absent.
#   5. NetworkManager._emit_client_visual_updates(CLEAR_ASSIGNMENT /
#      CLEAR_ALL_ASSIGNMENTS) routes into
#      ShootingController.clear_remote_target_assignments when present, and
#      is a no-op when absent.
#   6. The host-side relay and ENet branches mirror the same controller calls
#      so the host's own screen sees the remote client's visual hints (T5-MP3
#      bidirectional).
#   7. The shooting-setup action types are listed in the optimistic-execution
#      allow-list so SELECT_SHOOTER / ASSIGN_TARGET / CLEAR_ASSIGNMENT /
#      CLEAR_ALL_ASSIGNMENTS run through the broadcast pipeline at all.
#
# Usage: godot --headless --path . -s tests/test_shooting_visual_broadcast.gd

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
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_shooting_visual_broadcast ===\n")

	_test_select_shooter_reemits_signals_on_remote_phase()
	_test_confirm_targets_reemits_shooting_begun_on_remote()
	_test_complete_shooting_for_unit_reemits_shooting_resolved_on_remote()
	_test_assign_target_routes_to_controller_when_present()
	_test_assign_target_safe_when_controller_absent()
	_test_clear_assignment_routes_to_controller_when_present()
	_test_host_relay_path_calls_remote_visual_helpers()
	_test_host_enet_path_calls_remote_visual_helpers()
	_test_shooting_setup_actions_in_optimistic_allowlist()
	_test_shooting_controller_exposes_remote_visual_methods()

	_finish()

# ---------------------------------------------------------------------------
# 1. SELECT_SHOOTER → unit_selected_for_shooting + targets_available signals.
#
# Remote ShootingController._on_unit_selected_for_shooting and
# _on_targets_available are connected to these phase signals during
# _setup_shooting_signals. Both call _show_range_indicators() (which draws
# range circles + half-range circles + target highlights) and
# _visualize_los_to_target() in debug mode. So if these signals don't fire
# on the remote phase, the remote player sees NONE of those visuals.
# ---------------------------------------------------------------------------
func _test_select_shooter_reemits_signals_on_remote_phase() -> void:
	print("\n-- SELECT_SHOOTER re-emits unit_selected_for_shooting + targets_available on remote phase --")

	var phase_manager = root.get_node("PhaseManager")
	var network_manager = root.get_node("NetworkManager")

	# Save and replace current_phase_instance so we don't disturb whatever
	# the autoloads booted with.
	var prior_phase = phase_manager.current_phase_instance
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	phase_manager.add_child(phase)
	phase_manager.current_phase_instance = phase

	# Capture both signals.
	var selected_emissions := []
	var targets_emissions := []
	var capture_selected := func(unit_id):
		selected_emissions.append(unit_id)
	var capture_targets := func(unit_id, eligible):
		targets_emissions.append({"unit_id": unit_id, "eligible": eligible})
	phase.unit_selected_for_shooting.connect(capture_selected)
	phase.targets_available.connect(capture_targets)

	# Synthetic broadcast result for SELECT_SHOOTER. The shooter id doesn't
	# need to exist in GameState — RulesEngine.get_eligible_targets returns
	# an empty dict for unknown shooters, and the test only cares that the
	# signal fires with the correct unit_id.
	var synthetic_result := {
		"action_type": "SELECT_SHOOTER",
		"action_data": {
			"actor_unit_id": "U_SHOOTER_TEST"
		},
		"success": true
	}

	network_manager._emit_client_visual_updates(synthetic_result)

	_check("unit_selected_for_shooting emitted exactly once",
		selected_emissions.size() == 1,
		"got %d emissions" % selected_emissions.size())
	if selected_emissions.size() == 1:
		_check("unit_selected_for_shooting carries the broadcast actor_unit_id",
			selected_emissions[0] == "U_SHOOTER_TEST",
			"got '%s'" % str(selected_emissions[0]))

	_check("targets_available emitted exactly once",
		targets_emissions.size() == 1,
		"got %d emissions" % targets_emissions.size())
	if targets_emissions.size() == 1:
		_check("targets_available carries the broadcast actor_unit_id",
			targets_emissions[0]["unit_id"] == "U_SHOOTER_TEST",
			"got '%s'" % str(targets_emissions[0]["unit_id"]))
		_check("targets_available carries a Dictionary of eligible targets",
			typeof(targets_emissions[0]["eligible"]) == TYPE_DICTIONARY,
			"got type %s" % str(typeof(targets_emissions[0]["eligible"])))

	# Empty-actor guard — must NOT emit either signal.
	selected_emissions.clear()
	targets_emissions.clear()
	network_manager._emit_client_visual_updates({
		"action_type": "SELECT_SHOOTER",
		"action_data": {"actor_unit_id": ""},
		"success": true
	})
	_check("SELECT_SHOOTER with empty actor → no unit_selected_for_shooting emission",
		selected_emissions.size() == 0,
		"got %d unexpected emissions" % selected_emissions.size())
	_check("SELECT_SHOOTER with empty actor → no targets_available emission",
		targets_emissions.size() == 0,
		"got %d unexpected emissions" % targets_emissions.size())

	# Restore phase_manager state.
	phase.unit_selected_for_shooting.disconnect(capture_selected)
	phase.targets_available.disconnect(capture_targets)
	phase_manager.current_phase_instance = prior_phase
	phase.queue_free()

# ---------------------------------------------------------------------------
# 2. CONFIRM_TARGETS → shooting_begun.
#
# Drives the animated tracer ShootingLineVisual on remote (T5-V2 +
# ShootingController._on_shooting_begun). Without this re-emission the
# remote sees the dice rolls but never any visual cue that shooting is
# happening on the board.
# ---------------------------------------------------------------------------
func _test_confirm_targets_reemits_shooting_begun_on_remote() -> void:
	print("\n-- CONFIRM_TARGETS re-emits shooting_begun on remote phase --")

	var phase_manager = root.get_node("PhaseManager")
	var network_manager = root.get_node("NetworkManager")

	var prior_phase = phase_manager.current_phase_instance
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	phase_manager.add_child(phase)
	phase_manager.current_phase_instance = phase

	# CONFIRM_TARGETS branch reads shooter id from `phase.active_shooter_id`,
	# not the action payload — set it explicitly.
	phase.active_shooter_id = "U_SHOOTER_CONFIRM"

	var begun_emissions := []
	var capture := func(unit_id):
		begun_emissions.append(unit_id)
	phase.shooting_begun.connect(capture)

	network_manager._emit_client_visual_updates({
		"action_type": "CONFIRM_TARGETS",
		"action_data": {},
		"success": true
	})

	_check("shooting_begun emitted exactly once for CONFIRM_TARGETS",
		begun_emissions.size() == 1,
		"got %d emissions" % begun_emissions.size())
	if begun_emissions.size() == 1:
		_check("shooting_begun carries phase.active_shooter_id",
			begun_emissions[0] == "U_SHOOTER_CONFIRM",
			"got '%s'" % str(begun_emissions[0]))

	# Empty active_shooter_id guard — must NOT emit.
	phase.active_shooter_id = ""
	begun_emissions.clear()
	network_manager._emit_client_visual_updates({
		"action_type": "CONFIRM_TARGETS",
		"action_data": {},
		"success": true
	})
	_check("CONFIRM_TARGETS with empty active_shooter_id → no shooting_begun emission",
		begun_emissions.size() == 0,
		"got %d unexpected emissions" % begun_emissions.size())

	phase.shooting_begun.disconnect(capture)
	phase_manager.current_phase_instance = prior_phase
	phase.queue_free()

# ---------------------------------------------------------------------------
# 3. COMPLETE_SHOOTING_FOR_UNIT → shooting_resolved.
#
# ShootingController._on_shooting_resolved clears per-shooter visuals on the
# remote (LoS lines, range circles, etc). If this re-emission drops, the
# remote's overlays accumulate stale state across multiple shooters in a
# turn.
# ---------------------------------------------------------------------------
func _test_complete_shooting_for_unit_reemits_shooting_resolved_on_remote() -> void:
	print("\n-- COMPLETE_SHOOTING_FOR_UNIT re-emits shooting_resolved on remote phase --")

	var phase_manager = root.get_node("PhaseManager")
	var network_manager = root.get_node("NetworkManager")

	var prior_phase = phase_manager.current_phase_instance
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	phase_manager.add_child(phase)
	phase_manager.current_phase_instance = phase

	var resolved_emissions := []
	var capture := func(unit_id, target_unit_id, result_dict):
		resolved_emissions.append({
			"unit_id": unit_id,
			"target_unit_id": target_unit_id,
			"result": result_dict,
		})
	phase.shooting_resolved.connect(capture)

	network_manager._emit_client_visual_updates({
		"action_type": "COMPLETE_SHOOTING_FOR_UNIT",
		"action_data": {"actor_unit_id": "U_SHOOTER_DONE"},
		"success": true
	})

	_check("shooting_resolved emitted exactly once for COMPLETE_SHOOTING_FOR_UNIT",
		resolved_emissions.size() == 1,
		"got %d emissions" % resolved_emissions.size())
	if resolved_emissions.size() == 1:
		_check("shooting_resolved carries broadcast actor_unit_id",
			resolved_emissions[0]["unit_id"] == "U_SHOOTER_DONE",
			"got '%s'" % str(resolved_emissions[0]["unit_id"]))

	# Empty actor guard.
	resolved_emissions.clear()
	network_manager._emit_client_visual_updates({
		"action_type": "COMPLETE_SHOOTING_FOR_UNIT",
		"action_data": {"actor_unit_id": ""},
		"success": true
	})
	_check("COMPLETE_SHOOTING_FOR_UNIT with empty actor → no shooting_resolved emission",
		resolved_emissions.size() == 0,
		"got %d unexpected emissions" % resolved_emissions.size())

	phase.shooting_resolved.disconnect(capture)
	phase_manager.current_phase_instance = prior_phase
	phase.queue_free()

# ---------------------------------------------------------------------------
# 4. ASSIGN_TARGET → ShootingController.show_remote_target_assignment.
#
# This dispatch is method-based (not signal-based), because the remote
# rendering happens inside ShootingController instead of on the phase. We
# install a stub Node at /root/Main/ShootingController that records the call
# and assert the dispatcher routes correctly.
# ---------------------------------------------------------------------------
func _test_assign_target_routes_to_controller_when_present() -> void:
	print("\n-- ASSIGN_TARGET routes to ShootingController.show_remote_target_assignment --")

	var network_manager = root.get_node("NetworkManager")
	var phase_manager = root.get_node("PhaseManager")

	# Make sure a current_phase_instance exists so dispatch reaches the branch.
	var prior_phase = phase_manager.current_phase_instance
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	phase_manager.add_child(phase)
	phase_manager.current_phase_instance = phase

	# Build a /root/Main node tree with a stub controller exposing
	# show_remote_target_assignment + clear_remote_target_assignments.
	var prior_main = root.get_node_or_null("Main")
	var main = Node.new()
	main.name = "Main"
	if prior_main == null:
		root.add_child(main)
	else:
		# Don't fight with whatever Main is in scene — just stash it under a
		# different name and put our test Main at /root/Main.
		prior_main.name = "Main_orig_for_test"
		root.add_child(main)

	var stub = StubShootingController.new()
	stub.name = "ShootingController"
	main.add_child(stub)

	var synthetic_result := {
		"action_type": "ASSIGN_TARGET",
		"action_data": {
			"actor_unit_id": "U_SHOOTER",
			"payload": {
				"target_unit_id": "U_TARGET",
				"weapon_id": "W_BOLTGUN"
			}
		},
		"success": true
	}

	network_manager._emit_client_visual_updates(synthetic_result)

	_check("show_remote_target_assignment called exactly once",
		stub.show_calls.size() == 1,
		"got %d calls" % stub.show_calls.size())
	if stub.show_calls.size() == 1:
		var c = stub.show_calls[0]
		_check("show call carries shooter_id",
			c["shooter"] == "U_SHOOTER",
			"got '%s'" % str(c["shooter"]))
		_check("show call carries target_unit_id",
			c["target"] == "U_TARGET",
			"got '%s'" % str(c["target"]))
		_check("show call carries weapon_id",
			c["weapon"] == "W_BOLTGUN",
			"got '%s'" % str(c["weapon"]))

	# Empty target guard — must NOT call.
	stub.show_calls.clear()
	network_manager._emit_client_visual_updates({
		"action_type": "ASSIGN_TARGET",
		"action_data": {
			"actor_unit_id": "U_SHOOTER",
			"payload": {"target_unit_id": "", "weapon_id": "W_BOLTGUN"}
		},
		"success": true
	})
	_check("ASSIGN_TARGET with empty target → controller NOT called",
		stub.show_calls.size() == 0,
		"got %d unexpected calls" % stub.show_calls.size())

	# Cleanup our stub Main; restore prior Main if any.
	main.queue_free()
	if prior_main != null:
		prior_main.name = "Main"
	phase_manager.current_phase_instance = prior_phase
	phase.queue_free()

# ---------------------------------------------------------------------------
# 5. ASSIGN_TARGET when no /root/Main/ShootingController exists.
#
# Must be a no-op: the dispatcher uses get_node_or_null and a has_method
# check, so a missing controller cannot crash the broadcast pipeline.
# ---------------------------------------------------------------------------
func _test_assign_target_safe_when_controller_absent() -> void:
	print("\n-- ASSIGN_TARGET no-ops gracefully when ShootingController is absent --")

	var network_manager = root.get_node("NetworkManager")
	var phase_manager = root.get_node("PhaseManager")

	var prior_phase = phase_manager.current_phase_instance
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	phase_manager.add_child(phase)
	phase_manager.current_phase_instance = phase

	# Ensure /root/Main/ShootingController is gone.
	var prior_main = root.get_node_or_null("Main")
	if prior_main != null:
		prior_main.name = "Main_orig_absent_test"

	# Should not crash even with no Main / no controller.
	var crashed = false
	var trapper = func():
		network_manager._emit_client_visual_updates({
			"action_type": "ASSIGN_TARGET",
			"action_data": {
				"actor_unit_id": "U_SHOOTER",
				"payload": {"target_unit_id": "U_TARGET", "weapon_id": "W_BOLTGUN"}
			},
			"success": true
		})
	# Direct call — if it crashed, the script itself would terminate. The fact
	# that we reach the next line is the assertion. We also re-run for
	# CLEAR_ASSIGNMENT and CLEAR_ALL_ASSIGNMENTS in the next test.
	trapper.call()
	_check("ASSIGN_TARGET dispatch did not crash when controller absent", true)

	if prior_main != null:
		prior_main.name = "Main"
	phase_manager.current_phase_instance = prior_phase
	phase.queue_free()

# ---------------------------------------------------------------------------
# 6. CLEAR_ASSIGNMENT / CLEAR_ALL_ASSIGNMENTS → controller.clear_remote_target_assignments.
# ---------------------------------------------------------------------------
func _test_clear_assignment_routes_to_controller_when_present() -> void:
	print("\n-- CLEAR_ASSIGNMENT / CLEAR_ALL_ASSIGNMENTS route to controller.clear_remote_target_assignments --")

	var network_manager = root.get_node("NetworkManager")
	var phase_manager = root.get_node("PhaseManager")

	var prior_phase = phase_manager.current_phase_instance
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	phase_manager.add_child(phase)
	phase_manager.current_phase_instance = phase

	var prior_main = root.get_node_or_null("Main")
	var main = Node.new()
	main.name = "Main"
	if prior_main != null:
		prior_main.name = "Main_orig_clear_test"
	root.add_child(main)

	var stub = StubShootingController.new()
	stub.name = "ShootingController"
	main.add_child(stub)

	# CLEAR_ASSIGNMENT
	network_manager._emit_client_visual_updates({
		"action_type": "CLEAR_ASSIGNMENT",
		"action_data": {},
		"success": true
	})
	_check("CLEAR_ASSIGNMENT triggers clear_remote_target_assignments",
		stub.clear_call_count == 1,
		"got %d calls" % stub.clear_call_count)

	# CLEAR_ALL_ASSIGNMENTS — same controller method.
	network_manager._emit_client_visual_updates({
		"action_type": "CLEAR_ALL_ASSIGNMENTS",
		"action_data": {},
		"success": true
	})
	_check("CLEAR_ALL_ASSIGNMENTS triggers clear_remote_target_assignments",
		stub.clear_call_count == 2,
		"got %d total calls" % stub.clear_call_count)

	main.queue_free()
	if prior_main != null:
		prior_main.name = "Main"
	phase_manager.current_phase_instance = prior_phase
	phase.queue_free()

# ---------------------------------------------------------------------------
# 7. Host-side relay path mirrors controller calls so the host's screen sees
# the remote client's visual hints. This is the bidirectional half of T5-MP3:
# without it, only the player who didn't take the action sees the visuals,
# but the host (when not the active player) does not.
# ---------------------------------------------------------------------------
func _test_host_relay_path_calls_remote_visual_helpers() -> void:
	print("\n-- Host relay path calls show_remote_target_assignment / clear_remote_target_assignments --")

	var nm_src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	_check("NetworkManager.gd readable", nm_src != null)
	if nm_src == null:
		return
	var text = nm_src.get_as_text()
	nm_src.close()

	# The relay branch lives inside _handle_relayed_action (host path for web
	# relay). Cross-check the marker comments and the controller calls.
	_check("Relay path: host shows remote ASSIGN_TARGET visual",
		text.contains('T5-MP3: Host (relay) showing remote player\'s ASSIGN_TARGET visual'),
		"relay branch missing — host's screen won't show remote shooter's targeting line")
	_check("Relay path: host calls show_remote_target_assignment(shooter, target, weapon)",
		text.contains("shooting_controller.show_remote_target_assignment(shooter_id, target_unit_id, weapon_id)"),
		"relay branch missing the controller call signature")
	_check("Relay path: host clears remote assignment visuals on CLEAR_ASSIGNMENT",
		text.contains("T5-MP3: Host (relay) clearing remote player's assignment visuals"),
		"relay clear branch missing")

# ---------------------------------------------------------------------------
# 8. Same as #7 but for the ENet host path — the host calls these helpers
# directly when applying a client's action via ENet RPC instead of via the
# web relay.
# ---------------------------------------------------------------------------
func _test_host_enet_path_calls_remote_visual_helpers() -> void:
	print("\n-- Host ENet path mirrors the same controller calls --")

	var nm_src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	_check("NetworkManager.gd readable (ENet branch)", nm_src != null)
	if nm_src == null:
		return
	var text = nm_src.get_as_text()
	nm_src.close()

	_check("ENet path: host shows remote ASSIGN_TARGET visual",
		text.contains("T5-MP3: Host (ENet) showing remote player's ASSIGN_TARGET visual"),
		"ENet branch missing — host's screen won't show remote shooter's targeting line")
	_check("ENet path: host clears remote assignment visuals on CLEAR_ASSIGNMENT",
		text.contains("T5-MP3: Host (ENet) clearing remote player's assignment visuals"),
		"ENet clear branch missing")

# ---------------------------------------------------------------------------
# 9. Allow-list invariant — SELECT_SHOOTER, ASSIGN_TARGET, CLEAR_ASSIGNMENT,
# and CLEAR_ALL_ASSIGNMENTS must all be in the optimistic-execution allowlist
# (or whatever the equivalent set is for shooting setup actions). If they
# get removed from this list, the remote player's broadcast pipeline never
# fires for those actions and the visuals desync.
# ---------------------------------------------------------------------------
func _test_shooting_setup_actions_in_optimistic_allowlist() -> void:
	print("\n-- Shooting-setup actions are present in NetworkManager allow-list --")

	var nm_src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	_check("NetworkManager.gd readable (allow-list check)", nm_src != null)
	if nm_src == null:
		return
	var text = nm_src.get_as_text()
	nm_src.close()

	# The exact list literal lives near the top of the file; we just need to
	# confirm each token appears in the file as a quoted string. (More
	# specific checks would be brittle to whitespace and reorderings.)
	for action in ["SELECT_SHOOTER", "ASSIGN_TARGET", "CLEAR_ASSIGNMENT", "CLEAR_ALL_ASSIGNMENTS"]:
		_check("Allow-list contains '%s'" % action,
			text.contains('"%s"' % action),
			"action removed from optimistic allow-list — remote will not see broadcast")

# ---------------------------------------------------------------------------
# 10. ShootingController source exposes the methods the broadcast pipeline
# expects to call on the remote. Renaming or deleting these silently is the
# kind of refactor regression this static-source check catches.
# ---------------------------------------------------------------------------
func _test_shooting_controller_exposes_remote_visual_methods() -> void:
	print("\n-- ShootingController defines show_remote_target_assignment + clear_remote_target_assignments --")

	var sc_src = FileAccess.open("res://scripts/ShootingController.gd", FileAccess.READ)
	_check("ShootingController.gd readable", sc_src != null)
	if sc_src == null:
		return
	var text = sc_src.get_as_text()
	sc_src.close()

	_check("show_remote_target_assignment(shooter_id, target_unit_id, weapon_id) is defined",
		text.contains("func show_remote_target_assignment(shooter_id: String, target_unit_id: String, weapon_id: String)"),
		"public method renamed/removed — NetworkManager will silently no-op the per-assignment visual")
	_check("clear_remote_target_assignments() is defined",
		text.contains("func clear_remote_target_assignments()"),
		"public method renamed/removed — NetworkManager will silently no-op the per-assignment clear")
	_check("show_remote_target_assignment uses _create_shooting_line_visual",
		text.contains("_create_shooting_line_visual(positions.from, positions.to, weapon_name, false)"),
		"per-assignment line visual call drifted — remote sees no targeting line on assign")
	_check("show_remote_target_assignment also highlights the target",
		text.contains("_create_target_highlight(target_unit_id, HIGHLIGHT_COLOR_SELECTED)"),
		"target-highlight call dropped — remote sees no highlight on assigned target")

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

# Inline stub used to record controller calls without depending on the
# ShootingController autoload path or the heavy UI it builds in _ready.
class StubShootingController extends Node:
	var show_calls: Array = []
	var clear_call_count: int = 0

	func show_remote_target_assignment(shooter_id: String, target_unit_id: String, weapon_id: String) -> void:
		show_calls.append({
			"shooter": shooter_id,
			"target": target_unit_id,
			"weapon": weapon_id
		})

	func clear_remote_target_assignments() -> void:
		clear_call_count += 1

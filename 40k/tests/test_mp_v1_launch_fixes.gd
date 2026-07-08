extends SceneTree

# Multiplayer v1.0 launch-readiness fixes — regression net.
#
# Pins the contracts introduced by the 2026-07 multiplayer hardening pass.
# Each of these guarded a LIVE, reproduced failure in a two-instance ENet
# game (see version_history entry for the play-facing summary):
#
#   A) Roll-off phases expose roll_off_result and validate the choose action
#      (MP-1: every LAN game soft-locked at the deployment roll-off).
#   B) GameManager delegates unknown action types to the current phase
#      (MP-8: END_SCOUT_PHASE, DECLINE_COMMAND_REROLL, END_PILE_IN,
#      USE_COUNTER_OFFENSIVE, ... all hard-failed in multiplayer only).
#   C) NetworkManager exempts reactive/cross-turn actions from turn
#      validation (roll-off completions + reactive stratagem windows).
#   D) PhaseManager: clients never self-advance phases; outgoing phase
#      instances are disconnected before queue_free (MP-5: stale deferred
#      phase_completed skipped FIRST_TURN_ROLLOFF and cascaded clients
#      through COMMAND→CHARGE alone).
#   E) compute_state_hash hashes the canonical gameplay subset (MP-2: the
#      full-state hash could never match after a snapshot sync, so the
#      desync detector cried wolf on every check).
#   F) Multiplayer lobby reloads the terrain layout on the host (MP-3: host
#      adjudicated terrain rules against an empty board.terrain).
#
# Usage: godot --headless --path . -s tests/test_mp_v1_launch_fixes.gd

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
	print("\n=== test_mp_v1_launch_fixes ===\n")

	print("-- A: roll-off result signal + winner-gated choice --")
	var roll_off_script = load("res://phases/RollOffPhase.gd")
	var ftro_script = load("res://phases/FirstTurnRollOffPhase.gd")
	var ro = roll_off_script.new()
	_check("RollOffPhase declares roll_off_result", ro.has_signal("roll_off_result"))
	var ftro = ftro_script.new()
	_check("FirstTurnRollOffPhase declares roll_off_result", ftro.has_signal("roll_off_result"))

	# Behavioral: CHOOSE_DEPLOYMENT winner enforcement.
	ro._roll_complete = true
	ro._roll_off_winner = 1
	var v_wrong = ro.validate_action({"type": "CHOOSE_DEPLOYMENT", "choice": "first", "player": 2})
	_check("CHOOSE_DEPLOYMENT by non-winner rejected", not v_wrong.get("valid", true))
	var v_right = ro.validate_action({"type": "CHOOSE_DEPLOYMENT", "choice": "first", "player": 1})
	_check("CHOOSE_DEPLOYMENT by winner accepted", v_right.get("valid", false),
		str(v_right.get("errors", [])))
	var v_unstamped = ro.validate_action({"type": "CHOOSE_DEPLOYMENT", "choice": "second"})
	_check("CHOOSE_DEPLOYMENT without player accepted (SP/test dispatch)",
		v_unstamped.get("valid", false), str(v_unstamped.get("errors", [])))
	ro.free()
	ftro.free()

	print("\n-- B: GameManager delegates unknown actions to the phase --")
	var gm_src = FileAccess.get_file_as_string("res://autoloads/GameManager.gd")
	_check("default arm delegates instead of hard-failing",
		gm_src.find("not handled directly — delegating to current phase") != -1)
	_check("old unconditional unknown-action failure removed",
		gm_src.find('return {"success": false, "error": "Unknown action type: " + str(action.get("type", "UNKNOWN"))}') == -1)

	print("\n-- C: reactive/cross-turn actions exempt from turn validation --")
	var nm_src = FileAccess.get_file_as_string("res://autoloads/NetworkManager.gd")
	for a in ["CHOOSE_DEPLOYMENT", "CONFIRM_FIRST_TURN", "USE_EPIC_CHALLENGE",
			"DECLINE_EPIC_CHALLENGE", "USE_COUNTER_OFFENSIVE", "DECLINE_COUNTER_OFFENSIVE",
			"USE_FIRE_OVERWATCH", "DECLINE_FIRE_OVERWATCH", "USE_COMMAND_REROLL",
			"DECLINE_COMMAND_REROLL"]:
		_check("exempt list contains %s" % a, nm_src.find('"%s"' % a) != -1)
	_check("roll_off_result re-emitted for clients",
		nm_src.find('phase.emit_signal("roll_off_result"') != -1)
	_check("epic_challenge_opportunity re-emitted for clients",
		nm_src.find('phase.emit_signal("epic_challenge_opportunity"') != -1)
	_check("client-action broadcasts carry state hash",
		nm_src.find("result[\"_state_hash\"] = compute_state_hash()\n\t\t_broadcast_result.rpc(result)") != -1)

	print("\n-- D: phase-advance hardening --")
	var pm_src = FileAccess.get_file_as_string("res://autoloads/PhaseManager.gd")
	_check("client phase_completed suppression present",
		pm_src.find("phase_completed on CLIENT — waiting for host to advance") != -1)
	_check("outgoing phase signals disconnected before queue_free",
		pm_src.find("current_phase_instance.phase_completed.disconnect(_on_phase_completed)") != -1)
	var main_src = FileAccess.get_file_as_string("res://scripts/Main.gd")
	_check("Main skips duplicate phase transition",
		main_src.find("skipping duplicate transition") != -1)
	_check("Main gates phase action button on local turn",
		main_src.find("Phase action button blocked — not local player's turn") != -1)

	print("\n-- E: canonical state hash --")
	var nm = root.get_node_or_null("NetworkManager")
	var gs = root.get_node_or_null("GameState")
	if nm and gs:
		# Enrichment keys that only exist on snapshot-loaded peers must not
		# affect the hash — that asymmetry meant host/client hashes never matched.
		var h1 = nm.compute_state_hash()
		gs.state["mission_manager"] = {"only": "on snapshot-loaded peers"}
		gs.state["phase_log"] = ["local", "noise"]
		var h2 = nm.compute_state_hash()
		gs.state.erase("mission_manager")
		gs.state.erase("phase_log")
		_check("hash ignores snapshot-enrichment/local-noise keys", h1 == h2,
			"h1=%d h2=%d" % [h1, h2])
		# ...while genuinely divergent unit state must change it.
		var had_units = gs.state.has("units")
		if had_units:
			gs.state.units["__mp_test_unit"] = {"owner": 1}
			var h3 = nm.compute_state_hash()
			gs.state.units.erase("__mp_test_unit")
			_check("hash reacts to unit divergence", h1 != h3)
	else:
		_check("NetworkManager+GameState autoloads reachable", false)

	print("\n-- F: lobby reloads terrain on host --")
	var lobby_src = FileAccess.get_file_as_string("res://scripts/MultiplayerLobby.gd")
	_check("host terrain reload present in _do_start_game",
		lobby_src.find("Reloaded terrain layout") != -1)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

extends RefCounted
class_name GameWatcher

# PM-8b — watch one running AI-vs-AI game to completion, or to a diagnosis.
#
# Extracted from the PM-8a spike driver so the simulator does not carry its own
# copy of the stall/timeout logic. The distinction it draws is the useful one:
#
#   completed  PhaseManager.game_ended went true
#   timeout    the game is still moving, but has taken too long overall
#   stalled    the game has stopped moving — same round / phase / action count
#              for `stall_seconds`. This is a BUG signature, not slowness, and
#              conflating it with a timeout hides real hangs.
#
# `AIBenchmarkRunner` still has its own copy of this loop
# (AIBenchmarkRunner.gd:374-407). Migrating it was left alone deliberately:
# it is the harness the project's bench baselines come from, and changing it
# to prove a point about code sharing is a worse trade than one duplicated
# 40-line loop. This helper is written to be adoptable when that harness is
# next touched for its own reasons.

## Progress signature: while this string keeps changing, the game is alive.
static func progress_signature(game_state, ai_player) -> String:
	var actions := 0
	if ai_player != null and "_action_log" in ai_player:
		actions = ai_player._action_log.size()
	return "%d|%d|%d" % [game_state.get_battle_round(), game_state.get_current_phase(), actions]


## Await one game. `on_progress` (optional) is called with
## (elapsed_seconds, battle_round, phase, actions) each time the signature moves.
## Returns {status, note, battle_round, phase, actions, wall_seconds}.
static func watch(tree: SceneTree, opts: Dictionary = {}) -> Dictionary:
	var max_seconds: float = float(opts.get("max_seconds", 600.0))
	var stall_seconds: float = float(opts.get("stall_seconds", 90.0))
	var poll_seconds: float = float(opts.get("poll_seconds", 0.5))
	var on_progress: Callable = opts.get("on_progress", Callable())
	var should_cancel: Callable = opts.get("should_cancel", Callable())

	var root := tree.root
	var game_state = root.get_node_or_null("GameState")
	var phase_manager = root.get_node_or_null("PhaseManager")
	var ai_player = root.get_node_or_null("AIPlayer")
	if game_state == null or phase_manager == null:
		return {"status": "error", "note": "GameState/PhaseManager missing",
			"battle_round": 0, "phase": -1, "actions": 0, "wall_seconds": 0.0}

	var start_ticks := Time.get_ticks_msec()
	var last_signature := ""
	var last_progress_ticks := start_ticks
	var status := "unknown"
	var note := ""

	while true:
		await tree.create_timer(poll_seconds).timeout
		var elapsed := (Time.get_ticks_msec() - start_ticks) / 1000.0

		if should_cancel.is_valid() and bool(should_cancel.call()):
			status = "cancelled"
			note = "cancelled at round %d" % game_state.get_battle_round()
			break
		if phase_manager.game_ended:
			status = "completed"
			break
		if elapsed > max_seconds:
			status = "timeout"
			note = "max_seconds %.0f exceeded at round %d" % [max_seconds, game_state.get_battle_round()]
			break

		var signature := progress_signature(game_state, ai_player)
		if signature != last_signature:
			last_signature = signature
			last_progress_ticks = Time.get_ticks_msec()
			if on_progress.is_valid():
				on_progress.call(elapsed, game_state.get_battle_round(),
					game_state.get_current_phase(),
					ai_player._action_log.size() if ai_player != null else 0)
		elif (Time.get_ticks_msec() - last_progress_ticks) / 1000.0 > stall_seconds:
			status = "stalled"
			note = "no progress for %.0fs at %s" % [stall_seconds, signature]
			break

	return {
		"status": status,
		"note": note,
		"battle_round": game_state.get_battle_round(),
		"phase": game_state.get_current_phase(),
		"actions": ai_player._action_log.size() if ai_player != null else 0,
		"wall_seconds": (Time.get_ticks_msec() - start_ticks) / 1000.0,
	}

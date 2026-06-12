class_name ReplayVerifier
extends RefCounted

## Deterministic replay of an ActionLogger bundle (ISS-021).
##
## Restores the bundle's initial snapshot, re-executes every logged action
## through the real pipeline (PhaseManager phase instances; payload
## rng_seeds make every dice roll reproduce), and compares the resulting
## state hash with the recorded one. This is the foundation the
## golden-master harness (ISS-029) records full games onto.

## Replays `bundle` against live autoloads. DESTRUCTIVE to current
## GameState — callers snapshot/restore around it (tests do).
## Returns {ok, replayed_hash, recorded_hash, failures: [per-action errors]}.
static func replay(bundle: Dictionary) -> Dictionary:
	var failures: Array = []
	var snapshot = bundle.get("initial_snapshot", {})
	if snapshot.is_empty():
		return {"ok": false, "failures": ["bundle has no initial_snapshot"]}

	GameState.state = snapshot.duplicate(true)
	var phase_at_start = int(GameState.state.get("meta", {}).get("phase", 0))
	PhaseManager.transition_to_phase(phase_at_start)

	for entry in bundle.get("actions", []):
		var action = entry.duplicate(true)
		# Strip logger enrichment and replay-irrelevant keys that handlers
		# don't expect back.
		for k in ["_log_metadata", "_replay_diffs", "_log_text"]:
			action.erase(k)
		var atype = str(action.get("type", ""))
		if atype == "PHASE_CHANGE" or atype == "":
			continue  # transitions re-derive from the actions themselves
		var phase = PhaseManager.get_current_phase_instance()
		if phase == null:
			failures.append("%s: no phase instance" % atype)
			continue
		var result = phase.execute_action(action)
		if not (result is Dictionary and result.get("success", false)):
			failures.append("%s: %s" % [atype, str(result)])

	var replayed_hash = ActionLogger.replay_hash(GameState.state)
	var recorded_hash = int(bundle.get("final_replay_hash", 0))
	return {
		"ok": failures.is_empty() and replayed_hash == recorded_hash,
		"replayed_hash": replayed_hash,
		"recorded_hash": recorded_hash,
		"failures": failures,
	}

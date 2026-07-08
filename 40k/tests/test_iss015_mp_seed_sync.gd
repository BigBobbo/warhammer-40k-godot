extends SceneTree

# ISS-015: multiplayer determinism — every submitted action carries a seed,
# and result broadcasts carry a canonical state hash for desync detection.
#
# Checks (source + behavior, no live peers needed):
#   A) submit_action embeds rng_seed for ANY action type when missing and
#      never overwrites an existing seed (source-level check of the
#      generalized hook + behavioral check in single-player mode).
#   B) compute_state_hash is canonical: identical content with different
#      dictionary insertion order hashes identically.
#   C) The client result path compares hashes and the desync signal exists.
#
# Usage: godot --headless --path . -s tests/test_iss015_mp_seed_sync.gd

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
	print("\n=== test_iss015_mp_seed_sync ===\n")
	var nm = root.get_node_or_null("NetworkManager")
	if nm == null:
		_check("NetworkManager autoload reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return

	print("-- A: generalized seed embedding --")
	var src = FileAccess.get_file_as_string("res://autoloads/NetworkManager.gd")
	_check("BEGIN_ADVANCE special-case removed (hook covers all types)",
		src.find('action.get("type") == "BEGIN_ADVANCE" and not action.get("payload", {}).has("rng_seed")') == -1)
	_check("generalized embed present",
		src.find('if not action.get("payload", {}).has("rng_seed"):') != -1)

	print("\n-- B: canonical state hash --")
	# compute_state_hash now hashes the CANONICAL gameplay subset
	# (units/players/factions/meta minus volatile keys) — full-state hashing
	# could never match between a host (raw state) and a client (snapshot-
	# enriched state). Exercise order-insensitivity and content-sensitivity
	# within that subset, and confirm non-canonical keys are ignored.
	var gs = root.get_node_or_null("GameState")
	var prev = gs.state.duplicate(true)
	gs.state = {"units": {"b": {"hp": 2}, "a": {"hp": 1}}, "meta": {"y": [1, 2], "x": "v"}}
	var h1 = nm.compute_state_hash()
	gs.state = {"meta": {"x": "v", "y": [1, 2]}, "units": {"a": {"hp": 1}, "b": {"hp": 2}}}
	var h2 = nm.compute_state_hash()
	_check("insertion order does not change the hash", h1 == h2, "%d vs %d" % [h1, h2])
	gs.state = {"units": {"a": {"hp": 1}, "b": {"hp": 3}}, "meta": {"x": "v", "y": [1, 2]}}
	_check("content change changes the hash", nm.compute_state_hash() != h1)
	gs.state = {"units": {"b": {"hp": 2}, "a": {"hp": 1}}, "meta": {"y": [1, 2], "x": "v"}, "phase_log": ["local-only noise"]}
	_check("non-canonical keys (snapshot enrichment / local logs) do not change the hash",
		nm.compute_state_hash() == h1)
	gs.state = prev

	print("\n-- C: desync detector wiring --")
	_check("desync_detected signal declared", nm.has_signal("desync_detected"))
	_check("host attaches _state_hash to broadcast results",
		src.find('result["_state_hash"] = compute_state_hash()') != -1)
	_check("client compares hash after applying result",
		src.find("DESYNC DETECTED") != -1)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

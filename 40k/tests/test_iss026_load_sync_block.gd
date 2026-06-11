extends SceneTree

# ISS-026: a failed multiplayer load sync must not continue silently.
# On ack timeout the host retries the snapshot send (up to 3x) and blocks
# action submission until peers confirm; success unblocks and resets.
#
# Usage: godot --headless --path . -s tests/test_iss026_load_sync_block.gd

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
	print("\n=== test_iss026_load_sync_block ===\n")
	var nm = root.get_node_or_null("NetworkManager")
	if nm == null:
		_check("NetworkManager reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return

	_check("starts unblocked", nm._load_sync_blocked == false)

	# Exhausted-retries path first (no resend fires on this branch — in the
	# offline test env an rpc_id executes locally and would self-ack).
	nm._load_sync_pending_acks = {2: false}
	nm._load_sync_retries = nm.LOAD_SYNC_MAX_RETRIES
	nm._on_load_sync_timeout()
	_check("after max retries still blocked (failure surfaced)",
		nm._load_sync_blocked == true)

	# Retry path: blocks and increments. (The resend self-acks in offline
	# mode — equivalent to the peer confirming — so only the retry counter
	# and the momentary block are assertable here.)
	nm._load_sync_blocked = false
	nm._load_sync_pending_acks = {2: false}
	nm._load_sync_retries = 0
	nm._on_load_sync_timeout()
	_check("timeout with retries left schedules retry", nm._load_sync_retries == 1)

	# All peers confirm -> unblock via the success path
	nm._load_sync_pending_acks = {2: true}
	nm._check_all_load_acks_received()
	_check("all-acks success unblocks and resets retries",
		nm._load_sync_blocked == false and nm._load_sync_retries == 0)

	# Cleanup
	nm._load_sync_pending_acks = {}
	nm._stop_load_sync_timer()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

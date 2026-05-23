extends SceneTree

# Regression test for the "Downloading armies..." freeze when both players
# select a cloud-saved army list.
#
# Bug: ArmyListManager.fetch_cloud_army() previously tracked the in-flight
# request with a single _pending_cloud_fetch String. When the lobby called
# fetch_cloud_army() twice in a row (one per player), the second call
# overwrote the first; when the first HTTP response arrived,
# _on_cloud_army_downloaded() saw army_name != _pending_cloud_fetch and
# never emitted cloud_army_fetched. The lobby's _cloud_fetch_count never
# decremented to zero, so the game never started.
#
# Fix: _pending_cloud_fetches is now Dictionary<army_name, player>, so
# every in-flight download can be matched on completion.
#
# Usage: godot --headless --path . -s tests/test_cloud_army_dual_fetch.gd

var passed := 0
var failed := 0
var received: Array = []  # [{name, player_owner_of_first_unit}]


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init():
	create_timer(0.1).timeout.connect(_run_tests)


func _run_tests() -> void:
	if passed > 0 or failed > 0:
		return
	print("\n=== test_cloud_army_dual_fetch ===\n")
	_test_dual_pending_fetch_completes_both()
	_test_failure_clears_all_pending()
	_finish()


func _on_fetched(army_name: String, army_data: Dictionary) -> void:
	# Capture the player by inspecting the first unit's owner (set by _process_army_data).
	var first_owner = -1
	if army_data.has("units") and army_data.units is Dictionary:
		for unit_id in army_data.units:
			first_owner = army_data.units[unit_id].get("owner", -1)
			break
	received.append({"name": army_name, "owner": first_owner})


func _on_fetch_failed(army_name: String, _error: String) -> void:
	received.append({"name": army_name, "owner": -999})


func _test_dual_pending_fetch_completes_both() -> void:
	print("\n-- dual pending fetches both emit cloud_army_fetched --")
	var alm = root.get_node_or_null("ArmyListManager")
	_check("ArmyListManager autoload present", alm != null)
	if alm == null:
		return

	received.clear()
	alm.cloud_army_cache.clear()
	alm._pending_cloud_fetches.clear()
	if not alm.cloud_army_fetched.is_connected(_on_fetched):
		alm.cloud_army_fetched.connect(_on_fetched)

	# Seed two in-flight fetches directly (bypassing CloudStorage HTTP layer).
	alm._pending_cloud_fetches["ArmyA"] = 1
	alm._pending_cloud_fetches["ArmyB"] = 2

	var sample_units = {"u1": {"status": "UNDEPLOYED", "models": []}}
	alm._on_cloud_army_downloaded("ArmyA", {"units": sample_units.duplicate(true)})
	alm._on_cloud_army_downloaded("ArmyB", {"units": sample_units.duplicate(true)})

	_check("two cloud_army_fetched signals fired", received.size() == 2,
		"got %d" % received.size())
	var saw_a := false
	var saw_b := false
	for r in received:
		if r.name == "ArmyA":
			saw_a = true
			_check("ArmyA processed for player 1", r.owner == 1, "owner=%d" % r.owner)
		elif r.name == "ArmyB":
			saw_b = true
			_check("ArmyB processed for player 2", r.owner == 2, "owner=%d" % r.owner)
	_check("ArmyA signal received", saw_a)
	_check("ArmyB signal received", saw_b)
	_check("pending dict drained", alm._pending_cloud_fetches.is_empty())


func _test_failure_clears_all_pending() -> void:
	print("\n-- get_army failure fails all in-flight fetches --")
	var alm = root.get_node_or_null("ArmyListManager")
	if alm == null:
		return

	received.clear()
	alm._pending_cloud_fetches.clear()
	if not alm.cloud_army_fetch_failed.is_connected(_on_fetch_failed):
		alm.cloud_army_fetch_failed.connect(_on_fetch_failed)

	alm._pending_cloud_fetches["ArmyA"] = 1
	alm._pending_cloud_fetches["ArmyB"] = 2

	alm._on_cloud_request_failed("get_army", "boom")

	_check("two cloud_army_fetch_failed signals fired", received.size() == 2,
		"got %d" % received.size())
	_check("pending dict cleared on failure", alm._pending_cloud_fetches.is_empty())


func _finish() -> void:
	print("\n=== Summary: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

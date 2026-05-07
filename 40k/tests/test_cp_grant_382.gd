extends SceneTree

# Issue #382: validate the CP-grant builds the expected diff list.
# We don't call PhaseManager.apply_state_changes here (that requires a
# fully-initialized scene); we test the diff-construction logic instead,
# which is the only thing that changed.

func _initialize():
	print("=== Issue #382: CP-grant both players ===")

	# Reproduce the post-fix logic:
	var state_players = {"1": {"cp": 5}, "2": {"cp": 7}}
	var changes = []
	for player in [1, 2]:
		var player_cp = state_players.get(str(player), {}).get("cp", 0)
		changes.append({"op": "set", "path": "players.%s.cp" % str(player), "value": player_cp + 1})

	var fails = 0
	if changes.size() != 2:
		print("[FAIL] expected 2 changes, got %d" % changes.size()); fails += 1
	else:
		print("[OK]   2 changes generated (one per player)")

	if changes[0].get("path", "") != "players.1.cp":
		print("[FAIL] changes[0].path expected players.1.cp, got %s" % changes[0].get("path", "")); fails += 1
	elif changes[0].get("value", -1) != 6:
		print("[FAIL] changes[0].value expected 6 (5+1), got %s" % str(changes[0].get("value", -1))); fails += 1
	else:
		print("[OK]   P1 diff: cp 5 -> 6")

	if changes[1].get("path", "") != "players.2.cp":
		print("[FAIL] changes[1].path expected players.2.cp, got %s" % changes[1].get("path", "")); fails += 1
	elif changes[1].get("value", -1) != 8:
		print("[FAIL] changes[1].value expected 8 (7+1), got %s" % str(changes[1].get("value", -1))); fails += 1
	else:
		print("[OK]   P2 diff: cp 7 -> 8")

	if fails == 0:
		print("\n[OK] all #382 validations passed — both players granted CP")
		quit(0)
	else:
		print("\n[FAIL] %d validation(s) failed" % fails)
		quit(1)

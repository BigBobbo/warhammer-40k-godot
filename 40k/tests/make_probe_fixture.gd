extends SceneTree

# Build a diagnostic variant of an existing fixture by removing one player's
# army, so a benchmark run isolates "what does this army cost on its own".
#
# Why this exists: mirror_orks_2000_postdeploy cannot finish a game, while
# asym_2000_postdeploy — which contains the SAME 77-model Ork army — finishes
# in 266 s. The armies are ~20-30 inches apart at round 1, so an Ork unit's
# first move cannot be blocked by an enemy model. That points at the Ork army
# obstructing ITSELF, and the question becomes why that is survivable in one
# fixture and not the other. Deleting the opposing army answers it directly:
# if the grind survives with no enemy on the table, the enemy was never
# relevant.
#
# Usage:
#   godot --headless --path 40k -s tests/make_probe_fixture.gd -- \
#       --from=mirror_orks_2000_postdeploy --kill=2 --out=probe_orks_p1_only

var GS = null
var _from := ""
var _out := ""
var _kill := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="): _from = a.split("=", true, 1)[1]
		elif a.begins_with("--out="): _out = a.split("=", true, 1)[1]
		elif a.begins_with("--kill="): _kill = int(a.split("=", true, 1)[1])
		else:
			printerr("[probe] FAIL: unrecognised argument %r" % a)
			quit(2)
			return
	if _from == "" or _out == "" or _kill not in [1, 2]:
		printerr("usage: --from=<fixture> --kill=<1|2> --out=<name>")
		quit(2)
		return
	await create_timer(0.5).timeout
	_build()


func _build() -> void:
	var slm = root.get_node_or_null("SaveLoadManager")
	GS = root.get_node_or_null("GameState")
	if slm == null or GS == null:
		printerr("[probe] FAIL: autoload missing")
		quit(1)
		return
	if not slm.load_game(_from):
		printerr("[probe] FAIL: could not load %s" % _from)
		quit(1)
		return

	var removed := 0
	var kept := 0
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		if int(u.get("owner", 0)) == _kill:
			# Off the table entirely rather than "dead in place": a dead model
			# still sitting at a position would keep showing up in obstacle
			# lists and defeat the point of the probe.
			u["status"] = 7  # UnitStatus.IN_RESERVES
			for m in u.get("models", []):
				m["alive"] = false
				m["position"] = null
			removed += 1
		else:
			kept += 1
	print("[probe] %s: removed P%d (%d units), kept %d units" % [_from, _kill, removed, kept])

	var ss = root.get_node_or_null("StateSerializer")
	if ss != null:
		ss.set_compression_enabled(false)
	if not slm.save_game(_out):
		printerr("[probe] FAIL: save_game(%r) returned false" % _out)
		quit(1)
		return
	print("[probe] wrote %s" % _out)
	quit(0)

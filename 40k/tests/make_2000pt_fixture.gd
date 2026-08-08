extends SceneTree

# Build a benchmark fixture from SHIPPED 2000-point army lists.
#
# Why this exists, and why it is not the Python generator next door:
# `make_mirror_fixture.py` mirrors an army that is already inside an existing
# save. That was fine when the only armies available were the ones baked into
# `audit_baseline_postdeploy` — but those are a hand-built benchmark save at
# 1335 and 1840 points, not rosters anyone plays. 40k is balanced at 2000, so
# every number the lab has ever produced came from a format the game is not
# designed around.
#
# Starting from the army-list JSON instead means the units must go through
# `ArmyListManager.load_army_list`, which is the whole point: display names,
# ability canonicalisation, wargear and enhancement stat bonuses, model-profile
# wounds, model-count correction and the Custodes deep-strike backfill all
# happen there. Hand-splicing JSON would silently skip every one of them and
# produce units the game would never create.
#
# What is kept from the shell save: board size, terrain, objectives, deployment
# zones, mission and the secondary deck. Those are validated and the AI depends
# on them, and none of them are army-specific.
#
# Usage:
#   godot --headless --path 40k -s tests/make_2000pt_fixture.gd -- \
#       --p1=custodes_lions --p2=recon_stomps --out=asym_2000_postdeploy
#   godot --headless --path 40k -s tests/make_2000pt_fixture.gd -- \
#       --mirror=custodes_lions --out=mirror_custodes_2000_postdeploy
#
# --mirror places the SAME list on both sides and rotates player 2's deployment
# 180 degrees about the board centre, so the only asymmetry left is who goes
# first. Packing each side independently would not be a mirror — it would be
# two armies in two zones, and the fixture's structural bias F would stop being
# interpretable.

const SHELL := "mirror_custodes_postdeploy"   # board, terrain, objectives, zones
const PX_PER_INCH := 40.0

# Autoloads are not registered as compile-time globals while a SceneTree
# script is being loaded, so every one of them is resolved from the tree at
# run time instead of referenced by name.
var GS = null

var _p1 := ""
var _p2 := ""
var _mirror := ""
var _out := ""
var _predeploy := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--p1="): _p1 = a.split("=", true, 1)[1]
		elif a.begins_with("--p2="): _p2 = a.split("=", true, 1)[1]
		elif a.begins_with("--mirror="): _mirror = a.split("=", true, 1)[1]
		elif a.begins_with("--out="): _out = a.split("=", true, 1)[1]
		elif a == "--predeploy": _predeploy = true
		else:
			# Silently ignoring an unrecognised flag is how a bare `--mirror`
			# (no `=<list>`) produced a fixture that was named like a mirror,
			# reported "models out of place: 0", and was not a mirror at all —
			# both sides were packed independently. Refuse instead.
			printerr("[fixture] FAIL: unrecognised argument %r (did you mean --mirror=<list>?)" % a)
			quit(2)
			return
	if _mirror != "":
		_p1 = _mirror
		_p2 = _mirror
	if _p1 == "" or _p2 == "" or _out == "":
		printerr("usage: --p1=<list> --p2=<list> --out=<name>  |  --mirror=<list> --out=<name>")
		quit(2)
		return
	await create_timer(0.5).timeout
	_build()


func _fail(msg: String) -> void:
	printerr("[fixture] FAIL: %s" % msg)
	quit(1)


func _build() -> void:
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	GS = root.get_node_or_null("GameState")
	if slm == null or alm == null or GS == null:
		_fail("SaveLoadManager / ArmyListManager / GameState autoload missing")
		return

	# 1. Shell: board, terrain, objectives, deployment zones, mission, deck.
	if not slm.load_game(SHELL):
		_fail("could not load the shell save %s" % SHELL)
		return
	print("[fixture] shell loaded: %s" % SHELL)

	# 2. Both armies, through the real loader.
	alm.scan_available_armies()
	for spec in [[_p1, 1], [_p2, 2]]:
		var data = alm.load_army_list(str(spec[0]), int(spec[1]))
		if data.is_empty() or not data.has("units"):
			_fail("army list %r did not load" % spec[0])
			return
		alm.apply_army_to_game_state(data, int(spec[1]))
		print("[fixture] P%d <- %s (%d units)" % [int(spec[1]), str(spec[0]), data.units.size()])

	# 3. Deploy. Player 1 is packed into its own zone; player 2 is either the
	#    180-degree rotation of that packing (mirror) or its own packing (asym).
	var size = GS.state.board.size
	var w_px := float(size.width) * PX_PER_INCH
	var h_px := float(size.height) * PX_PER_INCH
	var zones := _zone_bounds()
	if not zones.has(1) or not zones.has(2):
		_fail("the shell save has no deployment zone for one of the players")
		return

	if not _predeploy:
		var p1_spots := _pack(1, zones[1])
		if p1_spots < 0:
			return
		print("[fixture] P1 packed %d model(s)" % p1_spots)

		if _mirror != "":
			var n := _mirror_p2_from_p1(w_px, h_px)
			if n < 0:
				return
			print("[fixture] P2 mirrored %d model(s) by 180-degree rotation" % n)
		else:
			var p2_spots := _pack(2, zones[2])
			if p2_spots < 0:
				return
			print("[fixture] P2 packed %d model(s)" % p2_spots)
	else:
		print("[fixture] --predeploy: no packing, both armies left UNDEPLOYED")

	# 4. A fixture starts clean: nothing has moved, shot, charged or died.
	#    --predeploy additionally strips every model position and leaves the
	#    status at UNDEPLOYED, which is what DeploymentPhase._get_undeployed_units_for_player
	#    keys off to emit DEPLOY_UNIT actions.
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		u["status"] = 0 if _predeploy else 2  # UnitStatus.UNDEPLOYED / DEPLOYED
		u["flags"] = {}
		for m in u.get("models", []):
			m["alive"] = true
			m["current_wounds"] = m.get("wounds", 1)
			m["status_effects"] = []
			if _predeploy:
				m["position"] = null
				m["rotation"] = 0.0

	# 5. Symmetric per-player state. For a mirror this is required — an
	#    asymmetric CP or secondary deck would put a bias in the fixture that
	#    no side swap can cancel. For the asymmetric fixture it is still right:
	#    both players start a game of 40k with the same CP and the same deck.
	var st = GS.state
	if st.has("players") and st.players.has("1"):
		st.players["2"] = st.players["1"].duplicate(true)
	if st.has("secondary_missions") and st.secondary_missions.has("player_state"):
		var ps = st.secondary_missions.player_state
		if ps.has("1"):
			ps["2"] = ps["1"].duplicate(true)

	# 6. Round 1, command phase, player 1 first — the shell's own start point,
	#    restated so this does not silently inherit a different one later.
	st.meta["battle_round"] = 1
	st.meta["phase"] = 1 if _predeploy else 6  # Phase.DEPLOYMENT / Phase.COMMAND
	st.meta["active_player"] = 1
	st.meta["first_turn_player"] = 1
	st.meta["turn"] = 1
	st["history"] = []
	st["phase_log"] = []
	st["unit_visuals"] = {}

	# 7. Report before saving, so a bad fixture is visible in the build log.
	var report := _summarise()
	print("[fixture] %s" % _out)
	for line in report:
		print("[fixture]   %s" % line)

	# A 2000-pt save is ~200 KB of JSON, well over StateSerializer's 50 KB
	# COMPRESSION_SIZE_THRESHOLD, so the default path would gzip+base64 it into
	# one unreadable line. The engine reads that back fine (deserialize_game_state
	# auto-detects), but a committed fixture wants to be greppable and diffable
	# like the ones already in 40k/tests/saves/. Turn compression off for the
	# write only.
	var ss = root.get_node_or_null("StateSerializer")
	if ss != null:
		ss.set_compression_enabled(false)
	if not slm.save_game(_out):
		_fail("save_game(%r) returned false" % _out)
		return
	print("[fixture] saved to %ssave" % slm.save_directory)
	quit(0)


func _zone_bounds() -> Dictionary:
	var out := {}
	for z in GS.state.board.get("deployment_zones", []):
		var xs := []
		var ys := []
		for p in z.get("poly", []):
			xs.append(float(p.x) * PX_PER_INCH)
			ys.append(float(p.y) * PX_PER_INCH)
		if xs.is_empty():
			continue
		out[int(z.player)] = {
			"min_x": xs.min(), "max_x": xs.max(),
			"min_y": ys.min(), "max_y": ys.max(),
		}
	return out


func _radius_px(model: Dictionary) -> float:
	return float(model.get("base_mm", 32)) / 25.4 * PX_PER_INCH / 2.0


func _pack(player: int, zone: Dictionary) -> int:
	"""Grid-pack every model of `player` into its zone without overlap.

	LARGEST BASE FIRST. The first version of this walked units in sorted id
	order, which fragmented the zone with 25mm Gretchin and then had nowhere to
	put a 180mm Stompa — it failed on the 77th of 77 Ork models in a zone that
	is only 59% full by area. Big-first is the standard bin-packing heuristic
	and costs nothing here.

	Otherwise deliberately dumb and fully deterministic: a fixed scan step,
	first free slot left-to-right then top-to-bottom, ties broken by unit id
	then model index. A cleverer packing would be a hidden variable in every
	game played on this fixture; the point is that it is reproducible, not that
	it is good."""
	var queue: Array = []
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		if int(u.get("owner", 0)) != player:
			continue
		var models = u.get("models", [])
		for i in range(models.size()):
			queue.append({"uid": uid, "idx": i, "r": _radius_px(models[i])})
	queue.sort_custom(func(a, b):
		if abs(a.r - b.r) > 0.001:
			return a.r > b.r
		if a.uid != b.uid:
			return a.uid < b.uid
		return a.idx < b.idx)

	var occupied: Array = []
	var placed := 0
	const STEP := 10.0

	for item in queue:
		var m = GS.state.units[item.uid].models[item.idx]
		var r: float = item.r
		var spot := Vector2.INF
		var y: float = zone.min_y + r + 2.0
		while y <= zone.max_y - r and spot == Vector2.INF:
			var x: float = zone.min_x + r + 2.0
			while x <= zone.max_x - r:
				var ok := true
				for o in occupied:
					var gap: float = r + o[2] + 2.0
					var dx: float = x - o[0]
					if absf(dx) >= gap:
						continue
					var dy: float = y - o[1]
					if dx * dx + dy * dy < gap * gap:
						ok = false
						break
				if ok:
					spot = Vector2(x, y)
					break
				x += STEP
			y += STEP
		if spot == Vector2.INF:
			_fail("no room in P%d's zone for a %.0fmm model of %s (%d of %d already placed)"
				% [player, m.get("base_mm", 32), item.uid, placed, queue.size()])
			return -1
		m["position"] = {"x": spot.x, "y": spot.y}
		occupied.append([spot.x, spot.y, r])
		placed += 1
	return placed


func _mirror_p2_from_p1(w_px: float, h_px: float) -> int:
	"""Place P2 as the 180-degree rotation of P1's packing.

	Both sides field the same list, so the units pair up by sorted id — the
	same order _pack used. If they do not pair up the fixture is not a mirror
	and must not be written."""
	var p1_ids := []
	var p2_ids := []
	for uid in GS.state.units:
		var owner := int(GS.state.units[uid].get("owner", 0))
		if owner == 1: p1_ids.append(uid)
		elif owner == 2: p2_ids.append(uid)
	p1_ids.sort()
	p2_ids.sort()
	if p1_ids.size() != p2_ids.size():
		_fail("mirror: P1 has %d units, P2 has %d" % [p1_ids.size(), p2_ids.size()])
		return -1

	var moved := 0
	for i in range(p1_ids.size()):
		var a = GS.state.units[p1_ids[i]]
		var b = GS.state.units[p2_ids[i]]
		if a.meta.get("name", "") != b.meta.get("name", ""):
			_fail("mirror: %s (%s) does not pair with %s (%s) — sorted ids do not line up"
				% [p1_ids[i], a.meta.get("name", "?"), p2_ids[i], b.meta.get("name", "?")])
			return -1
		var am = a.get("models", [])
		var bm = b.get("models", [])
		if am.size() != bm.size():
			_fail("mirror: %s has %d models, %s has %d" % [p1_ids[i], am.size(), p2_ids[i], bm.size()])
			return -1
		for j in range(am.size()):
			var p = am[j].get("position")
			if p == null:
				_fail("mirror: %s model %d has no position to mirror" % [p1_ids[i], j])
				return -1
			bm[j]["position"] = {"x": w_px - float(p.x), "y": h_px - float(p.y)}
			moved += 1
	return moved


func _summarise() -> Array:
	var out := []
	for player in [1, 2]:
		var units := 0
		var models := 0
		var pts := 0
		var names := {}
		for uid in GS.state.units:
			var u = GS.state.units[uid]
			if int(u.get("owner", 0)) != player:
				continue
			units += 1
			models += u.get("models", []).size()
			pts += int(u.get("meta", {}).get("points", 0))
			names[u.get("meta", {}).get("name", "?")] = true
		var f = GS.state.get("factions", {}).get(str(player), {})
		out.append("P%d: %d units, %d models, %d pts — %s / %s"
			% [player, units, models, pts, f.get("name", "?"), f.get("detachment", "?")])
	if _predeploy:
		# The invariant is inverted here: NOTHING may be on the board, and every
		# unit must read UNDEPLOYED, or DeploymentPhase emits no DEPLOY_UNIT
		# action for it and the AI silently starts the game a unit short.
		var placed := 0
		var not_undeployed := 0
		for uid in GS.state.units:
			var u = GS.state.units[uid]
			if int(u.get("status", -1)) != 0:
				not_undeployed += 1
			for m in u.get("models", []):
				if m.get("position") != null:
					placed += 1
		out.append("models still placed: %d (must be 0)" % placed)
		out.append("units not UNDEPLOYED: %d (must be 0)" % not_undeployed)
		return out

	# Every alive model must be somewhere, and in its own half.
	var h_px := float(GS.state.board.size.height) * PX_PER_INCH
	var stray := 0
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var owner := int(u.get("owner", 0))
		for m in u.get("models", []):
			var p = m.get("position")
			if p == null:
				stray += 1
				continue
			var y := float(p.y)
			if (owner == 1 and y > h_px * 0.5) or (owner == 2 and y < h_px * 0.5):
				stray += 1
	out.append("models out of place: %d" % stray)
	return out

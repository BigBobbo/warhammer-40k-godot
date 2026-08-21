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

	# 1b. PM-F3: do NOT trust the shell's board geometry. The shell's board is a
	# snapshot from whenever the shell was made, and the zone JSONs have been
	# regenerated since (crucible_of_battle went from a stepped band to a
	# triangle). SaveLoadManager restores the stale board verbatim, so every
	# fixture built on this shell played geometry no menu game can produce —
	# and the PM-10 A/B was measured on it. Refresh zones and objectives from
	# the same sources a fresh menu game uses: DeploymentZoneData.get_zones for
	# the zones, MissionManager._setup_objectives_for_deployment for the
	# objectives (which prefers layout-sourced objectives exactly like a real
	# game, so the terrain layout the shell restored keeps its say).
	var DZD = load("res://scripts/data/DeploymentZoneData.gd")
	var mm = root.get_node_or_null("MissionManager")
	if DZD == null or mm == null:
		_fail("DeploymentZoneData / MissionManager unavailable for the PM-F3 board refresh")
		return
	var dep_type := str(GS.state.meta.get("deployment_type", ""))
	if dep_type.is_empty():
		_fail("shell save carries no meta.deployment_type")
		return
	var old_zones := JSON.stringify(GS.state.board.get("deployment_zones", []))
	var old_objs := JSON.stringify(GS.state.board.get("objectives", []))
	GS.state.board["deployment_zones"] = DZD.get_zones(dep_type)
	mm._setup_objectives_for_deployment(dep_type)
	var zones_changed := old_zones != JSON.stringify(GS.state.board.get("deployment_zones", []))
	var objs_changed := old_objs != JSON.stringify(GS.state.board.get("objectives", []))
	print("[fixture] PM-F3 board refresh (%s): zones %s, objectives %s" % [
		dep_type,
		"REPLACED (shell was stale)" if zones_changed else "already current",
		"REPLACED (shell was stale)" if objs_changed else "already current"])

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

	# 6.5. COHERENCY GATE — judged by the ENGINE's own predicate (the same one
	# the ISS-042 end-of-turn sweep enforces), not a re-implementation. A
	# fixture that deploys any unit out of coherency is an illegal game state:
	# the AI cannot legally move the scattered unit (it grinds the movement
	# ladder for minutes concluding that), and the engine amputates the unit at
	# the next End of Turn. Either way every number measured on it is garbage.
	# Refuse to write such a fixture.
	if not _predeploy:
		for uid in GS.state.units:
			var coh = AttackSequence.check_unit_coherency(GS.state.units[uid])
			if not bool(coh.get("coherent", false)):
				_fail("unit %s would deploy OUT OF COHERENCY (offenders: %s) — illegal deployment, fixture not written"
					% [uid, str(coh.get("offenders", []))])
				return
		print("[fixture] coherency gate: all units coherent as deployed")

	# 7. Report before saving, so a bad fixture is visible in the build log.
	var report := _summarise()
	print("[fixture] %s" % _out)
	for line in report:
		print("[fixture]   %s" % line)

	# Leave StateSerializer's compression ALONE — a 2000-pt save is ~200 KB of
	# JSON and it gzip+base64s anything over COMPRESSION_SIZE_THRESHOLD (50 KB).
	#
	# An earlier version of this disabled it so the committed fixture would be
	# greppable and diffable. That was the wrong trade. Six fixtures of
	# pretty-printed JSON added ~72,000 lines to the pull request — ten times the
	# size of the actual code change — and nobody reviews 12,000 lines of model
	# coordinates anyway. Compressed they are ~19 KB and one line each, a 92%
	# reduction, and the review value lost is close to zero because
	# `tools/ai_lab/fixture_check.py` validates the contents properly (unit
	# counts, points, the 11e reserves cap, mirror symmetry, status/position
	# agreement) and reads either form transparently. Provenance is the sha256
	# recorded in every game record, not the diff.
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
		var poly := PackedVector2Array()
		for p in z.get("poly", []):
			var px := float(p.x) * PX_PER_INCH
			var py := float(p.y) * PX_PER_INCH
			xs.append(px)
			ys.append(py)
			poly.append(Vector2(px, py))
		if xs.is_empty():
			continue
		out[int(z.player)] = {
			"min_x": xs.min(), "max_x": xs.max(),
			"min_y": ys.min(), "max_y": ys.max(),
			# PM-F3: the polygon itself, because the bounds rectangle is a
			# strict over-approximation for the triangular and stepped zones
			# and a rectangle-packed fixture puts models outside the real zone.
			"poly": poly,
		}
	return out


func _wholly_inside(pt: Vector2, r: float, poly: PackedVector2Array) -> bool:
	"""Circle of radius r around pt sits wholly inside poly — the phase's own
	deployment rule ('Model must be wholly within deployment zone'). A zone
	with no polygon defers, matching the pre-PM-F3 behaviour."""
	if poly.size() < 3:
		return true
	if not Geometry2D.is_point_in_polygon(pt, poly):
		return false
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var closest := Geometry2D.get_closest_point_to_segment(pt, a, b)
		if pt.distance_to(closest) < r:
			return false
	return true


func _radius_px(model: Dictionary) -> float:
	return float(model.get("base_mm", 32)) / 25.4 * PX_PER_INCH / 2.0


func _pack(player: int, zone: Dictionary) -> int:
	"""Grid-pack every UNIT of `player` into its zone as one contiguous block.

	PER-UNIT BLOCKS, LARGEST UNIT FIRST. The first version of this packed the
	77 MODELS individually, sorted by base size across the whole army — which
	interleaved every unit's models with every other unit's and deployed 19 of
	the Ork mirror's 34 units OUT OF COHERENCY (Warbikers Delta's six bikes
	spanned 36 inches). That deployment is illegal, and it is what made
	mirror_orks_2000_postdeploy unable to finish a game:

	  * the AI's move placement (correctly) refuses to reproduce an incoherent
	    formation, so a scattered unit wedged between other units' models has
	    ZERO legal placements — and the movement fallback ladder re-derives
	    that impossibility for minutes inside one decision call;
	  * the engine's ISS-042 end-of-turn sweep (11e 03.03) then DESTROYS the
	    scattered models of whichever army survives to an End of Turn — in the
	    probe runs it amputated 31 of player 2's 77 models before that army
	    ever moved, which is why "player 2's exact mirror completes" while
	    player 1 hangs: player 1's first movement phase never ends, so the
	    sweep never reaches it. Turn order converted the symmetric defect into
	    an asymmetric outcome.

	Packing each unit as a near-square block keeps every deployment legal:
	within a block, neighbours sit 2px apart edge-to-edge (0.05in, far inside
	the 2in coherency distance) and the block diagonal stays inside the 11e
	9in envelope. _build gates on the engine's own coherency check afterwards.

	Big-first at the unit level is the same bin-packing heuristic the model
	version used (a zone fragmented by Gretchin has nowhere to put a Stompa).
	Otherwise deliberately dumb and fully deterministic: a fixed scan step,
	first anchor that fits the whole block, left-to-right then front-to-back,
	ties broken by unit id. A cleverer packing would be a hidden variable in
	every game played on this fixture; the point is that it is reproducible,
	not that it is good."""
	var uqueue: Array = []
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		if int(u.get("owner", 0)) != player:
			continue
		var models = u.get("models", [])
		if models.is_empty():
			continue
		var max_r := 0.0
		for m in models:
			max_r = maxf(max_r, _radius_px(m))
		uqueue.append({"uid": uid, "n": models.size(), "r": max_r})
	uqueue.sort_custom(func(a, b):
		if absf(a.r - b.r) > 0.001:
			return a.r > b.r
		if a.n != b.n:
			return a.n > b.n
		return a.uid < b.uid)

	var occupied: Array = []
	var placed := 0
	const STEP := 10.0

	# Fill from the edge of the zone NEAREST THE BOARD CENTRE, i.e. the front
	# rank, for both players.
	#
	# Scanning from `zone.min_y` unconditionally looks symmetric and is not:
	# min_y is the BOARD EDGE for player 1 and the FRONT of the zone for player
	# 2. Combined with largest-first, that put player 1's big bases at the
	# back and player 2's at the front — from the same code.
	var board_mid: float = float(GS.state.board.size.height) * PX_PER_INCH * 0.5
	var front_is_max: bool = absf(zone.max_y - board_mid) < absf(zone.min_y - board_mid)

	for item in uqueue:
		var u = GS.state.units[item.uid]
		var models: Array = u.get("models", [])
		var n: int = item.n
		var r: float = item.r
		var cell: float = r * 2.0 + 2.0

		# PM-F3: candidate block shapes, near-square first. One fixed
		# ceil(sqrt(n)) shape was enough on the old (rectangular-ish) stale
		# zones, but the true crucible triangles narrow to a point and a
		# mid-pack unit can be unplaceable in the one shape while fitting fine
		# as a wider or narrower block (measured: asym_2000_postdeploy's P2
		# Orks failed at U_GRETCHIN_B, 45 of 77 models placed). Shapes beyond
		# the first are only reached when the previous shape fits NOWHERE, so
		# every fixture that packed before packs identically now. Each shape
		# keeps the block diagonal inside the 11e 9" envelope; the engine's
		# own coherency gate after packing remains the final word.
		var col_candidates: Array = []
		var primary: int = int(ceil(sqrt(float(n))))
		var order: Array = [primary]
		for c in range(primary + 1, n + 1):
			order.append(c)
		for c in range(primary - 1, 0, -1):
			order.append(c)
		for c in order:
			var rows_c: int = int(ceil(float(n) / float(c)))
			var diag: float = Vector2(float(c - 1) * cell, float(rows_c - 1) * cell).length()
			if diag <= 8.8 * PX_PER_INCH:
				col_candidates.append(c)
		if col_candidates.is_empty():
			col_candidates.append(primary)  # huge bases: let the engine gate decide

		var cols: int = col_candidates[0]
		var offs: Array = []
		var w: float = 0.0
		var h: float = 0.0
		var spot := Vector2.INF
		for cand in col_candidates:
			cols = cand
			# Row-major local offsets from the block's front-left model. Row 0
			# is the FRONT rank; deeper rows extend toward the back.
			offs = []
			for i in range(n):
				offs.append(Vector2(float(i % cols) * cell, float(i / cols) * cell))
			w = float(cols - 1) * cell
			h = float(int(ceil(float(n) / float(cols))) - 1) * cell
			spot = _scan_for_spot(zone, w, h, r, n, offs, occupied)
			if spot != Vector2.INF:
				if cand != col_candidates[0]:
					print("[fixture] %s: primary %d-col block fit nowhere; packed as %d columns" % [item.uid, col_candidates[0], cols])
				break
		if spot == Vector2.INF:
			_fail("no room in P%d's zone for %s as a coherent block (%d models, cell %.0fpx; %d model(s) already placed)"
				% [player, item.uid, n, cell, placed])
			return -1
		for i in range(n):
			var mx: float = spot.x + offs[i].x
			var my: float = (spot.y - offs[i].y) if front_is_max else (spot.y + offs[i].y)
			models[i]["position"] = {"x": mx, "y": my}
			occupied.append([mx, my, _radius_px(models[i])])
			placed += 1
	return placed


func _scan_for_spot(zone: Dictionary, w: float, h: float, r: float, n: int,
		offs: Array, occupied: Array) -> Vector2:
	"""The original front-to-back, left-to-right scan, extracted verbatim so
	_pack can try more than one block shape. Returns the block's front-left
	model position, or Vector2.INF when the shape fits nowhere."""
	const STEP := 10.0
	var board_mid: float = float(GS.state.board.size.height) * PX_PER_INCH * 0.5
	var front_is_max: bool = absf(zone.max_y - board_mid) < absf(zone.min_y - board_mid)
	var y: float = (zone.max_y - r - 2.0) if front_is_max else (zone.min_y + r + 2.0)
	while ((y - h >= zone.min_y + r) if front_is_max else (y + h <= zone.max_y - r)):
		var x: float = zone.min_x + r + 2.0
		while x + w <= zone.max_x - r:
			var ok := true
			for i in range(n):
				var mx: float = x + offs[i].x
				var my: float = (y - offs[i].y) if front_is_max else (y + offs[i].y)
				# PM-F3: wholly inside the real polygon, not just the bounds
				# rectangle — the stepped and triangular zones are smaller
				# than their rectangle, and a model packed into the difference
				# starts the game outside its own zone.
				if not _wholly_inside(Vector2(mx, my), r, zone.get("poly", PackedVector2Array())):
					ok = false
					break
				for o in occupied:
					var gap: float = r + o[2] + 2.0
					var dx: float = mx - o[0]
					if absf(dx) >= gap:
						continue
					var dy: float = my - o[1]
					if dx * dx + dy * dy < gap * gap:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2(x, y)
			x += STEP
		y += (-STEP if front_is_max else STEP)
	return Vector2.INF


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

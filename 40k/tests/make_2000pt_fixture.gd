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
#
# --reserves=ai (opt-in, postdeploy only) puts into Strategic Reserves / Deep
# Strike exactly the units the AI's own Formations logic would put there, with
# the reserve type it would pick; every other unit stays deployed exactly as
# without the flag. For a mirror both players hold back the same units —
# checked, not assumed. Without the flag nothing is in reserve, as before.
# See _reserve_like_the_ai.
#
# --base=<fixture> (only with --reserves) starts from an existing postdeploy
# fixture in tests/saves instead of the shell and the lists. That is how the
# bench's reserves fixtures are built, because the lists no longer reproduce
# the bench armies (see _load_base):
#   godot --headless --path 40k -s tests/make_2000pt_fixture.gd -- \
#       --base=mirror_custodes_2000_postdeploy --reserves=ai \
#       --out=mirror_custodes_2000_reserves_postdeploy

const SHELL := "mirror_custodes_postdeploy"   # board, terrain, objectives, zones
const PX_PER_INCH := 40.0

# --reserves=ai drives the AI's Formations decisions at the lab's default
# difficulty (tools/ai_lab/run_paired.py --difficulty) with a fixed seed. EASY
# is never used: it declares at random. The seed is belt and braces — the
# Formations decisions draw no random numbers today (measured 2026-10-31 on the
# bench armies: the same reserves for seeds 1, 7 and 999 at difficulty 2 and 3).
const RESERVES_AI_DIFFICULTY := 2   # AIDifficultyConfig.Difficulty.HARD
const RESERVES_AI_SEED := 1
const RESERVES_AI_MAX_STEPS := 200  # declarations per seat before the run counts as stuck

# Autoloads are not registered as compile-time globals while a SceneTree
# script is being loaded, so every one of them is resolved from the tree at
# run time instead of referenced by name.
var GS = null
# GameState's script, for its UnitStatus / Phase enums (--reserves / --base
# only). For the same reason it is taken from the GameState node at run time:
# naming its class here compiles GameState.gd while this script loads, before
# the autoloads that script depends on exist (measured: 4 SCRIPT ERRORs in
# every build, flag or not).
var GSD = null

var _p1 := ""
var _p2 := ""
var _mirror := ""
var _out := ""
var _predeploy := false
var _reserves := ""   # --reserves=ai — see _reserve_like_the_ai
var _base := ""       # --base=<fixture> — see _load_base


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--p1="): _p1 = a.split("=", true, 1)[1]
		elif a.begins_with("--p2="): _p2 = a.split("=", true, 1)[1]
		elif a.begins_with("--mirror="): _mirror = a.split("=", true, 1)[1]
		elif a.begins_with("--out="): _out = a.split("=", true, 1)[1]
		elif a == "--predeploy": _predeploy = true
		elif a.begins_with("--base="): _base = a.split("=", true, 1)[1]
		elif a.begins_with("--reserves="):
			# Same lesson as the refusal below: a fixture that reads like a
			# reserves fixture and is not one poisons every number measured on
			# it, so a value other than `ai` (empty included) is an error.
			_reserves = a.split("=", true, 1)[1]
			if _reserves != "ai":
				printerr("[fixture] FAIL: --reserves takes 'ai' (got '%s')" % _reserves)
				quit(2)
				return
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
	if _reserves != "" and _predeploy:
		printerr("[fixture] FAIL: --reserves builds postdeploy fixtures only; it cannot be combined with --predeploy")
		quit(2)
		return
	if _base != "":
		if _reserves == "" or _p1 != "" or _p2 != "" or _out == "":
			printerr("usage: --base=<fixture in tests/saves> --reserves=ai --out=<name>  (no --p1/--p2/--mirror)")
			quit(2)
			return
	elif _p1 == "" or _p2 == "" or _out == "":
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

	# --base: the board, both armies and every position come from an existing
	# postdeploy fixture, so steps 1-6.5 are skipped (_load_base says why) and
	# only the reserves step and the report run on it.
	if _base != "":
		if _load_base(slm) and _reserve_like_the_ai():
			_report_and_save(slm)
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

	# 6.6. --reserves=ai (opt-in): hold back what the AI would. Everything above
	# ran exactly as it does without the flag, so the units left on the table
	# are the default build's, positions included.
	if _reserves != "" and not _reserve_like_the_ai():
		return

	_report_and_save(slm)


func _report_and_save(slm) -> void:
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
		if _reserves != "" and int(u.get("status", -1)) == GSD.UnitStatus.IN_RESERVES:
			continue  # --reserves: a unit in reserve is off the table by definition
		for m in u.get("models", []):
			var p = m.get("position")
			if p == null:
				stray += 1
				continue
			var y := float(p.y)
			if (owner == 1 and y > h_px * 0.5) or (owner == 2 and y < h_px * 0.5):
				stray += 1
	out.append("models out of place: %d" % stray)
	if _reserves != "":
		for player in [1, 2]:
			var held := []
			for uid in GS.state.units:
				var u = GS.state.units[uid]
				if int(u.get("owner", 0)) != player or int(u.get("status", -1)) != GSD.UnitStatus.IN_RESERVES:
					continue
				var bodyguard = u.get("attached_to")
				held.append("%s %s%s" % [uid, str(u.get("reserve_type", "")),
					"" if bodyguard == null else (" (attached to %s)" % str(bodyguard))])
			held.sort()
			var pts: int = GS.get_reserves_points(player)
			var total: int = GS.get_total_army_points(player)
			out.append("P%d in reserve: %d/%d units, %d/%d pts (%.0f%%) — %s" % [
				player, GS.get_reserves_unit_count(player), GS.get_total_unit_count(player),
				pts, total, 100.0 * pts / maxf(float(total), 1.0),
				", ".join(held) if not held.is_empty() else "none"])
	return out


func _load_base(slm) -> bool:
	"""--base: start from an existing postdeploy fixture, skipping steps 1-6.5.

	The bench fixtures cannot be rebuilt from the lists any more: the lists
	have changed under them (measured 2026-10-31 with this builder:
	custodes_lions now loads as 9 units / 1850 pts against the fixture's
	11 / 2000, and recon_stomps as 75 models / 2280 pts against 77 / 1975),
	and so has the board — commit 6f07340 rotated the committed fixtures to
	the 11e geometry (terrain layout take_and_hold_mirror_1) instead of
	rebuilding them, while the shell still yields legacy_fallback_mirror_1
	with the objectives mirrored. A reserves fixture built from the lists
	would differ from its bench counterpart in every unit and in the board,
	not just in what is held back, and even the AI's reserves would change:
	the shipped Ork plan is keyed to the bench layout and does not match the
	shell's. Loading the fixture itself keeps its board, both armies and every
	on-table position as committed."""
	GSD = GS.get_script()
	var path := "res://tests/saves/%s.w40ksave" % _base
	if not slm.load_game_from_file_path(path):
		_fail("could not load the base fixture %s" % path)
		return false
	print("[fixture] base loaded: %s" % path)
	var meta: Dictionary = GS.state.get("meta", {})
	if int(meta.get("phase", -1)) != GSD.Phase.COMMAND or int(meta.get("battle_round", 0)) != 1:
		_fail("base %s is not a postdeploy fixture (phase %s, round %s; expected round 1, Command)"
			% [_base, str(meta.get("phase")), str(meta.get("battle_round"))])
		return false
	return true


func _reserve_like_the_ai() -> bool:
	"""--reserves=ai: hold back exactly what the AI's own Formations logic would.

	A reserves fixture exists so that the AI logic which only runs against an
	enemy with units in reserve — the deep-strike denial screens, the
	reserve-backed keepers, reserve arrival — meets the reserves it meets in a
	real game. Those are whatever AIDecisionMaker._decide_formations declares:
	a matching AI plan's reserves list, else the FORM-3 formula. So the choice
	is not re-implemented or hand-picked here, it is RUN (_ai_reserve_choice):
	the real FormationsPhase and the real AIDecisionMaker.decide, both seats,
	on the fixture's own armies. Change the AI's reserves logic and a rebuilt
	fixture follows it.

	Only the reserves are taken from that run. The AI's other Formations
	declarations (leader attachments, embarkations, a warlord pick) are not:
	every unit left on the table stays exactly as the build placed it. The one
	exception is a CHARACTER the AI attached to a unit it then reserved — that
	leader leaves the table WITH its bodyguard
	(FormationsPhase._reserve_attached_characters), so it goes into reserve
	attached to it; without the link MovementPhase could not set the two up
	together when they arrive."""
	GSD = GS.get_script()
	# The run and the write-back assume the army the build produces: every unit
	# deployed, nothing attached, embarked or already in reserve.
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var ad = u.get("attachment_data", {})
		var td = u.get("transport_data", {})
		if int(u.get("status", -1)) != GSD.UnitStatus.DEPLOYED \
				or u.get("attached_to") != null or u.get("embarked_in") != null \
				or (ad is Dictionary and not ad.get("attached_characters", []).is_empty()) \
				or (td is Dictionary and not td.get("embarked_units", []).is_empty()):
			_fail("--reserves=ai needs every unit DEPLOYED, unattached and not embarked; %s is not (status %s)"
				% [uid, str(u.get("status"))])
			return false

	var picked := _ai_reserve_choice()
	if picked.is_empty():
		return false

	# A mirror must hold back the SAME units on both sides. Each seat was
	# decided on its own, so the two are compared rather than P1's copied
	# over: if the AI would play the seats differently the fixture is not a
	# mirror. fixture_check cannot catch that — its mirror signature ignores
	# status, and its position check only looks at models that HAVE one.
	var twins := _p1_twins()
	if _base.begins_with("mirror_") and twins.is_empty():
		_fail("base %s is named as a mirror but its armies do not pair up" % _base)
		return false
	if _mirror != "" or (_base != "" and not twins.is_empty()):
		var sides := []
		for player in [1, 2]:
			var lines := []
			for e in picked[player]:
				var ids := [str(e.get("unit_id", ""))]
				for c in e.get("attached_character_ids", []):
					ids.append(str(c))
				if player == 2:
					ids = ids.map(func(x): return str(twins.get(x, "unpaired:" + x)))
				var riders := ids.slice(1)
				riders.sort()
				lines.append("%s %s [%s]" % [ids[0], str(e.get("reserve_type", "")), ",".join(riders)])
			lines.sort()
			sides.append(lines)
		if sides[0] != sides[1]:
			_fail("mirror: the AI holds back different units for the two seats — P1 %s; P2 (as P1 ids) %s"
				% [str(sides[0]), str(sides[1])])
			return false
		print("[fixture] mirror: both seats hold back the same %d unit(s): %s" % [sides[0].size(), str(sides[0])])

	_apply_reserves(picked)
	return _reserves_gate()


func _ai_reserve_choice() -> Dictionary:
	"""Run Formations for both seats with the AI deciding, and return what each
	seat declared into reserves: {1: [...], 2: [...]}, entries exactly as
	FormationsPhase records them ({unit_id, reserve_type,
	attached_character_ids}). Empty on failure, which has been reported.

	The AI has to see what it sees at Formations in a real game — nothing on
	the table, attached, embarked or declared — so the live state is rewound to
	that first; and executing CONFIRM_FORMATIONS applies the phase's diffs to
	the live GameState. The whole state is therefore snapshotted before the run
	and restored after it, and the restore is CHECKED against what a save would
	have written: a fixture the run leaked into is refused, not written.

	The loop is AIPlayer's Formations loop: a transport is not offered again
	once an embarkation on it was tried (AIPlayer._failed_transport_ids), and
	the AI runs on the shipped parameters and plans — a plan that matches the
	army and board is auto-matched exactly as in a game
	(AIDecisionMaker._resolve_plan_for), and its reserves list wins."""
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	var pristine: Dictionary = GS.create_snapshot()
	var pristine_json := JSON.stringify(pristine)

	for uid in GS.state.units:
		var u = GS.state.units[uid]
		u["status"] = GSD.UnitStatus.UNDEPLOYED
		u["flags"] = {}
		for m in u.get("models", []):
			m["position"] = null
	GS.state.meta["phase"] = GSD.Phase.FORMATIONS
	for key in ["formations", "formations_declared", "formations_p1_confirmed", "formations_p2_confirmed"]:
		GS.state.meta.erase(key)

	AIDM.clear_all_plans()
	AIDM.reset_caches()
	AIDM.set_ai_seed(RESERVES_AI_SEED)
	var phase = load("res://phases/FormationsPhase.gd").new()
	root.add_child(phase)
	phase.enter_phase(GS.create_snapshot(false))

	var error := ""
	for player in [1, 2]:
		phase.current_declaring_player = player
		GS.set_active_player(player)
		var tried_transports := []
		var confirmed := false
		for _step in range(RESERVES_AI_MAX_STEPS):
			var available: Array = phase.get_available_actions().filter(func(a):
				return not (a.get("type", "") == "DECLARE_TRANSPORT_EMBARKATION"
					and str(a.get("transport_id", "")) in tried_transports))
			var decision: Dictionary = AIDM.decide(GSD.Phase.FORMATIONS,
				GS.create_snapshot(false), available, player, RESERVES_AI_DIFFICULTY)
			if decision.is_empty():
				break
			decision["player"] = player
			var kind := str(decision.get("type", ""))
			var result: Dictionary = phase.execute_action(decision)
			if kind == "DECLARE_TRANSPORT_EMBARKATION":
				tried_transports.append(str(decision.get("transport_id", "")))
			if result.get("success", false):
				if kind == "CONFIRM_FORMATIONS":
					confirmed = true
					break
				continue
			var errors := str(result.get("errors", []))
			if kind == "DECLARE_TRANSPORT_EMBARKATION":
				print("[fixture] P%d: AI embarkation in %s rejected (%s) — transport skipped, as AIPlayer does"
					% [player, str(decision.get("transport_id", "")), errors])
				continue
			if kind == "CONFIRM_FORMATIONS" and "arlord" in errors:
				# Not a reserves question, and every reserve is declared by now:
				# satisfy the warlord rule the way the engine's own reserves-cap
				# test does (tests/unit/test_reserves_half_army_cap.gd) and confirm
				# again. The pick is not kept — the state is restored below.
				var designated := false
				for action in available:
					if action.get("type", "") == "DESIGNATE_WARLORD":
						var pick: Dictionary = action.duplicate(true)
						pick["player"] = player
						if phase.execute_action(pick).get("success", false):
							designated = true
							break
				if designated:
					continue
			error = "P%d's %s was rejected: %s" % [player, kind, errors]
			break
		if error == "" and not confirmed:
			error = "P%d's AI did not confirm its formations within %d declarations" % [player, RESERVES_AI_MAX_STEPS]
		if error != "":
			break

	# Read once BOTH seats have confirmed: the second confirmation is what runs
	# _build_formation_changes, which can still add forced reserves to either side.
	var picked := {}
	if error == "":
		for player in [1, 2]:
			var f: Dictionary = phase.player_formations.get(player, {})
			picked[player] = f.get("reserves", []).duplicate(true)
			var plan = AIDM.get_player_plan(player)
			print("[fixture] P%d AI formations (plan: %s) — attachments %s, embarkations %s, reserves %s" % [
				player, str(plan.get("name", "none")) if plan is Dictionary and not plan.is_empty() else "none",
				str(f.get("leader_attachments", {})), str(f.get("transport_embarkations", {})),
				str(picked[player])])
	root.remove_child(phase)
	phase.free()

	GS.load_from_snapshot(pristine)
	if error != "":
		_fail("--reserves=ai: %s" % error)
		return {}
	if JSON.stringify(GS.create_snapshot()) != pristine_json:
		_fail("--reserves=ai: restoring the state after the Formations run did not reproduce it — refusing to write a fixture the run leaked into")
		return {}
	print("[fixture] --reserves=ai: Formations run done, state restored exactly (snapshot compared)")
	return picked


func _p1_twins() -> Dictionary:
	"""P2 unit id -> the P1 unit it mirrors, paired the way _mirror_p2_from_p1
	pairs them (sorted ids, same datasheet name). Empty when the two armies do
	not pair up, i.e. the fixture is not a mirror."""
	var p1_ids := []
	var p2_ids := []
	for uid in GS.state.units:
		var owner := int(GS.state.units[uid].get("owner", 0))
		if owner == 1: p1_ids.append(uid)
		elif owner == 2: p2_ids.append(uid)
	p1_ids.sort()
	p2_ids.sort()
	if p1_ids.size() != p2_ids.size():
		return {}
	var twins := {}
	for i in range(p1_ids.size()):
		var a = GS.state.units[p1_ids[i]].get("meta", {}).get("name", "")
		var b = GS.state.units[p2_ids[i]].get("meta", {}).get("name", "")
		if a != b:
			return {}
		twins[str(p2_ids[i])] = str(p1_ids[i])
	return twins


func _apply_reserves(picked: Dictionary) -> void:
	"""Write the AI's reserves onto the units the way
	FormationsPhase._build_formation_changes does — status IN_RESERVES and the
	reserve_type on the unit and on every CHARACTER riding with it, the riders'
	attached_to and the bodyguard's attachment_data — plus meta.formations for
	the record. Every model of a reserved unit loses its position: it is not
	on the battlefield.

	`rotation` is left alone and must never be written as null: the bench
	fixtures carry no rotation key (readers take model.get("rotation", 0.0)),
	and an explicit null is passed straight on to Measurement's base-shape
	maths once an attached CHARACTER arrives (MovementPhase only writes a
	character's rotation when one is supplied)."""
	var formations = GS.state.meta.get("formations", {})
	if not (formations is Dictionary):
		formations = {}
	for player in [1, 2]:
		var pf = formations.get(str(player), {})
		if not (pf is Dictionary):
			pf = {}
		var attachments = pf.get("leader_attachments", {})
		if not (attachments is Dictionary):
			attachments = {}
		var entries := []
		for e in picked[player]:
			var uid := str(e.get("unit_id", ""))
			var rtype := str(e.get("reserve_type", "strategic_reserves"))
			var riders := []
			for c in e.get("attached_character_ids", []):
				riders.append(str(c))
			for id in [uid] + riders:
				var u = GS.state.units[id]
				u["status"] = GSD.UnitStatus.IN_RESERVES
				u["reserve_type"] = rtype
				for m in u.get("models", []):
					m["position"] = null
			for r in riders:
				GS.state.units[r]["attached_to"] = uid
				attachments[r] = uid
			if not riders.is_empty():
				var bodyguard = GS.state.units[uid]
				if not (bodyguard.get("attachment_data") is Dictionary):
					bodyguard["attachment_data"] = {}
				bodyguard["attachment_data"]["attached_characters"] = riders.duplicate()
			entries.append({"unit_id": uid, "reserve_type": rtype, "attached_character_ids": riders})
		pf["leader_attachments"] = attachments
		if not pf.has("transport_embarkations"):
			pf["transport_embarkations"] = {}
		pf["reserves"] = entries
		formations[str(player)] = pf
	GS.state.meta["formations"] = formations


func _reserves_gate() -> bool:
	"""Re-check the 11e reserves rules on the state about to be saved, with the
	engine's own helpers. fixture_check only checks the points cap (and warns
	on any reserve at all), so this is the gate for the rest; a fixture that
	breaks any of them is refused."""
	for player in [1, 2]:
		var pts: int = GS.get_reserves_points(player)
		var total_pts: int = GS.get_total_army_points(player)
		var n: int = GS.get_reserves_unit_count(player)
		var total_n: int = GS.get_total_unit_count(player)
		# 20.01 / Chapter Approved 2025-26: at most half the points AND half the
		# units, attached leaders counted in both — the caps
		# FormationsPhase._validate_declare_reserves enforces.
		if pts > int(total_pts * 0.50) or n > int(total_n * 0.50):
			_fail("P%d: %d/%d pts and %d/%d units in reserve — over the 50%% caps" % [player, pts, total_pts, n, total_n])
			return false
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var models: Array = u.get("models", [])
		if int(u.get("status", -1)) != GSD.UnitStatus.IN_RESERVES:
			# 23.01: at 11e an AIRCRAFT unit must start in reserves.
			if GS.unit_must_start_in_reserves(uid):
				_fail("%s is AIRCRAFT and must start in reserves" % uid)
				return false
			for m in models:
				if m.get("alive", true) and m.get("position") == null:
					_fail("%s is on the table but a model of it has no position" % uid)
					return false
			# Step 6.5's predicate, for the --base path that skips 6.5.
			var coh = AttackSequence.check_unit_coherency(u)
			if not bool(coh.get("coherent", false)):
				_fail("unit %s is OUT OF COHERENCY (offenders: %s) — fixture not written" % [uid, str(coh.get("offenders", []))])
				return false
			continue
		var rtype := str(u.get("reserve_type", ""))
		if rtype != "deep_strike" and rtype != "strategic_reserves":
			_fail("%s is in reserve with reserve_type '%s'" % [uid, rtype])
			return false
		if rtype == "deep_strike" and not GS.unit_has_deep_strike(uid):
			_fail("%s is in Deep Strike reserve without the Deep Strike ability" % uid)
			return false
		if GS.unit_is_fortification(uid):
			_fail("%s is a FORTIFICATION and cannot start in reserves" % uid)
			return false
		for m in models:
			if m.get("position") != null:
				_fail("%s is in reserve but a model of it still has a position" % uid)
				return false
		var bodyguard = u.get("attached_to")
		if bodyguard != null:
			var b: Dictionary = GS.state.units.get(str(bodyguard), {})
			var b_ad = b.get("attachment_data", {})
			if int(b.get("status", -1)) != GSD.UnitStatus.IN_RESERVES \
					or str(b.get("reserve_type", "")) != rtype \
					or not (b_ad is Dictionary and uid in b_ad.get("attached_characters", [])):
				_fail("%s rides with %s, which is not in the same reserve with it attached" % [uid, str(bodyguard)])
				return false
	print("[fixture] reserves gate: caps, reserve types, positions, attachments and coherency all legal")
	return true

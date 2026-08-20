extends SceneTree

# PM-10 — author the two shipped Ork plans against the REAL geometry they will
# be played on.
#
# Placements are validated by DeploymentPhase.validate_action itself, on a live
# board, so every position in an emitted plan is one the deployment phase
# actually accepts — terrain, base shapes, overlaps and coherency included.
# Authoring "by eye" and hoping is how a plan ends up silently degrading to the
# formula on half its units.
#
# Two plans, same army and the same tactical content, different boards:
#
#   1. crucible_of_battle, packed against the mirror_orks_2000_predeploy
#      fixture — the plan the PM-10 bench run measures.
#   2. hammer_anvil, packed against a fresh default game — the plan a player
#      picks from the menu. Its keys leave terrain_layout_id empty so it
#      matches whatever terrain the player rolls; per-unit repair/fallback
#      (PM-2a) handles any piece that happens to sit under a model.
#
# TWO GEOMETRIES FOR THE CRUCIBLE PLAN, and it has to satisfy both:
#
#   * the fixture's saved board carries a STEPPED crucible zone (a 44x8 band
#     plus a 24x6 centre step) with obj_home_1 at (22, 4). That is what the
#     deployment phase checks against during the measured bench run.
#   * a FRESH crucible_of_battle game reads res://deployment_zones/
#     crucible_of_battle.json, a TRIANGLE (0,0)-(44,30)-(44,0) with obj_home_1
#     at (32, 14). That is what PlanValidator checks, and what a real game
#     from the menu uses.
#
# The fixture predates the JSON regeneration, so it is stale (see the PM-10
# report). Rather than author a plan that is only legal on a stale board, every
# model is required to sit wholly inside BOTH polygons.
#
# Run: godot --headless --path . -s tests/spikes/pm10_author_plans.gd
#
# ⚠ RUNNING THIS OVERWRITES THE SHIPPED PLANS, AND RIGHT NOW THAT IS A
# DOWNGRADE FOR hammer_anvil. PM-F4 made this spike author at edition 11 (the
# edition the game plays at) instead of the 10e baseline SettingsService pins a
# `godot -s` run to. That is the correct thing to validate against — but the
# anchors below were hand-tuned against the 10e packing, and re-packing at 11e
# moves U_GRETCHIN_B, U_STORMBOYZ_A and U_STORMBOYZ_B, which crowds out what is
# packed after them. Measured, twice each, on sp/pm10_shipped_plan_from_menu:
#
#   shipped file (authored at 10e)   adherence 10 of 11 exact, 11 plan records
#   re-authored at 11e                adherence  9 of 11 exact, 10 plan records
#                                     (U_WARBIKERS_B off by 17.43", U_MEK_A by 1.46")
#
# The shipped file is therefore KEPT as it is: it validates clean at edition 11
# (0 errors, 0 warnings, worst envelope 8.76") and it measures better. The
# anchors want re-tuning for the 11e packing before this spike's output should
# replace it — filed as PM-F7. Until then, treat a diff in data/ai_plans/ after
# running this as a result to evaluate, not one to commit.

const PX := 40.0
const GAP := 0.1   # inches between base edges. Models may touch; they may not
                   # overlap. 0.1" survives the 0.01" rounding in the emitted file.
# 11e core 03.03: every model within 9" of every OTHER model in its unit. Held
# a little under 9 so rounding cannot push a layout over the line.
const COHERENCY_ENVELOPE_IN := 8.8

# --- Content shared by both plans -------------------------------------------

# Tactical order the AI follows: the objective holder first, then the screens,
# then the heavies pushing up the middle.
#
# EVERY deployable unit is here, including the two Deffkilla Wartrikes, and
# that is load-bearing rather than tidy. A unit the plan does not cover is
# deployed by the FORMULA, and the formula runs its units FIRST — so in the
# first measured run the two uncovered Wartrikes (95x150mm each) were put down
# before anything else and then six planned placements collided with them and
# fell back. Seat-2 adherence was 5/11. A partial plan on a tight board is
# self-defeating: leave a unit out and it will be standing in your way.
const ORDER := [
	"U_GRETCHIN_A", "U_GRETCHIN_B",
	"U_STORMBOYZ_A", "U_STORMBOYZ_B",
	"U_STOMPA_A", "U_WAZDAKKA_GUTSMEK_A",
	"U_DEFFKILLA_WARTRIKE_A", "U_WARBIKERS_C",
	"U_DEFFKILLA_WARTRIKE_B", "U_WARBIKERS_D",
	"U_WARBIKERS_A", "U_WARBIKERS_B",
	"U_MEK_A",
]

# The order the AUTHORING pass PACKS units in — most important first, because
# whatever is packed last is what gets squeezed out on a tight board. This is a
# packing concern only; `ORDER` is the tactical sequence, and the two are
# independent because only POSITIONS come out of the packing pass.
const PACK_ORDER := [
	"U_GRETCHIN_A",            # has to be ON the objective — nothing else gets that spot
	"U_STOMPA_A",              # 180mm base: the hardest thing on the board to fit
	"U_WAZDAKKA_GUTSMEK_A",
	# Each mob is packed immediately before its Wartrike so the Wartrike takes
	# the space next to the mob it leads rather than whatever is left over.
	"U_WARBIKERS_C", "U_DEFFKILLA_WARTRIKE_A",
	"U_WARBIKERS_D", "U_DEFFKILLA_WARTRIKE_B",
	"U_GRETCHIN_B",
	"U_STORMBOYZ_A", "U_STORMBOYZ_B",
	"U_WARBIKERS_A", "U_WARBIKERS_B",
	"U_MEK_A",
]

# Reserves are the other half of the answer to a zone that cannot hold the
# army: both Deffkopta units go up and come down on round 2, which is also
# where they want to be (they arrive next to whatever character they are
# hunting instead of driving across the board). 410 of 2000 points and 4 of 17
# units — comfortably inside the 50% caps.
const RESERVED := ["U_STORMBOYZ_C", "U_STORMBOYZ_D", "U_DEFFKOPTAS_A", "U_DEFFKOPTAS_B"]

const ATTACHMENTS := [
	{"character": "U_DEFFKILLA_WARTRIKE_A", "bodyguard": "U_WARBIKERS_C"},
	{"character": "U_DEFFKILLA_WARTRIKE_B", "bodyguard": "U_WARBIKERS_D"},
]

# Deffkoptas carry HUNT_CHARACTERS rather than RESERVE_UNTIL: v1 allows one
# earmark per unit, and deployment.reserves is the single source of truth for
# holding a unit back, so the earmark is free to say what the unit is FOR.
const EARMARKS := [
	{"unit": "U_GRETCHIN_A", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1"},
	{"unit": "U_GRETCHIN_B", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1"},
	{"unit": "U_STORMBOYZ_A", "verb": "SCREEN"},
	{"unit": "U_STORMBOYZ_B", "verb": "SCREEN"},
	{"unit": "U_STORMBOYZ_C", "verb": "RESERVE_UNTIL", "round": 2},
	{"unit": "U_STORMBOYZ_D", "verb": "RESERVE_UNTIL", "round": 2},
	{"unit": "U_STOMPA_A", "verb": "PUSH_CENTER"},
	{"unit": "U_WAZDAKKA_GUTSMEK_A", "verb": "PUSH_CENTER"},
	{"unit": "U_WARBIKERS_C", "verb": "PUSH_CENTER"},
	{"unit": "U_WARBIKERS_D", "verb": "PUSH_CENTER"},
	{"unit": "U_DEFFKOPTAS_A", "verb": "HUNT_CHARACTERS"},
	{"unit": "U_DEFFKOPTAS_B", "verb": "HUNT_CHARACTERS"},
]

const DESCRIPTION := "Gretchin hold the home objective with a second mob screening beside them. The Stompa leads Wazdakka and both Warbiker mobs — each led by a Deffkilla Wartrike — straight up the middle, with two Stormboyz mobs screening the approach. Two more Stormboyz mobs and both Deffkopta units stay in Reserves and arrive on round 2, the Deffkoptas dropping in on whichever character is worth hunting."

# --- The two plans ----------------------------------------------------------

const PLANS := [
	{
		"out": "res://data/ai_plans/orks_recon_stomps_crucible.json",
		"name": "Orks — Recon Stomps on Crucible",
		"zone": "crucible_of_battle",
		"fixture": "mirror_orks_2000_predeploy",
		"author_terrain": "",                       # the fixture brings its own
		"terrain_layout_id": "take_and_hold_mirror_1",
		# The usable region is the INTERSECTION of a 44x8 band + 24x6 step with
		# a triangle, so the whole army does not fit and the anchors crowd the
		# centre. Reserves take the rest.
		"anchors": {
			"U_GRETCHIN_A": [22.0, 4.0],            # ON the fixture's obj_home_1
			"U_STOMPA_A": [25.0, 9.0],              # centre, straddling band into step
			"U_WAZDAKKA_GUTSMEK_A": [32.0, 9.5],    # up with the Stompa, right of it
			"U_WARBIKERS_C": [31.0, 12.0],          # furthest forward, right
			"U_DEFFKILLA_WARTRIKE_A": [35.0, 6.0],  # riding with C
			"U_WARBIKERS_D": [21.0, 11.5],          # furthest forward, left
			"U_DEFFKILLA_WARTRIKE_B": [17.0, 6.5],  # riding with D
			"U_GRETCHIN_B": [14.0, 4.0],            # second body, left of the objective
			"U_STORMBOYZ_A": [10.0, 5.5],           # screen, left
			"U_STORMBOYZ_B": [30.0, 5.0],           # screen, right
			"U_WARBIKERS_A": [37.0, 4.0],           # right flank
			"U_WARBIKERS_B": [40.0, 6.5],
			"U_MEK_A": [19.0, 6.5],                 # behind the Gretchin, repairing
		},
	},
	{
		"out": "res://data/ai_plans/orks_recon_stomps_hammer_anvil.json",
		"name": "Orks — Recon Stomps on Hammer and Anvil",
		"zone": "hammer_anvil",
		"fixture": "",                              # fresh default game
		# Authored against the layout the windowed scenario rolls, so the
		# shipped plan is exact on at least one real board. keys.terrain_layout_id
		# is still left EMPTY so the plan matches any layout — on a different one
		# the consumer repairs or falls back per unit, which is the designed
		# behaviour and is what the scenario's own numbers show.
		"author_terrain": "take_and_hold_vs_purge_the_foe_3",
		"terrain_layout_id": "",                    # matches whatever terrain is rolled
		# A 44x18 rectangle: room for the whole deployable half of the army, so
		# the line can be drawn properly — holders back, heavies forward.
		"anchors": {
			"U_GRETCHIN_A": [22.0, 10.0],           # ON obj_home_1
			"U_STOMPA_A": [22.0, 14.0],             # spearhead, dead centre
			"U_WAZDAKKA_GUTSMEK_A": [29.0, 14.0],
			"U_WARBIKERS_C": [35.0, 15.0],          # forward right
			"U_DEFFKILLA_WARTRIKE_A": [37.0, 8.0],  # riding with C
			"U_WARBIKERS_D": [11.0, 15.0],          # forward left
			"U_DEFFKILLA_WARTRIKE_B": [7.0, 8.0],   # riding with D
			"U_GRETCHIN_B": [12.0, 6.0],            # second body, back left
			"U_STORMBOYZ_A": [16.0, 16.5],          # screen, forward left
			"U_STORMBOYZ_B": [28.0, 16.5],          # screen, forward right
			"U_WARBIKERS_A": [40.0, 11.0],          # flanks
			"U_WARBIKERS_B": [4.0, 11.0],
			"U_MEK_A": [22.0, 5.0],                 # behind the Gretchin, repairing
		},
	},
]

var _shipped_poly := PackedVector2Array()
var _last_reason: String = ""
var _failures := 0


func _init():
	create_timer(0.4).timeout.connect(_run)


func _run() -> void:
	# PM-F4. A plan is authored here and played somewhere else, so it must be
	# validated against the edition it will be PLAYED at. SettingsService treats
	# any `godot -s` run as an automated harness and pins the legacy 10e
	# baseline (SettingsService.gd:257-286), which has no 9" coherency
	# envelope — so without this line DeploymentPhase.validate_action below
	# certifies layouts the game then refuses. Every player launch runs 11.
	GameConstants.edition = 11
	print("[pm10] authoring at rules edition %d (the edition the game plays at)" % GameConstants.edition)
	for spec in PLANS:
		await _author(spec)
	print("\n=== %s ===" % ("ALL PLANS WRITTEN" if _failures == 0 else "%d PLAN(S) FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _author(spec: Dictionary) -> void:
	var zone := str(spec["zone"])
	print("\n\n================ %s ================" % str(spec["name"]))
	var PV = load("res://scripts/PlanValidator.gd")
	_shipped_poly = PV.get_zone_polygon(zone, 1)
	print("shipped '%s' player-1 polygon (what a real game and the validator use):" % zone)
	print("  %s" % str(_shipped_poly))

	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var fixture := str(spec["fixture"])
	if fixture.is_empty():
		gs.initialize_default_state()
		gs.state["board"]["deployment_type"] = zone
		var want_terrain := str(spec.get("author_terrain", ""))
		if not want_terrain.is_empty():
			var tm = root.get_node_or_null("TerrainManager")
			if tm != null:
				tm.load_terrain_layout(want_terrain)
				print("authoring against terrain layout '%s'" % want_terrain)
		await create_timer(0.5).timeout
	else:
		var save_mgr = root.get_node_or_null("SaveLoadManager")
		if save_mgr == null or not save_mgr.load_game(fixture):
			print("FAILED: could not load fixture %s" % fixture)
			_failures += 1
			return
		await create_timer(0.5).timeout

	print("live board polygon (what the deployment phase checks while packing):")
	for z in gs.state.get("board", {}).get("deployment_zones", []):
		if int(z.get("player", 0)) == 1:
			var pts: Array = []
			for p in z.get("poly", []):
				pts.append("(%.0f,%.0f)" % [float(p["x"]), float(p["y"])])
			print("  %s" % ", ".join(pts))

	# Autoloads are not identifiers at compile time in a `-s` script — fetch
	# them off the root, and spell the phase enum as its int (DEPLOYMENT = 1).
	pm.transition_to_phase(1)
	await create_timer(0.5).timeout
	var phase = pm.get_current_phase_instance()
	if phase == null:
		print("FAILED: no deployment phase instance")
		_failures += 1
		return

	var anchors: Dictionary = spec["anchors"]
	var placements_by_unit: Dictionary = {}
	var failed: Array = []

	print("\npacking (most important first):")
	for unit_id in PACK_ORDER:
		# A MIRROR fixture makes TurnManager alternate the active player after
		# every placement, and the phase then rejects a player-1 unit with
		# "Unit does not belong to active player". Authoring is not playing —
		# pin the seat back to 1 before each unit.
		gs.set_active_player(1)
		var unit = gs.state.units.get(unit_id, {})
		if unit.is_empty():
			failed.append("%s (missing from the army)" % unit_id)
			continue
		var inches := _fit(phase, unit_id, unit, anchors[unit_id])
		if inches.is_empty():
			failed.append("%s (%s)" % [unit_id, _last_reason])
			continue
		# Commit so later units see it and cannot overlap it.
		var positions: Array = []
		for pt in inches:
			positions.append(Vector2(pt[0] * PX, pt[1] * PX))
		var action := {"type": "DEPLOY_UNIT", "unit_id": unit_id, "player": 1,
			"model_positions": positions}
		if not phase.execute_action(action).get("success", false):
			failed.append("%s (execute refused an action validate accepted)" % unit_id)
			continue
		placements_by_unit[unit_id] = {
			"unit": unit_id,
			"unit_name": str(unit.get("meta", {}).get("name", unit_id)),
			"models_inches": inches,
		}
		# Drift is measured from the unit's CENTROID, not its first model: a
		# block's first model is its top-left corner, so a first-model reading
		# reports the block's own half-width as if the packer had wandered.
		var anchor: Array = anchors[unit_id]
		var centroid := Vector2.ZERO
		for pt in inches:
			centroid += Vector2(float(pt[0]), float(pt[1]))
		centroid /= float(inches.size())
		var drift := centroid.distance_to(Vector2(float(anchor[0]), float(anchor[1])))
		print("  placed %-26s %2d model(s)  centroid (%.1f, %.1f), %.1f\" from its anchor" % [
			unit_id, inches.size(), centroid.x, centroid.y, drift])

	if not failed.is_empty():
		print("\nNOT COVERED — these degrade to the formula per-unit (PM-2a):")
		for f in failed:
			print("  %s" % f)

	# Emit in the TACTICAL order, not the packing order.
	var placements: Array = []
	var placed_order: Array = []
	for unit_id in ORDER:
		if placements_by_unit.has(unit_id):
			placements.append(placements_by_unit[unit_id])
			placed_order.append(unit_id)

	var plan := {
		"format": "wh40k_ai_plan",
		"version": 1,
		"name": str(spec["name"]),
		"description": DESCRIPTION,
		"author": "claude-draft — owner review wanted",
		"keys": {
			"army_file": "recon_stomps",
			"detachment_hint": "",
			"deployment_zone_id": zone,
			"terrain_layout_id": str(spec["terrain_layout_id"]),
			"mission_id": "",
		},
		"deployment": {
			"order": placed_order,
			"placements": placements,
			"reserves": [],
			"embarkations": [],
			"attachments": ATTACHMENTS,
		},
		"earmarks": EARMARKS,
	}
	for unit_id in RESERVED:
		plan["deployment"]["reserves"].append({"unit": unit_id, "arrival_round": 2})

	# Self-check the emitted file against the rule the PHASE cannot be trusted
	# to enforce here (see COHERENCY_ENVELOPE_IN). Cheap, and it is the exact
	# condition that cost a whole measured campaign.
	var over: Array = []
	for placement in placements:
		var pts: Array = placement["models_inches"]
		var span := 0.0
		for i in range(pts.size()):
			for j in range(i + 1, pts.size()):
				span = max(span, Vector2(float(pts[i][0]), float(pts[i][1])).distance_to(
					Vector2(float(pts[j][0]), float(pts[j][1]))))
		if span > 9.0:
			over.append("%s spans %.2f\"" % [str(placement["unit"]), span])
	if not over.is_empty():
		print("\nRefusing to write — these break the 9\" coherency envelope the AI enforces:")
		for o in over:
			print("  %s" % o)
		_failures += 1
		return

	var result: Dictionary = PV.validate_plan(plan, _army_for_validation(gs))
	print("\nPlanValidator: valid=%s  %d error(s)  %d warning(s)" % [
		str(result.get("valid", false)),
		result.get("errors", []).size(), result.get("warnings", []).size()])
	for e in result.get("errors", []):
		print("  ERROR: %s" % str(e))
	for w in result.get("warnings", []):
		print("  WARNING: %s" % str(w))
	if not result.get("valid", false) or not result.get("warnings", []).is_empty():
		print("\nRefusing to write: PM-10 requires zero errors AND zero warnings.")
		_failures += 1
		return

	var dir = DirAccess.open("res://data")
	if dir != null and not dir.dir_exists("ai_plans"):
		dir.make_dir("ai_plans")
	var out := str(spec["out"])
	var file = FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(plan, "\t"))
	file.close()
	print("\nwrote %s" % ProjectSettings.globalize_path(out))
	print("  %d of %d deployable unit(s) covered, %d reserve(s), %d attachment(s), %d earmark(s)" % [
		placements.size(), PACK_ORDER.size(), plan["deployment"]["reserves"].size(),
		ATTACHMENTS.size(), EARMARKS.size()])


func _army_for_validation(gs) -> Dictionary:
	var units := {}
	for unit_id in gs.state.units:
		var unit = gs.state.units[unit_id]
		if int(unit.get("owner", 0)) == 1:
			units[unit_id] = unit
	return {"units": units}


# ============================================================
# PACKING
# ============================================================

func _fit(phase, unit_id: String, unit: Dictionary, anchor: Array) -> Array:
	"""Lay `unit` out near `anchor`, searching the whole zone nearest-first
	until a layout is wholly inside the SHIPPED polygon and accepted by the
	deployment phase on the LIVE board. Returns model positions in inches
	(already rounded to the 0.01" the plan file stores), or [] if nothing fit."""
	var models: Array = unit.get("models", [])
	if models.is_empty():
		_last_reason = "unit has no models"
		return []
	var n := models.size()
	var m0: Dictionary = models[0]
	var dims: Dictionary = m0.get("base_dimensions", {})
	var base_mm := float(m0.get("base_mm", 32))
	var w_in: float = float(dims.get("length", base_mm)) / 25.4
	var h_in: float = float(dims.get("width", base_mm)) / 25.4
	# Conservative bounding radius: a base of any rotation fits inside it, so a
	# model that passes the polygon test cannot poke out however it is oriented.
	var r_in: float = max(w_in, h_in) * 0.5

	# Formation shapes to try, widest first (a wide, shallow block is what fits
	# a shallow band), then progressively squarer — but never wider than the 9"
	# COHERENCY ENVELOPE.
	#
	# This filter is load-bearing and was added after a measured run. 11e core
	# 03.03 requires every model to be within 9" of every OTHER model in the
	# unit. Both AIDecisionMaker._plan_positions_legal and DeploymentPhase
	# enforce it through the SAME edition-aware helper
	# (AttackSequence.check_unit_coherency), so they never disagree with each
	# other — but they do answer for whatever GameConstants.edition happens to
	# be, and SettingsService pins a `godot -s` run like this one to the legacy
	# 10e baseline, which has no 9" envelope. Authoring therefore used to
	# certify a layout the GAME would refuse: Gretchin Alpha was authored as an
	# 11-model line 13.6" across, passed validation here, and then fell back to
	# the formula in every single measured game. PM-F4 closes that split — this
	# spike now runs at edition 11 (see _run) and PlanValidator answers for 11
	# regardless of ambient — and this filter stays as the belt to that braces.
	var col_options: Array = []
	var fallback_cols := 1
	var best_span := INF
	for c in [n, int(ceil(n / 2.0)), int(ceil(n / 3.0)), int(ceil(n / 4.0)), 3, 2, 1]:
		if c < 1 or c > n or col_options.has(c):
			continue
		var rows := int(ceil(float(n) / float(c)))
		var span := Vector2(float(c - 1) * (w_in + GAP), float(rows - 1) * (h_in + GAP)).length()
		if span < best_span:
			best_span = span
			fallback_cols = c
		if span <= COHERENCY_ENVELOPE_IN:
			col_options.append(c)
	if col_options.is_empty():
		# A unit whose models cannot fit inside 9" however they are arranged
		# (huge bases). Take the tightest shape and let the phase decide.
		col_options.append(fallback_cols)

	var reason_no_poly := 0
	var reason_phase := 0
	for centre in _candidate_centres(anchor):
		for cols in col_options:
			var inches := _layout(centre, n, cols, w_in + GAP, h_in + GAP)
			if not _all_wholly_inside(inches, r_in):
				reason_no_poly += 1
				continue
			var positions: Array = []
			for pt in inches:
				positions.append(Vector2(pt[0] * PX, pt[1] * PX))
			var check = phase.validate_action({"type": "DEPLOY_UNIT",
				"unit_id": unit_id, "player": 1, "model_positions": positions})
			if check.get("valid", false):
				return inches
			reason_phase += 1
	_last_reason = "no legal layout: %d rejected by the shipped zone polygon, %d by the deployment phase" % [
		reason_no_poly, reason_phase]
	return []


func _layout(centre: Vector2, n: int, cols: int, cell_w: float, cell_h: float) -> Array:
	"""A cols-wide block centred on `centre`, in inches, rounded to 0.01" so the
	positions VALIDATED here are byte-for-byte the ones written to the file."""
	var rows := int(ceil(float(n) / float(cols)))
	var out: Array = []
	for i in range(n):
		out.append([
			snappedf(centre.x + (float(i % cols) - float(cols - 1) * 0.5) * cell_w, 0.01),
			snappedf(centre.y + (float(i / cols) - float(rows - 1) * 0.5) * cell_h, 0.01),
		])
	return out


func _candidate_centres(anchor: Array) -> Array:
	"""Every 0.5" lattice point over the zone's bounding box, nearest to the
	anchor first, so a unit ends up as close to its intended spot as the board
	allows and only wanders when it has to."""
	var want := Vector2(float(anchor[0]), float(anchor[1]))
	var max_y := 0.0
	for p in _shipped_poly:
		max_y = max(max_y, p.y)
	max_y = min(max_y, 30.0)   # no plan deploys past the halfway line
	var out: Array = []
	var y := 0.5
	while y <= max_y:
		var x := 0.5
		while x <= 43.5:
			out.append(Vector2(x, y))
			x += 0.5
		y += 0.5
	out.sort_custom(func(a, b): return a.distance_squared_to(want) < b.distance_squared_to(want))
	return out


func _all_wholly_inside(inches: Array, r_in: float) -> bool:
	for pt in inches:
		if not _wholly_inside(Vector2(float(pt[0]), float(pt[1])), r_in):
			return false
	return true


func _wholly_inside(centre: Vector2, r_in: float) -> bool:
	"""Base of radius r_in entirely inside the shipped polygon: the centre is in
	the polygon and no edge comes closer than the radius."""
	if _shipped_poly.size() < 3:
		return false
	if not Geometry2D.is_point_in_polygon(centre, _shipped_poly):
		return false
	for i in range(_shipped_poly.size()):
		var a := _shipped_poly[i]
		var b := _shipped_poly[(i + 1) % _shipped_poly.size()]
		if _dist_to_segment(centre, a, b) < r_in:
			return false
	return true


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

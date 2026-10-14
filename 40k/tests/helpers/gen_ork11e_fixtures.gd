extends SceneTree

## gen_ork11e_fixtures.gd — builds the two Codex: Orks (11e) stratagem test
## fixtures (design .llm/ork_codex_11e_design.md §6 documents their contents):
##
##   tests/saves/ork11e_orks_active.w40ksave   — P1 = Orks (ork11e_codex_test,
##       War Horde) ACTIVE vs P2 = Adeptus Custodes (custodes_lions).
##   tests/saves/ork11e_orks_reactive.w40ksave — P2 = Orks NON-active vs
##       P1 = Adeptus Custodes ACTIVE (the same battlefield rotated 180°).
##
## Usage (from the repo root; writes both fixtures, or one with --only=):
##   godot --headless --path 40k -s tests/helpers/gen_ork11e_fixtures.gd
##   godot --headless --path 40k -s tests/helpers/gen_ork11e_fixtures.gd -- --only=ork11e_orks_active
##
## How it is built:
##  1. Shell save mirror_custodes_postdeploy: 44x60" board, objectives,
##     deployment zones, mission + secondary deck. Terrain is replaced by the
##     test-only EMPTY layout terrain_layouts/test_open_field.json (not in
##     index_11e.json, never offered in menus) so ranges / LoS are exact.
##  2. Both armies through the real ArmyListManager.load_army_list /
##     apply_army_to_game_state (display names, wargear, loadouts, faction +
##     detachment, faction stratagems).
##  3. Every unit placed from the LAYOUT table below (inches, written for the
##     "Orks at the top" orientation; the reactive fixture rotates 180° about
##     the board centre so objectives keep their relative positions). Engaged
##     pairs sit 1" apart front-to-front (11e Engagement Range is 2"); every
##     other unit is > 2" from all enemies.
##  4. Warboss attached to the Boyz (CharacterAttachmentManager.attach_character).
##  5. Clean state: DEPLOYED, no flags, full wounds, CP 6 each, battle round 2,
##     Command phase. Scenarios move on with transition_to_phase and reposition
##     units with execute_script as needed.
##  6. Gates before writing: every unit coherent (AttackSequence), no model
##     inside a terrain footprint, the engaged pairs engaged and every other
##     unit unengaged (RulesEngine.is_unit_engaged). Any failure = no file.
##  7. SaveLoadManager.save_game → user://saves, then copied into
##     res://tests/saves/ (the committed fixture).

const SHELL := "mirror_custodes_postdeploy"
const TERRAIN_LAYOUT := "test_open_field"
const ORK_ARMY := "ork11e_codex_test"
const ENEMY_ARMY := "custodes_lions"
const PX_PER_INCH := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25   # edge-to-edge gap between models of one unit

# [unit_id, centre_x_in, front_edge_y_in, columns, rows_direction]
# rows_direction -1 = the unit's rows extend toward SMALLER y (Ork side in this
# orientation), +1 toward LARGER y (enemy side). front_edge_y is the edge of the
# FRONT rank facing the opposing side.
const LAYOUT := [
	# ---- Band A: engaged pairs on the centre line (y = 30") ----
	["U_NOBZ_A", 8.0, 29.5, 5, -1],
	["U_CUSTODIAN_GUARD_B", 8.0, 30.5, 3, 1],
	["U_BOYZ_B", 22.0, 29.5, 5, -1],          # on obj_center (22, 30)
	["U_WARBOSS_A", 22.0, 26.6, 1, -1],       # attached to U_BOYZ_B (behind them)
	["U_CUSTODIAN_GUARD_A", 22.0, 30.5, 3, 1],
	["U_MEGANOBZ_A", 36.0, 29.5, 3, -1],
	["U_BLADE_CHAMPION_A", 36.0, 30.5, 1, 1],
	# ---- Band B: engaged pairs pushed into the Ork half (line y = 21") ----
	["U_DEFF_DREAD_A", 14.0, 20.5, 1, -1],
	["U_PROSECUTORS_A", 14.0, 21.5, 2, 1],
	["U_BEAST_SNAGGA_BOYZ_A", 30.0, 20.5, 5, -1],
	["U_ALLARUS_CUSTODIANS_A", 30.0, 21.5, 3, 1],
	# ---- Ork rear rank R1 (front y = 16.5") ----
	["U_FLASH_GITZ_A", 4.0, 16.5, 3, -1],
	["U_TANKBUSTAS_A", 10.0, 16.5, 3, -1],
	["U_BREAKA_BOYZ_A", 16.0, 16.5, 3, -1],
	["U_KOMMANDOS_A", 22.5, 16.5, 5, -1],
	["U_STORMBOYZ_A", 38.0, 16.5, 5, -1],
	# ---- Ork rear rank R2 (front y = 12.5") ----
	["U_GRETCHIN_C", 4.0, 12.5, 5, -1],
	["U_RUNTHERD_A", 4.0, 10.1, 1, -1],
	["U_GRETCHIN_D", 10.5, 12.5, 5, -1],
	["U_MEK_GUNZ_A", 15.5, 12.5, 1, -1],
	["U_KILLA_KANS_A", 20.0, 12.5, 3, -1],
	["U_DEFFKOPTAS_A", 29.0, 12.5, 3, -1],
	["U_WARBIKERS_A", 39.0, 12.5, 3, -1],
	# ---- Ork vehicles R3 (front y = 8.5") ----
	["U_BATTLEWAGON_A", 9.5, 8.5, 1, -1],
	["U_TRUKK_A", 17.5, 8.5, 1, -1],
	["U_RUKKATRUKK_SQUIGBUGGIES_A", 25.0, 8.5, 1, -1],
	["U_DAKKAJET_A", 32.0, 8.5, 1, -1],
	# ---- Custodes rear (6–15" from the Ork band A line) ----
	["U_CUSTODIAN_GUARD_C", 8.0, 38.0, 3, 1],
	["U_BLADE_CHAMPION_B", 15.0, 37.0, 1, 1],
	["U_CUSTODIAN_GUARD_D", 22.0, 38.0, 3, 1],
	["U_BLADE_CHAMPION_C", 29.0, 37.0, 1, 1],
	["U_CUSTODIAN_GUARD_E", 36.0, 38.0, 3, 1],
	["U_CUSTODIAN_GUARD_F", 22.0, 45.0, 3, 1],
]

## Engaged pairs (Ork unit, enemy unit) the gate asserts.
const ENGAGED_PAIRS := [
	["U_NOBZ_A", "U_CUSTODIAN_GUARD_B"],
	["U_BOYZ_B", "U_CUSTODIAN_GUARD_A"],
	["U_MEGANOBZ_A", "U_BLADE_CHAMPION_A"],
	["U_DEFF_DREAD_A", "U_PROSECUTORS_A"],
	["U_BEAST_SNAGGA_BOYZ_A", "U_ALLARUS_CUSTODIANS_A"],
]

const ATTACHMENTS := [["U_WARBOSS_A", "U_BOYZ_B"]]

var GS = null
var _only := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.split("=", true, 1)[1]
		else:
			printerr("[ork11e-fixture] FAIL: unrecognised argument %s" % a)
			quit(2)
			return
	await create_timer(0.5).timeout
	var ok := true
	if _only == "" or _only == "ork11e_orks_active":
		ok = _build("ork11e_orks_active", 1, 1) and ok
	if ok and (_only == "" or _only == "ork11e_orks_reactive"):
		ok = _build("ork11e_orks_reactive", 2, 1) and ok
	quit(0 if ok else 1)


func _fail(msg: String) -> bool:
	printerr("[ork11e-fixture] FAIL: %s" % msg)
	return false


func _build(out_name: String, orks_player: int, active_player: int) -> bool:
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	GS = root.get_node_or_null("GameState")
	if slm == null or alm == null or GS == null or cam == null:
		return _fail("SaveLoadManager / ArmyListManager / CharacterAttachmentManager / GameState missing")
	GameConstants.edition = 11

	if not slm.load_game(SHELL):
		return _fail("could not load shell %s" % SHELL)
	print("[ork11e-fixture] %s: shell %s loaded" % [out_name, SHELL])
	GS.state["units"] = {}
	# Open field: the test-only empty layout (terrain_layouts/test_open_field.json,
	# not in index_11e.json so menus never offer it). Ranges, line of sight and
	# engagement are then exactly what the LAYOUT table says.
	var tm = root.get_node_or_null("TerrainManager")
	if tm == null:
		return _fail("TerrainManager missing")
	tm.load_terrain_layout(TERRAIN_LAYOUT)
	if tm.current_layout != TERRAIN_LAYOUT or not tm.terrain_features.is_empty():
		return _fail("could not switch to the %s terrain layout" % TERRAIN_LAYOUT)
	GS.state.board["terrain_layout"] = TERRAIN_LAYOUT
	GS.state.board["terrain_features"] = []
	GS.state.board["terrain"] = []

	var enemy_player := 2 if orks_player == 1 else 1
	alm.scan_available_armies()
	for spec in [[ORK_ARMY, orks_player], [ENEMY_ARMY, enemy_player]]:
		var data = alm.load_army_list(str(spec[0]), int(spec[1]))
		if data.is_empty() or not data.has("units"):
			return _fail("army list %s did not load" % spec[0])
		alm.apply_army_to_game_state(data, int(spec[1]))
		print("[ork11e-fixture] P%d <- %s (%d units)" % [int(spec[1]), str(spec[0]), data.units.size()])

	# Place every unit; anything in an army but not in LAYOUT is a hard error.
	var laid := {}
	for row in LAYOUT:
		var uid := str(row[0])
		if not GS.state.units.has(uid):
			return _fail("LAYOUT names %s but no such unit was loaded" % uid)
		_place_unit(uid, float(row[1]), float(row[2]), int(row[3]), int(row[4]), orks_player == 2)
		laid[uid] = true
	for uid in GS.state.units:
		if not laid.has(uid):
			return _fail("unit %s has no LAYOUT entry" % uid)

	for uid in GS.state.units:
		var u = GS.state.units[uid]
		u["status"] = 2  # DEPLOYED
		u["flags"] = {}
		u.erase("attached_to")
		if u.has("attachment_data"):
			u["attachment_data"] = {"attached_characters": []}
		u.erase("embarked_in")
		for m in u.get("models", []):
			m["alive"] = true
			m["current_wounds"] = m.get("wounds", 1)
			m["status_effects"] = []
	for pair in ATTACHMENTS:
		cam.attach_character(str(pair[0]), str(pair[1]))
		if str(GS.state.units[str(pair[0])].get("attached_to", "")) != str(pair[1]):
			return _fail("could not attach %s to %s" % [pair[0], pair[1]])

	var st = GS.state
	for p in ["1", "2"]:
		if st.players.has(p):
			st.players[p]["cp"] = 6
	st.meta["battle_round"] = 2
	st.meta["turn"] = 2
	st.meta["phase"] = 6  # COMMAND
	st.meta["active_player"] = active_player
	st.meta["first_turn_player"] = 1
	st["history"] = []
	st["phase_log"] = []
	st["unit_visuals"] = {}

	if not _gates(orks_player):
		return false

	for line in _summary(orks_player):
		print("[ork11e-fixture]   %s" % line)
	if not slm.save_game(out_name):
		return _fail("save_game(%s) failed" % out_name)
	var copied := _copy_into_repo(slm, out_name)
	if not copied:
		return false
	print("[ork11e-fixture] %s written (res://tests/saves/%s.w40ksave)" % [out_name, out_name])
	return true


func _radius_in(model: Dictionary) -> float:
	var mm := float(model.get("base_mm", 32))
	var dims = model.get("base_dimensions", null)
	if typeof(dims) == TYPE_DICTIONARY and not dims.is_empty():
		mm = maxf(float(dims.get("length", mm)), float(dims.get("width", mm)))
	return mm / 25.4 / 2.0


func _place_unit(uid: String, cx: float, front_y: float, cols: int, dir: int, rotate: bool) -> void:
	var models: Array = GS.state.units[uid].get("models", [])
	var n := models.size()
	if n == 0:
		return
	var r := 0.0
	for m in models:
		r = maxf(r, _radius_in(m))
	var cell := r * 2.0 + SPACING_IN
	cols = maxi(1, mini(cols, n))
	for i in range(n):
		var row := i / cols
		var col := i % cols
		var in_row := mini(cols, n - row * cols)
		var x := cx + (float(col) - float(in_row - 1) / 2.0) * cell
		var y := front_y + float(dir) * (r + float(row) * cell)
		if rotate:
			x = BOARD_W_IN - x
			y = BOARD_H_IN - y
		models[i]["position"] = {"x": x * PX_PER_INCH, "y": y * PX_PER_INCH}
		models[i]["rotation"] = 0.0


func _gates(orks_player: int) -> bool:
	var re = root.get_node_or_null("RulesEngine")
	var tm = root.get_node_or_null("TerrainManager")
	var ok := true
	# Coherency (engine predicate).
	for uid in GS.state.units:
		var coh = AttackSequence.check_unit_coherency(GS.state.units[uid])
		if not bool(coh.get("coherent", false)):
			ok = _fail("%s out of coherency (%s)" % [uid, str(coh.get("offenders", []))]) and ok
	# On the board.
	for uid in GS.state.units:
		for m in GS.state.units[uid].get("models", []):
			var p = m.position
			var rr := _radius_in(m) * PX_PER_INCH
			if p.x - rr < 0 or p.y - rr < 0 or p.x + rr > BOARD_W_IN * PX_PER_INCH or p.y + rr > BOARD_H_IN * PX_PER_INCH:
				ok = _fail("%s model %s off the board at %s" % [uid, m.get("id", "?"), str(p)]) and ok
	# Terrain footprints: no model centre inside, and no base overlapping an edge.
	if tm:
		for t in tm.terrain_features:
			var poly = t.get("polygon", PackedVector2Array())
			if not (poly is PackedVector2Array) or poly.size() < 3:
				continue
			for uid in GS.state.units:
				for m in GS.state.units[uid].get("models", []):
					var c := Vector2(float(m.position.x), float(m.position.y))
					var rr := _radius_in(m) * PX_PER_INCH
					var overlap := Geometry2D.is_point_in_polygon(c, poly)
					if not overlap:
						for i in range(poly.size()):
							var a: Vector2 = poly[i]
							var b: Vector2 = poly[(i + 1) % poly.size()]
							if c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)) < rr:
								overlap = true
								break
					if overlap:
						ok = _fail("%s model %s overlaps terrain %s" % [uid, m.get("id", "?"), t.get("id", "?")]) and ok
	# Engagement: pairs engaged, everything else unengaged.
	var paired := {}
	for pair in ENGAGED_PAIRS:
		paired[str(pair[0])] = true
		paired[str(pair[1])] = true
	paired["U_WARBOSS_A"] = true  # attached to an engaged unit
	for uid in GS.state.units:
		var engaged: bool = re.is_unit_engaged(uid, GS.state)
		if paired.has(uid):
			if uid != "U_WARBOSS_A" and not engaged:
				ok = _fail("%s should be engaged" % uid) and ok
		elif engaged:
			ok = _fail("%s should NOT be engaged" % uid) and ok
	return ok


func _summary(orks_player: int) -> Array:
	var out := []
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var p = u.models[0].position
		out.append("P%d %-30s %2d models  first model at (%.1f, %.1f)in  engaged=%s" % [
			int(u.owner), uid, u.models.size(), p.x / PX_PER_INCH, p.y / PX_PER_INCH,
			str(root.get_node("RulesEngine").is_unit_engaged(uid, GS.state))])
	return out


func _copy_into_repo(slm, out_name: String) -> bool:
	var dst_dir := ProjectSettings.globalize_path("res://tests/saves/")
	for ext in [".w40ksave", ".meta"]:
		var src: String = slm.save_directory + out_name + ext
		if not FileAccess.file_exists(src):
			if ext == ".w40ksave":
				return _fail("saved file %s not found" % src)
			continue
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src), dst_dir + out_name + ext)
		if err != OK:
			return _fail("copy %s -> %s failed (%d)" % [src, dst_dir, err])
	return true

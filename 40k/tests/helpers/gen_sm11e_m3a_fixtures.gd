extends SceneTree

## gen_sm11e_m3a_fixtures.gd — builds the two Codex: Space Marines (11e)
## GENERIC detachment stratagem fixtures for WP-M3a (SMCodex11e.gd):
##
##   tests/saves/sm11e_m3a_active.w40ksave   — P1 = Space Marines
##       (armies/sm11e_codex_test.json) ACTIVE vs P2 = Orks (a subset of
##       ork11e_codex_test).
##   tests/saves/sm11e_m3a_reactive.w40ksave — P1 = Orks ACTIVE vs P2 = Space
##       Marines NON-active (same battlefield, owners swapped): the
##       opponent's-turn windows are driven by the Ork player's actions.
##
## Both: battle round 2, P1's Command phase, P1 took the first turn, CP 6 each.
## Tests / scenarios switch the Space Marines detachments in their setup
## (GameState.state.factions[p].detachments + load_faction_stratagems_for_player).
##
## Usage (writes both, or one with --only=<name>):
##   godot --headless --path 40k -s tests/helpers/gen_sm11e_m3a_fixtures.gd
##
## Built like gen_sw11e_s3_fixtures.gd: shell mirror_custodes_postdeploy
## (44x60" board; objectives obj_center (22,30), obj_nml_1 (10,22),
## obj_nml_2 (34,38), obj_home_1 (22,4), obj_home_2 (22,56)), the test-only
## EMPTY terrain layout test_open_field, both armies through the real
## ArmyListManager, the units in LAYOUT placed (inches; Space Marines at the
## bottom = large y), every other unit dropped, clean state. Gates before
## writing: coherency, on the board, the engaged pairs engaged and every other
## unit unengaged, no overlapping bases, the Intercessors embarked within the
## Rhino, the Sternguard wholly within 6" of the Impulsor.
##
## Geometry (what the tests / scenarios rely on):
##  - Band A (line y = 30"): Assault Intercessors (TACTICUS, BATTLELINE, x 22 —
##    within range of obj_center) vs Boyz B; Outrider Squad (MOUNTED, x 37) vs
##    Nobz.
##  - Space Marines unengaged: Hellblasters (TACTICUS INFANTRY, x 8, front 40),
##    Infiltrator Squad (PHOBOS, x 30, front 40), Incursor Squad (PHOBOS, on
##    obj_nml_2 at (34, 38) — x 34 front 37.6 … in range, controlling it),
##    Land Speeder (SPEEDER, x 20, front 44), Gladiator Lancer (VEHICLE, x 14,
##    front 48), Scout Squad (SCOUT SQUAD, x 4, front 52), Sternguard (INFANTRY,
##    x 30, front 51) next to the Impulsor (TRANSPORT, x 35.2, front 51),
##    Rhino (TRANSPORT, x 22, front 54 — within range of obj_home_2) with the
##    Intercessor Squad (BATTLELINE) embarked.
##  - Orks: Kommandos (x 10, front 22), Flash Gitz (x 30, front 22), Mek Gunz
##    (VEHICLE, x 18, front 20), Warbikers (M12, x 24, front 24).

const SHELL := "mirror_custodes_postdeploy"
const TERRAIN_LAYOUT := "test_open_field"
const SM_ARMY := "sm11e_codex_test"
const ORK_ARMY := "ork11e_codex_test"
const PX_PER_INCH := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25

# [unit_id, centre_x_in, front_edge_y_in, columns, rows_direction]
# Space Marines rows extend toward LARGER y (+1), Orks toward SMALLER y (-1).
const LAYOUT := [
	# ---- Band A: engaged pairs on the centre line (y = 30") ----
	["U_ASSAULT_INTERCESSOR_SQUAD_A", 22.0, 30.5, 5, 1],
	["U_BOYZ_B", 22.0, 29.5, 5, -1],
	["U_OUTRIDER_SQUAD_A", 37.0, 30.5, 3, 1],
	["U_NOBZ_A", 37.0, 29.5, 5, -1],
	# ---- Space Marines half: unengaged ----
	["U_HELLBLASTER_SQUAD_A", 8.0, 40.0, 5, 1],
	["U_INFILTRATOR_SQUAD_A", 30.0, 40.0, 5, 1],
	["U_INCURSOR_SQUAD_A", 38.5, 36.4, 3, 1],
	["U_LAND_SPEEDER_A", 20.0, 44.0, 1, 1],
	["U_GLADIATOR_LANCER_A", 14.0, 48.0, 1, 1],
	["U_SCOUT_SQUAD_A", 4.0, 52.0, 5, 1],
	["U_STERNGUARD_VETERAN_SQUAD_A", 30.0, 51.0, 3, 1],
	["U_IMPULSOR_A", 35.2, 51.0, 1, 1],
	["U_RHINO_A", 22.0, 54.0, 1, 1],
	# ---- Ork shooters / movers ----
	["U_KOMMANDOS_A", 10.0, 22.0, 5, -1],
	["U_FLASH_GITZ_A", 30.0, 22.0, 5, -1],
	["U_MEK_GUNZ_A", 18.0, 20.0, 1, -1],
	["U_WARBIKERS_A", 24.0, 24.0, 3, -1],
]

# [passenger, transport] — embarked at build time (no position).
const EMBARKED := [["U_INTERCESSOR_SQUAD_A", "U_RHINO_A"]]

const ENGAGED_PAIRS := [
	["U_BOYZ_B", "U_ASSAULT_INTERCESSOR_SQUAD_A"],
	["U_NOBZ_A", "U_OUTRIDER_SQUAD_A"],
]

var GS = null
var _only := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.split("=", true, 1)[1]
		else:
			printerr("[sm11e-m3a-fixture] FAIL: unrecognised argument %s" % a)
			quit(2)
			return
	await create_timer(0.5).timeout
	var ok := true
	if _only == "" or _only == "sm11e_m3a_active":
		ok = _build("sm11e_m3a_active", 1) and ok
	if ok and (_only == "" or _only == "sm11e_m3a_reactive"):
		ok = _build("sm11e_m3a_reactive", 2) and ok
	quit(0 if ok else 1)


func _fail(msg: String) -> bool:
	printerr("[sm11e-m3a-fixture] FAIL: %s" % msg)
	return false


func _build(out_name: String, sm_player: int) -> bool:
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	GS = root.get_node_or_null("GameState")
	if slm == null or alm == null or GS == null:
		return _fail("SaveLoadManager / ArmyListManager / GameState missing")
	GameConstants.edition = 11
	if not slm.load_game(SHELL):
		return _fail("could not load shell %s" % SHELL)
	GS.state["units"] = {}
	var tm = root.get_node_or_null("TerrainManager")
	if tm == null:
		return _fail("TerrainManager missing")
	tm.load_terrain_layout(TERRAIN_LAYOUT)
	if tm.current_layout != TERRAIN_LAYOUT or not tm.terrain_features.is_empty():
		return _fail("could not switch to the %s terrain layout" % TERRAIN_LAYOUT)
	GS.state.board["terrain_layout"] = TERRAIN_LAYOUT
	GS.state.board["terrain_features"] = []
	GS.state.board["terrain"] = []

	var orks_player := 2 if sm_player == 1 else 1
	alm.scan_available_armies()
	for spec in [[SM_ARMY, sm_player], [ORK_ARMY, orks_player]]:
		var data = alm.load_army_list(str(spec[0]), int(spec[1]))
		if data.is_empty() or not data.has("units"):
			return _fail("army list %s did not load" % spec[0])
		alm.apply_army_to_game_state(data, int(spec[1]))
		print("[sm11e-m3a-fixture] %s: P%d <- %s (%d units)" % [out_name, int(spec[1]), str(spec[0]), data.units.size()])

	var laid := {}
	for row in LAYOUT:
		var uid := str(row[0])
		if not GS.state.units.has(uid):
			return _fail("LAYOUT names %s but no such unit was loaded" % uid)
		_place_unit(uid, float(row[1]), float(row[2]), int(row[3]), int(row[4]))
		laid[uid] = true
	for pair in EMBARKED:
		laid[str(pair[0])] = true
	for uid in GS.state.units.keys():
		if not laid.has(uid):
			GS.state.units.erase(uid)

	for uid in GS.state.units:
		var u = GS.state.units[uid]
		u["status"] = 2  # DEPLOYED
		u["flags"] = {}
		u.erase("attached_to")
		if u.has("attachment_data"):
			u["attachment_data"] = {"attached_characters": []}
		u.erase("embarked_in")
		if u.has("transport_data"):
			u.transport_data["embarked_units"] = []
		for m in u.get("models", []):
			m["alive"] = true
			m["current_wounds"] = m.get("wounds", 1)
			m["status_effects"] = []
	for pair in EMBARKED:
		var pid := str(pair[0])
		var tid := str(pair[1])
		var t = GS.state.units[tid]
		if not t.has("transport_data"):
			return _fail("%s has no transport_data" % tid)
		GS.state.units[pid]["embarked_in"] = tid
		t.transport_data["embarked_units"] = [pid]
		for m in GS.state.units[pid].get("models", []):
			m["position"] = null

	var st = GS.state
	var fac = st.get("factions", {}).get(str(sm_player), {})
	if str(fac.get("name", "")) != "Space Marines":
		return _fail("P%d faction should be Space Marines (got %s)" % [sm_player, str(fac.get("name", ""))])
	for p in ["1", "2"]:
		if st.players.has(p):
			st.players[p]["cp"] = 6
			st.players[p]["bonus_cp_gained_this_round"] = 0
	st.meta["battle_round"] = 2
	st.meta["turn"] = 2
	st.meta["phase"] = 6  # COMMAND
	st.meta["active_player"] = 1
	st.meta["first_turn_player"] = 1
	st["history"] = []
	st["phase_log"] = []
	st["unit_visuals"] = {}

	if not _gates():
		return false
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var p = u.models[0].position
		if p == null:
			print("[sm11e-m3a-fixture]   P%d %-36s %2d models  EMBARKED in %s" % [int(u.owner), uid, u.models.size(), str(u.get("embarked_in", ""))])
			continue
		print("[sm11e-m3a-fixture]   P%d %-36s %2d models  first model at (%.2f, %.2f)in  engaged=%s" % [
			int(u.owner), uid, u.models.size(), p.x / PX_PER_INCH, p.y / PX_PER_INCH,
			str(root.get_node("RulesEngine").is_unit_engaged(uid, GS.state))])
	if not slm.save_game(out_name):
		return _fail("save_game(%s) failed" % out_name)
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
	print("[sm11e-m3a-fixture] %s written (res://tests/saves/%s.w40ksave)" % [out_name, out_name])
	return true


func _radius_in(model: Dictionary) -> float:
	var mm := float(model.get("base_mm", 32))
	var dims = model.get("base_dimensions", null)
	if typeof(dims) == TYPE_DICTIONARY and not dims.is_empty():
		mm = maxf(float(dims.get("length", mm)), float(dims.get("width", mm)))
	return mm / 25.4 / 2.0


func _place_unit(uid: String, cx: float, front_y: float, cols: int, dir: int) -> void:
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
		models[i]["position"] = {"x": x * PX_PER_INCH, "y": y * PX_PER_INCH}
		models[i]["rotation"] = 0.0


func _gates() -> bool:
	var re = root.get_node_or_null("RulesEngine")
	var ok := true
	for uid in GS.state.units:
		if GS.state.units[uid].get("embarked_in", null) != null:
			continue
		var coh = AttackSequence.check_unit_coherency(GS.state.units[uid])
		if not bool(coh.get("coherent", false)):
			ok = _fail("%s out of coherency (%s)" % [uid, str(coh.get("offenders", []))]) and ok
	for uid in GS.state.units:
		for m in GS.state.units[uid].get("models", []):
			var p = m.position
			if p == null:
				continue
			var rr := _radius_in(m) * PX_PER_INCH
			if p.x - rr < 0 or p.y - rr < 0 or p.x + rr > BOARD_W_IN * PX_PER_INCH or p.y + rr > BOARD_H_IN * PX_PER_INCH:
				ok = _fail("%s model %s off the board at %s" % [uid, m.get("id", "?"), str(p)]) and ok
	var paired := {}
	for pair in ENGAGED_PAIRS:
		paired[str(pair[0])] = true
		paired[str(pair[1])] = true
	for uid in GS.state.units:
		if GS.state.units[uid].get("embarked_in", null) != null:
			continue
		var engaged: bool = re.is_unit_engaged(uid, GS.state)
		if paired.has(uid):
			if not engaged:
				ok = _fail("%s should be engaged" % uid) and ok
		elif engaged:
			ok = _fail("%s should NOT be engaged" % uid) and ok
	var meas = root.get_node_or_null("Measurement")
	var ids: Array = GS.state.units.keys()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			for ma in GS.state.units[ids[i]].models:
				if ma.position == null:
					continue
				for mb in GS.state.units[ids[j]].models:
					if mb.position == null:
						continue
					if meas and float(meas.model_to_model_distance_inches(ma, mb)) < -0.01:
						ok = _fail("%s and %s overlap" % [ids[i], ids[j]]) and ok
	# Geometry the scenarios rely on.
	var Mv = load("res://scripts/codex/space_marines/SMCodexAMovement.gd")
	var far: float = Mv._group_farthest_inches("U_STERNGUARD_VETERAN_SQUAD_A", "U_IMPULSOR_A")
	if far > 6.0:
		ok = _fail("Sternguard must be wholly within 6\" of the Impulsor (farthest %.2f\")" % far) and ok
	var mm = root.get_node_or_null("MissionManager")
	var obj_home_2 := {}
	var obj_nml_2 := {}
	for o in GS.state.board.get("objectives", []):
		if str(o.get("id", "")) == "obj_home_2":
			obj_home_2 = o
		if str(o.get("id", "")) == "obj_nml_2":
			obj_nml_2 = o
	if mm and not obj_home_2.is_empty() and not mm.model_in_objective_range(GS.state.units["U_RHINO_A"].models[0], obj_home_2):
		ok = _fail("the Rhino must be within range of obj_home_2") and ok
	var inc_in := false
	for m in GS.state.units["U_INCURSOR_SQUAD_A"].models:
		if mm and not obj_nml_2.is_empty() and mm.model_in_objective_range(m, obj_nml_2):
			inc_in = true
	if not inc_in:
		ok = _fail("the Incursors must be within range of obj_nml_2") and ok
	return ok

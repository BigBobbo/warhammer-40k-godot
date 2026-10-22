extends SceneTree

## gen_sw11e_s2_fixtures.gd — builds the Codex: Space Marines (11e) Space
## Wolves army-rules / detachments / enhancements fixture for WP-S2:
##
##   tests/saves/sw11e_s2_wolves_active.w40ksave — P1 = Space Wolves
##       (armies/sw11e_codex_test.json: Saga of the Great Wolf + Champions of
##       Fenris; WARLORD Logan Grimnar — Transhuman Strategist) ACTIVE vs
##       P2 = Orks (a subset of ork11e_codex_test). Battle round 2, P1's
##       Command phase, P1 took the first turn — loading it runs the start of
##       the battle round (Transhuman Strategist) and P1's Command phase.
##       Enhancements (setup for the S2 tests / scenarios; the list-build half
##       is applied here like ArmyListManager would): Howlmaw (Wolf Priest),
##       Skjald's Foretelling (Wolf Guard Battle Leader), Preyslayer (Arjac
##       Rockfist), A Giant Amongst Giants (Ragnar Blackmane).
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_sw11e_s2_fixtures.gd
##
## Built like gen_cus11e_c3_fixtures.gd: shell mirror_custodes_postdeploy, the
## EMPTY terrain layout test_open_field, both armies through the real
## ArmyListManager, every unit placed from LAYOUT (inches; Space Wolves at the
## bottom = large y), clean state (DEPLOYED, no flags, full wounds, CP 6 each).
## Gates before writing: coherency, on the board, the engaged pairs engaged
## and every other unit unengaged.
##
## Geometry (what the tests / scenarios rely on):
##  - Band A (line y = 30"): Blood Claws A (x 9") vs Boyz B (x 10") — fall
##    back (Tactical Doctrine); Thunderwolf Cavalry A vs Deff Dread A (VEHICLE,
##    x 22") — Legendary Slayers; Wolf Priest A (Howlmaw) vs Meganobz A (x 34").
##  - Gretchin C (2 x 5) at x 30", front y 41" — Grey Hunters A at x 30",
##    front y 50" (9" away): advance + charge lane (Assault Doctrine).
##  - Curse of the Wulfen: Wulfen A (OC 0 on the datasheet) on obj_nml_1
##    (10", 22") with the Wolf Guard Battle Leader A (SPACE WOLVES CHARACTER)
##    ~3" away — the curse gives the Wulfen OC 1 each, so they control it.
##  - Rear: Logan Grimnar (WARLORD) x 22" y 54", Arjac Rockfist x 38" y 48",
##    Ragnar x 14" y 56", Venerable Dreadnought A x 4" y 54".

const SHELL := "mirror_custodes_postdeploy"
const TERRAIN_LAYOUT := "test_open_field"
const SW_ARMY := "sw11e_codex_test"
const ORK_ARMY := "ork11e_codex_test"
const OUT_NAME := "sw11e_s2_wolves_active"
const PX_PER_INCH := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25

# [unit_id, centre_x_in, front_edge_y_in, columns, rows_direction]
const LAYOUT := [
	["U_BLOOD_CLAWS_A", 9.0, 30.5, 5, 1],
	["U_BOYZ_B", 10.0, 29.5, 5, -1],
	["U_THUNDERWOLF_CAVALRY_A", 22.0, 30.5, 3, 1],
	["U_DEFF_DREAD_A", 22.0, 29.5, 1, -1],
	["U_WOLF_PRIEST_A", 34.0, 30.5, 1, 1],
	["U_MEGANOBZ_A", 34.0, 29.5, 3, -1],
	["U_GRETCHIN_C", 30.0, 41.0, 5, -1],
	["U_GREY_HUNTERS_A", 30.0, 50.0, 5, 1],
	["U_WULFEN_A", 10.0, 23.5, 5, -1],
	["U_WOLF_GUARD_BATTLE_LEADER_A", 16.0, 23.5, 1, -1],
	["U_LOGAN_GRIMNAR_A", 22.0, 54.0, 1, 1],
	["U_ARJAC_ROCKFIST_A", 38.0, 48.0, 1, 1],
	["U_RAGNAR_BLACKMANE_A", 14.0, 56.0, 1, 1],
	["U_VENERABLE_DREADNOUGHT_A", 4.0, 54.0, 1, 1],
]

const ENGAGED_PAIRS := [
	["U_BOYZ_B", "U_BLOOD_CLAWS_A"],
	["U_DEFF_DREAD_A", "U_THUNDERWOLF_CAVALRY_A"],
	["U_MEGANOBZ_A", "U_WOLF_PRIEST_A"],
]

## Enhancements given in the fixture (unit -> enhancement name).
const ENHANCEMENTS := {
	"U_WOLF_PRIEST_A": "Howlmaw",
	"U_WOLF_GUARD_BATTLE_LEADER_A": "Skjald's Foretelling",
	"U_ARJAC_ROCKFIST_A": "Preyslayer",
	"U_RAGNAR_BLACKMANE_A": "A Giant Amongst Giants",
}

var GS = null


func _initialize() -> void:
	await create_timer(0.5).timeout
	quit(0 if _build() else 1)


func _fail(msg: String) -> bool:
	printerr("[sw11e-fixture] FAIL: %s" % msg)
	return false


func _build() -> bool:
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

	alm.scan_available_armies()
	for spec in [[SW_ARMY, 1], [ORK_ARMY, 2]]:
		var data = alm.load_army_list(str(spec[0]), int(spec[1]))
		if data.is_empty() or not data.has("units"):
			return _fail("army list %s did not load" % spec[0])
		if int(spec[1]) == 1:
			var enh = load("res://scripts/codex/space_wolves/SWEnhancements11e.gd")
			var det_names = load("res://scripts/codex/ArmyDetachments11e.gd").names_from_army(data)
			for uid in ENHANCEMENTS:
				if not data.units.has(uid):
					return _fail("no %s in %s" % [uid, SW_ARMY])
				data.units[uid].meta["enhancements"] = [ENHANCEMENTS[uid]]
				enh.apply_list_build(uid, data.units[uid], det_names)
		alm.apply_army_to_game_state(data, int(spec[1]))
		print("[sw11e-fixture] P%d <- %s (%d units)" % [int(spec[1]), str(spec[0]), data.units.size()])

	var laid := {}
	for row in LAYOUT:
		var uid := str(row[0])
		if not GS.state.units.has(uid):
			return _fail("LAYOUT names %s but no such unit was loaded" % uid)
		_place_unit(uid, float(row[1]), float(row[2]), int(row[3]), int(row[4]))
		laid[uid] = true
	for uid in GS.state.units.keys():
		if not laid.has(uid):
			GS.state.units.erase(uid)

	for uid in GS.state.units:
		var u = GS.state.units[uid]
		u["status"] = 2  # DEPLOYED
		var keep := {}
		for k in u.get("flags", {}):
			if str(k).begins_with("sw11e_listbuild_"):
				keep[k] = u.flags[k]
		u["flags"] = keep
		u.erase("attached_to")
		if u.has("attachment_data"):
			u["attachment_data"] = {"attached_characters": []}
		u.erase("embarked_in")
		for m in u.get("models", []):
			m["alive"] = true
			m["current_wounds"] = m.get("wounds", 1)
			m["status_effects"] = []
	if not bool(GS.state.units["U_LOGAN_GRIMNAR_A"].get("meta", {}).get("is_warlord", false)):
		return _fail("U_LOGAN_GRIMNAR_A should be the Space Wolves WARLORD (army file)")

	var st = GS.state
	for p in ["1", "2"]:
		if st.players.has(p):
			st.players[p]["cp"] = 6
			st.players[p]["bonus_cp_gained_this_round"] = 0
	st.meta["battle_round"] = 2
	st.meta["turn"] = 2
	st.meta["phase"] = 6  # COMMAND
	st.meta["active_player"] = 1
	st.meta["first_turn_player"] = 1
	st.meta.erase("command_start_resolved")
	st["history"] = []
	st["phase_log"] = []
	st["unit_visuals"] = {}
	for p in ["1", "2"]:
		var f = st.factions.get(p, {})
		for k in f.keys():
			if str(k).begins_with("sw11e_"):
				f.erase(k)

	if not _gates():
		return false
	for obj in st.board.get("objectives", []):
		var op = obj.get("position")
		print("[sw11e-fixture]   objective %s at (%.1f, %.1f)in zone %s" % [str(obj.get("id", "?")), float(op.x) / PX_PER_INCH, float(op.y) / PX_PER_INCH, str(obj.get("zone", ""))])
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var p = u.models[0].position
		print("[sw11e-fixture]   P%d %-32s %2d models  first model at (%.2f, %.2f)in  OC %s  engaged=%s  enh=%s" % [
			int(u.owner), uid, u.models.size(), p.x / PX_PER_INCH, p.y / PX_PER_INCH,
			str(u.meta.get("stats", {}).get("objective_control", "?")),
			str(root.get_node("RulesEngine").is_unit_engaged(uid, GS.state)), str(u.meta.get("enhancements", []))])
	if not slm.save_game(OUT_NAME):
		return _fail("save_game(%s) failed" % OUT_NAME)
	var dst_dir := ProjectSettings.globalize_path("res://tests/saves/")
	for ext in [".w40ksave", ".meta"]:
		var src: String = slm.save_directory + OUT_NAME + ext
		if not FileAccess.file_exists(src):
			if ext == ".w40ksave":
				return _fail("saved file %s not found" % src)
			continue
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src), dst_dir + OUT_NAME + ext)
		if err != OK:
			return _fail("copy %s -> %s failed (%d)" % [src, dst_dir, err])
	print("[sw11e-fixture] %s written (res://tests/saves/%s.w40ksave)" % [OUT_NAME, OUT_NAME])
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
		var coh = AttackSequence.check_unit_coherency(GS.state.units[uid])
		if not bool(coh.get("coherent", false)):
			ok = _fail("%s out of coherency (%s)" % [uid, str(coh.get("offenders", []))]) and ok
	for uid in GS.state.units:
		for m in GS.state.units[uid].get("models", []):
			var p = m.position
			var rr := _radius_in(m) * PX_PER_INCH
			if p.x - rr < 0 or p.y - rr < 0 or p.x + rr > BOARD_W_IN * PX_PER_INCH or p.y + rr > BOARD_H_IN * PX_PER_INCH:
				ok = _fail("%s model %s off the board at %s" % [uid, m.get("id", "?"), str(p)]) and ok
	var paired := {}
	for pair in ENGAGED_PAIRS:
		paired[str(pair[0])] = true
		paired[str(pair[1])] = true
	for uid in GS.state.units:
		var engaged: bool = re.is_unit_engaged(uid, GS.state)
		if paired.has(uid):
			if not engaged:
				ok = _fail("%s should be engaged" % uid) and ok
		elif engaged:
			ok = _fail("%s should NOT be engaged" % uid) and ok
	return ok

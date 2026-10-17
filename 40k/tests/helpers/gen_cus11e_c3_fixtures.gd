extends SceneTree

## gen_cus11e_c3_fixtures.gd — builds the Codex: Adeptus Custodes (11e) army
## rules fixture for WP-C3 (CustodesKatah.gd):
##
##   tests/saves/cus11e_c3_custodes_active.w40ksave — P1 = Adeptus Custodes
##       (adeptus_custodes, codex data, Guardians of the Throne; WARLORD
##       Shield-Captain with Aquila Commander + Master of Ka'tahs) ACTIVE vs
##       P2 = Orks (a subset of ork11e_codex_test). Battle round 2, P1's
##       Command phase, P1 took the first turn — so loading it runs the start
##       of the battle round (Aquila Commander) and P1's readied step.
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_cus11e_c3_fixtures.gd
##
## Built like gen_ork11e_fixtures.gd: shell mirror_custodes_postdeploy, the
## test-only EMPTY terrain layout test_open_field, both armies through the real
## ArmyListManager, every unit placed from LAYOUT (inches; Custodes at the
## bottom = large y), clean state (DEPLOYED, no flags, full wounds, CP 6 each). Gates before writing:
## coherency, on the board, the engaged pairs engaged and every other unit
## unengaged.
##
## Geometry (what the scenarios rely on):
##  - Band A (line y = 30"): Custodian Guard B (x 9") and the Shield-Captain
##    (x 12.8", its own unit) vs Boyz B at x 10"; Blade Champion A vs Deff
##    Dread A (VEHICLE) at x 22"; Contemptor-Achillus vs Meganobz at x 34".
##  - Calistus lane: the Telemon Heavy Dreadnought (VEHICLE, 100 mm base) at
##    x 8" (y 40-43.94") with Witchseekers C right behind it (front y 44.2") —
##    a normal move ~5.7" straight north has to go THROUGH the vehicle, which
##    no non-FLY model may do without CALISTUS ("all types of model").
##  - Gretchin C (2 x 5) at x 30", front y 41" — targets in the Custodes half.
##  - Rear: Witchseekers D x 38" (front y 44"), Shield-Captain on Dawneagle
##    Jetbike x 14" / Caladius x 30" (front 52").

const SHELL := "mirror_custodes_postdeploy"
const TERRAIN_LAYOUT := "test_open_field"
const CUSTODES_ARMY := "adeptus_custodes"
const ORK_ARMY := "ork11e_codex_test"
const OUT_NAME := "cus11e_c3_custodes_active"
const PX_PER_INCH := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25

# [unit_id, centre_x_in, front_edge_y_in, columns, rows_direction]
# Custodes (P1) rows extend toward LARGER y (+1), Orks (P2) toward SMALLER y (-1);
# front_edge_y is the edge of the front rank facing the opposing side.
const LAYOUT := [
	# ---- Band A: engaged pairs on the centre line (y = 30") ----
	["U_CUSTODIAN_GUARD_B", 9.0, 30.5, 3, 1],
	["U_SHIELD_CAPTAIN_A", 12.8, 30.5, 1, 1],     # its own unit (see ATTACHMENTS)
	["U_BOYZ_B", 10.0, 29.5, 5, -1],
	["U_BLADE_CHAMPION_A", 22.0, 30.5, 1, 1],
	["U_DEFF_DREAD_A", 22.0, 29.5, 1, -1],
	["U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H", 34.0, 30.5, 1, 1],
	["U_MEGANOBZ_A", 34.0, 29.5, 3, -1],
	# ---- Calistus lane: Witchseekers C right behind the Telemon (VEHICLE) ----
	["U_TELEMON_HEAVY_DREADNOUGHT_I", 8.0, 40.0, 1, 1],
	["U_WITCHSEEKERS_C", 8.0, 44.2, 4, 1],
	# ---- Ork screen in the Custodes half (shooting targets) ----
	["U_GRETCHIN_C", 30.0, 41.0, 5, -1],
	# ---- Custodes rear ----
	["U_WITCHSEEKERS_D", 38.0, 44.0, 4, 1],
	["U_SHIELD_CAPTAIN_JETBIKE_A", 14.0, 52.0, 1, 1],
	["U_CALADIUS_GRAV-TANK_E", 30.0, 52.0, 1, 1],
]

const ENGAGED_PAIRS := [
	["U_BOYZ_B", "U_CUSTODIAN_GUARD_B"],
	["U_BOYZ_B", "U_SHIELD_CAPTAIN_A"],
	["U_DEFF_DREAD_A", "U_BLADE_CHAMPION_A"],
	["U_MEGANOBZ_A", "U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H"],
]

# No Attached units: the codex data gives Custodian Guard Sodality no
# "CUSTODIAN GUARD SODALITY" keyword, so CharacterAttachmentManager.can_attach
# (keyword match on Leader can_lead) refuses the Shield-Captain — reported in
# WP-C3's report. Attached-unit ka'tah behaviour is covered headless.
const ATTACHMENTS := []

var GS = null


func _initialize() -> void:
	await create_timer(0.5).timeout
	quit(0 if _build() else 1)


func _fail(msg: String) -> bool:
	printerr("[cus11e-fixture] FAIL: %s" % msg)
	return false


func _build() -> bool:
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	GS = root.get_node_or_null("GameState")
	if slm == null or alm == null or GS == null or cam == null:
		return _fail("SaveLoadManager / ArmyListManager / CharacterAttachmentManager / GameState missing")
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
	for spec in [[CUSTODES_ARMY, 1], [ORK_ARMY, 2]]:
		var data = alm.load_army_list(str(spec[0]), int(spec[1]))
		if data.is_empty() or not data.has("units"):
			return _fail("army list %s did not load" % spec[0])
		alm.apply_army_to_game_state(data, int(spec[1]))
		print("[cus11e-fixture] P%d <- %s (%d units)" % [int(spec[1]), str(spec[0]), data.units.size()])

	var laid := {}
	for row in LAYOUT:
		var uid := str(row[0])
		if not GS.state.units.has(uid):
			return _fail("LAYOUT names %s but no such unit was loaded" % uid)
		_place_unit(uid, float(row[1]), float(row[2]), int(row[3]), int(row[4]))
		laid[uid] = true
	# Every Custodes unit is laid out; the Ork units not in LAYOUT are dropped.
	for uid in GS.state.units.keys():
		if laid.has(uid):
			continue
		if int(GS.state.units[uid].get("owner", 0)) == 1:
			return _fail("Custodes unit %s has no LAYOUT entry" % uid)
		GS.state.units.erase(uid)

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
	if not bool(GS.state.units["U_SHIELD_CAPTAIN_A"].get("meta", {}).get("is_warlord", false)):
		return _fail("U_SHIELD_CAPTAIN_A should be the Custodes WARLORD (army file)")

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
	st["history"] = []
	st["phase_log"] = []
	st["unit_visuals"] = {}

	if not _gates():
		return false
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var p = u.models[0].position
		print("[cus11e-fixture]   P%d %-38s %2d models  first model at (%.2f, %.2f)in  engaged=%s" % [
			int(u.owner), uid, u.models.size(), p.x / PX_PER_INCH, p.y / PX_PER_INCH,
			str(root.get_node("RulesEngine").is_unit_engaged(uid, GS.state))])
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
	print("[cus11e-fixture] %s written (res://tests/saves/%s.w40ksave)" % [OUT_NAME, OUT_NAME])
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

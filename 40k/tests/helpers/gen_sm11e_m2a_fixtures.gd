extends SceneTree

## gen_sm11e_m2a_fixtures.gd — builds the Codex: Space Marines (11e) generic
## army-rules / detachments-A fixture for WP-M2a:
##
##   tests/saves/sm11e_m2a_marines_active.w40ksave — P1 = Space Marines
##       (armies/sm11e_codex_test.json, faction "Space Marines"; WARLORD
##       Captain — Transhuman Strategist) ACTIVE vs P2 = Orks (a subset of
##       ork11e_codex_test). Battle round 2, P1's Command phase, P1 took the
##       first turn — loading it runs the start of the battle round
##       (Transhuman Strategist) and P1's Command phase.
##       P1 took ALL SEVEN WP-M2a detachments (Gladius Task Force primary +
##       Ironstorm Spearhead, Stormlance / Gauntlet / Tacticus Attack Force,
##       Phobos Shadow / Shock Force) so every rule and enhancement is live;
##       tests / scenarios narrow factions.1.detachments for A/B checks.
##       Enhancements (list-build half applied here like ArmyListManager):
##       see ENHANCEMENTS below.
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_sm11e_m2a_fixtures.gd
##
## Built like gen_sw11e_s2_fixtures.gd: shell mirror_custodes_postdeploy, the
## EMPTY terrain layout test_open_field (tests inject a dense ruin where they
## need a hidden unit), both armies through the real ArmyListManager, every
## unit placed from LAYOUT (inches; Space Marines at the bottom = large y),
## clean state (DEPLOYED, no flags, full wounds, CP 6 each). The Captain in
## Phobos Armour starts EMBARKED in the Rhino (Damocles-class Uplink).
## Gates before writing: coherency, on the board, the engaged pair engaged and
## every other unit unengaged.
##
## Geometry (what the tests / scenarios rely on):
##  - Band A (y = 30"): Ancient A (Standard of the Emperor Ascendant, x 8")
##    and Lieutenant A (Laurels of Triumph, x 10") engaged with Boyz B.
##  - Gretchin C (x 22", front y 36") — Intercessors A (x 22", front y 44",
##    8" away): advance + charge lane (Assault Doctrine).
##  - Impulsor A (x 36", y 47") — Deff Dread A (VEHICLE, x 34", front y 28").
##  - Land Speeder A (Auspex, x 40", y 40") — Meganobz A (x 40", front 30").
##  - Rhino A (x 28", y 47") carries the Captain in Phobos Armour (Damocles).

const SHELL := "mirror_custodes_postdeploy"
const TERRAIN_LAYOUT := "test_open_field"
const SM_ARMY := "sm11e_codex_test"
const ORK_ARMY := "ork11e_codex_test"
const OUT_NAME := "sm11e_m2a_marines_active"
const PX_PER_INCH := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25

const DETACHMENTS := ["Gladius Task Force", "Ironstorm Spearhead", "Stormlance Task Force", "Gauntlet Task Force",
	"Phobos Shadow Force", "Tacticus Attack Force", "Phobos Shock Force"]

# [unit_id, centre_x_in, front_edge_y_in, columns, rows_direction]
const LAYOUT := [
	["U_ANCIENT_A", 8.0, 30.5, 1, 1],
	["U_LIEUTENANT_A", 10.0, 30.5, 1, 1],
	["U_BOYZ_B", 9.0, 29.5, 5, -1],
	["U_GRETCHIN_C", 22.0, 36.0, 5, -1],
	["U_INTERCESSOR_SQUAD_A", 22.0, 44.0, 5, 1],
	["U_DEFF_DREAD_A", 34.0, 28.0, 1, -1],
	["U_MEGANOBZ_A", 41.0, 30.0, 3, -1],
	["U_IMPULSOR_A", 36.0, 47.0, 1, 1],
	["U_RHINO_A", 28.0, 47.0, 1, 1],
	["U_REDEMPTOR_DREADNOUGHT_A", 42.0, 50.0, 1, 1],
	["U_REPULSOR_A", 28.0, 53.5, 1, 1],
	["U_GLADIATOR_LANCER_A", 17.0, 54.0, 1, 1],
	["U_OUTRIDER_SQUAD_A", 8.0, 44.5, 3, 1],
	["U_LAND_SPEEDER_A", 40.0, 40.0, 1, 1],
	["U_INFILTRATOR_SQUAD_A", 13.0, 40.0, 5, 1],
	["U_SCOUT_SQUAD_A", 5.0, 51.0, 5, 1],
	["U_LIEUTENANT_IN_PHOBOS_ARMOUR_A", 19.0, 49.0, 1, 1],
	["U_LIEUTENANT_WITH_COMBI_WEAPON_A", 31.0, 41.0, 1, 1],
	["U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", 35.0, 53.0, 1, 1],
	["U_CAPTAIN_A", 22.0, 57.0, 1, 1],
	["U_JUDICIAR_A", 38.0, 57.0, 1, 1],
	["U_APOTHECARY_A", 10.0, 57.0, 1, 1],
	["U_TECHMARINE_A", 4.0, 57.0, 1, 1],
	["U_CHAPLAIN_A", 42.0, 57.0, 1, 1],
	["U_LIBRARIAN_A", 13.0, 49.0, 1, 1],
	["U_CHIEF_LIBRARIAN_TIGURIUS_A", 32.0, 57.0, 1, 1],
	["U_CAPTAIN_IN_PHOBOS_ARMOUR_A", 28.0, 58.5, 1, 1],  # placed, then embarked in the Rhino
]

const EMBARKED := {"U_CAPTAIN_IN_PHOBOS_ARMOUR_A": "U_RHINO_A"}

const ENGAGED_PAIRS := [
	["U_BOYZ_B", "U_ANCIENT_A"],
	["U_BOYZ_B", "U_LIEUTENANT_A"],
]

## Enhancements given in the fixture (unit -> enhancement name).
const ENHANCEMENTS := {
	"U_ANCIENT_A": "Standard of the Emperor Ascendant",
	"U_LIEUTENANT_A": "Laurels of Triumph",
	"U_CAPTAIN_A": "Adept of the Codex",
	"U_CHAPLAIN_A": "Artificer Armour",
	"U_REPULSOR_A": "Redoubtable Machine Spirit",
	"U_GLADIATOR_LANCER_A": "Gunnery Honours",
	"U_OUTRIDER_SQUAD_A": "Supercharged Engines",
	"U_LAND_SPEEDER_A": "Auspex Triangulation Shrines",
	"U_TECHMARINE_A": "Linebreaker Onslaught",
	"U_CAPTAIN_IN_PHOBOS_ARMOUR_A": "Damocles-class Uplink",
	"U_LIEUTENANT_IN_PHOBOS_ARMOUR_A": "Venator Omni-auspex",
	"U_LIEUTENANT_WITH_COMBI_WEAPON_A": "Execute and Redeploy",
	"U_JUDICIAR_A": "Martial Paragon",
	"U_APOTHECARY_A": "Spearpoint War Leader",
	"U_LIBRARIAN_IN_PHOBOS_ARMOUR_A": "Seal of Shrouding",
}

var GS = null


func _initialize() -> void:
	await create_timer(0.5).timeout
	quit(0 if _build() else 1)


func _fail(msg: String) -> bool:
	printerr("[sm11e-fixture] FAIL: %s" % msg)
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
	for spec in [[SM_ARMY, 1], [ORK_ARMY, 2]]:
		var data = alm.load_army_list(str(spec[0]), int(spec[1]))
		if data.is_empty() or not data.has("units"):
			return _fail("army list %s did not load" % spec[0])
		if int(spec[1]) == 1:
			data["faction"]["detachment"] = DETACHMENTS[0]
			data["faction"]["detachments"] = DETACHMENTS.duplicate()
			var enh = load("res://scripts/codex/space_marines/SMDetachmentsA.gd")
			for uid in data.units:
				data.units[uid].meta["enhancements"] = []
			for uid in ENHANCEMENTS:
				if not data.units.has(uid):
					return _fail("no %s in %s" % [uid, SM_ARMY])
				data.units[uid].meta["enhancements"] = [ENHANCEMENTS[uid]]
				enh.apply_list_build(uid, data.units[uid], DETACHMENTS)
		alm.apply_army_to_game_state(data, int(spec[1]))
		print("[sm11e-fixture] P%d <- %s (%d units)" % [int(spec[1]), str(spec[0]), data.units.size()])

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
			if str(k).begins_with("sm11e_listbuild_") or str(k).begins_with("sw11e_listbuild_"):
				keep[k] = u.flags[k]
		u["flags"] = keep
		u.erase("attached_to")
		if u.has("attachment_data"):
			u["attachment_data"] = {"attached_characters": []}
		u.erase("embarked_in")
		if u.has("transport_data") and u.transport_data is Dictionary:
			u.transport_data["embarked_units"] = []
		for m in u.get("models", []):
			m["alive"] = true
			m["current_wounds"] = m.get("wounds", 1)
			m["status_effects"] = []
	# Embark (Damocles-class Uplink: the Captain in Phobos Armour rides in the Rhino).
	for uid in EMBARKED:
		var tid: String = EMBARKED[uid]
		var u = GS.state.units[uid]
		var t = GS.state.units[tid]
		u["embarked_in"] = tid
		for m in u.models:
			m["position"] = null
		if not t.has("transport_data") or not (t.transport_data is Dictionary):
			t["transport_data"] = {"capacity": 12, "embarked_units": []}
		t.transport_data["embarked_units"] = [uid]
	if not bool(GS.state.units["U_CAPTAIN_A"].get("meta", {}).get("is_warlord", false)):
		return _fail("U_CAPTAIN_A should be the Space Marines WARLORD (army file)")

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
			if str(k).begins_with("sw11e_") or str(k).begins_with("sm11e_"):
				f.erase(k)
	st.factions["1"]["detachment"] = DETACHMENTS[0]
	st.factions["1"]["detachments"] = DETACHMENTS.duplicate()

	if not _gates():
		return false
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var p = u.models[0].position
		var pos_txt := "embarked in %s" % str(u.get("embarked_in", "")) if p == null else "(%.2f, %.2f)in" % [p.x / PX_PER_INCH, p.y / PX_PER_INCH]
		print("[sm11e-fixture]   P%d %-36s %2d models  %s  engaged=%s  enh=%s" % [
			int(u.owner), uid, u.models.size(), pos_txt,
			str(root.get_node("RulesEngine").is_unit_engaged(uid, GS.state)) if p != null else "-", str(u.meta.get("enhancements", []))])
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
	print("[sm11e-fixture] %s written (res://tests/saves/%s.w40ksave)" % [OUT_NAME, OUT_NAME])
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
	return ok

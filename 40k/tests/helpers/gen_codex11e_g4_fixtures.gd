extends SceneTree

## gen_codex11e_g4_fixtures.gd — builds the WP-G4 windowed scenario fixtures
## (Codex: Adeptus Custodes 11e ADVANCED FIREPOWER; Codex: Orks 11e BIG'ED
## BOSSBUNKA — Raucous Occupants, Fortification, Ramshackle Cover):
##
##   tests/saves/cus11e_g4_shoot      P1 Custodes' turn: Caladius Annihilator vs
##                                     an Ork Deff Dread (VEHICLE) and Gretchin.
##   tests/saves/ork11e_g4_fort       P1 Orks' turn: Custodian Guard (P2) engaged
##                                     with ONLY the Big'ed Bossbunka; Boyz to shoot it.
##   tests/saves/ork11e_g4_fort_move  P2 Custodes' turn: the same engagement (fall back).
##   tests/saves/ork11e_g4_cover      P2 Custodes' turn: Custodian Guard shooting at
##                                     Boyz partly hidden behind the Bossbunka.
##   tests/saves/ork11e_g4_oc         P1 Orks' turn: the Bossbunka on P1's home
##                                     objective with Boyz embarked; Custodian Guard
##                                     (P2) contesting the same objective.
##
## Armies: the codex rosters tests/fixtures/cus11e_ab_roster.json (Custodes)
## and ork11e_ab_roster_b.json / _c.json (Orks), processed through
## ArmyListManager like a loaded army. Shell mirror_custodes_postdeploy (44x60"
## board, objectives incl. obj_home_1 / obj_home_2), the EMPTY terrain layout
## test_open_field; every unit placed explicitly (inches), clean state
## (DEPLOYED, no flags, full wounds, CP 6), the Command phase of the active
## player (scenarios transition to their phase).
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_codex11e_g4_fixtures.gd [name ...]
##
## NOTE user:// is shared between worktrees: the user://saves copy is removed
## after writing (ScenarioRunner restages it from tests/saves).

const SHELL := "mirror_custodes_postdeploy"
const OPEN_FIELD := "test_open_field"
const PX := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25

## Placement: [unit_id, centre_x_in, centre_y_in, columns]. "embark": [[unit, transport]].
const FIXTURES := {
	"cus11e_g4_shoot": {
		"p1": "cus11e_ab_roster", "p2": ["ork11e_ab_roster_c"], "active": 1,
		"place": [
			["U_ANNIHILATOR_A", 16.0, 50.0, 1],
			["U_DEFF_DREAD_A", 16.0, 30.0, 1],
			["U_GRETCHIN_A", 32.0, 30.0, 5],
		],
	},
	"ork11e_g4_fort": {
		"p1": ["ork11e_ab_roster_b"], "p2": "cus11e_ab_roster", "active": 1,
		"place": [
			["U_BIGED_BOSSBUNKA_A", 22.0, 24.0, 1],
			["U_GUARD_A", 22.0, 26.4, 3],
			["U_BOYZ_D", 22.0, 12.0, 5],
		],
		"engaged": [["U_GUARD_A", "U_BIGED_BOSSBUNKA_A"]],
	},
	"ork11e_g4_fort_move": {
		"p1": ["ork11e_ab_roster_b"], "p2": "cus11e_ab_roster", "active": 2,
		"place": [
			["U_BIGED_BOSSBUNKA_A", 22.0, 24.0, 1],
			["U_GUARD_A", 22.0, 26.4, 3],
			["U_BOYZ_D", 22.0, 10.0, 5],
		],
		"engaged": [["U_GUARD_A", "U_BIGED_BOSSBUNKA_A"]],
	},
	"ork11e_g4_cover": {
		"p1": ["ork11e_ab_roster_b"], "p2": "cus11e_ab_roster", "active": 2,
		"place": [
			["U_BOYZ_D", 22.0, 16.0, 5],
			["U_BIGED_BOSSBUNKA_A", 22.0, 24.0, 1],
			["U_GUARD_A", 22.0, 40.0, 3],
		],
	},
	"ork11e_g4_oc": {
		"p1": ["ork11e_ab_roster_b"], "p2": "cus11e_ab_roster", "active": 1,
		"place": [
			["U_BIGED_BOSSBUNKA_A", 22.0, 4.0, 1],
			["U_GUARD_A", 22.0, 7.8, 3],
		],
		"embark": [["U_BOYZ_D", "U_BIGED_BOSSBUNKA_A"]],
	},
}

var GS = null


func _initialize() -> void:
	await create_timer(0.5).timeout
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		names.append(a)
	if names.is_empty():
		names = FIXTURES.keys()
	var ok := true
	for n in names:
		if not FIXTURES.has(n):
			printerr("[g4-fixture] unknown fixture %s" % n)
			ok = false
			continue
		ok = _build(str(n), FIXTURES[n]) and ok
	quit(0 if ok else 1)


func _fail(msg: String) -> bool:
	printerr("[g4-fixture] FAIL: %s" % msg)
	return false


func _json(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/%s.json" % name, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}


## Merge one or more roster files into one processed army for `player`.
func _army(alm, src, player: int) -> Dictionary:
	var names: Array = src if src is Array else [src]
	var out := {}
	for n in names:
		var d := _json(str(n))
		if d.is_empty():
			return {}
		var p: Dictionary = alm._process_army_data(d, player)
		if out.is_empty():
			out = p
		else:
			for k in p.units:
				out.units[k] = p.units[k]
	return out


func _build(name: String, spec: Dictionary) -> bool:
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	var tm = root.get_node_or_null("TerrainManager")
	GS = root.get_node_or_null("GameState")
	if slm == null or alm == null or GS == null or tm == null:
		return _fail("autoloads missing")
	GameConstants.edition = 11
	if not slm.load_game(SHELL):
		return _fail("could not load shell %s" % SHELL)
	GS.state["units"] = {}
	tm.load_terrain_layout(OPEN_FIELD)
	if tm.current_layout != OPEN_FIELD:
		return _fail("could not switch to the %s terrain layout" % OPEN_FIELD)
	GS.state.board["terrain_layout"] = OPEN_FIELD
	GS.state.board["terrain_features"] = []
	GS.state.board["terrain"] = []
	for p in [1, 2]:
		var army := _army(alm, spec["p%d" % p], p)
		if army.is_empty():
			return _fail("%s: P%d army did not load" % [name, p])
		army.faction["team_name"] = "WP-G4"
		alm.apply_army_to_game_state(army, p)

	var keep := {}
	for row in spec.get("place", []):
		var uid := str(row[0])
		if not GS.state.units.has(uid):
			return _fail("%s: no unit %s" % [name, uid])
		_place_unit(uid, float(row[1]), float(row[2]), int(row[3]))
		keep[uid] = true
	for pair in spec.get("embark", []):
		keep[str(pair[0])] = true
	for uid in GS.state.units.keys():
		if not keep.has(uid):
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
		u.meta["is_warlord"] = false
	for pair in spec.get("embark", []):
		var eu = GS.state.units[str(pair[0])]
		eu["embarked_in"] = str(pair[1])
		for m in eu.models:
			m["position"] = null
		var t = GS.state.units[str(pair[1])]
		if not t.has("transport_data"):
			t["transport_data"] = {}
		t.transport_data["embarked_units"] = [str(pair[0])]
	for p in [1, 2]:
		for uid in GS.state.units:
			var u = GS.state.units[uid]
			if int(u.owner) == p and "CHARACTER" in u.meta.get("keywords", []):
				u.meta["is_warlord"] = true
				break

	var st = GS.state
	for p in ["1", "2"]:
		if st.players.has(p):
			st.players[p]["cp"] = 6
			st.players[p]["bonus_cp_gained_this_round"] = 0
	var active := int(spec.get("active", 1))
	st.meta["battle_round"] = 2
	st.meta["turn"] = 2 + (1 if active == 1 else 2)
	st.meta["phase"] = 6  # COMMAND
	st.meta["active_player"] = active
	st.meta["first_turn_player"] = 1
	st["history"] = []
	st["phase_log"] = []
	st["unit_visuals"] = {}

	if not _gates(name, spec):
		return false
	var re = root.get_node("RulesEngine")
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var p = u.models[0].position
		if p == null:
			print("[g4-fixture]   P%d %-24s embarked in %s" % [int(u.owner), uid, str(u.get("embarked_in", ""))])
			continue
		print("[g4-fixture]   P%d %-24s %2d models  first at (%.2f, %.2f)in  engaged=%s" % [
			int(u.owner), uid, u.models.size(), p.x / PX, p.y / PX, str(re.is_unit_engaged(uid, GS.state))])
	if not slm.save_game(name):
		return _fail("save_game(%s) failed" % name)
	var dst_dir := ProjectSettings.globalize_path("res://tests/saves/")
	for ext in [".w40ksave", ".meta"]:
		var src: String = slm.save_directory + name + ext
		if not FileAccess.file_exists(src):
			if ext == ".w40ksave":
				return _fail("saved file %s not found" % src)
			continue
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src), dst_dir + name + ext)
		if err != OK:
			return _fail("copy %s -> %s failed (%d)" % [src, dst_dir, err])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(src))
	print("[g4-fixture] %s written (res://tests/saves/%s.w40ksave)" % [name, name])
	return true


func _radius_in(model: Dictionary) -> float:
	var mm := float(model.get("base_mm", 32))
	var dims = model.get("base_dimensions", null)
	if typeof(dims) == TYPE_DICTIONARY and not dims.is_empty():
		mm = maxf(float(dims.get("length", mm)), float(dims.get("width", mm)))
	return mm / 25.4 / 2.0


## A grid of `cols` columns centred on (cx, cy); rows grow toward larger y.
func _place_unit(uid: String, cx: float, cy: float, cols: int) -> void:
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
		var y := cy + float(row) * cell
		models[i]["position"] = {"x": x * PX, "y": y * PX}
		models[i]["rotation"] = 0.0


func _gates(name: String, spec: Dictionary) -> bool:
	var re = root.get_node_or_null("RulesEngine")
	var ok := true
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		if u.get("embarked_in", null) != null:
			continue
		var coh = AttackSequence.check_unit_coherency(u)
		if not bool(coh.get("coherent", false)):
			ok = _fail("%s: %s out of coherency (%s)" % [name, uid, str(coh.get("offenders", []))]) and ok
		for m in u.get("models", []):
			var p = m.position
			var rr := _radius_in(m) * PX
			if p.x - rr < 0 or p.y - rr < 0 or p.x + rr > BOARD_W_IN * PX or p.y + rr > BOARD_H_IN * PX:
				ok = _fail("%s: %s model %s off the board at %s" % [name, uid, m.get("id", "?"), str(p)]) and ok
	var paired := {}
	for pair in spec.get("engaged", []):
		paired[str(pair[0])] = true
		paired[str(pair[1])] = true
		if not re.check_units_in_engagement_range(GS.state.units[str(pair[0])], GS.state.units[str(pair[1])], GS.state):
			ok = _fail("%s: %s should be engaged with %s" % [name, pair[0], pair[1]]) and ok
	for uid in GS.state.units:
		if GS.state.units[uid].get("embarked_in", null) != null:
			continue
		var engaged: bool = re.is_unit_engaged(uid, GS.state)
		if engaged and not paired.has(uid):
			ok = _fail("%s: %s should NOT be engaged" % [name, uid]) and ok
	var meas = root.get_node_or_null("Measurement")
	var ids: Array = GS.state.units.keys()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			for ma in GS.state.units[ids[i]].models:
				for mb in GS.state.units[ids[j]].models:
					if ma.position == null or mb.position == null:
						continue
					if meas and float(meas.model_to_model_distance_inches(ma, mb)) < -0.01:
						ok = _fail("%s: %s and %s overlap" % [name, ids[i], ids[j]]) and ok
	return ok

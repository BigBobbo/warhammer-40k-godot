extends SceneTree

## gen_cus11e_c7_fixtures.gd — builds the WP-C7 (Codex: Adeptus Custodes 11e
## DATASHEET abilities, scripts/codex/custodes/CustodesAbilities.gd) windowed
## scenario fixtures:
##
##   tests/saves/cus11e_c7_<name>.w40ksave — Adeptus Custodes = units of the
##       codex roster tests/fixtures/cus11e_ab_roster.json (all 29 datasheets,
##       generated from the codex data), Orks = armies/ork11e_codex_test.json.
##       The Custodes are P1 or P2 per fixture ("custodes"); the active player
##       is "active"; battle round "round" (default 2); the Command phase of
##       the active player (scenarios transition to their phase).
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_cus11e_c7_fixtures.gd [name ...]
##
## Built like gen_ork11e_ab_fixtures.gd: shell mirror_custodes_postdeploy (44x60"
## board), the EMPTY terrain layout test_open_field, every unit placed from its
## row (inches; Custodes at the bottom = large y, rows growing away from the
## enemy), clean state (DEPLOYED, no flags, full wounds, CP 6). Gates before
## writing: coherency, on the board, the engaged pairs engaged and every other
## unit unengaged, attachments in place, and the ability offers each scenario
## relies on.
##
## NOTE user:// is shared between worktrees: the stale user://saves copy is
## removed after writing (ScenarioRunner restages it from tests/saves).

const SHELL := "mirror_custodes_postdeploy"
const OPEN_FIELD := "test_open_field"
const ROSTER := "cus11e_ab_roster"
const ORK_ARMY := "ork11e_codex_test"
const PX_PER_INCH := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25

# Row: [unit_id, centre_x_in, front_edge_y_in, columns]. Custodes rows grow
# toward LARGER y, Ork rows toward SMALLER y; front_edge_y faces the enemy.
const FIXTURES := {
	# P1 Custodes' Fight phase: Moment Shackle + Neutronium Cascade Mine at the
	# start of the phase; Sweeping Advance at its end.
	"fight": {
		"custodes": 1, "active": 1,
		"cus": [
			["U_TRAJANN_A", 8.0, 30.5, 1],
			["U_VENATARI_KD_A", 22.0, 31.5, 3],
			["U_SC_JETBIKE_A", 36.0, 30.5, 1],
		],
		"orks": [
			["U_BOYZ_B", 8.0, 29.5, 5],
			["U_GRETCHIN_C", 22.0, 29.0, 5],
			["U_GRETCHIN_D", 36.0, 29.5, 5],
		],
		"engaged": [["U_TRAJANN_A", "U_BOYZ_B"], ["U_SC_JETBIKE_A", "U_GRETCHIN_D"]],
		"offers": [[1, "phase_start", 10, 1, ["moment_shackle", "neutronium_cascade_mine"]]],
	},
	# Battle round 1, P1 Custodes' Command phase: Sword of the Throne.
	"round1": {
		"custodes": 1, "active": 1, "round": 1,
		"cus": [
			["U_BLADE_CHAMPION_A", 14.0, 46.0, 1],
			["U_GUARD_A", 24.0, 46.0, 3],
		],
		"orks": [
			["U_BOYZ_B", 14.0, 22.0, 5],
			["U_DEFF_DREAD_A", 30.0, 22.0, 1],
		],
		"offers": [[1, "phase_start", 6, 1, ["sword_of_the_throne"]]],
	},
	# P1 Orks' Shooting phase vs P2 Custodes: Praesidium Shield, Vengeful
	# Surge (Shield-Captain), Repulsor Suspensor Technology (Coronus).
	"enemy_shoot": {
		"custodes": 2, "active": 1,
		"cus": [
			["U_SHIELD_CAPTAIN_A", 12.0, 38.0, 1],
			["U_CORONUS_A", 32.0, 38.0, 1],
		],
		"orks": [
			["U_TANKBUSTAS_A", 12.0, 27.0, 3],
			["U_FLASH_GITZ_A", 32.0, 24.0, 5],
		],
	},
	# P1 Custodes' Shooting phase: Sanctified Flames, Mobile Hunter, Purity of
	# Execution, Captain-General (aura), Destructor Optics.
	"shoot": {
		"custodes": 1, "active": 1,
		"cus": [
			["U_WITCHSEEKERS_A", 5.0, 40.0, 5],
			["U_PALLAS_A", 15.0, 44.0, 1],
			["U_PROSECUTORS_A", 25.0, 44.0, 5],
			["U_GUARD_A", 37.0, 42.0, 3],
			["U_TRAJANN_A", 37.0, 47.0, 1],
			["U_CALADIUS_A", 15.0, 52.0, 1],
		],
		"orks": [
			["U_GRETCHIN_C", 5.0, 33.0, 5],
			["U_BOYZ_B", 15.0, 30.0, 5],
			["U_NOBZ_A", 25.0, 30.0, 5],
			["U_MEGANOBZ_A", 37.0, 30.0, 3],
		],
	},
	# P1 Custodes' Movement phase: Archeotech Teleport-shunter (the Allarus
	# Shield-Captain leading Allarus Custodians).
	"move": {
		"custodes": 1, "active": 1,
		"cus": [
			["U_ALLARUS_A", 20.0, 48.0, 3],
			["U_SC_ALLARUS_A", 20.0, 51.5, 1],
		],
		"orks": [
			["U_BOYZ_B", 20.0, 14.0, 5],
		],
		"attach": [["U_SC_ALLARUS_A", "U_ALLARUS_A"]],
		"offers": [[1, "movement_phase_start", 7, 1, ["archeotech_teleport_shunter"]]],
	},
	# The end of P1 Orks' Fight phase vs P2 Custodes: Take Wing (Venatari),
	# Infernus Firebombs (Ares; the Dakkajet is an AIRCRAFT — no option).
	"fight_end": {
		"custodes": 2, "active": 1,
		"cus": [
			["U_ARES_A", 14.0, 46.0, 1],
			["U_VENATARI_VL_A", 32.0, 44.0, 3],
		],
		"orks": [
			["U_BOYZ_B", 14.0, 30.0, 5],
			["U_DAKKAJET_A", 32.0, 30.0, 1],
		],
		"offers": [[2, "fight_phase_end", 10, 1, ["take_wing", "infernus_firebombs"]]],
	},
	# P1 Orks' Fight phase vs P2 Custodes: Deft Parry (Vigilators engaged with
	# Boyz that charged).
	"enemy_fight": {
		"custodes": 2, "active": 1,
		"cus": [
			["U_VIGILATORS_A", 16.0, 30.5, 5],
		],
		"orks": [
			["U_BOYZ_B", 16.0, 29.5, 5],
		],
		"engaged": [["U_VIGILATORS_A", "U_BOYZ_B"]],
		"flags": {"U_BOYZ_B": {"charged_this_turn": true}},
	},
}

var GS = null
var CA = null


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
			printerr("[cus11e-c7-fixture] unknown fixture %s" % n)
			ok = false
			continue
		ok = _build(str(n), FIXTURES[n]) and ok
	quit(0 if ok else 1)


func _fail(msg: String) -> bool:
	printerr("[cus11e-c7-fixture] FAIL: %s" % msg)
	return false


func _json(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/%s.json" % name, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _build(name: String, spec: Dictionary) -> bool:
	var out_name := "cus11e_c7_" + name
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	var tm = root.get_node_or_null("TerrainManager")
	GS = root.get_node_or_null("GameState")
	CA = load("res://scripts/codex/custodes/CustodesAbilities.gd")
	if slm == null or alm == null or GS == null or cam == null or tm == null:
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

	var cus_player := int(spec.get("custodes", 1))
	var ork_player := 2 if cus_player == 1 else 1
	var roster := _json(ROSTER)
	if roster.is_empty():
		return _fail("roster %s missing" % ROSTER)
	var cus_data: Dictionary = alm._process_army_data(roster, cus_player)
	cus_data.faction["team_name"] = "WP-C7 datasheet abilities"
	alm.apply_army_to_game_state(cus_data, cus_player)
	alm.scan_available_armies()
	var orks = alm.load_army_list(ORK_ARMY, ork_player)
	if orks.is_empty() or not orks.has("units"):
		return _fail("army list %s did not load" % ORK_ARMY)
	alm.apply_army_to_game_state(orks, ork_player)

	var laid := {}
	for side in [["cus", cus_player, 1], ["orks", ork_player, -1]]:
		for row in spec.get(side[0], []):
			var uid := str(row[0])
			if not GS.state.units.has(uid):
				return _fail("%s: row names %s but no such unit was loaded" % [name, uid])
			if int(GS.state.units[uid].get("owner", 0)) != int(side[1]):
				return _fail("%s: %s is not P%d's" % [name, uid, side[1]])
			_place_unit(uid, float(row[1]), float(row[2]), int(row[3]), int(side[2]))
			laid[uid] = true
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
		u.meta["is_warlord"] = false
	# One WARLORD per side (Trajann's SUPREME COMMANDER when he is there).
	for p in [cus_player, ork_player]:
		var pick := ""
		for uid in GS.state.units:
			var u = GS.state.units[uid]
			if int(u.owner) != p or not "CHARACTER" in u.meta.get("keywords", []):
				continue
			if pick == "" or CA.is_supreme_commander(u):
				pick = str(uid)
		if pick != "":
			GS.state.units[pick].meta["is_warlord"] = true

	var st = GS.state
	for p in ["1", "2"]:
		if st.players.has(p):
			st.players[p]["cp"] = 6
			st.players[p]["bonus_cp_gained_this_round"] = 0
			st.players[p].erase(CA.ARMY_USES)
	var active := int(spec.get("active", 1))
	var rnd := int(spec.get("round", 2))
	st.meta["battle_round"] = rnd
	st.meta["turn"] = (rnd - 1) * 2 + (1 if active == 1 else 2)
	st.meta["phase"] = 6  # COMMAND
	st.meta["active_player"] = active
	st.meta["first_turn_player"] = 1
	st["history"] = []
	st["phase_log"] = []
	st["unit_visuals"] = {}

	for pair in spec.get("attach", []):
		cam.attach_character(str(pair[0]), str(pair[1]))
		if str(GS.state.units[str(pair[0])].get("attached_to", "")) != str(pair[1]):
			return _fail("%s: could not attach %s to %s" % [name, pair[0], pair[1]])
	var fl: Dictionary = spec.get("flags", {})
	for uid in fl:
		for k in fl[uid]:
			GS.state.units[uid].flags[k] = fl[uid][k]

	if not _gates(name, spec):
		return false
	var re = root.get_node("RulesEngine")
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var p = u.models[0].position
		print("[cus11e-c7-fixture]   P%d %-28s %2d models  first at (%.2f, %.2f)in  engaged=%s" % [
			int(u.owner), uid, u.models.size(), p.x / PX_PER_INCH, p.y / PX_PER_INCH, str(re.is_unit_engaged(uid, GS.state))])
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
		DirAccess.remove_absolute(ProjectSettings.globalize_path(src))
	print("[cus11e-c7-fixture] %s written (res://tests/saves/%s.w40ksave)" % [out_name, out_name])
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


func _gates(name: String, spec: Dictionary) -> bool:
	var re = root.get_node_or_null("RulesEngine")
	var ok := true
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var coh = AttackSequence.check_unit_coherency(u)
		if not bool(coh.get("coherent", false)):
			ok = _fail("%s: %s out of coherency (%s)" % [name, uid, str(coh.get("offenders", []))]) and ok
		for m in u.get("models", []):
			var p = m.position
			var rr := _radius_in(m) * PX_PER_INCH
			if p.x - rr < 0 or p.y - rr < 0 or p.x + rr > BOARD_W_IN * PX_PER_INCH or p.y + rr > BOARD_H_IN * PX_PER_INCH:
				ok = _fail("%s: %s model %s off the board at %s" % [name, uid, m.get("id", "?"), str(p)]) and ok
	var paired := {}
	for pair in spec.get("engaged", []):
		paired[str(pair[0])] = true
		paired[str(pair[1])] = true
		if not re.check_units_in_engagement_range(GS.state.units[str(pair[0])], GS.state.units[str(pair[1])], GS.state):
			ok = _fail("%s: %s should be engaged with %s" % [name, pair[0], pair[1]]) and ok
	for uid in GS.state.units:
		var engaged: bool = re.is_unit_engaged(uid, GS.state)
		if engaged and not paired.has(uid):
			ok = _fail("%s: %s should NOT be engaged" % [name, uid]) and ok
	var meas = root.get_node_or_null("Measurement")
	var ids: Array = GS.state.units.keys()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			for ma in GS.state.units[ids[i]].models:
				for mb in GS.state.units[ids[j]].models:
					if meas and float(meas.model_to_model_distance_inches(ma, mb)) < -0.01:
						ok = _fail("%s: %s and %s overlap" % [name, ids[i], ids[j]]) and ok
	# Ability-offer gates: [player, window_id, phase, active_player, [slugs]].
	for g in spec.get("offers", []):
		var meta: Dictionary = GS.state.meta
		var keep := [meta.get("phase"), meta.get("active_player")]
		meta["phase"] = int(g[2])
		meta["active_player"] = int(g[3])
		var got: Array = CA.window_offers(int(g[0]), str(g[1]), {"window_id": str(g[1])}).map(func(o): return CA.slug_of(str(o.get("stratagem_id", ""))))
		meta["phase"] = keep[0]
		meta["active_player"] = keep[1]
		for slug in g[4]:
			if not slug in got:
				ok = _fail("%s: %s not offered in %s (got %s)" % [name, slug, g[1], str(got)]) and ok
	return ok

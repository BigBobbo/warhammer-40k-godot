extends SceneTree

## gen_sm11e_m4c_fixtures.gd — builds the WP-M4c (Codex: Space Marines 11e,
## generic DATASHEET abilities of the M4c datasheets,
## scripts/codex/space_marines/SMAbilitiesC.gd) windowed scenario fixtures:
##
##   tests/saves/sm11e_m4c_<name>.w40ksave — Space Marines =
##       armies/sm11e_codex_test.json, Orks = armies/ork11e_codex_test.json,
##       both through ArmyListManager.load_army_list. The Space Marines are P1
##       (spec "sm"); the active player is "active"; battle round "round"
##       (default 2); the Command phase of the active player (scenarios
##       transition to their phase), or "phase" when given (Formations = 0).
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_sm11e_m4c_fixtures.gd [name ...]
##
## The gen_sw11e_s4_fixtures.gd builder (WP-S4): shell mirror_custodes_postdeploy
## (44x60" board), the EMPTY terrain layout test_open_field, every listed unit
## placed from its row (inches; Space Marines at the bottom = large y), clean
## state (DEPLOYED, no flags, full wounds, CP 6), the rest removed. Gates before
## writing: coherency, on the board, engaged pairs engaged / others unengaged,
## attachments, and the ability offers each scenario relies on.
##
## NOTE user:// is shared between worktrees: the stale user://saves copy is
## removed after writing (ScenarioRunner restages it from tests/saves).

const SHELL := "mirror_custodes_postdeploy"
const OPEN_FIELD := "test_open_field"
const SW_ARMY := "sm11e_codex_test"
const ORK_ARMY := "ork11e_codex_test"
const PX_PER_INCH := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25

# Row: [unit_id, centre_x_in, front_edge_y_in, columns]. Space Wolves rows grow
# toward LARGER y, Ork rows toward SMALLER y; front_edge_y faces the enemy.
const FIXTURES := {
	# P1 Space Marines' Command phase (round 2): Strategic Acumen (Captain on
	# Bike), Narthecium (Apothecary leading Intercessors that lost 2 models and
	# a wound), Master of Shadows (Aethon Shaan, Assault Intercessors near him).
	"command": {
		"sm": 1, "active": 1,
		"sms": [
			["U_CAPTAIN_ON_BIKE_A", 8.0, 46.0, 1],
			["U_INTERCESSOR_SQUAD_A", 20.0, 44.0, 5],
			["U_APOTHECARY_A", 20.0, 48.0, 1],
			["U_AETHON_SHAAN_A", 34.0, 50.0, 1],
			["U_ASSAULT_INTERCESSOR_SQUAD_A", 34.0, 44.0, 5],
		],
		"orks": [
			["U_BOYZ_B", 20.0, 22.0, 5],
		],
		"attach": [["U_APOTHECARY_A", "U_INTERCESSOR_SQUAD_A"]],
		"dead": {"U_INTERCESSOR_SQUAD_A": 2},
		"wounds": {"U_INTERCESSOR_SQUAD_A": 1},
		"offers": [[1, "phase_start", 6, 1, ["strategic_acumen", "narthecium", "master_of_shadows"]]],
	},
	# P1 Space Marines' Movement phase: Master Tactician (Marneus Calgar, an
	# Intercessor Squad 3" away), Seeker of the Unfound (Vulkan next to the
	# right no-man's-land objective), Raise the Banner (Ancient on the home
	# objective, secured at the end of the Movement phase).
	"move": {
		"sm": 1, "active": 1,
		"sms": [
			["U_MARNEUS_CALGAR_A", 12.0, 50.0, 1],
			["U_INTERCESSOR_SQUAD_A", 12.0, 44.0, 5],
			["U_VULKAN_HE_STAN_A", "obj_nml_2", 1.5, 1],
			["U_ANCIENT_A", "obj_home_2", 0.0, 1],
		],
		"orks": [
			["U_BOYZ_B", 20.0, 14.0, 5],
		],
		"offers": [[1, "phase_start", 7, 1, ["master_tactician", "seeker_of_the_unfound"]]],
	},
	# P1 Space Marines' Shooting phase: Forgefather (Vulkan; Eradicators with
	# Melta Rifles), Overlapping Destruction (Eradicators with Heavy Bolters vs
	# 10 Boyz). Vulkan's Seeker objective is already chosen.
	"shoot": {
		"sm": 1, "active": 1,
		"sms": [
			["U_VULKAN_HE_STAN_A", 10.0, 46.0, 1],
			["U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", 14.0, 42.0, 3],
			["U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", 30.0, 42.0, 3],
		],
		"orks": [
			["U_DEFF_DREAD_A", 10.0, 28.0, 1],
			["U_BOYZ_B", 30.0, 26.0, 5],
		],
		"flags": {"U_VULKAN_HE_STAN_A": {"sm11e_abc_seeker_objective": "obj_center"}},
		"offers": [[1, "phase_start", 8, 1, ["forgefather", "overlapping_destruction"]]],
	},
	# P1 Space Marines' Fight phase: Righteous Fury (Captain Titus leading
	# Intercessors, engaged with the Warboss), Fearsome Assault (Reivers engaged
	# with the Boyz — the Boyz test at the start of the phase).
	"fight": {
		"sm": 1, "active": 1,
		"sms": [
			["U_INTERCESSOR_SQUAD_A", 12.0, 30.5, 5],
			["U_CAPTAIN_TITUS_A", 12.0, 34.0, 1],
			["U_REIVER_SQUAD_A", 32.0, 30.5, 5],
		],
		"orks": [
			["U_WARBOSS_A", 12.0, 29.5, 1],
			["U_BOYZ_B", 32.0, 29.5, 5],
		],
		"attach": [["U_CAPTAIN_TITUS_A", "U_INTERCESSOR_SQUAD_A"]],
		"engaged": [["U_INTERCESSOR_SQUAD_A", "U_WARBOSS_A"], ["U_REIVER_SQUAD_A", "U_BOYZ_B"]],
		"wounds": {"U_CAPTAIN_TITUS_A": 3},
	},
	# P2 Orks' Charge phase vs P1 Space Marines: Combat Embarkation (an
	# Intercessor Squad wholly within 3" of a Repulsor; the Boyz 7" away).
	"enemy_charge": {
		"sm": 1, "active": 2,
		"sms": [
			["U_REPULSOR_A", 12.0, 40.0, 1],
			["U_INTERCESSOR_SQUAD_A", 12.0, 37.5, 5],
		],
		"orks": [
			["U_BOYZ_B", 12.0, 30.0, 5],
		],
	},
	# P1 Space Marines' Fight phase: Cold and Calculating (Caanok Var engaged
	# with a Deff Dread), Banner of Macragge (Victrix engaged with the Boyz).
	"fight_cards": {
		"sm": 1, "active": 1,
		"sms": [
			["U_CAANOK_VAR_A", 10.0, 30.5, 1],
			["U_VICTRIX_HONOUR_GUARD_A", 30.0, 30.5, 3],
		],
		"orks": [
			["U_DEFF_DREAD_A", 10.0, 29.5, 1],
			["U_BOYZ_B", 30.0, 29.5, 5],
		],
		"engaged": [["U_CAANOK_VAR_A", "U_DEFF_DREAD_A"], ["U_VICTRIX_HONOUR_GUARD_A", "U_BOYZ_B"]],
	},
	# Declare Battle Formations, the Space Marines (P1) declare: Thunderhawk
	# Insertion (Marneus Calgar) and Cerebrex Logic Engine (Caanok Var).
	"formations": {
		"sm": 1, "active": 1, "round": 1, "phase": 0, "undeployed": true,
		"sms": [
			["U_MARNEUS_CALGAR_A", 6.0, 56.0, 1],
			["U_CAANOK_VAR_A", 12.0, 56.0, 1],
			["U_INTERCESSOR_SQUAD_A", 20.0, 50.0, 5],
			["U_HELLBLASTER_SQUAD_A", 32.0, 50.0, 5],
		],
		"orks": [
			["U_BOYZ_B", 20.0, 10.0, 5],
			["U_WARBOSS_A", 30.0, 10.0, 1],
		],
	},
}

var GS = null
var SW = null


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
			printerr("[sm11e-m4c-fixture] unknown fixture %s" % n)
			ok = false
			continue
		ok = _build(str(n), FIXTURES[n]) and ok
	quit(0 if ok else 1)


func _fail(msg: String) -> bool:
	printerr("[sm11e-m4c-fixture] FAIL: %s" % msg)
	return false


func _build(name: String, spec: Dictionary) -> bool:
	var out_name := "sm11e_m4c_" + name
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	var tm = root.get_node_or_null("TerrainManager")
	GS = root.get_node_or_null("GameState")
	SW = load("res://scripts/codex/space_marines/SMAbilitiesC.gd")
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
	var sw_player := int(spec.get("sm", 1))
	var ork_player := 2 if sw_player == 1 else 1
	alm.scan_available_armies()
	var sw = alm.load_army_list(SW_ARMY, sw_player)
	if sw.is_empty() or not sw.has("units"):
		return _fail("army list %s did not load" % SW_ARMY)
	alm.apply_army_to_game_state(sw, sw_player)
	var orks = alm.load_army_list(ORK_ARMY, ork_player)
	if orks.is_empty() or not orks.has("units"):
		return _fail("army list %s did not load" % ORK_ARMY)
	alm.apply_army_to_game_state(orks, ork_player)

	var laid := {}
	for side in [["sms", sw_player, 1], ["orks", ork_player, -1]]:
		for row in spec.get(side[0], []):
			var uid := str(row[0])
			if not GS.state.units.has(uid):
				return _fail("%s: row names %s but no such unit was loaded" % [name, uid])
			if int(GS.state.units[uid].get("owner", 0)) != int(side[1]):
				return _fail("%s: %s is not P%d's" % [name, uid, side[1]])
			if typeof(row[1]) == TYPE_STRING:
				# [uid, objective id, dy, columns]: centred on that objective marker.
				var op := _objective_pos_in(str(row[1]))
				if op.x < 0:
					return _fail("%s: no objective %s (have %s)" % [name, row[1], str(GS.state.board.get("objectives", []).map(func(o): return o.get("id", "")))])
				_place_unit(uid, op.x, op.y + float(row[2]), int(row[3]), int(side[2]))
			else:
				_place_unit(uid, float(row[1]), float(row[2]), int(row[3]), int(side[2]))
			laid[uid] = true
	for uid in spec.get("reserves", []):
		laid[str(uid)] = true
	for uid in GS.state.units.keys():
		if not laid.has(uid):
			GS.state.units.erase(uid)

	var undeployed := bool(spec.get("undeployed", false))
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		u["status"] = 0 if undeployed else 2  # UNDEPLOYED / DEPLOYED
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
			if undeployed:
				m["position"] = null
		u.meta["is_warlord"] = false
	for uid in spec.get("reserves", []):
		var ru = GS.state.units[str(uid)]
		ru["status"] = 7  # IN_RESERVES
		ru["reserve_type"] = "strategic_reserves"
		for m in ru.get("models", []):
			m["position"] = null
	var fl: Dictionary = spec.get("flags", {})
	for uid in fl:
		for k in fl[uid]:
			GS.state.units[uid].flags[k] = fl[uid][k]
	var dd: Dictionary = spec.get("dead", {})
	for uid in dd:
		var ms: Array = GS.state.units[uid].models
		for i in range(int(dd[uid])):
			ms[ms.size() - 1 - i]["alive"] = false
			ms[ms.size() - 1 - i]["current_wounds"] = 0
	var wd: Dictionary = spec.get("wounds", {})
	for uid in wd:
		GS.state.units[uid].models[0]["current_wounds"] = int(wd[uid])
	# One WARLORD per side (never Murderfang — Force of Untamed Destruction).
	if not undeployed:
		for p in [sw_player, ork_player]:
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
			st.players[p].erase(SW.ARMY_USES)
	var active := int(spec.get("active", 1))
	var rnd := int(spec.get("round", 2))
	st.meta["battle_round"] = rnd
	st.meta["turn"] = (rnd - 1) * 2 + (1 if active == 1 else 2)
	st.meta["phase"] = int(spec.get("phase", 6))
	st.meta["active_player"] = active
	st.meta["first_turn_player"] = 1
	if undeployed:
		st.meta["formations_p1_confirmed"] = false
		st.meta["formations_p2_confirmed"] = false
		st.meta["formations_declared"] = false
		st.meta.erase("formations")
	st["history"] = []
	st["phase_log"] = []
	st["unit_visuals"] = {}

	for pair in spec.get("attach", []):
		cam.attach_character(str(pair[0]), str(pair[1]))
		if str(GS.state.units[str(pair[0])].get("attached_to", "")) != str(pair[1]):
			return _fail("%s: could not attach %s to %s" % [name, pair[0], pair[1]])

	if not _gates(name, spec):
		return false
	var re = root.get_node("RulesEngine")
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var p = u.models[0].position
		if p == null:
			print("[sm11e-m4c-fixture]   P%d %-30s %2d models  (off the table, status %d)" % [int(u.owner), uid, u.models.size(), int(u.status)])
			continue
		print("[sm11e-m4c-fixture]   P%d %-30s %2d models  first at (%.2f, %.2f)in  engaged=%s" % [
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
	print("[sm11e-m4c-fixture] %s written (res://tests/saves/%s.w40ksave)" % [out_name, out_name])
	return true


func _objective_pos_in(obj_id: String) -> Vector2:
	for o in GS.state.board.get("objectives", []):
		if str(o.get("id", "")) == obj_id:
			var p = o.get("position", {})
			if p is Vector2:
				return p / PX_PER_INCH
			return Vector2(float(p.get("x", 0)), float(p.get("y", 0))) / PX_PER_INCH
	return Vector2(-1, -1)


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
		if u.models[0].position == null:
			continue
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
		if GS.state.units[uid].models[0].position == null:
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
	for g in spec.get("offers", []):
		var meta: Dictionary = GS.state.meta
		var keep := [meta.get("phase"), meta.get("active_player")]
		meta["phase"] = int(g[2])
		meta["active_player"] = int(g[3])
		var got: Array = SW.window_offers(int(g[0]), str(g[1]), {"window_id": str(g[1])}).map(func(o): return SW.slug_of(str(o.get("stratagem_id", ""))))
		meta["phase"] = keep[0]
		meta["active_player"] = keep[1]
		for slug in g[4]:
			if not slug in got:
				ok = _fail("%s: %s not offered in %s (got %s)" % [name, slug, g[1], str(got)]) and ok
	return ok

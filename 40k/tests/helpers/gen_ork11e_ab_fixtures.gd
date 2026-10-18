extends SceneTree

## gen_ork11e_ab_fixtures.gd — builds the WP-O6 (Codex: Orks 11e DATASHEET
## abilities, scripts/codex/orks/OrkAbilities11e.gd) windowed-scenario
## fixtures:
##
##   tests/saves/ork11e_ab_<name>.w40ksave — P1 = Orks: units of the three
##       codex rosters tests/fixtures/ork11e_ab_roster_{a,b,c}.json (generated
##       from the codex data, so every ability carries its codex name), P2 =
##       Adeptus Custodes (armies/adeptus_custodes.json). Battle round 2, the
##       active player's Command phase (scenarios transition to their phase).
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_ork11e_ab_fixtures.gd [name ...]
##
## Built like gen_cus11e_c3_fixtures.gd: shell mirror_custodes_postdeploy, the
## test-only EMPTY terrain layout test_open_field (fight_end uses the default
## official layout: Kunnin' Infiltrator needs a dense terrain area), every unit
## placed from its LAYOUT row (inches; Orks at the top = small y, rows growing
## away from the enemy), clean state (DEPLOYED, no flags, full wounds, CP 6).
## Gates before writing: coherency, on the board, the engaged pairs engaged and
## every other unit unengaged, attachments / embarks in place, and the hidden
## units hidden.
##
## NOTE user:// is shared between worktrees: ScenarioRunner stages a fixture
## only when user://saves has no file of that name, so after regenerating,
## delete the stale user://saves/ork11e_ab_* copies (this script does).

const SHELL := "mirror_custodes_postdeploy"
const OPEN_FIELD := "test_open_field"
const DENSE_LAYOUT := "take_and_hold_mirror_1"
const ROSTERS := ["ork11e_ab_roster_a", "ork11e_ab_roster_b", "ork11e_ab_roster_c"]
const CUSTODES_ARMY := "adeptus_custodes"
const PX_PER_INCH := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25

const PULSA := {"name": "Pulsa Rokkit (Once per battle, per unit)", "type": "Wargear",
	"description": "Once per battle, in your Shooting phase, when this unit is selected to shoot, select one enemy MONSTER or VEHICLE unit within 24\" of it: until the end of the phase, this unit's attacks that target that unit have +1 AP and [LETHAL HITS]."}

# Row: [unit_id, centre_x_in, front_edge_y_in, columns]. P1 (Orks) rows grow
# toward SMALLER y, P2 (Custodes) toward LARGER y; front_edge_y is the edge
# facing the other side.
const FIXTURES := {
	# Shooting phase: Boss' Ammo Runt / Ammo Runts / Pulsa Rokkit (selected to
	# shoot), Rokkit Barrage / Squig Barrage / Bust 'Em / Madcap Artillery
	# (has shot, two units in range of split fire), Strafing Run (passive).
	"shoot": {
		"active": 1,
		"p1": [
			["U_BOYZ_C", 6.0, 20.0, 5],
			["U_WARBOSS_A", 6.0, 16.6, 1],
			["U_TANKBUSTAS_A", 15.0, 20.0, 3],
			["U_RUKKATRUKK_SQUIGBUGGIES_A", 23.0, 20.0, 1],
			["U_WARTRAKKS_A", 29.0, 20.0, 1],
			["U_WARBIKERS_A", 35.0, 20.0, 3],
			["U_MEK_GUNZ_A", 41.5, 20.0, 2],
			["U_DAKKAJET_A", 10.0, 11.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 4.0, 30.0, 3],
			["U_WITCHSEEKERS_C", 12.0, 29.0, 4],
			["U_WITCHSEEKERS_D", 20.0, 29.0, 4],
			["U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H", 30.0, 30.0, 1],
			["U_TELEMON_HEAVY_DREADNOUGHT_I", 39.0, 31.0, 1],
		],
		"attach": [["U_WARBOSS_A", "U_BOYZ_C"]],
		"add_abilities": {"U_TANKBUSTAS_A": [PULSA]},
		# Madcap Artillery needs every Mek Gun on the same gun; two models so
		# the battery can split fire at two units.
		"models": {"U_MEK_GUNZ_A": 2},
		"wargear": {"U_MEK_GUNZ_A": ["2x Traktor Kannon"]},
	},
	# Movement phase (no movement_phase_start abilities on the board).
	"move": {
		"active": 1,
		"p1": [
			["U_WARBOSS_A", 4.5, 8.0, 1],
			["U_BOYZ_C", 4.5, 14.0, 5],
			["U_DEFFKILLA_WARTRIKE_A", 14.0, 8.0, 1],
			["U_WARBIKERS_A", 14.0, 14.0, 3],
			["U_BEASTBOSS_A", 24.0, 8.0, 1],
			["U_BEAST_SNAGGA_BOYZ_B", 24.0, 14.0, 5],
			["U_MEK_A", 33.0, 8.0, 1],
			["U_GUNWAGON_A", 33.0, 10.5, 1],
			["U_BIG_MEK_A", 41.0, 8.0, 1],
			["U_KOMMANDOS_A", 6.0, 24.0, 5],
			["U_TANKBUSTAS_A", 16.0, 24.0, 3],
			["U_SQUIGHOG_BOYZ_A", 26.0, 24.0, 2],
			["U_WARBUGGIES_A", 36.0, 24.0, 1],
			["U_MORKANAUT_A", 40.0, 18.0, 1],
			["U_NOBZ_A", 34.0, 17.0, 5],
		],
		"p2": [
			["U_WITCHSEEKERS_C", 6.0, 33.0, 4],
			["U_WITCHSEEKERS_D", 16.0, 33.0, 4],
			["U_CUSTODIAN_GUARD_B", 26.0, 33.0, 3],
			["U_SHIELD_CAPTAIN_A", 37.0, 29.5, 1],
		],
		"embark": [["U_NOBZ_A", "U_MORKANAUT_A"]],
		"wounds_lost": {"U_GUNWAGON_A": 4},
		"flags": {"U_BOYZ_C": {"battle_shocked": true}},
	},
	# Movement phase start: Makari, Hoist Dat Banner! / Da Jump.
	"move_start": {
		"active": 1,
		"p1": [
			["U_GHAZGHKULL_THRAKA_A", 12.0, 10.0, 1],
			["U_BOYZ_C", 6.0, 20.0, 5],
			["U_BOYZ_D", 18.0, 20.0, 5],
			["U_MEGANOBZ_B", 30.0, 20.0, 3],
			["U_WEIRDBOY_A", 38.0, 10.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 22.0, 40.0, 3],
		],
	},
	# The opponent's Movement phase: Supreme Kunnin' (an enemy ends a move
	# within 8" of Nazdreg).
	"enemy_move": {
		"active": 2,
		"p1": [
			["U_NAZDREG_A", 20.0, 20.0, 1],
			["U_BOYZ_C", 6.0, 20.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 20.0, 32.0, 3],
		],
	},
	# Fight phase: Rokkit Charge (charged Stormboyz), Warpath (Weirdboy, Kill
	# Rig), Might Is Right (passive, charged Warboss).
	"fight": {
		"active": 1,
		"p1": [
			["U_STORMBOYZ_A", 8.0, 30.0, 5],
			["U_WEIRDBOY_A", 20.0, 30.0, 1],
			["U_KILL_RIG_A", 31.0, 30.0, 1],
			["U_WARBOSS_A", 40.5, 30.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 8.0, 30.5, 3],
			["U_WITCHSEEKERS_C", 20.0, 30.5, 4],
			["U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H", 31.0, 30.5, 1],
			["U_SHIELD_CAPTAIN_A", 40.5, 30.5, 1],
		],
		"engaged": [["U_STORMBOYZ_A", "U_CUSTODIAN_GUARD_B"], ["U_WEIRDBOY_A", "U_WITCHSEEKERS_C"],
			["U_KILL_RIG_A", "U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H"], ["U_WARBOSS_A", "U_SHIELD_CAPTAIN_A"]],
		"flags": {"U_STORMBOYZ_A": {"charged_this_turn": true}, "U_WARBOSS_A": {"charged_this_turn": true}},
	},
	# Charge phase: Krushin' Impetus (unit ended a charge move), Mobbed
	# (passive, Beast Snagga Boyz charge a VEHICLE).
	"charge": {
		"active": 1,
		"p1": [
			["U_WARBOSS_IN_MEGA_ARMOUR_A", 8.0, 20.0, 1],
			["U_BEAST_SNAGGA_BOYZ_B", 30.0, 20.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 8.0, 23.5, 3],
			["U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H", 30.0, 23.5, 1],
		],
	},
	# The opponent's Fight phase ends: Kunnin' Infiltrator (hidden Snikrot),
	# Aerial Manoover, Burna Bomb, Boom Bomb.
	"fight_end": {
		"active": 2,
		"terrain": DENSE_LAYOUT,
		"p1": [
			["U_DEFFKOPTAS_A", 6.0, 8.0, 3],
			["U_BURNA_BOMMER_A", 34.5, 8.0, 1],  # (at x 18 a ruin blocked its view of Custodian Guard B)
			["U_BLITZA_BOMMER_A", 28.0, 8.0, 1],
		],
		"p2": [
			["U_WITCHSEEKERS_C", 18.0, 26.0, 4],
			["U_CUSTODIAN_GUARD_B", 30.0, 28.0, 3],
		],
		"hidden": ["U_BOSS_SNIKROT_A"],
		# Gate: every ability the scenarios use is on offer at the end of P2's Fight phase.
		"offers": [[1, "fight_phase_end", 10, 2, ["kunnin_infiltrator", "aerial_manoover", "burna_bomb", "boom_bomb"]]],
	},
	# Command phase, Battle-shock step: Crude Surgery (+ Catch Dat Red Bit), Fix
	# Dat Armour Up, Push Dat Bit Back In, Full Throttle + Shokk Attack Engine
	# (battle_shock_step_start), That'll Learn Ya (unit_battle_shocked).
	"command": {
		"active": 1,
		"p1": [
			["U_BOYZ_C", 6.0, 20.0, 5],
			["U_PAINBOY_A", 6.0, 16.6, 1],
			["U_BIG_MEK_IN_MEGA_ARMOUR_A", 15.0, 20.0, 1],
			["U_PAINBOSS_A", 24.0, 13.0, 1],
			["U_BEAST_SNAGGA_BOYZ_B", 24.0, 20.0, 5],
			["U_WAZDAKKA_GUTSMEK_A", 33.0, 20.0, 1],
			["U_GRETCHIN_A", 40.5, 20.0, 3],
			["U_RUNTHERD_A", 37.6, 20.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 22.0, 40.0, 3],
		],
		"attach": [["U_PAINBOY_A", "U_BOYZ_C"], ["U_RUNTHERD_A", "U_GRETCHIN_A"]],
		"dead": {"U_BOYZ_C": 2, "U_BEAST_SNAGGA_BOYZ_B": 1, "U_GRETCHIN_A": 6},
		"wounds_lost": {"U_BIG_MEK_IN_MEGA_ARMOUR_A": 3},
	},
}

var GS = null
var OA = null


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
			printerr("[ork11e-ab-fixture] unknown fixture %s" % n)
			ok = false
			continue
		ok = _build(str(n), FIXTURES[n]) and ok
	quit(0 if ok else 1)


func _fail(msg: String) -> bool:
	printerr("[ork11e-ab-fixture] FAIL: %s" % msg)
	return false


func _json(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/%s.json" % name, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _build(name: String, spec: Dictionary) -> bool:
	# Optional spec keys (WP-O5 gen_ork11e_enh_fixtures.gd reuses this builder):
	# prefix, detachment, enhancements {uid: [names]}, reserves {uid: reserve_type},
	# battle_round. Absent = the WP-O6 behaviour.
	var out_name := str(spec.get("prefix", "ork11e_ab_")) + name
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	var tm = root.get_node_or_null("TerrainManager")
	var trm = root.get_node_or_null("TransportManager")
	GS = root.get_node_or_null("GameState")
	OA = load("res://scripts/codex/orks/OrkAbilities11e.gd")
	if slm == null or alm == null or GS == null or cam == null or tm == null or trm == null:
		return _fail("autoloads missing")
	GameConstants.edition = 11
	if not slm.load_game(SHELL):
		return _fail("could not load shell %s" % SHELL)
	GS.state["units"] = {}
	var layout := str(spec.get("terrain", OPEN_FIELD))
	tm.load_terrain_layout(layout)
	if tm.current_layout != layout:
		return _fail("could not switch to the %s terrain layout" % layout)
	GS.state.board["terrain_layout"] = layout
	if layout == OPEN_FIELD:
		GS.state.board["terrain_features"] = []
		GS.state.board["terrain"] = []

	# P1: the three codex rosters (one army: the union of their units).
	var orks := {}
	var faction := {}
	for r in ROSTERS:
		var d := _json(r)
		if d.is_empty():
			return _fail("roster %s missing" % r)
		faction = d.get("faction", {})
		for k in d.units:
			orks[k] = d.units[k]
	if spec.has("detachment"):
		faction = faction.duplicate(true)
		faction["detachment"] = str(spec.detachment)
	var enh_spec: Dictionary = spec.get("enhancements", {})
	for uid in enh_spec:
		if not orks.has(uid):
			return _fail("%s: enhancement bearer %s is not in the rosters" % [name, uid])
		orks[uid] = orks[uid].duplicate(true)
		orks[uid].meta["enhancements"] = (enh_spec[uid] as Array).duplicate()
	var p1_data: Dictionary = alm._process_army_data({"faction": faction.duplicate(true), "units": orks}, 1)
	p1_data.faction["team_name"] = "WP-O6 datasheet abilities"
	alm.apply_army_to_game_state(p1_data, 1)
	alm.scan_available_armies()
	var cus = alm.load_army_list(CUSTODES_ARMY, 2)
	if cus.is_empty() or not cus.has("units"):
		return _fail("army list %s did not load" % CUSTODES_ARMY)
	alm.apply_army_to_game_state(cus, 2)

	# Extra models / wargear / abilities BEFORE placement.
	var models_spec: Dictionary = spec.get("models", {})
	for uid in models_spec:
		var u: Dictionary = GS.state.units[uid]
		while u.models.size() < int(models_spec[uid]):
			var m: Dictionary = u.models[0].duplicate(true)
			m["id"] = "m%d" % (u.models.size() + 1)
			u.models.append(m)
	var wg: Dictionary = spec.get("wargear", {})
	for uid in wg:
		GS.state.units[uid].meta["wargear"] = wg[uid]
		GS.state.units[uid].erase("_loadout_version")
		for m in GS.state.units[uid].models:
			m.erase("ranged_loadout")
			m.erase("melee_loadout")
	var ab: Dictionary = spec.get("add_abilities", {})
	for uid in ab:
		for a in ab[uid]:
			GS.state.units[uid].meta.abilities.append(a.duplicate(true))

	var laid := {}
	for side in [["p1", 1, -1], ["p2", 2, 1]]:
		for row in spec.get(side[0], []):
			var uid := str(row[0])
			if not GS.state.units.has(uid):
				return _fail("%s: LAYOUT names %s but no such unit was loaded" % [name, uid])
			if int(GS.state.units[uid].get("owner", 0)) != int(side[1]):
				return _fail("%s: %s is not P%d's" % [name, uid, side[1]])
			_place_unit(uid, float(row[1]), float(row[2]), int(row[3]), int(side[2]))
			laid[uid] = true
	for uid in spec.get("hidden", []):
		laid[uid] = true
	for uid in spec.get("reserves", {}):
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

	var st = GS.state
	for p in ["1", "2"]:
		if st.players.has(p):
			st.players[p]["cp"] = 6
			st.players[p]["bonus_cp_gained_this_round"] = 0
			st.players[p].erase("ork11e_ab_uses")
	var active := int(spec.get("active", 1))
	st.meta["battle_round"] = int(spec.get("battle_round", 2))
	st.meta["turn"] = 2 if active == 1 else 3
	if int(spec.get("battle_round", 2)) == 1:
		st.meta["turn"] = 1 if active == 1 else 2
	st.meta["phase"] = 6  # COMMAND
	st.meta["active_player"] = active
	st.meta["first_turn_player"] = 1
	st["history"] = []
	st["phase_log"] = []
	st["unit_visuals"] = {}

	var rsv: Dictionary = spec.get("reserves", {})
	for uid in rsv:
		var ru: Dictionary = GS.state.units[uid]
		ru["status"] = 7  # IN_RESERVES
		ru["reserve_type"] = str(rsv[uid])
		for m in ru.get("models", []):
			m["position"] = null
	for uid in spec.get("hidden", []):
		if not _place_hidden(str(uid)):
			return _fail("%s: no dense-terrain spot hides %s" % [name, uid])

	for pair in spec.get("attach", []):
		cam.attach_character(str(pair[0]), str(pair[1]))
		if str(GS.state.units[str(pair[0])].get("attached_to", "")) != str(pair[1]):
			return _fail("%s: could not attach %s to %s" % [name, pair[0], pair[1]])
	for pair in spec.get("embark", []):
		trm.embark_unit(str(pair[0]), str(pair[1]))
		if str(GS.state.units[str(pair[0])].get("embarked_in", "")) != str(pair[1]):
			return _fail("%s: could not embark %s in %s" % [name, pair[0], pair[1]])
	var dead: Dictionary = spec.get("dead", {})
	for uid in dead:
		var ms: Array = GS.state.units[uid].models
		for i in range(int(dead[uid])):
			var m: Dictionary = ms[ms.size() - 1 - i]
			m["alive"] = false
			m["current_wounds"] = 0
	var wl: Dictionary = spec.get("wounds_lost", {})
	for uid in wl:
		var m0: Dictionary = GS.state.units[uid].models[0]
		m0["current_wounds"] = maxi(1, int(m0.get("wounds", 1)) - int(wl[uid]))
	var fl: Dictionary = spec.get("flags", {})
	for uid in fl:
		for k in fl[uid]:
			GS.state.units[uid].flags[k] = fl[uid][k]

	if not _gates(name, spec):
		return false
	var re = root.get_node("RulesEngine")
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		if u.get("embarked_in", null) != null:
			print("[ork11e-ab-fixture]   P%d %-36s embarked in %s" % [int(u.owner), uid, u.embarked_in])
			continue
		if int(u.get("status", 0)) == 7:
			print("[ork11e-ab-fixture]   P%d %-36s in reserves (%s)" % [int(u.owner), uid, str(u.get("reserve_type", ""))])
			continue
		var p = u.models[0].position
		print("[ork11e-ab-fixture]   P%d %-36s %2d models  first at (%.2f, %.2f)in  engaged=%s" % [
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
		# Stale-copy guard (user:// is shared between worktrees): ScenarioRunner
		# only stages a fixture that user://saves does not already hold.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(src))
	print("[ork11e-ab-fixture] %s written (res://tests/saves/%s.w40ksave)" % [out_name, out_name])
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


## Scan the Ork half for a spot where every model of `uid` is hidden (13.09:
## within a dense terrain area) and no other unit is within 3".
func _place_hidden(uid: String) -> bool:
	var u: Dictionary = GS.state.units[uid]
	for yy in range(4, 26):
		for xx in range(2, 42):
			_place_unit(uid, float(xx), float(yy) + 0.5, 1, -1)
			var ok := true
			for m in u.models:
				if not root.get_node("TerrainManager").is_model_hidden(m, u):
					ok = false
					break
			if not ok:
				continue
			var clear := true
			for other in GS.state.units:
				if other == uid or GS.state.units[other].get("embarked_in", null) != null:
					continue
				if OA.dist_in(uid, str(other)) < 3.0:
					clear = false
					break
			if clear:
				print("[ork11e-ab-fixture]   %s hidden at (%d, %.1f)in" % [uid, xx, yy + 0.5])
				return true
	return false


func _gates(name: String, spec: Dictionary) -> bool:
	var re = root.get_node_or_null("RulesEngine")
	var ok := true
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		if u.get("embarked_in", null) != null or int(u.get("status", 0)) == 7:
			continue
		var coh = AttackSequence.check_unit_coherency(u)
		if not bool(coh.get("coherent", false)):
			ok = _fail("%s: %s out of coherency (%s)" % [name, uid, str(coh.get("offenders", []))]) and ok
		for m in u.get("models", []):
			if not m.get("alive", true):
				continue
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
		if GS.state.units[uid].get("embarked_in", null) != null or int(GS.state.units[uid].get("status", 0)) == 7:
			continue
		var engaged: bool = re.is_unit_engaged(uid, GS.state)
		if engaged and not paired.has(uid):
			ok = _fail("%s: %s should NOT be engaged" % [name, uid]) and ok
	for uid in spec.get("hidden", []):
		if not OA.unit_is_hidden(str(uid)):
			ok = _fail("%s: %s should be hidden" % [name, uid]) and ok
	# Ability-offer gates: [player, window_id, phase, active_player, [slugs]].
	for g in spec.get("offers", []):
		var meta: Dictionary = GS.state.meta
		var keep := [meta.get("phase"), meta.get("active_player")]
		meta["phase"] = int(g[2])
		meta["active_player"] = int(g[3])
		var got: Array = OA.window_offers(int(g[0]), str(g[1]), {"window_id": str(g[1])}).map(func(o): return OA.slug_of(str(o.get("stratagem_id", ""))))
		meta["phase"] = keep[0]
		meta["active_player"] = keep[1]
		for slug in g[4]:
			if not slug in got:
				ok = _fail("%s: %s not offered in %s (got %s)" % [name, slug, g[1], str(got)]) and ok
	return ok

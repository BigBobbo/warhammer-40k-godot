extends SceneTree

## gen_sm11e_m4a_fixtures.gd — builds the WP-M4a (Codex: Space Marines 11e,
## generic datasheet abilities of the M4a list, scripts/codex/space_marines/
## SMAbilitiesA.gd) windowed scenario fixtures:
##
##   tests/saves/sm11e_m4a_<name>.w40ksave — Space Marines =
##       armies/sm11e_codex_test.json, Orks = armies/ork11e_codex_test.json,
##       both through ArmyListManager.load_army_list (so the M4a list build —
##       default kits, Relic / Storm / Combat Shields, transport keywords —
##       runs). The Space Marines are P1 or P2 per fixture ("sm"); the active
##       player is "active"; battle round "round" (default 2); the Command
##       phase of the active player (scenarios transition to their phase), or
##       "phase" when given.
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_sm11e_m4a_fixtures.gd [name ...]
##
## Built like gen_sw11e_s4_fixtures.gd: shell mirror_custodes_postdeploy (44x60"
## board), the EMPTY terrain layout test_open_field unless "terrain" names a
## layout (Priority Target Identified needs terrain features), every listed
## unit placed from its row (inches; Space Marines at the bottom = large y),
## clean state (DEPLOYED, no flags, full wounds, CP 6), the rest removed.
## "wargear" stamps roster wargear (+ the wargear ability rows the roster
## would carry) and re-runs the list build; "embark" puts units inside a
## transport; "reserves" puts units in strategic reserves. Gates before
## writing: coherency, on the board, engaged pairs engaged / others unengaged,
## attachments, and the ability offers each scenario relies on.
##
## NOTE user:// is shared between worktrees: the stale user://saves copy is
## removed after writing (ScenarioRunner restages it from tests/saves).

const SHELL := "mirror_custodes_postdeploy"
const OPEN_FIELD := "test_open_field"
const SM_ARMY := "sm11e_codex_test"
const ORK_ARMY := "ork11e_codex_test"
const PX_PER_INCH := 40.0
const BOARD_W_IN := 44.0
const BOARD_H_IN := 60.0
const SPACING_IN := 0.25

const RELIC_SHIELD := {"name": "Relic Shield", "type": "Wargear", "description": "This model has +1 W."}
const HELIX := {"name": "Helix Gauntlet", "type": "Wargear", "description": "In your Command phase, this unit heals D3 wounds."}
const STORM_SHIELD := {"name": "Storm Shield", "type": "Wargear", "description": "This model has +1 W."}
const COMBAT_SHIELD := {"name": "Combat Shield", "type": "Wargear", "description": "This model has 5+ InSv."}

# Row: [unit_id, centre_x_in, front_edge_y_in, columns]. Space Marine rows grow
# toward LARGER y, Ork rows toward SMALLER y; front_edge_y faces the enemy.
const FIXTURES := {
	# P1 Space Marines' Command phase (round 2, terrain layout
	# priority_assets_vs_priority_assets_1): Strategic Acumen (Captain leads
	# Intercessors), Priority Target Identified (Boyz in the area-medium-9
	# ruin), Helix Gauntlet (damaged Infiltrators that took one).
	"command": {
		"sm": 1, "active": 1, "terrain": "priority_assets_vs_priority_assets_1",
		"sms": [
			["U_INTERCESSOR_SQUAD_A", 14.0, 46.0, 5],
			["U_CAPTAIN_A", 14.0, 50.0, 1],
			["U_LIEUTENANT_WITH_COMBI_WEAPON_A", 22.0, 44.0, 1],
			["U_INFILTRATOR_SQUAD_A", 28.0, 50.0, 5],
		],
		"orks": [
			["U_BOYZ_B", 32.0, 24.0, 5],
		],
		"attach": [["U_CAPTAIN_A", "U_INTERCESSOR_SQUAD_A"]],
		"wargear": {"U_INFILTRATOR_SQUAD_A": [["1x Helix Gauntlet", "5x Marksman Bolt Carbine", "5x Bolt Pistol"], [HELIX]]},
		"dead": {"U_INFILTRATOR_SQUAD_A": 1},
		"wounds": {"U_INFILTRATOR_SQUAD_A": 1},
		"offers": [[1, "command_phase_main", 6, 1, ["strategic_acumen", "priority_target_identified", "helix_gauntlet"]]],
	},
	# P1 Space Marines' Movement phase: Author of the Codex (Guilliman,
	# Intercessors 8" away), Blessings of the Omnissiah (Techmarine next to a
	# damaged Redemptor), Assault Ramp (Land Raider with Terminators inside).
	"move": {
		"sm": 1, "active": 1,
		"sms": [
			["U_ROBOUTE_GUILLIMAN_A", 22.0, 50.0, 1],
			["U_INTERCESSOR_SQUAD_A", 22.0, 40.0, 5],
			["U_TECHMARINE_A", 36.0, 50.0, 1],
			["U_REDEMPTOR_DREADNOUGHT_A", 36.0, 44.0, 1],
			["U_LAND_RAIDER_A", 8.0, 44.0, 1],
		],
		"orks": [
			["U_BOYZ_B", 22.0, 16.0, 5],
		],
		"embark": [["U_TERMINATOR_SQUAD_A", "U_LAND_RAIDER_A"]],
		"wounds": {"U_REDEMPTOR_DREADNOUGHT_A": 6},
		"offers": [[1, "phase_start", 7, 1, ["author_of_the_codex"]]],
	},
	# P1 Space Marines' Shooting phase: Thunderous Force (Librarian in
	# Terminator Armour leads Terminators), Soul Sight + Omni-scramblers
	# (Librarian in Phobos Armour leads Infiltrators), Catechism of Fire
	# (Chaplain on Bike leads Outriders), Driven from Cover (Infernus Squad).
	"shoot": {
		"sm": 1, "active": 1,
		"sms": [
			["U_TERMINATOR_SQUAD_A", 8.0, 40.0, 5],
			["U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", 8.0, 44.0, 1],
			["U_INFILTRATOR_SQUAD_A", 20.0, 40.0, 5],
			["U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", 20.0, 43.5, 1],
			["U_OUTRIDER_SQUAD_A", 32.0, 40.0, 3],
			["U_CHAPLAIN_ON_BIKE_A", 32.0, 44.5, 1],
			["U_INFERNUS_SQUAD_A", 40.0, 36.0, 5],
		],
		"orks": [
			["U_BOYZ_B", 20.0, 28.0, 5],
			["U_GRETCHIN_C", 38.0, 30.0, 5],
		],
		"attach": [["U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", "U_TERMINATOR_SQUAD_A"], ["U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", "U_INFILTRATOR_SQUAD_A"], ["U_CHAPLAIN_ON_BIKE_A", "U_OUTRIDER_SQUAD_A"]],
		"offers": [[1, "phase_start", 8, 1, ["thunderous_force", "soul_sight", "omni_scramblers"]]],
	},
	# P1 Space Marines' Fight phase: Bladeguard (Bladeguard Veterans charged
	# the Boyz), Finest Hour (Captain leads Intercessors engaged with
	# Gretchin), Might of Heroes (Librarian in Terminator Armour + Terminators
	# engaged with Nobz).
	"fight": {
		"sm": 1, "active": 1,
		"sms": [
			["U_BLADEGUARD_VETERAN_SQUAD_A", 8.0, 30.5, 3],
			["U_INTERCESSOR_SQUAD_A", 22.0, 30.5, 5],
			["U_CAPTAIN_A", 26.7, 30.2, 1],  # beside the front rank: in Engagement Range of the Gretchin
			["U_TERMINATOR_SQUAD_A", 36.0, 30.5, 5],
			["U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", 36.0, 34.4, 1],
		],
		"orks": [
			["U_BOYZ_B", 8.0, 29.5, 5],
			["U_GRETCHIN_C", 22.0, 29.5, 5],
			["U_NOBZ_A", 36.0, 29.5, 5],
		],
		"attach": [["U_CAPTAIN_A", "U_INTERCESSOR_SQUAD_A"], ["U_LIBRARIAN_IN_TERMINATOR_ARMOUR_A", "U_TERMINATOR_SQUAD_A"]],
		"engaged": [["U_BLADEGUARD_VETERAN_SQUAD_A", "U_BOYZ_B"], ["U_INTERCESSOR_SQUAD_A", "U_GRETCHIN_C"], ["U_CAPTAIN_A", "U_GRETCHIN_C"], ["U_TERMINATOR_SQUAD_A", "U_NOBZ_A"]],
		"flags": {"U_BLADEGUARD_VETERAN_SQUAD_A": {"charged_this_turn": true}},
		"offers": [[1, "phase_start", 10, 1, ["might_of_heroes"]]],
	},
	# Battle round 1, P1 Space Marines' Command phase: Teleport Homer
	# (Terminator Assault Squad in strategic reserves) + Forward Assault Warsuit.
	"round1": {
		"sm": 1, "active": 1, "round": 1,
		"sms": [
			["U_INVICTOR_TACTICAL_WARSUIT_A", 12.0, 46.0, 1],
			["U_INTERCESSOR_SQUAD_A", 28.0, 44.0, 5],
		],
		"orks": [
			["U_BOYZ_B", 12.0, 16.0, 5],
			["U_WARBOSS_A", 28.0, 16.0, 1],
		],
		"reserves": ["U_TERMINATOR_ASSAULT_SQUAD_A"],
		"offers": [[1, "phase_start", 6, 1, ["teleport_homer", "forward_assault_warsuit"]]],
	},
	# Battle round 1, P1 Space Marines' Movement phase: Drop Pod Assault (the
	# Drop Pod in strategic reserves with Intercessors inside arrives in round 1).
	"drop_pod": {
		"sm": 1, "active": 1, "round": 1,
		"sms": [
			["U_HELLBLASTER_SQUAD_A", 30.0, 52.0, 5],
		],
		"orks": [
			["U_BOYZ_B", 30.0, 8.0, 5],
		],
		"reserves": ["U_DROP_POD_A"],
		"embark": [["U_INTERCESSOR_SQUAD_A", "U_DROP_POD_A"]],
	},
	# P2 Orks' Movement phase vs P1 Space Marines: Sentinel Protocols in the
	# movement_phase_end window (Firestrike Servo-turrets + Intercessors).
	"overwatch": {
		"sm": 1, "active": 2,
		"sms": [
			["U_FIRESTRIKE_SERVO_TURRETS_A", 14.0, 40.0, 1],
			["U_INTERCESSOR_SQUAD_A", 30.0, 40.0, 5],
		],
		"orks": [
			["U_BOYZ_B", 20.0, 26.0, 5],
		],
	},
	# P2 Orks' turn vs P1 Space Marines: Evade and Survive (Lieutenant with
	# Combi-weapon; the Boyz move to within 8"), Shrouding (Librarian in Phobos
	# Armour + Infiltrators targeted by the Flash Gitz), Parabolic Jetleap
	# (Inceptors at the end of the Orks' Fight phase).
	"enemy_turn": {
		"sm": 1, "active": 2,
		"sms": [
			["U_LIEUTENANT_WITH_COMBI_WEAPON_A", 10.0, 40.0, 1],
			["U_INFILTRATOR_SQUAD_A", 26.0, 40.0, 5],
			["U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", 26.0, 43.5, 1],
			["U_INCEPTOR_SQUAD_A", 38.0, 44.0, 3],
		],
		"orks": [
			["U_BOYZ_B", 10.0, 28.0, 5],
			["U_FLASH_GITZ_A", 26.0, 26.0, 5],
		],
		"attach": [["U_LIBRARIAN_IN_PHOBOS_ARMOUR_A", "U_INFILTRATOR_SQUAD_A"]],
	},
	# P2 Orks' Fight phase vs P1 Space Marines: Bladeguard (the Boyz charged
	# the Bladeguard Veterans and target them).
	"enemy_fight": {
		"sm": 1, "active": 2,
		"sms": [
			["U_BLADEGUARD_VETERAN_SQUAD_A", 14.0, 30.5, 3],
		],
		"orks": [
			["U_BOYZ_B", 14.0, 29.5, 5],
		],
		"engaged": [["U_BLADEGUARD_VETERAN_SQUAD_A", "U_BOYZ_B"]],
		"flags": {"U_BOYZ_B": {"charged_this_turn": true}},
	},
	# P1 Space Marines' Command phase: the M4a wargear on the table — a
	# Captain with a Relic Shield (6 W), Terminator Assault Squad with 2 Storm
	# Shields (4 W bearers), Vanguard Veterans with Combat Shields (5+ InSv),
	# a Land Raider with its default kit only.
	"wargear": {
		"sm": 1, "active": 1,
		"sms": [
			["U_CAPTAIN_A", 10.0, 46.0, 1],
			["U_TERMINATOR_ASSAULT_SQUAD_A", 22.0, 44.0, 5],
			["U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A", 34.0, 44.0, 5],
			["U_LAND_RAIDER_A", 22.0, 52.0, 1],
		],
		"orks": [
			["U_BOYZ_B", 22.0, 14.0, 5],
		],
		"wargear": {
			"U_CAPTAIN_A": [["1x Heavy Bolt Pistol", "1x Relic Shield", "1x Master-crafted Power Weapon"], [RELIC_SHIELD]],
			"U_TERMINATOR_ASSAULT_SQUAD_A": [["2x Storm Shield", "2x Thunder Hammer", "3x Twin Lightning Claws"], [STORM_SHIELD]],
			"U_VANGUARD_VETERAN_SQUAD_WITH_JUMP_PACKS_A": [["5x Combat Shield", "1x Relic Blade", "4x Master-crafted Power Weapon"], [COMBAT_SHIELD]],
		},
	},
}

var GS = null
var SMA = null


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
			printerr("[sm11e-m4a-fixture] unknown fixture %s" % n)
			ok = false
			continue
		ok = _build(str(n), FIXTURES[n]) and ok
	quit(0 if ok else 1)


func _fail(msg: String) -> bool:
	printerr("[sm11e-m4a-fixture] FAIL: %s" % msg)
	return false


func _build(name: String, spec: Dictionary) -> bool:
	var out_name := "sm11e_m4a_" + name
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	var tm = root.get_node_or_null("TerrainManager")
	GS = root.get_node_or_null("GameState")
	SMA = load("res://scripts/codex/space_marines/SMAbilitiesA.gd")
	if slm == null or alm == null or GS == null or cam == null or tm == null:
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
	else:
		GS.state.board["terrain_features"] = tm.get_terrain_for_save()
	var sm_player := int(spec.get("sm", 1))
	var ork_player := 2 if sm_player == 1 else 1
	alm.scan_available_armies()
	var sm = alm.load_army_list(SM_ARMY, sm_player)
	if sm.is_empty() or not sm.has("units"):
		return _fail("army list %s did not load" % SM_ARMY)
	alm.apply_army_to_game_state(sm, sm_player)
	var orks = alm.load_army_list(ORK_ARMY, ork_player)
	if orks.is_empty() or not orks.has("units"):
		return _fail("army list %s did not load" % ORK_ARMY)
	alm.apply_army_to_game_state(orks, ork_player)

	var laid := {}
	for side in [["sms", sm_player, 1], ["orks", ork_player, -1]]:
		for row in spec.get(side[0], []):
			var uid := str(row[0])
			if not GS.state.units.has(uid):
				return _fail("%s: row names %s but no such unit was loaded" % [name, uid])
			if int(GS.state.units[uid].get("owner", 0)) != int(side[1]):
				return _fail("%s: %s is not P%d's" % [name, uid, side[1]])
			_place_unit(uid, float(row[1]), float(row[2]), int(row[3]), int(side[2]))
			laid[uid] = true
	for uid in spec.get("reserves", []):
		laid[str(uid)] = true
	for pair in spec.get("embark", []):
		laid[str(pair[0])] = true
		laid[str(pair[1])] = true
	for uid in GS.state.units.keys():
		if not laid.has(uid):
			GS.state.units.erase(uid)

	for uid in GS.state.units:
		var u = GS.state.units[uid]
		u["status"] = 2
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
	# Roster wargear (+ the wargear abilities it brings) and the list build again.
	var wg: Dictionary = spec.get("wargear", {})
	for uid in wg:
		var u = GS.state.units[uid]
		u.meta["wargear"] = (wg[uid][0] as Array).duplicate()
		u.meta.erase("sm11e_default_kit")
		for ab in wg[uid][1]:
			u.meta.abilities.append((ab as Dictionary).duplicate())
		for m in u.models:
			for k in ["ranged_loadout", "melee_loadout"]:
				m.erase(k)
		u.erase("_loadout_version")
		u.erase("_loadout_checked")
		SMA.apply_list_build(str(uid), u)
		for m in u.models:
			m["current_wounds"] = m.get("wounds", 1)
		print("[sm11e-m4a-fixture]   %s wargear %s -> W %s invuln %s" % [uid, str(u.meta.wargear), str(u.models.map(func(mm): return mm.wounds)), str(u.models.map(func(mm): return mm.get("invuln", 0)))])
	for uid in spec.get("reserves", []):
		var ru = GS.state.units[str(uid)]
		ru["status"] = 7  # IN_RESERVES
		ru["reserve_type"] = "strategic_reserves"
		for m in ru.get("models", []):
			m["position"] = null
	for pair in spec.get("embark", []):
		var pu = GS.state.units[str(pair[0])]
		var tu = GS.state.units[str(pair[1])]
		pu["embarked_in"] = str(pair[1])
		pu["status"] = 2
		for m in pu.get("models", []):
			m["position"] = null
		if not tu.has("transport_data"):
			return _fail("%s: %s is not a transport" % [name, pair[1]])
		var emb: Array = tu.transport_data.get("embarked_units", [])
		emb.append(str(pair[0]))
		tu.transport_data["embarked_units"] = emb
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
	# One WARLORD per side (Guilliman when present: SUPREME COMMANDER).
	for p in [sm_player, ork_player]:
		var pick := ""
		for uid in GS.state.units:
			var u = GS.state.units[uid]
			if int(u.owner) != p or not "CHARACTER" in u.meta.get("keywords", []):
				continue
			if pick == "" or str(uid) == "U_ROBOUTE_GUILLIMAN_A":
				pick = str(uid)
		if pick != "":
			GS.state.units[pick].meta["is_warlord"] = true

	var st = GS.state
	for p in ["1", "2"]:
		if st.players.has(p):
			st.players[p]["cp"] = 6
			st.players[p]["bonus_cp_gained_this_round"] = 0
	var active := int(spec.get("active", 1))
	var rnd := int(spec.get("round", 2))
	st.meta["battle_round"] = rnd
	st.meta["turn"] = (rnd - 1) * 2 + (1 if active == 1 else 2)
	st.meta["phase"] = int(spec.get("phase", 6))
	st.meta["active_player"] = active
	st.meta["first_turn_player"] = 1
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
			print("[sm11e-m4a-fixture]   P%d %-44s %2d models  (off the table, status %d, embarked_in %s)" % [int(u.owner), uid, u.models.size(), int(u.status), str(u.get("embarked_in", ""))])
			continue
		print("[sm11e-m4a-fixture]   P%d %-44s %2d models  first at (%.2f, %.2f)in  engaged=%s" % [
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
	print("[sm11e-m4a-fixture] %s written (res://tests/saves/%s.w40ksave)" % [out_name, out_name])
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
		var got: Array = SMA.window_offers(int(g[0]), str(g[1]), {"window_id": str(g[1]), "phase": "x"}).map(func(o): return SMA.slug_of(str(o.get("stratagem_id", ""))))
		meta["phase"] = keep[0]
		meta["active_player"] = keep[1]
		for slug in g[4]:
			if not slug in got:
				ok = _fail("%s: %s not offered in %s (got %s)" % [name, slug, g[1], str(got)]) and ok
	return ok

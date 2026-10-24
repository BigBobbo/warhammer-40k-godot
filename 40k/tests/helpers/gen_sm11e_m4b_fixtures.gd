extends SceneTree

## gen_sm11e_m4b_fixtures.gd — builds the WP-M4b (Codex: Space Marines 11e,
## M4b datasheet abilities, scripts/codex/space_marines/SMAbilitiesB.gd)
## windowed scenario fixtures:
##
##   tests/saves/sm11e_m4b_<name>.w40ksave — Space Marines = armies/sm11e_codex_test.json
##       (P1), Orks = armies/ork11e_codex_test.json (P2), both through
##       ArmyListManager.load_army_list. The active player is "active"; battle
##       round "round" (default 2); the Command phase of the active player
##       (scenarios transition to their phase).
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_sm11e_m4b_fixtures.gd [name ...]
##
## Built like gen_sw11e_s4_fixtures.gd: shell mirror_custodes_postdeploy (44x60"
## board), the EMPTY terrain layout test_open_field, every listed unit placed
## from its row (inches; Space Marines at the bottom = large y), clean state
## (DEPLOYED, no flags, full wounds, CP 6), the rest removed. Gates before
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

# Row: [unit_id, centre_x_in, front_edge_y_in, columns]. Space Marine rows grow
# toward LARGER y, Ork rows toward SMALLER y; front_edge_y faces the enemy.
const FIXTURES := {
	# P1 Space Marines' Command phase (round 2): Strategic Acumen (Captain in
	# Gravis Armour leading Heavy Intercessors), Demi-company Commander
	# (Lieutenant), Spiritual Leader (Chaplain next to battle-shocked Intercessors).
	"command": {
		"active": 1,
		"sms": [
			["U_HEAVY_INTERCESSOR_SQUAD_A", 10.0, 44.0, 5],
			["U_CAPTAIN_IN_GRAVIS_ARMOUR_A", 10.0, 47.5, 1],
			["U_LIEUTENANT_A", 22.0, 48.0, 1],
			["U_INTERCESSOR_SQUAD_A", 33.0, 44.0, 5],
			["U_CHAPLAIN_A", 33.0, 47.5, 1],
		],
		"orks": [
			["U_BOYZ_B", 20.0, 22.0, 5],
		],
		"attach": [["U_CAPTAIN_IN_GRAVIS_ARMOUR_A", "U_HEAVY_INTERCESSOR_SQUAD_A"]],
		"flags": {"U_INTERCESSOR_SQUAD_A": {"battle_shocked": true}},
		"offers": [[1, "phase_start", 6, 1, ["strategic_acumen", "spiritual_leader"]]],
	},
	# P1 Space Marines' Movement phase: Prescience (Tigurius leading
	# Intercessors), Force Dome (Librarian), Rampart (Lysander leading
	# Terminators).
	"move": {
		"active": 1,
		"sms": [
			["U_INTERCESSOR_SQUAD_A", 9.0, 42.0, 5],
			["U_CHIEF_LIBRARIAN_TIGURIUS_A", 9.0, 45.5, 1],
			["U_LIBRARIAN_A", 22.0, 46.0, 1],
			["U_TERMINATOR_SQUAD_A", 34.0, 42.0, 5],
			["U_DARNATH_LYSANDER_A", 34.0, 46.0, 1],
		],
		"orks": [
			["U_BOYZ_B", 20.0, 26.0, 5],
		],
		"attach": [["U_CHIEF_LIBRARIAN_TIGURIUS_A", "U_INTERCESSOR_SQUAD_A"], ["U_DARNATH_LYSANDER_A", "U_TERMINATOR_SQUAD_A"]],
		"offers": [[1, "phase_start", 7, 1, ["prescience", "force_dome", "rampart"]]],
	},
	# P1 Space Marines' Shooting phase: Telepathic Assault (Tigurius, Boyz
	# ~14" away), Haywire Mine (Incursors 4" from a Deff Dread), Signum Array
	# (Tor Garadon); Eliminators (Special-issue Optics) + the Incursors'
	# Divinator-class Auspexes when a unit is selected to shoot.
	"shoot": {
		"active": 1,
		"sms": [
			["U_CHIEF_LIBRARIAN_TIGURIUS_A", 8.0, 44.0, 1],
			["U_INCURSOR_SQUAD_A", 32.0, 38.0, 5],
			["U_TOR_GARADON_A", 20.0, 46.0, 1],
			["U_ELIMINATOR_SQUAD_A", 12.0, 48.0, 3],
		],
		"orks": [
			["U_BOYZ_B", 10.0, 30.0, 5],
			["U_DEFF_DREAD_A", 32.0, 34.0, 1],
		],
		"offers": [[1, "phase_start", 8, 1, ["telepathic_assault", "haywire_mine", "signum_array"]]],
	},
	# Battle round 1, P1 Space Marines' Command phase: Teleport Homer (the
	# Terminator Squad in Deep Strike reserves).
	"round1": {
		"active": 1, "round": 1,
		"sms": [
			["U_INTERCESSOR_SQUAD_A", 20.0, 50.0, 5],
		],
		"orks": [
			["U_BOYZ_B", 20.0, 10.0, 5],
		],
		"reserves": [["U_TERMINATOR_SQUAD_A", "deep_strike"]],
		"offers": [[1, "phase_start", 6, 1, ["teleport_homer"]]],
	},
}

var GS = null
var B = null


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
			printerr("[sm11e-m4b-fixture] unknown fixture %s" % n)
			ok = false
			continue
		ok = _build(str(n), FIXTURES[n]) and ok
	quit(0 if ok else 1)


func _fail(msg: String) -> bool:
	printerr("[sm11e-m4b-fixture] FAIL: %s" % msg)
	return false


func _build(name: String, spec: Dictionary) -> bool:
	var out_name := "sm11e_m4b_" + name
	var slm = root.get_node_or_null("SaveLoadManager")
	var alm = root.get_node_or_null("ArmyListManager")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	var tm = root.get_node_or_null("TerrainManager")
	GS = root.get_node_or_null("GameState")
	B = load("res://scripts/codex/space_marines/SMAbilitiesB.gd")
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
	alm.scan_available_armies()
	var sm = alm.load_army_list(SM_ARMY, 1)
	if sm.is_empty() or not sm.has("units"):
		return _fail("army list %s did not load" % SM_ARMY)
	alm.apply_army_to_game_state(sm, 1)
	var orks = alm.load_army_list(ORK_ARMY, 2)
	if orks.is_empty() or not orks.has("units"):
		return _fail("army list %s did not load" % ORK_ARMY)
	alm.apply_army_to_game_state(orks, 2)

	var laid := {}
	for side in [["sms", 1, 1], ["orks", 2, -1]]:
		for row in spec.get(side[0], []):
			var uid := str(row[0])
			if not GS.state.units.has(uid):
				return _fail("%s: row names %s but no such unit was loaded" % [name, uid])
			if int(GS.state.units[uid].get("owner", 0)) != int(side[1]):
				return _fail("%s: %s is not P%d's" % [name, uid, side[1]])
			_place_unit(uid, float(row[1]), float(row[2]), int(row[3]), int(side[2]))
			laid[uid] = true
	for r in spec.get("reserves", []):
		laid[str(r[0])] = true
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
	for r in spec.get("reserves", []):
		var ru = GS.state.units[str(r[0])]
		ru["status"] = 7  # IN_RESERVES
		ru["reserve_type"] = str(r[1])
		for m in ru.get("models", []):
			m["position"] = null
	var fl: Dictionary = spec.get("flags", {})
	for uid in fl:
		for k in fl[uid]:
			GS.state.units[uid].flags[k] = fl[uid][k]
	# One WARLORD per side.
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
			st.players[p].erase(B.ARMY_USES)
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
			print("[sm11e-m4b-fixture]   P%d %-34s %2d models  (off the table, status %d)" % [int(u.owner), uid, u.models.size(), int(u.status)])
			continue
		print("[sm11e-m4b-fixture]   P%d %-34s %2d models  first at (%.2f, %.2f)in  engaged=%s" % [
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
	print("[sm11e-m4b-fixture] %s written (res://tests/saves/%s.w40ksave)" % [out_name, out_name])
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
	for uid in GS.state.units:
		if GS.state.units[uid].models[0].position == null:
			continue
		if re.is_unit_engaged(uid, GS.state):
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
		var got: Array = B.window_offers(int(g[0]), str(g[1]), {"window_id": str(g[1])}).map(func(o): return B.slug_of(str(o.get("stratagem_id", ""))))
		meta["phase"] = keep[0]
		meta["active_player"] = keep[1]
		for slug in g[4]:
			if not slug in got:
				ok = _fail("%s: %s not offered in %s (got %s)" % [name, slug, g[1], str(got)]) and ok
	return ok

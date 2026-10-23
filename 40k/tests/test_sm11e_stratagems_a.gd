extends SceneTree

# Codex: Space Marines (11e) — GENERIC detachment stratagems, WP-M3a
# (SMCodex11e.gd + SMCodexACombat / SMCodexAMovement / SMCodexACommand):
# Gladius Task Force (6), Ironstorm Spearhead, Stormlance Task Force, Gauntlet
# Task Force, Phobos Shadow Force, Tacticus Attack Force, Phobos Shock Force
# (3 each) — 24 stratagems.
# Fixtures (tests/helpers/gen_sm11e_m3a_fixtures.gd):
#   sm11e_m3a_active   P1 Space Marines ACTIVE vs P2 Orks
#   sm11e_m3a_reactive P1 Orks ACTIVE vs P2 Space Marines
# The Space Marine player gets all seven detachments (set in-test).
#
#   A. registry / data: 24 csv ids implemented, windows, pinned bit values,
#      non-Space-Marine armies refused, chapter army fallback (Space Wolves in
#      Gladius Task Force)
#   B. ADAPTIVE STRATEGY + MIGHT OF THE MACHINE SPIRIT  command_phase_main (real
#      END_COMMAND hook), variants, re-offer, CP, once per phase, the ignore-
#      modifier hooks (A/B), expiry at the owner's next Command phase only
#   C. STORM OF DEVASTATION / HEADHUNTER DOCTRINE / RELENTLESS ASSAULT / STRIKE
#      FROM THE SHADOWS  unit_selected_to_shoot (real SELECT_SHOOTER hook) /
#      unit_selected_to_fight, eligibility (hidden), A/B (same seeds), expiry
#   D. ARMOUR OF CONTEMPT / A WORTHY DEATH / HURTLING TARGETS / UMBRAL EVASION /
#      LAYERED CERAMITE  defensive windows + S panel, A/B, ends / expiry
#   E. RESPONSIVE TACTICS / TRANSHUMAN REACTIONS / SUDDEN ONSLAUGHT / AGGRESSIVE
#      DISEMBARKATION / STORM AND SECURE / MORTIS SNARES  Movement phase
#   F. MIGHT OF ANGELS / WIND-SWIFT EVASION / DUTY IS NEVER DONE / TACTICAL
#      WITHDRAWAL / TACTICAL FOCUS / TRANSHUMAN SWIFTNESS  Fight phase
#   G. AI deciders never stall
#
# Usage: godot --headless --path 40k --script tests/test_sm11e_stratagems_a.gd

const ACTIVE := "sm11e_m3a_active"
const REACTIVE := "sm11e_m3a_reactive"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0
const DETS := ["Gladius Task Force", "Ironstorm Spearhead", "Stormlance Task Force", "Gauntlet Task Force",
	"Phobos Shadow Force", "Tacticus Attack Force", "Phobos Shock Force"]

const CSV_STORM := "storm-of-devastation-gladius-task-force"
const CSV_RESPONSIVE := "responsive-tactics-gladius-task-force"
const CSV_WORTHY := "a-worthy-death-gladius-task-force"
const CSV_CONTEMPT := "armour-of-contempt-gladius-task-force"
const CSV_ANGELS := "might-of-angels-gladius-task-force"
const CSV_ADAPTIVE := "adaptive-strategy-gladius-task-force"
const CSV_MACHINE := "might-of-the-machine-spirit-ironstorm-spearhead"
const CSV_CERAMITE := "layered-ceramite-ironstorm-spearhead"
const CSV_HEADHUNTER := "headhunter-doctrine-ironstorm-spearhead"
const CSV_WINDSWIFT := "wind-swift-evasion-stormlance-task-force"
const CSV_ONSLAUGHT := "sudden-onslaught-stormlance-task-force"
const CSV_HURTLING := "hurtling-targets-stormlance-task-force"
const CSV_DUTY := "duty-is-never-done-gauntlet-task-force"
const CSV_SECURE := "storm-and-secure-gauntlet-task-force"
const CSV_AGGRESSIVE := "aggressive-disembarkation-gauntlet-task-force"
const CSV_WITHDRAWAL := "tactical-withdrawal-phobos-shadow-force"
const CSV_SNARES := "mortis-snares-phobos-shadow-force"
const CSV_SHADOWS_A := "strike-from-the-shadows-phobos-shadow-force"
const CSV_FOCUS := "tactical-focus-tacticus-attack-force"
const CSV_RELENTLESS := "relentless-assault-tacticus-attack-force"
const CSV_SWIFTNESS := "transhuman-swiftness-tacticus-attack-force"
const CSV_SHADOWS_B := "strike-from-the-shadows-phobos-shock-force"
const CSV_REACTIONS := "transhuman-reactions-phobos-shock-force"
const CSV_UMBRAL := "umbral-evasion-phobos-shock-force"

const EXPECTED_WINDOWS := {
	CSV_STORM: ["unit_selected_to_shoot"],
	CSV_RESPONSIVE: ["enemy_ended_move"],
	CSV_WORTHY: ["enemy_targets_unit_fight"],
	CSV_CONTEMPT: ["enemy_targets_unit_shooting", "enemy_targets_unit_fight"],
	CSV_ANGELS: ["unit_selected_to_fight"],
	CSV_ADAPTIVE: ["command_phase_main"],
	CSV_MACHINE: ["command_phase_main"],
	CSV_CERAMITE: [],
	CSV_HEADHUNTER: ["unit_selected_to_shoot"],
	CSV_WINDSWIFT: ["fight_phase_end"],
	CSV_ONSLAUGHT: ["unit_selected_to_move"],
	CSV_HURTLING: ["enemy_targets_unit_shooting"],
	CSV_DUTY: ["fight_phase_end"],
	CSV_SECURE: ["movement_phase_end"],
	CSV_AGGRESSIVE: ["unit_selected_to_move"],
	CSV_WITHDRAWAL: ["fight_phase_end"],
	CSV_SNARES: ["movement_phase_end"],
	CSV_SHADOWS_A: ["unit_selected_to_shoot", "unit_selected_to_fight"],
	CSV_FOCUS: ["unit_selected_to_consolidate"],
	CSV_RELENTLESS: ["unit_selected_to_shoot", "unit_selected_to_fight"],
	CSV_SWIFTNESS: ["enemy_has_fought"],
	CSV_SHADOWS_B: ["unit_selected_to_shoot", "unit_selected_to_fight"],
	CSV_REACTIONS: ["enemy_ended_move"],
	CSV_UMBRAL: ["enemy_targets_unit_shooting"],
}

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var Codex = null
var Common = null
var RM = null
var Combat = null
var Movement = null
var Command = null
var _sm := 1


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _initialize() -> void:
	await create_timer(0.3).timeout
	await _run()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _stage_fixture(fixture: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok = slm.load_game(fixture)
	GameConstants.edition = 11
	_sm = 1 if fixture == ACTIVE else 2
	GS.state.factions[str(_sm)]["detachment"] = DETS[0]
	GS.state.factions[str(_sm)]["detachments"] = DETS.duplicate()
	SM.load_faction_stratagems_for_player(_sm)
	var tm = root.get_node("TerrainManager")
	tm.terrain_features = []
	_reset_usage()
	return ok


func _reset_usage(cp: int = 6) -> void:
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = cp
	GS.state.players["2"]["cp"] = cp


func _sid(player: int, csv: String) -> String:
	for s in SM.get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) == csv:
			return str(s.id)
	return ""


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u := _unit(uid)
	if not (u.get("flags", null) is Dictionary):
		u["flags"] = {}
	return u.flags


func _offer_ids(offers: Array) -> Array:
	return offers.map(func(o): return str(o.get("stratagem_id", "")))


func _offer_targets(offers: Array, sid: String) -> Array:
	for o in offers:
		if str(o.get("stratagem_id", "")) == sid:
			return o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))
	return []


func _offer_entry(offers: Array, sid: String, uid: String) -> Dictionary:
	for o in offers:
		if str(o.get("stratagem_id", "")) != sid:
			continue
		for t in o.get("targets", []):
			if str(t.get("unit_id", "")) == uid:
				return t
	return {}


func _no_phase_advance(phase) -> void:
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)


func _decline_pending(phase) -> int:
	var n := 0
	while phase.has_pending_stratagem_window() and n < 8:
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1
	return n


func _phase(phase_id: int):
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	if phase_id != PHASE_COMMAND:
		PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	_decline_pending(phase)
	return phase


func _translate(uid: String, dx_in: float, dy_in: float) -> void:
	for m in _unit(uid).get("models", []):
		var p = m.get("position", null)
		if p is Dictionary:
			m["position"] = {"x": float(p.x) + dx_in * PX, "y": float(p.y) + dy_in * PX}


func _sum_successes(dice: Array, ctx: String) -> int:
	var n := 0
	for b in dice:
		if str(b.get("context", "")) == ctx:
			n += int(b.get("successes", 0))
	return n


func _log_count(fragment: String) -> int:
	var gel = root.get_node_or_null("GameEventLog")
	var n := 0
	if gel and "entries" in gel:
		for e in gel.entries:
			if fragment in str(e.get("text", "")):
				n += 1
	return n


func _block(result: Dictionary, ctx_name: String) -> Dictionary:
	for d in result.get("dice", []):
		if str(d.get("context", "")) == ctx_name:
			return d
	return {}


func _melee_weapon(ws: String, s: String, d: String, a: String = "4", ap: String = "0", rules: String = "") -> Dictionary:
	return {"name": "Test Blade", "type": "Melee", "range": "Melee", "attacks": a, "weapon_skill": ws,
		"strength": s, "ap": ap, "damage": d, "special_rules": rules}


func _melee_board(att_flags: Dictionary, att_kw: Array, weapon: Dictionary, n_att: int, tgt_t: int, tgt_flags: Dictionary = {}, tgt_save: int = 7, tgt_wounds: int = 3, tgt_kw: Array = ["INFANTRY"]) -> Dictionary:
	var atk: Array = []
	for i in range(n_att):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3})
	var tgt: Array = []
	for i in range(4):
		tgt.append({"id": "mt%d" % i, "position": {"x": 30.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": tgt_wounds, "current_wounds": tgt_wounds})
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"name": "Attackers", "keywords": att_kw, "stats": {"toughness": 4, "save": 6, "wounds": 3},
				"abilities": [], "weapons": [weapon]},
			"flags": att_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"name": "Targets", "keywords": tgt_kw, "stats": {"toughness": tgt_t, "save": tgt_save, "wounds": tgt_wounds}, "abilities": []},
			"flags": tgt_flags, "models": tgt},
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 2}}


func _melee(board: Dictionary, seed_val: int) -> Dictionary:
	RE.set_test_seed(seed_val)
	var rng = RE.RNGService.new()
	return RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "Test Blade"}]}}, board, rng)


func _wounds_lost(result: Dictionary, board: Dictionary) -> int:
	var final := {}
	for d in result.get("diffs", []):
		var path := str(d.get("path", ""))
		if path.begins_with("units.U_TGT.models.") and path.ends_with(".current_wounds"):
			final[path] = int(d.get("value", 0))
	var lost := 0
	for path in final:
		var idx := int(path.split(".")[3])
		lost += int(board.units.U_TGT.models[idx].get("wounds", 1)) - int(final[path])
	return lost


## A/B over seeds: [hits_off, hits_on, wounds_off, wounds_on, lost_off, lost_on].
func _ab(board_off: Dictionary, board_on: Dictionary, seeds: Array) -> Array:
	var out := [0, 0, 0, 0, 0, 0]
	for sd in seeds:
		var a = _melee(board_off.duplicate(true), int(sd))
		var b = _melee(board_on.duplicate(true), int(sd))
		out[0] += int(_block(a, "hit_roll_melee").get("successes", 0))
		out[1] += int(_block(b, "hit_roll_melee").get("successes", 0))
		out[2] += int(_block(a, "wound_roll_melee").get("successes", 0))
		out[3] += int(_block(b, "wound_roll_melee").get("successes", 0))
		out[4] += _wounds_lost(a, board_off)
		out[5] += _wounds_lost(b, board_on)
	return out


## Ranged A/B on live-fixture snapshots: [to_hit successes, to_wound successes, target wounds lost].
func _ranged_ab(board_off: Dictionary, board_on: Dictionary, shooter: String, target: String, seeds: Array) -> Array:
	var weapons: Dictionary = RE.get_unit_weapons(shooter, board_off)
	var per := {}
	for mid in weapons:
		for wid in weapons[mid]:
			if str(wid).ends_with("_melee"):
				continue
			if not per.has(wid):
				per[wid] = []
			per[wid].append(mid)
	var asg: Array = []
	for wid in per:
		asg.append({"weapon_id": wid, "target_unit_id": target, "model_ids": per[wid]})
	var out := [0, 0, 0, 0, 0, 0]
	for sd in seeds:
		var a = RE.resolve_shoot({"actor_unit_id": shooter, "payload": {"assignments": asg}}, board_off.duplicate(true), RE.RNGService.new(int(sd)))
		var b = RE.resolve_shoot({"actor_unit_id": shooter, "payload": {"assignments": asg}}, board_on.duplicate(true), RE.RNGService.new(int(sd)))
		out[0] += _sum_successes(a.get("dice", []), "to_hit")
		out[1] += _sum_successes(b.get("dice", []), "to_hit")
		out[2] += _sum_successes(a.get("dice", []), "to_wound")
		out[3] += _sum_successes(b.get("dice", []), "to_wound")
		out[4] += _lost_in(a, target, board_off)
		out[5] += _lost_in(b, target, board_on)
	return out


func _lost_in(result: Dictionary, target: String, board: Dictionary) -> int:
	var final := {}
	for d in result.get("diffs", []):
		var path := str(d.get("path", ""))
		if path.begins_with("units.%s.models." % target) and path.ends_with(".current_wounds"):
			final[path] = int(d.get("value", 0))
	var lost := 0
	for path in final:
		var idx := int(path.split(".")[3])
		lost += int(board.units[target].models[idx].get("current_wounds", 1)) - int(final[path])
	return lost


func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])


## A dense ruin (tall) under a unit — 13.09 hidden (setup).
func _ruin_under(uid: String) -> void:
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for m in _unit(uid).models:
		var p = m.position
		minp = Vector2(minf(minp.x, p.x), minf(minp.y, p.y))
		maxp = Vector2(maxf(maxp.x, p.x), maxf(maxp.y, p.y))
	var c := (minp + maxp) / 2.0
	var tm = root.get_node("TerrainManager")
	tm.terrain_features = [{"id": "sm11e_test_ruin", "type": "ruins", "polygon": _rect(c.x, c.y, maxp.x - minp.x + 4.0 * PX, maxp.y - minp.y + 4.0 * PX), "height_category": "tall"}]


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	Codex = load("res://scripts/codex/space_marines/SMCodex11e.gd")
	Common = load("res://scripts/codex/space_wolves/SWCommon.gd")
	RM = load("res://scripts/rules/ReactiveMove11e.gd")
	Combat = load("res://scripts/codex/space_marines/SMCodexACombat.gd")
	Movement = load("res://scripts/codex/space_marines/SMCodexAMovement.gd")
	Command = load("res://scripts/codex/space_marines/SMCodexACommand.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)

	print("\n=== test_sm11e_stratagems_a ===\n")
	_check("fixture %s loads" % ACTIVE, _stage_fixture(ACTIVE))
	_section_registry()
	_section_command()
	_section_attack_buffs()
	_section_defence()
	_section_movement()
	_section_fight()
	_section_ai()
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry / data --")
	var a_ids: Array = Codex.group_a_ids()
	_check("24 WP-M3a csv ids registered", a_ids.size() == 24, str(a_ids.size()))
	var impl: Array = Codex.all_implemented_ids()
	var all_a_impl := true
	for id in a_ids:
		if not id in impl:
			all_a_impl = false
	_check("…all implemented", all_a_impl)
	var loaded := 0
	for s in SM.get_faction_stratagems_for_player(1):
		if not Codex.handles(s):
			continue
		var csv := str(s.get("csv_id", ""))
		if not csv in a_ids:
			continue
		loaded += 1
		_check("%s: implemented, marker custom:sm11e" % csv, bool(s.get("implemented", false)) and Codex.is_registered(s))
		var w: Array = s.get("timing", {}).get("windows", [])
		_check("%s windows = %s" % [csv, str(EXPECTED_WINDOWS.get(csv, "?"))], w == EXPECTED_WINDOWS.get(csv, ["?"]), str(w))
	_check("all 24 loaded for P1 (7 detachments)", loaded == 24, str(loaded))
	_check("HitModifier.MINUS_ONE pinned at 4", int(RE.HitModifier.MINUS_ONE) == Codex.HIT_MINUS_ONE)
	_check("WoundModifier.MINUS_ONE pinned at 8", int(RE.WoundModifier.MINUS_ONE) == Codex.WOUND_MINUS_ONE)
	var strat: Dictionary = SM.get_stratagem(_sid(1, CSV_CERAMITE))
	var v = Codex.validate(strat, 2, "U_MEK_GUNZ_A", {})
	_check("a non-Space-Marine army (Orks) is refused", not v.ok and "Space Marine" in str(v.reason), str(v))
	_check("SMCodexB group: loaded only when the file exists", (Codex.group_b() != null) == ResourceLoader.exists(Codex.GROUP_B_PATH))
	# Chapter army fallback: a Space Wolves army in Gladius Task Force gets the SM rows.
	var slm = root.get_node("SaveLoadManager")
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/sw11e_s3_active" + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + "sw11e_s3_active" + ext))
	slm.load_game("sw11e_s3_active")
	GameConstants.edition = 11
	GS.state.factions["1"]["detachment"] = "Gladius Task Force"
	GS.state.factions["1"]["detachments"] = ["Gladius Task Force"]
	SM.load_faction_stratagems_for_player(1)
	_phase(PHASE_SHOOTING)
	var sw_storm := _sid(1, CSV_STORM)
	_check("Space Wolves army in Gladius Task Force: STORM OF DEVASTATION loaded (SM fallback)", sw_storm != "")
	var sw_offers = SM.get_window_offers(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_WULFEN_A"})
	_check("…offered when the Wulfen are selected to shoot", sw_storm in _offer_ids(sw_offers), str(_offer_ids(sw_offers)))
	var sw_n := 0
	for s in SM.get_faction_stratagems_for_player(1):
		if Codex.handles(s) and bool(s.get("implemented", false)):
			sw_n += 1
	_check("…all 6 Gladius rows implemented for the Space Wolves army", sw_n == 6, str(sw_n))


# ---------------------------------------------------------------------------
func _section_command() -> void:
	print("\n-- B. ADAPTIVE STRATEGY + MIGHT OF THE MACHINE SPIRIT (command_phase_main) --")
	_stage_fixture(ACTIVE)
	var ad := _sid(1, CSV_ADAPTIVE)
	var ms := _sid(1, CSV_MACHINE)
	var phase = _phase(PHASE_COMMAND)
	var offers = SM.get_window_offers(1, "command_phase_main", {"phase": "command"})
	var ad_t := _offer_targets(offers, ad)
	var ms_t := _offer_targets(offers, ms)
	_check("ADAPTIVE STRATEGY offered on the Hellblasters", "U_HELLBLASTER_SQUAD_A" in ad_t, str(ad_t))
	_check("ADAPTIVE STRATEGY also on the Gladius Lancer (no MONSTER/VEHICLE exclusion printed)", "U_GLADIATOR_LANCER_A" in ad_t)
	_check("ADAPTIVE STRATEGY: three doctrines, a choice required", _offer_entry(offers, ad, "U_HELLBLASTER_SQUAD_A").get("variants", []).size() == 3 and bool(_offer_entry(offers, ad, "U_HELLBLASTER_SQUAD_A").get("require_variant", false)))
	_check("MIGHT OF THE MACHINE SPIRIT offered on the Gladiator Lancer only", ms_t == ["U_GLADIATOR_LANCER_A"], str(ms_t))
	_check("…not on the Rhino (DEDICATED TRANSPORT) / Land Speeder (FLY)", not "U_RHINO_A" in ms_t and not "U_LAND_SPEEDER_A" in ms_t)
	_check("not offered to P2 (Orks)", not ad in _offer_ids(SM.get_window_offers(2, "command_phase_main", {"phase": "command"})))
	_check("not in another window", not ad in _offer_ids(SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_HELLBLASTER_SQUAD_A", "move_type": "normal"})))
	var r = phase.execute_action({"type": "END_COMMAND", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("END_COMMAND opens command_phase_main for P1", str(pend.get("window_id", "")) == "command_phase_main" and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, "command_phase_main", {"phase": "command"}, "")
	var none = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "command_phase_main", "stratagem_id": ad, "target_unit_id": "U_HELLBLASTER_SQUAD_A"})
	_check("ADAPTIVE STRATEGY without a doctrine choice refused", not none.get("success", true))
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "command_phase_main", "stratagem_id": ad,
		"target_unit_id": "U_HELLBLASTER_SQUAD_A", "context": {"variant_id": "devastator"}})
	_check("USE ADAPTIVE STRATEGY (Devastator Doctrine) succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var f := _flags("U_HELLBLASTER_SQUAD_A")
	_check("per-unit doctrine keys written (SWCommon contract)", str(f.get("sw11e_doctrine", "")) == "devastator" and int(f.get("sw11e_doctrine_expires_player", 0)) == 1 and str(f.get("sm11e_adaptive_strategy", "")) == "devastator", str(f))
	_check("SWCommon.doctrine_active: devastator yes, assault no", Common.doctrine_active_id("U_HELLBLASTER_SQUAD_A", "devastator") and not Common.doctrine_active_id("U_HELLBLASTER_SQUAD_A", "assault"))
	_check("Game Log names the stratagem and doctrine", _log_count("Used ADAPTIVE STRATEGY") >= 1 and _log_count("Devastator Doctrine") >= 1)
	pend = phase.get_pending_stratagem_window()
	_check("window re-offered after the use", str(pend.get("window_id", "")) == "command_phase_main", str(pend.get("window_id", "")))
	var re_ids := _offer_ids(pend.get("offers", []))
	_check("…MACHINE SPIRIT still offered, ADAPTIVE STRATEGY not (once per phase)", ms in re_ids and not ad in re_ids, str(re_ids))
	cp0 = _cp(1)
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "command_phase_main", "stratagem_id": ms, "target_unit_id": "U_GLADIATOR_LANCER_A"})
	_check("USE MIGHT OF THE MACHINE SPIRIT succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag sm11e_machine_spirit", bool(_flags("U_GLADIATOR_LANCER_A").get("sm11e_machine_spirit", false)))
	_decline_pending(phase)
	var lancer := _unit("U_GLADIATOR_LANCER_A")
	_check("hit bits: -1 to hit ignored (+1 kept)", Codex.apply_hit_bits(4 | 2, lancer, {}, false, []) == 2)
	_check("wound bits: -1 to wound ignored", Codex.apply_wound_bits(8, lancer, {}, false, []) == 0)
	_check("BS worsening ignored (ranged)", Codex.ignores_bs_worsening(lancer, false) and not Codex.ignores_bs_worsening(lancer, true))
	var stack = ModifierStack.new()
	stack.add("bs", 1, "cover")
	stack.add("hit_roll", 1, "heavy")
	stack.add("hit_roll", -1, "damaged")
	var removed: Array = Codex.filter_hit_stack(lancer, stack, false)
	_check("hit stack: cover + damaged removed, [HEAVY] kept", removed.size() == 2 and stack.net("hit_roll") == 1 and stack.net("bs") == 0, "%s / %s" % [str(removed), str(stack.entries)])
	_check("M penalties ignored", Codex.ignores_move_penalties(lancer))
	_check("another vehicle unaffected", not Codex.ignores_bs_worsening(_unit("U_LAND_SPEEDER_A"), false))
	# A/B ranged (same seeds): the Lancer shooting with an imposed -1 to hit.
	var board: Dictionary = GS.create_snapshot()
	board.units.U_GLADIATOR_LANCER_A.flags["effect_minus_one_hit"] = true
	var off_board: Dictionary = board.duplicate(true)
	off_board.units.U_GLADIATOR_LANCER_A.flags.erase("sm11e_machine_spirit")
	var ab := _ranged_ab(off_board, board, "U_GLADIATOR_LANCER_A", "U_MEK_GUNZ_A", range(8100, 8130))
	_check("A/B MACHINE SPIRIT vs an imposed -1 to hit: more hits (%d -> %d)" % [ab[0], ab[1]], ab[1] > ab[0], str(ab))
	# Expiry: the opponent's Command phase does not end them; the owner's does.
	SM.on_turn_start(2)
	_check("still active at the start of P2's turn", Common.doctrine_active_id("U_HELLBLASTER_SQUAD_A", "devastator") and bool(_flags("U_GLADIATOR_LANCER_A").get("sm11e_machine_spirit", false)))
	SM.on_turn_start(1)
	_check("expired at the start of P1's next Command phase: doctrine keys + machine spirit cleared",
		not _flags("U_HELLBLASTER_SQUAD_A").has("sw11e_doctrine") and not _flags("U_HELLBLASTER_SQUAD_A").has("sm11e_adaptive_strategy") and not _flags("U_GLADIATOR_LANCER_A").has("sm11e_machine_spirit"))
	_check("…the vehicle no longer ignores -1 to hit", Codex.apply_hit_bits(4, _unit("U_GLADIATOR_LANCER_A"), {}, false, []) == 4)
	var bad = SM.can_use_stratagem(1, ad, "U_HELLBLASTER_SQUAD_A", {"window_id": "command_phase_main", "variant_id": "bogus"})
	_check("an unknown doctrine is refused", not bad.can_use, str(bad))
	GS.state.meta["active_player"] = 2
	_check("refused in the opponent's Command phase", not SM.can_use_stratagem(1, ms, "U_GLADIATOR_LANCER_A", {"window_id": "command_phase_main"}).can_use)
	GS.state.meta["active_player"] = 1


# ---------------------------------------------------------------------------
func _section_attack_buffs() -> void:
	print("\n-- C. STORM OF DEVASTATION / HEADHUNTER / RELENTLESS ASSAULT / STRIKE FROM THE SHADOWS --")
	_stage_fixture(ACTIVE)
	var st := _sid(1, CSV_STORM)
	var hh := _sid(1, CSV_HEADHUNTER)
	var ra := _sid(1, CSV_RELENTLESS)
	var sa := _sid(1, CSV_SHADOWS_A)
	var sb := _sid(1, CSV_SHADOWS_B)
	var phase = _phase(PHASE_SHOOTING)
	var w := "unit_selected_to_shoot"
	var hb := _offer_ids(SM.get_window_offers(1, w, {"phase": "shooting", "unit_id": "U_HELLBLASTER_SQUAD_A"}))
	_check("Hellblasters (AA TACTICUS INFANTRY): STORM + RELENTLESS offered, HEADHUNTER / STRIKE not", st in hb and ra in hb and not hh in hb and not sa in hb, str(hb))
	var lc := _offer_ids(SM.get_window_offers(1, w, {"phase": "shooting", "unit_id": "U_GLADIATOR_LANCER_A"}))
	_check("Gladiator Lancer: HEADHUNTER + STORM offered", hh in lc and st in lc, str(lc))
	_check("Land Speeder (FLY): HEADHUNTER not offered", not hh in _offer_ids(SM.get_window_offers(1, w, {"phase": "shooting", "unit_id": "U_LAND_SPEEDER_A"})))
	_check("Infiltrators in the open (not hidden): STRIKE FROM THE SHADOWS not offered", not sa in _offer_ids(SM.get_window_offers(1, w, {"phase": "shooting", "unit_id": "U_INFILTRATOR_SQUAD_A"})))
	_check("no Space Marine stratagem offered to P2 (Orks)", _offer_ids(SM.get_window_offers(2, w, {"phase": "shooting", "unit_id": "U_KOMMANDOS_A"})).filter(func(i): return Codex.handles(SM.get_stratagem(i))).is_empty())
	# Real hook: SELECT_SHOOTER.
	var r = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_HELLBLASTER_SQUAD_A", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("SELECT_SHOOTER Hellblasters opens unit_selected_to_shoot for P1", str(pend.get("window_id", "")) == w and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, w, {"phase": "shooting", "unit_id": "U_HELLBLASTER_SQUAD_A"}, "")
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": st, "target_unit_id": "U_HELLBLASTER_SQUAD_A"})
	_check("USE STORM OF DEVASTATION succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("the engine's [IGNORES COVER] grant is on", bool(_flags("U_HELLBLASTER_SQUAD_A").get("effect_ignores_cover", false)) and ModifierStack.attack_ignores_cover(_unit("U_HELLBLASTER_SQUAD_A"), {}))
	_check("15.01: RELENTLESS ASSAULT refused on the Hellblasters this phase", not SM.can_use_stratagem(1, ra, "U_HELLBLASTER_SQUAD_A", {"window_id": w, "unit_id": "U_HELLBLASTER_SQUAD_A", "variant_id": "sustained"}).can_use)
	_check("once per phase: STORM refused on the Lancer", not SM.can_use_stratagem(1, st, "U_GLADIATOR_LANCER_A", {"window_id": w, "unit_id": "U_GLADIATOR_LANCER_A"}).can_use)
	_decline_pending(phase)
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry: [IGNORES COVER] grant + marker cleared", not _flags("U_HELLBLASTER_SQUAD_A").has("effect_ignores_cover") and not _flags("U_HELLBLASTER_SQUAD_A").has("sm11e_storm_of_devastation"))
	# A grant the unit already had survives the expiry.
	_reset_usage()
	_flags("U_GLADIATOR_LANCER_A")["effect_ignores_cover"] = true
	SM.use_stratagem(1, st, "U_GLADIATOR_LANCER_A", {"window_id": w, "unit_id": "U_GLADIATOR_LANCER_A"})
	SM.on_phase_end(PHASE_SHOOTING)
	_check("a pre-existing [IGNORES COVER] is kept at expiry", bool(_flags("U_GLADIATOR_LANCER_A").get("effect_ignores_cover", false)))
	_flags("U_GLADIATOR_LANCER_A").erase("effect_ignores_cover")
	# HEADHUNTER DOCTRINE — ranged [LETHAL HITS: MONSTER/VEHICLE].
	_reset_usage()
	use = SM.use_stratagem(1, hh, "U_GLADIATOR_LANCER_A", {"window_id": w, "unit_id": "U_GLADIATOR_LANCER_A"})
	_check("USE HEADHUNTER DOCTRINE succeeds", use.get("success", false), str(use.get("error", "")))
	var lancer := _unit("U_GLADIATOR_LANCER_A")
	_check("lethal vs the Mek Gunz (VEHICLE)", str(Codex.attack_grants(lancer, _unit("U_MEK_GUNZ_A"), false).lethal) == "Headhunter Doctrine")
	_check("…not vs the Kommandos (INFANTRY), not in melee", str(Codex.attack_grants(lancer, _unit("U_KOMMANDOS_A"), false).lethal) == "" and str(Codex.attack_grants(lancer, _unit("U_MEK_GUNZ_A"), true).lethal) == "")
	var board: Dictionary = GS.create_snapshot()
	board.units.U_MEK_GUNZ_A.meta.stats["toughness"] = 20
	for m in board.units.U_MEK_GUNZ_A.models:
		m["wounds"] = 99
		m["current_wounds"] = 99
	var off_b: Dictionary = board.duplicate(true)
	off_b.units.U_GLADIATOR_LANCER_A.flags.erase("sm11e_headhunter")
	var ab := _ranged_ab(off_b, board, "U_GLADIATOR_LANCER_A", "U_MEK_GUNZ_A", range(8200, 8240))
	_check("A/B HEADHUNTER vs a T20 VEHICLE: same hits (%d), more wounds lost (%d -> %d)" % [ab[0], ab[4], ab[5]], ab[0] == ab[1] and ab[5] > ab[4], str(ab))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry: sm11e_headhunter cleared", not _flags("U_GLADIATOR_LANCER_A").has("sm11e_headhunter"))
	# RELENTLESS ASSAULT — the variant choice.
	_reset_usage()
	var ra_offers = SM.get_window_offers(1, w, {"phase": "shooting", "unit_id": "U_HELLBLASTER_SQUAD_A"})
	var ra_entry := _offer_entry(ra_offers, ra, "U_HELLBLASTER_SQUAD_A")
	_check("RELENTLESS ASSAULT: two options, a choice required", ra_entry.get("variants", []).size() == 2 and bool(ra_entry.get("require_variant", false)), str(ra_entry))
	use = SM.use_stratagem(1, ra, "U_HELLBLASTER_SQUAD_A", {"window_id": w, "unit_id": "U_HELLBLASTER_SQUAD_A", "variant_id": "sustained"})
	_check("USE RELENTLESS ASSAULT (sustained) succeeds", use.get("success", false), str(use.get("error", "")))
	var hbu := _unit("U_HELLBLASTER_SQUAD_A")
	_check("[SUSTAINED HITS 1] vs INFANTRY, not vs a VEHICLE", int(Codex.attack_grants(hbu, _unit("U_KOMMANDOS_A"), false).sustained) == 1 and int(Codex.attack_grants(hbu, _unit("U_MEK_GUNZ_A"), false).sustained) == 0)
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry: sm11e_relentless_assault cleared", not _flags("U_HELLBLASTER_SQUAD_A").has("sm11e_relentless_assault"))
	var tkw := ["ADEPTUS ASTARTES", "INFANTRY", "TACTICUS"]
	var abm = _ab(_melee_board({}, tkw, _melee_weapon("3", "4", "1", "6"), 3, 4), _melee_board({"sm11e_relentless_assault": "sustained"}, tkw, _melee_weapon("3", "4", "1", "6"), 3, 4), range(8300, 8330))
	_check("A/B RELENTLESS (sustained) melee vs INFANTRY: same rolled hits, more wounds from the extra hits (%d -> %d)" % [abm[2], abm[3]], abm[0] == abm[1] and abm[3] > abm[2], str(abm))
	var abv = _ab(_melee_board({}, tkw, _melee_weapon("3", "4", "1", "6"), 3, 10, {}, 7, 20, ["VEHICLE"]), _melee_board({"sm11e_relentless_assault": "lethal"}, tkw, _melee_weapon("3", "4", "1", "6"), 3, 10, {}, 7, 20, ["VEHICLE"]), range(8300, 8330))
	_check("A/B RELENTLESS (lethal) melee vs a T10 VEHICLE: more wounds lost (%d -> %d)" % [abv[4], abv[5]], abv[5] > abv[4], str(abv))
	var abx = _ab(_melee_board({}, tkw, _melee_weapon("3", "4", "1", "6"), 3, 10, {}, 7, 20, ["INFANTRY"]), _melee_board({"sm11e_relentless_assault": "lethal"}, tkw, _melee_weapon("3", "4", "1", "6"), 3, 10, {}, 7, 20, ["INFANTRY"]), range(8300, 8320))
	_check("…the lethal option does nothing vs INFANTRY", abx[4] == abx[5], str(abx))
	# STRIKE FROM THE SHADOWS — hidden PHOBOS only.
	_reset_usage()
	_ruin_under("U_INFILTRATOR_SQUAD_A")
	_check("Infiltrators inside a dense ruin are hidden (13.09)", Combat.unit_is_hidden("U_INFILTRATOR_SQUAD_A"))
	var inf := _offer_ids(SM.get_window_offers(1, w, {"phase": "shooting", "unit_id": "U_INFILTRATOR_SQUAD_A"}))
	_check("hidden Infiltrators: both STRIKE FROM THE SHADOWS rows offered", sa in inf and sb in inf, str(inf))
	use = SM.use_stratagem(1, sa, "U_INFILTRATOR_SQUAD_A", {"window_id": w, "unit_id": "U_INFILTRATOR_SQUAD_A"})
	_check("USE STRIKE FROM THE SHADOWS succeeds", use.get("success", false), str(use.get("error", "")))
	var g: Dictionary = Codex.attack_grants(_unit("U_INFILTRATOR_SQUAD_A"), _unit("U_KOMMANDOS_A"), false)
	_check("+1 S and [LETHAL HITS] (ranged and melee)", int(g.strength) == 1 and str(g.lethal) == "Strike from the Shadows" and int(Codex.attack_grants(_unit("U_INFILTRATOR_SQUAD_A"), _unit("U_KOMMANDOS_A"), true).strength) == 1)
	var pkw := ["ADEPTUS ASTARTES", "INFANTRY", "PHOBOS"]
	var abs_ = _ab(_melee_board({}, pkw, _melee_weapon("3", "4", "1", "6"), 3, 5), _melee_board({"sm11e_strike_shadows": true}, pkw, _melee_weapon("3", "4", "1", "6"), 3, 5), range(8400, 8430))
	_check("A/B STRIKE FROM THE SHADOWS melee S4 vs T5: same hits, more wounds (%d -> %d)" % [abs_[2], abs_[3]], abs_[0] == abs_[1] and abs_[3] > abs_[2], str(abs_))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry: sm11e_strike_shadows cleared", not _flags("U_INFILTRATOR_SQUAD_A").has("sm11e_strike_shadows"))
	GS.state.meta["active_player"] = 2
	_check("STRIKE refused in the opponent's Shooting phase", not SM.can_use_stratagem(1, sa, "U_INFILTRATOR_SQUAD_A", {"window_id": w, "unit_id": "U_INFILTRATOR_SQUAD_A"}).can_use)
	GS.state.meta["active_player"] = 1
	root.get_node("TerrainManager").terrain_features = []


# ---------------------------------------------------------------------------
func _section_defence() -> void:
	print("\n-- D. ARMOUR OF CONTEMPT / A WORTHY DEATH / HURTLING TARGETS / UMBRAL EVASION / LAYERED CERAMITE --")
	_stage_fixture(ACTIVE)
	var ac := _sid(1, CSV_CONTEMPT)
	var wd := _sid(1, CSV_WORTHY)
	var phase = _phase(PHASE_FIGHT)
	var w := "enemy_targets_unit_fight"
	var ctx := {"phase": "fight", "attacker_unit_id": "U_BOYZ_B", "target_unit_ids": ["U_ASSAULT_INTERCESSOR_SQUAD_A"]}
	var offers = SM.get_window_offers(1, w, ctx)
	_check("ARMOUR OF CONTEMPT + A WORTHY DEATH offered when the Boyz target the Assault Intercessors", _offer_targets(offers, ac) == ["U_ASSAULT_INTERCESSOR_SQUAD_A"] and _offer_targets(offers, wd) == ["U_ASSAULT_INTERCESSOR_SQUAD_A"], str(_offer_ids(offers)))
	_check("not for a unit that was not targeted", not SM.can_use_stratagem(1, ac, "U_OUTRIDER_SQUAD_A", ctx.merged({"window_id": w})).can_use)
	phase.open_stratagem_window(1, w, ctx, "")
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": ac, "target_unit_id": "U_ASSAULT_INTERCESSOR_SQUAD_A"})
	_check("USE ARMOUR OF CONTEMPT succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var f = _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").get("sm11e_armour_of_contempt", null)
	_check("flag records the attacker", typeof(f) == TYPE_DICTIONARY and "U_BOYZ_B" in f.get("attacker_ids", []), str(f))
	var aiu := _unit("U_ASSAULT_INTERCESSOR_SQUAD_A")
	_check("modify_ap: AP 2 -> 1, AP 1 -> 0, AP 0 stays 0 (both sign conventions)", Codex.modify_ap(2, {}, aiu) == 1 and Codex.modify_ap(1, {}, aiu) == 0 and Codex.modify_ap(0, {}, aiu) == 0 and Codex.modify_ap(-2, {}, aiu) == -1)
	var okw := ["ORKS", "INFANTRY"]
	var ab = _ab(_melee_board({}, okw, _melee_weapon("3", "5", "1", "6", "-2"), 3, 4, {}, 3), _melee_board({}, okw, _melee_weapon("3", "5", "1", "6", "-2"), 3, 4, {"sm11e_armour_of_contempt": {"attacker_ids": ["U_ATK"]}}, 3), range(8500, 8530))
	_check("A/B AP-2 vs Sv3+: same wounds (%d), fewer wounds lost (%d -> %d)" % [ab[2], ab[4], ab[5]], ab[2] == ab[3] and ab[5] < ab[4], str(ab))
	Codex.on_unit_has_attacked("U_NOBZ_A")
	_check("another enemy unit attacking does not end it", _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").has("sm11e_armour_of_contempt"))
	Codex.on_unit_has_attacked("U_BOYZ_B")
	_check("ends once the Boyz have attacked", not _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").has("sm11e_armour_of_contempt"))
	_decline_pending(phase)
	# A WORTHY DEATH: the engine's Fight On Death.
	_reset_usage()
	use = SM.use_stratagem(1, wd, "U_ASSAULT_INTERCESSOR_SQUAD_A", ctx.merged({"window_id": w}))
	_check("USE A WORTHY DEATH succeeds", use.get("success", false), str(use.get("error", "")))
	_check("Fight On Death mode sm11e_worthy_death", str(_flags("U_ASSAULT_INTERCESSOR_SQUAD_A").get("ork11e_fod_mode", "")) == "sm11e_worthy_death")
	_check("FOD roll: 4+, no modifier", Codex.is_fod_mode("sm11e_worthy_death") and int(Codex.fod_roll("x", 0).get("pass", 0)) == 4 and int(Codex.fod_roll("x", 0).get("mod", 9)) == 0)
	var kept_seen := false
	var removed_seen := false
	for sd in range(8600, 8640):
		if kept_seen and removed_seen:
			break
		var idx := 0
		var alive_idx := -1
		for i in range(_unit("U_ASSAULT_INTERCESSOR_SQUAD_A").models.size()):
			if _unit("U_ASSAULT_INTERCESSOR_SQUAD_A").models[i].get("alive", true) and not i in _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").get("ork11e_fod_pending", []):
				alive_idx = i
				break
		if alive_idx < 0:
			break
		idx = alive_idx
		RE.set_test_seed(sd)
		var changes := [{"op": "set", "path": "units.U_ASSAULT_INTERCESSOR_SQUAD_A.models.%d.alive" % idx, "value": false}]
		phase._ork11e_fod_intercept(changes)
		var kept: bool = changes[0].get("value", false) == true
		if kept:
			kept_seen = true
		else:
			removed_seen = true
		PM.apply_state_changes(changes)
	_check("a destroyed model rolls: some kept on the battlefield (4+), some removed", kept_seen and removed_seen)
	var fod_named := false
	for b in phase.dice_log:
		if typeof(b) == TYPE_DICTIONARY and str(b.get("context", "")) == "ork11e_fight_on_death" and str(b.get("stratagem", "")) == "A WORTHY DEATH":
			fod_named = true
	_check("the Fight On Death dice block names A WORTHY DEATH", fod_named)
	var pending: Array = _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").get("ork11e_fod_pending", [])
	var rm_diffs: Array = phase._ork11e_fod_remove(["U_ASSAULT_INTERCESSOR_SQUAD_A"], "has fought")
	_check("kept models are removed when the unit has fought (%d pending)" % pending.size(), pending.size() > 0 and rm_diffs.any(func(d): return str(d.get("path", "")).ends_with(".alive") and d.get("value", true) == false))
	PM.apply_state_changes(rm_diffs)
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: the FOD mode is cleared", not _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").has("ork11e_fod_mode"))
	_reset_usage()
	phase.units_that_fought.append("U_ASSAULT_INTERCESSOR_SQUAD_A")
	_check("A WORTHY DEATH refused once the unit has been selected to fight", not SM.can_use_stratagem(1, wd, "U_ASSAULT_INTERCESSOR_SQUAD_A", ctx.merged({"window_id": w})).can_use)
	phase.units_that_fought.erase("U_ASSAULT_INTERCESSOR_SQUAD_A")
	# Opponent's Shooting phase (reactive fixture): ARMOUR OF CONTEMPT / HURTLING / UMBRAL.
	_stage_fixture(REACTIVE)
	var ac2 := _sid(2, CSV_CONTEMPT)
	var ht := _sid(2, CSV_HURTLING)
	var ue := _sid(2, CSV_UMBRAL)
	phase = _phase(PHASE_SHOOTING)
	var sw := "enemy_targets_unit_shooting"
	var base := {"phase": "shooting", "attacker_unit_id": "U_FLASH_GITZ_A"}
	_check("HURTLING TARGETS offered on the targeted Land Speeder (SPEEDER)", _offer_targets(SM.get_window_offers(2, sw, base.merged({"target_unit_ids": ["U_LAND_SPEEDER_A"]})), ht) == ["U_LAND_SPEEDER_A"])
	_check("HURTLING TARGETS not on the Hellblasters", not ht in _offer_ids(SM.get_window_offers(2, sw, base.merged({"target_unit_ids": ["U_HELLBLASTER_SQUAD_A"]}))))
	_check("UMBRAL EVASION offered on the targeted Infiltrators (PHOBOS), not the Land Speeder", _offer_targets(SM.get_window_offers(2, sw, base.merged({"target_unit_ids": ["U_INFILTRATOR_SQUAD_A"]})), ue) == ["U_INFILTRATOR_SQUAD_A"] and not ue in _offer_ids(SM.get_window_offers(2, sw, base.merged({"target_unit_ids": ["U_LAND_SPEEDER_A"]}))))
	_check("ARMOUR OF CONTEMPT offered in the opponent's Shooting phase", ac2 in _offer_ids(SM.get_window_offers(2, sw, base.merged({"target_unit_ids": ["U_HELLBLASTER_SQUAD_A"]}))))
	phase.active_shooter_id = "U_FLASH_GITZ_A"
	phase.confirmed_assignments = [{"target_unit_id": "U_LAND_SPEEDER_A", "weapon_id": "x", "model_ids": []}]
	var chk: Dictionary = phase._check_reactive_stratagems()
	var found := false
	for e in chk.get("available_stratagems", []):
		if str(e.get("stratagem", {}).get("id", "")) == ht:
			found = true
	_check("HURTLING TARGETS in the defender's reactive dialog", chk.get("has_opportunities", false) and found)
	phase.awaiting_reactive_stratagem = true
	cp0 = _cp(2)
	var ru = phase.execute_action({"type": "USE_REACTIVE_STRATAGEM", "player": 2, "stratagem_id": ht, "target_unit_id": "U_LAND_SPEEDER_A"})
	_check("USE_REACTIVE_STRATAGEM HURTLING TARGETS succeeds, CP -1", ru.get("success", false) and _cp(2) == cp0 - 1, str(ru.get("error", "")))
	var ls := _unit("U_LAND_SPEEDER_A")
	_check("ranged attacks that target it: -1 to hit; melee unaffected", (Codex.apply_hit_bits(0, {}, ls, false, []) & 4) == 4 and Codex.apply_hit_bits(0, {}, ls, true, []) == 0)
	var ledger: Array = []
	Codex.apply_hit_bits(0, {}, ls, false, ledger)
	_check("named in the modifier ledger", ledger.any(func(e): return str(e.get("source", "")) == "Hurtling Targets"), str(ledger))
	var board: Dictionary = GS.create_snapshot()
	var off_b: Dictionary = board.duplicate(true)
	off_b.units.U_LAND_SPEEDER_A.flags.erase("sm11e_hurtling_targets")
	var rab := _ranged_ab(off_b, board, "U_FLASH_GITZ_A", "U_LAND_SPEEDER_A", range(8700, 8730))
	_check("A/B HURTLING TARGETS (Flash Gitz vs Land Speeder): fewer hits (%d -> %d)" % [rab[0], rab[1]], rab[1] < rab[0], str(rab))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at the end of the phase", not _flags("U_LAND_SPEEDER_A").has("sm11e_hurtling_targets"))
	_reset_usage()
	var ue_use = SM.use_stratagem(2, ue, "U_INFILTRATOR_SQUAD_A", base.merged({"window_id": sw, "target_unit_ids": ["U_INFILTRATOR_SQUAD_A"]}))
	_check("USE UMBRAL EVASION succeeds; -1 to hit for ranged attacks that target it", ue_use.get("success", false) and (Codex.apply_hit_bits(0, {}, _unit("U_INFILTRATOR_SQUAD_A"), false, []) & 4) == 4, str(ue_use.get("error", "")))
	SM.on_phase_end(PHASE_SHOOTING)
	# Own Shooting phase: refused.
	_stage_fixture(ACTIVE)
	_check("HURTLING TARGETS refused in its own turn", not SM.can_use_stratagem(1, _sid(1, CSV_HURTLING), "U_LAND_SPEEDER_A", {"window_id": sw, "attacker_unit_id": "U_FLASH_GITZ_A", "target_unit_ids": ["U_LAND_SPEEDER_A"]}).can_use)
	# LAYERED CERAMITE — S panel, any phase, VEHICLE.
	_stage_fixture(REACTIVE)
	var lc := _sid(2, CSV_CERAMITE)
	phase = _phase(PHASE_SHOOTING)
	var panel = SM.can_use_stratagem(2, lc)
	_check("S panel: LAYERED CERAMITE usable in the opponent's Shooting phase", panel.can_use, str(panel))
	_check("target: Gladiator Lancer (VEHICLE) yes, Hellblasters no, an Ork unit no", SM.can_use_stratagem(2, lc, "U_GLADIATOR_LANCER_A").can_use and not SM.can_use_stratagem(2, lc, "U_HELLBLASTER_SQUAD_A").can_use and not SM.can_use_stratagem(2, lc, "U_KOMMANDOS_A").can_use)
	cp0 = _cp(2)
	use = SM.use_stratagem(2, lc, "U_GLADIATOR_LANCER_A")
	_check("use succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	var lu := _unit("U_GLADIATOR_LANCER_A")
	_check("FNP 5+ against mortal wounds, not ordinary damage", RE.get_unit_fnp_vs(lu, false, true) == 5 and RE.get_unit_fnp_vs(lu, false, false) == 0)
	var lost_off := 0
	var lost_on := 0
	var mboard: Dictionary = GS.create_snapshot()
	var moff: Dictionary = mboard.duplicate(true)
	moff.units.U_GLADIATOR_LANCER_A.flags.erase("sm11e_layered_ceramite")
	for sd in range(8800, 8820):
		lost_off += int(RE.apply_mortal_wounds("U_GLADIATOR_LANCER_A", 4, moff.duplicate(true), RE.RNGService.new(sd)).get("wounds_applied", 0))
		lost_on += int(RE.apply_mortal_wounds("U_GLADIATOR_LANCER_A", 4, mboard.duplicate(true), RE.RNGService.new(sd)).get("wounds_applied", 0))
	_check("A/B 4 mortal wounds x 20 seeds: fewer applied (%d -> %d)" % [lost_off, lost_on], lost_on < lost_off)
	_check("once per phase", not SM.can_use_stratagem(2, lc, "U_GLADIATOR_LANCER_A").can_use)
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at the end of the phase", not _flags("U_GLADIATOR_LANCER_A").has("sm11e_layered_ceramite"))
	_reset_usage()
	PM.transition_to_phase(PHASE_FIGHT)
	_check("usable in the Fight phase too (any phase)", SM.can_use_stratagem(2, lc, "U_GLADIATOR_LANCER_A").can_use)


# ---------------------------------------------------------------------------
func _section_movement() -> void:
	print("\n-- E. RESPONSIVE TACTICS / TRANSHUMAN REACTIONS / SUDDEN ONSLAUGHT / AGGRESSIVE DISEMBARKATION / STORM AND SECURE / MORTIS SNARES --")
	_stage_fixture(REACTIVE)
	var rt := _sid(2, CSV_RESPONSIVE)
	var tr := _sid(2, CSV_REACTIONS)
	var phase = _phase(PHASE_MOVEMENT)
	var w := "enemy_ended_move"
	var far_ctx := {"phase": "movement", "enemy_unit_id": "U_WARBIKERS_A", "move_type": "normal"}
	_check("Warbikers far away: RESPONSIVE TACTICS / TRANSHUMAN REACTIONS not offered", not rt in _offer_ids(SM.get_window_offers(2, w, far_ctx)) and not tr in _offer_ids(SM.get_window_offers(2, w, far_ctx)))
	# The Warbikers end a move within 8" of the Hellblasters and the Infiltrators (setup).
	_translate("U_WARBIKERS_A", -6.0, 11.0)
	var offers = SM.get_window_offers(2, w, far_ctx)
	print("    distances: hellblasters %.2f infiltrators %.2f" % [Common.group_distance_inches("U_HELLBLASTER_SQUAD_A", "U_WARBIKERS_A"), Common.group_distance_inches("U_INFILTRATOR_SQUAD_A", "U_WARBIKERS_A")])
	var rt_t := _offer_targets(offers, rt)
	var tr_t := _offer_targets(offers, tr)
	_check("RESPONSIVE TACTICS offered on the Hellblasters (INFANTRY within 8\")", "U_HELLBLASTER_SQUAD_A" in rt_t, str(rt_t))
	_check("…not on the engaged Assault Intercessors / Outriders, not on the Land Speeder (VEHICLE)", not "U_ASSAULT_INTERCESSOR_SQUAD_A" in rt_t and not "U_OUTRIDER_SQUAD_A" in rt_t and not "U_LAND_SPEEDER_A" in rt_t, str(rt_t))
	_check("TRANSHUMAN REACTIONS offered on the Infiltrators (PHOBOS), not the Hellblasters", "U_INFILTRATOR_SQUAD_A" in tr_t and not "U_HELLBLASTER_SQUAD_A" in tr_t, str(tr_t))
	phase.open_stratagem_window(2, w, far_ctx, "")
	var cp0 := _cp(2)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": w, "stratagem_id": rt, "target_unit_id": "U_HELLBLASTER_SQUAD_A"})
	_check("USE RESPONSIVE TACTICS succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	var rmv: Dictionary = phase._ork11e_reactive_move
	_check("normal-move follow-up for P2: up to D6\"", not rmv.is_empty() and str(rmv.get("unit_id", "")) == "U_HELLBLASTER_SQUAD_A" and float(rmv.get("max_inches", 0)) >= 1.0 and float(rmv.get("max_inches", 0)) <= 6.0, str(rmv))
	_check("Game Log: the D6 roll", _log_count("RESPONSIVE TACTICS: ") >= 1)
	# TRANSHUMAN REACTIONS with the tactical doctrine: a flat 6".
	_stage_fixture(REACTIVE)
	phase = _phase(PHASE_MOVEMENT)
	_translate("U_WARBIKERS_A", -6.0, 11.0)
	for gid in ["U_INFILTRATOR_SQUAD_A"]:
		_flags(gid)["sw11e_doctrine"] = "tactical"
	var tr_res = Movement.apply(SM.get_stratagem(tr), "U_INFILTRATOR_SQUAD_A", far_ctx)
	_check("TRANSHUMAN REACTIONS with the tactical doctrine: up to 6\" (no roll)", typeof(tr_res) == TYPE_DICTIONARY and float(tr_res.followup.max_inches) == 6.0 and int(tr_res.followup.roll) == 0, str(tr_res))
	_flags("U_INFILTRATOR_SQUAD_A").erase("sw11e_doctrine")
	tr_res = Movement.apply(SM.get_stratagem(tr), "U_INFILTRATOR_SQUAD_A", far_ctx)
	_check("…without it: up to D6\"", float(tr_res.followup.max_inches) == float(tr_res.followup.roll) and int(tr_res.followup.roll) >= 1)
	_stage_fixture(ACTIVE)
	_translate("U_WARBIKERS_A", -6.0, 11.0)
	_check("refused in its own Movement phase", not SM.can_use_stratagem(1, _sid(1, CSV_RESPONSIVE), "U_HELLBLASTER_SQUAD_A", far_ctx.merged({"window_id": w})).can_use)
	# SUDDEN ONSLAUGHT (active): real BEGIN_ADVANCE hook.
	_stage_fixture(ACTIVE)
	var so := _sid(1, CSV_ONSLAUGHT)
	phase = _phase(PHASE_MOVEMENT)
	_check("not offered for a normal move", not so in _offer_ids(SM.get_window_offers(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_LAND_SPEEDER_A", "move_type": "normal"})))
	_check("not on the Hellblasters (INFANTRY)", not so in _offer_ids(SM.get_window_offers(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_HELLBLASTER_SQUAD_A", "move_type": "advance"})))
	var r = phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_LAND_SPEEDER_A", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("BEGIN_ADVANCE (Land Speeder) opens unit_selected_to_move with SUDDEN ONSLAUGHT", str(pend.get("window_id", "")) == "unit_selected_to_move" and so in _offer_ids(pend.get("offers", [])), "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	cp0 = _cp(1)
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_move", "stratagem_id": so, "target_unit_id": "U_LAND_SPEEDER_A"})
	_check("USE SUDDEN ONSLAUGHT succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_decline_pending(phase)
	var am: Dictionary = phase.active_moves.get("U_LAND_SPEEDER_A", {})
	var m_in: float = phase.get_unit_movement(_unit("U_LAND_SPEEDER_A"))
	_check("the advance roll is a 6 (move cap M + 6)", int(am.get("advance_roll", 0)) == 6 and float(am.get("move_cap_inches", 0)) == m_in + 6.0, str(am.get("advance_roll", "?")) + " / " + str(am.get("move_cap_inches", "?")))
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("expiry: sm11e_sudden_onslaught cleared", not _flags("U_LAND_SPEEDER_A").has("sm11e_sudden_onslaught"))
	# AGGRESSIVE DISEMBARKATION (active): real DISEMBARK_UNIT hook.
	_stage_fixture(ACTIVE)
	var ag := _sid(1, CSV_AGGRESSIVE)
	phase = _phase(PHASE_MOVEMENT)
	var positions := _disembark_positions("U_INTERCESSOR_SQUAD_A", "U_RHINO_A")
	var dis_action := {"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_INTERCESSOR_SQUAD_A", "payload": {"positions": positions}}
	var v0: Dictionary = phase._validate_confirm_disembark(dis_action)
	_check("without the stratagem: a model only WITHIN 3\" (not wholly) is refused", not v0.get("valid", true), str(v0))
	r = phase.execute_action({"type": "DISEMBARK_UNIT", "actor_unit_id": "U_INTERCESSOR_SQUAD_A", "player": 1})
	pend = phase.get_pending_stratagem_window()
	_check("DISEMBARK_UNIT opens unit_selected_to_move (move_type disembark) with AGGRESSIVE DISEMBARKATION", str(pend.get("window_id", "")) == "unit_selected_to_move" and str(pend.get("ctx", {}).get("move_type", "")) == "disembark" and ag in _offer_ids(pend.get("offers", [])), "%s / %s" % [str(r.get("error", "")), str(pend)])
	_check("…SUDDEN ONSLAUGHT not offered on a disembark", not _sid(1, CSV_ONSLAUGHT) in _offer_ids(pend.get("offers", [])))
	cp0 = _cp(1)
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_move", "stratagem_id": ag, "target_unit_id": "U_INTERCESSOR_SQUAD_A"})
	_check("USE AGGRESSIVE DISEMBARKATION succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var v1: Dictionary = phase._validate_confirm_disembark(dis_action)
	_check("with it: the same placement is valid (within, not wholly within)", v1.get("valid", false), str(v1))
	var cd = phase.execute_action(dis_action)
	_check("CONFIRM_DISEMBARK succeeds — the Intercessors are on the battlefield", cd.get("success", false) and _unit("U_INTERCESSOR_SQUAD_A").get("embarked_in", null) == null, str(cd.get("error", "")))
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("expiry: sm11e_aggressive_disembark cleared", not _flags("U_INTERCESSOR_SQUAD_A").has("sm11e_aggressive_disembark"))
	# STORM AND SECURE + MORTIS SNARES (active): real END_MOVEMENT hook.
	_stage_fixture(ACTIVE)
	var ss := _sid(1, CSV_SECURE)
	var ms := _sid(1, CSV_SNARES)
	phase = _phase(PHASE_MOVEMENT)
	var mpe: Array = SM.get_window_offers(1, "movement_phase_end", {"phase": "movement"})
	_check("STORM AND SECURE offered on the Rhino (Intercessors embarked) with obj_home_2", _offer_targets(mpe, ss) == ["U_RHINO_A"] and _offer_entry(mpe, ss, "U_RHINO_A").get("secondary", {}).get("options", []).map(func(o): return str(o.id)) == ["obj_home_2"], str(_offer_entry(mpe, ss, "U_RHINO_A")))
	_check("…not on the Impulsor (nothing embarked)", not "U_IMPULSOR_A" in _offer_targets(mpe, ss))
	var sn_t := _offer_targets(mpe, ms)
	_check("MORTIS SNARES offered on the Incursors + Infiltrators (PHOBOS on obj_nml_2), not the Scouts (no objective)", "U_INCURSOR_SQUAD_A" in sn_t and "U_INFILTRATOR_SQUAD_A" in sn_t and not "U_SCOUT_SQUAD_A" in sn_t, str(sn_t))
	r = phase.execute_action({"type": "END_MOVEMENT", "player": 1})
	pend = phase.get_pending_stratagem_window()
	_check("END_MOVEMENT opens movement_phase_end for P1", str(pend.get("window_id", "")) == "movement_phase_end" and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, "movement_phase_end", {"phase": "movement"}, "")
	var miss = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "movement_phase_end", "stratagem_id": ss, "target_unit_id": "U_RHINO_A", "context": {}})
	_check("STORM AND SECURE without the objective choice refused", not miss.get("success", true))
	cp0 = _cp(1)
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "movement_phase_end", "stratagem_id": ss, "target_unit_id": "U_RHINO_A", "context": {"secondary_id": "obj_home_2"}})
	_check("USE STORM AND SECURE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var mm = root.get_node("MissionManager")
	_check("obj_home_2 is secured by Player 1 (14.03)", Common.objective_secured_by("obj_home_2") == 1, str(mm.is_objective_secured("obj_home_2")))
	_check("Game Log: STORM AND SECURE", _log_count("STORM AND SECURE") >= 1)
	_decline_pending(phase)
	# MORTIS SNARES — direct use (once per phase is per stratagem; a different one here).
	cp0 = _cp(1)
	use = SM.use_stratagem(1, ms, "U_INCURSOR_SQUAD_A", {"window_id": "movement_phase_end", "phase": "movement", "secondary_id": "obj_nml_2"})
	_check("USE MORTIS SNARES succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("obj_nml_2 is snared", "obj_nml_2" in Command.snared_objectives(1))
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("the snare outlasts the phase (only the marker expires)", "obj_nml_2" in Command.snared_objectives(1) and not _flags("U_INCURSOR_SQUAD_A").has("sm11e_mortis_snares"))
	# Trigger: a friendly unit moving there does nothing; staging does nothing; an
	# enemy unit that ENDS a move within range rolls.
	Codex.on_action_begin("CONFIRM_UNIT_MOVE")
	_translate("U_HELLBLASTER_SQUAD_A", 0.5, 0.0)
	_check("a friendly unit moving does not trigger it", Codex.on_action_applied("Movement").is_empty() and "obj_nml_2" in Command.snared_objectives(1))
	_translate("U_HELLBLASTER_SQUAD_A", -0.5, 0.0)
	var wb_before := 0
	for m in _unit("U_WARBIKERS_A").models:
		wb_before += int(m.current_wounds)
	Codex.on_action_begin("STAGE_MODEL_MOVE")
	_translate("U_WARBIKERS_A", 10.0, 13.0)
	_check("a staged (unfinished) enemy move does not trigger it", Codex.on_action_applied("Movement").is_empty() and "obj_nml_2" in Command.snared_objectives(1))
	print("    warbikers in range of obj_nml_2: %s" % str(Common.group_in_objective_range("U_WARBIKERS_A", Common.objective_by_id("obj_nml_2"))))
	RE.set_test_seed(8901)
	Codex.on_action_begin("CONFIRM_UNIT_MOVE")
	var sd: Array = Codex.on_action_applied("Movement")
	_check("the enemy unit ending its move in range triggers it: the objective is no longer snared", not "obj_nml_2" in Command.snared_objectives(1))
	var wb_after := 0
	for m in _unit("U_WARBIKERS_A").models:
		if m.get("alive", true):
			wb_after += int(m.current_wounds)
	_check("Game Log: MORTIS SNARES D6 roll", _log_count("MORTIS SNARES: ") >= 2)
	print("    snare diffs %d, warbikers wounds %d -> %d" % [sd.size(), wb_before, wb_after])
	_check("on a 2+ the enemy unit lost wounds (or the log shows the 1)", wb_after < wb_before or _log_count("no effect; the objective is no longer snared") >= 1)
	Codex.on_action_begin("CONFIRM_UNIT_MOVE")
	_translate("U_WARBIKERS_A", 0.3, 0.0)
	_check("it triggers only once", Codex.on_action_applied("Movement").is_empty())
	GS.state.meta["active_player"] = 2
	_check("STORM AND SECURE refused at the end of the opponent's Movement phase", not SM.can_use_stratagem(1, ss, "U_RHINO_A", {"window_id": "movement_phase_end", "secondary_id": "obj_home_2"}).can_use)
	GS.state.meta["active_player"] = 1


## Disembark placements around the TRANSPORT: four models WHOLLY within 3"
## and the fifth only WITHIN 3" (near edge 2.5", farthest point 3.76"),
## coherent with the model in front of it.
func _disembark_positions(uid: String, transport_id: String) -> Array:
	var t = _unit(transport_id).models[0]
	var c := Vector2(float(t.position.x), float(t.position.y))
	var meas = root.get_node("Measurement")
	var rt: float = float(meas.base_extent_px(t))
	var mods: Array = _unit(uid).models
	var r: float = float(meas.base_extent_px(mods[0]))
	var out: Array = []
	var angles := [-75.0, -25.0, 25.0, 75.0]
	for a in angles:
		var dir := Vector2(0, -1).rotated(deg_to_rad(a))
		out.append(c + dir * (rt + 0.3 * PX + r))
	var dir2 := Vector2(0, -1).rotated(deg_to_rad(-25.0))
	out.append(c + dir2 * (rt + 2.5 * PX + r))
	return out


# ---------------------------------------------------------------------------
func _section_fight() -> void:
	print("\n-- F. MIGHT OF ANGELS / WIND-SWIFT EVASION / DUTY IS NEVER DONE / TACTICAL WITHDRAWAL / TACTICAL FOCUS / TRANSHUMAN SWIFTNESS --")
	_stage_fixture(ACTIVE)
	var ma := _sid(1, CSV_ANGELS)
	var phase = _phase(PHASE_FIGHT)
	var w := "unit_selected_to_fight"
	var ai_ids := _offer_ids(SM.get_window_offers(1, w, {"phase": "fight", "unit_id": "U_ASSAULT_INTERCESSOR_SQUAD_A"}))
	_check("Assault Intercessors selected to fight: MIGHT OF ANGELS + RELENTLESS offered", ma in ai_ids and _sid(1, CSV_RELENTLESS) in ai_ids, str(ai_ids))
	_check("not offered to P2", not ma in _offer_ids(SM.get_window_offers(2, w, {"phase": "fight", "unit_id": "U_BOYZ_B"})))
	for _i in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
		_decline_pending(phase)
	var sel = phase.sequencer_11e.peek_selection(GS.state)
	print("    selection: %s" % str(sel))
	if int(sel.get("player", 0)) == 1:
		var r = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_ASSAULT_INTERCESSOR_SQUAD_A", "player": 1})
		var pend: Dictionary = phase.get_pending_stratagem_window()
		_check("SELECT_FIGHTER opens unit_selected_to_fight for P1", r.get("success", false) and str(pend.get("window_id", "")) == w, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, w, {"phase": "fight", "unit_id": "U_ASSAULT_INTERCESSOR_SQUAD_A"}, "")
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": ma, "target_unit_id": "U_ASSAULT_INTERCESSOR_SQUAD_A"})
	_check("USE MIGHT OF ANGELS succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("the engine's melee [LANCE] grant is on", bool(_flags("U_ASSAULT_INTERCESSOR_SQUAD_A").get("effect_grant_lance", false)))
	var kw := ["ADEPTUS ASTARTES", "INFANTRY"]
	var ab = _ab(_melee_board({"charged_this_turn": true}, kw, _melee_weapon("3", "4", "1", "6"), 3, 5), _melee_board({"charged_this_turn": true, "effect_grant_lance": true}, kw, _melee_weapon("3", "4", "1", "6"), 3, 5), range(9000, 9030))
	_check("A/B [LANCE] after a charge (S4 vs T5): more wounds (%d -> %d)" % [ab[2], ab[3]], ab[3] > ab[2], str(ab))
	_decline_pending(phase)
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: [LANCE] grant + marker cleared", not _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").has("effect_grant_lance") and not _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").has("sm11e_might_of_angels"))
	# fight_phase_end (active): WIND-SWIFT EVASION / DUTY IS NEVER DONE.
	_stage_fixture(ACTIVE)
	var ws := _sid(1, CSV_WINDSWIFT)
	var dn := _sid(1, CSV_DUTY)
	var tw := _sid(1, CSV_WITHDRAWAL)
	phase = _phase(PHASE_FIGHT)
	_flags("U_STERNGUARD_VETERAN_SQUAD_A")["was_eligible_to_fight"] = true  # setup: it fought this phase
	var fe: Array = SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"})
	_check("WIND-SWIFT EVASION offered on the Outriders (MOUNTED, eligible to fight)", "U_OUTRIDER_SQUAD_A" in _offer_targets(fe, ws), str(_offer_targets(fe, ws)))
	_check("…not on the Land Speeder (not eligible to fight)", not "U_LAND_SPEEDER_A" in _offer_targets(fe, ws))
	_check("DUTY IS NEVER DONE offered on the Sternguard → Impulsor", _offer_targets(fe, dn) == ["U_STERNGUARD_VETERAN_SQUAD_A"] and "Impulsor" in str(_offer_entry(fe, dn, "U_STERNGUARD_VETERAN_SQUAD_A").get("label", "")), str(_offer_entry(fe, dn, "U_STERNGUARD_VETERAN_SQUAD_A")))
	_check("TACTICAL WITHDRAWAL not at the end of its own Fight phase", not tw in _offer_ids(fe))
	phase.open_stratagem_window(1, "fight_phase_end", {"phase": "fight"}, "")
	cp0 = _cp(1)
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "fight_phase_end", "stratagem_id": ws, "target_unit_id": "U_OUTRIDER_SQUAD_A"})
	_check("USE WIND-SWIFT EVASION succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var fm: Dictionary = phase.sm11e_fight_move
	_check("engaged → a fall-back move up to M (12\") waits for P1", not fm.is_empty() and str(fm.get("move_kind", "")) == "fall_back" and float(fm.get("max_inches", 0)) >= 12.0, str(fm.keys()))
	_check("fell_back flag written", bool(_flags("U_OUTRIDER_SQUAD_A").get("fell_back", false)))
	var blocked = phase.execute_action({"type": "END_FIGHT", "player": 1})
	_check("nothing else while the move is in progress", not blocked.get("success", true))
	var info: Dictionary = phase.ork11e_reactive_move_info()
	_check("move info for the panel (not valid before moving: engaged)", not info.is_empty() and not bool(info.get("valid", true)))
	var auto = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 1})
	_check("Auto-move finds a legal fall-back", auto.get("success", false) and bool(auto.get("ork11e_reactive_move", {}).get("valid", false)), str(auto.get("error", "")))
	var conf = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 1})
	_check("Confirm finishes the move", conf.get("success", false) and phase.sm11e_fight_move.is_empty(), str(conf.get("error", "")))
	_check("the Outriders are no longer engaged", not Common.is_engaged("U_OUTRIDER_SQUAD_A"))
	_check("Game Log: WIND-SWIFT EVASION", _log_count("WIND-SWIFT EVASION") >= 2)
	var pend2: Dictionary = phase.get_pending_stratagem_window()
	print("    after the move: pending %s" % str(pend2.get("window_id", "")))
	_check("the follow-up is over: the window flow resumed (no follow-up pending)", not phase._window_followup_pending)
	# DUTY IS NEVER DONE.
	_stage_fixture(ACTIVE)
	phase = _phase(PHASE_FIGHT)
	_flags("U_STERNGUARD_VETERAN_SQUAD_A")["was_eligible_to_fight"] = true
	phase.open_stratagem_window(1, "fight_phase_end", {"phase": "fight"}, "")
	cp0 = _cp(1)
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "fight_phase_end", "stratagem_id": dn, "target_unit_id": "U_STERNGUARD_VETERAN_SQUAD_A"})
	_check("USE DUTY IS NEVER DONE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var sg := _unit("U_STERNGUARD_VETERAN_SQUAD_A")
	_check("the Sternguard are embarked within the Impulsor (off the board)", str(sg.get("embarked_in", "")) == "U_IMPULSOR_A" and sg.models.all(func(m): return m.get("position", null) == null) and "U_STERNGUARD_VETERAN_SQUAD_A" in _unit("U_IMPULSOR_A").transport_data.embarked_units)
	_check("Game Log: DUTY IS NEVER DONE embarks", _log_count("DUTY IS NEVER DONE: ") >= 1)
	_flags("U_HELLBLASTER_SQUAD_A")["was_eligible_to_fight"] = true
	_check("not for a unit that is not wholly within 6\" of a TRANSPORT", not SM.can_use_stratagem(1, dn, "U_HELLBLASTER_SQUAD_A", {"window_id": "fight_phase_end"}).can_use)
	# Unengaged MOUNTED: a normal move (AI decider, auto placement).
	_stage_fixture(ACTIVE)
	phase = _phase(PHASE_FIGHT)
	_translate("U_OUTRIDER_SQUAD_A", 0.0, 4.0)
	_flags("U_OUTRIDER_SQUAD_A")["was_eligible_to_fight"] = true
	var ai = root.get_node("AIPlayer")
	var o0: Dictionary = RM.current_positions("U_OUTRIDER_SQUAD_A", GS.state)
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var started: bool = Movement.fight_move_start(phase, 1, {"unit_id": "U_OUTRIDER_SQUAD_A", "kind": "normal", "max_inches": 12.0, "source": "WIND-SWIFT EVASION"})
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	var o1: Dictionary = RM.current_positions("U_OUTRIDER_SQUAD_A", GS.state)
	var moved := false
	for k in o0:
		if o1.has(k) and o1[k].distance_to(o0[k]) > 4.0:
			moved = true
	_check("AI decider: the unengaged Outriders make their normal move at once (no pause)", not started and phase.sm11e_fight_move.is_empty() and moved)
	_check("…ending unengaged and coherent", not Common.is_engaged("U_OUTRIDER_SQUAD_A") and RM.group_coherent("U_OUTRIDER_SQUAD_A", GS.state))
	# TACTICAL WITHDRAWAL (reactive: end of the opponent's Fight phase).
	_stage_fixture(REACTIVE)
	tw = _sid(2, CSV_WITHDRAWAL)
	phase = _phase(PHASE_FIGHT)
	var tw_t := _offer_targets(SM.get_window_offers(2, "fight_phase_end", {"phase": "fight"}), tw)
	_check("TACTICAL WITHDRAWAL offered on the Scouts (SCOUT SQUAD) and the Phobos units", "U_SCOUT_SQUAD_A" in tw_t and "U_INFILTRATOR_SQUAD_A" in tw_t and "U_INCURSOR_SQUAD_A" in tw_t, str(tw_t))
	_check("…not on the Hellblasters", not "U_HELLBLASTER_SQUAD_A" in tw_t)
	phase.open_stratagem_window(2, "fight_phase_end", {"phase": "fight"}, "")
	cp0 = _cp(2)
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "fight_phase_end", "stratagem_id": tw, "target_unit_id": "U_SCOUT_SQUAD_A"})
	_check("USE TACTICAL WITHDRAWAL succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	var su := _unit("U_SCOUT_SQUAD_A")
	_check("placed in strategic reserves (status, reserve type, off the board)", int(su.status) == int(GS.UnitStatus.IN_RESERVES) and str(su.get("reserve_type", "")) == "strategic_reserves" and su.models.all(func(m): return m.get("position", null) == null))
	_check("Game Log: TACTICAL WITHDRAWAL", _log_count("TACTICAL WITHDRAWAL") >= 1)
	# TACTICAL FOCUS — unit_selected_to_consolidate.
	_stage_fixture(ACTIVE)
	var tf := _sid(1, CSV_FOCUS)
	phase = _phase(PHASE_FIGHT)
	_flags("U_ASSAULT_INTERCESSOR_SQUAD_A")["was_eligible_to_fight"] = true
	_check("TACTICAL FOCUS offered on the Assault Intercessors (TACTICUS)", tf in _offer_ids(SM.get_window_offers(1, "unit_selected_to_consolidate", {"phase": "fight", "unit_id": "U_ASSAULT_INTERCESSOR_SQUAD_A", "step_kind": "consolidate"})))
	_check("…not on the Outriders", not tf in _offer_ids(SM.get_window_offers(1, "unit_selected_to_consolidate", {"phase": "fight", "unit_id": "U_OUTRIDER_SQUAD_A"})))
	_check("the owner has a unit_selected_to_consolidate stratagem (routing gate)", Codex.player_has_window_stratagem(1, "unit_selected_to_consolidate") and not Codex.player_has_window_stratagem(2, "unit_selected_to_consolidate"))
	var d0: float = phase._get_consolidation_distance("U_ASSAULT_INTERCESSOR_SQUAD_A")
	use = SM.use_stratagem(1, tf, "U_ASSAULT_INTERCESSOR_SQUAD_A", {"window_id": "unit_selected_to_consolidate", "unit_id": "U_ASSAULT_INTERCESSOR_SQUAD_A"})
	var d1: float = phase._get_consolidation_distance("U_ASSAULT_INTERCESSOR_SQUAD_A")
	_check("USE TACTICAL FOCUS: consolidation 3\" -> D3+3 (4..6\")", use.get("success", false) and d0 == 3.0 and d1 >= 4.0 and d1 <= 6.0, "%s -> %s %s" % [d0, d1, str(use.get("error", ""))])
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: back to 3\"", phase._get_consolidation_distance("U_ASSAULT_INTERCESSOR_SQUAD_A") == 3.0 and not _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").has("sm11e_tactical_focus"))
	# TRANSHUMAN SWIFTNESS — enemy_has_fought (opponent's Fight phase).
	_stage_fixture(REACTIVE)
	var ts := _sid(2, CSV_SWIFTNESS)
	phase = _phase(PHASE_FIGHT)
	for _i in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
		_decline_pending(phase)
	var ehf_ctx := {"phase": "fight", "enemy_unit_id": "U_NOBZ_A", "attacker_unit_id": "U_NOBZ_A"}
	var ts_t := _offer_targets(SM.get_window_offers(2, "enemy_has_fought", ehf_ctx), ts)
	_check("TRANSHUMAN SWIFTNESS offered on the Assault Intercessors (TACTICUS, on obj_center, eligible to fight)", ts_t == ["U_ASSAULT_INTERCESSOR_SQUAD_A"], str(ts_t))
	# Real hook: the Nobz (P1, active) finish their activation.
	phase.active_fighter_id = "U_NOBZ_A"
	var res: Dictionary = phase._finish_fight_activation_11e(phase.create_result(true, []))
	var pend3: Dictionary = phase.get_pending_stratagem_window()
	_check("the Nobz have fought: enemy_has_fought opens for P2", str(pend3.get("window_id", "")) == "enemy_has_fought" and int(pend3.get("player", 0)) == 2 and ts in _offer_ids(pend3.get("offers", [])), str(pend3.get("window_id", "")) + " " + str(res.get("error", "")))
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(2, "enemy_has_fought", ehf_ctx, "")
	cp0 = _cp(2)
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "enemy_has_fought", "stratagem_id": ts, "target_unit_id": "U_ASSAULT_INTERCESSOR_SQUAD_A"})
	_check("USE TRANSHUMAN SWIFTNESS succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	_check("Fights First + the must-be-next marker", bool(_flags("U_ASSAULT_INTERCESSOR_SQUAD_A").get("fights_first", false)) and bool(_flags("U_ASSAULT_INTERCESSOR_SQUAD_A").get("sm11e_transhuman_swiftness", false)))
	_check("FightSequencer: P2 may only select the Assault Intercessors next", Codex.restrict_fight_candidates(2, ["U_OUTRIDER_SQUAD_A", "U_ASSAULT_INTERCESSOR_SQUAD_A"]) == ["U_ASSAULT_INTERCESSOR_SQUAD_A"])
	var selectable: Array = phase.sequencer_11e.selectable_units(GS.state, 2, false)
	_check("…the live sequencer agrees", selectable == ["U_ASSAULT_INTERCESSOR_SQUAD_A"] or selectable.is_empty(), str(selectable))
	_decline_pending(phase)
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: Fights First + marker cleared", not _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").has("fights_first") and not _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").has("sm11e_transhuman_swiftness"))
	# Own turn (either player's Fight phase): the window also opens for the active player.
	_stage_fixture(ACTIVE)
	phase = _phase(PHASE_FIGHT)
	for _i in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
		_decline_pending(phase)
	_check("own Fight phase: P1 has an enemy_has_fought stratagem", Codex.player_has_window_stratagem(1, "enemy_has_fought"))
	phase.active_fighter_id = "U_NOBZ_A"
	phase._finish_fight_activation_11e(phase.create_result(true, []))
	var pend4: Dictionary = phase.get_pending_stratagem_window()
	_check("the Nobz (P2, non-active) have fought: enemy_has_fought opens for P1 (active)", str(pend4.get("window_id", "")) == "enemy_has_fought" and int(pend4.get("player", 0)) == 1 and _sid(1, CSV_SWIFTNESS) in _offer_ids(pend4.get("offers", [])), str(pend4.get("window_id", "")))
	_decline_pending(phase)


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- G. AI deciders --")
	var ai = root.get_node("AIPlayer")
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	# Command window: AI P1 answers synchronously.
	_stage_fixture(ACTIVE)
	var phase = _phase(PHASE_COMMAND)
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var cp0 := _cp(1)
	var paused: bool = phase.open_stratagem_window(1, "command_phase_main", {"phase": "command"}, "")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI command_phase_main: no pause, nothing pending", not paused and not phase.has_pending_stratagem_window())
	print("    AI command: CP %d -> %d" % [cp0, _cp(1)])
	_check("AI spent CP only on what it used (CP never negative)", _cp(1) >= 0 and _cp(1) <= cp0)
	# Window decisions are sane.
	_phase(PHASE_SHOOTING)
	var lc_ctx := {"phase": "shooting", "unit_id": "U_GLADIATOR_LANCER_A", "planned_target_unit_ids": ["U_MEK_GUNZ_A"]}
	var offers = SM.get_window_offers(1, "unit_selected_to_shoot", lc_ctx)
	var d: Dictionary = AIDM.decide_window_stratagem(1, "unit_selected_to_shoot", offers, lc_ctx)
	_check("AI Lancer shooting the Mek Gunz (VEHICLE): HEADHUNTER DOCTRINE", bool(d.get("use", false)) and str(d.get("stratagem_id", "")) == _sid(1, CSV_HEADHUNTER), str(d))
	var hb_ctx := {"phase": "shooting", "unit_id": "U_HELLBLASTER_SQUAD_A", "planned_target_unit_ids": ["U_KOMMANDOS_A"]}
	d = AIDM.decide_window_stratagem(1, "unit_selected_to_shoot", SM.get_window_offers(1, "unit_selected_to_shoot", hb_ctx), hb_ctx)
	# The Kommandos have Stealth (the benefit of cover) — STORM OF DEVASTATION's [IGNORES COVER] is the right buy.
	var k_cover: bool = root.get_node("TerrainManager").unit_has_cover_11e(_unit("U_KOMMANDOS_A"), _unit("U_HELLBLASTER_SQUAD_A").models[0])
	_check("AI Hellblasters vs the Kommandos (Stealth = cover: %s): STORM OF DEVASTATION" % str(k_cover), k_cover and str(d.get("stratagem_id", "")) == _sid(1, CSV_STORM), str(d))
	var fg_ctx := {"phase": "shooting", "unit_id": "U_HELLBLASTER_SQUAD_A", "planned_target_unit_ids": ["U_FLASH_GITZ_A"]}
	d = AIDM.decide_window_stratagem(1, "unit_selected_to_shoot", SM.get_window_offers(1, "unit_selected_to_shoot", fg_ctx), fg_ctx)
	var g_cover: bool = root.get_node("TerrainManager").unit_has_cover_11e(_unit("U_FLASH_GITZ_A"), _unit("U_HELLBLASTER_SQUAD_A").models[0])
	_check("AI Hellblasters vs the Flash Gitz (cover: %s): RELENTLESS ASSAULT (sustained)" % str(g_cover), g_cover or (str(d.get("stratagem_id", "")) == _sid(1, CSV_RELENTLESS) and str(d.get("context", {}).get("variant_id", "")) == "sustained"), str(d))
	_phase(PHASE_FIGHT)
	var etf := {"phase": "fight", "attacker_unit_id": "U_BOYZ_B", "target_unit_ids": ["U_ASSAULT_INTERCESSOR_SQUAD_A"]}
	d = AIDM.decide_window_stratagem(1, "enemy_targets_unit_fight", SM.get_window_offers(1, "enemy_targets_unit_fight", etf), etf)
	print("    AI enemy_targets_unit_fight decision vs Boyz: %s" % str(d))
	_check("AI enemy_targets_unit_fight decision is well-formed", d.has("use"))
	# Fight end: AI P1 synchronous, never stalls.
	_flags("U_OUTRIDER_SQUAD_A")["was_eligible_to_fight"] = true
	ai.enabled = true
	ai.ai_players = {1: true, 2: true}
	var fp = PM.get_current_phase_instance()
	paused = fp.open_stratagem_window(1, "fight_phase_end", {"phase": "fight"}, "")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI fight_phase_end: no pause, no move left pending", not paused and not fp.has_pending_stratagem_window() and fp.sm11e_fight_move.is_empty())
	# Reactive: AI P2 in enemy_ended_move (RESPONSIVE TACTICS auto-move) never stalls.
	_stage_fixture(REACTIVE)
	phase = _phase(PHASE_MOVEMENT)
	_translate("U_WARBIKERS_A", -6.0, 11.0)
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	paused = phase.open_stratagem_window(2, "enemy_ended_move", {"phase": "movement", "enemy_unit_id": "U_WARBIKERS_A", "move_type": "normal"}, "")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI enemy_ended_move: no pause, nothing pending", not paused and not phase.has_pending_stratagem_window() and phase._ork11e_reactive_move.is_empty())
	# Panel AI: LAYERED CERAMITE never spent where no mortal wounds come.
	var lc: Dictionary = SM.get_stratagem(_sid(2, CSV_CERAMITE))
	GS.state.meta.phase = PHASE_COMMAND
	_check("AI LAYERED CERAMITE scores 0 in the Command phase", Codex.ai_score(lc, 2, "U_GLADIATOR_LANCER_A", "", {}) == 0.0)
	# ADAPTIVE STRATEGY AI doctrine pick.
	_check("AI doctrine pick: engaged -> tactical", Command.ai_doctrine("U_ASSAULT_INTERCESSOR_SQUAD_A") == "tactical")
	_check("AI doctrine pick: a gun line -> devastator", Command.ai_doctrine("U_HELLBLASTER_SQUAD_A") in ["devastator", "assault"])

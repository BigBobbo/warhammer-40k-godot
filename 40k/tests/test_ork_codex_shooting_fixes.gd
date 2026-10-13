extends SceneTree

# Codex: Orks (11e) — regression checks for the verified SHOOTING-cluster
# defects (verification run on claude/bold-pasteur-45wgjz @ ff89f1a). Each
# section names the finding key it pins.
#
#   A. framework:F7   held atomic SHOOT resumed inside the window action still
#                      opens the post-shot windows (enemy_has_shot)
#   B. framework:F12 / r4:WS-3 / r5:F4  kill hook: once per unit, credited to the
#                      OPPONENT of the destroyed unit's owner
#   C. framework:F9 / r4:WS-3  GUN-CRAZY SHOW-OFFS shot-back: attribution
#                      (enemy_unit_has_attacked -> INFESTED WAR ZONE) + kill credit
#   D. r4:WS-1 / r4:WS-7  GRAB IT on terrain-hosted objectives; AI score honours
#                      the auto-move and the charge-lock cost
#   E. r4:WS-2  Hunter profiles + [CLOSE-QUARTERS] either/or (24.07)
#   F. r4:WS-4  DRIVE-BY BUSTIN' offered only when a Firing Deck weapon can fire
#   G. r4:WS-6  11e AP sign: every "+N AP" worsens the save; worsen-AP reduces it
#   H. r1:WH-3  RAPID FIRE half range measured to the whole Attached target
#   I. r3:F2 / r3:F3  surge target + GROT SHIELDS distance use the whole Attached unit
#   J. r3:F6 / r3:F8 / r5:F10 / live:LIVE-6  log lines + display helpers
#   K. live:LIVE-7  GOADED INTO ACTION on an out-of-coherency unit
#   L. r5:F8  SPEEDIEST FREEKS AI score follows the attacker's BS / TORRENT
#   M. r5:F7 / r5:F6 / r5:F9  re-roll a dice at most once; re-roll decision
#                      uses modifiers and fail bands
#
# Usage: godot --headless --path 40k --script tests/test_ork_codex_shooting_fixes.gd

const PHASE_COMMAND := 6
const PHASE_SHOOTING := 8
const PX := 40.0

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var MM = null
var RM = null
var G_SHOOT = null
var G_REACT = null
var _window_events: Array = []


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


func _on_window_opened(player: int, window_id: String, offers: Array, ctx: Dictionary) -> void:
	_window_events.append({"player": player, "window_id": window_id,
		"offers": offers.map(func(o): return str(o.get("name", ""))), "ctx": ctx})


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _load(fixture: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok: bool = slm.load_game(fixture)
	GameConstants.edition = 11
	_ai_off()
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	return ok


func _ai_off() -> void:
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}


func _set_det(player: int, det: String) -> void:
	GS.state.factions[str(player)]["detachment"] = det
	SM.load_faction_stratagems_for_player(player)


func _sid(player: int, csv: String) -> String:
	for s in SM.get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) == csv:
			return str(s.id)
	return ""


func _shooting():
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_SHOOTING)
	var ph = PM.get_current_phase_instance()
	if ph and not ph.stratagem_window_opened.is_connected(_on_window_opened):
		ph.stratagem_window_opened.connect(_on_window_opened)
	return ph


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _alive(uid: String) -> int:
	var n := 0
	for m in _unit(uid).get("models", []):
		if m.get("alive", true):
			n += 1
	return n


func _wounds(uid: String) -> int:
	var n := 0
	for m in _unit(uid).get("models", []):
		if m.get("alive", true):
			n += int(m.get("current_wounds", m.get("wounds", 1)))
	return n


func _kill(uid: String, n: int) -> void:
	var killed := 0
	for m in _unit(uid).get("models", []):
		if killed >= n:
			break
		if m.get("alive", true):
			m["alive"] = false
			m["current_wounds"] = 0
			killed += 1


func _translate(uid: String, dx_in: float, dy_in: float) -> void:
	for m in _unit(uid).get("models", []):
		var p = m.get("position", null)
		if p == null:
			continue
		m["position"] = {"x": float(p.x) + dx_in * PX, "y": float(p.y) + dy_in * PX}


func _centroid(uid: String) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for m in _unit(uid).get("models", []):
		if m.get("position", null) == null or not m.get("alive", true):
			continue
		c += Vector2(float(m.position.x), float(m.position.y))
		n += 1
	return c / max(1, n)


func _move_to(uid: String, at: Vector2) -> void:
	var d: Vector2 = (at * PX - _centroid(uid)) / PX
	_translate(uid, d.x, d.y)


func _park(uid: String) -> void:
	# Keep a unit on the board but far from everything (bottom-left corner).
	for m in _unit(uid).get("models", []):
		m["position"] = {"x": 1.0 * PX, "y": 59.0 * PX}


func _pending(ph) -> Dictionary:
	return ph.get_pending_stratagem_window() if ph.has_pending_stratagem_window() else {}


func _offer_names(w: Dictionary) -> Array:
	return w.get("offers", []).map(func(o): return str(o.get("name", "")))


func _ranged_assignments(shooter: String, target: String) -> Array:
	var board: Dictionary = GS.create_snapshot()
	var weapons: Array = RE.get_eligible_targets(shooter, board).get(target, {}).get("weapons_in_range", [])
	var by_weapon := {}
	var uw: Dictionary = RE.get_unit_weapons(shooter, board)
	for mid in uw:
		for wid in uw[mid]:
			if not wid in weapons:
				continue
			if not by_weapon.has(wid):
				by_weapon[wid] = []
			by_weapon[wid].append(mid)
	var out: Array = []
	for wid in by_weapon:
		out.append({"weapon_id": wid, "target_unit_id": target, "model_ids": by_weapon[wid]})
	return out


func _shoot(ph, shooter: String, target: String, seed_val: int = -1) -> Dictionary:
	var payload := {"assignments": _ranged_assignments(shooter, target)}
	if seed_val >= 0:
		payload["rng_seed"] = seed_val
	return ph.execute_action({"type": "SHOOT", "actor_unit_id": shooter, "player": int(_unit(shooter).owner), "payload": payload})


func _log_count(needle: String) -> int:
	# DebugLogger buffers lines; flush so the file holds everything logged so far.
	var dl = root.get_node_or_null("DebugLogger")
	var path := ""
	if dl != null:
		if dl.has_method("_flush_buffer"):
			dl._flush_buffer()
		if dl.has_method("get_real_log_file_path"):
			path = str(dl.get_real_log_file_path())
	if path == "" or not FileAccess.file_exists(path):
		var dir := ProjectSettings.globalize_path("user://logs/")
		var da := DirAccess.open(dir)
		if da == null:
			return -1
		var newest := ""
		for f in da.get_files():
			if f.begins_with("debug_") and f > newest:
				newest = f
		if newest == "":
			return -1
		path = dir + newest
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return -1
	var n := 0
	while not fa.eof_reached():
		if needle in fa.get_line():
			n += 1
	return n


func _dead_diffs(uid: String) -> Array:
	var out: Array = []
	var models: Array = _unit(uid).get("models", [])
	for i in range(models.size()):
		out.append({"op": "set", "path": "units.%s.models.%d.alive" % [uid, i], "value": false})
		out.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [uid, i], "value": 0})
	return out


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	MM = root.get_node("MissionManager")
	RM = load("res://scripts/rules/ReactiveMove11e.gd")
	G_SHOOT = load("res://scripts/stratagems/ork_codex/OrkCodexShooting.gd")
	G_REACT = load("res://scripts/stratagems/ork_codex/OrkCodexShootingReactive.gd")
	var ss = root.get_node_or_null("SettingsService")
	if ss:
		ss.set("auto_allocate_wounds", true)
	GameConstants.edition = 11
	print("\n=== test_ork_codex_shooting_fixes ===")
	_section_a_held_shoot_post_windows()
	_section_b_kill_hook()
	_section_c_gun_crazy_attribution()
	_section_d_grab_it()
	_section_e_hunter_and_close_quarters()
	_section_f_drive_by()
	_section_g_ap_sign()
	_section_h_rapid_fire_attached()
	_section_i_attached_groups()
	_section_j_logs_and_display()
	_section_k_goaded_coherency()
	_section_l_speediest_freeks_ai()
	_section_m_rerolls()


# ---------------------------------------------------------------------------
func _section_a_held_shoot_post_windows() -> void:
	print("\n-- A. framework:F7 held atomic SHOOT -> post-shot windows --")
	_check("fixture loads", _load("ork11e_orks_active"))
	_set_det(1, "War Horde")
	GS.state.factions["2"] = GS.state.factions["1"].duplicate(true)
	_kill("U_CUSTODIAN_GUARD_E", 99)
	_kill("U_CUSTODIAN_GUARD_F", 99)
	GS.state.units["U_BEAST_SNAGGA_BOYZ_A"]["owner"] = 2
	_set_det(2, "Da Big Hunt")
	_move_to("U_TANKBUSTAS_A", Vector2(38, 43))
	_move_to("U_BEAST_SNAGGA_BOYZ_A", Vector2(40, 52))
	var ph = _shooting()
	_window_events.clear()
	var res = _shoot(ph, "U_TANKBUSTAS_A", "U_BEAST_SNAGGA_BOYZ_A", 5)
	_check("SHOOT is held by the human unit_selected_to_shoot window", res.get("success", false) and str(_pending(ph).get("window_id", "")) == "unit_selected_to_shoot",
		str(_pending(ph).get("window_id", "")))
	var w_before := _wounds("U_BEAST_SNAGGA_BOYZ_A")
	_window_events.clear()
	var dec = ph.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_shoot"})
	_check("DECLINE resumes the held SHOOT", dec.get("success", false) and "U_TANKBUSTAS_A" in ph.units_that_shot, str(dec.get("error", "")))
	var lost := _wounds("U_BEAST_SNAGGA_BOYZ_A") < w_before
	var ehs := str(_pending(ph).get("window_id", "")) == "enemy_has_shot"
	for e in _window_events:
		if e.window_id == "enemy_has_shot":
			ehs = true
	_check("Beast Snagga lost wounds to the resumed SHOOT", lost)
	_check("enemy_has_shot (GOADED INTO ACTION for P2) opened after the resumed SHOOT", ehs, str(_window_events))


# ---------------------------------------------------------------------------
func _section_b_kill_hook() -> void:
	print("\n-- B. framework:F12 / r4:WS-3 / r5:F4 kill hook --")
	_check("fixture loads", _load("ork11e_orks_active"))
	var ph = _shooting()
	MM._kills_this_round = {"1": 0, "2": 0}
	# A P2 unit destroyed in P1's turn: credited to P1, once.
	var d1 := _dead_diffs("U_CUSTODIAN_GUARD_E")
	PM.apply_state_changes(d1)
	ph._check_kill_diffs(d1)
	ph._check_kill_diffs(d1)
	_check("enemy unit destroyed -> 1 kill for P1 even when the diffs reach the hook twice",
		int(MM._kills_this_round.get("1", 0)) == 1 and int(MM._kills_this_round.get("2", 0)) == 0, str(MM._kills_this_round))
	# The ACTIVE player's own unit destroyed (out-of-turn attack): credited to P2.
	var d2 := _dead_diffs("U_GRETCHIN_D")
	PM.apply_state_changes(d2)
	ph._check_kill_diffs(d2)
	_check("active player's unit destroyed -> credited to its OPPONENT (P2), not to P1",
		int(MM._kills_this_round.get("2", 0)) == 1 and int(MM._kills_this_round.get("1", 0)) == 1, str(MM._kills_this_round))
	# Deadly Demise is rolled once per destroyed unit.
	var dd_before := _log_count("Deadly Demise detected on destroyed unit Dakkajet")
	var d3 := _dead_diffs("U_DAKKAJET_A")
	PM.apply_state_changes(d3)
	ph._check_kill_diffs(d3)
	ph._check_kill_diffs(d3)
	var dd_after := _log_count("Deadly Demise detected on destroyed unit Dakkajet")
	_check("Deadly Demise rolled ONCE for a unit whose kill diffs arrive twice", dd_after - dd_before == 1, "before %d after %d" % [dd_before, dd_after])
	_check("...and its kill counted once (P2 now 2)", int(MM._kills_this_round.get("2", 0)) == 2, str(MM._kills_this_round))


# ---------------------------------------------------------------------------
func _section_c_gun_crazy_attribution() -> void:
	print("\n-- C. framework:F9 / r4:WS-3 GUN-CRAZY shot-back attribution --")
	_check("fixture loads", _load("ork11e_orks_active"))
	_set_det(1, "Runt Swarm")
	_kill("U_CUSTODIAN_GUARD_E", 99)
	_kill("U_CUSTODIAN_GUARD_F", 99)
	GS.state.factions["2"] = GS.state.factions["1"].duplicate(true)
	GS.state.units["U_TANKBUSTAS_A"]["owner"] = 2
	_set_det(2, "Wreckas")
	var gc := _sid(2, "gun-crazy-show-offs-wreckas")
	_check("GUN-CRAZY SHOW-OFFS loaded for P2", gc != "")
	_move_to("U_TANKBUSTAS_A", Vector2(40, 52))
	_move_to("U_GRETCHIN_D", Vector2(40, 44.5))
	var ph = _shooting()
	RE.set_test_seed(11)
	var res = _shoot(ph, "U_GRETCHIN_D", "U_TANKBUSTAS_A", 3)
	var w := _pending(ph)
	_check("Gretchin D shot the Tankbustas -> enemy_has_shot window for P2", res.get("success", false) and str(w.get("window_id", "")) == "enemy_has_shot" and int(w.get("player", 0)) == 2,
		str(w.get("window_id", "")))
	if str(w.get("window_id", "")) != "enemy_has_shot":
		RE.set_test_seed(-1)
		return
	_kill("U_GRETCHIN_D", _alive("U_GRETCHIN_D") - 1)  # one Gretchin left: the shot-back destroys the unit
	MM._kills_this_round = {"1": 0, "2": 0}
	_window_events.clear()
	var use = ph.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "enemy_has_shot", "stratagem_id": gc, "target_unit_id": "U_TANKBUSTAS_A"})
	_check("USE GUN-CRAZY succeeds", use.get("success", false), str(use.get("error", "")))
	_check("the shot-back destroyed Gretchin D", _alive("U_GRETCHIN_D") == 0)
	var iwz := false
	for e in _window_events:
		if e.window_id == "enemy_unit_has_attacked" and e.player == 1 and "INFESTED WAR ZONE" in e.offers \
				and str(e.ctx.get("attacker_unit_id", "")) == "U_TANKBUSTAS_A":
			iwz = true
	var w2 := _pending(ph)
	if str(w2.get("window_id", "")) == "enemy_unit_has_attacked" and "INFESTED WAR ZONE" in _offer_names(w2):
		iwz = true
	_check("enemy_unit_has_attacked opened for P1 with the Tankbustas as the attacker (INFESTED WAR ZONE offered)", iwz, str(_window_events))
	_check("the kill is credited to P2 (the Ork shooter's owner), not the active P1",
		int(MM._kills_this_round.get("2", 0)) == 1 and int(MM._kills_this_round.get("1", 0)) == 0, str(MM._kills_this_round))
	RE.set_test_seed(-1)
	# An atomic SHOOT names its own attacker: it wins over a unit that is merely
	# selected (the shooting panel auto-selects one at phase entry) — windowed
	# proof: ork11e_infested_war_zone (attacker_unit_id == Custodian Guard F).
	var ph2 = _shooting()
	ph2.active_shooter_id = "U_TANKBUSTAS_A"
	var depth_before: int = ph2._ev_depth
	ph2._ev_depth = 0
	ph2._window_events_begin({"type": "SHOOT", "actor_unit_id": "U_FLASH_GITZ_A"})
	var atk_shoot: String = ph2._ev_action_attacker
	ph2._ev_depth = 0
	ph2._window_events_begin({"type": "CONFIRM_TARGETS"})
	var atk_confirm: String = ph2._ev_action_attacker
	ph2._ev_depth = depth_before
	ph2.active_shooter_id = ""
	_check("atomic SHOOT: the action's actor is the attacker even while another unit is selected", atk_shoot == "U_FLASH_GITZ_A", atk_shoot)
	_check("other actions: the selected (active) shooter is the attacker", atk_confirm == "U_TANKBUSTAS_A", atk_confirm)


# ---------------------------------------------------------------------------
func _true_gap(uid: String) -> float:
	var best := INF
	for m in _unit(uid).get("models", []):
		if not m.get("alive", true):
			continue
		for o in GS.state.board.objectives:
			var hosted: Array = MM._objective_host_areas(o)
			var d_in := float(MM.model_distance_to_objective_px(m, o)) / PX
			best = minf(best, d_in if not hosted.is_empty() else maxf(0.0, d_in - 3.0))
	return best


func _place_at_gap(uid: String, lo: float, hi: float) -> bool:
	for gx in range(4, 41, 1):
		for gy in range(6, 55, 1):
			_move_to(uid, Vector2(gx, gy))
			var g := _true_gap(uid)
			if g > lo and g <= hi and not RE.is_unit_engaged(uid, GS.state) and not _overlaps_others(uid):
				return true
	return false


## True when a model of the unit overlaps a model of any other unit.
func _overlaps_others(uid: String) -> bool:
	var meas = root.get_node("Measurement")
	for m in _unit(uid).get("models", []):
		if not m.get("alive", true):
			continue
		for oid in GS.state.units:
			if oid == uid:
				continue
			for om in GS.state.units[oid].get("models", []):
				if om.get("alive", true) and meas.models_overlap(m, om):
					return true
	return false


## Failure detail for the GRAB IT auto-move: the validate() violations met
## translating the unit straight at each objective in range of a 6" move.
func _solve_diag(uid: String, origin: Dictionary) -> String:
	var out: Array = []
	for o in GS.state.board.objectives:
		var op = o.get("position", Vector2.ZERO)
		if op is Dictionary:
			op = Vector2(float(op.get("x", 0)), float(op.get("y", 0)))
		var c := _centroid(uid)
		var dir: Vector2 = (op - c).normalized()
		var seen := {}
		var t := 0.5
		while t <= 6.0:
			var proposed := {}
			for k in origin:
				proposed[k] = origin[k] + dir * (t * PX)
			var v: Dictionary = RM.validate("normal", uid, origin, proposed, 6.0, {"end_condition": "within_objective_range"}, GS.state)
			for x in v.get("violations", []):
				seen[str(x)] = true
			t += 0.5
		out.append("%s @%s: %s" % [str(o.get("id", "?")), str(op / PX), str(seen.keys())])
	return " | ".join(out)


func _grab_it_offered(uid: String, gi: String) -> bool:
	for o in SM.get_window_offers(1, "unit_has_shot", {"phase": "shooting", "unit_id": uid}):
		if str(o.stratagem_id) == gi:
			return true
	return false


func _section_d_grab_it() -> void:
	print("\n-- D. r4:WS-1 / r4:WS-7 GRAB IT on terrain-hosted objectives --")
	_check("fixture loads", _load("ork11e_orks_active"))
	_set_det(1, "Wreckas")
	var gi := _sid(1, "grab-it-wreckas")
	var TM = root.get_node("TerrainManager")
	TM.load_terrain_layout("purge_the_foe_vs_purge_the_foe_1")
	MM._setup_objectives_for_deployment("search_and_destroy")
	var hosted := 0
	for o in GS.state.board.objectives:
		if not MM._objective_host_areas(o).is_empty():
			hosted += 1
	_check("official 11e layout: every objective is terrain-hosted", hosted == GS.state.board.objectives.size() and hosted > 0, "%d/%d" % [hosted, GS.state.board.objectives.size()])
	_shooting()
	for uid in GS.state.units:
		if int(GS.state.units[uid].owner) == 2:
			_park(uid)
	# 6.3-8.7" from the nearest objective AREA: the engine used to say 3.3-5.7".
	_check("Tankbustas placed 6.3-8.7\" from the nearest objective area", _place_at_gap("U_TANKBUSTAS_A", 6.3, 8.7))
	var tg := _true_gap("U_TANKBUSTAS_A")
	var eg: float = G_REACT.objective_range_gap_inches("U_TANKBUSTAS_A")
	_check("engine gap == true 11e gap (inside the area, not within 3\")", absf(eg - tg) < 0.05, "engine %.2f true %.2f" % [eg, tg])
	_check("GRAB IT NOT offered when no objective is reachable with a 6\" move", not _grab_it_offered("U_TANKBUSTAS_A", gi))
	# 1-3" from an area: reachable — offered, and the AI (no enemy near) pays for it.
	_check("Tankbustas placed 1-3\" from the nearest objective area", _place_at_gap("U_TANKBUSTAS_A", 1.0, 3.0))
	var near_gap := _true_gap("U_TANKBUSTAS_A")
	_check("not yet within range (gap %.2f\")" % near_gap, not RM.group_within_objective_range(GS.state, "U_TANKBUSTAS_A"))
	_check("GRAB IT offered when an objective area is within reach", _grab_it_offered("U_TANKBUSTAS_A", gi))
	var origin: Dictionary = RM.current_positions("U_TANKBUSTAS_A", GS.state)
	var sol: Dictionary = RM.solve("normal", "U_TANKBUSTAS_A", origin, 6.0, {"end_condition": "within_objective_range"}, GS.state)
	_check("the auto-move finds a placement within range of the objective", not sol.is_empty(), _solve_diag("U_TANKBUSTAS_A", origin) if sol.is_empty() else "")
	var score: float = G_REACT.ai_score(SM.get_stratagem(gi), 1, "U_TANKBUSTAS_A", "unit_has_shot", {"unit_id": "U_TANKBUSTAS_A"})
	_check("AI scores the reachable GRAB IT (no charge to lose): 2.5", absf(score - 2.5) < 0.01, "%.2f" % score)
	# WS-7: the charge-lock cost. An enemy 6" away: the shooty Tankbustas keep
	# 2.5, the melee-minded Breaka Boyz would forfeit a charge.
	var C = load("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")
	var tb_c := _centroid("U_TANKBUSTAS_A") / PX
	var to_mid: Vector2 = (Vector2(22, 30) - tb_c).normalized()
	_move_to("U_CUSTODIAN_GUARD_C", tb_c + to_mid * 9.0)
	_move_to("U_BREAKA_BOYZ_A", tb_c + to_mid * 17.0)
	var d_tb: float = C.unit_distance_inches("U_TANKBUSTAS_A", "U_CUSTODIAN_GUARD_C")
	var d_bb: float = C.unit_distance_inches("U_BREAKA_BOYZ_A", "U_CUSTODIAN_GUARD_C")
	_check("enemy within 12\" of both units, neither engaged (%.1f\" / %.1f\")" % [d_tb, d_bb],
		d_tb <= 12.0 and d_bb <= 12.0 and not RE.is_unit_engaged("U_TANKBUSTAS_A", GS.state) and not RE.is_unit_engaged("U_BREAKA_BOYZ_A", GS.state))
	_check("ranged-minded Tankbustas: GRAB IT does not forfeit a charge worth keeping", not G_REACT._grab_it_forfeits_charge("U_TANKBUSTAS_A"))
	_check("melee-minded Breaka Boyz with an enemy in charge range: GRAB IT would forfeit a charge", G_REACT._grab_it_forfeits_charge("U_BREAKA_BOYZ_A"))
	_park("U_CUSTODIAN_GUARD_C")
	_check("no enemy within 12\" -> no charge to lose (Breaka Boyz)", not G_REACT._grab_it_forfeits_charge("U_BREAKA_BOYZ_A"))
	TM.load_terrain_layout("test_open_field")


# ---------------------------------------------------------------------------
func _section_e_hunter_and_close_quarters() -> void:
	print("\n-- E. r4:WS-2 Hunter profiles + [CLOSE-QUARTERS] either/or --")
	_check("reactive fixture loads", _load("ork11e_orks_reactive"))
	_set_det(2, "Wreckas")
	var ph = _shooting()
	var hunter := "busta_rokkit_launcha___hunter_ranged"
	var standard := "busta_rokkit_launcha___standard_ranged"
	_check("Hunter profile requires MONSTER/VEHICLE", RE.hunter_profile_target_keywords(hunter, GS.state) == ["MONSTER", "VEHICLE"], str(RE.hunter_profile_target_keywords(hunter, GS.state)))
	_check("Standard profile is not a Hunter profile", RE.hunter_profile_target_keywords(standard, GS.state).is_empty())
	_check("Hunter profile cannot target INFANTRY (Custodian Guard)", not RE.weapon_profile_can_target(hunter, _unit("U_CUSTODIAN_GUARD_C"), GS.state))
	_check("Hunter profile can target a VEHICLE", RE.weapon_profile_can_target(hunter, _unit("U_BATTLEWAGON_A"), GS.state))
	# Custodian Guard C 7" from the Tankbustas (inside the Rokkit Pistol's 12").
	# Try a few sides so the Guard is not engaged with another Ork unit
	# (an engaged INFANTRY target cannot be shot).
	var tb := _centroid("U_TANKBUSTAS_A") / PX
	var cgm: Array = _unit("U_CUSTODIAN_GUARD_C").models
	var board: Dictionary = {}
	for off in [Vector2(0, -8), Vector2(0, 8), Vector2(-8, 0), Vector2(8, 0), Vector2(6, -6), Vector2(-6, 6)]:
		for i in range(cgm.size()):
			cgm[i]["position"] = {"x": (tb.x + off.x - 4.0 + i * 2.0) * PX, "y": (tb.y + off.y) * PX}
		board = GS.create_snapshot()
		if RE.get_eligible_targets("U_TANKBUSTAS_A", board).has("U_CUSTODIAN_GUARD_C"):
			break
	var wir: Array = RE.get_eligible_targets("U_TANKBUSTAS_A", board).get("U_CUSTODIAN_GUARD_C", {}).get("weapons_in_range", [])
	_check("normal shooting: weapons_in_range vs INFANTRY excludes the Hunter profile", not hunter in wir and standard in wir,
		"%s targets=%s vis=%s" % [str(wir), str(RE.get_eligible_targets("U_TANKBUSTAS_A", board).keys()), str(RE._check_target_visibility("U_TANKBUSTAS_A", "U_CUSTODIAN_GUARD_C", standard, board))])
	var v = RE.validate_shoot({"type": "SHOOT", "actor_unit_id": "U_TANKBUSTAS_A", "payload": {"assignments": [
		{"weapon_id": hunter, "target_unit_id": "U_CUSTODIAN_GUARD_C", "model_ids": ["m2"]}]}}, board)
	_check("validate_shoot refuses a Hunter profile at INFANTRY", not v.valid and "Hunter profile" in str(v.errors), str(v))
	var asg: Array = ph._ork11e_forced_shoot_assignments("U_TANKBUSTAS_A", "U_CUSTODIAN_GUARD_C", board)
	var per_model := {}
	var any_hunter := false
	for a in asg:
		if str(a.weapon_id) == hunter:
			any_hunter = true
		for mid in a.model_ids:
			if not per_model.has(mid):
				per_model[mid] = []
			per_model[mid].append(str(a.weapon_id))
	var mixed: Array = []
	for mid in per_model:
		var has_cq := false
		var has_other := false
		for wid in per_model[mid]:
			if ph._ork11e_is_close_quarters_weapon(wid, board):
				has_cq = true
			else:
				has_other = true
		if has_cq and has_other:
			mixed.append(mid)
	_check("GUN-CRAZY forced shot never fires the Hunter profile at INFANTRY", not any_hunter, str(asg))
	_check("24.07: no model fires its [CLOSE-QUARTERS] AND another ranged weapon", mixed.is_empty(), str(per_model))
	_check("the Rokkit Pistol counts as [CLOSE-QUARTERS] (24.27 / data 'close quarters')", ph._ork11e_is_close_quarters_weapon("rokkit_pistol_ranged", board))
	_check("every Tankbusta with a launcha still shoots (Standard profile)", per_model.size() >= 5, str(per_model))


# ---------------------------------------------------------------------------
func _dbb_offered(sid: String, uid: String) -> bool:
	for o in SM.get_window_offers(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": uid}):
		if str(o.stratagem_id) == sid:
			return true
	return false


func _section_f_drive_by() -> void:
	print("\n-- F. r4:WS-4 DRIVE-BY BUSTIN' only when a Firing Deck weapon can fire --")
	_check("fixture loads", _load("ork11e_orks_active"))
	_set_det(1, "Wreckas")
	var dbb := _sid(1, "drive-by-bustin-wreckas")
	_shooting()
	var td: Dictionary = _unit("U_TRUKK_A").get("transport_data", {})
	td["embarked_units"] = []
	_check("empty Trukk: NOT offered", not _dbb_offered(dbb, "U_TRUKK_A"))
	td["embarked_units"] = ["U_KOMMANDOS_A"]
	_check("Trukk with a passenger that can still shoot: offered", _dbb_offered(dbb, "U_TRUKK_A"))
	_unit("U_KOMMANDOS_A")["flags"]["has_shot"] = true
	_check("Trukk whose only passenger has shot: NOT offered", not _dbb_offered(dbb, "U_TRUKK_A"))
	_unit("U_KOMMANDOS_A")["flags"]["has_shot"] = false
	var fd := int(td.get("firing_deck", 0))
	td["firing_deck"] = 0
	_check("transport without Firing Deck: NOT offered", not _dbb_offered(dbb, "U_TRUKK_A"))
	td["firing_deck"] = fd
	td["embarked_units"] = []


# ---------------------------------------------------------------------------
func _save_aps(board: Dictionary, shooter: String, wid: String, target: String) -> Array:
	var mids: Array = []
	var w = RE.get_unit_weapons(shooter, board)
	for mid in w:
		if wid in w[mid]:
			mids.append(mid)
	var act := {"type": "SHOOT", "actor_unit_id": shooter, "payload": {"assignments": [{"weapon_id": wid, "target_unit_id": target, "model_ids": mids}]}}
	var ap_int := -999
	var ap_auto := -999
	for s in range(40):
		var r = RE.resolve_shoot_until_wounds(act, board.duplicate(true), RE.RNGService.new(40 + s))
		if not r.get("save_data_list", []).is_empty():
			ap_int = int(r.save_data_list[0].get("ap", -999))
			break
	for s in range(40):
		var r2 = RE.resolve_shoot(act, board.duplicate(true), RE.RNGService.new(40 + s))
		for d in r2.get("dice", []):
			if str(d.get("context", "")) == "save":
				ap_auto = int(d.get("ap", -999))
		if ap_auto != -999:
			break
	return [ap_int, ap_auto]


func _section_g_ap_sign() -> void:
	print("\n-- G. r4:WS-6 11e AP sign convention --")
	_check("improve_ap: signed AP-2 +1 -> -3", RE.improve_ap(-2, 1) == -3)
	_check("improve_ap: AP 0 +1 -> -1 (02.02.06)", RE.improve_ap(0, 1) == -1)
	_check("improve_ap: legacy positive magnitude 2 +1 -> 3", RE.improve_ap(2, 1) == 3)
	_check("worsen_ap: AP-3 worsened by 1 -> -2", RE.worsen_ap(-3, 1) == -2)
	_check("worsen_ap: AP-1 worsened by 2 -> 0 (never past 0)", RE.worsen_ap(-1, 2) == 0)
	_check("worsen_ap: legacy magnitude 2 worsened by 1 -> 1", RE.worsen_ap(2, 1) == 1)
	_check("worsen_ap: AP 0 stays 0", RE.worsen_ap(0, 1) == 0)
	_check("fixture loads", _load("ork11e_orks_active"))
	var b: Dictionary = GS.state.duplicate(true)
	var xs = [6.0, 8.0, 10.0, 12.0, 14.0]
	for i in range(b.units.U_CUSTODIAN_GUARD_C.models.size()):
		b.units.U_CUSTODIAN_GUARD_C.models[i]["position"] = {"x": xs[i] * PX, "y": 22.0 * PX}
		b.units.U_CUSTODIAN_GUARD_C.models[i]["current_wounds"] = 99
	var wid := "busta_rokkit_launcha___standard_ranged"
	var base_ap := int(RE.get_weapon_profile(wid, b).get("ap", 0))
	_check("Tankbustas Standard profile is AP-2 (signed)", base_ap == -2, str(base_ap))
	# effect -> (attacker flags, target flags, expected save AP)
	var cases := [
		["none", {}, {}, -2],
		["PULSA ROKKIT", {"effect_pulsa_rokkit_active": true}, {}, -3],
		["scoped improve_ap (ranged +1)", {"effect_improve_ap_ranged": 1}, {}, -3],
		["SPESHUL SHELLS (More Dakka!)", {"effect_speshul_shells_md": true}, {}, -3],
		["TRY DAT BUTTON! (+2)", {"effect_try_dat_ap2": true}, {}, -4],
		["GLOWIN' DAKKA + PULSA ROKKIT", {"ork11e_glowin_dakka": true, "effect_pulsa_rokkit_active": true}, {}, -4],
		["target worsen AP 1", {}, {"effect_worsen_ap": 1}, -1],
		["GLOWIN' DAKKA + target worsen AP 1", {"ork11e_glowin_dakka": true}, {"effect_worsen_ap": 1}, -2],
	]
	for c in cases:
		var bb: Dictionary = b.duplicate(true)
		for k in c[1]:
			bb.units.U_TANKBUSTAS_A.flags[k] = c[1][k]
		for k in c[2]:
			bb.units.U_CUSTODIAN_GUARD_C.flags[k] = c[2][k]
		var aps := _save_aps(bb, "U_TANKBUSTAS_A", wid, "U_CUSTODIAN_GUARD_C")
		_check("%s: save AP %d on the interactive AND auto paths" % [c[0], c[3]], aps[0] == c[3] and aps[1] == c[3], "interactive %d auto %d" % [aps[0], aps[1]])
	# Melee interactive save preparation (prepare_melee_save_resolution):
	# a signed AP-2 melee profile vs a target that worsens AP by 1 -> AP-1.
	var bm: Dictionary = b.duplicate(true)
	bm.units.U_CUSTODIAN_GUARD_C.flags["effect_worsen_ap"] = 1
	var mprof := {"name": "Test Klaw", "type": "Melee", "ap": -2, "damage": 2, "damage_raw": "2", "special_rules": "", "keywords": [], "abilities": []}
	var msr: Dictionary = RE.prepare_melee_save_resolution(1, "U_CUSTODIAN_GUARD_C", "U_TANKBUSTAS_A", mprof, bm)
	_check("melee interactive: AP-2 vs a target that worsens AP by 1 -> AP-1", msr.get("success", false) and int(msr.get("ap", 99)) == -1, str(msr.get("ap", msr.get("error", ""))))
	bm.units.U_TANKBUSTAS_A.flags["martial_mastery_improve_ap"] = true
	msr = RE.prepare_melee_save_resolution(1, "U_CUSTODIAN_GUARD_C", "U_TANKBUSTAS_A", mprof, bm)
	_check("melee interactive: ... plus an 'improve AP by 1' -> AP-2", msr.get("success", false) and int(msr.get("ap", 99)) == -2, str(msr.get("ap", msr.get("error", ""))))
	# DRIVE-BY DAKKA (ability) and PREY (Da Big Hunt) are the other "+1 AP" helpers.
	var bd: Dictionary = b.duplicate(true)
	bd.units.U_TANKBUSTAS_A.meta["abilities"] = bd.units.U_TANKBUSTAS_A.meta.get("abilities", []) + [{"name": "Drive-by Dakka"}]
	var bd_c: Vector2 = Vector2(float(bd.units.U_TANKBUSTAS_A.models[1].position.x), float(bd.units.U_TANKBUSTAS_A.models[1].position.y))
	for i in range(bd.units.U_CUSTODIAN_GUARD_C.models.size()):
		bd.units.U_CUSTODIAN_GUARD_C.models[i]["position"] = {"x": bd_c.x + (i - 2) * 1.8 * PX, "y": bd_c.y + 6.0 * PX}
	var aps_d := _save_aps(bd, "U_TANKBUSTAS_A", wid, "U_CUSTODIAN_GUARD_C")
	_check("DRIVE-BY DAKKA (target within 9\"): save AP -3", aps_d[0] == -3 and aps_d[1] == -3, "interactive %d auto %d" % [aps_d[0], aps_d[1]])
	var bp: Dictionary = b.duplicate(true)
	bp.units.U_CUSTODIAN_GUARD_C.flags["is_prey_of_1"] = true
	var bsb_w := ""
	var bw = RE.get_unit_weapons("U_BEAST_SNAGGA_BOYZ_A", bp)
	for mid in bw:
		for x in bw[mid]:
			if bsb_w == "" and float(RE.get_weapon_profile(str(x), bp).get("range", 0)) > 0:
				bsb_w = str(x)
	if bsb_w != "":
		var bsb_ap := int(RE.get_weapon_profile(bsb_w, bp).get("ap", 0))
		var bpc: Vector2 = Vector2(float(bp.units.U_BEAST_SNAGGA_BOYZ_A.models[0].position.x), float(bp.units.U_BEAST_SNAGGA_BOYZ_A.models[0].position.y))
		for i in range(bp.units.U_CUSTODIAN_GUARD_C.models.size()):
			bp.units.U_CUSTODIAN_GUARD_C.models[i]["position"] = {"x": bpc.x + (i - 2) * 1.8 * PX, "y": bpc.y - 7.0 * PX}
		for i in range(bp.units.U_ALLARUS_CUSTODIANS_A.models.size()):
			bp.units.U_ALLARUS_CUSTODIANS_A.models[i]["position"] = {"x": 2.0 * PX, "y": 2.0 * PX}
		var aps_p := _save_aps(bp, "U_BEAST_SNAGGA_BOYZ_A", bsb_w, "U_CUSTODIAN_GUARD_C")
		_check("PREY (BEAST SNAGGA vs its Prey): AP %d -> %d" % [bsb_ap, RE.improve_ap(bsb_ap, 1)], aps_p[0] == RE.improve_ap(bsb_ap, 1) and aps_p[1] == RE.improve_ap(bsb_ap, 1), "interactive %d auto %d" % [aps_p[0], aps_p[1]])


# ---------------------------------------------------------------------------
func _section_h_rapid_fire_attached() -> void:
	print("\n-- H. r1:WH-3 RAPID FIRE half range to the whole Attached target --")
	_check("fixture loads", _load("ork11e_orks_active"))
	var b: Dictionary = GS.state.duplicate(true)
	# Custodian Guard C shoots Boyz B (+ attached Warboss). Warboss within 12",
	# every Boyz model beyond 12" of every shooter.
	var wb: Vector2 = Vector2(float(b.units.U_WARBOSS_A.models[0].position.x), float(b.units.U_WARBOSS_A.models[0].position.y))
	var cgm: Array = b.units.U_CUSTODIAN_GUARD_C.models
	for i in range(cgm.size()):
		cgm[i]["position"] = {"x": wb.x + (i - 2) * 1.8 * PX, "y": wb.y - 10.0 * PX}
	for m in b.units.U_BOYZ_B.models:
		m["position"] = {"x": float(m.position.x), "y": float(m.position.y) + 6.0 * PX}
	b.units.U_CUSTODIAN_GUARD_C.flags["ork11e_close_range_dakka"] = true
	var wid := ""
	var w = RE.get_unit_weapons("U_CUSTODIAN_GUARD_C", b)
	var mids: Array = []
	for mid in w:
		for x in w[mid]:
			if float(RE.get_weapon_profile(str(x), b).get("range", 0)) > 0:
				wid = str(x)
		if wid in w[mid]:
			mids.append(mid)
	var C = load("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")
	var half: float = float(RE.get_weapon_profile(wid, b).get("range", 24)) / 2.0
	var far_boyz := true
	for sm in b.units.U_CUSTODIAN_GUARD_C.models:
		for bm in b.units.U_BOYZ_B.models:
			if bm.get("alive", true) and root.get_node("Measurement").model_to_model_distance_inches(sm, bm) <= half:
				far_boyz = false
	_check("geometry: no Boyz model within half range (%.0f\") of any shooter" % half, far_boyz)
	var n_half: int = RE.count_models_in_half_range(b.units.U_CUSTODIAN_GUARD_C, b.units.U_BOYZ_B, wid, mids, b)
	_check("every shooter is within half range of the attached Warboss -> counted", n_half == mids.size(), "%d/%d" % [n_half, mids.size()])
	var r = RE.resolve_shoot_until_wounds({"type": "SHOOT", "actor_unit_id": "U_CUSTODIAN_GUARD_C", "payload": {"assignments": [
		{"weapon_id": wid, "target_unit_id": "U_BOYZ_B", "model_ids": mids}]}}, b.duplicate(true), RE.RNGService.new(7))
	var rf_bonus := -1
	for d in r.get("dice", []):
		if str(d.get("context", "")) == "to_hit":
			rf_bonus = int(d.get("rapid_fire_bonus", -1))
	_check("CLOSE-RANGE DAKKA [RAPID FIRE 1] adds one attack per shooter (leader within half range)", rf_bonus == mids.size(), "rf_bonus %d" % rf_bonus)


# ---------------------------------------------------------------------------
func _section_i_attached_groups() -> void:
	print("\n-- I. r3:F2 surge target / r3:F3 GROT SHIELDS use the whole Attached unit --")
	_check("reactive fixture loads", _load("ork11e_orks_reactive"))
	_set_det(2, "Da Big Hunt")
	_shooting()
	var bsb := "U_BEAST_SNAGGA_BOYZ_A"
	var cg := "U_CUSTODIAN_GUARD_D"
	var bc := "U_BLADE_CHAMPION_B"
	for uid in GS.state.units:
		if uid in [bsb, cg, bc]:
			continue
		for m in GS.state.units[uid].models:
			m["alive"] = false
	GS.state.units[bc]["attached_to"] = cg
	GS.state.units[cg]["attachment_data"] = {"attached_characters": [bc]}
	var y0 := 20.0
	var cgm: Array = _unit(cg).models
	for i in range(cgm.size()):
		cgm[i]["position"] = {"x": (26.0 + i * 1.8) * PX, "y": y0 * PX}
	_unit(bc).models[0]["position"] = {"x": 29.6 * PX, "y": (y0 + 1.7) * PX}
	var bm: Array = _unit(bsb).models
	for i in range(bm.size()):
		bm[i]["position"] = {"x": (26.6 + (i % 5) * 1.4) * PX, "y": (y0 + 7.8 + int(i / 5) * 1.4) * PX}
	var tgt: String = RM.surge_target(bsb, GS.state)
	_check("surge target = the Attached unit's head (bodyguard), even when the leader is closest", tgt == cg, tgt)
	var origin: Dictionary = RM.current_positions(bsb, GS.state)
	var prop := {}
	for k in origin:
		prop[k] = origin[k] + Vector2(0, -4.5 * PX)
	var v = RM.validate("surge", bsb, origin, prop, 6.0, {"surge_target": tgt}, GS.state)
	_check("a surge ending engaged with leader AND bodyguard is legal (one unit, 19.03)", v.ok, str(v))
	var v_leader = RM.validate("surge", bsb, origin, prop, 6.0, {"surge_target": bc}, GS.state)
	_check("...also when the target was recorded as the leader's id", v_leader.ok, str(v_leader))
	# GROT SHIELDS: Gretchin within 3" of the attached Warboss only.
	_check("fixture loads", _load("ork11e_orks_reactive"))
	_set_det(2, "Runt Swarm")
	_shooting()
	var wbp: Vector2 = Vector2(float(_unit("U_WARBOSS_A").models[0].position.x), float(_unit("U_WARBOSS_A").models[0].position.y)) / PX
	var boyz_c := _centroid("U_BOYZ_B") / PX
	var away: Vector2 = (wbp - boyz_c).normalized()
	# Gretchin D just behind the Warboss (away from the Boyz): within 3" of the
	# leader's model, more than 3" from every Boyz model.
	var C = load("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")
	var d_boyz := 0.0
	var d_wb := 0.0
	var ok_geom := false
	var k := 2.0
	while k <= 8.0 and not ok_geom:
		_move_to("U_GRETCHIN_D", wbp + away * k)
		d_boyz = C.unit_distance_inches("U_GRETCHIN_D", "U_BOYZ_B")
		d_wb = C.unit_distance_inches("U_GRETCHIN_D", "U_WARBOSS_A")
		ok_geom = d_wb <= 3.0 and d_boyz > 3.0
		k += 0.25
	_check("geometry: Gretchin within 3\" of the Warboss (%.2f) but not of any Boyz model (%.2f)" % [d_wb, d_boyz], ok_geom)
	var gs := _sid(2, "grot-shields-runt-swarm")
	var offered := false
	for o in SM.get_window_offers(2, "enemy_targets_unit_shooting", {"phase": "shooting", "attacker_unit_id": "U_CUSTODIAN_GUARD_C", "target_unit_ids": ["U_BOYZ_B"]}):
		if str(o.stratagem_id) == gs:
			for t in o.targets:
				if str(t.unit_id) == "U_GRETCHIN_D":
					offered = true
	_check("GROT SHIELDS offered for the Attached ORKS INFANTRY unit via its leader's models", offered)


# ---------------------------------------------------------------------------
func _section_j_logs_and_display() -> void:
	print("\n-- J. r3:F6 / r3:F8 / r5:F10 / live:LIVE-6 log + display --")
	_check("fixture loads", _load("ork11e_orks_active"))
	var ph = _shooting()
	var gel = root.get_node("GameEventLog")
	var n0 := 0
	for e in gel.get_all_entries():
		if "hit(s) intercepted by" in str(e.get("text", "")):
			n0 += 1
	ph._emit_verbose_combat_log("U_FLASH_GITZ_A", [{"context": "grot_shields", "message": "GROT SHIELDS: 3 hit(s) intercepted by Gretchin Alpha — 3 mortal wound(s), 3 model(s) slain"}], [], 0, "shooting_hits")
	var n1 := 0
	for e in gel.get_all_entries():
		if "hit(s) intercepted by" in str(e.get("text", "")):
			n1 += 1
	_check("r3:F6: a grot_shields dice block becomes a Game Log line", n1 == n0 + 1, "%d -> %d" % [n0, n1])
	# r3:F8: the use log names the VINDICTIVE ARTILLERISTS option.
	_set_det(1, "Madcap Meks")
	var va := _sid(1, "vindictive-artillerists-madcap-meks")
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	_check("r3:F8: variant label for the overcharged option", Codex.variant_label(SM.get_stratagem(va), "overcharge") == "[HAZARDOUS] + [LETHAL HITS] + [SUSTAINED HITS 1]",
		Codex.variant_label(SM.get_stratagem(va), "overcharge"))
	var u = SM.use_stratagem(1, va, "U_MEK_GUNZ_A", {"window_id": "unit_selected_to_shoot", "unit_id": "U_MEK_GUNZ_A", "variant_id": "lethal_hits", "phase": "shooting"})
	var logged := false
	for e in gel.get_all_entries():
		if "Used VINDICTIVE ARTILLERISTS" in str(e.get("text", "")) and "— [LETHAL HITS]" in str(e.get("text", "")):
			logged = true
	_check("r3:F8: 'Used VINDICTIVE ARTILLERISTS … — [LETHAL HITS]' in the Game Log", u.get("success", false) and logged, str(u))
	# r5:F10: a SPEEDIEST FREEKS band reaches the dice block and the dice colours.
	var b: Dictionary = GS.state.duplicate(true)
	b.units.U_CUSTODIAN_GUARD_C.flags["ork11e_speediest_freeks"] = true
	var xs = [6.0, 8.0, 10.0, 12.0, 14.0]
	for i in range(b.units.U_CUSTODIAN_GUARD_C.models.size()):
		b.units.U_CUSTODIAN_GUARD_C.models[i]["position"] = {"x": xs[i] * PX, "y": 22.0 * PX}
	var wid := "busta_rokkit_launcha___standard_ranged"
	var mids: Array = []
	var w = RE.get_unit_weapons("U_TANKBUSTAS_A", b)
	for mid in w:
		if wid in w[mid]:
			mids.append(mid)
	var r = RE.resolve_shoot_until_wounds({"type": "SHOOT", "actor_unit_id": "U_TANKBUSTAS_A", "payload": {"assignments": [
		{"weapon_id": wid, "target_unit_id": "U_CUSTODIAN_GUARD_C", "model_ids": mids}]}}, b, RE.RNGService.new(5))
	var band := -1
	for d in r.get("dice", []):
		if str(d.get("context", "")) == "to_hit":
			band = int(d.get("hit_fail_band", -1))
	_check("r5:F10: the to_hit dice block carries the fail band (SPEEDIEST FREEKS: 3)", band == 3, str(band))
	var F = load("res://scripts/DiceLogFormatter.gd")
	_check("r5:F10: an unmodified 2 inside a 1-3 fail band is coloured as a FAIL even vs 2+", F._die_color(2, 2, 2, 6, 3) == DiceFaceIcons.COLOR_FAIL)
	_check("r5:F10: without a band the same die is a success", F._die_color(2, 2, 2, 6, 1) == DiceFaceIcons.COLOR_SUCCESS)
	# LIVE-6: violation strings name the model, never the raw engine key.
	_check("LIVE-6: model label", RM.model_label("U_TANKBUSTAS_A:0", GS.state).ends_with("model 1") and not "U_" in RM.model_label("U_TANKBUSTAS_A:0", GS.state),
		RM.model_label("U_TANKBUSTAS_A:0", GS.state))
	var origin: Dictionary = RM.current_positions("U_TANKBUSTAS_A", GS.state)
	var prop := {}
	for k in origin:
		prop[k] = origin[k] + Vector2(0, 9.0 * PX)
	var v = RM.validate("normal", "U_TANKBUSTAS_A", origin, prop, 6.0, {}, GS.state)
	var raw_id := false
	for s in v.violations:
		if "U_TANKBUSTAS_A:" in str(s):
			raw_id = true
	_check("LIVE-6: an over-long move's violations carry no raw unit:index ids", not v.ok and not raw_id, str(v.violations))


# ---------------------------------------------------------------------------
func _goaded_offer(sid: String, uid: String) -> Dictionary:
	for o in SM.get_window_offers(2, "enemy_has_shot", {"phase": "shooting", "attacker_unit_id": "U_CUSTODIAN_GUARD_C",
			"hit_unit_ids": [uid], "wounded_unit_ids": [uid]}):
		if str(o.stratagem_id) == sid:
			for t in o.targets:
				if str(t.unit_id) == uid:
					return t
	return {}


func _section_k_goaded_coherency() -> void:
	print("\n-- K. live:LIVE-7 GOADED INTO ACTION on an out-of-coherency unit --")
	_check("reactive fixture loads", _load("ork11e_orks_reactive"))
	_set_det(2, "Da Big Hunt")
	var goaded := _sid(2, "goaded-into-action-da-big-hunt")
	_shooting()
	var bsb := "U_BEAST_SNAGGA_BOYZ_A"
	# Clear the field (test-only isolation): only the Beast Snagga Boyz and
	# Custodian Guard C stay on the battlefield.
	for uid in GS.state.units:
		if uid in [bsb, "U_CUSTODIAN_GUARD_C"]:
			continue
		for m in GS.state.units[uid].models:
			m["alive"] = false
	_kill(bsb, _alive(bsb) - 2)
	var alive_models: Array = []
	for m in _unit(bsb).models:
		if m.get("alive", true):
			alive_models.append(m)
	# CG C 4" in front of two survivors 4" apart (2.7" base gap -> out of coherency).
	alive_models[0]["position"] = {"x": 30.0 * PX, "y": 52.0 * PX}
	alive_models[1]["position"] = {"x": 34.0 * PX, "y": 52.0 * PX}
	var cgm: Array = _unit("U_CUSTODIAN_GUARD_C").models
	for i in range(cgm.size()):
		cgm[i]["position"] = {"x": (28.0 + i * 2.0) * PX, "y": 47.5 * PX}
	_check("setup: unit out of coherency, unengaged", not RM.group_coherent(bsb, GS.state) and not RE.is_unit_engaged(bsb, GS.state))
	var t := _goaded_offer(goaded, bsb)
	_check("restorable (a 6\" surge can regroup it): offered, with a warning on the button", not t.is_empty() and "out of coherency" in str(t.get("label", "")), str(t))
	alive_models[1]["position"] = {"x": 8.0 * PX, "y": 52.0 * PX}
	t = _goaded_offer(goaded, bsb)
	_check("survivors 22\" apart (no surge can restore coherency): NOT offered", t.is_empty(), str(t))
	alive_models[1]["position"] = {"x": 31.6 * PX, "y": 52.0 * PX}
	t = _goaded_offer(goaded, bsb)
	_check("coherent unit: offered with the plain label", RM.group_coherent(bsb, GS.state) and not t.is_empty() and not "out of coherency" in str(t.get("label", "")), str(t))


# ---------------------------------------------------------------------------
func _set_ranged_bs_everywhere(weapon_name: String, bs: String, extra_rules: String = "") -> void:
	# get_weapon_profile resolves a weapon by NAME across the board, so every
	# copy of the profile must change for the engine to see it.
	for uid in GS.state.units:
		for w in GS.state.units[uid].get("meta", {}).get("weapons", []):
			if str(w.get("name", "")) == weapon_name:
				w["ballistic_skill"] = bs
				if extra_rules != "":
					# Structured abilities are authoritative (ISS-003).
					var ab: Array = w.get("abilities", []) if w.get("abilities", []) is Array else []
					ab.append({"id": extra_rules})
					w["abilities"] = ab
					w["special_rules"] = extra_rules


func _section_l_speediest_freeks_ai() -> void:
	print("\n-- L. r5:F8 SPEEDIEST FREEKS AI score follows the attacker's BS / TORRENT --")
	_check("reactive fixture loads", _load("ork11e_orks_reactive"))
	_set_det(2, "Kult of Speed")
	var sf := _sid(2, "speediest-freeks-kult-of-speed")
	var ctx := {"attacker_unit_id": "U_CUSTODIAN_GUARD_C", "target_unit_ids": ["U_WARBIKERS_A"]}
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	var spear := ""
	for w in _unit("U_CUSTODIAN_GUARD_C").meta.weapons:
		if str(w.get("type", "")).to_lower() == "ranged":
			spear = str(w.get("name", ""))
	var s2: float = Codex.ai_score(SM.get_stratagem(sf), 2, "U_WARBIKERS_A", "enemy_targets_unit_shooting", ctx)
	_set_ranged_bs_everywhere(spear, "3")
	var s3: float = Codex.ai_score(SM.get_stratagem(sf), 2, "U_WARBIKERS_A", "enemy_targets_unit_shooting", ctx)
	_set_ranged_bs_everywhere(spear, "5")
	var s5: float = Codex.ai_score(SM.get_stratagem(sf), 2, "U_WARBIKERS_A", "enemy_targets_unit_shooting", ctx)
	_set_ranged_bs_everywhere(spear, "2", "torrent")
	var st: float = Codex.ai_score(SM.get_stratagem(sf), 2, "U_WARBIKERS_A", "enemy_targets_unit_shooting", ctx)
	_check("BS 2+ attacker scores higher than BS 3+ (%.2f > %.2f)" % [s2, s3], s2 > s3 and s3 > 0.0)
	_check("BS 5+ attacker: SPEEDIEST FREEKS cannot remove a hit -> score 0 (%.2f)" % s5, s5 == 0.0)
	_check("TORRENT attacker (no hit roll): score 0 (%.2f)" % st, st == 0.0)


# ---------------------------------------------------------------------------
func _section_m_rerolls() -> void:
	print("\n-- M. r5:F7 re-roll once / r5:F6 + r5:F9 re-roll decision --")
	var REROLL_FAILED: int = RE.HitModifier.REROLL_FAILED
	var PLUS: int = RE.HitModifier.PLUS_ONE
	var MINUS: int = RE.HitModifier.MINUS_ONE
	var r_minus = RE.apply_hit_modifiers(5, REROLL_FAILED | MINUS, RE.RNGService.new(3), 5)
	_check("F6: raw 5 vs BS5+ with -1 (a miss after modifiers) IS re-rolled", r_minus.rerolled)
	var r_plus = RE.apply_hit_modifiers(4, REROLL_FAILED | PLUS, RE.RNGService.new(3), 5)
	_check("F6: raw 4 vs BS5+ with +1 (already a hit) is NOT re-rolled", not r_plus.rerolled)
	var r_band = RE.apply_hit_modifiers(2, REROLL_FAILED, RE.RNGService.new(3), 2, 3, 6)
	_check("F9: raw 2 vs BS2+ inside a 1-3 fail band IS re-rolled", r_band.rerolled)
	var r_crit = RE.apply_hit_modifiers(6, REROLL_FAILED | MINUS, RE.RNGService.new(3), 6)
	_check("an unmodified 6 (critical, always hits) is never re-rolled", not r_crit.rerolled)
	_check("unchanged without modifiers: raw 2 vs BS4+ re-rolled, raw 4 not",
		RE.apply_hit_modifiers(2, REROLL_FAILED, RE.RNGService.new(3), 4).rerolled and not RE.apply_hit_modifiers(4, REROLL_FAILED, RE.RNGService.new(3), 4).rerolled)
	# r5:F7: a die already re-rolled cannot be re-rolled again.
	var ctx := {"hit_evals": [{"raw": 2, "final": 5, "is_hit": true, "is_crit": false, "rerolled": true},
		{"raw": 1, "final": 1, "is_hit": false, "is_crit": false, "rerolled": false}],
		"hit_rolls": [5, 1], "modified_rolls": [5, 1], "bs": 4, "bs_per_attack": [4, 4], "hit_modifiers": 0,
		"critical_hit_threshold": 6, "critical_hits": 0}
	_check("F7: staged_die_already_rerolled flags the re-rolled die", RE.staged_die_already_rerolled(ctx, "hits", 0) and not RE.staged_die_already_rerolled(ctx, "hits", 1))
	var rr0 = RE.reroll_hit_die(ctx, 0, RE.RNGService.new(9))
	_check("F7: reroll_hit_die refuses a die that was already re-rolled", not rr0.get("success", true), str(rr0))
	var rr1 = RE.reroll_hit_die(ctx, 1, RE.RNGService.new(9))
	_check("F7: a fresh die can be re-rolled once...", rr1.get("success", false), str(rr1))
	var rr1b = RE.reroll_hit_die(ctx, 1, RE.RNGService.new(9))
	_check("F7: ...and then not again", not rr1b.get("success", true), str(rr1b))
	# Real resolver: LONG, UNCONTROLLED BURSTS re-rolls vs a FLY target mark their dice.
	_check("fixture loads", _load("ork11e_orks_active"))
	var b: Dictionary = GS.state.duplicate(true)
	b.units.U_CUSTODIAN_GUARD_C.meta.keywords.append("FLY")
	b.units.U_DAKKAJET_A.flags["ork11e_long_uncontrolled_bursts"] = true
	var dj: Vector2 = Vector2(float(b.units.U_DAKKAJET_A.models[0].position.x), float(b.units.U_DAKKAJET_A.models[0].position.y))
	for i in range(b.units.U_CUSTODIAN_GUARD_C.models.size()):
		b.units.U_CUSTODIAN_GUARD_C.models[i]["position"] = {"x": dj.x + (i - 2) * 1.8 * PX, "y": dj.y + 12.0 * PX}
	var wid := ""
	var mids: Array = []
	var w = RE.get_unit_weapons("U_DAKKAJET_A", b)
	for mid in w:
		for x in w[mid]:
			if wid == "" and float(RE.get_weapon_profile(str(x), b).get("range", 0)) > 0:
				wid = str(x)
		if wid in w[mid]:
			mids.append(mid)
	var marked := -1
	var refused := false
	for s in range(20):
		var r = RE.resolve_shoot_hits({"actor_unit_id": "U_DAKKAJET_A", "payload": {"assignments": [
			{"weapon_id": wid, "target_unit_id": "U_CUSTODIAN_GUARD_C", "model_ids": mids}]}}, b.duplicate(true), RE.RNGService.new(40 + s))
		var hc: Dictionary = r.get("hit_context", {})
		var evals: Array = hc.get("hit_evals", [])
		for i in range(evals.size()):
			if bool(evals[i].get("rerolled", false)):
				marked = i
				break
		if marked >= 0:
			refused = not RE.reroll_hit_die(hc, marked, RE.RNGService.new(1)).get("success", true)
			break
	_check("F7: a die LONG, UNCONTROLLED BURSTS re-rolled is marked, and a Command Re-roll on it is refused", marked >= 0 and refused, "marked %d" % marked)

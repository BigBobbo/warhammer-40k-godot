extends SceneTree

# Codex: Orks (11e) — MOVEMENT group stratagems (design .llm/ork_codex_11e_design.md
# §3, §3.2, §6; handlers scripts/stratagems/ork_codex/OrkCodexMovement.gd, hooks
# in phases/MovementPhase.gd).
#
# Against the real fixtures (tests/saves/ork11e_orks_active / _reactive):
#   A. registry: the 12 movement csv ids are implemented
#   B. FUNGUS-FUEL INJECTION — unit_selected_to_move window, keyword gates, CP,
#      +2" M on the move cap, expiry
#   C. 'ERE WE GO — offered only for advance moves, +2 to the advance roll (A/B, same seed)
#   D. STOMPING JUGGERNAUT — move + declares-charge windows, MOBILE through dense terrain
#   E. MIND MOSTLY ON THE MISSION — advance / fall-back only, action eligibility kept
#   F. DUBIOUS RESTRAINT — movement_phase_start / _end, objective secured, secondary pick
#   G. READIED BRAWLERS — unit_ended_normal_move, assault disembark follow-up (human + skip + AI)
#   H. SCARPER! — enemy_ended_move (opponent's turn), 8" gate, D6 / 6" attached,
#      human reactive move (cap, engagement), AI auto-move
#   I. WHIRLIGIG EVASION — 8" gate, D6 / 6" riled up
#   J. WHERE D'YA FINK YOU'RE GOING? — enemy_selected_to_fall_back, desperate escape
#      forced, extra MONSTER/VEHICLE hazard rolls (-1 battle-shocked), no legacy 10e path
#   K. WHILE THEIR BACKS ARE TURNED — movement_phase_end (opponent), engaged at start
#   K2. reverify:RV-2 — the same through the networked HOST path
#      (GameManager.apply_action END_MOVEMENT): the window opens, the result
#      carries the stratagem_window_opened stamp, the decision ends the phase
#   L. DREAD POWER — S panel, riled-up grants, expiry at the start of your next turn
#   M. DELICIOUS EATING SQUIGS — S panel, heal 3 per 02.02.04 within 3"
#   N. AI decision paths (scores + synchronous windows)
#
# Usage: godot --headless --path 40k --script tests/test_ork_codex_movement.gd

const ACTIVE := "ork11e_orks_active"
const REACTIVE := "ork11e_orks_reactive"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PX := 40.0

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var MM = null
var Movement = null
var _events: Array = []


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
	_events.append({"player": player, "window_id": window_id, "offers": offers, "ctx": ctx})


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _load(fixture: String, det_player: int = 0, detachment: String = "") -> bool:
	var slm = root.get_node("SaveLoadManager")
	var ok: bool = slm.load_game_from_file_path("res://tests/saves/%s.w40ksave" % fixture)
	GameConstants.edition = 11
	if det_player > 0 and detachment != "":
		GS.state.factions[str(det_player)]["detachment"] = detachment
		SM.load_faction_stratagems_for_player(det_player)
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	_set_ai(false, false)
	return ok

func _set_ai(p1: bool, p2: bool) -> void:
	var ai = root.get_node("AIPlayer")
	ai.enabled = p1 or p2
	ai.ai_players = {1: p1, 2: p2}

func _sid(player: int, csv: String) -> String:
	for s in SM.get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) == csv:
			return str(s.id)
	return ""

func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)

func _flag(uid: String, f: String, def = null):
	return GS.state.units[uid].get("flags", {}).get(f, def)

func _movement() -> Node:
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	if not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	return phase

func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p

## Move every model of a unit (and its attached characters) by d inches.
func _shift_unit(uid: String, d: Vector2) -> void:
	var group: Array = [uid]
	for c in GS.state.units[uid].get("attachment_data", {}).get("attached_characters", []):
		group.append(str(c))
	for gid in group:
		for m in GS.state.units[gid].models:
			if m.get("position") != null:
				var p := _pos(m)
				m["position"] = {"x": p.x + d.x * PX, "y": p.y + d.y * PX}

## Place a unit's models in a row starting at (x, y) inches, step inches apart.
func _place_row(uid: String, x: float, y: float, step: float = 1.4) -> void:
	var i := 0
	for m in GS.state.units[uid].models:
		if not m.get("alive", true):
			continue
		m["position"] = {"x": (x + i * step) * PX, "y": y * PX}
		i += 1

## Stage a rigid move of the unit (+ attached chars) by d inches, then confirm.
func _move_unit(phase, uid: String, d: Vector2, confirm: bool = true) -> Dictionary:
	var entries: Array = []
	var group: Array = [uid]
	for c in GS.state.units[uid].get("attachment_data", {}).get("attached_characters", []):
		group.append(str(c))
	for gid in group:
		for m in GS.state.units[gid].models:
			if m.get("alive", true) and m.get("position") != null:
				entries.append([gid, m])
	entries.sort_custom(func(a, b): return _pos(a[1]).dot(d) > _pos(b[1]).dot(d))
	for e in entries:
		var dest: Vector2 = _pos(e[1]) + d * PX
		var payload := {"model_id": str(e[1].id), "dest": [dest.x, dest.y]}
		if e[0] != uid:
			payload["model_source_unit_id"] = e[0]
		var r = phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": uid, "payload": payload})
		if not r.get("success", false):
			return {"success": false, "error": "stage %s/%s: %s" % [e[0], e[1].id, str(r.get("error", r.get("errors", "")))]}
	if not confirm:
		return {"success": true}
	return phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": uid, "payload": {}})

func _offer_names(offers: Array) -> Array:
	return offers.map(func(o): return str(o.get("name", "?")))

func _offer_targets(offers: Array, sid: String) -> Array:
	for o in offers:
		if str(o.get("stratagem_id", "")) == sid:
			return o.targets.map(func(t): return str(t.unit_id))
	return []

func _use(phase, player: int, window_id: String, sid: String, uid: String, ctx: Dictionary = {}) -> Dictionary:
	return phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": player, "window_id": window_id,
		"stratagem_id": sid, "target_unit_id": uid, "context": ctx})

func _decline(phase, player: int, window_id: String) -> Dictionary:
	return phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": player, "window_id": window_id})

func _pending_id(phase) -> String:
	return str(phase.get_pending_stratagem_window().get("window_id", "")) if phase.has_pending_stratagem_window() else ""

## Clear the movement_phase_start window if one paused the phase at entry.
func _drain_start_window(phase) -> void:
	while phase.has_pending_stratagem_window() and _pending_id(phase) == "movement_phase_start":
		_decline(phase, int(phase.get_pending_stratagem_window().player), "movement_phase_start")

## Decline the legacy reactive prompts (Fire Overwatch, Krump and Run,
## Scatter!) the opponent is offered when a unit moves. Returns the result of
## the last decline (it carries any window diffs replayed on that action).
func _settle(phase) -> Dictionary:
	var last := {}
	for _i in range(6):
		if phase._awaiting_fire_overwatch or phase._awaiting_overwatch_decision:
			last = phase.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": phase._fire_overwatch_player})
		elif phase._awaiting_krump_and_run:
			last = phase.execute_action({"type": "DECLINE_KRUMP_AND_RUN"})
		elif phase._awaiting_scatter:
			last = phase.execute_action({"type": "DECLINE_SCATTER"})
		else:
			break
	return last

## 11e FIRE OVERWATCH (15.08) is offered to the NON-active player in the
## movement_phase_end window: decline it when that is what the window holds.
## Returns true when it declined a window carrying FIRE OVERWATCH.
func _decline_end_of_phase_overwatch(phase) -> bool:
	if _pending_id(phase) != "movement_phase_end":
		return false
	var w: Dictionary = phase.get_pending_stratagem_window()
	if int(w.get("player", 0)) == GS.get_active_player():
		return false
	if not w.get("offers", []).any(func(o): return str(o.get("stratagem_id", "")) == "fire_overwatch_11e"):
		return false
	_decline(phase, int(w.player), "movement_phase_end")
	return true

func _win_ctx(phase) -> Dictionary:
	return phase.get_pending_stratagem_window().get("ctx", {}) if phase.has_pending_stratagem_window() else {}


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	MM = root.get_node("MissionManager")
	Movement = load("res://scripts/stratagems/ork_codex/OrkCodexMovement.gd")
	GameConstants.edition = 11
	print("\n=== test_ork_codex_movement ===\n")
	_section_registry()
	await _section_fungus_fuel()
	await _section_ere_we_go()
	await _section_stomping_juggernaut()
	await _section_mind_on_mission()
	await _section_dubious_restraint()
	await _section_readied_brawlers()
	await _section_scarper()
	await _section_eem_disembark_ingress()
	await _section_whirligig()
	await _section_where_dya_fink()
	await _section_while_their_backs()
	await _section_while_their_backs_host_path()
	await _section_dread_power()
	await _section_delicious_squigs()
	await _section_ai()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry --")
	_check("12 movement csv ids registered", Movement.IDS.size() == 12, str(Movement.IDS.size()))
	var missing: Array = []
	for csv in Movement.IDS:
		if not Movement.IMPLEMENTED.get(csv, false):
			missing.append(csv)
	_check("all 12 movement stratagems implemented", missing.is_empty(), str(missing))
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	for csv in Movement.IDS:
		_check("dispatcher routes %s to the movement group" % csv, Codex.group_for_id(csv) == Movement)


# ---------------------------------------------------------------------------
func _section_fungus_fuel() -> void:
	print("\n-- B. FUNGUS-FUEL INJECTION --")
	_check("fixture loads", _load(ACTIVE))
	var sid := _sid(1, "fungus-fuel-injection-war-horde")
	_check("FFI loaded for P1 (War Horde)", sid != "")
	var r = SM.can_use_stratagem(1, sid, "U_WARBIKERS_A")
	_check("outside its window -> 'Offered automatically when …'", not r.can_use and "Offered automatically when one of your units is selected to move" in str(r.reason), str(r))
	var phase = _movement()
	_drain_start_window(phase)
	var ctx := {"phase": "movement", "unit_id": "U_WARBIKERS_A", "move_type": "normal"}
	var offers = SM.get_window_offers(1, "unit_selected_to_move", ctx)
	_check("offered on an ORKS MOUNTED unit (Warbikers)", sid in offers.map(func(o): return o.stratagem_id), str(_offer_names(offers)))
	_check("offered on an ORKS VEHICLE unit (Battlewagon)", not SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_BATTLEWAGON_A", "move_type": "normal"}).is_empty())
	_check("NOT offered on INFANTRY (Kommandos)", SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_KOMMANDOS_A", "move_type": "normal"}).is_empty())
	_check("NOT offered in another window (unit_ended_normal_move)", SM.get_window_offers(1, "unit_ended_normal_move", {"unit_id": "U_WARBIKERS_A"}).is_empty())
	_check("NOT offered to the opponent", SM.get_window_offers(2, "unit_selected_to_move", ctx).is_empty())
	r = SM.can_use_stratagem(1, sid, "U_TRUKK_A", {"window_id": "unit_selected_to_move", "unit_id": "U_WARBIKERS_A", "move_type": "normal"})
	_check("must target the unit selected to move", not r.can_use, str(r))

	_events.clear()
	var cp0 := _cp(1)
	var res = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_WARBIKERS_A"})
	_check("BEGIN_NORMAL_MOVE succeeds", res.get("success", false), str(res.get("error", "")))
	_check("window unit_selected_to_move pending for P1", _pending_id(phase) == "unit_selected_to_move" and phase.get_pending_stratagem_window_decider() == 1)
	_check("the move is not set up while the window waits (no cap computed)", not phase.active_moves.has("U_WARBIKERS_A"))
	_check("ctx carries move_type normal", str(_events.back().ctx.get("move_type", "")) == "normal" if not _events.is_empty() else false, str(_events))
	var blocked = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_KOMMANDOS_A"})
	_check("other actions refused while waiting", not blocked.get("success", true))
	var use = _use(phase, 1, "unit_selected_to_move", sid, "U_WARBIKERS_A")
	_check("USE succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP 6 -> 5", _cp(1) == cp0 - 1, "%d -> %d" % [cp0, _cp(1)])
	_check("flag ork11e_plus_move = 2", int(_flag("U_WARBIKERS_A", "ork11e_plus_move", 0)) == 2)
	var cap := float(phase.active_moves.get("U_WARBIKERS_A", {}).get("move_cap_inches", 0.0))
	_check("resumed: move cap = M 12 + 2 = 14\"", absf(cap - 14.0) < 0.01, str(cap))
	_check("result carries the CP diff", use.get("changes", []).any(func(d): return str(d.get("path", "")) == "players.1.cp"))
	# A 13" move is legal (beyond the datasheet 12").
	var mv = _move_unit(phase, "U_WARBIKERS_A", Vector2(0, 13.0), false)
	_check("a 13\" move stages (needs the +2\")", mv.get("success", false), str(mv))
	var again = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_WARBIKERS_A"})
	_check("re-sent BEGIN_NORMAL_MOVE does not reopen the window", again.get("success", false) and not phase.has_pending_stratagem_window())
	# Expiry
	var eff = SM.active_effects.filter(func(e): return str(e.stratagem_id) == sid)
	_check("expires at end of phase", eff.size() == 1 and str(eff[0].expires) == "end_of_phase", str(eff))
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("flag cleared at end of phase", _flag("U_WARBIKERS_A", "ork11e_plus_move") == null)


# ---------------------------------------------------------------------------
func _section_ere_we_go() -> void:
	print("\n-- C. 'ERE WE GO (Green Tide) --")
	var caps := {}
	for with_strat in [false, true]:
		_load(ACTIVE, 1, "Green Tide")
		var sid := _sid(1, "ere-we-go-green-tide")
		# Free the Boyz: move Custodian Guard A out of engagement range.
		_shift_unit("U_CUSTODIAN_GUARD_A", Vector2(0, 8))
		var phase = _movement()
		_drain_start_window(phase)
		if not with_strat:
			_check("not offered for a normal move", SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_BOYZ_B", "move_type": "normal"}).is_empty())
			_check("offered for an advance move (BOYZ)", _offer_targets(SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_BOYZ_B", "move_type": "advance"}), sid) == ["U_BOYZ_B"])
			_check("NOT offered on Kommandos (not BOYZ / BEAST SNAGGA BOYZ)", SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_KOMMANDOS_A", "move_type": "advance"}).is_empty())
			var r = SM.can_use_stratagem(1, sid, "U_BOYZ_B", {"window_id": "unit_selected_to_move", "unit_id": "U_BOYZ_B", "move_type": "normal"})
			_check("validate refuses a normal move", not r.can_use, str(r))
		RE.set_test_seed(4242)
		var res = phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_BOYZ_B"})
		_check("BEGIN_ADVANCE succeeds (%s)" % ("with" if with_strat else "without"), res.get("success", false), str(res.get("error", "")))
		_check("window pending before the advance roll", _pending_id(phase) == "unit_selected_to_move" and not phase.active_moves.has("U_BOYZ_B"))
		var cp0 := _cp(1)
		var ans: Dictionary
		if with_strat:
			ans = _use(phase, 1, "unit_selected_to_move", sid, "U_BOYZ_B")
			_check("USE succeeds", ans.get("success", false), str(ans.get("error", "")))
			_check("CP -1", _cp(1) == cp0 - 1)
			_check("Boyz + attached Warboss flagged", int(_flag("U_BOYZ_B", "ork11e_ere_we_go", 0)) == 2 and int(_flag("U_WARBOSS_A", "ork11e_ere_we_go", 0)) == 2)
		else:
			ans = _decline(phase, 1, "unit_selected_to_move")
		if phase._awaiting_reroll_decision:
			phase.execute_action({"type": "DECLINE_COMMAND_REROLL"})
		caps[with_strat] = float(phase.active_moves.get("U_BOYZ_B", {}).get("move_cap_inches", -1.0))
		if with_strat:
			_check("dice log shows the 'ERE WE GO modifier", phase.dice_log.any(func(d): return str(d.get("type", "")) == "'ERE WE GO"))
			SM.on_phase_end(PHASE_MOVEMENT)
			_check("flag cleared at end of phase", _flag("U_BOYZ_B", "ork11e_ere_we_go") == null)
	_check("A/B same seed: advance cap +2 with 'ERE WE GO (%.0f -> %.0f)" % [caps.get(false, -1.0), caps.get(true, -1.0)],
		absf(caps.get(true, 0.0) - caps.get(false, 0.0) - 2.0) < 0.01)
	# Flat advances (no roll) are not modified.
	_load(ACTIVE, 1, "Green Tide")
	_shift_unit("U_CUSTODIAN_GUARD_A", Vector2(0, 8))
	var p2 = _movement()
	_drain_start_window(p2)
	GS.state.units.U_BOYZ_B.flags["ork11e_ere_we_go"] = 2
	p2._ork11e_stm_opened["U_BOYZ_B:advance"] = true
	var flat = p2._resolve_advance_roll("U_BOYZ_B", 6, false)
	_check("flat advance value is not modified", absf(float(p2.active_moves.U_BOYZ_B.move_cap_inches) - 12.0) < 0.01, str(p2.active_moves.U_BOYZ_B.move_cap_inches))


# ---------------------------------------------------------------------------
func _section_stomping_juggernaut() -> void:
	print("\n-- D. STOMPING JUGGERNAUT (Dread Mob) --")
	_load(ACTIVE, 1, "Dread Mob")
	var sid := _sid(1, "stomping-juggernaut-dread-mob")
	# Free the Deff Dread and give it room.
	_shift_unit("U_PROSECUTORS_A", Vector2(0, 10))
	var phase = _movement()
	_drain_start_window(phase)
	_check("offered on the Deff Dread (ORKS WALKER)", _offer_targets(SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_DEFF_DREAD_A", "move_type": "normal"}), sid) == ["U_DEFF_DREAD_A"])
	_check("offered on Killa Kans (ORKS WALKER)", not SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_KILLA_KANS_A", "move_type": "advance"}).is_empty())
	_check("NOT offered on a non-WALKER vehicle (Trukk)", SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_TRUKK_A", "move_type": "normal"}).filter(func(o): return o.stratagem_id == sid).is_empty())
	# A tall dense wall between the Dread and its destination.
	var TM = root.get_node("TerrainManager")
	var saved_features: Array = TM.terrain_features.duplicate(true)
	var d0 := _pos(GS.state.units.U_DEFF_DREAD_A.models[0])
	var wall := {"id": "test_wall", "type": "ruins", "category": "dense", "height_category": "tall", "height": 5.0, "height_inches": 5.0,
		"piece_class": "feature", "polygon": PackedVector2Array([d0 + Vector2(-80, 120), d0 + Vector2(80, 120), d0 + Vector2(80, 140), d0 + Vector2(-80, 140)])}
	TM.terrain_features.append(wall)
	var res = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_DEFF_DREAD_A"})
	_check("window opens for the Dread", res.get("success", false) and _pending_id(phase) == "unit_selected_to_move")
	_decline(phase, 1, "unit_selected_to_move")
	var gate_no = phase._check_dense_terrain_gate("U_DEFF_DREAD_A", phase.active_moves.U_DEFF_DREAD_A, d0, d0 + Vector2(0, 200), GS.state.units.U_DEFF_DREAD_A.models[0])
	_check("without MOBILE the tall dense wall blocks the Dread (13.06)", not gate_no.valid, str(gate_no))
	# New phase: use it.
	PM.transition_to_phase(PHASE_COMMAND)
	SM._usage_history = {"1": [], "2": []}
	phase = _movement()
	_drain_start_window(phase)
	var cp0 := _cp(1)
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_DEFF_DREAD_A"})
	var use = _use(phase, 1, "unit_selected_to_move", sid, "U_DEFF_DREAD_A")
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag ork11e_mobile", _flag("U_DEFF_DREAD_A", "ork11e_mobile", false) == true)
	_check("terrain keywords now include MOBILE", "MOBILE" in phase._terrain_rule_keywords("U_DEFF_DREAD_A", phase.active_moves.U_DEFF_DREAD_A))
	var gate_yes = phase._check_dense_terrain_gate("U_DEFF_DREAD_A", phase.active_moves.U_DEFF_DREAD_A, d0, d0 + Vector2(0, 200), GS.state.units.U_DEFF_DREAD_A.models[0])
	_check("with MOBILE the Dread moves through the dense wall", gate_yes.valid, str(gate_yes))
	var mv = _move_unit(phase, "U_DEFF_DREAD_A", Vector2(0, 5.0))
	_check("real STAGE + CONFIRM through the wall succeeds", mv.get("success", false), str(mv))
	# Charge phase: the unit_declares_charge window (hook added by the Other group).
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("MOBILE expires at end of phase", _flag("U_DEFF_DREAD_A", "ork11e_mobile") == null)
	SM._usage_history = {"1": [], "2": []}
	PM.transition_to_phase(PHASE_CHARGE)
	var cctx := {"phase": "charge", "unit_id": "U_KILLA_KANS_A", "target_unit_ids": ["U_CUSTODIAN_GUARD_A"]}
	var coffers = SM.get_window_offers(1, "unit_declares_charge", cctx)
	_check("offered in the unit_declares_charge window (Charge phase)", _offer_targets(coffers, sid) == ["U_KILLA_KANS_A"], str(_offer_names(coffers)))
	var cu = SM.use_stratagem(1, sid, "U_KILLA_KANS_A", {"window_id": "unit_declares_charge", "unit_id": "U_KILLA_KANS_A", "phase": "charge"})
	_check("charge-window use applies MOBILE", cu.get("success", false) and _flag("U_KILLA_KANS_A", "ork11e_mobile", false) == true, str(cu.get("error", "")))
	var cp_phase = PM.get_current_phase_instance()
	var k0 := _pos(GS.state.units.U_KILLA_KANS_A.models[0])
	var cwall := {"id": "test_wall2", "type": "ruins", "category": "dense", "height": 5.0, "height_inches": 5.0, "piece_class": "feature",
		"polygon": PackedVector2Array([k0 + Vector2(-30, 60), k0 + Vector2(30, 60), k0 + Vector2(30, 80), k0 + Vector2(-30, 80)])}
	TM.terrain_features.append(cwall)
	var paths := {"m1": [[k0.x, k0.y], [k0.x, k0.y + 120.0]]}
	var tv = cp_phase._validate_no_solid_terrain_on_paths("U_KILLA_KANS_A", paths, GS.state.units.U_KILLA_KANS_A.meta.keywords)
	_check("ChargePhase path gate honours MOBILE", tv.valid, str(tv))
	GS.state.units.U_KILLA_KANS_A.flags.erase("ork11e_mobile")
	tv = cp_phase._validate_no_solid_terrain_on_paths("U_KILLA_KANS_A", paths, GS.state.units.U_KILLA_KANS_A.meta.keywords)
	_check("... and blocks without it", not tv.valid, str(tv))
	_check("NOT offered in the Charge phase window to the opponent", SM.get_window_offers(2, "unit_declares_charge", cctx).is_empty())
	TM.terrain_features = saved_features


# ---------------------------------------------------------------------------
func _section_mind_on_mission() -> void:
	print("\n-- E. MIND MOSTLY ON THE MISSION (Taktikal Brigade) --")
	_load(ACTIVE, 1, "Taktikal Brigade")
	var sid := _sid(1, "mind-mostly-on-the-mission-taktikal-brigade")
	var phase = _movement()
	_drain_start_window(phase)
	_check("NOT offered for a normal move", SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_KOMMANDOS_A", "move_type": "normal"}).filter(func(o): return o.stratagem_id == sid).is_empty())
	_check("offered for an advance (Kommandos)", _offer_targets(SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_KOMMANDOS_A", "move_type": "advance"}), sid) == ["U_KOMMANDOS_A"])
	_check("offered for a fall-back (Boyz)", _offer_targets(SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_BOYZ_B", "move_type": "fall_back"}), sid) == ["U_BOYZ_B"])
	_check("NOT offered on Breaka Boyz (not BOYZ/KOMMANDOS/STORMBOYZ)", SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_BREAKA_BOYZ_A", "move_type": "advance"}).filter(func(o): return o.stratagem_id == sid).is_empty())
	# Kommandos advance with it; Stormboyz advance without it.
	var cp0 := _cp(1)
	phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_KOMMANDOS_A"})
	var use = _use(phase, 1, "unit_selected_to_move", sid, "U_KOMMANDOS_A")
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	if phase._awaiting_reroll_decision:
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL"})
	var mv = _move_unit(phase, "U_KOMMANDOS_A", Vector2(0, 1.0))
	_check("Kommandos advance confirmed", mv.get("success", false), str(mv))
	phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_STORMBOYZ_A"})
	if phase.has_pending_stratagem_window():
		_decline(phase, 1, "unit_selected_to_move")
	if phase._awaiting_reroll_decision:
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL"})
	var mv2 = _move_unit(phase, "U_STORMBOYZ_A", Vector2(0, 1.0))
	_check("Stormboyz advance confirmed", mv2.get("success", false), str(mv2))
	_check("Kommandos advanced flag set", _flag("U_KOMMANDOS_A", "advanced", false) == true)
	_check("no 16.01 action lock on the Kommandos", _flag("U_KOMMANDOS_A", "cannot_start_action", false) == false)
	_check("action lock on the Stormboyz", _flag("U_STORMBOYZ_A", "cannot_start_action", false) == true)
	var AM = load("res://scripts/rules/ActionsManager.gd")
	var k_el = AM.can_start_action("U_KOMMANDOS_A", GS.state)
	var s_el = AM.can_start_action("U_STORMBOYZ_A", GS.state)
	_check("Kommandos still eligible to start an action", k_el.eligible, str(k_el))
	_check("Stormboyz (no stratagem) not eligible", not s_el.eligible, str(s_el))
	var eff = SM.active_effects.filter(func(e): return str(e.stratagem_id) == sid)
	_check("lasts until the end of the turn", eff.size() == 1 and str(eff[0].expires) == "end_of_turn", str(eff))
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("still active after the Movement phase", _flag("U_KOMMANDOS_A", "ork11e_mind_on_mission", false) == true)
	SM.on_turn_start(2)
	_check("cleared at the next turn start", _flag("U_KOMMANDOS_A", "ork11e_mind_on_mission") == null)
	_check("turn reset list now clears cannot_start_action (ScoringPhase)", "cannot_start_action" in FileAccess.get_file_as_string("res://phases/ScoringPhase.gd"))


# ---------------------------------------------------------------------------
func _section_dubious_restraint() -> void:
	print("\n-- F. DUBIOUS RESTRAINT (Taktikal Brigade) --")
	_load(ACTIVE, 1, "Taktikal Brigade")
	var sid := _sid(1, "dubious-restraint-taktikal-brigade")
	MM._sticky_objectives.clear()
	MM.check_all_objectives()
	_check("obj_center controlled by P1 (Boyz on it)", int(MM.objective_control_state.get("obj_center", 0)) == 1, str(MM.objective_control_state))
	_events.clear()
	var phase = _movement()
	if not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	_check("movement_phase_start window pending for P1 at phase entry", _pending_id(phase) == "movement_phase_start" and phase.get_pending_stratagem_window_decider() == 1, _pending_id(phase))
	var offers: Array = phase.get_pending_stratagem_window().get("offers", [])
	_check("offered on the Boyz (controlling obj_center)", _offer_targets(offers, sid) == ["U_BOYZ_B"], str(offers))
	_check("NOT offered to the opponent at their phase start (turn gate)", SM.get_window_offers(2, "movement_phase_start", {"phase": "movement"}).is_empty())
	var cp0 := _cp(1)
	var use = _use(phase, 1, "movement_phase_start", sid, "U_BOYZ_B")
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var sec = MM.is_objective_secured("obj_center")
	_check("obj_center is secured by P1", sec.secured and int(sec.player) == 1, str(sec))
	_check("no window left pending", not phase.has_pending_stratagem_window())
	_check("once per phase: not offered again at the end", SM.get_window_offers(1, "movement_phase_end", {"phase": "movement", "engaged_at_phase_start": []}).filter(func(o): return o.stratagem_id == sid).is_empty())
	# 14.03: the secured objective stays P1's with no P1 unit in range until the
	# opponent's level of control is greater.
	_shift_unit("U_BOYZ_B", Vector2(0, -12))
	_shift_unit("U_CUSTODIAN_GUARD_A", Vector2(0, 15))
	MM.check_all_objectives()
	_check("secured objective still P1's with nobody in range", int(MM.objective_control_state.get("obj_center", 0)) == 1, str(MM.objective_control_state.get("obj_center")))
	# Secondary pick: a unit controlling two objectives (state set up directly).
	_load(ACTIVE, 1, "Taktikal Brigade")
	MM._sticky_objectives.clear()
	_shift_unit("U_CUSTODIAN_GUARD_A", Vector2(0, 15))
	var kom: Array = GS.state.units.U_KOMMANDOS_A.models
	for i in range(kom.size()):
		var t := float(i) / float(kom.size() - 1)
		kom[i]["position"] = {"x": lerpf(11.2, 20.6, t) * PX, "y": lerpf(23.0, 29.0, t) * PX}
	_shift_unit("U_BOYZ_B", Vector2(0, -8))
	MM.check_all_objectives()
	MM.objective_control_state["obj_center"] = 1
	MM.objective_control_state["obj_nml_1"] = 1
	var objs: Array = Movement.controlled_objectives("U_KOMMANDOS_A", 1)
	_check("Kommandos control both obj_nml_1 and obj_center", "obj_center" in objs and "obj_nml_1" in objs, str(objs))
	var eoffers = SM.get_window_offers(1, "movement_phase_end", {"phase": "movement", "engaged_at_phase_start": []})
	PM.transition_to_phase(PHASE_MOVEMENT)
	var p2 = PM.get_current_phase_instance()
	eoffers = p2.get_pending_stratagem_window().get("offers", []) if p2.has_pending_stratagem_window() else SM.get_window_offers(1, "movement_phase_start", {"phase": "movement"})
	var kt := {}
	for o in eoffers:
		if o.stratagem_id == sid:
			for t in o.targets:
				if t.unit_id == "U_KOMMANDOS_A":
					kt = t
	_check("target entry carries an objective secondary with both options", kt.has("secondary") and kt.secondary.kind == "objective" and kt.secondary.options.size() == 2, str(kt))
	if p2.has_pending_stratagem_window():
		var no_sec = _use(p2, 1, "movement_phase_start", sid, "U_KOMMANDOS_A")
		_check("USE without the secondary choice is refused", not no_sec.get("success", true), str(no_sec))
		var with_sec = _use(p2, 1, "movement_phase_start", sid, "U_KOMMANDOS_A", {"secondary_id": "obj_nml_1"})
		_check("USE with secondary obj_nml_1 succeeds", with_sec.get("success", false), str(with_sec.get("error", "")))
		_check("obj_nml_1 secured, obj_center not", MM.is_objective_secured("obj_nml_1").secured and not MM.is_objective_secured("obj_center").secured)
	# movement_phase_end path (END_MOVEMENT): offered there when unused.
	_load(ACTIVE, 1, "Taktikal Brigade")
	MM._sticky_objectives.clear()
	MM.check_all_objectives()
	var p3 = _movement()
	_drain_start_window(p3)
	var end_res = p3.execute_action({"type": "END_MOVEMENT"})
	_check("END_MOVEMENT succeeds", end_res.get("success", false), str(end_res.get("error", "")))
	_check("movement_phase_end window pending before the phase ends", _pending_id(p3) == "movement_phase_end" and GS.get_current_phase() == PHASE_MOVEMENT, _pending_id(p3))
	var u3 = _use(p3, 1, "movement_phase_end", sid, "U_BOYZ_B")
	_check("END window USE secures obj_center", u3.get("success", false) and MM.is_objective_secured("obj_center").secured, str(u3.get("error", "")))
	# 11e 15.08: the opponent's movement_phase_end window (FIRE OVERWATCH)
	# follows the active player's before the phase ends.
	_check("then P2's FIRE OVERWATCH window (15.08) is answered", _decline_end_of_phase_overwatch(p3), _pending_id(p3))
	_check("the phase then completes (Shooting)", GS.get_current_phase() == PHASE_SHOOTING, str(GS.get_current_phase()))
	MM._sticky_objectives.clear()


# ---------------------------------------------------------------------------
func _section_readied_brawlers() -> void:
	print("\n-- G. READIED BRAWLERS (Blitz Brigade) --")
	_load(ACTIVE, 1, "Blitz Brigade")
	var sid := _sid(1, "readied-brawlers-blitz-brigade")
	var TMgr = root.get_node("TransportManager")
	TMgr.embark_unit("U_FLASH_GITZ_A", "U_BATTLEWAGON_A")
	TMgr.embark_unit("U_TANKBUSTAS_A", "U_BATTLEWAGON_A")
	_check("Flash Gitz + Tankbustas embarked", str(GS.state.units.U_FLASH_GITZ_A.get("embarked_in", "")) == "U_BATTLEWAGON_A" and str(GS.state.units.U_TANKBUSTAS_A.get("embarked_in", "")) == "U_BATTLEWAGON_A")
	var phase = _movement()
	_drain_start_window(phase)
	_check("NOT offered on a non-WAGON (Trukk)", SM.get_window_offers(1, "unit_ended_normal_move", {"unit_id": "U_TRUKK_A"}).is_empty())
	_check("NOT offered in unit_selected_to_move", SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_BATTLEWAGON_A", "move_type": "normal"}).filter(func(o): return o.stratagem_id == sid).is_empty())
	_check("NOT offered to the opponent", SM.get_window_offers(2, "unit_ended_normal_move", {"unit_id": "U_BATTLEWAGON_A"}).is_empty())
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BATTLEWAGON_A"})
	if phase.has_pending_stratagem_window():
		_decline(phase, 1, "unit_selected_to_move")
	_settle(phase)
	var cp0 := _cp(1)
	# The wagon's hull is 100mm (x) by 180mm (y); move it 2" east.
	var mv = _move_unit(phase, "U_BATTLEWAGON_A", Vector2(2.0, 0))
	_check("Battlewagon normal move confirmed", mv.get("success", false), str(mv))
	_check("unit_ended_normal_move window pending (P1) before any opponent reaction", _pending_id(phase) == "unit_ended_normal_move" and phase.get_pending_stratagem_window_decider() == 1, _pending_id(phase))
	var use = _use(phase, 1, "unit_ended_normal_move", sid, "U_BATTLEWAGON_A")
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("assault disembark follow-up running (human)", phase.is_ork11e_assault_disembark_pending("U_FLASH_GITZ_A") and phase.is_ork11e_assault_disembark_pending("U_TANKBUSTAS_A"))
	_check("DisembarkMove selects the 18.06 assault mode", MoveTypes.get_type("disembark").select_mode("U_FLASH_GITZ_A", GS.state).mode == "assault")
	var blocked = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_KOMMANDOS_A"})
	_check("other actions refused during the follow-up", not blocked.get("success", true), str(blocked))
	_check("AIPlayer sees the follow-up owner as pending decider", phase.get_pending_stratagem_window_decider() == 1)
	# Flash Gitz (40mm) in a column just west of the hull (hull x = w.x +/- 1.97").
	var w := _pos(GS.state.units.U_BATTLEWAGON_A.models[0])
	var positions := []
	for i in range(5):
		positions.append({"x": w.x - 3.0 * PX, "y": w.y + (-3.0 + i * 1.7) * PX})
	var conf = phase.execute_action({"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_FLASH_GITZ_A", "payload": {"positions": positions}})
	_check("CONFIRM_DISEMBARK (assault) succeeds", conf.get("success", false), str(conf.get("error", conf.get("errors", ""))))
	_check("Flash Gitz on the battlefield", GS.state.units.U_FLASH_GITZ_A.get("embarked_in", null) == null)
	_check("assault disembark: still eligible to charge", _flag("U_FLASH_GITZ_A", "cannot_charge", false) == false)
	_check("follow-up moves on to the Tankbustas", phase.is_ork11e_assault_disembark_pending("U_TANKBUSTAS_A"))
	var skip = phase.execute_action({"type": "SKIP_ASSAULT_DISEMBARK", "actor_unit_id": "U_TANKBUSTAS_A", "payload": {"unit_id": "U_TANKBUSTAS_A"}})
	_check("SKIP_ASSAULT_DISEMBARK succeeds", skip.get("success", false), str(skip.get("error", "")))
	_check("Tankbustas stay embarked", str(GS.state.units.U_TANKBUSTAS_A.get("embarked_in", "")) == "U_BATTLEWAGON_A")
	_check("follow-up finished, flag removed", not phase.is_ork11e_assault_disembark_pending("U_TANKBUSTAS_A") and _flag("U_BATTLEWAGON_A", "ork11e_readied_brawlers") == null)
	_check("later disembarks no longer use the assault mode", MoveTypes.get_type("disembark").select_mode("U_TANKBUSTAS_A", GS.state).mode != "assault", str(MoveTypes.get_type("disembark").select_mode("U_TANKBUSTAS_A", GS.state)))
	_settle(phase)
	_check("phase accepts actions again", not phase.has_pending_stratagem_window() and phase.get_pending_stratagem_window_decider() == 0)
	# Not offered after an Advance; not offered with nobody embarked.
	_load(ACTIVE, 1, "Blitz Brigade")
	var p2 = _movement()
	_drain_start_window(p2)
	_check("NOT offered with nobody embarked", SM.get_window_offers(1, "unit_ended_normal_move", {"unit_id": "U_BATTLEWAGON_A"}).is_empty())
	TMgr.embark_unit("U_FLASH_GITZ_A", "U_BATTLEWAGON_A")
	p2.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_BATTLEWAGON_A"})
	if p2.has_pending_stratagem_window():
		_decline(p2, 1, "unit_selected_to_move")
	if p2._awaiting_reroll_decision:
		p2.execute_action({"type": "DECLINE_COMMAND_REROLL"})
	_settle(p2)
	var amv = _move_unit(p2, "U_BATTLEWAGON_A", Vector2(2.0, 0))
	_check("after an ADVANCE no unit_ended_normal_move window", amv.get("success", false) and _pending_id(p2) != "unit_ended_normal_move", "%s %s" % [_pending_id(p2), str(amv.get("error", ""))])
	# AI decider: auto-placement.
	_load(ACTIVE, 1, "Blitz Brigade")
	TMgr.embark_unit("U_FLASH_GITZ_A", "U_BATTLEWAGON_A")
	_place_row("U_CUSTODIAN_GUARD_F", 1.5, 19.5, 1.8)  # an enemy within 12" of the wagon (AI score)
	var p3 = _movement()
	_drain_start_window(p3)
	_set_ai(true, false)
	p3.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BATTLEWAGON_A"})
	_settle(p3)
	var cp1 := _cp(1)
	var amv3 = _move_unit(p3, "U_BATTLEWAGON_A", Vector2(2.0, 0))
	_set_ai(false, false)
	_check("AI: confirm succeeds and never pauses on the window", amv3.get("success", false) and not p3.has_pending_stratagem_window() and p3.get_pending_stratagem_window_decider() == 0, str(amv3.get("error", "")))
	_check("AI used READIED BRAWLERS (CP -1)", _cp(1) == cp1 - 1, "%d -> %d" % [cp1, _cp(1)])
	_check("AI assault-disembarked the Flash Gitz", GS.state.units.U_FLASH_GITZ_A.get("embarked_in", null) == null and _flag("U_FLASH_GITZ_A", "cannot_charge", false) == false)
	_check("AI result carries the disembark diffs", amv3.get("changes", []).any(func(d): return "U_FLASH_GITZ_A" in str(d.get("path", ""))))
	_check("AI follow-up removed the wagon flag", _flag("U_BATTLEWAGON_A", "ork11e_readied_brawlers") == null)


# ---------------------------------------------------------------------------
func _section_scarper() -> void:
	print("\n-- H. SCARPER! (Runt Swarm) — opponent's Movement phase --")
	_check("reactive fixture loads", _load(REACTIVE, 2, "Runt Swarm"))
	var sid := _sid(2, "scarper-runt-swarm")
	_check("SCARPER! loaded for P2 (Orks, non-active)", sid != "")
	# Gretchin C at (37.5..42.5, 48..49.2); Custodian Guard C ends ~6.7" north of it.
	_place_row("U_CUSTODIAN_GUARD_C", 35.0, 37.0, 1.8)
	_place_row("U_RUNTHERD_A", 43.0, 53.0)   # out of the Gretchin's way
	var phase = _movement()
	_drain_start_window(phase)
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_C"})
	_check("no window for the Custodes (no window stratagems)", not phase.has_pending_stratagem_window())
	_settle(phase)
	var cp2 := _cp(2)
	var mv = _move_unit(phase, "U_CUSTODIAN_GUARD_C", Vector2(0, 3.0))
	_check("Custodes move confirmed", mv.get("success", false), str(mv))
	# 11e (migrated): FIRE OVERWATCH 15.08 is "End of your opponent's Movement
	# phase" only — no per-move offer precedes the codex window any more (this
	# used to assert the 10e Balance Dataslate per-move prompt came first).
	_check("11e: no per-move Fire Overwatch; the codex window opens at once", not (phase._awaiting_fire_overwatch or phase._awaiting_overwatch_decision))
	_settle(phase)
	_check("enemy_ended_move pending for P2", _pending_id(phase) == "enemy_ended_move" and phase.get_pending_stratagem_window_decider() == 2, _pending_id(phase))
	var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
	var targets := _offer_targets(offers, sid)
	_check("offered on Gretchin C (within 8\")", "U_GRETCHIN_C" in targets, str(targets))
	_check("NOT offered when the enemy ended far away (8\" gate)", SM.get_window_offers(2, "enemy_ended_move", {"phase": "movement", "enemy_unit_id": "U_CUSTODIAN_GUARD_F", "move_type": "normal"}).is_empty())
	_check("NOT offered to the active player", SM.get_window_offers(1, "enemy_ended_move", _win_ctx(phase)).is_empty())
	_check("window ctx names the enemy unit + move type", str(_win_ctx(phase).get("enemy_unit_id", "")) == "U_CUSTODIAN_GUARD_C" and str(_win_ctx(phase).get("move_type", "")) == "normal", str(_win_ctx(phase)))
	RE.set_test_seed(777)
	var use = _use(phase, 2, "enemy_ended_move", sid, "U_GRETCHIN_C")
	_check("USE by P2 succeeds, P2 CP -1", use.get("success", false) and _cp(2) == cp2 - 1, str(use.get("error", "")))
	var rm: Dictionary = phase._ork11e_reactive_move
	var cap := float(phase.active_moves.get("U_GRETCHIN_C", {}).get("move_cap_inches", 0.0))
	_check("reactive move set up for Gretchin C (P2)", str(rm.get("unit_id", "")) == "U_GRETCHIN_C" and int(rm.get("player", 0)) == 2, str(rm))
	_check("max distance = the D6 roll (1..6)", cap >= 1.0 and cap <= 6.0 and absf(cap - round(cap)) < 0.001, str(cap))
	_check("D6 roll recorded in the dice log", phase.dice_log.any(func(d): return str(d.get("type", "")) == "SCARPER!" and int(d.get("roll", 0)) == int(cap)), str(phase.dice_log.slice(-2)))
	var g0 := _pos(GS.state.units.U_GRETCHIN_C.models[0])
	var over = phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_GRETCHIN_C",
		"payload": {"model_id": str(GS.state.units.U_GRETCHIN_C.models[0].id), "dest": [g0.x, g0.y + (cap + 0.6) * PX]}})
	_check("a move beyond the roll is refused", not over.get("success", true), str(over))
	var blocked = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_D"})
	_check("the active player waits for the reactive move", not blocked.get("success", true), str(blocked))
	var gmv = _move_unit(phase, "U_GRETCHIN_C", Vector2(0, minf(cap, 1.0) - 0.05))
	_check("Gretchin reactive move confirmed (human)", gmv.get("success", false), str(gmv))
	_check("reactive state cleared, follow-up done", phase._ork11e_reactive_move.is_empty() and phase._reactive_move_owner == 0 and phase.get_pending_stratagem_window_decider() == 0)
	_check("Gretchin marked moved", _flag("U_GRETCHIN_C", "moved", false) == true)
	_check("active player can move again", phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_D"}).get("success", false))
	# Attached unit -> 6" (no roll).
	_load(REACTIVE, 2, "Runt Swarm")
	var gc: Dictionary = GS.state.units.U_GRETCHIN_C
	gc["attachment_data"] = {"attached_characters": ["U_RUNTHERD_A"]}
	GS.state.units.U_RUNTHERD_A["attached_to"] = "U_GRETCHIN_C"
	_place_row("U_CUSTODIAN_GUARD_C", 35.0, 37.0, 1.8)
	var p2 = _movement()
	_drain_start_window(p2)
	p2.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_C"})
	_settle(p2)
	_move_unit(p2, "U_CUSTODIAN_GUARD_C", Vector2(0, 3.0))
	_settle(p2)
	var u2 = _use(p2, 2, "enemy_ended_move", sid, "U_GRETCHIN_C")
	_check("attached Gretchin + Runtherd: normal move up to 6\" (no roll)", u2.get("success", false) and absf(float(p2.active_moves.get("U_GRETCHIN_C", {}).get("move_cap_inches", 0.0)) - 6.0) < 0.01, str(u2.get("error", "")))
	_check("the Runtherd moves with its unit (original positions tracked)", str(p2.active_moves.get("U_GRETCHIN_C", {}).get("original_positions", {}).keys()).contains("U_RUNTHERD_A"), str(p2.active_moves.get("U_GRETCHIN_C", {}).get("original_positions", {}).keys()))
	# "Skip Overwatch" declines INSIDE the CONFIRM action (the controller answers
	# the fire_overwatch_opportunity signal synchronously), before BasePhase has
	# applied the move: the window must still see the Custodes where they ended.
	_load(REACTIVE, 2, "Runt Swarm")
	_place_row("U_CUSTODIAN_GUARD_C", 35.0, 37.0, 1.8)
	var pn = _movement()
	_drain_start_window(pn)
	var auto_decline := func(player: int, _units: Array, _enemy: String) -> void:
		pn.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": player})
	pn.fire_overwatch_opportunity.connect(auto_decline)
	pn.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_C"})
	var nmv = _move_unit(pn, "U_CUSTODIAN_GUARD_C", Vector2(0, 3.0))
	pn.fire_overwatch_opportunity.disconnect(auto_decline)
	_check("nested auto-decline: move confirmed", nmv.get("success", false), str(nmv.get("error", "")))
	_check("nested auto-decline: enemy_ended_move offers Gretchin C (8\" measured from the END position)",
		_pending_id(pn) == "enemy_ended_move" and "U_GRETCHIN_C" in _offer_targets(pn.get_pending_stratagem_window().get("offers", []), sid), _pending_id(pn))
	_check("nested auto-decline: GameState holds the applied move afterwards", absf(_pos(GS.state.units.U_CUSTODIAN_GUARD_C.models[0]).y - 40.0 * PX) < 1.0, str(_pos(GS.state.units.U_CUSTODIAN_GUARD_C.models[0])))
	# engaged -> not offered
	_load(REACTIVE, 2, "Runt Swarm")
	var ge := _pos(GS.state.units.U_GRETCHIN_C.models[0])
	_place_row("U_CUSTODIAN_GUARD_E", ge.x / PX - 0.5, ge.y / PX - 1.5, 1.8)
	_check("Gretchin C engaged after setup", RE.is_unit_engaged("U_GRETCHIN_C", GS.state))
	PM.transition_to_phase(PHASE_MOVEMENT)
	var engaged_offers = SM.get_window_offers(2, "enemy_ended_move", {"phase": "movement", "enemy_unit_id": "U_CUSTODIAN_GUARD_E", "move_type": "normal"})
	_check("engaged Gretchin not offered", not "U_GRETCHIN_C" in _offer_targets(engaged_offers, sid), str(engaged_offers))
	# AI decider: synchronous auto-move. 11e (migrated): with no per-move
	# Fire Overwatch, the Custodes' CONFIRM itself opens enemy_ended_move, so
	# the AI seat is set before the move and that result carries the diffs
	# (at 10e it was the Overwatch decline that opened the window).
	_load(REACTIVE, 2, "Runt Swarm")
	_place_row("U_CUSTODIAN_GUARD_C", 35.0, 37.0, 1.8)
	var p3 = _movement()
	_drain_start_window(p3)
	p3.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_C"})
	_settle(p3)
	var before := _pos(GS.state.units.U_GRETCHIN_C.models[0])
	var cp_ai := _cp(2)
	_set_ai(false, true)
	RE.set_test_seed(31337)
	var amv = _move_unit(p3, "U_CUSTODIAN_GUARD_C", Vector2(0, 3.0))
	var settled := _settle(p3)
	if settled.is_empty():
		settled = amv
	_set_ai(false, false)
	var after := _pos(GS.state.units.U_GRETCHIN_C.models[0])
	_check("AI: no pause", amv.get("success", false) and not p3.has_pending_stratagem_window() and p3.get_pending_stratagem_window_decider() == 0, str(amv.get("error", "")))
	_check("AI used SCARPER! (P2 CP -1)", _cp(2) == cp_ai - 1, "%d -> %d" % [cp_ai, _cp(2)])
	var moved_in := before.distance_to(after) / PX
	var ai_cap := 0.0
	for d in p3.dice_log:
		if str(d.get("type", "")) == "SCARPER!":
			ai_cap = float(d.get("roll", 0))
	_check("AI moved the Gretchin, within the roll (%.2f\" <= %.0f\")" % [moved_in, ai_cap], moved_in > 0.1 and moved_in <= ai_cap + 0.05)
	_check("AI moved away from the enemy", after.distance_to(_pos(GS.state.units.U_CUSTODIAN_GUARD_C.models[0])) > before.distance_to(_pos(GS.state.units.U_CUSTODIAN_GUARD_C.models[0])))
	_check("AI move ends unengaged", not RE.is_unit_engaged("U_GRETCHIN_C", GS.state))
	_check("AI result (on the move that opened the window) carries the Gretchin position diffs", settled.get("changes", []).any(func(d): return "U_GRETCHIN_C.models" in str(d.get("path", ""))), str(settled.get("changes", []).size()))
	_check("AI reactive state cleared", p3._ork11e_reactive_move.is_empty() and p3._reactive_move_owner == 0)


# ---------------------------------------------------------------------------
## r3:F4 / r5:F5 — 11e disembark (18.04) and ingress (20.04) are moves: the
## opponent's enemy_ended_move window opens once each has ended (the Custodes
## fixture has no transport, so the active player borrows the Ork Trukk —
## setup privilege — with Custodian Guard C embarked; the ingress arrival is a
## special-rule set-up within 8", resolved through _process_place_reinforcement
## because a normal ingress must end more than 8" from every enemy).
func _section_eem_disembark_ingress() -> void:
	print("\n-- H2. enemy_ended_move after a disembark / ingress move --")
	_load(REACTIVE, 2, "Runt Swarm")
	var sid := _sid(2, "scarper-runt-swarm")
	var trukk: Dictionary = GS.state.units.U_TRUKK_A
	trukk["owner"] = 1
	var tpos := _pos(trukk.models[0])
	var cg: Dictionary = GS.state.units.U_CUSTODIAN_GUARD_C
	cg["embarked_in"] = "U_TRUKK_A"
	for m in cg.models:
		m["position"] = null
	trukk["transport_data"] = trukk.get("transport_data", {})
	trukk.transport_data["embarked_units"] = ["U_CUSTODIAN_GUARD_C"]
	# Gretchin C 6-7" from the Trukk, clear of everything else.
	_place_row("U_GRETCHIN_C", tpos.x / PX - 4.0, tpos.y / PX - 9.0, 1.2)
	var phase = _movement()
	_drain_start_window(phase)
	var payload: Dictionary = phase._ork11e_greedy_disembark_payload("U_CUSTODIAN_GUARD_C", ["U_CUSTODIAN_GUARD_C"], "U_TRUKK_A", 1)
	_check("setup: a legal disembark set-up exists", not payload.is_empty())
	var dres = phase.execute_action({"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_CUSTODIAN_GUARD_C", "player": 1, "payload": payload})
	_check("CONFIRM_DISEMBARK succeeds", dres.get("success", false), str(dres.get("error", "")))
	var near: bool = Movement._attached_within("U_CUSTODIAN_GUARD_C", "U_GRETCHIN_C", 8.0)
	_check("the disembarked unit ended within 8\" of Gretchin C", near)
	_check("disembark move ended -> enemy_ended_move pending for P2", _pending_id(phase) == "enemy_ended_move" and phase.get_pending_stratagem_window_decider() == 2, _pending_id(phase))
	_check("window ctx: move_type disembark, enemy = Custodian Guard C", str(_win_ctx(phase).get("move_type", "")) == "disembark" and str(_win_ctx(phase).get("enemy_unit_id", "")) == "U_CUSTODIAN_GUARD_C", str(_win_ctx(phase)))
	var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
	_check("SCARPER! offered on Gretchin C", "U_GRETCHIN_C" in _offer_targets(offers, sid), str(_offer_names(offers)))
	_decline(phase, 2, "enemy_ended_move")
	_check("declined: no second window for the same move", not phase.has_pending_stratagem_window() and phase._ork11e_eem_pending.is_empty())
	# Ingress: Custodian Guard D arrives from reserves 5" from the Gretchin.
	_load(REACTIVE, 2, "Runt Swarm")
	var cgd: Dictionary = GS.state.units.U_CUSTODIAN_GUARD_D
	cgd["status"] = GS.UnitStatus.IN_RESERVES
	var gpos := _pos(GS.state.units.U_GRETCHIN_C.models[0])
	phase = _movement()
	_drain_start_window(phase)
	var mps: Array = []
	for i in range(cgd.models.size()):
		mps.append(Vector2(gpos.x + (i * 1.8 - 3.6) * PX, gpos.y - 5.5 * PX))
	var ires: Dictionary = phase._process_place_reinforcement({"type": "PLACE_REINFORCEMENT", "unit_id": "U_CUSTODIAN_GUARD_D", "model_positions": mps})
	_check("reinforcement placed", ires.get("success", false), str(ires.get("error", "")))
	_settle(phase)
	_check("ingress move ended -> enemy_ended_move pending for P2", _pending_id(phase) == "enemy_ended_move" and str(_win_ctx(phase).get("move_type", "")) == "ingress", "%s %s" % [_pending_id(phase), str(_win_ctx(phase))])
	if phase.has_pending_stratagem_window():
		_decline(phase, 2, "enemy_ended_move")


func _section_whirligig() -> void:
	print("\n-- I. WHIRLIGIG EVASION (Flyboyz) --")
	for riled in [false, true]:
		_load(REACTIVE, 2, "Flyboyz")
		var sid := _sid(2, "whirligig-evasion-flyboyz")
		# Deffkoptas (75mm ovals) east of Custodian Guard F; F ends ~2" from them.
		_place_row("U_DEFFKOPTAS_A", 28.0, 14.0, 3.2)
		if riled:
			GS.state.units.U_DEFFKOPTAS_A.flags["waaagh_active"] = true
		var phase = _movement()
		_drain_start_window(phase)
		phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_F"})
		_settle(phase)
		var mv = _move_unit(phase, "U_CUSTODIAN_GUARD_F", Vector2(0, 3.0))
		_check("Custodes move confirmed", mv.get("success", false), str(mv))
		_settle(phase)
		var offers: Array = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
		_check("enemy_ended_move offers WHIRLIGIG on the Deffkoptas", _offer_targets(offers, sid) == ["U_DEFFKOPTAS_A"], str(_offer_names(offers)))
		if not riled:
			_check("NOT offered when the enemy ended beyond 8\" (Guard E)", SM.get_window_offers(2, "enemy_ended_move", {"phase": "movement", "enemy_unit_id": "U_CUSTODIAN_GUARD_E", "move_type": "normal"}).is_empty())
			_check("NOT offered on another unit type (Warbikers)", not "U_WARBIKERS_A" in _offer_targets(offers, sid))
		RE.set_test_seed(99)
		var cp2 := _cp(2)
		var use = _use(phase, 2, "enemy_ended_move", sid, "U_DEFFKOPTAS_A")
		_check("USE succeeds, P2 CP -1", use.get("success", false) and _cp(2) == cp2 - 1, str(use.get("error", "")))
		var cap := float(phase.active_moves.get("U_DEFFKOPTAS_A", {}).get("move_cap_inches", 0.0))
		if riled:
			var wl: Array = phase.dice_log.filter(func(d): return str(d.get("type", "")) == "WHIRLIGIG EVASION")
			_check("riled up: up to 6\" (no roll)", absf(cap - 6.0) < 0.01 and wl.size() == 1 and int(wl[0].roll) == 0, "%s %s" % [str(cap), str(wl)])
		else:
			_check("not riled up: up to D6\"", cap >= 1.0 and cap <= 6.0, str(cap))
		var gmv = _move_unit(phase, "U_DEFFKOPTAS_A", Vector2(minf(cap, 1.0) - 0.05, 0))
		_check("Deffkoptas reactive move confirmed", gmv.get("success", false), str(gmv))
		_check("the active player continues", phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_CUSTODIAN_GUARD_E"}).get("success", false))


# ---------------------------------------------------------------------------
func _section_where_dya_fink() -> void:
	print("\n-- J. WHERE D'YA FINK YOU'RE GOING? (Da Big Hunt) --")
	_load(REACTIVE, 2, "Da Big Hunt")
	var sid := _sid(2, "where-dya-fink-youre-going-da-big-hunt")
	_check("WDYF loaded for P2", sid != "")
	_check("Allarus engaged with the Beast Snagga Boyz", Movement.units_engaged_with_each_other("U_BEAST_SNAGGA_BOYZ_A", "U_ALLARUS_CUSTODIANS_A"))
	var phase = _movement()
	_drain_start_window(phase)
	# legacy Krump and Run name list no longer picks the codex row
	var kar = phase._check_krump_and_run_opportunity("U_ALLARUS_CUSTODIANS_A")
	_check("legacy Krump-and-Run path ignores the codex row", not kar.get("triggered", false) and not phase._awaiting_krump_and_run)
	var cp2 := _cp(2)
	var res = phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_ALLARUS_CUSTODIANS_A"})
	_check("BEGIN_FALL_BACK succeeds", res.get("success", false), str(res.get("error", "")))
	_check("enemy_selected_to_fall_back pending for P2 before the move is set up", _pending_id(phase) == "enemy_selected_to_fall_back" and not phase.active_moves.has("U_ALLARUS_CUSTODIANS_A"), _pending_id(phase))
	_check("offered on the engaged BEAST SNAGGA unit only", _offer_targets(phase.get_pending_stratagem_window().offers, sid) == ["U_BEAST_SNAGGA_BOYZ_A"])
	var use = _use(phase, 2, "enemy_selected_to_fall_back", sid, "U_BEAST_SNAGGA_BOYZ_A")
	_check("USE succeeds, P2 CP -1", use.get("success", false) and _cp(2) == cp2 - 1, str(use.get("error", "")))
	_check("fall-back resumed in desperate escape mode", str(phase.active_moves.get("U_ALLARUS_CUSTODIANS_A", {}).get("fall_back_mode", "")) == "desperate_escape", str(phase.active_moves.get("U_ALLARUS_CUSTODIANS_A", {}).get("fall_back_mode", "")))
	var hz: Dictionary = phase.active_moves.U_ALLARUS_CUSTODIANS_A.get("desperate_escape_ctx", {}).get("hazard", {})
	_check("one hazard roll per model (5), no extra rolls (not MONSTER/VEHICLE)", hz.get("rolls", []).size() == 5 and not hz.has("extra_rolls"), str(hz))
	# A/B: without the stratagem the default is ordered retreat.
	_load(REACTIVE, 2, "Da Big Hunt")
	var pb = _movement()
	_drain_start_window(pb)
	pb.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_ALLARUS_CUSTODIANS_A"})
	_decline(pb, 2, "enemy_selected_to_fall_back")
	_check("declined: ordered retreat (default)", str(pb.active_moves.U_ALLARUS_CUSTODIANS_A.get("fall_back_mode", "")) == "ordered_retreat")
	# MONSTER/VEHICLE: three extra rolls per BEAST SNAGGA unit, -1 while battle-shocked.
	_load(REACTIVE, 2, "Da Big Hunt")
	GS.state.units.U_ALLARUS_CUSTODIANS_A.meta.keywords.append("VEHICLE")
	GS.state.units.U_BEAST_SNAGGA_BOYZ_A.flags["ork11e_where_dya_fink"] = true
	var FB = MoveTypes.get_type("fall_back")
	_check("forced mode via the template", FB.select_mode("U_ALLARUS_CUSTODIANS_A", GS.state).mode == "desperate_escape")
	var extra: Dictionary = Movement.where_dya_fink_extra_hazard("U_ALLARUS_CUSTODIANS_A", GS.state)
	_check("VEHICLE engaged with 1 BEAST SNAGGA unit: 3 extra rolls, no modifier", int(extra.count) == 3 and int(extra.modifier) == 0, str(extra))
	RE.set_test_seed(5)
	var ctx = FB.before_moving("U_ALLARUS_CUSTODIANS_A", GS.state, RE.make_rng(), {"mode": "desperate_escape"})
	_check("hazard rolls = 5 per model + 3 extra", ctx.hazard.rolls.size() == 8 and ctx.hazard.extra_rolls.size() == 3, str(ctx.hazard))
	GS.state.units.U_ALLARUS_CUSTODIANS_A.flags["battle_shocked"] = true
	extra = Movement.where_dya_fink_extra_hazard("U_ALLARUS_CUSTODIANS_A", GS.state)
	_check("battle-shocked: -1 to those hazard rolls", int(extra.modifier) == -1, str(extra))
	# -1 makes a 3 fail: compare failures with forced dice.
	var shocked_unit = GS.state.units.U_ALLARUS_CUSTODIANS_A
	var AS = load("res://scripts/rules/AttackSequence.gd")
	var fixed := {"roll_d6": func(n): return [3, 3, 3]}
	var hz_mod = AS.hazard_rolls(shocked_unit, 3, _FixedRng.new([3, 3, 3]), -1)
	var hz_none = AS.hazard_rolls(shocked_unit, 3, _FixedRng.new([3, 3, 3]), 0)
	_check("a 3 fails at -1 (3 failures) but not unmodified (0)", int(hz_mod.failures) == 3 and int(hz_none.failures) == 0, "%s / %s" % [str(hz_mod), str(hz_none)])
	_check("MONSTER/VEHICLE hazard failures inflict 3 MW each", int(hz_mod.mortal_wounds) == 9, str(hz_mod))
	# Effect lasts the phase: a second enemy falling back from the same unit is forced too.
	SM.on_phase_end(PHASE_MOVEMENT)


class _FixedRng:
	var values: Array
	func _init(v: Array) -> void:
		values = v
	func roll_d6(n: int) -> Array:
		return values.slice(0, n)


# ---------------------------------------------------------------------------
func _section_while_their_backs() -> void:
	print("\n-- K. WHILE THEIR BACKS ARE TURNED (Taktikal Brigade) --")
	_load(REACTIVE, 2, "Taktikal Brigade")
	var sid := _sid(2, "while-their-backs-are-turned-taktikal-brigade")
	var phase = _movement()
	_drain_start_window(phase)
	_check("Boyz B engaged at the start of the phase", phase._engagement_at_phase_start.has("U_BOYZ_B"))
	# Custodian Guard A falls back away from the Boyz.
	phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_CUSTODIAN_GUARD_A"})
	while phase.has_pending_stratagem_window():
		_decline(phase, int(phase.get_pending_stratagem_window().player), _pending_id(phase))
	var fb = _move_unit(phase, "U_CUSTODIAN_GUARD_A", Vector2(0, -4.0))
	_check("Custodian Guard A fell back", fb.get("success", false), str(fb))
	while phase.has_pending_stratagem_window() and _pending_id(phase) == "enemy_ended_move":
		_decline(phase, 2, "enemy_ended_move")
	_check("Boyz B now unengaged", not Movement.is_attached_unit_engaged("U_BOYZ_B"))
	var mctx := {"phase": "movement", "engaged_at_phase_start": phase._engagement_at_phase_start.keys()}
	var offers = SM.get_window_offers(2, "movement_phase_end", mctx)
	_check("offered on Boyz B (engaged at start, unengaged now)", "U_BOYZ_B" in _offer_targets(offers, sid), str(offers))
	_check("NOT offered on Kommandos (not engaged at start)", not "U_KOMMANDOS_A" in _offer_targets(offers, sid))
	_check("NOT offered on still-engaged Nobz... (not BOYZ either)", not "U_NOBZ_A" in _offer_targets(offers, sid))
	_check("NOT offered to the active player", SM.get_window_offers(1, "movement_phase_end", mctx).is_empty())
	var cp2 := _cp(2)
	var end_res = phase.execute_action({"type": "END_MOVEMENT"})
	_check("END_MOVEMENT succeeds", end_res.get("success", false), str(end_res.get("error", "")))
	_check("movement_phase_end window pending for P2 (phase not ended)", _pending_id(phase) == "movement_phase_end" and phase.get_pending_stratagem_window_decider() == 2 and GS.get_current_phase() == PHASE_MOVEMENT, _pending_id(phase))
	var use = _use(phase, 2, "movement_phase_end", sid, "U_BOYZ_B")
	_check("USE succeeds, P2 CP -1", use.get("success", false) and _cp(2) == cp2 - 1, str(use.get("error", "")))
	_check("reactive 6\" move set up for the Boyz (+ Warboss)", absf(float(phase.active_moves.get("U_BOYZ_B", {}).get("move_cap_inches", 0)) - 6.0) < 0.01 and phase.active_moves.U_BOYZ_B.original_positions.has("U_WARBOSS_A:%s" % str(GS.state.units.U_WARBOSS_A.models[0].id)))
	_check("phase still Movement while the move is pending", GS.get_current_phase() == PHASE_MOVEMENT)
	var bmv = _move_unit(phase, "U_BOYZ_B", Vector2(0, 1.0))
	_check("Boyz reactive move confirmed", bmv.get("success", false), str(bmv))
	_check("then the Movement phase ends (Shooting)", GS.get_current_phase() == PHASE_SHOOTING, str(GS.get_current_phase()))


# ---------------------------------------------------------------------------
## WTBT set-up shared by K2: Taktikal Brigade P2, Custodian Guard A falls back
## from the Boyz so they are offered WHILE THEIR BACKS ARE TURNED at the end.
func _wtbt_setup() -> Node:
	_load(REACTIVE, 2, "Taktikal Brigade")
	var phase = _movement()
	_drain_start_window(phase)
	phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_CUSTODIAN_GUARD_A"})
	while phase.has_pending_stratagem_window():
		_decline(phase, int(phase.get_pending_stratagem_window().player), _pending_id(phase))
	_move_unit(phase, "U_CUSTODIAN_GUARD_A", Vector2(0, -4.0))
	while phase.has_pending_stratagem_window() and _pending_id(phase) == "enemy_ended_move":
		_decline(phase, 2, "enemy_ended_move")
	return phase


func _section_while_their_backs_host_path() -> void:
	print("\n-- K2. reverify:RV-2 networked host path: GameManager END_MOVEMENT --")
	var GM = root.get_node("GameManager")
	var sid := _sid(2, "while-their-backs-are-turned-taktikal-brigade")
	# (a) USE: the window opens on the host path and its follow-up ends the phase.
	var phase = _wtbt_setup()
	var mctx := {"phase": "movement", "engaged_at_phase_start": phase._engagement_at_phase_start.keys()}
	_check("WTBT offered on Boyz B at the end of this phase", "U_BOYZ_B" in _offer_targets(SM.get_window_offers(2, "movement_phase_end", mctx), sid))
	var cp2 := _cp(2)
	var res = GM.apply_action({"type": "END_MOVEMENT", "player": 1})
	_check("GameManager END_MOVEMENT succeeds", res.get("success", false), str(res.get("error", "")))
	_check("the phase did NOT end: movement_phase_end pending for P2", _pending_id(phase) == "movement_phase_end"
		and phase.get_pending_stratagem_window_decider() == 2 and GS.get_current_phase() == PHASE_MOVEMENT and PM.get_current_phase_instance() == phase,
		"pending=%s phase=%d" % [_pending_id(phase), GS.get_current_phase()])
	var stamp: Dictionary = res.get("stratagem_window_opened", {})
	_check("the result carries the window stamp for the client mirror", str(stamp.get("window_id", "")) == "movement_phase_end" and int(stamp.get("player", 0)) == 2, str(stamp))
	var phase_diff := false
	for d in res.get("diffs", res.get("changes", [])):
		if str(d.get("path", "")) == "meta.phase":
			phase_diff = true
	_check("no meta.phase diff while the window waits", not phase_diff)
	var use = GM.apply_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "movement_phase_end", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B", "context": {}})
	_check("USE through GameManager succeeds, P2 CP -1", use.get("success", false) and _cp(2) == cp2 - 1, str(use.get("error", "")))
	_check("the reactive move holds the phase", GS.get_current_phase() == PHASE_MOVEMENT and phase.active_moves.has("U_BOYZ_B"))
	var bmv = _move_unit(phase, "U_BOYZ_B", Vector2(0, 1.0))
	_check("Boyz reactive move confirmed", bmv.get("success", false), str(bmv))
	_check("then the Movement phase ends (Shooting)", GS.get_current_phase() == PHASE_SHOOTING, str(GS.get_current_phase()))
	# (b) DECLINE: the decision completes the phase.
	phase = _wtbt_setup()
	res = GM.apply_action({"type": "END_MOVEMENT", "player": 1})
	_check("(decline) END_MOVEMENT holds the phase for the window", res.get("success", false) and _pending_id(phase) == "movement_phase_end" and GS.get_current_phase() == PHASE_MOVEMENT)
	var dec = GM.apply_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": "movement_phase_end"})
	_check("(decline) DECLINE through GameManager ends the Movement phase", dec.get("success", false) and GS.get_current_phase() == PHASE_SHOOTING,
		"%s phase=%d" % [str(dec.get("error", "")), GS.get_current_phase()])
	# (c) No offers: END_MOVEMENT through GameManager still ends the phase at once,
	# with the meta.phase diff the client transitions from.
	_load(ACTIVE, 1, "War Horde")
	# 11e: P2 would be offered FIRE OVERWATCH (15.08) here — at 0 CP it is
	# not, so this stays the no-window path.
	GS.state.players["2"]["cp"] = 0
	phase = _movement()
	_drain_start_window(phase)
	res = GM.apply_action({"type": "END_MOVEMENT", "player": 1})
	var to_phase := -1
	for d in res.get("diffs", res.get("changes", [])):
		if str(d.get("path", "")) == "meta.phase":
			to_phase = int(d.get("value", -1))
	_check("no window: GameManager END_MOVEMENT ends the phase with a meta.phase diff", res.get("success", false) and GS.get_current_phase() == PHASE_SHOOTING and to_phase == PHASE_SHOOTING,
		"phase=%d diff=%d" % [GS.get_current_phase(), to_phase])


# ---------------------------------------------------------------------------
func _section_dread_power() -> void:
	print("\n-- L. DREAD POWER (Dread Mob, S panel) --")
	_load(ACTIVE, 1, "Dread Mob")
	var sid := _sid(1, "dread-power-dread-mob")
	PM.transition_to_phase(PHASE_COMMAND)
	var r = SM.can_use_stratagem(1, sid)
	_check("not usable in the Command phase", not r.can_use, str(r))
	var phase = _movement()
	_drain_start_window(phase)
	r = SM.can_use_stratagem(1, sid)
	_check("S panel probe (no target) ok in your Movement phase", r.can_use, str(r))
	_check("target: Deff Dread ok", SM.can_use_stratagem(1, sid, "U_DEFF_DREAD_A").can_use)
	_check("target: Battlewagon refused (not WALKER)", not SM.can_use_stratagem(1, sid, "U_BATTLEWAGON_A").can_use)
	_check("not usable by the opponent", not SM.can_use_stratagem(2, sid, "U_DEFF_DREAD_A").can_use)
	var cp0 := _cp(1)
	var res = phase.execute_action({"type": "USE_STRATAGEM", "stratagem_id": sid, "target_unit_id": "U_DEFF_DREAD_A"})
	_check("USE_STRATAGEM succeeds, CP -1", res.get("success", false) and _cp(1) == cp0 - 1, str(res.get("error", "")))
	var u = GS.state.units.U_DEFF_DREAD_A
	_check("riled up (Common.is_riled_up)", load("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd").is_riled_up(u))
	_check("5+ invulnerable save", int(u.flags.get("effect_invuln", 0)) == 5 and str(u.flags.get("effect_invuln_source", "")) == "Dread Power")
	_check("advance and charge + ranged [ASSAULT]", u.flags.get("effect_advance_and_charge", false) and u.flags.get("effect_advance_and_shoot", false))
	_check("Waaagh! state flag for the engine's Waaagh! consumers", u.flags.get("waaagh_active", false))
	# r2:F1 — riled up (11e) gives NO melee bonus: the +1 A / +1 S is the 10e
	# Waaagh! only. Same seed A/B: Dread Klaws vs the engaged Prosecutors.
	var dp_board: Dictionary = GS.create_snapshot()
	var dp_plain: Dictionary = dp_board.duplicate(true)
	for k in ["waaagh_active", "ork11e_riled_up", "ork11e_dread_power", "effect_invuln", "effect_invuln_source",
			"effect_advance_and_charge", "effect_advance_and_shoot", "ork11e_dread_power_assault"]:
		dp_plain.units.U_DEFF_DREAD_A.flags.erase(k)
	var dp_with: Dictionary = _dread_klaws_ab(dp_board)
	var dp_without: Dictionary = _dread_klaws_ab(dp_plain)
	_check("11e riled up: no +1 A (same number of melee hit dice, seed 555)", dp_with.hits > 0 and dp_with.hits == dp_without.hits, "with=%s without=%s" % [str(dp_with), str(dp_without)])
	_check("11e riled up: no +1 S (same wound-roll Strength)", dp_with.s > 0 and dp_with.s == dp_without.s, "with=%s without=%s" % [str(dp_with), str(dp_without)])
	_check("FactionAbilityManager.waaagh_melee_bonus_applies is false at 11e", not root.get_node("FactionAbilityManager").waaagh_melee_bonus_applies(u))
	# 10e engagement range is 1": close the fixture's 1" gap for the control.
	for bb in [dp_board, dp_plain]:
		for pm in bb.units.U_PROSECUTORS_A.models:
			pm.position = {"x": float(pm.position.x), "y": float(pm.position.y) - 0.6 * PX}
	GameConstants.edition = 10
	var dp_with10: Dictionary = _dread_klaws_ab(dp_board)
	var dp_without10: Dictionary = _dread_klaws_ab(dp_plain)
	GameConstants.edition = 11
	_check("10e control: the Waaagh! state still adds +1 A / +1 S", dp_with10.hits == dp_without10.hits + 1 and dp_with10.s == dp_without10.s + 1, "with=%s without=%s" % [str(dp_with10), str(dp_without10)])
	var eff = SM.active_effects.filter(func(e): return str(e.stratagem_id) == sid)
	_check("lasts until the start of your next Command phase", eff.size() == 1 and str(eff[0].expires) == "next_own_command_phase", str(eff))
	SM.on_phase_end(PHASE_MOVEMENT)
	SM.on_turn_start(2)
	_check("still riled up in the opponent's turn", u.flags.get("ork11e_riled_up", false) and int(u.flags.get("effect_invuln", 0)) == 5)
	SM.on_turn_start(1)
	_check("cleared at the start of your next turn", not u.flags.get("ork11e_riled_up", false) and not u.flags.has("effect_invuln") and not u.flags.get("waaagh_active", false))
	await _section_army_waaagh_11e()


## Deff Dread Dread Klaws vs Prosecutors with seed 555 -> {hits, s}.
func _dread_klaws_ab(board: Dictionary) -> Dictionary:
	var act := {"type": "FIGHT", "actor_unit_id": "U_DEFF_DREAD_A", "payload": {"assignments": [
		{"attacker": "U_DEFF_DREAD_A", "target": "U_PROSECUTORS_A", "weapon": "Dread Klaws"}]}}
	RE.set_test_seed(555)
	var res_m = RE.resolve_melee_attacks(act, board.duplicate(true), RE.RNGService.new())
	var out := {"hits": -1, "s": -1}
	for dd in res_m.get("dice", []):
		var ctx_name := str(dd.get("context", ""))
		if ctx_name == "hit_roll_melee":
			out.hits = (dd.get("rolls_raw", dd.get("rolls", [])) as Array).size()
		elif ctx_name in ["wound_roll_melee", "to_wound_melee", "wound_roll"]:
			out.s = int(dd.get("strength", -1))
	return out


## r2:F1 — the army Waaagh! (War Cry) at 11e: riled-up benefits only (5+ InSv,
## ranged [ASSAULT], advance-and-charge), no +1 A / +1 S, plus the Waaagh!
## ability's advance re-roll; the log text names the 11e benefits.
func _section_army_waaagh_11e() -> void:
	print("\n-- L2. army Waaagh! at 11e (riled up, no 10e melee bonus) --")
	_load(ACTIVE)
	var fam = root.get_node("FactionAbilityManager")
	fam._waaagh_used = {"1": false, "2": false}
	fam._waaagh_active = {"1": false, "2": false}
	fam.detect_faction_abilities(1)
	var boyz = GS.state.units.U_BOYZ_B
	boyz.flags.erase("effect_advance_and_shoot")
	var act = fam.activate_waaagh(1)
	_check("army Waaagh! called", act.get("success", false), str(act))
	var msg := str(act.get("message", ""))
	_check("Waaagh! message names the 11e benefits, not +1 S/A", "[ASSAULT]" in msg and not "+1 S/A" in msg, msg)
	_check("riled up: waaagh_active + 5+ invuln + advance-and-charge", boyz.flags.get("waaagh_active", false) and int(boyz.flags.get("effect_invuln", 0)) == 5 and boyz.flags.get("effect_advance_and_charge", false), str(boyz.flags))
	_check("riled up: ranged [ASSAULT] (effect_advance_and_shoot)", boyz.flags.get("effect_advance_and_shoot", false))
	_check("no 10e melee bonus at 11e", not fam.waaagh_melee_bonus_applies(boyz))
	GameConstants.edition = 10
	_check("10e: melee bonus applies", fam.waaagh_melee_bonus_applies(boyz))
	GameConstants.edition = 11
	fam.deactivate_waaagh(1)
	_check("Waaagh! over: the [ASSAULT] it granted is removed", not boyz.flags.get("effect_advance_and_shoot", false) and not boyz.flags.has(fam.WAAAGH_ASSAULT_MARKER), str(boyz.flags))
	# A unit whose [ASSAULT] came from elsewhere keeps it when the Waaagh! ends.
	fam._waaagh_used = {"1": false, "2": false}
	boyz.flags["effect_advance_and_shoot"] = true
	fam.activate_waaagh(1)
	fam.deactivate_waaagh(1)
	_check("other-source [ASSAULT] survives the Waaagh! clear", boyz.flags.get("effect_advance_and_shoot", false))
	boyz.flags.erase("effect_advance_and_shoot")
	# Real Movement phase: the Waaagh! ability's optional advance re-roll is
	# NOT applied automatically (deferred — it would replace the Command
	# Re-roll offer the T3 tutorial teaches): a 1-3 advance roll is kept as
	# rolled and the Command Re-roll is offered.
	var seed_low := -1
	var first_low := -1
	for seed_v in range(1, 200):
		var rng_probe = RE.RNGService.new(seed_v)
		var first_die: int = int(rng_probe.roll_d6(1)[0])
		if first_die <= 3:
			seed_low = seed_v
			first_low = first_die
			break
	var phase = _movement()
	_drain_start_window(phase)
	var r = phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_TANKBUSTAS_A", "payload": {"rng_seed": seed_low}})
	while phase.has_pending_stratagem_window():
		r = _decline(phase, int(phase.get_pending_stratagem_window().player), _pending_id(phase))
	_check("BEGIN_ADVANCE with a low first die succeeds", r.get("success", false) and seed_low > 0, str(r.get("error", "")))
	_check("low advance roll kept as rolled, Command Re-roll offered (no automatic Waaagh! re-roll)",
		phase._awaiting_reroll_decision and int(phase._reroll_pending_data.get("advance_roll", -1)) == first_low,
		"seed=%d first=%d pending=%s" % [seed_low, first_low, str(phase._reroll_pending_data)])


# ---------------------------------------------------------------------------
func _section_delicious_squigs() -> void:
	print("\n-- M. DELICIOUS EATING SQUIGS (Kult of Speed, S panel) --")
	_load(ACTIVE, 1, "Kult of Speed")
	var sid := _sid(1, "delicious-eating-squigs-kult-of-speed")
	var phase = _movement()
	_drain_start_window(phase)
	var rk := _pos(GS.state.units.U_RUKKATRUKK_SQUIGBUGGIES_A.models[0])
	_check("no ORKS INFANTRY within 3\" -> not usable", not SM.can_use_stratagem(1, sid, "U_RUKKATRUKK_SQUIGBUGGIES_A").can_use)
	# Tankbustas (W3) and Kommandos (W1) right next to the buggies; Breaka Boyz far away.
	_place_row("U_TANKBUSTAS_A", rk.x / PX - 3.5, rk.y / PX + 2.8, 1.7)
	_place_row("U_KOMMANDOS_A", rk.x / PX - 6.0, rk.y / PX + 4.6, 1.4)
	var tb: Array = GS.state.units.U_TANKBUSTAS_A.models
	tb[0]["current_wounds"] = 1      # boss nob W3: 2 lost
	tb[1]["current_wounds"] = 1      # tankbusta W2: 1 lost
	var ko: Array = GS.state.units.U_KOMMANDOS_A.models
	ko[0]["alive"] = false
	ko[0]["current_wounds"] = 0
	ko[1]["alive"] = false
	ko[1]["current_wounds"] = 0
	GS.state.units.U_BREAKA_BOYZ_A.models[0]["current_wounds"] = 1
	var targets: Array = Movement.delicious_squigs_targets("U_RUKKATRUKK_SQUIGBUGGIES_A", 1)
	_check("Tankbustas + Kommandos within 3\" are selected", "U_TANKBUSTAS_A" in targets and "U_KOMMANDOS_A" in targets and not "U_BREAKA_BOYZ_A" in targets, str(targets))
	_check("usable now", SM.can_use_stratagem(1, sid, "U_RUKKATRUKK_SQUIGBUGGIES_A").can_use)
	var cp0 := _cp(1)
	var res = phase.execute_action({"type": "USE_STRATAGEM", "stratagem_id": sid, "target_unit_id": "U_RUKKATRUKK_SQUIGBUGGIES_A"})
	_check("USE succeeds, CP -1", res.get("success", false) and _cp(1) == cp0 - 1, str(res.get("error", "")))
	_check("Tankbustas: 3 lost wounds healed (02.02.04)", int(tb[0].current_wounds) == 3 and int(tb[1].current_wounds) == 2, "%d/%d" % [int(tb[0].current_wounds), int(tb[1].current_wounds)])
	_check("Kommandos: full wounds -> two destroyed models revived with 1 wound (third heal wasted)", ko[0].alive and ko[1].alive and int(ko[0].current_wounds) == 1 and int(ko[1].current_wounds) == 1)
	_check("units beyond 3\" untouched", int(GS.state.units.U_BREAKA_BOYZ_A.models[0].current_wounds) == 1)
	var hd: Dictionary = Movement.heal_unit_diffs("U_WARBOSS_A", 3)
	_check("heal never exceeds starting wounds / revives no CHARACTER model", hd.healed == 0 and hd.revived == 0, str(hd))
	await _section_delicious_squigs_placement()


## r5:F1 — 01.02.03: a revived model is SET UP in coherency with models that
## started the phase on the battlefield (not where it died after its unit
## moved), never overlapping a model, never engaging a new enemy unit; with no
## legal spot it is not revived.
func _section_delicious_squigs_placement() -> void:
	print("\n-- M2. DELICIOUS EATING SQUIGS revive set-up (01.02.03) --")
	var AS = load("res://scripts/rules/AttackSequence.gd")
	var meas = root.get_node("Measurement")
	_load(ACTIVE, 1, "Kult of Speed")
	var sid := _sid(1, "delicious-eating-squigs-kult-of-speed")
	var phase = _movement()
	_drain_start_window(phase)
	var bm: Array = GS.state.units.U_RUKKATRUKK_SQUIGBUGGIES_A.models
	for i in range(bm.size()):
		bm[i]["position"] = {"x": (6.0 + i * 3.5) * PX, "y": 57.5 * PX}
	var ko: Array = GS.state.units.U_KOMMANDOS_A.models
	for i in range(ko.size()):
		ko[i]["position"] = {"x": (2.0 + (i % 5) * 1.4) * PX, "y": (49.0 - int(i / 5) * 1.4) * PX}
	var last: int = ko.size() - 1
	ko[last]["alive"] = false
	ko[last]["current_wounds"] = 0
	var death := _pos(ko[last])
	phase.game_state_snapshot = GS.create_snapshot()
	# The survivors make a REAL 4" normal move towards the buggies; the dead model stays behind.
	var bg = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_KOMMANDOS_A"})
	_check("BEGIN_NORMAL_MOVE Kommandos", bg.get("success", false), str(bg.get("error", bg.get("errors", ""))))
	while phase.has_pending_stratagem_window():
		_decline(phase, int(phase.get_pending_stratagem_window().player), _pending_id(phase))
	var mv = _move_unit(phase, "U_KOMMANDOS_A", Vector2(0, 4.0))
	_settle(phase)
	while phase.has_pending_stratagem_window():
		_decline(phase, int(phase.get_pending_stratagem_window().player), _pending_id(phase))
	_check("survivors moved 4\" (real BEGIN/STAGE/CONFIRM)", mv.get("success", false), str(mv.get("error", "")))
	_check("Kommandos now within 3\" of the buggies", "U_KOMMANDOS_A" in Movement.delicious_squigs_targets("U_RUKKATRUKK_SQUIGBUGGIES_A", 1))
	# Then an unengaged enemy steps in behind the moved unit (setup), between it
	# and where the model died: the nearest spots behind the rear rank would
	# engage a NEW enemy unit (01.02.03), so the set-up must avoid them.
	var cg: Array = GS.state.units.U_CUSTODIAN_GUARD_E.models
	for i in range(cg.size()):
		cg[i]["position"] = {"x": (4.0 + i * 1.7) * PX, "y": 47.4 * PX}
	_check("setup: the Custodian Guard is not engaged with the Kommandos", not root.get_node("RulesEngine").is_unit_engaged("U_KOMMANDOS_A", GS.state) if root.get_node("RulesEngine").has_method("is_unit_engaged") else true)
	var preview: Array = Movement.delicious_squigs_preview("U_RUKKATRUKK_SQUIGBUGGIES_A", 1)
	var pv_pos = null
	for e in preview:
		if str(e.unit_id) == "U_KOMMANDOS_A" and not (e.placements as Array).is_empty():
			pv_pos = e.placements[0].position
	_check("preview: one Kommando revived with a set-up position", pv_pos != null, str(preview))
	var res = phase.execute_action({"type": "USE_STRATAGEM", "stratagem_id": sid, "target_unit_id": "U_RUKKATRUKK_SQUIGBUGGIES_A"})
	_check("DES used", res.get("success", false), str(res.get("error", "")))
	var rv: Dictionary = ko[last]
	var rv_pos := _pos(rv)
	_check("revived model is alive with 1 wound", rv.get("alive", false) and int(rv.get("current_wounds", 0)) == 1)
	_check("revived model was set up (not left where it died, 4\" behind its unit)", rv_pos.distance_to(death) > 1.0, "death=%s now=%s" % [str(death / PX), str(rv_pos / PX)])
	_check("set-up position = the preview shown to the player", pv_pos != null and rv_pos.distance_to(pv_pos) < 0.5, "%s vs %s" % [str(rv_pos), str(pv_pos)])
	var coh = AS.check_attached_unit_coherency("U_KOMMANDOS_A", GS.state.units)
	_check("unit coherent after DES (no End-of-Turn removal)", coh.coherent, str(coh.get("merged_offenders", [])))
	var overlap := false
	var engages_new := false
	for uid in GS.state.units:
		for m in GS.state.units[uid].models:
			if m == rv or not m.get("alive", true) or m.get("position") == null:
				continue
			if meas.models_overlap(rv, m):
				overlap = true
			if uid == "U_CUSTODIAN_GUARD_E" and meas.is_in_engagement_range_shape_aware(rv, m):
				engages_new = true
	_check("revived model overlaps no model", not overlap)
	_check("revived model is not within Engagement Range of the unengaged Custodian Guard", not engages_new)
	# No legal spot: a unit set up this phase (disembarked) has no model that
	# started the phase on the battlefield -> nothing to set up against.
	_load(ACTIVE, 1, "Kult of Speed")
	phase = _movement()
	_drain_start_window(phase)
	ko = GS.state.units.U_KOMMANDOS_A.models
	ko[0]["alive"] = false
	ko[0]["current_wounds"] = 0
	GS.state.units.U_KOMMANDOS_A["disembarked_this_phase"] = true
	var hd: Dictionary = Movement.heal_unit_diffs("U_KOMMANDOS_A", 3)
	_check("no model started the phase on the battlefield -> revive skipped (no legal spot)", hd.revived == 0 and hd.no_room >= 1 and not ko[0].get("alive", true), str(hd))
	GS.state.units.U_KOMMANDOS_A.erase("disembarked_this_phase")


# ---------------------------------------------------------------------------
## Place every enemy (P2) unit in a row `dist` inches from `uid`'s first model
## (along whichever y direction stays on the board), nudging until the closest
## base-to-base gap is between lo and hi inches (OrkCodexMovement._enemy_within).
func _enemies_at_gap(Mv, uid: String, lo: float, hi: float) -> bool:
	var wb := _pos(GS.state.units[uid].models[0]) / PX
	var dir := 1.0 if wb.y < 30.0 else -1.0
	var dist := (lo + hi) * 0.5 + 2.0
	for _i in range(24):
		var row_y := wb.y + dir * dist
		for eid in GS.state.units:
			if int(GS.state.units[eid].get("owner", 0)) == 2:
				_place_row(str(eid), clampf(wb.x - 2.0, 2.0, 38.0), row_y, 0.0)
		var near: bool = Mv._enemy_within(uid, 1, lo)
		var far_ok: bool = Mv._enemy_within(uid, 1, hi)
		if not near and far_ok:
			return true
		dist += 0.25 if near else -0.25
	return false

## ai:AI-08 — movement-group ai_score: FUNGUS-FUEL INJECTION on a Normal move
## only when the extra 2" brings charge range (for a unit with charge-worthy
## melee) or an objective into reach; SCARPER! only when the enemy that ended
## its move could still charge.
func _section_ai_08_movement_scores(ADM, ffi: String) -> void:
	var Mv = load("res://scripts/stratagems/ork_codex/OrkCodexMovement.gd")
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	var dd := "U_DEFF_DREAD_A"
	var ctx_n := {"unit_id": dd, "move_type": "normal"}
	var m := float(GS.state.units[dd].meta.stats.move)
	_check("AI-08 precondition: Deff Dread (Dread Klaws S12) has charge-worthy melee and M > 0", m > 0.0 and Mv._charge_worthy_melee(dd), str(m))
	_check("AI-08: Mek Gunz (S2 A1 shivs) are not charge-worthy melee", not Mv._charge_worthy_melee("U_MEK_GUNZ_A"))
	_check("AI-08: Warbikers (S4 A2 close combat weapon) are not charge-worthy melee", not Mv._charge_worthy_melee("U_WARBIKERS_A"))
	# Closest enemy at M+7 < gap <= M+9: only the FFI +2" puts it in charge range.
	var placed := _enemies_at_gap(Mv, dd, m + 7.0 + 0.2, m + 9.0 - 0.2)
	var obj_gain: bool = Mv._uncontrolled_objective_within(dd, 1, m + 5.0) and not Mv._uncontrolled_objective_within(dd, 1, m + 3.0)
	_check("AI-08 setup: closest enemy between M+7\" and M+9\" of the Deff Dread", placed, "obj_gain=%s" % obj_gain)
	var s := float(Codex.ai_score(SM.get_stratagem(ffi), 1, dd, "unit_selected_to_move", ctx_n))
	_check("AI-08: FFI normal-move score 2.5 when +2\" reaches charge range", absf(s - 2.5) < 0.01, str(s))
	var o = SM.get_window_offers(1, "unit_selected_to_move", ctx_n)
	var d = ADM.decide_window_stratagem(1, "unit_selected_to_move", o, ctx_n)
	_check("AI-08: AI uses FFI on that normal move", d.get("use", false) and str(d.get("stratagem_id", "")) == ffi, str(d))
	# Closest enemy already within M+7: the bonus is wasted.
	placed = _enemies_at_gap(Mv, dd, m + 3.0, m + 6.5)
	obj_gain = Mv._uncontrolled_objective_within(dd, 1, m + 5.0) and not Mv._uncontrolled_objective_within(dd, 1, m + 3.0)
	_check("AI-08 setup: enemy already in reach without the bonus (no objective gain)", placed and not obj_gain, "placed=%s obj_gain=%s" % [placed, obj_gain])
	s = float(Codex.ai_score(SM.get_stratagem(ffi), 1, dd, "unit_selected_to_move", ctx_n))
	_check("AI-08: FFI normal-move score 0 when the enemy is already in reach", s == 0.0, str(s))
	# Same charge-range gap for the Warbikers: no charge-worthy melee -> no CP.
	var wctx := {"unit_id": "U_WARBIKERS_A", "move_type": "normal"}
	var wm := float(GS.state.units.U_WARBIKERS_A.meta.stats.move)
	placed = _enemies_at_gap(Mv, "U_WARBIKERS_A", wm + 7.0 + 0.2, wm + 9.0 - 0.2)
	obj_gain = Mv._uncontrolled_objective_within("U_WARBIKERS_A", 1, wm + 5.0) and not Mv._uncontrolled_objective_within("U_WARBIKERS_A", 1, wm + 3.0)
	s = float(Codex.ai_score(SM.get_stratagem(ffi), 1, "U_WARBIKERS_A", "unit_selected_to_move", wctx))
	_check("AI-08: Warbikers at the same gap (no objective gain) -> FFI score 0", placed and not obj_gain and s == 0.0, "placed=%s obj_gain=%s s=%s" % [placed, obj_gain, s])
	# SCARPER!: the enemy Custodian Guard C ended ~7" from Gretchin C and is
	# not engaged (Tankbustas / Flash Gitz sit at y ~44.3").
	_load(REACTIVE, 2, "Runt Swarm")
	_place_row("U_CUSTODIAN_GUARD_C", 35.0, 39.5, 1.8)
	PM.transition_to_phase(PHASE_MOVEMENT)
	var sc := _sid(2, "scarper-runt-swarm")
	var sctx := {"phase": "movement", "enemy_unit_id": "U_CUSTODIAN_GUARD_C", "move_type": "normal"}
	_check("AI-08 precondition: Gretchin C not on an objective", not Mv._unit_in_range_of_any_objective("U_GRETCHIN_C"))
	s = float(Codex.ai_score(SM.get_stratagem(sc), 2, "U_GRETCHIN_C", "enemy_ended_move", sctx))
	_check("AI-08: SCARPER! score 2.0 when the enemy can still charge", absf(s - 2.0) < 0.01,
		"%s eligible=%s within12=%s status=%s flags=%s" % [s, RE.eligible_to_charge("U_CUSTODIAN_GUARD_C", GS.state), Mv._attached_within("U_CUSTODIAN_GUARD_C", "U_GRETCHIN_C", 12.0), GS.state.units.U_CUSTODIAN_GUARD_C.get("status"), GS.state.units.U_CUSTODIAN_GUARD_C.get("flags")])
	o = SM.get_window_offers(2, "enemy_ended_move", sctx)
	d = ADM.decide_window_stratagem(2, "enemy_ended_move", o, sctx)
	_check("AI-08: AI scarpers from a charge threat", d.get("use", false) and str(d.get("stratagem_id", "")) == sc, str(d))
	var cf: Dictionary = GS.state.units.U_CUSTODIAN_GUARD_C.flags
	cf["advanced"] = true
	cf["cannot_charge"] = true
	s = float(Codex.ai_score(SM.get_stratagem(sc), 2, "U_GRETCHIN_C", "enemy_ended_move", sctx))
	_check("AI-08: SCARPER! score 0 when the enemy advanced (cannot charge)", s == 0.0, str(s))
	o = SM.get_window_offers(2, "enemy_ended_move", sctx)
	d = ADM.decide_window_stratagem(2, "enemy_ended_move", o, sctx)
	_check("AI-08: AI keeps its CP when there is no charge threat", not d.get("use", true), str(d))
	cf.erase("advanced")
	cf.erase("cannot_charge")
	_load(ACTIVE, 1, "War Horde")
	PM.transition_to_phase(PHASE_MOVEMENT)

func _section_ai() -> void:
	print("\n-- N. AI decision paths --")
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	_load(ACTIVE, 1, "War Horde")
	PM.transition_to_phase(PHASE_MOVEMENT)
	var ffi := _sid(1, "fungus-fuel-injection-war-horde")
	var o = SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_WARBIKERS_A", "move_type": "advance"})
	var d = ADM.decide_window_stratagem(1, "unit_selected_to_move", o, {"unit_id": "U_WARBIKERS_A", "move_type": "advance"})
	_check("AI uses FFI for an advance", d.get("use", false) and str(d.get("stratagem_id", "")) == ffi, str(d))
	o = SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_WARBIKERS_A", "move_type": "normal"})
	d = ADM.decide_window_stratagem(1, "unit_selected_to_move", o, {"unit_id": "U_WARBIKERS_A", "move_type": "normal"})
	_check("AI declines FFI for a normal move when +2\" changes nothing (fixture positions)", not d.get("use", true), str(d))
	_section_ai_08_movement_scores(ADM, ffi)
	# DUBIOUS RESTRAINT at the end of the phase.
	_load(ACTIVE, 1, "Taktikal Brigade")
	MM._sticky_objectives.clear()
	MM.check_all_objectives()
	PM.transition_to_phase(PHASE_MOVEMENT)
	var p = PM.get_current_phase_instance()
	_drain_start_window(p)
	var dr := _sid(1, "dubious-restraint-taktikal-brigade")
	o = SM.get_window_offers(1, "movement_phase_end", {"phase": "movement", "engaged_at_phase_start": []})
	d = ADM.decide_window_stratagem(1, "movement_phase_end", o, {"phase": "movement"})
	_check("AI secures a controlled objective at the end of the phase", d.get("use", false) and str(d.get("stratagem_id", "")) == dr, str(d))
	# AI at phase start through the phase (synchronous; applied at entry).
	_load(ACTIVE, 1, "Taktikal Brigade")
	MM._sticky_objectives.clear()
	MM.check_all_objectives()
	_set_ai(true, false)
	PM.transition_to_phase(PHASE_MOVEMENT)
	var ps = PM.get_current_phase_instance()
	_set_ai(false, false)
	_check("AI never leaves a movement_phase_start window pending", not ps.has_pending_stratagem_window())
	# WDYF AI score: 5 Allarus models -> worth it; a lone character -> not.
	_load(REACTIVE, 2, "Da Big Hunt")
	PM.transition_to_phase(PHASE_MOVEMENT)
	var wd := _sid(2, "where-dya-fink-youre-going-da-big-hunt")
	o = SM.get_window_offers(2, "enemy_selected_to_fall_back", {"phase": "movement", "enemy_unit_id": "U_ALLARUS_CUSTODIANS_A"})
	d = ADM.decide_window_stratagem(2, "enemy_selected_to_fall_back", o, {"enemy_unit_id": "U_ALLARUS_CUSTODIANS_A"})
	_check("AI forces a 5-model unit into desperate escape", d.get("use", false) and str(d.get("stratagem_id", "")) == wd, str(d))
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	var lone = Codex.ai_score(SM.get_stratagem(wd), 2, "U_BEAST_SNAGGA_BOYZ_A", "enemy_selected_to_fall_back", {"enemy_unit_id": "U_BLADE_CHAMPION_A"})
	_check("a lone character is not worth it (score < 2)", lone < 2.0, str(lone))
	# DREAD POWER proactive (panel) heuristic.
	_load(ACTIVE, 1, "Dread Mob")
	PM.transition_to_phase(PHASE_MOVEMENT)
	_drain_start_window(PM.get_current_phase_instance())
	var pa = ADM.evaluate_proactive_faction_stratagems(GS.create_snapshot(), 1, "movement")
	_check("AI proactive: DREAD POWER on a walker", str(pa.get("stratagem_id", "")) == _sid(1, "dread-power-dread-mob") and str(pa.get("target_unit_id", "")) in ["U_DEFF_DREAD_A", "U_KILLA_KANS_A"], str(pa))

extends SceneTree

# WP-G3 — Codex: Orks (11e) movement gaps:
#   A-H  PULSE JET (Wazdakka Gutsmek; Full Throttle "pulse") — the Ork army
#        rule's PULSE JET MOVE (scripts/rules/movetypes/PulseJetMove.gd, driven
#        by MovementPhase as mode PULSE_JET): eligibility (engine not chosen,
#        engaged, already moving), the pulse roll + 18" cap, through models and
#        terrain, must end unengaged, AFTER effects (no charge / no action,
#        -1 to be hit through RulesEngine's aggregator + ledger) and the expiry
#        of the -1 at the start of the owner's next turn; AI paths.
#   J    RUNNIN' WIV DA HERD (Painboss) keyword swap: attach / detach /
#        bodyguard destroyed, not for a non-MOUNTED bodyguard, the BasePhase
#        after-action hook and the phase-transition hook.
#   K    GET OUT DA WAY! (Nobz) + the 11e 03 charge path rule: through enemy
#        non-MONSTER/VEHICLE models, never through MONSTER/VEHICLE ones, other
#        units blocked by enemy models, friendly models never block; the real
#        DECLARE / ROLL / APPLY_CHARGE_MOVE flow and the AI charge planner.
#
# Fixtures: tests/saves/ork11e_g3_{pulse,herd,charge}.w40ksave
# (tests/helpers/gen_ork11e_g3_fixtures.gd).
#
# Usage: godot --headless --path 40k --script tests/test_codex11e_g3_ork_movement.gd

const PX := 40.0
const P_CMD := 6
const P_MOV := 7
const P_SHOOT := 8
const P_CHG := 9
const P_FIGHT := 10
const WAZ := "U_WAZDAKKA_GUTSMEK_A"
const CUS := "U_CUSTODIAN_GUARD_B"

var passed := 0
var failed := 0
var GS = null
var SM = null
var RE = null
var PM = null
var OA = null


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

func _load(fixture: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	var ok: bool = slm.load_game_from_file_path("res://tests/saves/%s.w40ksave" % fixture)
	GameConstants.edition = 11
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	RE.set_test_seed(-1)
	return ok

func _u(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})

func _flag(uid: String, f: String, def = null):
	return _u(uid).get("flags", {}).get(f, def)

func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p

func _kw(uid: String) -> Array:
	return _u(uid).get("meta", {}).get("keywords", [])

func _decline_windows(phase) -> void:
	for _i in range(8):
		if not phase.has_pending_stratagem_window():
			return
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 1)), "window_id": str(w.get("window_id", ""))})

func _settle(phase) -> void:
	for _i in range(6):
		if phase.get("_awaiting_fire_overwatch") or phase.get("_awaiting_overwatch_decision"):
			phase.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": phase._fire_overwatch_player})
		elif phase.get("_awaiting_krump_and_run"):
			phase.execute_action({"type": "DECLINE_KRUMP_AND_RUN"})
		elif phase.get("_awaiting_scatter"):
			phase.execute_action({"type": "DECLINE_SCATTER"})
		elif phase.has_pending_stratagem_window():
			_decline_windows(phase)
		else:
			return

func _to(phase_id: int, active: int = 1):
	GS.state.meta["active_player"] = active
	PM.transition_to_phase(phase_id)
	var ph = PM.get_current_phase_instance()
	_decline_windows(ph)
	return ph

## Give Wazdakka the Full Throttle engine through the real ability use
## (battle_shock_step_start window card, variant).
func _full_throttle(variant: String) -> Dictionary:
	GS.state.meta["phase"] = P_CMD
	GS.state.meta["active_player"] = 1
	return SM.use_stratagem(1, OA.sid_of("full_throttle"), WAZ, {"window_id": "battle_shock_step_start", "variant_id": variant})

## A seed whose first D6 (RNGService.new(seed)) satisfies pred.
func _seed_d6(pred: Callable, n: int = 1) -> int:
	for s in range(1, 2000):
		var r: Array = RE.RNGService.new(s).roll_d6(n)
		if pred.call(r):
			return s
	return -1

func _offered(phase, type: String, uid: String) -> bool:
	for a in phase.get_available_actions():
		if str(a.get("type", "")) == type and str(a.get("actor_unit_id", "")) == uid:
			return true
	return false

func _stage(phase, uid: String, model: Dictionary, dest: Vector2) -> Dictionary:
	return phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": uid,
		"payload": {"model_id": str(model.id), "dest": [dest.x, dest.y], "rotation": float(model.get("rotation", 0.0))}})


# ---------------------------------------------------------------------------
func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	PM = root.get_node("PhaseManager")
	OA = load("res://scripts/codex/orks/OrkAbilities11e.gd")
	_section_registry()
	_section_pulse_eligibility()
	_section_pulse_move()
	_section_pulse_expiry()
	_section_pulse_ai()
	_section_herd()
	_section_get_out_da_way()


func _section_registry() -> void:
	print("\n--- A. registry ---")
	var mt = MoveTypes.get_type("pulse_jet")
	_check("MoveTypes registers pulse_jet (PulseJetMove)", mt != null and mt.id == "pulse_jet")
	_check("max distance = 18\" + pulse roll", mt != null and is_equal_approx(mt.max_distance_inches({}, {"pulse_roll": 4}), 22.0))
	var ctx: Dictionary = mt.before_moving("", {}, RE.RNGService.new(7), {})
	_check("BEFORE MOVING: a pulse roll of one D6", int(ctx.get("pulse_roll", 0)) >= 1 and int(ctx.get("pulse_roll", 0)) <= 6, str(ctx))
	_check("pulse_jet is not one of the four basic moves", not "pulse_jet" in MoveTypes.available_for(WAZ, {"units": {}}))


func _section_pulse_eligibility() -> void:
	print("\n--- B. Pulse Jet eligibility ---")
	_load("ork11e_g3_pulse")
	var ph = _to(P_MOV)
	_check("no Full Throttle engine: not eligible", not MoveTypes.get_type("pulse_jet").eligible(WAZ, GS.state).eligible)
	_check("no Full Throttle engine: BEGIN_PULSE_JET_MOVE refused", not ph.execute_action({"type": "BEGIN_PULSE_JET_MOVE", "actor_unit_id": WAZ}).get("success", false))
	_check("no Full Throttle engine: not offered", not _offered(ph, "BEGIN_PULSE_JET_MOVE", WAZ))
	_load("ork11e_g3_pulse")
	var ft := _full_throttle("turbo")
	_check("Full Throttle turbo used", ft.get("success", false), str(ft))
	ph = _to(P_MOV)
	_check("Turbo Engine chosen: no pulse jet move", not MoveTypes.get_type("pulse_jet").eligible(WAZ, GS.state).eligible)
	_load("ork11e_g3_pulse")
	GS.state.meta["phase"] = P_CMD
	var ft_offer: Array = OA.window_offers(1, "battle_shock_step_start", {"window_id": "battle_shock_step_start"}).filter(func(o): return str(o.get("stratagem_id", "")) == OA.sid_of("full_throttle"))
	var ft_vars: Array = ft_offer[0].targets[0].get("variants", []).map(func(v): return str(v.id)) if not ft_offer.is_empty() else []
	_check("Full Throttle card offers the Pulse Jet variant", "pulse" in ft_vars, str(ft_vars))
	ft = _full_throttle("pulse")
	_check("Full Throttle pulse used (real ability use)", ft.get("success", false) and OA.engine_of(WAZ) == "pulse", str(ft))
	ph = _to(P_MOV)
	_check("pulse engine: eligible", MoveTypes.get_type("pulse_jet").eligible(WAZ, GS.state).eligible)
	_check("pulse engine: offered in get_available_actions", _offered(ph, "BEGIN_PULSE_JET_MOVE", WAZ))
	_check("not offered for a unit without the ability (Boyz)", not _offered(ph, "BEGIN_PULSE_JET_MOVE", "U_BOYZ_C"))
	# Engaged: move the Custodian Guard into engagement range.
	var keep: Array = []
	var wpos := _pos(_u(WAZ).models[0])
	for m in _u(CUS).models:
		keep.append(m.position.duplicate())
	_u(CUS).models[0]["position"] = {"x": wpos.x, "y": wpos.y + 3.4 * PX}
	_check("engaged Wazdakka: not eligible (if this unit is unengaged)", RE.is_unit_engaged(WAZ, GS.state) and not MoveTypes.get_type("pulse_jet").eligible(WAZ, GS.state).eligible)
	_check("engaged Wazdakka: BEGIN_PULSE_JET_MOVE refused", not ph.execute_action({"type": "BEGIN_PULSE_JET_MOVE", "actor_unit_id": WAZ}).get("success", false))
	for i in range(keep.size()):
		_u(CUS).models[i]["position"] = keep[i]
	# Opponent's turn: not offered (own Movement phase only).
	GS.state.meta["active_player"] = 2
	_check("opponent's Movement phase: refused", not ph._validate_begin_pulse_jet_move({"actor_unit_id": WAZ}).get("valid", false))
	GS.state.meta["active_player"] = 1
	# Selected to make a normal move and a model already moved: no switch.
	ph.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": WAZ})
	_decline_windows(ph)
	_check("normal move begun, no model moved: still offered", ph._validate_begin_pulse_jet_move({"actor_unit_id": WAZ}).get("valid", false))
	var m0: Dictionary = _u(WAZ).models[0]
	var st := _stage(ph, WAZ, m0, _pos(m0) + Vector2(-2.0 * PX, 0))
	_check("(staged a 2\" normal move)", st.get("success", false), str(st))
	_check("a model already moved: pulse jet refused", not ph._validate_begin_pulse_jet_move({"actor_unit_id": WAZ}).get("valid", false))


func _begin_pulse(ph, roll: int) -> Dictionary:
	var seed := _seed_d6(func(r): return int(r[0]) == roll)
	var r = ph.execute_action({"type": "BEGIN_PULSE_JET_MOVE", "actor_unit_id": WAZ, "payload": {"rng_seed": seed}})
	_decline_windows(ph)
	return r


func _section_pulse_move() -> void:
	print("\n--- C-G. Pulse Jet move ---")
	_load("ork11e_g3_pulse")
	_full_throttle("pulse")
	var ph = _to(P_MOV)
	ph.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": WAZ})  # what selecting the unit does
	_decline_windows(ph)
	var r := _begin_pulse(ph, 2)
	var md: Dictionary = ph.active_moves.get(WAZ, {})
	_check("BEGIN_PULSE_JET_MOVE succeeds (replacing the selection's normal move)", r.get("success", false), str(r.get("error", "")))
	_check("mode PULSE_JET, mode locked", str(md.get("mode", "")) == "PULSE_JET" and bool(md.get("mode_locked", false)))
	_check("pulse roll 2 -> cap 20\"", int(md.get("pulse_roll", 0)) == 2 and is_equal_approx(float(md.get("move_cap_inches", 0)), 20.0), str(md.get("move_cap_inches")))
	_check("flags.move_cap_inches = 20", is_equal_approx(float(_flag(WAZ, "move_cap_inches", 0)), 20.0))
	_check("pulse roll in the dice log", ph.get_dice_log().any(func(d): return str(d.get("type", "")) == "Pulse roll"))
	_check("cannot switch back to a normal move", not ph.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": WAZ}).get("success", false))
	_check("cannot advance instead", not ph.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": WAZ}).get("success", false))
	_check("no second pulse roll", not ph.execute_action({"type": "BEGIN_PULSE_JET_MOVE", "actor_unit_id": WAZ}).get("success", false))
	var m0: Dictionary = _u(WAZ).models[0]
	var p0 := _pos(m0)
	# D. Through models: straight down across Custodian Guard B.
	var dest := p0 + Vector2(0, 19.5 * PX)
	_check("(the straight path crosses Custodian Guard B's bases)", ph._path_crosses_enemy_bases(p0, dest, WAZ, m0))
	_check("a NORMAL move may not cross them (gate on)", not ph._o6_moves_through_models(WAZ, {"mode": "NORMAL"}))
	_check("a PULSE_JET move moves through all models (gate off)", ph._o6_moves_through_models(WAZ, md))
	# E. Terrain: a tall dense wall across the path; Wazdakka is a VEHICLE.
	var TM = root.get_node("TerrainManager")
	var saved: Array = TM.terrain_features.duplicate(true)
	var wall := {"id": "g3_wall", "type": "ruins", "category": "dense", "height_category": "tall", "height": 5.0, "height_inches": 5.0,
		"piece_class": "feature", "polygon": PackedVector2Array([p0 + Vector2(-140, 4.0 * PX), p0 + Vector2(140, 4.0 * PX), p0 + Vector2(140, 4.6 * PX), p0 + Vector2(-140, 4.6 * PX)])}
	TM.terrain_features.append(wall)
	var gate_normal = ph._check_dense_terrain_gate(WAZ, {"mode": "NORMAL"}, p0, dest, m0)
	var gate_pulse = ph._check_dense_terrain_gate(WAZ, md, p0, dest, m0)
	_check("dense wall blocks a VEHICLE's normal move (control)", not gate_normal.valid, str(gate_normal))
	_check("pulse jet moves horizontally through all terrain categories", gate_pulse.valid, str(gate_pulse))
	_check("pulse jet ignores vertical distance / terrain penalty (0\")", is_equal_approx(ph._get_movement_terrain_penalty(p0, dest, WAZ, false), 0.0))
	# C. Distance: over the cap refused.
	var over = _stage(ph, WAZ, m0, p0 + Vector2(0, 20.6 * PX))
	_check("20.6\" > 20\" cap: refused", not over.get("success", false))
	# F. Must end unengaged: next to the Custodians.
	var cpos := _pos(_u(CUS).models[1])
	var near = _stage(ph, WAZ, m0, Vector2(cpos.x, cpos.y + 4.0 * PX))
	_check("ending within engagement range of Custodian Guard B: refused", not near.get("success", false), str(near))
	var ok_stage = _stage(ph, WAZ, m0, dest)
	_check("19.5\" through the Custodians and the dense wall: staged", ok_stage.get("success", false), str(ok_stage.get("error", "")))
	TM.terrain_features = saved
	var conf = ph.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": WAZ, "payload": {}})
	_settle(ph)
	_check("CONFIRM_UNIT_MOVE succeeds", conf.get("success", false), str(conf.get("error", "")))
	_check("Wazdakka ended 19.5\" away, beyond the Custodians", _pos(_u(WAZ).models[0]).distance_to(dest) < 1.0)
	_check("ended unengaged", not RE.is_unit_engaged(WAZ, GS.state))
	# G. AFTER MOVING effects.
	_check("flags: moved", _flag(WAZ, "moved", false) == true)
	_check("not advanced (shooting unaffected)", not _flag(WAZ, "advanced", false))
	_check("flags: cannot_charge", _flag(WAZ, "cannot_charge", false) == true)
	_check("flags: cannot_start_action", _flag(WAZ, "cannot_start_action", false) == true)
	_check("charge template: not eligible to declare a charge", not ChargeMove11e.new().eligible(WAZ, GS.state).eligible)
	_u(WAZ).flags["effect_advance_and_charge"] = true
	_u(WAZ).flags["effect_fall_back_and_charge"] = true
	_check("advance/fall-back-and-charge effects cannot lift it (no advanced/fell_back source)", not ChargeMove11e.new().eligible(WAZ, GS.state).eligible)
	_u(WAZ).flags.erase("effect_advance_and_charge")
	_u(WAZ).flags.erase("effect_fall_back_and_charge")
	_check("marker %s set {player 1}" % OA.F_PULSE_JET, typeof(_flag(WAZ, OA.F_PULSE_JET)) == TYPE_DICTIONARY and int(_flag(WAZ, OA.F_PULSE_JET).get("player", 0)) == 1)
	# -1 to hit for every attack that targets Wazdakka (aggregator + ledger).
	var prof := {"name": "guardian spear", "type": "Ranged", "range": 24}
	var ab: Dictionary = RE.ork11e_ab_mods(_u(CUS), _u(WAZ), prof, false, GS.state)
	_check("RulesEngine aggregator: hit_minus vs Wazdakka (ranged)", bool(ab.get("hit_minus", false)))
	_check("source 'Pulse Jet' (kind hit, minus_one)", ab.get("sources", []).any(func(s): return s.name == "Pulse Jet" and s.kind == "hit" and s.effect == "minus_one"), str(ab.get("sources", [])))
	var abm: Dictionary = RE.ork11e_ab_mods(_u(CUS), _u(WAZ), {"name": "spear", "type": "Melee"}, true, GS.state)
	_check("melee attacks too", bool(abm.get("hit_minus", false)))
	var ledger: Array = []
	var bits: int = RE.ork11e_ab_hit_bits(0, ledger, ab)
	_check("folded into HitModifier.MINUS_ONE", (bits & RE.HitModifier.MINUS_ONE) != 0)
	_check("modifier breakdown names Pulse Jet", str(ledger).contains("Pulse Jet"), str(ledger))
	var ab_own: Dictionary = RE.ork11e_ab_mods(_u(WAZ), _u(CUS), prof, false, GS.state)
	_check("Wazdakka's OWN attacks are not penalised", not ab_own.get("sources", []).any(func(s): return s.name == "Pulse Jet"))
	_check("pulse_jet_hit_penalty(Wazdakka)", OA.pulse_jet_hit_penalty(WAZ))


func _section_pulse_expiry() -> void:
	print("\n--- H. Pulse Jet expiry ---")
	# Continue from the confirmed move above (P1's turn, Movement phase).
	_to(P_SHOOT)
	_check("Shooting phase: -1 still applies", OA.pulse_jet_hit_penalty(WAZ))
	_to(P_CHG)
	_check("Charge phase: cannot_charge still set", _flag(WAZ, "cannot_charge", false) == true)
	_to(P_FIGHT)
	GS.state.meta["battle_round"] = int(GS.state.meta.get("battle_round", 2))
	_to(P_CMD, 2)
	_check("opponent's turn (P2 Command): -1 still applies", OA.pulse_jet_hit_penalty(WAZ))
	_to(P_MOV, 2)
	_to(P_SHOOT, 2)
	_check("opponent's Shooting phase: attacks that target Wazdakka still -1", bool(RE.ork11e_ab_mods(_u(CUS), _u(WAZ), {"name": "x", "type": "Ranged", "range": 24}, false, GS.state).get("hit_minus", false)))
	_to(P_FIGHT, 2)
	GS.state.meta["battle_round"] = int(GS.state.meta.get("battle_round", 2)) + 1
	_to(P_CMD, 1)
	_check("start of P1's next turn: the -1 to hit expired", not OA.pulse_jet_hit_penalty(WAZ) and _flag(WAZ, OA.F_PULSE_JET) == null)
	_check("... and the Full Throttle engine expired with it", OA.engine_of(WAZ) == "")


func _section_pulse_ai() -> void:
	print("\n--- I. AI ---")
	_load("ork11e_g3_pulse")
	# Full Throttle AI variant: Custodian Guard B is 4" away -> turbo.
	GS.state.meta["phase"] = P_CMD
	var offers: Array = OA.window_offers(1, "battle_shock_step_start", {"window_id": "battle_shock_step_start"})
	var ft_o: Array = offers.filter(func(o): return str(o.get("stratagem_id", "")) == OA.sid_of("full_throttle"))
	var t_near: Dictionary = ft_o[0].targets[0] if not ft_o.is_empty() else {}
	_check("AI Full Throttle variant near the enemy: turbo", str(t_near.get("ai_variant", "")) == "turbo", str(t_near.get("ai_variant", "")))
	for uid in GS.state.units:
		if int(_u(uid).get("owner", 0)) == 2:
			var i := 0
			for m in _u(uid).models:
				m["position"] = {"x": (30.0 + 2.0 * i) * PX, "y": 56.0 * PX}
				i += 1
	offers = OA.window_offers(1, "battle_shock_step_start", {"window_id": "battle_shock_step_start"})
	ft_o = offers.filter(func(o): return str(o.get("stratagem_id", "")) == OA.sid_of("full_throttle"))
	var t_far: Dictionary = ft_o[0].targets[0] if not ft_o.is_empty() else {}
	_check("AI Full Throttle variant > 24\" from every enemy: pulse", str(t_far.get("ai_variant", "")) == "pulse", str(t_far.get("ai_variant", "")) + " dist " + str(OA.dist_in(WAZ, CUS)))
	_full_throttle("pulse")
	var ph = _to(P_MOV)
	# AI: an advance assignment for Wazdakka becomes a pulse jet move.
	GS.state.units.erase("U_BOYZ_C")
	var snap: Dictionary = GS.create_snapshot(false)
	var avail: Array = ph.get_available_actions()
	var dec: Dictionary = AIDecisionMaker.decide(GameStateData.Phase.MOVEMENT, snap, avail, 1)
	print("    AI decision: %s %s" % [str(dec.get("type", "")), str(dec.get("_ai_description", ""))])
	_check("AI movement decision is a legal action type", str(dec.get("type", "")) in ["BEGIN_PULSE_JET_MOVE", "BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY", "END_MOVEMENT"], str(dec.get("type", "")))
	# Drive the AI's pulse jet path directly (assignment-independent): plan 19"
	# toward the far board edge, begin, stage the planned destinations, confirm.
	var unit: Dictionary = snap.units[WAZ]
	var target := _pos(unit.models[0]) + Vector2(0, 30.0 * PX)
	var dests: Dictionary = AIDecisionMaker._compute_movement_toward_target(unit, WAZ, target, 19.0, snap, AIDecisionMaker._get_enemy_units(snap, 1), 0.0, [], AIDecisionMaker._get_objectives(snap))
	_check("AI planner finds pulse jet destinations (19\" plan)", not dests.is_empty())
	var b = ph.execute_action({"type": "BEGIN_PULSE_JET_MOVE", "actor_unit_id": WAZ, "player": 1})
	_decline_windows(ph)
	_check("AI BEGIN_PULSE_JET_MOVE accepted", b.get("success", false), str(b.get("error", "")))
	# AIPlayer's own staging path (what it runs after a successful BEGIN_*).
	var staged_ok: bool = root.get_node("AIPlayer")._execute_ai_movement(1, {"type": "BEGIN_PULSE_JET_MOVE", "actor_unit_id": WAZ,
		"_ai_model_destinations": dests, "_ai_description": "test: AI pulse jet"})
	_settle(ph)
	_check("AIPlayer stages + confirms the pulse jet move (never stalls)", staged_ok and _flag(WAZ, "moved", false) == true and _flag(WAZ, OA.F_PULSE_JET) != null)


func _section_herd() -> void:
	print("\n--- J. Runnin' wiv da Herd ---")
	_load("ork11e_g3_herd")
	var PB := "U_PAINBOSS_A"
	var SQ := "U_SQUIGHOG_BOYZ_A"
	var cam = root.get_node("CharacterAttachmentManager")
	_check("(fixture) Painboss attached to Squighog Boyz (MOUNTED)", str(_u(PB).get("attached_to", "")) == SQ and "MOUNTED" in _kw(SQ))
	var d: Array = OA.sync_herd_keywords()
	_check("sync applies the swap", not d.is_empty())
	_check("attached: no INFANTRY", not "INFANTRY" in _kw(PB), str(_kw(PB)))
	_check("attached: has MOBILE and MOUNTED", "MOBILE" in _kw(PB) and "MOUNTED" in _kw(PB), str(_kw(PB)))
	_check("RulesEngine.unit_has_keyword(Painboss, INFANTRY) false", not RE.unit_has_keyword(_u(PB), "INFANTRY"))
	_check("RulesEngine.unit_has_keyword(Painboss, MOUNTED) true", RE.unit_has_keyword(_u(PB), "MOUNTED"))
	_check("the Attached unit has no INFANTRY (19.03 union)", not "INFANTRY" in cam.attached_unit_keywords(SQ), str(cam.attached_unit_keywords(SQ)))
	_check("+4\" M while attached (existing move_modifier)", is_equal_approx(OA.move_modifier(_u(PB)), 4.0))
	_check("record of what changed", typeof(_flag(PB, OA.F_HERD_KW)) == TYPE_DICTIONARY and _flag(PB, OA.F_HERD_KW).removed == ["INFANTRY"])
	_check("sync is idempotent", OA.sync_herd_keywords().is_empty())
	# Detached.
	cam.detach_character(PB)
	OA.sync_herd_keywords()
	_check("detached: INFANTRY back", "INFANTRY" in _kw(PB), str(_kw(PB)))
	_check("detached: MOBILE / MOUNTED gone (it had neither)", not "MOBILE" in _kw(PB) and not "MOUNTED" in _kw(PB), str(_kw(PB)))
	_check("detached: record cleared", _flag(PB, OA.F_HERD_KW) == null)
	# Attached to a non-MOUNTED unit (Beast Snagga Boyz): no swap.
	cam.attach_character(PB, "U_BEAST_SNAGGA_BOYZ_B")
	OA.sync_herd_keywords()
	_check("attached to INFANTRY Beast Snagga Boyz: keeps INFANTRY", str(_u(PB).get("attached_to", "")) == "U_BEAST_SNAGGA_BOYZ_B" and "INFANTRY" in _kw(PB) and not "MOUNTED" in _kw(PB))
	cam.detach_character(PB)
	cam.attach_character(PB, SQ)
	# Through a real phase action (BasePhase after-action hook).
	var ph = _to(P_MOV)
	_check("phase transition hook applied the swap", not "INFANTRY" in _kw(PB))
	for m in _u(SQ).models:
		m["alive"] = false
		m["current_wounds"] = 0
	_check("(bodyguard destroyed; attached_to still set)", str(_u(PB).get("attached_to", "")) == SQ)
	var r = ph.execute_action({"type": "REMAIN_STATIONARY", "actor_unit_id": "U_BEAST_SNAGGA_BOYZ_B"})
	_check("an action ran", r.get("success", false), str(r.get("error", "")))
	_check("after the action: INFANTRY back (bodyguard destroyed)", "INFANTRY" in _kw(PB) and not "MOUNTED" in _kw(PB), str(_kw(PB)))
	_check("the action's recorded changes carry the keyword diff", r.get("changes", []).any(func(c): return str(c.get("path", "")) == "units.%s.meta.keywords" % PB))
	_check("+4\" M gone with the bodyguard", is_equal_approx(OA.move_modifier(_u(PB)), 0.0), str(OA.move_modifier(_u(PB))))
	# Edition 10: never swaps.
	_load("ork11e_g3_herd")
	GameConstants.edition = 10
	_check("10e: no swap", OA.herd_keyword_diffs().is_empty())
	GameConstants.edition = 11


func _section_get_out_da_way() -> void:
	print("\n--- K. Get Out da Way! / 11e 03 charge paths ---")
	_load("ork11e_g3_charge")
	var ph = _to(P_CHG)
	var NOBZ := "U_NOBZ_A"
	var WSC := "U_WITCHSEEKERS_C"
	var WSD := "U_WITCHSEEKERS_D"
	var DREAD := "U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H"
	_check("Nobz have Get Out da Way!", OA.charge_moves_through_models(NOBZ))
	_check("Boyz do not", not OA.charge_moves_through_models("U_BOYZ_C"))
	var nb: Array = ChargeMove11e.path_blocking_models(NOBZ, GS.state)
	_check("Nobz blockers: only enemy MONSTER/VEHICLE models (the Contemptor)", not nb.is_empty() and nb.all(func(b): return b.unit_id == DREAD), str(nb.map(func(b): return b.unit_id)))
	var bb: Array = ChargeMove11e.path_blocking_models("U_BOYZ_C", GS.state)
	_check("Boyz blockers: every enemy model", bb.any(func(b): return b.unit_id == WSD) and bb.any(func(b): return b.unit_id == WSC) and bb.any(func(b): return b.unit_id == DREAD))
	_check("friendly models never block (no P1 model in either list)", not bb.any(func(b): return int(_u(b.unit_id).owner) == 1) and not nb.any(func(b): return int(_u(b.unit_id).owner) == 1))
	# Straight lanes.
	var n0: Dictionary = _u(NOBZ).models[2]
	var np := _pos(n0)
	var lane_n := [[np.x, np.y], [np.x, np.y + 6.9 * PX]]
	_check("(the Nobz lane crosses Witchseekers C)", ChargeMove11e.path_crosses_models(n0, lane_n, bb.filter(func(b): return b.unit_id == WSC)) == WSC)
	_check("Nobz: through Witchseekers C (non-M/V) allowed", ChargeMove11e.path_crosses_models(n0, lane_n, nb) == "")
	var dp := _pos(_u(DREAD).models[0])
	var lane_v := [[dp.x, dp.y - 3.0 * PX], [dp.x, dp.y + 3.0 * PX]]
	_check("Nobz: through the Contemptor (VEHICLE) refused", ChargeMove11e.path_crosses_models(n0, lane_v, nb) == DREAD)
	var b0: Dictionary = _u("U_BOYZ_C").models[2]
	var bp := _pos(b0)
	var lane_b := [[bp.x, bp.y], [bp.x, bp.y + 6.9 * PX]]
	_check("Boyz: through Witchseekers D refused (11e 03)", ChargeMove11e.path_crosses_models(b0, lane_b, bb) == WSD)
	var lane_f := [[np.x, np.y], [bp.x, bp.y]]
	_check("Nobz: across the Boyz (friendly) allowed", ChargeMove11e.path_crosses_models(n0, lane_f, nb) == "")
	# Phase validator: the THROUGH_MODELS category.
	var v = ph._validate_charge_movement_constraints("U_BOYZ_C", {"m3": lane_b}, {"distance": 12, "targets": [DREAD]})
	_check("ChargePhase validator rejects the Boyz path (THROUGH_MODELS)", not v.valid and v.categorized_errors.any(func(e): return e.category == ph.FAIL_THROUGH_MODELS), str(v.get("errors", [])))
	var vn = ph._g3_validate_paths_through_models(NOBZ, {"m3": lane_n})
	_check("ChargePhase path gate passes the Nobz path through Witchseekers C", vn.valid, str(vn))
	var vv = ph._g3_validate_paths_through_models(NOBZ, {"m3": lane_v})
	_check("ChargePhase path gate refuses the Nobz path through the Contemptor", not vv.valid, str(vv))
	GameConstants.edition = 10
	_check("10e: no path gate", ChargeMove11e.path_blocking_models("U_BOYZ_C", GS.state).is_empty())
	GameConstants.edition = 11
	# Real flow: declare, roll 9+, the AI charge planner (validator parity) plans
	# straight through Witchseekers C, APPLY_CHARGE_MOVE accepted.
	var dr = ph.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": NOBZ, "player": 1, "payload": {"target_unit_ids": ["U_CUSTODIAN_GUARD_B"]}})
	_decline_windows(ph)
	_check("DECLARE_CHARGE (Nobz -> Custodian Guard B)", dr.get("success", false), str(dr.get("error", "")))
	var seed := _seed_d6(func(r): return int(r[0]) + int(r[1]) >= 10, 2)
	var rr = ph.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": NOBZ, "player": 1, "payload": {"rng_seed": seed}})
	if ph.get("awaiting_ability_reroll"):
		ph.execute_action({"type": "DECLINE_ABILITY_REROLL", "actor_unit_id": NOBZ, "player": 1})
	if ph.get("awaiting_reroll_decision"):
		ph.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": NOBZ, "player": 1})
	_decline_windows(ph)
	var dist := int(ph.pending_charges.get(NOBZ, {}).get("distance", 0))
	_check("CHARGE_ROLL >= 10", rr.get("success", false) and dist >= 10, "dist %d %s" % [dist, str(rr.get("error", ""))])
	var mv: Dictionary = AIDecisionMaker._compute_charge_move(GS.create_snapshot(false), NOBZ, dist, ["U_CUSTODIAN_GUARD_B"], 1)
	_check("AI charge planner: APPLY_CHARGE_MOVE for the Nobz", str(mv.get("type", "")) == "APPLY_CHARGE_MOVE", str(mv.get("_ai_description", "")))
	var crosses := false
	var wsc_only: Array = bb.filter(func(b): return b.unit_id == WSC)
	for k in mv.get("payload", {}).get("per_model_paths", {}):
		var mm: Dictionary = {}
		for m in _u(NOBZ).models:
			if str(m.id) == str(k):
				mm = m
		if ChargeMove11e.path_crosses_models(mm, mv.payload.per_model_paths[k], wsc_only) != "":
			crosses = true
	_check("the planned paths go THROUGH Witchseekers C (Get Out da Way!)", crosses)
	mv["player"] = 1
	var ar = ph.execute_action(mv)
	_check("APPLY_CHARGE_MOVE accepted by the phase", ar.get("success", false), str(ar.get("error", ar.get("errors", ""))))
	_check("Nobz engaged with Custodian Guard B", RE.check_units_in_engagement_range(_u(NOBZ), _u("U_CUSTODIAN_GUARD_B"), GS.state))
	_check("Nobz not engaged with Witchseekers C (non-target)", not RE.check_units_in_engagement_range(_u(NOBZ), _u(WSC), GS.state))
	# AI parity for a unit WITHOUT the ability: Boyz behind Witchseekers D can
	# not be planned through them.
	var mvb: Dictionary = AIDecisionMaker._compute_charge_move(GS.create_snapshot(false), "U_BOYZ_C", 12, [DREAD], 1)
	var b_cross := false
	for k in mvb.get("payload", {}).get("per_model_paths", {}):
		var mm2: Dictionary = {}
		for m in _u("U_BOYZ_C").models:
			if str(m.id) == str(k):
				mm2 = m
		if ChargeMove11e.path_crosses_models(mm2, mvb.payload.per_model_paths[k], ChargeMove11e.path_blocking_models("U_BOYZ_C", GS.state)) != "":
			b_cross = true
	_check("AI never plans a Boyz path through enemy models", not b_cross, str(mvb.get("_ai_description", "")))

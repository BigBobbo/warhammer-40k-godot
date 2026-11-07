extends SceneTree

# WP-G1 (Codex 11e gaps) — the Redeployment step (phases/RedeploymentPhase.gd)
# that the human UI (scripts/RedeploymentController.gd) drives:
#   Castellan's Mark (Codex: Adeptus Custodes, Guardians of the Throne) and
#   Kaptin's Hat (Codex: Orks, Wreckas): "When both players have deployed their
#   armies, you can redeploy up to three friendly <KEYWORD> units. When doing
#   so, you can set those units up in strategic reserves, regardless of how
#   many units are already in strategic reserves."
#   Core rules: resolved after Deploy Armies; players alternate, starting with
#   the Attacker; normal deployment rules apply (incl. Infiltrators).
# Fixtures: tests/saves/ork11e_enh_wreckas_redeploy (P1 Orks, Warboss with
# Kaptin's Hat leading Flash Gitz; P2 Custodes) and
# tests/saves/cus11e_c3_custodes_active (P1 Custodes Guardians of the Throne,
# P2 Orks).
#
# Usage: godot --headless --path 40k --script tests/test_codex11e_g1_redeploy.gd

const ORK_FX := "ork11e_enh_wreckas_redeploy"
const CUS_FX := "cus11e_c3_custodes_active"
const PH_REDEPLOY := 2
const PX := 40.0

const FG := "U_FLASH_GITZ_A"
const WB := "U_WARBOSS_A"
const BOYZ := "U_BOYZ_C"
const WAGON := "U_BATTLEWAGON_A"
const CG_B := "U_CUSTODIAN_GUARD_B"
const SC := "U_SHIELD_CAPTAIN_A"
const WS_C := "U_WITCHSEEKERS_C"
const WS_D := "U_WITCHSEEKERS_D"
const O_BOYZ_B := "U_BOYZ_B"

var passed := 0
var failed := 0
var GS = null
var PM = null
var FAM = null


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _initialize() -> void:
	await create_timer(0.3).timeout
	GameConstants.edition = 11
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	FAM = root.get_node("FactionAbilityManager")
	var ai = root.get_node_or_null("AIPlayer")
	if ai:
		ai.enabled = false
	await _section_kaptins_hat_eligibility()
	await _section_redeploy_unit_validation()
	await _section_send_to_reserves()
	await _section_alternation_attacker_first()
	await _section_three_use_limit_and_ability_units()
	await _section_infiltrators()
	await _section_staged_flow()
	await _section_ai_never_stalls()
	await _section_nothing_to_redeploy()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _load(fx: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fx + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fx + ext))
	var ok: bool = slm.load_game(fx)
	GameConstants.edition = 11
	FAM._razgit_redeploys_used = {"1": 0, "2": 0}
	var ai = root.get_node_or_null("AIPlayer")
	if ai:
		ai.enabled = false
	return ok


func _enter(attacker: int = 0) -> Object:
	if attacker > 0:
		GS.state.meta["attacker"] = attacker
		GS.state.meta["defender"] = 3 - attacker
	else:
		GS.state.meta.erase("attacker")
	GS.state.meta["phase"] = 1  # DEPLOYMENT
	PM.transition_to_phase(PH_REDEPLOY)
	await process_frame
	await process_frame
	return PM.get_current_phase_instance()


func _phase_num() -> int:
	return int(GS.state.meta.phase)


func _unit(uid: String) -> Dictionary:
	return GS.state.units[uid]


func _run(ph, action: Dictionary) -> Dictionary:
	if not action.has("player"):
		action["player"] = GS.get_active_player()
	var r = ph.execute_action(action)
	await process_frame
	return r if r is Dictionary else {}


## A row of placements for the group (unit + attached characters), left to
## right from (x_in, y_in), spacing in inches.
func _row(ph, unit_id: String, x_in: float, y_in: float, spacing_in: float = 1.7) -> Array:
	var out: Array = []
	var i := 0
	for g in ph._redeploy_group_models(unit_id):
		out.append({"unit_id": g.unit_id, "model_id": str(g.model.id), "x": (x_in + i * spacing_in) * PX, "y": y_in * PX, "rotation": 0.0})
		i += 1
	return out


func _first_pos(uid: String) -> Vector2:
	var p = _unit(uid).models[0].position
	return Vector2(float(p.x), float(p.y)) if p != null else Vector2(-1, -1)


# ---------------------------------------------------------------------------
# 1. Kaptin's Hat: who is eligible
# ---------------------------------------------------------------------------

func _section_kaptins_hat_eligibility() -> void:
	print("\n-- 1. Kaptin's Hat: eligible units, Attached unit, Attacker first --")
	_check("ork fixture loads", _load(ORK_FX))
	var ph = await _enter()
	_check("the Redeployment step is entered (not skipped)", _phase_num() == PH_REDEPLOY, str(_phase_num()))
	var p1: Array = ph.redeploy_units_pending.get(1, [])
	_check("ORKS INFANTRY units are listed (Flash Gitz, Boyz)", p1.has(FG) and p1.has(BOYZ), str(p1))
	_check("the Battlewagon (VEHICLE) is not", not p1.has(WAGON), str(p1))
	_check("the attached Warboss is not a separate entry (it moves with its Flash Gitz)", not p1.has(WB), str(p1))
	_check("no meta.attacker: Player 1 resolves first", GS.get_active_player() == 1)
	var menu: Dictionary = ph.get_redeploy_menu(1)
	_check("menu names the enhancement", str(menu.enhancement) == "Kaptin's Hat", str(menu.enhancement))
	_check("menu: keyword filter ORKS INFANTRY", menu.keywords == ["ORKS", "INFANTRY"], str(menu.keywords))
	_check("menu: three uses", int(menu.uses_left) == 3)
	var fg_row := {}
	for r in menu.units:
		if str(r.unit_id) == FG:
			fg_row = r
	_check("menu: the Flash Gitz row covers the Warboss (6 models)", int(fg_row.get("models", 0)) == 6 and str(fg_row.get("label", "")).contains("Warboss"), str(fg_row))
	_check("menu: enhancement units can go to Strategic Reserves", bool(fg_row.get("can_reserve", false)))
	var acts: Array = ph.get_available_actions().map(func(a): return str(a.get("description", "")))
	_check("available actions still offer the Kaptin's Hat moves", acts.has("Redeploy Boyz") and acts.has("Kaptin's Hat: Send Boyz to Strategic Reserves"), str(acts))


# ---------------------------------------------------------------------------
# 2. REDEPLOY_UNIT: normal deployment rules
# ---------------------------------------------------------------------------

func _section_redeploy_unit_validation() -> void:
	print("\n-- 2. REDEPLOY_UNIT: deployment zone, whole Attached unit, coherency, overlap --")
	_load(ORK_FX)
	var ph = await _enter()
	var good := _row(ph, FG, 12.0, 3.0)
	var v: Dictionary = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": good, "player": 1})
	_check("a legal set-up wholly within the deployment zone validates", bool(v.valid), str(v.get("errors", [])))
	var outside := _row(ph, FG, 12.0, 25.0)
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": outside, "player": 1})
	_check("outside the deployment zone is rejected", not bool(v.valid) and str(v.errors).contains("deployment zone"), str(v.get("errors", [])))
	var no_leader: Array = good.filter(func(p): return str(p.unit_id) != WB)
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": no_leader, "player": 1})
	_check("leaving the attached Warboss behind is rejected", not bool(v.valid) and str(v.errors).contains("missing"), str(v.get("errors", [])))
	var spread := _row(ph, FG, 2.0, 3.0, 7.0)
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": spread, "player": 1})
	_check("out of coherency is rejected", not bool(v.valid) and str(v.errors).contains("coherency"), str(v.get("errors", [])))
	var stacked := _row(ph, FG, 12.0, 3.0, 0.2)
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": stacked, "player": 1})
	_check("models on top of each other are rejected", not bool(v.valid) and str(v.errors).contains("overlap"), str(v.get("errors", [])))
	# On top of the Boyz (another unit) — Boyz first model position
	var bp := _first_pos(BOYZ)
	var on_boyz := _row(ph, FG, bp.x / PX, bp.y / PX)
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": on_boyz, "player": 1})
	_check("set up on another unit's models is rejected", not bool(v.valid) and str(v.errors).contains("overlap with other models"), str(v.get("errors", [])))
	# Over its own old footprint is fine (the unit is picked up first)
	var own := []
	var gi := 0
	for g in ph._redeploy_group_models(FG):
		var op = g.model.position
		own.append({"unit_id": g.unit_id, "model_id": str(g.model.id), "x": float(op.x) + 1.0, "y": float(op.y), "rotation": 0.0})
		gi += 1
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": own, "player": 1})
	_check("its own old positions never block (the unit is picked up)", not str(v.get("errors", [])).contains("other models"), str(v.get("errors", [])))
	GS.set_active_player(2)
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": good, "player": 2})
	GS.set_active_player(1)
	_check("the opponent cannot redeploy it", not bool(v.valid) and str(v.errors).contains("active player"), str(v.get("errors", [])))
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": WAGON, "placements": _row(ph, WAGON, 30.0, 3.0), "player": 1})
	_check("an ineligible unit (Battlewagon) is rejected", not bool(v.valid) and str(v.errors).contains("not eligible"), str(v.get("errors", [])))

	var r := await _run(ph, {"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": good})
	_check("REDEPLOY_UNIT succeeds", bool(r.get("success", false)), str(r))
	_check("Flash Gitz now where they were set up", _first_pos(FG).distance_to(Vector2(12.0 * PX, 3.0 * PX)) < 0.5, str(_first_pos(FG)))
	var wb_expected := Vector2((12.0 + 5 * 1.7) * PX, 3.0 * PX)
	_check("the attached Warboss moved with them", _first_pos(WB).distance_to(wb_expected) < 0.5, str(_first_pos(WB)))
	_check("both still DEPLOYED, still attached", int(_unit(FG).status) == 2 and int(_unit(WB).status) == 2 and str(_unit(WB).get("attached_to", "")) == FG)
	_check("one of the three Kaptin's Hat uses spent", FAM.get_razgit_redeploys_remaining(1) == 2, str(FAM.get_razgit_redeploys_remaining(1)))
	_check("Flash Gitz resolved (no longer pending)", not ph.redeploy_units_pending.get(1, []).has(FG))
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": good, "player": 1})
	_check("a unit cannot be redeployed twice", not bool(v.valid), str(v.get("errors", [])))
	_check("the step is still on (Boyz pending)", _phase_num() == PH_REDEPLOY)


# ---------------------------------------------------------------------------
# 3. Strategic Reserves, ignoring the reserves limit
# ---------------------------------------------------------------------------

func _section_send_to_reserves() -> void:
	print("\n-- 3. SEND_TO_STRATEGIC_RESERVES --")
	_load(ORK_FX)
	var ph = await _enter()
	# Fill the reserves well past the 50% points cap first (Battlewagon). The
	# rule says "regardless of how many units are already in strategic reserves".
	_unit(WAGON)["status"] = 7
	_unit(WAGON)["reserve_type"] = "strategic_reserves"
	var r := await _run(ph, {"type": "SEND_TO_STRATEGIC_RESERVES", "unit_id": FG})
	_check("Flash Gitz (+ Warboss) to Strategic Reserves succeeds", bool(r.get("success", false)), str(r))
	_check("status IN_RESERVES, reserve_type strategic_reserves", int(_unit(FG).status) == 7 and str(_unit(FG).get("reserve_type", "")) == "strategic_reserves")
	_check("the attached Warboss goes with them", int(_unit(WB).status) == 7 and str(_unit(WB).get("reserve_type", "")) == "strategic_reserves")
	_check("models off the battlefield", _unit(FG).models[0].position == null and _unit(WB).models[0].position == null)
	_check("listed by GameState.get_reserves_for_player (arrives later)", GS.get_reserves_for_player(1).has(FG))
	_check("a use spent (2 left)", FAM.get_razgit_redeploys_remaining(1) == 2)
	r = await _run(ph, {"type": "SEND_TO_STRATEGIC_RESERVES", "unit_id": BOYZ})
	_check("Boyz to Strategic Reserves succeeds", bool(r.get("success", false)), str(r))
	_check("P1 has nothing left; P2 has nothing: the step ends", _phase_num() != PH_REDEPLOY, str(_phase_num()))


# ---------------------------------------------------------------------------
# 4. Alternation: Attacker first, Done hands over
# ---------------------------------------------------------------------------

func _section_alternation_attacker_first() -> void:
	print("\n-- 4. Players alternate, starting with the Attacker --")
	_load(ORK_FX)
	_unit(CG_B).meta["enhancements"] = ["Castellan's Mark"]  # P2 Custodes (test set-up)
	_check("P2 owns Castellan's Mark", FAM.get_redeploy_enhancement_name(2) == "Castellan's Mark")
	var ph = await _enter(2)
	_check("Attacker = Player 2 resolves first", GS.get_active_player() == 2, str(GS.get_active_player()))
	_check("P2 pending: the Custodian Guard", ph.redeploy_units_pending.get(2, []).has(CG_B))
	var v: Dictionary = ph.validate_action({"type": "SEND_TO_STRATEGIC_RESERVES", "unit_id": BOYZ, "player": 1})
	_check("P1 cannot act during P2's redeployments", not bool(v.valid))
	var r := await _run(ph, {"type": "END_REDEPLOYMENT_PHASE"})
	_check("P2 Done Redeploying succeeds", bool(r.get("success", false)))
	_check("the step passes to Player 1 (not ended)", _phase_num() == PH_REDEPLOY and GS.get_active_player() == 1, "phase %d active %d" % [_phase_num(), GS.get_active_player()])
	_check("P2's declined unit stayed DEPLOYED", int(_unit(CG_B).status) == 2)
	r = await _run(ph, {"type": "END_REDEPLOYMENT_PHASE"})
	_check("P1 Done: the step ends", _phase_num() != PH_REDEPLOY, str(_phase_num()))
	# P1 attacker, P1 finishes by using its units: hands to P2 automatically
	_load(ORK_FX)
	_unit(CG_B).meta["enhancements"] = ["Castellan's Mark"]
	ph = await _enter(1)
	_check("Attacker = Player 1 resolves first", GS.get_active_player() == 1)
	await _run(ph, {"type": "SKIP_REDEPLOY", "unit_id": FG})
	await _run(ph, {"type": "SEND_TO_STRATEGIC_RESERVES", "unit_id": BOYZ})
	_check("P1 done -> Player 2 resolves", _phase_num() == PH_REDEPLOY and GS.get_active_player() == 2)
	var good: Array = []
	var i := 0
	for g in ph._redeploy_group_models(CG_B):
		good.append({"unit_id": CG_B, "model_id": str(g.model.id), "x": (14.0 + i * 1.8) * PX, "y": 56.0 * PX})
		i += 1
	r = await _run(ph, {"type": "REDEPLOY_UNIT", "unit_id": CG_B, "placements": good})
	_check("P2 re-places its Custodian Guard in its own zone", bool(r.get("success", false)), str(r))
	_check("P2 Castellan's Mark use spent", FAM.get_razgit_redeploys_remaining(2) == 2)
	_check("then the step ends", _phase_num() != PH_REDEPLOY)


# ---------------------------------------------------------------------------
# 5. Up to three units; datasheet-ability units
# ---------------------------------------------------------------------------

func _section_three_use_limit_and_ability_units() -> void:
	print("\n-- 5. Castellan's Mark: up to three units; ability units --")
	_load(CUS_FX)
	_unit(SC).meta["enhancements"] = ["Castellan's Mark"]
	_unit(O_BOYZ_B).meta.abilities.append({"name": "Redeploy"})  # P2: a datasheet redeploy ability (test set-up)
	var ph = await _enter(1)
	var p1: Array = ph.redeploy_units_pending.get(1, [])
	_check("every deployed ADEPTUS CUSTODES unit is listed (incl. the bearer)", p1.has(SC) and p1.has(CG_B) and p1.has("U_CALADIUS_GRAV-TANK_E") and p1.size() == 9, str(p1))
	_check("Ork units are not", not p1.has(O_BOYZ_B))
	await _run(ph, {"type": "SEND_TO_STRATEGIC_RESERVES", "unit_id": WS_C})
	await _run(ph, {"type": "SEND_TO_STRATEGIC_RESERVES", "unit_id": WS_D})
	_check("two uses spent, step still Player 1's", FAM.get_razgit_redeploys_remaining(1) == 1 and GS.get_active_player() == 1)
	await _run(ph, {"type": "SEND_TO_STRATEGIC_RESERVES", "unit_id": CG_B})
	_check("three units in Strategic Reserves", int(_unit(WS_C).status) == 7 and int(_unit(WS_D).status) == 7 and int(_unit(CG_B).status) == 7)
	_check("no fourth: the rest of Player 1's list drops", ph.redeploy_units_pending.get(1, []).is_empty(), str(ph.redeploy_units_pending.get(1, [])))
	_check("the other Custodes units keep their positions", int(_unit(SC).status) == 2 and _unit(SC).models[0].position != null)
	_check("the step passes to Player 2 (datasheet-ability unit)", GS.get_active_player() == 2 and _phase_num() == PH_REDEPLOY)
	var v: Dictionary = ph.validate_action({"type": "SEND_TO_STRATEGIC_RESERVES", "unit_id": O_BOYZ_B, "player": 2})
	_check("a datasheet-ability redeploy cannot go to Strategic Reserves", not bool(v.valid))
	var good: Array = []
	var i := 0
	for g in ph._redeploy_group_models(O_BOYZ_B):
		good.append({"unit_id": O_BOYZ_B, "model_id": str(g.model.id), "x": (3.0 + (i % 5) * 1.3) * PX, "y": (55.0 + (i / 5) * 1.3) * PX})
		i += 1
	var r := await _run(ph, {"type": "REDEPLOY_UNIT", "unit_id": O_BOYZ_B, "placements": good})
	_check("the ability unit redeploys", bool(r.get("success", false)), str(r))
	_check("it spends no enhancement use (P2 has none)", FAM.get_razgit_redeploys_remaining(2) == 3)
	_check("the step ends", _phase_num() != PH_REDEPLOY)


# ---------------------------------------------------------------------------
# 6. Infiltrators
# ---------------------------------------------------------------------------

func _section_infiltrators() -> void:
	print("\n-- 6. Infiltrators: normal Infiltrators set-up applies --")
	# Ork fixture: the only enemy unit (Custodian Guard B) sits in P2's zone.
	_load(ORK_FX)
	_unit(BOYZ).meta.abilities.append({"name": "Infiltrators", "type": "Core"})  # test set-up
	var ph = await _enter(1)
	var mid := _grid(ph, BOYZ, 18.0, 28.0)
	var v: Dictionary = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": BOYZ, "placements": mid, "player": 1})
	_check("Infiltrators: mid-board, >8\" from the enemy zone and models, validates", bool(v.valid), str(v.get("errors", [])))
	var near := _grid(ph, BOYZ, 18.0, 38.5)
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": BOYZ, "placements": near, "player": 1})
	_check("Infiltrators within 8\" of the enemy zone is rejected", not bool(v.valid) and str(v.errors).contains("enemy deployment zone"), str(v.get("errors", [])))
	var fg_mid := _grid(ph, FG, 18.0, 28.0)
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": FG, "placements": fg_mid, "player": 1})
	_check("without Infiltrators the same spot is outside the zone", not bool(v.valid) and str(v.errors).contains("deployment zone"), str(v.get("errors", [])))
	_check("menu flags the Infiltrators unit", ph.get_redeploy_menu(1).units.any(func(r): return str(r.unit_id) == BOYZ and bool(r.infiltrators)))
	# An enemy model 6" in front of the chosen spot blocks it (>8" from enemy models).
	var cg0: Dictionary = _unit(CG_B).models[0]
	var saved = cg0.position
	cg0["position"] = {"x": 20.0 * PX, "y": 35.5 * PX}
	v = ph.validate_action({"type": "REDEPLOY_UNIT", "unit_id": BOYZ, "placements": mid, "player": 1})
	_check("Infiltrators within 8\" of an enemy model is rejected", not bool(v.valid) and str(v.errors).contains("enemy models"), str(v.get("errors", [])))
	cg0["position"] = saved
	var r := await _run(ph, {"type": "REDEPLOY_UNIT", "unit_id": BOYZ, "placements": mid})
	_check("the Infiltrators unit redeploys mid-board", bool(r.get("success", false)) and _first_pos(BOYZ).distance_to(Vector2(18.0 * PX, 28.0 * PX)) < 0.5, str(r))


## A 5-wide grid (1.3" pitch) of placements for the group from (x_in, y_in).
func _grid(ph, unit_id: String, x_in: float, y_in: float) -> Array:
	var out: Array = []
	var i := 0
	for g in ph._redeploy_group_models(unit_id):
		out.append({"unit_id": g.unit_id, "model_id": str(g.model.id), "x": (x_in + (i % 5) * 1.3) * PX, "y": (y_in + (i / 5) * 1.3) * PX})
		i += 1
	return out


# ---------------------------------------------------------------------------
# 7. Staged BEGIN / SET / CONFIRM flow (scripts) uses the same rules
# ---------------------------------------------------------------------------

func _section_staged_flow() -> void:
	print("\n-- 7. Staged flow: BEGIN_REDEPLOY / SET_REDEPLOY_MODEL_POS / CONFIRM_REDEPLOY --")
	_load(ORK_FX)
	var ph = await _enter()
	var r := await _run(ph, {"type": "BEGIN_REDEPLOY", "unit_id": BOYZ})
	_check("BEGIN_REDEPLOY", bool(r.get("success", false)), str(r))
	var bad: Dictionary = ph.validate_action({"type": "SET_REDEPLOY_MODEL_POS", "unit_id": BOYZ, "model_id": "m1", "destination": {"x": 20 * PX, "y": 30 * PX}, "player": 1})
	_check("SET outside the zone is rejected (was a silent pass: wrong zone key)", not bool(bad.valid), str(bad))
	var v: Dictionary = ph.validate_action({"type": "CONFIRM_REDEPLOY", "unit_id": BOYZ, "player": 1})
	_check("CONFIRM with models unplaced is rejected", not bool(v.valid))
	var i := 0
	for g in ph._redeploy_group_models(BOYZ):
		await _run(ph, {"type": "SET_REDEPLOY_MODEL_POS", "unit_id": BOYZ, "model_id": str(g.model.id), "destination": {"x": (2.0 + (i % 5) * 1.3) * PX, "y": (2.0 + (i / 5) * 1.3) * PX}})
		i += 1
	r = await _run(ph, {"type": "CONFIRM_REDEPLOY", "unit_id": BOYZ})
	_check("CONFIRM_REDEPLOY succeeds", bool(r.get("success", false)), str(r))
	_check("Boyz moved; a use spent", _first_pos(BOYZ).distance_to(Vector2(2.0 * PX, 2.0 * PX)) < 0.5 and FAM.get_razgit_redeploys_remaining(1) == 2, str(_first_pos(BOYZ)))


# ---------------------------------------------------------------------------
# 8. The AI path never stalls
# ---------------------------------------------------------------------------

func _section_ai_never_stalls() -> void:
	print("\n-- 8. AI resolves the step (both seats with redeploys) --")
	_load(ORK_FX)
	_unit(CG_B).meta["enhancements"] = ["Castellan's Mark"]
	var ph = await _enter(1)
	var steps := 0
	while _phase_num() == PH_REDEPLOY and steps < 20:
		var p: int = GS.get_active_player()
		var d: Dictionary = load("res://scripts/AIDecisionMaker.gd")._decide_redeployment(GS.create_snapshot(), ph.get_available_actions(), p)
		if d.is_empty():
			break
		d["player"] = p
		await _run(ph, d)
		steps += 1
	_check("AI decisions end the step (%d actions)" % steps, _phase_num() != PH_REDEPLOY, "phase %d" % _phase_num())
	_check("AI keeps positions (skips)", int(_unit(FG).status) == 2 and int(_unit(CG_B).status) == 2)


# ---------------------------------------------------------------------------
# 9. No redeploy rule: the step is skipped
# ---------------------------------------------------------------------------

func _section_nothing_to_redeploy() -> void:
	print("\n-- 9. Nobody has a redeploy rule: the step is skipped --")
	_load(CUS_FX)
	_check("no redeploy enhancement in this list", FAM.get_redeploy_enhancement_name(1) == "" and FAM.get_redeploy_enhancement_name(2) == "")
	await _enter(1)
	await process_frame
	_check("the step completes by itself", _phase_num() != PH_REDEPLOY, str(_phase_num()))
	# Kaptin's Hat bearer's units all in reserves already: also nothing to do
	_load(ORK_FX)
	for uid in [FG, WB, BOYZ]:
		_unit(uid)["status"] = 7
	await _enter(1)
	await process_frame
	_check("enhancement but no deployed eligible unit: skipped", _phase_num() != PH_REDEPLOY, str(_phase_num()))

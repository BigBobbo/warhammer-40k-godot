extends SceneTree

# FIX_SHOOT_ATTACHED_RANGE (shooting: a shot is in range of the whole Attached
# unit — 11e 04.02 / 01.04.01 / 19.01). The engine's range and sight-line
# checks walk every model of an Attached unit (RulesEngine._target_model_entries:
# its own, then each attached CHARACTER's, both link directions), so an
# Attached unit whose leader alone is within a weapon's range is a legal
# target. The AI's damage / score estimates measured to the bodyguard dict's
# own models only, priced that shot at 0 and skipped "no valid targets in
# range".
#
# Cases (fixture ork11e_orks_reactive, terrain cleared): Custodian Guard A
# 23" from the Warboss attached to Boyz B, 25.6"+ from every Boy —
#   (a) OFF / unset: estimate 0, decide() skips; ON: estimate > 0, decide()
#       shoots the Boyz, and the engine agrees the target is eligible;
#   (b) a leader linked only by his own attached_to back-pointer counts too;
#   (c) control: with a Boy in range the estimate is the same OFF and ON;
#   (d) half range (RAPID FIRE) is read off the whole-unit distance;
#   (d') the same through a leader linked ONLY by his attached_to: the AI's
#       RAPID FIRE credit matches the engine's half-range count (MELTA path,
#       RAPID FIRE path, preview_attack, both resolve paths' [MA-14] bonus),
#       which used to read the forward attached_characters list alone;
#   (e) the engaged-pistol gate (T7-48) measures the leader too;
#   (f) 0.0 == unset: decide() byte-identical.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_shoot_attached_range.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const FIXTURE := "res://tests/saves/ork11e_orks_reactive.w40ksave"
const KNOB := "FIX_SHOOT_ATTACHED_RANGE"
const BOLTER_RF := {"name": "Rapid bolter", "type": "Ranged", "range": "24", "attacks": "2",
	"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": "rapid fire 2"}

var passed := 0
var failed := 0
var _completed := false
var AIDM = null
var GS = null
var TM = null
var RE = null
var SM = null
var MM = null
var AIP = null

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
	if not _completed:
		failed += 1
		print("  FAIL: the run aborted before its last check (see the SCRIPT ERROR above)")
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 or passed == 0 else 0)

func _load_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	var ok: bool = slm.load_game_from_file_path(FIXTURE)
	GameConstants.edition = 11
	var keep := ["U_CUSTODIAN_GUARD_A", "U_BOYZ_B", "U_WARBOSS_A"]
	var units: Dictionary = {}
	for uid in keep:
		if GS.state.units.has(uid):
			units[uid] = GS.state.units[uid]
			units[uid]["flags"] = {}
	GS.state.units = units
	GS.state.board["objectives"] = []
	GS.state.meta["battle_round"] = 2
	GS.state.meta["active_player"] = 1
	GS.state.meta["phase"] = 8
	TM.terrain_features = []
	GS.state.board["terrain_features"] = []
	RE.clear_los_memo()
	SM._usage_history = {"1": [], "2": []}
	MM.objective_control_state = {}
	MM.objective_contested_state = {}
	AIP.enabled = false
	AIP.ai_players = {1: false, 2: false}
	# The exam's board (tests/exams/sh03_shoot_the_leader_in_range.json).
	var k := 0
	for m in GS.state.units.U_CUSTODIAN_GUARD_A.models:
		m["position"] = {"x": 300.0 + float(k) * 65.0, "y": 400.0}
		k += 1
	for m in GS.state.units.U_WARBOSS_A.models:
		m["position"] = {"x": 430.0, "y": 1383.0}
	var j := 0
	for m in GS.state.units.U_BOYZ_B.models:
		if m.get("alive", true):
			m["position"] = {"x": 205.0 + float(j) * 50.0, "y": 1480.0}
			j += 1
	return ok and units.size() == 3

func _knob(v) -> void:
	if v == null:
		AIDM._config_overrides.erase(KNOB)
	else:
		AIDM._config_overrides[KNOB] = float(v)

func _spear(unit: Dictionary) -> Dictionary:
	for w in unit.meta.weapons:
		if str(w.get("type", "")).to_lower() == "ranged" and str(w.get("name", "")).to_lower().contains("spear"):
			return w
	return {}

func _decide() -> Dictionary:
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	AIDM.set_ai_seed(7)
	return AIDM.decide(8, GS.create_snapshot(), [{"type": "SELECT_SHOOTER", "actor_unit_id": "U_CUSTODIAN_GUARD_A"},
		{"type": "END_SHOOTING"}], 1)

func _shape(d: Dictionary) -> String:
	return "%s | %s | %s" % [str(d.get("type", "")), str(d.get("payload", {})), str(d.get("_ai_description", ""))]

func _targets_of(d: Dictionary) -> Array:
	var out: Array = []
	for a in d.get("payload", {}).get("assignments", []):
		out.append(str(a.get("target_unit_id", "")))
	return out

func _section_leader_only() -> void:
	print("\n-- (a) the leader alone is in range --")
	var snap: Dictionary = GS.create_snapshot()
	var cg: Dictionary = snap.units.U_CUSTODIAN_GUARD_A
	var boyz: Dictionary = snap.units.U_BOYZ_B
	var spear := _spear(cg)
	_check("fixture: Custodian Guard A has a 24\" guardian spear", not spear.is_empty() and int(str(spear.get("range", "0"))) == 24)
	var elig: Dictionary = RE.get_eligible_targets("U_CUSTODIAN_GUARD_A", snap, false, {"U_BOYZ_B": true})
	_check("engine: the Boyz are an eligible target, the spear in range (via the Warboss)", elig.has("U_BOYZ_B")
		and str(elig.get("U_BOYZ_B", {}).get("weapons_in_range", [])).to_lower().contains("spear"), str(elig))
	var d_own: float = AIDM._get_closest_model_distance_inches(cg, boyz)
	_check("the nearest Boy is beyond the spear's range (%.1f\" > 24\")" % d_own, d_own > 24.0)
	_knob(null)
	var e_unset: float = AIDM._estimate_weapon_damage(spear, boyz, snap, cg)
	var s_unset: float = AIDM._score_shooting_target(spear, boyz, snap, cg)
	_knob(0.0)
	var e_off: float = AIDM._estimate_weapon_damage(spear, boyz, snap, cg)
	var d_off: Dictionary = _decide()
	_check("OFF: the estimates read 0 (estimate %.3f, score %.3f; unset %.3f)" % [e_off, s_unset, e_unset],
		e_off == 0.0 and e_unset == 0.0 and s_unset == 0.0)
	_check("OFF: decide() skips 'no valid targets in range' (got %s)" % _shape(d_off),
		str(d_off.get("type", "")) == "SKIP_UNIT" and str(d_off.get("_ai_description", "")).contains("no valid targets in range"))
	_knob(1.0)
	var d_att: float = AIDM._shot_target_distance_inches(cg, boyz, snap, 24.0, spear)
	var e_on: float = AIDM._estimate_weapon_damage(spear, boyz, snap, cg)
	var s_on: float = AIDM._score_shooting_target(spear, boyz, snap, cg)
	_check("ON: the whole Attached unit is %.1f\" away (the Warboss), within 24\"" % d_att, d_att <= 24.0 and absf(d_att - 23.0) < 0.05)
	_check("ON: the estimates price the shot (estimate %.3f > 0, score %.3f > 0)" % [e_on, s_on], e_on > 0.0 and s_on > 0.0)
	var d_on: Dictionary = _decide()
	_check("ON: decide() shoots the Boyz (got %s)" % _shape(d_on),
		str(d_on.get("type", "")) == "SHOOT" and "U_BOYZ_B" in _targets_of(d_on))
	# The engine accepts the action as the AI built it.
	var v: Dictionary = RE.validate_shoot(d_on, GS.create_snapshot()) if RE.has_method("validate_shoot") else {"valid": true}
	_check("engine: validate_shoot accepts that SHOOT (%s)" % str(v.get("errors", v)), bool(v.get("valid", false)))

func _section_back_pointer() -> void:
	print("\n-- (b) a leader linked only by his own attached_to back-pointer --")
	GS.state.units.U_BOYZ_B["attachment_data"] = {"attached_characters": []}
	GS.state.units.U_WARBOSS_A["attached_to"] = "U_BOYZ_B"
	var snap: Dictionary = GS.create_snapshot()
	var cg: Dictionary = snap.units.U_CUSTODIAN_GUARD_A
	var spear := _spear(cg)
	var comps: Array = RE.attached_unit_component_ids("U_BOYZ_B", snap)
	_check("engine: the Attached unit still has both components (%s)" % str(comps), comps.size() == 2 and "U_WARBOSS_A" in comps)
	_knob(0.0)
	var e_off: float = AIDM._estimate_weapon_damage(spear, snap.units.U_BOYZ_B, snap, cg)
	_knob(1.0)
	var e_on: float = AIDM._estimate_weapon_damage(spear, snap.units.U_BOYZ_B, snap, cg)
	_check("OFF 0 (%.3f), ON > 0 (%.3f)" % [e_off, e_on], e_off == 0.0 and e_on > 0.0)
	GS.state.units.U_BOYZ_B["attachment_data"] = {"attached_characters": ["U_WARBOSS_A"]}

func _section_control_in_range() -> void:
	print("\n-- (c) control: a Boy in range — the estimate does not change --")
	var keep: Dictionary = GS.state.units.U_BOYZ_B.models[0].get("position", {}).duplicate()
	GS.state.units.U_BOYZ_B.models[0]["position"] = {"x": 420.0, "y": 1300.0}
	var snap: Dictionary = GS.create_snapshot()
	var cg: Dictionary = snap.units.U_CUSTODIAN_GUARD_A
	var spear := _spear(cg)
	_knob(0.0)
	var e_off: float = AIDM._estimate_weapon_damage(spear, snap.units.U_BOYZ_B, snap, cg)
	_knob(1.0)
	var e_on: float = AIDM._estimate_weapon_damage(spear, snap.units.U_BOYZ_B, snap, cg)
	_check("same estimate OFF and ON when a Boy is nearer than the Warboss (%.4f / %.4f)" % [e_off, e_on], e_off > 0.0 and e_off == e_on)
	GS.state.units.U_BOYZ_B.models[0]["position"] = keep

func _section_half_range() -> void:
	print("\n-- (d) half range (RAPID FIRE) from the whole-unit distance --")
	# Every Boy 13"+ away (beyond half of 24"), the Warboss 11" away (within it).
	var keep_w = GS.state.units.U_WARBOSS_A.models[0].get("position", {}).duplicate()
	var keep_b: Array = []
	for m in GS.state.units.U_BOYZ_B.models:
		keep_b.append(m.get("position", {}).duplicate() if m.get("position", null) is Dictionary else m.get("position", null))
	GS.state.units.U_WARBOSS_A.models[0]["position"] = {"x": 430.0, "y": 400.0 + 31.5 * 2.0 + 11.0 * 40.0}
	var j := 0
	for m in GS.state.units.U_BOYZ_B.models:
		if m.get("alive", true):
			m["position"] = {"x": 205.0 + float(j) * 50.0, "y": 400.0 + 31.5 + 25.2 + 13.5 * 40.0}
			j += 1
	var snap: Dictionary = GS.create_snapshot()
	var cg: Dictionary = snap.units.U_CUSTODIAN_GUARD_A
	var d_own: float = AIDM._get_closest_model_distance_inches(cg, snap.units.U_BOYZ_B)
	_knob(0.0)
	var e_off: float = AIDM._estimate_weapon_damage(BOLTER_RF, snap.units.U_BOYZ_B, snap, cg)
	_knob(1.0)
	var d_att: float = AIDM._shot_target_distance_inches(cg, snap.units.U_BOYZ_B, snap, 24.0, BOLTER_RF)
	var e_on: float = AIDM._estimate_weapon_damage(BOLTER_RF, snap.units.U_BOYZ_B, snap, cg)
	_check("setup: Boyz %.1f\" (beyond 12\"), Warboss %.1f\" (within 12\")" % [d_own, d_att], d_own > 12.0 and d_att <= 12.0)
	_check("ON adds the RAPID FIRE attacks (%.3f > %.3f, both in range)" % [e_on, e_off], e_off > 0.0 and e_on > e_off)
	GS.state.units.U_WARBOSS_A.models[0]["position"] = keep_w
	for i in range(GS.state.units.U_BOYZ_B.models.size()):
		GS.state.units.U_BOYZ_B.models[i]["position"] = keep_b[i]

# The engine's [MA-14] RAPID FIRE bonus off a resolve result's dice log (-1: none).
func _rf_bonus(res: Dictionary) -> int:
	for d in res.get("dice", []):
		if d is Dictionary and d.has("rapid_fire_bonus"):
			return int(d.get("rapid_fire_bonus", -1))
	return -1

func _section_half_range_back_pointer() -> void:
	print("\n-- (d') half range through a leader linked only by attached_to: AI credit == engine count --")
	# (d)'s board — every Boy 13.5" away (beyond half of 24"), the Warboss 11"
	# away (within it) — with the Custodians' own spear given [RAPID FIRE 1], so
	# the engine resolves the very weapon the AI prices. Two link shapes of the
	# same Attached unit: the forward attached_characters list (the engine always
	# agreed) and the Warboss's attached_to back-pointer alone (the engine's
	# half-range counts read the forward list only: 0/5 in half range, while the
	# AI credited all five — twice the attacks the engine rolled).
	var keep_w = GS.state.units.U_WARBOSS_A.models[0].get("position", {}).duplicate()
	var keep_b: Array = []
	for m in GS.state.units.U_BOYZ_B.models:
		keep_b.append(m.get("position", {}).duplicate() if m.get("position", null) is Dictionary else m.get("position", null))
	GS.state.units.U_WARBOSS_A.models[0]["position"] = {"x": 430.0, "y": 400.0 + 31.5 * 2.0 + 11.0 * 40.0}
	var j := 0
	for m in GS.state.units.U_BOYZ_B.models:
		if m.get("alive", true):
			m["position"] = {"x": 205.0 + float(j) * 50.0, "y": 400.0 + 31.5 + 25.2 + 13.5 * 40.0}
			j += 1
	# The engine reads the structured abilities (ISS-003: authoritative, the
	# special_rules string is re-synthesised from them); the AI reads the string.
	var spear_live: Dictionary = _spear(GS.state.units.U_CUSTODIAN_GUARD_A)
	var keep_sr := str(spear_live.get("special_rules", ""))
	var had_abilities: bool = spear_live.has("abilities")
	var keep_ab = spear_live.get("abilities", []).duplicate(true) if spear_live.get("abilities", []) is Array else spear_live.get("abilities")
	spear_live["special_rules"] = (keep_sr + ", " if keep_sr != "" else "") + "rapid fire 1"
	var ab_rf: Array = spear_live.get("abilities", []).duplicate(true) if spear_live.get("abilities", []) is Array else []
	ab_rf.append({"id": "rapid_fire", "x": 1})
	spear_live["abilities"] = ab_rf
	var got: Dictionary = {}
	for link in ["forward", "back_only"]:
		GS.state.units.U_BOYZ_B["attachment_data"] = {"attached_characters": ["U_WARBOSS_A"] if link == "forward" else []}
		GS.state.units.U_WARBOSS_A["attached_to"] = "U_BOYZ_B"
		RE.clear_los_memo()
		AIDM.reset_caches()
		var snap: Dictionary = GS.create_snapshot()
		var cg: Dictionary = snap.units.U_CUSTODIAN_GUARD_A
		var boyz: Dictionary = snap.units.U_BOYZ_B
		var spear := _spear(cg)
		var wid: String = RE.generate_weapon_id(str(spear.get("name", "")), str(spear.get("type", "")))
		var mids: Array = []
		for m in cg.models:
			if m.get("alive", true):
				mids.append(str(m.get("id", "")))
		var base_attacks: int = int(str(spear.get("attacks", "0"))) * mids.size()
		var d_own: float = AIDM._get_closest_model_distance_inches(cg, boyz)
		_knob(0.0)
		var e_off: float = AIDM._estimate_weapon_damage(spear, boyz, snap, cg)
		_knob(1.0)
		var d_att: float = AIDM._shot_target_distance_inches(cg, boyz, snap, 24.0, spear)
		var e_on: float = AIDM._estimate_weapon_damage(spear, boyz, snap, cg)
		var hr_melta: int = RE.count_models_in_half_range(cg, boyz, wid, mids, snap)
		var hr_rf: int = RE.count_models_in_half_range(cg, boyz, wid, mids, snap, true)
		var pv: Dictionary = RE.preview_attack("U_CUSTODIAN_GUARD_A", "U_BOYZ_B", wid, snap)
		var action := {"type": "SHOOT", "actor_unit_id": "U_CUSTODIAN_GUARD_A", "payload": {"assignments": [
			{"weapon_id": wid, "target_unit_id": "U_BOYZ_B", "model_ids": mids}]}}
		var rf_auto := _rf_bonus(RE.resolve_shoot(action, snap.duplicate(true), RE.RNGService.new(7)))
		var rf_inter := _rf_bonus(RE.resolve_shoot_until_wounds(action, snap.duplicate(true), RE.RNGService.new(7)))
		var comps: Array = RE.attached_unit_component_ids("U_BOYZ_B", snap)
		print("  [%s] comps=%s d_own=%.2f d_att=%.2f e_off=%.4f e_on=%.4f hr_melta=%d hr_rf=%d preview_attacks=%s rf_auto=%d rf_inter=%d (base %d)" % [
			link, str(comps), d_own, d_att, e_off, e_on, hr_melta, hr_rf, str(pv.get("total_attacks", "?")), rf_auto, rf_inter, base_attacks])
		_check("[%s] setup: one Attached unit (%s), Boyz %.1f\" (beyond 12\"), Warboss %.1f\" (within 12\")" % [link, str(comps), d_own, d_att],
			comps.size() == 2 and "U_WARBOSS_A" in comps and d_own > 12.0 and d_att <= 12.0 and mids.size() > 0)
		_check("[%s] AI ON credits [RAPID FIRE 1] for the whole unit (%.4f = %.4f x 3/2)" % [link, e_on, e_off],
			e_off > 0.0 and absf(e_on - e_off * 1.5) < 0.0005)
		_check("[%s] engine: every shooter within half range — MELTA path %d/%d, RAPID FIRE path %d/%d" % [link, hr_melta, mids.size(), hr_rf, mids.size()],
			hr_melta == mids.size() and hr_rf == mids.size())
		_check("[%s] engine: preview_attack gathers base + 1 per shooter (%s == %d)" % [link, str(pv.get("total_attacks", "?")), base_attacks + mids.size()],
			int(float(pv.get("total_attacks", -1))) == base_attacks + mids.size())
		_check("[%s] engine: [MA-14] +%d attacks in both resolve paths (auto-resolve %d, interactive %d)" % [link, mids.size(), rf_auto, rf_inter],
			rf_auto == mids.size() and rf_inter == mids.size())
		got[link] = e_on
	_check("the AI's credit is the same for both link shapes (%.4f / %.4f)" % [float(got.get("forward", -1.0)), float(got.get("back_only", -2.0))],
		got.has("forward") and is_equal_approx(float(got.forward), float(got.back_only)))
	spear_live["special_rules"] = keep_sr
	if had_abilities:
		spear_live["abilities"] = keep_ab
	else:
		spear_live.erase("abilities")
	GS.state.units.U_BOYZ_B["attachment_data"] = {"attached_characters": ["U_WARBOSS_A"]}
	GS.state.units.U_WARBOSS_A["attached_to"] = "U_BOYZ_B"
	GS.state.units.U_WARBOSS_A.models[0]["position"] = keep_w
	for i in range(GS.state.units.U_BOYZ_B.models.size()):
		GS.state.units.U_BOYZ_B.models[i]["position"] = keep_b[i]
	RE.clear_los_memo()
	AIDM.reset_caches()

func _section_engaged_pistol() -> void:
	print("\n-- (e) the engaged-pistol gate (T7-48) measures the leader too --")
	var snap: Dictionary = GS.create_snapshot()
	var cg: Dictionary = snap.units.U_CUSTODIAN_GUARD_A
	var w: Dictionary = snap.units.U_WARBOSS_A
	# The Warboss 0.5" from the nearest Custodian, every Boy far away.
	w.models[0]["position"] = Vector2(430.0, 400.0 + 31.5 * 2.0 + 0.5 * 40.0)
	_knob(0.0)
	var d_off: float = AIDM._shot_target_distance_inches(cg, snap.units.U_BOYZ_B, snap, 1.0)
	_knob(1.0)
	var d_on: float = AIDM._shot_target_distance_inches(cg, snap.units.U_BOYZ_B, snap, 1.0)
	_check("OFF %.1f\" (beyond 1\"), ON %.1f\" (within 1\")" % [d_off, d_on], d_off > 1.0 and d_on <= 1.0)

func _section_zero_is_unset() -> void:
	print("\n-- (f) 0.0 == unset: decide() byte-identical --")
	_knob(null)
	var a: Dictionary = _decide()
	_knob(0.0)
	var b: Dictionary = _decide()
	_check("unset and 0.0 give the same decision (%s)" % _shape(a), _shape(a) == _shape(b))

func _run() -> void:
	GS = root.get_node("GameState")
	TM = root.get_node("TerrainManager")
	RE = root.get_node("RulesEngine")
	SM = root.get_node("StratagemManager")
	MM = root.get_node("MissionManager")
	AIP = root.get_node("AIPlayer")
	AIDM = load(AI_PATH)
	print("\n=== FIX_SHOOT_ATTACHED_RANGE: a shot is in range of the whole Attached unit (11e 04.02 / 19.01) ===")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	if not _load_fixture():
		_check("fixture loaded (Custodian Guard A, Boyz B, Warboss A)", false)
		return
	_section_leader_only()
	_section_back_pointer()
	_section_control_in_range()
	_section_half_range()
	_section_half_range_back_pointer()
	_section_engaged_pistol()
	_section_zero_is_unset()
	AIDM._config_overrides.erase(KNOB)
	AIDM.reset_caches()
	GameConstants.edition = prev_edition
	_completed = true

extends SceneTree

# FIX-WAAAGH-ADVANCE-CHARGE (critic cluster "waaagh_advance_charge", round 4):
# Ork melee units Advanced "to attack" an enemy that a Normal move would have
# put in charge range, and then could not declare the charge (s7468 r3 P2
# Stormboyz: a Normal move measured +6.14 [3.08, 9.19] over 36 seeds).
#
# Root cause — the melee chase gate (_melee_chase_gate) decided "may charge
# after Advancing" by matching "advance" and "charge" in ability text. Every
# Ork unit's Waaagh! army rule contains both words, but the advance-and-charge
# clause only applies WHILE the unit is riled up (the turn of the once-per-
# battle War Cry and the next turn). The engine (ChargePhase) refuses a charge
# after an Advance without an active effect, so the gate now asks
# EffectPrimitives.has_effect_advance_and_charge, the engine's own test.
#
# Guards: a riled-up unit (flag set) still Advances; a unit that will be
# riled when selected to move (Keep Huntin'! from an attached Beastboss,
# unused this round) still Advances; a Kult of Speed SPEED FREEKS unit (engine
# grant) still Advances; an enemy beyond Normal-move + 12" is still chased
# with an Advance; FIX_WAAAGH_ADVANCE_CHARGE = 0 restores the text test.
# Bench Stormboyz ('Full Throttle' text, no engine grant) Normal-move.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_waaagh_advance_charge.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const ARMY := "res://armies/Orks_2000.json"
const PX := 40.0  # pixels per inch
const ORIGIN := Vector2(800, 1200)
const OBJ := Vector2(880, 1200)
const WAAAGH := {"name": "Waaagh!", "type": "Faction", "description": "Friendly ORKS units with this ability can:\n• Re-roll advance rolls.\n• Become riled up, as stated in other rules.\nWhile a unit is riled up:\n• That unit has 5+ InSv.\n• That unit's ranged attacks have [ASSAULT].\n• When that unit is selected to make an advance move, that advance move does not prevent that unit from being eligible to declare a charge.\nWar Cry (Once per battle, per army): At the start of the Command phase, you can use this ability. If you do, friendly ORKS units with the Waaagh! ability are riled up until the end of the next turn."}
const FULL_THROTTLE := {"name": "Full Throttle", "type": "Datasheet", "description": "The unit gains the Advance & Charge ability."}
const CHOPPA := {"name": "Choppa", "type": "Melee", "range": "Melee", "attacks": "3", "weapon_skill": "3",
	"strength": "5", "ap": "-1", "damage": "1", "special_rules": ""}
const BOLTER := {"name": "Boltgun", "type": "Ranged", "range": "24", "attacks": "2", "ballistic_skill": "3",
	"strength": "4", "ap": "0", "damage": "1", "special_rules": ""}

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _gs() -> Node:
	return root.get_node("GameState")

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== FIX-WAAAGH-ADVANCE-CHARGE: a dormant Waaagh! does not allow advance-and-charge ===\n")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	AIDM = load(AI_PATH)
	AIDM._config_overrides["FIX_WAAAGH_ADVANCE_CHARGE"] = 1.0

	test_dormant_waaagh_normal_moves_into_charge_range()
	test_active_waaagh_still_advances()
	test_far_enemy_still_advanced_toward()
	test_param_zero_restores_text_test()
	var saved_state: Dictionary = _gs().state.duplicate(true)
	test_keep_huntin_pending_keeps_the_advance()
	_gs().state = saved_state.duplicate(true)
	test_bench_stormboyz_full_throttle_normal_moves()
	_gs().state = saved_state.duplicate(true)
	test_kult_of_speed_engine_grant_still_advances()
	_gs().state = saved_state.duplicate(true)
	test_planner_dormant_waaagh_normal_move_attack()
	_gs().state = saved_state

	AIDM._config_overrides.erase("FIX_WAAAGH_ADVANCE_CHARGE")
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _boyz(flags: Dictionary = {}) -> Dictionary:
	var army = JSON.parse_string(FileAccess.get_file_as_string(ARMY))
	var u: Dictionary = army["units"]["U_BEAST_SNAGGA_BOYZ_A"].duplicate(true)
	u["owner"] = 1
	u["flags"] = flags.duplicate()
	var i := 0
	for m in u["models"]:
		m["alive"] = true
		m["position"] = {"x": ORIGIN.x + float(i % 5) * 34.0, "y": ORIGIN.y + float(i / 5) * 34.0}
		i += 1
	return u

func _enemy(dist_inches: float) -> Dictionary:
	# A lone 40mm model straight ahead of the Boyz' centroid.
	var army = JSON.parse_string(FileAccess.get_file_as_string(ARMY))
	var boyz: Dictionary = _boyz()
	var c = AIDM._get_unit_centroid(boyz)
	return {"id": "U_ENEMY", "owner": 2, "status": 2, "flags": {},
		"meta": {"name": "Prosecutor Squad", "keywords": ["INFANTRY"], "stats": {"move": 6, "toughness": 3, "save": 3, "wounds": 1, "objective_control": 2}},
		"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 40,
			"position": {"x": c.x + dist_inches * PX, "y": c.y}}]}

func _gate(boyz: Dictionary, enemy_dist: float) -> Dictionary:
	var enemy = _enemy(enemy_dist)
	var snapshot = {"meta": {"battle_round": 3, "active_player": 1}, "battle_round": 3,
		"units": {"U_BEAST_SNAGGA_BOYZ_A": boyz, "U_ENEMY": enemy}, "factions": {"1": "Orks", "2": "Adeptus Custodes"}}
	var assignment = {"action": "move", "objective_id": "obj_far",
		"objective_pos": AIDM._get_unit_centroid(boyz) + Vector2(0, 30 * PX)}
	return AIDM._melee_chase_gate(boyz, "U_BEAST_SNAGGA_BOYZ_A", assignment,
		{"U_ENEMY": enemy}, {"U_BEAST_SNAGGA_BOYZ_A": boyz}, snapshot, 1)

func test_dormant_waaagh_normal_moves_into_charge_range():
	# 12" away, M6: a Normal move leaves 6" — a charge this turn. Advancing
	# without an active Waaagh! would forfeit it (ChargePhase refuses).
	var gate = _gate(_boyz(), 12.0)
	_assert(not gate.is_empty(), "dormant Waaagh!: the gate still sends the Boyz to attack (got %s)" % str(gate))
	_assert(not gate.is_empty() and gate.get("advance", true) == false,
		"dormant Waaagh!: Normal move into charge range, not an Advance (advance=%s)" % str(gate.get("advance", "?")))

func test_active_waaagh_still_advances():
	# Riled up (the engine sets effect_advance_and_charge): Advancing keeps
	# the charge, so the extra inches are free.
	var gate = _gate(_boyz({"waaagh_active": true, "effect_advance_and_charge": true}), 12.0)
	_assert(not gate.is_empty() and gate.get("advance", false) == true,
		"active Waaagh!: the Boyz still Advance to attack (advance=%s)" % str(gate.get("advance", "?")))

func test_far_enemy_still_advanced_toward():
	# 19" away: a Normal move leaves 13" (no charge this turn either way), so
	# the gate still Advances to close the distance (inside the 20" chase cap).
	var gate = _gate(_boyz(), 19.0)
	_assert(not gate.is_empty() and gate.get("advance", false) == true,
		"enemy beyond Normal move + 12\": still Advances to close (advance=%s)" % str(gate.get("advance", "?")))

func test_param_zero_restores_text_test():
	AIDM._config_overrides["FIX_WAAAGH_ADVANCE_CHARGE"] = 0.0
	var gate = _gate(_boyz(), 12.0)
	_assert(not gate.is_empty() and gate.get("advance", false) == true,
		"FIX_WAAAGH_ADVANCE_CHARGE=0: the text test (Advance) is back (advance=%s)" % str(gate.get("advance", "?")))
	AIDM._config_overrides["FIX_WAAAGH_ADVANCE_CHARGE"] = 1.0

# --- Live-GameState cases (the rile / detachment lookups read GameState) ---

func _live_board(units: Dictionary, detachment: String) -> void:
	_gs().state["units"] = units
	_gs().state["meta"]["battle_round"] = 3
	_gs().state["meta"]["active_player"] = 1
	_gs().state["factions"] = {"1": {"name": "Orks", "detachment": detachment}, "2": {"name": "Adeptus Custodes", "detachment": ""}}
	_gs().state["players"] = {"1": {}, "2": {}}

func _gate_live(u: Dictionary, unit_id: String, enemy_dist: float) -> Dictionary:
	var enemy = _enemy(enemy_dist)
	var c = AIDM._get_unit_centroid(u)
	enemy["models"][0]["position"] = {"x": c.x + enemy_dist * PX, "y": c.y}
	var snapshot = {"meta": {"battle_round": 3, "active_player": 1}, "battle_round": 3,
		"units": {unit_id: u, "U_ENEMY": enemy}, "factions": _gs().state["factions"]}
	var assignment = {"action": "move", "objective_id": "obj_far",
		"objective_pos": c + Vector2(0, 30 * PX)}
	return AIDM._melee_chase_gate(u, unit_id, assignment, {"U_ENEMY": enemy}, {unit_id: u}, snapshot, 1)

func test_keep_huntin_pending_keeps_the_advance():
	# Beast Snagga Boyz + attached Beastboss (Keep Huntin'!), 13" from the
	# enemy. Unused this round, the ability riles the unit when it is
	# selected to move, so the Advance keeps the charge. Used this round, it
	# cannot, so the Boyz Normal-move.
	var army = JSON.parse_string(FileAccess.get_file_as_string(ARMY))
	var boyz: Dictionary = _boyz()
	boyz["id"] = "U_BEAST_SNAGGA_BOYZ_A"
	boyz["status"] = GameStateData.UnitStatus.DEPLOYED
	var boss: Dictionary = army["units"]["U_BEASTBOSS_A"].duplicate(true)
	boss["id"] = "U_BEASTBOSS_A"
	boss["owner"] = 1
	boss["flags"] = {}
	boss["status"] = GameStateData.UnitStatus.DEPLOYED
	boss["attached_to"] = "U_BEAST_SNAGGA_BOYZ_A"
	for m in boss["models"]:
		m["alive"] = true
		m["position"] = {"x": ORIGIN.x - 40.0, "y": ORIGIN.y}
	boyz["attachment_data"] = {"attached_characters": ["U_BEASTBOSS_A"]}
	_live_board({"U_BEAST_SNAGGA_BOYZ_A": boyz, "U_BEASTBOSS_A": boss}, "War Horde")
	_gs().state["players"]["1"]["ork11e_ab_uses"] = {"keep_huntin": {"battle": 1, "round": 2}}
	var gate = _gate_live(boyz, "U_BEAST_SNAGGA_BOYZ_A", 13.0)
	_assert(not gate.is_empty() and gate.get("advance", false) == true,
		"Keep Huntin'! unused this round (used in round 2): the Boyz keep the Advance (advance=%s)" % str(gate.get("advance", "?")))
	_gs().state["players"]["1"]["ork11e_ab_uses"] = {"keep_huntin": {"battle": 1, "round": 3}}
	gate = _gate_live(boyz, "U_BEAST_SNAGGA_BOYZ_A", 13.0)
	_assert(not gate.is_empty() and gate.get("advance", true) == false,
		"Keep Huntin'! already used this round: the Boyz Normal-move to keep the charge (advance=%s)" % str(gate.get("advance", "?")))

func _stormboyz(keywords: Array) -> Dictionary:
	var models = []
	for i in range(5):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 32, "wounds": 1, "current_wounds": 1,
			"position": {"x": ORIGIN.x + float(i) * 34.0, "y": ORIGIN.y}})
	return {"id": "U_STORMBOYZ_A", "owner": 1, "status": GameStateData.UnitStatus.DEPLOYED, "flags": {},
		"meta": {"name": "Stormboyz", "keywords": keywords,
			"stats": {"move": 12, "toughness": 5, "save": 5, "wounds": 1, "leadership": 7, "objective_control": 1},
			"weapons": [CHOPPA], "abilities": [WAAAGH, FULL_THROTTLE]},
		"models": models}

func test_bench_stormboyz_full_throttle_normal_moves():
	# Bench Stormboyz: the Waaagh! text plus 'Full Throttle: The unit gains
	# the Advance & Charge ability.' The engine grants neither (not SPEED
	# FREEKS), so an Advance would forfeit the charge — Normal move (M12,
	# enemy 18": 6" after the move).
	var sb := _stormboyz(["FLY", "INFANTRY", "JUMP PACK", "ORKS", "STORMBOYZ"])
	_live_board({"U_STORMBOYZ_A": sb}, "War Horde")
	var gate = _gate_live(sb, "U_STORMBOYZ_A", 18.0)
	_assert(not gate.is_empty() and gate.get("advance", true) == false,
		"bench Stormboyz (Full Throttle text, no engine grant): Normal move to attack (advance=%s)" % str(gate.get("advance", "?")))

func test_kult_of_speed_engine_grant_still_advances():
	# A SPEED FREEKS unit in a Kult of Speed army: the engine grants
	# advance-and-charge (OrkDetachments11e.advance_allows_charge), so the
	# unit still Advances.
	var sb := _stormboyz(["FLY", "INFANTRY", "ORKS", "SPEED FREEKS"])
	_live_board({"U_STORMBOYZ_A": sb}, "Kult of Speed")
	var gate = _gate_live(sb, "U_STORMBOYZ_A", 18.0)
	_assert(not gate.is_empty() and gate.get("advance", false) == true,
		"Kult of Speed SPEED FREEKS (engine says yes): still Advances to attack (advance=%s)" % str(gate.get("advance", "?")))

# --- Planner level (graft from the 'narrow' design): _decide_movement ---

func _planner_board(enemy_in: float) -> Dictionary:
	var snap = {"battle_round": 3, "meta": {"battle_round": 3, "first_turn_player": 1},
		"board": {"objectives": [
			{"id": "obj_center", "position": OBJ, "zone": "no_mans_land"},
			{"id": "obj_home_1", "position": Vector2(880, 240), "zone": "player1"},
			{"id": "obj_home_2", "position": Vector2(880, 2160), "zone": "player2"},
		], "terrain_features": []}, "units": {}}
	var start = OBJ + Vector2(-500, 0)
	_add_planner_unit(snap, "boyz", 1, start, 5, 12, [CHOPPA], [WAAAGH], ["INFANTRY", "ORKS"])
	_add_planner_unit(snap, "marines", 2, start + Vector2(0, enemy_in * PX), 5, 6, [BOLTER], [], ["INFANTRY"])
	return snap

func _add_planner_unit(snapshot: Dictionary, unit_id: String, owner: int, pos: Vector2, n: int,
		move: int, weapons: Array, abilities: Array, keywords: Array) -> void:
	var models = []
	for i in range(n):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 32,
			"base_type": "circular", "base_dimensions": {},
			"position": Vector2(pos.x + (i - (n - 1) / 2.0) * 40.0, pos.y), "wounds": 2, "current_wounds": 2})
	snapshot.units[unit_id] = {
		"id": unit_id, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": unit_id, "points": 100, "stats": {"move": move, "toughness": 5, "save": 5,
			"wounds": 2, "leadership": 7, "objective_control": 2}, "keywords": keywords,
			"weapons": weapons, "abilities": abilities},
		"models": models, "flags": {}}

func test_planner_dormant_waaagh_normal_move_attack():
	# Ork chaser (Waaagh! not riled up), M12, enemy 12" away: the planner
	# converts it to ATTACK and executes it as a Normal move.
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	var actions = [
		{"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "boyz"},
		{"type": "BEGIN_ADVANCE", "actor_unit_id": "boyz"},
		{"type": "REMAIN_STATIONARY", "actor_unit_id": "boyz"},
		{"type": "END_MOVEMENT"},
	]
	var d = AIDM._decide_movement(_planner_board(12.0), actions, 1)
	print("  -> %s %s (%s)" % [d.get("type", ""), d.get("actor_unit_id", ""), str(d.get("_ai_description", "")).substr(0, 120)])
	_assert(str(d.get("_ai_description", "")).contains("attack marines") and str(d.get("type", "")) == "BEGIN_NORMAL_MOVE",
		"planner: dormant Waaagh! chaser makes a Normal move to attack (%s, %s)" % [d.get("type", ""), str(d.get("_ai_description", "")).substr(0, 80)])

extends SceneTree

# FIX_OBJ_AREA_ON_OBJ (11e rules audit OC-03, protocol V2-4): target
# valuation read "standing on an objective" as the unit CENTROID within 3.79"
# of the objective MARKER. Every bench objective is a terrain area, and 11e
# 14.02 puts a model within range of a terrain objective while it is within
# that terrain area (01.04.01: one model is enough; MissionManager counts a
# base overlapping the hosting area). At bench deployment U_CUSTODIAN_GUARD_F
# has all 5 models on area-large-14 with its centroid 4.95" from the marker,
# so _calculate_target_value paid it the 'near' premium (x1.15) instead of the
# objective-holder premium (x1.4 + 0.5/OC); 63% of real holders were misread.
# Same test in the charge target, fight target, fight order, phase plan,
# focus fire and Insane Bravery valuations.
#
# Fix: _unit_on_objective - a model within the objective's range
# (MissionManager's area predicate on a terrain objective, base edge within
# 3" + 20 mm of the marker on open ground); 'near' = the nearest model within
# 3.79" of the range (OC-01's _obj_gap_px).
#
# Guards: a unit 8" from every area gets neither term; a unit standing round
# the marker is 'on' either way; a unit 1" outside the area's long edge is
# 'near' either way. FIX_OBJ_AREA_ON_OBJ = 0 restores the centroid test.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_obj_area_on_obj.gd
# (runs once the scene tree is up: the fix reads MissionManager/TerrainManager)

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const PX := 40.0  # pixels per inch
const OBJ := Vector2(600, 1200)
const HALF := Vector2(140, 230)  # area-large: 7" (x) by 11.5" (y) around the marker
const R40 := 31.5  # 40 mm base radius, px
const SPEAR := {"name": "Guardian spear", "type": "Melee", "range": "Melee", "attacks": "5", "weapon_skill": "2",
	"strength": "7", "ap": "-2", "damage": "2", "special_rules": ""}

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

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
	print("\n=== FIX_OBJ_AREA_ON_OBJ: 'on objective' = a model on the hosting area, not the centroid by the marker ===\n")
	var mm = root.get_node_or_null("MissionManager")
	var tm = root.get_node_or_null("TerrainManager")
	_assert(mm != null and tm != null, "MissionManager / TerrainManager autoloads present")
	if mm == null or tm == null:
		print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_terrain = tm.terrain_features.duplicate(true)
	tm.terrain_features = [{"id": "area_obj", "piece_class": "area", "type": "ruins",
		"height_category": "tall", "polygon": PackedVector2Array([
			OBJ + Vector2(-HALF.x, -HALF.y), OBJ + Vector2(HALF.x, -HALF.y),
			OBJ + Vector2(HALF.x, HALF.y), OBJ + Vector2(-HALF.x, HALF.y)])}]
	AIDM = load(AI_PATH)

	test_area_holder_valued_as_on_objective()
	test_fight_target_on_area_gets_objective_bonus()
	test_param_zero_restores_centroid_test()
	test_guard_far_unit_gets_neither_term()
	test_guard_unit_round_marker_is_on_either_way()
	test_guard_unit_just_off_long_edge_is_near_either_way()

	AIDM._config_overrides.erase("FIX_OBJ_AREA_ON_OBJ")
	tm.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _snapshot(battle_round: int = 2) -> Dictionary:
	var objs = [{"id": "obj_area", "position": OBJ, "zone": "no_mans_land", "source_pieces": ["area_obj"]}]
	return {"battle_round": battle_round, "meta": {"battle_round": battle_round},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

func _unit(uid: String, owner: int, positions: Array, oc: int = 2) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 40,
			"base_type": "circular", "base_dimensions": {}, "position": positions[i],
			"wounds": 3, "current_wounds": 3})
	return {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "points": 170, "stats": {"move": 6, "toughness": 6, "save": 2,
			"wounds": 3, "leadership": 6, "objective_control": oc},
			"keywords": ["INFANTRY"], "weapons": [SPEAR]},
		"models": models, "flags": {}}

## U_CUSTODIAN_GUARD_F at bench deployment: 5 models on the area in a line,
## centroid 4.95" (198 px) from the marker.
func _area_holder() -> Dictionary:
	var y := OBJ.y + 198
	return _unit("HOLDER", 2, [Vector2(OBJ.x - 128, y), Vector2(OBJ.x - 64, y), Vector2(OBJ.x, y),
		Vector2(OBJ.x + 64, y), Vector2(OBJ.x + 128, y)])

func _set_fix(v: float) -> void:
	AIDM._config_overrides["FIX_OBJ_AREA_ON_OBJ"] = v

func _target_terms(target: Dictionary) -> Dictionary:
	AIDM.reset_caches()
	var snap = _snapshot()
	snap.units[target.id] = target
	var terms := {}
	AIDM._calculate_target_value(target, snap, 1, terms)
	return terms

func _fight_terms(target: Dictionary) -> Dictionary:
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	var snap = _snapshot()
	var attacker = _unit("ATTACKER", 1, [OBJ + Vector2(0, 300)])
	snap.units[target.id] = target
	snap.units["ATTACKER"] = attacker
	var terms := {}
	AIDM._score_fight_target(attacker, target, 4.0, snap, 1, AIDM._get_objectives(snap), terms)
	return terms

# --- tests --------------------------------------------------------------------

func test_area_holder_valued_as_on_objective() -> void:
	print("\n--- (a) 5 models on the area, centroid 4.95\" from the marker: shooting target value ---")
	_set_fix(1.0)
	var terms = _target_terms(_area_holder())
	print("  terms: %s" % str(terms))
	_assert(terms.has("tv_on_objective"), "fix on: the area holder gets the objective-holder premium (tv_on_objective)")
	_assert(not terms.has("tv_near_objective"), "fix on: not the 'near' premium")

func test_fight_target_on_area_gets_objective_bonus() -> void:
	print("\n--- (a) the same unit as a fight target ---")
	_set_fix(1.0)
	var terms = _fight_terms(_area_holder())
	print("  fight terms: %s" % str(terms))
	_assert(terms.has("fight_target_on_objective"), "fix on: fight_target_on_objective bonus for the area holder")

func test_param_zero_restores_centroid_test() -> void:
	print("\n--- (b) FIX_OBJ_AREA_ON_OBJ = 0: the centroid-within-3.79\"-of-the-marker test ---")
	_set_fix(0.0)
	var terms = _target_terms(_area_holder())
	print("  terms: %s" % str(terms))
	_assert(not terms.has("tv_on_objective"), "off: no tv_on_objective (centroid 4.95\" > 3.79\")")
	_assert(terms.has("tv_near_objective"), "off: the 'near' premium (centroid within 7.57\")")
	var fterms = _fight_terms(_area_holder())
	_assert(not fterms.has("fight_target_on_objective"), "off: no fight_target_on_objective bonus")
	_set_fix(1.0)

func test_guard_far_unit_gets_neither_term() -> void:
	print("\n--- (c) guard: a unit 8\" from the area's long edge ---")
	var x := OBJ.x + HALF.x + 8.0 * PX + R40
	for v in [0.0, 1.0]:
		_set_fix(v)
		var terms = _target_terms(_unit("FAR", 2, [Vector2(x, OBJ.y - 40), Vector2(x, OBJ.y + 40), Vector2(x + 64, OBJ.y)]))
		_assert(not terms.has("tv_on_objective") and not terms.has("tv_near_objective"),
			"fix=%.0f: neither objective term (%s)" % [v, str(terms.keys())])
		var fterms = _fight_terms(_unit("FAR", 2, [Vector2(x, OBJ.y - 40), Vector2(x, OBJ.y + 40), Vector2(x + 64, OBJ.y)]))
		_assert(not fterms.has("fight_target_on_objective"), "fix=%.0f: no fight objective bonus" % v)
	_set_fix(1.0)

func test_guard_unit_round_marker_is_on_either_way() -> void:
	print("\n--- (c) guard: a unit standing round the marker (centroid on it) ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var u = _unit("MARK", 2, [OBJ + Vector2(-64, 0), OBJ + Vector2(64, 0), OBJ + Vector2(0, -64), OBJ + Vector2(0, 64)])
		var terms = _target_terms(u)
		_assert(terms.has("tv_on_objective") and not terms.has("tv_near_objective"),
			"fix=%.0f: tv_on_objective (%s)" % [v, str(terms.keys())])
		_assert(_fight_terms(u).has("fight_target_on_objective"), "fix=%.0f: fight objective bonus" % v)
	_set_fix(1.0)

func test_guard_unit_just_off_long_edge_is_near_either_way() -> void:
	print("\n--- (c) guard: a single model 1\" outside the area's long edge (centre 5.3\" from the marker) ---")
	for v in [0.0, 1.0]:
		_set_fix(v)
		var terms = _target_terms(_unit("EDGE", 2, [OBJ + Vector2(HALF.x + 1.0 * PX + R40, 0)]))
		_assert(terms.has("tv_near_objective") and not terms.has("tv_on_objective"),
			"fix=%.0f: 'near', not 'on' (%s)" % [v, str(terms.keys())])
	_set_fix(1.0)

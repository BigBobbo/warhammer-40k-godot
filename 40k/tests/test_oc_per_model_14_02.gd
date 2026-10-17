extends SceneTree

# 14.02 LEVEL OF CONTROL is a PER-MODEL sum (docs/rules/40k_11th_edition_core_rules.txt):
#   "At the end of each phase and turn, to determine a player's level of
#    control over an objective, add together the OC characteristics of all
#    the models in that player's army that are within range of that
#    objective" — and the worked example: "The models in this unit each have
#    an OC characteristic of 1. Six of its models are within the terrain
#    area." ... "The RED player's level of control is 6."
# MissionManager._check_objective_control used to add each unit's OC ONCE
# (10 x OC2 Boyz = 2), so 2 x OC3 took the objective off 10 x OC2.
#
# Coverage:
#   A) 10 x OC2 vs 2 x OC3 on a terrain objective -> P1 20 vs 6, P1 controls
#   B) open-ground marker (3" of the marker) vs terrain objective (14.01: on
#      the area, even far from the point; off the area does not count)
#   C) mixed in/out of range models of ONE unit: only the in-range ones add
#   D) equal per-model totals -> uncontrolled AND flagged contested
#   E) battle-shocked unit adds nothing (01.07: OC '-')
#   F) per-model profile OC (model_profiles[...].stats_override.objective_control)
#   G) Da Boss Iz Watchin' override is per model of ITS unit dict (not the
#      Boyz it leads); +OC (HUGE SHOW-OFFS / DAT'S OURS) is +1 PER MODEL;
#      override + additive; OC 0 + bonus stays 0
#   H) attached unit (19.01): both components summed; a leader-only or
#      bodyguard-only battle-shock flag zeroes the whole group; a wiped
#      bodyguard's stale flag does not shock its surviving leader
#   I) 10e marker path sums per model too
#   J) 14.03 secured objective: a per-model tie holds, a mid-phase lead does
#      not break it, a phase-end per-model lead does
#   K) CasualtyPreference parity: the computer's casualty pick protects the
#      one model whose OC removal would flip control under the per-model sum
#
# Usage: godot --headless --path . -s tests/test_oc_per_model_14_02.gd

var passed := 0
var failed := 0
var _ran := false

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _models(prefix: String, positions: Array, extra: Dictionary = {}) -> Array:
	var out: Array = []
	for i in range(positions.size()):
		var p: Vector2 = positions[i]
		var m = {"id": "%s%d" % [prefix, i + 1], "alive": true, "base_mm": 32,
			"base_type": "circular", "position": {"x": p.x, "y": p.y}}
		for k in extra:
			m[k] = extra[k]
		out.append(m)
	return out

func _unit(id: String, owner: int, oc: int, positions: Array) -> Dictionary:
	return {"id": id, "owner": owner, "status": 2,  # UnitStatus.DEPLOYED (raw int)
		"flags": {}, "attached_to": null, "attachment_data": {"attached_characters": []},
		"meta": {"name": id, "keywords": ["INFANTRY"], "stats": {"objective_control": oc}},
		"models": _models(id.to_lower() + "_m", positions)}

## n positions on a row starting at (x, y), `step` px apart.
func _row(x: float, y: float, n: int, step: float = 24.0) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(Vector2(x + i * step, y))
	return out

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== test_oc_per_model_14_02 ===\n")
	var mm = root.get_node_or_null("MissionManager")
	var gs = root.get_node_or_null("GameState")
	var tm = root.get_node_or_null("TerrainManager")
	_check("MissionManager / GameState / TerrainManager autoloads present", mm != null and gs != null and tm != null)
	if mm == null or gs == null or tm == null:
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	_check("edition pinned to 11 for this suite", GameConstants.edition == 11, str(GameConstants.edition))
	var prev_state = gs.state.duplicate(true)
	var prev_ctrl = mm.objective_control_state.duplicate(true)
	var prev_contested = mm.objective_contested_state.duplicate(true)
	var prev_sticky = mm._sticky_objectives.duplicate(true)
	var prev_terrain = tm.terrain_features.duplicate(true)
	mm._sticky_objectives = {}

	# Terrain objective: one area 600..1100 x 300..500, the objective point
	# near its LEFT edge (620,400) so a base can be within 3" of the point
	# while OFF the area.
	var area = {"id": "area_obj", "piece_class": "area", "type": "ruins",
		"polygon": PackedVector2Array([Vector2(600, 300), Vector2(1100, 300),
			Vector2(1100, 500), Vector2(600, 500)]), "height_category": "tall"}
	tm.terrain_features = [area]
	var terrain_obj = {"id": "OBJ_T", "position": Vector2(620, 400)}

	# ── A) the reported bug ────────────────────────────────────────────
	print("-- A) 10 x OC2 vs 2 x OC3 on a terrain objective --")
	var units_a = {
		"P1_BOYZ": _unit("P1_BOYZ", 1, 2, _row(640, 340, 10)),
		"P2_ELITE": _unit("P2_ELITE", 2, 3, _row(700, 460, 2)),
	}
	var loc_a = mm.get_level_of_control(terrain_obj, units_a)
	_check("P1 level of control = 10 models x OC2 = 20", int(loc_a[1]) == 20, str(loc_a))
	_check("P2 level of control = 2 models x OC3 = 6", int(loc_a[2]) == 6, str(loc_a))
	_check("P1 controls (20 > 6; per-unit counting gave P2 3 > 2)",
		mm._check_objective_control(terrain_obj, units_a) == 1)
	_check("model_oc reads the statline per model", mm.model_oc(units_a.P1_BOYZ, units_a.P1_BOYZ.models[0]) == 2)

	# ── B) open-ground marker vs terrain objective ─────────────────────
	print("\n-- B) open-ground marker range vs terrain-objective area --")
	var meas = root.get_node("Measurement")
	var r_px = meas.base_radius_px(32)
	var ctrl_px = meas.inches_to_px(3.78740157)  # 3" + the 20mm marker radius
	var marker = {"id": "OBJ_M", "position": Vector2(1500, 1500)}  # no area here
	var units_b = {
		"P1_IN": _unit("P1_IN", 1, 1, [Vector2(1500 + ctrl_px + r_px - 2.0, 1500)]),
		"P1_OUT": _unit("P1_OUT", 1, 1, [Vector2(1500, 1500 - ctrl_px - r_px - 4.0)]),
	}
	var loc_b = mm.get_level_of_control(marker, units_b)
	_check("open ground: the base within 3\" of the marker adds, the one beyond does not", int(loc_b[1]) == 1, str(loc_b))
	var units_t = {
		# on the area but ~11" from the objective point: in range (14.01)
		"P1_FAR_ON": _unit("P1_FAR_ON", 1, 2, [Vector2(1080, 480)]),
		# within 3" of the point but its base is OFF the area: not in range
		"P1_NEAR_OFF": _unit("P1_NEAR_OFF", 1, 5, [Vector2(560, 400)]),
	}
	var loc_t = mm.get_level_of_control(terrain_obj, units_t)
	_check("terrain objective: only the on-area model adds (2, not 2+5)", int(loc_t[1]) == 2, str(loc_t))

	# ── C) mixed in/out of range models of one unit ────────────────────
	print("\n-- C) mixed in/out of range models in one unit --")
	var mixed_pos = _row(640, 400, 4) + _row(300, 700, 6)  # 4 on the area, 6 far off it
	var units_c = {"P2_MIXED": _unit("P2_MIXED", 2, 1, mixed_pos)}
	var loc_c = mm.get_level_of_control(terrain_obj, units_c)
	_check("only the 4 in-range models add (4 x OC1)", int(loc_c[2]) == 4, str(loc_c))

	# ── D) tie -> uncontrolled, contested ──────────────────────────────
	print("\n-- D) equal per-model totals --")
	var units_d = {
		"P1_PAIR": _unit("P1_PAIR", 1, 2, _row(640, 340, 2)),   # 2 x OC2 = 4
		"P2_FOUR": _unit("P2_FOUR", 2, 1, _row(640, 460, 4)),   # 4 x OC1 = 4
	}
	mm.objective_control_state["OBJ_T"] = 0
	var ctrl_d = mm._check_objective_control(terrain_obj, units_d)
	_check("4 vs 4 -> not controlled by either player (per-unit gave P1 2 > 1)", ctrl_d == 0, str(ctrl_d))
	_check("4 vs 4 is flagged CONTESTED (nonzero tie)", mm.objective_contested_state.get("OBJ_T", false) == true)

	# ── E) battle-shocked unit ─────────────────────────────────────────
	print("\n-- E) battle-shocked unit --")
	var units_e = {
		"P1_ONE": _unit("P1_ONE", 1, 1, [Vector2(640, 340)]),
		"P2_SHOCKED": _unit("P2_SHOCKED", 2, 3, _row(640, 460, 3)),
	}
	units_e.P2_SHOCKED.flags["battle_shocked"] = true
	_check("battle-shocked unit adds nothing (OC '-')", int(mm.get_level_of_control(terrain_obj, units_e)[2]) == 0)
	_check("so the lone OC1 model controls", mm._check_objective_control(terrain_obj, units_e) == 1)

	# ── F) per-model profile OC ────────────────────────────────────────
	print("\n-- F) per-model profile OC (stats_override.objective_control) --")
	var kroot = _unit("P1_KROOT", 1, 1, _row(640, 340, 9))
	kroot.meta["model_profiles"] = {
		"farstalker": {"label": "Kroot Farstalker", "stats_override": {}},
		"hound": {"label": "Kroot Hound", "stats_override": {"objective_control": 0}},
	}
	for i in range(9):
		kroot.models[i]["model_type"] = "farstalker" if i < 5 else "hound"
	_check("5 Farstalkers (OC1) + 4 Hounds (OC0) = 5", int(mm.get_level_of_control(terrain_obj, {"P1_KROOT": kroot})[1]) == 5)
	var king = _unit("P2_KING", 2, 6, _row(640, 460, 3))
	king.meta["model_profiles"] = {"menhir": {"label": "Triarchal Menhir", "stats_override": {"objective_control": 1}}}
	king.models[1]["model_type"] = "menhir"
	king.models[2]["model_type"] = "menhir"
	_check("Szarekh (OC6) + 2 Menhirs (override OC1) = 8", int(mm.get_level_of_control(terrain_obj, {"P2_KING": king})[2]) == 8)

	# ── G) override / additive modifiers ───────────────────────────────
	print("\n-- G) Da Boss override is per model of its own dict; +OC is per model --")
	var boyz = _unit("P1_BOYZ_G", 1, 2, _row(640, 340, 10))
	var banner = _unit("P1_BANNER", 1, 2, [Vector2(900, 400)])
	banner.flags["effect_oc_override"] = 5
	banner["attached_to"] = "P1_BOYZ_G"
	boyz.attachment_data.attached_characters = ["P1_BANNER"]
	var loc_g1 = mm.get_level_of_control(terrain_obj, {"P1_BOYZ_G": boyz, "P1_BANNER": banner})
	_check("Banner Nob OC5 + 10 Boyz OC2 = 25 (override stays on the Nob's model)", int(loc_g1[1]) == 25, str(loc_g1))
	var trio = _unit("P2_TRIO", 2, 2, _row(640, 460, 3))
	trio.flags["effect_oc_override"] = 5
	_check("override on a 3-model unit dict sets EACH model to 5 (15)", int(mm.get_level_of_control(terrain_obj, {"P2_TRIO": trio})[2]) == 15)
	var show_offs = _unit("P2_SHOW", 2, 2, _row(640, 460, 5))
	show_offs.flags[EffectPrimitivesData.FLAG_PLUS_OC] = 1
	_check("+1 OC to models in the unit: 5 x (2+1) = 15, not 2+1", int(mm.get_level_of_control(terrain_obj, {"P2_SHOW": show_offs})[2]) == 15)
	var both = _unit("P2_BOTH", 2, 2, _row(640, 460, 2))
	both.flags["effect_oc_override"] = 5
	both.flags[EffectPrimitivesData.FLAG_PLUS_OC] = 1
	_check("override then additive: 2 x (5+1) = 12", int(mm.get_level_of_control(terrain_obj, {"P2_BOTH": both})[2]) == 12)
	var zero = _unit("P2_ZERO", 2, 0, _row(640, 460, 3))
	zero.flags[EffectPrimitivesData.FLAG_PLUS_OC] = 1
	_check("OC 0 + bonus stays 0 (existing order kept)", int(mm.get_level_of_control(terrain_obj, {"P2_ZERO": zero})[2]) == 0)

	# ── H) attached units (19.01) ──────────────────────────────────────
	print("\n-- H) attached unit: summed as one unit, battle-shocked as one unit --")
	var bg = _unit("P1_BG", 1, 2, _row(640, 340, 5))
	var ldr = _unit("P1_LDR", 1, 1, [Vector2(800, 340)])
	ldr["attached_to"] = "P1_BG"
	bg.attachment_data.attached_characters = ["P1_LDR"]
	var units_h = {"P1_BG": bg, "P1_LDR": ldr}
	_check("bodyguard 5 x OC2 + leader OC1 = 11", int(mm.get_level_of_control(terrain_obj, units_h)[1]) == 11)
	ldr.flags["battle_shocked"] = true
	_check("leader-only battle-shock flag zeroes the WHOLE attached unit", int(mm.get_level_of_control(terrain_obj, units_h)[1]) == 0)
	ldr.flags.erase("battle_shocked")
	bg.flags["battle_shocked"] = true
	_check("bodyguard-only battle-shock flag zeroes the leader too", int(mm.get_level_of_control(terrain_obj, units_h)[1]) == 0)
	_check("AttackSequence.group_battle_shocked sees it from either id",
		AttackSequence.group_battle_shocked("P1_LDR", units_h) and AttackSequence.group_battle_shocked("P1_BG", units_h))
	for m in bg.models:
		m["alive"] = false
	_check("a WIPED bodyguard's stale flag does not shock its surviving leader (OC1)",
		int(mm.get_level_of_control(terrain_obj, units_h)[1]) == 1)

	# ── I) 10e marker path ─────────────────────────────────────────────
	print("\n-- I) 10e: the marker path sums per model too --")
	GameConstants.edition = 10
	var units_i = {
		"P1_BOYZ": _unit("P1_BOYZ", 1, 2, _row(520, 400, 10, 20.0)),   # all within ~100px of (620,400)
		"P2_ELITE": _unit("P2_ELITE", 2, 3, _row(610, 430, 2)),
	}
	var loc_i = mm.get_level_of_control(terrain_obj, units_i)
	_check("10e: 20 vs 6", int(loc_i[1]) == 20 and int(loc_i[2]) == 6, str(loc_i))
	_check("10e: P1 controls", mm._check_objective_control(terrain_obj, units_i) == 1)
	GameConstants.edition = 11
	_check("edition back to 11", GameConstants.edition == 11)

	# ── J) 14.03 secured objective ─────────────────────────────────────
	print("\n-- J) secured objective: per-model tie holds, phase-end lead breaks --")
	tm.terrain_features = []
	var sec_obj = {"id": "OBJ_S", "position": Vector2(1500, 1500)}
	if not gs.state.has("board"):
		gs.state["board"] = {}
	gs.state["board"]["objectives"] = [sec_obj]
	gs.state["units"] = {
		"P1_DREAD": _unit("P1_DREAD", 1, 3, [Vector2(1500, 1460)]),
		"P2_SQUAD": _unit("P2_SQUAD", 2, 1, _row(1460, 1540, 3, 30.0)),
	}
	mm.objective_control_state = {"OBJ_S": 0}
	mm.objective_contested_state = {}
	mm._sticky_objectives = {}
	mm.secure_objective("OBJ_S", 1)
	mm.check_all_objectives(true)
	_check("3 vs 3 (1 x OC3 vs 3 x OC1) tie: the secured player keeps it",
		mm.objective_control_state.get("OBJ_S", 0) == 1 and mm.is_objective_secured("OBJ_S").secured,
		str(mm.objective_control_state))
	gs.state["units"]["P2_SQUAD"]["models"].append(_models("p2_extra", [Vector2(1550, 1540)])[0])
	mm.check_all_objectives(false)
	_check("mid-phase 4 vs 3 lead does not break the lock (14.03: end of a phase)",
		mm.is_objective_secured("OBJ_S").secured)
	mm.check_all_objectives(true)
	_check("phase-end 4 vs 3 per-model lead breaks it (per-unit gave 1 < 3)",
		mm.objective_control_state.get("OBJ_S", 0) == 2 and not mm.is_objective_secured("OBJ_S").secured,
		str(mm.objective_control_state))

	# ── K) CasualtyPreference parity ───────────────────────────────────
	print("\n-- K) CasualtyPreference protects the model whose OC removal flips control --")
	tm.terrain_features = []
	var cp_obj = {"id": "OBJ_C", "position": Vector2(700, 426)}
	# 6-model clump (every base within 2" of every other: coherency never
	# binds); columns x=800/852 are in range of the marker, x=904 is not.
	var hold = _unit("P2_HOLD", 2, 1, [Vector2(800, 400), Vector2(800, 452),
		Vector2(852, 400), Vector2(852, 452), Vector2(904, 400), Vector2(904, 452)])
	hold.meta["model_profiles"] = {
		"heavy": {"label": "Heavy", "stats_override": {"objective_control": 2}},
		"trooper": {"label": "Trooper", "stats_override": {}},
	}
	for i in range(6):
		hold.models[i]["model_type"] = "heavy" if i == 0 else "trooper"
	var foe = _unit("P1_FOE", 1, 3, [Vector2(600, 426)])
	var cp_units = {"P2_HOLD": hold, "P1_FOE": foe}
	var cp_state = {"units": cp_units, "board": {"objectives": [cp_obj]}, "meta": {}, "players": {}}
	var cp_loc = mm.get_level_of_control(cp_obj, cp_units)
	_check("P2 holds 5 (heavy OC2 + 3 troopers) vs P1 3", int(cp_loc[2]) == 5 and int(cp_loc[1]) == 3, str(cp_loc))
	_check("MissionManager: P2 controls", mm._check_objective_control(cp_obj, cp_units) == 2)
	hold.models[0]["alive"] = false
	_check("removing the heavy (OC2) flips it: 3 vs 3, uncontrolled", mm._check_objective_control(cp_obj, cp_units) == 0)
	hold.models[0]["alive"] = true
	hold.models[1]["alive"] = false
	_check("removing one trooper does not: 4 vs 3, still P2", mm._check_objective_control(cp_obj, cp_units) == 2)
	hold.models[1]["alive"] = true
	var keep = CasualtyPreference._objective_keep(hold, [0, 1, 2, 3, 4, 5], cp_state, 2)
	_check("the heavy is AT STAKE", float(keep.get(0, 0.0)) == CasualtyPreference.KEEP_OBJECTIVE_AT_STAKE, str(keep))
	_check("in-range troopers get presence only",
		float(keep.get(1, 0.0)) == CasualtyPreference.KEEP_OBJECTIVE_PRESENCE
		and float(keep.get(3, 0.0)) == CasualtyPreference.KEEP_OBJECTIVE_PRESENCE, str(keep))
	_check("out-of-range models get no objective bonus", not keep.has(4) and not keep.has(5), str(keep))
	var order = CasualtyPreference.compute_preferred_targets(hold, cp_state, {"defender_player": 2})
	_check("the heavy is the computer's LAST casualty pick (it stands nearest the enemy)",
		order.size() == 6 and int(order[5]) == 0, str(order))
	_check("the out-of-range models die first", order.slice(0, 2).has(4) and order.slice(0, 2).has(5), str(order))

	tm.terrain_features = prev_terrain
	gs.state = prev_state
	mm.objective_control_state = prev_ctrl
	mm.objective_contested_state = prev_contested
	mm._sticky_objectives = prev_sticky
	GameConstants.edition = prev_edition
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

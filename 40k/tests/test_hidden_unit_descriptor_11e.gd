extends SceneTree

# 01.02.07 DESCRIBING UNITS (official rules commentary): "For such descriptors
# to apply to a unit, that unit must have at least one model in that unit that
# meets that descriptor ... Example: A hidden unit would be a unit that has a
# model in it that is hidden."
#
# Regression: the codex "hidden unit" helpers (OrkAbilities11e.unit_is_hidden,
# SMDetachmentsA.unit_is_hidden, SMCodexACombat.unit_is_hidden) required EVERY
# alive model to be hidden, so Nowhere to Hide ("attacks that target a hidden
# unit"), Venator Omni-auspex ("attacks that target a hidden unit"), Vanguard
# Ambushers ("if a friendly Phobos unit is hidden") and STRIKE FROM THE SHADOWS
# ("a friendly hidden Phobos unit") were refused for a unit only partly in
# terrain. Only Kunnin' Infiltrator ("if EACH model in this unit is hidden")
# needs every model — OrkAbilities11e.every_model_hidden.
#
# Real fixture: tests/saves/sm11e_m2a_marines_active (P1 Space Marines, P2 Orks).
#
# Usage: godot --headless --path . -s tests/test_hidden_unit_descriptor_11e.gd

const FIXTURE := "sm11e_m2a_marines_active"
const PX := 40.0
const LT_PHOBOS := "U_LIEUTENANT_IN_PHOBOS_ARMOUR_A"
const INFIL := "U_INFILTRATOR_SQUAD_A"
const GRETS := "U_GRETCHIN_C"

var passed := 0
var failed := 0
var GS = null
var PM = null
var RE = null
var TM = null
var D = null
var OA = null
var CA = null

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

func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)

func _xs(uid: String) -> Array:
	var xs: Array = []
	for m in GS.state.units[uid].models:
		if m.get("alive", true) and m.get("position", null) != null:
			xs.append(float(m.position.x))
	xs.sort()
	return xs

## Terrain of `cat` covering the models of `uid` left of its median x (part of
## the unit), or all of them.
func _cover(uid: String, cat: String, partly: bool) -> void:
	var xs := _xs(uid)
	var right: float = 60.0 * PX
	if partly:
		right = (float(xs[int(xs.size() / 2) - 1]) + float(xs[int(xs.size() / 2)])) / 2.0 - 30.0
	TM.terrain_features = [{"id": "desc_%s" % cat, "type": "ruins", "category": cat, "height_category": "tall",
		"polygon": PackedVector2Array([Vector2(0, 0), Vector2(right, 0), Vector2(right, 60.0 * PX), Vector2(0, 60.0 * PX)])}]

func _hidden_count(uid: String) -> Array:
	var u: Dictionary = GS.state.units[uid]
	var n := 0
	var tot := 0
	for m in u.models:
		if m.get("alive", true) and m.get("position", null) != null:
			tot += 1
			if TM.is_model_hidden(m, u):
				n += 1
	return [n, tot]

func _src_names(m: Dictionary) -> Array:
	return m.get("sources", []).map(func(s): return str(s.get("name", "")))

func _set_dets(dets: Array) -> void:
	GS.state.factions["1"]["detachments"] = dets.duplicate()
	GS.state.factions["1"]["detachment"] = str(dets[0])

func _run() -> void:
	print("\n=== test_hidden_unit_descriptor_11e ===")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	TM = root.get_node("TerrainManager")
	D = load("res://scripts/codex/space_marines/SMDetachmentsA.gd")
	OA = load("res://scripts/codex/orks/OrkAbilities11e.gd")
	CA = load("res://scripts/codex/space_marines/SMCodexACombat.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	var prev_terrain = TM.terrain_features.duplicate(true)
	if not _stage_fixture():
		_check("fixture loaded", false)
		return
	await create_timer(0.2).timeout
	GameConstants.edition = 11
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2
	GS.state.meta["phase"] = 8
	_set_dets(["Phobos Shadow Force", "Phobos Shock Force"])
	for uid in [GRETS, INFIL, LT_PHOBOS]:
		GS.state.units[uid]["flags"] = {}

	for cat in ["light", "dense"]:
		print("\n-- %s terrain over PART of the unit --" % cat)
		_cover(GRETS, cat, true)
		var hc := _hidden_count(GRETS)
		_check("setup: some but not all Gretchin hidden (%d/%d)" % [hc[0], hc[1]], hc[0] > 0 and hc[0] < hc[1])
		_check("OrkAbilities11e.unit_is_hidden: a hidden unit (Nowhere to Hide)", OA.unit_is_hidden(GRETS))
		_check("SMDetachmentsA.unit_is_hidden: a hidden unit (Venator / Auspex)", D.unit_is_hidden(GS.state.units[GRETS]))
		_check("SMCodexACombat.unit_is_hidden: a hidden unit (STRIKE FROM THE SHADOWS)", CA.unit_is_hidden(GRETS))
		_check("Kunnin' Infiltrator needs EACH model: every_model_hidden is false", not OA.every_model_hidden(GRETS))
		var vm: Dictionary = RE.ork11e_ab_mods(GS.state.units[LT_PHOBOS], GS.state.units[GRETS], {"name": "test"}, false, GS.state)
		_check("Venator Omni-auspex re-rolls wound rolls of 1 vs the partly hidden unit",
			str(vm.get("wound_reroll", "")) == "ones" and "Venator Omni-auspex" in _src_names(vm), str(vm))
		_cover(GRETS, cat, false)
		_check("whole unit covered: every_model_hidden is true", OA.every_model_hidden(GRETS))

	print("\n-- Vanguard Ambushers / STRIKE FROM THE SHADOWS: a partly hidden PHOBOS unit --")
	_cover(INFIL, "dense", true)
	var ic := _hidden_count(INFIL)
	_check("setup: some but not all Infiltrators hidden (%d/%d)" % [ic[0], ic[1]], ic[0] > 0 and ic[0] < ic[1])
	_check("STRIKE FROM THE SHADOWS: a friendly hidden Phobos unit", CA.unit_is_hidden(INFIL))
	D.on_movement_phase_end(1)
	_check("Vanguard Ambushers: the partly hidden Infiltrators are marked at the end of the Movement phase",
		str(GS.state.units[INFIL].get("flags", {}).get(D.F_AMBUSH, "")) == D.turn_stamp(), str(GS.state.units[INFIL].get("flags", {})))
	TM.terrain_features = []
	_check("out of terrain: not a hidden unit", not CA.unit_is_hidden(INFIL) and not D.unit_is_hidden(GS.state.units[INFIL]))

	print("\n-- the shot record covers an attached leader (19.01) --")
	var cam = root.get_node("CharacterAttachmentManager")
	var lt: Dictionary = GS.state.units[LT_PHOBOS]
	var infil_m: Dictionary = GS.state.units[INFIL].models[0]
	for m in lt.models:
		m["position"] = {"x": float(infil_m.position.x) + 40.0, "y": float(infil_m.position.y)}
	cam.attach_character(LT_PHOBOS, INFIL)
	_cover(INFIL, "dense", false)
	_check("setup: leader attached and both components in the ruin are hidden",
		str(GS.state.units[LT_PHOBOS].get("attached_to", "")) == INFIL and TM.is_model_hidden(lt.models[0], lt) and _hidden_count(INFIL)[0] > 0)
	var phase = load("res://phases/ShootingPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = GS.create_snapshot()
	var stamp: Array = phase._hidden_shot_stamp(INFIL)
	root.remove_child(phase)
	phase.free()
	PM.apply_state_changes(stamp)
	_check("after the Attached unit shoots, the leader carries the stamp too", GS.state.units[LT_PHOBOS].get("flags", {}).has("last_shot_idx"),
		str(GS.state.units[LT_PHOBOS].get("flags", {})))
	_check("... so it is not a hidden unit (no component has a hidden model)", not D.unit_is_hidden(GS.state.units[INFIL]) and not CA.unit_is_hidden(INFIL))
	TM.terrain_features = prev_terrain

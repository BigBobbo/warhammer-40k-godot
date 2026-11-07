extends SceneTree

# 13.09: "While a model is hidden, it can only be visible to ENEMY models that
# are within its detection range." A friendly observer is not limited by it.
#
# Regression: RulesEngine.unit_sight_line (and _check_target_visibility) applied
# the hidden detection-range gate whoever owned the observer, so rules needing a
# "visible friendly unit" could refuse one — reproduced on the real offer path:
# Guilliman's Author of the Codex (12") did not offer his own Eliminator Squad
# at 10.5" while it stood hidden in a light area with Chameleoline Cloaks (-3")
# and Gone to Ground (-3", a small dense pillar) giving it a 9" detection range.
#
#   A. unit_sight_line / _has_los_to_target_unit: friendly vs enemy observer
#   B. Author of the Codex (SMAbilitiesA.window_offers) — the probe's layout
#
# Usage: godot --headless --path . -s tests/test_hidden_friendly_observer_11e.gd

const FIXTURE := "cus11e_c5_active"
const SM_ARMY := "sm11e_codex_test"
const ORK_ARMY := "ork11e_codex_test"
const P_CMD := 6
const P_MOV := 7

var passed := 0
var failed := 0
var GS = null
var SM = null
var RE = null
var SMA = null
var UAM = null
var TM = null
var MS = null
var _sm_army: Dictionary = {}
var _ork_army: Dictionary = {}

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _initialize() -> void:
	await create_timer(0.3).timeout
	_run()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

func _model(id: String, x: float, y: float) -> Dictionary:
	return {"id": id, "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}, "wounds": 1, "current_wounds": 1}

func _section_sight_line() -> void:
	print("\n-- A. unit_sight_line: the hidden gate applies to ENEMY observers only --")
	TM.terrain_features = [{"id": "light_area", "type": "barricade", "polygon": _rect(1200, 1000, 200, 200), "height_category": "low"}]
	var units := {
		"U_TGT": {"id": "U_TGT", "owner": 1, "status": 2, "flags": {}, "meta": {"name": "Target", "keywords": ["INFANTRY"], "stats": {}},
			"models": [_model("t0", 1200, 1000)]},
		"U_FRIEND": {"id": "U_FRIEND", "owner": 1, "status": 2, "flags": {}, "meta": {"name": "Friend", "keywords": ["INFANTRY"], "stats": {}},
			"models": [_model("f0", 1200 - 17 * 40, 1000)]},
		"U_ENEMY": {"id": "U_ENEMY", "owner": 2, "status": 2, "flags": {}, "meta": {"name": "Enemy", "keywords": ["INFANTRY"], "stats": {}},
			"models": [_model("e0", 1200 - 17 * 40, 1040)]},
	}
	var board := {"units": units, "terrain_features": TM.terrain_features, "meta": GS.state["meta"].duplicate(true)}
	RE.clear_los_memo()
	_check("setup: the target model is hidden (light area) and ~16\" away", TM.is_model_hidden(units.U_TGT.models[0], units.U_TGT)
		and MS.px_to_inches(MS.model_to_model_distance_px(units.U_FRIEND.models[0], units.U_TGT.models[0])) > 15.0)
	_check("a FRIENDLY observer sees it (13.09 limits enemy models only)", RE.unit_sight_line("U_FRIEND", "U_TGT", board, false).has_los)
	_check("_has_los_to_target_unit agrees for the friendly observer", RE._has_los_to_target_unit("U_FRIEND", "U_TGT", board))
	_check("an ENEMY observer at the same range does not", not RE.unit_sight_line("U_ENEMY", "U_TGT", board, false).has_los)

func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)

func _reset_unit(u: Dictionary) -> void:
	u["flags"] = {}
	u["status"] = 0
	u.erase("attached_to")
	u.erase("embarked_in")
	u["attachment_data"] = {"attached_characters": []}
	if u.has("transport_data"):
		u.transport_data["embarked_units"] = []
	for m in u.get("models", []):
		m["alive"] = true
		m["position"] = null
		m["current_wounds"] = int(m.get("wounds", 1))

func _fresh() -> void:
	_stage_fixture()
	GameConstants.edition = 11
	GS.state.units = {}
	for pair in [[_sm_army, 1], [_ork_army, 2]]:
		var army: Dictionary = pair[0]
		for k in army.get("units", {}):
			var u: Dictionary = army.units[k].duplicate(true)
			u["id"] = k
			u["owner"] = int(pair[1])
			_reset_unit(u)
			GS.state.units[k] = u
	GS.state.factions["1"] = _sm_army.get("faction", {}).duplicate(true)
	GS.state.factions["2"] = _ork_army.get("faction", {}).duplicate(true)
	SM.load_faction_stratagems_for_player(1)
	SM.load_faction_stratagems_for_player(2)
	GS.state.meta["phase"] = P_CMD
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2
	for p in ["1", "2"]:
		GS.state.players[p]["cp"] = 6
		GS.state.players[p].erase(SMA.ARMY_STATE)
	SM._usage_history = {"1": [], "2": []}
	UAM.reset_for_new_game()
	SMA.offers_suppressed = false
	SMA.reset_machine_spirit()
	TM.terrain_features = []

func _set_pos(uid: String, positions: Array) -> void:
	var u: Dictionary = GS.state.units[uid]
	u["status"] = 2
	var ms: Array = u.get("models", [])
	for i in range(ms.size()):
		ms[i]["position"] = {"x": positions[i].x, "y": positions[i].y}

func _aotc_options() -> Array:
	var c := {"phase": "movement", "window_id": "phase_start"}
	for o in SMA.window_offers(1, "phase_start", c):
		if str(o.get("stratagem_id", "")) == SMA.sid_of("author_of_the_codex"):
			for t in o.get("targets", []):
				if str(t.get("unit_id", "")) == "U_ROBOUTE_GUILLIMAN_A":
					return t.get("secondary", {}).get("options", []).map(func(x): return str(x.get("id", "")))
	return []

func _section_author_of_the_codex() -> void:
	print("\n-- B. Author of the Codex offers Guilliman's own hidden Eliminators --")
	var alm = root.get_node("ArmyListManager")
	_sm_army = alm.load_army_list(SM_ARMY, 1)
	_ork_army = alm.load_army_list(ORK_ARMY, 2)
	if _sm_army.is_empty() or _ork_army.is_empty():
		_check("armies loaded", false)
		return
	_fresh()
	if not GS.state.units.has("U_ROBOUTE_GUILLIMAN_A") or not GS.state.units.has("U_ELIMINATOR_SQUAD_A"):
		_check("Guilliman and an Eliminator Squad in the test army", false, str(GS.state.units.keys()))
		return
	_set_pos("U_ROBOUTE_GUILLIMAN_A", [Vector2(800, 1600)])
	_set_pos("U_ELIMINATOR_SQUAD_A", [Vector2(800, 2099), Vector2(800, 2169), Vector2(800, 2239)])
	TM.terrain_features = [
		{"id": "light_area", "type": "ruins", "piece_class": "area", "category": "light",
			"height_category": "low", "polygon": _rect(800, 2169, 240, 320)},
		{"id": "pillar", "type": "ruins", "height_category": "tall", "polygon": _rect(816, 1850, 16, 16)},
	]
	RE.clear_los_memo()
	SMA.on_phase_transition(P_CMD, P_MOV)
	GS.state.meta["phase"] = P_MOV
	var g: Dictionary = GS.state.units["U_ROBOUTE_GUILLIMAN_A"]
	var e: Dictionary = GS.state.units["U_ELIMINATOR_SQUAD_A"]
	var m1: Dictionary = e.models[0]
	var d_in: float = MS.px_to_inches(MS.model_to_model_distance_px(g.models[0], m1))
	var det: float = TM.detection_range_inches_for(m1, e, g.models[0])
	_check("setup: Eliminators hidden, nearest %.1f\" away, 9\" detection vs Guilliman (Chameleoline + Gone to Ground)" % d_in,
		TM.is_model_hidden(m1, e) and det == 9.0 and d_in > 9.0 and d_in < 12.0, "det=%.1f" % det)
	_check("they are visible to Guilliman (same army)", RE._has_los_to_target_unit("U_ROBOUTE_GUILLIMAN_A", "U_ELIMINATOR_SQUAD_A", GS.state))
	var opts := _aotc_options()
	_check("Author of the Codex offers the Eliminator Squad", "U_ELIMINATOR_SQUAD_A" in opts, str(opts))

func _run() -> void:
	print("\n=== test_hidden_friendly_observer_11e ===")
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	RE = root.get_node("RulesEngine")
	UAM = root.get_node("UnitAbilityManager")
	TM = root.get_node("TerrainManager")
	MS = root.get_node("Measurement")
	SMA = load("res://scripts/codex/space_marines/SMAbilitiesA.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	var prev_terrain = TM.terrain_features.duplicate(true)
	GameConstants.edition = 11
	GS.state["meta"]["battle_round"] = 2
	GS.state["meta"]["active_player"] = 1
	_section_sight_line()
	_section_author_of_the_codex()
	TM.terrain_features = prev_terrain
	GameConstants.edition = 10

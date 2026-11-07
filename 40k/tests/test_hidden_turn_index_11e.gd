extends SceneTree

# 13.09 HIDDEN — "That model's unit did not make one or more ranged attacks
# during this turn or during the previous turn" — measured on the PLAY-ORDER
# turn counter (07.02: one turn per player per battle round; the first-turn
# player from the roll-off takes the first turn of every round).
#
# Regression: the stamp (ShootingPhase._hidden_shot_stamp), the check
# (TerrainManager.is_model_hidden) and the Shadow Masters waiver
# (SMDetachmentsA) all used battle_round*2 + (Player 1 ? 0 : 1). When Player 2
# took the first turn, play order P2R1, P1R1, P2R2, P1R2 indexed 3, 2, 5, 4 —
# a Player 1 unit that shot was hidden again in the very next turn, a Player 2
# unit that shot was not hidden two turns later, and a Player 2 Shadow Masters
# unit lost Hidden in the turn after the waiver. They now share
# GameState.get_player_turn_index() (OrkArmyRules11e.turn_index() = it - 2).
#
#   A. the shared index: values + monotonic over REAL END_TURN transitions,
#      for first_turn_player = 1 and 2; Ork turn_index parity
#   B. REAL ShootingPhase stamp + REAL ScoringPhase END_TURN + REAL
#      is_model_hidden, turn by turn in play order, against 13.09
#   C. Shadow Masters (Phobos Shadow Force) used by a Player 2 unit with
#      Player 2 going first, through StratagemManager.use_stratagem on the
#      real SM fixture
#
# Usage: godot --headless --path . -s tests/test_hidden_turn_index_11e.gd

const SM_FIXTURE := "sm11e_m2a_marines_active"
const INFIL := "U_INFILTRATOR_SQUAD_A"
const PHASE_SHOOTING := 8
const PHASE_SCORING := 11

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure
var GS = null
var TM = null
var PM = null

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
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

# --- real phase helpers -------------------------------------------------------

func _end_turn(player: int) -> Dictionary:
	GS.state["meta"]["phase"] = PHASE_SCORING
	var phase = load("res://phases/ScoringPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = GS.create_snapshot()
	var result = phase.execute_action({"type": "END_TURN", "player": player})
	root.remove_child(phase)
	phase.free()
	return result

## The diffs a real Shooting-phase completion writes for `unit_id`
## (ShootingPhase._hidden_shot_stamp), applied to the live state.
func _shoot_stamp(unit_id: String) -> Array:
	GS.state["meta"]["phase"] = PHASE_SHOOTING
	var phase = load("res://phases/ShootingPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = GS.create_snapshot()
	var stamp = phase._hidden_shot_stamp(unit_id)
	root.remove_child(phase)
	phase.free()
	var diffs: Array = stamp if stamp is Array else [stamp]
	PM.apply_state_changes(diffs)
	return diffs

func _units() -> Dictionary:
	var out := {}
	for p in [1, 2]:
		out["U_P%d" % p] = {"id": "U_P%d" % p, "owner": p, "status": 2,
			"meta": {"name": "P%d Infantry" % p, "keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "m1", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 400, "y": 400}, "wounds": 1, "current_wounds": 1}],
			"flags": {}}
	return out

func _hidden(uid: String) -> bool:
	var u: Dictionary = GS.state["units"][uid]
	return TM.is_model_hidden(u["models"][0], u)

func _label() -> String:
	return "P%dR%d" % [int(GS.get_active_player()), int(GS.get_battle_round())]

func _fresh(first: int) -> void:
	GS.initialize_default_state()
	GameConstants.edition = 11
	GS.state["meta"]["first_turn_player"] = first
	GS.state["meta"]["active_player"] = first
	GS.state["meta"]["battle_round"] = 1
	GS.state["units"] = _units()

# --- A ------------------------------------------------------------------------

func _section_index() -> void:
	print("\n-- A. the shared play-order turn index --")
	var cases := [
		[1, 1, 1, 2], [1, 1, 2, 3], [1, 2, 1, 4], [1, 2, 2, 5],
		[2, 1, 2, 2], [2, 1, 1, 3], [2, 2, 2, 4], [2, 2, 1, 5]]
	for c in cases:
		var meta := {"first_turn_player": c[0], "battle_round": c[1], "active_player": c[2]}
		_check("first=P%d, round %d, P%d active -> index %d" % [c[0], c[1], c[2], c[3]],
			GS.player_turn_index_from_meta(meta) == int(c[3]),
			"got %d" % GS.player_turn_index_from_meta(meta))
	_check("unset / invalid first_turn_player falls back to Player 1 first",
		GS.player_turn_index_from_meta({"battle_round": 3, "active_player": 2}) == 7
		and GS.player_turn_index_from_meta({"first_turn_player": 0, "battle_round": 3, "active_player": 1}) == 6)
	var ork = load("res://scripts/codex/orks/OrkArmyRules11e.gd")
	for first in [1, 2]:
		_fresh(first)
		var seq: Array = []
		var labels: Array = []
		var ork_ok := true
		for _t in range(6):
			seq.append(int(GS.get_player_turn_index()))
			labels.append(_label())
			if int(ork.turn_index()) != int(GS.get_player_turn_index()) - 2:
				ork_ok = false
			var r := _end_turn(int(GS.get_active_player()))
			if not r.get("success", false):
				_check("END_TURN succeeded (%s)" % _label(), false, str(r))
				return
		var mono := true
		for i in range(1, seq.size()):
			if seq[i] != seq[i - 1] + 1:
				mono = false
		_check("first=P%d: index rises by exactly 1 per REAL player turn %s -> %s" % [first, str(labels), str(seq)],
			mono and int(seq[0]) == 2, str(seq))
		_check("first=P%d: OrkArmyRules11e.turn_index() == shared index - 2 every turn" % first, ork_ok)

# --- B ------------------------------------------------------------------------

## Plays `n` real turns from the start of the battle; `shooter` makes ranged
## attacks (real stamp applied) in the turn labelled `shoot_turn`. Every turn
## is checked against 13.09: not hidden iff it shot this turn or the previous.
func _scenario(first: int, shooter: String, shoot_turn: String, n: int) -> void:
	_fresh(first)
	var prev_label := "(none)"
	var shot_in := ""
	var all_ok := true
	var trace: Array = []
	for _t in range(n):
		var lbl := _label()
		if lbl == shoot_turn:
			_shoot_stamp(shooter)
			shot_in = lbl
		var expect_hidden := not (shot_in == lbl or shot_in == prev_label)
		var got := _hidden(shooter)
		trace.append("%s:%s%s" % [lbl, "H" if got else "-", "" if got == expect_hidden else "(want %s)" % ("H" if expect_hidden else "-")])
		if got != expect_hidden:
			all_ok = false
		prev_label = lbl
		var r := _end_turn(int(GS.get_active_player()))
		if not r.get("success", false):
			_check("END_TURN succeeded", false, str(r))
			return
	_check("first=P%d, %s shoots in %s: hidden matches 13.09 every turn  %s" % [first, shooter, shoot_turn, str(trace)], all_ok)

func _section_play_order() -> void:
	print("\n-- B. real stamp + real END_TURN + real is_model_hidden (13.09 bullet 2) --")
	TM.terrain_features = [
		{"id": "ruin", "type": "ruins", "polygon": _rect(400, 400, 200, 200), "height_category": "tall"},
	]
	# Player 2 goes first — the broken cases.
	_scenario(2, "U_P1", "P1R1", 5)
	_scenario(2, "U_P1", "P1R2", 6)
	_scenario(2, "U_P2", "P2R1", 4)
	_scenario(2, "U_P2", "P2R2", 6)
	# Player 1 goes first — unchanged (the stamp values are the same as before).
	_scenario(1, "U_P1", "P1R1", 4)
	_scenario(1, "U_P2", "P2R1", 4)
	_scenario(1, "U_P1", "P1R2", 6)
	_fresh(2)
	GS.state["meta"]["battle_round"] = 2
	GS.state["meta"]["active_player"] = 1
	var d: Array = _shoot_stamp("U_P1")
	var stamp_val := -1
	for x in d:
		if str(x.get("path", "")) == "units.U_P1.flags.last_shot_idx":
			stamp_val = int(x.get("value", -1))
	_check("first=P2: the stamp in P1R2 (the round's SECOND turn) is 2*2+1 = 5", stamp_val == 5, str(d))

# --- C ------------------------------------------------------------------------

func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + SM_FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + SM_FIXTURE + ext))
	return slm.load_game(SM_FIXTURE)

func _section_shadow_masters() -> void:
	print("\n-- C. Shadow Masters, Player 2 going first (real SM fixture) --")
	if not _stage_fixture():
		_check("SM fixture loaded", false)
		return
	await create_timer(0.2).timeout
	GameConstants.edition = 11
	var D = load("res://scripts/codex/space_marines/SMDetachmentsA.gd")
	# Make Player 2 the Space Marine (Phobos Shadow Force) player and hand it the
	# Infiltrators, then let Player 2 take the first turn.
	GS.state["factions"]["2"] = GS.state["factions"]["1"].duplicate(true)
	GS.state["factions"]["2"]["detachments"] = ["Phobos Shadow Force"]
	GS.state["factions"]["2"]["detachment"] = "Phobos Shadow Force"
	var infil: Dictionary = GS.state["units"][INFIL]
	infil["owner"] = 2
	infil["flags"] = {}
	GS.state["meta"]["first_turn_player"] = 2
	GS.state["meta"]["battle_round"] = 1
	GS.state["meta"]["active_player"] = 2
	GS.state["meta"]["phase"] = PHASE_SHOOTING
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for m in infil["models"]:
		var p := Vector2(float(m.position.x), float(m.position.y))
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var c := (lo + hi) / 2.0
	TM.terrain_features = [{"id": "sm_ruin", "type": "ruins", "polygon": _rect(c.x, c.y, hi.x - lo.x + 200.0, hi.y - lo.y + 200.0), "height_category": "tall"}]
	_check("fixture: Player 2 has Phobos Shadow Force", D.has_det(2, D.SHADOW))
	_check("before shooting: the Infiltrators in the ruin are hidden", D.unit_is_hidden(GS.state["units"][INFIL]))
	_shoot_stamp(INFIL)
	_check("P2R1 (first turn): after shooting they are NOT hidden", not D.unit_is_hidden(GS.state["units"][INFIL]))
	var r: Dictionary = root.get_node("StratagemManager").use_stratagem(2, D.RULE_SHADOW, INFIL, {"variant_id": "hidden"})
	_check("SHADOW MASTERS 'stay hidden' used by Player 2", r.get("success", false), str(r))
	_check("P2R1: hidden again (those attacks do not prevent it)", D.unit_is_hidden(GS.state["units"][INFIL]))
	GS.state["meta"]["active_player"] = 1  # P1R1 — the very next turn
	_check("P1R1 (the very next turn): still hidden — those attacks do not count", D.unit_is_hidden(GS.state["units"][INFIL]),
		"last_shot_idx=%s index=%d" % [str(GS.state["units"][INFIL]["flags"].get("last_shot_idx", "-")), int(GS.get_player_turn_index())])
	GS.state["meta"]["battle_round"] = 2
	GS.state["meta"]["active_player"] = 2  # P2R2
	_check("P2R2: still hidden", D.unit_is_hidden(GS.state["units"][INFIL]))

func _run() -> void:
	print("\n=== test_hidden_turn_index_11e ===")
	GS = root.get_node("GameState")
	TM = root.get_node("TerrainManager")
	PM = root.get_node("PhaseManager")
	var prev_terrain = TM.terrain_features.duplicate(true)
	var prev_edition = GameConstants.edition
	_section_index()
	_section_play_order()
	await _section_shadow_masters()
	TM.terrain_features = prev_terrain
	GameConstants.edition = prev_edition
	_completed = true

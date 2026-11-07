extends SceneTree

# 13.09 HIDDEN — saves written before the shot record was reworked load with
# the right answers (StateSerializer 1.3.0 -> 1.4.0,
# scripts/rules/HiddenShotRecord.gd).
#
#   A. Attached units (19.01): the old build stamped flags.last_shot_idx on the
#      active shooter only — the bodyguard dict — so an attached CHARACTER had
#      no record. With the 01.02.07 any-model "hidden unit" helpers that leader
#      read as hidden in terrain and the whole unit as a hidden unit for up to
#      two turns after loading, although it had just shot (Nowhere to Hide,
#      Venator Omni-auspex, STRIKE FROM THE SHADOWS).
#   B. Player 2 first: the old turn index was battle_round*2 + (P1 ? 0 : 1),
#      the record is now in play order (GameState.get_player_turn_index), so
#      every saved stamp had the wrong parity — for one turn after loading a
#      Player 2 unit stayed un-hidden too long and a Player 1 unit hid a turn
#      early. The old stamps are converted (idx ^ 1).
#
# Every save goes through the REAL StateSerializer serialize/deserialize (the
# version stamped back to 1.3.0, as the old build wrote it) and
# GameState.load_from_snapshot.
#
# Usage: godot --headless --path . -s tests/test_hidden_save_compat_11e.gd

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure
var GS = null
var TM = null
var SS = null
var ORK = null
var SMD = null
var SMC = null
var HSR = null

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
	if not _completed:
		failed += 1
		print("  FAIL: the run aborted before its last check (see the SCRIPT ERROR above)")
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

func _m(id: String, x: float, y: float) -> Dictionary:
	return {"id": id, "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}, "wounds": 1, "current_wounds": 1}

func _ruin() -> Array:
	return [{"id": "ruin", "type": "ruins", "polygon": _rect(420, 420, 300, 300), "height_category": "tall"}]

## Serialize the live state and stamp the save as `version` (the old build
## wrote 1.3.0).
func _save_json(version: String) -> String:
	var txt: String = SS.serialize_game_state(GS.create_snapshot())
	var data = JSON.parse_string(txt)
	data["_serialization"]["version"] = version
	return JSON.stringify(data)

func _load(json: String) -> void:
	GS.initialize_default_state()  # wipe the live state first
	var loaded: Dictionary = SS.deserialize_game_state(json)
	GS.load_from_snapshot(loaded)
	GameConstants.edition = 11
	TM.terrain_features = _ruin()  # the layout reload replaces terrain; put the ruin back

## Old-build mid-game state: Player 2's turn of round 2 (P1 went first); the
## Boyz and their attached Warboss (both INFANTRY, in a ruin) just shot — the
## old stamp sits on the Boyz only. Main's formula (battle_round*2 + (P1 ? 0 : 1))
## and the play-order index agree here: 5.
func _old_attached_state() -> void:
	GS.initialize_default_state()
	GameConstants.edition = 11
	GS.state["meta"]["first_turn_player"] = 1
	GS.state["meta"]["battle_round"] = 2
	GS.state["meta"]["active_player"] = 2
	GS.state["units"] = {
		"U_BOYZ": {"id": "U_BOYZ", "owner": 2, "status": 2, "flags": {"has_shot": true, "last_shot_idx": 5},
			"attachment_data": {"attached_characters": ["U_BOSS"]},
			"meta": {"name": "Boyz", "keywords": ["INFANTRY", "ORKS"]}, "models": [_m("b1", 400, 400), _m("b2", 430, 400)]},
		"U_BOSS": {"id": "U_BOSS", "owner": 2, "status": 2, "flags": {}, "attached_to": "U_BOYZ",
			"meta": {"name": "Warboss", "keywords": ["INFANTRY", "CHARACTER", "ORKS"]}, "models": [_m("w1", 415, 430)]},
		# Linked ONLY by its own back-pointer (saves like this exist).
		"U_NOB": {"id": "U_NOB", "owner": 2, "status": 2, "flags": {}, "attached_to": "U_BOYZ",
			"meta": {"name": "Nob", "keywords": ["INFANTRY", "CHARACTER", "ORKS"]}, "models": [_m("n1", 445, 430)]},
		# A unit that never shot keeps no record.
		"U_GROTS": {"id": "U_GROTS", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Grots", "keywords": ["INFANTRY", "ORKS"]}, "models": [_m("g1", 460, 400)]},
	}
	TM.terrain_features = _ruin()

func _hidden_answers() -> Dictionary:
	var u: Dictionary = GS.state.units
	return {
		"leader_hidden": TM.is_model_hidden(u.U_BOSS.models[0], u.U_BOSS),
		"nob_hidden": TM.is_model_hidden(u.U_NOB.models[0], u.U_NOB),
		"ork": ORK.unit_is_hidden("U_BOYZ"),
		"smd": SMD.unit_is_hidden(u.U_BOYZ),
		"smc": SMC.unit_is_hidden("U_BOYZ"),
	}

func _section_attached() -> void:
	print("\n-- A. an Attached unit stamped on its bodyguard only (old saves) --")
	_old_attached_state()
	var old_json := _save_json("1.3.0")
	_load(old_json)
	var u: Dictionary = GS.state.units
	_check("the attached Warboss carries the Boyz' record after loading", int(u.U_BOSS.get("flags", {}).get("last_shot_idx", -1)) == 5,
		str(u.U_BOSS.get("flags", {})))
	_check("... and so does the back-pointer-only Nob", int(u.U_NOB.get("flags", {}).get("last_shot_idx", -1)) == 5,
		str(u.U_NOB.get("flags", {})))
	_check("a unit that never shot gets no record", not u.U_GROTS.get("flags", {}).has("last_shot_idx"))
	var a := _hidden_answers()
	_check("the turn it shot (turn 5): no model of the unit is hidden", not a.leader_hidden and not a.nob_hidden, str(a))
	_check("... and it is not a 'hidden unit' (Orks / SM detachments / SM codex helpers)", not a.ork and not a.smd and not a.smc, str(a))
	GS.state["meta"]["battle_round"] = 3
	GS.state["meta"]["active_player"] = 1
	a = _hidden_answers()
	_check("the next turn (turn 6, the previous turn's shots count): still not hidden", not a.ork and not a.smd and not a.smc and not a.leader_hidden, str(a))
	GS.state["meta"]["active_player"] = 2
	a = _hidden_answers()
	_check("two turns on (turn 7): hidden again", a.ork and a.smd and a.smc and a.leader_hidden, str(a))
	# Control: the migration is keyed on the save version — a save written by
	# this build is loaded as it is.
	_old_attached_state()
	_load(_save_json(SS.CURRENT_VERSION))
	_check("control: a %s save is not rewritten (the hand-made leader keeps no record)" % SS.CURRENT_VERSION,
		not GS.state.units.U_BOSS.get("flags", {}).has("last_shot_idx"))
	# Idempotent on a save whose components already agree.
	_old_attached_state()
	for d in HSR.stamp_diffs("U_BOYZ", GS.state):
		var parts: PackedStringArray = str(d.path).split(".")
		GS.state[parts[0]][parts[1]][parts[2]][parts[3]] = d.value
	var before: Dictionary = GS.state.units.duplicate(true)
	_check("idempotent: a fully stamped Attached unit is left unchanged", HSR.unify_attached_records(GS.state.units) == 0
		and str(before) == str(GS.state.units))

func _unit(uid: String, owner: int, stamp: int) -> Dictionary:
	var f := {} if stamp < -1 else {"last_shot_idx": stamp}
	return {"id": uid, "owner": owner, "status": 2, "flags": f,
		"meta": {"name": uid, "keywords": ["INFANTRY"], "stats": {"move": 6}},
		"models": [_m("m1", 420, 420)]}

func _set_turn(rnd: int, active: int) -> void:
	GS.state["meta"]["battle_round"] = rnd
	GS.state["meta"]["active_player"] = active

func _hid(uid: String) -> bool:
	var u: Dictionary = GS.state.units[uid]
	return TM.is_model_hidden(u.models[0], u)

func _section_p2_first() -> void:
	print("\n-- B. Player 2 went first: old-formula stamps converted to play order --")
	# The old build, Player 1's turn of round 2 (Player 2 went first). U_P2 shot
	# in P2's round-2 turn (old 2*2+1 = 5), U_P1 in P1's round-2 turn (old 2*2 = 4),
	# U_NEVER never shot (no stamp).
	GS.initialize_default_state()
	GameConstants.edition = 11
	GS.state["meta"]["first_turn_player"] = 2
	_set_turn(2, 1)
	GS.state["units"] = {"U_P2": _unit("U_P2", 2, 5), "U_P1": _unit("U_P1", 1, 4), "U_NEVER": _unit("U_NEVER", 1, -100)}
	TM.terrain_features = _ruin()
	_load(_save_json("1.3.0"))
	var u: Dictionary = GS.state.units
	# Play order with Player 2 first: P2R2 = 4, P1R2 = 5, P2R3 = 6, P1R3 = 7.
	_check("U_P2's stamp is P2R2 in play order (4)", int(u.U_P2.flags.get("last_shot_idx", -1)) == 4, str(u.U_P2.flags))
	_check("U_P1's stamp is P1R2 in play order (5)", int(u.U_P1.flags.get("last_shot_idx", -1)) == 5, str(u.U_P1.flags))
	_check("a unit that never shot stays unstamped", not u.U_NEVER.flags.has("last_shot_idx"), str(u.U_NEVER.flags))
	_check("P1R2 (the save's own turn, 5): neither is hidden (P2 shot last turn, P1 this turn)", not _hid("U_P2") and not _hid("U_P1"))
	_set_turn(3, 2)
	_check("P2R3 (6): U_P2 hidden again (it shot two turns ago); U_P1 not (it shot last turn)", _hid("U_P2") and not _hid("U_P1"),
		"U_P2=%s U_P1=%s" % [str(_hid("U_P2")), str(_hid("U_P1"))])
	_set_turn(3, 1)
	_check("P1R3 (7): both hidden", _hid("U_P2") and _hid("U_P1"))
	# Control: Player 1 first — the two formulas agree; nothing is converted.
	GS.initialize_default_state()
	GameConstants.edition = 11
	GS.state["meta"]["first_turn_player"] = 1
	_set_turn(2, 2)
	GS.state["units"] = {"U_P2": _unit("U_P2", 2, 5), "U_P1": _unit("U_P1", 1, 4)}
	_load(_save_json("1.3.0"))
	_check("control: Player 1 first — stamps unchanged (5, 4)", int(GS.state.units.U_P2.flags.get("last_shot_idx", -1)) == 5
		and int(GS.state.units.U_P1.flags.get("last_shot_idx", -1)) == 4)
	# Control: a save written by this build (play-order stamps) is not converted.
	GS.initialize_default_state()
	GameConstants.edition = 11
	GS.state["meta"]["first_turn_player"] = 2
	_set_turn(2, 1)
	GS.state["units"] = {"U_P2": _unit("U_P2", 2, 4), "U_P1": _unit("U_P1", 1, 5)}
	_load(_save_json(SS.CURRENT_VERSION))
	_check("control: a %s save keeps its play-order stamps (4, 5)" % SS.CURRENT_VERSION, int(GS.state.units.U_P2.flags.get("last_shot_idx", -1)) == 4
		and int(GS.state.units.U_P1.flags.get("last_shot_idx", -1)) == 5)

func _run() -> void:
	print("\n=== test_hidden_save_compat_11e ===")
	GS = root.get_node("GameState")
	TM = root.get_node("TerrainManager")
	SS = root.get_node("StateSerializer")
	ORK = load("res://scripts/codex/orks/OrkAbilities11e.gd")
	SMD = load("res://scripts/codex/space_marines/SMDetachmentsA.gd")
	SMC = load("res://scripts/codex/space_marines/SMCodexACombat.gd")
	HSR = load("res://scripts/rules/HiddenShotRecord.gd")
	var prev_terrain = TM.terrain_features.duplicate(true)
	_section_attached()
	_section_p2_first()
	TM.terrain_features = prev_terrain
	GameConstants.edition = 10
	_completed = true

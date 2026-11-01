extends SceneTree

# T09 — exhaustion shading for units that have acted this phase (design doc §8).
#
# Covers what does not need a window:
#   Engine — BasePhase.has_unit_acted_this_phase / unit_acted_in_phase, driven
#   through the real PhaseManager + execute_action:
#     - Movement: a unit in the middle of its move has not acted; End This
#       Unit's Move (CONFIRM_UNIT_MOVE) flips it and emits unit_acted_in_phase
#       exactly once; REMAIN_STATIONARY flips the unit and its attached
#       character; the opponent's left-over flags.moved never counts; a refused
#       action and an action that changes nothing emit nothing
#     - Shooting: SKIP_UNIT flips the unit; the opponent's Fire Overwatch
#       has_shot does not count
#     - Charge: SKIP_CHARGE flips the unit; flags.charged_this_turn (what a
#       network client sees) counts
#     - Fight: units_that_fought / flags.has_fought count, for either player
#     - Command: no unit has acted, whatever its flags
#   UI — TokenVisual, LeftRosterStrip and UnitExhaustionTracker under a
#   stand-in Main (BoardRoot/TokenLayer + LeftRoster):
#     - the acted unit's token modulates to (0.6, 0.6, 0.6, 1) with
#       is_exhausted_this_phase; every other token stays (1, 1, 1, 1)
#     - its roster card is dimmed (darker stylebox + the same modulate)
#     - a network client — diffs through GameManager.apply_result, no
#       execute_action, no signal — dims too
#     - a token rebuilt mid-phase starts dim
#     - the next phase resets every token and card
#     - the Can Act filter lists exactly the units that have not acted
#
# The rendered frame (the token and card actually darker, the T08 rings still
# readable) is covered by tests/scenarios/visual/T09_exhaustion_grayscale.json.
#
# Usage: godot --headless --path . -s tests/test_unit_exhaustion.gd

const PH_COMMAND := 6
const PH_MOVEMENT := 7
const PH_SHOOTING := 8
const PH_CHARGE := 9
const PH_FIGHT := 10
const DIM := Color(0.6, 0.6, 0.6, 1.0)
const LIT := Color(1.0, 1.0, 1.0, 1.0)

var passed := 0
var failed := 0
var _ran := false

var GS = null
var PM = null
var GM = null
var _emitted: Array = []
var _main: Node = null
var _layer: Node2D = null
var _roster = null
var _tracker = null
var TV = null


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init():
	create_timer(0.1).timeout.connect(_run_tests)


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _unit(owner: int, unit_name: String, x: float, y: float, flags: Dictionary = {}) -> Dictionary:
	return {
		"owner": owner, "status": 2, "flags": flags.duplicate(true),
		"meta": {"name": unit_name, "display_name": unit_name, "keywords": ["INFANTRY"],
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 2, "objective_control": 1}},
		"models": [{"id": "m1", "alive": true, "wounds": 2, "current_wounds": 2,
			"base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}}],
	}


func _seed_state() -> void:
	var units := {
		"U_T09_A": _unit(1, "Movers", 400.0, 400.0),
		"U_T09_B": _unit(1, "Holders", 600.0, 400.0),
		"U_T09_C": _unit(1, "Bodyguard", 800.0, 400.0),
		"U_T09_CH": _unit(1, "Leader", 840.0, 400.0),
		# The opponent: flags left over from its own turn (moved) and from Fire
		# Overwatch earlier in this turn (has_shot).
		"U_T09_E": _unit(2, "Opponent", 400.0, 1600.0, {"moved": true, "has_shot": true}),
	}
	units["U_T09_C"]["attachment_data"] = {"attached_characters": ["U_T09_CH"]}
	units["U_T09_CH"]["attached_to"] = "U_T09_C"
	units["U_T09_CH"]["meta"]["keywords"] = ["INFANTRY", "CHARACTER"]
	GS.state["units"] = units
	GS.state["meta"]["active_player"] = 1
	GS.state["meta"]["phase"] = PH_COMMAND


func _on_acted(unit_id: String) -> void:
	_emitted.append(unit_id)


func _bind_phase() -> Object:
	var phase = PM.get_current_phase_instance()
	if phase != null and not phase.unit_acted_in_phase.is_connected(_on_acted):
		phase.unit_acted_in_phase.connect(_on_acted)
	return phase


func _tokens_of(unit_id: String) -> Array:
	var out: Array = []
	for t in _layer.get_children():
		if t.is_queued_for_deletion():
			continue
		if t.has_meta("unit_id") and str(t.get_meta("unit_id")) == unit_id:
			out.append(t)
	return out


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= 0.02 and absf(a.g - b.g) <= 0.02 and absf(a.b - b.b) <= 0.02 and absf(a.a - b.a) <= 0.02


func _token_state(unit_id: String) -> String:
	var parts: Array = []
	for t in _tokens_of(unit_id):
		parts.append("%s/%s" % [t.modulate.to_html(true), str(t.is_exhausted_this_phase)])
	return ",".join(parts)


func _token_dim(unit_id: String) -> bool:
	var ts := _tokens_of(unit_id)
	if ts.is_empty():
		return false
	for t in ts:
		if not (_near(t.modulate, DIM) and t.is_exhausted_this_phase):
			return false
	return true


func _token_lit(unit_id: String) -> bool:
	var ts := _tokens_of(unit_id)
	if ts.is_empty():
		return false
	for t in ts:
		if not (_near(t.modulate, LIT) and not t.is_exhausted_this_phase):
			return false
	return true


func _card(unit_id: String):
	return _roster.get_node_or_null("Scroll/Cards/UnitCard_%s" % unit_id)


func _card_dim(unit_id: String) -> bool:
	var c = _card(unit_id)
	if c == null:
		return false
	var sb = c.get_theme_stylebox("panel")
	return _roster.is_card_exhausted(unit_id) and _near(c.modulate, DIM) \
		and c.has_theme_stylebox_override("panel") and sb is StyleBoxFlat \
		and sb.bg_color.v < 0.1


func _card_lit(unit_id: String) -> bool:
	var c = _card(unit_id)
	if c == null:
		return false
	return not _roster.is_card_exhausted(unit_id) and _near(c.modulate, LIT) \
		and not c.has_theme_stylebox_override("panel")


func _add_token(unit_id: String) -> Node2D:
	var t = TV.new()
	var u: Dictionary = GS.state["units"][unit_id]
	t.owner_player = int(u["owner"])
	t.set_model_data(u["models"][0].duplicate(true))
	t.set_meta("unit_id", unit_id)
	t.set_meta("model_id", "m1")
	var p: Dictionary = u["models"][0]["position"]
	t.position = Vector2(float(p["x"]), float(p["y"]))
	_layer.add_child(t)
	return t


func _build_ui() -> void:
	# Stand-in for Main: the tracker reads BoardRoot/TokenLayer and LeftRoster
	# off its parent. Not named "Main", so nothing that looks /root/Main up
	# (SceneRefs) mistakes it for the battle scene.
	_main = Node.new()
	_main.name = "T09Main"
	root.add_child(_main)
	var board := Node2D.new()
	board.name = "BoardRoot"
	_main.add_child(board)
	_layer = Node2D.new()
	_layer.name = "TokenLayer"
	board.add_child(_layer)
	for uid in ["U_T09_A", "U_T09_B", "U_T09_C", "U_T09_CH", "U_T09_E"]:
		_add_token(uid)
	_roster = load("res://scripts/LeftRosterStrip.gd").new()
	_main.add_child(_roster)
	_roster.refresh()
	_tracker = load("res://scripts/UnitExhaustionTracker.gd").new()
	_main.add_child(_tracker)


func _run_tests() -> void:
	if _ran:
		return
	_ran = true
	print("\n=== test_unit_exhaustion (T09) ===\n")
	GS = root.get_node_or_null("GameState")
	PM = root.get_node_or_null("PhaseManager")
	GM = root.get_node_or_null("GameManager")
	if GS == null or PM == null or GM == null:
		_check("GameState / PhaseManager / GameManager reachable", false)
		_finish()
		return
	TV = load("res://scripts/TokenVisual.gd")
	var prev_state = GS.state.duplicate(true)
	_seed_state()
	_build_ui()
	_check("UnitExhaustionTracker installed under the stand-in Main",
		_main.get_node_or_null("UnitExhaustionTracker") == _tracker)
	_check("roster strip built a card per unit",
		_card("U_T09_A") != null and _card("U_T09_E") != null)

	_test_command_phase_default()
	_test_movement()
	_test_shooting()
	_test_charge()
	_test_fight()
	_test_back_to_command()

	_main.queue_free()
	GS.state = prev_state
	_finish()


func _test_command_phase_default() -> void:
	print("\n-- Command phase: no unit has acted (default) --")
	PM.transition_to_phase(PH_COMMAND)
	var phase = _bind_phase()
	_check("Command phase active", GS.get_current_phase() == PH_COMMAND)
	_check("no unit acted although U_T09_E carries moved/has_shot flags",
		phase.get_units_acted_this_phase().is_empty(), str(phase.get_units_acted_this_phase()))
	_check("every token lit at the start",
		_token_lit("U_T09_A") and _token_lit("U_T09_B") and _token_lit("U_T09_E"))


func _test_movement() -> void:
	print("\n-- Movement phase --")
	PM.transition_to_phase(PH_MOVEMENT)
	var phase = _bind_phase()
	_emitted.clear()
	_check("Movement phase active", GS.get_current_phase() == PH_MOVEMENT)
	_check("tracker bound to the movement phase's unit_acted_in_phase",
		phase.unit_acted_in_phase.is_connected(_tracker._on_unit_acted_in_phase))
	_check("opponent's left-over flags.moved does not count",
		not phase.has_unit_acted_this_phase("U_T09_E"))
	_check("nobody has acted at the start of the phase",
		phase.get_units_acted_this_phase().is_empty(), str(phase.get_units_acted_this_phase()))

	var r = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_T09_A"})
	_check("BEGIN_NORMAL_MOVE U_T09_A succeeds", r.get("success", false), str(r.get("error", "")))
	r = phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": "U_T09_A",
		"payload": {"model_id": "m1", "dest": [400.0, 520.0]}})
	_check("STAGE_MODEL_MOVE 3\" succeeds", r.get("success", false), str(r.get("error", r.get("errors", ""))))
	_check("a unit in the middle of its move has not acted yet",
		not phase.has_unit_acted_this_phase("U_T09_A") and _emitted.is_empty() and _token_lit("U_T09_A"),
		"emitted=%s token=%s" % [str(_emitted), _token_state("U_T09_A")])

	r = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_T09_A", "payload": {}})
	_check("End This Unit's Move (CONFIRM_UNIT_MOVE) succeeds", r.get("success", false), str(r.get("error", "")))
	_check("U_T09_A has acted", phase.has_unit_acted_this_phase("U_T09_A"))
	_check("unit_acted_in_phase emitted once, for U_T09_A", _emitted == ["U_T09_A"], str(_emitted))
	_check("tracker received the signal", _tracker.last_acted_unit_id == "U_T09_A" and _tracker.acted_signal_count == 1,
		"%s/%d" % [_tracker.last_acted_unit_id, _tracker.acted_signal_count])
	_check("acted token: modulate (0.6, 0.6, 0.6, 1) and is_exhausted_this_phase", _token_dim("U_T09_A"), _token_state("U_T09_A"))
	_check("un-acted tokens: modulate (1, 1, 1, 1), not exhausted",
		_token_lit("U_T09_B") and _token_lit("U_T09_C") and _token_lit("U_T09_CH") and _token_lit("U_T09_E"),
		"B=%s C=%s E=%s" % [_token_state("U_T09_B"), _token_state("U_T09_C"), _token_state("U_T09_E")])
	_check("acted unit's roster card dimmed (darker stylebox + modulate)", _card_dim("U_T09_A"))
	_check("un-acted cards keep the default look", _card_lit("U_T09_B") and _card_lit("U_T09_E"))
	_check("tracker.acted_unit_ids == [U_T09_A]", _tracker.acted_unit_ids == ["U_T09_A"], str(_tracker.acted_unit_ids))

	# A re-sync leaves a controller's tint on an un-acted token alone (the fight
	# overlap red while dragging), and puts the dim back on an acted token whose
	# modulate was reset to white (that feedback does so when a drag ends).
	var red := Color(1.0, 0.3, 0.3, 1.0)
	var b_tok: Node2D = _tokens_of("U_T09_B")[0]
	var a_tok: Node2D = _tokens_of("U_T09_A")[0]
	b_tok.modulate = red
	a_tok.modulate = LIT
	_tracker.refresh()
	_check("re-sync keeps an un-acted token's controller tint", _near(b_tok.modulate, red), b_tok.modulate.to_html(true))
	_check("re-sync restores the dim on an acted token reset to white",
		_near(a_tok.modulate, DIM) and a_tok.is_exhausted_this_phase, a_tok.modulate.to_html(true))
	b_tok.modulate = LIT

	# A token rebuilt mid-phase (Main._recreate_unit_visuals) starts dim.
	for t in _tokens_of("U_T09_A"):
		_layer.remove_child(t)
		t.free()
	var rebuilt := _add_token("U_T09_A")
	_check("a token rebuilt mid-phase starts dim",
		_near(rebuilt.modulate, DIM) and rebuilt.is_exhausted_this_phase, _token_state("U_T09_A"))

	# A refused action and a no-op action announce nothing.
	r = phase.execute_action({"type": "REMAIN_STATIONARY", "actor_unit_id": "U_T09_A"})
	_check("REMAIN_STATIONARY after the move is refused", not r.get("success", true))
	r = phase.execute_action({"type": "END_COMMAND"})
	_check("a no-op action succeeds", r.get("success", false))
	_check("neither re-emitted", _emitted == ["U_T09_A"], str(_emitted))

	# Remain Stationary: the bodyguard and its attached character act together.
	r = phase.execute_action({"type": "REMAIN_STATIONARY", "actor_unit_id": "U_T09_C"})
	_check("REMAIN_STATIONARY U_T09_C succeeds", r.get("success", false), str(r.get("error", "")))
	_check("bodyguard and attached character both acted (one signal each)",
		_emitted == ["U_T09_A", "U_T09_C", "U_T09_CH"], str(_emitted))
	_check("both their tokens dimmed", _token_dim("U_T09_C") and _token_dim("U_T09_CH"))

	# Network client: the host's diffs arrive through GameManager.apply_result;
	# the client's phase never runs execute_action, so no signal fires.
	var before_count: int = _tracker.acted_signal_count
	GM.apply_result({"success": true, "diffs": [
		{"op": "set", "path": "units.U_T09_B.flags.moved", "value": true}]})
	_check("client path: U_T09_B dims from the applied diff", _token_dim("U_T09_B"), _token_state("U_T09_B"))
	_check("client path: its card dims", _card_dim("U_T09_B"))
	_check("client path: no unit_acted_in_phase was needed",
		_tracker.acted_signal_count == before_count, str(_tracker.acted_signal_count))

	# Can Act lists exactly the units that have not acted (the opponent here).
	_roster.set_active_filter("can_act")
	_check("Can Act lists only the units that have not acted",
		_roster.visible_unit_ids == ["U_T09_E"], str(_roster.visible_unit_ids))
	_roster.set_active_filter("all")
	_check("All lists every unit again", _roster.visible_unit_ids.size() == 5, str(_roster.visible_unit_ids))
	_check("a rebuilt strip keeps the dim cards (UnitCard_<id> resolves to the live card)",
		_card_dim("U_T09_A") and _card_lit("U_T09_E")
		and not _card("U_T09_A").is_queued_for_deletion() and not _card("U_T09_E").is_queued_for_deletion()
		and _roster.get_node("Scroll/Cards").get_child_count() == 5,
		"cards=%d" % _roster.get_node("Scroll/Cards").get_child_count())


func _test_shooting() -> void:
	print("\n-- Shooting phase: the next phase resets everything --")
	PM.transition_to_phase(PH_SHOOTING)
	var phase = _bind_phase()
	_emitted.clear()
	_check("Shooting phase active", GS.get_current_phase() == PH_SHOOTING)
	_check("tracker rebound to the shooting phase",
		phase.unit_acted_in_phase.is_connected(_tracker._on_unit_acted_in_phase))
	var all_lit := true
	for uid in ["U_T09_A", "U_T09_B", "U_T09_C", "U_T09_CH", "U_T09_E"]:
		all_lit = all_lit and _token_lit(uid)
	_check("phase change: every token back to (1, 1, 1, 1)", all_lit,
		"A=%s B=%s" % [_token_state("U_T09_A"), _token_state("U_T09_B")])
	_check("phase change: every card back to the default look",
		_card_lit("U_T09_A") and _card_lit("U_T09_B") and _card_lit("U_T09_C"))
	_check("phase change: tracker.acted_unit_ids empty", _tracker.acted_unit_ids.is_empty(), str(_tracker.acted_unit_ids))
	_check("opponent's Fire Overwatch has_shot does not count",
		not phase.has_unit_acted_this_phase("U_T09_E"))
	var r = phase.execute_action({"type": "SKIP_UNIT", "actor_unit_id": "U_T09_A"})
	_check("SKIP_UNIT U_T09_A succeeds", r.get("success", false), str(r.get("error", "")))
	_check("skipped shooter has acted, signal emitted", phase.has_unit_acted_this_phase("U_T09_A") and _emitted == ["U_T09_A"], str(_emitted))
	_check("its token dimmed", _token_dim("U_T09_A"), _token_state("U_T09_A"))
	_check("the others stay lit", _token_lit("U_T09_B") and _token_lit("U_T09_E"))


func _test_charge() -> void:
	print("\n-- Charge phase --")
	PM.transition_to_phase(PH_CHARGE)
	var phase = _bind_phase()
	_emitted.clear()
	_check("Charge phase active", GS.get_current_phase() == PH_CHARGE)
	_check("tokens reset on entering the Charge phase", _token_lit("U_T09_A"), _token_state("U_T09_A"))
	var r = phase.execute_action({"type": "SKIP_CHARGE", "actor_unit_id": "U_T09_A"})
	_check("SKIP_CHARGE U_T09_A succeeds", r.get("success", false), str(r.get("error", "")))
	_check("skipped charger has acted, signal emitted", phase.has_unit_acted_this_phase("U_T09_A") and _emitted == ["U_T09_A"], str(_emitted))
	_check("its token dimmed", _token_dim("U_T09_A"))
	GM.apply_result({"success": true, "diffs": [
		{"op": "set", "path": "units.U_T09_B.flags.charged_this_turn", "value": true}]})
	_check("charged_this_turn (client view) counts as acted",
		phase.has_unit_acted_this_phase("U_T09_B") and _token_dim("U_T09_B"), _token_state("U_T09_B"))
	_check("a unit that has not charged stays lit", _token_lit("U_T09_C"))


func _test_fight() -> void:
	print("\n-- Fight phase --")
	PM.transition_to_phase(PH_FIGHT)
	var phase = _bind_phase()
	_check("Fight phase active", GS.get_current_phase() == PH_FIGHT)
	_check("charged_this_turn alone is not 'acted' in the Fight phase", not phase.has_unit_acted_this_phase("U_T09_B"))
	_check("tokens reset on entering the Fight phase", _token_lit("U_T09_A") and _token_lit("U_T09_B"))
	GM.apply_result({"success": true, "diffs": [
		{"op": "set", "path": "units.U_T09_E.flags.has_fought", "value": true}]})
	_check("has_fought counts for either player (the opponent fought)",
		phase.has_unit_acted_this_phase("U_T09_E") and _token_dim("U_T09_E"), _token_state("U_T09_E"))
	phase.units_that_fought.append("U_T09_A")
	_check("units_that_fought counts", phase.has_unit_acted_this_phase("U_T09_A"))
	_check("not yet fought stays lit", _token_lit("U_T09_C"))


func _test_back_to_command() -> void:
	print("\n-- Back to a phase without a per-unit step --")
	PM.transition_to_phase(PH_COMMAND)
	var phase = _bind_phase()
	_check("Command phase: no unit has acted (flags ignored)",
		phase.get_units_acted_this_phase().is_empty(), str(phase.get_units_acted_this_phase()))
	_check("every token lit", _token_lit("U_T09_A") and _token_lit("U_T09_E"))
	_check("every card lit", _card_lit("U_T09_A") and _card_lit("U_T09_E"))

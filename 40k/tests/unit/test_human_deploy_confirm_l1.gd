extends SceneTree

# Human deployment through a REAL DeploymentController (review L1-1 .. L1-5,
# L4-4 part) on the bw_load_deploy_pretrigger fixture (tipping point, Lootas
# leading Big Meks, formations declared, 11e).
#
# L1-2 — a Confirm the phase REFUSES keeps the placement session open. The old
#   handling finalized the preview tokens, cleared the session and emitted
#   unit_confirmed anyway, leaving the unit DEPLOYING with no model positions,
#   gone from every list and never blocking END_DEPLOYMENT (stranded). Both
#   failure branches are driven: COMPOSITE_DEPLOY (bodyguard + leader) and a
#   plain DEPLOY_UNIT. The refusal is provoked by a deployed model the placement
#   UI did not see standing where a staged model is (a stand-in for any UI /
#   phase disagreement); the player then moves that model and Confirms again.
# L1-1 — the reposition validator (Shift+click / pad L3 drop) refuses a spot
#   the click path refuses: a MOUNTED model on a solid 11e piece, a base off the
#   board edge in Infiltrators mode; a combined session is in Infiltrators mode
#   only when the bodyguard AND every attached character have Infiltrators;
#   _validate_formation_position reads the keywords of the model's own unit.
# L1-3 — the phase judges a COMPOSITE_DEPLOY's coherency once, over bodyguard +
#   characters (19.01); DEPLOY_UNIT and an empty combined_char_data keep the
#   bodyguard-only check, and the merged check still refuses a stray leader.
# L1-5 — the game-log line for a human COMPOSITE_DEPLOY names the leader and
#   counts the whole attached unit.
# L4-4 — the Infiltrators "inside the enemy zone" toast states the edition's
#   stand-off (8" at 11e).
#
# Run with: godot --headless --path . -s tests/unit/test_human_deploy_confirm_l1.gd

const FIXTURE := "res://tests/saves/bw_load_deploy_pretrigger.w40ksave"
const ORK := 2
const DEPLOYING := 1
const DEPLOYED := 2

var GS
var PM
var SL
var AI
var BS
var GEL
var TM
var TOASTS

var _pass_count: int = 0
var _fail_count: int = 0
var _confirmed: int = 0

func _init():
	create_timer(0.3).timeout.connect(_run)

func _run():
	print("\n=== Human deployment confirm / checks (L1-1 .. L1-5) ===\n")
	GS = root.get_node_or_null("GameState")
	PM = root.get_node_or_null("PhaseManager")
	SL = root.get_node_or_null("SaveLoadManager")
	AI = root.get_node_or_null("AIPlayer")
	BS = root.get_node_or_null("BoardState")
	GEL = root.get_node_or_null("GameEventLog")
	TM = root.get_node_or_null("TerrainManager")
	TOASTS = root.get_node_or_null("ToastManager")
	if GS == null or PM == null or SL == null or AI == null or BS == null or GEL == null or TM == null or TOASTS == null:
		_assert(false, "autoloads available at run time")
	else:
		var saved_edition: int = GameConstants.edition
		GameConstants.edition = 11
		await test_composite_refusal_keeps_session()
		await test_deploy_unit_refusal_keeps_session()
		await test_lifted_leader_updates_coherency_circles()
		await test_reposition_refuses_solid_piece_and_off_board()
		await test_combined_infiltrators_needs_every_member()
		await test_formation_position_reads_model_keywords()
		await test_phase_merged_coherency_decides()
		await test_game_log_names_leader()
		await test_infiltrators_toast_uses_edition_standoff()
		GameConstants.edition = saved_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	print("ALL TESTS PASSED" if _fail_count == 0 else "SOME TESTS FAILED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

# ---------------------------------------------------------------------------

func _load() -> Object:
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}
	if not SL.load_game_from_file_path(FIXTURE):
		_assert(false, "fixture loads")
		return null
	GameConstants.edition = 11
	var gc = GS.state["meta"].get("game_config", {})
	if gc == null:
		gc = {}
	gc["player1_type"] = "HUMAN"
	gc["player2_type"] = "HUMAN"
	GS.state["meta"]["game_config"] = gc
	PM.transition_to_phase(1)
	await process_frame
	GS.state["meta"]["active_player"] = ORK
	# Main.setup_deployment_zones() does this in the game; a bare -s run keeps
	# BoardState at its default zones otherwise.
	BS.initialize_deployment_zones(GS.get_deployment_type())
	for t in TOASTS.active_toasts:
		if is_instance_valid(t):
			t.queue_free()
	TOASTS.active_toasts.clear()
	_confirmed = 0
	return PM.get_current_phase_instance()

func _make_dc() -> Node:
	var dc = load("res://scripts/DeploymentController.gd").new()
	root.add_child(dc)
	var tl := Node2D.new()
	root.add_child(tl)
	var gl := Node2D.new()
	root.add_child(gl)
	dc.set_layers(tl, gl)
	dc.unit_confirmed.connect(func(): _confirmed += 1)
	return dc

func _free_dc(dc: Node) -> void:
	if dc == null:
		return
	if dc.token_layer and is_instance_valid(dc.token_layer):
		dc.token_layer.queue_free()
	if dc.ghost_layer and is_instance_valid(dc.ghost_layer):
		dc.ghost_layer.queue_free()
	dc.queue_free()

func _place(dc: Node, points: Array) -> int:
	"""try_place_at each point on the slot the controller offers; returns how
	many drops stuck."""
	var ok := 0
	for p in points:
		var slot: int = dc.model_idx
		if slot < 0 or slot >= dc.temp_positions.size():
			break
		dc.try_place_at(p)
		if dc.temp_positions[slot] != null:
			ok += 1
	return ok

func _finalized_tokens(dc: Node, ids: Array) -> int:
	var n := 0
	for c in dc.token_layer.get_children():
		if c.has_meta("unit_id") and str(c.get_meta("unit_id")) in ids:
			n += 1
	return n

func _toast_containing(fragment: String) -> String:
	for t in TOASTS.active_toasts:
		if is_instance_valid(t) and t.get_child_count() > 0:
			var lbl = t.get_child(0)
			if lbl is Label and str(lbl.text).contains(fragment):
				return str(lbl.text)
	return ""

func _plant_obstacle(unit_id: String, at: Vector2) -> void:
	"""A DEPLOYED model the placement UI never checked against (it arrived after
	the drops) — stands in for any UI / phase disagreement at Confirm."""
	var u: Dictionary = GS.state.units[unit_id]
	u["status"] = DEPLOYED
	u.models[0]["position"] = {"x": at.x, "y": at.y}

func _clear_obstacle(unit_id: String) -> void:
	var u: Dictionary = GS.state.units[unit_id]
	u["status"] = 0
	u.models[0]["position"] = null

func _move_staged(dc: Node, slot: int, to: Vector2) -> void:
	"""What a committed Shift+click reposition leaves behind (_end_model_repositioning)."""
	dc.temp_positions[slot] = to
	var token = dc._find_preview_token(slot)
	if token:
		token.position = to

func _lootas_two_ranks() -> Array:
	var pts: Array = []
	for i in range(5):
		pts.append(Vector2(300.0 + 56.0 * i, 2340.0))
	for i in range(5):
		pts.append(Vector2(300.0 + 56.0 * i, 2280.0))
	return pts

# ---------------------------------------------------------------------------

func test_composite_refusal_keeps_session() -> void:
	print("\n--- L1-2: a refused COMPOSITE_DEPLOY keeps the session open ---")
	var phase = await _load()
	if phase == null:
		return
	var dc = _make_dc()
	dc.begin_deploy("U_LOOTAS_A")
	_assert(dc.is_combined_deployment and dc.get_total_model_count() == 11, "combined session: 10 Lootas + Big Mek Beta")
	dc._on_model_type_selected("bg_U_LOOTAS_A")
	var mek := Vector2(620.0, 2310.0)
	var placed := _place(dc, _lootas_two_ranks() + [mek])
	_assert(placed == 11 and dc._is_unit_coherent(), "all 11 models staged, coherent (%d)" % placed)
	_plant_obstacle("U_CUSTODIAN_GUARD_A", mek)
	dc.confirm()
	await process_frame
	var u = GS.state.units
	_assert(dc.unit_id == "U_LOOTAS_A" and dc.is_placing() and dc.is_combined_deployment,
		"the session is still open on Lootas Alpha (unit_id='%s')" % dc.unit_id)
	_assert(dc.get_placed_count() == 11 and dc.placed_tokens.size() == 11,
		"all 11 staged positions and preview tokens kept (%d / %d)" % [dc.get_placed_count(), dc.placed_tokens.size()])
	_assert(_finalized_tokens(dc, ["U_LOOTAS_A", "U_BIG_MEK_B"]) == 0, "no preview was promoted to a permanent board token")
	_assert(int(u["U_LOOTAS_A"].status) == DEPLOYING and int(u["U_BIG_MEK_B"].status) == 0,
		"statuses unchanged: bodyguard DEPLOYING (owned by the open session), leader UNDEPLOYED")
	_assert(u["U_LOOTAS_A"].models[0].get("position") == null and u["U_BIG_MEK_B"].models[0].get("position") == null,
		"nothing written to GameState")
	_assert(_confirmed == 0, "unit_confirmed was NOT emitted (Main keeps the card and Confirm up)")
	var toast := _toast_containing("Deployment refused")
	_assert(toast != "" and toast.contains("overlap"), "the refusal reason is shown: '%s'" % toast)
	# The player moves the leader off the obstacle and Confirms again.
	_move_staged(dc, 10, Vector2(620.0, 2220.0))
	_assert(dc._is_unit_coherent(), "the moved leader is still coherent with the squad")
	dc.confirm()
	await process_frame
	_assert(int(u["U_LOOTAS_A"].status) == DEPLOYED and int(u["U_BIG_MEK_B"].status) == DEPLOYED,
		"re-Confirm accepted: bodyguard and leader DEPLOYED")
	_assert(_finalized_tokens(dc, ["U_LOOTAS_A"]) == 10 and _finalized_tokens(dc, ["U_BIG_MEK_B"]) == 1,
		"exactly one board token per model (10 + 1)")
	_assert(dc.unit_id == "" and not dc.is_placing() and dc.placed_tokens.is_empty() and _confirmed == 1,
		"session closed once, unit_confirmed emitted once")
	_clear_obstacle("U_CUSTODIAN_GUARD_A")
	_free_dc(dc)

func test_deploy_unit_refusal_keeps_session() -> void:
	print("\n--- L1-2: a refused DEPLOY_UNIT keeps the session open ---")
	var phase = await _load()
	if phase == null:
		return
	var dc = _make_dc()
	dc.begin_deploy("U_BURNA_BOYZ_A")
	var pts: Array = []
	for i in range(5):
		pts.append(Vector2(300.0 + 56.0 * i, 2300.0))
	_assert(_place(dc, pts) == 5 and not dc.is_combined_deployment, "5 Burna Boyz staged (plain unit)")
	_plant_obstacle("U_CUSTODIAN_GUARD_B", Vector2(550.0, 2300.0))
	dc.confirm()
	await process_frame
	var bb = GS.state.units["U_BURNA_BOYZ_A"]
	_assert(dc.unit_id == "U_BURNA_BOYZ_A" and dc.is_placing() and dc.get_placed_count() == 5 and dc.placed_tokens.size() == 5,
		"the session is still open with its 5 previews")
	_assert(int(bb.status) == DEPLOYING and bb.models[0].get("position") == null and _finalized_tokens(dc, ["U_BURNA_BOYZ_A"]) == 0,
		"not stranded: status DEPLOYING owned by the session, no positions, no permanent tokens")
	_assert(_confirmed == 0 and _toast_containing("Deployment refused") != "", "no unit_confirmed; the refusal toast is shown")
	_move_staged(dc, 4, Vector2(468.0, 2240.0))
	dc.confirm()
	await process_frame
	_assert(int(bb.status) == DEPLOYED and _finalized_tokens(dc, ["U_BURNA_BOYZ_A"]) == 5 and _confirmed == 1 and dc.unit_id == "",
		"re-Confirm accepted: DEPLOYED, 5 board tokens, session closed")
	_clear_obstacle("U_CUSTODIAN_GUARD_B")
	_free_dc(dc)

func test_lifted_leader_updates_coherency_circles() -> void:
	print("\n--- lifting an attached leader keeps the coherency circles live ---")
	var phase = await _load()
	if phase == null:
		return
	var dc = _make_dc()
	dc.begin_deploy("U_LOOTAS_A")
	dc._on_model_type_selected("bg_U_LOOTAS_A")
	var mek := Vector2(620.0, 2310.0)
	_assert(_place(dc, _lootas_two_ranks() + [mek]) == 11 and dc.coherency_circles.size() == 11,
		"11 models staged, one coherency circle each")
	var held: Dictionary = dc._get_deployed_model_at_position(mek)
	_assert(int(held.get("model_index", -1)) == 10, "Shift+click hit-test finds the Big Mek at combined slot 10")
	dc._start_model_repositioning(held)
	dc._update_coherency_circles()
	# The lifted slot's circle is hidden inside the per-circle loop; the old code
	# indexed the bodyguard's 10-model array with slot 10 and aborted every frame
	# before reaching it ("Invalid access of index '10'").
	_assert(dc.is_repositioning() and not dc.coherency_circles[10].visible and dc.coherency_circles[0].visible,
		"the lifted leader's circle is hidden and the squad's circles stay live (the update ran through)")
	dc._cancel_model_repositioning()
	_free_dc(dc)

func test_reposition_refuses_solid_piece_and_off_board() -> void:
	print("\n--- L1-1: the reposition drop applies the wall / solid-piece and off-board checks ---")
	var phase = await _load()
	if phase == null:
		return
	var dc = _make_dc()
	dc.begin_deploy("U_WARBIKERS_A")
	# Live tipping_point zone for P2: x>=22in,y>=40in plus x<22in,y>=48in.
	var bikes := [Vector2(1112.0, 1992.0), Vector2(1192.0, 1992.0), Vector2(1272.0, 1992.0)]
	_assert(_place(dc, bikes) == 3, "3 Warbikers (MOUNTED) staged just south of corner-ruin-left-19")
	var md: Dictionary = dc._reposition_model_data(1)
	var onto := Vector2(1192.0, 1856.0)
	var probe: Dictionary = md.duplicate()
	probe["position"] = onto
	probe["rotation"] = dc.temp_rotations[1]
	_assert(TM.solid_terrain_endpoint_blocker_11e(probe, GS.state.units["U_WARBIKERS_A"].meta.keywords) == "corner-ruin-left-19",
		"precondition: that spot is on corner-ruin-left-19 (dense, 5in) — MOUNTED cannot end there at 11e")
	_assert(not dc._validate_reposition(onto, md, 1, true), "a lifted bike cannot be dropped on the ruin wall")
	_assert(dc._validate_reposition(Vector2(1192.0, 2080.0), md, 1, true), "...but can be nudged to a clear legal spot")
	var phase_v: Dictionary = phase.validate_action({"type": "DEPLOY_UNIT", "unit_id": "U_WARBIKERS_A", "player": ORK,
		"model_positions": [bikes[0], onto, bikes[2]], "model_rotations": dc.temp_rotations.duplicate()})
	_assert(not phase_v.get("valid", true) and str(phase_v.get("errors", [])).contains("overlap with walls this unit can"),
		"(the phase refuses that set-up too: %s)" % str(phase_v.get("errors", [])))
	var ok_v: Dictionary = phase.validate_action({"type": "DEPLOY_UNIT", "unit_id": "U_WARBIKERS_A", "player": ORK,
		"model_positions": bikes.duplicate(), "model_rotations": dc.temp_rotations.duplicate()})
	_assert(ok_v.get("valid", false), "(and accepts the bikes where they stand: %s)" % str(ok_v.get("errors", [])))
	_free_dc(dc)

	# Off-board: Infiltrators mode only tests the model's CENTRE against the board.
	phase = await _load()
	var ab: Array = GS.state.units["U_BURNA_BOYZ_B"].meta.get("abilities", []).duplicate()
	ab.append({"name": "Infiltrators", "type": "Core"})
	GS.state.units["U_BURNA_BOYZ_B"].meta["abilities"] = ab
	dc = _make_dc()
	dc.begin_deploy("U_BURNA_BOYZ_B")
	_assert(dc.is_infiltrators_mode, "Burna Boyz with Infiltrators deploy in Infiltrators mode")
	var nml: Array = []
	for i in range(5):
		nml.append(Vector2(200.0 + 56.0 * i, 1240.0))
	_assert(_place(dc, nml) == 5, "5 Infiltrators staged in no-man's land (>8in from the enemy zone)")
	var md0: Dictionary = dc._reposition_model_data(0)
	_assert(not dc._validate_reposition(Vector2(10.0, 1240.0), md0, 0, true),
		"a lifted model whose base hangs off the board edge (centre on the board) is refused")
	_assert(dc._validate_reposition(Vector2(200.0, 1300.0), md0, 0, true), "...an on-board nudge is accepted")
	_free_dc(dc)

func test_combined_infiltrators_needs_every_member() -> void:
	print("\n--- L1-1 / 24.20: combined Infiltrators mode needs the bodyguard AND every attached character ---")
	var phase = await _load()
	if phase == null:
		return
	var ab: Array = GS.state.units["U_LOOTAS_B"].meta.get("abilities", []).duplicate()
	ab.append({"name": "Infiltrators", "type": "Core"})
	GS.state.units["U_LOOTAS_B"].meta["abilities"] = ab
	var dc = _make_dc()
	dc.begin_deploy("U_LOOTAS_B")
	_assert(dc.is_combined_deployment and not dc.is_infiltrators_mode,
		"Lootas with Infiltrators led by a Big Mek without it: NOT Infiltrators mode (zone rules for the whole attached unit)")
	dc.reset_unit()
	var cab: Array = GS.state.units["U_BIG_MEK_C"].meta.get("abilities", []).duplicate()
	cab.append({"name": "Infiltrators", "type": "Core"})
	GS.state.units["U_BIG_MEK_C"].meta["abilities"] = cab
	dc.begin_deploy("U_LOOTAS_B")
	_assert(dc.is_combined_deployment and dc.is_infiltrators_mode, "both have Infiltrators: Infiltrators mode")
	_free_dc(dc)

func test_formation_position_reads_model_keywords() -> void:
	print("\n--- L1-1: _validate_formation_position judges walls with the model's own unit keywords ---")
	var phase = await _load()
	if phase == null:
		return
	# Make the attached leader MOUNTED (its squad stays INFANTRY) — no shipped
	# pair differs like this today, which is why the gap was latent.
	GS.state.units["U_BIG_MEK_B"].meta["keywords"] = ["CHARACTER", "MOUNTED", "ORKS"]
	var dc = _make_dc()
	dc.begin_deploy("U_LOOTAS_A")
	var mek_slot := -1
	for i in range(dc.combined_models.size()):
		if str(dc.combined_models[i]["unit_id"]) == "U_BIG_MEK_B":
			mek_slot = i
	_assert(mek_slot == 10, "the leader is combined slot 10")
	var zone = BS.get_deployment_zone_for_player(ORK)
	var md: Dictionary = dc.combined_models[mek_slot]["model_data"]
	var on_ruin := Vector2(1060.0, 1720.0)
	_assert(not dc._validate_formation_position(on_ruin, md, zone, 0.0, true, mek_slot),
		"with its slot, the MOUNTED leader is refused on the corner ruin's wall")
	_assert(dc._validate_formation_position(on_ruin, md, zone, 0.0, true, 0),
		"judged as a Loota's slot (INFANTRY) the same spot passes — so the slot is what decides")
	_free_dc(dc)

func test_phase_merged_coherency_decides() -> void:
	print("\n--- L1-3: the phase judges an attached unit's coherency once, as one unit ---")
	var phase = await _load()
	if phase == null:
		return
	var block: Array = []
	for r in range(3):
		for c in range(3):
			block.append(Vector2(900.0 + 56.0 * c, 2120.0 + 56.0 * r))
	var lootas: Array = block.duplicate()
	lootas.append(Vector2(1204.0, 2176.0))
	var rot: Array = []
	for i in range(10):
		rot.append(0.0)
	var bridge := {"U_BIG_MEK_C": [{"x": 1108.0, "y": 2176.0, "rotation": 0.0, "model_idx": 0}]}
	var composite := {"type": "COMPOSITE_DEPLOY", "unit_id": "U_LOOTAS_B", "player": ORK,
		"model_positions": lootas.duplicate(), "model_rotations": rot.duplicate(), "combined_char_data": bridge}
	var v: Dictionary = phase.validate_action(composite.duplicate(true))
	_assert(v.get("valid", false), "the 10th Loota's only 2in neighbour is the leader: ACCEPTED as one attached unit %s" % str(v.get("errors", [])))
	var plain: Dictionary = phase.validate_action({"type": "DEPLOY_UNIT", "unit_id": "U_LOOTAS_B", "player": ORK,
		"model_positions": lootas.duplicate(), "model_rotations": rot.duplicate()})
	_assert(not plain.get("valid", true) and str(plain.get("errors", [])).contains("Unit coherency broken"),
		"the same Lootas as a plain DEPLOY_UNIT keep the bodyguard-only check: refused")
	var empty_ccd: Dictionary = composite.duplicate(true)
	empty_ccd["combined_char_data"] = {}
	var ev: Dictionary = phase.validate_action(empty_ccd)
	_assert(not ev.get("valid", true) and str(ev.get("errors", [])).contains("Unit coherency broken"),
		"a COMPOSITE_DEPLOY with an EMPTY combined_char_data keeps the bodyguard-only check")
	var stray: Dictionary = composite.duplicate(true)
	stray["combined_char_data"] = {"U_BIG_MEK_C": [{"x": 1380.0, "y": 2330.0, "rotation": 0.0, "model_idx": 0}]}
	var sv: Dictionary = phase.validate_action(stray)
	_assert(not sv.get("valid", true) and str(sv.get("errors", [])).contains("Attached unit coherency broken"),
		"the merged 19.01 check still refuses a leader set up away from the squad %s" % str(sv.get("errors", [])))
	# A coherent squad with the leader beside it still validates either way.
	var ranks := _lootas_two_ranks()
	var ok: Dictionary = phase.validate_action({"type": "COMPOSITE_DEPLOY", "unit_id": "U_LOOTAS_A", "player": ORK,
		"model_positions": ranks, "model_rotations": rot.duplicate(),
		"combined_char_data": {"U_BIG_MEK_B": [{"x": 620.0, "y": 2310.0, "rotation": 0.0, "model_idx": 0}]}})
	_assert(ok.get("valid", false), "an ordinary attached set-up is accepted %s" % str(ok.get("errors", [])))

func test_game_log_names_leader() -> void:
	print("\n--- L1-5: the game log names the leader of a COMPOSITE_DEPLOY ---")
	var phase = await _load()
	if phase == null:
		return
	var rot: Array = []
	for i in range(10):
		rot.append(0.0)
	var a := {"type": "COMPOSITE_DEPLOY", "unit_id": "U_LOOTAS_A", "player": ORK, "model_positions": _lootas_two_ranks(),
		"model_rotations": rot, "combined_char_data": {"U_BIG_MEK_B": [{"x": 620.0, "y": 2310.0, "rotation": 0.0, "model_idx": 0}]}}
	var line: String = GEL._format_action(a, "COMPOSITE_DEPLOY", ORK)
	_assert(line == "P2: Deployed Lootas Alpha + Big Mek Beta (11 models)", "COMPOSITE_DEPLOY line: '%s'" % line)
	var plain: String = GEL._format_action({"type": "DEPLOY_UNIT", "unit_id": "U_BURNA_BOYZ_A", "player": ORK}, "DEPLOY_UNIT", ORK)
	_assert(plain == "P2: Deployed Burna Boyz Alpha (5 models)", "plain DEPLOY_UNIT line unchanged: '%s'" % plain)
	var ai_line: String = GEL._format_action({"type": "COMPOSITE_DEPLOY", "unit_id": "U_LOOTAS_A", "_ai_description": "AI deploys X with Y"}, "COMPOSITE_DEPLOY", ORK)
	_assert(ai_line == "P2: AI deploys X with Y", "an AI action keeps its own description: '%s'" % ai_line)

func test_infiltrators_toast_uses_edition_standoff() -> void:
	print("\n--- L4-4: the 'inside the enemy zone' Infiltrators toast states the 11e stand-off ---")
	var phase = await _load()
	if phase == null:
		return
	var dc = _make_dc()
	dc.begin_deploy("U_BURNA_BOYZ_A")
	var md: Dictionary = GS.state.units["U_BURNA_BOYZ_A"].models[0]
	var inside_enemy_zone := Vector2(400.0, 200.0)
	_assert(not dc._validate_infiltrators_position(inside_enemy_zone, md, 0.0, false), "a spot inside the enemy zone is refused")
	var toast := _toast_containing("Infiltrators must be")
	_assert(toast.contains(">8\"") and not toast.contains("9\""), "toast states 8in at 11e: '%s'" % toast)
	_free_dc(dc)

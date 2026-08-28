extends SceneTree

# The 50% reserves caps (11e 20.01 / CA 2025-26) hold for the AI, not just for
# the player.
#
# The bug: FormationsPhase priced a DECLARE_RESERVES by the units the ACTION
# named. The player's dialog names the leaders attached to the reserved
# bodyguard (Main.gd:10229-10240); the AI declares straight off
# get_available_actions and named none. So every AI-attached leader left the
# battlefield with its bodyguard for free — a live AI-vs-AI game put 7 of 11
# Custodes units and 1310 of 2000 points (65.5%) off the table under a cap of
# 50% — and, since the leader's status was never set to IN_RESERVES,
# MovementPhase.gd:3973 then refused to bring it in with its unit at all.
#
# Covers:
#   - the phase derives the riding leaders itself, so an AI-shaped action
#     (no attached_character_ids) is priced with them in BOTH caps;
#   - a declaration that busts the points cap only once the leader is counted
#     is rejected;
#   - CONFIRM puts the derived leaders in reserves with their bodyguard;
#   - attach-after-reserve cannot smuggle a leader past the caps;
#   - the AI's own budget matches the phase's, end to end: the real
#     FormationsPhase driven by the real AIDecisionMaker never lands over
#     either cap, and never proposes an action the phase rejects.
#
# Run with: godot --headless --path . -s tests/unit/test_reserves_half_army_cap.gd

# Nothing is preloaded — see tests/unit/test_ai_plan_deployment.gd for why.
const AIDM_PATH := "res://scripts/AIDecisionMaker.gd"
const FORMATIONS_PHASE_PATH := "res://phases/FormationsPhase.gd"

const STATUS_UNDEPLOYED := 0
const STATUS_IN_RESERVES := 7

# The armies the live repro used: custodes_lions is the one that went 65.5%
# over, orks carries dual-leader Boyz (two riders on one bodyguard).
const AI_ARMIES := ["custodes_lions", "orks"]
const FOE_ARMY := "space_marines"

var AIDM
var GS
var GSD
var ALM

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	create_timer(0.3).timeout.connect(_run)

func _run():
	print("\n=== Reserves 50%% cap applies to the AI ===\n")
	AIDM = load(AIDM_PATH)
	GS = get_root().get_node_or_null("GameState")
	ALM = get_root().get_node_or_null("ArmyListManager")
	GSD = load("res://autoloads/GameState.gd")
	if AIDM == null or GS == null or ALM == null:
		_assert(false, "AIDecisionMaker / GameState / ArmyListManager available at run time")
	else:
		test_ai_shaped_declaration_prices_its_leaders()
		test_confirm_reserves_the_derived_leaders()
		test_attach_after_reserve_respects_the_caps()
		await test_ai_never_exceeds_the_caps()
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

func _load_armies(ai_army: String, foe_army: String) -> bool:
	var a1 = ALM.load_army_for_game(foe_army, 1)
	var a2 = ALM.load_army_for_game(ai_army, 2)
	if a1.is_empty() or a2.is_empty():
		return false
	ALM.apply_army_to_game_state(a1, 1)
	ALM.apply_army_to_game_state(a2, 2)
	GS.state["meta"]["battle_round"] = 1
	GS.state["meta"]["phase"] = GSD.Phase.FORMATIONS
	for key in ["formations_p1_confirmed", "formations_p2_confirmed", "formations_declared"]:
		GS.state["meta"].erase(key)
	return true

func _new_phase() -> Node:
	var phase = load(FORMATIONS_PHASE_PATH).new()
	get_root().add_child(phase)
	phase.enter_phase(GS.create_snapshot(false))
	return phase

func _first_leader_pairing(player: int) -> Dictionary:
	"""A (character, bodyguard) pair the phase would accept, or {}."""
	var phase = _new_phase()
	GS.state["meta"]["active_player"] = player
	phase.current_declaring_player = player
	var out := {}
	for action in phase.get_available_actions():
		if action.get("type", "") == "DECLARE_LEADER_ATTACHMENT":
			out = {"character_id": action["character_id"], "bodyguard_id": action["bodyguard_id"]}
			break
	phase.queue_free()
	return out

func _reserved_totals(player: int) -> Dictionary:
	"""What is OFF THE TABLE because of a reserves declaration.

	Deliberately not just `status == IN_RESERVES`: the bug left an attached
	leader UNDEPLOYED while its bodyguard sat in reserves, which hid the
	overshoot from that measure exactly. A unit attached to a reserved
	bodyguard is off the table with it, whatever its status says."""
	var total_units := 0
	var total_points := 0
	var res_units := 0
	var res_points := 0
	for uid in GS.state["units"]:
		var unit = GS.state["units"][uid]
		if int(unit.get("owner", 0)) != player:
			continue
		var points = int(unit.get("meta", {}).get("points", 0))
		total_units += 1
		total_points += points
		var reserved := int(unit.get("status", 0)) == STATUS_IN_RESERVES
		if not reserved:
			var bodyguard_id = unit.get("attached_to", "")
			if bodyguard_id != null and str(bodyguard_id) != "":
				var bodyguard = GS.state["units"].get(str(bodyguard_id), {})
				reserved = int(bodyguard.get("status", 0)) == STATUS_IN_RESERVES
		if reserved:
			res_units += 1
			res_points += points
	return {
		"units": res_units, "total_units": total_units,
		"points": res_points, "total_points": total_points,
		"unit_pct": 100.0 * float(res_units) / float(max(1, total_units)),
		"point_pct": 100.0 * float(res_points) / float(max(1, total_points)),
	}

# ---------------------------------------------------------------------------

func test_ai_shaped_declaration_prices_its_leaders() -> void:
	print("\n-- an AI-shaped DECLARE_RESERVES is priced with its leaders --")
	if not _load_armies("custodes_lions", FOE_ARMY):
		_assert(false, "armies load")
		return
	var pairing := _first_leader_pairing(2)
	if pairing.is_empty():
		_assert(false, "the fixture army offers a leader attachment")
		return

	var phase = _new_phase()
	GS.state["meta"]["active_player"] = 2
	phase.current_declaring_player = 2
	var attach_ok: bool = phase.execute_action({
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": pairing.character_id,
		"bodyguard_id": pairing.bodyguard_id,
		"player": 2,
	}).get("success", false)
	_assert(attach_ok, "leader %s attached to %s" % [pairing.character_id, pairing.bodyguard_id])

	# The action the AI sends: no attached_character_ids at all.
	var declare := {
		"type": "DECLARE_RESERVES",
		"unit_id": pairing.bodyguard_id,
		"reserve_type": "strategic_reserves",
		"player": 2,
	}
	var validation: Dictionary = phase.validate_action(declare)
	_assert(validation.get("valid", false),
		"an under-cap AI declaration is still accepted (%s)" % str(validation.get("errors", [])))

	var leader_points = int(GS.get_unit(pairing.character_id).get("meta", {}).get("points", 0))
	_assert(leader_points > 0, "the attached leader is worth points (%d)" % leader_points)

	# Squeeze the cap to exactly the bodyguard's points: the declaration is
	# legal on the bodyguard alone and illegal once the leader is counted.
	var bodyguard_points = int(GS.get_unit(pairing.bodyguard_id).get("meta", {}).get("points", 0))
	var others: Array = []
	for uid in GS.state["units"]:
		var unit = GS.state["units"][uid]
		if int(unit.get("owner", 0)) != 2 or uid == pairing.bodyguard_id or uid == pairing.character_id:
			continue
		others.append(uid)
	# Total army points must be < 2 * (bodyguard + leader) and >= 2 * bodyguard.
	var target_total = 2 * bodyguard_points + leader_points  # cap = bodyguard + leader/2
	var filler = max(0, target_total - bodyguard_points - leader_points)
	var per_unit = int(filler / max(1, others.size()))
	for i in range(others.size()):
		var value = per_unit if i < others.size() - 1 else filler - per_unit * (others.size() - 1)
		GS.state["units"][others[i]]["meta"]["points"] = max(0, value)

	var tight: Dictionary = phase.validate_action(declare)
	var cap = int(GS.get_total_army_points(2) * 0.50)
	_assert(not tight.get("valid", true),
		"the same declaration is rejected once the leader's %d pts count (cap %d, unit %d) -> %s" % [
			leader_points, cap, bodyguard_points, str(tight.get("errors", []))])
	var mentions_points := false
	for err in tight.get("errors", []):
		if "points limit" in str(err):
			mentions_points = true
	_assert(mentions_points, "the rejection names the points cap")
	phase.queue_free()

func test_confirm_reserves_the_derived_leaders() -> void:
	print("\n-- CONFIRM sends the derived leaders into reserves too --")
	if not _load_armies("custodes_lions", FOE_ARMY):
		_assert(false, "armies load")
		return
	var pairing := _first_leader_pairing(2)
	if pairing.is_empty():
		_assert(false, "the fixture army offers a leader attachment")
		return

	var phase = _new_phase()
	GS.state["meta"]["active_player"] = 2
	phase.current_declaring_player = 2
	phase.execute_action({
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": pairing.character_id,
		"bodyguard_id": pairing.bodyguard_id,
		"player": 2,
	})
	var declared: bool = phase.execute_action({
		"type": "DECLARE_RESERVES",
		"unit_id": pairing.bodyguard_id,
		"reserve_type": "strategic_reserves",
		"player": 2,
	}).get("success", false)
	_assert(declared, "AI-shaped declaration accepted")

	# The count the caps see must include the rider, not just the bodyguard.
	_assert(phase._get_declared_reserves_count(2) == 2,
		"declared reserves count is 2 (bodyguard + rider), got %d" % phase._get_declared_reserves_count(2))

	# Formation changes only land when BOTH seats confirm; apply the diffs the
	# phase would emit so the resulting state can be inspected here.
	GS.apply_state_changes(phase._build_formation_changes())
	_assert(int(GS.get_unit(pairing.bodyguard_id).get("status", 0)) == STATUS_IN_RESERVES,
		"bodyguard is IN_RESERVES after confirm")
	_assert(int(GS.get_unit(pairing.character_id).get("status", 0)) == STATUS_IN_RESERVES,
		"the attached leader is IN_RESERVES too (was stranded UNDEPLOYED, so it never arrived)")
	phase.queue_free()

func test_attach_after_reserve_respects_the_caps() -> void:
	print("\n-- attach-after-reserve cannot smuggle a leader past the caps --")
	if not _load_armies("custodes_lions", FOE_ARMY):
		_assert(false, "armies load")
		return
	var pairing := _first_leader_pairing(2)
	if pairing.is_empty():
		_assert(false, "the fixture army offers a leader attachment")
		return

	var phase = _new_phase()
	GS.state["meta"]["active_player"] = 2
	phase.current_declaring_player = 2
	var declared: bool = phase.execute_action({
		"type": "DECLARE_RESERVES",
		"unit_id": pairing.bodyguard_id,
		"reserve_type": "strategic_reserves",
		"player": 2,
	}).get("success", false)
	_assert(declared, "bodyguard reserved first")

	# Now make the army so cheap that adding the leader's points busts the cap.
	var bodyguard_points = int(GS.get_unit(pairing.bodyguard_id).get("meta", {}).get("points", 0))
	for uid in GS.state["units"]:
		var unit = GS.state["units"][uid]
		if int(unit.get("owner", 0)) != 2 or uid == pairing.bodyguard_id or uid == pairing.character_id:
			continue
		unit["meta"]["points"] = 0
	GS.state["units"][pairing.character_id]["meta"]["points"] = max(1, bodyguard_points)

	var late: Dictionary = phase.validate_action({
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": pairing.character_id,
		"bodyguard_id": pairing.bodyguard_id,
		"player": 2,
	})
	_assert(not late.get("valid", true),
		"attaching to an already-reserved bodyguard is rejected when it busts the cap -> %s" % str(late.get("errors", [])))
	phase.queue_free()

func test_ai_never_exceeds_the_caps() -> void:
	print("\n-- the real AI, driving the real phase, stays inside both caps --")
	for ai_army in AI_ARMIES:
		if not _load_armies(ai_army, FOE_ARMY):
			_assert(false, "armies load (%s)" % ai_army)
			continue
		var phase = _new_phase()
		await create_timer(0.1).timeout
		GS.state["meta"]["active_player"] = 2
		phase.current_declaring_player = 2

		var rejected := ""
		var steps := 0
		while steps < 120:
			steps += 1
			var available: Array = phase.get_available_actions()
			if available.is_empty():
				break
			var decision: Dictionary = AIDM.decide(GSD.Phase.FORMATIONS, GS.create_snapshot(false), available, 2, 2)
			if decision.is_empty():
				break
			decision["player"] = 2
			var result: Dictionary = phase.execute_action(decision)
			if not result.get("success", false):
				# A warlord requirement is not a reserves rejection — satisfy it
				# and carry on; anything else is the failure this test is for.
				var errors := str(result.get("errors", []))
				if "Warlord" in errors or "warlord" in errors:
					var designated := false
					for action in available:
						if action.get("type", "") == "DESIGNATE_WARLORD":
							var pick = action.duplicate(true)
							pick["player"] = 2
							if phase.execute_action(pick).get("success", false):
								designated = true
								break
					if designated:
						continue
				rejected = "%s -> %s" % [decision.get("type", ""), errors]
				break
			if decision.get("type", "") == "CONFIRM_FORMATIONS":
				break

		_assert(rejected == "", "[%s] the AI never proposes an action the phase rejects (%s)" % [ai_army, rejected])
		GS.apply_state_changes(phase._build_formation_changes())
		var totals := _reserved_totals(2)
		_assert(totals.point_pct <= 50.0,
			"[%s] points off the table within the cap: %d/%d (%.1f%%)" % [
				ai_army, totals.points, totals.total_points, totals.point_pct])
		_assert(totals.unit_pct <= 50.0,
			"[%s] units off the table within the cap: %d/%d (%.1f%%)" % [
				ai_army, totals.units, totals.total_units, totals.unit_pct])
		phase.queue_free()
		await create_timer(0.1).timeout

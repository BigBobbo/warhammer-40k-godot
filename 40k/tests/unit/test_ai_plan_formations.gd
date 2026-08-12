extends SceneTree

# PM-2b — the AI consumes a plan's FORMATIONS sections: leader attachments,
# transport embarkations and reserves.
#
# Covers: each declaration is emitted in the phase's own order (attach, embark,
# reserve) and stops once the plan's list is satisfied; the plan's reserves list
# is the single source of truth, so the formula's own reserves evaluation is
# suppressed while a plan is active — including when the plan reserves NOTHING;
# an over-cap plan is trimmed deterministically in plan order and logged; and a
# reserve the FORMATIONS phase never got to declare (predeploy fixtures start at
# DEPLOYMENT with formations already confirmed) is retrofitted through
# DeploymentPhase's PLACE_IN_RESERVES safety net.
#
# PM-F5 — the formula's own embarkation pass must not overrule the plan: a unit
# the plan PLACES or RESERVES is not embarked, while a unit the plan does not
# mention still is. Carries a negative control, because the assertion is
# worthless unless the formula genuinely wanted to embark that unit.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_plan_formations.gd

# Nothing is preloaded — see tests/unit/test_ai_plan_deployment.gd for why.
const AIDM_PATH := "res://scripts/AIDecisionMaker.gd"
const RECON_STOMPS := "res://armies/recon_stomps.json"
const FIXTURE_RICH := "res://tests/fixtures/ai_plans/fixture_recon_stomps_rich.json"

const STATUS_UNDEPLOYED := 0
const STATUS_IN_RESERVES := 7

var AIDM

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	create_timer(0.2).timeout.connect(_run)

func _run():
	print("\n=== AI plan formations (PM-2b) Tests ===\n")
	AIDM = load(AIDM_PATH)
	if AIDM == null:
		_assert(false, "AIDecisionMaker loads at run time")
	else:
		_run_tests()
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

func _read_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK or not (json.data is Dictionary):
		return {}
	return json.data

func _make_snapshot(player: int = 1) -> Dictionary:
	var army := _read_json(RECON_STOMPS)
	var units := {}
	for unit_id in army.get("units", {}).keys():
		var unit: Dictionary = army["units"][unit_id].duplicate(true)
		unit["id"] = unit_id
		unit["owner"] = player
		unit["status"] = STATUS_UNDEPLOYED
		for model in unit.get("models", []):
			model["position"] = null
			model["alive"] = true
		# ArmyListManager derives transport_data from the TRANSPORT ability text
		# at load time (ArmyListManager.gd:234); reading the army JSON directly
		# skips that, and _evaluate_transport_embarkation ignores any transport
		# without it. Without this the formula can never embark anything here,
		# which would quietly make every embarkation assertion vacuous.
		var kws: Array = unit.get("meta", {}).get("keywords", [])
		if "TRANSPORT" in kws and not unit.has("transport_data"):
			unit["transport_data"] = {
				"capacity": 22,  # "transport capacity of 22 ORKS INFANTRY models"
				"capacity_keywords": ["ORKS", "INFANTRY"],
				"capacity_multipliers": {},
				"excluded_keywords": [],
				"embarked_units": [],
				"firing_deck": 0,
			}
		units[unit_id] = unit
	return {
		"meta": {"deployment_type": "hammer_anvil", "battle_round": 1, "phase": 0},
		"board": {"size": {"width": 44, "height": 60}, "deployment_zones": [], "terrain_features": []},
		"factions": {str(player): {"name": "Orks", "detachment": "Speedwaaagh!"}},
		"units": units,
	}

func _formations_actions(snapshot: Dictionary, player: int, declared: Dictionary) -> Array:
	"""Rebuild the phase's available actions, minus whatever is already declared
	— mirroring FormationsPhase.get_available_actions (:1160-1240)."""
	var actions: Array = []
	for unit_id in snapshot["units"].keys():
		var unit = snapshot["units"][unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		var keywords: Array = unit.get("meta", {}).get("keywords", [])
		if declared.get("attached", []).has(unit_id) or declared.get("embarked", []).has(unit_id) \
				or declared.get("reserved", []).has(unit_id):
			continue
		if "CHARACTER" in keywords:
			for bodyguard_id in snapshot["units"].keys():
				var bg = snapshot["units"][bodyguard_id]
				if int(bg.get("owner", 0)) != player or bodyguard_id == unit_id:
					continue
				if "CHARACTER" in bg.get("meta", {}).get("keywords", []):
					continue
				actions.append({
					"type": "DECLARE_LEADER_ATTACHMENT",
					"character_id": unit_id,
					"bodyguard_id": bodyguard_id,
					"player": player,
				})
		if "TRANSPORT" in keywords:
			actions.append({"type": "DECLARE_TRANSPORT_EMBARKATION", "transport_id": unit_id, "player": player})
		actions.append({"type": "DECLARE_RESERVES", "unit_id": unit_id,
			"reserve_type": "strategic_reserves", "player": player})
	actions.append({"type": "CONFIRM_FORMATIONS", "player": player})
	return actions

# ---------------------------------------------------------------------------

func _run_tests() -> void:
	test_declarations_in_order()
	test_plan_owns_reserves()
	test_over_cap_reserves_are_trimmed()
	test_post_formations_retrofit()
	test_placed_units_are_not_embarked_by_formula()

func test_declarations_in_order() -> void:
	var plan := _read_json(FIXTURE_RICH)
	_assert(not plan.is_empty(), "rich fixture plan loads")
	var snapshot := _make_snapshot(1)
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, plan)

	var declared := {"attached": [], "embarked": [], "reserved": []}

	# Expectations come from the plan itself, not from hardcoded ids — the
	# fixture's attachment has to name a pairing the game can actually make
	# (only the Deffkilla Wartrike leads Warbikers in
	# data/40kdc/leaderAttachments.json), and that is a property of the data.
	var want_attach: Dictionary = plan["deployment"]["attachments"][0]
	var want_embark: Dictionary = plan["deployment"]["embarkations"][0]

	# 1. Attachment first.
	var d1: Dictionary = AIDM._decide_formations(snapshot, _formations_actions(snapshot, 1, declared), 1)
	_assert(str(d1.get("type", "")) == "DECLARE_LEADER_ATTACHMENT",
		"the first plan declaration is the leader attachment (got %s)" % d1.get("type", ""))
	_assert(str(d1.get("character_id", "")) == str(want_attach["character"]) and str(d1.get("bodyguard_id", "")) == str(want_attach["bodyguard"]),
		"…the pairing the plan asked for (%s -> %s)" % [d1.get("character_id", ""), d1.get("bodyguard_id", "")])
	_assert(str(d1.get("_ai_description", "")).find("from plan") != -1, "…and it says it came from the plan")
	declared["attached"].append(str(want_attach["character"]))

	# 2. Embarkation next.
	var d2: Dictionary = AIDM._decide_formations(snapshot, _formations_actions(snapshot, 1, declared), 1)
	_assert(str(d2.get("type", "")) == "DECLARE_TRANSPORT_EMBARKATION",
		"the second plan declaration is the embarkation (got %s)" % d2.get("type", ""))
	_assert(str(d2.get("transport_id", "")) == str(want_embark["transport"]) and d2.get("unit_ids", []).has(str(want_embark["unit"])),
		"…the passenger the plan asked for (%s <- %s)" % [d2.get("transport_id", ""), str(d2.get("unit_ids", []))])
	declared["embarked"].append(str(want_embark["unit"]))

	# 3. Reserves, in plan order.
	var expected_reserves: Array = []
	for entry in plan["deployment"]["reserves"]:
		expected_reserves.append(str(entry["unit"]))
	for i in range(expected_reserves.size()):
		var d: Dictionary = AIDM._decide_formations(snapshot, _formations_actions(snapshot, 1, declared), 1)
		_assert(str(d.get("type", "")) == "DECLARE_RESERVES",
			"plan reserve %d is declared (got %s)" % [i + 1, d.get("type", "")])
		_assert(str(d.get("unit_id", "")) == expected_reserves[i],
			"…in plan order: expected %s, got %s" % [expected_reserves[i], d.get("unit_id", "")])
		declared["reserved"].append(str(d.get("unit_id", "")))

	# 4. Plan satisfied -> the plan pass stops and existing logic takes over.
	var d5: Dictionary = AIDM._decide_formations(snapshot, _formations_actions(snapshot, 1, declared), 1)
	_assert(str(d5.get("_ai_description", "")).find("from plan") == -1,
		"once the plan's declarations are made, the plan pass stops (got '%s')" % d5.get("_ai_description", ""))
	_assert(str(d5.get("type", "")) != "DECLARE_RESERVES",
		"…and no further reserves are declared, because the plan's list is the single source of truth")

func test_plan_owns_reserves() -> void:
	var snapshot := _make_snapshot(1)
	var declared := {"attached": [], "embarked": [], "reserved": []}

	# A plan whose reserves list is EMPTY is a positive statement: reserve
	# nothing. It must still suppress the formula's own reserves evaluation.
	var plan := _read_json(FIXTURE_RICH)
	plan["deployment"]["reserves"] = []
	plan["deployment"]["embarkations"] = []
	plan["deployment"]["attachments"] = []
	plan["earmarks"] = []
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, plan)
	_assert(AIDM._plan_owns_reserves(plan), "a plan with an empty reserves list still OWNS reserves")

	var with_plan: Dictionary = AIDM._decide_formations(snapshot, _formations_actions(snapshot, 1, declared), 1)
	_assert(str(with_plan.get("type", "")) != "DECLARE_RESERVES",
		"…so the AI declares no reserves of its own (got %s)" % with_plan.get("type", ""))

	# A plan with no reserves KEY leaves reserves to the existing logic.
	var no_key := _read_json(FIXTURE_RICH)
	no_key["deployment"].erase("reserves")
	_assert(not AIDM._plan_owns_reserves(no_key), "a plan with no reserves key does NOT own reserves")
	_assert(not AIDM._plan_owns_reserves({}), "no plan at all does not own reserves")

func test_over_cap_reserves_are_trimmed() -> void:
	var snapshot := _make_snapshot(1)
	var plan := _read_json(FIXTURE_RICH)
	# recon_stomps is 2000 pts over 17 units -> caps are 1000 pts / 8 units.
	# The Stompa alone is 600; adding the 140-pt Deffkoptas and both 120-pt
	# Warbiker squads pushes past the points cap partway through the list.
	plan["deployment"]["reserves"] = [
		{"unit": "U_STOMPA_A", "arrival_round": 2},
		{"unit": "U_DEFFKOPTAS_A", "arrival_round": 2},
		{"unit": "U_WARBIKERS_C", "arrival_round": 2},
		{"unit": "U_WARBIKERS_D", "arrival_round": 3},
		{"unit": "U_DEFFKOPTAS_B", "arrival_round": 3},
	]
	plan["deployment"]["attachments"] = []
	plan["earmarks"] = []

	var chosen: Array = AIDM._plan_reserve_units(plan, snapshot, 1)
	var points := 0
	for entry in chosen:
		points += int(snapshot["units"][str(entry["unit"])]["meta"]["points"])
	_assert(points <= 1000, "trimmed reserves stay inside the 50%% points cap (%d <= 1000)" % points)
	_assert(chosen.size() < 5, "…by dropping entries, not by keeping them all (%d of 5)" % chosen.size())
	_assert(chosen.size() > 0, "…while still reserving what fits")
	var order_ok := true
	for i in range(chosen.size()):
		if str(chosen[i]["plan_unit"]) != str(plan["deployment"]["reserves"][i]["unit"]):
			order_ok = false
	_assert(order_ok, "…trimming from the END of the plan's order, so the trim is deterministic")

	# The unit cap bites too: 17 units -> at most 8 reserve entries.
	var many := _read_json(FIXTURE_RICH)
	many["deployment"]["attachments"] = []
	many["earmarks"] = []
	var cheap: Array = []
	for unit_id in ["U_STORMBOYZ_A", "U_STORMBOYZ_B", "U_STORMBOYZ_C", "U_STORMBOYZ_D",
			"U_GRETCHIN_A", "U_GRETCHIN_B", "U_MEK_A", "U_WARBIKERS_A", "U_WARBIKERS_B"]:
		cheap.append({"unit": unit_id, "arrival_round": 2})
	many["deployment"]["reserves"] = cheap
	var trimmed: Array = AIDM._plan_reserve_units(many, snapshot, 1)
	_assert(trimmed.size() == 8, "the 50%% unit cap trims 9 cheap reserves to 8 (got %d)" % trimmed.size())

func test_post_formations_retrofit() -> void:
	# Predeploy fixtures start at DEPLOYMENT with formations already confirmed,
	# so the declaration path never runs; PLACE_IN_RESERVES is the way in.
	var plan := _read_json(FIXTURE_RICH)
	var snapshot := _make_snapshot(1)
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, plan)

	var pending: Array = AIDM.plan_post_formations_reserves(plan, snapshot, 1)
	_assert(pending.size() == 2, "both plan reserves are still pending while undeployed (got %d)" % pending.size())

	var deploy_actions := [
		{"type": "DEPLOY_UNIT", "unit_id": "U_STORMBOYZ_B"},
		{"type": "DEPLOY_UNIT", "unit_id": "U_DEFFKOPTAS_A"},
	]
	var decision: Dictionary = AIDM._plan_deployment_reserve_action(plan, deploy_actions, 1, snapshot)
	_assert(str(decision.get("type", "")) == "PLACE_IN_RESERVES",
		"a plan reserve is retrofitted through PLACE_IN_RESERVES (got %s)" % decision.get("type", ""))
	_assert(str(decision.get("unit_id", "")) == "U_STORMBOYZ_B", "…the first one in plan order")
	_assert(str(decision.get("_ai_description", "")).find("from plan") != -1, "…and it says it came from the plan")

	# Once a unit is actually in reserves it stops being pending.
	snapshot["units"]["U_STORMBOYZ_B"]["status"] = STATUS_IN_RESERVES
	pending = AIDM.plan_post_formations_reserves(plan, snapshot, 1)
	_assert(pending.size() == 1, "an already-reserved unit drops out of the pending list (got %d)" % pending.size())

	# And a unit the plan does not reserve is never retrofitted.
	var other := [{"type": "DEPLOY_UNIT", "unit_id": "U_GRETCHIN_A"}]
	_assert(AIDM._plan_deployment_reserve_action(plan, other, 1, snapshot).is_empty(),
		"a unit the plan does not reserve is not placed in reserves")

	AIDM.clear_all_plans()

func _drive_formations(player: int, plan: Dictionary) -> Array:
	"""Run FORMATIONS to completion the way the phase does — decide, apply the
	declaration, offer the reduced action list again — and return every
	declaration made, in order."""
	var snapshot := _make_snapshot(player)
	AIDM.clear_all_plans()
	if not plan.is_empty():
		AIDM.set_player_plan(player, plan)

	var declared := {"attached": [], "embarked": [], "reserved": []}
	var made: Array = []
	var seen := {}
	# The real phase stops at CONFIRM_FORMATIONS; the bound is a guard against a
	# decision loop, not an expected exit.
	#
	# A repeat is treated as "no further progress" rather than as another
	# declaration: FormationsPhase records an embarkation in player_formations
	# (:565-573) and only writes it onto the unit at CONFIRM (:973), so the
	# snapshot the AI scores against never shows it, and the AI is free to offer
	# the same one again. Counting repeats would inflate every embarkation
	# assertion below.
	for _i in range(40):
		var d: Dictionary = AIDM._decide_formations(snapshot, _formations_actions(snapshot, player, declared), player)
		var t := str(d.get("type", ""))
		if t.is_empty() or t == "CONFIRM_FORMATIONS":
			break
		var key := "%s|%s|%s|%s" % [t, str(d.get("character_id", "")), str(d.get("transport_id", "")) + str(d.get("unit_ids", [])), str(d.get("unit_id", ""))]
		if seen.has(key):
			break
		seen[key] = true
		made.append(d)
		match t:
			"DECLARE_LEADER_ATTACHMENT":
				declared["attached"].append(str(d.get("character_id", "")))
			"DECLARE_TRANSPORT_EMBARKATION":
				for uid in d.get("unit_ids", []):
					declared["embarked"].append(str(uid))
			"DECLARE_RESERVES":
				declared["reserved"].append(str(d.get("unit_id", "")))
			_:
				# DESIGNATE_WARLORD and anything else declares nothing that
				# changes the action list — stop rather than spin.
				made.pop_back()
				break
	return made

func _embarked_units(declarations: Array) -> Array:
	var out: Array = []
	for d in declarations:
		if str(d.get("type", "")) != "DECLARE_TRANSPORT_EMBARKATION":
			continue
		for uid in d.get("unit_ids", []):
			out.append(str(uid))
	return out

func test_placed_units_are_not_embarked_by_formula() -> void:
	# PM-F5. The rich fixture PLACES U_GRETCHIN_A on the board and EMBARKS
	# U_GRETCHIN_B in the Stompa — the two halves of the same decision. The bug
	# was that the formula's own embarkation pass ran anyway and put the PLACED
	# one in the Stompa too; an embarked unit never deploys, so the plan's
	# coordinates for it were silently discarded.
	var plan := _read_json(FIXTURE_RICH)
	_assert(not plan.is_empty(), "rich fixture plan loads")
	_assert(not AIDM._plan_placement_for(plan, "U_GRETCHIN_A", 1, _make_snapshot(1)).is_empty(),
		"the fixture does place U_GRETCHIN_A (the test would be vacuous otherwise)")

	# NEGATIVE CONTROL FIRST: with no plan at all, does the formula actually
	# want to embark U_GRETCHIN_A? If it does not, the assertion below proves
	# nothing and this test is worthless.
	#
	# clear_all_plans() is NOT enough to mean "no plan": _resolve_plan_for falls
	# through to an auto-match, and since PM-10 shipped a hammer_anvil Ork plan
	# this snapshot matches one. PLANS_ENABLED=0 is the only gate that stops
	# every plan consumer, auto-match included.
	AIDM._config_overrides["PLANS_ENABLED"] = 0
	var formula_only := _embarked_units(_drive_formations(1, {}))
	AIDM._config_overrides.erase("PLANS_ENABLED")
	_assert(formula_only.has("U_GRETCHIN_A"),
		"CONTROL: with no plan, the formula does embark U_GRETCHIN_A (got %s) — so suppressing it is a real change" % str(formula_only))

	# With the plan in force, the placed unit stays on the board and only the
	# unit the plan named goes inside.
	var with_plan := _embarked_units(_drive_formations(1, plan))
	_assert(not with_plan.has("U_GRETCHIN_A"),
		"a unit the plan PLACES is not embarked by the formula (embarked: %s)" % str(with_plan))
	_assert(with_plan.has("U_GRETCHIN_B"),
		"…while the embarkation the plan DID ask for still happens (embarked: %s)" % str(with_plan))

	# Every embarkation made under a plan must be one the plan asked for.
	var plan_embarks: Array = []
	for entry in plan["deployment"]["embarkations"]:
		plan_embarks.append(str(entry["unit"]))
	var unasked: Array = []
	for uid in with_plan:
		if not plan_embarks.has(uid):
			unasked.append(uid)
	_assert(unasked.is_empty(),
		"no unit is embarked that the plan did not ask for (unasked: %s)" % str(unasked))

	# A unit the plan does not mention at all is still the formula's to decide,
	# exactly as deployment order already works.
	var partial := _read_json(FIXTURE_RICH)
	var kept: Array = []
	for p in partial["deployment"]["placements"]:
		if str(p.get("unit", "")) != "U_GRETCHIN_A":
			kept.append(p)
	partial["deployment"]["placements"] = kept
	partial["deployment"]["embarkations"] = []
	_assert(AIDM._plan_placement_for(partial, "U_GRETCHIN_A", 1, _make_snapshot(1)).is_empty(),
		"the trimmed plan no longer places U_GRETCHIN_A")
	var unmentioned := _embarked_units(_drive_formations(1, partial))
	_assert(unmentioned.has("U_GRETCHIN_A"),
		"a unit the plan does not mention is still embarkable by the formula (embarked: %s)" % str(unmentioned))

	AIDM.clear_all_plans()

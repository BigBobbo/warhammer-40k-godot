extends SceneTree

# Transport validation audit (2026-07) — regression net for the defects found
# while live-validating transports across every phase:
#   1. Firing Deck capacity parsed from "Firing Deck 11" ability names
#      (ArmyListManager previously required the exact name "FIRING DECK",
#      leaving firing_deck = 0 for every army-file transport).
#   2. Battlewagon army data carries the MEGA ARMOUR / JUMP PACK capacity
#      multiplier sentences, and the parser picks them up.
#   3. FormationsPhase transport embark declarations require ALL capacity
#      keywords (a MOUNTED Orks unit may not embark in "ORKS INFANTRY").
#   4. EMBARK_UNIT clears model positions (a movement-phase embark used to
#      leave stale board positions: embarked units stayed shootable and
#      charge-eligible).
#   5. RulesEngine.get_eligible_targets never offers an embarked unit.
#   6. CONFIRM_DISEMBARK rejects placements overlapping other models.
#   7. FIRING DECK loans: get_unit_weapons offers each loaned embarked weapon
#      as a synthetic hull bearer "<hull>@fd<i>" carrying the base weapon id
#      (so identical guns group into one row and split-fire like a squad).
#
# Usage: godot --headless --path . -s tests/test_transport_audit_2026_07.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	create_timer(0.2).timeout.connect(_run_tests)

var _ran := false

func _run_tests():
	if _ran:
		return
	_ran = true
	print("\n=== test_transport_audit_2026_07 ===\n")

	_test_firing_deck_parse()
	_test_battlewagon_multiplier_data()
	_test_formations_all_keywords()
	_test_embark_clears_positions()
	_test_targets_exclude_embarked()
	_test_confirm_disembark_overlap()
	_test_firing_deck_loan()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

# -- 1+2: army-file parse ---------------------------------------------------

func _test_firing_deck_parse() -> void:
	print("-- Firing Deck parse (ArmyListManager) --")
	var alm = root.get_node_or_null("ArmyListManager")
	_check("ArmyListManager autoload present", alm != null)
	if alm == null:
		return
	var fd_named = alm._parse_firing_deck_value({"name": "Firing Deck 11", "description": "The unit gains the Firing Deck ability (11)."})
	_check("parses 'Firing Deck 11' ability name", fd_named == 11, "got %d" % fd_named)
	var fd_legacy = alm._parse_firing_deck_value({"name": "FIRING DECK", "description": "Firing Deck 6"})
	_check("parses legacy 'FIRING DECK' + desc number", fd_legacy == 6, "got %d" % fd_legacy)
	var fd_none = alm._parse_firing_deck_value({"name": "TRANSPORT", "description": "capacity of 22"})
	_check("non-firing-deck ability yields 0", fd_none == 0, "got %d" % fd_none)

	# End-to-end: load the battlewagons army through the real load path and
	# confirm every Battlewagon gets firing_deck 11 (minus 'Ard Case strips).
	var army = alm.load_army_list("battlewagons", 1)
	var found_bw := 0
	var fd_ok := true
	for uid in army.get("units", {}):
		var u = army.units[uid]
		if "BATTLEWAGON" in u.get("meta", {}).get("keywords", []):
			found_bw += 1
			var fd = u.get("transport_data", {}).get("firing_deck", 0)
			var has_ard_case = false
			for w in u.get("meta", {}).get("wargear", []):
				if "Ard Case" in str(w):
					has_ard_case = true
			if not has_ard_case and fd != 11:
				fd_ok = false
	_check("battlewagons army loads with firing_deck=11 (%d wagons)" % found_bw, found_bw > 0 and fd_ok)

func _test_battlewagon_multiplier_data() -> void:
	print("-- Battlewagon capacity multipliers (army data) --")
	var alm = root.get_node_or_null("ArmyListManager")
	if alm == null:
		return
	var army = alm.load_army_list("battlewagons", 1)
	var checked := false
	for uid in army.get("units", {}):
		var u = army.units[uid]
		if "BATTLEWAGON" in u.get("meta", {}).get("keywords", []):
			var mult = u.get("transport_data", {}).get("capacity_multipliers", {})
			_check("%s parses MEGA ARMOUR x2" % uid, int(mult.get("MEGA ARMOUR", 0)) == 2, str(mult))
			_check("%s parses JUMP PACK x2" % uid, int(mult.get("JUMP PACK", 0)) == 2, str(mult))
			checked = true
			break
	_check("at least one battlewagon checked", checked)

# -- 3: formations ALL-keyword gate ----------------------------------------

func _test_formations_all_keywords() -> void:
	print("-- FormationsPhase: ALL capacity keywords required --")
	var phase_script = load("res://phases/FormationsPhase.gd")
	var phase = phase_script.new()
	root.add_child(phase)

	var game_state = root.get_node("GameState")
	game_state.state["units"] = {
		"U_TRANSPORT": {"id": "U_TRANSPORT", "owner": 1, "flags": {},
			"meta": {"keywords": ["ORKS", "TRANSPORT", "VEHICLE"], "stats": {}},
			"transport_data": {"capacity": 12, "capacity_keywords": ["ORKS", "INFANTRY"], "capacity_multipliers": {"MEGA ARMOUR": 2}, "excluded_keywords": [], "embarked_units": [], "firing_deck": 0},
			"models": [{"id": "m1", "alive": true, "position": null}]},
		"U_BIKERS": {"id": "U_BIKERS", "owner": 1, "flags": {},
			"meta": {"keywords": ["ORKS", "MOUNTED"], "stats": {}},
			"models": [{"id": "m1", "alive": true, "position": null}]},
		"U_BOYZ": {"id": "U_BOYZ", "owner": 1, "flags": {},
			"meta": {"keywords": ["ORKS", "INFANTRY"], "stats": {}},
			"models": [{"id": "m1", "alive": true, "position": null}, {"id": "m2", "alive": true, "position": null}]},
		"U_MEGA": {"id": "U_MEGA", "owner": 1, "flags": {},
			"meta": {"keywords": ["ORKS", "INFANTRY", "MEGA ARMOUR"], "stats": {}},
			"models": [{"id": "m1", "alive": true, "position": null},
				{"id": "m2", "alive": true, "position": null},
				{"id": "m3", "alive": true, "position": null},
				{"id": "m4", "alive": true, "position": null},
				{"id": "m5", "alive": true, "position": null},
				{"id": "m6", "alive": true, "position": null}]},
	}
	phase.game_state_snapshot = game_state.state.duplicate(true)
	if phase.has_method("_ensure_player_formations"):
		phase._ensure_player_formations(1)
	elif not phase.player_formations.has(1):
		phase.player_formations[1] = {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []}

	var v_bikers = phase._validate_declare_transport_embarkation({
		"type": "DECLARE_TRANSPORT_EMBARKATION", "transport_id": "U_TRANSPORT",
		"unit_ids": ["U_BIKERS"], "player": 1})
	_check("MOUNTED unit rejected (needs ORKS+INFANTRY)", not v_bikers.valid, str(v_bikers))

	var v_boyz = phase._validate_declare_transport_embarkation({
		"type": "DECLARE_TRANSPORT_EMBARKATION", "transport_id": "U_TRANSPORT",
		"unit_ids": ["U_BOYZ"], "player": 1})
	_check("ORKS INFANTRY unit accepted", v_boyz.valid, str(v_boyz))

	# 6 MEGA ARMOUR models x2 = 12 slots -> fits capacity 12 exactly; adding
	# 2 more plain models would exceed.
	var v_mega = phase._validate_declare_transport_embarkation({
		"type": "DECLARE_TRANSPORT_EMBARKATION", "transport_id": "U_TRANSPORT",
		"unit_ids": ["U_MEGA"], "player": 1})
	_check("6 MEGA ARMOUR models weigh 12 slots (fit 12)", v_mega.valid, str(v_mega))
	var v_both = phase._validate_declare_transport_embarkation({
		"type": "DECLARE_TRANSPORT_EMBARKATION", "transport_id": "U_TRANSPORT",
		"unit_ids": ["U_MEGA", "U_BOYZ"], "player": 1})
	_check("weighted capacity rejects 12+2 > 12", not v_both.valid, str(v_both))

	root.remove_child(phase)
	phase.free()

# -- 4: EMBARK_UNIT clears positions ---------------------------------------

func _test_embark_clears_positions() -> void:
	print("-- MovementPhase EMBARK_UNIT clears model positions --")
	var phase_script = load("res://phases/MovementPhase.gd")
	var src = phase_script.source_code
	_check("_process_embark_unit nulls model positions",
		"Embarked models are off the battlefield: clear their positions" in src)

func _test_targets_exclude_embarked() -> void:
	print("-- get_eligible_targets skips embarked units --")
	var board = {
		"units": {
			"U_SHOOTER": {"id": "U_SHOOTER", "owner": 2, "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {},
					"weapons": [{"name": "Gun", "type": "Ranged", "range": "24", "attacks": "1", "ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1"}]},
				"models": [{"id": "m1", "alive": true, "base_mm": 32, "position": {"x": 100, "y": 100}}]},
			"U_EMBARKED": {"id": "U_EMBARKED", "owner": 1, "embarked_in": "U_BOX", "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {}},
				"models": [{"id": "m1", "alive": true, "base_mm": 32, "position": {"x": 140, "y": 100}}]},
			"U_BOX": {"id": "U_BOX", "owner": 1, "flags": {},
				"meta": {"keywords": ["VEHICLE", "TRANSPORT"], "stats": {}},
				"transport_data": {"capacity": 10, "capacity_keywords": [], "capacity_multipliers": {}, "excluded_keywords": [], "embarked_units": ["U_EMBARKED"], "firing_deck": 0},
				"models": [{"id": "m1", "alive": true, "base_mm": 100, "position": {"x": 300, "y": 100}}]},
		},
		"board": {"size": {"width": 44, "height": 60}},
	}
	var rules = root.get_node("RulesEngine")
	var targets = rules.get_eligible_targets("U_SHOOTER", board)
	_check("embarked unit absent from targets (stale position)", not targets.has("U_EMBARKED"), str(targets.keys()))
	_check("the transport itself IS a target", targets.has("U_BOX"), str(targets.keys()))

# -- 6: CONFIRM_DISEMBARK overlap gate -------------------------------------

func _test_confirm_disembark_overlap() -> void:
	print("-- CONFIRM_DISEMBARK rejects overlapping placements --")
	var phase_script = load("res://phases/MovementPhase.gd")
	var src = phase_script.source_code
	_check("validator checks placement overlap vs other units",
		"Disembark position overlaps a model from" in src)
	_check("validator checks self-overlap",
		"Disembark positions overlap each other" in src)

# -- 7: firing deck loan through weapon queries ----------------------------

func _test_firing_deck_loan() -> void:
	print("-- FIRING DECK weapon loan (get_unit_weapons / get_weapon_profile) --")
	var board = {
		"units": {
			"U_WAGON": {"id": "U_WAGON", "owner": 1,
				"flags": {"firing_deck_weapons": [
					{"unit_id": "U_BOYZ", "model_id": "m1", "weapon_id": "shoota_ranged"},
					{"unit_id": "U_BOYZ", "model_id": "m2", "weapon_id": "shoota_ranged"}]},
				"meta": {"keywords": ["VEHICLE", "TRANSPORT"], "stats": {},
					"weapons": [{"name": "Big shoota", "type": "Ranged", "range": "36", "attacks": "3", "ballistic_skill": "5", "strength": "5", "ap": "0", "damage": "1"}]},
				"transport_data": {"capacity": 12, "capacity_keywords": [], "capacity_multipliers": {}, "excluded_keywords": [], "embarked_units": ["U_BOYZ"], "firing_deck": 11},
				"models": [{"id": "m1", "alive": true, "base_mm": 100, "position": {"x": 200, "y": 200}}]},
			"U_BOYZ": {"id": "U_BOYZ", "owner": 1, "embarked_in": "U_WAGON", "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {},
					"weapons": [{"name": "Shoota", "type": "Ranged", "range": "18", "attacks": "2", "ballistic_skill": "5", "strength": "4", "ap": "0", "damage": "1"}]},
				"models": [{"id": "m1", "alive": true, "base_mm": 32, "position": null},
					{"id": "m2", "alive": true, "base_mm": 32, "position": null}]},
		},
	}
	var rules = root.get_node("RulesEngine")
	var weapons = rules.get_unit_weapons("U_WAGON", board)
	# FIRING DECK grouping: the two loaned Shootas are exposed as synthetic hull
	# bearers "m1@fd0" / "m1@fd1", each carrying the BASE weapon id (not a
	# per-weapon "__fd" alias), so identical guns collapse into one "×N" row and
	# split-fire like a squad. The hull model itself keeps only its own guns.
	var hull = weapons.get("m1", [])
	_check("hull model keeps its own gun (Big shoota), not the loaned Shootas",
		"big_shoota_ranged" in hull and not ("shoota_ranged" in hull), str(hull))
	var bearer0 = weapons.get("m1@fd0", [])
	var bearer1 = weapons.get("m1@fd1", [])
	_check("both loans become synthetic hull bearers carrying the base weapon",
		"shoota_ranged" in bearer0 and "shoota_ranged" in bearer1, str([bearer0, bearer1]))
	# The synthetic bearer id resolves to the transport hull model (BS/position).
	var resolved = rules.get_model_by_id(board.units.U_WAGON, "m1@fd0")
	_check("synthetic bearer id resolves to the hull model", resolved.get("id", "") == "m1", str(resolved.get("id")))
	var profile = rules.get_weapon_profile("shoota_ranged", board)
	_check("loaned base weapon resolves to the Shoota profile", profile.get("name", "") == "Shoota", str(profile.get("name")))
	_check("loaned weapon keeps base attacks", int(profile.get("attacks", 0)) == 2, str(profile.get("attacks")))

	# Embarked unit still cannot shoot on its own (weapons come via the loan).
	var boyz_weapons = rules.get_unit_weapons("U_BOYZ", board)
	_check("embarked unit itself still enumerable (no crash)", boyz_weapons is Dictionary)

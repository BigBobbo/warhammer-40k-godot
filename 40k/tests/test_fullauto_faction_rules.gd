extends SceneTree

# Full-auto faction rules regression test (Orks + Adeptus Custodes audit).
#
# Covers the engine half of the "every Ork/Custodes rule is mechanically
# implemented" work:
#   1. Army load pipeline: wargear stat bonuses apply from type "Datasheet"
#      abilities ('Ard Case +2T / Firing Deck removal, Praesidium Shield +1W)
#      and renamed 11e abilities are canonicalized (Da Jump, Ramshackle).
#   2. Faction stratagems: all 6 War Horde + all 6 Shield Host stratagems load
#      mechanically implemented from the curated effects_json.
#   3. Defender-side modifiers: 'ARD AS NAILS (-1 wound vs the flagged unit,
#      ranged + melee) and UNWAVERING SENTINELS (-1 hit vs the flagged unit,
#      melee only — must NOT leak into ranged).
#   4. Blastajet Force Field: always-on ability applies effect_invuln 4.
#   5. Devoted to Destruction: melee-only +2 Attacks (fight phase flag).
#   6. Sneaky Gitz: unit excluded from Fire Overwatch eligibility.
#   7. Bodyguard: second leader-role attachment allowed, third rejected.
#   8. Admonimortis: DORMANT (no 11e rule in the 40kdc dataset) — pinned off.
#   9. StateSerializer 1.2.0 -> 1.3.0 migration canonicalizes ability names.
#
# The windowed analogues live in tests/scenarios/sp/fullauto_*.json.
#
# Usage: godot --headless --path . -s tests/test_fullauto_faction_rules.gd

var passed := 0
var failed := 0

const ATTACKS = 80

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

# ----------------------------------------------------------------------------
# Board factory (mirrors test_stealth_keyword_pipeline.gd)
# ----------------------------------------------------------------------------
func _make_board(target_flags: Dictionary = {}, distance_inches: float = 2.0) -> Dictionary:
	var px_per_inch = 40.0
	var target_distance_px = distance_inches * px_per_inch
	var shooter_models = []
	for i in range(4):
		shooter_models.append({
			"id": "ms%d" % i,
			"position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	var target_models = []
	for i in range(8):
		target_models.append({
			"id": "mt%d" % i,
			"position": {"x": target_distance_px, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 4}
		})
	return {
		"units": {
			"U_SHOOTER": {
				"id": "U_SHOOTER", "owner": 1,
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}, "abilities": []},
				"flags": {},
				"models": shooter_models
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2,
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}, "abilities": []},
				"flags": target_flags,
				"models": target_models
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1}
	}

func _shoot(board: Dictionary, seed_val: int) -> Dictionary:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {
		"type": "SHOOT",
		"actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "bolt_rifle",
			"target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1", "ms2", "ms3"],
			"attacks_override": ATTACKS
		}]}
	}
	return rules.resolve_shoot(action, board, rng)

func _melee(board: Dictionary, seed_val: int) -> Dictionary:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	# lance_melee is the registered melee test profile used by
	# test_stealth_keyword_pipeline.gd; omit `models` so the engine picks all
	# eligible models in engagement range.
	var action := {
		"type": "FIGHT",
		"actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"attacker": "U_SHOOTER",
			"target": "U_TARGET",
			"weapon": "lance_melee"
		}]}
	}
	return rules.resolve_melee_attacks(action, board, rng)

func _count_successes(result: Dictionary, context_substr: String) -> int:
	var total := 0
	for d in result.get("dice", []):
		if context_substr in str(d.get("context", "")):
			total += int(d.get("successes", -1)) if d.has("successes") else 0
	return total

func _sum_wounds_from_dice(result: Dictionary) -> int:
	# Count successful wound rolls across dice records whose context mentions wound
	var total := 0
	for d in result.get("dice", []):
		var ctx = str(d.get("context", "")).to_lower()
		if "wound" in ctx and d.has("successes"):
			total += int(d.get("successes", 0))
	return total

func _sum_hits_from_dice(result: Dictionary) -> int:
	var total := 0
	for d in result.get("dice", []):
		var ctx = str(d.get("context", "")).to_lower()
		if ("hit" in ctx or "to_hit" in ctx) and d.has("successes"):
			total += int(d.get("successes", 0))
	return total

# ----------------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------------

func _test_army_load_pipeline() -> void:
	print("\n-- Army load pipeline: wargear bonuses + name canonicalization --")
	var alm = root.get_node("ArmyListManager")

	var orks = alm.load_army_list("orks", 1)
	_check("orks army loads", not orks.is_empty())
	var bw = orks.get("units", {}).get("U_BATTLEWAGON_G", {})
	_check("Battlewagon T12 ('Ard Case +2)", int(bw.get("meta", {}).get("stats", {}).get("toughness", 0)) == 12,
		"got %s" % str(bw.get("meta", {}).get("stats", {}).get("toughness")))
	_check("Battlewagon Firing Deck removed", int(bw.get("transport_data", {}).get("firing_deck", -1)) == 0)
	var bw_ability_names := []
	for ab in bw.get("meta", {}).get("abilities", []):
		bw_ability_names.append(ab.get("name", "") if ab is Dictionary else str(ab))
	_check("Battlewagon has canonical 'Ramshackle'", "Ramshackle" in bw_ability_names, str(bw_ability_names))
	_check("Battlewagon 'Firing Deck 11' ability stripped", not ("Firing Deck 11" in bw_ability_names))

	var wb = orks.get("units", {}).get("U_WEIRDBOY_J", {})
	var wb_names := []
	for ab in wb.get("meta", {}).get("abilities", []):
		wb_names.append(ab.get("name", "") if ab is Dictionary else str(ab))
	_check("Weirdboy has canonical 'Da Jump'", "Da Jump" in wb_names, str(wb_names))

	var cust = alm.load_army_list("adeptus_custodes", 2)
	_check("custodes army loads", not cust.is_empty())
	var cg = cust.get("units", {}).get("U_CUSTODIAN_GUARD_B", {})
	_check("Custodian Guard W4 (Praesidium Shield +1)", int(cg.get("meta", {}).get("stats", {}).get("wounds", 0)) == 4)
	var all_w4 := true
	for m in cg.get("models", []):
		if int(m.get("wounds", 0)) != 4:
			all_w4 = false
	_check("all Custodian Guard models W4", all_w4)

func _test_faction_stratagems_implemented() -> void:
	print("\n-- Faction stratagems: 6/6 War Horde + 6/6 Shield Host implemented --")
	var alm = root.get_node("ArmyListManager")
	var sm = root.get_node("StratagemManager")

	var orks = alm.load_army_list("orks", 1)
	var cust = alm.load_army_list("adeptus_custodes", 2)
	alm.apply_army_to_game_state(orks, 1)
	alm.apply_army_to_game_state(cust, 2)
	sm.load_all_faction_stratagems()

	for player in [1, 2]:
		var strats = sm.get_faction_stratagems_for_player(player)
		_check("player %d has 6 faction stratagems" % player, strats.size() == 6, "got %d" % strats.size())
		var impl := 0
		for s in strats:
			if s.get("implemented", false):
				impl += 1
			else:
				print("    unimplemented: %s" % s.get("name", "?"))
		_check("player %d: all 6 mechanically implemented" % player, impl == 6, "%d/6" % impl)

	# Spot-check curated effect types survived the loader round-trip
	var expect := {
		"UNBRIDLED CARNAGE": "crit_hit_on",
		"MOB RULE": "remove_battle_shock",
		"ORKS IS NEVER BEATEN": "swing_back_before_remove",
		"AVENGE THE FALLEN": "plus_attacks",
		"MULTIPOTENTIALITY": "fall_back_and_shoot",
		"VIGILANCE ETERNAL": "sticky_objective_control",
	}
	var seen := {}
	for player in [1, 2]:
		for s in sm.get_faction_stratagems_for_player(player):
			var nm = str(s.get("name", "")).replace("’", "'").to_upper()
			for e in s.get("effects", []):
				if nm in expect and str(e.get("type", "")) == expect[nm]:
					seen[nm] = true
	for nm in expect:
		_check("%s carries effect '%s'" % [nm, expect[nm]], seen.get(nm, false))

func _test_defender_minus_one_wound() -> void:
	print("\n-- 'ARD AS NAILS: defender-side -1 to wound (ranged + melee) --")
	# Same seed => same raw rolls; the defensive flag shifts the wound threshold
	# so successful wounds must be <= baseline, and < for at least one seed.
	var strictly_less_ranged := false
	var never_more_ranged := true
	for s in [11, 22, 33]:
		var base = _sum_wounds_from_dice(_shoot(_make_board({}), s))
		var flagged = _sum_wounds_from_dice(_shoot(_make_board({"effect_minus_one_wound_defense": true}), s))
		if flagged > base:
			never_more_ranged = false
		if flagged < base:
			strictly_less_ranged = true
	_check("ranged: flagged target never takes MORE wounds", never_more_ranged)
	_check("ranged: flagged target takes strictly fewer wounds on some seed", strictly_less_ranged)

	var strictly_less_melee := false
	var never_more_melee := true
	var melee_saw_dice := false
	for s in [11, 22, 33, 44, 55, 66]:
		var base_m = _sum_wounds_from_dice(_melee(_make_board({}, 0.5), s))
		var flag_m = _sum_wounds_from_dice(_melee(_make_board({"effect_minus_one_wound_defense": true}, 0.5), s))
		if base_m > 0:
			melee_saw_dice = true
		if flag_m > base_m:
			never_more_melee = false
		if flag_m < base_m:
			strictly_less_melee = true
	_check("melee: attacks actually resolved (harness sanity)", melee_saw_dice)
	_check("melee: flagged target never takes MORE wounds", never_more_melee)
	_check("melee: flagged target takes strictly fewer wounds on some seed", strictly_less_melee)

func _test_defender_minus_one_hit_melee_only() -> void:
	print("\n-- UNWAVERING SENTINELS: defender-side -1 to hit, melee only --")
	var strictly_less := false
	var never_more := true
	for s in [11, 22, 33, 44, 55, 66]:
		var base = _sum_hits_from_dice(_melee(_make_board({}, 0.5), s))
		var flagged = _sum_hits_from_dice(_melee(_make_board({"effect_minus_one_hit_defense_melee": true}, 0.5), s))
		if flagged > base:
			never_more = false
		if flagged < base:
			strictly_less = true
	_check("melee: flagged target is hit no more often", never_more)
	_check("melee: flagged target is hit strictly less on some seed", strictly_less)

	# Must NOT leak into ranged
	var ranged_identical := true
	for s in [11, 22]:
		var base_r = _sum_hits_from_dice(_shoot(_make_board({}), s))
		var flag_r = _sum_hits_from_dice(_shoot(_make_board({"effect_minus_one_hit_defense_melee": true}), s))
		if base_r != flag_r:
			ranged_identical = false
	_check("ranged: melee-defense flag does NOT change ranged hits", ranged_identical)

func _test_blastajet_force_field() -> void:
	print("\n-- Blastajet Force Field: always-on 4+ invulnerable --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")
	_check("ability is table-implemented", uam.is_ability_implemented("Blastajet Force Field"))
	# Craft a unit with the ability, apply phase-start effects, read the flag.
	gs.state["units"] = {
		"U_WAZBOM": {
			"id": "U_WAZBOM", "owner": 1,
			"meta": {"keywords": ["VEHICLE", "FLY"], "stats": {"toughness": 9, "save": 3, "wounds": 12, "invuln": 6},
				"abilities": [{"name": "Blastajet Force Field", "type": "Datasheet"}]},
			"flags": {},
			"models": [{"id": "m1", "alive": true, "wounds": 12, "current_wounds": 12, "position": {"x": 100, "y": 100}}]
		}
	}
	uam.on_phase_start(8)  # shooting
	var flags = gs.state["units"]["U_WAZBOM"].get("flags", {})
	_check("effect_invuln 4 applied at shooting phase start", int(flags.get("effect_invuln", 0)) == 4, str(flags))
	uam.on_phase_end(8)

func _test_devoted_to_destruction() -> void:
	print("\n-- Devoted to Destruction: +2 melee Attacks flag in fight phase --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")
	_check("ability is table-implemented", uam.is_ability_implemented("Devoted to Destruction"))
	gs.state["units"] = {
		"U_TELEMON": {
			"id": "U_TELEMON", "owner": 2,
			"meta": {"keywords": ["VEHICLE"], "stats": {"toughness": 10, "save": 2, "wounds": 14},
				"abilities": [{"name": "Devoted to Destruction", "type": "Datasheet"}]},
			"flags": {},
			"models": [{"id": "m1", "alive": true, "wounds": 14, "current_wounds": 14, "position": {"x": 100, "y": 100}}]
		}
	}
	uam.on_phase_start(10)  # fight
	var flags = gs.state["units"]["U_TELEMON"].get("flags", {})
	_check("effect_plus_attacks 2 applied at fight phase start", int(flags.get("effect_plus_attacks", 0)) == 2, str(flags))
	uam.on_phase_end(10)
	# Melee-only: shooting phase must not set it
	gs.state["units"]["U_TELEMON"]["flags"] = {}
	uam.on_phase_start(8)
	var flags2 = gs.state["units"]["U_TELEMON"].get("flags", {})
	_check("no plus_attacks flag in shooting phase (melee-only)", int(flags2.get("effect_plus_attacks", 0)) == 0)
	uam.on_phase_end(8)

func _test_sneaky_gitz_overwatch() -> void:
	print("\n-- Sneaky Gitz: cannot Fire Overwatch --")
	var sm = root.get_node("StratagemManager")
	var gs = root.get_node("GameState")
	var units := {
		"U_KOMMANDOS": {
			"id": "U_KOMMANDOS", "owner": 2,
			"meta": {"name": "Kommandos", "keywords": ["INFANTRY"], "stats": {},
				"abilities": [{"name": "Sneaky Gitz", "type": "Datasheet"}],
				"weapons": [{"name": "Slugga", "type": "Ranged", "range": "12"}]},
			"flags": {},
			"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "position": {"x": 400, "y": 300}, "base_mm": 32}]
		},
		"U_BOYZ": {
			"id": "U_BOYZ", "owner": 2,
			"meta": {"name": "Boyz", "keywords": ["INFANTRY"], "stats": {},
				"abilities": [],
				"weapons": [{"name": "Slugga", "type": "Ranged", "range": "12"}]},
			"flags": {},
			"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "position": {"x": 440, "y": 300}, "base_mm": 32}]
		},
		"U_ENEMY": {
			"id": "U_ENEMY", "owner": 1,
			"meta": {"name": "Guard", "keywords": ["INFANTRY"], "stats": {}, "abilities": [], "weapons": []},
			"flags": {},
			"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "position": {"x": 500, "y": 100}, "base_mm": 32}]
		}
	}
	gs.state["units"] = units
	gs.state["players"] = {"1": {"cp": 3}, "2": {"cp": 3}}
	# fire_overwatch is gated on phase/turn via GameState (opponent's Movement
	# or Charge phase) — put the live state there, not just the snapshot.
	gs.state["meta"] = {"phase": 7, "active_player": 1, "battle_round": 1, "turn_number": 1}
	var snapshot = {"units": units, "meta": {"phase": 7, "active_player": 1, "battle_round": 1}}
	var eligible = sm.get_fire_overwatch_eligible_units(2, "U_ENEMY", snapshot)
	var ids := []
	for e in eligible:
		ids.append(e.get("unit_id", ""))
	_check("Boyz eligible for overwatch", "U_BOYZ" in ids, str(ids))
	_check("Kommandos (Sneaky Gitz) NOT eligible", not ("U_KOMMANDOS" in ids), str(ids))

func _test_bodyguard_extra_leader() -> void:
	print("\n-- Bodyguard: second leader-role attach allowed, third rejected --")
	var cam = root.get_node("CharacterAttachmentManager")
	var gs = root.get_node("GameState")
	var mk_char := func(uid: String) -> Dictionary:
		return {
			"id": uid, "owner": 1, "attached_to": null, "embarked_in": null,
			"status": 0,
			"meta": {"name": uid, "keywords": ["CHARACTER", "INFANTRY"], "stats": {},
				"abilities": [], "leader_data": {"can_lead": ["BOYZ"]}},
			"flags": {},
			"models": [{"id": "m1", "alive": true, "wounds": 5, "current_wounds": 5}]
		}
	var boyz := {
		"id": "U_BOYZ", "owner": 1, "attached_to": null,
		"attachment_data": {"attached_characters": []},
		"meta": {"name": "Boyz", "keywords": ["INFANTRY", "BOYZ"], "stats": {},
			"abilities": [{"name": "Bodyguard", "type": "Datasheet"}]},
		"flags": {},
		"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1}]
	}
	gs.state["units"] = {
		"U_BOYZ": boyz,
		"U_CHAR_A": mk_char.call("U_CHAR_A"),
		"U_CHAR_B": mk_char.call("U_CHAR_B"),
		"U_CHAR_C": mk_char.call("U_CHAR_C"),
	}
	var v1 = cam.can_attach("U_CHAR_A", "U_BOYZ")
	_check("first leader can attach", v1.get("valid", false), str(v1))
	gs.state["units"]["U_BOYZ"]["attachment_data"]["attached_characters"] = ["U_CHAR_A"]
	gs.state["units"]["U_CHAR_A"]["attached_to"] = "U_BOYZ"
	var v2 = cam.can_attach("U_CHAR_B", "U_BOYZ")
	_check("second leader can attach (Bodyguard)", v2.get("valid", false), str(v2))
	gs.state["units"]["U_BOYZ"]["attachment_data"]["attached_characters"] = ["U_CHAR_A", "U_CHAR_B"]
	gs.state["units"]["U_CHAR_B"]["attached_to"] = "U_BOYZ"
	var v3 = cam.can_attach("U_CHAR_C", "U_BOYZ")
	_check("third leader rejected", not v3.get("valid", true), str(v3))
	# Without the Bodyguard ability the SECOND leader must be rejected
	gs.state["units"]["U_BOYZ"]["meta"]["abilities"] = []
	gs.state["units"]["U_BOYZ"]["attachment_data"]["attached_characters"] = ["U_CHAR_A"]
	var v4 = cam.can_attach("U_CHAR_B", "U_BOYZ")
	_check("second leader rejected without Bodyguard", not v4.get("valid", true), str(v4))

func _test_admonimortis() -> void:
	print("\n-- Admonimortis: bearer death, 4+ = D3 MW to nearest enemy in 6\" --")
	var rules = root.get_node("RulesEngine")
	var board := {
		"units": {
			"U_BEARER": {
				"id": "U_BEARER", "owner": 2,
				"meta": {"name": "Shield-Captain", "keywords": ["CHARACTER"], "stats": {},
					"abilities": [], "enhancements": ["Admonimortis"]},
				"flags": {},
				"models": [{"id": "m1", "alive": false, "wounds": 6, "current_wounds": 0, "position": {"x": 100.0, "y": 100.0}, "base_mm": 40}]
			},
			"U_NEAR_ENEMY": {
				"id": "U_NEAR_ENEMY", "owner": 1,
				"meta": {"name": "Boyz", "keywords": ["INFANTRY"], "stats": {"toughness": 5, "save": 5, "wounds": 1}},
				"flags": {},
				"models": [
					{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "position": {"x": 220.0, "y": 100.0}, "base_mm": 32},
					{"id": "m2", "alive": true, "wounds": 1, "current_wounds": 1, "position": {"x": 260.0, "y": 100.0}, "base_mm": 32}
				]
			},
			"U_FAR_ENEMY": {
				"id": "U_FAR_ENEMY", "owner": 1,
				"meta": {"name": "Lootas", "keywords": ["INFANTRY"], "stats": {"toughness": 5, "save": 5, "wounds": 1}},
				"flags": {},
				"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "position": {"x": 900.0, "y": 900.0}, "base_mm": 32}]
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1}
	}
	# Find a seed whose first D6 is >= 4 and one < 4 (deterministic).
	var hit_seed := -1
	var miss_seed := -1
	for s in range(1, 30):
		var probe = rules.RNGService.new(s)
		var roll = probe.roll_d6(1)[0]
		if roll >= 4 and hit_seed == -1:
			hit_seed = s
		if roll < 4 and miss_seed == -1:
			miss_seed = s
		if hit_seed != -1 and miss_seed != -1:
			break

	# 11e policy: the 40kdc dataset ships no rule for Admonimortis (ability_id
	# null at 1.0.24), so the bearer-death trigger is DORMANT until official
	# 11e text lands (RulesEngine.ADMONIMORTIS_11E_ENABLED). Pin that state —
	# and keep the original behavior checks behind the flag so re-enabling
	# revives them unchanged.
	if rules.ADMONIMORTIS_11E_ENABLED:
		var res_hit = rules.resolve_admonimortis("U_BEARER", board, rules.RNGService.new(hit_seed))
		_check("applicable on bearer with enhancement", res_hit.get("applicable", false))
		_check("triggers on 4+", res_hit.get("triggered", false))
		_check("targets the NEAREST enemy unit", res_hit.get("target_unit_id", "") == "U_NEAR_ENEMY", str(res_hit))
		_check("deals 1-3 mortal wounds", res_hit.get("mortal_wounds", 0) >= 1 and res_hit.get("mortal_wounds", 0) <= 3)
		_check("produces damage diffs", res_hit.get("diffs", []).size() > 0)

		var res_miss = rules.resolve_admonimortis("U_BEARER", board, rules.RNGService.new(miss_seed))
		_check("does not trigger below 4", not res_miss.get("triggered", true))

		var no_enh = board.duplicate(true)
		no_enh["units"]["U_BEARER"]["meta"]["enhancements"] = []
		var res_na = rules.resolve_admonimortis("U_BEARER", no_enh, rules.RNGService.new(hit_seed))
		_check("not applicable without the enhancement", not res_na.get("applicable", true))
	else:
		var res_dormant = rules.resolve_admonimortis("U_BEARER", board, rules.RNGService.new(hit_seed))
		_check("dormant: not applicable while no 11e rule exists", not res_dormant.get("applicable", true), str(res_dormant))
		_check("dormant: never triggers", not res_dormant.get("triggered", true))
		_check("dormant: produces no diffs", res_dormant.get("diffs", []).is_empty())

func _test_serializer_migration() -> void:
	print("\n-- StateSerializer 1.2.0 -> 1.3.0: ability name canonicalization --")
	var ser = root.get_node("StateSerializer")
	var data := {
		"_serialization": {"version": "1.2.0"},
		"units": {
			"U_WEIRDBOY": {"meta": {"abilities": [
				{"name": "Da Jump (Psychic)", "type": "Datasheet"},
				{"name": "Waaagh!", "type": "Faction"}
			]}},
			"U_BW": {"meta": {"abilities": [
				{"name": "Ramshackle but Rugged", "type": "Datasheet"}
			]}}
		},
		"meta": {}, "players": {}, "board": {}, "factions": {}
	}
	var migrated = ser.migrate_save_data(data)
	_check("migration returns data", not migrated.is_empty())
	_check("migrated to current version", migrated.get("_serialization", {}).get("version", "") == ser.CURRENT_VERSION)
	var wb_names := []
	for ab in migrated["units"]["U_WEIRDBOY"]["meta"]["abilities"]:
		wb_names.append(ab.get("name", ""))
	_check("Da Jump canonicalized in save", "Da Jump" in wb_names, str(wb_names))
	var bw_names := []
	for ab in migrated["units"]["U_BW"]["meta"]["abilities"]:
		bw_names.append(ab.get("name", ""))
	_check("Ramshackle canonicalized in save", "Ramshackle" in bw_names, str(bw_names))

# ----------------------------------------------------------------------------
func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_fullauto_faction_rules ===")
	# The game is 11e; SettingsService may reset the static edition var from a
	# stored setting in headless runs. Force 11 — the shipped rules edition.
	GameConstants.edition = 11

	_test_army_load_pipeline()
	_test_faction_stratagems_implemented()
	_test_defender_minus_one_wound()
	_test_defender_minus_one_hit_melee_only()
	_test_blastajet_force_field()
	_test_devoted_to_destruction()
	_test_sneaky_gitz_overwatch()
	_test_bodyguard_extra_leader()
	_test_admonimortis()
	_test_serializer_migration()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

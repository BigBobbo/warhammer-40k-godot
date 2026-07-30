extends SceneTree

# MA-LOADOUT: a melee assignment is swung only by the models that CARRY the
# weapon — even when the assignment names no models.
#
# 11e Fight — Select Weapons: "For each model in the attacking unit, select which
# weapons that model will make attacks with … you must select one melee weapon
# THAT MODEL HAS." An ASSIGN_ATTACKS with no `models` list (the shape the AI,
# auto-resolve and networked paths submit) used to mean "every model in the unit
# swings this", so a 10-model Ork Boyz mob told to use a Power klaw swung TEN
# power klaws — a weapon exactly zero of its models own. The datasheet is
# unambiguous: "The Boss Nob is equipped with: slugga; big choppa. Every Boy is
# equipped with: slugga; choppa." Choppa, Close combat weapon, Big choppa and
# Power klaw are mutually-exclusive wargear OPTIONS on that datasheet, not a
# shared arsenal.
#
# Covered here (engine/phase state only — the player-facing dialog is covered by
# tests/scenarios/sp/tut_t6_krumpin.json and fight_one_weapon_per_model_11e.json):
#   1. the mob resolves to 9 Choppa + 1 Big choppa, one weapon per model
#   2. a whole-unit Choppa assignment rolls 9 models' worth of attacks, not 10
#   3. a whole-unit Power klaw assignment does NOT silently zero the unit
#      (nobody carries it -> conservative fallback, loudly logged)
#   4. FightPhase gap-fills the Boss Nob's big choppa when a whole-unit pick
#      leaves him out, so both weapons swing in the one activation
#   5. an assignment that DOES name its models (the dialog path) is untouched
#   6. PAIRED wargear options: a roster records the ranged half of a swap
#      ("9x Shoota") and nothing about melee, and the datasheet's option list is
#      what says those Boyz hold a CLOSE COMBAT WEAPON rather than the choppa
#      they started with
#   7. a swap the roster names without a count is left unresolved rather than
#      answered with the default kit (which would drop the weapon entirely)
#
# Usage: godot --headless --path . -s tests/test_melee_per_model_carriers.gd

var passed := 0
var failed := 0
var RE
var _gs = null


func _init():
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.2).timeout.connect(_run)


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _load_json(path: String):
	var fa = FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var txt = fa.get_as_text()
	fa.close()
	return JSON.parse_string(txt)


# A real Boyz mob off the shipped army list, placed in base contact with an
# enemy so every model is eligible to fight.
func _make_state():
	var ork = _load_json("res://armies/orks.json")
	if typeof(ork) != TYPE_DICTIONARY:
		return {}
	var boyz = ork["units"].get("U_BOYZ_K", {})
	if boyz.is_empty():
		return {}
	boyz = boyz.duplicate(true)
	boyz["id"] = "U_BOYZ_K"
	boyz["owner"] = 1
	boyz["flags"] = {"charged_this_turn": true}
	# Resolution stamps are per-unit and cached; start from the roster's own
	# state so this test exercises the real resolve path.
	boyz.erase("_loadout_checked")
	boyz.erase("_loadout_version")
	for i in range(boyz["models"].size()):
		var m = boyz["models"][i]
		m["position"] = {"x": 0.0, "y": float(i * 35)}
		m["base_mm"] = 32
		m["alive"] = true
		m["current_wounds"] = m.get("wounds", 1)
		m.erase("melee_loadout")

	var target_models = []
	for i in range(10):
		target_models.append({
			"id": "mt%d" % i, "position": {"x": 38.0, "y": float(i * 35)},
			"base_mm": 32, "alive": true, "wounds": 3, "current_wounds": 3
		})

	return {
		"meta": {"phase": 10, "active_player": 1, "battle_round": 2, "turn": 2},
		"board": {"size": {"width": 1760, "height": 2400}, "objectives": []},
		"players": {"1": {"cp": 0, "vp": 0}, "2": {"cp": 0, "vp": 0}},
		"units": {
			"U_BOYZ_K": boyz,
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2, "flags": {},
				"meta": {
					"name": "Targets", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 6, "wounds": 3}
				},
				"models": target_models
			}
		}
	}


# Total attacks a melee assignment actually gathers, read off the returned dice
# blocks (the hit roll block has one die per attack). Resolves against a COPY —
# resolution kills models, and a thinned-out target would change the next call's
# engagement ranges and make these counts order-dependent.
func _attacks_for(assignment: Dictionary, board: Dictionary) -> int:
	var res = RE.resolve_melee_attacks({
		"actor_unit_id": "U_BOYZ_K",
		"payload": {"assignments": [assignment]}
	}, board.duplicate(true), RE.make_rng("per-model-carriers"))
	var n = 0
	for d in res.get("dice", []):
		if str(d.get("context", "")) == "hit_roll_melee":
			n += int(d.get("rolls_raw", d.get("rolls", [])).size())
	return n


func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_melee_per_model_carriers ===\n")

	RE = root.get_node_or_null("RulesEngine")
	if RE == null:
		_check("RulesEngine autoload reachable", false)
		_finish()
		return
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		_check("GameState autoload reachable", false)
		_finish()
		return
	GameConstants.edition = 11

	var state = _make_state()
	if state.is_empty():
		_check("orks.json U_BOYZ_K loadable", false)
		_finish()
		return
	_gs.state = state

	# ---- 1. the mob's real melee loadout -------------------------------------
	var mm = RE.get_unit_melee_weapons("U_BOYZ_K", state)
	var hist := {}
	var worst := 0
	for mid in mm:
		worst = max(worst, mm[mid].size())
		for wn in mm[mid]:
			hist[str(wn)] = int(hist.get(str(wn), 0)) + 1
	_check("9 Boyz carry a Choppa", int(hist.get("Choppa", 0)) == 9, str(hist))
	_check("1 Boss Nob carries a Big choppa", int(hist.get("Big choppa", 0)) == 1, str(hist))
	_check("no Power klaw ghost (an option the roster never took)", not hist.has("Power klaw"), str(hist))
	_check("no Close combat weapon ghost", not hist.has("Close combat weapon"), str(hist))
	_check("exactly one melee weapon per model", worst == 1, "worst=%d" % worst)

	var eligible = RE.get_eligible_melee_model_indices(state.units["U_BOYZ_K"], state)
	_check("all 10 models are in engagement range", eligible.size() == 10, str(eligible.size()))

	# ---- 2/3. whole-unit assignments respect the carriers ---------------------
	# Choppa is A:3 and carried by 9 of the 10 models -> 27 attacks, not 30.
	var choppa_attacks = _attacks_for(
		{"attacker": "U_BOYZ_K", "target": "U_TARGET", "weapon": "choppa_melee", "models": []}, state)
	_check("whole-unit Choppa rolls 9x3 = 27 attacks (was 10x3 = 30)",
		choppa_attacks == 27, "got %d" % choppa_attacks)

	# Big choppa is A:3 and carried by the Boss Nob alone -> 3 attacks, not 30.
	var big_choppa_attacks = _attacks_for(
		{"attacker": "U_BOYZ_K", "target": "U_TARGET", "weapon": "big_choppa_melee", "models": []}, state)
	_check("whole-unit Big choppa rolls the Boss Nob's 3 attacks (was 30)",
		big_choppa_attacks == 3, "got %d" % big_choppa_attacks)

	# Nobody carries a Power klaw. Narrowing to "no carriers" must NOT silently
	# zero the unit's output — the conservative fallback keeps the old behaviour
	# and logs it, exactly like every other loadout narrowing in the engine.
	var klaw_attacks = _attacks_for(
		{"attacker": "U_BOYZ_K", "target": "U_TARGET", "weapon": "power_klaw_melee", "models": []}, state)
	_check("a weapon nobody carries falls back rather than zeroing the unit",
		klaw_attacks > 0, "got %d" % klaw_attacks)

	# ---- 5. an explicit model list is authoritative --------------------------
	var two_models = _attacks_for(
		{"attacker": "U_BOYZ_K", "target": "U_TARGET", "weapon": "choppa_melee", "models": ["1", "2"]}, state)
	_check("an explicit model list still wins (2 models x 3 = 6)",
		two_models == 6, "got %d" % two_models)

	# ---- 4. FightPhase gap-fills the models the unit-wide pick left out ------
	# Fresh state: the resolutions above ran on copies, but be explicit that the
	# phase drives an intact board (a thinned target changes engagement ranges).
	_gs.state = _make_state()
	# load() at runtime — naming FightPhase at parse time forces an eager compile
	# before the autoloads register.
	var phase = load("res://phases/FightPhase.gd").new()
	root.add_child(phase)
	phase.enter_phase(_gs.state)
	phase.active_fighter_id = "U_BOYZ_K"
	if phase.sequencer_11e != null:
		phase.sequencer_11e.select_to_fight("U_BOYZ_K", _gs.state)
	phase.pending_attacks = [{
		"attacker": "U_BOYZ_K", "target": "U_TARGET", "weapon": "choppa_melee", "models": []
	}]
	var confirm = phase.process_action({"type": "CONFIRM_AND_RESOLVE_ATTACKS", "player": 1})
	_check("CONFIRM_AND_RESOLVE_ATTACKS succeeded", confirm.get("success", false), str(confirm))

	var by_weapon := {}
	for a in phase.confirmed_attacks:
		by_weapon[str(a.get("weapon", ""))] = a.get("models", [])
	_check("the unit-wide Choppa assignment is kept as-is",
		by_weapon.has("choppa_melee") and by_weapon["choppa_melee"].is_empty(), str(by_weapon))
	_check("the Boss Nob's Big choppa was gap-filled in",
		by_weapon.has("big_choppa_melee"), str(by_weapon))
	_check("the gap-fill names only the Boss Nob (model 0)",
		by_weapon.get("big_choppa_melee", []) == ["0"], str(by_weapon.get("big_choppa_melee", [])))
	_check("no weapon the mob does not carry was added",
		not by_weapon.has("power_klaw_melee") and not by_weapon.has("close_combat_weapon_melee"), str(by_weapon))

	# A per-model path (the dialog) names its models — a model deliberately left
	# out must stay out, so nothing is gap-filled.
	phase.confirmed_attacks = []
	phase.pending_attacks = [{
		"attacker": "U_BOYZ_K", "target": "U_TARGET", "weapon": "choppa_melee",
		"models": ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
	}]
	phase.process_action({"type": "CONFIRM_AND_RESOLVE_ATTACKS", "player": 1})
	var explicit_weapons := []
	for a in phase.confirmed_attacks:
		explicit_weapons.append(str(a.get("weapon", "")))
	_check("an explicit per-model assignment is never gap-filled",
		explicit_weapons == ["choppa_melee"], str(explicit_weapons))

	phase.queue_free()

	_check_paired_wargear_options()
	_finish()


# A histogram of the melee weapons a unit's models actually carry.
func _melee_hist(uid: String, unit: Dictionary) -> Dictionary:
	var mm = RE.get_unit_melee_weapons(uid, {"units": {uid: unit}})
	var hist := {}
	for mid in mm:
		for wn in mm[mid]:
			hist[str(wn)] = int(hist.get(str(wn), 0)) + 1
	return hist


func _fresh_boyz(wargear: Array) -> Dictionary:
	var ork = _load_json("res://armies/orks.json")
	if typeof(ork) != TYPE_DICTIONARY:
		return {}
	var u = ork["units"].get("U_BOYZ_K", {})
	if u.is_empty():
		return {}
	u = u.duplicate(true)
	u["meta"]["wargear"] = wargear
	u.erase("_loadout_checked")
	u.erase("_loadout_version")
	for m in u.get("models", []):
		m.erase("ranged_loadout")
		m.erase("melee_loadout")
	return u


# The pairing problem: a roster's wargear string almost never records the MELEE
# half of a swap. "Any number of Boyz can each have their slugga AND choppa
# replaced with 1 shoota AND 1 close combat weapon" is the only thing that says
# a Boy holding a shoota is holding a close combat weapon — the datasheet's
# default kit alone would wrongly hand him the choppa he traded away.
func _check_paired_wargear_options() -> void:
	print("\n--- paired wargear options ---")

	# Whole mob on shootas: 9 Boyz swapped, the Boss Nob keeps his big choppa.
	var shoota_mob = _fresh_boyz(["9x Shoota", "1x Slugga"])
	if not shoota_mob.is_empty():
		var h = _melee_hist("U_BOYZ_SHOOTA", shoota_mob)
		_check("shoota Boyz carry a Close combat weapon, not a Choppa",
			int(h.get("Close combat weapon", 0)) == 9 and not h.has("Choppa"), str(h))
		_check("the Boss Nob keeps his Big choppa", int(h.get("Big choppa", 0)) == 1, str(h))

	# Partial swap: 3 Boyz took shootas, 6 kept slugga + choppa.
	var mixed = _fresh_boyz(["3x Shoota", "7x Slugga"])
	if not mixed.is_empty():
		var h2 = _melee_hist("U_BOYZ_MIXED", mixed)
		_check("3 shoota Boyz -> 3 Close combat weapons", int(h2.get("Close combat weapon", 0)) == 3, str(h2))
		_check("6 unchanged Boyz keep their Choppas", int(h2.get("Choppa", 0)) == 6, str(h2))
		_check("still exactly 10 melee weapons across 10 models",
			int(h2.get("Close combat weapon", 0)) + int(h2.get("Choppa", 0)) + int(h2.get("Big choppa", 0)) == 10, str(h2))

	# Ambiguous alternatives: shoota and big shoota swaps BOTH grant a close
	# combat weapon, so the shared weapon proves nothing — each swap is counted
	# from the gun that is unique to it.
	var two_swaps = _fresh_boyz(["8x Shoota", "1x Big shoota", "1x Slugga", "9x Close combat weapon"])
	if not two_swaps.is_empty():
		var h3 = _melee_hist("U_BOYZ_TWO_SWAPS", two_swaps)
		_check("two different swaps still leave 9 Close combat weapons",
			int(h3.get("Close combat weapon", 0)) == 9, str(h3))
		_check("no Choppa survives when every Boy swapped", not h3.has("Choppa"), str(h3))

	# A swap the roster names with NO count, on a datasheet that allows any
	# number, cannot be sized — answering with the default kit would silently
	# drop the sentinel blades this roster paid for.
	var cust = _load_json("res://armies/Adeptus_Custodes_1995_Mar_7.json")
	if typeof(cust) == TYPE_DICTIONARY:
		var g = cust["units"].get("U_CUSTODIAN_GUARD_A", {})
		if not g.is_empty():
			g = g.duplicate(true)
			g.erase("_loadout_checked")
			g.erase("_loadout_version")
			for m in g.get("models", []):
				m.erase("melee_loadout")
			RE.get_unit_melee_weapons("U_CUSTODIAN_GUARD_A", {"units": {"U_CUSTODIAN_GUARD_A": g}})
			var stamped := false
			for m in g.get("models", []):
				if m.has("melee_loadout"):
					stamped = true
					break
			_check("count-less 'Sentinel blade' swap -> left unresolved, blade not dropped",
				not stamped, str(g["meta"].get("wargear", [])))


func _finish():
	print("\n=== test_melee_per_model_carriers: %d passed, %d failed ===\n" % [passed, failed])
	quit(0 if failed == 0 else 1)

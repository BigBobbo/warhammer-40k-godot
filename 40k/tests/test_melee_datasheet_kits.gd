extends SceneTree

# MA-LOADOUT: what each model is EQUIPPED with, read off the datasheet.
#
# tests/test_melee_per_model_loadout.gd already pins the carrier funnel — only a
# model equipped with the picked weapon swings it. This pins the layer beneath:
# working out what "equipped with" means for a roster whose wargear string does
# not say.
#
# A Boyz mob's wargear rarely says everything about melee, so the funnel used
# to fall back to `model_profiles` — the datasheet's option MENU — and count
# every model as carrying every melee option (Choppa AND Big Choppa AND Power
# Klaw ...). Those are mutually-exclusive options. The datasheet itself is
# unambiguous — Codex: Orks (11e): "Every Nob is equipped with: 1 Kustom Choppa;
# 1 Kombi-skorcha. Every Boy is equipped with: 1 Choppa; 1 Shoota; 1 Slugga."
# Model kits are built from that line plus whichever "•" swaps the roster
# took, so the funnel is asked a question it can answer correctly.
# (Ported from the pre-codex Boyz kit — Boss Nob big choppa, Boy shoota swap —
# with the Codex: Orks import; the mechanics checked are unchanged.)
#
# Covered here (engine/phase state only — the attack dialog is covered by the
# windowed scenarios):
#   1. the mob resolves to 9 Choppa + 1 Kustom Choppa, one weapon per model,
#      with no Big Choppa or Power Klaw the roster never bought
#   2/3. a whole-unit assignment rolls only its carriers' attacks, and a weapon
#      nobody carries falls back rather than zeroing the unit
#   4. FightPhase gap-fills the Nob's Kustom Choppa when a whole-unit pick
#      (the AI's action shape) leaves him out, so both weapons swing at once
#   5. an assignment that DOES name its models (the dialog path) is untouched
#   6. PAIRED swaps: "Kustom Choppa AND Kombi-skorcha replaced with 1 Big
#      Choppa" — the roster records the new weapon and the datasheet's option
#      list says which weapons the Nob gave up
#   7. a swap the roster names without a count is left unresolved rather than
#      answered with the default kit (which would drop the weapon entirely)
#
# Usage: godot --headless --path . -s tests/test_melee_datasheet_kits.gd

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
	print("\n=== test_melee_datasheet_kits ===\n")

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
	_check("1 Nob carries a Kustom Choppa", int(hist.get("Kustom Choppa", 0)) == 1, str(hist))
	_check("no Power Klaw ghost (an option the roster never took)", not hist.has("Power Klaw"), str(hist))
	_check("no Big Choppa ghost", not hist.has("Big Choppa"), str(hist))
	_check("exactly one melee weapon per model", worst == 1, "worst=%d" % worst)

	var eligible = RE.get_eligible_melee_model_indices(state.units["U_BOYZ_K"], state)
	_check("all 10 models are in engagement range", eligible.size() == 10, str(eligible.size()))

	# ---- 2/3. whole-unit assignments respect the carriers ---------------------
	# Choppa is A:3 and carried by 9 of the 10 models -> 27 attacks, not 30.
	var choppa_attacks = _attacks_for(
		{"attacker": "U_BOYZ_K", "target": "U_TARGET", "weapon": "choppa_melee", "models": []}, state)
	_check("whole-unit Choppa rolls 9x3 = 27 attacks (was 10x3 = 30)",
		choppa_attacks == 27, "got %d" % choppa_attacks)

	# Kustom Choppa is A:4 and carried by the Nob alone -> 4 attacks, not 40.
	var kustom_attacks = _attacks_for(
		{"attacker": "U_BOYZ_K", "target": "U_TARGET", "weapon": "kustom_choppa_melee", "models": []}, state)
	_check("whole-unit Kustom Choppa rolls the Nob's 4 attacks (was 40)",
		kustom_attacks == 4, "got %d" % kustom_attacks)

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
	_check("the Nob's Kustom Choppa was gap-filled in",
		by_weapon.has("kustom_choppa_melee"), str(by_weapon))
	_check("the gap-fill names only the Nob (model 0)",
		by_weapon.get("kustom_choppa_melee", []) == ["0"], str(by_weapon.get("kustom_choppa_melee", [])))
	_check("no weapon the mob does not carry was added",
		not by_weapon.has("power_klaw_melee") and not by_weapon.has("big_choppa_melee"), str(by_weapon))

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


# The pairing problem: a roster's wargear records the weapon a model TOOK, and
# only the datasheet's option list says what it gave up. "Any number of Nob
# models can each have their Kustom Choppa AND Kombi-skorcha replaced with 1 Big
# Choppa" is what says a Nob holding a Big Choppa no longer swings the Kustom
# Choppa he started with.
func _check_paired_wargear_options() -> void:
	print("\n--- paired wargear options ---")

	# The Nob takes the paired swap: Big Choppa replaces Kustom Choppa + Kombi-skorcha.
	var big = _fresh_boyz(["1x Big Choppa", "9x Choppa", "9x Shoota", "9x Slugga"])
	if not big.is_empty():
		var h = _melee_hist("U_BOYZ_BIG", big)
		_check("paired swap: the Nob carries the Big Choppa, not his Kustom Choppa",
			int(h.get("Big Choppa", 0)) == 1 and not h.has("Kustom Choppa"), str(h))
		_check("paired swap: the 9 Boyz keep their Choppas", int(h.get("Choppa", 0)) == 9, str(h))
		_check("paired swap: still exactly 10 melee weapons across 10 models",
			int(h.get("Big Choppa", 0)) + int(h.get("Choppa", 0)) == 10, str(h))

	# Single swap: Power Klaw replaces the Kustom Choppa only.
	var klaw = _fresh_boyz(["1x Power Klaw", "1x Kombi-skorcha", "9x Choppa", "9x Shoota", "9x Slugga"])
	if not klaw.is_empty():
		var h2 = _melee_hist("U_BOYZ_KLAW", klaw)
		_check("single swap: the Nob carries the Power Klaw instead of the Kustom Choppa",
			int(h2.get("Power Klaw", 0)) == 1 and not h2.has("Kustom Choppa"), str(h2))
		_check("single swap: the Boyz keep their Choppas", int(h2.get("Choppa", 0)) == 9, str(h2))

	# A RANGED-only swap (a Boy's Shoota -> Big Shoota) changes no melee weapon.
	var ranged = _fresh_boyz(["1x Kustom Choppa", "1x Kombi-skorcha", "9x Choppa", "8x Shoota", "1x Big Shoota", "9x Slugga"])
	if not ranged.is_empty():
		var h3 = _melee_hist("U_BOYZ_RANGED", ranged)
		_check("ranged-only swap: melee kit unchanged (9 Choppa + 1 Kustom Choppa)",
			int(h3.get("Choppa", 0)) == 9 and int(h3.get("Kustom Choppa", 0)) == 1, str(h3))

	# A swap the roster names with NO count, on a datasheet that allows any
	# number, cannot be sized — answering with the default kit would silently
	# drop the sentinel blades this roster paid for.
	# (Roster lines from the retired 10e import Adeptus_Custodes_1995_Mar_7.)
	var cust = _load_json("res://armies/custodes_lions.json")
	if typeof(cust) == TYPE_DICTIONARY:
		var g = cust["units"].get("U_CUSTODIAN_GUARD_A", {})
		if not g.is_empty():
			g = g.duplicate(true)
			g["meta"]["wargear"] = ["3x Guardian Spear", "Sentinel blade", "Praesidium Shield"]
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
	print("\n=== test_melee_datasheet_kits: %d passed, %d failed ===\n" % [passed, failed])
	quit(0 if failed == 0 else 1)

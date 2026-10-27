extends SceneTree

# Lions of the Emperor + Silent Hunters (Adeptus Custodes) — 10e regression test,
# RETIRED / REWRITTEN in WP-C46 (Codex: Adeptus Custodes 11e).
#
# The 10e Lions of the Emperor stopgaps (Against All Odds, Fierce Conqueror,
# Superior Creation's 10e path, Praesidius, Admonimortis) and the Silent
# Hunters detachment (Skin-Crawling Disorientation, Encircling Hunter,
# Psyk-out Grenades) are deleted; their groups now PIN the removal so the 10e
# code cannot silently return (.llm/codex_11e_wahapedia/RETIRED_TESTS.md). The
# codex rules are covered by tests/test_custodes_detachments_11e.gd and
# tests/test_custodes_enhancements_11e.gd.
#
# Still live (generic EffectPrimitives the 10e stratagems introduced and other
# rules reuse): effect-granted LANCE, plus_attacks_vs_psyker, grant_rapid_fire,
# grant_blast, scoped improve_ap.
#
# Usage: godot --headless --path . -s tests/test_custodes_lions_silent_hunters.gd

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
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

var _tests_ran := false

var gs: Node = null

func _run_tests() -> void:
	if _tests_ran:
		return
	_tests_ran = true
	gs = root.get_node("GameState")

	print("\n===== Custodes Lions of the Emperor + Silent Hunters tests =====")

	# _test_stratagem_loading / _test_gilded_champion retired with Codex:
	# Adeptus Custodes (11e): the 10e Lions of the Emperor stratagems and the
	# Silent Hunters detachment no longer exist; the codex Lions / Auric
	# Champions stratagems are WP-C5's (.llm/codex_11e_wahapedia/RETIRED_TESTS.md).
	# The remaining groups exercise 10e engine code that WP-C46 replaces.
	_test_against_all_odds()
	_test_effect_lance()
	_test_plus_attacks_vs_psyker()
	_test_grant_rapid_fire()
	_test_grant_blast()
	_test_improve_ap_scoped()
	_test_fierce_conqueror()
	_test_superior_creation()
	_test_praesidius_and_psyk_out()
	_test_admonimortis_stopgap()
	_test_encircling_hunter()
	_test_skin_crawling_disorientation()

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

# ----------------------------------------------------------------------------
# Board factory
# ----------------------------------------------------------------------------
func _make_board(opts: Dictionary = {}) -> Dictionary:
	var px_per_inch = 40.0
	var distance_inches: float = opts.get("distance_inches", 2.0)
	var target_distance_px = distance_inches * px_per_inch
	var shooter_models = []
	for i in range(opts.get("shooter_models", 4)):
		shooter_models.append({
			"id": "ms%d" % i,
			"position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3
		})
	var target_models = []
	var spacing: float = opts.get("target_spacing_px", 35.0)
	for i in range(opts.get("target_models", 8)):
		target_models.append({
			"id": "mt%d" % i,
			"position": {"x": target_distance_px, "y": float(i) * spacing},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3,
			"stats": {"toughness": 4, "save": 4}
		})
	return {
		"units": {
			"U_SHOOTER": {
				"id": "U_SHOOTER", "owner": 1,
				"meta": {
					"name": "Shooter",
					"keywords": opts.get("shooter_keywords", ["INFANTRY"]),
					"stats": {"toughness": 4, "save": 4, "wounds": 3},
					"abilities": [],
					"enhancements": opts.get("shooter_enhancements", []),
					"weapons": [{"name": "Choppa", "type": "melee"}]
				},
				"flags": opts.get("shooter_flags", {}),
				"models": shooter_models
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2,
				"meta": {
					"name": "Target",
					"keywords": opts.get("target_keywords", ["INFANTRY"]),
					"stats": {"toughness": 4, "save": 4, "wounds": 3},
					"abilities": [],
					"weapons": [{"name": "Choppa", "type": "melee"}]
				},
				"flags": opts.get("target_flags", {}),
				"models": target_models
			}
		},
		"factions": opts.get("factions", {}),
		"board": {"size": {"width": 44, "height": 60}},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1}
	}

func _shoot(board: Dictionary, seed_val: int, weapon_id: String = "bolt_rifle", attacks_override: int = -1) -> Dictionary:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var assignment := {
		"weapon_id": weapon_id,
		"target_unit_id": "U_TARGET",
		"model_ids": ["ms0", "ms1", "ms2", "ms3"]
	}
	if attacks_override > 0:
		assignment["attacks_override"] = attacks_override
	var action := {
		"type": "SHOOT",
		"actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [assignment]}
	}
	return rules.resolve_shoot(action, board, rng)

func _melee(board: Dictionary, seed_val: int, weapon: String = "choppa") -> Dictionary:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {
		"type": "FIGHT",
		"actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"attacker": "U_SHOOTER",
			"target": "U_TARGET",
			"weapon": weapon
		}]}
	}
	return rules.resolve_melee_attacks(action, board, rng)

func _count_rolls(result: Dictionary, context_substr: String) -> int:
	var total := 0
	for d in result.get("dice", []):
		if context_substr in str(d.get("context", "")):
			total += d.get("rolls_raw", []).size()
	return total

func _count_successes(result: Dictionary, context_substr: String) -> int:
	var total := 0
	for d in result.get("dice", []):
		if context_substr in str(d.get("context", "")) and d.has("successes"):
			total += int(d.get("successes", 0))
	return total

func _count_field(result: Dictionary, context_substr: String, field: String) -> int:
	var total := 0
	for d in result.get("dice", []):
		if context_substr in str(d.get("context", "")) and d.has(field):
			total += int(d.get(field, 0))
	return total

func _lions_factions(owner: int = 1) -> Dictionary:
	return {str(owner): {"name": "Adeptus Custodes", "detachment": "Lions of the Emperor"}}

# ----------------------------------------------------------------------------
# 1. Stratagem loading
# ----------------------------------------------------------------------------
func _test_stratagem_loading() -> void:
	print("\n-- Stratagem load: 6/6 Lions + 3/3 Silent Hunters implemented --")
	var alm = root.get_node("ArmyListManager")
	var sm = root.get_node("StratagemManager")

	var lions = alm.load_army_list("custodes_lions", 1)
	_check("Lions army loads", not lions.is_empty())
	alm.apply_army_to_game_state(lions, 1)
	var cust = alm.load_army_list("adeptus_custodes", 2)
	alm.apply_army_to_game_state(cust, 2)
	# Player 2 becomes the Silent Hunters army (no shipped roster uses it, so
	# override the detachment before loading stratagems).
	gs.state["factions"]["2"] = {"name": "Adeptus Custodes", "detachment": "Silent Hunters"}
	sm.load_all_faction_stratagems()

	var expected := {
		1: ["PEERLESS WARRIOR", "GILDED CHAMPION", "DEFIANT TO THE LAST",
			"UNLEASH THE LIONS", "MANOEUVRE AND FIRE", "SWIFT AS THE EAGLE"],
		2: ["DEATHSONG SCYTHES", "UMBRAL PROSECUTION", "SYNCHRONISED INFERNO"],
	}
	for player in expected:
		var strats = sm.get_faction_stratagems_for_player(player)
		var by_name := {}
		for s in strats:
			by_name[s.get("name", "").to_upper()] = s
		_check("player %d loads %d faction stratagems" % [player, expected[player].size()],
			strats.size() == expected[player].size(), "got %d" % strats.size())
		for want in expected[player]:
			var s = by_name.get(want, {})
			_check("  %s loaded + implemented" % want,
				not s.is_empty() and s.get("implemented", false),
				"missing" if s.is_empty() else "implemented=false")

	# Target-keyword parsing for the Sisters of Silence datasheets
	var sh = sm.get_faction_stratagems_for_player(2)
	for s in sh:
		var conds: Array = s.get("target", {}).get("conditions", [])
		match s.get("name", "").to_upper():
			"DEATHSONG SCYTHES":
				_check("  Deathsong targets VIGILATORS", "keyword:VIGILATORS" in conds, str(conds))
			"UMBRAL PROSECUTION":
				_check("  Umbral targets PROSECUTORS", "keyword:PROSECUTORS" in conds, str(conds))
			"SYNCHRONISED INFERNO":
				_check("  Synchronised targets WITCHSEEKERS", "keyword:WITCHSEEKERS" in conds, str(conds))

# ----------------------------------------------------------------------------
# 2. Against All Odds
# ----------------------------------------------------------------------------
func _test_against_all_odds() -> void:
	# RETIRED (WP-C46): the 10e Lions of the Emperor "Against All Odds" (+1 hit /
	# +1 wound while isolated) is gone — the codex Lions rule is On Gilded Wings
	# (tests/test_custodes_detachments_11e.gd). Pin the removal.
	print("\n-- Against All Odds (RETIRED, WP-C46) --")
	var fam = root.get_node("FactionAbilityManager")
	_check("retired: check_against_all_odds removed", not fam.has_method("check_against_all_odds"))
	_check("retired: evaluate_against_all_odds removed", not fam.has_method("evaluate_against_all_odds"))
	_check("retired: is_against_all_odds_active removed", not fam.has_method("is_against_all_odds_active"))

# ----------------------------------------------------------------------------
# 3. Effect-granted LANCE
# ----------------------------------------------------------------------------
func _test_effect_lance() -> void:
	print("\n-- Deathsong Scythes: effect-granted LANCE (+1 wound on charge) --")
	var ep = load("res://autoloads/EffectPrimitives.gd")

	# Ranged path with a NON-lance weapon: flag + charged → more wounds
	var base_flags = {"charged_this_turn": true}
	var lance_flags = {"charged_this_turn": true, ep.FLAG_LANCE: true}
	var res_no = _shoot(_make_board({"shooter_flags": base_flags}), 777, "bolt_rifle", 60)
	var res_yes = _shoot(_make_board({"shooter_flags": lance_flags}), 777, "bolt_rifle", 60)
	var wounds_no = _count_successes(res_no, "to_wound")
	var wounds_yes = _count_successes(res_yes, "to_wound")
	_check("effect_lance +1 wound when charged (with %d > without %d)" % [wounds_yes, wounds_no], wounds_yes > wounds_no)

	# Without the charge, the flag must NOT help
	var res_nc = _shoot(_make_board({"shooter_flags": {ep.FLAG_LANCE: true}}), 777, "bolt_rifle", 60)
	var res_plain = _shoot(_make_board({}), 777, "bolt_rifle", 60)
	_check("effect_lance inert without charge", _count_successes(res_nc, "to_wound") == _count_successes(res_plain, "to_wound"))

	# Melee path with a NON-lance weapon (choppa)
	var m_no = _melee(_make_board({"shooter_flags": base_flags, "distance_inches": 0.5}), 4242)
	var m_yes = _melee(_make_board({"shooter_flags": lance_flags, "distance_inches": 0.5}), 4242)
	var mw_no = _count_successes(m_no, "wound_roll_melee")
	var mw_yes = _count_successes(m_yes, "wound_roll_melee")
	_check("effect_lance +1 wound in melee (with %d > without %d)" % [mw_yes, mw_no], mw_yes > mw_no)

# ----------------------------------------------------------------------------
# 4. plus_attacks_vs_psyker
# ----------------------------------------------------------------------------
func _test_plus_attacks_vs_psyker() -> void:
	print("\n-- Deathsong Scythes: +1 melee Attack vs PSYKER targets --")
	var ep = load("res://autoloads/EffectPrimitives.gd")
	var flags = {ep.FLAG_PLUS_ATTACKS_VS_PSYKER: 1}

	var vs_psyker = _melee(_make_board({
		"shooter_flags": flags, "target_keywords": ["INFANTRY", "PSYKER"], "distance_inches": 0.5,
	}), 99)
	var vs_normal = _melee(_make_board({
		"shooter_flags": flags, "target_keywords": ["INFANTRY"], "distance_inches": 0.5,
	}), 99)
	var rolls_psyker = _count_rolls(vs_psyker, "hit_roll_melee")
	var rolls_normal = _count_rolls(vs_normal, "hit_roll_melee")
	_check("+1 attack per model vs PSYKER (psyker %d = normal %d + models)" % [rolls_psyker, rolls_normal],
		rolls_psyker == rolls_normal + 4, "expected +4 (4 models)")

# ----------------------------------------------------------------------------
# 5. grant_rapid_fire
# ----------------------------------------------------------------------------
func _test_grant_rapid_fire() -> void:
	print("\n-- Umbral Prosecution: granted RAPID FIRE 2 inside half range --")
	var ep = load("res://autoloads/EffectPrimitives.gd")
	# slugga: A1, range 12, no native Rapid Fire; target at 2" (inside half range)
	var res_no = _shoot(_make_board({}), 55, "slugga")
	var res_yes = _shoot(_make_board({"shooter_flags": {ep.FLAG_GRANT_RAPID_FIRE: 2}}), 55, "slugga")
	var rolls_no = _count_rolls(res_no, "to_hit")
	var rolls_yes = _count_rolls(res_yes, "to_hit")
	_check("granted RF2 adds 2 attacks per model in half range (%d → %d)" % [rolls_no, rolls_yes],
		rolls_yes == rolls_no + 8, "expected +8 (4 models × RF2)")

	# Outside half range: no bonus
	var res_far = _shoot(_make_board({"shooter_flags": {ep.FLAG_GRANT_RAPID_FIRE: 2}, "distance_inches": 8.0}), 55, "slugga")
	_check("granted RF2 inert outside half range", _count_rolls(res_far, "to_hit") == rolls_no,
		"got %d" % _count_rolls(res_far, "to_hit"))

# ----------------------------------------------------------------------------
# 6. grant_blast
# ----------------------------------------------------------------------------
func _test_grant_blast() -> void:
	print("\n-- Synchronised Inferno: granted BLAST vs 8-model target --")
	var ep = load("res://autoloads/EffectPrimitives.gd")
	var res_no = _shoot(_make_board({"target_models": 8}), 66, "slugga")
	var res_yes = _shoot(_make_board({"target_models": 8, "shooter_flags": {ep.FLAG_GRANT_BLAST: true}}), 66, "slugga")
	var rolls_no = _count_rolls(res_no, "to_hit")
	var rolls_yes = _count_rolls(res_yes, "to_hit")
	_check("granted BLAST adds attacks vs 8 models (%d → %d)" % [rolls_no, rolls_yes], rolls_yes > rolls_no)

# ----------------------------------------------------------------------------
# 7. improve_ap scoped
# ----------------------------------------------------------------------------
func _test_improve_ap_scoped() -> void:
	print("\n-- Umbral Prosecution: improve_ap scope=ranged --")
	var ep = load("res://autoloads/EffectPrimitives.gd")
	var diffs = ep.apply_effects([{"type": "improve_ap", "value": 1, "scope": "ranged"}], "U_X")
	var flag_path = ""
	for d in diffs:
		flag_path = d.get("path", "")
	_check("scoped effect writes effect_improve_ap_ranged", flag_path.ends_with(ep.FLAG_IMPROVE_AP_RANGED), flag_path)

	var unit = {"flags": {ep.FLAG_IMPROVE_AP_RANGED: 1}}
	_check("get_effect_improve_ap_scoped ranged = 1", ep.get_effect_improve_ap_scoped(unit, "ranged") == 1)
	_check("get_effect_improve_ap_scoped melee = 0", ep.get_effect_improve_ap_scoped(unit, "melee") == 0)

	# End-to-end: fewer successful saves with ranged AP improvement (same seed)
	var res_no = _shoot(_make_board({}), 88, "bolt_rifle", 60)
	var res_yes = _shoot(_make_board({"shooter_flags": {ep.FLAG_IMPROVE_AP_RANGED: 1}}), 88, "bolt_rifle", 60)
	var fails_no = _count_field(res_no, "save", "fails")
	var fails_yes = _count_field(res_yes, "save", "fails")
	_check("ranged AP+1 raises failed saves (%d > %d)" % [fails_yes, fails_no], fails_yes > fails_no)

# ----------------------------------------------------------------------------
# 8. Fierce Conqueror
# ----------------------------------------------------------------------------
func _test_fierce_conqueror() -> void:
	# RETIRED (WP-C46): Fierce Conqueror was a 10e Lions stopgap; Codex: Adeptus
	# Custodes 11e has no such enhancement.
	print("\n-- Fierce Conqueror (RETIRED, WP-C46) --")
	var rules = root.get_node("RulesEngine")
	_check("retired: get_fierce_conqueror_bonus_attacks removed", not rules.has_method("get_fierce_conqueror_bonus_attacks"))

# ----------------------------------------------------------------------------
# 9. Superior Creation
# ----------------------------------------------------------------------------
func _test_superior_creation() -> void:
	# RETIRED (WP-C46): the 10e Lions Superior Creation path is replaced by the
	# codex Auric Champions enhancement (CustodesEnhancements.resolve_superior_creation,
	# tests/test_custodes_enhancements_11e.gd).
	print("\n-- Superior Creation, 10e path (RETIRED, WP-C46) --")
	var rules = root.get_node("RulesEngine")
	_check("retired: RulesEngine.record_superior_creation_death removed", not rules.has_method("record_superior_creation_death"))

# ----------------------------------------------------------------------------
# 10/11. Praesidius + Psyk-out Grenades army-load grants
# ----------------------------------------------------------------------------
func _test_praesidius_and_psyk_out() -> void:
	# RETIRED (WP-C46): Praesidius (10e Lions) and Psyk-out Grenades (Silent
	# Hunters) are not Codex: Adeptus Custodes 11e enhancements.
	print("\n-- Praesidius / Psyk-out Grenades (RETIRED, WP-C46) --")
	var alm = root.get_node("ArmyListManager")
	_check("retired: Praesidius grant table entry removed", not alm.ENHANCEMENT_GRANTED_ABILITIES.has("Praesidius"))
	_check("retired: Psyk-out Grenades keyword grant removed", not alm.ENHANCEMENT_GRANTED_KEYWORDS.has("Psyk-out Grenades"))

# ----------------------------------------------------------------------------
# 11b. Admonimortis (10e stopgap): +3S / +1AP / +1D on the bearer's melee weapons
# ----------------------------------------------------------------------------
func _test_admonimortis_stopgap() -> void:
	# RETIRED (WP-C46): Admonimortis was a 10e Lions stopgap.
	print("\n-- Admonimortis (RETIRED, WP-C46) --")
	var rules = root.get_node("RulesEngine")
	_check("retired: has_admonimortis removed", not rules.has_method("has_admonimortis"))

# ----------------------------------------------------------------------------
# 12. Encircling Hunter
# ----------------------------------------------------------------------------
func _test_encircling_hunter() -> void:
	# RETIRED (WP-C46): Encircling Hunter (Silent Hunters) is gone with that
	# detachment; the generic redeploy table now carries the codex Castellan's
	# Mark (Guardians of the Throne) instead.
	print("\n-- Encircling Hunter (RETIRED, WP-C46) --")
	var fam = root.get_node("FactionAbilityManager")
	var names: Array = []
	for e in fam.REDEPLOY_ENHANCEMENTS:
		names.append(str(e.get("name", "")))
	_check("retired: Encircling Hunter not a redeploy enhancement", not ("Encircling Hunter" in names), str(names))
	_check("codex Castellan's Mark is a redeploy enhancement", "Castellan's Mark" in names, str(names))

# ----------------------------------------------------------------------------
# 13. Skin-Crawling Disorientation
# ----------------------------------------------------------------------------
func _test_skin_crawling_disorientation() -> void:
	# RETIRED (WP-C46): Skin-Crawling Disorientation was the Silent Hunters rule.
	print("\n-- Skin-Crawling Disorientation (RETIRED, WP-C46) --")
	var fam = root.get_node("FactionAbilityManager")
	_check("retired: check_skin_crawling_disorientation removed", not fam.has_method("check_skin_crawling_disorientation"))
	_check("retired: no Silent Hunters detachment ability", not fam.DETACHMENT_ABILITIES.has("Silent Hunters"))

# ----------------------------------------------------------------------------
# 14. Gilded Champion
# ----------------------------------------------------------------------------
func _test_gilded_champion() -> void:
	print("\n-- Gilded Champion: restore a spent once-per-battle ability --")
	var alm = root.get_node("ArmyListManager")
	var sm = root.get_node("StratagemManager")
	var uam = root.get_node("UnitAbilityManager")

	# Fresh Lions army for player 1
	var lions = alm.load_army_list("custodes_lions", 1)
	alm.apply_army_to_game_state(lions, 1)
	sm.load_faction_stratagems_for_player(1)
	gs.state["players"]["1"]["cp"] = 5

	var strat_id = sm.find_faction_stratagem_by_name(1, "GILDED CHAMPION")
	_check("Gilded Champion stratagem found", strat_id != "")

	# Find an AC CHARACTER unit in the army
	var char_id := ""
	for uid in gs.state.get("units", {}):
		var u = gs.state.units[uid]
		if u.get("owner", 0) != 1:
			continue
		var kws: Array = u.get("meta", {}).get("keywords", [])
		if "CHARACTER" in kws and "ADEPTUS CUSTODES" in kws:
			char_id = uid
			break
	_check("AC CHARACTER unit found in Lions army", char_id != "")

	# No spent ability → cannot use
	var check_before = sm.can_use_stratagem(1, strat_id, char_id, {"bypass_phase_check": true})
	_check("blocked before any once-per-battle ability used", not check_before.can_use, str(check_before))

	# Spend a once-per-battle ability, then the stratagem becomes usable
	uam.mark_once_per_battle_used(char_id, "Moment Shackle")
	_check("ability recorded as used", uam.is_once_per_battle_used(char_id, "Moment Shackle"))
	var check_after = sm.can_use_stratagem(1, strat_id, char_id, {"bypass_phase_check": true})
	_check("usable after a once-per-battle ability was spent", check_after.can_use, str(check_after))

	var use_result = sm.use_stratagem(1, strat_id, char_id, {"bypass_phase_check": true})
	_check("use_stratagem succeeds", use_result.get("success", false), str(use_result))

	# Restored, but blocked in the SAME phase
	_check("still 'used' in the same phase (block)", uam.is_once_per_battle_used(char_id, "Moment Shackle"))
	# Advance the phase → available again
	var old_phase = gs.state.meta.phase
	gs.state.meta.phase = (int(old_phase) + 1) % 12
	_check("available again in a later phase", not uam.is_once_per_battle_used(char_id, "Moment Shackle"))
	gs.state.meta.phase = old_phase

	# Once per battle per model
	uam.mark_once_per_battle_used(char_id, "Moment Shackle")
	var check_again = sm.can_use_stratagem(1, strat_id, char_id, {"bypass_phase_check": true})
	_check("same model cannot be targeted twice", not check_again.can_use, str(check_again))

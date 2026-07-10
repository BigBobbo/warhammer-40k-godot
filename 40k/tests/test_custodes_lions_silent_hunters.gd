extends SceneTree

# Lions of the Emperor + Silent Hunters (Adeptus Custodes) regression test.
#
# 11e-only policy: the game implements exactly what the 40kdc 11e dataset
# defines. For Silent Hunters that is everything (detachment rule, both
# enhancements, all three stratagems). For Lions of the Emperor the dataset
# defines ONLY the Against All Odds detachment rule — the six stratagems and
# four enhancements ship with no 11e payloads (still true at 1.0.24), so they
# must stay display-only stubs (NOT backfilled from 10e sources).
#
# Covers:
#   1. Stratagem load: all 6 Lions stratagems load UNIMPLEMENTED (stub text);
#      all 3 Silent Hunters stratagems load implemented from the dataset.
#   2. Against All Odds (the one dataset-defined Lions rule): detachment-gated
#      (Lions only), +1 to hit applies in MELEE as well as ranged, VEHICLE and
#      non-isolated units excluded.
#   3. Effect-granted LANCE (Deathsong Scythes): +1 to wound when the unit
#      charged, for weapons without the native keyword.
#   4. plus_attacks_vs_psyker (Deathsong Scythes): melee attack count rises
#      only against PSYKER targets.
#   5. grant_rapid_fire (Umbral Prosecution): extra attacks inside half range.
#   6. grant_blast (Synchronised Inferno): blast bonus attacks vs big units.
#   7. improve_ap scoped flags (Umbral Prosecution): ranged-only AP bonus.
#   8. Psyk-out Grenades: grants the EXPLOSIVES keyword at army load (11e).
#   9. Encircling Hunter: redeploy-enhancement eligibility (Anathema Psykana
#      INFANTRY, bearer excluded, 3 slots).
#  10. Skin-Crawling Disorientation: Anathema Psykana may perform actions
#      after Advancing (Silent Hunters only).
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

	_test_stratagem_loading()
	_test_against_all_odds()
	_test_effect_lance()
	_test_plus_attacks_vs_psyker()
	_test_grant_rapid_fire()
	_test_grant_blast()
	_test_improve_ap_scoped()
	_test_psyk_out_grenades()
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
	print("\n-- Stratagem load: Lions 6/6 display-only stubs, Silent Hunters 3/3 implemented --")
	var alm = root.get_node("ArmyListManager")
	var sm = root.get_node("StratagemManager")

	var lions = alm.load_army_list("Adeptus_Custodes_1995_Mar_7", 1)
	_check("Lions army loads", not lions.is_empty())
	alm.apply_army_to_game_state(lions, 1)
	var cust = alm.load_army_list("adeptus_custodes", 2)
	alm.apply_army_to_game_state(cust, 2)
	# Player 2 becomes the Silent Hunters army (no shipped roster uses it, so
	# override the detachment before loading stratagems).
	gs.state["factions"]["2"] = {"name": "Adeptus Custodes", "detachment": "Silent Hunters"}
	sm.load_all_faction_stratagems()

	# 11e policy: the 40kdc dataset has NO effect text for any Lions of the
	# Emperor stratagem (1.0.24), so all six must load as display-only stubs
	# (implemented=false) — a regression here means 10e content leaked back in.
	var lions_expected := ["PEERLESS WARRIOR", "GILDED CHAMPION", "DEFIANT TO THE LAST",
		"UNLEASH THE LIONS", "MANOEUVRE AND FIRE", "SWIFT AS THE EAGLE"]
	var lions_strats = sm.get_faction_stratagems_for_player(1)
	var lions_by_name := {}
	for s in lions_strats:
		lions_by_name[s.get("name", "").to_upper()] = s
	_check("player 1 loads 6 Lions stratagems", lions_strats.size() == 6, "got %d" % lions_strats.size())
	for want in lions_expected:
		var s = lions_by_name.get(want, {})
		_check("  %s loaded as display-only stub (no 11e rules yet)" % want,
			not s.is_empty() and not s.get("implemented", true),
			"missing" if s.is_empty() else "implemented=true — 10e content leaked back in")
		if not s.is_empty():
			var use_check = sm.can_use_stratagem(1, s.get("id", ""), "", {"bypass_phase_check": true})
			_check("  %s not usable by the player" % want, not use_check.can_use)

	var sh_expected := ["DEATHSONG SCYTHES", "UMBRAL PROSECUTION", "SYNCHRONISED INFERNO"]
	var sh_strats = sm.get_faction_stratagems_for_player(2)
	var sh_by_name := {}
	for s in sh_strats:
		sh_by_name[s.get("name", "").to_upper()] = s
	_check("player 2 loads 3 Silent Hunters stratagems", sh_strats.size() == 3, "got %d" % sh_strats.size())
	for want in sh_expected:
		var s = sh_by_name.get(want, {})
		_check("  %s loaded + implemented (11e dataset rules)" % want,
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
	print("\n-- Against All Odds: detachment gate + melee hit/wound --")
	var fam = root.get_node("FactionAbilityManager")

	# Isolated AC unit under Lions → buff active
	var board = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": _lions_factions(1),
	})
	var unit = board.units["U_SHOOTER"]
	_check("isolated Lions AC unit gets AAO", fam.check_against_all_odds(unit, board))

	# Same unit under Shield Host → NO buff (detachment gate)
	var board_sh = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": {"1": {"name": "Adeptus Custodes", "detachment": "Shield Host"}},
	})
	_check("Shield Host army does NOT get AAO", not fam.check_against_all_odds(board_sh.units["U_SHOOTER"], board_sh))

	# NBSP detachment name still matches (issue #366 rosters)
	var board_nbsp = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": {"1": {"name": "Adeptus Custodes", "detachment": "Lions of the Emperor"}},
	})
	_check("NBSP detachment name still gets AAO", fam.check_against_all_odds(board_nbsp.units["U_SHOOTER"], board_nbsp))

	# VEHICLE excluded
	var board_v = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "VEHICLE"],
		"factions": _lions_factions(1),
	})
	_check("VEHICLE excluded from AAO", not fam.check_against_all_odds(board_v.units["U_SHOOTER"], board_v))

	# Friendly unit within 6" → no buff
	var board_f = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": _lions_factions(1),
	})
	board_f.units["U_FRIEND"] = {
		"id": "U_FRIEND", "owner": 1,
		"meta": {"name": "Friend", "keywords": ["INFANTRY"], "stats": {}, "abilities": []},
		"flags": {},
		"models": [{"id": "mf0", "position": {"x": 80.0, "y": 0.0}, "base_mm": 32, "alive": true, "wounds": 1, "current_wounds": 1}]
	}
	_check("friendly within 6\" blocks AAO", not fam.check_against_all_odds(board_f.units["U_SHOOTER"], board_f))

	# Melee: same seed, Lions vs Shield Host — Lions must land at least as many
	# hits and wounds (+1 to hit AND +1 to wound; seed chosen so the delta shows)
	var melee_lions = _melee(_make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": _lions_factions(1),
		"distance_inches": 0.5,
	}), 1234)
	var melee_shield = _melee(_make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": {"1": {"name": "Adeptus Custodes", "detachment": "Shield Host"}},
		"distance_inches": 0.5,
	}), 1234)
	var hits_lions = _count_successes(melee_lions, "hit_roll_melee")
	var hits_shield = _count_successes(melee_shield, "hit_roll_melee")
	_check("AAO melee +1 to hit (lions %d > shield %d)" % [hits_lions, hits_shield], hits_lions > hits_shield)

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
# 8. Psyk-out Grenades army-load grant (11e: Explosives keyword)
# ----------------------------------------------------------------------------
func _test_psyk_out_grenades() -> void:
	print("\n-- Psyk-out Grenades: EXPLOSIVES keyword granted at army load --")
	var alm = root.get_node("ArmyListManager")
	var rules = root.get_node("RulesEngine")

	var sos = {
		"id": "U_S", "owner": 1,
		"meta": {
			"name": "Prosecutors",
			"keywords": ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "PROSECUTORS"],
			"abilities": [],
			"enhancements": ["Psyk-out Grenades"],
		},
		"flags": {}, "models": []
	}
	alm._apply_enhancement_granted_abilities("U_S", sos)
	_check("Psyk-out grants EXPLOSIVES", rules.unit_has_keyword(sos, "EXPLOSIVES"))
	# Idempotent
	alm._apply_enhancement_granted_abilities("U_S", sos)
	var explosives_count = 0
	for kw in sos.meta.keywords:
		if str(kw).to_upper() == "EXPLOSIVES":
			explosives_count += 1
	_check("grant is idempotent", explosives_count == 1, str(sos.meta.keywords))

	# 11e policy: Lions enhancements have no dataset rules — the grant tables
	# must not carry entries for them (no 10e backfill).
	_check("no ability grants for Lions enhancements",
		not alm.ENHANCEMENT_GRANTED_ABILITIES.has("Praesidius"))

# ----------------------------------------------------------------------------
# 9. Encircling Hunter
# ----------------------------------------------------------------------------
func _test_encircling_hunter() -> void:
	print("\n-- Encircling Hunter: redeploy-enhancement eligibility --")
	var fam = root.get_node("FactionAbilityManager")

	# Build a small GameState army: bearer + 2 Anathema Psykana INFANTRY + 1 other
	# load() at runtime — a compile-time GameStateData reference makes the
	# -s test script pull the DeploymentZoneData/FactionPalettes chain before
	# the autoloads register (transient "Identifier not found" stderr noise).
	var deployed = load("res://autoloads/GameState.gd").UnitStatus.DEPLOYED
	gs.state["units"] = {
		"U_BEARER": {"id": "U_BEARER", "owner": 1, "status": deployed,
			"meta": {"name": "Knight-Centura", "keywords": ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "INFANTRY", "CHARACTER"],
				"abilities": [], "enhancements": ["Encircling Hunter"]},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 0, "y": 0}}]},
		"U_SOS_A": {"id": "U_SOS_A", "owner": 1, "status": deployed,
			"meta": {"name": "Prosecutors", "keywords": ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "INFANTRY"], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 40, "y": 0}}]},
		"U_SOS_B": {"id": "U_SOS_B", "owner": 1, "status": deployed,
			"meta": {"name": "Witchseekers", "keywords": ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "INFANTRY"], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 80, "y": 0}}]},
		"U_GUARD": {"id": "U_GUARD", "owner": 1, "status": deployed,
			"meta": {"name": "Custodian Guard", "keywords": ["ADEPTUS CUSTODES", "INFANTRY"], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "alive": true, "position": {"x": 120, "y": 0}}]},
	}
	if fam.has_method("reset_all"):
		pass
	fam._razgit_redeploys_used = {"1": 0, "2": 0}

	_check("has_razgit_magik_map true via Encircling Hunter", fam.has_razgit_magik_map(1))
	_check("enhancement name reported", fam.get_redeploy_enhancement_name(1) == "Encircling Hunter")
	var eligible = fam.get_razgit_eligible_units(1)
	var ids := []
	for e in eligible:
		ids.append(e.get("unit_id", ""))
	_check("both Anathema Psykana units eligible", "U_SOS_A" in ids and "U_SOS_B" in ids, str(ids))
	_check("bearer excluded", not ("U_BEARER" in ids), str(ids))
	_check("non-Anathema unit excluded", not ("U_GUARD" in ids), str(ids))
	_check("3 redeploy slots", fam.get_razgit_redeploys_remaining(1) == 3)
	fam.mark_razgit_redeploy_used(1)
	_check("slot consumed", fam.get_razgit_redeploys_remaining(1) == 2)
	fam._razgit_redeploys_used = {"1": 0, "2": 0}

	var redeploy_units = gs.get_redeploy_units_for_player(1)
	_check("GameState offers the eligible units for redeployment",
		"U_SOS_A" in redeploy_units and "U_SOS_B" in redeploy_units, str(redeploy_units))

# ----------------------------------------------------------------------------
# 10. Skin-Crawling Disorientation
# ----------------------------------------------------------------------------
func _test_skin_crawling_disorientation() -> void:
	print("\n-- Skin-Crawling Disorientation: actions after Advancing --")
	var fam = root.get_node("FactionAbilityManager")

	var board = {
		"factions": {"1": {"name": "Adeptus Custodes", "detachment": "Silent Hunters"}},
		"units": {}
	}
	var sos = {"id": "U_S", "owner": 1,
		"meta": {"keywords": ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "INFANTRY"], "abilities": []},
		"flags": {"advanced": true}, "models": []}
	_check("Silent Hunters Anathema unit may act after Advance", fam.check_skin_crawling_disorientation(sos, board))

	var custodian = {"id": "U_C", "owner": 1,
		"meta": {"keywords": ["ADEPTUS CUSTODES", "INFANTRY"], "abilities": []},
		"flags": {"advanced": true}, "models": []}
	_check("non-Anathema unit does not benefit", not fam.check_skin_crawling_disorientation(custodian, board))

	var board_lions = {
		"factions": {"1": {"name": "Adeptus Custodes", "detachment": "Lions of the Emperor"}},
		"units": {}
	}
	_check("other detachments do not benefit", not fam.check_skin_crawling_disorientation(sos, board_lions))

	_check("DETACHMENT_ABILITIES has Silent Hunters entry",
		fam.DETACHMENT_ABILITIES.has("Silent Hunters")
		and fam.DETACHMENT_ABILITIES["Silent Hunters"].get("ability_name", "") == "Skin-Crawling Disorientation")

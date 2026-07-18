extends SceneTree

# Lions of the Emperor + Silent Hunters (Adeptus Custodes) regression test.
#
# Policy (user ruling 2026-07-10): the game implements the 40kdc 11e dataset
# where published (all of Silent Hunters), and the official 10e wording as an
# EXPLICIT provisional stopgap where 11e is not published yet (all Lions
# stratagems + enhancements, whose CSV rows carry a PROVISIONAL note).
#
# Covers the engine half of "both Custodes detachments are mechanically
# implemented":
#   1. Stratagem load: all 6 Lions of the Emperor + all 3 Silent Hunters
#      stratagems load mechanically implemented (curated effects_json +
#      custom handlers marked by StratagemManager).
#   2. Against All Odds: detachment-gated (Lions only), +1 to hit applies in
#      MELEE as well as ranged, VEHICLE and non-isolated units excluded.
#   3. Effect-granted LANCE (Deathsong Scythes): +1 to wound when the unit
#      charged, for weapons without the native keyword.
#   4. plus_attacks_vs_psyker (Deathsong Scythes): melee attack count rises
#      only against PSYKER targets.
#   5. grant_rapid_fire (Umbral Prosecution): extra attacks inside half range.
#   6. grant_blast (Synchronised Inferno): blast bonus attacks vs big units.
#   7. improve_ap scoped flags (Umbral Prosecution): ranged-only AP bonus.
#   8. Fierce Conqueror: +2 melee Attacks per 5 enemy models within 6".
#   9. Superior Creation: first-death revival roll at end of phase (2+),
#      once per battle, placement outside Engagement Range.
#  10. Praesidius: grants Lone Operative + Stealth at army load.
#  11. Psyk-out Grenades: grants EXPLOSIVES/GRENADES keywords at army load.
#  12. Encircling Hunter: redeploy-enhancement eligibility (Anathema Psykana
#      INFANTRY, bearer excluded, 3 slots).
#  13. Skin-Crawling Disorientation: Anathema Psykana may perform actions
#      after Advancing (Silent Hunters only).
#  14. Gilded Champion: restores a spent once-per-battle ability, blocked in
#      the same phase, once per battle per model.
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
	_test_fierce_conqueror()
	_test_superior_creation()
	_test_praesidius_and_psyk_out()
	_test_admonimortis_stopgap()
	_test_encircling_hunter()
	_test_skin_crawling_disorientation()
	_test_gilded_champion()

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

	var lions = alm.load_army_list("Adeptus_Custodes_1995_Mar_7", 1)
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

	# Attached leader (Leader rules: one unit) must NOT block the buff — in
	# either direction (bodyguard attacking, or the attached character attacking).
	var board_led = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": _lions_factions(1),
	})
	board_led.units["U_SHOOTER"]["attachment_data"] = {"attached_characters": ["U_LEADER"]}
	board_led.units["U_LEADER"] = {
		"id": "U_LEADER", "owner": 1, "attached_to": "U_SHOOTER",
		"meta": {"name": "Leader", "keywords": ["ADEPTUS CUSTODES", "CHARACTER", "INFANTRY"], "stats": {}, "abilities": []},
		"flags": {},
		"models": [{"id": "ml0", "position": {"x": 0.0, "y": 150.0}, "base_mm": 32, "alive": true, "wounds": 6, "current_wounds": 6}]
	}
	_check("attached leader does not block AAO (bodyguard attacks)", fam.check_against_all_odds(board_led.units["U_SHOOTER"], board_led))
	_check("bodyguard does not block AAO (attached leader attacks)", fam.check_against_all_odds(board_led.units["U_LEADER"], board_led))

	# ...but a leader's models ARE part of the unit: a friendly within 6" of the
	# LEADER model (though beyond 6" of every bodyguard model) still blocks.
	var board_led2 = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": _lions_factions(1),
	})
	board_led2.units["U_SHOOTER"]["attachment_data"] = {"attached_characters": ["U_LEADER"]}
	board_led2.units["U_LEADER"] = {
		"id": "U_LEADER", "owner": 1, "attached_to": "U_SHOOTER",
		"meta": {"name": "Leader", "keywords": ["ADEPTUS CUSTODES", "CHARACTER", "INFANTRY"], "stats": {}, "abilities": []},
		"flags": {},
		"models": [{"id": "ml0", "position": {"x": 0.0, "y": 400.0}, "base_mm": 32, "alive": true, "wounds": 6, "current_wounds": 6}]
	}
	# Friend ~4.7" edge-to-edge from the leader model (y=560 → 160px gap), but
	# ~10" from the nearest bodyguard model (y=105 → 455px gap).
	board_led2.units["U_FRIEND"] = {
		"id": "U_FRIEND", "owner": 1,
		"meta": {"name": "Friend", "keywords": ["INFANTRY"], "stats": {}, "abilities": []},
		"flags": {},
		"models": [{"id": "mf0", "position": {"x": 0.0, "y": 560.0}, "base_mm": 32, "alive": true, "wounds": 1, "current_wounds": 1}]
	}
	_check("friendly near the attached leader still blocks AAO", not fam.check_against_all_odds(board_led2.units["U_SHOOTER"], board_led2))

	# Embarked friendly (stale battlefield position) must NOT block — an
	# embarked unit is not on the battlefield.
	var board_e = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": _lions_factions(1),
	})
	board_e.units["U_FRIEND"] = {
		"id": "U_FRIEND", "owner": 1, "embarked_in": "U_TRANSPORT",
		"meta": {"name": "Friend", "keywords": ["INFANTRY"], "stats": {}, "abilities": []},
		"flags": {},
		"models": [{"id": "mf0", "position": {"x": 80.0, "y": 0.0}, "base_mm": 32, "alive": true, "wounds": 1, "current_wounds": 1}]
	}
	_check("embarked friendly does not block AAO", fam.check_against_all_odds(board_e.units["U_SHOOTER"], board_e))

	# Friendly in Strategic Reserves (stale position) must NOT block.
	var board_r = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": _lions_factions(1),
	})
	board_r.units["U_FRIEND"] = {
		"id": "U_FRIEND", "owner": 1,
		"status": load("res://autoloads/GameState.gd").UnitStatus.IN_RESERVES,
		"meta": {"name": "Friend", "keywords": ["INFANTRY"], "stats": {}, "abilities": []},
		"flags": {},
		"models": [{"id": "mf0", "position": {"x": 80.0, "y": 0.0}, "base_mm": 32, "alive": true, "wounds": 1, "current_wounds": 1}]
	}
	_check("friendly in reserves does not block AAO", fam.check_against_all_odds(board_r.units["U_SHOOTER"], board_r))

	# base_mm must be honoured: a 60mm-base friendly at 7.5" centre-to-centre is
	# ~5.7" edge-to-edge (blocks); assuming 32mm would put it at ~6.2" (no block).
	var board_b = _make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": _lions_factions(1),
	})
	board_b.units["U_FRIEND"] = {
		"id": "U_FRIEND", "owner": 1,
		"meta": {"name": "Friend", "keywords": ["INFANTRY"], "stats": {}, "abilities": []},
		"flags": {},
		"models": [{"id": "mf0", "position": {"x": 300.0, "y": 0.0}, "base_mm": 60, "alive": true, "wounds": 1, "current_wounds": 1}]
	}
	_check("60mm base friendly at 5.7\" edge-to-edge blocks AAO", not fam.check_against_all_odds(board_b.units["U_SHOOTER"], board_b))

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
	var wounds_lions = _count_successes(melee_lions, "wound_roll_melee")
	var wounds_shield = _count_successes(melee_shield, "wound_roll_melee")
	_check("AAO melee +1 to wound (lions %d > shield %d)" % [wounds_lions, wounds_shield], wounds_lions > wounds_shield)

	# Ranged: same seed and 60 attacks — +1 to hit and +1 to wound must both show
	var shoot_lions = _shoot(_make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": _lions_factions(1),
	}), 4321, "bolt_rifle", 60)
	var shoot_shield = _shoot(_make_board({
		"shooter_keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
		"factions": {"1": {"name": "Adeptus Custodes", "detachment": "Shield Host"}},
	}), 4321, "bolt_rifle", 60)
	var rhits_lions = _count_successes(shoot_lions, "to_hit")
	var rhits_shield = _count_successes(shoot_shield, "to_hit")
	_check("AAO ranged +1 to hit (lions %d > shield %d)" % [rhits_lions, rhits_shield], rhits_lions > rhits_shield)
	var rwounds_lions = _count_successes(shoot_lions, "to_wound")
	var rwounds_shield = _count_successes(shoot_shield, "to_wound")
	_check("AAO ranged +1 to wound (lions %d > shield %d)" % [rwounds_lions, rwounds_shield], rwounds_lions > rwounds_shield)

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
	print("\n-- Fierce Conqueror: +2 melee Attacks per 5 enemy models within 6\" --")
	var rules = root.get_node("RulesEngine")

	# 8 enemy models at 2" → floor(8/5)*2 = +2
	var board = _make_board({
		"shooter_models": 1,
		"shooter_enhancements": ["Fierce Conqueror"],
		"target_models": 8,
	})
	_check("+2 per 5 enemies (8 within 6\")", rules.get_fierce_conqueror_bonus_attacks(board.units["U_SHOOTER"], board) == 2)

	# 12 enemy models → floor(12/5)*2 = +4
	var board12 = _make_board({
		"shooter_models": 1,
		"shooter_enhancements": ["Fierce Conqueror"],
		"target_models": 12,
		"target_spacing_px": 18.0,
	})
	_check("+4 per 5 enemies (12 within 6\")", rules.get_fierce_conqueror_bonus_attacks(board12.units["U_SHOOTER"], board12) == 4)

	# 4 enemy models → 0
	var board4 = _make_board({
		"shooter_models": 1,
		"shooter_enhancements": ["Fierce Conqueror"],
		"target_models": 4,
	})
	_check("no bonus below 5 enemies", rules.get_fierce_conqueror_bonus_attacks(board4.units["U_SHOOTER"], board4) == 0)

	# No enhancement → 0
	var board_none = _make_board({"shooter_models": 1, "target_models": 8})
	_check("no bonus without the enhancement", rules.get_fierce_conqueror_bonus_attacks(board_none.units["U_SHOOTER"], board_none) == 0)

	# Enemies out of range → 0
	var board_far = _make_board({
		"shooter_models": 1,
		"shooter_enhancements": ["Fierce Conqueror"],
		"target_models": 8,
		"distance_inches": 10.0,
	})
	_check("no bonus when enemies beyond 6\"", rules.get_fierce_conqueror_bonus_attacks(board_far.units["U_SHOOTER"], board_far) == 0)

	# End-to-end: melee attack count rises by the bonus (1 model, choppa A3 → 3+2=5 rolls)
	var m_with = _melee(board, 31)
	var m_none = _melee(board_none, 31)
	_check("melee rolls include Fierce Conqueror bonus (%d = %d + 2)" % [_count_rolls(m_with, "hit_roll_melee"), _count_rolls(m_none, "hit_roll_melee")],
		_count_rolls(m_with, "hit_roll_melee") == _count_rolls(m_none, "hit_roll_melee") + 2)

# ----------------------------------------------------------------------------
# 9. Superior Creation
# ----------------------------------------------------------------------------
func _test_superior_creation() -> void:
	print("\n-- Superior Creation: first-death revival at end of phase --")
	var rules = root.get_node("RulesEngine")

	var board = _make_board({
		"shooter_models": 1,
		"shooter_enhancements": ["Superior Creation"],
	})
	# Kill the bearer (position stays on the dead model)
	board.units["U_SHOOTER"].models[0]["alive"] = false
	board.units["U_SHOOTER"].models[0]["current_wounds"] = 0

	var rec = rules.record_superior_creation_death("U_SHOOTER", board)
	_check("death recorded as applicable", rec.get("applicable", false))
	# Apply the diffs by hand (flags on the unit)
	board.units["U_SHOOTER"].flags["superior_creation_used"] = true
	board.units["U_SHOOTER"].flags["superior_creation_pending"] = {"x": 0.0, "y": 0.0}

	# Second death attempt — once per battle
	var rec2 = rules.record_superior_creation_death("U_SHOOTER", board)
	_check("revival is once per battle", not rec2.get("applicable", false))

	# Scan seeds: both outcomes must occur, and revived placement must be legal
	var revived_count := 0
	var failed_count := 0
	for seed_val in range(1, 13):
		var b = _make_board({
			"shooter_models": 1,
			"shooter_enhancements": ["Superior Creation"],
			"distance_inches": 0.75,  # enemy inside Engagement Range of the death spot
		})
		b.units["U_SHOOTER"].models[0]["alive"] = false
		b.units["U_SHOOTER"].models[0]["current_wounds"] = 0
		b.units["U_SHOOTER"].flags["superior_creation_pending"] = {"x": 0.0, "y": 0.0}
		b.units["U_SHOOTER"].flags["superior_creation_used"] = true
		rules.set_test_seed(seed_val)
		var rng = rules.RNGService.new()
		var res = rules.resolve_superior_creation_revivals(b, rng)
		var cleared := false
		var revived := false
		var new_pos = null
		for d in res.get("diffs", []):
			var path: String = d.get("path", "")
			if path.ends_with("superior_creation_pending") and d.get("value") == null:
				cleared = true
			if path.ends_with("models.0.alive") and d.get("value") == true:
				revived = true
			if path.ends_with("models.0.position"):
				new_pos = d.get("value")
		_check("seed %d: pending flag consumed" % seed_val, cleared)
		if revived:
			revived_count += 1
			# Placement: must be at least 1" edge-to-edge from the enemy at 0.75"
			var meas = root.get_node("Measurement")
			var enemy_pos = Vector2(0.75 * 40.0, 0.0)
			var p = Vector2(float(new_pos.get("x", 0)), float(new_pos.get("y", 0)))
			var radius = meas.base_radius_px(32)
			var closest := INF
			for i in range(8):
				var ep2 = Vector2(0.75 * 40.0, float(i * 35))
				var edge = meas.px_to_inches(p.distance_to(ep2) - radius * 2.0)
				closest = min(closest, edge)
			_check("seed %d: revived outside Engagement Range (%.2f\" ≥ 1\")" % [seed_val, closest], closest >= 1.0)
		else:
			failed_count += 1
	_check("some revivals succeed across seeds (2+)", revived_count > 0, "0/12 revived")
	_check("some revivals fail across seeds (roll of 1)", failed_count > 0, "0/12 failed")

# ----------------------------------------------------------------------------
# 10/11. Praesidius + Psyk-out Grenades army-load grants
# ----------------------------------------------------------------------------
func _test_praesidius_and_psyk_out() -> void:
	print("\n-- Praesidius / Psyk-out Grenades: army-load grants --")
	var alm = root.get_node("ArmyListManager")
	var rules = root.get_node("RulesEngine")

	var unit = {
		"id": "U_P", "owner": 1,
		"meta": {
			"name": "Praesidius Bearer",
			"keywords": ["ADEPTUS CUSTODES", "CHARACTER"],
			"abilities": [],
			"enhancements": ["Praesidius"],
		},
		"flags": {}, "models": []
	}
	alm._apply_enhancement_granted_abilities("U_P", unit)
	_check("Praesidius grants Lone Operative", rules.has_lone_operative(unit))
	_check("Praesidius grants Stealth", rules.has_stealth_ability(unit))
	# Idempotent
	alm._apply_enhancement_granted_abilities("U_P", unit)
	_check("grants are idempotent", unit.meta.abilities.size() == 2, str(unit.meta.abilities))

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
	_check("Psyk-out grants EXPLOSIVES (11e dataset keyword)", rules.unit_has_keyword(sos, "EXPLOSIVES"))
	_check("Psyk-out does not add extra keywords", not rules.unit_has_keyword(sos, "GRENADES"))

# ----------------------------------------------------------------------------
# 11b. Admonimortis (10e stopgap): +3S / +1AP / +1D on the bearer's melee weapons
# ----------------------------------------------------------------------------
func _test_admonimortis_stopgap() -> void:
	print("\n-- Admonimortis (10e stopgap): melee +3 Strength, +1 AP, +1 Damage --")
	var rules = root.get_node("RulesEngine")
	_check("has_admonimortis detects the enhancement",
		rules.has_admonimortis({"meta": {"enhancements": ["Admonimortis"]}}))
	_check("has_admonimortis false without it",
		not rules.has_admonimortis({"meta": {"enhancements": []}}))

	# choppa is S4 vs T4 (4+ to wound); +3 S makes it S7 ≥ 2T? no — 7 < 8, but
	# S7 > T4 wounds on 3+. Same seed: wound successes must rise, save
	# successes must fall (AP -1 → -2), casualties/damage must not decrease.
	var m_plain = _melee(_make_board({"shooter_models": 4, "distance_inches": 0.5}), 2024)
	var m_admon = _melee(_make_board({
		"shooter_models": 4, "distance_inches": 0.5,
		"shooter_enhancements": ["Admonimortis"],
	}), 2024)
	var w_plain = _count_successes(m_plain, "wound_roll_melee")
	var w_admon = _count_successes(m_admon, "wound_roll_melee")
	_check("+3 Strength raises melee wounds (%d > %d)" % [w_admon, w_plain], w_admon > w_plain)
	var ap_plain = _count_field(m_plain, "save_roll_melee", "ap")
	var ap_admon = _count_field(m_admon, "save_roll_melee", "ap")
	_check("+1 AP applied to melee saves (ap %d → %d)" % [ap_plain, ap_admon], ap_admon == ap_plain + 1)

# ----------------------------------------------------------------------------
# 12. Encircling Hunter
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
# 13. Skin-Crawling Disorientation
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

# ----------------------------------------------------------------------------
# 14. Gilded Champion
# ----------------------------------------------------------------------------
func _test_gilded_champion() -> void:
	print("\n-- Gilded Champion: restore a spent once-per-battle ability --")
	var alm = root.get_node("ArmyListManager")
	var sm = root.get_node("StratagemManager")
	var uam = root.get_node("UnitAbilityManager")

	# Fresh Lions army for player 1
	var lions = alm.load_army_list("Adeptus_Custodes_1995_Mar_7", 1)
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

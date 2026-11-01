extends SceneTree

# T05 — hover-forecast tooltip for shooting (design guidelines §7).
#
# 1. RulesEngine.preview_attack: the expected-value chain for one weapon vs one
#    target (attacks -> hits -> wounds -> unsaved -> damage) and the 11e
#    modifiers the live roll applies:
#      * benefit of cover worsens BS by 1 (13.08; STEALTH grants it, 24.33;
#        the stratagem_cover flag too) and never improves the save,
#      * [IGNORES COVER] and [TORRENT] skip it; [TORRENT] never scores crits,
#      * [HEAVY] is +1 to the hit roll on the 11e conditions (24.16),
#      * plunging fire improves BS by 1 (22.05),
#      * +1 and -1 to hit cancel (flag semantics, like the live roll),
#      * re-rolling failed hits raises the critical-hit chance too
#        (Sustained Hits), Twin-linked re-rolls wounds,
#      * damage beyond a model's Wounds does not kill a second model,
#      * at 10e STEALTH is a -1 to hit and cover is not a BS change.
# 2. ShootingController: _calc_weapon_expected_damage (the P3-114 card / dock /
#    quick-assign forecast) is now the same numbers; compute_hover_forecast
#    returns the hover-hook shape {weapon_id, target_id, bs, s, t, ap, d,
#    expected_wounds, ...} without touching the hover state, picking the
#    selected weapon row or else the best weapon; the test_hover_target_id
#    seam drives current_hover_forecast and the HoverForecast node.
# 3. HoverForecast: the card's rows (title, profile, cover row, rolls, chain,
#    result, footer) and hide.
#
# Usage: godot --headless --path . -s tests/test_hover_forecast.gd

const HoverForecastScript = preload("res://scripts/HoverForecast.gd")

var passed := 0
var failed := 0


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps


func _init() -> void:
	# Autoloads are added after SceneTree._init — run once they are live.
	call_deferred("_run")


func _run() -> void:
	print("\n=== test_hover_forecast ===\n")
	var gs = root.get_node_or_null("GameState")
	var rules = root.get_node_or_null("RulesEngine")
	_check("GameState + RulesEngine autoloads live", gs != null and rules != null)
	if gs == null or rules == null:
		_finish()
		return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	_test_preview_core(rules)
	_test_preview_cover(rules)
	_test_preview_heavy_plunging(rules)
	_test_preview_rerolls_and_kills(rules)
	_test_preview_edition_10(rules)
	_test_controller(gs, rules)
	_test_card()

	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()


# One shooter model 5" from four target models: in range, unengaged.
func _board(weapons: Array, target_abilities: Array = [], shooter_flags: Dictionary = {},
		target_flags: Dictionary = {}, elevation: float = 0.0, target_wounds: int = 1) -> Dictionary:
	var shooter_model := {"id": "m1", "position": {"x": 100, "y": 100}, "base_mm": 32,
		"base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3}
	if elevation > 0.0:
		shooter_model["elevation_inches"] = elevation
	var targets: Array = []
	for i in range(4):
		targets.append({"id": "m%d" % (i + 1), "position": {"x": 300, "y": 100 + float(i * 35)},
			"base_mm": 32, "base_type": "circular", "alive": true,
			"wounds": target_wounds, "current_wounds": target_wounds})
	return {
		"units": {
			"U_SHOOTER": {"id": "U_SHOOTER", "owner": 1, "flags": shooter_flags,
				"meta": {"name": "Shooters", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 3, "wounds": 3}, "weapons": weapons},
				"models": [shooter_model]},
			"U_TARGET": {"id": "U_TARGET", "owner": 2, "flags": target_flags,
				"meta": {"name": "Targets", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 4, "wounds": target_wounds},
					"abilities": target_abilities},
				"models": targets}},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 2}}


func _gun(name: String, special: String = "", attacks: String = "6", bs: String = "3",
		strength: String = "4", ap: String = "0", damage: String = "1") -> Dictionary:
	return {"name": name, "type": "Ranged", "range": "24", "attacks": attacks,
		"ballistic_skill": bs, "strength": strength, "ap": ap, "damage": damage,
		"special_rules": special}


func _pv(rules, board: Dictionary, weapon_id: String = "test_gun_ranged") -> Dictionary:
	return rules.preview_attack("U_SHOOTER", "U_TARGET", weapon_id, board)


func _test_preview_core(rules) -> void:
	print("-- 1a. preview_attack: plain chain --")
	var b := _board([_gun("Test Gun")])
	var p := _pv(rules, b)
	_check("returns a forecast", not p.is_empty())
	if p.is_empty():
		return
	_check("6 attacks from the one bearer", _near(p.total_attacks, 6.0), str(p.total_attacks))
	_check("BS 3+, no modifiers: bs 3 / hit 3+", p.bs == 3 and p.base_bs == 3 and p.hit_display == "3+",
		"%s %s %s" % [p.bs, p.base_bs, p.hit_display])
	_check("hits = 6 x 4/6 = 4.0", _near(p.expected_hits, 4.0), str(p.expected_hits))
	_check("S4 vs T4 wounds on 4+: 2.0 wound rolls succeed", p.wound_display == "4+" and _near(p.expected_wounds, 2.0),
		"%s %s" % [p.wound_display, p.expected_wounds])
	_check("Sv 4+, AP0: 1.0 unsaved, 1.0 damage, 1.0 model",
		p.best_save == 4 and _near(p.expected_unsaved, 1.0) and _near(p.expected_damage, 1.0) and _near(p.expected_models_killed, 1.0),
		"%s %s %s %s" % [p.best_save, p.expected_unsaved, p.expected_damage, p.expected_models_killed])
	_check("not in cover, no modifier tags", not p.in_cover and p.cover_bs_delta == 0 and (p.active_tags as Array).is_empty(),
		str(p.active_tags))
	_check("unknown shooter -> {}", rules.preview_attack("NOPE", "U_TARGET", "test_gun_ranged", b).is_empty())
	_check("unknown target -> {}", rules.preview_attack("U_SHOOTER", "NOPE", "test_gun_ranged", b).is_empty())
	_check("unknown weapon -> {}", rules.preview_attack("U_SHOOTER", "U_TARGET", "no_such_gun_ranged", b).is_empty())

	print("\n-- 1b. +1 and -1 to hit cancel (flag semantics) --")
	p = _pv(rules, _board([_gun("Test Gun")], [], {"effect_plus_one_hit": true, "effect_minus_one_hit": true}))
	_check("+1 and -1 net 0: hit 3+, 4.0 hits", p.hit_modifier == 0 and p.hit_display == "3+" and _near(p.expected_hits, 4.0),
		"%s %s %s" % [p.hit_modifier, p.hit_display, p.expected_hits])
	p = _pv(rules, _board([_gun("Test Gun")], [], {"effect_plus_one_hit": true}))
	_check("+1 alone: hit 2+ (bs stays 3), 5.0 hits", p.hit_modifier == 1 and p.bs == 3 and p.hit_display == "2+" and _near(p.expected_hits, 5.0),
		"%s %s %s %s" % [p.hit_modifier, p.bs, p.hit_display, p.expected_hits])


func _test_preview_cover(rules) -> void:
	print("\n-- 1c. benefit of cover (11e 13.08) --")
	var p := _pv(rules, _board([_gun("Test Gun")], ["Stealth"]))
	_check("STEALTH target: BS 3+ worsened to 4+ (bs 4, bs_no_cover 3)",
		p.bs == 4 and p.bs_no_cover == 3 and p.base_bs == 3 and p.hit_display == "4+",
		"%s %s %s %s" % [p.bs, p.bs_no_cover, p.base_bs, p.hit_display])
	_check("in_cover, every firing model, delta 1, tagged", p.in_cover and _near(p.cover_fraction, 1.0)
		and p.cover_bs_delta == 1 and "Cover" in p.active_tags, str(p.active_tags))
	_check("hits = 6 x 3/6 = 3.0", _near(p.expected_hits, 3.0), str(p.expected_hits))
	_check("cover does not improve the save at 11e (still 4+)", p.best_save == 4 and p.modified_save == 4,
		"%s %s" % [p.best_save, p.modified_save])
	p = _pv(rules, _board([_gun("Test Gun")], [], {}, {"stratagem_cover": true}))
	_check("stratagem_cover flag (Go to Ground / Smokescreen): bs 4", p.bs == 4 and p.in_cover, "%s %s" % [p.bs, p.in_cover])
	# A 10-model unit: only PREVIEW_COVER_SAMPLE_MAX firing models are terrain-checked,
	# the rest counted at the sampled share — every one sees the STEALTH target in cover.
	var big := _board([_gun("Test Gun")], ["Stealth"])
	for i in range(2, 11):
		big.units["U_SHOOTER"].models.append({"id": "m%d" % i, "position": {"x": 100, "y": 100 + float(i * 35)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3})
	var cache := {}
	p = rules.preview_attack("U_SHOOTER", "U_TARGET", "test_gun_ranged", big, {"cover_cache": cache})
	_check("10 firing models: 60 attacks, all with cover -> bs 4, 30.0 hits",
		_near(p.total_attacks, 60.0) and p.bs == 4 and _near(p.cover_fraction, 1.0) and _near(p.expected_hits, 30.0),
		"%s %s %s %s" % [p.total_attacks, p.bs, p.cover_fraction, p.expected_hits])
	_check("...with at most %d terrain checks (cover_cache entries)" % rules.PREVIEW_COVER_SAMPLE_MAX,
		cache.size() <= rules.PREVIEW_COVER_SAMPLE_MAX and cache.size() > 0, str(cache.size()))
	p = _pv(rules, _board([_gun("Test Gun", "ignores cover")], ["Stealth"]))
	_check("[IGNORES COVER]: bs stays 3, not in cover", p.bs == 3 and not p.in_cover and _near(p.expected_hits, 4.0),
		"%s %s %s" % [p.bs, p.in_cover, p.expected_hits])
	p = _pv(rules, _board([_gun("Test Gun", "torrent, sustained hits 1")], ["Stealth"]))
	_check("[TORRENT]: auto-hit, cover skipped, hit 'Auto'", p.is_torrent and not p.in_cover and p.hit_display == "Auto",
		"%s %s %s" % [p.is_torrent, p.in_cover, p.hit_display])
	_check("[TORRENT] never crits: Sustained Hits adds nothing (6.0 hits)", _near(p.expected_hits, 6.0), str(p.expected_hits))


func _test_preview_heavy_plunging(rules) -> void:
	print("\n-- 1d. [HEAVY] (24.16) and plunging fire (22.05) --")
	var p := _pv(rules, _board([_gun("Test Gun", "heavy")], [], {"remained_stationary": true}))
	_check("stationary: +1 to hit -> hit 2+, 5.0 hits, tagged Heavy",
		p.hit_modifier == 1 and p.hit_display == "2+" and _near(p.expected_hits, 5.0) and "Heavy" in p.active_tags,
		"%s %s %s %s" % [p.hit_modifier, p.hit_display, p.expected_hits, p.active_tags])
	p = _pv(rules, _board([_gun("Test Gun", "heavy")], [], {"moved_max_inches": 2.5}))
	_check("moved 2.5\" (<= 3\"): Heavy still applies", p.hit_modifier == 1, str(p.hit_modifier))
	p = _pv(rules, _board([_gun("Test Gun", "heavy")], [], {"moved_max_inches": 5.0}))
	_check("moved 5\": no Heavy", p.hit_modifier == 0 and not ("Heavy" in p.active_tags), str(p.active_tags))
	p = _pv(rules, _board([_gun("Test Gun", "heavy")], [], {"remained_stationary": true, "set_up_this_turn": true}))
	_check("set up this turn: no Heavy", p.hit_modifier == 0, str(p.hit_modifier))
	p = _pv(rules, _board([_gun("Test Gun", "heavy")], ["Stealth"], {"remained_stationary": true}))
	_check("Heavy + cover: bs 4 (cover) and hit 3+ (Heavy), 4.0 hits",
		p.bs == 4 and p.hit_modifier == 1 and p.hit_display == "3+" and _near(p.expected_hits, 4.0),
		"%s %s %s %s" % [p.bs, p.hit_modifier, p.hit_display, p.expected_hits])
	p = _pv(rules, _board([_gun("Test Gun")], [], {}, {}, 3.0))
	_check("attacker 3\" up: plunging fire improves BS to 2+ (5.0 hits)",
		p.bs == 2 and _near(p.expected_hits, 5.0) and "Plunging Fire" in p.active_tags,
		"%s %s %s" % [p.bs, p.expected_hits, p.active_tags])
	p = _pv(rules, _board([_gun("Test Gun")], ["Stealth"], {}, {}, 3.0))
	_check("plunging fire + cover cancel: bs 3", p.bs == 3 and p.in_cover and _near(p.expected_hits, 4.0),
		"%s %s %s" % [p.bs, p.in_cover, p.expected_hits])


func _test_preview_rerolls_and_kills(rules) -> void:
	print("\n-- 1e. re-rolls, critical hits, overkill --")
	var p := _pv(rules, _board([_gun("Test Gun", "sustained hits 1")], [], {"effect_reroll_hits": "failed"}))
	# P(hit) = 4/6 + 2/6 * 4/6 = 8/9; P(crit) = 1/6 + 2/6 * 1/6 = 2/9.
	_check("re-roll failed hits + SH1: 6 x (8/9 + 2/9) = 6.667 hits",
		_near(p.expected_hits, 6.0 * 10.0 / 9.0), str(p.expected_hits))
	_check("tagged RR Hits + SH 1", "RR Hits" in p.active_tags and "SH 1" in p.active_tags, str(p.active_tags))
	p = _pv(rules, _board([_gun("Test Gun", "twin-linked")]))
	_check("twin-linked: 4.0 hits x (1/2 + 1/2 x 1/2) = 3.0 wounds",
		_near(p.expected_wounds, 3.0) and "Twin-Linked" in p.active_tags, "%s %s" % [p.expected_wounds, p.active_tags])
	p = _pv(rules, _board([_gun("Test Gun", "", "6", "3", "4", "-3", "3")]))
	# AP-3 vs Sv4+ = 7+: no save. 2.0 wounds -> 2.0 unsaved -> 6.0 damage.
	_check("AP-3 leaves no save: 2.0 unsaved, 6.0 damage", p.best_save == 7 and _near(p.expected_unsaved, 2.0)
		and _near(p.expected_damage, 6.0), "%s %s %s" % [p.best_save, p.expected_unsaved, p.expected_damage])
	_check("D3 into 1-wound models: 2.0 models, not 6.0", _near(p.expected_models_killed, 2.0), str(p.expected_models_killed))
	p = _pv(rules, _board([_gun("Test Gun", "", "6", "3", "4", "-3", "1")], [], {}, {}, 0.0, 2))
	_check("D1 into 2-wound models: 2.0 unsaved kill 1.0 model", _near(p.expected_models_killed, 1.0), str(p.expected_models_killed))


func _test_preview_edition_10(rules) -> void:
	print("\n-- 1f. edition 10 keeps the 10e rules --")
	GameConstants.edition = 10
	var p := _pv(rules, _board([_gun("Test Gun")], ["Stealth"]))
	_check("10e STEALTH: -1 to hit (hit 4+), BS unchanged, no cover delta",
		p.bs == 3 and p.hit_modifier == -1 and p.hit_display == "4+" and p.cover_bs_delta == 0,
		"%s %s %s %s" % [p.bs, p.hit_modifier, p.hit_display, p.cover_bs_delta])
	p = _pv(rules, _board([_gun("Test Gun", "heavy")], [], {"remained_stationary": true}))
	_check("10e Heavy: remained stationary -> +1", p.hit_modifier == 1 and "Heavy" in p.active_tags, str(p.active_tags))
	GameConstants.edition = 11


func _test_controller(gs, rules) -> void:
	print("\n-- 2. ShootingController forecast + hover hook --")
	var b := _board([_gun("Test Gun"), _gun("Big Gun", "", "6", "3", "8", "-2", "2")], ["Stealth"])
	gs.state["units"] = b.units
	var sc = load("res://scripts/ShootingController.gd").new()
	sc.active_shooter_id = "U_SHOOTER"
	var card: Dictionary = sc._calc_weapon_expected_damage("test_gun_ranged", "U_TARGET")
	var pv: Dictionary = rules.preview_attack("U_SHOOTER", "U_TARGET", "test_gun_ranged", gs.state)
	_check("P3-114 card numbers == RulesEngine.preview_attack", not card.is_empty()
		and _near(card.expected_hits, pv.expected_hits) and _near(card.expected_damage, pv.expected_damage)
		and card.hit_display == pv.hit_display, "%s vs %s" % [card.get("expected_hits"), pv.get("expected_hits")])
	var card_keys := ["weapon_name", "target_name", "toughness", "save_stat", "invuln", "fnp", "total_attacks",
		"expected_hits", "expected_wounds", "expected_unsaved", "expected_damage", "expected_models_killed",
		"hit_display", "wound_display", "best_save", "active_tags"]
	var missing: Array = []
	for k in card_keys:
		if not card.has(k):
			missing.append(k)
	_check("the card / dock keys are all still there", missing.is_empty(), str(missing))
	_check("the card now shows the cover-worsened hit roll (4+)", card.hit_display == "4+", str(card.hit_display))
	var sliced: Dictionary = sc._calc_weapon_expected_damage("test_gun_ranged", "U_TARGET", 3)
	_check("model_count_override forecasts a 3-bearer slice (18 attacks)", _near(sliced.total_attacks, 18.0), str(sliced.total_attacks))

	var fc = sc.compute_hover_forecast("U_SHOOTER", "U_TARGET")
	_check("compute_hover_forecast returns the hook", fc != null)
	if fc == null:
		sc.free()
		return
	var hook_keys := ["weapon_id", "target_id", "bs", "s", "t", "ap", "d", "expected_wounds"]
	missing = []
	for k in hook_keys:
		if not fc.has(k):
			missing.append(k)
	_check("hook keys {weapon_id, target_id, bs, s, t, ap, d, expected_wounds}", missing.is_empty(), str(missing))
	_check("best weapon picked (Big Gun out-damages Test Gun)", fc.weapon_id == "big_gun_ranged"
		and fc.weapon_choice == "best" and fc.weapons_in_range == 2, "%s %s" % [fc.weapon_id, fc.weapon_choice])
	_check("hook bs 4 = BS 3+ worsened by the target's cover", fc.bs == 4 and fc.in_cover, str(fc.bs))
	_check("hook s/t/ap/d = 8 / 4 / -2 / 2.0", fc.s == 8 and fc.t == 4 and fc.ap == -2 and _near(fc.d, 2.0),
		"%s %s %s %s" % [fc.s, fc.t, fc.ap, fc.d])
	_check("hook expected_wounds > 0 and all-weapons total covers both guns",
		fc.expected_wounds > 0.0 and fc.all_weapons_damage > fc.expected_damage, "%s %s" % [fc.expected_wounds, fc.all_weapons_damage])
	_check("compute_hover_forecast leaves current_hover_forecast null", sc.current_hover_forecast == null)
	sc.selected_weapon_id = "test_gun_ranged"
	fc = sc.compute_hover_forecast("U_SHOOTER", "U_TARGET")
	_check("a selected weapon row is described instead", fc.weapon_id == "test_gun_ranged" and fc.weapon_choice == "selected",
		"%s %s" % [fc.weapon_id, fc.weapon_choice])
	sc.selected_weapon_id = ""
	_check("unknown shooter -> null", sc.compute_hover_forecast("NOPE", "U_TARGET") == null)
	# "Best" = most wounds actually removed: against 1-wound models a many-shot
	# gun beats a big-damage one whose extra damage per model is lost.
	gs.state["units"] = _board([_gun("Blaze Gun", "", "2", "3", "12", "-3", "6"),
		_gun("Spinner", "", "8", "3", "5", "0", "1")]).units
	var horde = sc.compute_hover_forecast("U_SHOOTER", "U_TARGET")
	var blaze: Dictionary = rules.preview_attack("U_SHOOTER", "U_TARGET", "blaze_gun_ranged", gs.state)
	_check("vs a 1-wound horde the Spinner (1.78 wounds off) beats the Blaze Gun (6.7 raw damage, 1.11 off)",
		horde != null and horde.weapon_id == "spinner_ranged" and blaze.expected_damage > horde.expected_damage
		and _near(blaze.expected_effective_damage, 10.0 / 9.0) and _near(horde.expected_effective_damage, 16.0 / 9.0),
		"%s blaze raw %.3f eff %.3f / spinner eff %.3f" % [horde.get("weapon_id") if horde != null else "null",
		blaze.get("expected_damage", 0.0), blaze.get("expected_effective_damage", 0.0),
		horde.get("expected_effective_damage", 0.0) if horde != null else 0.0])
	gs.state["units"] = b.units
	_check("empty ids -> null", sc.compute_hover_forecast("", "") == null)

	# The task's seam: test_hover_target_id drives the real hover path.
	sc.eligible_targets = {"U_TARGET": {"weapons_in_range": ["test_gun_ranged", "big_gun_ranged"], "unit_name": "Targets"}}
	sc.test_hover_target_id = "U_TARGET"
	_check("seam: current_hover_forecast set for the hovered unit", sc.current_hover_forecast != null
		and str(sc.current_hover_forecast.get("target_id", "")) == "U_TARGET")
	var panel = sc.get_node_or_null("HoverForecast")
	_check("seam: HoverForecast node built and visible", panel != null and panel.visible)
	if panel != null:
		_check("seam: card shows the cover row 'BS 3+ -> 4+'", panel.get_node("Body/CoverRow").visible
			and "BS 3+ → 4+" in str(panel.get_node("Body/CoverRow/CoverLabel").text),
			str(panel.get_node("Body/CoverRow/CoverLabel").text))
	sc.test_hover_target_id = ""
	_check("seam '' ends the hover: forecast null, card hidden", sc.current_hover_forecast == null
		and (panel == null or not panel.visible))
	sc.test_hover_target_id = "U_SHOOTER"
	_check("a unit that is not an eligible target gets no card", sc.current_hover_forecast == null)
	sc.free()


func _test_card() -> void:
	print("\n-- 3. HoverForecast card rows --")
	var card = HoverForecastScript.new()
	var fc := {"weapon_name": "Twin adrathic destructor", "target_name": "Kommandos", "target_owner": 2,
		"attacks": 1.0, "bs": 3, "bs_no_cover": 2, "is_torrent": false, "in_cover": true, "cover_fraction": 1.0,
		"cover_bs_delta": 1, "s": 6, "t": 5, "ap": -2, "damage_raw": "3", "best_save": 7, "invuln": 0,
		"modified_save": 7, "hit_display": "3+", "wound_display": "3+", "expected_hits": 0.67,
		"expected_wounds": 0.59, "expected_unsaved": 0.59, "expected_damage": 1.78,
		"expected_models_killed": 0.59, "active_tags": ["Cover", "Twin-Linked"],
		"weapon_choice": "selected", "weapons_in_range": 3, "all_weapons_damage": 5.1}
	card.show_forecast(fc, Vector2(500, 500))
	_check("named HoverForecast, visible after show_forecast", card.name == "HoverForecast" and card.visible)
	var title: String = card.get_node("Body/Title").get_parsed_text()
	_check("title: weapon -> target", "Twin adrathic destructor" in title and "Kommandos" in title and "→" in title, title)
	var stats: String = card.get_node("Body/Stats").get_parsed_text()
	_check("profile row: A 1, BS 3+, S 6 vs T 5, AP -2, D 3",
		"A 1" in stats and "BS 3+" in stats and "S 6 vs T 5" in stats and "AP -2" in stats and "D 3" in stats, stats)
	_check("cover row: icon + 'Benefit of cover: BS 2+ → 3+'", card.get_node("Body/CoverRow").visible
		and card.get_node("Body/CoverRow/CoverIcon") != null
		and card.get_node("Body/CoverRow/CoverLabel").text == "Benefit of cover: BS 2+ → 3+",
		card.get_node("Body/CoverRow/CoverLabel").text)
	var rolls: String = card.get_node("Body/Rolls").get_parsed_text()
	_check("rolls row: Hit 3+ / Wound 3+ / Save none", "Hit 3+" in rolls and "Wound 3+" in rolls and "Save none" in rolls, rolls)
	var result: String = card.get_node("Body/Result").get_parsed_text()
	_check("result row: ≈ 1.8 damage", "1.8 damage" in result, result)
	var footer: String = card.get_node("Body/Footer").get_parsed_text()
	_check("footer: tags without Cover, selected weapon of 3, all-weapons total",
		"Twin-Linked" in footer and not ("Cover" in footer) and "Selected weapon" in footer and "5.1" in footer, footer)
	fc["in_cover"] = false
	fc["cover_bs_delta"] = 0
	card.show_forecast(fc, Vector2(500, 500))
	_check("no cover -> no cover row", not card.get_node("Body/CoverRow").visible)
	card.hide_forecast()
	_check("hide_forecast hides it and forgets the forecast", not card.visible and card.forecast.is_empty())
	card.free()


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

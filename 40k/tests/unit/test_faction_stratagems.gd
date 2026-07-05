extends "res://addons/gut/test.gd"

# Tests for Faction Stratagem Loading (Step 9)
#
# 11e note: data CSVs are generated from the 40kdc dataset by
# scripts/40kdc/generate-stratagems.mjs. Real-row expectations below cite
# 40kdc ids (e.g. harmonised-exorcism-chorus-of-condemnation).
#
# Tests verify:
# 1. CSV parsing (pipe-delimited, BOM handling, header extraction)
# 2. Faction code lookup (name → code mapping)
# 3. Stratagem description parsing (HTML stripping, WHEN/TARGET/EFFECT extraction)
# 4. Timing parsing (turn, phase, trigger inference)
# 5. Target condition parsing (keyword extraction, special conditions)
# 6. Effect mapping (description text → EffectPrimitives effect types)
# 7. Restriction parsing (once-per-battle, once-per-turn, once-per-phase)
# 8. Stratagem ID generation (unique, deterministic)
# 9. Player ownership filtering in StratagemManager
# 10. Faction stratagem availability in reactive flows
# 11. Unit target matching for faction stratagems


# ==========================================
# Helpers
# ==========================================

var _loader: FactionStratagemLoaderData

func before_each():
	_loader = FactionStratagemLoaderData.new()

func _make_unit(keywords: Array = ["INFANTRY"], owner: int = 1, flags: Dictionary = {}) -> Dictionary:
	return {
		"meta": {"name": "Test Unit", "keywords": keywords},
		"models": [
			{"id": "m1", "alive": true, "wounds": 2, "current_wounds": 2},
			{"id": "m2", "alive": true, "wounds": 2, "current_wounds": 2}
		],
		"flags": flags,
		"owner": owner
	}


# ==========================================
# Section 1: CSV Parsing
# ==========================================

func test_parse_csv_returns_empty_for_missing_file():
	"""parse_csv_file should return empty array for non-existent file."""
	var result = FactionStratagemLoaderData.parse_csv_file("res://data/nonexistent.csv")
	assert_eq(result.size(), 0, "Should return empty for missing file")

func test_parse_csv_handles_pipe_delimiter():
	"""parse_csv_file should correctly parse pipe-delimited data."""
	# We test by parsing the actual Factions.csv file
	var rows = FactionStratagemLoaderData.parse_csv_file("res://data/Factions.csv")
	assert_true(rows.size() > 0, "Should parse at least one faction")

	# Check that the first row has the expected fields
	var first = rows[0]
	assert_true(first.has("id"), "Row should have 'id' field")
	assert_true(first.has("name"), "Row should have 'name' field")

func test_parse_csv_strips_bom():
	"""parse_csv_file should handle UTF-8 BOM in first header."""
	var rows = FactionStratagemLoaderData.parse_csv_file("res://data/Factions.csv")
	if rows.size() > 0:
		# The first header should be 'id', not '\uFEFFid'
		assert_true(rows[0].has("id"), "BOM should be stripped from first header")


# ==========================================
# Section 2: Faction Code Lookup
# ==========================================

func test_faction_code_lookup_space_marines():
	"""Should map 'Space Marines' to 'SM'."""
	_loader.load_faction_codes()
	assert_eq(_loader.get_faction_code("Space Marines"), "SM")

func test_faction_code_lookup_adeptus_custodes():
	"""Should map 'Adeptus Custodes' to 'AC'."""
	_loader.load_faction_codes()
	assert_eq(_loader.get_faction_code("Adeptus Custodes"), "AC")

func test_faction_code_lookup_orks():
	"""Should map 'Orks' to 'ORK'."""
	_loader.load_faction_codes()
	assert_eq(_loader.get_faction_code("Orks"), "ORK")

func test_faction_code_lookup_case_insensitive():
	"""Lookup should be case-insensitive."""
	_loader.load_faction_codes()
	assert_eq(_loader.get_faction_code("space marines"), "SM")

func test_faction_code_lookup_unknown_returns_empty():
	"""Unknown faction should return empty string."""
	_loader.load_faction_codes()
	assert_eq(_loader.get_faction_code("Unknown Faction"), "")

func test_faction_name_reverse_lookup():
	"""Should map code back to name."""
	_loader.load_faction_codes()
	# 11e (40kdc) Factions.csv names the SM faction "Adeptus Astartes";
	# forward lookups for "Space Marines" still resolve via the alias map.
	assert_eq(_loader.get_faction_name("SM"), "Adeptus Astartes")
	assert_eq(_loader.get_faction_name("AC"), "Adeptus Custodes")


# ==========================================
# Section 3: Description Parsing
# ==========================================

func test_strip_html_removes_tags():
	"""HTML tags should be stripped from description."""
	var html = '<b>WHEN:</b> Your Shooting phase.<br><br><b>TARGET:</b> One <span class="kwb">ADEPTUS</span> <span class="kwb">ASTARTES</span> unit.'
	var result = FactionStratagemLoaderData._strip_html(html)
	assert_false("<b>" in result, "Should not contain <b> tags")
	assert_false("<span" in result, "Should not contain <span> tags")
	assert_true("WHEN:" in result, "Should preserve text content")

func test_parse_description_extracts_sections():
	"""Should extract WHEN, TARGET, EFFECT sections from description."""
	var html = '<b>WHEN:</b> Your Shooting phase.<br><br><b>TARGET:</b> One ADEPTUS ASTARTES unit.<br><br><b>EFFECT:</b> Ranged weapons have [IGNORES COVER].'
	var result = FactionStratagemLoaderData._parse_description(html)
	assert_true(result.when_text != "", "Should extract WHEN text")
	assert_true(result.target_text != "", "Should extract TARGET text")
	assert_true(result.effect_text != "", "Should extract EFFECT text")
	assert_true("Shooting phase" in result.when_text, "WHEN should contain phase info")
	assert_true("IGNORES COVER" in result.effect_text, "EFFECT should contain effect info")

func test_parse_description_with_restrictions():
	"""Should extract RESTRICTIONS section when present."""
	var html = '<b>WHEN:</b> Phase.<br><br><b>TARGET:</b> Unit.<br><br><b>EFFECT:</b> Effect text.<br><br><b>RESTRICTIONS:</b> Cannot use once per battle.'
	var result = FactionStratagemLoaderData._parse_description(html)
	assert_true(result.restriction_text != "", "Should extract RESTRICTIONS text")


# ==========================================
# Section 4: Timing Parsing
# ==========================================

func test_timing_your_turn():
	"""'Your turn' should map to turn='your'."""
	var timing = _loader._parse_timing("Your turn", "Shooting phase", "")
	assert_eq(timing.turn, "your")

func test_timing_opponent_turn():
	"""\"Opponent's turn\" should map to turn='opponent'."""
	var timing = _loader._parse_timing("Opponent's turn", "Shooting phase", "")
	assert_eq(timing.turn, "opponent")

func test_timing_either_turn():
	"""'Either player's turn' should map to turn='either'."""
	var timing = _loader._parse_timing("Either player's turn", "Any phase", "")
	assert_eq(timing.turn, "either")

func test_phase_normalization_shooting():
	"""'Shooting phase' should normalize to 'shooting'."""
	var timing = _loader._parse_timing("Your turn", "Shooting phase", "")
	assert_eq(timing.phase, "shooting")

func test_phase_normalization_fight():
	"""'Fight phase' should normalize to 'fight'."""
	var timing = _loader._parse_timing("Your turn", "Fight phase", "")
	assert_eq(timing.phase, "fight")

func test_phase_normalization_shooting_or_fight():
	"""'Shooting or Fight phase' should normalize to 'shooting_or_fight'."""
	var timing = _loader._parse_timing("Your turn", "Shooting or Fight phase", "")
	assert_eq(timing.phase, "shooting_or_fight")

func test_phase_normalization_any():
	"""'Any phase' should normalize to 'any'."""
	var timing = _loader._parse_timing("Your turn", "Any phase", "")
	assert_eq(timing.phase, "any")

func test_trigger_inference_after_target_selected():
	"""Description with 'selected its targets' should infer after_target_selected trigger."""
	var desc = "just after an enemy unit has selected its targets"
	var timing = _loader._parse_timing("Opponent's turn", "Shooting phase", desc)
	assert_eq(timing.trigger, "after_target_selected")

func test_trigger_inference_after_enemy_fought():
	"""Description with 'enemy unit has fought' should infer after_enemy_fought."""
	var desc = "just after an enemy unit has fought"
	var timing = _loader._parse_timing("Either player's turn", "Fight phase", desc)
	assert_eq(timing.trigger, "after_enemy_fought")


# ==========================================
# Section 5: Target Condition Parsing
# ==========================================

func test_target_infantry_keyword():
	"""Target with INFANTRY should include keyword condition."""
	var target = _loader._parse_target("One INFANTRY unit from your army")
	assert_true("keyword:INFANTRY" in target.conditions, "Should detect INFANTRY keyword")
	assert_eq(target.owner, "friendly")

func test_target_adeptus_astartes_keyword():
	"""Target with ADEPTUS ASTARTES should include faction keyword."""
	var target = _loader._parse_target("One ADEPTUS ASTARTES unit from your army")
	assert_true("keyword:ADEPTUS ASTARTES" in target.conditions)

func test_target_selected_as_target():
	"""'Was selected as the target' should add is_target_of_attack condition."""
	var target = _loader._parse_target("One unit that was selected as the target of attacks")
	assert_true("is_target_of_attack" in target.conditions)

func test_target_enemy_unit():
	"""Target referencing enemy should set owner to 'enemy'."""
	var target = _loader._parse_target("One enemy unit within 6\"")
	assert_eq(target.owner, "enemy")


# ==========================================
# Section 6: Effect Mapping
# ==========================================

func test_effect_worsen_ap():
	"""'Worsen the Armour Penetration' should map to worsen_ap effect."""
	var effects = _loader._map_effects("worsen the Armour Penetration characteristic of that attack by 1")
	assert_eq(effects.size(), 1)
	assert_eq(effects[0].type, EffectPrimitivesData.WORSEN_AP)
	assert_eq(effects[0].value, 1)

func test_effect_minus_one_wound():
	"""'Subtract 1 from the Wound roll' should map to minus_one_wound."""
	var effects = _loader._map_effects("subtract 1 from the Wound roll")
	assert_eq(effects.size(), 1)
	assert_eq(effects[0].type, EffectPrimitivesData.MINUS_ONE_WOUND)

func test_effect_plus_one_hit():
	"""'Add 1 to the Hit roll' should map to plus_one_hit."""
	var effects = _loader._map_effects("add 1 to the Hit roll")
	assert_eq(effects.size(), 1)
	assert_eq(effects[0].type, EffectPrimitivesData.PLUS_ONE_HIT)

func test_effect_minus_one_hit():
	"""'Subtract 1 from the Hit roll' should map to minus_one_hit."""
	var effects = _loader._map_effects("subtract 1 from the Hit roll")
	assert_eq(effects.size(), 1)
	assert_eq(effects[0].type, EffectPrimitivesData.MINUS_ONE_HIT)

func test_effect_grant_ignores_cover():
	"""'[IGNORES COVER] ability' should map to grant_ignores_cover."""
	var effects = _loader._map_effects("ranged weapons equipped by models in your unit have the [IGNORES COVER] ability")
	var found = false
	for e in effects:
		if e.type == EffectPrimitivesData.GRANT_IGNORES_COVER:
			found = true
	assert_true(found, "Should include grant_ignores_cover")

func test_effect_grant_lance():
	"""'[LANCE] ability' should map to grant_lance."""
	var effects = _loader._map_effects("melee weapons have the [LANCE] ability")
	var found = false
	for e in effects:
		if e.type == EffectPrimitivesData.GRANT_LANCE:
			found = true
	assert_true(found, "Should include grant_lance")

func test_effect_grant_lethal_hits():
	"""'[LETHAL HITS] ability' should map to grant_lethal_hits."""
	var effects = _loader._map_effects("ranged weapons have the [LETHAL HITS] ability")
	var found = false
	for e in effects:
		if e.type == EffectPrimitivesData.GRANT_LETHAL_HITS:
			found = true
	assert_true(found, "Should include grant_lethal_hits")

func test_effect_grant_sustained_hits():
	"""'[SUSTAINED HITS' should map to grant_sustained_hits."""
	var effects = _loader._map_effects("ranged weapons have the [SUSTAINED HITS 1] ability")
	var found = false
	for e in effects:
		if e.type == EffectPrimitivesData.GRANT_SUSTAINED_HITS:
			found = true
	assert_true(found, "Should include grant_sustained_hits")

func test_effect_grant_fnp():
	"""'Feel No Pain 4+' should map to grant_fnp with value 4."""
	var effects = _loader._map_effects("models in your unit have the Feel No Pain 4+ ability")
	var found = false
	for e in effects:
		if e.type == EffectPrimitivesData.GRANT_FNP:
			found = true
			assert_eq(e.value, 4, "FNP value should be 4")
	assert_true(found, "Should include grant_fnp")

func test_effect_crit_hit_on_5():
	"""'Hit roll of 5+ scores a Critical Hit' should map to crit_hit_on with value 5."""
	var effects = _loader._map_effects("an unmodified hit roll of 5+ scores a Critical Hit")
	var found = false
	for e in effects:
		if e.type == EffectPrimitivesData.CRIT_HIT_ON:
			found = true
			assert_eq(e.value, 5)
	assert_true(found, "Should include crit_hit_on")

func test_effect_minus_damage():
	"""'Subtract 1 from the Damage characteristic' should map to minus_damage."""
	var effects = _loader._map_effects("subtract 1 from the Damage characteristic of that attack")
	assert_eq(effects.size(), 1)
	assert_eq(effects[0].type, EffectPrimitivesData.MINUS_DAMAGE)
	assert_eq(effects[0].value, 1)

func test_effect_fall_back_and_shoot():
	"""'Eligible to shoot...Fell Back' should map to fall_back_and_shoot."""
	var effects = _loader._map_effects("that unit is eligible to shoot and declare a charge in a turn in which it Fell Back")
	var found_shoot = false
	var found_charge = false
	for e in effects:
		if e.type == EffectPrimitivesData.FALL_BACK_AND_SHOOT:
			found_shoot = true
		if e.type == EffectPrimitivesData.FALL_BACK_AND_CHARGE:
			found_charge = true
	assert_true(found_shoot, "Should include fall_back_and_shoot")
	assert_true(found_charge, "Should include fall_back_and_charge")

func test_effect_reroll_hit():
	"""'Re-roll the Hit roll' should map to reroll_hits."""
	var effects = _loader._map_effects("you can re-roll the Hit roll")
	var found = false
	for e in effects:
		if e.type == EffectPrimitivesData.REROLL_HITS:
			found = true
			assert_eq(e.scope, "all")
	assert_true(found, "Should include reroll_hits")

func test_effect_reroll_wound():
	"""'Re-roll the Wound roll' should map to reroll_wounds."""
	var effects = _loader._map_effects("you can re-roll the Wound roll")
	var found = false
	for e in effects:
		if e.type == EffectPrimitivesData.REROLL_WOUNDS:
			found = true
	assert_true(found, "Should include reroll_wounds")

func test_effect_unmapped_falls_back_to_custom():
	"""Unrecognized effects should get custom:unmapped type."""
	var effects = _loader._map_effects("do something completely unique that has no pattern")
	assert_eq(effects.size(), 1)
	assert_true(effects[0].type.begins_with("custom:"), "Unmapped effects should use custom: prefix")

func test_effect_multiple_effects_mapped():
	"""Text with multiple recognizable effects should map all of them."""
	var effects = _loader._map_effects("add 1 to the Hit roll. If below half-strength, add 1 to the Wound roll as well")
	var has_hit = false
	var has_wound = false
	for e in effects:
		if e.type == EffectPrimitivesData.PLUS_ONE_HIT:
			has_hit = true
		if e.type == EffectPrimitivesData.PLUS_ONE_WOUND:
			has_wound = true
	assert_true(has_hit, "Should map +1 to hit")
	assert_true(has_wound, "Should map +1 to wound")


# ==========================================
# Section 7: Restriction Parsing
# ==========================================

func test_restriction_once_per_battle():
	"""'once per battle' should set once_per=battle."""
	var r = _loader._parse_restrictions("You cannot use this Stratagem more than once per battle.", "Battle Tactic")
	assert_eq(r.once_per, "battle")

func test_restriction_once_per_turn():
	"""'once per turn' should set once_per=turn."""
	var r = _loader._parse_restrictions("Once per turn.", "Strategic Ploy")
	assert_eq(r.once_per, "turn")

func test_restriction_default_once_per_phase():
	"""Default restriction should be once per phase."""
	var r = _loader._parse_restrictions("", "Battle Tactic")
	assert_eq(r.once_per, "phase")

func test_restriction_epic_deed_default_once_per_battle():
	"""Epic Deed stratagems should default to once per battle."""
	var r = _loader._parse_restrictions("", "Epic Deed Stratagem")
	assert_eq(r.once_per, "battle")


# ==========================================
# Section 8: Stratagem ID Generation
# ==========================================

func test_stratagem_id_format():
	"""Generated IDs should follow the faction_code_detachment_name pattern."""
	var id = _loader._generate_stratagem_id("SM", "Gladius Task Force", "STORM OF FIRE")
	assert_true(id.begins_with("faction_sm_"), "ID should start with faction_sm_")
	assert_true("storm_of_fire" in id, "ID should contain normalized name")

func test_stratagem_id_strips_special_chars():
	"""ID generation should strip apostrophes and exclamation marks."""
	var id = _loader._generate_stratagem_id("ORK", "War Horde", "'ARD AS NAILS")
	assert_false("'" in id, "Should not contain apostrophe")
	assert_true("ard_as_nails" in id, "Should contain cleaned name")

func test_stratagem_id_no_detachment():
	"""ID without detachment should skip detachment segment."""
	var id = _loader._generate_stratagem_id("SM", "", "STORM OF FIRE")
	assert_eq(id, "faction_sm_storm_of_fire")


# ==========================================
# Section 9: Full CSV Loading Integration
# ==========================================

func test_load_faction_stratagems_ac_shield_host():
	"""Should load Shield Host stratagems for Adeptus Custodes."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Adeptus Custodes", "Shield Host")
	assert_true(strats.size() > 0, "Should load at least one stratagem")
	# Should find specific known stratagems
	var found_alchemy = false
	for s in strats:
		if "ARCANE GENETIC ALCHEMY" in s.name:
			found_alchemy = true
			assert_eq(s.cp_cost, 1)
			assert_eq(s.faction_id, "AC")
			assert_eq(s.detachment, "Shield Host")
	assert_true(found_alchemy, "Should find ARCANE GENETIC ALCHEMY")

func test_load_faction_stratagems_sm_gladius():
	"""Should load Gladius Task Force stratagems for Space Marines."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	assert_true(strats.size() > 0, "Should load at least one stratagem")
	var found_storm = false
	for s in strats:
		if "STORM OF FIRE" in s.name:
			found_storm = true
			assert_eq(s.cp_cost, 1)
			assert_eq(s.faction_id, "SM")
	assert_true(found_storm, "Should find STORM OF FIRE")

func test_load_faction_stratagems_skips_boarding_actions():
	"""Should skip Boarding Actions detachment stratagems."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	for s in strats:
		assert_false("Boarding Actions" in s.get("type", ""), "Should not include Boarding Actions stratagems")

func test_loaded_stratagem_has_required_fields():
	"""Each loaded stratagem should have all required fields."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Adeptus Custodes", "Shield Host")
	for s in strats:
		assert_true(s.has("id"), "Should have id")
		assert_true(s.has("name"), "Should have name")
		assert_true(s.has("cp_cost"), "Should have cp_cost")
		assert_true(s.has("timing"), "Should have timing")
		assert_true(s.has("target"), "Should have target")
		assert_true(s.has("effects"), "Should have effects")
		assert_true(s.has("restrictions"), "Should have restrictions")
		assert_true(s.has("faction_id"), "Should have faction_id")
		assert_true(s.has("detachment"), "Should have detachment")
		assert_true(s.has("implemented"), "Should have implemented flag")

func test_unknown_faction_returns_empty():
	"""Unknown faction should return no stratagems."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Unknown", "Unknown")
	assert_eq(strats.size(), 0)


# ==========================================
# Section 10: Effect Mapping on Real Stratagems (11e 40kdc data)
# ==========================================
# The 11e CSVs are generated from the 40kdc dataset
# (scripts/40kdc/generate-stratagems.mjs), which contains NO GW rules prose.
# Stratagems whose 40kdc ability-DSL compiles to EffectPrimitives carry a
# pre-compiled effects_json column; the rest are display-only rows whose
# effects fall back to "custom:*" (implemented=false).

func _find_strat(strats: Array, name_fragment: String):
	for s in strats:
		if name_fragment in s.name:
			return s
	return null

func test_harmonised_exorcism_effects_json_plus_one_hit():
	"""HARMONISED EXORCISM (AS Chorus of Condemnation) ships a compiled
	effects_json column (40kdc ability roll-modifier hit +1) that the loader
	must pass through as plus_one_hit and mark implemented."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Adepta Sororitas", "Chorus of Condemnation")
	var he = _find_strat(strats, "HARMONISED EXORCISM")
	assert_not_null(he, "Should find HARMONISED EXORCISM")
	if he:
		var has_plus_hit = false
		for e in he.effects:
			if e.type == EffectPrimitivesData.PLUS_ONE_HIT:
				has_plus_hit = true
		assert_true(has_plus_hit, "Should have plus_one_hit effect from effects_json")
		assert_true(he.implemented, "Should be marked as implemented")

func test_sanctified_blows_effects_json_multi_effect():
	"""SANCTIFIED BLOWS (AS Sacred Champions) compiles to plus_attacks +
	plus_strength_melee (40kdc sequence of two stat-modifiers); values must
	arrive as ints (JSON floats normalised by the loader)."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Adepta Sororitas", "Sacred Champions")
	var sb = _find_strat(strats, "SANCTIFIED BLOWS")
	assert_not_null(sb, "Should find SANCTIFIED BLOWS")
	if sb:
		var has_attacks = false
		var has_strength = false
		for e in sb.effects:
			if e.type == EffectPrimitivesData.PLUS_ATTACKS:
				has_attacks = true
				assert_eq(e.value, 1, "plus_attacks value should be int 1")
				assert_eq(e.scope, "melee", "plus_attacks should be melee-scoped")
			if e.type == EffectPrimitivesData.PLUS_STRENGTH_MELEE:
				has_strength = true
		assert_true(has_attacks, "Should have plus_attacks effect")
		assert_true(has_strength, "Should have plus_strength_melee effect")
		assert_true(sb.implemented, "Should be marked as implemented")

func test_faithful_fortitude_effects_json_fnp():
	"""FAITHFUL FORTITUDE (AS Sacred Champions) compiles to
	grant_fnp_psychic_mortal 5 (40kdc feel-no-pain threshold 5, scope mortal)."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Adepta Sororitas", "Sacred Champions")
	var ff = _find_strat(strats, "FAITHFUL FORTITUDE")
	assert_not_null(ff, "Should find FAITHFUL FORTITUDE")
	if ff:
		var has_fnp = false
		for e in ff.effects:
			if e.type == EffectPrimitivesData.GRANT_FNP_PSYCHIC_MORTAL:
				has_fnp = true
				assert_eq(e.value, 5, "FNP value should be 5")
		assert_true(has_fnp, "Should have grant_fnp_psychic_mortal effect")

func test_p0_rows_display_only_without_curated_effects():
	"""Stratagems with no 40kdc ability-DSL AND no curated effects_json load
	as display-only rows (custom:* effects, implemented=false). The shipped
	detachments (War Horde / Shield Host) now carry curated effects_json in
	generate-stratagems.mjs, so only detachments the game doesn't ship armies
	for stay display-only."""
	_loader.load_faction_codes()
	var gladius = _loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	var first_co = _loader.load_faction_stratagems("Space Marines", "1st Company Task Force")

	var expected = [
		[gladius, "ARMOUR OF CONTEMPT"],
		[gladius, "STORM OF FIRE"],
		[gladius, "HONOUR THE CHAPTER"],
		[first_co, "LEGENDARY FORTITUDE"],
	]
	for pair in expected:
		var s = _find_strat(pair[0], pair[1])
		assert_not_null(s, "Should find %s in 11e CSV" % pair[1])
		if s:
			assert_true(s.effects.size() > 0, "%s should still carry a (custom) effect entry" % pair[1])
			assert_true(String(s.effects[0].get("type", "")).begins_with("custom:"),
				"%s has no 40kdc ability-DSL — expected custom:* placeholder effect" % pair[1])
			assert_false(s.implemented, "%s should be display-only (not implemented)" % pair[1])

func test_shipped_detachment_stratagems_fully_implemented():
	"""War Horde and Shield Host (the detachments the game ships armies for)
	carry curated effects_json — every stratagem must load mechanically
	implemented with the expected primitive."""
	_loader.load_faction_codes()
	var war_horde = _loader.load_faction_stratagems("Orks", "War Horde")
	var shield_host = _loader.load_faction_stratagems("Adeptus Custodes", "Shield Host")
	assert_eq(war_horde.size(), 6, "War Horde should have 6 stratagems")
	assert_eq(shield_host.size(), 6, "Shield Host should have 6 stratagems")
	for s in war_horde + shield_host:
		assert_true(s.get("implemented", false), "%s should be implemented" % s.get("name", "?"))

	var expected_effects = {
		"UNBRIDLED CARNAGE": "crit_hit_on",
		"ARD AS NAILS": "minus_one_wound_defense",
		"MOB RULE": "remove_battle_shock",
		"ERE WE GO": "plus_charge",
		"CAREEN": "deadly_demise_move",
		"ORKS IS NEVER BEATEN": "swing_back_before_remove",
		"ARCANE GENETIC ALCHEMY": "grant_fnp_psychic_mortal",
		"AVENGE THE FALLEN": "plus_attacks",
		"UNWAVERING SENTINELS": "minus_one_hit_defense_melee",
		"MULTIPOTENTIALITY": "fall_back_and_shoot",
		"VIGILANCE ETERNAL": "sticky_objective_control",
		"ARCHEOTECH MUNITIONS": "grant_lethal_hits",
	}
	for name in expected_effects:
		var pool = war_horde if _find_strat(war_horde, name) != null else shield_host
		var s = _find_strat(pool, name)
		assert_not_null(s, "Should find %s" % name)
		if s:
			var types := []
			for e in s.get("effects", []):
				types.append(str(e.get("type", "")))
			assert_true(expected_effects[name] in types,
				"%s should carry effect %s (got %s)" % [name, expected_effects[name], str(types)])

func test_careen_timing_column_overrides_epic_deed_default():
	"""CAREEN! (ORK War Horde) is an Epic Deed Stratagem, but the 11e
	timing column says once-per-phase — the timing column must win over
	the legacy 'Epic Deed => once per battle' text default."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Orks", "War Horde")
	var careen = _find_strat(strats, "CAREEN")
	assert_not_null(careen, "Should find CAREEN!")
	if careen:
		assert_true("Epic Deed" in careen.type, "CAREEN! should still be typed as an Epic Deed Stratagem")
		assert_eq(careen.restrictions.once_per, "phase",
			"timing column (once-per-phase) should override the Epic Deed once-per-battle default")


# ==========================================
# Section 11: Unit Target Matching
# ==========================================

func test_unit_matches_infantry_keyword():
	"""Unit with INFANTRY keyword should match keyword:INFANTRY condition."""
	var unit = _make_unit(["INFANTRY", "ADEPTUS ASTARTES"])
	var target = {"conditions": ["keyword:INFANTRY"]}
	assert_true(FactionStratagemLoaderData.unit_matches_target(unit, target))

func test_unit_fails_missing_keyword():
	"""Unit without required keyword should not match."""
	var unit = _make_unit(["VEHICLE"])
	var target = {"conditions": ["keyword:INFANTRY"]}
	assert_false(FactionStratagemLoaderData.unit_matches_target(unit, target))

func test_unit_matches_faction_keyword():
	"""Unit should match faction keyword condition."""
	var unit = _make_unit(["INFANTRY", "ADEPTUS ASTARTES"])
	var target = {"conditions": ["keyword:ADEPTUS ASTARTES"]}
	assert_true(FactionStratagemLoaderData.unit_matches_target(unit, target))

func test_unit_matches_target_of_attack_context():
	"""is_target_of_attack condition should check context."""
	var unit = _make_unit(["INFANTRY"])
	var target = {"conditions": ["is_target_of_attack"]}
	# Without context: should fail
	assert_false(FactionStratagemLoaderData.unit_matches_target(unit, target))
	# With context: should pass
	assert_true(FactionStratagemLoaderData.unit_matches_target(unit, target, {"is_target_of_attack": true}))

func test_unit_matches_below_starting_strength():
	"""below_starting_strength should check if models are dead."""
	var unit = _make_unit(["INFANTRY"])
	var target = {"conditions": ["below_starting_strength"]}
	# All alive: should fail
	assert_false(FactionStratagemLoaderData.unit_matches_target(unit, target))
	# Kill one model
	unit.models[0].alive = false
	assert_true(FactionStratagemLoaderData.unit_matches_target(unit, target))

func test_unit_matches_multiple_conditions():
	"""All conditions must pass for the unit to match."""
	var unit = _make_unit(["INFANTRY", "ORKS"])
	var target = {"conditions": ["keyword:INFANTRY", "keyword:ORKS"]}
	assert_true(FactionStratagemLoaderData.unit_matches_target(unit, target))

	var unit2 = _make_unit(["INFANTRY", "ADEPTUS ASTARTES"])
	assert_false(FactionStratagemLoaderData.unit_matches_target(unit2, target), "Should fail if missing ORKS keyword")


# ==========================================
# Section 12: Player Ownership
# ==========================================

func test_is_faction_stratagem():
	"""Faction stratagems should have IDs starting with 'faction_'."""
	var id = _loader._generate_stratagem_id("SM", "Gladius Task Force", "STORM OF FIRE")
	# Use a fresh StratagemManager-like check
	assert_true(id.begins_with("faction_"), "Faction stratagem IDs should start with 'faction_'")

func test_core_stratagem_not_faction():
	"""Core stratagem IDs should not be detected as faction stratagems."""
	assert_false("insane_bravery".begins_with("faction_"), "Core IDs should not start with 'faction_'")
	assert_false("command_re_roll".begins_with("faction_"), "Core IDs should not start with 'faction_'")


# ==========================================
# Section 13: Implemented Flag
# ==========================================

func test_implemented_flag_set_for_mapped_effects():
	"""Stratagems with compiled effects_json should be marked as implemented.
	11e note: the P0 rows (e.g. ARMOUR OF CONTEMPT) no longer auto-map —
	the 40kdc dataset has no rules prose for them — so this now pins an
	effects_json-carrying row instead."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Adepta Sororitas", "Chorus of Condemnation")
	var found = false
	for s in strats:
		if "HARMONISED EXORCISM" in s.name:
			found = true
			assert_true(s.implemented, "HARMONISED EXORCISM should be implemented (effects_json)")
	assert_true(found, "Should find HARMONISED EXORCISM")

func test_implemented_flag_false_for_unmapped_effects():
	"""Stratagems with only custom effects should NOT be marked as implemented."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	# ONLY IN DEATH DOES DUTY END has no 40kdc ability-DSL → stub EFFECT
	# text → custom:* → should NOT be implemented
	for s in strats:
		if "ONLY IN DEATH DOES DUTY END" in s.name:
			assert_false(s.implemented, "ONLY IN DEATH DOES DUTY END should not be implemented")

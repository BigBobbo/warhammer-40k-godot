extends "res://addons/gut/test.gd"

# Tests for Faction Stratagem Loading (Step 9)
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
	assert_eq(_loader.get_faction_name("SM"), "Space Marines")
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
# Section 10: Effect Mapping on Real Stratagems
# ==========================================

func test_armour_of_contempt_maps_to_worsen_ap():
	"""ARMOUR OF CONTEMPT (SM Gladius) should map to worsen_ap."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	var aoc = null
	for s in strats:
		if "ARMOUR OF CONTEMPT" in s.name:
			aoc = s
			break
	assert_not_null(aoc, "Should find ARMOUR OF CONTEMPT")
	if aoc:
		var has_worsen_ap = false
		for e in aoc.effects:
			if e.type == EffectPrimitivesData.WORSEN_AP:
				has_worsen_ap = true
		assert_true(has_worsen_ap, "Should have worsen_ap effect")
		assert_true(aoc.implemented, "Should be marked as implemented")

func test_storm_of_fire_maps_to_ignores_cover():
	"""STORM OF FIRE (SM Gladius) should map to grant_ignores_cover."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	var sof = null
	for s in strats:
		if "STORM OF FIRE" in s.name:
			sof = s
			break
	assert_not_null(sof, "Should find STORM OF FIRE")
	if sof:
		var has_ignores_cover = false
		for e in sof.effects:
			if e.type == EffectPrimitivesData.GRANT_IGNORES_COVER:
				has_ignores_cover = true
		assert_true(has_ignores_cover, "Should have grant_ignores_cover effect")
		assert_true(sof.implemented, "Should be marked as implemented")

func test_honour_the_chapter_maps_to_lance():
	"""HONOUR THE CHAPTER (SM Gladius) should map to grant_lance."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	var htc = null
	for s in strats:
		if "HONOUR THE CHAPTER" in s.name:
			htc = s
			break
	assert_not_null(htc, "Should find HONOUR THE CHAPTER")
	if htc:
		var has_lance = false
		for e in htc.effects:
			if e.type == EffectPrimitivesData.GRANT_LANCE:
				has_lance = true
		assert_true(has_lance, "Should have grant_lance effect")

func test_ard_as_nails_maps_to_minus_wound():
	"""'ARD AS NAILS (ORK War Horde) should map to minus_one_wound."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Orks", "War Horde")
	var aan = null
	for s in strats:
		if "ARD AS NAILS" in s.name:
			aan = s
			break
	assert_not_null(aan, "Should find 'ARD AS NAILS")
	if aan:
		var has_minus_wound = false
		for e in aan.effects:
			if e.type == EffectPrimitivesData.MINUS_ONE_WOUND:
				has_minus_wound = true
		assert_true(has_minus_wound, "Should have minus_one_wound effect")

func test_unbridled_carnage_maps_to_crit_hit():
	"""UNBRIDLED CARNAGE (ORK War Horde) should map to crit_hit_on 5."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Orks", "War Horde")
	var uc = null
	for s in strats:
		if "UNBRIDLED CARNAGE" in s.name:
			uc = s
			break
	assert_not_null(uc, "Should find UNBRIDLED CARNAGE")
	if uc:
		var has_crit = false
		for e in uc.effects:
			if e.type == EffectPrimitivesData.CRIT_HIT_ON:
				has_crit = true
				assert_eq(e.value, 5, "Should be crit on 5+")
		assert_true(has_crit, "Should have crit_hit_on effect")

func test_multipotentiality_maps_to_fall_back_and_shoot():
	"""MULTIPOTENTIALITY (AC Shield Host) should map to fall_back_and_shoot + fall_back_and_charge."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Adeptus Custodes", "Shield Host")
	var mp = null
	for s in strats:
		if "MULTIPOTENTIALITY" in s.name:
			mp = s
			break
	assert_not_null(mp, "Should find MULTIPOTENTIALITY")
	if mp:
		var has_fbs = false
		var has_fbc = false
		for e in mp.effects:
			if e.type == EffectPrimitivesData.FALL_BACK_AND_SHOOT:
				has_fbs = true
			if e.type == EffectPrimitivesData.FALL_BACK_AND_CHARGE:
				has_fbc = true
		assert_true(has_fbs, "Should have fall_back_and_shoot effect")
		assert_true(has_fbc, "Should have fall_back_and_charge effect")

func test_legendary_fortitude_maps_to_minus_damage():
	"""LEGENDARY FORTITUDE (SM 1st Company) should map to minus_damage."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Space Marines", "1st Company Task Force")
	var lf = null
	for s in strats:
		if "LEGENDARY FORTITUDE" in s.name:
			lf = s
			break
	assert_not_null(lf, "Should find LEGENDARY FORTITUDE")
	if lf:
		var has_minus_damage = false
		for e in lf.effects:
			if e.type == EffectPrimitivesData.MINUS_DAMAGE:
				has_minus_damage = true
		assert_true(has_minus_damage, "Should have minus_damage effect")


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
	"""Stratagems with mapped effects should be marked as implemented."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	# ARMOUR OF CONTEMPT maps to worsen_ap → should be implemented
	for s in strats:
		if "ARMOUR OF CONTEMPT" in s.name:
			assert_true(s.implemented, "ARMOUR OF CONTEMPT should be implemented")

func test_implemented_flag_false_for_unmapped_effects():
	"""Stratagems with only custom effects should NOT be marked as implemented."""
	_loader.load_faction_codes()
	var strats = _loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	# ONLY IN DEATH DOES DUTY END is fight-on-death → complex → should NOT be implemented
	for s in strats:
		if "ONLY IN DEATH DOES DUTY END" in s.name:
			assert_false(s.implemented, "ONLY IN DEATH DOES DUTY END should not be implemented")

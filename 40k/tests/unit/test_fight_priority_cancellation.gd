extends "res://addons/gut/test.gd"

# Tests for Fights First + Fights Last cancellation (10e rules, audit item T3-2)
#
# Per 10e Rules Commentary: If a unit has both Fights First and Fights Last,
# they cancel out and the unit fights in the Remaining Combats step (NORMAL).
#
# Scenarios tested:
# 1. Charged unit with Fights Last debuff -> NORMAL (cancellation)
# 2. Fights First ability with Fights Last debuff -> NORMAL (cancellation)
# 3. Charged unit without Fights Last -> FIGHTS_FIRST (no cancellation)
# 4. Non-charged unit with Fights Last debuff -> FIGHTS_LAST (no cancellation)
# 5. Normal unit (neither) -> NORMAL
# 6. Heroic Intervention with Fights Last -> FIGHTS_LAST (HI doesn't count as Fights First)

const FightPhase = preload("res://phases/FightPhase.gd")


# ==========================================
# Cancellation: Both Fights First + Fights Last
# ==========================================

func test_charged_unit_with_fights_last_cancels_to_normal():
	"""A charged unit with Fights Last debuff should cancel out to NORMAL priority."""
	var fight_phase = FightPhase.new()
	var unit = {
		"flags": {"charged_this_turn": true},
		"meta": {"name": "Cancellation Test Unit", "abilities": []},
		"status_effects": {"fights_last": true}
	}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.NORMAL, "Charged + Fights Last should cancel to NORMAL")
	fight_phase.free()

func test_fights_first_ability_with_fights_last_cancels_to_normal():
	"""A unit with Fights First ability and Fights Last debuff should cancel out to NORMAL."""
	var fight_phase = FightPhase.new()
	# Ability names are dictionaries; code checks str(ability).to_lower() for "fights_first"
	var unit = {
		"flags": {},
		"meta": {"name": "Ability Cancel Unit", "abilities": [{"name": "fights_first", "type": "Core", "description": "This unit fights first"}]},
		"status_effects": {"fights_last": true}
	}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.NORMAL, "Fights First ability + Fights Last should cancel to NORMAL")
	fight_phase.free()


# ==========================================
# No cancellation: Only one condition present
# ==========================================

func test_charged_unit_without_fights_last_gets_fights_first():
	"""A charged unit without Fights Last should still get FIGHTS_FIRST."""
	var fight_phase = FightPhase.new()
	var unit = {
		"flags": {"charged_this_turn": true},
		"meta": {"name": "Charged Unit", "abilities": []},
		"status_effects": {}
	}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.FIGHTS_FIRST, "Charged without Fights Last should be FIGHTS_FIRST")
	fight_phase.free()

func test_fights_last_only_gets_fights_last():
	"""A non-charged unit with only Fights Last debuff should get FIGHTS_LAST."""
	var fight_phase = FightPhase.new()
	var unit = {
		"flags": {},
		"meta": {"name": "Slow Unit", "abilities": []},
		"status_effects": {"fights_last": true}
	}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.FIGHTS_LAST, "Only Fights Last should be FIGHTS_LAST")
	fight_phase.free()

func test_normal_unit_gets_normal():
	"""A unit with neither Fights First nor Fights Last should get NORMAL."""
	var fight_phase = FightPhase.new()
	var unit = {
		"flags": {},
		"meta": {"name": "Normal Unit", "abilities": []},
		"status_effects": {}
	}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.NORMAL, "Normal unit should be NORMAL")
	fight_phase.free()


# ==========================================
# Edge case: Heroic Intervention + Fights Last
# ==========================================

func test_heroic_intervention_with_fights_last_stays_fights_last():
	"""Heroic Intervention does NOT grant Fights First, so Fights Last should still apply."""
	var fight_phase = FightPhase.new()
	var unit = {
		"flags": {"charged_this_turn": true, "heroic_intervention": true},
		"meta": {"name": "HI Unit", "abilities": []},
		"status_effects": {"fights_last": true}
	}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.FIGHTS_LAST, "HI + Fights Last should be FIGHTS_LAST (HI doesn't count as Fights First)")
	fight_phase.free()

func test_fights_first_ability_without_fights_last_gets_fights_first():
	"""A unit with Fights First ability but no Fights Last should get FIGHTS_FIRST."""
	var fight_phase = FightPhase.new()
	# Ability names are dictionaries; code checks str(ability).to_lower() for "fights_first"
	var unit = {
		"flags": {},
		"meta": {"name": "Fast Unit", "abilities": [{"name": "fights_first", "type": "Core", "description": "This unit fights first"}]},
		"status_effects": {}
	}
	var priority = fight_phase._get_fight_priority(unit)
	assert_eq(priority, FightPhase.FightPriority.FIGHTS_FIRST, "Fights First ability without Fights Last should be FIGHTS_FIRST")
	fight_phase.free()

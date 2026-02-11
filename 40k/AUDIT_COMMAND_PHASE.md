# Command Phase & Battle-shock Testing Audit
**Created:** 2026-02-11
**Status:** P4 Complete - Battle-shock Tests Implemented

## Overview

This document tracks the audit and improvement of testing coverage for the Command Phase and Battle-shock mechanics in the Warhammer 40k 10th Edition implementation.

## Priority Items

### P1: Command Phase Infrastructure - Stub Only
**Status:** Documented (no tests needed yet)

The CommandPhase (`phases/CommandPhase.gd`) is currently a **placeholder** with minimal functionality:
- Only supports `END_COMMAND` action
- Calls `MissionManager.check_all_objectives()` on entry
- Calls `MissionManager.score_primary_objectives()` on end
- No battle-shock test processing
- No Command Point gain logic
- No Stratagem usage framework

**Missing 10e Features:**
- [ ] Gain 1 CP at start of Command Phase
- [ ] Battle-shock test processing (should happen IN Command Phase, not Morale Phase)
- [ ] Stratagem framework for Command Phase
- [ ] Battle-shock flag clearing at start of owner's Command Phase

### P2: Morale Phase vs Command Phase Mismatch
**Status:** Documented

**Issue:** Per 10e rules, Battle-shock tests happen in the Command Phase (Step 2). However, the codebase implements morale/battle-shock logic in `MoralePhase.gd` instead. The MoralePhase uses a **9th edition style** morale test (casualties + D6 vs Leadership) rather than the **10e style** (2D6 >= Leadership for below-half-strength units).

**Current Implementation (MoralePhase):**
- Trigger: `casualties_this_turn > 0` (any casualties)
- Test: `casualties_this_turn + D6_roll <= Leadership` → pass
- Special rules: FEARLESS (auto-pass), ATSKNF (reroll)

**Correct 10e Rules:**
- Trigger: Unit is Below Half-strength (fewer than half models or half wounds)
- Test: `2D6 >= Leadership` → pass
- Effect: Battle-shocked (OC=0, no stratagems, desperate escape for all models)
- Duration: Until start of owner's next Command Phase

### P3: Battle-shock Flag Inconsistency
**Status:** Documented

Battle-shock status is stored in two different locations:
1. `unit.flags.battle_shocked` - Used by MissionManager for OC calculation
2. `unit.status_effects.battle_shocked` - Used by MovementPhase for Desperate Escape

This dual storage creates potential for desync. Should be unified.

### P4: Battle-shock Tests ✅ COMPLETE
**Status:** Complete (66 tests)
**File:** `tests/unit/test_battle_shock.gd`

Comprehensive test suite covering:

| Section | Tests | Description |
|---------|-------|-------------|
| Below Half-Strength Detection | 14 | Multi-model and single-model units, edge cases |
| Battle-shock Test Resolution | 8 | 2D6 vs Leadership for various factions |
| Battle-shock Flag Effects | 5 | OC=0, movement desperate escape, flag toggling |
| MoralePhase Integration | 9 | Casualty detection, test pass/fail, validation |
| Special Rules | 6 | FEARLESS, ATSKNF skip/auto-pass/reroll |
| CommandPhase Integration | 5 | Phase type, actions, validation, auto-complete |
| Available Actions | 2 | Morale test and skip actions in action list |
| Phase Completion | 2 | Complete when no pending tests |
| Skip Morale Processing | 1 | FEARLESS unit skip |
| Desperate Escape | 2 | Battle-shocked vs normal fallback |
| Duration & Reset | 2 | Persistence and clearing |
| Edge Cases | 10 | Invalid rolls, wrong player, missing fields, stratagem validation, horde/small units |
| **Total** | **66** | |

**Test Categories:**
1. **Pure logic tests** (Sections 1-3): Test below-half-strength calculation, 2D6 vs Ld resolution, and flag effect logic — no phase instances needed
2. **Phase integration tests** (Sections 4-8): Test MoralePhase and CommandPhase behavior with actual phase instances and game state snapshots
3. **Cross-system tests** (Sections 9-11): Test how battle-shock flags interact with movement (desperate escape), persistence across phases, and edge cases

**Known Issues Found During Testing:**
- MoralePhase checks `model.get("alive", true)` but TestDataFactory uses `model.is_alive` — key name mismatch
- TestDataFactory units have `player_id` but MoralePhase checks `owner` — field name mismatch
- MoralePhase uses 9e-style morale (casualties + D6) instead of 10e battle-shock (2D6 >= Ld)
- Dual storage of battle_shocked in `flags` and `status_effects`

### P5: Command Phase Battle-shock Implementation
**Status:** Not Started

Implement the actual 10e battle-shock test flow in CommandPhase:
1. Clear previous battle-shock flags at phase start
2. Detect below-half-strength units
3. Roll 2D6 per unit, compare to Leadership
4. Set `battle_shocked` flag on failed units
5. Apply OC=0 and stratagem restrictions

### P6: Morale Phase Modernization
**Status:** Not Started

Update MoralePhase to match 10e rules or remove it (since battle-shock should be in Command Phase):
- Remove old casualties+D6 morale test
- Keep any Combat Attrition logic if needed
- Or repurpose for other end-of-turn effects

## Recommended Next Task

**P5: Command Phase Battle-shock Implementation** should be addressed next because:
1. P4 tests provide the verification framework
2. The below-half-strength detection logic is tested and ready to integrate
3. The 2D6 vs Leadership resolution is tested and ready to integrate
4. This brings the Command Phase from stub to functional for 10e rules
5. It unblocks proper game flow (currently battle-shock never actually triggers)

Alternative: **P3: Battle-shock Flag Unification** is simpler and removes a bug class. Standardize on `flags.battle_shocked` everywhere and update MovementPhase to read from `flags` instead of `status_effects`.

## File References

| File | Purpose |
|------|---------|
| `phases/CommandPhase.gd` | Command Phase stub (needs battle-shock) |
| `phases/MoralePhase.gd` | Morale Phase (9e-style, needs modernization) |
| `phases/BasePhase.gd` | Base class for all phases |
| `phases/MovementPhase.gd:569` | Reads `status_effects.battle_shocked` for desperate escape |
| `phases/MovementPhase.gd:985-1065` | Desperate Escape test implementation |
| `autoloads/MissionManager.gd:123` | Reads `flags.battle_shocked` for OC=0 |
| `tests/unit/test_battle_shock.gd` | Battle-shock test suite (66 tests) |
| `tests/helpers/TestDataFactory.gd` | Test data factory |
| `tests/helpers/BasePhaseTest.gd` | Phase test base class |

## Rules Reference

Per Warhammer 40k 10th Edition Core Rules:

**Command Phase (Step 2 - Battle-shock):**
- Units Below Half-strength must take a Battle-shock test
- Below Half-strength: fewer than half starting models alive (multi-model) or fewer than half wounds (single model)
- Battle-shock test: Roll 2D6; pass on result >= Leadership characteristic
- Failed units are Battle-shocked until start of owner's next Command Phase

**Battle-shocked Effects:**
- Objective Control = 0
- Cannot be affected by Stratagems (except Insane Bravery)
- Desperate Escape tests apply to ALL models when Falling Back (not just those crossing enemies)

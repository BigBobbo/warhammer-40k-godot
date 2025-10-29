# Multiplayer Integration Test Plan
## Warhammer 40K Godot Implementation

**Version:** 1.0
**Date:** 2025-10-28
**Status:** Planning Phase

---

## Executive Summary

This document outlines a comprehensive testing strategy for multiplayer functionality in the Warhammer 40K Godot implementation. The strategy focuses on small, focused tests that load specific game states, enabling fast feedback and easy debugging.

### Goals
1. ✅ Ensure multiplayer synchronization works correctly
2. ✅ Verify all game phases function properly in multiplayer
3. ✅ Catch regressions early with fast, targeted tests
4. ✅ Build confidence for releases with comprehensive coverage

### Timeline
- **Phase 1 (MVP)**: Deployment + Movement tests (2 weeks)
- **Phase 2**: Shooting + Charge tests (2 weeks)
- **Phase 3**: Fight + Transitions tests (2 weeks)
- **Phase 4**: Full game smoke tests (1 week)
- **Total**: 7 weeks to complete coverage

---

## Test Architecture Overview

### Test Tiers

```
Tier 1: Phase-Level Tests (80% of tests)
├── Deployment Phase (5-10 tests)
├── Movement Phase (8-12 tests)
├── Shooting Phase (10-15 tests)
├── Charge Phase (5-8 tests)
└── Fight Phase (10-15 tests)

Tier 2: Integration Tests (15% of tests)
├── Phase Transitions (5 tests)
├── Turn Completion (3 tests)
└── Multi-turn scenarios (2 tests)

Tier 3: Smoke Tests (5% of tests)
└── Full Game (1-2 tests)
```

### Test Execution Strategy

**Daily Development:**
```bash
# Run current phase tests (~2-5 min)
./tests/run_multiplayer_tests.sh -f test_multiplayer_deployment.gd
```

**Pre-Commit:**
```bash
# Run all implemented phase tests (~10-15 min)
./tests/run_multiplayer_tests.sh
```

**Pre-Release:**
```bash
# Run full suite including smoke tests (~30 min)
./tests/run_multiplayer_tests.sh --all
```

---

## Phase 1: Deployment Phase Tests

**File:** `tests/integration/test_multiplayer_deployment.gd`
**Priority:** HIGH (MVP)
**Estimated Tests:** 8
**Estimated Time:** 2-3 days

### Test Scenarios

#### 1.1 Basic Deployment
```gdscript
test_deployment_single_unit()
- Load: deployment_start.w40ksave
- Action: Host deploys one unit in valid zone
- Verify: Client sees unit in correct position
- Verify: Unit marked as deployed on both clients
```

#### 1.2 Invalid Deployment
```gdscript
test_deployment_outside_zone()
- Load: deployment_start.w40ksave
- Action: Host tries to deploy outside deployment zone
- Verify: Deployment rejected
- Verify: Error message shown
- Verify: Unit not deployed on either client
```

#### 1.3 Deployment Turn Order
```gdscript
test_deployment_alternating_turns()
- Load: deployment_start.w40ksave
- Action: Verify Player 1 deploys first
- Action: Verify turn switches to Player 2
- Action: Verify Player 2 can deploy
- Action: Verify turn switches back to Player 1
```

#### 1.4 Terrain Blocking
```gdscript
test_deployment_blocked_by_terrain()
- Load: deployment_with_terrain.w40ksave
- Action: Try to deploy unit on impassable terrain
- Verify: Deployment rejected
- Verify: Error message clear
```

#### 1.5 Unit Coherency
```gdscript
test_deployment_unit_coherency()
- Load: deployment_start.w40ksave
- Action: Deploy multi-model unit (e.g., 10 models)
- Verify: All models within coherency distance
- Verify: Models synced on both clients
```

#### 1.6 Deployment Completion
```gdscript
test_deployment_completion_both_players()
- Load: deployment_nearly_complete.w40ksave
- Action: Player 1 completes deployment
- Verify: Still in deployment phase (waiting for P2)
- Action: Player 2 completes deployment
- Verify: Phase transitions to Movement
```

#### 1.7 Deployment Undo
```gdscript
test_deployment_undo_action()
- Load: deployment_start.w40ksave
- Action: Host deploys unit
- Action: Host clicks "Undo"
- Verify: Unit removed from board
- Verify: Synced on client
```

#### 1.8 Concurrent Deployment Attempt
```gdscript
test_deployment_wrong_turn()
- Load: deployment_player1_turn.w40ksave
- Action: Client (Player 2) tries to deploy
- Verify: Action rejected (not their turn)
- Verify: Error message shown
```

### Required Test Saves
- ✅ `deployment_start.w40ksave` (already exists)
- ☐ `deployment_nearly_complete.w40ksave`
- ☐ `deployment_with_terrain.w40ksave`
- ☐ `deployment_player1_turn.w40ksave`
- ☐ `deployment_player2_turn.w40ksave`

---

## Phase 2: Movement Phase Tests

**File:** `tests/integration/test_multiplayer_movement.gd`
**Priority:** HIGH (MVP)
**Estimated Tests:** 10
**Estimated Time:** 3-4 days

### Test Scenarios

#### 2.1 Basic Movement
```gdscript
test_movement_basic_advance()
- Load: movement_start.w40ksave
- Action: Host moves unit forward 6"
- Verify: Unit position updated on both clients
- Verify: Movement distance calculated correctly
```

#### 2.2 Movement Range Limit
```gdscript
test_movement_exceeds_range()
- Load: movement_start.w40ksave
- Action: Try to move unit beyond its Movement characteristic
- Verify: Move rejected or clamped to max distance
- Verify: Error/warning shown
```

#### 2.3 Unit Coherency During Movement
```gdscript
test_movement_maintains_coherency()
- Load: movement_multi_model_unit.w40ksave
- Action: Move multi-model unit
- Verify: All models maintain coherency
- Verify: Invalid moves rejected
```

#### 2.4 Movement Through Terrain
```gdscript
test_movement_difficult_terrain()
- Load: movement_with_terrain.w40ksave
- Action: Move unit through difficult terrain
- Verify: Movement reduced appropriately
- Verify: Terrain effects applied
```

#### 2.5 Movement Blocking
```gdscript
test_movement_blocked_by_enemy()
- Load: movement_with_enemies.w40ksave
- Action: Try to move through enemy unit
- Verify: Move blocked or engagement range triggered
```

#### 2.6 Multiple Unit Movement
```gdscript
test_movement_multiple_units()
- Load: movement_start.w40ksave
- Action: Move 3 different units in sequence
- Verify: All movements sync correctly
- Verify: Turn order maintained
```

#### 2.7 Movement Completion
```gdscript
test_movement_phase_completion()
- Load: movement_nearly_complete.w40ksave
- Action: Complete remaining moves
- Action: Click "End Movement Phase"
- Verify: Phase transitions to Shooting
```

#### 2.8 Movement Undo
```gdscript
test_movement_undo_move()
- Load: movement_start.w40ksave
- Action: Move unit
- Action: Click "Undo Move"
- Verify: Unit returns to original position
- Verify: Synced on both clients
```

#### 2.9 Advance vs Normal Move
```gdscript
test_movement_advance_action()
- Load: movement_start.w40ksave
- Action: Declare "Advance" for unit
- Verify: Movement range increased (M + D6)
- Verify: Unit marked as Advanced (can't shoot)
```

#### 2.10 Fall Back Movement
```gdscript
test_movement_fall_back()
- Load: movement_in_engagement.w40ksave
- Action: Unit in engagement range Falls Back
- Verify: Unit can move away from enemy
- Verify: Unit marked as Fell Back (can't shoot/charge)
```

### Required Test Saves
- ☐ `movement_start.w40ksave`
- ☐ `movement_nearly_complete.w40ksave`
- ☐ `movement_multi_model_unit.w40ksave`
- ☐ `movement_with_terrain.w40ksave`
- ☐ `movement_with_enemies.w40ksave`
- ☐ `movement_in_engagement.w40ksave`

---

## Phase 3: Shooting Phase Tests

**File:** `tests/integration/test_multiplayer_shooting.gd`
**Priority:** MEDIUM
**Estimated Tests:** 12
**Estimated Time:** 4-5 days

### Test Scenarios

#### 3.1 Basic Shooting Attack
```gdscript
test_shooting_basic_attack()
- Load: shooting_start.w40ksave
- Action: Select attacking unit
- Action: Select target unit
- Action: Resolve shooting (hit, wound, save, damage)
- Verify: Target takes damage
- Verify: Damage synced on both clients
```

#### 3.2 Range Validation
```gdscript
test_shooting_out_of_range()
- Load: shooting_long_range.w40ksave
- Action: Try to shoot target beyond weapon range
- Verify: Target selection rejected
- Verify: Error message shown
```

#### 3.3 Line of Sight
```gdscript
test_shooting_no_line_of_sight()
- Load: shooting_blocked_los.w40ksave
- Action: Try to shoot target with no LoS
- Verify: Shot blocked
- Verify: LoS check visible to user
```

#### 3.4 Hit Roll Calculation
```gdscript
test_shooting_hit_roll_modifiers()
- Load: shooting_with_modifiers.w40ksave
- Action: Perform attack with +1 to hit modifier
- Verify: Hit roll calculated correctly
- Verify: Modifiers applied and displayed
```

#### 3.5 Wound Roll Calculation
```gdscript
test_shooting_wound_roll()
- Load: shooting_start.w40ksave
- Action: Perform attack (S4 vs T4)
- Verify: Wound roll requires 4+
- Verify: Wound roll calculated from S vs T table
```

#### 3.6 Save Roll
```gdscript
test_shooting_save_roll()
- Load: shooting_start.w40ksave
- Action: Target takes hits
- Verify: Save roll offered
- Verify: AP modifier applied correctly
- Verify: Failed saves = wounds
```

#### 3.7 Damage Application
```gdscript
test_shooting_damage_application()
- Load: shooting_start.w40ksave
- Action: Weapon with Damage 3 wounds target
- Verify: 3 wounds removed from model
- Verify: Model removed when wounds = 0
- Verify: Synced on both clients
```

#### 3.8 Multiple Weapons
```gdscript
test_shooting_multiple_weapons()
- Load: shooting_mixed_weapons.w40ksave
- Action: Unit with bolt rifles AND heavy bolter shoots
- Verify: Can select which weapon to use
- Verify: Each weapon resolved separately
```

#### 3.9 Overwatch
```gdscript
test_shooting_overwatch()
- Load: shooting_overwatch_opportunity.w40ksave
- Action: Enemy declares charge
- Action: Defender declares Overwatch
- Verify: Shooting attack resolved
- Verify: Hit rolls at -1 modifier
```

#### 3.10 Split Fire
```gdscript
test_shooting_split_fire()
- Load: shooting_multiple_targets.w40ksave
- Action: Unit with multiple models splits fire
- Verify: Different models can target different units
- Verify: All attacks tracked correctly
```

#### 3.11 Advanced Unit Can't Shoot
```gdscript
test_shooting_advanced_unit_restricted()
- Load: shooting_with_advanced_unit.w40ksave
- Action: Try to shoot with unit that Advanced
- Verify: Shooting not allowed (or assault weapons only)
- Verify: Clear message shown
```

#### 3.12 Shooting Phase Completion
```gdscript
test_shooting_phase_completion()
- Load: shooting_nearly_complete.w40ksave
- Action: Complete remaining attacks
- Action: Click "End Shooting Phase"
- Verify: Phase transitions to Charge
```

### Required Test Saves
- ☐ `shooting_start.w40ksave`
- ☐ `shooting_nearly_complete.w40ksave`
- ☐ `shooting_long_range.w40ksave`
- ☐ `shooting_blocked_los.w40ksave`
- ☐ `shooting_with_modifiers.w40ksave`
- ☐ `shooting_mixed_weapons.w40ksave`
- ☐ `shooting_overwatch_opportunity.w40ksave`
- ☐ `shooting_multiple_targets.w40ksave`
- ☐ `shooting_with_advanced_unit.w40ksave`

---

## Phase 4: Charge Phase Tests

**File:** `tests/integration/test_multiplayer_charge.gd`
**Priority:** MEDIUM
**Estimated Tests:** 7
**Estimated Time:** 2-3 days

### Test Scenarios

#### 4.1 Basic Charge
```gdscript
test_charge_basic_declaration()
- Load: charge_start.w40ksave
- Action: Declare charge against target within 12"
- Verify: Charge declared
- Verify: Roll 2D6 for charge distance
- Verify: Move unit if within rolled distance
```

#### 4.2 Charge Range Limit
```gdscript
test_charge_out_of_range()
- Load: charge_far_target.w40ksave
- Action: Try to declare charge against target >12" away
- Verify: Charge declaration rejected
- Verify: Error message shown
```

#### 4.3 Failed Charge
```gdscript
test_charge_roll_insufficient()
- Load: charge_start.w40ksave
- Action: Declare charge (target 10" away)
- Action: Roll 2D6 = 7 (insufficient)
- Verify: Charge fails
- Verify: Unit doesn't move
- Verify: Unit marked as "Failed Charge"
```

#### 4.4 Successful Charge Movement
```gdscript
test_charge_successful_move()
- Load: charge_start.w40ksave
- Action: Declare charge (target 8" away)
- Action: Roll 2D6 = 10 (sufficient)
- Verify: Unit moves to within engagement range
- Verify: Movement synced on both clients
```

#### 4.5 Overwatch Reaction
```gdscript
test_charge_triggers_overwatch()
- Load: charge_start.w40ksave
- Action: Declare charge
- Verify: Defender offered Overwatch option
- Action: Defender accepts Overwatch
- Verify: Shooting phase interrupt
- Verify: Hit rolls at -1
```

#### 4.6 Charge Through Terrain
```gdscript
test_charge_dangerous_terrain()
- Load: charge_with_terrain.w40ksave
- Action: Charge through difficult terrain
- Verify: Charge roll modified (-2" or similar)
- Verify: Terrain effects applied
```

#### 4.7 Multiple Charge Targets
```gdscript
test_charge_multiple_targets()
- Load: charge_multiple_enemies.w40ksave
- Action: Declare charge against 2 enemy units
- Verify: Can select multiple targets
- Verify: Must end within engagement range of all
```

### Required Test Saves
- ☐ `charge_start.w40ksave`
- ☐ `charge_far_target.w40ksave`
- ☐ `charge_with_terrain.w40ksave`
- ☐ `charge_multiple_enemies.w40ksave`

---

## Phase 5: Fight Phase Tests

**File:** `tests/integration/test_multiplayer_fight.gd`
**Priority:** HIGH (Complex Phase)
**Estimated Tests:** 12
**Estimated Time:** 5-6 days

### Test Scenarios

#### 5.1 Basic Fight Attack
```gdscript
test_fight_basic_attack()
- Load: fight_start.w40ksave
- Action: Activate unit, select target
- Action: Resolve melee attacks (hit, wound, save, damage)
- Verify: Damage applied correctly
- Verify: Synced on both clients
```

#### 5.2 Fight Alternating Activation
```gdscript
test_fight_alternating_units()
- Load: fight_multiple_units.w40ksave
- Action: Player 1 activates unit
- Verify: Turn switches to Player 2
- Action: Player 2 activates unit
- Verify: Turn switches back to Player 1
- Verify: Correct until all units activated
```

#### 5.3 Fight Initiative Order
```gdscript
test_fight_unit_activation_order()
- Load: fight_start.w40ksave
- Verify: Units that charged can activate first
- Verify: Then alternate between players
- Verify: All eligible units shown
```

#### 5.4 Pile In Movement
```gdscript
test_fight_pile_in()
- Load: fight_with_distance.w40ksave
- Action: Activate unit for fight
- Action: Pile in 3" toward closest enemy
- Verify: Movement applied
- Verify: Unit closer to enemy
- Verify: Synced on client
```

#### 5.5 Fight Attack Resolution
```gdscript
test_fight_attack_sequence()
- Load: fight_start.w40ksave
- Action: Resolve all attacks from one unit
- Verify: Number of attacks calculated (A characteristic)
- Verify: Hit rolls (WS)
- Verify: Wound rolls (S vs T)
- Verify: Save rolls (AP modifier)
- Verify: Damage applied
```

#### 5.6 Consolidate Movement
```gdscript
test_fight_consolidate()
- Load: fight_after_attacks.w40ksave
- Action: Unit finishes attacks
- Action: Consolidate 3" (toward nearest enemy or objective)
- Verify: Movement applied
- Verify: Synced on both clients
```

#### 5.7 Fight Through Models
```gdscript
test_fight_model_removal()
- Load: fight_start.w40ksave
- Action: Kill multiple models in target unit
- Verify: Models removed when wounds = 0
- Verify: Removed models synced
- Verify: Unit coherency maintained
```

#### 5.8 Fight Against Multiple Units
```gdscript
test_fight_split_attacks()
- Load: fight_multiple_enemies.w40ksave
- Action: Unit in engagement with 2 enemies
- Verify: Can split attacks between targets
- Verify: All attacks tracked correctly
```

#### 5.9 Fight Phase Heroic Intervention
```gdscript
test_fight_heroic_intervention()
- Load: fight_character_nearby.w40ksave
- Action: Character performs Heroic Intervention (6" move)
- Verify: Character can move before fight begins
- Verify: Character now eligible to fight
```

#### 5.10 Fight Phase Completion
```gdscript
test_fight_phase_end()
- Load: fight_nearly_complete.w40ksave
- Action: Activate all remaining units
- Verify: Phase ends when all units activated
- Verify: Turn ends, switches to other player
```

#### 5.11 Fight Phase Manual End
```gdscript
test_fight_manual_end_turn()
- Load: fight_optional_activations.w40ksave
- Action: Player chooses not to activate remaining units
- Action: Click "End Fight Phase"
- Verify: Phase ends early
- Verify: Opponent's turn begins
```

#### 5.12 Multiple Combat Resolution
```gdscript
test_fight_complex_engagement()
- Load: fight_complex_melee.w40ksave
- Action: Resolve combat with 3+ units per side engaged
- Verify: Alternating activation works
- Verify: All units can fight
- Verify: No units skipped or duplicated
```

### Required Test Saves
- ☐ `fight_start.w40ksave`
- ☐ `fight_multiple_units.w40ksave`
- ☐ `fight_with_distance.w40ksave`
- ☐ `fight_after_attacks.w40ksave`
- ☐ `fight_multiple_enemies.w40ksave`
- ☐ `fight_character_nearby.w40ksave`
- ☐ `fight_nearly_complete.w40ksave`
- ☐ `fight_optional_activations.w40ksave`
- ☐ `fight_complex_melee.w40ksave`

---

## Phase 6: Phase Transition Tests

**File:** `tests/integration/test_multiplayer_phase_transitions.gd`
**Priority:** MEDIUM
**Estimated Tests:** 6
**Estimated Time:** 2 days

### Test Scenarios

#### 6.1 Deployment → Movement Transition
```gdscript
test_transition_deployment_to_movement()
- Load: deployment_nearly_complete.w40ksave
- Action: Both players complete deployment
- Verify: Phase changes to Movement
- Verify: Both clients see Movement phase
- Verify: Correct player's turn
```

#### 6.2 Movement → Shooting Transition
```gdscript
test_transition_movement_to_shooting()
- Load: movement_nearly_complete.w40ksave
- Action: Complete movement phase
- Verify: Phase changes to Shooting
- Verify: Units available to shoot
```

#### 6.3 Shooting → Charge Transition
```gdscript
test_transition_shooting_to_charge()
- Load: shooting_nearly_complete.w40ksave
- Action: Complete shooting phase
- Verify: Phase changes to Charge
- Verify: Eligible units shown for charging
```

#### 6.4 Charge → Fight Transition
```gdscript
test_transition_charge_to_fight()
- Load: charge_nearly_complete.w40ksave
- Action: Resolve all charges
- Verify: Phase changes to Fight
- Verify: Units that charged fight first
```

#### 6.5 Fight → End Turn Transition
```gdscript
test_transition_fight_to_end_turn()
- Load: fight_nearly_complete.w40ksave
- Action: Complete fight phase
- Verify: Turn ends
- Verify: Opponent's turn begins
- Verify: Phase cycles back to Movement
```

#### 6.6 Full Turn Cycle
```gdscript
test_complete_turn_cycle()
- Load: movement_start.w40ksave
- Action: Complete Movement → Shooting → Charge → Fight
- Verify: All transitions work in sequence
- Verify: Turn ends correctly
- Verify: Both clients remain synchronized
```

### Required Test Saves
- Uses saves from other phases (already listed)

---

## Phase 7: Full Game Smoke Tests

**File:** `tests/integration/test_multiplayer_full_game.gd`
**Priority:** LOW (Validation)
**Estimated Tests:** 2
**Estimated Time:** 2 days

### Test Scenarios

#### 7.1 Complete Game Round
```gdscript
test_full_game_one_round()
- Load: deployment_start.w40ksave
- Action: Complete full deployment
- Action: Player 1 full turn (all phases)
- Action: Player 2 full turn (all phases)
- Verify: No crashes
- Verify: Both clients synced throughout
- Verify: Game state valid at end
```

#### 7.2 Multi-Round Game
```gdscript
test_full_game_three_rounds()
- Load: deployment_start.w40ksave
- Action: Play 3 complete game rounds
- Verify: Turn counter increments correctly
- Verify: No memory leaks
- Verify: Performance remains acceptable
- Verify: Save/load works mid-game
```

### Required Test Saves
- Uses `deployment_start.w40ksave`

---

## Test Save File Inventory

### Total Required: 30+ save files

**Status Legend:**
- ✅ Created
- 🔨 In Progress
- ☐ Not Started

### Deployment Phase (5 saves)
- ✅ `deployment_start.w40ksave`
- ☐ `deployment_nearly_complete.w40ksave`
- ☐ `deployment_with_terrain.w40ksave`
- ☐ `deployment_player1_turn.w40ksave`
- ☐ `deployment_player2_turn.w40ksave`

### Movement Phase (6 saves)
- ☐ `movement_start.w40ksave`
- ☐ `movement_nearly_complete.w40ksave`
- ☐ `movement_multi_model_unit.w40ksave`
- ☐ `movement_with_terrain.w40ksave`
- ☐ `movement_with_enemies.w40ksave`
- ☐ `movement_in_engagement.w40ksave`

### Shooting Phase (9 saves)
- ☐ `shooting_start.w40ksave`
- ☐ `shooting_nearly_complete.w40ksave`
- ☐ `shooting_long_range.w40ksave`
- ☐ `shooting_blocked_los.w40ksave`
- ☐ `shooting_with_modifiers.w40ksave`
- ☐ `shooting_mixed_weapons.w40ksave`
- ☐ `shooting_overwatch_opportunity.w40ksave`
- ☐ `shooting_multiple_targets.w40ksave`
- ☐ `shooting_with_advanced_unit.w40ksave`

### Charge Phase (4 saves)
- ☐ `charge_start.w40ksave`
- ☐ `charge_far_target.w40ksave`
- ☐ `charge_with_terrain.w40ksave`
- ☐ `charge_multiple_enemies.w40ksave`

### Fight Phase (9 saves)
- ☐ `fight_start.w40ksave`
- ☐ `fight_multiple_units.w40ksave`
- ☐ `fight_with_distance.w40ksave`
- ☐ `fight_after_attacks.w40ksave`
- ☐ `fight_multiple_enemies.w40ksave`
- ☐ `fight_character_nearby.w40ksave`
- ☐ `fight_nearly_complete.w40ksave`
- ☐ `fight_optional_activations.w40ksave`
- ☐ `fight_complex_melee.w40ksave`

---

## Implementation Roadmap

### Week 1-2: MVP Phase 1
**Goal:** Deployment + Movement tests working

- [ ] Create deployment test saves (5 files)
- [ ] Implement deployment tests (8 tests)
- [ ] Run and fix deployment tests
- [ ] Create movement test saves (6 files)
- [ ] Implement movement tests (10 tests)
- [ ] Run and fix movement tests

**Deliverable:** Basic game flow tested (deploy → move)

### Week 3-4: Phase 2
**Goal:** Shooting + Charge tests working

- [ ] Create shooting test saves (9 files)
- [ ] Implement shooting tests (12 tests)
- [ ] Run and fix shooting tests
- [ ] Create charge test saves (4 files)
- [ ] Implement charge tests (7 tests)
- [ ] Run and fix charge tests

**Deliverable:** Combat initiation tested (shoot → charge)

### Week 5-6: Phase 3
**Goal:** Fight + Transitions tests working

- [ ] Create fight test saves (9 files)
- [ ] Implement fight tests (12 tests)
- [ ] Run and fix fight tests
- [ ] Implement phase transition tests (6 tests)
- [ ] Run and fix transition tests

**Deliverable:** Full turn cycle tested

### Week 7: Phase 4
**Goal:** Full game validation

- [ ] Implement full game smoke tests (2 tests)
- [ ] Run full test suite
- [ ] Fix any integration issues
- [ ] Document test coverage

**Deliverable:** Complete test suite operational

---

## Success Metrics

### Coverage Goals
- **Phase-level tests:** 45+ tests
- **Integration tests:** 6+ tests
- **Smoke tests:** 2+ tests
- **Total:** 53+ tests

### Performance Goals
- Individual test: < 60 seconds
- Phase test suite: < 5 minutes
- Full test suite: < 30 minutes

### Quality Goals
- All critical paths covered
- All multiplayer sync points verified
- No flaky tests (> 99% pass rate)
- Clear failure messages

---

## Maintenance Strategy

### Adding New Tests
1. Identify scenario to test
2. Create or reuse test save file
3. Write test following existing patterns
4. Run test and verify it works
5. Add to appropriate test suite
6. Update this document

### Test Save Management
- Store in `tests/saves/` directory
- Name descriptively: `{phase}_{scenario}.w40ksave`
- Document in save file JSON: `"test_save": true, "description": "..."`
- Keep saves small (minimal units for scenario)

### When Tests Fail
1. Check if game logic changed (expected)
2. Update test expectations if needed
3. Fix implementation if test is correct
4. Never ignore failing tests

---

## Appendix A: Test Template

```gdscript
extends MultiplayerIntegrationTest

func test_scenario_name():
    """
    Test: Brief description of what this tests

    Setup: What save file and initial conditions
    Action: What actions are performed
    Verify: What should be true after actions
    """

    # Setup: Load test save
    await launch_host_and_client()
    await wait_for_connection()
    await load_test_save("scenario.w40ksave")
    await wait_for_phase("ExpectedPhase", 5.0)

    # Action: Perform test actions
    var result = await simulate_action(...)

    # Verify: Check results
    assert_true(result.success, "Action should succeed")

    # Verify sync
    var host_state = host_instance.get_game_state()
    var client_state = client_instance.get_game_state()
    assert_eq(host_state.value, client_state.value, "States should match")
```

---

## Appendix B: Test Execution Commands

```bash
# Run all tests
./tests/run_multiplayer_tests.sh

# Run specific phase
./tests/run_multiplayer_tests.sh -f test_multiplayer_deployment.gd

# Run with verbose output
./tests/run_multiplayer_tests.sh -v

# Quick sanity check
./tests/test_quick.sh
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-28 | Claude Code | Initial test plan created |

---

**Status:** 📋 Ready for Implementation
**Next Action:** Begin Week 1 - Create deployment test saves
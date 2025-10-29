# Multiplayer Test Implementation Checklist

**Quick Reference**: Track progress through the testing roadmap

---

## 📊 Overall Progress: 2/53 tests passing, 8/53 implemented (15%)

### Test Files Status
- [x] test_multiplayer_deployment.gd (2/8 passing, 8/8 implemented - 6 pending action system)
- [ ] test_multiplayer_movement.gd (0/10 tests)
- [ ] test_multiplayer_shooting.gd (0/12 tests)
- [ ] test_multiplayer_charge.gd (0/7 tests)
- [ ] test_multiplayer_fight.gd (0/12 tests)
- [ ] test_multiplayer_phase_transitions.gd (0/6 tests)
- [ ] test_multiplayer_full_game.gd (0/2 tests)

---

## Week 1-2: MVP Phase (Deployment + Movement)

### Deployment Phase ✅ Started | 🔨 In Progress
**File**: `tests/integration/test_multiplayer_deployment.gd`

#### Test Saves (5 files)
- [x] deployment_start.w40ksave
- [x] deployment_nearly_complete.w40ksave
- [x] deployment_with_terrain.w40ksave
- [x] deployment_player1_turn.w40ksave
- [x] deployment_player2_turn.w40ksave

#### Tests (8 tests)
- [x] test_basic_multiplayer_connection ✅ PASSING
- [x] test_deployment_save_load ✅ PASSING
- [x] test_deployment_single_unit ⏸ PENDING (action system)
- [x] test_deployment_outside_zone ⏸ PENDING (action system)
- [x] test_deployment_alternating_turns ⏸ PENDING (action system)
- [x] test_deployment_wrong_turn ⏸ PENDING (action system)
- [x] test_deployment_blocked_by_terrain ⏸ PENDING (action system)
- [x] test_deployment_unit_coherency ⏸ PENDING (action system)
- [x] test_deployment_completion_both_players ⏸ PENDING (action system)
- [x] test_deployment_undo_action ⏸ PENDING (action system)

### Movement Phase ☐ Started | ☐ Complete
**File**: `tests/integration/test_multiplayer_movement.gd`

#### Test Saves (6 files)
- [ ] movement_start.w40ksave
- [ ] movement_nearly_complete.w40ksave
- [ ] movement_multi_model_unit.w40ksave
- [ ] movement_with_terrain.w40ksave
- [ ] movement_with_enemies.w40ksave
- [ ] movement_in_engagement.w40ksave

#### Tests (10 tests)
- [ ] test_movement_basic_advance
- [ ] test_movement_exceeds_range
- [ ] test_movement_maintains_coherency
- [ ] test_movement_difficult_terrain
- [ ] test_movement_blocked_by_enemy
- [ ] test_movement_multiple_units
- [ ] test_movement_phase_completion
- [ ] test_movement_undo_move
- [ ] test_movement_advance_action
- [ ] test_movement_fall_back

---

## Week 3-4: Combat Phase (Shooting + Charge)

### Shooting Phase ☐ Started | ☐ Complete
**File**: `tests/integration/test_multiplayer_shooting.gd`

#### Test Saves (9 files)
- [ ] shooting_start.w40ksave
- [ ] shooting_nearly_complete.w40ksave
- [ ] shooting_long_range.w40ksave
- [ ] shooting_blocked_los.w40ksave
- [ ] shooting_with_modifiers.w40ksave
- [ ] shooting_mixed_weapons.w40ksave
- [ ] shooting_overwatch_opportunity.w40ksave
- [ ] shooting_multiple_targets.w40ksave
- [ ] shooting_with_advanced_unit.w40ksave

#### Tests (12 tests)
- [ ] test_shooting_basic_attack
- [ ] test_shooting_out_of_range
- [ ] test_shooting_no_line_of_sight
- [ ] test_shooting_hit_roll_modifiers
- [ ] test_shooting_wound_roll
- [ ] test_shooting_save_roll
- [ ] test_shooting_damage_application
- [ ] test_shooting_multiple_weapons
- [ ] test_shooting_overwatch
- [ ] test_shooting_split_fire
- [ ] test_shooting_advanced_unit_restricted
- [ ] test_shooting_phase_completion

### Charge Phase ☐ Started | ☐ Complete
**File**: `tests/integration/test_multiplayer_charge.gd`

#### Test Saves (4 files)
- [ ] charge_start.w40ksave
- [ ] charge_far_target.w40ksave
- [ ] charge_with_terrain.w40ksave
- [ ] charge_multiple_enemies.w40ksave

#### Tests (7 tests)
- [ ] test_charge_basic_declaration
- [ ] test_charge_out_of_range
- [ ] test_charge_roll_insufficient
- [ ] test_charge_successful_move
- [ ] test_charge_triggers_overwatch
- [ ] test_charge_dangerous_terrain
- [ ] test_charge_multiple_targets

---

## Week 5-6: Melee Phase (Fight + Transitions)

### Fight Phase ☐ Started | ☐ Complete
**File**: `tests/integration/test_multiplayer_fight.gd`

#### Test Saves (9 files)
- [ ] fight_start.w40ksave
- [ ] fight_multiple_units.w40ksave
- [ ] fight_with_distance.w40ksave
- [ ] fight_after_attacks.w40ksave
- [ ] fight_multiple_enemies.w40ksave
- [ ] fight_character_nearby.w40ksave
- [ ] fight_nearly_complete.w40ksave
- [ ] fight_optional_activations.w40ksave
- [ ] fight_complex_melee.w40ksave

#### Tests (12 tests)
- [ ] test_fight_basic_attack
- [ ] test_fight_alternating_units
- [ ] test_fight_unit_activation_order
- [ ] test_fight_pile_in
- [ ] test_fight_attack_sequence
- [ ] test_fight_consolidate
- [ ] test_fight_model_removal
- [ ] test_fight_split_attacks
- [ ] test_fight_heroic_intervention
- [ ] test_fight_phase_end
- [ ] test_fight_manual_end_turn
- [ ] test_fight_complex_engagement

### Phase Transitions ☐ Started | ☐ Complete
**File**: `tests/integration/test_multiplayer_phase_transitions.gd`

#### Tests (6 tests)
- [ ] test_transition_deployment_to_movement
- [ ] test_transition_movement_to_shooting
- [ ] test_transition_shooting_to_charge
- [ ] test_transition_charge_to_fight
- [ ] test_transition_fight_to_end_turn
- [ ] test_complete_turn_cycle

---

## Week 7: Validation (Full Game)

### Full Game Smoke Tests ☐ Started | ☐ Complete
**File**: `tests/integration/test_multiplayer_full_game.gd`

#### Tests (2 tests)
- [ ] test_full_game_one_round
- [ ] test_full_game_three_rounds

---

## 📈 Progress Tracking

### Test Saves Created: 5/33 (15%)
- ✅ Deployment: 5/5 (100%)
- ☐ Movement: 0/6
- ☐ Shooting: 0/9
- ☐ Charge: 0/4
- ☐ Fight: 0/9

### Tests Implemented: 8/53 (15%)
- ✅ Deployment: 8/8 (100%)
- ☐ Movement: 0/10
- ☐ Shooting: 0/12
- ☐ Charge: 0/7
- ☐ Fight: 0/12
- ☐ Transitions: 0/6
- ☐ Full Game: 0/2

### Tests Passing: 2/53 (4%)
- ✅ Deployment: 2/8 passing (6 pending action system)
- ☐ Movement: 0/10
- ☐ Shooting: 0/12
- ☐ Charge: 0/7
- ☐ Fight: 0/12
- ☐ Transitions: 0/6
- ☐ Full Game: 0/2

---

## 🎯 Current Sprint Goals

### This Week
- [x] Create remaining deployment test saves (4 files) ✅ DONE
- [x] Implement all deployment tests (8 tests) ✅ DONE
- [ ] 🔨 Implement action simulation system (BLOCKER)
- [ ] Get all deployment tests passing

### Next Week
- [ ] Complete action simulation system
- [ ] Verify deployment tests pass
- [ ] Create movement test saves (6 files)
- [ ] Implement all movement tests (10 tests)

---

## 📝 Notes

### Blockers
- **Action Simulation System**: 6/8 deployment tests need ability to trigger game actions (deploy unit, undo, etc.) from tests
  - Current workaround: Tests marked as `gut.pending()`
  - Options:
    1. File-based command queue
    2. Network API for test commands
    3. Direct method calls via reflection
  - **Recommended**: File-based command queue (simplest for MVP)

### Learnings
- Test saves are easy to create once you have a template
- Tests can verify connection and phase sync without action system
- GUT's `pending()` is perfect for marking incomplete tests

### Technical Debt
- Need to implement action simulation system
- Helper functions in test file are stubs
- Some tests may need adjustment once real game actions are available

---

## 🔗 Quick Links

- **Full Test Plan**: `MULTIPLAYER_TEST_PLAN.md`
- **Run Tests**: `./tests/run_multiplayer_tests.sh`
- **Quick Test**: `./tests/test_quick.sh`

---

**Last Updated**: 2025-10-28
**Next Review**: After completing each sprint
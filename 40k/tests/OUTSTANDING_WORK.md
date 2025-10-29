# Outstanding Work for Complete Integration Test Suite

**Date:** 2025-10-28
**Status:** Phase 1 Infrastructure Complete - Implementation Phase Begins

---

## Current State

### ✅ **Completed Work**

**Test Infrastructure (100% Complete):**
- ✅ `MultiplayerIntegrationTest` base class created
- ✅ `GameInstance` helper for managing game processes
- ✅ `LogMonitor` for tracking game state via logs
- ✅ `TestModeHandler` autoload with action simulation
- ✅ Scene tree access bugs fixed
- ✅ Command file-based action simulation working
- ✅ All old tests archived to `tests/_archived/`

**Phase 1: Deployment Tests (100% Implemented, 0% Passing):**
- ✅ 10 test functions written in `test_multiplayer_deployment.gd`
- ✅ 5 test save files created
- ✅ Basic connection test infrastructure working
- ⚠️ Tests run but fail due to game state issues (not test framework issues)

**TestModeHandler Fixes (100% Complete):**
- ✅ Fixed `.has()` method error on Node
- ✅ Fixed phase access via GameState
- ✅ Fixed phase reporting with enum-to-string conversion
- ✅ All 4 action handlers implemented

---

## Immediate Next Steps (Priority 1)

### 1. **Debug Game Auto-Start in Test Mode** 🔴 CRITICAL

**Problem:** Game instances launch but don't properly enter Deployment phase when started via TestModeHandler

**Tasks:**
- [ ] Verify TestModeHandler's `_schedule_auto_start_game()` triggers correctly
- [ ] Check if MultiplayerLobby → Game scene transition works in test mode
- [ ] Ensure PhaseManager initializes to Deployment phase
- [ ] Debug why `get_game_state` returns phase != "Deployment"

**Success Criteria:**
- Game instances start in Deployment phase when auto-started
- `test_basic_multiplayer_connection` passes
- Phase name correctly reported as "Deployment"

**Estimated Time:** 2-4 hours

---

### 2. **Implement Missing GameManager Methods** 🔴 CRITICAL

**Current Status:** TestModeHandler calls these methods but they may not exist or work correctly

**Required Methods:**
- [ ] `GameManager.deploy_unit(unit_id: String, position: Vector2) -> bool`
- [ ] `GameManager.undo_last_action() -> bool`
- [ ] `GameManager.complete_deployment(player_id: int) -> bool`
- [ ] `GameManager.get_all_units() -> Dictionary` (optional, for debugging)

**Success Criteria:**
- `test_deployment_single_unit` passes
- Units can be deployed via action simulation
- Deployment appears on both host and client

**Estimated Time:** 3-5 hours

---

### 3. **Verify Multiplayer Sync for Deployment Actions** 🟡 HIGH

**Problem:** Actions may succeed on host but not sync to client

**Tasks:**
- [ ] Verify NetworkManager properly syncs deployment actions
- [ ] Check if RPC calls work when triggered via TestModeHandler
- [ ] Ensure client sees deployed units
- [ ] Test undo/redo syncs across network

**Success Criteria:**
- All 10 deployment tests pass
- Actions on host appear on client within 1 second
- Both instances show same game state

**Estimated Time:** 4-6 hours

---

## Phase 2: Movement Tests (0% Complete)

### Work Required:

**File Creation:**
- [ ] Create `tests/integration/test_multiplayer_movement.gd`
- [ ] Copy template from `test_multiplayer_deployment.gd`

**Test Save Files (6 required):**
- [ ] `movement_start.w40ksave` - Units deployed, ready to move
- [ ] `movement_nearly_complete.w40ksave` - Most moves done
- [ ] `movement_multi_model_unit.w40ksave` - 10-model unit for coherency
- [ ] `movement_with_terrain.w40ksave` - Difficult terrain on board
- [ ] `movement_with_enemies.w40ksave` - Enemy units nearby
- [ ] `movement_in_engagement.w40ksave` - Units in engagement range

**Test Implementation (10 tests):**
- [ ] `test_movement_basic_advance()` - Move unit 6"
- [ ] `test_movement_exceeds_range()` - Try to move beyond M characteristic
- [ ] `test_movement_maintains_coherency()` - Multi-model unit coherency
- [ ] `test_movement_difficult_terrain()` - Terrain reduces movement
- [ ] `test_movement_blocked_by_enemy()` - Can't move through enemy
- [ ] `test_movement_multiple_units()` - Move 3 units in sequence
- [ ] `test_movement_phase_completion()` - End movement, go to shooting
- [ ] `test_movement_undo_move()` - Undo movement action
- [ ] `test_movement_advance_action()` - Declare Advance (M+D6)
- [ ] `test_movement_fall_back()` - Fall Back from engagement

**TestModeHandler Actions (4 new handlers):**
- [ ] `_handle_move_unit(params)` - Move unit to position
- [ ] `_handle_advance_unit(params)` - Declare Advance
- [ ] `_handle_fall_back_unit(params)` - Declare Fall Back
- [ ] `_handle_end_movement_phase(params)` - Complete movement phase

**Estimated Time:** 5-7 days

---

## Phase 3: Shooting Tests (0% Complete)

### Work Required:

**File Creation:**
- [ ] Create `tests/integration/test_multiplayer_shooting.gd`

**Test Save Files (9 required):**
- [ ] `shooting_start.w40ksave`
- [ ] `shooting_nearly_complete.w40ksave`
- [ ] `shooting_long_range.w40ksave`
- [ ] `shooting_blocked_los.w40ksave`
- [ ] `shooting_with_modifiers.w40ksave`
- [ ] `shooting_mixed_weapons.w40ksave`
- [ ] `shooting_overwatch_opportunity.w40ksave`
- [ ] `shooting_multiple_targets.w40ksave`
- [ ] `shooting_with_advanced_unit.w40ksave`

**Test Implementation (12 tests):**
- [ ] `test_shooting_basic_attack()` - Full attack sequence
- [ ] `test_shooting_out_of_range()` - Reject targets beyond range
- [ ] `test_shooting_no_line_of_sight()` - Block shots without LoS
- [ ] `test_shooting_hit_roll_modifiers()` - Apply +1/-1 to hit
- [ ] `test_shooting_wound_roll()` - Calculate S vs T
- [ ] `test_shooting_save_roll()` - Apply AP modifier
- [ ] `test_shooting_damage_application()` - Remove wounds, models
- [ ] `test_shooting_multiple_weapons()` - Unit with 2+ weapons
- [ ] `test_shooting_overwatch()` - Defensive fire at -1 to hit
- [ ] `test_shooting_split_fire()` - Target multiple units
- [ ] `test_shooting_advanced_unit_restricted()` - Can't shoot if Advanced
- [ ] `test_shooting_phase_completion()` - End phase transition

**TestModeHandler Actions (5 new handlers):**
- [ ] `_handle_select_shooting_unit(params)` - Choose shooter
- [ ] `_handle_select_shooting_target(params)` - Choose target
- [ ] `_handle_resolve_shooting(params)` - Execute attack sequence
- [ ] `_handle_declare_overwatch(params)` - Reactive shooting
- [ ] `_handle_end_shooting_phase(params)` - Complete phase

**Estimated Time:** 6-8 days

---

## Phase 4: Charge Tests (0% Complete)

### Work Required:

**File Creation:**
- [ ] Create `tests/integration/test_multiplayer_charge.gd`

**Test Save Files (4 required):**
- [ ] `charge_start.w40ksave`
- [ ] `charge_far_target.w40ksave`
- [ ] `charge_with_terrain.w40ksave`
- [ ] `charge_multiple_enemies.w40ksave`

**Test Implementation (7 tests):**
- [ ] `test_charge_basic_declaration()` - Declare charge, roll 2D6
- [ ] `test_charge_out_of_range()` - Reject >12" charges
- [ ] `test_charge_roll_insufficient()` - Failed charge
- [ ] `test_charge_successful_move()` - Move to engagement range
- [ ] `test_charge_triggers_overwatch()` - Defender shoots
- [ ] `test_charge_dangerous_terrain()` - Terrain penalty
- [ ] `test_charge_multiple_targets()` - Charge 2+ units

**TestModeHandler Actions (3 new handlers):**
- [ ] `_handle_declare_charge(params)` - Declare charge target(s)
- [ ] `_handle_roll_charge_distance(params)` - Roll 2D6
- [ ] `_handle_end_charge_phase(params)` - Complete phase

**Estimated Time:** 4-5 days

---

## Phase 5: Fight Tests (0% Complete)

### Work Required:

**File Creation:**
- [ ] Create `tests/integration/test_multiplayer_fight.gd`

**Test Save Files (9 required):**
- [ ] `fight_start.w40ksave`
- [ ] `fight_multiple_units.w40ksave`
- [ ] `fight_with_distance.w40ksave`
- [ ] `fight_after_attacks.w40ksave`
- [ ] `fight_multiple_enemies.w40ksave`
- [ ] `fight_character_nearby.w40ksave`
- [ ] `fight_nearly_complete.w40ksave`
- [ ] `fight_optional_activations.w40ksave`
- [ ] `fight_complex_melee.w40ksave`

**Test Implementation (12 tests):**
- [ ] `test_fight_basic_attack()` - Melee attack sequence
- [ ] `test_fight_alternating_units()` - Players alternate activation
- [ ] `test_fight_unit_activation_order()` - Chargers go first
- [ ] `test_fight_pile_in()` - 3" move toward enemy
- [ ] `test_fight_attack_sequence()` - Full combat resolution
- [ ] `test_fight_consolidate()` - 3" move after fighting
- [ ] `test_fight_model_removal()` - Remove casualties
- [ ] `test_fight_split_attacks()` - Attack 2+ enemies
- [ ] `test_fight_heroic_intervention()` - Character 6" move
- [ ] `test_fight_phase_end()` - All units activated
- [ ] `test_fight_manual_end_turn()` - Early phase end
- [ ] `test_fight_complex_engagement()` - 3+ units per side

**TestModeHandler Actions (6 new handlers):**
- [ ] `_handle_select_fight_unit(params)` - Choose which unit fights
- [ ] `_handle_pile_in(params)` - 3" pile in move
- [ ] `_handle_resolve_fight(params)` - Execute melee attacks
- [ ] `_handle_consolidate(params)` - 3" consolidate move
- [ ] `_handle_heroic_intervention(params)` - Character move
- [ ] `_handle_end_fight_phase(params)` - Complete phase

**Estimated Time:** 7-9 days

---

## Phase 6: Phase Transition Tests (0% Complete)

### Work Required:

**File Creation:**
- [ ] Create `tests/integration/test_multiplayer_phase_transitions.gd`

**Test Save Files:**
- Reuses saves from other phases (no new saves needed)

**Test Implementation (6 tests):**
- [ ] `test_transition_deployment_to_movement()` - First transition
- [ ] `test_transition_movement_to_shooting()` - Mid-turn transition
- [ ] `test_transition_shooting_to_charge()` - Pre-combat transition
- [ ] `test_transition_charge_to_fight()` - Combat begins
- [ ] `test_transition_fight_to_end_turn()` - Turn ends
- [ ] `test_complete_turn_cycle()` - Full turn sequence

**TestModeHandler Actions:**
- No new handlers needed (uses existing phase completion handlers)

**Estimated Time:** 3-4 days

---

## Phase 7: Full Game Smoke Tests (0% Complete)

### Work Required:

**File Creation:**
- [ ] Create `tests/integration/test_multiplayer_full_game.gd`

**Test Save Files:**
- Uses `deployment_start.w40ksave` (already created)

**Test Implementation (2 tests):**
- [ ] `test_full_game_one_round()` - Complete game round
  - Full deployment
  - Player 1 full turn (all phases)
  - Player 2 full turn (all phases)
  - Verify no crashes, clients synced
- [ ] `test_full_game_three_rounds()` - Multi-round game
  - 3 complete rounds
  - Turn counter increments
  - Performance check
  - Save/load mid-game

**TestModeHandler Actions:**
- No new handlers needed (orchestrates existing handlers)

**Estimated Time:** 3-4 days

---

## Supporting Work

### Documentation

- [ ] **Test Writing Guide** - How to add new tests
- [ ] **Test Save Creation Guide** - How to create test saves manually
- [ ] **Action Handler Guide** - How to add new TestModeHandler actions
- [ ] **Troubleshooting Guide** - Common test failures and fixes
- [ ] **CI/CD Integration Guide** - Running tests in automation

**Estimated Time:** 2-3 days

---

### Test Infrastructure Improvements

**Optional but Recommended:**

- [ ] **Parallel Test Execution** - Run multiple test files simultaneously
- [ ] **Test Result Reporting** - Generate HTML reports with screenshots
- [ ] **Automatic Save File Validation** - Verify save files are valid before tests
- [ ] **Network Latency Simulation** - Test with artificial lag
- [ ] **Deterministic Dice Rolls** - Seed RNG for repeatable tests
- [ ] **Test Data Cleanup** - Auto-delete old command/result files
- [ ] **Video Recording** - Record test execution for debugging

**Estimated Time:** 5-7 days (if pursued)

---

## Test Metrics & Goals

### Coverage Goals (from original plan)

| Phase | Tests Planned | Tests Implemented | Tests Passing | % Complete |
|-------|---------------|-------------------|---------------|------------|
| Deployment | 10 | 10 | 0 | 10% |
| Movement | 10 | 0 | 0 | 0% |
| Shooting | 12 | 0 | 0 | 0% |
| Charge | 7 | 0 | 0 | 0% |
| Fight | 12 | 0 | 0 | 0% |
| Transitions | 6 | 0 | 0 | 0% |
| Smoke | 2 | 0 | 0 | 0% |
| **Total** | **59** | **10** | **0** | **17%** |

### Performance Goals

- [ ] Individual test execution: < 60 seconds
- [ ] Phase test suite: < 5 minutes
- [ ] Full test suite: < 30 minutes
- [ ] Test pass rate: > 95%
- [ ] Flake rate: < 5%

---

## Timeline Estimate

### Aggressive Schedule (Full-Time)
- **Week 1-2:** Fix Phase 1 blockers, all deployment tests passing
- **Week 3-4:** Movement + Shooting tests complete
- **Week 5-6:** Charge + Fight tests complete
- **Week 7:** Transitions + Smoke tests + Documentation
- **Total:** 7 weeks

### Realistic Schedule (Part-Time)
- **Weeks 1-3:** Debug and fix Phase 1 (deployment)
- **Weeks 4-7:** Movement tests
- **Weeks 8-11:** Shooting tests
- **Weeks 12-15:** Charge + Fight tests
- **Weeks 16-18:** Transitions + Smoke + Docs
- **Total:** 18 weeks (4.5 months)

### Current Velocity
- **Test Infrastructure:** 100% complete (1 week actual)
- **Deployment Tests:** 100% implemented, 0% passing
- **Estimated Remaining:** 4-5 weeks (aggressive) or 17 weeks (realistic)

---

## Critical Path Items

These must be completed before meaningful progress can be made:

1. 🔴 **Game Auto-Start Fix** - Without this, no tests can run
2. 🔴 **GameManager Methods** - Without these, tests pass but do nothing
3. 🔴 **Network Sync Verification** - Without this, multiplayer tests are invalid

**Estimated Critical Path:** 1-2 days of focused work

---

## Risk Assessment

### High Risk Items

1. **Network Synchronization Bugs**
   - Risk: Actions work locally but don't sync
   - Mitigation: Add explicit sync verification to each test
   - Impact: Could invalidate entire test suite

2. **Test Environment Instability**
   - Risk: Tests pass/fail randomly
   - Mitigation: Add retry logic, better error messages
   - Impact: Reduces confidence in test results

3. **Save File Corruption**
   - Risk: Test saves become invalid after game updates
   - Mitigation: Version save files, auto-validation
   - Impact: Tests fail for wrong reasons

### Medium Risk Items

1. **Performance Degradation**
   - Risk: Tests take too long to run
   - Mitigation: Optimize, parallelize
   - Impact: Developers won't run tests

2. **Maintenance Burden**
   - Risk: Tests require constant updates
   - Mitigation: Good abstraction, helper functions
   - Impact: Tests become abandonware

---

## Success Criteria

### MVP (Minimum Viable Product)
- ✅ Test infrastructure complete
- [ ] All 10 deployment tests passing
- [ ] All 10 movement tests passing
- [ ] Tests run in < 10 minutes
- [ ] 0 flaky tests
- [ ] Documentation for adding new tests

### Full Release
- [ ] All 59 tests passing
- [ ] Full test suite runs in < 30 minutes
- [ ] < 5% flake rate
- [ ] Comprehensive documentation
- [ ] CI/CD integration
- [ ] Video recordings of test execution

---

## Next Actions (This Week)

**Day 1:**
1. Fix game auto-start in test mode
2. Verify first test passes

**Day 2:**
3. Implement GameManager.deploy_unit()
4. Verify deployment tests pass

**Day 3:**
5. Test network sync for deployment
6. Fix any sync issues

**Day 4:**
7. All 10 deployment tests passing
8. Document lessons learned

**Day 5:**
9. Begin movement test implementation
10. Create movement test saves

---

**Last Updated:** 2025-10-28 13:30 UTC
**Status:** Infrastructure Complete - Debugging Phase
**Next Milestone:** All Deployment Tests Passing

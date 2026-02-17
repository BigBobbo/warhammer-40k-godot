# Secondary Missions Implementation Tasks (Tactical Mode)

## Phase 1: Data & State Foundation ---- COMPLETE

### Task 1: Secondary Mission Card Data Definitions -- COMPLETE
- [x] Create `SecondaryMissionData.gd` with all 19 mission cards defined as structured data
- [x] Fields: id, name, category, type (fixed/tactical/both), scoring conditions, VP values, when_drawn rules, action requirements
- [x] Single source of truth for all mission card content
- File: `scripts/data/SecondaryMissionData.gd`

### Task 2: SecondaryMissionManager (Autoload) -- COMPLETE
- [x] New autoload managing per-player state: deck (shuffled array), active cards (max 2), discard pile, secondary VP scored
- [x] Core functions: `setup_tactical_deck()`, `draw_missions_to_hand()`, `voluntary_discard()`, `get_active_missions()`, `score_secondary_missions_for_player()`
- [x] VP cap enforcement (40VP secondary, 90VP combined primary+secondary)
- [x] Registered in project.godot as autoload
- File: `autoloads/SecondaryMissionManager.gd`

### Task 3: GameState Integration -- COMPLETE
- [x] Add `secondary_vp` to player state alongside existing `vp`/`primary_vp`
- [x] Secondary mission tracking managed in SecondaryMissionManager._player_state per player
- [x] Update `get_vp_summary()` in MissionManager to include secondary VP
- Files modified: `autoloads/GameState.gd`, `autoloads/MissionManager.gd`

## Phase 2: Core Game Flow ---- COMPLETE

### Task 4: Pre-Game Setup -- COMPLETE
- [x] When game starts, auto-shuffle each player's 18-card tactical deck (excluding Display of Might from standard deck)
- [x] Triggered at start of first Command Phase (battle round 1, player 1)
- File modified: `phases/CommandPhase.gd`

### Task 5: Command Phase Integration - Card Drawing -- MOSTLY COMPLETE
- [x] At start of Command Phase, draw up to 2 active cards per player
- [x] Handle "When Drawn" conditions (e.g., Behind Enemy Lines shuffled back in Round 1; Cull the Horde discarded if no valid targets; Marked for Death triggers opponent interaction)
- [x] Backend for New Orders stratagem (1CP to swap a card) implemented in `SecondaryMissionManager.use_new_orders()`
- [ ] Register New Orders as a stratagem in StratagemManager
- [ ] UI for New Orders at end of Command Phase
- File modified: `phases/CommandPhase.gd`

### Task 6: End-of-Turn Scoring Framework -- COMPLETE
- [x] In ScoringPhase, before turn switch: evaluate all active secondary missions for the active player
- [x] Also evaluates end-of-opponent-turn missions for the opponent
- [x] Auto-discard achieved missions (those that scored VP)
- [x] Voluntary discard action available in ScoringPhase (player gets 1CP if on their turn)
- [x] Handle deck depletion (no more draws when empty, signal emitted)
- File modified: `phases/ScoringPhase.gd`

## Phase 3: Scoring Logic ---- BACKEND COMPLETE, NEEDS GAMEPLAY TESTING

### Task 7: Positional Mission Scoring (4 missions) -- BACKEND COMPLETE
- [x] Behind Enemy Lines: `_check_units_in_opponent_zone()` - checks units wholly in opponent's deployment zone
- [x] Engage on All Fronts: `_check_table_quarter_presence()` - checks presence in table quarters >6" from center
- [x] Area Denial: `_check_area_denial()` - checks units within 3"/6" of board center, no enemies nearby
- [x] Display of Might: `_check_display_of_might()` - compares unit counts wholly in No Man's Land
- **Needs gameplay testing to verify geometry checks work correctly**

### Task 8: Objective Control Mission Scoring (5 missions) -- BACKEND COMPLETE
- [x] Storm Hostile Objective: `_check_storm_hostile_objective()` - tracks objective control at start vs end of turn
- [x] Defend Stronghold: `_check_own_zone_objectives()` - checks own deployment zone objectives (round 2+, end of opponent turn)
- [x] Secure No Man's Land: `_check_nml_objectives()` - counts No Man's Land objectives controlled
- [x] A Tempting Target: `_check_tempting_target()` - checks control of opponent-chosen objective
- [x] Extend Battle Lines: `_check_extend_battle_lines()` - checks objectives in own zone AND No Man's Land
- **Needs gameplay testing to verify objective zone lookups**

### Task 9: Kill-Based Mission Scoring (6 missions) -- BACKEND COMPLETE, NEEDS INTEGRATION
- [x] Assassination: `_check_characters_destroyed_this_turn()` / `_check_all_enemy_characters_destroyed()`
- [x] No Prisoners: `_check_enemy_unit_destroyed_this_turn()` (while_active, 2VP up to 5VP)
- [x] Cull the Horde: `_check_infantry_horde_destroyed()` (INFANTRY starting strength 13+)
- [x] Bring It Down: `_check_monster_vehicle_destroyed()` (MONSTER/VEHICLE)
- [x] Overwhelming Force: `_check_overwhelming_force()` (units near objectives, 3VP up to 5VP)
- [x] Marked for Death: `_check_alpha_target_destroyed()` / `_check_gamma_target_destroyed()`
- [ ] **BLOCKER: RulesEngine/combat phases must call `SecondaryMissionManager.on_unit_destroyed()` with unit data when units are destroyed. Without this hook, kill-based missions will never trigger.**

### Task 10: Action-Based Mission System (4 missions) -- STUBS ONLY
- [x] Scoring condition checkers implemented (read from `_active_actions` array)
- [ ] New Action mechanic: units start Actions in Shooting Phase, complete at end of turn
- [ ] Establish Locus: action within opponent's zone or 6" of center (2VP/4VP)
- [ ] Cleanse: action on objectives outside own deployment zone (2VP/4-5VP)
- [ ] Sabotage: action within terrain, not in own deployment zone (3VP/6VP)
- [ ] Recover Assets: 2+ units in different battlefield zones simultaneously (3VP/5VP)
- [ ] **BLOCKER: Requires Shooting Phase integration (unit cannot shoot while performing an action). Needs new UI for selecting "Perform Action" instead of shooting.**

## Phase 4: UI & Interaction ---- PARTIALLY COMPLETE

### Task 11: Active Missions HUD Panel -- PARTIALLY COMPLETE
- [x] Scoring phase right panel shows active secondary missions with name, category, and scoring timing
- [x] VP breakdown (primary + secondary) displayed for both players
- [x] Deck remaining count and discard count shown
- [ ] Persistent panel visible during ALL phases (not just Scoring)
- [ ] Visual indicators for achieved/in-progress missions (color coding, icons)
- File modified: `scripts/ScoringController.gd`

### Task 12: Opponent Interaction Dialogs -- BACKEND ONLY
- [x] Backend: `resolve_marked_for_death(player, alpha_targets, gamma_target)` stores targets
- [x] Backend: `resolve_tempting_target(player, objective_id)` stores target objective
- [x] Signal `when_drawn_requires_interaction` emitted when card needs opponent input
- [ ] Modal UI dialog for opponent to pick 3 units (Marked for Death)
- [ ] Modal UI dialog for opponent to pick objective in No Man's Land (A Tempting Target)
- [ ] UI flow to pause card draw and prompt opponent

### Task 13: Voluntary Discard & New Orders UI -- BACKEND ONLY
- [x] Backend: `voluntary_discard()` removes card and grants 1CP
- [x] Backend: `use_new_orders()` discards card and draws replacement for 1CP
- [x] ScoringPhase exposes DISCARD_SECONDARY action in `get_available_actions()`
- [ ] Clickable discard buttons next to each active mission in scoring UI
- [ ] New Orders stratagem button/option at end of Command Phase

## Phase 5: Polish & Testing ---- PARTIALLY COMPLETE

### Task 14: VP Display Updates -- PARTIALLY COMPLETE
- [x] `MissionManager.get_vp_summary()` returns primary + secondary breakdown
- [x] ScoringController right panel shows VP summary
- [ ] Update HUD_Bottom VP display to show breakdown during all phases
- [ ] End-of-game summary screen showing mission-by-mission VP totals

### Task 15: Testing & Validation -- PARTIALLY COMPLETE
- [x] 39 unit tests passing for mission data integrity (`tests/test_secondary_missions.gd`)
- [ ] Test scoring conditions for each mission type in actual gameplay
- [ ] Test deck mechanics end-to-end (shuffle, draw, When Drawn, discard, depletion)
- [ ] Test VP caps (40VP secondary, 90VP combined) hit correctly
- [ ] Test action-based mission eligibility rules
- [ ] Test opponent interaction flow (Marked for Death, A Tempting Target)

## Implementation Order
1 → 2 → 3 → 4 → 5 → 11 → 6 → 7 → 8 → 12 → 9 → 10 → 13 → 14 → 15

## Files Created/Modified

### New files:
- `scripts/data/SecondaryMissionData.gd` - All 19 mission card definitions
- `autoloads/SecondaryMissionManager.gd` - Deck, drawing, scoring, VP management
- `tests/test_secondary_missions.gd` - 39 unit tests

### Modified files:
- `project.godot` - Added SecondaryMissionManager autoload
- `autoloads/GameState.gd` - Added `secondary_vp` to player state
- `autoloads/MissionManager.gd` - Updated `get_vp_summary()` with secondary VP
- `phases/CommandPhase.gd` - Deck init on round 1, card draw each command phase
- `phases/ScoringPhase.gd` - Secondary scoring, voluntary discard action, opponent scoring
- `scripts/ScoringController.gd` - UI shows active missions, VP breakdown, deck status

## Priority for Remaining Work
1. **Kill hooks** (Task 9 blocker) - Wire `on_unit_destroyed()` into RulesEngine combat resolution
2. **Opponent interaction UI** (Task 12) - Modals for Marked for Death / A Tempting Target
3. **Action system** (Task 10 blocker) - Shooting Phase "Perform Action" mechanic
4. **Persistent HUD** (Task 11) - Show missions during all phases
5. **New Orders UI** (Tasks 5, 13) - Register stratagem and add UI
6. **VP displays** (Task 14) - Update all HUD VP readouts
7. **Gameplay testing** (Task 15) - End-to-end validation

## Reference
- Chapter Approved 2025-26 rules: https://wahapedia.ru/wh40k10ed/the-rules/chapter-approved-2025-26/
- Local reference: 40k/deployment_zones/Chapter Approved 2025-26.htm
- 19 total secondary mission cards (18 in standard tournament deck, Display of Might excluded)
- Cards 1-9: Can be Fixed or Tactical; Cards 10-19: Tactical only
- VP caps: 40VP secondary, 50VP primary, 90VP combined (primary+secondary+challenger)

# Stratagems & Unit Abilities Implementation Plan

## Current State Assessment

### What Exists
- **44,000+ lines** of Godot 4.4 GDScript across 24 autoload managers, 8 game phases, controllers, and UI
- Complete phase flow: Deployment -> Command -> Movement -> Shooting -> Charge -> Fight -> Scoring
- Robust combat resolution: hit rolls, wound rolls, saves, damage allocation, FNP
- **Weapon keywords fully implemented**: Lethal Hits, Sustained Hits, Devastating Wounds, Blast, Torrent, Rapid Fire, Heavy, Assault, Pistol, Ignores Cover
- Hit modifier system (`HitModifier` enum with REROLL_ONES, PLUS_ONE, MINUS_ONE) -- currently populated manually via UI checkboxes
- **1,397 stratagem definitions** in `server/tools/wahapedia_csv/Stratagems.csv`
- **84,571 datasheet-to-stratagem mappings** in `Datasheets_stratagems.csv`
- Full ability data in army JSON files (`meta.abilities` array per unit)
- Ability data in `Abilities.csv` and `Datasheets_abilities.csv`

### What's Missing

**Stratagems: Not implemented at all**
- `GameManager.process_use_stratagem()` returns empty success (line 525-526)
- `MoralePhase._process_use_stratagem()` has skeleton code with TODOs (line 198-232)
- No stratagem data loaded into the game engine
- No stratagem UI
- No CP spending/tracking for stratagems

**Unit Abilities: Stored but mostly unused**
- Only 6 abilities are actually functional: Deep Strike, Infiltrators, Fights First, Leader, Transport, Firing Deck
- All other datasheet abilities (e.g., "Might is Right: +1 to Hit while leading") are stored in JSON but **never read during gameplay**
- No system to parse ability descriptions into mechanical effects
- No aura system for abilities that affect nearby units
- Hit/wound modifiers exist in RulesEngine but are only populated from manual UI checkboxes, not from abilities

---

## Stratagem Categorization

Analysis of all 1,397 stratagems reveals they fall into these mechanical effect groups:

| # | Effect Category | Count | Complexity | Example |
|---|----------------|-------|-----------|---------|
| 1 | Stat Modifiers (+/-1 Hit/Wound/AP/Damage) | ~170 | Low-Medium | ARMOUR OF CONTEMPT: worsen AP by 1 |
| 2 | Re-rolls (Hit, Wound, Save, Charge, etc.) | ~107 | Medium | COMMAND RE-ROLL: re-roll any single roll |
| 3 | Weapon Keyword Granting (Lethal/Sustained/etc.) | ~95 | Medium | STORM OF FIRE: gain [IGNORES COVER] |
| 4 | Eligibility Flags (Fall Back+Shoot, Advance+Charge) | ~90 | Low | Fall back and still shoot/charge |
| 5 | Mortal Wound Dealing/Protection | ~89 | Low | GRENADE: roll 6D6, 4+ = 1 MW each |
| 6 | Defensive Buffs (Invuln, FNP, Cover) | ~75 | Low-Medium | GO TO GROUND: 6+ invuln + cover |
| 7 | Battle-shock Manipulation | ~60 | Medium | INSANE BRAVERY: auto-pass shock test |
| 8 | Reactive Movement (out-of-phase moves) | ~55 | Medium-High | Move D6" after being shot at |
| 9 | Charge Modification (+/- charge rolls) | ~51 | Medium | Subtract 2 from enemy charge roll |
| 10 | Reserves/Deep Strike Manipulation | ~50 | Medium | RAPID INGRESS: arrive during enemy turn |
| 11 | Fight-on-Death | ~42 | High | Fight before being removed from play |
| 12 | Out-of-Sequence Shooting | ~40 | High | FIRE OVERWATCH: shoot during enemy move |
| 13 | Transport Interaction | ~39 | Medium | Embark/disembark outside normal timing |
| 14 | Model Resurrection/Healing | ~37 | Medium-High | Return D3+3 destroyed models |
| 15 | Move Characteristic Modification | ~35 | Low | Add D6" to Move characteristic |
| 16 | Critical Hit Threshold Modification | ~30 | Medium | Crit hits on 5+ instead of 6 |
| 17 | Pile-in/Consolidation Modification | ~29 | Low-Medium | 6" pile-in instead of 3" |
| 18 | Objective Control / Sticky Objectives | ~20 | Low | Objective stays controlled after leaving |
| 19 | Fight Order (Counter-Offensive) | ~3 | Medium | Your unit fights next |
| 20 | CP Generation | ~1 | Low | Gain 1 CP on condition |

**Key insight**: Implementing the top 6 categories covers ~625 stratagems (~45% of all). These are also the lowest-complexity effects.

### The 11 Core Stratagems (Available to All Armies)

These are universal and highest priority:

| Stratagem | CP | Phase | Effect |
|-----------|-----|-------|--------|
| **COMMAND RE-ROLL** | 1 | Any | Re-roll any single dice roll |
| **EPIC CHALLENGE** | 1 | Fight | CHARACTER melee attacks gain [PRECISION] |
| **INSANE BRAVERY** | 1 | Command | Auto-pass Battle-shock test (once/battle) |
| **GO TO GROUND** | 1 | Opponent Shooting | INFANTRY gains 6+ invuln + cover |
| **SMOKESCREEN** | 1 | Opponent Shooting | SMOKE unit gains cover + Stealth |
| **GRENADE** | 1 | Shooting | GRENADES unit: roll 6D6, 4+ = 1 MW |
| **TANK SHOCK** | 1 | Charge | VEHICLE: roll D6 = Toughness, 5+ = MW |
| **FIRE OVERWATCH** | 1 | Opponent Move/Charge | Shoot enemy (only hit on 6s) |
| **RAPID INGRESS** | 1 | Opponent Movement | Reserves unit arrives during enemy turn |
| **HEROIC INTERVENTION** | 1 | Opponent Charge | Declare counter-charge within 6" |
| **COUNTER-OFFENSIVE** | 2 | Fight | Your unit fights next |

---

## Architecture Design Options

### Option A: Hardcoded Stratagem System
Code each stratagem as a specific function in GDScript. Each stratagem has its own validation and effect logic.

**Pros**: Simple, explicit, easy to test individually
**Cons**: Doesn't scale to 1,397 stratagems, massive code duplication, each new stratagem = new code

### Option B: Data-Driven Effect Composition System (Recommended)
Define an **effect language** where stratagems and abilities are composed of reusable effect primitives. A stratagem definition specifies timing, targeting rules, CP cost, and a list of effects drawn from a shared library.

**Pros**: Scales to all stratagems, same system handles abilities, consistent behavior, testable
**Cons**: More upfront design work, some edge cases need special handling

### Option C: Hybrid (Recommended for Staged Approach)
Start with hardcoded implementations for the 11 Core Stratagems to validate the UI/timing framework, then refactor to data-driven as patterns emerge.

**Pros**: Ship value fast, learn what abstractions are needed from real code, avoid premature abstraction
**Cons**: Some rework when transitioning to data-driven

**Recommendation: Option C (Hybrid/Staged)**

---

## Staged Implementation Plan

### Stage 1: Foundation -- Stratagem Data Pipeline + UI Framework

**Goal**: Get stratagem data into the game, build the UI for selecting/using stratagems, implement CP tracking.

#### 1.1 Stratagem Data Model

Create a `StratagemData` resource/dictionary format:

```gdscript
# Example stratagem definition
{
    "id": "command_re_roll",
    "name": "COMMAND RE-ROLL",
    "type": "Core",           # Core, Battle Tactic, Strategic Ploy, Epic Deed, Wargear
    "cp_cost": 1,
    "timing": {
        "turn": "either",     # "your", "opponent", "either"
        "phase": "any",       # "command", "movement", "shooting", "charge", "fight", "any"
        "when": "after_roll"  # Specific trigger point
    },
    "target": {
        "type": "unit",       # "unit", "model", "weapon", "objective"
        "owner": "friendly",  # "friendly", "enemy"
        "keywords": [],       # Required keywords (e.g., ["INFANTRY"])
        "conditions": []      # Additional conditions
    },
    "effects": [
        {"type": "reroll", "target": "last_roll"}
    ],
    "restrictions": {
        "once_per": null,     # null, "turn", "phase", "battle"
        "max_uses": -1        # -1 = unlimited
    },
    "faction_id": "",         # Empty = Core/universal
    "detachment": ""          # Empty = not detachment-specific
}
```

#### 1.2 StratagemManager (New Autoload)

New autoload singleton responsible for:
- Loading stratagem definitions (from JSON, parsed from CSV data)
- Tracking which stratagems are available to each player (based on faction + detachment)
- Tracking usage (once-per-battle, once-per-turn restrictions)
- Validating stratagem use (correct phase, enough CP, valid target, timing)
- Providing the list of usable stratagems at any point in the game

#### 1.3 Stratagem UI

- **Stratagem Panel**: Always-visible sidebar showing available stratagems for current phase
- **Stratagem Card**: Shows name, CP cost, timing, description, and a "Use" button
- **CP Counter**: Display in the HUD (partially exists in player state already)
- **Confirmation Dialog**: "Use [Stratagem] on [Target] for [X] CP?"
- **Usage Log**: Show in the action log when stratagems are used

#### 1.4 Event/Trigger System

The critical architectural piece. Stratagems fire at specific **trigger points** during gameplay. Need to define hooks at:

```
COMMAND_PHASE_START
BATTLE_SHOCK_BEFORE_TEST        # Insane Bravery
BATTLE_SHOCK_AFTER_FAIL         # Insane Bravery (boarding)
COMMAND_PHASE_END               # New Orders

MOVEMENT_PHASE_START
UNIT_BEFORE_MOVE                # Movement stratagems
UNIT_AFTER_MOVE
UNIT_AFTER_ADVANCE
UNIT_AFTER_FALL_BACK            # Fall back + shoot/charge stratagems
ENEMY_UNIT_AFTER_MOVE           # Fire Overwatch trigger
ENEMY_UNIT_SET_UP               # Fire Overwatch trigger
MOVEMENT_PHASE_END              # Rapid Ingress

SHOOTING_PHASE_START
SHOOTER_SELECTED
TARGETS_SELECTED                # Go to Ground, Smokescreen (opponent)
AFTER_HIT_ROLL                  # Command Re-roll
AFTER_WOUND_ROLL                # Command Re-roll
AFTER_SAVE_ROLL                 # Command Re-roll
AFTER_DAMAGE_ROLL               # Command Re-roll
UNIT_AFTER_SHOOTING             # Fire and Fade
SHOOTING_PHASE_END

CHARGE_PHASE_START
CHARGE_DECLARED                 # Fire Overwatch trigger
AFTER_CHARGE_ROLL               # Command Re-roll
CHARGE_MOVE_COMPLETED           # Tank Shock, Heroic Intervention
CHARGE_PHASE_END

FIGHT_PHASE_START
FIGHTER_SELECTED                # Epic Challenge
AFTER_ENEMY_FOUGHT              # Counter-Offensive
AFTER_HIT_ROLL_MELEE
AFTER_WOUND_ROLL_MELEE
AFTER_SAVE_ROLL_MELEE
MODEL_DESTROYED_BEFORE_FIGHT    # Fight-on-death stratagems
FIGHT_PHASE_END
```

Each phase would emit these signals, and the StratagemManager listens and prompts the player when relevant stratagems are available.

#### 1.5 CP Tracking Enhancement

Current state: `players.X.cp` exists but is only incremented in Command phase.
Needed: Decrement on stratagem use, validation before use, display in UI.

---

### Stage 2: Core Stratagems (11 Universal Stratagems)

Implement the 11 Core stratagems that every army can use. This validates the entire framework.

#### Group A: Dice Modification (builds on existing HitModifier system)
- **COMMAND RE-ROLL** -- The hardest of the Core stratagems. Requires prompting after ANY roll result to offer a re-roll. Needs the trigger system from Stage 1.

#### Group B: Combat Modifier Stratagems
- **EPIC CHALLENGE** -- Grant [PRECISION] to CHARACTER melee attacks. Relatively simple: add a flag checked during fight phase weapon resolution.
- **GO TO GROUND** -- Grant 6+ invulnerable save + Benefit of Cover to INFANTRY. Modify save calculation in RulesEngine.
- **SMOKESCREEN** -- Grant Cover + Stealth to SMOKE units. Same save modification path.

#### Group C: Special Action Stratagems
- **GRENADE** -- Roll 6D6, each 4+ deals 1 mortal wound. New action type in Shooting phase. Requires mortal wound application (bypasses normal attack sequence).
- **TANK SHOCK** -- Roll D6 equal to Vehicle Toughness, 5+ = 1 MW. New action in Charge phase post-charge-move.

#### Group D: Reactive/Interrupt Stratagems (Hardest)
- **FIRE OVERWATCH** -- Shoot during opponent's move/charge phase, but only hit on unmodified 6s. Requires calling shooting resolution from movement/charge phase.
- **HEROIC INTERVENTION** -- Declare counter-charge during opponent's charge phase. Requires calling charge resolution during opponent's turn.
- **COUNTER-OFFENSIVE** -- Override fight order so your unit fights next. Requires a fight queue system.
- **RAPID INGRESS** -- Place reserves unit during opponent's movement phase end. Requires reserves deployment callable from non-movement phase.

#### Group E: Morale Stratagem
- **INSANE BRAVERY** -- Auto-pass Battle-shock test (once per battle). Simplest stratagem; intercept before battle-shock roll.

**Recommended implementation order within Stage 2:**
1. INSANE BRAVERY (simplest, validates trigger system)
2. GO TO GROUND + SMOKESCREEN (validates defensive modifier path)
3. EPIC CHALLENGE (validates weapon keyword granting path)
4. GRENADE + TANK SHOCK (validates mortal wound path)
5. COMMAND RE-ROLL (validates universal re-roll system)
6. COUNTER-OFFENSIVE (validates fight order manipulation)
7. FIRE OVERWATCH (validates cross-phase shooting)
8. HEROIC INTERVENTION (validates cross-phase charging)
9. RAPID INGRESS (validates cross-phase reserves)

---

### Stage 3: Effect Primitives Library

After Core stratagems prove the framework, extract reusable effect types:

```gdscript
# Effect primitives that can be composed
enum EffectType {
    # Dice modification
    REROLL_HIT,           # Re-roll hit roll(s)
    REROLL_WOUND,         # Re-roll wound roll(s)
    REROLL_SAVE,          # Re-roll save(s)
    REROLL_ANY,           # Re-roll any single roll
    PLUS_ONE_HIT,         # +1 to hit rolls
    MINUS_ONE_HIT,        # -1 to hit rolls
    PLUS_ONE_WOUND,       # +1 to wound rolls
    MINUS_ONE_WOUND,      # -1 to wound rolls
    IMPROVE_AP,           # Improve AP by N
    WORSEN_AP,            # Worsen AP by N
    PLUS_DAMAGE,          # +N to damage
    MINUS_DAMAGE,         # -N from damage (min 1)

    # Weapon keywords
    GRANT_LETHAL_HITS,
    GRANT_SUSTAINED_HITS,
    GRANT_DEVASTATING_WOUNDS,
    GRANT_IGNORES_COVER,
    GRANT_PRECISION,
    GRANT_LANCE,
    GRANT_TWIN_LINKED,
    GRANT_HAZARDOUS,

    # Defensive
    GRANT_INVULN,         # Grant invulnerable save (value)
    GRANT_FNP,            # Grant Feel No Pain (value)
    GRANT_COVER,          # Grant Benefit of Cover
    GRANT_STEALTH,        # Grant Stealth (-1 to hit)

    # Movement/eligibility
    FALL_BACK_AND_SHOOT,
    FALL_BACK_AND_CHARGE,
    ADVANCE_AND_CHARGE,
    ADVANCE_AND_SHOOT,    # (no penalty)
    NORMAL_MOVE,          # Out-of-sequence normal move (distance)
    ADD_MOVE,             # Add to Move characteristic

    # Mortal wounds
    DEAL_MORTAL_WOUNDS,   # Roll XD6, on Y+ deal MW

    # Battle-shock
    AUTO_PASS_SHOCK,
    FORCE_SHOCK_TEST,

    # Critical threshold
    CRIT_HIT_ON,          # Critical hits on X+ instead of 6
    CRIT_WOUND_ON,        # Critical wounds on X+ instead of 6

    # Misc
    FIGHT_ON_DEATH,
    FIGHT_NEXT,           # Counter-Offensive
    RETURN_MODELS,        # Resurrect destroyed models
    HEAL_WOUNDS,          # Restore wounds
    STICKY_OBJECTIVE,     # Objective stays controlled
}
```

Each effect would have:
- `type`: The EffectType enum
- `value`: Numeric parameter (e.g., save value, move distance, number of dice)
- `duration`: "end_of_phase", "end_of_turn", "end_of_battle"
- `condition`: Optional condition (e.g., "target_keyword:PSYKER", "within_range:6")
- `scope`: "model", "unit", "weapon" -- what the effect applies to

---

### Stage 4: Faction Detachment Stratagems

With the effect primitives library, faction stratagems become data entries. Focus on factions present in army JSON files:

1. **Space Marines** (233 stratagems across detachments)
2. **Orks** (62 stratagems)
3. **Adeptus Custodes** (44 stratagems)

For each faction, load their detachment's stratagems from parsed CSV data. Most will map directly to effect primitives. Edge cases get custom handlers.

---

### Stage 5: Unit Abilities System

Unit abilities use the **same effect primitives** as stratagems but with different trigger conditions:

#### 5.1 Ability Types

**Core Abilities** (already partially implemented):
- Deep Strike, Infiltrators, Scouts -- deployment rules
- Lone Operative, Stealth -- defensive modifiers
- Feel No Pain, Deadly Demise -- damage interaction
- Fights First -- fight phase ordering

**Faction Abilities** (passive, always-on or phase-triggered):
- Oath of Moment (SM): re-roll hits vs selected target
- Waaagh! (Orks): +1 Strength, +1 Attack on charge turn
- Martial Ka'tah (Custodes): stance-based bonuses

**Datasheet Abilities** (unit-specific):
- "Might is Right": +1 to melee hit rolls while leading
- "Ramshackle": damage mitigation roll
- Leader abilities: bonuses to led unit

#### 5.2 Ability Resolution

Abilities would register their effects with the same trigger system as stratagems, but:
- They activate **automatically** (no player choice needed for most)
- They persist for their stated duration (often "while leading" or "always")
- Some require a one-time choice (e.g., Oath of Moment target selection)

#### 5.3 Ability Parser

For the initial implementation, create a **lookup table** mapping ability names to effect definitions:

```gdscript
const ABILITY_EFFECTS = {
    "Might is Right": {
        "trigger": "FIGHTER_SELECTED",
        "condition": "unit_is_led_by_this_model",
        "effects": [{"type": EffectType.PLUS_ONE_HIT, "scope": "unit", "attack_type": "melee"}],
        "duration": "while_leading"
    },
    "Da Biggest and da Best": {
        "trigger": "FIGHT_PHASE_START",
        "condition": "waaagh_active",
        "effects": [{"type": EffectType.ADD_ATTACKS, "value": 4, "scope": "model", "attack_type": "melee"}],
        "duration": "end_of_phase"
    }
}
```

This avoids the complexity of NLP-parsing ability descriptions and instead uses curated mappings. Over time, more abilities get mapped.

---

### Stage 6: Integration & Polish

- Multiplayer sync for stratagem usage (actions already flow through GameManager diffs)
- AI opponent stratagem usage (simple heuristics: use Command Re-roll on failed critical rolls)
- Save/load integration (stratagem usage history in game state)
- Test coverage for all implemented stratagems and abilities

---

## Estimated Scope

| Stage | What Ships | Files Modified/Created |
|-------|-----------|----------------------|
| 1 | Data pipeline, UI, triggers, CP tracking | ~5 new files, ~8 modified |
| 2 | 11 Core stratagems playable | ~6 modified (phases + RulesEngine) |
| 3 | Effect primitives library | ~2 new files, ~3 modified |
| 4 | Faction stratagems (SM, Orks, Custodes) | ~2 new data files, ~2 modified |
| 5 | Unit abilities system | ~3 new files, ~4 modified |
| 6 | Polish, multiplayer, AI, tests | ~5 modified, ~5 test files |

---

## Key Architectural Decisions

### 1. Trigger/Event System
The trigger system is the most critical design decision. Two options:

**Option A: Signal-based** -- Each phase emits Godot signals at trigger points. StratagemManager connects to these signals and checks for available stratagems.

**Option B: Poll-based** -- After each action, StratagemManager is queried: "are any stratagems available now?" The UI shows them if yes.

**Recommendation: Hybrid.** Use signals for reactive triggers (opponent's turn stratagems) and polling for active-turn stratagems (your turn, you choose when to use them). Active-turn stratagems appear in the UI panel; reactive stratagems prompt via popup.

### 2. Effect Application
Effects must integrate with the existing `RulesEngine` modifier system. The current `HitModifier` enum is too limited (only REROLL_ONES, PLUS_ONE, MINUS_ONE). It needs to be extended to support:
- Full re-rolls (not just 1s)
- Wound modifiers
- Save modifiers
- AP modification
- Damage modification

**Recommendation:** Extend the existing system rather than replacing it. Add `WoundModifier`, `SaveModifier` enums. The `assignment.modifiers` dictionary already flows through `RulesEngine._resolve_assignment_until_wounds()` -- just need more modifier types.

### 3. State Representation
Stratagem effects need to be tracked in game state for:
- Multiplayer sync (diffs system)
- Save/load
- Undo support
- Duration tracking (end of phase, end of turn, etc.)

**Recommendation:** Add to game state:
```
state.active_effects = [
    {
        "source": "stratagem:go_to_ground",
        "target_unit": "U_INTERCESSORS_A",
        "effects": [...],
        "expires": "end_of_phase",
        "phase": "shooting",
        "turn": 2
    }
]
state.players.X.stratagems_used_this_turn = [...]
state.players.X.stratagems_used_this_battle = [...]
```

### 4. Ability vs Stratagem Unification
Both abilities and stratagems produce the same kinds of effects (modifiers, keyword grants, etc.). The difference is:
- **Stratagems**: Player-activated, costs CP, specific timing window
- **Abilities**: Always active or auto-triggered, no CP cost, often conditional

**Recommendation:** Share the effect primitives library. The trigger/activation system differs but the downstream effects are identical.

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Trigger system complexity | High | Start with Core stratagems only; reactive stratagems are hardest |
| UI interruption flow | Medium | Clear UX for "opponent wants to use stratagem" pauses |
| Multiplayer sync | Medium | Stratagems are actions; use existing diff system |
| Edge case interactions | High | Comprehensive test suite; start with non-overlapping effects |
| Scope creep | High | Strict staged approach; ship Core stratagems before faction ones |
| Performance | Low | Effects are evaluated per-attack, not per-frame; 10-20 effects max |

---

## Recommended Starting Point

**Start with Stage 1.2 (StratagemManager) + Stage 2 Group E (INSANE BRAVERY)** as the absolute minimum viable slice. This proves:
1. Stratagem data can be loaded
2. CP can be spent
3. A trigger point works (before battle-shock test)
4. The effect resolves (auto-pass)
5. Usage tracking works (once per battle)

Then expand to GO TO GROUND + SMOKESCREEN (defensive modifiers during opponent's turn -- proves reactive stratagem flow), then GRENADE (proves mortal wound path), then COMMAND RE-ROLL (proves universal re-roll), then the reactive stratagems.

---

## Build Order

Recommended implementation sequence. Each step proves a new capability in the pipeline:

| # | Task | What It Proves | Status |
|---|------|---------------|--------|
| 1 | StratagemManager + Insane Bravery | Pipeline end-to-end (data, CP, usage tracking, phase integration, UI) | **COMPLETED** |
| 2 | Go to Ground + Smokescreen | Reactive/opponent-turn flow with defensive modifiers | **COMPLETED** |
| 3 | Grenade | Mortal wounds path (bypasses normal attack sequence) | **COMPLETED** |
| 4 | Epic Challenge | Weapon keyword granting (PRECISION) | **COMPLETED** |
| 5 | Command Re-roll | Universal re-roll (any dice, any phase) | **COMPLETED** |
| 6 | Counter-Offensive | Fight order manipulation | Pending |
| 7 | Fire Overwatch + Heroic Intervention | Cross-phase actions (shooting/charging during opponent's turn) | Pending |
| 8 | Extract effect primitives library | Refactor hardcoded patterns into reusable data-driven effects | Pending |
| 9 | Faction stratagems via data | Load and apply faction stratagems from CSV | Pending |
| 10 | Unit abilities | Reuse effect primitives for datasheet/faction abilities | Pending |

---

## Implementation Notes

### Task 2: Go to Ground + Smokescreen (COMPLETED)

**Implementation approach**: Hybrid of StratagemManager effect tracking + unit flags in game state.

**Files modified:**
- `40k/autoloads/StratagemManager.gd` -- Added `_apply_stratagem_effects()`, `_clear_stratagem_flags()`, `get_reactive_stratagems_for_shooting()` methods. Stratagems set flags directly on target units via state diffs, and track active effects for duration management.
- `40k/autoloads/RulesEngine.gd` -- Modified `_resolve_assignment_until_wounds()` (both copies) to check `target_unit.flags.stratagem_stealth` for -1 to hit. Modified `prepare_save_resolution()` and auto-resolve save path to check `flags.stratagem_invuln` and `flags.stratagem_cover` for invulnerable saves and cover.
- `40k/phases/ShootingPhase.gd` -- Added `reactive_stratagem_opportunity` signal, `awaiting_reactive_stratagem` state, `_check_reactive_stratagems()` method. After `CONFIRM_TARGETS`, checks if defending player has reactive stratagems available. Added `USE_REACTIVE_STRATAGEM` and `DECLINE_REACTIVE_STRATAGEM` action types. Clears stratagem flags on phase exit.
- `40k/scripts/ShootingController.gd` -- Connected `reactive_stratagem_opportunity` signal. Shows `StratagemDialog` to defending player, routes USE/DECLINE actions back through `shoot_action_requested`.
- `40k/scripts/Main.gd` -- Added disconnect for `reactive_stratagem_opportunity` signal in cleanup.

**Files created:**
- `40k/dialogs/StratagemDialog.gd` -- AcceptDialog-based UI for reactive stratagem selection. Shows available stratagems with CP cost, description, and per-eligible-unit "Use" buttons plus a "Decline All" button.
- `40k/tests/unit/test_go_to_ground_smokescreen.gd` -- Comprehensive test suite (30+ tests) covering stratagem definitions, validation, effect application, RulesEngine integration, reactive detection, effect expiry, and edge cases.

**Architecture decisions:**
- **Unit flags over central effect store**: Stratagem effects are stored as flags on target units (`unit.flags.stratagem_invuln`, `unit.flags.stratagem_cover`, `unit.flags.stratagem_stealth`) rather than only in StratagemManager. This allows static `RulesEngine` methods to read effects directly from the `board` dictionary without needing access to the StratagemManager autoload.
- **Reactive flow via signal**: ShootingPhase emits `reactive_stratagem_opportunity` signal after targets are confirmed. The ShootingController shows a dialog to the defender. The defender's choice (USE/DECLINE) routes back through the normal action pipeline for multiplayer compatibility.
- **Effect flags are cleared both ways**: On phase exit, `ShootingPhase._clear_stratagem_phase_flags()` clears unit flags from game state, and `StratagemManager.on_phase_end()` clears its internal active effects list (which also calls `_clear_stratagem_flags()` for each expired effect).

**What this proved:**
1. Reactive/opponent-turn stratagem flow works (pause after target selection, show dialog, resume resolution)
2. Defensive modifiers integrate cleanly with existing RulesEngine save calculations
3. Stealth (-1 to hit) integrates with existing HitModifier system
4. Unit flag approach works well for static RulesEngine methods and multiplayer state sync

### Task 3: Grenade (COMPLETED)

**Implementation approach**: Active-player stratagem during own Shooting phase. Two-step selection (grenade unit → enemy target), 6D6 roll with 4+ mortal wounds, instant damage application bypassing the normal attack sequence.

**Files modified:**
- `40k/autoloads/RulesEngine.gd` -- Added `apply_mortal_wounds()` static method for applying mortal wounds (bypasses saves, supports FNP). Added `get_grenade_eligible_targets()` to find enemy units within 8" range.
- `40k/autoloads/StratagemManager.gd` -- Added `get_grenade_eligible_units()` to find player's units with GRENADES keyword meeting all conditions (not advanced, not fell back, not shot, not in engagement, not battle-shocked). Added `execute_grenade()` method handling the full flow: CP deduction, usage tracking, 6D6 roll, mortal wound application, and marking unit as has_shot.
- `40k/phases/ShootingPhase.gd` -- Added `grenade_result` signal, `USE_GRENADE_STRATAGEM` action type with validation and processing methods. Processing delegates to `StratagemManager.execute_grenade()` and emits result signals.
- `40k/scripts/ShootingController.gd` -- Added "Use GRENADE" button to shooting panel. Button visibility updates based on eligible units and CP. Connected `grenade_result` signal for result display. Handles full dialog flow: GrenadeTargetDialog → action → GrenadeResultDialog.
- `40k/scripts/Main.gd` -- Added `grenade_result` signal disconnect in shooting controller cleanup.

**Files created:**
- `40k/dialogs/GrenadeTargetDialog.gd` -- Two-step AcceptDialog: Step 1 selects which GRENADES unit throws, Step 2 selects enemy target within 8". Queries `RulesEngine.get_grenade_eligible_targets()` for range checking.
- `40k/dialogs/GrenadeResultDialog.gd` -- AcceptDialog showing 6D6 roll results with color-coded dice (green for 4+ successes, red for misses), mortal wound count, and casualty count.
- `40k/tests/unit/test_grenade_stratagem.gd` -- Comprehensive test suite covering stratagem definition, validation, unit eligibility (GRENADES keyword, exclusion conditions), target eligibility (range, friendly/enemy, destroyed), execution (CP deduction, dice rolling, mortal wound counting, has_shot marking, once-per-phase), mortal wound application (single/multi-wound models, excess damage, destroyed units), and integration tests.

**Architecture decisions:**
- **Active stratagem pattern**: Unlike Go to Ground/Smokescreen (reactive, opponent's turn), GRENADE is an active-turn stratagem. Uses a dedicated button in the shooting panel rather than the reactive signal/dialog flow.
- **Instant effect (no persistent flags)**: GRENADE has no persistent effect on game state — mortal wounds are applied immediately. No unit flags needed (unlike Go to Ground's invuln/cover flags). Effect tracking is still recorded for usage restriction enforcement.
- **execute_grenade applies diffs internally**: Since `execute_grenade()` calls `PhaseManager.apply_state_changes()` for each set of diffs, `_process_use_grenade_stratagem` returns empty changes to avoid double-application by `BasePhase.execute_action()`.
- **Unit marked as has_shot**: Using GRENADE consumes the unit's shooting action for the phase, matching the 10e rules ("instead of selecting targets" wording).
- **Reusable mortal wound system**: `RulesEngine.apply_mortal_wounds()` is designed as a general-purpose method that can be reused by Tank Shock and any future mortal-wound-dealing effects. Supports Feel No Pain interaction.

**What this proved:**
1. Active-player stratagem flow works (button → dialog → action → result)
2. Mortal wounds can bypass the normal attack sequence (no hit/wound/save rolls)
3. `RulesEngine.apply_mortal_wounds()` provides a reusable mortal wound pipeline
4. Two-step dialog selection (source unit → target unit) works for active stratagems
5. Grenade range checking (8") works via model position distance calculation

### Task 4: Epic Challenge (COMPLETED)

**Implementation approach**: Active-player stratagem during own Fight phase. When a CHARACTER unit is selected to fight, player is offered Epic Challenge. The stratagem sets a flag on the unit that RulesEngine checks during melee resolution to activate the PRECISION ability (critical hits allocate wounds to CHARACTER models in the target).

**Files modified:**
- `40k/autoloads/StratagemManager.gd` -- Added `is_epic_challenge_available()` method for CHARACTER keyword validation. Added `"epic_challenge"` case in `_apply_stratagem_effects()` to set `stratagem_precision_melee` flag. Added `"epic_challenge"` case in `_clear_stratagem_flags()` for cleanup on phase end.
- `40k/autoloads/RulesEngine.gd` -- Added `has_precision()` static method to detect PRECISION from weapon special_rules. Added `has_stratagem_precision_melee()` to detect stratagem flag on attacker unit. Added `_find_character_model_indices()` to find CHARACTER models in target units. Added `_apply_damage_to_character_models()` for PRECISION-targeted damage allocation. Modified `_resolve_melee_assignment()` Phase 3 to detect PRECISION (from weapon or stratagem), and Phase 7 to split damage between precision-targeted (CHARACTER models) and regular allocation using proportional damage splitting.
- `40k/phases/FightPhase.gd` -- Added `epic_challenge_opportunity` signal. Modified `_process_select_fighter()` to check Epic Challenge availability before pile-in. Added `USE_EPIC_CHALLENGE` and `DECLINE_EPIC_CHALLENGE` action types with validation and processing. USE applies the stratagem flag to both GameState and the local game_state_snapshot, then proceeds to pile-in. DECLINE proceeds directly to pile-in.
- `40k/scripts/FightController.gd` -- Connected `epic_challenge_opportunity` signal. Added `_on_epic_challenge_opportunity()`, `_on_epic_challenge_used()`, `_on_epic_challenge_declined()` handlers. Shows EpicChallengeDialog to the player, routes USE/DECLINE actions back through `fight_action_requested`.

**Files created:**
- `40k/dialogs/EpicChallengeDialog.gd` -- AcceptDialog-based UI showing Epic Challenge details (cost, target, effect description, PRECISION explanation) with Use and Decline buttons.
- `40k/tests/unit/test_epic_challenge.gd` -- Comprehensive test suite covering: stratagem definition, validation (CHARACTER required, CP, once-per-phase, battle-shocked), effect application (flag set, CP deduction, active effect tracking), effect expiry (flag cleared on phase end), RulesEngine PRECISION detection (weapon special_rules, stratagem flag), CHARACTER model detection (unit-level, model-level keywords), PRECISION damage allocation (_apply_damage_to_character_models), full integration flow, and edge cases.

**Architecture decisions:**
- **Proactive stratagem in fight phase**: Unlike Go to Ground (reactive, opponent's turn), Epic Challenge triggers during the player's own fighter selection. Uses a dialog between SELECT_FIGHTER and PILE_IN steps.
- **Dual PRECISION source**: RulesEngine checks both weapon-inherent PRECISION (`has_precision()`) and stratagem-granted PRECISION (`has_stratagem_precision_melee()`). This supports both Epic Challenge and future weapons with built-in PRECISION.
- **Proportional damage splitting**: Rather than tracking individual attacks through the wound pipeline, PRECISION damage is calculated proportionally: `precision_share = (critical_hits / total_unsaved) * actual_damage`. This avoids modifying the core wound/save pipeline while correctly approximating PRECISION behavior.
- **Flag on attacker unit**: The `stratagem_precision_melee` flag is set on the ATTACKING unit (not the target), and RulesEngine reads it during resolution. This matches the rules: "attacks made by that model have [PRECISION]".

**What this proved:**
1. Fight phase stratagem flow works (dialog inserted between fighter selection and pile-in)
2. Weapon keyword granting via stratagem flags integrates with RulesEngine melee resolution
3. PRECISION damage allocation to CHARACTER models works via separate allocation function
4. Pattern generalizes to other keyword-granting stratagems (e.g., LANCE, SUSTAINED HITS)

---

### Step 5: Command Re-roll — Implementation Notes

**What was implemented:**
- COMMAND RE-ROLL (Core – Battle Tactic Stratagem, 1 CP): Re-roll any single dice roll, usable in any phase on either turn, once per phase.

**Roll types currently supported:**
1. **Charge rolls (2D6)** — ChargePhase pauses after rolling, shows dialog, re-rolls both dice if accepted
2. **Battle-shock tests (2D6)** — CommandPhase pauses after a failed test, shows dialog, re-rolls if accepted
3. **Advance rolls (D6)** — MovementPhase pauses after rolling, shows dialog, re-rolls if accepted

**Roll types with infrastructure (future expansion):**
4. **Saving throws** — ShootingPhase and FightPhase have `command_reroll_opportunity` signal declared but not yet wired. Requires refactoring the bulk save-roll loop to intercept individual failed saves.
5. **Hit/wound rolls** — Dice are rolled in batch inside RulesEngine's `resolve_shooting_action_v2()` and `_resolve_melee_assignment()`. Individual die interception would require a yield/coroutine refactor of the resolution pipeline.

**Files modified:**
- `40k/autoloads/StratagemManager.gd` — Added `is_command_reroll_available(player)` for quick availability checks and `execute_command_reroll(player, unit_id, roll_context)` for CP deduction + usage tracking + phase logging.
- `40k/phases/ChargePhase.gd` — Added `command_reroll_opportunity` signal, `awaiting_reroll_decision`/`reroll_pending_unit_id` state tracking. Refactored `_process_charge_roll()` to check reroll availability before resolving. Extracted `_resolve_charge_roll()` to handle post-decision resolution. Added `_validate_command_reroll()`, `_process_use_command_reroll()`, `_process_decline_command_reroll()` action handlers.
- `40k/phases/CommandPhase.gd` — Added `command_reroll_opportunity` signal, `_awaiting_reroll_decision`/`_reroll_pending_unit_id`/`_reroll_pending_roll` state. Refactored `_handle_battle_shock_test()` to check reroll availability after a failed roll (skipped when `dice_roll` parameter is provided for test determinism). Extracted `_resolve_battle_shock_test()`. Added `_handle_use_command_reroll()`, `_handle_decline_command_reroll()`.
- `40k/phases/MovementPhase.gd` — Added `command_reroll_opportunity` signal, reroll state tracking. Refactored `_process_begin_advance()` to check reroll availability. Extracted `_resolve_advance_roll()`. Added `_process_use_command_reroll()`, `_process_decline_command_reroll()`.
- `40k/phases/ShootingPhase.gd` — Added `command_reroll_opportunity` signal declaration (infrastructure for future save re-rolls).
- `40k/phases/FightPhase.gd` — Added `command_reroll_opportunity` signal declaration (infrastructure for future save re-rolls).
- `40k/scripts/ChargeController.gd` — Connected `command_reroll_opportunity` signal. Added `_on_command_reroll_opportunity()` to show dialog, `_on_command_reroll_used()`/`_on_command_reroll_declined()` to route actions.
- `40k/scripts/CommandController.gd` — Connected `command_reroll_opportunity` signal. Added dialog show/response handlers.
- `40k/scripts/MovementController.gd` — Connected `command_reroll_opportunity` signal. Added dialog show/response handlers.

**Files created:**
- `40k/dialogs/CommandRerollDialog.gd` — AcceptDialog-based UI showing the roll type, original dice values, context info (e.g., "Need 7+ to pass"), CP cost, and Use/Decline buttons.
- `40k/tests/unit/test_command_reroll_stratagem.gd` — Test suite covering: stratagem definition/timing/restriction, validation (CP checks, availability checks), CP deduction via both `use_stratagem` and `execute_command_reroll`, once-per-phase enforcement, ChargePhase/CommandPhase/MovementPhase reroll state management, and edge cases.

**Architecture decisions:**
- **Phase-pause pattern**: Each phase checks `is_command_reroll_available()` after rolling dice but before resolving the result. If available, the phase emits `command_reroll_opportunity`, stores the pending roll state, and returns a result with `awaiting_reroll: true`. The controller shows a dialog, and the player's decision comes back as a `USE_COMMAND_REROLL` or `DECLINE_COMMAND_REROLL` action. This reuses the same action-validation-processing pipeline as all other game actions.
- **Extracted resolution methods**: Each phase has a `_resolve_*` method (e.g., `_resolve_charge_roll`) that runs after the reroll decision. This keeps the resolution logic DRY — the same code runs whether or not a reroll happened.
- **Deterministic test override**: CommandPhase's `dice_roll` parameter (used in tests) bypasses the reroll offer, ensuring test determinism.
- **Shooting/Fight deferred**: Batch dice rolling in RulesEngine makes per-die interception architecturally expensive. The signal infrastructure is in place for future expansion when the resolution pipeline supports yield/coroutine patterns.

**What this proved:**
1. The phase-pause-resume pattern generalizes across all phases (Charge, Command, Movement)
2. The Controller→Dialog→Action pipeline reuses the same patterns as reactive stratagems
3. StratagemManager's `can_use_stratagem` / `use_stratagem` correctly enforce once-per-phase for Command Re-roll
4. The architecture cleanly separates the reroll decision (UI) from the reroll execution (phase logic)

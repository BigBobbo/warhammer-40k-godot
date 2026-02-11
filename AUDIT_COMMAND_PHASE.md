# Command Phase Audit

**Reference:** [Warhammer 40K 10th Edition Core Rules - Command Phase](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Command-Phase)

**Last Updated:** 2026-02-11

## Overview

The Command Phase is the first phase of each player's turn (after Deployment in round 1). Per the 10th edition core rules, the following should occur:

1. **Command Point Generation** - The active player gains 1 CP
2. **Use Stratagems** - Players may use Command Phase stratagems
3. **Resolve Abilities** - Resolve any abilities that trigger in the Command Phase

## Audit Items

### P1: Command Point Generation [COMPLETE]

**Status:** Done
**Rules Reference:** "At the start of each player's Command phase, that player gains 1CP."
**Implementation:**
- `CommandPhase._on_phase_enter()` calls `_generate_command_points()` which increments the active player's CP by 1 via `PhaseManager.apply_state_changes()`
- State path: `players.<player_key>.cp`
- `CommandController` right panel now displays both players' CP values (was previously "Not Implemented")
- CP generation is logged: `CommandPhase: Generating 1 CP for player X (N -> N+1)`

**Files Changed:**
- `40k/phases/CommandPhase.gd` - Added `_generate_command_points()` method, called from `_on_phase_enter()`
- `40k/scripts/CommandController.gd` - Replaced placeholder CP label with live CP display for both players

---

### P2: Stratagem Framework (Command Phase Stratagems)

**Status:** Not Started
**Priority:** Medium
**Rules Reference:** Players may use stratagems during the Command Phase. Some stratagems are specifically labelled "Command Phase" and can only be used during this phase.
**Notes:**
- Currently no stratagem system exists in the codebase
- MoralePhase has a basic CP-spending pattern (Insane Bravery stratagem) that could serve as a reference
- Would need: stratagem data definitions, eligibility checking, CP cost validation, and UI for stratagem selection
- This is a large feature that spans all phases, not just Command

---

### P3: Command Phase Abilities

**Status:** Not Started
**Priority:** Medium
**Rules Reference:** Some unit abilities trigger "at the start of the Command Phase" or "during the Command Phase." These need to be resolved during this phase.
**Notes:**
- Would require an ability system that can query units for Command Phase triggers
- No ability trigger framework currently exists
- Army data files would need ability definitions with phase triggers

---

### P4: Battle-shock Tests

**Status:** Not Started
**Priority:** High
**Rules Reference:** In 10th edition, Battle-shock tests happen during the Command Phase. Each unit below half-strength must take a Battle-shock test (2D6 vs Leadership). Failed units are Battle-shocked and cannot hold objectives or use stratagems.
**Notes:**
- This is a significant rules mechanic that affects objective control and stratagem usage
- Requires: half-strength detection, Leadership stat on units, 2D6 roll, Battle-shocked status effect
- The existing `status_effects` array on models could be leveraged for tracking Battle-shocked status
- Would interact with objective scoring (Battle-shocked units cannot control objectives)

---

### P5: CP Display in Other Phases

**Status:** Not Started
**Priority:** Low
**Notes:**
- CP is currently only displayed during the Command Phase right panel
- Ideally CP should be visible in the top bar or persistent HUD element across all phases
- Would allow players to track CP available for stratagems in other phases (e.g., Shooting, Fight)

---

## Suggested Next Task

**P4: Battle-shock Tests** is the recommended next task. It is the highest-impact rules mechanic still missing from the Command Phase and directly affects gameplay (objective control, stratagem eligibility). It builds on existing infrastructure:
- Unit `status_effects` arrays already exist on models
- The dice rolling system from other phases can be reused
- Leadership stats would need to be added to army data files
- Half-strength detection is a straightforward count of alive models vs total

Alternatively, **P5: CP Display in Other Phases** is a quick UI improvement that would complement the CP generation work just completed.

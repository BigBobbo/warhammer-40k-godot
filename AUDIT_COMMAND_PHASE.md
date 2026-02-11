# Command Phase Implementation Audit

**Status:** In Progress
**Last Updated:** 2026-02-11

## Overview

This document tracks the implementation of Command Phase mechanics per Warhammer 40K 10th Edition rules. The Command Phase occurs at the start of each player's turn (after Deployment), handling battle-shock tests, command point generation, and objective scoring.

**Reference:** [Wahapedia - Core Rules](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/)

---

## Implementation Items

### P0 - Battle-shock (Critical Path)

| # | Item | Status | Files | Notes |
|---|------|--------|-------|-------|
| 1 | **`is_below_half_strength(unit)` utility** | DONE | `GameState.gd:338-363` | Multi-model: alive*2 < total. Single-model: current_wounds*2 < max_wounds. Handles edge cases (no models, all dead). |
| 2 | **2D6 vs Leadership battle-shock test** | DONE | `CommandPhase.gd:193-266` | Roll 2D6: roll >= Ld = pass, roll < Ld = fail. Supports deterministic `dice_roll` override for testing. Results logged to phase log. |
| 3 | **Apply/clear `battle_shocked` flag** | DONE | `CommandPhase.gd:49-67, 220-225` | Flags cleared at Command Phase start for active player only. Applied immediately on failed test. Writes to `unit.flags.battle_shocked` (same path MissionManager reads). |

### P1 - Command Points

| # | Item | Status | Files | Notes |
|---|------|--------|-------|-------|
| 4 | **Generate 1 CP at start of Command Phase** | TODO | — | Per 10e rules, each player gains 1 CP at the start of their Command Phase. Currently `players.{id}.cp` exists in GameState but is not auto-incremented. |
| 5 | **CP cap enforcement** | TODO | — | Players cannot exceed a CP cap (typically no cap in matched play, but Leviathan had a 4 CP cap). |

### P2 - Strategic Ploys / Stratagems

| # | Item | Status | Files | Notes |
|---|------|--------|-------|-------|
| 6 | **Command Phase stratagem window** | TODO | — | Some stratagems can only be used during the Command Phase. Needs stratagem system first. |

### P3 - Additional Rules

| # | Item | Status | Files | Notes |
|---|------|--------|-------|-------|
| 7 | **Battle-shock effects on abilities** | TODO | — | Battle-shocked units cannot use Stratagems and their OC becomes 0. OC=0 is already enforced in MissionManager.gd:122-125. Stratagem restriction needs stratagem system. |
| 8 | **Insane Bravery stratagem** | TODO | — | 2 CP stratagem to auto-pass one battle-shock test. Needs stratagem system. |

---

## Architecture Notes

### Battle-shock Flow
```
Command Phase Entry
  ├── 1. Clear battle_shocked flags (active player only)
  ├── 2. Identify Below Half-strength units
  ├── 3. Present BATTLE_SHOCK_TEST actions to player
  │     └── For each: Roll 2D6, compare to Leadership
  │           ├── Roll >= Ld → Pass (no flag)
  │           └── Roll < Ld  → Fail (set battle_shocked = true)
  ├── 4. Check objectives (MissionManager)
  ├── 5. Score primary objectives
  └── 6. END_COMMAND → advance to Movement Phase
```

### Key Integration Points
- **MissionManager.gd:122-125** — Reads `unit.flags.battle_shocked` to skip battle-shocked units from objective control calculations
- **MovementPhase.gd:569** — Reads battle-shocked status for Desperate Escape tests (currently reads from `status_effects` path — should be updated to read from `flags` for consistency)
- **GameState.gd:338-363** — `is_below_half_strength()` utility used by CommandPhase to identify eligible units

### Test Coverage
- **File:** `tests/unit/test_battle_shock.gd`
- **Tests:** 25 test cases covering:
  - `is_below_half_strength()` for multi-model units (10 tests)
  - `is_below_half_strength()` for single-model units (6 tests)
  - Edge cases (empty models, missing keys) (2 tests)
  - Battle-shocked flag clearing on phase enter (2 tests)
  - Unit identification for tests (2 tests)
  - 2D6 vs Leadership test pass/fail (5 tests)
  - Validation (3 tests)
  - Auto-resolve on END_COMMAND (1 test)
  - Result detail verification (1 test)
  - Integration with objective control (1 test)

---

## Suggested Next Task

**P1 Item #4: Command Point Generation** — Add automatic 1 CP generation at the start of each Command Phase. This is a simple addition to `_on_phase_enter()` that increments `GameState.state.players[player_key].cp`. Low complexity, high rules-compliance value.

Alternatively, if continuing with game-impacting mechanics:

**P3 Item #7: Battle-shock movement restrictions** — Fix the `MovementPhase.gd:569` inconsistency where it reads `status_effects.battle_shocked` instead of `flags.battle_shocked`. Ensure battle-shocked units properly trigger Desperate Escape tests.

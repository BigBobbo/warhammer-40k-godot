# Command Phase Audit — Warhammer 40k 10th Edition

**Date:** 2026-02-11
**Scope:** Online multiplayer (Web Relay) implementation
**Reference:** [Warhammer 40k 10th Edition Core Rules](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/)

---

## Executive Summary

The Command Phase is currently a **minimal placeholder** (84 lines in `CommandPhase.gd`, 190 lines in `CommandController.gd`). It checks objective control, displays VP totals, and provides an "End Command Phase" button. Nearly all core Command Phase mechanics from the 10th edition rules are missing, including CP generation, Battle-shock tests, stratagems, and faction abilities.

---

## 1. Current Implementation

### What exists today

| Component | File | Lines | What it does |
|-----------|------|-------|--------------|
| Phase logic | `phases/CommandPhase.gd` | 84 | Checks objectives on entry, scores primaries on exit, provides `END_COMMAND` action |
| UI controller | `scripts/CommandController.gd` | 190 | Displays battle round, active player, objective control status, VP summary |
| Game state | `autoloads/GameState.gd:46` | — | `"1": {"cp": 3, "vp": 0}` — CP tracked per player but never modified |
| Objective scoring | `autoloads/MissionManager.gd` | 284 | Checks objective control, scores "Take and Hold" primary from round 2+ |
| Battle-shock flag | `autoloads/MissionManager.gd:123` | — | Units with `battle_shocked` flag have OC 0 (skipped for objective control) |

### Phase flow

```
SCORING → (player switch) → COMMAND → MOVEMENT
```

On entering Command Phase:
1. `MissionManager.check_all_objectives()` — recalculates objective control
2. UI panel shows round, player, objectives, VP
3. Player clicks "End Command Phase"
4. `MissionManager.score_primary_objectives()` — awards VP for controlled objectives (round 2+)
5. Phase transitions to MOVEMENT

---

## 2. Rules Comparison — Missing Mechanics

### 2.1 Command Points Generation ~~(CRITICAL)~~ DONE

**Rule:** At the start of each Command Phase, the active player gains 1 CP. The opponent also gains 1 CP. A player can gain a maximum of 1 additional CP per battle round from other sources (abilities, Warlord traits, etc.).

**Implemented (2026-02-11):**
- `CommandPhase._generate_command_points()` awards +1 CP to both the active player and opponent via `PhaseManager.apply_state_changes()`
- CP changes propagate over the network (both host and client independently compute from synchronized state)
- `CommandController` right panel displays actual CP totals for both players, color-coded by team
- Snapshot is refreshed after CP changes so subsequent phase logic reads correct values

**Still needed (deferred to Stratagems milestone):**
- Cap additional CP gains at 1 per battle round per player (from non-phase sources)
- Track CP spending and validate sufficient CP before stratagem use

### 2.2 Battle-shock Tests (CRITICAL)

**Rule:** After gaining CP and resolving abilities, the active player must take Battle-shock tests for each of their units that is Below Half-strength:
- **Multi-model units:** Below half-strength if they have fewer than half their starting models alive
- **Single-model units:** Below half-strength if they have fewer than half their starting wounds remaining
- **Test:** Roll 2D6. If the result is **below** the unit's Leadership (Ld) characteristic, the unit is **Battle-shocked** until the start of its controlling player's next Command Phase
- **Effects of Battle-shocked:**
  - OC becomes 0 (partially implemented in `MissionManager.gd:123`)
  - Cannot be targeted by friendly Stratagems
  - If the unit Falls Back, each model must take a Desperate Escape test (roll D6; destroyed on 1-2)

**Current state:**
- The `battle_shocked` flag exists in the unit flags system and MissionManager respects it for objective control
- **No code** to determine "below half-strength" for any unit
- **No code** to roll 2D6 against Leadership for the test
- **No code** to apply or clear the `battle_shocked` flag during the Command Phase
- **No code** for the Desperate Escape test when battle-shocked units Fall Back
- The `MoralePhase.gd` implements a **9th-edition style** morale test (D6 + casualties vs Ld) which is incorrect for 10th edition. This phase is registered but never reached in the normal phase flow.

**What's needed:**
- `is_below_half_strength(unit: Dictionary) -> bool` utility function
- Battle-shock test step in Command Phase: iterate eligible units, roll 2D6 vs Ld
- Apply `battle_shocked` flag as a state change
- Clear `battle_shocked` flags at the start of each player's Command Phase (before new tests)
- Enforce stratagem restriction on battle-shocked units
- Implement Desperate Escape test in Movement Phase for battle-shocked Fall Back
- UI to show which units need tests, the roll result, and the outcome
- All rolls and results must be synchronized over the network (host rolls, broadcasts to guest)

### 2.3 Stratagems System (CRITICAL)

**Rule:** 12 core stratagems are available to every army. Two are directly relevant to the Command Phase:

| Stratagem | CP | When | Effect |
|-----------|----|------|--------|
| **Insane Bravery** | 1 | After failing a Battle-shock test in your Command Phase | Unit is treated as having passed the test instead |
| **New Orders** | 1 | End of your Command Phase, once per battle | Discard one active Secondary Mission and draw a new one |

The remaining 10 core stratagems are used in other phases but require the CP economy to function:

| Stratagem | CP | Phase |
|-----------|----|-------|
| Command Re-roll | 1 | Any phase |
| Counter-Offensive | 2 | Fight phase |
| Epic Challenge | 1 | Fight phase |
| Grenade | 1 | Shooting phase |
| Tank Shock | 1 | Charge phase |
| Rapid Ingress | 1 | Opponent's Movement phase |
| Fire Overwatch | 1 | Opponent's Movement/Charge phase |
| Heroic Intervention | 2 | Opponent's Charge phase |
| Smokescreen | 1 | Opponent's Shooting phase |
| Go to Ground | 1 | Opponent's Shooting phase |

**Current state:**
- `GameManager.gd:521` has a `process_use_stratagem()` stub that returns empty success
- `MoralePhase.gd` has skeleton validation for `USE_STRATAGEM` with TODO comments
- No stratagem definitions, no CP cost validation, no effects, no UI

**What's needed:**
- Stratagem definition data (name, CP cost, phase, timing, targets, effects)
- Stratagem manager autoload to track availability, usage restrictions, and cooldowns
- Per-phase stratagem integration (which stratagems can be played at which moments)
- "Once per phase" restriction enforcement (each stratagem can only be used once per phase)
- "Once per battle" restriction for certain stratagems (e.g., New Orders)
- Opponent stratagem interrupts (e.g., Fire Overwatch during opponent's charge)
- UI: stratagem selection panel, CP cost display, eligibility indicators
- Network: stratagem actions must route through host for validation

### 2.4 Faction Abilities in Command Phase (HIGH)

**Rule:** Many factions have abilities that trigger during the Command Phase. The army JSON files already reference these:

| Faction | Ability | Trigger |
|---------|---------|---------|
| Space Marines | **Oath of Moment** | "At the start of your Command phase, select one enemy unit. Re-roll hit rolls and wound rolls of 1 for attacks against that unit." |
| Orks (Lootaz) | **Get Da Good Bitz** | "At the end of your Command phase, if this unit is within range of an objective marker you control, that objective marker remains under your control..." |

**Current state:** Abilities are stored as text descriptions in army JSON files (e.g., `space_marines.json:66-68`, `orks.json:533-535`). **None are implemented as game mechanics.**

**What's needed:**
- Ability trigger system that fires at specific Command Phase timing points (start, end)
- Oath of Moment: target selection UI, re-roll modifier applied to shooting/fight phases
- Get Da Good Bitz: sticky objective control logic in MissionManager
- Framework for parsing/registering faction abilities from army JSON
- Network sync for ability targets/choices

### 2.5 Command Phase Sub-step Ordering (HIGH)

**Rule:** The Command Phase has a defined sequence:
1. **Gain CP** (both players gain 1 CP)
2. **Resolve Abilities** (active player resolves Command Phase abilities)
3. **Battle-shock Step** (test all Below Half-strength units)

**Current state:** There is no sub-step structure. The phase is a single "click to end" action.

**What's needed:**
- Command Phase should progress through sub-steps, blocking advancement until each is resolved
- Sub-step indicators in the UI so both players know where in the phase they are
- Network: sub-step transitions must be synchronized

### 2.6 CP Spending Validation (HIGH)

**Rule:**
- Each stratagem can only be used once per phase (even across both players)
- A maximum of 1 stratagem can be used per step/timing window by each player
- CP must be sufficient to pay the cost
- Battle-shocked units cannot be targeted by friendly stratagems

**Current state:** No validation exists.

### 2.7 Secondary Missions (MEDIUM)

**Rule:** Players have secondary mission cards. The "New Orders" stratagem (1 CP, once per battle) lets a player swap a secondary mission at the end of their Command Phase.

**Current state:** No secondary mission system exists.

### 2.8 Clearing Battle-shock (MEDIUM)

**Rule:** Battle-shock lasts "until the start of your next Command Phase." This means at the start of the active player's Command Phase, all their previously Battle-shocked units have that status cleared before new tests are taken.

**Current state:** `ScoringPhase.gd:93-98` resets per-turn action flags (`moved`, `advanced`, etc.) but `battle_shocked` is explicitly **not** in the reset list (it's in the "persistent status effects" category per `UNIT_FLAG_RESET_TEST_PLAN.md`). This is correct — it should be cleared in the Command Phase, not in Scoring.

---

## 3. Quality of Life / Visual Improvements

### 3.1 Remove Placeholder Text ~~(EASY)~~ DONE

~~`CommandController.gd:92` displays placeholder text about future features.~~
Replaced with actual battle round, active player, and faction name display (2026-02-11).

### 3.2 CP Display ~~(EASY)~~ DONE

~~`CommandController.gd:99-101` shows "Command Points: Not Implemented" in gray text.~~
Now displays actual CP totals for both players with faction names and team colors. `_refresh_ui()` dynamically updates CP labels (2026-02-11).

### 3.3 Battle-shock Visual Indicators (MEDIUM)

Units that are battle-shocked should have a visual indicator on their board tokens — a red border, pulsing effect, or icon overlay. The shader system (`shaders/` directory) could be leveraged for this.

### 3.4 Phase Progress Indicator (MEDIUM)

The Command Phase should show a step indicator (e.g., "Step 1/3: Gain CP" → "Step 2/3: Resolve Abilities" → "Step 3/3: Battle-shock Tests") so both players understand the flow, especially in multiplayer.

### 3.5 Turn Summary on Entry (LOW)

When entering the Command Phase, show a brief summary of the previous turn's key events (casualties inflicted, objectives changed hands, VP scored). This provides context for strategic decisions.

### 3.6 Objective Control Animation (LOW)

When objectives change control during the Command Phase check, animate the color transition on the board. Currently the control status is only shown in the right panel text.

### 3.7 CP Change Notifications (LOW)

When CP is gained or spent, show a floating notification ("+1 CP" or "-1 CP") near the player's CP display, similar to damage numbers in other games.

### 3.8 Multiplayer Opponent View (MEDIUM)

During the opponent's Command Phase, the non-active player currently has no visibility into what's happening. Show:
- Which units are being tested for Battle-shock
- The roll results
- Which abilities/stratagems are being used
- A "waiting for opponent" indicator

### 3.9 Right Panel Scrollability (EASY)

The right panel (`CommandController.gd:69-73`) has a `ScrollContainer` with a fixed minimum size of 250x400. On smaller screens or with many objectives, this may clip. The panel should adapt to available viewport height.

---

## 4. Multiplayer-Specific Concerns

### 4.1 Roll Authority

All dice rolls (Battle-shock 2D6, stratagem decisions) must originate from the **host** to prevent cheating. The current `NetworkManager.gd` has infrastructure for this via "deterministic" vs "non-deterministic" action routing, but the Command Phase doesn't use it at all.

### 4.2 CP Synchronization

CP changes must be applied as state changes (`PhaseManager.apply_state_changes()`) and broadcast to both clients. The current state change system supports this via the `"op": "set", "path": "players.1.cp"` pattern.

### 4.3 Stratagem Interrupts

Several stratagems allow the **non-active player** to react (e.g., "Insane Bravery" is used by the active player, but reactive stratagems like Fire Overwatch happen on the opponent's turn). The multiplayer system needs a "response window" where the non-active player can choose to use a reactive stratagem before the game proceeds.

### 4.4 Battle-shock Results Broadcast

When the host resolves Battle-shock tests, the results (which units tested, the 2D6 roll, pass/fail) must be sent to the guest so their UI updates correctly.

### 4.5 Phase Timeout

In multiplayer, if a player is AFK during the Command Phase, the non-active player is stuck waiting. Consider adding a configurable turn timer with auto-end behavior.

---

## 5. Priority Ranking

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| ~~P0~~ | ~~CP Generation (1 CP per command phase)~~ | ~~Low~~ | ~~DONE (2026-02-11)~~ |
| ~~P0~~ | ~~CP Display in UI~~ | ~~Low~~ | ~~DONE (2026-02-11)~~ |
| **P0** | **Battle-shock: Below-half-strength check** | **Medium** | **Core game mechanic — NEXT** |
| P0 | Battle-shock: 2D6 vs Leadership test | Medium | Core game mechanic |
| P0 | Battle-shock: Apply/clear flag | Low | Connects to existing OC=0 logic |
| ~~P1~~ | ~~Remove placeholder text~~ | ~~Low~~ | ~~DONE (2026-02-11)~~ |
| P1 | Command Phase sub-step ordering | Medium | Rules accuracy |
| P1 | Insane Bravery stratagem | Medium | Core stratagem for Command Phase |
| P1 | Battle-shock visual indicators | Medium | Player clarity |
| P1 | Multiplayer: Battle-shock roll broadcast | Medium | Multiplayer correctness |
| P2 | Full core stratagems system | High | Gameplay depth |
| P2 | Faction abilities (Oath of Moment, etc.) | High | Faction identity |
| P2 | CP spending validation | Medium | Rules enforcement |
| P2 | Phase progress indicator | Low | UX improvement |
| P2 | Opponent view during Command Phase | Medium | Multiplayer UX |
| P3 | Secondary missions + New Orders | High | Advanced gameplay |
| P3 | Turn summary on phase entry | Low | Nice-to-have |
| P3 | Objective control animations | Low | Visual polish |
| P3 | CP change notifications | Low | Visual polish |
| P3 | Phase timeout for AFK players | Medium | Multiplayer resilience |

---

## 6. Existing Code That Can Be Leveraged

1. **Flag system** — `battle_shocked` flag already respected by `MissionManager.gd:123`
2. **State changes** — `PhaseManager.apply_state_changes()` can set CP values and unit flags
3. **Dice rolling** — `RulesEngine.gd` has roll infrastructure for hit/wound/save
4. **Network routing** — `NetworkIntegration.route_action()` handles host validation + broadcast
5. **Unit model tracking** — `model.alive` and `model.current_wounds` fields exist for half-strength checks
6. **Leadership stat** — `unit.meta.stats.leadership` is defined in army JSON files
7. **MoralePhase.gd** — Contains skeleton code for stratagem usage and morale tests that could be adapted (though the 9th-edition morale mechanics should not be reused directly)

---

## 7. Suggested Implementation Order

1. ~~**CP Generation + Display**~~ — DONE (2026-02-11). `CommandPhase._generate_command_points()` awards +1 CP to both players. `CommandController` shows live CP totals.
2. **Below-half-strength utility** ← **UP NEXT** — Add `is_below_half_strength()` to `BasePhase` or a utility class.
3. **Battle-shock tests** — Add a `BATTLE_SHOCK_TEST` action type. On phase enter, identify eligible units and present them to the player. Host rolls 2D6, applies result.
4. **Battle-shock clear** — At the start of Command Phase, clear all `battle_shocked` flags for the active player's units.
5. **Insane Bravery** — After a failed test, offer the player the option to spend 1 CP to pass instead.
6. **Sub-step UI** — Refactor the Command Phase into distinct steps with a progress indicator.
7. **Remaining stratagems** — Build the full stratagem system, integrating into other phases.
8. **Faction abilities** — Parse ability triggers from army JSON and execute them at the correct timing.

# AI Dossier: Command Phase & CP Economy

All file references are relative to the repo root `/home/user/warhammer-40k-godot/`.
Verified against the code on 2026-08-27. The override file `40k/data/ai_config.json` sets only
`PLANS_ENABLED: 1` (`40k/data/ai_config.json:16-18`), so **every weight and threshold below is
the built-in code default and is also the effective value** — nothing command-phase-related is
overridden.

---

## Overview

The Command phase is where the game hands out Command Points (CP) and forces shaky units to test
their nerve. The CP gain itself is not an AI decision at all — the engine automatically gives
**both** players +1 CP at the start of every Command phase (`40k/phases/CommandPhase.gd:96-100,
166-185`), and both players start the game at 0 CP (`40k/autoloads/GameState.gd:64-65`). What the
AI actually decides here is: whether to spend 1 CP on INSANE BRAVERY to auto-pass a critical
battle-shock test, then it takes every required battle-shock test, and if a test fails it decides
whether to spend 1 CP on a COMMAND RE-ROLL. After the dice, it works through faction abilities
with a command-phase window (calling the Ork WAAAGH!, picking an Oath of Moment target, choosing
a Combat Doctrine, and several others), evaluates whether its secondary mission cards are worth
keeping (spending 1 CP on NEW ORDERS or a replace to swap a bad card), and finally ends the
phase. The Command Re-roll policy is a small set of hard-coded probability thresholds — for
example, a failed battle-shock is re-rolled only when the re-roll has at least a 40% chance to
pass, and a failed charge is re-rolled only when the target distance is 10" or less. Every one of
these decisions writes a plain-English "thinking" line that the player sees as a collapsible
block in the game log and as a streaming overlay. The AI also quietly builds its
"mission awareness" during this phase — a cache of which board zones its secondary and primary
mission cards care about — which steers its movement later in the turn. On Easy difficulty the AI
still takes its battle-shock tests and uses free faction abilities, but it never spends CP: it
declines all re-rolls and skips every stratagem.

---

## Decision flow

The engine runs the phase set-up automatically, then repeatedly asks the AI for one action at a
time until the AI answers `END_COMMAND`. The AI's chooser for this phase is
`_decide_command()` (`40k/scripts/AIDecisionMaker.gd:5908-6301`), reached from the master
dispatcher at `40k/scripts/AIDecisionMaker.gd:3128-3129`. Each numbered step below is checked in
order on every ask; the **first step that produces an action wins**, and the loop starts over on
the next ask.

**Engine set-up (automatic, before the AI is asked anything)** — `40k/phases/CommandPhase.gd:63-165`:

1. On the first turn of each battle round: reset round-kill tracking, reset the 1-bonus-CP-per-round
   cap, expire round-scoped stratagem effects (`40k/phases/CommandPhase.gd:63-76`).
2. **Both players gain +1 CP** (`40k/phases/CommandPhase.gd:91-100`, `_generate_command_points`
   at `166-185`).
3. Identify units that must take a battle-shock test: any unit **below half-strength, at exactly
   half-strength (11th edition), or already battle-shocked** — in 11e a shocked unit stays shocked
   until it passes a test (`40k/phases/CommandPhase.gd:288-301`, persistence rule at `223-246`).
   Units with FEARLESS / And They Shall Know No Fear are skipped (`40k/phases/CommandPhase.gd:280-285`).
4. Check objectives and open the primary-VP scoring window (engine-side, no AI choice)
   (`40k/phases/CommandPhase.gd:108-121`).
5. Draw secondary mission cards up to a hand of 2 (tactical mode)
   (`40k/phases/CommandPhase.gd:123-134`, `40k/autoloads/SecondaryMissionManager.gd:26,210-235`).

**AI decision order inside `_decide_command`** (`40k/scripts/AIDecisionMaker.gd:5908-6301`):

1. **Pending re-roll fallback** — if a re-roll window is somehow still open, decline it (the real
   answer comes from a signal handler, step 3 below) (`5908-5921`).
2. **INSANE BRAVERY** (1 CP, once per battle) — *before* rolling a critical test, consider
   auto-passing it. Only on Normal+ difficulty. Uses it when
   `P(fail) × unit value ≥ 1.2` (`5923-5933`, evaluator at `21857-21912`).
3. **Take every pending battle-shock test**, one per ask (`5935-5942`). The engine rolls 2D6 vs
   the unit's *effective* Leadership (best Ld in an attached unit,
   `40k/phases/CommandPhase.gd:991-996`). If the test **fails** and the player has ≥1 CP with
   Command Re-roll unused this phase, the engine pauses and signals a re-roll window
   (`40k/phases/CommandPhase.gd:937-986`). The AI answers via
   `AIPlayer._on_command_reroll_opportunity` → `evaluate_command_reroll_battleshock`
   (`40k/autoloads/AIPlayer.gd:1488-1558`, `40k/scripts/AIDecisionMaker.gd:23269-23292`): re-roll
   **only if the re-roll's pass chance is ≥ 40%** (true for Ld 8 or easier; Ld 9+ is let stand).
   A used re-roll re-rolls both dice (`40k/phases/CommandPhase.gd:1144-1163`).
4. **WAAAGH! timing (Orks)** — round 2+: always call it; round 1: call it only if at least one
   friendly unit is within ~22" of an enemy (advance+charge reach); otherwise hold
   (`5944-6006`).
5. **Plant the Waaagh! Banner** (free, once per battle) — use in round 2+, or round 1 if the
   nearest enemy is within 18" (`6013-6028`).
6. **Da Kaptin** (Orks, once per battle, unshocks a unit at the cost of D3 mortal wounds) — worth
   it only for a unit worth ≥100 pts or one standing on an objective (`6032-6054`).
7. **Grot Orderly** (once per battle, revive up to D3 bodyguard models) — wait until ≥3 models are
   down, or round 4+ with ≥1 down (`6058-6077`).
8. **Fix Dat Armour Up** (every Command phase, free 1-model return) — always use (`6080-6088`).
9. **Unleash the Lions** (Custodes, 1 CP, split into single-model units) — only round 2+ with
   ≥2 CP banked (`6092-6105`).
10. **Psychic Veil** — cast while the caster has ≥3 wounds left (5-in-6 upside vs 1-in-6 D3 MW
    downside) (`6109-6122`).
11. **Here Be Loot** (Freebooters) — mark the loot objective closest to the army's centre of mass
    (`6124-6161`).
12. **Oath of Moment target** (Space Marines) — score every enemy unit and mark the one the army
    most wants dead (see table below) (`6163-6172`, scorer at `6307-6420`).
13. **Combat Doctrine** (Gladius) — by round: rounds 1-2 Assault, round 3 Tactical, round 4+
    Devastator (`6174-6185`, `6426-6464`).
14. **Martial Mastery** (Shield Host) — `improve_ap` if the average enemy save is 3.5+ or better,
    else `crit_on_5` (`6187-6196`, `6466-6518`).
15. **Build mission awareness** (no visible action) — cache, once per round per player, which board
    zones the secondary cards reward (`6198-6208`, builder at `19826+`) and what the primary card
    wants (`6210-6221`, builder at `18708+`). Movement scoring consumes this cache later in the turn.
16. **Replace a newly drawn secondary** (1 CP, card goes back in the deck) — replace any card
    drawn this turn whose achievability score is **≤ 0.25** (`6223-6250`).
17. **NEW ORDERS** (1 CP stratagem, once per battle, permanent discard + redraw) — swap the worst
    active card if its achievability is **< 0.45 in rounds 1-2** or **< 0.30 in round 3+**
    (`6252-6292`; the stratagem itself: `40k/autoloads/StratagemManager.gd:395-421`).
18. **Proactive faction stratagems with a command window** — e.g. MOB RULE (unshock via a nearby
    mob), GRAB AND BASH (single-unit Waaagh!). Best candidate is used only if its score beats
    **2.0**, or **3.0 when it would spend the last CP** (`6294-6298`, engine at `21930-22004`,
    per-stratagem heuristics at `22043-22177`).
19. **END_COMMAND** (`6300-6301`).

**Related CP decisions outside the Command phase** (the rest of the CP economy):

- **Command Re-roll on charges** (charge phase window): never if the needed distance is >10";
  always if the miss was within 2" of a ≤9" target or the roll was ≤4 vs a ≤9" target; with ≥3 CP
  banked, any ≤9" target is re-rolled (`40k/scripts/AIDecisionMaker.gd:23226-23267`).
- **Command Re-roll on advances**: re-roll a 1 always; re-roll a 2 only with ≥3 CP banked
  (`23294-23315`).
- **Any other roll type**: declined — the AI only ever re-rolls charge, advance and battle-shock
  rolls (`40k/autoloads/AIPlayer.gd:1514-1538`, the `match` falls through to decline).
- **Discard a secondary for +1 CP** (Scoring phase, end of turn): discard the worst card if its
  achievability is **< 0.2** (or < 0.1 in round 4+ with an empty deck); the engine caps bonus CP
  at 1 per round (`40k/scripts/AIDecisionMaker.gd:18590-18688`;
  `40k/autoloads/GameState.gd:1222-1243`, `BONUS_CP_CAP_PER_ROUND = 1`).
- **Rapid Ingress CP discipline** (opponent's movement phase): never spend the last CP on it
  before round 4 (`40k/scripts/AIDecisionMaker.gd:23336-23344`).

**Thinking-block narration.** Every decision above calls `_add_thinking_step()`
(`40k/scripts/AIDecisionMaker.gd:2058-2060`); the accumulated lines are attached to the chosen
action (`3148-3150`) and rendered by AIPlayer: a header line "Thinking about Command Phase…
(actions on offer)" (`40k/autoloads/AIPlayer.gd:1986`), then a single log line or a collapsible
"Thinking: …" block in the GameEventLog plus a streaming overlay (`40k/autoloads/AIPlayer.gd:
2036-2059, 3359-3389`). Re-roll decisions happen outside the normal ask loop, so their reasoning
is flushed as its own block headed "Command Re-roll window (battle_shock_test)" etc.
(`40k/autoloads/AIPlayer.gd:1540, 3391-3399`).

---

## Scoring tables

### CP economy fixed facts (engine, not tunable)

| Term | Default value | Plain-English meaning |
|---|---|---|
| Starting CP | 0 | Both players begin the game with zero CP (`GameState.gd:64-65`) |
| CP gain per Command phase | +1 to **both** players | Automatic, every Command phase (`CommandPhase.gd:96-100,166-185`) |
| Bonus CP cap | 1 per battle round | Extra CP (e.g. from discarding a secondary) is capped (`GameState.gd:1222`) |
| COMMAND RE-ROLL cost | 1 CP, once per phase | 11e: single-die re-roll except charges (full 2D6); the battle-shock handler re-rolls both dice (`StratagemManager.gd:4230-4238`, `CommandPhase.gd:1144-1163`) |
| INSANE BRAVERY cost | 1 CP, once per battle | Auto-pass one battle-shock test, chosen before rolling (`StratagemManager.gd:4249-4257`) |
| NEW ORDERS cost | 1 CP, once per battle | Discard one active secondary card, draw a new one (`StratagemManager.gd:395-421`) |
| Battle-shock pass rule | 2D6 ≥ Leadership | Applies to the best Ld in an attached unit; +1 near a Waaagh! Effigy (`CommandPhase.gd:920-935, 991-996`) |
| Who must test | below half, at half (11e), or already shocked | Shocked units stay shocked until they pass (`CommandPhase.gd:288-301`) |

### Command Re-roll policy (1 CP each; all thresholds hard-coded)

| Roll type | Re-roll when… | Default value | Source |
|---|---|---|---|
| Battle-shock (failed) | re-roll pass chance ≥ 40% | `pass_chance >= 0.4` → yes for Ld ≤ 8 (Ld 6 = 72%, Ld 7 = 58%, Ld 8 = 42%), no for Ld 9+ (28%) | `AIDecisionMaker.gd:23283-23292` |
| Charge (failed) | needed distance ≤ 10", **and** (missed by ≤ 2" with need ≤ 9", **or** rolled ≤ 4 with need ≤ 9", **or** ≥ 3 CP banked with need ≤ 9") | gap ≤ 2; roll ≤ 4; CP ≥ 3; need > 10 = never | `AIDecisionMaker.gd:23239-23267` |
| Advance (low) | rolled a 1: always; rolled a 2: only with ≥ 3 CP | roll ≤ 1 always; roll = 2 needs CP ≥ 3 | `AIDecisionMaker.gd:23302-23315` |
| Anything else | never | declined by default | `AIPlayer.gd:1536-1538` |

The 2D6 probabilities come from an exact 36-outcome count in
`_charge_success_probability` (`AIDecisionMaker.gd:15240-15259`); failure chance is its
complement `_p_2d6_fail` (`21680-21682`).

### INSANE BRAVERY score (use when score ≥ 1.2)

`score = P(fail battle-shock) × value` (`AIDecisionMaker.gd:21857-21912`)

| Term | Default value | Plain-English meaning |
|---|---|---|
| On an objective | +3.0 to value | A shocked unit's Objective Control drops to 0 — protecting a holder is the main prize (`21885-21886`) |
| Unit points | +points ÷ 100 | A 200-pt unit adds +2.0 — pricier units are worth protecting (`21887`) |
| Round 3+ | +1.0 to value | Late-round scoring pressure (`21888-21889`) |
| Use threshold | 1.2 | Once per battle, so it demands real value (`21899`) |

### Command-phase faction ability triggers (fixed rules, no weights)

| Ability | Fires when | Source |
|---|---|---|
| WAAAGH! | Round 2+ always; round 1 if ≥1 unit within 22" of an enemy | `AIDecisionMaker.gd:5981-5993` |
| Plant Waaagh! Banner | Round 2+, or nearest enemy ≤ 18" | `6020` |
| Da Kaptin (D3 MW to unshock) | Target ≥ 100 pts or on an objective | `6045` |
| Grot Orderly (revive D3) | ≥3 bodyguard models dead, or round 4+ with ≥1 | `6068` |
| Fix Dat Armour Up | Always (free, every Command phase) | `6080-6088` |
| Unleash the Lions (1 CP) | Round ≥ 2 and CP ≥ 2 | `6096` |
| Psychic Veil | Caster has ≥ 3 wounds remaining | `6114` |
| Combat Doctrine | R1-2 Assault → R3 Tactical → R4+ Devastator | `6438-6444` |
| Martial Mastery | `improve_ap` if avg enemy save ≤ 3.5, else `crit_on_5` | `6494-6497` |

### Oath of Moment target score (multipliers on the base target value)

Base = `_calculate_target_value` (points, damage output, objective presence — the army's
focus-fire priority) (`AIDecisionMaker.gd:6341`), then:

| Term | Default value | Plain-English meaning |
|---|---|---|
| Toughness 5+ | ×1.05 per point over T4 (T8 = ×1.20) | Wound re-rolls matter more vs tough targets (`6352-6353`) |
| Save 3+ or better | ×1.1 | Each unsaved wound is precious (`6356-6357`) |
| 6+ wounds remaining | up to ~×1.24 | More attacks needed = more re-rolls used (`6362-6363`) |
| Below half strength | ×1.2 | Easier to finish off (`6368-6369`) |
| Invulnerable 4+ or better | ×0.9 | Invulns blunt the re-roll benefit (`6374-6375`) |
| Buffing leader | ×1.25 | Killing the leader strips the squad's buffs (`6380-6386`) |
| Army can't hurt it | ×0.5 | Re-rolls are wasted without the right guns (`6392-6394`) |

### Secondary mission card management

Achievability is a 0.0–1.0 score per card from `_evaluate_mission_achievability`
(`AIDecisionMaker.gd:18879-19006`) — e.g. kill-cards drop to 0.15 by round 3 with no kills yet,
positional cards are assessed from actual unit positions, unknown cards default to 0.5.

| Decision | Threshold | CP effect | Source |
|---|---|---|---|
| Replace a just-drawn card (back to deck) | achievability ≤ 0.25, needs ≥1 CP | −1 CP | `6242` |
| NEW ORDERS swap (permanent discard) | < 0.45 in rounds 1-2; < 0.30 in round 3+; needs ≥1 CP | −1 CP | `6276-6279` |
| End-of-turn discard (Scoring phase) | < 0.2 (< 0.1 in round 4+ with empty deck) | **+1 CP** if the 1-per-round bonus cap isn't hit | `18646-18657` |

### Proactive command-window stratagem scores (use if best ≥ 2.0, or ≥ 3.0 when spending the last CP)

| Stratagem | Score formula | Source |
|---|---|---|
| MOB RULE (unshock near a 10+ model MOB) | 2.5 + shocked unit's points ÷ 100 | `AIDecisionMaker.gd:22071-22073` |
| GRAB AND BASH (single-unit Waaagh!) | 2.0 + 0.2 × living models, if an enemy is within Move+14" | `22171-22172` |
| Use threshold | 2.0 normally / 3.0 for the last CP | `21976-21982` |

One related default worth knowing: `BATTLE_SHOCK_DENIAL_WEIGHT = 0.0` (**off**;
`AIDecisionMaker.gd:1895`) — the stratagems that battle-shock *enemy* units for objective flips
(SQUIG FLINGIN', IMPENDING CRUNCH) are disabled at default settings, and `ai_config.json` does
not turn them on, so the effective value is 0.0.

### Mission-awareness weights cached in the Command phase (consumed by movement)

| Term | Default (= effective) value | Plain-English meaning |
|---|---|---|
| SECONDARY_ENEMY_ZONE_PUSH_BONUS | 7.0 | Push into the enemy deployment zone for Behind Enemy Lines (`2014`, applied `19875`) |
| SECONDARY_POSITIONAL_BONUS | 4.0 | General pull toward card-relevant positions (`2010`) |
| SECONDARY_OBJECTIVE_ZONE_BONUS | 3.5 | Extra value on objectives in zones a card pays for (`2009`) |
| SECONDARY_CENTER_BONUS | 3.5 | Pull to board centre for Area Denial-type cards (`2013`) |

---

## Worked example

Invented but realistic: **Ork AI, battle round 2, its Command phase, 2 CP banked.**

1. **Engine set-up**: both players gain +1 CP → the AI now has **3 CP**
   (`CommandPhase.gd:96-100`). Two Ork units must test: a 20-strong Boyz mob reduced to 8 models
   (below half, Ld 7, 170 pts, standing on an objective) and a Gretchin unit at half strength
   (Ld 8, 40 pts, off-objective).
2. **INSANE BRAVERY check** (`AIDecisionMaker.gd:21857-21912`), evaluated per candidate:
   - Boyz: fail chance = P(2D6 < 7) = 15/36 = **41.7%**. Value = 3.0 (on objective)
     + 170/100 = 1.7 (points) + 0 (round < 3) = **4.7**. Score = 0.417 × 4.7 = **1.96 ≥ 1.2 → use**.
   - Gretchin: fail chance = P(2D6 < 8) = **58.3%**. Value = 0 + 0.4 + 0 = 0.4.
     Score = 0.583 × 0.4 = 0.23 — nowhere near the bar.
   The AI spends 1 CP (**3 → 2 CP**) and the Boyz auto-pass. Log line: "Insane Bravery check for
   Boyz: fail chance 42% (Ld 7), value 4.7 → score 1.96" then "Using INSANE BRAVERY on Boyz
   (score 1.96 ≥ 1.2)" (`21892, 21902`).
3. **Gretchin battle-shock test** (`5936-5942`): the engine rolls 2D6 = 2+4 = **6 vs Ld 8 — fail**.
   The AI has ≥1 CP and hasn't used Command Re-roll this phase, so the engine pauses and offers
   the re-roll (`CommandPhase.gd:937-970`). `evaluate_command_reroll_battleshock`: a re-roll
   passes P(2D6 ≥ 8) = 15/36 = **41.7% ≥ 40% → re-roll** (`23283-23288`). 1 CP spent
   (**2 → 1 CP**); both dice re-rolled → say 5+4 = 9 ≥ 8 — **passed, unit unshocked**. The log
   shows a "Command Re-roll window (battle_shock_test)" block: "Command Re-roll on battle-shock:
   failed 6 vs Ld 8 — re-roll passes 42% of the time" (`AIPlayer.gd:1540`, `23286`).
   (Had this been a Ld 9 unit — 27.8% — the AI would have kept the CP: `23290-23292`.)
4. **WAAAGH!**: round 2 → unconditionally called: "round 2, 5 units in range (early aggression)"
   (`5983-5989`). Free.
5. **Mission housekeeping**: awareness is rebuilt for the round (`6198-6221`). The AI's worst
   active secondary, "Assassination", scores achievability **0.20** (no enemy characters left
   alive worth hunting). Round 2 threshold for NEW ORDERS is **0.45**, and the AI has 1 CP → it
   spends it (**1 → 0 CP**): "New Orders: swap unachievable 'Assassination' for new mission"
   (`6276-6289`).
6. **Proactive command stratagems**: MOB RULE would score 2.5+, but with **0 CP** the candidate
   is filtered out before scoring (`21957-21959`) → nothing to use.
7. **END_COMMAND** (`6300-6301`). Net CP this phase: +1 gained, 3 spent, ending at 0 — with a
   likely +1 back at the end of the turn if a hopeless secondary gets discarded in the Scoring
   phase (`18668-18681`).

---

## Difficulty gates

Difficulty is set per player; the config class is `40k/scripts/AIDifficultyConfig.gd`
(autoloaded as `AIDifficultyConfigData`).

| Capability | Easy | Normal | Hard | Competitive | Source |
|---|---|---|---|---|---|
| Command phase logic runs at all | **Yes** — even Easy's random mode delegates COMMAND to the normal `_decide_command` ("just CP/Battle-shock, not tactical") | Yes | Yes | Yes | `AIDecisionMaker.gd:3046-3048, 3344-3346` |
| Command Re-roll (`use_command_reroll`) | **No — always declines** | Yes | Yes | Yes | `AIDifficultyConfig.gd:100-101`, enforced `AIPlayer.gd:1500-1509` |
| INSANE BRAVERY + all stratagems (`use_stratagems`) | **No** | Yes | Yes | Yes | `AIDifficultyConfig.gd:29-30`, gates at `AIDecisionMaker.gd:5925, 21936` |
| Proactive faction stratagems (MOB RULE, GRAB AND BASH…) | No | Yes | Yes | Yes | `AIDecisionMaker.gd:21936` |
| Battle-shock tests, WAAAGH!, banner, Oath target, doctrines, mission swaps | Yes (all difficulties — these paths have no difficulty gate inside `_decide_command`) | Yes | Yes | Yes | `AIDecisionMaker.gd:5935-6301` |
| Multi-phase planning (affects later phases, not command) | No | No | Yes | Yes | `AIDifficultyConfig.gd:33-34`, `AIDecisionMaker.gd:3110-3112` |

So the only real Command-phase differences by difficulty are: **Easy never spends CP** (no
re-rolls, no Insane Bravery, no New Orders via stratagem gate — though note the New Orders /
replace card logic itself is *not* difficulty-gated in `_decide_command`, Easy can still swap
cards) and Hard/Competitive add no extra command-phase behaviour beyond Normal.

One caveat flagged honestly: the statement above about card swapping on Easy is from code
reading — `REPLACE_SECONDARY_MISSION`/`USE_NEW_ORDERS` evaluation (`6223-6292`) sits inside
`_decide_command` with no `use_stratagems` check, and `_decide_random` routes COMMAND to
`_decide_command` (`3344-3346`) — but I did not run an Easy-difficulty game to observe it.

---

## Evidence

| Claim | Location |
|---|---|
| Both players +1 CP each Command phase; no round-1 skip | `40k/phases/CommandPhase.gd:91-100, 166-185` |
| Players start at 0 CP | `40k/autoloads/GameState.gd:64-65` |
| Bonus CP cap 1/round | `40k/autoloads/GameState.gd:1222-1243` |
| Who takes battle-shock tests (below/at half, or shocked); FEARLESS/ATSKNF immune | `40k/phases/CommandPhase.gd:260-301` |
| 11e: shocked units persist until they pass a test | `40k/phases/CommandPhase.gd:223-246, 1016-1023` |
| Battle-shock roll, effective Ld, Waaagh! Effigy +1 | `40k/phases/CommandPhase.gd:920-935, 991-1006` |
| Re-roll window offered only on failed tests with CP available | `40k/phases/CommandPhase.gd:937-986`; `40k/autoloads/StratagemManager.gd:3043-3051` |
| Re-roll re-rolls both dice for battle-shock | `40k/phases/CommandPhase.gd:1144-1163` |
| Command-phase decision order | `40k/scripts/AIDecisionMaker.gd:5908-6301` |
| Master dispatch to `_decide_command`; Easy delegates COMMAND to it too | `40k/scripts/AIDecisionMaker.gd:3128-3129, 3046-3048, 3344-3346` |
| Insane Bravery evaluator: score = P(fail)×value, threshold 1.2 | `40k/scripts/AIDecisionMaker.gd:21857-21912` |
| Battle-shock re-roll: ≥40% pass chance | `40k/scripts/AIDecisionMaker.gd:23269-23292` |
| Charge re-roll thresholds (≤10", gap ≤2, roll ≤4, CP ≥3) | `40k/scripts/AIDecisionMaker.gd:23226-23267` |
| Advance re-roll (1 always, 2 with CP ≥3) | `40k/scripts/AIDecisionMaker.gd:23294-23315` |
| Roll types handled; unknown types declined; Easy declines all | `40k/autoloads/AIPlayer.gd:1488-1558` |
| Exact 2D6 probability math | `40k/scripts/AIDecisionMaker.gd:15240-15259, 21680-21682` |
| WAAAGH! timing (R2+ always, R1 if ≥1 unit within 22") | `40k/scripts/AIDecisionMaker.gd:5944-6006` |
| Banner / Da Kaptin / Grot Orderly / Fix Dat Armour / Unleash / Psychic Veil / Here Be Loot rules | `40k/scripts/AIDecisionMaker.gd:6008-6161` |
| Oath of Moment scoring multipliers | `40k/scripts/AIDecisionMaker.gd:6307-6420` |
| Combat Doctrine round schedule; Martial Mastery save rule | `40k/scripts/AIDecisionMaker.gd:6426-6518` |
| Secondary/primary awareness build in command phase | `40k/scripts/AIDecisionMaker.gd:6198-6221, 19826-19851, 18708` |
| Replace-card ≤0.25; New Orders <0.45/<0.30 | `40k/scripts/AIDecisionMaker.gd:6223-6292` |
| Mission achievability scorer (0.0–1.0, per-card rules) | `40k/scripts/AIDecisionMaker.gd:18879-19006` |
| Scoring-phase discard <0.2 (<0.1 late) for +1 CP | `40k/scripts/AIDecisionMaker.gd:18590-18688` |
| Proactive stratagem thresholds 2.0 / 3.0-for-last-CP | `40k/scripts/AIDecisionMaker.gd:21930-22004` |
| MOB RULE and GRAB AND BASH score formulas | `40k/scripts/AIDecisionMaker.gd:22043-22076, 22153-22177` |
| BATTLE_SHOCK_DENIAL_WEIGHT default 0.0 (off) | `40k/scripts/AIDecisionMaker.gd:1895` |
| Stratagem definitions & costs (Command Re-roll, Insane Bravery, New Orders; 11e variants) | `40k/autoloads/StratagemManager.gd:110-164, 395-421, 4230-4257`; edition default 11 at `40k/scripts/rules/GameConstants.gd:26` |
| Battle-shocked units cannot use stratagems | `40k/autoloads/StratagemManager.gd:811-821` |
| CommandPhase offers Insane Bravery / New Orders / replace actions | `40k/phases/CommandPhase.gd:330-413` |
| Thinking narration pipeline (steps → blocks → GameEventLog + overlay) | `40k/scripts/AIDecisionMaker.gd:2058-2069, 3148-3161`; `40k/autoloads/AIPlayer.gd:1986, 2036-2059, 3359-3399` |
| Difficulty gates | `40k/scripts/AIDifficultyConfig.gd:23-30, 100-101` |
| ai_config.json sets only PLANS_ENABLED (no weight overrides) | `40k/data/ai_config.json:16-18`; layering in `40k/scripts/AIDecisionMaker.gd:1235-1256` |
| Rapid Ingress last-CP rule (economy context) | `40k/scripts/AIDecisionMaker.gd:23336-23344` |

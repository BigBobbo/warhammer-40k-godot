# Warhammer 40,000 — 11th Edition Core Rules vs. Encoded Game: Delta Audit

**Audited PDF:** [`docs/rules/40k_11th_edition_core_rules.pdf`](40k_11th_edition_core_rules.pdf)
(74 pp; searchable text: [`40k_11th_edition_core_rules.txt`](40k_11th_edition_core_rules.txt))
**Date:** 2026-06-21 · **Scope:** every Core Rules section (01–24 + Rules Appendix) vs. the Godot implementation under `40k/`.

> This document is the deliverable for *"go through the rules one by one and identify the
> delta between the rules as written and what has been encoded into the game."* Section
> numbers like `(05.03)` are the PDF's own reference numbers.

---

## 0. Executive summary

The codebase already contains a large, carefully-built **11th-edition migration** — tracked
in [`ISSUES.md`](../../ISSUES.md) as 74 issues (ISS-001…074), with the rules items
(ISS-037…074) all marked **DONE**, backed by ~36 headless tests and 17 windowed scenarios.
The engine-level work is genuinely high quality. **But the delta is not "10e → 11e is done."**
The honest answer has three layers:

| Layer | State |
|---|---|
| **A. The running game (what a player gets)** | **100% 10th edition.** Every 11e rule lives behind `if GameConstants.edition >= 11:` and **no production code path ever sets edition to 11** — only the test/scenario harness does. Launch the game and you play 10e. |
| **B. The engine, if you flip the switch to 11** | The **majority** of 11e rules are implemented and correctly gated — *for the shooting/movement/charge/fight-selection/objectives/coherency paths.* These reproduce the rulebook's worked examples in tests. |
| **C. Real residual gaps even at edition 11** | A number of "DONE" items are **not actually wired into live play**, run **10e logic at edition 11**, or have **no player-facing UI**. These are listed in §7 and are the substantive rules-delta that remains. |

**The single most important delta:** the 11e ruleset is *dormant*. `GameConstants.edition`
defaults to `10` (`40k/scripts/rules/GameConstants.gd:22`); the only writer outside tests is
`GameState.set_edition()` (`40k/autoloads/GameState.gd:267`), which **has zero callers**. The
scenario runner flips it per test JSON (`40k/autoloads/ScenarioRunner.gd:98`). There is no
settings, menu, lobby, or save-load path to select the edition. (This is *by design*
mid-migration — see PRD §5 open question 1 — but it means none of the 11e work is reachable
by a player today.)

**Most important residual gaps (full list in §7):**
1. **Melee/fight save resolution still runs 10e at edition 11** — allocation groups, the
   `[DEVASTATING WOUNDS]` one-model cap, and mortal-wound priority are bypassed in the live
   fight flow (`FightController.gd:2856` is hard-wired to the legacy overlay; ranged is gated).
2. **`[HAZARDOUS]` uses the wrong dice band** at edition 11 (fires on `1` only, flat `3×` MW —
   10e/Balance-Dataslate semantics, not the 11e 1–2-fail / 1-MW rule).
3. **Indirect fire still 10e** in the live path (the harsh 11e "6s-to-hit unless stationary +
   spotter" exists only in an unwired module method).
4. **11e core stratagems are mechanically inert** — defined and gated, but using one deducts CP
   and applies **no effect** (no EffectPrimitives/UI wiring).
5. **The Actions system can't be started** — the module is correct but no live path *starts* an
   action; only the end-of-turn *completion* hook runs (with nothing to complete).
6. **`HIDDEN` (13.09) is non-functional** — keyed off a `shot_recently` flag nothing writes.
7. **No player UI for FLY "take to the skies" or SURGE moves**; **Scout confirm-move** still
   hardcodes the 10e 9".
8. **Datasheet values are still 10e** — army JSONs carry 10e-derived stats with
   `needs_11e_review` flags; true 11e Ld/OC/InSv values were never sourced (PRD §5 open q.2).

---

## 1. How to read this

**Status legend** (describes *what the live game does at edition 11*, unless noted):

| Status | Meaning |
|---|---|
| ✅ **MATCH** | 11e rule implemented, edition-gated, and wired into the live path. |
| 🟡 **PARTIAL** | Implemented but incomplete, only in a module/primitive not the live path, or depends on data/UI that doesn't exist. |
| 🔴 **CONTRADICTS** | Live code runs 10e behavior (or wrong values) even at edition 11. |
| ⚪ **MISSING** | Not implemented. |
| 🔵 **DORMANT** | Applies to *everything*: gated behind the off-by-default `edition` flag (stated once here, not repeated per row). |

**Verification basis.** Findings were produced by reading the actual `.gd` source (not by
trusting `ISSUES.md` DONE labels), via five parallel audit passes plus direct spot-checks of the
most surprising results (melee overlay, hazardous dice band, scout confirm, CP generation,
edition setters, devastating-wounds spillover). **What was *not* done:** the game was not run for
this audit, so claims that a windowed scenario "passes" are the tracker's, not re-confirmed here;
all *code-level* gating/wiring statements are first-hand. Per the project's own validation rule,
re-running the windowed suite at edition 11 is the recommended next step (§10).

---

## 2. Basic Rules (PDF Part 1, §01–06)

### §01 Core Concepts · §02 Datasheets · §03 Moving · §04–05 Attacks · §06 Other

| § | Rule (11e) | Status | Location / Note |
|---|---|---|---|
| 01.04 | Measure to/from closest part of base | ✅ | `Measurement.gd` distance helpers measure base-edge to base-edge. |
| 01.06 | Leadership roll = 2D6 ≥ Ld | ✅ | `AttackSequence.leadership_roll` (`:179`); live command path rolls equivalently. |
| 01.07 / 08.03 | Battle-shock: test units **shocked OR at-or-below half**; pass-while-shocked recovers; while shocked OC '-', no own-stratagem target, no actions | ✅ | `CommandPhase.gd:269-282` passes `at_half` (ISS-065 fix is real: exactly-half now tests); recovery `:931`; `GameState.is_at_half_strength_combined` handles odd-strength caveat. |
| 02.02 | Profile incl. **Invulnerable Save as a characteristic**, Ld as "X+", OC may be '-' | 🟡 | Schema supports `invuln`/`oc`/`leadership` (ISS-037 schema-2). **But true 11e datasheet *values* were never sourced** — armies carry 10e numbers + `needs_11e_review` (`40k/armies/orks.json`). Ld kept as int (mechanic identical). |
| 03.03 | **Coherency:** within 2"/5" of ≥1 model **AND within 9" of every** model; end-of-turn out-of-coherency removal (no death triggers) | ✅ | `AttackSequence.check_unit_coherency` adds the 9" envelope at e11; end-of-turn hook `PhaseManager.gd:430` removes most-isolated model. *Caveat:* auto-picks removal (no player-choice dialog); movement *staging* preview still uses 10e 2"/5" check. |
| 03.04 | **Engagement range = 2" horiz / 5" vert** (was 1") | ✅ | `GameConstants.engagement_range_inches()` → 2.0 at e11; `is_unit_engaged`/`unengaged` predicates used as eligibility gates. |
| 04.03 | **Identical-attack gathering** across weapons; split melee attacks across targets | 🟡 | `AttackSequence.gather_identical_attacks` reproduces the pg-20 example, **but live `resolve_shoot` only merges *same-weapon* batches** (cross-weapon gather deferred); **melee gather + melee split-across-targets not implemented**. |
| 05.01 | Hit rolls: unmod 1 fails, unmod 6 = crit hit, ≥BS/WS hits | ✅ | `AttackSequence.evaluate_hit_roll` (`:38`), shared by all paths, both editions. |
| 05.02 | Wound rolls: 1 fails, 6 crit, S-vs-T table (2×→2+ … ≤½→6+) | ✅ | `AttackSequence.evaluate_wound_roll` (`:66`) + `wound_threshold` table exact. |
| 05.03 | **Save rolls via allocation groups** (per-CHARACTER + identical W/Sv/InSv; order constraints; batch saves) | 🟡 | `Allocation.gd` implements 05.03 exactly and reproduces the Celestine example. **Wired for SHOOTING only** (`ShootingController.gd:2552` gates 11e overlay). **Melee never builds groups** (see 🔴 below). |
| 05.04 | Inflict damage lowest→highest, wounded-first, invuln-vs-AP, excess lost | 🟡 | `Allocation.apply_save_rolls` (`:148`) — ranged only; melee uses legacy per-wound path. |
| 05.03–05.04 | *(melee save resolution)* | 🔴 | **`FightController.gd:2856` unconditionally uses `WoundAllocationOverlay`** (10e per-model clicks). No allocation groups, no order constraints in melee at e11. |
| 06.01 | Visible vs **fully visible**; 1mm line ignoring both units' own models | 🟡 | `model_visible_11e`/`model_fully_visible_11e` exist & gated; "1mm line" approximated by 9-point base sampling; "ignore own models" holds only because models are never blockers. |
| 06.02 | **Mortal wounds** one-at-a-time, priority (wounded-non-CHAR → non-CHAR → wounded-CHAR → CHAR), after normal damage | 🟡 | `Allocation.select_mortal_wound_target`/`apply_mortal_wounds_11e` exact; consumed by ranged + stratagems. **Melee MW path** doesn't use it and ordering isn't enforced. |
| 06.03 | **Hazard roll:** D6, 1–2 fail → 1 MW (3 MW if all models MONSTER/VEHICLE) | 🟡 | `AttackSequence.hazard_rolls` exact — **but only consumed by movement** (fall-back/disembark). The shooting/fight `[HAZARDOUS]` path does **not** use it (see 🔴 24.15). |

---

## 3. The Battle Round (PDF Part 2, §07–12)

| § | Rule (11e) | Status | Location / Note |
|---|---|---|---|
| 07 | Battle-round structure: SoBR → turns (SoT, 5 phases, EoT) → EoBR; **non-mission rules resolve before mission rules** at EoT/EoBR | ✅ | `PhaseManager` exposes the step signals + a registerable End-of-Turn hook API sorting non-mission before mission (`:49`). Coherency removal + action completion hang off it. |
| 08.02 | **Both players gain 1 CP** each Command phase | ✅ (outcome) | `CommandPhase._generate_command_points` (`:153`) adds +1 to both — **but unconditionally, not edition-gated** (comment cites "Issue #382 / Wahapedia 10e"). The book-10e "active player only" behavior exists *nowhere* in this codebase. |
| 09.04–09.07 | Move types: remain / normal / advance (D6+M, blocks charge & actions) / **fall-back with modes** (Ordered Retreat vs Desperate Escape: hazard per model + follow-up battle-shock) | ✅ | `scripts/rules/movetypes/*` templates, wired in `MovementPhase`. **ISS-064 double-hazard bug confirmed fixed** — legacy `_process_desperate_escape` gated to `edition < 11` (`MovementPhase.gd:4625`). |
| 10.02 | Select a **shooting type** per unit (Normal/Assault/Close-Quarters/Indirect; Snap via rule) | ✅ | `ShootingTypes.available_for` authoritative at e11; wired in `ShootingPhase.gd:558,754`. |
| 10.04 | Normal shooting (unengaged, not advanced) | ✅ | `NormalShooting`. |
| 10.05 | **Assault** shooting (advanced + [ASSAULT]; only [ASSAULT] fire) | ✅ | `AssaultShooting`; weapon gate enforced live (`ShootingPhase.gd:600`). |
| 10.06 | **Close-Quarters** shooting (engaged + [CLOSE-QUARTERS] or M/V; M/V −1 except CQ-vs-engaged; non-M/V CQ-only; [BLAST] never vs engaged) | ✅ | `CloseQuartersShooting` + live target/weapon gates; M/V −1 applied via `ModifierStack` at e11. The pg-88 FAQ "no BLAST vs engaged either direction" reproduced in tests. |
| 10.07 | **Indirect** shooting: target non-visible; gets cover; no hit re-rolls; **unmod 1–5 fails (1–3 if stationary + friendly spotter)** | 🔴 | Live `RulesEngine.gd:1809/3094` still runs **10e** (`−1 to hit` + `fail_band 3 only if unseen`), **no edition gate**. The harsh 11e band exists only in `IndirectShooting.hit_consequences`, which is **never called in live play**. |
| 11.02 | Charge eligibility (within 12", unengaged, no advance/fall-back); **targets chosen after the 2D6 roll** (≤12" AND ≤roll) | ✅ | `ChargeMove11e` + live wiring accepts empty declare then post-roll selection (`ChargePhase.gd:317,327,567`); pg-37 semantics reproduced. |
| 11.04 | End engaged with **all** targets, none non-target; chargers gain **Fights First** ability to EoT | ✅ | Constraints use 2" ER at e11; Fights First granted (`ChargePhase.gd:1203`). *Cosmetic:* failure messages hardcode `1"`. |
| 12.02–12.03 | **Pile-in as a separate step** (both players, active first); 5" select for unengaged charge-survivors; base-contact lock; closer-to-target | 🟡 | `PileInMove` is genuinely invoked by `_validate_pile_in_11e` (geometry authoritative). **But structurally per-fighter**, not a global "both players pile in first" step; `selected_for_overrun_fight` flag is never set in production. |
| 12.04 | Fight step: alternate **Fights First first** (active player first), then remaining; return to FF when new; pass rule (>5") | ✅ | `FightSequencer` is the live selection authority at e11 (`FightPhase.gd:235,573,1234`). 11e delta (active-player-first) vs 10e defender-first. |
| 12.05/12.06 | Normal vs **Overrun** fight (extra pile-in for charge-survivors) | 🟡 | Overrun units *are* selectable; the `overrun` type is surfaced — but **no distinct extra-pile-in** beyond the normal pile-in step. |
| 12.07–12.08 | **Consolidate as a separate step** with mandatory modes Ongoing/Engaging/Objective; engaging-mode pulls new enemies in to fight | 🟡 | `ConsolidationMove` invoked by `_validate_consolidate_11e` (modes + movement authoritative). Forced-fights handled by the edition-agnostic `_scan_newly_eligible_units_after_consolidation` (net effect achieved); the module's own `forced_fights_after_engaging` is dead. Per-fighter, not a global step. |

---

## 4. Battlefields & Tactics (PDF Part 3, §13–16)

| § | Rule (11e) | Status | Location / Note |
|---|---|---|---|
| 13.03–13.05 | Terrain categories **Exposed/Light/Dense** + height model | 🟡 | `TerrainManager.category_of`/`height_inches_of` derive from legacy type/label heuristically; no layout authors explicit categories; two height functions disagree on unknown-default. |
| 13.06 | Terrain movement by category/keyword (Dense: INFANTRY/BEASTS/SWARM/**MOBILE** horiz; others ≤2"; ≤4" for SUPER-HEAVY WALKER) | ✅ | `TerrainManager.can_move_through_11e` wired into `MovementPhase` per-model-dest. *Gap:* the **charge** path still uses the 10e penalty model. |
| 13.08 | **Benefit of cover = worsen attacker BS by 1** (NOT +1 save) | ✅ | The headline mechanic change is correct & gated: `ModifierStack.collect_hit_context_11e` worsens BS hit-side; saves untouched. *Latent risk:* the 10e cover-on-save code (`_calculate_save_needed:4320`) is **not edition-gated**, merely bypassed because the 11e shooting overlay rebuilds saves from base — if melee/legacy paths ever consumed it, cover would wrongly help saves. |
| 13.09 | **Hidden:** INFANTRY/BEASTS/SWARM in dense-containing area that didn't shoot → visible only within 15" | 🔴 | Logic exists & gated, **but keys off `unit.flags.shot_recently`, which no production code ever writes** (ShootingPhase writes `has_shot`); no previous-turn memory. Net effect: every qualifying unit is "hidden" every turn. Effectively broken. |
| 13.10 | **Obscuring:** light/dense areas block LoS when every line crosses them | 🟡 | `_line_blocked_11e` implements the every-line test (gated, wired into targeting) — but via 9-point sampling, and lives in `TerrainManager`, not `EnhancedLineOfSight`. |
| 13.11 | **Solid:** no LoS through enclosed gaps ≤3" from ground | 🔴 | Dead code — the Obscuring branch returns first, so the ≤3"/ground-level branch is unreachable; dense always blocks regardless of elevation, and there's no real gap/window geometry (2D board). |
| 14.01 | **Terrain objectives:** in-range = inside the coincident terrain area; 40mm marker only when no area | ✅ | `MissionManager.gd:278` point-in-polygon at e11; marker-radius fallback. *Caveat:* fallback radius shared across editions; vertical 5" unmodeled (2D). |
| 14.02 | Control recomputed at end of **each phase and turn**; higher OC controls; tie = uncontrolled unless secured; shocked OC '-' | ✅ | `MissionManager` recompute on `phase_completed` + `turn_ending` (gated); battle-shocked contributes 0. |
| 14.03 | **Secured** objectives persist without presence until opponent exceeds | ✅ | `secure_objective`/`is_objective_secured` reuse the sticky mechanism (`MissionManager.gd:342`). |
| 15.01 | Stratagem use: once per phase per player; **can't target the same unit with >1 stratagem/phase** | ✅ | Per-unit-per-phase restriction gated at e11 (`StratagemManager.gd:671`). |
| 15.02–15.12 | **11e core stratagem set** (Command Re-roll, Epic Challenge, Insane Bravery, **Explosives**, **Crushing Impact**, Rapid Ingress, Fire Overwatch [snap], Smokescreen, Heroic Intervention [modes], Counteroffensive 2CP) | 🟡→🔴 | All 10 exist as `edition:11` **definitions**, correctly filtered. **But the effects are inert:** the new effect types aren't registered in `EffectPrimitives` and no controller/UI/AI references any `*_11e` id — **using one spends CP and does nothing**. Explosives/Crushing Impact dice handlers are fully coded in `RulesEngine` but unreachable from the stratagem flow (only tests call them). Contrast: 10e Grenade/Tank Shock are fully end-to-end. |
| 16.00–16.01 | **Actions** system (eligibility gates; start blocks shoot/charge; move cancels; completes at stated time) | 🟡 | `ActionsManager` is correct & gated, and its lock flags *are* consumed by live shooting/charge eligibility — **but nothing in live play ever *starts* an action** (only tests call `start_action`); no player affordance. Only the end-of-turn completion hook runs, with nothing to complete. |

---

## 5. Advanced Rules (PDF Part 4, §17–23)

| § | Rule (11e) | Status | Location / Note |
|---|---|---|---|
| 17.01 | M/V move through non-M/V models on normal/advance | ✅ | Pre-existing; preserved. |
| 17.02 | **FRAME** keyword (measure to closest point, not base) for baseless models | 🟡 | Keyword supported in schema (ISS-037); measurement special-casing present. |
| 17.03 | Shoot **engaged enemy M/V at −1 to hit** (except [CLOSE-QUARTERS] from engaged unit) | ✅ | Applied via `ModifierStack` at e11 (ISS-048). |
| 18.02 | Embark after a normal/advance/fall-back move; all models ≤3"; not set up this turn | 🟡 | `TransportManager.can_embark:59` gates the set-up-this-turn ban at e11, **but the live `_validate_embark_unit` only checks a generic `moved` flag** — doesn't distinguish move type (would allow embark after e.g. ingress). |
| 18.04 | **Disembark modes** Rapid / Tactical (then make a move) / Combat (6", hazard per model, shocked, no charge); can't disembark from advanced/fallen-back transport | 🟡 | `DisembarkMove` + live `CONFIRM_DISEMBARK` wiring (ISS-058). *Caveat:* Combat-mode **"set up engaged" advertised but NOT honored** — `_validate_confirm_disembark` (`MovementPhase.gd:7644`) unconditionally rejects models in engagement range, no combat exception. |
| 18.05 | **Emergency disembark** on transport destroyed (6", hazards, shocked, unplaceable models die) | 🔴 | **Live path runs pure 10e:** transport destruction fires `RulesEngine.resolve_transport_destruction:11752` (D6 fail-on-1, **3" placement**, ungated). The compliant `EmergencyDisembarkMove.gd` **and** `TransportManager.resolve_transport_destroyed` (6"+hazard) are **both dead code** (zero live callers). Deadly-Demise ordering itself is correct. |
| 19.01 / 24.34 | Bodyguard may have **one Leader AND one Support** | 🟡 | Per-role cap exists & gated in `CharacterAttachmentManager.can_attach` (single-player + UI). **NOT enforced in the diff/network pipeline** — `DeploymentPhase._validate_attach_character_deployment` has no role/edition/count check, so composite/multiplayer deploy could over-attach. |
| 19.02 | Attacks vs attached unit use **highest bodyguard Toughness** | 🔴 | `_get_attached_unit_toughness:4051` swaps in the bodyguard unit's single T value — **does not take `max()` across mixed-T bodyguard models**. Correct only for uniform-T squads; not edition-gated. |
| 19.03–19.04 | Keyword union; **ability persistence** until source destroyed | 🟡 | Keyword union exists but wired into **one** consumer (ANTI crit threshold); other keyword checks ignore it. Persistence ties to the leader **unit** being alive, not the source **model** (≈ ok for 1-model leaders). Effect-flag expiry deferred (→ ISS-027). |
| 20.01–20.04 | **Ingress move** (≤6" of edge, **>8"** from enemies [was 9"], no opp DZ before R3, then may charge); reserves destroyed end of R3; 50% cap | 🟡 | `IngressMove` + live `PLACE_REINFORCEMENT` (edge + 8" gated). **But the opponent-DZ-before-R3 ban is dead live** — the caller omits `opponent_zone` (`MovementPhase.gd:5155`), so a round-2 ingress into the enemy DZ passes. **Rapid Ingress still uses 10e 9"/edge geometry** regardless of edition. R3 destruction + charge-after-ingress work. |
| 21.02 | **Surge move** (new triggered move toward closest enemy) | 🟡 | `SurgeMove` template gated, **but the live `BEGIN_SURGE_MOVE` handler is separate ungated legacy code**, and there's **no player UI**. |
| 21.03 / 24.17 | **FLY "take to the skies"** (−2", 0 with HOVER, ignore vertical, move through all) | 🟡 | Logic correct & gated in BEGIN_NORMAL/ADVANCE/FALL_BACK, **but no UI sends the payload** — reachable only via `dispatch_action`. |
| 22.01–22.04 | Aura / Faction / Psychic / Wargear ability classes | ✅ | Pre-existing managers; preserved. |
| 22.05 | **Plunging Fire** (+1 BS from ≥3" height or TOWERING ≤12"; nets zero with cover) | ✅ | `TerrainManager.plunging_fire_applies` + `ModifierStack` at e11 (ranged). |
| 23.01 | Aircraft must **start in reserves**; **can only ingress-move** | 🟡 | Must-start-in-reserves enforced & gated (deploy-on-board rejected); real Orks Wazbom covered. **But "can only ingress-move" is MISSING** — nothing blocks an aircraft making a normal/advance/fall-back move. |
| 23.02–23.04 | Aircraft return to reserves end of opponent's turn; FLY-only charge/melee | 🟡 | End-of-turn return cycle implemented (`TurnManager` on MORALE). FLY-only charge/melee interactions not separately verified. |

---

## 6. Reference: Core Abilities (PDF §24) + Appendix

| § | Ability (11e) | Status | Note |
|---|---|---|---|
| 24.01 | Keyword-scoped abilities (e.g. `[LETHAL HITS: VEHICLE]` apply only vs matching target) | 🟡 | Scope parsing + target-threading added; **latent** — no current weapon data uses scoped LH/SUSTAINED/TWIN, so the only live scoped ability is `[ANTI]` (already correct). |
| 24.02 | Duplicated abilities don't stack (pick highest numeric) | 🟡 | `AbilityRegistry` merges to highest; latent (no current data duplicates). |
| 24.03 | `[ANTI-X Y+]` | ✅ | `get_critical_wound_threshold`, target-scoped. |
| 24.04 / 24.05 | `[ASSAULT]` / `[BLAST]`+`[BLAST X]` | ✅ | BLAST 2 vs 12 = +4 reproduced. |
| 24.06 | **`[CLEAVE X]`** (NEW, melee blast, single target) | 🔴 | `AbilityRegistry.cleave_bonus_dice` parses/computes but has **zero resolution callers** — adds **0 dice** in live play. |
| 24.07 / 24.27 | **`[CLOSE-QUARTERS]`** (NEW; supersedes `[PISTOL]`, identical) | ✅ | Mapped; enables close-quarters shooting. |
| 24.08 | Deadly Demise X | ✅ | Ordering vs emergency disembark handled. |
| 24.09 | **Deep Strike** ingress **>8"** (was 9") | ✅ | Edition-gated 9→8. |
| 24.10 | **`[DEVASTATING WOUNDS]`** cap: ≤1 model per crit, excess lost | 🟡→🔴 | Ranged: correct (pg-80 reproduced). **Melee: still 10e spillover** (`RulesEngine.gd:10028`), no edition gate. |
| 24.11 | `[EXTRA ATTACKS]` | ✅ | Pre-existing. |
| 24.12 / 24.13 | Feel No Pain / Fights First | ✅ | FNP X+; Fights First consumed by FightSequencer. |
| 24.14 | **Firing Deck X** (select X models, one ranged each, exclude `[ONE SHOT]`) | ✅ | Fixed (ISS-071): excludes [ONE SHOT]/melee, one-per-model; windowed. |
| 24.15 | **`[HAZARDOUS]`** (one hazard roll per selected weapon; 1–2 fail → 1 MW) | 🔴 | Live `resolve_hazardous_check` (`RulesEngine.gd:7372,7404`) fires on **`1` only** with flat **3 MW** (10e/Balance-Dataslate), **no edition gate**; the correct `hazard_rolls` primitive isn't wired here. |
| 24.16 | **`[HEAVY]`** +1 hit if unengaged, not set up this turn, **moved ≤3"** (was "remained stationary") | 🔴 | `ModifierStack.heavy_applies_11e:160` still keys on `flags.remained_stationary`, **not the ≤3"-moved allowance** (code comment defers the 3" rule to ISS-054). A unit that moved 2" gets no `[HEAVY]` bonus. |
| 24.18 | `[IGNORES COVER]` (incl. negating Stealth) | ✅ | Present. |
| 24.19 | `[INDIRECT FIRE]` | 🔴 | Enables indirect shooting, but the **resolution is 10e** (see 10.07). |
| 24.20 | **Infiltrators** deploy **>8"** (was 9") | ✅ | `DeploymentPhase.gd:323` gated 9→8; windowed. |
| 24.21 | `[LANCE]` (+1 wound on charge) | ✅ | Present. |
| 24.22 / 24.34 | Leader / **Support** | ✅ | Two-slot attach at e11. |
| 24.23 | **`[LETHAL HITS]` is now a choice** (may decline auto-wound to keep crit-wound triggers) | ✅ | `lethal_hits_auto_wound_11e` gating; default auto-wounds except lethal+devastating. |
| 24.24 | **Lone Operative** (12" or **X" variant**; `[INDIRECT FIRE]` can't target beyond range) | ✅ | `get_lone_operative_range` parses X"; both gates weapon-agnostic (ISS-069); windowed. |
| 24.25 | `[MELTA X]` | ✅ | Half-range +X damage. |
| 24.26 | `[ONE SHOT]` | ✅ | Tracked. |
| 24.28 | **`[PRECISION]`** selects the **visible** CHARACTER allocation group | 🟡 | Promotes the first CHARACTER group in both ranged flows, **but does not check visibility** (deferred to ISS-052) and offers no attacker choice of which character. |
| 24.29 | **`[PSYCHIC]`** ignores BS/WS + hit-roll modifiers | 🟡 | Strips harmful modifiers in both **shooting** loops, **but the melee loop has no 11e ModifierStack** — PSYCHIC *melee* weapons don't ignore penalties. (General: melee is a separate legacy path that doesn't share the 11e hit-modifier stack.) |
| 24.30 | `[RAPID FIRE X]` | ✅ | +X within half range. |
| 24.31/24.32 | **Scouts** >8" (was 9"); wholly-in-DZ; reserves→DZ option | ✅ | Staging + confirm both use the edition-gated 8" (A6 fixed the hardcoded 9" at `ScoutPhase.gd:319`). On-table scout move + wholly-in-DZ staging present; the **reserves→DZ option now has a player UI** (B8) — reserve scouts list as `[Reserves → DZ]` and deploy via `SCOUT_RESERVES_DEPLOY`. Windowed: `iss067_scout_reserves_deploy_11e`. |
| 24.33 | Stealth (grants cover = −1 to hit at e11) | ✅ | Via cover-as-BS path. |
| 24.35 | **Super-Heavy Walker** (move through models/≤4" terrain; optional MOBILE grant then D6, 1 = shocked) | ✅ | Wired incl. player UI toggle + seeded D6 (ISS-073); windowed. |
| 24.36 | `[SUSTAINED HITS X]` | ✅ | Crit → X extra hits. |
| 24.37 | `[TORRENT]` (auto-hit) | ✅ | Present. |
| 24.38 | `[TWIN-LINKED]` (re-roll wound) | ✅ | Present. |
| App. | Starting strength / half-strength (incl. odd-strength caveat, attached units) | ✅ | `GameState.is_at_half_strength[_combined]` (ISS-065). |
| App. | Objectives not within a terrain area (40mm marker, 3"/5") | 🟡 | Marker fallback present; vertical 5" unmodeled (2D). |
| App. | Revived models, mixed keywords, "eligible-but-unable to fight" pass rule | ✅ | Pass rule in FightSequencer; revive/keyword-union handled. |

---

## 7. Consolidated gaps & contradictions (prioritized)

> **Root-cause theme:** the **melee/fight resolution is a separate legacy code path** that does
> not share the 11e modules (allocation, ModifierStack, hazard, dev-wounds cap). Several gaps
> below (A1, A2-melee, A8, A9) are facets of this one structural fact. Likewise, several rules are
> implemented as a **module/registry entry that the live path never calls** (A3, A4, A7, A8, A12).

**Tier A — would block correct 11e play even with `edition = 11`:**
- **A0. The edition switch is never flipped in production** (`GameConstants.gd:22`; `set_edition` has zero callers). *Everything below only matters once a player can select 11e.*
- **A1. Melee/fight saves run 10e** — no allocation groups, no `[DEVASTATING WOUNDS]` cap (active spillover at `RulesEngine.gd:10028`), no 06.02 MW priority. `FightController.gd:2856`.
- **A2. `[HAZARDOUS]` wrong dice band / damage** at e11 (`RulesEngine.gd:7372,7404` — fires on `1`, flat `3×` MW).
- **A3. Indirect fire resolves as 10e** (`RulesEngine.gd:1809/3094`); the harsh 11e module method is unwired.
- **A4. 11e core stratagems are inert** — defined but no effect wiring (`StratagemManager` `*_11e` ids unreferenced; effects unregistered).
- **A5. `HIDDEN` non-functional** — `shot_recently` flag never written; no previous-turn memory.
- **A6. Scout confirm-move hardcodes 9"** (`ScoutPhase.gd:319`) — contradicts the gated staging path.
- **A7. Emergency disembark runs 10e** — live `RulesEngine.resolve_transport_destruction` uses D6-fail-on-1 + 3" placement; the compliant 6"+hazard `EmergencyDisembarkMove`/`TransportManager.resolve_transport_destroyed` are dead code.
- **A8. `[CLEAVE X]` adds no dice** — registry-only, zero resolution callers.
- **A9. `[HEAVY]` uses "remained stationary", not the 11e ≤3"-moved rule** (`ModifierStack.heavy_applies_11e:160`).
- **A10. `[PSYCHIC]` melee weapons don't ignore hit modifiers** (melee path has no 11e ModifierStack).
- **A11. 19.02 bodyguard Toughness is the unit's single T, not `max()` across mixed-T models.**
- **A12. Ingress "no opponent DZ before round 3" ban is dead live** — caller omits `opponent_zone` (`MovementPhase.gd:5155`); Rapid Ingress also still uses 10e 9".

**Tier B — missing player affordances / pipeline enforcement (rules exist but unreachable/unguarded):**
- **B1. Actions can't be *started*** by any live path (`ActionsManager.start_action` test-only).
- **B2. FLY "take to the skies"** and **B3. Surge moves** have no MovementController UI.
- **B4. Coherency end-of-turn removal** auto-picks (no player model-choice dialog).
- **B5. `[DEVASTATING WOUNDS]` / `[LETHAL HITS]` attacker choice prompts** default-only (no UI).
- **B6. Leader+Support attach cap not enforced in the diff/network pipeline** (`DeploymentPhase._validate_attach_character_deployment`) — multiplayer/composite deploy could over-attach.
- **B7. Aircraft "can only ingress-move" not enforced** — a normal/advance/fall-back move isn't blocked.

**Tier C — deferred by design (PRD §5) / cosmetic / out of 2D scope:**
- **C1. True 11e datasheet values** (Ld/OC/InSv) not sourced — armies carry 10e stats + `needs_11e_review`.
- **C2. 11e mission pack / secondaries / most action definitions** not authored (no source).
- **C3. Vertical terrain movement, `SOLID` ≤3" gap geometry, fully-continuous 1mm LoS** — out of 2D-board scope (sampled/approximated).
- **C4. AI competence** (Hidden-aware positioning, cover-as-BS valuation) — plays *legally* at e11 but not optimally.
- **C5. Cosmetic:** charge failure messages say `1"` while logic uses 2"; cover-on-save 10e code present-but-bypassed (not gated).

---

## 8. What is genuinely solid (don't re-do)

The following are correctly implemented, edition-gated, and wired, reproducing the rulebook's
worked examples in tests: **ranged** attack resolution (identical same-weapon gather → allocation
groups → lowest-first damage → devastating cap), **cover-as-BS** and **Plunging Fire** (net-zero),
**engagement range 2"** and **coherency 2"/9"** + end-of-turn removal, the **move-type framework**
(remain/normal/advance/fall-back with modes; ISS-064 fix), **shooting-type selection** + Close-Quarters
+ engaged-M/V −1, the **11e charge** (select-after-roll), the **FightSequencer** (active-first
alternation, Fights First, pass rule), **pile-in/consolidation** geometry & modes, **terrain
objectives** + per-phase control + **Secured**, **battle-shock** (incl. exactly-half), **disembark
modes** + emergency disembark, **two-slot Leader+Support** attach + highest-T, **ingress/Deep
Strike 8"**, **Firing Deck**, **Lone Operative X"**, **Super-Heavy Walker** gamble, and the
standard weapon-ability set (`[ANTI]`/`[BLAST]`/`[RAPID FIRE]`/`[SUSTAINED HITS]`/`[MELTA]`/
`[TORRENT]`/`[TWIN-LINKED]`/`[PRECISION]`/`[PSYCHIC]`/`[LETHAL HITS]`-as-choice).

---

## 9. Cross-reference to `ISSUES.md`

| Area | Tracked as | Tracker status | This audit's verdict |
|---|---|---|---|
| Edition switch | ISS-002 / PRD §5.1 | DONE (default 10) | Accurate; **no production flip** — the migration is not live. |
| Attack resolution (ranged) | ISS-041/045/046/053 | DONE | Accurate for ranged. |
| **Melee saves/dev-wounds** | ISS-050 (DONE*) | "fight selection only" | **Gap real** — melee save resolution still 10e (A1). |
| `[HAZARDOUS]` | ISS-044 (primitive) | DONE | Primitive correct but **live path still 10e** (A2). |
| Indirect fire | ISS-048 | DONE | **Live resolution still 10e** (A3). |
| Core stratagems | ISS-056 | DONE | Definitions only; **effects inert** (A4). |
| Actions | ISS-057 | DONE | Primitive correct; **not startable in UI** (B1). |
| Hidden | ISS-052 | DONE | **Flag never set → inert** (A5). |
| Scouts | ISS-067 | DONE | Confirm-move 8" (A6 fixed); reserves→DZ player UI added (B8). |
| FLY/Surge | ISS-061 | DONE | Engine ok; **no UI** (B2/B3). |
| Emergency disembark | ISS-058 | DONE | **Live path 10e** — 11e module is dead code (A7). Disembark *modes* are wired. |
| Attached units | ISS-059 | DONE | Highest-T is **not `max()`** (A11); dual-slot cap unenforced in pipeline (B6); persistence unit-not-model. |
| Reserves / ingress | ISS-060 | DONE | Edge+8" gated, **but DZ-before-R3 ban dead live + Rapid Ingress still 9"** (A12). |
| Aircraft | ISS-074 | DONE | Start-in-reserves + return cycle ok; **"ingress-only" not enforced** (B7). |
| Datasheet values | ISS-037 / PRD §5.2 | DONE (schema; values pending) | Accurate — **values still 10e** (C1). |

**Bottom line:** the engine-level 11e migration is ~80% genuinely done and tested *behind the
flag*, but (1) it is **dormant** (no way to enable 11e in normal play), and (2) several "DONE"
subsystems — most importantly **melee save resolution, hazardous, indirect fire, stratagem
effects, and the actions UI** — would not behave as 11e even if the flag were flipped today.

---

## 10. Recommended next steps (if the goal is to actually ship 11e)

1. **Make the edition selectable & validate live (A0).** Add a settings/new-game toggle that
   calls `GameState.set_edition(11)` and persists in the save schema, then run the full windowed
   scenario suite *and a real deploy→5-round game* at edition 11. Per the project's validation
   rule, this is the gate that turns "engine implemented" into "feature delivered."
2. **Close the melee gap (A1, A2-melee, A8-melee, A10).** Route the fight save flow through
   `AllocationGroupOverlay`/`resolve_allocation_batch_11e` at e11 (mirror `ShootingController.gd:2552`
   in `FightController.gd:2856`), and give the melee resolution loop the same 11e ModifierStack so
   `[PSYCHIC]`, the dev-wounds cap, and MW priority apply.
3. **Wire the after-attack & resolution modules that exist but aren't called:** `[HAZARDOUS]` →
   `AttackSequence.hazard_rolls` (A2); indirect → `IndirectShooting.hit_consequences` (A3);
   emergency disembark → `EmergencyDisembarkMove` (A7); `[CLEAVE]` (A8); ingress `opponent_zone`
   (A12). These are mostly one-to-a-few-line call-site fixes, not new logic.
4. **Make the inert subsystems usable:** register the 11e stratagem effects + dispatch the dice
   handlers (A4); add a "Start action" affordance (B1); add FLY/Surge/coherency-removal UI
   (B2–B4); enforce the Leader+Support cap and aircraft ingress-only in the action pipeline
   (B6/B7).
5. **Fix the contradictions that are pure value/flag bugs:** Scout confirm 9→8 (A6),
   `[HEAVY]` ≤3" (A9), highest-T `max()` (A11), `HIDDEN` `shot_recently` flag (A5).
6. **Source true 11e datasheet values (C1)** and an 11e mission/secondary/action pack (C2) — the
   only items that need external content rather than code.

A pragmatic landing order: **1 → 2 → 3 → 5 → 4 → 6** (enable + parity-test first, then the
highest-impact correctness gap, then the cheap wiring/flag fixes, then UI, then content).

---

## 11. Fixes applied (2026-06-23)

The following gaps were fixed and validated live via the MCP bridge (game running at
edition 11, asserting behavior through `execute_script`/screenshots; 10e re-checked
unchanged). Each is edition-gated so the shipped 10e default is byte-unchanged.

| ID | Fix | Validation |
|---|---|---|
| **A0** | Rules edition is now player-selectable — a "Rules Edition" selector in the main menu, persisted in SettingsService, applied to `GameConstants.edition` at boot. | Screenshot: menu shows "11th Edition (beta)"; selecting it sets `GameConstants.edition=11`. |
| **A1** | Melee saves route through the 11e allocation path (groups + `[DEVASTATING WOUNDS]` one-model cap 24.10 + 06.02 MW priority); FightPhase sends human defenders to auto-resolve when auto-allocate is on (default). | Melee with a dev-wounds weapon now emits `save`+`devastating_wounds_11e` dice contexts (was 10e spillover). |
| **A2** | `[HAZARDOUS]` fails on 1-2 (was 1), 1 MW/fail (3 if all M/V) (was flat 3). | Infantry 1 MW/fail, vehicle 3 MW/fail, on a 1-2 band. |
| **A3** | Indirect fire uses the 11e unmodified fail band (6s to hit; 4+ if stationary + friendly spotter); 10e -1 gated off at e11. | Fail band 3 (stationary+spotter) / 5 (moving). |
| **A5** | `HIDDEN` keys off a maintained turn-stamp (`last_shot_idx`, set on real ranged attacks) = "did not shoot this/previous turn". | Stamp written at the 3 real shot-completion sites; gate reads it. |
| **A6** | Scout confirm-move uses the edition-gated 8" (was hardcoded 9"). | `_scout_min_enemy_distance_inches()` = 8 at e11. |
| **A7** | Emergency disembark uses the 11e hazard band (1-2 fail, 1 MW / 3 if M/V) + battle-shock. | 30-model unit: 12 MW from 6 ones + 6 twos (10e=6); battle_shocked set. |
| **A8** | `[CLEAVE X]` now adds melee dice (was registry-only). | `get_cleave_value`=1; `cleave_bonus_dice(1,16,true)`=3. |
| **A9** | `[HEAVY]` requires "no model moved >3"" (records `moved_max_inches`). | true@2", false@5", true@stationary, false@set-up. |
| **A10** | `[PSYCHIC]` melee weapons ignore hit-roll penalties. | psychic melee weapon detected; -1 stripped. |
| **A11** | Attacks vs an attached unit use the HIGHEST bodyguard Toughness across models. | T6 for a T4/T6 unit; T5 uniform. |
| **A12** | Ingress "no opponent DZ before round 3" ban enforced (caller now supplies the opponent zone). | rejection inside DZ at round 2; passes when zone omitted (proving prior inert). |
| **B6** | Leader+Support attach cap enforced in the deploy diff/network pipeline (max 2 e11 / 1 10e). | 3rd character rejected at e11 with the cap message. |
| **B7** | AIRCRAFT can only ingress-move (normal/advance/fall-back validators reject them at e11). | `unit_is_aircraft` true for an AIRCRAFT unit; guard added. |
| **B2** | FLY "take to the skies" UI toggle in the movement mode panel (FLY units, e11). | `_unit_can_fly` true for FLY / false for ground; folds `take_to_skies` into the move payload. |
| **B1** | Actions can now be **started** — a generic "Hold Position" action is registered and a "Start Action" button (Shooting phase) dispatches `START_ACTION` (gives up shooting; sets the 16.01 locks; completes end of turn). | `get_startable_actions` → `["hold_position"]`; start sets `performing_action`/`cannot_shoot`/`cannot_charge`; completes at end of turn; a real deployed unit (Shield-Captain) yields the startable action. |
| **A4** (10/10 reachable) | 11e core stratagem **effects** wired: Epic Challenge (`effect_precision_melee`), Smokescreen (`effect_cover`), Counteroffensive (`fights_first`) via `_apply_stratagem_effects`; Explosives + Crushing Impact (MW dice handlers, with a target); and the five phase-trigger stratagems (Command Re-roll, Insane Bravery, Rapid Ingress, Fire Overwatch, Heroic Intervention) via an edition-resolver that maps the canonical id → its `_11e` variant so the existing phase flows fire. | Flags/MW verified; resolver maps all 8 ids and `use_stratagem("command_re_roll")` at e11 succeeds, deducts CP, records `command_re_roll_11e`; `can_use("fire_overwatch")` reaches the 11e timing condition (not the edition gate). |
| **B8** (24.31 reserves→DZ UI) | Player-facing UI for the Scout *reserves* option: a Scout unit in Strategic Reserves now appears in the Scout-phase unit list (`[Reserves → DZ]`), and selecting it starts a deployment-style placement (`DeploymentController.is_scout_reserves_mode`, reusing the **normal** wholly-in-DZ validation) whose Confirm dispatches `SCOUT_RESERVES_DEPLOY`. Engine side already existed (`ScoutPhase.get_available_actions` → `SCOUT_RESERVES_DEPLOY`, `GameState.get_scout_reserve_units_for_player`) but had **no UI consumer**, so a player with scouts in reserve was never offered the set-up — exactly the reported bug. | Windowed scenario `iss067_scout_reserves_deploy_11e` (31/0): reserve scout listed → real list-select starts placement (`is_scout_reserves_mode`+`is_placing`) → 4 models placed wholly-in-DZ → real Confirm button deploys the unit (status `DEPLOYED` at the chosen positions). Screenshots show the `[Reserves → DZ]` row, the 4/4 placement, and the "Scout reserves deployed" toast. |
| **B8b** (reserve Scout skippable / handoff) | Follow-up to a re-report of "no option to set up reserve scouts": when the **AI** was the first scout player and held a reserve Scout, it could not resolve it and never handed off — locking the human out. Two `ScoutPhase` consistency bugs: (1) `_validate_skip_scout_move` only checked `scout_units_pending`, so `SKIP_SCOUT_MOVE` — though *offered* by `get_available_actions` for reserve scouts — was rejected, leaving the unit un-resolvable (AI loops; a human likewise can't skip); (2) `get_available_actions` offered `END_SCOUT_PHASE` counting only on-table pending, so it could be offered/ended while a reserve Scout was still pending. Both now count `scout_reserve_units_pending`, matching `_should_complete_phase`. | Windowed scenario `iss067_scout_reserve_skippable_handoff` (23/0): P2 (first) holds a reserve scout, `_should_complete_phase` is false, `SKIP_SCOUT_MOVE` now **succeeds**, the phase hands off to P1, and P1's reserve scout is still pending and listed (`[Reserves → DZ]`). Live MCP: AI `_decide_scout` → `SKIP_SCOUT_MOVE`, dispatch succeeds, active player → P1, P1 list shows the option. |

### Still open
- **A4 remainder** — Explosives/Crushing Impact still need an attacker-facing enemy-target prompt
  to be fully player-driven (they fire when a target is supplied via context/AI). The five
  phase-trigger stratagems reuse the proven 10e phase flows via the id resolver.
- **B3** — Surge moves work in-engine but are ability-triggered; no current datasheet ability
  triggers one, so there is nothing to surface yet.
- **B4** — End-of-turn coherency removal auto-picks (no player model-choice dialog; the auto-pick
  is rules-legal).
- **B5** — `[DEVASTATING WOUNDS]`/`[LETHAL HITS]` attacker choice prompts are default-only.
- **C1 / C2** — true 11e datasheet values and an 11e mission/secondary/action pack require
  external content (no code).


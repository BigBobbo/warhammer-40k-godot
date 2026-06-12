# PRD — Architecture Overhaul & 11th Edition Migration

This document describes the **target behavior** of the overhauled modules. It is the
spec that the fixes in `ISSUES.md` (especially Tier 3) are validated against. The
authoritative rules source is the uploaded 11th-edition core rules
(`warhammer40k_core_rules8.txt`); section numbers below (e.g. `05.03`) refer to it.
Where this PRD and that document disagree, the rules document wins.

## 1. Goals

1. **Play correct 11th-edition games** end-to-end (deployment → 5 battle rounds →
   scoring) for the existing armies (Orks, Space Marines, Adeptus Custodes), single
   player vs AI and multiplayer.
2. **One rules implementation** — the engine, the AI's evaluation, Mathhammer, and the
   UI previews all derive from the same rules code. A rules change is made once.
3. **Determinism as a property** — given the same initial state and action log (with
   seeds), any machine reproduces the identical game. Replay, undo, multiplayer
   validation, and golden-master testing all rest on this.
4. **Editability** — adding a weapon ability, stratagem, move type, or action is a
   registry/data addition with a focused hook, not an edit to a monolith.

## 2. Non-goals / out of scope

- New factions or datasheet content beyond converting the three existing armies.
- Codex/detachment rules beyond what already exists (faction abilities are ported, not
  expanded); Crusade/narrative play; points rebalancing.
- Visual overhaul, new art, sound. UI changes are limited to what the new rules require
  (allocation groups, shooting types, disembark modes, actions, coherency removal).
- Performance optimization beyond "no regressions noticeable in a 2,000-point game".
- Keeping 10th edition playable forever: the edition switch exists to de-risk migration
  (parity testing, incremental landing). Once the 11e suite is green and stable, the 10e
  paths may be removed. Mid-migration, only the migrated subsystems need to honor the
  switch.

## 3. Architectural contracts

### 3.1 Action pipeline (single mutation gate)
- Every in-game change to `GameState` flows: `submit_action(action)` → validate →
  resolve (rules code returns **diffs**, never mutates) → apply diffs → broadcast/log.
- Human UI, AI, network peers, replay, and tests are all clients of the same entry point.
- Every action that rolls dice carries (or is assigned at submit) an `rng_seed`; the
  seed used is recorded with the action in the log.
- Reverse diffs are captured at apply time; `undo` restores the exact prior state for
  any undoable action type (documented list).
- **Invariant (testable):** replaying a recorded log from the initial snapshot yields a
  bit-identical final state hash. Direct writes to `GameState.state` outside the
  pipeline are a lint failure (pre-game initialization whitelist excepted).

### 3.2 GameConstants & edition switch
- All rule distances/thresholds (engagement range, coherency, detection range, ingress
  distances, pile-in/consolidate 3", etc.) come from one module, parameterized by
  `edition` (10 → legacy values, 11 → values in this PRD). No rule literal appears
  inline in phases/controllers/AI.

### 3.3 Rules data
- Datasheets carry: M, T, Sv, InSv (optional), W, Ld (as a 2D6 target, e.g. `"7+"`), OC
  (int or `'-'`), keywords (including FRAME, MOBILE where applicable), structured
  abilities, structured weapon profiles.
- Weapon/unit abilities are structured entries `{id, x?, keyword?, threshold?}`
  validated against an `AbilityRegistry` at load time. Unknown ids fail the load loudly.
  Keyword-scoped abilities (`[LETHAL HITS: VEHICLE]`) apply only against matching
  targets (24.01). Duplicated abilities don't stack; the controlling player selects the
  applying instance (24.02).

### 3.4 AttackSequence (04, 05)
Contract for resolving any unit's shooting or fighting:
1. **Select weapons** (04.01): shooting = any ranged weapons; fighting = exactly one
   melee weapon per model (+ all [EXTRA ATTACKS] weapons). [CLOSE-QUARTERS] sidearm
   exclusivity per 24.07.
2. **Select targets** (04.02): shooting targets must be visible, in range, unengaged
   (exceptions: close-quarters shooting, engaged MONSTER/VEHICLE per 17.03, indirect).
   Melee may split attacks across engaged units (declared up front).
3. **Resolve** (04.03): per target, gather attack dice for *identical attacks*
   (same BS/WS, S, AP, D, and applicable abilities) across weapons; resolve hit → wound
   → save → damage per batch.
4. **Hit/wound** (05.01-05.02): unmodified 1 fails, unmodified 6 crits; wound chart by
   S vs T; modifiers come exclusively from the ModifierStack; net roll modifiers capped
   at ±1.
5. **Saves & damage** (05.03-05.04): the **defender** partitions the target into
   allocation groups (one per CHARACTER model; one per distinct W/Sv/InSv combination
   for the rest), declares the order under the constraints (wounded non-CHARACTER group
   first; CHARACTER groups last; wounded CHARACTER groups before unwounded ones); save
   rolls are batch-rolled; damage applies lowest roll → highest against the current
   group; excess attacks are lost when the unit dies.
6. **Mortal wounds** (06.02): applied after all normal damage, one at a time, with the
   model-selection priority (wounded non-CHARACTER → non-CHARACTER → wounded CHARACTER
   → CHARACTER). [DEVASTATING WOUNDS] (24.10): crit wound → attack sequence ends, D
   mortal wounds, at most one model damaged per crit, excess lost.
7. `expected_damage(weapon, attacker, target, context)` — analytic expectation over the
   same logic, used by AI and Mathhammer. **Invariant:** Monte-Carlo of the resolve path
   converges to `expected_damage` (test with fixed tolerance).
8. The worked examples on rulebook pages 20-23 must be reproduced exactly by unit tests
   (boltgun/heavy-bolter batching; Celestine attached-unit allocation order).

### 3.5 ModifierStack
- Single query surface for: hit/wound/save roll modifiers and characteristic
  modifications (BS/WS, Sv, S, A, D, range, Move). Sources: terrain (cover worsens BS by
  1; Plunging Fire improves BS by 1), abilities (Stealth → cover), stratagems,
  battle-shock, faction states. Each modifier has scope (model/unit/attack) and duration
  (until end of phase/turn/battle, while-condition).
- Net dice-roll modifiers cap at ±1; characteristic modifiers are applied before roll
  modifiers; [PSYCHIC] may ignore hit modifiers (24.29); [IGNORES COVER] removes
  cover-sourced modifiers (24.18).

### 3.6 MoveTypes (03, 09, 11, 12, 18, 20, 21, 24.32)
- Every move is an instance of one template: `MAX DISTANCE / ELIGIBLE IF / BEFORE /
  WHILE / AFTER`, with mutually exclusive **modes** assessed in declared order. If end
  conditions fail, all models return to their starting positions and the unit has *not*
  been selected to move (03.01/03.02).
- Required instances: remain stationary, normal, advance, fall back (ordered retreat /
  desperate escape), charge, pile-in, consolidation (ongoing / engaging / objective),
  disembark (rapid / tactical / combat), emergency disembark, ingress, scout, surge.
- Universal WHILE rules: through friendly models, not through enemy bases (exceptions:
  desperate escape, FLY taking to the skies, MONSTER/VEHICLE vs non-M/V per 17.01),
  battlefield edge forbidden, terrain traversal per 13.06, coherency + not-on-models at
  end (03.01).
- FLY: optional "take to the skies" declaration per move — −2" (0 with HOVER), ignore
  vertical, move through everything (21.03).

### 3.7 Phase structure (07-12, 16)
- Battle round = start-of-round → player turn ×2 → end-of-round; turn = start step →
  Command → Movement → Shooting → Charge → Fight → end step. End-of-turn resolves, in
  order: non-mission rules (incl. coherency enforcement with model removal, action
  completion), then mission rules (07.03). Hooks for each step are registerable and
  deterministic in order.
- Command (08): both players gain 1 CP; battle-shock step tests battle-shocked and
  at-or-below-half-strength units (2D6 leadership roll vs Ld); success while shocked
  recovers. While battle-shocked: OC `'-'`, not a legal stratagem target for its
  controller, cannot start/complete actions.
- Shooting (10): per-unit **shooting type** selection — normal / assault / close-quarters
  / indirect / snap (stratagem-granted) — each with its own eligibility and WHILE rules
  as specified; selecting any type makes the unit ineligible to start actions that phase.
- Charge (11): declare → roll 2D6 → select targets within 12" **and** within the roll →
  charge move must end engaged with all targets and no others; chargers gain Fights
  First until end of turn.
- Fight (12): global Pile In step (both players, active player first) → Fight step
  (alternate Fights First units, then remaining; pass rules per appendix pg 87; overrun
  fights for units whose targets died) → global Consolidate step (modes mandatory in
  order; engaging consolidation makes newly-engaged enemies fight).
- Actions (16): data-defined; eligibility/blocking exactly per 16.01; completion checked
  at the action's stated trigger; moving (except pile-in/consolidate) cancels.

### 3.8 Terrain, visibility, objectives (13, 14, 06.01)
- Terrain model: **areas** (bounded regions) containing **features** categorized
  exposed / light / dense, with heights. Movement gates per 13.06 (MOBILE, 2" sections,
  vertical cost, surface end-of-move rules, Solid 3" enclosure).
- Visibility: visible vs **fully visible** (06.01); Obscuring areas block LoS when every
  line crosses one (13.10); Solid blocks LoS through enclosed gaps ≤3" from ground
  (13.11); **Hidden** models (INFANTRY/BEASTS/SWARM in a dense-containing area, no
  ranged attacks this or previous turn) visible only within 15" detection (13.09);
  Lone Operative = 12" visibility + indirect protection (24.24).
- Cover: a unit with benefit of cover **worsens the attack's BS by 1** (13.08);
  Plunging Fire improves it by 1 (22.05). The pg 51 worked examples are acceptance
  tests.
- Objectives: terrain areas (or 40mm markers, 3" horiz / 5" vert); control = sum of OC
  in range, evaluated at the **end of each phase and turn**; **Secured** objectives
  persist control without presence until out-controlled (14.02-14.03).

### 3.9 Multiplayer & persistence
- Sync model: action replication with embedded seeds; peers resolve locally;
  post-action state hash compared; mismatch triggers logged resync (never silent
  divergence). Failed load-sync blocks play until resolved.
- Saves: `{schema_version, initial_snapshot, action_log, latest_snapshot}`; migration
  registry upgrades any older schema; fixtures per released schema version are load
  tested in CI.

### 3.10 AI
- The AI is a pipeline client: it selects among legal options enumerated by the same
  eligibility APIs as the UI, scores attacks via `expected_damage`, and submits actions.
  It holds no private copy of rules math. Caches are explicitly lifecycle-managed
  (cleared on load/turn-start by design).

## 4. Verification standard

- Engine modules: unit tests, including every worked example in the rules document that
  touches the module (these are the canonical fixtures).
- Anything player-facing: a windowed scenario over the MCP bridge per the project gate
  (`40k/tests/TESTING_METHODOLOGY.md`), driving the real UI.
- Refactors (Tier 1-2): golden-master action-log replays — identical final state hash
  pre/post change.
- Rules changes (Tier 3): scenario assertions against this PRD + the rules document;
  deltas from 10e behavior are expected and reviewed, not accidental.

## 5. Open questions (resolve before the affected issue starts)

1. **Edition coexistence horizon** — keep a playable 10e mode after 11e ships, or
   delete (recommend delete once stable; affects how much dual-path code ISS-041/050
   carry). Owner: product (you).
2. **True 11e datasheet values** — converted armies will carry 10e-derived stats with
   `needs_11e_review` flags (real 11e datasheets aren't in the uploaded core rules).
   Decision needed on sourcing official 11e datasheet values vs. playing with
   approximations. Affects ISS-037 acceptance.
3. **Mission pack** — 11e missions/secondaries (and most Actions) live outside the core
   rules. Until a mission source is provided, keep current missions mechanically ported
   (control checks per 14.02) with the example action as the only fixture. Affects
   ISS-055/057 scope.

# `wh40k_ai_plan` v1 — the AI plan format

A **plan** is a JSON artifact that tells the AI, for one specific army list on
one specific deployment map, (a) exactly how to deploy and (b) a high-level
intent for each unit for the rest of the game.

It is the same artifact however it was produced — hand-written, recorded by the
in-game Plan Editor, or generated offline. There is no separate authoring
format.

Two things a plan is **not**:

- **A script.** Every part of a plan is an *intent with a fallback chain*. A
  placement that will not validate is repaired, and if repair fails that one
  unit deploys via the AI's normal column formula. An earmark that cannot apply
  is ignored. A plan must be *unable* to produce an illegal game state.
- **A generalisation.** Plans are keyed to a specific list on a specific
  deployment (optionally a specific terrain layout). The fallback for "no plan
  matches" is simply the AI's current behaviour.

Related files:

| File | Role |
|---|---|
| `40k/scripts/PlanValidator.gd` | static validator (`validate_plan`, `coverage`, geometry helpers) |
| `40k/tests/unit/test_plan_validator.gd` | headless test suite for the above |
| `40k/tests/fixtures/ai_plans/` | test fixtures — **never** listed in the player-facing plan browser |
| `40k/data/ai_plans/` | shipped plans |
| `user://ai_plans/` | player-authored plans |

---

## Terminology: "earmark" vs "intent"

**`earmark`** is the word in the schema, in code, in logs and in decision
records. **"Intent"** is the player-facing word used in UI copy only (the
*Intent Painter*). They mean the same thing. Do not introduce a third word.

---

## Annotated example

Real `recon_stomps` unit ids throughout. This is a trimmed version of
`40k/tests/fixtures/ai_plans/fixture_recon_stomps_rich.json`.

```jsonc
{
  "format": "wh40k_ai_plan",          // required, exact
  "version": 1,                        // required, must equal 1
  "name": "Recon Stomps — Hammer & Anvil",   // required, non-empty
  "description": "Grots on the home objective, Stormboyz screen, Stompa mid.",
  "author": "roberto",

  // --- What game this plan is for -------------------------------------
  "keys": {
    "army_file": "recon_stomps",              // required. Army list basename.
    "detachment_hint": "Speedwaaagh!",        // optional. Used by fallback matching
                                              //   when meta.game_config is empty.
    "deployment_zone_id": "hammer_anvil",     // required. Must resolve to
                                              //   res://deployment_zones/<id>.json
    "terrain_layout_id": "take_and_hold_vs_purge_the_foe_3",
                                              // optional; "" = matches any layout
                                              //   (a weaker match than an exact one)
    "mission_id": ""                          // optional, reserved
  },

  // --- How to deploy ---------------------------------------------------
  "deployment": {
    // The order the AI puts units down in, on its own alternating turns.
    // Units not listed here deploy AFTER the listed ones, via the formula.
    "order": ["U_GRETCHIN_A", "U_STORMBOYZ_A", "U_STOMPA_A"],

    "placements": [
      {
        "unit": "U_STORMBOYZ_A",       // required. ARMY-FILE UNIT ID.
        "unit_name": "Stormboyz",      // optional. Degradation path only (see below).
        "role_fallback": "screen",     // optional. Degradation path only.
        "models_inches": [             // required, >= 1 model.
          [10.5, 12.0],                //   board INCHES, PLAYER-1 FRAME.
          [11.5, 12.0]                 //   Model order matches the unit's model order.
        ],
        "anchors": {                   // optional, RECORDED ONLY — never resolved in v1.
          "nearest_objective": "obj_home_1",
          "depth_from_zone_edge_in": 4.0,
          "nearest_terrain_piece": "area-large-2"
        }
      }
    ],

    // Units held in Reserves. THIS LIST IS THE SINGLE SOURCE OF TRUTH for
    // reserves — a RESERVE_UNTIL earmark that disagrees with it is an ERROR.
    "reserves": [
      { "unit": "U_STORMBOYZ_B", "arrival_round": 2 }   // arrival_round in 2..3
    ],

    // Declared in the FORMATIONS phase, not the deployment phase.
    "embarkations": [
      { "unit": "U_GRETCHIN_B", "transport": "U_STOMPA_A" }
    ],
    "attachments": [
      // Must be a pairing the game can make — see the formations section.
      { "character": "U_DEFFKILLA_WARTRIKE_A", "bodyguard": "U_WARBIKERS_C" }
    ]
  },

  // --- What each unit is FOR ------------------------------------------
  "earmarks": [
    { "unit": "U_GRETCHIN_A", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1" },
    { "unit": "U_WARBIKERS_C", "verb": "PUSH_CENTER" },
    { "unit": "U_STORMBOYZ_A", "verb": "SCREEN" },
    { "unit": "U_STORMBOYZ_B", "verb": "RESERVE_UNTIL", "round": 2 },
    { "unit": "U_DEFFKILLA_WARTRIKE_A", "verb": "HUNT_CHARACTERS" }
  ],

  // --- Optional AI parameter overrides --------------------------------
  "profile_fragment": { "parameters": {}, "rules": [] }
}
```

---

## The verb table — exactly five verbs

| Verb | Extra fields | Meaning | Mechanism |
|---|---|---|---|
| `HOLD_OBJECTIVE` | `target` (objective id, **required**) | Sit on this objective | Additive bonus for that (unit, objective) pair in the objective-assignment score |
| `PUSH_CENTER` | — | Contest the middle | Same-shaped bonus toward the central/mid objectives |
| `SCREEN` | — | Body-block for the rest of the army | Withheld from the objective passes so the unit falls through to the existing screening pass |
| `RESERVE_UNTIL` | `round` (2 or 3, **required**) | Arrive from Reserves on this round | Consumed at FORMATIONS / deployment; UI sugar over `deployment.reserves` |
| `HUNT_CHARACTERS` | — | Prefer enemy CHARACTERs | Additive term in the shooting / charge / fight per-attacker target scorers |

`TRADE` is **rejected** by the validator with "reserved for v2". It is not
implementable today: there is no per-unit parameter mechanism to express it, and
a verb that quietly does nothing is worse than no verb.

Any other verb is rejected as unknown. **The vocabulary is closed.** Adding a
sixth verb means adding the mechanism that makes it real, in the same change.

### Earmarks are priors, not orders

An earmark biases the AI's existing machinery; it never overrides legality or
forces a move. It is also **released** once the unit is too badly damaged to do
its job (below `PLAN_EARMARK_RELEASE_AT` of its starting strength) — the release
is logged once, and the unit rejoins normal decision-making.

---

## The coordinate frame rule (the one that bites)

> **Plan coordinates are ALWAYS authored in the player-1 zone frame.**

`models_inches` is in board inches on the 44" × 60" board, origin top-left,
using the **player-1** deployment zone.

A consumer seated as **player 2** must transform every placement by the 180°
board rotation before using it:

```
[x, y]  ->  [44 - x, 60 - y]
```

Skip this and every seat-2 placement fails the "wholly within your own zone"
deployment check, the plan silently degrades to the formula, and any
plan-vs-plan measurement quietly measures nothing.

All six shipped deployment zones are exact point reflections of each other, so
the transform always lands legally —
`test_plan_validator.gd::test_shipped_zones_are_point_symmetric` asserts this
for every entry in `DeploymentZoneData.DEPLOYMENT_TYPES`. The validator does not
assume it: it checks each placement in **both** frames and rejects any plan that
would not survive the mirror.

Pixels vs inches: plans are inches. Conversion is `Measurement.PX_PER_INCH`
(= 40.0) in UI/board code, `AIDecisionMaker.PIXELS_PER_INCH` (= 40.0) inside
AIDecisionMaker. Never a stray `40.0` literal.

---

## How units are referenced (and how that degrades)

`"unit"` is the **army-file unit id** (`U_STORMBOYZ_A`). Ids are authored,
stable, and survive into `GameState.state.units` verbatim.

Unit *names* are **not** unique — `recon_stomps` carries four units named
"Stormboyz" and four named "Warbikers" — so names cannot be the key.

When a plan references an id the current army does not have (the player edited
the list), `PlanValidator.coverage()` resolves it in this order:

1. **exact id match** — no warning;
2. **`unit_name` matching exactly one army unit** — warning. If the name is
   ambiguous, name matching is *refused* rather than guessed;
3. **`role_fallback`** — warning; the consumer degrades to role behaviour;
4. **unmatched** — warning; that entry is ignored.

None of these are errors. A plan for a slightly-edited list still applies to the
units it can still identify.

### The `_P<player>` mirror suffix

When **both seats pick the same army list**, the two copies' unit keys would
collide, so `ArmyListManager` re-keys the second copy with a deterministic
`_P<player>` suffix (`ArmyListManager.gd:333-346`): player 2's Gretchin is
`U_GRETCHIN_A_P2`, not `U_GRETCHIN_A`.

A plan is authored against the *army file*, so it always says `U_GRETCHIN_A`.
Every consumer must therefore look through the suffix:

- `PlanManager.resolve_unit_id(plan_unit_id, player, units)` — plan id → the id
  this game actually uses for that player. It tries the **suffixed form first**,
  because in a mirror match both forms exist and the plain one belongs to the
  *other* player.
- `PlanManager.units_for_player(snapshot, player)` — the player's units re-keyed
  back to army-file ids, for anything that wants to work in plan space.

Mirror matches are the simulator's headline case, so this is not an edge case.

---

## Validation

`PlanValidator.validate_plan(plan, army := {})` returns

```gdscript
{ "valid": bool, "errors": Array[String], "warnings": Array[String], "coverage": Dictionary }
```

Passing `army` (an army-list dict, a GameState snapshot, or a bare
`{unit_id: unit}` map) additionally enables coverage and the reserves caps.

**Errors** (plan is rejected):

- wrong/missing `format`, non-integer or non-1 `version`, empty `name`
- missing `keys.army_file` / `keys.deployment_zone_id`
- `deployment_zone_id` or `terrain_layout_id` that does not resolve to a file
- a placement with no `models_inches`, or a model position off the board
- a placement with **no** model inside the player-1 zone polygon
- a placement whose seat-2 transform lands **no** model inside the player-2 zone
- duplicate entries (same unit placed twice, ordered twice, earmarked twice)
- a unit that is both placed on the board and declared in reserves
- `arrival_round` outside 2–3
- a `RESERVE_UNTIL` earmark that is absent from `deployment.reserves`, or that
  names a different round than the reserves list does
- an unknown verb; `TRADE`; `HOLD_OBJECTIVE` without a `target`;
  `RESERVE_UNTIL` without a `round`
- reserves exceeding the 50% points cap or the 50% unit-count cap (mirrors
  `FormationsPhase.gd`; a character attached to a reserved bodyguard counts
  toward the points cap, exactly as the phase computes it)

**Warnings** (plan is still valid):

- a placement partly outside the zone polygon (the consumer will repair or fall
  back for that unit)
- an ordered unit with no placement, or a placement not in `order`
- every coverage degradation listed in the section above

### CI

Shipped plans' `profile_fragment`s inherit `wh40k_ai_profile` semantics
verbatim, including its documented traps (silent-zero multiply, unknown
conditions passing). Run `tools/ai_lab/validate_profile.py` over any fragment
you ship.

---

## Matching: which plan applies to this game?

Storage and matching live in `PlanManager`; consumption lives in
`AIDecisionMaker`. Matching is **seat-agnostic** — the seat-2 coordinate
transform is consumption's job, not matching's.

Ranked best-first:

1. army + zone + layout all match exactly;
2. army + zone match, plan's `terrain_layout_id` is empty (wildcard);
3. no match → `{}` → the AI uses its normal behaviour.

Ties break deterministically (alphabetically by plan name), and the choice plus
its reason are written to the debug log.

## How the AI consumes a plan (deployment)

`AIDecisionMaker` owns consumption, mirroring how it owns profile application
while `ProfileManager` owns profile storage:

```gdscript
AIDecisionMaker.set_player_plan(player, plan)   # after AIPlayer.configure()
AIDecisionMaker.clear_player_plan(player)
AIDecisionMaker.get_player_plan(player)
AIDecisionMaker.plans_enabled()                 # PLANS_ENABLED > 0.5
```

**Apply a plan AFTER `AIPlayer.configure()`.** `configure()` calls
`clear_all_profiles()`, which also clears plans — a plan is per-game
configuration exactly like a profile, and carrying one silently into the next
game is worse than losing it. With no plan explicitly set, the AI asks
`PlanManager.find_plan_for()` **once per player per game**.

On each of the AI's own deployment turns:

1. **Order.** Instead of taking `deploy_actions[0]`, the AI takes the action for
   the earliest `deployment.order` unit that is still undeployed. Alternation
   with the opponent, defender-first and the TITANIC skips are phase-controlled
   and untouched. Units the plan does not list deploy afterwards, via the
   formula.
2. **Placement.** `models_inches` → pixels (`PIXELS_PER_INCH`), mirrored first
   when the AI is seated as player 2.
3. **Legality.** The placement is checked against everything `DeploymentPhase`
   will check, using the *same* shape-aware helpers so it is neither stricter
   nor looser: wholly within the zone POLYGON (not its bounding rectangle —
   `crucible_of_battle` is a triangle), no overlap with deployed models or
   within the formation, clear of walls the unit cannot cross, on the board, and
   in 11e coherency (2" neighbour + 9" envelope).
4. **Repair, then fall back.** A placement that fails goes through
   `_resolve_formation_collisions`; if the repaired version still fails, that
   *one unit* deploys via the formula. Every path ends in a valid action or a
   legal skip — never a stall.

## How the AI consumes a plan (formations)

`reserves`, `embarkations` and `attachments` are **FORMATIONS-phase** decisions,
not deployment ones. When a plan is active `_decide_formations` emits the plan's
declarations first, in the phase's own order — attach, embark, reserve — and
stops once they are all made, leaving anything the plan does not mention to the
AI's existing logic (a plan that pairs one character still lets the AI attach
the rest).

Three rules worth knowing:

- **The plan's `reserves` list is the last word.** While a plan is active the
  formula's own reserves evaluation is suppressed, so a plan whose `reserves` is
  `[]` really does start everything on the table. Only a plan with no `reserves`
  key at all leaves reserves to the AI.
- **An over-cap plan is trimmed, not rejected.** Entries are kept in plan order
  until the 50% points or 50% unit cap would break, and the rest are dropped
  with a log line — so the trim is deterministic and reviewable.
- **Attachments must be pairings the game can actually make.** The eligible
  leader/bodyguard pairs come from `data/40kdc/leaderAttachments.json`; an
  attachment that is not in there simply never matches an available action and
  falls through to the AI's own pairing. The validator does **not** check this
  today — see PM-F2 in `.llm/plan-maker-todo.md`.

### Games that are already past FORMATIONS

The shipped predeploy saves start at DEPLOYMENT with `meta.formations_declared`
already set, so the declaration path never runs for them. Reserves still get in:
during deployment the AI emits `PLACE_IN_RESERVES` for any plan reserve still
sitting undeployed — the action `DeploymentPhase` keeps in validate/process "as
a safety-net for AI fallback" (`DeploymentPhase.gd:1390-1394`), and which still
enforces the caps.

Embarkations and leader attachments have no such retrofit — they are
formations-only — so a plan that asks for them in a fixture-era game logs once
and skips them.

### Measuring adherence

Every deployment decision record carries a `source` in its context:

| `source` | Meaning |
|---|---|
| `plan:<name>` | placed/declared from the plan (deployment records add `seat_mirrored` and `repaired`; formations records add a `declaration` of `attachment` / `embarkation` / `reserves`) |
| `formula_fallback` | a plan was active but did not cover, or could not legally place, this unit |
| `formula` | no plan applied at all |

Counting `plan:` records per seat is how a run reports adherence — and a seat-2
adherence of zero is the signature of a missing coordinate transform.

### Benchmarking a plan

`AIBenchmarkRunner` takes plans exactly like profiles:

```bash
BENCH_P1_PLAN=40k/tests/fixtures/ai_plans/fixture_custodes_lions_crucible.json \
BENCH_P2_PLAN=40k/tests/fixtures/ai_plans/fixture_custodes_lions_crucible.json \
BENCH_SEED_BASE=5001 bash 40k/tests/run_ai_benchmark.sh 2 mirror_custodes_2000_predeploy
```

(or `--bench-p1-plan=` / `--bench-p2-plan=` directly). A plan that cannot be
loaded, or that fails validation, is a **fatal** error rather than a warning:
otherwise the arm would quietly play with formula deployment and report a
perfectly ordinary result, and the A/B would measure nothing while looking like
a null effect. The plan path, its sha256 and its name are stamped into both the
result JSON and the game record's provenance.

## Enabling / disabling

Plans are gated on the numeric AI parameter **`PLANS_ENABLED`** (default `1`),
which lives inside the `parameters` object of `40k/data/ai_config.json` and is
read via `AIDecisionMaker.get_param("PLANS_ENABLED", 1.0) > 0.5`. Top-level keys
in that file are dead — the loader reads `parameters` only.

Plans apply at **Normal, Hard and Competitive**. Easy ignores them by
construction (EASY short-circuits to random decisions before any plan hook).

## Profile fragment merge order

`profile_fragment` is applied through the same per-player profile layering as a
standalone AI profile. Precedence, highest first:

1. rule overrides
2. an explicitly assigned per-player profile
3. the plan's `profile_fragment`
4. global `ai_config.json` `parameters`
5. the code default passed to `get_param`

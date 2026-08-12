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

**Writing for players?** `40k/docs/AI_PLANS_GUIDE.md` is the player-facing
version of this document — same feature, no schema.

---

## The whole loop, in pictures

Every image is a live capture from a windowed scenario run, not a mock-up.

| Step | What it looks like | Capture |
|---|---|---|
| 1. Open the sandbox | Main menu gains **Plan Editor** + its own zone picker | `docs/evidence/pm4_main_menu_plan_editor.png` |
| 2. Deploy | The session **stays open** at the end of deployment instead of advancing | `docs/evidence/pm4_plan_editor_held_open.png` |
| 3. Save | `Save as Plan` writes it to `user://ai_plans/` and refuses an invalid plan in place | `docs/evidence/pm5_save_dialog.png`, `pm5_saved_toast.png` |
| 4. Say what units are FOR | The INTENTS panel and the non-fading board badges | `docs/evidence/pm6_intents_painted.png` |
| 5. Hand it to an AI seat | Per-seat **AI Plan** picker, filtered by army and zone | `docs/evidence/pm7a_plan_dropdowns.png` |
| 6. Watch it deploy | Deployment driven by the plan | `docs/evidence/pm7a_deployment_from_plan.png` |
| 7. Manage what you have | The plan browser, and delete-behind-a-confirm | `docs/evidence/pm7b_plan_browser.png`, `pm7b_delete_confirm.png` |
| 8. Measure two plans | Battle Simulator: configure, then the results table | `docs/evidence/pm9_configured.png`, `pm9_results_table.png` |
| 9. Shipped content | The picker offering a shipped plan; plan seat vs formula seat on one board | `docs/evidence/pm10_shipped_plan_selected.png`, `pm10_plan_vs_formula_deployment.png` |
| 10. A game against it | Human seat vs the plan-driven AI | `docs/evidence/pm10_standin_human_vs_plan_ai.png` |

Two of those pictures are worth looking at for what went *wrong*, because they
are the honest half of the feature:
`pm10_plan_vs_formula_deployment.png` shows **HOME 1 Uncontrolled** at the end
of deployment — the objective the plan is built around, empty, because the AI
loaded the Gretchin into the Stompa (PM-F5). The stand-in capture shows the
same thing in a human game.

---

## Authoring: the Plan Editor sandbox (PM-4)

The **Plan Editor** button on the main menu opens a solo planning session
instead of a game. Pick the Player 1 army and — from the editor's own
picker, next to the button — the deployment zone the plan is being written
for. (The zone needs its own control because at 11th edition the *game's*
zone is derived from the Force Disposition matchup plus the terrain variant
and is shown as a read-only label; a plan is keyed on `deployment_zone_id`,
so the author has to be able to choose it directly.)

What the session does:

| Step | Behaviour |
|---|---|
| Flag | `plan_editor: true` inside `meta.game_config` — the canonical read is `PhaseManager.is_plan_editor_session()` |
| Seats | Target army is **Player 1** (plans are authored in the P1 frame; the AI mirrors for seat 2). Player 2's units are deleted right after army load |
| FORMATIONS | Runs for real for the target army so reserves / embarkations / attachments can be recorded. The empty Player 2 seat is auto-confirmed |
| ROLL_OFF | Auto-resolved with no dialog; the winner's choice is picked so **Player 1 is the Defender** and therefore deploys first |
| DEPLOYMENT | The normal deployment UI, with the hotseat "pass the device" curtain suppressed (there is only one author) |
| End of deployment | `PhaseManager._on_phase_completed` suppresses the advance, so the session **stays** in DEPLOYMENT with the board intact. All three deployment-completion emitters route through that one guard |
| Exit | The `PLAN EDITOR` banner above the board carries an **Exit to Menu** button |

Committed units cannot be un-deployed in v1 — the story for a mistake is
exit and restart. Painting earmarks onto a recording is PM-6.

Windowed proof: `40k/tests/scenarios/sp/pm4_plan_editor_session.json`.

### Save as Plan — the recorder (PM-5)

The banner's **Save as Plan** button reads the laid-out board back out through
`40k/scripts/PlanRecorder.gd` and writes it to `user://ai_plans/`.

| Plan field | Recorded from |
|---|---|
| `keys` | `PlanManager.resolve_game_identity(1, state)` — army file, zone, layout, detachment — plus `meta.game_config.mission` |
| `deployment.order` | `state.phase_log`, in dispatch order. The editor holds DEPLOYMENT open, so the log is never committed to history and still holds every action of the phase. Placed units the log does not mention are appended after |
| `deployment.placements` | `units[*].models[*].position`, px ÷ 40 → inches, rounded to 2dp, in model order |
| `deployment.reserves` | `status == IN_RESERVES`. The game stores no arrival round, so a recording defaults to `2` |
| `deployment.embarkations` | `units[*].embarked_in` — set by both the Formations declaration and Deployment's `COMPOSITE_DEPLOY` |
| `deployment.attachments` | `units[*].attached_to`, same two sources |
| `earmarks` | left `[]` — PM-6 fills them in |

Rules the recorder follows:

- **Only the author's seat.** Player 2 is not in an editor session anyway, but
  the filter is explicit so the same function works on a normal game state.
- **A unit is recorded once.** A reserved / embarked / attached unit is emitted
  in its own list and NOT as a placement — an attached character has no board
  position of its own, and "both placed and reserved" is a validator error.
- **A half-placed unit is skipped entirely.** `models_inches` is indexed by
  model number on consumption, so a gap would mis-seat the unit.
- **An unresolvable `terrain_layout_id` is dropped**, not emitted. `""` means
  "matches any layout" and is legal; an id with no file behind it is an error
  that would make the plan unsaveable.
- **`anchors` are derived and recorded only** (never resolved in v1), all
  measured from the unit's centroid: nearest objective id, distance to the
  nearest edge of the player-1 zone, nearest terrain piece id.

`PlanManager.save_plan` refuses an invalid plan, so the dialog stays open and
prints the validator's errors rather than closing over them. Validation runs
against the *live* army (`PlanRecorder.own_army`), which is what makes the
coverage and 50%-reserves-cap checks meaningful.

Proof: `40k/tests/unit/test_plan_roundtrip.gd` (record → consume for seat 1 and
seat 2) and `40k/tests/scenarios/sp/pm5_record_and_save_plan.json` (the whole
path from the menu, ending in a live round trip off the saved file).

### The intent painter (PM-6)

Once the editor's board is fully laid out, an **INTENTS** panel appears
(`40k/scripts/IntentPainter.gd`). Pick a unit, pick one of the five verbs, and
the unit gets a badge on the board (`40k/scripts/IntentOverlay.gd`).

- **`HOLD_OBJECTIVE` is bound by clicking the objective.** `ObjectiveVisual` is
  a plain `Node2D` with no input handling, so the painter hit-tests the
  objective positions in `state.board.objectives` itself, with a tolerance of
  the marker radius plus 20px.
- **The badge's line** goes to the bound objective for `HOLD_OBJECTIVE` and to
  the mission's *central* objective for `PUSH_CENTER` — which is what that verb
  actually biases toward (`AIDecisionMaker._plan_central_objective_ids`).
- **`RESERVE_UNTIL` overrides the board.** The author is saying the unit starts
  in Reserves whatever it is doing in the sandbox, so the recorder moves it into
  `deployment.reserves` with the painted round and drops its placement. The two
  MUST agree — the validator rejects a `RESERVE_UNTIL` whose unit is not in the
  reserves list, or is listed with a different round.
- **Attached characters are not listed**: a character joined to a bodyguard
  fights as part of that unit and is not separately steerable.

Earmarks live in `meta.plan_earmarks` in exactly the shape the plan uses, and
are written through `PhaseManager.apply_state_changes` rather than poked
straight into `GameState.state` (ISS-001). `PlanRecorder` reads them back at
save time, dropping any entry whose unit no longer exists on that seat.

The overlay is deliberately NOT built on `AIMovementPathVisual` (2.5s hold + 1s
fade) or `AIUnitHighlight` (a text-less pulsing ring). An intent badge is a
persistent annotation, so it has its own non-fading lifecycle; only the drawing
style is borrowed.

Proof: `40k/tests/scenarios/sp/pm6_paint_intents.json`.

---

## Assigning a plan to an AI seat (PM-7a)

Each AI seat in the main menu gets an **AI Plan** dropdown, under that seat's
army row. It offers every saved plan whose `keys.army_file` matches the seat's
army; a plan for a different `deployment_zone_id` is still listed but labelled
with the zone it was written for (it would not place legally here, and every
unit would degrade to the formula), and an invalid plan is labelled `(invalid)`.

Three values reach `meta.game_config.player<N>_plan`:

| Menu choice | Config value | Effect |
|---|---|---|
| Auto (best match) — default | `""` | The seat is left unset, so `AIDecisionMaker._resolve_plan_for` runs its one auto-match (`PlanManager.find_plan_for`) at decision time |
| None (no plan) | `"none"` | `AIDecisionMaker.suppress_player_plan()` — no plan **and** no auto-match |
| a plan | its path | `AIDecisionMaker.set_player_plan()` with the loaded file |

Two ordering rules, both load-bearing:

- **Install AFTER `AIPlayer.configure()`.** `configure()` calls
  `clear_all_profiles()`, which clears plans too — anything installed before it
  is discarded. Same reason `player<N>_ai_profile` is applied there.
- **"None" is not `set_player_plan(player, {})`.** That call routes to
  `clear_player_plan()`, which also clears the attempted-match flag, so the seat
  auto-matches a plan on its very first decision and "None" silently becomes
  "Auto". `suppress_player_plan()` burns the flag instead. The PM-7a scenario
  catches exactly this: it sets seat 1 to None and asserts **zero**
  plan-sourced deployment records against seat 2's twelve.

Because the deployment zone at 11e is derived from the Force Disposition
matchup plus the terrain variant, the dropdown is repopulated from
`_refresh_derived_mission_display` (which every zone-changing path routes
through) and from each army dropdown's `item_selected` — not from the
deployment dropdown, which is invisible and only ever changes programmatically.

Proof: `40k/tests/scenarios/sp/pm7a_assign_plan_from_menu.json`.

### The plan browser (PM-7b)

The **AI Plans** button opens `40k/dialogs/PlanBrowserDialog.gd`: one row per
plan on the search path, with the validation badge coming straight from
`PlanManager.list_plans` (which validates every entry it returns) — `OK`,
`OK, N note(s)` for warnings, or `N problem(s)` in red.

`user://` plans can be renamed (`PlanManager.rename_plan` rewrites `name` and
moves the file to the new slug, refusing an empty name or one already taken)
and deleted behind a confirmation. Shipped `res://` plans are listed and usable
but the two buttons are **disabled with the reason shown**, not hidden — in an
export they live inside the PCK and there is no file to rewrite or remove.
`rename_plan` and `delete_plan` both enforce that independently of the UI.

Closing the browser refreshes the per-seat plan pickers, so a plan just deleted
cannot still be selected for a game.

Proof: `40k/tests/scenarios/sp/pm7b_plan_browser.json`.

---

## Comparing two plans: the simulator (PM-8b)

`PlanSimulator` (autoload) runs N seeded AI-vs-AI games back to back in one
process — same mission, zone, layout and armies, plan A against plan B (either
may be "no plan") — and reports who won, by how much, and how much of each plan
the AI actually followed.

```gdscript
PlanSimulator.start({
    zone_id = "crucible_of_battle", layout_id = "take_and_hold_mirror_1",
    mission_id = "take_and_hold", army1 = "custodes_lions", army2 = "custodes_lions",
    plan1 = "user://ai_plans/mine.json", plan2 = "",   # "" / "none" = no plan
    games = 5, seed_base = 1000, difficulty = 1,
})
# signals: run_started(total) game_finished(i, result) run_finished(summary) run_cancelled(summary)
```

An **autoload**, because each game changes scene into `Main.tscn` — a node owned
by the menu scene would be freed on the first game.

### The reset list is not optional

The PM-8a spike
(`40k/tests/bench_baselines/2026-08-11_pm8a_inline_reset_spike.md`) established
that consecutive in-process games are viable *only* with the full reset in
`_reset_between_games`. With the obvious three entries
(`StratagemManager` / `UnitAbilityManager` / `PhaseManager`), two same-seed
games diverged. Every additional entry was earned by a measured divergence:

| Entry | What it was hiding |
|---|---|
| Quiesce the AI **before** teardown | AIPlayer kept acting while the next game was assembled; the later `configure()` then wiped the evidence |
| `FactionAbilityManager`'s per-game dictionaries | **The determinism-breaker.** No reset entry point, and fixed-shape `{"1":…,"2":…}` dicts whose *size* never changes, so a size fingerprint cannot see them leak |
| `PhaseManager._last_round_started` | `reset()` does not clear it |
| `MissionManager` lambda receivers | `Main._setup_objectives` connects lambdas capturing scene nodes to autoload signals; 105 ERROR lines in a 3-game run |
| `ActionLogger` / `GameEventLog` / `ReplayManager` | Unbounded growth, and both logs feed AI-visible context |
| **Seed the GLOBAL RNG** | `Array.shuffle()` / `randi()` / `randf()` do not use the seeding triple. A fresh process starts it from a fixed default — which is why two *processes* agreed — but the state carries over between in-session games |

Order matters too: quiesce, reset, *then* bootstrap. Resetting after the
bootstrap wipes what the bootstrap just populated.

`ReplayManager.auto_record_ai` is deliberately left **on**: the auto-recorded
replays are the only way to rewatch a simulated game. The cost is one replay
file per game.

Proof: `40k/tests/test_plan_simulator.gd` — a 2-game mirror run twice at the
same `seed_base`, asserting identical winners/margins/VP across runs, a
genuinely different game at a different seed, seat-2 plan adherence above zero,
and summary arithmetic that agrees with the rows.

### The Battle Simulator overlay (PM-9)

`PlanSimulatorUI` is an **autoload `CanvasLayer`**, for the same reason
`PlanSimulator` is an autoload: every game changes scene into `Main.tscn`, so a
menu-scene Control would be freed on the first game. The consequence is a
feature — the games play visibly underneath the panel.

Three things it is deliberately careful about:

- **The ETA is measured, never guessed.** It stays "unknown until the first
  game finishes" and is then driven by the observed seconds per game. Wall time
  varies enormously (the bench baselines are ~2.5 min/game Custodes and ~8 min
  Orks; a 3-unit list is ~15 s headless and ~30 s windowed), so any static
  estimate would be wrong most of the time. Pressing Run clears the previous
  run's measurement rather than presenting it as this run's estimate.
- **The results table is a view of the results file, not a second copy.** The
  scenario asserts every row's seed and VP, and the summary line, against the
  JSON `PlanSimulator` wrote to `user://plan_sim_results/`.
- **Closing returns to the menu.** After a run the scene underneath the overlay
  is a finished battle, not the menu, so `close()` performs the same teardown
  `Main._on_main_menu_requested` does and changes scene.

The game's own Game Over dialog is suppressed while a run is in progress
(`Main._show_game_over_dialog`): it is `exclusive` and `always_on_top`, so N
games meant N modal ceremonies covering the results table.

Proof: `40k/tests/scenarios/sp/pm9_simulator_run.json`, which runs the cancel
path and a full 2-game run.

---

## The shipped plans (PM-10)

Two plans ship in `res://data/ai_plans/` and are on `PlanManager`'s search
path, so they appear in the menu's AI Plan picker and in the plan browser with
`source: shipped` (read-only — see PM-7b).

| file | zone | terrain key | covers |
|---|---|---|---|
| `orks_recon_stomps_crucible.json` | `crucible_of_battle` | `take_and_hold_mirror_1` | 13 placed, 4 reserved, 2 attached |
| `orks_recon_stomps_hammer_anvil.json` | `hammer_anvil` | *(empty — any layout)* | 13 placed, 4 reserved, 2 attached |

13 placed + 4 reserved = all 17 units, deliberately: see "Cover the whole army"
below.

Both carry the same content: Gretchin on `obj_home_1` with a second mob
screening beside them, the Stompa leading Wazdakka and both Warbiker mobs up
the middle, two Stormboyz mobs screening, and two Stormboyz mobs plus both
Deffkopta units in Reserves for round 2. Each Deffkilla Wartrike is attached to
a 6-strong Warbiker mob — the only pairing `data/40kdc/leaderAttachments.json`
allows.

They are authored by `40k/tests/spikes/pm10_author_plans.gd`, which is worth
reading before hand-editing either file. Three things it does that hand
authoring gets wrong:

1. **Every placement is validated by `DeploymentPhase.validate_action` on a
   live board**, not by eye. A position that looks fine and is actually
   rejected does not fail loudly — the unit silently degrades to the formula.
2. **It rounds to 0.01" BEFORE validating**, so the coordinates checked are
   byte-for-byte the ones written to the file.
3. **It requires each model to sit wholly inside the SHIPPED zone polygon as
   well**, checked as "centre in the polygon and no polygon edge nearer than
   the base's bounding radius". This matters because of the next section.
4. **It keeps every unit inside the 9" coherency envelope and refuses to write
   a plan that does not** — which the phase alone will not catch. See below.

### Phase-validated is not the same as AI-accepted (the 9" envelope trap)

`AIDecisionMaker._plan_positions_legal` enforces 11e coherency — 2" to a
neighbour **and 9" to every other model in the unit** — unconditionally.
`DeploymentPhase._check_deployment_coherency` enforces it through the
edition-aware `AttackSequence.check_unit_coherency`, and the automated harness
pins `GameConstants.edition` to the legacy 10e baseline, which has no 9"
envelope.

So `phase.validate_action` will happily accept a placement the AI then throws
away. It happened: Gretchin Alpha was authored as an 11-model line **13.60"
across**, validated clean, and then fell back to the formula in *every*
measured game on *both* seats with only `did not validate and repair failed` in
the log. Seat-2 adherence was 5/11 before this was found. Filed as **PM-F4**.

If you hand-author or hand-edit a plan, check the widest pair in each unit.
The authoring script does it for you and refuses to write the file otherwise.

### The predeploy fixtures carry a stale crucible zone

`DeploymentZoneData.get_zones()` prefers `res://deployment_zones/<id>.json`
over its hardcoded fallback, and the crucible JSON was regenerated from the
40kdc 11e dataset. The `mirror_orks_*_predeploy` fixtures predate that
regeneration and have the OLD geometry baked into their saved `board`:

```
fixture board (what the deployment phase checks on a bench run):
  a 44x8 band plus a 24x6 centre step, obj_home_1 at (22, 4)
res://deployment_zones/crucible_of_battle.json (what a real game and
PlanValidator use):
  the triangle (0,0)-(44,30)-(44,0), obj_home_1 at (32, 14)
```

Loading a save restores `board.deployment_zones` from the save, so a bench run
on those fixtures plays a board no menu game can produce. The crucible plan is
therefore packed into the INTERSECTION of the two polygons — legal on the
fixture AND in a real game — at the cost of not being able to sit on both
versions of `obj_home_1` at once (it covers the fixture's, since that is where
it is measured; the `HOLD_OBJECTIVE` earmark still drives the unit to whichever
`obj_home_1` the live board has). Regenerating the fixtures is filed as
**PM-F3** rather than done here, because it moves a shared benchmark asset that
the neighbouring baselines were measured on.

### Cover the whole army

The crucible zone cannot hold this whole army on the board: the usable
intersection is about 410 sq in against roughly 330 sq in of base-plus-gap
area. The plans answer that with **Reserves**, not with partial coverage —
both Deffkopta units and two Stormboyz mobs come down on round 2 (410 of 2000
points and 4 of 17 units, inside the 50% caps), and everything else gets an
explicit placement.

Leaving a unit out of the plan entirely is the tempting shortcut and it is a
trap. A unit the plan does not cover is deployed by the FORMULA, in the
formula's own position — which may be exactly where a later planned placement
wants to be. Partial plans on a tight board eat themselves.

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

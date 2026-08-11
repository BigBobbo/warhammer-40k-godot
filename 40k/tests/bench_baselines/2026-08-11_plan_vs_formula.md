# PM-10 — plan vs formula: the first shipped plans, measured

**Date:** 2026-08-11
**Branch:** `claude/plan-maker-todo-w0syuf`
**Task:** `.llm/plan-maker-todo.md` → PM-10
**Fixture:** `mirror_orks_2000_predeploy` (gate: PASS, sha256 `140798d7ca0c`)
**Plan under test:** `res://data/ai_plans/orks_recon_stomps_crucible.json`
**Arms:** `plans_on.json` (PLANS_ENABLED 1) vs `plans_off.json` (PLANS_ENABLED 0)
**Difficulty:** 1 — **Normal**, the difficulty a player actually gets

**Question:** does an AI that follows a hand-authored plan score better than the
same AI running its deployment formula, and — separately, and more
importantly — does it *do what the plan says*?

---

## VERDICT

**PENDING — the paired A/B was still running when this file was committed.**
Everything else in this report is measured and final; the effect E, its se and
the per-game table land in the follow-up commit. Nothing below is a
placeholder: the adherence numbers, the three defects and the stall are all
from completed runs.

---

## The design, and why it is shaped this way

Both arms are handed **the same plan file, on both seats**. What swaps is the
profile: `PLANS_ENABLED` 1 on the candidate seat, 0 on the baseline seat. The
alternative — pass the plan to one arm only — would have made the two arms
differ by a command-line flag as well as by behaviour. Holding the plan
constant means the pair difference isolates *followed the plan* from
everything else, including the plan file itself.

`PLANS_ENABLED` is the single gate every plan consumer sits behind: deployment
order and per-model placement (PM-2a), formations reserves / embarkations /
attachments (PM-2b), and earmark bias (PM-3) all check it. Setting it to 0 is
therefore a complete revert to pre-plan behaviour with nothing else changed.

**The gate is per-seat, and that was verified rather than assumed.**
`AIDecisionMaker.plans_enabled()` calls `get_param()` with no player argument,
which looks global; `get_param` resolves per-seat via `_current_player`
(priority: rule overrides > player profile > global config > default). Reading
the code is not proof, so the separation was measured in two independent places
where one seat has the gate on and the other off:

```
bench, M1 arm (P1 plans_off, P2 plans_on):  P1 0 plan deployments, P2 10-12
windowed scenario (P1 plan, P2 None):       P2 0 plan records,     P1 9
```

Zero on the gated seat, double figures on the other, in the same process, in
both directions. The arm separation is real.

An **A/A arm** (`plans_off` on both seats, same plan file, same seeds) ran
alongside as a live harness guard: it must reproduce the fixture's structural
bias F, and a paired A/B whose implied F disagrees with it is not trustworthy.

---

## Power, stated before the numbers

The predeploy fixtures have a per-game margin sd of roughly **20 VP**. For a
paired design with `n` pairs the standard error of the effect is about
`sd / sqrt(2n)`:

| pairs | se (VP) | smallest effect a 2-se rule can call |
|---|---|---|
| 6 | ~5.8 | ~±11.6 VP |
| 12 | ~4.1 | ~±8.2 VP |
| 24 | ~2.9 | ~±5.8 VP |

**At 6 pairs this run can only detect an effect of roughly ±12 VP per game.**
A plan that is worth, say, 3 VP a game is completely invisible here and would
be indistinguishable from one worth nothing. That is a property of the run
size, decided before looking at the result, and it is why the primary gate for
PM-10 is *adherence*, not *effect*:

> **primary = zero stalls/errors + plan adherence ≥90% of covered units on both
> seats + before/after deployment screenshots. E is REPORTED with its se; "E not
> significantly negative" is a sanity check, not a success claim.**

A null E with high adherence is an acceptable — indeed expected — outcome. The
point of the plan feature is that the AI does something a person can predict
and recognise, not that it wins more.

---

## Results

**PENDING — see VERDICT.** The 18-game run (6 pairs x M1/M2 + a 6-game A/A
arm, Normal difficulty) was still in flight at commit time. What is already
known from it is the stall below, which came out of its first wave.

### Stalls

The primary gate includes **zero stalls**. It is not met, and the failure is
not in the plan:

```
seed 9001 (M1): stalled  round 1  "no progress for 90s at 1|1|41"
```

The action log of that game shows what happened, and which seat did it:

```
P1  Deployed Warbikers Alpha (durable_shooter, col 3, row 3)
P1  Deployed Warbikers (retry 1)
P2  Deployed Warbikers Gamma from plan 'Orks — Recon Stomps on Crucible'
P1  Deployed Warbikers Beta (durable_shooter, col 4, row 3)
P1  Deployed Warbikers (retry 2)
P2  Deployed Deffkilla Wartrike Beta from plan 'Orks — Recon Stomps on Crucible'
P1  Warbikers placed in reserves (fallback)
P2  Deployed Warbikers Delta from plan 'Orks — Recon Stomps on Crucible'
```

**P1 is the formula seat** (`plans_off` in the M1 arm) — it retries the same
Warbikers placement, gives up into reserves, and eventually the game makes no
progress for 90 seconds. The plan seat deploys cleanly through the whole
sequence. The same retry-until-fallback pattern is visible in the windowed
scenario's game log on the control seat ("*AND within 9" of every other model
in the unit (1 model(s) out of coherency.) — retry…*").

So this is a **pre-existing deployment-formula defect** in the same family as
PM-F1, surfaced by this run rather than caused by it — nothing in this task
changes AI code, and the seat that stalls is the one with plans switched off.
It is reported here as a gate failure regardless, because "the stall was
somebody else's fault" is not the same as "there were no stalls", and a stalled
game costs a whole pair.

---

## Adherence

**On the bench fixture, with the plan on both seats: 13 of 13 placements, both
seats, zero fallbacks.** Probe game, seed 7002, `plans_on` on P1 and P2:

```
P1 plan deploys: 13 distinct units    P2 plan deploys: 13 distinct units
"placement for X did not validate and repair failed": 0 occurrences
```

That is the number the PM-10 gate asks for (≥90% of covered units on both
seats), and it is only true after the two corrections below. Before them the
same measurement read **5 of 11**.

### How adherence is counted, and why the obvious way is wrong

Counting plan-sourced decision records **overstates adherence**. Reserve
arrivals also record `source: plan:<name>`, so a seat that placed 5 of 11 units
correctly reported 9 plan-sourced deployment records — 4 of them were the
reserved units arriving on round 2, which say nothing about whether a placement
was honoured.

Adherence here is therefore counted two ways, and both are reported:

1. **distinct units deployed from the plan**, de-duplicated against the plan's
   own placement list (reserve arrivals excluded);
2. **model positions compared against the plan file itself** — a unit counts
   only if every model is within 0.05" of where the plan put it. A placement the
   consumer had to *repair* is deliberately not counted as adherence.

### In a real game from the menu

`sp/pm10_shipped_plan_from_menu.json` — **27 passed, 0 failed** — plays a menu
game with the shipped hammer_anvil plan on seat 1 and "None" on seat 2, so the
same army deploys twice on one board:

```
plan-sourced deployment records   seat 1 (plan): 9      seat 2 (control): 0
placements eligible to deploy     9 of 13   (2 attached, 2 embarked — see below)
landed on the plan's coordinates  8 of 9    (1 repaired)
reserves                          exactly the 4 the plan asked for
attachments                       exactly the 2 the plan asked for
the control seat sits             12.8" from the plan's coordinates on average
```

The control seat's 12.8" is the check that stops this being circular: if the
formula happened to deploy where the plan says, the adherence number would be
meaningless.

**Why only 9 of 13 are eligible.** Two are the Deffkilla Wartrikes, which the
plan attaches to Warbiker mobs — an attached character deploys with its
bodyguard, so its own placement never applies. (On the bench fixture the
attachments cannot be retrofitted post-FORMATIONS, so there they *do* deploy
separately, which is why the bench number is 13 and this one is 9.) The other
two are both Gretchin mobs, and that one is a defect — **PM-F5**, below.

---

## A game against the plan-driven AI (the stand-in)

The task asks for one human-vs-AI game against the plan-driven AI, with notes
on where the plan looked smart or stupid. **The owner did not play this.** What
follows is the scripted stand-in the task text permits, and the distinction
matters when reading it:

* seat 1 is a **HUMAN seat**, not a second AI — but it is driven by
  `pm10_standin.py`, which deploys from the plan's own (unmirrored)
  coordinates and then passes every phase.
* so these notes are about **how the AI executes its plan over a full game** —
  does it hold the objective, do the reserves arrive, does the Stompa actually
  push — and **not** about how the plan fares against competent opposition.
  Nobody contested it.

_(observations filled in below)_

---

## What the plans are

Two plans ship, both for `recon_stomps`, both carrying the same tactical
content:

| file | zone | terrain key | placed | reserved | attached |
|---|---|---|---|---|---|
| `orks_recon_stomps_crucible.json` | `crucible_of_battle` | `take_and_hold_mirror_1` | 13 | 4 | 2 |
| `orks_recon_stomps_hammer_anvil.json` | `hammer_anvil` | *(any)* | 13 | 4 | 2 |

13 placed + 4 reserved accounts for all 17 units in the list, which is
deliberate — see "Cover the whole army" below.

Gretchin hold `obj_home_1` with a second mob screening beside them; the Stompa
leads Wazdakka and both Warbiker mobs — each led by a Deffkilla Wartrike — up
the middle; two Stormboyz mobs screen; two more Stormboyz mobs and both
Deffkopta units are in Reserves for round 2. Both validate with **0 errors and
0 warnings**, against the army, which is what turns on the coverage and
reserve-cap checks.

Authored by `40k/tests/spikes/pm10_author_plans.gd`: every placement is
validated by `DeploymentPhase.validate_action` on a live board, rounded to
0.01" *before* validation so the coordinates checked are the ones written, and
additionally required to sit wholly inside the shipped zone polygon.

### Cover the whole army — a partial plan eats itself

The crucible zone cannot hold this army on the board: the usable region is
about 410 sq in against roughly 330 sq in of base-plus-gap area. The answer is
**Reserves**, not partial coverage. Both Deffkopta units and two Stormboyz mobs
arrive on round 2 (410 of 2000 points, 4 of 17 units — inside the 50% caps),
and every remaining unit gets an explicit placement.

The first draft did the tempting thing instead and left the two attached
Deffkilla Wartrikes out of the plan, on the reasoning that an attached
character deploys with its bodyguard anyway. **Measured, that cost six of
eleven placements.** A unit the plan does not cover is deployed by the formula,
in the formula's chosen spot, and a 95x150mm base parked in the middle of a
44x8 band is exactly where the next planned placement wanted to be. Seat-2
adherence was **5/11** with the Wartrikes uncovered and **13/13** with them
covered — the single largest correction in this task.

---

## The embarkation finding (PM-F5) — the one that matters most

The plan declares `"embarkations": []`, places both Gretchin mobs **on**
`obj_home_1`, and earmarks both `HOLD_OBJECTIVE obj_home_1`. In a real game the
AI put them **inside the Stompa**, which is a transport, during FORMATIONS:

```
Player 1 transport_embarkations: { "U_STOMPA_A": ["U_GRETCHIN_A", "U_GRETCHIN_B"] }
Player 2 transport_embarkations: { "U_STOMPA_A_P2": ["U_GRETCHIN_A_P2", ...] }
```

Both seats, every run, with no log line and no error. Embarked units do not
deploy on their own, so the plan's placements for them are never used and the
objective the entire plan is built around is left empty — visible in
`pm10_plan_vs_formula_deployment.png` as **HOME 1: Uncontrolled** at the end of
deployment.

PM-2b made a plan able to *declare* embarkations. It did not make an empty
list mean "and embark nothing else", so the formula's own embarkation logic
still overrules a plan that wants the unit on the ground. Filed as **PM-F5**;
the scenario pins the current wrong behaviour on purpose so that fixing it
fails the step rather than landing unnoticed.

---

## The 9" envelope finding (PM-F4)

The second correction, and the one that would have been easiest to ship
without noticing. `AIDecisionMaker._plan_positions_legal` enforces 11e
coherency — 2" to a neighbour **and 9" to every other model in the unit** —
unconditionally. `DeploymentPhase._check_deployment_coherency` enforces it
through the edition-aware `AttackSequence.check_unit_coherency`, and the
automated harness pins `GameConstants.edition` to the legacy 10e baseline,
which has no 9" envelope.

The two disagree, and the AI is the stricter one. The authoring pass laid
Gretchin Alpha out as an 11-model line **13.60" across**,
`DeploymentPhase.validate_action` accepted it, and the AI then refused its own
plan's placement in every game on both seats — one line in the log, no error,
no stall, just a unit quietly standing somewhere else.

`pm10_author_plans.gd` now filters candidate formation shapes to an 8.8" span
and refuses to write a plan whose emitted placements exceed 9". The underlying
disagreement is filed as **PM-F4**; the shipped plans satisfy the stricter of
the two rules either way.

**Both corrections were only visible because adherence is measured against the
plan file rather than counted from the decision log.** Counting plan-sourced
records alone would have reported 9 for a seat that placed 5 units correctly,
because reserve arrivals also record a plan source.

---

## The stale-fixture finding (PM-F3)

`DeploymentZoneData.get_zones()` prefers `res://deployment_zones/<id>.json`
over its hardcoded fallback, and the crucible JSON was regenerated from the
40kdc 11e dataset. The predeploy fixtures predate that and carry the OLD
geometry in their saved `board`, which `SaveLoadManager` restores verbatim:

```
fixture board:   44x8 band + 24x6 centre step,   obj_home_1 at (22, 4)
shipped JSON:    triangle (0,0)-(44,30)-(44,0),  obj_home_1 at (32, 14)
```

**Every AI benchmark run on these fixtures — including this one — plays a board
no menu game can produce.** It surfaced here because the deployment phase
accepted placements that `PlanValidator` then flagged as outside the zone; the
two were reading different polygons.

The shipped crucible plan is packed into the **intersection** of the two, so it
is legal on the fixture and in a real game. It cannot sit on both versions of
`obj_home_1` at once, and covers the fixture's, since that is where it is
measured. Regenerating the fixtures is filed as **PM-F3** rather than done
here: it moves a shared benchmark asset that the neighbouring reports in this
directory were measured on.

---

## Reproducing

```bash
# author the plans (writes both files, refuses on any error OR warning)
export PATH="$HOME/bin:$PATH"
godot --headless --path 40k -s tests/spikes/pm10_author_plans.gd

# the paired A/B
python3 tools/ai_lab/run_paired.py \
  --candidate 40k/tests/bench_profiles/plans_on.json \
  --baseline  40k/tests/bench_profiles/plans_off.json \
  --plan      "res://data/ai_plans/orks_recon_stomps_crucible.json" \
  --fixture   mirror_orks_2000_predeploy \
  --difficulty 1 --season <dir> --min-pairs 6 --max-pairs 6 --batch 6 \
  --lanes 3 --aa-arm

# the player-facing path
bash 40k/tests/run_scenario.sh tests/scenarios/sp/pm10_shipped_plan_from_menu.json
```

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

**The plan feature does what it claims: 100% adherence, on both seats, in
every game that completed.** 13 of 13 placements and 4 of 4 reserves, measured
against the plan file rather than counted from the log. That is the primary
gate and it passes with room to spare.

**The run also fails the other half of the primary gate: there were stalls.**
Two of six seeds hung in deployment, deterministically, on the seat with plans
switched OFF. That is a pre-existing formula defect (**PM-F6**) rather than a
plan defect — but a plan-driven opponent reproduces it reliably, so shipping
plans makes it reachable in ordinary play, and it cost a third of the paired
data.

**There is no measured VP effect: E = +3.00 VP/game, se 6.83, 2-se interval
[−10.7, +16.7] at n = 4.** The run cannot see anything smaller than ±13.7 VP,
so this is a null in the "we could not have detected it" sense rather than the
"it does nothing" sense. E is not negative, which is the sanity check the gate
asks for, and nothing stronger is claimed. (At three pairs the same run read
+9.67 with an interval excluding zero; the fourth pair was −17.0. That is
recorded in full as an argument against reading sequential runs early.)

**Three further defects were found by measuring adherence properly**
(PM-F3, PM-F4, PM-F5), all of which the AI absorbs silently: no error, no
stall, just the AI doing something other than what the plan says. PM-F5 is the
one to fix first — it leaves the objective the whole plan is built around
**Uncontrolled** at the end of deployment.

Both plans ship. They are marked `"author": "claude-draft — owner review
wanted"`, and that label is doing real work: the content is strong practice
mechanically, but nobody has played against it.

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

**And the realised n is smaller than the planned n**, because a seed only
yields a pair if it completes in BOTH arms and PM-F6 stalls some of them. The
table above is therefore the optimistic case; the number of pairs actually
obtained is stated with the result, and the minimum detectable effect is
recomputed at that n rather than at 6.

---

## Results

12 games, 6 seeds x 2 arms, Normal difficulty, `--max-seconds 1800`.
`plans_on` is on P2 in M1 and on P1 in M2, so the pair difference cancels the
fixture's structural bias.

| arm | seed | winner | margin (P2−P1) | rounds | wall | plan seat adherence |
|---|---|---|---|---|---|---|
| M1 | 9001 | — | *stalled* | 1 | 94s | — |
| M1 | 9002 | 2 | +23 | 5 | 989s | 13/13 + 4/4 |
| M1 | 9003 | 2 | +19 | 5 | 834s | 13/13 + 4/4 |
| M1 | 9004 | 1 | −27 | 5 | 1103s | 13/13 + 4/4 |
| M1 | 9005 | — | *stalled* | 1 | 95s | — |
| M1 | 9006 | 2 | +11 | 5 | 689s | 13/13 + 4/4 |
| M2 | 9001 | 2 | +9 | 5 | 911s | 13/13 + 4/4 |
| M2 | 9002 | 2 | +1 | 5 | 661s | 13/13 + 4/4 |
| M2 | 9003 | 2 | +8 | 5 | 790s | 13/13 + 4/4 |
| M2 | 9004 | 2 | +7 | 5 | 1288s | 13/13 + 4/4 |
| M2 | 9006 | 1 | −14 | 5 | 740s | 13/13 + 4/4 |

**A seed only yields a pair if it completes in BOTH arms**, and PM-F6 stalled
9001 and 9005 in M1, so those seeds are gone regardless of what M2 did with
them. That is how 6 planned pairs became the handful reported below.

### The effect

```
paired seeds       9002, 9003, 9004, 9006     n = 4  (of 6 planned)
per-pair effects   +11.0, +5.5, -17.0, +12.5
E                  +3.00 VP/game
sd 13.67   se 6.83   2-se interval [-10.7, +16.7]
minimum detectable effect at n=4 (2 se):  +/- 13.7 VP
F (structural bias, from the A/B arms themselves) = +3.50 VP
```

**E is +3.00 VP/game with an interval that comfortably spans zero. There is no
measured effect here, and that is the expected outcome at this n.** A plan
worth 3 VP a game is invisible to a 4-pair run that cannot see anything under
±13.7 VP. The gate asked for E to be *reported* with its se and for the MDE to
be stated plainly — done — and for "E not significantly negative" as a sanity
check, which passes.

**A caution worth recording, because it nearly went the other way.** With three
pairs in hand this read `E = +9.67, sd 3.69, se 2.13`, a 2-se interval of
`[+5.4, +13.9]` that excluded zero, and would have satisfied the
pre-registered |E| ≥ 4 VP and 2 se rule. The fourth pair was −17.0 and the
effect collapsed to +3.00 with the interval spanning zero. Three consistent
numbers are not evidence of consistency; an sd estimated from three points is
an artefact of the sample. The interim figure is left here deliberately as the
reason not to read a sequential run early.

**The missing seeds are not missing at random.** 9001 and 9005 are exactly the
seeds where the formula seat stalls (PM-F6), so the surviving sample is the one
where the formula could deploy successfully. Which way that biases E is not
established; it is another reason the number is reported rather than claimed.

Confirming a real effect needs the PM-F6 stall fixed and a re-run at 12+ pairs.
On the prior sd of ~20 VP/game that is roughly ±8 VP of resolution — still
coarse, which is why the plan feature is justified on adherence and
predictability rather than on VP.

### Stalls — the primary gate FAILS, and it dominated the run

The primary gate includes **zero stalls**. It is not met. In the first
completed wave of the M1 arm, **4 of 5 games did not complete**:

```
9001  stalled    round 1   wall   94s   "no progress for 90s at 1|1|41"
9002  timeout    round 4   wall  901s
9003  completed  round 5   wall  839s   margin +19
9004  timeout    round 4   wall  918s   margin -39
9005  stalled    round 1   wall   94s   "no progress for 90s at 1|1|42"
```

Two distinct problems, and only one of them is mine:

**The timeouts were my run configuration.** A completed game on this fixture at
Normal takes ~840s; `--max-seconds 900` left no headroom, so games still
playing round 4 were cut off. The run was relaunched with `--max-seconds 1800`.
That is a harness setting, not a defect, and it is called out here because
"2 timeouts" in a results table looks like an engine problem and was not.

**The stalls are a real defect, and always on the seat with plans OFF.** Both
have the same signature:

```
seed 9001                                    seed 9005
P1  Deployed Warbikers Gamma (col 5, row 3)  P1  Warbikers placed in reserves (fallback)
P1  Warbikers placed in reserves (fallback)  P1  Deployed Warbikers Delta (col 1, row 4)
P2  Deployed Warbikers Delta FROM PLAN       P1  Deployed Wazdakka Gutsmek (character…)
P1  Deployed Warbikers Delta (col 1, row 4)  P1  Deployed Wazdakka Gutsmek (retry 4)
P1  Deployed Wazdakka Gutsmek (character…)   P2  Deployed Warbikers Alpha FROM PLAN
```

The formula retries a placement, falls back to reserves, and the game then
makes no progress at all. The plan-driven seat deploys cleanly through both
sequences. The same retry-until-fallback pattern appears in the windowed
scenario's log on its control seat ("*AND within 9" of every other model in the
unit (1 model(s) out of coherency.) — retry…*").

**The plan does not cause it, but it does expose it — and that distinction is
not a way of dodging the gate.** Seed 9001 completed in an earlier run of the
same arms against an earlier version of the plan. The formula counter-deploys
relative to the enemy cluster (`T7-44 melee counter-deploy: shift toward enemy
cluster`), so changing what the opponent puts on the board changes where the
formula tries to go, and on this fixture it sometimes tries to go somewhere it
cannot legally fill. Shipping a plan therefore makes this reproducible in
ordinary play. Filed as **PM-F6**.

Nothing in this task changes AI code; the seat that hangs is the one with plans
switched off. It is still reported as a gate failure, because "somebody else's
bug" is not "no stalls", and because each stalled seed costs a whole pair —
which is the direct reason the effect below is measured at a smaller n than
intended.

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

### What was actually played

A real menu game: seat 1 **HUMAN** on `recon_stomps`, seat 2 **AI** on
`recon_stomps` with the shipped hammer_anvil plan, hammer_anvil derived from
the Force Dispositions + `take_and_hold_vs_purge_the_foe_3`. The script
designated a warlord, confirmed formations, won the roll-off, chose a side, and
then deployed seat 1 from the plan's own (unmirrored) coordinates.

**Scope, stated plainly: this covers setup, formations and deployment — not
five battle rounds.** Driving a human seat's whole game through the bridge is a
much bigger job than it looks and the session budget went on the four defects
above instead. What follows is what the deployment phase showed. Screenshot:
`40k/docs/evidence/pm10_standin_human_vs_plan_ai.png`.

### Where the plan looked smart

* **It deployed at all.** The AI put 12 of 13 units down straight from the plan
  ("*P2: Deployed Warbikers Gamma from plan 'Orks — Recon Stomps on Hammer and
  Anvil'*", over and over in the game log), with 4 in reserves exactly as
  declared, while the human seat next to it was grinding.
* **Reserves and attachments came out right without any prompting** — the same
  4 units held back, the same 2 Wartrikes attached, in a game that had nothing
  to do with the bench fixture.
* **Every position it used was pre-validated.** That is the real advantage and
  it is invisible until you try to do it by hand — see below.

### Where the plan, and the board, looked stupid

* **`obj_home_1` is Uncontrolled at the end of deployment** — the objective the
  entire plan is written around. That is PM-F5: the AI put both Gretchin mobs
  inside the Stompa. A person watching this game would see the AI ignore its
  own stated intent, with nothing in the log to explain it.
* **The human seat could not legally deploy its Stompa anywhere.** 9,408
  candidate positions across the whole zone were rejected by the phase — the
  screenshot shows why, with the highlighted zone almost entirely under
  terrain. The plan's own Stompa coordinate was among the rejects for seat 1
  (`Model cannot overlap with walls this unit can't cross`), while the AI
  seated its mirrored Stompa without trouble: the terrain on this layout is not
  symmetric, so a plan authored in the player-1 frame is not automatically
  comfortable in it.
* **That cuts both ways as an argument for the feature.** A plan's positions
  are checked against the deployment phase itself at authoring time; a player
  eyeballing the same board gets no such help, and on this layout a 180mm base
  simply has nowhere to stand once the rest of the army is down.

**Nobody contested the plan**, so nothing here says whether it is a *good*
plan. That question is still open and is what the `"author": "claude-draft —
owner review wanted"` label is for.

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

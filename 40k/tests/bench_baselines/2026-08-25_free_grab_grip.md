# Da Free-Grab Grip — a plan authored through the player tools, measured 11–1

**Date:** 2026-08-25
**Branch:** `claude/plan-maker-todo-w0syuf`
**Plan:** `40k/data/ai_plans/orks_free_grab_grip_hammer_anvil.json` ("Orks — Da Free-Grab Grip")
**Authored:** in the live Plan Editor (real FORMATIONS declarations, real
deployment phase validation, intents painted through the INTENTS panel, saved
with the banner's Save as Plan button), driven over the MCP bridge.
**Author label:** "Claude — played via the Plan Editor and sim-tested 11-1 vs
the shipped plan; human review still wanted" — the label is doing real work:
this is Claude's tactical judgment exercised through the player's tools, not a
human's, and nobody has yet played against it by hand.

## The question

The A/B re-run (2026-08-21) ended with: adherence is saturated, so the only
lever left is plan CONTENT. This is the first content pass: design a better
hammer_anvil plan the way a player would — study the board, use the editor,
test in the simulator — and measure it against the shipped
`Orks — Recon Stomps on Hammer and Anvil`.

## The design, and where it came from

Three independently-designed candidates (a primary-maximisation lens, a tempo
lens, a deny-and-counterpunch lens) were adversarially judged and synthesised;
the synthesis was then corrected twice by engine measurement before a model
was ever placed:

- the judge's 17"-wide Gretchin picket line violates the 11e 9" coherency
  envelope (the exact shape PM-F4 was filed over) — replaced with a legal
  8"-wide double rank;
- "deep strikers arrive AT an earmarked objective" is not a thing the engine
  does — reinforcement placement scores proximity to ANY objective
  (`REINFORCE_OBJ_NEAR_BASE`), earmarks only steer movement after arrival —
  so the design stopped claiming it.

The thesis: primary caps at the "more than 2" bracket, so buy THREE
low-contest objectives — obj_home_1 plus both no-man's-land markers at
(6,30)/(38,30), which sit exactly one M12 move beyond the zone edge — and
glue OC to them with HOLD earmarks, while the Stompa parks on obj_center to
deny it and soak the formula's high-value-target preference. The shipped plan
binds nothing to either no-man's-land objective; that is the whole gap.

**Then the terrain rewrote the flanks**, which is the part a spreadsheet
would have missed: the rolled layout (`take_and_hold_mirror_1`) walls both
zone-edge flanks against MOUNTED bikes. The played answer: 3-bike columns
ride the clear 2" corridors on the board edges (west of x2.7, east of x41.7)
to take the markers on move 1; the Wartrike-led 6-bike mobs stage in clear
south pockets as second wave; Stormboyz jump the ruins the bikes cannot
cross. Every placement went through the live phase's validate-and-nudge —
the same "drag until the ghost turns green" a player does. The two attached
Wartrikes were placed by the phase itself (P1-66), not by the plan.

## The measurement

Plan-vs-plan in the shipped Battle Simulator backend: recon_stomps mirror,
hammer_anvil, layout take_and_hold_mirror_1, mission take_and_hold, Normal,
seeds 4001–4006, both seat orders — 12 games.

| arm | seats | result | mean margin |
|---|---|---|---|
| 1 | Grip = P1, shipped = P2 | **6–0 Grip** | +27.0 ± 8.7 (sd) |
| 2 | shipped = P1, Grip = P2 | **5–1 Grip** | +15.2 ± 11.4 (sd) |

**11–1 overall; seat-bias-cancelled effect ≈ +21 VP/game toward the Grip.
Zero stalls, zero timeouts.** Against the lab's noise scale (the A/B's se
was ~2.2 VP at n=6 pairs), this is not a coin-flip readout.

## Honest limits

- **One layout.** The Grip is layout-bound (`terrain_layout_id:
  take_and_hold_mirror_1`); on any other layout it does not match and players
  get the generic shipped plan as before — no regression surface, but also
  no claim beyond its own board.
- **Part of the margin is domain advantage.** The shipped plan was authored
  on a different layout and repairs on this one. That asymmetry is intrinsic
  to layout-bound vs match-any plans; the headline claim is "a layout-tuned
  plan beats the generic plan on its layout by ~21 VP", not "this design is
  universally better".
- **Same engine both sides.** Both seats are the same AI; this measures plan
  content under the game's own opponent, not against a human.
- **Claude judgment.** The three-lens design, the judging and the terrain
  adaptation were all mine. The "owner review wanted" flag stays.

## What was blocking this before? Nothing.

The stated reason the shipped plans carried a "nobody has played against it"
caveat was the absence of a player in the loop. The Plan Editor, the intent
painter, the save dialog and the simulator were all built for exactly this
loop, and they all worked first try when driven as a player would use them —
the only fixes this exercise needed were to MY plan (coherency envelope,
deep-strike assumption, terrain re-tasking), which is the tools doing their
job.

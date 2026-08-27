# Next-steps ladder: threshold hunt, E2 iteration 1, difficulty-gate wiring (2026-08-27)

Executed as one sequence after the LLM-commander null
(`2026-08-26_llm_commander.md`): (1) the threshold hunt that null left
open, (2) the conditional dial-commander branch, (3) the first offline
improvement iteration, (4) wiring the decorative difficulty gates.
All measurement ran on the pre-wiring engine; the gate change landed
last. Protocol throughout: custodes_lions mirror, hammer_anvil /
take_and_hold_mirror_1 / take_and_hold, difficulty 1, seeds 5001–5006,
seed-paired against the A/A anchor (margins [−20, +4, +64, −22, +10,
+24]).

## 1. Threshold hunt — binding earmarks (VERDICT: no promise)

The commander experiment's open question: does the LLM commander start
to matter once its orders actually bind? `commander.py --earmark-bonus
40` injects a profile fragment per game raising the earmark priors to
HOLD 40 / PUSH 30 / HUNT 20 (verified live: `get_param` readback 40.0
under the seat's player context; fragment install lines in the log).

| Arm | Paired deltas vs anchor | Mean |
|---|---|---|
| Commander P1, bonus 40 | 0, +6, −2, 0, −3, 0 | **+0.2 ± 3.1** |
| Commander P2, bonus 40 | 0, 0, 0, −5, +8, 0 | **+0.5 ± 4.2** |

**Seat-cancelled ≈ +0.3 VP/game** (pre-stated promise bar: ≥ +8).
With the bonus binding, ~95% of earmarked movement decisions went the
commander's way (e.g. 19–20 of 20 per game, including arguments the +8
prior used to lose) — and the outcomes still didn't move. Half the games
*still* replayed the anchor bit-for-bit because the orders agreed with
the formula. This closes the commander line cleanly: the null was never
about actuator strength or the commander's information — **the formula's
objective assignments are near-equivalent to LLM judgment on this
board.** Notable detail: seed 5004/P2 reproduced the bonus-8 run's
divergence exactly (same −17, same 28–45), i.e. the same disagreement,
same flip, no additional effect from the larger bonus.

## 2. Dial-commander branch — not pursued

Pre-stated rule: only on promise from (1). Recorded and skipped.

## 3. Offline improvement loop, iteration 1 (VERDICT: null, nothing adopted)

Three independent analysis lenses over the AI dossiers and bench history
each proposed 4 parameter-only candidates; all three converged on
lowering `FACTION_AGGRESSION_CUSTODES` (1.5 → 1.0/1.15/1.2), the analog
of the measured Ork discipline win. Screens used **fragment-only plans**
(a plan whose only content is `profile_fragment.parameters` — zero code,
one seat modified, native PlanSimulator installation; candidates in
`40k/tools/llm_commander/e2/`).

| Candidate | Arm | Paired deltas | Mean |
|---|---|---|---|
| A: FACTION_AGGRESSION_CUSTODES 1.15 | P1 | 0,0,0,0,0,+13 | +2.2 |
| A | P2 | −18,0,0,0,0,0 | −3.0 |
| B: MOVE_TURNS_AWAY_PENALTY 3.0 | P1 | 0,+3,0,0,0,0 | +0.5 |

Candidate A seat-cancelled ≈ **−0.4** — the arm-1 signal (one game,
+13) reversed in arm 2 (one game, −18). Candidate B inert. Nothing
adopted; the shipped defaults stand.

**The meta-finding, consistent across (1) and (3):** this mirror is
extraordinarily insensitive to single-knob nudges — 26 of 36 measured
games replayed the baseline identically, and the divergences were
sign-random singles. The formula's decisions sit in wide flat optima
here. Practical consequences: (a) parameter tuning on a single mirror
cannot resolve small effects at 6 seeds — future iterations need more
seeds and more matchups; (b) the levers that measurably changed games
this week remain the structural ones (deployment, reserves, layout
knowledge).

## 4. Difficulty gates wired (SHIPPED, v1.39.0)

The dossier finding — seven gates in `AIDifficultyConfig.gd` defined but
never consulted — is fixed per the documented intent:

- **Screening / deep-strike denial: Hard+** (Normal no longer screens;
  the support-fallback assignment still runs at all scoring tiers).
- **Trade analysis: Competitive only** (`_get_trade_efficiency` returns
  1.0 below it — one choke point covering charge and fight scoring).
- **Focus fire, weapon efficiency, survival assessment: Normal+**
  enforced at their sites (behavior-neutral today — Easy never reaches
  those paths — but the config is now real).
- `use_look_ahead` / `get_movement_iterations`: honestly marked "not
  yet consumed"; the Competitive description no longer claims look-ahead.

Validation: new unit test `test_difficulty_gates.gd` (75 assertions:
full tier matrix + call-site pins + behavioral checks) plus 13 AI test
files green headless; live seed-paired proof on the wired build —
Normal A/A seed 5001 **diverges** from the pre-wiring anchor (screening
off changed the game) while the same build's Hard game runs the
screening path. Changelog v1.39.0. A side fix: four pre-existing unit
tests now pin `_current_difficulty = NORMAL` (a headless static-init
quirk resolved it to EASY when bypassing `decide()`), which also
de-flaked `test_ai_charge_decisions.gd`.

## Where this leaves the AI roadmap

- The **online LLM commander line is closed** with mechanical evidence
  at two bonus levels. C2b's future reviewer should be a cheap
  heuristic unless a fundamentally different actuator (reserves,
  stratagems, CP) is on the table.
- The **offline loop is set up and cheap to iterate** (fragment-only
  screens, ~7 min/arm), but iteration 2 should widen the testbed
  (more seeds, a second matchup, ideally a horde army where decisions
  are denser) before trusting any single-mirror signal.
- **Difficulty tiers now differ as documented** — worth a future
  cross-tier benchmark (Normal vs Hard win rates) to quantify the gap
  the wiring created.

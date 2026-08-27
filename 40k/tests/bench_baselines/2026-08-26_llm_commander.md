# LLM Commander experiment — adaptive per-round directives (2026-08-26)

The follow-up the static-plan negative result demanded
(`2026-08-26_auric_vice.md`): if fixed plans lose because they are rigid,
does a **turn-adaptive commander** — an LLM that reads the live board and
rewrites the seat's standing earmarks every battle round — beat the
no-plan formula? This is the C2b "BattlePlan reviewed each command phase"
slot from `.llm/ai-overhaul-todo.md` with an LLM reviewer, run entirely
from outside the engine (harness: `40k/tools/llm_commander/`, design:
`.llm/llm-commander-experiment.md`). Zero engine changes.

**Headline: a clean null with a sharp mechanistic cause.** The commander
was heard — every game shows its earmarks consumed inside the movement
assignment — but it almost never mattered: most games replayed the
no-plan baseline **bit-for-bit identically**, because the earmark score
prior (+8/+6) is too small to flip this army's assignment decisions.
The bottleneck is the actuator, not the strategy or the cadence.

## Setup

- custodes_lions mirror, hammer_anvil / take_and_hold_mirror_1 /
  take_and_hold, difficulty 1, time_scale 10 — identical to the
  static-plan experiment; its A/A anchor transfers (margins below;
  re-verified on this container: seed 5001 reproduced −20 exactly, both
  in a freeze-exercised A/A and in the commander games).
- Commander brain: `claude -p --model claude-sonnet-5`, fresh context per
  decision, ~3.7KB board snapshot in, strict-JSON directive out.
  Latencies 12–52s per call, all inside a `Engine.time_scale = 0.0`
  freeze (measured outcome-neutral; hard 90s stall watchdog respected —
  zero stalls or timeouts in every valid game; the one watchdog
  interaction, a slow-mo artifact on seed 5004/C2, is dissected below).
- Five directives per game (rounds 1–5, caught at the seat's COMMAND
  phase every time; the `late` fallback never fired). Directives
  journaled verbatim in `40k/tools/llm_commander/runs/` (measured runs
  archived beside this report in `llm_commander_runs/`).
- Consumption proof per game: movement decision records carrying the
  earmark context and the `plan_earmark` score term (counted from
  `AIPlayer._all_decision_records`), plus live `[plan]` release lines in
  the debug log.
- A mid-pilot frame of a commander game in play:
  `40k/docs/evidence/llm_commander_pilot_round2.png` (round 2/5, the
  commanded mirror match mid-charge-phase).

## Arm C1 — commander on seat 1 (P1), formula on seat 2

| Seed | Margin (P1−P2) | A/A anchor | Paired Δ | Result | Earmarked records |
|------|---------------|-----------|----------|--------|-------------------|
| 5001 | −20 | −20 | 0 | L | 10/14 (10 chosen) |
| 5002 | +4  | +4  | 0 | W | 23/28 (20 chosen) |
| 5003 | +64 | +64 | 0 | W | 23/25 (21 chosen) |
| 5004 | −22 | −22 | 0 | L | 11/12 (7 chosen) |
| 5005 | −2  | +10 | **−12** | L | 11/16 (11 chosen) |
| 5006 | +24 | +24 | 0 | W | 16/20 (11 chosen) |

**Mean paired Δ −2.0 ± 4.9, wins 3–3.** Five of six games reproduced the
anchor exactly (identical VP, e.g. 5001's 37–57 three separate times:
anchor, pilot, arm) despite 10–23 earmarked movement records per game.
The one divergence (5005) flipped a +10 win into a −2 loss.

## Arm C2 — commander on seat 2 (P2), formula on seat 1

| Seed | Margin (P1−P2) | A/A anchor | Paired Δ (P2 view) | Result | Earmarked records |
|------|---------------|-----------|--------------------|--------|-------------------|
| 5001 | −20 | −20 | 0 | W | 15/17 (12 chosen) |
| 5002 | +4  | +4  | 0 | L | 12/14 (9 chosen) |
| 5003 | +64 | +64 | 0 | L | 7/8 (7 chosen) |
| 5004* | −17 | −22 | **−5** | W | 14/15 (14 chosen) |
| 5005 | +10 | +10 | 0 | L | 15/16 (12 chosen) |
| 5006 | +24 | +24 | 0 | L | 11/13 (10 chosen) |

**Mean paired Δ −0.8 ± 2.0 (P2 view), wins 2–4** — the anchor's own
seat split (P1 4–2) unchanged. Five of six valid games anchor-identical.

\* Seed 5004 needed three runs. Twice it was killed as "stalled" at the
same point — deterministically, with identical partial VP (19–7, round
3) — because a game-time quiet stretch in P1's round-3 charge/fight
inflates ×10 in wall time under the harness's slow-mo (time_scale 1.0)
and crosses the engine's fixed 90s wall-clock stall watchdog
(`DEFAULT_STALL_SECONDS`, not configurable). The commander freezes were
13s/22s — not the cause. Re-run with slow-mo at time_scale 2.0
(`--ts-slow 2.0`; slow-mo is outcome-neutral, established by the
bit-identical replays), it completed with all 5 rounds commanded and
produced the arm's one real divergence. Both killed runs are in the
journals.

## Combined verdict

Seat-cancelled commander effect ≈ **−1.4 VP/game** (mean of −2.0 and
−0.8) — indistinguishable from zero at this resolution, with a slight
negative lean. **10 of 12 valid games reproduced the no-plan baseline
bit-for-bit**; the two divergences were −12 (C1/5005) and −5 (C2/5004).
Zero stalls or timeouts in the 12 valid games; 60 commander directives
issued and consumed across them.

## What the bit-identical replays prove

1. **The pipeline works end to end.** Injection stored (readback), read
   live (release log lines, earmark contexts on records, `plan_earmark`
   terms on candidates), every round, both in agreeing and disagreeing
   cases (5002 had 3 records where the earmark lost the argument).
2. **The earmark lever is too weak to steer this army.** A +8 additive
   prior competes with assignment terms an order of magnitude larger
   (objective priorities, threat deltas, distance penalties, hold rules).
   When the LLM ordered what the AI already preferred, nothing changed;
   when it disagreed, it lost the argmax — except once, negatively.
3. **Seeded determinism is airtight**: separate `PlanSimulator.start()`
   calls reproduce games VP-for-VP across container rebuilds, exactly as
   the recon predicted. The paired-delta method rests on solid ground.
4. **Reinterpretation of the static-plan v3 result**: the earmarks-only
   plan measured −39.7 (arm1, seed-paired) — but this experiment shows
   round-level earmarks barely flip decisions. v3's game changes were
   therefore driven almost entirely by its **deep-strike reserve
   declaration** (a deployment-time actuator that really does change the
   game), not its earmarks. The strongest levers in the current plan
   vocabulary act before the first round, not during play.

## Implication for C2b (adaptive BattlePlan)

Adaptivity and review cadence are NOT the bottleneck — a per-round
commander with genuine strategic reasoning moved the result −2 VP on
average because its only lever was a sub-threshold score nudge. Before
any BattlePlan reviewer (LLM or heuristic) can matter, the plan-to-AI
coupling needs stronger actuators, in rough order of expected effect:
- **assignment overrides** (a directive the argmax cannot outvote,
  with the existing 50%-strength release as the safety valve),
- **reserve/arrival control** (already proven to change games),
- a **scaled bias** (earmark weight as a plan-tunable parameter — the
  no-code `profile_fragment` path can already raise
  `PLAN_EARMARK_HOLD_BONUS`, which suggests a cheap follow-up: rerun
  this exact experiment with the bonus at 30–50 to find the threshold
  where the commander's opinion starts to bind).

## Cost/latency observed

~5 calls/game, 23–52s each (median ~26s), ≈2.5 min of thinking per
game on top of ~2.5 min of simulation; 12-game arm ≈ 50 min wall. A
human-vs-AI game would spend the same ~2.5 min per game total, spread
one call per round — consistent with the design estimate that a
command-phase director is playable, while per-action LLM play is not.

## Honest scope

One commander model (claude-sonnet-5), one army (slow elite Custodes),
one board, 6 seeds per arm. The null is about the **earmark actuator
under this engine** — demonstrated mechanically by the replays, not just
statistically — and does not preclude an LLM commander mattering once a
binding actuator exists. Commander calls are non-deterministic across
runs (journals preserve what was decided); the engine side stayed fully
seeded throughout.

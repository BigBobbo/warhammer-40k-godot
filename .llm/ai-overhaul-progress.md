# AI Overhaul — progress journal

Companion to `.llm/ai-overhaul-todo.md`. One line per task: status, key
result, timestamp. Evidence blocks live under each task in the todo file;
this file is the index.

Run started 2026-08-07 on branch `claude/ai-overhaul-todo-completion-ve8fhj`
(from `origin/main` @ `8d693c7`).


---

# FINAL SUMMARY — run of 2026-08-07/08

**11 commits on `claude/ai-overhaul-todo-completion-ve8fhj`, all pushed.**
Phase 1 is complete except for B1; Phase 2 is not started. The workstreams
after that (WS-C plan layers, WS-D lookahead, WS-E the loop, WS-F personas)
are untouched, and two of them are physically out of reach for one session:
E1 alone is a 1,500-3,500-game campaign (2-4 days of unattended compute at
current speeds), and E2/E3 each cost 300-400 games per cycle.

## Tasks completed and validated

| Task | Outcome |
|---|---|
| **A1** | Shooting records carry the real scored field (top-6 weapon x target with marginal value, expected damage, target value, kill threshold, allocation, efficiency) instead of restating the plan. `hold_fire` recorded for the first time, proven both ways in a windowed scenario (chosen_index 0 on a chip shot, 1 when the shot is made worth taking). |
| **A2** | Movement score decomposed into 21 named additive terms with `sum(terms) == score`. Candidates carrying >= 3 named terms: **0/803 -> 797/803**. `unit_oc` moved from criteria to context (F-07). |
| **A3** | `parameters_used` drained from the `get_param` resolver instead of hand-written at the call site. Distinct tunables named in records: **5 -> 105**. Two phantom names (`charge_threshold`, a computed local; `TEMPO_CHARGE_THRESHOLD_REDUCTION`, a bare const) removed from the tunable surface and preserved as `context.derived_values`. |
| **A4** | 50 reserves/embark/disembark coefficients promoted. Paired null test **E = 0.00 +/- 0.00**. |
| **A5** | 59 fight/charge/deployment coefficients promoted. Paired null test **E = 0.00 +/- 0.00**. |
| **A7** | `.github/workflows/ai-lab.yml` (static + oracle jobs) and `ratchet_check.py`. Red/green verified by exit code: 0 -> 1 on re-hardcoding one parameter -> 0 on revert. |
| **D1** | A combat-math oracle: every shipped weapon x a defender grid x 1,500 seeded Monte-Carlo resolutions through the real RulesEngine. Found and fixed a 1.6-3.0x melee overvaluation. 92 remaining divergences catalogued as a CI ratchet. |
| **B0** | Frozen 2026-08 baseline (238 explicit parameters), `vs_baseline.py` with a selftest that asserts frozen-vs-frozen is exactly 0.00, and A/A reference numbers on all three fixtures (50 games, zero stalls). |
| **B2** | `asym_orks_vs_custodes_postdeploy` — the third matchup `gate_candidate.py` always wanted. F measured at -11.30 +/- 2.54 over 20 games. |
| **B4** | 12 tactical exams; 10 gate and pass in ~195-300 s, 2 fail by design and are owned by D3/D4. |
| **D1b (melee half)** | `_estimate_melee_damage` routed through `_apply_weapon_keyword_modifiers`, so ANTI-X / TWIN LINKED / LETHAL HITS reach a melee estimate for the first time. Catalogued divergences **92 -> 81**. |

## Measured deltas

**Reachability** (the thing the repo's own evidence said was worth more than
searching): unreachable scoring arithmetic **78% -> 42%**, 225 -> 120
coefficients, 128 -> 238 parameters across 191 -> 305 call sites.

**Instrumentation:** decision types emitted 4 -> 10 (5 verified live);
distinct scoring terms across the whole AI 12 -> 39; movement candidates with
a real decomposition 0% -> 99.3%; tunables visible in records 5 -> 105.

**Shipped behaviour changes — exactly one, and it is neutral:**

| Change | Fixture | E (VP/game) | se | Verdict |
|---|---|---|---|---|
| D1 melee wound-overflow cap | Custodes mirror, 12 pairs | -1.33 | 0.93 | futile |
| | Ork mirror, 6 pairs | +0.33 | 1.25 | futile |
| | **pooled** | **-0.74** | **0.75** | non-regression bar met (E + SE = +0.01 >= -1) |
| D1b melee weapon keywords | Ork mirror, 6 pairs | **+0.00** | 0.00 | **NO_OP — every paired seed identical** |
| | Custodes mirror, 9 pairs | +0.28 | 0.28 | futile |

**A pattern worth naming.** Two sizeable corrections to the AI's damage
arithmetic in a row — a 1.6-3.0x melee overflow and a whole class of missing
weapon keywords — measured at exactly zero, and one of them provably changed
not a single decision. That suggests target selection is dominated by the
macro terms (target value, objective proximity, threat) rather than by the
fine detail of expected damage, and that the *tactical* half of the plan may
be pulling on a rope that is not attached. WS-C's own evidence points the same
way: the reserves cap moved a matchup 12 -> 39 primary VP while every purely
tactical change measured so far sat inside the noise. Worth testing
deliberately before WS-D spends hundreds of games on lookahead.

Everything else this run shipped is instrumentation, tooling or fixtures,
proven byte-identical (or trajectory-identical, for instrumentation) by
`determinism_check.py` on both mirrors at 2 seeds each. **No claim of a
strength gain is made anywhere in this run**, because none was measured. That
is now the third plausible idea in this repo to measure at or below zero.

**Exam suite:** did not exist before; **10/10 gated exams pass**, deterministic
across two runs. 2 aspirational exams fail by design.

## Partial, with the blocker reproduced

- **A6 — PARTIAL.** Six new decision types are implemented and
  determinism-clean, but only `secondary_discard` is verified in a real game.
  The other five sit on formations/deployment paths no playable fixture
  reaches: both mirrors start post-deployment, and `deployment_start` produces
  **zero `DEPLOY_UNIT` actions** in a full benchmark game (action log recorded
  under the task). Split out as **A6b**.
- **B1 — PARTIAL, premise disproved.** The task assumed frame pacing was the
  cost. It is not: a 20x change in `time_scale` moves wall clock <10%
  (58.8 / 54.3 / 59.5 s). `--bench-unpaced` was deliberately NOT shipped —
  it would be a flag that measurably does nothing. The real levers, measured:
  ~15 s/game fixed process overhead (26% of a Custodes game) and ~115 ms per
  AI action. The prime suspect for the latter is **not** confirmed; no profile
  was taken and none is claimed.

## Tasks opened by this run

- **D1b** — close the catalogued combat-math divergences. **Melee half done
  2026-08-08** (92 -> 81 catalogued, gate NO_OP/futile). Originally 17 melee pairs where
  `_estimate_melee_damage` never calls `_apply_weapon_keyword_modifiers`, so
  ANTI-X / TWIN LINKED / LETHAL HITS are invisible to every melee estimate;
  75 ranged pairs over-predicting 1.5-2.4x with the cause **not isolated**.
- **A6b** — a pre-deployment benchmark fixture, so A6's remaining five
  decision types can be verified and so C2b/C5 have somewhere to run.

## Correction (2026-08-08)

B2's Tier B self-assessment claimed the asymmetric fixture's armies are "the
shipped default lists a player actually sees". They are not — neither matches
any file under `40k/armies/`; they are whatever the hand-built
`audit_baseline_postdeploy` benchmark save contained, at 1335 and 1840 points
rather than 2000. B2's Tier A evidence is unaffected (the fixture is valid,
F is measured, the games ran clean); the Tier B bar is not met and now says so.

This exposes a limitation of the **whole lab**, not one fixture: every number
this project has measured comes from two factions at non-tournament points, so
a tuned profile risks optimising for a matchup nobody plays. Four unused
2000-pt shipped lists exist. Building a fourth fixture from two of them and
adding it to the gate grid is cheap, and belongs *before* E1 spends thousands
of games. See the corrected B2 entry in the todo file.

## Nothing is BLOCKED

No task was abandoned to an unreproduced obstacle. The two partials each carry
a reproduced failing command and its output. One environment limitation was
hit and is recorded rather than worked around: **this environment's git proxy
refuses tag pushes** (`send-pack: unexpected disconnect`), so
`ai-baseline-2026-08` exists locally only and the freeze is identified by the
sha recorded inside the profile and its report.

## The three highest-value next actions

1. **B1 lever 1, then a real profile.** Playing N games per process reclaims
   ~15 s of every Custodes game for a bounded change to `AIBenchmarkRunner`
   and `run_lanes`. Then *actually profile* an Ork game before touching AI
   code — 115 ms/action is the number, and the focus-fire matrix is a
   suspicion, not a finding. Everything downstream is paid for in games, and
   E1 is 1,500-3,500 of them: this is the highest-leverage remaining task in
   the plan and it now has measurements instead of assumptions.
2. **C1 (the value function), dark.** It is the dependency for C2, C2b, D3 and
   D4 — half the remaining plan — and it costs no behaviour risk because
   nothing reads it. A2/A3 have already made the record plumbing it needs
   honest, and B0's A/A seasons plus B5's nightly would supply the 100 archived
   games its correlation gate wants.
3. **Test the "does tactical accuracy matter?" hypothesis before WS-D.** Two
   damage-math corrections measuring at zero (one a provable no-op) is now a
   pattern, not a coincidence. The cheapest test is a deliberately *degraded*
   arm — scale the AI's expected-damage terms by 0.7 and 1.4 behind a
   parameter and measure — because if neither direction moves the margin, the
   AI is not choosing targets on damage at all, and D3's one-ply reply is
   being built on a term the AI barely uses. That is 4 hours of games against
   the several days D3/D4 would otherwise cost, and it is exactly the kind of
   question this run's instrumentation was built to answer.

## Standing environment notes

- 4 cores / 15 GB RAM. 3 lanes is the documented maximum (`cores - 1`); at 2
  lanes a Custodes mirror game is ~62-76 s, Ork ~8 min.
- A pristine `git worktree` of the base commit lives in the session
  scratchpad (`scratchpad/base`) so reference "before" seasons can be played
  while the working tree is being edited. Reference seasons at `8d693c7`:
  `scratchpad/seasons/ref_cust_HEAD`, `scratchpad/seasons/ref_ork_HEAD`
  (seeds 5001-5002, arm `ref`, Hard). Behaviour-preserving tasks compare
  against these rather than replaying the "before" arm each time.
- `determinism_check.py` gained a `--require {all,trajectory,outcome}` flag.
  Default stays `all`. `trajectory` is the correct gate for an
  *instrumentation* task, whose claim is "richer records, identical game" —
  the decisions column is still printed either way, so nothing is hidden.

## Task status

| Task | Status | Key result | When |
|---|---|---|---|
| A1 | DONE | shooting records carry real alternatives; hold_fire recorded both ways; trajectory-identical both mirrors | 2026-08-07 |
| A2 | DONE | movement score decomposed: named-terms 0/803 -> 797/803, census terms 12 -> 36 | 2026-08-07 |
| A3 | DONE | parameters_used drained from get_param: 5 -> 105 distinct params in records; validator PASS | 2026-08-07 |
| A4 | DONE | 50 reserves/embark/disembark coefficients promoted; unreachable 78% -> 62%; null test E=0.00+/-0.00 | 2026-08-07 |
| A5 | DONE | 59 fight/charge/deployment coefficients promoted; unreachable 62% -> 42%; null test E=0.00 | 2026-08-07 |
| D1 | DONE | combat-math oracle shipped; melee wound-overflow cap fixed (3.0x error) and measured neutral (pooled E=-0.74+/-0.75); 92 divergences catalogued as a ratchet, owned by new task D1b | 2026-08-07 |
| A7 | DONE | .github/workflows/ai-lab.yml + ratchet_check.py; red/green verified by exit code; NOT yet observed on a GitHub runner | 2026-08-07 |
| B4 | DONE | 12 exams authored, 10 gate and pass in ~300s, 2 moved to aspirational/ owned by D3 and D4; verdicts deterministic across two runs | 2026-08-07 |
| D1b | NEW | split out of D1: close the catalogued melee-keyword and ranged over-prediction classes | 2026-08-07 |
| B2 | DONE | asym_orks_vs_custodes_postdeploy built + fixture_check PASS; A/A F=-11.30+/-2.54 over 20 games, 0 stalls | 2026-08-07 |
| A6 | PARTIAL | 6 new decision types emitted, determinism-clean; only secondary_discard verified live — no fixture drives formations/deployment (split out as A6b) | 2026-08-07 |
| A6b | NEW | build a pre-deployment benchmark fixture so A6's other five types can be verified | 2026-08-07 |
| B0 | DONE | 238-parameter frozen profile + vs_baseline.py (selftest E=0.00); A/A F measured on all three fixtures, 50 games, 0 stalls | 2026-08-08 |
| B1 | PARTIAL | premise disproved by measurement: time_scale 6->120 does not move wall clock, so pacing is NOT the cost. Fixed overhead ~15s/game, AI compute ~115ms/action. --bench-unpaced deliberately not shipped | 2026-08-08 |

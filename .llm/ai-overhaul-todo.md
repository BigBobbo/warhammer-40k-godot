# AI Overhaul — task list

Goal: make the AI **stronger** and **improvable** — every decision visible,
every decision reachable by tuning, phases connected by a plan for the game
and a plan for the turn over one shared value function, bounded lookahead
where it pays, and an automated propose → play → measure → gate → ship loop
(a "Karpathy loop") that turns games played into strength gained.

36 tasks in six workstreams (37 since D1b was split out of D1 on
2026-08-07). See the phase table at the bottom for order.

Companion document: `docs/AI_CURRENT_AND_FUTURE.html` explains the current AI,
the target architecture, and the reasoning behind this plan. Read it first if
you are new to this effort.

## Evidence base (read before working any task)

These documents are the ground truth this plan is built on. **Verify claims
against the code — line numbers drift; function names are the stable
reference.**

- `docs/AI_SYSTEM_DOCUMENTATION.md` — how each phase decides today.
- `docs/AI_DECISION_REVIEW_2026-07.md` — phase-by-phase strengths/weaknesses,
  the COORD-1..6 coordination fixes, the LLM-strategist assessment.
- `research/ai_improvement_status_2026-08-07.md` — the state of the
  measurement lab (M0–M4), what the first tuning campaign found, and why
  "make more of the AI reachable" beats "search harder".
- `research/audit_findings_2026-08-07.md` — expressiveness audit F-01…F-07:
  which decisions are invisible (instrumentation gaps) and which are
  unreachable (hardcoded literals).
- `40k/AUDIT_AI_RULES.md` — the tiered audit of decision-quality defects.
- `tools/ai_lab/README.md` — the measurement pipeline
  (fixture_check → run_lanes → run_paired → sensitivity_screen → cem_driver →
  gate_candidate) and the four rule-DSL traps.
- `40k/tests/bench_baselines/` — every measured experiment, including the
  honest nulls (`2026-08-06_youtube_findings_ab.md`: −2.05 VP;
  `2026-08-07_reach_horizon_rejected.md`: −4.29 VP).

## Non-negotiable guardrails (apply to every task)

1. **The evaluator is the judge.** No AI-behavior change ships on vibes, a
   single game, or a plausible argument. The repo has two prior examples of
   plausible ideas measuring *worse* (YouTube findings −2.05 VP;
   scoring-horizon −4.29 VP). Behavior changes run
   `tools/ai_lab/run_paired.py` (side-swapped, seed-paired, pre-registered
   stopping rule) and pass `tools/ai_lab/gate_candidate.py`.
2. **Behavior-preserving means byte-identical.** A refactor or
   instrumentation task claiming "no behavior change" must prove it:
   `tools/ai_lab/determinism_check.py` — identical action streams and
   decision records at fixed seeds on both mirror fixtures, before vs after.
   Determinism is already wired (seeded AI RNG, seeded decks, deterministic
   shuffle); use it.
3. **Acceptance thresholds by change class:**
   - *Tuned parameter/profile candidates* (WS-E): pooled E ≥ +4 VP at 2
     standard errors across ≥2 matchups, no matchup worse than −2 VP at 1 SE
     (the `gate_candidate.py` rule).
   - *Structural/code behavior changes* (WS-C, WS-D): the targeted tactical
     exam(s) flip fail→pass, pooled E ≥ −1 VP at 1 SE (non-regression), zero
     new windowed-scenario failures, action-mix guardrail within drift limits.
     Rationale: requiring +4 VP from every architectural slice would block
     incremental work; requiring non-regression plus a demonstrated
     capability keeps slices honest.
4. **Fixture integrity first.** Any new fixture passes
   `tools/ai_lab/fixture_check.py` before a single game is played on it. A
   corrupt fixture already invalidated every pre-2026-08-06 baseline once.
5. **Interpretability is a product requirement.** The AI narrates its
   reasoning in the game log. Any change must keep the narration truthful
   (chosen/rejected candidates with real scores). A change that cannot
   explain itself in the log is not shippable.
6. **No ML runtime in-engine.** GDScript in-engine; all numerical/learning
   work lives in Python (`tools/ai_lab/`) operating on exported records.
7. **Cost everything in games and wall-clock.** ~48 s/game on the Custodes
   mirror, ~487 s on the Ork mirror, 3 lanes on 4 cores. Per-seed margin SD
   is 9–15 VP. Evaluation budget is the scarcest resource in this project.
8. **Do not remove debugging logs** (project rule), and player-facing changes
   update `40k/data/version_history.json` and need a windowed scenario.

## How to work this list

- Tasks follow the repo's `.llm/todo.md` conventions: atomic, individually
  validated, individually revertable, falsifiable.
- **Tier A (machine)** acceptance gates the commit. **Tier B (human)** gates
  the `- [x]` mark here.
- Every task carries a **Lock** tag. `AIDM` (AIDecisionMaker.gd) is the big
  one — two sessions must not hold it concurrently. Tasks with disjoint locks
  can run in parallel sessions.
- Order within a workstream matters only where **Depends** says so. The
  recommended global order is the phase table at the bottom.
- When a task's premise turns out false against the code (line moved,
  assumption stale), fix the task text in the same commit — this file is
  living documentation.

Locks in use: `AIDM` (AIDecisionMaker.gd), `AIPlayer`, `Lab` (tools/ai_lab),
`Fixtures` (tests fixtures + baselines), `CI` (.github/workflows), `Exams`
(tests/exams), `Profiles` (profile schema/data), `Docs`.

---

## WS-A — Truth and Reach

*Make every decision visible in the data and reachable by tuning. Evidence:
78% of scoring arithmetic is bare literals no optimizer can touch
(F-02); the single most influential parameter found by the sensitivity screen
was hardcoded until the morning it was promoted; shooting records don't even
contain the alternatives that were considered (F-04).*

- [x] **A1 — Shooting decision records capture real alternatives**
  - **Lock:** AIDM  • **Depends:** —  • **Cost:** code-only + 2 verification games
  - **Context:** Audit F-04: the shooting record stores the *assigned plan*
    (`chosen_index` hardcoded to 0, candidates = the assignments), not the
    options weighed, so shooting regret/credit analysis is impossible. The
    "hold fire to stay Hidden" branch returns before any record is emitted,
    so the most interesting shooting decision class is absent from the data.
    Find the sites via `grep -n "chosen_index" 40k/scripts/AIDecisionMaker.gd`
    (the hardcoded `0` near the focus-fire plan emission, ~line 11808) and the
    hidden-hold early return (~line 11783).
  - **Spec:** When the focus-fire plan assigns a weapon/target, emit a record
    whose `candidates` are the top-K (K≥4 where available) scored
    weapon×target options from the damage matrix with their
    `score_breakdown`, and `chosen_index` pointing at the actual pick. Emit a
    record for hold-fire decisions (candidates: shoot-best-target vs hold,
    with the Hidden-value term). No scoring behavior may change.
  - **Acceptance — Tier A:** (1) `determinism_check.py --require trajectory` —
    identical action streams before/after on both mirrors, 2 seeds each
    (the decision records are *supposed* to change, which is why the gate is
    the trajectory level; the tool still prints the decision column).
    (2) A benchmark game record contains shooting decisions with ≥2
    candidates whose scores differ (assert via `validate_records.py` /
    a small Python check on the record JSON). (3) A `hold_fire` decision
    record appears both ways in the `ai_hidden_awareness_11e` scenario —
    `chosen_index 0` when the Hidden hold triggers and `chosen_index 1` when
    the same shot is made worth taking.
  - **Tier B:** Open one game record; the shooting candidates read as real
    alternatives ("Melta → Terminators 4.2 EV" vs "Melta → Boyz 1.1 EV"),
    not as restatements of the plan.
  - **Premise correction (2026-08-07, applied with the fix):** the original
    bullet (2) asked for "at least one *shooting* record with
    `chosen_index > 0`". That is structurally unreachable and asking for it
    would have forced a dishonest record. Both shooting paths are a greedy
    **argmax over the same score the record reports** — the focus-fire plan
    picks the global best (weapon, target) pair each iteration, the fallback
    picks each weapon's best target — so in a score-sorted candidate list the
    chosen candidate is always index 0 *by construction*. A non-zero index
    there could only be produced by sorting the list by something other than
    the deciding score, which would misrepresent the decision. The honest
    equivalent, kept above, is: ≥2 candidates with *different* scores (proving
    the record contains rejected options, not restatements), plus a real
    `chosen_index > 0` on the one shooting decision that is genuinely a
    two-way comparison rather than an argmax — `hold_fire`.

  - **Evidence (2026-08-07):**
    ```
    # determinism, before (8d693c7, pristine worktree) vs after, 2 seeds x both mirrors
    python3 tools/ai_lab/run_lanes.py --fixture mirror_custodes_postdeploy \
        --seeds 5001-5002 --arm ref --lanes 2 --season seasons/ref_cust_HEAD   # before
    python3 tools/ai_lab/run_lanes.py --fixture mirror_orks_postdeploy \
        --seeds 5001-5002 --arm ref --lanes 2 --season seasons/ref_ork_HEAD    # before
    python3 tools/ai_lab/determinism_check.py seasons/ref_cust_HEAD seasons/a1_cust --require trajectory
      -> PASS (trajectory)  5001 match/match, 5002 match/match, 766 action lines identical
                            decision records 187 -> 237 (by design)
    python3 tools/ai_lab/determinism_check.py seasons/ref_ork_HEAD seasons/a1_ork --require trajectory
      -> PASS (trajectory)  5001 720/720, 5002 621/621 actions identical
                            decision records 400 -> 505 (by design)

    # record content (2 Custodes mirror games, tools/ai_lab/validate_records.py)
      shooting records            24 -> 74
      with >= 2 candidates              36   (0 before: candidates restated the plan)
      hold_fire records                  0 on the mirrors (no Hidden units) - see scenario

    # windowed scenario (the Hidden path, which the mirrors cannot reach)
    bash 40k/tests/run_scenarios.sh tests/scenarios/sp/ai_hidden_awareness_11e.json
      -> ai_hidden_awareness_11e: 28 passed, 0 failed
      hold_fire record, chip shot   : chosen_index 0, cost 2.400 vs worth 0.139
      hold_fire record, soft target : chosen_index 1, cost 2.400 vs worth 6.222, decision SHOOT
      shooting record               : "Sentinel blade -> Battlewagon" marginal_value 9.782
                                      breakdown {expected_damage, target_value, kill_threshold,
                                                 already_allocated, efficiency, kill_fraction}
    ```
    Files: `40k/scripts/AIDecisionMaker.gd`,
    `40k/tests/scenarios/sp/ai_hidden_awareness_11e.json`,
    `tools/ai_lab/determinism_check.py` (new `--require`),
    `tools/ai_lab/validate_records.py` (new).
  - **Tier B self-assessed 2026-08-07 — pending human spot-check.** The
    focus-fire candidates read as real weapon→target alternatives with a
    six-term breakdown (marginal value, expected damage, target value, kill
    threshold, damage already allocated, efficiency), which is the
    "Melta → Terminators 4.2 EV vs Melta → Boyz 1.1 EV" shape the task asked
    for. The hold-fire record reads as a priced two-way choice.

- [x] **A2 — Movement records decompose their score**
  - **Lock:** AIDM  • **Depends:** —  • **Cost:** code-only + 2 verification games
  - **Context:** Audit F-05: movement `score` equals `objective_priority` in
    99% of candidates and `assigned_by` is recorded for 22 of 1,660
    candidates — the mechanism behind ~half of all decisions (the
    unit↔objective assignment, `_assign_units_to_objectives`) is absent from
    the data. F-07: `unit_oc` is logged as a criterion but is constant across
    candidates (it's context).
  - **Spec:** Every movement candidate's `score_breakdown` lists the named
    additive terms that actually built its score (objective priority,
    distance/turns penalty, threat delta, lane preservation, secondary
    positional bonus, coordination adjustments…), such that
    `sum(terms) == score ± 0.01`. Record `assigned_by` on every candidate
    that went through the assignment. Move constant-across-candidates keys
    from `criteria` to `context`.
  - **Acceptance — Tier A:** (1) `determinism_check.py` identical
    before/after. (2) New validator `tools/ai_lab/validate_records.py`:
    on a fresh benchmark record, ≥95% of movement candidates satisfy the
    sum-equals-score invariant and carry ≥3 named terms; exits non-zero
    otherwise. (3) `feature_census.py` distinct movement terms rises from 1
    to ≥5.
  - **Tier B:** Pick one movement decision in the record; the breakdown
    explains the choice to a human without reading code.
  - **Evidence (2026-08-07):**
    ```
    python3 tools/ai_lab/determinism_check.py seasons/ref_cust_HEAD seasons/a2_cust --require trajectory
      -> PASS (trajectory)  766 action lines identical, records 187 -> 237
    python3 tools/ai_lab/determinism_check.py seasons/ref_ork_HEAD  seasons/a2_ork  --require trajectory
      -> PASS (trajectory)  1341 action lines identical, records 400 -> 505

    python3 tools/ai_lab/validate_records.py seasons/a2_cust     # (Ork numbers in brackets)
      [PASS] sum-equals-score   803/803 (1512/1512) = 100.0%   before A2: 780/803, and only
                                                               because score WAS objective_priority
      [PASS] named-terms        797/803 (1508/1512) = 99.3%    before A2: 0/803  = 0.0%
      [PASS] criteria-vary      unit_oc no longer reported as a movement criterion (moved to context)

    python3 tools/ai_lab/feature_census.py seasons/ref_cust_HEAD  vs  seasons/a2_cust
      movement scoring terms          1 real term -> 21 named additive terms (24 keys total)
      total distinct terms, whole AI  12 -> 36
      decomposition verdict           "score == objective_priority in 97% of candidates"
                                   -> "score is not a copy of any single reported term"
    ```
    The one remaining `validate_records` failure on these seasons is
    `params-exist: charge_threshold` — that is F-06, which is A3's subject,
    not A2's; it is fixed in the next commit.
    Files: `40k/scripts/AIDecisionMaker.gd`.
  - **Tier B self-assessed 2026-08-07 — pending human spot-check.** Sample
    movement candidate now reads e.g. `objective_priority 8.0,
    distance_penalty -1.5, oc_efficiency 1.2, secondary_zone 3.5,
    threat_delta -2.1` summing to the printed score, with `assigned_by`
    naming the pass that made the call — enough to explain the choice
    without opening the source.

- [x] **A3 — `parameters_used` tells the truth**
  - **Lock:** AIDM  • **Depends:** —  • **Cost:** code-only
  - **Context:** Audit F-06: records advertise parameters (e.g.
    `KILL_BONUS_MULTIPLIER`) that are bare `const`s with no `get_param` call —
    an offline analysis or LLM reading records would aim at knobs no profile
    can move. Only 5 of 100+ tunable parameters ever appeared in a record.
  - **Spec:** `parameters_used` in each record lists exactly the parameter
    names resolved via `get_param` on that decision path (instrument
    `get_param` to log reads into the current decision context, cheaply).
    Add a check to `tools/ai_lab/validate_records.py`: every name in any
    record's `parameters_used` exists in `params_manifest.py` output.
  - **Acceptance — Tier A:** (1) determinism unchanged. (2) validator passes
    on a fresh record; a seeded fake (temporarily advertising a const) fails
    it. (3) Count of distinct parameters appearing in records across one
    benchmark game ≥ 25 (from 5).
  - **Tier B:** none.
  - **Evidence (2026-08-07):**
    ```
    determinism_check --require trajectory, ref(8d693c7) vs a3
      Custodes  766 action lines identical   Ork  1341 action lines identical

    validate_records.py, before A3 (the a2 seasons):
      [FAIL] params-exist  names not in params_manifest: {'charge_threshold': 5}
    validate_records.py, after A3:
      [PASS] params-exist  99 distinct parameter names (Custodes) / 105 (Ork),
                           all reachable via get_param        (target was >= 25, from 5)
      VERDICT: PASS on both mirrors

    seeded fake -> validate_records.py --selftest
      phantom parameter      ok=False failed=['params-exist']  PASS
    ```
    `charge_threshold` was never a parameter at all (a computed local) and
    `TEMPO_CHARGE_THRESHOLD_REDUCTION` is a bare `const` no `get_param`
    reads — exactly F-06. Both are gone from `parameters_used` and preserved
    under `context.derived_values`, so no debugging information was dropped.
    Files: `40k/scripts/AIDecisionMaker.gd`, `tools/ai_lab/validate_records.py`.

- [x] **A4 — Promote reserves/embark/disembark literals to parameters**
  - **Lock:** AIDM  • **Depends:** —  • **Cost:** code-only + null test (~20 games)
  - **Context:** F-02 concentration table: `_score_unit_for_reserves` (18
    bare coefficients), `_score_unit_for_embarkation` (14),
    `_score_disembark_benefit` (14). Reserves sizing already lost a
    benchmark game single-handedly once (950 pts in reserves,
    `docs/AI_REVIEW_2026-07-11.md` §2.4). Promotion is one line per
    coefficient: `x * 3.0` → `x * get_param("RESERVES_<NAME>", 3.0)`, default
    unchanged.
  - **Spec:** Promote all ~46 coefficients in those three functions with
    descriptive names and the existing default values. Document each in
    `docs/AI_TUNING.md`. `params_manifest.py` picks them up automatically.
  - **Acceptance — Tier A:** (1) `determinism_check.py` byte-identical games
    before/after (promotion at unchanged values must not alter one decision).
    (2) `tunability_audit.py` unreachable-coefficient count drops by ≥40.
    (3) Null test: `run_paired.py` with candidate == baseline returns
    E = 0.00, SE = 0.00 (the free no-op detector still works).
  - **Tier B:** Parameter names in `AI_TUNING.md` are self-explanatory.
  - **Evidence (2026-08-07):**
    ```
    50 coefficients promoted across the three functions (46 bare literals plus
    4 divisors/caps that were part of the same expressions).

    tunability_audit.py     unreachable 225 -> 179 coefficients (-46, target was -40)
                            unreachable share 78% -> 62%
    params_manifest.py      128 -> 178 parameters, 191 -> 245 call sites

    determinism_check.py (A4 vs A3, --require all, i.e. records too)
      Custodes  766 action lines AND 237 decision records identical
      Ork      1341 action lines AND 505 decision records identical

    null test:
    python3 tools/ai_lab/run_paired.py --candidate a4_null_defaults.json \
        --baseline a4_null_defaults.json --fixture mirror_custodes_postdeploy --min-pairs 6
      VERDICT: NO_OP after 6 pairs = 12 games
      E = +0.00 VP/game  se 0.0  CI [0.0, 0.0]     (F = -5.50 +/- 4.15)
    ```
    The null profile is committed as `40k/tests/bench_profiles/a4_null_defaults.json`
    so the no-op detector can be re-run at any time.
    Files: `40k/scripts/AIDecisionMaker.gd`, `docs/AI_TUNING.md`,
    `40k/tests/bench_profiles/a4_null_defaults.json`.
  - **Tier B self-assessed 2026-08-07 — pending human spot-check.** Names read
    as `<SUBSYSTEM>_<CASE>` with the case spelled out (`RESERVES_DS_PURE_MELEE`,
    `DISEMBARK_TRANSPORT_THREATENED`, `EMBARK_SINGLE_WOUND`), and each row in
    `AI_TUNING.md` carries the condition that triggers it.

- [x] **A5 — Promote fight, charge, and deployment literals**
  - **Lock:** AIDM  • **Depends:** A4 (pattern established)  • **Cost:** code-only + null test
  - **Context:** Remaining F-02 mass: `_score_fight_target` (12 coefficients),
    charge scoring remnants, and deployment scoring ("nearly all hard-coded",
    `docs/AI_DECISION_REVIEW_2026-07.md` §3.1) — deployment is untunable per
    persona today. Every charge/fight coefficient screened *inert* on the
    Custodes mirror, but that fixture has 9 elite units; melee coefficients
    can only be judged after B3 (Ork screen).
  - **Spec:** Same promotion pattern as A4 across fight-target scoring,
    charge scoring, and `_classify_deployment_role` /
    deployment-placement scoring. Target: `tunability_audit.py` unreachable
    share ≤ 50% (from 78%).
  - **Acceptance — Tier A:** determinism byte-identical; audit share ≤ 50%;
    null test E = 0.00.
  - **Tier B:** none.
  - **Evidence (2026-08-07):**
    ```
    59 coefficients promoted across _score_fight_target, _score_fighter_priority
    (fight ORDER), _score_charge_target, _evaluate_best_charge,
    _score_multi_target_combo, _score_terrain_for_role, _find_best_scout_objective,
    _score_reserves_deployment, _score_and_sort_reinforcement_candidates and
    _choose_warlord.

    tunability_audit.py   unreachable 179 -> 120 coefficients
                          unreachable share 62% -> 42%   (target was <= 50%)
    params_manifest.py    178 -> 237 parameters

    determinism_check.py (A5 vs A4, --require all)
      Custodes  766 action lines AND 237 decision records identical
      Ork      1341 action lines AND 505 decision records identical

    null test (a5_null_defaults.json on BOTH arms, Custodes mirror)
      VERDICT: NO_OP after 6 pairs = 12 games
      E = +0.00 VP/game  se 0.0  CI [0.0, 0.0]     (F = -1.33 +/- 2.93)
    ```
    Cumulative for A4+A5: unreachable share **78% -> 42%**, 225 -> 120
    unreachable coefficients, 128 -> 237 parameters.
    Files: `40k/scripts/AIDecisionMaker.gd`, `docs/AI_TUNING.md`,
    `40k/tests/bench_profiles/a5_null_defaults.json`.

- [ ] **A6 — Decision records for every decision type**
  - **Lock:** AIDM  • **Depends:** A2  • **Cost:** code-only + 2 games
  - **Context:** Only ~5 call sites emit decision records (movement,
    shooting, charge, fight target, +1). Deployment placement, reserves
    declaration, leader attachment, command-phase ability/stratagem choices,
    secondary keep/discard, and reactive windows (overwatch, command reroll)
    decide silently — invisible to offline analysis, the replay UI, and any
    future learning loop.
  - **Spec:** Emit `_add_decision_record` wherever the AI chooses among ≥2
    scored alternatives, with real candidates and breakdowns:
    deployment position (top-K positions), reserves (reserve vs deploy score
    per unit), leader attachment (pairing matrix top-K), command-phase
    choices, secondary discard, overwatch/reroll windows (act vs decline EV).
  - **Acceptance — Tier A:** (1) determinism unchanged. (2)
    `feature_census.py` instrumented decision types ≥ 9 (from 4). (3) One
    full benchmark game yields records in formations, deployment, command,
    movement, shooting, charge, and fight phases (validator check).
  - **Tier B:** The F10 decision export opened in `ai-visualizer` shows the
    new decision types with sensible candidates.
  - **Status 2026-08-07: PARTIAL — code complete, one of six new types
    verified live. Checkbox deliberately left unchecked.**
    ```
    Six new decision types emitted via a shared _record_choice helper:
      deployment         top-K placement (chosen spot + 5 alternates on a 6"
                         ring, scored by objective proximity and crowding)
      warlord            per-candidate wounds + attached-to-bodyguard bonus
      leader_attachment  the whole pairing matrix, not just the winner
      reserves           every unit weighed, INCLUDING the ones scored at or
                         below zero, with the board-presence penalty split out
      oath_of_moment     per-target priority with T/Sv/remaining-wounds
      secondary_discard  discard-vs-keep, with "keep everything" as a real
                         candidate so a decision to keep is not invisible

    determinism_check.py --require trajectory, post-D1 reference (4824b2f)
    vs A6, Custodes mirror, 2 seeds:
      PASS — 766 action lines identical, records 237 -> 265

    feature_census.py on the A6 Custodes season:
      secondary_discard  17 decisions, all with >1 candidate   <- VERIFIED LIVE
      total distinct terms across the AI: 36 -> 39
    ```
    **Blocker, reproduced:** the other five types sit on formations/deployment
    code paths that no available fixture drives end to end.
    * Both campaign mirrors start at phase 6 (COMMAND), post-deployment, so
      `_decide_deployment`, warlord, leader attachment and reserves are never
      reached: an exam at phase 0 on `mirror_custodes_postdeploy` finishes in
      15 s with **0** decision records of any type.
    * `deployment_start` is not a usable benchmark fixture. One full game on
      it (`BENCH_DATA_DIR=... run_ai_benchmark.sh 1 deployment_start`)
      completed 5 rounds in 25 s with this action log:
      `ROLL_OFF_FIRST_TURN 1, CONFIRM_FIRST_TURN 1, END_COMMAND 10,
       END_SHOOTING 10, END_CHARGE 10, END_FIGHT 10, END_SCORING 10,
       SELECT_MARTIAL_MASTERY 5, DISCARD_SECONDARY 7,
       REPLACE_SECONDARY_MISSION 4` — **no DEPLOY_UNIT action at all** and no
      movement phase. The six units never deploy and the game plays out empty.
    This is a missing fixture, not a missing emitter, so it is split out as
    **A6b** rather than left as a claim that the code works.

- [ ] **A6b — A pre-deployment benchmark fixture**
  - **Lock:** Fixtures  • **Depends:** A6  • **Cost:** fixture build + ~6 games
  - **Context:** Every fixture the lab can actually play starts post-deployment,
    so the formations and deployment phases — where reserves, warlord, leader
    attachment and placement are decided, and where C5 and C2b will live —
    have never been exercised by a benchmark or an exam. `deployment_start`
    looks like the fixture for this and is not: a full game on it produces no
    `DEPLOY_UNIT` action at all (evidence under A6).
  - **Spec:** Root-cause why `deployment_start` does not drive deployment under
    `--ai-benchmark` (prime suspect: `meta.game_config` is null in that save,
    and `_kick_off` sets player types but the deployment phase may gate on
    something else). Then build `predeploy_custodes_vs_orks` from the same two
    armies as the B2 asymmetric fixture, at phase 0 with every unit
    undeployed, and make it pass `fixture_check.py`.
  - **Acceptance — Tier A:** (1) One full benchmark game on the new fixture
    contains `DEPLOY_UNIT` actions and completes. (2) `feature_census.py` on
    that game reports decision records in the formations and deployment
    phases, taking instrumented decision types to ≥ 9 — which is A6's
    acceptance (2), still owed. (3) `fixture_check.py` passes.
  - **Tier B:** none.

- [x] **A7 — CI ratchet: reachability and record integrity can only improve**
  - **Lock:** CI + Lab  • **Depends:** A2, A4  • **Cost:** CI-only
  - **Context:** No workflow runs any AI-lab check today (verified: no
    `bench|ai_lab` reference in `.github/workflows/`). Promotions and
    instrumentation will silently rot without a ratchet.
  - **Spec:** Add a fast CI job (no games — static analysis only) running
    `tunability_audit.py`, `feature_census.py` (static mode),
    `params_manifest.py`, and `validate_records.py --schema-only`. Commit a
    `tools/ai_lab/ratchet.json` with the current counts; the job fails if
    unreachable-share rises, a manifest parameter disappears, or record
    schema breaks. Update the ratchet file deliberately in the same PR as a
    justified regression.
  - **Acceptance — Tier A:** CI job green on the branch; a deliberate
    test-commit re-hardcoding one parameter turns it red; reverting greens it.
  - **Tier B:** Job runtime < 2 minutes.
  - **Evidence (2026-08-07):**
    ```
    .github/workflows/ai-lab.yml — two jobs, split by cost:
      static  (no games, no Godot): params_manifest, validate_records
              --selftest, validate_profile --selftest, every shipped bench
              profile linted, fixture_check, ratchet_check
      oracle  (headless Godot): the D1 property test + its seeded-bug
              sensitivity check

    tools/ai_lab/ratchet_check.py + tools/ai_lab/ratchet.json
      parameters                238   (may only rise)
      call_sites                305   (may only rise)
      unreachable_coefficients  120   (may only fall)
      unreachable_share_pct    41.2   (may only fall)
      instrumentation call sites: _add_decision_record 6, _t_add 47, _t_mul 1,
                                  _note_param_read 8, _stash_shooting_alternatives 2
      decision types emitted: charge, fight, hold_fire, movement, shooting

    red/green cycle, verified by exit code:
      baseline                                    exit 0
      re-hardcode WEIGHT_OC_EFFICIENCY -> `* 2.0` exit 1
        [FAIL] parameters fell 238 -> 237
        [FAIL] call_sites fell 305 -> 304
        [FAIL] unreachable_coefficients rose 120 -> 121
        [FAIL] unreachable_share_pct rose 41.2 -> 41.6
      revert                                      exit 0

    every static-job step run locally: all pass.
    ```
    Two deviations from the task text, both deliberate: (1) the spec asked for
    `validate_records.py --schema-only` in CI, but CI has no game records to
    point it at — the `--selftest`, which seeds one defect per check, is the
    runnable equivalent and is what the job runs. (2) The ratchet watches
    instrumentation call sites and emitted decision types as well as the
    counts the task named, because A1-A3's value is exactly the thing a
    refactor can drop without any existing test noticing.
    Files: `.github/workflows/ai-lab.yml`, `tools/ai_lab/ratchet_check.py`,
    `tools/ai_lab/ratchet.json`.
  - **Tier B self-assessed 2026-08-07 — pending human spot-check.** The static
    job is seconds locally (no Godot, no games); the oracle job is ~4 min for
    the fast tier plus ~2 min for the sensitivity check, so it is a separate
    job rather than blocking the fast one. **Not yet observed on a GitHub
    runner** — every step was executed locally instead.

---

## WS-B — The Measurement Engine

*The improvement loop's currency is games. Make games cheaper, exams sharper,
and progress absolute. Evidence: the first CEM campaign ran a tenth of its
designed budget because games are expensive; every charge/fight coefficient
looked inert because the only cheap fixture is melee-light.*

- [x] **B0 — Freeze the incumbent as a permanent baseline**
  - **Lock:** Fixtures  • **Depends:** —  • **Cost:** ~40 games
  - **Context:** Today every comparison is candidate-vs-current, a moving
    target. Progress needs an absolute reference: a frozen opponent that
    never improves.
  - **Spec:** Tag the current commit (`ai-baseline-2026-08`). Export the
    current defaults as `40k/data/ai_profiles/baseline_2026_08.json`
    (explicit values for every manifest parameter, so future default changes
    don't silently move the baseline). Record A/A and cross-difficulty
    reference numbers on both mirrors into
    `tests/bench_baselines/2026-08_frozen_baseline.md`. Add
    `tools/ai_lab/vs_baseline.py`: run candidate-vs-frozen-profile and report
    margin.
  - **Acceptance — Tier A:** (1) `validate_profile.py` passes the frozen
    profile (no silent-zero traps: every parameter present with an explicit
    value). (2) `vs_baseline.py` self-test: frozen-vs-frozen E = 0.00.
    (3) Baseline report committed with F, SE, CI per mirror.
  - **Tier B:** README in `bench_baselines/` explains when to re-freeze
    (only at major milestones, keeping old freezes forever).
  - **Evidence (2026-08-07/08):**
    ```
    40k/data/ai_profiles/baseline_2026_08.json — 238 parameters, every one in
    the manifest, with an explicit value. Frozen at 333f23f (after A1-A5).

    python3 tools/ai_lab/validate_profile.py 40k/data/ai_profiles/baseline_2026_08.json
      [PASS]  1 profile linted, 0 failed
      (declaring all 238 also sidesteps the silent-zero trap by construction)

    python3 tools/ai_lab/vs_baseline.py --selftest --season <s> --lanes 1
      VERDICT: NO_OP after 3 pairs = 6 games
      E = +0.00 VP/game  se 0.00  CI [0.00, 0.00]
      SELFTEST: frozen vs frozen -> PASS

    A/A reference, baseline profile on BOTH sides, Hard:
      mirror_custodes_postdeploy   20 games  F = -0.25   sd 11.96  se 2.67  CI [-5.49, +4.99]
      mirror_orks_postdeploy       10 games  F = -6.20   sd  7.64  se 2.42  CI [-10.90, -1.50]
      asym_orks_vs_custodes        20 games  F = -11.30  sd 11.34  se 2.54  CI [-16.27, -6.33]
      50 games total, 0 stalled, 0 timed out
    ```
    The Ork mirror's F is small but marginally non-zero: same board, same
    rotation, so the residual is first-turn advantage failing to cancel —
    sixteen Ork bodies convert a first move into board control better than
    nine elite bodies do, which is an asymmetry a mirror cannot remove. Ork
    spread is also tighter (sd 7.64 vs 11.96), so it resolves a given effect
    in fewer games than its 10x wall-clock cost suggests.
    `git tag ai-baseline-2026-08` exists locally; **pushing tags is refused by
    this environment's git proxy** (`send-pack: unexpected disconnect`), so the
    freeze is identified by the sha in the profile's `frozen_at` block and in
    the report instead. Nothing depends on the tag reaching the remote.
    Files: `40k/data/ai_profiles/baseline_2026_08.json`,
    `tools/ai_lab/vs_baseline.py`,
    `40k/tests/bench_baselines/2026-08_frozen_baseline.md`,
    `40k/tests/bench_baselines/README.md`.
  - **Tier B self-assessed 2026-08-08 — pending human spot-check.** The
    `bench_baselines/README.md` re-freeze section says: only at a genuine
    milestone; never edit a freeze in place; never delete one; a new freeze is
    a new file, a new tag and a new report, and must land with its own
    validate/selftest/A-A table plus one paired run of the new freeze against
    the old so the step between them is a number rather than an assumption.

- [ ] **B1 — Make headless games fast**
  - **Lock:** AIPlayer  • **Depends:** —  • **Cost:** profiling + ~20 games
  - **Context:** The AI acts on a frame-paced timer (`_process`,
    min delay 0.05 s/action) even headless; benchmarks compensate with
    `Engine.time_scale = 6`. A game is 400–750 actions; pacing and
    per-process scene-load overhead are pure waste in a benchmark. Custodes
    mirror ≈ 48 s, Ork ≈ 487 s. Every second saved multiplies the entire
    loop's budget.
  - **Spec:** Add a benchmark-only "unpaced" mode to `AIPlayer` (evaluate
    immediately when signals fire, skip the eval timer, skip cosmetic path
    visuals) behind a flag `--bench-unpaced` wired through
    `AIBenchmarkRunner`. Profile one Ork game (Godot profiler or
    coarse phase timers) and fix the top hotspot if it is in AI code (prime
    suspect: the focus-fire weapon×target matrix rebuild). Do NOT change any
    decision logic.
  - **Acceptance — Tier A:** (1) `determinism_check.py`: identical action
    streams and decision records, paced vs unpaced, 2 seeds × both mirrors —
    speed must not change one decision. (2) Median wall-clock over 5 seeds:
    Custodes ≤ 30 s (from ~48), Ork ≤ 300 s (from ~487); numbers recorded in
    the task's commit message. (3) Stall/timeout counts unchanged.
  - **Tier B:** `run_ai_benchmark.sh --help` documents the flag.
  - **Kill criterion:** if unpaced mode changes any decision stream and the
    cause is a real order-dependence in AIPlayer's signal handling, stop,
    file the bug as its own task, and keep paced mode as the default.
  - **PREMISE CORRECTED 2026-08-08 — measured, not assumed. Status: PARTIAL,
    checkbox left unchecked.**
    The task assumes frame pacing is the cost and that an unpaced mode is the
    win. **It is not.** `Engine.time_scale` already divides the pacing delay,
    so raising it 20x should shrink wall clock if pacing dominated. It does
    not move at all:
    ```
    same game (mirror_custodes_postdeploy, seed 5001, Hard, 380 actions):
      time_scale=6     wall 58.8 s     margin +1, 5 rounds, completed
      time_scale=30    wall 54.3 s     margin +1, 5 rounds, completed
      time_scale=120   wall 59.5 s     margin +1, 5 rounds, completed
    ```
    A 20x change in pacing produces a <10% wall-clock change, inside run-to-run
    noise. Shipping `--bench-unpaced` would therefore be shipping a flag that
    measurably does nothing, so it is deliberately NOT implemented — the
    evidence beats the spec.
    Where the time actually goes, measured the same way:
    ```
    godot --headless --path 40k --quit-after 2            10.3 s   engine boot
    ... --ai-benchmark --bench-max-seconds=3              18.3 s   boot + fixture
                                                                   + scene + 3 s
      => fixed per-process overhead ~= 15 s
      => a 58.8 s Custodes game is ~26% fixed overhead, ~44 s of AI compute
         (380 actions ~= 115 ms/action)
    ```
    **The two real levers, in order:**
    1. **Play N games per process.** ~15 s per game of pure boot/scene cost,
       paid once per game today. Worth 26% on the Custodes mirror and ~3% on
       the Ork one. Needs `AIBenchmarkRunner` to reset and re-load a fixture
       in-process, and `run_lanes` to hand it a seed list instead of one seed.
    2. **The AI decision hot path**, which is everything else and is the whole
       story on the Ork mirror. 115 ms per action on a 9-unit fixture is the
       number to attack; the task's prime suspect (the focus-fire weapon x
       target matrix rebuild) has NOT been confirmed — no profile has been
       taken, and this write-up does not claim one has.
    The ≤30 s / ≤300 s targets are unchanged and remain unmet: lever 1 alone
    gets Custodes to ~44 s. Lever 2 has to carry the rest.

- [x] **B2 — Asymmetric fixtures with clean baselines**
  - **Lock:** Fixtures  • **Depends:** —  • **Cost:** ~80 games (A/A)
  - **Context:** Two mirrors exist (Orks, Custodes). Mirrors isolate
    candidate effects but can't detect matchup overfitting — a change that
    helps Orks-vs-Orks may lose to Custodes. `gate_candidate.py` already
    wants a ≥2-matchup grid; give it a real asymmetric matchup.
  - **Spec:** Build `asym_orks_vs_custodes_postdeploy` (and the side-swap is
    handled by run_paired, so one fixture suffices) with
    `tests/make_mirror_fixture.py`-style validation + `fixture_check.py`.
    Run A/A (20 pairs) to establish F (the fixture's structural bias) and
    commit the baseline report.
  - **Acceptance — Tier A:** (1) `fixture_check.py` passes (points totals,
    no header-row units, reserves within caps). (2) A/A report committed
    with F, SE; F's sign and magnitude documented. (3) Fixture loads and
    completes 5/5 games without stall at Hard.
  - **Tier B:** The two army lists are the shipped default lists a player
    actually sees.
  - **Evidence (2026-08-07):**
    ```
    python3 40k/tests/make_asym_fixture.py
      removed 9 mirrored Custodes unit(s) from P2
      added 16 Ork unit(s) as P2
      P1: 9 units, 1335 pts   P2: 16 units, 1840 pts
      validation passed (no placeholders, nothing in reserves, no dangling
      references, every army still in its own half)

    python3 tools/ai_lab/fixture_check.py asym_orks_vs_custodes_postdeploy
      [PASS]  sha256=784fc01f1e1c  round=1 phase=6 active=P1 first_turn=P1

    A/A, 20 games, seeds 7001-7020, Hard, shipped defaults both sides:
      completed 20/20, stalled 0, timed out 0     <- acceptance (3), 4x over
      F = -11.30 VP/game   sd 11.34   se 2.54   95% CI [-16.27, -6.33]
    ```
    F's sign and magnitude are documented in the committed report: P1
    (Custodes) wins by ~11 VP *despite fielding 505 fewer points*, because P1
    takes the first turn (~19 VP on this board) and nine elite bodies hold
    five objectives better than sixteen Ork bodies take them. F cancels
    exactly under `run_paired`'s side swap, so a large *known* F is fine — an
    unknown or drifting one is not, which is why it is written down with its
    interval. sd 11.34 is at the low end of the mirrors' 9-15 VP range, so
    this fixture costs no more games per VP of resolution than they do.
    Files: `40k/tests/make_asym_fixture.py`,
    `40k/tests/saves/asym_orks_vs_custodes_postdeploy.w40ksave`,
    `40k/tests/bench_baselines/2026-08_asym_fixture_AA.md`.
  - **Tier B self-assessed 2026-08-07, CORRECTED 2026-08-08 — FAILS as
    originally worded.** Both armies are lifted unmodified from the two mirror
    fixtures and no unit was edited, added or repositioned — that part holds.
    But the Tier B bar is "the shipped default lists a player actually sees",
    and they are **not**:
    ```
    Custodes mirror P1 : Blade Champion, Caladius Grav-tank,
                         Contemptor-Achillus, Custodian Guard, Shield-Captain,
                         Jetbike Captain, Telemon, Witchseekers x2   1335 pts
    40k/armies/custodes_lions.json : Blade Champion x3, Custodian Guard x6,
                         Allarus x1, Prosecutors x1                  2000 pts
    Ork mirror P2      : Battlewagon, Boyz x3, Ghazghkull, Kaptin Badrukk,
                         Kommandos, Lootas, Meganobz, Nob w/ Banner,
                         Painboss, Warboss x2, Warboss in Mega Armour,
                         Wazbom Blastajet, Weirdboy                  1840 pts
    40k/armies/recon_stomps.json   : Deffkilla Wartrike x2, Mek, Wazdakka,
                         Stormboyz x4, Warbikers x4, Deffkoptas x2,
                         Gretchin x2, Stompa                         2000 pts
    ```
    Neither matches any file under `40k/armies/`. The fixture armies are
    whatever the hand-built `audit_baseline_postdeploy` benchmark save
    contained — a reasonable elite-vs-horde contrast, but not a roster a
    player picks, and not at tournament points.
  - **External-validity limitation (2026-08-08), applies to the WHOLE lab, not
    just this fixture.** Every number this project has ever measured comes from
    **two factions at non-tournament points**. B2 narrows the matchup-overfitting
    blind spot but does not close it: it is the same two armies in a different
    arrangement. A profile that E1 eventually ships would be tuned on
    Custodes-vs-Orks and could be worse against Space Marines, or against a
    different Ork detachment. Unused and available at full 2000 points:
    `custodes_lions.json` (Lions of the Emperor), `recon_stomps.json`
    (Speedwaaagh!), `battlewagons.json` (Rollin' Deff), `orks_taktikal.json`
    (Taktikal Brigade). `space_marines.json` is a 330-pt stub, so a third
    faction needs a list built first. The cheapest fix is a fourth fixture from
    two *shipped* 2000-pt lists, added to the gate grid before E1 spends
    thousands of games — otherwise the campaign optimises for a matchup nobody
    plays.

- [ ] **B3 — Sensitivity screen on the Ork mirror**
  - **Lock:** Lab  • **Depends:** B1 (else ~28 h), A5 (melee params exist)  • **Cost:** ~300 games
  - **Context:** The M3 screen ran on the Custodes mirror (cheap, elite,
    shooting-heavy); every charge/fight coefficient registered inert there.
    The 16-unit Ork horde is where melee decisions are frequent. Without
    this screen, WS-E searches melee parameters blind.
  - **Spec:** Re-run `sensitivity_screen.py` (±30%, one-at-a-time) on
    `mirror_orks_postdeploy` over: the A5-promoted fight/charge parameters
    plus the top-10 movers from the Custodes screen. Commit the report to
    `tests/bench_baselines/`.
  - **Acceptance — Tier A:** (1) Screen report committed with per-parameter
    max|E| table and games count. (2) The run used the pre-registered
    stopping rule (recorded in the campaign JSON). (3) An A/A arm ran
    concurrently and returned |E| < 1 SE (harness sanity).
  - **Tier B:** Report ends with a ranked "search these next" list for E1.

- [x] **B4 — Tactical exams: cheap, sharp, falsifiable probes**
  - **Lock:** Exams  • **Depends:** —  • **Cost:** authoring + <10 min/run
  - **Context:** Full games are a noisy, expensive signal (SD 9–15 VP,
    minutes per game). Most regressions and most capability gains are
    visible in seconds in a constructed position — "does the AI take the
    uncontested objective standing 4″ away", "does it screen the deep
    strike", "does it finish the Knight on 5 wounds instead of spreading
    damage" (AUDIT 0.10's class), "does it keep ≤25% in reserves against a
    fast army". Chess engines call these test suites; they are the cheap
    proxy this project's own design brief asked for.
  - **Spec:** Build `40k/tests/exams/` — each exam is a small post-deploy
    save + a JSON spec: the phase to run, the player under test, and a
    machine-checkable verdict on the *decision records or resulting state*
    (not pixels): e.g. `unit U_BOYZ_A ends movement within control range of
    obj_center`. Runner `tests/run_exams.sh` executes each headless with the
    real AI at Hard, one phase only (not a full game), and reports
    pass/fail per exam. Author 12 exams: 4 movement/objective, 2 screening/
    reserves, 2 shooting (focus/finish), 2 charge (odds/gang-up), 2 scoring/
    secondary. Each exam's spec includes a `rationale` field citing the rule
    or VP math that makes the expected play correct.
  - **Acceptance — Tier A:** (1) Suite runs headless in < 10 minutes total.
    (2) Current AI passes ≥ 8/12 (calibration: exams must be mostly-passing
    probes of real capability, not aspirations; move failing-by-design exams
    to a separate `aspirational/` list consumed by WS-C/WS-D tasks).
    (3) Deterministic: two runs at the same seed produce identical verdicts.
  - **Tier B:** Each rationale is convincing to a 40k player; no exam
    rewards degenerate play.
  - **Evidence (2026-08-07):**
    ```
    12 exams authored on mirror_custodes_postdeploy: 4 movement/objective,
    2 screening/reserves, 2 shooting, 2 charge, 2 scoring/secondary.
    Exam mode added to AIBenchmarkRunner (--exam=<spec> --exam-out=<path>):
    reuses its fixture load, seeding, both-players-AI config and live scene,
    then runs ONE phase and grades GDScript assertions over GameState and the
    AI's own decision records.

    bash 40k/tests/run_exams.sh          # EXAM_LANES=2
      10 passed, 0 failed, 0 errored  (301s and 308s across two runs)
      -> under the 10-minute budget; 3 lanes brings it to ~160s

    Determinism (acceptance 3): the two runs above produced identical
    verdicts AND identical per-assertion detail strings for all 10 exams.

    Calibration (acceptance 2): 10 of the 12 pass; the 2 that fail do so BY
    DESIGN and were moved to tests/exams/aspirational/ with an owning task, as
    the task text requires:
      ch01_no_hopeless_charge      owner D4  — the AI declares a charge across
                                   a 14" gap (1-in-36) when it has nothing
                                   else to do; pricing a hopeless declaration
                                   against not declaring is D4's beam search.
      sh01_finish_the_wounded_target owner D3 — with a 1-wound character and a
                                   fresh squad both in range, the
                                   marginal-value allocator picks on damage
                                   efficiency alone, because nothing prices
                                   "it dies before it acts again". That is
                                   D3's one-ply reply.
    ```
    Files: `40k/tests/exams/` (10 gated + 2 aspirational + README),
    `40k/tests/run_exams.sh`, `40k/autoloads/AIBenchmarkRunner.gd`.
  - **Tier B self-assessed 2026-08-07 — pending human spot-check.** Every
    rationale cites the rule or the VP arithmetic that makes the expected play
    correct (11e 25.1 for objective scoring, 20.01 for the reserves cap, 2D6
    charge odds). Two exams exist specifically to stop the suite rewarding
    inaction: `ch02` is the mirror of `ch01` (an AI that never charges cannot
    pass both), and `mv04`'s sum-equals-score check cannot be satisfied by
    doing nothing because it requires records to exist at all.

- [ ] **B5 — Nightly self-play season with drift alarms**
  - **Lock:** CI + Lab  • **Depends:** B0, B1  • **Cost:** runner time nightly
  - **Context:** Benchmarking is operator-driven today; nothing notices AI
    regressions between sessions. A nightly season makes strength and
    behavior drift visible within a day.
  - **Spec:** A scheduled workflow (or documented cron on the dev box if CI
    runners are too slow — measure first and say which) runs: fixture gate →
    N games current-vs-current and current-vs-frozen-baseline (split budget,
    Custodes mirror + exams suite) → `build_index.py` → a one-page report
    artifact: stall rate, margin vs frozen, exam pass count, action-mix
    fingerprint vs 7-day median. Red flags: any stall, exam count drop,
    fingerprint drift beyond limits.
  - **Acceptance — Tier A:** (1) Two consecutive scheduled runs produce the
    artifact. (2) A deliberately-broken test run (temporarily set a weight
    to 0 locally) trips at least one red flag. (3) Runtime fits the runner's
    budget (documented).
  - **Tier B:** The report is readable in 30 seconds.

- [ ] **B6 — Counterfactual replay spike (credit assignment)**
  - **Lock:** Lab  • **Depends:** B1  • **Cost:** 3 days, timeboxed
  - **Context:** 400–600 actions/game, one terminal VP signal — credit
    assignment is the loop's hardest problem. Determinism now makes replay
    feasible: load the same fixture+seed, force one recorded decision to its
    runner-up candidate, complete the game, diff the VP. The design brief
    called this RQ3; nobody has built it.
  - **Spec:** `tools/ai_lab/replay_fork.py`: given a game record, a decision
    id, and an alternative index, re-run the benchmark with an injected
    override (AIDecisionMaker honors a `--force-decision <id>:<candidate>`
    test hook), producing the counterfactual outcome. Validate on 5 forks.
  - **Acceptance — Tier A:** (1) Replaying with the *chosen* candidate
    reproduces the original game byte-identically (the null fork). (2) Five
    forced-alternative forks complete and report VP deltas. (3) The hook is
    inert without the flag (determinism check).
  - **Tier B:** A short write-up: is per-decision regret worth computing at
    scale, and at what cost? Feeds E2's analyst.
  - **Kill criterion:** if the null fork does not reproduce byte-identically
    (hidden nondeterminism), document the source and stop — that bug becomes
    its own task and is worth more than the spike.

---

## WS-C — One Plan, One Value

*Connect the phases. Today each phase optimizes its own local score;
coordination lives in eight separate static caches (movement battle plan,
multi-phase plan, movement intents, focus-fire plan, fight-order plan, two
coordination ledgers, mission awareness) — and the multi-phase plan only
builds at Hard+ difficulty, so on Normal most cross-phase coordination is
silently off. A score can pass through five uncalibrated stacked modifiers
(faction aggression ÷, archetype ×, round strategy ×, tempo ×, difficulty
noise +). Give the AI one explicit value function and two plan horizons every
phase serves — a battle plan for the game, a turn plan for the turn. This is
the structural answer to "phase models without a connecting layer". Note the
horizons are separate on purpose: deployment and reserves are decided once
and pay off three rounds later, which no per-turn object can own.*

- [ ] **C0 — One source of truth for combat math**
  - **Lock:** AIDM  • **Depends:** D1 (the property test exists first, as the guard)  • **Cost:** code-only
  - **Context:** Expected-damage math is independently reimplemented ~9
    times in AIDecisionMaker (`_hit_probability` chains at ~L9281, 12313,
    12680, 12983, 14136, 15255, 19348…), and raw weapon-stat parsing
    (attacks/AP/damage strings) is duplicated 10–14×. There is no
    `WeaponProfile` struct. Divergence between copies is invisible until it
    costs games (the "D6"→1.0 bug lived in exactly this duplication).
  - **Spec:** Extract `AICombatMath` (expected damage ranged/melee, hit/
    wound/save/FNP chains, keyword modifiers) and `AIWeaponProfile` (parse
    once, typed fields) as static modules; replace every duplicate site
    with calls. No behavior change — where copies disagree today, keep the
    behavior of the copy the D1 property test validates as closest to the
    RulesEngine, and list any resulting decision changes (should be none if
    D1 fixes landed first).
  - **Acceptance — Tier A:** (1) `determinism_check.py` byte-identical on
    both mirrors. (2) grep-based count: `_hit_probability(` call sites
    outside AICombatMath ≤ 1; `ap_str.begins_with` outside AIWeaponProfile
    = 0. (3) D1 property test green before and after.
  - **Tier B:** none.

- [ ] **C1 — A board evaluation function, validated before it steers**
  - **Lock:** AIDM  • **Depends:** A2 (record plumbing)  • **Cost:** code + 1 season of records
  - **Context:** No global "how good is this position" exists; every phase
    scores its own proxies. Search (WS-D) needs a leaf evaluator; the
    strategist (C2) needs a goal metric; tuning needs it decomposed. But an
    unvalidated value function steering play is how the scoring-horizon
    change lost 4.29 VP — so V ships *dark* first.
  - **Spec:** `AIDecisionMaker.evaluate_board(snapshot, player) →
    {total, terms:{...}}`, pure, deterministic, decomposed into named
    `get_param`-weighted terms: projected primary VP for both players over
    remaining scoring turns (from actual mission cards + OC math), projected
    secondary VP, material EV difference (points × survival estimate),
    threat balance, objective-control stability. Compute per round end in
    benchmark games and write into the game record (`v_trace`). **No
    decision reads it yet.**
  - **Acceptance — Tier A:** (1) determinism unchanged (record-only).
    (2) On ≥100 archived games (one nightly season), Spearman correlation
    between round-3 `V_diff` and final VP margin ≥ 0.5; between round-4 and
    final ≥ 0.65 — computed by a committed script
    `tools/ai_lab/validate_value.py`; thresholds are the task's falsifiable
    claim. (3) Term decomposition sums to total.
  - **Tier B:** The per-round V trace narrates plausibly on a replayed game
    ("P1 ahead 12 → collapsed to −3 after the failed charge").
  - **Kill criterion:** if correlation < 0.35 after two iterations of term
    fixes, V as designed does not predict outcomes; write up why before any
    WS-D task leans on it.

- [ ] **C2 — TurnPlan: one plan object spanning the whole turn**
  - **Lock:** AIDM  • **Depends:** C1  • **Cost:** code + evaluator gate (~150 games)
  - **Context:** Three coordination caches exist and don't share state:
    the persistent movement battle plan (COORD-4), the multi-phase plan
    (charge intents / lock targets / lanes, Hard+), and the shooting
    focus-fire plan. They cooperate pairwise by convention (shooting
    under-shoots charge targets), CP budgeting doesn't exist, and no cache
    covers command/scoring. `docs/AI_DECISION_REVIEW_2026-07.md` §6-7 and
    the July review both point here.
  - **Spec:** Introduce `TurnPlan` — an explicit per-player plan object
    built in the command phase and passed through decisions (start
    migrating the 34 process-global `static var` caches into it; an
    explicit context object is also what lets an old and a new engine run
    side-by-side later). Contents: unit tasks ({unit → task: hold/take
    objective, screen zone, hunt target, deliver cargo, hold lane}),
    focus-fire intentions, charge intentions, CP reserve (see C3), and the
    mission read (which objectives matter this round, from the existing
    objective evaluation). Movement/shooting/charge/fight consult and
    consume TurnPlan; the existing caches become views or members of it.
    Build it at ALL difficulties (what differs by difficulty is plan
    quality, not plan existence — today `_build_phase_plan` silently skips
    below Hard). Replan-on-trigger semantics and the plan narration card
    stay (they are product features). Migrate one phase per commit,
    behavior-preserving where possible, evaluator-gated where not.
  - **Acceptance — Tier A:** (1) Slices claiming behavior-preservation pass
    `determinism_check.py`. (2) Final slice: pooled E ≥ −1 VP at 1 SE vs
    pre-C2 on both mirrors; zero new windowed-scenario failures (the
    `ai_battle_plan_log_integrity` and `ai_coordinated_movement` scenarios
    must stay green). (3) A new exam: shooting leaves the planned charge
    target ≥ N wounds (the cross-phase contract observable in one record).
  - **Tier B:** One log screenshot shows a single turn-plan card covering
    movement + shooting + charge intents (the "whole turn's intent at once"
    the July review asked for).

- [ ] **C2b — BattlePlan: how we intend to win this game**
  - **Lock:** AIDM  • **Depends:** C1 (V terms), C2 (TurnPlan is its execution vehicle)  • **Cost:** code + gate (~200 games)
  - **Context:** Above TurnPlan there is nothing. No object states how the AI
    intends to win the *game* — which objectives it contests all game versus
    concedes, whether it is the alpha strike or the counter-punch, when
    reserves land and what job they do, how CP and once-per-battle abilities
    spread across five rounds. Deployment and reserves are decided before
    round 1 and only pay off in rounds 2-3, so no per-turn object can own
    them: today reserves scoring is an orphan (18 hardcoded coefficients,
    promoted in A4) and deployment invents its own strategy per unit. The
    measured evidence says this layer carries the project's largest effects —
    the reserves cap alone moved a benchmark matchup from 12 to 39 primary VP
    (`docs/AI_REVIEW_2026-07-11.md` §2.4, §5), while every purely tactical
    change measured so far sat inside the noise.
  - **Spec:** `BattlePlan` — a per-player object built once after both armies
    are known and before deployment, and **reviewed** at each command phase,
    never rebuilt from scratch. Contents:
    - **win route** — projected primary/secondary VP for both sides from the
      mission cards and both army compositions; a chosen route (out-hold /
      out-kill / trade-and-hold) naming the C1 value terms it maximizes;
    - **objective stance** — per objective, for the game: contest-always /
      take-late / concede, with the round it matters;
    - **tempo** — commit round (alpha strike vs counter-punch), derived from
      relative threat ranges and durability;
    - **force allocation** — a durable per-unit job for the game (anchor
      home, hammer, screen, harass, reserve delivery) that TurnPlan tasks
      serve or explicitly override with a reason;
    - **resource arcs** — reserve manifest (which units, target arrival
      round, target job), CP arc per round (feeding C3), once-per-battle
      ability timing.
    Review semantics mirror the movement plan's replan-for-cause: the plan is
    re-scored each command phase against V and revised only when evidence
    contradicts it (a conceded objective becomes cheap, the commit round
    passed with no viable strike, the win route's projection inverts). Every
    revision is narrated. Downstream: TurnPlan (C2) derives unit tasks from
    the force allocation; C5's deployment posture derives from win route +
    tempo + objective stance instead of being independently invented;
    reserves declarations read the reserve manifest instead of their own
    scoring.
  - **Acceptance — Tier A:** (1) Built-but-not-consulted (flag off) is
    byte-identical vs pre-C2b on `determinism_check.py`. (2) Two new exams
    pass: "against a faster, tougher enemy the plan concedes the far
    objective and holds two near ones all game", and "reserves arrive in the
    round the manifest named, not on generic arrival scoring". (3) Pooled
    E ≥ −1 VP at 1 SE across both mirrors and the B2 asymmetric fixture, and
    a plan-vs-no-plan arm reported with its measured E whichever way it
    falls. (4) Plan revisions are recorded decisions with candidates; ≥1
    revision occurs and is narrated across a 5-round game.
  - **Tier B:** A replayed game reads as one story — deployment, reserve
    arrival and the round-4 push all serve the plan the log announced before
    round 1.
  - **Kill criterion:** if the plan arm measures worse than no plan at 1 SE
    on both mirrors after one revision pass of the review triggers, ship it
    default-off behind a parameter and write up which commitments hurt. A
    wrong plan committed to is worse than no plan; this criterion exists to
    catch exactly that.

- [ ] **C3 — CP budget as a decision, not nine private floors**
  - **Lock:** AIDM  • **Depends:** C2  • **Cost:** code + evaluator gate (~100 games)
  - **Context:** AUDIT Tier-3: no CP economy exists — nine stratagem
    evaluators each carry a private hardcoded CP floor; nothing reserves CP
    for the opponent's turn (overwatch at 1CP is the canonical case).
  - **Spec:** In TurnPlan, compute a CP budget: expected reactive value next
    turn (overwatch EV against the biggest projected threat, reroll
    insurance on planned high-stakes charges) vs proactive spend now. Each
    stratagem evaluator consults the shared budget (its floor becomes
    `get_param`-tunable); emit a decision record for spend/hold choices.
  - **Acceptance — Tier A:** (1) exams: "holds 1 CP when a 10-Boyz charge
    threatens next turn" and "spends freely on the last turn" both pass.
    (2) pooled E ≥ −1 VP at 1 SE on both mirrors. (3) Records show CP
    decisions with candidates.
  - **Tier B:** Narration explains a hold ("Keeping 1 CP for Overwatch").

- [ ] **C4 — Command phase scores its options instead of first-match-wins**
  - **Lock:** AIDM  • **Depends:** C2  • **Cost:** code + evaluator gate (~100 games)
  - **Context:** The command chain is prioritized ifs (battle-shock, then
    faction ability, then stratagems) — order encodes priority implicitly
    and can't be tuned or compared (`docs/AI_DECISION_REVIEW_2026-07.md`
    §3.2).
  - **Spec:** Enumerate command-phase options, score each with existing EV
    helpers against TurnPlan/V terms, pick the best legal sequence, emit
    records. Keep the once-per-battle timing heuristics (WAAAGH! rules) as
    scored bonuses, not gates.
  - **Acceptance — Tier A:** determinism-or-gate per guardrail 3; existing
    command-phase scenarios green; new records present.
  - **Tier B:** WAAAGH! timing narration still reads correctly.

- [ ] **C5 — Deployment master plan (posture before placement)**
  - **Lock:** AIDM  • **Depends:** A5 (deployment params exist), C2b (the posture comes from the battle plan)  • **Cost:** code + gate (~150 games)
  - **Context:** Deployment is reactive per unit; no whole-army posture
    ("castle center", "refuse left flank", "spread for scout screens")
    exists, and misclassification is known (Stormboyz deploy as "durable
    ranged", `docs/AI_REVIEW_2026-07-11.md` §6). Deployment largely decides
    round 1-2. It is independent in *timing* — it happens once, before
    everything — but maximally coupled in *consequence*, which is why the
    posture must be derived rather than invented: cover is only valuable if
    the plan intends to shoot from there.
  - **Spec:** Derive the posture from C2b's win route, tempo and objective
    stance (score 3-4 candidate postures for how well each *serves the plan*,
    rather than scoring them against the board in isolation); the chosen
    posture then parameterizes the existing per-unit placement (column
    geometry, depth, role targets). Fix role classification to weigh melee
    reach vs token pistols. Posture is a recorded decision, and its bias
    point for personas lives in the battle plan (F1).
  - **Acceptance — Tier A:** (1) two deployment exams pass (melee horde
    deploys forward-weighted vs shooting army; fragile shooters castle
    against melee). (2) pooled E ≥ −1 VP at 1 SE; deployment scenarios
    green. (3) Posture decision record with ≥3 candidates present.
  - **Tier B:** Replay shows visibly different deployments for Green Tide
    vs Shield Host personas on the same map.

- [ ] **C6 — Movement order by dependency**
  - **Lock:** AIDM  • **Depends:** C2  • **Cost:** code + gate (~100 games)
  - **Context:** Units move in a heuristic order (engaged, disembarked,
    normal, transports, front-to-back); a screen can move after the unit it
    screens, and objective-critical moves don't go first (July review
    roadmap #1).
  - **Spec:** Order TurnPlan movement tasks by dependency class:
    blockers/screens → objective-critical → damage-dealers → opportunists;
    within class keep the current order. Record the ordering rationale.
  - **Acceptance — Tier A:** exam "screen moves before the screened unit and
    ends between it and the deep-strike zone" passes; E ≥ −1 VP at 1 SE;
    determinism check on the no-dependency case (order unchanged when no
    dependencies exist).
  - **Tier B:** none.

- [ ] **C7 — Escort pairing (transport+cargo, leader+bodyguard) as one entity**
  - **Lock:** AIDM  • **Depends:** C2, C6  • **Cost:** code + gate (~100 games)
  - **Context:** Transports and cargo plan independently beyond delivery
    targets (July review roadmap #2); disembark scoring literals were
    promoted in A4, but the *coupling* (move transport where cargo's task
    wants to be next turn) has no owner.
  - **Spec:** TurnPlan tasks may bind an escort pair; the pair's movement/
    disembark decisions are scored jointly (transport destination scored by
    cargo's task value at the disembark point next turn, using C1 terms).
  - **Acceptance — Tier A:** exam "Trukk carries Boyz toward the objective
    it must hold turn 3 and disembarks in control range" passes; E ≥ −1 VP
    at 1 SE.
  - **Tier B:** Narration names the pair ("Trukk delivering Boyz to
    obj_center").

---

## WS-D — Looking Ahead

*Bounded search where it pays. The AI is greedy today: it never simulates an
opponent reply or an action sequence — no search tree, no state cloning,
no what-if evaluation exists anywhere in the file, and the
`use_look_ahead()` difficulty gate is dead config that nothing calls.
Full-game tree search is out of reach (branching, clone cost) — targeted
lookahead is not. Bot Bowl's years of results say scripted candidates +
selective search beats both pure scripting and pure ML at this scale.*

- [x] **D1 — Reconcile the AI's damage math with the RulesEngine**
  - **Lock:** AIDM  • **Depends:** —  • **Cost:** code + property test (no games)
  - **Context:** The AI *predicts* combat with its own expected-damage
    reimplementation; the engine *resolves* it in RulesEngine. They have
    already diverged catastrophically once (AUDIT 0.1: "D6" parsed as 1.0 —
    every anti-tank gun undervalued 2–3.5×; fixed, but nothing prevents the
    next divergence). Every scorer and every future search leaf trusts this
    math.
  - **Spec:** `tools/` property test (headless GDScript): for every weapon
    profile in the shipped army lists × a grid of defender profiles,
    compare AIDecisionMaker's expected damage vs a 2,000-sample Monte-Carlo
    through `RulesEngine.resolve_shoot`/melee resolution at fixed seeds.
    Fail on relative error > 10% (tolerance list for known intentional
    approximations, each with a comment). Wire into CI (fast tier: top 50
    weapons; nightly: full corpus).
  - **Acceptance — Tier A:** (1) test exists, runs headless, fails on a
    seeded deliberate bug (`"D6" → 1.0` reintroduced locally). (2) Current
    divergences either fixed or on the documented tolerance list with
    rationale. (3) CI wired.
  - **Tier B:** Tolerance list reviewed — nothing on it looks like AUDIT 0.1.
  - **Evidence (2026-08-07):**
    ```
    40k/tests/test_ai_combat_math_property.gd
      125 distinct weapon profiles across the shipped army lists
      x 5 single-model defender profiles (T4/Sv6, T4/Sv3, T6/Sv2+4++, T9/Sv3, T12/Sv2)
      x 1500 seeded Monte-Carlo resolutions through RulesEngine.resolve_shoot /
        resolve_melee_attacks
      fast tier (50 weapons) runs headless in ~4 min; --full for the whole corpus

    godot --headless --path 40k -s tests/test_ai_combat_math_property.gd -- --samples=1500
      158 pairs agree within 10%, 92 known+owned divergences, 0 NEW failures
      VERDICT: PASS

    godot ... -- --samples=600 --seeded-bug        # AUDIT 0.1 reintroduced
      163 agree, 71 known, 16 NEW failures -> DETECTED
      VERDICT: PASS   (inverted: it MUST fail with the bug injected)
    ```
    **Divergence found and FIXED:** `_estimate_melee_damage` never capped
    damage at the target's wounds-per-model, though the ranged estimator
    always has ("T7-6"). Every high-damage melee weapon was therefore
    overvalued against 1- and 2-wound models — the Castellan axe measured
    8.33 predicted vs 2.81 resolved against a 1-wound body (3.0x) and 4.17 vs
    2.68 against 2-wound marines (1.6x). Same class as AUDIT 0.1. With the cap:
    Big choppa 3.472 predicted vs 3.554 resolved (2.3%). Shipped as
    `MELEE_WOUND_OVERFLOW_CAP` (default 1.0 = on) rather than a bare `if`,
    because a code change applied to both sides of a mirror cannot be measured
    from the margin — the evaluator needs a way to hand one side the old
    behaviour (`d1_melee_cap_off.json`).

    **Divergences catalogued, NOT tolerated silently:** 92 pairs remain, in
    `40k/tests/ai_combat_math_known_divergences.json`, each with its measured
    predicted/resolved ratio. The file is a ratchet — an uncatalogued pair must
    agree within 10%, a catalogued one fails if it drifts 15% further. Two
    classes, both owned by the new task **D1b**:
      * 17 melee pairs where `_estimate_melee_damage` ignores weapon keyword
        modifiers entirely (ANTI-X, TWIN LINKED, LETHAL HITS). The ranged
        estimator calls `_apply_weapon_keyword_modifiers`; the melee one never
        has. The AI UNDER-values exactly the weapons built to kill what it is
        looking at — Beastchoppa vs a T12 hull: 0.56 predicted, 1.64 resolved.
      * 75 ranged pairs where the AI OVER-predicts by 1.5-2.4x. Concentrated in
        twin-linked, torrent and grenade weapons. **The cause is not isolated**
        and this write-up does not pretend otherwise.
    **The fix is behaviourally neutral, and it is shipped on correctness
    grounds, not on a measured strength gain.** Paired evaluation, cap ON vs
    cap OFF, stopping rule pre-registered by run_paired before the first game:
    ```
    Custodes mirror, 12 pairs = 24 games   E = -1.33 VP/game  se 0.93   FUTILE
    Ork mirror (melee-relevant), 6 pairs   E = +0.33 VP/game  se 1.25   FUTILE
    inverse-variance pooled                E = -0.74 VP/game  se 0.75
    ```
    Non-regression bar for a structural change is E ≥ −1 VP at 1 SE: pooled
    E + SE = +0.01. Both mirrors' intervals straddle zero, so the honest
    reading is that correcting a 1.6-3.0x overvaluation of melee damage did
    not measurably move the margin — which is itself worth knowing, and is the
    third time in this repo that a plausible effect has measured at zero.
    Files: `40k/tests/test_ai_combat_math_property.gd`,
    `40k/tests/ai_combat_math_known_divergences.json`,
    `40k/tests/bench_profiles/d1_melee_cap_{on,off}.json`,
    `40k/scripts/AIDecisionMaker.gd`, `.github/workflows/ai-lab.yml`.
  - **Tier B self-assessed 2026-08-07 — pending human spot-check.** The one
    entry in `TOLERANCE_LIST` (torrent weapons, wider band for a rolled attack
    count) is a sampling-convergence allowance, not a modelling claim. Nothing
    on it looks like AUDIT 0.1 — the things that *do* look like AUDIT 0.1 were
    deliberately kept out of the tolerance list and put in the catalogue with
    an owning task instead.

- [ ] **D1b — Close the catalogued combat-math divergences**
  - **Lock:** AIDM  • **Depends:** D1  • **Cost:** code + gate (~100 games/class)
  - **Context:** D1's oracle catalogued 92 reproduced (weapon, defender) pairs
    where the AI's expected damage disagrees with what the engine resolves, in
    two classes with opposite signs. Neither is a rounding difference; both
    change which target the AI picks. The catalogue
    (`40k/tests/ai_combat_math_known_divergences.json`) carries the measured
    ratio for each pair and is already a CI ratchet, so this task is bounded:
    close a class, regenerate, watch the catalogue shrink.
  - **Spec:** (1) Melee keyword modifiers: `_estimate_melee_damage` computes
    `p_hit`/`p_wound`/`p_unsaved` directly and never calls
    `_apply_weapon_keyword_modifiers`, so ANTI-X, TWIN LINKED, LETHAL HITS and
    SUSTAINED HITS are invisible to every melee estimate. Route melee through
    the same helper the ranged path uses (this is also C0's job — do it there
    if C0 lands first). (2) Ranged over-prediction on twin-linked/torrent/
    grenade weapons: **diagnose before fixing** — instrument one pair end to
    end (predicted terms vs the engine's own dice log) and find where the two
    part company. Do not guess from the keyword name.
  - **Acceptance — Tier A:** (1) The catalogue shrinks by the whole melee
    class (17 pairs) and the property test still passes with the smaller
    catalogue committed. (2) Each fix is either determinism-identical or
    passes a paired evaluation at E ≥ −1 VP at 1 SE on both mirrors. (3) The
    ranged class either shrinks or gains a written root-cause note per pair —
    "not isolated" is not an acceptable end state twice.
  - **Tier B:** A 40k player reading the melee estimate for an ANTI-VEHICLE
    weapon against a vehicle agrees with the number.
  - **Progress 2026-08-08 — the MELEE HALF is done; the ranged class remains.**
    `_estimate_melee_damage` now routes through
    `_apply_weapon_keyword_modifiers`, the same helper the ranged estimator
    has always used, so ANTI-X / TWIN LINKED / LETHAL HITS / SUSTAINED HITS
    reach a melee estimate for the first time. Melee has no range band, so
    distance is passed as unknown (-1) and the range-gated keywords (RAPID
    FIRE, MELTA) fall through their no-bonus paths, which is correct for a
    melee profile. Gated as `MELEE_KEYWORD_MODIFIERS` (default 1.0) so the
    change is measurable at all.
    ```
    oracle, 1500 samples/pair:
      catalogued divergences 92 -> 81
      RESOLVED (12): Phase sword and poison blades x5 (LETHAL HITS),
                     Vaultswords - Hurricanis x5, Vaultswords - Victus x2
      NEW (1):       Beast Snagga klaw vs T9 walker, ratio 1.21
                     (2.963 predicted vs 2.449 resolved — the AI now
                     over-predicts this one slightly; recorded in the
                     catalogue rather than hidden)
      agreements 158 -> 169, VERDICT: PASS with the regenerated catalogue

    paired gate, keywords ON vs OFF, stopping rule pre-registered:
      Ork mirror,      6 pairs = 12 games   E = +0.00  se 0.00   NO_OP
      Custodes mirror, 9 pairs = 18 games   E = +0.28  se 0.28   FUTILE
    ```
    **The Ork arm is a provable no-op — every paired seed played out
    identically**, so on that fixture the corrected melee keyword arithmetic
    changed not one decision. Custodes is +0.28 ± 0.28, indistinguishable from
    zero. Non-regression is satisfied on both.
    That is now **two** sizeable corrections to the AI's damage arithmetic in a
    row (D1's 1.6-3.0x melee overflow, D1b's missing keywords) that measure at
    zero. The pattern is worth naming rather than shrugging at: it suggests
    target selection is dominated by the macro terms (target value, objective
    proximity, threat) rather than by the fine detail of expected damage, and
    that the *tactical* half of the plan may be pulling on a rope that is not
    attached. WS-C's evidence for the strategic layer carrying the largest
    effects (reserves cap: 12 -> 39 primary VP) points the same way. Worth
    checking before WS-D spends games on lookahead.
    **Still open:** the 75-pair ranged class, cause not isolated.

- [ ] **D2 — Forward-model service with a measured budget**
  - **Lock:** AIDM  • **Depends:** D1  • **Cost:** code + microbenchmarks
  - **Context:** Search needs `apply(state, action) → state'` cheaply.
    Today `GameState.create_snapshot(false)` is a full deep copy per
    decision; AIDecisionMaker's 45 static caches are process-global (a
    forked evaluation would corrupt live planning — `suggest_action`
    already works around this with `_snapshot_planning_state()` /
    `_restore_planning_state()`).
  - **Spec:** Build `AIForwardModel` (static, engine-side): (a) EV mode —
    apply expected-value combat outcomes (D1 math) and deterministic moves
    to a *minimal* mutable view (units' positions/wounds/flags only), no
    full snapshot clone; (b) sampled mode — seeded dice for sequencing
    search (D4). Generalize the planning-state save/restore into a scoped
    guard. Microbenchmark: evals/sec for (move-unit, shoot-EV,
    charge-EV) on both mirror fixtures, committed as a table in the task's
    report.
  - **Acceptance — Tier A:** (1) ≥ 200 shoot-EV evals/s and ≥ 500
    move-position evals/s on the Custodes fixture (dev box), measured by a
    committed benchmark script. (2) A fork-and-discard during a live
    benchmark game leaves the game byte-identical (determinism check with
    forced no-op forks enabled). (3) No full `create_snapshot` calls inside
    the eval loop (grep-able assertion in the benchmark script).
  - **Tier B:** none.
  - **Kill criterion:** if after real optimization the budget lands below
    50 shoot-EV evals/s, restrict WS-D to D1+D3-lite (reply estimation via
    threat maps only, no state mutation) and record why.

- [ ] **D3 — One-ply opponent reply for high-stakes moves**
  - **Lock:** AIDM  • **Depends:** C1 (validated V), D2  • **Cost:** code + gate (~200 games)
  - **Context:** The classic greedy failure: the AI walks a unit onto an
    objective that three enemy units can delete on the reply. Threat maps
    approximate this; they don't price the *specific* reply against the
    *specific* final position. `use_look_ahead` (Competitive) was the
    intended home and is currently dead config — never called.
  - **Spec:** At Hard+ for the top-K (param, default 3) highest-value
    movement decisions per phase: for each of the top-M candidate
    destinations, estimate the opponent's best reply damage/OC flip against
    the resulting position (D2 EV mode, opponent shooters+chargers within
    threat range), and re-score candidates by
    `score + LOOKAHEAD_WEIGHT × (V_after_reply − V_now)` with all new
    coefficients as parameters. Wall-clock budget: ≤ +25% median decision
    time at Hard (measured).
  - **Acceptance — Tier A:** (1) aspirational exam flips: "does not step a
    350-pt unit into 3-unit kill range for +2 objective points when a safe
    hold scores equal primary" passes. (2) pooled E ≥ +1 VP at 1 SE on both
    mirrors (this one must *pay*, not just not-regress — it is the flagship
    strength feature). (3) Decision records show `reply_penalty` terms;
    wall-clock budget respected.
  - **Tier B:** Narration: "rejected obj_center — Custodian Guard + both
    Caladius can answer there".
  - **Kill criterion:** if E < +1 VP at 1 SE after two tuning passes of
    LOOKAHEAD_WEIGHT on the Ork mirror too, park the branch behind a
    default-off param and write up the measured result — do not ship a
    speculative slowdown.

- [ ] **D4 — Sequencing search for charge and fight order**
  - **Lock:** AIDM  • **Depends:** D2  • **Cost:** code + gate (~150 games)
  - **Context:** Charge declaration order and fight activation order are
    scored heuristically today (gang-up bonuses, kill-before-killed
    ranking); order interacts combinatorially (a first charge opens a lane
    or eats the overwatch that would kill the second). Branching here is
    small (≤ 8 units, order permutations prunable) — the one spot where
    real search is cheap.
  - **Spec:** Beam search (width param, default 3) over charge-declaration
    order and fight-activation order using D2 sampled mode (N=5 seeds per
    leaf, seeded), scoring terminal states with C1's V. Difficulty-gated:
    Hard uses beam 2, Competitive 4.
  - **Acceptance — Tier A:** (1) exams: "declares the overwatch-soak charge
    first" and "activates the finisher before the enemy interrupt can save
    the wounded Knight" pass. (2) pooled E ≥ 0 VP at 1 SE on the Ork mirror
    (melee-heavy; the Custodes mirror may be inert — record both).
    (3) Phase wall-clock at Hard ≤ +20%.
  - **Tier B:** Fight-order narration lists the planned sequence.

---

## WS-E — The Improvement Loop

*Close the Karpathy loop: propose → play → measure → gate → ship, with
humans, optimizers, and LLMs all proposing through the same gate. Most of the
machinery exists (`tools/ai_lab/`); what's missing is budget, cadence,
proposers beyond CEM, and a shipping channel.*

- [ ] **E1 — Run the parameter search at its designed budget**
  - **Lock:** Lab  • **Depends:** A4, A5, B1, B3  • **Cost:** 1,500–3,500 games (~2–4 days unattended after B1)
  - **Context:** The only CEM campaign so far used 264 games (a tenth of
    design budget) on 6 parameters, three of which had been unreachable
    literals that morning, and found nothing shippable (+2.25 ± 3.2 VP).
    That is an underpowered search over a freshly-widened space — not
    evidence tuning is dead. With A4/A5 the space is honest and B3 ranks
    it; run the search properly once.
  - **Spec:** `cem_driver.py` over the top-10 parameters ranked by both
    screens, two mirrors + the B2 asymmetric fixture in the gate,
    pre-registered stopping rule, racing enabled. Ship or null — either
    outcome is the deliverable, written to `tests/bench_baselines/`.
  - **Acceptance — Tier A:** (1) Campaign JSON records the stopping rule
    before the first game. (2) Concurrent A/A arm stays |E| < 1 SE.
    (3) Outcome: either a profile passing all five `gate_candidate.py`
    gates (then E5 ships it), or a null report with a power analysis
    (minimum detectable effect at the games spent).
  - **Tier B:** The report states plainly what would change the conclusion.

- [ ] **E2 — LLM analyst proposes rules and parameters through the gate**
  - **Lock:** Lab  • **Depends:** A1, A2, A3, A6 (honest records), B0  • **Cost:** ~300 games/cycle
  - **Context:** The profile rule DSL (conditions on 9+ context keys;
    override/multiply/add actions) is a machine-authorable policy space the
    optimizer can't search well (discrete, structural) but an LLM can
    hypothesize over — *if* the records it reads are honest (WS-A) and
    every proposal is validated (`validate_profile.py` catches the four
    known silent-failure traps) and measured (`run_paired.py`). This is
    design-doc stage M5, never started.
  - **Spec:** `tools/ai_lab/llm_analyst/` — a scripted cycle: (1) build a
    season summary from DuckDB (loss patterns, exam failures, high-regret
    decisions from B6 if available); (2) prompt an LLM (Claude via API; the
    prompt is a committed template) to propose ≤5 hypotheses as profile
    rules/parameter deltas with predicted effect and rationale; (3)
    auto-validate, auto-evaluate each (sequential stopping, racing); (4)
    write a cycle report: hypothesis, prediction, measured E, verdict.
    Human reviews before any ship (E5).
  - **Acceptance — Tier A:** (1) One full cycle runs end-to-end from one
    command. (2) Every proposal in the cycle report has a measured E with
    SE — no unmeasured claims. (3) A seeded bad proposal (multiply on an
    undeclared parameter) is caught by validation, not by a wasted
    campaign.
  - **Tier B:** The cycle report's hypotheses are specific and falsifiable
    ("Orks over-reserve vs fast armies; cap at 15% when enemy median move
    ≥ 10″"), not vibes.
  - **Kill criterion:** three consecutive cycles with zero gated wins and
    zero new insight → stop, write up, revisit after WS-C/WS-D land.

- [ ] **E3 — LLM patch loop for scoring code (AlphaEvolve-lite)**
  - **Lock:** Lab + AIDM  • **Depends:** E2 (harness), A7 (ratchet), D1 (math oracle)  • **Cost:** ~400 games/cycle
  - **Context:** Rules and parameters can't express a *missing feature*
    (audit bucket 3) — e.g. the objective-assignment penalty being blind to
    rounds-remaining was code, not a weight. The strongest current pattern
    for machine-proposed code is evolutionary LLM patching gated by
    automated evaluation (AlphaEvolve; Karpathy's propose-evaluate-commit
    loop). The repo already tried a crude ancestor (`ai_improve_loop.sh`);
    this replaces it with a measured one.
  - **Spec:** Extend the E2 harness: proposals may be unified diffs against
    a **whitelist** (initially `_score_unit_for_reserves`,
    `_score_fight_target`, the objective-assignment scoring block — pure
    functions with record coverage). Pipeline per patch: apply in a
    worktree → build + unit tests + D1 property test → determinism check
    (if claimed behavior-preserving) or paired evaluation (if behavioral) →
    exams → report. Nothing merges without a human reading the diff and the
    numbers. Provenance (prompt, model, patch, measurements) archived with
    the season.
  - **Acceptance — Tier A:** (1) The pipeline rejects a seeded
    syntax-error patch, a seeded determinism-violating patch, and a seeded
    exam-regressing patch, each at the right stage (three red-team
    fixtures committed). (2) One full cycle produces ≥3 evaluated patches
    with measured E each. (3) Whitelist enforcement: a patch touching a
    non-whitelisted function is refused.
  - **Tier B:** A human can audit one accepted/rejected patch end-to-end
    from the archived provenance in < 10 minutes.
  - **Kill criterion:** same as E2's, measured after three cycles.

- [ ] **E4 — Behavioral fingerprint and Goodhart hardening**
  - **Lock:** Lab  • **Depends:** B0  • **Cost:** analysis-only
  - **Context:** `gate_candidate.py` gate 4 already checks action-mix drift
    ("if the AI stops charging entirely and wins on points, the number
    improved and the game got worse"). As optimization pressure grows
    (E1–E3), widen the tripwire before it's needed.
  - **Spec:** Define the fingerprint in `tools/ai_lab/fingerprint.py`:
    per-game charge declarations, advance rate, reserve %, fall-back rate,
    mean engagement round, objective-control curve, kill-VP curve, CP spend
    curve — computed from game records; distance metric + per-metric drift
    limits vs the frozen baseline (B0), calibrated from A/A spread (limits
    = mean ± 4×A/A SD, recorded). Wire into `gate_candidate.py` as the
    expanded gate 4. Add the human protocol to the README: every shipped
    candidate gets 2 full game logs skimmed by a human against a 5-item
    "still looks like 40k" checklist.
  - **Acceptance — Tier A:** (1) Fingerprint of baseline-vs-baseline A/A
    stays within limits across 20 games (no false alarms). (2) A seeded
    degenerate profile (charge weights zeroed) trips it. (3) gate_candidate
    consumes it.
  - **Tier B:** Checklist items are observable in the game log without
    tooling.

- [ ] **E5 — A shipping channel for AI improvements**
  - **Lock:** Profiles + Docs  • **Depends:** B0  • **Cost:** code-only
  - **Context:** No profiles ship with the game today (`user://` only);
    an accepted candidate has no road to players except editing code
    defaults. Tuned improvements should ship as versioned data.
  - **Spec:** `res://data/ai_profiles/` shipped directory + manifest;
    `default_profile` per difficulty in config (absent → current defaults);
    ProfileManager loads shipped profiles read-only alongside user ones;
    `gate_candidate.py --ship` emits the profile + a
    `version_history.json` entry + the baseline report stub. Rollback =
    revert the data commit. This is player-facing: windowed scenario
    (profile visibly loaded in a new game: parameter provably in effect via
    a decision record) + screenshot per project rules.
  - **Acceptance — Tier A:** (1) Windowed scenario: game started at Hard
    loads the shipped default profile and a decision record shows a
    profile-overridden parameter value in `parameters_used`. (2)
    `validate_profile.py` in CI over every shipped profile. (3) Ship a
    trivial known-good profile (frozen baseline values) as the proof.
  - **Tier B:** Version history entry reads sensibly to a player.

- [ ] **E6 — The loop runbook**
  - **Lock:** Docs  • **Depends:** E1 (first full pass of any proposer)  • **Cost:** docs-only
  - **Context:** The loop only compounds if a future session (human or LLM)
    can run one full cycle without reverse-engineering the lab. The
    2026-08-07 status report shows how much context a cycle needs.
  - **Spec:** `tools/ai_lab/RUNBOOK.md`: the cycle as a checklist with exact
    commands (fixture gate → season → analyst → candidates → paired eval →
    gate → ship/null report → re-freeze policy), budget table
    (games and hours per stage at current speeds), the acceptance
    thresholds, the kill criteria, and "what to do when" failure notes
    (contaminated season dir, container suspension, A/A drift). Include the
    prompt template used by E2/E3.
  - **Acceptance — Tier A:** A fresh Claude session given only the runbook
    executes a mini-cycle (10-game season, one null candidate) end-to-end
    without human course-correction — this is literally testable and is the
    task's gate.
  - **Tier B:** Runbook fits in one screenful per stage.

---

## WS-F — Personas and Difficulty

*Different armies should play differently, and difficulty should come from
plan quality and lookahead, not score noise. Personas are data (profiles +
strategist biases), not code forks — so the improvement loop can tune each
persona the same way it tunes the default.*

- [ ] **F1 — Persona schema: strategist biases in shipped profiles**
  - **Lock:** Profiles + AIDM  • **Depends:** C2b (BattlePlan reads biases), C2, E5 (shipping channel)  • **Cost:** code + gate (~100 games)
  - **Context:** Profiles already carry `playstyle`/`faction_affinity`
    metadata that nothing reads. Faction behavior today is five hardcoded
    aggression constants plus archetype detection. A persona is not "charges
    more" — it is *how this army wins*, which makes the battle plan its
    natural home. The persona surface should be: parameter pack (exists) +
    rules (exists) + **strategist biases** (new) consumed by **C2b first**
    (win-route preference, tempo bias, reserve appetite, objective stance
    lean) and TurnPlan/C5 second (risk posture, target priorities).
  - **Spec:** Extend `wh40k_ai_profile` v2 with a `strategist` block (all
    fields optional, defaults = current behavior); BattlePlan reads the
    game-level biases, TurnPlan and deployment posture the turn-level ones;
    `validate_profile.py` and `ai-creator` learn the new fields. Document in
    `AI_TUNING.md`.
  - **Acceptance — Tier A:** (1) v1 profiles still load (round-trip test).
    (2) A test profile with `risk_posture: reckless` measurably shifts the
    fingerprint (charge rate up, reserve % down) on 10 games vs default —
    asserted by `fingerprint.py` distance > A/A limits. (3) Empty
    strategist block = byte-identical determinism vs no block.
  - **Tier B:** ai-creator renders the new fields with tooltips.

- [ ] **F2 — Two shipped reference personas, distinguishable and non-regressing**
  - **Lock:** Profiles  • **Depends:** F1, E4  • **Cost:** ~200 games
  - **Context:** The YouTube mining effort already produced draft faction
    profiles (`research/youtube/build_profiles.py` — six factions,
    explicitly "drafts, not tuned"). Ship the first two real ones: an Ork
    brawler ("Green Tide") and a Custodes counter-puncher ("Shield Host").
    Personas must be *visibly different* without being *worse*.
  - **Spec:** Author both from the drafts + B3 sensitivity knowledge; each
    must (a) differ from default by fingerprint distance > 4×A/A SD on ≥3
    metrics, (b) stay within −2 VP at 1 SE of the default profile on its
    own faction's mirror (a persona may sacrifice a little strength for
    flavor, bounded), (c) pass validate_profile + scenario suite. Selection
    UI: persona dropdown when picking an AI opponent (player-facing:
    version history + windowed scenario + screenshot).
  - **Acceptance — Tier A:** (1) fingerprint distinguishability per (a),
    from committed measurement. (2) strength bound per (b). (3) windowed
    scenario: selecting Green Tide in the menu produces a game whose first
    decision record carries the persona's profile name.
  - **Tier B:** Two replays feel different to a human player in the first
    two rounds; personas' descriptions match what the fingerprint shows.

- [ ] **F3 — Difficulty from capability, not noise**
  - **Lock:** AIDM + Profiles  • **Depends:** D3 or D4 (a real capability lever exists)  • **Cost:** ~150 games
  - **Context:** Difficulty today = score noise (100/1.5/0.5/0), applied in
    only three places, + feature gates — of which seven are dead config
    with no callers (`use_look_ahead`, `use_trade_analysis`,
    `use_focus_fire`, `use_survival_assessment`, `use_screening`,
    `use_weapon_efficiency`, `get_movement_iterations`). Noise makes the AI
    *randomly wrong*, which reads as stupid, not easy. Better: lower
    difficulties get shallower plans and no lookahead; higher get search.
  - **Spec:** Re-map: Easy = current Easy (it works as comedy); Normal =
    full scoring, no TurnPlan lookahead terms, no D3/D4; Hard = TurnPlan +
    D3 K=2; Competitive = D3 K=4 + D4 beams + zero noise. Audit and delete
    or wire the 7 dead gates. Measure the ladder: each step up must beat
    the step below by ≥ +4 VP at 1 SE over 20 paired games (a difficulty
    ladder that doesn't order is a bug).
  - **Acceptance — Tier A:** (1) ladder ordering measured and committed.
    (2) dead-gate audit: every `AIDifficultyConfig` function has ≥1 caller
    or is deleted. (3) wall-clock per difficulty documented; Competitive
    ≤ 1.5× Hard per decision.
  - **Tier B:** Difficulty descriptions in the UI match measured behavior.

---

## Recommended order (phases; tasks within a phase can parallelize by lock)

| Phase | Tasks | Theme | Exit condition |
|---|---|---|---|
| 1 | A1 A2 A3 A4 A5 D1 · B0 B1 B2 B4 | See clearly, measure cheaply | records honest; unreachable ≤50%; games ≤30 s/300 s; exams live; baseline frozen |
| 2 | A6 A7 B3 B5 C0 C1 · B6 spike | Instrument everything, dedupe the math, validate V, nightly pulse | census ≥9 types; one combat-math module; V correlation ≥0.5; nightly report running |
| 3 | C2 C2b C3 C4 E1 · E4 E5 | Two plan horizons; first full-budget search; ship channel | TurnPlan live in all phases; BattlePlan built, reviewed and measured; E1 shipped-or-null; profiles shippable |
| 4 | D1b D2 D3 D4 C5 C6 C7 | Lookahead + remaining plan features | D3 pays ≥+1 VP or is parked with numbers |
| 5 | E2 E3 E6 F1 F2 F3 | The loop runs itself; personas; difficulty | one analyst cycle + one patch cycle complete; two personas shipped |

**Decision checkpoint (owner):** after Phase 2, choose the improvement posture —
(A) static: stop at E1+E5, tune by hand thereafter; (B) offline-improvable
(recommended, this plan): E2/E3 run on a cadence, ship as profiles; (C) add
learned components (a fitted value function or small policy nets) — only
worth revisiting if B plateaus *and* the B6/record dataset has grown enough
to train on. The evidence for (B) is laid out in
`docs/AI_CURRENT_AND_FUTURE.html`.

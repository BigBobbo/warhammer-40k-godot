# Prompt: research and design a learning loop for the 40k AI

*Hand this to a capable LLM with repo access. It asks for a design, not an
implementation. Everything in the "Ground truth" section was verified against
the code on 2026-08-06 — but verify it again yourself, because some of it was
wrong the last time someone wrote it down.*

---

## Your role

You are designing a **framework that lets a Warhammer 40,000 game AI improve
from the games it plays**, in a codebase where today it improves only when a
human reads a benchmark table and hand-edits a constant.

Deliver a **design document**, not code. Ship nothing. The end product is a
decision I can act on: what to build, in what order, what it costs, what it
buys, and how we will know it worked.

## The problem, stated honestly

`40k/scripts/AIDecisionMaker.gd` is a ~22,300-line weighted-heuristic engine.
It plays a full game in 2.5–7 minutes headless. At the end, the harness writes
a JSON file with the final score and **everything else is discarded**. The next
game starts from exactly the same place. There is no memory, no dataset, no
gradient, no bandit, no archive — the only learning loop in the project is a
human in the middle, and it operates at roughly one hypothesis per day.

The most recent attempt to improve the AI (mining 1,029 YouTube transcripts
into 31 evidence-backed findings, implementing six of them) produced a measured
effect of **−2.05 VP/game, 95% CI [−7.2, +3.1]** — indistinguishable from zero,
with the point estimate slightly favouring the *old* behaviour. That is the
status quo you are trying to beat. Read
`40k/tests/bench_baselines/2026-08-06_mirror_new_vs_old.md` before you design
anything; it is the most honest account of how hard this measurement problem
actually is.

## Ground truth about the codebase

**Verify each of these against the code. Cite `file:line` when you rely on one.**
Do not trust this summary — the previous set of written-down assumptions about
this AI contained several stale line numbers and two claims that were flatly
false.

### The single most important asset: decision records already exist

`AIDecisionMaker._add_decision_record()` (`scripts/AIDecisionMaker.gd:457`)
already emits, per decision:

```
{ decision_type, unit_id, unit_name,
  candidates: [ { description, score, score_breakdown: {...} } ],
  chosen_index, parameters_used, difficulty, context: { phase, round, ... } }
```

`AIPlayer` batches these per round/phase into `_all_decision_records`
(`autoloads/AIPlayer.gd:3693`) as `{round, phase, player, records}`.

**This is a complete "here were my options, here is how I scored each one, here
is what I picked, here are the parameters I used" trace — and it is thrown
away.** It is ring-buffered at 500 batches (`:3698`), `pop_front`s the excess
into a `_decision_records_dropped` counter, and is cleared on `configure()`.
Nothing anywhere writes it to disk (`grep` for a persist path returns nothing).

Currently only **5 call sites** emit records, so coverage is partial. Assess
which decisions matter and what it would cost to instrument them.

### The tuning surface

- Hundreds of constants read through `get_param(name, default)`
  (`AIDecisionMaker.gd:421`), resolution order: rule overrides → per-player
  profile → global config → const default.
- **Profiles** (`scripts/ProfileManager.gd`, format `wh40k_ai_profile`): JSON
  with a flat `parameters` map and a `rules` array. Rules have `conditions`
  (AND-ed) and `actions` (`override` / `multiply` / `add`).
- Rule conditions may only use 9 context keys, built at
  `AIDecisionMaker.gd:1739`: `phase, round, vp_diff, units_remaining_pct,
  nearest_enemy_inches, on_objective, is_melee_unit, is_vehicle, unit_points`.
- **The rule DSL is a natural target for machine- or LLM-authored policy.**
  Consider whether it is expressive enough, and what minimal extension would
  make it a good search space.

### The evaluation harness

- `40k/tests/run_ai_benchmark.sh` → `autoloads/AIBenchmarkRunner.gd`. Headless
  AI-vs-AI, one game per process, per-player profile injection via
  `--bench-p1-profile` / `--bench-p2-profile`.
- Per-game JSON fields: `actions_taken, battle_round, difficulty, fixture,
  note, p1_profile, p2_profile, seed, status, time_scale, vp,
  vp_diff_p2_minus_p1, wall_seconds, winner`. `vp` splits primary/secondary
  per player. That is the entire outcome signal available today.
- `40k/tests/make_mirror_fixture.py` builds a mirror-match fixture (identical
  army both sides) and validates it. `mirror_orks_postdeploy` is balanced to
  within ~2 VP; `--source 1` builds the Custodes mirror.
- Windowed scenarios (`40k/tests/scenarios/`, `run_scenario.sh`) drive the real
  UI and are the project's correctness gate.

## Hard constraints — design within these

1. **Compute.** 4 cores, ~2–3 concurrent games. 2.5 min/game on the small
   fixture, ~7 min on a 2000-pt mirror. That is roughly **200–500 games/day**,
   total. Any proposal requiring millions of episodes is out; say so plainly
   rather than proposing it with a caveat.
2. **No ML runtime in-engine.** Godot 4.4 / GDScript. Anything numerical lives
   in an external Python process operating on exported data. In-engine
   inference, if any, must be cheap and interpretable.
3. **Games are not perfectly seed-reproducible.** Seeds fix dice and deck
   order, but the AI's frame-paced action loop interleaves with wall-clock, so
   trajectories diverge under different CPU load. **This kills naive variance
   reduction** (paired seeds, common random numbers) and is probably the single
   biggest constraint on sample efficiency. Investigate whether it can be made
   deterministic, and cost that fix — it may be the highest-leverage prerequisite
   in the whole project.
4. **Measurement noise is brutal.** Per-seed margin sd ≈ 9–15 VP. A
   side-swapped paired design gets se ≈ 2.6 at n=10 per arm. Resolving a 5 VP
   effect needs ~60 seeds/arm ≈ 8 hours. **Your design must treat evaluation
   budget as the scarcest resource**, and should probably spend as much thought
   on cheap high-signal proxies as on the learning algorithm itself.
5. **Interpretability is a product requirement, not a nicety.** The game
   surfaces AI reasoning to players in the log ("Shield-Captain holds fire to
   stay Hidden"). A learned policy that cannot explain itself degrades the
   product. Weigh this when comparing approaches.

## Traps that have already bitten this project

Design against these; they are not hypothetical.

- **Fixture integrity.** The benchmark fixture every prior AI baseline was
  tuned on contained an army-list header row imported as a *unit*
  (`points: 2000`, `keywords: ["UNKNOWN"]`). It inflated army totals, doubled
  the Strategic Reserves cap, and left one side fielding 31% of its army. Every
  historical tuning decision in `tests/bench_baselines/` is suspect as a
  result. **A learning loop pointed at a broken environment will confidently
  learn garbage, fast.** What continuous validation prevents a recurrence?
- **Goodharting.** VP margin is a proxy. A loop optimising it may find
  degenerate strategies, exploit engine bugs, or overfit one matchup. The AI
  must also *look* like it is playing 40k.
- **Overfitting across matchups.** A change that helps an Ork mirror may lose
  to Custodes. Any accepted change needs multi-matchup evidence.
- **Silent DSL failures.** `_get_base_param_value` returns `0.0` for a
  parameter absent from the profile, so `multiply` against an undeclared
  parameter silently yields **zero**. Unknown rule condition types **pass**;
  unknown action types are **silently dropped**. A search process generating
  profiles will hit all three. What validation is needed?
- **Dead configuration.** 7 of 17 `AIDifficultyConfig` gates have no callers.
  `vp_diff` is always 0 in real games, so any rule keyed on it never fires.
  Audit before you build on any of it.

## Research questions

Answer these with reasoning and evidence, not preferences.

1. **What is actually learnable here, given 200–500 games/day?** Compare
   honestly: parameter search (CEM, SPSA, Bayesian optimisation,
   population-based training) over the ~N most influential constants; bandits
   or evolutionary search over profile *rules*; offline value/advantage
   estimation from decision records; imitation from human games; LLM-in-the-loop
   critique. For each: sample complexity, wall-clock to a detectable win,
   interpretability, failure modes, and implementation cost. Recommend one, and
   say what would change your mind.
2. **Where does an LLM genuinely help, and where is it theatre?** Candidate
   roles: post-game analyst reading decision records and proposing structured
   hypotheses; credit-assignment reasoner over traces; author/mutator of profile
   rules; designer of new *features* for the heuristic; judge of whether
   behaviour looks like real 40k. Be skeptical — for each role, what is the
   cheaper non-LLM baseline, and does the LLM actually beat it?
3. **Credit assignment.** 400–600 actions per game, one terminal VP signal.
   What intermediate signals exist or could cheaply exist (per-phase objective
   control deltas, per-unit points-traded, per-decision regret against a
   post-hoc better option)? Is counterfactual replay from a saved state
   feasible in this engine, and what would it cost?
4. **What to persist, and in what schema?** Design the game record: decision
   records, outcomes, fixture/profile provenance, engine version. Estimate size
   per game and the storage/query approach at 10k games. Note that a
   corrupt-fixture episode means provenance is not optional.
5. **The evaluation harness is the foundation.** Specify it: A/A validation,
   side-swapping, multi-matchup grids, sequential testing / early stopping to
   spend fewer games per hypothesis, and a regression suite so an accepted
   change cannot silently break behaviour that windowed scenarios cover.
6. **Determinism.** Investigate the frame-pacing non-determinism. Can the
   engine be made to step deterministically headless? What does that buy in
   variance reduction, and is it worth doing first?
7. **What does "learning" mean for the shipped product?** Offline (we train,
   players get a tuned profile) vs online (the AI adapts against a player).
   These have very different risk, testing and UX profiles. Recommend one and
   justify it.

## Deliverables

1. **Options analysis** — the credible approaches, compared on the axes above,
   with an explicit recommendation and the evidence for it.
2. **Target architecture** — data flow from game → record → dataset → analysis
   → proposed change → evaluation → accept/reject → shipped profile. Name the
   components, the file formats, and where each lives.
3. **Staged roadmap.** Milestone 1 must be **small, independently valuable, and
   shippable in days** — most likely "persist what the AI already knows and
   make one season of games queryable", since that is nearly free and unlocks
   everything else. Each later stage states its prerequisite and its kill
   criterion.
4. **Milestone 1 spec** in enough detail to implement without further design:
   schema, file layout, touch points, size estimates, tests.
5. **Risk register** — what makes this fail, what detects each failure early.
6. **A falsifiable success metric.** "The AI improves" is not one. Something
   like: *a fully automated cycle produces a change that beats the incumbent by
   ≥X VP at 2 standard errors on a ≥2-matchup grid, without regressing the
   windowed scenario suite.* Choose X and defend it against the measured noise.

## Rules of engagement

- **Verify before relying.** Read the code. Cite `file:line`. If this brief
  contradicts the code, the code wins — say so.
- **Distinguish what you ran from what you reasoned about.** If you did not
  execute it, do not describe it as measured.
- **Cost everything in wall-clock games**, the real currency here.
- **Prefer the boring option that works.** If plain parameter search over 15
  constants beats a sophisticated design at this sample budget, recommend it.
- **State what you are unsure about**, especially where a wrong assumption
  would invalidate the design.

## Non-goals

- Do not implement the framework.
- Do not tune any AI constants.
- Do not propose deep RL requiring millions of episodes, or a GPU training
  cluster.
- Do not assume the historical baselines in `tests/bench_baselines/` are sound
  — most predate the fixture fix.

# A learning loop for the 40k AI — design document

*Response to `research/ai_learning_framework_prompt.md`. Design only — nothing
here is implemented. Written 2026-08-06 against commit `60ce588`. Every code
claim was re-verified against the working tree; where this document contradicts
the prompt, the code won and the discrepancy is called out.*

---

## 0. The decision, in one page

**Build the boring loop, in this order:**

1. **M0 — guard the instrument** (hours): a fixture validator and a re-run
   A/A baseline on both mirrors. Nothing may be learned on an unvalidated
   environment again.
2. **M1 — persist what already exists** (1–2 days): the AI already produces
   full decision records and the harness already writes outcomes; they are
   never joined. One JSON record per benchmark game — decisions + outcome +
   provenance — and a nightly indexer that makes a season queryable in DuckDB.
3. **M2 — make evaluation cheap** (1–3 days): seed the handful of unseeded
   `randf()` sites in the AI layer, verify same-seed reproducibility, and wrap
   the benchmark in a paired, side-swapped, sequential-stopping A/B driver
   with an always-on A/A arm. This is where most of the project's leverage
   is: the experiment run for this document (§2.1) shows same-seed games
   already reproduce **exactly** — 787/787 identical action lines under
   concurrent CPU load — the moment difficulty score noise is off. The
   suspected frame-pacing problem measured as a non-factor; determinism is a
   small seeding fix, not an engine project.
4. **M3 — find the ~10 constants that matter** (1 day + ~300 games): a
   one-at-a-time sensitivity screen over the highest-traffic scoring weights.
5. **M4 — automated search over those constants** (2–4 days + the games
   budget): cross-entropy method with racing/early-kill, evaluated only
   through the M2 harness, gated by the windowed-scenario suite and a
   two-mirror grid. First fully automated accept/reject.
6. **M5+ — only after M4 pays out**: rule-DSL search (after fixing the dead
   `vp_diff` context and adding a profile linter), targeted counterfactual
   replay for credit assignment, LLM-authored rule mutation as a *proposer*
   inside the same evaluator.

**Recommended learner: cross-entropy method (CEM) over 10–15 scoring
constants**, population ~24, 4–8 paired games per candidate with early
kill, two mirror fixtures. It is the only option on the list whose sample
cost, implementation cost, interpretability and failure modes are all
compatible with 200–500 games/day (§4). LLMs are deliberately *not* in the
core loop (§RQ2): the project's own history — 1,029 transcripts mined into 31
findings, six implemented, measured at **−2.05 VP, CI [−7.2, +3.1]** — shows
hypothesis generation was never the bottleneck. Evaluation is.

**Falsifiable success metric** (§9): within one 30-day season and ≤12,000
games, the automated cycle produces a profile change that beats the shipped
default by **≥ +4 VP/game pooled across both mirror matchups at ≥2 standard
errors** (≈36 paired games per matchup), with no single matchup regressing
by more than 2 VP at 1 se, no stall-rate increase, and zero new failures in
the windowed scenario suite. If it cannot, the approach is killed, and the
data from M1 remains valuable on its own.

---

## 1. Ground truth, re-verified

The prompt asked for every claim to be checked. Verdicts, with citations into
the working tree at `60ce588`:

| # | Prompt claim | Verdict | Evidence |
|---|---|---|---|
| 1 | `_add_decision_record()` at `AIDecisionMaker.gd:457` emits `{decision_type, unit_id, unit_name, candidates, chosen_index, parameters_used, difficulty, context}` | **Confirmed** | `40k/scripts/AIDecisionMaker.gd:457-473` |
| 2 | "Currently only **5** call sites emit records" | **Wrong — it is 4** | repo-wide grep: `movement` `:2686`, `shooting` `:11807`, `charge` `:13397`, `fight` `:15168`. Nothing else calls it. |
| 3 | `AIPlayer` batches records per round/phase as `{round, phase, player, records}` at `AIPlayer.gd:3693` | Confirmed, keys slightly richer | Append at `40k/autoloads/AIPlayer.gd:2043-2050`; batch carries `round, phase_name, player, records, thinking_steps, actions` |
| 4 | Ring-buffered at 500 batches, `pop_front` into a dropped counter, cleared on `configure()` | **Confirmed** | cap `:3698` (500 desktop / 100 web), drop `:2053-2055`, clear `:266-268` |
| 5 | "Nothing anywhere writes it to disk (grep for a persist path returns nothing)" | **Wrong.** An export path exists | `export_decision_log()` `AIPlayer.gd:3702-3815` writes `user://ai_decision_log.json` (+ timestamped archive). Triggers: F10 keybind `:180-185`, every 50 batches mid-game `:2056-2061`, and on game-complete `:1843-1847`. What *is* true: the export is a visualizer feed — it contains **no outcome, no seed, no profiles, no fixture identity** — and each game overwrites the same `user://` file, so it functions as "last game's decisions", not a dataset. The game-complete trigger is also unreliable in benchmark runs: `_process` returns before `_evaluate_and_act` once `PhaseManager.game_ended` is set (`:187-190`), so the final flush depends on evaluation timing; only the every-50-batches refresh is dependable, which can leave up to 49 batches unwritten at quit. |
| 6 | Tuning surface: "hundreds of constants" read through `get_param` at `:421` | Overstated; resolution order confirmed | `get_param` is at `:428-442` (int variant `:444-454`), priority rule-override → player profile → global config → default as described. The *runtime-tunable* surface is **96 distinct `get_param` names + 8 `get_param_int` names ≈ 104 parameters** across 152 call sites; 152 `const` declarations exist in the file but only the ~104 are profile-reachable. |
| 7 | Profiles: flat `parameters` map + `rules` with AND-ed `conditions` and `override/multiply/add` actions | **Confirmed** | `ProfileManager.gd` (format tag `wh40k_ai_profile` `:114`), rule evaluation `AIDecisionMaker.gd:326-344`, actions `:393-414` |
| 8 | Rule conditions use 9 context keys built at `:1739` | **Confirmed** (built at `:1762-1772`, inside `decide()` which starts `:1739`); 13 condition *types* consume those 9 keys (`:346-391`) |
| 9 | Silent DSL failures: `multiply` on an undeclared param yields 0; unknown condition types pass; unknown action types dropped | **All three confirmed** | `_get_base_param_value` returns `0.0` for any param not in a profile or config override — including every param that only has a `const` default (`:416-426`), so `multiply`/`add` against a const-default param silently zero/no-op it (`:404-414`). `match` in `_check_rule_conditions` has no default arm → unknown types fall through to pass (`:348-391`). Unknown action ops match nothing → dropped (`:401-414`). **Additionally: `ProfileManager.validate_profile()` checks structure only** — it validates none of: parameter-name existence, condition-type validity, action-type validity (`ProfileManager.gd:111-137`). A generated profile passes validation and silently does nothing (or worse). |
| 10 | `vp_diff` is always 0 in real games | **Confirmed** | `_get_vp_diff` reads `meta.player1_vp/player2_vp` (`:1182-1189`); repo-wide grep shows those keys are written **only** by one test (`tests/test_ai_movement_coordination.gd:50`). Real VP lives at `GameState.state.players[pk].vp` (`MissionManager.gd:2947`). All five `vp_*` condition types are therefore dead in live play. |
| 11 | 7 of 17 `AIDifficultyConfig` gates have no callers | **Confirmed exactly** | of the 17 config functions, zero non-test callers for: `use_focus_fire`, `use_trade_analysis`, `use_look_ahead`, `use_weapon_efficiency`, `use_survival_assessment`, `use_screening`, `get_movement_iterations` |
| 12 | Harness: per-game JSON fields as listed; profile injection per player | **Confirmed** | `AIBenchmarkRunner.gd:174-200` (result dict), `:52-55` + `:160-172` (profiles), `run_ai_benchmark.sh:53-66` (seed = base+i, one process per game) |
| 13 | Seeds fix dice and deck order | **Confirmed, with an important caveat** | `set_test_seed` seeds RulesEngine dice and the secondary deck (`AIBenchmarkRunner.gd:91-100`). But the seeded path derives per-consumer seeds from a **global monotonic counter** — `hash([test_mode_seed, _test_seed_counter])`, `RulesEngine.gd:552-564` — so the dice stream depends on the *order and count* of RNG constructions. Any single divergent decision reshuffles all subsequent dice. Seeding is real but fragile to divergence, which amplifies the next row. |
| 14 | Games are not seed-reproducible; frame pacing is the suspected cause | **Confirmed non-reproducible — but the dominant cause is not frame pacing.** | Measured in §2. The AI layer itself calls the **global unseeded RNG**: score noise `_apply_difficulty_noise` uses bare `randf()` (`AIDecisionMaker.gd:861-867`) and is applied at Hard (noise 0.5 — `AIDifficultyConfig.gd:72-83`) inside movement ordering (a *sort comparator*, `:5598-5599`), charge scoring (`:13269`, `:13598`) and fight scoring (`:15368`). Easy-mode actions (`:2159` ff.), deployment fallback scatter (`:18738`), and reinforcement scatter (`AIPlayer.gd:3474`, `:3617`) are also bare `randf/randi`. Frame pacing (wall-clock `_eval_timer`, `AIPlayer.gd:187-209`; 2 s watchdog `:47`) exists but is secondary — see experiment. |
| 15 | Benchmark noise: per-seed margin sd ≈ 9–15 VP, paired se ≈ 2.65 at n=10 | **Confirmed from the committed baseline** | `tests/bench_baselines/2026-08-06_mirror_new_vs_old.md`: arm sds 10.03–15.46; paired effect sd 8.37, se 2.65 |
| 16 | Historical baselines suspect (corrupt fixture) | **Confirmed** | same file; placeholder-unit mechanism documented in `tests/make_mirror_fixture.py:38-60` (docstring), validator `validate()` at `:224` |

Two smaller corrections worth recording: the shooting record always stores
`chosen_index = 0` and only the *assigned* targets as candidates
(`:11791-11810`) — it records the plan, not the alternatives considered — and
the "hold fire to stay Hidden" branch returns `SKIP_UNIT` *before* the record
is emitted (`:11783-11788`), so the exact decision class the corpus work
cared about is invisible in today's records. Coverage is real but shallower
than "4 call sites" suggests.

Also relevant: `tests/bench_baselines/README.md` claims "the seed reproduces
it deterministically: dice AND secondary-deck draws are seeded." That is true
for the *streams* and false for the *game*: see §2.

---

## 2. What I ran (vs. what I reasoned about)

Everything in this section was executed in this container on 2026-08-06.
Everything outside it is reasoning, and is labelled as such.

### 2.1 The determinism experiment

**Design.** Four headless benchmark games on the clean mirror fixture
(`mirror_orks_postdeploy`), all with **the same seed (4242)**, time-scale 6,
run **concurrently on 4 cores** to maximise CPU-load interference — the exact
condition under which the prompt says trajectories diverge:

- `hard_a`, `hard_b`: difficulty 2 (Hard) — score noise 0.5 via unseeded `randf()`
- `comp_a`, `comp_b`: difficulty 3 (Competitive) — score noise 0.0 (the
  `randf()` in `_apply_difficulty_noise` is short-circuited at `:865-866`)

On this fixture, deployment and reinforcement scatter (the other unseeded
`randf` sites) never execute — every model starts deployed. So the
Competitive pair isolates: dice seeded, deck seeded, score noise off. Any
remaining divergence must come from frame pacing / wall-clock interleaving
or an unseeded source I have not found.

**Results.**

| game | difficulty | status | rounds | actions | margin (P2−P1) | VP P1 (pri+sec) | VP P2 (pri+sec) | wall s |
|---|---|---|---|---|---|---|---|---|
| hard_a | Hard | **stalled** (round 3, charge phase, "no progress for 90s") | 3 | 478 | −10 | 40 (18+22) | 30 (16+14) | 469.1 |
| hard_b | Hard | completed | 5 | 695 | −33 | 76 (39+37) | 43 (19+24) | 381.6 |
| comp_a | Competitive | completed | 5 | 762 | −7 | 66 (39+27) | 59 (32+27) | 414.8 |
| comp_b | Competitive | completed | 5 | 762 | −7 | 66 (39+27) | 59 (32+27) | 412.9 |

Beyond outcomes, I extracted every "Deciding for phase …" and "executing
action" line from each game's stdout and diffed the pairs:

- **The Competitive pair is identical at trajectory level — all 787 action
  lines match exactly**, down to per-decision available-action counts, while
  running concurrently with three other Godot processes on 4 cores.
- **The Hard pair diverges at line 59 of 389/547** — player 2's *first
  movement phase of round 1* (one run had consumed one more action than the
  other by the fifth movement decision). Divergence starts with the first
  noisy scoring pass and compounds from there into different games entirely
  — including a stall that exists in one run and not the other at the same
  seed.

**Interpretation.**

1. **Non-reproducibility is real at the difficulties the benchmark uses
   (Hard), and its dominant cause is the unseeded score-noise `randf()`, not
   frame pacing.** The prompt's constraint #3 names the wrong mechanism.
2. **With noise structurally off, the game is trajectory-deterministic under
   CPU-load interference** on this fixture — frame pacing, the 2 s watchdog,
   `Engine.time_scale`, and process interleaving did not alter a single
   decision across 762 actions. Determinism is therefore not an engine
   research project; it is a small, cheap seeding fix in the AI layer (M2).
3. **Stall triage at Hard is currently broken**: `tests/bench_baselines/README.md`
   says a stall's seed "reproduces it deterministically" — hard_a/hard_b is a
   same-seed counterexample (one stalled, one didn't). After M2, that claim
   becomes true.

*Caveats (n=1 pair per arm):* one fixture, one seed, one hardware profile;
no reserves/reinforcement scatter on this fixture (those `randf` sites —
`AIPlayer.gd:3474,:3617` — never executed); reactive human-gate windows
never opened (AI-vs-AI). M2 must re-verify across ≥10 seeds and on a
reserves-bearing fixture before "deterministic" is declared.

### 2.2 Measured sizes and throughput

From the same four games (mirror fixture, time-scale 6, 4 concurrent lanes
on 4 cores):

- **Wall clock: 382–469 s/game** (6.4–7.8 min) at 4 contended lanes. Ceiling
  ≈ 740–900 games/day at 4 lanes; the prompt's 200–500/day is the right
  planning number once the box does anything else. At 3 lanes expect
  ~5–6 min/game.
- **Decision-log export (existing visualizer path): 640 KB** pretty-printed
  for one game — 150 record batches, 150 decision records, 539 action-log
  entries, **0 batches dropped** (the 500 cap was never hit on this
  fixture; ~20% of actions carry a record at current 4-site coverage).
- **Stdout/debug logs: 41–51 MB per game.** This kills any "archive
  everything" instinct: at 400 games/day that is ~18 GB/day. Logs must be
  kept only for failed/stalled games (see §7).
- **The game-complete decision-log export never fired** in any of the four
  benchmark runs — zero timestamped archives exist; only the every-50-batches
  refresh ran (mtime during play). This empirically confirms the race
  described in §1 row 5 and motivates M1's export-at-quit placement.

### 2.3 Everything else

All other quantitative claims in this document (noise magnitudes, paired
standard errors, historical effect sizes) are read from the committed
baseline `2026-08-06_mirror_new_vs_old.md`, not re-measured. Sample-cost
arithmetic derived from them is reasoning, not measurement.

---

## 3. Research questions

### RQ1. What is actually learnable at 200–500 games/day?

The currency table first. From the committed baseline: per-seed paired
effect sd = 8.37 VP (side-swapped pairs, 2 games per pair). To detect an
effect Δ at 2 standard errors you need `n ≥ (2·8.37/Δ)²` pairs:

| Δ (VP/game) | pairs | games/matchup | wall-clock @ 3 lanes, ~5.5 min/game (measured §2.2) |
|---|---|---|---|
| 5 | 12 | 24 | ~45 min |
| 4 | 18 | 36 | ~1.1 h |
| 3 | 32 | 64 | ~2 h |
| 2 | 71 | 142 | ~4.3 h |

So the budget supports **tens of 4-to-5-VP-resolution hypothesis tests per
day** — if and only if evaluation is paired, side-swapped, and stopped early
for losers. That constraint picks the learner:

| Approach | games to a detectable (≥4 VP) win | implementation cost | interpretability | failure modes |
|---|---|---|---|---|
| **CEM over 10–15 constants** (recommended) | ~1,500–3,500/matchup: pop ~24 × 4–8 paired games × 8–12 generations, racing kills the bottom half at 4 games | Low: ~300 lines of Python driving the existing bench script | High: output is a param distribution; each accepted change is a readable profile diff | converges on fixture quirks (mitigate: 2-matchup grid, holdout); noise swamps rank order if games/candidate too low |
| SPSA | ~600–2,000 | Low code, **high tuning fragility** (gain sequences vs noise scale of ±8 VP) | Medium | divergence/oscillation invisible until games are spent; poor fit for racing |
| Bayesian optimisation (batch GP-EI) | ~1,000–2,500 | Medium-high: GP with heavy noise, batch async, 15-dim kernel choices | Medium | model misspecification silently wastes the budget; hard to debug at this noise level |
| Population-based training | needs persistent parallel populations ≫ 3 lanes | Medium | Medium | designed for cheap evals; at 4 min/game it starves |
| Bandits / evolution over **profile rules** | 3–10k+ (space is combinatorial) | Medium + **mandatory DSL linter first** (§1 row 9) | High (rules read as sentences) | silent-zero DSL traps; dead `vp_diff` context (§1 row 10) makes half the intended conditions no-ops until fixed |
| Offline value/advantage estimation from decision records | **0 extra games** (consumes M1 data) | Medium: feature pipeline + shallow model | High if kept linear/GBT | it proposes, cannot verify; garbage-in if record coverage stays 4-sites-shallow |
| Imitation from human games | n/a — **no dataset exists** | High (collection UX + volume) | High | cold-start; would take months of player games to matter |
| Deep RL | out of scope per brief — millions of episodes at 4 min/game is centuries | — | — | — |

**Recommendation: CEM with racing, fed by a one-day sensitivity screen (M3)
to choose the 10–15 dimensions.** It is rank-based (only needs *ordering*
under noise, which paired evaluation gives cheaply), embarrassingly parallel
at exactly the 2–3-lane concurrency the box has, trivially resumable
(population state is a JSON file), and its output is interpretable both as a
distribution and as a diff.

**What would change my mind:**
- If M2 determinism lands and same-seed replay becomes exact, common-random-number
  pairing will cut per-comparison variance further; if that drops the
  4-VP cost to ~15 games/matchup, Bayesian optimisation's
  evaluation-efficiency advantage becomes worth its fragility.
- If the M3 screen finds ≤5 constants dominate, plain coordinate descent
  beats CEM — simpler and fewer games.
- If the offline model (M1 data) predicts per-decision VP impact well,
  the ceiling of *weight tuning* is probably low and the budget should move
  to *feature* work (new heuristic terms), which parameter search cannot find.

### RQ2. Where does an LLM genuinely help?

The project already ran the natural experiment: the YouTube corpus pipeline
(`research/youtube/`) — 1,029 transcripts, 31 evidence-backed findings, six
implemented by hand — measured **−2.05 VP, CI [−7.2, +3.1]**. The pipeline
produced plausible, sourced, rules-correct hypotheses, and the sum of six of
them is indistinguishable from zero. The lesson is not "the ideas were bad";
it is that **at ±8 VP paired noise, idea quality cannot be judged without an
evaluator, so idea generation is not the binding constraint.**

| Candidate LLM role | Cheaper non-LLM baseline | Verdict |
|---|---|---|
| Post-game analyst reading records, proposing hypotheses | descriptive stats over the M1 dataset (win-rate by decision pattern, VP-event timelines) | **Theatre until M4 exists.** Afterwards: useful *only if* output is machine-testable (a profile JSON diff entering the same evaluator queue), never prose |
| Credit-assignment reasoner over 400–600-action traces | per-round VP deltas, points-traded ledger, targeted counterfactual replay (RQ3) | **Theatre.** The arithmetic signals are cheaper, unbiased, and already nearly free; an LLM narrating credit over a 500-action trace is unverifiable |
| Author/mutator of profile rules | templated/random mutation over the DSL grammar | **The one genuinely promising role**, because the DSL is small, human-legible, and lintable — an LLM proposes *semantically plausible* rules ("round ≥ 4 and behind → raise objective weights") that random mutation would take thousands of games to stumble on. Strictly gated by: linter (M2), fixed `vp_diff` (M5), and the same paired evaluator as every other candidate. Pilot in M5; kill if its accept-rate per game spent is not clearly above CEM's |
| Designer of new heuristic *features* | none — this is code synthesis | Real but **already the human+Claude workflow**; formalise the input (M1 dataset queries) and keep a human in the loop. Not an autonomous loop component |
| Judge of "does it look like 40k" | guardrail metrics: stall rate, scenario-suite pass rate, action-mix distribution drift, secondary/primary VP split | Metrics are the gate. An LLM reading the (already human-readable) game log as a **low-frequency spot audit** is cheap and occasionally catches what metrics miss; fine as advisory, never as a gate |

### RQ3. Credit assignment

400–600 actions, one terminal signal — but the engine already emits, or can
trivially emit, intermediate signals:

- **Per-scoring-event VP with reasons** — `MissionManager.victory_points_scored(player, points, reason)`
  already fires on every primary/secondary award (`MissionManager.gd:8`,
  emits at `:2949`, `:3026`); AIPlayer already subscribes (`AIPlayer.gd:160-162`).
  Recording `(round, phase, player, points, reason)` is a ~15-line collector
  (in M1). This yields per-round VP deltas for free.
- **Points traded per turn** — `SecondaryMissionManager._units_destroyed_this_turn`
  already tracks destruction for secondary scoring (`SecondaryMissionManager.gd:45`);
  unit points are in `meta.points`. A per-phase "alive points per side, OC per
  objective" digest appended to each decision batch is ~30 lines and turns
  every batch into a (state, action, next-state-delta) triple.
- **Regret against the AI's own scoring** — already in the records: gap
  between chosen candidate score and max candidate score (nonzero when noise
  or coordination overrides deflected the choice). Free, but measures
  deviation from the *heuristic's* opinion, not from truth.
- **Counterfactual replay** — feasible with existing parts, priced honestly:
  fixtures are ordinary saves; `SaveLoadManager` can write one mid-game; the
  MCP bridge's `dispatch_action` (see `40k/addons/godot_mcp/README.md`) can
  force the alternative branch before handing control back to the AI. Cost
  per studied decision ≈ 2 × remaining-game wall time (~2–6 min mid-game)
  **if M2 determinism holds** (one rollout per branch); ~10× that without it
  (Monte-Carlo over dice). Verdict: never en-masse; reserve for the top ~20
  suspicious decisions per season mined from the offline model.

The workable scheme is hierarchical: game outcome → per-round VP/points/OC
deltas → per-phase attribution → shallow model over decision-record features
as an advantage proxy → counterfactual replay only where the model and the
heuristic disagree loudly.

### RQ4. What to persist — see the M1 spec (§7), which is the answer.

### RQ5. The evaluation harness — see §5/§6; specified as M2.

### RQ6. Determinism

Mechanism, verified in code and measured in §2: three layers.

1. **Unseeded AI-layer RNG (dominant, cheap to fix).** Score noise at
   Normal/Hard runs through bare `randf()` (`:861-867`) — including inside a
   movement-ordering sort comparator (`:5598-5599`), so *activation order*
   is stochastic per run. Deployment/reinforcement scatter are also bare
   (`:18738`; `AIPlayer.gd:3474,:3617`). Fix: route through a dedicated
   `RandomNumberGenerator` seeded per game (+ per decision index), or run
   evaluation at Competitive where noise is structurally off.
2. **Order-sensitive derived seeding (amplifier).** Seeded mode hands each
   consumer `hash([test_mode_seed, ++counter])` (`RulesEngine.gd:552-564`):
   correct only while both runs request RNGs in identical order. Any single
   divergence cascades into every later dice roll. No fix needed if layer 1
   is fixed and layer 3 is quiet; a keyed-seed scheme (hash of game_id +
   action id — the per-action `rng_seed` recorded by `rng_for_action`,
   `:597-610`, is exactly this) is the robust upgrade.
3. **Frame pacing (real, measured secondary).** Evaluation fires from
   `_process` on wall-clock timers (`:187-209`, 50 ms FAST delay `:66-71`,
   2 s watchdog `:47`, spectator timers), and `Engine.time_scale` stretches
   them. Measured (§2.1): with layer 1 silenced, pacing changed **zero of
   762 actions** across two concurrently-loaded same-seed runs. Pacing
   affects *when*, not *what*, at least on a no-reserves fixture — so no
   engine-level fixed-step work is needed for the benchmark use case.

**What determinism buys:** exact same-seed replay (debugging + regression
repro), common-random-number pairing (variance ↓ for small policy diffs),
single-rollout counterfactuals (RQ3), and a hard A/A identity test for the
harness. **Recommendation: spend up to 2 days in M2; if same-seed
reproducibility is not achieved within that box, stop** — the paired
side-swap design already contains the noise (se 2.65 at 10 pairs) and
everything else in this plan works without determinism, just ~2–4× slower.

### RQ7. What does "learning" mean for the shipped product?

**Offline.** Train/search on the box, ship a static, human-reviewed,
version-stamped profile through the existing loader
(`AIDecisionMaker.load_player_profile` `:308-313` / the `ai_config.json`
override path `:280-306`). Reasons: (a) every accepted change passes the scenario suite
and a multi-matchup grid *before* a player sees it — online adaptation
cannot be gated that way; (b) interpretability is a product requirement
(the AI narrates its reasoning — `_narrate_decision_record`, `:516` ff.),
and a fixed profile keeps the narration truthful; (c) online learning
against a single human at 40k game counts (a player might play 20 games a
month) has no statistical power at ±9–15 VP noise; it would be adapting to
dice. The only defensible "online" feature is picking among 2–3 *shipped,
fully-tested* profiles based on the player's win history — a UX difficulty
knob, not learning, and out of scope until M4 has paid for itself. Note:
shipped profile changes are player-facing → each accept gets a
`40k/data/version_history.json` entry per project policy.

---

## 4. Deliverable 1 — options analysis

Covered in RQ1 (table + recommendation + reversal conditions). Summary
judgement: **parameter search is the only approach whose cost curve fits the
budget today**; offline estimation from M1 data is the free companion that
chooses *which* parameters and sanity-checks directions; rule-DSL search and
LLM proposal are staged behind harness + linter prerequisites; imitation and
deep RL are out.

---

## 5. Deliverable 2 — target architecture

```
                       ┌────────────────────────────────────────────┐
                       │ GDScript (in-engine, headless)             │
 fixture (.w40ksave)──▶│ AIBenchmarkRunner                          │
 profiles (.json) ────▶│  • seeds dice+deck (+M2: AI-layer RNG)     │
 seed, difficulty ────▶│  • plays 1 game per process                │
                       │  • collects vp_events (M1)                 │
                       │  • writes result JSON (today)              │
                       │  • writes game record JSON (M1):           │
                       │    decisions+outcome+provenance            │
                       └───────────────┬────────────────────────────┘
                                       │ user://test_results/bench/*.json
                                       ▼
        ┌──────────────────────────────────────────────────────────┐
        │ Shell: 40k/tests/run_ai_benchmark.sh (exists)            │
        │        tools/ai_lab/run_paired.py (M2): seed-paired      │
        │        side-swapped arms, sequential stop, A/A arm       │
        └───────────────┬──────────────────────────────────────────┘
                        │ moves/gzips records → bench_data/season_N/games/
                        ▼
        ┌──────────────────────────────────────────────────────────┐
        │ Python offline lab: tools/ai_lab/ (M1–M4)                │
        │  build_index.py  JSONL→Parquet; DuckDB views             │
        │  fixture_check.py  M0 validator (points sums, UNKNOWN    │
        │      keywords, mirror symmetry, model counts)            │
        │  params_manifest.py  greps the ~104 get_param names +    │
        │      defaults out of AIDecisionMaker.gd → manifest JSON  │
        │  validate_profile.py  DSL linter vs manifest (kills the  │
        │      silent-zero / unknown-type traps)                   │
        │  analyze.py  per-decision features, VP-delta joins,      │
        │      fitted-weight comparison, regret mining             │
        │  cem_driver.py (M4)  population state, racing,           │
        │      accept/reject campaign log                          │
        └───────────────┬──────────────────────────────────────────┘
                        │ candidate profile JSON (linted)
                        ▼
        ┌──────────────────────────────────────────────────────────┐
        │ Gates (all must pass to ship)                            │
        │  • paired grid: Ork mirror + Custodes mirror (+A/A arm)  │
        │  • windowed scenario suite (478 files, run_scenarios.sh) │
        │  • stall-rate & action-mix guardrails                    │
        │  • human review of the profile diff + auto-summary       │
        └───────────────┬──────────────────────────────────────────┘
                        ▼
      shipped profile → 40k/data/… + version_history.json entry
```

File formats: game records = one gzipped JSON per game (schema §7);
season index = Parquet + a DuckDB file; campaigns = one JSON per candidate
(games played, sequential-test trajectory, verdict, provenance). Everything
under `bench_data/` (gitignored except campaign summaries and accepted
profiles, which are committed).

Components deliberately reused: the bench runner, the shell loop, the
mirror-fixture builder + `validate()`, the scenario suite, the profile
loader, and the decision-record machinery. New code is almost entirely
offline Python; in-engine additions are ~100–150 lines (M1 export + vp
collector + M2 seeding).

---

## 6. Deliverable 3 — staged roadmap

| Stage | What ships | Prerequisite | Kill criterion |
|---|---|---|---|
| **M0** (hours) | `fixture_check.py` + re-run A/A on both mirrors (Custodes mirror built via `make_mirror_fixture.py --source 1`); document both F̂ values | none | none — pure guard; if the Custodes mirror fails validation, fix before anything else |
| **M1** (1–2 days) | per-game record persistence + season index (spec §7) | M0 | none — foundational; if record size explodes (>5 MB/game gz) trim candidates’ `score_breakdown`, keep the rest |
| **M2** (1–3 days) | AI-layer RNG seeding; same-seed repro test; `run_paired.py` (side-swap, sequential stop, A/A arm); DSL linter + params manifest | M1 (records prove repro) | determinism sub-goal: if same-seed games are not identical after 2 days of seeding work, ship the paired driver without CRN and move on |
| **M3** (1 day + ~300 games) | sensitivity screen: ±30% one-at-a-time on ~15 candidate weights × 6 paired games; ranked influence list | M2 | if <5 params move the margin ≥2 VP, switch M4 to coordinate descent |
| **M4** (2–4 days + 1.5–3.5k games/matchup) | CEM campaign driver + full gate pipeline; **first automated accept/reject** | M3 | the §9 metric: no accepted ≥4 VP profile within one 30-day season → stop tuning weights; pivot to feature work informed by M1 data |
| **M5** (later, orderable) | (a) fix `vp_diff` context + instrument command/scoring/reactive decision sites; (b) rule-DSL search with linted mutation, optionally LLM-proposed; (c) counterfactual replay tool for top-N mined decisions; (d) periodic behaviour spot-audit | M4 accepted at least one change (proves the loop) | each sub-item individually killable: rule search dies if accept-rate per 1k games < CEM's; LLM proposer dies if not beating templated mutation per game spent |

Throughput sanity (measured, §2.2): 6.4–7.8 min/game at 4 contended lanes ⇒
M3's ~300 games ≈ one overnight run; M4's 1.5–3.5k games/matchup ≈ 4–9 days
of background compute at a realistic 400/day — which is why racing/early-kill
and the M2 harness exist before M4 starts.

---

## 7. Deliverable 4 — Milestone 1 spec

**Goal:** every benchmark game leaves behind one self-describing record
joining decisions, outcome, and provenance; a season of them is queryable
with DuckDB in one line. No behaviour change to the game.

### 7.1 Schema — `wh40k_ai_game_record` v1

One JSON object per game, written next to the existing result file, then
gzipped by the shell:

```jsonc
{
  "schema": "wh40k_ai_game_record",
  "schema_version": 1,
  "game_id": "<stamp>_<fixture>_<seed>_<arm>",        // assigned by shell via --bench-out naming
  "provenance": {
    "git_sha": "<from --bench-git-sha, shell-supplied>",
    "engine": "<Engine.get_version_info().string>",
    "fixture": "mirror_orks_postdeploy",
    "fixture_sha256": "<FileAccess.get_sha256 of the .w40ksave>",
    "p1_profile": {"path": "...", "sha256": "...", "inline": { /* full JSON */ }},
    "p2_profile": {"path": "...", "sha256": "...", "inline": { }},
    "difficulty": {"1": 2, "2": 2},
    "seed": 4242,
    "time_scale": 6.0,
    "schema_note": "records cover decision types: movement, shooting, charge, fight"
  },
  "outcome": { /* exactly the existing _collect_result() dict, AIBenchmarkRunner.gd:174-200 */ },
  "vp_events": [ {"round": 2, "phase": 9, "player": 1, "points": 5, "reason": "..."} ],
  "decisions": [ /* verbatim _all_decision_records batches, AIPlayer.gd:2043-2050 */ ],
  "action_log": [ /* verbatim _action_log entries: phase, action_type, description, player */ ],
  "decision_batches_total": 412,
  "decision_batches_dropped": 0
}
```

Provenance is non-negotiable (the corrupt-fixture episode): `fixture_sha256`
+ `git_sha` + full inline profiles make every game auditable and every
cross-era comparison detectable as such.

### 7.2 Touch points (all verified against current code)

1. **`AIBenchmarkRunner.gd`**
   - `_kick_off()`: after `ai.configure(...)` (`:116`), raise the record cap
     for the benchmark process: `ai._max_decision_record_batches = 100000`
     (plain `var`, `AIPlayer.gd:3698`; one game fits in RAM headless — see
     measured sizes §2.2). Connect `MissionManager.victory_points_scored`
     to a local `_vp_events` collector (signal exists, `MissionManager.gd:8`).
   - `_write_and_quit()` (`:211-222`): assemble the record from
     `ai._all_decision_records`, `ai._action_log`, `_vp_events`,
     `_collect_result()`, and provenance; write `<out>.record.json`
     **before** `get_tree().quit()`. Writing here (not on game-complete)
     covers completed *and* stalled games and dodges the game-ended race
     documented in §1 row 5.
   - New args: `--bench-git-sha=`, optional `--bench-record-out=`.
2. **`run_ai_benchmark.sh`**: pass `--bench-git-sha=$(git rev-parse --short HEAD)`;
   after each game `gzip` the record and `mv` into `bench_data/…` when a
   `BENCH_DATA_DIR` env var is set (default: leave in userdata).
3. **`tools/ai_lab/build_index.py`** (new, offline): scan a season directory,
   flatten to three Parquet tables — `games` (one row per game: outcome +
   provenance hashes), `decisions` (one row per record: game_id, round,
   phase, player, decision_type, unit, chosen/best score, n_candidates,
   parameters_used), `vp_events`. Emit `season.duckdb` with views joining
   them. Pandas+pyarrow or DuckDB directly; ~150 lines.
4. **No AIPlayer/AIDecisionMaker changes** in M1. The existing
   `export_decision_log()` visualizer path is left untouched.

### 7.3 Size and cost estimates

Anchored to the measured export (§2.2: 640 KB pretty-printed for 150
batches + 539 action-log entries): the M1 record adds outcome + provenance
+ vp_events (~2–5 KB) on top of the same payload. Compact JSON (no
pretty-print) roughly halves it; gzip takes it to **~40–80 KB/game**.

- 10k games ≈ **0.4–0.8 GB gzipped** records + ~100–200 MB Parquet. Query
  via DuckDB directly on Parquet; no database server, no schema migration
  machinery — a season directory is the unit of retention.
- Stdout/debug logs are **not** part of the record (41–51 MB/game measured).
  The shell keeps them only when `outcome.status != "completed"`, gzipped,
  capped at the newest 50 failures.
- In-RAM cost of the raised batch cap: 150 batches ≈ 0.6 MB → even a
  10× longer game stays ~10 MB. Safe headless; the cap stays at 500 for
  normal desktop/web play (M1 touches only the benchmark path).
- Implementation: ~60–90 lines GDScript (runner export + vp collector),
  ~30 lines shell, ~150 lines Python indexer, plus tests. 1–2 days
  including the smoke test.

### 7.4 Tests

- `tests/test_game_record_export.gd` (headless): construct the record dict
  from synthetic AIPlayer state via the same assembly function (factor it
  as a static helper so it is testable without a full game); assert schema
  fields, batch passthrough, dropped counter.
- One integration smoke in the shell: run a 1-game benchmark at
  `--bench-max-seconds=120` on the small fixture, assert the record file
  exists, parses, `outcome.status ∈ {completed, stalled}`, and
  `decisions.size() > 0`. (Headless-only is legitimate here per project
  policy — no UI affordance.)
- `build_index.py --selftest`: index the smoke game, assert row counts.

### 7.5 Explicitly out of M1

Instrumenting more decision sites (M5a), per-phase board digests (M5a/RQ3),
determinism (M2), any analysis conclusions. M1 only makes the data exist.

---

## 8. Deliverable 5 — risk register

| # | Risk | Early detector |
|---|---|---|
| 1 | **Broken environment** (the fixture trap, again) | M0 validator runs before every campaign; A/A arm always-on — `|F̂_AA − F̂_swap| > 2se` halts the campaign automatically (the 2026-08-06 baseline's own cross-check, made mandatory) |
| 2 | **Goodharting VP margin** — degenerate-but-winning behaviour | guardrail metrics logged per campaign: stall rate, battle-round distribution, action-mix drift vs baseline, primary/secondary split; windowed scenario suite as hard gate; low-frequency human/LLM log audit |
| 3 | **Sequential p-hacking** (peeking until significant) | stopping rules pre-registered in the campaign JSON; every game logged and counted; the driver, not the human, decides stop/continue |
| 4 | **Silent DSL failures** poisoning search | linter blocks unknown params/types and `multiply`/`add` on parameters that would resolve to the 0.0 base (`:416-426`); candidate profiles that lint clean but change nothing are caught by the A/A-identical-behaviour check (same seed, same trajectory ⇒ candidate is a no-op) |
| 5 | **Determinism fix fails or regresses gameplay** | M2 kill-box (2 days); same-seed repro test becomes a permanent CI check if it lands; if it doesn't, paired stats carry the plan at ~2–4× cost |
| 6 | **Overfitting to the mirror pair** | accept requires both mirrors; quarterly, re-derive the (fixed) asymmetric matchup as a holdout — evaluated only at accept time, never tuned on |
| 7 | **Engine drift mid-season** (rules fixes land during a campaign) | `git_sha` in every record; the index refuses cross-SHA pooling by default; campaigns pin a SHA |
| 8 | **Ring-buffer loss / stalled-game data loss** | cap raised in bench mode (M1); record written in `_write_and_quit` on *all* exit paths; `decision_batches_dropped` stored and asserted 0 in healthy games |
| 9 | **Compute contention** (campaign vs. dev work on one box) | campaign driver has a games/day budget and `nice`s its lanes; per-game wall-seconds tracked — drift up >50% flags contention |
| 10 | **Interpretability erosion** (product requirement) | accepted diffs capped (e.g. ≤±50% per constant per campaign); every accept ships an auto-generated "what changed, expected effect, evidence" note; narration path (`_narrate_decision_record`) untouched by tuning |
| 11 | **The loop works but the effect is fixture-local** (learned +4 VP that no player feels) | holdout matchup at accept; M5 spot-audits sample real difficulty settings (players face Normal/Hard, not Competitive) |

---

## 9. Deliverable 6 — the falsifiable success metric

> **Within one 30-day season and ≤12,000 games, the fully automated cycle
> (hypothesis → games → sequential decision → gates), with no human edits
> between proposal and verdict, produces at least one profile change that:**
> **(a) beats the shipped default by ≥ +4 VP/game pooled across the Ork and
> Custodes mirrors at ≥ 2 standard errors** (≈18 side-swapped pairs = 36
> games per matchup; pooled se ≈ 8.37/√36 ≈ 1.4, so +4 VP clears 2se with
> margin);
> **(b) shows no matchup worse than −2 VP at 1 se;**
> **(c) does not increase the stall rate** (per-campaign, against the same
> seeds);
> **(d) passes the windowed scenario suite with zero new failures; and**
> **(e) the concurrent A/A arm stays within 2 se of zero.**
> If no change meets (a)–(e) inside the season, the weight-tuning approach
> is falsified at this budget and is stopped in favour of feature work.

Why X = 4: it is the smallest effect confirmable inside a two-matchup gate
for under ~100 games (fast enough to run many candidates to completion), it
exceeds the −2.05 ± 2.65 blur of the last hand-tuning attempt (so the loop
must demonstrably beat the human-in-the-loop status quo, not tie it), and it
is large enough (≈ one secondary tick per game) to plausibly survive
transfer out of the tuning fixtures. And why a *deadline*: an unfalsifiable
"keep searching" loop is exactly the failure mode the brief warns about;
12,000 games ≈ 30 days × 400 games/day is the honest capacity ceiling.

---

## 10. Stated uncertainties

1. **Determinism evidence is one pair on one fixture.** The Competitive-pair
   identity (787/787 action lines) is a strong existence proof, but it was
   one seed, one no-reserves fixture, one machine. Reinforcement scatter
   (`AIPlayer.gd:3474,:3617`), deployment scatter (`AIDecisionMaker.gd:18738`),
   and reactive-window timing never executed. M2's acceptance test — ≥10
   seeds × 2 runs on both a clean and a reserves-bearing fixture — is what
   turns "observed once" into "property of the system".
2. **The paired-sd (8.37) is measured on one fixture, one difficulty, n=10.**
   The sample-cost table inherits that uncertainty; M0's re-baseline on both
   mirrors tightens it before anything expensive runs.
3. **Record coverage is shallow** (4 sites; shooting records omit
   alternatives and the hold-fire branch, §1). Offline analysis in M3–M4 sees
   a biased slice of the policy until M5a widens instrumentation. This is a
   known limitation of the M1 dataset, accepted to keep M1 at 1–2 days.
4. **Competitive-difficulty evaluation vs. shipped difficulty.** Evaluating
   with noise off (or seeded) measures a slightly different policy than the
   Normal/Hard players face. Mitigation: M4 confirms accepted candidates at
   Hard-with-noise before shipping; residual risk noted in risk #11.
5. **I did not run** the scenario suite, the Custodes mirror build, or any
   multi-game A/B in this session — quoted costs for those are reasoning
   from the committed baseline, not fresh measurement.

---

## Appendix A — citation index (all verified 2026-08-06)

- Decision records: `AIDecisionMaker.gd:457-473` (helper), `:2686`, `:11807`,
  `:13397`, `:15168` (the only 4 emit sites), `:1806` (cleared per decide),
  `:1921-1927` (attached to result); `AIPlayer.gd:2038-2061` (batch append,
  cap enforcement, 50-batch auto-export), `:3693-3700` (accumulator + cap),
  `:266-268` (cleared on configure), `:3702-3815` (export content & paths).
- Tuning surface: `get_param` `:428-442`, `get_param_int` `:444-454`,
  `_get_base_param_value` `:416-426` (the 0.0 trap), rules `:326-344`,
  conditions `:346-391` (unknown-type passes), actions `:393-414`
  (unknown-op dropped), context build `:1749-1804`, `_get_vp_diff`
  `:1182-1189` (dead in live play), `ProfileManager.gd:111-137`
  (structure-only validation).
- Difficulty: `AIDifficultyConfig.gd:12-124` (17 gates; 7 caller-less),
  noise table `:72-83`; noise application `AIDecisionMaker.gd:861-867`,
  call sites `:5598-5599`, `:13269`, `:13598`, `:15368`.
- RNG: `RulesEngine.gd:544-641` (RNGService, counter-derived seeds,
  factories, `set_test_seed`), `:597-610` (`rng_for_action` records
  per-action seeds — the natural replay hook).
- Harness: `AIBenchmarkRunner.gd` (whole file, 222 lines),
  `run_ai_benchmark.sh` (117 lines), `make_mirror_fixture.py` (`validate()`
  at `:224`), `tests/bench_baselines/2026-08-06_mirror_new_vs_old.md`.
- Pacing: `AIPlayer.gd:47` (watchdog 2 s), `:63-89` (speed presets, 50 ms
  FAST), `:187-209` (`_process` loop), `AIBenchmarkRunner.gd:122`
  (`Engine.time_scale`).

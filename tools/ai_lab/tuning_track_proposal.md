# V2-6 parameter-tuning track: PROPOSAL (not run), revised after two reviews

2026-10-31 · protocol_v2.md rule V2-6 · code HEAD 84d65b2 (AI code unchanged since 36b8626; AIDecisionMaker.gd md5 aec32113 = shipped 1.56.8)

- **Trigger.** Round 5 closed at 08:57 with nothing to bench (STATUS.md): marginal_oc none; attack_move dropped at h2; charge_target parked (V2-1 gate 0.33/game); ranged_hold_vs_centre parked (0 [HEAVY] weapons on the bench). Shipped gain 0 VP ≤ +0.5 VP, so V2-6 requires this proposal.
- **Nothing was run for it:** no screen, CEM, tuning or bench game. Only offline work: simulations; reads of code, records and sessions; one ai_versions.py test with a fake godot (no game launched).
- Tags: **(M)** measured or verified (records, sessions, code, offline tool test) · **(S)** simulated · **(E)** estimate or model · **(A)** assumption. container-h = hours of one 4-core sibling container. Changes against the reviews: "Review notes" at the end.

## 1. Answer first

- **Recommendation: hold.** This is a judgement about cost and priority; the simulation cannot decide it (table below). Start no tuning now: the V2-4 audit bundle is heading for its own V2-2 bench, and tuning must use the code that ships. After that decision, run at most the one-generation probe of §3, once, and only if its cost is not needed for higher-priority work (V2-4 bench, V2-5 reserve fixtures, new fixtures). Do not run the drafted multi-stage track.
- **The payoff is unknown, not known to be small.** The probe can ship only a large effect: V2-2 alone needs a true gain of 1.08 VP for a 50% chance at σ 10.26 (S). The odds depend on the spread τ and mean μ of the 8 candidates' true effects θ. Neither is measured for profile moves. The 5 code arms measured vs V7D (pooled E −0.21 to +1.17) spread less than noise: they allow τ up to ~1.2 VP (one-sided 5%) for code arms (S) and say nothing about profile moves.

| θ ~ N(μ, τ²), VP (A) | P(ship & θ>0) | P(ship & θ≥0.5) | E[shipped gain], VP |
|---|---|---|---|
| μ 0, τ 0.25 | 0.035 | 0.006 | +0.010 |
| **μ 0, τ 0.5 (main case, A)** | **0.10** | **0.07** | **+0.075** |
| μ 0, τ 1.0 | 0.31 | 0.29 | +0.45 |
| μ 0, τ 1.2 | 0.39 | 0.38 | +0.68 |
| μ −1, τ 2 | 0.43 | 0.42 | +0.99 |
| μ −2, τ 2 | 0.24 | 0.23 | +0.46 |

  (S: rule B, σ 10.26, 100,000 reps; full grid in §5.) In short: ≤ 0.10 if τ ≤ 0.5; 0.31-0.39 at τ 1.0-1.2 (μ 0); 0.24-0.43 at τ 2 with μ −1 to −2; ≤ 0.015 in a near-null pool (τ ≤ 0.1), where most ships would be false (§5c). Main case = middle of the 0-1.2 VP range the code arms allow; read the whole table. A no-ship tells little: it fits any τ below ~1 VP.
- **Further reasons to hold.** A ship tunes 3 bench matchups that miss much of the game: 0 attached leaders, 0 [HEAVY], 86 of 273 params inert, bench Orks = Kult of Speed, not the sweeps' Orks_2000 list (M). Waiting costs little: the probe must tune the post-V2-4 code anyway.
- **Probe cost (E).** 8.0 engineering hours on the probe path (§2a; ≤ 14 h if T8 is built in full). Then 53-81 sibling sessions, 22.5-49.1 container-h (expected 31-36), $26-60 sibling LLM tokens + parent orchestration ≥ $13-20, and 3.4-6.6 h wall on 14 containers (expected 4.4-5.1 h) plus parent lag at 4-6 barriers.
- **Drafted track:** 251-279 sessions, 86-110 container-h, 10.3-13.5 h; 3.6× the probe's container-h at 1 look, 2.3× at 3 looks; adds +0.004 / +0.015 / +0.086 to P(ship & θ>0) at τ 0.25 / 0.5 / 1.0 (μ 0, rule B for both; S).
- **Deviation from V2-6's wording.** V2-6 names cem_driver.py / sensitivity_screen.py; the probe uses neither loop. A live screen cannot rank at this noise (§3, S). cem_driver.py today rates only the first candidate of each generation (T1, M). One CEM generation with no refit is random sampling plus racing. All probe games run through ai_versions.py: the harness Stage C uses, where A/A exactness was measured (§2a). Hardening the two loop tools costs a further 7.75 h (E, §2b).

## 2. Prerequisite work

### 2a. Probe path (all needed before the first probe game)

| ID | Work → done when | Where (file:line) | h (E) |
|---|---|---|---|
| P1 | Sampler + lint: 8 profiles from N(default, (0.3·default)²) per dim, clipped to default × (1 ± 0.5), sampler seed recorded; validate_profile.py; rejects any param outside the 8 dims; canonical hash = sha256(json.dumps(parameters, sort_keys=True)) | new; validate_profile.py | 1 |
| P2 | Collision guard: --tag required and unique per (stage, generation, candidate, fixture, hash[:8]); --season must be new and empty, refuse a season holding records with another profile hash; margins() keeps only records whose provenance hash matches; the fake-godot collision test becomes a selftest | ai_versions.py:81-93, 122, 151; run_lanes.py:109-124 | 1.5 |
| P3 | Job generator: one job per (candidate, fixture); base = extracted SHIP copy, cand = HEAD + --cand-profile; asserts HEAD's AIDecisionMaker.gd blob = SHIP's; --rules11e --difficulty 3; --max-seconds 1800 (2400 ork); seeds from T16; profile sent base64 | new | 1.5 |
| P4 (= T9) | TUNE_RESULT template + TUNE kind in save_shard.py: per seed M1, M2, status; per-(arm, seed) trajectory hash; provenance (canonical hash, rules, difficulty, fixture sha256, git sha, per-seat AI blob) | .ai_lab_work/make_bench_prompts2.py:25-29, 50; .ai_lab_work/save_shard.py | 1.5 |
| P5 | merge_tuning.py: provenance checks; equal-weight pooled E and SE (decide_v2 formula) on common seeds; race → top 4; final → rule-B pick; applies the stop rules | new | 1.5 |
| T13 | M1 and M2 in one pool (today all M1 games, then all M2) | ai_versions.py:132-133 | 0.5 |
| T16 | Seed registry: Gate 0 38001/38101/38201; race/final 40001-48999; holdout 49001-49999; asserted disjoint from V2-1 (91001/91101/91201), V2-2 (94001-94288, 95001-95254, 99001-99254), V2-3 (5301-5324), vs_baseline.py (31001+) and older benches | new | 0.5 |
| | **Probe path total** | | **8.0** |

Facts behind 2a (M unless tagged):
- **Tag/season collision on the ai_versions path (P2).** run_lanes.run_one skips any seed whose `*_<arm>_<seed>.record.json.gz` is already in the season (arm = `<tag>_M1/_M2`). ai_versions.margins keys on (arm, seed) with no profile filter. Every --cand-profile run gets the default tag `HEAD_vs_HEAD`. Offline test with a fake godot (/tmp/review_tt/sim_aiv_collision.py, re-run here): candidate B in A's season launched 0 games and reported E 0.0, which is A's result (B's synthetic true E: +6.0). The V12 shard template has the same flaw: it pools every record in /tmp/season keyed only on M1/M2. The previous job line also lacked the required --season and a --tag.
- **The extracted SHIP base removes the seat leak.** Each seat's script has its own static _current_player and profiles, so the Rapid Ingress / Epic Challenge leak (T6) cannot occur. A/A exactness is measured in exactly this design (extracted V7D base vs HEAD + profile, the LF/RI arms): pairs with no fix tag in either game had M1 == M2 in 18/18 asy and 16/16 ork LF pairs and 3/3 ork RI pairs. The cus shards logged no per-game tags, so cus is untested in this design. At difficulty 3 the score noise returns before drawing (AIDecisionMaker.gd:2515-2520); AIPlayer.gd:3062 draws only a path-visual name.
- **One leak remains.** AIPlayer.gd:1699 and :2788 call HEAD's `AIDecisionMaker._compute_movement_toward_target` directly, not via `_dm()`. With threat_data = [] it reads only MOVE_LADDER_FAIL_BUDGET and MOVE_RIGID_BLOCK_FIRST, neither in the 8 dims; P1 rejects both.
- **Records already identify the candidate** (T9 corrected): profile path, sha256 and inline parameters per seat; rules, dispositions and difficulty in the outcome; fixture sha256 (AIBenchmarkRunner.gd:609-613, 786-793). The gaps: records stay in the sibling container (mean 94.3 KiB gz, above the 64 KiB message cap), BENCH_RESULT drops these fields, and no record names the per-seat AI script.

### 2b. Loop-tool hardening (only to use cem_driver.py / sensitivity_screen.py later)

| ID | Problem → fix | file:line | h (E) |
|---|---|---|---|
| T1 | All CEM candidates share one season; run_lanes skips seeds the first candidate played, so later candidates get E with n=0 (M, offline). Fix: one season per evaluation + the P2 guard | cem_driver.py:176-179, 196-200; run_lanes.py:109-124; run_paired.py:120-130 | 1 |
| T2 | --bench-11e never reaches the runner: legacy Take and Hold + the 10e deck (M). Fix: pass --rules11e; filter records on rules, difficulty, fixture | run_paired.py:67-70, 105-107, 225-249; cem_driver.py:68-73; sensitivity_screen.py:74-81; gate_candidate.py:72-78 | 1 |
| T3 | Default difficulty 2; the bench uses 3. They differ in score noise (0.5 vs 0; AIDecisionMaker.gd:2515), trade analysis (3 only; :16259) and charge threshold modifier (0.85 vs 0.7; :17532). Look-ahead and movement iterations are not consumed (AIDifficultyConfig.gd:52, 91). Fix: default 3 | cem_driver.py:115; sensitivity_screen.py:102; run_paired.py:242; gate_candidate.py:144; run_lanes.py:250 | 0.25 |
| T4 | --max-seconds 400: 20.5% of 224 cus games ran longer (M, older code); lost pairs drop silently. Fix: 1800 s (2400 ork), per-arm status counts. On the probe path the caps are job arguments | cem_driver.py:116, 181; sensitivity_screen.py:103, 138-140; run_paired.py:106, 296-299 | 1 |
| T5 | One fixture per run. Fix: per-fixture jobs, equal-weight pooled E | cem_driver.py:104; sensitivity_screen.py:94-96; gate_candidate.py:69 | 0.5 |
| T8-loop | Serial loops in one container. Fix: propose/tell split with saved RNG state, refit, screen job emission/ingestion. (The old T8's probe parts are P3-P5) | cem_driver.py:153-238; sensitivity_screen.py:123-153; run_paired.py:278-309 | 4 |
| | **Hardening total** | | **7.75** |

### 2c. Other (not needed for the probe)

| ID | Problem → fix | file:line | h (E) |
|---|---|---|---|
| T6 | RI and Epic Challenge never set _current_player. RI reads the seat that called decide() last, usually the active (opposing) seat. Epic Challenge usually reads the right seat: 349/359 cus decisions follow the same player's SELECT_FIGHTER (M). Needed only for --base HEAD jobs whose profile touches the 16 params that can change the RI decision or the 2 Epic Challenge params. Not for this probe: on these fixtures RI is always the same choice (Allarus Custodians from Deep Strike, 224/224 cus games, M; 0 on asy/ork per the audit); its score is ≥ 7.0 (275 pts / 50 + 1.5 melee + 1.0 ranged − 1.0, M) > MIN_SCORE 3.0 for any dim-3 value; dim 4 reaches RI only through objective `priority`, which RI does not use; placement uses none of the 8 dims. Fix: set/restore it + failing-first unit test | AIDecisionMaker.gd:26578, 25260 (readers :1459, :1480); AIPlayer.gd:1263, 1479 | 2 |
| T7 | From Golden Light END_TURN_REDEPLOY is decided by the unit's opponent (11.9 decisions per cus game, M); reads 0 params. Fix: route it to the owner | AIPlayer.gd:2023-2075, 2252; AIDecisionMaker.gd:21114, 21155; ScoringPhase.gd:1246-1253 | 2.5 |
| T10 | FIX_RI_* (read through _ri_part_on) are missing from the manifest | params_manifest.py:38; AIDecisionMaker.gd:12343-12345 | 0.5 |
| T11 | ×(1±d) cannot flip 18 toggles or move 13 zero defaults, and truncates 8 ints | cem_driver.py:130-137; sensitivity_screen.py:124-130 | 1 |
| T12 | no_op is decided on one fixture | sensitivity_screen.py:146 | 1 |
| T14 | Failed evaluations are scored as "no influence" | sensitivity_screen.py:144-146; cem_driver.py:185-188, 201-205 | 0.5 |
| T15 | Rule overrides leak across seats | AIDecisionMaker.gd:2955, 1416-1427 | 0.5 |
| T17 | gate_candidate.py is a v1 gate. Do not use it; Stage C runs on ai_versions.py + decide_v2.py | gate_candidate.py:69, 72-78, 138, 144 | 0 (0.5 to fix) |
| T18 | The screen ranks by the larger abs(E) of 5 noisy pairs | sensitivity_screen.py:144-145, 170-175 | 0.5 |
| T19 | Resolved: the extracted-copy base is exact A/A (facts in 2a) | – | 0 |
| T20 | Out-of-date docs (126 params, now 273; ~48 s/game) | sensitivity_screen.py:4, 94-96; README.md:402-408 | 0.25 |
| T21 | determinism_check.py keys records by seed only, so in an ai_versions season the M1 and M2 records overwrite each other | determinism_check.py:38-49 | 0.25 |
| | **Other total** | | **9.0** |

- Totals (E): probe path 8.0 h · loop-tool hardening 7.75 h · other 9.0 h. The previous "probe 16.75 h" counted T1-T6, T17 and all of T8; the probe path needs none of T1-T6 or T17, only part of T8 (now P3-P5), plus the new P1 and P2. The previous non-blocking rows summed to 8.75 h, not 9.25 h.
- Param reach (function bodies end at the next func header; the earlier scan cut multi-line signatures short): decide() reaches all 273 params (not 175). The RI path reads ~32; 16 of them can change the RI decision, the rest only feed objective `priority`. Epic Challenge reads 2 (MELEE_KEYWORD_MODIFIERS, MELEE_WOUND_OVERFLOW_CAP). The other reactive evaluate_* entry points read 0; suggest_* serve only the human hint. So the non-decide get_param entry points in AI-vs-AI games are RI, Epic Challenge and AIPlayer.gd:1699 / :2788.

## 3. Stages (the probe)

**Gate 0: checks before any tuning game**
- Code: after the V2-2 decision on the V2-4 bundle, SHIP = the AI then shipped. Extract it as the base (`ai_versions.py extract SHIP=<sha>`); HEAD must have the same AIDecisionMaker.gd blob.
- Merge §2a. Offline selftests, 0 games: P2 collision test, P1 lint on the 8 sampled profiles, P5 on synthetic TUNE_RESULTs.
- A/A + plumbing run: SHIP copy vs HEAD + a profile that sets all 8 dims to their default values (exercises the profile path), T13 on, 1 pair per fixture on seeds 38001 / 38101 / 38201: 6 games in 3 jobs. Pass: in every pair M1 == M2 and the M1/M2 trajectory hashes are equal (same container, so no cross-container comparison); every record has the expected canonical hash, rules 11e, difficulty 3 and fixture sha256; the TUNE_RESULTs save and merge. First cus check of this design.

**Stage A: screen (0 games)**
- The offline decision-flip screen already done replaces it: 273 params → 30 shortlisted (E, offline). 86 params cannot act on these fixtures; 30 FIX_, toggle or zero-default params do nothing under ×(1±d).
- A live screen cannot rank (S). With 21 params × 2 directions × 6 pairs (252 pairs), an influential param comes first 14.7-19.4% of the time against 14.3% by chance (3 influential, τ 0.5-1.0, σ 6-10). Its "≥ 2 VP" rule passes 13.8-18.0 of the 21 params by noise alone.
- The draft's cus-only no-op pass is unsafe: cus games never read Ork-relevant params (MOVE_HORDE_BONUS_LARGE: 0 reads in 224 games, M).

**Stage B: one generation, population 8, 8 dims**

| # | Dim | Default | Decisions changed per game at ±30% (E, offline): cus / asy / ork |
|---|---|---|---|
| 1 | MOVE_RACE_LOSS_FACTOR | 0.5 | 13.2 / 9.3 / 18.7 |
| 2 | STRATEGY_EARLY_OBJECTIVE | 0.95 | 6.6 / 12.0 / 8.0 |
| 3 | WEIGHT_VP_PER_POINT | 1.2 | 4.0 (2 games) / not measured / not measured |
| 4 | WEIGHT_ENEMY_WEAK_OBJ | 7 | 3.0 (2 games) / not measured / not measured |
| 5 | MOVE_TURNS_AWAY_FRACTION | 0.2 | 6.2 / 5.7 / 3.3 |
| 6, 7 | THREAT_SHOOTING_PENALTY / THREAT_CHARGE_PENALTY | 0.5 / 2 | whole threat term: 6.6 / 4.3 / 8.3 |
| 8 | STRATEGY_LATE_OBJECTIVE | 1.6 | 3.0 / not measured (0 records reached it) / 10.7 |

- Games behind each cell: 5 cus, 3 asy, 3 ork recorded games (sets_plus.json). Dims 3-4: 2 cus games, plus 2 games of the Ork reserve variant orkRSV (10.5 and 11.5), which is not a bench fixture. The counts measure how much a dim perturbs games (this drives σ), not whether it can gain VP (τ): the shortlist selects for decision traffic, not effect size.
- Kept fixed because they alias a dim: STRATEGY_EARLY_SURVIVAL (dims 6-7 in rounds 1-2) and MOVE_TURNS_AWAY_PENALTY (combined with dim 5 by max()). Dims 2 and 8 scale the whole objective priority (AIDecisionMaker.gd:9728).
- No charge dims: at ±30% the charge-bar params change 0.3-0.8 declarations per game; the decisive values are hard-coded (AIDecisionMaker.gd:17525 charge_threshold = 1.0; :17412 3% skip) (E, offline).
- Sampling (a judgement, not an output of the power analysis): mean = shipped default, sd = 0.3 × default, clipped to default × (1 ± 0.5). Clip rate: 9.6% of draws per dim land on a bound; 55% of candidates have ≥ 1 clipped dim (analytic; sd 0.45 gave 27%). Smaller moves stay nearer the hand-set defaults (less risk of a negative μ) but likely narrow τ; this trade-off is not modelled.
- Race: 8 candidates × 3 fixtures × 2 pairs = 48 pairs (96 games), 24 jobs, common seeds cus 40001-40002, asy 40008-40009, ork 40015-40016.
- Survivors: top 4 by pooled race E (equal fixture weight). Final: 4 × 3 × 4 pairs = 48 pairs (96 games), 12 jobs, new common seeds cus 40031-40034, asy 40051-40054, ork 40071-40074.
- Pick ("rule B"): the survivor with the best pooled E over its 18 pairs.
- Job: `python3 tools/ai_lab/ai_versions.py run --rules11e --difficulty 3 --base SHIP --cand HEAD --cand-profile /tmp/<tag>.json --fixture <f> --season /tmp/season_<tag> --tag <tag> --seed-base <S> --pairs <P> --lanes 4 --max-seconds 1800` (2400 on ork); `<tag>` = `<race|final>_g1_c<k>_<fx>_<hash8>`. The job decodes the profile from base64, prints its canonical hash and returns TUNE_RESULT (P4).

**Stage C: confirmation under V2-2** (registered before its first game)
- Arm: SHIP code with the pick written in as new defaults (the code that would ship) vs the extracted SHIP copy; ai_versions.py --rules11e + decide_v2.py.
- Looks at 124 / 248 / 372 pairs on the registered V2-2 seeds, 14 jobs per look: cus 3 × 14 (bases 95000/95020/95040), asy 6 × 7 (99000/99007/99020/99027/99040/99047), ork 5 × 8 (94000-94080 step 20). Looks 2 and 3 add 100 and 200 to every base. Tuning never uses these seeds.
- Expected size: 199-256 pairs, 1.6-2.1 looks (S; μ 0 to −τ, τ ≤ 1.2).

**Stop / park rules (pre-registered)**
1. A Gate-0 check fails → stop; no tuning game.
2. One generation only. A second needs a Stage C ship and a new proposal.
3. Timeout = a job not done within max(2 × the fixture's median job time, 60 min), or lost to a container restart: re-run the identical spec on a new container. A game that ends other than "completed" (stall guard, crash, error) replays the same way, so it is not re-run: disqualify that candidate. If the same seed fails for every candidate, drop it for all and top up all candidates of that fixture on the next registry seed. More than 2 of 8 candidates disqualified → stop and investigate.
4. A provenance mismatch (git sha, per-seat AI blob, canonical profile hash, rules ≠ 11e, difficulty ≠ 3, fixture sha256) rejects that job: fix the template, re-run.
5. Only Stage C decides. Never quote the merge/tell estimate of the pick (+3.2 to +3.5 VP at μ 0; S) as a gain.
6. Stage C ships if z ≥ 3.710 / 2.512 / 1.993 at looks 1 / 2 / 3 and no fixture 95% CI lies wholly below 0. Futility: stop at look 1 or 2 if pooled E ≤ 0. No crossing by look 3 → no ship.
7. No ship → PARK: keep the profiles and ranking as data, leave defaults unchanged, close V2-6. Ship → new defaults + a version_history.json entry + a windowed scenario (CLAUDE.md); report P(θ ≤ 0 given ship) for the case with it.
8. If the shipped AI changes before Stage C ends, stop.

**Draft track, for comparison only (not proposed).** A1: 21 params × 2 directions × 6 pairs on cus (252 pairs). A2: top 8 × 2 × 4 pairs × 3 fixtures (192 pairs). Then 4 CEM generations × 96 pairs, then V2-2. Cost and odds in §1, §4, §5.

## 4. Cost and time (all E)

| Stage | Sessions | Container-h, mean (P10-P90) | Sibling LLM USD | Wall, median (P10-P90), ≤ 14 containers |
|---|---|---|---|---|
| Engineering (§2a) | – | 8.0 engineering h | not estimated | not included |
| Gate 0: A/A + plumbing, 6 games | 3 | 0.7 (0.6-0.8) | 1.5-2.2 | 22 min (18-28) |
| A: screen | 0 | 0 | 0 | 0 |
| B race, 96 games | 24 | 5.8 (5.4-6.2) | 11.8-17.8 | 32 min (28-51) |
| B final, 96 games | 12 | 5.1 (4.6-5.5) | 5.9-8.9 | 48 min (43-65) |
| C, each V2-2 look, 248 games | 14 | 12.0 (11.2-12.9) | 6.9-10.4 | 91 min (82-114) |
| **Probe, stops at look 1** | 53 | 23.6 (22.5-24.6) | 26.0-39.3 | 3.4 h (3.1-3.9) |
| **Probe, expected (1.6-2.1 looks)** | 61-68 | 31-36 | 30-50 | 4.4-5.1 h |
| **Probe, all 3 looks** | 81 | 47.6 (46.0-49.1) | 39.8-60.0 | 6.6 h (6.1-7.2) |
| Probe with race and final packed per fixture, 1 / 3 looks | 31 / 59 | 22.2 / 46.3 | 15.2-23.0 / 29.0-43.7 | 3.8 / 7.0 h |
| Draft (+T13, + Gate 0), 1 / 3 looks | 251 / 279 | 85.8 / 109.9 | 123-186 / 137-207 | 10.3 / 13.5 h |

- Model (/tmp/ttp_v3/cost.py): each job's games are list-scheduled on 4 lanes; game time = container speed × relative game time. Speeds are calibrated so each of the 41 non-restart V12-round shard sessions is reproduced; relative times come from 121 logged games (seconds / shard mean). Job = 2.77 min setup and tail + makespan, plus restarts at the measured 0.089 per container-h. Short jobs therefore pay for their slowest game: over 9 non-restart shards the slowest of 4 games took 1.06-1.36× (median 1.09) the old model's per-wave time (M).
- Check: for the 11-shard layout actually run, the model gives 12.1 container-h (11.3-13.1) and 103 min (89-120); the 5 real looks took 11.8-12.6 container-h and 91-112 min (M).
- Brackets: P10-P90 of 10,000 Monte Carlo draws. Expected looks from §5's E[Stage C pairs]. Sibling USD = sessions × $0.49-0.74 (measured range, n = 9).
- Parent orchestration, lower bound: ≥ $0.08 per parent API call (cache reads of the parent's current 410,819-token context at $0.2/Mtok, the cost analysis's implied price) × ≥ 3 calls per sibling session in today's routine (save, archive, reply; STATUS.md) → ≥ $0.25 per session, ≥ $13-20 for 53-81 sessions. Output, cache writes, barrier and merge turns and context growth come on top; not estimated.
- Not included: parent lag at the 4-6 barriers, container compute cost, the engineering's LLM cost, the wait for the V2-4 decision.
- Contingencies: re-running one timed-out job costs 0.11-0.69 container-h; a seed lost for all candidates of a fixture costs one packed top-up job (8 candidates × 1 pair): cus 0.3, asy 0.7, ork 1.3 container-h, 18-79 min. Expected ≈ 0: 0 incomplete pairs in the 620 V12-round pairs at the same caps (M).
- Packing (needs P2): all race (or final) candidates of a fixture in 1 (cus), 2 (asy) or 4 (ork) containers, distinct tags and seasons, one 4-lane game pool per container (assumed). Saves 22 sessions ($11-16 sibling, ≥ $5 parent) and ~1.3 container-h; adds ~25 min wall.
- Cross-checks: race and final now cost 0.4 / 0.2 container-h more than the previous wave model. The table exceeds a per-pair estimate because every session pays 2.8 min of setup and tail and short jobs pay for their slowest game (with T13 a 2-pair job fills all 4 lanes). The draft's own estimate (70-90 container-h, 6-9 h) used 3.75 container-min per ork game; the typical ork shard took 5.0 (M).

## 5. Expected outcome (S; 100,000 reps per cell)

Model: 1 generation of 8 candidates; race 6 pairs each; 12 more pairs for the top 4; rule-B pick; then V2-2 (looks 124/248/372, OBF boundaries, futility, fixture veto). σ = 10.26 VP per pair (A: median of the 4 large code arms, measured 9.6-11.3; σ for profile candidates is not measured); fixture SD ratios from those arms; ρ = 0.04 (A); θ_i ~ N(μ, τ²) iid (A). Code: the review's independent re-derivation (/tmp/review_tt/sim_check.py; it reproduces the protocol power 0.159 / 0.492 / 0.778 / 0.882), re-run with a new seed (/tmp/ttp_v3/grid.py).

**5a. μ = 0**

| | τ 0.25 | τ 0.5 | τ 1.0 | τ 1.2 |
|---|---|---|---|---|
| P(ship) | 0.040 | 0.103 | 0.308 | 0.391 |
| **P(ship & θ > 0)** | **0.035** | **0.101** | **0.306** | **0.390** |
| P(ship & θ ≥ 0.5) | 0.006 | 0.074 | 0.292 | 0.379 |
| P(θ ≤ 0 given ship) | 0.13 | 0.03 | 0.005 | 0.003 |
| E[shipped gain], VP | +0.010 | +0.075 | +0.454 | +0.678 |
| E[θ given ship] | +0.26 | +0.72 | +1.47 | +1.73 |
| E[θ of the best of 8] | +0.36 | +0.71 | +1.43 | +1.71 |
| P(true best survives the race) | 0.53 | 0.57 | 0.64 | 0.67 |
| P(pick's θ > 0); random pick = 0.5 | 0.56 | 0.61 | 0.71 | 0.74 |
| Merge/tell estimate of the pick (18 pairs) | +3.21 | +3.26 | +3.49 | +3.61 |
| E[Stage C pairs] | 236 | 245 | 256 | 255 |
| Draft, 4 generations, rule B: P(ship & θ>0) / E[gain] | 0.039 / +0.012 | 0.116 / +0.091 | 0.392 / +0.620 | – |
| One unsearched candidate, V2-2 only: P(ship & θ>0) | 0.030 | 0.069 | 0.170 | – |
| Probe at σ 4.32 (LF-arm noise and ratios): P(ship & θ>0) | 0.131 | 0.385 | 0.725 | – |

**5b. P(ship & θ > 0) / E[shipped gain] by mean μ**

| τ | μ = 0 | μ = −τ/2 | μ = −τ |
|---|---|---|---|
| 0.25 | 0.035 / +0.010 | 0.018 / +0.004 | 0.009 / +0.001 |
| 0.5 | 0.101 / +0.075 | 0.050 / +0.031 | 0.022 / +0.010 |
| 1.0 | 0.306 / +0.454 | 0.169 / +0.216 | 0.081 / +0.088 |
| 1.2 | 0.390 / +0.678 | 0.225 / +0.336 | 0.108 / +0.139 |
| 1.5 | 0.507 / +1.07 | 0.310 / +0.56 | 0.156 / +0.24 |
| 2.0 | 0.647 / +1.77 | 0.432 / +0.99 | 0.236 / +0.46 |
| 3.0 | 0.815 / +3.29 | 0.611 / +1.97 | 0.367 / +0.98 |

**5c. Near-null pools**

| (μ, τ) | P(ship) | P(ship & θ ≤ 0) | P(θ ≤ 0 given ship) | E[θ given ship] |
|---|---|---|---|---|
| 0, 0 | 0.024 | 0.024 | 1.00 | 0 |
| −0.05, 0.05 | 0.019 | 0.015 | 0.77 | −0.04 |
| −0.1, 0.1 | 0.017 | 0.012 | 0.69 | −0.05 |
| 0, 0.05 | 0.025 | 0.010 | 0.41 | +0.01 |
| −0.25, 0.25 | 0.016 | 0.007 | 0.43 | +0.04 |
| 0, 0.25 | 0.040 | 0.005 | 0.13 | +0.26 |

- **What the data say about τ.** The 5 code arms vs V7D vary less than noise: sample variance 0.338 against 0.565 expected at τ = 0 with the measured error covariance (M). P(variance this small) = 0.22 / 0.073 / 0.046 / 0.025 at τ 0.5 / 1.0 / 1.2 / 1.5 (S): τ above ~1.2 VP is excluded at one-sided 5%, τ = 1.0 is not, and the point estimate is 0. The arms are nested hand-designed fixes with correlated true effects, so this bound is optimistic. It says nothing about profile moves, whose μ and τ are unmeasured; large moves of hand-set defaults may well mean a large τ with a negative μ (5b).
- **False ships.** Guarantee: P(ship & θ ≤ 0) ≤ 2.5% per Stage C (V2-2 one-sided α; Stage C seeds are never used for selection). In a near-null pool most ships are false (5c): a ship there is most likely a no-op or a slight loss.
- **A confirmable gain needs a large true effect:** V2-2 alone needs 1.08 VP for a 50% chance and 1.53 VP for 80% at σ 10.26.
- **ρ is an assumption.** 0.04 was measured only between two disjoint fixes (LF vs RI); between overlapping arms the measured correlation of pooled estimates is −0.09 to +0.65. Sensitivity: ρ 0 → 0.6 moves P(ship & θ>0) from 0.100 to 0.114 at τ 0.5 and from 0.302 to 0.377 at τ 1.0.
- **Expected gain vs the trigger.** V2-6's +0.5 VP triggers on one round's realized gain; it is not a bar for an expectation that counts no-ships as 0. The comparable figure is P(ship & θ ≥ 0.5) (5a). A yield-per-container-hour comparison with past critic rounds was not made: their container-hours were not measured.
- **Robustness** (review script re-run): unchanged with empirical heavy-tailed per-pair noise and estimated SEs (0.098 at τ 0.5, 0.308 at τ 1.0). Fixture-heterogeneous effects (0.5-1.0 VP between fixtures) raise P(ship & θ>0) to 0.12-0.21 at τ 0.5, because they widen the pooled spread.
- Model limits: θ iid normal with no link from move size to (μ, τ); σ for profile candidates = code arms; no learning between generations.

## 6. Risks and validity threats

| Threat | Mechanism and size | Mitigation |
|---|---|---|
| Payoff unknown | μ, τ for profile moves unmeasured; P(ship & θ>0) runs from ≤ 0.015 (τ ≤ 0.1) to 0.43-0.65 (τ 2, μ −1 to 0) (S) | Hold; run once at most; only Stage C decides |
| Silent tool error: tag/season collision | Same tag + same season → later candidates report the first one's margins with no error (offline test: 0 games, A's E 0.0 vs true +6.0, M). Triggers: warm workers, resumed seasons, packing | P2 guard + selftest; fresh season per job; merge keys on canonical hash |
| Profile identity | A re-typed profile changes a byte-level sha256 without changing values; a value typo goes unseen | Send base64; compare the canonical hash of the loaded parameters in record provenance |
| Seat attribution: RI, Epic Challenge | With --base HEAD, RI reads the opposing seat's profile; for the 8 dims this changes nothing on these fixtures (T6). Epic Challenge reads the other seat in 10/359 cus decisions (M) and reads 2 untuned params | Extracted SHIP base: no leak (each script has its own statics) |
| Seat attribution: AIPlayer direct calls | AIPlayer.gd:1699/2788 read HEAD's statics for both seats: MOVE_LADDER_FAIL_BUDGET, MOVE_RIGID_BLOCK_FIRST only | P1 rejects both |
| Seat attribution: From Golden Light | Decided by the unit's opponent, 11.9 decisions per cus game (M); reads 0 params | T7 before any FGL fix arm |
| Winner's curse | Merge/tell estimate +3.2 to +3.5 VP vs true +0.03 to +0.53 at μ 0 (S); the true best survives the race 53-64% of the time (S) | Decide only in Stage C, on registered seeds tuning never uses (T16) |
| Near-null false ships | 41-77% of ships are false at τ ≤ 0.1 (S) | ≤ 2.5% per Stage C; report P(θ ≤ 0 given ship) with any ship |
| Fixture coverage | 0 attached leaders, 0 embarked, 0 [HEAVY], 0 ANTI-, no Scouts; 86 of 273 params inert; RI only on cus; bench Orks = Kult of Speed (M) | A ship is tuned for 3 matchups only; say so in the version entry |
| Rules / policy mismatch | The loop tools play legacy Take and Hold + 10e deck at difficulty 2 (M) | Probe uses ai_versions.py --rules11e --difficulty 3; the merge rejects other values |
| Selection by game length | Slowest ork game 2122 s vs the 2400 s cap (M); 0 incomplete pairs in 620 at 1800/2400 s (M) | Caps 1800/2400; stalls disqualify the candidate (rule 3) |
| Code drift | The V2-4 bundle (13 clear fixes) is heading for its own V2-2 bench | Gate 0: tune the code that ships; rule 8 |
| Cost overrun | Container speed differs 1.7-1.8× between shards; 5 of 46 sessions restarted (+5-31 min), clustered (M) | Timeout rule; P90 column; contingencies (§4) |

## 7. What would change the recommendation

- **The V2-4 decision.** A precondition either way: tune the code that ships.
- **Evidence on τ for profile moves.** The probe is the cheapest direct test, but only a ship is informative. A V2-2 arm with pooled E well above +1.17 VP, or a between-arm spread larger than noise, would raise the odds.
- **Lower noise with large effects.** At σ 4.32 the probe's odds are 0.13 / 0.39 / 0.73 at τ 0.25 / 0.5 / 1.0 (S). So far only small changes had low noise (LF: 45-81% of pairs identical, M).
- **More budget helps little.** 4 generations (the draft's CEM part) reach 0.12 at τ 0.5 (S).
- **New bench fixtures** (V2-5 reserve fixtures; an Orks_2000 or Space Wolves mirror). Re-run the 0-game flip screen first; this changes the dims, not the noise argument.
- **Tool value on its own.** P2 (1.5 h) and P4 (1.5 h) are worth doing for any profile arm; T7 (2.5 h) before any From Golden Light fix arm.

## Sources

- This revision (read-only scratch files in this container): /tmp/ttp_v3/ — grid.py → grid.txt / grid.json (§1, §5); spread_fine.py (τ bound); cost.py → cost.txt / cost.json (§4); quiet_pairs.py (A/A pairs); epic_seat.py (349/359); allarus.py (RI unit); sim_robust_rerun.txt.
- Review scripts re-run: /tmp/review_tt/ (sim_check.py, sim_robust.py, spread.py, sim_aiv_collision.py, reach_params.py, ri_units.py, rec_check.py, fgl_check.py, g_vs_max4.py, xcontainer.py).
- Earlier analyses: /tmp/tt_analysis/ (tools, seat validity), /tmp/param_analyst/ (flip2_plus_30.txt, objweights_30.txt, sets_plus.json), /tmp/tuning_power/ (sim_design_100k.txt), /tmp/costmodel/ (sessions, per-game times), /tmp/proposal_calc/ (previous stage totals, superseded by /tmp/ttp_v3/cost.py).
- Corrections to /home/user/warhammer-40k-godot/.ai_lab_work/tuning_track_draft.md still stand: tool work is ~8 h on the probe path, not ~1 h; ork costs 5.0 container-min per game, not 3.75; a look costs ~12 container-h and ~1.5 h; a cus-only screen is unsafe; "small steps raise power per pair" is not supported; "0 reserves" is wrong for cus; the draft missed T1, T4, T6, T9, T13 and the ai_versions collision.

## Review notes

All major and minor points of both reviews were applied, with the exceptions and corrections below.

| Point | Outcome |
|---|---|
| τ, μ presented as established (major) | Applied: §1 and §5 are conditional; (μ, τ) grid (5b); the 5-arm bound is tagged (S), ~1.2 VP (finer grid: 0.052 at τ 1.15, 0.046 at 1.2); "do not run" became "hold", stated as a judgement |
| sd 0.45 from the power analysis | Applied: sd 0.3 × default as a judgement; clip rate reported. The linear-minus-quadratic move model was not built |
| Inconsistent §5 table | Applied: one set (rule B, σ 10.26, P(ship & θ>0)), re-run with a new seed. The draft row is now rule B too: it adds +0.004 / +0.015 / +0.086 (the review's +0.001 / +0.012 / +0.067 mixed rule A and B) |
| False ships ≤ 0.5% | Applied: ≤ 2.5% per Stage C; table 5c |
| ρ "measured" | Applied, corrected: between overlapping arms the measured correlation is −0.09 to +0.65, not 0.26-0.65 (the review's range left out LF-V11, RI-V11 and V11-V12W) |
| Expected gain vs the +0.5 trigger | Applied: P(ship & θ ≥ 0.5) reported. Not done: VP per container-hour vs critic rounds, because their container-hours were never measured |
| Dims table game counts | Applied |
| Probe hours 16.75 | Applied: probe path 8.0 h (E); the review's ≤ 14.0 h bound holds if T8 is built in full |
| Tag/season collision (major) | Applied: P2; job line fixed; fake-godot test re-run with the same result |
| T6 blocking (major) | Applied: non-blocking; the before/after-T6 Gate-0 run is dropped. Fixture decode re-checked: Allarus 275 pts, 5 models, melee + ranged (floor ≥ 7.0) |
| T19 / extracted-copy base (major) | Applied: it is the default job; quiet-pair counts re-derived (18/18, 16/16, 3/3); the direct-call leak is listed |
| Reach count | Applied: ~32 read, 16 decision-relevant; decide 273; Epic Challenge wording fixed (349/359 re-derived) |
| T3 list | Applied |
| Hour sums | Applied |
| Cost model | Applied: per-game list-scheduling model (reproduces the as-run looks); Gate 0 with T13 is 0.7 container-h, lower than the review's 1.3 because Gate 0 is now 3 jobs, not 6; ratio 3.6× / 2.3× |
| Gate-0 determinism_check | Applied: within-container A/A with an all-default 8-dim profile; T21 added |
| Stop rule 3 | Applied; top-ups costed |
| Byte-level sha256 | Applied: canonical hash + base64 |
| Seed ranges | Applied: Gate 0 38001/38101/38201; asy 6 × 7 bases stated |
| Parent tokens, packing | Partly: only a lower bound (≥ $0.25 per session); the parent's real cost per sibling session was not measured. Packing costed as an option |
| T9 wording | Applied |
| V2-6 deviation | Applied (§1) |

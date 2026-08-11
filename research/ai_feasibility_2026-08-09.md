# Is a challenging 40k AI feasible? A hyper-critical assessment

Date: 2026-08-09. Commissioned question: *botbowl's bots reportedly still lost
to random play after years of effort — is what we are attempting even
feasible, are we doing the right thing, and is it worth continuing?*

Method: two agents deep-read this repo's AI engine and its measurement-lab
evidence; six agents researched the outside world (the botbowl post-mortem,
search-based wargame AI, commercial practice, LLMs in game AI, RL
feasibility, and difficulty-perception research). ~280 sources were consulted;
every claim below is tagged where it matters as **measured** (this repo's
lab), **verified** (primary source fetched), **reported** (secondary source),
or **inference**. This document is the synthesis. It contains no new
measurements of its own.

---

## The verdict in four sentences

1. **"An AI that beats experienced humans on even points through decision
   quality" has no precedent anywhere** — not in any commercial wargame, not
   in academia, not in Blood Bowl after five years of open competition — and
   this project should explicitly stop treating it as the implicit goal.
2. **"An AI that is challenging for you and for hobbyist players, without
   cheating on dice" is feasible**, and the evidence says it is reached
   through three things this project has barely started: eliminating visible
   blunders, authoring the strategy layer (deployment templates, per-mission
   game plans, personas), and transparent difficulty handicaps — not through
   search, learning, or more parameter tuning.
3. **Your fear is miscalibrated in a useful way**: botbowl's failure modes
   (turnover + reward so sparse that 350,000 random games produced *zero*
   touchdowns) are structural properties of Blood Bowl that 40k does not
   have — but botbowl's *positive* lesson (scripted domain knowledge won 4 of
   5 competitions; parameter-evolving a mature heuristic added nothing) is
   already replicated in this repo's own lab results.
4. **Worth continuing: yes, with a redirect.** Kill the expensive tail of the
   current plan (large-scale parameter search, engine-rollout lookahead,
   any RL). Fund the cheap, high-information items: human games (there are
   currently **zero**), a blunder-rate metric, movement candidate
   enumeration, authored plans, and an honest difficulty menu.

---

## 1. What actually happened with botbowl — and what it does and does not prove

The user's memory ("their AIs were still losing at times to random choices")
is close but not literal, and the correction matters.

**The record (verified from official competition pages and papers):**

| Year | Winner | Approach | ML/RL entrants |
|---|---|---|---|
| Bot Bowl I (2019) | GrodBot 34/5/1 | scripted | A2C went 0/17/23 vs Random's 0/15/25 — level with random |
| Bot Bowl II (2020) | Minigrod 47/10/3 | scripted | Giaobot (IMPALA+LSTM) 0/20/40 — **below** Random (0/23/37); MCTS entrant Sapling 1/20/39 |
| Bot Bowl III (2021) | MimicBot | **imitation of the scripted bot** + RL fine-tune + scripted guardrails | the only ML win ever; beat a "novice-level" scripted bot 62.7% |
| Bot Bowl IV (2022) | Drefsante | scripted (one hobbyist) | Random collected 7 draws, incl. one vs the winner (reported) |
| Bot Bowl V (2023) | Drefsante | scripted | last competition ever held; repo dormant since 2023-08-25 |

No bot ever *lost* a game to random — random scored zero touchdowns in every
table found. What happened is that RL entrants finished at or below random in
the standings, and even winners conceded draws to random, because Blood
Bowl's scoring is so sparse that a 0-0 draw is the default outcome of any
game where the stronger side fails a dice chain. Two structural facts drove
everything:

- **Turnover**: one failed roll ends your whole turn. Risk sequencing under
  catastrophic single-roll failure is *the* core skill, returns are wildly
  high-variance, and a greedy bot's mistakes compound.
- **Zero-reward sparsity**: in 350,000 random-vs-random games, zero
  touchdowns were scored (verified, Justesen et al. 2019). Vanilla RL had no
  gradient to climb; 100M A2C training steps on the full board produced
  ~0.02 TD/game, and with curriculum tricks the same budget bought only
  "80% wins vs random."

**Neither property exists in 40k.** There is no turn-loss mechanic; dice
aggregate over dozens of attacks so expected-value math is reliable; and
primary VP is scored every battle round for standing on objectives, so the
reward signal is dense — this repo's lab measures a smooth VP margin in every
single game. The nightmare "draws with random" pathology cannot structurally
recur here. (Action item anyway: add a random-policy agent and a
"sit-on-objectives-never-shoot" agent as permanent floor baselines in the
lab. If the AI ever fails to crush both by huge margins, that is the Blood
Bowl red flag.)

**What botbowl does prove, twice over in this repo's own data:**

- *Scripted domain knowledge is the frontier at hobby compute.* 4 of 5 titles
  went to scripted bots; the one ML winner had to be taught by the scripted
  bot and wrapped in scripted guardrails.
- *Parameter-tuning a mature heuristic yields ~nothing.* EvoGrod (GrodBot
  with 16 evolved parameters) lost the Bot Bowl I final to hand-tuned GrodBot
  0-3. This repo's CEM campaign over 264 games found +2.25 ± 3.2 VP —
  the same null, independently replicated.
- *Nobody ever measured against humans*, because after five years the bots
  were plausibly still below a decent club player (GrodBot ≈ "slightly above
  rookie"). The competition died chasing "beat the best humans."

Botbowl is not evidence this project is infeasible. It is strong evidence
about **which paths are dead** — and the paths it kills (parameter search,
pure RL, naive MCTS) are exactly the ones this project's own lab has already
measured at zero or has not yet funded.

---

## 2. What this repo's own evidence says (the part most reports would soften)

The lab is genuinely excellent — seed-paired side-swapped evaluation,
pre-registered stopping rules, per-decision records, null-test-verified
instruments. Better measurement discipline than Bot Bowl ever had (winners
there called their own 10-game pairings meaningless). And its output so far
is a brutally consistent ledger (all **measured**):

| Change | E (VP/game) | Verdict |
|---|---|---|
| 6 YouTube-mined tactics findings (from 1,029 transcripts) | −2.05, CI [−7.2, +3.1] | zero; shipped OFF |
| Scoring-horizon fix | −4.29, CI [−7.43, −1.15] | the only result to ever clear the significance bar — **negative** |
| CEM parameter search, 264 games, 6 params | +2.25 ± 3.2 | nothing shippable |
| Melee wound-overflow fix (1.6–3.0× error!) | −0.74 ± 0.75 pooled | neutral |
| Melee keyword fix (ANTI-X, etc.) | +0.00 ± 0.00 on Orks | **provable no-op — every paired seed identical** |
| Reserves-cap change | 12 → 39 primary VP | the one big win — but **2 games, "directional, not statistical"** |

Plus the sensitivity screen: every charge, fight, and shooting coefficient
tested changed **zero decisions** at ±30%; the only parameters that move the
margin at all are macro movement/objective terms.

Read plainly: **five independent, plausible micro-tactical improvements
measured at or below zero on a verified instrument, while the only effects
found anywhere live in the strategic layer** (reserves, objective
assignment weights, deployment — the last being the phase the AI's own
source calls decisive, which had *zero* benchmark games behind it until
2026-08-08 and costs 3–4× more games to measure because self-deployment
doubles outcome variance).

Three uncomfortable findings from the code deep-read sharpen this:

1. **The movement pathology is architectural, not a tuning problem.** ~50% of
   movement decisions choose destinations both farther and lower-scoring than
   an available alternative — because `_compute_movement_toward_target`
   constructs *one* destination per unit (straight vector + local repair) and
   never enumerates or compares alternatives (verified,
   `AIDecisionMaker.gd:10298-10500`). The candidate-count difficulty knob
   (`get_movement_iterations`) is dead config that nothing calls. No amount
   of weight tuning can fix choosing among candidates that were never
   generated.
2. **The shipped default difficulty has planning disabled.** NORMAL — what
   players actually face — never builds the multi-phase plan at all: no
   charge intents, no lock targets, no shooting lanes (verified,
   `AIDecisionMaker.gd:2342-2344`). Six of thirteen advertised difficulty
   capabilities are dead config, including the marketing string
   "Competitive: Full look-ahead planning", which describes code that does
   not exist. Months of AI improvement work have been benchmarked on HARD
   while players meet a deliberately lobotomized NORMAL.
3. **There is zero data on the only question that matters.** No human-vs-AI
   game has ever been recorded, no difficulty-usage stats, no player
   feedback on strength. Whether the current AI beats, challenges, or amuses
   a competent human is completely unmeasured. The entire 4,000–8,000-game
   remaining plan (≈1–3 weeks of continuous 4-core compute) contains no
   task that answers it.

---

## 3. The comparables: nobody has done what you're implicitly attempting

The commercial sweep found **no symmetric, full-ruleset wargame AI that
reliably challenges experienced players on decision quality alone** —
anywhere, at any budget:

- **Every official 40k digital game** that is challenging gets there with
  numbers, not brains: Battlesector's hardest mode is ~+⅓ HP / +15 accuracy
  with the player capped at 80% points; Gladius's developer confirmed all
  difficulty is an economy multiplier and called it *"a necessary evil to
  create a challenging experience"* (verified); Mechanicus/Chaos Gate use
  stat sliders; Necromunda: Underhive Wars' AI helped sink the game.
- **Cyanide shipped three generations of commercial Blood Bowl** with the
  license and a AAA budget; the AI is the perennial weak point of all three
  ("simply pathetic", Hard playing worse than Normal, BB3 picking Skull
  results over strictly better dice).
- **The genre-best symmetric case, Field of Glory II** — a direct port of a
  tabletop miniatures ruleset — earns "surprisingly competent" reviews, and
  experienced players still say *"the AI will oblige by attacking into
  whatever well laid trap you set"*; its top difficulty is +25% troops.
- **The most respected hardcore wargame, Combat Mission, has no autonomous
  operational AI at all**: for ~20 years scenarios have shipped with
  human-authored, zone-painted, triggered AI *plans*, plus a reactive
  tactical layer. That is literally the user's "pre-described game plans"
  proposal, deployed as the flagship technique of the most demanding
  wargame series in existence.
- **XCOM — the genre's most celebrated tactics AI — is architecturally the
  same single-ply utility scorer as this repo's AIDecisionMaker**, inside an
  asymmetric game whose difficulty comes from encounter design, stat
  scaling — and secretly fudging dice *in the player's favor*.
- The only genuinely strong no-cheat board-game AIs found (Race for the
  Galaxy's self-play neural net, Through the Ages) live in games with tiny
  discrete action spaces that simulate in milliseconds. Neither property
  holds here.

The industry norm on the user's red line is also worth stating: **commercial
games essentially never fudge dice against the player** (several fudge them
*for* the player). Difficulty is bought with points, stats, resources, and
authored scenarios — all of which are open to this project. The no-dice-
cheating constraint costs nothing.

One perception finding reframes the whole goal. Players judge an AI by its
**worst visible blunder and its legibility, not its average strength**
(Halo's playtest datum: giving the AI more health — no behavior change —
made players rate it *smarter*; AoE2's no-cheat Extreme AI is community-
estimated at only ~800–1000 Elo yet reads as a serious opponent because the
overhaul removed idiocy, not because it added search). Corollary from Sid
Meier's GDC keynote: honest dice will periodically be *perceived* as
cheating — keep the roll log prominent, because transparency is the only
defense.

---

## 4. Verdict on each candidate approach

**Dead — do not fund (evidence is arithmetic, not taste):**

- **Engine-rollout search (MCTS/RHEA).** At ~115 ms/action, one 300-action
  rollout costs ~35 s; matching even botbowl's *failing* MCTS configuration
  (361 iterations in 5 s, 10% wins vs random) needs a ~2,000× faster
  simulator. There is no `(state, action) → state'` kernel — phases are
  Godot Nodes over a live singleton with dozens of wired signals; building a
  second abstract simulator is a multi-month project with permanent desync
  risk, undertaken on a genre precedent of non-superiority.
- **Self-play / deep RL.** This machine produces ~530–5,400 games/day
  saturated. AlphaGo Zero's 4.9M games = 2.5–25 *years* here; the Blood Bowl
  curriculum-A2C budget (~133k games) = 25–250 days of total saturation, and
  its prize in an easier game was "80% vs random" — a bar the current
  heuristic clears by construction. There is also a second wall: with margin
  sd 11–20 VP, *evaluating one checkpoint* to ±3 VP costs 2 hours–2 days.
  Offline RL and world models have no precedent at 10²–10³ games. Behavior
  cloning from humans is dead for lack of data.
- **Large-scale parameter search (E1 as designed: 1,500–3,500 games).**
  Double null already: this lab's CEM, and Bot Bowl's EvoGrod. The screen
  says the searchable surface is dominated by a handful of macro weights;
  tune those few by hand with paired A/Bs, and spend the rest of the games
  budget elsewhere.
- **Per-action or per-turn LLM play.** ~800 actions/game ≈ $2–4 and +15–40
  min of API latency per game on the cheapest capable model; breaks the
  seed-paired lab; and the best measured LLM-strategist result in the
  literature is *statistical parity with hand-written behavior trees* (46.4%
  vs 51.5%), with LLMs demonstrably weakest at exactly the spatial/legality/
  arithmetic skills this game's action layer needs (chess illegal moves,
  BALROG, Pokémon-with-scaffolding, all major LLMs losing at poker).

**Marginal — cheap enough to try, expect small effects:**

- **C1 value function, dark** (as already specified, with its Spearman ≥ 0.5
  gate and kill-at-0.35). Its realistic learned upgrade is fitting the
  ~10–50 term *weights* (linear/small GBDT — never a deep net) on 500–2,000
  archived games; KnightCap is the precedent (1650→2150 Elo from 308 games —
  but with a fast search consumer this project lacks). Do it because search
  needs *some* leaf evaluator and it's days of compute, not because the
  evidence says learning is where wins live.
- **Shallow closed-form expectimax on small discrete sub-decisions** —
  charge declarations (2D6 tail risk vs overwatch cost), fight sequencing,
  finishing wounded targets. 40k's dice are analytically tractable
  (binomial chains, 2D6), so no sampling and no cheating is needed. This is
  blunder removal wearing a search costume; scope it that way.
- **Script-space ("Puppet") search over 2–3 plan-level choice points**
  (commit-vs-screen, which flank, reserves timing). The only search family
  with literature support at scale — but every published win is on
  millisecond-forward-model toys. Research bet, gated by the lab,
  expectation: null.

**Alive — this is where the evidence actually points:**

1. **Blunder elimination as the primary metric.** Build a blunder-rate
   harness over the existing per-decision Parquet records: dominated
   destination chosen, unit idled, objective left uncontested at scoring,
   hopeless charge declared (the 1-in-36 exam case), wounded high-value
   target ignored, screen moved before the unit it screens. Hundreds of
   samples per game instead of one VP number with sd 11–20 — this escapes
   the statistical trap that killed every tactical A/B, and it measures the
   thing humans actually perceive. Drive each class toward zero.
2. **Movement candidate enumeration.** The single clearest architectural
   fix: generate K candidate destinations per unit (the assigned target,
   plus cover/objective/range-band alternatives) and score them with the
   *existing* evaluators. There is 8–40× compute headroom per decision at
   human-game pacing (1–5 s vs 115 ms). This directly attacks the measured
   50%-dominated-moves pathology, which no parameter can reach because the
   alternatives are never constructed.
3. **Authored strategy: deployment templates and per-mission game plans.**
   The user's instinct, validated from four independent directions: (a) the
   repo's only large measured effect was a strategic pre-decision; (b)
   deployment is described as deciding rounds 1–2 and is currently a
   deterministic column formula that doesn't even choose deployment *order*;
   (c) chess opening books and StarCraft build orders exist precisely
   because search is weakest where branching is highest and evaluation
   shallowest — the opening; (d) Combat Mission has shipped exactly this for
   20 years, and paper automas (Five Parsecs' seven persona codes, OPR solo
   rules, Scythe/Root automas) prove a *designed* opponent with
   condition-ordered priority lists pressures humans on zero compute.
   Concretely: a data-driven library of deployment templates (per mission ×
   deployment map × army archetype) and 3–5 legible personas ("Ork tide
   rushes mid and trades", "Custodes castle and counter-punch") that
   earmark units to objectives, set reserves policy, and pick secondaries
   stance — slotting into the existing phase-plan dictionaries and rule DSL,
   A/B tested on the pre-deploy fixtures.
4. **LLMs offline only — as proposal generators into the DSL, gated by the
   lab.** This is the one LLM integration with real literature support
   (Eureka / FunSearch / AlphaEvolve: "LLM proposes, rigorous evaluator
   disposes" — and this project already owns the rare asset, the rigorous
   evaluator). Aim proposals exclusively at the discrete-strategic class
   where the one big win lives: deployment doctrines, reserves policies,
   objective-assignment rules, persona definitions — not weight nudges or
   damage math, which are measured no-ops. Budget for mostly nulls (the
   YouTube experiment at −2.05 VP is the honest prior); use racing (kill
   candidates at 30–60 paired games); keep the LLM out of the runtime so
   determinism and shippability survive. The already-designed E2 (LLM
   analyst, ≤5 hypotheses/cycle, 3-cycle kill criterion) is the right shape.
5. **A transparent difficulty menu, no dice fudging.** Points asymmetry (AI
   fields 2,100/2,200/2,300 vs your 2,000 — tabletop players literally do
   this), curated stronger AI lists, first-turn choice, and full list-reading
   (open information in tournament 40k anyway). All community-legitimate per
   both tabletop norms and Gladius/Battlesector/FoG2 precedent; effect sizes
   (a whole extra unit) will actually clear the lab's ±3–4 VP detection
   floor, unlike decision-quality tweaks. Per the Halo finding, the extra
   durability will itself read as intelligence.

---

## 5. Are we doing the right thing? An honest audit of the current plan

**What is right:** the measurement lab (paired seeds, null tests,
pre-registration) is the project's crown jewel and the precondition for
everything above — most hobby AI efforts die of unmeasured plausible ideas,
and this one provably does not. The instrumentation work (decision records,
reachability 78%→42%, determinism) was the correct foundation. The plan
documents are unusually honest (kill criteria, premises disproved by
measurement and said so).

**What is wrong:**

- **The plan optimizes a metric the goal doesn't live in.** The goal is a
  human's experience; the lab measures AI-vs-AI VP margin on one matchup
  (Custodes vs Orks — every number ever produced). VP-invisible changes
  (blunders) are perception-critical, and perception-invisible changes can
  move VP. Nothing in the plan measures a human, ever.
- **The expensive tail points at the measured-dead layers.** E1
  (1,500–3,500 games of parameter search) re-runs a double-null experiment
  at 10× budget. D3/D4 lookahead scores opponent replies through damage
  math that two corrections have proven the AI barely acts on — the plan's
  own journal says "the tactical half of the plan may be pulling on a rope
  that is not attached" and prescribes the cheap degraded-arm test first;
  that test should be a hard gate.
- **The decisive layer is at the end of the dependency chain.** Deployment
  and game plans (C2b/C5) sit behind C1→C2→C2b, ~450 games of gates —
  while deployment templates as *data* need no value function at all.
- **The shipped product contradicts the work.** Players face NORMAL, which
  silently disables the planning layer the project spends its effort
  improving.

---

## 6. Recommended plan

**Immediately (days, near-zero games):**

1. **Play 3–5 recorded human-vs-AI games** (owner vs HARD, honest dice,
   decision records on). Note every moment the AI looks stupid and every
   moment it pressures you. This is the cheapest, highest-information
   experiment available and the entire project currently has zero data
   points on it. It also calibrates everything below.
2. **Fix the difficulty config honestly**: NORMAL gets the phase plan (or
   the difficulty labels get renamed); delete or implement the six dead
   capability gates; kill the fictional "full look-ahead" string.
3. **Add floor baselines to the lab** (random agent, objective-camper
   agent) as permanent regression anchors.

**Short term (1–2 weeks):**

4. **Blunder-rate harness** over the existing decision records; publish the
   per-class rates; drive the worst classes to zero. Treat blunder-rate as
   the primary KPI from now on, with VP A/Bs as the guardrail that changes
   don't *lose* games.
5. **Movement candidate enumeration** (K scored destinations through
   existing evaluators, using the 8–40× per-decision headroom), gated by
   blunder-rate improvement + VP non-regression.
6. **Deployment templates v1 as data** for the shipped missions/maps/armies
   (hand-authored; LLM-drafted is fine), replacing the column formula,
   A/B on the pre-deploy fixtures. Include deployment *order* and a
   robust-to-going-second rule.

**Medium term (a month, selective):**

7. **Personas / game plans v1**: 3–5 authored plans binding objective
   earmarks, reserves policy, aggression, and secondaries stance; selected
   per mission+matchup at game start; expressed in the existing rule DSL.
8. **E2-style LLM proposal loop** pointed only at the strategic-discrete
   class, with racing and the 3-cycle kill criterion.
9. **C1 dark + fitted weights**; shallow expectimax on charges/fights if
   the blunder audit shows those classes still firing.
10. **Difficulty menu** built on points/list/first-turn handicaps, labeled
    honestly, dice log kept prominent.

**Kill (write it down so it stays killed):** E1 at design budget;
engine-rollout MCTS/RHEA; any self-play RL, world model, or offline-RL
track; per-action/per-turn LLM play; further micro damage-math tuning as a
strength lever (keep the oracle as a correctness ratchet only).

**Stop conditions (so this doesn't become sunk-cost either):** if after the
human games + blunder fixes + deployment templates + one persona cycle the
AI still cannot pressure its owner at 2,000 vs 2,000 on honest dice — and a
+200-point handicap still doesn't make games tense — then decision-quality
investment has hit its ceiling; ship the handicap menu as the difficulty
story and stop funding AI strength work. That is a legitimate, precedented
outcome: it is exactly where the entire commercial genre landed.

---

## 7. Direct answers

**Why did botbowl "fail"?** Sparse reward (zero TDs in 350k random games) +
turnover-driven variance + a huge uneven action space killed learning;
MCTS died on branching even with a simulator ~1000× faster than ours;
scripted bots won 4/5 competitions and the field stopped in 2023 without
approaching human-competitive play. The "losing to random" memory is really
"RL entrants ranked at/below random, and winners drew against it" — an
artifact of Blood Bowl's scoring structure that 40k's dense per-round VP
makes impossible.

**Is something better feasible here?** For the actual goal — challenging,
non-cheating, fun to lose to for a hobbyist — yes, and the ingredients are
mostly already in the repo. For "beats experienced humans on even terms" —
no one on earth has shipped it in this genre; do not aim there.

**Are we doing the right thing?** The lab: emphatically yes. The plan's
allocation: no — it spends its biggest budgets on the two layers (parameter
space, tactical lookahead) that both this lab and the entire external record
say don't carry the effect, while the decisive layers (deployment, authored
strategy, blunders, the human experience) are underfunded, gated behind long
dependency chains, or entirely unmeasured.

**Are the user's two "thumb on the scales" ideas good?** Yes — they are not
hacks, they are the genre's core technique. Pre-authored deployment is
Combat Mission's 20-year flagship method and chess's opening book;
per-mission/army game plans with earmarked units are exactly how every
respected paper automa works. Both slot into existing plan-dictionary
architecture with low refactor cost, and both attack the layer where this
repo's only large measured effect lives.

**Is "not worth pursuing" the answer?** No. "Not worth pursuing *via
search, RL, or more parameter tuning*" is strongly supported. The redirect
above is cheap relative to what has already been built, and the first item
on it costs one evening and a dice tray.

---

## Appendix: source highlights

- Justesen et al., *Blood Bowl: A New Board Game Challenge and Competition
  for AI* (IEEE CoG 2019) — branching 10^30–10^51; 350k games, zero TDs;
  "tree search possible, but not very feasible."
- Bot Bowl I–V official results (njustesen.github.io/botbowl) — scripted
  4/5; RL at/below random; competition dormant since 2023.
- Pezzotti, *MimicBot* (arXiv:2108.09478) — the one ML win: imitation of
  the scripted bot + guardrails; 62.7% vs a "novice-level" scripted bot.
- Botbowl MCTS tutorial — 361 iterations/5 s ⇒ 10% wins vs random on the
  full board.
- Gladius developer, Steam (fetched) — all difficulty = economy bonus;
  "a necessary evil to create a challenging experience."
- Soren Johnson, *Game AI & Our Cheatin' Hearts* — "cheating is not the
  same thing as difficulty levels"; transparency doctrine.
- Butcher & Griesemer, *The Illusion of Intelligence* (Halo, GDC 2002) —
  more health ⇒ perceived smarter.
- Combat Mission scenario AI-plan tutorials — authored per-scenario plans
  as the shipped architecture for 20 years.
- Puppet Search (TCIAIG 2017); Ontañón CMAB/NaiveMCTS (JAIR 2017); Yang &
  Ontañón survey (IEEE ToG 2021) — script-space search literature; wins
  only on millisecond-forward-model toys.
- Tesauro, TD-Gammon; Baxter et al., KnightCap (arXiv cs/9901002) — strong
  eval + shallow search pattern; linear eval learned from 308 games.
- Eureka (ICLR 2024), FunSearch (Nature 2024), AlphaEvolve (2025) — "LLM
  proposes, evaluator disposes," all resting on cheap evaluators;
  arXiv:2501.11411 — most LLM-evolved heuristics don't generalize.
- BALROG (ICLR 2025); GTO Wizard 2026 poker benchmark; arXiv 2606.20014 —
  LLM strategist ≈ behavior trees (46.4% vs 51.5%).
- In-repo: `.llm/ai-overhaul-todo.md`, `.llm/ai-overhaul-progress.md`,
  `research/ai_improvement_status_2026-08-07.md`,
  `40k/tests/bench_baselines/*.md`, `AIDecisionMaker.gd` (cites in §2).

Full per-agent research narratives (8 documents, ~280 sources) were
generated during this analysis; this file is the synthesis.

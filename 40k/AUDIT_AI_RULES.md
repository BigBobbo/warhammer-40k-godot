# AI Rules Audit — where the AI still has nonexistent or poor decision rules

**Date:** 2026-07-25
**Trigger:** The model-removal upgrade (CasualtyPreference, PR #768) replaced a
"lowest-index model dies first" default with real scoring. This audit sweeps the
rest of the codebase for the same class of problem: places where the AI (or an
"auto/computer" path acting for a player) decides by array order, hardcoded
default, blind auto-accept/decline, or does not decide at all.

**Method:** Static audit of `AIDecisionMaker.gd` (~21k lines), `AIPlayer.gd`,
all `phases/*.gd`, `RulesEngine.gd`, `TransportManager.gd`, `StratagemManager.gd`,
`MissionManager.gd`, `SecondaryMissionManager.gd`, `Allocation.gd`,
`CasualtyPreference.gd`, dialogs and overlays, cross-checked against live army
JSON data. Line numbers are from branch `claude/ai-rules-audit-model-removal-solb5d`
(post-#768 main). Findings are code-read + spot-verified; none were reproduced in
a live game session.

---

## What is already solved (don't re-do)

`scripts/rules/CasualtyPreference.gd` is correctly wired into:

- `AllocationGroupOverlay.gd:684` — 11e overlay auto mode (AI defender or "Computer allocates wounds")
- `WoundAllocationOverlay.gd:1635` — legacy 10e auto pick
- `RulesEngine.gd:4504` — shooting engine auto-resolve (`engine_auto_preference`)
- `RulesEngine.gd:12270` — melee engine auto-resolve

Also verified clean: armor-vs-invuln best-save math, FNP handling, first-turn
roll-off, all optional-response dialogs are AI-gated with matching AI handlers
(no timeout auto-picks), and AI pile-in/consolidate submit explicit per-model
movements (no engine auto-pathing fallback).

---

> **Status update (2026-07-25, v0.94.1):** All Tier 0 items (0.1–0.10, plus four
> extra dice-parse sites found at :18888/:19199/:20973/:20979 and the same
> max-wounds bug in the charge scorer) and Tier 1 items 1 + 7 are FIXED on this
> branch. Validated live: MCP-driven unit checks plus 3 windowed AI scenarios
> (memops_ai_vs_ai_bounded, ai_casualty_preference, ai_coordinated_movement) all
> pass. Everything else below remains open.

## Tier 0 — Bugs that silently disable AI intelligence that already exists

These are not "missing features" — they are one-line bugs that make heuristics the
codebase already contains evaluate to constants. Highest value-per-line in the audit.

| # | Bug | Where | Effect |
|---|-----|-------|--------|
| 0.1 | Dice-notation Attacks/Damage (`"D6"`, `"D3"`, `"D6+2"`) fail `is_valid_float()` and collapse to **1.0** | `AIDecisionMaker.gd:8881, 12031, 12480, 12506, 13729, 13746, 15149, 15166, 18661, 18687` | Every anti-tank gun / power fist undervalued 2–3.5×; wrong weapon and target picks everywhere. Fix: use the existing `_parse_average_damage()` (:19004), already used correctly at :12222/:12258/:20543. Army data has 36× `"attacks":"D6"`, 49× `"damage":"D6"`, plus D3/3D6/D6+N |
| 0.2 | Weapon damage multiplied by **whole unit model count**, ignoring carriers | `AIDecisionMaker.gd:12556` (shooting), `:13764`, `:15181` (melee) | A Nob's single Power snappa scored as 10 models' worth; mixed squads (9× Choppa + 1× klaw, 5 rokkits in 6 Tankbustas) massively mis-scored. Fix: count carriers via `RulesEngine.get_unit_weapons()` |
| 0.3 | `stats.get("oc", …)` — key doesn't exist; data uses `"objective_control"` | `AIDecisionMaker.gd:3004, 6547, 12320, 16961` | Embark scoring, disembark scoring (its highest-weight term), target value, and NML assessment all treat every unit as OC-1 |
| 0.4 | Heavy-bonus charge-intent guard reads `meta.id` — id lives at unit top level | `AIDecisionMaker.gd:8946-8949` | Guard never fires; also the whole Heavy hold check is only reachable from the "move" plan branch |
| 0.5 | Focus-charge bonus reads `funit.get("player")` (units store `owner`) and top-level `is_engaged` (lives in `flags`) | `AIDecisionMaker.gd:13408-13426` | The +3.0 "join a combat we're already in" bonus is dead code (the seed block at :13443 gets both keys right) |
| 0.6 | Multi-target charge reach reads `meta.base_mm` (base_mm lives on models) | `AIDecisionMaker.gd:13193, 13212` | Every unit treated as 32mm — Termagant and Knight get identical multi-charge spread gates |
| 0.7 | Martial Mastery average save is integer-truncated; missing save defaults to 7 | `AIDecisionMaker.gd:4984-4993` | Armies averaging 3.9 read as 3; logs print a misleading `%.1f` |
| 0.8 | Objective id/zone lookup by index after `_get_objectives()` filtered null positions | `AIDecisionMaker.gd:6957-6959` | Ids/zones can shift; scout code (:4098) documents and avoids this exact hazard, `_evaluate_all_objectives` doesn't |
| 0.9 | Reactive strat CP telemetry assumes cost 1 (Counter-Offensive is 2) | `AIPlayer.gd:1669, 2009` | Post-game CP summary wrong; poisons any future CP budget logic |
| 0.10 | Fight target scoring uses **max** wounds, not remaining | `AIDecisionMaker.gd:14843, 14860` | A Knight on 5/22 wounds isn't seen as finishable; `_calculate_kill_threshold()` (:11835) exists and is used by the fighter-priority scorer but not here |

---

## Tier 1 — Control-flow hazards (softlocks / forfeits)

1. **Empty AI decision doesn't count toward `MAX_ACTIONS_PER_PHASE`** —
   `AIPlayer.gd:1911-1914` returns before the action counter increments, so the
   watchdog escape hatch never fires. Every "AI has no branch for this action
   type" bug becomes a **permanent hang** instead of a slow recovery. Fixing this
   one line downgrades every gap below from softlock to nuisance.
2. **Moment Shackle window has zero AI handling** — `FightPhase.gd:3354-3376`
   short-circuits `get_available_actions()` to only `USE/DECLINE_MOMENT_SHACKLE`;
   `AIDecisionMaker` has no branch → combined with (1), an AI Custodes list with
   that ability **hangs the game**.
3. **Five blocking Movement-phase ability windows unhandled** —
   `MovementPhase.gd:7438-7568` (`KUNNIN_INFILTRATOR`, `DEFF_FROM_ABOVE`,
   `QUICKSILVER_EXECUTION`, `MEKANIAK`, `GROT_OILER`): none exist in
   AIDecisionMaker → ~6.7 min visible freeze until the 200-action escape routes a
   decline. Need real evaluators plus a generic "unknown blocking window →
   DECLINE immediately" fallback.
4. **Failed SHOOT → permanent SKIP_UNIT** — `AIPlayer.gd:2179-2202`. A transient
   failure (target died to earlier fire) forfeits the unit's whole shooting phase
   with no retarget attempt.
5. **Failed SELECT_FIGHTER → END_FIGHT forfeits all remaining fights** —
   `AIPlayer.gd:2038-2059`; `_fight_step_over()` defaults `true` when the phase
   is unreadable (:474-483), so a transient null ref ends the whole combat.
6. **Failed move → REMAIN_STATIONARY** — `AIPlayer.gd:2214-2230`; the retry
   ladder (`[0.75, 0.5, 0.25]` at :2336) only shortens the same heading, never
   picks an alternative destination. Classic "AI unit never leaves its corner".
7. **Failure handler has no default branch** — `AIPlayer.gd:2038-2258` covers 11
   action types via `elif`; anything else that fails waits for the 2s watchdog.
   A terminal `else: _request_evaluation()` removes most visible stalls.
8. **AI APPLY_SAVES stub is always rejected** — `AIDecisionMaker.gd:11211-11212`
   submits an empty `save_results_list`, which `ShootingPhase.gd:3029` rejects.
   Either build a real list from CasualtyPreference or delete the branch.

---

## Tier 2 — The CasualtyPreference class of problem: engine picks for the AI by index

These are the direct siblings of the bug #768 fixed.

1. **Transport destroyed → casualties from the back of the array** —
   `TransportManager.gd:407-428`. Highest-index-first is lowest-index mirrored;
   never consults CasualtyPreference. One-call fix.
2. **Emergency disembark placement: fixed 50px ring** — `TransportManager.gd:472-493`.
   Guaranteed base overlap for 10-model squads, no terrain/edge/ER checks, 18.05
   "cannot be set up → destroyed" never enforced. `EmergencyDisembarkMove.gd`
   (6" placement rule) exists but has **zero callers**.
3. **AI-attacker shooting bypasses 11e allocation entirely** —
   `ShootingPhase.gd:2725-2729, 3146-3202`: `_auto_roll_saves` has no 11e branch;
   ends in lowest-index allocation. Consequence: a human who enables "Computer
   allocates wounds" gets the **smart** allocator when shooting the AI but the
   **dumb** one when the AI shoots them — a hole in the just-shipped feature.
4. **`engine_auto_preference` gates on AI ownership only** —
   `CasualtyPreference.gd:135-145` returns `[]` for human defenders even when
   the auto-allocate setting is on (its own docstring names that setting).
5. **05.03 allocation-group ORDER is never chosen** — `Allocation.gd:114-124`
   `default_order()` (wounded→non-char→char, insertion order within) is used by
   every non-interactive path (`RulesEngine.gd:2942`). Which profile group soaks
   a volley is the biggest defender decision in 11e; CasualtyPreference's own
   docstring disclaims it. Needs a `compute_group_order()` sibling.
6. **~14 mortal-wound call sites allocate lowest-index** — root helpers
   `RulesEngine.gd:13852` / `:13642` / `:14842`; call sites include Desperate
   Escape (`MovementPhase.gd:4203`), Tank Shock (`StratagemManager.gd:3286`),
   EXPLOSIVES/CRUSHING IMPACT (`RulesEngine.gd:3116/3146/3150`), Spiked Ram
   (`ChargePhase.gd:1229`), emergency-disembark hazards (`TransportManager.gd:446`),
   plus `CommandPhase.gd:2704`, `ShootingPhase.gd:2569/5639/6602`,
   `FightPhase.gd:2022`, `FactionAbilityManager.gd:1444/2125/2641`. All accept a
   `preferred` argument that is simply never passed.
7. **Overwatch always allocates to lowest-index model** — `RulesEngine.gd:1521-1536`
   (and 10e twin at :4615) — no groups, no preference, and it fires on most charges.
8. **Coherency auto-removal ignores model value** — `PhaseManager.gd:499-556`
   removes the most isolated offender (good) but will happily kill the
   Nob/attached CHARACTER; and the AI's own explicit path is worse:
   `AIDecisionMaker.gd:16292` takes `REMOVE_MODEL_FOR_COHERENCY` offers `[0]` —
   dumber than the engine's backstop it sits in front of.
9. **PRECISION character pick is `eligible[0]`** — `RulesEngine.gd:3220-3228`;
   `precision_group_choice` is only ever set by the human overlay
   (`AllocationGroupOverlay.gd:672`), never by the AI. 10e path wraps an index
   (`ShootingPhase.gd:3190`). Target scoring also can't see attached characters
   at all (they fold into the bodyguard, which drops the CHARACTER keyword), so
   precision weapons are strategically invisible to the AI.
10. **HAZARDOUS casualty within-class pick is `candidates[0]`** — `RulesEngine.gd:9182-9226`.
11. **Attached-character auto-placement: spiral from model[0], first free slot due east** —
    `GameManager.gd:266-291, 396-425`. No zone/terrain/coherency validation, no
    "behind the squad" bias; assumes all bodyguards share model[0]'s base size (:370).
12. **Desperate Escape (both players): "For MVP, remove the first N alive models"** —
    `MovementPhase.gd:5790-5800`. The literal pattern #768 was built to kill.

---

## Tier 3 — Missing decision systems (AI never decides at all)

### Economy / stratagems
1. **No CP economy.** Nine evaluators each carry a private hardcoded CP floor
   (`AIDecisionMaker.gd:19404, 19999, 20085, 20172, 20224, 20390, 20610, 20658, 20691`);
   CP goes to the first window that clears its local bar, in phase order. Needs a
   per-turn budget with reserved reactive CP and a shared value-per-CP bar.
2. **Command Re-roll covers only charge/advance/battle-shock** — `AIPlayer.gd:1462-1486`
   `match` falls to always-decline for everything else. Save rolls emit
   `roll_type: "save_roll"` (`ShootingPhase.gd:6728`, `FightPhase.gd:1801`) but the
   AI's atomic paths never reach the window; hit/wound pauses
   (`USE_SHOOTING_REROLL`/`USE_FIGHT_REROLL`) have zero AI references; desperate
   escape and hazardous emit no window at all. The AI banks CP it structurally
   cannot spend on the highest-value rerolls in the game.
3. **Proactive faction stratagems: 9 named heuristics vs ~60 implemented** —
   `AIDecisionMaker.gd:19438-19681` `_:` returns `{}` with no effects-based
   fallback (the reactive path has one at :19944). Anything unnamed is never used.
4. **No charge-phase proactive stratagem call site** — `evaluate_proactive_faction_stratagems`
   is called for command/movement/shooting/fight (:4800/:5190/:11246/:14561), never "charge".
5. **NEW ORDERS is dead at 11e** — retired via `edition_max=10`
   (`StratagemManager.gd:4152`) with no `new_orders_11e` definition anywhere; the
   AI's ~40-line swap heuristic (:4756-4796) is unreachable dead code.
6. **Reactive stratagem window only exists in ShootingPhase** — `FightPhase`/`ChargePhase`
   never emit `reactive_stratagem_opportunity`; scored-and-ready defensive strats
   (the code comments on this at :19911) can never fire in melee.
7. **Difficulty gates are on/off switches** — five identical blanket declines
   below Hard (`AIPlayer.gd:993, 1106, 1140, 1336, 1449`). Normal-difficulty games
   have an unused CP pool and no reactive layer; scale thresholds instead.
8. **Easy difficulty is uniform randomness** — `AIDecisionMaker.gd:2075-2197`
   (random directions, 20% charge chance). Looks broken rather than easy; should
   be the scored path plus noise/handicaps (the `_apply_difficulty_noise` hook
   at :777 already exists).

### Movement / combat flow
9. **Engaged units always fall back unless standing on an objective** —
   `AIDecisionMaker.gd:8195-8233`. `_assess_engaged_unit_survival` computes a
   `hold/fall_back/neutral` recommendation (:8480) that is **thrown away**; the AI
   only models damage taken, never damage it would deal. A deathstar that just
   charged in retreats and forfeits shoot+charge.
10. **Desperate Escape is never a costed choice** — fall back defaults to
    ordered retreat; `desperate_escape` mode only fires as a blind retry after
    staging fails (`AIPlayer.gd:2377-2394`), with no expected-losses comparison.
11. **Advance: hardcoded +2", considered only in a 2" band** —
    `AIDecisionMaker.gd:5452-5461, 7602-7610, 8697`. D6 averages 3.5/max 6;
    reachable objectives 3-6" beyond M are never even considered.
12. **Advance ignores ASSAULT weapons** — no weapon-rule check anywhere in
    `_should_unit_advance` (:8710-8760) despite engine support
    (`RulesEngine.gd:4915`, detachment-wide assault included). All-Assault units
    treat advancing as total shooting loss.
13. **AI can never embark mid-game** — `MovementPhase.gd:7932-7937` skips the
    embark prompt for AI; `EMBARK_UNIT` appears nowhere in AIDecisionMaker.
    Transports are one-way at deployment, never a taxi or rescue.
14. **Loaded transports are routed by hull OC only** — `_assign_units_to_objectives`
    (:7186-8066) has zero cargo awareness beyond a "don't hold for shooting" hack (:5653).
15. **No FIGHTS FIRST / FIGHTS LAST awareness anywhere** — `FightPhase.gd:88,2510-2554`
    implements tiers; zero references in AIDecisionMaker. The fight-order plan
    reasons one tier below where the real decision happens.
16. **Melee attacks can never split** — `_assign_fight_attacks` (:14699-14829)
    emits one weapon/one target for the whole unit, no `attacking_models`, and the
    engine's one-weapon-rule guard (`FightPhase.gd:995`) would reject a second
    assignment anyway. Multi-engagements and klaw/choppa mixed squads fight at a
    fraction of their output.
17. **Pile-in runs before target selection and is pure geometry** —
    dispatch at :14452 before `_assign_fight_attacks`; models can pile toward
    enemy A then declare enemy B. No wrap/objective/max-models-in-ER intent.
18. **Charge scoring never models the counter-attack** — `_score_charge_target`
    (:13311-13527) has no swing-back estimate, no Fights First check; 200-pt units
    get thrown into fights they lose on the return swing.
19. **Post-roll charge retargeting never upgrades** — :13856-13890 builds the
    scored list its docstring promises to use, then discards it if any declared
    target is still in reach.
20. **Charge-move placement is first-legal** — `_cm_choose_endpoint` (:14235)
    never ranks candidates by models-in-ER / wrap / OC gained; overwatch risk
    model (:13531) ignores once-per-turn, LoS, and post-move distance.

### Shooting
21. **Shooting activation order is first-come** — :11352-11361 takes the first
    offered shooter with a plan; fight phase has a scored order plan, shooting
    has none, so kill-completion sequencing never happens.
22. **Fallback weapon assignment: no LoS check, no overkill accounting** —
    `_build_unit_assignments_fallback` (:12581-12630) independently argmaxes each
    weapon (emitting assignments the engine can reject) whenever plan targets die.
23. **HAZARDOUS is never costed in any decision** — zero references in
    AIDecisionMaker; the AI fires overcharge-equivalents from 1-wound characters for free.
24. **Fire Overwatch scored by raw dice count** — :20028-20040: `shots/6`, no
    S-vs-T, no range/LoS check to the charger, no charge-breaking intent. 30 grot
    shots beat 2 lascannons against a Knight.
25. **Firing Deck: dialog is unreachable and the auto-pick prefers the *worst* gun** —
    `ShootingPhase.gd:5342-5425`: only `"auto"` is ever returned (dead dialog
    branch at :992), loans are array-order, hazardous/one-shot excluded outright,
    "plainest gun wins" comment contradicts mixed-loadout rosters.
26. **Free/once-per-battle abilities auto-fire with zero evaluation** —
    `AIPlayer.gd:1020-1064` + `ShootingPhase.gd:2494-2609`: Distraction Grot,
    Pulsa Rokkit, Ammo Runt, Throat Slittas, Sentinel Storm always-on; **Shooty
    Power Trip is a 1-in-3 self-D3-mortals gamble taken unconditionally** (the
    code even logs the self-destruct case). Bomb Squigs targets `eligible_targets[0]`
    (`AIPlayer.gd:1078`).

### Deployment / reserves
27. **Deployment order is army-list order** — `deploy_actions[0]` (:3293) despite
    the full menu being offered; counter-deploy logic can only nudge positions of
    whatever is next.
28. **Infiltrators are never used** — zero `infiltrat` references in
    AIDecisionMaker; forward-deploy units get parked in the home DZ while
    `DeploymentPhase.gd:308-360` fully supports placement.
29. **Placement is a modulo column grid** — :3363-3395, one shared objective
    blend point for every unit; deployed_count counts reserved/embarked units.
30. **CHOOSE_DEPLOYMENT hardcoded "second"; redeploy phase hardcoded skip;
    roll-off fallbacks take `[0]`** — :4341-4358, :3903-3927, :4361-4403.
31. **Deep-strike placement scorer doesn't know which unit is arriving** —
    `_score_and_sort_reinforcement_candidates` (:6251) has no unit parameter:
    melee (wants 9.1" from a chargeable target), shooting (wants LoS/half-range)
    and screening units all get the same spot; no threat evaluation of the landing zone.
32. **No turn-of-arrival decision** — :5896-5920: reserves arrive at the first
    legal opportunity, no "wait for round 3" comparison; the objective term added
    per candidate is constant across candidates (contributes nothing).
33. **AIPlayer's own reinforcement fallback throws 5 random darts** —
    `AIPlayer.gd:3412-3423` (and the failed-deployment recovery at :3266).
34. **Strategic Reserves cap: docstring says 25%, code enforces 50%** — :3023 vs :3043.
35. **Rapid Ingress threshold is a rubber stamp and measures nothing reactive** —
    :20668-20740: generic reserve score ≥3.0 that any 200-pt deep striker clears.
36. **Warlord = most wounds (+10 if attached); leader pairing is greedy argmax;
    scout only ever runs at objectives** — :2681-2695, :2705-2733, :3951-4168.

### Command / scoring
37. **Battle-shock: dictionary-order testing, and zero "play around it" logic** —
    `AIDecisionMaker.gd:4440` + `CommandPhase.gd:292`; nothing anywhere avoids
    below-half triggers on objective holders, values shocking enemy units off
    markers, or times tests vs the once-per-phase reroll.
38. **Insane Bravery: flat magic bar (≥1.2), never compared vs 1-CP Command
    Re-roll of the same test, no round-5 use-it-or-lose-it** — :19283-19338.
39. **Secondary ranking ignores card VP** — achievability alone (:16372-16418);
    a 5-VP card at 0.30 loses to a 2-VP card at 0.45.
40. **Three uncoordinated secondary-management thresholds** — free DISCARD has
    the *strictest* bar (0.2) vs paid REPLACE (0.25) and NEW ORDERS (0.30/0.45)
    (:4746, :4782, :16392); can pay to swap then discard in the same round.
41. **Several `_assess_*` mission scores are constants** —
    `_assess_defend_stronghold` = 0.7, `_assess_action_mission` = 0.65,
    `_assess_assassination` = 0.6, no_prisoners fallthrough = 1.0
    (:16938, :17549, :17040, :16714); storm-hostile/extend-battle-lines bucket
    purely on alive-unit count.
42. **No primary-vs-secondary tradeoff in `_decide_scoring`** — primary
    awareness is built (:16445) but only movement consumes it.
43. **11e mission-card actions auto-resolve first-eligible for the AI** —
    `MissionManager.gd:1461-1566`: Triangulate/Consecrate pick the first
    controlled objective, **Death Trap traps the first terrain feature and
    systematically forgoes the +3 VP objective-holding bonus** the human prompt
    advertises; Condemn takes `.slice(0,3)` in dict order. Humans get a revision
    prompt; the AI's auto-pick is final (`ScoringController.gd:807`).
44. **Marked for Death sorts by points, gamma = `remaining[0]`** —
    `AIPlayer.gd:2858-2885` (comment says "most damaged", code says lowest
    points); the CommandPhase backstop (:2664-2685) is worse: pure array slices.
45. **Combat Doctrine = round-number lookup** (:4934) ignoring army composition;
    **Ka'tah stance = `T>=7` cut** ignoring own Strength (:19767);
    **Acrobatic Escape always vanishes** (:16305) — the adjacent END_TURN_REDEPLOY
    block was already fixed away from exactly this pattern;
    **round-1 secondary shuffle-back auto-taken with a TODO** (`SecondaryMissionManager.gd:311`).
46. **Reroll heuristics use dice thresholds, never stakes** —
    charge/advance/battleshock evaluators (:20575-20666) never see what the roll
    is *worth* (the charge evaluator already computed a full score that isn't passed in).
47. **Counter-Offensive scores proxies (keywords, unit value), not the actual
    interrupt value** (:20250-20313) — no melee-damage estimate either direction,
    hardcoded 1.5" engagement stand-in despite the file's own ISS-002 rule.
48. **Grenade evaluator never checks CP and runs once per phase** (:19101-19181);
    its shooting-strength comparison hardcodes T4/50% save (:19205).

---

## Tier 4 — Low / hygiene

- Ties resolve by dict insertion order throughout (fallback target :12608, fight
  target :14756, overwatch :20032, counter-offensive :20310) — apply
  `_apply_difficulty_noise` or an explicit deterministic tiebreak.
- Fight windows taken by `[0]`: PILE_IN :14453, ASSIGN_ATTACKS_UI :14459,
  CONSOLIDATE :14578, SWEEPING_ADVANCE :14605 — order by the already-computed
  fighter priority.
- Consolidate tag-target is proximity-only (:15790); pile-in claims coherency in
  its docstring but never checks it (:15310) — `_cm_unit_coherent` exists.
- Secondary-mission score multipliers hardcoded and fetched via scene tree inside
  "pure static" code (:18756-18787) — route through `get_param`.
- Three phases open with unconditional `DECLINE_COMMAND_REROLL` fallbacks
  (:4417, :5030, :12651) — silent decline if signal wiring ever slips; add `push_warning`.
- `BEGIN_SURGE_MOVE` window (`MovementPhase.gd:7666`) has no AI answer (harmless
  until a datasheet ships one).
- `RulesEngine._apply_damage_to_unit` (:12822) — "apply to first alive model",
  zero callers; delete before someone calls it.
- Dialog-only abilities with no AI path at all (silently unused, no stall):
  Krump and Run, Scatter — they never appear in `get_available_actions`.
- Fall-back direction fan is first-legal from a hardcoded ±30°…180° list
  (:8326-8341) and the last-resort direction assumes top/bottom zones (:8296).

---

## Suggested implementation order

1. **Tier 0 key/parse bugs** (0.1–0.10) — one-liners, immediately raise the
   quality of every decision downstream. Do 0.1 + 0.2 first: they correct the
   damage numbers every other heuristic is built on.
2. **Tier 1 items 1 + 7** (count empty decisions, default failure branch) —
   converts all present and future gaps from hangs into recoverable stalls; then
   the Moment Shackle / movement-window evaluators.
3. **Tier 2** — thread CasualtyPreference through the ~14 mortal-wound sites,
   transport destruction, overwatch, `_auto_roll_saves` 11e branch, and widen
   `engine_auto_preference` to the auto-allocate setting (finishes what #768 started).
4. **Highest-leverage Tier 3**: engaged-unit hold-vs-fallback (9), Assault-aware
   advance (12), deployment order (27), reserves unit-aware placement + arrival
   timing (31/32), melee split attacks (16), CP budget (1), command-reroll
   coverage (2), effects-fallback for faction stratagems (3).

**Validation caveat:** every finding above is from reading the code (with the
Tier-0 items spot-verified against the source and army JSON). None were
reproduced in a live windowed session. Per the project gate, each fix that lands
must add/extend a windowed scenario driving the affected decision.

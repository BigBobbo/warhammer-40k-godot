# AI Dossier: The Parameter/Override Stack and Army Personality

All file paths are relative to the repo root `/home/user/warhammer-40k-godot/` unless shown absolute. The main file is `40k/scripts/AIDecisionMaker.gd` (referred to as **ADM** below). Every number in this document was read directly from the code, not guessed.

## Overview

The AI's behaviour is controlled by roughly 90 named "knobs" — scoring weights like `WEIGHT_UNCONTROLLED_OBJ` or `PLAN_EARMARK_HOLD_BONUS`. Every knob has a factory-default value written as a `const` in the code, but almost every place that uses one asks for it through a single resolver function called `get_param()`, which checks a stack of override layers before falling back to the default. The layers, from weakest to strongest, are: the code default, the shipped config file (`40k/data/ai_config.json`), a per-machine config file (`user://ai_config.json`), a "profile fragment" carried by an authored battle plan, a per-player profile (a JSON personality file), and finally *conditional rules* inside that profile that fire only when the game situation matches (e.g. "round 4 or later AND behind on victory points"). As shipped today, the config file overrides exactly one thing — `PLANS_ENABLED = 1` — which happens to equal the code default anyway, so **every default value listed below is the effective in-game value**. On top of this knob system sits "army personality": once per game the AI scans each army's weapons and classifies it as MELEE, SHOOTING, ELITE, or BALANCED, then multiplies its aggression, objective-priority, survival, and charge-willingness numbers accordingly — this is what produces the "AGGRESSIVE / MELEE army" stance line in the game log. A second, independent personality lever keys off the faction name (Orks, Custodes, World Eaters, Khorne) and mainly makes those factions charge more willingly. Finally, authored battle plans can pre-script deployment spots, reserves, and leader attachments, and can "earmark" units with standing orders (hold this objective, push the centre, hunt characters, screen) that add fixed bonuses to the normal scoring rather than replacing it.

## Decision flow

How the override machinery executes, in order:

1. **Game boot.** `AIPlayer._ready()` calls `AIDecisionMaker.load_config_overrides()` (40k/autoloads/AIPlayer.gd:175). That function reads two files in order — `res://data/ai_config.json` (ships with the game), then `user://ai_config.json` (per-machine, e.g. exported by the AI Gameplay Visualizer) — and merges their `"parameters"` objects into one dictionary, later file winning per key (ADM:289-322). Today the shipped file contains only `PLANS_ENABLED: 1` (40k/data/ai_config.json:15-17).
2. **Game start.** `AIPlayer.configure()` clears all per-player profiles **and all plans** (AIPlayer.gd:323-325 → ADM:337-347). Then `Main._initialize_ai_player()` re-applies the profile chosen in the menu for each AI seat (`player1_ai_profile` / `player2_ai_profile` → `AIPlayer.load_player_profile`, Main.gd:715-721; AIPlayer.gd:337-346), and afterwards applies any menu-chosen plan (`_apply_configured_plans`, Main.gd:725-728). Profiles are JSON files in `user://ai_profiles/` (ProfileManager.gd:8-9).
3. **Plan resolution.** The first time a decision needs a plan, `_resolve_plan_for()` returns the explicitly assigned plan, or makes exactly one auto-match attempt against the plan library (`user://ai_plans/` first, then shipped `res://data/ai_plans/` — PlanManager.gd:25-26), matching on army + deployment zone + terrain layout (ADM:433-448). Everything plan-related is gated on `PLANS_ENABLED` (ADM:418-421). If the plan carries a `profile_fragment`, it is installed *as* that player's profile — but only if the player doesn't already have an explicit profile; an explicit profile always wins (ADM:1074-1093).
4. **Every single decision** (`decide()`, ADM:2965): if the acting player has a profile, the AI builds a context snapshot — current phase, round, VP difference, % of units remaining, plus details about the unit about to act (is it melee-focused? a vehicle? on an objective? how far is the nearest enemy? how many points is it?) — and runs `evaluate_rules()` over the profile's conditional rules (ADM:2971-3030). Rules whose conditions all match write their parameter overrides into `_active_rule_overrides`, which is cleared and recomputed fresh each call (ADM:1110-1128).
5. **Every knob read** during that decision goes through `get_param(name, default)` which resolves top-down: (1) active rule overrides, (2) the current player's profile parameters, (3) the merged ai_config overrides, (4) the code default passed in (ADM:1235-1256; integer twin at 1258-1275). Every read is recorded so decision records can list which knobs actually mattered (ADM:1225-1233).
6. **Personality multipliers** are then layered onto scores inside the decision logic: army archetype (detected once per game, ADM:14207-14212) is multiplied together with the round strategy ("AGGRESSIVE" rounds 1-2 / "BALANCED" round 3 / "OBJECTIVE/SURVIVAL" rounds 4-5, ADM:14024-14053, 14228-14237) and applied to objective scores, threat penalties, target values, and the charge threshold (ADM:8893-8909, 9014-9033, 14476, 15139-15145, 15653, 17357). Faction aggression divides the charge threshold (ADM:15158-15164) and gates the melee-chase logic (ADM:2196-2275).
7. **Plan hooks fire inside the phase logic**: formations declarations (attachments → embarkations → reserves) are consumed from the plan before the normal evaluators run (ADM:4012-4021, 744-866); deployment picks the plan's next unit and its exact model positions, validating and if necessary repairing them, falling back to the normal formula per-unit if repair fails (ADM:4723-4752, 608-678); earmark bonuses are added inside the normal movement/shooting/charge/fight scorers (ADM:9255-9258, 21226, 15467, 17079).

## The override stack, bottom to top

| Layer (bottom → top) | Where it lives | Who wins | Evidence |
|---|---|---|---|
| 1. Code defaults | `const` values in ADM (e.g. ADM:945-948, 1984-2051) | Used only when nothing above overrides | ADM:1254-1256 |
| 2. Shipped config | `40k/data/ai_config.json` → `"parameters"` | Overrides code defaults; **currently only `PLANS_ENABLED: 1`** (equal to the default), so all const defaults are effective | 40k/data/ai_config.json:15-17; ADM:298 |
| 3. Machine config | `user://ai_config.json` | Merged over layer 2, later file wins per key (both land in one `_config_overrides` dict) | ADM:298-320 |
| 4. Plan `profile_fragment` | inside a matched plan JSON | Installed as the player's profile **only if no explicit profile exists** — an assigned profile is never overwritten by a plan | ADM:1074-1093 |
| 5. Per-player profile parameters | `user://ai_profiles/<name>.json` → `"parameters"` | Beats config for that player only (checked against `_current_player`) | ProfileManager.gd:8-9; ADM:1242-1248 |
| 6. Conditional rule overrides | `"rules"` array inside the profile | Highest priority; recomputed every decision from live game context | ADM:1110-1128, 1237-1241 |

The intended order is documented in the code itself: "rule overrides > an explicitly assigned per-player profile > the plan's fragment > ai_config.json > code default" (ADM:1077-1078), and in docs/AI_TUNING.md:16-25.

## Scoring tables

### Conditional rule engine — every condition type (ADM:1130-1175)

All conditions in one rule are ANDed — every one must pass (ADM:1131). Rules run in ascending `priority` order (lower number first, ADM:1120-1122); each firing rule writes into the same override map, so if two rules touch the same parameter the one that runs **last** (highest priority number) wins. Disabled rules (`enabled: false`) are skipped (ADM:1124).

| Condition type | Passes when… | Evidence |
|---|---|---|
| `phase` | current phase name equals the value (e.g. "MOVEMENT", "CHARGE") | ADM:1136-1138 |
| `round_gte` | battle round ≥ value | ADM:1139-1141 |
| `round_lte` | battle round ≤ value | ADM:1142-1144 |
| `vp_ahead` | my VP minus opponent VP > 0 (no value needed) | ADM:1145-1147 |
| `vp_behind` | my VP minus opponent VP < 0 (no value needed) | ADM:1148-1150 |
| `vp_diff_gte` | ahead by at least the value | ADM:1151-1153 |
| `vp_diff_lte` | **behind** by at least the value (passes when vp_diff ≤ −value) | ADM:1154-1156 |
| `units_remaining_pct_lte` | my surviving-units percentage ≤ value | ADM:1157-1159 |
| `enemy_within_inches` | nearest enemy to the acting unit ≤ value inches | ADM:1160-1162 |
| `on_objective` | the acting unit's centre is within objective control range | ADM:1163-1165 |
| `is_melee_unit` | acting unit is melee-focused (see personality section) | ADM:1166-1168 |
| `is_vehicle` | acting unit has the VEHICLE keyword | ADM:1169-1171 |
| `unit_points_gte` | acting unit costs at least the value in points | ADM:1172-1174 |

### Rule actions (ADM:1177-1198)

| Action type | What it does | Evidence |
|---|---|---|
| `override` (default) | sets the parameter to the given value outright | ADM:1186-1187 |
| `multiply` | multiplies the parameter's *base* value (profile or config) by the given value | ADM:1188-1193 |
| `add` | adds the given value to the *base* value | ADM:1194-1198 |

**Gotcha (real code behaviour, worth knowing):** for `multiply`/`add`, "base value" comes from `_get_base_param_value()`, which only checks profile parameters and config overrides — if the parameter appears in neither, it returns **0.0** (ADM:1200-1210). So a `multiply` rule on a parameter that only exists as a code default sets it to 0, it does *not* multiply the default. Use `override` for such parameters, or list a base value in the profile's `parameters` block. (A second quirk: the base lookup scans *all* loaded profiles, not just the acting player's — ADM:1203-1206.)

Rules can override **any** parameter that flows through `get_param`/`get_param_int` — the same ~90-knob catalogue documented in docs/AI_TUNING.md (the config file's own README says "all 91", 40k/data/ai_config.json:5); ADM contains ~295 `get_param(` call sites.

### Plan earmark priors (ADM:945-948, all overridable via the stack)

Earmarks are explicitly "PRIORS, not orders" — each verb adds a bonus into scoring the AI already does; it never forces a move or overrides legality (ADM:939-943).

| Term | Default value | Plain-English meaning |
|---|---|---|
| `PLAN_EARMARK_HOLD_BONUS` | **+8.0** | Added to the movement-assignment score of the specific objective a `HOLD_OBJECTIVE` earmark names (applied at ADM:9255-9258) |
| `PLAN_EARMARK_PUSH_BONUS` | **+6.0** | Added to the score of the board-centre objective(s) for a `PUSH_CENTER` earmark (central objectives resolved at ADM:999-1024) |
| `PLAN_EARMARK_HUNT_BONUS` | **+4.0** | Added when a `HUNT_CHARACTERS` unit scores a CHARACTER target — in shooting (ADM:21226), charge (ADM:15467) and fight (ADM:17079). Additive on top of the scorers' existing 1.2× CHARACTER multiplier (ADM:1053-1058) |
| `PLAN_EARMARK_RELEASE_AT` | **0.5** | Release threshold: once a unit falls **below 50% of its starting models**, its earmark is dropped for good and it rejoins normal decision-making (ADM:973-997) |
| `SCREEN` verb | (no number) | Withholds the unit from the objective-assignment passes entirely so it falls through to the screening pass (ADM:1044-1051, 8879-8885) |

### Army archetype detection thresholds (ADM:1984-1987)

| Term | Default value | Plain-English meaning |
|---|---|---|
| `ARCHETYPE_MELEE_THRESHOLD` | 0.60 | Army is MELEE if ≥60% of its rough total damage output (attacks × damage × models, per weapon — ADM:14100-14114) is melee |
| `ARCHETYPE_SHOOTING_THRESHOLD` | 0.65 | Army is SHOOTING if ≥65% of output is ranged |
| `ARCHETYPE_ELITE_AVG_WOUNDS` | 4.0 | ELITE check (runs first, beats melee/shooting): average wounds per model ≥ 4… |
| `ARCHETYPE_ELITE_AVG_POINTS` | 40.0 | …AND average points per model ≥ 40 (ADM:14139-14143). Anything else is BALANCED |

Note: these four are bare `const`s used directly (ADM:14141-14151) — they are *not* read through `get_param`, so profiles cannot move them.

### Archetype personality modifiers (ADM:1989-2005; wired in `_make_archetype_result`, ADM:14159-14205)

| Modifier | MELEE | SHOOTING | ELITE | BALANCED | What the number multiplies |
|---|---|---|---|---|---|
| aggression | **1.25** | 0.8 | 0.9 | 1.0 | kill-seeking scores: target value (ADM:14476), shooting scores (ADM:15653), fight scores (ADM:17357) |
| objective_priority | **0.9** | 1.1 | 1.15 | 1.0 | every objective-assignment score (ADM:8909) |
| survival | **0.8** | 1.3 | 1.25 | 1.0 | threat-avoidance penalties on movement (ADM:9014-9033) — lower = happier to walk into danger |
| charge_threshold | **0.75** | 1.3 | 1.0 | 1.0 | the bar a charge must clear to be declared (ADM:15139-15145) — lower = charges more |

These are also bare `const`s (not `get_param`-tunable). They stack **multiplicatively** with the round-strategy modifiers (ADM:14228-14237).

### Round strategy modifiers (ADM:14024-14053; consts at ADM:1966-1973 — these ARE `get_param`-tunable)

| Modifier | Rounds 1-2 "AGGRESSIVE" | Round 3 "BALANCED" | Rounds 4-5 "OBJECTIVE/SURVIVAL" |
|---|---|---|---|
| aggression | 1.3 | 1.0 | 0.7 |
| objective_priority | 0.95 | 1.0 | 1.6 |
| survival | 0.7 | 1.0 | 1.4 |
| charge_threshold | 0.5 | 1.0 | 1.3 |

### Faction aggression (ADM:2019-2023; read via `get_param` at ADM:2087-2100 so fully tunable)

| Term | Default value | Plain-English meaning |
|---|---|---|
| `FACTION_AGGRESSION_DEFAULT` | 1.0 | Everyone not listed below |
| `FACTION_AGGRESSION_ORKS` | 1.2 | Benchmark-tuned down from 1.8 on 2026-07-10: at ≥1.5 even shooty Ork units chased across the board and primary VP starved (comment at ADM:2021) |
| `FACTION_AGGRESSION_CUSTODES` | 1.5 | Elite melee fighters |
| `FACTION_AGGRESSION_KHORNE` | 1.8 | Khorne daemons |
| `FACTION_AGGRESSION_WORLD_EATERS` | 2.0 | "Blood for the blood god" |

What it changes: when > 1.0 the charge threshold is **divided** by it (ADM:15158-15164); at ≥ 1.5 the melee-chase gate loosens its leave-the-objective distance limits (18" vs 14" in round 1, etc.) and enables horde advances and round-1 setup charges (ADM:2208-2275). Since the 2026-07-10 rebalance it no longer decides *which* units chase (only melee-focused units chase — ADM:2158-2176), just *how* aggressively.

### Melee-seek movement bonuses (ADM:2027-2030, `get_param`-tunable)

| Term | Default | Meaning |
|---|---|---|
| `MELEE_AGGRESSION_ENEMY_SEEK_BONUS` | 8.0 | Movement score bonus for closing on the nearest enemy |
| `MELEE_AGGRESSION_CHARGE_RANGE_BONUS` | 12.0 | Big bonus for ending the move within charge range |
| `MELEE_AGGRESSION_ADVANCE_THRESHOLD_INCHES` | 20.0 | Chase cap — ignore enemies further than this (floored at own move+14", ADM:2245-2251) |
| `MELEE_AGGRESSION_MIN_MOVE_RATIO` | 0.6 | Move at least 60% of Move stat toward the enemy |

## Worked example

*Invented but realistic: an Ork army (auto-detected MELEE archetype), Hard difficulty, round 1, deciding whether a Boyz mob declares a charge, with a plan earmark in play.*

**Step 1 — where each number comes from.** No profile is loaded and the config file only sets `PLANS_ENABLED`, so every `get_param` call falls through to its code default (ADM:1235-1256).

**Step 2 — the charge threshold** (a charge is only declared if its score beats this bar), built at ADM:15124-15164:

| Factor | Value | Why |
|---|---|---|
| Base | 1.00 | ADM:15126 |
| Tempo (VP behind?) | ×1.00 | Round 1, scores level — no desperation discount (ADM:15127-15130) |
| Difficulty: Hard | ×0.85 | AIDifficultyConfig.gd:111-112 |
| Round strategy: rounds 1-2 | ×0.50 | `STRATEGY_EARLY_CHARGE` (ADM:1969, applied via 15139-15142) |
| Archetype: MELEE | ×0.75 | `ARCHETYPE_MELEE_CHARGE` (ADM:1993, multiplied into the same strategy at 14235) |
| Faction: Orks | ÷1.20 | threshold divided by `FACTION_AGGRESSION_ORKS` (ADM:15160-15162) |

Threshold = 1.00 × 0.85 × (0.50 × 0.75) / 1.2 ≈ **0.266**. The same charge that a SHOOTING army in round 5 would need a score of 1.0 × 0.85 × (1.3 × 1.3) = 1.44 to take, the round-1 Ork MELEE army takes at 0.27 — over five times more willing.

**Step 3 — the earmark bias.** The plan earmarks this mob `HOLD_OBJECTIVE: obj_3`. In movement assignment (ADM:8899-9258), suppose objective 3 evaluates at priority 11.0 and objective 2 at 14.0. Base scores: 11.0 and 14.0, each ×0.855 objective_priority (round 1 AGGRESSIVE 0.95 × MELEE 0.9, ADM:14232-14234 applied at 8909) → 9.41 vs 11.97. The earmark then adds `PLAN_EARMARK_HOLD_BONUS` +8.0 to objective 3 only (ADM:9255-9258): **17.41 vs 11.97** — the mob keeps its planned station. Two rounds later the mob is down to 9 of 20 models (45% < the 50% `PLAN_EARMARK_RELEASE_AT`): the earmark is released with a log line and the +8 disappears for the rest of the game (ADM:973-997).

## Difficulty gates

Difficulty (40k/scripts/AIDifficultyConfig.gd) is a separate axis from the override stack — it is passed into `decide()` (ADM:2965), not resolved through `get_param`. Where it interacts with this topic:

- **Easy** picks random valid actions (AIDifficultyConfig.gd:23-24; ADM:3046-3048), so profiles, rules, plans-as-priors, archetypes and faction aggression effectively do not matter — none of the scorers run. (Rule evaluation itself still executes at ADM:2972-3030, but nothing reads the results.)
- **Score noise** blurs all scoring: Easy 100.0, Normal 1.5, Hard 0.5, Competitive 0.0 (AIDifficultyConfig.gd:72-83) — so hand-tuned weights express most cleanly at Hard/Competitive.
- **Charge threshold modifier** stacks multiplicatively with the personality factors shown above: Easy 2.0, Normal 1.0, Hard 0.85, Competitive 0.7 (AIDifficultyConfig.gd:105-116, applied at ADM:15132-15133).
- Plans and earmarks have **no difficulty gate of their own** — only `PLANS_ENABLED` (ADM:418-421) — but on Easy they never surface because the plan hooks live inside the scored decision paths.

## Authored plans in brief (how they plug into the stack)

- **Master switch:** `PLANS_ENABLED` (default on; the one shipped config entry). Setting it to 0 restores pre-plan behaviour exactly (ADM:418-421; 40k/data/ai_config.json:10-13).
- **Matching:** explicit assignment from the menu (Main.gd:725-728, ADM:378-391) or one auto-match attempt per player per game against `user://ai_plans/` then `res://data/ai_plans/` (ADM:433-448; PlanManager.gd:25-30). Plan coordinates are authored in the player-1 frame and mirrored `[x,y] → [44−x, 60−y]` inches for seat 2 (ADM:357-358, 490-508).
- **Deployment:** the plan chooses both the next unit (deployment `order`, ADM:461-480) and its exact model positions (`placements`/`models_inches`, ADM:482-508). Placements are pre-validated against everything the deployment phase checks (zone polygon, overlaps, walls, coherency — ADM:548-606); an illegal placement is repaired, and if repair fails that one unit falls back to the normal column formula (ADM:633-645). "A plan is an INTENT with a fallback chain, never a script" (ADM:354-356).
- **Formations:** attachments, then embarkations, then reserves are consumed from the plan before the normal evaluators (ADM:4012-4021, 744-866). Plan reserves are trimmed to the Chapter Approved 50% caps (half of total points, half of total units, counting an attached leader's points with its reserved bodyguard) in plan order (ADM:692-742, caps computed at 710-711). A plan with an *empty* reserves list positively means "nothing in reserves" and suppresses the AI's own reserves logic (ADM:682-690).
- **Earmarks:** the +8 / +6 / +4 priors and the 50%-strength release described in the tables above.
- **Profile fragment:** a plan may carry parameters/rules that install as the player's profile — never over an explicitly assigned one (ADM:1074-1093).

## Evidence

- 40k/data/ai_config.json:1-19 — shipped config; layering README; only override is `PLANS_ENABLED: 1`
- 40k/autoloads/AIPlayer.gd:175 — config loaded at startup; :323-325 configure() clears profiles+plans; :337-346 per-player profile load
- 40k/scripts/Main.gd:707-728 — menu profiles and plans applied after configure()
- 40k/scripts/ProfileManager.gd:8-9 — profiles live in `user://ai_profiles/`
- 40k/scripts/PlanManager.gd:25-30 — plan search path and match kinds
- ADM 40k/scripts/AIDecisionMaker.gd:
  - 289-322 `load_config_overrides` (two layers, later wins); 324-347 profile load/clear (clear also clears plans)
  - 1235-1275 `get_param` / `get_param_int` resolution order; 1225-1233 param-read recording
  - 1110-1175 `evaluate_rules` + all 13 condition types; 1177-1210 rule actions and the base-value-0 gotcha
  - 2965-3042 `decide()` entry: rule-context build, evaluation, strategy/archetype log line
  - 349-448 plan gating, set/clear/suppress, auto-match; 452-678 deployment consumption; 682-937 formations/reserves consumption (50% caps at 710-711)
  - 945-948 earmark defaults (+8/+6/+4, release 0.5); 954-1072 earmark resolution, release, HOLD/PUSH/HUNT/SCREEN; 1074-1093 profile fragment
  - 9255-9258, 21226, 15467, 17079, 8879-8885 — earmark bonuses applied in movement, shooting, charge, fight, screening
  - 1981-2005 archetype enum, thresholds, modifier consts; 14059-14243 detection, result build, caching, strategy merge
  - 1954-1973 tempo and round-strategy consts; 14024-14053 round strategy ("AGGRESSIVE"/"BALANCED"/"OBJECTIVE/SURVIVAL")
  - 6825-6905 turn-intent announcement — source of the "Movement plan (Round N, AGGRESSIVE / MELEE army)" log line
  - 2019-2023, 2087-2127 faction aggression values and name detection; 15124-15170 full charge-threshold stack; 2196-2275 melee chase gate
  - 2129-2176 melee-focused unit classifier and seeker gate; 2027-2030 melee-seek bonuses
- 40k/scripts/AIDifficultyConfig.gd:23-24, 72-83, 105-116 — Easy randomness, score noise, difficulty charge modifier
- docs/AI_TUNING.md:16-28 — the project's own statement of the resolution priority (matches the code)

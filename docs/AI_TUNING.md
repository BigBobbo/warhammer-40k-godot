# AI Tuning Guide — how to hand-edit the AI

The AI's tactical behavior is driven by ~90 named scoring weights plus a
per-player profile/rules system. You can change all of it **without touching
GDScript**. This page documents every knob, where it lives, and how to test a
tweak.

For how the AI *decides* (algorithms per phase), see
`AI_SYSTEM_DOCUMENTATION.md`. For a critical review + roadmap, see
`AI_DECISION_REVIEW_2026-07.md`.

---

## Where to edit

Resolution priority for every parameter (highest wins):

| Priority | Source | File | When to use |
|---|---|---|---|
| 1 | **Conditional rules** | inside a player profile (`rules` array) | "IF behind on VP in round 4+ THEN raise aggression" |
| 2 | **Per-player profile** | `user://ai_profiles/<name>.json` | Give P1 and P2 different personalities |
| 3 | **Machine config** | `user://ai_config.json` | Local experiments, exported by the AI Gameplay Visualizer web app |
| 4 | **Shipped config** | `res://data/ai_config.json` (in the repo: `40k/data/ai_config.json`) | Tweaks you want committed to the game |
| 5 | Code defaults | `const` values in `40k/scripts/AIDecisionMaker.gd` | — |

`user://` on Linux is `~/.local/share/godot/app_userdata/40k/`, on macOS
`~/Library/Application Support/Godot/app_userdata/40k/`.

All config files share the same shape:

```json
{
  "parameters": {
    "WEIGHT_UNCONTROLLED_OBJ": 14.0,
    "FACTION_AGGRESSION_ORKS": 2.2
  }
}
```

Profiles additionally support `format`/`profile_name` metadata and a `rules`
array (see below). Config is loaded once at startup (`AIPlayer._ready` →
`AIDecisionMaker.load_config_overrides()`); restart the game (or call
`AIDecisionMaker.load_config_overrides()` from the MCP bridge) after editing.

### Per-player profiles

`user://ai_profiles/<name>.json`, validated by `ProfileManager.gd`:

```json
{
  "format": "wh40k_ai_profile",
  "version": 1,
  "profile_name": "Reckless Waaagh",
  "description": "Charges everything, ignores threat zones",
  "parameters": { "FACTION_AGGRESSION_ORKS": 2.4, "THREAT_CHARGE_PENALTY": 0.5 },
  "rules": [
    {
      "id": "desperate_lategame",
      "name": "All-in when losing late",
      "priority": 1,
      "enabled": true,
      "conditions": [ {"type": "round_gte", "value": 4}, {"type": "vp_behind"} ],
      "actions": [ {"type": "multiply", "param": "URGENCY_LATE_GAME_PUSH", "value": 1.5} ]
    }
  ]
}
```

Load with `AIPlayer.load_player_profile(player, "Reckless Waaagh")` (Main.gd
does this automatically when the game config names a profile). The
`ai-creator/index.html` web app in the repo root builds these files visually.

**Rule conditions** (ANDed): `phase` (FORMATIONS/DEPLOYMENT/MOVEMENT/SHOOTING/
CHARGE/FIGHT/SCORING), `round_gte`, `round_lte`, `vp_ahead`, `vp_behind`,
`vp_diff_gte`, `vp_diff_lte`, `units_remaining_pct_lte`,
`enemy_within_inches`, `on_objective`, `is_melee_unit`, `is_vehicle`,
`unit_points_gte`.
**Rule actions**: `override`, `multiply`, `add` — each with `param` + `value`.

### Difficulty gates (not in the config file)

Feature availability per difficulty (Easy/Normal/Hard/Competitive) is code in
`40k/scripts/AIDifficultyConfig.gd` — e.g. multi-phase planning is Hard+,
score noise per tier, charge-threshold modifier. Edit that file to change what
a tier is allowed to do.

### Testing a tweak

```bash
# AI-vs-AI regression: 3 headless games, prints wins + VP differential
bash 40k/tests/run_ai_benchmark.sh 3

# With profiles applied to one side:
bash 40k/tests/run_ai_benchmark.sh 5 audit_baseline_postdeploy "" my_profile.json
```

Watch a live game: the AI narrates every decision (chosen option, score, and
rejected alternatives) into the in-game game log; press **F10** to export the
full machine-readable decision log to `user://ai_decision_log.json`.

---

## Parameter reference (defaults as of 2026-07)

### Movement — objective scoring

| Parameter | Default | Meaning |
|---|---|---|
| `WEIGHT_UNCONTROLLED_OBJ` | 10.0 | Priority of objectives nobody controls |
| `WEIGHT_CONTESTED_OBJ` | 8.0 | Priority of objectives both sides sit on |
| `WEIGHT_ENEMY_WEAK_OBJ` | 7.0 | Priority of enemy objectives we can flip: their per-model OC (14.02) is ≤ 4 or below the OC we can bring within two moves |
| `WEIGHT_ENEMY_STRONG_OBJ` | -5.0 | Priority of strongly-held enemy objectives (avoid) |
| `WEIGHT_ALREADY_HELD_OBJ` | -3.0 | Priority of objectives we already safely hold |
| `WEIGHT_HOME_UNDEFENDED` | 9.0 | Extra priority when our home objective has no defender |
| `WEIGHT_SCORING_URGENCY` | 3.0 | Round-1 rush bonus (scoring starts round 2) |
| `WEIGHT_OC_EFFICIENCY` | 2.0 | Bonus for sending high-OC units where OC is needed |
| `WEIGHT_VP_PER_POINT` | 1.2 | Priority per expected VP the objective pays at next scoring (mission-aware) |
| `URGENCY_ROUND_2_CONTEST` | 2.0 | Round 2: contest uncontrolled objectives (first scoring round) |
| `URGENCY_ROUND_3_HOLD` | 1.5 | Round 3: consolidate/hold |
| `URGENCY_LATE_GAME_PUSH` | 2.5 | Rounds 4-5: flip everything flippable |

### Movement — positioning & safety

| Parameter | Default | Meaning |
|---|---|---|
| `THREAT_CHARGE_PENALTY` | 2.0 | Penalty for ending a move inside an enemy charge-threat zone |
| `THREAT_SHOOTING_PENALTY` | 0.5 | Penalty for ending inside enemy weapon range |
| `THREAT_CLOSE_MELEE_PENALTY` | 2.0 | Extra penalty for ending within 12" of enemy melee |
| `THREAT_FRAGILE_BONUS` | 1.3 | Threat multiplier for fragile/high-value units |
| `THREAT_MELEE_UNIT_IGNORE` | 0.05 | How much melee units care about charge threat (≈ not at all) |
| `WEIGHT_FIRING_POSITION_KEPT` | 3.0 | Bonus for destinations keeping current shooting targets in range |
| `WEIGHT_FIRING_POSITION_LOST` | -2.5 | Penalty for destinations losing ALL shooting targets |
| `WEIGHT_FIRING_POSITION_GAINED` | 1.5 | Bonus for destinations bringing new targets into range |
| `FIRING_POSITION_BLEND` | 0.35 | 0-1: how far movement bends toward a firing position vs the objective |
| `CHARGE_BLEND_REACH_INCHES` | 9.0 | A move only bends toward a planned charge target if it then ends within this many inches of it (tried 30%/50%/70% toward it, objective-first); otherwise the unit heads straight for its objective |
| `HALF_RANGE_MOVE_BLEND` | 0.4 | 0-1: how far movement bends toward Rapid Fire/Melta half-range |
| `HALF_RANGE_MIN_BENEFIT` | 2.0 | Min extra expected attacks/damage to bother repositioning for half-range |
| `HALF_RANGE_APPROACH_MARGIN_INCHES` | 1.0 | Safety margin inside half range |
| `HEAVY_STATIONARY_MIN_BENEFIT` | 0.15 | Min expected extra hits to hold still for Heavy +1 |
| `HEAVY_STATIONARY_OBJ_OVERRIDE_SCORE` | 10.0 | Objective priority that overrides a Heavy hold |
| `MELEE_AGGRESSION_ADVANCE_THRESHOLD_INCHES` | 20 | Chase cap: seekers ignore enemies farther than this (never below the unit's move+advance+charge reach) and follow their objective assignment instead |
| `SCREEN_CHEAP_UNIT_POINTS` | 100 | Units at/below this cost are screening candidates |
| `SCREEN_SCORE_BASE` | 8.0 | Base score of a screening assignment |
| `CORRIDOR_BLOCK_SCORE_BASE` | 7.0 | Base score of a corridor-block assignment |
| `CORRIDOR_BLOCK_POSITION_RATIO` | 0.55 | Blocker placed this fraction of the way from objective toward enemy |
| `CORRIDOR_BLOCK_MAX_POSITIONS` | 4 | Max simultaneous corridor blocks |
| `FIX_MOVE_COVER` | 0 | Behaviour switch (on at ≥ 0.5): a normal move toward the plan objective picks an end spot, anywhere on the disc the move can reach (a full-length move slides along it), that leaves the unit Hidden (11e 13.09, light or dense area per the errata) or in cover (13.08, -1 BS) from every enemy shooter that can reach it next turn. Hidden is credited only where the unit has no target in range or F002 would hold fire (the shot on offer, in F002's own currency, is worth less than the forfeit — chip shots only); otherwise the spot counts as cover. Fire tag: one `[FIX_MOVE_COVER] <unit> end spot old=… new=…` line per changed move, printed with the move it describes (none for a move `FIX_INDIRECT_STATIONARY` then turns into a hold). 0 = previous behaviour. Opt-in: `40k/tests/bench_profiles/move_cover_on.json` (pairs it with `HIDDEN_FORFEIT_PENALTY` 3.0, keeps `MOVE_COVER_PLAN_WEIGHT` at 0); exam `mv05_end_the_move_hidden` |
| `MOVE_COVER_MAX_LOSS_INCHES` | 2.0 | Most objective progress (gap to its range, terrain-area aware) a cover / Hidden spot may give up vs the straight move; the spot also may not add a turn-to-reach or lose control range |
| `MOVE_COVER_HIDDEN_WEIGHT` | 3.0 | Points for being Hidden next turn from the whole threatening shot volume (scaled by the blinded share; 1 pt ≈ 1" of progress) |
| `MOVE_COVER_COVER_WEIGHT` | 1.5 | Points for the Benefit of Cover against the whole cover-respecting shot volume (TORRENT / [IGNORES COVER] / PSYCHIC excluded) |
| `MOVE_COVER_NFV_FACTOR` | 0.5 | Share of the cover points when cover rests only on "not fully visible" (judged from the shooter's current spot) rather than every model inside a terrain area |
| `MOVE_COVER_LOSS_WEIGHT` | 1.0 | Points subtracted per inch of objective progress the spot gives up |
| `MOVE_COVER_THREAT_WEIGHT` | 1.0 | Points subtracted per point of threat (`_evaluate_position_threat`) the spot adds vs the straight end |
| `MOVE_COVER_MIN_GAIN` | 0.5 | Net points a spot must beat the straight end by — at selection and again on the destinations the mover returns |
| `MOVE_COVER_PLAN_WEIGHT` | 0 | Plan prior: share of the cheap spot value at the planner's estimated destination added as `cover_gain` (0 = executor stage only, the v1 setting even with the flag on; its Hidden half is dropped while `WEIGHT_HIDDEN_GAINED` > 0). Not fire-gated: it moves the global greedy assignment (keeper pick, OC-need capture, OBJ-ASSIGN-1 swaps compare scores across units), which no per-unit tag can attribute, so it has no `[FIX_MOVE_COVER]` line — only a `MOVE_COVER plan prior` debug line. Set it > 0 for exploratory runs only, until an assignment-level counterfactual tag exists |
| `MOVE_COVER_FAN_INCHES` | 2.0 | Radius of the heading fan round the straight end (proposes "behind terrain" spots) |
| `MOVE_COVER_MAX_SHOOTERS` | 4 | (int) Reaching enemy units, heaviest shot volume first, that get the sight-line checks (Gone to Ground, not fully visible) per spot; every reaching unit — at the spot or at the straight end — still counts in the share and the note's "of N", judged on distance and in-area cover alone (-1 = no cap) |
| `MOVE_COVER_MAX_CANDIDATES` | 12 | (int) Spots that pass the cheap screens and get the full engine-predicate evaluation, nearest the straight end first |
| `MOVE_COVER_FAN_HEADINGS` | 8 | (int) Headings in the fan (0 = terrain-area spots only) |
| `MOVE_COVER_MAX_GTG_CHECKS` | 64 | (int) Gone-to-Ground (13.11.01, -3" detection behind dense walls) engine checks per search; pairs past the budget count as visible (no credit) |
| `FIX_MOVE_FOR_SHOT` | 0 | Behaviour switch (on at ≥ 0.5): a unit with ranged weapons making a normal move toward its plan objective, whose returned destinations leave it with no eligible ranged target (11e 04.02 — the engine's own `RulesEngine.get_eligible_targets` on a hypothetical board, which must have said no about every enemy the move could reach before a spot is kept: range, 13.10/13.11 sight lines, 13.09 Hidden detection with Gone to Ground, Lone Operative, Psychic Veil; the target side is the enemy's whole Attached unit, so a leader standing nearer than its bodyguard counts, 19.01), re-aims the same move at a spot that has one (a sight line round terrain, inside a Hidden target's detection range, into weapon range) and keeps it only if the destinations the mover returns still do; otherwise the flag-off move stands. Same objective and plan action; never for an Advance or a planned charge; a kept `FIX_MOVE_COVER` spot wins. Fire tag: one `[FIX_MOVE_FOR_SHOT] <unit> end spot old=no_shot new=<target> …` line per changed move, printed with the move it describes (none for a move `FIX_INDIRECT_STATIONARY` then turns into a hold). 0 = previous behaviour. Opt-in: `40k/tests/bench_profiles/move_for_shot_on.json`; exam `mv06_move_for_a_shot` |
| `MOVE_FOR_SHOT_MAX_LOSS_INCHES` | 3.0 | Most objective progress (gap to its range, terrain-area aware) a shot spot may give up vs the flag-off destinations; the spot also may not add a turn-to-reach, lose control range, or put less OC within range of the objective than the flag-off move (14.02 sums every in-range model's OC, attached characters included — a spot that keeps one model on and walks the rest off is refused) (checked at selection and again on the returned destinations) |
| `MOVE_FOR_SHOT_LOSS_TIE_INCHES` | 0.5 | Shot spots within this much of the least loss count as tied; the tie goes to the higher expected damage, then nearest the straight end |
| `MOVE_FOR_SHOT_MIN_EV` | 0.1 | Expected damage (sum of `_estimate_weapon_damage` over the best eligible target's in-range weapons, fired from the spot) a spot needs to count — no zero-damage "shots" |
| `MOVE_FOR_SHOT_RING_INCHES` | 2.0 | Radius of the 8-heading sidestep ring round the straight end (0 = no ring) |
| `MOVE_FOR_SHOT_FAN_STEP_DEG` | 22.5 | Heading step of the -90..+90° fan round the move's aim, at full and 0.75 length (0 = no fan) |
| `MOVE_FOR_SHOT_STEP_MARGIN_INCHES` | 0.5 | How far inside the binding gate (weapon range, a Hidden model's detection range with and without Gone to Ground, Lone Operative range, Psychic Veil 18") an aimed closing step goes |
| `MOVE_FOR_SHOT_PROBES` | 8 | (int) Engine eligibility calls per search, besides the trigger and the re-check (0 = never probes, so never fires); once a shot is found, a spot that could not beat it even with every weapon firing is not probed |
| `MOVE_FOR_SHOT_MAX_TARGETS` | 3 | (int) Reachable enemy units aimed at and probed per spot — most reachable from the straight end first, then the most valuable |
| `MOVE_FOR_SHOT_MAX_PAIR_CHECKS` | 1600 | (int) Cost cap: (bodyguard model × target model) pairs within reach the probes may hand the engine, summed over the search; a probe that would pass it is skipped (-1 = no cap). Never binds on Custodes; caps Ork mob-vs-mob at about 4 probes |
| `FIX_MOVE_FOR_CHARGE` | 0 | Behaviour switch (on at ≥ 0.5): a melee unit that plans to charge this turn — an ATTACK assignment (melee chase gate) making a Normal move, or a MOVE assignment with a planned charge (T7-23) and a real melee weapon — chooses where that Normal move ends by the charge it leaves. 11e 11.02 / 11.04: targets are selected after the 2D6 roll, within 12" and within the (modified, never above 12) roll, base to base — so the stage aims by the edge gap of the closest pair of models (`_charge_roll_needed`), not the centroids; prices each spot as an option over the roll (per roll the best target in reach — a spot within reach of two targets is worth more), each target on its nearest clean lane (no enemy base across the path 03.01 — AIRCRAFT excepted, 23.02 —, no non-target enemy within engagement range of the contact point 11.04, room for the base, no uncrossable dense feature 13.06), always led by a bodyguard model: the AI's own charge move moves only the bodyguard (the engine moves an attached leader by its delta afterwards), so an attached CHARACTER makes targets selectable (12" / within the roll, from the whole Attached unit) but never carries the move, and a leader standing on the contact point is priced as the detour the charge move makes round it; an AIRCRAFT is a target only for a FLYING charger (23.04); stops every proposal just outside engagement range (09.05); in objective mode trades the odds against progress and may drop a T7-23 steer that buys too little. Re-checked on the destinations the mover returns (a lost gain keeps the flag-off move). Never for an Advance (09.06) or a unit `RulesEngine.eligible_to_charge` refuses. Fire tag: one `[FIX_MOVE_FOR_CHARGE] <unit> charge spot mode=… kind=… target=… old=<k>+/<p>% new=<k>+/<p>% …` line per changed move. 0 = previous behaviour. Opt-in: `40k/tests/bench_profiles/move_for_charge_on.json`; exam `mv07_stage_the_charge` |
| `MOVE_FOR_CHARGE_ODDS_WEIGHT` | 10.0 | Points per 1.0 of normalised charge option value (Σ over the 2D6 roll of P(roll) × the best reachable target's value, / the most valuable target's): one certain charge on the best target = 10 pts, i.e. 1 pt per 10% odds |
| `MOVE_FOR_CHARGE_LOSS_WEIGHT` | 1.0 | Objective mode: points per inch of objective progress (terrain-area-aware gap to the objective's range) given up against the straight objective move, beyond what the flag-off move gave up (a spot that gives up less than a T7-23 steer earns it back) |
| `MOVE_FOR_CHARGE_MAX_LOSS_INCHES` | 3.0 | Objective mode: most progress a spot may give up against the straight objective move; it also may not add a turn-to-reach, lose control range or put less OC within the objective's range (14.02). Checked at selection and again on the returned destinations |
| `MOVE_FOR_CHARGE_MIN_GAIN` | 0.5 | Net points a spot must beat the flag-off destinations by (0.5 admits every one-step need improvement from a 4+ up, +5.5% or more, except 12+ → 11+). A per-spot screen, like `MOVE_FOR_CHARGE_MIN_ODDS`: the pick is the best spot that passes both |
| `MOVE_FOR_CHARGE_MIN_ODDS` | 0.25 | "Realistic charge reach": a spot that steers toward a charge must leave at least this normalised option value (≈ a 9+ on 2D6, 27.8%); a progress-only pick (dropping or easing a T7-23 steer) is exempt. Screened per spot: a higher-gain spot under the floor never vetoes one that clears it |
| `MOVE_FOR_CHARGE_ODDS_TIE` | 0.03 | Attack mode: the announced target's own odds may not drop by more than this, so backups can never pull an ATTACK <X> unit off X |
| `MOVE_FOR_CHARGE_BACKUP_WEIGHT` | 1.0 | Points per other enemy unit in reach, scaled by its odds × clamp((V − H) / V_ref, 0, 1) (V = 2 × the unit's expected melee damage on it, H = 2 × what it deals back) — the "prefer a spot within reach of more than one target" term |
| `MOVE_FOR_CHARGE_BACKUP_MIN_ODDS` | 0.42 | A backup counts as "within reach" for the note's "also within reach of …" and the n_reach diagnostic at ≈ an 8+ or better (not used in the gain) |
| `MOVE_FOR_CHARGE_ER_MARGIN_INCHES` | 0.1 | Proposals stop this far outside engagement range (2") of every enemy model, on circumscribed radii, so the mover and the engine never see a model in engagement range after the move (09.05) |
| `MOVE_FOR_CHARGE_CONTACT_INSET_INCHES` | 0.1 | A lane's lead model ends this far inside engagement range of its target model; the non-target engagement and room checks are made at that contact point |
| `MOVE_FOR_CHARGE_FAN_STEP_DEG` | 15.0 | Heading step of the fan round the planned target's aimed line (from the closest member to the target's nearest model) |
| `MOVE_FOR_CHARGE_FAN_STEPS` | 3 | (int) Fan headings per side (±15/30/45°); 0 = aimed lines and blends only |
| `MOVE_FOR_CHARGE_MAX_TARGETS` | 3 | (int) Enemy units priced per spot: the planned one plus the nearest others whose edge gap now is within 12" + M |
| `MOVE_FOR_CHARGE_MAX_CANDIDATES` | 16 | (int) Spots that pass every screen and get the full lane and odds evaluation, in proposal order (aimed lines, objective blends, fan, multi-target midpoints) |
| `MOVE_FOR_CHARGE_LANE_PAIRS` | 3 | (int) Closest (bodyguard model × target model) pairs tried, nearest first, for a clean lane per target; none clean = out of reach from that spot |
| `MOVE_FOR_CHARGE_MIN_TARGET_VALUE` | 0.5 | Floor on a target's value V = max(`CHARGE_MELEE_DAMAGE_WEIGHT` × expected melee damage, this): a target the unit can barely hurt still counts as a lock, and normalisation never divides by 0 |
| `FIX_INDIRECT_STATIONARY` | 0 | Behaviour switch (on at ≥ 0.5, 11e only): a unit whose nominal ranged output is mainly [INDIRECT FIRE] and whose plan is a Normal move (support moves included; never an Advance, a planned charge or a rollout override) compares, AFTER the mover and every shaping stage have settled the move, next Shooting phase's damage if it Remains Stationary with the damage after that move plus what the move buys on the objectives — one points ledger (points per wound, the T7-24 rule), each side summing to its score — and Remains Stationary ("X remains stationary to arm its indirect fire at Y (…)") when staying wins by `INDIRECT_STATIONARY_MIN_MARGIN`. 11e 10.07: an [INDIRECT FIRE] attack at a target none of the unit's models can see gives it the benefit of cover (13.08), cannot re-roll its hit roll and fails on an unmodified 1-5 — only 1-3 if the unit Remained Stationary this turn (09.04: any move, even 1", loses it) and a friendly unit can see the target. Both options are priced with the engine's own `RulesEngine.preview_attack` on hypothetical boards (the unit unmoved with `remained_stationary`, or at the returned destinations with `moved_max_inches`), so the fail band, the indirect cover, the BS clamp at 6+ (02.02.01: a BS 5+ battery gains nothing, every Ork Lobba) and [HEAVY] (24.16, priced as the engine applies it, never changed here) are the engine's. STAY: `ind_stay_shot`. MOVE: `ind_move_shot` (0 when F002 would hold fire there), `ind_move_objective`, `ind_move_progress`. It stays only when the stay option's best target is one it cannot see, the engine's band there is 1-3 (`RulesEngine._indirect_hit_fail_band_11e`), and a RELIABLE friendly unit sees that target — one on the battlefield (01.02.04 as errata'd: not embarked, in Strategic Reserves or undeployed, even when an engine path such as Acrobatic Escape left it its old positions) that has acted this phase, is planned to hold, or has no movement action (see `INDIRECT_STATIONARY_TRUST_UNMOVED`). The stay option is priced as only those reliable spotters leave the board (the engine's band counts every friendly unit): every other friendly unit is marked off a copy of it unless it is within Engagement Range of an enemy, whose engagement still decides 04.02 / 17.03 / [BLAST] — so a target only an unreliable unit sees is priced at 1-5 and never outbids one a reliable spotter arms, and adding such a unit never changes the decision. Only shots the Shooting phase may take are priced or ranked: no [BLAST] weapon at a unit engaged with one of ours (17.03 as errata'd: `get_eligible_targets` keeps an engaged MONSTER/VEHICLE for every weapon, but `validate_shoot` and the SHOOT sanitizer's LAST-1 check, `_ai_blast_target_allowed`, reject it). The plan's objective is then not booked as incoming OC (`_ai_indirect_hold`); the plan card still says MOVE and the thinking steps explain the stay. Read only for units that carry an [INDIRECT FIRE] weapon (not [ONE SHOT]): armies without one — every 2000-pt bench fixture — never read the flag and play byte-identically even with it on, so the V2-1 fire gate needs a fixture with real artillery (11e Whirlwind / Arcus). Not priced: survival (a cover / Hidden spot or threat dodge the move would reach), spotters that move after the battery (move order is OFF-19's), the shooting phase spending the shot on another target (its target choice ignores the 10.07 band: after a stay that arms a lower-value target, it can fire at a higher-value one at 1-5). Fire tag: one `[FIX_INDIRECT_STATIONARY] <unit> move_choice old=move new=stay stay=… move=… target=<id> spotter=<id> ev=<stay>/<move>` line per flipped move. 0 = previous behaviour (byte-identical play). Opt-in: `40k/tests/bench_profiles/indirect_stationary_on.json`; exam `mv09_arm_the_indirect_battery` |
| `INDIRECT_STATIONARY_MIN_SHARE` | 0.5 | Battery gate: share of the unit's nominal ranged output (bodyguard + attached characters: average attacks × carriers × average damage × P(hit at its BS), [TORRENT] P = 1; [ONE SHOT] weapons left out of both sides) its [INDIRECT FIRE] weapons must carry |
| `INDIRECT_STATIONARY_MIN_MARGIN` | 5.0 | Points staying must beat moving by; ties and near-ties keep the move |
| `INDIRECT_STATIONARY_SHOT_WEIGHT` | 1.0 | `ind_stay_shot` / `ind_move_shot` = this × the expected wounds next Shooting phase on that option's best target (`preview_attack` expected_effective_damage summed over the weapons `get_eligible_targets` lists for it there, capped at the wounds its Attached unit has left) × its points per wound |
| `INDIRECT_STATIONARY_OBJECTIVE_PTS` | 25.0 | `ind_move_objective` when the move puts OC on an objective (14.02: every in-range model, attached characters included) and that improves who controls it (behind → tied/ahead, tied → ahead); mirrors `STAY_ENGAGED_LEAVE_OBJECTIVE_PTS` |
| `INDIRECT_STATIONARY_PROGRESS_PTS` | 1.0 | `ind_move_progress` per inch the move closes toward its assigned objective's range (terrain-area-aware gap now − after the move; 0 with no objective) |
| `INDIRECT_STATIONARY_MAX_TARGETS` | 4 | (int) Enemy units priced per option (bounds the `preview_attack` calls): the most valuable by a cheap prior, range-checked `_estimate_weapon_damage` from either spot × points per wound. 0 = never prices, never fires |
| `INDIRECT_STATIONARY_TRUST_UNMOVED` | 0 | 0 = only RELIABLE spotters count (on the battlefield, and acted this phase, planned to hold, or no movement action): a unit that has yet to move neither names the spotter nor arms a target in the stay option's pricing; ≥ 0.5 = a friendly unit that has yet to move counts too (it may walk out of sight before the Shooting phase) |

### Multi-phase planning (movement → shooting → charge)

| Parameter | Default | Meaning |
|---|---|---|
| `PHASE_PLAN_CHARGE_INTENT_THRESHOLD` | 3.0 | Min charge score for a unit to be flagged "intends to charge" |
| `PHASE_PLAN_CHARGE_LANE_BONUS` | 3.0 | Movement bonus toward the planned charge target |
| `PHASE_PLAN_SHOOTING_LANE_BONUS` | 2.0 | Movement bonus for keeping planned shooting lanes |
| `PHASE_PLAN_LOCK_SHOOTER_BONUS` | 3.0 | Charge bonus for locking dangerous enemy shooters in melee |
| `PHASE_PLAN_DONT_SHOOT_CHARGE_TARGET` | 0.5 | Multiplier on shooting value of targets we plan to charge |

### Shooting — target selection

| Parameter | Default | Meaning |
|---|---|---|
| `MACRO_POINTS_WEIGHT` | 0.008 | Target value per point of unit cost |
| `MACRO_RANGED_OUTPUT_WEIGHT` | 0.15 | Target value per expected ranged damage it deals |
| `MACRO_MELEE_OUTPUT_WEIGHT` | 0.10 | Target value per expected melee damage it deals |
| `MACRO_ABILITY_VALUE_WEIGHT` | 0.5 | Target value per ability multiplier above 1.0 |
| `MACRO_SURVIVABILITY_DISCOUNT` | 0.15 | Value discount per defensive multiplier (tough = inefficient to shoot) |
| `MACRO_OC_ON_OBJECTIVE_WEIGHT` | 0.5 | Target value per OC while it sits on an objective |
| `MACRO_OC_NEAR_OBJECTIVE_WEIGHT` | 0.2 | Target value per OC while near an objective |
| `MACRO_LEADER_BUFF_BONUS` | 1.5 | Multiplier for leaders buffing their unit |
| `MICRO_MARGINAL_KILL_BONUS` | 2.5 | Bonus when an assignment pushes damage past the kill threshold |
| `MICRO_OVERKILL_DECAY` | 0.35 | Value of damage beyond the kill threshold |
| `MICRO_MODEL_KILL_VALUE` | 0.6 | Value of killing models (vs 1.0 for wiping the unit) |
| `OVERKILL_TOLERANCE` | 1.15 | Allowed overkill before weapons redirect |
| `LOW_HEALTH_BONUS` | 1.5 | Bonus for finishing targets below half health |
| `EFFICIENCY_PERFECT_MATCH` | 1.4 | Anti-tank vs vehicle, anti-infantry vs horde |
| `EFFICIENCY_GOOD_MATCH` | 1.15 | Decent weapon-target pairing |
| `EFFICIENCY_POOR_MATCH` | 0.6 | Wrong tool (anti-infantry vs vehicle…) |
| `DAMAGE_WASTE_PENALTY_HEAVY` | 0.4 | D3+ weapons into 1-wound models |
| `DAMAGE_WASTE_PENALTY_MODERATE` | 0.7 | D2 weapons into 1-wound models |
| `ANTI_KEYWORD_BONUS` | 1.5 | Weapon has ANTI-X matching the target |
| `ANTI_TANK_STRENGTH_THRESHOLD` | 7 | S at/above ⇒ weapon classed anti-tank |
| `ANTI_TANK_AP_THRESHOLD` | 2 | AP at/above ⇒ weapon classed anti-tank |
| `ANTI_INFANTRY_STRENGTH_CAP` | 5 | S at/below ⇒ weapon classed anti-infantry |

### Trade, tempo & round strategy

| Parameter | Default | Meaning |
|---|---|---|
| `TRADE_PPW_WEIGHT` | 0.25 | Weight of points-per-wound trade efficiency |
| `TRADE_FAVORABLE_BONUS` | 1.3 | Max bonus for trading up |
| `TRADE_UNFAVORABLE_PENALTY` | 0.7 | Min multiplier for trading down |
| `TEMPO_VP_DIFF_WEIGHT` | 0.1 | Aggression shift per VP of difference |
| `TEMPO_BEHIND_AGGRESSION_BOOST` | 1.5 | Max aggression boost when losing |
| `TEMPO_AHEAD_CONSERVATION` | 0.8 | Conservatism when winning |
| `TEMPO_DESPERATION_ROUND` | 4 | Round at which being behind triggers desperation |
| `TEMPO_DESPERATION_MULTIPLIER` | 1.8 | Desperation aggression multiplier |
| `TEMPO_CHARGE_THRESHOLD_REDUCTION` | 0.4 | Charge-threshold cut when desperate |
| `TEMPO_MAX_ROUNDS` | 5 | Game length assumption |
| `STRATEGY_EARLY_AGGRESSION` | 1.3 | R1-2 kill-seeking multiplier |
| `STRATEGY_EARLY_OBJECTIVE` | 0.95 | R1-2 objective-weight multiplier |
| `STRATEGY_EARLY_SURVIVAL` | 0.7 | R1-2 threat-avoidance multiplier (accept risk) |
| `STRATEGY_EARLY_CHARGE` | 0.5 | R1-2 charge-threshold multiplier (charge more) |
| `STRATEGY_LATE_AGGRESSION` | 0.7 | R4-5 kill-seeking multiplier |
| `STRATEGY_LATE_OBJECTIVE` | 1.6 | R4-5 objective-weight multiplier |
| `STRATEGY_LATE_SURVIVAL` | 1.4 | R4-5 threat-avoidance multiplier |
| `STRATEGY_LATE_CHARGE` | 1.3 | R4-5 charge-threshold multiplier (charge less) |
| `STRATEGY_LATE_CHARGE_ON_OBJ_BONUS` | 1.5 | R4-5 bonus for charges that land on objectives |
| `STRATEGY_LATE_OBJ_TARGET_BONUS` | 1.3 | R4-5 bonus for shooting units on objectives |

### Faction personality

| Parameter | Default | Meaning |
|---|---|---|
| `FACTION_AGGRESSION_DEFAULT` | 1.0 | Baseline aggression |
| `FACTION_AGGRESSION_ORKS` | 1.2 | Orks: melee aggression. Benchmark-tuned down from 1.8 (2026-07-10): at ≥1.5 every melee-capable unit chased enemies instead of holding objectives — see `tests/bench_baselines/2026-07-10_ork_discipline_ab.md` |
| `FACTION_AGGRESSION_CUSTODES` | 1.5 | Custodes: elite melee aggression |
| `FACTION_AGGRESSION_WORLD_EATERS` | 2.0 | World Eaters |
| `FACTION_AGGRESSION_KHORNE` | 1.8 | Khorne daemons |

Faction aggression shapes HOW aggressively melee seekers behave (hold-leave
distance limits, home-objective stay bonuses, round-1 setup moves) — but as of
2026-07-10 it no longer decides WHO seeks: only melee-*focused* units leave
their objective assignments to hunt (see
`tests/bench_baselines/2026-07-10_ork_discipline_ab.md`), and all seekers
respect the `MELEE_AGGRESSION_ADVANCE_THRESHOLD_INCHES` chase cap.

### Engaged units & survival

| Parameter | Default | Meaning |
|---|---|---|
| `SURVIVAL_LETHAL_THRESHOLD` | 0.75 | Expected melee damage ≥ 75% of wounds ⇒ likely destroyed, fall back |
| `SURVIVAL_SEVERE_THRESHOLD` | 0.5 | ≥ 50% ⇒ badly hurt |
| `SURVIVAL_HOLD_BONUS` | 1.5 | Read only with `FIX_STAY_ENGAGED` on: `stay_survival` = this × the unit's points per wound when the survival check recommends "hold" (expected Fight-phase damage < 25% of its wounds) |
| `SURVIVAL_FALL_BACK_BONUS` | 2.0 | Read only with `FIX_STAY_ENGAGED` on: `leave_survival` = this × the unit's points per wound when the survival check recommends "fall_back" (lethal or severe) |
| `FIX_STAY_ENGAGED` | 0 | Behaviour switch (on at ≥ 0.5, 11e only): an engaged unit that would fall back by default — off its objectives, or on one where leaving would not change who controls it (the OC rules keep the other cases) — compares staying engaged with falling back on one points ledger (`engaged_choice` record; points per wound, the T7-24 rule) and stays (REMAIN_STATIONARY "X stays engaged with Y (…)") when STAY beats LEAVE by `STAY_ENGAGED_MIN_MARGIN`. STAY: `stay_fight` (damage it deals in our own Fight phase), `stay_kill`, `stay_loss` (the strike-back, cut by our first casualties × the chance we strike first — 12.04: 0 when the enemy has Fights First and we do not; Resolve Remaining Combats starts with the player who did NOT make the last Fights First pick, so with more eligible Fights First units than the enemy — every successful charge this turn has it, 11.04: our engaged Fights First units plus each unengaged phase-plan charger at its post-move charge odds — the enemy picks first there; and with S of our units in separate combats of the same step we strike first in ceil(S/2) of them; record context `p_strike_first`, `fights_first_ours` / `_planned` / `_theirs`, `contested_combats`), `stay_cq_shoot` (MONSTER/VEHICLE close-quarters shooting, 10.06), `stay_lock` (a phase-plan lock target kept from shooting next turn, an objective holder / action performer pinned — 04.02, 09.07, 16.01), `stay_shield` (enemy shooting avoided while still engaged, 04.02; 17.03 + errata), `stay_survival`. LEAVE, priced on the fall-back generator's own destinations: `leave_fb_shoot` / `leave_fb_charge` (Fall Back and X), `leave_objective` (14.02), `leave_free_target` (04.02: an engaged non-MONSTER/VEHICLE enemy that no other unit of ours keeps engaged becomes a target for our other shooters — see `STAY_ENGAGED_FREE_TARGET_WEIGHT`; no charge half, an engaged unit is still a legal charge target, 11.04; overlaps catalogue intent COO-05, which should reuse this term), `leave_hazard` / `leave_shock` (Desperate Escape when battle-shocked or forced by an enemy rule — Commentary 09.07.01 — or when the way out crosses enemy models where the engine refuses an Ordered Retreat through them: EA-08, Wave A, detected by its `MoveType.path_crosses_enemy_models`; until it lands AIPlayer's plain BEGIN_FALL_BACK is an Ordered Retreat that the engine lets through enemy models with no hazard roll, so a crossing costs nothing and the record / notes / steps say Ordered Retreat. The crossing test mirrors EA-08's shape-aware sweep: base contact is not moving through, an oval's real outline counts, attached CHARACTERs ride the first bodyguard model's delta, and FLY / Grapnel Launchers / CALISTUS ka'tah / SUPER-HEAVY WALKER keep the engine's exemptions. Hazard rolls: one per model the engine rolls for — the bodyguard's today, the whole Attached unit once EA-36 lands, read from `FallBackMove.attached_unit_hazard_view`; the unit test checks the count against `FallBackMove.before_moving`), `leave_survival`. Ranged estimates use the shared weapon-keyword rules (`_apply_weapon_keyword_modifiers`: [TORRENT] auto-hits with no -1, [RAPID FIRE] / [MELTA] at half range, [SUSTAINED HITS], [LETHAL HITS], [ANTI-X], [DEVASTATING WOUNDS]). The action line names the fight only when it wins (it wipes them out, or deals more than it takes back); a stay that only beats a costlier fall back says "falling back would cost more: its Desperate Escape makes N hazard roll(s)…". One horizon (this turn's fight, next enemy turn's shooting). Not priced: Hidden or cover at the fall-back spot; the casualties an enemy that strikes first inflicts also cutting our own attacks; `leave_free_target`'s other-target baseline is range-only (no sight line), which can only understate the gain. Fire tag: one `[FIX_STAY_ENGAGED] <unit> engaged_choice old=fall_back new=stay stay=… leave=… top=<term>` line per flipped decision (`top` is `leave_hazard` / `leave_shock` when the reason is what leaving costs). 0 = previous behaviour (byte-identical play). Opt-in: `40k/tests/bench_profiles/stay_engaged_on.json`; exam `mv08_stay_engaged_to_finish` |
| `STAY_ENGAGED_MIN_MARGIN` | 5.0 | Points STAY must beat LEAVE by; ties and near-ties keep the old fall back |
| `STAY_ENGAGED_FIGHT_WEIGHT` | 1.0 | `stay_fight` = this × min(expected melee damage of the unit + its attached characters, the engaged enemy's wounds left) × the enemy's points per wound |
| `STAY_ENGAGED_KILL_BONUS_FRAC` | 0.25 | `stay_kill` = this × the engaged enemy's points when the expected fight (+ counted close-quarters shooting) reaches its remaining wounds |
| `STAY_ENGAGED_LOSS_WEIGHT` | 1.0 | Points per point-value of our own wounds expected lost: the strike-back (`stay_loss`) and Desperate Escape mortal wounds (`leave_hazard`) |
| `STAY_ENGAGED_STRIKE_FIRST` | 1.0 | Share of our expected casualties on the focused enemy taken off its strike-back (12.04), × the chance we strike first (`p_strike_first`: 0 when it has Fights First and we do not; the 12.04 hand-over and the shared-step alternation in the `FIX_STAY_ENGAGED` row). 0 = the raw T7-27 survival estimate |
| `STAY_ENGAGED_LOCK_WEIGHT` | 1.0 | `stay_lock` per point-value of the shooting a phase-plan lock target is denied next turn (`_estimate_unit_ranged_strength` × our army's points per wound × survival odds) |
| `STAY_ENGAGED_LOCK_MV_FACTOR` | 0.25 | Share of a MONSTER/VEHICLE lock target's shooting denied (it keeps close-quarters shooting, 10.06); a target with Fall Back and Shoot is denied 0 |
| `STAY_ENGAGED_LOCK_HOLDER_FRAC` | 0.15 | Share of an engaged enemy unit's points for pinning it while it holds an objective or performs an action (an engaged unit cannot start an action, 16.01; not TITANIC) |
| `STAY_ENGAGED_SHIELD_WEIGHT` | 0.5 | `stay_shield`: share of the reaching enemy fire (enemy units within range + Move, not engaged themselves unless MONSTER/VEHICLE) assumed aimed at this unit |
| `STAY_ENGAGED_ENEMY_HOLDS` | 0.5 | Prior that the engaged enemy stays engaged through its own Movement phase (the shield needs it); a prior, not a measurement |
| `STAY_ENGAGED_CQ_MV_WEIGHT` | 1.0 | `stay_cq_shoot` for a MONSTER/VEHICLE: the better of the engaged unit (no [BLAST], -1 to hit except [CLOSE-QUARTERS]) or the best other target in range at -1 (one sight-line check). The AI's shooting phase keeps every ranged weapon of an engaged MONSTER/VEHICLE (`tests/unit/test_ai_pistol_engagement.gd`) |
| `STAY_ENGAGED_CQ_WEIGHT` | 0.0 | The same for a non-MONSTER/VEHICLE unit's [PISTOL]/[CLOSE-QUARTERS] weapons at the engaged unit. Ships 0: the AI's engaged-pistol filters read `weapon.keywords` while army data stores `pistol` in `special_rules`, and measure a 1" engagement range where 11e uses 2", so the shooting phase would not take this value |
| `STAY_ENGAGED_FB_X_WEIGHT` | 1.0 | Points per point-value of what a Fall Back and Shoot / Charge unit still does after falling back: the best shot from the destinations (sight line on the moved unit), or P(2D6 ≥ the gap the fall back leaves) × the fight it would win as the charger (11.04) |
| `STAY_ENGAGED_LEAVE_OBJECTIVE_PTS` | 25.0 | `leave_objective` when the fall-back destinations put a model on an objective the unit is not on and its OC there improves the level of control (behind → tied/ahead, tied → ahead) |
| `STAY_ENGAGED_SHOCK_COST_FRAC` | 0.1 | `leave_shock` = this × our points × P(fail) of the battle-shock roll a Desperate Escape forces on a unit not already battle-shocked (09.07; 01.07: OC "-", no actions) |
| `STAY_ENGAGED_FREE_TARGET_WEIGHT` | 1.0 | `leave_free_target` = this × Σ over our other shooters (alive, deployed, unengaged, not Advanced / Fallen Back, able to shoot) that reach the freed enemy now and have a sight line to it (one check) of max(0, min(expected damage on it, its wounds) × its points per wound − the best other target their guns reach now, range only), capped at its wounds left after our own Fall Back and Shoot / Charge damage, + `STAY_ENGAGED_KILL_BONUS_FRAC` × its points when that fire alone is expected to destroy it. 0 = the term is off |

### Secondary-mission positioning

| Parameter | Default | Meaning |
|---|---|---|
| `SECONDARY_OBJECTIVE_ZONE_BONUS` | 3.5 | Objectives in zones a secondary card pays for |
| `SECONDARY_POSITIONAL_BONUS` | 4.0 | Moving toward secondary-specific positions |
| `SECONDARY_KILL_PROXIMITY_BONUS` | 2.0 | Positioning near secondary kill targets |
| `SECONDARY_SPREAD_BONUS` | 6.0 | Spreading into uncovered table quarters (Engage on All Fronts) |
| `SECONDARY_CENTER_BONUS` | 3.5 | Area Denial: center positioning |
| `SECONDARY_ENEMY_ZONE_PUSH_BONUS` | 7.0 | Behind Enemy Lines: pushing into the enemy deployment zone |

### Reserves, embarkation and disembarkation (A4, 2026-08-07)

These three scorers between them held 46 bare literals — the largest single
block of scoring arithmetic no profile, rule or optimiser could reach
(`research/audit_findings_2026-08-07.md` F-02). Reserves sizing has already
lost a benchmark game on its own (950 pts held back;
`docs/AI_REVIEW_2026-07-11.md` §2.4), so the block being untunable was not a
theoretical problem. Promotion kept every default **exactly** as it was, which
`determinism_check.py` verifies as byte-identical play.

### Reserves — deep strike

| Parameter | Default | Meaning |
|---|---|---|
| `RESERVES_DS_LONG_RANGE` | 1.5 | deep strike: long-range shooter |
| `RESERVES_DS_MID_RANGE` | 3.5 | deep strike: shooter with max range <= 24" |
| `RESERVES_DS_MIXED_MELEE` | 6 | deep strike: mixed melee/ranged unit |
| `RESERVES_DS_POINTS_CAP` | 3 | deep strike: cap on the points-value bonus |
| `RESERVES_DS_POINTS_DIVISOR` | 100 | deep strike: points per unit of value bonus |
| `RESERVES_DS_PURE_MELEE` | 8 | deep strike: pure-melee unit |
| `RESERVES_DS_SHORT_RANGE` | 5 | deep strike: shooter with max range <= 18" |

### Reserves — strategic reserves

| Parameter | Default | Meaning |
|---|---|---|
| `RESERVES_SR_MIXED_MELEE` | 2.5 | strategic reserves: mixed melee/ranged unit |
| `RESERVES_SR_MOVE_10` | 1.5 | strategic reserves: unit with Move >= 10" |
| `RESERVES_SR_MOVE_12` | 2 | strategic reserves: unit with Move >= 12" |
| `RESERVES_SR_MOVE_8` | 0.5 | strategic reserves: unit with Move >= 8" |
| `RESERVES_SR_POINTS_CAP` | 1.5 | strategic reserves: cap on the melee points bonus |
| `RESERVES_SR_POINTS_DIVISOR` | 200 | strategic reserves: points per unit of melee value bonus |
| `RESERVES_SR_PURE_MELEE` | 4 | strategic reserves: pure-melee unit |
| `RESERVES_SR_RANGED` | 0.5 | strategic reserves: any other ranged unit |
| `RESERVES_SR_SHORT_RANGE` | 2 | strategic reserves: shooter with max range <= 18" |

### Reserves — universal modifiers

| Parameter | Default | Meaning |
|---|---|---|
| `RESERVES_CHEAP_SCREEN_PENALTY` | 0.5 | cheap non-Deep-Strike unit (better as a screen) |
| `RESERVES_LONG_RANGE_PENALTY` | 0.3 | ranged-only unit with max range >= 36" |
| `RESERVES_VEHICLE_MELEE_PENALTY` | 0.7 | melee-only VEHICLE/MONSTER |
| `RESERVES_VEHICLE_RANGED_PENALTY` | 0.4 | VEHICLE/MONSTER that is not melee-only |

### Embarkation (which cargo wants a transport)

| Parameter | Default | Meaning |
|---|---|---|
| `EMBARK_COSTLY` | 0.1 | cargo costs >= 100 pts |
| `EMBARK_EXPENSIVE` | 0.15 | cargo costs >= 150 pts |
| `EMBARK_INFANTRY` | 0.1 | cargo is INFANTRY (the common transportable type) |
| `EMBARK_LOW_TOUGHNESS` | 0.3 | cargo toughness <= 4 |
| `EMBARK_MEDIUM_UNIT` | 0.15 | cargo has <= 10 models |
| `EMBARK_MELEE` | 0.25 | cargo has melee weapons (transport delivers the charge) |
| `EMBARK_MID_RANGE` | 0.15 | cargo max weapon range <= 24" |
| `EMBARK_OC_PER_POINT` | 0.1 | per point of objective control on the cargo |
| `EMBARK_POOR_SAVE` | 0.2 | cargo save 5+ or worse |
| `EMBARK_SHORT_RANGE` | 0.3 | cargo max weapon range <= 12" |
| `EMBARK_SINGLE_WOUND` | 0.2 | cargo models have 1 wound |
| `EMBARK_SLOW` | 0.1 | cargo Move <= 6" |
| `EMBARK_SMALL_UNIT` | 0.3 | cargo has <= 5 models (capacity-efficient) |
| `EMBARK_VERY_SLOW` | 0.2 | cargo Move <= 5" |

### Disembarkation (get out now, or stay in?)

| Parameter | Default | Meaning |
|---|---|---|
| `DISEMBARK_AGGRESSIVE_FACTION` | 0.2 | aggressive faction keyword on the cargo |
| `DISEMBARK_CHARGE_CHANCE` | 0.4 | a charge is on after disembarking |
| `DISEMBARK_COSTLY_CARGO` | 0.15 | cargo costs >= 100 pts |
| `DISEMBARK_ELITE_CARGO` | 0.3 | cargo costs >= 200 pts |
| `DISEMBARK_NO_FIRING_DECK` | 0.4 | transport has no Firing Deck (nothing gained by staying in) |
| `DISEMBARK_OBJ_FAR` | 0.15 | objective within 12" of the transport |
| `DISEMBARK_OBJ_NEAR` | 0.4 | objective within 6" of the transport |
| `DISEMBARK_OBJ_ON_TOP` | 0.8 | transport is standing on an objective |
| `DISEMBARK_OC_BONUS` | 0.1 | per point of cargo OC when claiming that objective |
| `DISEMBARK_ROUND_1_PENALTY` | 0.2 | round 1: mild penalty for disembarking early |
| `DISEMBARK_ROUND_2_BONUS` | 0.3 | round 2: start getting out |
| `DISEMBARK_ROUND_3_BONUS` | 0.8 | round 3+: objectives will not score themselves |
| `DISEMBARK_SHOOTING_BASE` | 0.3 | at least one enemy in range after disembarking |
| `DISEMBARK_SHOOTING_PER_TARGET` | 0.1 | per additional enemy in range |
| `DISEMBARK_TRANSPORT_STUCK` | 0.3 | transport remained stationary — cargo is going nowhere |
| `DISEMBARK_TRANSPORT_THREATENED` | 0.25 | an anti-tank weapon can reach the transport |

### Fight, charge and deployment (A5, 2026-08-07)

The rest of F-02's mass. Deployment scoring was "nearly all hard-coded"
(`docs/AI_DECISION_REVIEW_2026-07.md` §3.1) — which meant deployment, the
thing that largely decides rounds 1-2, could not be tuned per persona at all.
Every charge and fight coefficient screened *inert* on the Custodes mirror,
but that fixture fields 9 elite units; B3 re-screens them on the 16-unit Ork
horde where melee decisions are frequent. A coefficient cannot be judged until
it is reachable. Values unchanged; `determinism_check.py` verifies that.

After A4 + A5 the unreachable share of scoring arithmetic is **42%**, down
from 78%.

### Deployment — terrain preference by role

| Parameter | Default | Meaning |
|---|---|---|
| `DEPLOY_TERRAIN_CHAR_COVER` | 2 | deployment terrain, character: piece grants cover |
| `DEPLOY_TERRAIN_CHAR_LOS_BLOCK` | 5 | deployment terrain, character: piece blocks line of sight |
| `DEPLOY_TERRAIN_DURABLE_COVER` | 2.5 | deployment terrain, durable ranged: cover |
| `DEPLOY_TERRAIN_DURABLE_LOS_BLOCK` | 1 | deployment terrain, durable ranged: LoS blocker |
| `DEPLOY_TERRAIN_FORWARD_WEIGHT` | 2 | deployment terrain, melee: weight on how far forward the piece is |
| `DEPLOY_TERRAIN_FRAGILE_COVER` | 3.5 | deployment terrain, fragile shooter: cover |
| `DEPLOY_TERRAIN_FRAGILE_LOS_BLOCK` | 3 | deployment terrain, fragile shooter: LoS blocker |
| `DEPLOY_TERRAIN_MELEE_COVER` | 1.5 | deployment terrain, melee: cover |
| `DEPLOY_TERRAIN_MELEE_LOS_BLOCK` | 4 | deployment terrain, melee: LoS blocker to advance behind |
| `DEPLOY_TERRAIN_SCREEN_COVER` | 2 | deployment terrain, screen: cover |
| `DEPLOY_TERRAIN_SCREEN_LOS_BLOCK` | 1.5 | deployment terrain, screen: LoS blocker |

### Deployment — scout objective choice

| Parameter | Default | Meaning |
|---|---|---|
| `SCOUT_OBJ_ALREADY_HELD` | 5 | scout target: already held (penalty) |
| `SCOUT_OBJ_CONTESTED` | 5 | scout target: contested, worth reinforcing |
| `SCOUT_OBJ_DISTANCE_PENALTY` | 0.3 | scout target: penalty per inch of distance |
| `SCOUT_OBJ_ENEMY_HELD` | 7 | scout target: enemy holds it, a scout can get there first |
| `SCOUT_OBJ_ENEMY_ZONE` | 4 | scout target: inside the enemy deployment zone (penalty) |
| `SCOUT_OBJ_NO_MANS_LAND` | 3 | scout target: sits in no man's land |
| `SCOUT_OBJ_OWN_ZONE` | 2 | scout target: inside our own zone (penalty) |
| `SCOUT_OBJ_UNCONTROLLED` | 10 | scout target: objective nobody controls |

### Reserves — arrival ordering and placement

| Parameter | Default | Meaning |
|---|---|---|
| `RESERVE_DEPLOY_CONTESTED_OBJ` | 1.5 | reserve arrival order: a contested objective needs help |
| `RESERVE_DEPLOY_DEEP_STRIKE` | 2 | reserve arrival order: unit deep strikes |
| `RESERVE_DEPLOY_MELEE` | 1.5 | reserve arrival order: melee unit |
| `RESERVE_DEPLOY_OPEN_OBJ` | 0.5 | reserve arrival order: an uncontested objective is available |
| `RESERVE_DEPLOY_POINTS_DIVISOR` | 50 | reserve arrival order: points per unit of base priority |
| `RESERVE_DEPLOY_ROUND_4` | 2 | reserve arrival order: round 4 |
| `RESERVE_DEPLOY_ROUND_5` | 5 | reserve arrival order: round 5, last chance to arrive |
| `RESERVE_DEPLOY_SHORT_RANGE` | 1 | reserve arrival order: short-ranged unit |

### Reserves — reinforcement placement

| Parameter | Default | Meaning |
|---|---|---|
| `REINFORCE_CHARGE_RANGE` | 3 | reinforcement spot: lands inside charge range |
| `REINFORCE_NEAR_CHARGE_RANGE` | 2 | reinforcement spot: just outside charge range |
| `REINFORCE_OBJ_FAR_BASE` | 8 | reinforcement spot: base value at longer range from an objective |
| `REINFORCE_OBJ_NEAR_BASE` | 10 | reinforcement spot: base value for landing near an objective |

### Charge — target and multi-charge scoring

| Parameter | Default | Meaning |
|---|---|---|
| `CHARGE_BELOW_HALF_BONUS` | 3 | target already below half strength |
| `CHARGE_CANT_HURT_PENALTY` | 1 | we cannot meaningfully damage it |
| `CHARGE_CHARACTER_BONUS` | 2 | target is a CHARACTER |
| `CHARGE_COMBO_OBJ_MULT` | 1.3 | multi-charge: a target is on an objective |
| `CHARGE_COMBO_SHORT_3IN_MULT` | 1.3 | multi-charge: farthest target within 3" |
| `CHARGE_COMBO_SHORT_6IN_MULT` | 1.2 | multi-charge: farthest target within 6" |
| `CHARGE_COMBO_TIGHT_CLUSTER_MULT` | 1.1 | multi-charge: targets are tightly clustered |
| `CHARGE_GANG_UP_BONUS` | 3 | charge target: a friendly unit is already fighting it |
| `CHARGE_HALF_KILL_BONUS` | 3 | charge target: we can remove half its remaining wounds |
| `CHARGE_LIKELY_KILL_BONUS` | 5 | charge target: we can likely kill it outright |
| `CHARGE_LOW_TOUGHNESS_BONUS` | 1 | charge target: toughness 3 or less |
| `CHARGE_MELEE_DAMAGE_WEIGHT` | 2 | expected melee damage multiplier |
| `CHARGE_RANGE_PX` | 480 | 12 inches |
| `CHARGE_SHORT_3IN_MULT` | 1.3 | charge: needs 3" or less (reliability multiplier) |
| `CHARGE_SHORT_6IN_MULT` | 1.2 | charge: needs 6" or less (reliability multiplier) |
| `CHARGE_TARGET_ON_OBJ_MULT` | 1.5 | charge: target is standing on an objective |
| `CHARGE_TIE_UP_SHOOTER_BONUS` | 2 | locks a long-range shooter in combat |

### Fight — which enemy to attack

| Parameter | Default | Meaning |
|---|---|---|
| `FIGHT_LOCK_DANGEROUS_SHOOTER` | 1.5 | fight target: shooter above the dangerous-output threshold |
| `FIGHT_LOCK_LONG_RANGE` | 2 | fight target: long-ranged shooter worth locking in melee |

### Fight — activation order

| Parameter | Default | Meaning |
|---|---|---|
| `FIGHT_ORDER_BADLY_HURT` | 1.5 | fight order: this unit will be badly hurt |
| `FIGHT_ORDER_CAN_WIPE` | 6 | fight order: this unit can wipe its target, so it goes first |
| `FIGHT_ORDER_CHARACTER` | 2 | fight order: target is a CHARACTER |
| `FIGHT_ORDER_DAMAGE_WEIGHT` | 1 | fight order: weight on raw expected melee damage |
| `FIGHT_ORDER_DANGEROUS_SHOOTER` | 2 | fight order: target is a dangerous shooter |
| `FIGHT_ORDER_HALF_KILL` | 3 | fight order: this unit can take its target below half |
| `FIGHT_ORDER_LIKELY_TO_DIE` | 3 | fight order: this unit is likely to die, get its value first |
| `FIGHT_ORDER_MASSIVE_OVERKILL` | 1.5 | fight order: massive overkill, let others take the weak target (penalty) |
| `FIGHT_ORDER_TARGET_ON_OBJ` | 1.5 | fight order: target is on an objective |

### Fight — remaining target terms

| Parameter | Default | Meaning |
|---|---|---|
| `FIGHT_ALREADY_OVERKILLED` | 1 | fight target: prior fighters already overkilled it (penalty) |
| `FIGHT_BELOW_HALF_BONUS` | 3 | target already below half strength |
| `FIGHT_CANT_HURT_PENALTY` | 3 | we cannot meaningfully damage it |
| `FIGHT_CAN_HALVE_BONUS` | 3 | we can take it below half strength |
| `FIGHT_CAN_WIPE_BONUS` | 6 | we can likely destroy the unit outright |
| `FIGHT_CHARACTER_BONUS` | 2 | target is a CHARACTER |
| `FIGHT_LOW_TOUGHNESS` | 1 | fight target: toughness 3 or less |
| `FIGHT_MELEE_DAMAGE_WEIGHT` | 2 | expected melee damage multiplier |
| `FIGHT_OVERKILL_PENALTY` | 1 | >3x the wounds remaining |
| `FIGHT_TARGET_ON_OBJ` | 2 | fight target: standing on an objective |

### Warlord selection

| Parameter | Default | Meaning |
|---|---|---|
| `WARLORD_ATTACHED_BONUS` | 10 | warlord pick: character is already attached to a bodyguard |

---

## What is *not* (yet) a parameter

Anything not listed above is a hard-coded constant or inline number in
`AIDecisionMaker.gd` (e.g. melee-aggression distance limits, horde-unit model
thresholds, deployment scoring). The convention for making one tunable:
replace the raw use with `get_param("NAME", NAME)` — the constant stays as the
default and the name immediately works in every config layer. Add it to the
table here when you do.

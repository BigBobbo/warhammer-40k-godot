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
| `WEIGHT_ENEMY_WEAK_OBJ` | 7.0 | Priority of enemy objectives held with OC ≤ 4 (flippable) |
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

### Secondary-mission positioning

| Parameter | Default | Meaning |
|---|---|---|
| `SECONDARY_OBJECTIVE_ZONE_BONUS` | 3.5 | Objectives in zones a secondary card pays for |
| `SECONDARY_POSITIONAL_BONUS` | 4.0 | Moving toward secondary-specific positions |
| `SECONDARY_KILL_PROXIMITY_BONUS` | 2.0 | Positioning near secondary kill targets |
| `SECONDARY_SPREAD_BONUS` | 6.0 | Spreading into uncovered table quarters (Engage on All Fronts) |
| `SECONDARY_CENTER_BONUS` | 3.5 | Area Denial: center positioning |
| `SECONDARY_ENEMY_ZONE_PUSH_BONUS` | 7.0 | Behind Enemy Lines: pushing into the enemy deployment zone |

---

## What is *not* (yet) a parameter

Anything not listed above is a hard-coded constant or inline number in
`AIDecisionMaker.gd` (e.g. melee-aggression distance limits, horde-unit model
thresholds, deployment scoring). The convention for making one tunable:
replace the raw use with `get_param("NAME", NAME)` — the constant stays as the
default and the name immediately works in every config layer. Add it to the
table here when you do.

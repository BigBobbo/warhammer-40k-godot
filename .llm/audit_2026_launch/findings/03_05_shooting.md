# 03.05 — Shooting Phase Findings

**Audit date:** 2026-05-06
**Scope:** Shooting *sequence* (eligibility, hit→wound→save→damage pipeline, LOS, BGNT, Pistols, Indirect Fire, modifier cap, allocation, reactive timing). Per-token weapon-ability audit is out of scope (see `04_data_entities/02_weapon_rules.md`).
**Source files audited:** `40k/phases/ShootingPhase.gd` (6,058 lines), `40k/autoloads/RulesEngine.gd` (10,886 lines), `40k/scripts/ShootingController.gd` (4,988 lines), `40k/scripts/WoundAllocationOverlay.gd` (1,869 lines), `40k/autoloads/EffectPrimitives.gd`, `40k/phases/ChargePhase.gd`, `40k/phases/MovementPhase.gd` (Fire Overwatch callers).
**Live validation:** MCP bridge available; current scene is mid-Fight (battle round 1, P2 active). Could not drive a fresh shooting flow without disrupting an in-progress fight, but did probe `RulesEngine.validate_shoot()` directly via `execute_script` to reproduce one finding (NEW-S1).

---

## 1. Findings table

| Rule | Wahapedia § | Depth | Correctness | Evidence | Notes |
|------|------|------|------|------|------|
| Eligibility — embarked units cannot shoot directly | Shooting Phase / Datasheet (Transport) | W | ✅ | `phases/ShootingPhase.gd:3005-3006` (`embarked_in != null` rejected); firing-deck branch `:3046-3053` | Existing `SHOOTING_PHASE_AUDIT.md` row, regression spot-check ✅ |
| Eligibility — cannot shoot twice per phase | Shooting Phase | W | ✅ | `phases/ShootingPhase.gd:3013-3014` (`flags.has_shot`); flag set on confirm at `:1185, 1262, 1293, 1388, 1493, 1604, 4098, 4193` | ✅ |
| Eligibility — cannot shoot if Battle-shocked | Battle-shock | W | ✅ VERIFIED (regression spot-check, 2026-05) | `phases/ShootingPhase.gd:3017-3018` AND `autoloads/RulesEngine.gd:3270-3272` (validate_shoot) | Fixed by 2026-05 audit |
| Eligibility — Advanced unit may only fire ASSAULT weapons | Movement Phase / ASSAULT | W | ✅ | `phases/ShootingPhase.gd:3023-3028` selection; `autoloads/RulesEngine.gd:3309-3312` per-weapon validation; advance_and_shoot effect override at both sites | ✅ |
| Eligibility — Fell Back unit cannot shoot | Movement Phase / Fall Back | W | ✅ | `phases/ShootingPhase.gd:3031-3033`; `autoloads/RulesEngine.gd:3279-3282`; `fall_back_and_shoot` effect (Multipotentiality) override at both sites | Override exists at both seam sites; #356/#358 fix verified |
| Pistol — only Pistols may fire while in ER (per-unit) | Shooting Phase / Pistol | W | ✅ | `phases/ShootingPhase.gd:3057-3067` selection; `autoloads/RulesEngine.gd:3306-3307` validation | ✅ for non-BGNT unit. **BGNT case is buggy — see NEW-S1 below** |
| Pistol — target must be enemy unit in ER | Shooting Phase / Pistol | W | ⚠️ | `autoloads/RulesEngine.gd:3367-3371` (validate); `:4137-4138` (eligibility) | RAW also requires "**only target ONE** of the enemy units it is within ER of" (single-target restriction). Code allows multiple Pistol targets if multiple enemies are in ER → see NEW-S5 |
| Pistol — model-level mutual exclusivity (cannot fire both Pistol and non-Pistol) | Shooting Phase / Pistol | W | ✅ | `phases/ShootingPhase.gd:524-546` (per-model UI gate); `autoloads/RulesEngine.gd:3396-3423` (validate). MONSTER/VEHICLE exempt per RAW. | Was flagged 2.11 in `SHOOTING_PHASE_AUDIT.md` — **now fixed (MA-25)**. Regression ✅ |
| Big Guns Never Tire — eligibility (MONSTER/VEHICLE may shoot in ER) | Shooting Phase / BGNT | W | ✅ at selection / 🐛 at validation | `phases/ShootingPhase.gd:3063-3064` allows; `autoloads/RulesEngine.gd:4140-4143` (eligibility allows non-Pistol for BGNT). **`autoloads/RulesEngine.gd:3306-3307, 3367-3371`** rejects in `validate_shoot()` for ANY in-engagement actor with no MONSTER/VEHICLE exemption. | **NEW-S1** — confirmed live via execute_script: a VEHICLE with `in_engagement=true` firing a non-Pistol weapon at an out-of-ER target returns `valid: false` with errors "Non-Pistol weapon ... cannot be fired while in engagement range" + "Pistol weapons can only target enemies in engagement range". Eligibility filter agrees BGNT is allowed; **validate_shoot rejects** the same path. This is the seam between `_resolve_assignment()`/eligibility and `validate_shoot()` — drift. |
| Big Guns Never Tire — -1 to hit penalty (in-ER OR target-in-friendly-ER) | Shooting Phase / BGNT | W | ✅ VERIFIED (regression spot-check, #337 fix in 2026-05) | `autoloads/RulesEngine.gd:4839-4900` (`big_guns_never_tire_penalty_applies`); applied in `:1589-1594` (interactive) and `:2422-2427` (auto). | ✅ |
| Splitting fire across weapons | Shooting Phase / Multiple weapons | W | ✅ | `phases/ShootingPhase.gd:_validate_assign_target` (per-weapon assignments); reassignment allowed `:518-522` | ✅ |
| Hit roll — modifier cap ±1 | Core / Modifiers | W | ✅ | `autoloads/RulesEngine.gd:610-611` (`clamp(net_modifier, -1, 1)`) | ✅ |
| Hit roll — unmodified 1 always misses, unmodified 6 always hits | Core | W | ✅ | `autoloads/RulesEngine.gd:1678-1689` (interactive); `:2493-2509` (auto) | ✅ |
| Hit roll — re-rolls applied before modifiers | Core / Re-rolls | W | ✅ | `autoloads/RulesEngine.gd:589-601` (`apply_hit_modifiers`) | ✅ |
| Wound roll — modifier cap ±1, unmodified 1 always fails | Core / Modifiers | W | ✅ | `autoloads/RulesEngine.gd:631-667` (`apply_wound_modifiers`); unmodified-1 check at `:1927-1928, 1955-1956` (interactive) and `:2832-2853` (auto) | ✅ Wound modifier infrastructure present in BOTH paths (2.5 from prior `SHOOTING_PHASE_AUDIT.md` is now resolved) |
| Wound roll — Twin-linked re-roll | TWIN-LINKED | W | ✅ VERIFIED (regression spot-check, 2026-05) | `autoloads/RulesEngine.gd:1828, 2662` etc. via `WoundModifier.REROLL_FAILED` | ✅ |
| Save — AP applied to armour, invuln immune to AP | Core / Saving Throw | W | ✅ | `autoloads/RulesEngine.gd:3694-3729` (`_calculate_save_needed`); invuln picked when better | ✅ |
| Save — cover +1, save improvement capped at +1 | Core / Cover | W | ✅ | `autoloads/RulesEngine.gd:3708-3714` | ✅ |
| Save — saves never better than 2+ | Core / Saving Throw | W | ✅ | `autoloads/RulesEngine.gd:3717` (`max(2, armour_save)`) | ✅ |
| Save — cap on 3+ saves vs cover (vs AP 0) | Core / Benefit of Cover | W | ❓ | `autoloads/RulesEngine.gd:3704-3706`; comment claims rule is "universal in 10e core; NOT keyword-gated to INFANTRY/BEAST/SWARM". | The 2026-05 audit memory had this as INFANTRY/BEAST/SWARM-only, the current code is universal. Wahapedia core text on this exact wording was not retrievable via WebFetch (page truncated). Flag for human review — potential overcapping for non-INFANTRY units in cover at AP 0. |
| Save — unmodified 1 always fails | Core / Saving Throw | W | ✅ | `autoloads/RulesEngine.gd:1189` (overwatch), `:3081-3088` (auto-resolve), `scripts/WoundAllocationOverlay.gd:828` (interactive) | All three paths enforce. 2.13 from `SHOOTING_PHASE_AUDIT.md` resolved |
| Save — IGNORES COVER overrides terrain & stratagem cover | Core / IGNORES COVER | W | ✅ | `autoloads/RulesEngine.gd:9259` (interactive `prepare_save_resolution`); `:3049-3054` (auto) — cover only granted when `not weapon_ignores_cover` | ✅ |
| LOS — base-aware true LoS via shape geometry | Core / Visibility | W | ✅ VERIFIED (regression spot-check, t2.s8) | `autoloads/RulesEngine.gd:3779-3786` → `EnhancedLineOfSight.check_enhanced_visibility` | ✅ |
| Range check — edge-to-edge model-aware distance | Core / Ranges | W | ✅ | `autoloads/RulesEngine.gd:3767-3768` (`Measurement.model_to_model_distance_px`) | ✅ |
| Targeting — friendly units cannot be targeted | Core | W | ✅ | `autoloads/RulesEngine.gd:4070-4072` eligibility; `:3346-3347` validation | ✅ |
| Targeting — cannot target enemies in ER of friendlies (unless target is MONSTER/VEHICLE) | Core / BGNT | W | ✅ VERIFIED (regression spot-check) | `autoloads/RulesEngine.gd:4088-4095` eligibility; `:3349-3354` validation; helper `_is_target_in_friendly_engagement` | ✅ |
| Targeting — Lone Operative 12" rule | Core / Lone Operative | W | ✅ | `autoloads/RulesEngine.gd:4097-4111` eligibility; `:3356-3364` validation; `has_lone_operative` at `:5362` | T2-2; correctly skips when attached or when leading bodyguard. 2.7 from `SHOOTING_PHASE_AUDIT.md` resolved |
| Targeting — Stealth -1 to hit when ALL models have ability | Core / Stealth | W | ⚠️ | `autoloads/RulesEngine.gd:has_stealth_ability:5885-5893` checks ANY ability presence at unit level (not "all models"). Applied at `:1596-1603` (interactive) and `:2429-2436` (auto). | The 10e rule is "If every model in a unit has Stealth", but the helper checks unit-level ability list. **NEW-S6** — possible bug if a unit contains a mix of Stealth and non-Stealth models (e.g. a non-Stealth attached leader joining a Stealth bodyguard). Verify via `has_stealth_ability` semantics. |
| Look Out, Sir / character protection | (10e: no LOS!; replaced by attached-unit + Lone Operative) | W | ✅ VERIFIED (regression, 2026-05) | `autoloads/RulesEngine.gd:4074-4076` (attached unit not directly targetable); Lone Operative covered above; commentary at `:5391` confirms "no 9e wounds-threshold" | Per Wahapedia core rules WebFetch (2026-05-06), no separate LOS! mechanic exists in 10e — protection is via attachment + Lone Operative only. ✅ |
| Indirect Fire — can shoot without LoS | Core / INDIRECT FIRE | W | ✅ | `autoloads/RulesEngine.gd:3743-3777` (`_check_target_visibility` skips LoS when `is_indirect`); applied via `has_indirect_fire` | ✅ |
| Indirect Fire — -1 to hit, unmodified 1-3 fail, target gets cover **WHEN no models visible** | Core / INDIRECT FIRE | W | 🐛 | `autoloads/RulesEngine.gd:1605-1609` (interactive), `:2438-2442` (auto), `:3045-3052` (auto cover), `:9258-9262` (interactive cover): penalties apply **whenever weapon has INDIRECT FIRE keyword**, regardless of whether target is visible. | **NEW-S2** — RAW per Wahapedia core rules: "If no models in a target unit are visible to the attacking unit when you select that target, then ... subtract 1, unmodified 1-3 fail, target gets Benefit of Cover" — i.e. only when target is NOT visible. The code applies these unconditionally. Visible Indirect-Fire targets currently incur an unjustified -1 to hit + cover. |
| Indirect Fire — no CHARACTER targeting unless visible (audit prompt bullet) | (not in core 10e Indirect Fire) | — | — | — | The audit prompt's bullet "no CHARACTER targeting unless visible" is not present in Wahapedia's Indirect Fire rule — skipping per rule "no claim without Wahapedia URL". |
| Sustained Hits | SUSTAINED HITS | W | ✅ VERIFIED (regression, 2026-05) | `autoloads/RulesEngine.gd:640-655` and Sustained-Hits-injection at #335 | ✅ |
| Lethal Hits | LETHAL HITS | W | ✅ | `autoloads/RulesEngine.gd:710-717` (auto-wound on critical hit; not for Torrent) | ✅ |
| Devastating Wounds — critical wounds → mortal wounds, spillover within unit | Core / DEVASTATING WOUNDS | W | ✅ | `autoloads/RulesEngine.gd:9870-9915` (`_apply_damage_to_unit_pool` with spillover for DW); regular damage `_apply_damage_per_wound_no_spillover` at `:9920-9970`. T2-11 separation. | DW spills, regular doesn't. Matches RAW. ✅ |
| Damage allocation — wounded model first | Core / Allocate Attacks | W | ✅ | `autoloads/RulesEngine.gd:_find_allocation_target_model:10080-10096` — returns first wounded alive model, then any alive | ✅ |
| Damage — variable attacks/damage rolled per model / per save | Core / Variable Stats | W | ✅ | `autoloads/RulesEngine.gd:1352, 2190` (per-model attacks), `:9101, 3102, 1200` (per-save damage) — uses `roll_variable_characteristic` | 2.4 from `SHOOTING_PHASE_AUDIT.md` resolved |
| FNP — rolled per damage point, applies to DW MWs | Core / FNP | W | ✅ VERIFIED (regression, T-016/T-017) | `autoloads/RulesEngine.gd:get_unit_fnp_for_attack:10116+`, applied per-damage-point in `apply_save_damage` and DW path | T-016/T-017 resolved psychic-mortal FNP. ✅ |
| HAZARDOUS — post-attack 1s on D6 per Hazardous weapon, MW or model loss | Core / HAZARDOUS | W | ✅ VERIFIED (regression, t2.s10) | `autoloads/RulesEngine.gd:706-715` (post-resolve hook in `resolve_shoot`); `:759-799` (in `resolve_shoot_until_wounds` — stored on result for post-save processing) | ✅ |
| BLAST — bonus attacks 1/2 vs 6/11+ models, min 3 vs 6+ | Core / BLAST | W | ✅ VERIFIED (regression, t2.s9) | `autoloads/RulesEngine.gd:calculate_blast_bonus`/`calculate_blast_minimum`; `validate_blast_targeting` for friendly-engagement block | ✅ |
| TORRENT — auto-hit, no crit | Core / TORRENT | W | ✅ | `autoloads/RulesEngine.gd:1494-1536` (interactive), `:2331-2373` (auto) | ✅ |
| ANTI-[KEYWORD] X+ | Core / ANTI- | W | ✅ | `autoloads/RulesEngine.gd:get_anti_keyword_data`, `get_critical_wound_threshold`; applied `:1958-1959, 2832+` | Fixed in `SHOOTING_PHASE_AUDIT.md` 2.3. ✅ |
| TWIN-LINKED — re-roll wound rolls | Core / TWIN-LINKED | W | ✅ VERIFIED (regression, t2.st1c) | `WoundModifier.REROLL_FAILED` at `autoloads/RulesEngine.gd:1828, 2662` | ✅ |
| MELTA X — +X damage at half range | Core / MELTA | W | ✅ | `autoloads/RulesEngine.gd:9624-9638` (`apply_save_damage`); `:3107-3111` (auto-resolve `_resolve_assignment`); melta data computed in `prepare_save_resolution` | ✅ MELTA was Tier-1 missing per `SHOOTING_PHASE_AUDIT.md` recommendations — now implemented |
| LANCE — +1 to wound on charge (ranged) | Core / LANCE | W | ✅ | `autoloads/RulesEngine.gd:1853-1862, 2671+` (interactive + auto) | ✅ Implementation present |
| ONE SHOT — once per battle | Core / ONE SHOT | W | ✅ VERIFIED (T4-2) | `autoloads/RulesEngine.gd:3387-3394` (`validate_shoot`); `:717-723` (resolve hook); `is_one_shot_weapon`, `mark_one_shot_fired_diffs`, `has_fired_one_shot` | ✅ |
| EXTRA ATTACKS — bonus, not replacement | Core / EXTRA ATTACKS | W | ✅ | `autoloads/RulesEngine.gd:has_extra_attacks:4744`; auto-injected at `phases/ShootingPhase.gd:_auto_inject_extra_attacks_weapons_shooting:3130` | ✅ |
| PRECISION — wounds can be allocated to attached CHARACTER | Core / PRECISION | W | ✅ | `autoloads/RulesEngine.gd:has_precision:5141`; applied in interactive `:2041-2055` and auto `:2912-2918`; `_find_attached_character_info:5207`; PRECISION damage at `:5237`, `:8849` | ✅ Per-model PRECISION on attached characters supported (P3-100). |
| Cover — terrain types beyond Ruins (woods/crater/obstacle/barricade) | Core / Cover / Terrain | W | ✅ | `autoloads/RulesEngine.gd:3893-3894` (`COVER_TERRAIN_TYPES_WITHIN_AND_BEHIND` = ruins/obstacle/barricade; `COVER_TERRAIN_TYPES_WITHIN_ONLY` = woods/crater/area_terrain/forest); `check_benefit_of_cover:3897-3924` | 2.9 from `SHOOTING_PHASE_AUDIT.md` resolved |
| Reactive — Fire Overwatch (1 CP, opponent's Movement/Charge) | Stratagem / FIRE OVERWATCH | W | ✅ VERIFIED (regression, 2026-05 #348/ss13) | `phases/MovementPhase.gd:3666` and `phases/ChargePhase.gd:2635` invoke `RulesEngine.resolve_shoot` with `overwatch:true`; BS forced to 7 in both paths (`autoloads/RulesEngine.gd:1471-1476, 2308-2313`) | ✅ |
| Reactive — Go to Ground (1 CP, after target select) | Stratagem / GO TO GROUND | W | ✅ VERIFIED (regression, 2026-05 t2.st1) | `autoloads/StratagemManager.gd`; trigger surfaced after `CONFIRM_TARGETS` | ✅ |
| Reactive — Smokescreen (1 CP, after target select, SMOKE keyword) | Stratagem / SMOKESCREEN | W | ✅ VERIFIED (regression, 2026-05 ss16) | `autoloads/StratagemManager.gd`; effect_cover + effect_stealth applied | ✅ Effect-only; UI eligibility filter relies on SMOKE keyword presence |
| Sequential weapon resolution (each weapon profile resolves in turn) | Shooting Phase / "After all weapons selected" | W | ✅ VERIFIED (regression, t2.s11) | `phases/ShootingPhase.gd:_resolve_next_weapon:2524`; `:682-764` sequence loop | ✅ |
| Wound modifier paths drift between auto and interactive | (cross-cutting) | W | ✅ | Both `_resolve_assignment` (`autoloads/RulesEngine.gd:2649-2829`) and `_resolve_assignment_until_wounds` (`autoloads/RulesEngine.gd:1815-1999`) collect wound modifiers from the same set of effects (Twin-linked, Lance, +1/-1 wound effects, Da Boss Ladz, OoM-equivalents, etc.) | Drift checked: identical effect-flag set in both paths. ✅ but see NEW-S3 about the cover/Indirect-Fire seam |
| Pistol restrict pistol-firing unit to ONE target unit per RAW | Core / Pistol | W | ⚠️ | `autoloads/RulesEngine.gd:3367-3371` only checks each target individually (must be in ER); does NOT enforce "only one target" | **NEW-S5** — gap. RAW: "can only target one of the enemy units it is within Engagement Range of." Code allows splitting Pistol fire across multiple in-ER enemies. |

Legend: C/W/U/L = depth; ✅⚠️❌🐛❓ = correctness.

---

## 2. New findings (not in `SHOOTING_PHASE_AUDIT.md` or `40k/test_results/audit_2026_05/AUDIT_REPORT.md`)

### NEW-S1 — `validate_shoot()` blocks BGNT MONSTER/VEHICLE actors from firing non-Pistol weapons in ER 🐛

**File:line:**
- `40k/autoloads/RulesEngine.gd:3290-3307` — non-Pistol-in-engagement rejection has NO `is_monster_or_vehicle(actor_unit)` exemption.
- `40k/autoloads/RulesEngine.gd:3367-3371` — target-must-be-in-ER restriction has NO BGNT exemption.
- Compare: `40k/autoloads/RulesEngine.gd:4133-4143` (eligibility filter) and `40k/phases/ShootingPhase.gd:3055-3067` (`_can_unit_shoot`) DO exempt MONSTER/VEHICLE.

**Wahapedia §:** Big Guns Never Tire — "MONSTER and VEHICLE units are eligible to shoot in their controlling player's Shooting phase even while they are within Engagement Range of one or more enemy units."

**Live repro (2026-05-06 via MCP execute_script):**
```
RulesEngine.validate_shoot({
  actor_unit_id: "T_V",
  payload: { assignments: [{weapon_id: "hazardous_plasma", target_unit_id: "T_T", model_ids: ["m1"]}] }
}, board where T_V owner=1 keywords=[VEHICLE] in_engagement=true; T_T owner=2 keywords=[INFANTRY] no flags)
=> { valid: false, errors: [
     "Non-Pistol weapon 'Hazardous Plasma Gun (Test)' cannot be fired while in engagement range",
     "Pistol weapons can only target enemies in engagement range (target 'T_T' is not in engagement range)",
     "No valid targets in range and LoS"
   ] }
```

**Impact:** Eligibility filter says "yes BGNT vehicle, you can target this enemy at -1 to hit"; then validate_shoot fires when the player tries to confirm and rejects. **A BGNT vehicle in melee cannot fire its main weapons at any target through normal play in the current build.** This is the seam between auto-resolve eligibility and validate_shoot — exactly the drift class the audit prompt warned about.

**Fix shape:** add `not is_monster_or_vehicle(actor_unit)` guard to both line 3306 and the actor side of line 3367.

### NEW-S2 — Indirect Fire applies penalties unconditionally; per RAW only when target is invisible 🐛

**File:line:**
- `40k/autoloads/RulesEngine.gd:1605-1609` (interactive `_resolve_assignment_until_wounds`)
- `40k/autoloads/RulesEngine.gd:2438-2442` (auto `_resolve_assignment`)
- `40k/autoloads/RulesEngine.gd:3045-3052` (auto save resolution: cover always granted)
- `40k/autoloads/RulesEngine.gd:9258-9262` (interactive `prepare_save_resolution`: cover always granted)

**Wahapedia §:** Indirect Fire — "If no models in a target unit are visible to the attacking unit when you select that target, then each time a model in the attacking unit makes an attack against that target using an Indirect Fire weapon, subtract 1 from that attack's Hit roll, an unmodified Hit roll of 1-3 always fails, and the target has the Benefit of Cover against that attack." (verified live via WebFetch 2026-05-06)

**Current code:** Applies -1 to hit, unmodified 1-3 fail, and grants cover **whenever the weapon has INDIRECT FIRE**, irrespective of whether at least one target model is visible to at least one attacker model.

**Impact:** Visible Indirect-Fire targets are unfairly given cover and penalize the attacker. Most artillery in 10e gets a meaningful damage hit from this; e.g. an unobstructed Whirlwind shot should hit on its native BS, not BS-1 with cover.

**Fix shape:** Compute `any_target_model_visible = (for any target_model: any actor_model has LoS to it)`. Apply Indirect-Fire penalties only when this is `false`. The non-LoS targeting permission (currently in `_check_target_visibility`) should remain so the attack is still legal.

### NEW-S3 — Auto-resolve and interactive paths agree on Indirect-Fire wrongness, but that means both are wrong (regression risk)

**File:line:** as in NEW-S2 — both `_resolve_assignment` and `_resolve_assignment_until_wounds` apply penalties unconditionally; Fire Overwatch (which uses the auto path via `phases/MovementPhase.gd:3666` / `phases/ChargePhase.gd:2635`) inherits the same incorrect behaviour for any future Indirect-Fire overwatch.

**Note:** Not a separate bug per se, but a heads-up that fixing NEW-S2 must touch both paths to avoid the exact drift class flagged as a recurring bug pattern.

### NEW-S5 — Pistol-firing unit can target multiple enemy units in ER ⚠️

**File:line:** `40k/autoloads/RulesEngine.gd:3367-3371` (validate_shoot only checks each target's individual ER status; no aggregate "single target" check across the assignments array).

**Wahapedia §:** Pistol — "When such a unit is selected to shoot, it can only resolve attacks using its Pistols **and can only target one of the enemy units it is within Engagement Range of**."

**Impact:** A Pistol-firing unit in ER of two enemy units could split shots across both. Edge case but still off-RAW. Practical impact is low (the typical Pistol-in-ER unit only has one engaged enemy), but it surfaces with overlapping engagements.

**Fix shape:** When `actor_in_engagement and not is_monster_or_vehicle(actor_unit)`, walk the assignments and require all `target_unit_id`s be the same.

### NEW-S6 — Stealth ability check is unit-level, not "all models in unit have Stealth" ⚠️

**File:line:** `40k/autoloads/RulesEngine.gd:has_stealth_ability:5882-5895` — iterates `unit.get("meta", {}).get("abilities", [])` and returns true if ANY entry mentions "stealth".

**Wahapedia §:** "If every model in a unit has the Stealth ability, ranged attacks targeting that unit subtract 1 from their hit rolls." (10e core rules)

**Impact:** If a Stealth bodyguard squad has a non-Stealth attached leader (e.g. Phobos squad + non-Phobos character), per RAW the unit no longer benefits from Stealth. Current code, treating Stealth as a unit-wide flag, would still grant -1 to hit. This is a Stealth-attaches-leader specific case.

**Fix shape:** Replace the unit-level abilities scan with an iteration: every alive model in `unit.models` must individually have Stealth (either via its own profile or through unit-level ability if no model overrides). For attached units this needs to verify both the bodyguard models and any attached CHARACTER models.

### NEW-S7 — Cover save 3+ cap is universal in code; prior-audit memory said INFANTRY/BEAST/SWARM-only ❓

**File:line:** `40k/autoloads/RulesEngine.gd:3704-3706`. In-code comment claims the rule is universal; 2026-05 audit memory (`feedback_godot_testing_methodology.md` and `00_overview.md` line 88) lists the rule as INFANTRY/BEAST/SWARM-gated.

**Wahapedia §:** Could not retrieve full "Benefit of Cover" rule via WebFetch (page section truncated 2026-05-06). Public 10e core text (per the FAQ-and-errata I had access to in earlier 10e versions) supports the keyword-gated reading; the code's universal reading is a behaviour change.

**Impact:** Non-INFANTRY/BEAST/SWARM units with a 3+ save (e.g. some Sv 3+ Custodes Bikes, some VEHICLEs) currently lose cover at AP 0 in this build, when prior-audit consensus said they shouldn't. Either the in-code comment is right and the audit memory is stale, or the code regressed. **Flag for human review with a fresh Wahapedia/Designer's-Commentary pull.**

---

## 3. Top 3 launch-blocker gaps

1. **NEW-S1 — BGNT vehicles in ER cannot legally fire non-Pistol weapons through normal play** (validate_shoot rejects what eligibility allows). This is the first-class drift between `_resolve_assignment()` and the interactive flow that the audit prompt explicitly warned about. Direct gameplay impact: any vehicle pulled into melee loses its weapons until it Falls Back next turn, which contradicts the BGNT rule's whole point.
2. **NEW-S2 — Indirect Fire wrongly penalises every shot.** Whenever a target is visible to the firing unit, current code still applies -1 to hit, unmodified 1-3 fail, and grants the target Benefit of Cover. Indirect-Fire artillery is significantly under-strength. Hits two paths (interactive + Fire Overwatch via auto-resolve) — must be fixed in both.
3. **NEW-S7 — 3+ cover-cap rule is universal in code; previous-audit memory and 10e Designer's Commentary suggest it should be INFANTRY/BEAST/SWARM-gated.** Needs human verification against fresh Wahapedia text. If wrong, every 3+-save VEHICLE in cover at AP 0 is currently being denied cover — a launch-blocker for vehicle-heavy armies.

## 4. Top 3 invisible features

1. **Wound modifier infrastructure is wired** (`WoundModifier` enum, `apply_wound_modifiers`, `effect_minus_one_wound`, `effect_plus_one_wound`, Twin-linked re-roll) but **the player has no UI affordance to manually toggle a +1/-1 wound modifier** in the assignment panel. All wound modifiers come from effect flags on the actor unit, set via stratagems/abilities. There's no checkbox in `ShootingController.gd` for "the GM said +1 to wound" the way `assignment.modifiers.hit.plus_one` exists for hit (`autoloads/RulesEngine.gd:2649-2659`). Functions present, no UI surface.
2. **Pistol mutual exclusivity is enforced per-model**, but the weapon assignment UI in `ShootingController.gd` does not visibly distinguish Pistol from non-Pistol weapons in a way that warns a player they are about to violate the rule before they hit Add Assignment — the rejection only fires post-validation as a toast.
3. **Lone Operative 12" rule is enforced in eligibility/validation**, but the shooting controller's range-circle visualization (`scripts/ShootingController.gd` Range Circle subsystem) does not show a "Lone Operative cutoff" 12" ring around standalone Lone-Operative enemy units. Players have to learn by trial that targets >12" are excluded.

## 5. Live-validation summary

- MCP bridge confirmed reachable (`ping` ok, engine 4.6-stable).
- Game in-progress in Fight phase Round 1; could not drive a clean shooting flow without disrupting existing test fixture.
- Inline-script probe of `RulesEngine.validate_shoot` confirmed **NEW-S1** end-to-end (returned the exact rejection error strings cited above with a synthetic VEHICLE-in-ER + non-Pistol assignment).
- `RulesEngine.is_monster_or_vehicle({meta:{keywords:[VEHICLE]}})` returned `true` — i.e. the keyword test works; it's only the validate_shoot logic that omits the BGNT branch.
- LIVE-VALIDATION SKIPPED for **NEW-S2** (Indirect Fire visibility seam): would require setting up a P1 Indirect Fire weapon shooter with both a visible and a non-visible target back-to-back, which is not feasible in the active Fight scene without a fresh save load. The code path is short enough to be code-grep verified (lines 1605-1609 / 2438-2442 / 3045-3052 / 9258-9262 — no `target_visible` guard).
- LIVE-VALIDATION SKIPPED for **NEW-S5/S6/S7** for the same reason.
- Screenshot captured: `/Users/robertocallaghan/Library/Application Support/Godot/app_userdata/40k/test_screenshots/audit_2026_05_shooting_baseline.png` (game state baseline, Fight Phase R1 P2).

## 6. Cross-references to existing audit rows

These rows in `SHOOTING_PHASE_AUDIT.md` are **resolved** in the current code and should be marked done if not already:
- 2.1 (target in friendly engagement) — fixed
- 2.2 (Overwatch) — fixed (Fire Overwatch + StratagemManager)
- 2.3 (ANTI-, MELTA, TWIN-LINKED, IGNORES COVER, ONE SHOT, EXTRA ATTACKS, PRECISION, LANCE) — all fixed
- 2.4 (variable attacks/damage) — fixed
- 2.5 (wound roll modifiers) — fixed (full WoundModifier system + effect flags)
- 2.6 (Stealth) — fixed but see NEW-S6 about all-models semantics
- 2.7 (Lone Operative) — fixed (T2-2)
- 2.8 (battle-shocked cannot shoot) — fixed
- 2.9 (cover terrain types) — fixed
- 2.11 (Pistol mutual exclusivity) — fixed (MA-25, per-model)
- 2.12 (unmodified 1 wound) — handled by REROLL ordering and explicit unmodified-1 check
- 2.13 (unmodified 1 save in auto path) — fixed at line 3081
- 5.3 (weapon stats in assignment UI) — done
- 5.6 (Undo Last) — done
- 5.7 (keyboard shortcuts) — done
- 6.2 (shooting line visual) — done (T5-V2)
- 6.3 (damage flash) — done (T5-V4)
- 6.4 (range circle visualization) — done (T5-V5)

These remain **partially or fully open** in `SHOOTING_PHASE_AUDIT.md`:
- 2.10 (DW mortal wound model) — mostly correct per T2-11 (separate spillover paths) — minor edge cases noted
- 4.1 (excessive debug logging in `ShootingPhase.gd`) — still present, e.g. the box-drawing `╔═══` blocks at lines `927-936, 1233-1235, 5784-5798` etc.
- 4.2 (duplicate resolution paths) — still two paths but they now mirror each other on most concerns; the seams flagged in NEW-S1, S2, S3 are the practical risks
- 5.1 (auto-select weapon for single-weapon units) — not implemented
- 5.4 (expected damage preview) — implemented (T5-UX1/P3-114)
- 5.5 (shooting phase summary panel) — `dialogs/ShootingPhaseSummaryDialog.gd` exists; verify it's wired
- 6.1 (animated dice visuals) — text-based dice log still present

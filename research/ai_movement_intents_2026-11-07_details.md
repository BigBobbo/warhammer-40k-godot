# AI movement intents — details

_2026-11-07 · companion to `ai_movement_intents_2026-11-07.md`_

### Survival & concealment

#### SUR-01 — Move into light or dense terrain to become Hidden

End the move with every alive model of an INFANTRY/BEASTS/SWARM unit within a terrain area that contains a dense feature (ruins, woods, buildings, containers), and plan not to shoot. While the unit made no ranged attacks this turn or the previous turn, each such model is visible only to enemy models within its detection range (15″ by default). Beyond that range it cannot be targeted by direct fire, Fire Overwatch, Explosives, Surveil or Precision. A unit is visible if any one model is, so every model must qualify; an attached leader without one of those keywords breaks it. Advancing in is free if the unit was not going to charge or start an action anyway. On a terrain objective the same move holds the objective (a model within the area is in range) and hides the unit.

- **When:** Use when the unit is INFANTRY/BEASTS/SWARM and its shooting this turn is absent or low-value. A dense area must be reachable this move (M, or M+D6 when Advancing costs nothing) and must fit every model. Score by the share of enemy ranged threat that would still be beyond detection range at their next-turn firing positions (enemy M + range): a Hidden spot that hides from nobody is worth nothing. Strongest in rounds 1-2, against gunlines, and for objective holders on terrain objectives, action units and melee units that are staging. Discount it when enemy melee can reach the spot (Hidden does not stop charges), against [INDIRECT FIRE], and against Hidden-removing abilities (e.g. Burna Bomb).
- **Units:** INFANTRY, BEASTS, SWARM. Attached units qualify only if every model has one of those keywords. Never MONSTER, VEHICLE or MOUNTED.
- **Move type:** Normal Move / Advance / Remain Stationary (already inside) / Disembark (tactical, then move) / Reserves arrival into a dense area
- **11e rules (corrected):** 13.09 HIDDEN (docs/rules/40k_11th_edition_core_rules.txt:2292-2303): an INFANTRY/BEASTS/SWARM model within a terrain area containing one or more dense features, whose unit made no ranged attacks this turn or the previous turn, is visible only to enemy models within its detection range, 15″ unless otherwise stated. 13.05 dense examples (:2089-2095). 06.01: a unit is visible if any model is visible (:1087-1110). 04.02: targets must be visible (:628-642). 10.07: [INDIRECT FIRE] can still target non-visible units (:1549-1574). 09.06: an Advance bars only charges and actions (:1401-1415). 14.02: a model is in range of a terrain objective while within that area (:2401-2406). Engine: TerrainManager.is_model_hidden (40k/autoloads/TerrainManager.gd:999-1043) checks any part of the base, the area group, and a turn stamp delta < 2. The unit is hidden only while every alive model is hidden (.llm/codex_11e_wahapedia/RULINGS.md:169). Unconfirmed (web snippet only): a later commentary letting light-only areas qualify; the core text and the engine both require dense.
  - _Skeptic:_ Hidden is not dense-only. The 13.09 errata changes the first bullet to 'a terrain area that contains one or more light/dense terrain features' (40k_11th_edition_errata_faq_commentary.md:529). The engine already implements this (TerrainManager.is_model_hidden -> category_allows_hidden, TerrainManager.gd:1001-1051, commit dc9d3b0). So both the 'unconfirmed light-only' caveat and 'the core text and the engine both require dense' are stale. Also wrong: '09.06: an Advance bars only charges and actions'. After an Advance the unit may shoot only with [ASSAULT] weapons (10.04 :1489-1491, 10.05 :1506-1516), and is barred from indirect shooting (10.07 :1553) and Explosives (15.05 :2659-2662). Per 01.02.07, a 'hidden unit' needs only one hidden model (errata_faq:49). Denying targeting still needs every model to be non-visible (06.01 :1098-1099). — 40k_11th_edition_errata_faq_commentary.md:529, :49; 40k_11th_edition_core_rules.txt:2292-2303, 1098-1099, 1489-1516, 1553; TerrainManager.gd:1001-1051
  - _Errata check:_ Hidden needs a terrain area containing a light OR dense feature, not dense only (13.09 errata). The 'no ranged attacks in the previous turn' condition counts as met in the first turn (13.09.01), and a hidden model the attacker cannot fully see because of intervening DENSE features has gone to ground: its detection range drops by 3″, from 15″ to 12″, and can never go below 9″ (13.11.01, 02.02.01). A 'hidden unit' needs only one hidden model (01.02.07), not every alive model as RULINGS.md:169 says, but denying targeting still needs every model to be non-visible (06.01). — 13.09 errata; Commentary 13.09.01 Hidden and the First Turn; Commentary 13.11.01 Gone to Ground; Commentary 01.02.07 Describing Units; Commentary 02.02.01 Modifiers
- **AI today (none):** Implemented but shipped OFF. _hidden_gain_value (40k/scripts/AIDecisionMaker.gd:28578-28589) returns 0 because WEIGHT_HIDDEN_GAINED = 0.0 (:2633, after two inconclusive A/Bs, :2615-2631). It is only added at objective-trip endpoints (:10306-10314) and to threat-dodge candidates (:28965-28970). Even when switched on it never generates a 'go into this dense area' destination. It sizes the immunity by enemy centroid against the 15″ base range (_hidden_immunity_fraction :28548-28575), which ignores per-observer Gone to Ground and enemy movement. The cover nudge (:14817-14877) tests 'any polygon between me and one enemy centroid', which is unrelated to 13.09.
- **Engine support:** Reuse TerrainManager.is_model_hidden through the probe-model pattern _position_would_be_hidden (AIDecisionMaker.gd:28515). Use TerrainManager.area_at (:847), build_area_group_map, category_of (:792) and pieces_model_within_of (:927) to enumerate dense areas, and hidden_model_visible_to / detection_range_inches_for (:1047/:1061) per enemy observer. Use the placement ladder _try_move_with_collision_check (AIDecisionMaker.gd:15405) to fit every model inside. NEW: a candidate generator for dense areas reachable within M (or M + average D6) that can hold the whole unit, scored by the enemy shot volume that cannot get within detection range next turn, minus a discount for melee reach and indirect fire.
- **Value (high):** The corpus calls 'get to hidden 12' the main infantry movement goal in rounds 1-2 (F001: high confidence, 4 channels). It blanks a whole enemy shooting phase at no cost for units with nothing to shoot, and the full rule is already live in the engine. The bench says it pays only where infantry can reach dense terrain and survive there, so it must be scored by immunity fraction, not given a flat bonus.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:2292-2303 (13.09 text) and :2346-2356 (worked example: B and C hidden, D inside B's 15″ detection range)
  - 40k/autoloads/TerrainManager.gd:999-1043 is_model_hidden; :1047 hidden_model_visible_to; :1061 detection_range_inches_for
  - .llm/codex_11e_wahapedia/RULINGS.md:169 (hidden only while every alive model is hidden)
  - YouTube 0Gcpze1G4Lc @10:00 (40K Dirtbags): “I try and get that dense cover for the hidden 12 ... How fast can I get to hidden 12” [research/youtube/ai_learnings.json F001]
  - YouTube SkaqF6vbCYA @12:00 (Happy Krumping): “elite infantry is incredibly powerful, making use of the hidden rule ... can't be targeted outside of 15 or 12” [F001]
  - YouTube dPFfT2IIlME @15:00 (Tabletop Titans): “if you want to be a shooting army right now ... you have to be able to get within hidden range quickly”
  - _…and 9 more_
- **Absorbed duplicates:** SUR-11 (Pick the Hidden spot behind a dense wall and beyond each shooter's detection range)
- **Found by:** core-rules, youtube, web, first-principles, factions

#### SUR-04 — End the Movement phase out of Fire Overwatch reach

Fire Overwatch (1CP) is used once, at the END of our Movement phase, after the opponent has seen every move. One unengaged, non-TITANIC, non-battle-shocked enemy unit snap-shoots ONE visible, eligible (unengaged) unit of ours within 24″, hitting only on unmodified 6s with no hit re-rolls. Only final positions matter. Units can cross open ground freely, but the ones we can least afford to lose should end the phase unseen (out of line of sight, Hidden beyond detection range, beyond Lone Operative range, or embarked), engaged, or more than 24″ away and outside the weapon range of the enemy's high-volume and [TORRENT] shooters. The opponent can shoot only one unit, so manage the army's worst exposure (the best target they will have), not the sum. Baiting with a cheap model does not work in 11e (see rejected).

- **When:** Use when the opponent has 1+ CP and at least one unengaged, non-battle-shocked unit with high shot volume or [TORRENT] weapons, within 24″ and line of sight of where our valuable units would end. It matters most when those units are fragile, high-value, about to charge or about to score. It matters least for cheap chaff and in rounds 4-5, when objective moves are mandatory.
- **Units:** All. Most important for low-Toughness multi-wound infantry, characters, fragile vehicles and units that need full strength to charge.
- **Move type:** End position of every move in our Movement phase (Normal / Advance / Disembark / Reserves arrival / Embark)
- **11e rules (verified):** 15.08 FIRE OVERWATCH (docs/rules/40k_11th_edition_core_rules.txt:2735-2747): WHEN is the end of the opponent's Movement phase; TARGET is one friendly unengaged unit, excluding TITANIC. 15.09 SNAP SHOOTING (:2749-2760): one visible, eligible enemy unit within 24″; hits only on an unmodified 6 irrespective of BS or modifiers (so cover is irrelevant); no hit re-rolls. 15.01: the same stratagem only once per phase (:2496-2499). 01.07: battle-shocked units cannot be targeted with their own side's stratagems (:212-216). 04.02: targets must be unengaged (:628-642). 17.03: engaged MONSTER/VEHICLE units can be targeted only in the attacker's own Shooting phase (:2894-2909). Engine: 11e timing is movement_phase_end only (40k/phases/MovementPhase.gd:1745-1749; StratagemManager.gd:174, :5086-5100); RulesEngine.snap_shooting_targets_11e (:1475). In the engine [TORRENT] still auto-hits under snap shooting (RulesEngine.gd:2443, :2474, :2509); the core text does not settle Torrent against 15.09.
- **AI today (none):** _overwatch_exposure_penalty (40k/scripts/AIDecisionMaker.gd:28660-28687) exists, but OVERWATCH_EXPOSURE_PENALTY = 0.0 (:2662), and it is applied only to objective-trip candidates (:10290-10304). Even when switched on it is range-only (a 24″ band around enemy centroids) and sums every newly exposed enemy's shot volume instead of taking the single best target the opponent gets. It ignores visibility, Hidden and engagement, and does not skip engaged or TITANIC watchers. Its header comment (:2650-2656) wrongly says the engine still uses the 10e timing.
- **Engine support:** RulesEngine.snap_shooting_targets_11e (:1475) on a copied board answers 'which of my units could this enemy overwatch'. TerrainManager.model_visible_11e (:1201) and hidden_model_visible_to (:1047) handle probe positions. _unit_ranged_shot_volume (AIDecisionMaker.gd:28637) gives volume, and RulesEngine.is_torrent_weapon (:11361) identifies auto-hit volume. NEW: an army-level, end-of-phase evaluator: the maximum over our units of expected snap-shot damage × unit value, given the opponent's CP and unengaged watchers, applied to each mover's candidate set.
- **Value (high):** It applies in every one of our Movement phases, the corpus treats it as a top 11e consideration (F004: high confidence, 4 channels), and only end positions need scoring. The cost per phase is bounded (one unit, 6s to hit), so it is a tie-breaker-plus rather than an override.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:2735-2760 (15.08, 15.09) and :2496-2499 (15.01)
  - 40k/phases/MovementPhase.gd:1745-1749 (no per-move Overwatch offer at 11e); 40k/autoloads/StratagemManager.gd:174 and :5086-5100
  - 40k/autoloads/RulesEngine.gd:1475 snap_shooting_targets_11e; :2443/:2509 Torrent auto-hit; :2474 snap 6+ clamp
  - YouTube qahZnQPN8a8 @27:00 (Vanguard Tactics): “Overwatch is so powerful in this game now because you can't ... put one model out ... you can't bait them out anymore” [F004]
  - YouTube eUpeWbN7gF4 @28:00 (StrikingScorpion82): “overwatch is done at the end of the opponent's movement phase ... it's a decision we can make uh once movement's done” [F004]
  - YouTube FT5JoL5Myis @05:00 (Deploy on the Line 40K): “it's just too easy to overwatch in 11th edition. You can't play around it anymore with these big squads” [F004]
  - _…and 9 more_
- **Absorbed duplicates:** OFF-05 (Stage the charge out of sight to avoid Overwatch)
- **Found by:** core-rules, youtube, web, first-principles, bucket-editor

#### SUR-02 — Break line of sight completely behind obscuring or Solid terrain

End fully unseen by the enemy's dangerous shooters. Either stand just outside (not inside) a terrain area containing a light or dense feature so that every sight line crosses it, or stand behind the ground-level walls of a dense (Solid) feature. An unseen unit cannot be targeted by direct fire, Fire Overwatch, Explosives, Surveil or Precision. Only [INDIRECT FIRE] can still reach it: the target gets cover, and hits fail on 1-5 unless the shooter stayed stationary and has a spotter. This works for every unit type, including vehicles and monsters that can never be Hidden and units that shot last turn.

- **When:** Use when the unit does not need to shoot this turn, or can shoot from an angle that keeps the main threats blind, and it must survive: damaged or high-value units, characters, transports, units the opponent's kill cards pay for, and units that cannot be Hidden. Weight each enemy by the damage it could do next turn from where it can move to, not only from where it stands now. Do not step inside the obscuring area: 13.10 ignores any area that either model is within.
- **Units:** All. Essential for VEHICLE, MONSTER and MOUNTED units, and for units that shot recently.
- **Move type:** Normal Move / Advance / Fall Back (landing behind terrain) / Remain Stationary
- **11e rules (verified):** 13.10 OBSCURING (docs/rules/40k_11th_edition_core_rules.txt:2305-2311): areas with light or dense features are obscuring; if every line of sight crosses obscuring areas (excluding areas either model is within), the two models are not visible to each other. 13.11 SOLID (:2313-2316): no line of sight across enclosed gaps 3″ or less from ground level. 06.01 (:1024-1034, :1087-1110). 04.02 (:628-642). 10.07 (:1549-1574). Engine: TerrainManager._line_blocked_11e (:1169) via model_visible_11e (:1201), using 9-point base sampling. The 13.11 gap branch is dead code, but dense terrain always blocks at ground level (docs/rules/11th_edition_delta_audit.md:135-136). Models never block line of sight in the engine (:100).
- **AI today (partial):** Only the unscored Task-8 cover nudge exists. When the direct path is clear, _find_cover_path (40k/scripts/AIDecisionMaker.gd:14746, :14817-14855) tries ±15° and ±30° headings and takes the first endpoint where _position_has_cover (:14857-14877) finds any terrain polygon between it and any single enemy centroid. There is no 13.10 test, no requirement that all threats be blind, and no destinations generated behind terrain. The threat model (:28794-28880) is distance-only. Only deployment (not movement) prefers line-of-sight blockers for characters and fragile shooters (_score_terrain_for_role :5594-5640).
- **Engine support:** TerrainManager.model_visible_11e / model_fully_visible_11e (:1201-1211) accept probe model dictionaries, and is_obscured_between (:976) handles point checks. LineOfSightManager.calculate_los_to_position (40k/autoloads/LineOfSightManager.gd:101) and calculate_visibility_grid_to_target (:340) answer 'who can see this spot'. RulesEngine.unit_sight_line (:6641) works on a copied board. NEW: a candidate generator for points on the far side of obscuring areas from the threat-weighted enemy positions, plus a 'visible enemy damage at destination' score that uses enemy next-turn positions.
- **Value (high):** It is the only full protection for vehicles, monsters and units that have just fired, and F005 calls staging out of line of sight the default opening. Line-of-sight queries that accept probe positions already exist, but the movement planner never calls them (inventory gap 1).
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:2305-2316 (13.10, 13.11) and :2345-2350 (example: obscuring area between A and D, so they are not visible to each other)
  - 40k/autoloads/TerrainManager.gd:1169 _line_blocked_11e; :1201-1211 model_visible_11e / model_fully_visible_11e
  - docs/rules/11th_edition_delta_audit.md:135-136 (13.10 partial; 13.11 gap branch dead)
  - YouTube 1SRkN4Drhs4 @18:00 (Play On Tabletop): “my jumpack intercessors will move to stage behind this terrain ... I just don't want to be shot” [F005]
  - https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics/Adeptus_Mechanicus (search snippet: keep units edged right up against ruins, but not IN them)
  - https://www.tabletopbattles.com/40k-start-competing-gw-terrain-layout-1/ (search snippet: sitting behind the C ruin with a vehicle at the start of the game is common)
- **Found by:** core-rules, web, first-principles

#### SUR-03 — Move into cover (Benefit of Cover: attacker's BS worsened by 1)

This is the user's own 'move into cover' example. End the move so the unit has the benefit of cover against the expected attackers. Either every model of an INFANTRY/BEASTS/SWARM unit is within some terrain area (exposed craters and debris count), or every model is not fully visible to the attacking model because of intervening terrain features or obscuring areas. In 11e cover worsens the BS of each incoming ranged attack by 1; it is not a save bonus, so its value grows with shot volume rather than AP. It is all-or-nothing for the unit: one model in the open loses it. Use it when Hidden is not available: the unit will shoot, has shot recently, or enemies are inside detection range.

- **When:** Use when the unit expects to be shot next turn and cannot be Hidden or out of line of sight, and a terrain area within M can hold every model while keeping its own firing lanes. It is worth most against many weak BS-based shots. It is worthless against [TORRENT] (auto-hit), [IGNORES COVER], [PSYCHIC] (may ignore BS modifiers) and snap shooting (unmodified 6s). It is redundant for STEALTH units and against indirect fire (the target always has cover), and does nothing in melee. A [HEAVY] unit that creeps 3″ or less into cover keeps its +1 to hit.
- **Units:** INFANTRY, BEASTS, SWARM through the in-area clause; any unit through the not-fully-visible clause (see SUR-08 for vehicles and monsters).
- **Move type:** Normal Move / Advance / Remain Stationary; a Normal Move of 3″ or less for [HEAVY] units
- **11e rules (corrected):** 13.08 BENEFIT OF COVER (docs/rules/40k_11th_edition_core_rules.txt:2278-2290): every model must qualify; worsen BS by 1. Terrain categories 13.03-13.05 (:2074-2095). 24.18 [IGNORES COVER] (:3783-3795). 24.33 STEALTH (:3922-3930). 24.37 [TORRENT] (:3943-3950). 24.29 [PSYCHIC] may ignore BS modifiers (:3878-3888). 15.09: snap shots hit on unmodified 6s irrespective of modifiers (:2749-2760). 10.07: an indirect target has cover (:1549-1574). 24.16 [HEAVY]: no model moved more than 3″ (:3751-3770). Engine: TerrainManager.unit_has_cover_11e (40k/autoloads/TerrainManager.gd:1380-1418), judged per attacker model. Cover is skipped for TORRENT, IGNORES COVER and PSYCHIC (RulesEngine.gd:17755-17761) and for snap shooting (RULINGS.md:498).
  - _Errata check:_ Cover is decided separately for each attacking model (FAQ 13.08): each target model may qualify by either condition (in a terrain area or not fully visible), and a model in the open loses cover only against attackers that can fully see it. So it is not all-or-nothing against a whole enemy unit, and because BS can never be worsened past 6+ (Commentary 02.02.01), cover does nothing against BS 6+ attacks. — FAQ 13.08 Benefit of Cover; Commentary 02.02.01 Modifiers
- **AI today (partial):** Only the B34 cover nudge applies (40k/scripts/AIDecisionMaker.gd:14746, :14817-14877): the first ±15°/±30° heading whose endpoint has any terrain polygon between it and one enemy centroid. This is not 13.08: there is no candidate with every model inside a terrain area, and terrain categories are not checked. The AI's own _target_has_benefit_of_cover (:25044-25120) is 10e-style and used only to score shooting targets. A [HEAVY] creep of 3″ or less is never planned: B23 either holds or moves (:7419-7430).
- **Engine support:** TerrainManager.unit_has_cover_11e(unit with probe positions, attacker_model) (:1380), area_at (:847) and pieces_model_within_of (:927). ModifierStack.collect_hit_context_11e (ModifierStack.gd:96-121) prices the -1 BS, and ModifierStack.heavy_applies_11e (:168) handles the 3″ Heavy rule. NEW: a candidate generator for terrain areas within M that fit the whole unit and keep at least one target visible, scored by expected incoming hits removed (enemy BS-based shots × 1/6) minus firing lanes lost.
- **Value (high):** It is the user's own example. It gives -1 BS from every direction to the most common unit type, comes up all the time and is cheap to evaluate, and the current nudge does not implement the 11e rule.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:2278-2290 (13.08) and :2346-2350 (diagram: unit B loses cover because not all models are within the area)
  - 40k/autoloads/TerrainManager.gd:1380-1418 unit_has_cover_11e
  - 40k/scripts/rules/ModifierStack.gd:96-121 collect_hit_context_11e (cover applied on the hit side)
  - YouTube aQsog-fkQJ8 @85:00 (Maelstrom Gaming Studios - Tyranids): “partially obscured ... your storm bolters will be at minus one to hit” [F030]
  - YouTube VqwMdS9MuIY @171:00 (TacticalTortoise 40k): “Don't get cover, right? Yeah. No, it's ignore cover for all” [F030]
  - https://www.wargamer.com/warhammer-40k/terrain-rules (search snippet: cover is -1 to the attacker's BS instead of +1 save)
  - _…and 1 more_
- **Found by:** core-rules, youtube, web, first-principles

#### SUR-05 — Stay outside enemy charge reach (kite)

End the move beyond the next-turn charge reach of every dangerous enemy melee unit. That reach is the enemy's M, plus D6 only if it can Advance and still charge (e.g. riled-up Orks), plus 12″: a charge target must be within 12″ and within the 2D6 roll, and engagement range does not extend this. Shooters should keep those enemies inside their own weapon range at the same time (retrograde shooting). Dense features over 2″ high, which non-INFANTRY/BEASTS/SWARM/MOBILE models cannot move through horizontally, lengthen the enemy's real reach. Hidden does not stop charges, so this is the counter to melee.

- **When:** Use for fragile shooters, characters, aura/support carriers, artillery and melee-weak vehicles facing enemy melee units, when the unit is not needed on a priced objective this turn and being charged would be a bad trade. Advance away when no shooting is lost (no targets in range, or [ASSAULT] guns). Skip it for lockers and for units that want to be charged.
- **Units:** Ranged infantry, characters, support/aura units, artillery, light vehicles
- **Move type:** Normal Move / Advance (break contact) / Fall Back (to a spot outside reach)
- **11e rules (verified):** 11.02: eligible to charge if within 12″ of an enemy, unengaged, and did not Advance or Fall Back this turn (docs/rules/40k_11th_edition_core_rules.txt:1603-1625). 11.04: targets must be within 12″ and within the roll; the move must end engaged (:1640-1666). 09.05/09.06 move distances (:1390-1415). 13.06: dense sections over 2″ block horizontal moves by models without INFANTRY/BEASTS/SWARM/MOBILE (:2163-2183). Orks riled up: their Advance does not prevent a charge (.llm/codex_11e_wahapedia/orks/RULES.md:76). Engine: ChargeMove11e.eligible / selectable_distance_ceiling (40k/scripts/rules/movetypes/ChargeMove11e.gd:31, :106).
- **AI today (partial):** Three partial mechanisms. B21 threat-aware hold (40k/scripts/AIDecisionMaker.gd:7357-7391): a pure-ranged unit with faction aggression ≤1.2 stays put if its straight-line destination's charge threat is ≥3.0 and an enemy centroid is in weapon range. B35 dodge (_find_safer_position :28892-28990, applied :14486-14493): tries 2″/4″ sideways shifts and 75%/50% moves. A threat_delta term in objective scoring (:10285-10288). None of them generates a 'move away to the edge of reach' destination. The radius is centroid-based M + 12 + ER (:28714), with no Advance for enemies that can Advance and charge, and no terrain pathing.
- **Engine support:** _calculate_enemy_threat_data (:28695), once the radius is corrected. EffectPrimitives.has_effect_advance_and_charge for enemy units. TerrainManager.can_move_through_11e (:1249) and calculate_charge_terrain_penalty (:509) for path-aware reach. RulesEngine.unit_within_weapon_reach (:6718) to keep our own targets. NEW: 'kite point' candidates: points within M (or M+D6) beyond every dangerous melee unit's reach (closest-model distances) that keep at least one target in range.
- **Value (high):** This is the standard counter to melee armies. Today the AI only stays still or nudges locally, so its shooters walk into charge range whenever their objective trip says so.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1603-1666 (11.02, 11.04)
  - 40k/scripts/rules/movetypes/ChargeMove11e.gd:4-17 (targets chosen after the roll; within min(12″, roll))
  - 40k/scripts/AIDecisionMaker.gd:28714 (AI charge threat = M + 12″ + 2″ ER, overstated by the ER)
  - research/youtube/ai_learnings.json F023 ai_impact.risk: 'Bound the exposure to units the enemy cannot reach with a charge this turn'; F001 risk: 'Hidden does not stop charges'
  - https://40-carrot.app/guides/threat-range-40k (Movement + 12″ maximum charge is the outer edge of a melee threat)
  - https://grimhammertactics.com/40k-tactics-mastering-movement-in-warhammer-40k/ (pre-measure enemy threat ranges before moving)
  - _…and 4 more_
- **Absorbed duplicates:** OFF-20 (Kite: shoot from outside the enemy's charge reach)
- **Found by:** youtube, core-rules, web, first-principles

#### SUR-07 — Ordered Retreat out of a losing combat to a safe landing spot

Fall back up to M with an engaged unit that is not battle-shocked when it would lose the coming fights or is wasted tied up. Land somewhere actually safe or useful: out of line of sight or Hidden, outside the enemy's charge reach, in cover, or still contesting an objective. Ordered Retreat cannot pass through enemy models. Afterwards the unit cannot shoot, charge or start an action this turn unless an ability allows it, so price that loss.

- **When:** Use when the unit is engaged and not battle-shocked, and its expected losses in the next Fight phases (ours and theirs) exceed the value of staying (OC kept, shield from shooting, lock). A legal route around the enemy models must lead to a landing spot whose next-turn exposure is lower than staying. Prefer units with fall-back-and-shoot or fall-back-and-charge abilities, and be wary with vehicles, which lose a whole turn of shooting.
- **Units:** Any engaged unit that is not battle-shocked
- **Move type:** Fall Back (Ordered Retreat)
- **11e rules (corrected):** 09.07 FALL-BACK MOVE (docs/rules/40k_11th_edition_core_rules.txt:1417-1441): eligible if engaged; Ordered Retreat only if not battle-shocked; the unit must end unengaged; afterwards it is not eligible to shoot, declare a charge or start an action this turn. 03.01: bases cannot move through enemy models (:389-395). Engine: FallBackMove.select_mode / after_moving_effects (40k/scripts/rules/movetypes/FallBackMove.gd:52, :116-135); ShootingType honours fall-back-and-shoot abilities (ShootingType.gd:80-93).
  - _Errata check:_ Ordered Retreat is also unavailable when an enemy stratagem or ability instructs the unit to take a Desperate Escape test. The unit must then use Desperate Escape (a hazard roll per model, with that rule's penalty applied to each roll, plus a battle-shock roll), so check the engaged enemy for such rules before pricing the retreat. — Commentary 09.07.01 Desperate Escape
- **AI today (partial):** _decide_engaged_unit falls back by default whenever the unit is not holding an objective (40k/scripts/AIDecisionMaker.gd:12123-12161). The survival estimate (:12373-12427) only changes on-objective decisions and the narration. The landing spot (_compute_fall_back_destinations :12185-12273) is the best objective 'behind' the unit, or straight away from the engaging enemies, tried at 100/75/50/25% of M. It is never scored for cover, line of sight, Hidden or charge threat.
- **Engine support:** _compute_fall_back_destinations (:12185) and _try_fall_back_positions as the executor. To score landing spots: TerrainManager.model_visible_11e (:1201), is_model_hidden (:999), unit_has_cover_11e (:1380), and _evaluate_position_threat (AIDecisionMaker.gd:28794). AIAbilityAnalyzer.can_fall_back_and_shoot (AIAbilityAnalyzer.gd:290). NEW: scored landing-spot candidates (exposure after landing vs staying), and a decision that compares them with SUR-06 and SUR-18.
- **Value (high):** The decision comes up most turns once armies meet. The AI makes it by a fixed rule and lands in the open.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1417-1441 (09.07)
  - 40k/scripts/rules/movetypes/FallBackMove.gd:52-135
  - 40k/scripts/AIDecisionMaker.gd:12123-12161 (falls back whenever not holding), :12185-12273 (landing spot)
  - YouTube F5TL7LhZJlY @13:00 (40K Dirtbags): “He spends a CP realizing after the fact that you can't fall back and shoot with vehicles. It's only infantry” [F017]
- **Found by:** core-rules, first-principles

#### SUR-08 — Hull-down a vehicle or monster behind intervening terrain

Models without INFANTRY/BEASTS/SWARM never get cover by standing inside terrain and can never be Hidden. They get the benefit of cover only against attacking models that cannot see them fully because of intervening terrain features or obscuring areas, judged per attacking model. Park the model so terrain clips the main enemy anti-tank's view of it while it keeps its own firing lanes. Do not stand inside the obscuring area you rely on: 13.10 ignores any area either model is within.

- **When:** Use when a VEHICLE or MONSTER must stay exposed enough to shoot or hold an objective and cannot fully break line of sight, and the enemy anti-tank comes from a predictable arc. It is worthless against [IGNORES COVER], [TORRENT], [PSYCHIC] and snap shooting. For [HEAVY] weapons, an adjustment of 3″ or less keeps the +1 to hit.
- **Units:** VEHICLE, MONSTER, MOUNTED and any unit without INFANTRY/BEASTS/SWARM (infantry outside a terrain area can use the same clause)
- **Move type:** Normal Move / Remain Stationary (a shuffle of 3″ or less for [HEAVY])
- **11e rules (verified):** 13.08 second bullet (docs/rules/40k_11th_edition_core_rules.txt:2283-2286): not fully visible to the attacking model because of intervening terrain features and/or obscuring areas. 06.01: a model is fully visible only if every part facing the observer is visible (:1087-1104). 13.10: areas either model is within are excluded (:2305-2311). 13.09: Hidden requires INFANTRY/BEASTS/SWARM (:2292-2297). Engine: the not-fully-visible branch of TerrainManager.unit_has_cover_11e, per attacker model (40k/autoloads/TerrainManager.gd:1403-1416), via model_fully_visible_11e (:1207).
- **AI today (partial):** The B34 nudge also applies to vehicles (40k/scripts/AIDecisionMaker.gd:14746, :14817-14877), but it only asks whether any polygon lies between the endpoint and some enemy centroid. It never judges per attacking model or checks that the unit keeps its own lanes, and Heavy-safe creeps are not planned (B23 :7419-7430).
- **Engine support:** TerrainManager.model_fully_visible_11e (:1207) and unit_has_cover_11e(unit, attacker_model) (:1380) with probe positions, per enemy anti-tank model. features_crossing (:857) to find candidate walls. RulesEngine.get_eligible_targets (:7137) on a copied board to confirm our own targets stay visible. NEW: a hull-down candidate generator (points next to terrain on the threat side), scored by the share of enemy anti-tank damage that suffers -1 BS minus own lanes lost.
- **Value (high):** It is the only cover option for the army's most expensive models, which can never be Hidden, and it comes up often on objectives.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:2278-2290, :1087-1104, :2305-2311
  - 40k/autoloads/TerrainManager.gd:1403-1416 (per-attacker not-fully-visible test)
  - YouTube 1SRkN4Drhs4 @52:00 (Play On Tabletop): “because you're not an infantry, so you have to be obscured by the terrain itself” [F030]
  - YouTube HQ0sQa37uHA @13:00 (Planet 40K): “as it's a monster, you're not going to be getting the hidden keyword” [F001]
  - https://www.warhammer-community.com/en-gb/articles/xlppkx5s/new40k-take-cover-with-updated-terrain-rules/ (search snippet: vehicles and monsters can sit behind ruins, trees and rubble to get the benefit of cover)
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-terrain-and-objectives/ (search snippet: a VEHICLE/MONSTER inside the area cannot claim cover from it; it needs intervening terrain)
- **Found by:** core-rules, web, first-principles, youtube

#### SUR-09 — Stage as far forward as possible while out of line of sight

In the opening rounds, move units to the far side of mid-board obscuring or Solid terrain from every enemy gun, as far forward as they can go while staying unseen. They cannot be shot or overwatched now, yet threaten objectives and charges next turn. This includes vehicles, monsters and jump/melee units that cannot use Hidden, and it also physically occupies the staging space the opponent wants.

- **When:** Use in rounds 1-2, or the turn before a strike, against a shooting army or when going first. The unit must not be needed on an objective this turn, and from the staging point its next-turn move plus charge or weapon reach must still cover its targets or objectives.
- **Units:** All; especially melee units, jump-pack infantry, fast units, vehicles and monsters
- **Move type:** Normal Move / Advance (if it will not charge or act this turn anyway)
- **11e rules (verified):** 13.10/13.11 (docs/rules/40k_11th_edition_core_rules.txt:2305-2316). 15.09: snap shooting needs a visible target within 24″ (:2749-2760). 11.02: a charge next turn needs the target within 12″ (:1603-1625). The rules mechanics are verified; 'this is the default opening' is player opinion (ai_learnings.json F005, medium confidence).
- **AI today (partial):** Only at deployment: _score_terrain_for_role (40k/scripts/AIDecisionMaker.gd:5594-5640) rewards melee units for forward line-of-sight-blocking terrain. In movement, round-1/2 urgency (B05) and objective trips choose destinations, and only the unscored cover nudge (:14817-14877) can angle the endpoint behind a polygon. There is no 'forward-most unseen point' candidate.
- **Engine support:** The same line-of-sight probes as SUR-02 (TerrainManager.model_visible_11e :1201; LineOfSightManager.calculate_visibility_grid_to_target :340). _evaluate_all_objectives (AIDecisionMaker.gd:8926) and the charge-intent data (B04 :3773-3946) value next-turn reach. NEW: a search over points behind obscuring areas that maximises forward progress and next-turn reach, subject to zero visible enemy ranged threat.
- **Value (high):** The corpus calls it the default opening. It combines survival with tempo and is the main way vehicles and melee units cross the board.
- **Evidence:**
  - YouTube -Bh3n-_Tpfs @61:00 (40K Fireside): “move block your opponent from touching the middle ruin and staging your army behind it” [F005]
  - YouTube mX7VBM9qJjY @07:00 (Auspex Tactics): “staged as far forward as possible but out of line of sight” [F005]
  - YouTube 6Lgr1hUGsgw @14:00 (Master Crafted): “we're behind it, we're hidden, they can't see us, but at least we know that we're taking up the space” [F005]
  - YouTube 1SRkN4Drhs4 @18:00 (Play On Tabletop): “my jumpack intercessors will move to stage behind this terrain ... I just don't want to be shot” [F005]
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-moving-and-the-movement-phase/ (search snippet: hiding behind terrain is a more reliable way to advance)
  - 40k/autoloads/TerrainManager.gd:1169, :1201
  - _…and 7 more_
- **Absorbed duplicates:** OBJ-11 (Stage for next turn's strike: end out of the enemy's reach and sight but inside your own next-turn reach)
- **Found by:** youtube, core-rules, first-principles, web

#### SUR-12 — Go dark: hold fire in light or dense terrain to keep or reset Hidden

Plan the turn so a unit that can be Hidden deliberately makes no ranged attacks. It stays in, or moves into or within, a dense area to a spot where it has nothing worth shooting, because firing forfeits Hidden for this turn AND the next (the opponent's coming turn). Reset variant: a unit that shot last turn is Hidden again in the opponent's turn only if it skips shooting in our turn in between. Units whose abilities say their attacks do not prevent them being hidden (Shadow Masters) shoot instead.

- **When:** Use when the unit is or will be Hidden, its best shot this turn is low value, it holds an objective or a backfield position, and a large share of enemy shooters are outside detection range, so the immunity being given up is large. Drop it when the unit's expected damage is significant.
- **Units:** INFANTRY/BEASTS/SWARM objective holders, screens and backfield shooters; Phobos/Scout units with Shadow Masters are the exception
- **Move type:** Remain Stationary, or Normal Move into dense terrain, paired with skipping the unit in the Shooting phase
- **11e rules (corrected):** 13.09: 'did not make one or more ranged attacks during this turn or during the previous turn' (docs/rules/40k_11th_edition_core_rules.txt:2292-2303). Engine stamp: flags.last_shot_idx, hidden again only when delta ≥ 2 (40k/autoloads/TerrainManager.gd:1014-1026). Shadow Masters exception (.llm/codex_11e_wahapedia/RULINGS.md:356). Inference, not validated: under 15.08/15.09 a Fire Overwatch is the unit shooting as described in Making Attacks (:2735-2760), so it should also forfeit Hidden, but the engine stamps only Shooting-phase shots (RULINGS.md:356).
  - _Skeptic:_ Hidden works in light OR dense terrain areas (13.09 errata, errata_faq:529), so 'in dense terrain' is too narrow. The Overwatch inference is supported by the text: snap shooting is the unit shooting as in Making Attacks (15.09 :2754-2755), i.e. ranged attacks, which forfeits Hidden this turn and the next (13.09 :2298-2299). 13.11.01 adds that a unit that shot cannot go to ground, even with an ability that lets it shoot and stay hidden (errata_faq:539). In the first turn the 'previous turn' condition is treated as met (errata_faq:533). — 40k_11th_edition_errata_faq_commentary.md:529, :533, :539; 40k_11th_edition_core_rules.txt:2298-2299, 2749-2755
  - _Errata check:_ Hidden works in a terrain area with a light OR dense feature, not dense only (13.09 errata), and in the first turn the 'previous turn' condition counts as met (13.09.01). Holding fire also keeps Gone to Ground (-3″ detection range against attackers whose view is blocked by intervening dense features), which a unit that shot this turn or last turn always loses, even if an ability like Shadow Masters lets it shoot and stay hidden (13.11.01 Designer's Note). — 13.09 errata; Commentary 13.09.01 Hidden and the First Turn; Commentary 13.11.01 Gone to Ground
- **AI today (none):** The shooting-phase hold-fire branch (40k/scripts/AIDecisionMaker.gd:16773-16800) fires only when _hidden_forfeit_cost (:28592-28610) is above 0, and HIDDEN_FORFEIT_PENALTY = 0.0 (:2638). Nothing on the movement side moves a unit into dense terrain specifically to go silent.
- **Engine support:** _hidden_forfeit_cost (:28592), _unit_is_currently_hidden (:28530), and TerrainManager.is_model_hidden (:999) with the last_shot_idx stamp. NEW: couple the movement candidate (into or within a dense area) with the shooting decision (skip), valued as next-turn immunity against this turn's expected damage.
- **Value (medium):** It is a corpus-confirmed two-turn trade (F002) and is already implemented but switched off. It is mostly a shooting decision.
- **Evidence:**
  - YouTube TJQWtTZiP1g @58:00 (Zeeto): “as soon as you give up hidden, you shoot a ball across the map ... you've got the 15 inch hidden anyway” [F002]
  - YouTube k-IMme1pngY @42:00 (Mid Table Tactics): “They're not going to be hidden though because they are probably going to shoot” [F002]
  - YouTube VqwMdS9MuIY @186:00 (TacticalTortoise 40k): “I'm hidden in the line like this cuz I just got to shoot there ... not hidden cuz they're shooting” [F002]
  - YouTube f_z0hvW0VMk @49:00 (Proxy Hammer): “you don't have to move out into the open ... remain hidden even while shooting” [F002]
  - 40k/autoloads/TerrainManager.gd:1014-1026; .llm/codex_11e_wahapedia/RULINGS.md:356
  - 40k/tests/bench_baselines/2026-08-06_youtube_findings_ab.md:111-120 (hold-fire SKIP_UNIT path exercised in ai_hidden_awareness_11e.json)
- **Found by:** youtube

#### SUR-19 — Stay outside distance-gated enemy bonus bands (half range, Explosives 8″, TOWERING 12″)

Deny enemy bonuses that switch on by distance when targets are selected. [MELTA X] adds X damage, and [RAPID FIRE X] adds X attacks, if the target unit is within half range. The EXPLOSIVES stratagem (six D6, each 4+ is a mortal wound) needs a visible, unengaged target within 8″ of an EXPLOSIVES/GRENADES model whose unit did not Advance. A TOWERING attacker gets Plunging Fire (+1 BS, cancelling cover) within 12″. Keep the closest model of a valuable unit beyond enemy M + band, or screen the approach. The enemy moves before it shoots.

- **When:** Use for our vehicles and monsters against melta units (including melta arriving from reserves), for elite infantry against rapid-fire blobs, for any unit against EXPLOSIVES/GRENADES units when the opponent has CP, and for ground units against TOWERING models. It is most achievable against slow or stationary enemy units (heavy weapons, artillery).
- **Units:** VEHICLE, MONSTER, elite multi-wound infantry; any ground-level unit against TOWERING attackers
- **Move type:** Normal Move / Advance / Remain Stationary
- **11e rules (verified):** 24.25 [MELTA] (docs/rules/40k_11th_edition_core_rules.txt:3833-3848) and 24.30 [RAPID FIRE] (:3896-3908): half range is judged at the Select Targets step. 15.05 EXPLOSIVES (:2651-2671). 22.05 PLUNGING FIRE (:3453-3462). Engine: half range is measured from each firing model to the closest target model (40k/autoloads/RulesEngine.gd:2343-2366); TerrainManager.plunging_fire_applies (:1425-1442). This corrects first-principles#5 and #12, which said these texts are not in the local sources: they are.
- **AI today (none):** _get_unit_half_range_data (40k/scripts/AIDecisionMaker.gd:13669-13754) and the T7-30 blend (:7550-7572) are offensive only. The movement planner has no TOWERING, Plunging Fire or Explosives term (no matches in AIDecisionMaker.gd); the Explosives logic covers only our own stratagem use (:16450-16453).
- **Engine support:** RulesEngine.count_models_in_half_range (:11812), is_target_within_range_inches (:10122) and TerrainManager.plunging_fire_applies (:1425); the weapon-keyword parsing from _get_unit_half_range_data (:13669) applied to enemy units. NEW: per-enemy bonus-band radii (enemy M + band) added to the threat model, valued at the bonus damage.
- **Value (medium):** Melta half range can double the damage against our most expensive models, but the band is small and often unavoidable. It is cheap to add to the threat model.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:3833-3848, :3896-3908, :2651-2671, :3453-3462
  - 40k/autoloads/RulesEngine.gd:2343-2366 (half range measured to the closest model)
  - 40k/autoloads/TerrainManager.gd:1425-1442 plunging_fire_applies
  - 40k/scripts/AIDecisionMaker.gd:13669 _get_unit_half_range_data (used offensively only)
  - https://www.tabletopbattles.com/40k-competitive-innovations-in-11th-assault-phase-pt-2 (search snippet: screening an opponent out of rapid-fire range matters)
- **Found by:** core-rules, web, first-principles

#### SUR-20 — Tuck the attached CHARACTER model where the main shooters cannot see it

When moving an attached unit, place the leader or support CHARACTER model behind terrain or on the far side of the unit, so the enemy's [PRECISION] shooters cannot see that model even if the bodyguards are visible. [PRECISION] can only promote a CHARACTER allocation group that is visible to an attacking model. This protects the leader's buffs and denies Assassination.

- **When:** Use when the enemy has [PRECISION] ranged weapons or snipers, when the leader carries key buffs, or when Assassination is in play. It matters mostly against ranged Precision; in melee the character is usually visible.
- **Units:** Attached units (Leader or Support characters)
- **Move type:** Normal Move (per-model placement)
- **11e rules (verified):** 24.28 [PRECISION] (docs/rules/40k_11th_edition_core_rules.txt:3856-3870): only CHARACTER models visible to one or more attacking models can be picked. 05.03: CHARACTER groups otherwise go last (:783-800). The engine now gates Precision on per-model visibility, including Hidden and line of sight (RulesEngine._precision_group_11e / _character_group_visible_to_attackers, 40k/autoloads/RulesEngine.gd:3978-4027). The 'does not check visibility' row in docs/rules/11th_edition_delta_audit.md:196 is stale.
- **AI today (none):** Model destinations come from the placement ladder (40k/scripts/AIDecisionMaker.gd:14520-14722, :15405), which optimises legality, overlap and coherency only. There is no per-model role placement.
- **Engine support:** RulesEngine._character_group_visible_to_attackers (:4000) with probe positions; TerrainManager.model_visible_11e (:1201). NEW: a post-pass on the formation that puts the CHARACTER model in the slot least visible to enemy Precision weapons.
- **Value (medium):** It protects leader buffs and Assassination VP and is cheap post-processing of existing formations, but it only matters against Precision.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:3856-3870
  - 40k/autoloads/RulesEngine.gd:3978-4027 (visibility-gated Precision)
  - https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics/Necrons (search snippet: keep the leader model behind cover; Precision cannot be allocated to a leader the attacking unit cannot see)
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-special-unit-types/ (Precision can strip Leader effects)
- **Found by:** web

#### SUR-13 — Stand off outside enemy shooting reach (out-range or break contact)

End beyond each dangerous enemy shooter's next-turn reach: its M (plus D6 only for an Advance with [ASSAULT] weapons) plus weapon range. Ideally the enemy stays inside our own range (out-ranging). When we have nothing to shoot, simply Advance away to break contact. Distances are measured between the closest models.

- **When:** Use when our range or speed beats theirs (long guns against short-ranged shooters, fast units against slow ones), and for units that must survive (Beacon holder, characters, damaged units) with no option to break line of sight. If the unit has no target this turn, Advancing costs nothing. It is usually infeasible against 36-48″ guns; use SUR-02 then.
- **Units:** Long-ranged shooters, fast units, characters, damaged units
- **Move type:** Normal Move / Advance
- **11e rules (verified):** 04.02: targets must be within range and visible (docs/rules/40k_11th_edition_core_rules.txt:628-642). 09.05/09.06 (:1390-1415). 10.05: after an Advance only [ASSAULT] weapons can shoot (:1506-1520). 01.04: measure to the closest part of the base (:163-170).
- **AI today (partial):** The threat model has a shooting zone equal to the enemy's max weapon range around its centroid, without enemy movement (40k/scripts/AIDecisionMaker.gd:28718). It is weighted by THREAT_SHOOTING_PENALTY 0.5 (:2587) inside the threat dodge (:28892-28990) and objective scoring (:10285). The MOV-1 clamp and firing-position preservation keep our own targets in range (:14476-14484, :7574-7593). No candidate maximises our reach minus theirs, and none retreats to break contact.
- **Engine support:** RulesEngine.max_ranged_weapon_range_inches (:6693) for both sides (it includes attached characters and codex range bonuses); unit_within_weapon_reach (:6718); _calculate_enemy_threat_data (:28695) once the shooting radius includes enemy M (and D6 for Assault). NEW: 'stand-off band' candidates between the enemy's reach and our own range.
- **Value (medium):** It is decisive in asymmetric matchups and for scoring-critical units, but often infeasible against long-range armies.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:628-642, :1390-1415, :1506-1520
  - 40k/scripts/AIDecisionMaker.gd:28718 (shooting threat = enemy max range; enemy move not added) and :2587 (THREAT_SHOOTING_PENALTY 0.5)
  - https://grimhammertactics.com/40k-tactics-mastering-movement-in-warhammer-40k/ (pre-measure firing lanes and threat ranges)
  - https://www.tabletopbattles.com/start-competing-40k-deployment-tactics-surviving-turn-zero/ (search snippet: 36″ threat ranges are manageable; ~48″ makes avoidance near impossible)
- **Found by:** core-rules, web, first-principles

#### SUR-14 — Keep standalone characters out of sight or reach

11e has no Look Out, Sir. A CHARACTER that is not part of an attached unit (never attached, bodyguard destroyed, or unable to attach) is an ordinary target unless it has Lone Operative. Move it Hidden, out of line of sight, into a transport, or beyond enemy reach, and keep it near the units it buffs only if it can still stay unseen there.

- **When:** Use for standalone characters with valuable auras or buffs and for leaders whose bodyguard died, and whenever the opponent scores Assassination (3 VP per CHARACTER model, +1 if W4+) or fields [PRECISION] snipers.
- **Units:** CHARACTER units not in an attached unit and without Lone Operative
- **Move type:** Normal Move / Advance / Embark
- **11e rules (verified):** The 11e core text has no Look Out, Sir rule (grep of docs/rules/40k_11th_edition_core_rules.txt), and .llm/rules-audit.md:17 notes that standalone protection lives only in Lone Operative. 24.24 Lone Operative (:3813-3828). 19.01: an attached unit is a single unit for all rules purposes (:3094-3101). 05.03: CHARACTER groups come last only within the target unit (:783-800). 24.28 [PRECISION] (:3856-3870). Assassination card: 40k/data/40kdc/missionCards.json:2272.
- **AI today (partial):** _evaluate_position_threat multiplies threat by 1.5 for CHARACTER units (40k/scripts/AIDecisionMaker.gd:28805-28809, :28865-28867). Screen-protect sends a cheap unit 60% of the way from an unattached character toward the nearest enemy (+50 priority, :15055-15076). Both are distance-only, and models never block line of sight in the engine, so the screen does nothing against shooting.
- **Engine support:** The destination queries from SUR-01/02/16. The attachment fields used by AIAbilityAnalyzer.gd:409-420 (attached_to, attachment_data.attached_characters) detect an unattached character. NEW: a CHARACTER multiplier on visible enemy damage (line-of-sight based) instead of on distance.
- **Value (medium):** Characters carry buffs and VP, and standalone ones die fast, but each army has only a few of them.
- **Evidence:**
  - .llm/rules-audit.md:17 (Look Out Sir removed; standalone protection only via Lone Operative)
  - docs/rules/40k_11th_edition_core_rules.txt:783-800, :3094-3101, :3813-3828
  - 40k/data/40kdc/missionCards.json:2272 (assassination: 3 VP per character model, +1 for W4+, either turn)
  - 40k/scripts/AIDecisionMaker.gd:28805-28809 (CHARACTER ×1.5 threat multiplier), :15055-15076 (screen-protect priority for unattached characters)
- **Found by:** core-rules, first-principles

#### SUR-15 — Lone Operative: end beyond the range it can be seen from (12″ or X″)

An unattached LONE OPERATIVE unit is not visible to enemy models more than 12″ (or its X″) away and cannot be targeted by [INDIRECT FIRE] from beyond that range. End every move so that no enemy model that could shoot it next turn can get within that range (enemy M + 12″/X″, between the closest models), or so that terrain blocks their view, while it still spots, scores, performs actions or snipes. It does not stop charges.

- **When:** Use on every move of an unattached Lone Operative (assassins, lone characters, snipers).
- **Units:** LONE OPERATIVE units that are not part of an attached unit
- **Move type:** Normal Move / Advance / Remain Stationary
- **11e rules (corrected):** 24.24 LONE OPERATIVE and Lone Operative X″ (docs/rules/40k_11th_edition_core_rules.txt:3813-3828). Engine: RulesEngine.has_lone_operative (40k/autoloads/RulesEngine.gd:9829-9853; includes the X″ variant and conditional grants) and get_lone_operative_range (:9953-9969); docs/rules/11th_edition_delta_audit.md:193 marks it done.
  - _Errata check:_ Lone Operative is not limited to unattached units: an attached unit in which every model has it also benefits, with the highest X among its models on the battlefield applied to the whole unit. It also becomes active again once an attached unit is reduced to only Lone Operative models (e.g. its bodyguard is destroyed), and a Lone Operative range can never be modified below 9″ or above 30″. — Commentary 24.24.01 Attached units and Lone Operative; Commentary 02.02.01 Modifiers
- **AI today (partial):** The T7-11 override (40k/scripts/AIDecisionMaker.gd:7432-7465): if the nearest enemy centroid is within 12″ + M, the unit retreats to the candidate point (directly away, or ±30°/60°) that is more than 12.5″ from every enemy centroid and closest to the objective (_get_lone_operative_safe_position :14010-14076); otherwise it holds. Problems: the range is a fixed 12″ (:7437) that ignores Lone Operative X″; centroid-to-centroid distances (:13999-14008) overstate the real model-to-model gap; enemy movement is not added; and AIAbilityAnalyzer.has_lone_operative only matches an ability named exactly 'lone operative' (AIAbilityAnalyzer.gd:400-407), so X″ variants and conditional grants are missed. It is an override, not a scored candidate.
- **Engine support:** RulesEngine.get_lone_operative_range (:9953) and has_lone_operative (:9829); Measurement.model_to_model_distance_px for closest-model distances; TerrainManager.model_visible_11e as a line-of-sight fallback. NEW: score Lone Operative candidates by the enemy models able to get within X″ with line of sight next turn, combined with the unit's firing or scoring value.
- **Value (medium):** Few units have it, but the protection is total when respected. The existing override is close and needs fixes rather than a new mechanism.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:3813-3828
  - 40k/autoloads/RulesEngine.gd:9829-9853, :9953-9969
  - 40k/scripts/AIDecisionMaker.gd:7432-7465, :13999-14076; 40k/scripts/AIAbilityAnalyzer.gd:400-407
  - https://warhammerguild.com/guides/40k-11th-edition-cheat-sheet/ (search snippet: cannot be seen from more than 12″ unless attached)
  - 40k/autoloads/RulesEngine.gd:9949-9969 (Lone Operative visibility gate)
  - 40k/autoloads/RulesEngine.gd:9953 (get_lone_operative_range returns X)
- **Absorbed duplicates:** COO-32 (Keep Lone Operative spacing while staying in your own range)
- **Found by:** core-rules, web, first-principles

#### SUR-17 — Choose Desperate Escape (or take to the skies) to escape through enemy models

When an Ordered Retreat cannot reach a legal or useful unengaged spot (the unit is wrapped, or the safe spot or objective lies beyond the enemy), choose Desperate Escape. Models may then move through enemy models. The cost is one hazard roll per model before moving (1-2 fails: 1 mortal wound, or 3 if every model is a MONSTER/VEHICLE) and, if the unit was not already battle-shocked, a battle-shock roll afterwards. It is mandatory for battle-shocked units, so for them the real choice is escape vs stay (SUR-06/SUR-18). A FLY unit can instead take to the skies for the fall-back (-2″, or no penalty with HOVER) and move through all models and terrain with no hazard rolls.

- **When:** Use for surrounded units, for destinations reachable only through the enemy, and for expendable or numerous models where losing about a third to hazards costs less than staying. For battle-shocked units, use it only if leaving still beats staying. FLY units should prefer taking to the skies.
- **Units:** Any engaged unit; especially FLY units (take to the skies) and hordes; avoid with small elite units
- **Move type:** Fall Back (Desperate Escape mode, or FLY taking to the skies)
- **11e rules (corrected):** 09.07 fall-back modes (docs/rules/40k_11th_edition_core_rules.txt:1417-1441). 06.03 hazard rolls (:1067-1074). 01.07 battle-shock (:197-222). 21.03: a FLYING unit can take to the skies on a fall-back move: -2″, and it moves through all models and terrain (:3358-3375). 24.17 HOVER (:3771-3781). Engine: hazard rolls in FallBackMove.before_moving (40k/scripts/rules/movetypes/FallBackMove.gd:74-115) and the battle-shock roll in after_moving (:116-135); MoveType.take_to_skies_modifier (MoveType.gd:95).
  - _Errata check:_ Desperate Escape is mandatory not only for battle-shocked units but whenever an enemy stratagem or ability instructs a Desperate Escape test, and any penalty to that test applies to every per-model hazard roll (a -1 makes 1-3 fail). In those cases a FLY unit that takes to the skies still makes the hazard rolls; it avoids them only when it can select Ordered Retreat. — Commentary 09.07.01 Desperate Escape
- **AI today (partial):** Desperate Escape is used only as a retry after an Ordered Retreat fails to stage (40k/autoloads/AIPlayer.gd:2823-2852, payload fall_back_mode=desperate_escape, same destinations), plus narration when the mode is forced on a battle-shocked unit (40k/scripts/AIDecisionMaker.gd:12146-12153). It is never chosen to cross enemies on purpose, and take to the skies is never sent (no take_to_skies in AIDecisionMaker.gd or AIPlayer.gd).
- **Engine support:** FallBackMove.select_mode (:52) and before_moving (:74); the BEGIN_FALL_BACK payload fall_back_mode; SET_TAKE_TO_SKIES / payload.take_to_skies (MoveType.take_to_skies_modifier :95). NEW: a destination search that allows paths through enemy models, priced by expected hazard losses (about a third of the hazard rolls fail, applied per model's wounds) plus battle-shock odds from Ld, or at zero cost for FLY units taking to the skies.
- **Value (medium):** It comes up fairly often for wrapped hordes and battle-shocked units, and FLY escapes are free. Today the AI only stumbles into it.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1417-1441, :1067-1074, :3358-3375
  - 40k/scripts/rules/movetypes/FallBackMove.gd:74-135
  - 40k/autoloads/AIPlayer.gd:2823-2852 (Desperate Escape used only as a retry)
  - YouTube aQsog-fkQJ8 @98:00 (Maelstrom Gaming Studios - Tyranids): “no, we'll fall back and we'll take our hazardous roles. Ones and twos, they die” [F017]
  - YouTube aQsog-fkQJ8 @98:00 (Maelstrom Gaming Studios - Tyranids, F017): 'no, we'll fall back and we'll take our hazardous roles. Ones and twos, they die'
  - 40k/phases/MovementPhase.gd:2911-2925 (fall_back_mode payload; Desperate Escape can be chosen); the SET_TAKE_TO_SKIES validator accepts FALL_BACK
  - _…and 1 more_
- **Absorbed duplicates:** COO-39 (Escape a wrap by falling back through enemy models)
- **Found by:** core-rules, youtube, first-principles, web

#### SUR-22 — Shape the unit defensively: compact, near edge pulled back, all models in the area

Arrange the models for defence. Keep the unit compact: coherency is 2″ to one other model and 9″ to every model, and a unit that casualties from Overwatch, hazard rolls or shooting split into two groups loses models at the end of the turn. Pull back the models closest to the enemy, because charge, Overwatch (24″), half-range and detection distances are all measured to the closest model. Keep every model inside the terrain area when relying on cover or Hidden. Spreading out buys nothing in 11e: the defender orders the allocation groups, [BLAST] counts models rather than spacing, and Deadly Demise and Explosives hit whole units.

- **When:** Use on every move of a multi-model unit that will be exposed: large units, screens, objective chains, and units near the edge of a threat band.
- **Units:** Multi-model units
- **Move type:** Any move (per-model placement)
- **11e rules (corrected):** 03.03 COHERENCY and Regaining Coherency (docs/rules/40k_11th_edition_core_rules.txt:518-537). 05.03: the defender declares the allocation order (:783-800). 24.05 [BLAST] counts models in the target unit (:3595-3610). 24.08 Deadly Demise hits each unit (:3670-3690). 01.04: measure to the closest part of the base (:163-170). 13.08/13.09 require every model. Engine: PhaseManager._enforce_coherency_11e (40k/autoloads/PhaseManager.gd:576); AttackSequence.check_unit_coherency (40k/scripts/rules/AttackSequence.gd:229); GameConstants.coherency_envelope_inches (GameConstants.gd:76).
  - _Errata check:_ Hidden (13.09) is judged per model, and a unit counts as a 'hidden unit' if just one model is hidden (Commentary 01.02.07), so 13.09 does not itself require every model. Keeping every model in the area still matters because the unit can be targeted if any one model is visible (06.01); cover does need every model to qualify, but this is judged separately for each attacking model (FAQ 13.08). — Commentary 01.02.07 Describing Units; FAQ 13.08 Benefit of Cover
- **AI today (none):** The placement ladder (40k/scripts/AIDecisionMaker.gd:14520-14722) and AIPlayer staging (40k/autoloads/AIPlayer.gd:2733-2867) optimise legality and coherency only. There is no deliberate compact or defensive formation and no pulling back of the near edge.
- **Engine support:** AttackSequence.check_unit_coherency (:229) to test fragility (e.g. models whose loss would split the unit); _try_move_with_collision_check (AIDecisionMaker.gd:15405) as the executor. NEW: a formation scorer covering connectivity under k casualties, closest-model distance to threats, and an all-models-in-area flag.
- **Value (low):** Small, steady gains: coherency losses are rare and the other distance effects are second-order. The offensive half of first-principles#79 (pushing models into range, objectives or auras) belongs to the shaping bucket.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:518-537, :783-800, :3595-3610
  - 40k/autoloads/PhaseManager.gd:576; 40k/scripts/rules/AttackSequence.gd:229-260
  - 40k/autoloads/RulesEngine.gd:2343-2366 (half range measured to the closest target model)
  - Web search snippet (11e screening results): all models within a unit now have to be within 9″ of each other, which makes thorough screening more difficult
- **Found by:** core-rules, first-principles

#### SUR-23 — Stay unseen by every enemy unit to deny indirect-fire spotting

Enemy [INDIRECT FIRE] weapons hit only on unmodified 6s, improving to 4+ only if the firing unit remained stationary AND one or more of its friendly units can see the target. A unit that ends unseen by ALL enemy units (out of every enemy's line of sight, or Hidden beyond every enemy model's detection range) keeps enemy artillery hitting on 6s. A Lone Operative cannot be targeted by indirect fire at all from beyond its range.

- **When:** Use when the opponent fields stationary artillery or mortars, our unit is a likely indirect target (dense infantry, objective holders), and a spot unseen from all sides is reachable.
- **Units:** All (most often Hidden infantry)
- **Move type:** Normal Move / Advance / Remain Stationary
- **11e rules (verified):** 10.07 INDIRECT SHOOTING (docs/rules/40k_11th_edition_core_rules.txt:1549-1574): the target has cover; no hit re-rolls; an unmodified 1-5 fails, unless the unit remained stationary and the target is visible to one or more friendly units, in which case 1-3 fails. 24.24 Lone Operative against indirect fire (:3813-3828). Engine: RulesEngine._indirect_hit_fail_band_11e (40k/autoloads/RulesEngine.gd:6594-6605) returns 3 only when the shooter remained stationary and some friendly unit has line of sight; IndirectShooting.has_spotter (40k/scripts/rules/shootingtypes/IndirectShooting.gd:47).
- **AI today (none):** The movement planner has no spotter or indirect-fire term (40k/scripts/AIDecisionMaker.gd threat model :28695-28880 is distance-only and treats indirect weapons as ordinary range).
- **Engine support:** RulesEngine._has_los_to_target_unit (:6607) and unit_sight_line (:6641) for every enemy unit against a probe board; TerrainManager.hidden_model_visible_to (:1047). NEW: a 'visible to any enemy unit' flag at the destination, weighted by the enemy's stationary [INDIRECT FIRE] output.
- **Value (low):** It matters only against artillery-heavy lists and only when the unit can be unseen by every enemy unit; often it is a by-product of SUR-01/02.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1549-1574
  - 40k/autoloads/RulesEngine.gd:6594-6605
  - docs/rules/11th_edition_delta_audit.md:117 (10.07 resolved; band live in both resolve loops)
  - https://www.40k.app/rules/10-shooting-phase (search snippet)
- **Found by:** core-rules

#### SUR-25 — Keep bystander units clear of melee scrums (more than 5″, at least more than 3″)

Shooters and characters parked next to an ongoing combat can be dragged into it in the Fight phase. An enemy unit that was engaged at the start of the Fight step but is now unengaged may make an Overrun fight, whose extra pile-in can target our units within 5″. An enemy unit that fought may consolidate, and if it is within 3″ of our units it must then use Engaging Consolidation to engage them. Our bystander is then locked for the next turn: it must fall back or use only close-quarters shooting.

- **When:** Use when moving shooters, characters or objective holders near a combat that will continue in either player's Fight phase.
- **Units:** Shooting units, characters, objective holders
- **Move type:** End positions of Normal / Advance moves (adjacent consequence: Fight-phase pile-in and consolidation)
- **11e rules (corrected):** 12.04: a unit is eligible to fight if it is engaged or was engaged at the start of the step (docs/rules/40k_11th_edition_core_rules.txt:1819-1824). 12.06 OVERRUN FIGHT: one additional pile-in (:1866-1877). 12.03: an unengaged unit's pile-in targets enemy units within 5″ (:1737-1766). 12.07/12.08: consolidating is optional, but a unit that consolidates within 3″ of enemy units must use Engaging Consolidation (:1725-1728, :1934-1990). CORRECTED: core-rules#18 said the enemy 'must' consolidate into us; the move itself is optional, only its mode is mandatory.
  - _Errata check:_ Engaging Consolidation applies only to an unengaged enemy unit within 3″; a still-engaged enemy uses Ongoing Consolidation, and its 3″ move can also end engaged with a nearby bystander. Per the 12.08 errata, after either mode each of our units it ends engaged with that has not fought this phase must be selected to fight, so a dragged-in bystander fights back at once but is still locked in combat afterwards. — 12.08 errata (Consolidation Move, After Moving, Ongoing Consolidation)
- **AI today (none):** The movement threat model (40k/scripts/AIDecisionMaker.gd:28794-28880) has no pile-in or consolidation band around engaged enemy units; bystanders are placed only by objective, screen and threat-dodge logic.
- **Engine support:** The ConsolidationMove and PileInMove templates for reach; RulesEngine.units_in_engagement_range (:18481) to find enemy units that will fight. NEW: 5″/3″ bands around engaged enemy units in the threat model for units that are not melee-focused.
- **Value (low):** It is an occasional loss of a shooting phase, limited to units parked next to fights.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1725-1728 (you don't have to pile in or consolidate), :1737-1766, :1819-1824, :1866-1877, :1934-1990
  - docs/rules/11th_edition_missions_gdm2026.md:195-199 (Engaging Consolidation is 3″)
  - 40k/scripts/rules/movetypes/ConsolidationMove.gd; 40k/scripts/rules/movetypes/PileInMove.gd
- **Found by:** core-rules, web

#### SUR-26 — Keep friendly units more than 6″ from our own Deadly Demise models that may die

When a Deadly Demise model is destroyed, on a 6 every unit within 6″, friend or foe, suffers X mortal wounds. This happens after any passengers have made their emergency disembark, which leaves them inside the radius. Do not park fragile characters, infantry or other Deadly Demise vehicles (chain explosions) next to our damaged Deadly Demise vehicles and monsters. The mirror move, driving a dying Deadly Demise model into enemies, is the existing ram override.

- **When:** Use when our DEADLY DEMISE model is damaged and likely to die this round, especially with D3/D6 values. Give it low weight, since it fires only on a 6.
- **Units:** Friendly units near our own DEADLY DEMISE VEHICLE/MONSTER models
- **Move type:** Normal Move / Advance
- **11e rules (verified):** 24.08 DEADLY DEMISE (docs/rules/40k_11th_edition_core_rules.txt:3670-3690): on a 6, each unit within 6″ suffers X mortal wounds, after emergency disembarks. 18.05: passengers are set up wholly within 6″ (:3061-3078). This corrects first-principles#8: the 11e wording is in the local sources.
- **AI today (none):** The only Deadly Demise movement logic is the doomed-vehicle ram toward enemies (40k/scripts/AIDecisionMaker.gd:7466-7489), and it ignores friendly units within 6″.
- **Engine support:** AIAbilityAnalyzer.has_deadly_demise / get_deadly_demise_value / is_unit_doomed (AIAbilityAnalyzer.gd:546, :559, :595). NEW: a friendly-proximity penalty of P(destroyed) × 1/6 × X × unit value.
- **Value (low):** It triggers only on a 6 and only next to damaged models, but it is trivial to add.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:3670-3690, :3061-3078
  - 40k/autoloads/RulesEngine.gd:16962, :17462 (Deadly Demise hits all units, friend and foe, within 6″)
  - 40k/scripts/AIDecisionMaker.gd:7466-7489 (ram override ignores friendly units)
  - https://www.newrecruit.eu/wiki/wh40k-11e/warhammer-40,000-11th-edition/rules/deadly-demise
- **Found by:** core-rules, web, first-principles

#### SUR-27 — Hug the escort to keep a conditional Lone Operative

Some characters and support pieces have Lone Operative only while within 3″ of a specified friendly unit: Ghazghkull (Da Grand Warlord's Ladz), Big Mek with Shokk Attack Gun (Support Shokka), Beastboss on Squigosaur and Mozrog (Boss of da Hunt, Beast Snagga Following), Wartrakks (Speednob Support, every model), a Dreadherder Big Mek near an ORKS WALKER, Techmarine and Iron Father Feirros near an ADEPTUS ASTARTES VEHICLE, Iron Priest near a SPACE WOLVES VEHICLE, and Guilliman (Leader of Astartes) near ADEPTUS ASTARTES INFANTRY. Move the escort first, then end the tethered model within 3″ of it. The intent is staying close to the escort, not staying away from the enemy.

- **When:** Use when the tethered unit is unattached and would otherwise be visible to enemy shooters. Prefer escorts that are themselves out of line of sight or Hidden.
- **Units:** Ghazghkull, Big Mek with SAG, Beastboss on Squigosaur, Mozrog, Wartrakks, Big Mek with Dreadherder, Techmarine, Iron Father Feirros, Iron Priest, Roboute Guilliman
- **Move type:** Normal Move (escort first, then the tethered unit) / Remain Stationary
- **11e rules (verified):** 24.24 (docs/rules/40k_11th_edition_core_rules.txt:3813-3828). Datasheet text: .llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:32, :192, :218, :228, :284; .llm/codex_11e_wahapedia/orks/RULES.md:130; .llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:141, :168, :178, :322, :536. Engine: RulesEngine.has_lone_operative evaluates the tether live (40k/autoloads/RulesEngine.gd:9829-9853), via OrkAbilities11e.conditional_lone_operative (40k/scripts/codex/orks/OrkAbilities11e.gd:986-1016), SWAbilities11e.gd:776 and SMAbilitiesA.gd:807.
- **AI today (none):** AIAbilityAnalyzer.has_lone_operative only matches an ability named exactly 'Lone Operative' (40k/scripts/AIAbilityAnalyzer.gd:400-407), so the T7-11 logic (AIDecisionMaker.gd:7432-7465) never sees these units, and nothing keeps them within 3″ of their escort.
- **Engine support:** RulesEngine.has_lone_operative (:9829) on a probe board; move-order control (B03, AIDecisionMaker.gd:7119-7147) to move the escort first. NEW: a tether constraint in the destination search.
- **Value (low):** Few, faction-specific units, but when it applies it is total protection from shooting beyond 12″.
- **Evidence:**
  - .llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:32 (“While this unit is within 3″ of another friendly Orks Infantry unit, this unit has Lone Operative.”)
  - .llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:178 (Techmarine: within 3″ of a friendly ADEPTUS ASTARTES VEHICLE)
  - 40k/scripts/codex/orks/OrkAbilities11e.gd:986-1016 conditional_lone_operative
  - 40k/scripts/AIAbilityAnalyzer.gd:400-407 (exact-name Lone Operative check)
- **Found by:** factions

#### SUR-28 — Spend a temporary defensive buff: accept an exposed route this turn

Defensive effects that last until the start of our next turn change how much exposure a move can accept. Examples: riled-up Orks (5+ InSv), Librarian Force Dome (4+ InSv), Tigurius Prescience (+1 Sv), and Dread Host GOLDEN LIGHT OF THE MOIRAIDES on ingress (-1 to hit against the unit and no snap shooting at it). While such a buff is active, or castable this Movement phase, take the open-ground route or the forward objective that would normally be too exposed.

- **When:** Use when the buff is active or will be cast this phase, the exposed route gains an objective, charge position or tempo, and the enemy's damage is mostly the kind the buff blunts (AP-heavy fire for an invulnerable save; any shooting for -1 to hit).
- **Units:** Riled-up Ork units, Librarians/Tigurius and their attached units, Dread Host Custodes arriving from reserves
- **Move type:** Normal Move / Advance / Reserves arrival (a modifier on the survival terms of other moves)
- **11e rules (verified):** Codex and datasheet text: Waaagh! riled up gives a 5+ InSv (.llm/codex_11e_wahapedia/orks/RULES.md:76); Force Dome gives a 4+ InSv until the start of your next turn (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:496); Prescience gives +1 Sv (:440); GOLDEN LIGHT OF THE MOIRAIDES (.llm/codex_11e_wahapedia/custodes/RULES.md:233).
- **AI today (none):** The AI casts Prescience and Force Dome when an enemy is within 24″ (40k/scripts/codex/space_marines/SMAbilitiesB.gd:1818-1820), but the movement threat checks (B21, 40k/scripts/AIDecisionMaker.gd:7357-7391; _evaluate_position_threat :28794-28880) take no account of active invulnerable saves, save buffs or -1-to-hit effects.
- **Engine support:** Unit effect flags (riled up, InSv and save modifiers from the effect system); _evaluate_position_threat (:28794) could scale threat by an incoming-damage multiplier computed with the unit's current saves. NEW: survivability-aware threat weighting (expected damage instead of a distance-only danger rating).
- **Value (low):** It is faction-specific and only a weighting tweak; the bigger fix is a damage-based threat model.
- **Evidence:**
  - .llm/codex_11e_wahapedia/orks/RULES.md:76; .llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:440, :496; .llm/codex_11e_wahapedia/custodes/RULES.md:233
  - 40k/scripts/codex/space_marines/SMAbilitiesB.gd:1818-1820 (Prescience/Force Dome cast when an enemy is within 24″)
  - YouTube vLQTE5P6pJg @03:00 (Hubtown Hammer): “Turn two, the Orks used the Waagh, which turned out to be a great choice ... blunted by some hot five plus invulnerable” [F020]
- **Found by:** factions

#### SUR-29 — Deny Surveil the Foe: stay unseen or beyond 18″ of surveillers, or shelter under our decoyed objectives

When the opponent's primary is Surveil the Foe, their Surveil action in the Shooting phase tags one visible enemy unit within 18″ of the acting unit and pays 4 VP at the end of the turn, unless every surveilled unit is within range of an objective shielded by our operation markers. Deny it by ending our units unseen (out of line of sight or Hidden), or more than 18″ plus enemy M from their likely acting units. When we play Smoke and Mirrors, also park exposed units within range of our decoyed objectives whose markers survive, and keep enemy units from ending moves within range of them, since that scrubs the marker.

- **When:** Use when our primary is Smoke and Mirrors or the opponent's is Surveil the Foe. It is low priority against kill and objective intents.
- **Units:** Any; preferably the units that decoyed the objective
- **Move type:** Normal Move / Advance / Remain Stationary
- **11e rules (verified):** 40k/data/40kdc/missionCards.json: surveil-the-foe (:1757; text: 'surveils one visible enemy unit within 18 inches ... unless every one of them is within range of an objective shielded by operation markers') and smoke-and-mirrors (:1100); docs/rules/11th_edition_missions_gdm2026.md:134-141. ENGINE GAP: PrimaryMissionData11e.gd:276-283 notes that Surveil tagging is not implemented (warns once, scores 0 VP); the decoy-marker scrub is implemented (40k/autoloads/MissionManager.gd:1849-1864).
- **AI today (none):** No AI code references Surveil or decoy shelters, and the engine's Surveil award currently pays 0 VP (PrimaryMissionData11e.gd:280-283), so the intent has no in-engine payoff today.
- **Engine support:** MissionManager decoy state (MissionManager.gd:1645-1654, :1849-1864); TerrainManager.model_visible_11e (:1201) for the visibility half. NEW: needs the engine's Surveil action first, then a term that reads the opponent's primary.
- **Value (low):** It applies to one primary pairing, and the Surveil award scores 0 VP in this engine today.
- **Evidence:**
  - 40k/data/40kdc/missionCards.json:1757, :1100
  - docs/rules/11th_edition_missions_gdm2026.md:134-141
  - 40k/scripts/data/PrimaryMissionData11e.gd:276-291 (Surveil award 'approximate', tagging not implemented)
  - 40k/autoloads/MissionManager.gd:1849-1864 (decoy scrub when an enemy unit is in range)
- **Found by:** missions

#### SUR-30 — Perch infantry on a high terrain level out of reach of ground-bound enemies

Engagement needs 2″ horizontally AND 5″ vertically, and only INFANTRY/BEASTS/SWARM/FLY/MONSTER models may end a move on upper levels. Infantry more than 5″ up a ruin therefore cannot be charged by VEHICLE or MOUNTED models without FLY, and a unit with no model at ground level is immune to Plunging Fire.

- **When:** Use for infantry threatened mainly by vehicles, mounted units or other melee that cannot climb, when tall ruins are available. NOT REPRESENTABLE in this engine today: the board is 2D and has no live elevation.
- **Units:** INFANTRY, BEASTS, SWARM (FLY and MONSTER models can also perch)
- **Move type:** Normal Move (vertical climb)
- **11e rules (verified):** 03.04 ENGAGEMENT (docs/rules/40k_11th_edition_core_rules.txt:542-552). 13.06: ending a move on surfaces other than ground level (:2197-2210). 22.05: Plunging Fire needs a target with a model on ground level (:3453-3462). 11.04: a charge must end engaged (:1640-1666). Engine: elevation_inches is only ever read (TerrainManager.gd:1120-1121, :1430-1437; EnhancedLineOfSight.gd:120-121; RulesEngine.gd:6839-6841) and never written outside tests.
- **AI today (none):** There is no AI logic, and the engine cannot place models above ground level in live play.
- **Engine support:** None until the engine supports vertical placement; plunging_fire_applies (:1425) and the visibility code already read elevation_inches. NEW (engine first): a live elevation writer for moves onto upper floors.
- **Value (low):** It is legal and occasionally strong on the table, but cannot be executed in this engine.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:542-552, :2197-2210, :3453-3462
  - grep of 40k/ for elevation_inches writers: only tests/test_iss053_cover_plunging_11e.gd, tests/test_vision_map_agreement.gd, tests/test_hover_forecast.gd, tests/test_iss016_modifier_stack.gd
  - 40k/autoloads/TerrainManager.gd:1425-1442 plunging_fire_applies (reads elevation_inches)
- **Found by:** core-rules

#### SUR-N01 — Stay more than 6″ from enemy Deadly Demise models you are about to destroy _(added by completeness review)_

Before shooting or charging a wounded enemy DEADLY DEMISE model, end the moves of your fragile units more than 6″ from it: lone or attached characters, small elite squads, objective holders. Let durable or expendable units do the close work. When the model is destroyed, a 6 on one D6 inflicts X mortal wounds on every unit within 6″ of it, friend or foe, and a unit that kills it in melee is always inside the radius. The catalogue has the mirror (SUR-26, our own Deadly Demise models); the enemy side is missing.

- **When:** A wounded enemy model with Deadly Demise X (X = D3, D6 or more: tanks, Knights, big monsters) is likely to die this turn or in the enemy turn, and a fragile friendly unit could end within 6″ of it. Ignore it for Deadly Demise 1 or when only expendable units are near.
- **Units:** Characters, low-wound elite units and objective holders near enemy vehicles or monsters; melee units deciding whether to charge a doomed enemy vehicle
- **Move type:** Normal / Advance end position, plus the choice of which unit charges the vehicle
- **11e rules (verified):** 24.08 Deadly Demise: each time a model is destroyed, after any embarked units' emergency disembark, roll one D6; on a 6, each unit within 6″ suffers X mortal wounds (40k_11th_edition_core_rules.txt:3670-3700).
- **AI today (none):** Deadly Demise logic exists only for the AI's own doomed vehicles: the movement ram at AIDecisionMaker.gd:7466-7490 and the charge bonuses at :18629-18636 and :19397-19405. No movement or charge-target term prices ending within 6″ of an enemy Deadly Demise model the AI is about to kill.
- **Engine support:** RulesEngine.resolve_deadly_demise (RulesEngine.gd:16929) resolves it. AIAbilityAnalyzerData.has_deadly_demise, get_deadly_demise_value and is_unit_doomed (AIAbilityAnalyzer.gd:546, 559, 595) work on enemy unit dicts too. New: a destination penalty of about (1/6) × E[X] × P(model dies this turn) for each friendly unit ending within 6″, weighted up for characters.
- **Value (low):** A 1-in-6 event, but it can kill a character or strip an objective's OC, and it is cheap to price once the Deadly Demise values are read.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:3670-3700 (24.08)
  - SUR-26 in this catalogue covers only the friendly-model side of the same rule
- **Found by:** cross_bucket_critic

#### SUR-N02 — Keep an escape lane open behind units that may be charged _(added by completeness review)_

End units that are likely to be charged (shooters, transports, characters, vehicles) with clear ground behind them. Do not back them against the board edge, against a dense ruin wall that a non-INFANTRY model cannot cross, or against your own blob, where a fall-back cannot end. A fall-back must end unengaged, and an Ordered Retreat cannot pass through enemy models. So a unit boxed in by terrain and the charge cannot fall back at all, or only by Desperate Escape: a hazard roll per model plus a battle-shock roll.

- **When:** A unit that does not want to stay in combat ends inside an enemy unit's charge reach, and the ground behind it is restricted by the board edge, dense terrain (for MONSTER/VEHICLE models) or tightly packed friendly units.
- **Units:** Vehicles and monsters (cannot cross dense terrain), gunline infantry, characters
- **Move type:** Normal / Remain Stationary (choice of end position)
- **11e rules (verified):** 09.07 a fall-back must end unengaged; Desperate Escape costs hazard rolls plus a battle-shock roll (40k_11th_edition_core_rules.txt:1417-1446). 03.01 bases cannot move through enemy models or cross the battlefield edge (:379-395). 13.06 movement limits in dense terrain (:2163-2183).
- **AI today (none):** Fall-back space is searched only after the unit is engaged (_compute_fall_back_destinations AIDecisionMaker.gd:12185, trying 12 directions from _build_fall_back_directions :12501). No destination term in _assign_units_to_objectives or _find_safer_position (:28892) prices escape lanes.
- **Engine support:** _try_fall_back_positions (AIDecisionMaker.gd:12517) and _move_path_blocked (:15244) can be reused as a probe. New: a count of escape lanes from point P (fall-back directions clear of the edge, terrain and friendly units), used as a small destination term for units inside enemy charge reach.
- **Value (low):** Prevents rare but expensive traps, such as a tank stuck in combat for the rest of the game; a small term.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1417-1446 (09.07)
  - YouTube F017, video aQsog-fkQJ8 at 98:00: 'no, we'll fall back and we'll take our hazardous roles. Ones and twos, they die'
- **Found by:** cross_bucket_critic

### Shooting & charge setup

#### OFF-03 — Open a sight line to the target

Reposition so each firing model has at least one sight line to the target that crosses no obscuring terrain area that neither model is within, and that does not pass through a Solid feature's enclosed gaps 3″ or less above ground. In practice: step around a ruin corner, or put part of a base into the edge of an obscuring area, which stops that area blocking because areas a model is within are excluded. Prefer a 'peek' spot that sees the target while as few other enemy units as possible can see back. Standing inside the area also lets enemies see in.

- **When:** The target is in range but not visible from the current spot or from the straight-line endpoint. Suits glass-cannon shooters that need a single lane, and vehicles or monsters, which have no Hidden to lose.
- **Units:** Any ranged unit (visibility is checked per firing model)
- **Move type:** Normal (3″ or less to keep [HEAVY], see OFF-06)
- **11e rules (verified):** 13.10 Obscuring, excluding areas that either model is within (40k_11th_edition_core_rules.txt:2305-2311). 13.11 Solid: no line of sight through enclosed gaps 3″ or less from ground level (:2313-2316; example :2361-2378). 06.01 model and unit visibility (:1080-1099). 04.02: the target must be visible to the firing model (:637-639).
- **AI today (none):** The movement planner never tests line of sight. _can_shooter_see_target (AIDecisionMaker.gd:190) is only called in the Shooting phase (16712, 17201). The firing_position, T7-14 and MOV-1 checks are centroid range tests (10251-10273, 7574-7593, 13760-13778). Worse, the B34 cover nudge (_find_cover_path 14817-14877), which runs on every computed move, takes the first ±15°/30° heading whose endpoint has ANY terrain polygon between it and an enemy centroid. That can close the unit's own firing lane.
- **Engine support:** Reuse TerrainManager.model_visible_11e / model_fully_visible_11e (TerrainManager.gd:1201-1216), is_obscured_between (:976), LineOfSightManager.calculate_los_to_position (LineOfSightManager.gd:101, which deployed models see a point), calculate_visibility_grid_to_target (:340, a grid of positions that see a target) and RulesEngine.unit_sight_line (RulesEngine.gd:6641). New: a probe-model query 'which target models are visible from P' (copy the probe in _position_would_be_hidden, AIDecisionMaker.gd:28515) used inside OFF-01's scorer. B34 should also reject endpoints that lose the planned target's sight line.
- **Value (high):** Range without sight is worthless, and 11e terrain (obscuring areas, Solid walls) blocks a lot. The AI is blind to it, and its cover nudge can actively wreck lanes.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:2305-2325, 2361-2378, 1080-1099
  - 40k/autoloads/TerrainManager.gd:951 visibility_exclusions_for, :1169 _line_blocked_11e, :1201-1216 model_visible_11e / model_fully_visible_11e
  - Tabletop Battles Ruleshammer 11e shooting/LoS https://www.tabletopbattles.com/ruleshammer-40k-11th-shooting-range-line-of-sight-and-visibility (search snippet: you can't stick a gun barrel through a window and gain line of sight through the wall)
- **Found by:** core-rules, first-principles

#### OFF-04 — Close inside detection range to unmask Hidden or Lone Operative targets

A Hidden model is INFANTRY/BEASTS/SWARM in a terrain area with dense terrain whose unit has not shot this turn or last. It is only visible to enemy models within its detection range: 15″, reduced in the engine by 3″ (floor 9″) when a dense/Solid feature obscures it from that observer (Gone to Ground). A Lone Operative is only visible within 12″ (or X″) and cannot be targeted by [INDIRECT FIRE] from farther away. Move enough shooters inside that radius, on a line that avoids dense terrain so the full 15″ applies, accepting that the unit is now in the target's reach too. Timing: an enemy in dense terrain that fired last turn but not this turn will be Hidden again in its own next turn, so shoot it now (F003). Units with hidden-target buffs (Kommandos Nowhere to Hide, Venator Omni-auspex) gain the most. [INDIRECT FIRE] can target unseen Hidden units without closing, with the 10.07 penalties.

- **When:** A priority enemy is Hidden (often on a terrain objective) or is a Lone Operative, our shooters' range covers the gap, they can survive at 15″/12″ or less, and there is no indirect option.
- **Units:** Short- and mid-range shooters; durable or fast shooters; units with detection-range boosts
- **Move type:** Normal (Advance with [ASSAULT], OFF-13)
- **11e rules (corrected):** 13.09 Hidden, with a 15″ detection range 'unless otherwise stated' (40k_11th_edition_core_rules.txt:2292-2303; example :2346-2357). 24.24 Lone Operative X″ (:3813-3830). 10.07: [INDIRECT FIRE] weapons can target non-visible units (:1562-1563). Gone to Ground (−3″) and the 9″ floor are engine rules taken from the review doc; they are not in the core text (GameConstants.gd:86-95; TerrainManager.gd:1053-1080).
  - _Skeptic:_ Gone to Ground (−3″) is official 11e rules commentary 13.11.01 (errata_faq:539), and detection range and Lone Operative are clamped to 9″-30″ (errata_faq:165). They are not engine-only rules taken from a review doc. The engine has the 9″ floor but no 30″ cap (GameConstants.gd:94-97). Hidden also applies in light terrain areas (errata_faq:529). — 40k_11th_edition_errata_faq_commentary.md:165, :529, :539; 40k_11th_edition_core_rules.txt:2292-2303, 3813-3830, 1562-1563
  - _Errata check:_ Hidden needs an INFANTRY/BEASTS/SWARM model within a terrain area containing light OR dense terrain features (not dense-only), so the 'fired last turn' timing note also covers light-terrain areas. Gone to Ground is official rules commentary, not an engine-only rule: while a model is hidden, not fully visible to the attacking model because of one or more intervening dense features, and its unit has not shot this turn or last, its detection range drops by 3″; detection range and Lone Operative are clamped to 9″-30″ after all modifiers. — 13.09 errata; Commentary 13.11.01 Gone to Ground; Commentary 02.02.01 Modifiers (detection range / Lone Operative 9″-30″)
- **AI today (none):** No movement code closes on Hidden or Lone Operative enemies. _get_enemies_in_weapon_range (AIDecisionMaker.gd:13760-13778) counts them as 'in range' by centroid distance, so firing_position, T7-14 and MOV-1 can hold or route for targets that cannot legally be shot. F003's HIDDEN_WINDOW_BONUS ships neutral (1.0, line 2642) and only re-weights Shooting-phase targets (17841-17851). WEIGHT_HIDDEN_GAINED (2633) is about our own units being Hidden. The AI's own Lone Operative spacing uses a fixed 12″ (7432-7464).
- **Engine support:** Reuse TerrainManager.is_model_hidden (TerrainManager.gd:999), hidden_model_visible_to (:1047), detection_range_inches_for (:1061, which includes Gone to Ground and codex modifiers), RulesEngine.get_lone_operative_range (RulesEngine.gd:9953), get_eligible_targets (:7137, which already gates Hidden and Lone Operative) and AIDecisionMaker._target_regains_hidden_soon (28612). New: an 'unmask' candidate. For each Hidden or Lone Operative priority target, find endpoints within M that put at least k firing models inside detection_range_inches_for(target, probe) with line of sight, scored by EV minus the exposure at that range.
- **Value (high):** 11e's Hidden rule decides whether a shooting army can shoot its best targets at all (F001, confirmed/high). The AI ignores it and even scores Hidden enemies as in range.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:2292-2303, 3813-3830
  - 40k/autoloads/TerrainManager.gd:1047-1080 hidden_model_visible_to / detection_range_inches_for
  - YouTube dPFfT2IIlME @15:00 (Tabletop Titans, F001): “if you want to be a shooting army right now ... you have to be able to get within hidden range quickly”
  - YouTube gRQZh-QYBIQ @20:00 (Boltgun Tactics, F003): “I'm not going to shoot the raptors cuz they might get hidden um if I don't shoot”
  - YouTube Enm67qaqHkU @07:00 (40K Dirtbags, F003): “these guys won't be able to shoot me turn one if everybody's hidden”
  - BoLS terrain objectives 11e https://www.belloflostsouls.net/2026/04/warhammer-40k-terrain-objectives-how-they-work-in-11th-edition.html (search snippet: Hidden only blocks ranged attacks made from outside detection range)
  - _…and 1 more_
- **Found by:** core-rules, youtube, web, first-principles, factions

#### OFF-07 — Remain stationary to arm Indirect Fire and other stationary-gated shooting

[INDIRECT FIRE] attacks fail on an unmodified 1-5. They fail only on 1-3 if the firing unit remained stationary this turn AND one or more friendly units can see the target. The target also gets cover, and hit rolls cannot be re-rolled. So indirect units should Remain Stationary on every turn they rely on indirect fire, ideally out of sight, and pair with a spotter (OFF-19); even a 1″ move drops them back to 6s. The same strict 'remained stationary' gate arms datasheet buffs such as Powerful Volley (Rapier Carrier: [HEAVY] attacks also gain [LETHAL HITS]) and Atomantic Arc-reactor (Cerberus).

- **When:** The unit's best damage this turn is indirect (or stationary-gated), and a friendly unit already sees the target or can be moved to see it. Units with both direct and indirect weapons choose each turn.
- **Units:** [INDIRECT FIRE] units (artillery, mortars); Rapier Carrier; Cerberus
- **Move type:** Remain Stationary
- **11e rules (verified):** 10.07 Indirect shooting (40k_11th_edition_core_rules.txt:1549-1574). 09.04 Remain Stationary (:1378-1387). 24.19 [INDIRECT FIRE] (:3796-3805). 24.24: a Lone Operative can only be indirect-targeted from within X″ (:3818-3822). Engine: RulesEngine._indirect_hit_fail_band_11e (RulesEngine.gd:6594-6605). Powerful Volley: .llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:87.
- **AI today (none):** AIDecisionMaker.gd and AIPlayer.gd have no reference to indirect fire (grep -i 'indirect': 0 hits), Powerful Volley or Atomantic Arc-reactor. Indirect units move like any other ranged unit. MOV-1 holds only when the straight move would lose every centroid-range target (7392-7417), which rarely happens for 36-48″ artillery, and T7-26 holds only for [HEAVY] (7419-7430).
- **Engine support:** Reuse RulesEngine._indirect_hit_fail_band_11e (RulesEngine.gd:6594) and _has_los_to_target_unit (:6607) for the 4+/6+ band, get_eligible_targets (:7137) for indirect target lists, and scripts/rules/shootingtypes/IndirectShooting.gd for eligibility. New: an 'indirect battery' hold. If the unit's best expected damage is indirect, prefer REMAIN_STATIONARY and value it by whether a friendly unit sees the best target, or can be made to see it via OFF-19.
- **Value (high):** Triples the hit rate (1/6 to 1/2) at the cost of not moving, and is cheap to implement. Today every artillery move toward an objective throws it away.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1549-1574
  - 40k/autoloads/RulesEngine.gd:6594-6605 (fail band 3 only when remained_stationary and a friendly unit has LoS)
  - Sprues & Brews 11e core rules deep dive https://spruesandbrews.com/2026/06/01/warhammer-40000-11th-edition-core-rules-deep-dive/
  - Tabletop Battles attacks/shooting deep dive https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-attacks-and-the-shooting-phase/ (search snippet: stationary plus a spotter is the only route above 6s)
  - YouTube short F-8oPTEPi38 'Indirect Fire Nerfed! Weird Warhammer 40k 11th Rules Reveals' (title only, from search)
- **Found by:** core-rules, web, first-principles, factions

#### OFF-N01 — Take the firing spot that sees the target but few enemy guns _(added by completeness review)_

Among the endpoints from which the unit's firing models can see and reach its chosen target, pick the one that the fewest dangerous enemy shooters can see. For INFANTRY/BEASTS/SWARM, prefer one inside a terrain area so the unit keeps the benefit of cover while it fires. In 11e an obscuring terrain area blocks a sight line completely unless one of the two models is within it, and a unit is visible as soon as any one of its models is, so where the unit ends decides who can see it. Practical shapes: shoot from the corner of a ruin footprint that opens only the target's angle; stand just inside the edge of a terrain area (that area then stops blocking your own lines out, and infantry gain cover); keep every model that does not need the line behind the footprint. This is the exposure half of OFF-01/OFF-03: they ask 'can I hurt it from here', this asks 'who hurts me back from here'. A unit that fires loses Hidden this turn and next (13.09), so for shooters sight-line exposure is the main defence left.

- **When:** A ranged unit has a target worth shooting this turn and more than one endpoint gives it range and sight. Strongest for MONSTER/VEHICLE shooters (they are never Hidden), infantry that will forfeit Hidden by firing, and long-range units that can trade a few inches for a narrow angle. Little value against [INDIRECT FIRE] or [IGNORES COVER] return fire, or for units already outside most enemy ranges.
- **Units:** Ranged infantry squads, battle tanks, artillery, monsters, shooting characters; [HEAVY] units within 3″
- **Move type:** Normal (3″ or less for [HEAVY], see OFF-06); Advance with [ASSAULT]; a short shift instead of Remain Stationary
- **11e rules (verified):** 06.01 visibility per model pair: a unit is visible if any model is, and only the observing and observed units' own models are ignored (40k_11th_edition_core_rules.txt:1024-1035, 1100-1117). 04.02 the target must be visible and in range (:628-636). 13.10 Obscuring: areas that either model is within are excluded (:2305-2311). 13.11 Solid blocks enclosed gaps 3″ or less from ground level (:2313-2318). 13.08 cover is judged per attacking model (:2278-2290; FAQ 13.08, 40k_11th_edition_errata_faq_commentary.md:522-525). 13.09 firing forfeits Hidden this turn and next (:2292-2303).
- **AI today (none):** Firing-position logic only checks range. _get_enemies_in_weapon_range (AIDecisionMaker.gd:13760) compares unit centroids. _find_firing_position_toward_objective (:13848) and _clamp_move_for_weapon_range (:13780) never test line of sight. _find_cover_path (:14817) only tries ±15/30° using the polygon proxy _position_has_cover (:14858). Nothing counts how many enemy units could see the endpoint, and the F004 Overwatch term (:28660) is explicitly range-only.
- **Engine support:** TerrainManager.model_visible_11e and model_fully_visible_11e (TerrainManager.gd:1209/1215), unit_has_cover_11e(unit, attacker_model) (:1388) and hidden_model_visible_to (:1055) all take model dicts, so probe models at a hypothetical position work. That is the same pattern as _position_would_be_hidden (AIDecisionMaker.gd:28515). New query needed: _probe_exposure(unit, dests, enemy_units) returning {sees_target, enemy_shooters_seeing, weighted_incoming}, sampling 3-5 models per unit and memoised per candidate (the RulesEngine LoS memo is at RulesEngine.gd:6825).
- **Value (high):** In 11e line of sight is all-or-nothing per obscuring area, so the endpoint decides most of the return fire. It applies to every ranged unit every turn, and the current range-only scorer cannot see it.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1024-1035 (06.01) and :2305-2311 (13.10 Obscuring)
  - [Warhammer Community #New40k terrain preview](https://www.warhammer-community.com/en-gb/articles/xlppkx5s/new40k-take-cover-with-updated-terrain-rules/) (WebSearch snippet only, page not fetched): units can stay out of line of sight just behind the footprint of a terrain area
  - YouTube F005, video 1SRkN4Drhs4 at 18:00: 'my jumpack intercessors will move to stage behind this terrain ... I just don't want to be shot' (research/youtube/ai_learnings.json)
  - YouTube F030, video aQsog-fkQJ8 at 85:00: 'partially obscured ... your storm bolters will be at minus one to hit'
- **Found by:** cross_bucket_critic

#### OFF-01 — Move toward an enemy to shoot it

User example. Pick the most valuable target the unit can hurt this turn and end a Normal move where as many firing models as possible have it within range (judged per model, edge to edge) and visible (see OFF-03). Prefer endpoints that reach several targets, which gives the Shooting phase options, and measure with the unit's effective range, including codex range extensions. An Advance limits the unit to [ASSAULT] weapons (OFF-13), so walk unless that trade is better.

- **When:** The unit's best target (expected damage × target value) is out of range now but reachable within M, the shot is worth more than the objective trip, and the unit is not held by a stationary gate (OFF-06 Heavy, OFF-07 Indirect).
- **Units:** Any unit with ranged weapons
- **Move type:** Normal
- **11e rules (verified):** 04.02: each target must be visible to the firing model, within range and unengaged (40k_11th_edition_core_rules.txt:628-642). 06.01: a unit is visible if any of its models is (:1098-1099). 10.04: normal shooting requires the unit to be unengaged and not to have advanced (:1489-1491). 10.05: after an Advance, only [ASSAULT] weapons can fire (:1506-1515). Effective range including the Ork Dakka! Dakka! Dakka! bonus: RulesEngine.gd:6693-6703.
- **AI today (partial):** The only movement candidates are objectives (B06, AIDecisionMaker.gd:9910-10598). Shooting appears only as nudges on objective trips: the firing_position term (+3×kept, −2.5 when all targets are lost, +1.5 when new ones are gained, +1 for enemies near; 10251-10273; weights 2532-2534) and the shooting_lane term (+1 per planned lane kept; 10336-10349). The execution overrides only keep targets the unit already has: MOV-1 hold-for-shooting (7392-7417; _should_hold_for_shooting 13906), the T7-14 35% blend toward a point that keeps one target (7574-7593, 13848; FIRING_POSITION_BLEND 2535) and the weapon-range clamp (13780). No code moves a unit toward a target when none is in range. Every test is centroid to centroid against the printed max range (_get_enemies_in_weapon_range 13760-13778; _get_max_weapon_range 13517-13527, no codex bonus), with no line of sight, which is only checked in the Shooting phase (16712, 17201). Loaded transports zero their own range (7398-7402).
- **Engine support:** Reuse RulesEngine.get_eligible_targets (RulesEngine.gd:7137) on a copied board with the unit translated, which answers range, LoS, Hidden and Lone Operative per weapon. Also reuse RulesEngine.max_ranged_weapon_range_inches (:6693), is_target_within_range_inches (:10122), TerrainManager.model_visible_11e (TerrainManager.gd:1201) on probe models (pattern: AIDecisionMaker._position_would_be_hidden 28515), _calculate_target_value (17642), _estimate_weapon_damage (17984) and the executor _compute_movement_toward_target (14212). New: a 'shoot' candidate generator inside _assign_units_to_objectives that samples endpoints within M, scores Σ(models in range and visible × weapon EV × target value) − threat, and competes with the objective candidates.
- **Value (high):** The user's own example and the most common reason a ranged unit moves. Today a unit never moves to bring a target into range unless an objective lies that way.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:628-642, 1489-1518
  - 40k/scripts/AIDecisionMaker.gd:10251-10273 (firing_position term), :7574-7593 (T7-14 blend), :13780 (_clamp_move_for_weapon_range), :13848 (_find_firing_position_toward_objective)
  - Warhammer Community 'Warhammer 40,000 tactica: the Movement Phase' https://www.warhammer-community.com/en-gb/articles/wrrt241d/warhammer-40000-tactica-the-movement-phase/ (search snippet: a unit moved so it can see several enemy units has more options in the Shooting phase; edition-agnostic)
  - 40k/autoloads/RulesEngine.gd:6693-6703 max_ranged_weapon_range_inches adds codex range bonuses; AIDecisionMaker._get_max_weapon_range :13517-13527 does not (factions#27)
- **Found by:** core-rules, web, first-principles, factions

#### OFF-02 — Move toward an enemy to charge it

User example. Choose the target by value, not by proximity, and end the Movement phase where it is within 12″ and the charge roll is most likely to cover the edge-to-edge gap, counting the 2D6 plus any modifiers and re-rolls. In 11e the target must be within the roll itself: a 7″ gap needs a 7 (58%), a 9″ gap a 9 (28%). The move must end unengaged. Do not Advance or Fall Back unless a rule allows a charge afterwards (OFF-23, OFF-33), and do not start an action or make a Rapid or Combat disembark with a unit that has to charge. Units with +1/+2 or a charge re-roll (Command Re-roll re-rolls the whole roll) can stage farther back, outside the target's threat. If no charge is possible this turn, close in so it is possible next turn.

- **When:** A melee-capable unit has a worthwhile target within roughly M + 7-9″, with a 12″ maximum gap after the move. Aim for a final gap of 7″ or less without bonuses. Account for Overwatch (OFF-05), lanes (OFF-12) and Heroic Intervention support (OFF-24).
- **Units:** Melee units, and any unit whose charge pays off (Fights First, [LANCE])
- **Move type:** Normal (Advance only with an advance-and-charge rule, or to close in for next turn)
- **11e rules (corrected):** 11.02 eligibility: within 12″, unengaged, and no advance or fall-back this turn (40k_11th_edition_core_rules.txt:1617-1622). The 2D6 roll is the maximum distance, and the player may decline after rolling (:1624-1629). 11.04: targets must be within 12″ AND within the roll; the unit must end engaged with every target and with no other unit; Fights First until end of turn (:1647-1665). 16.01: a unit that starts an action cannot charge (:2819-2822). 18.04: Rapid and Combat Disembark forbid charging (:3050-3057). 15.02: Command Re-roll re-rolls the whole charge roll (:2658-2673). 24.21 [LANCE]: +1 to wound after a charge move (:3767-3775). Correction: first-principles#33 says an unmodified 2 always fails. The sidebar says a double 1 never suffices only in the absence of modifiers (:1593-1613).
- **AI today (partial):** B04 charge_intent (AIDecisionMaker.gd:3812-3906) keeps one target per melee-capable unit. Score = 2×melee damage plus a lock bonus, ×1.3 if the target is on an objective, ×0.5 if the post-move centroid gap is over 9″, ×1.2 if it is 6″ or less. It has no roll odds and no edge gaps. The T7-23 steer blends the move 30/50/70% toward that target (CHARGE_BLEND_WEIGHTS 2541) only if it then ends within 9″ centroid to centroid (CHARGE_BLEND_REACH_INCHES 2540; 7491-7548); otherwise it re-plans straight to the objective (7600-7622). The charge_lane term adds +3×alignment to objective scores (10316-10334). Melee-focused units take the chase gate instead (2947-3099): the NEAREST enemy by centroid distance plus terrain penalty (3114-3151), filtered by round and horde distance limits, then a full Normal move or Advance straight at the target centroid with threat avoidance off (7228-7272). There is no stop-short staging. Planning ignores charge modifiers (FIX_CHARGE_REROLL_ODDS = 0.0 at 1960; charge_roll_bonus is never read). The real odds helpers (_charge_roll_needed 18840, _charge_success_probability 18928) are only used in the Charge phase.
- **Engine support:** Reuse _charge_roll_needed (18840), _charge_success_probability (18928), _charge_odds_with_reroll (18968), _get_closest_model_pair_info (19703), _estimate_charge_terrain_penalty (98) and _estimate_melee_damage (19576) at a probe end position, plus the codex charge_roll_bonus helpers (SMDetachmentsB.gd:315, SWDetachments11e.gd:200, CustodesDetachments.gd:711, CustodesEnhancements.gd:515, OrkAbilities11e.gd:931). New: a 'stage charge' candidate per (unit, target) that searches endpoints within M for the highest P(roll ≥ edge gap | modifiers) × melee EV − exposure, replacing the centroid blend. The chase gate should then pick its target by this value instead of by proximity.
- **Value (high):** The user's own example and the only way melee units deal damage. The current chase, aimed at the nearest target's centroid with no odds model, wastes charges.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1593-1666
  - 40k/scripts/rules/movetypes/ChargeMove11e.gd:4-18
  - 40k/scripts/AIDecisionMaker.gd:18840-18844 (_charge_roll_needed: 11e max(edge, move))
  - BoLS 'New Close Combat Rules Revealed' https://www.belloflostsouls.net/2026/04/warhammer-40k-new-close-combat-rules-revealed-melee-movement-made-easy.html (search snippet: with 2″ engagement range a successful roll gives about 2″ of slack)
  - Tabletop Battles charge/fight deep dive https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-the-charge-and-fight-phases/ (snippet: 'If a unit is 10″ away and you roll a 9″ charge then you can't select that unit')
  - Charge modifiers (factions#25): Thundering Stampede orks/wahapedia/Datasheets_abilities.csv:216; Death Blow space-marines/RULES.md:652; Competitive Streak orks/RULES.md:119; engine helpers SMDetachmentsB.gd:315, SWDetachments11e.gd:200, CustodesDetachments.gd:711, OrkAbilities11e.gd:931
- **Found by:** core-rules, web, first-principles, factions

#### OFF-06 — Keep [HEAVY] while moving 3″ or less

In 11e, [HEAVY] gives +1 to hit in your Shooting phase if the unit is unengaged, was not set up this turn, and no model moved more than 3″ this turn; vertical distance counts toward that. So a heavy-weapon unit can step up to 3″ to gain line of sight, enter cover or a terrain area, reach objective range or clear a lane, and keep the bonus. Any model moving more than 3″ loses it, and arriving from reserves or disembarking (both are set-ups) loses it for that turn. The same 3″ envelope applies to rules that grant [Heavy] (Gunnery Honours) or that require a limited move (the chapter-only Ceramite Sentinels 'entrenched': 3″ or less, inside a terrain area).

- **When:** A [HEAVY] unit has targets in range and a step of 3″ or less improves LoS, cover or objective presence, or an objective move has to be weighed against losing +1 to hit. Does not apply to Overwatch, since the bonus is Shooting-phase only.
- **Units:** Units with [HEAVY] weapons (heavy-weapon squads, artillery, tanks); vehicles with Gunnery Honours
- **Move type:** Normal (3″ or less for every model) or Remain Stationary
- **11e rules (corrected):** 24.16 [HEAVY] (40k_11th_edition_core_rules.txt:3759-3768). 13.06: distance moved vertically is added to the distance moved (:2192-2194). Disembark and ingress are set-ups (18.04 EFFECT :3027; 20.04 EFFECT :3262). Engine: ModifierStack.heavy_applies_11e (ModifierStack.gd:168-186) reads flags.moved_max_inches, which MovementPhase.gd records at :3458 and :3994. Gunnery Honours: .llm/codex_11e_wahapedia/space-marines/RULES.md:270; SMDetachmentsA.gd:442.
  - _Errata check:_ Vertical distance counts toward the 3″ except for a FLY unit that takes to the skies: per FAQ its vertical movement does not count for [HEAVY] (21.03 already ignores it for that move), so such a unit can climb onto terrain and keep the bonus as long as no model moves more than 3″ horizontally. — FAQ on [HEAVY] and taking to the skies (errata doc, filed under 23.04)
- **AI today (partial):** T7-26 (AIDecisionMaker.gd:7419-7430; _should_hold_for_heavy_bonus 13618-13663) implements the 10e rule. It takes REMAIN_STATIONARY when +1 to hit is worth at least 0.15 extra hits (HEAVY_STATIONARY_MIN_BENEFIT 2547), an enemy centroid is within Heavy range, the objective is not reachable this turn, and the unit has no charge intent. It never plans a move of 3″ or less (the AI never reads moved_max_inches), never prices the lost bonus on moves over 3″, and does not check set_up_this_turn, so it can hold a just-disembarked unit for nothing.
- **Engine support:** Reuse ModifierStack.heavy_applies_11e (ModifierStack.gd:168), _get_unit_heavy_weapon_data (AIDecisionMaker.gd:13547), and _compute_movement_toward_target (14212) with move_inches capped at 3.0. New: a 'Heavy creep' candidate (3″ or less for every model), scored with OFF-01/OFF-03's range and LoS queries plus cover and objective gains, and a Heavy-loss cost term on objective moves longer than 3″.
- **Value (high):** Heavy weapons are common and 11e changed the rule. The AI either freezes the unit or moves it and drops the +1 to hit without pricing that.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:3751-3769
  - 40k/scripts/rules/ModifierStack.gd:159-186
  - New Recruit wiki Heavy (11e) https://www.newrecruit.eu/wiki/wh40k-11e/warhammer-40,000-11th-edition/rules/heavy
  - Thrifthammer 11e core keywords cheat sheet https://thrifthammer.com/blog/warhammer-40k-11th-edition-core-keywords-cheat-sheet/ (10e required staying still; 11e loosens that)
  - docs/rules/11th_edition_delta_audit.md §6 (Heavy: moved 3″ or less, was 'remained stationary')
  - .llm/codex_11e_wahapedia/space-marines/RULES.md:270 (Gunnery Honours), :495 (Ceramite Sentinels entrenched)
- **Found by:** core-rules, youtube, web, first-principles, factions

#### OFF-11 — Stage within reach of several charge targets

In 11e you declare the charge, roll 2D6 and only then pick targets, each of which must be within 12″ and within the roll; you can also decline after a bad roll. So end the move with two or more acceptable targets at staggered distances, a near, safe option and a far, high-value one, so that most rolls produce a useful charge.

- **When:** A melee unit approaches a cluster where the preferred target is at a low-probability distance and an acceptable nearer target exists, or where a failed charge would strand the unit.
- **Units:** Melee units
- **Move type:** Normal
- **11e rules (verified):** 11.02 steps 2-3: the roll comes first, then the charge is attempted 'if it is possible ... and if you still want to' (40k_11th_edition_core_rules.txt:1624-1629). 11.04 BEFORE MOVING: targets are selected after the roll (:1647-1650). Worked example (:1669-1702).
- **AI today (none):** charge_intent keeps one best target per unit (AIDecisionMaker.gd:3834-3906) and the steer aims only at that target (7503-7548). The chase gate picks the single nearest enemy (2951). Choosing targets after the roll is modelled only at declaration in the Charge phase (_evaluate_multi_target_charge 18973-19130), after positions are already fixed.
- **Engine support:** Reuse _charge_success_probability (18928) per target gap and the roll-EV maths in _evaluate_multi_target_charge (18973). New: a 'charge option value' at each candidate endpoint, Σ over rolls r of P(r) × max(EV of the target sets reachable with r), so staging maximizes expected value across all rolls rather than the odds against a single target.
- **Value (medium):** 11e's roll-first targeting makes this a free gain in charge reliability, but it needs several targets close together.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1612-1650, 1669-1702
  - Tabletop Battles 'Ruleshammer 11th Edition: Charge Phase' https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-charge-phase
  - docs/rules/11th_edition_delta_audit.md (11.02 row: targets chosen after the 2D6 roll)
  - 40k/scripts/rules/movetypes/ChargeMove11e.gd:4-8
- **Found by:** core-rules, youtube, web

#### OFF-16 — Set up a multi-unit charge

Deliberately bring a second (or third) enemy unit inside the likely roll so one charge can select and engage several targets. The charge must end engaged with all of them and with no other unit. This locks more shooters, uses Fights First on more targets, and makes falling back harder (the Death Guard style).

- **When:** Two adjacent enemy units are both worth locking, the charging unit is durable, and the end positions can engage every target.
- **Units:** Large-footprint melee mobs, monsters, Death Guard-style lock armies
- **Move type:** Normal
- **11e rules (verified):** 11.04 BEFORE and AFTER MOVING (40k_11th_edition_core_rules.txt:1647-1663). 03.04: engagement range is 2″ (:542-552). Example C, two targets within the roll (:1695-1702). Death Guard fall-back penalties are faction rules and were not checked here.
- **AI today (none):** Movement never stages for a multi-target charge: charge_intent is single-target (AIDecisionMaker.gd:3834-3906). Only the Charge phase evaluates 2-3-target combinations, once positions are fixed (_evaluate_multi_target_charge 18973-19130).
- **Engine support:** Reuse _evaluate_multi_target_charge (18973) and _compute_charge_move (19797) from a probe start, plus the ChargeMove11e after-moving conditions. New: an endpoint search that maximizes the expected value of the best multi-target combination across rolls.
- **Value (medium):** Strong when enemy units cluster, and central to lock-style armies, but situational.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1640-1702
  - YouTube F5TL7LhZJlY @23:00 (40K Dirtbags, F024): “If both of these guys were in combat with the death shroud ... both of them would have to pass a seven up to fall back”
  - YouTube u8fm403MGtg @08:00 (40K Fireside, F024): “Plague Legion it gets stuck in combat a lot and it's really hard to get out of combat”
  - research/youtube/ai_learnings.json F017 detail: 'armies that want the enemy stuck deliberately engage from multiple units so that falling back is unattractive'
- **Found by:** youtube, first-principles, core-rules

#### OFF-17 — Flank to strip the target's cover

Cover is judged per attacking model. A target has it only if EVERY one of its models either is INFANTRY/BEASTS/SWARM within a terrain area, or is not fully visible to that attacking model because of intervening terrain. Against vehicles, monsters and mounted units, and against infantry outside terrain areas, move firing models to angles where at least one target model is fully visible, denying the −1 BS. Infantry inside a terrain area keep cover from every angle, so use [IGNORES COVER], [TORRENT] (auto-hits) or Plunging Fire against them instead. Cross-fire from two directions defeats a single piece of terrain.

- **When:** High-BS shooters face a partly obscured priority VEHICLE/MONSTER and have movement to spare after reaching range.
- **Units:** Mobile shooters
- **Move type:** Normal
- **11e rules (verified):** 13.08 Benefit of Cover (40k_11th_edition_core_rules.txt:2278-2290). 06.01 'fully visible' (:1087-1093). 24.18 [IGNORES COVER] (:3783-3793). 24.37 [TORRENT] automatically hits (:3943-3950). 22.05 (:3453-3462).
- **AI today (none):** A target's cover is only consulted when choosing Shooting-phase targets, using a 10e-style helper (_target_has_benefit_of_cover, AIDecisionMaker.gd:25044-25120). Movement never evaluates a target's cover from a candidate endpoint.
- **Engine support:** Reuse TerrainManager.unit_has_cover_11e(unit, attacker_model) (TerrainManager.gd:1380-1416) and model_fully_visible_11e (:1207), which both accept probe attacker models, plus RulesEngine.check_unit_has_cover (RulesEngine.gd:7005). New: in OFF-01's endpoint scorer, call unit_has_cover_11e(target, probe) per firing model and value the −1 BS.
- **Value (medium):** −1 BS is a meaningful swing against high-value vehicles and monsters, but it needs spare movement and the right target type.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:2278-2290, 2346-2357 (example)
  - YouTube 1SRkN4Drhs4 @52:00 (Play On Tabletop, F030): “because you're not an infantry, so you have to be obscured by the terrain itself”
  - YouTube aQsog-fkQJ8 @85:00 (Maelstrom Gaming Studios - Tyranids, F030): “partially obscured ... your storm bolters will be at minus one to hit”
  - YouTube VqwMdS9MuIY @171:00 (TacticalTortoise 40k, F030): “Don't get cover, right? Yeah. No, it's ignore cover for all”
  - Tabletop Battles 'More Examples #01' https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-more-visibility-and-cover-examples ('Cover is now determined per attacking model')
- **Found by:** core-rules, youtube, web, first-principles

#### OFF-19 — Spot for the gunline

Move one unit so it enables OTHER units' shots. (a) Give a stationary [INDIRECT FIRE] battery a friendly unit that can see its target, which raises its hits from 6s to 4+. (b) Bring a detection-range raiser within its ability's range of a Hidden enemy so the gunline 12-15″ away can target it. Raisers: Kommandos Found 'Em! (Movement phase, within 12″, +3″), Infiltrator Omni-scramblers (18″, +3″), Prosecutors Purity of Execution (18″, +3″), Eliminators Special-issue Optics (24″, +6″), Stormlance Auspex Triangulation Shrines (12″, +3″), Lieutenant Priority Target Identified. The spotter has to move before the shooters do.

- **When:** An indirect battery is holding still (OFF-07) and nothing sees its best target, or a priority enemy is Hidden beyond the gunline's detection reach.
- **Units:** Any cheap or fast unit as a LoS spotter; Kommandos, Infiltrator Squad, Prosecutors, Eliminators, Stormlance speeders, Lieutenant with Combi-weapon
- **Move type:** Normal
- **11e rules (corrected):** 10.07: the 1-3 fail band needs the target to be visible to a friendly unit (40k_11th_edition_core_rules.txt:1568-1571). 13.09: detection range is 15″ 'unless otherwise stated' (:2301-2303). Found 'Em! text: .llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:89. Engine codex detection modifiers: TerrainManager.gd:1065-1079.
  - _Errata check:_ The '12-15″' gunline band only holds for a target that has gone to ground (hidden, not fully visible to that attacking model because of intervening dense features, unshot this turn and last: 12″). A hidden target that has not gone to ground, including one in a light-only terrain area that the 13.09 errata now makes hidden, keeps 15″, so a +3″/+6″ raiser serves a gunline 15-18″/15-21″ away; detection range can never exceed 30″. — Commentary 13.11.01 Gone to Ground; 13.09 errata; Commentary 02.02.01 Modifiers (30″ cap)
- **AI today (none):** The AI has no indirect-fire awareness at all (grep -i 'indirect' in AIDecisionMaker.gd and AIPlayer.gd: 0). Detection-range abilities get flat scores when they are offered (OrkAbilities11e.gd:2321-2322 found_em 1.5; SMAbilitiesA.gd:2266-2267 omni_scramblers 1.5; SMAbilitiesB.gd:1816-1817 special_issue_optics 2.0) or 0.0 'not modelled by the AI' (CustodesAbilities.gd:1327-1328). None of them drives movement.
- **Engine support:** Reuse RulesEngine._indirect_hit_fail_band_11e (RulesEngine.gd:6594) and _has_los_to_target_unit (:6607), and TerrainManager.detection_range_inches_for (TerrainManager.gd:1061) with its codex bonus hooks (1065-1079). New: a 'spotter' assignment. For an indirect battery's top target, or a Hidden priority target, find the cheapest friendly unit that can reach an endpoint where it sees the target (or is within ability range), scored by the shooters' EV gain minus the spotter's exposure.
- **Value (medium):** Unlocks OFF-07's 3× hit rate and Hidden targets. It depends on having indirect units or specific spotters.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1564-1571, 2292-2303
  - .llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:89 (Found 'Em!); space-marines/wahapedia/Datasheets_abilities.csv:144 (Omni-scramblers), :454 (Special-issue Optics); custodes/wahapedia/Datasheets_abilities.csv:134 (Purity of Execution)
  - 40k/autoloads/TerrainManager.gd:1065-1079 (detection-range bonus hooks)
  - 40k/autoloads/RulesEngine.gd:6594-6605 (indirect band uses any friendly unit's LoS)
  - 40k/autoloads/RulesEngine.gd:6594-6605 (_indirect_hit_fail_band_11e: 5 normally, 3 when remained_stationary and a friendly unit has LoS)
  - 40k/scripts/rules/shootingtypes/IndirectShooting.gd:45-66 (has_spotter: a friendly unit other than the shooter)
  - _…and 3 more_
- **Absorbed duplicates:** COO-03 (Spot for your indirect fire)
- **Found by:** factions, core-rules, web, first-principles, youtube

#### OFF-22 — Strike first: charge the enemy melee threat before it charges you

If an enemy melee unit will reach us next turn anyway, move in and charge it now. Every model in a unit that made a charge move has Fights First until the end of the turn, and Fights First units fight before all others. Waiting means being charged and struck first instead.

- **When:** Melee-against-melee standoffs where both sides are inside each other's next-turn reach and our unit wins, or trades well, when it strikes first.
- **Units:** Melee units
- **Move type:** Normal (charge setup)
- **11e rules (verified):** 11.04 AFTER MOVING: Fights First until end of turn (40k_11th_edition_core_rules.txt:1664-1665). 24.13 Fights First (:3736-3745). Fights First units must be selected to fight before other units (:1885-1886). 12.04 (:1819-1850).
- **AI today (none):** charge_intent and charge scoring value our own damage (AIDecisionMaker.gd:3853-3855, 19168) and penalize the survivor's return damage (ch_retaliation 19377-19384). Nothing compares 'charge now with Fights First' against 'be charged next turn'. The threat model only pushes ranged units away (7357-7390).
- **Engine support:** Reuse _estimate_melee_damage (19576) in both directions, and _calculate_enemy_threat_data (28695) for 'will reach us next turn'. New: a pre-emption term. If the target can charge us next turn, add the first-strike damage it would deal to us to the value of charging now.
- **Value (medium):** Decides many melee mirror matches, but needs both sides within reach.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1660-1665, 1819-1850, 1883-1886
  - 40k/scripts/rules/movetypes/ChargeMove11e.gd:9-10 (Fights First ability after a charge move)
  - 40k/scripts/rules/FightSequencer.gd:4-21 (per first-principles#37)
- **Found by:** first-principles

#### OFF-10 — Close to a bonus range band (half range, datasheet bands)

Move so the target is inside a distance band that boosts the attack in the Select Targets step. Core bands: half range for [RAPID FIRE X] (+X attacks) and [MELTA X] (+X damage). Datasheet bands: Fury of the First 9″ +1 AP, Close-quarters Firestorm 9″ +1 S, Fury of the Machine Spirit 12″ [LETHAL HITS], Priority Target Acquisition 12″ +1 S, Ballistus Strike 24″ [SUSTAINED HITS 1], Tempered Ferocity 6″, GLOWIN' DAKKA 9″ +1 AP, TIP OF THE TALON 9″ +1 S. Use effective range (Dakka! Dakka! Dakka! +3″, Targetin' Squigs +3″, Thunderous Force +6″, Salvus +6″). Skip the half-range approach for Tacticus units under Codex Fire-patterns, whose [RAPID FIRE] works out to maximum range.

- **When:** The band is reachable this turn without walking into a worse threat, and the bonus applies to the unit's main weapons (especially melta against vehicles and monsters). Pick the tightest band that pays.
- **Units:** [RAPID FIRE]/[MELTA] units; Terminator Squads, Aggressors, Land Raider Crusader/Redeemer, Gladiator Valiant, Ballistus Dreadnought, Wolf Guard Battle Leader, Shoota Boyz, Aquilan Shield Custodes
- **Move type:** Normal
- **11e rules (verified):** 24.30 [RAPID FIRE X] (40k_11th_edition_core_rules.txt:3903-3908). 24.25 [MELTA X] (:3837-3844). Half range is judged in the Select Targets step. Datasheets: Fury of the First (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:403); Codex Fire-patterns (space-marines/RULES.md:729). Engine: RulesEngine.count_models_in_half_range (RulesEngine.gd:11812-11822) applies Fire-patterns and the Ork range bonus.
- **AI today (partial):** T7-30 (AIDecisionMaker.gd:7550-7572; _find_best_half_range_position 13702-13754) blends the move 40% (HALF_RANGE_MOVE_BLEND 2526) toward a point 1″ inside half range of the enemy with the largest combined Rapid Fire and Melta benefit (at least 2.0, line 2527). It only considers enemies already in full range, works by centroid, ignores LoS, and is skipped when the unit has a charge intent. Datasheet bands, codex range extensions and Fire-patterns are never read (grep 'range_bonus', 'Fire-patterns', 'Fury of the First': 0), and ranges are the printed ones (_get_max_weapon_range 13517-13527).
- **Engine support:** Reuse RulesEngine.count_models_in_half_range (RulesEngine.gd:11812), max_ranged_weapon_range_inches (:6693) and _get_unit_half_range_data (AIDecisionMaker.gd:13669). New: generalize half_range_data into per-weapon 'band bonuses' (band in inches, EV gain), built from weapon keywords plus a datasheet band table and measured per model, edge to edge, at the probe endpoint; fold it into OFF-01's scorer.
- **Value (medium):** Common (bolt rifles, meltas) and already half-handled. The gain is per model and modest, except melta against vehicles.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:3833-3850, 3896-3917
  - 40k/scripts/AIDecisionMaker.gd:13702-13754 (_find_best_half_range_position)
  - .llm/codex_11e_wahapedia/space-marines/RULES.md:729 (Codex Fire-patterns), space-marines/wahapedia/Datasheets_abilities.csv:403 (Fury of the First), :471 (Close-quarters Firestorm), :14 (Fury of the Machine Spirit), :66 (Ballistus Strike); orks/RULES.md:228, :235 (Dakka! Dakka! Dakka!, GLOWIN' DAKKA)
  - 40k/autoloads/RulesEngine.gd:11812-11822 (half range with Fire-patterns and Ork range bonus)
- **Found by:** core-rules, first-principles, factions

#### OFF-12 — Approach the charge target on a clean lane

Stage so that the charge path to the intended target neither passes through enemy bases nor ends within 2″ of an enemy unit that is not a target. Screens and neighbouring units otherwise force a failed charge or an unwanted multi-target one. Every charging model must also end closer to a target, and those that can get within 1″ must. Account for climbing on the path: non-INFANTRY models cannot cross dense sections taller than 2″. FLY units can take to the skies over blockers (OFF-27).

- **When:** Crowded fronts, screened targets, or ruins between the charger and the target.
- **Units:** Melee units, especially non-INFANTRY near dense terrain
- **Move type:** Normal
- **11e rules (corrected):** 11.04 WHILE and AFTER MOVING (40k_11th_edition_core_rules.txt:1652-1663). 03.01: bases cannot be moved through enemy models (:393). 17.01: MONSTER/VEHICLE move-through applies to normal and advance moves only (:2871-2874). 13.06 dense terrain (:2167-2182). 11.04 example of a target that cannot be engaged around terrain (:1669-1682).
  - _Errata check:_ Taking to the skies must be declared before the charge roll and (unless the unit has HOVER) subtracts 2″ from the maximum distance used to pick charge targets (a roll of 9 only reaches targets within 7″), so a flier relying on it to clear a screen must stage about 2″ closer. Friendly units do not block the lane: in a charge every model, MONSTER/VEHICLE included, can move through friendly models. — FAQ 21.03 Flying Models; FAQ 02.02 Profiles (charge-roll modifiers / Take to the Skies); FAQ 17.01 Moving Monsters and Vehicles
- **AI today (partial):** Path terrain is considered only when ranking the nearest target: _get_nearest_enemy_for_charge adds _estimate_charge_terrain_penalty to the distance (AIDecisionMaker.gd:3134-3136). Moves aim at the target's centroid (7228-7272, 7503-7548). Nothing checks for enemy bases in the way or for non-target units within 2″ of the likely charge end. _find_flank_around_terrain (3153-3190), which builds a waypoint around terrain blocking a charge path, has no callers.
- **Engine support:** Reuse the ChargeMove11e after-moving conditions, TerrainManager.calculate_charge_terrain_penalty (TerrainManager.gd:509), the unused _find_flank_around_terrain (AIDecisionMaker.gd:3153), and _compute_charge_move (19797) to simulate the charge end from a probe start. New: a lane check that rejects or penalizes endpoints whose minimal engaging placement touches a non-target unit or crosses enemy bases.
- **Value (medium):** A charge that touches a stray unit fails outright, and 11e's 2″ engagement range widens the danger zone. Matters most on crowded boards.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1652-1682, 2869-2874
  - 40k/scripts/rules/movetypes/ChargeMove11e.gd:4-10 (end engaged with all targets, none other)
  - YouTube _xKjN6N1jT0 @04:00 (40K Fireside, F008): “you need to kill like I don't know, 10 guardsmen move blocking your big charges”
- **Found by:** core-rules, first-principles

#### OFF-13 — Advance and still shoot with [ASSAULT] weapons

Advance (M + D6) when the extra inches are needed for range or LoS on a target, for an objective or for a Hidden spot, and then fire only the [ASSAULT] weapons using assault shooting. The cost: no charge, no actions, no [HEAVY] bonus (a model moved more than 3″), and no EXPLOSIVES this turn. The same applies when a rule grants [ASSAULT]: Orks riled up, Dakka! Dakka! Dakka!, Devastator Doctrine, Adrenaline Junkies, Wind Walker, and post-advance Custodes stratagems.

- **When:** The target or objective is just beyond a Normal move, the unit's damage is in its [ASSAULT] weapons, and it will not charge or start an action this turn.
- **Units:** Units with [ASSAULT] weapons; riled-up Orks; Shoota Boyz; Adeptus Astartes under Devastator Doctrine
- **Move type:** Advance
- **11e rules (verified):** 10.05 Assault shooting (40k_11th_edition_core_rules.txt:1506-1518). 09.06: after an Advance, no charge or actions until end of turn (:1401-1414). 24.04 [ASSAULT] (:3617-3624). 16.01 (:2816). 15.05 requires the unit not to have advanced (:2659-2662). Devastator Doctrine: .llm/codex_11e_wahapedia/space-marines/RULES.md:231-232. Waaagh! riled up gives [ASSAULT]: orks/RULES.md:76.
- **AI today (partial):** The AI only ever Advances toward an objective or an ATTACK target (AIDecisionMaker.gd:7202-7221, 7242-7255). _should_unit_advance (12650-12748) recognizes advance-and-shoot only through the effect flag or ability text containing 'advance' and 'shoot' (12679-12700). Per-weapon [ASSAULT] is counted only on long trips, by RI-ASSAULT, when every ranged weapon is [ASSAULT] (_ri_ranged_all_assault 12809-12822, used 12984-13008). The EffectPrimitives predicates sit behind FIX_ADV_ENGINE_PREDICATES = 0.0 (2008). There is no 'Advance to a firing position' candidate.
- **Engine support:** Reuse EffectPrimitives.has_effect_advance_and_shoot (EffectPrimitives.gd:850) via _adv_engine_predicates (AIDecisionMaker.gd:12640-12648), _advance_reach_chance (13247) for the roll odds, and RulesEngine.get_eligible_targets on a copy flagged 'advanced'. New: an Advance variant of OFF-01's shoot candidate comparing EV over the D6 of the [ASSAULT]-weapon shots at the reached point with the Normal-move full-arsenal EV.
- **Value (medium):** Frequent for Ork and Doctrine armies and for assault-armed infantry; the AI handles only the all-[ASSAULT] long-trip case.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:1401-1414, 1506-1518
  - 40k/scripts/rules/shootingtypes/AssaultShooting.gd:4-30; 40k/scripts/rules/movetypes/AdvanceMove.gd:4-7
  - .llm/codex_11e_wahapedia/RULINGS.md:124 (Adrenaline Junkies: [ASSAULT] after an advance)
  - .llm/codex_11e_wahapedia/orks/RULES.md:228 (Dakka! Dakka! Dakka!)
- **Found by:** core-rules, web, first-principles, factions

#### OFF-14 — Approach the enemy units your mission cards pay for

Many 11e cards pay for killing particular enemy units, scored at the end of either player's turn. Assassination pays per CHARACTER model (3VP, +1 if W4+; tactical 5VP). Bring It Down pays per W10+ model (4VP). A Grievous Blow pays for units with Starting Strength 13+. No Prisoners pays 2VP per unit. Overwhelming Force pays 3VP per unit that STARTED the turn within range of an objective (max 5). Primaries pay for victims that started the turn on objectives (Purge and Secure 3VP), on a CENTRAL objective (Secure Asset), or inside terrain (Search and Scour), and for Condemned units (Punishment: 5VP each, condemned at the start of your turn mostly from units on objectives). Snapshot the qualifying enemies at the start of the turn and move shooters and chargers into range, LoS or charge reach of them, inside detection range if they are Hidden (OFF-04). The kill still counts if the victim has moved off the objective.

- **When:** Such a card is active and a qualifying target can be killed this turn (or next).
- **Units:** Damage dealers matched to the target profile (anti-tank for W10+, precision for characters, volume for 13+ hordes)
- **Move type:** Normal / Advance (with [ASSAULT]) / charge setup
- **11e rules (verified):** 40k/data/40kdc/missionCards.json awards: purge-and-secure (:232; destroyer_on_objective / victim_started_turn_on_objective, exclusive_group purge-kill), punishment (condemned left-battlefield, either player's turn, 5VP), assassination (3VP per CHARACTER model, +1 if W4+), bring-it-down (4VP per W10+ model), overwhelming-force (3VP per unit that started within range of an objective, max 5). All five were read and checked. Engine auto-condemns enemy units in range of objectives: MissionManager.gd:1754-1795.
- **AI today (partial):** In movement, all pulls are nudges on objective trips using centroid distances: secondary_kill_proximity +2.0 when an objective has a kill-keyword enemy within 12″ (AIDecisionMaker.gd:10452-10468; keywords from Assassination, Bring It Down and A Grievous Blow at 24129-24145), No Prisoners up to +2.0 by proximity (10470-10484), and Overwhelming Force up to +2.5 for enemies within 6″ of an objective (10486-10499). Nothing snapshots start-of-turn positions. Punishment's condemned list is never read by the AI (grep 'condemn': one comment at 1879). Primary kill rules only set kill_pressure, a ×1.15 on Shooting-phase target value (22867-22870, 17878-17880). In the Shooting phase, kill-keyword targets get ×1.4 (17853-17876).
- **Engine support:** Reuse _get_secondary_awareness and _get_primary_awareness (24024-24237, 22800-22888), the MissionManager primary state including the condemned list (MissionManager.gd:1649-1664, 1754-1795), and MissionManager.model_in_objective_range (MissionManager.gd:529) for 'started on an objective'. New: a start-of-turn table of priced victims (unit_id → VP if destroyed this turn) that feeds target value in OFF-01/OFF-02 and replaces the keyword-proximity nudges.
- **Value (medium):** Kill cards pay 2-5VP per kill and F028 is corpus-confirmed, but the AI's shooting already partly prioritizes these targets. The missing piece is moving toward them.
- **Evidence:**
  - 40k/data/40kdc/missionCards.json:232 (purge-and-secure); ids punishment, assassination, bring-it-down, overwhelming-force (awards checked)
  - YouTube Krfpc2el0cA @25:00 (Tabletop Titans, F028): “Overwhelming is good. This is kill things on objectives. It's what I want to do ... you really want to try to get two kills”
  - YouTube 1AwnDclFviQ @552:00 (WarGames Live, F028): “Kill things on objectives. Easy. And do actions”
  - YouTube TPV3hVKSUxw @42:00 (Play On Tabletop, F028): “we've got overwhelming force. So, kill things on objectives”
  - YouTube i7MkaccGXeA @25:00 (TacticalTortoise 40k): “gives you points where you destroy enemies ... So it's a simply a race”
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2272, :2537, :2785, :2516, :2578, :232, :371
  - _…and 3 more_
- **Absorbed duplicates:** MIS-08 (Move toward the enemy unit your cards pay for, to shoot it); MIS-09 (Move toward the enemy unit your cards pay for, to charge it)
- **Found by:** missions, youtube, core-rules

#### OFF-15 — Hunt enemy characters (make the CHARACTER model visible or reachable)

Position [PRECISION] shooters so that a CHARACTER model in the target unit is itself visible to at least one attacking model: Precision can only promote the allocation group of a visible CHARACTER. Separately, move a CHARACTER that can use EPIC CHALLENGE (1CP: its melee weapons gain [PRECISION]) into charge reach of an attached leader, ideally after the bodyguard has been battle-shocked or thinned. Killing characters strips auras and leader buffs and scores Assassination.

- **When:** An enemy leader provides key buffs, Assassination is active or the unit carries the HUNT_CHARACTERS plan verb, and a precision attacker can reach.
- **Units:** [PRECISION] units, snipers, CHARACTERs able to use Epic Challenge, Wolf Guard Headtakers (precision against their quarry)
- **Move type:** Normal (precision sight line) / charge setup
- **11e rules (verified):** 24.28 [PRECISION]: only a CHARACTER model visible to an attacking model can be picked (40k_11th_edition_core_rules.txt:3863-3875). 15.03 EPIC CHALLENGE (:2676-2690). Attached units are a single unit (19). Assassination: missionCards.json 'assassination'.
- **AI today (partial):** The HUNT_CHARACTERS earmark adds +4.0 only in the shooting, charge and fight target scorers (AIDecisionMaker.gd:1373-1395; used at 19183, 20832, 25506). Assassination adds CHARACTER to kill_keywords, giving a +2.0 proximity nudge on objective trips (10452-10468) and ×1.4 shooting priority (17853-17862). CHARGE_CHARACTER_BONUS applies at declaration (19182), and EPIC CHALLENGE is used in the Fight phase (26693-26739). No movement candidate tries to make the CHARACTER model visible to precision shooters or to reach the leader.
- **Engine support:** Reuse TerrainManager.model_visible_11e (TerrainManager.gd:1201) on probe models against the target's CHARACTER model(s), RulesEngine.get_eligible_targets (RulesEngine.gd:7137), and the earmark lookup _plan_earmark_for (AIDecisionMaker.gd:1373-1395). New: a 'character visible from P' term in OFF-01/OFF-03 scoring for [PRECISION] units, and a movement term (not only a target term) for HUNT_CHARACTERS.
- **Value (medium):** Leaders carry big buffs and Assassination pays per model, but it needs specific weapons and reach.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:3856-3875, 2676-2690
  - YouTube efeKiBbPUPM @09:00 (Maelstrom Gaming Studios - Tyranids, F023): “My Neurolictor battleshocked Volus and the Paladins, which allowed both the Neurolictor and the Hive turret to charge in and precision out”
  - docs/rules/11th_edition_doc_change_audit.md (Tab 8: Precision is gated on visibility)
  - 40k/docs/PLAN_FORMAT.md:530 (HUNT_CHARACTERS: 'Additive term in the shooting / charge / fight per-attacker target scorers')
- **Found by:** core-rules, youtube

#### OFF-23 — Advance into charge range when a rule allows advance-and-charge

An 11e Advance forbids charging 'unless otherwise stated'. With a granting rule the unit can Advance M + D6 and still charge. Grants include Orks riled up (Waaagh!, Da Boss is Watchin', Keep Huntin'! ...), Adrenaline Junkies, Assault Doctrine, Berserk Charge, Spear of Chogoris, Sally Forth, and post-advance Custodes stratagems (UNLIMITED ENDURANCE and others). Use it to reach charge range from farther away, and time the Waaagh! so several units benefit at once.

- **When:** The target is beyond a Normal move plus a likely charge but within an Advance plus a likely charge, and the grant is active or affordable.
- **Units:** Orks (riled up), Speed Freeks, Adeptus Astartes under Assault Doctrine, Blood Claws, Custodes infantry
- **Move type:** Advance
- **11e rules (verified):** 09.06 AFTER MOVING: no charge 'unless otherwise stated' (40k_11th_edition_core_rules.txt:1413-1414). 11.02 (:1622). Waaagh! riled up: 'that advance move does not prevent that unit from being eligible to declare a charge' (.llm/codex_11e_wahapedia/orks/RULES.md:76). Assault Doctrine (space-marines/RULES.md:228-229).
- **AI today (partial):** The melee chase gate Advances a melee seeker toward the nearest enemy when it may charge after advancing (flag or ability text, checked against EffectPrimitives.has_effect_advance_and_charge under FIX_WAAAGH_ADVANCE_CHARGE = 1.0; AIDecisionMaker.gd:3058-3087, 1828), or when a Normal move cannot get it within 12″. _should_unit_advance returns true for advance-and-charge units (12702-12704), and 'ERE WE GO is spent when the post-move gap is 6-13″ (26371-26399). Not planned: grants that cost CP after the Advance (Custodes stratagems; CustodesCodexMovement.gd:250-252 per factions#22) and timing a multi-unit Waaagh!. Advance destinations are planned at M + 2″ (7244).
- **Engine support:** Reuse EffectPrimitives.has_effect_advance_and_charge (EffectPrimitives.gd:836), _rile_pending_on_selection (AIDecisionMaker.gd:3072), _advance_reach_chance (13247) and _charge_success_probability (18928). New: joint odds over the advance D6 and the charge 2D6 for a given edge gap, fed into OFF-02's staging scorer.
- **Value (medium):** Defines Ork and Assault Doctrine play. Partly handled, but the AI chases the nearest target and has no odds model.
- **Evidence:**
  - .llm/codex_11e_wahapedia/orks/RULES.md:76 (Waaagh!), space-marines/RULES.md:228-229 (Assault Doctrine)
  - 40k/autoloads/EffectPrimitives.gd:836 (has_effect_advance_and_charge)
  - YouTube QZ9wggn2oUo @04:00 (Tabletop Nexus, F020): “A strong Waaagh! turn has several units positioned to benefit at once”
  - YouTube DHVBk9vnR8w @07:00 (40K Dirtbags, F020): “moved up a little bit like two extra inches forward uh to plan for turn two Waagh”
  - 40k/scripts/AIDecisionMaker.gd:1811-1828 (FIX_WAAAGH_ADVANCE_CHARGE = 1.0: the text test made units Advance and lose the charge; a Normal move measured +6.14 VP over 36 seeds)
  - 40k/scripts/AIDecisionMaker.gd:3064-3080 (the chase gate asks the engine whether a charge after advancing is allowed)
  - _…and 1 more_
- **Absorbed duplicates:** COO-24 (Advance into charge reach when an ability allows a charge after advancing)
- **Found by:** factions, bucket-editor

#### OFF-32 — Line up a Crushing Impact charge

Just after a MONSTER/VEHICLE unit ends a charge move, the 1CP Crushing Impact stratagem rolls D6 equal to one engaged model's T. Each 5+ inflicts a mortal wound on the engaged enemy unit (max 6), and each 1 inflicts one on your own unit. Move a high-T model into charge reach of low-T, wounded or cheap targets such as screens, objective holders or characters. If the target dies, the charger can still pile in (it made a charge move) and make an overrun fight.

- **When:** A high-T MONSTER/VEHICLE is near light infantry or a wounded character, CP is available, and it has nothing better to shoot.
- **Units:** MONSTER, VEHICLE
- **Move type:** Normal (charge setup)
- **11e rules (verified):** 15.06 Crushing Impact (40k_11th_edition_core_rules.txt:2673-2696). 12.03: a unit that made a charge move is eligible to pile in, even if unengaged (:1740-1753). 12.06 Overrun fight (:1866-1877). Worked example (:1772-1781).
- **AI today (none):** The stratagem is only decided after a successful charge (evaluate_tank_shock AIDecisionMaker.gd:27346, called at 18287-18296, labelled Crushing Impact at 11e, 27379-27380). Neither charge_intent nor charge scoring adds its EV, so movement never sets it up.
- **Engine support:** Reuse evaluate_tank_shock's EV maths (27346-27470). New: add Crushing Impact EV (about T/3 mortal wounds on the target minus T/6 on our unit, capped) to charge_intent for MONSTER/VEHICLE units when CP ≥ 1.
- **Value (low):** Modest mortal-wound damage for 1CP, and only for MONSTER/VEHICLE units.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:2673-2696, 1737-1781
  - 40k/autoloads/StratagemManager.gd:5054-5062
  - 1d6chan 11e tactics https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics (search snippet: renamed Tank Shock, now usable by monsters too)
  - docs/AI_11E_UPGRADE_PLAN.md (WS1 1.6 Crushing Impact EV)
  - 40k/autoloads/StratagemManager.gd:5054-5062 (crushing_impact)
  - 40k/scripts/AIDecisionMaker.gd:27346-27420 (evaluate_tank_shock: T dice, expected T/3 mortal wounds, T/6 to self)
- **Absorbed duplicates:** COO-41 (Set up a Crushing Impact charge)
- **Found by:** core-rules, web, first-principles

#### OFF-34 — Climb for Plunging Fire, or bring a TOWERING model within 12″

Ranged attacks against a visible unit with models on ground level get +1 BS if the attacking model is on a terrain section 3″ or more high, or if it is TOWERING and the target is within 12″. Only INFANTRY/BEASTS/SWARM/FLY/MONSTER models may end a move on upper levels. Climbing distance counts toward the move, and models must stay within ½″ of the feature while climbing. The +1 offsets the −1 BS from the target's cover. Plunging Fire has no effect on attacks by or against AIRCRAFT.

- **When:** Shooters next to tall ruins facing ground-level targets in cover (a climb of 3″ or less also keeps [HEAVY]), or TOWERING models closing to 12″.
- **Units:** INFANTRY/BEASTS/SWARM/FLY/MONSTER climbers; TOWERING models (e.g. the Stompa in armies/recon_stomps.json)
- **Move type:** Normal
- **11e rules (corrected):** 22.05 Plunging Fire (40k_11th_edition_core_rules.txt:3453-3462). 13.06 moving vertically and ending a move on non-ground surfaces (:2184-2208). 23.03: Plunging Fire has no effect by or against AIRCRAFT (:3522). 13.08: cover worsens BS by 1 (:2289-2290). Correction: core-rules#30 and web#20 say Plunging Fire 'cancels' cover. It does not remove cover; its +1 BS offsets cover's −1 BS, so 'cancels' is only true of the net hit roll.
  - _Errata check:_ A FLY unit that takes to the skies ignores vertical distance and, per FAQ, that vertical movement does not count toward [HEAVY]'s 3″, so it can reach a 3″+ perch and keep [HEAVY] if no model moves more than 3″ horizontally. BS is clamped to 2+ to 6+ after all modifiers, so Plunging Fire does nothing for a BS 2+ model against an uncovered target or for a BS 6+ model against a covered one. — FAQ on [HEAVY] and taking to the skies (errata doc, filed under 23.04); Commentary 02.02.01 Modifiers (BS cannot be 1+ or better, or 7+ or worse)
- **AI today (none):** AIDecisionMaker.gd never mentions Plunging Fire or TOWERING (grep -i 'plunging|towering': 0).
- **Engine support:** Reuse TerrainManager.plunging_fire_applies (TerrainManager.gd:1425). New: a TOWERING 12″ entry in OFF-10's band table. The climbing branch needs engine support for model elevation first.
- **Value (low):** +1 BS is good, but the engine cannot climb today and TOWERING models are rare.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:3453-3485, 2184-2213
  - 40k/autoloads/TerrainManager.gd:1419-1442 plunging_fire_applies
  - Engine gap: model elevation_inches is only read (TerrainManager.gd:1120, 1192, 1430, 1435) and never written outside tests, so the climbing branch cannot trigger in play; only the TOWERING branch is live
  - BoLS '11th Edition Terrain Rules Revealed' https://www.belloflostsouls.net/2026/04/warhammer-40k-11th-edition-terrain-rules-revealed-redefining-terrain-on-the-tabletop.html
- **Found by:** core-rules, web, first-principles

#### OFF-37 — Route toward the marked quarry or oath target

Mark abilities pick an enemy unit at the start of the battle, and pick a new one when it dies. These units should head for their mark rather than for the nearest enemy or objective. Examples: Headhunters (attacks against the quarry gain [DEVASTATING WOUNDS] and [PRECISION]), Slayer's Oath, Forward Assault Warsuit, Sword of the Throne (+1 to wound against the mark), Assemblage of Might.

- **When:** The mark is reachable within one or two turns and the unit's other jobs are not urgent.
- **Units:** Ulrik the Slayer, Wolf Guard Headtakers, Invictor Tactical Warsuit, Blade Champion, Custodes characters
- **Move type:** Normal (approach / charge setup)
- **11e rules (verified):** Datasheet text: Headhunters (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:791); Sword of the Throne (custodes/wahapedia/Datasheets_abilities.csv:106).
- **AI today (none):** Marks are chosen when offered (SWAbilities11e.gd:1830: slayers_oath/headhunters 3.0; CustodesAbilities.gd:1318: sword_of_the_throne 3.0), but AIDecisionMaker.gd never reads a mark or quarry (grep 'quarry|oath': 0).
- **Engine support:** Reuse the codex mark state set through SWAbilities11e and CustodesAbilities. New: a target-value multiplier for the unit's own mark in charge_intent and in OFF-01's shoot candidates.
- **Value (low):** A handful of characters and units; a big bonus on the marked target only.
- **Evidence:**
  - .llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:791 (Headhunters), :307 (Slayer's Oath), :369 (Forward Assault Warsuit)
  - .llm/codex_11e_wahapedia/custodes/wahapedia/Datasheets_abilities.csv:106 (Sword of the Throne)
  - 40k/scripts/codex/space_wolves/SWAbilities11e.gd:1830; 40k/scripts/codex/custodes/CustodesAbilities.gd:1318 (mark chosen, score 3.0)
- **Found by:** factions

#### OFF-39 — Make a normal move to arm move-gated buffs (Walking Fortress)

Gravis Linebreaker Force's Walking Fortress: in a turn a GRAVIS unit made a normal move, its ranged attacks lose [HEAVY] and gain +1 to hit. So any Normal move, even a token step into cover, onto an objective or to a better angle, beats Remaining Stationary or Advancing for these units. It is the inverse of the Heavy hold.

- **When:** The army uses Gravis Linebreaker Force and a GRAVIS unit has ranged targets.
- **Units:** GRAVIS units (Heavy Intercessors, Aggressors, Eradicators, Gravis characters)
- **Move type:** Normal
- **11e rules (verified):** Walking Fortress text (.llm/codex_11e_wahapedia/space-marines/RULES.md:674). Engine: SMDetachmentsB.gd:349 walking_fortress_applies. 09.05 Normal move (40k_11th_edition_core_rules.txt:1390-1397).
- **AI today (none):** AIDecisionMaker.gd has 0 references to Walking Fortress. T7-26 (7419-7430) would hold a GRAVIS unit with [HEAVY] weapons in place, forfeiting the +1 to hit that a normal move grants.
- **Engine support:** Reuse SMDetachmentsB.walking_fortress_applies (SMDetachmentsB.gd:349). New: a generic 'move-gated buff' predicate checked by the Heavy hold and OFF-06, which skips the hold and requires a normal move.
- **Value (low):** One detachment, but the AI's current behaviour is actively wrong for it.
- **Evidence:**
  - .llm/codex_11e_wahapedia/space-marines/RULES.md:674
  - 40k/scripts/codex/space_marines/SMDetachmentsB.gd:349
- **Found by:** factions

#### OFF-33 — Fall back to re-charge or shoot when a rule allows it

11e Fall Back normally forbids shooting, charging and actions. With a granting rule it becomes a tactical reset: leave a grinding or losing combat and re-charge a better target, or the same one, to regain Fights First and on-charge bonuses (Lance, Hammer of Wrath, Crushing Impact and similar), or fall back and shoot. Granting rules include Tactical Doctrine (shoot and charge), Suspiciously Well Organised (Boyz/Kommandos/Stormboyz: charge), Adrenaline Junkies, Talon Sortie and MANOEUVRE AND FIRE. Ordered Retreat is only available to units that are not battle-shocked; Desperate Escape forces hazard rolls and a battle-shock roll.

- **When:** The unit is engaged with something the fight will not kill or is not worth it, a better target is within charge reach after the fall-back, and the on-charge payoff outweighs staying.
- **Units:** Adeptus Astartes under Tactical Doctrine, Boyz/Kommandos/Stormboyz (Taktikal Brigade), Speed Freeks, Custodes (Solar Watch)
- **Move type:** Fall Back
- **11e rules (verified):** 09.07: no shooting, charging or actions 'unless otherwise stated'; Ordered Retreat and Desperate Escape modes (40k_11th_edition_core_rules.txt:1417-1441). Tactical Doctrine (.llm/codex_11e_wahapedia/space-marines/RULES.md:234-235). Suspiciously Well Organised (orks/RULES.md:184). 11.04 Fights First (:1664-1665).
- **AI today (partial):** _decide_engaged_unit reads AIAbilityAnalyzer.can_fall_back_and_charge and can_fall_back_and_shoot (AIDecisionMaker.gd:12012-12013). Fall-back-and-charge skips the late-game and sole-holder holds (12051, 12095-12097) and adds to the logged reason (12111-12138). The fall-back destination (12185-12273) is not chosen for a re-charge target, and nothing compares the re-charge EV with staying. Detection is a text match on 'fall back' with a space (AIAbilityAnalyzer.gd:261-266, 317-336) plus effect flags, so 11e grants written as 'fall-back' are likely missed unless a flag is set (static reading, not run).
- **Engine support:** Reuse EffectPrimitives.has_effect_fall_back_and_charge / _shoot (EffectPrimitives.gd:814-833), _compute_fall_back_destinations (AIDecisionMaker.gd:12185) and OFF-02's staging scorer. New: when the unit can charge after falling back, set the fall-back destination to the best re-charge staging point (OFF-02).
- **Value (low):** Faction-specific, though strong where it applies; the detection gap may hide it entirely.
- **Evidence:**
  - .llm/codex_11e_wahapedia/space-marines/RULES.md:234-235; orks/RULES.md:184
  - 40k/autoloads/EffectPrimitives.gd:814-833 (has_effect_fall_back_and_shoot / _charge)
  - 40k/scripts/AIAbilityAnalyzer.gd:261-266, 317-336 (text match on 'fall back' with a space)
- **Found by:** factions

#### OFF-35 — Ram a doomed Deadly Demise model into enemies

A badly damaged DEADLY DEMISE model that will probably die in the next enemy turn ends its move (or charge) within 6″ of as many valuable enemy units as possible. When it is destroyed, a 6 on one D6 inflicts X mortal wounds on EVERY unit within 6″, friend or foe.

- **When:** A doomed vehicle or monster with nothing better to do, and no friendly units within 6″ of the end position.
- **Units:** DEADLY DEMISE models
- **Move type:** Normal (or charge)
- **11e rules (verified):** 24.08 Deadly Demise X: on a 6, each unit within 6″ suffers X mortal wounds (40k_11th_edition_core_rules.txt:3670-3685).
- **AI today (partial):** An override (AIDecisionMaker.gd:7466-7489): a VEHICLE/MONSTER with Deadly Demise that is_unit_doomed (25% of wounds or less) makes a full Normal move at the nearest enemy centroid with threat avoidance off, overriding its objective. It ignores the 1-in-6 trigger, friendly units within 6″ (24.08 hits every unit), the value of enemy clusters, and whether the model should keep shooting instead. In the Charge phase the score is multiplied by dd_bonus (18632-18635, 19404).
- **Engine support:** Reuse AIAbilityAnalyzer.has_deadly_demise, get_deadly_demise_value and is_unit_doomed (AIAbilityAnalyzer.gd:546-616). New: an endpoint search maximizing Σ(enemy units within 6″ × value) − Σ(friendly units within 6″ × value), weighted by 1/6 × P(dies next turn).
- **Value (low):** Only a 1-in-6 payoff, and the AI already has a crude version of it.
- **Evidence:**
  - docs/rules/40k_11th_edition_core_rules.txt:3670-3699
  - 40k/scripts/AIDecisionMaker.gd:7466-7489 (override), :18632-18635 and :19404 (ch_deadly_demise)
  - 40k/scripts/AIAbilityAnalyzer.gd:546-616 (has_deadly_demise / is_unit_doomed)
  - 40k/autoloads/RulesEngine.gd:17462 (Deadly Demise resolution, hits every unit within 6″)
  - 40k/scripts/AIAbilityAnalyzer.gd:546-616 (has_deadly_demise and related helpers)
- **Absorbed duplicates:** COO-44 (Ram a dying Deadly Demise vehicle into enemy clusters)
- **Found by:** core-rules, first-principles

### Objective play & tempo

#### OBJ-06 — Move into cover on the objective: hold from a Hidden or obscured spot inside its terrain area

Because the terrain area IS the objective, holders need not stand in the open part of it. A holding unit whose models are all INFANTRY/BEASTS/SWARM within the area has the benefit of cover: attacks against it worsen BS by 1. In an area with dense terrain, its models are Hidden (visible only to enemies within 15in) while the unit has not shot this turn or last. Behind Solid walls, or across obscuring areas, they can be out of line of sight entirely. Shuffle the holders to the spots in the area that are Hidden or out of sight of the main shooters and away from the side the enemy will charge from, keeping the OC needed in range. Use a short Normal Move, or no more than 3in so [HEAVY] still applies. This is the objective form of the user's 'move into cover'.

- **When:** Holding against shooting armies; the objective area contains dense or light features or Solid walls; the holders are INFANTRY/BEASTS/SWARM; the holder can skip shooting (for Hidden) or only needs cover; the opponent is paid for kills on objectives.
- **Units:** INFANTRY/BEASTS/SWARM objective holders (vehicles and monsters use OBJ-15 instead).
- **Move type:** Normal Move (short reposition within range) / Remain Stationary
- **11e rules (corrected):** 14.02: within range while within the area (40k_11th_edition_core_rules.txt:2405-2406). 13.08: benefit of cover when every model is INFANTRY/BEASTS/SWARM within a terrain area or not fully visible; BS worsened by 1 (:2279-2290). 13.09 Hidden: inside an area with dense terrain, no ranged attacks this turn or the previous turn, 15in detection range (:2292-2303). 13.10 obscuring (:2305-2310). 13.11 Solid (:2313-2315). 24.16 [HEAVY]: +1 to hit if no model moved more than 3in (:3751-3768).
  - _Skeptic:_ 13.09 Hidden needs a terrain area containing one or more light OR dense features (errata_faq:529), not 'an area with dense terrain'. The rest is correct: 14.02 range = within the area, 13.08 −1 BS, 13.10/13.11, [HEAVY] for moves of 3″ or less. — 40k_11th_edition_errata_faq_commentary.md:529; 40k_11th_edition_core_rules.txt:2278-2316, 2405-2406, 3759-3768
  - _Errata check:_ Hidden needs a terrain area containing one or more light OR dense terrain features (not only dense), and the unit must have made no ranged attacks this turn or the previous turn (the previous-turn condition is automatically met in the first turn). A Hidden holder that is also not fully visible to an attacker because of intervening dense terrain features has gone to ground: its detection range against that attacker drops by 3in (15in to 12in), so keep dense walls between the holders and the main shooters. — 13.09 errata; Commentary 13.11.01 Gone to Ground; Commentary 13.09.01 Hidden and the First Turn
- **AI today (none):** A hold executes as REMAIN_STATIONARY immediately (AIDecisionMaker.gd:7187-7200); there is no 'hold but reposition within range'. Hidden-seeking is implemented but ships off (WEIGHT_HIDDEN_GAINED = 0.0 at 2633), and it is only evaluated at the endpoints of objective trips (10306-10314). The cover nudge (14817-14877) only checks for any polygon between the endpoint and enemy centroids, ignoring 13.08 / 13.10 / 13.11. Objective evaluation gives the area's own terrain no value.
- **Engine support:** Reuse TerrainManager.is_model_hidden (TerrainManager.gd:999), unit_has_cover_11e (1380), model_visible_11e (1201), is_obscured_between (976), area_at / category_of (792-950); LineOfSightManager.calculate_los_to_position (LineOfSightManager.gd:101); MissionManager.model_in_objective_range (MissionManager.gd:529); the probe pattern in _position_would_be_hidden (AIDecisionMaker.gd:28515). New: an in-area reposition generator. It samples model positions inside the hosting area within M (3in for [HEAVY] units), keeps the needed OC in range and the unit in coherency, and scores each spot by which enemy shooters could see or target it and by charge exposure.
- **Value (high):** Keeps the scoring unit alive through the enemy turn at no OC cost, and the AI never does it.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2279-2315, :3751-3768
  - YouTube 0Gcpze1G4Lc @10:00 (40K Dirtbags): "I try and get that dense cover for the hidden 12 ... How fast can I get to hidden 12" (ai_learnings.json F001)
  - YouTube Enm67qaqHkU @07:00 (40K Dirtbags): "these guys won't be able to shoot me turn one if everybody's hidden"
  - ai_learnings.json F001 ai_impact.risk: 'Gate it against the objective VP estimator so it never outbids a scoring move.'
  - https://www.belloflostsouls.net/2026/04/warhammer-40k-terrain-objectives-how-they-work-in-11th-edition.html (search snippets: holding a terrain objective usually gives your unit cover; staying hidden and holding objectives with infantry is a common approach)
  - https://zatu.com/en-us/blogs/news/the-road-to-11th-edition-terrain-and-objectives (web-stream result)
  - _…and 4 more_
- **Absorbed duplicates:** MIS-15 (Move into cover or Hidden on a scoring spot that must survive the enemy turn)
- **Found by:** web, youtube, core-rules, missions

#### OBJ-01 — Hold objectives through the opponent's turn for your next Command-phase score

From round 2 most 11e primaries pay at the end of YOUR Command phase: Battlefield Dominance 3VP per objective, Immovable Object 5VP per non-home objective (R2-4), Purge and Secure / Unstoppable Force / Search and Scour 4VP per non-home objective, Outmanoeuvre 5VP per non-home objective (R2-3), and a flat 4VP for holding 1+ non-home objective on most other cards. Burden of Trust and Defend Stronghold score at the end of the opponent's turn. Control is re-totalled after the opponent's whole turn and after your own battle-shock step, which runs before mission scoring. So the move that scores is made the turn before. Leave a holder in place (Remain Stationary, or a short move that keeps a model in range) that will still control the objective at that check: durable, out of enemy reach and line of sight where possible, with an OC margin over what the enemy can bring in one move, and not at or below half strength (it must pass a battle-shock roll first). Do not move or redeploy a scoring unit off the objective during this window.

- **When:** Rounds 1-4, for every objective your next Command-phase rows pay for (round-1 positions set up the round-2 score). Also at the end of your turn whenever Burden of Trust or Defend Stronghold (R2+) is active. Not round 5, where Command rows score at the end of your own turn (see OBJ-04).
- **Units:** Durable OC holders: Battleline, high-OC vehicles and monsters, full-strength squads, units inside Ld/OC auras. Avoid units at or below half strength.
- **Move type:** Remain Stationary (or a short Normal Move that keeps a model in range)
- **11e rules (verified):** 14.02: control is determined at the end of each phase and turn from summed OC, and a tie leaves the objective uncontrolled (40k_11th_edition_core_rules.txt:2401-2419). 08.03: the battle-shock step rolls for units at or below half-strength (:1242-1255), before 08.05 mission scoring (:1264-1275). 01.07: battle-shocked models have OC '-' (:216-217). 09.04 Remain Stationary (:1378-1388). GDM timing key 'C = your Command phase (switches to end of turn in Round 5)' (11th_edition_missions_gdm2026.md:7). missionCards.json Command rows {end-of-phase, command, battle_round min 2} (battlefield-dominance :3, immovable-object :108, outmanoeuvre :854) and end-of-opponent's-turn rows (burden-of-trust :2225, defend-stronghold :2706).
- **AI today (partial):** The hold pass keeps one keeper whose OC beats the enemy OC on the objective or one move away (AIDecisionMaker.gd:10606-10660, OBJ-HOLD-2 / KEEP-OC / KEEPER-PICK). _build_primary_awareness prices next round's Command rows during this round's moves (22838-22845). There is a stay_on_objective bonus of +5/+6/+7 (10205-10216) and retention bonuses (9302-9320). Not modelled: whether the holder survives the opponent's shooting and charges; the battle-shock roll a holder at or below half strength must pass before scoring (movement has no half-strength logic); turn order. 'Threatened' means any enemy unit within 12in (9170-9175). A hold always executes as REMAIN_STATIONARY (7187-7200), so the AI never looks for a safer spot within range (see OBJ-06). A battle-shocked holder can still be picked as keeper, because candidate unit_oc comes from _unit_alive_oc (13432-13439).
- **Engine support:** Reuse _ri_enemy_next_move_oc (AIDecisionMaker.gd:12839), _estimate_incoming_melee_damage (12350), _evaluate_position_threat (28794), _estimate_unit_value (28003), _unit_oc_at_position (13054), the probe pattern in _position_would_be_hidden (28515) and _evaluate_insane_bravery (26177). New query: P(this holder still controls at my next Command phase) = f(enemy OC that can reach range, expected enemy shooting and melee damage on the holder, P(failing the 08.03 roll) when alive models are at or below half starting strength). Use it to rank holders and to trigger reinforcement (OBJ-05).
- **Value (high):** Most 11e primary VP (the Command rows in R2-4) is decided by this move; one lost holder costs 3-5VP per objective per round.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1242-1275 (08.03 battle-shock step, then 08.05 mission scoring)
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2409-2419 (14.02: end of each phase and turn; a tie is not controlled)
  - /home/user/warhammer-40k-godot/docs/rules/11th_edition_missions_gdm2026.md:7 (timing key)
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:3, :108, :854, :2225, :2706
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:22838-22845 (comment: Command-phase rules 'score at the start of the NEXT round's turn, from what this round's moves hold')
  - YouTube veM7sLjtdIw @01:00 (Warpbane Tactics): "being careful about when we use our teleportation. Picking a unit up is incredibly useful, but under Take and Hold, that decision becomes more costly" (ai_learnings.json F027)
  - _…and 3 more_
- **Found by:** missions, core-rules, web, first-principles

#### OBJ-03 — Contest an enemy-held objective to deny their next score and break their majority

When you cannot out-OC the holder, move just enough OC into range to TIE their level of control. A tie leaves the objective uncontrolled (unless they secured it). That removes it from their next Command-phase rows (per-objective, hold 1+ and threshold) and from their count for majority rows (Battlefield Dominance, Inescapable Dominion, Punishment, Consecrate, Destroyer's Wrath, Surveil the Foe). With more OC you flip it outright. Between the end of your turn and their scoring, only their Command phase happens: their own battle-shock rolls and Command-phase abilities. So an end-of-your-turn contest in rounds 1-4 almost certainly denies that score. Expendable units are fine here: the VP denied outweighs the unit.

- **When:** The opponent holds a non-secured objective that their card pays for at their next Command phase, and you can bring equal OC. Majority rows are tied or within one. Your turns in rounds 1-4. From the opponent's round-5 turn, their Command rows score at the end of THEIR turn, so a contest must then survive their whole turn, unless it is made in the last turn of the game (OBJ-04).
- **Units:** Any unit with OC 1+ that is not battle-shocked: cheap fast units, deep strikers, multi-model infantry.
- **Move type:** Normal Move / Advance (also via Deep Strike or Rapid Ingress arrivals)
- **11e rules (verified):** 14.02: a tie means not controlled unless secured (40k_11th_edition_core_rules.txt:2417-2419). 14.03: a secured objective needs strictly greater control to flip (:2427-2435). 08.03: only the active player's units take battle-shock rolls (:1242-1251); 08.05 scoring follows (:1264-1275). 07.02: the same player takes the first turn every round (:1135-1139). GDM timing key (11th_edition_missions_gdm2026.md:7); 11th_edition_doc_change_audit.md:197 applies the round-5 switch to both players. missionCards.json 'objective-majority' rows: battlefield-dominance :3, inescapable-dominion :159, punishment :371, destroyers-wrath :560, consecrate :646, surveil-the-foe :1757.
- **AI today (partial):** The only support is a heuristic T10-1 denial bonus on enemy_weak / enemy_strong objectives, and it starts in round 3 (AIDecisionMaker.gd:9289-9301), although the opponent scores from round 2. The OC need for an enemy-held objective is enemy_oc - friendly_oc + 1 (oc_needed at 9370; _initial_objective_oc_needs at 9405-9440), so a tie never counts as achieving anything. hold_more pricing values flips only (22996-23001). The opponent's cards are never read: _get_primary_awareness and _get_secondary_awareness are only called for the AI's own player (9340, 9623, 10355, 10380, 11060, 17854, 17879). There is no turn-order logic.
- **Engine support:** Reuse _reachable_contest_oc (AIDecisionMaker.gd:13449), _get_oc_at_position (13030), the evaluation's enemy_oc / contest_oc / projected_enemy_oc fields, and MissionManager.player_primary_missions[opponent] (the opponent's card, priced with the same PrimaryMissionData11e rule schema). New: denial_vp(objective) = the VP the opponent's next scoring window loses if the objective is uncontrolled. Add a 'tie is enough' OC target (enemy_oc) next to the flip target (enemy_oc + 1).
- **Value (high):** Denying a Command-phase score swings as much VP as scoring one; players cite primary denial as the main way to win in 11e.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2401-2435
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:910-920 (equal OC -> controller 0, contested flag)
  - YouTube EBJW0VDeT_Q @45:00 (40K Dirtbags): "win on primary by denying primary and stuff like that. It's really the only way to to win 40k" (ai_learnings.json F011)
  - YouTube 9fuvetVLB3s @29:00 (Master Crafted): "they don't have to kill you. It's just going to take you five turns to kill their army and they're just going to keep scoring" (F011)
  - YouTube TJQWtTZiP1g @02:00 (Zeeto): "That sort of Battleshock um OC denial sort of list ... would probably work well in teams" (F009)
  - https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics (search snippet: control is the total OC in range at the end of each phase)
  - _…and 6 more_
- **Absorbed duplicates:** DEN-08 (Contest the objectives the opponent's cards need to control)
- **Found by:** core-rules, missions, web, first-principles, youtube

#### OBJ-04 — Go all-in on objectives in the final round

In round 5 the Command-phase rows score at the end of your own turn, so survival no longer matters for them. Drop exposure and Hidden preferences. Advance freely, since it only costs this turn's charge and actions. Charge or consolidate onto objectives, contest every enemy objective you can reach, and pour units into the end-of-battle bonus areas: enemy home 5/8/10VP, central 5VP, hold 4+ objectives 10VP, no enemy wholly in your territory 5VP, 4+ decoyed objectives 10VP. Turn order matters. The second player's round-5 turn is the last of the game, so nothing it takes or contests can be retaken, and that includes contesting the opponent's end-of-battle objectives. The first player's end-of-battle holdings must still survive the opponent's last turn.

- **When:** Battle round 5 (plan it from late round 4). Price it differently for the first and the second player.
- **Units:** Every unit, including characters, vehicles and units normally kept back.
- **Move type:** Advance / Normal Move
- **11e rules (corrected):** GDM timing key: 'C ... switches to end of turn in Round 5' (11th_edition_missions_gdm2026.md:7); 11th_edition_doc_change_audit.md:197 applies it to both players. missionCards.json: battlefield-dominance text ('or end of your turn in the fifth battle round', :3); immovable-object round-5 end-of-turn row (:108); end-of-battle rows (unstoppable-force :302, inescapable-dominion :159, punishment :371, vital-link :1412, vanguard-operation :1597, triangulation :1874, search-and-scour :2005, smoke-and-mirrors :1100). 07.02: the same player goes first every round (40k_11th_edition_core_rules.txt:1135-1139). 09.06: an Advance only bars charges and actions (:1401-1414).
  - _Skeptic:_ '09.06: an Advance only bars charges and actions' is wrong as stated. An advanced unit can only use assault shooting with [ASSAULT] weapons (10.04 :1489-1491, 10.05 :1506-1516). It cannot use close-quarters or indirect shooting (10.06 :1524, 10.07 :1553) or Explosives (15.05 :2659-2662). A transport that advanced cannot be disembarked from (18.04 :3024-3025). The round-5 timing and card rows are correct. — 40k_11th_edition_core_rules.txt:1401-1414, 1489-1516, 1524, 1553, 2659-2662, 3024-3025; 11th_edition_missions_gdm2026.md:7; missionCards.json:3, 108
- **AI today (partial):** Late-game urgency adds +2.5 to contested / enemy_weak objectives (x0.8 for uncontrolled) in R4-5 and +1.0 to enemy_strong in R5 (AIDecisionMaker.gd:9261-9268), with STRATEGY_LATE_OBJECTIVE 1.6 (2723) and a 7.0 stay bonus (2260). Working against the intent, the same R4-5 strategy raises threat avoidance (STRATEGY_LATE_SURVIVAL 1.4 at 2724, multiplying threat_delta at 10285-10288) and makes the AI less willing to charge (STRATEGY_LATE_CHARGE 1.3 at 2725). There is no first/second-player logic anywhere. End-of-battle rows are priced in every round (FIX_EOG_TIMING = 0.0 at 1886), so round 5 gets no extra end-of-battle push.
- **Engine support:** Reuse _get_round_strategy_modifiers (AIDecisionMaker.gd:17421), _build_primary_awareness (22800) and the timing of MissionManager.score_primary_eog_11e. New: a 'last turn' context (round 5, plus whether this player moves last) that zeroes the threat, Overwatch and Hidden terms for scoring moves and prefers Advancing onto any reachable objective. When this player moves last, it also adds the opponent's end-of-battle objectives to the contest set.
- **Value (high):** The final turn regularly swings 10-25VP, and the AI's R4-5 modifier currently pushes survival the wrong way.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1137-1150 (round 5: Command-phase primary scoring deferred to end of turn)
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:2598-2606 (score_primary_eog_11e: both players, once, at the end of the battle)
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:13-17 (Command rows for rounds 2-4 plus the round-5 end-of-turn row translated as one rule)
  - /home/user/warhammer-40k-godot/docs/rules/11th_edition_doc_change_audit.md:197
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1135-1139
  - YouTube mbNWzDn6Pu4 @10:00 (Exile Wargaming): "we did win the dice roll and had to go first, which I don't really like in recon" (ai_learnings.json F019)
- **Found by:** core-rules, missions, first-principles

#### OBJ-05 — Reinforce a contested or threatened objective to win the OC count

Move a second OC source onto an objective you hold or contest when the enemy could match or beat your level of control at the next check. Three cases: enemy OC is already in range; enemy OC is one move away; or the holder is at or below half strength and must pass a battle-shock roll in your Command phase before scoring (failing makes its OC '-'). Count only models that are not battle-shocked.

- **When:** Contested objectives; held objectives with enemy OC in range or one move away; a lone half-strength holder before your next Command phase; an objective that decides a majority or threshold row.
- **Units:** Any unit with OC 1+ that is not battle-shocked; high-OC multi-model infantry.
- **Move type:** Normal Move / Advance
- **11e rules (verified):** 14.02: the highest summed OC of models in range controls (40k_11th_edition_core_rules.txt:2409-2416). 01.07: battle-shocked models have OC '-' (:216-217). 08.03: units at or below half-strength roll in your Command phase (:1242-1255), before 08.05 mission scoring (:1264-1275).
- **AI today (partial):** Reinforcement is generated. held_threatened objectives get an OC need sized against the enemy OC there and the projected enemy OC one move away (_initial_objective_oc_needs, AIDecisionMaker.gd:9405-9440). Pass 2 assigns and narrates 'reinforce' (10999-11252), and RI-RACE keeps only part of the value when the race is lost (10153-10180). Missing: the holder's own battle-shock risk (movement has no half-strength logic, and Insane Bravery is only priced in the Command phase, 26177), and OC lost to kills on the holder.
- **Engine support:** Reuse _initial_objective_oc_needs (AIDecisionMaker.gd:9405), _ri_enemy_next_move_oc (12839) and the 2D6-vs-Ld failure maths in _battle_shock_flip_value (26051). New: when the holder is at or below half starting strength, add P(fails battle-shock) x holder OC to the objective's OC need.
- **Value (high):** Directly protects the next Command-phase score; a battle-shock roll just before scoring is an 11e-specific failure mode.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1242-1275, :2409-2416
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:9405-9440 (COORD-5: OC need sized against projected enemy OC)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:1777-1797, 10153-10180 (RI-RACE reinforcement race)
  - YouTube qwnHaQvzCq0 @14:00 (Grimdark Breakdown): "If you Battle Shock me, I go to 1 OC instead of 0" (ai_learnings.json F009)
  - YouTube ewxyBDMvC64 @23:00 (The Six Machine): "it is more likely that you will get battleshocked and potentially stay battleshocked" (F009)
- **Found by:** core-rules, missions

#### OBJ-07 — Flip an objective you did not control at the start of your turn

Determined Acquisition pays 2VP at the end of your turn for every objective you newly controlled this turn, in every round. Purge and Secure and Unstoppable Force pay 3VP at the end of your turn, from round 2, for taking a non-home objective you did not control at the start of the turn. Control at the start of the turn is recorded, so every uncontrolled, contested or enemy-held objective is a target. Movement comes before Shooting and Fight, so the plan can be: move enough OC into range now, then remove the enemy OC with shooting, charges, fights or battle-shock before the end of the turn (OBJ-09, OBJ-10). Deep strike or ingress onto an uncontested objective also counts. Prefer such flips to sitting on objectives you already hold.

- **When:** One of those cards is active and at least one objective was not yours at the start of the turn. Prefer objectives where your OC after shooting will exceed theirs.
- **Units:** Fast OC units, melee units that charge onto the objective, deep strikers, ranged units that clear holders first.
- **Move type:** Normal Move / Advance / Reserves arrival
- **11e rules (corrected):** missionCards.json determined-acquisition: 'objective-newly-controlled-this-turn', 2VP at the end of your turn, every round, with no home exclusion (:63). The GDM summary row says 'excl. home', but neither the official dataset nor the engine excludes it (PrimaryMissionData11e.gd:142). purge-and-secure (:232) and unstoppable-force (:302): 'new-objective-controlled', 3VP from R2 (non-home in the engine: PrimaryMissionData11e.gd:124, :157). 14.02: control at the end of the turn (40k_11th_edition_core_rules.txt:2409-2416). Start-of-turn control is recorded at MissionManager.gd:1726-1731.
- **AI today (partial):** The VP estimator adds the card's hold_new / per_new_objective VP to every objective not currently held (AIDecisionMaker.gd:23013-23016), so capture candidates are priced. Gaps: 'held' means current control, not the start-of-turn control MissionManager records (MissionManager.gd:1731). The branch ignores exclude_home, so it also prices the home objective for Purge and Secure / Unstoppable Force. The plan never sequences 'step in now, kill the holders later this turn': an enemy_strong objective gets -5 priority (2561; state set at 9177-9186) even when this turn's shooting or charges would clear it.
- **Engine support:** Reuse _estimate_objective_vp_value (AIDecisionMaker.gd:22928), MissionManager._control_at_turn_start (MissionManager.gd:88, 1731; needs a getter), and the lock targets / charge intents in _build_phase_plan (AIDecisionMaker.gd:3773). New: a combined 'clear-then-step' candidate that pairs an OC mover with the shooting or charge expected to remove the holder's OC this turn, priced by P(holder destroyed or shocked).
- **Value (high):** Three primaries pay every turn for fresh captures; it rewards flipping over sitting.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:63, :232, :302
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:124, :138-147, :157
  - /home/user/warhammer-40k-godot/docs/rules/11th_edition_missions_gdm2026.md:19-20 (summary rows for Determined Acquisition / Unstoppable Force)
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1726-1731 (_control_at_turn_start snapshot), :2670, :2698 (used by the new-objective rows)
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-purge-the-foe/ (web-stream search snippet)
- **Found by:** core-rules, missions, web, first-principles

#### OBJ-08 — Grab an objective for this turn's end-of-turn award even if you will lose it

End-of-turn rows pay for control at the end of YOUR turn, so a capture scores even if the opponent retakes it next turn. Commit expendable or exposed units to these:
- Battlefield Dominance: majority, 2VP (R1-2).
- Immovable Object: central, 3VP every turn.
- Inescapable Dominion: 4VP for 3+ objectives.
- Determined Acquisition: 2VP per new objective.
- Outmanoeuvre: 4VP per non-home objective (R1), 6VP per non-home objective (R4+), 10VP for the enemy home in any turn.
- Meatgrinder: enemy home, 5VP (R2+).
- Gather Intel: central, 6VP (R1).
- Search and Scour: central, 3VP.
- Vital Link: central, 2VP plus markers.
- Delaying Action: central plus an expansion objective, 3VP (R2+).
- Secondaries: Forward Position, Secure No Man's Land and A Tempting Target, 5VP each.
Count the OC that charges and Objective Consolidation will add before the end of the turn.

- **When:** Inside those round windows, especially when the objective cannot realistically be held through the enemy turn. Prefer this over holding back when the row pays at end of turn rather than in the Command phase.
- **Units:** Fast or expendable OC units, melee units charging onto the objective, deep strikers.
- **Move type:** Normal Move / Advance / Reserves arrival
- **11e rules (verified):** 14.02: control is determined at the end of the turn (40k_11th_edition_core_rules.txt:2409-2416). missionCards.json end-of-turn rows for your turn: battlefield-dominance :3, immovable-object :108, inescapable-dominion :159, determined-acquisition :63, outmanoeuvre :854, meatgrinder :474, gather-intel :2071, search-and-scour :2005, vital-link :1412, delaying-action :916, forward-position :2181, secure-no-mans-land :2489, a-tempting-target :2759. Engine: score_primary_eot_11e (MissionManager.gd:1823).
- **AI today (partial):** End-of-turn rows active this round are priced by _estimate_objective_vp_value the same way as Command rows (AIDecisionMaker.gd:22928-23050; awareness at 22836-22880), so the grab is valued. But nothing marks a score as 'end of THIS turn, survival irrelevant'. threat_delta (10285-10288) and the LONE-TRIP skip (10780-10994) still penalise an expendable grab, and the AI never deliberately picks an expendable unit for it.
- **Engine support:** Reuse the rule's 'when' field, already read in _build_primary_awareness (AIDecisionMaker.gd:22836-22880), and _estimate_objective_vp_value (22928). New: split each objective's VP into eot_vp (needs control at the end of this turn only) and hold_vp (needs control at the next Command phase or the end of the opponent's turn), and apply the threat and survival terms to hold_vp only.
- **Value (high):** Early-round and every-turn end-of-turn rows are worth 2-10VP and reward cheap sacrificial grabs.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json (rows listed in rules_basis)
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1823-1835 (score_primary_eot_11e)
  - YouTube nGqRAvAMTYA @66:00 (TacticalTortoise 40k): "He also can 6 in deep strike high OC onto an objective in order to grab it" (ai_learnings.json F007)
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-purge-the-foe/ (search snippet: 'disposable objective-grabbers, melee units to flip objectives, and ranged units to clear objectives')
- **Found by:** missions

#### OBJ-09 — Move toward the enemy objective holder to shoot it off before the control check

To flip or contest an objective, the enemy OC in range has to go. Move a shooting unit to where it can see and reach the enemy unit(s) standing in the objective's area, and into half range for Rapid Fire / Melta when that matters. This turn's shooting then destroys or battle-shocks enough of them before the end-of-turn check while your OC unit steps in. Choose firing spots that see past the area's obscuring and Solid terrain; a Hidden holder can only be seen from within its detection range (15in). This is the objective form of the user's 'move toward an enemy to shoot it'.

- **When:** An enemy unit holds or contests an objective you want this turn (flip, contest, new-capture or end-of-turn rows) and its OC exceeds what you can bring. Your shooters cannot currently see or reach it. Late rounds.
- **Units:** Ranged units, especially high-volume or anti-infantry guns against multi-model holders, and [IGNORES COVER] or anti-Hidden tools.
- **Move type:** Normal Move (Advance only for [ASSAULT] weapons)
- **11e rules (corrected):** 14.02: control at the end of each phase and turn (40k_11th_edition_core_rules.txt:2409-2416). 10.04: normal shooting requires no advance (:1489-1491). 10.05: assault shooting after an advance uses [ASSAULT] weapons only (:1506-1516). 13.08: cover worsens BS by 1 (:2279-2290). 13.09: Hidden models are visible only within detection range (:2292-2303). 13.10 / 13.11 line of sight (:2305-2315). 01.07: battle-shocked models have OC '-' (:216-217).
  - _Errata check:_ A Hidden holder (Hidden now also applies in terrain areas with only light features) can be seen only from within its detection range. That range is 15in, but only 12in for a shooter it is not fully visible to because of intervening dense terrain features while its unit has not shot this turn or the previous turn (gone to ground), so firing spots need either no dense feature in between or must be within 12in. — Commentary 13.11.01 Gone to Ground; 13.09 errata
- **AI today (partial):** Target choice already favours holders: tv_on_objective is x1.4 plus an OC weight, and x1.3 more in R4-5 (AIDecisionMaker.gd:17828-17835). Movement only gets nudges: firing_position +1 when enemies are near the unit's own target objective (10268-10273), shooting_lane +1 per planned lane kept (10349), and the T7-14 blend that keeps a current target in range (13848-13904). No candidate move has a firing position on an enemy holder as its destination, and every range test uses unit centroids with no line-of-sight check.
- **Engine support:** Reuse RulesEngine.get_eligible_targets (RulesEngine.gd:7137) on a board copy with the unit moved, LineOfSightManager.calculate_los_to_position (LineOfSightManager.gd:101), TerrainManager.hidden_model_visible_to / detection_range_inches_for (TerrainManager.gd:1047-1090), RulesEngine.count_models_in_half_range (11812) and _estimate_weapon_damage (AIDecisionMaker.gd:17984). New: a firing-spot generator toward each enemy objective holder, scored by expected OC removed x the VP at stake on that objective.
- **Value (high):** Most flips need the holder removed first, and the user asked for this intent explicitly.
- **Evidence:**
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-purge-the-foe/ (search snippet via missions stream: 'ranged units to clear objectives')
  - YouTube Krfpc2el0cA @25:00 (Tabletop Titans): "Overwhelming is good. This is kill things on objectives. It's what I want to do ... you really want to try to get two kills" (ai_learnings.json F028)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:17828-17835 (shooting target value x1.4 for units on objectives, x1.3 more in R4-5)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:10255-10273 (firing_position terms on objective trips)
- **Found by:** missions, user-example

#### OBJ-10 — Move toward the enemy objective holder to charge it off the objective

Use a Normal Move to close to reliable charge distance of the enemy unit holding the objective (a charge needs an enemy within 12in and a 2D6 roll). Don't Advance: that forbids the charge unless an ability allows it. Each step then works on the objective. The charge move often ends your models inside the area. The fight destroys or ties up the holder. If no enemy is left within 3in, Objective Consolidation can add more models before the end-of-turn check. Approach from cover and out of Overwatch sight where possible. This is the objective form of the user's 'move toward an enemy to charge it'.

- **When:** A melee unit can reach charge range of an objective holder this turn; flip, contest, new-capture or end-of-turn rows are active; holders are weak in melee; late rounds.
- **Units:** Melee units; advance-and-charge units (riled-up Orks, etc.).
- **Move type:** Normal Move (Advance only with an advance-and-charge ability)
- **11e rules (verified):** 11.02: declaring a charge needs an enemy within 12in and no advance or fall back this turn (40k_11th_edition_core_rules.txt:1603-1625, :1620, :1622). 09.06 (:1411-1414). 12.08: Objective Consolidation applies when the unit is not engaged and not within 3in of enemies but is within 3in of an objective; moved models end within range if possible (:1942-1975). 14.02 (:2409-2416). 15.08: Fire Overwatch at the end of the opponent's Movement phase (:2735-2742).
- **AI today (partial):** The phase plan's charge_intent multiplies a target's score by 1.3 when it is on an objective (AIDecisionMaker.gd:3864-3880), and the charge scorer boosts holders (18611-18613). The charge-intent steer only bends the unit's own objective trip toward its target (7491-7548). Melee seekers converted to ATTACK chase the nearest enemy by centroid, not the objective holder (_melee_chase_gate, 2947-3099), and the approach is never chosen for cover or to avoid Overwatch.
- **Engine support:** Reuse charge_intent in _build_phase_plan (AIDecisionMaker.gd:3773-3946), _melee_chase_gate (2947), _estimate_melee_damage (19576), _overwatch_exposure_penalty (28660) and MissionManager.model_within_inches_of_objective (MissionManager.gd:545). New: rank charge targets by objective VP flipped x P(charge succeeds) x P(holder's OC removed), and choose an approach endpoint within 9in of the holder that is out of Overwatch line of sight.
- **Value (high):** Charging holders is the main melee route to flipping objectives, and the user asked for this intent explicitly.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:3864-3880 (phase-plan charge intent x1.3 when the target is on an objective)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:18611-18613 (charge declaration bonus for holders, x1.5 in R4-5)
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-purge-the-foe/ (search snippet: 'melee units to flip objectives')
  - YouTube efeKiBbPUPM @09:00 (Maelstrom Gaming Studios - Tyranids): "My Neurolictor battleshocked Volus and the Paladins, which allowed both the Neurolictor and the Hive turret to charge in and precision out" (ai_learnings.json F023)
- **Found by:** missions, user-example

#### OBJ-14 — Raid the opponent's home objective on the card's timing

Many cards pay for the enemy home:
- Outmanoeuvre: 10VP at the end of ANY of your turns.
- Meatgrinder: 5VP at end of turn from R2.
- Forward Position: 5VP at end of turn.
- Punishment 8VP, Vital Link 10VP, Vanguard Operation 10VP and Inescapable Dominion 5VP at the end of the battle.
- Gather Intel markers there pay at the end of the battle.
Time the raid to the card: for end-of-turn rows, grab it at the end of any turn; for end-of-battle rows, arrive late and survive. Deep Strike can land in the enemy deployment zone from R2 (more than 8in from enemy units). Ordinary strategic-reserve ingress cannot enter it before R3.

- **When:** One of those cards is active and the enemy home is lightly held or reachable by deep strike or fast units. End-of-battle rows from R4.
- **Units:** Deep strikers, fast melee, transports, durable high-OC units.
- **Move type:** Reserves arrival (Deep Strike / ingress) / Advance / Normal Move
- **11e rules (verified):** 20.03: ingress from R2 (40k_11th_edition_core_rules.txt:3250-3253). 20.04: no set-up in the opponent's deployment zone before the third round (:3267-3269). 24.09: Deep Strike anywhere more than 8in from enemy units, even in the opponent's deployment zone (:3649-3661). missionCards.json opponent-home rows: outmanoeuvre :854, meatgrinder :474, punishment :371, vital-link :1412, vanguard-operation :1597, inescapable-dominion :159, forward-position :2181, gather-intel :2071.
- **AI today (partial):** hold_enemy_home is priced (awareness at 22861-22863, estimator at 23002-23005, candidate term at 10360-10361), and Forward Position adds a 5VP hint (24185). The R2 enemy-DZ filter is applied to strategic reserves only, so deep strikers may land there in R2 (8082-8092, 8364-8375). Gaps: end-of-battle home rows are priced in every round from R1 (FIX_EOG_TIMING = 0.0; the comment at 1876-1886 measures +13.5 to +27 priority from round 1). An enemy_strong home takes -3 (9285-9286). Deep-strike candidate rings sit 10-15in from objectives (8019-8247) rather than on them. Nothing times an 'arrive late, survive to the end' raid.
- **Engine support:** Reuse _decide_reserves_arrival (AIDecisionMaker.gd:7728), the deep-strike candidate generator (8019-8247) and the already-written FIX_EOG_TIMING switch (1886). New: a raid value timed to the card (end-of-turn row: any turn; end-of-battle row: P(survive to the end) x VP), and deep-strike candidates inside the home area when it is more than 8in from enemies.
- **Value (high):** A single objective worth 5-10VP on many cards.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/IngressMove.gd:97-106 (the before-R3 enemy-DZ ban is lifted for Deep Strike)
  - /home/user/warhammer-40k-godot/40k/autoloads/GameState.gd:375-386 (ingress_opponent_dz_ban_applies)
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:854, :474, :371, :1412, :1597, :159, :2181
  - YouTube nGqRAvAMTYA @66:00 (TacticalTortoise 40k): "He also can 6 in deep strike high OC onto an objective in order to grab it" (ai_learnings.json F007)
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:134, :168, :182, :323, :337, :399
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:1877-1886 (FIX_EOG_TIMING = 0.0 and its rationale)
- **Absorbed duplicates:** MIS-27 (Time the grab of the enemy home objective for the end-of-battle check)
- **Found by:** core-rules, missions, first-principles, web

#### OBJ-N01 — Play the last battle round by turn order _(added by completeness review)_

In round 5, decide by who moves last. If you are the second player, no enemy turn follows: Command-phase rows score at the end of your turn and end-of-battle rows are checked right after it. So drop survival, screens, Hidden and Overwatch exposure entirely: Advance everything, charge onto objectives, contest with every body, and bring reserves in (strategic reserves are destroyed at the end of the final turn). If you are the first player, the opponent still has a full, all-in turn. Your end-of-your-turn rows still pay, but every end-of-battle row must survive that turn (Vital Link, Vanguard Operation, Inescapable Dominion and Punishment for the enemy home; Triangulation; Search and Scour's 'no enemies in your territory'). So must every end-of-opponent-turn row (Defend Stronghold, Display of Might's 5VP tier, Beacon). Hold with depth, screen the objectives they need, keep Rapid Ingress and Heroic Intervention answers.

- **When:** Battle round 5 (MAX_BATTLE_ROUNDS_AI). The switch is the first_turn_player flag. For the first player, also round 4, when planning which units must still be alive for the last turn.
- **Units:** Whole army; especially reserves, screens, objective holders and fast scorers
- **Move type:** Second player: Advance / Normal / Reserves arrival. First player: Remain Stationary / Normal / screening.
- **11e rules (verified):** 07.02 the same player takes the first turn in every battle round (40k_11th_edition_core_rules.txt:1135-1146). Mission timing key 'C = your Command phase (switches to end of turn in Round 5)' and the end-of-battle rows (docs/rules/11th_edition_missions_gdm2026.md:7, 13-38, 41-62). 20.01.02 strategic reserves are destroyed at the end of the final turn (40k_11th_edition_errata_faq_commentary.md:671-673).
- **AI today (partial):** _get_round_strategy_modifiers (AIDecisionMaker.gd:17421) treats rounds 4 and 5 identically and raises survival (STRATEGY_LATE_SURVIVAL 1.4, :2724) even when the AI moves last. _enemy_next_turn_round (:9812) knows the turn order but feeds only one holder-loss check (:11073). End-of-battle rules are released only in the last round (FIX_EOG_TIMING, :22830-22834). _decide_engaged_unit holds objectives in rounds 4-5 regardless of turn order (:12050).
- **Engine support:** snapshot.meta.first_turn_player (read at AIDecisionMaker.gd:9813), MAX_BATTLE_ROUNDS_AI (:2213), and the primary vp_rules with their 'when' field. New: a moves_last_in_battle flag passed into _get_round_strategy_modifiers and into the objective and threat scoring.
- **Value (high):** The final turn carries the end-of-battle bonuses (5-10 VP), and today's late-game weights point the wrong way for the player who moves last.
- **Evidence:**
  - docs/rules/11th_edition_missions_gdm2026.md:7 (Round 5 timing switch)
  - [Tabletop Battles: 11e Force Disposition Review, Priority Assets](https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-priority-assets/) (WebSearch snippet only): Round 5 moves scoring to the end of each turn; 'the end game condition is a lot easier if you're going second, but either way you'll just need to put every body you've got left on objectives'
  - YouTube F011, video MG546BN181w at 47:00: 'You do not have to kill your opponent in 11th edition'
- **Found by:** cross_bucket_critic

#### OBJ-02 — Take an objective: move enough OC into its range

Normal Move (or Advance if the D6 is needed to arrive) so enough models end within range to beat the enemy's level of control at the next end-of-phase or end-of-turn check. On 11e terrain objectives the terrain area IS the objective. A model is in range while any part of its base is within the area, so a vehicle only needs to touch it. Where a layout has no area, a model is in range within 3in horizontally and 5in vertically of the 40mm marker. Infantry that end inside the area also gain cover, and Hidden if the area contains dense terrain.

- **When:** Uncontrolled or weakly held objectives that your primary or secondary cards pay for. Adding a second OC source to win a contest is OBJ-05.
- **Units:** Any unit with OC 1+ that is not battle-shocked.
- **Move type:** Normal Move / Advance
- **11e rules (corrected):** 14.01: the terrain area is the objective; measure to its closest part (40k_11th_edition_core_rules.txt:2389-2398). 14.02: a model is within range of a terrain objective while it is within that area (:2405-2406); control is summed at the end of each phase and turn (:2409-2416). 01.04: measure from the closest part of the base (:163-166). Rules appendix: objective markers, 3in horizontally / 5in vertically (:4085-4103). 13.08 / 13.09: cover and Hidden for INFANTRY/BEASTS/SWARM within a terrain area (:2279-2303). 09.05 / 09.06 (:1390-1414).
  - _Errata check:_ Hidden is not dense-only. INFANTRY/BEASTS/SWARM models within a terrain area that contains one or more light or dense terrain features are Hidden while their unit has made no ranged attacks this turn or the previous turn (during the first turn the previous-turn condition counts as met). — 13.09 errata (Hidden, first bullet); Commentary 13.09.01 Hidden and the First Turn
- **AI today (full):** Objective evaluation plus greedy capture assignment generate and score this move (AIDecisionMaker.gd:8926-9398; candidates from 9910; pass-2 capture/flip at 10999-11252). The move heads for the shortest approach onto the hosting area (_objective_approach_target, 13193) and is emitted as BEGIN_NORMAL_MOVE (7637) or BEGIN_ADVANCE (7202-7221). Caveats: FIX_OBJ_AREA_REACH, FIX_OBJ_AREA_ON_OBJ and FIX_OBJ_AREA_HOLD are all 0.0 (1844, 1859, 1875). So the reach, 'on objective' and hold gates still measure from the unit centroid to the marker, and terrain objectives look about a turn farther away than they are. The AI also does not choose how many models enter or from which side (see OBJ-15).
- **Engine support:** Already exists: MissionManager.model_in_objective_range (MissionManager.gd:529), model_gap_to_objective_range_px (569), _objective_host_areas_for_edition (506); AIDecisionMaker _objective_approach_target (13193) and _unit_oc_at_position (13054). Turning on the existing OBJ-AREA switches moves the reach gates onto the terrain-area check.
- **Value (high):** The basic objective move; every primary card pays for control.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2389-2424, :2439-2450 (diagram: a VEHICLE 'within the terrain area' with only part of its hull inside), :4085-4103
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:494-527 (_model_in_objective_range: any base overlap with a hosting area counts; otherwise 3in + 20mm of the marker)
  - /home/user/warhammer-40k-godot/40k/terrain_layouts/take_and_hold_vs_purge_the_foe_1.json (5 terrain-hosted objectives; all 46 layouts with objectives carry 5)
  - https://www.belloflostsouls.net/2026/04/warhammer-40k-terrain-objectives-how-they-work-in-11th-edition.html (search snippet: vehicles just touch the footprint)
- **Found by:** first-principles, core-rules

#### OBJ-12 — Garrison your home objective with the cheapest sufficient OC unit and push only part of the army

Your home objective matters in several ways. It enables Battlefield Dominance's +2VP per non-home objective (only while you hold home). It scores Defend Stronghold (3VP at the end of the opponent's turn, R2+). It counts toward thresholds that don't exclude home (Inescapable Dominion, Secure Asset 3+, Triangulation 4+). And losing it feeds the opponent's enemy-home rows (up to 10VP). Keep a cheap OC unit in range of it, ideally Hidden in its area, and send the expensive units forward. Commit only part of the army to the forward objectives instead of pushing everything.

- **When:** Always, while a home-dependent row is active for you or the opponent's card pays for your home. Give it more weight against deep strikers, Scouts and Infiltrators.
- **Units:** Cheapest OC units (Gretchin-class job units, small Battleline squads) as the garrison; bricks push forward.
- **Move type:** Remain Stationary / Normal Move
- **11e rules (verified):** missionCards.json: the battlefield-dominance cumulative row requires controlling your home objective (:3); defend-stronghold pays for your home at the end of the opponent's turn, R2+ (:2706); opponent-home rows (outmanoeuvre :854, vital-link :1412, punishment :371, vanguard-operation :1597). 14.02 (40k_11th_edition_core_rules.txt:2409-2419).
- **AI today (full):** An undefended home gets +9 priority (WEIGHT_HOME_UNDEFENDED, AIDecisionMaker.gd:2560, applied at 9221-9230). KEEPER-PICK keeps the cheapest sufficient holder using a points tie-break (10641-10660). The require_hold_home rider is priced as 'home enables +X per objective' (22958-22967), plus +3 primary_awareness on home (10366-10367). Defend Stronghold adds a 3VP home hint (24101-24106). AGGRO-FREE releases melee units of 10+ models from home in R1-2. There is a HOLD_OBJECTIVE plan verb (40k/docs/PLAN_FORMAT.md:526). Gap: nothing limits how much of the army goes forward (FIX_OVERCOMMIT = 0.0 at 1675).
- **Engine support:** Exists. The already-written switches FIX_OVERCOMMIT (AIDecisionMaker.gd:1675) and FIX_KEEPER_RELEASE (1712) cover the 'only part of the army' and 'release the keeper when the card does not pay' refinements.
- **Value (high):** Home control gates large per-objective bonuses and denies the opponent's biggest rows.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:96-100 (Battlefield Dominance require_hold_home rider)
  - YouTube QZ9wggn2oUo @07:00 (Tabletop Nexus): "Gretchen handle the boring jobs, your home objectives, more screening so boys don't have to" (ai_learnings.json F021)
  - YouTube DHVBk9vnR8w @02:00 (40K Dirtbags): "20-man gretchin with Zagdrod, two 10-man gretchin which I really liked having extra gretchin unit" (F021)
  - YouTube VU4S_6e1NgE @24:00 (Deploy on the Line 40K): "you're just going to win on primary points as long as you don't burn out" (F011)
  - Exile Wargaming mbNWzDn6Pu4 @34:00, a paraphrase only (ai_learnings.json disagreements): '11e removed the need to push everything onto objectives; hold home, take a couple of bricks, do actions'
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-reconnaissance/ (search snippet: 'Be extremely protective of your home deployment zone')
- **Found by:** missions, youtube, core-rules, first-principles

#### OBJ-13 — Take and keep the central objective

Every shipped 11e layout has one central objective at the board centre, built from two linked terrain areas that count as one objective (a model in either area is in range). It pays on many cards:
- Immovable Object: 3VP at the end of every turn.
- Unstoppable Force: 5VP at the end of the battle.
- Gather Intel: 6VP at the end of R1.
- Search and Scour: 3VP at the end of every turn.
- Vital Link: 2VP plus 1VP per marker at end of turn, and +4VP at Command.
- Delaying Action: together with an expansion objective.
It is also where the Sensor Sweep (Extract Relic) and Maintain Control (Vital Link) actions start. Put a durable high-OC unit into either half early, and keep a second body there so an action unit can work.

- **When:** Any of those cards is active; R1 for Gather Intel; every turn for Immovable Object and Search and Scour.
- **Units:** Tanky high-OC units, plus a second body for actions.
- **Move type:** Normal Move / Advance / Remain Stationary
- **11e rules (verified):** 14.01 / 14.02 (40k_11th_edition_core_rules.txt:2389-2419). Central = the no-man's-land objective nearest the board centre (MissionManager.gd:268-288). missionCards.json central rows: immovable-object :108, unstoppable-force :302, gather-intel :2071, search-and-scour :2005, vital-link :1412, delaying-action :916, extract-relic :1286.
- **AI today (full):** hold_central / hold_central_plus_nml rows are priced per objective (AIDecisionMaker.gd:23006-23012) and add central_bonus in candidate scoring (10362-10365). The PUSH_CENTER earmark adds +6.0 (PLAN_FORMAT.md:527), and Centre Ground adds a hint (24202). Caveats: 'central' is tested as 'within 4in of the board centre' (9324, 10363) instead of MissionManager's designation, and central-only actions are never planned.
- **Engine support:** MissionManager.get_objective_ids_by_designation('central') (MissionManager.gd:293) can replace the 4in test. MissionManager.can_start_mission_action_11e (2030) and get_card_action_summary_11e (2197) cover the action half.
- **Value (high):** Central rows appear on most cards, and many pay every turn.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/terrain_layouts/take_and_hold_vs_purge_the_foe_1.json (obj_center at (22,30), source_pieces [area-trapezoid-1, area-trapezoid-2]); checked: all 46 layouts with objectives have 5 objectives and a two-area centre
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:268-288
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-take-and-hold/ (snippet: '4 out of 5 of the missions here involve a big, central objective')
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-priority-assets/ (snippet: 'especially if you have a tanky unit hanging out in the middle of the table')
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2071
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:246
- **Absorbed duplicates:** MIS-32 (Gather Intel round 1: get a unit onto the central objective)
- **Found by:** missions

#### OBJ-15 — Toe in: put only the models you need into the objective area, from the side away from threats

Only models within the area add OC, and a base that only partly overlaps it still counts. Touch the area's edge with just enough models (or a vehicle or monster's hull) to win or tie the count, on the side away from enemy firing and charge lanes. Keep the rest of the unit in coherency behind terrain or outside the area. On open-ground markers, stop at the 3in ring instead of on the marker. Trade-off: an infantry unit only partly inside the area loses the 13.08 'within a terrain area' cover, unless its other models are not fully visible.

- **When:** Control is needed at the next check but standing inside the area is very exposed; vehicles and monsters that cannot be Hidden; units with surplus OC per model; large areas and the two-area centre.
- **Units:** VEHICLE / MONSTER holders; multi-model units with spare OC.
- **Move type:** Normal Move
- **11e rules (verified):** 14.01 / 14.02 (40k_11th_edition_core_rules.txt:2389-2419); the rules diagram counts a VEHICLE 'within the terrain area' with only part of its hull inside (:2439-2450). 01.04: measure from the closest part of the base (:163-166). Rules appendix: objective markers 3in / 5in (:4085-4103). 03.03: coherency 2in / 9in (:518-530). 13.08: every model must qualify for cover (:2279-2290).
- **AI today (none):** The approach target is the shortest way onto the area from the unit's nearest model (_objective_approach_target, AIDecisionMaker.gd:13193-13240): the near side, chosen for distance, not safety. The whole unit is moved as a formation (placement ladder, 14520-14722), so neither the number of models that end inside nor the side they enter from is chosen.
- **Engine support:** Reuse MissionManager.model_in_objective_range per model (MissionManager.gd:529), Measurement.model_overlaps_polygon, _evaluate_position_threat (AIDecisionMaker.gd:28794) and LineOfSightManager.calculate_los_to_position (LineOfSightManager.gd:101). New: a 'safe-edge' target per objective, found by sampling boundary points of the hosting area and ranking them by enemy line of sight and charge exposure. Then a placement that puts ceil(needed OC / OC per model) models inside and the rest in coherency behind cover.
- **Value (medium):** Cuts holder exposure, mainly for vehicles and monsters that cannot hide; secondary to deciding to hold at all.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:494-527 (shape-aware overlap: 'a base half on the area counts')
  - /home/user/warhammer-40k-godot/40k/autoloads/TerrainManager.gd:1029 (comment: 'Within = any part of the base (01.04)')
  - https://www.belloflostsouls.net/2026/06/warhammer-40k-top-5-11th-edition-rules-changes-for-competitive-play.html (#5: 'this new 11th edition bring backs the whole toe-in experience we used to have')
  - https://spikeybits.com/11th-edition-40k-terrain-rules-rumors-guide/ (search snippet: models score by touching the edge of the terrain footprint)
  - https://www.warhammer-community.com/en-gb/articles/xlppkx5s/new40k-take-cover-with-updated-terrain-rules/ (web-stream result)
  - Counterpoint, web search snippet via the first-principles stream: objectives are larger, so you can no longer comfortably toe onto one edge
- **Found by:** missions, web, core-rules

#### OBJ-33 — Stand within objective range to switch on objective-gated abilities

Many 11e datasheets fight at full power only when they, or their target, are within range of an objective. Examples:
- Intercessor Squad, Bolter Discipline: +1 to hit if this unit OR the target is within range of an objective.
- Custodian Guard, Impenetrable Defence: [SUSTAINED HITS 1].
- Sentinel Guard, Stand Vigil: [LETHAL HITS].
- Flash Gitz, Finderz Keeperz: +1 AP.
- Wreckas, Wreckin' and Lootin'.
- Heavy Intercessors, Unyielding in the Face of the Foe: +1 save while controlling.
- Bladeguard Ancient, Deeds of Legend; Grey Hunters, Cunning Hunters; Vulkan He'stan, Seeker of the Unfound.
So objectives double as buff zones. End within range of one while still shooting or fighting the target, or pick firing lanes onto enemies standing on objectives.

- **When:** The unit can end within an objective's range and still reach its target while choosing firing positions, and the buff changes the expected damage materially.
- **Units:** Intercessors, Heavy Intercessors, Bladeguard Ancient, Grey Hunters, Centurion Devastators, Custodian / Sentinel Guard, Flash Gitz, Wreckas units, Vulkan He'stan, etc.
- **Move type:** Normal Move
- **11e rules (verified):** Datasheet text, e.g. Bolter Discipline (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:371, checked). Objective range per 14.02 (40k_11th_edition_core_rules.txt:2405-2406) and MissionManager.model_in_objective_range (MissionManager.gd:529).
- **AI today (none):** None of these ability names appears in AIDecisionMaker.gd (factions-stream grep: 0 hits each). Objectives are valued only for OC and VP, so a unit's destination never accounts for an objective-gated buff.
- **Engine support:** Reuse MissionManager.model_in_objective_range (MissionManager.gd:529) and the RulesEngine weapon-profile modifiers. New: an 'objective-gated buff' flag per unit (parsed once from ability text) that adds the expected-damage gain to destinations within objective range.
- **Value (medium):** Intercessors and Custodian Guard are common, and the buff is worth roughly 15-20% more damage.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:371 (Bolter Discipline: 'In your Shooting phase, if any of the following apply, this unit's ranged attacks have +1 to hit rolls: This unit is within range of an objective. The target of that attack is within range of an objective.')
  - Per the factions stream: same file :399 (Unyielding in the Face of the Foe), :384 (Deeds of Legend), :318 (Cunning Hunters), :421 (Decimator Protocols), :628 (Seeker of the Unfound); /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/custodes/wahapedia/Datasheets_abilities.csv:131 (Impenetrable Defence), :127 (Stand Vigil); /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:154 (Finderz Keeperz); orks/RULES.md:206 (Wreckin' and Lootin')
- **Found by:** factions

#### OBJ-21 — Hand off an objective: move a cheap unit in so an expensive holder can leave

Free an expensive or offensive unit sitting on a safe objective. First move a cheap job unit into range, so control still holds at the end of the phase, then move the expensive unit to its real job. With a securing ability, use OBJ-16 instead.

- **When:** An expensive melee or offensive unit holds a low-threat (often home) objective, a cheap OC unit can reach it this turn, and the freed unit has a valuable target.
- **Units:** Expensive melee units leaving; cheap infantry taking over.
- **Move type:** Normal Move (two units, in order)
- **11e rules (verified):** 14.02: control at the end of each phase and turn (40k_11th_edition_core_rules.txt:2409-2416).
- **AI today (partial):** Only a narrow case: when two units already share an objective, KEEPER-PICK keeps the cheapest sufficient one and frees the other (AIDecisionMaker.gd:10641-10660), and AGGRO-FREE releases melee units of 10+ models from home in R1-2. Holds are decided in pass 1 from units already in range, before the pass-2 captures (10606 vs 10999), and units move front to back (7119-7147). So a cheap unit is never sent in first to relieve a holder.
- **Engine support:** Reuse the COORD-2 incoming-OC ledger (AIDecisionMaker.gd:3977-4075), KEEPER-PICK (10641-10660) and the move-order tiers (7657-7722). New: a paired assignment (relief unit -> objective, holder -> new job) that moves the relief unit first.
- **Value (medium):** Frees the army's best units without dropping control; a common Ork / Gretchin pattern.
- **Evidence:**
  - YouTube QZ9wggn2oUo @07:00 (Tabletop Nexus): "Gretchen handle the boring jobs, your home objectives, more screening so boys don't have to" (ai_learnings.json F021)
  - /home/user/warhammer-40k-godot/research/youtube/profiles/orks.json:38 (draft rule ork_boyz_off_held_objectives: WEIGHT_ALREADY_HELD_OBJ -7.0 for melee units of 150+ pts on an objective)
  - /home/user/warhammer-40k-godot/research/youtube/batch.py:26-30 (the 'STICKY' and 'SECURE-then-leave' themes were searched; per the youtube stream no quote survived)
  - YouTube QZ9wggn2oUo @07:00 (Tabletop Nexus, F021): 'Gretchen handle the boring jobs, your home objectives, more screening so boys don't have to'
  - research/youtube/ai_learnings.json F021 (player_opinion, medium)
  - research/youtube/profiles/orks.json 'ork_boyz_off_held_objectives' (WEIGHT_ALREADY_HELD_OBJ -7 for 150+ point melee units on a held objective; not a shipped profile)
- **Absorbed duplicates:** COO-08 (Rotate a cheap holder onto an objective to free a combat unit)
- **Found by:** youtube, first-principles

#### OBJ-22 — Flip an abandoned secured enemy objective

An objective the opponent secured stays theirs with nobody in range until your level of control is greater at the end of a phase. So a single OC 1+ model ending its move in an empty enemy-secured area flips it at the end of your Movement phase. From then on it counts for you and against their count. Look for objectives that the opponent's securing units have walked away from.

- **When:** The opponent has secure abilities (Get da Good Bitz, Thievin' Scavengers, Raise the Banner, DUBIOUS RESTRAINT, IMPENETRABLE BASTION, VIGILANCE ETERNAL, ...) and has left a secured objective; cheap fast units are nearby.
- **Units:** Fast or cheap units with OC 1+.
- **Move type:** Normal Move / Advance / Reserves arrival
- **11e rules (verified):** 14.03 (40k_11th_edition_core_rules.txt:2427-2435); 14.02 end-of-phase determination (:2409-2416).
- **AI today (partial):** Only by accident: with FIX_SECURED_AWARE = 0.0 (AIDecisionMaker.gd:1925), an empty enemy-secured objective reads 0 v 0 'uncontrolled' (9170-9188), so capture scoring may still send a unit. But it is left out of their_holds (8957-8966), so majority and denial pricing undervalue it, and the AI never deliberately targets the opponent's lock.
- **Engine support:** Reuse _secured_aware_lock (AIDecisionMaker.gd:8899) and the already-written FIX_SECURED_AWARE state mapping (9190-9203: opponent lock -> enemy_weak).
- **Value (medium):** Frequent in the bench's Ork / Space Marine / Custodes mirrors; one model takes a whole objective back.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:141-150 (secure_objective / is_objective_secured), :304-311 and :360-396 (only end-of-phase checks break a lock), :922-934 (the lock breaks when the opponent has greater OC)
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/RULINGS.md:188 (Thievin' Scavengers: the objective stays secured after the Gretchin die, until the opponent takes control)
- **Found by:** core-rules

#### OBJ-26 — Stage within one Normal move of next turn's scoring condition

In 11e you draw two tactical cards per turn with no hand limit, unscored cards stay in hand, and several actions only open from round 2. A card or action that can't be done this turn should still shape the move. End within one Normal move of next turn's spot; don't Advance there, because an Advance bars starting an action. Spots include the enemy deployment zone (Behind Enemy Lines), a flank edge band (Outflank), an uncovered table quarter, the centre ring, a forward terrain area (Plunder), the Tempting Target, and a non-home objective for Triangulate / Extract Intelligence. Prefer Hidden or out-of-sight spots, so the card scores next turn without a long exposed run.

- **When:** A held card or upcoming action can't be reached this turn but can be next turn. Weigh it against discarding the card for 1CP.
- **Units:** Fast or cheap units assigned to positional or action jobs.
- **Move type:** Normal Move
- **11e rules (verified):** Engine 11e deck rules: CARDS_DRAWN_PER_TURN_11E = 2, no hand limit, only achieved cards discarded (SecondaryMissionManager.gd:27-31, 1602-1625). 'Discard a secondary at end of turn for 1CP' (11th_edition_missions_gdm2026.md:67). 16.01: a unit that advanced or fell back can't start an action (40k_11th_edition_core_rules.txt:2816). missionCards.json: the triangulation and gather-intel actions run 'from the second battle round onwards' (:1874, :2071).
- **AI today (partial):** Active secondaries add positional bonuses to the endpoints of objective trips whether or not they can score this turn (AIDecisionMaker.gd:10378-10499; awareness at 24024-24237), which nudges units toward the right areas. But nothing stages a unit to be 'reachable next turn with a Normal move', and units are never positioned to start actions. Plunder's wants_forward_terrain and Burden of Trust's hold_objectives are set but never read (24223, 24196), and the enemy-zone centre is hard-coded (10394-10400).
- **Engine support:** Reuse SecondaryMissionManager.get_active_missions, MissionManager.get_card_action_summary_11e / can_start_mission_action_11e (MissionManager.gd:2197, 2030), ActionsManager.get_startable_actions (ActionsManager.gd:60) and _get_table_quarter (AIDecisionMaker.gd:24250). New: a per-card 'next-turn target region', and a staging score = reachable next turn with a Normal move x card VP x P(survive).
- **Value (medium):** Tactical secondaries are worth up to 45VP, and staging turns held cards into points a turn earlier.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/autoloads/SecondaryMissionManager.gd:27-31, :1602-1625
  - https://www.tabletopbattles.com/40k-an-introduction-to-missions-in-11th-edition/ (search snippet: 'unscored tactical cards no longer vanish at the end of your turn')
  - YouTube mbNWzDn6Pu4 @05:00 (Exile Wargaming): "we have to triangulate objectives by doing actions on them. We can only do one a turn"
  - /home/user/warhammer-40k-godot/docs/rules/11th_edition_missions_gdm2026.md:66-67
  - /home/user/warhammer-40k-godot/40k/autoloads/SecondaryMissionManager.gd:210-240, :1602-1617
- **Absorbed duplicates:** MIS-29 (Stage this turn for card geometry you can only reach next turn)
- **Found by:** missions, first-principles

#### OBJ-27 — Advance now to pre-position when nothing is lost this turn

If the unit has nothing to shoot (or only [ASSAULT] weapons), cannot charge this turn anyway, and has no action to start, Advance so it reaches next turn's objective, charge or action spot a turn earlier. Command Re-roll can re-roll the advance roll. Don't Advance a loaded transport whose cargo must disembark this phase.

- **When:** Long trips; round-1 forward staging; units out of range of everything; units whose guns are all [ASSAULT].
- **Units:** All; especially fast units and melee units far from targets.
- **Move type:** Advance
- **11e rules (verified):** 09.06 Advance: M + D6, no charge or action afterwards (40k_11th_edition_core_rules.txt:1401-1414). 10.04 normal shooting requires no advance; 10.05 assault shooting uses [ASSAULT] weapons (:1489-1491, :1506-1516). 15.02: Command Re-roll covers the advance roll (:2651-2672). 16.01 (:2816). 18.04: no disembark from a transport that advanced this phase (:3019-3024).
- **AI today (partial):** RACE-1 Advances on long trips when it saves a whole turn with P >= ADVANCE_SAVE_TURN_MIN_P and costs no shooting or charge (AIDecisionMaker.gd:12773-12786, 12946-13015; MOVE_LONG_ADVANCE = 1.0 at 2255). On short trips it Advances 'whenever nothing is in weapon range' (12650-12748). This only covers objective and ATTACK destinations. It ignores the 16.01 action ban and the 18.04 disembark ban, so a loaded transport can be assigned an Advance. Command Re-roll looks at the roll value (always on a 1, on a 2 with 3+ CP), not the distance needed (28096-28119).
- **Engine support:** Exists for objectives. New: pass the turn's action and disembark plan into _should_unit_advance (AIDecisionMaker.gd:12650), and re-roll when the roll falls short of the needed gap (_advance_reach_chance, 13247).
- **Value (medium):** Saves a turn on long trips at no cost; mostly implemented already.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1401-1414, :2651-2672
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:12773-12786 (_long_trip_advance_saves_turn)
- **Found by:** core-rules

#### OBJ-29 — Choose who commits first: bait with cheap holders or hang back so the opponent exposes first

Decide deliberately who steps onto the contested central objectives first. Either move cheap infantry onto them early, forcing the opponent to come out of cover and commit into you. Or hold the strike units just out of reach so the opponent has to expose themselves first, then counter-punch. The 11e trade-off is concrete: round-1 holds are what score your first Command-phase rows (round 2), but anything the opponent can kill there scores nothing and feeds their kill rows. Card timing shapes the choice (Disruption: 'score at least 8 on T1, hold 1 on T2-3, push on T4-5'), and so does the score (protect a lead or chase).

- **When:** Symmetric missions with contested middles; you have cheap holders and a stronger second wave; the opponent's alpha strike out-ranges yours; the VP difference.
- **Units:** Cheap objective units plus strike units.
- **Move type:** Normal Move / Remain Stationary
- **11e rules (verified):** A strategy built on 14.02 end-of-phase/turn control (40k_11th_edition_core_rules.txt:2409-2416), the GDM Command timing (11th_edition_missions_gdm2026.md:7) and 07.02 fixed turn order (:1135-1139).
- **AI today (partial):** Only the VP-difference tempo modifier (AIDecisionMaker.gd:17387-17419; applied at 9270-9284): behind means more objective urgency, ahead means more defensive play. Round 1 always pushes (WEIGHT_SCORING_URGENCY +3 at 9235-9239; STRATEGY_EARLY_SURVIVAL 0.7 at 2720 accepts more risk). There is no 'hang back' candidate and no turn-order logic.
- **Engine support:** Reuse _calculate_tempo_modifier (AIDecisionMaker.gd:17387), _get_round_strategy_modifiers (17421) and _calculate_enemy_threat_data (28695). New: a per-objective 'commit now vs next turn' comparison. Committing now is worth the next Command rows minus expected losses and opponent kill VP given the enemy's reach; compare that with the same units striking a turn later.
- **Value (medium):** Shapes the first two rounds, but needs a survival model to price well.
- **Evidence:**
  - https://www.tabletopbattles.com/40k-competitive-innovations-in-11th-to-take-perchance-to-hold-pt-1 (search snippet: Orks move infantry onto objectives early to force the Blood Angels to move first)
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-disruption/ (snippet: 'score at least 8 on T1, and hold on to 1 objective on turns 2 and 3 before pushing on turns 4 and 5')
  - YouTube pAk1YiuioNQ @70:00 (Happy Krumping): "disruption scores poorly, it kind of releases you to not have to worry about scoring ... you might as well just obliterate your opponents" (ai_learnings.json F012)
- **Found by:** web

#### OBJ-17 — Steal an objective held only by battle-shocked enemies

Battle-shocked models have OC '-', so an objective held only by shocked units flips to any unshocked unit with OC 1+ that steps into range. No kill is needed. Shock lasts until the owner passes a battle-shock roll in their own Command phase, and that roll comes BEFORE their scoring. So the steal certainly scores your end-of-turn rows. It denies their next Command-phase score if they fail the re-test, or regardless of the re-test if your OC there is at least equal to theirs.

- **When:** Enemy holders are battle-shocked now (they failed a test, or one of your abilities forced one this turn) and your unit can reach range. Pairs with OBJ-40.
- **Units:** Any unshocked unit with OC 1+; cheap fast units.
- **Move type:** Normal Move / Advance
- **11e rules (verified):** 01.07: battle-shocked models have OC '-' (40k_11th_edition_core_rules.txt:216-217). 08.03: a shocked unit re-tests in its owner's battle-shock step and recovers only on a pass (:1242-1255). 14.02 (:2409-2416).
- **AI today (full):** Objective evaluation skips battle-shocked enemy units (AIDecisionMaker.gd:9061-9063), and so do the contest and arrival helpers (_reachable_contest_oc at 13453, _ri_enemy_next_move_oc at 12846). An objective held only by shocked units therefore reads as uncontrolled / enemy_weak, and normal capture scoring sends a unit (pass 2, 10999-11252). Not priced: the chance the holder recovers in its 08.03 test before the opponent scores.
- **Engine support:** Exists. Refinement: reuse the P(fail) maths in _battle_shock_flip_value (AIDecisionMaker.gd:26051) for the recovery chance.
- **Value (medium):** A cheap flip whenever enemies are shocked; how often it applies depends on battle-shock sources.
- **Evidence:**
  - YouTube TJQWtTZiP1g @02:00 (Zeeto): "That sort of Battleshock um OC denial sort of list ... would probably work well in teams" (ai_learnings.json F009)
  - YouTube eokQteHr0Fo @19:00 (6 Plus Plus Gaming): "if you really need them to not have a secondary uh primary point ... it's a really powerful strategy" (F009)
  - YouTube qwnHaQvzCq0 @14:00 (Grimdark Breakdown): "If you Battle Shock me, I go to 1 OC instead of 0" (F009; some faction rules keep OC while shocked)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:26029-26045 (comment: 11e battle-shock does not expire on its own; CommandPhase._clear_battle_shocked_flags returns early for edition >= 11)
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:753-768 (_unit_oc_in_range zeroes battle-shocked units)
- **Found by:** youtube, web

#### OBJ-19 — Take the objective that completes a count threshold, not surplus ones

Threshold rows put all the value on the objective that crosses the line:
- Inescapable Dominion: 4VP at end of turn for 3+, 5VP at Command for 2+.
- Secure Asset: 4VP at Command for 3+.
- Triangulation: 10VP for 4+ at the end of the battle.
- Secure No Man's Land: needs 2 no-man's-land objectives.
- Delaying Action: needs central plus an expansion objective.
- The flat '4VP for 1+ non-home' row on most cards.
Primary VP is also capped at 15 per turn. Send the next free unit to the objective that reaches (or keeps) the threshold rather than reinforcing a surplus one, stop spending units once the tier or the cap is reached, and re-evaluate after each move.

- **When:** Threshold or flat 'hold 1+' rows are active, and the count is one short of a tier or exactly at it.
- **Units:** Any OC unit; send the cheapest to the deciding objective.
- **Move type:** Normal Move / Advance
- **11e rules (verified):** missionCards.json count_min rows: inescapable-dominion :159, secure-asset :1189, triangulation :1874, secure-no-mans-land :2489, delaying-action :916. PrimaryMissionData11e.gd:59-60 (MAX_PRIMARY_VP_PER_TURN_11E = 15). 11th_edition_missions_gdm2026.md:7 (15VP per turn cap).
- **AI today (full):** The VP estimator prices hold_min rows by the extra VP each objective adds: full VP for the objective that reaches or keeps the threshold, 0.5 when building toward it, 0.2 as insurance (AIDecisionMaker.gd:22968-22995). It applies the 15VP per-turn cap the same way (23018-23036). DIM-RETURNS skips captures worth less than 1VP once the plan's other captures are counted (10938-10950). Partial for secondaries: Secure No Man's Land and A Tempting Target are flat no-man's-land hints (24108-24119) that don't know the threshold or the designated objective.
- **Engine support:** Exists for primaries. For secondaries: price Secure No Man's Land as hold_min 2 over no-man's-land objectives, and A Tempting Target on its designated objective only (SecondaryMissionManager stores it).
- **Value (medium):** Avoids wasted moves; already priced for primaries.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:159, :1189, :1874, :2489, :916
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:59-60
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:22968-22995, 23018-23036 (threshold and cap pricing by extra VP gained)
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2489
  - /home/user/warhammer-40k-godot/40k/scripts/data/SecondaryMissionData.gd:196-219
- **Absorbed duplicates:** MIS-20 (Control two No Man's Land objectives at the end of your turn)
- **Found by:** missions, first-principles, web

#### OBJ-34 — Stay locked on the objective: remain stationary while engaged to keep holding or contesting it

An engaged unit on an objective keeps its OC there. Falling back gives the objective away and also forbids shooting, charging and starting actions for the rest of the turn; Desperate Escape adds hazard rolls and a battle-shock roll. If your OC there is winning or tied, or your presence denies their score, stay engaged. Fall back only if the unit will die anyway and other units keep control without it.

- **When:** Engaged on an objective you control or contest, especially in late rounds, when the enemy can't destroy the unit outright in the Fight phase.
- **Units:** Any engaged unit with OC on an objective.
- **Move type:** Remain Stationary (engaged), instead of Fall Back
- **11e rules (verified):** 09.04 (40k_11th_edition_core_rules.txt:1378-1388). 09.07: after a fall-back, no shooting, charge or action; Desperate Escape adds hazard rolls and a battle-shock roll (:1417-1441). 14.02: OC counts whether or not the unit is engaged (:2409-2416).
- **AI today (full):** _decide_engaged_unit holds an engaged unit on an objective when its side's OC there is winning or tied (always in R4-5 unless it can fall back and charge), and falls back only when the unit would likely die and the rest still hold (AIDecisionMaker.gd:12046-12080; whole decision at 11958-12179). Gaps for the engaged bucket: FIX_OBJ_AREA_HOLD = 0.0 (1875), so 'on the objective' is centroid-based, and the shooting lost by falling back is not priced (F017).
- **Engine support:** Exists.
- **Value (medium):** A common late-game decision that is already handled.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:12046-12080 (engaged on an objective: hold when winning or tied; R4-5 bias)
  - YouTube F5TL7LhZJlY @13:00 (40K Dirtbags): "He spends a CP realizing after the fact that you can't fall back and shoot with vehicles. It's only infantry" (ai_learnings.json F017)
  - YouTube Enm67qaqHkU @25:00 (40K Dirtbags): "If they fall back and shoot, these guys could have fell back and shot. But that's only one unit of shooting" (F017)
- **Found by:** bucket-editor

#### OBJ-39 — Keep options open: end in central, flexible spots that reach two or more objectives next turn

Prefer central positions from which the unit can reach two or more objectives or targets next turn, instead of committing to one flank before the opponent reveals reserves, Rapid Ingress or reactive moves.

- **When:** Early rounds; the opponent's plan or reserves are still unrevealed; the unit has no scoring job this turn.
- **Units:** Mobile units.
- **Move type:** Normal Move
- **11e rules (verified):** A strategy supported by 11e reactive timing: Rapid Ingress 15.07 and Fire Overwatch 15.08 both happen at the end of the opponent's Movement phase (40k_11th_edition_core_rules.txt:2714-2742).
- **AI today (none):** Each unit gets one objective (pass 2, AIDecisionMaker.gd:10999-11252), and no 'objectives reachable next turn' term exists.
- **Engine support:** Reuse _unit_gap_to_objective_px and _capture_arrival (AIDecisionMaker.gd:13091) for each objective. New: an optionality term = the number (or VP) of objectives reachable next turn from the destination.
- **Value (low):** A soft positional gain that is hard to measure.
- **Evidence:**
  - /home/user/warhammer-40k-godot/research/youtube/ai_learnings.json F014 ('Reactive movement abilities are widespread enough in 11e that the AI cannot treat enemy positions as fixed between its own decisions')
  - YouTube Enm67qaqHkU @20:00 (40K Dirtbags): "he then reactive moves and kind of spreads out to stop Ghaz from moving this way" (F014)
- **Found by:** first-principles

#### OBJ-41 — Bring the OC-granting character to the contested objective

Some units only reach full OC near a specific friendly model. Move the enabler (or the units) so the bonus is active on the contested objective when control is checked. Curse of the Wulfen: a Wulfen unit that is not battle-shocked and is within 6in of a SPACE WOLVES CHARACTER (non-Wulfen) or 12in of a Wolf Priest has +1 OC (INFANTRY) or +3 OC (VEHICLE: Wulfen Dreadnought, Murderfang). Hunting Hounds: +1 OC for Fenrisian Wolves and hunting wolves within 6in of a Space Wolves CHARACTER. The same applies to Ld auras that keep holders from being battle-shocked.

- **When:** An objective is tied or contested; a Wulfen VEHICLE (+3 OC) or several wolf units can reach it; the enabler can get within 6in / 12in safely; scoring rounds.
- **Units:** Space Wolves Wulfen units, Wulfen Dreadnought, Murderfang, Fenrisian Wolves, Wolf Guard Headtakers, Wolf Scouts; Space Wolves characters and Wolf Priests as enablers.
- **Move type:** Normal Move
- **11e rules (verified):** Curse of the Wulfen (.llm/codex_11e_wahapedia/space-marines/SPACE_WOLVES.md:17-18). Hunting Hounds (space-marines/wahapedia/Datasheets_abilities.csv:349, :793, :840). The engine applies it as an OC aura via MissionManager.model_oc (MissionManager.gd:659-690; SWArmyRules11e.gd:40). 14.02.
- **AI today (none):** Neither rule is referenced in AIDecisionMaker.gd. The AI's OC numbers come from MissionManager.model_oc (AIDecisionMaker.gd:13044-13048), so an aura that is already active is counted, but nothing moves the enabler or the Wulfen to switch it on, and movement never uses the UnitAbilityManager aura helpers.
- **Engine support:** Reuse MissionManager.model_oc (MissionManager.gd:659) at a test position, and UnitAbilityManager.is_unit_in_aura / find_friendly_units_within_aura (UnitAbilityManager.gd:3662-3730). New: 'aura enabler' destinations near contested objectives, scored by the OC gained.
- **Value (low):** Limited to Space Wolves, though +3 OC can swing an objective.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/space-marines/SPACE_WOLVES.md:17-18 (Curse of the Wulfen text, checked)
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_wolves/SWArmyRules11e.gd:40 (OC aura through the MissionManager hook)
  - Factions-stream grep: 'Curse of the Wulfen' and 'Hunting Hounds' -> 0 hits in /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd
- **Found by:** factions

#### OBJ-43 — Shoot-and-scoot: take a forward firing position knowing a post-shooting move can reach an objective

Units that can move after shooting can take a forward firing spot in the Movement phase, then use the second move to reach an objective, break line of sight or leave charge range. Examples:
- Wreckas GRAB IT: a normal move of up to 6in that must end within range of an objective; no charge afterwards.
- Gravis PURGATION PUSH: 5in, must end within objective range.
- Land Speeder Purgation Run; Pallas Mobile Hunter; Phobos Execute and Redeploy / Shadow Masters; Captain in Phobos Armour Tactical Fluidity.

- **When:** Targets are just out of range from a safe spot, an objective or safe spot lies within the post-shooting distance, and the unit doesn't need to charge.
- **Units:** Breaka Boyz, Flash Gitz, Tankbustas (Wreckas), Gravis (Linebreaker), Land Speeders, Pallas Grav-attack, Phobos units.
- **Move type:** Normal Move (plus an adjacent post-shooting reactive move)
- **11e rules (verified):** GRAB IT text (.llm/codex_11e_wahapedia/orks/RULES.md:212, checked). PURGATION PUSH (space-marines/RULES.md:681). Reactive normal moves follow 09.05 (40k/scripts/rules/ReactiveMove11e.gd:3-25).
- **AI today (none):** The Movement planner does not anticipate these moves. At use time, GRAB IT is paid when 6in reaches an objective (OrkCodexShootingReactive.gd:252-253, 688-699), and Execute and Redeploy only when a 6in move reaches one. Purgation Run, Mobile Hunter and Tactical Fluidity are declined with score 0.0 (SMAbilitiesC.gd:1930-1931; CustodesAbilities.gd:1329-1330; SMAbilitiesB.gd:1827-1828).
- **Engine support:** Reuse ReactiveMove11e.solve (ReactiveMove11e.gd:315-466) to predict the second move, and MissionManager.model_gap_to_objective_range_px (MissionManager.gd:569). New: value a Movement-phase candidate as the shooting value from the forward spot plus the objective or safety value reachable by the post-shooting move.
- **Value (low):** Only a few units and stratagems, but it turns shooters into objective grabbers.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/orks/RULES.md:212 (GRAB IT: 'Your unit can make a normal move of up to 6", and must end that move within range of an objective. Your unit is not eligible to declare a charge until the end of the turn.')
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/space-marines/RULES.md:681, :622, :619 (per the factions stream)
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_marines/SMAbilitiesC.gd:1930-1931; /home/user/warhammer-40k-godot/40k/scripts/codex/custodes/CustodesAbilities.gd:1329-1330; /home/user/warhammer-40k-godot/40k/scripts/codex/space_marines/SMAbilitiesB.gd:1827-1828 (declined as plan-level)
- **Found by:** factions

#### OBJ-46 — Keep a bombing lane open for strikes at the end of the opponent's Fight phase

Three aircraft abilities act at the END of the opponent's Fight phase, from wherever your Movement phase left the aircraft:
- Burna-bommer, Burna Bomb: a visible non-Lone-Operative, non-MONSTER/VEHICLE enemy within 36in. On a 2+ it takes D3 mortal wounds, cannot be hidden until the end of your next turn, and your ranged attacks against it gain [IGNORES COVER].
- Blitza-bommer, Boom Bomb: within 24in.
- Ares Gunship, Infernus Firebombs: within 24in.
End the aircraft's move with broad central visibility over the enemy's likely Hidden objective holders, so the bomb strips Hidden and cover before your next shooting at them.

- **When:** The enemy holds objectives with Hidden infantry, and the aircraft can end its move safely with central visibility.
- **Units:** Burna-bommer, Blitza-bommer, Ares Gunship.
- **Move type:** Normal Move (AIRCRAFT)
- **11e rules (corrected):** Datasheet text: .llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:111 (Burna Bomb, checked), :115 (Boom Bomb); custodes/wahapedia/Datasheets_abilities.csv:94 (Infernus Firebombs). 13.09 Hidden (40k_11th_edition_core_rules.txt:2292-2303). The engine implements 'cannot be hidden' at TerrainManager.gd:999-1005.
  - _Skeptic:_ All three bombers are AIRCRAFT: Burna-bommer and Blitza-bommer (orks Datasheets_keywords.csv) and Ares Gunship (custodes Datasheets_keywords.csv). AIRCRAFT can only make ingress moves (23.02 :3505-3506), so 'Normal Move' is illegal. They start in strategic reserves (23.01 :3500-3501) and arrive by ingress from round 2; they cannot use Rapid Ingress (15.07 :2724). They stay on the battlefield through the opponent's Fight phase and return to reserves at the end of the opponent's turn (23.02 :3507-3509). So the lane is chosen at the ingress set-up: wholly within 6″ of an edge and more than 8″ from enemies (20.04 :3264-3266). In the rules, friendly models of other units can block that sight line (06.01 :1029-1030). Burna Bomb needs a visible target within 36″; Boom Bomb and Infernus Firebombs within 24″. — 40k_11th_edition_core_rules.txt:3499-3509, 3255-3273, 2724; orks/wahapedia/Datasheets_abilities.csv:111,115; custodes/wahapedia/Datasheets_abilities.csv:94
  - _Errata check:_ The bombs target a 'visible' enemy unit, which must be visible to the aircraft itself, and a Hidden model is visible only to enemy models within its detection range (15in unless modified); Hidden now also covers INFANTRY/BEASTS/SWARM in areas with only light features. So to bomb a holder unit whose models are all Hidden, the aircraft must set up within that range, not merely within 24in/36in with open sight lines. — Commentary 06.01.01 Describing Visible Units; 13.09 errata
- **AI today (none):** burna_bomb, boom_bomb and infernus_firebombs score 3.0 when the ability is offered (OrkAbilities11e.gd:2309; CustodesAbilities.gd:1318), but the aircraft's own move ignores the bombing lane.
- **Engine support:** Reuse TerrainManager.model_visible_11e (TerrainManager.gd:1201) at test positions. New: an aircraft destination term = enemy objective holders visible within 24in / 36in.
- **Value (low):** Only three datasheets.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:111
  - /home/user/warhammer-40k-godot/40k/autoloads/TerrainManager.gd:999-1005 (Burna Bomb 'cannot be hidden')
  - /home/user/warhammer-40k-godot/40k/scripts/codex/orks/OrkAbilities11e.gd:2309; /home/user/warhammer-40k-godot/40k/scripts/codex/custodes/CustodesAbilities.gd:1318 (scored only when the ability is offered)
- **Found by:** factions

#### OBJ-N02 — Anchor one model on the objective and stretch the rest toward the next job _(added by completeness review)_

A unit only needs enough models inside the objective's terrain area to win the OC count. Coherency only requires each model to be within 2″ of one other model and within 9″ of every model. So leave one or two models in the area and move the rest to the edge of that envelope toward the next task: a charge (charge eligibility is measured from the closest model), a firing lane, the approach to a second objective, a screening line or a table-quarter boundary. This differs from OBJ-15, which toes in from the safe side to minimise exposure, and from OBJ-01, which holds. The per-model obligations of a later charge move are not verified here.

- **When:** A multi-model unit holds an objective with spare OC, a second job lies within about 9″ of the area, the stretched models are not needed for the OC count, and the anchor models are not left exposed alone.
- **Units:** Large infantry units (Boyz, Intercessors, Termagants) and units with high OC per model
- **Move type:** Normal (per model; only some models move)
- **11e rules (corrected):** 03.01 you may move one or more of a unit's models (40k_11th_edition_core_rules.txt:379-387). 03.03 coherency: 2″ to one model plus a 9″ envelope (:518-530). 14.02 a model within the terrain area is in range and adds its OC (:2401-2420). 11.02 'within 12″' is measured from the closest part of the base (01.04, :163-170).
  - _Errata check:_ Coherency also requires the unit to be a single contiguous group. Each stretched model must link back to the anchor models through a chain of models each within 2in horizontally and 5in vertically of the next, as well as being within 9in of every model, so a detached sub-group is illegal even if each of its models has a 2in partner. — FAQ 03.03 Coherency
- **AI today (none):** The executor either moves every model by one vector (rigid-block and formation passes, AIDecisionMaker.gd:14527-14600 and :15714) or holds the whole unit (REMAIN_STATIONARY at :7194 and :7350). There is no partial-unit stretch.
- **Engine support:** MovementPhase validates per-model destinations and coherency (MovementPhase.gd:1017-1072), so a subset move is legal. _ai_model_in_objective_range (AIDecisionMaker.gd:13145) tests each model. New: a stretch-formation generator that pins k models in the area and translates the rest within the 9″ envelope.
- **Value (low):** Gives big units extra reach and charge tempo, but the 9″ envelope keeps the gain small.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:518-530 (03.03 coherency)
- **Found by:** cross_bucket_critic

#### OBJ-N03 — Straddle two objectives with one unit _(added by completeness review)_

Where two objectives lie within one unit's 9″ coherency envelope (two terrain areas, or a marker and an area), put models in both. A model's OC counts toward every objective it is within range of, and the unit counts as controlling each one. One cheap unit can then hold or contest two objectives for threshold rows (OBJ-19), or deny two at once.

- **When:** The layout puts two objective areas or markers less than about 9″ apart edge to edge (layout dependent, e.g. 6-objective maps), and the unit has enough OC per model to matter on both.
- **Units:** Multi-model infantry with OC 1-2 per model
- **Move type:** Normal / Advance
- **11e rules (corrected):** FAQ 14.02: 'can the same model's OC count towards more than one objective that model is within range of? Yes' (40k_11th_edition_errata_faq_commentary.md:550-553). 03.03 9″ envelope (40k_11th_edition_core_rules.txt:518-530). 14.01.01 objective markers have 3″ range (errata md:546-548).
  - _Errata check:_ The models in the two objectives must form one contiguous chain (each within 2in of the next) as well as staying inside the 9in envelope; two separate clumps are not legal. The gap a unit can straddle therefore depends on its model count and base size (e.g. two 32mm-based models can bridge only about 4.5in), not just on the 9in envelope. — FAQ 03.03 Coherency
- **AI today (none):** _assign_units_to_objectives (AIDecisionMaker.gd:9834) scores (unit, objective) pairs and gives each unit exactly one objective; there is no candidate for a pair of objectives.
- **Engine support:** MissionManager.model_in_objective_range (MissionManager.gd:529). New: a candidate type for objective pairs that fit inside one unit's envelope.
- **Value (low):** Layout dependent: a big payoff when two objectives are close, none otherwise.
- **Evidence:**
  - 40k_11th_edition_errata_faq_commentary.md:550-553 (FAQ 14.02)
  - MissionManager computes each objective's level of control independently over all units (MissionManager.gd:863-905), so a model in two ranges already counts twice in-engine
- **Found by:** cross_bucket_critic

#### OBJ-42 — Buy the reach: pair the move with a move or advance boost when it turns 'one turn short' into 'arrives now'

Plan objective and charge reach with the real, modified distances:
- +M: Follow Me Ladz, Cybork Boosta, Lightning-fast Strike, Wolf-Touched, FUNGUS-FUEL INJECTION (+2in), etc.
- Advance-roll bonuses: 'ERE WE GO (+2 to advance rolls in 11e), Fuel-mixa Grot (+1).
- Effects that set the advance roll to 6: SUDDEN ONSLAUGHT, Wind Walker, Veil of Time, Shokk-boosta.
- Re-rolls: Waaagh!, Supercharged Engines, etc.
Spend the CP or ability when it converts a maybe into a guaranteed arrival on the objective this turn.

- **When:** The objective or charge distance is beyond M but within the modified M or a fixed-6 advance; the unit has the modifier, or a CP-cost boost is affordable; arriving now is worth a scoring window.
- **Units:** Ork bosses, Meks, Wagons, Speed Freeks, Boyz; Space Marine Mounted units / Speeders and Jump Pack captains; Space Wolves units near Venerable Dreadnoughts; Custodes (Solar Watch, Knight-Centura).
- **Move type:** Advance / Normal Move
- **11e rules (verified):** Stratagem and datasheet texts, e.g. 'ERE WE GO: 'Your unit has +2 to advance rolls' (.llm/codex_11e_wahapedia/orks/RULES.md:143). 09.06 Advance (40k_11th_edition_core_rules.txt:1401-1414). 15.02 (:2651-2672).
- **AI today (partial):** FUNGUS-FUEL and 'ERE WE GO are paid when the move is already an Advance (or when FFI's extra 2in matters), and the move is re-planned from the real move cap (OrkCodexMovement.gd:275-287). The free Waaagh! advance re-roll is taken on 1-3 (OrkArmyRules11e.gd:176). The proactive 'ERE WE GO heuristic at AIDecisionMaker.gd:26371 still assumes the 10e +2 to advance and charge. SUDDEN ONSLAUGHT is only used after the AI has already chosen to Advance (SMCodexAMovement.gd:289-291); Shokk-boosta and INEXORABLE score 0. The Advance and objective choices themselves never consider modified reach.
- **Engine support:** Reuse _advance_reach_chance (AIDecisionMaker.gd:13247) and _prob_sum_d6_at_least with face_probs (12788) for re-rolls and fixed rolls. New: a per-unit 'reach profile' (M bonus, advance bonus, fixed 6, re-roll) fed into the candidate gap and turns_to_reach.
- **Value (low):** An accuracy improvement spread across many faction tools rather than a new plan.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/orks/RULES.md:143 ('ERE WE GO, checked), :94, :96, :129, :253 (per the factions stream)
  - /home/user/warhammer-40k-godot/40k/scripts/stratagems/ork_codex/OrkCodexMovement.gd:275-287 (FUNGUS-FUEL / 'ERE WE GO priced only for Advance moves, or FFI when the extra 2in matters)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:6921, :26371 (the proactive 'ERE WE GO heuristic still described as +2 advance AND charge, which is the 10e version)
  - 40k/scripts/AIDecisionMaker.gd:2009-2023 (FIX_WAAAGH_ADV_REROLL comment: with the re-roll, faces 1-3 are 1/12 each and 4-6 are 1/4 each, mean 4.25″; RACE-1 odds go from 0.28 to 0.54; 11e rules audit AR-06)
  - 40k/scripts/AIDecisionMaker.gd:2258-2259 (ADVANCE_REROLL_EXPECTED_EXTRA_INCHES, ADVANCE_REROLL_BAND_INCHES)
  - 40k/autoloads/AIPlayer.gd:1579-1610 (the free Waaagh! re-roll is taken on a 1-3)
- **Absorbed duplicates:** COO-23 (Plan Advances around advance re-rolls and fixed advance results)
- **Found by:** factions, bucket-editor

#### OBJ-44 — Split a multi-model unit to cover more objectives, then spread the pieces

Unit-splitting rules multiply bodies for objectives and actions. UNLEASH THE LIONS (Command phase) turns a Custodes Terminator unit of 2+ models into single-model units. Kommandos' Taktikal Know-wotz (Declare Battle Formations) makes two 5-model units. After the split, send the pieces to different objectives or flanks rather than moving them as a block.

- **When:** There are more objectives or actions than units, and the brick isn't needed concentrated this turn. Counterpoint: Custodes usually want to stay concentrated (OBJ-30).
- **Units:** Custodes Allarus / Aquilon Terminators, Kommandos.
- **Move type:** Normal Move (after a Command-phase or formations split)
- **11e rules (corrected):** UNLEASH THE LIONS (.llm/codex_11e_wahapedia/custodes/RULES.md:119, checked: 'Your unit is split into separate units, each containing one model'). Taktikal Know-wotz (.llm/codex_11e_wahapedia/ork_abilities_audit.md:40).
  - _Errata check:_ Kommandos are a 10-model unit, so Taktikal Know-wotz normally gives 5+5. With Boss Snikrot attached (11 models) the stated 5/5 split is impossible, so the unit is split into two units as equal as possible (6 and 5, noting which models form each), and split units can never be split again. — 01.02.06 Splitting Units errata; Commentary 01.02.06 Splitting Units
- **AI today (partial):** UNLEASH THE LIONS is used from round 2 with at least 2 CP 'to cover more objectives' (AIDecisionMaker.gd:6477-6500). The single-model pieces then go through the normal one-unit-one-objective assignment, which spreads them only as far as OC needs dictate. Kommandos are split at deployment.
- **Engine support:** Exists. Optionally gate the split on 'objectives needing OC outnumber the available units'.
- **Value (low):** Only two units are in scope.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:6477-6500 (UNLEASH THE LIONS from R2 with >= 2 CP 'to cover more objectives')
  - YouTube EAqaLgAudQo @216:00 (Tabletop Titans): "custodians are just not designed that way. They want to be hanging out together just few units but just wrecking ball" (ai_learnings.json F022, counterpoint)
- **Found by:** factions

### Mission actions & secondaries

#### MIS-01 — Stage a cheap action carrier with a Normal move, then keep it still

Shared rule for every 11e action card. Primary actions: Secure Asset, Sabotage, Vanguard Operation, Maintain Control, Sensor Sweep, Booby Trap, Decoy, Triangulate, Extract Intelligence, Surveil. Secondary actions: Cleanse, Plunder. Each card's site is in MIS-02 to MIS-06, MIS-18 and MIS-23. Send the unit whose lost shooting and charge cost least and that can reach and survive the site (small, cheap, mobile, able to become Hidden), not simply the nearest unit. It must get there by a Normal move, Remain Stationary, a Rapid or Tactical Disembark followed by a Normal move, or an ingress or Deep Strike arrival. It must never Advance or Fall Back. It must end unengaged, not battle-shocked, with OC 1+, and not already acting (an attached unit counts as one unit). After it starts the action in the Shooting phase it cannot shoot (TITANIC excepted) or charge. Any further move other than pile-in or consolidation, or becoming battle-shocked, makes the action fail, so plan no further move for it. TITANIC units lose nothing: they can start while engaged and still shoot.

- **When:** Any turn an action card is live and a qualifying site is within Normal-move reach. Choose the carrier before deciding whether that unit Advances. Rank candidates by ranged and charge output forgone plus points at risk. Exclude units holding screen, denial or objective-keeper jobs.
- **Units:** OC 1+ units that are not AIRCRAFT/FORTIFICATION and not battle-shocked: cheap infantry and small-base units, characters with nothing worth shooting, TITANIC units (no shooting cost).
- **Move type:** Normal (also Remain Stationary, Disembark rapid/tactical, Reserves arrival)
- **11e rules (corrected):** 16.01 Performing Actions (40k_11th_edition_core_rules.txt:2794-2828): eligibility :2808-2817; no shooting (excluding TITANIC) and no charge :2819-2822; any move except pile-in or consolidation, or leaving the battlefield, cancels :2824-2828. 09.06 Advance :1413-1415 and 09.07 Fall-back :1436-1439 bar starting an action. 01.07: battle-shocked units have OC '-' and cannot start or complete an action (:216-222). 18.04: a disembark is not a barred move, but Combat Disembark battle-shocks the unit (:3055-3056). Engine: ActionsManager.gd:117-193 (eligibility and faction waivers), :247-257 (a move cancels), :263-280 (battle-shock blocks completion). Corrections: youtube#46 says Knights must pay CP to shoot and act, but 16.01 exempts TITANIC units from the no-shooting effect (:2821), so the 1CP quote is unverified. core-rules#82's Gather Intel site is any non-home objective without your marker (missionCards.json:2071), not only NML objectives. Plunder needs a terrain AREA outside your territory (missionCards.json:2367).
  - _Errata check:_ Becoming battle-shocked fails a started action only for units with no rule that lets them start actions while battle-shocked. Per FAQ 16.01, such units (e.g. Tactical Mainstay, CONSERVAI ka'tah; see MIS-36) keep the action going if they become battle-shocked after starting it, but a battle-shocked carrier still has OC '-' and so cannot meet a 'controls the objective' completion (01.07, 14.02). — FAQ 16.01 Performing Actions (also filed under FAQ 01.07 Battle-shock Rolls)
- **AI today (none):** No movement candidate stages a carrier. The AI never dispatches START_ACTION; only the human ShootingController.gd:4894 does. In the Shooting phase the AI only takes PERFORM_SECONDARY_ACTION with a unit that already stands on a site, scored as VP x1.5 minus shooting value (AIDecisionMaker.gd:16472-16484, 23780-23818). The Advance decision never checks that 09.06 bars actions (_should_unit_advance 12650-12748, long trip 12946-13015). MissionManager resolves primary-card actions by position at end of turn (MissionManager.gd:1841-1953). Sabotage, Vanguard and Extract Intelligence fall back to a positional score when no action was started (e.g. :2749-2767), so in the engine the AI scores without giving up shooting. Action rule types add only a flat +1.0 objective pressure (AIDecisionMaker.gd:22874-22878).
- **Engine support:** Reuse ActionsManager.can_start_action / get_startable_actions (ActionsManager.gd:117, :60), MissionManager.can_start_mission_action_11e (MissionManager.gd:2030-2047) and get_card_action_summary_11e (:2210), _estimate_unit_shooting_value (AIDecisionMaker.gd:23954) for the cost of forgone shooting, and _compute_movement_toward_target (14212). New: a site generator per card; a carrier cost (shooting and charge value forgone plus points at risk); a plan flag that forbids Advance/Fall Back for the chosen carrier and holds it after it arrives; dispatch of START_ACTION in the Shooting phase.
- **Value (high):** Action primaries pay up to 15VP per turn and Cleanse/Plunder up to 5VP. Under the real 11e rules none of them score without a carrier that arrived by Normal move, and nothing in the AI models that.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2808-2828 (16.01)
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1413-1415, :1436-1439 (09.06 / 09.07)
  - /home/user/warhammer-40k-godot/40k/scripts/rules/ActionsManager.gd:117-193, :247-280
  - YouTube VPTL092E0VI @12:00 (Grimdark Breakdown, ai_learnings F018): “They have very small bases and then put down somewhere else on the board to do the action”
  - YouTube 7AgzQIEq3j4 @10:00 (TacticalTortoise 40k, F018): “Titanic units can shoot and perform actions. So, it's not actually like that bad”
  - YouTube 42CPnCfuCN8 @01:00 (Recon By Fire, F018; which rule it refers to is unverified): “for one CP, they are capable of shooting and still being able to perform an action”
  - _…and 6 more_
- **Absorbed duplicates:** COO-13 (Give the action to the cheapest unit that can reach it and still meet its completion condition)
- **Found by:** core-rules, missions, youtube, web, first-principles

#### MIS-05 — Booby-trap as many untrapped terrain areas as you have spare units, objective areas first

Death Trap's Booby Trap completes immediately, so the unit needs neither to survive nor to control anything. Each distinct unit that Normal-moves into a different untrapped terrain area outside your deployment zone (or in range of a non-home objective) traps it: 2VP per area trapped this turn, +3VP if the area is an objective. Areas stay trapped, so each turn needs fresh ones. Send every spare unit that has not advanced, OC-1 chaff included, into different areas, objective areas first. 45 of the 48 shipped layouts have 16 areas, and 4 non-home objectives lie outside your DZ. Trap the areas the Take and Hold opponent must stand in, then kill units that started their turn there for 3VP.

- **When:** Your primary is Death Trap. Every turn while untrapped areas are within Normal-move reach.
- **Units:** Many cheap units including OC-1 chaff; infantry becomes Hidden in dense areas.
- **Move type:** Normal
- **11e rules (verified):** missionCards.json death-trap (:767): Shooting phase; a unit in range of a non-home objective or within an untrapped terrain area outside your DZ; unlimited, one area each; completes immediately. Pays 2VP per area trapped this turn, +3VP if it is an objective, 3VP if an enemy unit that started the turn in trapped terrain is destroyed, and 4VP at the R2+ Command check. 16.01. 14.01: objectives are terrain areas (40k_11th_edition_core_rules.txt:2389-2399). Engine deviation, found by reading: get_booby_trap_candidates_11e does not exclude areas inside your own DZ (MissionManager.gd:3106-3135).
- **AI today (none):** At end of turn the engine traps whatever areas friendly units already stand in, one unit per area (MissionManager.gd:1910-1928, 3138-3160). The AI does not price trapped_score (+1.0, AIDecisionMaker.gd:22874-22878), and no movement candidate aims at untrapped areas.
- **Engine support:** MissionManager.get_booby_trap_candidates_11e (3106), _assign_booby_trap_units_11e (3138), _layout_defines_terrain_areas_11e (2989), _terrain_objective_ids_11e; TerrainManager.area_at / build_area_group_map (TerrainManager.gd:792-950). New: an untrapped-area target generator (the area interior point nearest each spare unit) and a one-unit-per-area assignment.
- **Value (high):** Up to 5VP per objective area and 2VP per other area every turn, with no survival requirement: the most VP per unit of any primary.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:767
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1910-1928 (end-of-turn auto-trap), :3106-3160 (candidates, one unit per area), :2829-2845 (trapped_score)
  - /home/user/warhammer-40k-godot/40k/terrain_layouts/*.json (45 layouts with 16 'area' pieces and 5 objectives; 1 with 14 areas)
  - https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics (search snippet: Booby Trap marks an area Trapped; non-objective area 2VP)
- **Found by:** missions, first-principles

#### MIS-06 — Occupy an enemy-territory terrain area the enemy cannot get back into this turn

Vanguard Operation: once per turn a carrier within a terrain area inside the opponent's territory starts the action. It completes at end of turn for 4VP only if no enemy unit is within that area. Pick an area with no enemy models now that enemy reactions in your turn cannot reach. Fire Overwatch at the end of your Movement phase (visible target within 24in, hits only on unmodified 6s) can kill the carrier before it starts. Heroic Intervention Into the Fray at the end of your Charge phase (enemy units within 6in, roll capped at 6) can put an enemy model into the area. A dense area keeps INFANTRY Hidden, since the carrier does not shoot. Deep Strike can land in such an area from R2 and act the same turn.

- **When:** Your primary is Vanguard Operation. Every turn, choosing the safest qualifying area.
- **Units:** Cheap OC infantry (Hidden in dense areas) and deep strikers.
- **Move type:** Normal (or Reserves arrival via Deep Strike)
- **11e rules (corrected):** missionCards.json vanguard-operation (:1597): once per turn; terrain in enemy territory; completes if no enemy units are in that area; 4VP; 2VP for any kill; 4VP at the R2+ Command check; 10VP at end of battle for the enemy home. 15.08 Fire Overwatch (40k_11th_edition_core_rules.txt:2735-2761). 15.11 Heroic Intervention (:2734-2766): Leap to Defend only targets units that made a charge move; Into the Fray targets units within 6in. 13.09 Hidden (:2292-2303). 24.09 Deep Strike (:3649-3660). Correction to missions#17: a carrier cannot charge, so only Into the Fray (6in) threatens it, not a 12in reach. The engine approximates enemy territory with the enemy DZ polygon (MissionManager.gd:2134-2167, :3224-3238).
  - _Skeptic:_ The 'only Into the Fray threatens it' correction is too strong. Leap to Defend can still put an enemy unit into the area by charging any OTHER friendly unit that charged this phase (15.11 :2751-2754), provided it does not end engaged with non-targets (11.04 :1662-1663). Enemy units also pile in and consolidate in our Fight phase (12.02 :1730-1734; 12.07 :1935-1939; Engaging/Objective modes 12.08 :1954-1961). Enemy surge moves in our Shooting phase must end engaged with the closest enemy unit, which may be the carrier (21.02 :3313-3318). Enemy reactive normal moves triggered by our moves (e.g. SCARPER!, RESPONSIVE TACTICS) and enemy Rapid Ingress at the end of our Movement phase (15.07 :2722; more than 8″, 20.04 :3264-3266) can also put units there. Killing the carrier also stops the action completing (16.01 :2825-2827). — 40k_11th_edition_core_rules.txt:2734-2766, 1660-1663, 1729-1735, 1934-1961, 3301-3326, 2714-2728, 2824-2828; missionCards.json:1597
  - _Errata check:_ Hidden now needs only a terrain area containing LIGHT or dense features, for an INFANTRY/BEASTS/SWARM unit that made no ranged attacks this turn or the previous turn (Overwatch it fired in the enemy turn breaks it). So a light area also hides the carrier from Overwatch beyond 15in, and a dense area adds Gone to Ground: detection range drops by 3in (to 12in) against attackers whose view is blocked by intervening dense features. — 13.09 errata; Commentary 13.11.01 Gone to Ground
- **AI today (none):** There are no terrain-area candidates. vanguard_terrain_area is not priced (+1.0, AIDecisionMaker.gd:22874-22878). The engine credits it only when a unit happens to end in an enemy-DZ area with no enemy in it (MissionManager.gd:2780-2786, :3224-3238).
- **Engine support:** MissionManager._vanguard_area_held_11e (3224), _unit_terrain_area_in_enemy_territory_11e (2134), _player_model_in_terrain_11e; TerrainManager.area_at; _calculate_enemy_threat_data (AIDecisionMaker.gd:28695) for how far enemy reactions reach. New: candidates at interior points of enemy-territory areas without enemy models, scored by enemy reach (6in Into the Fray, visible within 24in for Overwatch) and by Hidden.
- **Value (high):** 4VP every turn from one cheap unit, and the same push sets up the 10VP enemy-home end-of-battle award.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:1597
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2734-2766 (15.08 / 15.11)
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:2084-2095 (completion: no enemy model in the area), :3224-3238 (positional backstop)
- **Found by:** missions, first-principles, web

#### MIS-02 — Send action carriers to different qualifying objectives

Control actions with unlimited uses pay per carrier or per objective. Send several carriers to DIFFERENT qualifying objectives; each carrier must itself control its objective at end of turn, so bring enough OC. Sabotage: any non-home objective, 3VP per saboteur, +2VP in enemy territory (enemy home first, then central, which counts as enemy territory). Stop at the 15VP primary cap (three 5VP saboteurs). Decoy (Smoke and Mirrors): only UNDECOYED non-home objectives. The tag never clears and pays 2VP (+2VP in enemy territory) every turn, and 4+ decoyed objectives pay 10VP at end of battle. Each layout has 4 non-home objectives (2 expansions, central, enemy home), so all four, including the enemy home, must be decoyed at some point. Extract Intelligence (Gather Intel, R2+): non-home objectives with none of your markers, 7VP per completion, so two per turn nearly reaches the cap. End of battle pays 5VP for 3+ markers and 5VP for a marker in range of the enemy home. Cleanse (secondary): two different non-home objectives for 5VP; one alone is 2VP.

- **When:** Your primary is Sabotage, Smoke and Mirrors or Gather Intel (R2+), or Cleanse is in hand. Two or more qualifying objectives are within Normal-move reach of spare carriers that can still control them at end of turn.
- **Units:** Several cheap OC 1+ carriers, durable OC for contested objectives, transports that drop carriers (MIS-31).
- **Move type:** Normal
- **11e rules (verified):** missionCards.json sabotage (:1531; unlimited, one objective each, completes at end of turn if that unit controls that objective; 3VP per unit +2VP in enemy territory). smoke-and-mirrors (:1100; undecoyed non-home; decoyed never clears; 2VP +2VP per objective; 10VP at end of battle for 4+). gather-intel (:2071; R2+; non-home with none of your markers; 7VP per completion; end of battle 5VP for 3+ markers and 5VP for a marker in range of the opponent's home). cleanse (:2599; 2VP/5VP tiers). 15VP per-turn primary cap: PrimaryMissionData11e.gd:60 and 11th_edition_missions_gdm2026.md:7. 14.02: a model is in range of a terrain objective while within its terrain area (40k_11th_edition_core_rules.txt:2405-2406); controlling unit :2421-2424. Central counts as enemy territory for Sabotage: 11th_edition_missions_gdm2026.md:113. All 46 shipped layouts with objectives have 2 home, 2 expansion (NML) and 1 central objective (40k/terrain_layouts/*.json). Conflict: the missions doc (:142-144) limits Extract Intelligence to NML objectives; the card data says any non-home objective.
- **AI today (partial):** Only incidental. The plan captures non-home objectives for generic reasons and the engine credits the card by position: Sabotage on each controlled non-home objective (MissionManager.gd:2749-2767); every controlled undecoyed non-home objective is decoyed automatically (:1890-1904); an intel token goes on any NML objective with a friendly unit in range (:1929-1938). The VP estimator does not price sabotage_per_objective, decoyed_score or intel_tokens_placed; it handles only per_objective and hold_* rules (AIDecisionMaker.gd:22958-23016), and the others get +1.0 (22874-22878). So there is no preference for enemy-territory, undecoyed or unmarked objectives and no cap logic. Cleanse gets an NML zone bonus x0.6 (24227-24231) and is performed only by a unit already on an objective (16472-16484).
- **Engine support:** MissionManager._primary_state_11e (decoyed_ever, intel_tokens), _get_controlled_objectives (MissionManager.gd:3316), _objective_in_enemy_territory_11e (2921), ShootingPhase._objective_cleansed_this_turn (2659), the plan's OC need ledger and _capture_arrival (AIDecisionMaker.gd:13247). New: a per-card objective filter (undecoyed / unmarked / not yet cleansed) and per-objective VP under the 15VP cap, fed into _estimate_objective_vp_value, then one carrier per objective in the capture pass.
- **Value (high):** Sabotage and Gather Intel can each reach the 15VP per-turn cap through these moves alone, and Smoke and Mirrors' 10VP end-of-battle award needs every non-home objective decoyed once.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:1531, :1100, :2071, :2599
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:2749-2767 (Sabotage positional backstop), :1890-1904 (auto-decoy), :1929-1938 (auto intel token, NML only), :2918-2925 (enemy territory = enemy-DZ objective or central)
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:250-256 (enemy-home intel award unreachable in play)
  - /home/user/warhammer-40k-godot/40k/phases/ShootingPhase.gd:2853-2888 (Cleanse offer: non-home objective in range)
  - Web search snippet, tabletopbattles.com Priority Assets review: 'you must also move-block enemy units to keep them off objectives'
- **Found by:** missions

#### MIS-03 — Keep an action carrier and a separate OC holder on central every turn

Vital Link's Maintain Control and the shared Sensor Sweep (Extract Relic, Locate and Deny) need a carrier within range of a central objective that does not move after starting. Both complete only if that unit controls central at end of turn. Vital Link pays 2VP plus 1VP per operation marker within range of central at each end of turn you control it, adds one marker per successful action, and pays +4VP at the R2+ Command check when a held non-home objective is central. Extract Relic pays 4VP per completed sweep (once per turn; not while only one marker remains). Locate and Deny sweeps its own markers down to the one it can hold. Put a cheap carrier and a durable high-OC holder there, and use the 2in engagement range to tie up would-be contesters.

- **When:** Your primary is Vital Link, Extract Relic or Locate and Deny. Every turn from R1 while central can be controlled at end of turn.
- **Units:** Cheap carrier plus a durable high-OC holder.
- **Move type:** Normal
- **11e rules (corrected):** missionCards.json vital-link (:1412): maintain-control once per turn, central only, completes if controlling; EOT 2VP + 1VP per marker within range of a controlled central objective; R2+ Command +4VP for central; end of battle 10VP for the enemy home. extract-relic (:1286) and locate-and-deny (:983) sensor-sweep: central only, once per turn, completes if controlling, restricted when one marker remains. 03.04 engagement range 2in (40k_11th_edition_core_rules.txt:542-552). 16.01. Correction to missions#18: losing central only zeroes that turn's payout. The card does not remove placed markers; the engine keeps a counter (MissionManager.gd:1905-1909) and scores it only while central is held (:2769-2777).
- **AI today (partial):** The VP estimator prices Vital Link's R2+ Command hold_central rule (AIDecisionMaker.gd:23006-23012) and the primary central_bonus applies (10362-10365). central_operation_markers and sensor_sweep_vp are not priced (+1.0 generic, 22874-22878). The engine places the marker or sweeps automatically while central is controlled (MissionManager.gd:1905-1909, :1939-1951), so no carrier/holder split is planned. The PUSH_CENTER plan earmark (+6.0) helps only if a plan author set it (10563-10568).
- **Engine support:** MissionManager.get_objective_ids_by_designation (MissionManager.gd:293), _get_central_objective_id_11e, _relic_markers_11e, objective_control_state; the AI OC ledger. New: a two-unit assignment (carrier plus holder) for central and pricing of the per-marker stack.
- **Value (high):** Vital Link's payout grows every turn central is held, and Extract Relic pays 4VP per sweep and drives its 4VP/5VP final-marker condition.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:1412, :1286, :983
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1905-1909 (auto marker), :1939-1951 (auto sweep), :2769-2777 (marker payout)
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-priority-assets/ (search snippet on Vital Link: 'using the large engagement ranges units have in 11th Edition to your advantage is very important')
- **Found by:** missions

#### MIS-04 — Send the once-per-turn carrier to the best qualifying non-home objective

Secure Asset: any non-home objective, every round including R1, 4VP if the carrier controls it at end of turn. The card also pays 2VP for killing an enemy unit that started the turn on central, and at the R2+ Command check 4VP for holding 1+ non-home and 4VP for holding 3+ objectives. Triangulate: from R2, one NEW untriangulated non-home objective per turn; the tag is permanent. End-of-turn tiers are 3/6/10VP for 1/2/3+ triangulated objectives, with no need to keep control. End of battle pays 10VP for controlling 4+ objectives. Pick the qualifying objective the carrier can control at end of turn with least risk (often your-side expansion) and keep a second OC source next to it. For Triangulation plan the order (e.g. R2 own expansion, R3 central, R4 enemy expansion) and spread to 4+ objectives in R5.

- **When:** Your primary is Secure Asset (every turn) or Triangulation (R2-R4 for the action, R5 for the 4+ spread).
- **Units:** One cheap OC carrier per turn plus an OC holder.
- **Move type:** Normal
- **11e rules (verified):** missionCards.json secure-asset (:1189): once per turn; completes at end of turn if the unit controls the targeted non-home objective; awards as listed. triangulation (:1874): battle_round min 2, once per turn, non-home, tag never clears; tiers; end-of-battle count_min 4. 16.01; 14.02 (40k_11th_edition_core_rules.txt:2401-2424). Engine deviation, found by reading and not run: the Triangulation auto-pick and its prompt accept any controlled objective, home included, and do not wait for R2 (MissionManager.gd:1872-1877, :2286-2290). Secure Asset is modelled as a hold_min rule, not an action (PrimaryMissionData11e.gd:293-299).
- **AI today (partial):** The VP estimator prices Secure Asset's hold_min rule (AIDecisionMaker.gd:22968-23001), so a unit does get sent to a non-home objective. triangulated_count is not priced (+1.0, 22874-22878). There is no preference for a new objective each turn and no carrier selection.
- **Engine support:** MissionManager._primary_state_11e.triangulated, _get_controlled_objectives (3316), _estimate_objective_vp_value (AIDecisionMaker.gd:22928). New: the marginal tier value of one more triangulated objective, and an untriangulated-objective filter for the carrier.
- **Value (high):** Secure Asset pays 4VP every turn, and Triangulation's 10VP tier from R4 depends on one carrier reaching a new objective each turn.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:1189, :1874
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:293-299
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1872-1877
  - YouTube mbNWzDn6Pu4 @05:00 (Exile Wargaming, F018): “we have to triangulate objectives by doing actions on them. We can only do one a turn”
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-reconnaissance/ (search snippet: Triangulation 'can be done once per turn on an objective that is not their home objective')
- **Found by:** missions, youtube

#### MIS-07 — Spread units into uncovered table quarters, wholly inside and clear of the centre

Engage on All Fronts (fixed 2/4VP, tactical 3/5VP) and the Reconnaissance Sweep primary (3/6VP plus 1VP per kill) score presence in 3 or 4 table quarters at the end of your turn. Presence means a unit (not AIRCRAFT, not battle-shocked) wholly within a quarter and not within 6in of the battlefield centre. On the engine's 44x60 board the quarters split at x=22 and y=30. Send a cheap or fast unit to each uncovered quarter, compact, with no base across a quarter line and every base edge more than 6in from the centre. Units holding central give no presence. The 3rd and 4th quarters matter most.

- **When:** Either card is active; Engage on All Fronts can be a fixed card all game. Usually from R1-R2.
- **Units:** Cheap fast units, scouts, small squads; OC is irrelevant.
- **Move type:** Normal / Advance / Reserves arrival
- **11e rules (verified):** missionCards.json engage-on-all-fronts (:2417) and reconnaissance-sweep (:1691): 'engagement-fronts' count_min 3/4. 01.04: measure to the closest part of the base (40k_11th_edition_core_rules.txt:163-169). Engine: SecondaryMissionManager._check_table_quarter_presence (SecondaryMissionManager.gd:1070-1114).
- **AI today (partial):** Engage on All Fronts adds +6.0 when an objective trip's straight-line estimated destination lands in an uncovered quarter (AIDecisionMaker.gd:10435-10441), with no wholly-within or 6in-from-centre test for the moving unit. RI-QUARTER prices Reconnaissance Sweep correctly (_ri_quarter_vp 12894-12940, used at 10368-10376 and 10523-10561), but only on objective candidates. _get_covered_quarters matches the rule (24260-24300). There is no quarter-only destination, and reserves never arrive into an empty quarter.
- **Engine support:** _get_covered_quarters (24260), _ri_quarter_vp (12894), _get_table_quarter (24250); SecondaryMissionManager._check_table_quarter_presence (1070). New: stand-alone candidates at points in each uncovered quarter, more than 6in plus base radius from the centre, nearest each unit.
- **Value (high):** Reconnaissance Sweep pays 6VP per turn and Engage on All Fronts can score every turn as a fixed card, yet both need destinations that are not objectives, which the planner cannot generate.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2417, :1691
  - /home/user/warhammer-40k-godot/40k/autoloads/SecondaryMissionManager.gd:1070-1114
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:24260-24300 (_get_covered_quarters), :12894-12940 (RI-QUARTER pricing)
  - research/youtube/ai_learnings.json F022 ai_impact.risk: 'Concentration loses to mission formats that reward spread (Recon table quarters, Priority Assets actions)'
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-reconnaissance/ (search snippet: 3VP for three quarters not within 6in of the centre, 6VP for four)
- **Found by:** core-rules, missions, web, first-principles, youtube

#### MIS-10 — Arrive from reserves straight onto mission geometry

Place arriving reserves where they score or can start an action this turn, not only near objectives. Options: a flank edge band outside your territory for Outflank (an ingress set-up is always within 6in of an edge); the edge of an uncovered table quarter for Engage on All Fronts / Reconnaissance Sweep, without crossing the halfway line; wholly inside the enemy DZ for Behind Enemy Lines (Deep Strike from R2, strategic reserves only from R3); a terrain area that qualifies for Vanguard Operation, Plunder or Booby Trap (Deep Strike, then act in the Shooting phase); wholly inside NML for Display of Might; or an objective that qualifies for Sabotage, Decoy or Cleanse. Arriving does not stop a unit starting an action, but it cannot make another move until the next Charge phase.

- **When:** R2+ with reserves to place and a positional or action card live. R3 is the last chance for strategic reserves.
- **Units:** Deep strikers and strategic reserves, ideally cheap units.
- **Move type:** Reserves arrival
- **11e rules (verified):** 20.03: arrive from R2 (40k_11th_edition_core_rules.txt:3250-3253). 20.04: ingress wholly within 6in of an edge, more than 8in from all enemy units, no models in the opponent's DZ before R3, no other move until the next Charge phase (:3255-3270). Strategic reserves that have not arrived are destroyed at the end of R3 (:3277). 24.09 Deep Strike: anywhere more than 8in from enemies, even in the opponent's DZ (:3649-3660). 16.01 does not list ingress among the moves that bar actions (:2808-2817). Engine: GameState.ingress_opponent_dz_ban_applies (GameState.gd:375-386).
- **AI today (partial):** Placement ranks only distance to objectives and a 9-15in band from enemies (_score_and_sort_reinforcement_candidates AIDecisionMaker.gd:8204-8244), after a filter for the R2 enemy-DZ ban (8189-8193). The choice of which unit arrives (_decide_reserves_arrival 7728-8017) ignores secondaries. Nothing scores edges, quarters, being wholly in a DZ, terrain areas or NML.
- **Engine support:** Edge-grid candidate generator (AIDecisionMaker.gd:8076-8130) and the deep-strike rings/grid; _get_covered_quarters (24260); SecondaryMissionManager._check_units_near_board_edges (1688), _is_unit_wholly_in_zone (2919), _count_units_wholly_in_nml (2984); MissionManager.get_booby_trap_candidates_11e (3106). New: score each placement candidate with the same card-geometry value functions the movement planner uses.
- **Value (high):** Reserves are the cheapest way to fill an empty quarter, an edge in the enemy half or the enemy DZ, yet today they are placed only by objective distance.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3250-3277, :3649-3660
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:8204-8244 (placement ranking: objective distance and enemy distance only)
  - /home/user/warhammer-40k-godot/40k/autoloads/GameState.gd:375-386
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json (behind-enemy-lines: 'Score per friendly unit (excluding AIRCRAFT and battle-shocked units) wholly within the opponent's deployment zone ... up to a ceiling of 5 VP')
  - /home/user/warhammer-40k-godot/docs/rules/11th_edition_missions_gdm2026.md:48-62, 161-164
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-reconnaissance/ (search snippet: Infiltrate and Deep Strike units are extremely handy for taking table quarters)
  - _…and 4 more_
- **Absorbed duplicates:** TRN-08 (Arrive to score a positional secondary (enemy deployment zone, flank edge, empty quarter, No Man's Land)); TRN-12 (Arrive at an action site and start the action the same turn)
- **Found by:** core-rules, missions, web, first-principles, youtube

#### MIS-23 — Get a Surveil carrier within 18in and sight of an unshielded enemy unit

Surveil the Foe's Surveil action (Shooting phase, unlimited uses, completes immediately) tags one visible enemy unit within 18in that has not been surveilled this turn. It pays 4VP at the end of your turn unless every surveilled unit is within range of an objective shielded by the opponent's operation markers. Normal-move a cheap unit (it need not be able to hurt the target) so that an enemy unit NOT on a shielded objective is within 18in and visible. Hidden infantry is visible only inside its detection range: 15in, and the engine takes 3in off for Gone to Ground. Approach from outside the target's threat range.

- **When:** Your primary is Surveil the Foe; every turn, choosing unshielded targets first.
- **Units:** Cheap mobile unit with line of sight.
- **Move type:** Normal
- **11e rules (corrected):** missionCards.json surveil-the-foe (:1757). 13.09 Hidden (40k_11th_edition_core_rules.txt:2292-2303). 24.24 (:3813-3830). TerrainManager.gd:1057-1080 (detection range per observer).
  - _Errata check:_ Gone to Ground is an official rule, not just an engine choice: a hidden model that is not fully visible to the attacking model because of intervening DENSE features, and whose unit made no ranged attacks this or the previous turn, has its detection range cut by 3in (15in to 12in, never below 9in). The text says 'attacking model', so 12in is the cautious figure for a Surveil sight check; Hidden itself now also applies in terrain areas that hold only LIGHT features, so more targets need the carrier within 15in. — Commentary 13.11.01 Gone to Ground; 13.09 errata; Commentary 02.02.01 Modifiers (detection range 9in-30in)
- **AI today (none):** Surveil is not implemented in the engine: its rule is a 0VP placeholder (PrimaryMissionData11e.gd:276-283) and MissionManager.gd:2847-2852 warns once. The AI has no term for it.
- **Engine support:** TerrainManager.model_visible_11e (1201-1246), hidden_model_visible_to (1047); LineOfSightManager.calculate_los_to_position (101); RulesEngine.unit_sight_line (6641). New: implement the action first, then a destination generator for 'within 18in and line of sight of an unshielded enemy'.
- **Value (medium):** 4VP every turn under the real card, but 0VP in the engine until the action exists.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:1757
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:276-283 (Surveil is a 0VP placeholder)
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:2847-2852
- **Found by:** missions

#### MIS-24 — End a real move within range of objectives that carry enemy operation markers

Under Surveil the Foe, whenever a friendly unit ENDS A MOVE within range of an objective with any of the opponent's operation markers in range, those markers are removed. From R2 you score 5VP at the end of your turn while none of their markers remain, and removing them also exposes their units to your Surveil. This is not an action, so Advance is allowed. Route units to end moves within range of each marked objective. A unit already standing there must actually move, because Remain Stationary triggers no end-of-move rules. Smoke and Mirrors still scores every objective it ever decoyed, so scrubbing earns you VP rather than costing them any. Faction version: ending a move within 1in of an enemy Space Marine Teleport Homer token removes it.

- **When:** You play Surveil the Foe against Smoke and Mirrors and there are markers on the board, or an enemy Teleport Homer token is reachable.
- **Units:** Any unit, including fast or expendable ones.
- **Move type:** Normal / Advance
- **11e rules (corrected):** missionCards.json surveil-the-foe (:1757: clear-markers rule; R2+ 5VP when the opponent has no operation markers left). 09.04 (40k_11th_edition_core_rules.txt:1384-1387). SM Teleport Homer (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:108; SMAbilitiesA.gd:1044-1069). Correction to web#61: Search and Scour has no marker-removal rule (missionCards.json:2005; missions doc appendix :145-147); the rule belongs to Surveil the Foe. The engine approximates removal as 'an enemy unit within range at end of turn' (MissionManager.gd:1849-1864), so in-engine a stationary unit also scrubs.
- **AI today (none):** The AI has no awareness of markers; AIDecisionMaker.gd never references decoys or operation markers. no_enemy_markers gets only the generic +1.0 (22874-22878).
- **Engine support:** MissionManager._primary_state_11e[opponent].decoyed, _enemy_unit_in_range_of_objective_11e (2930); SMAbilitiesA.check_homers_after_move (1044). New: a destination term for ending a move within range of a marked objective, and a rule that the scrubbing unit must not Remain Stationary.
- **Value (medium):** 5VP per turn from R2 for Surveil the Foe, and it also enables that card's Surveil scoring.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:1757, :2005
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1384-1387 (09.04)
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1849-1864, :2804-2806
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_marines/SMAbilitiesA.gd:1044-1069
- **Found by:** core-rules, missions, web, first-principles

#### MIS-25 — Be the only side in the last relic marker's terrain area

Extract Relic and Locate and Deny share one set of markers. At the start the Disruption player marks up to five terrain areas outside their DZ, and each Sensor Sweep removes one (not while only one remains). Both cards pay 4VP at the end of turn and 5VP at the end of the battle when exactly one marker remains, a friendly unit is in its terrain area, and no enemy unit is in it. As markers drop to one or two, move a durable unit into the likely last area and keep enemy models out. When sweeping, choose which marker to remove so the survivor is one you can hold.

- **When:** Either card is active; from about R3, or once two markers remain.
- **Units:** A durable unit able to sit alone in the area; killers to clear it.
- **Move type:** Normal / Advance
- **11e rules (corrected):** missionCards.json extract-relic (:1286, opponent's markers) and locate-and-deny (:983, own markers): one marker left, a friendly unit in the same terrain area and no enemy in it. Correction to first-principles#54: for Extract Relic the last marker is the opponent's, not ours. Engine: _final_relic_marker_held_11e (MissionManager.gd:3240-3250); the automatic sweep removes the last list entry (:1939-1951); set-up picks the five areas farthest from the Disruption home (:1681-1724).
- **AI today (none):** The AI never references relic markers. relic_final_marker is not priced (+1.0, AIDecisionMaker.gd:22874-22878).
- **Engine support:** MissionManager._relic_markers_11e, _final_relic_marker_held_11e (3240), _player_model_in_terrain_11e. New: a candidate that occupies the area, scored on being the only side present at end of turn.
- **Value (medium):** 4VP each turn and 5VP at the end of battle once the markers are down to one.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:1286, :983
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1681-1724, :1939-1951, :3240-3250
- **Found by:** missions, first-principles

#### MIS-26 — Put the planned killer on an objective before it kills

Purge and Secure pays 3VP when a friendly unit within range of an objective destroys an enemy unit, or when an enemy unit that started the turn on an objective is destroyed (one branch, not both). Consecrate: a unit that destroys an enemy unit becomes a consecration unit. At the end of your turn it may consecrate one unconsecrated non-home objective it is within range of (3VP for 1-2, 6VP for 3+, and 5VP at end of battle if the opponent's home is consecrated). Before shooting or charging, move the intended killer into range of a qualifying objective it can still shoot from. Or plan a charge whose Objective Consolidation (Fight phase, adjacent) ends in range.

- **When:** Your primary is Purge and Secure or Consecrate and you expect a kill this turn.
- **Units:** High-damage shooters and melee units likely to destroy a unit.
- **Move type:** Normal (adjacent: Fight-phase consolidation, 12.08)
- **11e rules (corrected):** missionCards.json purge-and-secure (:232; two branches, only one pays), consecrate (:646). 12.08 Objective Consolidation (40k_11th_edition_core_rules.txt:1942-1975; mode :1958). Correction to first-principles#50: Purge and Secure also pays through the victim branch. Engine: Purge and Secure models only the victim branch (PrimaryMissionData11e.gd:115-122); Consecrate is approximated as 'any kill lets one controlled non-home objective be consecrated' (MissionManager.gd:1879-1889).
- **AI today (none):** No term pulls a killer onto an objective before it attacks. The x1.3 charge-intent bonus (AIDecisionMaker.gd:3864-3880) is about where the victim stands. consecrated_count is not priced (22874-22878). Consolidation uses the objective mode only when it applies (B52, 21729-22496).
- **Engine support:** MissionManager.model_in_objective_range (MissionManager.gd:545), _get_controlled_objectives (3316), _primary_state_11e.consecrated; _build_phase_plan charge_intent (AIDecisionMaker.gd:3773). New: for units expected to kill, a destination term for being in range of a qualifying objective while keeping range and line of sight to the target.
- **Value (medium):** 3VP per turn for Purge and Secure and permanent Consecrate tiers worth up to 6VP per turn.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:232, :646
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:115-122
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1879-1889
  - 40k/data/40kdc/missionCards.json:232 (purge-and-secure)
  - 40k/scripts/data/PrimaryMissionData11e.gd:112-126 (engine only models the victim branch, via a death-position proxy, 'approximate': true)
- **Absorbed duplicates:** OFF-41 (Shoot or fight from inside objective range (Purge and Secure))
- **Found by:** missions, first-principles

#### MIS-12 — Get two units wholly inside the enemy deployment zone

Behind Enemy Lines pays 3VP per friendly unit (not AIRCRAFT or battle-shocked) wholly within the opponent's deployment zone at the end of your turn, max 5VP, so two units. It is redrawn if drawn in R1. Ways in: fast units on foot; Deep Strike into the enemy DZ from R2; strategic-reserve ingress there only from R3 (their back-edge band usually lies inside their DZ); scouts and infiltrators that survived. Keep every base inside the zone with a margin of one base radius. Units there also deny the opponent's Defend Stronghold +2VP. OC does not matter. If no unit can get wholly in this turn, stage instead (MIS-29).

- **When:** Card in hand from R2 and a unit can end wholly inside this turn.
- **Units:** Deep strikers, fast cheap units, scouts and infiltrators.
- **Move type:** Normal / Advance / Reserves arrival
- **11e rules (corrected):** missionCards.json behind-enemy-lines (:2679). 01.04: measure to the closest part of the base (40k_11th_edition_core_rules.txt:163-169). 20.04 (:3268); 24.09 (:3660). defend-stronghold (missionCards.json:2706). Correction to core-rules#84: the card text says any enemy unit within their DZ denies the opponent's Defend Stronghold bonus, not only one wholly within; the engine checks wholly within (SecondaryMissionManager.gd:1826-1843). The engine's wholly-within test uses model centres (SecondaryMissionManager.gd:2919-2935).
- **AI today (partial):** +7.0 enemy_zone_push, graded by distance to a hard-coded Search and Destroy zone centre ((32,48)/(12,12), AIDecisionMaker.gd:10390-10412), applied to every unit's objective-trip destination. There is no wholly-within test and no two-unit cap, and reserves never Deep Strike into the DZ for this card (8204-8244).
- **Engine support:** SecondaryMissionManager._get_deployment_zone_polygon (2864), _is_unit_wholly_in_zone (2919), _count_units_in_opponent_zone (1042); AIDecisionMaker._get_deployment_zone_polygon_pixels (24856). New: replace the hard-coded centre with the real enemy DZ polygon and test destinations for wholly-within, inset by base radius.
- **Value (medium):** A reliable 5VP for two units once R2 begins, and it also denies the opponent's Defend Stronghold bonus.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2679, :2706
  - /home/user/warhammer-40k-godot/40k/autoloads/SecondaryMissionManager.gd:1042-1068 (count), :2919-2935 (model centres)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:10390-10412 (enemy zone centre hard-coded to (32,48)/(12,12))
- **Found by:** core-rules, missions, first-principles, web, youtube

#### MIS-13 — Outnumber the enemy wholly inside No Man's Land and stay there

Display of Might pays 2VP at the end of your turn or 5VP at the end of the opponent's turn while more friendly units than enemy units (not AIRCRAFT or battle-shocked) are wholly within No Man's Land, i.e. outside both DZs. The count is of units, not size or OC. Move many cheap units fully out of both DZs into spots that survive the enemy turn (Hidden in dense NML terrain, obscured, out of threat range). Kill or battle-shock enemy units in NML. Disembarked passengers count as separate units; an attached unit counts once. Rapid Ingress at the end of the opponent's Movement phase can add a unit before the 5VP check (adjacent). Your NML units also deny the opponent's own Display of Might.

- **When:** Card in hand. Aim for the 5VP at the end of the opponent's turn when your NML units can survive it.
- **Units:** Many small or cheap units, Lone Operatives, transports with passengers.
- **Move type:** Normal / Advance / Disembark
- **11e rules (corrected):** missionCards.json display-of-might (:2246). The engine treats NML as outside both DZs (SecondaryMissionManager.gd:2984-3025). 13.09 Hidden (40k_11th_edition_core_rules.txt:2292-2303). 24.24 Lone Operative (:3813-3830). 15.07 Rapid Ingress (:2714-2728). Correction to missions#32: only HUMAN players can hold the 2VP to cash 5VP later; AI players score a met tactical card at once (ScoringPhase.gd:119-131).
  - _Errata check:_ Hidden works in any NML terrain area containing LIGHT or dense features, not only dense, for INFANTRY/BEASTS/SWARM units that made no ranged attacks this turn or the previous turn (so a holder must not shoot in your turn if it is to stay hidden through the enemy's). Dense terrain still adds Gone to Ground (detection range -3in) against attackers whose view it blocks. — 13.09 errata; Commentary 13.11.01 Gone to Ground
- **AI today (partial):** nml_priority and an NML objective zone bonus (AIDecisionMaker.gd:24087-24091, applied at 10383-10388 and 10419-10422) only nudge objective trips toward NML objectives. There is no unit-count or wholly-within logic. The hold-for-5VP advice (22603-22660) applies only to human players, so the AI cashes 2VP at the end of its own turn.
- **Engine support:** SecondaryMissionManager._count_units_wholly_in_nml (2984) and _check_display_of_might (1156); threat model (AIDecisionMaker.gd:28695-28990); _position_would_be_hidden (28515). New: a per-destination term for units wholly in NML and an estimate of survival through the opponent's turn; for AI players, a choice of whether to meet the card at the end of its own turn.
- **Value (medium):** 2-5VP for units that would often move forward anyway, but the 5VP tier needs units that survive and a scoring policy the AI lacks.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2246
  - /home/user/warhammer-40k-godot/40k/phases/ScoringPhase.gd:119-131 (AI players keep scoring immediately)
  - YouTube 0Gcpze1G4Lc @10:00 (40K Dirtbags): “I try and get that dense cover for the hidden 12 ... How fast can I get to hidden 12”
  - https://frontlinegaming.org/2026/05/28/11th-ed-40k-rules-roundup-from-the-warhammertv-battle-report/ (search snippet: Display of Might 'scores more at the end of your opponent's turn in no-man's land')
- **Found by:** core-rules, missions, web, first-principles

#### MIS-14 — Walk the Beacon unit out of your territory and keep it alive

Beacon designates one unit when drawn: on the battlefield, or embarked in a transport that is on the battlefield. At the end of the opponent's turn (or the end of R5) it pays 3VP if the beacon is on the battlefield and not within your DZ, or 5VP if not within your territory. An embarked beacon is not on the battlefield, so disembark it. Move it fully across the territory line to a spot that survives the enemy turn: Hidden in dense terrain, out of sight, beyond enemy move-plus-charge reach. If only a 3VP spot is safe, take it rather than lose the unit; a destroyed beacon never scores.

- **When:** Beacon in hand; each turn until scored.
- **Units:** The designated unit, ideally durable, easy to conceal or a Lone Operative.
- **Move type:** Normal / Advance / Disembark
- **11e rules (corrected):** missionCards.json beacon (:2826). 18.02: embarked units are not on the battlefield (40k_11th_edition_core_rules.txt:2995-2999). Engine: territory = your board half (SecondaryMissionManager.gd:1845-1863); scoring checks positioned models (:1767-1824); embarked models have no position (TransportManager.gd:224-227). Correction to first-principles#60: embarking counts for the designation only, not for scoring.
  - _Errata check:_ An INFANTRY/BEASTS/SWARM beacon is Hidden in any terrain area containing LIGHT or dense features, not only dense, as long as its unit made no ranged attacks in the current or previous turn (so it must not shoot in your turn). Dense terrain also lets it go to ground (detection range -3in) against attackers whose view it blocks. — 13.09 errata; Commentary 13.11.01 Gone to Ground
- **AI today (partial):** enemy_zone_push x0.6 and NML priority are applied to EVERY unit's objective trips, not just the beacon (AIDecisionMaker.gd:24205-24210, 10390-10422). AIPlayer designates the most durable unit already outside its DZ (AIPlayer.gd:3603-3633). Nothing scores the beacon's survival specifically.
- **Engine support:** mission_data.beacon_unit_id; SecondaryMissionManager._check_unit_outside_own_dz (1767), _check_unit_outside_own_territory (1801), _get_own_territory_rect (1845); _find_safer_position (AIDecisionMaker.gd:28892). New: a destination term for the beacon only (outside DZ / territory) multiplied by its chance of surviving the opponent's turn.
- **Value (medium):** Up to 5VP from a single unit, lost entirely if the unit dies or stays in your territory.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2826
  - /home/user/warhammer-40k-godot/40k/autoloads/SecondaryMissionManager.gd:1767-1824
  - /home/user/warhammer-40k-godot/40k/autoloads/AIPlayer.gd:3603-3633 (_pick_beacon_unit)
  - https://frontlinegaming.org/2026/05/28/11th-ed-40k-rules-roundup-from-the-warhammertv-battle-report/ (search snippet: 'you just have to survive a turn with the unit you pick and be outside of your deployment zone')
- **Found by:** core-rules, missions, web, first-principles

#### MIS-16 — Put a unit within 3in of the centre and keep enemies 6in away

Centre Ground pays at the end of your turn: 3VP while a friendly unit (not AIRCRAFT or battle-shocked) is within 3in of the centre of the battlefield and no enemy unit is within 3in of it; 5VP when no enemy unit is within 6in. Get any model of a durable unit within 3in of the exact centre (22,30 in-engine, between the two halves of the central objective). Kill or keep out every enemy unit within 6in this turn. Units there give no Engage on All Fronts presence, so use different units for that card.

- **When:** Card in hand; the centre is reachable and enemies near it can be killed.
- **Units:** Durable units to hold the centre, plus killers to clear it.
- **Move type:** Normal / Advance
- **11e rules (verified):** missionCards.json centre-ground (:2311; 3VP and 5VP tiers, only the better one scores). Engine: SecondaryMissionData.gd:561-581; SecondaryMissionManager._check_area_denial (SecondaryMissionManager.gd:1116-1154).
- **AI today (partial):** Objective-trip destinations get center_priority 3.5, fading to 0 at 12in from the centre (AIDecisionMaker.gd:24198-24203, 10424-10433). The central objective gets a 4.0 VP hint (23037-23050), plus the generic kill-proximity bonus. There is no exact 3in test and no plan to clear the 6in ring.
- **Engine support:** SecondaryMissionManager._check_area_denial (1116), _has_model_within_range (2967). New: a centre-point destination (any model within 3in) and a clearance value from killing or keeping out enemy units within 6in.
- **Value (medium):** 3-5VP per turn with one unit, but the 5VP tier needs the area around it cleared.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2311
  - /home/user/warhammer-40k-godot/40k/scripts/data/SecondaryMissionData.gd:561-581
  - /home/user/warhammer-40k-godot/40k/autoloads/SecondaryMissionManager.gd:1116-1154
- **Found by:** core-rules, missions, first-principles, web

#### MIS-17 — Hug a battlefield edge outside your territory, with a partner on the opposite edge

Outflank, per the local card data: 3VP at the end of your turn while a unit (not AIRCRAFT or battle-shocked) is within 6in of a battlefield edge and not within your territory. 5VP when two such units are within 6in of opposite (parallel) edges and at least one of them is outside your territory, e.g. both flanks beyond the halfway line, or your own back edge plus the enemy's. An ingress set-up is always wholly within 6in of an edge, so a flank arrival in the enemy half scores at once (R2+, and not in the enemy DZ before R3). The engine requires every model to be within 6in (measured from model centres) and treats territory as your board half; plan for that.

- **When:** Card in hand; a fast unit or reserve can reach an edge band outside your half.
- **Units:** Fast units, reserves, scouts; OC is irrelevant.
- **Move type:** Normal / Advance / Reserves arrival
- **11e rules (unverified):** missionCards.json outflank (:2339). 20.04 (40k_11th_edition_core_rules.txt:3255-3268). Engine: SecondaryMissionManager.gd:1688-1765 (all models near an edge), :1845-1863 (territory = board half). Conflict: the missions doc (:161-162) and a Frontline Gaming preview say 'not in your deployment zone' with 3VP for one edge and 5VP for two edges, with no mention of territory or opposite edges.
- **AI today (partial):** +4.0 edge_flank when an objective trip's estimated destination is within 6in of a SIDE edge and outside the AI's half, judged by board y (AIDecisionMaker.gd:24212-24216, 10443-10451). Top and bottom edges and the opposite-edge pair are ignored, there is no edge-only destination, and reserves never arrive for this card.
- **Engine support:** SecondaryMissionManager._check_units_near_board_edges (1688), _get_own_territory_rect (1845); reserve edge candidates (AIDecisionMaker.gd:8076-8130). New: a shared board-edge-distance helper, edge-band destinations outside your territory, and a pair assignment for the 5VP tier.
- **Value (medium):** 3-5VP with one or two cheap units, especially through reserves.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2339
  - /home/user/warhammer-40k-godot/docs/rules/11th_edition_missions_gdm2026.md:161-162
  - [Frontline Gaming 11th rules roundup](https://frontlinegaming.org/2026/05/28/11th-ed-40k-rules-roundup-from-the-warhammertv-battle-report/) (web search: within 6in of a board edge and not in your deployment zone; 5VP for two edges)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:10443-10451 (side edges only; own half by board y)
- **Found by:** core-rules, missions, web, first-principles

#### MIS-18 — Plunder: move one cheap unit into a terrain area outside your territory

Plunder is a Shooting-phase action by one unit within a terrain area that lies outside your territory (per the card wording and a Wahapedia FAQ snippet). Once per turn. It completes immediately, so the unit need not survive or control anything, and pays 5VP at the end of your turn. Normal-move the cheapest unit that has not advanced and is unengaged into the nearest area wholly beyond your territory line. Deep Strike arrivals can plunder the same turn. Plunder and Cleanse cannot both be held.

- **When:** Plunder in hand; every turn until scored.
- **Units:** Cheapest OC 1+ unit, deep strikers; infantry stays Hidden in dense areas.
- **Move type:** Normal (or Reserves arrival)
- **11e rules (verified):** missionCards.json plunder (:2367). The 'plundered' tag never clears, but the card does not say an area cannot be plundered again (unverified); the engine does not block it (ShootingPhase.gd:2666-2671). 16.01. Engine: the area must have no vertex in your board half (ShootingPhase.gd:2673-2712). The missions doc table (:62) is vaguer ('Action on objectives to loot').
- **AI today (partial):** nml_priority x0.5 on objective trips (AIDecisionMaker.gd:24218-24224). The 'wants_forward_terrain' hint is set but never read. The action is taken only if a unit already stands in a qualifying area (16472-16484; ShootingPhase.gd:2890-2930). Engine deviation, found by reading: secondary actions use shooting eligibility (ShootingPhase.gd:954-978), so an Advanced unit with Assault weapons is offered Plunder despite 16.01.
- **Engine support:** ShootingPhase._get_plunder_terrain_for_unit (2673), SecondaryMissionManager._get_own_territory_rect (1845), TerrainManager.area_at. New: a candidate at the nearest interior point of an area wholly outside your territory, for the cheapest unit that has not advanced.
- **Value (medium):** A flat 5VP per turn from one cheap unit that needs no survival or control.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2367
  - /home/user/warhammer-40k-godot/40k/phases/ShootingPhase.gd:2673-2712, :2890-2930
  - https://wahapedia.ru/wh40k11ed/the-rules/mission-deck-2026-27/ (search snippet: FAQ says Plunder's 'not within your territory' refers to the terrain area)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:24218-24224 ('wants_forward_terrain' set; never read)
- **Found by:** missions, first-principles

#### MIS-19 — Hold the opponent's home or an expansion objective for Forward Position

Forward Position pays 5VP at the end of your turn while you control the opponent's home objective and/or an expansion objective. This is the local card data and the engine's reading; the card is redrawn in R1. Under that reading the cheapest route is your own-side expansion (obj_nml_1 for P1 and obj_nml_2 for P2 in all 46 shipped layouts). Use the enemy-side expansion or the enemy home only when yours is unavailable or the move also serves another card. If the 'both expansions' reading is correct, you must hold both.

- **When:** Card in hand from R2.
- **Units:** Any OC unit.
- **Move type:** Normal / Advance
- **11e rules (unverified):** missionCards.json forward-position (:2181: 'controls the opponent's home objective and/or an expansion objective', count_min 1). Engine: SecondaryMissionManager.gd:1651-1667. Conflict: the missions doc (:54) and a Frontline Gaming preview say 'both Expansion objectives'; Tabletop Battles says 'each expansion objective'.
- **AI today (partial):** VP hints of 5.0 on the enemy home and 2.5 on EVERY non-home objective, central included (AIDecisionMaker.gd:24179-24187, 23037-23050), plus enemy_zone_push x0.8, which drags units toward the enemy DZ. The expansion designation is never used, so the AI does not know its own-side expansion is enough.
- **Engine support:** MissionManager.get_objective_ids_by_designation('expansion') (MissionManager.gd:293); hints in _estimate_objective_vp_value (AIDecisionMaker.gd:22928). New: an 'expansion' hint kind matched by designation, and dropping the enemy-DZ push for this card.
- **Value (medium):** 5VP per turn, often from an objective the army would hold anyway, if the AI prices the right objective.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2181
  - /home/user/warhammer-40k-godot/40k/autoloads/SecondaryMissionManager.gd:1651-1667
  - [Frontline Gaming roundup](https://frontlinegaming.org/2026/05/28/11th-ed-40k-rules-roundup-from-the-warhammertv-battle-report/) (web search: 'opponent's home objective and/or both expansion objectives')
  - [Tabletop Battles intro to 11e missions](https://www.tabletopbattles.com/40k-an-introduction-to-missions-in-11th-edition/) (web search: 'either the opponent's home objective or each expansion objective')
  - /home/user/warhammer-40k-godot/40k/terrain_layouts/*.json (obj_nml_1 always in P1's half, obj_nml_2 in P2's half)
- **Found by:** missions, web

#### MIS-21 — Take the objective the opponent named as your Tempting Target

When A Tempting Target is drawn, the opponent selects one non-home objective in No Man's Land. You score 5VP at the end of your turn while you control it. Expect the pick that is hardest for you, often their-side expansion. Send OC and killers to that specific objective, staging over two turns if needed, since the card stays in hand until scored.

- **When:** Card in hand; the target can be reached within one or two turns.
- **Units:** OC units, plus killers to clear the holders.
- **Move type:** Normal / Advance
- **11e rules (verified):** missionCards.json a-tempting-target (:2759). Engine: SecondaryMissionData.gd:221-246. Tactical cards stay in hand until scored (SecondaryMissionManager.gd:1602-1617).
- **AI today (partial):** The awareness adds the NML zone bonus and a 2.0 VP hint to ALL NML objectives (AIDecisionMaker.gd:24115-24119). mission_data.tempting_target_id is read only by the discard assessor (23440-23483). When the AI is the chooser it picks the objective the drawer is least likely to control (AIPlayer.gd:3556-3600).
- **Engine support:** mission_data.tempting_target_id; _estimate_objective_vp_value. New: a VP hint for that one objective.
- **Value (medium):** 5VP for one specific objective; today the AI spreads the value over every NML objective.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2759
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:24115-24119, 23440-23483
  - /home/user/warhammer-40k-godot/40k/autoloads/AIPlayer.gd:3556-3600 (AI as chooser)
- **Found by:** missions

#### MIS-22 — Keep each Burden of Trust guard in range of its objective through the enemy turn

Burden of Trust: when the card is drawn, and at the start of each of your turns, you pick one guard unit per objective. Until your next turn an objective is guarded while its guard is within range of it and you control it. It pays 2VP per guarded objective at the end of the opponent's turn (or the end of R5), max 5VP, so three objectives. After picking, move each guard into range of its own objective or keep it there, and never send it on another job. Choose positions that survive and keep an OC margin: Hidden on the area, approaches blocked.

- **When:** Card in hand; plan three objectives you can guard (home plus two).
- **Units:** Durable OC units as guards.
- **Move type:** Remain Stationary / Normal (stay in range)
- **11e rules (verified):** missionCards.json burden-of-trust (:2225). Engine: SecondaryMissionManager.gd:1420-1450 (guard in range and objective controlled), :2238-2321 (guards auto-assigned at start of turn).
- **AI today (partial):** defend_home x0.7, nml_priority x0.7 and a 2.0 VP hint on any objective (AIDecisionMaker.gd:24189-24196, 23037-23050). The 'hold_objectives' flag is never read. Pass-1 holds are driven by OC need and keeper choice (10606-10772), not by which unit is the guard. Overrides such as the melee leave or the Deadly Demise ram can pull a guard off its objective.
- **Engine support:** mission_data.guards; SecondaryMissionManager._count_guarded_objectives (1420), _auto_assign_guards (2238). New: treat a guard as a pinned holder in the plan, and add a term for surviving the opponent's turn with OC to spare.
- **Value (medium):** Up to 5VP for objectives the army often holds anyway, lost whenever a guard wanders off.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2225
  - /home/user/warhammer-40k-godot/40k/autoloads/SecondaryMissionManager.gd:1420-1450, :2238-2321
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:24189-24196 ('hold_objectives' set; never read)
- **Found by:** missions

#### MIS-28 — Prefer objectives inside the opponent's territory when the card pays a territory bonus

Determined Acquisition (Take and Hold vs Disruption) pays 2VP at end of turn per objective you newly control this turn. From R2 its Command check pays 3VP per controlled objective plus another 3VP for each one in the opponent's territory. Sabotage (+2VP per saboteur) and Smoke and Mirrors (+2VP per decoyed objective) pay the same kind of territory bonus. When choosing between capture trips, rank objectives in the opponent's territory (their home, their-side expansion, and central for Sabotage) above equally costly objectives in your own half. For Determined Acquisition also value flipping objectives you did not hold at the start of the turn.

- **When:** Your primary is Determined Acquisition, Sabotage or Smoke and Mirrors.
- **Units:** OC units that can hold forward objectives.
- **Move type:** Normal / Advance
- **11e rules (verified):** missionCards.json determined-acquisition (:63; extra VP per controlled objective in enemy territory, added to the base award), sabotage (:1531), smoke-and-mirrors (:1100). Central counts as enemy territory for Sabotage (11th_edition_missions_gdm2026.md:113). 'Territory' is not defined in the local core rules, so exactly which objectives count is unverified. The engine uses two approximations: the board half (SecondaryMissionManager.gd:1845-1863), and enemy-DZ objectives plus central (MissionManager.gd:2918-2925), which leaves out the enemy-side expansion.
- **AI today (partial):** The VP estimator's per_objective branch ignores the rule's zone filter, so Determined Acquisition's territory bonus is priced on every objective (AIDecisionMaker.gd:22958-22967). hold_new/per_new_objective price newly taken objectives (23013-23016). Sabotage and Decoy territory bonuses are not priced (22874-22878). The result is no preference for enemy territory.
- **Engine support:** MissionManager._objective_in_enemy_territory_11e (2921), _count_controlled_filtered_11e (zone filter); _estimate_objective_vp_value (AIDecisionMaker.gd:22928). New: pass each objective's zone or territory into the estimator and honour rule.zone.
- **Value (medium):** Doubles the per-objective payout for the right objectives on three primaries.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:63
  - /home/user/warhammer-40k-godot/docs/rules/11th_edition_missions_gdm2026.md:19, :113
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:146 (per_objective with zone enemy_territory)
  - Local docs/rules/11th_edition_missions_gdm2026.md (Determined Acquisition) as cited by web#56 and youtube#48
  - /home/user/warhammer-40k-godot/40k/deployment_zones/dawn_of_war.json ('territories' = two halves split at x=22; no .gd file reads 'territories')
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:2857-2875 (the Determined Acquisition zone filter counts only the enemy home), :2921-2925 (Sabotage / Smoke and Mirrors: enemy home or central)
  - _…and 2 more_
- **Absorbed duplicates:** OBJ-20 (Push onto objectives in the opponent's territory when a card pays a territory bonus)
- **Found by:** web, youtube, missions

#### MIS-30 — Advance into positional scoring geometry, never with a unit that must start an action

Advancing costs only the charge and the right to start an action this turn. It does not affect OC or the positional cards: Behind Enemy Lines, quarters, Display of Might, Centre Ground, Outflank, Beacon, Forward Position, Secure No Man's Land, Tempting Target, Defend Stronghold's home objective. When such geometry is beyond M but within M + D6 and the unit has no worthwhile shooting or charge, Advance there; in R5 that is almost always right. Never Advance the unit planned as this turn's action carrier, unless it has a faction exemption (MIS-36).

- **When:** The positional target is beyond Normal-move reach but within Advance reach, and the unit's shooting or charge is worth little this turn.
- **Units:** Fast units, units without good targets, units with Assault weapons.
- **Move type:** Advance
- **11e rules (verified):** 09.06 Advance (40k_11th_edition_core_rules.txt:1401-1415; after moving, no charge and no action :1413-1415). The card conditions in missionCards.json have no move-type requirement.
- **AI today (partial):** Advance is chosen only toward objectives or attack targets (_should_unit_advance AIDecisionMaker.gd:12650-12748, long trip 12946-13015, assignment 10505-10520), never toward an edge band, a quarter or the DZ. Nothing stops an intended action carrier from advancing.
- **Engine support:** _advance_reach_chance (13193), _prob_sum_d6_at_least (12788), EffectPrimitives.has_effect_advance_and_shoot / has_effect_advance_and_charge. New: card-geometry targets in the Advance decision, and a veto for the planned carrier.
- **Value (medium):** Reaches positional VP a turn early at no cost when the unit had nothing to shoot or charge.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1401-1415
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:10505-10520 (Advance assigned only on objective candidates)
- **Found by:** missions

#### MIS-N01 — Line up the turn's easiest kill when a card pays for kill count _(added by completeness review)_

Several cards pay for how many units die, not which ones. Unstoppable Force, Meatgrinder and Destroyer's Wrath pay 3VP at end of turn for destroying 1+ unit, and Meatgrinder and Destroyer's Wrath also pay 4VP for killing more than the opponent did last turn. Delaying Action pays 2VP per unit, Reconnaissance Sweep 1VP per unit, Vanguard Operation 2VP for any kill, and No Prisoners 2VP per unit up to 10. Before other moves are committed, move one or two units to where they can almost certainly finish the weakest reachable enemy unit this turn: a wounded unit, a lone character, isolated chaff, a damaged vehicle. If the 'kill more' row is live, add units toward the next-easiest kills too. Value targets by kill probability, not points.

- **When:** Our primary or secondary has a destroy-1+, per-kill or kill-more rule active this turn, and the AI has no kill banked yet this turn (or is below the opponent's last-turn count).
- **Units:** Any shooter or charger; cheap units for finishing blows
- **Move type:** Normal / Advance with [ASSAULT] / charge setup
- **11e rules (verified):** Primary rows in docs/rules/11th_edition_missions_gdm2026.md:20-21, 24-25, 32, 36 (destroy 1+, kill more than the opponent's last turn, per-unit kills) and the No Prisoners secondary (:50); these score at the End of Turn step (40k_11th_edition_core_rules.txt:1202-1212). The missions doc itself labels card values approximate.
- **AI today (partial):** _build_primary_awareness sets kill_pressure for destroyed_min, per-unit and killed_more rules (AIDecisionMaker.gd:22866-22870), but _calculate_target_value only multiplies target value by 1.15 (:17879-17880). No Prisoners gets a generic proximity bonus (:10468-10481). Nothing knows whether a kill is already banked this turn, and movement never prefers the most killable target.
- **Engine support:** MissionManager already tracks kills: _kills_this_turn_11e(player) (MissionManager.gd:3270) and the rule evaluation at MissionManager.gd:2706-2712. New query: expose kills_this_turn and opponent_kills_last_turn to the AI, and rank reachable targets by kill probability using the existing expected-damage and kill-threshold helpers (_calculate_marginal_value, after AIDecisionMaker.gd:17895).
- **Value (medium):** Purge the Foe primaries pay 3-4 VP every turn for one cheap kill, while the AI currently spends its moves on high-value targets it may not finish.
- **Evidence:**
  - docs/rules/11th_edition_missions_gdm2026.md:20-25, 32, 36, 50
  - [Tabletop Battles: 11e Force Disposition Review, Purge the Foe](https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-purge-the-foe/) (WebSearch snippet only): 'going second tends to be better here as it allows you to react to your opponent when it comes to scoring kill more'
  - YouTube F010, video D5XVd0FRgK8 at 02:00: 'unit left alive on one wood can still hold an objective, block our movement'
- **Found by:** cross_bucket_critic

#### MIS-36 — Use a faction exemption to Advance, Fall Back or stay engaged and still start the action

Some 11e faction rules lift the 16.01 bars, so a carrier can take the faster or safer route and still act. Advance or Fall Back allowed: Ork MIND MOSTLY ON THE MISSION (1CP; Boyz, Kommandos, Stormboyz), Ork Sneaky Little Gitz (GRETCHIN), Space Marine Scout Squad Flexible Asset, Custodes Favoured Conservai. Engaged allowed: Ork Boyz Never Too Busy to Fight. Engaged or battle-shocked allowed, and starting the action does not stop shooting: Intercessor Tactical Mainstay and the Custodes CONSERVAI ka'tah.

- **When:** An action site is beyond Normal-move reach but within Advance reach, or the carrier is engaged or battle-shocked, and the unit has one of these rules.
- **Units:** Gretchin, Boyz/Kommandos/Stormboyz (Taktikal Brigade), Scout Squads, Intercessors, Custodes (Conservai).
- **Move type:** Advance / Fall Back / Remain Stationary (engaged)
- **11e rules (corrected):** .llm/codex_11e_wahapedia/orks/RULES.md:190 (MIND MOSTLY ON THE MISSION), :217 (Sneaky Little Gitz); orks/wahapedia/Datasheets_abilities.csv:69 (Never Too Busy to Fight); space-marines/wahapedia/Datasheets_abilities.csv:372 (Tactical Mainstay), :380 (Flexible Asset); custodes/RULES.md:63 (CONSERVAI ka'tah), :195 (Favoured Conservai). Engine waivers: ActionsManager.gd:139-180.
  - _Errata check:_ Per FAQ 16.01, a unit whose rule lets it start an action while battle-shocked (Tactical Mainstay, CONSERVAI ka'tah) also keeps that action going if it becomes battle-shocked after starting it. A completion that needs the unit to control an objective still cannot be met while it is battle-shocked, because its OC is '-' (01.07, 14.02). — FAQ 16.01 Performing Actions (also filed under FAQ 01.07 Battle-shock Rolls)
- **AI today (none):** MIND MOSTLY ON THE MISSION scores 0.0 because the AI 'never starts actions' (OrkCodexMovement.gd:288-291). CONSERVAI scores 0.0 (CustodesKatah.gd:728-729). No carrier is ever staged (MIS-01).
- **Engine support:** ActionsManager.can_start_action waivers (ActionsManager.gd:139-180); OrkDetachments11e / CustodesDetachments move_keeps_action_eligibility; SMAbilitiesB.action_ignores_engaged_and_shocked. New: let MIS-01's carrier filter check these waivers before ruling out Advance or Fall Back.
- **Value (low):** Matters only for a few factions, and only once MIS-01 exists.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/orks/RULES.md:190, :217
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:372, :380
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/custodes/RULES.md:63, :195
  - /home/user/warhammer-40k-godot/40k/scripts/rules/ActionsManager.gd:139-180
  - YouTube 42CPnCfuCN8 @01:00 (Recon By Fire, F018): “for one CP, they are capable of shooting and still being able to perform an action”
- **Found by:** factions

#### MIS-38 — Send a backup action carrier when the first is exposed to Overwatch

Fire Overwatch happens at the end of your Movement phase, before the Shooting phase in which your actions start. A carrier that ends visible within 24in of an enemy unit can therefore be shot before it acts. Snap shooting only hits on unmodified 6s, so this mostly matters against high-volume shooters. When the action is worth a lot, send a second unit that can perform an action toward the same or another site.

- **When:** A high-value action, a carrier ending visible within 24in of an unengaged enemy unit with many shots, and a spare cheap unit that can reach.
- **Units:** Cheap units able to perform actions.
- **Move type:** Normal
- **11e rules (verified):** 15.08 Fire Overwatch (40k_11th_edition_core_rules.txt:2735-2761): end of the opponent's Movement phase; one visible enemy unit within 24in; hits only on unmodified 6s. 16.01 (:2808-2828).
- **AI today (none):** No carrier is ever staged (MIS-01). The Overwatch exposure penalty ships at 0.0 (OVERWATCH_EXPOSURE_PENALTY, AIDecisionMaker.gd:2662; 28660-28687).
- **Engine support:** _overwatch_exposure_penalty (AIDecisionMaker.gd:28660-28687), TerrainManager.model_visible_11e for the 'visible within 24in' check. New: send a second carrier when expected Overwatch hits could kill the first.
- **Value (low):** Overwatch only hits on 6s, so a backup pays off only against high-volume shooters protecting a high-VP action.
- **Evidence:**
  - Web search snippet only (1d6chan 11th Edition Tactics): 'if there's an Overwatch threat looming, maybe throw in a second unit that can do the action if the first one gets burned' https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2735-2761
- **Found by:** youtube

#### MIS-35 — Fall back toward mission geometry instead of only away from the enemy

A fall-back move (Ordered Retreat if not battle-shocked) bars shooting, charging and actions, but the unit keeps its OC and still counts for positional cards. When a unit must disengage, aim the fall back at mission geometry: an uncovered quarter, an edge band outside your territory, wholly into the enemy DZ or NML, back into range of an objective (it still adds OC), or out of the 6in centre ring when Engage on All Fronts needs it. Never pick Desperate Escape by choice: it forces a battle-shock roll, and a battle-shocked unit has OC '-' and counts for none of the cards.

- **When:** An engaged unit will fall back anyway; choose where it lands by mission value.
- **Units:** Engaged units that are not battle-shocked.
- **Move type:** Fall Back
- **11e rules (verified):** 09.07 (40k_11th_edition_core_rules.txt:1417-1445; restrictions :1436-1439; Desperate Escape battle-shock roll :1440-1441). 01.07 (:216-222). Cards that exclude battle-shocked units: missionCards.json engage-on-all-fronts (:2417), behind-enemy-lines (:2679), display-of-might (:2246), centre-ground (:2311), outflank (:2339).
- **AI today (partial):** The retreat target is the best objective 'behind' the unit (alignment x300, +200 if friendly-controlled, +100 if uncontrolled; _pick_fall_back_target AIDecisionMaker.gd:12429-12480), or otherwise straight away from the enemy. Quarters, edges, NML and DZ geometry are not considered. Ordered Retreat is the default (12157).
- **Engine support:** _compute_fall_back_destinations (AIDecisionMaker.gd:12185), _pick_fall_back_target (12429), plus the card-geometry value functions from MIS-07, MIS-12, MIS-13 and MIS-17.
- **Value (low):** Applies only to engaged units, but turns a forced move into positional VP at no extra cost.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1417-1445
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:12185-12273, 12429-12480
- **Found by:** missions

### Screening, denial & opponent modelling

#### DEN-05 — Seal the screen's gaps against the widest enemy base

When a unit acts as a wall (charge screen, corridor block, objective fill), lay out its models so the clear gap between neighbouring bases is narrower than the widest base of any enemy model that could try to pass — the gap seals when centre distance < rA + rB + d. In 11e a mover may pass straight through your engagement range and is blocked only by base overlap, so the 10e rule of thumb (gap < base + 2″, 'stay 1″ away') is wrong. Coherency caps the wall: each model within 2″ of another and within 9″ of every other model, so one unit seals roughly 9″ plus its end bases (derived). Sealing does not stop FLY units taking to the skies, SUPER-HEAVY WALKERs or (by the rules) enemy M/V on normal/advance moves; the wall still denies end positions within 2″ and charge end positions.

- **When:** Every time a unit is placed as a screen or block; size the gap to the widest non-FLY enemy base that can reach the lane next turn.
- **Units:** Multi-model cheap infantry screens.
- **Move type:** Normal (model layout within the move)
- **11e rules (corrected):** 03.01: a model can be moved through any space its base can fit through and cannot be moved through enemy models (40k_11th_edition_core_rules.txt:385-395); 09.05 (:1390-1397); FAQ 03.04: moving through engagement range does not engage (40k_11th_edition_errata_faq_commentary.md:265); 03.03 coherency 2″ and 9″ (:518-532); 21.03 (:3358-3375); 24.35 (:3940-3966); 17.01 (:2867-2874). Corrected: F006's 'base + 2″' mechanism is 10th edition (already corrected in code).
- **AI today (none):** The seal is only measured and logged after a screener is assigned ([SCREEN-GAP] print, AIDecisionMaker.gd:11563-11578, via _screen_widest_passable_gap_inches :28388-28420); the placement ladder and staging (B38, :14520-14722, :15405+; AIPlayer.gd:2733-2867) translate the unit as it stands and optimise legality, never wall shape.
- **Engine support:** Reuse _screen_max_model_spacing_px (AIDecisionMaker.gd:28380), _widest_enemy_base_inches (:28366), _try_move_with_collision_check (:15405) and the engine coherency check used by the placement ladder. New: a line/arc formation solver that places N models along a target segment at spacing < rA+rB+d inside 2″/9″ coherency, then validates each model with MovementPhase rules.
- **Value (high):** Without it every screen and block (DEN-02/04/19) can leak through 'a tiny hole' (F006 confirmed/high); the geometry helper already exists, only the placer is missing.
- **Evidence:**
  - 40k/scripts/AIDecisionMaker.gd:28344-28420 (SCREEN GAP GEOMETRY: “the gap SEALS iff D < rA + rB + d”)
  - 40k/tests/bench_baselines/2026-08-06_youtube_findings_ab.md:17-19 (F006 not implemented as written: “a 10th-edition rule”)
  - YouTube gRqdSBkqVlA @22:00 (6 Plus Plus Gaming): “What I didn't think of was leaving gaps between my models to screen a 32 mil base” [F006]
  - YouTube xFGyuYmXyJY @10:00 (Proxy Hammer): “you can have a little bit of space in between your models that they won't be able to actually fit through” [F006]
  - YouTube VqwMdS9MuIY @514:00 (TacticalTortoise 40k): “create a gap that is less than 1 in between all of those models ... will prevent any orc model from going through” [F006; 10e-shaped reasoning]
  - Web search snippet (Tabletop Battles reveal recap, unfetched): “being able to move through engagement ranges does make sense with this change, as otherwise screening would be too strong”
- **Found by:** youtube, core-rules, first-principles

#### DEN-06 — Move into cover first to deny it: occupy the contested staging terrain (user example: move into cover)

The denial version of 'move into cover': in rounds 1-2 put bodies into or against the mid-board terrain both armies want to stage in or behind. INFANTRY/BEASTS/SWARM models inside a terrain area that contains light or dense features are Hidden (13.09 as amended), and units behind such an area are obscured from enemies whose every sight line crosses it, so your army stages out of sight. At the same time enemy models cannot end a move within 2″ of yours, so they lose that staging spot, and models without INFANTRY/BEASTS/SWARM/MOBILE cannot move horizontally through dense sections over 2″ tall, so infantry can claim ruins vehicles cannot contest. One move both protects you and denies them.

- **When:** Rounds 1-2 on layouts with a dominant central ruin or dense area between the armies, when you can get there first (moving first, scouts/infiltrators, fast units), especially against short-range or melee armies that need that cover to approach.
- **Units:** INFANTRY/BEASTS/SWARM (gain Hidden), durable bricks, scouts and infiltrators.
- **Move type:** Normal / Advance (adjacent pre-battle variant: Scout move 24.32, Infiltrators deployment)
- **11e rules (corrected):** 13.09 Hidden, first bullet amended to ‘one or more light/dense terrain features’ (40k_11th_edition_errata_faq_commentary.md:529; the launch text 40k_11th_edition_core_rules.txt:2292-2303 says dense only); 13.10 obscuring, excluding areas either model is within (:2305-2311); 13.11 Solid (:2313-2317); 13.06 dense traversal (:2163-2183); 09.05 end unengaged (:1390-1397); 03.04 (:542-552). Corrected: the raw candidates cited the dense-only launch text.
- **AI today (none):** No terrain-target candidates: objective scoring has no terrain value (B05/B06); the cover nudge only angles an objective trip 15-30° until any terrain polygon lies between the endpoint and enemy centroids (AIDecisionMaker.gd:14745-14749, :14817-14877); Hidden-seeking (_position_would_be_hidden :28515) ships with WEIGHT_HIDDEN_GAINED 0.0 (:2633). Deployment values terrain roles (_score_terrain_for_role, B59 :5055-5797) but movement never reuses it, and scouts only target objectives (B48, :5831-6240).
- **Engine support:** TerrainManager.area_at / pieces_model_within / build_area_group_map / category_of (TerrainManager.gd:792-950), is_model_hidden (:1001-1046, already applying the light/dense errata in the working tree), is_obscured_between (:976), model_visible_11e (:1201-1246), LineOfSightManager.calculate_los_to_position (LineOfSightManager.gd:101); reuse _score_terrain_for_role from deployment. New: identify contested staging areas (terrain areas between the armies that hide units from most enemy shooters and that both sides can reach next turn) and offer them as move candidates scored for self-protection plus denial.
- **Value (high):** F005: the default 11e opening, and both the user's 'move into cover' and a denial play; the AI has no terrain destinations at all today.
- **Evidence:**
  - YouTube -Bh3n-_Tpfs @61:00 (40K Fireside): “move block your opponent from touching the middle ruin and staging your army behind it” [F005]
  - YouTube 6Lgr1hUGsgw @14:00 (Master Crafted): “we're behind it, we're hidden, they can't see us, but at least we know that we're taking up the space” [F005]
  - YouTube 1SRkN4Drhs4 @18:00 (Play On Tabletop): “my jumpack intercessors will move to stage behind this terrain ... I just don't want to be shot” [F005]
  - research/youtube/ai_learnings.json F005 detail: “putting bodies against it denies the opponent the same protection, so the move is simultaneously defensive and a denial play”
  - https://www.tabletopbattles.com/40k-start-competing-gw-terrain-layout-7/ (search snippet)
  - YouTube 6Lgr1hUGsgw @14:00 (Master Crafted): "we're behind it, we're hidden, they can't see us, but at least we know that we're taking up the space" (ai_learnings.json F005)
  - _…and 1 more_
- **Absorbed duplicates:** OBJ-38 (Occupy the key mid-board staging terrain first)
- **Found by:** core-rules, youtube, web, first-principles

#### DEN-07 — Move toward the enemy's screens to shoot or charge them away (user example: move toward an enemy to shoot it)

The counter-denial form of 'move toward someone to shoot them': enemy chaff that blocks your charge lanes, sits in your reserves' landing zones or walls a corridor is worth more than its points. Move shooters and chargers so they can remove it before the units that need the space act. Within a turn shooting comes before charging, so clearing a screen in the Shooting phase opens the lane for this turn's charges (a charge cannot end engaged with a non-target). Your own arrivals happen in the Movement phase, before your shooting, so landing zones must be cleared the turn before — or this turn, to open space for your Rapid Ingress at the end of the opponent's next Movement phase (they may re-screen first) — because arrivals must be more than 8″ from every enemy unit.

- **When:** A planned charge on a valuable target is blocked by chaff; you hold reserves for rounds 2-3 and every good landing spot is within 8″ of an enemy screen; or their screen protects their gunline/objective. Worth a trade down (F008), but don't spend your best melee unit on it.
- **Units:** High-volume shooters, fast chaff-killers; sequenced before the chargers/arrivals that need the space.
- **Move type:** Normal / Advance (assault weapons)
- **11e rules (verified):** 11.04 a charge cannot end engaged with a non-target (40k_11th_edition_core_rules.txt:1660-1665); 20.04 and 24.09 arrivals more than 8″ from all enemy units (:3255-3274, :3649-3661); 09.02 reserves arrive in the Move Units step (:1345-1366); 15.07 Rapid Ingress at the end of the opponent's Movement phase (:2714-2731).
- **AI today (none):** No movement candidate targets enemy screens, and the shooting target scorer has no 'blocks my charge lane or landing zone' term (its only move-blocking mention is a range-band comment, AIDecisionMaker.gd:25418-25431). Reserves placement merely avoids spots near enemies (B43, :8019-8247); charge planning (B04, :3773-3946) does not price a blocked lane.
- **Engine support:** Reuse IngressMove validation (IngressMove.gd:36-112) to count the AI's legal landing spots with and without a given enemy unit (remove it on a probe board), ChargeMove11e.after_moving_conditions (:113-133) and _compute_charge_move (AIDecisionMaker.gd:19797) to test whether a planned charge is blocked by a non-target, and the target scorer (:25866 onward). New: a per-enemy 'blocking value' (value of the charges/arrivals it prevents) shared by movement and target selection.
- **Value (high):** F008 (high confidence): screens are worth more than their points; a melee army such as the shipped Orks loses charges and landing zones to chaff without this.
- **Evidence:**
  - research/youtube/ai_learnings.json F008 (player_opinion, high): “Clearing enemy screens is worth more than the screen's points, because the screen is what stops the rest of the army from scoring or charging.”
  - YouTube VqwMdS9MuIY @62:00 (TacticalTortoise 40k): “it's absolutely worth a genailer squad to eviscerate one of those ranger squads even though it's a trade down” [F008]
  - YouTube _xKjN6N1jT0 @04:00 (40K Fireside): “you need to kill like I don't know, 10 guardsmen move blocking your big charges” [F008]
  - YouTube 7AgzQIEq3j4 @93:00 (TacticalTortoise 40k): “you can clear screening units and infiltrators ... have to run 20 possessed into ... 10 commandos” [F008]
  - YouTube D5XVd0FRgK8 @02:00 (Warpbane Tactics): “unit left alive on one wood can still hold an objective, block our movement” [F008/F010]
  - YouTube _xKjN6N1jT0 @04:00 (40K Fireside, F008): “you need to kill like I don't know, 10 guardsmen move blocking your big charges”
  - _…and 6 more_
- **Absorbed duplicates:** OFF-28 (Clear the screen that blocks your charges or landing zones); COO-10 (Clear the enemy screen with a cheaper unit first)
- **Found by:** core-rules, bucket-editor, youtube

#### DEN-01 — Screen deep-strike and Rapid Ingress landing zones with 8″ denial bubbles

Spread cheap units so no spot near your home/backfield objectives, artillery, characters and gunline is more than 8″ from one of your units: reserves arriving by an ingress move must be set up more than 8″ horizontally from ALL enemy units (Deep Strike anywhere, even inside your deployment zone; strategic reserves only within 6″ of an edge — see DEN-13). Size each unit's bubble to the real stand-off: 8″ core, 6″ against arrivals allowed closer (Dark Angels RELIC TELEPORTARIUM), 12″ around an Arae-Shrike bearer (enemy ingress cannot be set up within 12″ of it). The screen must already be complete at the END of your own Movement phase (the opponent's Rapid Ingress arrives then) and must still hold after your charges and consolidations (their normal arrivals come in their own Movement phase): move screeners before the units they screen, keep them out of charges, re-check coverage at the end of the turn. Coherency (within 2″ of one model and 9″ of every other model) caps how wide one unit can spread.

- **When:** The opponent still has units in strategic reserves (incl. Deep Strike) or repositioned units, plus CP for Rapid Ingress. Arrivals start in battle round 2 and Rapid Ingress cannot be used in round 1: if the AI moves second, its round-1 end-of-turn positions already face the opponent's round-2 arrivals; if it moves first, the first check is the end of its own round-2 Movement phase. Unarrived strategic reserves are destroyed at the end of round 3, so drop the task from round 4 unless repositioned units remain. Cap the screeners so objectives keep their OC, and skip it entirely when nothing is left in reserve.
- **Units:** Cheap multi-model infantry, fast cheap units, scouts/infiltrators, chaff (Gretchin, spore mines); an Arae-Shrike Custodes bearer as a 12″ anchor; units already holding home objectives count as coverage.
- **Move type:** Normal (Remain Stationary once in place; adjacent pre-battle variant: Scout move / Infiltrators deployment)
- **11e rules (corrected):** 20.03 strategic reserves arrive from battle round 2 and are destroyed if not arrived by the end of round 3 (40k_11th_edition_core_rules.txt:3249-3253, :3276-3283); 20.04 ingress: wholly within 6″ of an edge, more than 8″ horizontally from all enemy units, not in the opponent's DZ before round 3 (:3255-3274); 24.09 Deep Strike anywhere more than 8″, even in the opponent's DZ (:3649-3661); 15.07 RAPID INGRESS — WHEN: end of your opponent's Movement phase; not in battle round 1 (:2714-2731); 03.03 coherency 2″/9″ (:518-532). Engine: GameConstants.gd:44-50 (8.0 at 11e); StratagemManager.gd:5063-5076 matches the printed 15.07 timing, so the 'approximation of start of any opponent phase' note in 11th_edition_delta_audit.md:141 is outdated. Arae-Shrike .llm/codex_11e_wahapedia/custodes/RULES.md:164; RELIC TELEPORTARIUM space-marines/RULES.md:310 (‘more than 6″ ... (instead of more than 8″)’). Corrected: first-principles#63's 'from round 1 onward' only holds when the AI moves second.
  - _Skeptic:_ 'From round 1 onward only holds when the AI moves second' is too strong. 20.03 arrivals are 'unless otherwise stated' (:3252-3253), and first-turn ingress grants exist: Drop Pod Assault and Termite Assault (SM Datasheets_abilities.csv:61, :463); Impulsive Recon (orks/RULES.md:264); Lightning Descent (custodes/RULES.md:115); Deff from the Shadows, usable from round 1 at the end of the opponent's Movement phase (ork_abilities_audit.md:21); High King of Fenris (RULINGS.md:317). Against these, round-1 screens matter whichever seat the AI has. The rest is correct: 8″ bubbles, Rapid Ingress timing and no-round-1 rule, Deep Strike into the DZ, Arae-Shrike 12″, RELIC TELEPORTARIUM 6″. — 40k_11th_edition_core_rules.txt:3250-3274, 2714-2731, 3649-3661; space-marines/wahapedia/Datasheets_abilities.csv:61,463; orks/RULES.md:264; custodes/RULES.md:115,164
- **AI today (partial):** Pass 3 of _assign_units_to_objectives (AIDecisionMaker.gd:11438-11577) sends leftover screening candidates (_is_screening_candidate :14911-14925: non-CHARACTER, ≤100 pts and OC≤2, or ≤150 pts with no ranged weapons) to denial points, only while an enemy unit is IN_RESERVES (:11440-11441). _calculate_denial_positions (:14929-15026) offers 0.75R toward the board centre from each home objective (:14953) plus DZ-only backfield gaps judged on unit centroids (:14979-15022); R = 8″, shortened only by ability text on enemy reserve units (:28452-28481 — a detachment stratagem such as RELIC TELEPORTARIUM is missed); spacing 2R (:28484); score 8.0+priority−0.3/inch; execution moves the unit as it stands (:7274-7304). Missing: artillery/characters outside home objectives, an own Arae-Shrike 12″ radius (the Arae-Shrike code at :8303-8309 only filters the AI's OWN arrivals — this also covers factions#39 part e), any check at the end of the AI's Movement phase or after its charges, a screens-first move order (B03, :7119-7147), and round gating by seat and the round-3 deadline.
- **Engine support:** Reuse _calculate_denial_positions (AIDecisionMaker.gd:14929), _deep_strike_denial_radius_px (:28452), _screen_spacing_px (:28484), _get_enemy_reserves (:14884, has reserve_type), _get_deployment_zone_polygon_pixels (:24856), GameConstants.reinforcement_min_enemy_distance_inches (GameConstants.gd:49) and IngressMove validation (scripts/rules/movetypes/IngressMove.gd:36-112). New: a 'legal landing area remaining' query (sample points, edge-to-edge distance to the PLANNED model positions) evaluated after the planned moves; a per-unit denial radius (Arae-Shrike via CustodesEnhancements.key_in_group as at :8306-8307); stratagem-aware arrival distances; a screeners-first move-order class (.llm/ai-overhaul-todo.md C6).
- **Value (high):** 11e cut the stand-off to 8″ and players say deep strikes matter more (F007 confirmed/high, 4 channels; F029); an unscreened home objective or gunline hands the opponent a free steal or kill. The AI already has the skeleton, so better geometry and timing is cheap.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:3249-3283, :3649-3661, :2714-2731
  - 40k/scripts/rules/GameConstants.gd:44-50
  - 40k/scripts/AIDecisionMaker.gd:14929-15026 (_calculate_denial_positions), :28452-28485 (_deep_strike_denial_radius_px, _screen_spacing_px)
  - .llm/codex_11e_wahapedia/custodes/RULES.md:164 (Arae-Shrike); .llm/codex_11e_wahapedia/space-marines/RULES.md:310 (RELIC TELEPORTARIUM)
  - YouTube SyVxk7EW_tI @132:00 (Tactical Sugar): “it's so much harder screen out now in 11th and deep strikes are so much more important in 11th” [F007]
  - YouTube uYFHWwWSklU @87:00 (Odyssey40k): “there's a 6-in deep strike in retaliation ... you have to screen really aggressively for it” [F007]
  - _…and 7 more_
- **Absorbed duplicates:** DEN-13 (Deny strategic-reserve board-edge arrivals (cover the 6″ edge bands))
- **Found by:** core-rules, youtube, web, first-principles, factions, missions

#### DEN-02 — Charge-screen a valuable unit (bubble-wrap it, with depth)

Place a cheap unit across the approaches to a valuable friendly unit (gunline, artillery, character, objective holder) so that any charge ending engaged with it would also end within 2″ of the screen. An 11e charge must end engaged with every charge target and with no other enemy unit, and charge moves cannot pass through models (17.01's MONSTER/VEHICLE pass-through covers only normal and advance moves), so the charger must also declare the screen (within 12″ and within its roll) and engage both with one roll, go around, or fail. FLY chargers can take to the skies over the screen but still need a landing spot engaged with the target and more than 2″ from the screen, so a tight wrap still works. Leave depth: if the screen dies, an enemy unit that has not fought can make an overrun fight (one extra 3″ pile-in toward enemy units within 5″) and units that fought must consolidate 3″ toward any enemy within 3″, so keep the protected unit roughly 5″+ behind where the chargers will stand (derived).

- **When:** An unengaged enemy melee unit can reach a valuable friendly unit next turn (its M + up to 12″) and a cheap unit can stand in that lane; move the screen before the unit it protects.
- **Units:** Screens: cheap infantry, chaff, vehicle hulls. Protected: gunlines, artillery, characters, objective holders.
- **Move type:** Normal (Remain Stationary when already in the lane)
- **11e rules (verified):** 11.04 charge move: targets within 12″ and within the roll; AFTER MOVING engaged with all charge targets and with no non-target (40k_11th_edition_core_rules.txt:1640-1665); 03.01 bases cannot move through enemy models (:385-395); 03.04 engagement range 2″ (:542-552); 17.01 pass-through only on normal/advance moves (:2867-2874); 21.03 taking to the skies includes charge moves (:3358-3375); 12.03 pile-in targets within 5″ and 12.06 overrun pile-in (:1737-1760, :1866-1877); 12.08 engaging consolidation when within 3″ (:1954-1957). Engine: ChargeMove11e.gd:106-133.
- **AI today (partial):** Screen-protect in pass 3 (AIDecisionMaker.gd:11579-11609; _compute_screen_position :15028-15086): a leftover cheap unit goes 60% of the way from the most valuable nearby friendly (unattached CHARACTER +50, attached +10, points×0.01, 1000/distance) toward the NEAREST enemy centroid, flat score SCREEN_SCORE_BASE 8.0 (:2676). It never checks that an enemy melee unit can actually reach the protected unit, which lane the charge would use, the depth needed against overrun/consolidation, or that every approach is covered; it protects one unit, uses only units left over after objectives, and moves screens in board order rather than first (:7119-7147).
- **Engine support:** Reuse _calculate_enemy_threat_data / _evaluate_position_threat (AIDecisionMaker.gd:28695, :28794) for enemy charge reach (note it adds +2″ ER although 11.04 caps targets at the roll — ChargeMove11e.selectable_distance_ceiling :106-107), _compute_screen_position (:15028), _screen_max_model_spacing_px / _screen_widest_passable_gap_inches (:28380, :28388), and ChargeMove11e.after_moving_conditions (:113-133) on a probe board to test 'can a charge engage the protected unit without engaging the screen'. New: a per (enemy melee unit, protected unit) charge-lane probe and a wrap/arc formation placer (the placement ladder at :14520-14722 optimises legality only).
- **Value (high):** F006 (confirmed, high) and F008 (high): a cheap screen in front of a gunline or character routinely decides games, and 11.04's no-non-target rule makes screens strong in 11e; the AI's version is a single point with no lane logic.
- **Evidence:**
  - 40k/scripts/rules/movetypes/ChargeMove11e.gd:113-133 (after_moving_conditions)
  - 40k/scripts/AIDecisionMaker.gd:28362-28363 (screens “still block charges onto a protected unit”)
  - YouTube _xKjN6N1jT0 @04:00 (40K Fireside): “you need to kill like I don't know, 10 guardsmen move blocking your big charges” [F008]
  - YouTube VPTL092E0VI @13:00 (Grimdark Breakdown): “The amount of times that I have tried to screen and there's a tiny hole” [F006]
  - research/youtube/ai_learnings.json F006 detail: “a model that squeezes through kills the screen and then consolidates into whatever was behind it”
  - https://grimhammertactics.com/40k-tactics-mastering-movement-in-warhammer-40k/ and https://www.goonhammer.com/start-competing-how-to-screen-everything (search snippets; pre-11e)
- **Found by:** core-rules, youtube, web, first-principles

#### DEN-03 — Move toward a dangerous enemy shooter or action unit to charge and lock it (user example: move toward an enemy to charge it)

The denial form of 'move toward someone to charge them': pick the enemy unit whose shooting or next action matters most and move into charge reach, planning to engage and stay engaged. An engaged non-MONSTER/VEHICLE unit cannot make normal shooting (only close-quarters shooting with [CLOSE-QUARTERS] weapons at units it is engaged with), cannot start an action, and if it falls back it cannot shoot, charge or start an action that turn. Against MONSTER/VEHICLE targets the lock is weaker: they may still close-quarters shoot (at -1 to hit unless a [CLOSE-QUARTERS] weapon targets a unit they are engaged with) and your other units can shoot them at -1; a locked transport still cannot make a normal move. The charger need not win the fight — the value is the enemy's lost shooting/action.

- **When:** An enemy unit with high ranged output, or one that would start a scoring action next turn, is within the melee unit's M + likely charge roll (the target must be within 12″ and within the roll); the charger can survive the return fight; best against non-M/V shooters. Do not Advance unless the unit may still charge after advancing.
- **Units:** Melee units, fast melee, durable or cheap tarpit units.
- **Move type:** Normal / Advance (Advance only with an advance-and-charge ability)
- **11e rules (corrected):** 10.04 normal shooting needs the unit unengaged (40k_11th_edition_core_rules.txt:1489-1494); 10.06 close-quarters shooting (:1522-1545); 17.03 shooting engaged M/V at -1 (:2896-2910; [BLAST] excluded by errata, 40k_11th_edition_errata_faq_commentary.md:608); 16.01 an engaged unit cannot start an action (:2806-2817); 09.07 after a fall-back: no shooting, charge or action (:1417-1440); 11.02 charge eligibility within 12″, not after advance/fall back (:1597-1623); 09.06 (:1399-1411). Corrected: F015's vehicle examples overstate the 11e lock (engaged M/V can still shoot at -1).
- **AI today (partial):** The phase plan marks enemies with estimated ranged output ≥ PHASE_PLAN_RANGED_STRENGTH_DANGEROUS as lock_targets (AIDecisionMaker.gd:3789-3805) and adds PHASE_PLAN_LOCK_SHOOTER_BONUS + 0.3×ranged strength to charge_intent (:3857-3862) and to the charge-target score (:19198-19212). In the Movement phase that only steers a unit's objective trip 30/50/70% toward its charge-intent target (B26, :7491-7548); melee seekers converted to ATTACK chase the NEAREST enemy (_melee_chase_gate → _get_nearest_enemy_for_charge, :2951, :3114). No lock value for enemy action units, no M/V vs non-M/V distinction, no check that the charger survives to keep the lock.
- **Engine support:** Reuse _estimate_unit_ranged_strength (AIDecisionMaker.gd:25866), _estimate_melee_damage (:19576), _estimate_incoming_melee_damage (:12350), the charge-intent plan (:3773-3946), _prob_sum_d6_at_least (:12788) with ChargeMove11e.selectable_distance_ceiling (ChargeMove11e.gd:106-107) for charge odds, and ActionsManager.can_start_action (ActionsManager.gd:60) / MissionManager.get_card_action_summary_11e (MissionManager.gd:2197) to find units that would act next turn. New: let the chase gate target the lock target / charge intent instead of the nearest enemy, and scale the lock value by target keyword (non-M/V much higher than M/V).
- **Value (high):** F015 (confirmed): switching off an expensive gun for a turn with a cheap charge is a standard play, and in 11e engaged non-M/V units lose normal shooting and actions; the AI already computes lock targets, so wiring them into melee movement is a small change.
- **Evidence:**
  - research/youtube/ai_learnings.json F015 (confirmed, medium): “Charging purely to tie up a dangerous shooter is worth doing even when the charging unit expects to deal and receive negligible damage.”
  - YouTube MkeH0tr1o_o @57:00 (WednesdayNightWarhammer): “I guess I would attempt the charge to get just to tie you up” [F015]
  - YouTube HER6VzUGO60 @658:00 (WarGames Live): “We'll charge the truck in just to lock you in because we can still touch you and still be on the objective” [F015]
  - YouTube lp4j3iYlpQ4 @25:00 (Mordian Glory): “I charged up to the hell hound just to tie them up again” [F015]
  - 40k/scripts/AIDecisionMaker.gd:3789-3810 (lock_targets), :3857-3862 (charge-intent lock bonus), :19198-19212 (charge-target lock bonus)
  - YouTube MkeH0tr1o_o @57:00 (WednesdayNightWarhammer, F015): “I guess I would attempt the charge to get just to tie you up”
  - _…and 7 more_
- **Absorbed duplicates:** OFF-08 (Tie up a dangerous shooter); OFF-21 (Lock the enemy's action or objective unit in melee)
- **Found by:** first-principles, core-rules, youtube, web, missions

#### DEN-04 — Move-block the enemy's approach corridors and the routes to your objectives

Stand blockers across the lanes enemy units must use — gaps between terrain pieces, the approach to an objective you hold or need next Command phase or at the end of the enemy turn — forward of the objective, so walkers detour or stop short: normal and advance moves cannot cross enemy bases and must end more than 2″ from your models (they may pass through your engagement range mid-move). Treat cheap units as consumables: the value is the movement tax. Use MONSTER/VEHICLE hulls as the wall against enemy MONSTER/VEHICLE movers: 17.01 lets M/V models move through non-M/V models on normal/advance moves but not through other M/V, so by the rules infantry blocks do not stop them, nor FLY units that take to the skies (-2″), nor SUPER-HEAVY WALKERs. Engine today: plain M/V movers are blocked by any enemy base, and FLY units cross enemy bases on every normal/advance move without declaring take to the skies.

- **When:** An objective you must still hold (next Command phase or end of the enemy turn) or your backline is reachable by enemy OC or melee units next turn through predictable gaps; cap the number of blockers so objectives keep OC, and stop spending them once the army is thin.
- **Units:** Cheap multi-model infantry, chaff (spore mines, Gretchin, cheap broods), vehicles as walls.
- **Move type:** Normal
- **11e rules (verified):** 03.01 a base can pass any gap it fits but cannot be moved through enemy models (40k_11th_edition_core_rules.txt:385-395); 09.05 AFTER MOVING unengaged (:1390-1397); FAQ 03.04: moving through an enemy's engagement range does not engage (40k_11th_edition_errata_faq_commentary.md:265); 17.01 (:2867-2874); 21.03 (:3358-3375); 24.35 (:3940-3966); 14.02 control is checked at the end of each phase and turn (:2401-2418; errata doc :557).
- **AI today (partial):** Corridor blocking (T7-42) in pass 3 (AIDecisionMaker.gd:11611-11649; _calculate_corridor_blocking_positions :15092-15182): for each objective not enemy_strong and each enemy centroid 6″-30″ from it, a point 55% of the way from the enemy to the objective (CORRIDOR_BLOCK_POSITION_RATIO :2682), priority = state base (held_threatened 6 ... enemy_weak 2, home +2) + proximity + enemy threat, max 4 points 5″ apart, score 7.0+priority−0.3/inch, leftover cheap units only (after denial and screen-protect). Straight lines only — no terrain chokepoints, no check whether the enemy is FLY, M/V or SUPER-HEAVY WALKER, no line formation (DEN-05). The SCREEN plan verb only withholds a unit from the objective passes (AIDecisionMaker.gd:1362-1369; docs/PLAN_FORMAT.md:528).
- **Engine support:** Reuse _calculate_corridor_blocking_positions (AIDecisionMaker.gd:15092), _compute_movement_toward_target (:14212), TerrainManager.features_crossing (TerrainManager.gd:857) and can_move_through_11e (:1249) to locate chokepoints, and the MovementPhase._path_crosses_enemy_bases logic (:7422) for pass/no-pass. New: an enemy reachable-area flood fill (enemy M through gaps its base fits, honouring 17.01 / 21.03 / 24.35) so a block is scored by how much enemy OC it keeps off the objective.
- **Value (high):** F031/F008: move-blocking keeps enemy OC off objectives and protects scoring units; because 11e lets movers pass through engagement range only physical walls work, and the AI's block is a single unaimed point.
- **Evidence:**
  - 40k/phases/MovementPhase.gd:7080-7094 (destination-only engagement check), :7422-7475 (base-overlap crossing), :756-761 (non-FLY normal/advance only; no 17.01 exemption)
  - 40k/scripts/AIDecisionMaker.gd:15092-15182 (_calculate_corridor_blocking_positions), :28344-28363 (SCREEN GAP GEOMETRY)
  - YouTube VPTL092E0VI @13:00 (Grimdark Breakdown): “you could put things in their way to block their easy path” [F031]
  - YouTube K8OD14Mz6N4 @09:00 (Into the Hive Mind): “putting these spore mines out that screen out deep strikers or any kind of reserve” [F031]
  - YouTube sPWC5HujB_Y @19:00 (StrikingScorpion82): “holding objectives, picking on isolated, tying units down, blocking movements ... it's no big deal if they're slain” [F031]
  - research/youtube/profiles/tyranids.json (CORRIDOR_BLOCK_SCORE_BASE 9.0, CORRIDOR_BLOCK_MAX_POSITIONS 6)
  - _…and 1 more_
- **Found by:** core-rules, missions, web, first-principles, youtube

#### DEN-09 — Spoil the opponent's presence- or majority-based scoring zones

Plant a unit (one model counts) where the opponent's card needs emptiness, or a majority, at its check: (a) Centre Ground — any of your units within 6″ of the centre blocks their 5VP tier and within 3″ blocks both; checked at the end of THEIR turn, so the unit must survive it. (b) Defend Stronghold bonus — one of your units within their DZ at the end of YOUR turn strips their +2VP (the engine needs it wholly within). (c) Vanguard Operation — their action completes at the end of their turn only if none of your units is within that terrain area (an area in your territory), so pre-occupy the areas in your half they can reach. (d) Extract Relic / Locate and Deny — the last-marker condition needs no enemy unit in that terrain area. (e) Search and Scour — their end-of-battle 5VP needs none of your units wholly within their territory (engine: their DZ). (f) Display of Might — their 5VP tier at the end of YOUR turn needs strictly more of their units than yours wholly in No Man's Land (excluding AIRCRAFT and battle-shocked units), so step extra cheap units wholly into NML or kill/shock theirs.

- **When:** The opponent's revealed cards include one of these and the check falls in a round where it scores; prefer durable, Hidden or Lone Operative units when the check is at the end of their turn.
- **Units:** Cheap units; durable/Hidden/Lone Operative units; fast or deep-striking units for their DZ.
- **Move type:** Normal / Advance / Reserves arrival (Deep Strike into their DZ)
- **11e rules (verified):** 40k/data/40kdc/missionCards.json centre-ground :2311, defend-stronghold :2706, vanguard-operation :1597, extract-relic :1286, locate-and-deny :983, search-and-scour :2005, display-of-might :2246. Engine checks: SecondaryMissionManager.gd:1116-1154 (any enemy model within range blocks), :1156-1163 (strictly more units wholly in NML), :1826-1840 (Defend Stronghold: no enemy unit WHOLLY within, while the card text says within); MissionManager.gd:2084-2095 (Vanguard), :3240-3250 (final relic marker), :3255-3268 (territory approximated by the DZ); 24.09 Deep Strike may land in the opponent's DZ (40k_11th_edition_core_rules.txt:3649-3661).
- **AI today (none):** The AI never reads the opponent's cards (AIDecisionMaker.gd:22822 own primary only; get_active_missions(player) own only, e.g. :24056). Its own Display of Might / Centre Ground / Behind Enemy Lines handling (:24087-24091, :24198-24203, :10388-10411) chases its own VP and overlaps with denial only by accident.
- **Engine support:** SecondaryMissionManager.get_active_missions(opponent) (:2638) plus the engine's own scoring checkers run on a probe board with the planned destination: _check_area_denial (:1116), _check_display_of_might (:1156), _check_no_enemy_wholly_in_own_dz (:1826), MissionManager._player_model_in_terrain_11e and _enemy_wholly_in_my_dz_11e (:3255); _get_deployment_zone_polygon_pixels (AIDecisionMaker.gd:24856). New: an 'opponent VP at their next check' estimator per candidate destination.
- **Value (medium):** One model in the right zone denies 2-5 VP per card, but only when those cards are in play, and it needs opponent-card reading first.
- **Evidence:**
  - 40k/data/40kdc/missionCards.json:2311 (Centre Ground: no enemy units within 3 inches for the lower tier, within 6 inches for the higher tier)
  - 40k/data/40kdc/missionCards.json:1597 (Vanguard Operation: “completes at end of turn if no enemy units are within that terrain area”)
  - 40k/data/40kdc/missionCards.json:2246 (Display of Might: “the larger one at the end of the opponent's turn, while more friendly units than enemy units ... are wholly within No Man's Land”)
  - 40k/autoloads/SecondaryMissionManager.gd:1116-1163, :1826-1840; 40k/autoloads/MissionManager.gd:2084-2095, :3240-3268
  - 40k/scripts/AIDecisionMaker.gd:22822, :24056 (no code reads the opponent's cards)
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:1597, :2246, :2311, :2706, :1757
  - _…and 3 more_
- **Absorbed duplicates:** MIS-11 (Deny the opponent's mission scoring with your own moves)
- **Found by:** missions, first-principles, youtube, core-rules

#### DEN-10 — Don't end moves inside enemy 'ends a move within X″' triggers (reactive moves, snared objectives)

Many 11e faction rules fire in your Movement phase when one of your units ENDS a move near theirs: RESPONSIVE TACTICS (Space Marines, D6″), MASTERFUL TACTICS and TRANSHUMAN REACTIONS (D6″, or 6″ with the tactical doctrine), PRACTICAL TACTICS and SWIFT AS THE EAGLE (D3+3″), SCARPER! and WHIRLIGIG EVASION (Orks, D6″ or 6″), Predatory Instinct (Space Wolves, D6″, once per battle round) — all on an enemy ending within 8″, measured edge to edge; MORTIS SNARES hits the first unit that ends a move within range of the snared objective with D6 mortal wounds on a 2+. Unless the reaction helps you, end just outside the trigger (more than 8″) so their unit stays put for your shooting and charges, or Remain Stationary — a unit that remains stationary never triggers start/end-of-move rules. Discount long charges and precise blocks against units that can jump away.

- **When:** An enemy unit with such a rule (and the CP or use left) is near your planned destination and its dodge would cost you a charge target, a shooting target, an objective or a block; or a valuable unit would end on a snared objective.
- **Units:** All units; especially chargers, shooters that need a fixed target, valuable objective-takers.
- **Move type:** Normal / Advance (or Remain Stationary instead)
- **11e rules (corrected):** 09.04 remain stationary triggers no start/end-of-move rules (40k_11th_edition_core_rules.txt:1378-1388); trigger texts .llm/codex_11e_wahapedia/space-marines/RULES.md:259 (RESPONSIVE TACTICS), :647 (TRANSHUMAN REACTIONS), :714 (MASTERFUL TACTICS), :625 (MORTIS SNARES), custodes/RULES.md:156 (SWIFT AS THE EAGLE), orks/RULES.md:223 (SCARPER!), :268 (WHIRLIGIG EVASION); PRACTICAL TACTICS in space-marines/wahapedia/Stratagems.csv (D3+3″); predatory_instinct at 40k/scripts/codex/space_wolves/SWAbilities11e.gd:1262; RULINGS.md:396, :482 (8″ edge to edge), :402 (any settled move in any phase triggers a snare); 15.01 once per phase (:2495-2500).
  - _Errata check:_ Under Commentary 01.02.02, a stratagem effect with no stated duration lasts only for its trigger period. An opponent's MORTIS SNARES (used at the end of their Movement phase) has therefore lapsed before your Movement phase, so drop 'avoid ending on a snared objective' from your own moves; only a move ending in range during that same end step (e.g. your own Rapid Ingress arrival) could trigger it. The reactive-move stratagem parts stand. — Commentary 01.02.02 Persisting Rules Effects (errata doc :28)
- **AI today (none):** The threat model is enemy M+12″+ER charge reach and weapon range only (_calculate_enemy_threat_data, AIDecisionMaker.gd:28695-28720), with no reactive or snare term; the only hit for these stratagem names in AIDecisionMaker.gd is the SWIFT AS THE EAGLE decline at :16397-16416, and MORTIS has none.
- **Engine support:** 40k/data/40kdc/abilities.json triggers (event enemy-unit-ended-move, proximity range) and the codex stratagem tables to list enemy reactive units; the engine's enemy_ended_move window (StratagemManager.gd:118); snare state state.factions[p].sm11e_snared_objectives (RULINGS.md:402); enemy CP from snapshot.players; edge-to-edge distance from Measurement. New: an 'enemy reaction exposure' term in _evaluate_position_threat (AIDecisionMaker.gd:28794) and destination scoring, with Remain Stationary as the zero-exposure option.
- **Value (medium):** F014 (confirmed, 4 channels) and the shipped Space Marine, Custodes, Ork and Space Wolf codices are full of 8″ reactive moves; ignoring them costs charges and blocks, though each is a once-per-phase 1CP effect.
- **Evidence:**
  - 40k/scripts/rules/movetypes/RemainStationaryMove.gd:4-5
  - YouTube ycW5l0xHp9s @08:00 (PNW 40K): “He can make a reactive move ... reactive moves in general are very powerful” [F014]
  - YouTube Wm2Hd8h74_o @65:00 (HivemindHobbies): “if he moves up at all, then they will automatically reactive move behind this obscuring wall” [F014]
  - YouTube VqwMdS9MuIY @60:00 (TacticalTortoise 40k): “it has the ability to reactive move to enemies going close to it ... it may be able to jump away” [F014]
  - research/youtube/ai_learnings.json F014 detail: “they decline moves that would trigger a reactive escape”
  - 40k/data/40kdc/abilities.json reactive-evasion-fulguris-task-force (trigger enemy-unit-ended-move, proximity 8, D3+3; pre-launch-provisional)
  - _…and 4 more_
- **Absorbed duplicates:** COO-21 (Stay outside enemy ability trigger radii)
- **Found by:** youtube, web, factions, first-principles, core-rules

#### DEN-12 — Hunt the enemy units that score from your half before the check

You cannot move enemy units, so some denial needs them dead: your Search and Scour pays 5VP at the end of the battle only if no enemy units are wholly within your territory (engine: your DZ); your Defend Stronghold +2VP needs no enemy in your DZ at the end of their turn; their Behind Enemy Lines (units wholly in your DZ) and Outflank (units within 6″ of an edge and outside their own territory) score at the end of their turn; their Beacon pays at the end of YOUR turn while their beacon unit is alive outside their DZ. Move shooters and chargers back or across to kill the infiltrators, deep strikers and raiders standing there — engaging them is not enough.

- **When:** Those cards are active and enemy units stand in the scoring position; for Search and Scour start clearing by rounds 3-4, since the check is at the end of the battle.
- **Units:** Home-guard killers, fast units that can turn back, deep strikers.
- **Move type:** Normal / Advance
- **11e rules (verified):** 40k/data/40kdc/missionCards.json search-and-scour :2005, defend-stronghold :2706, behind-enemy-lines :2679, outflank :2339, beacon :2826; MissionManager.gd:3255-3268 (_enemy_wholly_in_my_dz_11e: territory approximated by the DZ).
- **AI today (none):** 'search-and-scour' has no references in AIDecisionMaker.gd; no code looks for enemy units inside the AI's own DZ or territory (grep), and neither movement nor the shooting target scorer has a card-based value for raiders, flankers or the enemy Beacon.
- **Engine support:** MissionManager._enemy_wholly_in_my_dz_11e (MissionManager.gd:3255), SecondaryMissionManager.get_active_missions(opponent) (:2638), the shooting target scorer (AIDecisionMaker.gd:25866 onward) and _compute_movement_toward_target (:14212). New: a 'VP denied by killing this unit' value per enemy unit used by both movement and target selection.
- **Value (medium):** Swings up to 5VP at the end of the battle and 2-5VP per turn on common cards, but only with those cards in play.
- **Evidence:**
  - 40k/data/40kdc/missionCards.json:2005 (Search and Scour: “End of battle pays out if no enemy units are wholly within your territory”)
  - 40k/data/40kdc/missionCards.json:2826 (Beacon: scored at the end of your opponent's turn while the beacon unit is on the battlefield outside your deployment zone/territory)
  - 40k/autoloads/MissionManager.gd:3255-3268
  - 40k/scripts/data/PrimaryMissionData11e.gd:260-274 (cited by the missions stream; not re-read)
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2706, :2005
  - /home/user/warhammer-40k-godot/docs/rules/11th_edition_missions_gdm2026.md:145-147
  - _…and 1 more_
- **Absorbed duplicates:** MIS-37 (Kill enemy units that sit inside your deployment zone or territory)
- **Found by:** missions, web

#### DEN-16 — Deny the opponent's kill-based scoring (don't offer their paying targets)

Pull back, hide or swap out the units that would pay the opponent's kill cards this round: models with W 10+ (Bring It Down), units with a Starting Strength of 13+ (A Grievous Blow), CHARACTER models (Assassination, more for W4+), any unit that starts their turn within range of an objective (Overwhelming Force; Purge and Secure; Locate and Deny / Extract Relic kills), and under out-kill or per-kill primaries (Meatgrinder, Destroyer's Wrath, Delaying Action) or No Prisoners any unit you cannot afford to lose. When they hold Overwhelming Force, end your turn with sturdy units, not fragile ones, on objectives.

- **When:** The opponent's revealed cards pay for kills of that type and the unit would be exposed at its end position.
- **Units:** Big models, hordes, characters, fragile objective sitters.
- **Move type:** Normal / Remain Stationary / Fall Back
- **11e rules (verified):** 40k/data/40kdc/missionCards.json bring-it-down :2537, a-grievous-blow :2785, assassination :2272, overwhelming-force :2578, purge-and-secure :232, meatgrinder :474, destroyers-wrath :560, delaying-action :916, no-prisoners :2516, locate-and-deny :983, extract-relic :1286.
- **AI today (none):** Card-blind: the generic threat dodge (B35, AIDecisionMaker.gd:28695-28890; CHARACTER ×1.5, fragile ×1.3) avoids danger regardless of which units pay the opponent, and the opponent's cards are never read (:22822, :24056).
- **Engine support:** SecondaryMissionManager.get_active_missions(opponent) (SecondaryMissionManager.gd:2638); weight _evaluate_position_threat (AIDecisionMaker.gd:28794) by 'VP the opponent gains if this unit dies', from unit meta (W, starting strength, keywords) and objective range at the end of the turn (MissionManager.model_in_objective_range, MissionManager.gd:545).
- **Value (medium):** Kill cards are among the most common secondaries (F028), and the fix is a weighting on threat avoidance the AI already has.
- **Evidence:**
  - 40k/data/40kdc/missionCards.json:2578 (Overwhelming Force: “Score per enemy unit that started the turn within range of one or more objectives and was destroyed”)
  - YouTube Krfpc2el0cA @25:00 (Tabletop Titans): “Overwhelming is good. This is kill things on objectives. It's what I want to do ... you really want to try to get two kills” [F028]
  - YouTube VvZD_rjUBjE @19:00 (MiniWarGaming): “Kill things on the critical objectives with overwhelming force” [F028]
  - 40k/data/40kdc/missionCards.json:2272, :2516, :2537, :2578, :2785, :232, :474, :560, :767, :2005
  - docs/rules/11th_edition_missions_gdm2026.md:45-53
  - https://warhammerguild.com/guides/40k-11th-edition-missions-explained/ (fixed cards include Assassination, Bring It Down, A Grievous Blow)
  - _…and 7 more_
- **Absorbed duplicates:** SUR-10 (Hide the units the enemy's kill cards pay for); OBJ-23 (Keep fragile units off objectives and terrain areas the opponent is paid to kill them on); OBJ-24 (Pull a doomed unit out of reach to deny the opponent's kill VP)
- **Found by:** first-principles, missions, web, youtube, core-rules

#### DEN-18 — Zone ground with your threat ranges (counter-punch posture)

Park melee and shooting threats at the edge of your own reach but outside the enemy's, so any enemy unit that steps onto a given objective or lane would end inside your charge reach (within 12″ and within your likely 2D6) or your kill zone next turn. This deters the move without blocking it ('castle and counter-punch'); combine it with a bait (DEN-31) or a screen.

- **When:** Your threat range exceeds the enemy's, or you cannot hold the objective with bodies but can punish whoever steps onto it; mid-game, when ahead or when the enemy must come to you.
- **Units:** Fast melee counter-punchers, long-range shooters, durable elite armies.
- **Move type:** Normal / Remain Stationary
- **11e rules (verified):** 11.02 a charge needs an enemy within 12″ and is barred after advancing or falling back (40k_11th_edition_core_rules.txt:1597-1623); 11.04 targets within 12″ and within the roll (:1640-1647; ChargeMove11e.gd:89-107); 09.06 advanced units cannot charge (:1399-1411).
- **AI today (none):** Only ENEMY reach is modelled, for avoidance (B35, AIDecisionMaker.gd:28695-28890); there is no own-threat projection term in objective or destination scoring, and the threat-aware hold (B21, :7357-7390) only keeps pure ranged units still.
- **Engine support:** Mirror _calculate_enemy_threat_data (AIDecisionMaker.gd:28695) for friendly units; _prob_sum_d6_at_least (:12788) for charge odds; RulesEngine.max_ranged_weapon_range_inches / unit_within_weapon_reach (RulesEngine.gd:6693, :6718). New: a friendly threat map and an 'enemy cost to enter' score per objective and lane.
- **Value (medium):** A core competitive skill that makes the opponent's objective grabs expensive; it reuses the existing threat-map code, mirrored.
- **Evidence:**
  - 40k/scripts/rules/movetypes/ChargeMove11e.gd:89-107 (selectable_distance_ceiling = min(12, roll))
  - research/ai_feasibility_2026-08-09.md:297 (persona “Custodes castle and counter-punch”)
  - .llm/ai-overhaul-todo.md:1059-1062 (“castle center”, “refuse left flank”)
  - research/youtube/ai_learnings.json disagreements[0] note: “the resolving variable is the opponent's turn-one threat range, which the AI can compute”
  - Wellspokenman 'Deployment - interlocking fields of fire and avenues of approach' https://wellspokenman.wordpress.com/2016/10/28/deployment-interlocking-fields-of-fire-and-avenues-of-approach/ (edition-agnostic)
  - Raptors Chapter Guide https://www.thegametown.com/blogs/news/raptors-chapter-guide (crossfire; edition unconfirmed)
  - _…and 1 more_
- **Absorbed duplicates:** COO-30 (Build a kill zone over an objective or approach lane)
- **Found by:** youtube, first-principles, web

#### DEN-19 — Fill a small terrain-objective area so enemy models can't end in it

A model is in range of a terrain objective only while it is within that terrain area, and enemy normal/advance moves must end more than 2″ from your models and cannot pass through them. Spread a many-model unit across a small objective area so every spot in it is within 2″ of one of your models, and seal the entrances (DEN-05): enemy walkers then cannot end in range and add OC. It does not stop charges (chargers end engaged with your models inside the area and their OC counts) or units already inside; FLY and M/V movers can pass through but still cannot end within 2″.

- **When:** Small terrain objectives you hold, with a unit that has enough models to cover the area inside coherency (each model within 9″ of every other).
- **Units:** Large infantry units.
- **Move type:** Normal
- **11e rules (corrected):** 14.01-14.02: within range of a terrain objective = within the terrain area (40k_11th_edition_core_rules.txt:2389-2410); 09.05 (:1390-1397); 03.01 (:385-395); 03.03 9″ envelope (:518-532); 11.04 charges end engaged (:1640-1665).
  - _Errata check:_ Per the FAQ, models on upper levels of terrain features inside the area's boundary (and overhanging FRAME parts) are within the terrain area and so in range, but engagement range reaches only 5″ vertically. A ground-level fill therefore does not stop enemy INFANTRY (or other models allowed to end on upper surfaces, 13.06) from ending more than 5″ above your models, e.g. on a ruin's second floor; also occupy those levels, or rely on the fill only for low, single-level areas. — FAQ 14.01 Terrain Objectives (same FAQ under 13.01 Placing Terrain and 17.02 Frame; errata doc :511, :543, :603)
- **AI today (none):** Holding means REMAIN_STATIONARY (B19, AIDecisionMaker.gd:7187-7200; B20 :7314-7355); there is no reposition inside the objective area, no spread to occupy it, and no area-coverage test.
- **Engine support:** MissionManager.model_in_objective_range / model_gap_to_objective_range_px (MissionManager.gd:529-569), TerrainManager.area_at (TerrainManager.gd:792-950), the placement ladder (AIDecisionMaker.gd:14520-14722). New: an area-coverage placer (models packed so the area is within 2″ of a model, in coherency) plus a check that no legal enemy end spot remains in range.
- **Value (medium):** Terrain objectives are the 11e default and filling a small one makes walk-on contests impossible, but charges still get in and only small areas can be filled.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:2389-2410, :1390-1397, :385-395
- **Found by:** core-rules

#### DEN-20 — Use dense terrain as a moat against enemy vehicles and monsters

Hold objectives and backline spots with INFANTRY/BEASTS/SWARM inside or behind dense terrain that enemy models without INFANTRY/BEASTS/SWARM/MOBILE cannot cross horizontally where a section is over 2″ tall. By 13.06 such models must climb (the vertical distance counts toward the move) and cannot end on non-ground surfaces of that feature; in this engine the segment is simply refused, so the moat is a hard wall. SUPER-HEAVY WALKERs cross sections up to 4″ and can gamble for MOBILE; FLY units that take to the skies ignore terrain.

- **When:** Against vehicle- or monster-heavy armies; when choosing which objective or area infantry should hold; when an enemy vehicle threat must path around a ruin.
- **Units:** INFANTRY, BEASTS, SWARM (the defenders).
- **Move type:** Normal / Remain Stationary
- **11e rules (corrected):** 13.06 (40k_11th_edition_core_rules.txt:2163-2205); 24.35 (:3940-3966); 21.03 (:3358-3375); 13.06.01 commentary on Solid (40k_11th_edition_errata_faq_commentary.md:518-520). Engine: MovementPhase.gd:736-745 (_check_dense_terrain_gate refuses the segment because ‘the 2D board cannot path the mandated vertical traversal’), TerrainManager.gd:1229-1314. Corrected: first-principles#9 described a hard block; the rule is a climbing tax, the engine makes it a wall.
- **AI today (none):** Destinations are scored only for objectives and threat; terrain enters movement as path blocking (B33, AIDecisionMaker.gd:14212-14474) and the any-polygon cover nudge (B34, :14817-14877); deployment's terrain roles (B59) are not reused.
- **Engine support:** TerrainManager.can_move_through_11e (TerrainManager.gd:1249) with the enemy unit's keywords, category_of / height_inches_of, calculate_charge_terrain_penalty (:509); the enemy reachable-area query from DEN-04.
- **Value (medium):** In this engine dense terrain is a hard wall for non-infantry, so it is a cheap, strong defence against vehicle and monster armies.
- **Evidence:**
  - 40k/phases/MovementPhase.gd:736-745
  - 40k/autoloads/TerrainManager.gd:1229-1314
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-moving-and-the-movement-phase/ (search snippet: MOBILE models move through dense terrain like Infantry; vehicles cannot end on top of terrain)
- **Found by:** first-principles

#### DEN-21 — Box in an enemy transport to spoil its passengers' disembark

Ring a loaded enemy transport with models standing just outside 2″ of it (not engaged with it). Disembarking units must be set up wholly within 3″ (rapid/tactical) and unengaged: after the transport makes a normal move they must use Rapid Disembark and cannot get out if there is no legal spot; if it has not moved and Tactical is impossible they are forced into Combat Disembark (6″, a hazard roll per model, battle-shocked, no charge, and only allowed to be engaged with units the transport is engaged with). If you then destroy the transport, Emergency Disembark sets them up within 6″ as close as possible — unengaged if possible, otherwise engaged (errata) — so models die only if they still cannot be placed: the ring now mainly forces them into engagement, battle-shocked and unable to charge, rather than killing them. By the rules the transport itself can drive through non-M/V models on its normal/advance move (not yet in the engine).

- **When:** A loaded enemy transport is near spare bodies of yours and stopping or degrading its passengers' disembark, charge or action next turn matters — or you plan to kill the transport this turn.
- **Units:** Cheap infantry, oval-based models, any units that can reach around the transport.
- **Move type:** Normal
- **11e rules (corrected):** 03.02 set up unengaged (40k_11th_edition_core_rules.txt:491-512); 18.04 disembark modes (:3013-3058); 18.05 as amended by errata (40k_11th_edition_errata_faq_commentary.md:609; launch text :3061-3078); 17.01 (:2867-2874). Corrected: the 18.05 errata removes most of core-rules#62's 'models that cannot be placed are destroyed' payoff.
- **AI today (none):** No candidate targets the space around enemy transports; transport logic exists only for the AI's own disembarks (B44, AIDecisionMaker.gd:8417-8832), and the AI never reasons about enemy cargo.
- **Engine support:** TransportManager.can_disembark (TransportManager.gd:784) and DisembarkMove mode selection (scripts/rules/movetypes/DisembarkMove.gd) on a probe board to test whether the passengers keep a legal set-up; enemy cargo from snapshot embarked_in; _try_move_with_collision_check (AIDecisionMaker.gd:15405). New: a ring placer at about 2.1″ from a target hull.
- **Value (medium):** Can neuter a transport's delivery for a turn, but it is situational and needs several spare models; the kill payoff is weaker after the 18.05 errata.
- **Evidence:**
  - 40k/scripts/rules/movetypes/EmergencyDisembarkMove.gd:4-6 (engine template still describes the launch rule; whether it implements the errata's engaged fallback was not checked)
  - docs/CORE_RULES_REMEDIATION_2026-10.md (P1-4 Emergency disembark placement, 18.05; cited by the core-rules stream)
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-moving-and-the-movement-phase/ (search snippet: the 2″ zone is “a huge amount of zoning”; paired oval bases can box in a transport)
- **Found by:** core-rules, web

#### DEN-N01 — Tarpit a dangerous enemy melee unit with a durable cheap unit _(added by completeness review)_

Charge, or set up a charge on, an enemy melee threat with a cheap but durable unit purely so the threat starts its next turn engaged. Durable means high T/Sv/InSv, many wounds, Feel No Pain, or simply a big expendable blob. An engaged unit cannot make a Normal or Advance move and cannot declare a charge, and if it falls back it cannot charge or shoot either. So for one turn the threat cannot reach the gunline, characters or objective holders it was heading for; it can only pile in and fight the tarpit. Keep other friendly units more than 3″ away so it has no consolidation target (SUR-25), and prefer a tarpit that survives both our Fight phase (the enemy fights back) and theirs. This is the melee mirror of DEN-03/OFF-08, which only lock shooters and action units.

- **When:** An enemy melee unit will reach a high-value friendly unit or key objective holder next turn (charge reach is M + 12″ by 11.04, more with advance-and-charge rules), nothing can kill it this turn, and a cheap durable unit is within charge reach. Skip it when the threat has a fall-back-and-charge rule, could consolidate into another unit within 3″, or would simply kill the tarpit and be free.
- **Units:** Cheap durable infantry blobs (Gretchin, Boyz, Poxwalkers, Cultists), Terminators, Custodian Guard, Plague Marines, walkers and vehicles with good saves
- **Move type:** Normal move to set up the charge; then Remain Stationary while engaged next turn
- **11e rules (verified):** 09.05 a Normal move is allowed only if unengaged (40k_11th_edition_core_rules.txt:1390-1399). 09.06 Advance likewise (:1401-1415). 09.07 a fall-back bars shooting and charging (:1417-1446). 11.02 an engaged unit, or one that fell back, cannot declare a charge (:1603-1625). 12.03 pile-in targets only enemies already engaged (:1737-1760). 12.08 Engaging Consolidation reaches only units within 3″ (:1942-1990).
- **AI today (none):** _build_phase_plan lock_targets (AIDecisionMaker.gd:3789-3806) only collects dangerous SHOOTERS (_estimate_unit_ranged_strength >= PHASE_PLAN_RANGED_STRENGTH_DANGEROUS). charge_intent is scored as melee damage × target value plus PHASE_PLAN_LOCK_SHOOTER_BONUS (:2692). _melee_chase_gate (:2947) chases the nearest enemy. No term values 'this enemy melee unit cannot charge next turn' or the tarpit's durability. Worse, the next turn _decide_engaged_unit makes an off-objective engaged unit fall back (:12123), so even an accidental tarpit is released.
- **Engine support:** Charges, fights and fall-backs are fully implemented. Reuse _calculate_enemy_threat_data (AIDecisionMaker.gd:28695) to find enemy melee units whose reach covers our valuable units, and _estimate_incoming_melee_damage (:12350) plus _assess_engaged_unit_survival (:12373) to price whether the tarpit survives. New: a melee-lock entry in phase_plan.lock_targets, with a charge score based on durability rather than damage.
- **Value (medium):** Directly protects the AI's gunline and scoring units from the commonest 11e killers (Orks, World Eaters, Custodes bricks), at the cost of chaff the AI already owns.
- **Evidence:**
  - [1d6chan 11th Edition Tactics/World Eaters](https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics/World_Eaters) (WebSearch snippet only): 'the enemy can't fall back without making a Desperate Escape test, so the melee unit can tie an enemy up while other units do the damage'
  - YouTube F031, video sPWC5HujB_Y at 19:00: 'holding objectives, picking on isolated, tying units down, blocking movements ... it's no big deal if they're slain'
  - YouTube F024, video u8fm403MGtg at 08:00: 'Plague Legion it gets stuck in combat a lot and it's really hard to get out of combat'
- **Found by:** cross_bucket_critic

#### DEN-11 — Keep enemy units out of your deployment zone through their turn

For your own Defend Stronghold (from round 2, scored at the end of the OPPONENT's turn: 3VP for controlling your home, +2VP while no enemy units are within your DZ — the engine counts only units wholly within) and against their Behind Enemy Lines (they score per unit wholly within your DZ at the end of their turn): keep a durable OC unit on home, block the DZ entrances against walkers (DEN-04), deny deep-strike spots inside the DZ (Deep Strike may land there; DEN-01) and, from round 3, your DZ's edge band (DEN-13), so that no enemy unit can be in your DZ when their turn ends.

- **When:** Defend Stronghold is active for the AI from round 2 (it is redrawn if drawn in round 1), or the opponent holds Behind Enemy Lines, and enemy units can reach or arrive in your DZ next turn.
- **Units:** Durable home holder plus cheap screeners.
- **Move type:** Normal / Remain Stationary
- **11e rules (corrected):** 40k/data/40kdc/missionCards.json:2706 (defend-stronghold: opponent-turn trigger, battle_round min 2, ‘or the end of the fifth battle round, whichever comes first’; territory-control your-deployment-zone enemy_units_max 0), :2679 (behind-enemy-lines); SecondaryMissionManager.gd:1826-1840 (engine: no enemy unit WHOLLY within); 20.04 non-Deep-Strike ingress barred from your DZ only before round 3 (40k_11th_edition_core_rules.txt:3267-3270); 24.09 Deep Strike may land in your DZ (:3649-3661). Corrected: missions#40's 'no survival needed for the player going second in round 5' does not follow from the card text — for either seat the end of the opponent's round-5 turn is never later than the end of round 5, so the holders must survive the opponent's turn every round.
  - _Skeptic:_ The correction of missions#40 is itself wrong. Defend Stronghold scores 'at the end of your opponent's turn or the end of the fifth battle round (whichever comes first)' (missionCards.json:2706 text). For the player going second, a card held or drawn during their own round-5 turn scores at the end of round 5, straight after their own turn, with no enemy turn to survive; that is what the clause is for. The engine does the same: final_round_clause lets the last player of the final round score at the end of that round (SecondaryMissionManager.gd:704-709; ScoringPhase.gd:112-118). Holders must survive the opponent's turn in every earlier round, and in round 5 when the AI moves first. — missionCards.json:2706; SecondaryMissionManager.gd:653-709; ScoringPhase.gd:112-118; 40k_11th_edition_core_rules.txt:3267-3270, 3649-3661
- **AI today (partial):** With Defend Stronghold active the AI adds a home-objective bonus (sec_awareness.defend_home = SECONDARY_OBJECTIVE_ZONE_BONUS, AIDecisionMaker.gd:24101-24106, applied at :10413-10416) and a 3VP home hint, but nothing scores 'no enemy in my DZ at the end of their turn': no DZ-entrance blocks, no DZ landing-spot test, and an opponent's Behind Enemy Lines is never read.
- **Engine support:** _check_no_enemy_wholly_in_own_dz (SecondaryMissionManager.gd:1826), _get_deployment_zone_polygon_pixels (AIDecisionMaker.gd:24856), _calculate_denial_positions (:14929) restricted to the DZ, plus the enemy reachable-area query proposed in DEN-04.
- **Value (medium):** 2VP a turn from round 2 on a common card plus denying Behind Enemy Lines' 3-5VP; reuses the screening machinery.
- **Evidence:**
  - 40k/data/40kdc/missionCards.json:2706, :2679
  - 40k/autoloads/SecondaryMissionManager.gd:1826-1840
  - 40k/scripts/AIDecisionMaker.gd:24101-24106 (Defend Stronghold awareness), :10413-10416 (home bonus)
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-priority-assets/ (search snippet: move-block enemy units to keep them off objectives)
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2706, :2005
  - /home/user/warhammer-40k-godot/40k/scripts/data/PrimaryMissionData11e.gd:271 (no_enemy_wholly_in_my_dz approximates territory with the deployment-zone polygon)
  - _…and 1 more_
- **Absorbed duplicates:** OBJ-25 (Keep enemy units out of your deployment zone and territory)
- **Found by:** missions, core-rules, first-principles

#### DEN-14 — Stay out of enemy Heroic Intervention reach

At the end of your Charge phase the opponent (1CP) can charge with one unengaged unit within 12″ of your units (a VEHICLE only if CHARACTER/WALKER). Leap to Defend may only target your units that made a charge move this phase and are within its 2D6 roll; Into the Fray (+1CP, 2CP in total) caps the roll at 6 but may target any of your units within 6″. End non-charging units — especially fragile shooters and action units — more than 6″ from unengaged enemy melee/character units, and when choosing charges expect Leap to Defend from enemy units within roll distance of where your chargers end: kill or lock those interceptors first, or charge where they cannot reach.

- **When:** The opponent has 1-2 CP and unengaged melee-capable units near your charge targets or your forward units.
- **Units:** All units; especially chargers and fragile forward units.
- **Move type:** Normal / Advance (and the charge-target choice)
- **11e rules (corrected):** 15.11 HEROIC INTERVENTION (40k_11th_edition_core_rules.txt:2734-2770); FAQ 15.01: Into the Fray's original cost is 2CP (40k_11th_edition_errata_faq_commentary.md:576); FAQ 11.02: a rule-granted charge resolves the roll and the move (errata doc :481-484), so by 11.04 (:1663-1665) the intervening unit also has Fights First — the engine withholds it (ChargePhase.gd:4092-4099, ‘Per 10e rules’), contradicting 11e. Engine stratagem StratagemManager.gd:5110-5118. Corrected: first-principles#41's 'a Heroic Intervention gives no Fights First' is the engine's behaviour, not the 11e rule.
  - _Errata check:_ Also discount enemy units that cannot be targeted with Heroic Intervention. That means any unit that used the rapid disembark mode this turn (e.g. Boyz that piled out of a Trukk via Pilin' Out when your unit ended a move within 8″ of it), and any battle-shocked unit, because its controlling player cannot target it with stratagems (e.g. passengers that emergency-disembarked from a transport you destroyed this turn). — FAQ 'Can a unit that used the rapid disembark mode this turn be targeted with the Heroic Intervention stratagem? No' (errata doc :610, grouped under 17.03); FAQ 14.03 (a controlling player cannot target its battle-shocked unit with stratagems, 01.07)
- **AI today (partial):** No model of the opponent's Heroic Intervention: the AI's HI code (B50, AIDecisionMaker.gd:27697-27976) only decides its own interventions, and charge declaration/target scoring never prices an enemy one. Only incidentally, the generic threat dodge (B35, :28695-28890) keeps non-melee units out of enemy M+12″+2″ reach, which covers the 6″ Into the Fray bubble; pure-melee units weight threat ×0.05 and chargers' landing spots are never checked.
- **Engine support:** StratagemManager.get_heroic_intervention_eligible_units_11e (called at AIDecisionMaker.gd:27809-27810) run for the OPPONENT on a probe board lists interceptors; evaluate_heroic_intervention (:27770) can estimate whether they would use it; _calculate_enemy_threat_data (:28695). New: an HI-exposure term in charge-target scoring and destination scoring.
- **Value (medium):** Every army has this 1-2CP core stratagem and it punishes overextended chargers and lone shooters, but it is once per phase.
- **Evidence:**
  - 40k/autoloads/StratagemManager.gd:5110-5118
  - 40k/phases/ChargePhase.gd:4092-4099
  - https://www.wargamer.com/warhammer-40k/stratagems (search snippet: Into the Fray costs +1CP and may pick any enemy unit within six inches)
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-the-charge-and-fight-phases/ (search snippet: 2CP total for Into the Fray)
  - docs/rules/40k_11th_edition_core_rules.txt:2734-2790
  - 40k/autoloads/StratagemManager.gd:4338-4370, :5110-5118
  - _…and 5 more_
- **Absorbed duplicates:** SUR-24 (Keep non-chargers more than 6″ from unengaged enemy units (Into the Fray)); OFF-24 (Pick on isolated targets)
- **Found by:** web, first-principles, core-rules, youtube, factions

#### DEN-23 — Bait or soak the enemy's one-shot reactions with a cheap unit first

Each player can use the same stratagem only once per phase, and a snare fires once. Move an expendable unit first so it ends within 8″ of the enemy reactive unit (or on the snared objective): the enemy spends its once-per-phase reaction and CP (or the snare's D6 mortal wounds, after which the objective is no longer snared) on chaff, or its unit dodges off an objective or out of a firing position; then move the units that matter. Use it to pull a reactive unit off an objective you then take.

- **When:** The enemy has a reactive unit or snared objective that would spoil your main move, a cheap unit can reach the trigger first, and your main plan does not depend on that enemy unit staying put (it may move D6″).
- **Units:** Cheap fast units, chaff.
- **Move type:** Normal / Advance (sequenced before the key moves)
- **11e rules (corrected):** 15.01: a player cannot use the same stratagem more than once in the same phase (40k_11th_edition_core_rules.txt:2495-2500); triggers as in DEN-10 (space-marines/RULES.md:259, :625, :647, :714; custodes/RULES.md:156; orks/RULES.md:223, :268); RULINGS.md:402 (the snare is cleared whatever the roll; one unit triggers one snare).
  - _Errata check:_ Under Commentary 01.02.02, an enemy MORTIS SNARES (used at the end of their Movement phase, no stated duration) has lapsed before your Movement phase, so there is normally no snare to soak with chaff. The bait still works against the once-per-phase reactive-move stratagems. — Commentary 01.02.02 Persisting Rules Effects (errata doc :28)
- **AI today (none):** No reactive-move model (see DEN-10), and the move order (B03, AIDecisionMaker.gd:7119-7147) is engaged → disembarked → normal → transports, then front-to-back by board y — never 'bait first'.
- **Engine support:** Trigger data as in DEN-10; StratagemManager's per-phase usage tracking to know whether the reaction has been spent; the move-order sort in _select_movement_action (AIDecisionMaker.gd:7119-7147).
- **Value (low):** Clever but narrow: faction-specific triggers, spare chaff and careful sequencing.
- **Evidence:**
  - YouTube Wm2Hd8h74_o @65:00 (HivemindHobbies): “if he moves up at all, then they will automatically reactive move behind this obscuring wall” [F014]
  - YouTube VqwMdS9MuIY @60:00 (TacticalTortoise 40k): “it has the ability to reactive move to enemies going close to it ... it may be able to jump away” [F014]
  - 40k/data/40kdc/stratagems.json (Reactive Evasion / Reactive Repositioning: once-per-phase)
  - https://www.tabletopbattles.com/40k-11th-edition-faction-pack-review-tyranids (search snippet: on many objectives, anywhere the opponent ends on it will trigger the move)
  - .llm/codex_11e_wahapedia/RULINGS.md:453, :497
  - 1d6chan Imperial Guard 11e https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics/Imperial_Guard (generic baiting advice only; the web stream found no source for this exact sequence)
- **Absorbed duplicates:** COO-35 (Bait the enemy's once-per-phase reaction with a cheap unit first)
- **Found by:** youtube, web, factions, first-principles, core-rules

#### DEN-26 — Pin the enemy with fall-back-punishing units

Some units make falling back from them costly: Space Wolves Wulfen (Savage Frenzy) and Custodes Knight-Centura (Corner the Quarry) force engaged non-M/V enemies to use Desperate Escape (-1 to the hazard rolls if battle-shocked); Ork Nobz with Wimp-kickaz force it (-1 when riled up); Da Big Hunt's WHERE D'YA FINK YOU'RE GOING? forces it and gives M/V three extra hazard rolls per Beast Snagga unit; Shadowkeepers NO ESCAPE (2CP) lets an unengaged Custodes Infantry unit within 6″ charge a unit that fell back; Aquilan Shield RAPID REACTIONS lets the Custodes unit it fell back from shoot it. Move or charge these units into the enemy shooters and objective holders you most want held, and keep a NO ESCAPE unit within 6″ behind the lock. Mirror: do not plan to fall back from such enemy units.

- **When:** The enemy has a valuable shooter or objective holder that will want to fall back next turn and your punisher can reach it; for NO ESCAPE, a second Custodes Infantry unit within 6″.
- **Units:** Wulfen, Knight-Centura, Nobz (Wimp-kickaz), Beast Snagga (Da Big Hunt), Custodes Infantry (Shadowkeepers, Aquilan Shield).
- **Move type:** Normal / Advance (toward the target to charge)
- **11e rules (verified):** 09.07 (40k_11th_edition_core_rules.txt:1417-1440); 09.07.01 (40k_11th_edition_errata_faq_commentary.md:474); .llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:326 (Savage Frenzy), custodes/wahapedia/Datasheets_abilities.csv:119 (Corner the Quarry), orks/RULES.md:151 (Wimp-kickaz), :110 (WHERE D'YA FINK YOU'RE GOING?), custodes/RULES.md:141 (NO ESCAPE), :211 (RAPID REACTIONS).
- **AI today (none):** The engine forces Desperate Escape for these rules (FallBackMove.gd:61-72), but no AI code targets for them (none of the rule names appear in AIDecisionMaker.gd); the AI's engaged decision only narrates a forced Desperate Escape when its own unit is battle-shocked (AIDecisionMaker.gd:12146-12156).
- **Engine support:** FallBackMove.select_mode (FallBackMove.gd:52-75) and its helpers (savage_frenzy_source, corner_the_quarry_source, forces_desperate_escape, where_dya_fink_forces_desperate_escape) detect 'this engagement forces Desperate Escape'; multiply the lock bonus in charge-intent scoring (AIDecisionMaker.gd:3857-3862) accordingly.
- **Value (low):** Faction-specific, but it turns an engagement into a hard lock for units in the shipped Space Wolves, Custodes and Orks codices.
- **Evidence:**
  - 40k/scripts/rules/movetypes/FallBackMove.gd:52-75 (the engine forces desperate_escape for these rules)
  - YouTube F5TL7LhZJlY @23:00 (40K Dirtbags): “If both of these guys were in combat with the death shroud ... both of them would have to pass a seven up to fall back” [F024; Death Guard analogue]
- **Found by:** factions

#### DEN-27 — Stand within 3″ of a fight to dictate the enemy's consolidation

Leave a unit that has not fought within 3″ (but more than 2″) of where an enemy melee unit will be when the fighting ends — for example an enemy unit on an objective that your chargers are attacking. If it consolidates, the Engaging mode comes before the Objective mode, so it must move toward your unit rather than onto the objective, and if it engages your unit you get to fight it. Consolidation is optional, so the enemy may simply stay put, but it can no longer step onto the objective. Conversely, keep enemies more than 3″ from your own fighters that need Objective consolidation.

- **When:** An enemy fight next to a contested objective, in either player's Fight phase. Exceptions: Custodes rules that allow any mode (Unstoppable Destroyer) or force the objective mode (EMPEROR'S DOMAIN).
- **Units:** Any unit near an ongoing combat.
- **Move type:** Normal (payoff in the Fight phase)
- **11e rules (verified):** 12.07-12.08 consolidation modes, mandatory and assessed in order (40k_11th_edition_core_rules.txt:1934-1985; Ongoing Consolidation errata, 40k_11th_edition_errata_faq_commentary.md:492); pile-in and consolidation are optional (:1719-1730). Engine ConsolidationMove.gd:62-91 (incl. the Custodes overrides).
- **AI today (none):** The AI only chooses its OWN consolidation (B52, AIDecisionMaker.gd:21729-22496); no movement candidate targets an enemy unit's consolidation.
- **Engine support:** ConsolidationMove.select_mode (ConsolidationMove.gd:62-91) run for the enemy unit on a probe board; MissionManager.model_within_inches_of_objective (MissionManager.gd:569) for the 3″ objective test.
- **Value (low):** Narrow geometry and the enemy can decline to consolidate; useful mainly around contested objectives.
- **Evidence:**
  - 40k/scripts/rules/movetypes/ConsolidationMove.gd:1-25, :62-91
  - Web search snippet (40k.app fight phase, unfetched): a unit within 3″ of enemies must select Engaging consolidation; Objective consolidation applies only otherwise
- **Found by:** first-principles

#### DEN-28 — Remove enemy tokens and markers by ending a move next to them

Some enemy assets vanish when your units end moves near them. A Space Marine Teleport Homer token (it gives their Rapid Ingress -1CP and a set-up within 3″ of the token) is removed when one of your units ends a move within 1″ of it — do it during your Movement phase, before the end of the phase when their Rapid Ingress happens. Under Surveil the Foe, whenever your unit ends a move within range of an objective that has any of the opponent's operation markers within range, those markers are removed (the engine scrubs Smoke and Mirrors decoys whenever your unit is in range of a decoyed objective at the end of a turn). Send cheap units to sweep them.

- **When:** An enemy Teleport Homer token is within reach while their reserves can still arrive (rounds 1-3); you hold Surveil the Foe, or the opponent's Smoke and Mirrors decoys are scoring.
- **Units:** Cheap fast units, units already nearby.
- **Move type:** Normal / Advance
- **11e rules (verified):** Teleport Homer datasheet text (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:108: ‘If an enemy unit ends a move within 1″ of that Teleport Homer token, that Teleport Homer token is removed from the battlefield’); RULINGS.md:502 (engine: removed when an enemy model is within 1″, checked at every phase change); 40k/data/40kdc/missionCards.json surveil-the-foe :1757 (text :1867), smoke-and-mirrors :1100; MissionManager.gd:1849-1864 (decoy scrub, both players, approximating 'ends a move within range').
- **AI today (none):** The AI only knows the 10e 'deploy_teleport_homer' secondary action (AIDecisionMaker.gd:16472, :23178, :24010, :24227); 'surveil' has no hits; no candidate move goes to enemy tokens or marked objectives.
- **Engine support:** SMAbilitiesA.homer_position_px (SMAbilitiesA.gd:983) and the F_HOMER unit flag (:186) for token positions; MissionManager._primary_state_11e decoyed lists (MissionManager.gd:98, :1645) for marked objectives; _compute_movement_toward_target (AIDecisionMaker.gd:14212).
- **Value (low):** Cheap moves that strip a CP discount and arrival anchor, or per-objective VP, but only against specific units or cards.
- **Evidence:**
  - .llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:108
  - .llm/codex_11e_wahapedia/RULINGS.md:502
  - 40k/scripts/codex/space_marines/SMAbilitiesA.gd:186-188, :951-1015 (homer token state)
  - 40k/data/40kdc/missionCards.json:1867 (“Whenever a friendly unit ends a move within range of an objective that has any of the opponent's operation markers within range, those markers are removed”)
  - 40k/autoloads/MissionManager.gd:1849-1864
- **Found by:** factions, bucket-editor

#### DEN-30 — Spread a picket net of Hidden infantry across separate terrain pieces

Instead of stacking small Hidden-capable infantry on objectives, post them in separate light/dense terrain areas along the enemy's approach routes. Hidden, they are only visible to enemies within their 15″ detection range (3″ less when gone to ground behind dense terrain), so they are hard to remove; their 8″ bubbles add deep-strike denial (DEN-01), they deny those areas to enemy staging (DEN-06), and they threaten isolated units moving in. Shooting ends Hidden for that turn and the next, so pick shots carefully.

- **When:** Several small Hidden-capable infantry units (Phobos, Scouts and similar), an enemy that must cross the board, and other units holding the objectives.
- **Units:** Small elite or cheap infantry (Phobos, Scouts).
- **Move type:** Normal / Advance (adjacent: Scout move, Infiltrators deployment)
- **11e rules (corrected):** 13.09 Hidden, amended to light/dense (40k_11th_edition_errata_faq_commentary.md:529; 40k_11th_edition_core_rules.txt:2292-2303); 13.11.01 gone to ground -3″ detection (errata doc :535-539); 20.04/24.09 more than 8″ (:3255-3274, :3649-3661). Corrected: light terrain now qualifies, and shooting forfeits Hidden for two turns, so 'picking off' enemies trades against staying Hidden.
- **AI today (none):** Hidden-seeking is implemented but off (WEIGHT_HIDDEN_GAINED 0.0, AIDecisionMaker.gd:2633; _position_would_be_hidden :28515); no candidate spreads units across separate terrain pieces, and screeners are chosen by cost, not by Hidden.
- **Engine support:** TerrainManager.is_model_hidden (TerrainManager.gd:1001-1046; light/dense in the working tree), detection_range_inches_for (:1047-1090), area_at / build_area_group_map; _calculate_denial_positions (AIDecisionMaker.gd:14929) to credit the pickets' bubbles.
- **Value (low):** Real but niche (needs several Hidden-capable units) and largely covered by DEN-01 and DEN-06.
- **Evidence:**
  - Web search snippet (1d6chan 11e Space Marines tactics, unfetched): spread Phobos units across separate terrain pieces rather than parking them all on objectives, so they can pick off enemies moving in
  - YouTube 1AwnDclFviQ @159:00 (WarGames Live): “this dog is doing some rapid ingress screening which is nice ... Deep strike denying” [F029]
- **Found by:** youtube

#### DEN-34 — Hold ground inside enemy charge reach with a Fights First unit (corrected premise)

The raw idea was to stand a Fights First unit (Custodes under Heralds of the Throne, a Judiciar's Tempormortis, objective-gated TRANSHUMAN SWIFTNESS / INDOMITABLE GUARDIANS) in front of enemy melee so it 'strikes first if charged'. In 11e that premise is wrong: every unit that makes a charge move has Fights First until the end of the turn, and the player whose turn it is starts the Fights First alternation, so the charger still swings first. What remains: your Fights First unit fights right after the first enemy Fights First unit instead of after all of them (it matters when several enemy units charge in one phase), and COUNTEROFFENSIVE (2CP) gives the same timing. Use it to hold an objective or bait a charge with a unit that hits back hard, not to pre-empt the charger.

- **When:** Your defender is a strong Fights First melee unit, several enemy units are likely to charge into the area, and holding the objective matters.
- **Units:** Custodes (Emissaries Imperatus), a Judiciar and its unit, Space Marines/Custodes with objective-gated Fights First.
- **Move type:** Normal / Remain Stationary
- **11e rules (corrected):** 11.04 AFTER MOVING: each model has Fights First (40k_11th_edition_core_rules.txt:1663-1665); 12.04 Fights First combats start with the player whose turn it is and alternate (:1830-1850); 24.13 (:3736-3744); 15.12 COUNTEROFFENSIVE (:2770-2782); .llm/codex_11e_wahapedia/custodes/RULES.md:195 (Heralds of the Throne). Engine: ChargePhase.gd:1458-1466 (a charge grants flags.fights_first), FightSequencer.gd:4-20, :91-101. Corrected: factions#43 said charging does not grant Fights First.
- **AI today (none):** Fights First appears only in fight-phase choices (e.g. the COUNTEROFFENSIVE valuation, AIDecisionMaker.gd:1960-1968, :27663-27672); movement threat logic has no Fights First term (:7357-7391).
- **Engine support:** FightSequencer.is_fights_first (FightSequencer.gd:91-101) and next_selection to simulate the order; _estimate_melee_damage (AIDecisionMaker.gd:19576) and _estimate_incoming_melee_damage (:12350).
- **Value (low):** The genuine 11e payoff is small; it is only worth it in multi-charge situations.
- **Evidence:**
  - 40k/phases/ChargePhase.gd:1458-1466 (“Mark unit as charged and grant Fights First”)
  - 40k/scripts/rules/FightSequencer.gd:9-20, :91-101
  - .llm/codex_11e_wahapedia/custodes/RULES.md:195
- **Found by:** factions

#### DEN-N02 — Wall enemy MONSTER/VEHICLE lanes with your own MONSTER/VEHICLE models _(added by completeness review)_

When the enemy movers you need to stop are MONSTER/VEHICLE models, build the move-block (DEN-04/DEN-05) from your own MONSTER/VEHICLE models and dense terrain, not infantry. On normal and advance moves, MONSTER/VEHICLE models can move straight through enemy models other than MONSTER/VEHICLE models. An infantry wall is therefore transparent to a tank's or monster's normal move; only other MONSTER/VEHICLE bodies and dense sections over 2″ high stop it. Infantry screens still work against their charges, because the 17.01 exemption covers only normal and advance moves. So split the job: hulls across movement lanes to objectives, infantry across charge lanes.

- **When:** The threats approaching an objective or backline lane are enemy MONSTER/VEHICLE units (Knights, tanks, gargantuan creatures, Battlewagons), and the AI has spare MONSTER/VEHICLE models nearby (empty transports, cheap walkers).
- **Units:** As blockers: empty transports, walkers, monsters, tanks. Used against enemy MONSTER/VEHICLE movers.
- **Move type:** Normal / Remain Stationary
- **11e rules (verified):** 17.01 (40k_11th_edition_core_rules.txt:2870-2875). 03.01 bases cannot move through enemy models (:379-395). FAQ 17.01: other move types pass through friendly units only (40k_11th_edition_errata_faq_commentary.md:596-599). 11.04 the charge move has no 17.01 exemption (:1640-1665). 13.06 dense sections over 2″ high (:2163-2183).
- **AI today (none):** Screen and blocker selection is cost-based. _is_screening_candidate (AIDecisionMaker.gd:14911) takes units of 100 pts or less with OC 2 or less. _calculate_corridor_blocking_positions (:15092) places them without checking whether the threatening enemies are MONSTER/VEHICLE models that ignore infantry on normal and advance moves.
- **Engine support:** The AI's planner already models pass-through for its own movers (_get_monster_vehicle_models :15897, _path_crosses_monster_vehicle :15957); reuse them on the enemy's projected path. New: a blocker-type filter in the corridor-block pass, keyed on the enemy movers' keywords.
- **Value (low):** Only matters against MONSTER/VEHICLE-heavy lists, but without it the AI's corridor blocks against those lists are wasted units.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:2870-2875 (17.01)
  - DEN-22/COO-28 in this catalogue already record the attacker's side of 17.01; this entry is the defender's side
- **Found by:** cross_bucket_critic

#### DEN-25 — Block an engaged enemy's fall-back route (surround to trap)

Move other units (more than 2″ away, or via charges and pile-ins) to close the escape directions of an enemy unit engaged with yours. An Ordered Retreat cannot move through your models, so the enemy must choose Desperate Escape — a hazard roll per model (1-2 = a mortal wound, 3 for all-M/V units) and then a battle-shock roll — or cannot fall back at all if no unengaged end position is reachable within M. Desperate Escape can always cross your models, so in 11e a trap taxes rather than seals.

- **When:** A valuable enemy unit is locked by your tarpit (DEN-15), its exits can be closed, and escaping would hand it shooting or scoring.
- **Units:** Any friendly units near an existing combat.
- **Move type:** Normal (adjacent: pile-in / consolidation wrap in the Fight phase)
- **11e rules (verified):** 09.07 fall-back modes; Desperate Escape models may be moved through enemy models (40k_11th_edition_core_rules.txt:1417-1440); 03.01 (:385-395); 06.03 hazard rolls (:1067-1073); 09.07.01 commentary (40k_11th_edition_errata_faq_commentary.md:474).
- **AI today (partial):** Adjacent only: the Fight-phase consolidation places models on the far side of the enemy to block its fall-back (B52, AIDecisionMaker.gd:21972, :22178-22240); nothing in the Movement phase. Engine-limited: MovementPhase checks enemy-base crossing only for NORMAL/ADVANCE (:756, :893, :8144, :8231), so an ordered retreat already walks through non-M/V models here; the block only bites through M/V bases (:898-903) or by denying end positions.
- **Engine support:** Engine first: apply _path_crosses_enemy_bases (MovementPhase.gd:7422) to FALL_BACK in ordered_retreat mode. Then run FallBackMove.select_mode (FallBackMove.gd:52-75) and the AI's own _compute_fall_back_destinations (AIDecisionMaker.gd:12185) for the ENEMY unit on a probe board to count its legal exits.
- **Value (low):** 11e softens traps (Desperate Escape always crosses for about one wound in three per model plus a battle-shock roll) and the engine does not enforce the block yet.
- **Evidence:**
  - 40k/scripts/rules/movetypes/FallBackMove.gd:20-75
  - 40k/phases/MovementPhase.gd:756, :893, :8144, :8231 (enemy-base crossing checked only for NORMAL/ADVANCE), :898-903 (M/V bases block every non-FLY move)
  - YouTube u8fm403MGtg @08:00 (40K Fireside): “Plague Legion it gets stuck in combat a lot and it's really hard to get out of combat” [F024]
- **Found by:** first-principles

### Coordination, auras & abilities

#### COO-02 — Stay inside friendly buff auras and place the aura source to cover the most units

End the beneficiaries' moves inside a friendly aura (or a 'within X″ of a CHARACTER' ability range), and move the aura source last so it covers the most valuable units at the moment the buff is used. In-engine sources: Ghazghkull's Prophet of da Great Waaagh! (ORKS within 6″: +1 to hit and +1 to wound in melee), Beastboss on Squigosaur's Thundering Stampede (+1 to charge), Venerable Dreadnought's Fervour of the Ancients (+1 to advance and charge within 6″) and Wisdom of the Ancients, Guilliman, Trajann's Captain-General (6″), Murderfang, Psychic Null, and OC auras (Curse of the Wulfen and Hunting Hounds near a SPACE WOLVES CHARACTER).

- **When:** The beneficiary will shoot, charge, advance or fight this turn or next, and can end inside the bubble without dropping its objective or role. Advance and charge auras must cover the unit when the roll is made, so it must be inside at the end of its own move: move beneficiaries first and the source last, or plan them together. Discount it when clustering exposes the source or invites area attacks. Embarked or reserve sources give nothing, because they are not on the battlefield.
- **Units:** Unattached aura characters and walkers (Ghazghkull, Beastboss on Squigosaur, Venerable Dreadnought, Guilliman, Trajann, Murderfang, Anathema Psykana units, Rhino Primaris), and the ORKS / SPACE WOLVES / ADEPTUS ASTARTES / CUSTODES units they buff
- **Move type:** Normal / Advance (beneficiaries and source); Remain Stationary when already covered
- **11e rules (corrected):** 22.01 Aura abilities: they affect units within the stated range, the source is always within its own aura, and the same aura applies only once (40k_11th_edition_core_rules.txt:3407-3416). 01.04.01: a model is within a distance if any part of its base is, and a unit is within it if one of its models is (40k_11th_edition_errata_faq_commentary.md:79-81). 01.02.04 and the 18.02 FAQ: embarked and reserve units are not on the battlefield, so their abilities cannot measure (errata_faq:34-36, 617-620). Datasheet texts: Prophet of da Great Waaagh! (.llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:34), Fervour of the Ancients (space-marines/wahapedia/Datasheets_abilities.csv:730).
  - _Errata check:_ An advance roll is made before the unit moves (core 09.06 'BEFORE MOVING'; FAQ 21.03 has take to the skies declared when the unit is selected, before that roll), so a +1-to-advance aura must already cover the beneficiary when it is selected to move: move or place the source first. Only charge auras, rolled in the Charge phase, reward moving the beneficiaries first and the source last. — Core 09.06 Advance Move (Before Moving); FAQ 21.03 Flying Models (errata_faq:681-682)
- **AI today (none):** In AIDecisionMaker.gd, grep 'aura' hits only Smokescreen stratagem lines (27099, 27153) and a reserve-distance sanity check (28443). None of the aura ability names appear, and the UnitAbilityManager aura helpers are unused by the AI. Candidate OC (oc_efficiency, B06 9910-10598) uses the printed OC, so OC auras at a destination are not seen.
- **Engine support:** UnitAbilityManager.get_aura_abilities_on_unit / is_unit_in_aura / find_friendly_units_within_aura (UnitAbilityManager.gd:3662-3730); codex predicates such as the Prophet check (OrkAbilities11e.gd:815-838) and captain_general_source (CustodesAbilities.gd:490); MissionManager.model_oc (MissionManager.gd:659) for OC auras. New query: per aura source, its range, keyword filter and effect value as data; a destination term for the value of the buffs the unit would be inside at its end position; and a source-placement pass that maximises the value it covers.
- **Value (high):** The AI's main faction (Orks, with Ghazghkull in shipped lists) gets +1 to hit and +1 to wound in melee by staying within 6″, and no movement term exists today.
- **Evidence:**
  - 40k/scripts/codex/orks/OrkAbilities11e.gd:815-838 (Prophet aura applied within 6″ of Ghazghkull)
  - 40k/scripts/codex/space_wolves/SWAbilities11e.gd:745 (Fervour of the Ancients); 40k/scripts/codex/custodes/CustodesAbilities.gd:139, :490 (Captain-General, 6″)
  - 40k/autoloads/MissionManager.gd:679-689 (Curse of the Wulfen and Hunting Hounds OC near a SPACE WOLVES CHARACTER)
  - 40k/armies/orks.json and orks_taktikal.json (Ghazghkull in shipped Ork lists); sw11e_codex_test.json (Venerable Dreadnought, Murderfang)
  - 1d6chan Death Guard 11e https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics/Death_Guard (search snippet: put the 9″ aura unit right behind the wall; faction not implemented here)
  - research/ai_feasibility_2026-08-09/research_commercial-practice.md:13 (XCOM position scoring includes 'proximity to allies')
  - _…and 3 more_
- **Absorbed duplicates:** OFF-36 (Stay inside a friendly offensive aura)
- **Found by:** core-rules, youtube, web, factions, first-principles

#### COO-05 — Fall back to free the enemy for your guns and fresh chargers

Make an Ordered Retreat with an engaged unit so the enemy it was holding becomes a legal ranged target for the rest of the army, and so a fresh unit can charge it and gain Fights First. The unit that fell back gives up its own shooting, charge and actions this turn.

- **When:** The damage friendly shooters and chargers can do to the freed enemy this turn is worth more than keeping it locked plus the falling-back unit's own lost turn. It pays most when the enemy is not a MONSTER/VEHICLE (an engaged M/V can already be shot at -1 to hit) and the friendly engaged unit is cheap or losing.
- **Units:** Any engaged friendly unit (Ordered Retreat needs it not battle-shocked); the payoff comes from other friendly shooters and melee units
- **Move type:** Fall Back
- **11e rules (verified):** 04.02: ranged targets must be unengaged (40k_11th_edition_core_rules.txt:639-644). 17.03: an engaged MONSTER/VEHICLE can still be targeted, at -1 to hit (:2898-2910; errata excludes [BLAST], 40k_11th_edition_errata_faq_commentary.md:608). 09.07: after a fall-back move the unit cannot shoot, declare a charge or start an action, and Ordered Retreat is only for units that are not battle-shocked (:1417-1442). 11.04: chargers gain Fights First (:1661-1665).
- **AI today (none):** _decide_engaged_unit (AIDecisionMaker.gd:11958-12179) weighs only survival and objective OC; it never prices what friendly shooters and chargers could do to the freed enemy. It falls back by default when off an objective (12093-12157), which frees the target only by accident, and it holds on an objective when winning or tied on OC (12050-12090) even when the army could kill the locked enemy.
- **Engine support:** _estimate_unit_ranged_strength (25866), _estimate_melee_damage (19576), and shooting_lanes / charge_intent from _build_phase_plan (3773) to count friendly units that could engage the freed enemy; RulesEngine.get_eligible_targets (RulesEngine.gd:7137) on a board copy with the friendly unit moved away. New query: friendly expected damage on enemy E if E were unengaged, added as a fall-back bonus in _decide_engaged_unit.
- **Value (high):** An engaged-unit decision comes up most turns in melee matchups, the swing (the whole army's shooting on the freed unit versus one locked enemy) is large, and the AI already has the decision point to hang the term on.
- **Evidence:**
  - 40k/scripts/rules/shootingtypes/ShootingType.gd:45-53 (engaged non-MONSTER/VEHICLE units cannot be targeted)
  - 40k/scripts/rules/movetypes/ChargeMove11e.gd:135-141 (chargers get fights_first)
  - Search synthesis of 1d6chan 10e tactics https://1d6chan.miraheze.org/wiki/Warhammer_40,000/10th_Edition_Tactics (10e source, edition-agnostic tactic: fall back the engaged unit, then shoot the enemy)
  - docs/rules/40k_11th_edition_core_rules.txt:628-642, 2894-2909, 1417-1441
- **Absorbed duplicates:** OFF-29 (Fall back to free an engaged enemy for your shooters)
- **Found by:** web, first-principles, core-rules

#### COO-01 — Converge several units on one priority target

Move two or more units so their weapon ranges or charge reach overlap on the same priority enemy, with enough combined expected damage to remove it this turn, instead of each unit choosing its own target. This includes adding a fresh charger to a combat that is already going on and finishing a wounded objective holder or lane blocker: a one-model survivor still scores its OC and still blocks movement.

- **When:** A high-value enemy (objective holder, character, dangerous shooter, screen blocking a lane) needs more damage than any one unit can deal; a wounded enemy still holds an objective the VP estimator values; or a combat is stalemated and a second charger would end it. Skip when the combined kill chance stays low or the meeting point is inside an enemy kill zone.
- **Units:** All shooting and melee units (each charger must be within 12″ of the target to declare)
- **Move type:** Normal / Advance (Advance only for assault shooters or units allowed to charge after advancing)
- **11e rules (verified):** 04.02: each weapon picks its own target, which must be visible, within range and unengaged (40k_11th_edition_core_rules.txt:628-645). 14.02: level of control adds up the OC of every model in range, so one survivor keeps control (:2401-2416). 11.02: each unit declares its own charge (within 12″, not engaged, no advance or fall-back move) (:1612-1622). 11.04: several charge targets are allowed and chargers gain Fights First (:1640-1665).
- **AI today (partial):** Convergence happens only outside movement: the Shooting-phase focus-fire plan works among units already in range (_build_focus_fire_plan AIDecisionMaker.gd:17023, built at 16532-16542), and the Charge phase adds +3.0 when a friendly unit is already fighting the target (CHARGE_GANG_UP_BONUS 1615, applied 19263). In movement, charge_intent picks one target per unit with no kill-sufficiency or shared-target term (3830-3912), shooting_lanes only lists enemies already in range (3914-3940), and melee seekers chase the nearest enemy (B11, 2947-3099).
- **Engine support:** Extend _build_phase_plan (AIDecisionMaker.gd:3773) with a per-target ledger of damage pledged against wounds left, using _estimate_melee_damage (19576), _estimate_weapon_damage (17984) and _estimate_unit_ranged_strength (25866). Post-move reach: RulesEngine.unit_within_weapon_reach and max_ranged_weapon_range_inches (RulesEngine.gd:6718, 6693). New query: which enemies a unit could target from a candidate destination (RulesEngine.get_eligible_targets on a board copy with the unit moved, RulesEngine.gd:7137).
- **Value (high):** It applies to every army in most turns, it is a confirmed corpus principle (F010), and movement has no convergence term, so damage spreads over targets that survive and keep scoring.
- **Evidence:**
  - YouTube PWtaFLZYu_U @03:00 (Warpbane Tactics, F010): 'spreading my damage across multiple units would have been a massive mistake. I focused on completely removing one unit at a time'
  - YouTube D5XVd0FRgK8 @02:00 (Warpbane Tactics, F010): 'unit left alive on one wood can still hold an objective, block our movement'
  - YouTube lNn0zv_w8t8 @05:00 (Planet 40K, F010): 'another bad priority target ... is just simply bad trades'
  - research/youtube/ai_learnings.json F010 (rules_status confirmed, medium confidence)
  - 40k/scripts/AIDecisionMaker.gd:1615 and :19263 (CHARGE_GANG_UP_BONUS, Charge phase only)
- **Found by:** core-rules, youtube, first-principles

#### COO-04 — Secure an objective at the end of your Movement phase, then move on

With a securing ability, end the Movement phase controlling an objective so that it is secured (14.03). Next turn, release the unit for another job: the objective stays yours until the enemy's level of control is greater than yours at the end of a phase. Prefer objectives the enemy cannot easily out-OC.

- **When:** The unit has Thievin' Scavengers (Gretchin) or Raise the Banner (Bladeguard Ancient, Ancient in Terminator Armour), or a securing stratagem such as DUBIOUS RESTRAINT or VIGILANCE ETERNAL is affordable. The objective is away from enemy OC, and the army has more objectives to cover than bodies. Next turn, leave a secured objective for an unsecured one rather than sitting on it.
- **Units:** Gretchin (Thievin' Scavengers), Bladeguard Ancient and Ancient in Terminator Armour (Raise the Banner), Taktikal Brigade Boyz / Kommandos / Stormboyz (DUBIOUS RESTRAINT), Custodes and Space Marine stratagem targets
- **Move type:** Normal / Advance onto the objective this turn (securing is not an action, so an Advance is fine); Normal / Advance away next turn
- **11e rules (verified):** 14.03 Secured Objectives (40k_11th_edition_core_rules.txt:2427-2433). 14.03 FAQ: a unit that took control at the end of your Movement phase can secure that objective with its ability (40k_11th_edition_errata_faq_commentary.md:561-562). 14.02 tie rule for secured objectives (:2410-2416). DUBIOUS RESTRAINT: 'Start/end of your Movement phase ... Select one objective your unit is controlling. That objective is secured.' (.llm/codex_11e_wahapedia/orks/RULES.md:191).
- **AI today (partial):** Securing happens only incidentally, when an ordinary capture lands a securing unit on an objective. DUBIOUS RESTRAINT is used at the end of the phase if the unit already controls an objective and 2+ CP are available (OrkCodexMovement.gd:292-295), and VIGILANCE ETERNAL is scored at use (AIDecisionMaker.gd:26661). SECURED-AWARE, which would read secured objectives as held and free their keeper, ships OFF (FIX_SECURED_AWARE = 0.0, 1912-1925; keeper release at 10716-10725). No candidate values 'secure it this turn, leave next turn'.
- **Engine support:** MissionManager.is_objective_secured and get_sticky_objectives (MissionManager.gd:147, 1068); _secured_aware_lock (AIDecisionMaker.gd:8899); _capture_arrival (13091). New queries: which units carry a securing trigger and when it fires; and a capture-candidate bonus for keeping the objective without a keeper next turn, with FIX_SECURED_AWARE on so the plan then frees the securer.
- **Value (high):** Gretchin with Thievin' Scavengers are in most shipped Ork lists. A secured objective is free OC that frees a unit every turn, yet the AI pins keepers on objectives it already holds.
- **Evidence:**
  - 40k/scripts/codex/orks/OrkAbilities11e.gd:2385-2404 (Thievin' Scavengers: at the end of your Movement phase, a controlled objective is secured)
  - 40k/scripts/codex/space_marines/SMAbilitiesB.gd:862-882 (Raise the Banner)
  - 40k/autoloads/MissionManager.gd:141-150 (secure_objective, is_objective_secured)
  - 40k/armies/recon_stomps.json, battlewagons.json, Orks_2000.json, tutorial_orks.json (Gretchin); orks_taktikal.json (Taktikal Brigade)
  - 40k/scripts/AIDecisionMaker.gd:1921-1922 comment: 'Bench Kult of Speed Gretchin secure objectives (Thievin' Scavengers); the AI read them as uncontrolled / contested and pinned keepers on them'
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:136-150 (secure_objective / is_objective_secured), :922-934 (a lock is broken only at the end of a phase, by greater OC)
  - _…and 3 more_
- **Absorbed duplicates:** OBJ-16 (Secure an objective, then walk the unit on to the next one)
- **Found by:** missions, first-principles, core-rules, web, factions, youtube

#### COO-06 — Stage the Orks for one coordinated Waaagh! turn

In the turn before calling the War Cry, move several Ork units so that next turn, once riled up (5+ invulnerable save, ranged [ASSAULT], an Advance does not stop a charge), as many as possible are within M + re-rolled Advance + 2D6 of worthwhile targets at the same time. Do not call it just because one unit can reach something. This entry was added by the bucket editor from the bucket definition ('faction triggers such as Waaagh!').

- **When:** Orks with the War Cry still unused: position in rounds 1-2 for a call in round 2-3 (F020: not turn one, not the moment one unit can reach something). Hold faster units back so they arrive with the slow ones. Also consider calling it when the army must cross open ground, because the 5+ invulnerable save is worth it on its own.
- **Units:** ORKS units with the Waaagh! ability (Boyz, Nobz, Beast Snagga, Speed Freeks, Warbosses)
- **Move type:** Normal (staging distance) this turn; Advance + charge in the Waaagh! turn
- **11e rules (verified):** Orks 11e army rule Waaagh!: re-roll advance rolls; while riled up the unit has a 5+ invulnerable save, its ranged attacks have [ASSAULT], and an advance move does not stop it declaring a charge; War Cry (once per battle, start of the Command phase) riles every ORKS unit with the ability until the end of the next turn (.llm/codex_11e_wahapedia/orks/RULES.md:76). 11.02: a charge needs an enemy within 12″ (40k_11th_edition_core_rules.txt:1618-1622).
- **AI today (partial):** The Command-phase call (AIDecisionMaker.gd:6364-6420) always calls from round 2, or in round 1 if any single unit is within about 22″ of an enemy. It counts units in range but never moves units into range together, and movement has no Waaagh! staging term. WAAAGH_MIN_UNITS_IN_RANGE from profiles/orks.json is not read by the AI (grep finds 0 hits), and that profile is not shipped (40k/data/ai_profiles holds only baseline_2026_08.json).
- **Engine support:** _get_nearest_enemy_for_charge (AIDecisionMaker.gd:3114), _advance_reach_chance (13247) and _prob_sum_d6_at_least (12788) for M + re-rolled D6 + 2D6 reach; the call's units-in-range counter (6364-6420) can share a 'units in range next turn' count. New query: a plan-level 'Waaagh! next turn' flag that adds a staging bonus to destinations inside the threat band of priority targets, with a hold-back for units that would arrive alone.
- **Value (high):** Orks are the AI's main faction (every shipped plan is an Ork plan), the Waaagh! is its biggest once-per-battle swing, and the corpus finding is high-confidence and confirmed.
- **Evidence:**
  - YouTube QZ9wggn2oUo @04:00 (Tabletop Nexus, F020): 'Don't call it turn one, though. Don't call it the moment you can reach something'
  - YouTube QZ9wggn2oUo @04:00 (Tabletop Nexus, F020): 'A strong Waaagh! turn has several units positioned to benefit at once'
  - YouTube DHVBk9vnR8w @07:00 (40K Dirtbags, F020): 'moved up a little bit like two extra inches forward uh to plan for turn two Waagh'
  - YouTube vLQTE5P6pJg @03:00 (Hubtown Hammer, F020): 'Turn two, the Orks used the Waagh, which turned out to be a great choice ... blunted by some hot five plus invulnerable'
  - research/youtube/profiles/orks.json WAAAGH_MIN_UNITS_IN_RANGE 3 (draft profile, not shipped)
  - YouTube QZ9wggn2oUo @04:00 (Tabletop Nexus): "Don't call it turn one, though. Don't call it the moment you can reach something" (ai_learnings.json F020)
  - _…and 6 more_
- **Absorbed duplicates:** OBJ-28 (Stage several units for a coordinated strike turn (once-per-battle army buff, e.g. Waaagh! War Cry))
- **Found by:** bucket-editor, youtube, web, factions, first-principles

#### COO-11 — Park a Heroic Intervention umbrella

End your Movement phase with an unengaged melee unit (not battle-shocked; a VEHICLE only if it is a CHARACTER or WALKER) placed so that enemies likely to charge your objective holders or gunline end within its reach. Leap to Defend charges only units that made a charge move, within the 2D6 roll; Into the Fray (+1CP) charges any enemy within 6″, with the roll capped at 6. The same unit also threatens a counter-charge in your next turn.

- **When:** The opponent's melee threats are approaching your objective holders or gunline, you will have 1CP (2CP for Into the Fray) in their turn, and the counter-punch unit is unlikely to be shot off or charged first. A unit that rapid-disembarked this turn cannot be the target.
- **Units:** Melee units; VEHICLES only if CHARACTER or WALKER
- **Move type:** Normal / Remain Stationary in your own Movement phase; the payoff is adjacent (15.11, end of the opponent's Charge phase)
- **11e rules (verified):** 15.11: target one friendly unengaged unit within 12″ of one or more enemy units; a VEHICLE only if CHARACTER/WALKER; Leap to Defend targets only units that made a charge move this phase; Into the Fray (+1CP) caps the roll at 6 and allows any enemy within 6″ (40k_11th_edition_core_rules.txt:2734-2766). 15.01 FAQ: Into the Fray costs 2CP (40k_11th_edition_errata_faq_commentary.md:576-577). 01.07: a battle-shocked unit cannot be targeted by its own player's stratagems (:212-220). FAQ: a unit that used rapid disembark this turn cannot be targeted with Heroic Intervention (errata_faq:610-611).
- **AI today (none):** Heroic Intervention is only a reactive decision (evaluate_heroic_intervention AIDecisionMaker.gd:27770-27976, wired at 18259-18308; B50). No movement term places a counter-punch unit near likely charge targets; grep 'heroic' finds no Movement-phase use.
- **Engine support:** _calculate_enemy_threat_data (AIDecisionMaker.gd:28695) to predict which friendly units the enemy can charge; _estimate_melee_damage (19576); _prob_sum_d6_at_least (12788) for 2D6 reach. New query: expected Heroic Intervention value at destination D, equal to P(an enemy charger ends within 2D6 of D) x melee value, plus the 6″ Into the Fray band.
- **Value (medium):** A core stratagem every army has that deters charges onto holders, but it needs CP in the opponent's turn and a spare melee unit.
- **Evidence:**
  - 40k/autoloads/StratagemManager.gd:5110-5118 (heroic_intervention_11e)
  - 40k/phases/ChargePhase.gd:1753 (the engine gives Heroic Intervention chargers no Fights First; 15.11 resolves a charge through 11.02/11.04, which does grant it, so this is unverified)
  - Spikey Bits https://spikeybits.com/warhammer-40k-11th-edition-stratagems-overhauled/ (search snippet: used at the end of the Charge phase, range up to 12″)
  - Frontline Gaming 'A Case Study on Heroic Intervention' https://frontlinegaming.org/2020/05/08/93739/ (older edition; concept only)
  - 40k/autoloads/StratagemManager.gd:5110-5118
  - .llm/codex_11e_wahapedia/custodes/RULES.md:165, 202; space-marines/RULES.md:366, 709
  - _…and 2 more_
- **Absorbed duplicates:** ADJ-15 (Park counter-chargers within Heroic Intervention reach of where the enemy will charge or score)
- **Found by:** core-rules, youtube, web, first-principles, factions, missions

#### COO-12 — Post an Overwatch picket over the enemy's approach

End your Movement phase with an unengaged, non-TITANIC high-volume or [TORRENT] shooter that has sight lines, within 24″, over the lanes and objectives the enemy must move into. At the end of the opponent's Movement phase it can Fire Overwatch (1CP; snap shooting at one visible, unengaged enemy within 24″, hitting only on unmodified 6s).

- **When:** The opponent must cross open ground to reach objectives or to charge, you will have 1CP in their turn, and the shooter does not rely on staying Hidden (firing removes Hidden for that turn and your next).
- **Units:** High shot-volume and [TORRENT] units (not TITANIC)
- **Move type:** Normal / Remain Stationary
- **11e rules (corrected):** 15.08 Fire Overwatch: end of the opponent's Movement phase, one friendly unengaged unit excluding TITANIC units (40k_11th_edition_core_rules.txt:2735-2748). 15.09 snap shooting: one visible enemy within 24″, unmodified 6s only, no hit re-rolls (:2749-2768). 15.01: the same stratagem once per phase (:2495-2499). 13.09: ranged attacks this turn or last remove Hidden (:2292-2303). How [TORRENT] (24.37, :3956-3962) interacts with 15.09's 'only hits on an unmodified 6' is not settled locally (unverified).
  - _Errata check:_ Fire Overwatch is resolved at the end of the opponent's Movement phase, so only where enemies end their moves matters: INFANTRY/BEASTS/SWARM models that end in a terrain area containing light or dense features (such as many terrain objectives) and did not shoot this turn or last are hidden and can only be seen from within 15″, or 12″ once they have Gone to Ground behind dense features, so the picket must be that close to those areas, not merely within 24″. FAQ 05.01 also restates that, unless a rule says otherwise, snap-shooting attacks only hit on a roll of 6; it does not name [TORRENT], but it points to [TORRENT] weapons not auto-hitting in Overwatch. — 13.09 errata (errata_faq:529); Commentary 13.11.01 Gone to Ground (:539); FAQ 05.01 Hit Roll (:344-347)
- **AI today (none):** Overwatch is only a reactive decision (evaluate_fire_overwatch AIDecisionMaker.gd:27249, wired at 18215-18256). The movement planner has no term for keeping a shooter unengaged with sight over enemy approach lanes. The only Overwatch term in movement is the exposure penalty for our own moves, which ships OFF (OVERWATCH_EXPOSURE_PENALTY = 0.0 at 2662; term at 10290-10304).
- **Engine support:** _estimate_unit_overwatch_damage (AIDecisionMaker.gd:19521); _calculate_enemy_threat_data (28695) to predict where enemy moves end; TerrainManager.model_visible_11e (TerrainManager.gd:1209) and LineOfSightManager.calculate_los_to_position (LineOfSightManager.gd:101) with probe models. New query: the expected Overwatch damage from destination D onto the enemy's likely end positions, as a destination term.
- **Value (medium):** The corpus says Overwatch is strong in 11e and cannot be baited, but each use is one unit, costs 1CP and hits only on 6s.
- **Evidence:**
  - YouTube FT5JoL5Myis @05:00 (Deploy on the Line 40K, F004): 'it's just too easy to overwatch in 11th edition. You can't play around it anymore with these big squads'
  - YouTube eUpeWbN7gF4 @28:00 (StrikingScorpion82, F004): 'overwatch is done at the end of the opponent's movement phase ... it's a decision we can make uh once movement's done'
  - 40k/autoloads/StratagemManager.gd:5086-5100 (fire_overwatch_11e); 40k/scripts/rules/shootingtypes/SnapShooting.gd:22-41
  - 40k/autoloads/RulesEngine.gd:1458-1468 (snap-shooting targets must be unengaged, even MONSTER/VEHICLE, because 17.03 applies only in your own Shooting phase)
  - Grimslate https://grimslate.com/blog/core-stratagems-guide-11th-edition (search snippet: a volume play)
  - docs/rules/40k_11th_edition_core_rules.txt:2735-2769
  - _…and 10 more_
- **Absorbed duplicates:** OFF-40 (Set up an Overwatch net); OBJ-45 (Set an Overwatch / crossfire net for the opponent's turn); ADJ-11 (Leave volume shooters where they can Fire Overwatch on the enemy's approach)
- **Found by:** core-rules, web, missions, first-principles, factions

#### COO-17 — Push battle-shock and OC-debuff abilities onto enemy objective holders

Move units whose abilities force battle-shock rolls or cut OC so the enemy's objective holders are inside range at the moment the ability applies, stripping their OC and setting up flips, precision kills and charges. In-engine examples: Custodes Creeping Dread (enemy PSYKER or below-starting-strength units within 12″ of an ANATHEMA PSYKANA model roll battle-shock at -1 in the opponent's Command phase), Reivers' Terror Troops (-1 OC for enemy models within 3″), and Lord of the Pyroclasts (-1 OC for the enemy engaged with his unit). The Tyranid and Death Guard examples in the corpus are factions this engine does not implement.

- **When:** Enemy holders have low Leadership, are below half strength or are PSYKERs, and the ability's range can be reached without being charged first. Time it before the scoring check (for example the end of your turn, for a test in the opponent's Command phase).
- **Units:** Anathema Psykana units (Null Maiden Vigil), Reiver Squads, Adrax Agatone; Tyranid synapse / Neurolictor and Death Guard aura units in other factions
- **Move type:** Normal / Advance
- **11e rules (verified):** 01.07: a battle-shocked unit's OC becomes '-' (40k_11th_edition_core_rules.txt:212-220). 08.03: units that are battle-shocked or at or below half strength roll in the Battle-shock step (:1244-1256). 14.02 level of control (:2401-2416). Creeping Dread ruling: .llm/codex_11e_wahapedia/RULINGS.md:75.
- **AI today (none):** BATTLE_SHOCK_DENIAL_WEIGHT = 0.0 (AIDecisionMaker.gd:2647) switches off the only battle-shock-denial logic (26057, 26150, 26443, 26480), and that logic values stratagems and targets, not movement. No movement term places a debuff source in range of enemy holders.
- **Engine support:** MissionManager.model_oc (MissionManager.gd:659) to price OC lost under Terror Troops-style auras; the Creeping Dread range constant (CustodesDetachments.gd:146); _unit_oc_at_position (AIDecisionMaker.gd:13054). New query: per friendly debuff source, the enemy holders inside its range from a destination, multiplied by P(fail battle-shock) or the OC cut, times the objective's VP.
- **Value (medium):** Flipping an objective without killing anything is a confirmed 11e lever (F009, F023), but only a few in-engine units carry these abilities.
- **Evidence:**
  - YouTube OKoDYKdWm1E @04:00 (Factions&Fate, F023): 'infiltrated up here just a little bit past my deployment line, but still within range to hand out battle shocks'
  - YouTube efeKiBbPUPM @09:00 (Maelstrom Gaming Studios - Tyranids, F023): 'My Neurolictor battleshocked Volus and the Paladins, which allowed both the Neurolictor and the Hive turret to charge in and precision out'
  - YouTube eokQteHr0Fo @19:00 (6 Plus Plus Gaming, F009): 'if you really need them to not have a secondary uh primary point ... it's a really powerful strategy'
  - 40k/scripts/codex/custodes/CustodesDetachments.gd:140-146, 811-818 (Creeping Dread, 12″)
  - 40k/scripts/codex/space_marines/SMAbilitiesC.gd:785-802 (Terror Troops -1 OC within 3″); 40k/autoloads/MissionManager.gd:690-693 (OC debuff hooks)
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/custodes/RULES.md:70 (Huntress' Eye: 'In your Movement phase, you can select one visible enemy unit within 12" of this unit. That unit makes a battle-shock roll, with -1')
  - _…and 4 more_
- **Absorbed duplicates:** OBJ-40 (Project battle-shock onto the enemy objective holder, then step on)
- **Found by:** youtube, web, first-principles, factions

#### COO-19 — Screen a key friendly with a SMOKE or cover-granting unit

Move a SMOKE unit, or a Speed Freeks unit with Smoky Gubbinz, between the main enemy firing lanes and a key friendly unit, so the friend is not fully visible because of its models. Smokescreen (1CP, at the start of the opponent's Shooting phase) then gives the SMOKE unit and every unit it partly screens the benefit of cover: the attacker's BS is worsened by 1. This is the bucket's 'LoS-blocking for friends'.

- **When:** A key friendly unit must stand in or cross open ground inside enemy range, a SMOKE unit (not battle-shocked) and 1CP are available, or a Smoky Gubbinz unit can stand between them without becoming the easier target itself.
- **Units:** SMOKE units (in shipped lists: Kommandos, Infiltrator Squads, Land Raiders, Venerable Dreadnoughts, Wolf Scouts); Speed Freeks with Smoky Gubbinz (the Deffkilla Wartrike in recon_stomps.json); the units sheltering behind them
- **Move type:** Normal / Advance (screening unit); Normal (sheltered unit)
- **11e rules (corrected):** 15.10 Smokescreen: until the end of the phase, each attack that targets your SMOKE unit, or a unit that is not fully visible to the attacking model because of one or more models in your SMOKE unit, has the target in cover (40k_11th_edition_core_rules.txt:2714-2731). 13.08: cover worsens the attack's BS by 1 (:2280-2290). 06.01: when drawing line of sight, only models in the observing unit and the observed unit are ignored, so other units' models can block it; ordinary models still give no cover unless a rule such as Smokescreen or Smoky Gubbinz says so (:1024-1033). Correction: first-principles#78 said ordinary models do not block line of sight in 11e; 06.01 says they can.
- **AI today (none):** Smokescreen is only scored as a reactive defensive stratagem (evaluate_reactive_stratagem AIDecisionMaker.gd:26752; Smokescreen value at 27098-27103), and 'Smoky Gubbinz' has 0 references in the AI. The screen-protect pass (_compute_screen_position 15028-15086) places a cheap unit 60% of the way toward the nearest enemy with no line-of-sight test and never picks a unit for its SMOKE keyword.
- **Engine support:** OrkEnhancements11e.smoky_gubbinz_cover (OrkEnhancements11e.gd:1665) as the geometry template; TerrainManager._sight_points and model_fully_visible_11e (TerrainManager.gd:1155, 1215); _compute_screen_position (AIDecisionMaker.gd:15028). Engine prerequisite: read covers_screened in the Smokescreen effect (StratagemManager.gd:1918-1927) with a model-blocker test. New query: which enemy shooters' sight lines to friend F pass through unit S's bases when S is at destination D.
- **Value (medium):** Cover takes 1 off the BS of every ranged attack on the key unit, and SMOKE units are in many shipped lists, but the engine only rewards the screened unit for Smoky Gubbinz until Smokescreen's 'screened units' clause is implemented.
- **Evidence:**
  - 40k/autoloads/StratagemManager.gd:5101-5108 (smokescreen_11e has covers_screened: true) and :1918-1927 (cover is applied to the SMOKE unit only; grep shows covers_screened is never read)
  - 40k/autoloads/TerrainManager.gd:1136-1147 (engine sight lines are blocked only by terrain, never by models)
  - 40k/scripts/codex/orks/OrkEnhancements11e.gd:1656-1705 and TerrainManager.gd:1397 (Smoky Gubbinz is implemented with a base-circle blocker test)
  - YouTube aQsog-fkQJ8 @85:00 (Maelstrom Gaming Studios - Tyranids, F030): 'partially obscured ... your storm bolters will be at minus one to hit'
  - Tabletop Battles '11 on 11th' https://www.tabletopbattles.com/11-on-11th-recapping-the-new-warhammer-40k-rules-reveals-through-5-1/ (search snippet: any unit partly hidden by the Smoke unit also gets Benefit of Cover)
  - docs/rules/40k_11th_edition_core_rules.txt:1024-1034, :2714-2730
  - _…and 3 more_
- **Absorbed duplicates:** SUR-31 (Hide behind a large model or a SMOKE unit)
- **Found by:** core-rules, youtube, web, factions, first-principles

#### COO-20 — End a Normal move within range of a proximity-damage ability

Choose a Normal move (not an Advance) that ends with line of sight to a valuable target inside the trigger radius of a proximity-damage ability, often a target your guns cannot reach: EXPLOSIVES (8″, six D6, each 4+ is a mortal wound), Bomb Squigs (when the unit ends a normal move, a visible enemy within 12″ takes D3 mortal wounds on a 3+), Haywire Mine (6″), Neutronium Cascade Mine (3″).

- **When:** A high-value or damaged target is within 12″ (Bomb Squigs), 8″ (EXPLOSIVES, which needs an unengaged and visible target), 6″ (Haywire) or 3″ (Neutronium) of an end position that is safe enough; uses or CP remain; and the unit's main job does not need an Advance.
- **Units:** Any EXPLOSIVES/GRENADES unit; Tankbustas, Breaka Boyz, Kommandos, Squighog Boyz (Bomb Squigs); Incursors, Wolf Scouts (Haywire Mine); Venatari with Verutum Lances (Neutronium)
- **Move type:** Normal (an Advance forfeits EXPLOSIVES and Bomb Squigs)
- **11e rules (verified):** 15.05 EXPLOSIVES: your Shooting phase; one unengaged EXPLOSIVES/GRENADES unit that is eligible to shoot and did not advance; one unengaged enemy unit within 8″ of and visible to the chosen model; six D6, each 4+ is 1 mortal wound (40k_11th_edition_core_rules.txt:2651-2667). 15.01 errata: the Grenade stratagem is the same as Explosives (40k_11th_edition_errata_faq_commentary.md:568). Bomb Squigs: once per turn and twice per battle, triggered when the unit ends a normal move (.llm/codex_11e_wahapedia/ork_abilities_audit.md:32). Haywire Mine (space-marines/wahapedia/Datasheets_abilities.csv:376); Neutronium Cascade Mine (custodes/wahapedia/Datasheets_abilities.csv:139).
- **AI today (none):** These abilities are used only when the unit is already in range: EXPLOSIVES through evaluate_grenade_usage (AIDecisionMaker.gd:25784, called at 16450-16462), and Bomb Squigs and Haywire Mine with a flat 3.0 when offered (OrkAbilities11e.gd:2309-2310). Movement never steers into the radius and may Advance, which forfeits both EXPLOSIVES and Bomb Squigs.
- **Engine support:** StratagemManager.get_grenade_eligible_units (used at AIDecisionMaker.gd:25802); RulesEngine._has_los_to_target_unit (RulesEngine.gd:6607) on a board copy; Measurement model-to-model distance. New query: for units holding such an ability, the expected mortal wounds available at destination D (best visible target within the radius), added as a Normal-move-only bonus.
- **Value (medium):** EXPLOSIVES averages 3 mortal wounds for 1CP from any GRENADES unit, and Bomb Squig units are in shipped Ork lists; the payoff often sits just a few inches from where units end anyway.
- **Evidence:**
  - 40k/autoloads/StratagemManager.gd:5040-5053 (explosives: unengaged, did not advance, 8″)
  - 40k/scripts/codex/orks/OrkAbilities11e.gd:1396, 1414 (Bomb Squigs fires in the unit_ended_normal_move window)
  - 40k/armies/Orks_2000.json, battlewagons.json, ork11e_codex_test.json (Tankbustas, Kommandos)
  - docs/rules/40k_11th_edition_core_rules.txt:2651-2671
  - 40k/autoloads/StratagemManager.gd:5040-5053
  - Grimslate 'All 10 Core Stratagems' https://grimslate.com/blog/core-stratagems-guide-11th-edition (search snippet: the 8″ range and the no-Advance clause mean you plan your move around it)
- **Absorbed duplicates:** OFF-31 (Move EXPLOSIVES/GRENADES units within 8″ without advancing)
- **Found by:** factions, first-principles, core-rules, youtube, web

#### COO-26 — End the Movement phase Hidden to arm hidden-gated rules

Some rules pay off only if the unit is hidden at a set moment: Vanguard Ambushers (a PHOBOS unit hidden at the end of your Movement phase re-rolls wound rolls of 1 this turn), STRIKE FROM THE SHADOWS (+1 S and [LETHAL HITS] when a hidden PHOBOS unit attacks), Kunnin' Infiltrator (if every model is hidden and unengaged at the end of the opponent's Fight phase, the unit can go to strategic reserves) and Shadow Masters (shooting does not break Hidden). End in a light or dense terrain area even when no enemy is within detection range.

- **When:** PHOBOS units that will attack this turn and can reach a light or dense terrain area; Boss Snikrot whenever he is not committed to a charge; any unit whose next activation depends on being hidden.
- **Units:** PHOBOS units (Infiltrators, Incursors, Eliminators, Reivers, Phobos characters), Scout Squads, Boss Snikrot
- **Move type:** Normal / Remain Stationary
- **11e rules (corrected):** 13.09 Hidden: INFANTRY/BEASTS/SWARM within a terrain area that contains light or dense features (errata, 40k_11th_edition_errata_faq_commentary.md:529) whose unit made no ranged attacks this turn or the previous turn (40k_11th_edition_core_rules.txt:2292-2303); a unit is hidden only while every alive model is (.llm/codex_11e_wahapedia/RULINGS.md:357). Texts: Vanguard Ambushers, STRIKE FROM THE SHADOWS and Shadow Masters (space-marines/RULES.md:641, :626, :619); Kunnin' Infiltrator (orks/wahapedia/Datasheets_abilities.csv:51).
  - _Skeptic:_ 'A unit is hidden only while every alive model is' (RULINGS.md:357) contradicts official commentary 01.02.07, Describing Units: a descriptor applies to a unit if at least one of its models meets it, and 'A hidden unit would be a unit that has a model in it that is hidden' (errata_faq:49). So Vanguard Ambushers ('if a friendly Phobos unit is hidden', SM RULES.md:641) and STRIKE FROM THE SHADOWS ('friendly hidden Phobos unit', :626) need only one hidden model. Only Kunnin' Infiltrator explicitly needs 'each model in this unit is hidden' (orks Datasheets_abilities.csv:51). The light/dense errata citation is correct. — 40k_11th_edition_errata_faq_commentary.md:49, 529; space-marines/RULES.md:626, 641; orks/wahapedia/Datasheets_abilities.csv:51
  - _Errata check:_ Per Commentary 01.02.07 a unit is hidden if at least one of its models is hidden, so Vanguard Ambushers and STRIKE FROM THE SHADOWS need only one hidden model (the RULINGS.md 'every alive model' reading is wrong); only Kunnin' Infiltrator, which says 'each model in this unit is hidden', needs all of them. Shadow Masters keeps a unit hidden after it shoots, but that unit cannot Go to Ground (Commentary 13.11.01 designer's note). — Commentary 01.02.07 Describing Units (errata_faq:49); Commentary 13.11.01 Gone to Ground (:539)
- **AI today (none):** AIDecisionMaker.gd never mentions Vanguard Ambushers or STRIKE FROM THE SHADOWS. The Hidden-seeking term ships at WEIGHT_HIDDEN_GAINED = 0.0 (AIDecisionMaker.gd:2633; term at 10306-10314) and is not tied to these abilities. Kunnin' Infiltrator is cancelled (6792-6801), and Shadow Masters takes 'stay hidden' only if the unit already stands where it can be hidden (SMDetachmentsA.gd:1053-1054).
- **Engine support:** TerrainManager.is_model_hidden (TerrainManager.gd:1001, errata-aware); _position_would_be_hidden and _hidden_gain_value (AIDecisionMaker.gd:28515, 28578). New query: per unit, the value of the hidden-gated abilities it holds this turn, added to the hidden bonus at destinations where every model would be hidden.
- **Value (medium):** It gives a concrete, rules-backed payoff to the Hidden term the AI already has but ships switched off; it matters for Phobos-heavy Space Marine lists and Snikrot.
- **Evidence:**
  - 40k/scripts/codex/space_marines/SMDetachmentsA.gd:58-59, 142-144 (Vanguard Ambushers implemented)
  - 40k/scripts/AIDecisionMaker.gd:2633 (WEIGHT_HIDDEN_GAINED = 0.0, shipped off after two inconclusive A/Bs)
  - 40k/scripts/AIDecisionMaker.gd:6792-6801 (Kunnin' Infiltrator placement cancelled)
  - 40k/armies/sm11e_codex_test.json, space_marines.json (Infiltrator, Incursor, Eliminator, Reiver squads); Orks_2000.json (Boss Snikrot)
- **Found by:** factions

#### COO-27 — Take to the skies with FLY units to hop terrain and screens

Declare 'take to the skies' for a FLY unit's normal, advance, fall-back or charge move. Its maximum distance drops by 2″ (none with HOVER), but it ignores vertical distance and can move through all models and every category of terrain. Use it to cross dense ruins, reach upper floors, or hop a screen to reach an objective or target behind it.

- **When:** The direct path is blocked by dense terrain or models and the detour costs more than 2″; or a vertical climb or upper-level end spot is needed. Declare it before rolling for an Advance or charge.
- **Units:** FLY units (jump packs, Deffkoptas, Stormboyz, jetbikes, skimmers, flying monsters); HOVER units pay no distance
- **Move type:** Normal / Advance / Fall Back / Charge with take to the skies declared
- **11e rules (verified):** 21.03 Flying models: declared before moving; -2″ to the maximum distance; vertical distance ignored; can move through all types of model and all categories of terrain feature (40k_11th_edition_core_rules.txt:3358-3376). 24.17 HOVER: no -2″ (:3771-3780). 21.03 FAQ: declare before rolling for an Advance or charge (40k_11th_edition_errata_faq_commentary.md:679-682). FAQ: vertical movement while taking to the skies does not count for [HEAVY] (errata_faq:704-705).
- **AI today (none):** The AI never sends take_to_skies or SET_TAKE_TO_SKIES (grep finds 0 in AIDecisionMaker.gd and AIPlayer.gd). Its 13.06 path gate (_path_blocked_by_solid_terrain_direct, AIDecisionMaker.gd:15390-15403) makes non-infantry FLY units route around dense terrain, while the legacy polygon check lets every FLY unit through (15212-15218).
- **Engine support:** MovementPhase payload.take_to_skies (MovementPhase.gd:1184-1196); MoveType.take_to_skies_modifier (MoveType.gd:95-103); TerrainManager.can_move_through_11e (TerrainManager.gd:1257). New query: for a FLY unit, compare the best reachable destination with and without the take-to-the-skies cap (-2″, or 0 with HOVER), skipping the 13.06 gate in the second case, and send the payload when the second wins.
- **Value (medium):** FLY units are common and dense terrain often blocks their direct line, but in this engine FLY already passes models for free, so the gain is limited to terrain shortcuts.
- **Evidence:**
  - 40k/phases/MovementPhase.gd:1184-1196 (payload.take_to_skies on BEGIN_*) and the SET_TAKE_TO_SKIES validator that follows 7185
  - 40k/phases/MovementPhase.gd:7162-7183 (the 13.06 dense-terrain gate is bypassed only when took_to_skies; the error message tells FLY units to tick 'Take to the skies')
  - 40k/phases/MovementPhase.gd:756-770, 889-903 (any FLY unit is exempt from the model-crossing checks even without taking to the skies, a 10e carry-over that is more permissive than 21.03)
  - 40k/scripts/rules/movetypes/MoveType.gd:95-103 (take_to_skies_modifier)
  - Tabletop Battles Ruleshammer Movement https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-movement (search snippet: a massive boost for Monsters/Vehicles/Mounted with FLY)
  - docs/rules/40k_11th_edition_core_rules.txt:3358-3385
  - _…and 3 more_
- **Absorbed duplicates:** OFF-27 (Take to the skies over screens and walls)
- **Found by:** core-rules, youtube, web, factions, first-principles

#### COO-28 — Drive MONSTER/VEHICLE models straight through enemy infantry screens

On normal and advance moves, MONSTER/VEHICLE models can be moved through friendly and enemy models that are not themselves MONSTER/VEHICLE models, so chaff screens do not stop a tank or monster from reaching its objective or firing spot. It still cannot end on a model or end engaged. Charges and fall-backs get no pass-through.

- **When:** An enemy infantry screen stands between a vehicle or monster and its objective, firing position or blocking spot, and the far side is reachable within M while ending more than 2″ from enemies.
- **Units:** MONSTER, VEHICLE
- **Move type:** Normal / Advance
- **11e rules (corrected):** 17.01: 'Each time you make a normal or advance move with a unit, MONSTER/VEHICLE models in that unit can be moved through friendly and enemy models (excluding other MONSTER/VEHICLE models)' (40k_11th_edition_core_rules.txt:2869-2874). 13.06: dense sections over 2″ still stop non-INFANTRY models moving horizontally (:2161-2180). 09.05: the unit must end unengaged (:1390-1398).
  - _Errata check:_ Per FAQ 17.01 a MONSTER/VEHICLE unit can move through friendly units on every move type, charges and fall-backs included (03.01 lets any model move through friendly models), so only the pass-through of enemy non-MONSTER/VEHICLE models is limited to normal and advance moves; a Desperate Escape fall-back also lets every model move through enemy models (core 09.07). — FAQ 17.01 Moving Monsters and Vehicles (errata_faq:598-599)
- **AI today (none):** The AI's path model checks only MONSTER/VEHICLE bases (mv_models via _get_monster_vehicle_models, AIDecisionMaker.gd:14508, 15897) and relies on engine rejection and staging retries for other enemy bases (B38). Because the engine itself rejects these drive-throughs, nothing can choose them today.
- **Engine support:** Engine fix first: exempt MONSTER/VEHICLE movers from _path_crosses_enemy_bases for non-M/V enemy models on Normal and Advance moves (MovementPhase.gd:756-762, 889-896, 7422-7475). Then let the AI treat non-M/V enemy bases as passable for M/V movers in _compute_movement_toward_target (AIDecisionMaker.gd:14212) while keeping the end-position checks.
- **Value (medium):** Vehicle and monster-heavy lists (Ork Battlewagons, Custodes and Space Wolf Dreadnoughts) are often stopped by chaff, and this is a core 11e change, but it is blocked by an engine gap.
- **Evidence:**
  - 40k/phases/MovementPhase.gd:756-762, 889-896 and 7422-7475: Normal and Advance paths crossing any enemy base are rejected unless the unit has FLY, a Shokk-boosta or Grapnel Launchers, Calistus, or is a Super-Heavy Walker. There is no MONSTER/VEHICLE exemption, so 17.01 appears unimplemented (read, not run)
  - docs/rules/11th_edition_delta_audit.md:150 (row 17.01 marked done 'Pre-existing; preserved', which the code above contradicts)
  - Tabletop Battles 'Rules Deep Dive: Special Unit Types' https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-special-unit-types/ (search snippet: they can pass through enemy models without the Monster/Vehicle keyword)
  - 40k/phases/MovementPhase.gd:756-761, :893-896, :8144-8148, :8231-8235 (non-FLY normal/advance paths may not cross enemy bases; only SUPER-HEAVY WALKER :7434-7437, CALISTUS, SHOKK-BOOSTA and GRAPNEL LAUNCHERS are exempt — no 17.01 exemption, although docs/rules/11th_edition_delta_audit.md:150 marks 17.01 as done)
  - Web search snippet (Tabletop Battles deep dive, unfetched): “Monsters and Vehicles can now move through non-Monster/Vehicle enemy models when making Normal or Advance moves, as long as they end the move legally”
- **Absorbed duplicates:** DEN-22 (Drive a MONSTER/VEHICLE through an enemy infantry screen)
- **Found by:** core-rules, web, youtube

#### COO-31 — Bait and counter-punch: stage a retaliation unit behind a forward unit

Put a tempting forward unit, cheap or durable, where the enemy wants to charge, shoot or score, and stage a hammer (melee or guns) just outside the enemy's reach but within reach of where the enemy will end up after attacking it. Whatever takes the bait is then destroyed next turn or by a Heroic Intervention. Accept losing the bait when the exchange favours you in points or primary VP.

- **When:** Against aggressive melee or reserve-heavy opponents, on contested mid-board objectives, when you have a fast hitter or a strong second line and the bait is cheap or tough.
- **Units:** Bait: cheap or durable scoring units. Hammer: fast melee or shooting units
- **Move type:** Normal / Advance
- **11e rules (verified):** An edition-agnostic tactic. The 11e rules it uses: 11.02, a charge needs an enemy within 12″ (40k_11th_edition_core_rules.txt:1618-1622), and 15.11 Heroic Intervention (:2734-2766).
- **AI today (none):** There is no retaliation-range term. The threat dodge (AIDecisionMaker.gd:28892-28990) only moves units away from threats, and CHARGE_RETALIATION_WEIGHT (1767) is a Charge-phase term for a target fighting back, not staging.
- **Engine support:** _calculate_enemy_threat_data and _evaluate_position_threat (AIDecisionMaker.gd:28695, 28794) to predict where enemies end after attacking the bait; _estimate_melee_damage (19576) and _estimate_unit_ranged_strength (25866) for the hammer; _estimate_unit_value (28003) for the trade. New query: a paired candidate (bait B at D1, hammer H at D2) where H is outside enemy reach now but within reach of the likely end positions of B's attackers next turn.
- **Value (medium):** Trading well wins 11e games (F011, tabling is not a win condition), but the pattern needs two-unit, two-turn planning the AI lacks.
- **Evidence:**
  - YouTube MG546BN181w @47:00 (Grimdark Breakdown, F011): 'You do not have to kill your opponent in 11th edition. A giant condition of winning was tableabling your opponent in 10th'
  - YouTube VqwMdS9MuIY @62:00 (TacticalTortoise 40k, F008): 'it's absolutely worth a genailer squad to eviscerate one of those ranger squads even though it's a trade down'
  - BoLS '40K Tactics: Maximizing your Assault' https://www.belloflostsouls.net/2010/08/40k-tactics-maximizing-your-assault.html (search snippet: put bait where you'll be able to countercharge next turn; older edition)
  - Wertstammer 'Hammer and Anvil' https://wertstammer40k.wordpress.com/2016/11/11/hammer-and-anvil/ (older edition)
  - YouTube sPWC5HujB_Y @19:00 (StrikingScorpion82): “holding objectives, picking on isolated, tying units down, blocking movements ... it's no big deal if they're slain” [F031]
  - YouTube VqwMdS9MuIY @62:00 (TacticalTortoise 40k): “it's absolutely worth a genailer squad to eviscerate one of those ranger squads even though it's a trade down” [F008]
- **Absorbed duplicates:** DEN-31 (Bait with an expendable unit to pull an enemy unit out of position)
- **Found by:** web, first-principles

#### COO-07 — End your move in range of the friendly unit your support ability should target

Plan the support model's move, and the order of moves, so a 'select one friendly unit within X″' ability lands on the best recipient: un-shock and rile up another Ork unit, repair a damaged vehicle, hand out a doctrine, or heal infantry. Riling a unit before it moves lets it Advance and still charge.

- **When:** A friendly unit is battle-shocked (OC '-', cannot be targeted by its own stratagems) or is about to Advance and charge; a damaged vehicle is about to shoot or fight; or a unit needs a doctrine this turn. Use the start-of-move window when the recipient is already in range and the end-of-move window when the support model must close in first. Move the support model before the recipient.
- **Units:** Warboss, Warboss in Mega Armour, Nazdreg (Intimidating Motivation, 6″); Beastboss (Keep Huntin'!); Deffkilla Wartrike (Get Back in da Race!); Mek (Clever Know-wotz, 3″); Rukkatrukk (Delicious Eating Squigs, 3″); Techmarine, Iron Priest, Iron Father Feirros (3″ repair); Marneus Calgar (9″); Guilliman (12″); Chaplain (6″); Gauntlet Captain (Damocles-class Uplink, 6″ of the transport); Custodes Inspirational Exemplar (9″)
- **Move type:** Normal (support model, at the start or end of its move), sequenced before the recipient's move
- **11e rules (verified):** Intimidating Motivation (once per battle round, per army): 'In your Movement phase, at the start or end of this unit's move, you can select one friendly ORKS unit within 6″ of this unit. That unit: is no longer battle-shocked; is riled up until the start of your next turn.' (.llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:7). Riled-up effects come from the Waaagh! army rule (orks/RULES.md:76). 01.07: a battle-shocked unit has OC '-', cannot be targeted by its own player's stratagems and cannot start actions (40k_11th_edition_core_rules.txt:212-220). 01.04.01 'within' (40k_11th_edition_errata_faq_commentary.md:79-81).
- **AI today (partial):** Only the self case is modelled. _rile_pending_on_selection (AIDecisionMaker.gd:3101-3112) lets a unit whose own Attached leader holds Keep Huntin'!, Intimidating Motivation or Get Back in da Race! Advance and still charge. When the card is offered it gets a flat score: 2.5 for the riling abilities (OrkAbilities11e.gd:2316-2317), 2.0 for Clever Know-wotz, 2.0 for Master of the Forge and Blessings of the Omnissiah, 1.5 for Author of the Codex (SMAbilitiesA.gd:2262-2266). The movement planner never moves a support model toward a recipient, and move order (7119-7147) ignores it.
- **Engine support:** OrkAbilities11e.group_holder and army_used_this_round (as used at AIDecisionMaker.gd:3109-3111); _unit_oc_at_position (13054) for the OC an un-shock gives back. New queries: per support ability, its range, trigger (start or end of move) and recipient filter; a pairwise term for the value of the best recipient within X″ of a destination; and a move-order rule that moves the support model before the recipient.
- **Value (medium):** Un-shocking returns OC and stratagem access, and riling gives a second unit advance-and-charge, but only lists with these characters benefit and the recipient must also be well placed.
- **Evidence:**
  - .llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:7 (Intimidating Motivation), :211 (Keep Huntin'!), :56 (Clever Know-wotz)
  - .llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:179, :321, :874, :167, :393; space-marines/RULES.md:611 (Damocles-class Uplink); custodes/RULES.md:82 (Inspirational Exemplar)
  - 40k/scripts/codex/orks/OrkAbilities11e.gd:1396 (intimidating_motivation offered in the unit_ended_normal_move window)
  - 40k/armies/orks.json, orks_taktikal.json, tutorial_orks.json, ork11e_codex_test.json (Warbosses in shipped lists)
- **Found by:** factions

#### COO-09 — Move as a mutually supporting group; do not arrive piecemeal

Keep units within support range of each other (overlapping fire, counter-charge reach, shared auras), and time arrivals so several units reach a contested area in the same turn. Hold fast units back rather than letting them arrive alone. At plan level: overload one flank and refuse the other.

- **When:** Elite armies with few units (Custodes), any army attacking a defended area, or whenever the lead unit would be alone inside enemy threat range this turn. Relax it in rounds 4-5 and when cards pay for spreading out (table quarters, No Man's Land counts).
- **Units:** All; especially elite bricks and fast units that race ahead
- **Move type:** Normal / Advance (including deliberately short moves)
- **11e rules (verified):** A tactical principle; the rules it relies on are 15.11 Heroic Intervention reach (40k_11th_edition_core_rules.txt:2734-2766) and 22.01 auras (:3407-3416).
- **AI today (partial):** Only objective-control filters keep units from going alone: LONE-TRIP keeps fragile units off objectives where they would stand alone and outnumbered (FIX_LONE_TRIP = 1.0, AIDecisionMaker.gd:1631-1640, 10824-10834), and units left over from the passes support only objectives the army holds or is heading to (11655-11672); FAR-TRIP is OFF. The support pass actively spreads spare units (SUPPORT_STACK_PENALTY 3.5 per unit already committed there, 2580, applied 14112), and the threat model has no friendly-proximity term (28695-28990).
- **Engine support:** _calculate_enemy_threat_data and _evaluate_position_threat (AIDecisionMaker.gd:28695, 28794): add friendly support within X″ as threat mitigation; the COORD-2/4 intent ledger (3977-4075) tells where friends will end; _find_best_remaining_objective (14098). New queries: the number of friendly units, and their damage, that could retaliate at a destination next turn; and arrival-turn alignment across units heading to the same area.
- **Value (medium):** A core strategic principle that stops units being isolated and traded one at a time, but it is a posture weight that must be tuned against spreading out for cards.
- **Evidence:**
  - YouTube EAqaLgAudQo @216:00 (Tabletop Titans, F022): 'custodians are just not designed that way. They want to be hanging out together just few units but just wrecking ball'
  - research/youtube/ai_learnings.json F022 (player_opinion, medium); research/youtube/profiles/adeptus_custodes.json SUPPORT_STACK_PENALTY 1.5 (draft)
  - research/ai_feasibility_2026-08-09/research_commercial-practice.md:11 (Field of Glory II AI 'drifts piecemeal into concentrations')
  - .llm/ai-overhaul-todo.md:1059-1062 (posture examples 'castle center', 'refuse left flank')
  - YouTube EAqaLgAudQo @216:00 (Tabletop Titans): "custodians are just not designed that way. They want to be hanging out together just few units but just wrecking ball" (ai_learnings.json F022)
  - https://wellspokenman.wordpress.com/2016/10/28/deployment-interlocking-fields-of-fire-and-avenues-of-approach/ (older edition: split into two groups on opposite sides)
- **Absorbed duplicates:** OBJ-30 (Concentrate force on a subset of objectives or refuse a flank)
- **Found by:** youtube, first-principles, web

#### COO-14 — Send OC-light or expendable units to positional cards; keep OC for objectives and actions

Positional cards (Behind Enemy Lines, Display of Might, Centre Ground, Outflank, Engage on All Fronts) count units regardless of OC. Assign OC-0 and low-OC units, Lone Operatives and cheap units to those positions, and keep high-OC units for objectives and actions, which need OC 1+.

- **When:** Every turn in which positional and objective cards compete for the same units. Lone Operatives suit end-of-opponent's-turn positions, since they cannot be seen from beyond 12″.
- **Units:** OC-0 characters and vehicles, Lone Operatives and chaff for positional jobs; OC units for objectives and actions
- **Move type:** Normal / Advance
- **11e rules (verified):** Card texts count 'friendly units (excluding AIRCRAFT and battle-shocked units)' (40k/data/40kdc/missionCards.json: display-of-might :2246, centre-ground :2311, outflank :2339, engage-on-all-fronts :2417, behind-enemy-lines :2679). 16.01: a unit with OC 0 or '-' cannot start an action (40k_11th_edition_core_rules.txt:2806-2814). 24.24 Lone Operative (:3813-3830). 23.02 AIRCRAFT movement (:3503-3515).
- **AI today (partial):** Positional terms (B17, AIDecisionMaker.gd:10378-10499) are unit-agnostic bonuses on the destinations of objective trips, and OC is priced separately (oc_efficiency, B06), so no pass splits positional jobs from OC jobs. RI-QUARTER skips battle-shocked and AIRCRAFT units (_ri_quarter_vp 12894-12900).
- **Engine support:** SecondaryMissionManager._is_unit_excluded (SecondaryMissionManager.gd:2891-2917); _get_table_quarter and _get_covered_quarters (AIDecisionMaker.gd:24250, 24260); _ri_quarter_vp (12894). New query: positional-card destinations that are not objectives (zone, quarter, edge and centre points) as candidates, with a role cost equal to the unit's OC value elsewhere.
- **Value (medium):** It turns otherwise idle OC-0 units into VP and keeps OC where it counts, but it is a missions-bucket assignment problem rather than a pure movement intent.
- **Evidence:**
  - 40k/data/40kdc/missionCards.json behind-enemy-lines text: 'Score per friendly unit (excluding AIRCRAFT and battle-shocked units) wholly within the opponent's deployment zone'
  - 40k/data/40kdc/missionCards.json display-of-might, centre-ground, outflank, engage-on-all-fronts (same exclusion; units counted regardless of OC)
  - 40k/autoloads/SecondaryMissionManager.gd:2891-2917 (_is_unit_excluded)
- **Found by:** missions

#### COO-15 — Re-task battle-shocked units as bodies, not scorers

A battle-shocked unit has OC '-', cannot be targeted by its own player's stratagems, cannot start or complete actions, does not count for most positional cards, and must Desperate Escape if it falls back. Move it to jobs that need only bodies (move blocks, charge screens, deep-strike denial) or to safety, and hand its scoring job to another unit.

- **When:** After a failed battle-shock roll, a combat disembark or a Desperate Escape; also for units at or below half strength, which will test in the next Command phase.
- **Units:** Battle-shocked units, or units likely to become battle-shocked
- **Move type:** Normal / Advance (a Fall Back would be a forced Desperate Escape)
- **11e rules (corrected):** 01.07 battle-shocked effects (40k_11th_edition_core_rules.txt:212-220). 08.03: a unit stays battle-shocked until it passes a roll, and units at or below half strength must roll (:1244-1256). 09.07: Desperate Escape is mandatory when battle-shocked (:1423-1426). Card exclusions 'excluding AIRCRAFT and battle-shocked units' (40k/data/40kdc/missionCards.json, e.g. behind-enemy-lines :2679).
  - _Errata check:_ Per FAQ 01.07 (repeated under 16.01), a unit with a rule that lets it start actions while battle-shocked (e.g. Custodes readied with Conservai Ka'tah) can carry on with an action it started even if it becomes battle-shocked afterwards. Also count an emergency disembark as a battle-shock source (18.05): under the 18.05 errata, models that cannot be set up unengaged are now set up engaged instead of destroyed, so those battle-shocked survivors can only leave combat by a Desperate Escape. — FAQ 01.07 Battle-shock Rolls (errata_faq:141-142; repeated as FAQ 16.01 Performing Actions :593-594); 18.05 errata Emergency Disembark Move (:609)
- **AI today (partial):** _unit_oc_at_position returns 0 for battle-shocked units (AIDecisionMaker.gd:13051-13060), which lowers their capture scores, and _ri_quarter_vp skips them (12896). But screen, denial and corridor-block selection uses printed points and printed OC only (_is_screening_candidate 14911-14925), so a battle-shocked unit is never deliberately re-tasked as a body, and positional secondary terms (10378-10499) still pull it.
- **Engine support:** flags.battle_shocked; _is_screening_candidate (AIDecisionMaker.gd:14911) and the pass-3 screen, denial and block passes (11527-11649). New query: a role filter that moves battle-shocked units from capture and positional candidates to screen and block candidates and raises their screen score.
- **Value (medium):** Battle-shock happens often in 11e and a shocked unit has no scoring value, so moving it onto body jobs is pure gain, but the AI already zeroes its OC.
- **Evidence:**
  - YouTube ewxyBDMvC64 @23:00 (The Six Machine, F009): 'it is more likely that you will get battleshocked and potentially stay battleshocked'
  - 40k/scripts/rules/movetypes/FallBackMove.gd:52-69 (battle-shocked units are forced into Desperate Escape)
  - 40k/autoloads/SecondaryMissionManager.gd:2891-2917 (_is_unit_excluded)
  - /home/user/warhammer-40k-godot/40k/scripts/data/SecondaryMissionData.gd:51-86 (Behind Enemy Lines / Engage on All Fronts rows exclude Battle-shocked units)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:13432-13439 (_unit_alive_oc sums MissionManager.model_oc, which has no battle-shock check: MissionManager.gd:659) vs MissionManager.gd:753-768 (_unit_oc_in_range zeroes shocked units)
- **Absorbed duplicates:** OBJ-18 (Use battle-shocked units as bodies, not scorers)
- **Found by:** missions, first-principles, core-rules

#### COO-16 — Pick destinations that satisfy several cards at once and split conflicting geometry

Score each destination by the sum of the card values it satisfies: an enemy-side expansion objective can count for Forward Position, Determined Acquisition, Secure No Man's Land, Display of Might, an uncovered quarter and a flank edge at once. Also detect conflicting geometry, so different units take each side: Centre Ground needs a unit within 3″ of the centre, while quarter presence needs one more than 6″ from it, and an action actor cannot shoot while the holder keeps OC.

- **When:** Two or more cards are active; it is always worth computing.
- **Units:** All
- **Move type:** Normal / Advance
- **11e rules (verified):** Card geometries in 40k/data/40kdc/missionCards.json (centre-ground :2311 'within 3 inches of the centre of the battlefield'; engage-on-all-fronts :2417 'wholly within it and not within 6 inches of the centre'). 01.04.05 table quarters (40k_11th_edition_errata_faq_commentary.md:95-97). Mission zones in docs/rules/11th_edition_missions_gdm2026.md.
- **AI today (partial):** Secondary terms are additive per objective destination (AIDecisionMaker.gd:10378-10499), alongside primary terms (10351-10376) and RI-QUARTER VP (12894-12940), so an objective that serves several cards already scores higher. But only objectives are candidates (B06), the enemy-zone centre is hard-coded to Search and Destroy corners (10394-10400), and no conflict check splits incompatible geometry across units.
- **Engine support:** _get_secondary_awareness (AIDecisionMaker.gd:24239), _get_table_quarter and _get_covered_quarters (24250, 24260), _get_deployment_zone_polygon_pixels (24856). New queries: destination candidates that are not objectives (zone, quarter, edge and centre points), scored by the sum of card predicates; and a pairwise conflict check between the card roles assigned to units.
- **Value (medium):** Multi-card destinations are common and cheap to score, but most of the value is already captured by the additive objective terms.
- **Evidence:**
  - 40k/data/40kdc/missionCards.json (centre-ground, engage-on-all-fronts, outflank, display-of-might, behind-enemy-lines texts)
  - 40k/scripts/AIDecisionMaker.gd:10377-10500 (current per-objective additive secondary terms)
- **Found by:** missions

#### COO-18 — Stay engaged on purpose

Remain stationary while engaged when staying is worth more than falling back. While engaged the unit cannot be shot by other enemies (unless it is a MONSTER/VEHICLE), it keeps a dangerous enemy shooter locked out of normal shooting and actions, a MONSTER/VEHICLE keeps shooting with close-quarters shooting, and a battle-shocked unit avoids the forced Desperate Escape.

- **When:** The unit will survive the Fight phase and is pinning something valuable (a lock-target shooter, an objective holder); falling back would cost shooting, actions or hazard rolls; or it is a MONSTER/VEHICLE with good guns.
- **Units:** Engaged units, especially tar-pits and MONSTER/VEHICLE units
- **Move type:** Remain Stationary (engaged)
- **11e rules (verified):** 04.02: targets must be unengaged (40k_11th_edition_core_rules.txt:639-644). 10.06 close-quarters shooting: MONSTER/VEHICLE units can shoot while engaged, at -1 to hit except [CLOSE-QUARTERS] weapons against units they are engaged with (:1522-1547). 17.03 (:2898-2910; errata excludes [BLAST], 40k_11th_edition_errata_faq_commentary.md:608). 09.07 (:1417-1442). 16.01: engaged units cannot start actions (:2810).
- **AI today (partial):** _decide_engaged_unit (AIDecisionMaker.gd:11958-12179) stays only for objective OC (on-objective holds at 12050-12090) or because it is the sole holder. It never values being unshootable, locking a lock-target shooter (lock_targets built at 3789-3805 are not read there), or a MONSTER/VEHICLE's close-quarters shooting. SURVIVAL_FALL_BACK_BONUS and SURVIVAL_HOLD_BONUS are unused constants (2788-2789).
- **Engine support:** lock_targets from _build_phase_plan (AIDecisionMaker.gd:3789-3805); _estimate_unit_ranged_strength (25866) for the locked enemy's lost shooting; CloseQuartersShooting.gd for M/V output while engaged; _estimate_incoming_melee_damage (12350). New query: a hold value equal to the enemy's lost shooting and actions plus our close-quarters shooting plus the shooting we avoid, compared with the fall-back value in COO-05.
- **Value (medium):** A frequent decision with a clear payoff (locking a shooter, avoiding Desperate Escape hazards), but it overlaps the engaged-bucket logic that already exists.
- **Evidence:**
  - YouTube F5TL7LhZJlY @13:00 (40K Dirtbags, F017): 'He spends a CP realizing after the fact that you can't fall back and shoot with vehicles. It's only infantry'
  - YouTube F5TL7LhZJlY @23:00 (40K Dirtbags, F024): 'both of them would have to pass a seven up to fall back'
  - YouTube HER6VzUGO60 @658:00 (WarGames Live, F015): 'We'll charge the truck in just to lock you in because we can still touch you and still be on the objective'
  - research/youtube/ai_learnings.json F015, F017, F024
  - docs/rules/40k_11th_edition_core_rules.txt:628-642, :1522-1545, :2894-2909
  - 40k/scripts/rules/shootingtypes/ShootingType.gd:45 target_allowed; 40k/scripts/rules/shootingtypes/CloseQuartersShooting.gd:43 target_allowed
  - _…and 13 more_
- **Absorbed duplicates:** SUR-06 (Stay engaged as a shield from enemy shooting (decline to fall back)); SUR-18 (Stay locked in combat when falling back would forfeit the turn); DEN-15 (Stay engaged to keep an enemy unit locked (decline to fall back)); OFF-09 (Stay engaged with a MONSTER/VEHICLE and keep shooting)
- **Found by:** web, core-rules, first-principles, youtube

#### COO-22 — Clear lanes and sequence your own moves

Order the army's moves so units do not block each other: move units out of corridors others need, let fast units through gaps before screens close, move transports and their cargo in the right order, and move screens last when they must seal around others. In 11e friendly models never block movement (only end positions cannot overlap), but this engine still blocks paths through friendly MONSTER/VEHICLE bases, so lane order matters most around friendly vehicles.

- **When:** Congested deployment zones and corridors, and armies that mix vehicles with infantry (Ork Battlewagons and Trukks); also whenever a screen must close a gap other units are using.
- **Units:** All
- **Move type:** other (move ordering for Normal / Advance / Disembark)
- **11e rules (corrected):** 03.01: a model can be moved through friendly models, its base cannot be moved through enemy models, and no model may end on another model (40k_11th_edition_core_rules.txt:386-416). 17.01 FAQ: a MONSTER/VEHICLE unit can move through friendly units on any move type (40k_11th_edition_errata_faq_commentary.md:596-599). Correction: first-principles#76 left the friendly MONSTER/VEHICLE block as possibly 11e. Local 11e text lets every model move through friendly models; the engine block is a 10e carry-over.
- **AI today (partial):** Move order is fixed: engaged units first, then units that disembarked this phase, then normal units, with transport vehicles last, each tier front-to-back by board y (AIDecisionMaker.gd:7119-7147; _move_tier 7657-7665). The placement ladder retries collisions (B38, 14520-14722). The order is not intent-aware (screens are not moved last, lanes are not cleared for a specific unit) and it assumes a vertical layout with P1 at the top and P2 at the bottom.
- **Engine support:** _move_tier and _build_move_order (AIDecisionMaker.gd:7657, 7666); _path_crosses_monster_vehicle (15957). New query: a dependency order built from whether unit A's planned path or end spot overlaps unit B's current or planned footprint. Engine fix worth more than the AI change: let models pass friendly MONSTER/VEHICLE bases (03.01, 17.01 FAQ) at MovementPhase.gd:764-770 and 898-903, and drop the mirror at AIDecisionMaker.gd:14508.
- **Value (medium):** The friendly-vehicle block is the largest recorded source of staging failures, but the main fix belongs in the engine; after it, sequencing matters only for end spots and screens.
- **Evidence:**
  - 40k/phases/MovementPhase.gd:764-770, 898-903 ('10e Errata: Cannot move across MONSTER or VEHICLE models (friendly or enemy)') and 7477-7531
  - 40k/scripts/AIDecisionMaker.gd:15944-15957 comment: the friendly Battlewagon block was 'the single largest movement-staging failure in the benchmark: 50 in one 4-round game, 23 of 25 against the Battlewagon'
  - 40k/scripts/AIDecisionMaker.gd:14508 (the AI mirrors the block; FLY units are exempt)
- **Found by:** first-principles

#### COO-29 — Use a move-through or MOBILE grant to shortcut models and terrain

Spend an ability-granted path, rather than detouring, to reach a hidden unit in dense terrain, an objective behind a ruin, or a target behind chaff. The SUPER-HEAVY WALKER core ability moves through models (except TITANIC) and over sections 4″ or lower, and can take the MOBILE gamble (become MOBILE for the move and pass dense terrain, but battle-shocked on a D6 roll of 1). Faction grants include STOMPING JUGGERNAUT (Ork Walkers become MOBILE), UNSTOPPABLE MOMENTUM (Custodes Dreadnoughts), FENRISIAN FEROCITY (Space Wolf Mounted and Walkers), Calistus ka'tah (through all models), Get Out da Way! (Nobz charge through non-M/V models), Grapnel Launchers (Reivers) and Shokk-boosta (Big Mek advance).

- **When:** The straight line to the objective or target crosses dense terrain or a screen, the detour costs the charge or the objective this turn, and the grant's cost (CP, a hazard roll per model for the Shokk-boosta, a 1-in-6 battle-shock for the MOBILE gamble) is acceptable. Skip the MOBILE gamble when the walker's OC is needed.
- **Units:** SUPER-HEAVY WALKERs (Stompa, Gorkanaut, Morkanaut), Ork Walkers, Nobz, Big Mek, Custodes with Calistus and Custodes Dreadnoughts, Space Wolf Mounted and Walkers, Reivers
- **Move type:** Normal / Advance / Fall Back (Charge for Get Out da Way!)
- **11e rules (verified):** 24.35 SUPER-HEAVY WALKER (40k_11th_edition_core_rules.txt:3940-3967). 13.06: only INFANTRY/BEASTS/SWARM/MOBILE pass dense terrain horizontally; other models only over sections 2″ or lower (:2161-2180). 03.01.02: a 'move through models' rule lets a model pass enemy models while every other restriction still applies (40k_11th_edition_errata_faq_commentary.md:226-228). Grant texts: .llm/codex_11e_wahapedia/orks/RULES.md:134 (STOMPING JUGGERNAUT), orks/wahapedia/Datasheets_abilities.csv:80 (Get Out da Way!), custodes/RULES.md:63, :129, space-marines/RULES.md:475, space-marines/wahapedia/Datasheets_abilities.csv:607.
- **AI today (partial):** Only FENRISIAN FEROCITY is used, and only when dense terrain blocks the straight line (SWCodexMovement.gd:169-174). Calistus is taken only for fall-backs (CustodesKatah.gd:720-724). STOMPING JUGGERNAUT scores 0.0 (OrkCodexMovement.gd:288-291), UNSTOPPABLE MOMENTUM and INEXORABLE 0.0 (CustodesCodexMovement.gd:268-269), Shokk-boosta 0.0 (OrkAbilities11e.gd:2323-2324). The AI never sends shw_mobile_gamble, and its path model routes a Super-Heavy Walker around friendly MONSTER/VEHICLE bases that the engine would let it cross (no SHW exemption at AIDecisionMaker.gd:14508).
- **Engine support:** MovementPhase._shw_moves_through_models, _terrain_rule_keywords, _o6_moves_through_models, _cus11e_moves_through_all_models (MovementPhase.gd:7105-7148); TerrainManager.can_move_through_11e with extra keywords (TerrainManager.gd:1257). New query: the AI path model per grant (SHW passes non-TITANIC models and sections 4″ or lower; MOBILE passes dense terrain), with each grant's cost compared against the detour.
- **Value (medium):** A Stompa is in a shipped Ork plan list and the AI routes it as an ordinary vehicle; the other grants are narrower.
- **Evidence:**
  - 40k/phases/MovementPhase.gd:7141-7148 (_shw_moves_through_models), 1197-1201 (payload.shw_mobile_gamble), 7120-7139 (MOBILE grants feed the 13.06 gate), 7105-7114 (Shokk-boosta, Grapnel Launchers, Calistus)
  - 40k/scripts/stratagems/ork_codex/OrkCodexMovement.gd:288-291 (STOMPING JUGGERNAUT scored 0.0: 'The AI movement planner does not path through dense terrain')
  - 40k/armies/recon_stomps.json (a Stompa in a shipped Ork plan list)
  - docs/rules/11th_edition_delta_audit.md (24.35 row, ISS-073)
- **Found by:** core-rules, web, factions

#### COO-N01 — Choose where the Advance goes after seeing the roll _(added by completeness review)_

In 11e the advance roll is made before any model moves, and once rolled the unit has made an Advance: no charge, no actions, only [ASSAULT] shooting, whatever distance it then uses. So plan the Advance as a contingent move. A high roll reaches the objective, action site, quarter or staging spot. A low roll should switch to the best fallback within the actual distance: the nearest Hidden, cover or out-of-sight spot, a screening line, or a position outside enemy charge reach. It should not stop short in the open on the original heading. Also decide before rolling whether a bad result is worth a Command Re-roll, and declare take to the skies before the roll (FAQ 21.03).

- **When:** Any Advance whose payoff depends on distance (reaching an objective, action area, quarter or charge reach) and where a short roll would leave the unit exposed.
- **Units:** Any unit that Advances: fast infantry, Orks with advance re-rolls, transports
- **Move type:** Advance
- **11e rules (verified):** 09.06 'BEFORE MOVING: Make an advance roll by rolling one D6' and the after-moving restrictions (40k_11th_edition_core_rules.txt:1401-1415). 15.02 Command Re-roll on an advance roll (:2651-2670). FAQ 21.03 declare take to the skies before rolling (40k_11th_edition_errata_faq_commentary.md:679-682).
- **AI today (partial):** AIPlayer.recompute_destinations_for_cap (AIPlayer.gd:1697-1716) re-plans for the rolled distance but keeps the pre-roll heading (_advance_heading_target), so a roll of 1-2 stops short on the same line. The Advance was planned at M+2 (AIDecisionMaker.gd:7205, :7244; AIPlayer.gd:1678), while assignment scoring uses ADVANCE_EXPECTED_EXTRA_INCHES = 3.5 (AIDecisionMaker.gd:2256).
- **Engine support:** MovementPhase pauses after the roll for the Command Re-roll decision. AIPlayer already hooks in at AIPlayer.gd:1670-1693. _advance_reach_chance (AIDecisionMaker.gd:13247) and _prob_sum_d6_at_least (:12788) price roll outcomes. New: re-run the unit's own move choice with the rolled distance (single-unit focus, as _suggest_focus_unit_id does at :7158-7166), plus a fallback-spot generator (cover, Hidden, out of reach) for when the main target is out of reach.
- **Value (medium):** Every Advance currently stakes a whole turn of exposure on one D6; choosing after the roll removes the worst outcomes cheaply.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1401-1415 (09.06)
  - AIPlayer.gd:1674-1693 already pauses after the roll and recomputes destinations, so the hook exists
- **Found by:** cross_bucket_critic

#### COO-33 — Stay within reach of a friendly enabler for reactive protection or extraction

End a protected unit's move close to the unit that enables a reaction: a Gretchin unit within 3″ of an Orks Infantry mob (GROT SHIELDS turns hits into mortal wounds on the Gretchin), every model within 3″ of a Repulsor (Combat Embarkation pulls the charge target inside), wholly within 6″ of a transport at the end of the Fight phase (KEEP IT RUNNIN', DUTY IS NEVER DONE re-embark the unit), or Battleline units within 12″ of a Laurels of Vigilance bearer (Fire Overwatch or Heroic Intervention costs 1CP less). Keep the enabler itself out of easy reach.

- **When:** A valuable Ork mob is about to be shot; infantry next to a Repulsor faces a likely charge; a melee unit will finish its fight near its transport and should be re-delivered next turn; Battleline units are likely to need cheap Overwatch.
- **Units:** Gretchin with Orks Infantry (Runt Swarm), Repulsor and Adeptus Astartes cargo, Ork Infantry and transports (Blitz Brigade), Adeptus Astartes Infantry and transports (Gauntlet), Battleline near a Laurels of Vigilance bearer
- **Move type:** Normal / Advance
- **11e rules (corrected):** Stratagem and datasheet texts: GROT SHIELDS 'One friendly Gretchin unit within 3″ of that ORKS INFANTRY unit' (.llm/codex_11e_wahapedia/orks/RULES.md:222); KEEP IT RUNNIN' 'wholly within 6″ of a friendly Transport' (orks/RULES.md:201); DUTY IS NEVER DONE (space-marines/RULES.md:613); Laurels of Vigilance, 12″ (space-marines/RULES.md:709); Combat Embarkation, 'If every model in that unit is within 3″ of this TRANSPORT' (space-marines/wahapedia/Datasheets_abilities.csv:615).
  - _Errata check:_ Per Commentary 18.02.01 a unit is only able to embark (KEEP IT RUNNIN'; DUTY IS NEVER DONE says 'eligible to embark') if it still meets 18.02's unmodified conditions, including not having been set up on the battlefield this turn, so a unit that disembarked or arrived from reserves this turn cannot be re-embarked by these stratagems at the end of that turn's Fight phase. Neither stratagem says the unit may embark in a turn it disembarked, which per FAQ 18.02 is what lifts that restriction. — Commentary 18.02.01 Able To Embark (errata_faq:626); FAQ 18.02 Embarking (:621-622)
- **AI today (none):** These reactions are scored only when offered (OrkCodexShootingReactive.gd:250-251; SMAbilitiesC.gd:1928-1929; SMCodexAMovement.gd:292-294). No movement term keeps units within these radii, and the AI never embarks during play (inventory B44 and gap 6).
- **Engine support:** The codex window predicates hold the radii (the scripts cited above); Measurement model-to-model distance; _estimate_incoming_melee_damage (AIDecisionMaker.gd:12350) for what the reaction prevents. New query: per protected unit, the enablers it could stand within X″ of, as a destination bonus equal to the expected damage prevented or the extraction value.
- **Value (low):** Each case needs a specific detachment or datasheet and the payoff depends on what the enemy does, though GROT SHIELDS can be large for Runt Swarm Orks.
- **Evidence:**
  - 40k/scripts/stratagems/ork_codex/OrkCodexShootingReactive.gd:250-251 (GROT SHIELDS scored at use)
  - 40k/scripts/codex/space_marines/SMAbilitiesC.gd:1928-1929 (Combat Embarkation 2.5 at use)
  - 40k/scripts/codex/space_marines/SMCodexAMovement.gd:292-294 (DUTY IS NEVER DONE 2.0 when no enemy within 9″)
- **Found by:** factions

#### COO-34 — Switch off enemy Overwatch with a denier during your Movement phase

Move an Overwatch denier so that, before the end of your Movement phase, it is within range of and can see the enemy unit whose Overwatch threatens your assault lane: Drive-by Skorchin' (a visible non-MONSTER/VEHICLE enemy within 6″ cannot be targeted with Fire Overwatch this turn) or Murderous Hurricane (a visible enemy within 12″ cannot make snap-shooting attacks). The rest of the army can then cross that unit's sight lines safely.

- **When:** The opponent has CP and an unengaged high-volume shooter within 24″ of your planned destinations, your key units must cross its sight lines this turn, and the denier can reach it.
- **Units:** Warbuggies (Drive-by Skorchin'), Njal Stormcaller (Murderous Hurricane)
- **Move type:** Normal / Advance (the denier only needs to end in range before the phase ends)
- **11e rules (corrected):** 15.08: Fire Overwatch is used at the end of the opponent's Movement phase (40k_11th_edition_core_rules.txt:2735-2748), so it resolves after all your moves; the denier does not have to move first, only to have used its ability on the right enemy by then. Correction: factions#16 said 'move the denier first'. Texts: Drive-by Skorchin' (.llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:125); Murderous Hurricane (psychic, battle-shocked on a 1) (space-marines/wahapedia/Datasheets_abilities.csv:301).
- **AI today (none):** Drive-by Skorchin' and Murderous Hurricane get flat scores of about 1.5 when offered (OrkAbilities11e.gd:2321; SWAbilities11e.gd:1834), with no link to which enemy carries the Overwatch threat. The Overwatch exposure term ships OFF and ignores denial (OVERWATCH_EXPOSURE_PENALTY = 0.0, AIDecisionMaker.gd:2662; helper 28660-28688).
- **Engine support:** _overwatch_exposure_penalty (AIDecisionMaker.gd:28660-28688) to find the enemy unit carrying the largest Overwatch threat on our destinations; _estimate_unit_overwatch_damage (19521). New query: whether a denier can end within 6″ or 12″ of that unit with visibility, and the exposure saved for the rest of the army.
- **Value (low):** Only two in-engine units can deny Overwatch, and the value depends on an exposure term that is currently switched off.
- **Evidence:**
  - 40k/scripts/codex/orks/OrkAbilities11e.gd:1424 (Drive-by Skorchin' implemented) and :2321 (scored 1.5 at use)
  - 40k/scripts/codex/space_wolves/SWAbilities11e.gd:1462, 1834 (Murderous Hurricane 12″, scored at use)
  - YouTube eUpeWbN7gF4 @28:00 (StrikingScorpion82, F004): 'overwatch is done at the end of the opponent's movement phase ... it's a decision we can make uh once movement's done'
- **Found by:** factions

#### COO-36 — Take the exposed direct lane with Overwatch-immune units

Units that cannot be targeted by snap shooting can end in the open, inside enemy sight lines, at no Overwatch cost, so give them the direct exposed route and send other units through the covered one.

- **When:** A snap-immune unit (Seal of Shrouding, Linebreaker Onslaught after disembarking, Combat Deployment cargo, GOLDEN LIGHT OF THE MOIRAIDES on the turn it ingresses) must cross open ground covered by enemy Overwatch.
- **Units:** Phobos units with Seal of Shrouding; Gauntlet Linebreaker Onslaught and Grav-Assault Combat Deployment cargo; Dread Host reserves
- **Move type:** Normal / Advance / Disembark / Reserves arrival
- **11e rules (verified):** 15.08 and 15.09 (40k_11th_edition_core_rules.txt:2735-2768). Texts: Seal of Shrouding, 'Enemy units cannot target this unit with snap shooting attacks' (.llm/codex_11e_wahapedia/space-marines/RULES.md:643); Linebreaker Onslaught (space-marines/RULES.md:610); Combat Deployment (custodes/RULES.md:220); GOLDEN LIGHT OF THE MOIRAIDES (custodes/RULES.md:233).
- **AI today (none):** The Overwatch exposure term ships OFF (OVERWATCH_EXPOSURE_PENALTY = 0.0, AIDecisionMaker.gd:2662) and its helper has no immunity check (28660-28688), so immunity cannot change any choice today.
- **Engine support:** SnapShooting.target_allowed (SnapShooting.gd:22-34) and CustodesCodex11e.blocks_snap_shooting_at. New query: 'is this unit a legal snap-shooting target' inside _overwatch_exposure_penalty, zeroing the penalty when it is not.
- **Value (low):** It only matters once an Overwatch exposure term is switched on, and few units are immune.
- **Evidence:**
  - 40k/scripts/rules/shootingtypes/SnapShooting.gd:26-28 (GOLDEN LIGHT OF THE MOIRAIDES blocks snap shooting)
  - 40k/scripts/codex/space_marines/SMDetachmentsA.gd:60 (Seal of Shrouding: no snap shooting at this unit)
- **Found by:** factions

#### COO-37 — Arrive or disembark in sequence to share an arrival-triggered buff

Some buffs are created by one unit's arrival or shooting and used by others that arrive or disembark the same turn, so order and spacing matter. Flyboss (when this Orks Aircraft ends an ingress move, each friendly Orks Aircraft or Deffkoptas unit within 6″ is riled up; Skyborne Loons then gives riled aircraft +1 to hit): bring the other aircraft and Deffkoptas in FIRST and land the Flyboss last, within 6″ of them. Combined Deployment: the transport shoots before its disembarked cargo, so the cargo gets [SUSTAINED HITS 1] against the assailed target. Linebreaker Onslaught and Combat Deployment: disembarked units re-roll charges, so disembark and stage for a long charge.

- **When:** Several Ork aircraft or Deffkoptas are arriving from reserves (Flyboss); a transport and its cargo can both engage the same target this turn; cargo needs the charge re-roll to make a long charge after disembarking.
- **Units:** Ork Aircraft and Deffkoptas (Flyboss); Adeptus Astartes transports and cargo (Gauntlet, Razorback); Custodes grav-assault transports; Kill Rig; Stompa
- **Move type:** Reserves arrival / Disembark (sequenced)
- **11e rules (corrected):** Flyboss: 'When this unit ends an ingress move, each friendly Orks Aircraft/Deffkoptas unit within 6″ of this unit is riled up until the start of your next turn' (.llm/codex_11e_wahapedia/orks/RULES.md:263), so only units already on the battlefield are riled; this corrects factions#21's 'bring the enabler in first'. Skyborne Loons (orks/RULES.md:261). Combined Deployment (space-marines/RULES.md:608). Linebreaker Onslaught (space-marines/RULES.md:610). Combat Deployment (custodes/RULES.md:220). 18.03 FAQ: any disembark move counts as having disembarked that turn (40k_11th_edition_errata_faq_commentary.md, 18.03 entry).
  - _Errata check:_ FAQ 18.03 counts every disembark mode as having disembarked, but only a Tactical Disembark (made before the transport moves, or while it stays stationary) followed by a normal move leaves the unit able to charge; after a Rapid Disembark (forced once the transport has made a normal or ingress move this phase), a Combat Disembark or an Emergency Disembark it cannot declare a charge that turn (core 18.04/18.05), so the Linebreaker Onslaught / Combat Deployment charge re-roll only pays off after a Tactical Disembark. — Core 18.04 Disembark Move / 18.05 Emergency Disembark Move (After Moving); FAQ 18.03 Disembarking (errata_faq:630-631)
- **AI today (none):** Reserves arrive one at a time by individual score (B42, AIDecisionMaker.gd:7728-8017), and disembarks are chosen per unit (8417-8832); none of Flyboss, Combined Deployment, Fire Support or Linebreaker Onslaught is referenced in AIDecisionMaker.gd. The Combined Deployment target is the most expensive enemy hit (SMDetachmentsA.gd:1038-1048), not the cargo's target.
- **Engine support:** _decide_reserves_arrival (AIDecisionMaker.gd:7728) and _decide_transport_disembark (8417) for ordering; the placement candidates (8019-8247). New query: a joint arrival plan that orders arrivals (Flyboss last, within 6″ of the others) and aligns the transport's shooting target with the cargo's charge or shooting target.
- **Value (low):** Each case is a niche enhancement or detachment rule with a small, conditional payoff.
- **Evidence:**
  - 40k/scripts/codex/space_marines/SMDetachmentsA.gd:37-38 (Combined Deployment implemented) and :1038-1048 (AI always assails the most expensive enemy hit)
  - .llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:240 (Beastscent), :159 (Idol of Belligerence)
- **Found by:** factions

#### COO-38 — Slip past screens through their engagement range

A Normal or Advance move only has to END unengaged: models may pass within 2″ of enemy models (never through their bases) to get behind a screen, onto an objective or into the backfield, provided the gaps are wide enough for their bases.

- **When:** An enemy screen has base-sized gaps, there is a target or objective behind it, and the unit has enough movement to end more than 2″ from every enemy.
- **Units:** All units without FLY (FLY units can take to the skies instead)
- **Move type:** Normal / Advance
- **11e rules (verified):** 03.01: bases cannot be moved through enemy models, but there is no engagement restriction while moving (40k_11th_edition_core_rules.txt:386-404). 09.05: the unit must be unengaged after moving (:1390-1398). 03.04 FAQ: 'Does my model or unit become engaged while moving through an enemy unit's engagement range during a move? A: No' (40k_11th_edition_errata_faq_commentary.md:265-266).
- **AI today (none):** Only by accident: the destination engine checks engagement at endpoints only (_is_position_near_enemy, AIDecisionMaker.gd:15329), so a greedy path can pass through engagement range. The planner never looks for a gap behind a screen, and its own path model checks only MONSTER/VEHICLE bases, relying on engine rejection and retries for infantry bases (B38). The gap geometry is computed only for our own screens (_screen_widest_passable_gap_inches, 28388).
- **Engine support:** _screen_widest_passable_gap_inches and _screen_max_model_spacing_px (AIDecisionMaker.gd:28388, 28380) apply the same physics in reverse; MovementPhase._path_crosses_enemy_bases (MovementPhase.gd:7422). New query: destinations behind an enemy screen reachable through a gap at least one base wide, with the path clear of enemy bases and the end more than 2″ away.
- **Value (low):** It sometimes unlocks a target or objective behind chaff, but greedy pathing already passes through engagement range when the line is clear.
- **Evidence:**
  - 40k/phases/MovementPhase.gd:7080-7094 (_check_engagement_range_at_position tests destinations only)
  - 40k/scripts/AIDecisionMaker.gd:28344-28365 (screen-gap notes: 11e Normal moves have no mid-move engagement restriction)
  - BoLS 'New Close Combat Rules Revealed' https://www.belloflostsouls.net/2026/04/warhammer-40k-new-close-combat-rules-revealed-melee-movement-made-easy.html (search snippet: you can now move through an enemy model's engagement range in the Movement phase)
- **Found by:** web

#### COO-40 — Rotate oval and FRAME bases for free reach or width

Rotating costs no movement in 11e, so finish a move by turning oval-based or FRAME models so the long side points at the objective or charge target (extra effective reach), or lies broadside to widen a block or screen.

- **When:** Oval or FRAME models that end just short of an objective's range or a charge target, or that are forming a screen or block.
- **Units:** Oval-based models (bikes, Battlewagons, Knights) and FRAME models
- **Move type:** Normal / Advance / any move (rotation is free)
- **11e rules (verified):** 03.01: 'rotating a model does not count towards the distance it has moved' (40k_11th_edition_core_rules.txt:405-408). 17.02 FRAME: measure to and from the closest point of the model (:2877-2889).
- **AI today (none):** The AI never rotates models: AIPlayer stages every model with rotation 0.0 (AIPlayer.gd:2898, 2912), and no destination search varies orientation.
- **Engine support:** MovementPhase STAGE_MODEL_MOVE payload.rotation (MovementPhase.gd:3031); Measurement.models_overlap with rotation (used by AIDecisionMaker.gd:15541-15546); MissionManager.model_gap_to_objective_range_px (MissionManager.gd:529). New query: for oval or FRAME models, the end rotation that minimises the gap to the objective or charge target (or maximises screen width) without overlaps.
- **Value (low):** It gives an inch or two for a few models and needs per-model orientation search.
- **Evidence:**
  - 40k/phases/MovementPhase.gd:3031 (STAGE_MODEL_MOVE accepts payload.rotation)
  - 40k/autoloads/AIPlayer.gd:2898, 2912 (the AI always stages rotation 0.0)
  - 40k/phases/MovementPhase.gd:873-877, 2120-2150 (10e pivot cost, applied only on APPLY_PIVOT_COST, which the AI never sends)
  - Tabletop Battles Ruleshammer Movement https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-movement (search snippet: rotation lets FRAME and oval-based models end moves closer to targets)
- **Found by:** web

#### COO-43 — Route a Thunderhawk over enemy units on a bombing run

Thunderhawk Cluster Bombs trigger when the Gunship ends a normal or advance move: pick one enemy unit it moved over during that move and roll six D6, each 3+ is a mortal wound. The path, not just the destination, has value, so route the move over the most valuable enemy unit it can cross.

- **When:** The Thunderhawk is moving anyway and a high-value or wounded enemy unit lies on or near its route; Advance only if the extra distance is needed.
- **Units:** Thunderhawk Gunship (FLY, VEHICLE, TITANIC, TRANSPORT; not AIRCRAFT)
- **Move type:** Normal / Advance
- **11e rules (verified):** Datasheet text: 'In your Movement phase, when this unit ends a normal/advance move, you can select one enemy unit this unit moved over during that move and roll six D6: For each 3+, that enemy unit suffers 1 mortal wound.' (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:175). The Gunship's keywords are FLY, VEHICLE, TITANIC, TRANSPORT (space-marines/wahapedia/Datasheets_keywords.csv:237-243), so 23.02's AIRCRAFT ingress-only rule does not apply. It can cross non-M/V models under 17.01 (40k_11th_edition_core_rules.txt:2869-2874), or any model by taking to the skies (21.03, :3358-3376).
- **AI today (none):** The ability is scored 3.0 when its card is offered (SMAbilitiesA.gd:2259-2260), but no movement code plans a path over enemy units: grep for 'Cluster Bombs' and 'moved over' finds 0 in AIDecisionMaker.gd.
- **Engine support:** The moved-over check in the ability (SMAbilitiesA.gd); path sampling like _path_crosses_monster_vehicle (AIDecisionMaker.gd:15957); the two-leg dogleg planner (_plan_dogleg, 14285) to route over a target. New query: the route choice that maximises the value of enemy units crossed, at equal destination quality.
- **Value (low):** One datasheet, only in a test list.
- **Evidence:**
  - 40k/scripts/codex/space_marines/SMAbilitiesA.gd:1444-1445, 1471 (Cluster Bombs offered when the unit ends a normal or advance move) and :2259-2260 (AI score 3.0 at use)
  - 40k/armies/sm11e_codex_test.json (Thunderhawk present)
- **Found by:** factions

#### COO-45 — Shape the surge target with your end positions

A surge move always goes toward the closest enemy unit, so in your own Movement phase end your units so that, for each friendly unit with a reactive surge, the enemy you want it to hit is its closest enemy; likewise keep a cheap unit closest to an enemy surge unit so its surge lands on the cheap unit. This entry was added by the bucket editor from the bucket definition ('Surge'); the surge itself happens in the opponent's turn.

- **When:** You have units with reactive surges (GOADED INTO ACTION, Vengeful Surge, Bestial Rage), or the enemy does, and the closest-enemy choice would otherwise send the surge into a bad matchup or onto a valuable unit.
- **Units:** Da Big Hunt Orks (GOADED INTO ACTION), Shield-Captain (Vengeful Surge), Space Wolves with Bestial Rage; cheap units as surge decoys
- **Move type:** Normal (own Movement phase positioning); adjacent: the Surge move (21.02) in the opponent's turn
- **11e rules (verified):** 21.02 Surge move: the unit must not be battle-shocked, must be unengaged and must not have moved this phase; before moving, the closest enemy unit becomes the surge target; models must end engaged with it if possible, otherwise as close as possible; afterwards the unit cannot be engaged with any other enemy unit (40k_11th_edition_core_rules.txt:3301-3325). 01.04.02: if two units are equally close, the controlling player of the unit using the rule chooses (40k_11th_edition_errata_faq_commentary.md:83-85).
- **AI today (none):** Whether to use a surge is scored in decide_window_stratagem through the codex ai_score (e.g. Vengeful Surge 2.0, CustodesAbilities.gd:1326-1327), and the engine then solves the move toward the closest enemy. No AI positioning anticipates which enemy will be closest; grep 'surge' in AIDecisionMaker.gd finds only a comment (26637).
- **Engine support:** SurgeMove.before_moving (SurgeMove.gd:41) and ReactiveMove11e.solve (ReactiveMove11e.gd:315-466). New query: for each surge-capable unit (ours or theirs), which enemy would be closest after our planned moves, with a bonus when that is the preferred target and a penalty when a valuable friendly unit becomes the closest target of an enemy surge.
- **Value (low):** Surges are reactive and conditional, and only a few in-engine units have them.
- **Evidence:**
  - 40k/scripts/rules/ReactiveMove11e.gd:315-466 (the engine solves GOADED INTO ACTION as a surge toward the closest enemy, line 373)
  - 40k/scripts/rules/movetypes/SurgeMove.gd:41 (before_moving selects the closest enemy unit)
  - .llm/codex_11e_wahapedia/RULINGS.md:95 (Vengeful Surge, D6+2″ toward the closest enemy)
  - 40k/scripts/codex/space_wolves/SWAbilities11e.gd:1263 (Bestial Rage, surge of up to D6+1″)
  - docs/rules/40k_11th_edition_core_rules.txt:3297-3352
  - 40k/scripts/rules/movetypes/SurgeMove.gd:4-12
  - _…and 6 more_
- **Absorbed duplicates:** OFF-38 (Bait a surge with surge-capable melee units); DEN-24 (Be the lightning rod for enemy surge moves)
- **Found by:** bucket-editor, factions, web, first-principles

#### COO-N02 — Keep your own shooters' sight lines clear of your other units _(added by completeness review)_

In 11e only the models of the observing unit and of the observed unit are ignored for line of sight, so every other model blocks sight, including your own tanks, monsters and blobs. When moving a unit that will not shoot through the gap (a screen, transport, melee unit or objective holder), do not end it across the lanes your gunline needs this Shooting phase or next turn, and move it out of them if it is already there. Order the moves so the shooters' lanes are known first (COO-22).

- **When:** A large-footprint friendly unit (vehicle, monster, big blob) is about to end between a friendly shooting unit and that shooter's likely targets.
- **Units:** Potential blockers: vehicles, monsters, transports, large infantry blobs
- **Move type:** Normal / Advance, plus move ordering
- **11e rules (verified):** 06.01 'other models in the observing model's unit and in the observed model's unit are ignored' (40k_11th_edition_core_rules.txt:1024-1031), so models of any other unit block line of sight. Models never grant cover except through SMOKESCREEN 15.10 (:2714-2733).
- **AI today (none):** No AI term treats friendly models as sight-line blockers. COO-22's lane clearing deals only with movement corridors (move-order sort at AIDecisionMaker.gd:7124-7148).
- **Engine support:** None today. Engine line of sight is terrain-only (EnhancedLineOfSight.check_enhanced_visibility, EnhancedLineOfSight.gd:27; TerrainManager.gd:1221-1224 says 'only terrain blocks these lines'). Model occlusion has to be added to the LoS module before this intent has any in-engine payoff.
- **Value (low):** Correct 11e play, but it has zero in-engine effect until line of sight models occlusion.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1024-1031 (06.01)
  - SUR-31/COO-19 in this catalogue rely on the same rule from the sheltered unit's side
- **Found by:** cross_bucket_critic

### Transports & reserves

#### TRN-04 — Delivery run: keep the cargo aboard and drive the transport to where the cargo's next task is

Treat the transport and its cargo as one escort pair. The cargo stays embarked this turn, and the transport's move is chosen for where the cargo needs to be when it gets out next turn: within 3″ + M of the objective it must hold, or within tactical-disembark-plus-charge reach of its target. Because nobody is getting out this phase, the transport may Advance for extra distance. Next turn, choose between parking (tactical, keeps the charge) and driving (rapid).

- **When:** The cargo has no good job at its current disembark point, would be exposed on foot, and has a defined task one turn away (an objective to hold in round 2 or 3, or a priority target). The transport can survive the approach.
- **Units:** TRANSPORTs and their cargo, e.g. Trukk + Boyz, Rhino/Impulsor + Marines, Raider/Venom + Drukhari.
- **Move type:** Normal / Advance (transport); the cargo stays embarked
- **11e rules (verified):** 09.02: an embarked unit is selected to move like any other unit and can simply not disembark (40k_11th_edition_core_rules.txt:1345-1365). 18.04: only disembarking is barred after the transport advances or falls back (:3024-3025); next turn the mode is tactical if the transport stays put, rapid if it moves (:3029-3054). Embarked units are not on the battlefield and cannot be targeted (40k_11th_edition_errata_faq_commentary.md:36).
- **AI today (none):** Transports are planned as ordinary units with their own objective assignment. A loaded transport differs only in two ways: hold-for-shooting is skipped (AIDecisionMaker.gd:7398-7402) and it moves last (7657-7664). Cargo almost always disembarks at Step 1.75 before the transport moves (see TRN-02), so there is rarely anything aboard to deliver. No term scores a transport destination by its cargo's next-turn task (.llm/ai-overhaul-todo.md:1096-1109).
- **Engine support:** Reuse _assign_units_to_objectives candidate scoring (AIDecisionMaker.gd:9834) with the cargo's OC and score evaluated at transport end point + 3″ + cargo M; _capture_arrival (13091) for arrival turns; _evaluate_position_threat (28794) for the transport's survival. New: an escort-pair assignment that binds transport and cargo, and a real valued 'stay embarked' option in _decide_transport_disembark in place of the 0.0 baseline.
- **Value (high):** Without it, the AI's transports are nearly empty from round 1, wasting both the transport's mobility and the protection it gives the cargo.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/ai-overhaul-todo.md:1096-1109 (C7: the coupling 'move transport where cargo's task wants to be next turn' has no owner; exam 'Trukk carries Boyz toward the objective it must hold turn 3')
  - /home/user/warhammer-40k-godot/research/ai_feasibility_2026-08-09/code_engine-architecture.md:29 ('transports and cargo planning independently')
  - YouTube gRqdSBkqVlA @07:00 (6 Plus Plus Gaming): “Drukhari really love it in Sky Splinter Assault ... it gives them that bit of protection”
  - /home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/DisembarkMove.gd:16-31
  - /home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/DisembarkMove.gd:84-95 (select_mode)
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3013-3058
- **Absorbed duplicates:** OBJ-32 (Park the transport for next turn's tactical disembark and charge)
- **Found by:** youtube, first-principles

#### TRN-05 — Stay embarked, or embark, to protect a threatened unit and deny kills

Keep a fragile or valuable unit inside its transport, or end its Normal, Advance or Fall Back move with every model within 3″ of a friendly transport with room, and embark. It leaves the battlefield: it cannot be shot, overwatched (Fire Overwatch happens at the end of the Movement phase, against visible units within 24″), charged, or counted by kill cards until the transport dies. The costs: while aboard it cannot shoot (except through Firing Deck), charge, hold objectives or perform actions. If the transport is destroyed, the unit makes an emergency disembark (hazard rolls, battle-shocked, models that cannot be placed are destroyed) and can then be hit by the transport's Deadly Demise.

- **When:** The unit would likely die, or give up a kill-card score, next turn; it has no objective or action job this turn; and a transport with capacity is within reach. Weight this more for armies whose infantry depend on transports (Drukhari) and under kill-based cards. Never embark the Beacon unit (it must be on the battlefield when it scores at the end of the opponent's turn), or a unit Condemned by the opponent's Punishment card (leaving the battlefield pays them). A unit set up this turn (disembarked or arrived from reserves) cannot embark.
- **Units:** Characters, glass-cannon infantry, damaged units: anything that fits a friendly TRANSPORT.
- **Move type:** Embark (after a Normal / Advance / Fall Back move), or stay embarked
- **11e rules (corrected):** 18.02 Embarking: after a normal, advance or fall-back move; every model within 3″; not set up this turn; enough capacity; the unit is then not on the battlefield (40k_11th_edition_core_rules.txt:2981-2997). 15.08 Fire Overwatch: end of the opponent's Movement phase, one visible enemy unit within 24″ (:2735-2760). Not on the battlefield means not visible and not measurable (40k_11th_edition_errata_faq_commentary.md:36). 18.05 emergency disembark, with errata (:3061-3078; errata_faq:609). 24.08 Deadly Demise resolves after the emergency disembark (:3670-3699). 24.14 Firing Deck (:3705-3730). Beacon card (engine data): a unit may be designated while embarked, but it scores only 'if the beacon unit is on the battlefield' (40k/data/40kdc/missionCards.json:2850; the full card is unconfirmed per docs/rules/11th_edition_missions_gdm2026.md:4). Punishment: a Condemned unit that leaves the battlefield pays the card's owner (missionCards.json:467; MissionManager.gd:1772-1780, 1955-1965). Correction to first-principles#10: an embarked Beacon does not score.
- **AI today (none):** The AI never embarks during play. EMBARK_UNIT never appears in AIDecisionMaker.gd or AIPlayer.gd, and MovementPhase._check_embark_opportunity returns early for AI players (MovementPhase.gd:8306-8311). Staying embarked only happens when every disembark score is ≤ the 0.0 baseline (AIDecisionMaker.gd:8444, 8475). The only negative term is round 1's −0.2 (8563-8567), and no Firing Deck adds +0.4 (8603-8616), so cargo stays in essentially only in round 1, in a Firing Deck transport. No term looks at the cargo's exposure, kill cards, or Beacon / Condemned status. Adjacent: faction end-of-Fight-phase embarks are scored. DUTY IS NEVER DONE scores 2.0 when no enemy is within 9″ and the unit is off objectives (SMCodexAMovement.gd:292-294); MOUNT UP, LADZ resolves at StratagemManager.gd:2788-2806.
- **Engine support:** Reuse TransportManager.can_embark (TransportManager.gd:107) and is_unit_within_embark_range (:784). The action validator, _validate_embark_unit (MovementPhase.gd:9120-9150), checks neither the 3″ range nor engagement range, so the AI must check them itself. Reuse _calculate_enemy_threat_data / _evaluate_position_threat (AIDecisionMaker.gd:28695, 28794) for exposure, and MissionManager card state for Beacon / Condemned. New: an 'embark' destination in the movement plan (within 3″ of a friendly transport with room), followed by EMBARK_UNIT; and a real valued 'stay embarked' option in _decide_transport_disembark.
- **Value (high):** Saving a key unit or denying a kill-card score is worth several VP, and today the AI unloads nearly every transport in round 1.
- **Evidence:**
  - YouTube 3lwK9jAR0RM @23:00 (MiniWarGaming): “going to pick Drazar up to protect Drazar from at least a round of shooting”
  - YouTube nCQuNE_8V44 @19:00 (SkaredCast): “you didn't need the entire unit to kill them. They died very fast. Should have kept them in the transport”
  - https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-transports (search snippet: every model within 3″ after a Normal, Advance or Fall Back move)
  - https://spikeybits.com/warhammer-40k-11th-edition-stratagems-overhauled/ (search snippet: a unit that boards a transport partway through its move cannot be overwatched)
  - /home/user/warhammer-40k-godot/40k/data/40kdc/missionCards.json:2850, 467
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1772-1780, 1955-1965
  - _…and 5 more_
- **Absorbed duplicates:** SUR-16 (Embark into a transport to take the unit off the battlefield)
- **Found by:** youtube, web, first-principles, missions, core-rules

#### TRN-02 — Drive the transport first, then Rapid-disembark the cargo where it must shoot, score or act

Give the loaded TRANSPORT a Normal move first, then disembark. The cargo is set up wholly within 3″ of the hull, so it reaches transport M + 3″ (plus the hull's length) instead of the 3″ + its own M of a tactical disembark. Afterwards the cargo cannot declare a charge or move again this phase. It can still shoot normally (without the [HEAVY] +1, because it was set up this turn) and can start an action. This is the transport version of "move toward an enemy to shoot it", and of taking a far objective with OC this turn.

- **When:** Use it when the cargo's job this turn is shooting (Melta or Rapid Fire half range, or a target beyond its own reach), objective OC, or an action, and transport M + 3″ gets there while 3″ + cargo M does not. The transport must make a Normal move: an Advance or Fall Back bars disembarking this phase. Do not use it when the cargo needs to charge; use TRN-03, or a faction assault disembark (TRN-15).
- **Units:** Embarked shooting, scoring and action units, and their TRANSPORT.
- **Move type:** Normal (transport), then Disembark (rapid mode)
- **11e rules (verified):** 18.04 Disembark Move: only if the transport has not advanced or fallen back this phase; rapid mode is mandatory if it made a normal or ingress move; set-up wholly within 3″; afterwards the unit cannot declare a charge until the end of the turn (40k_11th_edition_core_rules.txt:3013-3052). 09.02: each unit is selected to move once, so a rapid-disembarked unit gets no further move (:1345-1356). 10.04 normal shooting only needs the unit unengaged and not to have advanced (:1489-1500). 24.16 [HEAVY]: no +1 for a unit set up this turn (:3751-3765). 16.01: a disembark is neither an advance nor a fall back, so the unit can start an action (:2808-2817). Engine: TransportManager.gd:281-295 (a disembark after the transport moved sets cannot_move and cannot_charge).
- **AI today (partial):** This only happens incidentally. Disembark is decided at Step 1.75, before any unit on the table moves (AIDecisionMaker.gd:6823-6828), and it beats the 0.0 'stay' baseline at any positive score (8444, 8475, 8488). From round 2 every embarked unit scores at least +0.3 (8563-8570). In round 1, a unit in a transport with no Firing Deck detected scores at least −0.2 + 0.4 (8603-8616). So cargo normally gets out before its transport moves (tactical mode). Drive-then-rapid only occurs when the cargo stayed in (score ≤ 0, or no legal placement) and the Step 1.75 re-run after the transport's move scores > 0, for example because the transport ended within 3″ or 6″ of an objective (+0.8 / +0.4; 8512-8527). Transports move last (tier 2, 7657-7664). Nothing compares the two reaches, and the transport's destination is planned for the transport, not for its cargo. Read from code; not validated live.
- **Engine support:** Reuse _score_disembark_benefit (AIDecisionMaker.gd:8498) and _compute_disembark_positions (8626), evaluated at the transport's projected end point; _compute_movement_toward_target (14212) for the transport leg; TransportManager.can_disembark (TransportManager.gd:173). New: a two-step candidate, 'transport Normal move to P, then rapid set-up within 3″ of P', scored by the cargo's shooting and objective value at P against the tactical alternative (TRN-03); block Advance for that transport. Caution (read from code): DisembarkMove.select_mode keys rapid mode off flags.moved_this_phase (DisembarkMove.gd:84), which only SurgeMove writes (SurgeMove.gd:113). Live, this disembark is therefore labelled 'tactical', and the rapid effects come from TransportManager via flags.moved. Plan from flags.moved, not from the mode label.
- **Value (high):** Delivery is what transports are for. Today cargo almost always gets out at the start of the phase, so the transport's move delivers nothing. This sequence is the main way shooting, scoring and action cargo gets transport M + 3″ of reach.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3013-3057
  - /home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/DisembarkMove.gd:64-95, 119-133
  - /home/user/warhammer-40k-godot/40k/autoloads/TransportManager.gd:281-300
  - https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-transports (search snippet: moving the transport first gives transport movement plus 3″, but no charge)
- **Found by:** core-rules, first-principles, web, youtube

#### TRN-03 — Tactical-disembark before the transport moves, then make the cargo's own move (keeps the charge)

Disembark while the transport has not yet moved, or is remaining stationary. The cargo is set up wholly within 3″ and is then selected for a Normal or Advance move. After a Normal move it can still shoot and declare a charge, so this is the transport version of "move toward an enemy to charge it" (about 3″ + hull + M, then 2D6). An Advance adds distance but bars both the charge and actions. The transport can move afterwards with any move type: the advance/fall-back bar only stops units disembarking after the transport has made such a move.

- **When:** Melee or charge-capable cargo with a target within roughly 3″ + M + 12″ (a charge target must be within 12″ and within the charge roll). Also cargo that needs its own movement, for example to reach cover or a quarter. Disembark before the transport is selected to move. If the transport is engaged but there is room for an unengaged set-up within 3″, tactical mode is mandatory; do it before the transport falls back, because a transport that fell back bars disembarking.
- **Units:** Embarked units (melee units especially) and their TRANSPORT.
- **Move type:** Disembark (tactical mode), then Normal / Advance
- **11e rules (corrected):** 18.04 Tactical Disembark: mandatory if the transport remained stationary or has not yet been selected to move, and the unit can be set up wholly within 3″; afterwards, select the unit for a normal or advance move (40k_11th_edition_core_rules.txt:3013-3054). 03.02: a set-up must be unengaged and in coherency (:491-507). 09.06 Advance: no charge and no action afterwards (:1401-1414). 11.02 charge eligibility: within 12″, no advance or fall back (:1603-1625). 11.04: targets must be within the charge roll (:1640-1650). 24.16: no [HEAVY] +1 for a unit set up this turn (:3751-3765). Correction to core-rules#70: 18.04 sets no limit on how the transport moves after its cargo has left. The advance/fall-back clause only applies to disembarking after such a move (:3024-3025), and the engine adds no restriction either (TransportManager.gd:296-300).
- **AI today (partial):** This is the AI's default. Step 1.75 runs before transports move (AIDecisionMaker.gd:6823-6828, commented 'so disembarked units can still move'), so the engine picks tactical mode. _score_disembark_benefit adds +0.4 for a melee unit with an enemy within M + 15″ while the transport has not moved (8546-8561), and disembarked units move first (tier 0, 7657-7664). Gaps: (1) Scoring uses centroids only and is never weighed against staying aboard (TRN-04) or driving first (TRN-02). (2) Placement faces the nearest objective, not the charge target (8626+). (3) Possible bug, read from code and not validated live: the follow-up opens an active move (MovementPhase.gd:9090-9092, 8773-8846). get_available_actions then offers CONFIRM_UNIT_MOVE for it (7943-7953), and _decide_movement confirms any CONFIRM_UNIT_MOVE before planning (AIDecisionMaker.gd:6804-6814). The cargo may therefore close its follow-up move without moving at all.
- **Engine support:** Reuse _score_disembark_benefit / _compute_disembark_positions (AIDecisionMaker.gd:8498, 8626), the charge-intent plan (3773-3946, _get_charge_intent 3961), _prob_sum_d6_at_least (12788), _compute_movement_toward_target (14212), TransportManager.can_disembark (TransportManager.gd:173). New: set the cargo up on the side facing the planned target; score set-up point + M + 2D6 odds; route the follow-up through normal BEGIN_NORMAL_MOVE planning rather than the Step 1 confirm.
- **Value (high):** It is the standard way to deliver melee out of a transport. It already happens by default, but crudely, and the follow-up move may be lost.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3013-3057
  - /home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/DisembarkMove.gd:16-24, 88-92, 126-129
  - /home/user/warhammer-40k-godot/40k/phases/MovementPhase.gd:8773-8846, 9085-9094
  - https://www.greenstuffworld.com/en/blog/all-about-warhammer-40k-11th-edition-rules-news-and-armageddon-box-n144 (search snippet: after a Tactical disembark the unit must make a Normal or Advance move, and with a Normal move it can charge as usual)
  - docs/rules/40k_11th_edition_core_rules.txt:3013-3078
  - 40k/scripts/rules/movetypes/DisembarkMove.gd:18-23 (rapid / tactical / combat mode selection)
  - _…and 1 more_
- **Absorbed duplicates:** OFF-25 (Disembark tactically so the unit can still charge)
- **Found by:** core-rules, first-principles, web, youtube

#### TRN-06 — Arrive from reserves to charge the same turn (move toward an enemy to charge it)

Land a melee unit just over 8″ from an unscreened priority target and charge it in the same turn. An ingress move only bars other moves until the next Charge phase. The charge target must be within 12″ and within the 2D6 roll, so landing at 8″+ needs a 9+ (about 28%). The odds improve with a Command Re-roll (re-rolls the whole charge), a charge bonus (e.g. FURY OF THE EMPEROR, +2 for Custodes Terminators that made an ingress move), or several targets in range. In 11e, Fire Overwatch happens at the end of the Movement phase, after the unit arrives, not during the charge.

- **When:** Rounds 2-3. A high-value target (character, scoring unit, artillery) has open ground more than 8″ from every enemy unit and within 12″ of it. The unit has a charge re-roll or bonus, or a failed charge still leaves it somewhere useful (on an objective, or in cover). Deep Strike can land in the backfield, even in the enemy deployment zone; strategic reserves need the target near an edge.
- **Units:** Melee units with Deep Strike or in strategic reserves: assault Terminators, jump infantry, Custodes Terminators, Ork deep strikers.
- **Move type:** Reserves arrival, then a charge in the Charge phase
- **11e rules (corrected):** 20.04: more than 8″ from all enemy units; after moving, no other move type until the start of the next Charge phase (40k_11th_edition_core_rules.txt:3264-3273). 24.09 Deep Strike (:3649-3655). 11.02 charge eligibility: within 12″, unengaged, no advance or fall back (:1603-1625). 11.04: each charge target must be within the maximum distance, i.e. the charge roll (:1640-1650). 15.02 Command Re-roll: charge rolls are re-rolled in full (:2651-2680). 15.08 Overwatch timing (:2735-2737). FURY OF THE EMPEROR text (.llm/codex_11e_wahapedia/custodes/RULES.md:118). Engine: IngressMove.gd:138-146 (no_moves_until_charge_phase; the unit can still charge).
  - _Errata check:_ Holds for most units. But if a non-AIRCRAFT model is too large to set up wholly within 6″ of the battlefield edge, it must be set up touching the edge, and its unit then cannot make a normal, advance, fall-back or charge move that turn. So it cannot charge on arrival from an edge ingress. Deep Strike set-ups have no edge distance and are not affected. — Commentary 03.02.02 Setting Up Large Models (From Strategic Reserves)
- **AI today (partial):** Melee units get +1.5 in the arrival order (AIDecisionMaker.gd:7967-7968). Every candidate spot gets +3 when the nearest enemy centroid is 10-15″ away, or +2 at 9-10″ (8226-8239); the code's own comment calls that band 'hard to charge immediately'. The 9″ + buffer candidate filter (8029) also removes the 8-9″ band. So arrivals are placed to threaten next turn, not to charge this turn. There is no charge-odds, target-value, re-roll or bonus term, and FURY OF THE EMPEROR and the other arrival buffs never appear in AIDecisionMaker.gd.
- **Engine support:** Reuse _generate_deep_strike_candidates and _is_valid_reinforcement_position (AIDecisionMaker.gd:8137, 8331) with GameConstants.reinforcement_min_enemy_distance_inches (GameConstants.gd:48-49); _prob_sum_d6_at_least (12788); _estimate_melee_damage (19576); charge-intent target values (3773-3946); evaluate_command_reroll_charge (28028). New: a ring of charge-landing candidates 8-12″ edge-to-edge from chosen targets, scored by P(charge) × damage/value minus Overwatch exposure (use _overwatch_exposure_penalty, 28660, as the template).
- **Value (high):** Melee deep strike is a staple 11e threat (8″ stand-off), and the AI currently places arrivals so they cannot charge that turn.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1603-1665, 2651-2680, 3255-3274
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-moving-and-the-movement-phase/ (search snippet: after an Ingress Move you cannot make any type of move until the next Charge phase)
  - https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics (search snippet: arrive just outside 8″)
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/custodes/RULES.md:118 (FURY OF THE EMPEROR)
  - /home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/IngressMove.gd:138-146
  - https://www.warhammer-community.com/en-gb/articles/4a8o9tzw/adeptus-custodes-top-detachment-tips/ (search summary: a charge re-roll helps Terminators charge after arriving from reserves)
  - _…and 4 more_
- **Absorbed duplicates:** OFF-18 (Arrive from reserves in charge position)
- **Found by:** web, first-principles, factions, core-rules

#### TRN-07 — Arrive from reserves to shoot (move toward an enemy to shoot it)

Deep Strike or ingress a shooting unit where its guns work best this turn: within half range for [MELTA] or [RAPID FIRE]; within detection range of a Hidden priority target (15″, or 12″ against a model that has gone to ground); or on a flank or backfield angle the army on the table cannot see. The unit can use normal shooting (it did not advance) but never gets the [HEAVY] +1, because it was set up this turn. Faction arrival buffs make the arrival turn the best shooting turn: Inceptor Meteoric Descent (+1 to hit), Deffkoptas Deff from Above (+1 to hit), Venatari Strike from the Skies (re-roll hits).

- **When:** Rounds 2-3, or later for repositioned units. A valuable target is reachable from more than 8″ away and visible from the landing spot, and the unit's damage is concentrated at short range or it has an arrival buff. Accept that it faces Overwatch at the end of this Movement phase and then the opponent's next Shooting phase (see TRN-10).
- **Units:** Shooting units in reserves: melta, plasma and rapid-fire squads, Inceptors, Deffkoptas, Venatari. AIRCRAFT: see TRN-17.
- **Move type:** Reserves arrival
- **11e rules (corrected):** 20.04 / 24.09 (40k_11th_edition_core_rules.txt:3255-3274, 3649-3655). 10.04: normal shooting only requires no advance (:1489-1500). 24.16 [HEAVY]: no bonus for a unit set up this turn (:3751-3765; engine ModifierStack.gd:168-172). 24.25 [MELTA] and 24.30 [RAPID FIRE] half range (:3833-3845, 3896-3905). 13.09 Hidden, 15″ detection range (:2292-2302), as errata'd to light/dense terrain (40k_11th_edition_errata_faq_commentary.md:529); gone to ground −3″ (errata_faq:539). Datasheets: Meteoric Descent (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:131), Deff from Above (orks/wahapedia/Datasheets_abilities.csv:102), Strike from the Skies (custodes/wahapedia/Datasheets_abilities.csv:179).
  - _Errata check:_ Holds for most units. But if a non-AIRCRAFT model is too large to set up wholly within 6″ of the battlefield edge, it must be set up touching the edge, and its unit then cannot make any attacks with ranged weapons that turn. So an edge ingress cannot be used to shoot with it. Deep Strike set-ups have no edge distance and are not affected. — Commentary 03.02.02 Setting Up Large Models (From Strategic Reserves)
- **AI today (partial):** Units with ranged weapons get +1.0 in the arrival order (AIDecisionMaker.gd:7971-7972, labelled 'short range' but applied to any unit with ranged weapons). Spots get the same 10-15″ / 9-10″ enemy-centroid band (8226-8239). There is no term for weapon range, half range, line of sight, Hidden or detection range, or arrival buffs; Meteoric Descent, Deff from Above and Strike from the Skies never appear in AIDecisionMaker.gd.
- **Engine support:** Reuse the arrival candidate generators (AIDecisionMaker.gd:8073, 8137); RulesEngine.get_eligible_targets on a board copy with the unit placed (RulesEngine.gd:7137) or TerrainManager.model_visible_11e (TerrainManager.gd:1209) for sight lines; RulesEngine.max_ranged_weapon_range_inches (RulesEngine.gd:6693); the half-range helper behind the Rapid Fire / Melta blend (AIDecisionMaker.gd:13669-13754); _estimate_weapon_damage (17984). New: score landing spots by expected damage to the best visible target, plus any arrival buff.
- **Value (high):** Melta and rapid-fire drops are a staple use of Deep Strike, and the AI never aims an arrival at a target.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/scripts/rules/ModifierStack.gd:168-172
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:131 (Meteoric Descent: 'If this unit made an ingress move this turn, this unit's ranged attacks have +1 to hit')
  - https://grimslate.com/blog/reserves-and-deep-strike-11th-edition (search snippet: pick the ingress spot for half range)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:7971-7972, 8226-8239
  - docs/rules/40k_11th_edition_core_rules.txt:3249-3283
  - 40k/scripts/AIDecisionMaker.gd:8232-8238 (10-15″ 'can shoot' band), :8027-8029 (9″+ stand-off)
- **Absorbed duplicates:** OFF-30 (Arrive from reserves in a firing position)
- **Found by:** first-principles, web, factions, core-rules, bucket-editor

#### TRN-09 — Bring every strategic-reserves unit in by the end of battle round 3

Strategic reserves that have not made an ingress move by the end of round 3 are destroyed. The exceptions are units inside a transport that has made an ingress move, and repositioned units. Treat round 3 as the last own-turn arrival. For a unit that still could not be placed, the last chance is a Rapid Ingress at the end of the opponent's round-3 Movement phase. Plan arrivals so the deadline never forces a bad spot (or leaves no spot), and keep CP for that last Rapid Ingress.

- **When:** Any unit still in strategic reserves at the start of round 3. Also round 2, when legal space is scarce: enemy screens, or the 12″ zones around Omni-scrambler / Arae-Shrike units.
- **Units:** Strategic reserves units, including reserve TRANSPORTs with cargo and units with Deep Strike. Not repositioned units.
- **Move type:** Reserves arrival (adjacent: Rapid Ingress at the end of the opponent's round-3 Movement phase)
- **11e rules (verified):** 20.03 (40k_11th_edition_core_rules.txt:3250-3254). 20.04: destruction at the end of round 3, with its exceptions (:3276-3283). 20.02 repositioned units (:3219-3240). 15.07 Rapid Ingress: end of the opponent's Movement phase; not in round 1; not AIRCRAFT (:2714-2731). Engine: ScoringPhase.gd:955-1035 (_destroy_remaining_reserves; repositioned units exempt at 966-971).
- **AI today (partial):** The deadline is usually met by default, because every reserve arrives at its first legal chance (Step 1.5, AIDecisionMaker.gd:6815-6821; there is no hold-back option). But the urgency is 10e-shaped. Arrival order adds +2.0 in round 3 and +5.0, commented 'last chance on Round 5', from round 4 (7974-7978; constants 2060-2061). Rapid Ingress declines with 1 CP before round 4 and adds urgency only in round 3+ / 4+ (28143-28146, 28167-28173). The 9″ + buffer filter (8029) can leave a unit with no candidate in a crowded round 3, and nothing relaxes it. The plan's RESERVE_UNTIL arrival_round is recorded at formations (1058, 1172-1218) but never read when units arrive.
- **Engine support:** Reuse _score_reserves_deployment (AIDecisionMaker.gd:7949), evaluate_rapid_ingress (28121) and GameState.get_battle_round. New: a hard 'must arrive this turn' flag in round 3 (and for the opponent's round-3 Rapid Ingress) that relaxes the spot filter to the legal 8″ and keeps 1 CP for the Rapid Ingress fallback.
- **Value (high):** Missing the deadline loses the whole unit, and any hold-back logic (TRN-11) depends on getting this right.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3276-3283
  - /home/user/warhammer-40k-godot/40k/phases/ScoringPhase.gd:955-1035
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:7974-7978 ('Critical — last chance on Round 5'), 28143-28146, 28167-28173
  - 40k_11th_edition_core_rules.txt:3250-3283
  - https://grimslate.com/blog/reserves-and-deep-strike-11th-edition (search snippet: every use of Rapid Ingress is one more chance to beat that clock)
  - 40k/scripts/AIDecisionMaker.gd:28164-28172, 7975-7979 (urgency comments still say 'must deploy by Round 5')
- **Absorbed duplicates:** ADJ-12 (Use Rapid Ingress as the last arrival window before the end-of-round-3 reserve wipe)
- **Found by:** core-rules, missions, web

#### TRN-01 — Arrive from reserves onto an objective

Use a strategic-reserves ingress (wholly within 6″ of a battlefield edge) or a Deep Strike (anywhere more than 8″ from all enemy units, even in the enemy deployment zone) to put a unit in range of an objective that no on-table unit can reach. Targets: an uncontrolled or lightly held marker (a high-OC unit can flip a weak hold on arrival), an edge or flank objective, a threatened home objective, or, with Deep Strike, a backfield objective. After arriving the unit cannot move again until the Charge phase, so it has to land in range.

- **When:** Battle round 2 or later (round 1 only with a first-turn grant, see TRN-22). Pick an objective that still needs OC, has a legal spot in control range more than 8″ from every enemy unit, and where the arriving OC beats what the enemy can bring back before the next scoring point (or the VP from one check is worth the unit). Skip objectives already held securely, where extra OC adds nothing.
- **Units:** Strategic reserves and Deep Strike units; high-OC infantry; cheap scoring units.
- **Move type:** Reserves arrival (ingress 20.04 / Deep Strike 24.09)
- **11e rules (verified):** 20.03: arrive from battle round 2 unless stated otherwise (40k_11th_edition_core_rules.txt:3250-3254). 20.04 ingress: wholly within 6″ of an edge, more than 8″ horizontally from all enemy units, not in the opponent's deployment zone before round 3; after moving, no other move type until the next Charge phase (:3255-3274). 24.09 Deep Strike: if every model has it, anywhere more than 8″ from all enemy units, even inside the opponent's deployment zone (:3649-3655). 09.02: units in strategic reserves are selected to move like any other (:1345-1365). Engine: IngressMove.gd:44-112 (validate_setup); GameConstants.gd:48-49 (8″ in 11e).
- **AI today (full):** Step 1.5 calls _decide_reserves_arrival whenever PLACE_REINFORCEMENT is offered (AIDecisionMaker.gd:6815-6821). Arrival order adds the best objective the unit can help (contested / enemy_weak / held_threatened 1.5, uncontrolled 0.5, times an OC factor, plus VP x1.2). Deep strikers skip objectives with an enemy model within 9″ minus control range (7994-8015). Candidate spots: every 4″ along all edges, 3″ in (8073-8135), or 10/12/15″ rings round objectives plus a grid (8137-8170). Spots are ranked 10 − d within 6″ of an objective, otherwise 8 − 0.3d (8204-8223). FIX-HELD-DUP drops objectives that need no OC (8036-8039, 8054-8071). Limits: (1) candidates need 9″ + base radius + 0.6″ from enemy model centres (8029), while validation uses the legal 8″ (8346), so the 8-9″ band is never proposed. (2) Distance is measured to the marker centre, not to a terrain-objective's area. (3) No check that the unit survives the reply.
- **Engine support:** Reuse _decide_reserves_arrival (AIDecisionMaker.gd:7728), _compute_reinforcement_positions (8019), _is_valid_reinforcement_position (8331), _evaluate_all_objectives (8926), MissionManager.model_in_objective_range / model_gap_to_objective_range_px (MissionManager.gd:529, 569) and IngressMove.validate_setup (IngressMove.gd:44). New: generate spots inside the objective's control band at the legal >8″ (GameConstants.reinforcement_min_enemy_distance_inches) instead of the 9″ + buffer, and score each by OC margin at the next scoring check and by next-turn survival.
- **Value (high):** This is the most common reason to hold reserves. The AI already does it, so what is left to gain is the 8-9″ band and terrain-objective range.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3250-3283, 3649-3655
  - /home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/IngressMove.gd:44-112
  - YouTube nGqRAvAMTYA @66:00 (TacticalTortoise 40k): “He also can 6 in deep strike high OC onto an objective in order to grab it” (a faction 6″ deep strike; the core rule is more than 8″)
  - https://grimslate.com/blog/reserves-and-deep-strike-11th-edition (search snippet, cited by the web stream)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:7949-8015, 8019-8240
- **Found by:** core-rules, youtube, first-principles, missions, web

#### TRN-10 — Set up out of sight, in cover or Hidden when arriving or disembarking (move into cover)

An arrival or a disembark is a set-up the unit cannot move away from this turn: an ingress bars other moves, and a rapid disembark ends the unit's move. The unit will face the opponent's Fire Overwatch at the end of this Movement phase and their whole next turn; a Rapid Ingress arrival faces their Shooting phase straight away. So pick a spot out of enemy line of sight (behind Solid or obscuring terrain) or inside a terrain area for the benefit of cover. INFANTRY / BEASTS / SWARM can instead set up with every model inside a terrain area containing light or dense features: they are then Hidden, visible only within the 15″ detection range (−3″ if gone to ground), because the unit has not shot this turn or last. This is the transport/reserves version of "move into cover".

- **When:** Every arrival or disembark near enemy shooters, especially for fragile or high-value units, or when the unit's job (objective, action, next-turn charge) does not need it to shoot this turn. Weigh it against TRN-07: shooting gives up Hidden for this turn and the next.
- **Units:** All arriving and disembarking units. Hidden applies to INFANTRY / BEASTS / SWARM only.
- **Move type:** Reserves arrival / Disembark (where to set up)
- **11e rules (corrected):** 20.04: no other move until the next Charge phase (40k_11th_edition_core_rules.txt:3271-3273). 18.04 rapid: no further move (:3029-3052). 15.08 Overwatch: end of the opponent's Movement phase, one visible unit within 24″ (:2735-2760). 15.07 Rapid Ingress timing (:2714-2731). 13.08 cover (:2278-2290). 13.09 Hidden (:2292-2302), errata'd to 'light/dense terrain features' (40k_11th_edition_errata_faq_commentary.md:529), with the first-turn note (:533) and gone to ground (:539). 13.10 obscuring (:2305-2311). 13.11 Solid (:2313-2318). Correction to core-rules#78: Hidden needs a terrain area with light OR dense features (errata), not dense only.
- **AI today (none):** Reserve spots are ranked only by objective proximity and enemy-centroid distance (AIDecisionMaker.gd:8204-8240). Disembark placement puts models in rows on the side facing the nearest objective (8626+). Neither checks line of sight, cover, terrain areas or Hidden. A Hidden-seeking term exists only for objective trips, and it ships at weight 0 (WEIGHT_HIDDEN_GAINED, 2633; used at 10306-10314).
- **Engine support:** Reuse _position_would_be_hidden (AIDecisionMaker.gd:28515), TerrainManager.is_model_hidden (TerrainManager.gd:1001), model_visible_11e (1209), unit_has_cover_11e (1388), area_at (847), and LineOfSightManager.calculate_los_to_position (LineOfSightManager.gd:101). New: score each arrival and disembark candidate by the shot volume of enemy units that can see it (Overwatch within 24″ now, full shooting next turn), plus a bonus for Hidden or cover.
- **Value (medium):** It shapes every arrival rather than being a reason to arrive, but it decides whether expensive arrivals live long enough to do their job.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_errata_faq_commentary.md:527-539
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2278-2318, 2735-2770
  - /home/user/warhammer-40k-godot/40k/autoloads/TerrainManager.gd:1001 (is_model_hidden), 1209 (model_visible_11e), 1388 (unit_has_cover_11e)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:28515 (_position_would_be_hidden probe), 2633 (WEIGHT_HIDDEN_GAINED = 0.0)
- **Found by:** core-rules

#### TRN-11 — Hold a unit in reserve this turn (keep the Rapid Ingress threat or a reactive answer)

Choose not to make an ingress move, so the reserve unit remains stationary and stays a live threat. At the end of the opponent's Movement phase it can Rapid Ingress (1CP) behind whatever they committed: onto an objective they left, behind units that advanced, or on a flank they overloaded. Meanwhile the opponent has to keep screening during their own turn. Against very fast, high-pressure armies, bring everything on instead.

- **When:** Round 2 (rarely round 3). You have a punishing reserve unit and at least 1-2 CP to spare, the opponent's screens are thin, and no spot this turn is clearly better than the expected Rapid Ingress spot. Never let the unit miss the round-3 deadline (TRN-09). Not for AIRCRAFT, which cannot Rapid Ingress.
- **Units:** Strategic reserves and Deep Strike units (not AIRCRAFT); melee or melta units that punish an exposed backline.
- **Move type:** Remain Stationary (in strategic reserves); adjacent: Rapid Ingress at the end of the opponent's Movement phase
- **11e rules (verified):** 09.02: every unit, including those in strategic reserves, is selected to move and may remain stationary (40k_11th_edition_core_rules.txt:1345-1365; 40k_11th_edition_errata_faq_commentary.md:458: units with no move type selected remain stationary). 15.07 Rapid Ingress: end of the opponent's Movement phase; a strategic-reserves unit excluding AIRCRAFT; not in battle round 1 (:2714-2731). 20.04 deadline (:3276-3283).
- **AI today (none):** _decide_movement deploys a reserve unit whenever PLACE_REINFORCEMENT is offered and a legal formation exists (AIDecisionMaker.gd:6815-6821, 7772-7945); there is no 'stay in reserve' option. Rapid Ingress (adjacent) is only evaluated for units that happen to still be in reserves (28121-28334), and it declines with 1 CP before round 4 (28143-28146). The arrival_round of the RESERVE_UNTIL plan verb is never read when units arrive (it is stored at 1058, 1172-1218).
- **Engine support:** Reuse _score_reserves_deployment (AIDecisionMaker.gd:7949) for the value of arriving now, evaluate_rapid_ingress (28121) for the expected Rapid Ingress value, _calculate_enemy_threat_data (28695) for the opponent's speed, and the plan's arrival_round (1058). New: an explicit 'hold' option compared with the best arrival spot, gated by CP and by round (never past round 3).
- **Value (medium):** Strong players use it to force screening and to punish commitments, but the CP cost and the round-3 deadline make it situational.
- **Evidence:**
  - YouTube Enm67qaqHkU @04:00 (40K Dirtbags): “at least one unit in reserves cuz you're making lists to have a reserve rapid ingress target”
  - YouTube ym0SnzF2ydg @162:00 (Art of War 40k): “maybe they should have just started the game in reserve so they could be a little bit more of a reactive answer”
  - YouTube uYFHWwWSklU @87:00 (Odyssey40k): “there's a 6-in deep strike in retaliation ... you have to screen really aggressively for it” (refers to a faction 6″ deep strike)
  - YouTube pAk1YiuioNQ @09:00 (Happy Krumping), the counter-view: “If you're ever going to play against it, don't start things in reserves. You need everything on the table”
  - https://odyssey40k.com/rapid-ingress-is-the-best-stratagem-in-11th-edition/ (search snippet)
  - /home/user/warhammer-40k-godot/40k/phases/ScoringPhase.gd:584-586 (destroy reserves not arrived by the end of round 3)
  - _…and 5 more_
- **Absorbed duplicates:** OBJ-31 (Time the reserves: hold arrivals for round 3 or for Rapid Ingress)
- **Found by:** core-rules, youtube, first-principles

#### TRN-14 — Combat-disembark out of an engaged or boxed-in transport

When the transport has not moved (it is engaged and staying put, or ringed so tightly that no unengaged 3″ set-up exists), the cargo must use combat mode. It is set up wholly within 6″, may be set up engaged with units the transport is engaged with, and makes one hazard roll per model (D6: 1-2 is a mortal wound). It is then battle-shocked (OC '-', no actions, no friendly stratagems on it) and cannot charge this turn. Uses: escaping a transport about to die (the alternative, an emergency disembark, also battle-shocks the unit, loses any models that cannot be placed, and then Deadly Demise can hit it); getting bodies into a fight (an engaged unit fights, and can use close-quarters shooting with [CLOSE-QUARTERS] weapons); or tying up the units attacking the transport. It cannot add OC. Disembark before the transport falls back, because a transport that fell back bars every disembark.

- **When:** The transport is locked in combat or surrounded and staying stationary; the cargo is worth more outside (it fights well, or the transport will probably die); and the expected hazard losses (about 1 mortal wound per 3 models) are acceptable. If an unengaged 3″ set-up exists, tactical mode is mandatory instead (TRN-03).
- **Units:** Units in an engaged or crowded TRANSPORT; melee cargo; cargo with [CLOSE-QUARTERS] weapons.
- **Move type:** Disembark (combat mode)
- **11e rules (corrected):** 18.04 mode order: rapid if the transport moved; tactical if it is stationary or not yet moved and a 3″ set-up is possible; otherwise combat. Combat cargo may be set up engaged with units the transport is engaged with, and afterwards is battle-shocked and cannot charge (40k_11th_edition_core_rules.txt:3029-3057). 03.02: a set-up must be unengaged (:491-507). 06.03 hazard roll (:1067-1072). Battle-shock effects (:213-221). 10.06 close-quarters shooting (:1522-1545). 18.05 with errata, and 24.08 ordering (:3061-3078; errata_faq:609; :3670-3699). Corrections: first-principles#82's 'add OC to an objective' is impossible (battle-shocked OC '-'); web#52's 'if the transport is engaged ... combat disembark' only holds when no unengaged tactical set-up exists.
- **AI today (none):** The AI's CONFIRM_DISEMBARK payload never sets can_setup_tactical=false (AIDecisionMaker.gd:8477-8483). _compute_disembark_positions only places models within 3″ and outside engagement range (8626+); if that fails, the unit is marked as failed and stays aboard (AIPlayer.gd:2648-2657). Nothing gets cargo out before its transport falls back.
- **Engine support:** Reuse DisembarkMove.select_mode / before_moving (DisembarkMove.gd:64-111); CONFIRM_DISEMBARK with payload.can_setup_tactical=false (MovementPhase.gd:8509-8511, 8760); _estimate_incoming_melee_damage (AIDecisionMaker.gd:12350) for the transport's survival; _estimate_melee_damage (19576) for the cargo's fight value. New: a combat-disembark placement solver (6″, may engage the transport's foes) and a score weighing hazard losses plus battle-shock against staying aboard.
- **Value (medium):** Situational, but decisive when a loaded transport is locked in combat or about to die.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3029-3057
  - /home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/DisembarkMove.gd:88-95, 99-111, 130-132
  - /home/user/warhammer-40k-godot/40k/phases/MovementPhase.gd:8509-8511, 8568 (engaged only with the transport's foes), 8760 (combat toggle → can_setup_tactical=false)
  - https://www.greenstuffworld.com/en/blog/all-about-warhammer-40k-11th-edition-rules-news-and-armageddon-box-n144 (search snippet: 6″ set-up, can start engaged, a roll per model, battle-shocked, no charge)
- **Found by:** core-rules, web, first-principles

#### TRN-16 — Drive a Firing Deck transport into firing position

A TRANSPORT with Firing Deck X lends itself one ranged weapon each from up to X embarked models (no [ONE SHOT] weapons) in your Shooting phase, and the passengers then cannot shoot. Move it to where those borrowed weapons have range and line of sight to good targets, while the passengers stay protected inside. The borrowed guns are fired by the transport: if it advanced, only [ASSAULT] weapons can fire, and the passengers' own abilities do not boost them.

- **When:** Embarked shooters have targets within reach of the transport's move but would be exposed on foot, or the cargo is waiting to disembark later (TRN-04).
- **Units:** TRANSPORTs with Firing Deck, and their shooting cargo.
- **Move type:** Normal (transport) / Remain Stationary
- **11e rules (verified):** 24.14 Firing Deck (40k_11th_edition_core_rules.txt:3705-3730). FAQ: abilities that affect the weapons in the passengers' hands do not apply when the transport fires them (40k_11th_edition_errata_faq_commentary.md:620, 690-691). 10.04 / 10.05 normal vs assault shooting after an advance (:1489-1518). Engine: ShootingPhase.gd:1278-1309 (transport_data.firing_deck, _compute_firing_deck_plan).
- **AI today (none):** Movement never values the cargo's guns. A loaded transport has its weapon range set to zero for hold-for-shooting and range clamping (AIDecisionMaker.gd:7398-7402). The only Firing Deck reference in AI code is the +0.4 'no Firing Deck' disembark bonus, and that reads ability names rather than transport_data.firing_deck (8603-8616).
- **Engine support:** Reuse the ShootingPhase Firing Deck plan logic (ShootingPhase.gd:1278-1309); RulesEngine.max_ranged_weapon_range_inches on the embarked units (RulesEngine.gd:6693); the firing-position helpers (AIDecisionMaker.gd:13669-13754, 13848-13904) using the borrowed weapons' ranges. New: when choosing a loaded Firing Deck transport's destination, treat it as a shooter with the borrowed profiles.
- **Value (medium):** Lets cargo shoot from safety every turn. Firing Deck is common on transports, and the AI ignores the borrowed guns entirely.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3705-3730
  - /home/user/warhammer-40k-godot/40k/phases/ShootingPhase.gd:1278-1309
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:7398-7402, 8603-8616
  - docs/rules/40k_11th_edition_core_rules.txt:3705-3730
  - .llm/codex_11e_wahapedia/orks/wahapedia/Abilities.csv:3 (Firing Deck 24.14); orks/RULES.md:213 (DRIVE-BY BUSTIN')
  - docs/rules/11th_edition_delta_audit.md (24.14 row, ISS-071)
- **Absorbed duplicates:** OFF-26 (Drive a Firing Deck transport into a firing position)
- **Found by:** first-principles, core-rules, factions

#### TRN-21 — Relocate a unit through strategic reserves (Da Jump, Teleport-shunter, Shokk Attack Engine)

Use an own-turn ability that puts a unit into strategic reserves so it can arrive somewhere else. Weirdboy Da Jump: a psychic roll in the Movement phase, once per army per battle round; the unit goes into reserves with Deep Strike, and on a 1 it is also battle-shocked. Shield-Captain in Allarus, Archeotech Teleport-shunter: once per battle, if unengaged and not yet selected to move; it goes into reserves and must ingress this phase. Wazdakka Gutsmek, Shokk Attack Engine: Command phase, if unengaged. With Deep Strike the unit can drop anywhere more than 8″ from enemies, even in the enemy deployment zone, leaving a dead-end position without a Fall Back. A unit relocated after it was already selected to move cannot ingress again this phase (each unit is selected once). Repositioned units are exempt from the round-3 destruction.

- **When:** The unit is 15″ or more from every useful objective or target, or would be charged or shot off with no other escape, and a better spot more than 8″ from all enemies exists. Avoid it when: the unit's OC is holding a contested objective (it stops scoring where it was, which costs most under Take and Hold-style cards); the unit is Condemned by the opponent's Punishment card (leaving the battlefield pays them); or it is round 1 (strategic reserves cannot arrive until round 2).
- **Units:** Weirdboy (and its attached unit), Shield-Captain in Allarus Terminator Armour, Wazdakka Gutsmek. Chapter-only equivalents are out of scope.
- **Move type:** other (ability: place in strategic reserves), then Reserves arrival
- **11e rules (verified):** 20.02 repositioned units: such rules can be used on units that already moved; a unit set up again the same turn still counts as having made its advance, fall-back or disembark move (40k_11th_edition_core_rules.txt:3219-3235). 20.03 (:3250-3254). 20.04, including the repositioned-unit exemption (:3276-3283). 24.09 (:3649-3655). 09.02: each unit is selected once per phase (:1345-1356). Datasheets: Da Jump (.llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:23), Shokk Attack Engine (:268), Archeotech Teleport-shunter (custodes/wahapedia/Datasheets_abilities.csv:34; RULINGS.md:96: round 2+ only).
- **AI today (none):** Explicitly declined: da_jump and shokk_attack_engine score 0.0 ('repositioning through reserves is a plan-level decision'; OrkAbilities11e.gd:2325-2326, 2337-2338), as does archeotech_teleport_shunter (CustodesAbilities.gd:1329-1330); see also RULINGS.md:197.
- **Engine support:** Reuse the ability windows the engine already has (RULINGS.md:96, 117, 183), the _decide_reserves_arrival placement with Deep Strike (AIDecisionMaker.gd:7728), and _evaluate_all_objectives (8926) to price the OC given up. New: an ai_score that compares the best Deep Strike landing against the value of the unit's current position (objective OC, threat).
- **Value (medium):** A strong relocation tool, but faction-specific, and currently never used.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:23
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/custodes/wahapedia/Datasheets_abilities.csv:34
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/RULINGS.md:96, 183, 197
  - YouTube veM7sLjtdIw @01:00 (Warpbane Tactics): “Picking a unit up is incredibly useful, but under Take and Hold, that decision becomes more costly”
  - /home/user/warhammer-40k-godot/40k/autoloads/MissionManager.gd:1955-1965 (a Condemned unit leaving the battlefield)
  - YouTube veM7sLjtdIw @01:00 (Warpbane Tactics, F027): 'being careful about when we use our teleportation. Picking a unit up is incredibly useful, but under Take and Hold, that decision becomes more costly'
  - _…and 3 more_
- **Absorbed duplicates:** COO-25 (Redeploy with a repositioning ability when the VP math is positive)
- **Found by:** factions, core-rules, youtube, web

#### TRN-13 — Disembark to add a scoring or action unit

A transport and its cargo are separate units, and many cards pay per unit or need distinct units: Behind Enemy Lines (per unit in the enemy deployment zone), Gather Intel (7 VP per unit that completes Extract Intelligence), Sabotage (one objective per saboteur), Booby Trap (one area per unit), Engage on All Fronts (quarter presence), Display of Might (units in No Man's Land), Outflank (two units on opposite edges). Disembarking puts a second unit on the board. A rapid disembark (the transport has moved) can still start actions. A tactical disembark followed by a Normal move keeps action eligibility; an Advance loses it. Do not use a combat disembark for this: it battle-shocks the unit (OC '-', no actions, no positional cards). A transport parked near a quarter line can drop its cargo wholly into the next quarter.

- **When:** Count-based or one-per-unit cards are active, a loaded transport is near the target geometry, and the cargo will survive to the scoring point.
- **Units:** TRANSPORTs and their cargo.
- **Move type:** Disembark (rapid, or tactical + Normal)
- **11e rules (verified):** 18.04 modes (40k_11th_edition_core_rules.txt:3013-3057). 16.01 action eligibility (:2808-2817). Battle-shocked: OC '-', no actions (:213-221). Cards: 40k/data/40kdc/missionCards.json (behind-enemy-lines, outflank, engage-on-all-fronts, display-of-might, gather-intel, sabotage); docs/rules/11th_edition_missions_gdm2026.md:111-150.
- **AI today (partial):** _score_disembark_benefit rewards a transport on or near an objective (+0.8 + 0.1 × OC within 3″, +0.4 within 6″, +0.15 within 12″; AIDecisionMaker.gd:8512-8527) and rounds 2+ (8563-8570). Nothing counts per-unit card value, quarters, the enemy deployment zone, edges or actions, and placement faces the nearest objective (8626+).
- **Engine support:** Reuse _get_covered_quarters (AIDecisionMaker.gd:24260); _assess_behind_enemy_lines / _assess_outflank / _assess_engage_on_all_fronts (23223, 23699, 23265); the MissionManager card-action queries (MissionManager.gd:2030-2266); _compute_disembark_positions (8626). New: a per-unit card value term in _score_disembark_benefit, and placement aimed at the card's geometry (e.g. wholly within the adjacent quarter).
- **Value (medium):** Turns one unit on the board into two for count-based cards: moderate VP when the right cards are in play.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2999-3058
  - /home/user/warhammer-40k-godot/docs/rules/11th_edition_missions_gdm2026.md:142-146 (Gather Intel: 7 VP per friendly unit that completed the action)
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:8498-8624
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3013-3056
  - /home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd:8417-8832 (disembark scoring has no mission terms)
- **Absorbed duplicates:** MIS-31 (Disembark at the scoring spot in a mode that keeps the unit scoring)
- **Found by:** missions

#### TRN-15 — Drive first, then assault- or shock-disembark (faction transport grants)

Some transports change the trade so that moving first no longer costs the charge. Assault disembarks (18.06: 3″, no charge ban) after the transport's Normal move: the Land Raider family's Assault Ramp, the Morkanaut/Gorkanaut Gut Hatch, Blitz Brigade READIED BRAWLERS (Wagons), MEKANISED BRUTALITY (Ork rig), Thunderhawk Aerial Assault, and Drop Pod / Termite Assault. These give transport M + 3″ + 2D6. The Impulsor's Rapid Disembarkation allows a shock disembark (18.07: 3″, no charge) after the transport ADVANCED, a fast gunline delivery. Gauntlet AGGRESSIVE DISEMBARKATION sets models up within, rather than wholly within, the set-up distance. With the Orion Assault Dropship, cargo can tactical-disembark, advance and still charge.

- **When:** Assault grants: the transport's move + 3″ + a charge reaches a target the cargo cannot reach on foot. Shock disembark: shooters need transport M + D6 + 3″ to get in range this turn. Either way, the transport must survive the approach and end somewhere the cargo can be placed.
- **Units:** Land Raiders (including Crusader, Redeemer, Venerable), Morkanaut/Gorkanaut, Ork Wagons and rigs (Blitz Brigade), Thunderhawk, Drop Pods / Termites, Impulsor, Orion Assault Dropship, Gauntlet Task Force transports, and their cargo.
- **Move type:** Normal / Advance (transport), then Disembark (assault 18.06 / shock 18.07)
- **11e rules (corrected):** 18.04 baseline (40k_11th_edition_core_rules.txt:3013-3057). Faction move types: 18.06 ASSAULT DISEMBARK (3″; no charge restriction afterwards; transport not advanced or fallen back) and 18.07 SHOCK DISEMBARK (3″; no charge) (.llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md:16-19). RULINGS.md:423 (Assault Ramp / Rapid Disembarkation), :501 (Drop Pod Assault). Datasheets: orks/wahapedia/Datasheets_abilities.csv:143 (Gut Hatch), orks/RULES.md:202 (READIED BRAWLERS), custodes/wahapedia/Datasheets_abilities.csv:90 (Assault Dropship). Engine: DisembarkMove.gd:64-82; TransportManager.gd:284-295 (MEKANISED BRUTALITY / READIED BRAWLERS keep charge eligibility).
  - _Skeptic:_ Assault Dropship (custodes Datasheets_abilities.csv:90) is not a drive-first grant. It applies to a TACTICAL disembark, where the transport is stationary or not yet moved (18.04 :3032-3035), and lets the follow-up Advance keep charge eligibility, so it belongs with TRN-03. The drive-first grants check out: Gut Hatch (orks csv:143), READIED BRAWLERS (orks/RULES.md:202), Assault Ramp / Rapid Disembarkation (RULINGS.md:423). 18.06 assault disembark: 3″, transport must not have advanced or fallen back, no charge restriction. 18.07 shock disembark: 3″, no charge afterwards (SPACE_MARINES_GENERIC.md:16-19). — custodes/wahapedia/Datasheets_abilities.csv:90; 40k_11th_edition_core_rules.txt:3029-3057; space-marines/SPACE_MARINES_GENERIC.md:16-19; orks/wahapedia/Datasheets_abilities.csv:143
- **AI today (partial):** Follow-ups are taken when offered: assault_ramp / aerial_assault score 2.0 with an enemy within 12″ (SMAbilitiesA.gd:2279-2283), gut_hatch 2.0 (OrkAbilities11e.gd:2323-2324), READIED BRAWLERS 2.5 with an enemy within 12″ and ≥ 2 CP (OrkCodexMovement.gd:296-299); AGGRESSIVE DISEMBARKATION scores 0.0 (SMCodexAMovement.gd:295-297). But the AI decides disembarks at Step 1.75, before any transport moves (AIDecisionMaker.gd:6823-6828), so cargo usually gets out first, and drive-then-assault only happens when it stayed aboard by chance. Possible engine issue, read from code and not validated: the Land Raider Redeemer's Assault Ramp checks flags.moved_this_phase (SMAbilitiesB.gd:834-840), which a Normal move never writes (only SurgeMove.gd:113 does; tests set it by hand, test_sm11e_abilities_b.gd:1148).
- **Engine support:** Reuse SMAbilitiesA.transport_grants_assault_disembark (SMAbilitiesA.gd:1109), SMAbilitiesB.transport_allows_shock_disembark (SMAbilitiesB.gd:847), the OrkCodexMovement assault-disembark candidates, and the TransportManager charge flags (TransportManager.gd:281-300). New: for transports with such grants, plan 'transport moves toward the target, then assault disembark + charge' as one candidate, and skip the early Step 1.75 disembark for that cargo.
- **Value (medium):** Faction-specific, but for Land Raider, Gorkanaut and Wagon armies it is the whole point of the transport.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md:16-19
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/RULINGS.md:423, 501
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_marines/SMAbilitiesA.gd:1109-1113, 2279-2283
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_marines/SMAbilitiesB.gd:834-853
  - /home/user/warhammer-40k-godot/40k/scripts/stratagems/ork_codex/OrkCodexMovement.gd:296-299
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_marines/SMCodexAMovement.gd:295-297
- **Found by:** factions

#### TRN-17 — AIRCRAFT: choose a fresh ingress spot every turn

AIRCRAFT start in strategic reserves and can only make ingress moves: wholly within 6″ of an edge, more than 8″ from enemies, and outside the enemy deployment zone before round 3. They go back into reserves at the end of the opponent's turn, so each turn is a fresh edge set-up, chosen for firing lanes and limited exposure. They cannot charge, start actions, count for most positional cards, or use Rapid Ingress. Other units can move through them, Plunging Fire does not apply to attacks by or against them, and only FLYING units can choose them as charge targets. A large aircraft that cannot fit wholly within 6″ may be set up touching the edge and may overhang it.

- **When:** Every own Movement phase from round 2 (round 1 with Impulsive Recon).
- **Units:** AIRCRAFT.
- **Move type:** Reserves arrival (ingress only)
- **11e rules (verified):** 23.01-23.04 (40k_11th_edition_core_rules.txt:3499-3531). 20.04 (:3255-3274). 16.01: AIRCRAFT cannot start actions (:2811-2812). 15.07 excludes AIRCRAFT (:2724). Setting up large models from strategic reserves (40k_11th_edition_errata_faq_commentary.md:244). Positional cards exclude AIRCRAFT (missionCards.json: outflank, engage-on-all-fronts, behind-enemy-lines, display-of-might).
- **AI today (partial):** Aircraft arrive through the generic reserve path every turn (Step 1.5, AIDecisionMaker.gd:6815-6821). Edge candidates are ranked by objective proximity and the 10-15″ enemy-centroid band (8073-8135, 8204-8240), with +1.0 for ranged units in the arrival order (7971-7972). There is no aircraft-specific term: nothing for firing lanes, line of sight to targets, anti-air threats or exposure. Objective proximity is worthless for a unit that cannot score positional cards or start actions.
- **Engine support:** Reuse the arrival generators (AIDecisionMaker.gd:8073), _is_valid_reinforcement_position (8331), RulesEngine.get_eligible_targets on a board copy (RulesEngine.gd:7137) or TerrainManager.model_visible_11e (TerrainManager.gd:1209) for lanes, and _calculate_enemy_threat_data (AIDecisionMaker.gd:28695) for exposure. New: for AIRCRAFT, score edge spots by expected damage to the best visible targets minus incoming fire. Engine notes (read from code, not validated): (1) TurnManager returns the ending player's own aircraft at the end of that player's turn (TurnManager.gd:76-83 calls GameState.return_aircraft_to_reserves(get_active_player())), whereas 23.02 says the end of the opponent's turn. (2) _destroy_remaining_reserves exempts only repositioned units (ScoringPhase.gd:966-971), not units that have already made an ingress move, so an aircraft sitting in reserves at the end of round 3 may be destroyed, contrary to 20.04.
- **Value (medium):** Matters every turn for armies with aircraft, but few lists field them.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3499-3531
  - /home/user/warhammer-40k-godot/40k/phases/MovementPhase.gd:624-626 (AIRCRAFT can only make ingress moves)
  - /home/user/warhammer-40k-godot/40k/autoloads/TurnManager.gd:76-83 and /home/user/warhammer-40k-godot/40k/autoloads/GameState.gd:613-660 (return-to-reserves cycle)
  - https://www.40k.app/rules/20-strategic-reserves (cited by the web stream)
- **Found by:** core-rules, web

#### TRN-18 — Arrive in the enemy backfield (deployment zone) where reserves normally cannot

Strategic reserves cannot set up in the opponent's deployment zone before round 3, but Deep Strike ignores that (anywhere more than 8″ from enemies). Faction rules also lift it: the Scout Bike Squad's Outflank (its ingress may set up in the opponent's deployment zone); Logan Grimnar's High King of Fenris (one Space Wolves unit treats the round as one higher, so it can arrive in round 1, or in the deployment zone in round 2); and the Terminators' Teleport Homer (a Rapid Ingress within 3″ of a token placed at the start of the battle, at −1 CP). The aim: threaten the enemy home objective, backline artillery and characters, or Behind Enemy Lines from round 2.

- **When:** Round 2, or round 3 for plain strategic reserves. The enemy home objective or backline is lightly screened (a legal spot more than 8″ from every enemy unit exists), and the unit can survive, or the score or kill is worth losing it.
- **Units:** Deep Strike units; Scout Bike Squad; Space Wolves reserves with Logan; Terminator Squad / Terminator Assault Squad (homer).
- **Move type:** Reserves arrival (Teleport Homer: adjacent, via Rapid Ingress)
- **11e rules (verified):** 20.04: 'before the third battle round ... no models can be set up within your opponent's deployment zone' (40k_11th_edition_core_rules.txt:3267-3269). 24.09: 'even if that is within your opponent's deployment zone' (:3649-3655). Outflank datasheet text (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:161); Teleport Homer (:108; RULINGS.md:502); High King of Fenris (RULINGS.md:317). Engine: IngressMove.gd:103 (deployment-zone ban skipped for Deep Strike); MovementPhase.gd:4311-4317 (the Outflank exemption is deliberately not applied at edition 11, pending a rules call).
- **AI today (partial):** Deep Strike candidates (rings round objectives plus a board grid) have no deployment-zone filter (AIDecisionMaker.gd:8137-8170), and strategic reserves are only kept out of the enemy deployment zone in round 2 (8083, 8367). So arrivals can land in the backfield, but only when a nearby objective needs OC (8204-8223); there is no term for backline targets, the enemy home objective or Behind Enemy Lines. The faction lifts go unused: Teleport Homer and High King of Fenris score 0.0 (SMAbilitiesA.gd:2284-2285; SWAbilities11e.gd:1839-1840), and the engine does not honour the Outflank datasheet at 11e (MovementPhase.gd:4311-4317).
- **Engine support:** Reuse _get_deployment_zone_polygon_pixels (AIDecisionMaker.gd:24856), _generate_deep_strike_candidates (8137), _assess_behind_enemy_lines (23223), and _estimate_unit_value (28003) for backline targets. New: a set of backfield candidates inside the enemy deployment zone, scored by home-objective VP, Behind Enemy Lines VP and the value of backline targets; read whether High King or a homer token is available.
- **Value (medium):** Backfield pressure forces the opponent to keep units at home and scores Behind Enemy Lines and enemy-home cards, but it relies on gaps in their screen.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:108, 161
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/RULINGS.md:317, 502
  - /home/user/warhammer-40k-godot/40k/phases/MovementPhase.gd:4311-4317
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_marines/SMAbilitiesA.gd:2284-2285 (teleport_homer 0.0)
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_wolves/SWAbilities11e.gd:1839-1840 (high_king_of_fenris 0.0)
- **Found by:** core-rules, factions, missions

#### TRN-19 — Transport strike: deliver the cargo to kill a key target, accepting the squad's loss

Keep a lethal squad aboard until the strike turn, then drive the transport in and disembark it to remove one key enemy piece (an enabler, character or scoring unit), expecting the squad not to survive the reply. The disembark can be tactical then charge, rapid then shoot, or a faction assault disembark. Judge the trade on what the kill is worth against what the squad is worth.

- **When:** A key target is within transport move + disembark + weapon or charge reach, and the trade is worth it (the target is an enabler, character or scoring unit). Rounds 1-3; be cautious again in rounds 4-5. Avoid it against an opponent on a kill-based primary such as Purge the Foe, where losing the squad feeds their score.
- **Units:** Glass-cannon squads that ride in transports: Drukhari Incubi / Wyches / Kabalites, Ork Boyz / Tankbustas, Marine melta or assault teams.
- **Move type:** Normal (transport) + Disembark (tactical / rapid / assault)
- **11e rules (verified):** 18.04 modes (40k_11th_edition_core_rules.txt:3013-3057). 18.06 assault disembark through faction grants (.llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md:16-19). 11.02 / 11.04 charge rules (:1603-1650). The trade judgement itself is player opinion (YouTube finding F025: medium confidence, 4 channels).
- **AI today (partial):** Only generic nudges exist. Disembark scoring adds +0.3, plus 0.1 per enemy in range, for shooters (AIDecisionMaker.gd:8529-8544), and +0.4 for melee units with an enemy within M + 15″ (8546-8561). Targets are never valued. The disembark happens before the transport moves (6823-6828), and the threat dodge actively steers fragile or expensive units away from exposure (28892-28990). The Drukhari draft profile is not shipped, and the TRADE verb is rejected.
- **Engine support:** Reuse _estimate_melee_damage (AIDecisionMaker.gd:19576), _estimate_weapon_damage (17984), _estimate_unit_value (28003), the charge-intent lock targets (3773-3946), and the profile parameters loaded by ProfileManager (40k/scripts/ProfileManager.gd). New: a strike candidate made of transport destination + disembark mode + target, scored by the value of the kill minus the value of the squad lost.
- **Value (medium):** The core of Drukhari and Ork transport play, but rare elsewhere.
- **Evidence:**
  - YouTube jJwrYZs3l-I @11:00 (Deploy on the Line 40K): “squad in transport. They're going to suicide themselves”
  - YouTube nCQuNE_8V44 @19:00 (SkaredCast): “you didn't need the entire unit to kill them. They died very fast. Should have kept them in the transport”
  - /home/user/warhammer-40k-godot/research/youtube/profiles/drukhari.json (draft profile: TRADE_UNFAVORABLE_PENALTY 0.9, round-4 caution rule; not shipped, since 40k/data/ai_profiles holds only baseline_2026_08.json)
  - /home/user/warhammer-40k-godot/40k/docs/PLAN_FORMAT.md:532-535 (the TRADE verb is rejected as 'reserved for v2')
- **Found by:** youtube

#### TRN-20 — Ingress a loaded transport and Rapid-disembark the cargo the same turn

Units inside a TRANSPORT in strategic reserves arrive with it; they cannot make an ingress move themselves. After the transport's ingress move, the cargo may disembark in rapid mode in the same phase. Every model must obey the transport's ingress restrictions (more than 8″ from all enemy units; not in the opponent's deployment zone before round 3), and the cargo cannot charge. Cargo inside a transport that has made an ingress move is also safe from the end-of-round-3 reserves destruction.

- **When:** Rounds 2-3, to put scoring or action units onto an edge or flank objective, or to deliver two units with one arrival.
- **Units:** A TRANSPORT in strategic reserves, and its cargo.
- **Move type:** Reserves arrival (transport ingress), then Disembark (rapid)
- **11e rules (verified):** 20.04 eligibility excludes units embarked in transports that are themselves in reserves (40k_11th_edition_core_rules.txt:3258-3260). 18.04: rapid mode after an ingress move; the models follow the transport's ingress rules; they cannot charge afterwards (:3030-3052, with its sidebar; 40k_11th_edition_errata_faq_commentary.md:635). 20.04: end-of-round-3 exception (:3276-3281). 20.01: the 50% points cap counts embarked units (:3205-3216).
- **AI today (partial):** Happens incidentally. A reserve transport arrives through the generic path, with its spot chosen for the transport's own objective value (AIDecisionMaker.gd:7949-8240); Step 1.75 then disembarks the cargo on a later decision if its score is > 0 (6823-6828, 8417-8496). Disembark placement does not apply the >8″ or enemy-deployment-zone restrictions. Code reading suggests the engine's CONFIRM_DISEMBARK validation does not either: it checks 3″, engagement range, the board edge and coherency (MovementPhase.gd:8480-8580). Not validated live.
- **Engine support:** Reuse _compute_reinforcement_positions (AIDecisionMaker.gd:8019) driven by the cargo's needs; _compute_disembark_positions (8626) plus the checks in IngressMove.validate_setup (IngressMove.gd:44-112) for the cargo's set-up. New: score a reserve transport's arrival by the cargo's objective and action value at arrival point + 3″.
- **Value (medium):** One arrival delivers two scoring units and protects the cargo from the round-3 deadline, but such lists are uncommon.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:3039-3057, 3255-3283
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_errata_faq_commentary.md:633-635
  - /home/user/warhammer-40k-godot/40k/phases/ScoringPhase.gd:975-981 (the cargo of a transport still in reserves is destroyed with it)
- **Found by:** core-rules

#### TRN-22 — Drop in during battle round 1 with a first-turn ingress grant

Strategic reserves cannot normally arrive in round 1, but some rules allow an ingress in your first Movement phase: Ork aircraft with Impulsive Recon; Space Marine Terminators with the Corporeum Reliquary; the Custodes Shield-Captain in Allarus with Lightning Descent; Drop Pod / Termite Assault (the cargo must disembark more than 8″ from enemies when it lands); and Logan Grimnar's High King of Fenris (one unit treats the round as one higher). Boss Snikrot's Deff from the Shadows (end of the opponent's Movement phase, from round 1) is not implemented. The aim is to take a far objective or hit an exposed backline unit before the opponent's screens and Rapid Ingress denial are in place. A round-1 ingress still cannot enter the enemy deployment zone unless the unit has Deep Strike.

- **When:** Round 1, while enemy screens are incomplete and a target or objective is more than 8″ from all enemies; best with arrival-turn buffs (TRN-06 / TRN-07).
- **Units:** Ork AIRCRAFT (Impulsive Recon), Terminator units (Corporeum Reliquary), Shield-Captain in Allarus (Lightning Descent), Drop Pod / Termite cargo, Space Wolves reserves with Logan, Boss Snikrot.
- **Move type:** Reserves arrival (battle round 1)
- **11e rules (verified):** 20.03: 'Unless otherwise stated ... from the second battle round onwards' (40k_11th_edition_core_rules.txt:3250-3254). 20.04 (:3255-3274). Texts: orks/RULES.md:264 (Impulsive Recon), space-marines/wahapedia/Datasheets_abilities.csv:61 (Drop Pod Assault) and :463 (Termite Assault), custodes/RULES.md:115 (Lightning Descent), RULINGS.md:366 (Corporeum Reliquary), :501 (Drop Pod Assault), :317 (High King of Fenris); ork_abilities_audit.md:21 (Deff from the Shadows not implemented).
- **AI today (partial):** Any round-1 PLACE_REINFORCEMENT the engine offers (MovementPhase.gd:7800-7812) is taken by the generic arrival logic (AIDecisionMaker.gd:6815-6821, 7728) with objective-proximity placement, and Drop Pod cargo disembarks automatically (RULINGS.md:501). High King of Fenris is declined (SWAbilities11e.gd:1839-1840), and Deff from the Shadows is not implemented. The AI's strategic-reserves spot filter keeps out of the enemy deployment zone only when battle_round == 2 (8083, 8367). Round-1 candidates can therefore sit inside the enemy deployment zone, and IngressMove.validate_setup (battle_round < 3; IngressMove.gd:103) would reject them. Read from code; not validated live.
- **Engine support:** Reuse the same arrival path and change the round test to battle_round < 3. New: a round-1 arrival value that weighs the objective taken before the opponent moves against the threat of their turn-1 reply.
- **Value (medium):** A tempo swing for the few lists that have it; today it is handled only generically.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/orks/RULES.md:264
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:61
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/RULINGS.md:317, 366, 501
  - /home/user/warhammer-40k-godot/40k/phases/MovementPhase.gd:7800-7812 (round-1 ingress offered for Lightning Descent / Impulsive Recon units)
- **Found by:** factions

#### TRN-N01 — Bail out of a transport before it is destroyed _(added by completeness review)_

If the loaded transport will probably die before your next Movement phase, disembark now while you still choose the mode and the spot. An emergency disembark is much worse. Every model makes a hazard roll (a 1-2 inflicts a mortal wound). Models are set up as close as possible to the wreck: engaged if no unengaged spot exists, destroyed if neither fits. The unit is battle-shocked and cannot charge. And it happens before the hull's Deadly Demise roll, so the survivors sit inside its 6″ radius. A Tactical Disembark before the transport moves keeps the unit's own Normal move and charge; afterwards the empty hull can still act (block, screen, ram).

- **When:** The transport has few wounds left, or faces enough anti-tank to kill it next turn (expected damage at least its remaining wounds), and the cargo has a useful job within 3″ plus its M. Strongest when the transport has Deadly Demise or is engaged.
- **Units:** Transports and their passengers (Rhinos, Trukks, Raiders, Wave Serpents, Impulsors)
- **Move type:** Disembark (Tactical, then a Normal move) / Disembark (Rapid, after the transport moves)
- **11e rules (verified):** 18.04 disembark eligibility and modes (40k_11th_edition_core_rules.txt:3013-3058). 18.05 emergency disembark, with its errata (:3061-3086; 40k_11th_edition_errata_faq_commentary.md:609-611). 06.03 hazard rolls (:1067-1074). 24.08 Deadly Demise resolves after emergency disembarks (:3670-3700).
- **AI today (partial):** _score_disembark_benefit Factor 5 (AIDecisionMaker.gd:8572-8587) adds DISEMBARK_TRANSPORT_THREATENED whenever any enemy ranged weapon of S7+ is within 24″, regardless of the hull's remaining wounds or the expected incoming damage. Nothing prices the cost of an emergency disembark (hazard rolls, battle-shock, as-close-as-possible placement, the Deadly Demise radius).
- **Engine support:** AIAbilityAnalyzerData.is_unit_doomed (AIAbilityAnalyzer.gd:595, used at AIDecisionMaker.gd:7472), _estimate_unit_remaining_wounds (:12362), and AIAbilityAnalyzerData.has_deadly_demise / get_deadly_demise_value (AIAbilityAnalyzer.gd:546/559). New: the expected ranged damage on the hull in the next enemy turn (reuse the shooting-phase damage estimator against the transport), compared with its remaining wounds.
- **Value (medium):** Saves whole squads, and their OC, from hazard rolls, battle-shock and Deadly Demise; the current trigger fires on any S7 gun within 24″.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:3061-3086 (18.05) and errata md:609-611
  - AIDecisionMaker.gd:8572-8587: the existing disembark trigger fires on any S7+ gun within 24″, whatever the hull's state
- **Found by:** cross_bucket_critic

#### TRN-23 — Embark a slow unit to taxi it (ride the transport this phase or next)

Use a transport to move a unit that is badly out of position. The unit makes its Normal or Advance move so that every model ends within 3″ of a transport that has not yet been selected to move, and embarks; the transport then makes its own move carrying it. Next turn it tactical-disembarks (3″ + M, keeps the charge) or rapid-disembarks after another transport move. Total reach: its own move plus the transport's move this turn, then 3″ + M (or transport M + 3″) next turn. It cannot disembark again in the phase it embarked, and a unit set up this turn (disembarked or arrived from reserves) cannot embark.

- **When:** Slow infantry is far from the objective or fight it is needed at within 1-2 turns, and a transport with capacity is within reach and not needed for anything else. Unlike TRN-05, the purpose is distance, not protection.
- **Units:** Slow infantry, and a friendly TRANSPORT with capacity.
- **Move type:** Normal / Advance, then Embark (the transport then makes a Normal / Advance move)
- **11e rules (verified):** 18.02 Embarking: after a normal, advance or fall-back move; all models within 3″; not set up this turn; enough capacity (40k_11th_edition_core_rules.txt:2981-2997). 18.04 eligibility: 'did not embark within that TRANSPORT this phase' (:3023) is the only same-phase restriction. No 11e text bars the transport from moving after a unit embarks, and 09.02 lets the transport, not yet selected, be selected afterwards (:1345-1356). FAQ: a rule letting a unit embark in the turn it disembarked overrides 18.02 (40k_11th_edition_errata_faq_commentary.md:621-622). Engine: DisembarkMove.gd:49-51 (embarked_this_phase only blocks disembarking); MovementPhase.gd:9176-9182. first-principles#84 marked this unconfirmed; the local text has no restriction.
- **AI today (none):** The AI never emits EMBARK_UNIT (it appears in neither AIDecisionMaker.gd nor AIPlayer.gd), and MovementPhase skips the embark prompt for AI players (MovementPhase.gd:8306-8311). Transports move last (tier 2, AIDecisionMaker.gd:7657-7664), which would suit a pick-up, but nothing plans one.
- **Engine support:** Reuse TransportManager.can_embark / is_unit_within_embark_range (TransportManager.gd:107, 784); _capture_arrival / _unit_gap_to_objective_px (AIDecisionMaker.gd:13091, 13163) to compare arrival turns on foot and riding; the movement executor (14212). New: a 'pick-up' candidate (move to within 3″ of a transport, EMBARK_UNIT, then the transport's move). The AI must check the range itself, because _validate_embark_unit (MovementPhase.gd:9120-9150) does not.
- **Value (low):** Rescues slow units that would otherwise contribute nothing. Uncommon, but cheap when a transport is idle.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:2981-2997, 3020-3025
  - /home/user/warhammer-40k-godot/40k/scripts/rules/movetypes/DisembarkMove.gd:49-51
  - /home/user/warhammer-40k-godot/40k/phases/MovementPhase.gd:9176-9182
  - /home/user/warhammer-40k-godot/40k/autoloads/TransportManager.gd:107-170
- **Found by:** core-rules, first-principles

#### TRN-24 — Fall back and embark to pull a unit out of combat

An engaged unit makes a Fall Back move (Ordered Retreat, or Desperate Escape with hazard rolls if it is battle-shocked) that ends with every model within 3″ of a friendly transport with room, and then embarks. It is removed from the battlefield, so it cannot be charged, shot or fought next turn, and it can disembark next turn.

- **When:** A valuable unit is stuck in a fight it is losing, a friendly transport with capacity is within its M, and it has no job left where it is. Falling back already costs its shooting, charge and actions this turn, so embarking costs little more.
- **Units:** Engaged units that fit a nearby friendly TRANSPORT.
- **Move type:** Fall Back, then Embark
- **11e rules (verified):** 09.07 Fall-back move: maximum M; engaged units only; Ordered Retreat or Desperate Escape (hazard rolls, may move through enemy models); afterwards the unit cannot shoot, declare a charge or start an action this turn (40k_11th_edition_core_rules.txt:1417-1440). 18.02: embarking after a fall-back move (:2981-2997).
- **AI today (none):** Fall-back destinations aim at an objective 'behind' the unit, or straight away from the engaging enemies (AIDecisionMaker.gd:12185-12273, 12429-12627). A transport is never considered as a destination, and EMBARK_UNIT is never emitted (MovementPhase.gd:8306-8311 skips the AI).
- **Engine support:** Reuse _compute_fall_back_destinations (AIDecisionMaker.gd:12185) with an extra candidate within 3″ of a friendly transport with capacity; TransportManager.can_embark / is_unit_within_embark_range (TransportManager.gd:107, 784); the survival estimates in _decide_engaged_unit (11958-12179, 12350). New: score 'fall back + embark' against holding and against a plain fall back.
- **Value (low):** Rare. The fall back alone escapes the fight; embarking adds protection for the next turn.
- **Evidence:**
  - https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-transports (search snippet: falling back and then embarking pulls a unit out of combat)
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1417-1440, 2981-2997
  - docs/rules/40k_11th_edition_core_rules.txt:2981-2996, :1417-1441
  - 40k/phases/MovementPhase.gd:9120-9144
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-moving-and-the-movement-phase/ (search snippet: embark after a Normal, Advance or Fall Back move)
- **Absorbed duplicates:** SUR-21 (Fall back straight into a transport)
- **Found by:** web, core-rules

#### TRN-25 — Arrive as a blocker or denial screen

Bring a cheap reserve unit in to plug a gap. Its 8″ no-arrival zone denies the opponent's own reserves (their ingress, Deep Strike and Rapid Ingress must all be more than 8″ from our units), and it can body-block an objective approach or block a movement lane. A unit that arrives in our Movement phase is already in place when the opponent's Rapid Ingress window opens at the end of that phase.

- **When:** The enemy still has units in reserves (or CP for Rapid Ingress) and our screen has a hole, for example after casualties; or an objective approach needs blocking for a turn.
- **Units:** Cheap reserve units (single models or small units, where OC does not matter).
- **Move type:** Reserves arrival
- **11e rules (verified):** 20.04: 'more than 8″ horizontally from all enemy units' also binds the opponent's arrivals (40k_11th_edition_core_rules.txt:3264-3266). 24.09 (:3649-3655). 15.07 Rapid Ingress timing (:2714-2731). Engine: GameConstants.gd:44-49.
- **AI today (none):** Denial screening (pass 3, AIDecisionMaker.gd:11527-11577, 14929-15026) only assigns units already on the table. Reserve arrivals are never placed for denial or blocking (7728-8247).
- **Engine support:** Reuse _deep_strike_denial_radius_px / _screen_spacing_px (AIDecisionMaker.gd:28452, 28484), _compute_screen_position (15028), and the denial-point generator (14929-15026) as arrival candidates. New: score denial spots for arriving units while enemy reserves remain.
- **Value (low):** Useful against reserve-heavy opponents, but screens already on the table usually do this job.
- **Evidence:**
  - /home/user/warhammer-40k-godot/40k/scripts/rules/GameConstants.gd:44-49
  - YouTube 1AwnDclFviQ @159:00 (WarGames Live): “this dog is doing some rapid ingress screening which is nice ... Deep strike denying” (a screen already on the table; using an arrival for it is a first-principles extension)
- **Found by:** first-principles

#### TRN-26 — Park loaded transports where an emergency disembark is survivable

If a loaded transport is destroyed, each passenger makes a hazard roll and must be set up within 6″ of it, as close as possible. Per the errata, a model is set up engaged only if no unengaged spot exists, and models that still cannot be placed are destroyed. The unit is battle-shocked and cannot charge. The transport's Deadly Demise (on a 6) then hits every unit within 6″, passengers included, and in the Fight phase overrun fights can catch them. So avoid ending a loaded transport's move against board edges, impassable or Solid terrain, or where enemies can surround it, and keep it out of reach of enemy melee and anti-tank fire where you can.

- **When:** Every move of a loaded transport that ends within enemy charge or anti-tank range.
- **Units:** TRANSPORTs carrying cargo.
- **Move type:** Normal (transport) / Remain Stationary
- **11e rules (corrected):** 18.03 / 18.05 (40k_11th_edition_core_rules.txt:2999-3007, 3061-3078), with the 18.05 errata (40k_11th_edition_errata_faq_commentary.md:609). 06.03 hazard rolls (:1067-1072). 24.08 Deadly Demise: resolved after the emergency disembark; hits each unit within 6″ (:3670-3699). The core-rules Fight phase example shows an overrun fight on a unit that has just emergency-disembarked (:1880-1916). Correction to core-rules#75: under the errata, models are set up engaged before any are destroyed.
- **AI today (none):** No term considers the cargo. Transports use the generic threat dodge (AIDecisionMaker.gd:28892-28990), and _estimate_unit_value counts only the transport's own models and keywords (28003-28024). Nothing checks for room to set up within 6″ in an emergency, or for the passengers' value.
- **Engine support:** Reuse _evaluate_position_threat (AIDecisionMaker.gd:28794), _estimate_incoming_melee_damage (12350), and RulesEngine._emergency_disembark_placements (RulesEngine.gd:17300) as a feasibility probe. New: add the embarked units' value to a loaded transport's threat weight, and penalise end points with little free space within 6″.
- **Value (low):** Rare but costly; mostly a tie-breaker when choosing a transport's end point.
- **Evidence:**
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_errata_faq_commentary.md:609
  - /home/user/warhammer-40k-godot/docs/rules/40k_11th_edition_core_rules.txt:1880-1916, 3061-3078, 3670-3699
  - /home/user/warhammer-40k-godot/40k/autoloads/RulesEngine.gd:17067 (resolve_transport_destruction), 17300-17470 (_emergency_disembark_placements: 6″ set-up; candidates within engagement range are rejected, so the errata's engaged fallback appears unimplemented, read from code)
- **Found by:** core-rules

#### TRN-27 — Stage within 6″ or 9″ of an edge, unengaged, to keep an end-of-turn extraction

Several rules put a unit back into strategic reserves at the end of the opponent's Fight phase, so it can drop again next turn, but only if it is unengaged, and some also need it near an edge or Hidden. Gated: Da Big Hunt INSTINCTIVE HUNTERS (Beast Snagga within 6″ of an edge), Saga of the Beastslayer CO-ORDINATED STRIKE (Blood Claws / Thunderwolf Cavalry / Wulfen within 9″ of an edge), Boss Snikrot's Kunnin' Infiltrator (hidden). Ungated, but still needing the unit unengaged: TACTICAL WITHDRAWAL (Phobos / Scouts), On Gilded Wings (Custodes Terminators), Deffkoptas' Aerial Manoover, Inceptors' Parabolic Jetleap, Venatari's Take Wing, Kayvaan Shrike's Echo of the Ravenspire. End this Movement phase's move, and later moves, where the gate will be met and the enemy cannot easily lock the unit in combat. Repositioned units are not destroyed at the end of round 3.

- **When:** A fast or expensive unit will be exposed after it acts, dropping in again next turn reaches a better target or objective, and CP for the stratagem is available.
- **Units:** Beast Snagga, Blood Claws / Thunderwolf Cavalry / Wulfen, Boss Snikrot, Deffkoptas, Inceptors, Venatari, Custodes Terminators, Kayvaan Shrike, Phobos / Scout squads.
- **Move type:** Normal / Advance (positioning); adjacent: return to reserves at the end of the opponent's Fight phase
- **11e rules (corrected):** Stratagem and ability texts: orks/RULES.md:112 (INSTINCTIVE HUNTERS: 'unengaged Beast Snagga unit within 6″ of a battlefield edge'); space-marines/SPACE_WOLVES.md:44 (CO-ORDINATED STRIKE: 'within 9″ of one or more battlefield edges'); space-marines/RULES.md:624 (TACTICAL WITHDRAWAL); custodes/RULES.md:113 (On Gilded Wings). 20.02 repositioned units (40k_11th_edition_core_rules.txt:3219-3240). 20.04 round-3 exemption (:3276-3283). Engine: ScoringPhase.gd:966-971.
  - _Skeptic:_ These are not end-of-turn extractions. All four trigger at the END OF THE OPPONENT'S FIGHT PHASE: INSTINCTIVE HUNTERS (orks/RULES.md:112), CO-ORDINATED STRIKE (SPACE_WOLVES.md:44), TACTICAL WITHDRAWAL (SM RULES.md:624), On Gilded Wings (custodes/RULES.md:113). Only INSTINCTIVE HUNTERS (6″) and CO-ORDINATED STRIKE (9″) need a battlefield edge; TACTICAL WITHDRAWAL and On Gilded Wings need only an unengaged unit. The 20.02/20.04 claims (repositioned units are exempt from the round-3 wipe) are correct. — orks/RULES.md:112; space-marines/SPACE_WOLVES.md:44; space-marines/RULES.md:624; custodes/RULES.md:113; 40k_11th_edition_core_rules.txt:3219-3245, 3276-3283
- **AI today (none):** The AI only decides whether to use an extraction when it is offered, and treats it as recycling an idle unit. TACTICAL WITHDRAWAL and CO-ORDINATED STRIKE score 2.1 only with no enemy within 12″ and off objectives (SMCodexAMovement.gd:298-305; SWCodexMovement.gd:175-182). kunnin_infiltrator, aerial_manoover, take_wing and parabolic_jetleap score 0.0 (OrkAbilities11e.gd:2329-2330; CustodesAbilities.gd:1329-1330; SMAbilitiesA.gd:2284-2285). No movement term stages a unit near an edge or keeps it unengaged for this purpose.
- **Engine support:** Reuse the inline edge-distance code (AIDecisionMaker.gd:8362, 10446), or add the missing shared helper; _is_position_near_enemy (15329) for the risk of being engaged. New: an edge-proximity bonus on the destinations of units whose extraction rule requires it.
- **Value (low):** Faction-specific and infrequent.
- **Evidence:**
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/orks/RULES.md:112
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/space-marines/SPACE_WOLVES.md:44
  - /home/user/warhammer-40k-godot/.llm/codex_11e_wahapedia/custodes/RULES.md:113
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_marines/SMCodexAMovement.gd:298-305
  - /home/user/warhammer-40k-godot/40k/scripts/codex/space_wolves/SWCodexMovement.gd:175-182
  - https://www.tabletopbattles.com/detachment-focus-lions-of-the-emperor (search summary: On Gilded Wings is reusable)
- **Found by:** factions

### Adjacent (outside the unit's own Movement phase)

#### ADJ-05 — Make a reactive move into cover or out of sight before their shooting (move into cover)

Reactive moves trigger when an enemy ends a move within 8″ (RESPONSIVE TACTICS, SWIFT AS THE EAGLE, SCARPER! ...) or when an enemy unit shoots your unit (BATTLE INSTINCTS). Use the normal move to do one of these:
- Put an obscuring terrain area between your unit and the enemy shooters that haven't fired yet.
- Step inside a terrain area for cover.
- Become Hidden: INFANTRY/BEASTS/SWARM inside a terrain area with light or dense terrain can be seen only within 15″ detection range.
Hidden also needs no ranged attacks this turn or last turn. A unit that shot in your turn gets only the line-of-sight and cover benefit. The move must end unengaged, it is the unit's one normal move this phase, and it cancels any action the unit is performing.

- **When:** A reactive trigger fired for an unengaged unit and enemy shooting that hasn't fired yet can see it. A spot within the move cap breaks line of sight, or gives cover or Hidden, without giving up an objective needed at the end of their turn or an action in progress.
- **Units:** - AA Infantry/Mounted: Gladius RESPONSIVE TACTICS, Tactical Brethren MASTERFUL TACTICS, Saga of the Great Wolf BATTLE INSTINCTS.
- Phobos units: TRANSHUMAN REACTIONS.
- Trusted Sentinels: SWIFT AS THE EAGLE.
- Gretchin: SCARPER!
- Deffkoptas: WHIRLIGIG EVASION.
- Nazdreg: Supreme Kunnin'.
- Lieutenant with Combi-weapon: Evade and Survive.
- Cato Sicarius: Knight Champion of Macragge.
- Fenrisian Wolves: Predatory Instinct.
- Warboss with Morgog's Finkin' Cap.
- **Move type:** Normal move (09.05) granted reactively. Adjacent: opponent's Movement or Shooting phase.
- **11e rules (corrected):** - 09.05 normal move: the unit is unengaged before and after (40k_11th_edition_core_rules.txt:1390-1399). One normal move per unit per phase (40k_11th_edition_errata_faq_commentary.md:470).
- 01.03: the mover's controller is the active player during the move (:137-158).
- 13.08 cover (:2278-2290); 13.09 Hidden (:2292-2302), light/dense after the errata (errata_faq:529); 13.10 obscuring (:2305-2311).
- 16.01: a move cancels an action in progress (:2824-2828).
- 15.01: one stratagem per unit per phase (:2500-2501).
- Rule texts: RESPONSIVE TACTICS (space-marines/RULES.md:259), SWIFT AS THE EAGLE (custodes/RULES.md:156), SCARPER! (orks/RULES.md:223), BATTLE INSTINCTS (space-marines/SPACE_WOLVES.md:54), Supreme Kunnin' (orks/wahapedia/Datasheets_abilities.csv:296).
- Corrections: youtube#55, factions#49 and first-principles#104 say Hidden needs dense terrain; the 13.09 errata makes it light or dense. GRAB IT, listed by core-rules#108 as a reactive move, is an own-Shooting-phase move (ADJ-33).
  - _Errata check:_ Hidden detection range is 15″, but a hidden model also goes to ground (3″ less, so 12″) while it is not fully visible to the attacking model due to intervening dense terrain features and its unit hasn't shot this turn or last. Prefer spots with dense features between you and the shooters. — Commentary 13.11.01 Gone to Ground (errata_faq:539)
- **AI today (none):** Each codex ai_score decides use or decline (decide_window_stratagem, AIDecisionMaker.gd:26859), and none of them looks at line of sight:
- RESPONSIVE TACTICS / TRANSHUMAN REACTIONS pay only when an objective is reachable (SMCodexAMovement.gd:271-278).
- SCARPER! / WHIRLIGIG EVASION pay only against a live charge threat, and never from an objective (OrkCodexMovement.gd:300-309).
- BATTLE INSTINCTS pays only when an objective is within 4″ (SWCodexMovement.gd:164-167).
- SWIFT AS THE EAGLE scores 0.0 (CustodesCodexMovement.gd:255-256), and the post-shooting window version is always declined (AIDecisionMaker.gd:16397-16416).
- Supreme Kunnin' scores a flat 1.5 (OrkAbilities11e.gd:2327-2328).
- Evade and Survive, Predatory Instinct and Knight Champion score 0.0 (SMAbilitiesA.gd:2284-2285, SWAbilities11e.gd:1839-1840, SMAbilitiesC.gd:1930-1931).
Placement is the engine's auto-solver. It translates the unit straight away from the trigger, or toward the nearest objective the player doesn't control (MovementPhase.gd:6439-6525). The 'normal' solver in ReactiveMove11e only targets objectives (ReactiveMove11e.gd:315-358).
- **Engine support:** Reuse these as probes at candidate spots, following the _position_would_be_hidden pattern (:28515):
- TerrainManager.model_visible_11e / unit_fully_visible_11e / is_obscured_between / is_model_hidden (TerrainManager.gd:1209, 1224, 976, 1001).
- LineOfSightManager.calculate_los_to_position (LineOfSightManager.gd:101) for 'who can see me here'.
- _estimate_unit_ranged_strength (:25866) to weight shooters.
New:
- A destination generator for reactive moves: sample points within the cap, then validate them with ReactiveMove11e.validate or _ork11e_translation_legal.
- A shared reactive-move scorer that every codex ai_score calls.
- **Value (high):** Every army in the project has reactive moves, and dodging the enemy's shooting after seeing their move is high-leverage. This is the user's 'move into cover' example. Today the AI ignores line of sight entirely.
- **Evidence:**
  - YouTube 6 Plus Plus Gaming uKl8cEJlk0c @27:00 — “with how Overwatch is now, that's really really powerful to have a reactive move” [F004]
  - YouTube HivemindHobbies Wm2Hd8h74_o @65:00 — “if he moves up at all, then they will automatically reactive move behind this obscuring wall” [F014]
  - YouTube TacticalTortoise 40k VqwMdS9MuIY @60:00 — “it has the ability to reactive move to enemies going close to it ... it may be able to jump away” [F014]
  - YouTube PNW 40K ycW5l0xHp9s @08:00 — “He can make a reactive move ... reactive moves in general are very powerful” [F014]
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-reconnaissance/ (search summary: reactive moves used to run away from charges, throw themselves in front of a more valuable unit, move-block choke points)
  - https://www.tabletopbattles.com/what-we-know-about-11th-edition-40k-so-far-recapping-the-new-rules-reveals-through-may-29th (reactive moves count as a move type); https://www.belloflostsouls.net/2025/11/warhammer-40k-3-movement-issues-gw-needs-to-fix-in-11th-edition.html
  - _…and 2 more_
- **Found by:** youtube, factions, web, first-principles, core-rules

#### ADJ-07 — Infiltrate or Scout a forward screen against enemy infiltrators, scouts and deep strikers

Every model on the table makes an 8″ zone where enemy units can't be set up or end certain moves:
- Enemy Infiltrators must set up more than 8″ from all enemy units.
- Enemy scout moves must end more than 8″ away.
- Ingress and deep strike must be more than 8″ away.
Put a cheap Infiltrators or Scouts unit forward, spread with 2″/9″ coherency, to push enemy infiltrators and scouts back from your lines and to deny landing spots near your objectives and backfield. The screen keeps working through the opponent's Rapid Ingress window as long as it survives.

- **When:** When all of these apply:
- The opponent fields Infiltrators, Scouts or deep strikers (for example Emperor's Children).
- You have a cheap forward-capable unit.
- Your near objectives or a flank would otherwise be open.
Pre-battle rules alternate starting with the first-turn player, so a screen placed first also shapes their scout moves.
- **Units:** Cheap Infiltrators or Scouts units: Gretchin with Minefield Detail, Scout Squads, Incursors, Kommandos.
- **Move type:** Infiltrators set-up (24.20) / Scout move (24.32). Adjacent: pre-battle.
- **11e rules (verified):** - 24.20 (40k_11th_edition_core_rules.txt:3754-3762) and 24.32 (:3884-3901): more than 8″ from enemy units.
- 20.04: ingress more than 8″ away (:3255-3273). 24.09: deep strike more than 8″ away (:3649-3662).
- 03.03: coherency 2″ and 9″ (:514-537).
- FAQ: pre-battle rules alternate starting with the first-turn player (40k_11th_edition_errata_faq_commentary.md:696-697).
- Engine: GameConstants.reinforcement_min_enemy_distance_inches / infiltrators_min_enemy_distance_inches (GameConstants.gd:49-61); ScoutPhase._scout_min_enemy_distance_inches (ScoutPhase.gd:182-184).
- **AI today (none):** Scout destinations are objectives only (AIDecisionMaker.gd:5969-6061), and Infiltrators are never deployed forward (no unit_has_infiltrators call; _decide_deployment :5055). Movement-phase deep-strike denial screens do exist (pass 3, :11527-11577, :14929-15026), but nothing places a screen before the battle.
- **Engine support:** Reuse _deep_strike_denial_radius_px (:28452), _screen_spacing_px (:28484), _get_enemy_reserves (:14884), _compute_screen_position (:15028) and _screen_widest_passable_gap_inches (:28388).
New:
- A pre-battle denial-point generator (home objectives and backfield) shared by the deployment and scout decisions.
- A check for enemy units with Infiltrators or Scouts.
- **Value (high):** Screens against Rapid Ingress and infiltrators are standard (F029, F021) and cost only a cheap unit. Infiltrators are wholly unused today.
- **Evidence:**
  - YouTube 6 Plus Plus Gaming gRqdSBkqVlA @06:00 — “a big Helion Brick for rapid ingress threats ... I needed a infiltrate screen unit against things like Emperor's Children” [F029]
  - YouTube WarGames Live 1AwnDclFviQ @159:00 — “this dog is doing some rapid ingress screening which is nice ... Deep strike denying” [F029]
  - YouTube Tabletop Nexus QZ9wggn2oUo @07:00 — “Gretchen handle the boring jobs, your home objectives, more screening so boys don't have to” [F021]
  - .llm/codex_11e_wahapedia/orks/RULES.md:220 (Minefield Detail)
  - 40k/scripts/rules/GameConstants.gd:49-61
- **Found by:** youtube, first-principles, web, factions, core-rules

#### ADJ-01 — Counter-drop with Rapid Ingress into the gap the opponent's move left

At the end of the opponent's Movement phase (battle round 2+), spend 1CP to make an ingress move with a strategic-reserves unit after seeing every enemy move. Land on or next to an objective they vacated or left lightly held, behind their advance, within next-turn shooting or charge reach of a priority target, or in a hole in your own denial screen. The unit is set up more than 8″ from every enemy unit: wholly within 6″ of an edge and outside their deployment zone before round 3, or anywhere with Deep Strike. Their Shooting and Charge phases come next, so prefer spots out of sight or Hidden and outside likely charge reach. The ingress no-move restriction ends at the start of their Charge phase, so the unit moves, shoots and charges normally in your turn. A unit landing 8-12″ from an enemy can even Heroic Intervene at the end of that Charge phase. Faction rules change the price and anchor point:
- Swift Ruin and Leonine Ferocity: -1CP and outside the once-per-phase limit, so two units can drop.
- Grimnar's Mark: -1CP.
- Teleport Homer: -1CP, set up within 3″ of its token.
This needs a unit still in reserve. As the second player in round 2, this window comes before your own first arrival.

- **When:** All of these apply:
- Round 2 or later.
- A non-AIRCRAFT, non-battle-shocked unit is still in strategic reserves.
- You have 1CP to spare.
- After the opponent's moves there is an empty or weakly held objective, an exposed enemy unit, or a hole in your screen.
- A legal landing spot covers that opportunity without being exposed to heavy shooting or likely charges in their remaining phases.
- **Units:** Strategic-reserves units, best with Deep Strike: Terminators, jump-pack and bike units, Inceptors, Venatari, Deffkoptas, Stormboyz. Never AIRCRAFT.
- **Move type:** Ingress move (20.04) via the Rapid Ingress stratagem. Adjacent: end of the opponent's Movement phase.
- **11e rules (verified):** - 15.07 Rapid Ingress: WHEN end of your opponent's Movement phase; TARGET one strategic-reserves unit (excluding AIRCRAFT); not in the first battle round (40k_11th_edition_core_rules.txt:2714-2729).
- 20.04 ingress: wholly within 6″ of an edge; more than 8″ from all enemy units; no models in the opponent's DZ before round 3; no other move until the start of the next Charge phase (:3255-3273).
- 24.09 Deep Strike: anywhere more than 8″ away, even in the opponent's DZ (:3649-3662).
- 15.01: the same stratagem once per phase, and one stratagem per unit per phase (:2498-2501).
- 01.07: battle-shocked units can't be targeted by stratagems (:216-217).
- 13.09 Hidden: light/dense terrain after the errata (:2292-2302; 40k_11th_edition_errata_faq_commentary.md:529).
- Engine: StratagemManager.gd:5068-5076 (end_of_phase, not_battle_round 1). Placement is validated at the 11e 8″ (MovementPhase.gd:2340-2452, via GameConstants.reinforcement_min_enemy_distance_inches, GameConstants.gd:49-50).
- The delta audit's notes 'start of any opponent phase' and 'Rapid Ingress still 9″' (11th_edition_delta_audit.md:141, :159) are stale: 15.07's WHEN and the current validator contradict them.
- **AI today (partial):** What exists: evaluate_rapid_ingress (AIDecisionMaker.gd:28121-28334, called from AIPlayer.gd:1306).
- It declines below 1CP, or with the last CP before round 4 (:28139-28147).
- It scores each reserve with the own-turn arrival scorer _score_reserves_deployment (:7949-8017: points, deep strike, melee/ranged, one best objective), then adds +3 in R4+, +1 in R3 and -1 for the CP (:28164-28172). It uses Rapid Ingress at a score of 3.0 or more.
- Placement reuses _compute_reinforcement_positions (:8019+). Its candidate filter is 9″ + base + 0.6″ (:8027-8029), and it ranks objective proximity plus an enemy 10-15″ away.
What is missing:
- Nothing diffs the board before and after the opponent's move (vacated objectives, exposed units, screen holes).
- Nothing weighs exposure to the opponent's Shooting and Charge phases.
- Double drops and faction discounts are unknown to the AI: Swift Ruin, Leonine Ferocity and Grimnar's Mark have 0 grep hits, and Teleport Homer scores 0.0 at SMAbilitiesB.gd:1827-1828.
- Own-turn arrival always lands reserves at the first chance (_decide_reserves_arrival :7728), so a unit is rarely still held for this window.
- **Engine support:** Reuse:
- _score_reserves_deployment (:7949) and _compute_reinforcement_positions / _generate_strategic_reserves_candidates (:8019, :8073).
- _evaluate_all_objectives (:8926).
- _calculate_enemy_threat_data and _evaluate_position_threat (:28695, :28794).
- _position_would_be_hidden (:28515) and _charge_success_probability (:18928).
New:
- Snapshot the board at the start of the opponent's Movement phase, to diff objective states and exposed units against it.
- A next-turn reach term: targets shootable or chargeable from the landing spot.
- Drop the 9″ filter to GameConstants.reinforcement_min_enemy_distance_inches.
- A keep-in-reserve option in _decide_reserves_arrival.
- **Value (high):** The corpus treats keeping a Rapid Ingress answer in reserve as standard 11e play (F013, F029). It is the only arrival made after seeing the opponent's whole move, and it costs 1CP. The AI's version is a generic arrival score that ignores what the opponent's move just changed.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:2714-2729, 3255-3273, 3649-3662
  - 40k/autoloads/StratagemManager.gd:5068-5076; 40k/phases/MovementPhase.gd:2225 (_get_rapid_ingress_eligible_units), :2340-2452 (placement validator)
  - YouTube 40K Dirtbags Enm67qaqHkU @04:00 — “at least one unit in reserves cuz you're making lists to have a reserve rapid ingress target” [F013/F029]
  - YouTube 6 Plus Plus Gaming gRqdSBkqVlA @06:00 — “a big Helion Brick for rapid ingress threats ... I needed a infiltrate screen unit against things like Emperor's Children” [F029]
  - https://odyssey40k.com/rapid-ingress-is-the-best-stratagem-in-11th-edition/ (search snippet: on the table before their shooting, in a position they could not screen against)
  - https://grimslate.com/blog/core-stratagems-guide-11th-edition ; https://grimslate.com/blog/reserves-and-deep-strike-11th-edition ; https://rapidingress.com/what-is-rapid-ingress
  - _…and 5 more_
- **Absorbed duplicates:** OBJ-36 (Rapid Ingress onto an open objective (adjacent: end of the opponent's Movement phase))
- **Found by:** core-rules, youtube, web, first-principles, factions, missions, bucket-editor

#### ADJ-02 — Infiltrate or Scout forward onto objectives that score in round 1

Use either pre-battle option to start in range of a non-home objective:
- The Scout move: up to X″, starting wholly within your deployment zone and ending more than 8″ from all enemy units. A DEDICATED TRANSPORT whose passengers all have Scouts can make it instead.
- Infiltrators set-up: anywhere more than 8″ from the opponent's deployment zone and all enemy units.
The objective is then yours at the first end-of-phase, end-of-turn or Command-phase check, and the early cards pay. Per missions#67 these include:
- Central holds (Immovable Object, Search and Scour).
- Non-home holds (Outmanoeuvre).
- Majorities (Battlefield Dominance, Inescapable Dominion).
- Round-1 actions (Secure Asset, Sabotage, Death Trap, Smoke and Mirrors, Vanguard Operation).
- Tactical cards: Display of Might, Centre Ground, Outflank, Plunder, Cleanse, Engage on All Fronts.
Pre-battle rules alternate starting with the first-turn player, so the turn order is already known. When going second, choose spots the opponent can't wipe out on turn 1.

- **When:** During deployment or the Resolve Pre-battle Abilities step, when all of these apply:
- The unit has Scouts X″ or Infiltrators, or a grant: Kill Kommanda, Minefield Detail, Spearpoint War Leader, Relentless Advance, Caanok Var Cerebrex Logic Engine, Impulsor Orbital Comms Array.
- Your primary or secondary pays for early non-home control or a round-1 action.
- A legal spot in range of the objective exists.
- **Units:** Kommandos, Boss Snikrot, Infiltrator / Incursor / Scout / Eliminator Squads, Phobos characters, Reivers, Vanguard Veterans, Invictor, Scout Bike Squad, Wolf Scouts, Knight-Centura and grant recipients; dedicated transports carrying Scouts.
- **Move type:** Scout move (24.32) / Infiltrators set-up (24.20). Adjacent: pre-battle.
- **11e rules (verified):** - 24.20 Infiltrators: more than 8″ from the opponent's DZ and all enemy units (40k_11th_edition_core_rules.txt:3754-3762).
- 24.31 Scouts options, including the DEDICATED TRANSPORT scout move (:3859-3880).
- 24.32 scout move: max X″, wholly within your DZ, ends more than 8″ from all enemy units (:3884-3901).
- Appendix FAQ: no embarking after a scout move (:4121-4126).
- FAQ: pre-battle rules alternate starting with the first-turn player (40k_11th_edition_errata_faq_commentary.md:696-697).
- 14.02: control is checked at the end of each phase and turn (:2401-2423).
- Engine: ScoutPhase.gd:182-184 (8″ at 11e) and :195-212 (wholly in DZ); DeploymentPhase.gd:144-152 and :327-379 (Infiltrators >8″).
- The card list comes from missions#67 (missionCards.json). It was spot-checked, not re-verified card by card.
- **AI today (partial):** Scouts: _decide_scout (AIDecisionMaker.gd:5831-5918) moves every Scouts unit toward the objective picked by _find_best_scout_objective (:5969-6061).
- Scoring: uncontrolled 10, enemy-held 7, contested 5, already held -5; no-man's-land +3, home -4, enemy home -2; -0.3 per inch.
- Distance check: hard-coded >9″ (SCOUT_ENEMY_DIST_INCHES = 9.0 at :6125) instead of the 11e >8″.
- It ignores the mission cards and the known turn order.
Infiltrators: no coverage. The AI never calls GameState.unit_has_infiltrators (0 grep hits), so _decide_deployment (:5055) sets them up in its own zone. Only a hand-authored plan placement (docs/PLAN_FORMAT.md:110-111) could put one forward.
- **Engine support:** Reuse:
- _find_best_scout_objective, _estimate_objective_vp_value (:22928) and _compute_scout_movement (:6063).
- DeploymentPhase._validate_infiltrators_position (:327) as the legality check.
- GameConstants.infiltrators_min_enemy_distance_inches (GameConstants.gd:60-61).
- MissionManager.model_in_objective_range (MissionManager.gd:529).
New:
- An Infiltrators placement generator inside _decide_deployment: candidate points more than 8″ from the enemy DZ and deployed enemy units, scored by objective VP.
- A 'first turn known' input to both decisions.
- **Value (high):** Round-1 control pays VP immediately and denies the opponent's early scoring. The AI never uses Infiltrators at all, and every scout move wastes an inch to the 9″ check.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:3754-3762, 3859-3901, 4121-4126
  - 40k/phases/ScoutPhase.gd:182-184; 40k/phases/DeploymentPhase.gd:327-379
  - YouTube Factions&Fate OKoDYKdWm1E @04:00 — “infiltrated up here just a little bit past my deployment line, but still within range to hand out battle shocks” [F023]
  - Web search snippet (1d6chan 11th Edition Tactics): 'if you have units with scout or infiltrators, and particularly if you go first, you can rack up a solid amount of VP early on'
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-disruption/ (search snippet: 'infiltrating and fast-moving units will be a great place to start')
  - https://www.newrecruit.eu/wiki/wh40k-11e/warhammer-40,000-11th-edition/rules/infiltrators (8″); https://www.wargamer.com/warhammer-40k/abilities (says 9″, conflicts with the local 8″, local text wins); https://wahapedia.ru/wh40k11ed/factions/space-marines/Scout-Squad
  - _…and 5 more_
- **Absorbed duplicates:** OBJ-37 (Scout or Infiltrate onto, or within one move of, an objective (adjacent: pre-battle)); MIS-34 (Deploy, infiltrate and scout toward the geometry your early cards pay for)
- **Found by:** missions, youtube, web, first-principles, factions, core-rules, bucket-editor

#### ADJ-03 — Wrap engaged enemies so their only way out is Desperate Escape

When charging, piling in and consolidating, place models all around the enemy unit, far side included, so no Ordered Retreat path exists. Bases can't move through enemy models, and a fall-back must end unengaged (more than 2″ from all your models). The enemy then has two choices:
- Stay locked. It loses normal shooting: MONSTER/VEHICLE units keep close-quarters shooting at -1, and other units can only use [CLOSE-QUARTERS] weapons against units engaged with them. It also can't start actions or walk onto objectives.
- Desperate Escape. It makes a hazard roll per model (a 1-2 inflicts 1 mortal wound, or 3 if every model is MONSTER/VEHICLE) plus a battle-shock roll, and still can't shoot, charge or start actions afterwards.
MONSTER/VEHICLE models pass through enemy models only on normal and advance moves, so wrapped vehicles pay the full Desperate Escape price. FLY units (taking to the skies on the fall-back) and Super-Heavy Walkers get out, so don't spend models wrapping them.

- **When:** Your multi-model melee unit is engaged, or about to be, with a valuable non-FLY unit you want stuck or hurt by hazard rolls: an infantry shooter, an objective holder or a vehicle. You need enough models and pile-in or consolidation reach to close its perimeter.
- **Units:** Multi-model melee units (Boyz, Beast Snagga Boyz, Gretchin, Assault Intercessors, Blood Claws, Wulfen). Best targets are non-FLY vehicles and gunlines.
- **Move type:** Charge move (11.04), pile-in (12.03), consolidation (12.08). Adjacent: Charge and Fight phases.
- **11e rules (verified):** - 03.01: a base can't be moved through enemy models (40k_11th_edition_core_rules.txt:388).
- 09.07: Ordered Retreat vs Desperate Escape. Only Desperate Escape moves through enemy models; the move ends unengaged; no shooting, charging or actions afterwards; Desperate Escape adds a battle-shock roll (:1417-1442).
- 06.03 hazard rolls (:1067-1074). 03.04 engagement range 2″ (:539-541).
- 10.04 normal shooting needs an unengaged unit (:1489-1491); 10.06 close-quarters shooting (:1522-1547).
- 17.01: MONSTER/VEHICLE models pass through models only on normal and advance moves (:2869-2874). FAQ: other move types pass through friendly models only (40k_11th_edition_errata_faq_commentary.md:598).
- 21.03: take to the skies on a fall-back (:3358-3373). 24.35 Super-Heavy Walker (:3940-3960).
- Constraints on the wrapping moves: 11.04 (:1640-1665), 12.03 (:1737-1766), 12.08 Engaging mode (:1947-1975).
- **AI today (partial):** Only engaging-mode consolidation tries far-side wrap angles around the target. This is priority 2 in _compute_consolidate_movements_engagement (AIDecisionMaker.gd:21968-21975, :22178-22240). It takes the first legal slot and never checks whether the enemy's retreat is actually closed. Charge placement only covers the declared targets (_compute_charge_move :19797-20324), and pile-in moves each model straight at the closest enemy model (_compute_pile_in_movements :21352). So no wrap is planned on the charge or the pile-in.
- **Engine support:** Reuse:
- The consolidation wrap-angle code (:22178-22240) and _pile_in_position_collides (:21208).
- The coverage pass in _compute_charge_move.
- The fall-back move templates (scripts/rules/movetypes/) to test whether an Ordered Retreat still exists.
New: an 'escape path exists?' query. Take the enemy models' M-inch reachable region, minus our bases, ending more than 2″ from our models, and use it to score charge, pile-in and consolidation layouts.
- **Value (high):** A wrap forces a hazard-plus-battle-shock Desperate Escape, or keeps the unit off objectives and actions. 11e removed vehicle pass-through on fall-backs, so this pays off more than it did in 10e. The lock does less against MONSTER/VEHICLE shooting, because close-quarters shooting still works at -1.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:385-395, 1417-1442, 1067-1074, 1522-1547, 2869-2874
  - 40k/scripts/AIDecisionMaker.gd:21968-21975, 22178-22240 (consolidation wrap angles)
  - https://www.tabletopbattles.com/40k-11th-edition-faction-pack-review-black-templars (Unsparing Execution forces Desperate Escape, which shows the value of forcing it)
  - YouTube Maelstrom Gaming Studios - Tyranids aQsog-fkQJ8 @98:00 — “no, we'll fall back and we'll take our hazardous roles. Ones and twos, they die” [F017]
  - A web search for 11e wrapping returned nothing specific (2026-11-06): this entry is derived from the rules
- **Found by:** core-rules, web, first-principles

#### ADJ-04 — Consolidate into a fresh enemy unit to lock it (Engaging Consolidation)

A unit that fought may end unengaged but within 3″ of other enemy units. If it moves, it must use Engaging Consolidation: up to 3″, each moved model ends closer to the closest selected unit, and the unit must end engaged with every selected unit. Selected units that have not fought must then fight it at once.
Pick targets your unit survives and that lose the most from being locked into their next turn:
- Non-MONSTER/VEHICLE shooters. They can then only use [CLOSE-QUARTERS] weapons against units engaged with them, and a fall-back means no shooting.
- Action or objective units. Engaged units can't start actions, and neither can a unit that falls back.
Locked MONSTER/VEHICLE units still shoot (close-quarters, at -1) and can still be shot by your army, so they are weaker lock targets. TACTICAL FOCUS (consolidate D3+3″) extends the reach; target-selection distances don't change.

- **When:** At the end of any Fight phase (both players consolidate), when all of these apply:
- An enemy infantry shooter, actor or objective holder is within 3″ of your unengaged unit.
- Your unit survives its attacks.
- The lock lasts into the enemy's next turn.
- **Units:** Durable melee units that fought this phase.
- **Move type:** Consolidation move, Engaging mode (12.08). Adjacent: Fight phase.
- **11e rules (corrected):** - 12.07: both players consolidate, active player first, optional per unit (40k_11th_edition_core_rules.txt:1934-1941).
- 12.08 Engaging mode and the forced fights (:1947-1989). The errata extends the forced fight to Ongoing consolidations (40k_11th_edition_errata_faq_commentary.md:492). Distance FAQs (:493-498).
- 16.01: engaged units, and units that fell back, can't start actions (:2807-2815).
- 09.07: no shooting or charging after a fall-back (:1437-1439).
- 10.06 close-quarters shooting (:1522-1547); 17.03 shooting at engaged MONSTER/VEHICLE units (:2898-2908).
- TACTICAL FOCUS: .llm/codex_11e_wahapedia/space-marines/RULES.md:635.
  - _Errata check:_ Locked MONSTER/VEHICLE units can still be shot by your other, unengaged units at -1 to hit, but not with [BLAST] weapons. Your engaged locking unit itself can only shoot them with close-quarters shooting. — 17.03 errata (errata_faq:608); Commentary 17.03.01 Shooting While Engaged With Monsters/Vehicles (errata_faq:615)
- **AI today (partial):** _determine_ai_consolidate_mode returns ENGAGEMENT whenever any enemy model is within 3″ (AIDecisionMaker.gd:21861-21966). _compute_consolidate_movements_engagement then always tags not-yet-engaged enemy units first, then wraps, then closes on the nearest (:21968-22240). It never weighs the tagged unit's attacks against the lock value, and never prefers shooters or actors. TACTICAL FOCUS is paid when an objective is 3-4″ away or an enemy 3-4.5″ away (SMCodexAMovement.gd:306-311).
- **Engine support:** Reuse:
- _estimate_incoming_melee_damage (:12350), _estimate_melee_damage (:19576) and _estimate_unit_ranged_strength (:25866).
- The lock_targets threshold of the multi-phase plan (:3773-3946).
- MissionManager.can_start_mission_action_11e / get_pending_card_action_11e (MissionManager.gd:2030, 2266) to identify actors.
New: a consolidation-option scorer that compares each selectable enemy subset against declining (ADJ-08), feeding _compute_consolidate_action.
- **Value (high):** Tying up a shooter or actor into the enemy's next turn is a core melee tactic (F015, F016). The AI already tags units blindly, so the gap is choosing which unit to tag, and when not to.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1934-1989, 2807-2828
  - YouTube Auspex Tactics YM1sRZGVOhw @12:00 — “If you're able to hit something, destroy something, consolidate into something else” [F016]
  - YouTube WarGames Live HER6VzUGO60 @658:00 — “We'll charge the truck in just to lock you in because we can still touch you and still be on the objective” [F015]
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-the-charge-and-fight-phases/ ; https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-faq-compendium
  - 40k/scripts/AIDecisionMaker.gd:21968-22240
- **Found by:** youtube, missions, core-rules, web, first-principles, factions

#### ADJ-06 — Consolidate onto an objective (Objective Consolidation) in either player's Fight phase

This applies to a unit that fought, is unengaged, has no enemy within 3″ and is within 3″ of an objective. If it moves, it must use Objective Consolidation: up to 3″, each moved model ends in range of the selected objective if possible (closer if not), and the unit must end in range. It adds OC just before the end-of-phase and end-of-turn checks:
- In your Fight phase: for end-of-turn holds and Command-phase scoring. Pile-in and consolidation moves don't cancel an action in progress.
- In the opponent's Fight phase: to stand on an objective at the end of THEIR turn. This feeds Burden of Trust, Defend Stronghold and Display of Might's opponent-turn tier, contests their scoring or action completion, or claims the objective for your next Command phase.
With several objectives within 3″, pick by value, not distance. Set it up earlier by finishing charges and pile-ins within 3″ of the target objective and more than 3″ from other enemies (ADJ-19). TACTICAL FOCUS (D3+3″) extends the reach.

- **When:** At the end of every Fight phase, for each unit that fought, when an objective is within 3″ and no enemy is within 3″. It matters most just before an end-of-turn scoring check.
- **Units:** Any unit that was eligible to fight this phase.
- **Move type:** Consolidation move, Objective mode (12.08). Adjacent: Fight phase, yours or the opponent's.
- **11e rules (verified):** - 12.07: both players consolidate, active player first, optional per unit (40k_11th_edition_core_rules.txt:1934-1941).
- 12.08: modes in order Ongoing, Engaging, Objective. Objective mode applies within 3″ of objectives, and the unit must end within range of the selected one (:1942-1989).
- 14.02: control is checked at the end of each phase and turn; being within range of a terrain objective means being within its area (:2401-2423).
- 16.01: pile-in and consolidation moves don't cancel actions (:2824-2828).
- Card timing: missionCards.json burden-of-trust (:2225), display-of-might (:2246) and defend-stronghold (:2706) score at the end of the opponent's turn.
- TACTICAL FOCUS: space-marines/RULES.md:635.
- **AI today (partial):** The mode follows the 12.08 range gates (_determine_ai_consolidate_mode, AIDecisionMaker.gd:21861-21966). In OBJECTIVE mode every model moves toward one objective (:21772-21800; _compute_consolidate_movements_objective :22320). That objective is the closest selectable one (_ai_consolidate_objective_target :21823-21860); forced_objective_id is only an override hook. So the AI picks neither the most valuable objective nor the one that matters at the coming end-of-turn check. Nothing positions charges or pile-ins to finish within 3″ of an objective. EMPEROR'S DOMAIN can force objective mode (:21761-21766).
- **Engine support:** Reuse:
- _ai_consolidate_objective_target and MissionManager.model_within_inches_of_objective (MissionManager.gd:545).
- _evaluate_all_objectives (:8926) and _estimate_objective_vp_value (:22928).
- The engine already accepts a player pick through context.chosen_objective (ConsolidationMove.gd:110-126).
New:
- Score each selectable objective by VP at the next check, including opponent-turn cards.
- Add a fight-phase precursor term to charge-target and pile-in planning.
- **Value (high):** It happens every Fight phase and adds OC right before scoring checks. In the opponent's Fight phase it is one of the few ways to change the board before their end-of-turn scoring.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1934-1990
  - YouTube Maelstrom Gaming Studios - Tyranids aQsog-fkQJ8 @71:00 — “I will tow this guy onto the objective ... get a tiny bit further away” [F016]
  - YouTube Boltgun Tactics 6V8asnfgFUE @161:00 — “We'll just consolidate into the middle” [F016]
  - research/youtube/ai_learnings.json F016 ('Consolidation should be scored as a positioning move — onto an objective, into a new enemy unit, or backwards out of line of sight')
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-the-charge-and-fight-phases/ (on a terrain objective you can move 3″ within it as long as you don't leave the terrain); https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-faq-compendium
  - 40k/data/40kdc/missionCards.json:2225, 2246, 2706
  - _…and 4 more_
- **Absorbed duplicates:** OBJ-35 (Consolidate onto an objective after fighting (adjacent: Fight phase))
- **Found by:** youtube, missions, core-rules, web, first-principles, factions, bucket-editor

#### ADJ-08 — Decline consolidation when the forced mode would hurt you

Consolidation is optional per unit, but once a unit moves its mode is forced:
- Within 3″ of an enemy, it must Engaging-consolidate. It ends engaged with every selected unit, and unfought units fight it now.
- Otherwise, within 3″ of an objective, it must move into that objective's range.
Stay put when the forced move would get the unit killed, release a dangerous enemy's attacks, pull it off an objective it already holds, or move it out of the cover or terrain area that keeps it Hidden.

- **When:** At the end of the Fight phase, when the forced mode would engage a unit that out-fights you, or drag you off an objective or out of cover, and staying still keeps OC or protection.
- **Units:** Any unit that fought.
- **Move type:** Consolidation (12.08), declined. Adjacent: Fight phase.
- **11e rules (corrected):** - 12.07: players consolidate 'with all of their eligible units they choose to move' (40k_11th_edition_core_rules.txt:1934-1941). The Fight-phase sidebar says 'you don't have to pile in or consolidate with a unit if you don't want to' (:1720-1727).
- 12.08: the mandatory mode order and the forced fights (:1947-1989). Errata: 40k_11th_edition_errata_faq_commentary.md:492.
- Selecting modes commentary (errata_faq:462).
  - _Errata check:_ An engaged unit that consolidates must use Ongoing Consolidation, and under the errata any enemy unit it is then engaged with that hasn't been selected to fight this phase must fight it now. So declining applies to engaged units too, and Engaging mode is only for unengaged units within 3″ of an enemy. — 12.08 errata, Ongoing Consolidation (errata_faq:492)
- **AI today (none):** The Fight AI takes every CONSOLIDATE offer (AIDecisionMaker.gd:20533-20539) and moves in whatever mode the range gates give (:21861-21966). It sends END_CONSOLIDATION only once nothing is left (:20541-20549). No branch ever declines. An empty-movements CONSOLIDATE is already used as a skip for AIRCRAFT (:21748-21756), so a decline is mechanically available.
- **Engine support:** Reuse _estimate_incoming_melee_damage (:12350), _estimate_melee_damage (:19576), _unit_has_model_in_control_range (:13269) and TerrainManager.is_model_hidden (TerrainManager.gd:1001).
New: a consolidate-vs-stay comparison in _compute_consolidate_action that emits the empty CONSOLIDATE when staying is better.
- **Value (medium):** It prevents self-inflicted losses (forced engagements, lost objectives), and it is cheap to add once consolidation options are scored.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1720-1727, 1934-1989
  - Web search snippet: 'skipping consolidation matters more in 11th edition, because an unengaged unit with enemies inside 3″ is forced into an Engaging Consolidation if it moves at all'
  - docs/rules/11th_edition_delta_audit.md §3 (12.07-12.08: one move per unit, optional per unit)
  - 40k/scripts/AIDecisionMaker.gd:20530-20549 (CONSOLIDATE taken whenever offered)
- **Found by:** youtube, core-rules

#### ADJ-13 — Rapid Ingress to score or deny at the end of the opponent's turn

Land where scoring at the end of the opponent's turn is decided, whether it is their card or one of your own opponent-turn cards:
- Wholly in no-man's-land, for Display of Might's 5VP opponent-turn tier.
- Within 6″ (or 3″) of the centre, more than 8″ from their units, to break their Centre Ground.
- Inside the terrain area in your territory where their Vanguard Operation actor stands, which voids 'no enemy units within that terrain area'.
- On your home objective and in your deployment zone, for Defend Stronghold or Burden of Trust.
- In range of an objective they are about to score.

- **When:** From round 2, when you hold a reserve unit and an end-of-turn award (theirs or one of your opponent-turn cards) hinges on a zone a legal ingress spot reaches: more than 8″ from their units, and within 6″ of an edge unless the unit has Deep Strike.
- **Units:** Strategic-reserves units, best with Deep Strike; never AIRCRAFT.
- **Move type:** Ingress move (20.04) via Rapid Ingress (15.07). Adjacent: end of the opponent's Movement phase.
- **11e rules (verified):** - 15.07 (40k_11th_edition_core_rules.txt:2714-2729). 20.04 constraints (:3255-3273). 24.09 Deep Strike (:3649-3662).
- 14.02: control at the end of each phase and turn (:2401-2423).
- Card timings in missionCards.json: display-of-might (:2246; 5VP at the end of the opponent's turn), centre-ground (:2311; enemy within 3″ or 6″ of the centre denies), vanguard-operation (:1597; completes if no enemy units are within the terrain area), defend-stronghold (:2706), burden-of-trust (:2225), beacon (:2826).
- **AI today (none):** evaluate_rapid_ingress (AIDecisionMaker.gd:28121-28334) inherits the generic objective VP term from _score_reserves_deployment (:7983-8016, via _estimate_objective_vp_value :22928). Nothing there is timing-aware: it never knows the score is checked at the end of THIS (the opponent's) turn, and it never scores zones (no-man's-land, centre, terrain areas) or denial of the opponent's cards. Placement ranks only objective proximity and enemy distance (_compute_reinforcement_positions :8019+).
- **Engine support:** Reuse _assess_display_of_might / _assess_defend_stronghold (AIDecisionMaker.gd:23149-23156), _get_deployment_zone_polygon_pixels (:24856) and MissionManager.get_card_action_summary_11e / get_pending_card_action_11e (MissionManager.gd:2197, 2266).
New:
- An evaluator for scoring and denial at the end of the opponent's turn, shared with ADJ-14 and ADJ-06.
- Rapid Ingress candidate spots that target zones.
- **Value (medium):** Several 11e cards pay or deny at the end of the opponent's turn: Display of Might's 5VP tier, Defend Stronghold, Burden of Trust, Centre Ground and Vanguard Operation. The value depends on which cards are in play.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:2714-2729
  - 40k/data/40kdc/missionCards.json:1597, 2225, 2246, 2311, 2706, 2826
  - YouTube 40K Dirtbags Enm67qaqHkU @04:00 — “at least one unit in reserves cuz you're making lists to have a reserve rapid ingress target” [F013]
  - https://odyssey40k.com/rapid-ingress-is-the-best-stratagem-in-11th-edition/ (search snippet)
  - Coverage inventory B49 limitation: “No intent to drop in to block, screen, contest an objective the opponent just moved onto, or deny an action” (AIDecisionMaker.gd:28121-28334)
  - YouTube nGqRAvAMTYA @66:00 (TacticalTortoise 40k): “He also can 6 in deep strike high OC onto an objective in order to grab it” [F007]
  - _…and 4 more_
- **Absorbed duplicates:** DEN-17 (Arrive by Rapid Ingress (or from reserves) to deny the opponent's end-of-turn scoring); MIS-33 (In the opponent's turn, break their action or end-of-turn scoring with reactive moves)
- **Found by:** missions, core-rules, bucket-editor, coverage, youtube

#### ADJ-14 — Heroic Intervene onto the objective or terrain area the enemy is scoring from

Use Heroic Intervention so your unit ends engaged with, and usually within range of, the objective or area the opponent needs at the end of THEIR turn. Per missions#64 this can:
- Contest their OC, so actions that complete 'if it controls the objective' fail: Secure Asset, Sabotage, Cleanse, Decoy, Triangulate, Extract Intelligence, Maintain Control, Sensor Sweep.
- Break their end-of-turn holds (Outmanoeuvre, Immovable Object, Inescapable Dominion).
- Void Vanguard Operation's 'no enemy units within this terrain area'.
- Enter the centre against Centre Ground.
- Move your own unit into no-man's-land, or out of your territory, for your own opponent-turn cards.

- **When:** In the opponent's turn, when all of these apply:
- Their end-of-turn award or action completion hinges on an objective or area within your Heroic Intervention reach: within 12″ of an enemy, and Into the Fray targets within 6″.
- You have the CP.
- Your unit's OC will count, because it isn't battle-shocked.
- **Units:** Unengaged melee-capable units, not battle-shocked; a VEHICLE only if CHARACTER/WALKER.
- **Move type:** Charge move (11.04) via Heroic Intervention (15.11). Adjacent: end of the opponent's Charge phase.
- **11e rules (corrected):** - 15.11 (40k_11th_edition_core_rules.txt:2734-2766).
- 14.02: control at the end of each phase and turn (:2401-2423).
- 01.07: a battle-shocked unit's OC is '-' (:212-215).
- Card clauses in missionCards.json: centre-ground (:2311), vanguard-operation (:1597), display-of-might (:2246), defend-stronghold (:2706).
- The action names come from missions#64 and were not re-verified card by card.
  - _Errata check:_ Add the Heroic Intervention targeting limit to the conditions: a unit that used the rapid disembark mode this turn (e.g. from a Trukk's Pilin' Out) can't be targeted. — FAQ, rapid disembark vs Heroic Intervention (errata_faq:610-611)
- **AI today (none):** evaluate_heroic_intervention has no objective, area or card term (AIDecisionMaker.gd:27770-27976). The Heroic Intervention decision never reads the opponent's pending card actions (MissionManager.get_pending_card_action_11e).
- **Engine support:** Reuse MissionManager.get_card_action_summary_11e / get_pending_card_action_11e (MissionManager.gd:2197, 2266), MissionManager.model_in_objective_range (:529) and _estimate_objective_vp_value (:22928).
New: an estimator of the opponent's end-of-turn VP at stake per objective or area, used by Heroic Intervention (and by Rapid Ingress and consolidation).
- **Value (medium):** One Heroic Intervention can deny several VP and break an action in the opponent's turn. It is mission-dependent.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:2734-2765, 2401-2423
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-purge-the-foe/ (search snippet: 'Purge mirror-matches are described as having a secret weapon in Heroic Intervention')
  - 40k/data/40kdc/missionCards.json:1597, 2246, 2311, 2706
  - 40k/scripts/AIDecisionMaker.gd:27770-27976 (evaluate_heroic_intervention: unit value ×0.5, +2 CHARACTER, +1 MONSTER, ×1.3/×0.7 by target value)
  - Coverage inventory B50 limitation: “No objective or positional value for the counter-charge (contesting an objective, shielding a unit)”
- **Absorbed duplicates:** DEN-33 (Heroic Intervention to contest an objective or shield a unit)
- **Found by:** missions, bucket-editor, coverage

#### ADJ-18 — Make a reactive move to body-block the mover's route

Use the reactive move to spread the unit across the triggering enemy's route to an objective or to a soft friendly unit. Its later moves and charges must then go around, or end up charging the blockers: enemy bases can't pass through your models, so leave gaps narrower than their base. The move must still end unengaged and in coherency (2″, and 9″ across the unit). Trukk Pilin' Out (a reactive rapid disembark when an enemy ends within 8″) could drop a blocking unit, but the engine hasn't implemented it.

- **When:** The enemy still has phases to move toward an objective or unit (their Charge phase, their next turn), your multi-model unit has a reactive move, and it has enough models to make a wall within the cap while ending more than 2″ from enemies.
- **Units:** Multi-model units with reactive moves (Gretchin, Gladius Infantry, Phobos squads); Trukk passengers (Pilin' Out).
- **Move type:** Normal move (09.05) granted reactively, or a reactive rapid disembark (18.04). Adjacent: opponent's Movement phase.
- **11e rules (corrected):** - 03.01: bases can't move through enemy models (40k_11th_edition_core_rules.txt:388).
- 09.05: ends unengaged (:1390-1399). 03.03: coherency 2″ and 9″ (:514-537).
- 11.04: a charging unit can't end engaged with non-targets (:1662-1663).
- Pilin' Out: .llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv:96. FAQ: a unit that rapid-disembarked can't be Heroic Intervention's target (40k_11th_edition_errata_faq_commentary.md:610-611).
- Gap physics: 11e normal moves only need to END unengaged, so a gap seals when it is narrower than the enemy base (AIDecisionMaker.gd:28388).
  - _Errata check:_ The gap physics is now officially sourced: a unit doesn't become engaged while moving through an enemy's engagement range, so only bases block, and the wall holds only where gaps are narrower than the mover's base. Movers with a 'move through models' rule still pass. — FAQ 03.04 Engagement (errata_faq:265-266); Commentary 03.01.02 Moving Over Or Through Models (errata_faq:228)
- **AI today (none):** No reactive handler scores blocking. The engine's AI solver only moves away from the trigger or toward an objective, translating the unit rigidly (MovementPhase.gd:6443-6525). Pilin' Out has a name mapping only (OrkAbilities11e.gd:80, :163), with no window or handler.
- **Engine support:** Reuse _screen_widest_passable_gap_inches (:28388), _compute_screen_position (:15028) and the corridor block points (:15092-15182).
New:
- Block-point targeting for reactive moves.
- A per-model line-formation solver, since the current solver only translates the unit.
- **Value (medium):** It stalls an enemy push using mid-turn information. It needs multi-model units and a model-line solver.
- **Evidence:**
  - YouTube 40K Dirtbags Enm67qaqHkU @20:00 — “he then reactive moves and kind of spreads out to stop Ghaz from moving this way” [F014]
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-reconnaissance/ (search summary: throw themselves in front of a more valuable unit, move-block choke points)
  - 40k/scripts/AIDecisionMaker.gd:28388 (_screen_widest_passable_gap_inches)
  - 40k/scripts/codex/orks/OrkAbilities11e.gd:80, 163 (Pilin' Out name mapping only)
  - YouTube Enm67qaqHkU @20:00 (40K Dirtbags): “he then reactive moves and kind of spreads out to stop Ghaz from moving this way” [F014]
  - 40k/phases/MovementPhase.gd:6443-6480 (_ork11e_auto_reactive_move: away from the trigger or toward the nearest objective not controlled)
  - _…and 2 more_
- **Absorbed duplicates:** DEN-32 (Use your own reactive move to body-block or screen, not only to dodge)
- **Found by:** youtube, factions, first-principles, core-rules, bucket-editor

#### ADJ-19 — Shape the charge move's end positions for what comes next

Within the charge-move rules, choose where around the targets your models land. The rules: each model ends closer to a charge target, models that can end within 1″ of a target or engaged with it must do so, and the unit can't end engaged with non-targets. Useful choices:
- The far side, to start a wrap (ADJ-03).
- Inside the objective's range, so the fight ends with OC there and Objective Consolidation is available.
- More than 3″ from other enemy units you don't want to be forced into on consolidation.
- Inside a terrain area, for cover.
- Spread out, to maximise pile-in reach.
FLY units may take to the skies on a charge (-2″, declared before the roll) to land over terrain or models.

- **When:** After a successful charge roll, in your own Charge phase or a Heroic Intervention, when there's spare distance or placement freedom.
- **Units:** Charging units.
- **Move type:** Charge move (11.04). Adjacent: Charge phase.
- **11e rules (verified):** - 11.04: each model ends closer to a charge target; models that can end within 1″, or engaged, must; the unit must be engaged with all targets and with no others (40k_11th_edition_core_rules.txt:1640-1665).
- 12.08: Engaging and Objective consolidation gates at 3″ (:1947-1958).
- 14.02 (:2401-2423).
- 21.03 take to the skies (:3358-3373); FAQ: declare it before rolling (40k_11th_edition_errata_faq_commentary.md:681-682).
- **AI today (none):** _compute_charge_move (AIDecisionMaker.gd:19797-20324) covers every declared target (uncovered targets first, nearest first), then fixes missed close-in obligations and coherency. There is no term for objectives, wraps, cover or consolidation set-up. FLY units never take to the skies (SET_TAKE_TO_SKIES is never emitted).
- **Engine support:** Reuse the _compute_charge_move scaffolding, MissionManager.model_in_objective_range (MissionManager.gd:529), TerrainManager.area_at (TerrainManager.gd:847) and the consolidation wrap angles (:22178-22240).
New: a per-model endpoint scorer covering objective range, wrap slots, distance to other enemies, and cover.
- **Value (medium):** It sets up wraps and objective consolidation on every successful charge.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1640-1665, 1947-1958
  - missions#65 movement precursor: plan charge and fight end positions within 3″ of the target objective and more than 3″ from other enemies
  - 40k/scripts/AIDecisionMaker.gd:19797-20324 (_compute_charge_move)
- **Found by:** core-rules, missions

#### ADJ-21 — Use Objective Consolidation to slide out of sight or charge reach while staying on the objective

11e has no free 'step back' consolidation: with no enemy within 3″ and no objective within 3″, the unit can't consolidate at all. Objective mode, though, only requires each moved model to end within range of the selected objective. Models already in range can move up to 3″ to another point still in range, for example the far side of a terrain objective or behind its walls. With several objectives within 3″, you may pick the one whose range lies behind cover. Use this to dodge the enemy's next shooting or charges while keeping OC.

- **When:** The unit fought, is unengaged, has no enemy within 3″ and has an objective within 3″, and enemy shooters or chargers will act before you move again.
- **Units:** Any unit that fought.
- **Move type:** Consolidation move, Objective mode (12.08). Adjacent: Fight phase.
- **11e rules (corrected):** - 12.08: Objective mode, WHILE and AFTER conditions (40k_11th_edition_core_rules.txt:1956-1958, 1968-1970, 1985-1987).
- 14.02: within range of a terrain objective means within its area (:2401-2406).
- 13.08 / 13.10 cover and obscuring (:2278-2311).
- Engine: the player's pick wins, and the default is the closest objective (ConsolidationMove.gd:110-126).
- Correction: youtube#59 and the F016 quote 'consolidate backwards' are legal only through Objective mode.
- **AI today (none):** Objective mode always heads to the closest selectable objective (_ai_consolidate_objective_target, AIDecisionMaker.gd:21823-21860). _compute_consolidate_movements_objective (:22320+) then moves models toward that marker, with no line-of-sight or threat term.
- **Engine support:** Reuse TerrainManager.model_visible_11e (TerrainManager.gd:1209), LineOfSightManager.calculate_los_to_position (:101), _evaluate_position_threat (:28794) and MissionManager.model_in_objective_range (:529).
New: an in-range endpoint search that minimises enemy sight lines and charge reach, plus objective selection via chosen_objective.
- **Value (medium):** It keeps OC while denying the enemy a free shot, which F016 explicitly recommends. Only some board states allow it.
- **Evidence:**
  - YouTube 40K Dirtbags Enm67qaqHkU @24:00 — “I picked this objective to cons consolidate backwards a little bit so he doesn't get shot” [F016]
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-the-charge-and-fight-phases/ (single-source snippet: on a terrain objective you can freely move 3″ on it as long as you don't leave the terrain)
  - 40k/scripts/rules/movetypes/ConsolidationMove.gd:1-20, 110-126
- **Found by:** youtube, web, first-principles, factions

#### ADJ-22 — Scout or Infiltrate into a Hidden or obscured forward post (move into cover, pre-battle)

Put INFANTRY/BEASTS/SWARM Scouts or Infiltrators inside a forward terrain area with light or dense terrain, so they start the battle Hidden: visible only within 15″ detection range, and 3″ less when dense terrain conceals them (gone to ground). Alternatively, put them behind obscuring terrain. This gives safe forward pressure, early scoring for terrain-area cards and actions (Plunder, Death Trap, Vanguard Operation), and a launch point for turn-2 charges or actions. In the first turn a unit counts as not having shot in the previous turn.

- **When:** A forward terrain area is reachable within Scouts X″ (or anywhere, for Infiltrators) and is more than 8″ from enemies. This matters most when you go second (the turn order is known at this step) or face a shooting army.
- **Units:** INFANTRY/BEASTS/SWARM with Scouts or Infiltrators (Phobos squads, Scout Squads, Kommandos, Wolf Scouts, Fenrisian Wolves with a grant).
- **Move type:** Scout move (24.32) / Infiltrators set-up (24.20). Adjacent: pre-battle.
- **11e rules (corrected):** - 24.20 / 24.32 (40k_11th_edition_core_rules.txt:3754-3762, 3884-3901).
- 13.09 Hidden (:2292-2302), with the light/dense errata (40k_11th_edition_errata_faq_commentary.md:529).
- 13.09.01: Hidden in the first turn (errata_faq:533). 13.11.01: gone to ground (errata_faq:539).
- 13.10 obscuring (:2305-2311).
- FAQ: pre-battle rules alternate (errata_faq:696-697).
- Correction: candidates say 'dense terrain' for Hidden; the errata makes it light or dense.
- **AI today (none):** Scout destinations are objectives only (AIDecisionMaker.gd:5969-6061). The deployment terrain scoring is never applied to scouts or Infiltrators; that is the scoring where characters and fragile shooters prefer line-of-sight blockers and cover (_score_terrain_for_role :5594, _classify_deployment_role :5353). WEIGHT_HIDDEN_GAINED is 0.0 (:2633) and is used only in Movement-phase scoring.
- **Engine support:** Reuse _position_would_be_hidden / _hidden_immunity_fraction (:28515, :28548), TerrainManager.area_at / category_of (TerrainManager.gd:847+) and _score_terrain_for_role (:5594).
New: Hidden-post candidates for scout and Infiltrator placement, scored by safety and the next-turn objective or action they enable.
- **Value (medium):** Hidden forward units are a 11e staple (F001), and Scouts and Infiltrators are ideal for them. Today the AI places none.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:2292-2311, 3754-3762, 3884-3901
  - 40k_11th_edition_errata_faq_commentary.md:529, 533, 539
  - research/youtube/ai_learnings.json F001 (40K Dirtbags 0Gcpze1G4Lc @10:00 — “I try and get that dense cover for the hidden 12 ... How fast can I get to hidden 12”)
  - web#73: Hidden forward terrain against gunlines; 40k/scripts/AIDecisionMaker.gd:24218-24224 (Plunder wants_forward_terrain, never read)
- **Found by:** youtube, web, first-principles, factions, core-rules

#### ADJ-23 — Scout or Infiltrate within turn-1 reach of the enemy (charge staging or aura range: move toward an enemy to charge it, pre-battle)

End the scout move (more than 8″ from all enemy units), or set up Infiltrators, where taking the first turn lets a normal move or Advance plus the 2D6 charge reach a priority target. Charge targets must be within 12″ and within the roll. Alternatively, put an aura or ability carrier, such as a battle-shock aura, where it covers enemy units on turn 1. The turn order is known at this step, so push hard only when going first. Going second, stage at the same distance behind obscuring terrain.

- **When:** Fast melee units or aura carriers have Scouts or Infiltrators, a priority enemy deployed within reach, and you take the first turn (or have a safe screened spot).
- **Units:** Fast melee units with Scouts (Wolf Scouts, Scout Bike Squad, Kommandos with Snikrot); aura or ability carriers with Infiltrators (Neurolictor-style battle-shock auras).
- **Move type:** Scout move (24.32) / Infiltrators set-up (24.20). Adjacent: pre-battle.
- **11e rules (verified):** - 24.32: ends more than 8″ from all enemy units (40k_11th_edition_core_rules.txt:3884-3901). 24.20 (:3754-3762).
- 11.02: a unit must be within 12″ to declare a charge, and can't if it advanced, unless a rule allows (:1603-1629).
- 11.04: targets within the roll (:1640-1661; FAQ 40k_11th_edition_errata_faq_commentary.md:161).
- 22.01 aura abilities (:3394-3403).
- FAQ: pre-battle rules alternate starting with the first-turn player (errata_faq:696-697).
- **AI today (none):** The scout and deployment decisions have no first-turn charge or aura term (AIDecisionMaker.gd:5831-6240, 5055-5797). These decisions don't use the UnitAbilityManager aura helpers (UnitAbilityManager.gd:3662-3730).
- **Engine support:** Reuse _charge_success_probability (:18928), _estimate_melee_damage (:19576) and UnitAbilityManager.find_enemy_units_within_aura (UnitAbilityManager.gd:3662-3730).
New: a first-turn threat evaluator for scout and Infiltrator destinations, with the first-turn player as an input.
- **Value (medium):** It turns the pre-battle move into turn-1 damage or battle-shocks when going first. The value depends on the army and on the turn order.
- **Evidence:**
  - YouTube Factions&Fate OKoDYKdWm1E @04:00 — “infiltrated up here just a little bit past my deployment line, but still within range to hand out battle shocks” [F023]
  - YouTube Maelstrom Gaming Studios - Tyranids efeKiBbPUPM @09:00 — “My Neurolictor battleshocked Volus and the Paladins, which allowed both the Neurolictor and the Hive turret to charge in and precision out” [F023]
  - web#73 / factions#47: staging a turn-1 charge is a listed Scouts job
- **Found by:** web, first-principles, factions, youtube

#### ADJ-24 — Shoot, then move out of sight or out of charge reach (post-shooting move)

Several rules give a normal move right after the unit shoots in your Shooting phase:
- Purgation Run (Land Speeders, D6″).
- Mobile Hunter (Pallas Grav-attack, D6″).
- Shadow Masters (Phobos and Scout Squads: D6″, or stay Hidden instead).
- Execute and Redeploy (Phobos, 6″).
- Tactical Fluidity (Captain in Phobos Armour, D6″).
Use the move to shoot and scoot: break line of sight from the enemy's best guns, leave the charge reach of nearby melee, or step into a terrain area. These moves usually cost the unit its charge this turn.

- **When:** The unit has shot and is exposed to return fire or charges, and a line-of-sight blocker, terrain area or out-of-reach spot is within the move distance.
- **Units:** Land Speeders, Pallas Grav-attack, Phobos units, Scout Squads, Captain in Phobos Armour.
- **Move type:** Normal move (09.05) granted after shooting. Adjacent: your own Shooting phase.
- **11e rules (corrected):** - Rule texts: Purgation Run (.llm/codex_11e_wahapedia/space-marines/wahapedia/Datasheets_abilities.csv:588), Tactical Fluidity (:557), Mobile Hunter (custodes/wahapedia/Datasheets_abilities.csv:85), Shadow Masters (space-marines/RULES.md:619), Execute and Redeploy (:622).
- Reactive normal moves are 09.05 normal moves (ReactiveMove11e.gd:3-25; 40k_11th_edition_core_rules.txt:1390-1399).
- 13.08-13.10 (:2278-2311).
  - _Errata check:_ Shadow Masters' 'stay Hidden' option keeps the unit hidden (15″), but a unit that shot this turn or last can't go to ground (no -3″). All of these post-shooting moves are normal moves, so a unit makes at most one per phase (e.g. not Shadow Masters plus Execute and Redeploy or Tactical Fluidity). — Commentary 13.11.01 Gone to Ground, designer's note (errata_faq:539); Commentary 09.05.01 More Than One Normal Move in a Phase (errata_faq:470)
- **AI today (none):** The AI never makes these moves to hide:
- Purgation Run, Knight Champion and Glory of Ultramar score 0.0 (SMAbilitiesC.gd:1930-1931).
- Mobile Hunter and Take Wing score 0.0 (CustodesAbilities.gd:1329-1330).
- Teleport Homer and Tactical Fluidity score 0.0 (SMAbilitiesB.gd:1827-1828).
- Shadow Masters always takes the 'stay Hidden' option, never the move (SMDetachmentsA.gd:1053-1055).
- Execute and Redeploy is used only when its move reaches an objective (:1056-1058).
The reactive solver only knows 'toward an objective' or 'away from the trigger' (ReactiveMove11e.gd:315-358; MovementPhase.gd:6503-6525).
- **Engine support:** Same probes as ADJ-05: TerrainManager.model_visible_11e (:1209), LineOfSightManager.calculate_los_to_position (:101), _evaluate_position_threat (:28794).
New: the shared reactive-move destination scorer, given a 'shooters that act before my next move' input.
- **Value (medium):** Shoot-and-scoot makes these fast units survive. The AI today declines a free move every time it is offered.
- **Evidence:**
  - .llm/codex_11e_wahapedia/space-marines/RULES.md:619, 622; space-marines/wahapedia/Datasheets_abilities.csv:557, 588; custodes/wahapedia/Datasheets_abilities.csv:85
  - 40k/scripts/codex/space_marines/SMAbilitiesC.gd:1930-1931; SMAbilitiesB.gd:1827-1828; 40k/scripts/codex/custodes/CustodesAbilities.gd:1329-1330; 40k/scripts/codex/space_marines/SMDetachmentsA.gd:1053-1058
  - 40k/scripts/rules/ReactiveMove11e.gd:315-376
  - 40k/scripts/codex/space_marines/SMDetachmentsA.gd:841-872 (Execute and Redeploy: reactive_normal_move follow-up, max 6″)
  - 40k/scripts/codex/space_marines/SMDetachmentsA.gd:1015-1058 (AI: Execute and Redeploy only when out of objective range and a 6″ move reaches one; Shadow Masters only 'stay hidden')
  - 40k/scripts/AIDecisionMaker.gd:16397-16416 (Swift as the Eagle and Go Get 'Em! always declined: the engine has no executor for the move)
  - _…and 1 more_
- **Absorbed duplicates:** COO-42 (Use move-after-shooting abilities to reposition)
- **Found by:** factions, bucket-editor

#### ADJ-09 — Heroic Intervention (Leap to Defend) into a unit that just charged

At the end of the opponent's Charge phase, for 1CP, an unengaged unit within 12″ of enemies resolves a charge whose targets can only be units that made a charge move this phase and are within the 2D6 roll. Use it to join a fight the enemy started: counter-hit the charger now, since it fights in their Fight phase as well as yours, and protect or add OC around the friend or objective it charged.
The charge gives your unit Fights First. The active player starts the Fights First alternation, though, so their chargers usually still swing first.
Costs: the unit may leave an objective (control is checked at the end of every phase and turn), and it starts your turn engaged, so it can only Fall Back or stay, and can't charge.
Faction discounts: Countercharge (AA CHARACTER, -1CP), Laurels of Vigilance, Celeritous Sentries, Grimnar's Mark.

- **When:** When all of these apply:
- An enemy charge landed within 12″ of your unengaged melee unit.
- The trade is good and you have 1CP.
- The unit isn't needed on an objective at the end of their turn.
- It didn't rapid-disembark this turn.
- **Units:** Unengaged melee-capable units within 12″ of the charger, not battle-shocked. A VEHICLE only if it is a CHARACTER or WALKER.
- **Move type:** Charge move (11.04) via Heroic Intervention (15.11). Adjacent: end of the opponent's Charge phase.
- **11e rules (corrected):** - 15.11: WHEN end of your opponent's Charge phase. TARGET an unengaged unit within 12″ of enemy units; a VEHICLE only if CHARACTER/WALKER. Leap to Defend: only units that made a charge move this phase (40k_11th_edition_core_rules.txt:2734-2766).
- 11.02 / 11.04 charge: targets within 12″ and within the roll; models that can engage must; Fights First until end of turn (:1603-1665).
- 12.04: the Fights First alternation starts with the active player (:1830-1832).
- 15.01 limits (:2498-2501). 01.07: no stratagems on battle-shocked units (:216-217).
- FAQ: a unit that rapid-disembarked this turn can't be targeted (40k_11th_edition_errata_faq_commentary.md:610-611).
- Discounts: space-marines/RULES.md:366 (Countercharge), :709 (Laurels of Vigilance); custodes/RULES.md:165 (Celeritous Sentries); space-marines/SPACE_WOLVES.md:50 (Grimnar's Mark).
- Correction: first-principles#103 and web#75 say Heroic Intervention gives no Fights First. 15.11 resolves a charge, and 11.04 grants Fights First (:1664-1665). The engine withholds it 'Per 10e rules' (ChargePhase.gd:4092-4099).
- **AI today (partial):** What exists: evaluate_heroic_intervention (AIDecisionMaker.gd:27770-27976, called at :18277).
- It scores eligible melee units by unit value x0.5, +2 for CHARACTER, +1 for MONSTER, then x1.3 / x0.7 by target value.
- It uses Heroic Intervention at a score of 2.0 or more, or 4.0 or more with the last CP (:27909-27921).
- _hi_target_for_unit_11e picks Leap to Defend whenever a charger is within 12″ (:27697-27717).
- Charge odds count only with FIX_HI_CHARGE_ODDS, which is OFF (:1948; _hi_mode_odds_11e :27729-27758).
What is missing: no value for protecting a friend or objective, no cost for leaving an objective, and no faction discounts (0 grep hits for Countercharge, Laurels or Celeritous).
- **Engine support:** Reuse _hi_mode_odds_11e, _charge_success_probability (:18928), _estimate_melee_damage (:19576), _estimate_incoming_melee_damage (:12350), _unit_has_model_in_control_range (:13269) and _evaluate_all_objectives (:8926).
New:
- A 'friend saved / OC kept' term and an 'objective left' cost.
- Read the discounted CP cost through StratagemManager.
- **Value (medium):** Every army has this core stratagem in each opponent turn. The AI already uses it, so the gain comes from better target and cost modelling.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:2734-2766, 1640-1665, 1830-1832
  - 40k/autoloads/StratagemManager.gd:5110-5118; 40k/phases/ChargePhase.gd:3855-3898 (mode targets), :4092-4099 (no fights_first, '10e')
  - https://grimslate.com/blog/core-stratagems-guide-11th-edition (search snippet)
  - https://spikeybits.com/warhammer-40k-11th-edition-stratagems-overhauled/ (the unit you intervene with might not even swing first); https://www.wargamer.com/warhammer-40k/stratagems
  - https://www.youtube.com/shorts/5DwnE4bZBBc ; https://www.tiktok.com/@first.turn.tactic/video/7649715891055136020 (search titles: 'In 11th edition heroic interventions will get the fights first ability for the remainder of the turn')
- **Found by:** core-rules, web, first-principles, factions

#### ADJ-10 — Counter-charge to lock a dangerous shooter or action unit before your turn (Into the Fray, NO ESCAPE)

Into the Fray (+1CP, 2CP total; roll capped at 6; targets any enemy within 6″) lets an unengaged unit charge a unit that did NOT charge: a shooter, objective holder or actor that crept close. The target fights now and stays engaged into its next turn. Then it must Fall Back, which means no shooting, charging or actions afterwards unless a rule allows it, or stay locked. While engaged it can't Fire Overwatch or Heroic Intervene, and non-MONSTER/VEHICLE units can only shoot [CLOSE-QUARTERS] weapons at units engaged with them.
Shadowkeepers NO ESCAPE (2CP, opponent's Movement phase) does the same to a unit that just fell back within 6″.
Costs:
- In your turn you can't shoot a locked non-MONSTER/VEHICLE target.
- Your unit starts your turn engaged.
- Locking a MONSTER/VEHICLE barely reduces its shooting: close-quarters shooting works at -1.

- **When:** At the end of the opponent's Charge phase (NO ESCAPE: right after an enemy fall-back), when all of these apply:
- A high-output non-vehicle shooter, actor or objective holder is within 6″ and within the capped roll.
- You have 2CP.
- Your unit survives the target's attacks.
- **Units:** Durable melee units (a VEHICLE only if CHARACTER/WALKER); Custodes Infantry for NO ESCAPE.
- **Move type:** Charge move (11.04) via Heroic Intervention Into the Fray (15.11) or NO ESCAPE. Adjacent: opponent's Charge or Movement phase.
- **11e rules (corrected):** - 15.11 Into the Fray: +1CP, roll capped at 6, targets within 6″ (40k_11th_edition_core_rules.txt:2756-2765). FAQ: a +1CP section makes the original cost 2CP (40k_11th_edition_errata_faq_commentary.md:576-577).
- 09.07: after a fall-back, no shooting, charging or starting actions (:1437-1439).
- 15.08 Fire Overwatch and 15.11 both need an unengaged unit (:2741-2742, :2745-2746).
- 16.01: engaged units can't start actions (:2807-2815).
- 10.06 close-quarters shooting (:1522-1547); 17.03: only engaged MONSTER/VEHICLE units can be shot (:2898-2908).
- NO ESCAPE: .llm/codex_11e_wahapedia/custodes/RULES.md:141.
- Correction: the engine and the AI price Into the Fray at 1CP (StratagemManager.gd:5110-5118; ChargePhase.gd:3858-3898; AIDecisionMaker.gd:27785-27790).
  - _Errata check:_ Engaged MONSTER/VEHICLE units can be shot only with non-[BLAST] ranged attacks (17.03 errata). Also, a unit that used the rapid disembark mode this turn (e.g. Pilin' Out) can't be targeted with Heroic Intervention, so it can't use Into the Fray. — 17.03 errata (errata_faq:608); FAQ, rapid disembark vs Heroic Intervention (errata_faq:610-611)
- **AI today (partial):** The AI chooses Into the Fray only when no charger is within 12″ (_hi_target_for_unit_11e, AIDecisionMaker.gd:27697-27717), and scores it like any Heroic Intervention by unit value and target value (:27770-27976). There is no lock value: neither the target's ranged output nor its actions count. The CP gate checks the 1CP base (:27785-27790), though this mode costs 2CP. NO ESCAPE scores a flat 2.5 for any melee unit (CustodesCodexMovement.gd:257-258).
- **Engine support:** Reuse _estimate_unit_ranged_strength (:25866), the multi-phase plan's lock-target threshold (:3773-3946) and MissionManager.get_pending_card_action_11e (MissionManager.gd:2266) to identify actors.
New:
- A lock-value term: the shooting denied next turn, minus our own lost shooting at the target.
- The 2CP gate for Into the Fray.
- **Value (medium):** This denies an enemy shooting or action turn for 2CP; F015 shows players charge purely to tie up shooters. 11e close-quarters shooting limits the payoff against vehicles.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:2734-2766, 1437-1439, 1522-1547
  - 40k_11th_edition_errata_faq_commentary.md:576-577
  - .llm/codex_11e_wahapedia/custodes/RULES.md:141 (NO ESCAPE)
  - YouTube 40K Dirtbags 0Gcpze1G4Lc @14:00 — “this thing was within range to move up and shoot her. So, I needed to make this charge to stop this tank” [F015]
  - https://grimslate.com/blog/core-stratagems-guide-11th-edition ; https://www.wargamer.com/warhammer-40k/stratagems
- **Found by:** core-rules, web, first-principles, factions

#### ADJ-16 — Make a reactive move out of the triggering enemy's charge reach

An enemy that can still declare a charge this turn may end a move within 8″ of your unit. Use the reactive normal move to open the gap beyond its likely charge (targets must be within 12″ and within the 2D6 roll), or to put terrain or friendly units in its path. Don't do it when the unit is needed on an objective at the end of their turn.

- **When:** The triggering enemy is melee-capable and didn't Advance or Fall Back, your unit fights poorly, and the move doesn't leave an objective you need or break an action.
- **Units:** Reactive-move units, as in ADJ-05: Gretchin (SCARPER!), Deffkoptas (WHIRLIGIG EVASION), Gladius units, Phobos units, Trusted Sentinels, and others.
- **Move type:** Normal move (09.05) granted reactively. Adjacent: opponent's Movement phase.
- **11e rules (verified):** - 09.05 (40k_11th_edition_core_rules.txt:1390-1399); one normal move per phase (40k_11th_edition_errata_faq_commentary.md:470).
- 11.02 charge eligibility: within 12″, not advanced or fallen back (:1603-1629).
- 11.04: targets within 12″ and within the roll (:1640-1661). FAQ: targets must be within the roll including modifiers (errata_faq:161).
- Rule texts: SCARPER! (orks/RULES.md:223), WHIRLIGIG EVASION (orks/RULES.md:268).
- **AI today (partial):** Only the Ork units do this today. SCARPER! and WHIRLIGIG EVASION pay 2.0 only when the triggering enemy could still charge this unit, and never from an objective (OrkCodexMovement.gd:300-309, _charge_threat). The engine's AI solver then moves the unit straight away from the trigger ('away' goal, MovementPhase.gd:6503-6510), trying headings up to 180° at 100/75/50/25% of the cap (:6443-6500).
The other armies' reactive moves never use this purpose:
- RESPONSIVE TACTICS / TRANSHUMAN REACTIONS are objective-only (SMCodexAMovement.gd:271-278).
- SWIFT AS THE EAGLE, Evade and Survive and Predatory Instinct score 0.0 (CustodesCodexMovement.gd:255-256).
The resulting gap is never checked against charge odds or terrain.
- **Engine support:** Reuse _charge_success_probability and _charge_roll_needed (:18928, :18840), TerrainManager.calculate_charge_terrain_penalty (TerrainManager.gd:509) and _evaluate_position_threat (:28794).
New: a charge-odds term in the shared reactive-move destination scorer (ADJ-05).
- **Value (medium):** It saves fragile units from charges using information only available mid-turn. Several armies have the tool, but only the Orks use it, and crudely.
- **Evidence:**
  - YouTube TacticalTortoise 40k VqwMdS9MuIY @60:00 — “it has the ability to reactive move to enemies going close to it ... it may be able to jump away” [F014]
  - https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-reconnaissance/ (search summary: reactive moves used to run away from charges)
  - 40k/scripts/stratagems/ork_codex/OrkCodexMovement.gd:300-309; 40k/phases/MovementPhase.gd:6443-6510
- **Found by:** youtube, factions, web, first-principles, core-rules

#### ADJ-17 — Make a reactive move onto an objective (grab it, or retake it after they disengage)

Use an out-of-turn normal move to step into range of an objective before the opponent's end-of-phase or end-of-turn control check: one the mover just left, or one nobody holds. Taktikal Brigade WHILE THEIR BACKS ARE TURNED (end of their Movement phase, 6″) lets a unit that was engaged at the start of the phase walk back onto the contested objective after the enemy fell back. Control is recalculated at the end of every phase, so arriving in their Movement phase also changes who controls the objective during their Shooting phase.

- **When:** A reactive trigger fires, and an objective you need at the end of their turn (Burden of Trust, Defend Stronghold) or at your next Command phase is within the move. The enemy can't easily push you off before their turn ends.
- **Units:** Reactive-move units (the ADJ-05 list), plus Boyz, Kommandos and Stormboyz (WHILE THEIR BACKS ARE TURNED).
- **Move type:** Normal move (09.05) granted reactively. Adjacent: opponent's Movement or Shooting phase.
- **11e rules (corrected):** - 09.05 (40k_11th_edition_core_rules.txt:1390-1399).
- 14.02: control at the end of each phase and turn (:2401-2423).
- Rule texts: WHILE THEIR BACKS ARE TURNED (.llm/codex_11e_wahapedia/orks/RULES.md:189), RESPONSIVE TACTICS (space-marines/RULES.md:259), BATTLE INSTINCTS (space-marines/SPACE_WOLVES.md:54).
- Correction: core-rules#108 lists GRAB IT (orks/RULES.md:212) as a reactive move, but it is made in your own Shooting phase (ADJ-33).
  - _Errata check:_ Control is determined first at the end of each phase, before any other end-of-phase rules. A move from an end-of-Movement-phase rule such as WHILE THEIR BACKS ARE TURNED only changes control from the end of their Shooting phase; only moves made during the phase (e.g. RESPONSIVE TACTICS) count at the end of their Movement phase. — Commentary 14.02.01 Controlling an Objective at the End of a Phase (errata_faq:557)
- **AI today (partial):** What exists:
- RESPONSIVE TACTICS / TRANSHUMAN REACTIONS pay 2.1 only when an objective not already held is within 2″, or within the Tactical-doctrine reach (SMCodexAMovement.gd:271-278).
- BATTLE INSTINCTS pays when one is within 4″ (SWCodexMovement.gd:164-167; RULINGS.md:277).
- WHILE THEIR BACKS ARE TURNED pays 2.2 when an uncontrolled objective is within 9″ (OrkCodexMovement.gd:310-311).
- The engine solver heads for the nearest objective the player doesn't control (MovementPhase.gd:6503-6525; ReactiveMove11e.gd:315-358).
What is missing: objective value and end-of-turn timing. The AI goes to the nearest objective, not the most valuable.
- **Engine support:** Reuse _estimate_objective_vp_value (:22928), MissionManager.model_gap_to_objective_range_px (MissionManager.gd:569) and ReactiveMove11e._solve_normal_to_objective (:318-358).
New: choose the objective by its value at the coming check, inside the shared reactive scorer (ADJ-05).
- **Value (medium):** OC at the opponent's end-of-turn check, gained for free from moves the AI is already offered. Partly done today.
- **Evidence:**
  - .llm/codex_11e_wahapedia/orks/RULES.md:189, 212; space-marines/RULES.md:259
  - 40k/scripts/stratagems/ork_codex/OrkCodexMovement.gd:310-311; 40k/scripts/codex/space_marines/SMCodexAMovement.gd:271-278
  - 40k/scripts/rules/ReactiveMove11e.gd:315-358; 40k/phases/MovementPhase.gd:6503-6525
- **Found by:** core-rules, factions, first-principles, web

#### ADJ-20 — Overrun slingshot: extra pile-in into a second enemy when your target dies before you fight

A unit can be eligible to fight but unengaged: its charge target died to Crushing Impact or to earlier fights, or everything it was engaged with died before it fought. It then makes an Overrun fight: one additional 3″ pile-in toward enemy units within 5″, which must end engaged, and then it fights. Sequence your fights so a shared target dies first, then slingshot into a second unit. If no enemy is within 5″ yet, pass (allowed when all your eligible units are more than 5″ from enemies) and wait for an enemy pile-in to come close. Extended pile-ins (6″, D3+3″) raise the distance but not the 5″ target-selection range.

- **When:** When all of these apply:
- Two of your units share a target, or Crushing Impact may kill it.
- A second enemy is within 5″ plus reach.
- The unit is still eligible to fight: it charged this turn or was engaged at the start of the Fight step.
- **Units:** Melee units that charged, or were engaged, and lost their target.
- **Move type:** Pile-in move (12.03) as part of an Overrun fight (12.06). Adjacent: Fight phase.
- **11e rules (corrected):** - 12.04 eligibility (40k_11th_edition_core_rules.txt:1819-1825). 12.06 Overrun fight (:1866-1877).
- 12.03: an unengaged unit picks pile-in targets within 5″; moved models end closer to the closest target; the unit must end engaged (:1737-1766).
- FAQ: an overrun needs eligibility to fight (:4111-4119).
- Pass when more than 5″ away (40k_11th_edition_errata_faq_commentary.md:505-507). Extended pile-in distance FAQs (errata_faq:493-498).
- Corrections: youtube#61's 'or toward an objective' is illegal, because the pile-in must end engaged. The web preview's 'up to 6″' is 3″ unless an ability extends it.
  - _Errata check:_ Destroyed models awaiting a Fight On Death effect (e.g. A WORTHY DEATH, ORKS IS NEVER BEATEN, DUTY UNTO DEATH) stay on the battlefield, still engaged with your unit, until their unit has attacked or the phase ends. So the slingshot only opens once they are removed, and they can restrict the overrun pile-in. — FAQ 05.04 Inflict Damage, models awaiting Fight On Death (errata_faq:376-377)
- **AI today (partial):** When the engine grants the 12.06 extra pile-in, it offers PILE_IN for the active fighter (FightPhase.gd:4557-4566). The AI always takes it and moves models at the nearest enemy model (AIDecisionMaker.gd:20381-20391, then _compute_pile_in_action :21317). _pile_in_targets_11e (:21669) is gated off (FIX_PILEIN_TARGETS_11E = 0.0, :1988). The T7-46 fight-order optimiser (:20968-21060) never sequences a shared target's death to set up an overrun. The more-than-5″ pass is taken only when the engine offers it, never planned (:20580-20583).
- **Engine support:** Reuse FightSequencer's fight types (FightSequencer.gd:322-334), _pile_in_targets_11e, _score_fighter_priority (:21032) and _estimate_melee_damage (:19576).
New:
- A kill-then-slingshot sequencing term in fight order.
- A check for second targets within 5″ plus reach.
- **Value (medium):** It turns overkill into a second combat, a trick the community highlights for 11e. It needs several units in the same fight.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1729-1770, 1866-1877, 4111-4119
  - https://www.tabletopbattles.com/11-on-11th-recapping-the-new-warhammer-40k-rules-reveals-through-5-1/ (search snippet: an 'Overrun Fight' with an extra Pile In, described as a slingshot)
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-the-charge-and-fight-phases/ ; https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-fight-phase ; https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-faq-compendium (6″ pile-ins confirmed)
  - YouTube titles only (not watched): lcKvzVSN5l4 '11th Edition Fight Phase Trick - Move Angron 44″!'; _hGkcildjx0 'The STRONGEST Fight Phase tricks in 40k'
  - 40k/phases/FightPhase.gd:148-154, 1175-1186, 4557-4566; 40k/scripts/rules/FightSequencer.gd:322-334
- **Found by:** youtube, web, core-rules, first-principles

#### ADJ-25 — Remove casualties (and coherency breakers) to improve the unit's position

You choose which models leave the board in two situations: when you allocate damage, you pick which model in the current allocation group dies (wounded models first), and at each end of turn you pick which models to remove to restore coherency. Pick models so the survivors:
- Stay coherent. A bad pick costs an extra model at the end of the turn, and models removed for coherency still count as destroyed for mission cards.
- Keep the models that are in an objective's range, a terrain area or cover.
- Lengthen the enemy's next charge, by removing the closest models.
- End unengaged, by removing every model within 2″ of the enemy, so the unit can move and shoot normally next turn.

- **When:** Every allocation of attacks or mortal wounds to your unit, and every end-of-turn coherency check.
- **Units:** Multi-model units.
- **Move type:** Casualty or coherency removal (05.04, 03.03), in any phase. Adjacent: not a move, but it repositions the unit's footprint.
- **11e rules (verified):** - 05.03: allocation groups and order. 05.04 Select Model: one model in the current group, a wounded one if possible (40k_11th_edition_core_rules.txt:782-837).
- 03.03 Regaining Coherency: the controlling player removes models one at a time (:530-537).
- FAQ: models destroyed for coherency count for mission objectives (40k_11th_edition_errata_faq_commentary.md:252-253).
- **AI today (partial):** Allocation: CasualtyPreference.gd (:4-63) is the defender's automatic allocation for AI players. Coherency dominates its order, then it protects objective OC, removes front-rank models first by proximity, and adds charge-denial. It is applied wherever the engine auto-allocates (RulesEngine.gd:16663-16690; ShootingPhase.gd:3572-3580, 3772-3776).
End-of-turn coherency: AI owners fall through to the PhaseManager auto-pick of the most isolated offender (PhaseManager.gd:576-616). ScoringPhase.gd:51-58 offers the choice only to humans.
Missing: no cover or Hidden term, no explicit 'become unengaged' goal, and the coherency pick ignores objectives.
- **Engine support:** Reuse CasualtyPreference.compute_preferred_targets / engine_auto_preference, MissionManager.model_in_objective_range (:529), TerrainManager.area_at (:847) and is_model_hidden (:1001).
New:
- A cover/Hidden keep term and a 'remove all engaged models' option.
- Route PhaseManager's coherency auto-pick through CasualtyPreference.
- **Value (medium):** It happens constantly and is mostly handled. The remaining gains are cover/Hidden preservation and smarter coherency removals.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:782-837, 514-537
  - 40k/scripts/rules/CasualtyPreference.gd:4-63
  - 40k/autoloads/PhaseManager.gd:576-616; 40k/phases/ScoringPhase.gd:51-58
  - docs/rules/11th_edition_delta_audit.md:92 (03.03 caveat: removal auto-picked)
- **Found by:** core-rules

#### ADJ-26 — Pull a doomed unit off the board into strategic reserves (escape)

Some rules place a unit into strategic reserves outside the Movement phase:
- At the end of the opponent's Fight phase: On Gilded Wings, TACTICAL WITHDRAWAL, Kunnin' Infiltrator (all models Hidden), Aerial Manoover, INSTINCTIVE HUNTERS, CO-ORDINATED STRIKE, GUNSHIP EXTRACTION, Echo of the Ravenspire, Take Wing, Parabolic Jetleap.
- At the end of your turn: From Golden Light.
Use them to save a badly hurt or about-to-be-charged unit from the next turn's shooting and charges, then bring it back by an ingress move later. Repositioned units are exempt from the end-of-round-3 destruction, but units still in reserve at the end of the battle are destroyed. Leaving also gives up the unit's OC immediately.

- **When:** The unit is unengaged (as required), at low wounds or below half strength, with enemies that can reach it. It isn't needed for OC at the next check, and there are rounds left to arrive again (battle round below 5).
- **Units:** Custodes Terminators (On Gilded Wings), Phobos and Scout Squads (TACTICAL WITHDRAWAL), AA Terminators (GUNSHIP EXTRACTION), Blood Claws, Thunderwolf Cavalry and Wulfen (CO-ORDINATED STRIKE), Beast Snagga (INSTINCTIVE HUNTERS), Boss Snikrot, Deffkoptas, Kayvaan Shrike, Venatari, Inceptors.
- **Move type:** Repositioned to strategic reserves (20.02), later an ingress move (20.04). Adjacent: end of the opponent's Fight phase, or end of your turn.
- **11e rules (corrected):** - 20.02 repositioned units (40k_11th_edition_core_rules.txt:3219-3245).
- 20.03: the round-3 wipe exempts repositioned units (:3276-3283). 20.04 ingress (:3255-3273).
- FAQ: in-battle reserves may exceed the 50% cap (40k_11th_edition_errata_faq_commentary.md:662-665). Units in reserves at the end of the final turn are destroyed (errata_faq:673).
- Rule texts: On Gilded Wings (custodes/RULES.md:113; RULINGS.md:72), TACTICAL WITHDRAWAL (space-marines/RULES.md:624), GUNSHIP EXTRACTION (:659), CO-ORDINATED STRIKE (space-marines/SPACE_WOLVES.md:44), Kunnin' Infiltrator (orks/wahapedia/Datasheets_abilities.csv:51).
  - _Skeptic:_ Every cited extraction triggers at the end of the opponent's Fight phase: On Gilded Wings (custodes/RULES.md:113), TACTICAL WITHDRAWAL (SM RULES.md:624), GUNSHIP EXTRACTION (SM RULES.md:659), CO-ORDINATED STRIKE (SPACE_WOLVES.md:44), Kunnin' Infiltrator (orks Datasheets_abilities.csv:51). None triggers at 'end of your turn', so drop that timing. Kunnin' Infiltrator also needs every model hidden and unengaged. The 20.02/20.03 exemptions and the FAQs are correct. — custodes/RULES.md:113; space-marines/RULES.md:624, 659; space-marines/SPACE_WOLVES.md:44; orks/wahapedia/Datasheets_abilities.csv:51; 40k_11th_edition_core_rules.txt:3219-3245, 3276-3283
- **AI today (partial):** Each ability has its own heuristic:
- From Golden Light escapes at 50% wounds or less with an enemy within 12″, and never leaves an objective (AIDecisionMaker.gd:22496-22536, :22575-22600).
- On Gilded Wings: below half strength, or off an objective with an enemy within 9″ (CustodesDetachments.gd:1165-1174).
- INSTINCTIVE HUNTERS / KEEP IT RUNNIN' score 2.5 with an enemy within 12″ when not holding an objective (OrkCodexFight.gd:990-1002).
- TACTICAL WITHDRAWAL, CO-ORDINATED STRIKE, GUNSHIP EXTRACTION and Echo of the Ravenspire fire only for idle units with no enemy within 12″, so never as an escape (SMCodexAMovement.gd:298-305; SWCodexMovement.gd:175-183; SMCodexBAction.gd:279-285; SMAbilitiesC.gd:1922-1927).
- Kunnin' Infiltrator, Aerial Manoover, Take Wing and Parabolic Jetleap score 0.0 (OrkAbilities11e.gd:2329-2330; CustodesAbilities.gd:1329-1330; SMAbilitiesA.gd:2284-2285).
None estimates the incoming damage, or where the unit could arrive again.
- **Engine support:** Reuse _estimate_incoming_melee_damage (:12350), _evaluate_position_threat (:28794), _evaluate_end_turn_redeploy as the template, and _compute_reinforcement_positions (:8019) to check that an arrival spot exists.
New: one shared extraction scorer (expected loss if the unit stays vs the OC lost), called by all these codex hooks.
- **Value (medium):** It saves points that would otherwise die, and several armies in the project have it. The heuristics are inconsistent and mostly blind to the threat.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:3219-3245, 3276-3283
  - .llm/codex_11e_wahapedia/custodes/RULES.md:113; space-marines/RULES.md:624, 659; space-marines/SPACE_WOLVES.md:44; orks/wahapedia/Datasheets_abilities.csv:51
  - 40k/scripts/codex/orks/OrkAbilities11e.gd:1255-1268 (strategic-reserves diffs for Kunnin' Infiltrator and Aerial Manoover)
  - YouTube Warpbane Tactics veM7sLjtdIw @01:00 — “being careful about when we use our teleportation. Picking a unit up is incredibly useful, but under Take and Hold, that decision becomes more costly” [F027]
- **Found by:** factions, first-principles

#### ADJ-27 — Declare formations and deploy so the army works whether it goes first or second

Before the battle, choose what starts embarked, what goes into strategic reserves (AIRCRAFT must; at most 50% of points) and what starts on the table. Then deploy fragile and key units out of line of sight or in terrain, and threats where they can act on turn 1. The deployment must survive the opponent taking the first turn, because the first turn appears to be decided after deployment. Keep one Rapid Ingress answer in reserve unless the opponent's turn-1 threat range forces everything onto the table (F013).

- **When:** The Declare Battle Formations and deployment steps.
- **Units:** All units.
- **Move type:** Deployment set-up and formation declarations (18.01, 20.01, 23.01). Adjacent: pre-battle.
- **11e rules (unverified):** - 18.01: units can start embarked (40k_11th_edition_core_rules.txt:2975-2978).
- 20.01: strategic reserves are capped at 50% of points (:3205-3216).
- 23.01: AIRCRAFT must start in reserves (:3499-3501).
- 07.02: the mission says who takes the first turn (:1133-1138). The local missions summary doesn't state the method.
- So 'decided after deployment by a roll-off with no choice' rests on the engine (FirstTurnRollOffPhase.gd:6-21, labelled 10th edition), on F019, and on third-party 11e guides: the first-turn roll-off is its own step, and pre-battle rules alternate from the first-turn player, which matches 40k_11th_edition_errata_faq_commentary.md:696-697.
- **AI today (partial):** What exists:
- _evaluate_reserves_declarations / _score_unit_for_reserves (AIDecisionMaker.gd:4737-5033) send deep-strike melee and short-range units to reserves, with penalties for long-range, cheap-screen and vehicle units.
- _evaluate_transport_embarkation (:4439-4705).
- _decide_deployment (:5055-5797) uses _classify_deployment_role and _score_terrain_for_role, where characters and fragile shooters prefer line-of-sight blockers and cover and melee prefers forward blockers, plus _apply_counter_deployment.
- Plans can hand-author placements (PLAN_FORMAT.md:110-112).
Missing: no explicit 'if we go second' test of enemy turn-1 threat ranges against our deployment, and no rule to keep one Rapid Ingress answer.
- **Engine support:** Reuse _score_terrain_for_role (:5594), _apply_counter_deployment (:5421), _get_deployed_enemy_analysis (:5565) and _calculate_enemy_threat_data (:28695).
New:
- An 'opponent goes first' threat pass over candidate deployments.
- A reserve-keeping rule conditioned on the opponent's turn-1 threat range (F013's resolving variable).
- **Value (medium):** Deployment decides early survival. The AI already has terrain-aware deployment, so the missing pieces are turn-order robustness and a reserve answer.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1133-1138, 2975-2978, 3205-3216, 3499-3502
  - YouTube MiniWarGaming dy1zEFAKLzk @03:00 — “This is the nice thing about the whoever rolls highest has to go first. I do not have to sweat about who gets first turn” [F019, rules_status unverified]
  - YouTube Exile Wargaming mbNWzDn6Pu4 @10:00 — “we did win the dice roll and had to go first, which I don't really like in recon” [F019]
  - YouTube Art of War 40k ym0SnzF2ydg @162:00 — “maybe they should have just started the game in reserve so they could be a little bit more of a reactive answer” [F013]; Happy Krumping pAk1YiuioNQ @09:00 — “If you're ever going to play against it, don't start things in reserves. You need everything on the table” [F013]
  - 40k/phases/FirstTurnRollOffPhase.gd:6-21; 40k/phases/RollOffPhase.gd:6-18
  - https://warhammerguild.com/guides/40k-11th-edition-missions-explained/ ; https://spikeybits.com/40k-chapter-approved-tournament-companion-guide/ (search results: the first-turn roll-off is its own step after deployment)
- **Found by:** core-rules

#### ADJ-28 — Pile in to bring more models into the fight

In the shared Pile In step at the start of every Fight phase, both players may pile in, active player first. Move models not in base contact up to 3″ so each ends closer to the closest pile-in target, and engaged with it if possible, keeping every existing engagement. More models end up fighting. Extensions such as LIGHTNING WRATH (D3+3″) raise the maximum distance but not target selection.

- **When:** Every Fight phase in which your unit is engaged or charged this turn.
- **Units:** Engaged units and units that charged.
- **Move type:** Pile-in move (12.03). Adjacent: Fight phase, yours or the opponent's.
- **11e rules (verified):** - 12.02: both players pile in, active player first, optional (40k_11th_edition_core_rules.txt:1729-1735).
- 12.03: targets, the closer-and-engaged-if-possible rule, and keeping engagements (:1737-1766).
- FAQs on pile-in distance (40k_11th_edition_errata_faq_commentary.md:493-498).
- LIGHTNING WRATH: .llm/codex_11e_wahapedia/custodes/RULES.md:235.
- **AI today (full):** _compute_pile_in_action / _compute_pile_in_movements (AIDecisionMaker.gd:21317-21710) move each model up to 3″ toward the closest enemy model, into base contact where possible. They keep base-contact models in place, keep coherency and move attached characters too. LIGHTNING WRATH is paid when models are 3-6″ from an enemy (CustodesCodexFight.gd:314-317). Caveat: FIX_PILEIN_TARGETS_11E is OFF (:1988), so the target is the closest enemy model rather than the 11e closest pile-in target unit.
- **Engine support:** Existing: PileInMove template (PileInMove.gd) and _pile_in_targets_11e (:21669). To finish 11e fidelity: turn on FIX_PILEIN_TARGETS_11E.
- **Value (medium):** The core default, needed every Fight phase, and already covered.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1729-1766
  - docs/rules/11th_edition_delta_audit.md (12.02 row: global pile-in step)
  - 40k/scripts/rules/movetypes/PileInMove.gd:1-17
  - https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-the-charge-and-fight-phases/
- **Found by:** core-rules, first-principles, web, factions

#### ADJ-29 — Decline or limit the pile-in to keep objective range or avoid a second engagement

Pile-in is optional per unit, and only the models you choose to move must end closer to the target. Don't pile in, or move only the models that add attacks, when moving would:
- pull models out of an objective's range or a terrain area's cover, or
- bring them into engagement with an extra enemy unit, which then becomes eligible to fight you.

- **When:** The unit is already doing enough damage, or the extra models' attacks are worth less than the objective control, cover or safety they would give up.
- **Units:** Engaged units and units that charged.
- **Move type:** Pile-in move (12.03), declined or partial. Adjacent: Fight phase.
- **11e rules (verified):** - 12.02: 'all of their eligible units they choose to move', plus the sidebar 'you don't have to pile in or consolidate with a unit if you don't want to' (40k_11th_edition_core_rules.txt:1720-1735).
- 12.03: only moved models must end closer (:1757-1761).
- 12.04: engaged units are eligible to fight (:1821-1823).
- 14.02: control at the end of each phase (:2401-2423).
- **AI today (none):** The AI answers every PILE_IN offer with a move for every model not in base contact (AIDecisionMaker.gd:20381-20391, :21317-21350). It sends END_PILE_IN only after its units have piled in (:20551-20560). There is no objective-range or extra-engagement check.
- **Engine support:** Reuse MissionManager.model_in_objective_range (:529) and _estimate_incoming_melee_damage (:12350).
New: a per-model pile-in filter (move only if it adds attacks without losing range or adding an unwanted engagement).
- **Value (low):** A niche correction, but cheap once pile-in movements are scored.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:1720-1766
  - first-principles#101: pile in while staying in objective range
  - 40k/scripts/AIDecisionMaker.gd:20381-20391, 21317-21350
- **Found by:** first-principles, core-rules

#### ADJ-31 — Redeploy after both armies are set up, to answer the opponent's deployment

Several enhancements let you redeploy up to three units after both armies have deployed, and put them into strategic reserves however many units are already there: Wreckas Kaptin's Hat (Ork Infantry), Hunter's Guile (Blood Claws, Thunderwolf Cavalry, Wulfen), Chariots of the Storm (any AA units), Castellan's Mark (Custodes), Cyber-familiar (AA Infantry), Strategium Command. A redeployed unit is deployed again with all the normal rules, including Infiltrators. Uses:
- Pull units out of the enemy's firing lanes.
- Move to the flank where the enemy is weak.
- Shift into reserves to answer their deep strikers.

- **When:** The opponent deployed into a lopsided position, a unit is exposed to an alpha strike, or reserves are needed as a reactive answer (F013).
- **Units:** Ork Infantry (Kaptin's Hat), Blood Claws, Thunderwolf Cavalry and Wulfen, AA units, Custodes units.
- **Move type:** Redeployment set-up (deployment rules re-applied). Adjacent: pre-battle.
- **11e rules (verified):** - Enhancement texts: .llm/codex_11e_wahapedia/orks/RULES.md:208 (Kaptin's Hat); space-marines/SPACE_WOLVES.md:40 (Hunter's Guile), :51 (Chariots of the Storm); space-marines/RULES.md:731 (Cyber-familiar); space-marines/wahapedia/Datasheets_abilities.csv:862 (Strategium Command); custodes/RULES.md:150 (Castellan's Mark).
- Redeploying uses the normal deployment rules, including Infiltrators (40k_11th_edition_errata_faq_commentary.md:248).
- **AI today (none):** _decide_redeployment always ends the phase or skips ('AI keeps position', AIDecisionMaker.gd:5799-5825).
- **Engine support:** Reuse _decide_deployment's terrain and role scoring (:5055-5797), _apply_counter_deployment (:5421) and the reserves scorer (:4905).
New: a redeploy evaluator that compares the current spot with the best counter-deployment spot or reserves.
- **Value (low):** Only armies with these enhancements can do it, but for them it is a strong counter-deployment tool that the AI never uses.
- **Evidence:**
  - .llm/codex_11e_wahapedia/orks/RULES.md:208; space-marines/SPACE_WOLVES.md:40, 51; custodes/RULES.md:150
  - 40k_11th_edition_errata_faq_commentary.md:248
  - 40k/scripts/AIDecisionMaker.gd:5799-5825 (always skip)
  - YouTube Deploy on the Line 40K gZWxrJy66nw @12:00 — “there's no reason to put anything in reserve because I have redeploy” [F013]
- **Found by:** factions

#### ADJ-32 — Hold Scouts in reserve and set them up in your zone after seeing the enemy deployment

The first Scouts option: a Scouts unit placed in strategic reserves can, in the Resolve Pre-battle Abilities step, be set up anywhere wholly within your deployment zone. That makes it the last deployment drop, after the opponent has finished deploying, and with the first-turn player known. Use it to counter-deploy against the side they loaded, to screen, or to put a unit exactly where the opponent's alpha strike can't reach.

- **When:** During Declare Battle Formations, the army has Scouts units it can afford to place in reserve (within the 50% cap), and counter-deployment matters: the opponent deploys second, or has asymmetric threats.
- **Units:** Units with Scouts X″.
- **Move type:** Set-up from strategic reserves under 24.31. Adjacent: pre-battle.
- **11e rules (corrected):** - 24.31: if the unit is in strategic reserves, set it up anywhere wholly within your deployment zone (40k_11th_edition_core_rules.txt:3859-3880).
- 20.01: the 50% cap applies at the formations step (:3205-3216).
- FAQ: pre-battle rules alternate (40k_11th_edition_errata_faq_commentary.md:696-697).
- Engine: SCOUT_RESERVES_DEPLOY (ScoutPhase.gd:151, 172, 837); delta audit row 24.31/24.32 (windowed scenario iss067_scout_reserves_deploy_11e).
  - _Errata check:_ The set-up comes after deployment with the first-turn player known, but pre-battle rules alternate starting with the first-turn player, so the opponent's scout moves and other pre-battle rules can still answer it. It is the last placement only if they have none left to resolve after it. — FAQ, Scouts: players alternate pre-battle rules starting with the first-turn player (errata_faq:696-697)
- **AI today (none):** SCOUT_RESERVES_DEPLOY is never emitted: _decide_scout (AIDecisionMaker.gd:5831-5918) handles only CONFIRM, BEGIN and SKIP scout moves. _evaluate_reserves_declarations (:4737) never reserves Scouts units for this purpose.
- **Engine support:** Reuse the deployment-role scoring (:5594) and counter-deployment (:5421).
New:
- A formations-step choice that reserves Scouts units for a late drop.
- A Scout-phase placement that emits SCOUT_RESERVES_DEPLOY.
- **Value (low):** A free information edge for armies with Scouts. It is niche, and the on-table scout move usually matters more.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:3859-3880
  - 40k/phases/ScoutPhase.gd:151, 172, 837
  - docs/rules/11th_edition_delta_audit.md:199 (reserves-to-DZ option has a player UI)
- **Found by:** factions, core-rules, web, first-principles

#### ADJ-37 — Place emergency-disembarked passengers where they survive

When your loaded transport is destroyed, each passenger makes a hazard roll. Each model is set up wholly within 6″ of the transport and as close as possible to it. Under the errata, a model that can't be placed unengaged may be set up engaged; models that still can't be placed are destroyed. The unit is then battle-shocked: its OC is '-', it can't be targeted by stratagems or start actions, and it can't charge this turn.
Within 'as close as possible' you still choose which side of the hull. Pick the side in cover or a terrain area, out of the killers' line of sight, toward next turn's objective, and away from enemy melee. The Deadly Demise roll (on a 6, mortal wounds to every unit within 6″) comes after the disembark and can't be avoided at that distance.

- **When:** Whenever a loaded transport is destroyed, in any phase.
- **Units:** Embarked units.
- **Move type:** Emergency disembark move (18.05), forced. Adjacent: any phase.
- **11e rules (corrected):** - 18.05 emergency disembark (40k_11th_edition_core_rules.txt:3061-3078), with the errata's engaged fallback (40k_11th_edition_errata_faq_commentary.md:609).
- 01.07 battle-shock: OC '-', no stratagems, no actions (:197-221).
- 24.08 Deadly Demise: resolved after emergency disembarks, against units within 6″ (:3670-3699).
- FAQ: an emergency disembark counts as disembarking (errata_faq:630-631).
- Corrections: core-rules#109's 'keep clear of the Deadly Demise blast' is impossible at that distance. 'Choose objective range' gives no OC this turn, because the unit is battle-shocked.
- **AI today (none):** Placement is automatic for every owner, so no AI or player choice exists:
- RulesEngine._emergency_disembark_placements (RulesEngine.gd:17300; via resolve_transport_destruction :17238, called from ShootingPhase.gd:403 and FightPhase.gd:491) searches a 0.5″ grid nearest-first, outside engagement range, keeping coherency, and destroys models that can't be placed.
- The older TransportManager.resolve_transport_destroyed path places a ring around the hull (TransportManager.gd:677-694).
Neither implements the errata's engaged fallback.
- **Engine support:** Reuse _emergency_disembark_placements as the legal-candidate generator, plus TerrainManager.area_at (:847), model_visible_11e (:1209) and _evaluate_position_threat (:28794).
New:
- A side-of-hull scorer, with the choice exposed to AI and human owners.
- The errata's engaged fallback.
- **Value (low):** Rare and tightly constrained. The main win is cover and line of sight for the battle-shocked survivors.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:3061-3078, 3670-3699
  - 40k_11th_edition_errata_faq_commentary.md:609
  - 40k/scripts/rules/movetypes/EmergencyDisembarkMove.gd:1-6
  - docs/CORE_RULES_REMEDIATION_2026-10.md:87-98 (P1-4: nearest-first grid placement)
  - 40k/autoloads/RulesEngine.gd:17238, 17300 (_emergency_disembark_placements); 40k/autoloads/TransportManager.gd:677-694 (legacy ring placement)
- **Found by:** core-rules, first-principles

#### ADJ-30 — Pull an idle or stranded unit into reserves to re-drop where it matters (reposition)

The extraction rules in ADJ-26, and Grey Knights-style teleports, can also move a unit that is far from every objective and fight to a new arrival point next turn. They can also reset a unit for buffs that apply when it arrives (Meteoric Descent, Deff from Above, FURY OF THE EMPEROR). Weigh the OC and the turn of board presence it gives up: under Take and Hold this is costly (F027).

- **When:** The unit is unengaged, holds nothing, and is 15″ or more from useful objectives or fights. A legal arrival spot near a valuable objective or target will exist next turn, and it is before round 5.
- **Units:** The same units as ADJ-26.
- **Move type:** Repositioned to strategic reserves (20.02), then an ingress move (20.04). Adjacent.
- **11e rules (verified):** - 20.02 (40k_11th_edition_core_rules.txt:3219-3245); 20.03 exemption (:3276-3283).
- FAQ: in-battle reserves may exceed 50% (40k_11th_edition_errata_faq_commentary.md:662-665). End-of-battle destruction (errata_faq:673).
- .llm/codex_11e_wahapedia/RULINGS.md:72 (On Gilded Wings).
- **AI today (partial):** What exists:
- From Golden Light's reposition branch fires when the unit is more than 15″ from every objective in rounds 1-3 (AIDecisionMaker.gd:22532-22534).
- TACTICAL WITHDRAWAL, CO-ORDINATED STRIKE and GUNSHIP EXTRACTION score 2.1, and Echo of the Ravenspire 1.5, when no enemy is within 12″, the unit is off objectives, and it is before round 5 (SMCodexAMovement.gd:298-305; SWCodexMovement.gd:175-183; SMCodexBAction.gd:279-285; SMAbilitiesC.gd:1922-1927).
- Kunnin' Infiltrator, Aerial Manoover, Da Jump and Take Wing score 0.0 (OrkAbilities11e.gd:2325-2330; CustodesAbilities.gd:1329-1330).
Nothing checks where the unit could arrive, or which arrival buffs it would gain.
- **Engine support:** Reuse _compute_reinforcement_positions (:8019) and _score_reserves_deployment (:7949) to value next turn's arrival.
New: a value comparison of staying vs re-dropping in the shared extraction scorer (ADJ-26).
- **Value (low):** Occasionally strong (arrival buffs, stranded units), but it gives up OC and tempo. Partly covered.
- **Evidence:**
  - YouTube Warpbane Tactics veM7sLjtdIw @01:00 — “Picking a unit up is incredibly useful, but under Take and Hold, that decision becomes more costly” [F027]
  - 40k/scripts/AIDecisionMaker.gd:22496-22536 (From Golden Light reposition branch)
  - 40k/scripts/codex/space_wolves/SWCodexMovement.gd:175-183; 40k/scripts/codex/space_marines/SMCodexBAction.gd:279-285
- **Found by:** factions, first-principles

#### ADJ-33 — Shoot, then step onto an objective (post-shooting move)

Some moves after shooting must end in objective range: GRAB IT (Wreckas: a 6″ normal move, no charge afterwards) and PURGATION PUSH (Gravis Linebreaker: 5″). Execute and Redeploy (Phobos, 6″) and the free D6″ moves of ADJ-24 also allow it. The unit shoots from where it stands and still adds OC at the end-of-phase and end-of-turn checks. Weigh the lost charge.

- **When:** The unit has shot, an objective is within the move, and the OC is worth more than the charge it gives up.
- **Units:** Breaka Boyz, Flash Gitz, Tankbustas (GRAB IT); Gravis units (PURGATION PUSH); Phobos units.
- **Move type:** Normal move (09.05) granted after shooting. Adjacent: your own Shooting phase.
- **11e rules (verified):** - GRAB IT: .llm/codex_11e_wahapedia/orks/RULES.md:212. PURGATION PUSH: space-marines/RULES.md:681. Execute and Redeploy: :622.
- 09.05 (40k_11th_edition_core_rules.txt:1390-1399). 14.02 (:2401-2423).
- **AI today (partial):** What exists:
- GRAB IT is scored when an objective is reachable and no charge is forfeited (OrkCodexShootingReactive.gd:669-690).
- PURGATION PUSH scores 2.2 when the gap is 5″ or less (SMCodexBAction.gd:292-294).
- Execute and Redeploy is used when its 6″ reaches an objective (SMDetachmentsA.gd:1056-1058).
- The solver translates the unit to the nearest reachable objective (ReactiveMove11e.gd:318-358).
Missing: the free D6″ moves (Purgation Run, Mobile Hunter, Tactical Fluidity, Shadow Masters' move) are never used for this. They score 0.0, or the AI picks the other option.
- **Engine support:** Already reusable. To extend it, route the free post-shooting moves through the same objective check, and choose the objective by value (_estimate_objective_vp_value :22928).
- **Value (low):** Mostly covered. The remaining gain is extending it to the free post-shooting moves.
- **Evidence:**
  - .llm/codex_11e_wahapedia/orks/RULES.md:212; space-marines/RULES.md:622, 681
  - 40k/scripts/stratagems/ork_codex/OrkCodexShootingReactive.gd:669-690; 40k/scripts/codex/space_marines/SMCodexBAction.gd:292-294; 40k/scripts/codex/space_marines/SMDetachmentsA.gd:1056-1058
  - 40k/scripts/rules/ReactiveMove11e.gd:318-358
- **Found by:** factions, core-rules

#### ADJ-34 — Move again at the end of the Fight phase: leave a losing fight or reposition

Some end-of-Fight rules give a second move:
- WIND-SWIFT EVASION (Stormlance Mounted units that were eligible to fight): a normal move if unengaged, a fall-back move if engaged.
- Sweeping Advance (Shield-Captain on Dawneagle Jetbike, once per battle): the same split.
- Tactical Fluidity (Captain in Phobos Armour): if engaged at the end of the opponent's Fight phase, a 6″ fall-back.
- EMPEROR'S DOMAIN (Trusted Sentinels): Objective Consolidation even while engaged, to step out of combat onto an objective.
Use them to leave a fight you're losing, reach the next objective, or get out of next turn's charges and shooting.

- **When:** At the end of any Fight phase in which the unit was eligible to fight, when a better position exists within M (normal move) or the fight isn't worth staying in.
- **Units:** AA Mounted (Stormlance), Shield-Captain on Dawneagle Jetbike, Captain in Phobos Armour, Trusted Sentinels.
- **Move type:** Normal or fall-back move (09.05 / 09.07), or Objective consolidation (12.08) via a rule. Adjacent: end of a Fight phase.
- **11e rules (verified):** - Rule texts: WIND-SWIFT EVASION (.llm/codex_11e_wahapedia/space-marines/RULES.md:283), Sweeping Advance (custodes/wahapedia/Datasheets_abilities.csv:41), Tactical Fluidity (space-marines/wahapedia/Datasheets_abilities.csv:557; RULINGS.md:420), EMPEROR'S DOMAIN (custodes/RULES.md:168).
- 09.07 fall-back (40k_11th_edition_core_rules.txt:1417-1442). 12.08 (:1942-1989).
- **AI today (partial):** What exists:
- WIND-SWIFT EVASION scores 2.1 to leave a fight against a higher-points foe, or to reach an objective (SMCodexAMovement.gd:279-288; solver :754-811).
- Sweeping Advance is always taken via _compute_sweeping_advance_action (AIDecisionMaker.gd:20563-20569, :28996-29078). Each model moves straight away from its nearest enemy model if engaged, or straight to the nearest objective if not, with no collision, terrain or coherency planning.
- EMPEROR'S DOMAIN scores 1.6 when the unit is engaged within 6″ of an uncontrolled objective (CustodesCodexFight.gd:318-327; mode override AIDecisionMaker.gd:21761-21766).
- Tactical Fluidity scores 0.0 (SMAbilitiesB.gd:1827-1828).
- **Engine support:** Reuse _compute_fall_back_destinations (:12185), the movement destination pipeline (_compute_movement_toward_target :14212) instead of straight per-model lines, and _evaluate_position_threat (:28794).
New: a shared post-fight reposition scorer.
- **Value (low):** Few units have these rules, and part of the logic exists.
- **Evidence:**
  - .llm/codex_11e_wahapedia/space-marines/RULES.md:283; custodes/RULES.md:168; custodes/wahapedia/Datasheets_abilities.csv:41
  - 40k/scripts/codex/space_marines/SMCodexAMovement.gd:279-288, 754-811; 40k/scripts/AIDecisionMaker.gd:20563-20569, 28996-29078; 40k/scripts/codex/custodes/CustodesCodexFight.gd:318-327
- **Found by:** factions

#### ADJ-35 — Re-embark outside your Movement phase for protection or redelivery

KEEP IT RUNNIN' (Blitz Brigade) and DUTY IS NEVER DONE (Gauntlet: an unengaged AA Infantry unit that was eligible to fight, wholly within 6″ of a TRANSPORT) let a unit embark at the end of the Fight phase. It is then safe from the next turn's shooting and ready to be driven to the next objective.
By RAW, 18.02 also lets a unit embark after any normal move: it has no phase restriction, and the moving player is the active player. So a reactive normal move ending within 3″ of a transport could embark. No local FAQ confirms this, and the engine's reactive-move path never offers embarking.

- **When:** The unit has no fight left, a transport with capacity is within 6″ (stratagems) or 3″ (embark), and the unit isn't holding an objective needed at the next check.
- **Units:** Ork Infantry near a Trukk or Battlewagon (KEEP IT RUNNIN'), AA Infantry near a TRANSPORT (DUTY IS NEVER DONE), reactive-move units near a transport.
- **Move type:** Embark (18.02) granted at the end of the Fight phase, or after a reactive normal move. Adjacent.
- **11e rules (corrected):** - 18.02 embarking: after a normal, advance or fall-back move; every model within 3″; not set up this turn; capacity available (40k_11th_edition_core_rules.txt:2981-2996).
- 01.03 (:137-158).
- FAQ: a rule letting a unit embark in a turn it disembarked overrides the core restriction (40k_11th_edition_errata_faq_commentary.md:621-622).
- Rule texts: DUTY IS NEVER DONE (.llm/codex_11e_wahapedia/space-marines/RULES.md:613), KEEP IT RUNNIN' (orks/RULES.md:201).
- The reactive-move embark is my reading of the RAW and is unconfirmed.
  - _Errata check:_ KEEP IT RUNNIN' and DUTY IS NEVER DONE only change the timing and distance; the unit must still meet the other 18.02 conditions (capacity, datasheet eligibility, not set up on the battlefield this turn). So a unit that disembarked or arrived this turn can't re-embark with them, since neither rule says it may embark in a turn it disembarked. — Commentary 18.02.01 Able To Embark (errata_faq:626); FAQ 18.02 (errata_faq:621-622)
- **AI today (partial):** What exists:
- DUTY IS NEVER DONE scores 2.0 when no enemy is within 9″ and the unit is off objectives (SMCodexAMovement.gd:292-294).
- KEEP IT RUNNIN' scores 2.5 with an enemy within 12″ and no objective held, else 0.5 (OrkCodexFight.gd:270-271, :990-1002).
What the AI never does:
- It never emits EMBARK_UNIT in play, because MovementPhase._check_embark_opportunity skips AI players (MovementPhase.gd:8306-8311).
- The reactive-move confirm path returns before the embark check (MovementPhase.gd:3803-3825).
- **Engine support:** Reuse TransportManager.is_unit_within_embark_range / can_embark (TransportManager.gd:107, 173) and _estimate_incoming_melee_damage (:12350).
New:
- An embark-value scorer (damage avoided plus next-turn delivery value, minus OC lost).
- Engine support for embarking after reactive moves, if the RAW reading is accepted.
- **Value (low):** Situational, and limited to a few detachments.
- **Evidence:**
  - .llm/codex_11e_wahapedia/space-marines/RULES.md:613; orks/RULES.md:201
  - 40k_11th_edition_core_rules.txt:2981-2996
  - 40k/scripts/codex/space_marines/SMCodexAMovement.gd:292-294; 40k/scripts/stratagems/ork_codex/OrkCodexFight.gd:270-271, 990-1002
  - 40k/phases/MovementPhase.gd:3803-3825, 8306-8311
- **Found by:** factions

#### ADJ-36 — Use rule-granted surge moves on your terms (and pre-position so the closest enemy is the right target)

Surge moves include IMPETUOSITY (Blood Claws, Thunderwolf Cavalry and Wulfen, after being shot), GOADED INTO ACTION (Beast Snagga, after losing a wound to shooting), Vengeful Surge (Custodes, D6+2″), Bestial Rage (D6+1″) and Glory of Ultramar. They have fixed rules:
- They go toward the CLOSEST enemy unit.
- They must end engaged with it if possible, otherwise as close as possible.
- They can't end engaged with any other unit.
- The unit must be unengaged, not battle-shocked, and not have moved this phase.
Because the target is forced, decide in your own Movement phase which enemy will be closest to your surge-capable units. Decline the surge when the closest enemy is a fight you lose, or when it drags you off an objective. AIRCRAFT are ignored as 'closest' unless the surging unit can FLY.

- **When:** A surge trigger fires and the closest enemy is a target you want. Plan ahead in your own Movement phase.
- **Units:** Blood Claws, Thunderwolf Cavalry and Wulfen (IMPETUOSITY), Beast Snagga (GOADED INTO ACTION), Custodes with Vengeful Surge, Fenrisian Wolves (Bestial Rage), Ultramarines (Glory of Ultramar). No shipped datasheet carries 'Surge X″'.
- **Move type:** Surge move (21.02). Adjacent: usually the opponent's Shooting phase.
- **11e rules (verified):** - 21.01-21.02 surge move (40k_11th_edition_core_rules.txt:3297-3325).
- 23.02: AIRCRAFT are ignored when finding the closest unit unless the surging unit can FLY (:3512-3515).
- Rule texts: IMPETUOSITY (.llm/codex_11e_wahapedia/space-marines/SPACE_WOLVES.md:45), GOADED INTO ACTION (orks/RULES.md:111), Bestial Rage (RULINGS.md:321).
- Engine: SurgeMove.gd:1-33; RulesEngine.get_surge_move_inches (RulesEngine.gd:9865). BEGIN_SURGE_MOVE is offered for 'Surge X' datasheets (MovementPhase.gd:8043), and none ship (docs/rules/11th_edition_doc_change_audit.md:188, 292).
- **AI today (partial):** What exists:
- IMPETUOSITY and GOADED INTO ACTION score 2.5 when the closest enemy is within 6″ and the unit has melee weapons (SWCodexMovement.gd:160-163; OrkCodexShootingReactive.gd:768-780).
- Vengeful Surge always scores 2.0 (CustodesAbilities.gd:1325-1326).
- Bestial Rage and Predatory Instinct score 0.0 (SWAbilities11e.gd:1839-1840). Glory of Ultramar scores 0.0 (SMAbilitiesC.gd:1930-1931).
- Placement is the engine's surge solver (ReactiveMove11e.gd:365+).
Missing: no check of who the closest enemy is or how dangerous its melee is, no objective cost, and no own-turn pre-positioning. BEGIN_SURGE_MOVE is never emitted (AIDecisionMaker.gd:6831).
- **Engine support:** Reuse SurgeMove.before_moving (SurgeMove.gd:41) to identify the forced target, _estimate_melee_damage (:19576) and _estimate_incoming_melee_damage (:12350).
New:
- A surge-target quality check in the codex scores.
- A 'closest enemy to my surge units' term in Movement-phase scoring.
- **Value (low):** Few units have surges, and the move itself is fixed by the rules. The gains are in declining bad surges and pre-positioning.
- **Evidence:**
  - 40k_11th_edition_core_rules.txt:3297-3352
  - 40k/scripts/rules/movetypes/SurgeMove.gd:1-33; 40k/scripts/codex/custodes/CustodesAbilities.gd:834
  - docs/rules/11th_edition_doc_change_audit.md:188 (no shipped datasheet carries Surge yet)
  - 40k/scripts/codex/space_wolves/SWCodexMovement.gd:160-163; 40k/scripts/stratagems/ork_codex/OrkCodexShootingReactive.gd:768-780
- **Found by:** core-rules, web, first-principles, factions


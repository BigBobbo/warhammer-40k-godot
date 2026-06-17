import html, datetime

# ---------- DATA (from the 4 verified audit agents + first-hand checks) ----------
# status: done / partial / gap / nodelta / unverified
# delta catalog rows: (code, title, what_10e, what_11e, status, evidence)
deltas = [
# CORE / SEQUENCE (01-09)
("03.03","Coherency","within 2\" of ≥1 model; 7+ units need 2 neighbours; no separation cap","2\"H/5\"V of ≥1 AND within 9\"H/5\"V of EVERY other model; 7+ rule removed","done","AttackSequence.check_unit_coherency 229-249; coherency_envelope_inches()=9.0; end-of-turn removal hook (ISS-042)"),
("03.04","Engagement range","1\" horizontal / 5\" vertical","2\" horizontal / 5\" vertical","done","GameConstants.engagement_range_inches() 27-28; consumed across RulesEngine (ISS-039)"),
("04.03","Resolve Attacks — gather identical attacks","dice gathered per weapon, no pooling box","weapons making identical attacks at one target gather & resolve together","done","AttackSequence.gather_identical_attacks; pg-20 example reproduces (ISS-041)"),
("05.03","Save Rolls — allocation groups","one model at a time, wounded first","defender forms groups, declares an allocation ORDER under 3 constraints","done","Allocation.build_groups/validate_order; AllocationGroupOverlay UI (ISS-041/045, scenario 31/31)"),
("05.04","Inflict Damage — lowest→highest","resolve per model","resolve saves lowest→highest, current-group walk, excess lost on death","done","Allocation.apply_save_rolls; Celestine example reproduces (ISS-041)"),
("06.02","Mortal Wounds — selection priority","allocate like normal damage","explicit 4-tier select-model priority; normal damage before MW","done","Allocation.select_mortal_wound_target / apply_mortal_wounds_11e (ISS-046)"),
("06.03","Hazard Rolls","HAZARDOUS test, 1 = MW (3 for M/V)","generalised hazard primitive 1-2 fail; reused by Desperate Escape","done","AttackSequence.hazard_rolls (ISS-044)"),
("08.03","Battle-shock step","clear at start; only below-half tests; no recovery","shock persists; tests if shocked OR at-or-below half; passing recovers","done","Recovery + shocked-trigger + at-or-below-half all wired: GameState.is_at_half_strength(_combined) (exact-half + odd-strength caveat); CommandPhase passes at_half into battleshock_test_required (ISS-065)"),
("09.06","Advance move","advance roll+M; can't charge; ASSAULT only","+ not eligible to start an action until end of turn","done","AdvanceMove.after_moving_effects 41-43 (cannot_start_action); wired MovementPhase 4628-4634"),
("09.07","Fall-back move — modes","single mode; per-model desperate-escape only when crossing enemies","Ordered Retreat vs Desperate Escape (hazard per model; may cross enemies; follow-up battle-shock)","done","11e modes/hazards/follow-up via FallBackMove (33-85, wired 4023-4046); the legacy 10e _process_desperate_escape is now gated to edition < 11 so hazards apply exactly once at 11e (ISS-064)"),
# SHOOTING / CHARGE / FIGHT (10-12)
("10.02","Shoot — select shooting type","no shooting-type sub-step","new 'Select Shooting Type' step (normal/assault/close-quarters/indirect)","done","ShootingTypes registry; ShootingPhase wires at ed≥11 (558-564,751-764) (ISS-048)"),
("10.05","Assault shooting","weapon-level only (advanced units shoot ASSAULT)","a selectable TYPE; only [ASSAULT] weapons usable","done","AssaultShooting.gd 12-31"),
("10.06","Close-Quarters shooting","PISTOL + Big-Guns handled ad-hoc","a selectable type; engaged-target rules; non-M/V limited to CQ weapons; M/V −1","done","CloseQuartersShooting.gd 17-69; ModifierStack 135-148"),
("10.07","Indirect shooting","weapon-level (−1, cover)","a selectable type; per-attack cover, no hit re-rolls, 1-5 fail (1-3 w/ spotter)","done","IndirectShooting.gd 31-65"),
("11.02","Charge — declare/targets","targets chosen at declare, then roll","targets selected AFTER 2D6 roll: within 12\" AND within rolled distance","done","ChargeMove11e 42-48; ChargePhase ed≥11 (317,395-401,570-583) (ISS-049)"),
("11.04","Charge move","end within ER of a target","end engaged with EVERY target, NO non-target enemy; each model gains Fights First ABILITY","done","ChargeMove11e.after_moving_conditions/effects 55-82"),
("12.02/03","Pile-in move","3\" toward nearest enemy model","global step (active first); targets = engaged enemies else within 5\"; base-contact locked","done","FightPhase._validate_pile_in branches to _validate_pile_in_11e at edition≥11, driving the real PileInMove template (5\" target select, base-contact lock) (ISS-066)"),
("12.04-06","Fight types / sequencer","alternate; charging units fight first","Fights-First then Remaining steps w/ pass rules & return-to-FF; Overrun fight","done","FightSequencer.gd 33-141; FightPhase consults it at ed≥11 (573-582,1223) (ISS-050)"),
("12.07/08","Consolidation — modes","3\" toward nearest enemy / objective","3 mandatory modes: Ongoing / Engaging (forces those enemies to fight!) / Objective","done","FightPhase._validate_consolidate branches to _validate_consolidate_11e at edition≥11, driving the real ConsolidationMove template (Ongoing / Engaging / Objective) (ISS-066)"),
# TERRAIN / OBJECTIVES (13-14)
("13.06","Terrain & movement","simpler traversal","per-keyword dense traversal; ≤2\" (≤4\" SUPER-HEAVY WALKER) else vertical; MOBILE","done","TerrainManager.can_move_through_11e; wired into MovementPhase._validate_set_model_dest at ed≥11 (ISS-054, windowed)"),
("13.08","Benefit of cover","cover improves the SAVE by 1","cover WORSENS the attack's BS by 1 (no save bonus) — headline change","done","TerrainManager.unit_has_cover_11e 1014-1044; ModifierStack 91-112 (ISS-053)"),
("13.09","Hidden","did not exist","INF/BEAST/SWARM in dense area (not shot recently) visible only within 15\" detection","done","TerrainManager.is_model_hidden/hidden_model_visible_to 852-880; consumed RulesEngine 4416-4420 (ISS-052)"),
("13.10","Obscuring","obscuring-trait / tall blocks LoS","light/dense areas obscuring; blocked if EVERY line crosses one neither model is in","done","TerrainManager._visibility_lines_11e/model_visible_11e 911-953 (ISS-052)"),
("13.11","Solid","not formalised","dense features Solid: LoS can't cross enclosed gaps ≤3\" from ground","done","TerrainManager._line_blocked_11e ground-level dense block 918-934 (ISS-052)"),
("14.01","Terrain objectives","objective = point; control within 3\" of marker","objective = a terrain AREA; in range while WITHIN the area","done","MissionManager._check_objective_control 278-309 (area_at + point-in-polygon) (ISS-055)"),
("14.03","Secured objectives","objective-secured sticky","secured stays controlled with no units until opponent control is greater","done","MissionManager secured API 91-105,325-350 (ISS-055)"),
# STRATAGEMS / ACTIONS / M&V / TRANSPORT / ATTACHED / RESERVES / FLY (15-23)
("15.01","Using stratagems","same stratagem once/phase","+ cannot target the SAME unit with >1 stratagem per phase","done","StratagemManager 669-678 (ISS-056)"),
("15.02","Command Re-roll","re-roll a roll","re-roll ONE die only; charge rolls re-rolled in full","done","StratagemManager 2666-2674"),
("15.05","Explosives","'Grenade' stratagem","renamed; EXPLOSIVES/GRENADES keyword; 6D6, 4+ = MW","done","StratagemManager 2693-2702; RulesEngine.resolve_explosives_11e 2451-2467"),
("15.06","Crushing Impact","'Tank Shock' (different)","NEW ram: roll T dice, 1=self MW, 5+=enemy MW (max 6)","done","StratagemManager 2703-2711; RulesEngine.resolve_crushing_impact_11e 2473-2501"),
("15.08","Fire Overwatch","hit on 6s","grants Snap Shooting type; excl. TITANIC; once/turn","done","StratagemManager 2721-2729"),
("15.09","Snap Shooting","did not exist","NEW type: 1 target ≤24\", unmodified 6 hits, no re-rolls","done","ShootingTypes registers SnapShooting (rule-granted)"),
("15.11","Heroic Intervention","move D6\" toward charger","REWORKED: a real charge (11.02) w/ Leap-to-Defend / Into-the-Fray modes","done","StratagemManager 2739-2748"),
("15.12","Counteroffensive","1CP, Fights First","2CP; Fights First + must be next selection","done","StratagemManager 2749-2757"),
("15.x","10e core set retirement","10e core active","reworked 10e core entries retired at 11e","done","StratagemManager 2758-2763 (edition_max:10 on 12 ids)"),
("16.01","Performing Actions","10e action gates","full 11e eligibility gates + start-locks (no shoot/charge)","done","ActionsManager.gd; locks consumed by 11e shooting/charge templates; turn-ending completion hook (ISS-057)"),
("17.03","Shooting at engaged M/V (was Big Guns Never Tire)","M/V shooter fires non-pistol while engaged at −1","BGNT retired; engaged M/V TARGET shot at −1 (except CQ from engaged unit)","done","10e BGNT gated off (RulesEngine 1680,2980); 11e via ModifierStack 135-148"),
("18.02","Embarking","within 3\" after a move","+ unit not set up on the battlefield this turn","done","TransportManager.can_embark 61 (ISS-058)"),
("18.04","Disembark — modes","single mode (3\"; shock if transport advanced)","NEW 3 modes: Rapid / Tactical / Combat (6\", hazard, shock); advanced transport bars disembark","done","DisembarkMove.gd 38-97; wired CONFIRM_DISEMBARK ed≥11 (ISS-058, windowed)"),
("18.05","Emergency disembark","6\"; un-placeable die","+ per-model hazard roll + battle-shock","done","EmergencyDisembarkMove.gd; TransportManager 357-484 (ISS-058)"),
("19.01","Forming attached units","Leader only; one per bodyguard","adds SUPPORT; one LEADER and one SUPPORT per bodyguard","done","CharacterAttachmentManager 82-106 (ISS-059)"),
("19.03","Keywords in attached units","union","codified union; drives ANTI-[KEYWORD]","done","CharacterAttachmentManager.attached_unit_keywords 113; pg-67 ANTI-PSYKER reproduces (ISS-059)"),
("19.04","Abilities in attached units","unit abilities apply until source dies","source-expiry matrix w/ until-attacks-resolved grace","partial","Keyword/crit expiry on death works; full effect-FLAG source-expiry deferred to ISS-027"),
("20.04","Ingress move","wholly within 6\" edge, >9\" from enemies",">8\" from enemies; no opp DZ before round 3; no further move until Charge (can charge)","done","IngressMove.gd 38-90; PLACE_REINFORCEMENT ed≥11 (ISS-060, windowed)"),
("21.02","Surge move","did not exist as core","NEW triggered move toward closest enemy; must engage surge target","done","SurgeMove.gd 1-83 (ISS-061)"),
("21.03","Flying — take to the skies","FLY ignored vertical / moved through models","opt-in per move: −2\" max distance (0 with HOVER), ignore vertical, move through all","done","MoveType.take_to_skies_modifier 95-103; live in BEGIN_NORMAL/ADVANCE/FALL_BACK (ISS-061, windowed)"),
("22.05","Plunging Fire","did not exist","NEW +1 BS if attacker ≥3\" elevation or TOWERING within 12\", vs ground targets","done","ModifierStack 114-124 (ISS-053)"),
("23.01/02/03","Aircraft reserve cycle","10e zoom/hover movement","AIRCRAFT must start in reserves; ingress-only; return to reserves each opp turn","done","GameState.unit_must_start_in_reserves + return_aircraft_to_reserves; DeploymentPhase rejects on-board AIRCRAFT; TurnManager MORALE hook runs the end-of-turn return. Edition+keyword gated, inert without aircraft data (ISS-074)"),
# ABILITY GLOSSARY (24.xx) — deltas only
("24.01","[ABILITIES] keyword scoping","plain bracket abilities","trailing keyword scopes ability to matching targets ([LETHAL HITS: VEHICLE])","done","RulesEngine.get_weapon_ability_scope + has_* helpers now take target_unit; scoped abilities checked against the target's keywords across all 16 resolution call sites. Unscoped data unchanged (ISS-070)"),
("24.02","Duplicated abilities","—","same ability not cumulative; pick one instance","done","AbilityRegistry.from_weapon collapses duplicate ids keeping the highest numeric param; get_sustained_hits_value takes the highest instance, never the sum (ISS-072)"),
("24.05","[BLAST X]","+1 die per 5 models","+ [BLAST X] variant adds X per 5","done","AbilityRegistry.blast_bonus_dice 267; BLAST 2 vs 12 = +4 tested"),
("24.06","[CLEAVE X]","did not exist","NEW: like BLAST but only vs a single all-attacks target","done","AbilityRegistry.cleave_bonus_dice 274; CLEAVE 1 vs 16 = +3 tested"),
("24.07","[CLOSE-QUARTERS]","[PISTOL]","NEW keyword supersedes PISTOL","done","CloseQuartersShooting.gd; PISTOL→CQ map (ISS-048)"),
("24.09","Deep Strike","set up >9\" from enemies","set up >8\" horizontally; no opp DZ before round 3","done","IngressMove 47 (8.0), 75 (DZ ban) (ISS-060)"),
("24.10","[DEVASTATING WOUNDS]","crit wound → damage as mortals (no save)","crit ENDS the sequence; MW = weapon D; 1 model/crit, excess lost","done","Allocation.apply_devastating_wounds_11e 317; pg-80 example reproduces (ISS-046)"),
("24.14","Firing Deck","select X embarked models","+ exclude [ONE SHOT]; one ranged weapon per model","done","FiringDeckDialog._populate_available_weapons uses get_unit_weapons, excludes [ONE SHOT] via is_one_shot_weapon, and enforces one ranged weapon per model (ISS-071)"),
("24.16","[HEAVY]","+1 to hit if Remained Stationary","+1 to hit in YOUR Shooting phase: unengaged, not set up this turn, moved ≤3\"","done","ModifierStack.heavy_applies_11e 150-169 (ISS-016)"),
("24.17","HOVER","FLY ignored vertical","when taking to the skies, no −2\" penalty","done","MoveType.take_to_skies_modifier (0 with HOVER) (ISS-061)"),
("24.20","Infiltrators","deploy >9\" from enemy DZ & models","deploy >8\" HORIZONTALLY from enemy DZ & all enemy units","done","DeploymentPhase._validate_infiltrators_position uses infiltrate_min = 8.0 at ed≥11 (else 9.0) across all 6 sites (ISS-068)"),
("24.22/34","Leader / Support","Leader only","NEW SUPPORT role parallel to Leader","done","CharacterAttachmentManager.attachment_role 86-100 (ISS-059)"),
("24.23","[LETHAL HITS]","crit hit auto-wounds (mandatory)","now a CHOICE — declining keeps crit-wound triggers","done","RulesEngine.lethal_hits_auto_wound_11e 2282 (ISS-047)"),
("24.24","Lone Operative","target only within 12\"","+ explicit [INDIRECT FIRE] clause + Lone Operative X\" variant","done","RulesEngine.get_lone_operative_range parses the 'Lone Operative X\"' variant (default 12); both targeting gates (visibility + indirect) use the parsed range, edition-gated (ISS-069)"),
("24.27","[PISTOL]","own pistol rules","now identical to [CLOSE-QUARTERS]","done","ShootingType 96 maps pistol→close_quarters (ISS-048)"),
("24.28","[PRECISION]","allocate the attack to a character","attacker makes the CHARACTER group the current allocation group","done","RulesEngine.has_precision/precision_data 2185 (ISS-047)"),
("24.29","[PSYCHIC]","no inherent rule","may ignore any/all BS/WS & hit-roll modifiers; attacks are 'psychic'","done","RulesEngine.is_psychic_weapon 1778-1785,3063-3070 (ISS-047)"),
("24.31","Scouts","wholly-in-DZ → scout move (or transport)","+ if in STRATEGIC RESERVES, set up wholly within your DZ","done","ScoutPhase adds the reserves→DZ deploy path (SCOUT_RESERVES_DEPLOY + scout_reserve_units_pending), wholly-in-own-DZ check, edition-gated (ISS-067)"),
("24.32","Scout move","after move >9\" from enemy models","after move >8\" HORIZONTALLY from enemy UNITS; eligible if wholly in DZ","done","ScoutPhase._scout_min_enemy_distance_inches = 8.0 at ed≥11 (else 9.0), horizontal from enemy units, DZ-containment precondition (ISS-067)"),
("24.35","Super-Heavy Walker","did not exist","move through models & ≤4\" terrain; optional MOBILE-grant then D6 (1 = shock)","done","≤4\" traversal (TerrainManager); begin handlers record shw_mobile from payload.shw_mobile_gamble, MOBILE passed to the 13.06 traversal, D6 at move-confirm sets battle_shocked on a 1 (ISS-073)"),
]

nodelta_24 = ["24.03 [ANTI]","24.04 [ASSAULT]","24.08 Deadly Demise","24.11 [EXTRA ATTACKS]","24.12 Feel No Pain","24.13 Fights First","24.15 [HAZARDOUS]","24.18 [IGNORES COVER]","24.19 [INDIRECT FIRE]","24.21 [LANCE]","24.25 [MELTA]","24.26 [ONE SHOT]","24.30 [RAPID FIRE]","24.33 Stealth","24.36 [SUSTAINED HITS]","24.37 [TORRENT]","24.38 [TWIN-LINKED]"]

# Session issues: (id, title, status, category)
# category: 11e / arch / infra
issues = [
("ISS-001","Route all in-game state mutations through pipeline","done","arch"),
("ISS-002","GameConstants module + edition switch","done","arch"),
("ISS-003","Structured ability schema + registry","done","arch"),
("ISS-004","Uniform per-action RNG seeding","done","arch"),
("ISS-005","PhaseControllerBase extraction","done","arch"),
("ISS-006","Remove committed artifacts from git (~165MB)","done","arch"),
("ISS-007","Guard freed-node access in cleanup","done","arch"),
("ISS-008","Standardize controller input handling","done","arch"),
("ISS-009","Replace hardcoded /root/ paths (SceneRefs chokepoint)","done","arch"),
("ISS-010","Move root status docs to docs/history","done","arch"),
("ISS-011","Triage archived/disabled tests","done","arch"),
("ISS-012","Unified AttackSequence (dedupe ranged/melee)","done","arch"),
("ISS-013","Signal registry + phase lifecycle out of Main","done","arch"),
("ISS-014","AI consumes shared rules math","done","arch"),
("ISS-015","Multiplayer: seeds on every dice action","done","arch"),
("ISS-016","Consolidated modifier stack","done","arch"),
("ISS-017","State accessors + diff-path hardening","done","arch"),
("ISS-018","Per-phase UI container teardown","todo","arch"),
("ISS-019","Unify ability checks through ability layer","done","arch"),
("ISS-020","RulesEngine public API for phases","done","arch"),
("ISS-021","Action log + deterministic replay","done","infra"),
("ISS-022","Verify/extend undo coverage","done","arch"),
("ISS-024","Eliminate stale phase snapshots (live-view)","done","arch"),
("ISS-025","TurnManager vs PhaseManager ownership; applier→GameState","done","arch"),
("ISS-026","MP load-sync failure handling","done","arch"),
("ISS-027","Main.gd remaining decomposition","todo","arch"),
("ISS-028","Save migration framework + fixtures","done","infra"),
("ISS-029","Golden-master replay harness","done","infra"),
("ISS-030","Split AIDecisionMaker into planners","todo","arch"),
("ISS-031","BoardState: merge away / document","done","arch"),
("ISS-032","AI cache save/load policy","done","arch"),
("ISS-033","Shared dialog base class","todo","arch"),
("ISS-034","Remove duplicate/legacy phases (SCOUT_MOVES/MORALE)","done","arch"),
("ISS-035","Autosave deferral (verified + hardened)","done","arch"),
("ISS-036","Disconnect grace period (verified — already implemented)","done","arch"),
("ISS-037","11e datasheet/army schema + converter","done","11e"),
("ISS-038","11e battle-round/turn structure hooks","done","11e"),
("ISS-039","Engagement range 2\"/5\"","done","11e"),
("ISS-040","11e move-type framework + MovementPhase wiring","done","11e"),
("ISS-041","11e attack core: allocation groups","done","11e"),
("ISS-042","11e coherency + end-of-turn enforcement","done","11e"),
("ISS-043","11e leadership + battle-shock rework","done","11e"),
("ISS-044","Hazard roll mechanic","done","11e"),
("ISS-045","Wound-allocation UI for groups","done","11e"),
("ISS-046","11e mortal wounds + dev-wounds cap","done","11e"),
("ISS-047","11e weapon abilities","done","11e"),
("ISS-048","11e shooting types","done","11e"),
("ISS-049","11e charge phase","done","11e"),
("ISS-050","11e fight phase restructure","done","11e"),
("ISS-051","11e terrain data model","done","11e"),
("ISS-052","11e visibility (Hidden/Obscuring/Solid)","done","11e"),
("ISS-053","Cover + Plunging Fire as BS modifiers","done","11e"),
("ISS-054","11e terrain movement + MOBILE","done","11e"),
("ISS-055","11e objectives + Secured","done","11e"),
("ISS-056","11e core stratagems + per-unit limit","done","11e"),
("ISS-057","Actions system","done","11e"),
("ISS-058","11e transports (modes, emergency)","done","11e"),
("ISS-059","11e attached units (Support, T, persistence)","done","11e"),
("ISS-060","11e reserves/ingress/aircraft","done","11e"),
("ISS-061","11e FLY/surge/hover","done","11e"),
("ISS-062","AI updated for 11e","done","11e"),
("ISS-063","11e windowed scenario suite","done","11e"),
("ISS-064","Fall-back desperate-escape single-fire at 11e (09.07)","done","11e"),
("ISS-065","Battle-shock test at exactly half-strength (08.03)","done","11e"),
("ISS-066","11e pile-in / consolidation reach the Fight phase (12.02-12.08)","done","11e"),
("ISS-067","Scouts: 8\" + strategic-reserves→DZ option (24.31/32)","done","11e"),
("ISS-068","Infiltrators deploy 8\" horizontal at 11e (24.20)","done","11e"),
("ISS-069","Lone Operative X\" variant + indirect clause (24.24)","done","11e"),
("ISS-070","Keyword-scoped weapon abilities honour the target (24.01)","done","11e"),
("ISS-071","Firing Deck excludes [ONE SHOT], one weapon/model (24.14)","done","11e"),
("ISS-072","Duplicated weapon abilities non-cumulative (24.02)","done","11e"),
("ISS-073","Super-Heavy Walker MOBILE-grant + D6 gamble (24.35)","done","11e"),
("ISS-074","Aircraft reserve cycle (23.01/23.02)","done","11e"),
("ISS-023","Single source of truth for positions","todo","arch"),
]

# Confirmed gaps surfaced by THIS audit (beyond what tracker openly deferred).
# Every CRITICAL→LOW gap below has since been fixed, validated, and committed;
# the `resolution` field records the fix + the issue id. Two INFO items remain
# open (one a tracked deferral, one unverified).
# (sev, code, title, desc, loc, resolution)
gaps = [
("CRITICAL","09.07","Fall-back desperate-escape double-fires at edition 11","The legacy 10e _process_desperate_escape runs at move-confirm with no edition guard, while the 11e FallBackMove.before_moving already rolled per-model hazards at move-begin. A battle-shocked unit falling back has hazard mortal wounds applied twice.","MovementPhase.gd:4596","FIXED (ISS-064): legacy desperate-escape gated to edition < 11; the 11e template owns the single hazard application at move-begin. Headless + windowed validation drive begin→confirm and assert the alive count does not change at confirm."),
("CRITICAL","08.03","Units at EXACTLY half-strength skip their battle-shock test","11e 08.03 reads 'at, or below, half-strength'. battleshock_test_required() has the right at_half parameter but CommandPhase passes it hardcoded false, and below_half uses a strict '<'. A unit at exactly half (5/10 models) never tests.","CommandPhase.gd:276 / GameState.gd:962","FIXED (ISS-065): GameState.is_at_half_strength(_combined) added (exact-half + odd-strength caveat); CommandPhase passes at_half into battleshock_test_required. Headless + windowed validation."),
("HIGH","12.07/08","11e consolidation modes never reach the live Fight phase","ConsolidationMove (Ongoing/Engaging/Objective, incl. engaging-consolidation forcing enemies to fight) is implemented & unit-tested but FightPhase._validate_consolidate / _determine_consolidate_mode still run legacy 10e modes with no edition branch.","FightPhase.gd:809,864","FIXED (ISS-066): _validate_consolidate branches to _validate_consolidate_11e at edition≥11, driving the real ConsolidationMove template. Validated headless against the real FightPhase validators."),
("HIGH","12.02/03","11e pile-in never reaches the live Fight phase","PileInMove (5\" target select, base-contact lock) is implemented & unit-tested but FightPhase._validate_pile_in / _process_pile_in run hardcoded legacy 3\"/closest-model logic with no edition branch.","FightPhase.gd:639,1267","FIXED (ISS-066): _validate_pile_in branches to _validate_pile_in_11e at edition≥11. Validated headless against the real FightPhase validators + existing windowed fight scenarios."),
("HIGH","24.31/32","Scouts still run 10e: wrong distance + missing reserves option","ScoutPhase uses 9.0\" straight-line (11e: >8\" horizontal from enemy UNITS), requires DEPLOYED status (rejecting the new 11e strategic-reserves→'set up wholly within your DZ' option), and has no DZ-containment precondition.","ScoutPhase.gd:15,135,215,265","FIXED (ISS-067): 8\" horizontal-from-units at ed≥11, SCOUT_RESERVES_DEPLOY reserves→DZ path with wholly-in-own-DZ check, progression includes reserves. Headless + windowed validation."),
("MEDIUM","24.20","Infiltrators deploy distance still 9\" (10e), should be 8\" horizontal","DeploymentPhase hardcodes 9.0\" for both the enemy-DZ and enemy-model checks, with no edition gate.","DeploymentPhase.gd:348,361","FIXED (ISS-068): infiltrate_min = 8.0 at ed≥11 (else 9.0) across all 6 sites. Headless boundary test + 10e sensitivity."),
("MEDIUM","24.24","Lone Operative missing the X\" variant and the [INDIRECT FIRE] clause","Code hardcodes a 12\" normal-targeting gate only; 11e adds an explicit indirect-fire restriction and a 'Lone Operative X\"' distance variant.","RulesEngine.gd:3967,4753,4857","FIXED (ISS-069): get_lone_operative_range parses the X\" variant; both targeting gates use the parsed range; has_lone_operative matches the 'Lone Operative X\"' name form. Headless validation of get_eligible_targets."),
("MEDIUM","24.01","Keyword-scoped abilities fire against all targets","The [LETHAL HITS: KEYWORD] scoping primitives exist in AbilityRegistry but the live resolution helpers take (weapon, board) with no target, so a scoped ability is never restricted to matching targets.","RulesEngine.gd:5813,5930,5997","FIXED (ISS-070): has_*/get_* helpers take target_unit and check the scope against the target's keywords; target threaded through all 16 resolution call sites. Backward-compatible for unscoped data and no-target callers."),
("MEDIUM","24.14","Firing Deck doesn't exclude [ONE SHOT] / one-weapon-per-model","Selects up to X embarked models correctly, but lists every weapon — 11e requires excluding [ONE SHOT] and one ranged weapon per selected model.","FiringDeckDialog.gd:101","FIXED (ISS-071): _populate_available_weapons rewired to get_unit_weapons, excludes [ONE SHOT], one-weapon-per-model guard. (Also fixed a pre-existing call to a non-existent method.) Headless validation drives the real dialog."),
("LOW","24.02","Duplicated-ability non-stacking not enforced","No instance-selection / non-cumulative logic exists in the resolution path.","(was unimplemented)","FIXED (ISS-072): AbilityRegistry.from_weapon collapses duplicate ids keeping the highest numeric param; get_sustained_hits_value takes the highest instance, never the sum. Headless validation."),
("LOW","24.35","Super-Heavy Walker MOBILE-grant + D6 battle-shock gamble not driven","The ≤4\" terrain traversal works; the optional 'grant all models MOBILE then roll D6, 1 = battle-shocked' is not applied by any action.","MovementPhase.gd + TerrainManager.gd","FIXED (ISS-073): begin handlers record shw_mobile from payload.shw_mobile_gamble (ed≥11 + SUPER-HEAVY WALKER); MOBILE passed to the 13.06 traversal; seeded D6 at move-confirm sets battle_shocked on a 1. 13-assertion headless test drives the real MovementPhase."),
("LOW","23.01/02","Aircraft reserve cycle absent (tracked deferral)","No forced-reserves at deployment and no return-to-reserves cycle. Openly deferred in the tracker — no aircraft datasheets exist in the current armies.","(was unimplemented)","FIXED (ISS-074): GameState forced-reserves + return-to-reserves helpers; DeploymentPhase rejects on-board AIRCRAFT; TurnManager MORALE hook runs the end-of-turn return. Edition+keyword gated → inert without aircraft data. 23-assertion headless test drives the real path."),
("INFO","19.04","Attached-unit effect-flag source-expiry matrix is partial","Keyword/crit-threshold expiry on leader death works; the full effect-flag source-expiry with the until-attacks-resolved grace is deferred to ISS-027.","CharacterAttachmentManager.gd","OPEN — deferred to ISS-027 (architecture workstream)."),
("INFO","20.02","Repositioned-units persistence rules unverified","The audit could not confirm the duration-effect persistence at a specific file:line.","(unverified)","OPEN — still unverified; flagged rather than guessed."),
]

# ---------- HTML ----------
def badge(s):
    label={"done":"DONE","partial":"PARTIAL","gap":"GAP","nodelta":"NO DELTA","unverified":"UNVERIFIED"}[s]
    return f'<span class="b b-{s}">{label}</span>'

esc=html.escape
now=datetime.date(2026,6,16).isoformat()

n_done=sum(1 for d in deltas if d[4]=="done")
n_part=sum(1 for d in deltas if d[4]=="partial")
n_gap=sum(1 for d in deltas if d[4]=="gap")

rows=""
for code,title,t10,t11,st,ev in deltas:
    rows+=f'<tr class="r-{st}"><td class="code">{esc(code)}</td><td>{esc(title)}</td><td class="muted">{esc(t10)}</td><td>{esc(t11)}</td><td>{badge(st)}</td><td class="ev">{esc(ev)}</td></tr>\n'

gaprows=""
sevcls={"CRITICAL":"sev-crit","HIGH":"sev-high","MEDIUM":"sev-med","LOW":"sev-low","INFO":"sev-info"}
for sev,code,title,desc,loc,resolution in gaps:
    resolved = resolution.startswith("FIXED")
    rcls = "res-fixed" if resolved else "res-open"
    gaprows+=f'<tr class="{rcls}"><td><span class="sev {sevcls[sev]}">{sev}</span></td><td class="code">{esc(code)}</td><td><b>{esc(title)}</b><div class="gd">{esc(desc)}</div></td><td class="ev">{esc(loc)}</td><td class="res">{esc(resolution)}</td></tr>\n'

n_gaps_fixed=sum(1 for g in gaps if g[5].startswith("FIXED"))
n_gaps_open=sum(1 for g in gaps if not g[5].startswith("FIXED"))

def issue_block(cat,heading,blurb):
    items=[i for i in issues if i[3]==cat]
    out=f'<h3>{esc(heading)} <span class="cnt">{sum(1 for i in items if i[2]=="done")}/{len(items)} done</span></h3><p class="blurb">{esc(blurb)}</p><div class="igrid">'
    for iid,title,st,_ in sorted(items):
        cls="i-done" if st=="done" else "i-todo"
        tag="✓" if st=="done" else "○ planned"
        out+=f'<div class="icard {cls}"><span class="iid">{esc(iid)}</span> <span class="itag">{tag}</span><div class="it">{esc(title)}</div></div>'
    out+='</div>'
    return out

nodelta_html=" · ".join(esc(x) for x in nodelta_24)

doc=f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>WH40k 10th → 11th Edition Migration Audit</title>
<style>
:root{{--bg:#0f1115;--card:#181b22;--card2:#1f232c;--ink:#e7e9ee;--mut:#9aa3b2;--line:#2a2f3a;
--done:#2ea043;--part:#d29922;--gap:#f85149;--nod:#6e7681;--acc:#58a6ff;}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}}
.wrap{{max-width:1180px;margin:0 auto;padding:32px 22px 80px}}
h1{{font-size:30px;margin:0 0 6px}}
h2{{font-size:22px;margin:42px 0 10px;padding-bottom:8px;border-bottom:1px solid var(--line)}}
h3{{font-size:17px;margin:24px 0 6px}}
.sub{{color:var(--mut);margin:0 0 22px}}
a{{color:var(--acc)}}
.callout{{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--acc);border-radius:8px;padding:14px 18px;margin:18px 0}}
.callout.warn{{border-left-color:var(--gap)}}
.stats{{display:flex;gap:14px;flex-wrap:wrap;margin:18px 0}}
.stat{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 18px;flex:1;min-width:150px}}
.stat .n{{font-size:28px;font-weight:700}}
.stat .l{{color:var(--mut);font-size:13px}}
table{{width:100%;border-collapse:collapse;margin:12px 0;font-size:13.5px}}
th,td{{text-align:left;padding:9px 10px;border-bottom:1px solid var(--line);vertical-align:top}}
th{{color:var(--mut);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.04em;position:sticky;top:0;background:var(--bg)}}
td.code{{font-family:ui-monospace,Menlo,Consolas,monospace;white-space:nowrap;color:var(--acc)}}
td.muted{{color:var(--mut)}}
td.ev{{color:var(--mut);font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px}}
tr.r-gap{{background:rgba(248,81,73,.06)}}
tr.r-partial{{background:rgba(210,153,34,.06)}}
tr.res-fixed{{background:rgba(46,160,67,.06)}}
tr.res-open{{background:rgba(88,166,255,.05)}}
td.res{{font-size:12.5px;color:#9fe0ad}}
tr.res-open td.res{{color:#9cd1ff}}
.b{{display:inline-block;padding:2px 8px;border-radius:20px;font-size:11px;font-weight:700;white-space:nowrap}}
.b-done{{background:rgba(46,160,67,.18);color:#56d364}}
.b-partial{{background:rgba(210,153,34,.18);color:#e3b341}}
.b-gap{{background:rgba(248,81,73,.18);color:#ff7b72}}
.b-nodelta{{background:rgba(110,118,129,.18);color:#9aa3b2}}
.sev{{display:inline-block;padding:2px 9px;border-radius:6px;font-size:11px;font-weight:700}}
.sev-crit{{background:#7d1a14;color:#ffb3ad}} .sev-high{{background:#7a4b08;color:#ffd591}}
.sev-med{{background:#5a4a0a;color:#ffe08a}} .sev-low{{background:#33384a;color:#aeb6c6}} .sev-info{{background:#1f3b52;color:#9cd1ff}}
.gd{{color:var(--mut);font-size:12.5px;margin-top:4px}}
.igrid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:10px;margin:10px 0 6px}}
.icard{{background:var(--card2);border:1px solid var(--line);border-radius:8px;padding:10px 12px}}
.icard.i-todo{{border-style:dashed;opacity:.85}}
.iid{{font-family:ui-monospace,monospace;color:var(--acc);font-size:12px;font-weight:700}}
.itag{{float:right;font-size:11px;color:var(--mut)}}
.i-done .itag{{color:#56d364}}
.it{{font-size:13px;margin-top:3px}}
.cnt{{font-size:12px;color:var(--mut);font-weight:400}}
.blurb{{color:var(--mut);font-size:13px;margin:2px 0 4px}}
.legend{{display:flex;gap:16px;flex-wrap:wrap;margin:8px 0 0;color:var(--mut);font-size:12.5px}}
code{{background:#11141a;padding:1px 5px;border-radius:4px;font-size:12.5px}}
.foot{{margin-top:50px;color:var(--mut);font-size:12.5px;border-top:1px solid var(--line);padding-top:16px}}
</style></head>
<body><div class="wrap">

<h1>Warhammer 40,000 — 10th → 11th Edition Migration Audit</h1>
<p class="sub">Comprehensive rule-by-rule audit of the codebase against the uploaded 11th-edition core rules · generated {now}</p>

<div class="callout warn">
<b>Read this first — scope &amp; honesty.</b> This page was produced by a fresh, rule-by-rule re-audit (every numbered rule 01.xx–24.xx checked against the actual code, not against the issue tracker's "DONE" labels). It exists because an earlier pass batched several abilities into a single deferred bullet and reported the migration "complete" when it was not. The audit <b>confirmed that pattern was real and systemic</b>: parent issues were marked DONE while specific sub-mechanics remained unwired. Every one of those gaps (CRITICAL → LOW) has since been <b>fixed, validated, and committed</b> (ISS-064 – ISS-074); they remain listed up front under <a href="#gaps">Confirmed Gaps</a> with their resolutions, so the record of what was wrong is preserved alongside the fix.
</div>

<div class="callout">
<b>Edition is opt-in.</b> <code>GameConstants.edition</code> defaults to <b>10</b>. Every 11e behaviour below is gated behind <code>edition&nbsp;&gt;=&nbsp;11</code> and is dormant in a default game; it activates when the switch is flipped (tests/scenarios set it explicitly). "DONE" therefore means "edition-gated 11e code exists and runs under the edition-11 tests/scenarios," not "live in the shipped 10e build."
</div>

<div class="stats">
<div class="stat"><div class="n">{len(deltas)}</div><div class="l">10e→11e rule deltas catalogued</div></div>
<div class="stat"><div class="n" style="color:var(--done)">{n_done}</div><div class="l">implemented &amp; verified (edition-gated)</div></div>
<div class="stat"><div class="n" style="color:var(--part)">{n_part}</div><div class="l">partial</div></div>
<div class="stat"><div class="n" style="color:var(--gap)">{n_gap}</div><div class="l">gap (still 10e / unwired)</div></div>
<div class="stat"><div class="n" style="color:var(--done)">{n_gaps_fixed}</div><div class="l">audit gaps fixed this pass (ISS-064–074)</div></div>
</div>

<h2 id="gaps">1 · Confirmed Gaps — found by this audit, now resolved</h2>
<p class="sub">Surfaced by this audit and verified first-hand against the rulebook and code. Two were active correctness bugs at edition 11; the rest were missing or 10e-only behaviour. <b>All {n_gaps_fixed} actionable gaps (CRITICAL → LOW) have since been fixed, validated, and committed</b> — the right-hand column records the fix and its issue id. The remaining {n_gaps_open} INFO rows are a tracked deferral (ISS-027) and one item that could not be pinned to a file:line. Ordered by severity.</p>
<table><thead><tr><th>Severity</th><th>Rule</th><th>Gap (as found)</th><th>Location</th><th>Status / resolution</th></tr></thead><tbody>
{gaprows}
</tbody></table>

<h2>2 · Complete 10e → 11e Delta Catalog</h2>
<p class="sub">Every core rule that <b>changed</b> or is <b>new</b> in 11th edition, with implementation status and code evidence. Sections identical between editions are summarised below the table.</p>
<div class="legend">{badge('done')} edition-gated 11e code verified &nbsp; {badge('partial')} part implemented &nbsp; {badge('gap')} still 10e / unwired</div>
<table><thead><tr><th>Rule</th><th>Title</th><th>10th edition</th><th>11th edition change</th><th>Status</th><th>Evidence</th></tr></thead><tbody>
{rows}
</tbody></table>
<p class="sub" style="margin-top:14px"><b>Ability glossary — no delta (identical 10e/11e, present in code):</b><br><span class="muted" style="color:var(--mut);font-size:13px">{nodelta_html}</span></p>

<h2>3 · Everything Changed This Session</h2>
<p class="sub">All 74 tracker issues (ISS-001 – ISS-074), grouped by intent — including the 11 TIER-4 issues (ISS-064 – ISS-074) opened by this audit to fix the confirmed gaps. The 11e migration is one of three workstreams; the architecture and infrastructure work is included per the request to cover all session changes even where they are not strictly an edition change.</p>
{issue_block("11e","11th-edition rules migration","The rule-conversion work catalogued in section 2 — schema, phases, attack resolution, terrain, stratagems, transports, attached units, reserves, AI, and the windowed scenario suite.")}
{issue_block("arch","Architecture &amp; refactor (not edition-specific)","Structural cleanups that underpin the migration: routing all mutation through the action pipeline, the edition switch itself, ability schema, the consolidated modifier stack, live-view snapshots, the PhaseManager/TurnManager ownership split, the SceneRefs path chokepoint, and more. Dashed cards are the 5 remaining planned refactors.")}
{issue_block("infra","Test &amp; safety infrastructure","The nets that make the migration verifiable: deterministic action-log replay, the save-migration framework, and the golden-master replay harness (records games, replays after scrambling, asserts hash-identical, proves sensitivity to rules drift).")}

<h2>4 · Validation</h2>
<ul>
<li>Headless regression suite after the gap fixes: <b>1250 checks across 79 tests, 0 failures</b> (was 1138/68 at the time of the original audit). Each ISS-064–074 fix added a dedicated test that drives the REAL phase/engine function (not a stub) plus a 10e sensitivity check.</li>
<li>Windowed scenarios (real UI, screenshots reviewed) added for the player-facing fixes — fall-back single-hazard, at-half battle-shock, and the Scout strategic-reserves→DZ deploy — alongside the existing edition-11 scenario batch and the AI-vs-AI full game to battle round 5 at edition 11.</li>
<li>Golden-master replay: 10e and 11e game slices reproduce hash-identical; tampering the dice stream provably breaks the golden. The keyword-scope / duplicated-ability / target-threading changes are backward-compatible — current (unscoped, single-instance) data keeps the goldens byte-identical.</li>
<li><b>Why the original suites missed these:</b> the gaps in section 1 were precisely the behaviours those suites did <i>not</i> exercise — e.g. the fall-back scenario asserted the begin-path hazard roll count but never confirmed the move, so it never caught the double-fire. Green suites did not imply completeness; the new tests close exactly those holes.</li>
</ul>

<h2>5 · Method &amp; honest limitations</h2>
<ul>
<li>Four independent audit passes covered rule ranges 01–09, 10–14, 15–23, and the 24.xx ability glossary; each opened the cited code and checked the edition branch and constant values directly rather than trusting tracker status.</li>
<li>The audit findings were initially reported as code-evident (not runtime-proven). Since then every CRITICAL → LOW gap has been driven live: each fix has a dedicated headless test exercising the real phase/engine function and a 10e sensitivity check, and the player-facing ones add a windowed scenario. The two original CRITICAL items (fall-back double-fire, at-half battle-shock) are now runtime-proven, not merely code-evident.</li>
<li>One item (20.02 repositioned-units persistence) could not be pinned to a file:line and is still flagged UNVERIFIED rather than guessed. The 19.04 effect-flag source-expiry matrix remains partial and is deferred to ISS-027.</li>
<li>The 11e datasheet <i>values</i> (per-unit Ld/OC/invuln re-baselining) are data, not rules, and remain a separate review (ISS-037 left the schema + review flags as the landing pad).</li>
</ul>

<div class="foot">
Generated from a first-principles re-audit of the 11e core rules against the codebase at commit <code>05b541b</code>.
This page supersedes the earlier "11e tier complete" summary: the migration is substantially implemented and verified for the catalogued DONE rows, but it is <b>not complete</b> — see section 1.
</div>

</div></body></html>"""

open("docs/11e_migration_audit.html","w").write(doc)
print("written docs/11e_migration_audit.html  (%d bytes)" % len(doc))
print("deltas: %d done / %d partial / %d gap" % (n_done,n_part,n_gap))
print("gaps listed: %d" % len(gaps))

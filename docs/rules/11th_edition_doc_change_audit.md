# 10th → 11th Edition Changes vs. the Godot Game — Doc-Driven Validation

**Source doc:** "Tabletop Battles Reviews: Warhammer 40k 11th Edition" (Google Doc `1uBu-…LZTM`),
comprising the overview + 8 rules deep-dives + missions article (Tabs 1–10).
**Method:** every concrete rules change the doc calls out was catalogued, mapped to the codebase,
and — for everything with a runtime surface — **driven live** at `GameConstants.edition == 11` through the
`addons/godot_mcp` bridge (real menu clicks, deploy, move, shoot, allocation dialogs, screenshots) plus the
windowed scenario suite. Static-only claims were confirmed first-hand in `.gd` source.
**Date:** 2026-07-02. **Companion:** `docs/rules/11th_edition_delta_audit.md` (the PDF-driven audit this cross-checks).

## Legend
- ✅ **DONE** — 11e rule implemented, edition-gated, wired into the live path, and validated (live or scenario).
- 🟡 **PARTIAL** — implemented but incomplete, approximate (2D board), or missing a player affordance/data.
- 🔴 **MISSING** — not implemented in a way a player can use.
- ▪️ **UNCHANGED** — the doc explicitly lists this as unchanged from 10e; present in-game.

---

## How this was validated live (evidence highlights)

A full P1 turn was played as a user (Adeptus Custodes vs Orks, 11th Edition):

| Area | Evidence captured |
|---|---|
| Edition default + selector | Main-menu "Rules Edition: **11th Edition (beta)**"; `GameConstants.edition == 11` at boot. |
| Leader **+ Support** dual attach | Formations dialog attached Blade Champion to Custodian Guard; a second character slot is offered on the same unit. |
| Coherency 2"/9" | Deploy/move rejections cite *"not within 2" horizontally"* and *"coherency broken"* at e11. |
| Engagement 2" | `GameConstants.engagement_range_inches() == 2.0`. |
| Advance blocks non-Assault shooting | Advanced Witchseekers are **absent** from the Shooting-phase shooter list. |
| FLY "Take to the Skies" | Movement panel toggle on the jetbike; move cap 12" → **10"** (−2") after toggling. |
| `[HEAVY]` ≤3" tracking | `flags.moved_max_inches` = 0 (stationary), 4.0 (advanced) written on confirm. |
| Both players +1 CP | Right panel "Player 1: 1 CP / Player 2: 1 CP — +1 CP generated this phase". |
| 11e save **allocation groups** | Live dialog: *"Declare the allocation order (05.03). Damage is applied lowest save roll → highest"*; log `11e allocation, order ["grp_1_5_0"]`; 3 Boyz destroyed lowest-first. |
| Fast-dice / weapon-order | "Choose Weapon Order" + "Fast Roll All" batch UI. |
| **Start Action** | "Start Action: Hold Position" button live in the Shooting phase (16.00 actions are now startable). |
| Aircraft must start in reserves | On-board deploy of the Wazbom rejected: *"AIRCRAFT must start in Strategic Reserves (23.01)"*. |
| Terrain objectives + control | Board shows HOME/NML terrain-area objectives; right panel "Objective Control … Contested/Custodes/Orks" recomputed per phase. |
| Secondary missions (Tactical) | Command phase drew "No Prisoners" + "Extend Battle Lines"; replace-for-1CP offered. |
| Scout 8" | `ScoutPhase._scout_min_enemy_distance_inches() == 8`. |
| Fight phase | `iss050_fight_11e` windowed scenario **16/16 pass**. |

---

## 1. Core Concepts (Tab 1)

| # | Change (11e) | Status | Where / note |
|---|---|---|---|
| Numbered rule blocks | Presentation only | ▪️ n/a | Cosmetic; no game surface. |
| App-only extended rules | Presentation | ▪️ n/a | No game surface. |
| Rule templates / **modal** rules (e.g. Disembark 3 modes) | ✅ | Disembark modal (Rapid/Tactical/**Combat**) wired (`MovementPhase` `CONFIRM_DISEMBARK`). |
| Active/Opposing player + **sequencing** (opponent last say) | 🟡 | Reactive-stratagem windows exist (Overwatch/HI/Rapid Ingress offered to opponent at phase end, validated live) but the general "mandatory-then-optional, opponent-last" sequencer is not a formal engine step. |
| **Invulnerable saves mandatory** (best of armour/invuln, no opt-out) | ✅ | `Allocation.gd:207` always takes the better save; no player choice to use the worse one. |
| Turn/phase **Start/End steps + scoring sub-step** | ✅ | `PhaseManager` start/end signals + end-of-command scoring sub-step (validated: objectives scored on END_COMMAND). |
| **Hazard rolls** (D6, 1–2 = 1 MW / 3 for M-V) | ✅ | `AttackSequence.hazard_rolls`; consumed by `[HAZARDOUS]`, desperate escape, emergency/combat disembark, all edition-gated. |
| **Actions in core rules** (OC1, not aircraft, blocks/blocked-by shoot+charge) | 🟡 | `ActionsManager` correct + a live **"Start Action: Hold Position"** affordance exists; but only one generic action is authored — the 11e mission-specific action set (Tab 10) is absent. |
| Battle-shock **OC → "-"** (unmodifiable) | ✅ | `CommandPhase`/`GameState` set unmodifiable OC at e11. |
| Battle-shock **at** half-strength (2-model units test) | ✅ | `GameState.is_at_half_strength_combined`; validated `iss065`. |
| Battle-shock **no auto-recovery** (re-test next command) | ✅ | Recovery test in `CommandPhase`; Insane Bravery can't auto-pass a recovering unit. |
| **Detachment Points** (pool, 3 @ 2000pts) | 🔴 | Army construction still 10e single-detachment; no DP pool. |
| Leaders attach at **army construction** | ✅ | Attach happens in the pre-deploy Formations step; permanent for the game. |
| **Support characters** (2nd attach slot, must attach) | 🟡 | Engine + FormationsPhase per-role slots wired; the Bannernob (orks.json) now ships `Support` + `leader_data` and attaches alongside a Leader through the live Formations dialog (windowed `iss059b_support_attach_11e`, 30/30). Remaining: "must attach" not enforced; no other Support datasheets authored. |
| **Enhancement after attach, 1/unit** | 🟡 | Enhancement validation exists (1/char) but not re-sequenced after attach; no post-attach UI gate. |
| **Upgrades** (non-char, ×3, 1 enhancement pick) | 🔴 | Not implemented. |
| **Warlord = army faction** | 🔴 | No warlord-faction restriction enforced. |
| **Multiple-modifier order** (set→×→+→÷→−, set-0 stops) | 🟡 | Damage-side ordering VERIFIED in every live path (melta/+dmg adds → halve → −1, all six sites; live pin `test_iss047` E4: 6+2→halve→4). Residual: no single shared pipeline (each site hand-ordered), and set-×/set-0 semantics have no data consumer yet. Hit modifiers remain a net-sum `ModifierStack`. |
| **Lone Operative X"** + 9"–30" mod cap | 🟡 | `get_lone_operative_range` parses X" (validated `iss069`); the 9–30 modifier clamp is not separately enforced. |

## 2. Command Phase (Tab 2/9)

All major items ✅ and validated (both-player +1 CP live; OC "-"; at-half test; no auto-recovery; scoring sub-step
after abilities). Command-abilities-after-battleshock ordering ✅ in `CommandPhase`.

## 3. Movement (Tab 3)

| # | Change | Status | Note |
|---|---|---|---|
| Coherency 2" **+ 9" envelope** | ✅ | Validated (deploy/move rejections). End-of-turn removal is now player-chosen for human owners (03.03 dialog, `iss042b`); auto-pick remains the AI/backstop. |
| Engagement **2"** global | ✅ | Live `2.0`. |
| Move **through** enemy ER (end outside) | ✅ | `MovementPhase` staging allows transit, checks end-position. |
| Set-Up outside ER; **Engaged** as a term | ✅ | Deploy/ingress validators enforce. |
| Move templates (Max/Set-Up dist, Before/While/After) | ✅ | `movetypes/*`. |
| **Free pivots** / straight-line+pivot | 🟡 | Pivot cost gated off at e11; not a fully modelled multi-segment pivot geometry. |
| **FLY "Take to the Skies"** (−2", ignore vertical, through all) | ✅ | Movement-panel toggle validated live (12→10"). |
| Move through gaps by base | ✅ | Pre-existing. |
| M/V through non-M/V enemies | ✅ | Gated at e11. |
| **FRAME** keyword (measure-to-hull) | 🟡 | Schema + measurement special-case present; few data users. |
| **No Reinforcements step** (reserves move in Movement) | ✅ | Ingress in Movement phase; validated (Wazbom → reserves, ingress later). |
| **Overwatch at end of Movement** (Snap Shooting) | ✅ | Overwatch/Rapid Ingress offered at end-of-movement; not in Charge. |
| Six move types incl. Ingress/Disembark | ✅ | Enumerated in `get_available_actions`. |
| Advance blocks charge/action, Assault-only shoot | ✅ | Validated (advanced unit not in shooter list). |
| **Fall Back: Ordered Retreat vs Desperate Escape** (hazard + battle-shock) | ✅ | `FallBackMove`; `iss064` (single-hazard) fix confirmed. |
| **Ingress Move** (>8", ≤6" edge, no opp-DZ pre-R3) | ✅ | Edge+8" gated; opp-DZ ban wired (audit A12 fix). |
| Deep Strike = ingress modifier (>8") | ✅ | 9→8 gated; `iss068`. |
| Repositioned units / Da Jump ingress | ✅ | `376_da_jump` scenario. |
| No movement after Ingress | ✅ | Ingress sets a no-further-move lock. |
| Single 1000pt reserves cap; destroyed EoR3 | 🟡 | Reserve cap + R3 destruction present; the single-pool vs split not strictly enforced. |
| **Embark blocked if set-up this turn** | 🟡 | `TransportManager.can_embark` gates it, but the live embark validator keys a generic `moved` flag (audit 18.02). |
| Disembark modes Rapid/Tactical/**Combat** | ✅ | Wired; Combat-mode "set up **engaged**" honoured — models may be set up engaged with enemy units the transport is engaged with, others rejected (`iss058b_combat_disembark_engaged_11e`); DisembarkDialog exposes a Combat Disembark toggle with a 6" ring. |
| **Emergency disembark** 6"+hazard+battle-shock | ✅ | 11e band wired (audit A7 fix). |

## 4. Attacks & Shooting (Tab 4)

| # | Change | Status | Note |
|---|---|---|---|
| **Batch attack resolution** (identical-profile groups) | ✅ | `AttackSequence.gather_identical_attacks`; live weapon-order/fast-roll UI. |
| **Save allocation groups** (05.03: char-last, wounded-first, lowest-die-first) | ✅ | **Validated live** — dialog cites 05.03, lowest-first; 3 Boyz died lowest-first. Ranged + melee (A1). |
| Damage lowest→highest, invuln-vs-AP, excess lost | ✅ | `Allocation.apply_save_rolls`. |
| **Mortal wounds per identical group**, priority order | ✅ | `Allocation.select_mortal_wound_target`; ranged + stratagems + melee (A1). |
| Slow-roll only for random-D / FNP | ✅ | Honoured. |
| **Cover = −1 BS** to shooter (stacks with −1 hit) | ✅ | `ModifierStack.collect_hit_context_11e` (bs side). |
| Cover **per attacking model** (split groups) | ✅ | Each attack takes the 13.08 cover worsening from ITS OWN firing model's view (per-attack BS via `cover_model_per_attack`, both resolution paths); pinned in `test_iss047` E6 (obscured firer misses, clear firer hits, same volley). |
| **Stealth → Cover** | ✅ | Routed through cover path. |
| Four shooting modes (Normal/Assault/CQ/Indirect) | ✅ | `ShootingTypes.available_for`; `iss048`. |
| Assault (advanced + [ASSAULT]) | ✅ | Validated (advanced unit shows only if it has Assault). |
| **Close-Quarters** (engaged; M/V −1 unless CQ; no Heavy while engaged; no Blast vs engaged) | ✅ | `CloseQuartersShooting` + ModifierStack. |
| **Indirect** (6s-to-hit unless stationary+spotter; cover; no hit re-roll) | ✅ | 11e harsh fail-band live & edition-gated (`RulesEngine:1699–1812`); 10e −1 gated off. |

## 5. Charge & Fight (Tab 5)

| # | Change | Status | Note |
|---|---|---|---|
| **Roll 2D6 first, pick targets after** | ✅ | `ChargeMove11e`; `iss049` drives it (the one scenario "failure" is a seed-sensitive expected-roll assertion, not a rules bug — the charge action succeeds and populates `pending_charges`). |
| Charge success = unit-to-unit distance; double-1 auto-fail | ✅ | 2" slack model. |
| DS/reserve charge still needs 9 (>8" setup) | ✅ | Gated. |
| Within 1" (no base contact needed) | ✅ | Priority ladder in `ChargeMove11e`. |
| Optional charge execution | ✅ | Empty-declare then post-roll select. |
| Charge Bonus = Fights First to EoT | ✅ | `ChargePhase` grants it. |
| **No Overwatch in Charge** | ✅ | Overwatch is Movement-only. |
| **Heroic Intervention** end-of-phase, 1CP (12", chargers) / **2CP (6", anyone)** | 🟡 | Offered end-of-charge (`hi_offer_after_charge…` scenarios); modal 1/2-CP effect wired via the stratagem resolver (audit A4). |
| **Shared Pile-In step** (active first, all eligible) | 🟡 | `PileInMove` geometry authoritative (`iss066`) but structurally per-fighter, not one global both-players step. |
| Fight eligibility locks at step start; **Overrun Fight** | 🟡 | `FightSequencer` keeps step-start-eligible units; overrun selectable, extra pile-in partial. |
| Attack eligibility = pure 2" | ✅ | ER predicate. |
| **Fight order: Active player picks first**, FF-first, revert-to-FF | ✅ | `FightSequencer`; `iss050` 16/16 (validated). |
| Melee split **attacks** across engaged targets, must use all | ✅ | Melee path. |
| **Shared Consolidation** (Ongoing/Engaging/Objective modes) | 🟡 | `ConsolidationMove` modes authoritative; Engaging-mode "pull new unit into a fresh Fight" achieved via an edition-agnostic scan; per-fighter not one global step; 3"-vs-5" ambiguity left at 3". |

## 6. Terrain & Objectives (Tab 6)

| # | Change | Status | Note |
|---|---|---|---|
| Terrain **Feature vs Area** split | 🟡 | Layouts model features + walls; a distinct "Terrain Area" polygon with its own boundary is approximated, not a first-class authored layer. |
| **Terrain Areas ARE objectives** | ✅ | `MissionManager` point-in-polygon objective control at e11. |
| Categories **Exposed/Light/Dense** | 🟡 | `TerrainManager.category_of` derives heuristically from type/height; layouts don't author explicit categories. |
| Category movement (Dense: INF/SWARM/BEAST; <2" free) | ✅ | `can_move_through_11e` (movement path). Charge path still uses 10e penalty. |
| **Solid** rule (no ending in <3" enclosed gap) | 🔴 | Dead branch behind Obscuring; no real window/gap geometry (2D). |
| Mixed-category areas | 🟡 | Supported structurally; not authored per layout. |
| **Cover conditions** (INF/SWARM/BEAST in area, or not fully visible) | 🟡 | Cover-as-BS works; keyword-in-area condition partial. |
| **Hidden** (15" detection, INF/SWARM/BEAST, no ranged this/prev turn) | ✅ | 13.09 gate (keywords + dense area + `last_shot_idx`/`shot_recently`) suppresses visibility in the live targeting path (`RulesEngine._check_target_visibility`); windowed `iss052b_gone_to_ground_11e`. |
| **Gone to Ground** (−3" → 12" when obscured) | ✅ | `TerrainManager.detection_range_inches_for`: −3" while an intervening DENSE piece blocks a 13.10/13.11 sight line; validated live (visibility flips at 12"/15" bands, `iss052b`). |
| **Detection Range datasheet modifiers** (down to 9") | 🟡 | Plumbing + parser done: a `Detection Range X"` datasheet ability overrides the 15" base (Lone Operative-style parse), clamped to the 9" floor even under Gone to Ground (`iss052b`). No shipped datasheet carries one yet (needs 11e data). |
| **Obscuring** (block LoS unless firer *within* area) | 🟡 | `_line_blocked_11e` every-line test via 9-point sampling; "within (not wholly)" approximated. |
| **Climbing** (0.5" horiz; Monsters may climb) | 🟡 | 2D board — vertical floors approximated. |
| **Plunging Fire** (>3" height → +1 BS) | ✅ | `plunging_fire_applies` + ModifierStack; 3" threshold at e11. |
| Objective control = Level of Control per phase/turn | ✅ | Recompute on phase/turn end; battle-shocked contributes 0. |
| Unit-controlling-objective (OC1 in a controlled objective) | ✅ | `MissionManager`. |
| **Secured** objectives | ✅ | Sticky mechanism. |
| **Home / Expansion / Central** objective types | 🔴 | Board labels HOME/NML but the Chapter-Approved Home/Expansion/Central *designation semantics* (mission scoring by type) are absent. |
| 40mm/3" marker fallback | ✅ | Appendix fallback present. |

## 7. Special Unit Types (Tab 7)

| # | Change | Status | Note |
|---|---|---|---|
| Leader + Support attach | 🟡 | Engine ✅; Bannernob ships `Support` and is player-usable via the Formations dialog (§1, `iss059b`); other factions still have no Support data. |
| Attachment permanent; parts not destroyed separately | 🟡 | Attached unit stays a unit; highest-T fixed (A11); keyword-destroyed-targeting & ability-source-model persistence partial. |
| Abilities persist while source model alive | 🟡 | Ties to leader *unit* alive (≈ ok for 1-model leaders). |
| Keyword union + destroyed-keyword targeting | 🟡 | Union present; wired into one consumer (ANTI). |
| M/V through enemy non-M/V | ✅ | Gated. |
| **FRAME** | 🟡 | Schema + measurement. |
| **TOWERING** → Plunging Fire ≤12" | ✅ | ModifierStack at e11. |
| Shoot engaged M/V at −1 | ✅ | ISS-048. |
| **Aircraft: ingress-only, no M char, return to reserves EoT, start in reserves, no charge** | 🟡 | Start-in-reserves ✅ (validated rejection); ingress-only ✅ (B7); return cycle present; "ignore Plunging both ways" partial. |

## 8. Core Stratagems & Abilities (Tab 8)

**Stratagems:** One-per-unit-per-phase ✅ (`StratagemManager:685`). Modal costs (HI 1/2CP) ✅.
Unchanged set (Epic Challenge, Insane Bravery, Counteroffensive, Explosives) present.
Changed: Command Re-roll (single die) ✅ (validated — the movement-phase re-roll dialog offered one die);
Crushing Impact (Tank Shock + monsters + self-MW-on-1) ✅ (dice handler + attacker target prompt, `iss047d`);
Rapid Ingress ✅; **Fire Overwatch + Snap Shooting** ✅; Smokescreen 🟡 (cover granted; "cover to units behind" nuance partial);
Go-to-Ground stratagem removed ✅ (only the Hidden sub-rule name remains — though that sub-rule itself is unimplemented, §6).

**Core abilities:** Blast X ✅, Lethal Hits optional ✅, Devastating Wounds batch+cap ✅ (ranged+melee),
Infiltrators/Deep Strike 8" ✅, Hazardous → hazard roll ✅, Lone Operative X" ✅, Melta X (post-order) 🟡,
Deadly Demise after disembark ✅, Extra Attacks modifiable ✅ (10e Balance-Dataslate suppression edition-gated off at e11; pinned in `test_iss047` E5), Stealth→Cover ✅, Super-Heavy Walker ✅ (`iss073`),
Fight First (reworked value) ✅, **Precision** (allocation-order) ✅ (visibility-gated + attacker PrecisionPicker in the allocation overlay, `iss047b`),
**Heavy ≤3"** ✅ (validated flag), **Cleave X** ✅ (A8 fix), **Hover** 🟡, **Psychic ignores hit mods** ✅ (ranged+melee A10),
Scouts 8" + reserves→DZ ✅ (`iss067`), **Surge Moves** 🟡 (engine + trigger + UI done: template-gated `BEGIN_SURGE_MOVE`, `Surge X"` ability parser, movement-list offering — `iss040b`; no shipped datasheet carries the ability yet),
Plunging Fire 3"/+1 ✅, **Hunter X** 🔴 (unimplemented, no data), **Heal X** 🔴 (unimplemented, no data).

## 9. Missions (Tab 10)

| # | Change | Status | Note |
|---|---|---|---|
| **Force Dispositions** (5, pick from detachment) | 🔴 | No disposition system — "disposition" appears only as a detachment flavour string in `Stratagems.csv`. |
| **Asymmetric primaries** (15 pairings, e.g. Meatgrinder/Vital Link) | 🔴 | Game uses 10e-style **symmetric** primary selection (Take & Hold / Purge the Foe dropdowns). |
| Primary caps (45 VP, 15/round, 2nd-player R5 EoT) | 🟡 | Take-and-Hold / Purge scoring exists; not the 11e pairing/caps model. |
| Secondary **Fixed vs Tactical** | ✅ | Both modes selectable + validated Tactical draw. |
| 11e **secondary deck** (Forward Position, Plunder, Beacon, Centre Ground, A Grievous Blow; no hand limit; 45 cap) | 🔴 | Current deck is 10e-derived; the specific 11e cards/rules not authored. |

---

## 10. Consolidated task list — what remains for full 11e

Ordered by player impact. Engine-level items marked **[code]**; content-authoring **[data]**.

### Tier 1 — whole subsystems a player cannot use today
1. **[code+data] 11e mission system.** Implement Force Dispositions (5), the 15 disposition-pairing table, and
   asymmetric per-player primary missions (Meatgrinder, Vital Link, Destroyer's Wrath, …) with the 45/15 caps and
   2nd-player round-5 end-of-turn scoring. Add disposition selection to army build/new-game. *(Ref: doc Tab 10.)*
2. **[data] 11e secondary mission deck.** Author the 11e Fixed four (Assassination, Bring it Down, A Grievous Blow,
   Engage on All Fronts) and the 18-card Tactical deck (Forward Position, Plunder, Beacon, Centre Ground, returning
   cards with tweaks), with no hand-size limit and the 45-VP cap. *(Tab 10.)*
3. **[data] Support-role datasheets + true 11e stat lines.** *(Partially done 2026-07-02:)* the Bannernob now carries
   `Support` + `leader_data` in orks.json, FormationsPhase enforces the 11e per-role slots (one leader + one support),
   and the flow is windowed-validated (`iss059b_support_attach_11e`). Still open: tag Support characters in other
   factions, and source real 11e **Ld/OC/Invuln** values — note the invuln picture is better than first reported
   (Custodes 4+/Draxus 5+/Beastboss 5+ etc. already present in `meta.stats.invuln`); what's missing is mostly
   orks.json characters (Ghazghkull, Badrukk, Warbosses) and any true-11e deltas, which need an official source
   (PRD §5 open q.2). *(Tab 1/7; §1, §7.)*
4. **[code] Hidden / Gone to Ground / Detection Range.** *(Done 2026-07-02, code side:)* Gone to Ground (−3" → 12"
   behind an intervening dense/Solid feature), the `Detection Range X"` datasheet parser with the 9" floor, and the
   Hidden gate all validated in the live targeting path (windowed `iss052b_gone_to_ground_11e`, 46/46; headless
   `test_iss052_hidden_11e`, 27/27). Remaining: author actual datasheet Detection-Range values once 11e data is
   sourced. *(Tab 6; §6.)*

### Tier 2 — army construction & terrain fidelity
5. **[code] Army construction 11e:** Detachment Points pool (3 @ 2000), Upgrades (non-char, ×3, one enhancement pick),
   enhancement-after-attach sequencing, and the Warlord-must-match-army-faction rule. *(Tab 1.)*
6. **[code+data] Terrain categories & areas:** author explicit Exposed/Light/Dense categories and Terrain-Area polygons
   per layout; implement the **Solid** <3"-gap rule and the Home/Expansion/Central objective designations used by
   missions. *(Tab 6.)*
7. **[code] Cover per attacking model:** *(Done 2026-07-02:)* each attack's BS worsening is computed from its own
   firing model's view of the target (13.08 second condition is per-attack); attacks with no recorded firer (overrides/
   bonus attacks) fall back to the first firer. Pinned in `test_iss047_weapon_abilities_11e` E6. *(Tab 4/6.)*

### Tier 3 — ability/affordance completeness (engine mostly present)
8. **[code] Surge Moves** — *(Code done 2026-07-02:)* `BEGIN_SURGE_MOVE` is template-gated at e11 (stated distance, closest-enemy target, no D6), a `Surge X"` datasheet ability lights up the movement-list offering (`iss040b_surge_move_11e`). Remaining: author a real datasheet with the ability once 11e data is sourced (PRD §5 q.2). *(Tab 8.)*
9. **[code] Hunter X and Heal X** core abilities. *(Tab 8 — currently absent.)*
10. **[code] Combat Disembark** — *(Done 2026-07-02:)* the validator honours "set up **engaged** within 6"" for enemy units the transport is engaged with (and only those); the placement UI gets a Combat Disembark toggle, 6" ring, and matching placement rules. Windowed `iss058b_combat_disembark_engaged_11e` 26/26. *(Tab 3.)*
11. **[code] Explosives / Crushing Impact** — *(Done 2026-07-02:)* the stratagem panel now runs a two-step target prompt (friendly unit, then eligible enemy — engaged for Crushing Impact, within-8"-and-visible for Explosives) and resolves via `use_stratagem` with the chosen enemy in context (`iss047d_crushing_impact_prompt_11e`). *(Tab 8.)*
12. **[code] Modifier-order pipeline** — *(Verified + pinned 2026-07-02:)* halve-after-melta already holds in every
    damage path (interactive allocation, auto-resolve, melee, devastating, overwatch) — confirmed by reading all six
    sites and pinned live (`test_iss047_weapon_abilities_11e` E4). Deferred: consolidating into one shared pipeline and
    set-×/set-0 semantics, which no shipped modifier uses yet. *(Tab 1.)*
13. **[code] Precision** — *(Done 2026-07-02:)* promotion is gated on the character being visible to an attacking model (13.09/13.10/13.11 + LoS), and the attacker chooses the promoted group (or declines) via the AllocationGroupOverlay PrecisionPicker; chosen group rides the save batch (`iss047b_precision_choice_11e`; headless E2 section). *(Tab 8.)*
14. **[code] Melee/Extra-Attacks/Melta polish** — *(Extra Attacks done 2026-07-02:)* the 10e Balance-Dataslate "cannot modify A" suppression is edition-gated off at e11 (Waaagh/Da Biggest bonuses now apply; pinned 10e-vs-11e in `test_iss047` E5). Melta "post-order" remains — its precise semantics live in the review-doc deep-dive, which is not in the repo (needs source). *(Tab 8.)*

### Tier 4 — structural/cosmetic
15. **[code] Fight-phase step structure** — make Pile-In and Consolidation single global both-player steps (active-first)
    rather than per-fighter; resolve the Engaging-consolidation 3"-vs-5" once GW FAQs. *(Tab 5.)*
16. **[code] End-of-turn coherency removal dialog** — *(Done 2026-07-02:)* END_TURN pauses for human-owned incoherent units; the CoherencyRemovalDialog lets the player pick each removed model, and the turn auto-completes once coherent (`iss042b_coherency_removal_choice_11e`). Auto-pick stays as the AI/backstop. *(Tab 3.)*
17. **[code] `[DEVASTATING WOUNDS]` / `[LETHAL HITS]` attacker-choice prompts** — *(Done 2026-07-02:)* the AbilityChoiceDialog offers both choices when a DW weapon is assigned; choices ride the assignment into all three resolution paths, incl. the new 24.10 decline (`iss047c_ability_choice_prompts_11e`; headless E3). *(Tab 4/8.)*

---

## 11. Bottom line

**Status 2026-07-02 (post-sweep):** every task-list item implementable from in-repo sources is done — Tier-1 #3
(Support attach) and #4 (Hidden/Gone to Ground/Detection Range) code-complete; Tier-3 #7, #8, #10, #11, #12, #13,
#14 (Extra Attacks), #16, #17 all landed with windowed/headless validation; delta-audit B6 closed. What remains is
**source-blocked**: the 11e mission system (#1–2, mission-pack texts not in repo), true 11e stat lines and Support
tags for other factions (#3, PRD §5 open q.2), Hunter X / Heal X (#9, zero rule text in the shipped core-rules PDF),
Melta "post-order" (#14 remainder, deep-dive only), terrain-category authoring (#6, layout data decisions), the DP/
Upgrades army-construction model (#5) — plus #15's fight-step restructure, which the audit itself parks pending a GW
FAQ on the 3"-vs-5" Engaging consolidation.

The **core engine** of 11th edition is in and genuinely playable at `edition == 11`: the new attack/allocation model,
cover-as-BS, engagement 2" / coherency 9", the move-type framework incl. FLY, the select-after-roll charge, the
active-first Fight sequencer, terrain-as-objectives with per-phase control, battle-shock, disembark modes, two-slot
attach, and the hazard/indirect/hazardous/heavy fixes all validate live or in the windowed suite. The **residual gap is
concentrated in three places**: (1) the **11e mission system** (Force Dispositions + asymmetric primaries + the new
secondary deck) is essentially unbuilt; (2) **Hidden/Gone-to-Ground/Detection-Range** and full **terrain-category /
Solid** fidelity are partial; and (3) **content** — Support datasheets, true 11e stat lines, Upgrades/Detachment-Points
army building, and the Hunter/Heal/Surge abilities that no shipped datasheet yet uses. Tiers 1–2 above are what stand
between "the 11e rules engine runs" and "a player plays a complete, rules-accurate 11th-edition game."

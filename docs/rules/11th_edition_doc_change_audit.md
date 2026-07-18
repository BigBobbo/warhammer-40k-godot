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
| **Free pivots** / straight-line+pivot | ✅ | Pivoting is FREE at e11 — `get_pivot_value_for_unit` returns 0" for every base type. (Correction 2026-07-18: this row previously claimed the cost was "gated off at e11", but the 10e 2" non-round-base pivot cost was actually applied **un-gated** and hit players; now edition-gated to 0" at e11.) Multi-segment pivot geometry still not modelled. |
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
| **Force Dispositions** (5, pick from detachment) | 🟡 | Per-player Force Disposition dropdowns in the new-game menu (`PrimaryMissionData11e.DISPOSITIONS`); pairing resolved at game init from `meta.game_config` (`iss064b_primary_disposition_11e`). Pick is menu-level, not detachment-derived. |
| **Asymmetric primaries** (25 pairings, e.g. Meatgrinder/Vital Link) | 🟡 | Full 25-card GDM 2026 pairing table authored from `docs/rules/11th_edition_missions_gdm2026.md`; each player scores their own card (own deck × opponent disposition). Concretely-specified conditions (hold/kill/enemy-home/central/quarters/escalation) are live; bespoke marker/action mechanics (Triangulate, Booby Trap, Sabotage, decoys, intel, Condemn, Consecrate…) score 0 and are flagged `approximate` pending card text. |
| Primary caps (45 VP, 15/round, 2nd-player R5 EoT) | 🟡 | 45-total + 15-per-turn caps enforced at e11; Command-phase scoring switches to end-of-turn in Round 5; EOT/EOG conditions hooked into ScoringPhase/game-end (`test_primary_missions_11e` 26/26). Doc says "C switches to EOT in Round 5" — applied to both players, not only the 2nd. |
| Secondary **Fixed vs Tactical** | ✅ | Both modes selectable + validated Tactical draw. |
| 11e **secondary deck** (Forward Position, Plunder, Beacon, Centre Ground, A Grievous Blow; no hand limit; 45 cap) | 🟡 | GDM 2026 deck authored from `docs/rules/11th_edition_missions_gdm2026.md`: 18 cards (7 new), draw-2/no-hand-limit, fixed-four restriction, 45-total + 15/turn caps (`iss063b_secondary_deck_11e`; `test_secondary_deck_11e` 31/31). Cards without published text carry `approximate: true`; Attacker/Defender variants not modelled (no variant text). |

---

## 10. Consolidated task list — what remains for full 11e

Ordered by player impact. Engine-level items marked **[code]**; content-authoring **[data]**.

### Tier 1 — whole subsystems a player cannot use today
1. **[code+data] 11e mission system.** *(Core done 2026-07-03, approximations flagged:)* Force Dispositions (5) are
   selectable per player in the new-game menu; the full 25-card GDM 2026 pairing table (`PrimaryMissionData11e`)
   resolves each player's own primary mission; a condition-based scorer in MissionManager evaluates
   hold/kill/enemy-home/central/quarters/hold-new/escalating-per-objective rules with the 45-total + 15-per-turn caps,
   the Round-5 Command→EOT switch, EOT conditions every turn, and EOG conditions at game end (save/load covered).
   Windowed `iss064b_primary_disposition_11e` + live MainMenu→start→pairing check; headless
   `test_primary_missions_11e` 37/37. **Update 2026-07-03 (web-sourced):** the bespoke action/marker mechanics were
   recovered from gdmissions.app snippets + the Tabletop Battles disposition reviews (missions doc appendix) and are
   now implemented AUTO-RESOLVED (deterministic target picks; the real cards let the player choose — cards stay
   flagged `approximate`): Triangulate (3/6/10), Consecrate markers, Punishment Condemn (left-battlefield 5 VP),
   Sabotage (3+2/objective), Vital Link operation markers (2+1/marker), Secure Asset (EOT 4 + destroyed-near-central
   2), Vanguard Operation terrain areas, Extract Relic / Locate and Deny shared relic markers + Sensor Sweep, Smoke
   and Mirrors decoys (2+2, EOG 10 at 4+, enemy-proximity scrub), Surveil (5 VP no-markers), Gather Intel tokens
   (7 VP R2+), Death Trap (2+3/area). Home/Expansion/Central objective designations are assigned per layout and
   drive the central/expansion conditions. **Update 2026-07-03 (player prompts):** the auto-picks are now PLAYER
   CHOICES for a human owner — END_TURN pauses behind a CardActionDialog (single-pick: Triangulate / Consecrate /
   Booby Trap / Sensor Sweep-marker; multi-pick with all pre-selected: Decoy / Extract Intelligence; Skip declines
   the optional action and the auto-pick stands down), and Punishment's Condemn pops a Command-phase revision
   dialog over the auto picks (up-to-3 cap enforced). AI players and headless callers keep the deterministic
   auto-resolve backstop (`MissionManager.get/resolve/decline_card_action_11e`,
   `get/resolve/dismiss_condemn_*_11e`; `card_action_resolved_this_turn` rides the save). Windowed
   `iss064d_triangulate_prompt_11e` / `iss064e_decoy_prompt_11e` / `iss064f_condemn_prompt_11e` /
   `iss064g_card_action_skip_11e` drive the real End Turn button and dialogs; headless
   `test_card_action_prompts_11e` 39/39. **Update 2026-07-04:** the marker state is now VISIBLE — objective badges
   (Triangulated/Consecrated/Decoy/Intel/Op-marker) via `ObjectiveVisual.set_card_action_badges`, Booby-Trap and
   relic-marker badges on terrain via the new `CardActionOverlay` layer, and per-player marker rows in the Scoring
   panel (`iss064h`); and the relic-marker SETUP is now the Disruption player's choice too — auto-pick backstop +
   Command-phase `RelicSetupDialog` revision window that closes at END_COMMAND or the first Sensor Sweep
   (`iss064i`; headless pins in `test_card_action_prompts_11e`, now 58). Still open: disposition is a menu pick
   rather than detachment-derived; 6-objective Inescapable Dominion maps aren't modelled; Vital Link stays fully
   automatic (its Operation Marker has no target choice). **Update 2026-07-04 (per-unit actions):** Sabotage,
   Vanguard Operation and Extract Intelligence are now REAL 16.01 per-unit actions — registered into
   ActionsManager per game for the owning player, started from the Shooting phase Start Action button (an
   ActionChoiceDialog picks between them and Hold Position), completing at end of turn via the ISS-038 hook.
   When the owner uses the action its rule scores from the action state (Extract Intelligence at the sourced
   7 VP per completing UNIT; a moved/failed action scores 0); otherwise the positional approximation remains the
   AI/headless backstop. Windowed `iss064j_mission_action_sabotage_11e` drives the whole flow with real clicks
   (headless pins in `test_card_action_prompts_11e`, 71). Secure Asset is deliberately not an action (its
   modelled hold rule already equals the outcome); Consecrate's killer-unit attribution still needs per-unit
   kill tracking. *(Ref: doc Tab 10 + appendix.)*
2. **[data] 11e secondary mission deck.** *(Done 2026-07-02, approximations flagged:)* the GDM 2026 deck is authored
   from `docs/rules/11th_edition_missions_gdm2026.md` — 18 cards incl. the Fixed four, draw-2-per-turn with no hand
   limit, the fixed-eligibility restriction, and the 45-total/15-per-turn caps. Cards whose full text was unpublished
   (Beacon, Plunder, Burden of Trust, Outflank, A Grievous Blow scoring numbers, Forward Position's Expansion
   alternative) are marked `approximate: true` pending card text; Attacker/Defender variants are not modelled.
   **Update 2026-07-03 (web-sourced):** A Grievous Blow now keys on Starting Strength 13+; Outflank scores 3/5 VP by
   distinct board edges; Beacon scores a surviving unit outside your DZ at the end of the opponent's turn; Forward
   Position's both-Expansion-objectives alternative is live (designations); fixed cards enforce the sourced 20 VP
   per-card cap (`test_gdm_sourced_11e` 20/20). Attacker/Defender variants exist as separate cards upstream but
   their texts were not retrievable — still not modelled. *(Tab 10 + appendix.)*
3. **[data] Support-role datasheets + true 11e stat lines.** *(Partially done 2026-07-02:)* the Bannernob now carries
   `Support` + `leader_data` in orks.json, FormationsPhase enforces the 11e per-role slots (one leader + one support),
   and the flow is windowed-validated (`iss059b_support_attach_11e`). Still open: tag Support characters in other
   factions, and source real 11e **Ld/OC/Invuln** values — note the invuln picture is better than first reported
   (Custodes 4+/Draxus 5+/Beastboss 5+ etc. already present in `meta.stats.invuln`); what's missing is mostly
   orks.json characters (Ghazghkull, Badrukk, Warbosses) and any true-11e deltas, which need an official source
   (PRD §5 open q.2). *(Update 2026-07-03:)* the Tabletop Battles Orks/Custodes faction-pack review snippets yielded
   ability-level changes, not full stat lines — the sourced FRAME keyword was added to the Battlewagon (the only
   FRAME unit present in orks.json); Snikrot/Kommandos ability tweaks and per-datasheet Ld/OC values were not
   retrievable and remain open. *(Tab 1/7; §1, §7 + appendix.)*
4. **[code] Hidden / Gone to Ground / Detection Range.** *(Done 2026-07-02, code side:)* Gone to Ground (−3" → 12"
   behind an intervening dense/Solid feature), the `Detection Range X"` datasheet parser with the 9" floor, and the
   Hidden gate all validated in the live targeting path (windowed `iss052b_gone_to_ground_11e`, 46/46; headless
   `test_iss052_hidden_11e`, 27/27). Remaining: author actual datasheet Detection-Range values once 11e data is
   sourced. *(Tab 6; §6.)*

### Tier 2 — army construction & terrain fidelity
5. **[code] Army construction 11e:** Detachment Points pool (3 @ 2000), Upgrades (non-char, ×3, one enhancement pick),
   enhancement-after-attach sequencing, and the Warlord-must-match-army-faction rule. *(Update 2026-07-03, partial:)*
   `ArmyListManager.validate_army_construction_11e` enforces the sourced rules as warnings — Warlord faction-keyword
   match, enhancement caps (2 per 1000 pts), Upgrade-tag ×3-non-CHARACTER semantics, and the 3-DP pool when army data
   declares DP costs (current army JSONs carry one detachment with no cost). Full DP-based list building UI and
   detachment data authoring remain. *(Tab 1 + appendix.)*
6. **[code+data] Terrain categories & areas:** *(Update 2026-07-03:)* the sourced category definitions (Exposed:
   craters/razorwire/debris; Light: barricades/low walls/statues; Dense: buildings/ruins/containers/woods) MATCH the
   existing `TerrainManager.category_of` derivation exactly — the implementation is now source-validated, and layouts
   can already override per piece via explicit `category`. **Home/Expansion/Central objective designations are DONE**
   (assigned per layout in MissionManager, used by the 11e mission conditions). Remaining: the **Solid** <3"-gap rule
   (no retrievable rule text yet) and authoring multi-feature Terrain-Area boundaries (schema v2). *(Tab 6 + appendix.)*
7. **[code] Cover per attacking model:** *(Done 2026-07-02:)* each attack's BS worsening is computed from its own
   firing model's view of the target (13.08 second condition is per-attack); attacks with no recorded firer (overrides/
   bonus attacks) fall back to the first firer. Pinned in `test_iss047_weapon_abilities_11e` E6. *(Tab 4/6.)*

### Tier 3 — ability/affordance completeness (engine mostly present)
8. **[code] Surge Moves** — *(Code done 2026-07-02:)* `BEGIN_SURGE_MOVE` is template-gated at e11 (stated distance, closest-enemy target, no D6), a `Surge X"` datasheet ability lights up the movement-list offering (`iss040b_surge_move_11e`). Remaining: author a real datasheet with the ability once 11e data is sourced (PRD §5 q.2). *(Tab 8.)*
9. **[code] Hunter X and Heal X** core abilities. *(Update 2026-07-03:)* **Heal X** implemented from the sourced core
   rule (restore a wound, else revive a model at 1 wound, X times; excess wasted) — `RulesEngine.get_heal_amount` /
   `apply_heal_11e`, pinned in `test_gdm_sourced_11e`. **Hunter X**: no rule text exists in ANY available source
   (core-rules deep dives, keyword cheat sheets, faction reviews all silent) — closed as not-in-shipped-rules; will
   revisit if a source ever materialises. *(Tab 8.)*
10. **[code] Combat Disembark** — *(Done 2026-07-02:)* the validator honours "set up **engaged** within 6"" for enemy units the transport is engaged with (and only those); the placement UI gets a Combat Disembark toggle, 6" ring, and matching placement rules. Windowed `iss058b_combat_disembark_engaged_11e` 26/26. *(Tab 3.)*
11. **[code] Explosives / Crushing Impact** — *(Done 2026-07-02:)* the stratagem panel now runs a two-step target prompt (friendly unit, then eligible enemy — engaged for Crushing Impact, within-8"-and-visible for Explosives) and resolves via `use_stratagem` with the chosen enemy in context (`iss047d_crushing_impact_prompt_11e`). *(Tab 8.)*
12. **[code] Modifier-order pipeline** — *(Verified + pinned 2026-07-02:)* halve-after-melta already holds in every
    damage path (interactive allocation, auto-resolve, melee, devastating, overwatch) — confirmed by reading all six
    sites and pinned live (`test_iss047_weapon_abilities_11e` E4). Deferred: consolidating into one shared pipeline and
    set-×/set-0 semantics, which no shipped modifier uses yet. *(Tab 1.)*
13. **[code] Precision** — *(Done 2026-07-02:)* promotion is gated on the character being visible to an attacking model (13.09/13.10/13.11 + LoS), and the attacker chooses the promoted group (or declines) via the AllocationGroupOverlay PrecisionPicker; chosen group rides the save batch (`iss047b_precision_choice_11e`; headless E2 section). *(Tab 8.)*
14. **[code] Melee/Extra-Attacks/Melta polish** — *(Extra Attacks done 2026-07-02:)* the 10e Balance-Dataslate "cannot modify A" suppression is edition-gated off at e11 (Waaagh/Da Biggest bonuses now apply; pinned 10e-vs-11e in `test_iss047` E5). *(Melta order RESOLVED 2026-07-03 by web source:)* the 11e sequence is base damage → add Melta bonus → apply damage-reduction (halve-after-melta) — exactly what the engine already does in all six damage paths (verified + pinned 2026-07-02, `test_iss047` E4). No code change needed; closed. *(Tab 8 + missions doc appendix.)*

### Tier 4 — structural/cosmetic
15. **[code] Fight-phase step structure** — make Pile-In and Consolidation single global both-player steps (active-first)
    rather than per-fighter. *(Update 2026-07-03:)* the 3"-vs-5" Engaging-consolidation question the audit parked is now
    RESOLVED by source: Engaging Consolidation is **3"** (must engage the selected targets; otherwise move toward the
    nearest objective), and consolidation happens **after all fighting across the battlefield, both players, active
    player first**. *(CONSOLIDATION HALF DONE 2026-07-03:)* at e11 the per-fighter consolidate is gone — activations end
    at attack resolution, END_FIGHT enters a global end-of-phase Consolidate step (active player's half first, one
    optional move per eligible unit, `flags.was_eligible_to_fight` stamped in production, 12.08 engaging-mode forced
    fights resolved mid-step), with a `ConsolidationStepDialog` player flow, AI ladder support (`END_CONSOLIDATION`),
    and multiplayer trigger metadata. Validated windowed (`global_consolidation_step_11e`, mouse-only player path incl.
    a new real-input `drag_board` primitive) + headless (`test_global_consolidation_11e`, `_ai_11e`).
    *(PILE-IN HALF DONE 2026-07-04 — item CLOSED:)* the fight phase now OPENS with the global Pile In step (12.02):
    active player's half first, one optional move per eligible unit (engaged/charged), END_PILE_IN passes,
    SELECT_FIGHTER gated until the step ends, `PileInStepDialog` player flow, AI ladder + multiplayer metadata. The
    12.06 overrun fight is now DISTINCT: normal fights get no mid-activation pile-in; overrun-eligible units
    (unengaged, or engaged but unengaged at the Fight-step start) get one additional pile-in move on selection
    (`selected_for_overrun_fight` now set in production). Validated windowed (`global_consolidation_step_11e` covers
    both global steps mouse-only) + headless (`test_global_pile_in_11e`). *(Tab 5 + appendix.)*
16. **[code] End-of-turn coherency removal dialog** — *(Done 2026-07-02:)* END_TURN pauses for human-owned incoherent units; the CoherencyRemovalDialog lets the player pick each removed model, and the turn auto-completes once coherent (`iss042b_coherency_removal_choice_11e`). Auto-pick stays as the AI/backstop. *(Tab 3.)*
17. **[code] `[DEVASTATING WOUNDS]` / `[LETHAL HITS]` attacker-choice prompts** — *(Done 2026-07-02:)* the AbilityChoiceDialog offers both choices when a DW weapon is assigned; choices ride the assignment into all three resolution paths, incl. the new 24.10 decline (`iss047c_ability_choice_prompts_11e`; headless E3). *(Tab 4/8.)*

---

## 11. Bottom line

**Status 2026-07-03 (post-GDM-missions):** the mission system is no longer unbuilt — with the GDM 2026 document now
in-repo, Tier-1 #2 (secondary deck, 2026-07-02) and the core of Tier-1 #1 (Force Dispositions, the 25-card pairing
table, per-player primary scoring with 45/15 caps and the R5 EOT switch, 2026-07-03) are implemented and validated
windowed + headless, with unpublished card components flagged `approximate` and scoring 0 rather than invented.
Earlier sweep results stand: Tier-1 #3 (Support attach) and #4 (Hidden/Gone to Ground/Detection Range)
code-complete; Tier-3 #7, #8, #10, #11, #12, #13, #14 (Extra Attacks), #16, #17 landed; delta-audit B6 closed.
**2026-07-03 web-source recovery:** the previously source-blocked card mechanics were recovered from
gdmissions.app/Tabletop Battles snippets (appendix in the missions doc) and implemented — all 25 primary cards now
score their sourced conditions with auto-resolved marker actions, the secondary corrections (Grievous Blow SS13+,
Outflank edges, Beacon, Forward Position expansions, fixed 20-per-card cap) are in, Home/Expansion/Central
designations exist per layout, Heal X is implemented, and army-construction rules validate as warnings. What
remains **genuinely blocked**: Hunter X (no rule text exists anywhere — presumed not shipped), secondary
Attacker/Defender variant texts, true 11e stat lines and Support tags for other factions (#3, PRD §5 open q.2),
Melta "post-order" (#14 remainder, deep-dive only), terrain Exposed/Light/Dense category authoring (#6 remainder),
DP costs per detachment + list-building UI (#5 remainder) — plus #15's fight-step restructure, which the audit
itself parks pending a GW FAQ on the 3"-vs-5" Engaging consolidation. *(Resolved 2026-07-03: player-choice prompts
for the auto-resolved card actions are DONE — CardActionDialog at end of turn + Condemn revision dialog in the
Command phase, with the deterministic auto-resolve kept as the AI/headless backstop. Resolved 2026-07-04: the
Extract Relic / Locate and Deny five-marker SETUP choice is a player prompt too, and all marker state renders on
the board + Scoring panel.)*

The **core engine** of 11th edition is in and genuinely playable at `edition == 11`: the new attack/allocation model,
cover-as-BS, engagement 2" / coherency 9", the move-type framework incl. FLY, the select-after-roll charge, the
active-first Fight sequencer, terrain-as-objectives with per-phase control, battle-shock, disembark modes, two-slot
attach, and the hazard/indirect/hazardous/heavy fixes all validate live or in the windowed suite. The **11e mission
system now runs end to end** — dispositions in the menu, the 25-card pairing table, per-player primary scoring with
the GDM caps/timing, and the 18-card secondary deck — with the bespoke card actions the only unbuilt part (no
published text). The **residual gap is concentrated in**: (1) those **card action mechanics** plus mission-facing
terrain designations (Home/Expansion/Central); (2) full **terrain-category / Solid** fidelity; and (3) **content** —
Support datasheets, true 11e stat lines, Upgrades/Detachment-Points army building, and the Hunter/Heal/Surge
abilities that no shipped datasheet yet uses. Tiers 1–2 above are what stand between "the 11e rules engine runs" and
"a player plays a complete, rules-accurate 11th-edition game."

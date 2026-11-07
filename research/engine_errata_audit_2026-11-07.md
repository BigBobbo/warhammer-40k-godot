# Engine errata audit — 2026-11-07

Read-only audit: does the engine implement each item in `docs/rules/40k_11th_edition_errata_faq_commentary.md` (official 11e errata, FAQ and designer commentary, which win over the launch rules)?
One finder per chapter group, then a refute-first verifier per gap. Details: [engine_errata_audit_2026-11-07_details.md](engine_errata_audit_2026-11-07_details.md); data: [engine_errata_audit_2026-11-07.json](engine_errata_audit_2026-11-07.json).

## Summary

- Items checked: **199** — implemented 98, partial 51, no_engine_surface 27, wrong 12, missing 8, unclear 3.
- Gaps raised: 74; confirmed by the verifier: **72** (high 14, medium 33, low 25); refuted: 2.
- Player-visible confirmed gaps: 64.
- Several gaps describe one defect from different rules (e.g. a wiped bodyguard dissolving the Attached unit; [HAZARDOUS] spill-over; take to the skies). They are listed separately here and grouped when fixed.

## Confirmed gaps

| id | sev | ref | gap | player-visible | files |
|---|---|---|---|---|---|
| EA-01 | high | 01.02.01 Starting Strength and Half-Strength | A leader whose bodyguard is wiped out is judged on its own wounds, so it never takes the half-strength battle-shock test | yes | CharacterAttachmentManager.gd, CommandPhase.gd, GameState.gd |
| EA-02 | high | 01.06 (outside the assigned 02.01-03.04.01 range; found while auditing the 02.02.01 Ld limits) | Attached-unit leadership rolls use the WORST Ld instead of the best | yes | CommandPhase.gd |
| EA-03 | high | 04.01.02 | [CLOSE-QUARTERS]/[PISTOL] either/or not enforced in normal/assault/indirect shooting | yes | NormalShooting.gd, RulesEngine.gd, ShootingController.gd, ShootingPhase.gd |
| EA-04 | high | 04.01.03 | Models fire every profile of a multi-profile ranged weapon | yes | RulesEngine.gd, ShootingController.gd, ShootingPhase.gd |
| EA-05 | high | 05.04.01 | Engine-side melee saves (AI defender / auto-allocate) never reach the attached CHARACTER | yes | Allocation.gd, FightPhase.gd, RulesEngine.gd |
| EA-06 | high | 05.04.04 | Attached unit treated as destroyed once its bodyguard models die: remaining weapons skipped | yes | CharacterAttachmentManager.gd, FightPhase.gd, ShootingPhase.gd |
| EA-07 | high | 06.03 FAQ (allocation of [HAZARDOUS] mortal wounds) | [HAZARDOUS] mortal wounds all go to one bearer model, with no spillover | yes | FightPhase.gd, RulesEngine.gd, ShootingPhase.gd |
| EA-08 | high | 09.02.02 Commentary (conditions labelled with a mode) / 09.07 WHILE MOVING | Ordered Retreat fall-backs can move through enemy models | yes | FallBackMove.gd, MovementController.gd, MovementPhase.gd |
| EA-09 | high | 15.01 FAQ (optional +1CP section) | Heroic Intervention's Into the Fray costs 1CP instead of 2CP | yes | ChargePhase.gd, HeroicInterventionDialog.gd, StratagemManager.gd |
| EA-10 | high | 17.01 (launch text, context for the 17.01 FAQ; not an update item) | MONSTER/VEHICLE normal/advance moves cannot pass through enemy non-M/V models | yes | MovementPhase.gd |
| EA-11 | high | 19.01.01 Commentary (and the 19.01 'single unit' rule) | Wiping the bodyguard dissolves the Attached unit into separate units | yes | CharacterAttachmentManager.gd, CommandPhase.gd, FightPhase.gd, GameState.gd, RulesEngine.gd, ShootingPhase.gd |
| EA-12 | high | 21.03 FAQ (take to the skies effects only when declared) | FLY units get take-to-the-skies benefits on normal/advance/fall-back moves without declaring it | yes | MovementPhase.gd |
| EA-13 | high | 21.03 FAQ (take to the skies on charge moves) | Charges have no take-to-the-skies declaration or -2"; FLY chargers get 10e fly benefits automatically | yes | ChargeController.gd, ChargeMove11e.gd, ChargePhase.gd, TerrainManager.gd |
| EA-14 | high | 23.04 FAQ ([HAZARDOUS] mortal wounds; same as 06.03 FAQ) | Hazardous mortal wounds forced onto the hazardous-weapon bearer, no spill-over | yes | Allocation.gd, FightPhase.gd, RulesEngine.gd, ShootingPhase.gd |
| EA-15 | medium | 01.02.02 Persisting Rules Effects | MORTIS SNARES snare stays active until something triggers it instead of ending with its trigger period | yes | BasePhase.gd, RULINGS.md, SMCodexACommand.gd |
| EA-16 | medium | 01.02.02 Persisting Rules Effects | Da Jump's granted Deep Strike lasts across turns until the unit arrives | yes | GameState.gd, OrkAbilities11e.gd |
| EA-17 | medium | 01.02.03 Revived and Adding Models to a Unit | Models revived by healing reappear where they died, ignoring the 01.02.03 set-up rules | yes | OrkAbilities11e.gd, OrkCodexMovement.gd, SMAbilitiesA.gd, SMAbilitiesC.gd, SMDetachmentsB.gd, SWAbilities11e.gd |
| EA-18 | medium | 01.02.06 Splitting Units | Splitting Kommandos with an attached leader (Taktikal Know-wotz) copies the leader into both halves | yes | DeploymentController.gd, GameState.gd |
| EA-19 | medium | 01.04.05 Table Quarters | Table-quarter scoring tests model centres against shared centre lines, ignoring base size and the 1 mm dividing line | yes | MissionManager.gd, SecondaryMissionManager.gd |
| EA-20 | medium | 01.05.02 | Wound re-rolls (Twin-linked, 'failed'/'all' grants) choose dice by raw roll vs the S/T threshold, ignoring wound modifiers and Anti-X crits | yes | AttackSequence.gd, RulesEngine.gd |
| EA-21 | medium | 01.06.01 | Leadership / battle-shock roll of an Attached unit uses the worst Ld instead of passing against any model's Ld | yes | CommandPhase.gd, FactionAbilityManager.gd, RULINGS.md, SMAbilitiesC.gd |
| EA-22 | medium | 01.07 | Battle-shocked CONSERVAI / Tactical Mainstay units always fail the action they started | yes | ActionsManager.gd, MissionManager.gd, PhaseManager.gd, RULINGS.md, test_iss057_actions_11e.gd |
| EA-23 | medium | 02.02 (FAQ: charge-roll / max-distance modifiers vs charge targets) | Charges cannot take to the skies; FLY chargers get its benefits without the -2in | yes | ChargeMove11e.gd, ChargePhase.gd, MoveType.gd |
| EA-24 | medium | 02.02.01 | Hit/wound modifiers are netted by sign presence, not by their cumulative total | yes | AttackSequence.gd, ModifierStack.gd, RulesEngine.gd |
| EA-25 | medium | 02.02.01 | Modified BS (and Ld) are not clamped to 2+..6+ (Ld 5+..8+) | yes | AttackSequence.gd, CommandPhase.gd, RulesEngine.gd |
| EA-26 | medium | 02.02.04 | Unit heals can revive destroyed CHARACTER models; model heals act on the whole unit | yes | OrkAbilities11e.gd, SMAbilitiesA.gd, SMAbilitiesC.gd, SMDetachmentsB.gd, SWAbilities11e.gd |
| EA-27 | medium | 03.01.01 | Attached units move every model, leader included, on the bodyguard's M | yes | MovementPhase.gd |
| EA-28 | medium | 03.01.02 | FLY units move through enemy (and MONSTER/VEHICLE) models without taking to the skies | yes | MovementPhase.gd |
| EA-29 | medium | 03.02.02 | No set-up exceptions for oversized models (disembark within 1in, touch the battlefield edge) | yes | DisembarkMove.gd, IngressMove.gd, MovementPhase.gd, TransportManager.gd |
| EA-30 | medium | 03.03 (FAQ: single contiguous group) | Coherency accepts units split into several groups | yes | AttackSequence.gd |
| EA-31 | medium | 03.03.01 | Move-phase coherency ignores attached CHARACTER models; 11e ingress set-up skips the engine coherency check | yes | AttackSequence.gd, MovementPhase.gd |
| EA-32 | medium | 04.02 FAQ | Unit-level target check requires one enemy model to be both in range and visible | yes | RulesEngine.gd |
| EA-33 | medium | 04.03.02 | A model cannot split one melee weapon's attacks between several engaged targets | yes | AttackAssignmentDialog.gd, FightPhase.gd, RulesEngine.gd |
| EA-34 | medium | 04.03.03 | Weapons whose target stops being eligible are skipped instead of re-targeted | yes | FightPhase.gd, RulesEngine.gd, ShootingPhase.gd |
| EA-35 | medium | 06.01 FAQ (LoS from any part of the observing model) | Cover's 'fully visible' check and Explosives' 'visible' check use only the attacker's base centre | yes | RulesEngine.gd, StratagemManager.gd, TerrainManager.gd |
| EA-36 | medium | 09.07.01 Commentary (one hazard roll per model) — Attached units | Desperate Escape by an Attached unit rolls and allocates for the bodyguard's models only | yes | FallBackMove.gd, MovementPhase.gd, SMCodexAMovement.gd |
| EA-37 | medium | 13.01 FAQ (within a terrain area) / 13.08 first bullet | Benefit of cover's in-area test uses the base centre, not any part of the base | yes | AIDecisionMaker.gd, LOSLineVisual.gd, TerrainManager.gd |
| EA-38 | medium | 13.08 FAQ (cover per attacking model) | Rapid Fire, Blast and +A bonus attacks take the first firing model's cover | yes | RulesEngine.gd |
| EA-39 | medium | 14.02.01 Commentary | Objective control is settled after end-of-phase/turn rules instead of before them | yes | ChargePhase.gd, FightPhase.gd, MissionManager.gd, MovementPhase.gd, PhaseManager.gd, ScoringPhase.gd |
| EA-40 | medium | 16.01 FAQ | Actions by units allowed to act while battle-shocked still fail on battle-shock | yes | ActionsManager.gd, CustodesKatah.gd, MissionManager.gd, RULINGS.md, SMAbilitiesB.gd |
| EA-41 | medium | 18.04.01 Commentary | Rapid disembark after an ingress move ignores the transport's ingress restrictions | yes | DisembarkController.gd, IngressMove.gd, MovementPhase.gd |
| EA-42 | medium | 18.05 Errata (filed under 17.03) | Emergency disembark destroys models instead of setting them up engaged | yes | RulesEngine.gd |
| EA-43 | medium | 19.04 FAQ (single-model rules such as Feel No Pain) | An attached CHARACTER's own Feel No Pain is not used while he is attached | yes | RulesEngine.gd |
| EA-44 | medium | 19.04.01 Commentary | Dead leaders keep conferring abilities and enhancements (Custodes, Space Marines and Space Wolves modules) | no | CustodesAbilities.gd, CustodesCommon.gd, CustodesEnhancements.gd, SMAbilitiesA.gd, SMDetachmentsA.gd, SWAbilities11e.gd |
| EA-45 | medium | 21.03 FAQ (declare before the advance roll) | Take to the skies can be declared or withdrawn after the advance roll | yes | MovementController.gd, MovementPhase.gd |
| EA-46 | medium | 24.28.01 Commentary | [PRECISION] + [DEVASTATING WOUNDS] mortal wounds skip the selected CHARACTER group | yes | Allocation.gd, RulesEngine.gd |
| EA-47 | medium | FAQ under 11.03 (a 'can move up to X"' consolidation rule changes the maximum distance) | Consolidation validator ignores consolidation-distance bonuses such as TACTICAL FOCUS | yes | FightController.gd, FightPhase.gd, SMCodexAMovement.gd |
| EA-48 | low | 01.02.02 Persisting Rules Effects | Damocles-class Uplink doctrine lasts until the next Command phase instead of ending with that Movement phase | yes | SMDetachmentsA.gd, SWArmyRules11e.gd |
| EA-49 | low | 01.04.02 Closest Or Nearest Model/Unit | Pile-in and consolidation don't fix each model's closest target; surge ties are picked automatically | no | ConsolidationMove.gd, PileInMove.gd, SurgeMove.gd |
| EA-50 | low | 01.05.02 | An Advance die can be re-rolled twice: automatic ability re-roll, then Command Re-roll | yes | MovementPhase.gd |
| EA-51 | low | 01.07.02 | Module 'battle-shock rolls' skip Tempered in Battle's leadership-roll re-roll, which forced 'Battle-shock tests' get | yes | CustodesAbilities.gd, FactionAbilityManager.gd, OrkAbilities11e.gd, SMAbilitiesC.gd |
| EA-52 | low | 02.01.01 | A datasheet name only counts as a keyword when the data happens to list it | yes | CustodesCommon.gd, RulesEngine.gd, SWCommon.gd |
| EA-53 | low | 02.02.01 | Modified charge roll is not capped at 12in | yes | ChargePhase.gd |
| EA-54 | low | 02.02.01 | AP improvement vs worsening is applied in a different order depending on the resolution path | no | EffectPrimitives.gd, RulesEngine.gd |
| EA-55 | low | 02.02.03 | Random S characteristics are parsed to a flat S3 | yes | RulesEngine.gd |
| EA-56 | low | 03.02.03 | Redeploy rules are not playable, and the redeploy validator skips normal deployment rules | yes | AIDecisionMaker.gd, Main.gd, RedeploymentPhase.gd |
| EA-57 | low | 04.03.01 | Identical attacks from different weapons are never gathered into one batch | no | AttackSequence.gd, RulesEngine.gd, ShootingPhase.gd |
| EA-58 | low | 04.03.05 | A fight activation that makes no attacks still counts as 'has fought / has attacked' | yes | FightPhase.gd, SMAbilitiesC.gd |
| EA-59 | low | 05.03 FAQ1 | Allocation validator rejects every order when two non-CHARACTER groups are wounded (latent soft-lock) | no | Allocation.gd, AllocationGroupOverlay.gd |
| EA-60 | low | 05.04.04 | Destroyed-model triggers (Deadly Demise, transport destruction) resolve mid-activation | yes | FightPhase.gd, ShootingPhase.gd |
| EA-61 | low | 05.04.06 | Measuring to a destroyed unit uses every model's stored position, not the last model destroyed | yes | MissionManager.gd, RulesEngine.gd |
| EA-62 | low | 09.05.01 Commentary (one Normal Move per phase) | Reactive normal moves are not limited to one Normal Move per phase | yes | MovementPhase.gd, SMCodexAMovement.gd, SMCodexBAction.gd, ShootingPhase.gd |
| EA-63 | low | 09.07.01 / 09.02.02 — fall-back moves made outside the Movement phase | Tactical Fluidity's fall-back ignores fall-back modes; WIND-SWIFT EVASION's Desperate Escape skips the battle-shock roll | yes | RULINGS.md, SMAbilitiesB.gd, SMCodexAMovement.gd |
| EA-64 | low | 12.08 Errata (Ongoing Consolidation forced fights) | Forced fights after consolidation key on 'was eligible' instead of 'selected to fight', and also fire after Objective consolidations | yes | FightPhase.gd |
| EA-65 | low | 12.08 Errata (Ongoing: each model that started engaged stays engaged) | 'Each model that started engaged must still be engaged' is checked per unit, not per model | no | ConsolidationMove.gd, FightPhase.gd |
| EA-66 | low | 13.06.01 Commentary (Solid terrain and movement) | INFANTRY can end a move inside a Solid wall and then see through it | yes | Measurement.gd, MovementPhase.gd, TerrainManager.gd, take_and_hold_mirror_1.json |
| EA-67 | low | 13.11.01 Commentary (Gone to Ground) | Dense terrain-area boundaries count as dense features for Gone to Ground | yes | TerrainManager.gd |
| EA-68 | low | 17.03 Errata ([BLAST] vs engaged MONSTER/VEHICLE) | AI atomic SHOOT can fire [BLAST] at an M/V engaged only with the shooter | yes | AIDecisionMaker.gd, RulesEngine.gd, ShootingPhase.gd |
| EA-69 | low | 18.02.01 Commentary (all embark conditions) | Embark range ignores the attached CHARACTER's models and is not re-validated server-side | no | MovementPhase.gd, TransportManager.gd |
| EA-70 | low | 19.03 FAQ (keywords of destroyed models) | A destroyed attached CHARACTER still lends its keywords to the unit | no | CharacterAttachmentManager.gd, CustodesCommon.gd, RulesEngine.gd, SWDetachments11e.gd |
| EA-71 | low | 23.04 FAQ (Scouts alternate) | Scout moves are resolved player by player instead of alternating | yes | ScoutPhase.gd |
| EA-72 | low | 24.24.01 (cross-check requested under 02.02.01) | Lone Operative reactivates per character after the bodyguard dies, even beside a non-LO leader or support | yes | CharacterAttachmentManager.gd, OrkAbilities11e.gd, RulesEngine.gd |

## Refuted

- **05.04.04** — Every destroyed unit is credited as 'destroyed by' the opponent. Verifier: The engine does what the auditor says, but the rule ruling behind the claim is wrong.  Engine behaviour, confirmed: every wiped unit is credited to its owner's opponent, whatever destroyed it. This happens at ShootingPhase.gd:333-342 (Hazardous diffs reach this hook), FightPhase.gd:429-434, ScoringPhase.gd:1009-1013 and the end-of-turn recount at MissionManager.gd:1408-1422 (which also catches Desperate Escape and coherency wipes). The kill primaries read these counters at MissionManager.gd:2706-2717 and 3270-3275.  Why 05.04.04 does not apply here: 1. The commentary (errata doc line 395) defi
- **13.11.01 Commentary (Gone to Ground, designer's note)** — Units that shot and used Shadow Masters 'Stay hidden' still go to ground. Verifier: Refuted for the checked-out engine (HEAD b48b429, branch claude/affectionate-brown-rr3zen). The auditor read an older snapshot.  Rule: the 13.11.01 Commentary (docs/rules/40k_11th_edition_errata_faq_commentary.md:539) says a model goes to ground only if its unit made no ranged attacks this turn or the previous turn. Its Designer's Note says this holds even for units with abilities that let them shoot and stay hidden. The launch text (core rules 13.09, lines 2292-2303) has no Gone to Ground rule at all.  What HEAD already does: - 40k/scripts/rules/HiddenShotRecord.gd keeps a separate stamp, F_A

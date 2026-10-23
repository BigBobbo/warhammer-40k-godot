# Codex: Space Marines (11e) — M4b datasheet + wargear ability audit (WP-M4b)

Source: `space-marines/SPACE_MARINES_GENERIC.md` § "Datasheet abilities"
(printed text) for the 29 M4b datasheets of PLAN_SPACE_MARINES.md, plus the
Librarius budget they spend. Scope: SM-D1 — every Space Marine army
(`SWCommon.is_sm_army`), 11e only; and only these datasheets (gated by
datasheet name, because M4a / M4c own the same ability names on other
datasheets — Strategic Acumen, Litany of Hate, Raise the Banner, Teleport
Homer, Assault Ramp, Librarian / Psychic Hood).

"Before" = the game at base 581a52e: a grep of UnitAbilityManager /
RulesEngine / FactionAbilityManager / EffectPrimitives found **no handler**
for any of these names (Litany of Hate / Haywire Mine rows existed only for
the Space Wolves datasheets, condition `sw11e`, gated on SPACE WOLVES). The
two game-dispatched names the import report lists for the Intercessor Squad —
**Objective Secured** (sticky objectives) and **Target Elimination** (+2 A
bolt rifles) — are 10e index abilities no codex datasheet carries: Objective
Secured is retired for 11e Space Marine armies (`has_sticky_objectives_ability`
guard; 10e keeps it), Target Elimination's `on_shooting_selection` condition
was never evaluated (dead row; commented).

Code: `40k/scripts/codex/space_marines/SMAbilitiesB.gd` (one module, thin
commented `WP-M4b` hooks elsewhere). Tests: `40k/tests/test_sm11e_abilities_b.gd`
(section numbers in the last column). Windowed scenarios:
`40k/tests/scenarios/sp/sm11e_ab_b_*.json`.

Core abilities on these datasheets — Leader, Support, Deep Strike, Scouts 6",
Infiltrators, Stealth, Deadly Demise, Damaged, Firing Deck 7, TRANSPORT — are
engine-handled; §0 checks they resolve. Faction abilities Combat Doctrines,
Transhuman Strategist and Librarius (army rule) are WP-M2a's; the psyker
budget is implemented here against the printed rule (see the ruling).

Activated abilities are free "Ability" cards in the stratagem-window dialog
(`sm11e_ab_b_<slug>`, cp 0, `is_ability: true`), the WP-C7 / WP-S4 pattern;
the AI scores them synchronously (`ai_score`).

| datasheet | ability | printed text (short) | before | WP-M4b implementation | test |
|---|---|---|---|---|---|
| Intercessor Squad | Bolter Discipline | your Shooting phase: ranged +1 to hit if this unit or the target is within range of an objective | none | `attack_mods` (+1 hit, own Shooting phase only) | §3 |
| Intercessor Squad | Tactical Mainstay | engaged / battle-shocked does not prevent starting an action; starting one does not prevent shooting | none | ActionsManager hooks (can_start_action, start_action skips `cannot_shoot`) | §16 |
| Intercessor Squad | (wargear) Grenade Launcher / Sergeant swaps | per-model loadout | every model reported every melee option (kit id "close-combat-weapon" ≠ "Knives and Fists") | resolver alias table + per-model resolution | §2 |
| Incursor Squad | Divinator-class Auspexes (once per phase, per unit) | your Shooting phase, a friendly ADEPTUS ASTARTES unit selected to shoot: a visible enemy within 18" of this unit is scanned (ranged attacks vs it re-roll hit 1s) | none | `unit_selected_to_shoot` card (any friendly AA shooter) + picker; `sm11e_ab_scanned` until end of phase; aggregator re-roll 1s | §10, scenario `sm11e_ab_b_selected_to_shoot` |
| Incursor Squad | Haywire Mine (once per battle, per unit) | your Shooting phase: visible enemy within 6", D6 2+: D3 MW (2D3 vs VEHICLE) | none (SW row only) | `phase_start` (Shooting) + own `unit_selected_to_shoot` card + picker; UAM once-per-battle ledger | §9, scenario `sm11e_ab_b_shooting_cards` |
| Incursor Squad | per-model weapons | "known not to resolve per model" | default kit = menu (correct, logged "left unresolved" only because nothing to narrow) | verified per model; no wargear options exist | §2 |
| Scout Squad | Flexible Asset | advance / fall-back does not prevent starting an action | none | ActionsManager + MovementPhase (cannot_start_action) hooks | §16 |
| Scout Squad | (wargear) Shotgun / Sniper / Heavy weapon | per-model loadout | Shotgun (granted by two swaps) left the unit unresolved (every model every gun) | resolver: ambiguous grants placed by option order | §2 |
| Bladeguard Ancient | Raise the Banner | end of your Movement phase, controlling an objective: secured | none | MovementPhase end hook → MissionManager.secure_objective (14.03) | §15 |
| Bladeguard Ancient | Deeds of Legend | within range of an objective: melee +1 A | none | `attack_mods` | §3 |
| Captain in Gravis Armour | Strategic Acumen | your Command phase: a doctrine active for this unit until your next Command phase | none | `phase_start` (Command) card with three doctrine options; per-unit SWCommon doctrine key + expiry; records the SWCommon Strategic Acumen ledger | §6, scenario `sm11e_ab_b_command_cards` |
| Captain in Gravis Armour | Refuse to Yield | attacks allocated to this model -1 D | none | RulesEngine per-model damage hook (beside Praesidium Shield) | §4 |
| Captain in Gravis Armour | per-model weapons | default MC Heavy Bolt Rifle + MC Power Weapon | single model reported all 7 options | resolver: silent wargear = printed default kit | §2 |
| Chaplain | Litany of Hate | melee [LANCE] | none (SW row only) | `attack_mods` +1 to wound after a charge (whole Attached unit) | §3 |
| Chaplain | Spiritual Leader (once per battle round, per unit) | start of any phase: a friendly battle-shocked AA unit within 6" is no longer battle-shocked | none | `phase_start` card (any phase, either turn) + picker | §7, scenario `sm11e_ab_b_command_cards` |
| Heavy Intercessor Squad | Unyielding in the Face of the Foe | controlling an objective: +1 to save rolls | none | RulesEngine save_modifier (4 save paths) before the ±1 cap | §4 (A/B) |
| Terminator Squad | Teleport Homer (once per battle, per unit) | start of the battle: token; RAPID INGRESS -1 CP, set up within 3" of it and not within 8" of an enemy; removed by an enemy ending a move within 1" | none | round-1 `phase_start` card + objective-spot picker; Rapid Ingress placement hook (within 3" replaces the edge rules) + 1 CP refund; removal check at every phase end | §18, scenario `sm11e_ab_b_teleport_homer` |
| Terminator Squad | Fury of the First | attacks vs a unit within 9": +1 AP | none | `attack_mods` | §3 |
| Lieutenant / Lt in Phobos Armour | Demi-company Commander (once per turn, per unit) | a friendly Captain uses Strategic Acumen: that doctrine is active for this unit | none | re-offered card after a Strategic Acumen this phase (SWCommon ledger, any package's Captain can write it) | §6, scenario `sm11e_ab_b_command_cards` |
| Lieutenant / Lt in Phobos Armour | Tactical Precision | [LETHAL HITS: non-MONSTER/VEHICLE] | none | `attack_mods` `lethal` vs non-M/V targets | §3 |
| Lieutenant | Storm Shield (wargear) | this model has a 4+ InSv | none | army load (ArmyListManager hook) | §20 |
| Lieutenant / Lt in Phobos | per-model weapons | default kit | single model reported every option | resolver default kit | §2 |
| Assault Intercessor Squad | Targeted Intercession | charged: melee +1 S and +1 AP | none | `attack_mods` | §3 |
| Storm Speeder Thunderstrike | Thunderstrike | ranged vs MONSTER/VEHICLE +1 to wound | none | `attack_mods` | §3 |
| Storm Speeder Thunderstrike | Shattered Defences | when this unit has shot: a M/V unit hit — friendly AA ranged attacks vs it +1 AP | none | `unit_has_shot` card + picker (M/V hit); `sm11e_ab_shattered` until end of phase | §12 |
| Chief Librarian Tigurius | Chief Librarian (psyker level 3) | psychic abilities | none | Librarius budget level 3 | §0, §5 |
| Chief Librarian Tigurius | Hood of Hellfire | FNP 4+ vs psychic attacks and mortal wounds | none | RulesEngine `_conditional_fnp` hook (whole Attached unit) | §4 |
| Chief Librarian Tigurius | Prescience (psychic level 2) | your Movement phase: psychic roll; +1 Sv until your next turn | none | `phase_start` (Movement) + own move-end card; Sv characteristic −1 on every component, restored at your next Command phase | §5, §8, scenario `sm11e_ab_b_movement_cards` |
| Chief Librarian Tigurius | Telepathic Assault (psychic level 1) | your Shooting phase: visible enemy within 24" suffers 2D3 MW | none | `phase_start` (Shooting) + own `unit_selected_to_shoot` card + picker | §9, scenario `sm11e_ab_b_shooting_cards` |
| Gladiator Reaper | Reaping Tally | ranged vs non-M/V +1 AP | none | `attack_mods` | §3 |
| Eliminator Squad | Chameleoline Cloaks | -3" detection range | none | TerrainManager detection hook | §4 |
| Eliminator Squad | Special-issue Optics and Ammunition | selected to shoot: [IGNORES COVER]; or an enemy within 24" +6" detection range until this unit has shot | none | `unit_selected_to_shoot` card with two options; ShootingPhase "has shot" hook ends both | §11, scenario `sm11e_ab_b_selected_to_shoot` |
| Gladiator Valiant | Priority Target Acquisition | ranged vs a unit within 12" +1 S | none | `attack_mods` | §3 |
| Hellblaster Squad | Rites of Thermal Appeasement | +1 to hazard rolls for Plasma Incinerator / Plasma Pistol | none | RulesEngine.resolve_hazardous_check hook | §19 (A/B) |
| Aggressor Squad | Close-quarters Firestorm | attacks vs an enemy within 9" +1 S | none | `attack_mods` | §3 |
| Adrax Agatone | Lord of the Pyroclasts | an enemy engaged with this unit -1 OC | none | MissionManager.model_oc hook | §4 |
| Adrax Agatone | Unto the Anvil | melee re-roll wound 1s; assault doctrine: re-roll wounds | none | `attack_mods` (reads SWCommon.doctrine_active) | §3 |
| Darnath Lysander | Rampart (once per battle, per army) | start of any phase: this model 2+ InSv until end of phase | none | `phase_start` card (any phase); model invuln with backup, restored at the phase end; army ledger | §8, scenario `sm11e_ab_b_movement_cards` |
| Darnath Lysander | Icon of Obstinacy | attacks that target this unit -1 to hit | none | `attack_mods` (target side, whole Attached unit) | §3 |
| Land Raider Redeemer | Assault Ramp | ends a normal move: embarked units make an assault disembark move | none | DisembarkMove.select_mode → `assault` after the Redeemer's normal move | §17 |
| Land Raider Redeemer | Wrath of the Machine Spirit | ranged vs a unit within 12": [DEVASTATING WOUNDS: non-M/V] | none | `attack_mods` `devastating` | §3 |
| Land Raider Redeemer | per-model weapons + options | default Flamestorm Cannons + Twin Assault Cannon; HK / Multi-melta / Storm Bolter optional | single model reported every option | resolver default kit / wargear | §2 |
| Sternguard Veteran Squad | Veteran Marksmen | ranged re-roll hit 1s | none | `attack_mods` | §3 (A/B) |
| Librarian | Librarian (psyker level 1) | psychic abilities | none | Librarius budget level 1 | §0 |
| Librarian | Psychic Hood | FNP 4+ vs psychic attacks | none | `_conditional_fnp` hook | §4 |
| Librarian | Veil of Time (psychic level 1) | selected to advance: psychic roll; advance roll changed to a 6 | none | `unit_selected_to_move` (advance) card; MovementPhase advance-roll hook (Shokk-boosta pattern) | §14 |
| Librarian | Force Dome (psychic level 1) | your Movement phase: psychic roll; 4+ InSv until your next turn | none | `phase_start` (Movement) + own move-end card; model invuln on the Attached unit, restored at your next Command phase | §8, scenario `sm11e_ab_b_movement_cards` |
| Desolation Squad | Targeter Optics | ranged vs a visible enemy: [IGNORES COVER] | none | `attack_mods` `ignores_cover` | §3 |
| Desolation Squad | (wargear) Vengor / Superkrak | per-model loadout | Vengor (two Sergeant swaps) left the unit unresolved | resolver: rank-and-file take the "any model" swap first; ambiguous grants by option order | §2 |
| Tor Garadon | Siege Captain | this model's attacks vs FORTIFICATION/M/V +2 S, AP, D | none | `attack_mods` (Tor's own attacks) | §3 |
| Tor Garadon | Signum Array | your Shooting phase: visible enemy within 18" cannot have the benefit of cover | none | `phase_start` + own `unit_selected_to_shoot` card + picker; `sm11e_ab_signum` until end of phase → `ignores_cover` for every attack vs it | §11, scenario `sm11e_ab_b_shooting_cards` |
| Impulsor | Rapid Disembarkation | ends an advance move: shock disembark | none | TransportManager / DisembarkMove eligibility + mode `rapid` (3", cannot charge) | §17 |
| Impulsor | Orbital Comms Array (wargear) | Scouts 6" | none | army load adds the Scouts 6" ability | §20 |
| Impulsor | Shield Dome (wargear) | 5+ InSv | none | army load: model invuln 5 | §20 |
| Impulsor | per-model weapons | default Storm Bolters | every option ("storm-bolter-impulsor" ≠ "Storm Bolters") | resolver alias + default kit | §2 |
| Ancient in Terminator Armour | Raise the Banner | (as above) | none | (as above) | §15 |
| Ancient in Terminator Armour | Never Shall the Standard Fall | within range of an objective: S > T attacks -1 to wound | none | RulesEngine wound-penalty hook | §4 |
| Astraeus | Suppression Fire | when this unit has shot: a unit hit by the Twin Macro-accelerator Cannon is suppressed (-1 to hit) until your next turn | none | `unit_has_shot` card; ShootingPhase post-shot ctx gains `hit_by_weapon` (RulesEngine to_hit blocks carry weapon_id) | §12 |
| Astraeus | per-model weapons + options | default kit; Plasma Eradicators / Twin Lascannon | single model reported every option | resolver default kit / wargear | §2 |
| Captain in Phobos Armour | Strategic Acumen | (as above) | none | (as above) | §6 |
| Captain in Phobos Armour | Tactical Fluidity (once per battle round, per unit) | has shot, unengaged: normal move up to D6"; or end of opponent's Fight phase, engaged: fall-back move up to 6" | none | `unit_has_shot` card → reactive normal move (ShootingPhase template); `fight_phase_end` card → engine-placed fall-back move | §13 |
| (army rule) | Librarius | psyker level budget per battle round | none for non-SW armies | `librarius_can_use` / `librarius_record` (same flags as SWAbilities11e) | §5 |

Resolver fixes (per-model weapons, §2): `UnitLoadoutResolver.SM11E_WEAPON_ID_NAME_SLUGS`
(the 12 Space Marine 40kdc weapon ids whose slug is not the weapon's name),
`_sm11e_silent_default_kit` (a roster with no wargear lines = the printed
default kit, single-model units too), and two `_datasheet_model_kits` rules
for 11e ADEPTUS ASTARTES units (an "any model" swap goes to the rank-and-file
first; a weapon several swaps can grant is placed by option order). All 29
datasheets resolve their default kit per model; the 16 with weapon options
were checked with a representative roster each.

Out of scope (other packages): Combat Doctrines selection / effects,
Transhuman Strategist, the Librarius army rule itself (M2a); stratagems (M3a/b);
the other 58 datasheets (M4a / M4c).

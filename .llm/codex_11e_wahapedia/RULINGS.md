# Codex 11e rulings (one line each, per work package)

Rulings made while implementing ambiguous printed text. Format:
`- <rule>: <ruling> (<why>)`

## Data import (W / C1 / O1)
- Ork curated stratagems vs the 2026-10-16 export: identical text; Wahapedia's phase column for MOW 'EM DOWN and UNBRIDLED CARNAGE reads "Charge or Fight phase" while WHEN says "Fight phase, when ... selected to fight" — kept "Fight phase" (the WHEN governs use).
- Praesidium Shield: no stat bonus (codex: -1 D to attacks allocated to the bearer — WP-C7).
- Vexilla: +1 OC applies only to units whose roster took a Vexilla (wargear abilities are emitted only for wargear the roster lists).
- Units sold in fixed sizes are snapped to a printed size (Gretchin 11 -> 10); pre-codex Custodes model counts are clamped (Custodian Guard 4-5 -> Sodality 3).
- Legends datasheets (Lootas, Burna Boyz, Aleya, Valerian, ...) are not imported; roster entries for them are kept unchanged (owner decision D2).

## WP-C3
- Martial Ka'tah readied step: every friendly unit with the ability is readied at the start of its owner's Command phase, units in Strategic Reserves / embarked included (the text names no battlefield condition); the opponent's units never are. A unit stays readied until it uses a ka'tah (no end-of-turn clear), so a unit not used in its own turn can use Dacatarai / Kaptaris / Rendax in the opponent's Fight phase.
- Ka'tah UI: each ka'tah is a 0-CP "KA'TAH" card in the stratagem window of its WHEN (Conservai command_phase_main, Calistus unit_selected_to_move, Salvus unit_selected_to_shoot, Dacatarai/Kaptaris fight_phase_start, Rendax unit_selected_to_fight); the readied state is a gold "K" diamond on every model of the unit plus a "Readied" line in the hover card (the codex's "place a token next to each readied unit"). Using a ka'tah re-opens the window so a stratagem / another unit's ka'tah can still follow (none of these windows is "one choice only").
- Conservai's WHEN ("your Command phase"): offered in the new command_phase_main window, which opens when the player first starts the Battle-shock step (End Command / Roll Call / a test), just before battle_shock_step_start — after the readied step and the Command-step prompts. Its effect lasts until the end of the turn (cleared at the next Command phase start). "Eligible to start an action" covers the engaged and battle-shocked eligibility checks; an action already started still fails if the unit later becomes battle-shocked (core rule unchanged); "starting an action does not prevent shooting" also lets a unit shoot after starting one.
- Calistus: "move through all types of model" = friendly and enemy models, including MONSTER / VEHICLE bases, for normal, advance and fall-back moves only (not charge, pile-in, consolidation, or a Desperate Escape test — the fall-back itself still makes the tests the rules require); it does not let a model END on another model.
- Salvus "can ignore modifiers": the engine ignores exactly the harmful ones (BS worsening, negative hit-roll and wound-roll modifiers, including the cover hit penalty) and keeps the beneficial ones — the same choice the engine makes for [PSYCHIC]-style ignore text. Applied on both ranged resolvers; logged in the modifier ledger as "Salvus (Ka'tah)".
- Dacatarai / Kaptaris "Start of the Fight phase": offered only for readied units within 6" of an enemy unit (a unit farther away cannot make or receive a melee attack this phase — pile-in is 3"), at the start of either player's Fight phase, active player first. Dacatarai's re-roll of 1s is skipped (not wasted) against MONSTER / VEHICLE targets; Kaptaris is -1 to hit for every melee attack that targets the unit, both stacking with the core -1/+1 cap.
- Rendax [LETHAL HITS: MONSTER/VEHICLE] is keyword-qualified: critical hits auto-wound only when the target unit is a MONSTER or VEHICLE; weapons that already have [LETHAL HITS] are unchanged.
- Phase-scoped expiry: Calistus, Salvus, Dacatarai, Kaptaris and Rendax end with the phase they were used in (BasePhase.exit_phase); the effect flags and the readied flag are written on every component of an Attached unit, and the unit is a single target.
- Master of Ka'tahs ("Once per battle round, per unit: if this unit is not readied, you can use this ability; if you do, it is readied"): offered as a "Master of Ka'tahs" button on a ka'tah card for a NOT readied unit that contains the ability (an Attached unit led by a Shield-Captain counts), which readies the unit and uses that ka'tah at once. Being readied has no other effect, so readying earlier would only matter to SUPERHUMAN FOCUS ("not readied" target) — out of WP-C3 scope.
- Favoured Ka'tah: CustodesKatah.favoured_katah(player) returns "" and favoured_katah_extra_effect(...) returns [] until CustodesDetachments.gd (WP-C46) defines them; the card text gains "(Favoured Ka'tah)" when it is the favoured one.
- Aegis of the Emperor: FNP 5+ vs every mortal wound (devastating wounds, hazardous, Deadly Demise, stratagem / ability / explosives / crushing impact / emergency-disembark / Desperate Escape MWs). Against wounds that are both mortal and psychic the best FNP wins (Daughters 3+ beats Aegis 5+); FNPs never stack and never roll twice.
- Daughters of the Abyss: FNP 3+ vs Psychic Attacks only (mortal wounds from a non-psychic source do not get it — that is Aegis's job; the 10e "psychic and mortal" grant is gone). Psychic Null (Aura): friendly ADEPTUS CUSTODES units within 6" (edge to edge, any model) of a friendly ANATHEMA PSYKANA unit with Daughters of the Abyss that is on the battlefield get FNP 5+ vs Psychic Attacks; the ANATHEMA unit itself uses its own 3+.
- Aquila Commander: "start of the battle round" = the first-turn player's Command phase entry, after the per-round bonus-CP tracker resets; only if the player's WARLORD is alive and has the ability; once per battle round (a save/load re-entry does not pay twice); the CP is a bonus CP, refused (and logged) when the player already gained a bonus CP this battle round.
- Anathema Psykana: an ANATHEMA PSYKANA model cannot be designated WARLORD (Formations validation refuses DESIGNATE_WARLORD and the warlord picker / auto-pick skip them; the army builder warns in 11e) unless CustodesDetachments.anathema_psykana_warlord_allowed(detachment) says so (Null Maiden Vigil hook, stub false).
- AI: uses a ka'tah only when it clearly pays — Rendax when engaged with a MONSTER/VEHICLE, Dacatarai (own turn) / Kaptaris (opponent's turn) when engaged with non-MONSTER/VEHICLE enemies, Calistus for a fall-back, Salvus when no enemy is within 18" (long shots, most likely to carry a hit penalty); never Conservai (it does not plan actions). Master of Ka'tahs needs a higher score. Decisions are synchronous, so a window never waits on the AI.

## WP-C5

## WP-C46

## WP-C7

## WP-O34

## WP-O5

## WP-O6
- "This unit" on a Leader-attached unit: the whole Attached unit (bodyguard + characters) has the ability's effect and shares its use counter; "this model" (Boss' Ammo Runt, Paired Krumpas) applies only to the bearer's attacks (attack batches carry bearer ids) (12.02 Attached units act as one unit).
- Hidden (Kunnin' Infiltrator, Nowhere to Hide, Burna Bomb): a unit is hidden only while every one of its alive models is hidden (13.09 is a per-model state; the abilities speak of the unit).
- Charge-roll bonuses (Waaagh! Banner, Trophy Hunters, Thundering Stampede, Waaagh!): different named sources stack; the same named source counts once (each printed rule is its own modifier; 08.02 caps only re-rolls).
- -1 D / -1 AP defensive abilities (Dread 'Ard, Mobile Fortress, Arrogant Invulnerability): not cumulative with another -1 D / -1 AP source on the same attack (the engine's EffectPrimitives take the best, as for other codex rules).
- Walking Bastion: ignores only harmful hit-roll modifiers (the -1); +1 to hit still applies (the rule removes penalties, not bonuses).
- "When this unit ends a normal move" (Bomb Squigs, Bomb Squig, Gut Hatch, Found 'Em!, Clever Know-wotz, Intimidating Motivation...): offered after normal moves only, not advances/fall-backs (the printed trigger names the move type).
- Start-or-end-of-move abilities (Intimidating Motivation, Get Back in da Race!, Keep Huntin'!, Clever Know-wotz, Found 'Em!, Drive-by Skorchin'): offered at selection and at the end of a normal move, usable once per phase per unit (or per its army limit) (one use per printed limit; two offers are just two chances).
- Post-shot "select one enemy unit hit" (Rokkit Barrage, Squig Barrage, Bust 'Em, Madcap Artillery): exactly one hit unit resolves automatically; two or more open the unit_has_shot window and declining forfeits it (no choice to make with one candidate; the mandatory wording "select" is honoured).
- Squig Barrage "hit by those attacks": approximated as any unit hit by this unit's attacks this activation (the post-shot ctx records hit units, not which weapon hit them).
- Madcap Artillery "all ranged weapons equipped by each Mek Gunz model are the same": read from the engine's resolved per-model loadout (MA-LOADOUT, from the roster's wargear); a generated datasheet with no wargear picks lists every gun, so the ability is not offered (the option menu is not the equipped kit).
- Crude Surgery: mandatory ("this unit heals 3 wounds"); offered in the battle_shock_step_start window (to allow Catch Dat Red Bit), and if not used there it heals 3 automatically when the Command phase ends (the heal must happen every Command phase).
- Healing (Crude Surgery, Fix Dat Armour Up, Push Dat Bit Back In, Clever Know-wotz): each healed wound restores a lost wound on a wounded model first; with none wounded a destroyed model returns with 1 wound (the engine's 02.02.04 heal model, as other packages).
- Fix Dat Armour Up: once per battle heal 3 in the Command phase (printed "(Once per battle, per unit)").
- Psychic abilities (Da Jump, Warpath, Beastscent): the psychic budget is FactionAbilityManager.unstable_energies_allows (WP-O34) when present, else 1 psychic level per battle round; a roll of 1 battle-shocks the unit but the effect still happens (the printed bullets are "On a 1, battle-shocked" + the effect, not "otherwise").
- Beastscent: used automatically when a unit disembarks from the Kill Rig in the Movement phase and the budget allows (always beneficial; avoids a dialog inside the disembark flow).
- Da Jump: the Deep Strike it grants lasts until the unit arrives (cleared once it is no longer in reserves) (the rule exists to bring the unit back).
- Runnin' wiv da Herd: +4" M while attached to a MOUNTED unit is implemented; the BEAST SNAGGA → MOUNTED keyword swap is not (no keyword-swap primitive; logged as not implemented).
- Super Runts "+1 WS": improves the WS characteristic by 1 (5+ becomes 4+, never better than 2+) (characteristic improvement, 01.07).
- Shokk-boosta: the advance roll is set to 6 and counts as an advance roll, so advance-roll modifiers (Fuel-mixa Grot) still apply; hazard rolls are made when the advance move ends (the printed "this advance roll is a 6").
- Taktikal Know-wotz: the split happens at deployment (the engine's existing split timing, GameState.split_unit_at_deployment); Squad A keeps Bomb Squig, Squad B gets Found 'Em!, both keep Nowhere to Hide (printed split of the abilities).
- Thievin' Scavengers: the objective is secured by the army (14.03), so it stays secured after the Gretchin die until the opponent takes control (the rule secures the objective, not "while this unit is alive").
- Tramplasquig Charge: any stratagem named CRUSHING IMPACT used on the Hunta Rig costs 1 CP less (the Ork faction stratagem; matched by name).
- Brutal Impact: +1 D on melee attacks only (it triggers on a charge move; ranged attacks are unaffected).
- Leadership of an Attached unit for battle-shock rolls the module makes (Rokkit Barrage, Mobbed): the best (lowest) Ld in the group; CommandPhase's own Battle-shock step uses the existing max rule — a pre-existing inconsistency, flagged, not changed (Leadership choice is outside WP-O6).
- Mobbed / Rokkit Barrage battle-shock rolls: 2D6 + modifier vs Ld, failure = battle-shocked (the 11e battle-shock roll), logged with both dice.
- Pulsa Rokkit: +1 AP and [LETHAL HITS] only against the unit selected when it was used, for the rest of the phase (printed "attacks that target that unit").
- Get Out da Way!: the engine's charge move has no model-crossing restriction (only the final overlap is checked), so the ability needs no hook beyond OrkAbilities11e.charge_moves_through_models (kept for when charge pathing gains one).
- Deff from the Shadows, Pilin' Out, Pulse Jet, Raucous Occupants / Fortification / Ramshackle Cover: not implemented (each needs a new engine flow — reserve arrival at the end of the opponent's Movement phase, a reactive disembark, a pulse-jet move type, fortification rules) (see ork_abilities_audit.md).
- Window offers for abilities: shown in the stratagem window as 0-CP "Ability" cards; after one is used the window re-opens while another ability is still on offer for the same trigger (several abilities can apply to one selection, e.g. Boss' Ammo Runt + Ammo Runts).
- AI: abilities are scored synchronously (OrkAbilities11e.ai_score, threshold 1.0, no CP) — hit / damage / heal / rile-up / post-shot abilities are used whenever offered; the repositioning ones (Da Jump, Kunnin' Infiltrator, Aerial Manoover, Shokk Attack Engine) and Shokk-boosta (a hazard roll per model) are declined, as they are plan-level decisions; the window never waits on the AI.

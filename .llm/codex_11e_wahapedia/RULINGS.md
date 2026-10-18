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

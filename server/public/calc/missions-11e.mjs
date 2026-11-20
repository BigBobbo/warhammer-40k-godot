// 11th edition missions (GDM 2026 mission deck + Event Companion), checked
// card by card against the official card images (gdmissions.app, 2026-11-16).
// Text here is a short paraphrase for the app; VP values are exact.
//
// Rules used by the forecast (forecast.mjs):
//  - Tactical: draw 2 face-up at the start of your Command phase; no hand
//    limit. Once per battle (end of your Command phase) pay 1CP to swap one.
//    End of each player's turn (both players check): score any active card
//    whose conditions are met (it is then discarded). Then, on your own turn,
//    you may discard one or more active cards to GAIN 1CP (events: at most
//    1CP per battle round from anything other than the Core CP).
//    VP scored "at the end of the battle" ignore the 15 VP per round limit.
//  - Fixed: 2 of the FIXED cards, never discarded, max 20 VP per card.
//  - Caps: primary 45 (15 per battle round), secondary 45 (15 per battle
//    round), Battle Ready 10. Five battle rounds.

export const RULES = {
  rounds: 5, drawPerTurn: 2,
  primaryCap: 45, primaryRoundCap: 15,
  secondaryCap: 45, secondaryRoundCap: 15, fixedCardCap: 20,
  battleReady: 10,
};

// timing: 'own' = end of your turn, 'opp' = end of your opponent's turn (or end of R5),
//         'any' = end of either turn.
// kind:   'kill' (scored from units destroyed), 'hold' (objectives held),
//         'position' (where your units are), 'action' (needs a unit to do an action).
export const SECONDARIES = [
  { id: 'a-grievous-blow', name: 'A Grievous Blow', fixed: true, timing: 'any', kind: 'kill', target: 'ss13',
    drawn: 'No enemy unit with Starting Strength 13+ left: you can discard it and draw a new card.',
    text: '5 VP if one or more enemy units with Starting Strength 13+ were destroyed this turn.',
    fixedText: '4 VP per enemy unit with Starting Strength 13+ destroyed (max 20 per game).' },
  { id: 'a-tempting-target', name: 'A Tempting Target', timing: 'own', kind: 'hold',
    drawn: 'Your opponent picks one non-home objective in No Man’s Land.',
    text: '5 VP if you control that objective at the end of your turn.' },
  { id: 'assassination', name: 'Assassination', fixed: true, timing: 'any', kind: 'kill', target: 'character',
    text: '5 VP if one or more enemy CHARACTER models were destroyed this turn (or all of them have been).',
    fixedText: '3 VP per enemy CHARACTER model destroyed, +1 each with W4+ (max 20 per game).' },
  { id: 'beacon', name: 'Beacon', timing: 'opp', kind: 'position',
    drawn: 'Pick one of your units as the beacon.',
    text: 'End of opponent’s turn: 3 VP if the beacon is alive and outside your deployment zone, or 5 VP outside your territory.' },
  { id: 'behind-enemy-lines', name: 'Behind Enemy Lines', timing: 'own', kind: 'position',
    drawn: 'Battle round 1: you can shuffle it back and draw a new card.',
    text: '3 VP per unit wholly within the enemy deployment zone (max 5).' },
  { id: 'bring-it-down', name: 'Bring It Down', fixed: true, timing: 'any', kind: 'kill', target: 'w10',
    drawn: 'No enemy model with W10+ left: you can discard it and draw a new card.',
    text: '5 VP if one or more enemy models with W10+ were destroyed this turn.',
    fixedText: '4 VP per enemy model with W10+ destroyed (max 20 per game).' },
  { id: 'burden-of-trust', name: 'Burden of Trust', timing: 'opp', kind: 'hold',
    drawn: 'Each of your turns: pick a guard unit for each objective.',
    text: 'End of opponent’s turn: 2 VP per objective you still control with its guard in range (max 5).' },
  { id: 'centre-ground', name: 'Centre Ground', timing: 'own', kind: 'position',
    text: '3 VP if you have a unit within 3" of the centre and no enemy within 3"; 5 VP if no enemy within 6".' },
  { id: 'cleanse', name: 'Cleanse', timing: 'own', kind: 'action', pair: 'plunder',
    drawn: 'If Plunder is active: you can shuffle it back and draw a new card.',
    text: 'Action (Shooting phase) on non-home objectives you control: 2 VP for one, 5 VP for two or more.' },
  { id: 'defend-stronghold', name: 'Defend Stronghold', timing: 'opp', kind: 'hold', minRound: 2,
    drawn: 'Battle round 1: shuffle it back and draw a new card (not optional).',
    text: 'End of opponent’s turn (from round 2): 3 VP if you control your home objective, +2 if no enemy unit is in your deployment zone.' },
  { id: 'display-of-might', name: 'Display of Might', timing: 'own', kind: 'position',
    text: 'More of your units than enemy units wholly in No Man’s Land: 2 VP at the end of your turn, or 5 VP at the end of your opponent’s.' },
  { id: 'engage-on-all-fronts', name: 'Engage on All Fronts', fixed: true, timing: 'own', kind: 'position',
    text: 'Units wholly in table quarters (not within 6" of the centre): 3 VP for three quarters, 5 VP for four.',
    fixedText: '2 VP for three quarters, 4 VP for four (max 20 per game).' },
  { id: 'forward-position', name: 'Forward Position', timing: 'own', kind: 'hold',
    drawn: 'Battle round 1: you can shuffle it back and draw a new card.',
    text: '5 VP if you control the enemy home objective and/or both expansion objectives.' },
  { id: 'no-prisoners', name: 'No Prisoners', timing: 'any', kind: 'kill', target: 'any',
    text: '2 VP per enemy unit destroyed this turn (max 5).' },
  { id: 'outflank', name: 'Outflank', timing: 'own', kind: 'position',
    text: '3 VP for a unit within 6" of a battlefield edge outside your territory; 5 VP for units near opposite edges.' },
  { id: 'overwhelming-force', name: 'Overwhelming Force', timing: 'any', kind: 'kill', target: 'onObjective',
    text: '3 VP per enemy unit destroyed that started the turn on an objective (max 5).' },
  { id: 'plunder', name: 'Plunder', timing: 'own', kind: 'action', pair: 'cleanse',
    drawn: 'If Cleanse is active: you can shuffle it back and draw a new card.',
    text: 'Action (Shooting phase) by a unit in a terrain area outside your territory: 5 VP.' },
  { id: 'secure-no-mans-land', name: 'Secure No Man’s Land', timing: 'own', kind: 'hold',
    text: '5 VP if you control two or more objectives in No Man’s Land.' },
];
// Most VP one tactical card can pay when it scores (checked on every card: the
// higher tier, the "max 5VP" cap, or 3 + 2 for Defend Stronghold), and the
// per-game cap for a FIXED card.
for (const c of SECONDARIES) { c.max = 5; if (c.fixed) c.fixedMax = RULES.fixedCardCap; }
export const SECONDARY_BY_ID = Object.fromEntries(SECONDARIES.map(c => [c.id, c]));
export const FIXED_IDS = SECONDARIES.filter(c => c.fixed).map(c => c.id);

// Primary missions: name -> scoring summary + which inputs drive it.
// Scoring functions live in forecast.mjs (primaryScore); `action` marks the
// ones whose VP depend on a mission action / markers you estimate yourself.
export const PRIMARIES = {
  'Battlefield Dominance': { kills: false, action: false, text: 'R1–2: 2 VP for holding more objectives. From R2 (Command phase): 3 VP per objective, +2 each non-home while you hold your home.' },
  'Determined Acquisition': { kills: false, action: false, text: '2 VP per objective you took this turn (not home). From R2: 3 VP per objective, +3 each in enemy territory.' },
  'Immovable Object': { kills: false, action: false, text: '3 VP for holding a central objective. R2–5: 5 VP per non-home objective.' },
  'Inescapable Dominion': { kills: false, action: false, text: '4 VP for 3+ objectives. From R2: 5 VP for 2+, 4 VP for more than your opponent. End: 5 VP for their home.' },
  'Purge and Secure': { kills: true, action: false, text: '3 VP for kills on/near objectives. From R2: 4 VP per non-home objective; 3 VP for taking a new one.' },
  'Consecrate': { kills: true, action: true, text: 'Units that kill mark (consecrate) objectives: 3 VP for 1–2, 6 VP for 3+. From R2: 4 VP for a non-home objective, 4 VP for more. End: 5 VP if their home is consecrated.' },
  "Destroyer's Wrath": { kills: true, action: false, text: '3 VP for a kill. From R2: 4 VP for a non-home objective, 6 VP for more; 4 VP for out-killing their last turn.' },
  'Meatgrinder': { kills: true, action: false, text: '3 VP for a kill. From R2: 4 VP for a non-home objective; 5 VP for out-killing their last turn; 5 VP for their home.' },
  'Punishment': { kills: true, action: false, text: 'Condemn up to 3 enemy units: 5 VP when one dies. From R2: 4 VP for a non-home objective, 5 VP for more. End: 8 VP for their home.' },
  'Unstoppable Force': { kills: true, action: false, text: '3 VP for a kill. From R2: 4 VP per non-home objective; 3 VP for taking a new one. End: 5 VP for a central objective.' },
  'Gather Intel': { kills: false, action: true, text: 'R1: 6 VP for a central objective. From R2: 4 VP for a non-home objective; 7 VP per unit completing Extract Intelligence. End: markers.' },
  'Reconnaissance Sweep': { kills: true, action: false, text: '3/6 VP for units in 3/4 table quarters; 1 VP per kill. From R2: 3 VP for a non-home objective.' },
  'Search and Scour': { kills: true, action: false, text: '3 VP for a central objective; 2 VP for killing a unit in terrain. From R2: 4 VP per non-home objective. End: 5 VP if your territory is clear.' },
  'Surveil the Foe': { kills: false, action: true, text: '4 VP for surveilling. From R2: 4 VP for a non-home objective, 4 VP for more; 5 VP if their markers are gone.' },
  'Triangulation': { kills: false, action: true, text: 'From R2: 4 VP for a non-home objective; 3/6/10 VP for 1/2/3+ triangulated objectives. End: 10 VP for 4+ objectives.' },
  'Extract Relic': { kills: true, action: true, text: '4 VP per sensor sweep; 3 VP for kills on objectives; marker VP. From R2: 4 VP for a non-home objective.' },
  'Sabotage': { kills: false, action: true, text: '3 VP per unit committing sabotage (+2 in enemy territory). From R2: 4 VP for a non-home objective.' },
  'Secure Asset': { kills: true, action: true, text: '4 VP for securing the asset; 2 VP for kills near the centre. From R2: 4 VP for a non-home objective, 4 VP for 3+.' },
  'Vanguard Operation': { kills: true, action: true, text: '4 VP per vanguard operation; 2 VP for a kill. From R2: 4 VP for a non-home objective. End: 10 VP for their home.' },
  'Vital Link': { kills: false, action: true, text: '2 VP for a central objective (+1 per marker there). From R2: 4 VP for a non-home objective, +4 if central. End: 10 VP for their home.' },
  'Death Trap': { kills: true, action: true, text: '2 VP per terrain area trapped (+3 if an objective); 3 VP for kills in trapped areas. From R2: 4 VP for a non-home objective.' },
  'Delaying Action': { kills: true, action: false, text: '2 VP per kill. From R2: 4 VP for a non-home objective; 3 VP for central + expansion.' },
  'Locate and Deny': { kills: true, action: true, text: '4 VP for kills on objectives; marker VP. From R2: 4 VP for a non-home objective. End: 5 VP marker.' },
  'Outmanoeuvre': { kills: false, action: false, text: '10 VP for their home (any turn). R1: 4 VP, R2–3: 5 VP, R4–5: 6 VP per non-home objective.' },
  'Smoke and Mirrors': { kills: false, action: true, text: '2 VP per decoyed objective (+2 in enemy territory). From R2: 4 VP for a non-home objective. End: 10 VP for 4+ decoyed.' },
};

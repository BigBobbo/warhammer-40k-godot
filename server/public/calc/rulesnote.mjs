// "Rules in force": what the rules in this app were last checked against, the next rules change that has been
// announced, and the rulings of the November 2026 update that are not in the numbers.
//
// Pure data and two small functions (no DOM, no dataset), unit-tested in tests/calc-rulesnote.test.mjs,
// where every "inData" claim below is checked against the rules data.
//
// Sources (read in the documents, not from memory):
//  - Warhammer Community, "The Warhammer 40,000 Updates Update", 29 Oct 2026: "The next rules change for
//    Warhammer 40,000 will be the quarterly balance update, set to be published the week beginning 7 December."
//  - "World Championships Rules Updates - November 2026" (GW): "currently only considered valid for the World
//    Championships". UKTC judge rulings FAQ: "Will UKTC be adopting the World Championships of Warhammer:
//    Barcelona 2026 rules updates? A: Yes."
//  - npm registry, 20 Nov 2026: the newest @alpaca-software/40kdc-data is 1.5.1 (13 Nov 2026).

/** The day the rules in the app were last read against their sources. */
export const RULES_CHECKED = '2026-11-20';
export const RULES_SOURCES = ['the core rules and rules appendix', 'Event Companion v1.3', 'the GW Grand Tournament pack 2026', 'UKTC policies'];
/**
 * The terrain layouts behind the Board and the forecast. Event Companion v1.3 (October 2026), read 24 Nov 2026:
 * "WHAT'S NEW? Base Size Guide: Wazbom Blastajet updated." and "LAYOUTS UPDATED: None." — the layouts are v1.2's
 * (August 2026). The app's layout files come from the 40kdc data (17 Sep 2026, after v1.2); 12 of the 45 were
 * compared by eye with the v1.3 PDF (zones, terrain positions, objectives): no difference found.
 */
export const LAYOUTS_SOURCE = { version: 'Event Companion v1.3', date: 'October 2026', note: 'layouts unchanged since v1.2, August 2026', checked: '2026-11-24', sample: '12 of 45 compared with the official PDF' };
/** The newest release of the rules dataset on the day of the check. */
export const DATASET_NEWEST = { version: '1.5.1', date: '2026-11-13' };
/** The next rules change that has a date. */
export const NEXT_UPDATE = { weekOf: '2026-12-07', what: 'the quarterly balance update', source: 'Warhammer Community, 29 Oct 2026' };

/**
 * The November 2026 update. It is for one event and for the events that adopt it, so its weapon changes are
 * not put on the numbers: the datasheets it changes say what differs. inData: the rules data already has it.
 */
export const UPDATE = {
  id: 'wcw-2026-11',
  label: 'World Championships rules updates, November 2026',
  short: 'Nov 2026 update',
  used: 'UKTC events use it',
  units: {
    'chief librarian mephiston': [{ weapon: 'Plasma pistol, Supercharge', change: 'add [HAZARDOUS]', inData: true }],
    'death company captain with jump pack': [{ weapon: 'Plasma pistol, Supercharge', change: 'add [CLOSE-QUARTERS]', inData: true }],
    'death company dreadnought': [{ weapon: 'Twin heavy bolter', change: 'add [RAPID FIRE 2]', inData: false }],
    'chaos bikers': [{ weapon: 'Combi-weapon', change: 'S5 and AP-1', inData: false }],
    'nemesis claw': [{ weapon: 'Close combat weapon', change: 'S5', inData: false }],
    'deathwatch terminator squad': [{ weapon: 'Plasma cannon', change: 'Standard S7, Supercharge S8', inData: true }],
    'deathwatch veterans': [{ weapon: 'Combi-weapon', change: 'Damnatus gains [MELTA 2], Purgatus loses it', inData: false }],
    'aggressor squad': [{ weapon: 'Auto boltstorm gauntlets', change: 'remove [CLOSE-QUARTERS]', inData: false }],
  },
  // rulings about a rule of a list, by ability id
  abilities: {
    'combat-doctrines': 'A doctrine made active for one unit by Strategic Acumen, Author of the Codex or Master Tactician does not count as your once-per-battle selection of that doctrine.',
  },
};

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const iso = (d) => (typeof d === 'string' ? d : `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`);
/** 2026-12-07 -> "7 December 2026" */
export const longDate = (s) => { const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s ?? ''); return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : ''; };

/**
 * Where the rules stand today.
 * -> { checked, sources, next: { weekOf, what, source, due } , changes: { total, missing } }
 * due: the week of the next update has begun (or passed): the rules in the app may be behind it.
 */
export function rulesStatus(today = new Date()) {
  const all = Object.values(UPDATE.units).flat();
  return {
    checked: RULES_CHECKED, sources: RULES_SOURCES, newest: DATASET_NEWEST,
    next: { ...NEXT_UPDATE, due: iso(today) >= NEXT_UPDATE.weekOf },
    changes: { total: all.length, missing: all.filter(c => !c.inData).length },
  };
}

/** What the November update changes on a datasheet: [{ weapon, change, inData }] ([] = nothing). */
export function unitUpdates(datasheetName) {
  return UPDATE.units[String(datasheetName ?? '').trim().toLowerCase()] ?? [];
}
/** A ruling of the November update about a rule (by ability id), or null. */
export function abilityUpdate(id) {
  return UPDATE.abilities[String(id ?? '')] ?? null;
}

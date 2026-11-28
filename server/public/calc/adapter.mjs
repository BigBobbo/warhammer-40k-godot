// Army adapter for the combat calculator: pasted list text -> combat units
// (attached Leaders/Support merged into their Bodyguard), attacker weapon
// rows and defender profiles/rules for engine.mjs.
//
// Reuses the Army Builder's importer and patched 40kdc dataset (store.js /
// importers.js), so every list format the builder accepts works here too.

import { conv, factionName, dc, ds, unitData, unitBasePoints, countsOf } from '../js/builder/store.js';
import { CODEX_OVERLAY_FACTIONS } from '../js/lib/data-patches.mjs';
import { ERRATA } from './errata-data.mjs';
import { importText, importGameObject } from '../js/builder/importers.js';
import { gameArmyText } from './gamelists.mjs';
import { normName, looseName } from '../js/lib/dckit.mjs';
import { mergeMods } from './engine.mjs';
import { solveCounts, quickStat } from './choose.mjs';
import { footprint } from './board.mjs';
import { BASE_SIZE_OVERRIDES } from '../js/lib/gameformat.mjs';
import { STRATAGEMS } from './stratagems-11e.mjs';
import {
  parseOffensive, parseDefensiveText, parseConditions, conditionsMet, describeConditions,
  stratagemRole, stratagemPhases, stratagemEligible, phraseInKeywords, parseWeaponBullets, weaponNamed,
} from './rules.mjs';
export { describeConditions };

export const DATASET_VERSION = dc.DATASET_VERSION;

// ---------------------------------------------------------------------------
// Points and weapon profiles of a newer 40kdc release, for the calculator only.
//
// The dataset bundle is shared with the Army Builder and is one release behind
// (a newer release re-keys abilities and stratagems, so the bundle cannot simply
// be swapped). errata-data.mjs (scripts/40kdc/gen_calc_errata.mjs) holds what
// keeps its key and shape in the newer release: unit points and weapon profiles
// of the factions this project has no codex import for. They are put on the
// records here, in place, when the calculator loads — the Army Builder and the
// game never import this module.

const errataStable = (v) => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.entries(x).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) : x));
/** The hash scripts/40kdc/gen_calc_errata.mjs writes as "was" (FNV-1a of the value's stable JSON). */
export function errataHash(v) {
  const str = errataStable(v);
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  return (h >>> 0).toString(36);
}

const ERRATA_DONE = new WeakMap();   // raw data -> result (applied once)
/**
 * Put the newer points and weapon profiles on the dataset records. An entry is
 * applied only to a record that is still the bundle's own (no codex import,
 * same value as when the entry was made). Returns what was done.
 */
export function applyErrata(raw = dc.RAW_DATA, errata = ERRATA, bundleVersion = dc.DATASET_VERSION) {
  if (ERRATA_DONE.has(raw)) return ERRATA_DONE.get(raw);
  const res = { from: errata?.from ?? null, date: errata?.dataslate?.date ?? null, points: 0, weapons: 0, units: 0, skipped: [], why: null };
  ERRATA_DONE.set(raw, res);
  if (!errata) { res.why = 'no refresh data'; return res; }
  if (bundleVersion !== errata.base) { res.why = `made for bundle ${errata.base}, the bundle is ${bundleVersion}`; return res; }
  const keep = new Set(errata.skipped ?? []);
  const stamp = `40kdc-${errata.from}@${errata.dataslate.date}`;
  const units = new Map(raw.units.map(u => [`${u.faction_id}::${u.id}`, u]));
  for (const [key, e] of Object.entries(errata.points ?? {})) {
    const u = units.get(key);
    if (!u || u.source || keep.has(u.faction_id) || errataHash(u.points) !== e.was) { res.skipped.push(`points ${key}`); continue; }
    u.points = e.now;
    res.points++;
  }
  const weapons = new Map(raw.weapons.map(w => [`${w.faction_id ?? ''}::${w.id}`, w]));
  for (const [key, e] of Object.entries(errata.weapons ?? {})) {
    const w = weapons.get(key);
    if (!w || w.source || keep.has(w.faction_id) || errataHash(w.profiles) !== e.was) { res.skipped.push(`weapon ${key}`); continue; }
    w.profiles = e.now;
    res.weapons++;
  }
  // the datasheets whose points and weapon profiles were compared with the newer release
  for (const [faction, ids] of Object.entries(errata.checked ?? {})) {
    for (const id of ids) { const u = units.get(`${faction}::${id}`); if (u && !u.source) { u.errata = stamp; res.units++; } }
  }
  console.log(`[calc] rules data: points of ${res.points} units and profiles of ${res.weapons} weapons from 40kdc ${errata.from} (${errata.dataslate.date})${res.skipped.length ? `; ${res.skipped.length} entries not applied` : ''}`);
  return res;
}
export const ERRATA_RESULT = applyErrata();

// ---------------------------------------------------------------------------
// How current is the rules data?
//
// Every datasheet record says where it comes from: the 40kdc dataset (its
// game_version names a rules snapshot with a date) or a codex datasheet this
// project brought in from Wahapedia (source "wahapedia-11e@<date>"). The app
// shows that date, and checks the points in the pasted list against the
// data: points change with the rules, so other points mean the datasheet
// may have changed since the data was made.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** 2026-10-21 -> "21 Oct 2026" */
export function fmtDataDate(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso ?? '');
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : 'date not known';
}
const SLATE_LABEL = { launch: '11th edition launch data', 'pre-launch-provisional': 'provisional data from before the 11th edition launch' };

/** Where a datasheet record comes from, and from when. */
export function recordStamp(dcUnit) {
  const src = /@(\d{4}-\d{2}-\d{2})$/.exec(dcUnit?.source ?? '');
  if (src) {
    const codex = CODEX_OVERLAY_FACTIONS[dcUnit.faction_id]?.codex?.replace(/\s*\(11th edition\)/, '') ?? 'Codex datasheet';
    return { kind: 'codex', date: src[1], label: `${codex} (Wahapedia)` };
  }
  const slate = dcUnit?.game_version?.dataslate ?? null;
  const gv = (dc.RAW_DATA.gameVersions ?? []).find(g => g.dataslate === slate);
  // points and weapon profiles from a newer release (applyErrata); the abilities are still the bundle's
  const err = /^40kdc-([\d.]+)@(\d{4}-\d{2}-\d{2})$/.exec(dcUnit?.errata ?? '');
  if (err) return { kind: 'errata', date: err[2], label: `40kdc ${err[1]} points and weapon profiles`, note: `abilities: 40kdc ${dc.DATASET_VERSION}, ${fmtDataDate(gv?.effective_date)}` };
  return { kind: 'base', date: gv?.effective_date ?? null, label: `40kdc ${dc.DATASET_VERSION}: ${SLATE_LABEL[slate] ?? gv?.label ?? 'dataset'}` };
}

/** The newest date in the whole rules data (dataset snapshots and codex datasheets). */
export function dataNewest() {
  const dates = [...(dc.RAW_DATA.gameVersions ?? []).map(g => g.effective_date)];
  for (const u of dc.RAW_DATA.units ?? []) { const m = /@(\d{4}-\d{2}-\d{2})$/.exec(u.source ?? u.errata ?? ''); if (m) dates.push(m[1]); }
  return dates.filter(Boolean).sort().pop() ?? null;
}

/** Provenance and points check of an army, worked out once per set of units. */
const DATA_CACHE = new WeakMap();   // army.units (replaced when attachments change) -> { prov, pts }
export function armyData(army) {
  let d = DATA_CACHE.get(army.units);
  if (!d) { d = { prov: dataProvenance(army), pts: pointsCheck(army) }; DATA_CACHE.set(army.units, d); }
  return d;
}

/** The rules data behind an army: per datasheet, and grouped (newest first). */
export function dataProvenance(army) {
  const units = [];
  for (const cu of army.units) for (const m of cu.members) units.push({ unit: cu.key, name: m.dcUnit.name, ...recordStamp(m.dcUnit) });
  const by = new Map();
  for (const u of units) {
    const k = `${u.label}|${u.date}`;
    if (!by.has(k)) by.set(k, { kind: u.kind, label: u.label, date: u.date, note: u.note ?? null, count: 0, names: [] });
    const g = by.get(k); g.count++; g.names.push(u.name);
  }
  const groups = [...by.values()].sort((a, b) => String(b.date ?? '').localeCompare(String(a.date ?? '')));
  const dates = units.map(u => u.date).filter(Boolean).sort();
  return { dataset: dc.DATASET_VERSION, units, groups, oldest: dates[0] ?? null, newest: dates[dates.length - 1] ?? null };
}

/**
 * What the list says a unit costs, its enhancement included. Importers differ: the GW app's unit header already
 * includes the enhancement (enhancement_points null), the New Recruit / WTC text gives the unit price and the
 * enhancement apart ("Telemon Heavy Dreadnought (310 pts)" + "Enhancement: Augury Uplink (+30 pts)" is stored as
 * 280 + 30), as the list builder does (store.js: points + enhancement_points).
 */
export const listedPoints = (ru) => (ru.points == null ? null : ru.points + (ru.enhancement_points ?? 0));

/**
 * The points in the pasted list against the rules data: the datasheet at its
 * size (any of its price steps for a 1st, 2nd, 3rd... copy), its priced
 * wargear and its enhancement. A unit with no points in the list, or with an
 * enhancement the data does not know, is not checked.
 */
/**
 * A list's prices against the rules data today (after a points update): each unit's listed price and what it costs
 * now (its copy of the datasheet counted in list order, its wargear and its enhancement), the totals, and the limit.
 * -> { listed, now, limit, over, changed: [{ name, list, now }], unknown: n (units the data cannot price) }
 */
export function listPointsNow(army) {
  const out = { listed: 0, now: 0, limit: army.roster.points?.declared_limit ?? null, changed: [], unknown: 0 };
  const copies = new Map();
  for (const ru of army.roster.units ?? []) {
    const listed = listedPoints(ru);
    out.listed += listed ?? 0;
    const id = ru.ref?.id, data = id ? unitData(id, ru._unit_faction_id ?? army.roster.faction_id) : null;
    const ord = (copies.get(id) ?? 0) + 1;
    copies.set(id, ord);
    let now = NaN;
    if (data) { try { now = unitBasePoints(data, ru.model_count ?? 1, countsOf(ru), ord); } catch { /* no price for this size */ } }
    const enhId = ru.enhancement?.id ?? ru.enhancement?.ref?.id ?? null;
    const enh = enhId ? (dc.RAW_DATA.enhancements ?? []).find(e => e.id === enhId) : null;
    if (!Number.isFinite(now) || (ru.enhancement && !Number.isFinite(enh?.cost))) { out.unknown++; out.now += listed ?? 0; continue; }
    now += enh?.cost ?? 0;
    out.now += now;
    if (listed != null && listed !== now) out.changed.push({ name: ru.ref?.raw_name ?? id, list: listed, now });
  }
  out.over = out.limit != null && out.now > out.limit;
  return out;
}

export function pointsCheck(army) {
  const out = { checked: 0, mismatches: [] };
  for (const cu of army.units) for (const m of cu.members) {
    const ru = m.ru;
    if (ru.points == null) continue;
    const data = unitData(m.dcUnit.id, m.factionId ?? army.roster.faction_id);
    if (!data) continue;
    const enhId = ru.enhancement?.id ?? ru.enhancement?.ref?.id ?? null;
    const enh = enhId ? (dc.RAW_DATA.enhancements ?? []).find(e => e.id === enhId) : null;
    if (ru.enhancement && (!enh || !Number.isFinite(enh.cost))) continue;
    const want = new Set();
    for (let ordinal = 1; ordinal <= 4; ordinal++) {
      let pts = NaN;
      try { pts = unitBasePoints(data, ru.model_count ?? 1, countsOf(ru), ordinal); } catch { /* no price for this size */ }
      if (Number.isFinite(pts) && pts > 0) want.add(pts + (enh?.cost ?? 0));
    }
    if (!want.size) continue;
    out.checked++;
    if (!want.has(listedPoints(ru))) {
      out.mismatches.push({ unit: cu.key, name: m.dcUnit.name, models: ru.model_count ?? 1, list: listedPoints(ru), data: [...want].sort((a, b) => a - b),
        enhancement: enh ? { name: enh.name, cost: enh.cost } : null, ...recordStamp(m.dcUnit) });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Import

/**
 * A list from the game's army store (a game army file) as list text for importArmy. Two ways, the better one kept:
 * the Army Builder's converter (game file -> roster -> WTC text: exact when it knows every datasheet, it keeps the
 * loadout per model), and the file written out line by line (gamelists.gameArmyText: for the units the builder's
 * converter cannot place, e.g. the Space Wolves datasheets). Better = more units recognised, then more units whose
 * points match the rules data, then fewer import notes. -> { text, how, units, recognised, pointsOk, checked }
 */
export function gameArmyToText(json, name = '') {
  const tries = [];
  try {
    const { roster } = importGameObject(json, { name });
    // the converter prices each unit again (a second copy at the first copy's price): keep the file's price
    const metas = Object.values(json?.units ?? {}).map(u => u?.meta).filter(m => m?.name);
    if (metas.length === roster.units.length) {
      roster.units.forEach((ru, k) => {
        const p = Number(metas[k].points);
        if (Number.isFinite(p) && p > 0 && looseName(metas[k].name) === looseName(ru.ref?.raw_name ?? metas[k].name)) ru.points = p - (ru.enhancement_points ?? 0);
      });
    }
    const t = dc.exportRoster(roster, 'newrecruit-wtc-full', ds);
    tries.push({ how: 'builder', text: typeof t === 'string' ? t : String(t?.text ?? t) });
  } catch (e) { console.log('[calc] game list: the builder\'s converter failed:', e.message); }
  try { tries.push({ how: 'lines', text: gameArmyText(json, name) }); } catch (e) { console.log('[calc] game list: line by line failed:', e.message); }
  let best = null;
  for (const t of tries) {
    let army;
    try { army = importArmy(t.text); } catch { continue; }
    const pc = pointsCheck(army);
    const r = { ...t, units: army.roster.units.length, recognised: army.roster.units.filter(u => u.ref?.id).length, pointsOk: pc.checked - pc.mismatches.length, checked: pc.checked, notes: army.warnings.length };
    const better = (a, b) => (a.recognised - b.recognised) || (a.pointsOk - b.pointsOk) || (b.notes - a.notes);
    if (!best || better(r, best) > 0) best = r;
  }
  if (!best) throw new Error('This army could not be read.');
  console.log(`[calc] game list "${name}": ${best.how}, ${best.recognised}/${best.units} units recognised, points ${best.pointsOk}/${best.checked}`);
  return best;
}

/** An army read in the calculator as a game army file (the Army Builder's converter, as its "Save to cloud"). */
export function armyToGame(army, today = new Date()) {
  const createdDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  const { army: game, warnings } = conv.rosterToGame(army.roster, { createdDate });
  return { game, warnings: warnings ?? [] };
}

export function importArmy(text) {
  const { roster, report } = importText(text);
  const attachments = defaultAttachments(roster);
  const units = combatUnits(roster, attachments);
  const unresolved = (roster.units ?? []).filter(u => !u.ref?.id).map(u => u.ref?.raw_name ?? '?');
  return {
    roster,
    faction: roster.faction_id ? factionName(roster.faction_id) : 'Unknown faction',
    name: roster.name || 'Army',
    defaultAttachments: attachments,
    attachments,
    units,
    warnings: [...(report?.warnings ?? []), ...unresolved.map(n => `unit not recognised: ${n}`)],
  };
}

/** Re-derive the combat units after the player changes who is attached to whom. */
export function setAttachments(army, attachments) {
  army.attachments = attachments;
  army.units = combatUnits(army.roster, attachments);
  return army;
}

function resolveUnit(roster, ru) {
  if (!ru.ref?.id) return null;
  const found = conv.findUnitById(roster.faction_id, ru.ref.id);
  return found ? { dcUnit: found.unit, factionId: found.factionId } : null;
}

function isCharacter(dcUnit) {
  return (dcUnit.keywords ?? []).some(k => /^character$/i.test(k));
}

function rosterParts(roster) {
  const parts = [];
  (roster.units ?? []).forEach((ru, i) => {
    const r = resolveUnit(roster, ru);
    if (r) parts.push({ index: i, ru, ...r });
  });
  return parts;
}

/** 'leader' | 'support' for a character that can be attached, else null. */
export function attachRole(part) {
  if (eligibleBodyguardIds(part).size === 0) return null;
  return part.dcUnit.attachment_role === 'support' || part.ru.leader_attachment?.role === 'support' ? 'support' : 'leader';
}

/** Datasheet ids this character may join (Leader list + enhancement grants). */
function eligibleBodyguardIds(part) {
  const la = (dc.RAW_DATA.leaderAttachments ?? []).filter(x => x.leader_id === part.dcUnit.id);
  const ids = new Set(la.flatMap(x => x.eligible_bodyguard_ids ?? []));
  const enhId = part.ru.enhancement?.id ?? part.ru.enhancement?.ref?.id;
  if (enhId) for (const b of (dc.RAW_DATA.enhancements ?? []).find(x => x.id === enhId)?.attachment_bodyguard_ids ?? []) ids.add(b);
  return ids;
}

/**
 * Attachments as listed in the imported army: { [characterRosterIndex]: bodyguardRosterIndex }.
 * (GW app "Attached as" blocks; other formats usually carry none.)
 */
export function defaultAttachments(roster) {
  const parts = rosterParts(roster);
  const out = {};
  const used = new Map(); // bodyguard index -> Set(roles)
  for (const p of parts) {
    const bgId = p.ru.leader_attachment?.bodyguard_ref?.id;
    if (!bgId) continue;
    const role = p.ru.leader_attachment?.role === 'support' ? 'support' : 'leader';
    const bg = parts.find(q => q.ru.ref.id === bgId && q !== p && !q.ru.leader_attachment && !used.get(q.index)?.has(role));
    if (!bg) continue;
    if (!used.has(bg.index)) used.set(bg.index, new Set());
    used.get(bg.index).add(role);
    out[p.index] = bg.index;
  }
  return out;
}

/**
 * What an enhancement gives the bearer's whole unit, from wording like Wolf-Touched:
 * "This unit has: • Wulfen. • +2" M."  -> { keywords: ['WULFEN'], move: 2 }
 * (only the plain "This unit has:" form: one that starts with a condition is left alone)
 */
export function enhancementGrants(ru) {
  const out = { keywords: [], move: 0, name: null };
  const eid = ru?.enhancement?.id ?? ru?.enhancement?.ref?.id;
  const e = eid ? (dc.RAW_DATA.enhancements ?? []).find(x => x.id === eid) : null;
  const m = String(e?.rules_text ?? '').replace(/\s+/g, ' ').match(/(?:^|\. )This unit has:\s*•(.*)$/);
  if (!m) return out;
  out.name = e.name;
  for (const b of m[1].split('•').map(s => s.trim().replace(/\.$/, ''))) {
    const mv = b.match(/^\+(\d+)" M$/);
    if (mv) out.move += Number(mv[1]);
    else if (/^[A-Z][A-Za-z’' -]{2,30}$/.test(b) && !/\b(has|have|can|when|if|strike|operative|stealth|scouts|infiltrators)\b/i.test(b)) out.keywords.push(b.toUpperCase());
  }
  return out;
}

/**
 * Attachments to suggest when a list does not say who leads which unit: every character that is not attached yet
 * goes to a unit on its Leader list with that slot (Leader / Support) free. The characters with the fewest
 * possible units go first; a Leader prefers a unit with no character yet, a Support one that already has a
 * Leader (the GW pairing: Logan Grimnar + Ancient in Terminator Armour with the Terminators); then the unit
 * with the most points. Keeps the attachments already made. -> { [characterIndex]: bodyguardIndex }
 */
export function suggestAttachments(army) {
  const parts = rosterParts(army.roster);
  const att = { ...(army.attachments ?? {}) };
  const roleOf = new Map(parts.map(p => [p.index, attachRole(p)]));
  const bodyguards = parts.filter(p => !roleOf.get(p.index) && !isCharacter(p.dcUnit));
  const chars = parts.filter(p => roleOf.get(p.index) && att[p.index] == null)
    .map(p => ({ p, role: roleOf.get(p.index), ids: eligibleBodyguardIds(p) }))
    .map(c => ({ ...c, n: bodyguards.filter(b => c.ids.has(b.dcUnit.id)).length }))
    .filter(c => c.n > 0)
    // leaders before supports (a support goes where a leader is), then the least choice first
    .sort((a, b) => (a.role === 'support') - (b.role === 'support') || a.n - b.n || a.p.index - b.p.index);
  const on = (bi) => Object.entries(att).filter(([, x]) => x === bi).map(([ci]) => roleOf.get(Number(ci)));
  const pts = (p) => listedPoints(p.ru) ?? 0;
  for (const c of chars) {
    const free = bodyguards.filter(b => c.ids.has(b.dcUnit.id) && !on(b.index).includes(c.role));
    if (!free.length) continue;
    const score = (b) => {
      const here = on(b.index);
      return [c.role === 'leader' ? (here.length ? 0 : 1) : (here.includes('leader') ? 1 : 0), pts(b)];
    };
    free.sort((a, b) => { const x = score(a), y = score(b); return (y[0] - x[0]) || (y[1] - x[1]) || (a.index - b.index); });
    att[c.p.index] = free[0].index;
  }
  return att;
}

// ---- transports: who can embark, and how many spaces they take (rules data: transport_capacity)
const kwSet = (dcUnit) => new Set([...(dcUnit.keywords ?? []), ...(dcUnit.faction_keywords ?? [])].map(k => String(k).toUpperCase()));
/** Does a unit with these keywords have every keyword in the phrase? ("Adeptus Astartes Infantry": ADEPTUS ASTARTES + INFANTRY) */
function hasAllKeywords(kws, phrase) {
  let rest = ` ${String(phrase).toUpperCase().replace(/\s+/g, ' ').trim()} `;
  for (const k of [...kws].sort((a, b) => b.length - a.length)) while (rest.includes(` ${k} `)) rest = rest.replace(` ${k} `, ' ');
  return rest.trim() === '';
}
/**
 * The transport in a combat unit, or null: { name, capacity, phrase (who may embark, from the datasheet text; null =
 * not given: Infantry of the same army is assumed), exclude: [keyword phrases], multipliers: [{ keyword, spaces }] }.
 */
export function transportOf(cu) {
  const m = cu?.members?.find(x => x.dcUnit.transport_capacity?.capacity);
  if (!m) return null;
  const tc = m.dcUnit.transport_capacity, text = tc.rules_text ?? '';
  const phrase = /transport capacity of \d+ (.+?) models?\b/i.exec(text)?.[1] ?? null;
  const cannot = /cannot transport ([^.]+?) models?\b/i.exec(text)?.[1]?.split(/\s*\/\s*|\s*,\s*|\s+or\s+/) ?? [];
  return { name: m.dcUnit.name, capacity: tc.capacity, phrase, exclude: [...new Set([...(tc.exclusion_keywords ?? []), ...cannot].filter(Boolean))],
    multipliers: tc.multipliers ?? [], faction: m.dcUnit.faction_id, text };
}
/** Can combat unit `cu` embark in transport `tr` (transportOf)? -> { ok, spaces, why } */
export function passengerCheck(tr, cu) {
  if (!tr || !cu) return { ok: false, spaces: 0, why: 'not a transport' };
  let spaces = 0;
  for (const m of cu.members) {
    const kws = kwSet(m.dcUnit);
    if (kws.has('VEHICLE') || kws.has('MONSTER')) return { ok: false, spaces: 0, why: `${m.dcUnit.name} is a ${kws.has('VEHICLE') ? 'Vehicle' : 'Monster'}` };
    const ex = tr.exclude.find(e => hasAllKeywords(kws, e));
    if (ex) return { ok: false, spaces: 0, why: `${tr.name} cannot transport ${ex} models` };
    if (tr.phrase ? !hasAllKeywords(kws, tr.phrase) : !(kws.has('INFANTRY') && m.dcUnit.faction_id === tr.faction))
      return { ok: false, spaces: 0, why: tr.phrase ? `only ${tr.phrase} models` : 'only Infantry of this army (the rules data names no other)' };
    const mult = Math.max(1, ...tr.multipliers.filter(x => hasAllKeywords(kws, x.keyword)).map(x => x.spaces));
    spaces += (m.ru.model_count ?? 1) * mult;
  }
  return { ok: true, spaces, why: null };
}

/** Roster -> combat units. A bodyguard and the characters attached to it are one unit. */
export function combatUnits(roster, attachments = defaultAttachments(roster)) {
  const parts = rosterParts(roster);
  const byIndex = new Map(parts.map(p => [p.index, p]));
  const taken = new Set();
  const attachedTo = new Map(); // bodyguard index -> [character parts]
  for (const [ci, bi] of Object.entries(attachments ?? {})) {
    const c = byIndex.get(Number(ci)), b = byIndex.get(Number(bi));
    if (!c || !b || c === b) continue;
    if (!attachedTo.has(b.index)) attachedTo.set(b.index, []);
    attachedTo.get(b.index).push(c);
    taken.add(c.index);
  }
  const seen = new Map();
  const out = [];
  for (const p of parts) {
    if (taken.has(p.index)) continue;
    const leaders = attachedTo.get(p.index) ?? [];
    const members = [
      ...leaders.map(l => ({ ...l, role: 'leader', attachRole: attachRole(l) ?? 'leader' })),
      { ...p, role: leaders.length ? 'bodyguard' : 'single' },
    ];
    const baseName = [...leaders.map(l => l.dcUnit.name), p.dcUnit.name].join(' + ');
    const n = (seen.get(baseName) ?? 0) + 1;
    seen.set(baseName, n);
    const keywords = new Set();
    for (const m of members) for (const k of [...(m.dcUnit.keywords ?? []), ...(m.dcUnit.faction_keywords ?? []), ...enhancementGrants(m.ru).keywords]) keywords.add(k.toUpperCase());
    out.push({
      key: `u${p.index}`,
      index: p.index,
      baseName,
      name: baseName + (n > 1 ? ` (${n})` : ''),
      members,
      keywords: [...keywords],
      models: members.reduce((s, m) => s + (m.ru.model_count ?? 1), 0),
      points: members.reduce((s, m) => s + (listedPoints(m.ru) ?? 0), 0),
      // a lone character that could join a unit
      canJoin: !leaders.length && attachRole(p) != null,
      // a non-character unit that characters can join
      canHost: !isCharacter(p.dcUnit),
    });
  }
  // label duplicates "(1)" too once a "(2)" exists
  for (const u of out) if (seen.get(u.name) > 1) u.name += ' (1)';
  return out;
}

/** Short display name of a roster unit, numbered when the army has several. */
export function rosterUnitLabel(army, index) {
  const parts = rosterParts(army.roster);
  const p = parts.find(x => x.index === index);
  if (!p) return '?';
  const same = parts.filter(x => x.dcUnit.id === p.dcUnit.id);
  return same.length > 1 ? `${p.dcUnit.name} (${same.indexOf(p) + 1})` : p.dcUnit.name;
}

/**
 * Characters that could join bodyguard roster unit `bodyguardIndex`:
 * [{index, name, role, eligible, attachedTo (roster index|null), replaces (index|null)}]
 * Eligible ones first. Ineligible characters are listed too (the dataset's
 * Leader lists can lag a new codex) — the player decides.
 */
export function attachCandidates(army, bodyguardIndex) {
  const parts = rosterParts(army.roster);
  const bg = parts.find(p => p.index === bodyguardIndex);
  if (!bg) return [];
  const att = army.attachments ?? {};
  const out = [];
  for (const p of parts) {
    const role = attachRole(p);
    if (!role || p.index === bodyguardIndex) continue;
    const cur = att[p.index] ?? null;
    if (cur === bodyguardIndex) continue; // already here
    const replaces = Object.entries(att).find(([ci, bi]) => bi === bodyguardIndex &&
      attachRole(parts.find(x => x.index === Number(ci))) === role)?.[0];
    out.push({
      index: p.index,
      name: rosterUnitLabel(army, p.index),
      role,
      eligible: eligibleBodyguardIds(p).has(bg.dcUnit.id),
      attachedTo: cur,
      replaces: replaces != null ? Number(replaces) : null,
    });
  }
  return out.sort((a, b) => Number(b.eligible) - Number(a.eligible) || a.name.localeCompare(b.name));
}

/** Units a lone character could join: [{index, name, eligible, replaces}]. */
export function joinCandidates(army, characterIndex) {
  const parts = rosterParts(army.roster);
  const c = parts.find(p => p.index === characterIndex);
  const role = c ? attachRole(c) : null;
  if (!role) return [];
  const ids = eligibleBodyguardIds(c);
  const att = army.attachments ?? {};
  return parts.filter(p => p.index !== characterIndex && !isCharacter(p.dcUnit) && att[characterIndex] !== p.index)
    .map(p => {
      const replaces = Object.entries(att).find(([ci, bi]) => bi === p.index && Number(ci) !== characterIndex &&
        attachRole(parts.find(x => x.index === Number(ci))) === role)?.[0];
      return { index: p.index, name: rosterUnitLabel(army, p.index), eligible: ids.has(p.dcUnit.id), replaces: replaces != null ? Number(replaces) : null };
    })
    .sort((a, b) => Number(b.eligible) - Number(a.eligible) || a.name.localeCompare(b.name));
}

/**
 * New attachments map with `characterIndex` joined to `bodyguardIndex`
 * (null = detach). 11e: one Leader and one Support per bodyguard — a
 * character of the same role already there is detached.
 */
export function withAttachment(army, characterIndex, bodyguardIndex) {
  const parts = rosterParts(army.roster);
  const att = { ...(army.attachments ?? {}) };
  delete att[characterIndex];
  if (bodyguardIndex != null) {
    const role = attachRole(parts.find(p => p.index === characterIndex)) ?? 'leader';
    for (const [ci, bi] of Object.entries(att)) {
      if (bi === bodyguardIndex && (attachRole(parts.find(p => p.index === Number(ci))) ?? 'leader') === role) delete att[ci];
    }
    att[characterIndex] = bodyguardIndex;
  }
  return att;
}

// ---------------------------------------------------------------------------
// Model groups (per member): [{modelName, count, profile, wargear: [{id, perModel}]}]

function profileFor(dcUnit, modelName) {
  const key = normName(modelName ?? '');
  return dcUnit.profiles.find(p => normName(p.name) === key) ??
    dcUnit.profiles.find(p => key.includes(normName(p.name)) || normName(p.name).includes(key)) ??
    dcUnit.profiles[0];
}

function modelGroups(member) {
  const { ru, dcUnit } = member;
  if ((ru.loadout_groups ?? []).length) {
    return ru.loadout_groups.map(g => ({
      modelName: g.model_name,
      count: g.count,
      profile: profileFor(dcUnit, g.model_name),
      wargear: (g.wargear ?? []).filter(w => w.ref?.id).map(w => ({ id: w.ref.id, perModel: w.count ?? 1 })),
    }));
  }
  const n = ru.model_count ?? 1;
  return [{
    modelName: dcUnit.name,
    count: n,
    profile: dcUnit.profiles[0],
    // unit-wide counts: spread as "count across the unit" (perModel = total / n)
    wargear: (ru.wargear ?? []).filter(w => w.ref?.id).map(w => ({ id: w.ref.id, perModel: (w.count ?? 1) / n })),
  }];
}

// ---------------------------------------------------------------------------
// Weapons

const SUPPORTED_KW = new Set([
  'torrent', 'lethal-hits', 'sustained-hits', 'devastating-wounds', 'twin-linked', 'blast', 'cleave',
  'rapid-fire', 'melta', 'heavy', 'lance', 'ignores-cover', 'indirect-fire', 'precision', 'hazardous',
  'psychic', 'anti', 'hunter', 'pistol', 'close-quarters', 'extra-attacks', 'one-shot', 'assault',
]);

export function weaponKw(keywords) {
  const kw = { anti: [] };
  const tags = [];
  const unsupported = [];
  // 04.01.03: a Hunter profile "can only target units with the specified keywords". A profile
  // can name several (e.g. Monster and Vehicle): the target needs one of them.
  const hunters = [];
  // 24.01: an ability written with keywords ("[Lethal Hits: non-Monster/Vehicle]") "only applies if the
  // target unit has one or more of those keywords". limits: [{ field, any, not, label }] - field is the
  // kw field it switches (or 'anti:<KEYWORD>').
  const limits = [];
  for (const k of keywords ?? []) {
    const p = k.parameters ?? {};
    const id = k.keyword_id;
    const any = (p.required_target_keywords_any ?? []).map(x => String(x).toUpperCase());
    const not = (p.excluded_target_keywords ?? []).map(x => String(x).toUpperCase());
    const limited = any.length > 0 || not.length > 0;
    const field = { 'lethal-hits': 'lethal', 'sustained-hits': 'sustained', 'devastating-wounds': 'dev', 'twin-linked': 'twin', lance: 'lance', precision: 'precision', 'ignores-cover': 'ignoresCover', anti: `anti:${String(p.target_keyword ?? '').toUpperCase()}` }[id];
    switch (id) {
      case 'torrent': kw.torrent = true; break;
      case 'lethal-hits': kw.lethal = true; break;
      case 'sustained-hits': {
        const v = p.value ?? 1;
        if (typeof v === 'string' && /^d\d+$/i.test(v)) { kw.sustained = parseInt(v.slice(1), 10); kw.sustainedDice = true; }
        else kw.sustained = Number(v) || 1;
        break;
      }
      case 'devastating-wounds': kw.dev = true; break;
      case 'twin-linked': kw.twin = true; break;
      case 'blast': kw.blast = Number(p.value ?? 1) || 1; break;
      case 'cleave': kw.cleave = Number(p.value ?? 1) || 1; break;
      case 'rapid-fire': kw.rapidFire = Number(p.value ?? 1) || 1; break;
      case 'melta': kw.melta = Number(p.value ?? 2) || 2; break;
      case 'heavy': kw.heavy = true; break;
      case 'lance': kw.lance = true; break;
      case 'ignores-cover': kw.ignoresCover = true; break;
      case 'indirect-fire': kw.indirect = true; break;
      case 'precision': kw.precision = true; break;
      case 'hazardous': kw.hazardous = true; break;
      case 'psychic': kw.psychic = true; break;
      case 'anti': kw.anti.push({ keyword: String(p.target_keyword ?? '').toUpperCase(), threshold: Number(p.threshold ?? 4) }); break;
      case 'hunter': { const h = String(p.target_keyword ?? '').toUpperCase(); if (h && !hunters.includes(h)) hunters.push(h); break; }
      case 'assault': kw.assault = true; break;
      case 'pistol': kw.pistol = true; break;
      case 'close-quarters': kw.cq = true; break;
      case 'extra-attacks': kw.extraAttacks = true; break;
      case 'one-shot': kw.oneShot = true; break;
      default: break;
    }
    const words = (xs) => xs.map(x => x.charAt(0) + x.slice(1).toLowerCase()).join('/');
    const label = (id === 'anti' ? `Anti-${String(p.target_keyword ?? '').toLowerCase()} ${p.threshold ?? 4}+`
      : id.replace(/-/g, ' ') + (p.value != null ? ` ${p.value}` : '') + (id === 'hunter' && p.target_keyword ? ` (${p.target_keyword})` : ''))
      + (limited ? `: ${any.length ? `${words(any)} only` : `not ${words(not)}`}` : '');
    tags.push(label);
    if (limited && field) limits.push({ field, any, not, label });
    if (!SUPPORTED_KW.has(id) || (limited && !field)) unsupported.push(label);
  }
  return { kw, tags, unsupported, hunters, hunter: hunters[0] ?? null, limits };
}

/**
 * A weapon's abilities against one target: those limited to other targets are switched off (24.01).
 * -> { kw, off: [labels of the abilities that do not apply] }
 */
export function limitKw(kw, limits, targetKeywords) {
  if (!limits?.length || !targetKeywords) return { kw, off: [] };
  const has = (k) => targetKeywords.has(k);
  const out = { ...kw, anti: [...(kw.anti ?? [])] };
  const off = [];
  for (const l of limits) {
    if ((!l.any.length || l.any.some(has)) && !l.not.some(has)) continue;
    off.push(l.label);
    if (l.field.startsWith('anti:')) out.anti = out.anti.filter(a => String(a.keyword).toUpperCase() !== l.field.slice(5));
    else if (l.field === 'sustained') { out.sustained = 0; out.sustainedDice = false; }
    else out[l.field] = false;
  }
  return { kw: out, off };
}

function weaponProfiles(factionId, weaponId) {
  const w = conv.wres.resolve(factionId, weaponId);
  if (!w) return [];
  return w.profiles.map((prof, pi) => {
    const melee = prof.range === 'Melee';
    const { kw, tags, unsupported, hunters, limits } = weaponKw(prof.keywords);
    const skill = melee ? prof.stats.WS : prof.stats.BS;
    return {
      weaponId,
      profileIndex: pi,
      profileCount: w.profiles.length,
      name: w.profiles.length > 1 ? `${w.name} – ${prof.name}` : w.name,
      melee,
      range: melee ? 'Melee' : `${prof.range}"`,
      A: String(prof.stats.A),
      skill: skill == null || skill === 'N/A' ? null : Number(skill),
      S: Number(prof.stats.S),
      AP: Number(prof.stats.AP) || 0,
      D: String(prof.stats.D),
      kw, tags, unsupported, hunters, limits,
    };
  });
}

function profileLine(p) {
  const sk = p.skill == null ? '' : ` ${p.melee ? 'WS' : 'BS'}${p.skill}+`; // torrent: no BS (auto-hits)
  return `A${p.A}${sk} S${p.S} AP${p.AP} D${p.D}`;
}

const upperKw = (k) => String(k ?? '').toUpperCase();
const orWords = (xs) => (xs.length > 1 ? `${xs.slice(0, -1).join(', ')} or ${xs[xs.length - 1]}` : String(xs[0] ?? ''));
const titleWord = (s) => s.charAt(0) + s.slice(1).toLowerCase();

/**
 * Weapon rows for an attacking combat unit in `phase` ('shooting' | 'fight').
 * Each row is one weapon profile of one datasheet in the unit:
 *   { id, label, member, stats, range, ...profile, max, count, blocked, usable,
 *     wkey, extra, cq, parts: [{ g, n }] }
 * `max` is the number of those weapons in the unit; `count` the number that
 * attack. The array also carries `groups` ([{ id, count, vm }]: the groups of
 * identical models) and `shooting` (the shooting type), which choose.mjs needs.
 *
 * What can attack (the rules are quoted in choose.mjs):
 *  - fight: per model, every EXTRA ATTACKS weapon plus ONE other melee weapon;
 *  - shooting: every ranged weapon, but a model that is not a MONSTER / VEHICLE
 *    shoots its CLOSE-QUARTERS / PISTOL weapons or its other weapons;
 *  - a weapon with several profiles uses one of them; a Hunter profile only
 *    against a unit with one of its keywords;
 *  - opts.shooting 'assault' (the unit advanced): only ASSAULT weapons;
 *    'cq' (the unit is engaged): only CLOSE-QUARTERS weapons, MONSTER / VEHICLE
 *    models excepted;
 *  - opts.targetEngaged (an engaged MONSTER / VEHICLE): no BLAST weapons (17.03);
 *  - an ability limited to targets with (or without) a keyword is off against
 *    other targets (24.01): row.kw is what applies, row.tagsOff what does not.
 *
 * `count` here is the first guess from the quick analytic value (no engine):
 * right whenever there is nothing to choose. With a target and its set-up the
 * page and the worker choose with the engine (choiceProblem + choose.mjs).
 */
export function attackerRows(cu, phase, target = null, opts = {}) {
  const rows = new Map();
  const groups = [];
  const tgtKeywords = target ? new Set((target.keywords ?? []).map(upperKw)) : null;
  const fight = phase !== 'shooting';
  const shooting = fight ? 'normal' : (opts.shooting ?? 'normal');
  const blockedWhy = (p, vm) => {
    if (p.hunters.length && tgtKeywords && !p.hunters.some(h => tgtKeywords.has(h))) return `Hunter profile: only targets ${orWords(p.hunters.map(titleWord))} units`;
    if (!fight && shooting === 'assault' && !p.kw.assault) return 'After an advance only Assault weapons shoot';
    if (!fight && shooting === 'cq' && !vm && !(p.kw.cq || p.kw.pistol)) return 'Engaged: only Close-quarters weapons shoot';
    if (!fight && opts.targetEngaged && p.kw.blast) return 'Blast weapons cannot target an engaged unit';
    return null;
  };
  const multi = cu.members.length > 1;
  for (const member of cu.members) {
    const vm = (member.dcUnit.keywords ?? []).some(k => /^(monster|vehicle)$/i.test(k));
    modelGroups(member).forEach((g, gi) => {
      const gid = `${member.index}.${gi}`;
      let any = false;
      for (const wg of g.wargear) {
        const n = Math.round(wg.perModel * g.count);
        if (n <= 0) continue;
        for (const p of weaponProfiles(member.factionId, wg.id)) {
          if (p.melee !== fight) continue;
          any = true;
          const key = `${member.index}:${p.weaponId}:${p.profileIndex}`;
          let row = rows.get(key);
          if (!row) {
            const blocked = blockedWhy(p, vm);
            const lim = limitKw(p.kw, p.limits, tgtKeywords);
            row = {
              id: key,
              member: member.dcUnit.name,
              label: (multi && member.role === 'leader' ? `${member.dcUnit.name}: ` : '') + p.name,
              stats: profileLine(p),
              range: p.range,
              ...p,
              kw: lim.kw, tagsOff: lim.off,
              wkey: `${member.index}:${p.weaponId}`,
              lead: member.role === 'leader',        // an attached character's weapon
              extra: !!p.kw.extraAttacks,
              cq: !!(p.kw.cq || p.kw.pistol),
              max: 0, count: 0,
              blocked,
              // a Hunter profile is never the first guess while the target is not known
              usable: !blocked && !(p.hunters.length && !tgtKeywords),
              parts: [],
            };
            rows.set(key, row);
          }
          row.max += n;
          const part = row.parts.find(x => x.g === gid);
          if (part) part.n += n; else row.parts.push({ g: gid, n });
        }
      }
      if (any) groups.push({ id: gid, count: g.count, vm });
    });
  }
  const out = [...rows.values()].filter(r => r.max > 0);
  const counts = solveCounts({ phase: fight ? 'fight' : 'shooting', shooting, groups, rows: out }, (r) => quickStat(r, target ?? {}));
  for (const r of out) r.count = r.usable ? (counts[r.id] ?? 0) : 0;
  out.groups = groups;
  out.shooting = shooting;
  return out;
}

/** Weapon row -> engine weapon. */
export function engineWeapon(row) {
  return {
    name: row.label, count: row.count, melee: row.melee,
    A: row.A, skill: row.skill, S: row.S, AP: row.AP, D: row.D,
    kw: row.kw,
    ...(row.lead ? { lead: true } : {}),
  };
}

/**
 * Battle-shock after an attack (08.03, 01.06, 01.07): the unit's best Leadership, its starting strength
 * (attached leaders included, 01.02.01) and the wounds of a single-model unit.
 * -> { ld, start, single: W of the one model or 0 }
 */
export function shockFacts(cu) {
  const lds = cu.members.flatMap(m => (m.dcUnit.profiles ?? []).map(p => parseInt(p.Ld, 10))).filter(n => n > 0);
  const single = cu.models === 1 ? parseInt(cu.members[0].dcUnit.profiles?.[0]?.W, 10) || 0 : 0;
  return { ld: lds.length ? Math.min(...lds) : 7, start: cu.models, single };
}

export function allVehicleMonster(cu) {
  return cu.members.every(m => (m.dcUnit.keywords ?? []).some(k => /^(monster|vehicle)$/i.test(k)));
}

// ---------------------------------------------------------------------------
// Abilities (display) and defender rules (auto-detected, toggleable)

function abilityRecords(member) {
  const out = [];
  for (const aid of member.dcUnit.ability_ids ?? []) {
    const a = conv.ares.resolve(member.factionId, aid);
    if (!a) continue;
    out.push({ id: aid, name: a.name, type: a.ability_type, text: conv.safeDescribe(a), record: a });
  }
  const eid = member.ru.enhancement?.id ?? member.ru.enhancement?.ref?.id;
  if (eid) {
    const e = (dc.RAW_DATA.enhancements ?? []).find(x => x.id === eid);
    if (e) out.push({ id: eid, name: `${e.name} (enhancement)`, type: 'enhancement', text: e.rules_text ?? '', record: e });
  }
  return out;
}

export function abilitiesOf(cu) {
  const out = [];
  for (const m of cu.members) {
    for (const a of abilityRecords(m)) {
      if (a.type === 'detachment' || /^leader$/i.test(a.name)) continue;
      out.push({ member: m.dcUnit.name, name: a.name, type: a.type, text: a.text });
    }
  }
  return out;
}

// Core abilities the phase sheet writes itself, with the rule in a line (phasesheet.mjs coreEntries);
// Leader and Support are choices made when the list is written.
const CORE_ON_SHEET = /^(leader|support|deep-strike|infiltrators|scouts-\d|lone-operative|stealth|fights-first|firing-deck-\d|damaged-\d|deadly-demise-|feel-no-pain-\d)/;
let PHASE_MAP = null;
/** The rules data's phase mapping by id ("provisional", 40kdc community): Map 'type:id' -> phases. */
function phaseMap() {
  if (!PHASE_MAP) {
    PHASE_MAP = new Map();
    for (const m of dc.RAW_DATA.phaseMappings ?? []) PHASE_MAP.set(`${m.source_type}:${m.source_id}`, m.phases ?? []);
  }
  return PHASE_MAP;
}

/**
 * What phasesheet.mjs needs to sort an army's rules by phase: every unit's abilities (with the model that has
 * them), its core abilities, the detachment rules, the stratagems, and the phase mapping of the rules data.
 */
export function phaseSheetInput(army) {
  const pm = phaseMap();
  const rules = armyRules(army);
  const atArmyLevel = new Set([...rules, ...detachmentRules(army)].map(r => r.id));
  const units = army.units.map(cu => {
    const abilities = [];
    let fnp = 0;
    cu.members.forEach((m, mi) => {
      for (const a of abilityRecords(m)) {
        if (atArmyLevel.has(a.id)) continue;                         // the army rule and the detachment rules: listed once
        if (a.type === 'core') {
          const x = /^feel-no-pain-(\d)/.exec(String(a.id));
          if (x) fnp = fnp ? Math.min(fnp, Number(x[1])) : Number(x[1]);
          if (CORE_ON_SHEET.test(String(a.id))) continue;
        }
        // a rule of another detachment on a datasheet ("units with this ability"): an army-wide rule
        abilities.push({ id: a.id, name: a.name, text: a.text, type: a.type === 'detachment' ? 'faction' : a.type, owner: { id: `${cu.key}:${mi}`, name: m.dcUnit.name, unit: cu.name } });
      }
    });
    return { id: cu.key, name: cu.name, flags: { ...coreFlags(cu), fnp }, abilities };
  });
  return {
    units,
    armyRules: rules,
    detachmentRules: detachmentRules(army),
    stratagems: armyStratagems(army),
    mapped: (id, type = 'ability') => pm.get(`${type}:${id}`) ?? null,
  };
}

/**
 * The army rule(s) of the list's faction (Combat Doctrines, Waaagh!, Martial Ka'tah): [{ id, name, text }].
 * From the faction record's faction_rule_ids; a chapter without its own takes its parent faction's.
 */
export function armyRules(army) {
  const facs = dc.RAW_DATA.factions ?? [];
  const f = facs.find(x => x.id === army.roster.faction_id);
  const ids = f?.faction_rule_ids?.length ? f.faction_rule_ids : facs.find(x => x.id === f?.parent_faction_id)?.faction_rule_ids ?? [];
  const out = [];
  for (const id of ids) {
    const a = (dc.RAW_DATA.abilities ?? []).find(x => x.ability_id === id);
    if (a) out.push({ id, name: a.name, text: conv.safeDescribe(a) });
  }
  return out;
}

// Activated / situational wording: detected but OFF by default.
const ACTIVATED_RE = /\b(you can|at the start of|until the end of|until the start of|when an enemy unit|when this unit|select|once per battle|first time|psychic roll|while this unit is within|while this model is within|within range of an objective|if this unit made|if this model made|battle-shocked|in your|in the (fight|shooting|movement|command) phase)\b/i;

function parseStructured(a) {
  const e = a?.effect;
  if (!e || a.rules_text) return null;
  const permanent = (a.scope?.duration ?? 'permanent') === 'permanent';
  const out = [];
  const mod = e.modifier ?? {};
  const phases = mod.attack_type === 'ranged' ? ['shooting'] : mod.attack_type === 'melee' ? ['fight'] : ['shooting', 'fight'];
  if (e.type === 'feel-no-pain' && mod.threshold) {
    const v = Number(mod.threshold);
    const sc = String(mod.scope ?? mod.against_attack_type ?? '');
    if (sc === 'mortal') out.push({ label: `FNP ${v}+ vs mortal wounds`, apply: { fnpMortal: v }, phases });
    else if (sc === 'psychic') out.push({ label: `FNP ${v}+ vs psychic attacks`, apply: { fnpPsychic: v }, phases });
    else if (sc === 'psychic-and-mortal') out.push({ label: `FNP ${v}+ vs psychic & mortal`, apply: { fnpMortal: v, fnpPsychic: v }, phases });
    else if (!mod.applies_to_keywords) out.push({ label: `Feel No Pain ${v}+`, apply: { fnp: v }, phases });
  } else if (e.type === 'damage-reduction') {
    const r = mod.reduction ?? mod.value ?? mod.amount;
    if (r === 1 || r === 'half') out.push({ label: r === 'half' ? 'Halve Damage' : '-1 Damage', apply: { dr: r }, phases });
  } else if (e.type === 'invulnerable-save' && mod.invuln_sv) {
    out.push({ label: `${mod.invuln_sv}+ invulnerable save`, apply: { InSv: Number(mod.invuln_sv) }, phases });
  } else if (e.type === 'roll-modifier' && e.target === 'attacker' && mod.operation === 'subtract') {
    if (mod.roll === 'hit') out.push({ label: '-1 to hit', apply: { hitMod: -1 }, phases });
    if (mod.roll === 'wound') out.push({ label: '-1 to wound', apply: { woundMod: -1 }, phases });
  }
  return out.length ? { effects: out, permanent } : null;
}

/**
 * Defender profile: model groups + detected rules.
 * groups: [{key, name, member, count, W, Sv, InSv, T, character}]
 * rules:  [{id, source, label, text, auto, phases, apply, scope: 'unit'|'member', member, groupKeys}]
 */
export function defenderProfile(cu, army = null) {
  const groups = [];
  const rules = [];
  for (const m of cu.members) {
    const char = isCharacter(m.dcUnit);
    const mg = modelGroups(m);
    mg.forEach((g, gi) => {
      const p = g.profile;
      groups.push({
        key: `${m.index}:${gi}`,
        name: g.modelName,
        member: m.index,
        count: g.count,
        W: p.W, Sv: p.Sv, InSv: p.invuln_sv ?? 0, T: p.T,
        character: char && m.role !== 'bodyguard',
        ptsPerModel: (listedPoints(m.ru) ?? 0) / Math.max(1, m.ru.model_count ?? 1),
        wargearNames: g.wargear.map(w => looseName(conv.wres.resolve(m.factionId, w.id)?.name ?? w.id.replace(/-/g, ' '))),
      });
    });
    const memberGroups = groups.filter(g => g.member === m.index);
    for (const a of abilityRecords(m)) {
      if (a.type === 'detachment') continue;
      // core abilities by id
      const idFnp = String(a.id).match(/^feel-no-pain-(\d)$/);
      let effects = [];
      let permanent = true;
      if (idFnp) effects = [{ label: `Feel No Pain ${idFnp[1]}+`, apply: { fnp: Number(idFnp[1]) }, phases: ['shooting', 'fight'] }];
      else if (/^stealth$/i.test(a.name)) effects = [{ label: 'Stealth (cover vs ranged)', apply: { cover: true }, phases: ['shooting'] }];
      else {
        const st = parseStructured(a.record);
        if (st) { effects = st.effects; permanent = st.permanent; }
        else { effects = parseDefensiveText(a.text); permanent = !ACTIVATED_RE.test(a.text); }
      }
      if (!effects.length) continue;
      const leading = /while this model is leading a unit|while this model is attached/i.test(a.text);
      const otherChars = /other CHARACTER models/i.test(a.text);
      const thisModel = /\bthis model\b/i.test(a.text) && !/this unit/i.test(a.text);
      // which groups does it cover?
      let groupKeys;
      let carried = true;
      if (a.type === 'wargear') {
        // 22.04: a wargear ability belongs to the models that carry the wargear. When the list names no carrier
        // (the wargear is not in it) the rule is shown, switched off: no model gets it by default.
        const name = looseName(a.name);
        const carriers = memberGroups.filter(g => g.wargearNames.includes(name));
        carried = carriers.length > 0;
        groupKeys = (carried ? carriers : memberGroups).map(g => g.key);
      } else if (otherChars) {
        groupKeys = groups.filter(g => g.character && g.member !== m.index).map(g => g.key);
      } else if (leading) {
        groupKeys = null; // whole attached unit
      } else if (thisModel || m.role === 'leader') {
        groupKeys = memberGroups.map(g => g.key);
      } else {
        groupKeys = null; // "this unit"
      }
      const autoOn = (always) => carried && (permanent || always) && (!leading || m.role === 'leader');
      effects.forEach((ef, k) => {
        rules.push({
          id: `${m.index}:${a.id}:${k}`,
          source: a.name,
          member: m.dcUnit.name,
          label: ef.label,
          text: a.text,
          auto: autoOn(!!ef.always),
          notCarried: !carried,
          phases: ef.phases,
          apply: ef.apply,
          groupKeys,
        });
      });
    }
  }
  // detachment rules (always-on ones auto) and defensive stratagems (off: they cost CP)
  const stratText = [];
  if (army) {
    for (const d of detachmentRules(army)) {
      const effects = parseDefensiveText(d.text);
      effects.forEach((ef, k) => rules.push({
        id: `det:${d.id}:${k}`, source: d.name, member: 'Detachment', label: ef.label, text: d.text,
        auto: !ACTIVATED_RE.test(d.text) && !/\b(if|while)\b/i.test(d.text), phases: ef.phases, apply: ef.apply, groupKeys: null, kind: 'detachment',
      }));
    }
    for (const st of armyStratagems(army)) {
      // Command Re-roll (15.02) can re-roll a save: one failed save, once in the phase
      if (st.detachment === 'Core' && /^COMMAND RE-?ROLL$/i.test(st.name) && !st.missing) {
        rules.push({ id: `strat:${st.id}:save`, source: `${st.name} (${st.cp}CP)`, member: 'Stratagem', label: 'Re-roll one save',
          text: `WHEN: ${st.when}\nEFFECT: ${st.effect}`, auto: false, phases: ['shooting', 'fight'], apply: { rerollOneSave: true }, groupKeys: null, kind: 'stratagem', cp: st.cp });
        continue;
      }
      if (stratagemRole(st) !== 'defend' || !stratagemEligible(st, cu.keywords)) continue;
      const effects = st.missing ? [] : parseDefensiveText(st.effect);
      if (!effects.length) { stratText.push(st); continue; }
      effects.forEach((ef, k) => rules.push({
        id: `strat:${st.id}:${k}`, source: `${st.name} (${st.cp}CP)`, member: 'Stratagem', label: ef.label,
        text: `WHEN: ${st.when}\nEFFECT: ${st.effect}`, auto: false, phases: ef.phases.filter(p => stratagemPhases(st).includes(p)),
        apply: ef.apply, groupKeys: null, kind: 'stratagem', cp: st.cp,
      }));
    }
  }
  // leaders' groups listed after bodyguards
  groups.sort((x, y) => Number(x.character) - Number(y.character));
  return { name: cu.name, keywords: cu.keywords, groups, rules, stratText };
}

/** Summary stats for the target card / weapon defaults. */
export function defenderSummary(profile) {
  const bg = profile.groups.filter(g => !g.character);
  const main = bg.length ? bg : profile.groups;
  return {
    T: Math.max(...main.map(g => g.T)),
    Sv: Math.min(...main.map(g => g.Sv)),
    InSv: main.map(g => g.InSv).filter(Boolean).reduce((a, b) => Math.min(a, b), 7) % 7, // 0 = none
    W: [...main].sort((a, b) => b.count - a.count)[0]?.W ?? 1, // the bulk of the unit
    models: profile.groups.reduce((s, g) => s + g.count, 0),
    keywords: profile.keywords,
  };
}

const GROUP_FIELDS = new Set(['InSv', 'dr', 'fnp', 'W']);

/**
 * Engine defender for the chosen phase.
 * enabled: Set of rule ids switched on; manual: defender-side manual mods
 * (they win over / combine with the detected ones); overrides: per group key
 * {count, woundsLeftFirst}.
 */
export function buildDefender(profile, enabled, phase, manual = {}, overrides = {}) {
  const mods = {};
  const groups = profile.groups.map(g => ({ ...g, ...(overrides[g.key] ?? {}) }));
  const byKey = new Map(groups.map(g => [g.key, g]));
  for (const r of profile.rules) {
    if (!enabled.has(r.id) || !r.phases.includes(phase)) continue;
    for (const [k, v] of Object.entries(r.apply)) {
      const targets = r.groupKeys ? r.groupKeys.map(key => byKey.get(key)).filter(Boolean) : groups;
      if (GROUP_FIELDS.has(k)) {
        for (const g of targets) {
          if (k === 'W') g.W += v;          // "+1 W" on the models that carry it
          else if (k === 'InSv') g.InSv = g.InSv ? Math.min(g.InSv, v) : v;
          else if (k === 'fnp') g.fnp = g.fnp ? Math.min(g.fnp, v) : v;
          else if (k === 'dr') g.dr = v === 'half' || g.dr === 'half' ? 'half' : Math.max(g.dr || 0, v);
        }
      } else if (k === 'fnpMortal' || k === 'fnpPsychic') {
        mods[k] = mods[k] ? Math.min(mods[k], v) : v;
      } else if (k === 'cover') {
        mods.cover = true;
      } else if (k === 'rerollOneSave') {
        mods.rerollOneSave = true;
      } else {
        mods[k] = (mods[k] ?? 0) + v;
      }
    }
  }
  // manual defender modifiers
  const out = { ...mods };
  for (const [k, v] of Object.entries(manual ?? {})) {
    if (v == null || v === 0 || v === false || v === '') continue;
    if (k === 'cover') out.cover = true;
    // 17.03: only an engaged MONSTER / VEHICLE can be shot at all (with -1 to hit)
    else if (k === 'engaged') { if ((profile.keywords ?? []).some(x => /^(MONSTER|VEHICLE)$/i.test(x))) out.engagedMV = true; }
    else if (k === 'fnp' || k === 'fnpMortal' || k === 'invuln') out[k] = out[k] ? Math.min(out[k], v) : v;
    else if (k === 'damageReduction') out.damageReduction = v;
    else out[k] = (out[k] ?? 0) + v;
  }
  // 05.03: one allocation group per CHARACTER model; every other model with
  // the same W / Sv / InSv shares a group (T, DR and FNP kept in the key so
  // per-model rules stay exact).
  const merged = [];
  const index = new Map();
  for (const g of groups) {
    if (!(g.count > 0)) continue;
    const eg = {
      name: g.name, count: g.count, W: g.W, Sv: g.Sv, InSv: g.InSv || 0, T: g.T,
      character: g.character, woundsLeftFirst: g.woundsLeftFirst ?? null,
      dr: g.dr || 0, fnp: g.fnp || 0, ptsPerModel: g.ptsPerModel || 0,
    };
    const key = g.character ? null : [eg.W, eg.Sv, eg.InSv, eg.T, eg.dr, eg.fnp, eg.ptsPerModel].join('|');
    const prev = key ? index.get(key) : null;
    if (prev && (prev.woundsLeftFirst == null || eg.woundsLeftFirst == null)) {
      prev.count += eg.count;
      if (eg.woundsLeftFirst != null) prev.woundsLeftFirst = eg.woundsLeftFirst;
      if (!prev.name.includes(eg.name)) prev.name += ` / ${eg.name}`;
      continue;
    }
    merged.push(eg);
    if (key) index.set(key, eg);
  }
  return { name: profile.name, keywords: profile.keywords, groups: merged, mods: out };
}

// ---------------------------------------------------------------------------
// Detachment rules and stratagems of an army

function armyDetachmentRecords(army) {
  const out = [];
  for (const rd of army.roster.detachments ?? []) {
    const id = rd?.ref?.id;
    const rec = (dc.RAW_DATA.detachments ?? []).find(d => d.id === id) ??
      (dc.RAW_DATA.detachments ?? []).find(d => normName(d.name) === normName(rd?.ref?.raw_name ?? ''));
    out.push({ id: id ?? normName(rd?.ref?.raw_name ?? ''), name: rec?.name ?? rd?.ref?.raw_name ?? '', record: rec });
  }
  return out;
}

/**
 * Detachment rule abilities: [{id, name, text, detachment}].
 * The rules of a detachment are the abilities of type 'detachment' that name it
 * (ability.detachment_id). The codex imports are linked that way only: their
 * detachment record has no detachment_rule_id, or still points to the
 * provisional rule from before the codex. So: the codex records (they carry a
 * `source`) when there are any, else what detachment_rule_id(s) point to.
 */
export function detachmentRules(army) {
  const out = [];
  const all = dc.RAW_DATA.abilities ?? [];
  for (const d of armyDetachmentRecords(army)) {
    if (!d.record) continue;
    const linked = all.filter(a => a.ability_type === 'detachment' && a.detachment_id === d.record.id);
    const codex = linked.filter(a => a.source);
    const pointed = [d.record.detachment_rule_id, ...(d.record.detachment_rule_ids ?? [])].filter(Boolean)
      .map(id => all.find(a => a.ability_id === id)).filter(Boolean);
    const use = codex.length ? codex : [...new Map([...pointed, ...linked].map(a => [a.ability_id, a])).values()];
    for (const a of use) out.push({ id: a.ability_id, name: `${a.name} (${d.name})`, text: conv.safeDescribe(a), detachment: d.name });
  }
  return out;
}

/** The army's detachment stratagems (Wahapedia 11e import), deduplicated. */
export function armyStratagems(army) {
  const dets = armyDetachmentRecords(army);
  const ids = new Set(dets.map(d => d.id));
  const names = new Set(dets.map(d => normName(d.name)));
  const seen = new Set();
  return STRATAGEMS.filter(st => (ids.has(st.detachmentId) || names.has(normName(st.detachment)) || st.detachment === 'Core') &&
    !seen.has(st.id) && seen.add(st.id));
}

// ---------------------------------------------------------------------------
// Attacker rules: unit / leader / enhancement abilities, detachment rules and
// detachment stratagems that modify this unit's attacks.

/**
 * [{id, kind: 'ability'|'detachment'|'stratagem', source, member (roster index|null),
 *   memberName, effects, apply, phases, scope, conds, text, cp, partial}]
 * plus `stratText`: the army's attack stratagems the parser could not model.
 */
const RULES_CACHE = new WeakMap();   // combat unit -> Map(army -> { rules, stratText }); units are rebuilt when a list or its attachments change
export function attackerRules(cu, army) {
  let byArmy = RULES_CACHE.get(cu);
  if (!byArmy) RULES_CACHE.set(cu, byArmy = new Map());
  if (!byArmy.has(army)) byArmy.set(army, attackerRulesBuild(cu, army));
  return byArmy.get(army);
}
function attackerRulesBuild(cu, army) {
  const rules = [];
  const one = (base, p, extra = {}) => ({
    ...base,
    effects: p.effects,
    apply: p.effects.reduce((acc, e) => mergeMods(acc, e.apply), {}),
    label: p.effects.map(e => e.label).join(', '),
    phases: p.phases,
    scope: p.scope,
    conds: p.conds,
    partial: p.partial,
    ...extra,
  });
  const push = (base, parsed) => {
    if (!parsed) return false;
    const alts = parsed.alternatives ?? [];
    // a choice rule ("X, or Y"): one rule per option, sharing a group so only one is on
    rules.push(one(base, parsed, alts.length ? { group: base.id, option: 1 } : {}));
    alts.forEach((a, i) => rules.push(one({ ...base, id: `${base.id}:alt${i + 1}` }, a,
      { group: base.id, option: i + 2, label: `or: ${a.effects.map(e => e.label).join(', ')}` })));
    return true;
  };
  for (const m of cu.members) {
    for (const a of abilityRecords(m)) {
      if (/^leader$/i.test(a.name)) continue;
      // rules for named weapons of the unit ("this unit's: • Thunder Hammer weapons have ... • Other melee weapons have ...")
      const bullets = parseWeaponBullets(a.text);
      if (bullets) {
        const named = bullets.map(b => b.weapon).filter(Boolean);
        bullets.forEach((b, i) => rules.push({
          id: `${m.index}:${a.id}:w${i}`, kind: 'ability', source: a.name, member: m.index, memberName: m.dcUnit.name, memberRole: m.role, text: a.text,
          effects: b.effects, apply: b.effects.reduce((acc, e) => mergeMods(acc, e.apply), {}),
          label: `${b.weapon ? b.weapon.replace(/\b\w/g, ch => ch.toUpperCase()) : `Other ${b.others === 'any' ? '' : `${b.others} `}weapons`}: ${b.effects.map(e => e.label).join(', ')}`,
          phases: b.phases, scope: 'weapon', conds: b.conds, partial: false,
          weapon: b.weapon, others: b.others, named,
        }));
        continue;
      }
      push({ id: `${m.index}:${a.id}`, kind: a.type === 'detachment' ? 'detachment' : 'ability', source: a.name,
        member: m.index, memberName: m.dcUnit.name, memberRole: m.role, text: a.text }, parseOffensive(a.text));
    }
  }
  const ownKw = new Set(cu.keywords.map(k => String(k).toUpperCase()));
  for (const d of detachmentRules(army)) {
    const parsed = parseOffensive(d.text);
    // a detachment rule for other units ("Attacks made by friendly Wulfen units ...") is not this unit's rule
    if (parsed?.conds?.selfAny?.length && !parsed.conds.selfAny.some(ph => phraseInKeywords(ph, ownKw))) continue;
    push({ id: `det:${d.id}`, kind: 'detachment', source: d.name, member: null, memberName: 'Detachment', text: d.text }, parsed);
  }
  const stratText = [];
  for (const st of armyStratagems(army)) {
    if (st.detachment === 'Core' && /^COMMAND RE-?ROLL$/i.test(st.name) && !st.missing) {
      // "If you are rolling more than one dice together, select one of those dice to re-roll"
      const base = { kind: 'stratagem', source: `${st.name} (${st.cp}CP)`, member: null, memberName: 'Stratagem',
        text: `WHEN: ${st.when}\nEFFECT: ${st.effect}`, cp: st.cp, scope: 'unit', conds: parseConditions(''), phases: ['shooting', 'fight'], partial: false };
      const opts = [['rerollOneHit', 'Re-roll one hit'], ['rerollOneWound', 'Re-roll one wound'], ['rerollOneDamage', 'Re-roll one damage roll']];
      opts.forEach(([k, label], i) => rules.push({ ...base, id: `strat:${st.id}${i ? `:alt${i}` : ''}`, group: `strat:${st.id}`, option: i + 1,
        effects: [{ label, apply: { [k]: true } }], apply: { [k]: true }, label: i ? `or: ${label}` : label }));
      continue;
    }
    if (stratagemRole(st) !== 'attack' || !stratagemEligible(st, cu.keywords)) continue;
    const parsed = st.missing ? null : parseOffensive(st.effect);
    const ok = push({ id: `strat:${st.id}`, kind: 'stratagem', source: `${st.name} (${st.cp}CP)`, member: null,
      memberName: 'Stratagem', text: `WHEN: ${st.when}\nEFFECT: ${st.effect}`, cp: st.cp, stratPhases: stratagemPhases(st) }, parsed);
    if (ok) {
      const wc = parseConditions(st.when);
      for (const r of rules.filter(x => x.id === `strat:${st.id}` || x.group === `strat:${st.id}`)) {
        r.phases = r.phases.filter(p => r.stratPhases.includes(p));
        // a stratagem's own WHEN conditions ("...that made a charge move this turn") still gate it
        r.conds.charged ||= wc.charged;
      }
    } else stratText.push(st);
  }
  return { rules, stratText };
}

/**
 * Is attacker rule `r` on? Stratagems only when the player switched them on;
 * abilities / detachment rules follow their conditions unless overridden.
 */
export function attackerRuleOn(r, override, ctx) {
  if (override === true) return true;
  if (override === false) return false;
  if (r.kind === 'stratagem') return false;
  return conditionsMet(r.conds, { ...ctx, leading: r.memberRole === 'leader' });
}

/**
 * Engine attacker for one attacking combat unit: manual mods + enabled rules
 * (unit-scoped rules into the unit's mods, model-scoped ones only onto that
 * member's weapons).
 */
export function buildAttacker(cu, rows, manualMods, rules, enabledIds, phase) {
  const { unitMods, perMember, perWeapon } = attackerMods(cu, manualMods, rules, enabledIds, phase);
  return {
    name: cu.name,
    mods: unitMods,
    weapons: rows.filter(r => r.count > 0).map(row => {
      const w = engineWeapon(row);
      const wm = weaponMods(row, perMember, perWeapon);
      if (wm) w.mods = wm;
      return w;
    }),
    allVehicleMonster: allVehicleMonster(cu),
  };
}

/** The modifiers of one weapon row: its datasheet's (a leader's own rules) plus the rules for weapons of its name. */
function weaponMods(row, perMember, perWeapon) {
  const mi = Number(String(row.id).split(':')[0]);
  let mods = perMember.get(mi) ?? null;
  for (const r of perWeapon) {
    const hit = r.weapon ? weaponNamed(row.label, r.weapon)
      : (r.others === 'any' || (r.others === 'melee') === !!row.melee) && !r.named.some(n => weaponNamed(row.label, n));
    if (hit) mods = mergeMods(mods ?? {}, r.apply);
  }
  return mods;
}

/**
 * The weapon choice of one attacking unit against one target, for choose.mjs:
 * every weapon row with its engine weapon (the unit's rules and modifiers
 * applied), the groups of models, and the engine attacker and defender.
 */
export function choiceProblem(cu, rows, manualMods, rules, enabledIds, phase, defender, target = null) {
  const { unitMods, perMember, perWeapon } = attackerMods(cu, manualMods, rules, enabledIds, phase);
  return {
    phase,
    shooting: rows.shooting ?? 'normal',
    groups: rows.groups ?? [],
    target: target ? { T: target.T, Sv: target.Sv, InSv: target.InSv } : undefined,
    attacker: { name: cu.name, mods: unitMods, allVehicleMonster: allVehicleMonster(cu) },
    defender,
    rows: rows.map(r => {
      const { count, ...w } = engineWeapon(r);
      const wm = weaponMods(r, perMember, perWeapon);
      if (wm) w.mods = wm;
      return { id: r.id, wkey: r.wkey, extra: r.extra, cq: r.cq, usable: r.usable, max: r.max, parts: r.parts, w };
    }),
  };
}

/** Unit-wide and per-datasheet modifiers of an attacking unit: manual ones plus the enabled rules. */
function attackerMods(cu, manualMods, rules, enabledIds, phase) {
  let unitMods = { ...(manualMods ?? {}) };
  const perMember = new Map();
  const perWeapon = [];        // rules for weapons of a given name (or "other melee weapons") of this unit
  // a model-scoped stratagem ("Select one CHARACTER model ... that model's melee weapons") goes to the characters
  const charMembers = cu.members.filter(m => m.role === 'leader' || (cu.members.length === 1 && (m.dcUnit.keywords ?? []).some(k => /^character$/i.test(k))));
  for (const r of rules) {
    if (!enabledIds.has(r.id) || !r.phases.includes(phase)) continue;
    const { mortals, ...apply } = r.apply;
    if (mortals?.length) unitMods = mergeMods(unitMods, { mortals });
    if (r.scope === 'weapon') perWeapon.push({ weapon: r.weapon, others: r.others, named: r.named ?? [], apply });
    else if (r.scope === 'model' && r.member != null) perMember.set(r.member, mergeMods(perMember.get(r.member) ?? {}, apply));
    else if (r.scope === 'model' && r.member == null && charMembers.length) for (const m of charMembers) perMember.set(m.index, mergeMods(perMember.get(m.index) ?? {}, apply));
    else unitMods = mergeMods(unitMods, apply);
  }
  // mortal-wound dice counted "per T" / "per model" resolve against this unit
  if (unitMods.mortals?.length) {
    const maxT = Math.max(...cu.members.flatMap(m => (m.dcUnit.profiles ?? []).map(p => p.T || 0)), 1);
    unitMods.mortals = unitMods.mortals.map(src => ({
      ...src, dice: src.dice === 'T' ? maxT : src.dice === 'models' ? cu.models : src.dice,
    }));
  }
  return { unitMods, perMember, perWeapon };
}

// ---------------------------------------------------------------------------
// Enemy cheat sheet

/**
 * Everything a player wants to know about a combat unit at a glance:
 * per-datasheet stat lines, weapons (both phases), abilities, and the rules
 * the calculator detects (defensive + offensive).
 */
export function unitIntel(cu, army) {
  const profiles = [];
  for (const m of cu.members) {
    for (const p of m.dcUnit.profiles ?? []) {
      profiles.push({
        member: m.dcUnit.name, name: p.name, role: m.role,
        M: p.M, T: p.T, Sv: p.Sv, InSv: p.invuln_sv ?? null, W: p.W, Ld: p.Ld, OC: p.OC,
      });
    }
  }
  // collapse identical lines (Sergeant / trooper with the same stats)
  const seenLine = new Set();
  const stats = profiles.filter(p => {
    const k = [p.member, p.M, p.T, p.Sv, p.InSv, p.W, p.Ld, p.OC].join('|');
    return !seenLine.has(k) && seenLine.add(k);
  });
  const weapons = [...attackerRows(cu, 'shooting', null), ...attackerRows(cu, 'fight', null)]
    .map(r => ({ label: r.label, range: r.range, stats: r.stats, tags: r.tags, count: r.max, melee: r.melee }));
  const def = defenderProfile(cu, army);
  const off = attackerRules(cu, army).rules.filter(r => r.kind !== 'stratagem');
  const fnp = Math.min(...def.rules.filter(r => r.auto && r.apply.fnp).map(r => r.apply.fnp), 7);
  return {
    name: cu.name,
    models: cu.models,
    points: cu.points,
    keywords: cu.keywords,
    stats,
    fnp: fnp < 7 ? fnp : null,
    weapons,
    abilities: abilitiesOf(cu),
    defensive: def.rules.filter(r => r.kind !== 'stratagem' && r.kind !== 'detachment')
      .map(r => ({ label: r.label, source: r.source, auto: r.auto })),
    offensive: off.map(r => ({ label: r.label, source: r.source, when: describeConditions(r.conds), phases: r.phases })),
  };
}

/** Army-level intel: detachment rules and every stratagem, grouped by phase. */
export function armyIntel(army) {
  const strats = armyStratagems(army).map(st => ({
    name: st.name, cp: st.cp, phase: st.phase, detachment: st.detachment, turn: st.turn,
    when: st.when, target: st.target, effect: st.effect, missing: st.missing, role: stratagemRole(st),
  }));
  return {
    faction: army.faction,
    detachments: armyDetachmentRecords(army).map(d => d.name).filter(Boolean),
    armyRules: armyRules(army),
    detachmentRules: detachmentRules(army),
    stratagems: strats,
  };
}

// ---------------------------------------------------------------------------
// Board planner

/**
 * Core abilities that decide where a unit can be and who can see it (board, brief):
 * { deepStrike, infiltrators, scouts (inches), loneOperative (inches, 0 = no), stealth, fightsFirst,
 *   damaged (X of "Damaged X", 0 = no), deadlyDemise ('D3', '1', ... or null), firingDeck (models) }
 * Deep Strike, Infiltrators, Scouts, Stealth and Fights First need every model of the unit to have them
 * (24.09 "if every model in this unit has this ability"); Lone Operative does not work in an attached
 * unit (24.24).
 */
export function coreFlags(cu) {
  const idsOf = (m) => (m.dcUnit.ability_ids ?? []).map(String);
  const every = (re) => cu.members.every(m => idsOf(m).some(id => re.test(id)));
  const first = (re) => { for (const m of cu.members) for (const id of idsOf(m)) { const x = id.match(re); if (x) return x; } return null; };
  const sc = cu.members.map(m => Number(idsOf(m).map(id => id.match(/^scouts-(\d+)/)).find(Boolean)?.[1] ?? 0));
  const lone = cu.members.length === 1 ? first(/^lone-operative(?:-(\d+))?/) : null;
  return {
    deepStrike: every(/^deep-strike/), infiltrators: every(/^infiltrators/),
    scouts: sc.every(n => n > 0) ? Math.min(...sc) : 0,
    loneOperative: lone ? Number(lone[1] ?? 12) : 0,
    stealth: every(/^stealth/), fightsFirst: every(/^fights-first/),
    damaged: Number(first(/^damaged-(\d+)/)?.[1] ?? 0),      // Damaged X: -1 to hit at X wounds or fewer (24.39)
    deadlyDemise: first(/^deadly-demise-(.+)$/)?.[1].toUpperCase() ?? null,
    firingDeck: Number(first(/^firing-deck-(\d+)/)?.[1] ?? 0),
  };
}

/**
 * A rule that lets one unit a turn arrive from reserves as if the battle round were one higher (High King of
 * Fenris: "when that unit makes an ingress move, treat the current battle round number as being one higher than
 * it actually is"). November 2026 update, 20.03: such a unit can make an ingress move in the first turn.
 * -> { name, owner } | null
 */
export function earlyArrival(army) {
  for (const cu of army?.units ?? []) for (const m of cu.members) for (const a of abilityRecords(m)) {
    if (/treat the (current )?battle round number as being one higher/i.test(a.text ?? '')) return { name: a.name, owner: m.dcUnit.name };
  }
  return null;
}

/**
 * What an army has that changes how you deploy and move against it (the matchup brief): only what the list
 * really has. -> [{ id, name, units: ['Scout Squad ×2', ...], note }]
 * Rules read in the core rules text: 24.09 Deep Strike, 24.20 Infiltrators, 24.32 Scout move, 24.24 Lone
 * Operative, 12.04 Fights First, 24.37 Torrent + 15.09 snap shooting, 10.07 indirect shooting.
 */
export function armyTricks(army) {
  const by = { deepStrike: [], infiltrators: [], scouts: [], lone: [], fightsFirst: [], torrent: [], indirect: [] };
  for (const cu of army.units) {
    const f = coreFlags(cu);
    const name = cu.name.replace(/ \(\d+\)$/, '');
    if (f.deepStrike) by.deepStrike.push(name);
    if (f.infiltrators) by.infiltrators.push(name);
    if (f.scouts) by.scouts.push(`${name} ${f.scouts}"`);
    if (f.loneOperative) by.lone.push(`${name} ${f.loneOperative}"`);
    // the ability itself, or a rule of the unit that gives it ("... has the Fights First ability")
    const ff = f.fightsFirst ? null : abilitiesOf(cu).find(x => /\bfights first\b/i.test(`${x.name} ${x.text}`));
    if (f.fightsFirst) by.fightsFirst.push(name); else if (ff) by.fightsFirst.push(`${name} (${ff.name})`);
    const guns = attackerRows(cu, 'shooting', null);
    const list = (rows) => [...new Set(rows.map(r => `${r.label} ${r.range}`))].join(', ');
    const tor = guns.filter(r => r.kw?.torrent), ind = guns.filter(r => r.kw?.indirect);
    if (tor.length) by.torrent.push(`${name} (${list(tor)})`);
    if (ind.length) by.indirect.push(`${name} (${list(ind)})`);
  }
  const tally = (l) => { const n = new Map(); for (const x of l) n.set(x, (n.get(x) ?? 0) + 1); return [...n].map(([k, c]) => (c > 1 ? `${k} ×${c}` : k)); };
  const rows = [
    ['deepStrike', 'Deep Strike', 'From battle round 2 they can arrive anywhere more than 8" from your units, inside your deployment zone too (24.09).'],
    ['infiltrators', 'Infiltrators', 'They deploy anywhere more than 8" from your deployment zone and your units (24.20): expect them on the middle objectives.'],
    ['scouts', 'Scouts', 'Before the first turn they move this far, and end more than 8" from your units (24.32).'],
    ['lone', 'Lone Operative', 'Not visible to your models from further away than this (24.24): you have to get that close to shoot it.'],
    ['fightsFirst', 'Fights First', 'Fights in the Fights First step without charging (12.04): in your turn it strikes after your first charging unit, before your others.'],
    ['torrent', 'Torrent in overwatch', 'Torrent attacks hit automatically (24.37), while other weapons hit only on a 6 in Fire Overwatch (15.09). Counted at full effect here: stay out of the range shown, or charge something else first.'],
    ['indirect', 'Indirect Fire', 'Can shoot units it cannot see (10.07): it then hits only on a 6, or on a 4+ if it stood still and another of their units sees the target; the target has cover.'],
  ];
  return rows.filter(([id]) => by[id].length).map(([id, name, note]) => ({ id, name, units: tally(by[id]), note }));
}

/**
 * What the board needs to draw / reason about a combat unit:
 * { members: [{ count, fp, label, leader }], move, ranges: [inches...], melee: bool }
 */
/**
 * Extra Move from a detachment rule for the units it names, e.g. Stormlance Task Force:
 * "Friendly Adeptus Astartes Mounted/Speeder units have +2" M."  -> { bonus, source } (bonus 0 = none)
 */
export function detachmentMoveBonus(cu, army) {
  let best = { bonus: 0, source: null };
  if (!army) return best;
  const own = new Set(cu.keywords.map(upperKw));
  for (const d of detachmentRules(army)) {
    const m = String(d.text ?? '').match(/^\s*friendly ([A-Za-z’' /-]+?) units have \+(\d+)" M\b/i);
    if (!m) continue;
    // "Adeptus Astartes Mounted/Speeder": Adeptus Astartes Mounted, or (Adeptus Astartes) Speeder
    const parts = m[1].split('/').map(s => s.trim().toUpperCase()).filter(Boolean);
    const lead = parts[0].split(/\s+/).slice(0, -1).join(' ');
    const phrases = [parts[0], ...parts.slice(1).flatMap(p => (lead ? [p, `${lead} ${p}`] : [p]))];
    if (phrases.some(ph => phraseInKeywords(ph, own)) && Number(m[2]) > best.bonus) best = { bonus: Number(m[2]), source: d.name };
  }
  return best;
}

export function boardUnit(cu, army = null) {
  const members = cu.members.map(m => {
    const kw = [...(m.dcUnit.keywords ?? []), ...(m.dcUnit.faction_keywords ?? [])];
    const base = BASE_SIZE_OVERRIDES[m.dcUnit.id] ?? m.dcUnit.base_size_mm;
    // oc: the Objective Control of ONE model (14.02 counts the models within range, not the unit)
    return { count: m.ru.model_count ?? 1, fp: footprint(base, kw), label: m.dcUnit.name, leader: m.role === 'leader', oc: parseInt(m.dcUnit.profiles?.[0]?.OC, 10) || 0 };
  });
  // Move bonuses add up (02.02.01): a detachment rule for the unit's keywords, an enhancement for its unit
  const det = detachmentMoveBonus(cu, army);
  const enh = cu.members.map(m => enhancementGrants(m.ru)).filter(g => g.move > 0);
  const mv = { bonus: det.bonus + enh.reduce((a, g) => a + g.move, 0), source: [det.source?.replace(/\s*\(.*$/, ''), ...enh.map(g => g.name)].filter(Boolean).join(' + ') || null };
  const move = Math.min(...cu.members.map(m => Number(m.dcUnit.profiles?.[0]?.M) || 6)) + mv.bonus;
  const ranged = attackerRows(cu, 'shooting', null);
  const ranges = [...new Set(ranged.map(r => parseFloat(r.range)).filter(n => n > 0))].sort((a, b) => a - b);
  const rfMelta = [...new Set(ranged.filter(r => r.kw.rapidFire || r.kw.melta).map(r => parseFloat(r.range)).filter(n => n > 0))];
  // the share of the unit's shooting that each range carries (a rough value against a T4, 3+ target): a unit
  // with one long gun does not shoot with everything from afar (nextturn.rangeShare)
  const dmg = new Map();
  for (const r of ranged) { const rg = parseFloat(r.range), v = (r.count ?? 0) * quickStat(r).v; if (rg > 0 && v > 0) dmg.set(rg, (dmg.get(rg) ?? 0) + v); }
  const sum = [...dmg.values()].reduce((x, y) => x + y, 0);
  const bands = sum > 0 ? [...dmg].sort((x, y) => x[0] - y[0]).map(([range, v]) => ({ range, share: v / sum })) : [];
  // Leadership: a battle-shock roll succeeds against "one or more of the unit's Ld characteristics" (01.07): the best one
  const lds = cu.members.flatMap(m => (m.dcUnit.profiles ?? []).map(q => parseInt(q.Ld, 10))).filter(n => n > 0);
  return { members, move, moveBonus: mv.bonus, moveBonusFrom: mv.source, ranges, bands, ld: lds.length ? Math.min(...lds) : null, halfRangeWeapons: rfMelta, melee: attackerRows(cu, 'fight', null).length > 0, flags: coreFlags(cu) };
}

// Roster state for the army builder.
//
// The working model IS the 40kdc `Roster` (the same shape the package's
// importers emit and checkRoster validates), so import, legality checking,
// share/export serializers, and the game-format converter all operate on the
// state directly. Loadouts live on each unit as unit-wide weapon counts
// (ru.wargear = [{ref, count}]), edited through the package's loadout maths
// (baseLoadout / weaponBounds / clampWeaponCount / validateLoadout).

import * as DC from '../vendor/40kdc-data.mjs';
import { GAME_NAME_CANON_ENTRIES } from '../lib/canon.mjs';
import { createConverter, ALLIED_FACTIONS, FACTION_DISPLAY_OVERRIDES } from '../lib/gameformat.mjs';

export const dc = DC; // the full engine, re-exported for views/dialogs
export const ds = DC.dataset;

export const conv = createConverter({
  rawData: DC.RAW_DATA,
  describeAbility: DC.describeAbility,
  canonEntries: GAME_NAME_CANON_ENTRIES,
});

// Factions with full in-game rule automation (FactionAbilityManager tables).
export const FULLY_SUPPORTED_FACTIONS = new Set([
  'orks', 'adeptus-custodes', 'adeptus-astartes', 'agents-of-the-imperium',
]);

export const ROLE_ORDER = [
  'epic-hero', 'character', 'battleline', 'infantry', 'mounted', 'beast',
  'swarm', 'monster', 'vehicle', 'dedicated-transport', 'fortification',
];

export function roleLabel(role) {
  const labels = {
    'epic-hero': 'Epic Heroes',
    'character': 'Characters',
    'battleline': 'Battleline',
    'infantry': 'Infantry',
    'mounted': 'Mounted',
    'beast': 'Beasts',
    'swarm': 'Swarms',
    'monster': 'Monsters',
    'vehicle': 'Vehicles',
    'dedicated-transport': 'Dedicated Transports',
    'fortification': 'Fortifications',
  };
  return labels[role] ?? 'Other';
}

// ---------------------------------------------------------------------------
// State

const DRAFT_KEY = 'w40k_builder_draft';

export const state = {
  roster: newRoster(),
  selectedUnit: -1,      // index into roster.units
  cloudName: null,       // army name this roster was loaded from / saved to
  importReport: null,    // {title, warnings: [...]} from the last import
  status: null,          // {kind: 'ok'|'err'|'info', text} transient toast
  listeners: new Set(),
};

export function newRoster() {
  return {
    name: 'New Army',
    source: { format: 'roster-json', generated_by: 'w40k-army-builder' },
    faction_id: null,
    detachments: [],
    battle_size: 'strike-force',
    force_disposition: null,
    points: { declared_limit: 2000, detachment_cap: 3, total_reported: null, total_computed: 0 },
    units: [],
    game_version: { edition: '11th', dataslate: 'launch' },
    diagnostics: {
      resolved_units: 0, unresolved_units: 0,
      resolved_weapons: 0, unresolved_weapons: 0, warnings: [],
    },
  };
}

export function subscribe(fn) {
  state.listeners.add(fn);
  return () => state.listeners.delete(fn);
}

let notifyScheduled = false;
export function notify() {
  saveDraft();
  if (notifyScheduled) return;
  notifyScheduled = true;
  queueMicrotask(() => {
    notifyScheduled = false;
    for (const fn of state.listeners) fn();
  });
}

export function setStatus(kind, text, ttlMs = 4000) {
  state.status = { kind, text };
  notify();
  if (ttlMs) {
    setTimeout(() => {
      if (state.status && state.status.text === text) {
        state.status = null;
        notify();
      }
    }, ttlMs);
  }
}

// ---------------------------------------------------------------------------
// Dataset lookups

export function factionList() {
  const seen = new Set();
  const out = [];
  for (const u of DC.RAW_DATA.units) {
    if (!seen.has(u.faction_id)) { seen.add(u.faction_id); }
  }
  for (const f of DC.RAW_DATA.factions) {
    if (!seen.has(f.id)) continue; // factions without units aren't buildable
    out.push({
      id: f.id,
      name: FACTION_DISPLAY_OVERRIDES[f.id] ?? f.name,
      logo_url: f.logo_url ?? null,
      supported: FULLY_SUPPORTED_FACTIONS.has(f.id),
    });
  }
  out.sort((a, b) => a.name.localeCompare(b.name));
  return out;
}

export function factionName(fid) {
  return FACTION_DISPLAY_OVERRIDES[fid] ??
    DC.RAW_DATA.factions.find(f => f.id === fid)?.name ?? fid ?? '';
}

export function detachmentList(fid) {
  return conv.detachmentsOf(fid)
    .slice()
    .sort((a, b) => a.name.localeCompare(b.name));
}

export function forceDispositions() {
  const fds = DC.RAW_DATA.forceDispositions ?? [];
  return fds.map(fd => ({ id: fd.id, name: fd.name ?? fd.id }));
}

/** Raw 40kdc unit + composition + wargear options for a roster unit. */
export function unitData(unitId, unitFactionId) {
  const found = conv.findUnitById(unitFactionId ?? state.roster.faction_id, unitId);
  if (!found) return null;
  const raw = found.unit;
  const comp = conv.compByUnit.get(`${found.factionId}::${raw.id}`) ?? null;
  const options = (DC.RAW_DATA.wargearOptions ?? []).filter(
    o => o.unit_id === raw.id && o.faction_id === found.factionId);
  return { raw, comp, options, factionId: found.factionId };
}

/** Buildable squad sizes for a unit: distinct model counts of its point tiers. */
export function sizeChoices(raw) {
  const sizes = [...new Set((raw.points ?? []).map(t => t.models))].sort((a, b) => a - b);
  if (sizes.length) return sizes;
  const min = raw.model_count?.min ?? 1;
  const max = raw.model_count?.max ?? min;
  return min === max ? [min] : [min, max];
}

/**
 * Battlefield-role classification. Only characters / epic heroes / battleline
 * / dedicated transports carry an explicit role in the dataset; everything
 * else is classified from its keywords.
 */
export function classifyUnit(raw) {
  if (raw.role) return raw.role;
  const kws = new Set((raw.keywords ?? []).map(k => k.toLowerCase()));
  for (const k of ['fortification', 'vehicle', 'monster', 'mounted', 'beast', 'swarm', 'infantry']) {
    if (kws.has(k)) return k;
  }
  return 'other';
}

/** Units addable for the current faction, grouped by role, plus allies. */
export function unitBrowserGroups(query = '') {
  const fid = state.roster.faction_id;
  if (!fid) return [];
  const q = DC.normalizeName ? DC.normalizeName(query) : query.toLowerCase();
  const groups = new Map();
  const push = (raw, alliedFrom = null) => {
    if (q && !(DC.normalizeName?.(raw.name) ?? raw.name.toLowerCase()).includes(q)) return;
    const key = alliedFrom ? `allied:${alliedFrom}` : classifyUnit(raw);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(raw);
  };
  for (const u of DC.RAW_DATA.units) {
    if (u.faction_id === fid) push(u);
  }
  for (const af of ALLIED_FACTIONS[fid] ?? []) {
    for (const u of DC.RAW_DATA.units) {
      if (u.faction_id === af) push(u, af);
    }
  }
  const ordered = [];
  for (const role of ROLE_ORDER) {
    if (groups.has(role)) ordered.push({ key: role, label: roleLabel(role), units: sortUnits(groups.get(role)) });
    groups.delete(role);
  }
  for (const [key, units] of groups) {
    const label = key.startsWith('allied:')
      ? `Allied — ${factionName(key.slice(7))}`
      : roleLabel(key);
    ordered.push({ key, label, units: sortUnits(units) });
  }
  return ordered;
}

function sortUnits(units) {
  return units.sort((a, b) => a.name.localeCompare(b.name));
}

// ---------------------------------------------------------------------------
// Loadout helpers (thin wrappers over the package's loadout maths)

export function countsOf(ru) {
  const counts = new Map();
  for (const wg of ru.wargear ?? []) {
    if (wg.ref?.id) counts.set(wg.ref.id, (counts.get(wg.ref.id) ?? 0) + wg.count);
  }
  return counts;
}

export function writeCounts(ru, counts, unitFactionId) {
  ru.wargear = [];
  for (const [wid, count] of counts) {
    if (count <= 0) continue;
    const w = conv.wres.resolve(unitFactionId, wid);
    ru.wargear.push({ ref: { id: wid, raw_name: w?.name ?? wid, resolved: true, candidates: [] }, count });
  }
}

export function loadoutBounds(ru) {
  const data = unitData(ru.ref.id, ru._unit_faction_id);
  if (!data) return new Map();
  return DC.weaponBounds(data.raw, ru.model_count, data.options, data.comp?.models);
}

export function loadoutViolations(ru) {
  const data = unitData(ru.ref.id, ru._unit_faction_id);
  if (!data) return [];
  return DC.validateLoadout(data.raw, ru.model_count, data.options, countsOf(ru), data.comp?.models);
}

/**
 * Weapon rows for the loadout editor: every id that may appear in this unit's
 * loadout (union of current counts and the bounds' ids), with its display
 * name, profile summary, current count, and legal range.
 */
export function loadoutRows(ru) {
  const data = unitData(ru.ref.id, ru._unit_faction_id);
  if (!data) return [];
  const counts = countsOf(ru);
  const bounds = DC.weaponBounds(data.raw, ru.model_count, data.options, data.comp?.models);
  const ids = new Set([...bounds.keys()]);
  for (const id of counts.keys()) ids.add(id);
  const rows = [];
  for (const id of ids) {
    const w = conv.wres.resolve(data.factionId, id);
    rows.push({
      id,
      name: w?.name ?? id,
      profiles: w?.profiles ?? [],
      count: counts.get(id) ?? 0,
      min: bounds.get(id)?.min ?? 0,
      max: bounds.get(id)?.max ?? ru.model_count,
    });
  }
  rows.sort((a, b) => a.name.localeCompare(b.name));
  return rows;
}

/**
 * The wargear option (if any) that introduces `weaponId` as a replacement,
 * used to auto-balance swaps when a stepper changes.
 */
function optionAdding(options, weaponId) {
  for (const o of options) {
    if ((o.replacement ?? []).includes(weaponId)) return { option: o, branch: o.replacement };
    for (const branch of o.replacement_choice ?? []) {
      if (branch.includes(weaponId)) return { option: o, branch };
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Roster mutations

export function loadRoster(roster, { cloudName = null, report = null } = {}) {
  state.roster = roster;
  state.selectedUnit = roster.units.length ? 0 : -1;
  state.cloudName = cloudName;
  state.importReport = report;
  repriceAll();
  notify();
}

export function resetRoster() {
  state.roster = newRoster();
  state.selectedUnit = -1;
  state.cloudName = null;
  state.importReport = null;
  notify();
}

export function setName(name) {
  state.roster.name = name;
  saveDraft();
}

export function setFaction(fid) {
  const r = state.roster;
  r.faction_id = fid;
  r.units = [];
  state.selectedUnit = -1;
  const dets = detachmentList(fid);
  r.detachments = dets.length
    ? [{ ref: { id: dets[0].id, raw_name: dets[0].name, resolved: true, candidates: [] }, dp_cost: dets[0].detachment_points ?? 1 }]
    : [];
  repriceAll();
  notify();
}

export function setDetachment(detId) {
  const r = state.roster;
  const det = conv.findDetachment(r.faction_id, detId);
  r.detachments = det
    ? [{ ref: { id: det.id, raw_name: det.name, resolved: true, candidates: [] }, dp_cost: det.detachment_points ?? 1 }]
    : [];
  // Enhancements belong to a detachment — drop ones the new detachment lacks.
  const valid = new Set(det?.enhancement_ids ?? []);
  let dropped = 0;
  for (const ru of r.units) {
    const eid = ru.enhancement?.id ?? ru.enhancement?.ref?.id;
    if (eid && !valid.has(eid)) { ru.enhancement = null; ru.enhancement_points = null; dropped++; }
  }
  if (dropped) setStatus('info', `${dropped} enhancement(s) removed — not in ${det?.name ?? 'the new detachment'}`);
  repriceAll();
  notify();
}

export function setPointsLimit(points) {
  const r = state.roster;
  r.points.declared_limit = points;
  r.battle_size = points <= 1000 ? 'incursion' : 'strike-force';
  r.points.detachment_cap = points <= 1000 ? 2 : 3;
  notify();
}

export function setForceDisposition(id) {
  state.roster.force_disposition = id || null;
  notify();
}

export function addUnit(unitId, unitFactionId = null) {
  const r = state.roster;
  const data = unitData(unitId, unitFactionId);
  if (!data) return;
  const sizes = sizeChoices(data.raw);
  const modelCount = sizes[0] ?? 1;
  const base = DC.baseLoadout(data.raw, modelCount, data.options, data.comp?.models);
  const ru = {
    ref: { id: data.raw.id, raw_name: data.raw.name, resolved: true, candidates: [] },
    model_count: modelCount,
    points: 0,
    is_warlord: false,
    enhancement: null,
    enhancement_points: null,
    wargear: [],
    leader_attachment: null,
  };
  if (data.factionId !== r.faction_id) ru._unit_faction_id = data.factionId;
  writeCounts(ru, base.counts, data.factionId);
  r.units.push(ru);
  state.selectedUnit = r.units.length - 1;
  repriceAll();
  notify();
}

export function removeUnit(i) {
  const r = state.roster;
  const removed = r.units[i];
  r.units.splice(i, 1);
  // Leaders attached to a removed bodyguard detach (refs point by unit id;
  // only clear when no other copy of that unit remains).
  if (removed) {
    const stillThere = new Set(r.units.map(u => u.ref.id));
    for (const u of r.units) {
      if (u.leader_attachment && !stillThere.has(u.leader_attachment.bodyguard_ref?.id)) {
        u.leader_attachment = null;
      }
    }
  }
  if (state.selectedUnit >= r.units.length) state.selectedUnit = r.units.length - 1;
  repriceAll();
  notify();
}

export function duplicateUnit(i) {
  const r = state.roster;
  const copy = JSON.parse(JSON.stringify(r.units[i]));
  copy.is_warlord = false;
  copy.leader_attachment = null;
  r.units.splice(i + 1, 0, copy);
  state.selectedUnit = i + 1;
  repriceAll();
  notify();
}

export function selectUnit(i) {
  state.selectedUnit = i;
  notify();
}

/**
 * Replace an unresolved (imported) unit with a real datasheet, keeping its
 * army-level choices (warlord flag, size where legal).
 */
export function resolveUnitTo(i, unitId) {
  const r = state.roster;
  const old = r.units[i];
  const data = unitData(unitId, null);
  if (!data) return;
  const sizes = sizeChoices(data.raw);
  const modelCount = sizes.includes(old.model_count) ? old.model_count : sizes[0];
  const ru = {
    ref: { id: data.raw.id, raw_name: data.raw.name, resolved: true, candidates: [] },
    model_count: modelCount,
    points: 0,
    is_warlord: !!old.is_warlord,
    enhancement: null,
    enhancement_points: null,
    wargear: [],
    leader_attachment: null,
  };
  if (data.factionId !== r.faction_id) ru._unit_faction_id = data.factionId;
  const base = DC.baseLoadout(data.raw, modelCount, data.options, data.comp?.models);
  writeCounts(ru, base.counts, data.factionId);
  r.units[i] = ru;
  repriceAll();
  notify();
}

export function setModelCount(i, modelCount) {
  const ru = state.roster.units[i];
  const data = unitData(ru.ref.id, ru._unit_faction_id);
  if (!data) return;
  // Preserve the player's swaps across the resize: diff current counts vs the
  // old base loadout, re-apply the delta onto the new base, clamp to bounds.
  const oldBase = DC.baseLoadout(data.raw, ru.model_count, data.options, data.comp?.models);
  const current = countsOf(ru);
  const delta = new Map();
  for (const [id, n] of current) delta.set(id, n - (oldBase.counts.get(id) ?? 0));
  for (const [id, n] of oldBase.counts) if (!current.has(id)) delta.set(id, -n);

  ru.model_count = modelCount;
  const newBase = DC.baseLoadout(data.raw, modelCount, data.options, data.comp?.models);
  const bounds = DC.weaponBounds(data.raw, modelCount, data.options, data.comp?.models);
  const next = new Map(newBase.counts);
  for (const [id, d] of delta) {
    if (!d) continue;
    const want = (next.get(id) ?? 0) + d;
    next.set(id, DC.clampWeaponCount(bounds, id, want));
  }
  writeCounts(ru, next, data.factionId);
  repriceAll();
  notify();
}

/**
 * Set `weaponId` to `requested` in `counts` (clamped to legal bounds) and
 * auto-balance the swap: taking a replacement weapon hands back the weapons it
 * replaces (and vice versa), and bundled choice-branch partners move in step.
 * Mutates `counts`; returns the applied delta.
 */
export function applyWeaponDelta(data, modelCount, counts, weaponId, requested) {
  const bounds = DC.weaponBounds(data.raw, modelCount, data.options, data.comp?.models);
  const before = counts.get(weaponId) ?? 0;
  const after = DC.clampWeaponCount(bounds, weaponId, requested);
  if (after === before) return 0;
  counts.set(weaponId, after);
  const swap = optionAdding(data.options, weaponId);
  if (swap) {
    const steps = after - before;
    for (const rid of swap.option.replaces ?? []) {
      const cur = counts.get(rid) ?? 0;
      counts.set(rid, DC.clampWeaponCount(bounds, rid, cur - steps));
    }
    // A choice branch may bundle several ids (e.g. "slugga AND choppa") — keep
    // the bundled partners in step with the edited weapon.
    for (const bid of swap.branch ?? []) {
      if (bid === weaponId) continue;
      const cur = counts.get(bid) ?? 0;
      counts.set(bid, DC.clampWeaponCount(bounds, bid, cur + steps));
    }
  }
  return after - before;
}

/** Clamp every weapon count into its legal range for the unit's size. */
export function clampLoadoutToBounds(data, modelCount, counts) {
  const bounds = DC.weaponBounds(data.raw, modelCount, data.options, data.comp?.models);
  for (const [id] of bounds) {
    const cur = counts.get(id) ?? 0;
    const clamped = DC.clampWeaponCount(bounds, id, cur);
    if (clamped !== cur) counts.set(id, clamped);
  }
  return counts;
}

export function setWeaponCount(i, weaponId, requested) {
  const ru = state.roster.units[i];
  const data = unitData(ru.ref.id, ru._unit_faction_id);
  if (!data) return;
  const counts = countsOf(ru);
  applyWeaponDelta(data, ru.model_count, counts, weaponId, requested);
  writeCounts(ru, counts, data.factionId);
  notify();
}

export function resetLoadout(i) {
  const ru = state.roster.units[i];
  const data = unitData(ru.ref.id, ru._unit_faction_id);
  if (!data) return;
  const base = DC.baseLoadout(data.raw, ru.model_count, data.options, data.comp?.models);
  writeCounts(ru, base.counts, data.factionId);
  notify();
}

export function setEnhancement(i, enhId) {
  const ru = state.roster.units[i];
  if (!enhId) {
    ru.enhancement = null;
    ru.enhancement_points = null;
  } else {
    const e = (DC.RAW_DATA.enhancements ?? []).find(x => x.id === enhId);
    if (!e) return;
    ru.enhancement = { id: e.id, raw_name: e.name, resolved: true, candidates: [] };
    ru.enhancement_points = e.cost ?? 0;
  }
  repriceAll();
  notify();
}

export function setWarlord(i) {
  const r = state.roster;
  r.units.forEach((u, idx) => { u.is_warlord = idx === i; });
  notify();
}

export function setLeaderAttachment(i, bodyguardUnitId) {
  const ru = state.roster.units[i];
  if (!bodyguardUnitId) {
    ru.leader_attachment = null;
  } else {
    const target = state.roster.units.find(u => u.ref.id === bodyguardUnitId);
    ru.leader_attachment = {
      bodyguard_ref: {
        id: bodyguardUnitId,
        raw_name: target?.ref.raw_name ?? bodyguardUnitId,
        resolved: !!target,
        candidates: [],
      },
      role: 'leader',
      provisional: false,
    };
  }
  notify();
}

/** Eligible bodyguard squads (in this roster) for a leader roster-unit. */
export function eligibleBodyguards(ru) {
  const la = (DC.RAW_DATA.leaderAttachments ?? []).find(x => x.leader_id === ru.ref.id);
  if (!la) return [];
  const eligible = new Set(la.eligible_bodyguard_ids);
  const seen = new Set();
  const out = [];
  for (const u of state.roster.units) {
    if (u.ref.id && eligible.has(u.ref.id) && !seen.has(u.ref.id)) {
      seen.add(u.ref.id);
      out.push({ id: u.ref.id, name: u.ref.raw_name });
    }
  }
  return out;
}

/** Detachment enhancements + who holds each (one per enhancement army-wide). */
export function enhancementChoices() {
  const det = state.roster.detachments[0];
  const d = det?.ref?.id ? conv.findDetachment(state.roster.faction_id, det.ref.id) : null;
  if (!d) return [];
  const taken = new Map();
  state.roster.units.forEach((u, idx) => {
    const eid = u.enhancement?.id ?? u.enhancement?.ref?.id;
    if (eid) taken.set(eid, idx);
  });
  return (d.enhancement_ids ?? [])
    .map(eid => (DC.RAW_DATA.enhancements ?? []).find(x => x.id === eid))
    .filter(Boolean)
    .map(e => ({
      id: e.id,
      name: e.name,
      cost: e.cost ?? 0,
      upgrade: !!e.upgrade_tag,
      keyword_restrictions: e.keyword_restrictions ?? [],
      takenBy: taken.has(e.id) ? taken.get(e.id) : null,
    }));
}

// ---------------------------------------------------------------------------
// Pricing + legality

export function repriceAll() {
  const r = state.roster;
  const ordinals = new Map();
  let total = 0;
  for (const ru of r.units) {
    if (ru.ref?.id) {
      const ordinal = (ordinals.get(ru.ref.id) ?? 0) + 1;
      ordinals.set(ru.ref.id, ordinal);
      const data = unitData(ru.ref.id, ru._unit_faction_id);
      if (data) {
        ru.points = DC.baseUnitPoints(data.raw, ru.model_count, ordinal);
        ru._tier_missing = DC.pointsTierMissing(data.raw, ru.model_count, ordinal);
      }
    }
    total += (ru.points ?? 0) + (ru.enhancement_points ?? 0);
  }
  r.points.total_computed = total;
  r.diagnostics.resolved_units = r.units.filter(u => u.ref?.resolved).length;
  r.diagnostics.unresolved_units = r.units.length - r.diagnostics.resolved_units;
}

export function legality() {
  try {
    return DC.checkRoster(state.roster, ds);
  } catch (e) {
    return { units: [], army: [{ code: 'checker-error', id: 'roster', message: String(e), unitIndex: null, severity: 'warn' }] };
  }
}

export function totalPoints() {
  return state.roster.points.total_computed;
}

// ---------------------------------------------------------------------------
// Draft persistence

function saveDraft() {
  try {
    localStorage.setItem(DRAFT_KEY, JSON.stringify({
      roster: state.roster,
      cloudName: state.cloudName,
      savedAt: Date.now(),
    }));
  } catch (e) { /* storage full/blocked — drafts are best-effort */ }
}

export function loadDraft() {
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    if (!raw) return false;
    const draft = JSON.parse(raw);
    if (!draft?.roster) return false;
    state.roster = draft.roster;
    state.cloudName = draft.cloudName ?? null;
    state.selectedUnit = state.roster.units.length ? 0 : -1;
    repriceAll();
    return true;
  } catch (e) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Game JSON in/out

export function toGameJson() {
  const d = new Date();
  const createdDate = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  return conv.rosterToGame(state.roster, { createdDate });
}

export function fromGameJson(json, { name = '', cloudName = null } = {}) {
  const { roster, warnings } = conv.gameToRoster(json, { name });
  loadRoster(roster, {
    cloudName,
    report: warnings.length ? { title: 'Imported from game JSON', warnings } : null,
  });
  return { roster, warnings };
}

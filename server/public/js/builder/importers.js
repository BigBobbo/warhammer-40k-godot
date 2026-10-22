// List import: pasted text (GW app, New Recruit, ListForge, rosterizer …) or
// game JSON, normalized into an editable Roster.
//
// Primary path is the package's own multi-format importer (tryImportRoster).
// When it can't make sense of the text, the legacy parser (js/parser.js — the
// loose "faction on line 1" format the old uploader page accepted) runs as a
// fallback and its output is resolved against the dataset here.
//
// Both paths end in normalizeImportedRoster(), which snaps squad sizes to real
// point tiers (GW text carries no model counts) and normalizes weapon counts
// into legal bounds, starting fresh units from their default loadout.

import {
  dc, ds, conv, unitData, sizeChoices, countsOf, writeCounts,
  applyWeaponDelta, clampLoadoutToBounds,
} from './store.js';
import { looseName, normName } from '../lib/dckit.mjs';

/**
 * Import pasted list text. Returns { roster, report } or throws with a
 * readable message.
 */
export function importText(text, { factionOverride = null } = {}) {
  const notes = [];
  let roster = null;
  let source = null;
  // GW app exports (v2.8+) mark attached units with "• Attached as: Leader
  // (Character)" lines, which the package reads as wargear (and, inside a
  // squad, as an extra model). Take them out and re-apply them below.
  const gw = extractGwAttachments(text);
  text = gw.text;

  const res = dc.tryImportRoster(text, { dataset: ds }); // the patched dataset (store.js), not the pre-patch default
  if (res.ok && res.roster) {
    const r = res.roster;
    const resolvedUnits = r.diagnostics?.resolved_units ?? 0;
    const totalUnits = (r.units ?? []).length;
    const usable = r.faction_id && totalUnits > 0 && resolvedUnits >= Math.ceil(totalUnits / 2);
    if (usable) {
      roster = r;
      source = `package importer (${r.source?.format ?? '?'})`;
      resolveRosterEnhancements(roster, notes);
      for (const w of r.diagnostics?.warnings ?? []) {
        notes.push(w.raw_name ? `${w.code}: ${w.raw_name}` : `${w.code}: ${w.message}`);
      }
    } else {
      notes.push(`package importer matched ${resolvedUnits}/${totalUnits} units` +
        (r.faction_id ? '' : ' and no faction') + ' — trying the legacy parser');
    }
  } else if (res.reason) {
    notes.push(`package importer: ${res.reason}`);
  }

  if (!roster) {
    roster = legacyParse(text, factionOverride, notes);
  }
  if (!roster) {
    throw new Error('Could not parse the list. Supported: GW app, New Recruit (text/JSON), ListForge, rosterizer, or the plain "Faction (points)" format.');
  }

  if (factionOverride && !roster.faction_id) {
    roster.faction_id = factionOverride;
    notes.push(`faction set manually: ${factionOverride}`);
  }

  resolveRosterEnhancements(roster, notes);
  applyGwAttachments(roster, gw.groups, notes);
  normalizeImportedRoster(roster, notes);
  return { roster, report: { title: `Imported via ${source ?? 'legacy parser'}`, warnings: notes } };
}

// ---------------------------------------------------------------------------
// GW app "Attached Units" blocks.
//
//   Attached Unit 1
//
//   Logan Grimnar (150 points)
//   •  Attached as: Leader (Character)
//     • Warlord
//     ...
//   Terminator Assault Squad (395 points)
//   •  Attached as: Bodyguard

const UNIT_HEADER_RE = /^(\S.*?)\s*\((\d+)\s*(?:points?|pts?)\)\s*$/i;
const ATTACHED_AS_RE = /^\s*[•·*-]?\s*Attached as:\s*(.+?)\s*$/i;
const ATTACHED_GROUP_RE = /^\s*Attached Unit\s+\d+\s*$/i;

/** Strip "Attached as:" lines; return the cleaned text and the attached
 * groups: [[{name, nth, role: 'leader'|'support'|'bodyguard'}]], where nth is
 * the 0-based occurrence of that unit name among the list's unit headers. */
export function extractGwAttachments(text) {
  // The GW app pads its bullets with invisible WORD JOINERs (U+2060) and
  // no-break spaces.
  const lines = String(text).replace(/[\u2060\u200B\uFEFF]/g, '').replace(/\u00A0/g, ' ').split(/\r?\n/);
  const out = [];
  const groups = [];
  const seen = new Map();
  let group = null;
  let last = null;
  for (const line of lines) {
    if (ATTACHED_GROUP_RE.test(line)) {
      group = [];
      groups.push(group);
      out.push(line);
      continue;
    }
    const hm = line.match(UNIT_HEADER_RE);
    if (hm) {
      const k = looseName(hm[1]);
      const nth = seen.get(k) ?? 0;
      seen.set(k, nth + 1);
      last = { name: hm[1].trim(), nth };
      out.push(line);
      continue;
    }
    const am = line.match(ATTACHED_AS_RE);
    if (am) {
      if (group && last) {
        const role = /bodyguard/i.test(am[1]) ? 'bodyguard' : (/support/i.test(am[1]) ? 'support' : 'leader');
        group.push({ ...last, role });
      }
      continue;
    }
    // A role-group heading ("BATTLELINE", "OTHER DATASHEETS") ends the
    // attached-units section.
    if (/^[A-Z][A-Z &/-]+$/.test(line.trim())) group = null;
    out.push(line);
  }
  return { text: out.join('\n'), groups: groups.filter(g => g.length) };
}

/** Point each group's Leader / Support characters at its Bodyguard unit. */
function applyGwAttachments(roster, groups, notes) {
  if (!groups.length) return;
  const units = roster.units ?? [];
  const pick = (entry) => {
    const k = looseName(entry.name);
    return units.filter(u => looseName(u.ref?.raw_name ?? '') === k)[entry.nth] ?? null;
  };
  for (const g of groups) {
    const bg = g.find(e => e.role === 'bodyguard');
    const bgUnit = bg ? pick(bg) : null;
    if (!bgUnit?.ref?.id) {
      notes.push(`attached unit (${g.map(e => e.name).join(' + ')}): bodyguard not found — attach it by hand`);
      continue;
    }
    for (const e of g) {
      if (e.role === 'bodyguard') continue;
      const ru = pick(e);
      if (!ru) continue;
      ru.leader_attachment = {
        bodyguard_ref: { id: bgUnit.ref.id, raw_name: bgUnit.ref.raw_name, resolved: true, candidates: [] },
        role: e.role,
        provisional: false,
      };
    }
  }
}

/**
 * Re-resolve each enhancement against the roster's own detachments. The
 * package matches enhancement names faction-wide, so "Imperium's Sword" could
 * land on another detachment's record of the same name, and the GW app's
 * "Furious Assault (Upgrade)" suffix matched nothing.
 */
function resolveRosterEnhancements(roster, notes) {
  if (!roster.faction_id) return;
  const dets = (roster.detachments ?? [])
    .map(d => conv.findDetachment(roster.faction_id, d.ref?.id ?? d.ref?.raw_name ?? ''))
    .filter(Boolean);
  if (!dets.length) return;
  const ownIds = new Set(dets.flatMap(d => d.enhancement_ids ?? []));
  for (const ru of roster.units ?? []) {
    const enh = ru.enhancement;
    if (!enh || (enh.id && ownIds.has(enh.id))) continue;
    const name = String(enh.raw_name ?? '').replace(/\s*\((?:upgrade|aura|one per army)\)\s*$/i, '').trim();
    let hit = null;
    for (const d of dets) {
      const byName = conv.detachmentEnhancements(d);
      hit = byName.get(normName(name)) ?? [...byName.values()].find(e => looseName(e.name) === looseName(name)) ?? null;
      if (hit) break;
    }
    if (hit) {
      ru.enhancement = { id: hit.id, raw_name: hit.name, resolved: true, candidates: [] };
    } else {
      notes.push(`enhancement "${name}" is not from a detachment in this list`);
    }
  }
  // the package's own "enhancement-unresolved" notes for names resolved here
  roster.diagnostics.warnings = (roster.diagnostics?.warnings ?? []).filter(w =>
    w.code !== 'enhancement-unresolved' || !(roster.units ?? []).some(u => u.enhancement?.resolved &&
      looseName(String(w.raw_name ?? '').replace(/\s*\([^)]*\)\s*$/, '')) === looseName(u.enhancement.raw_name)));
}

// ---------------------------------------------------------------------------
// Legacy fallback (window.ArmyParser from js/parser.js, a non-module IIFE).

function legacyParse(text, factionOverride, notes) {
  const parser = globalThis.ArmyParser;
  if (!parser?.parse) return null;
  let parsed;
  try {
    parsed = parser.parse(text);
  } catch (e) {
    notes.push(`legacy parser: ${e.message}`);
    return null;
  }
  if (!parsed || !(parsed.units ?? []).length) return null;
  notes.push('parsed with the legacy text parser');

  const factionId = factionOverride ?? conv.factionIdForName(parsed.faction ?? '');
  if (!factionId) {
    notes.push(`faction "${parsed.faction ?? ''}" not recognized — pick one and re-import`);
  }

  const units = [];
  for (const pu of parsed.units ?? []) {
    const found = factionId ? conv.findUnitByName(factionId, pu.name, notes, pu.name) : null;
    if (!found) {
      units.push({
        ref: { id: null, raw_name: pu.name, resolved: false, candidates: candidatesFor(factionId, pu.name) },
        model_count: pu.modelCount ?? 1,
        points: pu.points ?? null,
        is_warlord: !!pu.isWarlord,
        enhancement: pu.enhancement
          ? { id: null, raw_name: pu.enhancement, resolved: false, candidates: [] }
          : null,
        enhancement_points: null,
        wargear: (pu.wargear ?? []).map(w => ({
          ref: { id: null, raw_name: String(w), resolved: false, candidates: [] }, count: 1,
        })),
        leader_attachment: null,
      });
      continue;
    }
    const ru = {
      ref: { id: found.unit.id, raw_name: pu.name, resolved: true, candidates: [] },
      model_count: pu.modelCount ?? 1,
      points: pu.points ?? null,
      is_warlord: !!pu.isWarlord,
      enhancement: resolveEnhancementByName(factionId, parsed.detachment, pu.enhancement, notes),
      enhancement_points: null,
      wargear: [],
      leader_attachment: null,
      _wargear_hints: (pu.wargear ?? []).map(String),
    };
    if (found.factionId !== factionId) ru._unit_faction_id = found.factionId;
    units.push(ru);
  }

  const det = factionId ? conv.findDetachment(factionId, parsed.detachment ?? '') : null;
  const declared = parsed.points ?? null;
  return {
    name: (parsed.faction ? `${parsed.faction} ${declared ?? ''}` : 'Imported list').trim(),
    source: { format: 'gw', generated_by: 'legacy-parser' },
    faction_id: factionId,
    detachments: det
      ? [{ ref: { id: det.id, raw_name: det.name, resolved: true, candidates: [] }, dp_cost: det.detachment_points ?? 1 }]
      : (parsed.detachment
        ? [{ ref: { id: null, raw_name: parsed.detachment, resolved: false, candidates: [] }, dp_cost: null }]
        : []),
    battle_size: declared == null ? null : (declared <= 1000 ? 'incursion' : 'strike-force'),
    force_disposition: null,
    points: {
      declared_limit: declared,
      detachment_cap: declared == null ? null : (declared <= 1000 ? 2 : 3),
      total_reported: declared,
      total_computed: 0,
    },
    units,
    game_version: { edition: '11th', dataslate: 'launch' },
    diagnostics: {
      resolved_units: units.filter(u => u.ref.resolved).length,
      unresolved_units: units.filter(u => !u.ref.resolved).length,
      resolved_weapons: 0,
      unresolved_weapons: 0,
      warnings: [],
    },
  };
}

function resolveEnhancementByName(factionId, detachmentName, name, notes) {
  if (!name) return null;
  const det = factionId ? conv.findDetachment(factionId, detachmentName ?? '') : null;
  const stripped = String(name).replace(/\s*\(\+?\d+\s*pts?\)\s*$/i, '');
  const e = det
    ? [...conv.detachmentEnhancements(det).values()].find(x => looseName(x.name) === looseName(stripped))
    : null;
  if (e) return { id: e.id, raw_name: e.name, resolved: true, candidates: [] };
  notes.push(`enhancement "${stripped}" not found${det ? ` in ${det.name}` : ''}`);
  return { id: null, raw_name: stripped, resolved: false, candidates: [] };
}

/** Up to 5 fuzzy datasheet suggestions for an unmatched unit name. */
export function candidatesFor(factionId, name) {
  if (!factionId) return [];
  const target = looseName(name);
  const words = new Set(target.split(' ').filter(Boolean));
  const scored = [];
  for (const u of dc.RAW_DATA.units) {
    if (u.faction_id !== factionId) continue;
    const un = looseName(u.name);
    if (un === target) return [{ id: u.id, name: u.name }];
    let score = 0;
    for (const w of un.split(' ')) if (words.has(w)) score++;
    if (un.includes(target) || target.includes(un)) score += 2;
    if (score > 0) scored.push({ score, id: u.id, name: u.name });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, 5).map(({ id, name: n }) => ({ id, name: n }));
}

// ---------------------------------------------------------------------------
// Post-import normalization (shared by every import path).

export function normalizeImportedRoster(roster, notes = []) {
  if (!roster.faction_id) return roster;

  for (const ru of roster.units ?? []) {
    if (!ru.ref?.id) continue;
    let data = unitData(ru.ref.id, ru._unit_faction_id);
    if (!data) continue;

    // --- a pre-codex datasheet the codex renamed (Custodian Guard ->
    // Custodian Guard Sodality): move the import to the codex datasheet, as
    // generate-armies.mjs does through UNIT_ALIASES (decision D1). The source
    // loadout does not carry over (the kit changed) — it restarts from the
    // codex default below.
    const next = data.raw.superseded_by ? unitData(data.raw.superseded_by, data.factionId) : null;
    if (next) {
      notes.push(`${ru.ref.raw_name}: pre-codex datasheet — imported as ${next.raw.name} (${data.raw.superseded_by_codex})`);
      ru.ref = { id: next.raw.id, raw_name: next.raw.name, resolved: true, candidates: [] };
      ru.wargear = [];
      delete ru._wargear_hints;
      data = next;
    } else if (data.raw.superseded_by_codex) {
      notes.push(`${ru.ref.raw_name}: pre-codex datasheet, not in ${data.raw.superseded_by_codex} — kept as imported`);
    }

    // --- squad size: sources without explicit model counts (GW text) arrive
    // at 1; snap to the tier whose cost matches the reported points, else the
    // smallest legal size.
    const sizes = sizeChoices(data.raw);
    if (!sizes.includes(ru.model_count)) {
      let snapped = null;
      if (ru.points != null) {
        for (const s of sizes) {
          if (dc.baseUnitPoints(data.raw, s, 1) === ru.points) { snapped = s; break; }
        }
      }
      const finalSize = snapped ?? sizes.reduce(
        (best, s) => (Math.abs(s - ru.model_count) < Math.abs(best - ru.model_count) ? s : best),
        sizes[0]);
      if (finalSize !== ru.model_count) {
        notes.push(`${ru.ref.raw_name}: squad size ${ru.model_count} → ${finalSize}` +
          (snapped ? ` (matches ${ru.points} pts)` : ' (nearest legal size)'));
        ru.model_count = finalSize;
      }
    }

    // --- loadout: start every unit from its default loadout, then apply the
    // source's optional-weapon picks as swaps, then clamp into legal bounds.
    remapForeignWeapons(data, ru, notes);
    const sourceCounts = countsOf(ru);
    const hints = ru._wargear_hints ?? [];
    delete ru._wargear_hints;
    const base = dc.baseLoadout(data.raw, ru.model_count, data.options, data.comp?.models);
    const counts = new Map(base.counts);

    if (sourceCounts.size) {
      for (const [wid, n] of sourceCounts) {
        const baseN = counts.get(wid) ?? 0;
        if (n > baseN) applyWeaponDelta(data, ru.model_count, counts, wid, n);
      }
    }
    for (const hint of hints) {
      const wid = weaponIdForName(data, hint);
      if (!wid) continue;
      if ((counts.get(wid) ?? 0) === 0) {
        applyWeaponDelta(data, ru.model_count, counts, wid, 1);
      }
    }
    clampLoadoutToBounds(data, ru.model_count, counts);
    writeCounts(ru, counts, data.factionId);
  }
  return roster;
}

/**
 * Move source weapons the datasheet does not list onto the datasheet's own
 * weapon of that name: the package resolves the GW app's "Chainsword" to the
 * generic `chainsword`, while the Outrider Squad / Grey Hunters carry
 * "Astartes chainsword" — the import then showed both.
 */
function remapForeignWeapons(data, ru, notes) {
  const own = new Set([...(data.raw.weapon_ids ?? []),
    ...conv.wargearItems(data.raw, data.factionId).keys(),
    ...DC_bounds(data, ru.model_count).keys()]);
  // Some per-datasheet ids have no weapon record ("thunder-hammer-captain-on-
  // bike"): name those from the id, minus the datasheet suffix.
  const nameOf = id => conv.wres.resolve(data.factionId, id)?.name ??
    id.replace(new RegExp(`-${data.raw.id}$`), '').replace(/-/g, ' ');
  const ownNamed = [...own].map(id => ({ id, n: looseName(nameOf(id)) }));
  const out = [];
  for (const wg of ru.wargear ?? []) {
    const id = wg.ref?.id;
    if (!id || own.has(id)) { out.push(wg); continue; }
    const n = looseName(wg.ref.raw_name ?? conv.wres.resolve(data.factionId, id)?.name ?? id);
    const hit = ownNamed.find(o => o.n === n) ?? ownNamed.find(o => o.n.endsWith(` ${n}`));
    if (hit) {
      out.push({ ...wg, ref: { ...wg.ref, id: hit.id, resolved: true } });
    } else {
      // The bundle's kit predates the codex (Ancient in Terminator Armour's
      // Master-crafted Power Weapon): keep the listed weapon.
      out.push(wg);
      notes.push(`${ru.ref.raw_name}: "${wg.ref.raw_name ?? id}" is not on the datasheet's kit — kept as listed`);
    }
  }
  ru.wargear = out;
}

function DC_bounds(data, modelCount) {
  return dc.weaponBounds(data.raw, modelCount, data.options, data.comp?.models);
}

function weaponIdForName(data, rawName) {
  const base = looseName(String(rawName).split(/\s+[–-]\s+/)[0].replace(/^\d+\s*x\s*/i, ''));
  for (const wid of data.raw.weapon_ids ?? []) {
    const w = conv.wres.resolve(data.factionId, wid);
    if (w && looseName(w.name) === base) return wid;
  }
  return null;
}

// ---------------------------------------------------------------------------
/** Import an already-parsed game army object (cloud load / .json upload). */
export function importGameObject(parsed, { name = '' } = {}) {
  const { roster, warnings } = conv.gameToRoster(parsed, { name });
  normalizeImportedRoster(roster, warnings);
  return { roster, report: { title: 'Imported game army JSON', warnings } };
}

/** Import a .json file: a game army (schema 1/2) or a 40kdc roster JSON. */
export function importJsonText(jsonText, { name = '' } = {}) {
  let parsed;
  try {
    parsed = JSON.parse(jsonText);
  } catch (e) {
    throw new Error('Not valid JSON: ' + e.message);
  }
  // Game army files have a faction block + units dict.
  if (parsed?.faction && parsed?.units && !Array.isArray(parsed.units)) {
    return importGameObject(parsed, { name });
  }
  // Otherwise let the package try (New Recruit JSON, roster JSON, ListForge).
  return importText(jsonText);
}

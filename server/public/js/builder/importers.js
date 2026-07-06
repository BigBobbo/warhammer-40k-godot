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
  dc, conv, unitData, sizeChoices, countsOf, writeCounts,
  applyWeaponDelta, clampLoadoutToBounds,
} from './store.js';
import { looseName } from '../lib/dckit.mjs';

/**
 * Import pasted list text. Returns { roster, report } or throws with a
 * readable message.
 */
export function importText(text, { factionOverride = null } = {}) {
  const notes = [];
  let roster = null;
  let source = null;

  // Modern GW app exports (v2.x, 11e) put the faction on line 1, join
  // multiple detachments in one "(N Detachment Points)" header, list Force
  // Dispositions, and wrap leader/bodyguard pairs in ATTACHED UNITS blocks —
  // none of which the generic text adapter understands. Normalize first.
  if (looksLikeGwAppV2(text)) {
    roster = importGwAppV2(text, notes);
    if (roster) source = 'GW app export (11e)';
  }

  if (!roster) {
    const res = dc.tryImportRoster(text);
    if (res.ok && res.roster) {
      const r = res.roster;
      // The adapter can resolve every unit yet miss the faction when the
      // header shape is unusual — recover it from the units themselves.
      if (!r.faction_id) {
        const inferred = inferFactionFromUnits(r);
        if (inferred) {
          r.faction_id = inferred;
          notes.push(`faction inferred from the resolved units: ${inferred}`);
        }
      }
      const resolvedUnits = (r.units ?? []).filter(u => u.ref?.resolved).length;
      const totalUnits = (r.units ?? []).length;
      const usable = r.faction_id && totalUnits > 0 && resolvedUnits >= Math.ceil(totalUnits / 2);
      if (usable) {
        roster = r;
        source = `package importer (${r.source?.format ?? '?'})`;
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
  }

  if (!roster) {
    roster = legacyParse(text, factionOverride, notes);
  }
  if (!roster) {
    throw new Error('Could not parse the list. Supported: GW app exports, New Recruit (text/JSON), ListForge, rosterizer, or the plain "Faction (points)" format.');
  }

  if (factionOverride && !roster.faction_id) {
    roster.faction_id = factionOverride;
    notes.push(`faction set manually: ${factionOverride}`);
  }

  normalizeImportedRoster(roster, notes);
  return { roster, report: { title: `Imported via ${source ?? 'legacy parser'}`, warnings: notes } };
}

// ---------------------------------------------------------------------------
// Modern GW app export (v2.x / 11th edition).
//
// Shape (see server/tests/fixtures/gw_app_v2_death_guard.txt):
//   Death Guard
//   Contagion Engines and Death Lord's Chosen (3 Detachment Points)
//   Force Dispositions: Priority Assets, Purge the Foe
//   Strike Force (2,000 Points)
//
//   ATTACHED UNITS
//   Attached unit 1
//   <leader>  (• Attached as: Leader (Character))
//   <bodyguard> (• Attached as: Bodyguard ())
//   ...
//   Exported with App Version: ...
//
// Strategy: capture the 11e-only information (multi-detachments + DP,
// dispositions, attachments, warlord bullets), rewrite the text into the
// classic header shape the package's `gw` adapter parses, import, then graft
// the captured information back onto the roster.

const GW2_BATTLE_RE = /^(Incursion|Strike Force|Onslaught)\s*\((\d[\d,]*)\s*Points?\)$/i;
const GW2_DETACH_RE = /^(.*?)\s*\((\d+)\s*Detachment Points?\)$/i;
const GW2_UNIT_RE = /^(.+?)\s*\((\d[\d,]*)\s*Points?\)$/;
const GW2_SECTION_RE = /^[A-Z][A-Z0-9 &'’-]+$/;

export function looksLikeGwAppV2(text) {
  return /Exported with App Version/i.test(text) ||
    /\(\d+\s*Detachment Points?\)/i.test(text) ||
    /^\s*Force Dispositions?\s*:/im.test(text) ||
    /^\s*[•◦]\s*Attached as\s*:/im.test(text);
}

function importGwAppV2(rawText, notes) {
  const lines = String(rawText).replace(/﻿/g, '').replace(/ /g, ' ')
    .replace(/\r\n?/g, '\n').split('\n');

  let factionRaw = null;
  let detachmentRaw = null;
  let battleLine = null;
  let dispositionsRaw = [];
  let inHeader = true;
  const bodyLines = [];
  const attachments = [];    // { leader, bodyguard } by unit display name
  const warlords = [];       // unit display names flagged by a Warlord bullet
  let currentAttach = null;
  let currentUnit = null;

  const stripThousands = (s) => s.replace(/(\d),(\d)/g, '$1$2');

  for (const line of lines) {
    const t = line.trim();
    if (!t) { if (!inHeader) bodyLines.push(''); continue; }
    if (/^Exported with App Version/i.test(t)) continue;

    if (inHeader) {
      if (GW2_BATTLE_RE.test(t)) { battleLine = stripThousands(t); continue; }
      const dm = t.match(GW2_DETACH_RE);
      if (dm) { detachmentRaw = dm[1].trim(); continue; }
      if (/^Force Dispositions?\s*:/i.test(t)) {
        dispositionsRaw = t.split(':').slice(1).join(':').split(',').map(s => s.trim()).filter(Boolean);
        continue;
      }
      const isSection = GW2_SECTION_RE.test(t);
      const isUnit = !/^[•◦]/.test(t) && GW2_UNIT_RE.test(t);
      if (!isSection && !isUnit) {
        if (!factionRaw) factionRaw = t;
        // any further free line in the header (list name variants) is ignored
        continue;
      }
      inHeader = false; // fall through into body handling for this line
    }

    if (/^Attached unit \d+/i.test(t)) {
      currentAttach = { leader: null, bodyguard: null };
      attachments.push(currentAttach);
      continue;
    }
    if (GW2_SECTION_RE.test(t)) {
      if (!/^ATTACHED UNITS$/i.test(t)) currentAttach = null;
      bodyLines.push(t);
      continue;
    }
    if (!/^[•◦]/.test(t)) {
      const uh = t.match(GW2_UNIT_RE);
      if (uh) {
        currentUnit = uh[1].trim();
        bodyLines.push(stripThousands(t));
        continue;
      }
    }
    const attachAs = t.match(/^[•◦]\s*Attached as\s*:\s*(Leader|Bodyguard)/i);
    if (attachAs) {
      if (currentAttach && currentUnit) {
        if (/^leader$/i.test(attachAs[1])) currentAttach.leader = currentUnit;
        else currentAttach.bodyguard = currentUnit;
      }
      continue; // the adapter would misread this bullet as wargear
    }
    if (/^[•◦]\s*Warlord$/i.test(t)) {
      if (currentUnit) warlords.push(currentUnit);
      continue;
    }
    bodyLines.push(stripThousands(
      line.replace(/^(\s*[•◦]\s*)Enhancements\s*:/i, '$1Enhancement:')));
  }

  if (!factionRaw) return null;
  const factionId = conv.factionIdForName(factionRaw);
  if (!factionId) {
    notes.push(`GW app export: faction "${factionRaw}" not in the dataset`);
    return null;
  }

  // Multi-detachment header: try the whole string, then "A and B" style splits,
  // matching against the faction's real detachment names.
  const detachments = resolveDetachmentHeader(factionId, detachmentRaw, notes);

  const pts = battleLine ? battleLine.match(GW2_BATTLE_RE)[2] : null;
  const header = [
    `${factionRaw} (${pts ?? '2000'} Points)`,
    '',
    factionRaw,
    detachments[0]?.name ?? detachmentRaw ?? '',
    battleLine ?? '',
  ].filter(l => l !== null);

  const normalized = header.join('\n') + '\n\n' + bodyLines.join('\n') + '\n';
  const res = dc.tryImportRoster(normalized);
  if (!res.ok || !res.roster) {
    notes.push(`GW app export: adapter failed after normalization (${res.reason ?? '?'})`);
    return null;
  }
  const roster = res.roster;
  for (const w of roster.diagnostics?.warnings ?? []) {
    if (w.code === 'faction-unresolved' || w.code === 'detachment-unresolved') continue; // fixed below
    notes.push(w.raw_name ? `${w.code}: ${w.raw_name}` : `${w.code}: ${w.message}`);
  }

  // --- graft the captured 11e information back on ---
  roster.name = `${factionRaw} ${pts ?? ''}`.trim();
  if (!roster.faction_id) roster.faction_id = factionId;
  if (detachments.length) {
    roster.detachments = detachments.map(d => ({
      ref: { id: d.id, raw_name: d.name, resolved: true, candidates: [] },
      dp_cost: d.detachment_points ?? 1,
    }));
  } else if (detachmentRaw) {
    roster.detachments = [{ ref: { id: null, raw_name: detachmentRaw, resolved: false, candidates: [] }, dp_cost: null }];
    notes.push(`detachment "${detachmentRaw}" not matched — pick one in the editor`);
  }
  if (dispositionsRaw.length) {
    // The export lists one disposition per detachment; the roster carries one,
    // validated against the primary detachment — pick the listed disposition
    // that detachment actually allows, else the first listed.
    const fds = dispositionsRaw
      .map(nameRaw => (dc.RAW_DATA.forceDispositions ?? []).find(
        x => looseName(x.name) === looseName(nameRaw)))
      .filter(Boolean);
    const primaryAllowed = new Set(detachments[0]?.force_dispositions ?? []);
    const pick = fds.find(fd => primaryAllowed.has(fd.id)) ?? fds[0];
    if (pick) roster.force_disposition = pick.id;
    if (dispositionsRaw.length > 1 && pick) {
      notes.push(`export lists ${dispositionsRaw.length} Force Dispositions (one per detachment); the builder keeps ${pick.name}`);
    }
  }
  if (pts) {
    const limit = parseInt(pts, 10);
    roster.points.declared_limit = limit;
    roster.battle_size = limit <= 1000 ? 'incursion' : 'strike-force';
    roster.points.detachment_cap = limit <= 1000 ? 2 : 3;
  }
  for (const name of warlords) {
    const u = roster.units.find(x => x.ref?.raw_name === name);
    if (u) u.is_warlord = true;
  }
  const claimed = new Set();
  for (const pair of attachments) {
    if (!pair.leader || !pair.bodyguard) continue;
    const leader = roster.units.find(x => x.ref?.raw_name === pair.leader && !x.leader_attachment && !claimed.has(x));
    const bodyguard = roster.units.find(x => x.ref?.raw_name === pair.bodyguard);
    if (leader && bodyguard) {
      claimed.add(leader);
      leader.leader_attachment = {
        bodyguard_ref: { id: bodyguard.ref.id, raw_name: pair.bodyguard, resolved: !!bodyguard.ref.id, candidates: [] },
        role: 'leader',
        provisional: false,
      };
    }
  }

  const resolved = roster.units.filter(u => u.ref?.resolved).length;
  if (!roster.units.length || resolved < Math.ceil(roster.units.length / 2)) {
    notes.push(`GW app export: only ${resolved}/${roster.units.length} units matched — falling back`);
    return null;
  }
  return roster;
}

/** Resolve a possibly-compound detachment header ("A and B") to dataset records. */
function resolveDetachmentHeader(factionId, raw, notes) {
  if (!raw) return [];
  const whole = conv.findDetachment(factionId, raw);
  if (whole) return [whole];
  const out = [];
  for (const part of raw.split(/\s+and\s+|\s*[,+]\s*/i)) {
    if (!part.trim()) continue;
    const d = conv.findDetachment(factionId, part.trim());
    if (d) out.push(d);
    else notes.push(`detachment "${part.trim()}" not found for this faction`);
  }
  return out;
}

/** Majority faction among the resolved unit ids (unit ids are faction-scoped). */
export function inferFactionFromUnits(roster) {
  const votes = new Map();
  for (const u of roster.units ?? []) {
    if (!u.ref?.id) continue;
    for (const raw of dc.RAW_DATA.units) {
      if (raw.id === u.ref.id) {
        votes.set(raw.faction_id, (votes.get(raw.faction_id) ?? 0) + 1);
      }
    }
  }
  let best = null, bestN = 0;
  for (const [fid, n] of votes) {
    if (n > bestN) { best = fid; bestN = n; }
  }
  return best;
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
    const data = unitData(ru.ref.id, ru._unit_faction_id);
    if (!data) continue;

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
    const sourceCounts = countsOf(ru);
    const hints = ru._wargear_hints ?? [];
    delete ru._wargear_hints;
    const base = dc.baseLoadout(data.raw, ru.model_count, data.options, data.comp?.models);
    const counts = new Map(base.counts);

    if (sourceCounts.size) {
      for (let [wid, n] of sourceCounts) {
        // Shared chassis author the same weapon under per-faction ids — the
        // importer may resolve a name to another faction's copy. Remap onto
        // the datasheet's own id (by display name) so counts merge correctly.
        if (!(data.raw.weapon_ids ?? []).includes(wid)) {
          const w0 = conv.wres.resolve(data.factionId, wid);
          const remapped = w0 ? weaponIdForName(data, w0.name) : null;
          if (remapped) wid = remapped;
        }
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

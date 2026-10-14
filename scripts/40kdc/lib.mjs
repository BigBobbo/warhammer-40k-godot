// Shared helpers for the 40kdc -> game data converters.
//
// The pure dataset maths (faction-scoped resolution, name normalization,
// points tiers) lives in server/public/js/lib/dckit.mjs so the browser army
// builder uses the exact same logic; this module re-exports it and adds the
// Node-only file loading.

import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { normName } from '../../server/public/js/lib/dckit.mjs';

export {
  factionScopedResolver,
  statStr,
  normName,
  looseName,
  pointsFor,
} from '../../server/public/js/lib/dckit.mjs';

export const DATA_DIR = join(
  dirname(fileURLToPath(import.meta.url)), '..', '..', '40k', 'data', '40kdc');

const GAME_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '40k');

export function loadCollection(name, dir = DATA_DIR) {
  return JSON.parse(readFileSync(join(dir, `${name}.json`), 'utf8'));
}

// The game dispatches ability/enhancement behavior on EXACT names
// (UnitAbilityManager.ABILITY_EFFECTS, FactionAbilityManager tables,
// ArmyListManager wargear/enhancement bonus tables). Extract those names so
// converters can canonicalize emitted names to the game's spelling when they
// differ only in case/punctuation. Returns [[normName(name), name], ...].
export function buildCanonEntries() {
  const canon = new Map();
  const dirs = ['autoloads/UnitAbilityManager.gd', 'autoloads/FactionAbilityManager.gd',
    'autoloads/ArmyListManager.gd'];
  for (const rel of dirs) {
    try {
      const src = readFileSync(join(GAME_DIR, rel), 'utf8');
      for (const m of src.matchAll(/"([^"\n]{3,60})"\s*:/g)) {
        const name = m[1];
        // Only Title-cased entries — the tables key on display names, while
        // lowercase matches are ordinary dict keys ("capacity", "wounds", ...).
        if (!/^[A-Z]/.test(name)) continue;
        if (!canon.has(normName(name))) canon.set(normName(name), name);
      }
    } catch { /* file moved — canonicalization becomes a no-op */ }
  }
  return [...canon.entries()];
}

// ---------------------------------------------------------------------------
// Faction splice (ORK-only regeneration)
// ---------------------------------------------------------------------------
// Rewrites a committed pipe-delimited CSV so that ONLY the rows selected by
// `isTarget(line)` are replaced by `newRows`; every other line stays
// byte-identical (same text, same order). The new rows are inserted where the
// first removed row was (or appended when the file had none). `header`, when
// given, replaces line 1 (e.g. to append a new optional column); otherwise
// line 1 is kept verbatim. Used by generate-stratagems.mjs /
// generate-leader-pairings.mjs `--only-faction` so a dataset bump only changes
// the faction under review (see .llm/ork_codex_11e_design.md §1).
export function spliceCsvRows(filePath, { header = null, isTarget, newRows }) {
  const text = readFileSync(filePath, 'utf8');
  const trailingNewline = text.endsWith('\n');
  const lines = text.split('\n');
  if (trailingNewline) lines.pop();
  if (lines.length === 0) throw new Error(`spliceCsvRows: ${filePath} is empty`);
  const out = [header ?? lines[0]];
  let insertAt = -1;
  let removed = 0;
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (line.trim() !== '' && isTarget(line)) {
      if (insertAt < 0) insertAt = out.length;
      removed++;
      continue;
    }
    out.push(line);
  }
  if (insertAt < 0) insertAt = out.length;
  out.splice(insertAt, 0, ...newRows);
  return {
    text: out.join('\n') + (trailingNewline ? '\n' : ''),
    removed,
    inserted: newRows.length,
  };
}

// Minimal `--flag value` / `--flag=value` argv reader for the generators.
export function argValue(name, argv = process.argv.slice(2)) {
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === `--${name}`) return argv[i + 1] ?? '';
    if (a.startsWith(`--${name}=`)) return a.slice(name.length + 3);
  }
  return null;
}

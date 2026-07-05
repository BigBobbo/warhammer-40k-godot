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

// Backup and restore of everything Combat Calc keeps on this device (lists,
// attack set-ups, the list library, saved scenarios, board plans, the mission
// plan / estimates / game in progress), and moving it to another device with a
// file or a short code (the server keeps a transfer for one hour).
//
// Table photos are not part of a backup (they are large and live in IndexedDB).
// The pure functions take a Storage-like object (getItem / setItem / removeItem)
// so they are unit-tested without a browser (tests/calc-backup.test.mjs).

export const BACKUP_KEYS = ['w40k_calc_v1', 'w40k_calc_lists_v1', 'w40k_calc_saved_v1', 'w40k_calc_board_v1', 'w40k_calc_mission_v1'];
export const UNDO_KEY = 'w40k_calc_before_restore_v1';
export const LAST_KEY = 'w40k_calc_last_backup_v1';
const FORMAT = 'combat-calc-backup';

/** Everything worth keeping, as one object. */
export function makeBackup(storage, { version = '', now = new Date() } = {}) {
  const data = {};
  for (const k of BACKUP_KEYS) {
    const raw = storage.getItem(k);
    if (raw == null) continue;
    try { data[k] = JSON.parse(raw); } catch { /* skip a corrupt key */ }
  }
  return { format: FORMAT, formatVersion: 1, app: version, exported: now.toISOString(), data };
}

/** What a backup holds, in words (for the confirm dialog), or why it is not one. */
export function describeBackup(b) {
  if (!b || typeof b !== 'object' || b.format !== FORMAT || typeof b.data !== 'object' || !b.data) return { ok: false, why: 'This is not a Combat Calc backup.' };
  if ((b.formatVersion ?? 1) > 1) return { ok: false, why: 'This backup was made by a newer version of the app. Update the app first.' };
  const d = b.data;
  if (!Object.keys(d).some(k => BACKUP_KEYS.includes(k))) return { ok: false, why: 'This backup is empty.' };
  const main = d.w40k_calc_v1 ?? {};
  const lists = ['A', 'B'].filter(s => (main.texts?.[s] ?? '').trim()).length;
  const firstLine = (s) => (main.texts?.[s] ?? '').trim().split('\n')[0]?.trim() ?? '';
  const plans = Object.values(d.w40k_calc_board_v1?.plans ?? {}).reduce((n, root) => n + (root?.variants?.length ?? (root?.steps ? 1 : 0)), 0);
  const library = Array.isArray(d.w40k_calc_lists_v1) ? d.w40k_calc_lists_v1.length : 0;
  const saved = Array.isArray(d.w40k_calc_saved_v1) ? d.w40k_calc_saved_v1.length : 0;
  const game = d.w40k_calc_mission_v1?.game;
  const inGame = !!game && (game.round > 1 || ['A', 'B'].some(X => game[X]?.hand?.length || game[X]?.used?.length || game[X]?.primary || game[X]?.secondary));
  const parts = [
    lists ? `${lists} loaded list${lists > 1 ? 's' : ''} (${['A', 'B'].map(firstLine).filter(Boolean).join(' / ')})` : null,
    library ? `${library} list${library > 1 ? 's' : ''} in the library` : null,
    plans ? `${plans} board plan${plans > 1 ? 's' : ''}` : null,
    saved ? `${saved} saved scenario${saved > 1 ? 's' : ''}` : null,
    inGame ? `a game in progress (round ${game.round})` : null,
  ].filter(Boolean);
  return { ok: true, exported: b.exported ?? null, app: b.app ?? '', summary: parts.length ? parts.join(', ') : 'settings only', counts: { lists, library, plans, saved, inGame } };
}

/**
 * Replace this device's data with the backup. What was here before is kept
 * under UNDO_KEY so one restore can be undone. Returns the keys written.
 */
export function applyBackup(storage, b, { now = new Date() } = {}) {
  const info = describeBackup(b);
  if (!info.ok) throw new Error(info.why);
  const before = makeBackup(storage, { now });
  try { storage.setItem(UNDO_KEY, JSON.stringify(before)); } catch { /* no room for the undo copy: restore anyway */ }
  const written = [];
  for (const k of BACKUP_KEYS) {
    if (k in b.data) { storage.setItem(k, JSON.stringify(b.data[k])); written.push(k); } else storage.removeItem(k);
  }
  return written;
}

/** Put back what was on the device before the last restore. */
export function undoRestore(storage) {
  const raw = storage.getItem(UNDO_KEY);
  if (!raw) return false;
  const before = JSON.parse(raw);
  for (const k of BACKUP_KEYS) {
    if (k in (before.data ?? {})) storage.setItem(k, JSON.stringify(before.data[k])); else storage.removeItem(k);
  }
  storage.removeItem(UNDO_KEY);
  return true;
}

export function backupFileName(now = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `combat-calc-backup-${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}.json`;
}

// transfer codes: no 0/O, 1/I/L
export const CODE_RE = /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$/;
export const normalizeCode = (s) => String(s ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6);

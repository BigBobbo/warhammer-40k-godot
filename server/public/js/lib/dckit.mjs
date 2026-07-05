// Pure helpers over the raw 40kdc dataset, shared by the Node data pipeline
// (scripts/40kdc/*.mjs) and the browser army builder (server/public/js/builder).
// This module must stay environment-free: no fs, no path, no DOM.
//
// The raw dataset keeps every faction's authored copy of shared record ids
// (e.g. `close-combat-weapon` appears 20 times with per-faction WS), laid out
// in contiguous per-faction blocks in the same faction order as units.json.
// The package's own Dataset API dedups first-wins by plain id, which can hand
// an Ork unit a Custodes statline — so we do faction-scoped resolution here
// instead, reconstructing the blocks from unambiguous "marker" ids.

/**
 * Faction-scoped resolver over a raw collection with duplicated ids.
 *
 * The raw arrays are concatenations of per-faction (and per-wave) authoring
 * files, so copies of a shared id group into contiguous runs. We segment the
 * array greedily: extend a segment while the running intersection of
 * "which factions reference this id" stays non-empty. A segment whose
 * intersection is a single faction is that faction's authored run; ambiguous
 * segments (all-shared ids, e.g. a run of Imperium pistols) still index every
 * faction in their intersection at lower priority.
 *
 * Resolution priority for (faction, id):
 *   1. record whose own faction hint (faction_id field) matches
 *   2. copy inside a segment unambiguously labeled with the faction
 *   3. copy inside an ambiguous segment whose candidate set contains it
 *   4. first occurrence in the raw stream (the package API's behaviour)
 *
 * @param records  raw array (weapons.json / abilities.json order preserved)
 * @param units    raw units.json (defines faction references)
 * @param idOf     record -> id
 * @param refsOf   unit -> array of referenced ids
 * @param hintOf   optional: record -> faction id hint (e.g. ability.faction_id)
 */
export function factionScopedResolver(records, units, idOf, refsOf, hintOf = null) {
  const factionsById = new Map();
  for (const u of units) {
    for (const id of refsOf(u) ?? []) {
      if (!factionsById.has(id)) factionsById.set(id, new Set());
      factionsById.get(id).add(u.faction_id);
    }
  }

  // Anchor positions per faction: indices of copies of ids referenced by
  // exactly one faction (or records carrying an explicit faction hint).
  // Blocks may be split across waves — anchors handle that naturally.
  const anchors = new Map(); // faction -> sorted index array
  const addAnchor = (f, i) => {
    if (!anchors.has(f)) anchors.set(f, []);
    anchors.get(f).push(i);
  };
  records.forEach((r, i) => {
    const hint = hintOf?.(r);
    if (hint) { addAnchor(hint, i); return; }
    const fs = factionsById.get(idOf(r));
    if (fs && fs.size === 1) addAnchor([...fs][0], i);
  });

  function nearestAnchorDist(f, i) {
    const arr = anchors.get(f);
    if (!arr || arr.length === 0) return Infinity;
    // binary search
    let lo = 0, hi = arr.length - 1;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (arr[mid] < i) lo = mid + 1; else hi = mid;
    }
    let best = Math.abs(arr[lo] - i);
    if (lo > 0) best = Math.min(best, Math.abs(arr[lo - 1] - i));
    return best;
  }

  const copiesById = new Map(); // id -> [{record, index}]
  const byHint = new Map();
  records.forEach((r, i) => {
    const id = idOf(r);
    if (!copiesById.has(id)) copiesById.set(id, []);
    copiesById.get(id).push({ r, i });
    const hint = hintOf?.(r);
    if (hint && !byHint.has(`${hint}::${id}`)) byHint.set(`${hint}::${id}`, r);
  });

  const stats = { hint: 0, single: 0, nearest: 0, fallback: 0, missing: 0 };
  const memo = new Map();
  function resolve(factionId, id) {
    const key = `${factionId}::${id}`;
    if (memo.has(key)) return memo.get(key);
    let out = null;
    const hinted = byHint.get(key);
    const copies = copiesById.get(id);
    if (hinted) { stats.hint++; out = hinted; }
    else if (!copies || copies.length === 0) { stats.missing++; out = null; }
    else if (copies.length === 1) { stats.single++; out = copies[0].r; }
    else {
      let best = null, bestD = Infinity;
      for (const { r, i } of copies) {
        const d = nearestAnchorDist(factionId, i);
        if (d < bestD) { bestD = d; best = r; }
      }
      if (bestD === Infinity) { stats.fallback++; out = copies[0].r; }
      else { stats.nearest++; out = best; }
    }
    memo.set(key, out);
    return out;
  }
  return { resolve, stats, anchors };
}

/** Stat value (int or dice string like "D6+2") -> display string. */
export function statStr(v) {
  if (v === null || v === undefined) return '-';
  return String(v);
}

/** "Celestian Sacresants" -> normalized key for name matching. */
export function normName(s) {
  return String(s)
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[’'`]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Loose match key: normName + singular-ize each word (handles
 * "Twin slugga" vs "Twin sluggas", "Killsaws" vs "Killsaw").
 */
export function looseName(s) {
  return normName(s).split(' ').map(w => w.replace(/s$/, '')).join(' ');
}

/** Points cost for a unit at a given model count (first-copy pricing). */
export function pointsFor(unit, modelCount) {
  const tiers = (unit.points ?? []).filter(
    t => (t.unit_count_min ?? 1) === 1 || t.unit_count_min == null);
  let best = null;
  for (const t of tiers) {
    if (t.models === modelCount) return t.cost;
    if (t.models <= modelCount && (!best || t.models > best.models)) best = t;
  }
  return best ? best.cost : (tiers[0]?.cost ?? 0);
}

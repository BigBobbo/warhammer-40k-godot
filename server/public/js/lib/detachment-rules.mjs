// 11e army construction — selecting detachments (core rules 25.03 / 25.04).
//
// - Battle size sets the Detachment Points pool: Incursion (1000 pts) 2 DP,
//   Strike Force (2000 pts) 3 DP. Selected detachments cannot exceed it,
//   except that "if you are playing an Incursion battle, you can select a
//   3DP detachment as your only detachment".
// - The same detachment cannot be selected twice.
// - Detachments sharing a tag ("Unique: Shield Host", ...) cannot be combined.
// - The army picks ONE Force Disposition from those its detachments give.
//
// Pure functions over detachment records ({id, name, detachment_points,
// tags, force_dispositions}); the JS twin of 40k/scripts/codex/ArmyDetachments11e.gd.

export function dpCap(pointsLimit) {
  return (pointsLimit ?? 2000) <= 1000 ? 2 : 3;
}

export function dpOf(det) {
  return det?.detachment_points ?? 1;
}

export function dpUsed(dets) {
  return dets.reduce((s, d) => s + dpOf(d), 0);
}

/** A lone 3 DP detachment at Incursion (the core-rules exception). */
export function isLoneIncursionException(dets, pointsLimit) {
  return dets.length === 1 && (pointsLimit ?? 2000) <= 1000 && dpOf(dets[0]) <= 3;
}

function tagLabel(tag) {
  return String(tag).split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}

/** The tag `det` shares with one of `dets` -> {tag, with}, or null. */
export function sharedTag(dets, det) {
  for (const t of det?.tags ?? []) {
    const other = dets.find(d => d.id !== det.id && (d.tags ?? []).includes(t));
    if (other) return { tag: t, with: other };
  }
  return null;
}

/** Why `det` cannot join `dets` (null when it can). */
export function addProblem(dets, det, pointsLimit) {
  if (dets.some(d => d.id === det.id)) return 'already selected';
  const st = sharedTag(dets, det);
  if (st) return `shares the Unique: ${tagLabel(st.tag)} tag with ${st.with.name}`;
  const cap = dpCap(pointsLimit);
  const left = cap - dpUsed(dets);
  if (dpOf(det) > left) {
    return dpOf(det) >= 3 ? `${dpOf(det)} DP — must be your only detachment` : 'not enough DP';
  }
  return null;
}

/** Every rule the selection breaks ([] when legal). */
export function selectionProblems(dets, pointsLimit) {
  const out = [];
  const cap = dpCap(pointsLimit);
  const used = dpUsed(dets);
  if (used > cap && !isLoneIncursionException(dets, pointsLimit)) {
    out.push(`detachments cost ${used} DP, the pool is ${cap} DP`);
  }
  const seen = new Set();
  dets.forEach((d, i) => {
    if (seen.has(d.id)) out.push(`${d.name} is selected more than once`);
    seen.add(d.id);
    const st = sharedTag(dets.slice(0, i), d);
    if (st) out.push(`${d.name} and ${st.with.name} share the Unique: ${tagLabel(st.tag)} tag`);
  });
  return out;
}

/** Force Disposition ids the selection gives (deduped, selection order). */
export function allowedDispositions(dets) {
  const out = [];
  for (const d of dets) for (const fd of d.force_dispositions ?? []) if (!out.includes(fd)) out.push(fd);
  return out;
}

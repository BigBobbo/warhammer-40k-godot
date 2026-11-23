// Branching board plans: one plan splits after a turn into options, either the player's own decision
// ("Hunters go left" / "go right") or an outcome they do not control ("their charge wipes the Grey Hunters", 50%).
// A branch shares every turn up to the split with the path it came from: an edit to a shared turn shows in
// every branch.
//
// Stored on the board plan's variants (boardview.mjs planRoot().variants):
//   { id, name, steps, cur, parent: id|null, from: number|null, branch: { label, p: number|null },
//     splits: { [at]: { kind: 'decision'|'chance', label, p: number|null, auto: {...}|null, chosen: id|null } } }
// - a root path has parent null; a branch has parent (the path it split from) and from (the last shared step).
//   Its steps array has null at every shared index (0..from): those steps belong to an ancestor.
// - the split meta lives on the parent: splits[at].label is the name of the parent's own continuation, p its
//   chance (chance splits), chosen the option that happened (or was decided) at the table.
//
// The value of a plan tree (forecast win chances of each path, missionview.mjs): at a decision the best option
// (expectimax); at a chance split the options weighted by their chance; at a split that was resolved, the option
// that happened. Pure module: tests/calc-plantree.test.mjs.

let seq = 0;
export const newId = () => `p${Date.now().toString(36)}${(seq++).toString(36)}`;

/** Every variant gets an id (plans saved before branching have none). */
export function ensureIds(variants) {
  for (const v of variants) v.id ??= newId();
  return variants;
}
const byId = (variants, id) => variants.findIndex(v => v.id === id);

/** The steps of path i, shared steps resolved to the ancestor's step objects (the same objects: edits are shared). */
export function resolveSteps(variants, i) {
  const v = variants[i];
  if (!v) return [];
  const pi = v.parent != null ? byId(variants, v.parent) : -1;
  if (pi < 0) return v.steps.slice();
  const up = resolveSteps(variants, pi);
  const out = [];
  const n = Math.max(v.steps.length, (v.from ?? -1) + 1);
  for (let k = 0; k < n; k++) out.push(k <= v.from ? up[k] : v.steps[k]);
  return out.filter(Boolean);
}

/** Root index of path i, and the chain root -> i. */
export function chain(variants, i) {
  const out = [];
  let k = i;
  while (k >= 0 && out.length < 50) { out.unshift(k); const p = variants[k]?.parent; k = p != null ? byId(variants, p) : -1; }
  return out;
}
export const rootOf = (variants, i) => chain(variants, i)[0];

/** The options of a split: the parent's continuation first, then the branches made at that step. */
export function optionsAt(variants, pi, at) {
  const parent = variants[pi];
  const split = parent.splits?.[at] ?? {};
  const kids = variants.map((v, k) => ({ v, k })).filter(({ v }) => v.parent === parent.id && v.from === at);
  return [{ vi: pi, id: parent.id, label: split.label ?? 'As planned', p: split.p ?? null }, ...kids.map(({ v, k }) => ({ vi: k, id: v.id, label: v.branch?.label ?? v.name, p: v.branch?.p ?? null }))];
}

/**
 * The chance of each option of a chance split: the ones given (typed, or worked out: `autoP` of the first branch),
 * the rest shared equally by the options with none; scaled down if they add up to more than 1.
 */
export function chances(options, autoP = null) {
  const given = options.map(o => (o.p != null ? o.p : null));
  // the worked-out chance of the first branch counts only while nothing is typed
  if (autoP != null && given.every(g => g == null)) given[1] = autoP;
  if (options.length === 2 && given[0] == null && given[1] != null) given[0] = 1 - given[1];
  if (options.length === 2 && given[1] == null && given[0] != null) given[1] = 1 - given[0];
  const sum = given.reduce((a, g) => a + (g ?? 0), 0);
  const free = given.filter(g => g == null).length;
  const rest = Math.max(0, 1 - sum) / (free || 1);
  let ps = given.map(g => (g == null ? rest : Math.max(0, g)));
  const tot = ps.reduce((a, b) => a + b, 0);
  if (tot > 1 + 1e-9) ps = ps.map(x => x / tot);
  return ps;
}

/**
 * The tree of a root path: node = { vi, from } (a path from step `from` on) that is either a leaf, or has a split:
 * { vi, from, split: { pi, at, kind, label, chosen, auto }, options: [{ id, vi, label, p, node }] }.
 * autoP(split) -> the worked-out chance of the first branch (null = none).
 */
export function treeOf(variants, ri, autoP = () => null) {
  const node = (vi, from) => {
    const v = variants[vi];
    const ats = Object.keys(v.splits ?? {}).map(Number).filter(a => a > from && optionsAt(variants, vi, a).length > 1).sort((a, b) => a - b);
    if (!ats.length) return { vi, from };
    const at = ats[0];
    const meta = v.splits[at];
    const opts = optionsAt(variants, vi, at);
    const kind = meta.kind === 'chance' ? 'chance' : 'decision';
    const ps = kind === 'chance' ? chances(opts, autoP({ ...meta, pi: vi, at })) : opts.map(() => null);
    return {
      vi, from,
      split: { pi: vi, at, kind, label: meta.question ?? '', chosen: meta.chosen ?? null, auto: meta.auto ?? null },
      // the parent's continuation goes on past `at` (its own later splits); a branch starts at `at`
      options: opts.map((o, i) => ({ ...o, p: ps[i], typed: o.p != null, node: node(o.vi, at) })),
    };
  };
  return node(ri, -1);
}

/**
 * Values of a tree: leafValue(vi) -> number | null (not worked out yet).
 * decision: the best option (best: its id); chance: options weighted by chance; resolved: the chosen option.
 * Returns the tree with .value (and .partial when some leaves are not known) on every node.
 */
export function evaluate(tree, leafValue) {
  const walk = (n) => {
    if (!n.split) { const v = leafValue(n.vi); return { ...n, value: v ?? null, partial: v == null }; }
    const opts = n.options.map(o => ({ ...o, node: walk(o.node) }));
    const known = opts.filter(o => o.node.value != null);
    const chosen = opts.find(o => o.id === n.split.chosen);
    let value = null, best = null;
    if (chosen) value = chosen.node.value;
    else if (n.split.kind === 'decision') {
      for (const o of known) if (value == null || o.node.value > value) { value = o.node.value; best = o.id; }
    } else if (known.length === opts.length) value = opts.reduce((a, o) => a + o.p * o.node.value, 0);
    const partial = opts.some(o => o.node.partial) || known.length < opts.length;
    return { ...n, options: opts, value, best, partial };
  };
  return walk(tree);
}

/** "Main ▸ Go left ▸ Wiped": the name of path i from its root. */
export function pathLabel(variants, i) {
  const c = chain(variants, i);
  return c.map((k, j) => (j === 0 ? variants[k].name : variants[k].branch?.label ?? variants[k].name)).join(' ▸ ');
}

/** Indices of path i and every branch below it (to delete them together). */
export function subtree(variants, i) {
  const out = [i];
  for (let j = 0; j < out.length; j++) {
    const id = variants[out[j]].id;
    variants.forEach((v, k) => { if (v.parent === id && !out.includes(k)) out.push(k); });
  }
  return out;
}

/**
 * Make a branch of path i after step `at` (the steps 0..at are shared). Both paths go on at least one turn past
 * the split (copies of step `at` when there was none), so there is something to plan. Returns the new variant.
 */
export function branch(variants, i, at, { kind = 'decision', label = null, parentLabel = null, question = '' } = {}) {
  ensureIds(variants);
  const v = variants[i];
  const steps = resolveSteps(variants, i);
  const copy = (o) => JSON.parse(JSON.stringify(o));
  if (steps.length <= at + 1) {
    const next = { name: `Turn ${at + 1}`, tokens: copy(steps[at]?.tokens ?? {}) };
    if (v.parent == null || at > v.from) v.steps[at + 1] = next; else v.steps.push(next);
  }
  const full = resolveSteps(variants, i);
  v.splits ??= {};
  const n = optionsAt(variants, i, at).length;
  v.splits[at] ??= { kind, label: parentLabel ?? (kind === 'chance' ? 'It does not happen' : 'Option 1'), p: null, question, chosen: null };
  const kidSteps = full.map((s, k) => (k <= at ? null : copy(s)));
  const nb = { id: newId(), name: label ?? (v.splits[at].kind === 'chance' ? 'It happens' : `Option ${n + 1}`), parent: v.id, from: at, steps: kidSteps, cur: at + 1, branch: { label: label ?? (v.splits[at].kind === 'chance' ? 'It happens' : `Option ${n + 1}`), p: null } };
  variants.push(nb);
  return nb;
}

/**
 * The leaves of a tree (evaluated or not), top to bottom: one row per path, in the order of the tree (at each split
 * the parent's continuation first). Row: { vi, value, path: [{ pi, at, kind, id, vi, label, p, hit, gone, best }],
 * reach (chance of ending up on this path from here: chance splits not yet known multiply, a known one is 1 or 0),
 * gone (an option on the way did not happen / was not chosen), onBest (every open decision on the way is the best one) }.
 */
export function treeRows(tree) {
  const rows = [];
  const walk = (n, path) => {
    if (!n.split) { rows.push({ vi: n.vi, value: n.value ?? null, path }); return; }
    const s = n.split;
    const open = s.kind === 'decision' && !s.chosen && n.best != null;
    for (const o of n.options) {
      walk(o.node, [...path, { pi: s.pi, at: s.at, kind: s.kind, id: o.id, vi: o.vi, label: o.label, p: o.p,
        hit: s.chosen === o.id, gone: !!s.chosen && s.chosen !== o.id, best: open && n.best === o.id, open }]);
    }
  };
  walk(tree, []);
  for (const r of rows) {
    r.reach = r.path.reduce((a, c) => a * (c.gone ? 0 : c.hit || c.kind !== 'chance' ? 1 : c.p ?? 0), 1);
    r.gone = r.path.some(c => c.gone);
    r.onBest = r.path.some(c => c.open) && r.path.every(c => !c.open || c.best);
  }
  return rows;
}

/**
 * "Main ▸ Go left ▸ Survives": the name of path i by every choice on the way, the parent's own continuations
 * included (pathLabel names only the branches: the main path would be just "Main").
 */
export function choiceLabel(variants, i) {
  const c = chain(variants, i), out = [variants[c[0]].name];
  c.forEach((k, j) => {
    const v = variants[k], next = c[j + 1] != null ? variants[c[j + 1]] : null;
    const from = j === 0 ? -1 : v.from, upto = next ? next.from : Infinity;
    for (const at of Object.keys(v.splits ?? {}).map(Number).filter(a => a > from && a <= upto).sort((a, b) => a - b)) {
      if (optionsAt(variants, k, at).length < 2) continue;
      out.push(next && at === upto ? next.branch?.label ?? next.name : v.splits[at].label ?? 'As planned');
    }
  });
  return out.join(' ▸ ');
}

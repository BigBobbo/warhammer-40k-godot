// Branching board plans (public/calc/plantree.mjs): shared turns, splits, chances, and the value of the tree.
import { test } from 'node:test';
import assert from 'node:assert/strict';
const T = await import(new URL('../public/calc/plantree.mjs', import.meta.url).href);

const tok = (x) => ({ 'A:gh': { x, y: 10 } });
const plan = () => T.ensureIds([{ name: 'Main', steps: [{ name: 'Deploy', tokens: tok(1) }, { name: 'Turn 1', tokens: tok(2) }, { name: 'Turn 2', tokens: tok(3) }], cur: 2 }]);

test('a branch shares the turns up to the split, as the same objects; later turns are its own', () => {
  const v = plan();
  const b = T.branch(v, 0, 1, { kind: 'decision', label: 'Go right', parentLabel: 'Go left' });
  assert.equal(v.length, 2);
  const s0 = T.resolveSteps(v, 0), s1 = T.resolveSteps(v, 1);
  assert.equal(s1.length, 3);
  assert.equal(s1[0], s0[0], 'Deploy is the same object');
  assert.equal(s1[1], s0[1], 'Turn 1 is the same object');
  assert.notEqual(s1[2], s0[2], 'Turn 2 is the branch’s own');
  s1[1].tokens['A:gh'].x = 9;                   // an edit to a shared turn shows in both
  assert.equal(T.resolveSteps(v, 0)[1].tokens['A:gh'].x, 9);
  s1[2].tokens['A:gh'].x = 20;                  // an edit after the split does not
  assert.equal(T.resolveSteps(v, 0)[2].tokens['A:gh'].x, 3);
  assert.deepEqual([b.parent, b.from, b.cur], [v[0].id, 1, 2]);
  assert.equal(T.pathLabel(v, 1), 'Main ▸ Go right');
  assert.equal(JSON.parse(JSON.stringify(v))[1].steps[0], null, 'shared turns are stored once');
});

test('branching at the last turn adds the next turn to both paths', () => {
  const v = plan();
  T.branch(v, 0, 2, { kind: 'chance', label: 'Charge wipes them', parentLabel: 'They survive' });
  assert.deepEqual(T.resolveSteps(v, 0).map(s => s.name), ['Deploy', 'Turn 1', 'Turn 2', 'Turn 3']);
  assert.deepEqual(T.resolveSteps(v, 1).map(s => s.name), ['Deploy', 'Turn 1', 'Turn 2', 'Turn 3']);
  assert.notEqual(T.resolveSteps(v, 0)[3], T.resolveSteps(v, 1)[3]);
});

test('chances: given ones kept, the rest shared; two options add up to 1; too much is scaled', () => {
  assert.deepEqual(T.chances([{ p: null }, { p: 0.3 }]), [0.7, 0.3]);
  assert.deepEqual(T.chances([{ p: null }, { p: null }], 0.45).map(x => +x.toFixed(2)), [0.55, 0.45], 'the worked-out chance of the first branch');
  assert.deepEqual(T.chances([{ p: 0.6 }, { p: null }], 0.45).map(x => +x.toFixed(2)), [0.6, 0.4], 'a typed chance beats the worked-out one');
  assert.deepEqual(T.chances([{ p: null }, { p: 0.2 }, { p: null }]).map(x => +x.toFixed(2)), [0.4, 0.2, 0.4]);
  assert.deepEqual(T.chances([{ p: 0.8 }, { p: 0.6 }, { p: null }]).map(x => +x.toFixed(3)), [0.571, 0.429, 0]);
});

test('the tree and its value: best at a decision, weighted at a chance, the chosen one once it happened', () => {
  const v = plan();
  // after Turn 1: go left (main) or go right; on the left path, after Turn 2: their charge wipes the squad (40%) or not
  const right = T.branch(v, 0, 1, { kind: 'decision', label: 'Go right', parentLabel: 'Go left' });
  const wiped = T.branch(v, 0, 2, { kind: 'chance', label: 'Squad wiped', parentLabel: 'Squad survives' });
  wiped.branch.p = 0.4;
  const iRight = v.indexOf(right), iWiped = v.indexOf(wiped);
  const tree = T.treeOf(v, 0);
  assert.equal(tree.split.at, 1);
  assert.deepEqual(tree.options.map(o => o.label), ['Go left', 'Go right']);
  const left = tree.options[0].node;
  assert.equal(left.split.kind, 'chance');
  assert.deepEqual(left.options.map(o => [o.label, +o.p.toFixed(2)]), [['Squad survives', 0.6], ['Squad wiped', 0.4]]);
  assert.equal(tree.options[1].node.split, undefined, 'the right path has no split of its own');
  // win chances of the paths (leaves)
  const win = { 0: 0.70, [iWiped]: 0.40, [iRight]: 0.55 };
  const ev = T.evaluate(tree, (i) => win[i] ?? null);
  const leftV = 0.6 * 0.70 + 0.4 * 0.40;            // 0.58
  assert.ok(Math.abs(ev.options[0].node.value - leftV) < 1e-9);
  assert.equal(ev.value, leftV, 'go left (58%) beats go right (55%)');
  assert.equal(ev.best, v[0].id);
  // their charge happened and wiped the squad: the left path is now worth 40%, so right is better
  v[0].splits[2].chosen = wiped.id;
  const ev2 = T.evaluate(T.treeOf(v, 0), (i) => win[i] ?? null);
  assert.equal(ev2.options[0].node.value, 0.40);
  assert.equal(ev2.best, right.id);
  // a path not worked out yet: the value is partial
  const ev3 = T.evaluate(T.treeOf(v, 0), (i) => (i === iRight ? null : win[i]));
  assert.equal(ev3.partial, true);
  assert.deepEqual(T.subtree(v, 0).sort(), [0, 1, 2]);
  assert.deepEqual(T.subtree(v, iWiped), [iWiped]);
});

test('a worked-out chance (from the calculator) is used until a chance is typed', () => {
  const v = plan();
  const b = T.branch(v, 0, 2, { kind: 'chance', label: 'Wiped', parentLabel: 'Survives' });
  v[0].splits[2].auto = { atk: 'B:mn', def: 'A:gh', how: 'fight' };
  const tree = T.treeOf(v, 0, (split) => (split.auto ? 0.3 : null));
  assert.deepEqual(tree.options.map(o => +o.p.toFixed(2)), [0.7, 0.3]);
  b.branch.p = 0.5;
  assert.deepEqual(T.treeOf(v, 0, () => 0.3).options.map(o => o.p), [0.5, 0.5]);
});

// List gap-finder (public/calc/gapfinder.mjs): reference targets and the per-target summary.
import { test } from 'node:test';
import assert from 'node:assert/strict';
const G = await import(new URL('../public/calc/gapfinder.mjs', import.meta.url).href);

test('eight reference targets; the Knight has its 5++ only against shooting', () => {
  assert.equal(G.GAP_TARGETS.length, 8);
  const k = G.GAP_TARGETS.find(t => t.id === 'knight');
  assert.equal(G.gapProfile(k, 'shooting').groups[0].InSv, 5);
  assert.equal(G.gapProfile(k, 'fight').groups[0].InSv, 0);
  assert.deepEqual(G.gapProfile(k, 'fight').keywords, ['VEHICLE', 'TITANIC']);
  assert.equal(G.gapStats(G.GAP_TARGETS.find(t => t.id === 'heavy')), 'T6 · 2+ · 4++ · W3 × 5');
});

test('summary: shooting and fighting add up per target, one unit counts at most one target; gaps flagged', () => {
  const cells = [
    { unit: 'a', name: 'Lascannons', target: 'tank', phase: 'shooting', frac: 0.6 },
    { unit: 'b', name: 'Thunder hammers', target: 'tank', phase: 'fight', frac: 1.7 },
    { unit: 'a', name: 'Lascannons', target: 'horde', phase: 'shooting', frac: 0.1 },
    { unit: 'b', name: 'Thunder hammers', target: 'horde', phase: 'fight', frac: 0.3 },
  ];
  const s = G.gapSummary(cells);
  const tank = s.find(x => x.id === 'tank'), horde = s.find(x => x.id === 'horde');
  assert.equal(tank.total, 1.6);
  assert.equal(tank.level, 'thin');
  assert.deepEqual(tank.best.map(b => b.name), ['Thunder hammers', 'Lascannons']);
  assert.equal(horde.level, 'gap');
  assert.ok(s.find(x => x.id === 'knight').weakest, 'nothing hurts the Knight: weakest');
  assert.equal(tank.meleeOnly, false);
  assert.equal(horde.meleeOnly, true);
  // the fight phase counts the best three units only
  const many = ['a', 'b', 'c', 'd', 'e'].map(u => ({ unit: u, name: u, target: 'elite', phase: 'fight', frac: 0.5 }));
  assert.equal(G.gapSummary(many).find(x => x.id === 'elite').fight, 1.5);
});

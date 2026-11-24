// Share links (public/calc/sharelink.mjs): the lists and plan go into the link, compressed, and come back intact.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const S = await import(new URL('../public/calc/sharelink.mjs', import.meta.url).href);
const SW = readFileSync(new URL('./fixtures/gw-space-wolves-2000.txt', import.meta.url), 'utf8');
const ORK = readFileSync(new URL('./fixtures/gw-orks-1000.txt', import.meta.url), 'utf8');

test('round trip: lists, set-up and plan come back the same; the link is URL-safe and much shorter than the lists', async () => {
  const p = { view: 'board', names: { A: 'Space Wolves', B: 'Orks' }, texts: { A: SW, B: ORK }, attach: { A: null, B: null },
    board: { settings: { variant: 2 }, plans: { 'x|y': { variants: [{ name: 'Main', steps: [{ name: 'Deploy', tokens: { 'A:u1': { x: 10, y: 5 } } }] }], v: 0 } } } };
  const code = await S.packShare(p);
  assert.match(code, /^[A-Za-z0-9_-]+$/);
  assert.ok(code.length < (SW.length + ORK.length) * 0.7, `${code.length} vs ${SW.length + ORK.length}`);
  const back = await S.unpackShare(code);
  assert.equal(back.f, S.SHARE_FORMAT);
  assert.deepEqual({ ...back, f: undefined, v: undefined }, { ...p, f: undefined, v: undefined });
  assert.equal(S.shareTitle(back), 'Space Wolves vs Orks — board plan');
});

test('a cut-short or foreign link says so', async () => {
  const code = await S.packShare({ texts: { A: SW, B: ORK } });
  await assert.rejects(S.unpackShare(code.slice(0, 40)), /incomplete or damaged/);
  await assert.rejects(S.unpackShare('not-a-link'), /incomplete or damaged/);
});

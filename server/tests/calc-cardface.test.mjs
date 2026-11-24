// Secondary cards drawn as cards (public/calc/cardface.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';

const F = await import(new URL('../public/calc/cardface.mjs', import.meta.url).href);
const { SECONDARIES, SECONDARY_BY_ID } = await import(new URL('../public/calc/missions-11e.mjs', import.meta.url).href);

test('scoring lines: one per VP amount, a shared lead-in kept apart', () => {
  assert.deepEqual(F.scoreLines(SECONDARY_BY_ID['engage-on-all-fronts'].text), { intro: 'Units wholly in table quarters (not within 6" of the centre)', lines: [{ vp: '3', text: 'For three quarters' }, { vp: '5', text: 'For four' }] });
  assert.deepEqual(F.scoreLines(SECONDARY_BY_ID['defend-stronghold'].text).lines.map(l => l.vp), ['3', '+2']);
  assert.deepEqual(F.scoreLines(SECONDARY_BY_ID.plunder.text), { intro: null, lines: [{ vp: '5', text: 'Action (Shooting phase) by a unit in a terrain area outside your territory' }] });
});

test('every card: at least one scoring line, each with its VP and words', () => {
  for (const c of SECONDARIES) {
    const s = F.scoreLines(c.text);
    assert.ok(s.lines.length >= 1 && s.lines.every(l => l.vp && l.text.length > 3), c.id);
    if (c.fixedText) assert.ok(F.scoreLines(c.fixedText).lines.every(l => l.vp && l.text), `${c.id} fixed`);
  }
});

test('the card face: name, Tactical / Fixed, When drawn, when it scores, the Fixed version', () => {
  const h = F.cardFace(SECONDARY_BY_ID['a-grievous-blow']);
  assert.match(h, /data-cardface="a-grievous-blow"/);
  assert.match(h, /cf-name">A Grievous Blow</);
  assert.match(h, /cf-tag">Tactical<\/span><span class="cf-tag fixed">Fixed</);
  assert.match(h, /When drawn<\/div><div>No enemy unit with Starting Strength 13\+ left/);
  assert.match(h, /Tactical · End of either player’s turn/);
  assert.match(h, /Fixed mission<\/div>.*cf-vp">4<small>VP/s);
  assert.doesNotMatch(F.cardFace(SECONDARY_BY_ID['centre-ground']), /Fixed mission|When drawn/);
});

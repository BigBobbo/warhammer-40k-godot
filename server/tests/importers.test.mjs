// Import-path tests for the army builder, run against the committed vendor
// bundle: node --test server/tests/
//
// The Death Guard fixture is a real export from the official GW app v2.0.5
// (11th edition): faction on line 1, a compound multi-detachment header with
// Detachment Points, a Force Dispositions line, ATTACHED UNITS blocks with
// "Attached as:" bullets, thousands separators, and an app-version footer.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';

const FIXTURE = new URL('./fixtures/gw_app_v2_death_guard.txt', import.meta.url);

const S = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const I = await import(new URL('../public/js/builder/importers.js', import.meta.url).href);

test('GW app v2 (11e) export is detected', () => {
  const text = readFileSync(FIXTURE, 'utf8');
  assert.ok(I.looksLikeGwAppV2(text));
  // ...and the classic formats are not misrouted into the v2 path
  assert.ok(!I.looksLikeGwAppV2('Orks (1000 pts)\nWar Horde\n\nBoyz (75 pts)\n'));
});

test('GW app v2 Death Guard list imports fully', () => {
  const text = readFileSync(FIXTURE, 'utf8');
  const { roster, report } = I.importText(text);

  assert.equal(roster.faction_id, 'death-guard', report.warnings.join('; '));
  assert.equal(roster.units.length, 16, 'all 16 entries present');
  assert.equal(roster.units.filter(u => u.ref.resolved).length, 16, 'all units matched');

  // Multi-detachment header: Contagion Engines (1DP) + Death Lord's Chosen (2DP)
  assert.deepEqual(
    roster.detachments.map(d => d.ref.id).sort(),
    ['contagion-engines', 'death-lords-chosen']);
  assert.equal(roster.detachments.reduce((s, d) => s + d.dp_cost, 0), 3);

  // Disposition picked from the listed pair, valid for the primary detachment
  assert.equal(roster.force_disposition, 'purge-the-foe');
  assert.equal(roster.battle_size, 'strike-force');
  assert.equal(roster.points.declared_limit, 2000);

  // Warlord bullet
  const typhus = roster.units.find(u => u.ref.id === 'typhus');
  assert.equal(typhus.is_warlord, true);

  // Attached-unit blocks become leader attachments
  const lov = roster.units.find(u => u.ref.id === 'lord-of-virulence');
  assert.equal(lov.leader_attachment?.bodyguard_ref?.id, 'blightlord-terminators');
  const loc = roster.units.find(u => u.ref.id === 'lord-of-contagion');
  assert.equal(loc.leader_attachment?.bodyguard_ref?.id, 'deathshroud-terminators');

  // Enhancement (plural "Enhancements:" line in the export)
  assert.equal(lov.enhancement?.ref?.id ?? lov.enhancement?.id, 'vile-vigour-death-lords-chosen');

  // Model counts from the ◦ model-group lines
  const blightlords = roster.units.find(u => u.ref.id === 'blightlord-terminators');
  assert.equal(blightlords.model_count, 5);
  const deathshrouds = roster.units.filter(u => u.ref.id === 'deathshroud-terminators');
  assert.deepEqual(deathshrouds.map(u => u.model_count).sort(), [3, 6]);
});

test('GW app v2 Death Guard list converts to game JSON without warnings', () => {
  const text = readFileSync(FIXTURE, 'utf8');
  const { roster } = I.importText(text);
  const { army, warnings, totalPoints } = S.conv.rosterToGame(roster, { createdDate: '2026-07-06' });

  assert.deepEqual(warnings, [], 'no conversion warnings');
  assert.equal(Object.keys(army.units).length, 16);
  assert.equal(totalPoints, 1995, 'matches the app export total');
  assert.equal(army.faction.name, 'Death Guard');

  // Cross-faction weapon-id remap: DG Chaos Spawn keep their own
  // hideous-mutations at the source count, not a duplicated foreign copy.
  const spawn = Object.values(army.units).find(u => u.meta.name === 'Chaos Spawn');
  assert.deepEqual(spawn.meta.wargear, ['2x Hideous mutations']);
  assert.equal(spawn.models.length, 2);

  const lov = Object.values(army.units).find(u => u.meta.name === 'Lord of Virulence');
  assert.deepEqual(lov.meta.enhancements, ['Vile Vigour']);
  assert.equal(lov.meta.points, 115, '100 base + 15 enhancement');

  // Army-construction legality: no errors from the package checker
  const legality = S.dc.checkRoster(roster, S.ds);
  assert.deepEqual(legality.army.filter(v => v.severity === 'error'), []);
  assert.deepEqual(legality.units.filter(u => u.violations.length), []);
});

test('faction is inferred from resolved units when the header fails', () => {
  // Old-style loose text: line 1 reads as a list name to the gw adapter, so
  // the faction comes back null — inference recovers it from the units.
  const text = `Orks (1000 pts)
War Horde

Beastboss (80 pts)
• Beast Snagga klaw

Boyz (150 pts)
• Choppa
`;
  const { roster } = I.importText(text);
  assert.equal(roster.faction_id, 'orks');
  assert.equal(roster.units.filter(u => u.ref.resolved).length, 2);
});

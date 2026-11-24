// Lists from / to the game's army store (public/calc/gamelists.mjs, adapter.mjs gameArmyToText / armyToGame).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';

const G = await import(new URL('../public/calc/gamelists.mjs', import.meta.url).href);
const A = await import(new URL('../public/calc/adapter.mjs', import.meta.url).href);
const gameFile = (n) => JSON.parse(readFileSync(new URL(`../../40k/armies/${n}.json`, import.meta.url), 'utf8'));
const fixture = (n) => readFileSync(new URL(`./fixtures/${n}`, import.meta.url), 'utf8');
const q = (s) => String(s ?? '').replace(/[’']/g, "'");

test('a game army file as WTC list text: one line per unit with its wargear, the enhancement, the warlord', () => {
  const t = G.gameArmyText({
    faction: { name: 'Space Wolves', points: 2000, force_disposition: 'take-and-hold' },
    detachments: [{ name: 'Assault Brethren' }, { name: 'Stormlance Task Force' }],
    units: {
      U_LOGAN: { meta: { name: 'Logan Grimnar', points: 150, is_warlord: true, enhancements: [], wargear: ['1x Axe Morkai'] }, models: [{}] },
      U_TAS: { meta: { name: 'Terminator Assault Squad', points: 395, enhancements: ['Furious Assault'], wargear: ['9x Thunder Hammer', '1x Twin Lightning Claws'] }, models: Array(10).fill({}) },
    },
  }, 'Gaelcon');
  assert.match(t, /\+ LIST NAME: Gaelcon\n\+ FACTION KEYWORD: Space Wolves\n\+ DETACHMENT: Assault Brethren\n\+ DETACHMENT: Stormlance Task Force\n\+ FORCE DISPOSITION: Take And Hold\n\+ TOTAL ARMY POINTS: 545pts/);
  assert.match(t, /\n1x Logan Grimnar \(150 pts\): 1x Axe Morkai, Warlord\n10x Terminator Assault Squad \(395 pts\): 9x Thunder Hammer, 1x Twin Lightning Claws\nEnhancement: Furious Assault\n/);
  assert.equal(G.storeName('R3 – Necrons (final)!'), 'R3_Necrons_final');
});

test('a Space Wolves game file: written out line by line (the builder’s converter cannot place its datasheets), every unit and price right', () => {
  const r = A.gameArmyToText(gameFile('sw11e_gw_import_2000'), 'sw');
  assert.equal(r.how, 'lines');
  assert.deepEqual([r.recognised, r.units, r.pointsOk, r.checked], [12, 12, 12, 12]);
  const army = A.importArmy(r.text);
  const tas = army.roster.units.find(u => u.ref?.raw_name === 'Terminator Assault Squad');
  assert.deepEqual([tas.model_count, tas.enhancement?.raw_name, A.listedPoints(tas)], [10, 'Furious Assault', 395]);
});

test('a Custodes game file: through the Army Builder’s converter, every unit recognised and priced as the file says', () => {
  const r = A.gameArmyToText(gameFile('custodes_lions'), 'cl');
  assert.equal(r.how, 'builder');
  assert.equal(r.recognised, r.units);
  const file = Object.values(gameFile('custodes_lions').units).map(u => u.meta.points).sort((a, b) => a - b);
  assert.deepEqual(A.importArmy(r.text).roster.units.map(u => A.listedPoints(u)).sort((a, b) => a - b), file);
});

test('send to the game and back: the same units, models, enhancements and prices (a second copy keeps its own price)', () => {
  const army = A.importArmy(fixture('nr-custodes-1995.txt'));
  const { game, warnings } = A.armyToGame(army, new Date(2026, 10, 24));
  assert.deepEqual(warnings, []);
  assert.equal(game.faction.created_date, '2026-11-24');
  assert.equal(Object.keys(game.units).length, 9);
  const back = A.importArmy(A.gameArmyToText(game, 'rt').text);
  const sig = (r) => r.units.map(u => `${u.ref?.id}|${u.model_count}|${q(u.enhancement?.raw_name)}|${A.listedPoints(u)}`).sort();
  assert.deepEqual(sig(back.roster), sig(army.roster));
  assert.deepEqual(back.roster.units.filter(u => u.ref?.raw_name === 'Shield-Captain').map(u => A.listedPoints(u)).sort(), [220, 225]);
});

test('the game-file converter prices a second copy of a datasheet as a second copy (Shield-Captain 205, then 225)', async () => {
  const I = await import(new URL('../public/js/builder/importers.js', import.meta.url).href);
  const { game } = A.armyToGame(A.importArmy(fixture('nr-custodes-1995.txt')));
  const { roster } = I.importGameObject(game, { name: 'x' });
  const sc = roster.units.filter(u => u.ref?.raw_name === 'Shield-Captain').map(u => [u.points, u.enhancement_points]);
  assert.deepEqual(sc, [[205, 15], [225, null]]);
  assert.equal(roster.points.total_computed, 1995);
});

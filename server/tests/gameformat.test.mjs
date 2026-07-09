// Unit tests for the shared 40kdc <-> game-format converter and the builder's
// roster engine, run against the committed vendor bundle (no npm install
// needed): node --test server/tests/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = join(here, '..', '..');
const ARMIES = join(ROOT, '40k', 'armies');

const V = await import(new URL('../public/js/vendor/40kdc-data.mjs', import.meta.url).href);
const { createConverter } = await import(new URL('../public/js/lib/gameformat.mjs', import.meta.url).href);
const { GAME_NAME_CANON_ENTRIES } = await import(new URL('../public/js/lib/canon.mjs', import.meta.url).href);

const conv = createConverter({
  rawData: V.RAW_DATA,
  describeAbility: V.describeAbility,
  canonEntries: GAME_NAME_CANON_ENTRIES,
});

const KNOWN_FACTIONS = new Set(['Orks', 'Adeptus Custodes', 'Space Marines']);

function armyFiles() {
  return readdirSync(ARMIES)
    .filter(f => f.endsWith('.json'))
    .map(f => ({ file: f, army: JSON.parse(readFileSync(join(ARMIES, f), 'utf8')) }))
    .filter(({ army }) => KNOWN_FACTIONS.has(army.faction?.name));
}

// ---------------------------------------------------------------------------

test('every bundled army round-trips through gameToRoster -> rosterToGame', () => {
  for (const { file, army } of armyFiles()) {
    const { roster } = conv.gameToRoster(army, { name: file });
    const { army: out } = conv.rosterToGame(roster, { createdDate: army.faction.created_date });
    assert.ok(out, `${file}: conversion produced no army`);

    const origUnits = Object.values(army.units).filter(
      u => !(u.meta?.keywords ?? []).includes('UNKNOWN'));
    const outUnits = Object.values(out.units);
    assert.equal(outUnits.length, origUnits.length, `${file}: unit count`);

    for (let i = 0; i < origUnits.length; i++) {
      const a = origUnits[i], b = outUnits[i];
      const label = `${file}/${a.meta.name}`;
      assert.equal(b.meta.name, a.meta.name, `${label}: order/name`);
      assert.equal(b.models.length, a.models.length, `${label}: model count`);
      assert.deepEqual(b.meta.stats, a.meta.stats, `${label}: stats`);
      assert.equal(b.meta.points, a.meta.points, `${label}: points`);
      assert.equal(b.meta.is_warlord, a.meta.is_warlord, `${label}: warlord`);
      const an = new Set(a.meta.weapons.map(w => w.name));
      const bn = new Set(b.meta.weapons.map(w => w.name));
      assert.deepEqual([...bn].sort(), [...an].sort(), `${label}: weapon set`);
    }
    assert.equal(out.faction.detachment, army.faction.detachment, `${file}: detachment`);
    assert.equal(out.faction.schema, 2, `${file}: schema`);
  }
});

test('fresh Ork roster builds a valid schema-2 army', () => {
  const boyz = V.RAW_DATA.units.find(u => u.faction_id === 'orks' && u.id === 'boyz');
  const comp = V.RAW_DATA.unitCompositions.find(c => c.faction_id === 'orks' && c.unit_id === 'boyz');
  const opts = V.RAW_DATA.wargearOptions.filter(o => o.faction_id === 'orks' && o.unit_id === 'boyz');
  const base = V.baseLoadout(boyz, 10, opts, comp.models);
  const wargearOf = (counts) => [...counts.entries()].map(([id, count]) => ({
    ref: { id, raw_name: id, resolved: true, candidates: [] }, count,
  }));

  const roster = {
    name: 'Test Orks',
    source: { format: 'roster-json', generated_by: 'test' },
    faction_id: 'orks',
    detachments: [{ ref: { id: 'war-horde', raw_name: 'War Horde', resolved: true, candidates: [] }, dp_cost: 2 }],
    battle_size: 'incursion',
    force_disposition: 'take-and-hold',
    points: { declared_limit: 1000, detachment_cap: 2, total_reported: null, total_computed: 0 },
    units: [
      {
        ref: { id: 'beastboss', raw_name: 'Beastboss', resolved: true, candidates: [] },
        model_count: 1, points: null, is_warlord: true,
        enhancement: { id: 'headwoppas-killchoppa-war-horde', raw_name: '', resolved: true, candidates: [] },
        enhancement_points: null,
        wargear: [], leader_attachment: null,
      },
      {
        ref: { id: 'boyz', raw_name: 'Boyz', resolved: true, candidates: [] },
        model_count: 10, points: null, is_warlord: false,
        enhancement: null, enhancement_points: null,
        wargear: wargearOf(base.counts), leader_attachment: null,
      },
    ],
    game_version: { edition: '11th', dataslate: 'launch' },
    diagnostics: { resolved_units: 2, unresolved_units: 0, resolved_weapons: 0, unresolved_weapons: 0, warnings: [] },
  };

  const { army, warnings } = conv.rosterToGame(roster, { createdDate: '2026-07-05' });
  assert.ok(army, 'army produced');
  assert.deepEqual(warnings, [], 'no conversion warnings');

  const keys = Object.keys(army.units);
  assert.deepEqual(keys, ['U_BEASTBOSS_A', 'U_BOYZ_A'], 'unit key convention');

  const bb = army.units.U_BEASTBOSS_A;
  assert.equal(bb.meta.is_warlord, true);
  assert.equal(bb.meta.points, 100, 'beastboss 80 + 20 enhancement');
  assert.deepEqual(bb.meta.enhancements, ["Headwoppa's Killchoppa"], 'canonical enhancement name');
  assert.ok(bb.meta.abilities.some(a => a.name === 'Waaagh!' && a.type === 'Faction'), 'army rule present');

  const bz = army.units.U_BOYZ_A;
  assert.equal(bz.meta.points, 75);
  assert.equal(bz.models.length, 10);
  assert.equal(bz.models[0].wounds, 2, 'boss nob first with W2');
  assert.ok(bz.models.slice(1).every(m => m.wounds === 1), 'boys W1');
  assert.deepEqual(bz.meta.wargear, ['10x Slugga', '1x Big choppa', '9x Choppa'], 'wargear strings');
  const slugga = bz.meta.weapons.find(w => w.name === 'Slugga');
  assert.ok(slugga && slugga.type === 'Ranged', 'slugga profile emitted');

  assert.equal(army.faction.name, 'Orks');
  assert.equal(army.faction.detachment, 'War Horde');
  assert.equal(army.faction.edition, 11);

  // Structured weapon abilities must stay inside the game's registry ids.
  const REGISTRY = new Set(['anti', 'assault', 'blast', 'cleave', 'close_quarters',
    'devastating_wounds', 'extra_attacks', 'hazardous', 'heavy', 'ignores_cover',
    'indirect_fire', 'lance', 'lethal_hits', 'melta', 'one_shot', 'pistol',
    'precision', 'psychic', 'rapid_fire', 'sustained_hits', 'torrent', 'twin_linked']);
  for (const u of Object.values(army.units)) {
    for (const w of u.meta.weapons) {
      for (const a of w.abilities ?? []) {
        assert.ok(REGISTRY.has(a.id), `unknown structured ability id ${a.id} on ${w.name}`);
      }
    }
  }
});

test('Stompa resolves to a 180mm round base, not the 32mm draft fallback', () => {
  // The dataset ships the Stompa with a dimensionless draft base
  // ({ shape: 'hull', draft: true }); BASE_SIZE_OVERRIDES pins it to 180mm.
  const stompa = V.RAW_DATA.units.find(u => u.faction_id === 'orks' && u.id === 'stompa');
  const comp = V.RAW_DATA.unitCompositions.find(c => c.faction_id === 'orks' && c.unit_id === 'stompa');
  assert.ok(stompa && comp, 'stompa unit + composition present in dataset');

  const models = conv.buildModelsArray(stompa, comp, 1);
  assert.equal(models.length, 1, 'stompa is a single-model unit');
  assert.equal(models[0].base_mm, 180, 'stompa base_mm pinned to 180');
  assert.ok(models[0].base_type === undefined || models[0].base_type === 'circular',
    'stompa stays a round base (no oval/rectangular base_type)');
});

test('package legality checker accepts the fresh roster shape', () => {
  const { roster } = conv.gameToRoster(
    JSON.parse(readFileSync(join(ARMIES, 'Orks_2000.json'), 'utf8')), { name: 'orks' });
  const verdict = V.checkRoster(roster, V.dataset);
  assert.ok(Array.isArray(verdict.army), 'army-level checks ran');
  assert.ok(Array.isArray(verdict.units), 'unit-level checks ran');
});

test('GW-format text imports, snaps sizes, and normalizes loadouts', async () => {
  // The builder store carries module state; import it fresh here.
  const S = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
  const I = await import(new URL('../public/js/builder/importers.js', import.meta.url).href);
  const text = `Waaagh Test (600 Points)

Orks
War Horde
Incursion (1000 Points)

CHARACTERS

Beastboss (80 Points)
  • 1x Beast Snagga klaw
  • 1x Beastchoppa
  • 1x Shoota

BATTLELINE

Boyz (150 Points)
  • 19x Boy
  • 1x Boss Nob
`;
  const { roster, report } = I.importText(text);
  assert.equal(roster.faction_id, 'orks', 'faction resolved');
  assert.equal(roster.units.length, 2);
  assert.ok(roster.units.every(u => u.ref.resolved), 'all units matched');
  const boyz = roster.units[1];
  assert.equal(boyz.model_count, 20, `boyz snapped to 20 via 150pts (${report.warnings.join('; ')})`);
  const counts = S.countsOf(boyz);
  assert.equal(counts.get('slugga'), 20, 'slugga at full squad count');
  assert.equal(counts.get('choppa'), 19, 'choppa on every boy');
  const violations = V.validateLoadout(
    V.RAW_DATA.units.find(u => u.faction_id === 'orks' && u.id === 'boyz'),
    20,
    V.RAW_DATA.wargearOptions.filter(o => o.faction_id === 'orks' && o.unit_id === 'boyz'),
    counts,
    V.RAW_DATA.unitCompositions.find(c => c.faction_id === 'orks' && c.unit_id === 'boyz').models);
  assert.deepEqual(violations, [], 'imported loadout is legal');
});

test('unit keys letter per duplicate datasheet', () => {
  const mk = (id) => ({
    ref: { id, raw_name: id, resolved: true, candidates: [] },
    model_count: 1, points: null, is_warlord: false,
    enhancement: null, enhancement_points: null, wargear: [], leader_attachment: null,
  });
  const roster = {
    name: 'dups', source: { format: 'roster-json', generated_by: 't' },
    faction_id: 'orks',
    detachments: [], battle_size: null, force_disposition: null,
    points: { declared_limit: null, detachment_cap: null, total_reported: null, total_computed: 0 },
    units: [mk('mek'), mk('mek'), mk('beastboss')],
    game_version: { edition: '11th', dataslate: 'launch' },
    diagnostics: { resolved_units: 3, unresolved_units: 0, resolved_weapons: 0, unresolved_weapons: 0, warnings: [] },
  };
  const { army } = conv.rosterToGame(roster, {});
  assert.deepEqual(Object.keys(army.units), ['U_MEK_A', 'U_MEK_B', 'U_BEASTBOSS_A']);
});

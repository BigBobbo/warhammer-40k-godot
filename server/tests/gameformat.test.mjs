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
const { createConverter, DEFAULT_DATA_SOURCE } = await import(new URL('../public/js/lib/gameformat.mjs', import.meta.url).href);
const { GAME_NAME_CANON_ENTRIES } = await import(new URL('../public/js/lib/canon.mjs', import.meta.url).href);
const { applyDataPatches } = await import(new URL('../public/js/lib/data-patches.mjs', import.meta.url).href);
const { pointsFor } = await import(new URL('../public/js/lib/dckit.mjs', import.meta.url).href);

// The browser builder patches the vendored dataset before use (store.js) —
// the Wahapedia codex overlay (WP-W3), codex detachments/enhancements. Test
// against the same effective dataset the real consumers see.
applyDataPatches(V.RAW_DATA);

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
  let strict = 0;
  const stale = [];
  for (const { file, army } of armyFiles()) {
    const { roster } = conv.gameToRoster(army, { name: file });
    const { army: out } = conv.rosterToGame(roster, { createdDate: army.faction.created_date });
    assert.ok(out, `${file}: conversion produced no army`);

    const origUnits = Object.values(army.units).filter(
      u => !(u.meta?.keywords ?? []).includes('UNKNOWN'));
    const outUnits = Object.values(out.units);
    assert.equal(outUnits.length, origUnits.length, `${file}: unit count`);

    // Datasheet facts can only round-trip for a file built from the data the
    // converter reads (faction.data_source). Files stamped with an older
    // dataset (space_marines.json and the tutorial rosters are still 1.0.19
    // snapshots — the tutorials stay pre-codex on purpose, PLAN follow-ups)
    // re-derive today's stats on conversion: structure only for those.
    if (army.faction?.data_source !== DEFAULT_DATA_SOURCE) {
      stale.push(`${file} (${army.faction?.data_source})`);
      continue;
    }
    strict++;

    // rosterToGame prices the Nth copy of a datasheet with the dataset's 11e
    // repeat pricing. Legacy files predate that and store first-copy prices
    // on every copy — accept a stored price that differs by exactly the
    // ordinal surcharge (enhancement costs cancel out of the delta).
    const fid = conv.factionIdForName(army.faction?.name ?? '');
    const ords = new Map();

    for (let i = 0; i < origUnits.length; i++) {
      const a = origUnits[i], b = outUnits[i];
      const label = `${file}/${a.meta.name}`;
      assert.equal(b.meta.name, a.meta.name, `${label}: order/name`);
      assert.equal(b.models.length, a.models.length, `${label}: model count`);
      assert.deepEqual(b.meta.stats, a.meta.stats, `${label}: stats`);
      let ordinalDelta = 0;
      let wargearDelta = 0;
      const found = fid ? conv.findUnitByName(fid, a.meta.name, [], file) : null;
      if (found) {
        const o = (ords.get(found.unit.id) ?? 0) + 1;
        ords.set(found.unit.id, o);
        ordinalDelta = pointsFor(found.unit, b.models.length, o) - pointsFor(found.unit, b.models.length);
        // Priced codex wargear (wargear_points, e.g. "per Killsaw 5"):
        // gameToRoster reconstructs a weapon that a file lists in meta.weapons
        // but not in a counted wargear line at 1x (it warns "reconstructed at
        // 1x"), and that guessed copy is priced. The stored file paid only for
        // its counted lines. Accept exactly that surcharge.
        const ru = roster.units[i];
        const counts = new Map((ru?.wargear ?? []).filter(w => w.ref.id).map(w => [w.ref.id, w.count]));
        wargearDelta = conv.wargearPointsFor(found.unit, found.factionId, counts) -
          conv.wargearPointsForLines(found.unit, a.meta.wargear ?? []);
      }
      const ok = [0, ordinalDelta, wargearDelta, ordinalDelta + wargearDelta]
        .some(d => b.meta.points === a.meta.points + d);
      assert.ok(ok, `${label}: points (stored ${a.meta.points}, out ${b.meta.points}, ` +
        `ordinal surcharge ${ordinalDelta}, 1x-reconstructed wargear ${wargearDelta})`);
      assert.equal(b.meta.is_warlord, a.meta.is_warlord, `${label}: warlord`);
      const an = new Set(a.meta.weapons.map(w => w.name));
      const bn = new Set(b.meta.weapons.map(w => w.name));
      assert.deepEqual([...bn].sort(), [...an].sort(), `${label}: weapon set`);
    }
    assert.equal(out.faction.detachment, army.faction.detachment, `${file}: detachment`);
    assert.equal(out.faction.schema, 2, `${file}: schema`);
  }
  assert.ok(strict >= 10, `strict round-trips: ${strict}`);
  console.log(`# round-trip: ${strict} files strict; structure only (older data_source): ${stale.join(', ') || 'none'}`);
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

  // Codex: Orks (11e) values (the builder's data is the game's since WP-W3).
  const bb = army.units.U_BEASTBOSS_A;
  assert.equal(bb.meta.is_warlord, true);
  assert.equal(bb.meta.points, 100, 'beastboss 85 + 15 enhancement');
  assert.deepEqual(bb.meta.enhancements, ["Headwoppa's Killchoppa"], 'canonical enhancement name');
  assert.ok(bb.meta.abilities.some(a => a.name === 'Waaagh!' && a.type === 'Faction'), 'army rule present');

  const bz = army.units.U_BOYZ_A;
  assert.equal(bz.meta.points, 85, 'codex Boyz x10');
  assert.equal(bz.models.length, 10);
  assert.equal(bz.models[0].wounds, 3, 'the Nob first with W3');
  assert.ok(bz.models.slice(1).every(m => m.wounds === 1), 'boys W1');
  assert.deepEqual(bz.meta.wargear,
    ['1x Kombi-skorcha', '1x Kustom Choppa', '9x Choppa', '9x Shoota', '9x Slugga'], 'wargear strings');
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

Beastboss (85 Points)
  • 1x Beast Snagga klaw and beastchoppa
  • 1x Shoota

BATTLELINE

Boyz (170 Points)
  • 19x Boy
  • 1x Nob
`;
  const { roster, report } = I.importText(text);
  assert.equal(roster.faction_id, 'orks', 'faction resolved');
  assert.equal(roster.units.length, 2);
  assert.ok(roster.units.every(u => u.ref.resolved), 'all units matched');
  const boyz = roster.units[1];
  // Codex: Orks Boyz are sold as 10 (85) or 20 (170): the 170 pts snap to 20.
  assert.equal(boyz.model_count, 20, `boyz snapped to 20 via 170pts (${report.warnings.join('; ')})`);
  const counts = S.countsOf(boyz);
  // The package's loadout allocator seats the Nob row at its minimum (1) and
  // fills the Boy row to its codex maximum (18).
  assert.equal(counts.get('slugga'), 18, 'slugga on every Boy');
  assert.equal(counts.get('choppa-boyz'), 18, 'choppa on every Boy');
  assert.equal(counts.get('kustom-choppa-boyz'), 1, "the Nob's kustom choppa");
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

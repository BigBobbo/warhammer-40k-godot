// Combat Calc backup / restore (pure part) and the server's transfer-code endpoint.
// Run: node --test server/tests/calc-backup.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const B = await import(new URL('../public/calc/backup.mjs', import.meta.url).href);
const here = dirname(fileURLToPath(import.meta.url));

function fakeStorage(init = {}) {
  const m = new Map(Object.entries(init));
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => { m.set(k, String(v)); }, removeItem: (k) => { m.delete(k); }, keys: () => [...m.keys()] };
}
const DEVICE = () => fakeStorage({
  w40k_calc_v1: JSON.stringify({ texts: { A: 'Gaelcon Awoo (2000 points)\nSpace Wolves', B: 'Calc Test Waaagh (1000 points)\nOrks' }, view: 'board' }),
  w40k_calc_lists_v1: JSON.stringify([{ name: 'Round 1' }, { name: 'Round 2' }]),
  w40k_calc_board_v1: JSON.stringify({ settings: {}, plans: { k1: { variants: [{ name: 'Main', steps: [] }, { name: 'Aggressive', steps: [] }], v: 0 }, k2: { steps: [] } } }),
  w40k_calc_mission_v1: JSON.stringify({ me: 'A', game: { round: 3, A: { hand: ['beacon'], used: [], primary: 12, secondary: 5 }, B: { hand: [], used: [], primary: 0, secondary: 0 } } }),
  something_else: 'not ours',
});

test('a backup holds every Combat Calc key and nothing else, and says what is in it', () => {
  const b = B.makeBackup(DEVICE(), { version: '1.94.0', now: new Date('2026-11-20T10:00:00Z') });
  assert.equal(b.format, 'combat-calc-backup');
  assert.deepEqual(Object.keys(b.data).sort(), ['w40k_calc_board_v1', 'w40k_calc_lists_v1', 'w40k_calc_mission_v1', 'w40k_calc_v1']);
  const d = B.describeBackup(b);
  assert.equal(d.ok, true);
  assert.deepEqual(d.counts, { lists: 2, library: 2, plans: 3, saved: 0, inGame: true });
  assert.match(d.summary, /2 loaded lists \(Gaelcon Awoo \(2000 points\) \/ Calc Test Waaagh \(1000 points\)\)/);
  assert.match(d.summary, /3 board plans/);
  assert.match(d.summary, /a game in progress \(round 3\)/);
  assert.equal(B.backupFileName(new Date(2026, 10, 5)), 'combat-calc-backup-2026-11-05.json');
});

test('restore replaces the device data, keeps one undo, and refuses anything that is not a backup', () => {
  const phone = DEVICE();
  const b = B.makeBackup(phone);
  const tablet = fakeStorage({ w40k_calc_v1: JSON.stringify({ texts: { A: 'Old list', B: '' } }), w40k_calc_saved_v1: JSON.stringify([{ id: 1 }]), other_app: 'x' });
  B.applyBackup(tablet, structuredClone(b));
  assert.equal(JSON.parse(tablet.getItem('w40k_calc_v1')).texts.A.split('\n')[0], 'Gaelcon Awoo (2000 points)');
  assert.equal(JSON.parse(tablet.getItem('w40k_calc_lists_v1')).length, 2);
  assert.equal(tablet.getItem('w40k_calc_saved_v1'), null, 'a key the backup does not hold is cleared');
  assert.equal(tablet.getItem('other_app'), 'x', 'other data on the device is untouched');
  // undo puts the old data back
  assert.equal(B.undoRestore(tablet), true);
  assert.equal(JSON.parse(tablet.getItem('w40k_calc_v1')).texts.A, 'Old list');
  assert.equal(JSON.parse(tablet.getItem('w40k_calc_saved_v1')).length, 1);
  assert.equal(tablet.getItem('w40k_calc_lists_v1'), null);
  assert.equal(B.undoRestore(tablet), false, 'only one undo');
  for (const bad of [null, {}, { format: 'x', data: {} }, { format: 'combat-calc-backup', data: {} }, { format: 'combat-calc-backup', formatVersion: 2, data: { w40k_calc_v1: {} } }]) {
    assert.equal(B.describeBackup(bad).ok, false, JSON.stringify(bad));
    assert.throws(() => B.applyBackup(fakeStorage(), bad));
  }
});

test('transfer codes: six characters without look-alikes', () => {
  assert.equal(B.normalizeCode(' abc-d2 3 '), 'ABCD23');
  assert.ok(B.CODE_RE.test('ABCD23'));
  assert.ok(!B.CODE_RE.test('ABCD10'), '0 and 1 are not used');
  assert.ok(!B.CODE_RE.test('ABCD2'));
});

// ---- the server endpoint (a real server on a spare port, its own database)
async function withServer(env, fn) {
  const port = 19100 + Math.floor(Math.random() * 400);
  const srv = spawn(process.execPath, [join(here, '..', 'relay-server.js')], { env: { ...process.env, PORT: String(port), DB_PATH: join(mkdtempSync(join(tmpdir(), 'calc-transfer-')), 't.db'), ...env }, stdio: 'ignore' });
  const base = `http://localhost:${port}`;
  try {
    for (let i = 0; i < 80; i++) { try { if ((await fetch(`${base}/api/health`)).ok) break; } catch { /* not up yet */ } await new Promise(r => setTimeout(r, 150)); }
    await fn(base);
  } finally { srv.kill(); }
}
const post = (base, body) => fetch(`${base}/api/calc-transfer`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

test('server: send a backup, get it back with the code (more than once), wrong and malformed codes fail', async () => {
  await withServer({}, async (base) => {
    const b = B.makeBackup(DEVICE(), { version: 't' });
    const res = await post(base, { data: b });
    assert.equal(res.status, 201);
    const { code, expires_in } = await res.json();
    assert.ok(B.CODE_RE.test(code), code);
    assert.equal(expires_in, 3600);
    for (const c of [code, code.toLowerCase()]) {
      const got = await fetch(`${base}/api/calc-transfer/${c}`);
      assert.equal(got.status, 200);
      assert.deepEqual((await got.json()).data, b);
    }
    const other = code.slice(0, 5) + (code[5] === 'A' ? 'B' : 'A');
    assert.equal((await fetch(`${base}/api/calc-transfer/${other}`)).status, 404);
    assert.equal((await fetch(`${base}/api/calc-transfer/NOPE`)).status, 400);
    assert.equal((await post(base, { data: { format: 'something-else', data: {} } })).status, 400, 'only Combat Calc backups are stored');
    assert.equal((await post(base, {})).status, 400);
    assert.equal((await fetch(`${base}/api/calc-transfer`, { method: 'DELETE' })).status, 405);
    // far too large: refused (the connection may be cut while it is still being sent)
    const big = { format: 'combat-calc-backup', data: { w40k_calc_v1: { texts: { A: 'x'.repeat(2500000), B: '' } } } };
    const tooBig = await post(base, { data: big }).then(r => r.status).catch(() => 413);
    assert.equal(tooBig, 413);
  });
});

test('server: a code stops working when its time is up', async () => {
  await withServer({ CALC_TRANSFER_TTL_MS: '400' }, async (base) => {
    const { code } = await (await post(base, { data: B.makeBackup(DEVICE()) })).json();
    assert.equal((await fetch(`${base}/api/calc-transfer/${code}`)).status, 200);
    await new Promise(r => setTimeout(r, 700));
    assert.equal((await fetch(`${base}/api/calc-transfer/${code}`)).status, 404);
  });
});

// Combat Calc browser tests, in parallel: tests/e2e-calc.mjs split into parts (E2E_SHARD=k/n), each part a process
// with a server and a browser of its own. Every check runs exactly once; the output of each part is kept in
// tests/screenshots/e2e-shard-<k>.log and its failures are listed at the end.
// Run: npm run test:e2e:calc:fast   (E2E_SHARDS=4 by default; a part more than cores makes the timing checks flaky)
import { spawn } from 'child_process';
import { createWriteStream, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const N = Math.max(1, Number(process.env.E2E_SHARDS) || 4);
const logDir = process.env.CALC_SHOTS ?? join(here, 'screenshots');
mkdirSync(logDir, { recursive: true });
const base = 19600 + Math.floor(Math.random() * 200);
const t0 = Date.now();

const runs = Array.from({ length: N }, (_, k) => new Promise((resolve) => {
  const log = createWriteStream(join(logDir, `e2e-shard-${k}.log`));
  const child = spawn(process.execPath, [join(here, 'e2e-calc.mjs')], { env: { ...process.env, E2E_SHARD: `${k}/${N}`, E2E_PORT: String(base + k * 3) }, stdio: ['ignore', 'pipe', 'pipe'] });
  const r = { k, ok: 0, fails: [], errors: [], code: null, secs: 0 };
  let buf = '';
  const take = (d) => {
    log.write(d);
    buf += d;
    const lines = buf.split('\n'); buf = lines.pop();
    for (const line of lines) {
      if (line.startsWith('  ok ')) r.ok++;
      else if (line.startsWith('  FAIL')) { r.fails.push(line.trim()); console.log(`[${k}] ${line.trim().slice(0, 600)}`); }
      else if (/^E2E error/.test(line)) { r.errors.push(line); console.log(`[${k}] ${line}`); }
      else if (/^  shard /.test(line)) console.log(line);
    }
  };
  child.stdout.on('data', take); child.stderr.on('data', take);
  child.on('exit', (code) => { r.code = code; r.secs = Math.round((Date.now() - t0) / 1000); log.end(); console.log(`[${k}] done in ${r.secs}s: ${r.ok} ok, ${r.fails.length} failed${code ? ` (exit ${code})` : ''}`); resolve(r); });
}));

const res = await Promise.all(runs);
const fails = res.reduce((a, r) => a + r.fails.length, 0), bad = res.filter(r => r.code !== 0);
console.log(`\n${res.reduce((a, r) => a + r.ok, 0)} checks ok, ${fails} failed, in ${Math.round((Date.now() - t0) / 1000)}s over ${N} parts (logs: ${logDir}/e2e-shard-*.log)`);
console.log(bad.length ? `FAILED: part${bad.length > 1 ? 's' : ''} ${bad.map(r => r.k).join(', ')}` : 'all checks passed');
process.exit(bad.length ? 1 : 0);

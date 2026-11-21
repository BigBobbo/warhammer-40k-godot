// Audit: is the weapon choice (public/calc/choose.mjs) the best one, for EVERY datasheet in the rules data?
//
// For each of the datasheets, in both phases, against each target of a panel (horde, marines,
// terminators, custodes, a character, a vehicle, a monster, a flyer): the app picks the unit's weapons and
// profiles; then every single change (leave a picked weapon out, force an unpicked one in) is simulated
// with more trials and another seed. A pick fails when a change is better by more than 3% (or 0.05
// wounds) beyond the noise of the simulation.
//
// Run:  cd server && node tests/audit-weapon-choice.mjs [--trials 6000] [--every 1] [--only id,id] [--context always|auto] [--out report.json]
// Takes several minutes for every datasheet (--every 10 checks each 10th). Exit code 1 when a pick fails.
// A sample of this runs with the unit tests (tests/calc-choose.test.mjs).
import { writeFileSync } from 'fs';
import { RAW, PANEL, unitOf, problemOf, auditProblem } from './helpers/choice-audit.mjs';

const arg = (name, def) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : def; };
const trials = Number(arg('trials', 6000)), every = Math.max(1, Number(arg('every', 1))), out = arg('out', null);
const only = arg('only', null)?.split(',');      // --only id1,id2: these datasheets
const context = arg('context', 'always');        // 'always' (the Attack tab) or 'auto' (the grid and the forecast odds)

const t0 = Date.now();
const tot = { datasheets: 0, cases: 0, withChoice: 0, decisions: 0, optionRuns: 0, failed: 0, worst: 0 };
const fails = [];
RAW.units.forEach((u, i) => {
  if (only ? !only.includes(u.id) : i % every) return;
  const cu = unitOf(u);
  if (!cu) return;
  tot.datasheets++;
  for (const phase of ['shooting', 'fight']) for (const t of PANEL) {
    const p = problemOf(cu, phase, t);
    if (!p) continue;
    tot.cases++;
    const r = auditProblem(p, { trials, context });
    if (!r.decisions) continue;
    tot.withChoice++; tot.decisions += r.decisions; tot.optionRuns += r.sims;
    if (r.worst > tot.worst) tot.worst = r.worst;
    if (r.fails.length) { tot.failed++; fails.push({ unit: u.id, faction: u.faction_id, phase, target: t.name, fails: r.fails }); }
  }
  if (tot.datasheets % 100 === 0) console.log(`  ${tot.datasheets} datasheets, ${tot.withChoice} cases with a choice, ${tot.failed} failed, ${Math.round((Date.now() - t0) / 1000)} s`);
});
tot.seconds = Math.round((Date.now() - t0) / 1000);
tot.worst = +tot.worst.toFixed(3);
console.log(JSON.stringify(tot));
for (const f of fails.slice(0, 40)) console.log('FAIL', f.unit, f.phase, '|', f.target, '|', f.fails.map(x => `${x.label}: picked ${x.picked}, alternative ${x.alternative} (allowed ${x.allow})`).join('; '));
if (out) writeFileSync(out, JSON.stringify({ tot, fails }, null, 1));
process.exit(fails.length ? 1 : 0);

// Runs the Monte Carlo off the UI thread.
//  - single scenario: a quick pass first so the phone shows a number at once,
//    then the full run;
//  - batch (matchup grid): one result per cell, posted as each finishes.
import { simulate, simulateChain } from './engine.mjs';
import { resolveScenario } from './choose.mjs';
import { forecast } from './forecast.mjs';

const QUICK = 3000;

self.onmessage = (ev) => {
  const { id, scenario, trials, batch, chain } = ev.data;
  if (ev.data.forecast) {
    // game VP forecast: the base plan, then each what-if
    try {
      const { base, variants } = ev.data.forecast;
      const out = { id, base: forecast(base), variants: (variants ?? []).map(v => ({ key: v.key, label: v.label, compare: !!v.compare, result: v.P ? forecast(v.P) : null })) };
      self.postMessage(out);
    } catch (err) { self.postMessage({ id, error: String(err?.stack ?? err) }); }
    return;
  }
  if (chain) {
    try { self.postMessage({ id, chain: true, result: simulateChain({ ...chain, trials: trials ?? 20000 }) }); }
    catch (err) { self.postMessage({ id, chain: true, error: String(err?.stack ?? err) }); }
    return;
  }
  if (batch) {
    for (const item of batch) {
      try {
        // a default matchup leaves its weapon choice to this thread (choose.mjs)
        const r = simulate({ ...resolveScenario(item.scenario), trials: trials ?? 2000 });
        // spread of the wounds dealt (the forecast combines several attackers on one target)
        let varW = 0;
        for (let i = 0; i < r.wounds.length; i++) varW += r.wounds[i] * (i - r.meanWounds) ** 2;
        self.postMessage({ id, key: item.key, result: {
          meanKills: r.meanKills, pWipe: r.pWipe, meanWounds: r.meanWounds, sdWounds: Math.sqrt(varW),
          totalModels: r.totalModels, totalWounds: r.totalWounds,
          meanPoints: r.meanPoints, totalPoints: r.totalPoints, groupKills: r.groupKills,
        } });
      } catch (err) {
        self.postMessage({ id, key: item.key, error: String(err?.message ?? err) });
      }
    }
    self.postMessage({ id, done: true });
    return;
  }
  try {
    const full = trials ?? 20000;
    if (full > QUICK * 2) {
      const quick = simulate({ ...scenario, trials: QUICK });
      self.postMessage({ id, final: false, result: quick });
    }
    const result = simulate({ ...scenario, trials: full });
    self.postMessage({ id, final: true, result });
  } catch (err) {
    self.postMessage({ id, final: true, error: String(err?.stack ?? err) });
  }
};

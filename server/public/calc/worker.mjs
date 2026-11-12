// Runs the Monte Carlo off the UI thread.
//  - single scenario: a quick pass first so the phone shows a number at once,
//    then the full run;
//  - batch (matchup grid): one result per cell, posted as each finishes.
import { simulate } from './engine.mjs';

const QUICK = 3000;

self.onmessage = (ev) => {
  const { id, scenario, trials, batch } = ev.data;
  if (batch) {
    for (const item of batch) {
      try {
        const r = simulate({ ...item.scenario, trials: trials ?? 2000 });
        self.postMessage({ id, key: item.key, result: {
          meanKills: r.meanKills, pWipe: r.pWipe, meanWounds: r.meanWounds,
          totalModels: r.totalModels, totalWounds: r.totalWounds,
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

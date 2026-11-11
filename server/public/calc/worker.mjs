// Runs the Monte Carlo off the UI thread: a quick pass first so the phone
// shows a number immediately, then the full run.
import { simulate } from './engine.mjs';

const QUICK = 3000;

self.onmessage = (ev) => {
  const { id, scenario, trials } = ev.data;
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

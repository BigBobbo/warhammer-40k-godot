// Matchup brief: one screen for the minutes after pairings — the missions and
// deployment this pairing gives, the forecast headline, which enemy units hurt
// you most (and from how far), your best answer to each of their big units,
// which secondary cards are dead, the units worth secondary VP, and the
// stratagems they can use in your turn. Everything comes from data the app
// already has (the lists, the calculator's unit-vs-unit results, the mission
// deck); nothing is typed in.
//
// app.js owns the shared state and calls in through initBrief().

import { boardUnit, armyIntel } from './adapter.mjs';
import { PRIMARIES } from './missions-11e.mjs';
import { boardContext } from './boardview.mjs';
import { layoutLetter, dispositionName } from './board.mjs';
import { matchupData, registerHost } from './missionview.mjs';
import { roundLabel } from './eventview.mjs';

let ctx = null;            // { state, esc, wide }
// sections fold on a phone (the threats stay open); app.js records the toggles in state.briefOpen
const fold = (key, title, body, dflt) => `<details class="more brief-sec" data-details="brief-${key}" ${(ctx.state.briefOpen?.[key] ?? dflt) ? 'open' : ''}><summary>${title}</summary>${body}</details>`;
const other = (p) => (p === 'A' ? 'B' : 'A');
const pct = (p) => `${Math.round(p * 100)}%`;

export function initBrief(c) {
  ctx = c;
  // re-drawn in place when the unit-vs-unit odds or the forecast arrive
  registerHost('brief-host', () => briefHtml());
}

/** How much of target t (of side Y) unit a (of side X) removes, by its better attack. */
function bite(pairs, X, a, Y, t) {
  const pr = pairs?.[`${X}:${a.key}`]?.[`${Y}:${t.key}`];
  if (!pr || !(pr.W > 0)) return null;
  const s = Math.min(1, (pr.sMu ?? 0) / pr.W), f = Math.min(1, (pr.fMu ?? 0) / pr.W);
  return f > s ? { p: f, how: 'in a fight', kill: pr.fight ?? 0 } : { p: s, how: 'shooting', kill: pr.shoot ?? 0 };
}
function reach(cu, army = null) {
  const u = boardUnit(cu, army);
  const maxR = u.ranges.length ? Math.max(...u.ranges) : 0;
  return [`M${u.move}"`, maxR ? `shoots ${maxR}" (reaches ${u.move + maxR}")` : null, u.melee ? `charge ${u.move + 7}" on average, ${u.move + 12}" at most` : null].filter(Boolean).join(' · ');
}

export function briefHtml() {
  const st = ctx.state, esc = ctx.esc;
  if (!st.armies.A || !st.armies.B) return '';
  const d = matchupData();
  const me = d.me, opp = other(me);
  const mine = st.armies[me], theirs = st.armies[opp];
  const bc = boardContext();
  const label = roundLabel();
  const r = d.result;
  const pWin = r ? (me === 'A' ? r.pWinA : r.pWinB) : null;
  const primary = (X) => { const name = bc.missions[X]; return `<b>${esc(name ?? '?')}</b>${PRIMARIES[name] ? ` — <span class="muted">${esc(PRIMARIES[name].text)}</span>` : ''}`; };

  let threats = '', answers = '';
  if (d.pairs) {
    // their units by the points of mine they remove with one attack on their best target
    const rows = theirs.units.map(e => {
      let best = null;
      for (const t of mine.units) {
        const b = bite(d.pairs, opp, e, me, t);
        if (!b) continue;
        const v = b.p * (t.points || 100);
        if (!best || v > best.v) best = { ...b, t, v };
      }
      return best ? { e, ...best } : null;
    }).filter(x => x && x.p >= 0.05).sort((a, b) => b.v - a.v).slice(0, 5);
    threats = rows.length ? `<table class="dist brief" id="brief-threats"><thead><tr><th>Their unit</th><th>hurts most</th><th></th></tr></thead><tbody>${rows.map(x =>
      `<tr><td><b>${esc(x.e.name)}</b><div class="tiny muted">${esc(reach(x.e, theirs))}</div></td><td>${esc(x.t.name)}<div class="tiny muted">${x.how}${x.kill >= 0.05 ? ` · destroys it ${pct(x.kill)}` : ''}</div></td><td><b>${pct(x.p)}</b></td></tr>`).join('')}</tbody></table>`
      : '<p class="muted small">None of their units removes 5% of one of yours in one attack.</p>';
    // their most valuable units and my two best tools against each
    const big = [...theirs.units].sort((a, b) => (b.points || 0) - (a.points || 0)).slice(0, 5);
    answers = `<table class="dist brief" id="brief-answers"><thead><tr><th>Their unit</th><th>your best attack</th><th></th></tr></thead><tbody>${big.map(t => {
      const opts = mine.units.map(a => ({ a, b: bite(d.pairs, me, a, opp, t) })).filter(x => x.b && x.b.p > 0).sort((x, y) => y.b.p - x.b.p).slice(0, 2);
      return `<tr><td><b>${esc(t.name)}</b><div class="tiny muted">${t.points ? `${t.points} pts · ` : ''}${t.models} models</div></td>
        <td>${opts.length ? opts.map(o => `${esc(o.a.name)} <span class="tiny muted">${o.b.how}</span>`).join('<br>') : '<span class="muted">nothing reaches it on paper</span>'}</td>
        <td>${opts.map(o => `<b>${pct(o.b.p)}</b>`).join('<br>')}</td></tr>`;
    }).join('')}</tbody></table>`;
  }
  const dead = { mine: d.dead(me), theirs: d.dead(opp) };
  const wideNow = ctx.wide?.() ?? false;
  const watch = armyIntel(theirs).stratagems.filter(s => /opponent/i.test(s.turn ?? '') && !s.missing).slice(0, 8);
  return `<div class="card brief-card" id="brief">
      <div class="row"><div class="title grow">Matchup brief</div>${label ? `<span class="pill good" id="brief-round">${esc(label)}</span>` : `<span class="pill">Layout ${bc.layout ? layoutLetter(bc.layout.variant) : '?'}</span>`}</div>
      <div class="small" style="margin-top:6px"><b style="color:var(--side-${me.toLowerCase()})">You</b> · ${esc(mine.faction)} · ${esc(dispositionName(me === 'A' ? bc.dispA : bc.dispB))}: ${primary(me)}</div>
      <div class="small" style="margin-top:4px"><b style="color:var(--side-${opp.toLowerCase()})">They</b> · ${esc(theirs.faction)} · ${esc(dispositionName(opp === 'A' ? bc.dispA : bc.dispB))}: ${primary(opp)}</div>
      <div class="small muted" style="margin-top:4px" id="brief-deploy">${esc(bc.deployment?.name ?? '')} · Layout ${bc.layout ? layoutLetter(bc.layout.variant) : '?'} · first turn is rolled after deployment</div>
      <button class="fc-mini" style="margin-top:8px" data-action="view" data-value="mission" id="brief-forecast">${r
        ? `<span><b>${pct(pWin)}</b> you win</span><span><b>${Math.round(r[me].mean)}</b> – <b>${Math.round(r[opp].mean)}</b> VP</span><span class="muted">forecast →</span>`
        : `<span class="muted">${d.busy ? 'Working out the forecast…' : 'Forecast →'}</span>`}</button>
      <div class="row" style="gap:6px;margin-top:8px"><button class="btn grow" data-action="view" data-value="board">Board →</button><button class="btn grow" data-action="brief-grid">📊 Every unit vs every unit</button></div>
    </div>
    <div class="lay2 brief"><div class="col">
      <section class="section">${fold('threats', 'Their biggest threats', `${d.pairs ? threats : '<p class="muted small">Working out unit-vs-unit odds…</p>'}
        <div class="tiny muted">Share of your unit removed by one attack with default rules (no stratagems), each of their units on the target it hurts most.</div>`, true)}</section>
      <section class="section">${fold('answers', 'Your best answers', d.pairs ? answers : '<p class="muted small">Working out unit-vs-unit odds…</p>', wideNow)}</section>
    </div><div class="col">
      <section class="section">${fold('cards', `Secondary cards — ${dead.mine.length ? `${dead.mine.length} dead for you` : 'none dead for you'}`, `
        <div class="small">${dead.mine.length ? `Dead for you (no targets): <b>${esc(dead.mine.join(', '))}</b>.` : 'No dead cards for you.'} ${dead.theirs.length ? `Dead for them: <b>${esc(dead.theirs.join(', '))}</b>.` : 'None dead for them.'}</div>
        <div class="lab tiny muted" style="margin-top:8px">Their units worth secondary VP to you</div>${d.hitList(me)}`, wideNow)}</section>
      ${watch.length ? `<section class="section">${fold('watch', `They can do this in your turn (${watch.length})`, watch.map(s =>
        `<div class="ability"><b>${esc(s.name)}</b> <span class="muted tiny">${s.cp}CP · ${esc(s.phase ?? '')}</span><div class="muted">${esc(s.when ?? '')}${s.effect ? ` — ${esc(s.effect.length > 190 ? `${s.effect.slice(0, 190)}…` : s.effect)}` : ''}</div></div>`).join(''), wideNow)}</section>` : ''}
    </div></div>`;
}

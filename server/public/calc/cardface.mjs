// A secondary mission card drawn as a card (Mission → Cards, the hand on Play): the name, Tactical / Fixed,
// "When drawn", when it scores, each scoring line with its VP, and the Fixed version. The words are the app's
// summary of the card (missions-11e.mjs SECONDARIES), not the printed text. Pure: tests/calc-cardface.test.mjs.

const KIND = { kill: ['☠', 'Destroy'], hold: ['⚑', 'Objectives'], position: ['⌖', 'Positions'], action: ['⚙', 'Action'] };
const WHEN = { own: 'End of your turn', opp: 'End of your opponent’s turn', any: 'End of either player’s turn' };
const cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);

/**
 * The scoring lines of a card's text: [{ vp, text }] (vp null: a line without its own VP), and an intro line
 * (the part before a ':' that the VP lines share), e.g. "Units wholly in table quarters …: 3 VP for three
 * quarters, 5 VP for four." -> intro "Units wholly in table quarters …", lines 3 "for three quarters", 5 "for four".
 */
export function scoreLines(text) {
  let t = String(text ?? '').trim();
  let intro = null;
  // a lead-in that ends with ':' and is followed by VP amounts ("End of opponent's turn: 3 VP if …")
  const colon = /^([^:]{3,}?):\s+(?=.*\d+\s*VP)/.exec(t);
  if (colon && !/\d+\s*VP/.test(colon[1])) { intro = colon[1]; t = t.slice(colon[0].length); }
  // split at ';' and at ', N VP' / ', or N VP' / ' or N VP' (a new amount starts a new line)
  const parts = t.split(/;\s*|,\s*(?:or\s+)?(?=\d+\s*VP)|\s+or\s+(?=\d+\s*VP)|,\s*(?=\+\d+\s)/).map(s => s.trim()).filter(Boolean);
  const lines = parts.map((p) => {
    const m = /^(\+?\d+)\s*VP\b[\s,]*(.*)$/i.exec(p) ?? /^(\+\d+)\s+(.*)$/.exec(p);
    if (m) return { vp: m[1], text: cap(m[2].replace(/\.$/, '')) };
    const inner = /(\+?\d+)\s*VP/.exec(p);
    return { vp: inner ? inner[1] : null, text: cap(p.replace(/\.$/, '')) };
  });
  // one amount and nothing after it ("…: 5 VP."): the lead-in is the line
  if (intro && lines.length === 1 && !lines[0].text) { lines[0].text = cap(intro); intro = null; }
  return { intro: intro ? cap(intro) : null, lines };
}

/** The card as HTML. opts: { esc, fixedMax, tactical: true when Tactical play is in use, foot: extra HTML } */
export function cardFace(c, { esc = (s) => String(s), foot = '' } = {}) {
  const [icon, kind] = KIND[c.kind] ?? ['•', 'Mission'];
  const sc = scoreLines(c.text);
  // the per-game cap is said once, under the lines
  const fx = c.fixedText ? scoreLines(c.fixedText.replace(/\s*\(max \d+ per game\)/, '')) : null;
  const row = (l) => `<div class="cf-line">${l.vp ? `<span class="cf-vp">${esc(l.vp)}<small>VP</small></span>` : '<span class="cf-vp none"></span>'}<span>${esc(l.text)}</span></div>`;
  return `<div class="cf cf-${esc(c.kind ?? 'other')}" data-cardface="${esc(c.id)}">
    <div class="cf-top"><span class="cf-kind">${icon} ${esc(kind)}</span><span class="cf-type">Secondary mission</span></div>
    <div class="cf-name">${esc(c.name)}</div>
    <div class="cf-tags"><span class="cf-tag">Tactical</span>${c.fixed ? '<span class="cf-tag fixed">Fixed</span>' : ''}${c.minRound ? `<span class="cf-tag">From round ${c.minRound}</span>` : ''}</div>
    ${c.drawn ? `<div class="cf-box"><div class="cf-h">When drawn</div><div>${esc(c.drawn)}</div></div>` : ''}
    <div class="cf-sec"><div class="cf-h">${c.fixed ? 'Tactical · ' : ''}${esc(WHEN[c.timing] ?? 'Scoring')}</div>
      ${sc.intro ? `<div class="cf-intro">${esc(sc.intro)}</div>` : ''}${sc.lines.map(row).join('')}
      <div class="cf-max">Up to ${c.max ?? 5} VP each time it scores</div></div>
    ${fx ? `<div class="cf-sec cf-fixed"><div class="cf-h">Fixed mission</div>${fx.intro ? `<div class="cf-intro">${esc(fx.intro)}</div>` : ''}${fx.lines.map(row).join('')}
      <div class="cf-max">Up to ${c.fixedMax ?? 20} VP per game</div></div>` : ''}
    ${foot ? `<div class="cf-foot">${foot}</div>` : ''}</div>`;
}

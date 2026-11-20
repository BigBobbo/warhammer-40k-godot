// Splitting pasted text into army lists (pure; tests/calc-event.test.mjs).

const SIZE_LINE = /^(combat patrol|incursion|strike force|onslaught)\s*\(\s*\d[\d,.]*\s*points?\s*\)/i;
const HEAD_LINE = /\(\s*\d[\d,.]*\s*(points|pts)\s*\)\s*$/i;
const BULLET = /^\s*(?:[•◦▪·*-]|\d+x\b)/i;

/**
 * Split pasted text into lists. A line of ---- / ==== separates lists; without
 * one, a GW-app list starts at "<name> (N points)" when a battle-size line
 * ("Strike Force (2000 points)") follows within a few lines with no unit
 * wargear in between. Anything else is one list.
 */
export function splitLists(text) {
  const src = String(text ?? '').replace(/\r/g, '');
  const bySep = src.split(/^\s*[-=_*]{4,}\s*$/m).map(s => s.trim()).filter(Boolean);
  if (bySep.length > 1) return bySep.flatMap(splitLists);
  const lines = src.split('\n');
  const starts = [];
  for (let i = 0; i < lines.length; i++) {
    if (!HEAD_LINE.test(lines[i]) || SIZE_LINE.test(lines[i].trim()) || BULLET.test(lines[i])) continue;
    let seen = 0;
    for (let j = i + 1; j < lines.length && seen < 8; j++) {
      const t = lines[j].trim();
      if (!t) continue;
      seen++;
      if (SIZE_LINE.test(t)) { starts.push(i); break; }
      if (BULLET.test(lines[j]) || HEAD_LINE.test(t)) break;
    }
  }
  if (starts.length < 2) return src.trim() ? [src.trim()] : [];
  return starts.map((s, k) => lines.slice(s, starts[k + 1] ?? lines.length).join('\n').trim()).filter(Boolean);
}

// 11e enhancement bearer rules for the army builder (WP-C46).
//
// Mirrors 40k/scripts/codex/EnhancementRules11e.gd so the builder offers an
// enhancement only to the units the game will accept it on:
//   - the printed restriction is the first sentence of the record's
//     rules_text: "<keywords / datasheet name> model only." or
//     "... unit only (excluding <X> units).";
//   - the phrase must be fully consumed by the unit's keywords + datasheet
//     name (longest match first, case-insensitive); "a/b" words are
//     alternatives ("Adeptus Custodes Infantry/Mounted");
//   - a normal enhancement needs a non-EPIC HERO CHARACTER; an Upgrade
//     (upgrade_tag) "can be given to non-CHARACTER units" (core rules, Select
//     Enhancements) — it is NOT limited to them: any non-EPIC HERO unit its
//     printed restriction allows (e.g. the Ork "Big Mek with Shokk Attack Gun
//     model only" Upgrades), on up to three units ("(one per army)": one).
// Records without rules_text (the dataset's superseded entries) carry no
// printed restriction.
//
// Environment-free (no DOM / fs) so node tests can import it.

const RESTRICTION_RE = /^(.+?)\s+(model|unit)s?\s+only(?:\s*\(excluding\s+(.+?)\s+units?\))?\s*\./i;

const fold = (s) => String(s ?? '').replace(/ /g, ' ').replace(/[‘’]/g, "'").trim();

/** {phrase, scope, excluding} or null. */
export function parseRestriction(rec) {
  const text = fold(rec?.rules_text);
  if (!text) return null;
  const m = RESTRICTION_RE.exec(text);
  if (!m) return null;
  return { phrase: m[1].trim(), scope: m[2].toLowerCase(), excluding: (m[3] ?? '').trim() };
}

/** Upper-cased candidate terms (keywords + datasheet name), longest first. */
export function unitTerms({ name = '', keywords = [] } = {}) {
  const terms = new Set();
  for (const k of keywords) {
    const t = fold(k).toUpperCase();
    if (t) terms.add(t);
  }
  const n = fold(name).toUpperCase();
  if (n) terms.add(n);
  return [...terms].sort((a, b) => b.length - a.length);
}

// "/" separates alternative KEYWORDS, and a keyword can be several words:
// "Big Mek/Warboss Infantry" is (BIG MEK or WARBOSS) INFANTRY, "Big Mek/Mek"
// is BIG MEK or MEK (Codex: Orks — WP-O5). The first alternative keeps the
// words before the slash; each later one may also start fresh (drop any of
// those preceding words), so a multi-word left keyword does not glue its
// first words onto the right alternative ("Big Warboss").
function expandAlternatives(phrase) {
  let out = [[]];
  for (const word of phrase.split(/\s+/).filter(Boolean)) {
    const alts = word.split('/').filter(Boolean);
    const next = [];
    for (const prefix of out) {
      alts.forEach((a, ai) => {
        next.push([...prefix, a]);
        if (ai > 0) for (let d = 1; d <= prefix.length; d++) next.push([...prefix.slice(d), a]);
      });
    }
    out = next;
  }
  return [...new Set(out.map(ws => ws.join(' ')))];
}

function phraseMatches(phrase, terms) {
  let rest = fold(phrase).toUpperCase();
  while (rest) {
    const t = terms.find(t => rest === t || rest.startsWith(`${t} `));
    if (!t) return false;
    rest = rest.slice(t.length).trim();
  }
  return true;
}

/** '' when the unit may bear the enhancement, else the reason. */
export function bearerViolation(rec, unit) {
  const r = parseRestriction(rec);
  if (!r) return '';
  const terms = unitTerms(unit);
  if (!expandAlternatives(r.phrase).some(p => phraseMatches(p, terms))) return `${r.phrase} ${r.scope} only`;
  if (r.excluding && expandAlternatives(r.excluding).some(p => phraseMatches(p, terms))) return `excluding ${r.excluding} units`;
  return '';
}

/** A record from a published codex (it carries the printed rules text). The
 * bundle's provisional pre-codex records keep the builder's old behaviour:
 * non-EPIC CHARACTERs only, one per army — their upgrade_tag values are not
 * reliable (e.g. the provisional Blitz Brigade rows are all tagged). */
export const isCodexRecord = (rec) => !!fold(rec?.rules_text);
export const isUpgrade = (rec) => isCodexRecord(rec) && !!rec?.upgrade_tag;
export const onePerArmy = (rec) => /\(one per army\)/i.test(String(rec?.name ?? ''));
/** How many units may carry it: 1, or 3 for an Upgrade (1 if "(one per army)"). */
export const maxHolders = (rec) => (isUpgrade(rec) ? (onePerArmy(rec) ? 1 : 3) : 1);

/**
 * Can this unit take this enhancement at all (ignoring who else holds it)?
 * unit: { name, keywords } (keywords include faction keywords).
 * Returns { ok, reason }.
 */
export function canBear(rec, unit) {
  const kw = (unit?.keywords ?? []).map(k => fold(k).toUpperCase());
  const isChar = kw.includes('CHARACTER');
  const isEpic = kw.includes('EPIC HERO');
  // EPIC HEROes take no enhancement (Upgrades included); a normal enhancement
  // needs a CHARACTER; an Upgrade may go on a CHARACTER or a non-CHARACTER
  // unit — its printed restriction (below) decides (WP-C46 ruling).
  if (isEpic) return { ok: false, reason: 'not on an EPIC HERO' };
  if (!isUpgrade(rec) && !isChar) return { ok: false, reason: 'CHARACTER models only' };
  const why = bearerViolation(rec, unit);
  return why ? { ok: false, reason: why } : { ok: true, reason: '' };
}

// Base-to-base measuring on the board or a table photo (boardview "📐 Bases" mode). Pure:
// tests/calc-measure.test.mjs.
//
// 40k measures between the closest points of two bases (01.04); a marker is a base of `mm` millimetres (round),
// or a point (mm 0, e.g. a hull edge or an objective centre). On a photo, how sure the number is depends on how
// many photo pixels cover an inch where you tapped (photo.localScale): a tap and the warped photo are each good to
// about a pixel, and the corners you tapped set the scale.

export const BASE_SIZES = [0, 25, 28.5, 32, 40, 50, 60, 90];
const MM = 1 / 25.4;

/** a, b: { x, y, mm } (inches, mm) -> { centre, edge, p, q } (edge: closest points; p, q: where the line meets the bases) */
export function baseToBase(a, b) {
  const ra = (a.mm || 0) * MM / 2, rb = (b.mm || 0) * MM / 2;
  const d = Math.hypot(b.x - a.x, b.y - a.y);
  const ux = d ? (b.x - a.x) / d : 1, uy = d ? (b.y - a.y) / d : 0;
  const edge = Math.max(0, d - ra - rb);
  return { centre: d, edge, p: [a.x + ux * ra, a.y + uy * ra], q: [b.x - ux * rb, b.y - uy * rb] };
}

/**
 * About how far off a photo measurement can be (inches), from the photo pixels per inch at each end (sA, sB) and
 * at the table corners (sCorner, the lowest). Each end: ~1.5 photo px to line a circle up with a base, plus the
 * map's 1/16" grain; the corner taps (~1.5 px each) scale the whole distance by up to their share of the table.
 * Not a guarantee: a photo taken at a low angle, a mat that is not flat or a lens that bends lines all add to it.
 */
export function measureError({ sA, sB, sCorner, dist, tableIn = 52 }) {
  const end = (s) => 1.5 / Math.max(1, s) + 1 / 16;
  const scale = (1.5 / Math.max(1, sCorner)) * Math.SQRT2 / tableIn; // relative error of the scale
  return Math.hypot(end(sA), end(sB)) + dist * scale;
}

/** "9.4"" / "under 0.1"" */
export const fmtIn = (v) => (v < 0.05 ? 'touching' : `${v.toFixed(1)}"`);

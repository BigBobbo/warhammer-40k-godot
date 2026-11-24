// Read-only share links: the two lists, the attack set-up and the board plan on screen, compressed into the link
// itself (#s=...). Nothing is stored on the server; whoever opens the link sees it without it touching their own
// lists and plans (app.js: state.viewing). Pure: tests/calc-sharelink.test.mjs.

export const SHARE_FORMAT = 'combat-calc-share';
export const SHARE_PREFIX = '#s=';

const b64url = (bytes) => {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const unb64url = (str) => {
  const s = atob(str.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((str.length + 3) % 4));
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
};
async function pipe(bytes, stream) {
  const res = new Response(new Blob([bytes]).stream().pipeThrough(stream));
  return new Uint8Array(await res.arrayBuffer());
}

/** payload -> the part of the link after '#s=' (deflate + base64url). */
export async function packShare(payload) {
  const json = JSON.stringify({ f: SHARE_FORMAT, v: 1, ...payload });
  return b64url(await pipe(new TextEncoder().encode(json), new CompressionStream('deflate-raw')));
}

/** The part after '#s=' -> payload; throws a readable error for a broken or foreign link. */
export async function unpackShare(code) {
  let obj;
  try {
    obj = JSON.parse(new TextDecoder().decode(await pipe(unb64url(String(code ?? '').trim()), new DecompressionStream('deflate-raw'))));
  } catch { throw new Error('This link is incomplete or damaged (it may have been cut short when it was copied).'); }
  if (obj?.f !== SHARE_FORMAT) throw new Error('This is not a Combat Calc share link.');
  if (typeof obj.texts?.A !== 'string' || typeof obj.texts?.B !== 'string') throw new Error('This link has no army lists in it.');
  return obj;
}

/** What the link shows, in a few words: "Space Wolves vs Orks — board plan". */
export function shareTitle(p) {
  const what = p.view === 'board' ? 'board plan' : p.view === 'attack' ? 'attack' : 'lists';
  return `${p.names?.A || 'Army A'} vs ${p.names?.B || 'Army B'} — ${what}`;
}

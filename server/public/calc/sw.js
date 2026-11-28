// Offline support for the combat calculator. Each app version has a cache of its own (the name carries the
// version: version.mjs), filled completely when the service worker of that version installs. Every file of the
// app is then served from that one cache, so a page always runs ONE version: the header, the Board, the data.
//
// Before 1.144 files were fetched from the network one by one, each falling back to its cached copy after 3.5 s.
// After a release, on a slow connection, the small files arrived new and a large one (the Board) came from the old
// cache: the header showed the new version over the old Board. Now a new release is picked up as a whole: the
// browser checks sw.js on every load, the new worker downloads the whole set, takes over, and the page reloads
// into it (app.js: at once if it has not been touched yet, else a "new version" bar).
const CACHE = 'w40k-calc-1.149.0';
const SHELL = [
  './', './index.html', './calc.css', './app.js', './adapter.mjs', './engine.mjs', './choose.mjs', './phasesheet.mjs', './rulesnote.mjs', './games.mjs', './plantree.mjs', './gamelists.mjs', './cardface.mjs', './gamestats.mjs', './droporder.mjs', './sharelink.mjs', './gapfinder.mjs', './printsheet.mjs', './measure.mjs', './ar-test.html', './arview.mjs', './armath.mjs', './worker.mjs', './rules.mjs', './stratagems-11e.mjs', './board.mjs', './boardview.mjs', './terrain-11e.mjs', './photo.mjs', './photoview.mjs', './sight.mjs', './missions-11e.mjs', './forecast.mjs', './missionview.mjs', './planeval.mjs', './nextturn.mjs', './playout.mjs', './paths.mjs', './advise.mjs', './version.mjs', './backup.mjs', './eventview.mjs', './briefview.mjs', './lists.mjs', './playtools.mjs', './errata-data.mjs',
  './manifest.webmanifest', './icon-192.png', './icon-512.png',
  '/js/builder/store.js', '/js/builder/importers.js', '/js/builder/api.js',
  '/js/lib/canon.mjs', '/js/lib/data-patches.mjs', '/js/lib/dckit.mjs', '/js/lib/detachment-rules.mjs',
  '/js/lib/enhancement-rules.mjs', '/js/lib/gameformat.mjs', '/js/lib/codex-11e-datasheets.mjs',
  '/js/lib/custodes-codex-11e-data.mjs', '/js/lib/orks-codex-11e-data.mjs', '/js/lib/sm-codex-11e-data.mjs',
  '/js/vendor/40kdc-data.mjs',
];

self.addEventListener('install', (ev) => {
  // (cache: 'reload': from the server, never the browser's HTTP cache - the set must be this version's)
  ev.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL.map(u => new Request(u, { cache: 'reload' })))).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (ev) => {
  ev.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k.startsWith('w40k-calc-') && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (ev) => {
  const req = ev.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/')) return;
  ev.respondWith(caches.open(CACHE).then(async (cache) => {
    // this version's own copy first: every file of the page then belongs to one version
    const cached = await cache.match(req, { ignoreSearch: true });
    if (cached) return cached;
    // a file that is not part of the shell (or a first visit still installing): from the network, kept for offline
    const res = await fetch(req);
    if (res.ok) cache.put(req, res.clone());
    return res;
  }));
});

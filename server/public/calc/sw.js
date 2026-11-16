// Offline support for the combat calculator: the app shell, the dataset
// bundle and the importer modules are cached on install; everything else
// same-origin (except /api) is served stale-while-revalidate.
const CACHE = 'w40k-calc-v11';
const SHELL = [
  './', './index.html', './calc.css', './app.js', './adapter.mjs', './engine.mjs', './worker.mjs', './rules.mjs', './stratagems-11e.mjs', './board.mjs', './boardview.mjs', './terrain-11e.mjs', './photo.mjs', './photoview.mjs', './sight.mjs',
  './manifest.webmanifest', './icon-192.png', './icon-512.png',
  '/js/builder/store.js', '/js/builder/importers.js',
  '/js/lib/canon.mjs', '/js/lib/data-patches.mjs', '/js/lib/dckit.mjs', '/js/lib/detachment-rules.mjs',
  '/js/lib/enhancement-rules.mjs', '/js/lib/gameformat.mjs', '/js/lib/codex-11e-datasheets.mjs',
  '/js/lib/custodes-codex-11e-data.mjs', '/js/lib/orks-codex-11e-data.mjs', '/js/lib/sm-codex-11e-data.mjs',
  '/js/vendor/40kdc-data.mjs',
];

self.addEventListener('install', (ev) => {
  ev.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
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
    const cached = await cache.match(req, { ignoreSearch: true });
    const network = fetch(req).then((res) => {
      if (res.ok) cache.put(req, res.clone());
      return res;
    }).catch(() => cached);
    return cached ?? network;
  }));
});

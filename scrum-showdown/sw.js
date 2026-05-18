/* Scrum Showdown service worker — versioned, cache-first app shell.
 *
 * FORCE-UPDATE LEVER: bump CACHE_VERSION (keep it in lockstep with
 * src/version.js → APP_VERSION). A new cache name makes install precache
 * fresh files and activate delete every old cache, so testers never get
 * stuck on a stale shell. skipWaiting + clients.claim make the new worker
 * take over on the very next load. See docs/PILOT.md. */
const CACHE_VERSION = '0.2.0+4';
const CACHE = `scrum-showdown-shell-v${CACHE_VERSION}`;

const SHELL = [
  './',
  './index.html',
  './app.css',
  './manifest.webmanifest',
  './icon.svg',
  './src/app.js',
  './src/version.js',
  './src/core/storage.js',
  './src/core/roster.js',
  './src/core/selection.js',
  './src/core/deck.js',
  './src/core/board.js',
  './src/core/glyphs.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  // Cache-first for the shell; fall back to network, then (for page
  // navigations on flaky wifi) the cached index.html so it never
  // white-screens.
  event.respondWith(
    caches.match(request).then(
      (hit) =>
        hit ||
        fetch(request)
          .then((res) => {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(request, copy)).catch(() => {});
            return res;
          })
          .catch(() => {
            if (request.mode === 'navigate') return caches.match('./index.html');
            return Response.error();
          }),
    ),
  );
});

// NaviVibe service worker: an app-shell cache so the PWA starts offline (to its
// sign-in / "can't reach the server" screens) and is installable.
//
// It never pins an old build:
// * It is registered as sw.js?v=<build id> (flutter_bootstrap.js), so every
//   deploy installs a new worker with its own cache, and the old caches are
//   deleted when it takes over.
// * Page loads and app code are network first; the cache is only the offline
//   fallback. A new deploy shows up on the next load, and an open page learns
//   about it from flutter_bootstrap.js (the "New version · Reload" prompt).
// * Engine and fonts (canvaskit/, assets/) are cache first per build, refreshed
//   in the background.
// * API, stream and cover requests (/rest, /auth, /api, /share, /ws, and
//   every other host) are never touched.
'use strict';

const BUILD = new URL(self.location.href).searchParams.get('v') || 'dev';
const PREFIX = 'navivibe-shell-';
const CACHE = PREFIX + BUILD;
const SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'main.dart.mjs',
  'main.dart.wasm',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
];
const NEVER = [/\/rest\//, /\/auth\//, /\/api\//, /\/share\//, /\/ws\//];
const STATIC = [/\/canvaskit\//, /\/assets\//, /\/icons\//, /sqlite3\.wasm$/, /drift_worker\.js$/];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Past the HTTP cache, so the shell is this build's. One missing file (a
    // JS-only build has no main.dart.wasm) must not stop the install.
    await Promise.all(SHELL.map((url) =>
      fetch(url, { cache: 'reload' })
        .then((res) => (res.ok ? cache.put(url, res) : undefined))
        .catch(() => {})));
    // Taking over at once is safe: app code is network first, so a page the
    // old worker served keeps running and the next load gets the new build.
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith(PREFIX) && key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  if (NEVER.some((re) => re.test(url.pathname))) return;
  if (req.headers.has('range')) return; // media byte ranges: let the browser handle them

  if (STATIC.some((re) => re.test(url.pathname))) {
    event.respondWith(staleWhileRevalidate(req));
  } else {
    event.respondWith(networkFirst(req));
  }
});

async function networkFirst(req) {
  const cache = await caches.open(CACHE);
  try {
    // no-cache: always ask the server (a 304 is cheap), never a stale HTTP copy.
    // A navigation Request can't be re-made with options, so go by its URL.
    const res = await fetch(req.mode === 'navigate'
      ? new Request(req.url, { cache: 'no-cache', credentials: 'same-origin' })
      : new Request(req, { cache: 'no-cache' }));
    if (res.ok) cache.put(req, res.clone());
    return res;
  } catch (e) {
    const hit = await cache.match(req, { ignoreSearch: true }) ||
      (req.mode === 'navigate' ? await cache.match('index.html') : undefined);
    if (hit) return hit;
    throw e;
  }
}

async function staleWhileRevalidate(req) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(req);
  const fresh = fetch(req).then((res) => {
    if (res.ok) cache.put(req, res.clone());
    return res;
  }).catch(() => hit);
  return hit || fresh;
}

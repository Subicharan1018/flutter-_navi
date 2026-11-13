// NaviVibe service worker: caches the app shell so the PWA starts offline (to
// its sign-in / "can't reach the server" screens) and is installable.
//
// * Same-origin app files only. API, stream and cover requests (/rest, /auth,
//   /api, /share, and every other host) always go to the network, untouched.
// * Page loads and the app code: network first, cache as fallback, so a new
//   deploy shows up on the next load.
// * Engine and fonts (canvaskit/, assets/): cache first, refreshed in the
//   background.
'use strict';

const CACHE = 'navivibe-shell-v1';
const SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
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
    // One missing file (a wasm-only build has no main.dart.js) must not stop
    // the worker from installing.
    await Promise.all(SHELL.map((url) => cache.add(url).catch(() => {})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key !== CACHE) await caches.delete(key);
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
    const res = await fetch(req);
    if (res.ok) cache.put(req, res.clone());
    return res;
  } catch (e) {
    const hit = await cache.match(req) ||
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

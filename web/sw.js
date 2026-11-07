// Network first so new content shows up as soon as the phone is online;
// the cache keeps everything working offline.
// The public site has only content.enc; local dev has only content.json. Each file is cached on
// its own so a missing one doesn't stop the rest.
const CACHE = 'coach-v2';
const FILES = [
    './',
    'index.html',
    'app.css',
    'app.js',
    'content.enc',
    'content.json',
    'manifest.webmanifest',
    'icons/icon-192.png',
    'icons/icon-512.png',
    'icons/maskable-512.png',
];

self.addEventListener('install', (event) => {
    event.waitUntil(caches.open(CACHE)
        .then((cache) => Promise.all(FILES.map((f) => cache.add(f).catch(() => {}))))
        .then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys()
            .then((keys) => Promise.all(keys.filter((k) => k.startsWith('coach-') && k !== CACHE).map((k) => caches.delete(k))))
            .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
    const { request } = event;
    if (request.method !== 'GET' || new URL(request.url).origin !== location.origin) return;
    event.respondWith(
        fetch(request)
            .then((response) => {
                if (response.ok) {
                    const copy = response.clone();
                    caches.open(CACHE).then((cache) => cache.put(request, copy));
                }
                return response;
            })
            .catch(() => caches.match(request, { ignoreSearch: true }).then((hit) => hit ?? Response.error())));
});

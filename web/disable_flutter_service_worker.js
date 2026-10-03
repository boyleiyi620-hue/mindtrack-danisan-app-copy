const CACHE_NAME = 'mindtrack-static-v6';
const STATIC_FILE = /\.(?:js|wasm|json|png|jpg|jpeg|gif|svg|ico|otf|ttf|woff2?)$/i;

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) =>
        Promise.all(
          names
            .filter((name) => name.startsWith('mindtrack-static-') && name !== CACHE_NAME)
            .map((name) => caches.delete(name)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || !STATIC_FILE.test(url.pathname)) {
    return;
  }

  // Ağdan güncel dosyayı al; yalnızca bağlantı yoksa cache'e düş. Cache-first
  // davranışı, aynı isimle yayımlanan main.dart.js dosyasını sonsuza dek eski
  // sürümde tutarak sunucu düzeltmelerinin kullanıcıya ulaşmasını engelliyordu.
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        if (!response || !response.ok) return response;
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        return response;
      })
      .catch(() => caches.match(event.request)),
  );
});

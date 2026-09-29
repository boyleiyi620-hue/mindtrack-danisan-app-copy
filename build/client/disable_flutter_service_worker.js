const cacheNamesToDelete = async () => {
  const names = await caches.keys();
  await Promise.all(names.map((name) => caches.delete(name)));
};

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    cacheNamesToDelete()
      .catch(() => {})
      .then(() => self.clients.claim())
      .then(() => self.registration.unregister()),
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method === 'GET') {
    event.respondWith(fetch(event.request));
  }
});

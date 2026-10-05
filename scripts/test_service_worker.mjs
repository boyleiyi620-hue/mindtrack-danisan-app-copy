import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const bootstrap = await readFile(
  new URL('../web/flutter_bootstrap.js', import.meta.url),
  'utf8',
);
assert.match(bootstrap, /_flutter\.loader\.load\(\{\s*config:/);
assert.match(bootstrap, /onEntrypointLoaded/);
assert.match(bootstrap, /await appRunner\.runApp\(\)/);
assert.match(bootstrap, /bootSplash\?\.remove\(\)/);
assert.match(bootstrap, /canvasKitBaseUrl:\s*'canvaskit\/'/);
assert.match(bootstrap, /mindtrack-boot/);
assert.match(bootstrap, /mindtrack-boot-detail/);
assert.match(bootstrap, /MindTrack startup error/);
assert.match(bootstrap, /reason\?\.stack/);
assert.doesNotMatch(bootstrap, /findVisibleCanvas|firstCanvasTimer/);
assert.match(bootstrap, /Uygulama başlatılamadı/);
assert.doesNotMatch(bootstrap, /https:\/\/www\.gstatic\.com\/flutter-canvaskit/);
assert.match(bootstrap, /canvasKitForceCpuOnly:\s*isTouchAndroid/);
assert.match(bootstrap, /Android/);
assert.match(bootstrap, /90000/);

for (const page of ['index.html', 'index_client.html', 'index_psychologist.html']) {
  const html = await readFile(new URL(`../web/${page}`, import.meta.url), 'utf8');
  assert.match(html, /id="mindtrack-boot"/);
  assert.match(html, /id="mindtrack-boot-detail"/);
  assert.match(html, /mindtrack-sw-network-v11/);
  assert.match(html, /bootstrap\.onerror/);
  assert.match(html, /rel="preload" href="main\.dart\.js" as="script"/);
  assert.doesNotMatch(html, /navigator\.serviceWorker\.ready/);
}

const source = await readFile(
  new URL('../web/disable_flutter_service_worker.js', import.meta.url),
  'utf8',
);
const pwaUpdater = await readFile(
  new URL('../web/pwa_update.js', import.meta.url),
  'utf8',
);
assert.match(pwaUpdater, /waiting\.postMessage\(\{ type: 'SKIP_WAITING' \}\)/);
assert.match(pwaUpdater, /isTextEditor\(document\.activeElement\)/);
assert.match(pwaUpdater, /hadControllerAtStartup = Boolean\(navigator\.serviceWorker\.controller\)/);
assert.match(pwaUpdater, /if \(!hadControllerAtStartup\)/);
assert.doesNotMatch(pwaUpdater, /window\.confirm/);
const psychologistPage = await readFile(
  new URL('../web/index_psychologist.html', import.meta.url),
  'utf8',
);
assert.ok(
  psychologistPage.indexOf('document.body.append(bootstrap)') <
    psychologistPage.indexOf('navigator.serviceWorker.register'),
  'Flutter must start before waiting for service-worker registration',
);
const clientPage = await readFile(
  new URL('../web/index_client.html', import.meta.url),
  'utf8',
);
assert.ok(
  clientPage.indexOf('document.body.append(bootstrap)') <
    clientPage.indexOf('navigator.serviceWorker.register'),
  'client Flutter must start before waiting for service-worker registration',
);
const handlers = new Map();
let fetchCount = 0;
let navigationCount = 0;
let skipWaitingCount = 0;
const oldResponse = new Response('old cached bundle');
const context = {
  URL,
  Promise,
  Response,
  self: {
    location: { origin: 'https://app.test' },
    addEventListener: (name, handler) => handlers.set(name, handler),
    skipWaiting: async () => {
      skipWaitingCount += 1;
    },
    clients: {
      claim: async () => {},
      matchAll: async () => [
        {
          url: 'https://app.test/',
          navigate: async () => {
            navigationCount += 1;
          },
        },
      ],
    },
  },
  caches: {
    keys: async () => [],
    delete: async () => true,
    match: async () => oldResponse.clone(),
    open: async () => ({ put: async () => {} }),
  },
  fetch: async () => {
    fetchCount += 1;
    return new Response('current bundle', { status: 200 });
  },
};
vm.runInNewContext(source, context);

// Kaydedilmemiş veri varken sekmeler yenilenmemeli: aktivasyon yalnızca
// eski önbelleği temizler ve kontrolü devralır, hiçbir sekmeye dokunmaz.
handlers.get('install')?.();
let activation;
handlers.get('activate')({ waitUntil: (promise) => (activation = promise) });
await activation;
assert.equal(
  navigationCount,
  0,
  'activation must never reload app tabs (unsaved session notes would be lost)',
);
assert.equal(skipWaitingCount, 0, 'install must not skip waiting');

handlers.get('message')({ data: { type: 'SKIP_WAITING' } });
assert.equal(skipWaitingCount, 1, 'app must be able to apply the update on demand');

let ignoredMessageCount = skipWaitingCount;
handlers.get('message')({ data: { type: 'BASKA_BIR_MESAJ' } });
assert.equal(
  skipWaitingCount,
  ignoredMessageCount,
  'unknown messages must not activate a pending update',
);

let networkResponse;
handlers.get('fetch')({
  request: new Request('https://app.test/main.dart.js'),
  respondWith: (promise) => {
    networkResponse = promise;
  },
});
assert.equal(await (await networkResponse).text(), 'current bundle');
assert.equal(fetchCount, 1, 'static assets must be fetched before cache fallback');

context.fetch = async () => {
  throw new Error('offline');
};
let offlineResponse;
handlers.get('fetch')({
  request: new Request('https://app.test/main.dart.js'),
  respondWith: (promise) => {
    offlineResponse = promise;
  },
});
assert.equal(await (await offlineResponse).text(), 'old cached bundle');

console.log('Service worker network-first and offline fallback checks passed.');

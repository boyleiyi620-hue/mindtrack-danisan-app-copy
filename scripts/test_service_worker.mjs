import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(
  new URL('../web/disable_flutter_service_worker.js', import.meta.url),
  'utf8',
);
const handlers = new Map();
let fetchCount = 0;
const oldResponse = new Response('old cached bundle');
const context = {
  URL,
  Promise,
  Response,
  self: {
    location: { origin: 'https://app.test' },
    addEventListener: (name, handler) => handlers.set(name, handler),
    skipWaiting: async () => {},
    clients: { claim: async () => {} },
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

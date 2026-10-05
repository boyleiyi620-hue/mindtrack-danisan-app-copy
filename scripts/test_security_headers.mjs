// Dağıtım güvenlik başlıklarını doğrular.
//
// Uygulama sağlık verisi işlediği için tarayıcı güvenlik başlıkları zorunludur.
// Bu kontrol, başlık kaybolursa veya gevşetilirse derlemeyi durdurur.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const config = JSON.parse(
  await readFile(new URL('./vercel.json', import.meta.url), 'utf8'),
);

const rules = config.headers ?? [];
assert.ok(rules.length > 0, 'vercel.json must declare headers');

// Tüm yollara uygulanan genel kural bulunmalı.
const global = rules.find((rule) => rule.source === '/(.*)');
assert.ok(global, 'a catch-all header rule must exist for /(.*)');

const headers = Object.fromEntries(
  global.headers.map((header) => [header.key, header.value]),
);

function has(key) {
  return Object.prototype.hasOwnProperty.call(headers, key);
}

// --- Zorunlu başlıklar ------------------------------------------------------
for (const key of [
  'Content-Security-Policy',
  'Strict-Transport-Security',
  'X-Content-Type-Options',
  'X-Frame-Options',
  'Referrer-Policy',
]) {
  assert.ok(has(key), `missing security header: ${key}`);
}

// --- İçerik Güvenliği Politikası ------------------------------------------
const csp = headers['Content-Security-Policy'];
assert.match(csp, /default-src 'self'/, "CSP must fall back to 'self'");
assert.match(csp, /object-src 'none'/, 'CSP must forbid plugin objects');
assert.match(csp, /frame-ancestors 'none'/, 'CSP must forbid framing (clickjacking)');
assert.match(csp, /base-uri 'self'/, 'CSP must pin base URI');
assert.match(csp, /form-action 'self'/, 'CSP must restrict form targets');

// Sağlık verisi gönderilen sunucu; hepsi beyaz listede olmalı.
assert.match(
  csp,
  /connect-src [^;]*https:\/\/\*\.supabase\.co/,
  'CSP must allow the Supabase REST endpoint',
);
assert.match(
  csp,
  /connect-src [^;]*wss:\/\/\*\.supabase\.co/,
  'CSP must allow the Supabase Realtime websocket',
);
assert.match(
  csp,
  /connect-src [^;]*https:\/\/fonts\.gstatic\.com/,
  'CSP must allow Flutter web font fallback requests',
);
assert.match(
  csp,
  /font-src [^;]*https:\/\/fonts\.gstatic\.com/,
  'CSP must allow the font fallback origin',
);

// --- Regresyon koruması ---------------------------------------------------

/// CSP yönergesindeki tüm kaynak jetonlarını verir.
function tokens(directive) {
  const match = csp.match(new RegExp(`(?:^|;)\\s*${directive}\\s+([^;]*)`));
  return match ? match[1].trim().split(/\s+/) : [];
}

const scriptSrc = tokens('script-src');
assert.ok(scriptSrc.length > 0, 'CSP must define script-src');
// 'wasm-unsafe-eval' CanvasKit'in WebAssembly'ı için gereklidir; düz
// 'unsafe-eval' ise script enjeksiyonuna kapı açar ve asla istememelidir.
assert.ok(
  !scriptSrc.includes("'unsafe-eval'"),
  "CSP must not enable plain 'unsafe-eval'",
);
assert.ok(
  scriptSrc.includes("'unsafe-inline'"),
  'Flutter bootstrap needs inline scripts',
);
assert.ok(
  scriptSrc.includes("'wasm-unsafe-eval'"),
  'CanvasKit WebAssembly requires wasm-unsafe-eval',
);
assert.ok(tokens('worker-src').includes('blob:'), 'Flutter web workers use blob URLs');
assert.ok(tokens('img-src').includes('data:'), 'CanvasKit renders data: images');
assert.ok(tokens('img-src').includes('blob:'), 'PDF previews use blob: images');
assert.ok(tokens('style-src').includes("'unsafe-inline'"), 'Flutter injects inline styles');

// HSTS yalnızca HTTPS üzerinden yönlendirilmelidir.
assert.match(
  headers['Strict-Transport-Security'],
  /max-age=\d{6,}/,
  'HSTS max-age must be at least ~1 year',
);

console.log('Security header checks passed.');

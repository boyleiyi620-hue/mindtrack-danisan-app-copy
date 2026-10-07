#!/usr/bin/env node
import process from 'node:process';

const url = process.argv[2];
const attempts = Number(process.argv[3] ?? '3');
const timeoutMs = 10_000;
const retryDelayMs = 2_000;
if (!url) {
  console.error('Kullanım: node scripts/check_uptime.mjs <health-url> [attempts]');
  process.exit(2);
}
if (!Number.isInteger(attempts) || attempts < 1 || attempts > 10) {
  console.error('Deneme sayısı 1 ile 10 arasında bir tam sayı olmalı.');
  process.exit(2);
}

let appUrl;
try {
  appUrl = new URL(url);
} catch {
  console.error('Uygulama adresi geçerli bir URL olmalı.');
  process.exit(2);
}
if (appUrl.protocol !== 'https:') {
  console.error('Uygulama adresi HTTPS kullanmalı.');
  process.exit(2);
}
if (!appUrl.pathname.endsWith('/')) appUrl.pathname += '/';

const checks = [
  { path: '', contentType: 'text/html' },
  { path: 'version.json', contentType: 'application/json' },
  { path: 'flutter_bootstrap.js', contentType: 'javascript' },
  { path: 'main.dart.js', contentType: 'javascript' },
];

let passed = 0;
for (let attempt = 1; attempt <= attempts; attempt += 1) {
  const started = Date.now();
  try {
    for (const check of checks) {
      const resourceUrl = new URL(check.path, appUrl);
      const response = await fetch(resourceUrl, {
        method: 'HEAD',
        redirect: 'error',
        signal: AbortSignal.timeout(timeoutMs),
      });
      const contentType = response.headers.get('content-type') ?? '';
      if (response.status !== 200 || !contentType.includes(check.contentType)) {
        throw new Error(
          `${resourceUrl.pathname}: HTTP ${response.status}, content-type=${contentType}`,
        );
      }
    }
    passed += 1;
    console.log(`uptime check ${attempt}/${attempts}: app and bundles ok (${Date.now() - started}ms)`);
  } catch (error) {
    console.error(`uptime check ${attempt}/${attempts}: failed: ${error}`);
  }
  if (attempt < attempts && passed !== attempt) {
    await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
  }
}

if (passed !== attempts) {
  process.exit(1);
}

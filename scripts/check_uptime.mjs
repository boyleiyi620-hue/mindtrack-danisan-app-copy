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

let healthUrl;
try {
  healthUrl = new URL(url);
} catch {
  console.error('Health URL geçerli bir URL olmalı.');
  process.exit(2);
}
if (healthUrl.protocol !== 'https:') {
  console.error('Health URL HTTPS kullanmalı.');
  process.exit(2);
}

let passed = 0;
for (let attempt = 1; attempt <= attempts; attempt += 1) {
  const started = Date.now();
  try {
    const response = await fetch(healthUrl, {
      redirect: 'error',
      signal: AbortSignal.timeout(timeoutMs),
      headers: { accept: 'application/json' },
    });
    const body = await response.json();
    if (
      response.status !== 200 ||
      body?.service !== 'mindtrack-web' ||
      body?.status !== 'ok' ||
      !Array.isArray(body?.checks) ||
      body.checks.length === 0
    ) {
      throw new Error(`HTTP ${response.status}, status=${body?.status}`);
    }
    passed += 1;
    console.log(`uptime check ${attempt}/${attempts}: ok (${Date.now() - started}ms)`);
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

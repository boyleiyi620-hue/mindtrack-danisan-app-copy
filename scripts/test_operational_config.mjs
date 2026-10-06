import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const health = JSON.parse(await readFile(new URL('../web/health.json', import.meta.url), 'utf8'));
assert.equal(health.service, 'mindtrack-web');
assert.equal(health.status, 'ok');
assert.deepEqual(health.checks, ['static-host', 'pwa-bundle']);

const build = await readFile(new URL('./build_web.sh', import.meta.url), 'utf8');
assert.match(build, /SUPABASE_URL/);
assert.match(build, /SUPABASE_PUBLISHABLE_KEY/);
assert.match(build, /health\.json/);
assert.doesNotMatch(build, /SUPABASE_SERVICE_ROLE|service_role=/i);

const uptime = await readFile(new URL('./check_uptime.mjs', import.meta.url), 'utf8');
assert.match(uptime, /redirect: 'error'/);
assert.match(uptime, /body\?\.status !== 'ok'/);
assert.match(uptime, /AbortSignal\.timeout\(timeoutMs\)/);
assert.match(uptime, /healthUrl\.protocol !== 'https:'/);
assert.match(uptime, /body\?\.service !== 'mindtrack-web'/);

console.log('Operational configuration checks passed.');

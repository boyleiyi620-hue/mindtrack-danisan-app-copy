import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile(
  new URL('../supabase/migrations/20261006160000_client_error_events.sql', import.meta.url),
  'utf8',
);
const alertMigration = await readFile(
  new URL('../supabase/migrations/20261006180000_critical_error_alerts.sql', import.meta.url),
  'utf8',
);
const alertFunction = await readFile(
  new URL('../supabase/functions/critical-error-alert/index.ts', import.meta.url),
  'utf8',
);
const backend = await readFile(
  new URL('../lib/data/mindtrack_backend.dart', import.meta.url),
  'utf8',
);
const supabaseConfig = await readFile(
  new URL('../supabase/config.toml', import.meta.url),
  'utf8',
);

for (const fragment of [
  'create table if not exists public.client_error_events',
  'create or replace function public.report_client_error',
  'severity in (\'warning\', \'error\', \'critical\')',
  'left(trim(p_message), 500)',
  'grant execute on function public.report_client_error',
]) {
  assert.match(migration.toLowerCase(), new RegExp(fragment.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
}

for (const forbidden of ['notes', 'diagnosiscodes', 'safety', 'data jsonb']) {
  assert.equal(
    migration.toLowerCase().includes(forbidden),
    false,
    `Hata günlüğü klinik alan içeriyor: ${forbidden}`,
  );
}

for (const fragment of [
  'alert_claimed_at timestamptz',
  'alert_sent_at timestamptz',
  'to service_role',
]) {
  assert.match(alertMigration.toLowerCase(), new RegExp(fragment.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
}
for (const fragment of [
  "authorization",
  "admin.auth.getUser(token)",
  "MINDTRACK_CRITICAL_ALERT_WEBHOOK",
  "SUPABASE_SECRET_KEYS",
  "JSON.parse(secretKeys).default",
  "redirect: 'error'",
  "AbortSignal.timeout(8_000)",
  "alert_sent_at",
]) {
  assert.ok(alertFunction.includes(fragment), `Critical alert integration missing ${fragment}`);
}
assert.doesNotMatch(alertFunction, /select\([^)]*message|organization_id|client_name|clinical_note/i);
assert.match(alertFunction, /\^\[a-z0-9_\]\{1,80\}\$/);
assert.match(backend, /functions\.invoke\('critical-error-alert'/);
assert.match(supabaseConfig, /\[functions\.critical-error-alert\]\s+verify_jwt = true/);

console.log('Critical error notification checks passed.');
console.log('Observability schema checks passed.');

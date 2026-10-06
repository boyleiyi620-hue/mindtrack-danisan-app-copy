import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile(
  new URL('../supabase/migrations/20261006160000_client_error_events.sql', import.meta.url),
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

console.log('Observability schema checks passed.');

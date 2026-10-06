import { readFile } from 'node:fs/promises';

const migration = await readFile(
  new URL('../supabase/migrations/20261006200000_licenses_and_billing.sql', import.meta.url),
  'utf8',
);
const sql = migration.toLowerCase();
for (const fragment of [
  'create table public.licenses', 'create table public.license_seats',
  'create table public.payment_records', 'create table public.audit_log',
  'create or replace function public.is_platform_admin', 'app_metadata',
  'alter table public.licenses enable row level security',
  'alter table public.license_seats enable row level security',
  'alter table public.payment_records enable row level security',
  'revoke all on table public.audit_log from anon, authenticated',
  'klinik üyeleri kendi lisansını görür', 'klinik yöneticisi tahsilatları görür',
]) {
  if (!sql.includes(fragment)) throw new Error(`License schema check failed: ${fragment}`);
}
for (const forbidden of ['grant insert on public.licenses', 'grant update on public.licenses', 'grant delete on public.licenses']) {
  if (sql.includes(forbidden)) throw new Error(`Unsafe license grant: ${forbidden}`);
}
console.log('License schema checks passed.');

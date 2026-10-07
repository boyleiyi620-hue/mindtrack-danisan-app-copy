import { readFile } from 'node:fs/promises';

const migration = await readFile(
  new URL('../supabase/migrations/20261005160000_psychologist_records.sql', import.meta.url),
  'utf8',
);
const rpcMigration = await readFile(
  new URL('../supabase/migrations/20261006120000_record_sync_rpc.sql', import.meta.url),
  'utf8',
);
const legacyMigration = await readFile(
  new URL('../supabase/migrations/20261007195000_enable_record_sync_on_legacy_projects.sql', import.meta.url),
  'utf8',
);

const required = [
  'create table public.psychologist_records',
  'primary key (psychologist_id, record_type, record_id)',
  'data jsonb not null',
  'record_version bigint not null',
  'deleted_at timestamptz',
  'alter table public.psychologist_records enable row level security',
  'using ((select auth.uid()) = psychologist_id)',
  'with check ((select auth.uid()) = psychologist_id)',
];

for (const fragment of required) {
  if (!migration.toLowerCase().includes(fragment.toLowerCase())) {
    throw new Error(`Kayıt şeması doğrulaması başarısız: ${fragment}`);
  }
}

for (const type of [
  'client', 'note', 'appointment', 'form', 'assessment', 'plan', 'task',
  'document', 'pdf_category', 'pdf_file', 'transaction', 'training',
  'finance_goal',
]) {
  if (!migration.includes(`'${type}'`)) {
    throw new Error(`Kayıt türü eksik: ${type}`);
  }
}

console.log('Record schema checks passed.');

for (const fragment of [
  'create or replace function public.upsert_psychologist_records',
  'record_conflict',
  'grant execute on function public.upsert_psychologist_records(jsonb) to authenticated',
]) {
  if (!rpcMigration.toLowerCase().includes(fragment.toLowerCase())) {
    throw new Error(`Kayıt RPC doğrulaması başarısız: ${fragment}`);
  }
}

console.log('Record sync RPC checks passed.');

for (const fragment of [
  'create table if not exists public.psychologist_records',
  'create or replace function public.upsert_psychologist_records',
  'alter publication supabase_realtime add table public.psychologist_records',
]) {
  if (!legacyMigration.toLowerCase().includes(fragment.toLowerCase())) {
    throw new Error(`Eski üretim senkron migration kontrolü başarısız: ${fragment}`);
  }
}

console.log('Legacy record sync migration checks passed.');

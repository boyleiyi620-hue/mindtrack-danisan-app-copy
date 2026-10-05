import { readFile } from 'node:fs/promises';

const migration = await readFile(
  new URL('../supabase/migrations/20261005160000_psychologist_records.sql', import.meta.url),
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

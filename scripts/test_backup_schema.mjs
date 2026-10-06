import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile(
  new URL('../supabase/migrations/20261006170000_record_history_backup.sql', import.meta.url),
  'utf8',
);
const runbook = await readFile(
  new URL('../docs/OPERATIONS-BACKUP.md', import.meta.url),
  'utf8',
);

for (const fragment of [
  'create table if not exists public.psychologist_record_history',
  'capture_psychologist_record_history',
  'before update on public.psychologist_records',
  'before delete on public.psychologist_records',
  'create or replace function public.restore_psychologist_record',
  'where history_id = p_history_id',
  'grant execute on function public.restore_psychologist_record',
]) {
  assert.match(migration.toLowerCase(), new RegExp(fragment.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
}

for (const fragment of [
  'PITR/günlük yedekleme',
  'Ayda en az bir kez',
  'PDF/Belge dosyaları',
  'veritabanı yedeğini kendi',
]) {
  assert.match(runbook.toLowerCase(), new RegExp(fragment.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
}

console.log('Backup and restore rehearsal checks passed.');

-- =============================================================================
-- Kayıt bazlı klinik veri temeli
--
-- Mevcut psychologist_state JSON satırı korunur. Bu tablo, kademeli geçişte
-- kayıtların ayrı ve güvenli satırlar olarak tutulacağı ortak alanı sağlar.
-- =============================================================================

create table public.psychologist_records (
  psychologist_id uuid not null references auth.users (id) on delete cascade,
  record_type text not null check (record_type in (
    'client', 'note', 'appointment', 'form', 'assessment', 'plan', 'task',
    'document', 'pdf_category', 'pdf_file', 'transaction', 'training',
    'finance_goal'
  )),
  record_id text not null,
  data jsonb not null default '{}'::jsonb,
  record_version bigint not null default 1 check (record_version > 0),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (psychologist_id, record_type, record_id)
);

create index psychologist_records_type_updated_idx
  on public.psychologist_records (psychologist_id, record_type, updated_at desc);

create index psychologist_records_deleted_idx
  on public.psychologist_records (psychologist_id, deleted_at);

create trigger psychologist_records_touch
  before update on public.psychologist_records
  for each row execute function public.touch_updated_at();

alter table public.psychologist_records enable row level security;

create policy "psikolog kendi kayıtlarını okur"
  on public.psychologist_records for select
  to authenticated
  using ((select auth.uid()) = psychologist_id);

create policy "psikolog kendi kayıtlarını yazar"
  on public.psychologist_records for insert
  to authenticated
  with check ((select auth.uid()) = psychologist_id);

create policy "psikolog kendi kayıtlarını günceller"
  on public.psychologist_records for update
  to authenticated
  using ((select auth.uid()) = psychologist_id)
  with check ((select auth.uid()) = psychologist_id);

create policy "psikolog kendi kayıtlarını siler"
  on public.psychologist_records for delete
  to authenticated
  using ((select auth.uid()) = psychologist_id);

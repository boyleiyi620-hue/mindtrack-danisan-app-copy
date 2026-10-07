-- Legacy üretim projelerinde kayıt bazlı senkronizasyonu etkinleştirir.
-- psychologist_state verisi korunur; ilk başarılı kayıtta kayıtlar ayrı satırlara
-- taşınır ve sonraki cihazlar aynı kayıtları okur.

create table if not exists public.psychologist_records (
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

create index if not exists psychologist_records_updated_idx
  on public.psychologist_records (psychologist_id, updated_at desc);

alter table public.psychologist_records enable row level security;

drop policy if exists "psikolog kendi kayıtlarını okur" on public.psychologist_records;
create policy "psikolog kendi kayıtlarını okur"
  on public.psychologist_records for select to authenticated
  using ((select auth.uid()) = psychologist_id);

drop policy if exists "psikolog kendi kayıtlarını yazar" on public.psychologist_records;
create policy "psikolog kendi kayıtlarını yazar"
  on public.psychologist_records for insert to authenticated
  with check ((select auth.uid()) = psychologist_id);

drop policy if exists "psikolog kendi kayıtlarını günceller" on public.psychologist_records;
create policy "psikolog kendi kayıtlarını günceller"
  on public.psychologist_records for update to authenticated
  using ((select auth.uid()) = psychologist_id)
  with check ((select auth.uid()) = psychologist_id);

drop policy if exists "psikolog kendi kayıtlarını siler" on public.psychologist_records;
create policy "psikolog kendi kayıtlarını siler"
  on public.psychologist_records for delete to authenticated
  using ((select auth.uid()) = psychologist_id);

grant select, insert, update, delete on public.psychologist_records to authenticated;

create or replace function public.upsert_psychologist_records(p_records jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
  item jsonb;
  v_type text;
  v_id text;
  v_data jsonb;
  v_expected bigint;
  v_current bigint;
  v_deleted_at timestamptz;
  result jsonb := '[]'::jsonb;
  v_user uuid := (select auth.uid());
  saved jsonb;
begin
  if v_user is null then raise exception 'Oturum gerekli'; end if;
  if jsonb_typeof(p_records) <> 'array' then raise exception 'Kayıt listesi geçersiz'; end if;
  for item in select value from jsonb_array_elements(p_records) loop
    v_type := nullif(trim(item->>'record_type'), '');
    v_id := nullif(trim(item->>'record_id'), '');
    v_data := coalesce(item->'data', '{}'::jsonb);
    v_expected := coalesce((item->>'expected_version')::bigint, 0);
    v_deleted_at := nullif(item->>'deleted_at', '')::timestamptz;
    if v_type is null or v_id is null then raise exception 'Kayıt kimliği eksik'; end if;
    select record_version into v_current from public.psychologist_records
     where psychologist_id = v_user and record_type = v_type and record_id = v_id;
    if v_current is null then
      if v_expected <> 0 then raise exception 'record_conflict:%:%', v_type, v_id; end if;
      insert into public.psychologist_records
        (psychologist_id, record_type, record_id, data, record_version, deleted_at)
      values (v_user, v_type, v_id, v_data, 1, v_deleted_at)
      returning jsonb_build_object('record_type', record_type, 'record_id', record_id,
        'data', data, 'record_version', record_version, 'deleted_at', deleted_at) into saved;
    else
      if v_current <> v_expected then raise exception 'record_conflict:%:%', v_type, v_id; end if;
      update public.psychologist_records set data = v_data, deleted_at = v_deleted_at,
        record_version = v_current + 1, updated_at = now()
       where psychologist_id = v_user and record_type = v_type and record_id = v_id
      returning jsonb_build_object('record_type', record_type, 'record_id', record_id,
        'data', data, 'record_version', record_version, 'deleted_at', deleted_at) into saved;
    end if;
    result := result || jsonb_build_array(saved);
  end loop;
  return result;
end;
$$;

revoke all on function public.upsert_psychologist_records(jsonb) from public;
grant execute on function public.upsert_psychologist_records(jsonb) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'psychologist_records'
     ) then
    execute 'alter publication supabase_realtime add table public.psychologist_records';
  end if;
end;
$$;

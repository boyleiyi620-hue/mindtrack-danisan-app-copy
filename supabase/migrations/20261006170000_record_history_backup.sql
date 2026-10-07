-- Kayıt bazlı otomatik geri alınabilirlik.
-- Her update/delete öncesi eski sürüm append-only geçmişe yazılır.

create table if not exists public.psychologist_record_history (
  history_id bigint generated always as identity primary key,
  psychologist_id uuid not null references auth.users (id) on delete cascade,
  record_type text not null,
  record_id text not null,
  data jsonb not null default '{}'::jsonb,
  record_version bigint not null,
  deleted_at timestamptz,
  change_kind text not null check (change_kind in ('update', 'delete')),
  captured_at timestamptz not null default now()
);

create index if not exists psychologist_record_history_lookup_idx
  on public.psychologist_record_history
  (psychologist_id, record_type, record_id, captured_at desc);

alter table public.psychologist_record_history enable row level security;

create policy "psikolog kendi kayıt geçmişini görür"
  on public.psychologist_record_history for select
  to authenticated
  using ((select auth.uid()) = psychologist_id);

create or replace function public.capture_psychologist_record_history()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.psychologist_record_history (
    psychologist_id, record_type, record_id, data, record_version,
    deleted_at, change_kind
  ) values (
    old.psychologist_id, old.record_type, old.record_id, old.data,
    old.record_version, old.deleted_at,
    case when tg_op = 'DELETE' then 'delete' else 'update' end
  );
  return old;
end;
$$;

drop trigger if exists psychologist_records_history_before_update
  on public.psychologist_records;
create trigger psychologist_records_history_before_update
  before update on public.psychologist_records
  for each row execute function public.capture_psychologist_record_history();

drop trigger if exists psychologist_records_history_before_delete
  on public.psychologist_records;
create trigger psychologist_records_history_before_delete
  before delete on public.psychologist_records
  for each row execute function public.capture_psychologist_record_history();

-- Geri yükleme yalnızca çağrıyı yapan psikoloğun kendi geçmişinden yapılabilir.
-- Mevcut kayıt silinmez; yeni bir sürüm olarak geri alınır.
create or replace function public.restore_psychologist_record(
  p_history_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  history_row public.psychologist_record_history%rowtype;
  current_version bigint;
  restored jsonb;
begin
  select * into history_row
    from public.psychologist_record_history
   where history_id = p_history_id
     and psychologist_id = (select auth.uid());
  if not found then
    raise exception 'Kayıt geçmişi bulunamadı';
  end if;

  select record_version into current_version
    from public.psychologist_records
   where psychologist_id = history_row.psychologist_id
     and record_type = history_row.record_type
     and record_id = history_row.record_id;

  if current_version is null then
    insert into public.psychologist_records (
      psychologist_id, record_type, record_id, data, record_version, deleted_at
    ) values (
      history_row.psychologist_id, history_row.record_type, history_row.record_id,
      history_row.data, 1, history_row.deleted_at
    ) returning jsonb_build_object(
      'record_type', record_type, 'record_id', record_id,
      'data', data, 'record_version', record_version, 'deleted_at', deleted_at
    ) into restored;
  else
    update public.psychologist_records
       set data = history_row.data,
           deleted_at = history_row.deleted_at,
           record_version = current_version + 1
     where psychologist_id = history_row.psychologist_id
       and record_type = history_row.record_type
       and record_id = history_row.record_id
    returning jsonb_build_object(
      'record_type', record_type, 'record_id', record_id,
      'data', data, 'record_version', record_version, 'deleted_at', deleted_at
    ) into restored;
  end if;
  return restored;
end;
$$;

revoke all on function public.restore_psychologist_record(bigint) from public;
grant execute on function public.restore_psychologist_record(bigint) to authenticated;

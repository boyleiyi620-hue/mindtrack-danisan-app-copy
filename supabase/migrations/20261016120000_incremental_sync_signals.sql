-- LOCAL DRAFT ONLY — DO NOT APPLY without separate production DB/RLS approval.
--
-- Incremental sync metadata only: clinical payloads remain in psychologist_records
-- and tasks. Clients subscribe to this narrow table, then re-fetch changed rows
-- through the source table's existing owner/client RLS. The migration does not
-- change policies on any existing clinical table.

create table public.mindtrack_sync_signals (
  user_id uuid not null references auth.users (id) on delete cascade,
  entity_type text not null check (entity_type in ('psychologist_record', 'task')),
  record_type text not null default '',
  record_id text not null,
  record_version bigint not null default 0,
  deleted_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, entity_type, record_type, record_id)
);

create index mindtrack_sync_signals_delta_idx
  on public.mindtrack_sync_signals
    (user_id, entity_type, updated_at, record_type, record_id);

alter table public.mindtrack_sync_signals enable row level security;
create policy "users read only their sync signals"
  on public.mindtrack_sync_signals for select to authenticated
  using ((select auth.uid()) = user_id);

grant select on public.mindtrack_sync_signals to authenticated;
revoke insert, update, delete on public.mindtrack_sync_signals
  from anon, authenticated;

create or replace function public.mindtrack_signal_psychologist_record()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid;
  v_type text;
  v_id text;
  v_version bigint;
  v_deleted_at timestamptz;
begin
  if tg_op = 'DELETE' then
    v_user := old.psychologist_id;
    v_type := old.record_type;
    v_id := old.record_id;
    v_version := old.record_version + 1;
    v_deleted_at := clock_timestamp();
  else
    v_user := new.psychologist_id;
    v_type := new.record_type;
    v_id := new.record_id;
    v_version := new.record_version;
    v_deleted_at := new.deleted_at;
  end if;

  insert into public.mindtrack_sync_signals
    (user_id, entity_type, record_type, record_id, record_version,
     deleted_at, updated_at)
  values
    (v_user, 'psychologist_record', v_type, v_id, v_version,
     v_deleted_at, clock_timestamp())
  on conflict (user_id, entity_type, record_type, record_id) do update
    set record_version = excluded.record_version,
        deleted_at = excluded.deleted_at,
        updated_at = greatest(
          clock_timestamp(),
          public.mindtrack_sync_signals.updated_at + interval '1 microsecond'
        );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.mindtrack_signal_psychologist_record()
  from public, anon, authenticated;
create trigger psychologist_records_sync_signal
  after insert or update or delete on public.psychologist_records
  for each row execute function public.mindtrack_signal_psychologist_record();

create or replace function public.mindtrack_signal_task()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid;
  v_deleted boolean;
begin
  -- A reassignment emits a removal signal to the former owner/client and a
  -- fresh signal to the new one. Task bodies and answers are never copied here.
  if tg_op <> 'INSERT' then
    for v_user in
      select distinct target_user_id
        from unnest(array[old.psychologist_id, old.client_uid]) as targets(target_user_id)
       where target_user_id is not null
    loop
      if tg_op = 'DELETE' then
        v_deleted := true;
      else
        v_deleted := v_user is distinct from new.psychologist_id
          and v_user is distinct from new.client_uid;
      end if;
      if v_deleted then
        insert into public.mindtrack_sync_signals
          (user_id, entity_type, record_type, record_id, record_version,
           deleted_at, updated_at)
        values
          (v_user, 'task', 'task', old.id::text, 1,
           clock_timestamp(), clock_timestamp())
        on conflict (user_id, entity_type, record_type, record_id) do update
          set record_version = public.mindtrack_sync_signals.record_version + 1,
              deleted_at = clock_timestamp(),
              updated_at = greatest(
                clock_timestamp(),
                public.mindtrack_sync_signals.updated_at + interval '1 microsecond'
              );
      end if;
    end loop;
  end if;

  if tg_op <> 'DELETE' then
    for v_user in
      select distinct target_user_id
        from unnest(array[new.psychologist_id, new.client_uid]) as targets(target_user_id)
       where target_user_id is not null
    loop
      insert into public.mindtrack_sync_signals
        (user_id, entity_type, record_type, record_id, record_version,
         deleted_at, updated_at)
      values
        (v_user, 'task', 'task', new.id::text, 1, null, clock_timestamp())
      on conflict (user_id, entity_type, record_type, record_id) do update
        set record_version = public.mindtrack_sync_signals.record_version + 1,
            deleted_at = null,
            updated_at = greatest(
              clock_timestamp(),
              public.mindtrack_sync_signals.updated_at + interval '1 microsecond'
            );
    end loop;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.mindtrack_signal_task()
  from public, anon, authenticated;
create trigger tasks_sync_signal
  after insert or update or delete on public.tasks
  for each row execute function public.mindtrack_signal_task();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'mindtrack_sync_signals'
     ) then
    execute 'alter publication supabase_realtime add table public.mindtrack_sync_signals';
  end if;
end;
$$;

-- A BEFORE UPDATE trigger must return NEW or PostgreSQL cancels the update.
-- Returning OLD here silently discarded every record edit after history capture.
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

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

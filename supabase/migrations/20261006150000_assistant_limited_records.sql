-- Asistan görünümü: klinik notlarını ve hassas alanları açmadan
-- danışan dizini ile randevu özetlerini sunar.

create or replace function public.fetch_assistant_records(
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  result jsonb;
begin
  if not exists (
    select 1
      from public.memberships current_member
     where current_member.organization_id = p_organization_id
       and current_member.user_id = (select auth.uid())
       and current_member.role = 'assistant'
       and current_member.status = 'active'
  ) then
    raise exception 'Bu görünüm yalnızca aktif klinik asistanları içindir';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'record_type', r.record_type,
    'record_id', r.record_id,
    'record_version', r.record_version,
    'deleted_at', null,
    'data', case r.record_type
      when 'client' then jsonb_build_object(
        'id', r.data->>'id',
        'name', coalesce(r.data->>'name', ''),
        'email', coalesce(r.data->>'email', ''),
        'phone', coalesce(r.data->>'phone', ''),
        'status', coalesce(r.data->>'status', 'active'),
        'createdAt', coalesce(r.data->'createdAt', '0'::jsonb),
        'updatedAt', coalesce(r.data->'updatedAt', '0'::jsonb)
      )
      when 'appointment' then jsonb_build_object(
        'id', r.data->>'id',
        'date', coalesce(r.data->>'date', ''),
        'time', coalesce(r.data->>'time', ''),
        'clientId', coalesce(r.data->>'clientId', ''),
        'type', coalesce(r.data->>'type', 'therapy'),
        'status', coalesce(r.data->>'status', 'planned'),
        'durationMin', coalesce(r.data->'durationMin', '50'::jsonb),
        'createdAt', coalesce(r.data->'createdAt', '0'::jsonb)
      )
    end
  ) order by r.updated_at desc), '[]'::jsonb)
    into result
    from public.psychologist_records r
    join public.memberships owner_member
      on owner_member.user_id = r.psychologist_id
     and owner_member.organization_id = p_organization_id
     and owner_member.status = 'active'
   where r.record_type in ('client', 'appointment')
     and r.deleted_at is null;

  return result;
end;
$$;

revoke all on function public.fetch_assistant_records(uuid) from public;
grant execute on function public.fetch_assistant_records(uuid) to authenticated;

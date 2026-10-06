-- Klinik yöneticisinin mevcut Supabase kullanıcılarını e-posta ile
-- kliniğe eklemesi ve üyelik durumunu yönetmesi.

create or replace function public.list_organization_members(p_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  result jsonb;
begin
  if not public.is_organization_admin(p_organization_id) then
    raise exception 'Bu işlem için klinik yöneticisi yetkisi gerekli';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', m.user_id,
    'email', coalesce(u.email, ''),
    'role', m.role,
    'status', m.status
  ) order by m.created_at), '[]'::jsonb)
    into result
    from public.memberships m
    left join auth.users u on u.id = m.user_id
   where m.organization_id = p_organization_id;
  return result;
end;
$$;

create or replace function public.manage_organization_member(
  p_organization_id uuid,
  p_email text,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid;
  result jsonb;
begin
  if not public.is_organization_admin(p_organization_id) then
    raise exception 'Bu işlem için klinik yöneticisi yetkisi gerekli';
  end if;
  if p_role not in ('psychologist', 'assistant') then
    raise exception 'Geçersiz klinik rolü';
  end if;

  select id into v_user_id
    from auth.users
   where lower(email) = lower(trim(p_email))
   limit 1;
  if v_user_id is null then
    raise exception 'Bu e-posta ile kayıtlı MindTrack hesabı bulunamadı';
  end if;

  insert into public.memberships (organization_id, user_id, role, status)
  values (p_organization_id, v_user_id, p_role, 'active')
  on conflict (organization_id, user_id)
  do update set role = excluded.role, status = 'active';

  select jsonb_build_object(
    'user_id', m.user_id,
    'email', coalesce(u.email, ''),
    'role', m.role,
    'status', m.status
  ) into result
    from public.memberships m
    left join auth.users u on u.id = m.user_id
   where m.organization_id = p_organization_id
     and m.user_id = v_user_id;
  return result;
end;
$$;

create or replace function public.set_organization_member_status(
  p_organization_id uuid,
  p_user_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_organization_admin(p_organization_id) then
    raise exception 'Bu işlem için klinik yöneticisi yetkisi gerekli';
  end if;
  if p_status not in ('active', 'suspended') then
    raise exception 'Geçersiz üyelik durumu';
  end if;
  update public.memberships
     set status = p_status
   where organization_id = p_organization_id
     and user_id = p_user_id;
end;
$$;

revoke all on function public.list_organization_members(uuid) from public;
revoke all on function public.manage_organization_member(uuid, text, text) from public;
revoke all on function public.set_organization_member_status(uuid, uuid, text) from public;
grant execute on function public.list_organization_members(uuid) to authenticated;
grant execute on function public.manage_organization_member(uuid, text, text) to authenticated;
grant execute on function public.set_organization_member_status(uuid, uuid, text) to authenticated;

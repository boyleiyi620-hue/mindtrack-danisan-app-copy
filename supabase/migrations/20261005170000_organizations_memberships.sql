-- =============================================================================
-- Klinik / çok kiracı veri temeli
--
-- Her klinik ayrı bir tenant'tır. Mevcut tek psikolog hesabı ve
-- psychologist_state tablosu bu migration'dan etkilenmez; uygulama bağlantısı
-- sonraki aşamada yapılacaktır.
-- =============================================================================

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 160),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'psychologist'
    check (role in ('admin', 'psychologist', 'assistant')),
  status text not null default 'active'
    check (status in ('pending', 'active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create index memberships_user_idx
  on public.memberships (user_id, status, organization_id);

create trigger organizations_touch
  before update on public.organizations
  for each row execute function public.touch_updated_at();

create trigger memberships_touch
  before update on public.memberships
  for each row execute function public.touch_updated_at();

-- Membership RLS politikaları içinde tekrar tekrar tablo sorgulamak yerine,
-- yalnızca admin kontrolünü güvenli bir yardımcı fonksiyonda topluyoruz.
create or replace function public.is_organization_admin(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
      from public.memberships m
     where m.organization_id = p_organization_id
       and m.user_id = (select auth.uid())
       and m.role = 'admin'
       and m.status = 'active'
  );
$$;

create or replace function public.create_organization(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_organization_id uuid;
begin
  if v_user_id is null then
    raise exception 'Oturum gerekli';
  end if;
  insert into public.organizations (name, created_by)
  values (trim(p_name), v_user_id)
  returning id into v_organization_id;

  insert into public.memberships (organization_id, user_id, role, status)
  values (v_organization_id, v_user_id, 'admin', 'active');
  return v_organization_id;
end;
$$;

revoke all on function public.is_organization_admin(uuid) from public;
grant execute on function public.is_organization_admin(uuid) to authenticated;
revoke all on function public.create_organization(text) from public;
grant execute on function public.create_organization(text) to authenticated;

alter table public.organizations enable row level security;
alter table public.memberships enable row level security;

create policy "üyeler kendi kliniklerini görür"
  on public.organizations for select
  to authenticated
  using (exists (
    select 1 from public.memberships m
     where m.organization_id = organizations.id
       and m.user_id = (select auth.uid())
       and m.status = 'active'
  ));

create policy "kullanıcı kendi kliniğini oluşturur"
  on public.organizations for insert
  to authenticated
  with check ((select auth.uid()) = created_by);

create policy "klinik yöneticisi kliniği günceller"
  on public.organizations for update
  to authenticated
  using (public.is_organization_admin(id))
  with check (public.is_organization_admin(id));

create policy "klinik yöneticisi kliniği siler"
  on public.organizations for delete
  to authenticated
  using (public.is_organization_admin(id));

create policy "kullanıcı üyeliğini veya yönettiği üyeleri görür"
  on public.memberships for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_organization_admin(organization_id)
  );

create policy "klinik yöneticisi üye ekler"
  on public.memberships for insert
  to authenticated
  with check (public.is_organization_admin(organization_id));

create policy "klinik yöneticisi üyeliği günceller"
  on public.memberships for update
  to authenticated
  using (public.is_organization_admin(organization_id))
  with check (public.is_organization_admin(organization_id));

create policy "klinik yöneticisi üyeliği siler"
  on public.memberships for delete
  to authenticated
  using (public.is_organization_admin(organization_id));

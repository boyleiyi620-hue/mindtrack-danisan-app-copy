-- MindTrack lisans, koltuk ve IBAN tahsilat temeli.

create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public, auth
as $$
  select coalesce((select auth.jwt() -> 'app_metadata' ->> 'mindtrack_role'), '')
    = 'platform_admin';
$$;

create table public.licenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  plan text not null default 'standard'
    check (plan in ('standard', 'clinic', 'enterprise')),
  seats_purchased integer not null check (seats_purchased > 0 and seats_purchased <= 10000),
  storage_quota_bytes bigint not null default 5368709120 check (storage_quota_bytes > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  grace_days integer not null default 0 check (grace_days between 0 and 90),
  status text not null default 'active'
    check (status in ('active', 'expired', 'suspended', 'cancelled')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index licenses_organization_idx on public.licenses (organization_id, ends_at desc);

create table public.license_seats (
  id uuid primary key default gen_random_uuid(),
  license_id uuid not null references public.licenses (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  psychologist_user_id uuid not null references auth.users (id) on delete cascade,
  assigned_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (license_id, psychologist_user_id),
  check (revoked_at is null or revoked_at >= assigned_at)
);

create index license_seats_active_idx on public.license_seats (license_id)
  where revoked_at is null;

create table public.payment_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  license_id uuid references public.licenses (id) on delete set null,
  amount_kurus bigint not null check (amount_kurus > 0),
  period_start date not null,
  period_end date not null,
  paid_at timestamptz not null,
  reference text not null default '',
  note text not null default '',
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  check (period_end >= period_start)
);

create index payment_records_organization_idx
  on public.payment_records (organization_id, paid_at desc);

create table public.audit_log (
  id bigint generated always as identity primary key,
  organization_id uuid references public.organizations (id) on delete set null,
  user_id uuid references auth.users (id) on delete set null,
  action text not null check (length(trim(action)) between 1 and 120),
  entity text not null check (length(trim(entity)) between 1 and 120),
  entity_id text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index audit_log_organization_idx on public.audit_log (organization_id, created_at desc);

create trigger licenses_touch before update on public.licenses
  for each row execute function public.touch_updated_at();

alter table public.licenses enable row level security;
alter table public.license_seats enable row level security;
alter table public.payment_records enable row level security;
alter table public.audit_log enable row level security;

create policy "platform yöneticisi lisansları yönetir" on public.licenses for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy "klinik üyeleri kendi lisansını görür" on public.licenses for select to authenticated
  using (exists (select 1 from public.memberships m where m.organization_id = licenses.organization_id
    and m.user_id = (select auth.uid()) and m.status = 'active'));

create policy "platform yöneticisi koltukları yönetir" on public.license_seats for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy "klinik üyeleri atanmış koltuklarını görür" on public.license_seats for select to authenticated
  using (exists (select 1 from public.memberships m where m.organization_id = license_seats.organization_id
    and m.user_id = (select auth.uid()) and m.status = 'active'));

create policy "platform yöneticisi tahsilatları yönetir" on public.payment_records for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy "klinik yöneticisi tahsilatları görür" on public.payment_records for select to authenticated
  using (exists (select 1 from public.memberships m where m.organization_id = payment_records.organization_id
    and m.user_id = (select auth.uid()) and m.role = 'admin' and m.status = 'active'));

create policy "platform yöneticisi denetim kaydını görür" on public.audit_log for select to authenticated
  using (public.is_platform_admin());

revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated;
revoke all on table public.licenses from anon, authenticated;
revoke all on table public.license_seats from anon, authenticated;
revoke all on table public.payment_records from anon, authenticated;
revoke all on table public.audit_log from anon, authenticated;
grant select, insert, update, delete on public.licenses, public.license_seats, public.payment_records to authenticated;
grant select on public.audit_log to authenticated;

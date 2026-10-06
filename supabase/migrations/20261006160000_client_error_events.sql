-- Klinik veri içermeyen istemci hata günlüğü.
-- Bu tablo bir Sentry alternatifi olarak temel olay geçmişini tutar;
-- dış bildirim kanalı ayrıca yapılandırılabilir.

create table if not exists public.client_error_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete set null,
  user_id uuid not null references auth.users (id) on delete cascade,
  category text not null check (char_length(category) between 1 and 80),
  message text not null check (char_length(message) between 1 and 500),
  severity text not null default 'error'
    check (severity in ('warning', 'error', 'critical')),
  app_version text not null default ''
    check (char_length(app_version) <= 40),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists client_error_events_org_created_idx
  on public.client_error_events (organization_id, created_at desc);
create index if not exists client_error_events_unresolved_idx
  on public.client_error_events (severity, created_at desc)
  where resolved_at is null;

alter table public.client_error_events enable row level security;

create or replace function public.report_client_error(
  p_category text,
  p_message text,
  p_severity text default 'error',
  p_app_version text default ''
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_org uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Oturum bulunamadı';
  end if;
  if p_severity not in ('warning', 'error', 'critical') then
    raise exception 'Geçersiz hata seviyesi';
  end if;

  select m.organization_id into v_org
    from public.memberships m
   where m.user_id = (select auth.uid())
     and m.status = 'active'
   order by m.created_at
   limit 1;

  insert into public.client_error_events (
    organization_id, user_id, category, message, severity, app_version
  ) values (
    v_org,
    (select auth.uid()),
    left(trim(p_category), 80),
    left(trim(p_message), 500),
    p_severity,
    left(trim(coalesce(p_app_version, '')), 40)
  );
end;
$$;

revoke all on table public.client_error_events from public;
revoke all on function public.report_client_error(text, text, text, text) from public;
grant execute on function public.report_client_error(text, text, text, text) to authenticated;

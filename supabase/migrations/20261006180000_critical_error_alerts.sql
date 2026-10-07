alter table public.client_error_events
  add column if not exists alert_claimed_at timestamptz,
  add column if not exists alert_sent_at timestamptz;

grant select, update on table public.client_error_events to service_role;

create index if not exists client_error_events_pending_alert_idx
  on public.client_error_events (created_at)
  where severity = 'critical' and alert_sent_at is null;

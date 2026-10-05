-- Prevent silent last-writer-wins overwrites while the legacy JSON state is
-- being migrated to record-based synchronization.
alter table public.psychologist_state
  add column if not exists state_version bigint not null default 0;

create index if not exists psychologist_state_version_idx
  on public.psychologist_state (psychologist_id, state_version);

-- Remove corrupt pending rows one final time and reject their recreation at the
-- database boundary, including writes from older app bundles.
delete from public.appointments where status = 'pending';

create or replace function public.reject_malformed_pending_appointment()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status = 'pending'
     and (
       new.client_uid is null
       or nullif(btrim(new.client_name), '') is null
       or new.appointment_at >= timestamptz '2099-01-01'
     ) then
    raise exception 'Randevu talebinde danışan veya tarih bilgisi geçersiz.'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists appointments_reject_malformed_pending on public.appointments;
create trigger appointments_reject_malformed_pending
  before insert or update on public.appointments
  for each row execute function public.reject_malformed_pending_appointment();

-- Exercise the same trigger function in isolation before accepting the
-- migration. This catches a guard that compiles but fails to reject sentinels.
create temporary table appointment_guard_probe (
  status text,
  appointment_at timestamptz,
  client_uid uuid,
  client_name text
);
create trigger appointment_guard_probe_trigger
  before insert or update on appointment_guard_probe
  for each row execute function public.reject_malformed_pending_appointment();

do $$
declare
  rejected boolean := false;
begin
  begin
    insert into appointment_guard_probe
      (status, appointment_at, client_uid, client_name)
    values ('pending', timestamptz '2100-01-01', null, 'Bilinmeyen Danışan');
  exception when sqlstate '22023' then
    rejected := true;
  end;
  if not rejected then
    raise exception 'Bozuk pending randevu testi başarısız.';
  end if;
end;
$$;

drop table appointment_guard_probe;

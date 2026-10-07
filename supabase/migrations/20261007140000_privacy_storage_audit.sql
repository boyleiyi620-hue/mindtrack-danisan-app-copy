-- Gizlilik ve denetim sertleştirmesi.
-- Klinik içerik audit_log'a yazılmaz; yalnızca olay türü ve kimlik bilgisi tutulur.

alter table public.patients
  add column if not exists consent_version text not null default '',
  add column if not exists consented_at timestamptz,
  add column if not exists consent_withdrawn_at timestamptz;

create or replace function public.track_patient_consent()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if tg_op = 'INSERT' and new.consented then
    new.consented_at := coalesce(new.consented_at, now());
  elsif tg_op = 'UPDATE' and new.consented and not coalesce(old.consented, false) then
    new.consented_at := coalesce(new.consented_at, now());
    new.consent_withdrawn_at := null;
  elsif tg_op = 'UPDATE' and not new.consented and coalesce(old.consented, false) then
    new.consent_withdrawn_at := coalesce(new.consent_withdrawn_at, now());
  end if;
  return new;
end;
$$;

drop trigger if exists patients_consent_timestamp on public.patients;
create trigger patients_consent_timestamp
  before insert or update of consented on public.patients
  for each row execute function public.track_patient_consent();

grant update (consent_version, consented_at, consent_withdrawn_at)
  on public.patients to authenticated;

-- Belge bucket'ı herkese açık olamaz. Yolun ilk parçası Supabase Auth UUID'sidir.
update storage.buckets
   set public = false
 where id = 'mindtrack-pdfs';

drop policy if exists "mindtrack pdf sahibi okuyabilir" on storage.objects;
create policy "mindtrack pdf sahibi okuyabilir"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "mindtrack pdf sahibi yukleyebilir" on storage.objects;
create policy "mindtrack pdf sahibi yukleyebilir"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "mindtrack pdf sahibi guncelleyebilir" on storage.objects;
create policy "mindtrack pdf sahibi guncelleyebilir"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "mindtrack pdf sahibi silebilir" on storage.objects;
create policy "mindtrack pdf sahibi silebilir"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create or replace function public.capture_privacy_audit()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := (select auth.uid());
  v_org uuid;
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_entity_id text := coalesce(
    v_row->>'id', v_row->>'record_id', v_row->>'user_id', v_row->>'history_id'
  );
begin
  if v_user is null then return new; end if;
  begin
    v_org := nullif(v_row->>'organization_id', '')::uuid;
  exception when invalid_text_representation then
    v_org := null;
  end;
  if v_org is null then
    select m.organization_id into v_org
      from public.memberships m
     where m.user_id = v_user and m.status = 'active'
     order by m.created_at
     limit 1;
  end if;

  insert into public.audit_log (organization_id, user_id, action, entity, entity_id)
  values (v_org, v_user, lower(tg_op), tg_table_name, left(coalesce(v_entity_id, ''), 200));
  return new;
end;
$$;

drop trigger if exists privacy_audit_psychologist_records on public.psychologist_records;
create trigger privacy_audit_psychologist_records
  after insert or update or delete on public.psychologist_records
  for each row execute function public.capture_privacy_audit();

drop trigger if exists privacy_audit_patients on public.patients;
create trigger privacy_audit_patients
  after insert or update or delete on public.patients
  for each row execute function public.capture_privacy_audit();

drop trigger if exists privacy_audit_appointments on public.appointments;
create trigger privacy_audit_appointments
  after insert or update or delete on public.appointments
  for each row execute function public.capture_privacy_audit();

drop trigger if exists privacy_audit_tasks on public.tasks;
create trigger privacy_audit_tasks
  after insert or update or delete on public.tasks
  for each row execute function public.capture_privacy_audit();

drop trigger if exists privacy_audit_homework on public.homework;
create trigger privacy_audit_homework
  after insert or update or delete on public.homework
  for each row execute function public.capture_privacy_audit();

revoke all on function public.capture_privacy_audit() from public;

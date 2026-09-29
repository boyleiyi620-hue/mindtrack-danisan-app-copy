-- =============================================================================
-- MindTrack · RPC'ler, depolama ve gerçek zamanlı yayın
--
-- Danışanın yazma işlemleri SECURITY DEFINER fonksiyonlarla sınırlandırılır.
-- Sebep: Postgres RLS hangi *sütunun* değiştirileceğini kısıtlayamaz. Firestore
-- bunu `affectedKeys().hasOnly([...])` ile yapıyordu; burada karşılığı, yazma
-- işlemini tamamen sunucu tarafına taşımaktır.
--
-- Her fonksiyon `set search_path` ile sabitlenir (search_path ele geçirme riski)
-- ve gövdesinde auth.uid() doğrulanır. SECURITY DEFINER fonksiyonlar varsayılan
-- olarak PUBLIC'e açık olduğu için execute yetkisi en sonda anon'a kapatılır.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Eşleşme kodunu sahiplen
--
-- Firestore kuralı `allow read: if signedIn()` idi; yani oturumu olan herkes
-- tüm bekleyen kodları listeleyebiliyordu. Burada okuma yalnızca sahiplenme
-- anında, atomik bir update içinde gerçekleşir.
-- -----------------------------------------------------------------------------
create function public.claim_pairing_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.pairing_codes;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '42501';
  end if;

  -- Atomik sahiplenme: yalnızca hâlâ bekleyen ve sahipsiz kod eşleşir.
  update public.pairing_codes
     set client_uid = v_uid,
         status     = 'paired',
         updated_at = now()
   where code = upper(btrim(p_code))
     and status = 'pending'
     and client_uid is null
     and expires_at > now()
  returning * into v_row;

  if not found then
    raise exception 'Geçersiz kod.' using errcode = 'P0002';
  end if;

  -- Danışanın kendi satırı da aynı işlem içinde güncellenir. Böylece istemci
  -- tarafında patients tablosuna yazma yetkisi gerekmez; eşleşme tek ve
  -- atomik bir adımda tamamlanır.
  insert into public.patients as p (id, psychologist_id, client_ref, diagnosis_codes)
  values (v_uid, v_row.psychologist_id, v_row.client_ref, v_row.diagnosis_codes)
  on conflict (id) do update
     set psychologist_id = excluded.psychologist_id,
         client_ref       = excluded.client_ref,
         diagnosis_codes  = excluded.diagnosis_codes;

  return jsonb_build_object(
    'code',            v_row.code,
    'psychologistId',  v_row.psychologist_id,
    'clientRef',       v_row.client_ref,
    'diagnosisCodes',  to_jsonb(v_row.diagnosis_codes)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Danışan: randevu iptal / sil
-- -----------------------------------------------------------------------------
create function public.cancel_appointment(p_id uuid, p_by text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '42501';
  end if;

  update public.appointments
     set status       = 'cancelled',
         cancelled_by = coalesce(nullif(btrim(p_by), ''), 'client'),
         updated_at   = now()
   where id = p_id
     and client_uid = v_uid;
end;
$$;

create function public.delete_own_appointment(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '42501';
  end if;

  delete from public.appointments
   where id = p_id
     and client_uid = v_uid;
end;
$$;

-- -----------------------------------------------------------------------------
-- Danışan: form / ödev yanıtı
-- -----------------------------------------------------------------------------
create function public.submit_task(
  p_id uuid,
  p_response text,
  p_answers jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '42501';
  end if;

  update public.tasks
     set done             = true,
         response         = coalesce(p_response, ''),
         structured_answers = coalesce(p_answers, '{}'::jsonb),
         updated_at       = now()
   where id = p_id
     and client_uid = v_uid;
end;
$$;

create function public.submit_homework(p_id uuid, p_response text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '42501';
  end if;

  update public.homework
     set response   = coalesce(p_response, ''),
         status     = 'submitted',
         updated_at = now()
   where id = p_id
     and client_uid = v_uid;
end;
$$;

-- =============================================================================
-- Yetkileri daralt
-- =============================================================================
revoke all on function public.claim_pairing_code(text) from public;
revoke all on function public.cancel_appointment(uuid, text) from public;
revoke all on function public.delete_own_appointment(uuid) from public;
revoke all on function public.submit_task(uuid, text, jsonb) from public;
revoke all on function public.submit_homework(uuid, text) from public;

grant execute on function public.claim_pairing_code(text) to authenticated;
grant execute on function public.cancel_appointment(uuid, text) to authenticated;
grant execute on function public.delete_own_appointment(uuid) to authenticated;
grant execute on function public.submit_task(uuid, text, jsonb) to authenticated;
grant execute on function public.submit_homework(uuid, text) to authenticated;

-- =============================================================================
-- PDF depolama
--
-- Ücretsiz planda 1 GB dosya alanı var. PDF'ler base64 olarak jsonb'ye gömülürse
-- ~%33 büyür ve 500 MB'lık veritabanını çok daha çabuk tüketir; bu yüzden
-- ikili içerik Storage'a, yalnızca küçük metinsel kayıt jsonb'de kalır.
-- Yol biçimi: <psikolog uid>/<dosya id>
-- =============================================================================
insert into storage.buckets (id, name, public)
values ('mindtrack-pdfs', 'mindtrack-pdfs', false)
on conflict (id) do nothing;

create policy "psikolog kendi dosyalarini okur"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "psikolog kendi dosyalarina yazar"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Storage upsert için INSERT + SELECT + UPDATE gerekir.
create policy "psikolog kendi dosyalarini guncelleyebilir"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "psikolog kendi dosyalarini silebilir"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'mindtrack-pdfs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- =============================================================================
-- Gerçek zamanlı yayın
--
-- Firestore'daki .snapshots() dinleyicilerinin karşılığı.
-- =============================================================================
alter publication supabase_realtime add table
  public.psychologist_state,
  public.patients,
  public.appointments,
  public.tasks,
  public.homework;

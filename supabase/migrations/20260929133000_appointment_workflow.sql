-- =============================================================================
-- MindTrack · Ortak randevu yaşam döngüsü
--
-- Danışanın oluşturduğu talep, eşleştiği psikoloğa ait tek ortak randevu
-- kaydıdır. Talep onaylandığında aynı kayıt `planned` olur; böylece iki ayrı
-- kayıt arasında kayma olmaz ve tüm durum değişiklikleri iki uygulamada da
-- Realtime ile anında görünür.
-- =============================================================================

-- Danışan randevu talebini profilindeki eşleşmeye göre oluşturur. Psikolog
-- kimliği, ad ve iletişim bilgileri istemciden alınmaz; sunucu bunları
-- `patients` satırından türetir.
create or replace function public.create_appointment_request(
  p_appointment_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_patient public.patients;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '42501';
  end if;

  select *
    into v_patient
    from public.patients
   where id = v_uid
     and psychologist_id is not null;

  if not found then
    raise exception 'Randevu talebi için önce psikoloğunuzla eşleşmelisiniz.'
      using errcode = 'P0002';
  end if;

  if p_appointment_at <= now() then
    raise exception 'Geçmiş bir tarih veya saat için randevu talebi oluşturulamaz.'
      using errcode = '22007';
  end if;

  insert into public.appointments (
    psychologist_id,
    client_uid,
    client_ref,
    client_name,
    client_first_name,
    client_last_name,
    client_email,
    appointment_at,
    status,
    type
  ) values (
    v_patient.psychologist_id,
    v_uid,
    v_patient.client_ref,
    v_patient.display_name,
    v_patient.first_name,
    v_patient.last_name,
    v_patient.email,
    p_appointment_at,
    'pending',
    'therapy'
  ) returning id into v_id;

  return v_id;
end;
$$;

-- Psikolog bekleyen talebi onaylar. Bu işlem, danışanın takip ettiği aynı
-- satırı planlı randevuya dönüştürür ve psikolog ekranındaki yerel randevu
-- kimliğini ilişkilendirir.
create or replace function public.approve_appointment_request(
  p_id uuid,
  p_appointment_at timestamptz,
  p_linked_appointment_id text
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

  if p_appointment_at <= now() then
    raise exception 'Geçmiş bir tarih veya saat için randevu onaylanamaz.'
      using errcode = '22007';
  end if;

  update public.appointments
     set status                = 'planned',
         appointment_at        = p_appointment_at,
         linked_appointment_id = coalesce(p_linked_appointment_id, ''),
         cancelled_by          = null,
         updated_at            = now()
   where id = p_id
     and psychologist_id = v_uid
     and status = 'pending';

  if not found then
    raise exception 'Bu bekleyen randevu talebi bulunamadı veya daha önce işlendi.'
      using errcode = 'P0002';
  end if;
end;
$$;

-- Psikologun ortak randevuda yaptığı tarih/saat, durum ve ilişki güncellemesi.
-- Sadece randevunun sahibi olan psikolog çağırabilir. Tamamlandı, iptal ve
-- gelmedi durumları ortak satıra yazıldığı için danışan uygulaması da Realtime
-- ile aynı sonucu görür.
create or replace function public.update_shared_appointment(
  p_id uuid,
  p_status text,
  p_appointment_at timestamptz,
  p_linked_appointment_id text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_status text := lower(btrim(coalesce(p_status, '')));
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '42501';
  end if;

  if v_status not in ('planned', 'done', 'cancelled', 'noshow', 'rejected') then
    raise exception 'Geçersiz randevu durumu.' using errcode = '22023';
  end if;

  update public.appointments
     set status                = v_status,
         appointment_at        = p_appointment_at,
         linked_appointment_id = coalesce(p_linked_appointment_id, ''),
         cancelled_by          = case when v_status = 'cancelled' then 'psychologist' else null end,
         updated_at            = now()
   where id = p_id
     and psychologist_id = v_uid;

  if not found then
    raise exception 'Randevu bulunamadı veya bu işlem için yetkiniz yok.'
      using errcode = '42501';
  end if;
end;
$$;

-- Önceki istemci sürümleri de bu RPC'yi çağırdığı için adı korunur; fiziksel
-- silme yerine ortak kaydı iptal eder. Böylece psikolog tarafındaki ve
-- danışan tarafındaki geçmiş tutarlı kalır.
create or replace function public.cancel_appointment(p_id uuid, p_by text)
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
         cancelled_by = 'client',
         updated_at   = now()
   where id = p_id
     and client_uid = v_uid
     and status in ('pending', 'approved', 'planned');

  if not found then
    raise exception 'Bu randevu iptal edilemedi.' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.delete_own_appointment(p_id uuid)
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
         cancelled_by = 'client',
         updated_at   = now()
   where id = p_id
     and client_uid = v_uid
     and status in ('pending', 'approved', 'planned');

  if not found then
    raise exception 'Bu randevu silinemedi.' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.create_appointment_request(timestamptz) from public;
revoke all on function public.approve_appointment_request(uuid, timestamptz, text) from public;
revoke all on function public.update_shared_appointment(uuid, text, timestamptz, text) from public;
revoke all on function public.cancel_appointment(uuid, text) from public;
revoke all on function public.delete_own_appointment(uuid) from public;

grant execute on function public.create_appointment_request(timestamptz) to authenticated;
grant execute on function public.approve_appointment_request(uuid, timestamptz, text) to authenticated;
grant execute on function public.update_shared_appointment(uuid, text, timestamptz, text) to authenticated;
grant execute on function public.cancel_appointment(uuid, text) to authenticated;
grant execute on function public.delete_own_appointment(uuid) to authenticated;

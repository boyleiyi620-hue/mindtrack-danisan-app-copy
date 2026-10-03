-- Önceki hatalı sürümlerin oluşturduğu, danışan adı/tarihi taşımayan bekleyen
-- talepler artık gerçek bir talep olmadığı için ekranda tutulmaz.
delete from public.appointments
 where status = 'pending'
   and (nullif(btrim(client_name), '') is null
        or appointment_at is null);

create or replace function public.reject_appointment_request(p_id uuid)
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
     set status = 'rejected',
         cancelled_by = 'psychologist',
         updated_at = now()
   where id = p_id
     and psychologist_id = v_uid
     and status = 'pending';

  if not found then
    raise exception 'Bu bekleyen randevu talebi bulunamadı veya daha önce işlendi.'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.reject_appointment_request(uuid) from public;
grant execute on function public.reject_appointment_request(uuid) to authenticated;

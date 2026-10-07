-- Kayıt bazlı senkronizasyon için optimistic concurrency RPC.
-- psychologist_state geçiş süresince korunur; bu RPC yeni yazma yolunun
-- her kaydı ayrı sürümle güncellemesini sağlar.

create or replace function public.upsert_psychologist_records(p_records jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
  item jsonb;
  v_type text;
  v_id text;
  v_data jsonb;
  v_expected bigint;
  v_current bigint;
  v_deleted_at timestamptz;
  result jsonb := '[]'::jsonb;
  v_user uuid := (select auth.uid());
  saved jsonb;
begin
  if v_user is null then
    raise exception 'Oturum gerekli';
  end if;
  if jsonb_typeof(p_records) <> 'array' then
    raise exception 'Kayıt listesi geçersiz';
  end if;

  for item in select value from jsonb_array_elements(p_records)
  loop
    v_type := nullif(trim(item->>'record_type'), '');
    v_id := nullif(trim(item->>'record_id'), '');
    v_data := coalesce(item->'data', '{}'::jsonb);
    v_expected := coalesce((item->>'expected_version')::bigint, 0);
    v_deleted_at := nullif(item->>'deleted_at', '')::timestamptz;

    if v_type is null or v_id is null then
      raise exception 'Kayıt kimliği eksik';
    end if;

    select record_version into v_current
      from public.psychologist_records
     where psychologist_id = v_user
       and record_type = v_type
       and record_id = v_id;

    if v_current is null then
      if v_expected <> 0 then
        raise exception 'record_conflict:%:%', v_type, v_id;
      end if;
      insert into public.psychologist_records
        (psychologist_id, record_type, record_id, data, record_version, deleted_at)
      values
        (v_user, v_type, v_id, v_data, 1, v_deleted_at)
      returning jsonb_build_object(
        'record_type', record_type,
        'record_id', record_id,
        'data', data,
        'record_version', record_version,
        'deleted_at', deleted_at
      ) into saved;
    else
      if v_current <> v_expected then
        raise exception 'record_conflict:%:%', v_type, v_id;
      end if;
      update public.psychologist_records
         set data = v_data,
             deleted_at = v_deleted_at,
             record_version = v_current + 1
       where psychologist_id = v_user
         and record_type = v_type
         and record_id = v_id
      returning jsonb_build_object(
        'record_type', record_type,
        'record_id', record_id,
        'data', data,
        'record_version', record_version,
        'deleted_at', deleted_at
      ) into saved;
    end if;
    result := result || jsonb_build_array(saved);
  end loop;
  return result;
end;
$$;

revoke all on function public.upsert_psychologist_records(jsonb) from public;
grant execute on function public.upsert_psychologist_records(jsonb) to authenticated;

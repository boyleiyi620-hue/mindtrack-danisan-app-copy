-- psychologist_state stores the local client directory as JSONB. Normalize it
-- at the database boundary so multiple devices or repeated saves cannot store
-- two client rows with the same email. Appointment references follow the
-- retained client's id.
create or replace function public.deduplicate_state_clients_by_email()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_client jsonb;
  v_appointment jsonb;
  v_clients jsonb := '[]'::jsonb;
  v_appointments jsonb := '[]'::jsonb;
  v_seen jsonb := '{}'::jsonb;
  v_aliases jsonb := '{}'::jsonb;
  v_email text;
  v_id text;
  v_keeper_id text;
  v_replacement text;
begin
  if jsonb_typeof(new.data -> 'clients') is distinct from 'array' then
    return new;
  end if;

  for v_client in
    select value from jsonb_array_elements(new.data -> 'clients')
  loop
    v_id := coalesce(v_client ->> 'id', '');
    v_email := lower(btrim(coalesce(v_client ->> 'email', '')));

    if v_email = '' or not (v_seen ? v_email) then
      v_clients := v_clients || jsonb_build_array(v_client);
      if v_email <> '' then
        v_seen := v_seen || jsonb_build_object(v_email, v_id);
      end if;
    else
      v_keeper_id := v_seen ->> v_email;
      if v_id <> '' and v_keeper_id <> '' then
        v_aliases := v_aliases || jsonb_build_object(v_id, v_keeper_id);
      end if;
      -- Preserve the linked client account id if the retained row lacks it.
      if coalesce(v_client ->> 'clientUserId', '') <> '' then
        select coalesce(
          jsonb_agg(
            case
              when item ->> 'id' = v_keeper_id
                and coalesce(item ->> 'clientUserId', '') = ''
              then jsonb_set(item, '{clientUserId}', v_client -> 'clientUserId', true)
              else item
            end
          ), '[]'::jsonb
        ) into v_clients
        from jsonb_array_elements(v_clients) as source(item);
      end if;
    end if;
  end loop;

  if jsonb_typeof(new.data -> 'appointments') = 'array' then
    for v_appointment in
      select value from jsonb_array_elements(new.data -> 'appointments')
    loop
      v_replacement := v_aliases ->> coalesce(v_appointment ->> 'clientId', '');
      if v_replacement is not null then
        v_appointment := jsonb_set(
          v_appointment,
          '{clientId}',
          to_jsonb(v_replacement),
          true
        );
      end if;
      v_appointments := v_appointments || jsonb_build_array(v_appointment);
    end loop;
    new.data := jsonb_set(new.data, '{appointments}', v_appointments, true);
  end if;

  new.data := jsonb_set(new.data, '{clients}', v_clients, true);
  return new;
end;
$$;

drop trigger if exists psychologist_state_deduplicate_clients on public.psychologist_state;
create trigger psychologist_state_deduplicate_clients
  before insert or update of data on public.psychologist_state
  for each row execute function public.deduplicate_state_clients_by_email();

-- Existing stored snapshots are normalized by the same trigger.
update public.psychologist_state set data = data;

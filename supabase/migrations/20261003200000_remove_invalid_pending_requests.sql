delete from public.appointments
 where status = 'pending'
   and (
     appointment_at >= timestamptz '2099-01-01'
     or nullif(lower(btrim(client_name)), '') is null
     or lower(btrim(client_name)) = 'bilinmeyen danışan'
   );

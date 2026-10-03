-- Clear pending request rows left by older cached client and psychologist
-- bundles. New requests can be created normally after the clients reload.
delete from public.appointments where status = 'pending';

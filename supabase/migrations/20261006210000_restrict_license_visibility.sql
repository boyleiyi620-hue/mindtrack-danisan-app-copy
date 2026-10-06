-- Lisans notları ve klinik koltuk listesi asistanlara/diğer üyelere açılmasın.
-- Psikolog yalnızca kendisine atanmış koltuğu; klinik yöneticisi tüm koltukları görür.

drop policy if exists "klinik üyeleri kendi lisansını görür"
  on public.licenses;
create policy "klinik yöneticileri lisansını görür"
  on public.licenses for select
  to authenticated
  using (public.is_organization_admin(organization_id));

drop policy if exists "klinik üyeleri atanmış koltuklarını görür"
  on public.license_seats;
create policy "klinik yöneticileri koltukları görür"
  on public.license_seats for select
  to authenticated
  using (public.is_organization_admin(organization_id));

create policy "psikolog kendi koltuğunu görür"
  on public.license_seats for select
  to authenticated
  using (
    psychologist_user_id = (select auth.uid())
    and exists (
      select 1
        from public.memberships m
       where m.organization_id = license_seats.organization_id
         and m.user_id = (select auth.uid())
         and m.role = 'psychologist'
         and m.status = 'active'
    )
  );

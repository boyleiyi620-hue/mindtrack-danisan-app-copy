-- Tenant izolasyonu: klinik üyeliği olmayan veya askıya alınmış kullanıcılar
-- psikolog kayıtlarına erişemez. Kişisel kuruluş akışı memberships satırını
-- oluşturduğu için mevcut hesaplar çalışmaya devam eder.

create or replace function public.is_active_clinical_member(
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
      from public.memberships m
     where m.user_id = p_user_id
       and m.status = 'active'
  );
$$;

revoke all on function public.is_active_clinical_member(uuid) from public;
grant execute on function public.is_active_clinical_member(uuid) to authenticated;

drop policy if exists "psikolog kendi durumunu okur"
  on public.psychologist_state;
drop policy if exists "psikolog kendi durumunu yazar"
  on public.psychologist_state;
drop policy if exists "psikolog kendi durumunu günceller"
  on public.psychologist_state;
drop policy if exists "psikolog kendi durumunu siler"
  on public.psychologist_state;

create policy "aktif klinik üyesi kendi durumunu okur"
  on public.psychologist_state for select
  to authenticated
  using (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  );

create policy "aktif klinik üyesi kendi durumunu yazar"
  on public.psychologist_state for insert
  to authenticated
  with check (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  );

create policy "aktif klinik üyesi kendi durumunu günceller"
  on public.psychologist_state for update
  to authenticated
  using (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  )
  with check (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  );

create policy "aktif klinik üyesi kendi durumunu siler"
  on public.psychologist_state for delete
  to authenticated
  using (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  );

drop policy if exists "psikolog kendi kayıtlarını okur"
  on public.psychologist_records;
drop policy if exists "psikolog kendi kayıtlarını yazar"
  on public.psychologist_records;
drop policy if exists "psikolog kendi kayıtlarını günceller"
  on public.psychologist_records;
drop policy if exists "psikolog kendi kayıtlarını siler"
  on public.psychologist_records;

create policy "aktif klinik üyesi kendi kayıtlarını okur"
  on public.psychologist_records for select
  to authenticated
  using (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  );

create policy "aktif klinik üyesi kendi kayıtlarını yazar"
  on public.psychologist_records for insert
  to authenticated
  with check (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  );

create policy "aktif klinik üyesi kendi kayıtlarını günceller"
  on public.psychologist_records for update
  to authenticated
  using (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  )
  with check (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  );

create policy "aktif klinik üyesi kendi kayıtlarını siler"
  on public.psychologist_records for delete
  to authenticated
  using (
    (select auth.uid()) = psychologist_id
    and public.is_active_clinical_member()
  );

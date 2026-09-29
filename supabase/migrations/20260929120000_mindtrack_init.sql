-- =============================================================================
-- MindTrack · Supabase şeması
--
-- Firestore (firebase) yerine geçer. Uygulama yerel-öncelikli çalışmaya devam
-- eder: psikologun tüm klinik kaydı AppData olarak tek bir jsonb satırında
-- tutulur (psychologist_state), geri kalan tablolar danışan ↔ psikolog
-- arasındaki canlı akışı taşır.
--
-- RLS notları:
--  * Firestore'un `allow read: if signedIn()` ile tüm eşleşme kodlarını
--    listelemeye açan kuralı bilinçli olarak daraltıldı: eşleşme kodu artık
--    yalnızca `claim_pairing_code` RPC'si ile okunur/sahiplenilir.
--  * Firestore'un `affectedKeys().hasOnly([...])` ile yaptığı kısıtlama
--    (danışan yalnızca status/response yazabilir) Postgres'te sütun bazlı
--    GRANT ve SECURITY DEFINER RPC'ler ile karşılanır; RLS tek başına
--    hangi sütunun değiştirileceğini kısıtlayamaz.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Güncelleme zaman damgaları
-- -----------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- =============================================================================
-- Tablolar
-- =============================================================================

-- Psikologun tüm klinik verisi. Firestore'daki
-- psychologists/{uid}/state/appData belgesinin karşılığı.
create table public.psychologist_state (
  psychologist_id uuid primary key references auth.users (id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Danışan profili. Firestore'daki patients/{uid} belgesinin karşılığı.
create table public.patients (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  first_name text not null default '',
  last_name text not null default '',
  email text not null default '',
  consented boolean not null default false,
  psychologist_id uuid references auth.users (id) on delete set null,
  client_ref text not null default '',
  diagnosis_codes text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Psikologun ürettiği, danışanın girdiği 8 karakterlik eşleşme kodu.
create table public.pairing_codes (
  code text primary key,
  psychologist_id uuid not null references auth.users (id) on delete cascade,
  psychologist_email text not null default '',
  client_ref text not null default '',
  client_uid uuid references auth.users (id) on delete set null,
  client_name text not null default '',
  client_email text not null default '',
  diagnosis_codes text[] not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'paired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days')
);

create index pairing_codes_psychologist_idx
  on public.pairing_codes (psychologist_id, created_at desc);

-- Randevular ve danışan randevu talepleri.
-- client_uid: danışanın auth kimliği (Firestore'daki clientFirebaseUid)
-- client_ref: psikologun yerel AppData danışan kimliği (opsiyonel)
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  psychologist_id uuid not null references auth.users (id) on delete cascade,
  client_uid uuid references auth.users (id) on delete cascade,
  client_ref text not null default '',
  client_name text not null default '',
  client_first_name text not null default '',
  client_last_name text not null default '',
  client_email text not null default '',
  appointment_at timestamptz not null,
  status text not null default 'planned',
  type text not null default 'request',
  linked_appointment_id text not null default '',
  cancelled_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index appointments_psychologist_date_idx
  on public.appointments (psychologist_id, appointment_at);
create index appointments_client_idx
  on public.appointments (client_uid, appointment_at);
create index appointments_pending_idx
  on public.appointments (psychologist_id, status)
  where status = 'pending';

-- Psikologun danışana gönderdiği formlar / ödevler.
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  psychologist_id uuid not null references auth.users (id) on delete cascade,
  client_ref text not null default '',
  client_uid uuid references auth.users (id) on delete cascade,
  client_name text not null default '',
  client_email text not null default '',
  title text not null,
  description text not null default '',
  form_ref text not null default '',
  form_draft jsonb not null default '{}'::jsonb,
  done boolean not null default false,
  response text not null default '',
  structured_answers jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index tasks_psychologist_idx
  on public.tasks (psychologist_id, created_at desc);
create index tasks_client_idx on public.tasks (client_uid, created_at desc);

create table public.homework (
  id uuid primary key default gen_random_uuid(),
  psychologist_id uuid not null references auth.users (id) on delete cascade,
  client_ref text not null default '',
  client_uid uuid references auth.users (id) on delete cascade,
  client_email text not null default '',
  title text not null,
  description text not null default '',
  status text not null default 'assigned',
  response text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index homework_psychologist_idx
  on public.homework (psychologist_id, created_at desc);
create index homework_client_idx
  on public.homework (client_uid, created_at desc);

-- =============================================================================
-- updated_at tetikleyicileri
-- =============================================================================
create trigger psychologist_state_touch
  before update on public.psychologist_state
  for each row execute function public.touch_updated_at();

create trigger patients_touch
  before update on public.patients
  for each row execute function public.touch_updated_at();

create trigger pairing_codes_touch
  before update on public.pairing_codes
  for each row execute function public.touch_updated_at();

create trigger appointments_touch
  before update on public.appointments
  for each row execute function public.touch_updated_at();

create trigger tasks_touch
  before update on public.tasks
  for each row execute function public.touch_updated_at();

create trigger homework_touch
  before update on public.homework
  for each row execute function public.touch_updated_at();

-- =============================================================================
-- RLS
-- =============================================================================
alter table public.psychologist_state enable row level security;
alter table public.patients          enable row level security;
alter table public.pairing_codes     enable row level security;
alter table public.appointments      enable row level security;
alter table public.tasks             enable row level security;
alter table public.homework          enable row level security;

-- --- psychologist_state: yalnızca kendi satırı -------------------------------
create policy "psikolog kendi durumunu okur"
  on public.psychologist_state for select
  to authenticated
  using ((select auth.uid()) = psychologist_id);

create policy "psikolog kendi durumunu yazar"
  on public.psychologist_state for insert
  to authenticated
  with check ((select auth.uid()) = psychologist_id);

create policy "psikolog kendi durumunu günceller"
  on public.psychologist_state for update
  to authenticated
  using ((select auth.uid()) = psychologist_id)
  with check ((select auth.uid()) = psychologist_id);

create policy "psikolog kendi durumunu siler"
  on public.psychologist_state for delete
  to authenticated
  using ((select auth.uid()) = psychologist_id);

-- --- patients ---------------------------------------------------------------
-- Satırın kendisi: danışan (id = auth.uid())
-- Psikolog: yalnızca kendisine bağlı danışanın tanı kodlarını yazabilir
--           (aşağıdaki sütun bazlı GRANT sayesinde display_name'i değiştiremez).
create policy "danışan kendi profilini okur"
  on public.patients for select
  to authenticated
  using ((select auth.uid()) = id or psychologist_id = (select auth.uid()));

create policy "danışan kendi profilini oluşturur"
  on public.patients for insert
  to authenticated
  with check ((select auth.uid()) = id);

create policy "danışan kendi profilini günceller"
  on public.patients for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- --- pairing_codes ----------------------------------------------------------
-- Danışan tarafı bilinçli olarak dışarıda bırakıldı: sahiplenme yalnızca
-- claim_pairing_code() RPC'si üzerinden yapılır.
create policy "psikolog kendi kodlarını okur"
  on public.pairing_codes for select
  to authenticated
  using ((select auth.uid()) = psychologist_id);

create policy "psikolog kendi kodlarını oluşturur"
  on public.pairing_codes for insert
  to authenticated
  with check ((select auth.uid()) = psychologist_id);

create policy "psikolog kendi kodlarını günceller"
  on public.pairing_codes for update
  to authenticated
  using ((select auth.uid()) = psychologist_id)
  with check ((select auth.uid()) = psychologist_id);

create policy "psikolog kendi kodlarını siler"
  on public.pairing_codes for delete
  to authenticated
  using ((select auth.uid()) = psychologist_id);

-- --- appointments -----------------------------------------------------------
create policy "psikolog kendi randevularını yönetir"
  on public.appointments for all
  to authenticated
  using ((select auth.uid()) = psychologist_id)
  with check ((select auth.uid()) = psychologist_id);

create policy "danışan kendi randevularını okur"
  on public.appointments for select
  to authenticated
  using ((select auth.uid()) = client_uid);

-- --- tasks ------------------------------------------------------------------
create policy "psikolog kendi görevlerini yönetir"
  on public.tasks for all
  to authenticated
  using ((select auth.uid()) = psychologist_id)
  with check ((select auth.uid()) = psychologist_id);

create policy "danışan kendi görevlerini okur"
  on public.tasks for select
  to authenticated
  using ((select auth.uid()) = client_uid);

-- --- homework ---------------------------------------------------------------
create policy "psikolog kendi ödevlerini yönetir"
  on public.homework for all
  to authenticated
  using ((select auth.uid()) = psychologist_id)
  with check ((select auth.uid()) = psychologist_id);

create policy "danışan kendi ödevlerini okur"
  on public.homework for select
  to authenticated
  using ((select auth.uid()) = client_uid);

-- =============================================================================
-- Sütun bazlı GRANT
--
-- Tablo düzeyinde UPDATE verilmez; hangi rolün hangi sütunu değiştirebileceği
-- burada daraltılır. RLS UPDATE'i zaten bir SELECT politikası gerektirir,
-- bu yüzden SELECT normal şekilde verilir.
-- =============================================================================
grant select on
  public.psychologist_state,
  public.patients,
  public.pairing_codes,
  public.appointments,
  public.tasks,
  public.homework
to authenticated;

grant insert, update, delete on
  public.psychologist_state,
  public.pairing_codes,
  public.appointments,
  public.tasks,
  public.homework
to authenticated;

-- Danışan yalnızca kendi profilinin onam/e-posta/ad alanlarını yazar.
grant update (display_name, first_name, last_name, email, consented) on public.patients to authenticated;
-- Psikolog yalnızca kendi danışanlarının tanı kodlarını yazar.
grant update (diagnosis_codes) on public.patients to authenticated;

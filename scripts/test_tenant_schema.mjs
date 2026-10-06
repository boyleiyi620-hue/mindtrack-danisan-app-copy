import { readFile } from 'node:fs/promises';

const migration = await readFile(
  new URL('../supabase/migrations/20261005170000_organizations_memberships.sql', import.meta.url),
  'utf8',
);

const required = [
  'create table public.organizations',
  'create table public.memberships',
  "role in ('admin', 'psychologist', 'assistant')",
  'security definer',
  'create or replace function public.create_organization',
  'alter table public.organizations enable row level security',
  'alter table public.memberships enable row level security',
  'public.is_organization_admin(organization_id)',
  'grant execute on function public.create_organization(text) to authenticated',
];

const hardening = await readFile(
  new URL('../supabase/migrations/20261006130000_tenant_rls_hardening.sql', import.meta.url),
  'utf8',
);

for (const fragment of required) {
  if (!migration.toLowerCase().includes(fragment.toLowerCase())) {
    throw new Error(`Tenant şeması doğrulaması başarısız: ${fragment}`);
  }
}

console.log('Tenant schema checks passed.');

for (const fragment of [
  'create or replace function public.is_active_clinical_member',
  'drop policy if exists "psikolog kendi durumunu okur"',
  'aktif klinik üyesi kendi durumunu okur',
  'aktif klinik üyesi kendi kayıtlarını okur',
  "m.status = 'active'",
]) {
  if (!hardening.toLowerCase().includes(fragment.toLowerCase())) {
    throw new Error(`Tenant RLS doğrulaması başarısız: ${fragment}`);
  }
}

console.log('Tenant RLS hardening checks passed.');

const membershipRpc = await readFile(
  new URL('../supabase/migrations/20261006140000_membership_management_rpc.sql', import.meta.url),
  'utf8',
);
for (const fragment of [
  'create or replace function public.list_organization_members',
  'create or replace function public.manage_organization_member',
  'create or replace function public.set_organization_member_status',
  'Bu e-posta ile kayıtlı MindTrack hesabı bulunamadı',
  'grant execute on function public.manage_organization_member',
]) {
  if (!membershipRpc.toLowerCase().includes(fragment.toLowerCase())) {
    throw new Error(`Üyelik RPC doğrulaması başarısız: ${fragment}`);
  }
}
console.log('Membership management RPC checks passed.');

const assistantRpc = await readFile(
  new URL('../supabase/migrations/20261006150000_assistant_limited_records.sql', import.meta.url),
  'utf8',
);
for (const fragment of [
  'create or replace function public.fetch_assistant_records',
  "r.record_type in ('client', 'appointment')",
  "'name', coalesce(r.data->>'name', '')",
  "'record_type', r.record_type",
  'grant execute on function public.fetch_assistant_records',
]) {
  if (!assistantRpc.toLowerCase().includes(fragment.toLowerCase())) {
    throw new Error(`Asistan görünümü doğrulaması başarısız: ${fragment}`);
  }
}
for (const forbidden of [
  "'notes'",
  "'diagnosisCodes'",
  "'safety'",
  "'financeGoals'",
]) {
  if (assistantRpc.toLowerCase().includes(forbidden.toLowerCase())) {
    throw new Error(`Asistan görünümü hassas alan içeriyor: ${forbidden}`);
  }
}
console.log('Assistant limited-record checks passed.');

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

for (const fragment of required) {
  if (!migration.toLowerCase().includes(fragment.toLowerCase())) {
    throw new Error(`Tenant şeması doğrulaması başarısız: ${fragment}`);
  }
}

console.log('Tenant schema checks passed.');

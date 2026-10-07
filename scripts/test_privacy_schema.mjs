import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile(
  new URL('../supabase/migrations/20261007140000_privacy_storage_audit.sql', import.meta.url),
  'utf8',
);
const auth = await readFile(
  new URL('../lib/screens/auth/auth_screen.dart', import.meta.url),
  'utf8',
);
const telemetry = await readFile(
  new URL('../lib/data/data_store.dart', import.meta.url),
  'utf8',
);

assert.match(migration, /consent_version/);
assert.match(migration, /consented_at/);
assert.match(migration, /consent_withdrawn_at/);
assert.match(migration, /track_patient_consent/);
assert.match(migration, /public\s*=\s*false/i);
assert.match(migration, /storage\.foldername\(name\)/);
assert.match(migration, /capture_privacy_audit/);
assert.match(migration, /create trigger privacy_audit_/);
assert.doesNotMatch(auth, /yalnızca bu cihazda saklanır/i);
assert.match(telemetry, /message:\s*'sync_failure'/);

console.log('Privacy, storage and telemetry checks passed.');

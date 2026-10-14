import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const [vault, blobStore, accountStore, pinScreen, pinSetup, dataStore, build, workflow] =
  await Promise.all([
    read('../web/secure_local_storage.js'),
    read('../lib/data/blob_store_web.dart'),
    read('../lib/data/account_store.dart'),
    read('../lib/screens/auth/pin_screen.dart'),
    read('../lib/screens/auth/pin_setup_dialog.dart'),
    read('../lib/data/data_store.dart'),
    read('./build_web.sh'),
    read('../.github/workflows/build-web.yml'),
  ]);

assert.match(vault, /indexedDB\.open\(DB_NAME, DB_VERSION\)/);
assert.match(vault, /DB_VERSION = 2/);
assert.match(vault, /name: 'AES-GCM', length: 256/);
assert.match(vault, /generateKey\([\s\S]*?false,\s*\['encrypt', 'decrypt'\]/);
assert.match(vault, /additionalData: encoder\.encode\(dataKey\)/);
assert.match(vault, /name: 'PBKDF2'[\s\S]*?iterations, hash: 'SHA-256'/);
assert.match(vault, /const iterations = 600000/);
assert.match(vault, /attempts|writeGeneration/);
assert.match(vault, /removeUserData/);
assert.doesNotMatch(vault, /localStorage\.setItem|localStorage\.getItem/);

assert.match(blobStore, /await _vaultInitialize\(\)\.toDart/);
assert.match(blobStore, /if \(verified != plaintext\)[\s\S]*?legacy\.remove\(key\)/);
assert.match(blobStore, /key == 'mt_users_v1'/);
assert.match(blobStore, /removeUserData\(String userId\)/);
assert.doesNotMatch(blobStore, /localStorage\.setItem|setString\s*\(/);
assert.match(accountStore, /if \(kIsWeb\)[\s\S]*?BlobStore\.instance\.set\(usersKey, encoded\)/);
assert.match(accountStore, /attempts < 5/);
assert.match(accountStore, /30 \* \(1 << exponent\)/);

assert.match(pinSetup, /hashWebPin\(pin\)/);
assert.match(pinScreen, /verifyWebPin\(pin, u\.pinHash, u\.salt\)/);
assert.match(pinScreen, /recordPinFailure\(u\)/);
assert.match(pinScreen, /flushUserWrites\(\)/);
assert.match(dataStore, /Future<void> prepareForLogout\(\)/);
assert.match(dataStore, /!hasUnsyncedChanges/);
assert.match(dataStore, /await BlobStore\.instance\.removeUserData\(user\.id\)/);
assert.match(dataStore, /Son klinik snapshot sunucuya kaydedilemedi/);

assert.match(build, /secure_local_storage\.js/);
assert.match(workflow, /node scripts\/test_web_security\.mjs/);
for (const page of ['../web/index.html', '../web/index_client.html', '../web/index_psychologist.html']) {
  const html = await read(page);
  const vaultScript = html.indexOf('src="secure_local_storage.js"');
  const flutterBoot = html.indexOf('flutter_bootstrap.js');
  assert.ok(vaultScript >= 0 && flutterBoot > vaultScript, `${page} must load secure storage before Flutter`);
}

for (const path of ['../vercel.json', './vercel.json']) {
  const config = JSON.parse(await read(path));
  const secureCacheRule = config.headers.find((rule) => rule.source.includes('secure_local_storage'));
  assert.ok(secureCacheRule, `${path} must define secure script cache policy`);
  assert.ok(
    secureCacheRule.headers.some((header) =>
      header.key === 'Cache-Control' && header.value.includes('max-age=0')),
    `${path} must revalidate the secure script`,
  );
}

console.log('Web encrypted storage, migration, PIN throttling, logout, and cache checks passed.');

// MindTrack web-only encrypted local cache.
// The AES key is non-extractable and stored by IndexedDB's structured clone;
// this protects copied/raw browser storage, not an active same-origin XSS.
(() => {
  'use strict';

  const DB_NAME = 'mindtrack_blobs';
  const DB_VERSION = 2;
  const DATA_STORE = 'kv';
  const KEY_STORE = 'crypto_keys';
  const ENVELOPE = 'mt-aes-gcm:v1:';
  const encoder = new TextEncoder();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let dbPromise;
  let initializePromise;
  const writeGeneration = new Map();

  function transactionDone(tx) {
    return new Promise((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onabort = () => reject(tx.error || new Error('IndexedDB transaction aborted'));
      tx.onerror = () => reject(tx.error || new Error('IndexedDB transaction failed'));
    });
  }

  function requestResult(request) {
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error('IndexedDB request failed'));
    });
  }

  function openDatabase() {
    if (dbPromise) return dbPromise;
    dbPromise = new Promise((resolve, reject) => {
      if (!globalThis.indexedDB) {
        reject(new Error('IndexedDB is unavailable'));
        return;
      }
      let wasBlocked = false;
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains(DATA_STORE)) db.createObjectStore(DATA_STORE);
        if (!db.objectStoreNames.contains(KEY_STORE)) db.createObjectStore(KEY_STORE);
      };
      request.onsuccess = () => {
        const db = request.result;
        if (wasBlocked) {
          db.close();
          return;
        }
        db.onversionchange = () => db.close();
        resolve(db);
      };
      request.onerror = () => reject(request.error || new Error('Could not open encrypted local database'));
      request.onblocked = () => {
        wasBlocked = true;
        reject(new Error('Close older MindTrack tabs to update secure storage'));
      };
    }).catch((error) => {
      dbPromise = undefined;
      throw error;
    });
    return dbPromise;
  }

  function keyIdForDataKey(dataKey) {
    if (!dataKey.startsWith('mt_data_')) return 'app:legacy';
    const userId = dataKey.slice('mt_data_'.length).split(/_(?:recovery|before_restore)_/)[0];
    if (!userId) throw new Error('Invalid account data key');
    return `user:${userId}`;
  }

  function userIdForDataKey(dataKey) {
    if (!dataKey.startsWith('mt_data_')) return null;
    return dataKey.slice('mt_data_'.length).split(/_(?:recovery|before_restore)_/)[0];
  }

  function generationFor(userId) {
    return userId == null ? 0 : (writeGeneration.get(userId) || 0);
  }

  async function getCryptoKey(db, dataKey) {
    const keyId = keyIdForDataKey(dataKey);
    const tx = db.transaction(KEY_STORE, 'readonly');
    const done = transactionDone(tx);
    const stored = await requestResult(tx.objectStore(KEY_STORE).get(keyId));
    await done;
    if (stored) return stored;

    const candidate = await crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 },
      false,
      ['encrypt', 'decrypt'],
    );
    return new Promise((resolve, reject) => {
      const write = db.transaction(KEY_STORE, 'readwrite');
      let selected;
      write.oncomplete = () => resolve(selected);
      write.onabort = () => reject(write.error || new Error('Could not save secure storage key'));
      write.onerror = () => reject(write.error || new Error('Could not save secure storage key'));
      const store = write.objectStore(KEY_STORE);
      const read = store.get(keyId);
      read.onerror = () => write.abort();
      read.onsuccess = () => {
        if (read.result) {
          selected = read.result;
        } else {
          store.put(candidate, keyId);
          selected = candidate;
        }
      };
    });
  }

  function bytesToBase64(bytes) {
    let binary = '';
    const chunkSize = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
    }
    return btoa(binary);
  }

  function base64ToBytes(text) {
    const binary = atob(text);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  async function encryptValue(db, dataKey, plaintext) {
    const key = await getCryptoKey(db, dataKey);
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ciphertext = await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv, additionalData: encoder.encode(dataKey), tagLength: 128 },
      key,
      encoder.encode(plaintext),
    );
    return `${ENVELOPE}${bytesToBase64(iv)}:${bytesToBase64(new Uint8Array(ciphertext))}`;
  }

  async function decryptValue(db, dataKey, envelope) {
    const parts = envelope.slice(ENVELOPE.length).split(':');
    if (parts.length !== 2) throw new Error('Invalid encrypted record format');
    const key = await getCryptoKey(db, dataKey);
    const plaintext = await crypto.subtle.decrypt(
      {
        name: 'AES-GCM',
        iv: base64ToBytes(parts[0]),
        additionalData: encoder.encode(dataKey),
        tagLength: 128,
      },
      key,
      base64ToBytes(parts[1]),
    );
    return decoder.decode(plaintext);
  }

  async function putEncrypted(db, dataKey, plaintext, expectedGeneration) {
    const userId = userIdForDataKey(dataKey);
    const generation = expectedGeneration === undefined
      ? generationFor(userId)
      : expectedGeneration;
    const envelope = await encryptValue(db, dataKey, plaintext);
    if (generationFor(userId) !== generation) {
      throw new Error('Secure write was cancelled by logout');
    }
    const tx = db.transaction(DATA_STORE, 'readwrite');
    const done = transactionDone(tx);
    tx.objectStore(DATA_STORE).put(envelope, dataKey);
    await done;
  }

  async function migratePlaintextIndexedDb(db) {
    const tx = db.transaction(DATA_STORE, 'readonly');
    const done = transactionDone(tx);
    const store = tx.objectStore(DATA_STORE);
    const [keys, values] = await Promise.all([
      requestResult(store.getAllKeys()),
      requestResult(store.getAll()),
    ]);
    await done;
    for (let index = 0; index < keys.length; index += 1) {
      const value = values[index];
      if (typeof value !== 'string') {
        throw new Error('Unsupported value in existing clinical-data store');
      }
      if (!value.startsWith(ENVELOPE)) await putEncrypted(db, String(keys[index]), value);
    }
  }

  async function initialize() {
    if (!globalThis.crypto || !crypto.subtle) {
      throw new Error('Web Crypto is unavailable; plaintext storage is disabled');
    }
    if (!initializePromise) {
      initializePromise = openDatabase()
        .then(async (db) => {
          await migratePlaintextIndexedDb(db);
          return true;
        })
        .catch((error) => {
          initializePromise = undefined;
          throw error;
        });
    }
    return initializePromise;
  }

  async function get(dataKey) {
    const userId = userIdForDataKey(dataKey);
    const generation = generationFor(userId);
    await initialize();
    const db = await openDatabase();
    const tx = db.transaction(DATA_STORE, 'readonly');
    const done = transactionDone(tx);
    const stored = await requestResult(tx.objectStore(DATA_STORE).get(dataKey));
    await done;
    if (stored === undefined || stored === null) return '';
    if (typeof stored !== 'string') throw new Error('Unsupported value in secure local storage');
    if (stored.startsWith(ENVELOPE)) {
      const plaintext = await decryptValue(db, dataKey, stored);
      if (generationFor(userId) !== generation) {
        throw new Error('Secure read was cancelled by logout');
      }
      return plaintext;
    }
    // Handles a legacy tab that wrote a plaintext value during deployment.
    await putEncrypted(db, dataKey, stored, generation);
    return stored;
  }

  async function set(dataKey, plaintext) {
    const userId = userIdForDataKey(dataKey);
    const generation = generationFor(userId);
    await initialize();
    const db = await openDatabase();
    await putEncrypted(db, dataKey, plaintext, generation);
    return true;
  }

  async function remove(dataKey) {
    await initialize();
    const db = await openDatabase();
    const tx = db.transaction(DATA_STORE, 'readwrite');
    const done = transactionDone(tx);
    tx.objectStore(DATA_STORE).delete(dataKey);
    await done;
    return true;
  }

  async function removeUserData(userId) {
    if (!userId || /[\u0000-\u001f]/.test(userId)) throw new Error('Invalid account id');
    writeGeneration.set(userId, generationFor(userId) + 1);
    await initialize();
    const db = await openDatabase();
    const prefix = `mt_data_${userId}`;
    const tx = db.transaction([DATA_STORE, KEY_STORE], 'readwrite');
    const done = transactionDone(tx);
    const data = tx.objectStore(DATA_STORE);
    const keyStore = tx.objectStore(KEY_STORE);
    const read = data.getAllKeys();
    read.onsuccess = () => {
      for (const key of read.result) {
        const value = String(key);
        if (value === prefix || value.startsWith(`${prefix}_`)) data.delete(key);
      }
      keyStore.delete(`user:${userId}`);
    };
    read.onerror = () => tx.abort();
    await done;
    return true;
  }

  function bytesToHex(bytes) {
    return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  }

  function constantTimeEqual(left, right) {
    if (left.length !== right.length) return false;
    let difference = 0;
    for (let i = 0; i < left.length; i += 1) difference |= left.charCodeAt(i) ^ right.charCodeAt(i);
    return difference === 0;
  }

  async function hashPin(pin) {
    if (!globalThis.crypto || !crypto.subtle) throw new Error('Web Crypto is unavailable');
    const iterations = 600000;
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const material = await crypto.subtle.importKey(
      'raw', encoder.encode(pin), 'PBKDF2', false, ['deriveBits'],
    );
    const bits = await crypto.subtle.deriveBits(
      { name: 'PBKDF2', salt, iterations, hash: 'SHA-256' },
      material,
      256,
    );
    return `pbkdf2-sha256$${iterations}$${bytesToBase64(salt)}$${bytesToBase64(new Uint8Array(bits))}`;
  }

  async function verifyPin(pin, storedHash, legacySalt) {
    if (!globalThis.crypto || !crypto.subtle || !storedHash) return false;
    if (!storedHash.startsWith('pbkdf2-sha256$')) {
      const digest = await crypto.subtle.digest(
        'SHA-256',
        encoder.encode(`${legacySalt}::${pin}`),
      );
      return constantTimeEqual(bytesToHex(new Uint8Array(digest)), storedHash.toLowerCase());
    }
    const parts = storedHash.split('$');
    if (parts.length !== 4) return false;
    const iterations = Number(parts[1]);
    if (!Number.isInteger(iterations) || iterations < 100000 || iterations > 2000000) return false;
    let salt;
    let expected;
    try {
      salt = base64ToBytes(parts[2]);
      expected = base64ToBytes(parts[3]);
    } catch (_) {
      return false;
    }
    if (salt.length < 16 || expected.length !== 32) return false;
    const material = await crypto.subtle.importKey(
      'raw', encoder.encode(pin), 'PBKDF2', false, ['deriveBits'],
    );
    const bits = await crypto.subtle.deriveBits(
      { name: 'PBKDF2', salt, iterations, hash: 'SHA-256' },
      material,
      256,
    );
    const actual = new Uint8Array(bits);
    let difference = 0;
    for (let i = 0; i < actual.length; i += 1) difference |= actual[i] ^ expected[i];
    return difference === 0;
  }

  globalThis.mindTrackSecureStorage = Object.freeze({
    initialize,
    get,
    set,
    remove,
    removeUserData,
    hashPin,
    verifyPin,
  });
})();

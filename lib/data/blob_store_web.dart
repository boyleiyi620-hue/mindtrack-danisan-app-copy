// Web için şifreli IndexedDB kasası.
// Düz metin localStorage fallback'i bilerek kaldırılmıştır: güvenli IndexedDB
// ve Web Crypto kullanılamıyorsa başlangıç/yazma güvenli hata verir.
import 'dart:js_interop';

import 'package:shared_preferences/shared_preferences.dart';

@JS('mindTrackSecureStorage.initialize')
external JSPromise<JSBoolean> _vaultInitialize();

@JS('mindTrackSecureStorage.get')
external JSPromise<JSString> _vaultGet(JSString key);

@JS('mindTrackSecureStorage.set')
external JSPromise<JSBoolean> _vaultSet(JSString key, JSString value);

@JS('mindTrackSecureStorage.remove')
external JSPromise<JSBoolean> _vaultRemove(JSString key);

@JS('mindTrackSecureStorage.removeUserData')
external JSPromise<JSBoolean> _vaultRemoveUserData(JSString userId);

@JS('mindTrackSecureStorage.hashPin')
external JSPromise<JSString> _vaultHashPin(JSString pin);

@JS('mindTrackSecureStorage.verifyPin')
external JSPromise<JSBoolean> _vaultVerifyPin(
  JSString pin,
  JSString storedHash,
  JSString legacySalt,
);

class BlobStore {
  BlobStore._();

  static final BlobStore instance = BlobStore._();

  static const String _dataKeyPrefix = 'mt_data_';

  /// Senkron DataStore okumaları için yalnızca bellekte tutulan açık metin.
  final Map<String, String> _cache = <String, String>{};

  SharedPreferences? _legacy;
  bool _ready = false;
  Future<void>? _initializing;

  Future<void> init() async {
    if (_ready) return;
    final inFlight = _initializing;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final attempt = _initialize();
    _initializing = attempt;
    try {
      await attempt;
    } catch (_) {
      if (identical(_initializing, attempt)) _initializing = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    _legacy = await SharedPreferences.getInstance();
    // Secure storage initializes IndexedDB v2, encrypts existing v1 values,
    // and fails closed if browser crypto/storage is unavailable.
    await _vaultInitialize().toDart;
    await _migrateLegacyLocalStorage();
    _ready = true;
  }

  /// Move legacy SharedPreferences/localStorage snapshots only after their
  /// encrypted IndexedDB copy has been written and read back successfully.
  Future<void> _migrateLegacyLocalStorage() async {
    final legacy = _legacy;
    if (legacy == null) return;
    final keys = legacy
        .getKeys()
        .where((key) => key.startsWith(_dataKeyPrefix) || key == 'mt_users_v1')
        .toList(growable: false);
    for (final key in keys) {
      final plaintext = legacy.getString(key);
      if (plaintext == null) continue;
      await _vaultSet(key.toJS, plaintext.toJS).toDart;
      final verified = (await _vaultGet(key.toJS).toDart).toDart;
      if (verified != plaintext) {
        throw StateError('Eski yerel kayıt güvenli kasaya doğrulanamadı.');
      }
      final removed = await legacy.remove(key);
      if (!removed) {
        throw StateError('Eski düz metin yerel kopyası silinemedi.');
      }
    }
  }

  /// DataStore, JSON çözümlemeden önce mevcut hesabın şifresiz eski
  /// IndexedDB/localStorage kaydını güvenli kasaya alır.
  Future<void> preload(String key) async {
    await init();
    if (_cache.containsKey(key)) return;
    final value = (await _vaultGet(key.toJS).toDart).toDart;
    if (value.isNotEmpty) _cache[key] = value;
  }

  /// Senkron okuma yalnızca önceden şifresi çözülmüş bellek kopyasını döndürür.
  String? get(String key) => _cache[key];

  Future<void> set(String key, String value) async {
    await init();
    await _vaultSet(key.toJS, value.toJS).toDart;
    _cache[key] = value;
  }

  Future<void> remove(String key) async {
    await init();
    await _vaultRemove(key.toJS).toDart;
    _cache.remove(key);
    await _legacy?.remove(key);
  }

  /// Çıkıştan önce, eşleşen hesabın snapshot ve recovery kopyalarını ve AES
  /// anahtarını tek IndexedDB işlemiyle kaldırır.
  Future<void> removeUserData(String userId) async {
    await init();
    await _vaultRemoveUserData(userId.toJS).toDart;
    final prefix = '$_dataKeyPrefix$userId';
    _cache.removeWhere(
      (key, _) => key == prefix || key.startsWith('${prefix}_'),
    );
    final legacy = _legacy;
    if (legacy != null) {
      final keys = legacy
          .getKeys()
          .where((key) => key == prefix || key.startsWith('${prefix}_'))
          .toList(growable: false);
      for (final key in keys) {
        if (!await legacy.remove(key)) {
          throw StateError('Eski yerel veri kopyası silinemedi.');
        }
      }
    }
  }

  Future<String> hashWebPin(String pin) async {
    await init();
    return (await _vaultHashPin(pin.toJS).toDart).toDart;
  }

  Future<bool> verifyWebPin(
    String pin,
    String? storedHash,
    String legacySalt,
  ) async {
    if (storedHash == null || storedHash.isEmpty) return false;
    await init();
    return (await _vaultVerifyPin(
      pin.toJS,
      storedHash.toJS,
      legacySalt.toJS,
    ).toDart).toDart;
  }
}

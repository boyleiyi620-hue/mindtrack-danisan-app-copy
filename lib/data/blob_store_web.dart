// Web için büyük veri deposu: IndexedDB.
//
// Neden? Psikologun klinik kaydı (seans notları, form yanıtları, danışanlar)
// 8 danışan/gün temposunda yılda ~8 MB büyüyor ve belge/PDF'lerle birlikte çok
// daha fazla. `localStorage` ~5 MB ile sınırlı olduğu için veri orada tutulamaz.
// IndexedDB ise gigabayt ölçeğindedir.
//
// Üç güvenlik ağı:
//  1. IndexedDB açılamazsa (gizli sekme, eski tarayıcı) yazma/okuma
//     SharedPreferences'a düşer — hiçbir ortamda veri kaybı olmaz.
//  2. `localStorage`'da kalan eski kayıtlar ilk okumada şeffaf biçimde
//     IndexedDB'ye taşınır; kullanıcı yükseltme sonrası verisini kaybetmez.
//  3. Yalnızca oturumdaki hesabın kaydı açılışta belleğe alınır; büyük
//     IndexedDB depoları giriş ekranını bekletmez.
import 'dart:async';

import 'package:indexed_db/indexed_db.dart' as idb;
import 'package:shared_preferences/shared_preferences.dart';

class BlobStore {
  BlobStore._();

  static final BlobStore instance = BlobStore._();

  static const String _dbName = 'mindtrack_blobs';
  static const String _storeName = 'kv';

  /// Bellek önbelleği: `get()` senkron olabilsin diye.
  final Map<String, String> _cache = <String, String>{};

  /// `localStorage`'daki eski kopyalar; yalnızca geçiş ve yedek için okunur.
  SharedPreferences? _legacy;

  idb.Database? _db;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      _legacy = await SharedPreferences.getInstance();
    } catch (_) {
      _legacy = null;
    }
    try {
      if (!idb.IdbFactory.supported) return;
      // `openCreate` in indexed_db 1.0.1 assumes `upgradeneeded` runs on
      // every open. IndexedDB only fires it when a database is first created
      // or upgraded, so reopening an existing database leaves its late locals
      // uninitialized and can stop the entire Flutter web app from starting.
      // Open the known v1 schema directly and create the store only during an
      // actual upgrade; this preserves existing clinical data on later opens.
      _db = await idb.IdbFactory().open(
        _dbName,
        version: 1,
        onUpgradeNeeded: (event) {
          final database = event.target.database;
          if (!(database.objectStoreNames?.contains(_storeName) ?? false)) {
            database.createObjectStore(
              _storeName,
              keyPath: null,
              autoIncrement: false,
            );
          }
        },
      );
    } catch (_) {
      _db = null;
    }
  }

  /// DataStore okumadan önce yalnızca açık hesabın kaydını yükler.
  /// Tüm anahtarları taramak, klinik kayıt büyüdükçe açılışı yavaşlatır.
  Future<void> preload(String key) async {
    if (_cache.containsKey(key)) return;
    final db = _db;
    if (db == null) return;
    try {
      final value = await db
          .transaction(_storeName, 'readonly')
          .objectStore(_storeName)
          .getObject(key);
      if (value is String) _cache[key] = value;
    } catch (_) {
      // Keep the existing localStorage fallback available through get().
    }
  }

  /// Senkron okuma: önce bellek, sonra eski `localStorage` kopyası.
  String? get(String key) {
    final cached = _cache[key];
    if (cached != null) return cached;
    final legacy = _legacy?.getString(key);
    if (legacy == null) return null;
    // Eski kayıt bulundu: belleğe al ve IndexedDB'ye taşı.
    _cache[key] = legacy;
    unawaited(_persist(key, legacy));
    return legacy;
  }

  Future<void> set(String key, String value) async {
    _cache[key] = value;
    await _persist(key, value);
  }

  Future<void> remove(String key) async {
    _cache.remove(key);
    final db = _db;
    if (db != null) {
      try {
        await db
            .transaction(_storeName, 'readwrite')
            .objectStore(_storeName)
            .delete(key);
      } catch (_) {
        // Yazılamadıysa eski kopyadan da silinmeli.
      }
    }
    await _legacy?.remove(key);
  }

  /// IndexedDB'ye yazar; açılamıyorsa `localStorage`'a düşer.
  Future<void> _persist(String key, String value) async {
    final db = _db;
    if (db != null) {
      try {
        await db
            .transaction(_storeName, 'readwrite')
            .objectStore(_storeName)
            .put(value, key);
        return;
      } catch (_) {
        _db = null;
      }
    }
    try {
      final legacy = _legacy ??= await SharedPreferences.getInstance();
      await legacy.setString(key, value);
    } catch (_) {
      // Son çare: veri bellekte durur, uygulama açıkken kaybolmaz.
    }
  }
}

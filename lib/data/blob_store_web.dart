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
//  3. Okuma bellekten senkron döner; IndexedDB hazır değilse alt satıra düşer.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';

import 'dart:html' as html;
import 'package:shared_preferences/shared_preferences.dart';

class BlobStore {
  BlobStore._();

  static final BlobStore instance = BlobStore._();

  static const String _dbName = 'mindtrack_blobs';
  static const String _storeName = 'kv';
  static const int _version = 1;

  /// Bellek önbelleği: `get()` senkron olabilsin diye.
  final Map<String, String> _cache = <String, String>{};

  /// `localStorage`'daki eski kopyalar; yalnızca geçiş ve yedek için okunur.
  SharedPreferences? _legacy;

  html.Database? _db;
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
      final idb = html.window.indexedDB;
      if (idb == null) return;
      _db = await _open(idb);
      if (_db != null) await _loadAll();
    } catch (_) {
      _db = null;
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
        db.transaction(_storeName, 'readwrite').objectStore(_storeName).delete(key);
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
        db.transaction(_storeName, 'readwrite').objectStore(_storeName).put(value, key);
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

  Future<html.Database?> _open(html.IdbFactory idb) async {
    final completer = Completer<html.Database?>();
    late html.IdbOpenDbRequest request;
    try {
      request = idb.open(_dbName, _version);
    } catch (_) {
      return null;
    }
    request.onUpgraded.listen((_) {
      try {
        final db = request.result;
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName);
        }
      } catch (_) {
        if (!completer.isCompleted) completer.complete(null);
      }
    });
    request.onSuccess.listen((_) {
      if (!completer.isCompleted) completer.complete(request.result);
    });
    request.onError.listen((_) {
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  /// Tüm kayıtları belleğe alır; böylece `get()` senkron çalışabilir.
  Future<void> _loadAll() async {
    final db = _db;
    if (db == null) return;
    try {
      final store = db.transaction(_storeName, 'readonly').objectStore(_storeName);
      final request = store.openCursor();
      final completer = Completer<void>();
      request.onSuccess.listen((_) {
        final cursor = request.result;
        if (cursor == null) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        final key = cursor.key;
        final value = cursor.value;
        if (key is String && value is String) _cache[key] = value;
        try {
          cursor.next();
        } catch (_) {
          if (!completer.isCompleted) completer.complete();
        }
      });
      request.onError.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
    } catch (_) {
      // Okuma başarısız olursa yazmalar yine de çalışır.
    }
  }
}

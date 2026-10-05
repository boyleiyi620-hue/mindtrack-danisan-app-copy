// Web dışı platformlar (Android/iOS/masaüstü) için büyük veri deposu.
//
// Burada SharedPreferences kullanılır; davranış eskisiyle birebir aynıdır.
// Web sürümü `blob_store_web.dart` ile değiştirilir.
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class BlobStore {
  BlobStore._();

  static final BlobStore instance = BlobStore._();

  SharedPreferences? _prefs;
  bool _ready = false;

  /// Depoyu hazırlar. Uygulama açılışında bir kez çağrılır.
  Future<void> init() async {
    if (_ready) return;
    _prefs ??= await SharedPreferences.getInstance();
    _ready = true;
  }

  /// SharedPreferences doğrudan okunur; yerel platformlarda ön yükleme gerekmez.
  Future<void> preload(String _) async {}

  /// Senkron okuma.
  String? get(String key) => _prefs?.getString(key);

  Future<void> set(String key, String value) async {
    final prefs = _prefs;
    if (prefs == null) await init();
    await _prefs?.setString(key, value);
  }

  Future<void> remove(String key) async {
    await _prefs?.remove(key);
  }
}

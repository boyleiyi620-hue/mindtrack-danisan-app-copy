import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_account.dart';
import 'blob_store.dart';

/// Yerel hesap deposu — web'de localStorage, mobilde kalıcı depolama.
class AccountStore {
  static const usersKey = 'mt_users_v1';
  static const sessionKey = 'mt_session_v1';
  static const lockedKey = 'mt_locked_v1';
  static const dataKeyPrefix = 'mt_data_';

  final SharedPreferences prefs;
  List<UserAccount> users = [];
  UserAccount? current;

  AccountStore(this.prefs) {
    _load();
  }

  /// Hesap deposunu hazırlar.
  ///
  /// Büyük klinik kaydının tutulduğu [BlobStore] da burada başlatılır; veri
  /// deposu `DataStore` kurulmadan **önce** hazır olmalıdır. Aksi halde ilk
  /// okuma boş döner ve mevcut kayıt üzerine yazılabilir.
  static Future<AccountStore> init() async {
    final prefs = await SharedPreferences.getInstance();
    final store = AccountStore(prefs);
    await BlobStore.instance.init();
    final current = store.current;
    if (current != null) {
      await BlobStore.instance.preload(store.dataKey(current));
    }
    return store;
  }

  void _load() {
    final raw = prefs.getString(usersKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        users = (jsonDecode(raw) as List)
            .map((e) => UserAccount.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        users = [];
      }
    }
    final sid = prefs.getString(sessionKey);
    if (sid != null && sid.isNotEmpty) {
      for (final u in users) {
        if (u.id == sid) {
          current = u;
          break;
        }
      }
    }
  }

  void saveUsers() {
    prefs.setString(
        usersKey, jsonEncode(users.map((u) => u.toJson()).toList()));
  }

  UserAccount? findByEmail(String email) {
    final e = email.trim().toLowerCase();
    for (final u in users) {
      if (u.email.toLowerCase() == e) return u;
    }
    return null;
  }

  /// Supabase kimliği, e-postadan daha güçlü hesap kimliğidir. E-posta
  /// eşleşmesi eski yerel kayıtları yanlış oturumla birleştirmemelidir.
  UserAccount? findByAuthUserId(String authUserId) {
    for (final u in users) {
      if (u.authUserId == authUserId) return u;
    }
    return null;
  }

  void addUser(UserAccount u) {
    users.add(u);
    saveUsers();
  }

  void updateUser(UserAccount u) => saveUsers();

  void setSession(UserAccount u) {
    current = u;
    prefs.setString(sessionKey, u.id);
  }

  void clearSession() {
    current = null;
    prefs.remove(sessionKey);
    prefs.remove(lockedKey);
  }

  bool get isLocked => prefs.getBool(lockedKey) ?? false;

  void setLocked(bool value) => prefs.setBool(lockedKey, value);

  /// Kullanıcıya özel veri anahtarı (veri katmanında kullanılır).
  String dataKey(UserAccount u) => dataKeyPrefix + u.id;
}

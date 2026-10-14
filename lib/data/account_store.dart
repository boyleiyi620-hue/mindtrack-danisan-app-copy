import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_account.dart';
import 'blob_store.dart';

/// Yerel hesap deposu — web'de şifreli IndexedDB, mobilde kalıcı depolama.
class AccountStore {
  static const usersKey = 'mt_users_v1';
  static const sessionKey = 'mt_session_v1';
  static const lockedKey = 'mt_locked_v1';
  static const dataKeyPrefix = 'mt_data_';

  final SharedPreferences prefs;
  List<UserAccount> users = [];
  UserAccount? current;
  Future<void> _userSaveChain = Future<void>.value();

  AccountStore(this.prefs) {
    _loadUsers(prefs.getString(usersKey));
    _loadSession();
  }

  AccountStore._web(this.prefs) {
    _loadUsers(BlobStore.instance.get(usersKey));
    _loadSession();
  }

  /// Hesap ve veri depolarını hazırlar. Web'de klinik snapshot'lar ve kullanıcı
  /// doğrulama özetleri yalnızca şifreli IndexedDB'den okunur.
  static Future<AccountStore> init() async {
    final prefs = await SharedPreferences.getInstance();
    await BlobStore.instance.init();
    if (kIsWeb) await BlobStore.instance.preload(usersKey);
    final store = kIsWeb ? AccountStore._web(prefs) : AccountStore(prefs);
    final current = store.current;
    if (current != null) {
      await BlobStore.instance.preload(store.dataKey(current));
    }
    return store;
  }

  void _loadUsers(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      users = (jsonDecode(raw) as List)
          .map((e) => UserAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      users = [];
    }
  }

  void _loadSession() {
    final sid = prefs.getString(sessionKey);
    if (sid == null || sid.isEmpty) return;
    for (final u in users) {
      if (u.id == sid) {
        current = u;
        break;
      }
    }
  }

  void saveUsers() {
    final encoded = jsonEncode(users.map((u) => u.toJson()).toList());
    if (kIsWeb) {
      // Keep account metadata (including the versioned PIN hash) encrypted at
      // rest. Recover a failed prior write only when a new save is requested.
      _userSaveChain = _userSaveChain
          .catchError((Object _) {})
          .then((_) => BlobStore.instance.set(usersKey, encoded));
    } else {
      unawaited(prefs.setString(usersKey, encoded));
    }
  }

  Future<void> flushUserWrites() => _userSaveChain;

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
    unawaited(prefs.setString(sessionKey, u.id));
  }

  void clearSession() {
    current = null;
    unawaited(prefs.remove(sessionKey));
    unawaited(prefs.remove(lockedKey));
  }

  bool get isLocked => prefs.getBool(lockedKey) ?? false;

  void setLocked(bool value) => unawaited(prefs.setBool(lockedKey, value));

  /// Web PIN denemeleri için tarayıcı kapanıp açılsa da süren kademeli fren.
  Duration pinLockRemaining(UserAccount user) {
    final until = prefs.getInt('mt_pin_locked_until_v1_${user.id}');
    if (until == null) return Duration.zero;
    final remaining = until - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  Future<Duration> recordPinFailure(UserAccount user) async {
    final attemptKey = 'mt_pin_attempts_v1_${user.id}';
    final untilKey = 'mt_pin_locked_until_v1_${user.id}';
    final attempts = (prefs.getInt(attemptKey) ?? 0) + 1;
    if (!await prefs.setInt(attemptKey, attempts)) {
      throw StateError('PIN deneme sınırı yerel olarak kaydedilemedi.');
    }
    if (attempts < 5) return Duration.zero;
    final exponent = (attempts - 5).clamp(0, 4);
    final delay = Duration(seconds: 30 * (1 << exponent));
    final until = DateTime.now().add(delay).millisecondsSinceEpoch;
    if (!await prefs.setInt(untilKey, until)) {
      throw StateError('PIN bekleme süresi yerel olarak kaydedilemedi.');
    }
    return delay;
  }

  Future<void> resetPinFailures(UserAccount user) async {
    await prefs.remove('mt_pin_attempts_v1_${user.id}');
    await prefs.remove('mt_pin_locked_until_v1_${user.id}');
  }

  /// Kullanıcıya özel veri anahtarı (veri katmanında kullanılır).
  String dataKey(UserAccount u) => dataKeyPrefix + u.id;

  Future<void> preloadUserData(UserAccount user) =>
      BlobStore.instance.preload(dataKey(user));
}

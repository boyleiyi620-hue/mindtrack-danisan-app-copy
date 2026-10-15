import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_data.dart';
import '../models/appointment.dart';
import '../models/assessment.dart';
import '../models/client.dart';
import '../models/document.dart';
import '../models/form_entry.dart';
import '../models/note.dart';
import '../models/pdf_library.dart';
import '../models/plan.dart';
import '../models/task.dart';
import '../models/user_account.dart';
import '../utils/formats.dart';
import 'account_store.dart';
import 'blob_store.dart';
import 'appointment_sync.dart';
import 'client_deduplication.dart' as client_dedup;
import 'mindtrack_backend.dart';
import 'binary_blobs.dart';
import 'record_sync.dart';
import 'sync_status.dart';

/// Kullanıcıya özel veri deposu — her değişiklikte kaydeder ve ekranlara haber verir.
class DataStore extends ChangeNotifier {
  final AccountStore accounts;
  AppData data = AppData.empty();
  int _uidCounter = 0;
  bool _remoteLoading = false;
  bool _remoteSaving = false;
  String? _pendingRemoteEncoded;
  int? _pendingRemoteRevision;
  UserAccount? _pendingRemoteUser;
  int? _pendingRemoteSessionGeneration;
  Timer? _remoteSaveTimer;
  StreamSubscription<RemoteStateSnapshot?>? _remoteSubscription;
  StreamSubscription<Map<String, dynamic>>? _recordSubscription;
  Future<void> _localSaveChain = Future<void>.value();
  int _saveRevision = 0;
  int _persistedRevision = 0;
  int _remoteVersion = 0;
  bool _recordSyncAvailable = false;
  bool _recordSyncActive = false;
  AppData _remoteRecordData = AppData.empty();
  Map<String, Map<String, dynamic>> _remoteRecordRows =
      <String, Map<String, dynamic>>{};
  Map<String, int> _recordVersions = <String, int>{};
  DateTime? _recordSignalCursor;
  bool _recordReconcileRunning = false;
  final Set<String> _pendingLocalDeletes = <String>{};
  Set<String> _lastLocalRecordKeys = <String>{};
  String? _pendingLocalDeletesOwnerId;

  // --- Kalıcı senkronizasyon durumu ---------------------------------------
  // Uzak yazma başarısız olduğunda yerel snapshot diske alınır ve "kirli"
  // işareti korunur; sonraki açılışta yeniden senkronizasyon başlatılır.
  SyncPhase _phase = SyncPhase.idle;
  int _failures = 0;
  DateTime? _lastSyncedAt;
  DateTime? _lastErrorAt;
  String? _syncMessage;
  Timer? _retryTimer;
  bool _disposed = false;
  bool _logoutPreparing = false;
  int _sessionGeneration = 0;
  String? _loadedUserId;
  String? _loadedAuthUserId;
  String? _lastReportedError;
  DateTime? _lastReportedErrorAt;

  static const String _appVersion = '1.0.1+2';

  /// Tekrarlanan denemelerde beklenecek süreler (üstel geri çekilme).
  /// Son adımda 10 dakikada bir denemeye düşer.
  static const List<Duration> _backoff = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  String _dirtyKey(UserAccount u) => 'mt_dirty_v2_${u.id}';
  String _syncedAtKey(UserAccount u) => 'mt_synced_at_v2_${u.id}';
  String _pendingLocalDeletesKey(UserAccount u) =>
      'mt_pending_deletes_v1_${u.id}';

  final bool _allowUnauthenticatedLocalForTesting;

  DataStore(this.accounts, {bool autoLoad = true})
    : _allowUnauthenticatedLocalForTesting = false {
    if (autoLoad) load();
  }

  @visibleForTesting
  DataStore.testOffline(this.accounts, {bool autoLoad = true})
    : _allowUnauthenticatedLocalForTesting = true {
    if (autoLoad) load();
  }

  bool get hasAccount => accounts.current != null;

  bool _isCurrentSession(UserAccount user, int generation) {
    if (_disposed || generation != _sessionGeneration) return false;
    final current = accounts.current;
    if (current?.id != user.id || current?.authUserId != user.authUserId) {
      return false;
    }
    final backend = MindTrackBackend.instance;
    if (backend.isSignedIn) {
      return user.authUserId != null && backend.userId == user.authUserId;
    }
    // An offline token refresh must not expose local clinical data without a
    // matching authenticated account. Only explicitly opted-in tests may use
    // an unauthenticated local store.
    return _allowUnauthenticatedLocalForTesting && !kReleaseMode;
  }

  void _beginSession(UserAccount? user) {
    _sessionGeneration++;
    _loadedUserId = user?.id;
    _loadedAuthUserId = user?.authUserId;
    _remoteSubscription?.cancel();
    _remoteSubscription = null;
    _recordSubscription?.cancel();
    _recordSubscription = null;
    _remoteSaveTimer?.cancel();
    _remoteSaveTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _remoteLoading = false;
    _pendingRemoteEncoded = null;
    _pendingRemoteRevision = null;
    _pendingRemoteUser = null;
    _pendingRemoteSessionGeneration = null;
    _saveRevision = 0;
    _persistedRevision = 0;
    _remoteVersion = 0;
    _recordSyncAvailable = false;
    _recordSyncActive = false;
    _remoteRecordData = AppData.empty();
    _remoteRecordRows = <String, Map<String, dynamic>>{};
    _recordVersions = <String, int>{};
    _recordSignalCursor = null;
    _recordReconcileRunning = false;
    _pendingLocalDeletes.clear();
    _inflightDownloads.clear();
    _lastLocalRecordKeys = <String>{};
    _pendingLocalDeletesOwnerId = null;
    _phase = SyncPhase.idle;
    _failures = 0;
    _lastSyncedAt = null;
    _lastErrorAt = null;
    _syncMessage = null;
    _logoutPreparing = false;
    _lastReportedError = null;
    _lastReportedErrorAt = null;
    data = AppData.empty();
  }

  /// Asistan oturumları yalnızca sunucunun süzdüğü dizin/randevu özetlerini
  /// okuyabilir; klinik JSON kayıtlarına hiçbir şekilde yazamaz.
  bool get isAssistantReadOnly =>
      accounts.current?.organizationRole == 'assistant' &&
      accounts.current?.organizationId != null;

  String newId() {
    _uidCounter++;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${_uidCounter.toRadixString(16)}';
  }

  SharedPreferences get _prefs => accounts.prefs;

  /// Oturumdaki kullanıcının verilerini yükler.
  void load() {
    final u = accounts.current;
    if (_loadedUserId != u?.id || _loadedAuthUserId != u?.authUserId) {
      _beginSession(u);
    }
    if (u == null) {
      data = AppData.empty();
      notifyListeners();
      return;
    }
    final generation = _sessionGeneration;
    _logoutPreparing = false;
    // Yerel klinik önbelleği yalnızca onu oluşturan Supabase hesabıyla
    // birlikte açılabilir. Kimlik doğrulanmamış/eski oturumda gösterme.
    if (!_isCurrentSession(u, generation)) {
      if (_loadedUserId != null || _loadedAuthUserId != null) {
        _beginSession(null);
      } else {
        _remoteSubscription?.cancel();
        _remoteSubscription = null;
        _recordSubscription?.cancel();
        _recordSubscription = null;
      }
      data = AppData.empty();
      notifyListeners();
      return;
    }
    final localKey = accounts.dataKey(u);
    try {
      final raw = BlobStore.instance.get(localKey);
      if (raw != null && raw.isNotEmpty) {
        data = AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (deduplicateClientsByEmail()) {
          unawaited(
            BlobStore.instance.set(
              accounts.dataKey(u),
              jsonEncode(data.toJson()),
            ),
          );
        }
      } else {
        data = AppData.empty();
      }
    } catch (_) {
      // Bozuk/yarım kalmış snapshot'ı silmek yerine kurtarma kopyası olarak
      // sakla. Böylece açılışta veri kaybı yaşanırsa ham kayıt incelenebilir.
      final raw = BlobStore.instance.get(localKey);
      if (raw != null && raw.isNotEmpty) {
        final recoveryKey =
            '${localKey}_recovery_${DateTime.now().microsecondsSinceEpoch}';
        unawaited(BlobStore.instance.set(recoveryKey, raw).catchError((_) {}));
      }
      data = AppData.empty();
    }
    if (isAssistantReadOnly) {
      // Asistan önbelleği de yalnızca sunucudan süzülen görünümle yenilenir;
      // eski bir psikolog snapshot'ı yanlışlıkla ekrana taşınmaz.
      data = AppData.empty();
    }
    _loadPendingLocalDeletes(u);
    _lastLocalRecordKeys = recordKeysFromAppData(data);
    _restoreSyncState(u);
    notifyListeners();
    unawaited(_loadRemote());
  }

  void _loadPendingLocalDeletes(UserAccount user) {
    _pendingLocalDeletes.clear();
    _pendingLocalDeletesOwnerId = user.id;
    if (!kIsWeb || isAssistantReadOnly) return;
    final raw = _prefs.getString(_pendingLocalDeletesKey(user));
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _pendingLocalDeletes.addAll(
          decoded
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty),
        );
      }
    } catch (_) {
      // A damaged queue is ignored; the original local snapshot remains intact.
    }
  }

  Future<void> _persistPendingLocalDeletes(
    UserAccount user,
    Set<String> keys,
  ) async {
    if (!kIsWeb) return;
    final ordered = keys.toList()..sort();
    final saved = await _prefs.setString(
      _pendingLocalDeletesKey(user),
      jsonEncode(ordered),
    );
    if (!saved) throw StateError('Silme kuyruğu yerel depoya yazılamadı.');
  }

  /// Kullanıcının diskte kalan senkronizasyon durumunu geri yükler.
  /// Uygulama çevrimdışı açıldığında arayüz doğru uyarıyı gösterebilsin.
  void _restoreSyncState(UserAccount u) {
    final stamped = _prefs.getDouble(_syncedAtKey(u));
    _lastSyncedAt = stamped == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(stamped.round());
    final dirty =
        (_prefs.getBool(_dirtyKey(u)) ?? false) ||
        _pendingLocalDeletes.isNotEmpty;
    if (dirty) {
      _failures = 0;
      _phase = SyncPhase.pending;
      _syncMessage = 'Son değişiklikler gönderilecek';
    } else {
      _phase = SyncPhase.idle;
      _syncMessage = null;
    }
  }

  /// Supabase oturumu açıldıktan sonra telefon/web senkronunu başlatır.
  Future<void> startRemoteSync() => _loadRemote();

  Future<void> _loadRemote() async {
    final localUser = accounts.current;
    final generation = _sessionGeneration;
    if (localUser == null ||
        _remoteLoading ||
        !_isCurrentSession(localUser, generation)) {
      return;
    }
    final backend = MindTrackBackend.instance;
    if (!backend.isSignedIn) return;
    _remoteLoading = true;
    try {
      await _remoteSubscription?.cancel();
      await _recordSubscription?.cancel();
      _remoteSubscription = null;
      _recordSubscription = null;
      if (!_isCurrentSession(localUser, generation) || _logoutPreparing) return;
      if (localUser.organizationRole == 'assistant' &&
          localUser.organizationId != null) {
        final rows = await backend.fetchAssistantRecords(
          localUser.organizationId!,
        );
        if (!_isCurrentSession(localUser, generation) || _logoutPreparing) {
          return;
        }
        final next = appDataFromRecords(rows);
        data = next;
        _lastLocalRecordKeys = recordKeysFromAppData(data);
        _recordSyncAvailable = false;
        _recordSyncActive = false;
        await BlobStore.instance.set(
          accounts.dataKey(localUser),
          jsonEncode(data.toJson()),
        );
        notifyListeners();
        return;
      }
      final rows = await backend.fetchPsychologistRecords(
        expectedUserId: localUser.authUserId!,
      );
      if (!_isCurrentSession(localUser, generation) || _logoutPreparing) return;
      _recordSyncAvailable = true;
      _remoteRecordRows = <String, Map<String, dynamic>>{
        for (final row in rows)
          syncRecordKey(row): Map<String, dynamic>.from(row),
      };
      _recordSignalCursor = SyncCursor.fromRows(rows)?.updatedAt;
      if (!_isCurrentSession(localUser, generation) || _logoutPreparing) return;
      if (rows.isNotEmpty) {
        _recordSyncActive = true;
        _recordVersions = recordVersionsFromRows(rows);
        final remoteData = appDataFromRecords(rows);
        carryLocalBinaries(remoteData, data);
        await _hydratePdfs(remoteData, localUser, generation);
        if (!_isCurrentSession(localUser, generation) || _logoutPreparing) {
          return;
        }
        // The first record fetch used to replace the local snapshot directly,
        // unlike later Realtime updates. On web, preserve a pending offline
        // snapshot and let _resumePendingSync diff it against this remote base.
        _remoteRecordData = remoteData;
        final preserveLocalChanges =
            hasUnsyncedChanges ||
            _pendingLocalDeletes.isNotEmpty ||
            _saveRevision > _persistedRevision ||
            _pendingRemoteEncoded != null ||
            _remoteSaving;
        data = AppData.reconcileInitialRemote(
          remote: remoteData,
          local: data,
          preserveLocalChanges: preserveLocalChanges,
        );
        if (preserveLocalChanges) {
          data = removeRecordsByKey(data, _pendingLocalDeletes);
        }
        _lastLocalRecordKeys = recordKeysFromAppData(data);
        final encoded = jsonEncode(data.toJson());
        await _persistLoadedSnapshot(
          localUser,
          encoded,
          sessionGeneration: generation,
        );
        if (!_isCurrentSession(localUser, generation) || _logoutPreparing) {
          return;
        }
        if (preserveLocalChanges) {
          unawaited(
            _saveRemote(
              encoded,
              revision: _saveRevision,
              user: localUser,
              sessionGeneration: generation,
            ),
          );
        }
        notifyListeners();
        _recordSubscription = backend
            .watchPsychologistRecordSignals(
              expectedUserId: localUser.authUserId!,
            )
            .listen((signal) {
              if (signal['__reconcile__'] == true) {
                unawaited(reconcileRemoteChanges());
              } else {
                unawaited(
                  _applyRemoteRecordSignal(signal, localUser, generation),
                );
              }
            }, onError: (_) => unawaited(reconcileRemoteChanges()));
      } else {
        _remoteSubscription = backend.watchState().listen(
          (remote) => _applyRemoteState(remote, localUser, generation),
          onError: (_) {},
        );
        // A new account may have no record rows yet and still write its first
        // changes through the record RPC. Keep listening so another device
        // does not wait for a full reload to see those changes.
        _recordSubscription = backend
            .watchPsychologistRecordSignals(
              expectedUserId: localUser.authUserId!,
            )
            .listen((signal) {
              if (signal['__reconcile__'] == true) {
                unawaited(reconcileRemoteChanges());
              } else {
                unawaited(
                  _applyRemoteRecordSignal(signal, localUser, generation),
                );
              }
            }, onError: (_) => unawaited(reconcileRemoteChanges()));
      }
    } catch (_) {
      if (!_isCurrentSession(localUser, generation) || _logoutPreparing) return;
      // Eski kurulumlarda psychologist_records henüz yoktur.
      _recordSyncAvailable = false;
      if (localUser.organizationRole == 'assistant') {
        data = AppData.empty();
        notifyListeners();
        _remoteLoading = false;
        return;
      }
      _remoteSubscription = backend.watchState().listen(
        (remote) => _applyRemoteState(remote, localUser, generation),
        onError: (_) {},
      );
    } finally {
      if (generation == _sessionGeneration) {
        _remoteLoading = false;
        if (_isCurrentSession(localUser, generation)) _resumePendingSync();
      }
    }
  }

  Future<void> _persistLoadedSnapshot(
    UserAccount user,
    String encoded, {
    required int sessionGeneration,
  }) async {
    final write = _localSaveChain.then((_) async {
      if (_logoutPreparing || !_isCurrentSession(user, sessionGeneration)) {
        return;
      }
      await BlobStore.instance.set(accounts.dataKey(user), encoded);
    });
    _localSaveChain = write.catchError((Object error) {
      if (_isCurrentSession(user, sessionGeneration)) {
        _onRemoteFailed(
          StateError('Yerel kayıt tamamlanamadı: ${_describeSyncError(error)}'),
          user: user,
          sessionGeneration: sessionGeneration,
        );
      }
    });
    await _localSaveChain;
  }

  Future<void> _applyRemoteState(
    RemoteStateSnapshot? snapshot,
    UserAccount localUser,
    int generation,
  ) async {
    if (snapshot == null ||
        _logoutPreparing ||
        !_isCurrentSession(localUser, generation) ||
        _recordSyncActive) {
      return;
    }
    try {
      // Bu cihazda sunucuya gitmemiş değişiklik varsa gelen durum
      // koşulsuz üzerine yazılırsa notlar kaybolur. Önce yerel
      // değişiklikler yazılır; ardından gelen durum bir sonraki
      // bildirimde kendi haline gelir.
      // Uzak olay, kendi yazmamızın Realtime yankısı olsa bile yerel kirli
      // işaret temizlenmeden uygulanmamalı. Aksi halde yazma sürerken gelen
      // olay son yerel değişikliği tekrar eski uzak kopyayla ezebilir.
      if (hasUnsyncedChanges) {
        _remoteVersion = snapshot.version;
        final remoteData = AppData.fromJson(snapshot.data);
        carryLocalBinaries(remoteData, data);
        _remoteRecordData = remoteData;
        data = removeRecordsByKey(
          AppData.mergePreservingLocal(remoteData, data),
          _pendingLocalDeletes,
        );
        _lastLocalRecordKeys = recordKeysFromAppData(data);
        final merged = jsonEncode(data.toJson());
        unawaited(BlobStore.instance.set(accounts.dataKey(localUser), merged));
        notifyListeners();
        unawaited(
          _saveRemote(merged, user: localUser, sessionGeneration: generation),
        );
        return;
      }
      _remoteVersion = snapshot.version;
      final next = AppData.fromJson(snapshot.data);
      final removedDuplicates = deduplicateClientsByEmail(next);
      // Sunucu gövdeyi taşımaz; bu cihazda indirilmiş belgeler
      // korunur, olmayanlar ilk açıldığında indirilir.
      carryLocalBinaries(next, data);
      await _hydratePdfs(next, localUser, generation);
      if (_logoutPreparing || !_isCurrentSession(localUser, generation)) return;
      final encoded = jsonEncode(next.toJson());
      _remoteRecordData = next;
      data = next;
      _lastLocalRecordKeys = recordKeysFromAppData(data);
      await BlobStore.instance.set(accounts.dataKey(localUser), encoded);
      if (_logoutPreparing || !_isCurrentSession(localUser, generation)) return;
      notifyListeners();
      if (removedDuplicates) {
        unawaited(
          _saveRemote(encoded, user: localUser, sessionGeneration: generation),
        );
      }
    } catch (_) {
      // Bozuk uzak veri mevcut yerel verinin üzerine yazılmaz.
    }
  }

  /// Delta reconciliation is used on resume, Realtime reconnect, and the
  /// foreground fallback. It first reads metadata-only signals; older servers
  /// without the draft signal migration use an updated_at delta query instead.
  Future<void> reconcileRemoteChanges() async {
    final user = accounts.current;
    final generation = _sessionGeneration;
    if (user == null ||
        _recordReconcileRunning ||
        !_recordSyncAvailable ||
        isAssistantReadOnly ||
        !_isCurrentSession(user, generation) ||
        user.authUserId == null) {
      return;
    }
    _recordReconcileRunning = true;
    try {
      final backend = MindTrackBackend.instance;
      if (!backend.isSignedIn) return;
      late final SyncSignalBatch batch;
      var hasSignalRows = true;
      try {
        batch = await backend.fetchPsychologistRecordSignalsSince(
          expectedUserId: user.authUserId!,
          updatedSince: _recordSignalCursor,
        );
      } catch (_) {
        hasSignalRows = false;
        batch = await backend.fetchPsychologistRecordChangesSince(
          expectedUserId: user.authUserId!,
          updatedSince: _recordSignalCursor,
        );
      }
      if (!_isCurrentSession(user, generation) || _logoutPreparing) return;
      if (hasSignalRows) {
        final changedRows = <Map<String, dynamic>>[];
        for (final signal in batch.rows) {
          final row = await _fetchRecordRowForSignal(signal, user, generation);
          if (row != null) changedRows.add(row);
          if (!_isCurrentSession(user, generation) || _logoutPreparing) return;
        }
        await _applyRemoteRecordRows(changedRows, user, generation);
      } else {
        await _applyRemoteRecordRows(batch.rows, user, generation);
      }
      if (!_isCurrentSession(user, generation) || _logoutPreparing) return;
      _recordSignalCursor = (SyncCursor(_recordSignalCursor))
          .advance(batch.updatedThrough)
          .updatedAt;
    } catch (_) {
      // Keep the previous cursor so a later resume/fallback retries this delta.
    } finally {
      _recordReconcileRunning = false;
    }
  }

  Future<void> _applyRemoteRecordSignal(
    Map<String, dynamic> signal,
    UserAccount user,
    int generation,
  ) async {
    final row = await _fetchRecordRowForSignal(signal, user, generation);
    if (row != null) await _applyRemoteRecordRows([row], user, generation);
  }

  Future<Map<String, dynamic>?> _fetchRecordRowForSignal(
    Map<String, dynamic> signal,
    UserAccount user,
    int generation,
  ) async {
    if (_logoutPreparing || !_isCurrentSession(user, generation)) return null;
    if (signal['user_id']?.toString() != user.authUserId) return null;
    final type = signal['record_type']?.toString();
    final id = signal['record_id']?.toString();
    if (type == null || type.isEmpty || id == null || id.isEmpty) return null;
    final key = '$type:$id';
    final signaledVersion = (signal['record_version'] as num?)?.toInt() ?? 0;
    if (signaledVersion <= (_recordVersions[key] ?? 0)) return null;
    final row = await MindTrackBackend.instance.fetchPsychologistRecord(
      expectedUserId: user.authUserId!,
      recordType: type,
      recordId: id,
    );
    if (_logoutPreparing || !_isCurrentSession(user, generation)) return null;
    if (row != null) {
      if (syncRecordVersion(row) < signaledVersion) return null;
      return row;
    }
    if (signal['deleted_at'] == null) return null;
    return <String, dynamic>{
      'record_type': type,
      'record_id': id,
      'data': const <String, dynamic>{},
      'record_version': signaledVersion,
      'deleted_at': signal['deleted_at'],
      'updated_at': signal['updated_at'],
    };
  }

  Future<void> _applyRemoteRecordRows(
    List<Map<String, dynamic>> rows,
    UserAccount localUser,
    int generation,
  ) async {
    if (_logoutPreparing || !_isCurrentSession(localUser, generation)) return;
    if (!_recordSyncActive && rows.isEmpty) return;
    try {
      var changed = false;
      for (final row in rows) {
        changed = applyNewerRecordRow(_remoteRecordRows, row) || changed;
      }
      if (!changed) return;
      _recordVersions = recordVersionsFromRows(_remoteRecordRows.values);
      final next = applyRemoteRecordRows(_remoteRecordData, rows);

      if (hasUnsyncedChanges) {
        carryLocalBinaries(next, data);
        _remoteRecordData = next;
        _recordSyncActive = true;
        data = removeRecordsByKey(
          AppData.mergePreservingLocal(next, data),
          _pendingLocalDeletes,
        );
        _lastLocalRecordKeys = recordKeysFromAppData(data);
        notifyListeners();
        unawaited(
          _saveRemote(
            jsonEncode(data.toJson()),
            user: localUser,
            sessionGeneration: generation,
          ),
        );
        return;
      }

      carryLocalBinaries(next, data);
      await _hydratePdfs(next, localUser, generation);
      if (_logoutPreparing || !_isCurrentSession(localUser, generation)) return;
      _recordSyncActive = true;
      _remoteRecordData = next;
      data = next;
      _lastLocalRecordKeys = recordKeysFromAppData(data);
      await BlobStore.instance.set(
        accounts.dataKey(localUser),
        jsonEncode(data.toJson()),
      );
      if (_logoutPreparing || !_isCurrentSession(localUser, generation)) return;
      notifyListeners();
    } catch (_) {
      // Corrupt or stale rows never replace the existing local snapshot.
    }
  }

  /// Aynı Gmail adresine ait eski/çift yerel kayıtları tek danışanda birleştirir.
  /// Randevular da korunan danışan kaydına taşınır; e-posta karşılaştırması
  /// isimden bağımsız ve küçük/büyük harf duyarsız yapılır.
  bool deduplicateClientsByEmail([AppData? target]) =>
      client_dedup.deduplicateClientsByEmail(target ?? data);

  /// Uzak kopyada yalnızca yol saklanan PDF ve danışan belgelerini
  /// indirip `dataUrl` alanını doldurur.
  ///
  /// Zaten indirilmiş olanlar atlanır; kütüphane her senkronizasyonda
  /// baştan indirilmez.
  Future<void> _hydratePdfs(
    AppData next,
    UserAccount user,
    int generation,
  ) async {
    if (!_isCurrentSession(user, generation)) return;
    for (final file in next.pdfFiles) {
      if (!needsDownload(file.dataUrl, file.storagePath)) continue;
      try {
        final bytes = await MindTrackBackend.instance.downloadPdf(
          file.storagePath,
          expectedUserId: user.authUserId!,
        );
        if (!_isCurrentSession(user, generation)) return;
        file.dataUrl = 'data:${file.type};base64,${base64Encode(bytes)}';
      } catch (_) {
        // Dosya uzak depoda yoksa satır boş kalır, uygulama çalışır.
      }
    }
    for (final doc in next.documents) {
      if (!needsDownload(doc.dataUrl, doc.storagePath)) continue;
      try {
        final bytes = await MindTrackBackend.instance.downloadPdf(
          doc.storagePath,
          expectedUserId: user.authUserId!,
        );
        if (!_isCurrentSession(user, generation)) return;
        doc.dataUrl = 'data:${doc.type};base64,${base64Encode(bytes)}';
      } catch (_) {
        // Belge uzak depoda yoksa açılınca tekrar denenir.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionGeneration++;
    _remoteSaveTimer?.cancel();
    _retryTimer?.cancel();
    _remoteSubscription?.cancel();
    _recordSubscription?.cancel();
    super.dispose();
  }

  void save() {
    final u = accounts.current;
    if (u == null || _logoutPreparing) return;
    final generation = _sessionGeneration;
    if (!_isCurrentSession(u, generation)) return;
    if (isAssistantReadOnly) return;
    deduplicateClientsByEmail();
    if (kIsWeb) {
      final currentKeys = recordKeysFromAppData(data);
      _pendingLocalDeletes.addAll(
        _lastLocalRecordKeys.difference(currentKeys).map(recordKeyHash),
      );
      _pendingLocalDeletes.removeAll(currentKeys.map(recordKeyHash));
      _lastLocalRecordKeys = currentKeys;
    }
    final pendingDeletes = Set<String>.from(_pendingLocalDeletes);
    final encoded = jsonEncode(data.toJson());
    final revision = ++_saveRevision;
    // Persist the dirty marker before the data snapshot. If the tab closes
    // between writes, the next launch still knows a remote sync is required.
    final dirtyWrite = _markDirty(u);
    if (_phase == SyncPhase.idle) _phase = SyncPhase.pending;
    notifyListeners();
    final localWrite = _localSaveChain.then((_) async {
      await dirtyWrite;
      if (kIsWeb) await _persistPendingLocalDeletes(u, pendingDeletes);
      await BlobStore.instance.set(accounts.dataKey(u), encoded);
      if (!_isCurrentSession(u, generation)) return;
      _persistedRevision = revision;
      // A user switch while IndexedDB is writing must not upload this snapshot
      // to whichever account happens to be active when the write completes.
      if (!_isCurrentSession(u, generation) || _logoutPreparing) return;

      // Debounce rapid edits only after the latest snapshot is safely local.
      _remoteSaveTimer?.cancel();
      if (kReleaseMode) {
        _remoteSaveTimer = Timer(const Duration(milliseconds: 450), () {
          _remoteSaveTimer = null;
          unawaited(
            _saveRemote(
              encoded,
              revision: revision,
              user: u,
              sessionGeneration: generation,
            ),
          );
        });
      } else {
        await _saveRemote(
          encoded,
          revision: revision,
          user: u,
          sessionGeneration: generation,
        );
      }
    });
    _localSaveChain = localWrite.catchError((Object error) {
      if (revision == _saveRevision && _isCurrentSession(u, generation)) {
        _onRemoteFailed(
          StateError('Yerel kayıt tamamlanamadı: ${_describeSyncError(error)}'),
          user: u,
          sessionGeneration: generation,
        );
      }
    });
  }

  /// Wait until queued local snapshots are durable (used by tests/lifecycle).
  Future<void> flushLocalWrites() => _localSaveChain;

  /// Yedek geri yüklemeden önce mevcut snapshot'ı kurtarma kopyasına alır.
  /// Kurtarma yazılamazsa yeni veri uygulanmaz; böylece yanlış/yarım geri
  /// yükleme mevcut klinik kaydını riske atmaz.
  Future<void> restoreFromBackup(AppData restored) async {
    final user = accounts.current;
    if (user == null) throw StateError('Aktif kullanıcı bulunamadı.');
    final generation = _sessionGeneration;
    if (!_isCurrentSession(user, generation)) {
      throw StateError('Oturum doğrulanamadı; yedek uygulanmadı.');
    }
    final current = jsonEncode(data.toJson());
    final recoveryKey =
        '${accounts.dataKey(user)}_before_restore_${DateTime.now().microsecondsSinceEpoch}';
    await BlobStore.instance.set(recoveryKey, current);
    if (!_isCurrentSession(user, generation) || _logoutPreparing) {
      throw StateError('Hesap değişti; yedek uygulanmadı.');
    }
    data = restored;
    save();
  }

  /// Psikolog takvimindeki durum değişikliğini ortak Supabase randevusuna da
  /// yazar. Ortak olmayan eski randevular için yardımcı işlem yapmadan döner;
  /// onlar yalnızca psikologun yerel/veri durumu içinde kaydedilir.
  Future<void> updateAppointmentStatus(
    Appointment appointment,
    String nextStatus,
  ) async {
    final previous = appointment.status;
    appointment.status = nextStatus;
    try {
      await syncSharedAppointment(appointment);
      save();
    } catch (_) {
      appointment.status = previous;
      rethrow;
    }
  }

  Future<void> _saveRemote(
    String encoded, {
    int? revision,
    UserAccount? user,
    int? sessionGeneration,
    bool allowDuringLogout = false,
  }) async {
    final u = user ?? accounts.current;
    final generation = sessionGeneration ?? _sessionGeneration;
    if (u == null ||
        !_isCurrentSession(u, generation) ||
        (_logoutPreparing && !allowDuringLogout)) {
      return;
    }
    if (isAssistantReadOnly) return;
    // Arka arkaya gelen işlemlerden hiçbiri kaybolmasın: yeni kayıt, devam eden
    // uzak yazmanın arkasında kuyruğa alınır ve son durum ayrıca yazılır.
    _pendingRemoteEncoded = encoded;
    _pendingRemoteRevision = revision ?? _saveRevision;
    _pendingRemoteUser = u;
    _pendingRemoteSessionGeneration = generation;
    try {
      await _markDirty(u);
    } catch (error) {
      _onRemoteFailed(error, user: u, sessionGeneration: generation);
      return;
    }
    if (!_isCurrentSession(u, generation) ||
        (_logoutPreparing && !allowDuringLogout)) {
      return;
    }
    if (_remoteSaving) return;

    _remoteSaving = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _setPhase(SyncPhase.syncing);
    try {
      while (_pendingRemoteEncoded != null) {
        final payload = _pendingRemoteEncoded!;
        final payloadRevision = _pendingRemoteRevision ?? _saveRevision;
        final payloadUser = _pendingRemoteUser;
        final payloadGeneration = _pendingRemoteSessionGeneration;
        _pendingRemoteEncoded = null;
        _pendingRemoteRevision = null;
        _pendingRemoteUser = null;
        _pendingRemoteSessionGeneration = null;
        if (payloadUser == null ||
            payloadGeneration == null ||
            !_isCurrentSession(payloadUser, payloadGeneration) ||
            (_logoutPreparing && !allowDuringLogout)) {
          break;
        }
        final backend = MindTrackBackend.instance;
        if (!backend.isSignedIn) {
          // Oturum yoksa veri kirli kalır; giriş olunca sürdürülür.
          _setPhase(SyncPhase.pending, message: 'Oturum bekleniyor');
          break;
        }
        try {
          // Base64 PDF'ler önce Storage'a çıkarılır; jsonb gövdesi hafif kalır.
          // Aksi halde ücretsiz plandaki 500 MB'lık veritabanı birkaç dosyada
          // dolar ve (eski sürümdeki gibi) senkron tümüyle durur.
          final slim = await _slimForRemote(
            payload,
            payloadUser,
            payloadGeneration,
          );
          if (!_isCurrentSession(payloadUser, payloadGeneration) ||
              (_logoutPreparing && !allowDuringLogout)) {
            break;
          }
          if (_recordSyncAvailable) {
            await _saveRecordPayload(slim, payloadUser, payloadGeneration);
          } else {
            _remoteVersion = await backend.saveState(
              slim,
              expectedVersion: _remoteVersion,
              expectedUserId: payloadUser.authUserId!,
            );
          }
          if (!_isCurrentSession(payloadUser, payloadGeneration) ||
              (_logoutPreparing && !allowDuringLogout)) {
            break;
          }
          await _onRemoteSaved(payloadRevision, payloadUser, payloadGeneration);
        } catch (error) {
          if (!_isCurrentSession(payloadUser, payloadGeneration)) break;
          _onRemoteFailed(
            error,
            user: payloadUser,
            sessionGeneration: payloadGeneration,
          );
          break;
        }
      }
    } finally {
      _remoteSaving = false;
      final pending = _pendingRemoteEncoded;
      final pendingUser = _pendingRemoteUser;
      final pendingRevision = _pendingRemoteRevision;
      final pendingGeneration = _pendingRemoteSessionGeneration;
      if (pending != null &&
          pendingUser != null &&
          pendingGeneration != null &&
          (!_logoutPreparing || allowDuringLogout) &&
          _isCurrentSession(pendingUser, pendingGeneration)) {
        unawaited(
          _saveRemote(
            pending,
            revision: pendingRevision,
            user: pendingUser,
            sessionGeneration: pendingGeneration,
          ),
        );
      }
    }
  }

  Future<void> _saveRecordPayload(
    Map<String, dynamic> payload,
    UserAccount user,
    int generation,
  ) async {
    if (!_isCurrentSession(user, generation)) return;
    final next = AppData.fromJson(payload);
    final previous = _recordSyncActive ? _remoteRecordData : AppData.empty();
    final changes = diffAppData(previous, next);
    final records = changes.all
        .map(
          (record) => record.copyWith(
            expectedVersion:
                _recordVersions['${record.recordType}:${record.recordId}'] ?? 0,
          ),
        )
        .toList();
    if (records.isNotEmpty) {
      final saved = await MindTrackBackend.instance.savePsychologistRecords(
        records,
        expectedUserId: user.authUserId!,
      );
      if (!_isCurrentSession(user, generation)) return;
      final savedVersions = recordVersionsFromRows(saved);
      if (saved.length != records.length ||
          records.any((record) {
            final key = '${record.recordType}:${record.recordId}';
            return savedVersions[key] != record.expectedVersion + 1;
          })) {
        throw BackendException(
          'Sunucu tüm kayıtlar için kalıcı onay vermedi; yerel değişiklikler korunuyor.',
        );
      }
      for (final row in saved) {
        _remoteRecordRows[syncRecordKey(row)] = Map<String, dynamic>.from(row);
      }
      _recordVersions = {..._recordVersions, ...recordVersionsFromRows(saved)};
    }
    if (!_isCurrentSession(user, generation)) return;
    _recordSyncActive = true;
    _remoteRecordData = next;
  }

  // ---------------- kalıcı senkronizasyon durumu ----------------

  /// Başarılı yazma sonrası: sıradaki iş kalmadıysa durum temizlenir.
  Future<void> _onRemoteSaved(
    int revision,
    UserAccount? syncedUser,
    int generation,
  ) async {
    final u = syncedUser;
    if (u == null || !_isCurrentSession(u, generation)) return;
    _failures = 0;
    _lastSyncedAt = DateTime.now();
    _lastErrorAt = null;
    _syncMessage = null;
    final isLatestDurableRevision =
        revision == _saveRevision &&
        revision <= _persistedRevision &&
        _pendingRemoteEncoded == null;
    if (isLatestDurableRevision) {
      final cleared = await _prefs.setBool(_dirtyKey(u), false);
      if (!cleared) {
        throw StateError('Senkron durumu yerel depoya yazılamadı.');
      }
      if (!_isCurrentSession(u, generation)) return;
      // A newer edit may have arrived while SharedPreferences was completing.
      // Reassert the dirty bit so its persisted snapshot is retried on launch.
      if (revision != _saveRevision || _pendingRemoteEncoded != null) {
        await _markDirty(u);
        if (!_isCurrentSession(u, generation)) return;
      } else {
        if (kIsWeb && _pendingLocalDeletes.isNotEmpty) {
          await _persistPendingLocalDeletes(u, <String>{});
          if (!_isCurrentSession(u, generation)) return;
          if (revision != _saveRevision || _pendingRemoteEncoded != null) {
            await _markDirty(u);
            if (!_isCurrentSession(u, generation)) return;
            await _persistPendingLocalDeletes(
              u,
              Set<String>.from(_pendingLocalDeletes),
            );
          } else {
            _pendingLocalDeletes.clear();
          }
        }
        if (!_isCurrentSession(u, generation)) return;
        await _prefs.setDouble(
          _syncedAtKey(u),
          _lastSyncedAt!.millisecondsSinceEpoch.toDouble(),
        );
      }
    }
    if (!_isCurrentSession(u, generation)) return;
    _setPhase(
      _pendingRemoteEncoded != null || revision != _saveRevision
          ? SyncPhase.pending
          : SyncPhase.idle,
    );
  }

  /// Başarısız yazma: veri kaybolmaz, üstel geri çekilmeyle yeniden denenir.
  void _onRemoteFailed(
    Object error, {
    UserAccount? user,
    int? sessionGeneration,
  }) {
    if (user != null &&
        sessionGeneration != null &&
        !_isCurrentSession(user, sessionGeneration)) {
      return;
    }
    if (_disposed) return;
    _failures++;
    _lastErrorAt = DateTime.now();
    final message = _describeSyncError(error);
    _setPhase(SyncPhase.error, message: message);
    _reportSyncError(message);
    _scheduleRetry(user: user, sessionGeneration: sessionGeneration);
  }

  void _reportSyncError(String message) {
    final now = DateTime.now();
    final fingerprint = '$message:${_failures > 0 ? 'sync' : 'error'}';
    if (_lastReportedError == fingerprint &&
        _lastReportedErrorAt != null &&
        now.difference(_lastReportedErrorAt!) < const Duration(minutes: 5)) {
      return;
    }
    _lastReportedError = fingerprint;
    _lastReportedErrorAt = now;
    unawaited(
      MindTrackBackend.instance.reportClientError(
        category: 'sync_failure',
        // Remote telemetry must never receive backend/provider error text. The
        // full detail remains local for the clinician's recovery UI only.
        message: 'sync_failure',
        severity: _failures >= 3 ? 'critical' : 'error',
        appVersion: _appVersion,
      ),
    );
  }

  void _scheduleRetry({UserAccount? user, int? sessionGeneration}) {
    if (_disposed) return;
    final owner = user ?? accounts.current;
    final generation = sessionGeneration ?? _sessionGeneration;
    if (owner == null || !_isCurrentSession(owner, generation)) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoffFor(_failures), () {
      unawaited(_retryNow(expectedUser: owner, expectedGeneration: generation));
    });
  }

  Duration _backoffFor(int failures) {
    if (failures <= 0) return _backoff.first;
    if (failures > _backoff.length) return _backoff.last;
    return _backoff[failures - 1];
  }

  /// Yeniden denemede veri yerel kaynaktan yeniden üretilir; bellekteki
  /// kopyadan değil. Böylece uygulama kapansa da veri kaybolmaz.
  Future<void> _retryNow({
    UserAccount? expectedUser,
    int? expectedGeneration,
  }) async {
    final user = expectedUser ?? accounts.current;
    final generation = expectedGeneration ?? _sessionGeneration;
    if (user == null || !_isCurrentSession(user, generation)) return;
    _retryTimer = null;
    if (!MindTrackBackend.instance.isSignedIn) {
      _setPhase(SyncPhase.pending, message: 'Oturum bekleniyor');
      return;
    }
    await _localSaveChain;
    if (!_isCurrentSession(user, generation) || _logoutPreparing) return;
    if (_persistedRevision < _saveRevision) {
      try {
        await _markDirty(user);
        await BlobStore.instance.set(
          accounts.dataKey(user),
          jsonEncode(data.toJson()),
        );
        if (!_isCurrentSession(user, generation)) return;
        _persistedRevision = _saveRevision;
      } catch (error) {
        _onRemoteFailed(error, user: user, sessionGeneration: generation);
        return;
      }
    }
    await _saveRemote(
      jsonEncode(data.toJson()),
      revision: _saveRevision,
      user: user,
      sessionGeneration: generation,
    );
  }

  /// Yerel veride sunucuya gitmemiş değişiklik olduğunu diske yazar.
  Future<void> _markDirty(UserAccount u) async {
    final saved = await _prefs.setBool(_dirtyKey(u), true);
    if (!saved) throw StateError('Bekleyen kayıt işareti yazılamadı.');
  }

  /// Önceki oturumdan yarım kalmış yazmayı sürdürür.
  void _resumePendingSync() {
    final u = accounts.current;
    if (u == null || _disposed) return;
    final generation = _sessionGeneration;
    if (!_isCurrentSession(u, generation)) return;
    if (!hasUnsyncedChanges) return;
    if (!MindTrackBackend.instance.isSignedIn) return;
    unawaited(_resumePendingSyncAfterLocalWrites(u, generation));
  }

  Future<void> _resumePendingSyncAfterLocalWrites(
    UserAccount user,
    int generation,
  ) async {
    await _localSaveChain;
    if (!_isCurrentSession(user, generation) || _logoutPreparing) return;
    if (!hasUnsyncedChanges) return;
    if (_persistedRevision < _saveRevision) {
      try {
        await _markDirty(user);
        await BlobStore.instance.set(
          accounts.dataKey(user),
          jsonEncode(data.toJson()),
        );
        if (!_isCurrentSession(user, generation)) return;
        _persistedRevision = _saveRevision;
      } catch (error) {
        _onRemoteFailed(error, user: user, sessionGeneration: generation);
        return;
      }
    }
    await _saveRemote(
      jsonEncode(data.toJson()),
      revision: _saveRevision,
      user: user,
      sessionGeneration: generation,
    );
  }

  /// Sunucuya yazılmamış yerel değişiklik var mı?
  bool get hasUnsyncedChanges {
    final u = accounts.current;
    if (u == null) return false;
    return (_prefs.getBool(_dirtyKey(u)) ?? false) ||
        (kIsWeb &&
            _pendingLocalDeletesOwnerId == u.id &&
            _pendingLocalDeletes.isNotEmpty);
  }

  /// Senkronizasyonun anlık durumu — arayüz bunu dinleyip kullanıcıya gösterir.
  SyncStatus get syncStatus => SyncStatus(
    phase: _phase,
    failures: _failures,
    lastSyncedAt: _lastSyncedAt,
    lastErrorAt: _lastErrorAt,
    message: _syncMessage,
  );

  /// Kullanıcı "Şimdi dene" dediğinde elle tetikler.
  Future<void> retrySyncNow() async {
    final user = accounts.current;
    if (user == null) return;
    final generation = _sessionGeneration;
    if (!_isCurrentSession(user, generation)) return;
    if (!MindTrackBackend.instance.isSignedIn) {
      _setPhase(SyncPhase.offline, message: 'Sunucuya ulaşılamıyor');
      return;
    }
    _failures = 0;
    await _saveRemote(
      jsonEncode(data.toJson()),
      user: user,
      sessionGeneration: generation,
    );
  }

  /// Çıkış öncesi hesabın işi durdurulur. Web cache'i ancak uzak kayıt teyit
  /// edilirse silinir; mobilde çevrimdışı değişiklikler hesap anahtarında kalır.
  Future<void> prepareForLogout() async {
    final user = accounts.current;
    if (user == null) {
      _beginSession(null);
      notifyListeners();
      return;
    }
    if (_logoutPreparing) throw StateError('Çıkış işlemi zaten sürüyor.');
    final generation = _sessionGeneration;
    final web = kIsWeb;
    if (web && !_isCurrentSession(user, generation)) {
      throw StateError('Sunucu oturumu doğrulanamadı; yerel kayıt silinmedi.');
    }
    _logoutPreparing = true;

    try {
      await accounts.flushUserWrites();
      await flushLocalWrites();
      _remoteSaveTimer?.cancel();
      _remoteSaveTimer = null;
      _retryTimer?.cancel();
      _retryTimer = null;

      if (web) {
        final loadDeadline = DateTime.now().add(const Duration(seconds: 15));
        while (_remoteLoading && DateTime.now().isBefore(loadDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (_remoteLoading) {
          throw StateError('Uzak kayıt yüklemesi tamamlanmadı.');
        }
      }

      final canWriteRemote =
          MindTrackBackend.instance.isSignedIn &&
          _isCurrentSession(user, generation) &&
          !isAssistantReadOnly;
      if (web && !isAssistantReadOnly) {
        if (!canWriteRemote) {
          throw StateError('Sunucu oturumu doğrulanamadı.');
        }
      }

      if (canWriteRemote) {
        final revision = _saveRevision;
        await _saveRemote(
          jsonEncode(data.toJson()),
          revision: revision,
          user: user,
          sessionGeneration: generation,
          allowDuringLogout: true,
        );
        final syncDeadline = DateTime.now().add(const Duration(seconds: 30));
        bool isSynced() =>
            !_remoteSaving &&
            _pendingRemoteEncoded == null &&
            !hasUnsyncedChanges &&
            _phase == SyncPhase.idle &&
            _saveRevision == revision &&
            _persistedRevision >= revision;
        while ((_remoteSaving || _pendingRemoteEncoded != null) &&
            DateTime.now().isBefore(syncDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (web && !isSynced()) {
          throw StateError('Son klinik snapshot sunucuya kaydedilemedi.');
        }
      } else if (web && !isAssistantReadOnly) {
        throw StateError('Son klinik snapshot sunucuya kaydedilemedi.');
      }

      await _remoteSubscription?.cancel();
      _remoteSubscription = null;
      await _recordSubscription?.cancel();
      _recordSubscription = null;
      if (web) {
        await BlobStore.instance.removeUserData(user.id);
        await _prefs.remove(_dirtyKey(user));
        await _prefs.remove(_syncedAtKey(user));
        await _prefs.remove(_pendingLocalDeletesKey(user));
      }
      // Invalidate callbacks before auth sign-out or another account can start.
      _beginSession(null);
      notifyListeners();
    } catch (_) {
      _logoutPreparing = false;
      rethrow;
    }
  }

  void _setPhase(SyncPhase phase, {String? message}) {
    if (_disposed) return;
    final unchanged = _phase == phase && _syncMessage == message;
    _phase = phase;
    _syncMessage = message;
    if (!unchanged) notifyListeners();
  }

  static String _describeSyncError(Object error) {
    if (error is BackendException) return error.message;
    final text = error.toString();
    return text.length > 120 ? '${text.substring(0, 117)}…' : text;
  }

  /// Belge ikililerini Storage'a yükleyip gövdeden çıkarır.
  ///
  /// `data` nesnesine dokunmaz; yalnızca gönderilecek kopya hafifletilir,
  /// böylece cihazdaki yerel önbellekler bozulmaz.
  ///
  /// Hiçbir platformda klinik PDF gövdesi veritabanına gönderilmez: Storage
  /// yüklemesi başarısızsa senkron durur ve yerel veri/kuyruk korunur.
  Future<Map<String, dynamic>> _slimForRemote(
    String encoded,
    UserAccount user,
    int generation,
  ) async {
    final slim = jsonDecode(encoded) as Map<String, dynamic>;
    dropUploadedBodies(slim);
    for (final file in extractInlineBinaries(slim)) {
      try {
        if (!_isCurrentSession(user, generation)) return slim;
        final path = await MindTrackBackend.instance.uploadPdf(
          file.id,
          file.bytes,
          expectedUserId: user.authUserId!,
        );
        applyStoragePath(slim, file.collection, file.id, path);
        _rememberStoragePath(file.collection, file.id, path, user, generation);
      } catch (_) {
        // Keep the source body in this outbound copy when upload fails.
      }
    }
    return slim;
  }

  /// Yüklenen belgenin (kütüphane PDF'i veya danışan dokümanı) uzak yolunu
  /// yerel kayda yazar.
  ///
  /// Böylece her senkronizasyonda aynı dosya yeniden yüklenmez; yereldeki
  /// `dataUrl` önbelleği korunur, belge ekranda açılırken yerel kopyası durur.
  void _rememberStoragePath(
    String collection,
    String id,
    String path,
    UserAccount user,
    int generation,
  ) {
    if (!_isCurrentSession(user, generation)) return;
    if (!stampStoragePath(data, collection, id, path)) return;
    _persistLocal(user, generation);
  }

  /// Mevcut kaydı diske yazar (kirli işareti bu yol değiştirir).
  void _persistLocal(UserAccount user, int generation) {
    if (_logoutPreparing || !_isCurrentSession(user, generation)) return;
    unawaited(
      BlobStore.instance.set(accounts.dataKey(user), jsonEncode(data.toJson())),
    );
  }

  // ---------------- tembel belge indirme ----------------

  /// Aynı belgenin eşzamanlı indirilmesini tek isteğe indirger.
  final Map<String, Future<Uint8List>> _inflightDownloads =
      <String, Future<Uint8List>>{};

  Future<Uint8List> _downloadBinary(
    String storagePath,
    String type,
    void Function(String dataUrl) cache,
  ) {
    final user = accounts.current;
    if (user == null ||
        user.authUserId == null ||
        !_isCurrentSession(user, _sessionGeneration)) {
      return Future<Uint8List>.value(Uint8List(0));
    }
    final generation = _sessionGeneration;
    final requestKey = '${user.id}:${user.authUserId}:$generation:$storagePath';
    final running = _inflightDownloads[requestKey];
    if (running != null) return running;
    final future = _performDownload(
      storagePath,
      type,
      cache,
      user: user,
      generation: generation,
      requestKey: requestKey,
    );
    _inflightDownloads[requestKey] = future;
    return future;
  }

  Future<Uint8List> _performDownload(
    String storagePath,
    String type,
    void Function(String dataUrl) cache, {
    required UserAccount user,
    required int generation,
    required String requestKey,
  }) async {
    try {
      final bytes = await MindTrackBackend.instance.downloadPdf(
        storagePath,
        expectedUserId: user.authUserId!,
      );
      if (_logoutPreparing || !_isCurrentSession(user, generation)) {
        return Uint8List(0);
      }
      cache('data:$type;base64,${base64Encode(bytes)}');
      _persistLocal(user, generation);
      notifyListeners();
      return bytes;
    } catch (_) {
      // Çevrimdışı veya silinmiş dosya: boş döner, arayüz uyarı gösterir.
      return Uint8List(0);
    } finally {
      _inflightDownloads.remove(requestKey);
    }
  }

  /// Kütüphane PDF'inin baytlarını döndürür.
  ///
  /// Bu cihazda önbelleği varsa indirilmez; yoksa sunucudan çekilip
  /// önbelleğe alınır. Başarısız olursa boş liste döner.
  Future<Uint8List> pdfBytes(PdfFile file) {
    final cached = bytesFromDataUrl(file.dataUrl);
    if (cached.isNotEmpty) return Future<Uint8List>.value(cached);
    if (file.storagePath.isEmpty) return Future<Uint8List>.value(Uint8List(0));
    return _downloadBinary(file.storagePath, file.type, (value) {
      file.dataUrl = value;
    });
  }

  /// Danışan dokümanının baytlarını döndürür.
  Future<Uint8List> documentBytes(Document doc) {
    final cached = bytesFromDataUrl(doc.dataUrl);
    if (cached.isNotEmpty) return Future<Uint8List>.value(cached);
    if (doc.storagePath.isEmpty) return Future<Uint8List>.value(Uint8List(0));
    return _downloadBinary(doc.storagePath, doc.type, (value) {
      doc.dataUrl = value;
    });
  }

  /// Belgenin bu cihazda indirilmiş kopyası var mı?
  ///
  /// `false` ise belge yalnızca sunucuda duruyor; çevrimdışı açılamaz ve
  /// ilk açılışta indirilir.
  bool pdfIsCached(PdfFile file) => isCached(file.dataUrl);

  /// Danışan dokümanı için aynı kontrol.
  bool documentIsCached(Document doc) => isCached(doc.dataUrl);

  /// Silinen belgelerin sunucu kopyalarını temizler.
  ///
  /// Silme yalnızca kayıttan çıkarmakla kalmaz; depoda kalan ikili kopyalar
  /// hem aylık depolama maliyeti hem de KVKK açısından sorunludur (silinen
  /// danışanın belgesi depoda kalırsa "sil" sözü tutmaz). Hata durumunda
  /// sessizce geçilir: geriye yalnızca boş bir depo nesnesi kalır.
  Future<void> purgeBlobs(Iterable<String> paths) async {
    final user = accounts.current;
    final generation = _sessionGeneration;
    if (user == null ||
        user.authUserId == null ||
        !_isCurrentSession(user, generation)) {
      return;
    }
    for (final path in paths) {
      if (!_isCurrentSession(user, generation)) return;
      if (path.isEmpty) continue;
      try {
        await MindTrackBackend.instance.deletePdf(
          path,
          expectedUserId: user.authUserId!,
        );
        if (!_isCurrentSession(user, generation)) return;
      } catch (_) {
        // Depo temizliği başarısız olursa veri kaybı olmaz.
      }
    }
  }

  Future<void> resetAll() async {
    final paths = <String>{
      for (final file in data.pdfFiles) file.storagePath,
      for (final document in data.documents) document.storagePath,
    };
    data = AppData.empty();
    save();
    await flushLocalWrites();
    await purgeBlobs(paths);
  }

  int get sizeBytes => utf8.encode(jsonEncode(data.toJson())).length;
  String get sizeLabel {
    final kb = sizeBytes / 1024;
    if (kb < 1) return '$sizeBytes B';
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(2)} MB';
  }

  // ---------- Örnek veri (web sürümüyle uyumlu) ----------
  void loadDemoData() {
    final today = DateTime.now();
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final form = FormEntry(
      id: newId(),
      title: 'İlk Değerlendirme Formu',
      description: 'Danışanın genel durumunu değerlendirir.',
      questions: [
        FormQuestion(
          id: newId(),
          type: 'scale',
          text: 'Genel kaygı düzeyinizi değerlendirin',
          scaleMax: 5,
          order: 0,
        ),
        FormQuestion(
          id: newId(),
          type: 'multiple_choice',
          text: 'Uyku kaliteniz nasıl?',
          options: ['Çok İyi', 'İyi', 'Orta', 'Kötü', 'Çok Kötü'],
          order: 1,
        ),
        FormQuestion(
          id: newId(),
          type: 'yes_no',
          text: 'Son 2 haftada işe/okula gitmekte zorlandınız mı?',
          order: 2,
        ),
      ],
    );
    data.forms.add(form);

    final c1 = Client(
      id: newId(),
      name: 'Ayşe Yılmaz',
      email: 'ayse@ornek.com',
      phone: '0532 000 00 01',
      gender: 'Kadın',
      tags: ['Kaygı'],
      notes: 'İlk görüşme ertelendi.',
    );
    final c2 = Client(
      id: newId(),
      name: 'Mehmet Demir',
      email: 'mehmet@ornek.com',
      phone: '0532 000 00 02',
      gender: 'Erkek',
      tags: ['Uyku'],
    );
    final c3 = Client(
      id: newId(),
      name: 'Zeynep Kaya',
      email: 'zeynep@ornek.com',
      phone: '0532 000 00 03',
      tags: ['Sınav'],
    );
    data.clients.addAll([c1, c2, c3]);

    data.assessments.add(
      Assessment(
        id: newId(),
        clientId: c1.id,
        formId: form.id,
        answers: {
          form.questions[0].id: 3,
          form.questions[1].id: 'Orta',
          form.questions[2].id: 'Hayır',
        },
        score: 10,
      ),
    );

    data.appointments.addAll([
      Appointment(
        id: newId(),
        date: iso(today),
        time: '10:00',
        clientId: c1.id,
        type: 'therapy',
        status: 'planned',
      ),
      Appointment(
        id: newId(),
        date: iso(today.add(const Duration(days: 2))),
        time: '14:30',
        clientId: c2.id,
        type: 'intake',
        status: 'planned',
      ),
    ]);

    data.notes.add(
      Note(
        id: newId(),
        clientId: c1.id,
        title: 'Seans 1',
        mood: 'Orta',
        subjective: 'Danışan kaygılarını dile getirdi.',
        objective: 'Göz teması düşük, konuşma hızı yüksek.',
        assessment: 'Yaygın kaygı belirtileri gözleniyor.',
        plan: 'Nefes egzersizleri önerildi.',
      ),
    );

    final plan = Plan(id: newId(), clientId: c1.id);
    plan.goals.add(
      Goal(
        id: newId(),
        text: 'Haftada 3 kez nefes egzersizi yapmak',
        category: 'short',
        status: 'in_progress',
      ),
    );
    plan.goals.add(
      Goal(
        id: newId(),
        text: 'Kaygı tetikleyicilerini günlükte izlemek',
        category: 'long',
        status: 'pending',
      ),
    );
    data.plans.add(plan);

    data.tasks.addAll([
      Task(
        id: newId(),
        text: 'Ayşe için ölçek sonuçlarını raporla',
        clientId: c1.id,
        priority: 'high',
        dueDate: iso(today.add(const Duration(days: 1))),
      ),
      Task(
        id: newId(),
        text: 'Mehmet için randevu hatırlatması gönder',
        clientId: c2.id,
        priority: 'medium',
      ),
    ]);

    data.pdfCats.add(PdfCategory(id: newId(), name: 'Ölçek Çıktıları'));
    data.pdfFiles.add(
      PdfFile(
        id: newId(),
        catId: data.pdfCats.last.id,
        name: 'MindTrack Ornek.pdf',
        size: 643,
        dataUrl: _demoPdfBase64,
      ),
    );
    save();
  }
}

/// Küçük, geçerli bir örnek PDF (643 bayt) — demo ve testler için.
const _demoPdfBase64 =
    'JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNzkyXSAvQ29udGVudHMgNCAwIFIgL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgNSAwIFIgPj4gPj4gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCA5OSA+PgpzdHJlYW0KQlQgL0YxIDIyIFRmIDcyIDcwMCBUZCAxNiBUTCAoTWluZFRyYWNrIE9ybmVrIFBERikgVGogVCogKEJ1IG9ybmVrIFBERiBjaWhhemluaXpkYSBzYWtsYW5pci4pIFRqIEVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PCAvVHlwZSAvRm9udCAvU3VidHlwZSAvVHlwZTEgL0Jhc2VGb250IC9IZWx2ZXRpY2EgPj4KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDI0MSAwMDAwMCBuIAowMDAwMDAwMzkwIDAwMDAwIG4gCnRyYWlsZXIKPDwgL1NpemUgNiAvUm9vdCAxIDAgUiA+PgpzdGFydHhyZWYKNDYwCiUlRU9GCg==';

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
  Timer? _remoteSaveTimer;
  StreamSubscription<RemoteStateSnapshot?>? _remoteSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _recordSubscription;
  Future<void> _localSaveChain = Future<void>.value();
  int _saveRevision = 0;
  int _persistedRevision = 0;
  int _remoteVersion = 0;
  bool _hasConflict = false;
  bool _recordSyncAvailable = false;
  bool _recordSyncActive = false;
  AppData _remoteRecordData = AppData.empty();
  Map<String, int> _recordVersions = <String, int>{};

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

  DataStore(this.accounts, {bool autoLoad = true}) {
    if (autoLoad) load();
  }

  bool get hasAccount => accounts.current != null;

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
    if (u == null) {
      _remoteSubscription?.cancel();
      _remoteSubscription = null;
      _recordSubscription?.cancel();
      _recordSubscription = null;
      data = AppData.empty();
      notifyListeners();
      return;
    }
    final backend = MindTrackBackend.instance;
    // Yerel klinik önbelleği yalnızca onu oluşturan Supabase hesabıyla
    // birlikte açılabilir. Kimlik doğrulanmamış/eski oturumda gösterme.
    if (kReleaseMode &&
        (!backend.isSignedIn ||
            u.authUserId == null ||
            u.authUserId != backend.userId)) {
      _remoteSubscription?.cancel();
      _remoteSubscription = null;
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
          unawaited(BlobStore.instance.set(
              accounts.dataKey(u), jsonEncode(data.toJson())));
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
        unawaited(
          BlobStore.instance.set(recoveryKey, raw).catchError((_) {}),
        );
      }
      data = AppData.empty();
    }
    if (isAssistantReadOnly) {
      // Asistan önbelleği de yalnızca sunucudan süzülen görünümle yenilenir;
      // eski bir psikolog snapshot'ı yanlışlıkla ekrana taşınmaz.
      data = AppData.empty();
    }
    _restoreSyncState(u);
    notifyListeners();
    _loadRemote();
  }

  /// Kullanıcının diskte kalan senkronizasyon durumunu geri yükler.
  /// Uygulama çevrimdışı açıldığında arayüz doğru uyarıyı gösterebilsin.
  void _restoreSyncState(UserAccount u) {
    final stamped = _prefs.getDouble(_syncedAtKey(u));
    _lastSyncedAt = stamped == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(stamped.round());
    final dirty = _prefs.getBool(_dirtyKey(u)) ?? false;
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
    if (localUser == null || _remoteLoading) return;
    final backend = MindTrackBackend.instance;
    if (!backend.isSignedIn) return;
    _remoteLoading = true;
    await _remoteSubscription?.cancel();
    await _recordSubscription?.cancel();
    _recordSubscription = null;
    try {
      if (localUser.organizationRole == 'assistant' &&
          localUser.organizationId != null) {
        final rows = await backend.fetchAssistantRecords(
          localUser.organizationId!,
        );
        final next = appDataFromRecords(rows);
        data = next;
        _recordSyncAvailable = false;
        _recordSyncActive = false;
        await BlobStore.instance.set(
          accounts.dataKey(localUser),
          jsonEncode(data.toJson()),
        );
        notifyListeners();
        _remoteLoading = false;
        return;
      }
      final rows = await backend.fetchPsychologistRecords();
      _recordSyncAvailable = true;
      if (rows.isNotEmpty) {
        _recordSyncActive = true;
        _recordVersions = recordVersionsFromRows(rows);
        final next = appDataFromRecords(rows);
        carryLocalBinaries(next, data);
        await _hydratePdfs(next);
        _remoteRecordData = next;
        data = next;
        await BlobStore.instance.set(
          accounts.dataKey(localUser),
          jsonEncode(data.toJson()),
        );
        notifyListeners();
        _recordSubscription = backend.watchPsychologistRecords().listen(
          _applyRemoteRecords,
          onError: (_) {},
        );
      } else {
        _remoteSubscription = backend.watchState().listen(
          (remote) => _applyRemoteState(remote, localUser),
          onError: (_) {},
        );
      }
    } catch (_) {
      // Eski kurulumlarda psychologist_records henüz yoktur.
      _recordSyncAvailable = false;
      if (localUser.organizationRole == 'assistant') {
        data = AppData.empty();
        notifyListeners();
        _remoteLoading = false;
        return;
      }
      _remoteSubscription = backend.watchState().listen(
        (remote) => _applyRemoteState(remote, localUser),
        onError: (_) {},
      );
    }
    _remoteLoading = false;
    _resumePendingSync();
  }

  Future<void> _applyRemoteState(
    RemoteStateSnapshot? snapshot,
    UserAccount localUser,
  ) async {
    if (snapshot == null) return;
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
        data = AppData.mergePreservingLocal(remoteData, data);
        final merged = jsonEncode(data.toJson());
        unawaited(BlobStore.instance.set(accounts.dataKey(localUser), merged));
        notifyListeners();
        unawaited(_saveRemote(merged));
        return;
      }
      _remoteVersion = snapshot.version;
      final next = AppData.fromJson(snapshot.data);
      final removedDuplicates = deduplicateClientsByEmail(next);
      // Sunucu gövdeyi taşımaz; bu cihazda indirilmiş belgeler
      // korunur, olmayanlar ilk açıldığında indirilir.
      carryLocalBinaries(next, data);
      await _hydratePdfs(next);
      final encoded = jsonEncode(next.toJson());
      data = next;
      await BlobStore.instance.set(accounts.dataKey(localUser), encoded);
      notifyListeners();
      if (removedDuplicates) _saveRemote(encoded);
    } catch (_) {
      // Bozuk uzak veri mevcut yerel verinin üzerine yazılmaz.
    }
  }

  Future<void> _applyRemoteRecords(
    List<Map<String, dynamic>> rows,
  ) async {
    if (!_recordSyncActive) return;
    try {
      _recordVersions = recordVersionsFromRows(rows);
      final next = appDataFromRecords(rows);
      if (hasUnsyncedChanges) {
        carryLocalBinaries(next, data);
        data = AppData.mergePreservingLocal(next, data);
        notifyListeners();
        unawaited(_saveRemote(jsonEncode(data.toJson())));
        return;
      }
      carryLocalBinaries(next, data);
      await _hydratePdfs(next);
      _remoteRecordData = next;
      data = next;
      final user = accounts.current;
      if (user != null) {
        await BlobStore.instance.set(
          accounts.dataKey(user),
          jsonEncode(data.toJson()),
        );
      }
      notifyListeners();
    } catch (_) {
      // Bozuk uzak kayıtlar mevcut yerel verinin üzerine yazılmaz.
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
  Future<void> _hydratePdfs(AppData next) async {
    for (final file in next.pdfFiles) {
      if (!needsDownload(file.dataUrl, file.storagePath)) continue;
      try {
        final bytes = await MindTrackBackend.instance.downloadPdf(
          file.storagePath,
        );
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
        );
        doc.dataUrl = 'data:${doc.type};base64,${base64Encode(bytes)}';
      } catch (_) {
        // Belge uzak depoda yoksa açılınca tekrar denenir.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _remoteSaveTimer?.cancel();
    _retryTimer?.cancel();
    _remoteSubscription?.cancel();
    _recordSubscription?.cancel();
    super.dispose();
  }

  void save() {
    final u = accounts.current;
    if (u == null) return;
    if (isAssistantReadOnly) return;
    deduplicateClientsByEmail();
    final encoded = jsonEncode(data.toJson());
    final revision = ++_saveRevision;
    // Persist the dirty marker before the data snapshot. If the tab closes
    // between writes, the next launch still knows a remote sync is required.
    final dirtyWrite = _markDirty(u);
    if (_phase == SyncPhase.idle) _phase = SyncPhase.pending;
    notifyListeners();
    final localWrite = _localSaveChain.then((_) async {
      await dirtyWrite;
      await BlobStore.instance.set(accounts.dataKey(u), encoded);
      _persistedRevision = revision;
      // A user switch while IndexedDB is writing must not upload this snapshot
      // to whichever account happens to be active when the write completes.
      if (accounts.current?.id != u.id || _disposed) return;

      // Debounce rapid edits only after the latest snapshot is safely local.
      _remoteSaveTimer?.cancel();
      if (kReleaseMode) {
        _remoteSaveTimer = Timer(const Duration(milliseconds: 450), () {
          _remoteSaveTimer = null;
          unawaited(_saveRemote(encoded, revision: revision, user: u));
        });
      } else {
        await _saveRemote(encoded, revision: revision, user: u);
      }
    });
    _localSaveChain = localWrite.catchError((Object error) {
      if (revision == _saveRevision) {
        _onRemoteFailed(
          StateError('Yerel kayıt tamamlanamadı: ${_describeSyncError(error)}'),
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
    final current = jsonEncode(data.toJson());
    final recoveryKey =
        '${accounts.dataKey(user)}_before_restore_${DateTime.now().microsecondsSinceEpoch}';
    await BlobStore.instance.set(recoveryKey, current);
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
  }) async {
    if (isAssistantReadOnly) return;
    // Arka arkaya gelen işlemlerden hiçbiri kaybolmasın: yeni kayıt, devam eden
    // uzak yazmanın arkasında kuyruğa alınır ve son durum ayrıca yazılır.
    _pendingRemoteEncoded = encoded;
    _pendingRemoteRevision = revision ?? _saveRevision;
    _pendingRemoteUser = user ?? accounts.current;
    final u = _pendingRemoteUser;
    if (u != null) {
      try {
        await _markDirty(u);
      } catch (error) {
        _onRemoteFailed(error);
        return;
      }
      if (accounts.current?.id != u.id) return;
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
        _pendingRemoteEncoded = null;
        _pendingRemoteRevision = null;
        _pendingRemoteUser = null;
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
          final slim = await _slimForRemote(payload);
          if (_recordSyncAvailable) {
            await _saveRecordPayload(slim);
          } else {
            _remoteVersion = await backend.saveState(
              slim,
              expectedVersion: _remoteVersion,
            );
          }
          await _onRemoteSaved(payloadRevision, payloadUser);
        } catch (error) {
          if (error is StateConflictException) {
            _hasConflict = true;
            _setPhase(SyncPhase.error, message: error.message);
          } else {
            _onRemoteFailed(error);
          }
          break;
        }
      }
    } finally {
      _remoteSaving = false;
    }
  }

  Future<void> _saveRecordPayload(Map<String, dynamic> payload) async {
    final next = AppData.fromJson(payload);
    final previous = _recordSyncActive ? _remoteRecordData : AppData.empty();
    final changes = diffAppData(previous, next);
    final records = changes.all
        .map((record) => record.copyWith(
              expectedVersion: _recordVersions[
                    '${record.recordType}:${record.recordId}'
                  ] ??
                  0,
            ))
        .toList();
    if (records.isNotEmpty) {
      final saved = await MindTrackBackend.instance.savePsychologistRecords(
        records,
      );
      _recordVersions = {
        ..._recordVersions,
        ...recordVersionsFromRows(saved),
      };
    }
    _recordSyncActive = true;
    _remoteRecordData = next;
  }

  // ---------------- kalıcı senkronizasyon durumu ----------------

  /// Başarılı yazma sonrası: sıradaki iş kalmadıysa durum temizlenir.
  Future<void> _onRemoteSaved(int revision, UserAccount? syncedUser) async {
    _failures = 0;
    _lastSyncedAt = DateTime.now();
    _lastErrorAt = null;
    _syncMessage = null;
    final u = syncedUser;
    final isLatestDurableRevision =
        u != null &&
        revision == _saveRevision &&
        revision <= _persistedRevision &&
        _pendingRemoteEncoded == null;
    if (isLatestDurableRevision) {
      final cleared = await _prefs.setBool(_dirtyKey(u), false);
      if (!cleared) {
        throw StateError('Senkron durumu yerel depoya yazılamadı.');
      }
      // A newer edit may have arrived while SharedPreferences was completing.
      // Reassert the dirty bit so its persisted snapshot is retried on launch.
      if (revision != _saveRevision || _pendingRemoteEncoded != null) {
        await _markDirty(u);
      } else {
        await _prefs.setDouble(
          _syncedAtKey(u),
          _lastSyncedAt!.millisecondsSinceEpoch.toDouble(),
        );
      }
    }
    _setPhase(
      _pendingRemoteEncoded != null || revision != _saveRevision
          ? SyncPhase.pending
          : SyncPhase.idle,
    );
  }

  /// Başarısız yazma: veri kaybolmaz, üstel geri çekilmeyle yeniden denenir.
  void _onRemoteFailed(Object error) {
    _failures++;
    _lastErrorAt = DateTime.now();
    final message = _describeSyncError(error);
    _setPhase(SyncPhase.error, message: message);
    _reportSyncError(message);
    _scheduleRetry();
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
    unawaited(MindTrackBackend.instance.reportClientError(
      category: 'sync_failure',
      // Remote telemetry must never receive backend/provider error text. The
      // full detail remains local for the clinician's recovery UI only.
      message: 'sync_failure',
      severity: _failures >= 3 ? 'critical' : 'error',
      appVersion: _appVersion,
    ));
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoffFor(_failures), _retryNow);
  }

  Duration _backoffFor(int failures) {
    if (failures <= 0) return _backoff.first;
    if (failures > _backoff.length) return _backoff.last;
    return _backoff[failures - 1];
  }

  /// Yeniden denemede veri yerel kaynaktan yeniden üretilir; bellekteki
  /// kopyadan değil. Böylece uygulama kapansa da veri kaybolmaz.
  Future<void> _retryNow() async {
    _retryTimer = null;
    if (_disposed || accounts.current == null) return;
    if (!MindTrackBackend.instance.isSignedIn) {
      _setPhase(SyncPhase.pending, message: 'Oturum bekleniyor');
      return;
    }
    await _localSaveChain;
    if (_persistedRevision < _saveRevision) {
      final user = accounts.current!;
      try {
        await _markDirty(user);
        await BlobStore.instance.set(
          accounts.dataKey(user),
          jsonEncode(data.toJson()),
        );
        _persistedRevision = _saveRevision;
      } catch (error) {
        _onRemoteFailed(error);
        return;
      }
    }
    await _saveRemote(
      jsonEncode(data.toJson()),
      revision: _saveRevision,
      user: accounts.current,
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
    if (!(_prefs.getBool(_dirtyKey(u)) ?? false)) return;
    if (!MindTrackBackend.instance.isSignedIn) return;
    unawaited(_resumePendingSyncAfterLocalWrites(u));
  }

  Future<void> _resumePendingSyncAfterLocalWrites(UserAccount user) async {
    await _localSaveChain;
    if (_disposed || accounts.current?.id != user.id) return;
    if (!(_prefs.getBool(_dirtyKey(user)) ?? false)) return;
    if (_persistedRevision < _saveRevision) {
      try {
        await _markDirty(user);
        await BlobStore.instance.set(
          accounts.dataKey(user),
          jsonEncode(data.toJson()),
        );
        _persistedRevision = _saveRevision;
      } catch (error) {
        _onRemoteFailed(error);
        return;
      }
    }
    await _saveRemote(
      jsonEncode(data.toJson()),
      revision: _saveRevision,
      user: user,
    );
  }

  /// Sunucuya yazılmamış yerel değişiklik var mı?
  bool get hasUnsyncedChanges {
    final u = accounts.current;
    if (u == null) return false;
    return _prefs.getBool(_dirtyKey(u)) ?? false;
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
    if (accounts.current == null) return;
    if (_hasConflict) {
      _setPhase(
        SyncPhase.error,
        message: 'Çakışma çözülmeden yerel verinin üzerine yazılmayacak.',
      );
      return;
    }
    if (!MindTrackBackend.instance.isSignedIn) {
      _setPhase(SyncPhase.offline, message: 'Sunucuya ulaşılamıyor');
      return;
    }
    _failures = 0;
    await _saveRemote(jsonEncode(data.toJson()));
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
  /// Yükleme sırası **gövde yerinde kalır**; yol yalnızca başarılı olduktan
  /// sonra yazılır. Yükleme başarısız olursa gövde gönderilir, böylece
  /// sunucuya hiç ulaşamayan belge kaybolmaz.
  Future<Map<String, dynamic>> _slimForRemote(String encoded) async {
    final slim = jsonDecode(encoded) as Map<String, dynamic>;
    // Sunucuda zaten var olanlar tekrar yüklenmez.
    dropUploadedBodies(slim);
    for (final file in extractInlineBinaries(slim)) {
      try {
        final path = await MindTrackBackend.instance.uploadPdf(
          file.id,
          file.bytes,
        );
        applyStoragePath(slim, file.collection, file.id, path);
        // Yerel kayıtta da yol tutulur; aksi halde her senkronizasyonda aynı
        // dosya yeniden yüklenir.
        _rememberStoragePath(file.collection, file.id, path);
      } catch (_) {
        // Yükleme başarısız: gövde gönderilecek kopyada kalır.
      }
    }
    return slim;
  }

  /// Yüklenen belgenin (kütüphane PDF'i veya danışan dokümanı) uzak yolunu
  /// yerel kayda yazar.
  ///
  /// Böylece her senkronizasyonda aynı dosya yeniden yüklenmez; yereldeki
  /// `dataUrl` önbelleği korunur, belge ekranda açılırken yerel kopyası durur.
  void _rememberStoragePath(String collection, String id, String path) {
    if (!stampStoragePath(data, collection, id, path)) return;
    _persistLocal();
  }

  /// Mevcut kaydı diske yazar (kirli işareti bu yol değiştirir).
  void _persistLocal() {
    final user = accounts.current;
    if (user == null) return;
    unawaited(BlobStore.instance.set(
        accounts.dataKey(user), jsonEncode(data.toJson())));
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
    final running = _inflightDownloads[storagePath];
    if (running != null) return running;
    final future = _performDownload(storagePath, type, cache);
    _inflightDownloads[storagePath] = future;
    return future;
  }

  Future<Uint8List> _performDownload(
    String storagePath,
    String type,
    void Function(String dataUrl) cache,
  ) async {
    try {
      final bytes = await MindTrackBackend.instance.downloadPdf(storagePath);
      cache('data:$type;base64,${base64Encode(bytes)}');
      _persistLocal();
      notifyListeners();
      return bytes;
    } catch (_) {
      // Çevrimdışı veya silinmiş dosya: boş döner, arayüz uyarı gösterir.
      return Uint8List(0);
    } finally {
      _inflightDownloads.remove(storagePath);
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
    for (final path in paths) {
      if (path.isEmpty) continue;
      try {
        await MindTrackBackend.instance.deletePdf(path);
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

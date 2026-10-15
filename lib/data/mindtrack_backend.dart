import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client.dart';
import 'record_sync.dart';
import 'supabase_config.dart';

/// Uygulamanın tüm uzak veri işlemlerini toplayan katman.
///
/// Tüm uzak veri işlemlerini toplar. Satırlar Postgres'ten gelir ancak
/// ekranların beklediği alan adlarına (`clientUserId`, `date`, `clientId`, …)
/// çevrilerek döndürülür; böylece arayüz kodunda kapsamlı bir alan adı
/// değişikliği gerekmez.
class MindTrackBackend {
  MindTrackBackend._();

  static final MindTrackBackend instance = MindTrackBackend._();

  static const String pdfBucket = 'mindtrack-pdfs';
  static const int _syncPageSize = 500;

  SupabaseClient get _db => Supabase.instance.client;

  /// `Supabase.initialize` çağrılmadan önce erişilirse (ör. testlerde veya
  /// yapılandırma eksikken) uygulama çökmesin; oturum yok sayılır.
  bool get isReady {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Oturumdaki kullanıcının Supabase UUID'si.
  String? get userId => isReady ? _db.auth.currentUser?.id : null;

  String? get userEmail => isReady ? _db.auth.currentUser?.email : null;

  String get displayName => isReady
      ? (_db.auth.currentUser?.userMetadata?['display_name'] as String?) ?? ''
      : '';

  bool get isSignedIn => isReady && _db.auth.currentUser != null;

  static Future<void> init() async {
    SupabaseConfig.ensureConfigured();
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  Stream<AuthState> authStateChanges() {
    if (!isReady) return const Stream<AuthState>.empty();
    return _db.auth.onAuthStateChange;
  }
  Future<T> _guardForUser<T>(
    String expectedUserId,
    Future<T> Function() action,
  ) => _guard(() async {
    if (userId != expectedUserId) {
      throw BackendException('Oturum değişti; işlem gönderilmedi.');
    }
    return action();
  });

  // ---------------------------------------------------------------- oturum ---

  Future<void> signIn(String email, String password) async {
    await _guard(() async {
      await _db.auth.signInWithPassword(email: email, password: password);
    });
  }

  Future<void> signUp(
    String email,
    String password, {
    String? displayName,
  }) async {
    await _guard(() async {
      await _db.auth.signUp(
        email: email,
        password: password,
        data: {
          if (displayName != null && displayName.trim().isNotEmpty)
            'display_name': displayName.trim(),
        },
      );
    });
  }

  /// E-posta adresine tek kullanımlık giriş kodu gönderir.
  Future<void> sendEmailLoginCode(String email) async {
    await _guard(() async {
      await _db.auth.signInWithOtp(
        email: email.trim().toLowerCase(),
      );
    });
  }

  /// Gmail'e gelen tek kullanımlık kodla oturum açar.
  Future<void> verifyEmailLoginCode({
    required String email,
    required String code,
  }) async {
    await _guard(() async {
      await _db.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: code.trim(),
        type: OtpType.email,
      );
    });
  }

  Future<void> signOut() async {
    await _guard(() async => _db.auth.signOut());
  }

  // ---------------------------------------------------------- klinik üyeliği -

  /// Kullanıcının aktif klinik üyeliğini döndürür.
  ///
  /// Üyelik doğrulanamadığında null dönmek güvenli değildir: uygulama yerel
  /// önbellekle açılırsa askıya alınmış veya başka bir tenant'ın verisi
  /// gösterilebilir. Bu nedenle üretimde bağlantı/migration hatası girişte
  /// görünür bir hata olarak yukarı taşınır.
  Future<OrganizationMembership> ensurePersonalOrganization({
    required String fallbackName,
  }) async {
    final uid = userId;
    if (uid == null) {
      throw BackendException('Sunucu hesabı doğrulanamadı.');
    }
    try {
      final existing = await _guard(() => _db
          .from('memberships')
          .select('organization_id, role, status')
          .eq('user_id', uid)
          .eq('status', 'active')
          .order('created_at')
          .limit(1)
          .maybeSingle());
      if (existing != null) {
        return OrganizationMembership.fromJson(existing);
      }
      final name = fallbackName.trim().isEmpty
          ? 'MindTrack Klinik'
          : fallbackName.trim();
      final created = await _guard(
        () => _db.rpc('create_organization', params: {'p_name': name}),
      );
      final organizationId = created?.toString();
      if (organizationId == null || organizationId.isEmpty) {
        throw BackendException('Klinik üyeliği oluşturulamadı.');
      }
      return OrganizationMembership(
        organizationId: organizationId,
        role: 'admin',
        status: 'active',
      );
    } catch (error) {
      if (error is BackendException) rethrow;
      throw BackendException(
        'Klinik üyeliği doğrulanamadı. Hesabınız güvenlik nedeniyle açılmadı; '
        'yönetici migration ve üyelik ayarlarını kontrol etmelidir.',
      );
    }
  }

  Future<List<OrganizationMember>> listOrganizationMembers(
    String organizationId,
  ) async {
    final result = await _guard(() => _db.rpc(
          'list_organization_members',
          params: {'p_organization_id': organizationId},
        ));
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map((row) => OrganizationMember.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList();
  }

  Future<OrganizationMember> addOrganizationMember({
    required String organizationId,
    required String email,
    required String role,
  }) async {
    final result = await _guard(() => _db.rpc(
          'manage_organization_member',
          params: {
            'p_organization_id': organizationId,
            'p_email': email.trim().toLowerCase(),
            'p_role': role,
          },
        ));
    if (result is! Map) throw BackendException('Üyelik yanıtı geçersiz.');
    return OrganizationMember.fromJson(Map<String, dynamic>.from(result));
  }

  Future<void> updateOrganizationMemberStatus({
    required String organizationId,
    required String userId,
    required String status,
  }) async {
    await _guard(() => _db.rpc(
          'set_organization_member_status',
          params: {
            'p_organization_id': organizationId,
            'p_user_id': userId,
            'p_status': status,
          },
    ));
  }

  /// Klinik verisi göndermeden teknik hata olayını kaydeder. Raporlama
  /// başarısız olursa asıl kullanıcı akışı etkilenmez.
  Future<void> reportClientError({
    required String category,
    required String message,
    required String severity,
    required String appVersion,
  }) async {
    final uid = userId;
    if (uid == null) return;
    try {
      await _guard(() => _db.rpc(
            'report_client_error',
            params: {
              'p_category': category,
              'p_message': message,
              'p_severity': severity,
              'p_app_version': appVersion,
            },
          ));
      if (severity == 'critical') {
        // Owner alert delivery must not make the clinical write/reporting path
        // fail. The Edge Function verifies this session and sends no PHI.
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            await _db.functions.invoke('critical-error-alert', body: const {});
            break;
          } catch (_) {
            if (attempt == 2) break;
            await Future<void>.delayed(Duration(seconds: attempt + 1));
          }
        }
      }
    } catch (_) {
      // Telemetri klinik uygulamanın çalışmasını durdurmamalı.
    }
  }

  // ------------------------------------------------ psikologun klinik kaydı ---

  /// Psikologun AppData'sının uzak kopyası. Psikologun tüm klinik kaydı
  /// tek bir jsonb satırında tutulur.
  Stream<RemoteStateSnapshot?> watchState() {
    final uid = userId;
    if (uid == null) return Stream<RemoteStateSnapshot?>.value(null);
    return _watchOne('psychologist_state', {
      'psychologist_id': uid,
    }, selector: (r) {
      final data = r['data'];
      if (data is! Map) return null;
      return RemoteStateSnapshot(
        data: Map<String, dynamic>.from(data),
        version: (r['state_version'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<int> saveState(
    Map<String, dynamic> data, {
    required int expectedVersion,
    required String expectedUserId,
  }) async {
    final uid = userId;
    if (uid == null || uid != expectedUserId) {
      throw BackendException('Oturum değişti; kayıt sunucuya gönderilmedi.');
    }
    return _guardForUser(uid, () async {
      final current = await _db
          .from('psychologist_state')
          .select()
          .eq('psychologist_id', uid)
          .maybeSingle();
      if (userId != uid) {
        throw BackendException('Oturum değişti; kayıt sunucuya gönderilmedi.');
      }
      // Preserve the legacy write path while a deployment is still on the old schema.
      if (current != null && !current.containsKey('state_version')) {
        await _db.from('psychologist_state').upsert({
          'psychologist_id': uid,
          'data': data,
        }, onConflict: 'psychologist_id');
        return expectedVersion;
      }
      final currentVersion = (current?['state_version'] as num?)?.toInt() ?? 0;
      if ((current == null && expectedVersion != 0) ||
          (current != null && currentVersion != expectedVersion)) {
        throw StateConflictException();
      }
      final nextVersion = expectedVersion + 1;
      if (current == null) {
        try {
          await _db.from('psychologist_state').insert({
            'psychologist_id': uid,
            'data': data,
            'state_version': nextVersion,
          });
        } on PostgrestException catch (error) {
          if (error.code == '23505') throw StateConflictException();
          if (_isMissingStateVersion(error)) {
            await _db.from('psychologist_state').upsert({
              'psychologist_id': uid,
              'data': data,
            }, onConflict: 'psychologist_id');
            return expectedVersion;
          }
          rethrow;
        }
        return nextVersion;
      }
      final updated = await _db
          .from('psychologist_state')
          .update({'data': data, 'state_version': nextVersion})
          .eq('psychologist_id', uid)
          .eq('state_version', expectedVersion)
          .select('state_version')
          .maybeSingle();
      if (updated == null) throw StateConflictException();
      return nextVersion;
    });
  }

  /// Kayıt bazlı geçiş katmanı. Eski psychologist_state akışıyla paralel
  /// kullanılabilir; istemci her kaydı kendi beklenen sürümüyle yazar.
  Future<List<Map<String, dynamic>>> savePsychologistRecords(
    Iterable<RecordEnvelope> records, {
    required String expectedUserId,
  }) async {
    final uid = userId;
    if (uid == null || uid != expectedUserId) {
      throw BackendException('Oturum değişti; kayıt sunucuya gönderilmedi.');
    }
    final payload = records.map((record) => record.toJson()).toList();
    if (payload.isEmpty) return const [];
    late final dynamic result;
    try {
      result = await _guard(() {
        if (userId != uid) {
          throw BackendException(
            'Oturum değişti; kayıt sunucuya gönderilmedi.',
          );
        }
        return _db.rpc(
          'upsert_psychologist_records',
          params: {'p_records': payload},
        );
      });
    } on BackendException catch (error) {
      if (error.message.toLowerCase().contains('record_conflict')) {
        throw StateConflictException();
      }
      rethrow;
    }
    if (userId != uid) {
      throw BackendException('Oturum değişti; kayıt onayı kabul edilmedi.');
    }
    if (result is! List) {
      throw BackendException('Sunucu kayıt onayı döndürmedi.');
    }
    return result
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchPsychologistRecords({
    required String expectedUserId,
  }) async {
    final uid = userId;
    if (uid == null || uid != expectedUserId) {
      throw BackendException('Oturum değişti; uzak kayıt okunmadı.');
    }
    return fetchAllPages<Map<String, dynamic>>((offset, limit) async {
      final rows = await _guardForUser(
        uid,
        () => _db
            .from('psychologist_records')
            .select(
              'record_type, record_id, data, record_version, deleted_at, updated_at',
            )
            .eq('psychologist_id', uid)
            .order('record_type')
            .order('record_id')
            .range(offset, offset + limit - 1),
      );
      return (rows as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }, pageSize: _syncPageSize);
  }
  Future<Map<String, dynamic>?> fetchPsychologistRecord({
    required String expectedUserId,
    required String recordType,
    required String recordId,
  }) async {
    final uid = userId;
    if (uid == null || uid != expectedUserId) {
      throw BackendException('Oturum değişti; uzak kayıt okunmadı.');
    }
    final row = await _guardForUser(
      uid,
      () => _db
          .from('psychologist_records')
          .select(
            'record_type, record_id, data, record_version, deleted_at, updated_at',
          )
          .eq('psychologist_id', uid)
          .eq('record_type', recordType)
          .eq('record_id', recordId)
          .maybeSingle(),
    );
    return row == null ? null : Map<String, dynamic>.from(row);
  }
  Future<SyncSignalBatch> fetchPsychologistRecordChangesSince({
    required String expectedUserId,
    DateTime? updatedSince,
  }) async {
    final uid = userId;
    if (uid == null || uid != expectedUserId) {
      throw BackendException('Oturum değişti; uzak kayıt okunmadı.');
    }
    final latest = await _guardForUser(
      uid,
      () => _db
          .from('psychologist_records')
          .select('updated_at')
          .eq('psychologist_id', uid)
          .order('updated_at', ascending: false)
          .order('record_type', ascending: false)
          .order('record_id', ascending: false)
          .limit(1)
          .maybeSingle(),
    );
    final through = DateTime.tryParse(latest?['updated_at']?.toString() ?? '');
    if (latest == null || through == null) {
      return const SyncSignalBatch(rows: [], updatedThrough: null);
    }
    final lowerBound = updatedSince?.toUtc().subtract(SyncCursor.overlap);
    final rows = await fetchAllPages<Map<String, dynamic>>((
      offset,
      limit,
    ) async {
      var query = _db
          .from('psychologist_records')
          .select(
            'record_type, record_id, data, record_version, deleted_at, updated_at',
          )
          .eq('psychologist_id', uid)
          .lte('updated_at', through.toUtc().toIso8601String());
      if (lowerBound != null) {
        query = query.gte('updated_at', lowerBound.toIso8601String());
      }
      final page = await _guardForUser(
        uid,
        () => query
            .order('updated_at')
            .order('record_type')
            .order('record_id')
            .range(offset, offset + limit - 1),
      );
      return (page as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }, pageSize: _syncPageSize);
    return SyncSignalBatch(rows: rows, updatedThrough: through.toUtc());
  }

  /// Asistan için yalnızca danışan dizini ve randevu özetlerini döndürür.
  /// Sunucu tarafı RPC'si not, tanı, güvenlik planı ve diğer kayıt alanlarını
  /// hiç üretmediği için istemci tarafı filtrelemeye güvenilmez.
  Future<List<Map<String, dynamic>>> fetchAssistantRecords(
    String organizationId,
  ) async {
    final result = await _guard(() => _db.rpc(
          'fetch_assistant_records',
          params: {'p_organization_id': organizationId},
        ));
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
  Stream<Map<String, dynamic>> watchPsychologistRecordSignals({
    required String expectedUserId,
  }) => _watchSyncSignals(
    expectedUserId: expectedUserId,
    entityType: 'psychologist_record',
  );
  Future<SyncSignalBatch> fetchPsychologistRecordSignalsSince({
    required String expectedUserId,
    DateTime? updatedSince,
  }) => _fetchSyncSignals(
    expectedUserId: expectedUserId,
    entityType: 'psychologist_record',
    updatedSince: updatedSince,
  );
  Stream<Map<String, dynamic>> _watchSyncSignals({
    required String expectedUserId,
    required String entityType,
  }) {
    final uid = userId;
    if (uid == null || uid != expectedUserId) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    final controller = StreamController<Map<String, dynamic>>();
    final channel = _db.channel('mt:sync-signals:$uid:$entityType');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'mindtrack_sync_signals',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: uid,
      ),
      callback: (payload) {
        if (userId != uid || controller.isClosed) return;
        final row = payload.newRecord;
        if (row['entity_type']?.toString() == entityType) {
          controller.add(Map<String, dynamic>.from(row));
        }
      },
    );
    channel.subscribe((status, error) {
      if (userId != uid || controller.isClosed) return;
      if (status == RealtimeSubscribeStatus.subscribed || error != null) {
        controller.add(const {'__reconcile__': true});
      }
    });
    controller.onCancel = () async => _db.removeChannel(channel);
    return controller.stream;
  }
  Future<SyncSignalBatch> _fetchSyncSignals({
    required String expectedUserId,
    required String entityType,
    DateTime? updatedSince,
  }) async {
    final uid = userId;
    if (uid == null || uid != expectedUserId) {
      throw BackendException('Oturum değişti; değişiklikler okunmadı.');
    }
    final latest = await _guardForUser(
      uid,
      () => _db
          .from('mindtrack_sync_signals')
          .select('updated_at')
          .eq('user_id', uid)
          .eq('entity_type', entityType)
          .order('updated_at', ascending: false)
          .order('record_type', ascending: false)
          .order('record_id', ascending: false)
          .limit(1)
          .maybeSingle(),
    );
    final through = DateTime.tryParse(latest?['updated_at']?.toString() ?? '');
    if (latest == null || through == null) {
      return const SyncSignalBatch(rows: [], updatedThrough: null);
    }
    final lowerBound = updatedSince?.toUtc().subtract(SyncCursor.overlap);
    final rows = await fetchAllPages<Map<String, dynamic>>((
      offset,
      limit,
    ) async {
      var query = _db
          .from('mindtrack_sync_signals')
          .select(
            'user_id, entity_type, record_type, record_id, record_version, deleted_at, updated_at',
          )
          .eq('user_id', uid)
          .eq('entity_type', entityType)
          .lte('updated_at', through.toUtc().toIso8601String());
      if (lowerBound != null) {
        query = query.gte('updated_at', lowerBound.toIso8601String());
      }
      final page = await _guardForUser(
        uid,
        () => query
            .order('updated_at')
            .order('record_type')
            .order('record_id')
            .range(offset, offset + limit - 1),
      );
      return (page as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }, pageSize: _syncPageSize);
    return SyncSignalBatch(rows: rows, updatedThrough: through.toUtc());
  }
  Future<SyncSignalBatch> _fetchTaskChangesSince({
    required String uid,
    required String ownerColumn,
    DateTime? updatedSince,
  }) async {
    final latest = await _guardForUser(
      uid,
      () => _db
          .from('tasks')
          .select('updated_at')
          .eq(ownerColumn, uid)
          .order('updated_at', ascending: false)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle(),
    );
    final through = DateTime.tryParse(latest?['updated_at']?.toString() ?? '');
    if (latest == null || through == null) {
      return const SyncSignalBatch(rows: [], updatedThrough: null);
    }
    final lowerBound = updatedSince?.toUtc().subtract(SyncCursor.overlap);
    final rows = await fetchAllPages<Map<String, dynamic>>((
      offset,
      limit,
    ) async {
      var query = _db
          .from('tasks')
          .select('id, updated_at')
          .eq(ownerColumn, uid)
          .lte('updated_at', through.toUtc().toIso8601String());
      if (lowerBound != null) {
        query = query.gte('updated_at', lowerBound.toIso8601String());
      }
      final page = await _guardForUser(
        uid,
        () => query
            .order('updated_at')
            .order('id')
            .range(offset, offset + limit - 1),
      );
      return (page as List).whereType<Map>().map((row) {
        final mapped = Map<String, dynamic>.from(row);
        final stamp = DateTime.tryParse(mapped['updated_at']?.toString() ?? '');
        return <String, dynamic>{
          'user_id': uid,
          'entity_type': 'task',
          'record_type': 'task',
          'record_id': mapped['id']?.toString() ?? '',
          // Tasks have no persisted row version; timestamp microseconds give
          // the fallback a stable stale/duplicate comparison token.
          'record_version': stamp?.microsecondsSinceEpoch ?? 0,
          'updated_at': mapped['updated_at'],
        };
      }).toList();
    }, pageSize: _syncPageSize);
    return SyncSignalBatch(rows: rows, updatedThrough: through.toUtc());
  }

  Stream<List<Map<String, dynamic>>> watchPsychologistRecords() {
    final uid = userId;
    if (uid == null) return Stream.value(const []);
    return _watch(
      'psychologist_records',
      {'psychologist_id': uid},
    );
  }

  static bool _isMissingStateVersion(PostgrestException error) {
    final text = '${error.code} ${error.message}'.toLowerCase();
    return text.contains('state_version') || text.contains('schema cache');
  }

  // ------------------------------------------------------------- danışan ---

  Stream<Map<String, dynamic>?> watchPatient() {
    final uid = userId;
    if (uid == null) return Stream<Map<String, dynamic>?>.value(null);
    return _watchOne('patients', {'id': uid}, selector: _legacyPatient);
  }

  /// Profil alanlarını birleştirerek yazar (yalnızca allow-list'li sütunlar).
  Future<void> upsertPatientProfile({
    String? displayName,
    String? email,
    bool? consented,
    String? consentVersion,
  }) async {
    final uid = userId;
    if (uid == null) return;
    final payload = <String, dynamic>{
      'display_name': ?displayName,
      'email': ?email,
      'consented': ?consented,
      'consent_version': ?consentVersion,
      if (consented == true) 'consented_at': DateTime.now().toUtc().toIso8601String(),
      if (consented == false) 'consent_withdrawn_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (payload.isEmpty) return;
    await _guard(() async {
      await _db.from('patients').upsert({
        'id': uid,
        ...payload,
      }, onConflict: 'id');
    });
  }

  /// Danışanın ad/soyad ve e-posta bilgilerini kaydeder.
  Future<void> saveProfile({
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await _guard(() async {
      await _db.from('patients').upsert({
        'id': uid,
        'display_name': '$firstName $lastName',
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
      }, onConflict: 'id');
    });
  }

  /// Eşleşme sonrası danışanın bağlı olduğu psikologu yazar.
  Future<void> linkPsychologist(
    String psychologistId, {
    String clientRef = '',
  }) async {
    final uid = userId;
    if (uid == null) return;
    await _guard(() async {
      await _db.from('patients').upsert({
        'id': uid,
        'psychologist_id': psychologistId,
        if (clientRef.isNotEmpty) 'client_ref': clientRef,
      }, onConflict: 'id');
    });
  }

  /// Psikolog, kendisine bağlı danışanın yalnızca tanı kodlarını yazabilir.
  Future<void> setDiagnosisCodes(String clientUid, List<String> codes) async {
    await _guard(() async {
      await _db
          .from('patients')
          .update({'diagnosis_codes': codes})
          .eq('id', clientUid);
    });
  }

  // -------------------------------------------------------- eşleşme kodu ---

  Future<String> createPairingCode({
    required String psychologistEmail,
    required String clientRef,
    required String clientName,
    required String clientEmail,
    required String clientUid,
    required List<String> diagnosisCodes,
  }) async {
    final uid = userId;
    if (uid == null) throw BackendException('Oturum bulunamadı.');
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final code = List.generate(
      8,
      (_) => chars[random.nextInt(chars.length)],
    ).join();

    await _guard(() async {
      await _db.from('pairing_codes').upsert({
        'code': code,
        'psychologist_id': uid,
        'psychologist_email': psychologistEmail,
        'client_ref': clientRef,
        'client_uid': clientUid.isEmpty ? null : clientUid,
        'client_name': clientName,
        'client_email': clientEmail,
        'diagnosis_codes': diagnosisCodes,
        'status': 'pending',
      }, onConflict: 'code');
    });
    return code;
  }

  /// Kodu sahiplenir ve eşleşme bilgisini döndürür. Okuma yalnızca burada,
  /// atomik bir işlem içinde gerçekleşir.
  Future<PairingClaim> claimPairingCode(String code) async {
    return _guard(() async {
      final result = await _db.rpc(
        'claim_pairing_code',
        params: {'p_code': code},
      );
      final map = Map<String, dynamic>.from(result as Map);
      return PairingClaim(
        psychologistId: map['psychologistId']?.toString() ?? '',
        clientRef: map['clientRef']?.toString() ?? '',
        diagnosisCodes:
            (map['diagnosisCodes'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[],
      );
    });
  }

  /// Psikologun, eşleşmiş danışanının auth kimliğini bulur.
  ///
  /// Önce danışan kaydında saklanan kimliğe bakar; yoksa eşleşme kodlarına
  /// bakar ve bulursa yerel kayda yazar.
  Future<String> resolveClientUserId(Client client) async {
    final direct = client.clientUserId.trim();
    if (direct.isNotEmpty) return direct;
    if (userId == null) return '';

    List<Map<String, dynamic>> rows;
    try {
      rows = await _select('pairing_codes', {'psychologist_id': userId!});
    } catch (_) {
      return '';
    }

    String find({String? clientRef, String? email}) {
      for (final row in rows.reversed) {
        final matchesRef =
            clientRef != null &&
            clientRef.isNotEmpty &&
            (row['client_ref']?.toString() ?? '') == clientRef;
        final matchesEmail =
            email != null &&
            email.isNotEmpty &&
            (row['client_email']?.toString().trim().toLowerCase() ?? '') ==
                email.toLowerCase();
        if (!matchesRef && !matchesEmail) continue;
        final uid = row['client_uid']?.toString().trim() ?? '';
        final status = row['status']?.toString() ?? '';
        if (uid.isNotEmpty && (status.isEmpty || status == 'paired')) {
          return uid;
        }
      }
      return '';
    }

    var resolved = find(clientRef: client.id);
    if (resolved.isEmpty && client.email.trim().isNotEmpty) {
      resolved = find(email: client.email.trim());
    }
    if (resolved.isNotEmpty) client.clientUserId = resolved;
    return resolved;
  }

  // ------------------------------------------------------------ randevu ---

  Stream<List<Map<String, dynamic>>> watchClientAppointments() {
    final uid = userId;
    if (uid == null) return Stream.value(const []);
    // Supabase'in yerleşik stream'i ilk SELECT'i ve INSERT/UPDATE olaylarını
    // aynı akışta birleştirir. Randevularda özel Realtime kanalı kullanmak
    // yerine bunu kullanmak, onay UPDATE'lerinin tarayıcıya kaçırılmasını
    // engeller.
    return _db
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('client_uid', uid)
        .map(
          (rows) => rows
              .map((row) => _legacyAppointment(row))
              .whereType<Map<String, dynamic>>()
              .toList(),
        );
  }

  /// Psikologun tüm randevuları (onaylananlar ve talepler dahil).
  Stream<List<Map<String, dynamic>>> watchPsychologistAppointments() {
    final uid = userId;
    if (uid == null) return Stream.value(const []);
    return _db
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('psychologist_id', uid)
        .map(
          (rows) => rows
              .map((row) => _legacyAppointment(row))
              .whereType<Map<String, dynamic>>()
              .toList(),
        );
  }

  /// Psikologun bekleyen randevu talepleri. Realtime filtresi tek sütun
  /// desteklediği için `status` süzgeci istemci tarafında uygulanır.
  Stream<List<Map<String, dynamic>>> watchPendingRequests() {
    final uid = userId;
    if (uid == null) return Stream.value(const []);
    return _db
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('psychologist_id', uid)
        .map(
          (rows) => rows
              .where((row) {
                if (row['status']?.toString() != 'pending') return false;
                final rawDate = row['appointment_at'] ?? row['date'];
                final date = rawDate is DateTime
                    ? rawDate
                    : DateTime.tryParse(rawDate?.toString() ?? '');
                final name = (row['client_name'] ?? row['clientName'])
                    ?.toString()
                    .trim()
                    .toLowerCase();
                // Eski sürümlerin ürettiği bozuk kayıtlar ekranda
                // 01.01.2100 / Bilinmeyen Danışan olarak görünüyordu.
                if (date == null || date.year >= 2099) return false;
                if (name == null ||
                    name.isEmpty ||
                    name == 'bilinmeyen danışan') {
                  return false;
                }
                return true;
              })
              .map((row) => _legacyAppointment(row))
              .whereType<Map<String, dynamic>>()
              .toList(),
        );
  }

  /// Danışan adına talep kaydı oluşturur. Psikolog ve danışan kimlikleri
  /// istemciden güvenilmez şekilde alınmaz; RPC bunları `patients` eşleşmesinden
  /// sunucu tarafında çözer.
  Future<String> createAppointmentRequest({required DateTime at}) async {
    if (userId == null) {
      throw BackendException('Oturum bulunamadı.');
    }
    return _guard(() async {
      final id = await _db.rpc(
        'create_appointment_request',
        params: {'p_appointment_at': at.toUtc().toIso8601String()},
      );
      return id.toString();
    });
  }

  /// Psikolog bekleyen talebi planlı ortak randevuya dönüştürür.
  Future<void> approveAppointmentRequest(
    String id, {
    required DateTime at,
    required String linkedAppointmentId,
  }) async {
    await _guard(() async {
      await _db.rpc(
        'approve_appointment_request',
        params: {
          'p_id': id,
          'p_appointment_at': at.toUtc().toIso8601String(),
          'p_linked_appointment_id': linkedAppointmentId,
        },
      );
    });
  }

  /// Psikologun bekleyen talebi reddetmesi. Ayrı RPC kullanılır; reddetme
  /// işleminde tarih veya yerel randevu kimliği gerekmez.
  Future<void> rejectAppointmentRequest(String id) async {
    await _guard(() async {
      await _db.rpc(
        'reject_appointment_request',
        params: {'p_id': id},
      );
    });
  }

  /// Psikologun ortak randevuda yaptığı durum veya saat değişikliğini yazar.
  /// Aynı satır danışan tarafından izlendiği için Realtime ile iki uygulama
  /// anında aynı sonucu görür.
  Future<void> updateSharedAppointment(
    String id, {
    required String status,
    required DateTime at,
    required String linkedAppointmentId,
  }) async {
    await _guard(() async {
      await _db.rpc(
        'update_shared_appointment',
        params: {
          'p_id': id,
          'p_status': status,
          'p_appointment_at': at.toUtc().toIso8601String(),
          'p_linked_appointment_id': linkedAppointmentId,
        },
      );
    });
  }

  Future<void> cancelAppointment(String id, {String by = 'client'}) async {
    await _guard(() async {
      await _db.rpc('cancel_appointment', params: {'p_id': id, 'p_by': by});
    });
  }

  Future<void> deleteAppointment(String id) async {
    await _guard(() async {
      await _db.rpc('delete_own_appointment', params: {'p_id': id});
    });
  }

  // -------------------------------------------------------------- görev ---

  Stream<List<Map<String, dynamic>>> watchClientTasks() {
    final uid = userId;
    if (uid == null) return Stream.value(const []);
    return _watchIncrementalTasks(uid: uid, ownerColumn: 'client_uid');
  }

  /// Psikologun gönderdiği görevler ve danışanların cevapları.
  ///
  /// Görevler `tasks` tablosunda tutulur; danışan cevabı `submit_task` RPC'si
  /// ile aynı satıra yazar. Psikolog tarafı bu akışı okumadığı için cevaplar
  /// veritabanında dursa da arayüzde görünmüyordu.
  Stream<List<Map<String, dynamic>>> watchPsychologistTasks() {
    final uid = userId;
    if (uid == null) return Stream.value(const []);
    return _watchIncrementalTasks(uid: uid, ownerColumn: 'psychologist_id');
  }

  /// `watchPsychologistTasks` akışının tek seferlik karşılığı. Canlı akış
  /// bağlantı kurulana kadar boş kalabilir; "Yenile" bunu kullanır.
  Future<List<Map<String, dynamic>>> psychologistTasks() async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await fetchAllPages<Map<String, dynamic>>((
      offset,
      limit,
    ) async {
      final page = await _guardForUser(
        uid,
        () => _db
            .from('tasks')
            .select()
            .eq('psychologist_id', uid)
            .order('id')
            .range(offset, offset + limit - 1),
      );
      return (page as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }, pageSize: _syncPageSize);
    return rows.map(_legacyTask).whereType<Map<String, dynamic>>().toList();
  }
  Stream<List<Map<String, dynamic>>> _watchIncrementalTasks({
    required String uid,
    required String ownerColumn,
  }) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    final cached = <String, Map<String, dynamic>>{};
    final signalVersions = <String, int>{};
    final requestedSignalVersions = <String, int>{};
    final cursor = ValueNotifier<SyncCursor?>(null);
    late final StreamSubscription<Map<String, dynamic>> signalSubscription;
    late final StreamSubscription<AuthState> authSubscription;
    Timer? fallbackTimer;
    var loading = false;
    var initialized = false;
    var queuedRefresh = false;
    var invalidated = false;

    void invalidateOnAccountSwitch() {
      if (invalidated || controller.isClosed || userId == uid) return;
      invalidated = true;
      cached.clear();
      controller.add(const <Map<String, dynamic>>[]);
      fallbackTimer?.cancel();
      unawaited(signalSubscription.cancel());
      unawaited(authSubscription.cancel());
    }

    List<Map<String, dynamic>> snapshot() {
      final rows = cached.values.toList()
        ..sort((a, b) {
          final byCreated = _asMillis(b['created_at'])
              .compareTo(_asMillis(a['created_at']));
          return byCreated != 0
              ? byCreated
              : a['id'].toString().compareTo(b['id'].toString());
        });
      return rows.map(_legacyTask).whereType<Map<String, dynamic>>().toList();
    }

    Future<List<Map<String, dynamic>>> loadSnapshot() =>
        fetchAllPages((offset, limit) async {
          final rows = await _guardForUser(
            uid,
            () => _db
                .from('tasks')
                .select()
                .eq(ownerColumn, uid)
                .order('id')
                .range(offset, offset + limit - 1),
          );
          return (rows as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        }, pageSize: _syncPageSize);

    Future<void> applySignal(Map<String, dynamic> signal) async {
      if (controller.isClosed) return;
      if (userId != uid) {
        invalidateOnAccountSwitch();
        return;
      }
      if (loading && !initialized) {
        queuedRefresh = true;
        return;
      }
      final id = signal['record_id']?.toString();
      if (signal['user_id']?.toString() != uid || id == null || id.isEmpty) {
        return;
      }
      // Both trigger signals and the no-migration fallback carry updated_at;
      // comparing that common microsecond token avoids mixing signal counters
      // with timestamp revisions.
      final stamp = DateTime.tryParse(signal['updated_at']?.toString() ?? '');
      final version =
          stamp?.microsecondsSinceEpoch ??
          (signal['record_version'] as num?)?.toInt() ??
          0;
      if (version <= (signalVersions[id] ?? 0) ||
          version <= (requestedSignalVersions[id] ?? 0)) {
        return;
      }
      requestedSignalVersions[id] = version;

      if (signal['deleted_at'] != null) {
        final changed = applyTaskSyncRow(
          rows: cached,
          appliedSignalVersions: signalVersions,
          signal: signal,
          fetchedRow: null,
        );
        if (changed && !controller.isClosed) controller.add(snapshot());
        return;
      }
      dynamic row;
      try {
        row = await _guardForUser(
          uid,
          () => _db
              .from('tasks')
              .select()
              .eq(ownerColumn, uid)
              .eq('id', id)
              .maybeSingle(),
        );
      } catch (_) {
        if (requestedSignalVersions[id] == version) {
          requestedSignalVersions.remove(id);
        }
        return;
      }
      if (controller.isClosed ||
          userId != uid ||
          version < (requestedSignalVersions[id] ?? 0)) {
        return;
      }
      final changed = applyTaskSyncRow(
        rows: cached,
        appliedSignalVersions: signalVersions,
        signal: signal,
        fetchedRow: row == null ? null : Map<String, dynamic>.from(row),
      );
      if (!changed && (signalVersions[id] ?? 0) < version) {
        requestedSignalVersions.remove(id);
      }
      if (changed && !controller.isClosed) controller.add(snapshot());
    }

    Future<void> reconcile() async {
      if (controller.isClosed) return;
      if (userId != uid) {
        invalidateOnAccountSwitch();
        return;
      }
      if (loading) {
        queuedRefresh = true;
        return;
      }
      loading = true;
      try {
        if (!initialized) {
          final rows = await loadSnapshot();
          if (controller.isClosed || userId != uid) return;
          cached
            ..clear()
            ..addEntries(
              rows.map((row) => MapEntry(row['id'].toString(), row)),
            );
          cursor.value = SyncCursor.fromRows(rows);
          initialized = true;
          controller.add(snapshot());
        }
        late final SyncSignalBatch batch;
        try {
          batch = await _fetchSyncSignals(
            expectedUserId: uid,
            entityType: 'task',
            updatedSince: cursor.value?.updatedAt,
          );
        } catch (_) {
          // Until the draft signal migration is approved/applied, this
          // owner-filtered delta still catches task updates without full polls.
          batch = await _fetchTaskChangesSince(
            uid: uid,
            ownerColumn: ownerColumn,
            updatedSince: cursor.value?.updatedAt,
          );
        }
        for (final signal in batch.rows) {
          await applySignal(signal);
          if (controller.isClosed || userId != uid) return;
        }
        cursor.value = (cursor.value ?? const SyncCursor(null)).advance(
          batch.updatedThrough,
        );
        if (batch.updatedThrough != null) controller.add(snapshot());
      } catch (_) {
        // A disconnect does not terminate the stream; the next signal or
        // foreground reconciliation retries the delta.
      } finally {
        loading = false;
        if (queuedRefresh && !controller.isClosed) {
          queuedRefresh = false;
          unawaited(reconcile());
        }
      }
    }

    signalSubscription =
        _watchSyncSignals(expectedUserId: uid, entityType: 'task').listen((
          signal,
        ) {
          if (signal['__reconcile__'] == true) {
            unawaited(reconcile());
          } else {
            unawaited(applySignal(signal));
          }
        }, onError: (_) => unawaited(reconcile()));
    authSubscription = _db.auth.onAuthStateChange.listen((_) {
      if (userId != uid) invalidateOnAccountSwitch();
    });
    fallbackTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (userId != uid) {
        invalidateOnAccountSwitch();
        return;
      }
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(reconcile());
      }
    });
    unawaited(reconcile());

    controller.onCancel = () async {
      fallbackTimer?.cancel();
      cursor.dispose();
      await signalSubscription.cancel();
      await authSubscription.cancel();
    };
    return controller.stream;
  }

  Future<void> assignTask({
    required String clientRef,
    required String clientUid,
    required String clientName,
    required String clientEmail,
    required String title,
    required String description,
    required String formRef,
    required Map<String, dynamic> formDraft,
  }) async {
    final psychId = userId;
    if (psychId == null) throw BackendException('Oturum bulunamadı.');
    await _guard(() async {
      await _db.from('tasks').insert({
        'psychologist_id': psychId,
        'client_ref': clientRef,
        'client_uid': clientUid,
        'client_name': clientName,
        'client_email': clientEmail,
        'title': title,
        'description': description,
        'form_ref': formRef,
        'form_draft': formDraft,
        'done': false,
        'response': '',
        'structured_answers': <String, dynamic>{},
      });
    });
  }

  Future<void> submitTask(
    String id, {
    required String response,
    required Map<String, dynamic> answers,
  }) async {
    await _guard(() async {
      await _db.rpc(
        'submit_task',
        params: {'p_id': id, 'p_response': response, 'p_answers': answers},
      );
    });
  }

  // --------------------------------------------------------------- ödev ---

  Stream<List<Map<String, dynamic>>> watchHomework() {
    final uid = userId;
    if (uid == null) return Stream.value(const []);
    return _watch('homework', {
      'psychologist_id': uid,
    }, rowMapper: _legacyHomework);
  }

  Future<void> assignHomework({
    required String clientRef,
    required String clientUid,
    required String clientEmail,
    required String title,
    required String description,
  }) async {
    final psychId = userId;
    if (psychId == null) throw BackendException('Oturum bulunamadı.');
    await _guard(() async {
      await _db.from('homework').insert({
        'psychologist_id': psychId,
        'client_ref': clientRef,
        'client_uid': clientUid.isEmpty ? null : clientUid,
        'client_email': clientEmail,
        'title': title,
        'description': description,
        'status': 'assigned',
        'response': '',
      });
    });
  }

  Future<void> submitHomework(String id, String response) async {
    await _guard(() async {
      await _db.rpc(
        'submit_homework',
        params: {'p_id': id, 'p_response': response},
      );
    });
  }

  // -------------------------------------------------------------- PDFler ---

  Future<String> uploadPdf(
    String fileId,
    Uint8List bytes, {
    required String expectedUserId,
  }) async {
    final uid = userId;
    if (uid == null || uid != expectedUserId) {
      throw BackendException('Oturum değişti; belge yüklenmedi.');
    }
    if (fileId.isEmpty ||
        fileId == '.' ||
        fileId == '..' ||
        fileId.contains('/') ||
        fileId.contains(String.fromCharCode(92))) {
      throw BackendException('Belge kimliği geçersiz; dosya yüklenmedi.');
    }
    return _guard(() async {
      if (userId != uid) {
        throw BackendException('Oturum değişti; belge yüklenmedi.');
      }
      final path = '$uid/$fileId';
      await _db.storage
          .from(pdfBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );
      return path;
    });
  }

  Future<Uint8List> downloadPdf(
    String path, {
    required String expectedUserId,
  }) async {
    final uid = userId;
    _validateStorageOwner(path, expectedUserId, uid);
    return _guard(() async {
      if (userId != uid) {
        throw BackendException('Oturum değişti; belge okunmadı.');
      }
      final bytes = await _db.storage.from(pdfBucket).download(path);
      if (userId != uid) {
        throw BackendException('Oturum değişti; belge yanıtı kabul edilmedi.');
      }
      return bytes;
    });
  }

  Future<void> deletePdf(String path, {required String expectedUserId}) async {
    final uid = userId;
    _validateStorageOwner(path, expectedUserId, uid);
    await _guard(() async {
      if (userId != uid) {
        throw BackendException('Oturum değişti; belge silinmedi.');
      }
      await _db.storage.from(pdfBucket).remove([path]);
    });
  }
  void _validateStorageOwner(
    String path,
    String expectedUserId,
    String? currentUserId,
  ) {
    final segments = path.split('/');
    if (currentUserId == null ||
        currentUserId != expectedUserId ||
        segments.length < 2 ||
        segments.first != expectedUserId ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw BackendException('Belge yolu bu hesaba ait değil.');
    }
  }

  // -------------------------------------------------------------- iç yapı ---

  /// Tüm uzak hataları kullanıcıya gösterilebilir tek bir türe indirger.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (e) {
      throw BackendException(_friendly(e.message, e.code));
    } on PostgrestException catch (e) {
      throw BackendException(_friendly(e.message, e.code));
    } on StorageException catch (e) {
      throw BackendException(_friendly(e.message, e.statusCode));
    } on BackendException {
      rethrow;
    } catch (_) {
      throw BackendException(
        'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
      );
    }
  }

  /// Sunucudan gelen İngilizce mesajları uygulamanın diline çevirir.
  static String _friendly(String message, String? code) {
    switch (code) {
      case '23505':
        return 'Bu kayıt zaten mevcut.';
      case '42501':
      case 'PGRST301':
        return 'Bu işlem için yetkiniz yok.';
      case 'P0002':
        return 'Geçersiz kod.';
    }
    return message;
  }

  Future<List<Map<String, dynamic>>> _select(
    String table,
    Map<String, Object?> filters,
  ) async {
    var query = _db.from(table).select();
    filters.forEach((column, value) {
      // PostgREST `eq` null kabul etmez; süzgeçler her zaman somut değer taşır.
      if (value == null) return;
      query = query.eq(column, value);
    });
    final rows = await query;
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Sorguyu bir kez çalıştırır ve sonrasında değişikliklerde yeniden okur.
  ///
  /// Postgres değişiklik yayınları tek bir sütunda süzgeç destekler; bu yüzden
  /// canlı dinleme ilk eşleşen sütuna bağlanır, kalan süzgeçler sunucu
  /// sorgusunda uygulanır. Değişiklikte tam yeniden okuma yapılır — veri
  /// küçük olduğu için bu, kısmi güncelleme mantığına göre hem güvenli hem
  /// de daha az hataya açık.
  Stream<List<Map<String, dynamic>>> _watch(
    String table,
    Map<String, Object?> filters, {
    Map<String, dynamic>? Function(Map<String, dynamic>)? rowMapper,
  }) {
    if (!isReady) return Stream.value(const <Map<String, dynamic>>[]);
    final controller = StreamController<List<Map<String, dynamic>>>();
    late final RealtimeChannel channel;
    Timer? refreshTimer;
    var emitting = false;

    Future<void> emit() async {
      if (emitting || controller.isClosed) return;
      emitting = true;
      try {
        final rows = await _select(table, filters);
        if (controller.isClosed) return;
        final mapped = <Map<String, dynamic>>[];
        for (final row in rows) {
          // Mapper null döndürdüğünde satır bilinçli olarak filtrelenmiştir
          // (ör. yalnızca pending randevu talepleri). Bu satırları tekrar
          // eklemek psikolog ekranında eski taleplerin Onayla görünmesine ve
          // approve RPC'sinin "bekleyen kayıt bulunamadı" hatası vermesine
          // neden oluyordu.
          if (rowMapper == null) {
            mapped.add(row);
          } else {
            final mappedRow = rowMapper(row);
            if (mappedRow != null) mapped.add(mappedRow);
          }
        }
        controller.add(mapped);
      } catch (_) {
        // Ağ hatası akışı kesmez; bir sonraki değişiklikte yeniden denenir.
      } finally {
        emitting = false;
      }
    }

    channel = _db.channel(
      'mt:$table:${filters.entries.map((e) => '${e.key}=${e.value}').join('|')}',
    );
    // appointments satırları UPDATE olduğunda UUID filtreli Realtime kanalı
    // bazı tarayıcı/proxy bağlantılarında olayı kaçırabiliyor. RLS zaten
    // sorgu sonucunu kullanıcının kendi satırlarıyla sınırlandırdığı için bu
    // tabloda filtresiz kanal kullanıp güvenli filtrelemeyi SELECT'e bırak.
    if (table == 'appointments') {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => emit(),
      );
    } else {
      final firstKey = filters.keys.first;
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: firstKey,
          value: filters[firstKey].toString(),
        ),
        callback: (_) => emit(),
      );
    }

    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) emit();
    });

    // Supabase Realtime bağlantısı tarayıcı uykuya geçtiğinde, ağ değiştiğinde
    // veya proxy/websocket bağlantısı koptuğunda olay kaçırabilir. Realtime
    // olaylarını korurken kısa bir sorgu yedeği kullanmak, talep/onay
    // değişikliklerinin uygulamadan çıkıp girmeden görünmesini garanti eder.
    // Kısa süreli ağ kopmalarında akış kendini toparlasın; 2 saniyelik sorgu
    // döngüsü düşük cihazlarda gereksiz kasmaya neden oluyordu.
    refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => emit());

    controller.onCancel = () async {
      refreshTimer?.cancel();
      await _db.removeChannel(channel);
    };
    return controller.stream;
  }

  /// Tek satırlık kayıtların canlı akışı (`_watch` liste döndürür).
  Stream<T?> _watchOne<T>(
    String table,
    Map<String, Object?> filters, {
    required T? Function(Map<String, dynamic>) selector,
  }) {
    final controller = StreamController<T?>();
    late final RealtimeChannel channel;

    Future<void> emit() async {
      try {
        final rows = await _select(table, filters);
        if (controller.isClosed) return;
        controller.add(rows.isEmpty ? null : selector(rows.first));
      } catch (_) {
        // Ağ hatası akışı kesmez.
      }
    }

    final firstKey = filters.keys.first;
    channel = _db.channel(
      'mt1:$table:${filters.entries.map((e) => '${e.key}=${e.value}').join('|')}',
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: firstKey,
        value: filters[firstKey].toString(),
      ),
      callback: (_) => emit(),
    );
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) emit();
    });

    // İlk veriyi WebSocket aboneliğini beklemeden al. Aksi halde danışan,
    // Realtime bağlantısı geç kurulursa sonsuz yükleniyor ekranında kalır.
    unawaited(emit());

    controller.onCancel = () async {
      await _db.removeChannel(channel);
    };
    return controller.stream;
  }

  // --------------------------------------------- satır → eski alan adları ---

  Map<String, dynamic>? _legacyPatient(Map<String, dynamic> r) => {
    'consented': r['consented'] == true,
    'displayName': r['display_name'],
    'firstName': r['first_name'],
    'lastName': r['last_name'],
    'name': r['display_name'],
    'email': r['email'],
    'psychologistId': r['psychologist_id'],
    'localClientId': r['client_ref'],
    'diagnosisCodes': r['diagnosis_codes'],
  };

  Map<String, dynamic>? _legacyAppointment(Map<String, dynamic> r) => {
    'id': r['id'],
    'clientUserId': r['client_uid'] ?? r['clientUserId'],
    'clientRef': r['client_ref'] ?? r['clientRef'],
    'clientName': r['client_name'] ?? r['clientName'],
    'clientFirstName': r['client_first_name'] ?? r['clientFirstName'],
    'clientLastName': r['client_last_name'] ?? r['clientLastName'],
    'clientEmail': r['client_email'] ?? r['clientEmail'],
    'date': r['appointment_at'] ?? r['date'] ?? r['appointmentAt'],
    'status': r['status'],
    'type': r['type'],
    'linkedAppointmentId':
        r['linked_appointment_id'] ?? r['linkedAppointmentId'],
    'cancelledBy': r['cancelled_by'],
    'createdAtMs': _asMillis(r['created_at']),
  };

  Map<String, dynamic>? _legacyTask(Map<String, dynamic> r) => {
    'id': r['id'],
    'clientId': r['client_ref'],
    'clientUserId': r['client_uid'],
    'clientName': r['client_name'],
    'clientEmail': r['client_email'],
    'title': r['title'],
    'description': r['description'],
    'formId': r['form_ref'],
    'formDraft': r['form_draft'],
    'done': r['done'],
    'response': r['response'],
    'structuredAnswers': r['structured_answers'],
    'createdAtMs': _asMillis(r['created_at']),
  };

  Map<String, dynamic>? _legacyHomework(Map<String, dynamic> r) => {
    'id': r['id'],
    'clientId': r['client_ref'],
    'clientUserId': r['client_uid'],
    'clientEmail': r['client_email'],
    'title': r['title'],
    'description': r['description'],
    'status': r['status'],
    'response': r['response'],
    'createdAtMs': _asMillis(r['created_at']),
  };

  /// `timestamptz` alanlarını epoch milisaniyesine çevirir; arayüzde sıralama
  /// için sayısal karşılaştırma gerekiyor.
  static int _asMillis(Object? value) {
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    }
    if (value is DateTime) return value.millisecondsSinceEpoch;
    return 0;
  }
}

class BackendException implements Exception {
  BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StateConflictException extends BackendException {
  StateConflictException()
      : super(
          'Bu kayıt başka bir cihazda değiştirildi. Yerel değişiklikleriniz '
          'bu cihazda korundu; veri ezilmedi.',
        );
}

class OrganizationMembership {
  const OrganizationMembership({
    required this.organizationId,
    required this.role,
    required this.status,
  });

  final String organizationId;
  final String role;
  final String status;

  factory OrganizationMembership.fromJson(Map<String, dynamic> json) =>
      OrganizationMembership(
        organizationId: json['organization_id'] as String,
        role: json['role'] as String? ?? 'psychologist',
        status: json['status'] as String? ?? 'active',
      );
}

class OrganizationMember {
  const OrganizationMember({
    required this.userId,
    required this.email,
    required this.role,
    required this.status,
  });

  final String userId;
  final String email;
  final String role;
  final String status;

  factory OrganizationMember.fromJson(Map<String, dynamic> json) =>
      OrganizationMember(
        userId: json['user_id']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'psychologist',
        status: json['status']?.toString() ?? 'active',
      );
}

class RemoteStateSnapshot {
  const RemoteStateSnapshot({required this.data, required this.version});

  final Map<String, dynamic> data;
  final int version;
}

class PairingClaim {
  const PairingClaim({
    required this.psychologistId,
    required this.clientRef,
    required this.diagnosisCodes,
  });

  final String psychologistId;
  final String clientRef;
  final List<String> diagnosisCodes;
}

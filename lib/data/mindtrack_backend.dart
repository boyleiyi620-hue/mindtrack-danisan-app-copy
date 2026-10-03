import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client.dart';
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

  /// Web OAuth akışı. Supabase panelinde Google provider ve redirect URL'leri
  /// ayrıca etkinleştirilmelidir.
  Future<void> signInWithGoogle() async {
    await _guard(() async {
      await _db.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.origin,
      );
    });
  }

  Future<void> signOut() async {
    await _guard(() async => _db.auth.signOut());
  }

  // ------------------------------------------------ psikologun klinik kaydı ---

  /// Psikologun AppData'sının uzak kopyası. Psikologun tüm klinik kaydı
  /// tek bir jsonb satırında tutulur.
  Stream<Map<String, dynamic>?> watchState() {
    final uid = userId;
    if (uid == null) return Stream<Map<String, dynamic>?>.value(null);
    return _watchOne('psychologist_state', {
      'psychologist_id': uid,
    }, selector: (r) => r['data'] as Map<String, dynamic>?);
  }

  Future<void> saveState(Map<String, dynamic> data) async {
    final uid = userId;
    if (uid == null) return;
    await _guard(() async {
      await _db.from('psychologist_state').upsert({
        'psychologist_id': uid,
        'data': data,
      }, onConflict: 'psychologist_id');
    });
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
  }) async {
    final uid = userId;
    if (uid == null) return;
    final payload = <String, dynamic>{
      'display_name': ?displayName,
      'email': ?email,
      'consented': ?consented,
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
        if (uid.isNotEmpty && (status.isEmpty || status == 'paired'))
          return uid;
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
              .where((row) => row['status']?.toString() == 'pending')
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
    return _watch('tasks', {'client_uid': uid}, rowMapper: _legacyTask);
  }

  /// Psikologun gönderdiği görevler ve danışanların cevapları.
  ///
  /// Görevler `tasks` tablosunda tutulur; danışan cevabı `submit_task` RPC'si
  /// ile aynı satıra yazar. Psikolog tarafı bu akışı okumadığı için cevaplar
  /// veritabanında dursa da arayüzde görünmüyordu.
  Stream<List<Map<String, dynamic>>> watchPsychologistTasks() {
    final uid = userId;
    if (uid == null) return Stream.value(const []);
    return _watch('tasks', {'psychologist_id': uid}, rowMapper: _legacyTask);
  }

  /// `watchPsychologistTasks` akışının tek seferlik karşılığı. Canlı akış
  /// bağlantı kurulana kadar boş kalabilir; "Yenile" bunu kullanır.
  Future<List<Map<String, dynamic>>> psychologistTasks() async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await _select('tasks', {'psychologist_id': uid});
    return rows.map(_legacyTask).whereType<Map<String, dynamic>>().toList();
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

  Future<String> uploadPdf(String fileId, Uint8List bytes) async {
    final uid = userId;
    if (uid == null) throw BackendException('Oturum bulunamadı.');
    return _guard(() async {
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

  Future<Uint8List> downloadPdf(String path) async {
    return _guard(() => _db.storage.from(pdfBucket).download(path));
  }

  Future<void> deletePdf(String path) async {
    await _guard(() async {
      await _db.storage.from(pdfBucket).remove([path]);
    });
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
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => emit());

    controller.onCancel = () async {
      refreshTimer?.cancel();
      await _db.removeChannel(channel);
    };
    return controller.stream;
  }

  /// Tek satırlık kayıtların canlı akışı (`_watch` liste döndürür).
  Stream<Map<String, dynamic>?> _watchOne(
    String table,
    Map<String, Object?> filters, {
    required Map<String, dynamic>? Function(Map<String, dynamic>) selector,
  }) {
    final controller = StreamController<Map<String, dynamic>?>();
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
    'clientUserId': r['client_uid'],
    'clientRef': r['client_ref'],
    'clientName': r['client_name'],
    'clientFirstName': r['client_first_name'],
    'clientLastName': r['client_last_name'],
    'clientEmail': r['client_email'],
    'date': r['appointment_at'],
    'status': r['status'],
    'type': r['type'],
    'linkedAppointmentId': r['linked_appointment_id'],
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

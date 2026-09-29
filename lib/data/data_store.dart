import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_data.dart';
import '../models/appointment.dart';
import '../models/assessment.dart';
import '../models/client.dart';
import '../models/form_entry.dart';
import '../models/note.dart';
import '../models/pdf_library.dart';
import '../models/plan.dart';
import '../models/task.dart';
import '../models/user_account.dart';
import 'account_store.dart';
import 'appointment_sync.dart';
import 'mindtrack_backend.dart';

/// Kullanıcıya özel veri deposu — her değişiklikte kaydeder ve ekranlara haber verir.
class DataStore extends ChangeNotifier {
  final AccountStore accounts;
  AppData data = AppData.empty();
  int _uidCounter = 0;
  bool _remoteLoading = false;
  bool _remoteSaving = false;
  String? _pendingRemoteEncoded;
  StreamSubscription<Map<String, dynamic>?>? _remoteSubscription;

  DataStore(this.accounts) {
    load();
  }

  bool get hasAccount => accounts.current != null;

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
      data = AppData.empty();
      notifyListeners();
      return;
    }
    try {
      final raw = _prefs.getString(accounts.dataKey(u));
      if (raw != null && raw.isNotEmpty) {
        data = AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } else {
        data = AppData.empty();
      }
    } catch (_) {
      data = AppData.empty();
    }
    notifyListeners();
    _loadRemote();
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
    _remoteSubscription = backend.watchState().listen(
      (remote) => _applyRemoteState(remote, localUser),
      onError: (_) {},
    );
    _remoteLoading = false;
  }

  Future<void> _applyRemoteState(
    Map<String, dynamic>? remote,
    UserAccount localUser,
  ) async {
    if (remote == null) return;
    try {
      final next = AppData.fromJson(remote);
      await _hydratePdfs(next);
      final encoded = jsonEncode(next.toJson());
      data = next;
      await _prefs.setString(accounts.dataKey(localUser), encoded);
      notifyListeners();
    } catch (_) {
      // Bozuk uzak veri mevcut yerel verinin üzerine yazılmaz.
    }
  }

  /// Uzak kopyada yalnızca yol saklanan PDF'leri indirip `dataUrl` alanını
  /// doldurur. Böylece PDF kütüphanesi ekranda her zaman yerel çalışır.
  Future<void> _hydratePdfs(AppData next) async {
    for (final file in next.pdfFiles) {
      if (file.dataUrl.isNotEmpty || file.storagePath.isEmpty) continue;
      try {
        final bytes = await MindTrackBackend.instance.downloadPdf(
          file.storagePath,
        );
        file.dataUrl = 'data:${file.type};base64,${base64Encode(bytes)}';
      } catch (_) {
        // Dosya uzak depoda yoksa kütüphane satırı boş kalır, uygulama çalışır.
      }
    }
  }

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    super.dispose();
  }

  void save() {
    final u = accounts.current;
    if (u == null) return;
    final encoded = jsonEncode(data.toJson());
    _prefs.setString(accounts.dataKey(u), encoded);
    notifyListeners();
    _saveRemote(encoded);
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

  Future<void> _saveRemote(String encoded) async {
    // Arka arkaya gelen işlemlerden hiçbiri kaybolmasın: yeni kayıt, devam eden
    // uzak yazmanın arkasında kuyruğa alınır ve son durum ayrıca yazılır.
    _pendingRemoteEncoded = encoded;
    if (_remoteSaving) return;
    _remoteSaving = true;
    try {
      while (_pendingRemoteEncoded != null) {
        final payload = _pendingRemoteEncoded!;
        _pendingRemoteEncoded = null;
        final backend = MindTrackBackend.instance;
        if (!backend.isSignedIn) break;
        try {
          // Base64 PDF'ler önce Storage'a çıkarılır; jsonb gövdesi hafif kalır.
          // Aksi halde ücretsiz plandaki 500 MB'lık veritabanı birkaç dosyada
          // dolar ve (eski sürümdeki gibi) senkron tümüyle durur.
          final slim = await _slimForRemote(payload);
          await backend.saveState(slim);
        } catch (_) {
          // Yerel kayıt korunur; sonraki kullanıcı işleminde yeniden denenir.
        }
      }
    } finally {
      _remoteSaving = false;
    }
  }

  /// PDF ikili içeriklerini Storage'a yükleyip gövdeden çıkarır.
  ///
  /// `data` nesnesine dokunmaz; yalnızca gönderilecek kopya hafifletilir,
  /// böylece cihazdaki yerel kopyalar bozulmaz.
  Future<Map<String, dynamic>> _slimForRemote(String encoded) async {
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final files = decoded['pdfFiles'];
    if (files is! List || files.isEmpty) return decoded;
    for (final raw in files) {
      if (raw is! Map) continue;
      final dataUrl = raw['dataUrl']?.toString() ?? '';
      if (dataUrl.isEmpty) continue;
      if ((raw['storagePath']?.toString() ?? '').isNotEmpty) {
        raw['dataUrl'] = '';
        continue;
      }
      final bytes = _decodeDataUrl(dataUrl);
      if (bytes == null) continue;
      try {
        final path = await MindTrackBackend.instance.uploadPdf(
          raw['id'].toString(),
          bytes,
        );
        raw['storagePath'] = path;
        raw['dataUrl'] = '';
      } catch (_) {
        // Yükleme başarısız olursa bu dosya için gövde olduğu gibi kalır.
      }
    }
    return decoded;
  }

  Uint8List? _decodeDataUrl(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  void resetAll() {
    data = AppData.empty();
    save();
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

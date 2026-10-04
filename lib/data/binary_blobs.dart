/// Belge (PDF) ikililerinin taşınmasıyla ilgili saf yardımcılar.
///
/// İki büyük maliyet buradan çözülüyor:
///  1. **Gövde şişkinliği** — base64 ikililer `psychologist_state` jsonb
///     satırına gömülürse veritabanı birkaç dosyada dolar. Gövde sunucu
///     deposuna çıkarılır, satıra yalnızca yol yazılır.
///  2. **Bant genişliği** — sunucu yalnızca yol taşıdığı için her senkronizasyonda
///     dosyaları indirmek zorunda değiliz; bu cihazda önbelleği olan belgeler
///     korunur, olmayanlar kullanıcı açtığında indirilir.
///
/// Buradaki fonksiyonlar sunucudan bağımsızdır; testlerde doğrudan
/// doğrulanabilirler. Yükleme/indirme işini `DataStore` yapar.
library;

import 'dart:typed_data';

import '../models/app_data.dart';
import '../utils/formats.dart';

/// `AppData.toJson()` içinde ikili gövdesi taşıyan listelerin adları.
const String pdfFilesKey = 'pdfFiles';
const String documentsKey = 'documents';

const List<String> binaryCollections = <String>[pdfFilesKey, documentsKey];

/// Sunucuya yüklenmesi gereken tek bir belge gövdesi.
class InlineBinary {
  const InlineBinary({
    required this.collection,
    required this.id,
    required this.bytes,
  });

  /// Kaynak listenin adı ([pdfFilesKey] veya [documentsKey]).
  final String collection;

  /// Kaydın kimliği; sunucu yolu `<psikolog uid>/<id>` olarak kurulur.
  final String id;

  /// Base64 gövdeden çözülmüş ikili içerik.
  final Uint8List bytes;
}

/// Zaten sunucuda olan gövdeleri gönderilecek kopyadan düşürür.
///
/// Yalnızca [InlineBinary] dönen kayıtlar için çağrılır: yolu olan kaydın
/// kopyası depoda gerçekten var, dolayısıyla gövdesini atmak veri kaybı
/// yaratmaz. Bu sayede aynı dosya her senkronizasyonda yeniden yüklenmez.
void dropUploadedBodies(Map<String, dynamic> payload) {
  for (final collection in binaryCollections) {
    final items = payload[collection];
    if (items is! List) continue;
    for (final raw in items) {
      if (raw is! Map) continue;
      if ((raw['storagePath']?.toString() ?? '').isEmpty) continue;
      raw['dataUrl'] = '';
    }
  }
}

/// Yüklenmesi gereken gövdeleri bulur; **payload'u değiştirmez**.
///
/// Yükleme başarısızlığında gövde gönderilecek kopyada yerinde kalabilmeli
/// (aksi halde sunucuya hiç ulaşamayan belge kaybolur). Bu yüzden önce yol
/// yazılmaz, [applyStoragePath] yalnızca yükleme başarılı olduktan sonra
/// çağrılır.
List<InlineBinary> extractInlineBinaries(Map<String, dynamic> payload) {
  final pending = <InlineBinary>[];
  for (final collection in binaryCollections) {
    final items = payload[collection];
    if (items is! List) continue;
    for (final raw in items) {
      if (raw is! Map) continue;
      if ((raw['storagePath']?.toString() ?? '').isNotEmpty) continue;
      final dataUrl = raw['dataUrl']?.toString() ?? '';
      if (dataUrl.isEmpty) continue;
      final bytes = bytesFromDataUrl(dataUrl);
      if (bytes.isEmpty) continue;
      pending.add(InlineBinary(
        collection: collection,
        id: raw['id'].toString(),
        bytes: bytes,
      ));
    }
  }
  return pending;
}

/// Başarıyla yüklenen belgenin yolunu gövdeye yazar ve gövdeyi düşürür.
void applyStoragePath(
  Map<String, dynamic> payload,
  String collection,
  String id,
  String path,
) {
  final items = payload[collection];
  if (items is! List) return;
  for (final raw in items) {
    if (raw is! Map) continue;
    if (raw['id'].toString() != id) continue;
    raw['storagePath'] = path;
    raw['dataUrl'] = '';
    return;
  }
}

/// Uzak durum bu cihaza uygulanırken, burada indirilmiş belgelerin gövdesini
/// korur.
///
/// Sunucu gövdeyi taşımaz (yalnızca yol), dolayısıyla uzak durum koşulsuz
/// üzerine yazılırsa bu cihazdaki önbellek de silinir ve kütüphanenin tamamı
/// her senkronizasyonda yeniden indirilir. Koruma yalnızca kimliği eşleşen
/// kayıtlar içindir; yeni gelen belgeler tembel indirmeye bırakılır.
void carryLocalBinaries(AppData next, AppData local) {
  if (local.pdfFiles.isNotEmpty) {
    final cached = <String, String>{
      for (final file in local.pdfFiles)
        if (file.dataUrl.isNotEmpty) file.id: file.dataUrl,
    };
    for (final file in next.pdfFiles) {
      final body = cached[file.id];
      if (body != null) file.dataUrl = body;
    }
  }
  if (local.documents.isNotEmpty) {
    final cached = <String, String>{
      for (final doc in local.documents)
        if (doc.dataUrl.isNotEmpty) doc.id: doc.dataUrl,
    };
    for (final doc in next.documents) {
      final body = cached[doc.id];
      if (body != null) doc.dataUrl = body;
    }
  }
}

/// Belgenin bu cihazda indirilmiş kopyası var mı?
bool isCached(String dataUrl) => dataUrl.isNotEmpty;

/// Belgeyi açmadan önce indirilmesi gerekiyor mu?
bool needsDownload(String dataUrl, String storagePath) =>
    dataUrl.isEmpty && storagePath.isNotEmpty;

/// Veri nesnesindeki kayda uzak yolu yazar; kaydı bulursa `true` döner.
///
/// Böylece bir kez yüklenen dosya için sonraki senkronizasyonlarda yol
/// gönderilecek kopyada da yerel kayıtta da bulunur.
bool stampStoragePath(AppData target, String collection, String id, String path) {
  if (collection == pdfFilesKey) {
    for (final file in target.pdfFiles) {
      if (file.id != id) continue;
      file.storagePath = path;
      return true;
    }
    return false;
  }
  if (collection == documentsKey) {
    for (final doc in target.documents) {
      if (doc.id != id) continue;
      doc.storagePath = path;
      return true;
    }
    return false;
  }
  return false;
}

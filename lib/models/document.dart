/// Danışan dokümanı (PDF).
///
/// Büyük içerik gövdeye gömülmez: dosya sunucu deposuna yüklenir ve burada
/// yalnızca [storagePath] tutulur. [dataUrl] yalnızca bu cihazdaki önbellektir;
/// sunucudan ilk gelen belgede boştur ve kullanıcı belgeyi açtığında indirilir.
class Document {
  final String id;
  String clientId;
  String name;
  String type; // application/pdf ...
  int size;
  String dataUrl; // base64 (yalnızca bu cihazdaki önbellek)

  /// Uzak depoda tutulan yol (`<psikolog uid>/<id>`). Boşsa belge henüz
  /// sunucuya çıkmamıştır ve gövde gönderilirken yerinde kalır.
  String storagePath;
  double addedAt;

  Document({
    required this.id,
    required this.clientId,
    required this.name,
    required this.dataUrl,
    this.type = 'application/pdf',
    this.size = 0,
    this.storagePath = '',
    double? addedAt,
  }) : addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch.toDouble();

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientId': clientId,
        'name': name,
        'type': type,
        'size': size,
        'dataUrl': dataUrl,
        'storagePath': storagePath,
        'addedAt': addedAt,
      };

  factory Document.fromJson(Map<String, dynamic> j) => Document(
        id: j['id'] as String,
        clientId: j['clientId'] as String? ?? '',
        name: j['name'] as String? ?? 'belge.pdf',
        type: j['type'] as String? ?? 'application/pdf',
        size: (j['size'] as num?)?.toInt() ?? 0,
        dataUrl: j['dataUrl'] as String? ?? '',
        storagePath: j['storagePath'] as String? ?? '',
        addedAt: (j['addedAt'] as num?)?.toDouble() ?? 0,
      );
}

/// PDF Kütüphanesi: kategoriler ve dosyalar.
class PdfCategory {
  final String id;
  String name;
  double createdAt;

  PdfCategory({required this.id, required this.name, double? createdAt})
      : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch.toDouble();

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'createdAt': createdAt};

  factory PdfCategory.fromJson(Map<String, dynamic> j) => PdfCategory(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        createdAt: (j['createdAt'] as num?)?.toDouble() ?? 0,
      );
}

class PdfFile {
  final String id;
  String catId;
  String name;
  String type;
  int size;
  String dataUrl;
  double addedAt;

  /// Uzak depoda tutulan yol (`<psikolog uid>/<id>`). Base64 içerik
  /// jsonb'ye gömülmez; cihazda yerel kopyası yoksa indirilir.
  String storagePath;

  PdfFile({
    required this.id,
    required this.catId,
    required this.name,
    required this.dataUrl,
    this.type = 'application/pdf',
    this.size = 0,
    this.storagePath = '',
    double? addedAt,
  }) : addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch.toDouble();

  Map<String, dynamic> toJson() => {
        'id': id,
        'catId': catId,
        'name': name,
        'type': type,
        'size': size,
        'dataUrl': dataUrl,
        'storagePath': storagePath,
        'addedAt': addedAt,
      };

  factory PdfFile.fromJson(Map<String, dynamic> j) => PdfFile(
        id: j['id'] as String,
        catId: j['catId'] as String? ?? '',
        name: j['name'] as String? ?? 'dosya.pdf',
        type: j['type'] as String? ?? 'application/pdf',
        size: (j['size'] as num?)?.toInt() ?? 0,
        dataUrl: j['dataUrl'] as String? ?? '',
        storagePath: j['storagePath'] as String? ?? '',
        addedAt: (j['addedAt'] as num?)?.toDouble() ?? 0,
      );
}

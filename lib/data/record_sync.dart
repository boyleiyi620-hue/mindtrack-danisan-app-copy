import 'dart:convert';

import '../models/app_data.dart';

/// AppData içindeki bir kaydın sunucuya taşınan biçimi.
///
/// [expectedVersion] optimistic concurrency kontrolünde kullanılır. Silinen
/// kayıtlar gövde yerine [deletedAt] ile tombstone olarak taşınır.
class RecordEnvelope {
  const RecordEnvelope({
    required this.recordType,
    required this.recordId,
    required this.data,
    this.expectedVersion = 0,
    this.deletedAt,
  });

  final String recordType;
  final String recordId;
  final Map<String, dynamic> data;
  final int expectedVersion;
  final DateTime? deletedAt;

  Map<String, dynamic> toJson() => {
        'record_type': recordType,
        'record_id': recordId,
        'data': data,
        'expected_version': expectedVersion,
        if (deletedAt != null) 'deleted_at': deletedAt!.toUtc().toIso8601String(),
      };
}

/// Bir kaydın önceki snapshot'tan çıkarıldığını temsil eder.
class RecordChangeSet {
  const RecordChangeSet({required this.upserts, required this.deletes});

  final List<RecordEnvelope> upserts;
  final List<RecordEnvelope> deletes;

  List<RecordEnvelope> get all => [...upserts, ...deletes];
}

const Map<String, String> _collectionToRecordType = {
  'forms': 'form',
  'clients': 'client',
  'assessments': 'assessment',
  'appointments': 'appointment',
  'notes': 'note',
  'plans': 'plan',
  'tasks': 'task',
  'documents': 'document',
  'pdfCats': 'pdf_category',
  'pdfFiles': 'pdf_file',
  'transactions': 'transaction',
  'trainings': 'training',
  'financeGoals': 'finance_goal',
};

const Map<String, String> _recordTypeToCollection = {
  for (final entry in _collectionToRecordType.entries)
    entry.value: entry.key,
};

/// AppData'yı kayıt bazlı sunucu payload'una çevirir.
List<RecordEnvelope> recordsFromAppData(
  AppData value, {
  Map<String, int> expectedVersions = const {},
}) {
  final json = value.toJson();
  final records = <RecordEnvelope>[];
  for (final entry in _collectionToRecordType.entries) {
    final items = json[entry.key];
    if (items is! List) continue;
    for (final item in items) {
      if (item is! Map) continue;
      final data = Map<String, dynamic>.from(item);
      final id = data['id']?.toString().trim();
      if (id == null || id.isEmpty) continue;
      records.add(RecordEnvelope(
        recordType: entry.value,
        recordId: id,
        data: data,
        expectedVersion: expectedVersions['${entry.value}:$id'] ?? 0,
      ));
    }
  }
  return records;
}

/// İki AppData snapshot'ı arasındaki kayıt değişikliklerini çıkarır.
///
/// Kayıt kimlikleri türle birlikte değerlendirilir; bu nedenle farklı
/// koleksiyonlarda aynı id kullanılması çakışma oluşturmaz.
RecordChangeSet diffAppData(AppData previous, AppData current) {
  final before = _index(recordsFromAppData(previous));
  final after = _index(recordsFromAppData(current));
  final upserts = <RecordEnvelope>[];
  final deletes = <RecordEnvelope>[];

  for (final entry in after.entries) {
    final old = before[entry.key];
    if (old == null || jsonEncode(old.data) != jsonEncode(entry.value.data)) {
      upserts.add(entry.value);
    }
  }
  final now = DateTime.now().toUtc();
  for (final entry in before.entries) {
    if (!after.containsKey(entry.key)) {
      deletes.add(RecordEnvelope(
        recordType: entry.value.recordType,
        recordId: entry.value.recordId,
        data: const {},
        deletedAt: now,
      ));
    }
  }
  return RecordChangeSet(upserts: upserts, deletes: deletes);
}

Map<String, RecordEnvelope> _index(Iterable<RecordEnvelope> records) => {
      for (final record in records)
        '${record.recordType}:${record.recordId}': record,
    };

/// Kayıt payload'larını eski AppData ekran modeline dönüştürür.
/// Tombstone kayıtları bilinçli olarak atlanır.
AppData appDataFromRecords(Iterable<Map<String, dynamic>> rows) {
  final collections = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    if (row['deleted_at'] != null) continue;
    final type = row['record_type']?.toString();
    final collection = _recordTypeToCollection[type];
    final data = row['data'];
    if (collection == null || data is! Map) continue;
    collections.putIfAbsent(collection, () => []).add(
          Map<String, dynamic>.from(data),
        );
  }
  return AppData.fromJson(collections);
}

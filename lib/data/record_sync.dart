import 'dart:convert';

import 'package:crypto/crypto.dart';

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

  RecordEnvelope copyWith({int? expectedVersion}) => RecordEnvelope(
    recordType: recordType,
    recordId: recordId,
    data: data,
    expectedVersion: expectedVersion ?? this.expectedVersion,
    deletedAt: deletedAt,
  );
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

final Map<String, String> _recordTypeToCollection = {
  for (final entry in _collectionToRecordType.entries) entry.value: entry.key,
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
      // FinanceGoal predates record sync and has no id field; its unique
      // YYYY-MM month is its stable identity for upserts and tombstones.
      final id =
          (data['id'] ?? (entry.value == 'finance_goal' ? data['month'] : null))
              ?.toString()
              .trim();
      if (id == null || id.isEmpty) continue;
      records.add(
        RecordEnvelope(
          recordType: entry.value,
          recordId: id,
          data: data,
          expectedVersion: expectedVersions['${entry.value}:$id'] ?? 0,
        ),
      );
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
      deletes.add(
        RecordEnvelope(
          recordType: entry.value.recordType,
          recordId: entry.value.recordId,
          data: const {},
          deletedAt: now,
        ),
      );
    }
  }
  return RecordChangeSet(upserts: upserts, deletes: deletes);
}

Set<String> recordKeysFromAppData(AppData value) => {
  for (final record in recordsFromAppData(value))
    '${record.recordType}:${record.recordId}',
};

String recordKeyHash(String key) => sha256.convert(utf8.encode(key)).toString();

Set<String> removedRecordKeys(AppData previous, AppData current) =>
    recordKeysFromAppData(previous)
        .difference(recordKeysFromAppData(current))
        .map(recordKeyHash)
        .toSet();

/// Removes locally deleted records after a remote/local union merge. The
/// persisted queue contains hashes, not record ids or clinical payloads.
AppData removeRecordsByKey(AppData value, Set<String> keys) {
  if (keys.isEmpty) return value;
  final json = value.toJson();
  for (final entry in _collectionToRecordType.entries) {
    final records = json[entry.key];
    if (records is! List) continue;
    json[entry.key] = records.where((item) {
      if (item is! Map) return true;
      final id =
          (item['id'] ?? (entry.value == 'finance_goal' ? item['month'] : null))
              ?.toString()
              .trim();
      return id == null || !keys.contains(recordKeyHash('${entry.value}:$id'));
    }).toList();
  }
  return AppData.fromJson(json);
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
    collections
        .putIfAbsent(collection, () => [])
        .add(Map<String, dynamic>.from(data));
  }
  return AppData.fromJson(collections);
}

/// Applies only changed rows to an existing remote base. This is important
/// during a gradual psychologist_state -> psychologist_records rollout: an
/// empty/partial record table must not erase unrelated legacy-state records.
AppData applyRemoteRecordRows(
  AppData base,
  Iterable<Map<String, dynamic>> rows,
) {
  final collections = base.toJson();
  for (final row in rows) {
    final collection = _recordTypeToCollection[row['record_type']?.toString()];
    if (collection == null) continue;
    final id = row['record_id']?.toString();
    if (id == null || id.isEmpty) continue;
    final current = collections[collection];
    final records = current is List
        ? current.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    records.removeWhere((record) {
      final recordId =
          (record['id'] ??
                  (collection == 'financeGoals' ? record['month'] : null))
              ?.toString();
      return recordId == id;
    });
    final data = row['data'];
    if (row['deleted_at'] == null && data is Map) {
      records.add(Map<String, dynamic>.from(data));
    }
    collections[collection] = records;
  }
  return AppData.fromJson(collections);
}

Map<String, int> recordVersionsFromRows(Iterable<Map<String, dynamic>> rows) =>
    {
      for (final row in rows)
        '${row['record_type']}:${row['record_id']}':
            (row['record_version'] as num?)?.toInt() ?? 0,
    };

/// A narrow invalidation row returned by the server-side sync trigger. The
/// trigger stores identity/version metadata only; clinical JSON stays in the
/// owner-RLS protected source table.
class SyncSignalBatch {
  const SyncSignalBatch({required this.rows, required this.updatedThrough});

  final List<Map<String, dynamic>> rows;
  final DateTime? updatedThrough;
}

/// Shared, deterministic watermark for psychologist-record and task changes.
/// The overlap deliberately re-reads recent signal metadata to cover timestamp
/// ties, in-flight transactions, reconnect gaps, and duplicate delivery.
class SyncCursor {
  const SyncCursor(this.updatedAt);

  static const Duration overlap = Duration(minutes: 10);

  final DateTime? updatedAt;

  DateTime? get querySince => updatedAt?.toUtc().subtract(overlap);

  SyncCursor advance(DateTime? candidate) {
    if (candidate == null) return this;
    final next = candidate.toUtc();
    if (updatedAt == null || next.isAfter(updatedAt!.toUtc())) {
      return SyncCursor(next);
    }
    return this;
  }

  String? get storageValue => updatedAt?.toUtc().toIso8601String();

  static SyncCursor? parse(String? value) {
    final parsed = value == null ? null : DateTime.tryParse(value);
    return parsed == null ? null : SyncCursor(parsed.toUtc());
  }

  static SyncCursor? fromRows(Iterable<Map<String, dynamic>> rows) {
    DateTime? latest;
    for (final row in rows) {
      final value = DateTime.tryParse(row['updated_at']?.toString() ?? '');
      if (value != null && (latest == null || value.isAfter(latest))) {
        latest = value;
      }
    }
    return latest == null ? null : SyncCursor(latest.toUtc());
  }
}

/// Stable ordering for page boundaries and timestamp ties.
int compareSyncRows(Map<String, dynamic> left, Map<String, dynamic> right) {
  final leftTime = DateTime.tryParse(left['updated_at']?.toString() ?? '');
  final rightTime = DateTime.tryParse(right['updated_at']?.toString() ?? '');
  final timeCompare =
      (leftTime?.compareTo(
        rightTime ?? DateTime.fromMillisecondsSinceEpoch(0),
      ) ??
      0);
  if (timeCompare != 0) return timeCompare;
  for (final key in const ['entity_type', 'record_type', 'record_id']) {
    final compare = (left[key]?.toString() ?? '').compareTo(
      right[key]?.toString() ?? '',
    );
    if (compare != 0) return compare;
  }
  return 0;
}

int syncRecordVersion(Map<String, dynamic>? row) =>
    (row?['record_version'] as num?)?.toInt() ?? 0;

String syncRecordKey(Map<String, dynamic> row) =>
    '${row['record_type']}:${row['record_id']}';

/// Replaces a cached remote row only when its server revision is newer.
/// Duplicate and out-of-order Realtime signals therefore cannot roll back data.
bool applyNewerRecordRow(
  Map<String, Map<String, dynamic>> rows,
  Map<String, dynamic> incoming,
) {
  final key = syncRecordKey(incoming);
  if (key == 'null:null' || key.startsWith('null:') || key.endsWith(':null')) {
    return false;
  }
  final existing = rows[key];
  if (existing != null &&
      syncRecordVersion(incoming) <= syncRecordVersion(existing)) {
    return false;
  }
  rows[key] = Map<String, dynamic>.from(incoming);
  return true;
}

/// Applies one fetched task row after an invalidation signal. Task rows do not
/// have record_version, so the signal's monotonic updated_at is the revision.
bool applyTaskSyncRow({
  required Map<String, Map<String, dynamic>> rows,
  required Map<String, int> appliedSignalVersions,
  required Map<String, dynamic> signal,
  required Map<String, dynamic>? fetchedRow,
}) {
  final id = signal['record_id']?.toString();
  if (id == null || id.isEmpty) return false;
  final stamp = DateTime.tryParse(signal['updated_at']?.toString() ?? '');
  final version =
      stamp?.microsecondsSinceEpoch ??
      (signal['record_version'] as num?)?.toInt() ??
      0;
  if (version <= (appliedSignalVersions[id] ?? 0)) return false;
  if (signal['deleted_at'] != null || fetchedRow == null) {
    rows.remove(id);
    appliedSignalVersions[id] = version;
    return true;
  }
  final previous = rows[id];
  final oldAt = DateTime.tryParse(previous?['updated_at']?.toString() ?? '');
  final newAt = DateTime.tryParse(fetchedRow['updated_at']?.toString() ?? '');
  if (oldAt != null && newAt != null && newAt.isBefore(oldAt)) return false;
  rows[id] = Map<String, dynamic>.from(fetchedRow);
  appliedSignalVersions[id] = version;
  return true;
}

/// Reads all pages without relying on server row order. Callers provide stable
/// ordering on the query; this helper is shared by initial and delta snapshots.
Future<List<T>> fetchAllPages<T>(
  Future<List<T>> Function(int offset, int limit) fetchPage, {
  int pageSize = 500,
}) async {
  if (pageSize < 1) throw ArgumentError.value(pageSize, 'pageSize');
  final result = <T>[];
  var offset = 0;
  while (true) {
    final page = await fetchPage(offset, pageSize);
    result.addAll(page);
    if (page.length < pageSize) return result;
    offset += page.length;
  }
}

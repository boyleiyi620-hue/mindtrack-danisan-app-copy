import 'package:flutter_test/flutter_test.dart';
import 'package:mindtrack_danisan_app/data/record_sync.dart';
import 'package:mindtrack_danisan_app/models/app_data.dart';
import 'package:mindtrack_danisan_app/models/client.dart';

void main() {
  test('ilk snapshot tüm sayfaları sabit offsetlerle toplar', () async {
    const source = ['r1', 'r2', 'r3', 'r4', 'r5'];
    final offsets = <int>[];
    final rows = await fetchAllPages<String>((offset, limit) async {
      offsets.add(offset);
      return source.skip(offset).take(limit).toList();
    }, pageSize: 2);

    expect(rows, source);
    expect(offsets, [0, 2, 4]);
  });

  test('cursor timestamp eşitliğinde örtüşme uygular ve geriye gitmez', () {
    final start = DateTime.parse('2026-10-16T00:00:00Z');
    final cursor = SyncCursor(start);
    expect(cursor.querySince, start.subtract(SyncCursor.overlap));
    expect(
      cursor.advance(start.subtract(const Duration(seconds: 1))).updatedAt,
      start,
    );
    expect(
      cursor.advance(start.add(const Duration(seconds: 1))).updatedAt,
      start.add(const Duration(seconds: 1)),
    );
    expect(
      SyncCursor.parse(
        cursor.advance(start.add(const Duration(seconds: 1))).storageValue,
      )?.updatedAt,
      start.add(const Duration(seconds: 1)),
    );
  });

  test('eşit zamanlı delta satırları deterministik anahtar sırası alır', () {
    final at = '2026-10-16T00:00:00Z';
    final rows = [
      {'updated_at': at, 'record_type': 'note', 'record_id': 'b'},
      {'updated_at': at, 'record_type': 'client', 'record_id': 'z'},
      {'updated_at': at, 'record_type': 'client', 'record_id': 'a'},
    ]..sort(compareSyncRows);

    expect(rows.map((row) => '${row['record_type']}:${row['record_id']}'), [
      'client:a',
      'client:z',
      'note:b',
    ]);
  });

  test('yinelenen ve sıra dışı sürüm kayıt cache’ini geriye alamaz', () {
    final cache = <String, Map<String, dynamic>>{};
    final v2 = {
      'record_type': 'client',
      'record_id': 'c1',
      'record_version': 2,
      'data': {'id': 'c1', 'name': 'İki'},
    };
    final v3 = {
      'record_type': 'client',
      'record_id': 'c1',
      'record_version': 3,
      'data': {'id': 'c1', 'name': 'Üç'},
    };

    expect(applyNewerRecordRow(cache, v3), isTrue);
    expect(applyNewerRecordRow(cache, v3), isFalse);
    expect(applyNewerRecordRow(cache, v2), isFalse);
    expect(cache['client:c1']?['data']['name'], 'Üç');
  });

  test('tombstone silmeyi taşır ve klinik kaydı snapshota geri koymaz', () {
    final tombstone = {
      'record_type': 'client',
      'record_id': 'c1',
      'record_version': 4,
      'data': <String, dynamic>{},
      'deleted_at': '2026-10-16T00:00:00Z',
    };
    expect(appDataFromRecords([tombstone]).clients, isEmpty);
    final changes = diffAppData(
      AppData(
        clients: [Client(id: 'c1', name: 'Danışan')],
      ),
      AppData.empty(),
    );
    expect(changes.deletes.single.deletedAt, isNotNull);
  });

  test('kısmi remote delta diğer legacy kayıtlarını korur', () {
    final base = AppData(
      clients: [
        Client(id: 'legacy', name: 'Legacy state kaydı'),
        Client(id: 'changed', name: 'Eski değer'),
      ],
    );
    final updated = applyRemoteRecordRows(base, [
      {
        'record_type': 'client',
        'record_id': 'changed',
        'record_version': 2,
        'deleted_at': null,
        'data': {'id': 'changed', 'name': 'Yeni değer'},
      },
      {
        'record_type': 'client',
        'record_id': 'deleted',
        'record_version': 4,
        'deleted_at': '2026-10-16T00:00:00Z',
        'data': <String, dynamic>{},
      },
    ]);

    expect(updated.clientById('legacy')?.name, 'Legacy state kaydı');
    expect(updated.clientById('changed')?.name, 'Yeni değer');
    expect(updated.clientById('deleted'), isNull);
  });

  test('kaçırılmış sinyalin sonraki delta turunda tekrar uygulanması idempotenttir', () {
    final before = DateTime.parse('2026-10-16T00:00:00Z');
    final later = before.add(const Duration(seconds: 2));
    final cursor = SyncCursor(before);
    final cache = <String, Map<String, dynamic>>{};
    final changedRow = {
      'record_type': 'client',
      'record_id': 'c2',
      'record_version': 1,
      'data': {'id': 'c2', 'name': 'Yeni kayıt'},
    };

    // A missed websocket event is recovered by the overlapping delta window;
    // replaying it does not duplicate or roll back the local row.
    expect(later.isAfter(cursor.querySince!), isTrue);
    expect(applyNewerRecordRow(cache, changedRow), isTrue);
    expect(applyNewerRecordRow(cache, changedRow), isFalse);
    expect(cache, hasLength(1));
  });

  test(
    'çevrimdışı yerel değişiklik bağlantı dönünce remote snapshotta korunur',
    () {
      final remote = AppData(
        clients: [Client(id: 'remote', name: 'Sunucudaki danışan')],
      );
      final local = AppData(
        clients: [
          Client(id: 'remote', name: 'Bu cihazdaki son düzenleme'),
          Client(id: 'offline', name: 'Çevrimdışı eklenen'),
        ],
      );

      final reconciled = AppData.reconcileInitialRemote(
        remote: remote,
        local: local,
        preserveLocalChanges: true,
      );
      expect(
        reconciled.clients.map((client) => client.id),
        containsAll(['remote', 'offline']),
      );
      expect(
        reconciled.clientById('remote')?.name,
        'Bu cihazdaki son düzenleme',
      );
    },
  );

  test('danışan görev delta satırı yenilenir; duplicate, eski olay ve tombstone güvenlidir', () {
    final taskRows = <String, Map<String, dynamic>>{
      't1': {
        'id': 't1',
        'title': 'Eski başlık',
        'updated_at': '2026-10-16T00:00:00Z',
      },
    };
    final applied = <String, int>{};
    final update = {
      'record_id': 't1',
      'updated_at': '2026-10-16T00:01:00Z',
      'record_version': 1,
    };
    final fetched = {
      'id': 't1',
      'title': 'Yeni başlık',
      'updated_at': '2026-10-16T00:01:00Z',
    };

    expect(
      applyTaskSyncRow(
        rows: taskRows,
        appliedSignalVersions: applied,
        signal: update,
        fetchedRow: fetched,
      ),
      isTrue,
    );
    expect(taskRows['t1']?['title'], 'Yeni başlık');
    expect(
      applyTaskSyncRow(
        rows: taskRows,
        appliedSignalVersions: applied,
        signal: update,
        fetchedRow: fetched,
      ),
      isFalse,
    );
    expect(
      applyTaskSyncRow(
        rows: taskRows,
        appliedSignalVersions: applied,
        signal: {'record_id': 't1', 'updated_at': '2026-10-16T00:00:30Z'},
        fetchedRow: {
          'id': 't1',
          'title': 'Eski başlık',
          'updated_at': '2026-10-16T00:00:30Z',
        },
      ),
      isFalse,
    );
    expect(
      applyTaskSyncRow(
        rows: taskRows,
        appliedSignalVersions: applied,
        signal: {
          'record_id': 't1',
          'updated_at': '2026-10-16T00:02:00Z',
          'deleted_at': '2026-10-16T00:02:00Z',
        },
        fetchedRow: null,
      ),
      isTrue,
    );
    expect(taskRows, isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mindtrack_danisan_app/data/record_sync.dart';
import 'package:mindtrack_danisan_app/models/app_data.dart';
import 'package:mindtrack_danisan_app/models/finance.dart';

void main() {
  test('finance goal month is a stable record id and round-trips remotely', () {
    final local = AppData(
      financeGoals: [
        FinanceGoal(month: '2026-10', target: 1250, notes: 'Aylık hedef'),
      ],
    );

    final records = recordsFromAppData(local);
    expect(records, hasLength(1));
    expect(records.single.recordType, 'finance_goal');
    expect(records.single.recordId, '2026-10');

    final restored = appDataFromRecords([
      {
        'record_type': records.single.recordType,
        'record_id': records.single.recordId,
        'record_version': 1,
        'data': records.single.data,
        'deleted_at': null,
      },
    ]);
    expect(restored.financeGoals.single.month, '2026-10');
    expect(restored.financeGoals.single.target, 1250);
    expect(restored.financeGoals.single.notes, 'Aylık hedef');
  });

  test('deleting a finance goal emits a stable month-keyed tombstone', () {
    final previous = AppData(
      financeGoals: [FinanceGoal(month: '2026-10', target: 1250)],
    );

    final changes = diffAppData(previous, AppData.empty());
    expect(changes.upserts, isEmpty);
    expect(changes.deletes, hasLength(1));
    expect(changes.deletes.single.recordType, 'finance_goal');
    expect(changes.deletes.single.recordId, '2026-10');
    expect(changes.deletes.single.deletedAt, isNotNull);

    final withoutDeletedGoal = removeRecordsByKey(
      previous,
      {recordKeyHash('finance_goal:2026-10')},
    );
    expect(withoutDeletedGoal.financeGoals, isEmpty);
  });
}

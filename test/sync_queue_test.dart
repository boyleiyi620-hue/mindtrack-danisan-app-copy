import 'package:flutter_test/flutter_test.dart';
import 'package:mindtrack_danisan_app/data/account_store.dart';
import 'package:mindtrack_danisan_app/data/binary_blobs.dart';
import 'package:mindtrack_danisan_app/data/crypto_utils.dart';
import 'package:mindtrack_danisan_app/data/data_store.dart';
import 'package:mindtrack_danisan_app/data/sync_status.dart';
import 'package:mindtrack_danisan_app/models/app_data.dart';
import 'package:mindtrack_danisan_app/models/client.dart';
import 'package:mindtrack_danisan_app/models/user_account.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserAccount _account(String id, String email) {
  final salt = randomHex();
  return UserAccount(
    id: id,
    name: 'Test Psikolog',
    email: email,
    salt: salt,
    pwdHash: hashPassword('123456', salt),
    createdAt: 1000,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('yerel kayıt, sunucuya gönderilene kadar "kirli" sayılır', () async {
    final accounts = await AccountStore.init();
    accounts.setSession(_account('queue-unsynced', 'unsynced@example.com'));
    final data = DataStore(accounts);

    expect(data.hasUnsyncedChanges, isFalse);

    data.data.clients.add(Client(id: 'c1', name: 'Danışan'));
    data.save();
    await data.flushLocalWrites();

    // Sunucu bağlantısı olmadığı için veri diske yazılır ama uzağa gidemez.
    expect(data.hasUnsyncedChanges, isTrue);
  });

  test('oturum yokken durum "bekliyor" olarak görünür', () async {
    final accounts = await AccountStore.init();
    accounts.setSession(_account('queue-pending', 'pending@example.com'));
    final data = DataStore(accounts);

    data.data.clients.add(Client(id: 'c1', name: 'Danışan'));
    data.save();
    await data.flushLocalWrites();

    expect(data.syncStatus.phase, SyncPhase.pending);
    expect(data.syncStatus.hasPendingWork, isTrue);
  });

  test('kirli işareti uygulama yeniden açıldığında korunur', () async {
    final accounts = await AccountStore.init();
    accounts.setSession(_account('queue-reopen', 'reopen@example.com'));
    final first = DataStore(accounts);

    first.data.clients.add(Client(id: 'c1', name: 'Danışan'));
    first.save();
    await first.flushLocalWrites();
    expect(first.hasUnsyncedChanges, isTrue);

    // Aynı hesapla yeni bir depo kurulur: uygulama yeniden açılmış gibi.
    final reopened = DataStore(accounts);
    expect(reopened.hasUnsyncedChanges, isTrue);
    expect(reopened.data.clients.single.name, 'Danışan');
  });

  test('başka kullanıcının kirli işareti diğerini etkilemez', () async {
    final accounts = await AccountStore.init();
    accounts.setSession(_account('queue-user-a', 'a@example.com'));
    final first = DataStore(accounts);
    first.data.clients.add(Client(id: 'c1', name: 'A'));
    first.save();
    await first.flushLocalWrites();
    expect(first.hasUnsyncedChanges, isTrue);

    accounts.setSession(_account('queue-user-b', 'b@example.com'));
    final second = DataStore(accounts);
    expect(second.hasUnsyncedChanges, isFalse);

    accounts.setSession(_account('queue-user-a', 'a@example.com'));
    expect(DataStore(accounts).hasUnsyncedChanges, isTrue);
  });

  test(
    'hızlı ardışık kayıtlar yeniden açılışta en yeni anlık görüntüyü korur',
    () async {
      final accounts = await AccountStore.init();
      accounts.setSession(_account('queue-latest', 'latest@example.com'));
      final data = DataStore(accounts);

      data.data.clients.add(Client(id: 'c1', name: 'İlk kayıt'));
      data.save();
      data.data.clients.single.name = 'En yeni kayıt';
      data.save();
      await data.flushLocalWrites();

      final reopened = DataStore(accounts);
      expect(reopened.data.clients.single.name, 'En yeni kayıt');
      expect(reopened.hasUnsyncedChanges, isTrue);
    },
  );

  test('yeniden deneme sunucu yokken çevrimdışı gösterir', () async {
    final accounts = await AccountStore.init();
    accounts.setSession(_account('queue-retry', 'retry@example.com'));
    final data = DataStore(accounts);

    await data.retrySyncNow();
    await Future<void>.delayed(Duration.zero);

    expect(data.syncStatus.phase, SyncPhase.offline);
    expect(data.syncStatus.hasPendingWork, isFalse);
    // Veri hâlâ cihazda; kullanıcı çıkış yapmadığı için kaybolmamalı.
    expect(data.hasUnsyncedChanges, isFalse);
  });

  test('oturum kapatılınca veri silinmez, işaret yerinde kalır', () async {
    final accounts = await AccountStore.init();
    accounts.setSession(_account('queue-logout', 'logout@example.com'));
    final data = DataStore(accounts);
    data.data.clients.add(Client(id: 'c1', name: 'Danışan'));
    data.save();
    await data.flushLocalWrites();

    accounts.clearSession();

    accounts.setSession(_account('queue-logout', 'logout@example.com'));
    final reopened = DataStore(accounts);
    expect(reopened.hasUnsyncedChanges, isTrue);
    expect(reopened.data.clients.single.name, 'Danışan');
  });

  test('yüklenmiş belge gövdesi uzak payloaddan çıkarılır', () {
    final payload = <String, dynamic>{
      'pdfFiles': [
        {'id': 'pdf-1', 'storagePath': 'user/pdf-1', 'dataUrl': 'large-body'},
        {'id': 'pdf-2', 'storagePath': '', 'dataUrl': 'pending-body'},
      ],
      'documents': [
        {'id': 'doc-1', 'storagePath': 'user/doc-1', 'dataUrl': 'large-body'},
      ],
    };

    dropUploadedBodies(payload);

    expect(payload['pdfFiles'][0]['dataUrl'], isEmpty);
    expect(payload['pdfFiles'][1]['dataUrl'], 'pending-body');
    expect(payload['documents'][0]['dataUrl'], isEmpty);
  });

  test('yedek geri yüklemeden önce mevcut snapshot kurtarılır', () async {
    final accounts = await AccountStore.init();
    final user = _account('restore-protection', 'restore@example.com');
    accounts.setSession(user);
    final data = DataStore(accounts);
    data.data.clients.add(Client(id: 'before', name: 'Geri alınmadan önce'));
    data.save();
    await data.flushLocalWrites();

    await data.restoreFromBackup(
      AppData(clients: [Client(id: 'after', name: 'Yedekten gelen')]),
    );
    await data.flushLocalWrites();

    expect(data.data.clients.single.name, 'Yedekten gelen');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where(
        (key) => key.startsWith('${accounts.dataKey(user)}_before_restore_'),
      ),
      isNotEmpty,
    );
  });

  test('storage yolu olmayan belgeler yükleme kuyruğuna alınır', () {
    final payload = <String, dynamic>{
      'pdfFiles': [
        {'id': 'pdf-1', 'storagePath': '', 'dataUrl': 'data:application/pdf;base64,SGk='},
        {'id': 'pdf-2', 'storagePath': 'user/pdf-2', 'dataUrl': 'data:application/pdf;base64,SGk='},
      ],
      'documents': <Map<String, dynamic>>[],
    };

    final pending = extractInlineBinaries(payload);

    expect(pending, hasLength(1));
    expect(pending.single.id, 'pdf-1');
    expect(pending.single.bytes, [72, 105]);
  });
}

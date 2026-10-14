import 'package:flutter_test/flutter_test.dart';
import 'package:mindtrack_danisan_app/data/account_store.dart';
import 'package:mindtrack_danisan_app/models/user_account.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('PIN hataları kalıcı kademeli bekleme uygular', () async {
    final store = await AccountStore.init();
    final account = UserAccount(
      id: 'pin-throttle-test-user',
      name: 'Test',
      email: 'test@example.invalid',
      salt: 'legacy-salt',
      pwdHash: 'unused',
      createdAt: 0,
      pinHash: 'legacy-hash',
    );

    for (var attempt = 0; attempt < 4; attempt += 1) {
      expect(await store.recordPinFailure(account), Duration.zero);
    }
    expect(await store.recordPinFailure(account), const Duration(seconds: 30));
    expect(store.pinLockRemaining(account), greaterThan(Duration.zero));

    final afterReload = await AccountStore.init();
    expect(afterReload.pinLockRemaining(account), greaterThan(Duration.zero));
    expect(
      await afterReload.recordPinFailure(account),
      const Duration(seconds: 60),
    );

    await afterReload.resetPinFailures(account);
    expect(afterReload.pinLockRemaining(account), Duration.zero);
  });
}

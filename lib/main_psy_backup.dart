import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_scope.dart';
import 'data/account_store.dart';
import 'data/data_store.dart';
import 'data/mindtrack_backend.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/auth/pin_screen.dart';
import 'screens/shell/main_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var backendReady = false;
  try {
    await MindTrackBackend.init();
    backendReady = true;
  } catch (_) {
    // Supabase başlatılamazsa Web/Android uygulaması yine açılabilmelidir.
    // Senkronizasyon, arka uç hazır olmadığında giriş ekranında devre dışı kalır.
  }
  final store = await AccountStore.init();
  final data = DataStore(store);
  runApp(MindTrackApp(
    store: store,
    data: data,
    backendSignedIn: backendReady && MindTrackBackend.instance.isSignedIn,
  ));
}

class MindTrackApp extends StatelessWidget {
  const MindTrackApp({
    super.key,
    required this.store,
    required this.data,
    this.backendSignedIn = true,
  });

  final AccountStore store;
  final DataStore data;
  final bool backendSignedIn;

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (store.current != null && backendSignedIn) {
      home = store.isLocked
          ? PinScreen(store: store, onUnlock: () {})
          : MainShell(store: store, data: data);
    } else {
      home = AuthScreen(store: store, data: data);
    }
    return AppScope(
      notifier: data,
      child: MaterialApp(
        title: 'MindTrack — Psikolog Değerlendirme Sistemi',
        debugShowCheckedModeBanner: false,
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildAppTheme(),
        routes: {
          '/auth': (_) => AuthScreen(store: store, data: data),
        },
        home: home,
      ),
    );
  }
}

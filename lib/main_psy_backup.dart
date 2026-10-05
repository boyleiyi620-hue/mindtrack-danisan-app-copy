import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_scope.dart';
import 'data/account_store.dart';
import 'data/data_store.dart';
import 'data/mindtrack_backend.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/auth/pin_screen.dart';
import 'screens/shell/main_shell.dart' deferred as main_shell;
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backendInitialization = () async {
    try {
      await MindTrackBackend.init();
      return true;
    } catch (_) {
      // Supabase kapalı olsa bile yerel giriş ekranı açılabilmelidir.
      return false;
    }
  }();
  // Backend ve yerel hesap/veri deposu birbirinden bağımsız hazırlanabilir.
  final storeInitialization = AccountStore.init();
  final store = await storeInitialization;
  final backendReady = await backendInitialization;
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
          : _DeferredMainShell(store: store, data: data);
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

/// Oturum açılana kadar kimlik doğrulanmış tüm sekmeleri indirmeyi erteler.
class _DeferredMainShell extends StatefulWidget {
  const _DeferredMainShell({required this.store, required this.data});

  final AccountStore store;
  final DataStore data;

  @override
  State<_DeferredMainShell> createState() => _DeferredMainShellState();
}

class _DeferredMainShellState extends State<_DeferredMainShell> {
  late Future<void> _loading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _loading = main_shell.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ana panel yüklenemedi. Bağlantınızı kontrol edin.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(_load),
                    child: const Text('Yeniden dene'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return main_shell.MainShell(store: widget.store, data: widget.data);
      },
    );
  }
}

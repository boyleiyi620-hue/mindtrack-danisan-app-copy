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
import 'widgets/fatal_error_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => FatalErrorView(details: details);
  runApp(const _PsychologistBootstrapApp());
}

class _PsychologistBootstrapApp extends StatefulWidget {
  const _PsychologistBootstrapApp();

  @override
  State<_PsychologistBootstrapApp> createState() =>
      _PsychologistBootstrapAppState();
}

class _PsychologistBootstrapAppState
    extends State<_PsychologistBootstrapApp> {
  late Future<_PsychologistBootstrapResult> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  void _retry() {
    setState(() => _initialization = _initialize());
  }

  Future<_PsychologistBootstrapResult> _initialize() async {
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
  // Büyük klinik JSON'unu ilk Flutter karesinden önce çözümleme; panel
  // iskeleti göründükten sonra _DeferredMainShell tarafından yüklenir.
  final data = DataStore(store, autoLoad: false);
    return _PsychologistBootstrapResult(
      store: store,
      data: data,
      backendSignedIn: backendReady && MindTrackBackend.instance.isSignedIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PsychologistBootstrapResult>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupState(
            error: true,
            onRetry: _retry,
          );
        }
        if (!snapshot.hasData) {
          return const _StartupState();
        }
        final result = snapshot.data!;
        return MindTrackApp(
          store: result.store,
          data: result.data,
          backendSignedIn: result.backendSignedIn,
        );
      },
    );
  }
}

class _PsychologistBootstrapResult {
  const _PsychologistBootstrapResult({
    required this.store,
    required this.data,
    required this.backendSignedIn,
  });

  final AccountStore store;
  final DataStore data;
  final bool backendSignedIn;
}

class _StartupState extends StatelessWidget {
  const _StartupState({this.error = false, this.onRetry});

  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFF5FAFA),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!error) ...[
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                error
                    ? 'Uygulama başlatılamadı.'
                    : 'MindTrack hazırlanıyor…',
                style: const TextStyle(
                  color: Color(0xFF194643),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (error) ...[
                const SizedBox(height: 8),
                const Text(
                  'Yerel depolama veya bağlantı hazırlanamadı.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF52716D), fontSize: 13),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Yeniden dene'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.data.load();
    });
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

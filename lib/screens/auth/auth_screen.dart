import 'package:flutter/material.dart';

import '../../data/account_store.dart';
import '../../data/crypto_utils.dart';
import '../../data/data_store.dart';
import '../../data/mindtrack_backend.dart';
import '../../models/user_account.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_box.dart';
import '../shell/main_shell.dart';

enum AuthMode { login, register }

/// Giriş / Kayıt ekranı — web sürümündeki akışla birebir uyumlu.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.store, required this.data});

  final AccountStore store;
  final DataStore data;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode _mode = AuthMode.login;
  bool _busy = false;
  String? _error;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _clinic = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _kvkkOk = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _clinic.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (_mode == AuthMode.login) {
        await _login();
      } else {
        await _register();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    final email = _email.text.trim().toLowerCase();
    final pass = _pass.text;
    if (!isEmailValid(email)) throw 'Geçerli bir e-posta girin.';
    if (pass.isEmpty) throw 'Şifre boş olamaz.';

    // Ortak hesap doğrulaması Supabase Auth üzerinden yapılır. Böylece Web’de
    // oluşturulan hesap, ilk Android girişinde yerel kayıt bulunmasa bile açılır.
    await _signInBackend(email, pass);
    var u = widget.store.findByEmail(email);
    if (u == null) {
      final backend = MindTrackBackend.instance;
      final salt = randomHex();
      final remoteName = backend.displayName.trim();
      u = UserAccount(
        id: backend.userId ?? salt + DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        name: remoteName.isNotEmpty ? remoteName : email.split('@').first,
        email: email,
        clinic: '',
        salt: salt,
        pwdHash: hashPassword(pass, salt),
        createdAt: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      widget.store.addUser(u);
    }
    widget.store.setSession(u);
    widget.data.load();
    await widget.data.startRemoteSync();
    if (mounted) _goHome();
  }

  Future<void> _signInBackend(String email, String pass) async {
    final backend = MindTrackBackend.instance;
    // Supabase hiçbaşlatılmadıysa (yapılandırma eksik, test ortamı)
    // uzak doğrulama yapılamaz; yerel hesapla devam edilir. `main()` de
    // arka uç hazır değilken uygulamanın açılabilmesini öngörüyor.
    if (!backend.isReady) return;

    try {
      await backend.signIn(email, pass);
    } on BackendException catch (e) {
      // Hesap uzak tarafta hiç yoksa ilk girişte sessizce oluşturulur; böylece
      // web'de açılan hesap ilk Android girişinde de tanınır.
      if (e.message.contains('Invalid login credentials')) {
        await backend.signUp(email, pass);
        return;
      }
      throw 'Oturum açılamadı: ${e.message}';
    }
  }

  Future<void> _register() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final pass = _pass.text;
    if (name.isEmpty) throw 'Adınızı ve soyadınızı girin.';
    if (!isEmailValid(email)) throw 'Geçerli bir e-posta girin.';
    if (pass.length < 6) throw 'Şifre en az 6 karakter olmalıdır.';
    if (pass != _pass2.text) throw 'Şifreler eşleşmiyor.';
    if (!_kvkkOk) {
      throw 'KVKK / Veri İşleme Aydınlatma Metni\'ni kabul etmelisiniz.';
    }
    if (widget.store.findByEmail(email) != null) {
      throw 'Bu e-posta ile zaten bir hesap var. Giriş yapın.';
    }
    final salt = randomHex();
    final u = UserAccount(
      id: salt + DateTime.now().microsecondsSinceEpoch.toRadixString(16),
      name: name,
      email: email.toLowerCase(),
      clinic: _clinic.text.trim(),
      salt: salt,
      pwdHash: hashPassword(pass, salt),
      createdAt: DateTime.now().millisecondsSinceEpoch.toDouble(),
      appMode: '', // Trigger mode selection on first login
    );
    if (MindTrackBackend.instance.isReady) {
      try {
        await MindTrackBackend.instance.signUp(
          email.toLowerCase(),
          pass,
          displayName: name,
        );
      } on BackendException catch (e) {
        if (e.message.contains('already registered')) {
          throw 'Bu e-posta zaten kayıtlı. Giriş yapmayı deneyin.';
        }
        throw 'Hesap oluşturulamadı: ${e.message}';
      }
    }
    widget.store.addUser(u);
    widget.store.setSession(u);
    widget.data.load();
    await widget.data.startRemoteSync();
    if (mounted) _goHome();
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainShell(store: widget.store, data: widget.data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                _brand(),
                const SizedBox(height: 22),
                _modeSwitch(),
                const SizedBox(height: 14),
                _card(),
                const SizedBox(height: 14),
                Text(
                  'Tüm verileriniz yalnızca bu cihazda saklanır.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted.withValues(alpha: .9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.monitor_heart_outlined,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MindTrack',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text)),
              Text('Psikolog Değerlendirme Sistemi',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.muted),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modeSwitch() {
    return SegmentedButton<AuthMode>(
      segments: const [
        ButtonSegment(
            value: AuthMode.login,
            label: Text('Giriş Yap',
                style: TextStyle( fontWeight: FontWeight.w600))),
        ButtonSegment(
            value: AuthMode.register,
            label: Text('Kayıt Ol',
                style: TextStyle( fontWeight: FontWeight.w600))),
      ],
      selected: {_mode},
      onSelectionChanged: (s) => setState(() {
        _mode = s.first;
        _error = null;
      }),
    );
  }

  Widget _card() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: .08),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_mode == AuthMode.register) ...[
            _field('Adınız ve soyadınız', _name,
                hint: 'Örn: Dr. Ayşe Yılmaz', icon: Icons.person_outline),
            const SizedBox(height: 12),
            _field('E-posta', _email,
                hint: 'ornek@email.com',
                icon: Icons.mail_outline,
                keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _field('Klinik Adı (isteğe bağlı)', _clinic,
                hint: 'Özel Psikoloji Kliniği', icon: Icons.home_work_outlined),
            const SizedBox(height: 12),
          ] else ...[
            _field('E-posta', _email,
                hint: 'ornek@email.com',
                icon: Icons.mail_outline,
                keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
          ],
          _field('Şifre', _pass,
              hint: 'En az 6 karakter',
              icon: Icons.lock_outline,
              obscure: true,
              keyboard: TextInputType.visiblePassword),
          if (_mode == AuthMode.register) ...[
            const SizedBox(height: 12),
            _field('Şifre Tekrar', _pass2,
                hint: 'Şifrenizi tekrarlayın',
                icon: Icons.lock_outline,
                obscure: true,
                keyboard: TextInputType.visiblePassword),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _kvkkOk,
                  onChanged: (v) => setState(() => _kvkkOk = v ?? false),
                  visualDensity: VisualDensity.compact,
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'KVKK / Veri İşleme Aydınlatma Metni\'ni okudum ve kabul ediyorum. Verilerim yalnızca bu cihazda saklanır.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.text2),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          ErrorBox(message: _error),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white))
                : Text(_mode == AuthMode.login ? 'Giriş Yap' : 'Kayıt Ol',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {String? hint, IconData? icon, bool obscure = false, TextInputType? keyboard}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      onSubmitted: (_) => _submit(),
      style: const TextStyle(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, size: 19, color: AppColors.muted),
      ),
    );
  }
}

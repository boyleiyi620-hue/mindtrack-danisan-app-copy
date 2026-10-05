import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/crypto_utils.dart';
import '../../data/data_store.dart';
import '../../models/app_data.dart';
import '../../models/user_account.dart';
import '../../theme/app_theme.dart';
import '../../utils/formats.dart';
import '../auth/pin_setup_dialog.dart';
import '../settings/data_io.dart';

/// Ayarlar ve Veri — profil, şifre, PIN kilidi, raporlama, dışa aktarım, KVKK.
class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.data,
    this.onProfileChanged,
    this.onLockRequest,
    this.onNavigate,
    this.onLogout,
  });

  final DataStore data;
  final VoidCallback? onProfileChanged;
  final VoidCallback? onLockRequest;
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onLogout;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _name;
  late final TextEditingController _clinic;
  late final TextEditingController _email;
  final _oldPw = TextEditingController();
  final _newPw = TextEditingController();
  final _newPw2 = TextEditingController();
  String? _profileError;
  String? _pwError;

  UserAccount get _u => widget.data.accounts.current!;
  AppData get _d => widget.data.data;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _u.name);
    _clinic = TextEditingController(text: _u.clinic);
    _email = TextEditingController(text: _u.email);
  }

  @override
  void dispose() {
    _name.dispose();
    _clinic.dispose();
    _email.dispose();
    _oldPw.dispose();
    _newPw.dispose();
    _newPw2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ayarlar ve Veri',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Hesap, dışa aktarım, raporlama ve gizlilik yönetimi',
                style: TextStyle(fontSize: 13.5, color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, bc) {
                  final wide = bc.maxWidth >= 900;
                  final left = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _profileCard(),
                      const SizedBox(height: 16),
                      _modeSettingsCard(),
                      const SizedBox(height: 16),
                      _passwordCard(),
                      const SizedBox(height: 16),
                      _pinCard(),
                    ],
                  );
                  final right = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _reportCard(),
                      const SizedBox(height: 16),
                      _exportCard(),
                      const SizedBox(height: 16),
                      _sampleDataCard(),
                      const SizedBox(height: 16),
                      _dataCard(),
                      const SizedBox(height: 16),
                      _aboutCard(),
                    ],
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: left),
                        const SizedBox(width: 16),
                        Expanded(child: right),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [left, const SizedBox(height: 16), right],
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(IconData icon, String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ---------------- Oturum Modu ----------------
  Widget _modeSettingsCard() {
    return Column(
      children: [
        _card(
          Icons.dashboard_customize_outlined,
          'Oturum Modu',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Uygulama özelliklerini ve görünümünü ihtiyacınıza göre özelleştirin.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              _modeRadioTile(
                'standard',
                'Standart Oturum',
                'Temel psikolog araçları.',
                Icons.person_outline,
              ),
              _modeRadioTile(
                'commercial',
                'Ticari Oturum',
                'Standart + Muhasebe ve Ödemeler.',
                Icons.account_balance_wallet_outlined,
              ),
            ],
          ),
        ),
        if (_u.appMode == 'commercial') ...[
          const SizedBox(height: 16),
          _card(
            Icons.account_balance_wallet_outlined,
            'Finansal Ayarlar',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Varsayılan Seans Ücreti',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: _u.defaultSessionFee.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixText: '₺ ',
                    hintText: 'Örn: 500',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final fee = double.tryParse(v) ?? 0.0;
                    _u.defaultSessionFee = fee;
                    widget.data.accounts.updateUser(_u);
                  },
                ),
                const SizedBox(height: 4),
                const Text(
                  'Yeni danışan eklendiğinde bu ücret otomatik önerilir.',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _modeRadioTile(String mode, String title, String desc, IconData icon) {
    final active = _u.appMode == mode;
    return InkWell(
      onTap: () {
        setState(() => _u.appMode = mode);
        widget.data.accounts.updateUser(_u);
        widget.onProfileChanged?.call(); // Refresh shell
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primarySoft.withValues(alpha: .5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? AppColors.primaryDark : AppColors.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              const Icon(
                Icons.check_circle,
                size: 18,
                color: AppColors.primaryDark,
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- Profil ----------------
  Widget _profileCard() {
    return _card(
      Icons.person_outline,
      'Profil',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Adınız ve soyadınız',
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _clinic,
            decoration: const InputDecoration(
              labelText: 'Klinik Adı',
              hintText: 'Özel Psikoloji Kliniği',
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'E-posta (giriş için)',
              hintText: 'ornek@klinik.com',
              isDense: true,
              errorText: _profileError,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('settings-save-profile'),
              onPressed: _saveProfile,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Profili Kaydet', style: TextStyle()),
            ),
          ),
        ],
      ),
    );
  }

  void _saveProfile() {
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _profileError = 'Ad boş olamaz.');
      return;
    }
    final email = _email.text.trim();
    if (!isEmailValid(email)) {
      setState(() => _profileError = 'Geçerli bir e-posta girin.');
      return;
    }
    final existing = widget.data.accounts.findByEmail(email);
    if (existing != null && existing.id != _u.id) {
      setState(() => _profileError = 'Bu e-posta ile zaten bir hesap var.');
      return;
    }
    _u.name = name;
    _u.clinic = _clinic.text.trim();
    _u.email = email.toLowerCase();
    widget.data.accounts.updateUser(_u);
    widget.onProfileChanged?.call();
    setState(() => _profileError = null);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Profil güncellendi.', style: TextStyle()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------- Şifre ----------------
  Widget _passwordCard() {
    return _card(
      Icons.lock_outline,
      'Şifre Değiştir',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _oldPw,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mevcut şifre',
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPw,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Yeni şifre',
              hintText: 'En az 6 karakter',
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPw2,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Tekrar',
              isDense: true,
              errorText: _pwError,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('settings-change-password'),
              onPressed: _changePassword,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Şifreyi Güncelle', style: TextStyle()),
            ),
          ),
        ],
      ),
    );
  }

  void _changePassword() {
    final messenger = ScaffoldMessenger.of(context);
    final oldP = _oldPw.text;
    final n1 = _newPw.text;
    final n2 = _newPw2.text;
    if (oldP.isEmpty) {
      setState(() => _pwError = 'Mevcut şifreyi girin.');
      return;
    }
    if (hashPassword(oldP, _u.salt) != _u.pwdHash) {
      setState(() => _pwError = 'Mevcut şifre hatalı.');
      return;
    }
    if (n1.length < 6) {
      setState(() => _pwError = 'Yeni şifre en az 6 karakter olmalıdır.');
      return;
    }
    if (n1 != n2) {
      setState(() => _pwError = 'Yeni şifreler eşleşmiyor.');
      return;
    }
    _u.salt = randomHex();
    _u.pwdHash = hashPassword(n1, _u.salt);
    widget.data.accounts.updateUser(_u);
    _oldPw.clear();
    _newPw.clear();
    _newPw2.clear();
    setState(() => _pwError = null);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Şifreniz güncellendi.', style: TextStyle()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------- PIN kilidi ----------------
  Widget _pinCard() {
    final hasPin = _u.hasPin;
    return _card(
      Icons.shield_outlined,
      'Uygulama Kilidi (PIN)',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                hasPin ? Icons.check_circle : Icons.info_outline,
                size: 17,
                color: hasPin ? AppColors.success : AppColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasPin
                      ? 'PIN aktif — ${_u.lockTimeout} dk otomatik kilit'
                      : 'PIN kilidi şu an kapalı.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: hasPin ? AppColors.success : AppColors.text2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Belirlenen süre işlem yapılmazsa veya uygulama arka plana alınırsa otomatik kilitlenir. PIN yalnızca bu cihazda saklanır.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('settings-open-pin'),
                onPressed: _openPinSetup,
                icon: const Icon(Icons.lock_outline, size: 16),
                label: Text(
                  hasPin ? 'PIN Ayarları' : 'PIN Kur',
                  style: const TextStyle(),
                ),
              ),
              if (hasPin)
                OutlinedButton.icon(
                  onPressed: widget.onLockRequest,
                  icon: const Icon(Icons.lock, size: 16),
                  label: const Text('Şimdi Kilitle', style: TextStyle()),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPinSetup() async {
    await PinSetupDialog.show(
      context,
      account: _u,
      onChanged: () {
        widget.data.accounts.updateUser(_u);
        widget.onProfileChanged?.call();
      },
      onLockRequest: widget.onLockRequest,
    );
    if (mounted) setState(() {});
  }

  // ---------------- Raporlama ----------------
  Widget _reportCard() {
    return _card(
      Icons.bar_chart_outlined,
      'Detaylı Yönetici Raporları',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Seçtiğiniz hafta veya ay için randevuları, danışanları, gönderilen formları, seans notu özetlerini ve değerlendirmeleri uygulama temasında hazırlayın.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.text2,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('settings-open-reports'),
              onPressed: () => widget.onNavigate?.call('reports'),
              icon: const Icon(Icons.insights_outlined, size: 16),
              label: const Text('Raporlara Git', style: TextStyle()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDemoData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Örnek veri ekle'),
        content: const Text(
          'Raporları ve uygulama özelliklerini denemeniz için örnek danışan, randevu ve kayıtlar eklenecek. Mevcut verileriniz silinmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Örnekleri Ekle'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.data.loadDemoData();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Örnek veriler eklendi.')),
    );
  }

  Widget _sampleDataCard() => _card(
    Icons.auto_awesome_outlined,
    'Örnek Veriler',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Uygulamayı ve raporları denemek için örnek danışan ve kayıtlar ekleyin. Mevcut verileriniz korunur.',
          style: TextStyle(fontSize: 12.5, color: AppColors.text2, height: 1.5),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('settings-load-demo-data'),
          onPressed: _loadDemoData,
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Örnek Veri Ekle', style: TextStyle()),
        ),
      ],
    ),
  );

  // ---------------- Dışa Aktarım ----------------
  Widget _exportCard() {
    return _card(
      Icons.download_outlined,
      'Dışa Aktarım (CSV)',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _csvButton(
                'Danışanlar',
                Icons.people_outline,
                'clients',
                const Key('export-clients-csv'),
              ),
              _csvButton(
                'Randevular',
                Icons.calendar_month_outlined,
                'appointments',
                const Key('export-appts-csv'),
              ),
              _csvButton(
                'Seans Notları',
                Icons.note_alt_outlined,
                'notes',
                const Key('export-notes-csv'),
              ),
              _csvButton(
                'Tedavi Planı',
                Icons.flag_outlined,
                'plans',
                const Key('export-plans-csv'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'CSV dosyalarını Excel veya benzeri programlarla açabilirsiniz.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tam yedekleme (JSON)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sağlık verisi içerir; dosyayı güvenli yerde saklayın.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('settings-export-backup'),
                onPressed: _exportBackup,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Yedeği İndir'),
              ),
              OutlinedButton.icon(
                key: const Key('settings-import-backup'),
                onPressed: _importBackup,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('Yedek Yükle'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    final payload = jsonEncode({
      'format': 'mindtrack-backup',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'data': _d.toJson(),
    });
    final ok = await saveTextFile(
      'mindtrack-yedek-${todayIso()}.json',
      payload,
      'application/json;charset=utf-8',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Tam yedek indirildi.' : 'Yedek oluşturulamadı.')),
    );
  }

  Future<void> _importBackup() async {
    final raw = await pickTextFile();
    if (raw == null || !mounted) return;
    AppData restored;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('JSON nesnesi bekleniyor.');
      }
      final map = Map<String, dynamic>.from(decoded);
      late final Map<String, dynamic> source;
      if (map['format'] == 'mindtrack-backup') {
        if (map['version'] != 1 || map['data'] is! Map) {
          throw const FormatException('Desteklenmeyen yedek sürümü.');
        }
        source = Map<String, dynamic>.from(map['data'] as Map);
      } else {
        const knownCollections = [
          'clients', 'appointments', 'notes', 'forms', 'assessments',
          'plans', 'tasks', 'documents', 'pdfCats', 'pdfFiles',
        ];
        if (!knownCollections.any(map.containsKey)) {
          throw const FormatException('MindTrack kayıt alanı bulunamadı.');
        }
        source = map;
      }
      restored = AppData.fromJson(source);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu dosya geçerli bir MindTrack yedeği değil.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yedeği geri yükle?'),
        content: Text(
          '${restored.clients.length} danışan, ${restored.notes.length} seans notu ve ${restored.appointments.length} randevu yüklenecek. Mevcut veriler bu cihazda değiştirilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Geri Yükle'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.data.data = restored;
    widget.data.save();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Yedek geri yüklendi ve senkronizasyona alındı.')),
    );
  }

  Widget _csvButton(String label, IconData icon, String kind, Key key) {
    return OutlinedButton.icon(
      key: key,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: () => _exportCsv(kind),
      icon: Icon(icon, size: 15, color: AppColors.primaryDark),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  Future<void> _exportCsv(String kind) async {
    final messenger = ScaffoldMessenger.of(context);
    final (rows, filename) = switch (kind) {
      'clients' => (_clientRows(), 'danisanlar-${todayIso()}.csv'),
      'appointments' => (_appointmentRows(), 'randevular-${todayIso()}.csv'),
      'notes' => (_noteRows(), 'seans-notlari-${todayIso()}.csv'),
      'plans' => (_planRows(), 'tedavi-plani-${todayIso()}.csv'),
      _ => (<Map<String, Object?>>[], 'dosya-${todayIso()}.csv'),
    };
    if (rows.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Dışa aktarılacak kayıt bulunamadı.',
            style: TextStyle(),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    final ok = await saveTextFile(
      filename,
      _rowsToCsv(rows),
      'text/csv;charset=utf-8',
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'CSV dosyası indirildi.' : 'Dosya oluşturulamadı.',
          style: const TextStyle(),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? null : AppColors.danger,
      ),
    );
  }

  List<Map<String, Object?>> _clientRows() => [
    for (final c in _d.clients)
      {
        'Ad': c.name,
        'E-posta': c.email,
        'Telefon': c.phone,
        'Doğum Tarihi': c.birthDate,
        'Cinsiyet': c.gender,
        'Etiketler': c.tags.join('; '),
        'Notlar': c.notes,
        'Durum': clientStatusLabel(c.status),
      },
  ];

  List<Map<String, Object?>> _appointmentRows() => [
    for (final a in _d.appointments)
      {
        'Tarih': fmtIsoDate(a.date),
        'Saat': a.time,
        'Danışan': _d.clientById(a.clientId)?.name ?? '',
        'Tür': apptTypeLabel(a.type),
        'Durum': apptStatusLabel(a.status),
        'Süre': '${a.durationMin} dk',
        'Not': a.notes,
      },
  ];

  List<Map<String, Object?>> _noteRows() => [
    for (final n in _d.notes)
      {
        'Tarih': fmtDateTime(n.date),
        'Danışan': _d.clientById(n.clientId)?.name ?? '',
        'Başlık': n.title,
        'Ruh Hali': n.mood,
        'Subjektif': n.subjective,
        'Objektif': n.objective,
        'Değerlendirme': n.assessment,
        'Plan': n.plan,
      },
  ];

  List<Map<String, Object?>> _planRows() => [
    for (final p in _d.plans)
      for (final g in p.goals)
        {
          'Danışan': _d.clientById(p.clientId)?.name ?? '',
          'Plan': p.title,
          'Hedef': g.text,
          'Vade': goalCategoryLabel(g.category),
          'Durum': goalStatusLabel(g.status),
          'Hedef Tarihi': g.targetDate ?? '',
        },
  ];

  String _csvCell(Object? v) {
    var s = v?.toString() ?? '';
    s = s.replaceAll('"', '""').replaceAll('\r', ' ').replaceAll('\n', ' ');
    return '"$s"';
  }

  String _rowsToCsv(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return '';
    final keys = rows.first.keys.toList();
    final buf = StringBuffer('\uFEFF');
    buf.writeln(keys.map(_csvCell).join(','));
    for (final r in rows) {
      buf.writeln(keys.map((k) => _csvCell(r[k])).join(','));
    }
    return buf.toString();
  }

  // ---------------- Veri yönetimi ----------------
  Widget _dataCard() {
    return _card(
      Icons.delete_sweep_outlined,
      'Veri Yönetimi',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tüm formlar, danışanlar, değerlendirmeler, randevular, seans notları ve tedavi planları kalıcı olarak silinir. Bu işlem geri alınamaz.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.text2,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('settings-reset-data'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
              onPressed: _resetData,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Tüm Verileri Sıfırla', style: TextStyle()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resetData() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm verileri sıfırla', style: TextStyle()),
        content: const Text(
          'Tüm formlar, danışanlar, değerlendirmeler, randevular, seans notları ve tedavi planları kalıcı olarak silinecek. Bu işlem geri alınamaz.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç', style: TextStyle()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Evet, Sıfırla', style: TextStyle()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.data.resetAll();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Tüm veriler sıfırlandı.', style: TextStyle()),
        behavior: SnackBarBehavior.floating,
      ),
    );
    widget.onNavigate?.call('overview');
  }

  // ---------------- Hakkında ----------------
  Widget _aboutCard() {
    return _card(
      Icons.info_outline,
      'Uygulama Hakkında',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.monitor_heart_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MindTrack',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const Text(
                    'Psikolog Değerlendirme Sistemi',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  Text(
                    'Sürüm ${'1.0'} — Flutter',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Bu uygulama bir klinik takip aracıdır; tıbbi tanı koymaz. Klinik verileriniz bağlı sunucu hesabında saklanır ve cihazlar arasında senkronize edilir. Bu nedenle yalnızca yetkili kişilerle paylaşım yapın.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.text2,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('settings-open-kvkk'),
                onPressed: _openKvkk,
                icon: const Icon(Icons.shield_outlined, size: 16),
                label: const Text(
                  'KVKK / Aydınlatma Metni',
                  style: TextStyle(),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('settings-logout'),
                onPressed: widget.onLogout,
                icon: const Icon(
                  Icons.logout,
                  size: 16,
                  color: AppColors.danger,
                ),
                label: const Text(
                  'Oturumu Kapat',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openKvkk() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'KVKK / Veri İşleme Aydınlatma Metni',
          style: TextStyle(),
        ),
        content: const SingleChildScrollView(
          child: Text(
            '1. Veri Sorumlusu: Veri sorumlusu uygulamayı kullanan psikolog/klinik işletmesidir.\n\n'
            '2. İşlenen Veriler: Danışan ad-soyad, iletişim bilgileri, değerlendirme cevapları, seans notları ve tedavi planı bilgileri.\n\n'
            '3. İşleme Amacı: Klinik süreç yönetimi, değerlendirme takibi ve tedavi planlaması.\n\n'
            '4. Saklama: Klinik kayıtlar bağlı sunucu hesabında ve çalışma cihazındaki uygulama önbelleğinde saklanabilir. Yetkisiz erişimi önlemek için hesap bilgilerinizi paylaşmayın.\n\n'
            '5. Güvenlik: Şifreler tek yönlü özetleme (SHA-256) ile saklanır. Cihaz düzeyinde ek koruma için işletim sisteminizin disk şifrelemesini etkinleştirmeniz önerilir.\n\n'
            '6. Haklarınız: KVKK kapsamında verilere erişim, düzeltme ve silme haklarınızı bu uygulamanın Ayarlar bölümünden kullanabilirsiniz.\n\n'
            'Uyarı: Bu uygulama tıbbi tanı veya tedavi aracı değildir; bir sağlık profesyonelinin mesleki kararlarını destekleyen bir kayıt aracıdır.',
            style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Kapat', style: TextStyle()),
          ),
        ],
      ),
    );
  }
}

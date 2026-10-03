import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import 'data/diagnosis_codes.dart';
import 'data/mindtrack_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await MindTrackBackend.init();
  } catch (error) {
    debugPrint('Supabase init error: $error');
  }
  runApp(const MindTrackClientApp());
}

class MindTrackClientApp extends StatelessWidget {
  const MindTrackClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindTrack Danışan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          primary: Colors.teal,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: MindTrackBackend.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data?.session == null) return const LoginScreen();
        return const ClientShell();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _isReg = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) return;
    if (_isReg && _name.text.trim().isEmpty) {
      _showError('Ad soyad alanı gereklidir.');
      return;
    }
    setState(() => _loading = true);
    try {
      final backend = MindTrackBackend.instance;
      final email = _email.text.trim();
      if (_isReg) {
        await backend.signUp(email, _pass.text, displayName: _name.text.trim());
        if (!backend.isSignedIn) {
          _showError(
            'Kayıt tamamlandı. Gmail adresinize gelen doğrulama bağlantısını onaylayıp giriş yapın.',
          );
          return;
        }
        await backend.upsertPatientProfile(
          displayName: _name.text.trim(),
          email: email,
        );
      } else {
        await backend.signIn(email, _pass.text);
        final name = backend.displayName;
        await backend.upsertPatientProfile(
          displayName: name,
          email: backend.userEmail ?? email,
        );
      }
    } on BackendException catch (e) {
      _showError('Hata: ${e.message}');
    } catch (error) {
      _showError('Hata: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _googleLogin() async {
    setState(() => _loading = true);
    try {
      await MindTrackBackend.instance.signInWithGoogle();
    } on BackendException catch (e) {
      _showError('Google girişi başlatılamadı: ${e.message}');
    } catch (e) {
      _showError('Google girişi başlatılamadı: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.favorite, size: 80, color: Colors.teal),
                const SizedBox(height: 16),
                const Text(
                  'MindTrack Danışan',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                if (_isReg) ...[
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Ad Soyad',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pass,
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const CircularProgressIndicator()
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_isReg ? 'Kayıt Ol' : 'Giriş Yap'),
                    ),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _googleLogin,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Google ile devam et'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isReg = !_isReg),
                  child: Text(_isReg ? 'Giriş Yap' : 'Kayıt Ol'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int _idx = 0;

  void selectTab(int index) => setState(() => _idx = index);

  @override
  Widget build(BuildContext context) {
    if (!MindTrackBackend.instance.isSignedIn) return const LoginScreen();

    return StreamBuilder<Map<String, dynamic>?>(
      stream: MindTrackBackend.instance.watchPatient(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final patient = snapshot.data ?? <String, dynamic>{};
        if (patient['consented'] != true) return const ConsentScreen();
        final psychologistId = patient['psychologistId']?.toString();
        if (psychologistId == null || psychologistId.isEmpty) {
          return const PairingScreen();
        }

        final pages = [
          ClientOverview(patient: patient, psychologistId: psychologistId),
          ClientAppointments(patient: patient, psychologistId: psychologistId),
          ClientHomeworks(patient: patient, psychologistId: psychologistId),
          ClientProfile(patient: patient),
        ];
        final safeIndex = _idx.clamp(0, pages.length - 1);

        return Scaffold(
          body: pages[safeIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: safeIndex,
            onDestinationSelected: (index) => setState(() => _idx = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Ana Sayfa',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Randevu',
              ),
              NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment),
                label: 'Formlar',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profil',
              ),
            ],
          ),
        );
      },
    );
  }
}

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreed = false;
  bool _saving = false;

  Future<void> _continue() async {
    if (!_agreed) return;
    setState(() => _saving = true);
    try {
      final backend = MindTrackBackend.instance;
      await backend.upsertPatientProfile(
        consented: true,
        email: backend.userEmail ?? '',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Onam')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      'Psikolojik Danışmanlık Süreci Onam Formu\n\n'
                      'Bu metin, psikolojik danışmanlık sürecine ilişkin bilgilendirme ve onam metnidir. '
                      'Süreç boyunca paylaştığınız bilgilerin doğru ve güncel olmasına dikkat ediniz. '
                      'Acil durumlarda ilgili acil yardım servislerine başvurunuz.',
                    ),
                  ),
                ),
                CheckboxListTile(
                  value: _agreed,
                  onChanged: (value) =>
                      setState(() => _agreed = value ?? false),
                  title: const Text('Okudum, onaylıyorum'),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _agreed && !_saving ? _continue : null,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Devam Et'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _code = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      // Eşleşme tek bir sunucu çağrısıyla atomik tamamlanır: kod sahiplenir ve
      // danışanın satırı aynı işlemde güncellenir.
      final claim = await MindTrackBackend.instance.claimPairingCode(code);
      if (claim.psychologistId.isEmpty) throw 'Eşleşme bilgisi eksik.';

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Eşleşme Başarılı!')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eşleşme')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.link, size: 60, color: Colors.teal),
                const SizedBox(height: 16),
                const Text(
                  'Psikoloğunuzun verdiği kodu girin:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 4),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _pair,
                    child: const Text('Eşleşmeyi Tamamla'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ClientOverview extends StatelessWidget {
  const ClientOverview({
    super.key,
    required this.patient,
    required this.psychologistId,
  });

  final Map<String, dynamic> patient;
  final String psychologistId;

  @override
  Widget build(BuildContext context) {
    final name = _patientName(patient);
    return Scaffold(
      appBar: AppBar(title: const Text('MindTrack Danışan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Merhaba, $name',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Danışmanlık sürecinizi, formlarınızı ve randevularınızı buradan takip edebilirsiniz.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE0F2F1),
                child: Icon(Icons.calendar_month, color: Colors.teal),
              ),
              title: const Text('Randevu'),
              subtitle: const Text(
                'Yeni randevu talebi gönderin ve durumunu takip edin.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectTab(context, 1),
            ),
          ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE0F2F1),
                child: Icon(Icons.assignment, color: Colors.teal),
              ),
              title: const Text('Formlar ve Ödevler'),
              subtitle: const Text(
                'Psikoloğunuzun gönderdiği formları doldurun.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectTab(context, 2),
            ),
          ),
          if (_patientDiagnosisCodes(patient).isNotEmpty)
            Card(
              child: ExpansionTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE0F2F1),
                  child: Icon(
                    Icons.local_hospital_outlined,
                    color: Colors.teal,
                  ),
                ),
                title: const Text('Tanı Kodları'),
                subtitle: Text(
                  '${_patientDiagnosisCodes(patient).length} kod atanmış',
                ),
                children: [
                  for (final code in _patientDiagnosisCodes(patient))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.label_outline, size: 18),
                      title: Text(_diagnosisDisplay(code)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _selectTab(BuildContext context, int index) {
    final shell = context.findAncestorStateOfType<_ClientShellState>();
    shell?.selectTab(index);
  }
}

class ClientAppointments extends StatelessWidget {
  const ClientAppointments({
    super.key,
    required this.patient,
    required this.psychologistId,
  });

  final Map<String, dynamic> patient;
  final String psychologistId;

  @override
  Widget build(BuildContext context) {
    final backend = MindTrackBackend.instance;
    if (!backend.isSignedIn) return const SizedBox.shrink();
    final stream = backend.watchClientAppointments();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Randevu'),
        actions: [
          IconButton(
            tooltip: 'Randevu Talebi',
            onPressed: () => _openRequestDialog(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Randevular yüklenemedi: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = [
            ...snapshot.data!,
          ]..sort((a, b) => _appointmentDate(a).compareTo(_appointmentDate(b)));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: () => _openRequestDialog(context),
                icon: const Icon(Icons.event_available),
                label: const Text('Randevu Talebi Gönder'),
              ),
              const SizedBox(height: 18),
              const Text(
                'Randevularınız',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (docs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Henüz randevunuz veya bekleyen talebiniz bulunmuyor.',
                    ),
                  ),
                )
              else
                for (final doc in docs) _appointmentCard(context, doc),
            ],
          );
        },
      ),
    );
  }

  Widget _appointmentCard(BuildContext context, Map<String, dynamic> data) {
    final date = _appointmentDate(data);
    final status = data['status']?.toString() ?? 'pending';
    final statusLabel = _appointmentStatusLabel(status);
    final canCancel =
        status == 'pending' || status == 'approved' || status == 'planned';
    final color = status == 'approved' || status == 'planned'
        ? Colors.green
        : status == 'done'
        ? Colors.teal
        : status == 'rejected' || status == 'cancelled'
        ? Colors.grey
        : status == 'noshow'
        ? Colors.red
        : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(Icons.calendar_month, color: color),
        ),
        title: Text(_formatDateTime(date)),
        subtitle: Text('Durum: $statusLabel'),
        trailing: canCancel
            ? IconButton(
                tooltip: 'Randevuyu iptal et',
                onPressed: () => _cancelAppointment(context, data),
                icon: const Icon(Icons.event_busy_outlined),
              )
            : const SizedBox(width: 8),
      ),
    );
  }

  Future<void> _openRequestDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AppointmentRequestDialog(onSubmit: _createRequest),
    );
    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Randevu talebi gönderildi. Psikolog onayı bekleniyor.',
          ),
        ),
      );
    }
  }

  Future<void> _createRequest(DateTime selectedDateTime) async {
    if (!MindTrackBackend.instance.isSignedIn) throw 'Oturum bulunamadı.';
    if (selectedDateTime.isBefore(DateTime.now())) {
      throw 'Geçmiş bir tarih veya saat seçilemez.';
    }

    await MindTrackBackend.instance.createAppointmentRequest(
      at: selectedDateTime,
    );
  }

  Future<void> _cancelAppointment(
    BuildContext context,
    Map<String, dynamic> appointment,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Randevuyu iptal et'),
        content: const Text(
          'Bu randevu iptal edilecek ve psikolog tarafında da iptal olarak görünecek. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MindTrackBackend.instance.cancelAppointment(
        appointment['id'].toString(),
        by: 'client',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Randevu iptal edildi.')));
      }
    } on BackendException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Randevu iptal edilemedi: ${error.message}')),
        );
      }
    }
  }
}

class AppointmentRequestDialog extends StatefulWidget {
  const AppointmentRequestDialog({super.key, required this.onSubmit});

  final Future<void> Function(DateTime dateTime) onSubmit;

  @override
  State<AppointmentRequestDialog> createState() =>
      _AppointmentRequestDialogState();
}

class _AppointmentRequestDialogState extends State<AppointmentRequestDialog> {
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day + 1);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Randevu Talebi'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Psikoloğunuz için uygun tarih ve saati seçin.'),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: Text('Tarih: ${_formatDate(_date)}'),
            ),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text('Saat: ${_time.format(context)}'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Randevu Talebi Gönder'),
        ),
      ],
    );
  }
}

class ClientHomeworks extends StatelessWidget {
  const ClientHomeworks({
    super.key,
    required this.patient,
    required this.psychologistId,
  });

  final Map<String, dynamic> patient;
  final String psychologistId;

  @override
  Widget build(BuildContext context) {
    final backend = MindTrackBackend.instance;
    if (!backend.isSignedIn) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('Formlar ve Ödevler')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: backend.watchClientTasks(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Formlar yüklenemedi: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!;
          if (docs.isEmpty) {
            return const Center(
              child: Text('Henüz atanmış form veya ödev yok.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index];
              final done = data['done'] == true;
              final draft = _mapValue(data['formDraft']);
              final title =
                  data['title']?.toString() ??
                  draft['title']?.toString() ??
                  'Form';
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(title),
                  subtitle: Text(done ? 'Tamamlandı' : 'Bekliyor'),
                  trailing: Icon(
                    done ? Icons.check_circle : Icons.pending,
                    color: done ? Colors.green : Colors.orange,
                  ),
                  onTap: () => _openForm(context, data),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    Map<String, dynamic> task,
  ) async {
    final draft = _mapValue(task['formDraft']);
    if (draft.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu görevde doldurulabilir bir form bulunmuyor.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClientFormDialog(
        taskId: task['id'].toString(),
        taskData: task,
        draft: draft,
      ),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form Başarıyla Gönderildi.')),
      );
    }
  }
}

class ClientFormDialog extends StatefulWidget {
  const ClientFormDialog({
    super.key,
    required this.taskId,
    required this.taskData,
    required this.draft,
  });

  final String taskId;
  final Map<String, dynamic> taskData;
  final Map<String, dynamic> draft;

  @override
  State<ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends State<ClientFormDialog> {
  late final List<Map<String, dynamic>> _questions;
  late final Map<String, dynamic> _answers;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _questions = (_listValue(widget.draft['questions']))
        .map(_mapValue)
        .where((question) => question.isNotEmpty)
        .toList();
    _answers = _mapValue(widget.taskData['structuredAnswers']);
  }

  Future<void> _save() async {
    for (var index = 0; index < _questions.length; index++) {
      final question = _questions[index];
      if (question['required'] == false) continue;
      final id = question['id']?.toString() ?? 'q$index';
      final answer = _answers[id];
      if (answer == null || answer.toString().trim().isEmpty) {
        setState(() => _error = '${index + 1}. soru zorunludur.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await MindTrackBackend.instance.submitTask(
        widget.taskId,
        response: 'Form tamamlandı.',
        answers: _answers,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Hata: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.draft['title']?.toString() ??
        widget.taskData['title']?.toString() ??
        'Form';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((widget.draft['description']?.toString() ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(widget.draft['description'].toString()),
                ),
              for (var index = 0; index < _questions.length; index++) ...[
                _questionWidget(_questions[index], index),
                const SizedBox(height: 16),
              ],
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Formu Tamamla ve Gönder'),
        ),
      ],
    );
  }

  Widget _questionWidget(Map<String, dynamic> question, int index) {
    final id = question['id']?.toString() ?? 'q$index';
    final text = question['text']?.toString() ?? 'Soru ${index + 1}';
    final type = question['type']?.toString() ?? 'text';
    final help = question['helpText']?.toString() ?? '';
    final answer = _answers[id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${index + 1}. $text',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        if (help.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(help, style: const TextStyle(color: Colors.black54)),
        ],
        const SizedBox(height: 8),
        if (type == 'multiple_choice')
          ..._multipleChoice(question, id, answer)
        else if (type == 'yes_no')
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const SizedBox(
                    width: double.infinity,
                    child: Center(child: Text('Evet')),
                  ),
                  selected: answer == 'Evet',
                  onSelected: (_) => setState(() => _answers[id] = 'Evet'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const SizedBox(
                    width: double.infinity,
                    child: Center(child: Text('Hayır')),
                  ),
                  selected: answer == 'Hayır',
                  onSelected: (_) => setState(() => _answers[id] = 'Hayır'),
                ),
              ),
            ],
          )
        else if (type == 'scale')
          _scaleWidget(question, id, answer)
        else
          TextFormField(
            initialValue: answer?.toString() ?? '',
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Yanıtınız...',
            ),
            onChanged: (value) => _answers[id] = value,
          ),
      ],
    );
  }

  List<Widget> _multipleChoice(
    Map<String, dynamic> question,
    String id,
    dynamic answer,
  ) {
    final options = _listValue(question['options']);
    return [
      for (final option in options)
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          title: Text(option.toString()),
          value: option.toString(),
          groupValue: answer?.toString(),
          onChanged: (value) => setState(() => _answers[id] = value),
        ),
    ];
  }

  Widget _scaleWidget(
    Map<String, dynamic> question,
    String id,
    dynamic answer,
  ) {
    final max = (question['scaleMax'] as num?)?.toDouble() ?? 5;
    final current = ((answer as num?)?.toDouble() ?? 1)
        .clamp(1, max)
        .toDouble();
    return Column(
      children: [
        Slider(
          value: current,
          min: 1,
          max: max,
          divisions: (max - 1).toInt(),
          label: current.toInt().toString(),
          onChanged: (value) => setState(() => _answers[id] = value.toInt()),
        ),
        Text('Seçilen Değer: ${current.toInt()}'),
      ],
    );
  }
}

class ClientProfile extends StatefulWidget {
  const ClientProfile({super.key, required this.patient});

  final Map<String, dynamic> patient;

  @override
  State<ClientProfile> createState() => _ClientProfileState();
}

class _ClientProfileState extends State<ClientProfile> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final identity = _requestIdentity(widget.patient);
    _firstName = TextEditingController(text: identity.firstName);
    _lastName = TextEditingController(text: identity.lastName);
    _email = TextEditingController(text: identity.email);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!MindTrackBackend.instance.isSignedIn) return;
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    if (first.isEmpty || last.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad ve soyad alanlarını doldurun.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await MindTrackBackend.instance.saveProfile(
        firstName: first,
        lastName: last,
        email: _email.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profil kaydedildi.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _firstName,
            decoration: const InputDecoration(
              labelText: 'Ad',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lastName,
            decoration: const InputDecoration(
              labelText: 'Soyad',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'E-posta',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Kaydediliyor...' : 'Profili Kaydet'),
          ),
          const SizedBox(height: 30),
          OutlinedButton.icon(
            onPressed: () => MindTrackBackend.instance.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
  }
}

class _RequestIdentity {
  const _RequestIdentity({
    required this.name,
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  final String name;
  final String firstName;
  final String lastName;
  final String email;
}

_RequestIdentity _requestIdentity(Map<String, dynamic> patient) {
  final backend = MindTrackBackend.instance;
  final email = _firstNonEmpty([
    patient['email']?.toString(),
    backend.userEmail,
    '',
  ]);
  final storedFirst = patient['firstName']?.toString().trim() ?? '';
  final storedLast = patient['lastName']?.toString().trim() ?? '';
  final storedName = _firstNonEmpty([
    patient['name']?.toString(),
    patient['displayName']?.toString(),
    backend.displayName,
    '',
  ]);
  final parts = storedName
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  final first = _firstNonEmpty([
    storedFirst,
    parts.isEmpty ? '' : parts.first,
    email.split('@').first,
  ]);
  final last = _firstNonEmpty([
    storedLast,
    parts.length > 1 ? parts.sublist(1).join(' ') : '',
  ]);
  final name = _firstNonEmpty([
    storedName,
    [first, last].where((part) => part.isNotEmpty).join(' '),
    email.split('@').first,
  ]);
  return _RequestIdentity(
    name: name,
    firstName: first,
    lastName: last,
    email: email,
  );
}

String _patientName(Map<String, dynamic> patient) =>
    _requestIdentity(patient).name;

List<String> _patientDiagnosisCodes(Map<String, dynamic> patient) {
  return _listValue(patient['diagnosisCodes'])
      .map((value) => value.toString())
      .where((value) => value.trim().isNotEmpty)
      .toList();
}

String _diagnosisDisplay(String code) {
  for (final item in diagnosisCodes) {
    if (item.code == code) return item.display;
  }
  return code;
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final clean = value?.trim() ?? '';
    if (clean.isNotEmpty) return clean;
  }
  return '';
}

Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

List<dynamic> _listValue(dynamic value) =>
    value is List ? value : const <dynamic>[];

/// Randevu zamanı. Supabase `timestamptz` alanlarını ISO-8601 metin olarak
/// döndürür; geçmişte kalan yerel kayıtlar için diğer temsiller de desteklenir.
DateTime _appointmentDate(Map<String, dynamic> data) {
  final raw = data['date'];
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw)?.toLocal() ?? DateTime(2100);
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  return DateTime(2100);
}

String _appointmentStatusLabel(String status) {
  switch (status) {
    case 'approved':
      return 'Onaylandı';
    case 'planned':
      return 'Planlandı';
    case 'rejected':
      return 'Reddedildi';
    case 'cancelled':
      return 'İptal Edildi';
    case 'done':
      return 'Tamamlandı';
    case 'noshow':
      return 'Gelmedi';
    default:
      return 'Beklemede';
  }
}

String _formatDateTime(DateTime value) =>
    '${_formatDate(value)} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _formatDate(DateTime value) {
  const months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

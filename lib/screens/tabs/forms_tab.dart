import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/form_presets.dart';
import '../../data/mindtrack_backend.dart';
import '../../models/app_data.dart';
import '../../models/assessment.dart';
import '../../models/client.dart';
import '../../models/form_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/formats.dart';
import '../../utils/scoring.dart';

/// Değerlendirme Formları — form oluşturma, düzenleme, kopyalama, silme ve doldurma.
class FormsTab extends StatefulWidget {
  const FormsTab({super.key, required this.data});

  final DataStore data;

  @override
  State<FormsTab> createState() => _FormsTabState();
}

class _FormsTabState extends State<FormsTab> {
  String _q = '';

  AppData get _d => widget.data.data;

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final forms = _d.forms.where((f) {
      if (q.isEmpty) return true;
      return f.title.toLowerCase().contains(q) ||
          f.description.toLowerCase().contains(q);
    }).toList();
    final totalQuestions = _d.forms.fold<int>(
      0,
      (s, f) => s + f.questions.length,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, totalQuestions),
              const SizedBox(height: 16),
              if (_d.forms.isEmpty)
                _emptyState(context)
              else ...[
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: 'Form ara...',
                    prefixIcon: const Icon(Icons.search, size: 19),
                    suffixIcon: _q.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _q = ''),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                if (forms.isEmpty)
                  _searchEmpty()
                else
                  LayoutBuilder(
                    builder: (context, bc) {
                      final cols = bc.maxWidth >= 980
                          ? 3
                          : bc.maxWidth >= 640
                          ? 2
                          : 1;
                      final gap = 14.0;
                      final cardW = (bc.maxWidth - gap * (cols - 1)) / cols;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final f in forms)
                            SizedBox(
                              width: cardW,
                              child: _formCard(context, f),
                            ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: AppColors.muted),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Formu düzenleyebilir, danışana gönderebilir veya bu cihazda örnek olarak doldurabilirsiniz.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int totalQuestions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Değerlendirme Formları',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_d.forms.length} form · $totalQuestions soru',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _openPresetLibrary(context),
              icon: const Icon(Icons.library_add_outlined, size: 17),
              label: const Text('Hazır Form Ekle', style: TextStyle()),
            ),
            FilledButton.icon(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Yeni Form', style: TextStyle()),
            ),
          ],
        );
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [title, const SizedBox(height: 12), actions],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.assignment_outlined,
                size: 28,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Henüz form yok',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'İlk değerlendirme formunuzu oluşturarak danışanlarınızın bilgilerini toplamaya başlayın.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('İlk Formu Oluştur', style: TextStyle()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bg2.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border2),
      ),
      child: const Column(
        children: [
          Icon(Icons.search_off, size: 26, color: AppColors.muted),
          SizedBox(height: 8),
          Text(
            'Arama kriterlerinize uygun form bulunamadı',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.text2),
          ),
        ],
      ),
    );
  }

  Widget _formCard(BuildContext context, FormEntry f) {
    final n = _d.assessments.where((a) => a.formId == f.id).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  f.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _activeChip(f.isActive),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            f.description.isNotEmpty ? f.description : 'Açıklama eklenmemiş',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: f.description.isNotEmpty
                  ? AppColors.text2
                  : AppColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _miniStat(Icons.list_alt, '${f.questions.length} soru'),
              _miniStat(
                Icons.assignment_turned_in_outlined,
                '$n değerlendirme',
              ),
              _miniStat(
                Icons.refresh,
                'Günc. ${fmtDate(DateTime.fromMillisecondsSinceEpoch((f.updatedAt > 0 ? f.updatedAt : f.createdAt).toInt()))}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: () => _openEditor(context, form: f),
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('Düzenle', style: TextStyle(fontSize: 12.5)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: () => _openFill(context, f),
                icon: const Icon(Icons.edit_note, size: 15),
                label: const Text('Doldur', style: TextStyle(fontSize: 12.5)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: () => _openIncomingResponses(f),
                icon: const Icon(Icons.inbox_outlined, size: 15),
                label: const Text('Cevaplar', style: TextStyle(fontSize: 12.5)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: () => _openAssignment(context, f),
                icon: const Icon(Icons.send_outlined, size: 15),
                label: const Text(
                  'Danışana Gönder',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
              IconButton(
                tooltip: 'Kopyala',
                visualDensity: VisualDensity.compact,
                onPressed: () => _duplicate(f),
                icon: const Icon(
                  Icons.copy_outlined,
                  size: 18,
                  color: AppColors.text2,
                ),
              ),
              IconButton(
                tooltip: 'Sil',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmDelete(context, f),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activeChip(bool active) {
    final fg = active ? AppColors.success : AppColors.muted;
    final bg = active ? AppColors.successSoft : AppColors.bg2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        active ? 'Aktif' : 'Pasif',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _miniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
        ),
      ],
    );
  }

  // ---------------- Aksiyonlar ----------------
  Future<void> _openPresetLibrary(BuildContext context) async {
    final result = await showDialog<FormEntry>(
      context: context,
      builder: (_) => ReadyFormLibraryDialog(newId: widget.data.newId),
    );
    if (result == null) return;
    _d.forms.add(result);
    widget.data.save();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${result.title} hazır form olarak eklendi.')),
        );
      setState(() {});
    }
  }

  void _openEditor(BuildContext context, {FormEntry? form}) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => FormEditorDialog(data: widget.data, existing: form),
    );
    if (ok == true) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Form kaydedildi.', style: TextStyle())),
        );
    }
  }

  void _openFill(BuildContext context, FormEntry f) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => FillFormDialog(data: widget.data, form: f),
    );
    if (ok == true) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Değerlendirme kaydedildi: ${f.title}',
              style: const TextStyle(),
            ),
          ),
        );
    }
  }

  Future<void> _openAssignment(BuildContext context, FormEntry form) async {
    final client = await showDialog<Client>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Danışana Form Gönder'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: _d.clients.isEmpty
              ? const Center(child: Text('Önce bir danışan ekleyin.'))
              : ListView.separated(
                  itemCount: _d.clients.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final client = _d.clients[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text(client.initials)),
                      title: Text(client.name),
                      subtitle: Text(
                        client.email.isEmpty ? 'E-posta yok' : client.email,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(ctx).pop(client),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );
    if (client == null || !mounted) return;

    final backend = MindTrackBackend.instance;
    final ready = await _ensureBackendSession(context);
    if (!ready || !mounted) return;

    final clientUid = await backend.resolveClientUserId(client);
    if (clientUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu danışan henüz eşleşmemiş. Önce danışan koduyla eşleşmeyi tamamlayın.',
          ),
        ),
      );
      return;
    }

    try {
      await backend.assignTask(
        clientRef: client.id,
        clientUid: clientUid,
        clientName: client.name,
        clientEmail: client.email,
        title: form.title,
        description: form.description,
        formRef: form.id,
        formDraft: {
          'id': form.id,
          'title': form.title,
          'description': form.description,
          'isActive': form.isActive,
          'questions': form.questions.map((q) => q.toJson()).toList(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${form.title} danışana gönderildi.')),
      );
    } on BackendException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Form gönderilemedi: ${error.message}')),
      );
    }
  }

  /// Danışanlardan gelen form cevaplarını canlı olarak gösterir.
  Future<void> _openIncomingResponses(FormEntry f) async {
    final ready = await _ensureBackendSession(context);
    if (!ready || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _IncomingResponsesDialog(form: f),
    );
  }

  /// Yerel hesabın uzak karşılığı açık değilse şifre ister.
  Future<bool> _ensureBackendSession(BuildContext context) async {
    final backend = MindTrackBackend.instance;
    if (backend.isSignedIn) return true;

    final email = widget.data.accounts.current?.email.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Önce hesabınızla giriş yapın.')),
        );
      }
      return false;
    }

    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabını bağla'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$email hesabıyla oturum açılacak.'),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Hesap şifresi'),
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Bağlan'),
          ),
        ],
      ),
    );
    if (confirmed != true || password.text.isEmpty) {
      password.dispose();
      return false;
    }

    try {
      await backend.signIn(email, password.text);
      password.dispose();
      return true;
    } on BackendException catch (error) {
      password.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Oturum açılamadı: ${error.message}')),
        );
      }
      return false;
    }
  }

  void _duplicate(FormEntry f) {
    final copy = FormEntry(
      id: widget.data.newId(),
      title: '${f.title} (Kopya)',
      description: f.description,
      isActive: false,
    );
    for (var i = 0; i < f.questions.length; i++) {
      final q = f.questions[i];
      copy.questions.add(
        FormQuestion(
          id: widget.data.newId(),
          type: q.type,
          text: q.text,
          required: q.required,
          options: List.of(q.options),
          expectedAnswer: q.expectedAnswer,
          helpText: q.helpText,
          scaleMax: q.scaleMax,
          order: i,
        ),
      );
    }
    _d.forms.add(copy);
    widget.data.save();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Form kopyalandı (pasif olarak eklendi).',
            style: TextStyle(),
          ),
        ),
      );
  }

  Future<void> _confirmDelete(BuildContext context, FormEntry f) async {
    final n = _d.assessments.where((a) => a.formId == f.id).length;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Formu sil', style: TextStyle()),
        content: Text(
          '"${f.title}" silinecek. Bu forma ait $n değerlendirme kaydı da silinir. Bu işlem geri alınamaz.',
          style: const TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç', style: TextStyle()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Evet, Sil', style: TextStyle()),
          ),
        ],
      ),
    );
    if (ok == true) {
      _d.forms.removeWhere((x) => x.id == f.id);
      _d.assessments.removeWhere((a) => a.formId == f.id);
      widget.data.save();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Form silindi.', style: TextStyle())),
        );
    }
  }
}

/// Danışanların gönderdiği form cevaplarını canlı izleyen pencere.
///
/// Cevaplar `tasks` tablosunda durur. Danışan `submit_task` ile yazdığında
/// Realtime üzerinden akış anında tazelenir; ayrıca "Yenile" düğmesi
/// bağlantı kopmuşsa elle çekme imkânı verir.
class _IncomingResponsesDialog extends StatefulWidget {
  const _IncomingResponsesDialog({required this.form});

  final FormEntry form;

  @override
  State<_IncomingResponsesDialog> createState() =>
      _IncomingResponsesDialogState();
}

class _IncomingResponsesDialogState
    extends State<_IncomingResponsesDialog> {
  List<Map<String, dynamic>>? _rows;

  Future<void> _reload() async {
    final uid = MindTrackBackend.instance.userId;
    if (uid == null) return;
    try {
      final rows = await MindTrackBackend.instance.psychologistTasks();
      if (!mounted) return;
      setState(() => _rows = rows);
    } on BackendException {
      // Akış zaten canlı; sessizce geç, bir sonraki değişiklikte düzelir.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: SizedBox(
        width: 680,
        height: 640,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: MindTrackBackend.instance.watchPsychologistTasks(),
          builder: (context, snapshot) {
            final all = snapshot.data ?? _rows ?? const <Map<String, dynamic>>[];
            final rows =
                all.where((t) => t['formId'] == widget.form.id).toList()
                  ..sort((a, b) => _time(b).compareTo(_time(a)));
            final answered = rows.where(_isAnswered).length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, rows.length, answered),
                const Divider(height: 1),
                Expanded(
                  child: rows.isEmpty
                      ? const _IncomingEmpty()
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ResponseCard(row: rows[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static double _time(Map<String, dynamic> row) =>
      (row['createdAtMs'] as num?)?.toDouble() ?? 0;

  static bool _isAnswered(Map<String, dynamic> row) {
    final text = (row['response'] ?? '').toString().trim();
    final answers = row['structuredAnswers'];
    return text.isNotEmpty || (answers is Map && answers.isNotEmpty);
  }

  Widget _header(BuildContext context, int total, int answered) {
    final pending = total - answered;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gelen Cevaplar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.form.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (answered > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 2),
              child: _countChip('$answered cevap', AppColors.success),
            ),
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 2),
              child: _countChip('$pending bekliyor', AppColors.muted),
            ),
          IconButton(
            tooltip: 'Yenile',
            visualDensity: VisualDensity.compact,
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 19),
          ),
          IconButton(
            tooltip: 'Kapat',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _countChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

/// Tek bir danışanın cevabı: soru/cevap listesi ve durum.
class _ResponseCard extends StatelessWidget {
  const _ResponseCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final name = (row['clientName'] ?? '').toString().trim();
    final answers = row['structuredAnswers'];
    final freeText = (row['response'] ?? '').toString().trim();
    final answered = _IncomingResponsesDialogState._isAnswered(row);
    final created = (row['createdAtMs'] as num?)?.toDouble() ?? 0;
    final draft = row['formDraft'];
    final questions = draft is Map
        ? ((draft['questions'] as List?) ?? const [])
            .map((e) => FormQuestion.fromJson(e as Map<String, dynamic>))
            .toList()
        : <FormQuestion>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                child: Text(
                  initials(name.isEmpty ? '?' : name),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'İsimsiz danışan' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      answered
                          ? 'Cevaplandı · ${timeAgo(created)}'
                          : 'Gönderildi · ${timeAgo(created)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (answered ? AppColors.success : AppColors.warning)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  answered ? 'Cevaplandı' : 'Bekliyor',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: answered ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          if (!answered) ...[
            const SizedBox(height: 10),
            const Text(
              'Danışan bu formu henüz doldurmadı.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            for (final q in questions) ...[
              _answerRow(q, answers is Map ? answers[q.id] : null),
              const SizedBox(height: 8),
            ],
            if (freeText.isNotEmpty) ...[
              const SizedBox(height: 2),
              const Text(
                'Serbest metin',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                freeText,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.text,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _answerRow(FormQuestion q, Object? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q.text,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.muted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _formatAnswer(value),
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  /// Cevap tipleri metin, sayı, boolean veya çoklu seçim listesi olabilir.
  static String _formatAnswer(Object? value) {
    if (value == null) return '—';
    if (value is List) {
      return value.isEmpty ? '—' : value.map((e) => e.toString()).join(', ');
    }
    if (value is bool) return value ? 'Evet' : 'Hayır';
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }
}

class _IncomingEmpty extends StatelessWidget {
  const _IncomingEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 34,
            color: AppColors.muted,
          ),
          const SizedBox(height: 10),
          const Text(
            'Bu form henüz danışana gönderilmedi.',
            style: TextStyle(fontSize: 13, color: AppColors.text2),
          ),
          const SizedBox(height: 4),
          const Text(
            'Gönderdiğinizde cevaplar burada belirir.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Düzenleme sırasında kullanılan soru taslağı.
class _QDraft {
  _QDraft({
    required this.id,
    this.type = 'text',
    this.text = '',
    this.required = true,
    this.helpText = '',
    List<String>? options,
    this.scaleMax = 5,
  }) : options = options ?? [];

  final String id;
  String type;
  String text;
  bool required;
  String helpText;
  List<String> options;
  int scaleMax;

  FormQuestion toQuestion(int order) => FormQuestion(
    id: id,
    type: type,
    text: text,
    required: required,
    options: type == 'multiple_choice' ? options : null,
    helpText: helpText,
    scaleMax: scaleMax,
    order: order,
  );
}

/// Form oluşturma / düzenleme penceresi.
class FormEditorDialog extends StatefulWidget {
  const FormEditorDialog({super.key, required this.data, this.existing});

  final DataStore data;
  final FormEntry? existing;

  @override
  State<FormEditorDialog> createState() => _FormEditorDialogState();
}

class _FormEditorDialogState extends State<FormEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late bool _active;
  late final List<_QDraft> _qs;
  String? _error;

  DataStore get _data => widget.data;

  @override
  void initState() {
    super.initState();
    final f = widget.existing;
    _title = TextEditingController(text: f?.title ?? '');
    _desc = TextEditingController(text: f?.description ?? '');
    _active = f?.isActive ?? true;
    _qs = [
      for (final q in f?.questions ?? <FormQuestion>[])
        _QDraft(
          id: q.id,
          type: q.type,
          text: q.text,
          required: q.required,
          helpText: q.helpText,
          options: List.of(q.options),
          scaleMax: q.scaleMax,
        ),
    ];
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _addQuestion() {
    setState(() {
      _qs.add(_QDraft(id: _data.newId()));
    });
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Form başlığı gereklidir.');
      return;
    }
    for (var i = 0; i < _qs.length; i++) {
      final q = _qs[i];
      if (q.text.trim().isEmpty) {
        setState(() => _error = '${i + 1}. sorunun metni boş olamaz.');
        return;
      }
      if (q.type == 'multiple_choice' &&
          q.options.where((o) => o.trim().isNotEmpty).length < 2) {
        setState(() => _error = '${i + 1}. soruda en az 2 seçenek olmalı.');
        return;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final existing = widget.existing;
    if (existing != null) {
      existing.title = title;
      existing.description = _desc.text.trim();
      existing.isActive = _active;
      existing.updatedAt = now;
      existing.questions
        ..clear()
        ..addAll([for (var i = 0; i < _qs.length; i++) _qs[i].toQuestion(i)]);
    } else {
      _data.data.forms.add(
        FormEntry(
          id: _data.newId(),
          title: title,
          description: _desc.text.trim(),
          isActive: _active,
          questions: [
            for (var i = 0; i < _qs.length; i++) _qs[i].toQuestion(i),
          ],
        ),
      );
    }
    _data.save();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing != null
                          ? 'Formu Düzenle'
                          : 'Yeni Değerlendirme Formu',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: 'Form Başlığı *',
                        hintText: 'Örn: İlk Görüşme Değerlendirme Formu',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _desc,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama (İsteğe Bağlı)',
                        hintText: 'Form hakkında kısa bir açıklama...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Form aktif',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: const Text(
                        'Pasif formlar listede kalır, doldurulamaz.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Sorular',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _addQuestion,
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text(
                            'Soru Ekle',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_qs.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.bg2.withValues(alpha: .4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border2),
                        ),
                        child: const Text(
                          'Henüz soru yok. "Soru Ekle" ile başlayın.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.muted,
                          ),
                        ),
                      )
                    else
                      for (var i = 0; i < _qs.length; i++)
                        _questionCard(context, i),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 18,
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('İptal', style: TextStyle()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Kaydet', style: TextStyle()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionCard(BuildContext context, int i) {
    final q = _qs[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg2.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: q.required ? AppColors.primarySoft : AppColors.bg2,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${questionTypeLabel(q.type)}${q.required ? ' · Zorunlu' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: q.required ? AppColors.primaryDark : AppColors.muted,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Yukarı',
                visualDensity: VisualDensity.compact,
                onPressed: i == 0
                    ? null
                    : () => setState(() {
                        final t = _qs[i - 1];
                        _qs[i - 1] = q;
                        _qs[i] = t;
                      }),
                icon: const Icon(
                  Icons.keyboard_arrow_up,
                  size: 19,
                  color: AppColors.text2,
                ),
              ),
              IconButton(
                tooltip: 'Aşağı',
                visualDensity: VisualDensity.compact,
                onPressed: i == _qs.length - 1
                    ? null
                    : () => setState(() {
                        final t = _qs[i + 1];
                        _qs[i + 1] = q;
                        _qs[i] = t;
                      }),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  size: 19,
                  color: AppColors.text2,
                ),
              ),
              IconButton(
                tooltip: 'Kopyala',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  final c = _QDraft(
                    id: _data.newId(),
                    type: q.type,
                    text: q.text,
                    required: q.required,
                    helpText: q.helpText,
                    options: List.of(q.options),
                    scaleMax: q.scaleMax,
                  );
                  _qs.insert(i + 1, c);
                }),
                icon: const Icon(
                  Icons.copy_outlined,
                  size: 17,
                  color: AppColors.text2,
                ),
              ),
              IconButton(
                tooltip: 'Sil',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _qs.removeAt(i)),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: q.type,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Soru Türü',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Açık Uçlu')),
                    DropdownMenuItem(
                      value: 'multiple_choice',
                      child: Text('Çoktan Seçmeli'),
                    ),
                    DropdownMenuItem(value: 'scale', child: Text('Ölçek')),
                    DropdownMenuItem(
                      value: 'yes_no',
                      child: Text('Evet/Hayır'),
                    ),
                  ],
                  onChanged: (v) => setState(() => q.type = v ?? 'text'),
                ),
              ),
              const SizedBox(width: 10),
              q.type == 'scale'
                  ? SizedBox(
                      width: 110,
                      child: DropdownButtonFormField<int>(
                        initialValue: q.scaleMax,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Ölçek',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('1 – 5')),
                          DropdownMenuItem(value: 10, child: Text('1 – 10')),
                        ],
                        onChanged: (v) => setState(() => q.scaleMax = v ?? 5),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: q.required,
                          onChanged: (v) =>
                              setState(() => q.required = v ?? true),
                        ),
                        const Text('Zorunlu', style: TextStyle(fontSize: 13)),
                      ],
                    ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'SORU METNİ *',
              hintText: 'Sorunuzu buraya yazın...',
            ),
            initialValue: q.text,
            onChanged: (v) => q.text = v,
          ),
          const SizedBox(height: 8),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Açıklama / Yardım (İsteğe Bağlı)',
              hintText: 'Danışana küçük bir yönlendirme...',
            ),
            initialValue: q.helpText,
            onChanged: (v) => q.helpText = v,
          ),
          if (q.type == 'multiple_choice') ...[
            const SizedBox(height: 8),
            const Text(
              'SEÇENEKLER *',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            for (var j = 0; j < q.options.length; j++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Seçenek',
                        ),
                        initialValue: q.options[j],
                        onChanged: (v) => q.options[j] = v,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Seçeneği sil',
                      visualDensity: VisualDensity.compact,
                      onPressed: q.options.length <= 2
                          ? null
                          : () => setState(() => q.options.removeAt(j)),
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(
                  () => q.options.add('Seçenek ${q.options.length + 1}'),
                ),
                icon: const Icon(Icons.add, size: 15),
                label: const Text(
                  'Seçenek Ekle',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
          if (q.type == 'scale') ...[
            const SizedBox(height: 4),
            Text(
              'Ölçek aralığı: 1 – ${q.scaleMax}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hazır form şablonları ve lisanslı JSON içe aktarma penceresi.
class ReadyFormLibraryDialog extends StatelessWidget {
  const ReadyFormLibraryDialog({super.key, required this.newId});

  final String Function() newId;

  Future<void> _importJson(BuildContext context) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty) return;
      final raw = utf8.decode(await files.single.readAsBytes());
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('JSON nesnesi bekleniyor.');
      }
      final source = FormEntry.fromJson(Map<String, dynamic>.from(decoded));
      if (source.title.trim().isEmpty || source.questions.isEmpty) {
        throw const FormatException('Form başlığı ve en az bir soru gerekli.');
      }
      final form = FormEntry(
        id: newId(),
        title: source.title,
        description: source.description,
        isActive: source.isActive,
        diagnosisCodes: List.of(source.diagnosisCodes),
        questions: [
          for (final q in source.questions)
            FormQuestion(
              id: newId(),
              type: q.type,
              text: q.text,
              required: q.required,
              options: List.of(q.options),
              expectedAnswer: q.expectedAnswer,
              helpText: q.helpText,
              scaleMax: q.scaleMax,
              order: q.order,
            ),
        ],
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(form);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Form içe aktarılamadı: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 700),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hazır Form Kütüphanesi',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Hazır bir şablonu forma ekleyin veya lisanslı form JSON’u içe aktarın.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: formPresets.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final preset = formPresets[index];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            preset.requiresLicense
                                ? Icons.lock_outline
                                : Icons.assignment_outlined,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                preset.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                preset.description,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.text2,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${preset.category} · ${preset.questionCount} soru',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                preset.licenseNote,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        preset.requiresLicense
                            ? OutlinedButton.icon(
                                onPressed: () => _importJson(context),
                                icon: const Icon(Icons.upload_file, size: 15),
                                label: const Text('JSON İçe Aktar'),
                              )
                            : FilledButton.icon(
                                onPressed: () =>
                                    Navigator.pop(context, preset.build(newId)),
                                icon: const Icon(Icons.add, size: 15),
                                label: const Text('Ekle'),
                              ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: const Text(
                'İçe aktarma biçimi: FormEntry.toJson() çıktısı veya aynı alanları içeren bir JSON nesnesi. BDI-II gibi lisanslı ölçeklerde soru metni ve kullanım hakkı kullanıcıya aittir.',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Form doldurma penceresi.
class FillFormDialog extends StatefulWidget {
  const FillFormDialog({super.key, required this.data, required this.form});

  final DataStore data;
  final FormEntry form;

  @override
  State<FillFormDialog> createState() => _FillFormDialogState();
}

class _FillFormDialogState extends State<FillFormDialog> {
  late final Map<String, Object?> _answers = {};
  String? _clientId;
  String? _error;

  DataStore get _data => widget.data;
  FormEntry get _form => widget.form;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _form.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        if (_form.description.isNotEmpty)
                          Text(
                            _form.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _clientId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Danışan',
                        hintText: 'Danışan seçilmedi',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Danışan seçilmedi'),
                        ),
                        for (final c in _data.data.clients)
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (v) => setState(() => _clientId = v ?? ''),
                    ),
                    const SizedBox(height: 18),
                    for (final q in _form.questions) _questionField(q),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 18,
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('İptal', style: TextStyle()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text(
                      'Değerlendirmeyi Kaydet',
                      style: TextStyle(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionField(FormQuestion q) {
    final value = _answers[q.id];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg2.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${q.text}${q.required ? ' *' : ''}',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          if (q.helpText.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              q.helpText,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 10),
          if (q.type == 'text' || q.type == 'date' || q.type == 'number')
            TextField(
              keyboardType: q.type == 'number'
                  ? TextInputType.number
                  : q.type == 'date'
                  ? TextInputType.datetime
                  : TextInputType.multiline,
              maxLines: q.type == 'text' ? 3 : 1,
              decoration: const InputDecoration(isDense: true),
              onChanged: (v) => _answers[q.id] = v,
            )
          else if (q.type == 'scale')
            _scalePicker(q, value)
          else if (q.type == 'yes_no')
            _yesNoPicker(q, value?.toString())
          else if (q.type == 'multiple_choice')
            _choicePicker(q, value?.toString())
          else if (q.type == 'multi_select')
            _multiSelectPicker(q, value),
        ],
      ),
    );
  }

  Widget _scalePicker(FormQuestion q, Object? value) {
    final v = value is int
        ? value
        : value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var n = 1; n <= q.scaleMax; n++)
          ChoiceChip(
            label: Text('$n'),
            selected: v == n,
            onSelected: (_) => setState(() => _answers[q.id] = n),
          ),
      ],
    );
  }

  Widget _yesNoPicker(FormQuestion q, String? v) {
    return Wrap(
      spacing: 8,
      children: [
        for (final opt in ['Evet', 'Hayır'])
          ChoiceChip(
            label: Text(opt),
            selected: v == opt,
            onSelected: (_) => setState(() => _answers[q.id] = opt),
          ),
      ],
    );
  }

  Widget _choicePicker(FormQuestion q, String? v) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final opt in q.options)
          ChoiceChip(
            label: Text(opt),
            selected: v == opt,
            onSelected: (_) => setState(() => _answers[q.id] = opt),
          ),
      ],
    );
  }

  Widget _multiSelectPicker(FormQuestion q, Object? value) {
    final sel = value is List ? value.cast<String>() : <String>[];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final opt in q.options)
          FilterChip(
            label: Text(opt),
            selected: sel.contains(opt),
            onSelected: (on) => setState(() {
              if (on) {
                sel.add(opt);
              } else {
                sel.remove(opt);
              }
              _answers[q.id] = List.of(sel);
            }),
          ),
      ],
    );
  }

  void _submit() {
    if (!_form.isActive) {
      setState(() => _error = 'Bu form pasif durumda, doldurulamaz.');
      return;
    }
    for (final q in _form.questions) {
      if (!q.required) continue;
      final v = _answers[q.id];
      final empty =
          v == null ||
          (v is String && v.trim().isEmpty) ||
          (v is List && v.isEmpty);
      if (empty) {
        setState(() => _error = 'Lütfen zorunlu soruları yanıtlayın.');
        return;
      }
    }
    // değerlendirme kaydı
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final a = Assessment(
      id: _data.newId(),
      clientId: _clientId ?? '',
      formId: _form.id,
      answers: Map.of(_answers),
      submittedAt: now,
    );
    final sc = assessmentScore(_data.data, a);
    a.score = sc?.avg;
    final form = _data.data.formById(_form.id);
    a.risk =
        form != null &&
        _form.questions.any((q) {
          final v = a.answers[q.id];
          if (v == null) return false;
          if (q.type == 'yes_no' &&
              RegExp(
                r'(zarar|intihar|canına kıyma|hayatına son|risk)',
                caseSensitive: false,
              ).hasMatch(q.text)) {
            return v.toString().toLowerCase().contains('evet');
          }
          if (q.type == 'scale' &&
              RegExp(
                r'(zarar|intihar|canına kıyma|hayatına son|risk)',
                caseSensitive: false,
              ).hasMatch(q.text)) {
            final n = v is int ? v : int.tryParse(v.toString());
            if (n != null) return n >= (q.scaleMax > 0 ? q.scaleMax : 5);
          }
          return false;
        });
    _data.data.assessments.add(a);
    _data.save();
    Navigator.of(context).pop(true);
  }
}

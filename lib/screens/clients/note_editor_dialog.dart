import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../models/note.dart';
import '../../theme/app_theme.dart';
import '../../utils/formats.dart';

const _moods = ['Çok İyi', 'İyi', 'Orta', 'Kötü', 'Çok Kötü'];

/// SOAP seans notu oluşturma / düzenleme penceresi.
class NoteEditorDialog extends StatefulWidget {
  const NoteEditorDialog({super.key, required this.data, required this.clientId, this.existing});

  final DataStore data;
  final String clientId;
  final Note? existing;

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _subjective;
  late final TextEditingController _objective;
  late final TextEditingController _assessment;
  late final TextEditingController _plan;
  String _mood = 'Orta';
  DateTime _date = DateTime.now();
  String? _error;

  /// Kullanıcı notu değiştirdiyse pencere kapatılırken uyarılır.
  /// Kaydedilmemiş bir seans notu, güncelleme veya yanlışlıkla çıkış
  /// yüzünden kaybolmamalıdır.
  bool _dirty = false;

  /// PopScope `canPop: false` iken programatik `Navigator.pop` da engellenir.
  /// Bu bayrak, onaylanmış çıkışların (Kaydet / Vazgeç) gerçekten kapandığını
  /// garanti eder; aksi halde Kaydet'e basınca uyarı penceresi açılırdı.
  bool _allowPop = false;

  /// Onaylanmış çıkış: izin bayrağını açıp bir sonraki karede kapatır.
  void _closeWith(Object? result) {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  /// Kaydedilmemiş değişiklik varken kapanmayı sorar.
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kaydedilmemiş değişiklik'),
        content: const Text(
          'Bu seans notunda kaydedilmemiş değişiklikler var. Çıkarsanız '
          'değişiklikler kaybolur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yine de çık'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    _title = TextEditingController(text: n?.title ?? '');
    _subjective = TextEditingController(text: n?.subjective ?? '');
    _objective = TextEditingController(text: n?.objective ?? '');
    _assessment = TextEditingController(text: n?.assessment ?? '');
    _plan = TextEditingController(text: n?.plan ?? '');
    _mood = n?.mood.isNotEmpty == true ? n!.mood : 'Orta';
    if (n != null && n.date > 0) {
      _date = DateTime.fromMillisecondsSinceEpoch(n.date.toInt());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _subjective.dispose();
    _objective.dispose();
    _assessment.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Not başlığı gereklidir.');
      return;
    }
    if (_subjective.text.trim().isEmpty &&
        _objective.text.trim().isEmpty &&
        _assessment.text.trim().isEmpty &&
        _plan.text.trim().isEmpty) {
      setState(() => _error = 'Not içeriği boş olamaz.');
      return;
    }
    final now = _date.millisecondsSinceEpoch.toDouble();
    final existing = widget.existing;
    if (existing != null) {
      existing.title = _title.text.trim();
      existing.mood = _mood;
      existing.subjective = _subjective.text.trim();
      existing.objective = _objective.text.trim();
      existing.assessment = _assessment.text.trim();
      existing.plan = _plan.text.trim();
      existing.date = now;
    } else {
      widget.data.data.notes.add(Note(
        id: widget.data.newId(),
        clientId: widget.clientId,
        title: _title.text.trim(),
        mood: _mood,
        subjective: _subjective.text.trim(),
        objective: _objective.text.trim(),
        assessment: _assessment.text.trim(),
        plan: _plan.text.trim(),
        date: now,
      ));
    }
    widget.data.save();
    _closeWith(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard()) _closeWith(result);
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radius)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
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
                            widget.existing != null
                                ? 'Seans Notunu Düzenle'
                                : 'Yeni Seans Notu (SOAP)',
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'S — Öznel, O — Nesnel, A — Değerlendirme, P — Plan',
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () async {
                        if (await _confirmDiscard()) _closeWith(false);
                      },
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _title,
                              decoration: const InputDecoration(
                                labelText: 'Not Başlığı *',
                                hintText: 'Örn: Seans 1',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 150,
                            child: InkWell(
                              onTap: _pickDate,
                              borderRadius: BorderRadius.circular(10),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Tarih',
                                  suffixIcon:
                                      Icon(Icons.calendar_today, size: 16),
                                ),
                                child: Text(
                                  fmtDate(_date),
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      color: AppColors.text),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ruh Hali',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text2)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final m in _moods)
                                ChoiceChip(
                                  label: Text(m,
                                      style: const TextStyle(
                                          fontSize: 12.5)),
                                  selected: _mood == m,
                                  onSelected: (_) => setState(() => _mood = m),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _soapField('S — Öznel (Subjective)', _subjective,
                          'Danışanın anlattıkları, belirtiler...'),
                      const SizedBox(height: 12),
                      _soapField('O — Nesnel (Objective)', _objective,
                          'Gözlemleriniz, ölçülebilir bulgular...'),
                      const SizedBox(height: 12),
                      _soapField('A — Değerlendirme (Assessment)', _assessment,
                          'Klinik değerlendirme, ilerleme...'),
                      const SizedBox(height: 12),
                      _soapField('P — Plan (Plan)', _plan,
                          'Sonraki adımlar, ev ödevleri, yönlendirmeler...'),
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
                              const Icon(Icons.error_outline,
                                  size: 18, color: AppColors.danger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.danger),
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
                      onPressed: () async {
                        if (await _confirmDiscard()) _closeWith(false);
                      },
                      child: const Text('İptal',
                          style: TextStyle()),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('Kaydet',
                          style: TextStyle()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _soapField(String label, TextEditingController c, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.text2)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          maxLines: 3,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

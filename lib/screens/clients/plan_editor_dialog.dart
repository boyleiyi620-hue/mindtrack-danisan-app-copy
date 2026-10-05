import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../models/client.dart';
import '../../models/plan.dart';
import '../../theme/app_theme.dart';
import '../../utils/formats.dart';

/// Tedavi planı oluşturma / düzenleme penceresi (hedefler + müdahaleler).
class PlanEditorDialog extends StatefulWidget {
  const PlanEditorDialog({super.key, required this.data, required this.client, this.existing});

  final DataStore data;
  final Client client;
  final Plan? existing;

  @override
  State<PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<PlanEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _interventions;
  late final List<_GoalDraft> _goals;
  String? _error;
  bool _dirty = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _title = TextEditingController(text: p?.title ?? 'Tedavi Planı');
    _desc = TextEditingController(text: p?.description ?? '');
    _interventions = TextEditingController(
        text: (p?.interventions ?? []).join('\n'));
    for (final controller in [_title, _desc, _interventions]) {
      controller.addListener(_markDirty);
    }
    _goals = [
      for (final g in p?.goals ?? <Goal>[])
        _GoalDraft(
          id: g.id,
          text: g.text,
          category: g.category,
          status: g.status,
          targetDate: g.targetDate ?? '',
        ),
    ];
  }

  void _markDirty() {
    if (_dirty || !mounted) return;
    setState(() => _dirty = true);
  }

  void _closeWith(Object? result) {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Kaydedilmemiş değişiklik'),
            content: const Text(
              'Bu tedavi planında kaydedilmemiş değişiklikler var. Çıkarsanız '
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
        ) ??
        false;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _interventions.dispose();
    super.dispose();
  }

  Future<void> _pickDate(_GoalDraft g) async {
    final initial =
        DateTime.tryParse(g.targetDate.length >= 10 ? g.targetDate.substring(0, 10) : '');
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _dirty = true;
        g.targetDate = '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Plan başlığı gereklidir.');
      return;
    }
    _goals.removeWhere((g) => g.text.trim().isEmpty);
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final existing = widget.existing;
    final interventions = _interventions.text
        .split('\n')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList();
    if (existing != null) {
      existing.title = title;
      existing.description = _desc.text.trim();
      existing.interventions
        ..clear()
        ..addAll(interventions);
      existing.goals
        ..clear()
        ..addAll([
          for (var i = 0; i < _goals.length; i++)
            Goal(
              id: _goals[i].id,
              text: _goals[i].text,
              category: _goals[i].category,
              status: _goals[i].status,
              targetDate: _goals[i].targetDate,
            ),
        ]);
      existing.updatedAt = now;
    } else {
      widget.data.data.plans.add(Plan(
        id: widget.data.newId(),
        clientId: widget.client.id,
        title: title,
        description: _desc.text.trim(),
        interventions: interventions,
        goals: [
          for (var i = 0; i < _goals.length; i++)
            Goal(
              id: _goals[i].id,
              text: _goals[i].text,
              category: _goals[i].category,
              status: _goals[i].status,
              targetDate: _goals[i].targetDate,
            ),
        ],
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
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
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
                              ? 'Tedavi Planını Düzenle'
                              : 'Tedavi Planı Oluştur',
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.client.name} — hedefler ve müdahaleler',
                          style: const TextStyle(
                              fontSize: 12,
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
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: 'Plan Başlığı *',
                        hintText: 'Örn: Kaygı Yönetimi Planı',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _desc,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama',
                        hintText: 'Tanı, gerekçe, yaklaşım...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Hedefler',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => setState(() {
                            _dirty = true;
                            _goals.add(_GoalDraft(
                                id: widget.data.newId()));
                          }),
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text('Hedef Ekle',
                              style: TextStyle(
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_goals.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bg2.withValues(alpha: .4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border2),
                        ),
                        child: const Text(
                          'Henüz hedef eklenmedi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.muted),
                        ),
                      )
                    else
                      for (var i = 0; i < _goals.length; i++)
                        _goalCard(context, i),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _interventions,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText:
                            'Müdahaleler / Teknikler (her satıra bir tane)',
                        hintText: 'Bilişsel yeniden yapılandırma\nNefes egzersizleri',
                      ),
                    ),
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
                    label: const Text('Planı Kaydet',
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

  Widget _goalCard(BuildContext context, int i) {
    final g = _goals[i];
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
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Hedef',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text2)),
              const Spacer(),
              IconButton(
                tooltip: 'Sil',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _dirty = true;
                  _goals.removeAt(i);
                }),
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.danger),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: g.text,
            decoration: const InputDecoration(
              labelText: 'Hedefi yazın...',
              hintText: 'Örn: Haftada 3 kez 20 dk yürüyüş',
              isDense: true,
            ),
            onChanged: (v) => g.text = v,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: g.category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Vade',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'short', child: Text('Kısa Vade')),
                    DropdownMenuItem(
                        value: 'long', child: Text('Uzun Vade')),
                  ],
                  onChanged: (v) => setState(() {
                    _dirty = true;
                    g.category = v ?? 'short';
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: g.status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Durum',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'pending', child: Text('Bekliyor')),
                    DropdownMenuItem(
                        value: 'in_progress', child: Text('Devam Ediyor')),
                    DropdownMenuItem(
                        value: 'achieved', child: Text('Tamamlandı')),
                    DropdownMenuItem(
                        value: 'dropped', child: Text('Bırakıldı')),
                  ],
                  onChanged: (v) => setState(() {
                    _dirty = true;
                    g.status = v ?? 'pending';
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(g),
                  icon: const Icon(Icons.calendar_today, size: 15),
                  label: Text(
                    g.targetDate.isEmpty ? 'Tarih seç' : fmtIsoDate(g.targetDate),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalDraft {
  _GoalDraft({
    required this.id,
    this.text = '',
    this.category = 'short',
    this.status = 'pending',
    this.targetDate = '',
  });

  final String id;
  String text;
  String category;
  String status;
  String targetDate;
}

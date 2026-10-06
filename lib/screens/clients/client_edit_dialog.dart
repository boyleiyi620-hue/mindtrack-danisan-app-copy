import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/client_deduplication.dart';
import '../../data/diagnosis_codes.dart';
import '../../data/mindtrack_backend.dart';
import '../../models/client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/diagnosis_picker.dart';

/// Yeni danışan ekleme / mevcut danışanı düzenleme penceresi.
class ClientEditDialog extends StatefulWidget {
  const ClientEditDialog({super.key, required this.data, this.existing});

  final DataStore data;
  final Client? existing;

  @override
  State<ClientEditDialog> createState() => _ClientEditDialogState();
}

class _ClientEditDialogState extends State<ClientEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _sessionFee;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  String _birthDate = '';
  String _gender = '';
  String _status = 'active';
  late final List<String> _diagnosisCodes;
  String? _error;
  bool _saving = false;
  bool _dirty = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _sessionFee = TextEditingController(
      text: c != null
          ? c.sessionFee.toStringAsFixed(0)
          : (widget.data.accounts.current?.defaultSessionFee.toStringAsFixed(
                  0,
                ) ??
                '0'),
    );
    _tags = TextEditingController(text: (c?.tags ?? []).join(', '));
    _notes = TextEditingController(text: c?.notes ?? '');
    for (final controller in [_name, _email, _phone, _sessionFee, _tags, _notes]) {
      controller.addListener(_markDirty);
    }
    _birthDate = c?.birthDate ?? '';
    _gender = c?.gender ?? '';
    _status = c?.status ?? 'active';
    _diagnosisCodes = List.of(c?.diagnosisCodes ?? const <String>[]);
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
    if (!_dirty || _saving) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Kaydedilmemiş değişiklik'),
            content: const Text(
              'Bu danışan kaydında kaydedilmemiş değişiklikler var. Çıkarsanız '
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
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _sessionFee.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool _isEmail(String v) {
    final m = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return m.hasMatch(v);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(
      _birthDate.length >= 10 ? _birthDate.substring(0, 10) : '',
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dirty = true;
        _birthDate =
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (widget.data.deduplicateClientsByEmail()) widget.data.save();
    final name = _name.text.trim();
    final email = normalizeClientEmail(_email.text);
    if (name.isEmpty) {
      setState(() => _error = 'Danışan adı gereklidir.');
      return;
    }
    if (!_isEmail(email)) {
      setState(() => _error = 'Geçerli bir e-posta girin.');
      return;
    }
    Client? duplicate;
    for (final client in widget.data.data.clients) {
      if (client.id != widget.existing?.id &&
          normalizeClientEmail(client.email) == email) {
        duplicate = client;
        break;
      }
    }
    if (duplicate != null) {
      setState(() => _error =
          'Bu Gmail adresi zaten kayıtlı. Aynı e-posta ile ikinci danışan oluşturulamaz.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now().millisecondsSinceEpoch.toDouble();
      final existing = widget.existing;
      final tags = _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      final sessionFee = double.tryParse(_sessionFee.text.trim()) ?? 0.0;
      late final Client savedClient;
      if (existing != null) {
        savedClient = existing;
        existing.name = name;
        existing.email = email;
        existing.phone = _phone.text.trim();
        existing.birthDate = _birthDate;
        existing.gender = _gender;
        existing.sessionFee = sessionFee;
        existing.tags
          ..clear()
          ..addAll(tags);
        existing.notes = _notes.text.trim();
        existing.status = _status;
        existing.diagnosisCodes
          ..clear()
          ..addAll(_diagnosisCodes);
        existing.updatedAt = now;
      } else {
        savedClient = Client(
          id: widget.data.newId(),
          name: name,
          email: email,
          phone: _phone.text.trim(),
          birthDate: _birthDate,
          gender: _gender,
          sessionFee: sessionFee,
          tags: tags,
          diagnosisCodes: List.of(_diagnosisCodes),
          notes: _notes.text.trim(),
          status: _status,
        );
        widget.data.data.clients.add(savedClient);
      }
      widget.data.save();
      try {
        final backend = MindTrackBackend.instance;
        final uid = await backend.resolveClientUserId(savedClient);
        if (uid.isNotEmpty) {
          await backend.setDiagnosisCodes(
            uid,
            List<String>.of(savedClient.diagnosisCodes),
          );
        }
      } on BackendException catch (error) {
        if (mounted) {
          setState(
            () => _error =
                'Danışan kaydedildi ancak tanı kodu aktarılmadı: ${error.message}',
          );
        }
        return;
      }
      if (mounted) _closeWith(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDiagnosisCodes() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => DiagnosisCodePickerDialog(initialCodes: _diagnosisCodes),
    );
    if (result != null) {
      setState(() {
        _dirty = true;
        _diagnosisCodes
          ..clear()
          ..addAll(result);
      });
    }
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing != null
                          ? 'Danışanı Düzenle'
                          : 'Yeni Danışan',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
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
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Ad Soyad *',
                        hintText: 'Örn: Ahmet Yılmaz',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'E-posta *',
                              hintText: 'ornek@email.com',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Telefon',
                              hintText: '05XX XXX XXXX',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(10),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Doğum Tarihi',
                                suffixIcon: Icon(
                                  Icons.calendar_today,
                                  size: 17,
                                ),
                              ),
                              child: Text(
                                _birthDate.isEmpty ? 'Seçilmedi' : _birthDate,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _birthDate.isEmpty
                                      ? AppColors.muted
                                      : AppColors.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _gender,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Cinsiyet',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '',
                                child: Text('Belirtilmedi'),
                              ),
                              DropdownMenuItem(
                                value: 'Kadın',
                                child: Text('Kadın'),
                              ),
                              DropdownMenuItem(
                                value: 'Erkek',
                                child: Text('Erkek'),
                              ),
                              DropdownMenuItem(
                                value: 'Diğer',
                                child: Text('Diğer'),
                              ),
                              DropdownMenuItem(
                                value: 'Belirtmek istemiyorum',
                                child: Text('Belirtmek istemiyorum'),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _dirty = true;
                              _gender = v ?? '';
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sessionFee,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Seans Ücreti (₺)',
                              hintText: 'Örn: 500',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _tags,
                            decoration: const InputDecoration(
                              labelText: 'Etiketler',
                              hintText: 'Örn: kaygı, bireysel',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Durum',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('Aktif')),
                        DropdownMenuItem(
                          value: 'paused',
                          child: Text('Tedaviye Ara Verildi'),
                        ),
                        DropdownMenuItem(
                          value: 'archived',
                          child: Text('Arşivlendi'),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _dirty = true;
                        _status = v ?? 'active';
                      }),
                    ),
                    const SizedBox(height: 12),
                    _diagnosisSection(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Danışan hakkında notlar',
                        hintText: 'Danışan hakkında notlar...',
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
                    onPressed: () async {
                      if (await _confirmDiscard()) _closeWith(false);
                    },
                    child: const Text('İptal', style: TextStyle()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
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

  Widget _diagnosisSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: .24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Danışan Tanı Kodları',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickDiagnosisCodes,
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Tanı Kodu Ekle'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'DSM-5-TR / ICD-10-CM kataloğundan bu danışana atanacak kodları seçin.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          if (_diagnosisCodes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Henüz tanı kodu eklenmedi.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final code in _diagnosisCodes)
                    Tooltip(
                      message: _diagnosisLabel(code),
                      child: InputChip(
                        label: Text(code, style: const TextStyle(fontSize: 11)),
                        onDeleted: () =>
                            setState(() {
                              _dirty = true;
                              _diagnosisCodes.remove(code);
                            }),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _diagnosisLabel(String code) {
    for (final item in diagnosisCodes) {
      if (item.code == code) return item.display;
    }
    return code;
  }
}

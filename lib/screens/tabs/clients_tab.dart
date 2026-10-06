import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/mindtrack_backend.dart';
import '../../models/app_data.dart';
import '../../models/appointment.dart';
import '../../models/client.dart';
import '../../models/document.dart';
import '../../models/note.dart';
import '../../models/plan.dart';
import '../../models/finance.dart' as mt;
import '../../theme/app_theme.dart';
import '../../utils/formats.dart';
import '../clients/client_edit_dialog.dart';
import '../clients/note_editor_dialog.dart';
import '../clients/plan_editor_dialog.dart';
import '../pdfs/pdf_viewer_screen.dart';

const _maxClientDocumentBytes = 10 * 1024 * 1024;

/// Danışanlar — liste, danışan detayı, SOAP notları, tedavi planı, güvenlik planı.
class ClientsTab extends StatefulWidget {
  const ClientsTab({super.key, required this.data, this.onNavigate});

  final DataStore data;
  final ValueChanged<String>? onNavigate;

  @override
  State<ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<ClientsTab> {
  String _q = '';
  String _status = ''; // '' | active | paused | archived
  String? _clientId;
  String _sub = 'overview';

  AppData get _d => widget.data.data;

  @override
  Widget build(BuildContext context) {
    final client = _clientId == null ? null : _d.clientById(_clientId!);
    if (client == null) return _listView(context);
    return _detailView(context, client);
  }

  // ==================== LİSTE ====================
  Widget _listView(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final clients =
        _d.clients.where((c) {
          if (_status.isNotEmpty && (c.status == _status) == false)
            return false;
          if (q.isEmpty) return true;
          return c.name.toLowerCase().contains(q) ||
              c.email.toLowerCase().contains(q) ||
              c.phone.contains(q);
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    final active = _d.clients.where((c) => c.status != 'archived').length;
    final archived = _d.clients.where((c) => c.status == 'archived').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Danışanlar',
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
                        '${_d.clients.length} danışan · $active aktif · $archived arşivli',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  );
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _openClientEditor(context),
                        icon: const Icon(Icons.person_add_alt, size: 17),
                        label: const Text('Yeni Danışan', style: TextStyle()),
                      ),
                    ],
                  );
                  return compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            heading,
                            const SizedBox(height: 12),
                            actions,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: heading),
                            actions,
                          ],
                        );
                },
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'Danışan ara (ad, e-posta, telefon)...',
                  prefixIcon: const Icon(Icons.search, size: 19),
                  suffixIcon: _q.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _q = ''),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final chip in const [
                    ['', 'Tümü'],
                    ['active', 'Aktif'],
                    ['paused', 'Ara Verildi'],
                    ['archived', 'Arşiv'],
                  ])
                    ChoiceChip(
                      label: Text(
                        chip[1],
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      selected: _status == chip[0],
                      onSelected: (_) => setState(() => _status = chip[0]),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (_d.clients.isEmpty)
                _emptyClients(context)
              else if (clients.isEmpty)
                _searchEmpty()
              else
                for (final c in clients) _clientRow(context, c),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyClients(BuildContext context) {
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
                Icons.people_outline,
                size: 28,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Henüz Danışan Yok',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'İlk danışanınızı ekleyerek değerlendirme sürecine başlayın.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openClientEditor(context),
              icon: const Icon(Icons.person_add_alt, size: 17),
              label: const Text('İlk Danışanı Ekle', style: TextStyle()),
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
            'Bu filtreye uygun danışan bulunamadı',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.text2),
          ),
        ],
      ),
    );
  }

  Widget _clientRow(BuildContext context, Client c) {
    final last = _d.assessmentsOf(c.id).isEmpty
        ? null
        : _d.assessmentsOf(c.id).first;
    final lastNote = _d.notesOf(c.id).isEmpty ? null : _d.notesOf(c.id).first;
    final lastNoteDays = lastNote == null
        ? null
        : DateTime.now()
              .difference(
                DateTime.fromMillisecondsSinceEpoch(lastNote.date.toInt()),
              )
              .inDays;
    final upcoming = _d
        .appointmentsOf(c.id)
        .where(
          (a) => a.date.compareTo(todayIso()) >= 0 && a.status == 'planned',
        )
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: () => setState(() {
          _clientId = c.id;
          _sub = 'overview';
        }),
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: c.status == 'archived'
                  ? AppColors.warning.withValues(alpha: .18)
                  : AppColors.primarySoft,
              child: Text(
                c.initials,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.status == 'archived'
                      ? AppColors.warning
                      : AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      if (c.status != 'active') ...[
                        const SizedBox(width: 6),
                        _statusChip(c.status),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${c.email.isNotEmpty ? c.email : '-'}${c.phone.isNotEmpty ? ' · ${c.phone}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 3,
                    children: [
                      Text(
                        last != null
                            ? 'Son değerlendirme: ${fmtDate(DateTime.fromMillisecondsSinceEpoch(last.submittedAt.toInt()))}'
                            : 'Değerlendirme yok',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                      Text(
                        lastNote != null
                            ? 'Son seans: ${lastNoteDays == null || lastNoteDays < 0
                                  ? 'bugün'
                                  : lastNoteDays == 0
                                  ? 'bugün'
                                  : lastNoteDays == 1
                                  ? 'dün'
                                  : '$lastNoteDays gün önce'}'
                            : 'Seans notu yok',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                      if (upcoming > 0)
                        Text(
                          '$upcoming yaklaşan randevu',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Düzenle',
              visualDensity: VisualDensity.compact,
              onPressed: () => _openClientEditor(context, client: c),
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppColors.text2,
              ),
            ),
            IconButton(
              tooltip: 'Sil',
              visualDensity: VisualDensity.compact,
              onPressed: () => _confirmDeleteClient(context, c),
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final Color fg;
    final Color bg;
    if (status == 'archived') {
      fg = AppColors.warning;
      bg = AppColors.warningSoft;
    } else if (status == 'paused') {
      fg = AppColors.info;
      bg = AppColors.infoSoft;
    } else {
      fg = AppColors.success;
      bg = AppColors.successSoft;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        clientStatusLabel(status),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  // ==================== DETAY ====================
  Widget _detailView(BuildContext context, Client c) {
    final notes = _d.notesOf(c.id);
    final appts = _d.appointmentsOf(c.id);
    final plans = _d.plansOf(c.id);
    final docs = _d.documentsOf(c.id);
    final upcoming = appts
        .where(
          (a) => a.date.compareTo(todayIso()) >= 0 && a.status == 'planned',
        )
        .length;
    final done = appts.where((a) => a.status == 'done').length;
    final age = ageFromBirth(c.birthDate);

    const subs = <(String, IconData, String)>[
      ('overview', Icons.space_dashboard_outlined, 'Genel Bakış'),
      ('forms', Icons.assignment_outlined, 'Form Cevapları'),
      ('appointments', Icons.calendar_month_outlined, 'Randevular'),
      ('notes', Icons.note_alt_outlined, 'Seans Notları'),
      ('plan', Icons.track_changes_outlined, 'Tedavi Planı'),
      ('safety', Icons.shield_outlined, 'Güvenlik Planı'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _clientId = null),
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text('Danışanlar', style: TextStyle()),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, bc) {
                        final narrow = bc.maxWidth < 700;
                        final identity = Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: AppColors.primarySoft,
                              child: Text(
                                c.initials,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  if (c.status != 'active') ...[
                                    const SizedBox(height: 4),
                                    _statusChip(c.status),
                                  ],
                                  if (c.tags.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final t in c.tags)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.bg2,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              t,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.text2,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                        final actions = Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _openClientEditor(context, client: c),
                              icon: const Icon(Icons.edit_outlined, size: 15),
                              label: const Text(
                                'Düzenle',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: () =>
                                  widget.onNavigate?.call('appointments'),
                              icon: const Icon(Icons.event_available, size: 15),
                              label: const Text(
                                'Randevu',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openHomeworkDialog(context, c),
                              icon: const Icon(
                                Icons.assignment_outlined,
                                size: 15,
                              ),
                              label: const Text(
                                'Ödevler',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        );
                        return narrow
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  identity,
                                  const SizedBox(height: 12),
                                  actions,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  identity,
                                  const SizedBox(width: 12),
                                  actions,
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, bc) {
                        final wide = bc.maxWidth >= 760;
                        final info = [
                          ('E-posta', c.email.isNotEmpty ? c.email : '-'),
                          ('Telefon', c.phone.isNotEmpty ? c.phone : '-'),
                          (
                            'Doğum Tarihi',
                            c.birthDate.isNotEmpty
                                ? '${fmtIsoDate(c.birthDate)}${age != null ? ' ($age yaş)' : ''}'
                                : '-',
                          ),
                          ('Cinsiyet', c.gender.isNotEmpty ? c.gender : '-'),
                          (
                            'Seans Ücreti',
                            '₺${c.sessionFee.toStringAsFixed(2)}',
                          ),
                          ('Tamamlanan Seans', '$done seans'),
                          ('Bekleyen Randevu', '$upcoming adet'),
                        ];
                        return Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            for (final (k, v) in info)
                              SizedBox(
                                width: wide
                                    ? (bc.maxWidth - 32) / 3
                                    : (bc.maxWidth - 16) / 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      k,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      v,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (c.diagnosisCodes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: .24),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.local_hospital_outlined,
                        size: 19,
                        color: AppColors.primaryDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tanı Kodları',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final code in c.diagnosisCodes)
                                  Chip(
                                    label: Text(
                                      code,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in subs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(
                            s.$2,
                            size: 15,
                            color: _sub == s.$1
                                ? AppColors.primaryDark
                                : AppColors.muted,
                          ),
                          label: Text(
                            s.$3,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          selected: _sub == s.$1,
                          onSelected: (_) => setState(() => _sub = s.$1),
                          showCheckmark: false,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _subView(context, c, _sub, notes, appts, plans, docs),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subView(
    BuildContext context,
    Client c,
    String sub,
    List<Note> notes,
    List<Appointment> appts,
    List<Plan> plans,
    List<Document> docs,
  ) {
    switch (sub) {
      case 'appointments':
        return _appointmentsView(context, appts);
      case 'forms':
        return _clientFormResponses(c);
      case 'notes':
        return _notesView(context, c, notes);
      case 'plan':
        return _planView(context, c, plans);
      case 'safety':
        return _safetyView(context, c);
      default:
        return _overviewSubView(context, c, notes, plans, docs);
    }
  }

  Widget _clientFormResponses(Client client) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: MindTrackBackend.instance.watchPsychologistTasks(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _miniEmpty(Icons.error_outline, 'Form cevapları yüklenemedi');
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final email = client.email.trim().toLowerCase();
        final tasks = snapshot.data!.where((task) {
          final sameClient = task['clientId']?.toString() == client.id ||
              (email.isNotEmpty &&
                  task['clientEmail']?.toString().trim().toLowerCase() == email);
          final answers = task['structuredAnswers'];
          final hasAnswers = (answers is Map && answers.isNotEmpty) ||
              (task['response']?.toString().trim().isNotEmpty ?? false);
          return sameClient && hasAnswers;
        }).toList()
          ..sort((a, b) =>
              ((b['createdAtMs'] as num?)?.toInt() ?? 0).compareTo(
                (a['createdAtMs'] as num?)?.toInt() ?? 0,
              ));
        if (tasks.isEmpty) {
          return _miniEmpty(
            Icons.assignment_outlined,
            'Bu danışandan henüz form cevabı gelmedi.',
          );
        }
        return Column(
          children: [
            for (final task in tasks)
              _ClientFormAnswerTile(task: task),
          ],
        );
      },
    );
  }

  Widget _documentsSection(
    BuildContext context,
    Client client,
    List<Document> documents,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Danışan Belgeleri',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _uploadClientDocument(context, client),
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('PDF ekle'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (documents.isEmpty)
            const Text(
              'Bu danışana ait belge yok. Belgeler sunucuda saklanır ve yalnızca açıldığında indirilir.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            )
          else
            for (final document in documents)
              _clientDocumentTile(context, document),
        ],
      ),
    );
  }

  Widget _clientDocumentTile(BuildContext context, Document document) {
    final cached = widget.data.documentIsCached(document);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
      title: Text(
        document.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${fmtBytes(document.size)} · ${cached ? 'Bu cihazda hazır' : 'Açılınca indirilecek'}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Wrap(
        spacing: 0,
        children: [
          IconButton(
            tooltip: 'Aç',
            onPressed: () => _openClientDocument(context, document),
            icon: const Icon(Icons.visibility_outlined, size: 19),
          ),
          IconButton(
            tooltip: 'Sil',
            onPressed: () => _deleteClientDocument(context, document),
            icon: const Icon(
              Icons.delete_outline,
              size: 19,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadClientDocument(
    BuildContext context,
    Client client,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Danışan PDF belgesi seç',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (picked == null) return;
      final name = picked.name.trim().isEmpty ? 'belge.pdf' : picked.name.trim();
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty || !name.toLowerCase().endsWith('.pdf')) {
        messenger.showSnackBar(const SnackBar(content: Text('Yalnızca geçerli PDF dosyası eklenebilir.')));
        return;
      }
      if (bytes.length > _maxClientDocumentBytes) {
        messenger.showSnackBar(const SnackBar(content: Text('Dosya başına en fazla 10 MB olabilir.')));
        return;
      }
      _d.documents.add(Document(
        id: widget.data.newId(),
        clientId: client.id,
        name: name,
        size: bytes.length,
        dataUrl: 'data:application/pdf;base64,${base64Encode(bytes)}',
      ));
      widget.data.save();
      if (mounted) {
        setState(() {});
        messenger.showSnackBar(const SnackBar(content: Text('Danışan belgesi eklendi.')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Belge seçilemedi.')));
      }
    }
  }

  Future<void> _openClientDocument(
    BuildContext context,
    Document document,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!widget.data.documentIsCached(document) && document.storagePath.isNotEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Belge indiriliyor…')));
    }
    final bytes = await widget.data.documentBytes(document);
    if (!mounted) return;
    if (bytes.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Belge indirilemedi. Bağlantınızı kontrol edin.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PdfViewerScreen(name: document.name, bytes: bytes),
    ));
  }

  Future<void> _deleteClientDocument(
    BuildContext context,
    Document document,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Belge silinsin mi?'),
        content: Text('“${document.name}” silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _d.documents.removeWhere((item) => item.id == document.id);
    widget.data.save();
    unawaited(widget.data.purgeBlobs([document.storagePath]));
    if (mounted) setState(() {});
  }

  // ---- Genel Bakış (danışan) ----
  Widget _overviewSubView(
    BuildContext context,
    Client c,
    List<Note> notes,
    List<Plan> plans,
    List<Document> docs,
  ) {
    final latestNote = notes.isEmpty ? null : notes.first;
    return LayoutBuilder(
      builder: (context, bc) {
        final wide = bc.maxWidth >= 760;
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _documentsSection(context, c, docs),
            const SizedBox(height: 12),
            if (widget.data.accounts.current?.appMode == 'commercial') ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: .2)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      size: 19,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Hızlı Tahsilat',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          Text(
                            'Seans ücreti: ₺${c.sessionFee.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: () => _quickCollect(context, c),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text(
                        'Ödeme Al',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg2.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 19,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Güvenlik Planı ${c.hasSafety ? '' : 'yok'}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _sub = 'safety'),
                    child: const Text(
                      'Düzenle',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final right = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panelTitle('Son Seans Notu', 'notes'),
            const SizedBox(height: 8),
            if (latestNote == null)
              _miniEmpty(Icons.note_alt_outlined, 'Seans notu yok')
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            latestNote.title.isNotEmpty
                                ? latestNote.title
                                : 'Seans Notu',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        Text(
                          fmtDate(
                            DateTime.fromMillisecondsSinceEpoch(
                              latestNote.date.toInt(),
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      latestNote.plan.isNotEmpty
                          ? latestNote.plan
                          : latestNote.subjective.isNotEmpty
                          ? latestNote.subjective
                          : latestNote.assessment.isNotEmpty
                          ? latestNote.assessment
                          : latestNote.objective,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            if (plans.isNotEmpty) ...[
              const SizedBox(height: 16),
              _panelTitle('Tedavi Planı Özeti', 'plan'),
              const SizedBox(height: 8),
              _planProgress(plans),
            ],
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
        return Column(children: [left, const SizedBox(height: 16), right]);
      },
    );
  }

  Widget _panelTitle(String title, String sub) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _sub = sub),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tümü', style: TextStyle()),
              SizedBox(width: 2),
              Icon(Icons.arrow_forward, size: 14),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniEmpty(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bg2.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.muted),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  // ---- Randevular ----
  Widget _appointmentsView(BuildContext context, List<Appointment> appts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (appts.isEmpty)
          _miniEmpty(Icons.calendar_month_outlined, 'Randevu bulunmuyor')
        else
          for (final a in appts) _apptRow(context, a),
      ],
    );
  }

  Widget _apptRow(BuildContext context, Appointment a) {
    final today = todayIso();
    final completed = a.status == 'done';
    final gone = a.status == 'noshow';
    final planned = a.status == 'planned';
    final isTodayOrPast = a.date.compareTo(today) <= 0;
    final dur = a.durationMin > 0 ? '${a.durationMin} dk' : '50 dk';
    final noteTxt = a.notes.isNotEmpty ? ' · ${a.notes}' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color:
                  (completed
                          ? AppColors.success
                          : gone
                          ? AppColors.danger
                          : AppColors.warning)
                      .withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              completed
                  ? Icons.check_circle
                  : gone
                  ? Icons.cancel
                  : Icons.schedule,
              size: 17,
              color: completed
                  ? AppColors.success
                  : gone
                  ? AppColors.danger
                  : AppColors.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtDate(DateTime.parse(a.date))}${a.date == today ? ' · Bugün' : ''} · ${fmtTime(a.time)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${apptTypeLabel(a.type)} · $dur$noteTxt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          _chip(apptStatusLabel(a.status), completed, gone),
          if (planned && isTodayOrPast) ...[
            IconButton(
              tooltip: 'Tamamlandı',
              visualDensity: VisualDensity.compact,
              onPressed: () => _setAppointmentStatus(context, a, 'done'),
              icon: const Icon(
                Icons.check_circle_outline,
                size: 19,
                color: AppColors.success,
              ),
            ),
            IconButton(
              tooltip: 'Gelmedi',
              visualDensity: VisualDensity.compact,
              onPressed: () => _setAppointmentStatus(context, a, 'noshow'),
              icon: const Icon(
                Icons.cancel_outlined,
                size: 19,
                color: AppColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setAppointmentStatus(
    BuildContext context,
    Appointment appointment,
    String status,
  ) async {
    try {
      await widget.data.updateAppointmentStatus(appointment, status);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Randevu durumu sunucuda güncellenemedi. Lütfen tekrar deneyin.',
              style: TextStyle(),
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Widget _chip(String label, bool completed, bool gone) {
    final Color fg;
    final Color bg;
    if (completed) {
      fg = AppColors.success;
      bg = AppColors.successSoft;
    } else if (gone) {
      fg = AppColors.danger;
      bg = AppColors.dangerSoft;
    } else {
      fg = AppColors.muted;
      bg = AppColors.bg2;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  // ---- SOAP notları ----
  Widget _notesView(BuildContext context, Client c, List<Note> notes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _openNoteEditor(context, c),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Seans Notu Ekle', style: TextStyle()),
          ),
        ),
        const SizedBox(height: 12),
        if (notes.isEmpty)
          _miniEmpty(
            Icons.note_alt_outlined,
            'Henüz seans notu yok. Seans sonrası SOAP notlarınızı buradan tutabilirsiniz.',
          )
        else
          for (final n in notes) _noteCard(context, c, n),
      ],
    );
  }

  Widget _noteCard(BuildContext context, Client c, Note n) {
    final sections = <(String, String)>[
      if (n.subjective.isNotEmpty) ('S — Öznel', n.subjective),
      if (n.objective.isNotEmpty) ('O — Nesnel', n.objective),
      if (n.assessment.isNotEmpty) ('A — Değerlendirme', n.assessment),
      if (n.plan.isNotEmpty) ('P — Plan', n.plan),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  n.title.isNotEmpty ? n.title : 'Seans Notu',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (n.mood.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successSoft,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    n.mood,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Düzenle',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openNoteEditor(context, c, note: n),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 17,
                  color: AppColors.text2,
                ),
              ),
              IconButton(
                tooltip: 'Sil',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmDeleteNote(context, n),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 17,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          Text(
            fmtDateTime(n.date),
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          for (final (k, v) in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    k,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    v,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.text2,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- Tedavi planı ----
  Widget _planView(BuildContext context, Client c, List<Plan> plans) {
    final plan = plans.isEmpty ? null : plans.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _openPlanEditor(context, c, plan: plan),
            icon: Icon(
              plan == null ? Icons.add : Icons.edit_outlined,
              size: 16,
            ),
            label: Text(
              plan == null ? 'Plan Oluştur' : 'Planı Düzenle',
              style: const TextStyle(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (plan == null)
          _miniEmpty(
            Icons.track_changes_outlined,
            'Danışanınız için hedefler ve müdahaleler belirleyin.',
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                if (plan.description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    plan.description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.text2,
                    ),
                  ),
                ],
                if (plan.interventions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final i in plan.interventions)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.infoSoft,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            i,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _goalList(plan),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _goalList(Plan plan) {
    if (plan.goals.isEmpty) {
      return _miniEmpty(Icons.flag_outlined, 'Henüz hedef eklenmedi');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in plan.goals)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.bg2.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  g.status == 'achieved'
                      ? Icons.check_circle
                      : g.status == 'dropped'
                      ? Icons.cancel
                      : g.status == 'in_progress'
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color: g.status == 'achieved'
                      ? AppColors.success
                      : g.status == 'dropped'
                      ? AppColors.danger
                      : g.status == 'in_progress'
                      ? AppColors.info
                      : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.text,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: g.status == 'achieved'
                              ? AppColors.muted
                              : AppColors.text,
                          decoration: g.status == 'achieved'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _goalChip(
                            goalCategoryLabel(g.category),
                            AppColors.primaryDark,
                            AppColors.primarySoft,
                          ),
                          _goalChip(
                            goalStatusLabel(g.status),
                            _statusColor(g.status),
                            _statusBg(g.status),
                          ),
                          if (g.targetDate != null && g.targetDate!.isNotEmpty)
                            Text(
                              'Hedef: ${fmtIsoDate(g.targetDate!)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'achieved':
        return AppColors.success;
      case 'in_progress':
        return AppColors.info;
      case 'dropped':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'achieved':
        return AppColors.successSoft;
      case 'in_progress':
        return AppColors.infoSoft;
      case 'dropped':
        return AppColors.dangerSoft;
      default:
        return AppColors.warningSoft;
    }
  }

  Widget _goalChip(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _planProgress(List<Plan> plans) {
    final goals = [for (final p in plans) ...p.goals];
    final counts = <String, int>{
      'pending': 0,
      'in_progress': 0,
      'achieved': 0,
      'dropped': 0,
    };
    for (final g in goals) {
      counts[g.status] = (counts[g.status] ?? 0) + 1;
    }
    final total = goals.length;
    final pct = total == 0
        ? 0.0
        : (counts['achieved']! / total * 100).clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _goalChip(
                '${counts['pending']} Bekliyor',
                AppColors.warning,
                AppColors.warningSoft,
              ),
              _goalChip(
                '${counts['in_progress']} Devam Ediyor',
                AppColors.info,
                AppColors.infoSoft,
              ),
              _goalChip(
                '${counts['achieved']} Tamamlandı',
                AppColors.success,
                AppColors.successSoft,
              ),
              _goalChip(
                '${counts['dropped']} Bırakıldı',
                AppColors.muted,
                AppColors.bg2,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 9,
              backgroundColor: AppColors.bg2,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            total == 0 ? 'Henüz hedef yok' : 'Tamamlanma: %${pct.round()}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  // ---- Güvenlik planı ----
  Widget _safetyView(BuildContext context, Client c) {
    return LayoutBuilder(
      builder: (context, bc) {
        final wide = bc.maxWidth >= 760;
        final form = SafeArea(
          top: false,
          child: _SafetyForm(
            key: ValueKey('safety-${c.id}-$_sub'),
            client: c,
            data: widget.data,
          ),
        );
        final info = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.infoSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCFE3F2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Acil Durum Hatları',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(height: 10),
              for (final line in const [
                '112 — Acil Sağlık (AMBULANS)',
                '155 — Polis İmdat',
                '156 — Jandarma',
                '183 — Aile, Kadın, Çocuk ve Engelli Sosyal Hizmet Danışma Hattı',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.text2,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              const Text(
                'Kriz anında danışana bu numaraları hatırlatın; ciddi riskte acil servise yönlendirin.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: form),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: info),
            ],
          );
        }
        return Column(children: [form, const SizedBox(height: 16), info]);
      },
    );
  }

  // ==================== DİYALOGLAR / AKSİYONLAR ====================
  Future<void> _openClientEditor(BuildContext context, {Client? client}) async {
    final messenger = ScaffoldMessenger.of(context);
    final beforeIds = _d.clients.map((c) => c.id).toSet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClientEditDialog(data: widget.data, existing: client),
    );
    if (ok == true) {
      Client? created;
      if (client == null) {
        for (final candidate in _d.clients) {
          if (!beforeIds.contains(candidate.id)) {
            created = candidate;
            break;
          }
        }
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              client == null ? 'Danışan eklendi.' : 'Danışan güncellendi.',
              style: const TextStyle(),
            ),
          ),
        );
      if (created != null && mounted) {
        await _openPairingCodeDialog(context, client: created);
      }
    }
  }

  Future<void> _openNoteEditor(
    BuildContext context,
    Client c, {
    Note? note,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          NoteEditorDialog(data: widget.data, clientId: c.id, existing: note),
    );
    if (ok == true) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              note == null ? 'Seans notu eklendi.' : 'Seans notu güncellendi.',
              style: const TextStyle(),
            ),
          ),
        );
    }
  }

  Future<void> _openPlanEditor(
    BuildContext context,
    Client c, {
    Plan? plan,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          PlanEditorDialog(data: widget.data, client: c, existing: plan),
    );
    if (ok == true) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              plan == null
                  ? 'Tedavi planı kaydedildi.'
                  : 'Tedavi planı güncellendi.',
              style: const TextStyle(),
            ),
          ),
        );
    }
  }

  Future<void> _confirmDeleteNote(BuildContext context, Note n) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notu sil', style: TextStyle()),
        content: Text(
          '"${n.title.isEmpty ? 'Seans Notu' : n.title}" kalıcı olarak silinsin mi?',
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
            child: const Text('Sil', style: TextStyle()),
          ),
        ],
      ),
    );
    if (ok == true) {
      _d.notes.removeWhere((x) => x.id == n.id);
      widget.data.save();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Not silindi.', style: TextStyle())),
        );
    }
  }

  Future<void> _openHomeworkDialog(BuildContext context, Client c) async {
    final ready = await _ensureBackendSession(context);
    if (!ready || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${c.name} · Ödevler', style: const TextStyle()),
        content: SizedBox(
          width: 520,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: MindTrackBackend.instance.watchHomework(),
            builder: (ctx, snap) {
              if (snap.hasError) {
                return Text(
                  'Ödevler yüklenemedi: ${snap.error}',
                  style: const TextStyle(),
                );
              }
              if (!snap.hasData) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final items =
                  snap.data!.where((d) => d['clientId'] == c.id).toList()..sort(
                    (a, b) => ((b['createdAtMs'] as num?)?.toInt() ?? 0)
                        .compareTo((a['createdAtMs'] as num?)?.toInt() ?? 0),
                  );
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Bu danışana henüz ödev verilmedi.'),
                );
              }
              return SizedBox(
                height: 300,
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = items[i];
                    final response = (d['response'] ?? '').toString().trim();
                    final status = (d['status'] ?? 'assigned').toString();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (d['title'] ?? 'Ödev').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        response.isEmpty
                            ? 'Yanıt bekleniyor · $status'
                            : 'Yanıt: $response',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: response.isEmpty
                          ? const Icon(Icons.hourglass_empty, size: 18)
                          : const Icon(
                              Icons.check_circle_outline,
                              color: AppColors.primary,
                              size: 19,
                            ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat', style: TextStyle()),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await _createHomework(context, c);
            },
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Yeni Ödev', style: TextStyle()),
          ),
        ],
      ),
    );
  }

  Future<void> _createHomework(BuildContext context, Client c) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${c.name} için ödev', style: const TextStyle()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Ödev başlığı'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Açıklama / yönerge',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gönder', style: TextStyle()),
          ),
        ],
      ),
    );
    final titleValue = title.text.trim();
    final descriptionValue = description.text.trim();
    title.dispose();
    description.dispose();
    if (result != true || titleValue.isEmpty) return;
    try {
      await MindTrackBackend.instance.assignHomework(
        clientRef: c.id,
        clientUid: c.clientUserId,
        clientEmail: c.email,
        title: titleValue,
        description: descriptionValue,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ödev danışana gönderildi.', style: TextStyle()),
          ),
        );
      }
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ödev gönderilemedi: ${e.message}',
              style: const TextStyle(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openPairingCodeDialog(
    BuildContext context, {
    Client? client,
  }) async {
    final ready = await _ensureBackendSession(context);
    if (!ready) return;
    final code = await MindTrackBackend.instance.createPairingCode(
      psychologistEmail: widget.data.accounts.current?.email ?? '',
      clientRef: client?.id ?? '',
      clientName: client?.name ?? '',
      clientEmail: client?.email ?? '',
      clientUid: client?.clientUserId ?? '',
      diagnosisCodes: List<String>.of(
        client?.diagnosisCodes ?? const <String>[],
      ),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Danışan eşleşme kodu', style: TextStyle()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (client != null) ...[
              Text(
                client.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
            ],
            const Text(
              'Bu kodu danışana verin:',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kod 7 gün geçerlidir.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat', style: TextStyle()),
          ),
        ],
      ),
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
          const SnackBar(
            content: Text('Önce hesabınızla giriş yapın.', style: TextStyle()),
          ),
        );
      }
      return false;
    }
    // Diyalog kendi denetleyicisini sahiplenir; `showDialog` dönüşünü
    // hemen dispose etmek, kapanış animasyonu sürerken hâlâ çalışan
    // TextField'i "kullanılmış controller" hatasına yol açıyordu.
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => _LinkAccountDialog(email: email),
    );
    if (password == null || password.isEmpty) return false;
    try {
      await backend.signIn(email, password);
      return true;
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Oturum açılamadı: ${e.message}',
              style: const TextStyle(),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _confirmDeleteClient(BuildContext context, Client c) async {
    final nA = _d.assessmentsOf(c.id).length;
    final nN = _d.notesOf(c.id).length;
    final nP = _d.plansOf(c.id).length;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Danışanı sil', style: TextStyle()),
        content: Text(
          '"${c.name}" ve kayıtlı tüm verileri silinecek:\n• $nA değerlendirme\n• $nN seans notu\n• $nP tedavi planı\n\nBu işlem geri alınamaz.',
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
      final documentPaths = _d.documents
          .where((x) => x.clientId == c.id)
          .map((x) => x.storagePath)
          .where((path) => path.isNotEmpty)
          .toList();
      _d.clients.removeWhere((x) => x.id == c.id);
      _d.assessments.removeWhere((x) => x.clientId == c.id);
      _d.appointments.removeWhere((x) => x.clientId == c.id);
      _d.notes.removeWhere((x) => x.clientId == c.id);
      _d.plans.removeWhere((x) => x.clientId == c.id);
      _d.documents.removeWhere((x) => x.clientId == c.id);
      unawaited(widget.data.purgeBlobs(documentPaths));
      if (_clientId == c.id) _clientId = null;
      widget.data.save();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Danışan ve tüm kayıtları silindi.',
              style: TextStyle(),
            ),
          ),
        );
    }
  }

  void _quickCollect(BuildContext context, Client c) {
    final amount = c.sessionFee > 0 ? c.sessionFee : 0.0;
    final controller = TextEditingController(
      text: amount > 0 ? amount.toStringAsFixed(0) : '',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ödeme Al'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.name} için seans ödemesi kaydedilsin mi?'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tutar (₺)',
                prefixText: '₺ ',
                hintText: 'Örn: 500',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () {
              final newAmt = double.tryParse(controller.text.trim()) ?? 0.0;
              _executeQuickCollect(context, c, newAmt);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _executeQuickCollect(BuildContext context, Client c, double amount) {
    final tx = mt.Transaction(
      id: widget.data.newId(),
      clientId: c.id,
      amount: amount,
      date: todayIso(),
      type: 'income',
      category: 'Seans',
      notes: 'Danışan kartından hızlı tahsilat',
    );
    setState(() => widget.data.data.transactions.add(tx));
    widget.data.save();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ödeme başarıyla kaydedildi.')),
    );
  }
}

class _ClientFormAnswerTile extends StatelessWidget {
  const _ClientFormAnswerTile({required this.task});

  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final draft = task['formDraft'] is Map
        ? Map<String, dynamic>.from(task['formDraft'] as Map)
        : <String, dynamic>{};
    final questions = draft['questions'] is List
        ? (draft['questions'] as List)
        : const <dynamic>[];
    final answers = task['structuredAnswers'] is Map
        ? Map<String, dynamic>.from(task['structuredAnswers'] as Map)
        : <String, dynamic>{};
    final submittedAt = (task['createdAtMs'] as num?)?.toInt();
    final date = submittedAt == null
        ? ''
        : fmtDate(DateTime.fromMillisecondsSinceEpoch(submittedAt));

    String display(Object? value) {
      if (value == null) return '—';
      if (value is List) return value.map((item) => item.toString()).join(', ');
      if (value is bool) return value ? 'Evet' : 'Hayır';
      final text = value.toString().trim();
      return text.isEmpty ? '—' : text;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.assignment_turned_in_outlined),
        title: Text(
          (task['title'] ?? draft['title'] ?? 'Form').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(date.isEmpty ? 'Cevaplandı' : 'Cevaplandı · $date'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (var i = 0; i < questions.length; i++)
            if (questions[i] is Map) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  (questions[i]['text'] ?? 'Soru ${i + 1}').toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  display(answers[questions[i]['id']?.toString()]),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          if ((task['response']?.toString().trim().isNotEmpty ?? false))
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                task['response'].toString(),
                style: const TextStyle(color: AppColors.text),
              ),
            ),
        ],
      ),
    );
  }
}

/// Güvenlik planı formu — kaydet butonuyla birlikte.
class _SafetyForm extends StatefulWidget {
  const _SafetyForm({super.key, required this.client, required this.data});

  final Client client;
  final DataStore data;

  @override
  State<_SafetyForm> createState() => _SafetyFormState();
}

class _SafetyFormState extends State<_SafetyForm> {
  late final TextEditingController _warnings;
  late final TextEditingController _coping;
  late final TextEditingController _contacts;
  late final TextEditingController _emergency;

  @override
  void initState() {
    super.initState();
    final s = widget.client.safety;
    _warnings = TextEditingController(text: s?.warnings ?? '');
    _coping = TextEditingController(text: s?.coping ?? '');
    _contacts = TextEditingController(text: s?.contacts ?? '');
    _emergency = TextEditingController(text: s?.emergency ?? '');
  }

  @override
  void dispose() {
    _warnings.dispose();
    _coping.dispose();
    _contacts.dispose();
    _emergency.dispose();
    super.dispose();
  }

  void _save() {
    final c = widget.client;
    final s = c.safety ?? SafetyPlan();
    s.warnings = _warnings.text.trim();
    s.coping = _coping.text.trim();
    s.contacts = _contacts.text.trim();
    s.emergency = _emergency.text.trim();
    s.updatedAt = DateTime.now().millisecondsSinceEpoch.toDouble();
    c.safety = s;
    c.updatedAt = DateTime.now().millisecondsSinceEpoch.toDouble();
    widget.data.save();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Güvenlik planı kaydedildi.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Kriz / Güvenlik Planı',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Kriz anlarına hazırlık için danışanla birlikte doldurun.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          _field(
            'Uyarı işaretleri — danışanı riskli hissettiren belirtiler',
            _warnings,
            'Örn: İçine kapanma, uyku bozukluğu, umutsuzluk...',
            3,
          ),
          const SizedBox(height: 10),
          _field(
            'Baş etme stratejileri — işe yarayan rahatlatıcı yöntemler',
            _coping,
            'Örn: Nefes egzersizi, güvendiği kişiyle konuşmak...',
            3,
          ),
          const SizedBox(height: 10),
          _field(
            'Destek kişileri — ad ve telefon (her satıra biri)',
            _contacts,
            'Örn: Ayşe (anne) — 05XX XXX XX XX',
            3,
          ),
          const SizedBox(height: 10),
          _field(
            'Acil durum notları',
            _emergency,
            'Hastane tercihi, ilaçlar, alerjiler, özel durumlar...',
            2,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Güvenlik Planını Kaydet'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint, int lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.text2,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          maxLines: lines,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

/// Hesabı bağlama parola istem diyalogğ. Denetleyiciyi kendi `dispose`
/// yaşamında yok eder; böylece kapanış animasyonu boyunca TextField
/// hâlâ kullanılır durumda kalmaz.
class _LinkAccountDialog extends StatefulWidget {
  const _LinkAccountDialog({required this.email});

  final String email;

  @override
  State<_LinkAccountDialog> createState() => _LinkAccountDialogState();
}

class _LinkAccountDialogState extends State<_LinkAccountDialog> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_password.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hesabını bağla', style: TextStyle()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.email} hesabıyla oturum açılacak.',
            style: const TextStyle(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Hesap şifresi'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç', style: TextStyle()),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Bağlan', style: TextStyle()),
        ),
      ],
    );
  }
}

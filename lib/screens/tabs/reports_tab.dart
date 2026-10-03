import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/mindtrack_backend.dart';
import '../../models/appointment.dart';
import '../../models/assessment.dart';
import '../../models/client.dart';
import '../../models/note.dart';
import '../../models/plan.dart';
import '../../theme/app_theme.dart';
import '../../utils/formats.dart';
import '../settings/data_io.dart';

/// Patron/yönetim paylaşımı için seçili dönem randevu raporu.
///
/// Rapor, uygulamanın aynı renk paletini kullanır ve tek dosyalık HTML olarak
/// indirilir; tarayıcıda açılıp yazdırılabilir veya PDF olarak kaydedilebilir.
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key, required this.data});

  final DataStore data;

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  _ReportRange _range = _ReportRange.month;
  DateTime _anchor = DateTime.now();
  bool _exporting = false;
  List<Map<String, dynamic>> _tasks = const [];

  List<Client> get _clients => widget.data.data.clients.where((client) {
    final date = DateTime.fromMillisecondsSinceEpoch(client.createdAt.toInt());
    return !date.isBefore(_periodStart) && date.isBefore(_periodEndExclusive);
  }).toList()..sort((a, b) => a.name.compareTo(b.name));

  List<Note> get _notes => widget.data.data.notes.where((note) {
    final date = DateTime.fromMillisecondsSinceEpoch(note.date.toInt());
    return !date.isBefore(_periodStart) && date.isBefore(_periodEndExclusive);
  }).toList()..sort((a, b) => b.date.compareTo(a.date));

  List<Assessment> get _assessments =>
      widget.data.data.assessments.where((assessment) {
        final date = DateTime.fromMillisecondsSinceEpoch(
          assessment.submittedAt.toInt(),
        );
        return !date.isBefore(_periodStart) && date.isBefore(_periodEndExclusive);
      }).toList()..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

  List<Plan> get _plans => widget.data.data.plans.where((plan) {
    final updated = DateTime.fromMillisecondsSinceEpoch(plan.updatedAt.toInt());
    return !updated.isBefore(_periodStart) && updated.isBefore(_periodEndExclusive);
  }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<Map<String, dynamic>> get _periodTasks => _tasks.where((task) {
    final timestamp = (task['createdAtMs'] as num?)?.toInt();
    if (timestamp == null || timestamp <= 0) return false;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return !date.isBefore(_periodStart) && date.isBefore(_periodEndExclusive);
  }).toList()..sort((a, b) =>
      ((b['createdAtMs'] as num?)?.toInt() ?? 0).compareTo(
        (a['createdAtMs'] as num?)?.toInt() ?? 0,
      ));

  List<Appointment> get _appointments {
    final start = _periodStart;
    final end = _periodEndExclusive;
    final items =
        widget.data.data.appointments.where((appointment) {
          final date = DateTime.tryParse(appointment.date);
          return date != null && !date.isBefore(start) && date.isBefore(end);
        }).toList()..sort((a, b) {
          final date = a.date.compareTo(b.date);
          return date != 0 ? date : a.time.compareTo(b.time);
        });
    return items;
  }

  DateTime get _periodStart {
    final day = DateTime(_anchor.year, _anchor.month, _anchor.day);
    if (_range == _ReportRange.month) return DateTime(day.year, day.month);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  DateTime get _periodEndExclusive {
    final start = _periodStart;
    return _range == _ReportRange.month
        ? DateTime(start.year, start.month + 1)
        : start.add(const Duration(days: 7));
  }

  String get _periodLabel {
    if (_range == _ReportRange.month) return _monthLabel(_periodStart);
    final end = _periodEndExclusive.subtract(const Duration(days: 1));
    return '${_shortDate(_periodStart)} – ${_shortDate(end)}';
  }

  void _movePeriod(int direction) {
    setState(() {
      _anchor = _range == _ReportRange.month
          ? DateTime(_anchor.year, _anchor.month + direction, 1)
          : _anchor.add(Duration(days: direction * 7));
    });
  }

  Future<void> _pickAnchor() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: _range == _ReportRange.month
          ? 'Rapora dahil edilecek aydan bir gün seçin'
          : 'Rapora dahil edilecek haftadan bir gün seçin',
    );
    if (picked != null) setState(() => _anchor = picked);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: MindTrackBackend.instance.watchPsychologistTasks(),
      builder: (context, snapshot) {
        if (snapshot.hasData) _tasks = snapshot.data!;
        return _buildReport();
      },
    );
  }

  Widget _buildReport() {
    final appointments = _appointments;
    final metrics = _ReportMetrics.from(appointments);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 18),
              _periodControls(),
              const SizedBox(height: 18),
              _metricsGrid(metrics),
              const SizedBox(height: 18),
              _appointmentsCard(appointments, metrics),
              const SizedBox(height: 16),
              _clientsCard(),
              const SizedBox(height: 16),
              _formsCard(),
              const SizedBox(height: 16),
              _notesCard(),
              const SizedBox(height: 16),
              _assessmentsCard(),
              const SizedBox(height: 16),
              _plansCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final title = const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detaylı Raporlar',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Seçtiğiniz hafta veya ay içindeki randevuları, danışan ve durum bilgileriyle yönetime sunun.',
              style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ],
        );
        final action = FilledButton.icon(
          onPressed: _exporting ? null : _exportHtml,
          icon: _exporting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.ios_share_outlined, size: 17),
          label: Text(_exporting ? 'Hazırlanıyor...' : 'Raporu İndir'),
        );
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [title, const SizedBox(height: 14), action],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  action,
                ],
              );
      },
    );
  }

  Widget _periodControls() {
    return _card(
      icon: Icons.date_range_outlined,
      title: 'Rapor Dönemi',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final rangeSelector = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Haftalık'),
                selected: _range == _ReportRange.week,
                onSelected: (_) => setState(() => _range = _ReportRange.week),
                showCheckmark: false,
              ),
              ChoiceChip(
                label: const Text('Aylık'),
                selected: _range == _ReportRange.month,
                onSelected: (_) => setState(() => _range = _ReportRange.month),
                showCheckmark: false,
              ),
            ],
          );
          final navigator = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.outlined(
                tooltip: 'Önceki dönem',
                onPressed: () => _movePeriod(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickAnchor,
                icon: const Icon(Icons.calendar_month_outlined, size: 16),
                label: Text(_periodLabel),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Sonraki dönem',
                onPressed: () => _movePeriod(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    rangeSelector,
                    const SizedBox(height: 14),
                    navigator,
                  ],
                )
              : Row(children: [rangeSelector, const Spacer(), navigator]);
        },
      ),
    );
  }

  Widget _metricsGrid(_ReportMetrics metrics) {
    final metricsList = <_MetricItem>[
      _MetricItem(
        Icons.event_available_outlined,
        'Toplam Randevu',
        metrics.total,
        AppColors.primary,
      ),
      _MetricItem(
        Icons.people_outline,
        'Tekil Danışan',
        metrics.uniqueClients,
        AppColors.info,
      ),
      _MetricItem(
        Icons.check_circle_outline,
        'Tamamlanan',
        metrics.done,
        AppColors.success,
      ),
      _MetricItem(
        Icons.schedule_outlined,
        'Planlanan',
        metrics.planned,
        AppColors.warning,
      ),
      _MetricItem(
        Icons.event_busy_outlined,
        'İptal / Gelmedi',
        metrics.cancelled + metrics.noShow,
        AppColors.danger,
      ),
      _MetricItem(
        Icons.person_add_alt_outlined,
        'Dönemde Eklenen Danışan',
        _clients.length,
        AppColors.info,
      ),
      _MetricItem(
        Icons.assignment_outlined,
        'Gönderilen Form / Ödev',
        _periodTasks.length,
        AppColors.primary,
      ),
      _MetricItem(
        Icons.task_alt_outlined,
        'Cevaplanan Form / Ödev',
        _periodTasks.where((t) => t['done'] == true).length,
        AppColors.success,
      ),
      _MetricItem(
        Icons.note_alt_outlined,
        'Seans Notu',
        _notes.length,
        AppColors.warning,
      ),
      _MetricItem(
        Icons.fact_check_outlined,
        'Tamamlanan Değerlendirme',
        _assessments.length,
        AppColors.info,
      ),
      _MetricItem(
        Icons.track_changes_outlined,
        'Güncellenen Tedavi Planı',
        _plans.length,
        AppColors.primary,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 5
            : constraints.maxWidth >= 620
            ? 3
            : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in metricsList)
              SizedBox(width: width, child: _metricCard(item)),
          ],
        );
      },
    );
  }

  Widget _metricCard(_MetricItem item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, size: 20, color: item.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.value}',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _appointmentsCard(
    List<Appointment> appointments,
    _ReportMetrics metrics,
  ) {
    return _card(
      icon: Icons.assignment_outlined,
      title: 'Randevu Detayları · $_periodLabel',
      child: appointments.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Column(
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    size: 28,
                    color: AppColors.muted,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Seçilen dönemde randevu bulunmuyor.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${metrics.total} randevu · ${metrics.uniqueClients} danışan',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(AppColors.bg2),
                    columnSpacing: 22,
                    horizontalMargin: 12,
                    columns: const [
                      DataColumn(label: Text('Tarih / Saat')),
                      DataColumn(label: Text('Danışan')),
                      DataColumn(label: Text('İletişim')),
                      DataColumn(label: Text('Tür')),
                      DataColumn(label: Text('Durum')),
                      DataColumn(label: Text('Not')),
                    ],
                    rows: [
                      for (final appointment in appointments)
                        _appointmentRow(appointment),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  List<Client> get _periodClients {
    final ids = _appointments.map((appointment) => appointment.clientId).toSet();
    return widget.data.data.clients.where((client) {
      if (ids.contains(client.id)) return true;
      final created = DateTime.fromMillisecondsSinceEpoch(
        client.createdAt.toInt(),
      );
      return !created.isBefore(_periodStart) &&
          created.isBefore(_periodEndExclusive);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Widget _clientsCard() {
    final clients = _periodClients;
    return _card(
      icon: Icons.people_outline,
      title: 'Danışanlar · $_periodLabel',
      child: clients.isEmpty
          ? _emptyPeriod('Bu dönemde danışan kaydı veya randevusu yok.')
          : _dataTable(
              const ['Danışan', 'E-posta', 'Telefon', 'Durum', 'Randevu'],
              clients.map((client) {
                final count = _appointments
                    .where((appointment) => appointment.clientId == client.id)
                    .length;
                return [
                  client.name,
                  client.email.isEmpty ? '—' : client.email,
                  client.phone.isEmpty ? '—' : client.phone,
                  clientStatusLabel(client.status),
                  '$count',
                ];
              }).toList(),
            ),
    );
  }

  Widget _formsCard() {
    final tasks = _periodTasks;
    return _card(
      icon: Icons.assignment_outlined,
      title: 'Danışanlara Gönderilen Formlar ve Ödevler · $_periodLabel',
      child: tasks.isEmpty
          ? _emptyPeriod('Bu dönemde gönderilmiş form veya ödev yok.')
          : _dataTable(
              const ['Tarih', 'Danışan', 'Form / Ödev', 'Durum'],
              tasks.map((task) {
                final timestamp = (task['createdAtMs'] as num?)?.toInt();
                final date = timestamp == null
                    ? '—'
                    : fmtDate(DateTime.fromMillisecondsSinceEpoch(timestamp));
                final draft = task['formDraft'] is Map
                    ? Map<String, dynamic>.from(task['formDraft'] as Map)
                    : const <String, dynamic>{};
                return [
                  date,
                  (task['clientName'] ?? 'Bilinmeyen danışan').toString(),
                  (task['title'] ?? draft['title'] ?? 'Form / Ödev').toString(),
                  task['done'] == true ? 'Cevaplandı' : 'Yanıt bekliyor',
                ];
              }).toList(),
            ),
    );
  }

  Widget _notesCard() {
    final notes = _notes;
    return _card(
      icon: Icons.note_alt_outlined,
      title: 'Yazılan Seans Notları · $_periodLabel',
      child: notes.isEmpty
          ? _emptyPeriod('Bu dönemde seans notu yok.')
          : _dataTable(
              const ['Tarih', 'Danışan', 'Başlık'],
              notes.map((note) => [
                fmtDate(DateTime.fromMillisecondsSinceEpoch(note.date.toInt())),
                widget.data.data.clientById(note.clientId)?.name ??
                    'Bilinmeyen danışan',
                note.title.isEmpty ? 'Seans notu' : note.title,
              ]).toList(),
            ),
    );
  }

  Widget _assessmentsCard() {
    final assessments = _assessments;
    return _card(
      icon: Icons.fact_check_outlined,
      title: 'Değerlendirmeler · $_periodLabel',
      child: assessments.isEmpty
          ? _emptyPeriod('Bu dönemde tamamlanmış değerlendirme yok.')
          : _dataTable(
              const ['Tarih', 'Danışan', 'Form', 'Sonuç'],
              assessments.map((assessment) {
                final form = widget.data.data.formById(assessment.formId);
                return [
                  fmtDate(DateTime.fromMillisecondsSinceEpoch(
                    assessment.submittedAt.toInt(),
                  )),
                  widget.data.data.clientById(assessment.clientId)?.name ??
                      'Bilinmeyen danışan',
                  form?.title ?? 'Değerlendirme formu',
                  assessment.score == null ? 'Tamamlandı' : 'Puanlandı',
                ];
              }).toList(),
            ),
    );
  }

  Widget _plansCard() {
    final plans = _plans;
    return _card(
      icon: Icons.track_changes_outlined,
      title: 'Güncellenen Tedavi Planları · $_periodLabel',
      child: plans.isEmpty
          ? _emptyPeriod('Bu dönemde tedavi planı güncellenmedi.')
          : _dataTable(
              const ['Güncelleme', 'Danışan', 'Plan', 'Hedef', 'Tamamlanan'],
              plans.map((plan) {
                final goals = plan.goals;
                return [
                  fmtDate(DateTime.fromMillisecondsSinceEpoch(
                    plan.updatedAt.toInt(),
                  )),
                  widget.data.data.clientById(plan.clientId)?.name ??
                      'Bilinmeyen danışan',
                  plan.title,
                  '${goals.length}',
                  '${goals.where((goal) => goal.status == 'achieved').length}',
                ];
              }).toList(),
            ),
    );
  }

  Widget _emptyPeriod(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: Text(message, style: const TextStyle(color: AppColors.muted)),
    ),
  );

  Widget _dataTable(List<String> headers, List<List<String>> rows) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(AppColors.bg2),
          columns: [for (final header in headers) DataColumn(label: Text(header))],
          rows: [
            for (final row in rows)
              DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
          ],
        ),
      );

  DataRow _appointmentRow(Appointment appointment) {
    final client = widget.data.data.clientById(appointment.clientId);
    final statusColor = _statusColor(appointment.status);
    final contact = [
      if ((client?.email ?? '').isNotEmpty) client!.email,
      if ((client?.phone ?? '').isNotEmpty) client!.phone,
    ].join('\n');
    return DataRow(
      cells: [
        DataCell(
          Text(
            '${fmtDate(DateTime.parse(appointment.date))}\n${fmtTime(appointment.time)}',
          ),
        ),
        DataCell(Text(client?.name ?? 'Bilinmeyen danışan')),
        DataCell(Text(contact.isEmpty ? '—' : contact)),
        DataCell(Text(apptTypeLabel(appointment.type))),
        DataCell(_statusChip(apptStatusLabel(appointment.status), statusColor)),
        DataCell(
          SizedBox(
            width: 220,
            child: Text(
              appointment.notes.isEmpty ? '—' : appointment.notes,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
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
              Icon(icon, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
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

  Future<void> _exportHtml() async {
    setState(() => _exporting = true);
    final ok = await saveTextFile(
      'mindtrack-rapor-${_fileDate(_periodStart)}-${_range.name}.html',
      _buildHtmlReport(),
      'text/html;charset=utf-8',
    );
    if (!mounted) return;
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Temalı rapor indirildi. Dosyayı tarayıcıda açıp PDF olarak yazdırabilirsiniz.'
              : 'Rapor dosyası oluşturulamadı.',
        ),
        backgroundColor: ok ? null : AppColors.danger,
      ),
    );
  }

  String _buildHtmlReport() {
    final appointments = _appointments;
    final metrics = _ReportMetrics.from(appointments);
    final account = widget.data.accounts.current;
    final clinician = _escape(account?.name ?? 'Psikolog');
    final clinic = _escape(account?.clinic ?? '');
    final generated = _escape(_longDateTime(DateTime.now()));
    final tableRows = appointments
        .map((appointment) {
          final client = widget.data.data.clientById(appointment.clientId);
          final contact = [
            if ((client?.email ?? '').isNotEmpty) client!.email,
            if ((client?.phone ?? '').isNotEmpty) client!.phone,
          ].join('<br>');
          return '''<tr>
        <td>${_escape(_shortDate(DateTime.parse(appointment.date)))}<br><span class="muted">${_escape(fmtTime(appointment.time))}</span></td>
        <td><strong>${_escape(client?.name ?? 'Bilinmeyen danışan')}</strong></td>
        <td>${contact.isEmpty ? '—' : _escape(contact).replaceAll('&lt;br&gt;', '<br>')}</td>
        <td>${_escape(apptTypeLabel(appointment.type))}</td>
        <td><span class="status ${_statusClass(appointment.status)}">${_escape(apptStatusLabel(appointment.status))}</span></td>
        <td>${_escape(appointment.notes.isEmpty ? '—' : appointment.notes)}</td>
      </tr>''';
        })
        .join('\n');
    final clientRows = _periodClients.map((client) {
      final count = appointments
          .where((appointment) => appointment.clientId == client.id)
          .length;
      return [
        client.name,
        client.email.isEmpty ? '—' : client.email,
        client.phone.isEmpty ? '—' : client.phone,
        clientStatusLabel(client.status),
        '$count',
      ];
    }).toList();
    final formRows = _periodTasks.map((task) {
      final timestamp = (task['createdAtMs'] as num?)?.toInt();
      final draft = task['formDraft'] is Map
          ? Map<String, dynamic>.from(task['formDraft'] as Map)
          : const <String, dynamic>{};
      return [
        timestamp == null
            ? '—'
            : fmtDate(DateTime.fromMillisecondsSinceEpoch(timestamp)),
        (task['clientName'] ?? 'Bilinmeyen danışan').toString(),
        (task['title'] ?? draft['title'] ?? 'Form / Ödev').toString(),
        task['done'] == true ? 'Cevaplandı' : 'Yanıt bekliyor',
      ];
    }).toList();
    final noteRows = _notes.map((note) => [
      fmtDate(DateTime.fromMillisecondsSinceEpoch(note.date.toInt())),
      widget.data.data.clientById(note.clientId)?.name ?? 'Bilinmeyen danışan',
      note.title.isEmpty ? 'Seans notu' : note.title,
    ]).toList();
    final assessmentRows = _assessments.map((assessment) => [
      fmtDate(DateTime.fromMillisecondsSinceEpoch(assessment.submittedAt.toInt())),
      widget.data.data.clientById(assessment.clientId)?.name ?? 'Bilinmeyen danışan',
      widget.data.data.formById(assessment.formId)?.title ?? 'Değerlendirme formu',
      assessment.score == null ? 'Tamamlandı' : 'Puanlandı',
    ]).toList();
    final planRows = _plans.map((plan) => [
      fmtDate(DateTime.fromMillisecondsSinceEpoch(plan.updatedAt.toInt())),
      widget.data.data.clientById(plan.clientId)?.name ?? 'Bilinmeyen danışan',
      plan.title,
      '${plan.goals.length}',
      '${plan.goals.where((goal) => goal.status == 'achieved').length}',
    ]).toList();

    return '''<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MindTrack Klinik Faaliyet Raporu · ${_escape(_periodLabel)}</title>
<style>
  :root { --primary:#347F76; --primary-dark:#254F4A; --bg:#F8FBFB; --bg2:#EEF6F5; --text:#1D2B29; --muted:#7B8F8C; --border:#E3EDEB; --success:#2E8B57; --warning:#C98A1B; --danger:#D64545; --info:#2F6F9F; }
  * { box-sizing:border-box; } body { margin:0; background:var(--bg); color:var(--text); font-family:Inter,Arial,sans-serif; line-height:1.45; }
  .page { max-width:1180px; margin:0 auto; padding:36px; } .cover { background:#fff; border:1px solid var(--border); border-radius:18px; padding:28px; border-top:7px solid var(--primary); }
  .brand { color:var(--primary); font-size:14px; font-weight:800; letter-spacing:.08em; text-transform:uppercase; } h1 { margin:8px 0 6px; font-size:30px; } .muted { color:var(--muted); font-size:13px; }
  .meta { display:flex; flex-wrap:wrap; gap:16px; margin-top:20px; padding-top:16px; border-top:1px solid var(--border); } .meta div { min-width:180px; }
  .metrics { display:grid; grid-template-columns:repeat(5,1fr); gap:12px; margin:20px 0; } .metric { background:#fff; border:1px solid var(--border); border-radius:14px; padding:16px; } .metric .num { font-size:27px; font-weight:800; color:var(--primary-dark); } .metric .label { color:var(--muted); font-size:12px; }
  .section { background:#fff; border:1px solid var(--border); border-radius:16px; padding:20px; } h2 { margin:0 0 5px; font-size:18px; } table { width:100%; border-collapse:collapse; margin-top:16px; font-size:12px; } th { text-align:left; background:var(--bg2); color:var(--primary-dark); padding:11px 10px; } td { border-bottom:1px solid var(--border); padding:11px 10px; vertical-align:top; } .status { display:inline-block; border-radius:999px; padding:3px 8px; font-weight:700; font-size:11px; background:#EEF6F5; color:var(--primary); } .done { background:#EAF7F0; color:var(--success); } .planned { background:#FDF6E8; color:var(--warning); } .cancelled,.noshow,.rejected { background:#FDF0F0; color:var(--danger); }
  .footer { color:var(--muted); font-size:11px; margin-top:18px; } @media(max-width:760px) { .page { padding:16px; } .metrics { grid-template-columns:repeat(2,1fr); } .cover { padding:20px; } table { font-size:10px; } th,td { padding:8px 5px; } } @media print { body { background:#fff; } .page { max-width:none; padding:0; } .cover,.section,.metric { break-inside:avoid; } }
</style>
</head>
<body>
  <main class="page">
    <section class="cover">
      <div class="brand">MindTrack · Yönetici Sunumu</div>
      <h1>Danışan ve Klinik Faaliyet Raporu</h1>
      <div class="muted">${_escape(_periodLabel)} dönemi için hazırlanmıştır.</div>
      <div class="meta">
        <div><strong>Psikolog</strong><br>$clinician</div>
        <div><strong>Klinik</strong><br>${clinic.isEmpty ? '—' : clinic}</div>
        <div><strong>Hazırlanma</strong><br>$generated</div>
      </div>
    </section>
    <section class="metrics">
      <div class="metric"><div class="num">${metrics.total}</div><div class="label">Toplam randevu</div></div>
      <div class="metric"><div class="num">${metrics.uniqueClients}</div><div class="label">Tekil danışan</div></div>
      <div class="metric"><div class="num">${metrics.done}</div><div class="label">Tamamlanan</div></div>
      <div class="metric"><div class="num">${metrics.planned}</div><div class="label">Planlanan</div></div>
      <div class="metric"><div class="num">${metrics.cancelled + metrics.noShow}</div><div class="label">İptal / gelmedi</div></div>
      <div class="metric"><div class="num">${_clients.length}</div><div class="label">Dönemde eklenen danışan</div></div>
      <div class="metric"><div class="num">${_periodTasks.length}</div><div class="label">Gönderilen form / ödev</div></div>
      <div class="metric"><div class="num">${_periodTasks.where((task) => task['done'] == true).length}</div><div class="label">Cevaplanan form / ödev</div></div>
      <div class="metric"><div class="num">${_notes.length}</div><div class="label">Seans notu kaydı</div></div>
      <div class="metric"><div class="num">${_assessments.length}</div><div class="label">Tamamlanan değerlendirme</div></div>
      <div class="metric"><div class="num">${_plans.length}</div><div class="label">Güncellenen tedavi planı</div></div>
    </section>
    <section class="section">
      <h2>Randevu Detayları</h2>
      <div class="muted">Danışan, iletişim, randevu türü ve güncel durum bilgileri</div>
      ${appointments.isEmpty ? '<p class="muted">Seçilen dönemde randevu bulunmuyor.</p>' : '<table><thead><tr><th>Tarih / Saat</th><th>Danışan</th><th>İletişim</th><th>Tür</th><th>Durum</th><th>Not</th></tr></thead><tbody>$tableRows</tbody></table>'}
    </section>
    <section class="section" style="margin-top:16px">
      <h2>Danışanlar</h2><div class="muted">Dönemde eklenen veya dönem randevularında yer alan danışanlar</div>
      ${_htmlTable(const ['Danışan','E-posta','Telefon','Durum','Randevu'], clientRows, 'Dönemle ilişkili danışan kaydı bulunmuyor.')}
    </section>
    <section class="section" style="margin-top:16px">
      <h2>Gönderilen Formlar ve Ödevler</h2><div class="muted">Cevap içerikleri ve klinik yanıtlar bu yönetim raporuna eklenmez.</div>
      ${_htmlTable(const ['Tarih','Danışan','Form / Ödev','Durum'], formRows, 'Dönemde gönderilmiş form veya ödev yok.')}
    </section>
    <section class="section" style="margin-top:16px">
      <h2>Seans Notları</h2><div class="muted">Gizlilik için seans notlarının klinik metni rapora dahil edilmemiştir.</div>
      ${_htmlTable(const ['Tarih','Danışan','Başlık'], noteRows, 'Dönemde seans notu yok.')}
    </section>
    <section class="section" style="margin-top:16px">
      <h2>Değerlendirmeler</h2><div class="muted">Yanıtlar ve puan detayları yalnızca yetkili klinik ekranlarında görüntülenir.</div>
      ${_htmlTable(const ['Tarih','Danışan','Form','Durum'], assessmentRows, 'Dönemde değerlendirme kaydı yok.')}
    </section>
    <section class="section" style="margin-top:16px">
      <h2>Tedavi Planları</h2><div class="muted">Güncellenen plan ve hedeflerin toplu özeti</div>
      ${_htmlTable(const ['Güncelleme','Danışan','Plan','Hedef','Tamamlanan'], planRows, 'Dönemde güncellenen tedavi planı yok.')}
    </section>
    <p class="footer">Bu rapor MindTrack tarafından oluşturulmuştur. İçerdiği kişisel veriler yalnızca yetkili kişilerle paylaşılmalıdır.</p>
  </main>
</body>
</html>''';
  }

  String _escape(String value) => const HtmlEscape().convert(value);

  String _htmlTable(List<String> headers, List<List<String>> rows, String empty) {
    if (rows.isEmpty) return '<p class="muted">${_escape(empty)}</p>';
    final head = headers.map((value) => '<th>${_escape(value)}</th>').join();
    final body = rows.map((row) => '<tr>${row.map((value) => '<td>${_escape(value)}</td>').join()}</tr>').join();
    return '<table><thead><tr>$head</tr></thead><tbody>$body</tbody></table>';
  }

  Color _statusColor(String status) => switch (status) {
    'done' => AppColors.success,
    'cancelled' || 'noshow' || 'rejected' => AppColors.danger,
    _ => AppColors.warning,
  };

  String _statusClass(String status) => switch (status) {
    'done' => 'done',
    'cancelled' => 'cancelled',
    'noshow' => 'noshow',
    'rejected' => 'rejected',
    _ => 'planned',
  };
}

enum _ReportRange { week, month }

class _ReportMetrics {
  const _ReportMetrics({
    required this.total,
    required this.uniqueClients,
    required this.planned,
    required this.done,
    required this.cancelled,
    required this.noShow,
  });

  final int total;
  final int uniqueClients;
  final int planned;
  final int done;
  final int cancelled;
  final int noShow;

  factory _ReportMetrics.from(List<Appointment> appointments) => _ReportMetrics(
    total: appointments.length,
    uniqueClients: appointments
        .map((item) => item.clientId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .length,
    planned: appointments.where((item) => item.status == 'planned').length,
    done: appointments.where((item) => item.status == 'done').length,
    cancelled: appointments
        .where(
          (item) => item.status == 'cancelled' || item.status == 'rejected',
        )
        .length,
    noShow: appointments.where((item) => item.status == 'noshow').length,
  );
}

class _MetricItem {
  const _MetricItem(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label;
  final int value;
  final Color color;
}

String _monthLabel(DateTime date) {
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
  return '${months[date.month - 1]} ${date.year}';
}

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

String _fileDate(DateTime date) =>
    '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

String _longDateTime(DateTime date) =>
    '${_shortDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

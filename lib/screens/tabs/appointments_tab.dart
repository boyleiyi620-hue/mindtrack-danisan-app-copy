import 'package:flutter/material.dart';

import 'dart:async';

import '../../data/data_store.dart';
import '../../data/mindtrack_backend.dart';
import '../../models/app_data.dart';
import '../../models/appointment.dart';
import '../../theme/app_theme.dart';
import '../../utils/formats.dart';

/// Randevular — aylık takvim, hafta görünümü, liste ve randevu planlama.
class AppointmentsTab extends StatefulWidget {
  const AppointmentsTab({super.key, required this.data});

  final DataStore data;

  @override
  State<AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<AppointmentsTab> {
  String _view = 'calendar'; // calendar | week | list
  DateTime _cal = DateTime.now();
  String _weekStart = mondayOfIso(todayIso());
  String _q = '';
  String _filter = 'all';
  StreamSubscription<List<Map<String, dynamic>>>?
  _remoteAppointmentsSubscription;

  AppData get _d => widget.data.data;

  @override
  void initState() {
    super.initState();
    _startRemoteAppointmentSync();
  }

  @override
  void dispose() {
    _remoteAppointmentsSubscription?.cancel();
    super.dispose();
  }

  void _startRemoteAppointmentSync() {
    final backend = MindTrackBackend.instance;
    if (!backend.isSignedIn) return;
    _remoteAppointmentsSubscription = backend
        .watchPsychologistAppointments()
        .listen(_applyRemoteAppointments, onError: (_) {});
  }

  void _applyRemoteAppointments(List<Map<String, dynamic>> snapshot) {
    var changed = false;

    for (final data in snapshot) {
      final remoteId = data['id']?.toString() ?? '';
      final linkedId = data['linkedAppointmentId']?.toString() ?? '';
      final local = _d.appointments.cast<Appointment?>().firstWhere(
        (appointment) =>
            appointment != null &&
            ((linkedId.isNotEmpty && appointment.id == linkedId) ||
                appointment.notes == 'request:$remoteId'),
        orElse: () => null,
      );
      if (local == null) continue;

      final remoteStatus = data['status']?.toString() ?? '';
      final localStatus = remoteStatus == 'approved' ? 'planned' : remoteStatus;
      if (const {
        'planned',
        'done',
        'cancelled',
        'noshow',
      }.contains(localStatus)) {
        if (local.status != localStatus) {
          local.status = localStatus;
          changed = true;
        }
      }

      final remoteDate = _remoteAppointmentDate(data['date']);
      if (remoteDate != null) {
        final date = isoDate(remoteDate);
        final time =
            '${remoteDate.hour.toString().padLeft(2, '0')}:${remoteDate.minute.toString().padLeft(2, '0')}';
        if (local.date != date || local.time != time) {
          local.date = date;
          local.time = time;
          changed = true;
        }
      }
    }

    final linkedRequestIds = snapshot
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final local in [..._d.appointments]) {
      if (!local.notes.startsWith('request:')) continue;
      final requestId = local.notes.substring('request:'.length).trim();
      if (requestId.isNotEmpty && !linkedRequestIds.contains(requestId)) {
        _d.appointments.removeWhere(
          (appointment) => appointment.id == local.id,
        );
        changed = true;
      }
    }

    if (!changed) return;
    widget.data.save();
    if (mounted) setState(() {});
  }

  DateTime? _remoteAppointmentDate(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw)?.toLocal();
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final monthAppts = _d.appointments
        .where((a) => a.date.startsWith(monthKey(_cal.year, _cal.month)))
        .length;
    final upcomingCount = _d.appointments
        .where(
          (a) => a.date.compareTo(todayIso()) >= 0 && a.status == 'planned',
        )
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, monthAppts, upcomingCount),
              const SizedBox(height: 14),
              if (_view == 'calendar')
                _calendar(context)
              else if (_view == 'week')
                _weekView(context)
              else
                _listView(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int monthAppts, int upcomingCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Randevular',
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
              '${monthName(_cal.year, _cal.month)} · $monthAppts randevu · $upcomingCount bekleyen',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _segmented(),
            FilledButton.icon(
              onPressed: () => _openApptDialog(context),
              icon: const Icon(Icons.event_available, size: 16),
              label: const Text('Yeni Randevu', style: TextStyle()),
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
                  const SizedBox(width: 10),
                  actions,
                ],
              );
      },
    );
  }

  Widget _segmented() {
    const opts = <(String, String, IconData)>[
      ('calendar', 'Takvim', Icons.calendar_month_outlined),
      ('week', 'Hafta', Icons.view_week_outlined),
      ('list', 'Liste', Icons.view_list_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in opts)
            InkWell(
              onTap: () => setState(() => _view = v.$1),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _view == v.$1 ? AppColors.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _view == v.$1
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .06),
                            blurRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      v.$3,
                      size: 15,
                      color: _view == v.$1
                          ? AppColors.primary
                          : AppColors.muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      v.$2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _view == v.$1
                            ? AppColors.primary
                            : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== TAKVİM ====================
  Widget _calendar(BuildContext context) {
    final year = _cal.year;
    final month = _cal.month;
    final today = todayIso();
    final dim = daysInMonth(year, month);

    // Kullanıcı isteği: yalnızca seçili ayı göster; her ay 1. günden başlasın.
    // Önceki/sonraki aya ait dolgu hücreleri özellikle eklenmez.
    final cells = <_CalCell>[];
    for (var day = 1; day <= dim; day++) {
      cells.add(_CalCell(isoDate(DateTime(year, month, day)), day, false));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Önceki ay',
              onPressed: () => setState(() {
                _cal = DateTime(year, month - 1, 1);
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                monthName(year, month),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Sonraki ay',
              onPressed: () => setState(() {
                _cal = DateTime(year, month + 1, 1);
              }),
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() {
                _cal = DateTime.now();
                _view = 'calendar';
              }),
              child: const Text('Bugün', style: TextStyle()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 92,
            crossAxisSpacing: 5,
            mainAxisSpacing: 5,
          ),
          itemCount: cells.length,
          itemBuilder: (context, i) => _calCell(context, cells[i], today),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final s in const <(String, String, Color)>[
              ('planned', 'Planlandı', AppColors.warning),
              ('done', 'Tamamlandı', AppColors.success),
              ('cancelled', 'İptal', AppColors.muted),
              ('noshow', 'Gelmedi', AppColors.danger),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.$3,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    s.$2,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            const Text(
              'Bir güne tıklayarak o güne randevu ekleyebilirsiniz.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _calCell(BuildContext context, _CalCell cell, String today) {
    final appts = _d.appointments.where((a) => a.date == cell.date).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final isToday = cell.date == today;
    final isPast = cell.date.compareTo(today) < 0;
    final color = _calStatusColor;

    return InkWell(
      key: ValueKey('cal-cell-${cell.date}'),
      onTap: () {
        if (appts.isNotEmpty) {
          _openDayDialog(context, cell.date);
        } else if (isPast) {
          _toast(
            context,
            'Geçmiş bir tarihe randevu eklenemez.',
            isError: true,
          );
        } else {
          _openApptDialog(context, date: cell.date);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: isToday
              ? AppColors.primarySoft
              : cell.other
              ? AppColors.bg2.withValues(alpha: .35)
              : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isToday
                ? AppColors.primary.withValues(alpha: .4)
                : cell.other
                ? Colors.transparent
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${cell.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: isToday
                    ? AppColors.primaryDark
                    : isPast
                    ? AppColors.muted.withValues(alpha: .6)
                    : AppColors.text2,
              ),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: appts.isEmpty
                  ? (cell.other || isPast
                        ? const SizedBox.shrink()
                        : const Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              '+',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                            ),
                          ))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final a in appts.take(3))
                          _calApptChip(a, color(a.status)),
                        if (appts.length > 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '+${appts.length - 3} daha',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
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

  Color _calStatusColor(String status) {
    switch (status) {
      case 'done':
        return AppColors.success;
      case 'cancelled':
        return AppColors.muted;
      case 'noshow':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  Widget _calApptChip(Appointment a, Color color) {
    final c = _d.clientById(a.clientId);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Icon(
            a.status == 'done' ? Icons.check : Icons.schedule,
            size: 9,
            color: color,
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              '${fmtTime(a.time)} ${c?.name ?? '?'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HAFTA ====================
  Widget _weekView(BuildContext context) {
    final days = [for (var i = 0; i < 7; i++) addDaysIso(_weekStart, i)];
    final range =
        '${fmtDate(DateTime.parse(days.first), long: true)} – ${fmtDate(DateTime.parse(days.last), long: true)}';
    final today = todayIso();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Önceki hafta',
              onPressed: () =>
                  setState(() => _weekStart = addDaysIso(_weekStart, -7)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                range,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Sonraki hafta',
              onPressed: () =>
                  setState(() => _weekStart = addDaysIso(_weekStart, 7)),
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() => _weekStart = mondayOfIso(today)),
              child: const Text('Bugün', style: TextStyle()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 7; i++)
                SizedBox(
                  width: i == 0 ? 200 : 170,
                  child: _weekDay(days[i], today),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _weekDay(String date, String today) {
    final d = DateTime.parse(date);
    final appts = _d.appointments.where((a) => a.date == date).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final names = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final isToday = date == today;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isToday ? AppColors.primarySoft : AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isToday
              ? AppColors.primary.withValues(alpha: .4)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${names[d.weekday - 1]} ${d.day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isToday ? AppColors.primaryDark : AppColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          if (appts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '—',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            )
          else
            for (final a in appts)
              InkWell(
                onTap: () => _openApptDialog(context, appt: a),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _calStatusColor(a.status).withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fmtTime(a.time),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _calStatusColor(a.status),
                        ),
                      ),
                      Text(
                        _d.clientById(a.clientId)?.name ?? '?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  // ==================== LİSTE ====================
  Widget _listView(BuildContext context) {
    final today = todayIso();
    final q = _q.trim().toLowerCase();
    final list = _d.appointments.where((a) {
      if (_filter != 'all' && a.status != _filter) return false;
      if (q.isEmpty) return true;
      final c = _d.clientById(a.clientId);
      return (c?.name.toLowerCase().contains(q) ?? false) ||
          (c?.email.toLowerCase().contains(q) ?? false);
    }).toList();
    final upcoming =
        list
            .where((a) => a.date.compareTo(today) >= 0 && a.status == 'planned')
            .toList()
          ..sort((a, b) {
            final c = a.date.compareTo(b.date);
            return c != 0 ? c : a.time.compareTo(b.time);
          });
    final past =
        list
            .where((a) => a.date.compareTo(today) < 0 || a.status != 'planned')
            .toList()
          ..sort((a, b) {
            final c = b.date.compareTo(a.date);
            return c != 0 ? c : b.time.compareTo(a.time);
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  hintText: 'Danışan ara...',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 17),
                ),
              ),
            ),
            for (final f in const [
              ['all', 'Tümü'],
              ['planned', 'Planlı'],
              ['done', 'Tamamlandı'],
              ['cancelled', 'İptal'],
              ['noshow', 'Gelmedi'],
            ])
              ChoiceChip(
                label: Text(f[1], style: const TextStyle(fontSize: 12)),
                selected: _filter == f[0],
                onSelected: (_) => setState(() => _filter = f[0]),
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          _empty('Randevu bulunamadı')
        else
          for (final a in [...upcoming, ...past]) _listRow(context, a),
      ],
    );
  }

  Widget _listRow(BuildContext context, Appointment a) {
    final c = _d.clientById(a.clientId);
    final statusColor = _calStatusColor(a.status);
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
              color: statusColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              a.status == 'done'
                  ? Icons.check_circle
                  : a.status == 'noshow'
                  ? Icons.cancel
                  : a.status == 'cancelled'
                  ? Icons.block
                  : Icons.schedule,
              size: 17,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      c?.name ?? '-',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (a.repeatGroup != null)
                      const Icon(
                        Icons.repeat,
                        size: 13,
                        color: AppColors.muted,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmtDate(DateTime.parse(a.date))}${a.date == todayIso() ? ' · Bugün' : ''} · ${fmtTime(a.time)} · ${apptTypeLabel(a.type)} · ${a.durationMin > 0 ? a.durationMin : 50} dk',
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
          const SizedBox(width: 8),
          _chip(apptStatusLabel(a.status), statusColor),
          IconButton(
            tooltip: 'Aç',
            visualDensity: VisualDensity.compact,
            onPressed: () => _openApptDialog(context, appt: a),
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: AppColors.text2,
            ),
          ),
          IconButton(
            tooltip: 'Sil',
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmDelete(context, a),
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _empty(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bg2.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_busy, size: 26, color: AppColors.muted),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 13, color: AppColors.text2),
          ),
        ],
      ),
    );
  }

  // ==================== GÜN DETAYI ====================
  Future<void> _openDayDialog(BuildContext context, String date) async {
    final appts = _d.appointments.where((a) => a.date == date).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${fmtDate(DateTime.parse(date), long: true)} · ${appts.length} randevu',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final a in appts) _dayApptRow(ctx, a),
                      if (appts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Bu tarihte randevu bulunmuyor.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Kapat', style: TextStyle()),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _openApptDialog(context, date: date);
                      },
                      icon: const Icon(Icons.event_available, size: 15),
                      label: const Text('Randevu Ekle', style: TextStyle()),
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

  Widget _dayApptRow(BuildContext ctx, Appointment a) {
    final c = _d.clientById(a.clientId);
    final statusColor = _calStatusColor(a.status);
    return InkWell(
      onTap: () {
        Navigator.of(ctx).pop();
        _openApptDialog(context, appt: a);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bg2.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.schedule, size: 16, color: statusColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fmtTime(a.time)} · ${c?.name ?? 'Bilinmeyen Danışan'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${apptTypeLabel(a.type)} · ${a.durationMin > 0 ? a.durationMin : 50} dk${a.notes.isNotEmpty ? ' · ${a.notes}' : ''}',
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
            _chip(apptStatusLabel(a.status), statusColor),
          ],
        ),
      ),
    );
  }

  // ==================== RANDEVU DİYALOĞU ====================
  Future<void> _openApptDialog(
    BuildContext context, {
    Appointment? appt,
    String? date,
  }) async {
    if (date != null && date.compareTo(todayIso()) < 0) {
      _toast(context, 'Geçmiş bir tarihe randevu eklenemez.', isError: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AppointmentDialog(
        data: widget.data,
        existing: appt,
        presetDate: date,
        onSaved: (notify) =>
            _toast(context, notify, isError: notify.contains('çıkamadı')),
        onDeleteRequested: appt == null
            ? null
            : (a) => _confirmDelete(context, a),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Appointment a) async {
    final group = a.repeatGroup == null
        ? null
        : _d.appointments.where((x) => x.repeatGroup == a.repeatGroup).toList();
    final messenger = ScaffoldMessenger.of(context);
    final bool deleteWhole;
    if (group != null && group.length > 1) {
      deleteWhole =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Tekrarlı randevuyu sil', style: TextStyle()),
              content: Text(
                'Bu randevu ${group.length} randevuluk bir tekrar dizisine ait. Sadece bu randevuyu mu, yoksa dizinin tamamını mı silmek istiyorsunuz?',
                style: const TextStyle(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Vazgeç', style: TextStyle()),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Sadece Bu', style: TextStyle()),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                  child: const Text('Tüm Tekrarlar', style: TextStyle()),
                ),
              ],
            ),
          ) ??
          false;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Randevuyu sil', style: TextStyle()),
          content: const Text(
            'Bu randevu silinecek. İşlem geri alınamaz.',
            style: TextStyle(),
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
      if (ok != true) return;
      deleteWhole = false;
    }
    if (deleteWhole) {
      for (final item in group!) {
        await deleteRemoteAppointment(item);
      }
      _d.appointments.removeWhere((x) => x.repeatGroup == a.repeatGroup);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${group.length} randevu silindi.',
              style: const TextStyle(),
            ),
          ),
        );
    } else {
      await deleteRemoteAppointment(a);
      _d.appointments.removeWhere((x) => x.id == a.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Randevu silindi.', style: TextStyle())),
        );
    }
    widget.data.save();
  }

  void _toast(BuildContext context, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError ? AppColors.danger : null,
          content: Text(msg, style: const TextStyle()),
        ),
      );
  }
}

Color _appointmentStatusColor(String status) {
  switch (status) {
    case 'done':
      return AppColors.success;
    case 'cancelled':
      return AppColors.muted;
    case 'noshow':
      return AppColors.danger;
    default:
      return AppColors.warning;
  }
}

/// Randevunun uzak karşılığı: not alanında saklanan `request:<id>` referansı.
/// Bu olmadan uzak kayıt bulunamaz ve güncellenemez.
String? _remoteAppointmentId(Appointment appointment) {
  final notes = appointment.notes;
  if (!notes.startsWith('request:')) return null;
  final requestId = notes.substring('request:'.length).trim();
  return requestId.isEmpty ? null : requestId;
}

Future<void> syncRemoteAppointment(
  Appointment appointment, {
  String? statusOverride,
}) async {
  try {
    final requestId = _remoteAppointmentId(appointment);
    if (requestId == null) return;
    await MindTrackBackend.instance.updateAppointmentRequest(
      requestId,
      status: statusOverride ?? appointment.status,
      at: DateTime.parse('${appointment.date} ${appointment.time}:00'),
      linkedAppointmentId: appointment.id,
    );
  } catch (_) {
    // Yerel kayıt korunur; çevrim içi kayıt sonraki işlemde güncellenebilir.
  }
}

Future<void> deleteRemoteAppointment(Appointment appointment) async {
  try {
    // Firebase dönemindeki `DocumentReference` yerine artık satırın UUID'si
    // doğrudan RPC'ye veriliyor.
    final remoteId = appointment.id.trim();
    if (remoteId.isEmpty) return;
    await MindTrackBackend.instance.deleteAppointment(remoteId);
  } catch (_) {
    // Yerel silme korunur; uzak kayıt sonraki senkron adımında temizlenebilir.
  }
}

class _CalCell {
  const _CalCell(this.date, this.day, this.other);
  final String date;
  final int day;
  final bool other;
}

/// Randevu oluşturma / düzenleme penceresi.
class AppointmentDialog extends StatefulWidget {
  const AppointmentDialog({
    super.key,
    required this.data,
    this.existing,
    this.presetDate,
    this.onSaved,
    this.onDeleteRequested,
  });

  final DataStore data;
  final Appointment? existing;
  final String? presetDate;
  final ValueChanged<String>? onSaved;
  final ValueChanged<Appointment>? onDeleteRequested;

  @override
  State<AppointmentDialog> createState() => _AppointmentDialogState();
}

class _AppointmentDialogState extends State<AppointmentDialog> {
  late String _clientId;
  late DateTime _date;
  late final TextEditingController _time;
  late final TextEditingController _notes;
  late final TextEditingController _repeatCount;
  int _duration = 50;
  String _type = 'ilk_görüşme';
  String _status = 'planned';
  String _repeat = 'none';
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    final today = DateTime.now();
    _clientId = a?.clientId ?? '';
    _date = a != null && a.date.isNotEmpty
        ? DateTime.parse(a.date.length >= 10 ? a.date.substring(0, 10) : a.date)
        : widget.presetDate != null
        ? DateTime.parse(widget.presetDate!.substring(0, 10))
        : today;
    _time = TextEditingController(
      text: a?.time.isNotEmpty == true ? a!.time : '10:00',
    );
    _notes = TextEditingController(text: a?.notes ?? '');
    _repeatCount = TextEditingController(text: '4');
    _duration = a?.durationMin ?? 50;
    _type = a?.type ?? 'ilk_görüşme';
    _status = a?.status ?? 'planned';
  }

  @override
  void dispose() {
    _time.dispose();
    _notes.dispose();
    _repeatCount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final isNew = _isNew && widget.presetDate == null;
    final picked = await showDatePicker(
      context: context,
      initialDate: isNew && _date.isBefore(DateTime.now())
          ? DateTime.now()
          : _date,
      firstDate: isNew
          ? DateTime.now().subtract(const Duration(days: 1))
          : DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final time = _time.text.trim();
    if (_clientId.isEmpty) {
      setState(() => _error = 'Danışan seçin.');
      return;
    }
    if (!isValidHm(time)) {
      setState(() => _error = 'Geçerli bir saat girin (örn: 10:00).');
      return;
    }
    final iso = isoDate(_date);
    if (_isNew && iso.compareTo(todayIso()) < 0) {
      setState(() => _error = 'Geçmiş bir tarihe randevu eklenemez.');
      return;
    }
    final d = widget.data.data;

    // Çakışma kontrolü (uyarı)
    final mStart =
        int.parse(time.substring(0, 2)) * 60 + int.parse(time.substring(3, 5));
    final mEnd = mStart + _duration;
    final clash = d.appointments.any((x) {
      if (x.id == (widget.existing?.id ?? '')) return false;
      if (x.clientId != _clientId || x.date != iso) return false;
      if (x.status == 'cancelled' || x.status == 'noshow') return false;
      final s =
          int.parse(x.time.substring(0, 2)) * 60 +
          int.parse(x.time.substring(3, 5));
      final e = s + (x.durationMin > 0 ? x.durationMin : 50);
      return s < mEnd && mStart < e;
    });

    final existing = widget.existing;
    if (existing != null) {
      existing.clientId = _clientId;
      existing.date = iso;
      existing.time = time;
      existing.durationMin = _duration;
      existing.type = _type;
      existing.status = _status;
      existing.notes = _notes.text.trim();
      widget.data.save();
      await syncRemoteAppointment(existing);
      Navigator.of(context).pop();
      widget.onSaved?.call('Randevu kaydedildi.');
      return;
    }

    // Tekrarlı seri
    final today = todayIso();
    if (_repeat != 'none') {
      final step = _repeat == 'weekly' ? 1 : 2;
      final count =
          (_repeatCount.text.trim().isEmpty
                  ? 4
                  : int.tryParse(_repeatCount.text.trim()) ?? 4)
              .clamp(2, 24);
      final gid = widget.data.newId();
      final series = <Appointment>[];
      for (var i = 0; i < count; i++) {
        final date = addDaysIso(iso, i * step * 7);
        if (date.compareTo(today) < 0) continue;
        series.add(
          Appointment(
            id: widget.data.newId(),
            date: date,
            time: time,
            clientId: _clientId,
            type: _type,
            status: _status,
            durationMin: _duration,
            notes: _notes.text.trim(),
            repeatGroup: gid,
          ),
        );
      }
      if (series.isEmpty) {
        setState(
          () => _error =
              'Tüm tekrarlar geçmiş tarihe denk geldi, randevu oluşturulamadı.',
        );
        return;
      }
      d.appointments.addAll(series);
      widget.data.save();
      Navigator.of(context).pop();
      widget.onSaved?.call(
        '${series.length} randevu planlandı (tekrarlı seri).',
      );
      return;
    }

    d.appointments.add(
      Appointment(
        id: widget.data.newId(),
        date: iso,
        time: time,
        clientId: _clientId,
        type: _type,
        status: _status,
        durationMin: _duration,
        notes: _notes.text.trim(),
      ),
    );
    widget.data.save();
    Navigator.of(context).pop();
    widget.onSaved?.call(
      clash
          ? 'Dikkat: Bu danışanın aynı zamana denk gelen bir randevusu daha var.'
          : 'Randevu kaydedildi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final clients = widget.data.data.clients;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isNew ? 'Yeni Randevu' : 'Randevuyu Düzenle',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(),
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
                    if (clients.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Randevu oluşturmak için önce bir danışan ekleyin.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: _clientId.isEmpty ? null : _clientId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Danışan *',
                        isDense: true,
                      ),
                      items: [
                        for (final c in clients)
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: clients.isEmpty
                          ? null
                          : (v) => setState(() => _clientId = v ?? ''),
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
                                labelText: 'Tarih *',
                                suffixIcon: Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                ),
                              ),
                              child: Text(
                                fmtDate(_date),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _time,
                            decoration: const InputDecoration(
                              labelText: 'Saat *',
                              hintText: '10:00',
                              isDense: true,
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
                          child: DropdownButtonFormField<int>(
                            initialValue: _duration,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Süre',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 30, child: Text('30 dk')),
                              DropdownMenuItem(value: 45, child: Text('45 dk')),
                              DropdownMenuItem(value: 50, child: Text('50 dk')),
                              DropdownMenuItem(value: 60, child: Text('60 dk')),
                              DropdownMenuItem(value: 90, child: Text('90 dk')),
                            ],
                            onChanged: (v) =>
                                setState(() => _duration = v ?? 50),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _type,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Tür',
                              isDense: true,
                            ),
                            items: [
                              for (final t in apptTypes.entries)
                                DropdownMenuItem(
                                  value: t.key,
                                  child: Text(t.value),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _type = v ?? 'ilk_görüşme'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Durum',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in const [
                              ['planned', 'Planlandı'],
                              ['done', 'Tamamlandı'],
                              ['cancelled', 'İptal'],
                              ['noshow', 'Gelmedi'],
                            ])
                              ChoiceChip(
                                avatar: _status == s[0]
                                    ? Icon(
                                        Icons.check,
                                        size: 15,
                                        color: _appointmentStatusColor(s[0]),
                                      )
                                    : null,
                                label: Text(
                                  s[1],
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _status == s[0]
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: _status == s[0]
                                        ? _appointmentStatusColor(s[0])
                                        : AppColors.text2,
                                  ),
                                ),
                                selected: _status == s[0],
                                selectedColor: _appointmentStatusColor(s[0])
                                    .withValues(alpha: .16),
                                onSelected: (_) =>
                                    setState(() => _status = s[0]),
                                showCheckmark: false,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Seçili durum: ${apptStatusLabel(_status)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _appointmentStatusColor(_status),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notes,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Randevu Notu',
                        hintText: 'Görüşme öncesi not...',
                      ),
                    ),
                    if (_isNew) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _repeat,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Tekrarla',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'none',
                            child: Text('Tek seferlik'),
                          ),
                          DropdownMenuItem(
                            value: 'weekly',
                            child: Text('Her hafta'),
                          ),
                          DropdownMenuItem(
                            value: 'biweekly',
                            child: Text('Her 2 haftada bir'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _repeat = v ?? 'none'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _repeatCount,
                        enabled: _repeat != 'none',
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Toplam seans',
                          helperText: 'Tekrarlar aynı saat ve süreyle planlanır; geçmişe denk gelenler atlanır.',
                          isDense: true,
                        ),
                      ),
                    ],
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
                  if (!_isNew)
                    TextButton(
                      onPressed: () {
                        final a = widget.existing!;
                        Navigator.of(context).pop();
                        widget.onDeleteRequested?.call(a);
                      },
                      child: const Text(
                        'Sil',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
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
}

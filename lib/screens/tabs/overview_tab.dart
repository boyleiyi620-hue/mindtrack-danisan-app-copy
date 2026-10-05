import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../models/app_data.dart';
import '../../models/appointment.dart';
import '../../models/client.dart';
import '../../models/task.dart';
import '../../models/user_account.dart';
import '../../theme/app_theme.dart';
import 'appointment_requests.dart';
import '../../utils/formats.dart';

/// Genel Bakış — psikoloğun günlük kontrol panosu.
/// Web sürümündeki `overviewView` yapısıyla birebir uyumlu.
class OverviewTab extends StatefulWidget {
  const OverviewTab({
    super.key,
    required this.account,
    required this.data,
    this.onNavigate,
  });

  final UserAccount account;
  final DataStore data;
  final ValueChanged<String>? onNavigate;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  UserAccount get _u => widget.account;
  DataStore get _data => widget.data;
  AppData get _d => widget.data.data;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toLocal();
    final today = todayIso();
    final firstName = _u.name
        .split(RegExp(r'\s+'))
        .firstWhere((s) => s.isNotEmpty, orElse: () => _u.name);

    final todayAppts = _d.appointments.where((a) => a.date == today).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final doneToday = todayAppts.where((a) => a.status == 'done').length;

    final upcoming =
        _d.appointments
            .where((a) => a.date.compareTo(today) >= 0 && a.status == 'planned')
            .toList()
          ..sort((a, b) {
            final c = a.date.compareTo(b.date);
            return c != 0 ? c : a.time.compareTo(b.time);
          });
    final upcomingList = upcoming.take(6).toList();

    final openTasks = _d.tasks.where((t) => !t.done).toList();
    final openTasksList = openTasks.take(4).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, firstName, todayAppts.length, doneToday, today),
              const SizedBox(height: 14),
              PendingAppointmentRequests(data: _data),
              const SizedBox(height: 16),
              _statsGrid(context),
              const SizedBox(height: 18),
              _reminderCard(context, now),
              const SizedBox(height: 18),
              _upcomingColumn(
                context,
                upcomingList,
                upcoming.isNotEmpty,
                today,
                now,
              ),
              const SizedBox(height: 18),
              _openTasksCard(context, openTasksList, openTasks.isNotEmpty),
              const SizedBox(height: 18),
              _quickActions(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- Üst başlık ----------------
  Widget _header(
    BuildContext context,
    String firstName,
    int todayCount,
    int doneToday,
    String today,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Merhaba, $firstName 👋',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hoş geldiniz! ${fmtDate(DateTime.now(), long: true)} — bugün $todayCount randevunuz var'
              '${todayCount > 0 ? ', $doneToday tamamlandı' : ''}.',
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => widget.onNavigate?.call('clients'),
              icon: const Icon(Icons.person_add_alt, size: 17),
              label: const Text('Yeni Danışan', style: TextStyle()),
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

  // ---------------- İstatistik kartları ----------------
  Widget _statsGrid(BuildContext context) {
    final today = todayIso();
    final activeForms = _d.forms.length;
    final todayAppts = _d.appointments.where((a) => a.date == today).length;
    final openTasks = _d.tasks.where((t) => !t.done).length;

    final stats = [
      _Stat(
        Icons.people_outline,
        'Danışan',
        _d.clients.length,
        AppColors.primary,
      ),
      _Stat(
        Icons.assignment_outlined,
        'Aktif Form',
        activeForms,
        AppColors.info,
      ),
      _Stat(
        Icons.check_circle_outline,
        'Bu Ay Değerlendirme',
        _monthAssess(),
        AppColors.success,
      ),
      _Stat(
        Icons.event_available,
        'Bugünkü Randevu',
        todayAppts,
        AppColors.warning,
      ),
      _Stat(
        Icons.schedule,
        'Bekleyen Randevu',
        _pendingAppts(today),
        AppColors.danger,
      ),
      _Stat(Icons.done_all, 'Açık Görev', openTasks, AppColors.primary),
      if (_u.appMode == 'commercial')
        _Stat(
          Icons.payments_outlined,
          'Bugünkü Kazanç',
          _todayEarnings().toInt(),
          Colors.green,
        ),
    ];

    return LayoutBuilder(
      builder: (context, bc) {
        final cols = bc.maxWidth >= 900
            ? 6
            : bc.maxWidth >= 560
            ? 3
            : 2;
        const gap = 12.0;
        final cardW = (bc.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final st in stats)
              SizedBox(width: cardW, child: _statCard(st)),
          ],
        );
      },
    );
  }

  int _monthAssess() {
    final now = DateTime.now();
    return _d.assessments.where((a) {
      final dt = DateTime.fromMillisecondsSinceEpoch(a.submittedAt.toInt());
      return dt.year == now.year && dt.month == now.month;
    }).length;
  }

  double _todayEarnings() {
    final today = todayIso();
    return _d.transactions
        .where((t) => t.type == 'income' && t.date == today)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  int _pendingAppts(String today) => _d.appointments
      .where((a) => a.date.compareTo(today) >= 0 && a.status == 'planned')
      .length;

  Widget _reminderCard(BuildContext context, DateTime now) {
    final reminders = _d.appointments.where((appointment) {
      if (appointment.status != 'planned') return false;
      final at = _appointmentLocalTime(appointment);
      final difference = at.difference(now);
      return !difference.isNegative && difference <= const Duration(hours: 24);
    }).toList()
      ..sort((a, b) {
        final aAt = _appointmentLocalTime(a);
        final bAt = _appointmentLocalTime(b);
        return aAt.compareTo(bAt);
      });

    if (reminders.isEmpty) return const SizedBox.shrink();
    final clients = <String, Client>{
      for (final client in _d.clients) client.id: client,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.warning.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: AppColors.warning),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Yaklaşan randevu hatırlatmaları',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              TextButton(
                onPressed: () => widget.onNavigate?.call('appointments'),
                child: const Text('Takvime git'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final appointment in reminders.take(4))
            _reminderRow(appointment, clients[appointment.clientId], now),
        ],
      ),
    );
  }

  Widget _reminderRow(Appointment appointment, Client? client, DateTime now) {
    final at = _appointmentLocalTime(appointment);
    final minutes = at.difference(now).inMinutes;
    final timing = minutes < 60
        ? '$minutes dk sonra'
        : minutes < 24 * 60
            ? '${minutes ~/ 60} saat sonra'
            : appointment.date;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${client?.name.isNotEmpty == true ? client!.name : 'Randevu'} · ${appointment.time}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(timing, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }

  /// Randevu date/time alanları birer yerel duvar saati değeridir.
  /// ISO parser'ın UTC/yerel saat varsayımına bırakılırsa bazı tarayıcılarda
  /// hatırlatma iki saat kayabilir.
  DateTime _appointmentLocalTime(Appointment appointment) {
    final date = appointment.date.length >= 10
        ? appointment.date.substring(0, 10)
        : appointment.date;
    final parts = date.split('-');
    final time = appointment.time.split(':');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
      int.parse(time[0]),
      int.parse(time[1]),
    );
  }

  Widget _statCard(_Stat s) {
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(s.icon, color: s.color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${s.value}',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  s.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Yaklaşan randevular ----------------
  Widget _upcomingColumn(
    BuildContext context,
    List<Appointment> list,
    bool hasItems,
    String today,
    DateTime now,
  ) {
    return _sectionCard(
      titleIcon: Icons.calendar_month_outlined,
      title: 'Yaklaşan Randevular',
      trailing: TextButton(
        onPressed: () => widget.onNavigate?.call('appointments'),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tümü', style: TextStyle()),
            SizedBox(width: 2),
            Icon(Icons.arrow_forward, size: 15),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (list.isEmpty)
            _emptyBox(
              Icons.calendar_month_outlined,
              'Önümüzdeki günlerde randevu bulunmuyor.',
              'Randevu eklemek için "Randevu Ekle" butonunu kullanın.',
            )
          else
            for (final a in list) _apptTile(context, a, today),
          if (hasItems) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => widget.onNavigate?.call('appointments'),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Randevu Ekle', style: TextStyle()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _apptTile(BuildContext context, Appointment a, String today) {
    final c = _d.clientById(a.clientId);
    final planned = a.status == 'planned';
    final isTodayOrPast = a.date.compareTo(today) <= 0;
    final completed = a.status == 'done';
    final gone = a.status == 'noshow';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg2.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: completed
                ? AppColors.success.withValues(alpha: .15)
                : gone
                ? AppColors.danger.withValues(alpha: .12)
                : AppColors.warning.withValues(alpha: .15),
            child: Text(
              initials(c?.name ?? '?'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: completed
                    ? AppColors.success
                    : gone
                    ? AppColors.danger
                    : AppColors.warning,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c?.name ?? 'Bilinmeyen Danışan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 11,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${fmtDate(DateTime.parse(a.date))} · ${fmtTime(a.time)} · ${apptTypeLabel(a.type)}'
                        '${a.repeatGroup != null ? ' · Tekrarlı' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusChip(apptStatusLabel(a.status), completed, gone),
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
      await _data.updateAppointmentStatus(appointment, status);
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

  // ---------------- Açık görevler ----------------
  Widget _openTasksCard(BuildContext context, List<Task> list, bool hasItems) {
    return _sectionCard(
      titleIcon: Icons.check_circle_outline,
      title: 'Açık Görevler',
      trailing: TextButton(
        onPressed: () => widget.onNavigate?.call('tasks'),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tümü', style: TextStyle()),
            SizedBox(width: 2),
            Icon(Icons.arrow_forward, size: 15),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (list.isEmpty)
            _emptyBox(
              Icons.check_circle_outline,
              'Açık görev bulunmuyor.',
              'Takip gerektiren işler için görev ekleyebilirsiniz.',
            )
          else
            for (final t in list) _taskTile(context, t),
          if (hasItems) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => widget.onNavigate?.call('tasks'),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Görev Ekle', style: TextStyle()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _taskTile(BuildContext context, Task t) {
    final c = t.clientId.isNotEmpty ? _d.clientById(t.clientId) : null;
    final now = todayIso();
    final overdue = t.dueDate != null && t.dueDate!.compareTo(now) < 0;
    final dueToday = t.dueDate == now;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg2.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Tamamla',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              t.done = true;
              _data.save();
            },
            icon: Icon(
              Icons.radio_button_unchecked,
              size: 20,
              color: AppColors.muted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.text,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (c != null)
                      Text(
                        c.name,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                    if (c != null && t.dueDate != null) const Text('·'),
                    if (t.dueDate != null && overdue)
                      _miniBadge(
                        'Gecikti',
                        AppColors.danger,
                        AppColors.dangerSoft,
                      )
                    else if (t.dueDate != null && dueToday)
                      _miniBadge(
                        'Bugün',
                        AppColors.warning,
                        AppColors.warningSoft,
                      )
                    else if (t.dueDate != null)
                      Text(
                        fmtDate(DateTime.parse(t.dueDate!)),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      )
                    else
                      const Text(
                        'Tarih yok',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                    if (t.priority == 'high')
                      _miniBadge('Yüksek', AppColors.info, AppColors.infoSoft),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sil',
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmDeleteTask(context, t),
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

  Widget _miniBadge(String text, Color fg, Color bg) {
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

  Future<void> _confirmDeleteTask(BuildContext context, Task t) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Görevi sil', style: TextStyle()),
        content: Text(
          '"${t.text}" görevi kalıcı olarak silinsin mi?',
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
      _d.tasks.removeWhere((x) => x.id == t.id);
      _data.save();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Görev silindi.', style: TextStyle())),
        );
    }
  }

  // ---------------- Hızlı işlemler ----------------
  Widget _quickActions(BuildContext context) {
    final items = [
      _Quick(Icons.assignment_outlined, 'Yeni Form', 'forms'),
      _Quick(Icons.person_add_alt, 'Yeni Danışan', 'clients'),
      _Quick(Icons.event_available, 'Randevu Planla', 'appointments'),
      _Quick(Icons.bar_chart_outlined, 'Rapor Oluştur', 'reports'),
      _Quick(Icons.folder_open, 'Danışan Dosyası', 'clients'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Hızlı İşlemler',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, bc) {
            final cols = bc.maxWidth >= 640 ? 3 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.45,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => _quickTile(items[i]),
            );
          },
        ),
      ],
    );
  }

  Widget _quickTile(_Quick q) {
    return InkWell(
      onTap: () => widget.onNavigate?.call(q.tab),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(q.icon, size: 17, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                q.label,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text2,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  // ---------------- Genel yardımcılar ----------------
  Widget _sectionCard({
    required IconData titleIcon,
    required String title,
    required Widget trailing,
    required Widget body,
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
              Icon(titleIcon, size: 18, color: AppColors.primaryDark),
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
              trailing,
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  Widget _emptyBox(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
      decoration: BoxDecoration(
        color: AppColors.bg2.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2, width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.bg2,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String label, bool completed, bool gone) {
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _Stat {
  const _Stat(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label;
  final int value;
  final Color color;
}

class _Quick {
  const _Quick(this.icon, this.label, this.tab);
  final IconData icon;
  final String label;
  final String tab;
}

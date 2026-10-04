import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/account_store.dart';
import '../../data/data_store.dart';
import '../../data/mindtrack_backend.dart';
import '../../data/sync_status.dart';
import '../../models/user_account.dart';
import '../../theme/app_theme.dart';
import '../auth/pin_screen.dart';
import '../auth/pin_setup_dialog.dart';
import '../tabs/appointments_tab.dart';
import '../tabs/clients_tab.dart';
import '../tabs/forms_tab.dart';
import '../tabs/overview_tab.dart';
import '../tabs/pdfs_tab.dart';
import '../tabs/reports_tab.dart';
import '../tabs/settings_tab.dart';
import '../tabs/tasks_tab.dart';
import '../tabs/finance_tab.dart';
import 'mode_selection_screen.dart';

class _NavItem {
  const _NavItem(
    this.id,
    this.label,
    this.icon,
    this.activeIcon,
    this.description,
  );
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String description;
}

const _navItems = [
  _NavItem(
    'overview',
    'Genel Bakış',
    Icons.space_dashboard_outlined,
    Icons.space_dashboard,
    'Bugünün özeti, yaklaşan randevular ve risk uyarıları.',
  ),
  _NavItem(
    'forms',
    'Formlar',
    Icons.assignment_outlined,
    Icons.assignment,
    'Değerlendirme formlarını oluşturun, düzenleyin ve doldurun.',
  ),
  _NavItem(
    'clients',
    'Danışanlar',
    Icons.people_outline,
    Icons.people,
    'Danışan kartları, seans notları ve tedavi planları burada olacak.',
  ),
  _NavItem(
    'appointments',
    'Randevular',
    Icons.calendar_month_outlined,
    Icons.calendar_month,
    'Takvim, randevu planlama ve tekrarlı randevular burada olacak.',
  ),
  _NavItem(
    'reports',
    'Raporlar',
    Icons.bar_chart_outlined,
    Icons.bar_chart,
    'Yönetim paylaşımı için dönemsel randevu raporları burada olacak.',
  ),
  _NavItem(
    'tasks',
    'Görevler',
    Icons.check_circle_outline,
    Icons.check_circle,
    'Açık ve tamamlanan görevlerin takibi burada olacak.',
  ),
  _NavItem(
    'pdfs',
    'PDF Kütüphanesi',
    Icons.folder_outlined,
    Icons.folder,
    'Kategorili PDF arşivi ve doküman görüntüleme burada olacak.',
  ),
  _NavItem(
    'settings',
    'Ayarlar',
    Icons.settings_outlined,
    Icons.settings,
    'Profil, CSV dışa aktarım ve KVKK burada olacak.',
  ),
];

/// Ana kabuk — masaüstünde yan menü, mobilde alt menü.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.store, required this.data});

  final AccountStore store;
  final DataStore data;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _locked = false;

  AppMode? get _selectedMode {
    final m = _u.appMode;
    if (m == 'commercial') return AppMode.commercial;
    if (m == 'standard') return AppMode.standard;
    return AppMode.standard;
  }

  void _setMode(AppMode m) {
    setState(() {
      _u.appMode = m.name;
      _index = 0;
    });
    widget.store.updateUser(_u);
  }

  Timer? _watchTimer;
  DateTime _lastActivity = DateTime.now();
  DateTime? _hiddenAt;

  UserAccount get _u => widget.store.current!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = widget.store.isLocked;
    _watchTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_locked && _u.lockTimeout > 0) {
        final el = DateTime.now().difference(_lastActivity);
        if (el.inMinutes >= _u.lockTimeout) _lock();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _hiddenAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_hiddenAt != null &&
          !_locked &&
          _u.lockTimeout > 0 &&
          DateTime.now().difference(_hiddenAt!).inSeconds > 45) {
        _lock();
      }
      _hiddenAt = null;
    }
  }

  void _tick() => _lastActivity = DateTime.now();

  void _lock() {
    if (!_u.hasPin || _locked) return;
    setState(() {
      _locked = true;
      _lastActivity = DateTime.now();
    });
    widget.store.setLocked(true);
  }

  void _unlock() {
    setState(() => _locked = false);
    _lastActivity = DateTime.now();
    widget.store.setLocked(false);
  }

  Future<void> _logout() async {
    try {
      await MindTrackBackend.instance.signOut();
    } catch (_) {
      // Yerel oturumu yine de kapat; ağ sorunu çıkış ekranında kalmayı
      // engellememeli.
    } finally {
      widget.store.clearSession();
      widget.data.load();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/auth', (r) => false);
      }
    }
  }

  void _onLockPressed() {
    if (_u.hasPin) {
      _lock();
    } else {
      PinSetupDialog.show(
        context,
        account: _u,
        onChanged: () {
          widget.store.updateUser(_u);
          setState(() {});
        },
        onLockRequest: _lock,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return PinScreen(store: widget.store, onUnlock: _unlock);
    }
    if (_u.appMode == '' || _u.appMode == 'none') {
      return ModeSelectionScreen(onSelected: _setMode);
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: _buildTopBar(context, wide),
      body: Row(
        children: [
          if (wide) _sidebar(context),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _tick(),
              child: AnimatedBuilder(
                animation: widget.data,
                builder: (context, _) => _content(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide ? null : _bottomNav(context),
    );
  }

  AppBar _buildTopBar(BuildContext context, bool wide) {
    String modeName = 'Standart';
    if (_selectedMode == AppMode.commercial) modeName = 'Ticari';

    return AppBar(
      title: Row(
        children: [
          const Icon(
            Icons.monitor_heart_outlined,
            color: AppColors.primary,
            size: 22,
          ),
          const SizedBox(width: 8),
          const Text('MindTrack', style: TextStyle()),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              modeName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
      actions: [
        _syncBadge(context),
        if (!wide)
          IconButton(
            tooltip: 'Uygulama Kilidi',
            onPressed: _onLockPressed,
            icon: Icon(_u.hasPin ? Icons.lock_outline : Icons.shield_outlined),
          ),
        if (wide) ...[
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    _u.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _u.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _u.clinic.isNotEmpty ? _u.clinic : _u.email,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Uygulama Kilidi',
            onPressed: _onLockPressed,
            icon: Icon(_u.hasPin ? Icons.lock_outline : Icons.shield_outlined),
          ),
        ],
        IconButton(
          tooltip: 'Oturumu Kapat',
          onPressed: _logout,
          icon: const Icon(Icons.logout),
        ),
      ],
    );
  }

  /// Senkronizasyon rozeti: verinin sunucuda olup olmadığını her an gösterir.
  ///
  /// Sessizce başarısız olan bir yazma artık fark edilemez değildir; hata
  /// durumunda rozet kırmızıya döner ve kullanıcı "Şimdi dene" ile yeniden
  /// deneyebilir.
  Widget _syncBadge(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.data,
      builder: (context, _) {
        final status = widget.data.syncStatus;
        final (IconData icon, Color color, String tooltip) =
            _syncAppearance(status);
        return IconButton(
          key: const Key('sync-badge'),
          tooltip: tooltip,
          onPressed: () => _showSyncSheet(context, status),
          icon: Icon(icon, color: color, size: 20),
        );
      },
    );
  }

  (IconData, Color, String) _syncAppearance(SyncStatus status) {
    switch (status.phase) {
      case SyncPhase.idle:
        return (
          Icons.cloud_done_outlined,
          AppColors.muted,
          'Tüm veriler sunucuda'
        );
      case SyncPhase.syncing:
        return (Icons.cloud_sync_outlined, AppColors.primary, 'Kaydediliyor');
      case SyncPhase.pending:
        return (Icons.cloud_queue_outlined, AppColors.warning, 'Bekleyen kayıt');
      case SyncPhase.offline:
        return (Icons.cloud_off_outlined, AppColors.muted, 'Çevrimdışı');
      case SyncPhase.error:
        return (Icons.cloud_off_outlined, AppColors.danger, 'Sunucuya kaydedilemedi');
    }
  }

  /// Durum ayrıntısı ve elle yeniden deneme.
  Future<void> _showSyncSheet(
    BuildContext context,
    SyncStatus status,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Veri durumu',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _syncMessage(status),
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('sync-retry'),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await widget.data.retrySyncNow();
                      },
                      child: const Text('Şimdi dene'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _syncMessage(SyncStatus status) {
    switch (status.phase) {
      case SyncPhase.idle:
        return 'Tüm değişiklikleriniz sunucuda güvenle saklanıyor.';
      case SyncPhase.syncing:
        return 'Değişiklikleriniz sunucuya gönderiliyor.';
      case SyncPhase.pending:
        return 'Değişiklikleriniz bu cihazda güvende. Sunucuya gönderilmek için '
            'bekliyor.';
      case SyncPhase.offline:
        return 'Sunucuya ulaşılamıyor. Verileriniz yalnızca bu cihazda duruyor; '
            'bağlantı gelince kendiliğinden gönderilecek.';
      case SyncPhase.error:
        final detail = status.message;
        final base = 'Son değişiklikler sunucuya kaydedilemedi. Verileriniz bu '
            'cihazda güvende ve arka planda tekrar denenecek.';
        return detail == null ? base : '$base\n\n$detail';
    }
  }

  List<_NavItem> get _currentNavItems {
    final List<_NavItem> items = List.from(
      _navItems.take(_navItems.length - 1),
    );
    if (_selectedMode == AppMode.commercial) {
      items.add(
        const _NavItem(
          'finance',
          'Muhasebe',
          Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet,
          'Ödeme takibi.',
        ),
      );
    }
    items.add(_navItems.last); // Settings always last
    return items;
  }

  Widget _sidebar(BuildContext context) {
    final items = _currentNavItems;
    return Container(
      width: 230,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    'ANA MENÜ',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: .08,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (var i = 0; i < items.length; i++)
                  _sidebarItem(context, i, items[i]),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bg2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: AppColors.primaryDark,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Gizlilik',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Klinik verileriniz bağlı sunucu hesabıyla eşitlenir.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(BuildContext context, int i, _NavItem item) {
    final active = i == _index;
    return InkWell(
      onTap: () {
        _tick();
        setState(() => _index = i);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              active ? item.activeIcon : item.icon,
              size: 19,
              color: active ? AppColors.primaryDark : AppColors.text2,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.primaryDark : AppColors.text2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomNav(BuildContext context) {
    final items = _currentNavItems;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                _bottomItem(context, i, items[i]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomItem(BuildContext context, int i, _NavItem item) {
    final active = i == _index;
    return InkWell(
      onTap: () {
        _tick();
        setState(() => _index = i);
      },
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? item.activeIcon : item.icon,
              size: 22,
              color: active ? AppColors.primary : AppColors.muted,
            ),
            const SizedBox(height: 3),
            Text(
              item.label.length > 12
                  ? '${item.label.substring(0, 12)}…'
                  : item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: active ? AppColors.primary : AppColors.muted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goTab(String id) {
    final items = _currentNavItems;
    final i = items.indexWhere((e) => e.id == id);
    if (i >= 0) setState(() => _index = i);
  }

  Widget _content() {
    final List<Widget> views = [
      OverviewTab(account: _u, data: widget.data, onNavigate: _goTab),
      FormsTab(data: widget.data),
      ClientsTab(data: widget.data, onNavigate: _goTab),
      AppointmentsTab(data: widget.data),
      ReportsTab(data: widget.data),
      TasksTab(data: widget.data),
      PdfsTab(data: widget.data),
    ];

    if (_selectedMode == AppMode.commercial) {
      views.add(FinanceTab(data: widget.data));
    }

    views.add(
      SettingsTab(
        data: widget.data,
        onProfileChanged: () => setState(() {}),
        onLockRequest: _lock,
        onNavigate: _goTab,
        onLogout: _logout,
      ),
    );

    final safeIndex = _index.clamp(0, views.length - 1);
    return IndexedStack(index: safeIndex, children: views);
  }
}

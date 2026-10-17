import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/app_constants.dart';
import '../../data/models/notification_record.dart';
import '../../state/family_state.dart';
import '../../state/garden_state.dart';
import '../../state/notification_state.dart';
import '../../state/theme_state.dart';
import '../widgets/motion_widgets.dart';
import 'app_nav_bar.dart';

/// 主壳：底部导航 + 通知轮询（对应 Web 版 `src/layouts/MainLayout.tsx`）。
///
/// 轮询**不在 store 里**，在这里：15 秒一次，页面不可见时跳过，
/// 回到前台立刻补一次；家长身份额外刷新待审批。
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final garden = context.read<GardenState>();
    if (state == AppLifecycleState.resumed) {
      garden.setAppVisible(true);
      _tick();
    } else {
      garden.setAppVisible(false);
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConstants.notificationPollInterval, (_) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      _tick();
    });
  }

  void _tick() {
    if (!mounted) return;
    final family = context.read<FamilyState>();
    final notifications = context.read<NotificationState>();
    unawaited(notifications.refresh());
    if (family.role == FamilyRole.parent) unawaited(family.refreshPending());
  }

  int _indexForLocation(String location) {
    // 顺序要紧：`/family/plan` 必须先于 `/family` 判断
    if (location.startsWith('/family/plan')) return 2;
    if (location.startsWith('/family')) return 1;
    if (location.startsWith('/garden')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  static const List<String> _locations = <String>[
    '/home',
    '/family',
    '/family/plan',
    '/garden',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexForLocation(location);
    final unread = context.select<NotificationState, int>((state) => state.unreadCount);
    final pending = context.select<FamilyState, int>((state) => state.pendingCount);
    final isParent = context.select<FamilyState, bool>((state) => state.role == FamilyRole.parent);
    final hasBackground = context.select<ThemeState, bool>(
      (ThemeState state) => state.background.isNotEmpty,
    );

    return Scaffold(
      // 换 Tab 时内容横向滑入淡出 —— 比硬切更容易看清「去了哪一格」
      body: SlideFadeSwitcher(
        childKey: ValueKey<String>(location),
        offset: 16,
        child: widget.child,
      ),
      // 悬浮胶囊底栏：选中靠弹簧透镜滑过去（跟手、会果冻），整条还随按下膨胀
      bottomNavigationBar: SafeArea(
        top: false,
        child: AppNavBar(
          selectedIndex: index,
          hasBackground: hasBackground,
          onSelected: (value) => context.go(_locations[value]),
          destinations: <AppNavDestination>[
            AppNavDestination(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: '首页',
              badge: unread,
            ),
            AppNavDestination(
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long,
              label: '家庭',
              badge: isParent ? pending : 0,
            ),
            const AppNavDestination(
              icon: Icons.calendar_month_outlined,
              selectedIcon: Icons.calendar_month,
              label: '计划',
            ),
            const AppNavDestination(
              icon: Icons.local_florist_outlined,
              selectedIcon: Icons.local_florist,
              label: '花园',
            ),
            const AppNavDestination(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}

/// 通知页需要的身份枚举（避免各处重复写 role → audience 的映射）
NotifyAudience audienceOf(FamilyRole? role) =>
    role == FamilyRole.parent ? NotifyAudience.parent : NotifyAudience.child;

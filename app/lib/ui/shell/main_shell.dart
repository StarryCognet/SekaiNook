import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/app_constants.dart';
import '../../data/models/app_update.dart';
import '../../data/models/notification_record.dart';
import '../../fl_ui/icons/icons.dart';
import '../../fl_ui/navigation_dock.dart';
import '../../state/family_state.dart';
import '../../state/garden_state.dart';
import '../../state/notification_state.dart';
import '../../state/update_state.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/update_dialog.dart';
import 'app_top_bar.dart';
import 'back_intent.dart';

/// 主壳：全局顶栏 + 底部导航 + 通知轮询（对应 Web 版 `src/layouts/MainLayout.tsx`）。
///
/// 轮询**不在 store 里**，在这里：10 秒一次（`AppConstants.notificationPollInterval`），
/// 页面不可见时跳过，回到前台立刻补一次；家长身份额外刷新待审批 ——
/// 但当前页面自己也在轮询待审批时让路（见 `_currentPageRefreshesPending`）。
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  Timer? _timer;
  late final UpdateState _update;

  /// 页面内的层级（设置分区、全站自检…）先在这里登记，返回键来了先问它们
  final BackIntentDispatcher _backIntent = BackIntentDispatcher();

  /// 走过的页面，返回到上一步用；同一页只换参数（花园菜单、家庭分区）不算新的一步
  final List<String> _backStack = <String>[];
  String _currentLocation = '';

  /// 一次会话只问一次「要不要更新」，点过「以后再说」也不再追问
  bool _updatePrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _update = context.read<UpdateState>();
    _update.addListener(_onUpdateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
    // 静默检查可能比这个壳先跑完（没登录时壳还没建），补看一次有没有已经拿到的版本
    WidgetsBinding.instance.addPostFrameCallback((_) => _onUpdateChanged());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _update.removeListener(_onUpdateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 有新版本就弹一次窗。通知可能在 build 过程中发出来，所以延到下一帧再弹。
  void _onUpdateChanged() {
    if (_updatePrompted || !mounted || _update.pending == null) return;
    _updatePrompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptUpdate());
  }

  Future<void> _promptUpdate() async {
    if (!mounted) return;
    final AppUpdateInfo? info = _update.pending;
    if (info == null) return;
    await promptUpdate(context, update: _update, info: info);
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
    // 待审批：当前页面自己也在轮询时让路 —— 否则同一个接口每 10s 被两个源各打一次
    //（首页 20s loadLedger、家庭页家长 10s refreshPending 都会顺带刷新待审批）。
    if (family.role == FamilyRole.parent && !_currentPageRefreshesPending()) {
      unawaited(family.refreshPending());
    }
  }

  /// 这些页面自己有轮询、且都会顺带刷新待审批，主壳不再重复发。
  bool _currentPageRefreshesPending() {
    if (_currentLocation.isEmpty) return false;
    final path = Uri.parse(_currentLocation).path;
    return path == '/home' || path == '/family';
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

  /// 记一步页面：整条路径变了才算新的一步
  void _recordLocation(String location) {
    if (location == _currentLocation) return;
    if (_currentLocation.isNotEmpty &&
        Uri.parse(location).path != Uri.parse(_currentLocation).path) {
      _backStack.add(_currentLocation);
      if (_backStack.length > 20) _backStack.removeAt(0);
    }
    _currentLocation = location;
  }

  /// 系统返回键：先让页面内层关，再退回上一个页面，真的没地方退了才退出 App
  void _handleSystemBack() {
    if (_backIntent.dispatch()) return;
    if (_backStack.isEmpty) {
      SystemNavigator.pop();
      return;
    }
    final String target = _backStack.removeLast();
    // 先认账，免得这次「回退」又被当成往前走了一步
    _currentLocation = target;
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    _recordLocation(location);
    final index = _indexForLocation(location);
    final unread = context.select<NotificationState, int>((state) => state.unreadCount);
    final pending = context.select<FamilyState, int>((state) => state.pendingCount);
    final isParent = context.select<FamilyState, bool>((state) => state.role == FamilyRole.parent);

    return BackIntentScope(
      dispatcher: _backIntent,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;
          _handleSystemBack();
        },
        child: Scaffold(
          // 上下两条都是真悬浮：body 铺满整屏，顶栏与底栏各是浮在内容之上的一层 ——
          // 内容能从胶囊后面滚过去，不再被硬切走一条。
          //
          // `extendBody: true` 时 Scaffold 会往 body 的 MediaQuery 里塞一条
          // `padding.bottom = 底栏高度`（实测 74），好让页面里的 `SafeArea`
          // 替底栏让位 —— 可页面一让位，内容区又被截在胶囊上方，看着跟没悬浮一样。
          // 所以这里把这条 padding 抹掉；手势条的真实高度留在 `viewPadding` 里
          // （各页 `AppNavBar.contentInset` 要读它），滚到底不压胶囊由列表自己的
          // 底部 padding 负责。顶部照同一套办：`padding.top` 也抹掉，
          // 各页 `AppTopBar.contentInset` 从 `viewPadding` 里拿真实状态栏高度自己让位。
          extendBody: true,
          body: Stack(
            // `StackFit.expand`：默认的 `loose` 下 Stack 会缩到内容大小，
            // `Positioned(left: 0, right: 0)` 的顶栏就只剩正文那么宽（实测 28.5px），
            // 右边两件直接落到条外 —— 布局看着对，点击全打空。
            fit: StackFit.expand,
            children: <Widget>[
              MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: MediaQuery.of(context).padding.copyWith(top: 0, bottom: 0),
                ),
                // 换 Tab 时内容横向滑入淡出 —— 比硬切更容易看清「去了哪一格」
                child: SlideFadeSwitcher(
                  childKey: ValueKey<String>(location),
                  offset: 16,
                  child: widget.child,
                ),
              ),
              // 全局顶栏（Web 版 MainLayout 的 Header）：浮在内容之上的一层，
              // 左边当前页、右边铃铛与深浅开关。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AppTopBarHost(location: location),
              ),
            ],
          ),
          // 悬浮胶囊底栏：FlClash lib/ui 的 NavigationDock（弹簧透镜跟手 + 按下膨胀）
          bottomNavigationBar: NavigationDock(
            selectedIndex: index,
            onSelected: (value) => context.go(_locations[value]),
            destinations: <NavigationDockDestination>[
              NavigationDockDestination(
                glyph: AppGlyphs.dashboard,
                label: '首页',
                badge: unread,
              ),
              NavigationDockDestination(
                glyph: AppGlyphs.profiles,
                label: '家庭',
                badge: isParent ? pending : 0,
              ),
              const NavigationDockDestination(
                glyph: AppGlyphs.requests,
                label: '计划',
              ),
              const NavigationDockDestination(
                glyph: AppGlyphs.sparkle,
                label: '花园',
              ),
              const NavigationDockDestination(
                glyph: AppGlyphs.settings,
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 通知页需要的身份枚举（避免各处重复写 role → audience 的映射）
NotifyAudience audienceOf(FamilyRole? role) =>
    role == FamilyRole.parent ? NotifyAudience.parent : NotifyAudience.child;

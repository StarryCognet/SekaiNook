import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'state/family_state.dart';
import 'ui/pages/family/family_dashboard_page.dart';
import 'ui/pages/family/weekly_plan_page.dart';
import 'ui/pages/garden/garden_page.dart';
import 'ui/pages/home/kid_home_page.dart';
import 'ui/pages/home/notifications_page.dart';
import 'ui/pages/home/parent_home_page.dart';
import 'ui/pages/role_gate_page.dart';
import 'ui/pages/settings/settings_page.dart';
import 'ui/pages/ui_preview_page.dart';
import 'ui/shell/main_shell.dart';
import 'ui/shell/route_cover.dart';

/// 路由表（对应 Web 版 `src/App.tsx`）。
///
/// `/` 落到 `/home`；未选身份先去 `/role`（**不能缺省为家长**）。
/// 六个页面全部挂在 [MainShell] 下（对应 Web 版 `MainLayout` 包住所有页面），
/// 所以通知页与周计划页也带底部导航。
///
/// [roleRefresh] 由调用方（`app.dart`）持有并负责 dispose：只有「身份变化」才 notify，
/// 账本刷新不重跑 redirect、不重建整张路由表。
GoRouter createRouter(
  FamilyState family,
  ValueNotifier<FamilyRole?> roleRefresh,
  RouteCoverState routeCover,
) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: roleRefresh,
    observers: <NavigatorObserver>[routeCover.observer],
    redirect: (BuildContext context, GoRouterState state) {
      final path = state.uri.path;
      // 试样间不依赖身份，也不该被踢去 /role —— 没选身份也能进去看看。
      if (path == '/ui-preview') return null;
      if (family.role == null) {
        return path == '/role' ? null : '/role';
      }
      if (path == '/role') return '/home';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/role',
        builder: (BuildContext context, GoRouterState state) => const RoleGatePage(),
      ),
      GoRoute(
        path: '/ui-preview',
        builder: (BuildContext context, GoRouterState state) => const UiPreviewPage(),
      ),
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            MainShell(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/home',
            builder: (BuildContext context, GoRouterState state) => const HomeSwitcher(),
          ),
          GoRoute(
            path: '/family',
            builder: (BuildContext context, GoRouterState state) => const FamilyDashboardPage(),
          ),
          GoRoute(
            path: '/home/notifications',
            builder: (BuildContext context, GoRouterState state) => const NotificationsPage(),
          ),
          GoRoute(
            path: '/family/plan',
            builder: (BuildContext context, GoRouterState state) => const WeeklyPlanPage(),
          ),
          GoRoute(
            path: '/garden',
            builder: (BuildContext context, GoRouterState state) => const GardenPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (BuildContext context, GoRouterState state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
}

/// 首页按身份分两版：妹妹版（打卡赚钱）/ 妈妈版（审批管账）
class HomeSwitcher extends StatelessWidget {
  const HomeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.select<FamilyState, FamilyRole?>((state) => state.role);
    return role == FamilyRole.parent ? const ParentHomePage() : const KidHomePage();
  }
}

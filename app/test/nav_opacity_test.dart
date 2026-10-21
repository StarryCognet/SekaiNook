import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sekainook_app/config/app_constants.dart';
import 'package:sekainook_app/core/api_client.dart';
import 'package:sekainook_app/data/api/settings_api.dart';
import 'package:sekainook_app/fl_ui/navigation_dock.dart';
import 'package:sekainook_app/state/theme_state.dart';
import 'package:sekainook_app/theme/tokens.dart';
import 'package:sekainook_app/ui/shell/app_nav_bar.dart';

/// 底栏真悬浮之后的两条硬约束：
/// ① **默认必须不透明** —— 半透明是用户自己在设置里调出来的，不能默认给全家看到；
/// ② 「页面要让出多少」的算式 —— 算少了滚到底最后一条就压在胶囊下面。
///
/// 这里不测「好不好看」，只测这两条容易悄悄改坏的事。
void main() {
  ThemeState theme(SharedPreferences prefs) =>
      ThemeState(prefs: prefs, settingsApi: SettingsApi(ApiClient()));

  group('底栏不透明度', () {
    test('默认完全不透明：没调过就是实心', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(theme(prefs).navBarOpacity, ThemeState.navOpacityOpaque);
    });

    test('改了就落盘，重开 App 还是那个值', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeState state = theme(prefs);
      await state.setNavBarOpacity(0.72);
      expect(state.navBarOpacity, closeTo(0.72, 1e-9));
      expect(prefs.getDouble(AppConstants.keyNavBarOpacity), closeTo(0.72, 1e-9));
      // 重开 App = 重新构造，值要从盘里读回来
      expect(theme(prefs).navBarOpacity, closeTo(0.72, 1e-9));
    });

    test('低于下限会被夹住（再低字就糊了）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeState state = theme(prefs);
      await state.setNavBarOpacity(0.1);
      expect(state.navBarOpacity, ThemeState.navOpacityMin);
    });

    test('盘里存了越界的脏值也夹回合法区间', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppConstants.keyNavBarOpacity: 5.0,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(theme(prefs).navBarOpacity, ThemeState.navOpacityOpaque);
    });

    test('值没变就不通知（拖到同一个点不该白刷一遍）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeState state = theme(prefs);
      int notified = 0;
      state.addListener(() => notified++);
      await state.setNavBarOpacity(0.72);
      expect(notified, 1);
      await state.setNavBarOpacity(0.72);
      expect(notified, 1);
    });
  });

  testWidgets('让位高度 = NavigationDock 高度 + 底部安全区 + 一点呼吸', (WidgetTester tester) async {
    late double inset;
    late double expected;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47, bottom: 34),
            viewPadding: EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: Builder(
            builder: (BuildContext context) {
              inset = AppNavBar.contentInset(context);
              // NavigationDock 自己算「条高 + max(离底间距, 安全区)」
              expected = NavigationDock.heightOf(context) + 34 + AppSpacing.sm;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(inset, closeTo(expected, 1e-9));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sekainook_app/core/api_client.dart';
import 'package:sekainook_app/data/api/notification_api.dart';
import 'package:sekainook_app/data/api/settings_api.dart';
import 'package:sekainook_app/state/notification_state.dart';
import 'package:sekainook_app/state/theme_state.dart';
import 'package:sekainook_app/theme/app_theme.dart';
import 'package:sekainook_app/theme/tokens.dart';
import 'package:sekainook_app/ui/shell/app_top_bar.dart';

/// 全局顶栏的回归测试。
///
/// 守五件事：① location → 页面名 / 图标 的推法（含先例顺序那个坑）；
/// ② 铃铛的未读角标与点击；③ 深浅开关「点另一档才切、点当前这档不动」；
/// ④ 真悬浮时高度算得对（状态栏自己让、正文从屏幕顶开始、`contentInset` 算得对、窄屏不溢出）；
/// ⑤ 接线层 `AppTopBarHost` 在真 store（`ThemeState`）上点一下真的换主题。
///
/// 前四组都是**裸 pump**（一层 Provider 都没有）—— 顶栏本体刻意不读 Provider
/// （接线在 `AppTopBarHost`），哪天有人在里面 `context.watch` 一下，那几组就会红。
/// 最后一组反过来：只喂 `AppTopBarHost` 需要的两个 store，不算 `MainShell`。
void main() {
  group('页面名与图标跟着 location 走', () {
    test('五个 Tab 加通知页各自认领', () {
      expect(AppTopBarPage.of('/home').label, '首页');
      expect(AppTopBarPage.of('/family').label, '家庭账本');
      expect(AppTopBarPage.of('/family/plan').label, '学习计划');
      expect(AppTopBarPage.of('/garden').label, '阳光花园');
      expect(AppTopBarPage.of('/settings').label, '设置');
      expect(AppTopBarPage.of('/home/notifications').label, '通知');
    });

    test('先例顺序：/home/notifications 不能落成首页、/family/plan 不能落成家庭账本', () {
      expect(AppTopBarPage.of('/home/notifications').icon, Icons.notifications_outlined);
      expect(AppTopBarPage.of('/family/plan').icon, Icons.calendar_month_outlined);
      expect(AppTopBarPage.of('/family').icon, Icons.receipt_long_outlined);
      expect(AppTopBarPage.of('/home').icon, Icons.home_outlined);
    });

    test('带 query 或子路径也认得出，认不出的兜底回首页', () {
      expect(AppTopBarPage.of('/garden?menu=poem').label, '阳光花园');
      expect(AppTopBarPage.of('/settings/about').label, '设置');
      expect(AppTopBarPage.of('/').label, '首页');
      expect(AppTopBarPage.of('/whatever').label, '首页');
    });
  });

  Future<_TapLog> pumpTopBar(
    WidgetTester tester, {
    AppTopBarPage page = AppTopBarPage.home,
    int unread = 0,
    bool dark = false,
    bool hasBackground = false,
    double topPadding = 0,
  }) async {
    final _TapLog log = _TapLog();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(dark ? ThemeId.midnight : ThemeId.original),
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            // 只改状态栏高度，其余（尺寸 / 方向）照旧从真实窗口来。
            // `viewPadding` 也要一起给：顶栏的 `contentInset` 读的是它
            // （真机上两者都是状态栏高度，只是 `padding` 会被外壳抹掉）。
            data: MediaQuery.of(context).copyWith(
              padding: EdgeInsets.only(top: topPadding),
              viewPadding: EdgeInsets.only(top: topPadding),
            ),
            // 照 `MainShell` 的挂法：顶栏是 `Stack` 里浮在内容之上的一层，
            // body 的 `MediaQuery.padding.top` 被抹掉 —— 内容从屏幕顶铺下来，
            // 由各页自己的 `AppTopBar.contentInset` 让位。
            child: Scaffold(
              body: Stack(
                // 与 MainShell 一致：不给 expand 的话 Stack 会缩到正文大小，
                // `Positioned(left: 0, right: 0)` 的顶栏就只剩 28.5px 宽。
                fit: StackFit.expand,
                children: <Widget>[
                  MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.of(context).padding.copyWith(top: 0),
                    ),
                    child: const SafeArea(child: Text('正文')),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AppTopBar(
                      page: page,
                      unread: unread,
                      hasBackground: hasBackground,
                      onNotifications: () => log.notifications++,
                      onToggleBrightness: () => log.brightness++,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return log;
  }

  testWidgets('左边是当前页名，右边铃铛可点、点了只走通知', (WidgetTester tester) async {
    final _TapLog log = await pumpTopBar(tester);

    expect(find.text('首页'), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.text('0'), findsNothing, reason: '没未读就不该挂角标');

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    expect(log.notifications, 1);
    expect(log.brightness, 0, reason: '点铃铛不该顺手把主题切了');
  });

  testWidgets('未读角标：7 显示 7，超过 99 显示 99+', (WidgetTester tester) async {
    await pumpTopBar(tester, unread: 7);
    expect(find.text('7'), findsOneWidget);

    await pumpTopBar(tester, unread: 120);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('浅色时：点月亮切一次，点太阳（当前这档）不动', (WidgetTester tester) async {
    final _TapLog log = await pumpTopBar(tester);

    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await tester.pump();
    expect(log.brightness, 0, reason: '已经在浅色，点太阳不该把用户弹到深色去');

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pump();
    expect(log.brightness, 1);
  });

  testWidgets('深色时：点太阳切一次，点月亮（当前这档）不动', (WidgetTester tester) async {
    final _TapLog log = await pumpTopBar(tester, dark: true);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pump();
    expect(log.brightness, 0);

    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await tester.pump();
    expect(log.brightness, 1);
  });

  testWidgets('真悬浮：顶栏不占布局（盖在内容上），让位交给 contentInset', (WidgetTester tester) async {
    await pumpTopBar(tester, topPadding: 44);
    expect(tester.takeException(), isNull, reason: '高度算歪了会在这里以溢出报出来');

    // preferredSize 只报条自身高度（60），状态栏那 44 由顶栏内部 SafeArea 吃掉
    expect(
      tester.getBottomLeft(find.byType(AppTopBar)).dy,
      moreOrLessEquals(44 + AppTopBar.preferredBarSize.height),
    );
    // 悬浮的关键：body 的 padding.top 被抹掉，正文从屏幕最顶开始 ——
    // 顶栏是盖在它上面的一层，不是把它推下去
    expect(tester.getTopLeft(find.text('正文')).dy, moreOrLessEquals(0));
    // 各页要自己让的高度 = 状态栏 + 条自身高 + 一道气口（与 AppNavBar.contentInset 对称）
    expect(
      AppTopBar.contentInset(tester.element(find.byType(AppTopBar))),
      moreOrLessEquals(44 + AppTopBar.topMargin + AppTopBar.innerHeight + AppSpacing.sm),
    );
  });

  testWidgets('窄屏 + 超长页面名：只截断，不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpTopBar(
      tester,
      page: const AppTopBarPage(
        label: '这是一个特别特别长的页面名用来把胶囊撑爆',
        icon: Icons.home_outlined,
      ),
      unread: 3,
    );

    expect(tester.takeException(), isNull);
    // 省略号截断走的是 Text.overflow，data 仍是全名
    expect(find.text('这是一个特别特别长的页面名用来把胶囊撑爆'), findsOneWidget);
    // 右侧两件（铃铛 / 深浅开关）没被挤走
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });

  testWidgets('有背景图时不炸（走玻璃底那一档色）', (WidgetTester tester) async {
    await pumpTopBar(tester, hasBackground: true, unread: 1);
    expect(tester.takeException(), isNull);
    expect(find.text('首页'), findsOneWidget);
  });

  group('接线层（AppTopBarHost）', () {
    /// 滑块（托着当前那一档的圆）在右边 = 正托着月亮
    Finder knobOnRight() => find.byWidgetPredicate(
          (Widget widget) =>
              widget is AnimatedAlign && widget.alignment == Alignment.centerRight,
        );

    testWidgets('认得出当前页，点月亮真的把主题切过去', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeState theme = ThemeState(
        prefs: prefs,
        settingsApi: SettingsApi(ApiClient()),
      );
      // 这个 store 只被读 unreadCount（不发请求），铃铛角标由上面的裸 pump 测
      final NotificationState notifications = NotificationState(
        api: NotificationApi(ApiClient()),
      );
      addTearDown(theme.dispose);
      addTearDown(notifications.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<ThemeState>.value(value: theme),
            ChangeNotifierProvider<NotificationState>.value(value: notifications),
          ],
          // 照 app.dart 的写法让主题跟着 store 走 —— 顶栏换档后滑块要真的挪过去
          child: Consumer<ThemeState>(
            builder: (BuildContext context, ThemeState state, Widget? child) => MaterialApp(
              theme: AppTheme.build(state.themeId, hasBackground: state.hasBackground),
              home: const Scaffold(
                body: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    SizedBox.shrink(),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AppTopBarHost(location: '/settings'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(AppTheme.preset(theme.themeId).dark, isFalse, reason: '出厂是浅色');
      expect(knobOnRight(), findsNothing);

      // 点月亮：走的就是设置页那颗按钮用的同一条路（ThemeState.toggleBrightness）
      await tester.tap(find.byIcon(Icons.dark_mode_outlined));
      await tester.pumpAndSettle();
      expect(AppTheme.preset(theme.themeId).dark, isTrue);
      expect(knobOnRight(), findsOneWidget, reason: '滑块要托到月亮那一档');

      await tester.tap(find.byIcon(Icons.light_mode_outlined));
      await tester.pumpAndSettle();
      expect(AppTheme.preset(theme.themeId).dark, isFalse);
      expect(knobOnRight(), findsNothing);
    });
  });
}

/// 回调记账：两条回调都只看次数（顶栏自身没有别的副作用）
class _TapLog {
  int notifications = 0;
  int brightness = 0;
}

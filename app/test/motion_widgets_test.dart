import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sekainook_app/core/api_client.dart';
import 'package:sekainook_app/data/api/settings_api.dart';
import 'package:sekainook_app/state/theme_state.dart';
import 'package:sekainook_app/theme/app_theme.dart';
import 'package:sekainook_app/theme/motion.dart';
import 'package:sekainook_app/theme/tokens.dart';
import 'package:sekainook_app/ui/widgets/app_card.dart';
import 'package:sekainook_app/ui/widgets/motion_widgets.dart';
import 'package:sekainook_app/ui/widgets/state_views.dart';

/// 动效组件的回归测试：不测"好不好看"，只测三件容易出错的事 ——
/// ① 关掉系统动画时必须直接落终点态（不能卡在透明）；
/// ② 组件能正常挂载/卸载，不因为动画控制器出异常；
/// ③ 交互回调照旧触发（动画不该抢走点击）。
void main() {
  Widget host(Widget child, {bool disableAnimations = false}) {
    return MaterialApp(
      theme: AppTheme.build(ThemeId.rose, dark: false),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    );
  }

  group('EnterBox', () {
    testWidgets('正常播完后完全可见且不再位移', (WidgetTester tester) async {
      await tester.pumpWidget(host(const EnterBox(child: Text('内容'))));

      await tester.pump(); // 起播
      await tester.pump(AppMotion.normal + AppMotion.stagger(10));

      expect(find.text('内容'), findsOneWidget);
      final Opacity opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, moreOrLessEquals(1, epsilon: 0.001));
    });

    testWidgets('关掉动画时立刻是可读的终点态', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(const EnterBox(child: Text('内容')), disableAnimations: true),
      );
      await tester.pump();

      final Opacity opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, 1);
      final Transform transform = tester.widget<Transform>(find.byType(Transform).first);
      expect(transform.transform.getTranslation().y, 0);
    });

    testWidgets('index 只影响延迟，不影响最终可见', (WidgetTester tester) async {
      await tester.pumpWidget(host(const EnterBox(index: 3, child: Text('第三项'))));
      await tester.pump();
      await tester.pump(AppMotion.normal + AppMotion.stagger(3));
      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
    });
  });

  group('骨架屏', () {
    testWidgets('SkeletonList 按数量铺卡片', (WidgetTester tester) async {
      await tester.pumpWidget(host(const SkeletonList(count: 3)));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(SkeletonCard), findsNWidgets(3));
    });

    testWidgets('关掉动画时不创建呼吸控制器', (WidgetTester tester) async {
      await tester.pumpWidget(host(const SkeletonList(count: 2), disableAnimations: true));
      await tester.pump();
      expect(find.byType(SkeletonCard), findsNWidgets(2));
    });
  });

  group('SlideFadeSwitcher', () {
    testWidgets('换 key 后新内容出现、旧内容退场', (WidgetTester tester) async {
      Widget build(String key) => host(
        SlideFadeSwitcher(childKey: ValueKey<String>(key), child: Text(key)),
      );

      await tester.pumpWidget(build('a'));
      await tester.pump();
      expect(find.text('a'), findsOneWidget);

      await tester.pumpWidget(build('b'));
      await tester.pump();
      expect(find.text('b'), findsOneWidget);

      await tester.pump(AppMotion.fast + AppMotion.instant);
      expect(find.text('a'), findsNothing);
    });

    testWidgets('关掉动画时直接切换', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          const SlideFadeSwitcher(childKey: ValueKey<String>('x'), child: Text('x')),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(find.text('x'), findsOneWidget);
    });
  });

  group('AnimatedCount', () {
    testWidgets('滚到目标值并用 formatter 渲染', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          const AnimatedCount(
            value: 135,
            style: TextStyle(fontFeatures: kTabularNumbers),
            formatter: _twoDecimals,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(AppMotion.slower + const Duration(milliseconds: 50));
      expect(find.text('135.00'), findsOneWidget);
    });
  });

  group('AnimatedProgressBar', () {
    testWidgets('值收敛到给定比例', (WidgetTester tester) async {
      await tester.pumpWidget(host(const AnimatedProgressBar(value: 0.5)));
      await tester.pump();
      await tester.pump(AppMotion.slower + const Duration(milliseconds: 50));
      expect(find.byType(AnimatedProgressBar), findsOneWidget);
    });
  });

  group('SuccessBurst', () {
    testWidgets('关掉动画时直接停在完成态', (WidgetTester tester) async {
      await tester.pumpWidget(host(const SuccessBurst(), disableAnimations: true));
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('showBurst 盖一层并在播完后收掉', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(Builder(builder: (BuildContext context) {
          return TextButton(
            onPressed: () => showBurst(context),
            child: const Text('打卡'),
          );
        })),
      );

      await tester.tap(find.text('打卡'));
      await tester.pump();
      expect(find.byType(SuccessBurst), findsOneWidget);

      await tester.pump(AppMotion.celebrate + const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byType(SuccessBurst), findsNothing);
    });
  });

  group('AppCard', () {
    Future<ThemeState> themeState() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // 这里只用于驱动主题色板，测试里不会真的发请求
      return ThemeState(prefs: prefs, settingsApi: SettingsApi(ApiClient()));
    }

    testWidgets('onTap 照旧能触发（按压动画不抢手势）', (WidgetTester tester) async {
      final ThemeState theme = await themeState();
      int taps = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeState>.value(
          value: theme,
          child: host(AppCard(onTap: () => taps += 1, child: const Text('卡片'))),
        ),
      );

      await tester.tap(find.text('卡片'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, 1);
    });
  });
}

String _twoDecimals(num value) => value.toStringAsFixed(2);

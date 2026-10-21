import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/ui/shell/app_nav_bar.dart';
import 'package:sekainook_app/ui/icons/icons.dart';

/// 底部导航（FlClash 风格弹簧透镜）的回归测试。
///
/// 这几条断言守的是「指针主线」：按下 → 透镜跟手 → 松手落位并回调，
/// 以及开了「减少动态效果」时不崩、仍然能选中。
void main() {
  const List<AppNavDestination> destinations = <AppNavDestination>[
    AppNavDestination(icon: AppIcons.home, selectedIcon: AppIcons.home, label: '首页', badge: 3),
    AppNavDestination(
      icon: AppIcons.receipt,
      selectedIcon: AppIcons.receipt,
      label: '家庭',
    ),
    AppNavDestination(
      icon: AppIcons.calendar,
      selectedIcon: AppIcons.calendar,
      label: '计划',
    ),
    AppNavDestination(
      icon: AppIcons.flower,
      selectedIcon: AppIcons.flower,
      label: '花园',
    ),
    AppNavDestination(
      icon: AppIcons.settings,
      selectedIcon: AppIcons.settings,
      label: '设置',
    ),
  ];

  Future<List<int>> pumpBar(
    WidgetTester tester, {
    int selectedIndex = 0,
    bool disableAnimations = false,
  }) async {
    final List<int> picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            bottomNavigationBar: AppNavBar(
              destinations: destinations,
              selectedIndex: selectedIndex,
              onSelected: picked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('五个 Tab 都在，角标显示数量', (WidgetTester tester) async {
    await pumpBar(tester);
    for (final AppNavDestination destination in destinations) {
      expect(find.text(destination.label), findsOneWidget);
    }
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('点第三格回调 2', (WidgetTester tester) async {
    final List<int> picked = await pumpBar(tester);
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    expect(picked, <int>[2]);
  });

  testWidgets('按住拖到最后一格，松手选中 4（跟手）', (WidgetTester tester) async {
    final List<int> picked = await pumpBar(tester);
    final Offset start = tester.getCenter(find.text('首页'));
    final Offset end = tester.getCenter(find.text('设置'));
    final TestGesture gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveTo(end);
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, <int>[4]);
  });

  testWidgets('开「减少动态效果」时直接落位，仍然能选中', (WidgetTester tester) async {
    final List<int> picked = await pumpBar(tester, disableAnimations: true);
    await tester.tap(find.text('花园'));
    await tester.pumpAndSettle();
    expect(picked, <int>[3]);
  });

  testWidgets('选中态语义标记跟着 selectedIndex 走', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpBar(tester, selectedIndex: 1);
    final SemanticsNode node = tester.getSemantics(find.bySemanticsLabel('家庭'));
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    handle.dispose();
  });
}

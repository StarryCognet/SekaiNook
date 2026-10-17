import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'floating_dock.dart';

/// 悬浮底栏的回归测试模板 —— 放进项目的 `test/` 目录即可跑。
///
/// 这几条断言守的是「指针主线」：按下 → 透镜跟手 → 松手落位并回调，
/// 以及开了「减少动态效果」时不崩、仍然能选中。
/// （透镜的视觉效果测不了，只能靠截图/真机看；能测的是行为与回调次数。）
void main() {
  const List<DockDestination> destinations = <DockDestination>[
    DockDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: '首页', badge: 3),
    DockDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: '家庭'),
    DockDestination(icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, label: '计划'),
    DockDestination(icon: Icons.local_florist_outlined, selectedIcon: Icons.local_florist, label: '花园'),
    DockDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '设置'),
  ];

  Future<List<int>> pumpDock(
    WidgetTester tester, {
    int selectedIndex = 0,
    bool disableAnimations = false,
    DockStyle style = const DockStyle(),
  }) async {
    final List<int> picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            // 放 bottomNavigationBar 槽位即可；想让它浮在内容之上就用
            // Stack + Positioned，并把 FloatingDock.reservedHeight 加进列表留白。
            bottomNavigationBar: FloatingDock(
              destinations: destinations,
              selectedIndex: selectedIndex,
              style: style,
              onSelected: picked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('每格都在，角标显示数量', (WidgetTester tester) async {
    await pumpDock(tester);
    for (final DockDestination destination in destinations) {
      expect(find.text(destination.label), findsOneWidget);
    }
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('点第三格只回调一次 2', (WidgetTester tester) async {
    final List<int> picked = await pumpDock(tester);
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    // 只回调一次 —— 如果格子里又挂了 InkWell/GestureDetector，这里会变成 [2, 2]
    expect(picked, <int>[2]);
  });

  testWidgets('按住拖到最后一格，松手选中 4（跟手）', (WidgetTester tester) async {
    final List<int> picked = await pumpDock(tester);
    final TestGesture gesture = await tester.startGesture(tester.getCenter(find.text('首页')));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveTo(tester.getCenter(find.text('设置')));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, <int>[4]);
  });

  testWidgets('拖动中途不改选中（松手才提交）', (WidgetTester tester) async {
    final List<int> picked = await pumpDock(tester);
    final TestGesture gesture = await tester.startGesture(tester.getCenter(find.text('首页')));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveTo(tester.getCenter(find.text('花园')));
    await tester.pump(const Duration(milliseconds: 40));
    expect(picked, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, <int>[3]);
  });

  testWidgets('开「减少动态效果」时直接落位，仍然能选中', (WidgetTester tester) async {
    final List<int> picked = await pumpDock(tester, disableAnimations: true);
    await tester.tap(find.text('花园'));
    await tester.pumpAndSettle();
    expect(picked, <int>[3]);
  });

  testWidgets('选中态语义标记跟着 selectedIndex 走', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpDock(tester, selectedIndex: 1);
    final SemanticsNode node = tester.getSemantics(find.bySemanticsLabel('家庭'));
    // 新版 SDK 用 Tristate 表达「选中」（旧写法 node.hasFlag(SemanticsFlag.isSelected)
    // 在 3.32 之后已废弃）
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('自定义样式与系统安全区都能吃下（不崩）', (WidgetTester tester) async {
    await pumpDock(
      tester,
      style: const DockStyle(
        height: 64,
        edgeMargin: 12,
        bottomMargin: 4,
        showLabels: false,
        showShadow: false,
        background: Color(0xCCFFFFFF),
        indicatorColor: Color(0xFF1A1A2E),
        selectedForeground: Colors.white,
      ),
    );
    expect(find.text('首页'), findsNothing); // showLabels: false
    expect(find.byIcon(Icons.home), findsOneWidget);
  });

  test('readableOn 在浅底给深字、深底给亮字', () {
    expect(readableOn(Colors.white).computeLuminance(), lessThan(0.2));
    expect(readableOn(Colors.black).computeLuminance(), greaterThan(0.7));
  });
}

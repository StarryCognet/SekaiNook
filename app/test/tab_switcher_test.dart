import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/theme/tab_transition.dart';
import 'package:sekainook_app/ui/widgets/motion/tab_switcher.dart';

/// 13 种整页转场共同的验收线（具体手感靠眼睛看，这里钉的是「别坏」）：
/// 1. 切换过程中**新旧两页同时存在** —— 否则说明退化成硬切了；
/// 2. 动画落地后旧页必须被移除，新页完全可见（不透明、没残留位移）；
/// 3. 全程不抛异常（裁剪/矩阵那些地方最容易在特定尺寸下炸）。
Widget _host(String page, TabTransition transition, {int direction = 1}) {
  return MaterialApp(
    home: Scaffold(
      body: TabTransitionSwitcher(
        childKey: ValueKey<String>(page),
        transition: transition,
        direction: direction,
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Center(child: Text(page)),
        ),
      ),
    ),
  );
}

void main() {
  for (final TabTransition transition in TabTransition.values) {
    testWidgets('${transition.id}：过渡期间两页同时在，落地只剩新页', (WidgetTester tester) async {
      await tester.pumpWidget(_host('旧页', transition));
      expect(find.text('旧页'), findsOneWidget);

      await tester.pumpWidget(_host('新页', transition));
      // 第一帧动画还没推进：AnimatedSwitcher 应该已经把两页都挂上
      await tester.pump();
      expect(find.text('旧页'), findsOneWidget, reason: '旧页应该还在退场');
      expect(find.text('新页'), findsOneWidget, reason: '新页应该已经开始进场');

      // 走到一半：各转场都在动，最不该出问题的时刻
      await tester.pump(transition.duration ~/ 2);
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(find.text('旧页'), findsNothing, reason: '动画结束后旧页必须被移除');
      expect(find.text('新页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${transition.id}：反向翻页（direction = -1）也正常', (WidgetTester tester) async {
      await tester.pumpWidget(_host('旧页', transition, direction: -1));
      await tester.pumpWidget(_host('新页', transition, direction: -1));
      await tester.pump(transition.duration ~/ 2);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('旧页'), findsNothing);
      expect(find.text('新页'), findsOneWidget);
    });
  }

  testWidgets('系统开了「减少动态效果」时不播任何动画，直接换', (WidgetTester tester) async {
    Widget build(String page) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              size: Size(400, 800),
              devicePixelRatio: 1,
            ),
            child: Scaffold(
              body: TabTransitionSwitcher(
                childKey: ValueKey<String>(page),
                transition: TabTransition.flip3d,
                direction: 1,
                child: Center(child: Text(page)),
              ),
            ),
          ),
        );

    await tester.pumpWidget(build('旧页'));
    await tester.pumpWidget(build('新页'));
    // 一帧都不用等：不该有过渡，旧页立刻消失
    await tester.pump();
    expect(find.text('旧页'), findsNothing);
    expect(find.text('新页'), findsOneWidget);
  });

  testWidgets('切到同一个 key 不重播动画（同一页换参数不该整页动一下）', (WidgetTester tester) async {
    await tester.pumpWidget(_host('同一页', TabTransition.paging));
    await tester.pumpWidget(_host('同一页', TabTransition.paging));
    await tester.pump();
    expect(find.text('同一页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

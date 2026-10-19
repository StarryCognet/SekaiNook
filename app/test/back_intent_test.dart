import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/ui/shell/back_intent.dart';

/// 系统返回键的分发：内层先关、外层兜底、登记随组件销毁一起撤掉。
///
/// 守的是一条踩过的坑：`ModalRoute` 把返回事件发给**所有**已注册的 `PopScope`，
/// 外壳和页面各挂一个会同时触发（既关分区又跳走）。所以这里必须是
/// 「按内到外问一遍，只让一个应声」。
void main() {
  test('内层应下就不再问外层', () {
    final BackIntentDispatcher dispatcher = BackIntentDispatcher();
    final List<String> asked = <String>[];

    dispatcher.add(() {
      asked.add('外层');
      return false;
    });
    dispatcher.add(() {
      asked.add('内层');
      return true;
    });

    expect(dispatcher.dispatch(), isTrue);
    expect(asked, <String>['内层']);
  });

  test('都没有可关的层就返回 false，交给外壳去退上一步 / 退出', () {
    final BackIntentDispatcher dispatcher = BackIntentDispatcher();
    final List<String> asked = <String>[];

    dispatcher.add(() {
      asked.add('外层');
      return false;
    });
    dispatcher.add(() {
      asked.add('内层');
      return false;
    });

    expect(dispatcher.dispatch(), isFalse);
    expect(asked, <String>['内层', '外层']);
  });

  test('撤销登记之后不再被问', () {
    final BackIntentDispatcher dispatcher = BackIntentDispatcher();
    bool Function()? handler;
    handler = () => true;

    dispatcher.add(handler);
    expect(dispatcher.dispatch(), isTrue);

    dispatcher.remove(handler);
    expect(dispatcher.dispatch(), isFalse);
  });

  testWidgets('BackIntentHandler 随挂载登记、随销毁撤销', (WidgetTester tester) async {
    final BackIntentDispatcher dispatcher = BackIntentDispatcher();
    int handled = 0;

    Widget build({required bool withHandler}) => MaterialApp(
          home: BackIntentScope(
            dispatcher: dispatcher,
            child: withHandler
                ? BackIntentHandler(
                    onBack: () {
                      handled += 1;
                      return true;
                    },
                    child: const SizedBox.shrink(),
                  )
                : const SizedBox.shrink(),
          ),
        );

    await tester.pumpWidget(build(withHandler: true));
    expect(dispatcher.dispatch(), isTrue);
    expect(handled, 1);

    await tester.pumpWidget(build(withHandler: false));
    expect(dispatcher.dispatch(), isFalse);
    expect(handled, 1);
  });

  testWidgets('嵌套时最内层先应（设置分区里的自检层就是这个形状）', (WidgetTester tester) async {
    final BackIntentDispatcher dispatcher = BackIntentDispatcher();
    final List<String> asked = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: BackIntentScope(
          dispatcher: dispatcher,
          child: BackIntentHandler(
            onBack: () {
              asked.add('分区');
              return true;
            },
            child: BackIntentHandler(
              onBack: () {
                asked.add('自检');
                return false;
              },
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    expect(dispatcher.dispatch(), isTrue);
    expect(asked, <String>['自检', '分区']);
  });

  testWidgets('外壳没给分发器时，页面上的 BackIntentHandler 安静失效', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackIntentHandler(
          onBack: () => throw StateError('不该被调用'),
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

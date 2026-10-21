import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/fl_ui/loading.dart';
import 'package:sekainook_app/theme/app_theme.dart';
import 'package:sekainook_app/ui/widgets/app_loading.dart';
import 'package:sekainook_app/ui/widgets/app_toast.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.build(ThemeId.rose, dark: false),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('AppToast 弹出后能看到文案，带撤销按钮时能显示', (tester) async {
    await tester.pumpWidget(
      _host(Builder(
        builder: (context) => Column(
          children: [
            TextButton(
              onPressed: () => AppToast.show(context, '已保存'),
              child: const Text('plain'),
            ),
            TextButton(
              onPressed: () => AppToast.show(
                context,
                '已提交，等家长审批',
                actionLabel: '撤销',
                onAction: () {},
              ),
              child: const Text('action'),
            ),
          ],
        ),
      )),
    );

    await tester.tap(find.text('plain'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('已保存'), findsOneWidget);

    await tester.tap(find.text('action'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('已提交，等家长审批'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
  });

  testWidgets('AppLoading 渲染 FlClash 彗星环', (tester) async {
    await tester.pumpWidget(_host(const Center(child: AppLoading())));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CommonCircleLoading), findsOneWidget);
  });
}

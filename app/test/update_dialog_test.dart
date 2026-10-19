import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sekainook_app/config/changelog.dart';
import 'package:sekainook_app/core/api_client.dart';
import 'package:sekainook_app/data/api/app_update_api.dart';
import 'package:sekainook_app/data/api/changelog_api.dart';
import 'package:sekainook_app/data/models/app_update.dart';
import 'package:sekainook_app/state/update_state.dart';
import 'package:sekainook_app/theme/app_theme.dart';
import 'package:sekainook_app/ui/widgets/update_dialog.dart';

/// 更新弹窗的真实回归点：日志一长，正文要能往下滑，而不是被截断。
///
/// 守的坑：约束（`maxHeight`）套在滚动视图**里面**时，等于先把内容截到固定高度、
/// 再让外面那层滚动 —— 内容不够撑满视口，滑不动，列表还会溢出。
class _StubApi extends AppUpdateApi {
  _StubApi(this.info);

  final AppUpdateInfo info;

  @override
  Future<AppUpdateInfo?> fetchLatest() async => info;
}

class _StubLogApi extends ChangelogApi {
  _StubLogApi(this.entry) : super(ApiClient());

  final ChangelogEntry entry;

  @override
  Future<ChangelogPayload> fetchChangelog() async => ChangelogPayload(
        version: entry.version,
        entries: <ChangelogEntry>[entry],
        ready: true,
      );
}

void main() {
  testWidgets('版本日志很长时，弹窗正文能往下滑', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ChangelogEntry entry = ChangelogEntry(
      version: '1.31.4',
      date: '2026-10-18 13:55:00',
      title: '这一版改了不少东西',
      changes: List<String>.generate(
        20,
        (int i) => '第 ${i + 1} 条：这一行故意写得长一点，好把弹窗撑满，用来验证日志多了能不能往下滑',
      ),
    );
    final AppUpdateInfo info = AppUpdateInfo(
      versionName: '1.31.4',
      versionCode: 6,
      url: 'https://pub.starrymiku.com/sekainook/SekaiNook-1.31.4-android-arm64-v8a.apk',
      sha256: 'a' * 64,
      size: 23245348,
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final UpdateState update = UpdateState(
      prefs: prefs,
      api: _StubApi(info),
      changelogApi: _StubLogApi(entry),
      currentVersionCode: () async => 1,
    );

    await update.autoCheck();
    expect(update.pendingLog, isNotNull, reason: '弹窗正文来自云端日志里对上的那一条');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(ThemeId.original),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: TextButton(
                onPressed: () {
                  promptUpdate(context, update: update, info: info, allowSkip: false);
                },
                child: const Text('打开弹窗'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v1.31.4'), findsOneWidget);
    expect(find.textContaining('第 1 条'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '正文不该溢出');

    final Finder scroller = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Scrollable),
    );
    expect(scroller, findsOneWidget);

    final double before = tester.state<ScrollableState>(scroller).position.pixels;
    await tester.drag(scroller, const Offset(0, -160));
    await tester.pumpAndSettle();
    final double after = tester.state<ScrollableState>(scroller).position.pixels;
    expect(after, greaterThan(before), reason: '日志长了要能往下滑');
  });
}

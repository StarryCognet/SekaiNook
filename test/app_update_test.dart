import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sekainook_app/config/app_constants.dart';
import 'package:sekainook_app/config/changelog.dart';
import 'package:sekainook_app/core/api_client.dart';
import 'package:sekainook_app/data/api/app_update_api.dart';
import 'package:sekainook_app/data/api/changelog_api.dart';
import 'package:sekainook_app/data/models/app_update.dart';
import 'package:sekainook_app/state/update_state.dart';

/// 可控的清单来源：不碰网络，只回一个预先摆好的结果。
class _FakeApi extends AppUpdateApi {
  _FakeApi(this.info);

  AppUpdateInfo? info;
  int calls = 0;

  @override
  Future<AppUpdateInfo?> fetchLatest() async {
    calls += 1;
    return info;
  }
}

/// 可控的云端版本日志（弹窗里那一段的正文）。
class _FakeLogApi extends ChangelogApi {
  _FakeLogApi([this.entries = const <ChangelogEntry>[]]) : super(ApiClient());

  final List<ChangelogEntry> entries;
  int calls = 0;

  @override
  Future<ChangelogPayload> fetchChangelog() async {
    calls += 1;
    return ChangelogPayload(
      version: entries.isEmpty ? null : entries.first.version,
      entries: entries,
      ready: entries.isNotEmpty,
    );
  }
}

/// 日志读挂了：更新本身不该受影响。
class _BrokenLogApi extends ChangelogApi {
  _BrokenLogApi() : super(ApiClient());

  @override
  Future<ChangelogPayload> fetchChangelog() async => throw StateError('日志服务挂了');
}

Map<String, Object> _manifestJson({
  String versionName = '1.32.0',
  int versionCode = 2026101801,
  String url = 'https://pub.starrymiku.com/sekainook/SekaiNook-1.32.0.apk',
  String? sha256,
  int size = 61445441,
  String? changelog = '修了花园浇水的一处错算',
}) =>
    <String, Object>{
      'versionName': versionName,
      'versionCode': versionCode,
      'url': url,
      'sha256': sha256 ?? 'a' * 64,
      'size': size,
      if (changelog != null) 'changelog': changelog,
    };

void main() {
  group('AppUpdateInfo.fromJson', () {
    test('清单齐全时解析出全部字段', () {
      final AppUpdateInfo? info =
          AppUpdateInfo.fromJson(_manifestJson(changelog: '第一行\n第二行'));

      expect(info, isNotNull);
      expect(info!.versionName, '1.32.0');
      expect(info.versionCode, 2026101801);
      expect(info.size, 61445441);
      expect(info.changelog, '第一行\n第二行');
      expect(info.sizeText, '58.6 MB');
      expect(info.fileName, 'SekaiNook-1.32.0.apk');
    });

    test('changelog 是可选的，缺了也不算坏清单', () {
      final AppUpdateInfo? info = AppUpdateInfo.fromJson(_manifestJson(changelog: null));

      expect(info, isNotNull);
      expect(info!.changelog, isNull);
    });

    test('关键字段缺失 / 不合法一律当没读到', () {
      // 少 sha256：装上去的东西没法校验，宁可不要
      final Map<String, Object> noSha = _manifestJson()..remove('sha256');
      expect(AppUpdateInfo.fromJson(noSha), isNull);

      // sha256 长度不对（复制粘贴漏了半截）
      expect(AppUpdateInfo.fromJson(_manifestJson(sha256: 'abc')), isNull);

      // 不是 https：安卓 9+ 默认禁明文，走 http 的清单不可信
      expect(
        AppUpdateInfo.fromJson(_manifestJson(url: 'http://pub.starrymiku.com/x.apk')),
        isNull,
      );

      expect(AppUpdateInfo.fromJson(_manifestJson(versionCode: 0)), isNull);
      expect(AppUpdateInfo.fromJson(_manifestJson(size: 0)), isNull);
      expect(AppUpdateInfo.fromJson(null), isNull);
      expect(AppUpdateInfo.fromJson('不是对象'), isNull);
    });
  });

  group('AppUpdateInfo.isNewerThan', () {
    final AppUpdateInfo info = AppUpdateInfo.fromJson(_manifestJson(versionCode: 100))!;

    test('比本机 versionCode 大才算新', () {
      expect(info.isNewerThan(99), isTrue);
      expect(info.isNewerThan(100), isFalse);
      expect(info.isNewerThan(101), isFalse);
    });
  });

  group('UpdateState', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    Future<UpdateState> build(
      _FakeApi api, {
      int current = 100,
      ChangelogApi? logApi,
    }) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return UpdateState(
        prefs: prefs,
        api: api,
        changelogApi: logApi ?? _FakeLogApi(),
        currentVersionCode: () async => current,
      );
    }

    _FakeApi newerApi() =>
        _FakeApi(AppUpdateInfo.fromJson(_manifestJson(versionCode: 200)));

    test('每次打开 App 都查一次：连着两次 autoCheck 都真的发请求', () async {
      final _FakeApi api = newerApi();
      final UpdateState state = await build(api);

      expect(await state.autoCheck(), isNotNull);
      expect(state.pending, isNotNull);
      expect(api.calls, 1);

      // 不再有「一天最多一次」的时间戳：下一次启动照样问
      expect(await state.autoCheck(), isNotNull);
      expect(api.calls, 2);
    });

    test('清单没读到不算「查过了」：什么都不留，下次打开还试', () async {
      final _FakeApi api = _FakeApi(null);
      final UpdateState state = await build(api);

      expect(await state.autoCheck(), isNull);
      expect(state.pending, isNull);
      expect(api.calls, 1);

      await state.autoCheck();
      expect(api.calls, 2);
    });

    test('没有新版本就什么都不留', () async {
      final _FakeApi api = _FakeApi(AppUpdateInfo.fromJson(_manifestJson(versionCode: 100)));
      final UpdateState state = await build(api);

      expect(await state.autoCheck(), isNull);
      expect(state.pending, isNull);
    });

    test('设置里关掉自动检测：autoCheck 一个请求都不发，手动检查照样能用', () async {
      final _FakeApi api = newerApi();
      final UpdateState state = await build(api);

      expect(state.autoCheckEnabled, isTrue);
      await state.setAutoCheckEnabled(false);
      expect(state.autoCheckEnabled, isFalse);

      expect(await state.autoCheck(), isNull);
      expect(api.calls, 0);

      final UpdateCheckResult manual = await state.checkNow();
      expect(manual.reachable, isTrue);
      expect(manual.update, isNotNull);
      expect(api.calls, 1);
    });

    test('把开关重新打开就顺手查一次，不用等下次启动', () async {
      final _FakeApi api = newerApi();
      final UpdateState state = await build(api);

      await state.setAutoCheckEnabled(false);
      expect(api.calls, 0);

      await state.setAutoCheckEnabled(true);
      expect(api.calls, 1);
      expect(state.pending, isNotNull);
    });

    test('手动检查断网时明确回报没连上，不冒充「已是最新」', () async {
      final _FakeApi api = _FakeApi(null);
      final UpdateState state = await build(api);

      final UpdateCheckResult result = await state.checkNow();

      expect(result.reachable, isFalse);
      expect(result.update, isNull);
    });

    test('弹窗用的日志取云端里跟新版本对上的那条', () async {
      final _FakeLogApi logApi = _FakeLogApi(<ChangelogEntry>[
        const ChangelogEntry(
          version: '1.33.0',
          date: '2026-10-20 10:00:00',
          title: '还没发的那一版',
          changes: <String>['写在最前面的最新一条'],
        ),
        const ChangelogEntry(
          version: '1.32.0',
          date: '2026-10-18 20:00:00',
          title: '花园更顺手了',
          changes: <String>['浇水不会错算了', '商店支持一次买好几样'],
        ),
      ]);
      final UpdateState state = await build(newerApi(), logApi: logApi);

      await state.autoCheck();

      expect(state.pendingLog?.version, '1.32.0');
      expect(state.pendingLog?.title, '花园更顺手了');
      expect(state.pendingLog?.changes, hasLength(2));
      expect(logApi.calls, 1);

      // 「以后再说」之后不该留着上一版的日志
      await state.skipPending();
      expect(state.pendingLog, isNull);
    });

    test('云端没有这一版的日志：pendingLog 为空，弹窗退回清单里那行说明', () async {
      final UpdateState state = await build(newerApi(), logApi: _FakeLogApi());

      await state.autoCheck();

      expect(state.pendingLog, isNull);
      expect(state.pending?.changelog, '修了花园浇水的一处错算');
    });

    test('云端日志读挂了也不影响更新本身', () async {
      final _FakeApi api = newerApi();
      final UpdateState state = await build(api, logApi: _BrokenLogApi());

      expect(await state.autoCheck(), isNotNull);
      expect(state.pending, isNotNull);
      expect(state.pendingLog, isNull);
    });

    test('点了「以后再说」：自动检查不再弹这个版本，手动检查照样能看见', () async {
      final _FakeApi api = newerApi();
      final UpdateState state = await build(api);

      await state.autoCheck();
      await state.skipPending();
      expect(state.pending, isNull);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppConstants.keySkipUpdateVersion), '1.32.0');

      // 自动检查：同一个版本闭嘴
      expect(await state.autoCheck(), isNull);
      expect(state.pending, isNull);

      // 手动检查：用户自己点的，得如实回答
      final UpdateCheckResult manual = await state.checkNow();
      expect(manual.reachable, isTrue);
      expect(manual.update, isNotNull);
      expect(state.pending, isNotNull);
    });

    test('清单里的版本比本机旧 / 一样时，checkNow 明确回「已是最新」', () async {
      final _FakeApi api = _FakeApi(AppUpdateInfo.fromJson(_manifestJson(versionCode: 100)));
      final UpdateState state = await build(api);

      final UpdateCheckResult result = await state.checkNow();
      expect(result.reachable, isTrue);
      expect(result.update, isNull);
      expect(state.pending, isNull);
    });

    test('没有待装版本时 downloadAndInstall 直接失败，不会去碰下载', () async {
      final _FakeApi api = _FakeApi(null);
      final UpdateState state = await build(api);

      expect(await state.downloadAndInstall(), UpdateInstallResult.failed);
    });
  });
}

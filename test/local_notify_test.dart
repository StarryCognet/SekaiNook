import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sekainook_app/config/app_constants.dart';
import 'package:sekainook_app/core/day_completion.dart';
import 'package:sekainook_app/core/local_notifications.dart';
import 'package:sekainook_app/data/models/ledger_record.dart';
import 'package:sekainook_app/data/models/task_config.dart';
import 'package:sekainook_app/state/local_notify_state.dart';

/// 可控的假通道：只记下被要求做了什么，不碰平台。
class FakeSink implements NotificationSink {
  FakeSink({this.supported = true, this.permission = true});

  final bool supported;
  bool permission;

  int initCount = 0;
  int permissionRequests = 0;
  int cancelCount = 0;
  final List<DateTime> scheduled = <DateTime>[];
  final List<String> scheduledTitles = <String>[];
  final List<String> shownTitles = <String>[];

  @override
  bool get isSupported => supported;

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {
    initCount += 1;
  }

  @override
  Future<bool> ensurePermission() async {
    permissionRequests += 1;
    return permission;
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> scheduleDaily({
    required DateTime beijingWallClock,
    required String title,
    required String body,
    required String payload,
  }) async {
    scheduled.add(beijingWallClock);
    scheduledTitles.add(title);
  }

  @override
  Future<void> cancelDaily() async {
    cancelCount += 1;
  }

  @override
  Future<void> showNow({
    required String title,
    required String body,
    required String payload,
  }) async {
    shownTitles.add(title);
  }
}

/// 造一条流水。[taskId] 相同即「同一个任务」，用于验去重。
LedgerRecord record({
  required String taskId,
  String? id,
  LedgerStatus? status,
  TaskType type = TaskType.earning,
  int amount = 10,
  DateTime? at,
}) {
  return LedgerRecord(
    id: id ?? 'r-$taskId-${at?.toIso8601String() ?? 'now'}',
    taskId: taskId,
    taskName: taskId,
    type: type,
    amount: amount,
    createdAt: at ?? DateTime.utc(2026, 10, 17, 2),
    status: status,
  );
}

void main() {
  // 2026-10-17 12:00 北京 = 04:00 UTC，属于东八区 10/17 白天
  final DateTime noonBeijing = DateTime.utc(2026, 10, 17, 4);

  group('countDayCompletions 口径（与服务端 DAY_COMPLETION_SQL 一致）', () {
    test('按 task_id 去重：一天背三首诗算 1 个任务', () {
      final records = <LedgerRecord>[
        record(taskId: 'read_book', id: 'a'),
        record(taskId: 'read_book', id: 'b'),
        record(taskId: 'read_book', id: 'c'),
      ];
      expect(countDayCompletions(records, now: noonBeijing).done, 1);
    });

    test('待审批与已驳回都不算完成（服务端只认 status IS NULL 或 approved）', () {
      final records = <LedgerRecord>[
        record(taskId: 'clean_room', status: null),
        record(taskId: 'wash_dishes', status: LedgerStatus.pending),
        record(taskId: 'do_laundry', status: LedgerStatus.rejected),
      ];
      // 与服务端 DAY_COMPLETION_SQL 的 `(status IS NULL OR status = 'approved')` 一致：
      // 只有还没被处理的（NULL）和已通过的算，待审批/已驳回都不算 ——
      // 所以「提交了但家长没批」照样会被算进没做完，提醒要照说。
      expect(countDayCompletions(records, now: noonBeijing).done, 1);
    });

    test('花钱与罚款不算完成', () {
      final records = <LedgerRecord>[
        record(taskId: 'clean_room'),
        record(taskId: 'ipad_time', type: TaskType.spending, amount: -10),
        record(taskId: 'sleep_penalty', amount: -20),
      ];
      expect(countDayCompletions(records, now: noonBeijing).done, 1);
    });

    test('三个系统 id 不计入', () {
      final records = <LedgerRecord>[
        record(taskId: 'seed_welcome_bonus', amount: 100),
        record(taskId: 'daily_min_tasks_penalty', amount: -10),
        record(taskId: 'sleep_penalty', amount: -20),
      ];
      expect(countDayCompletions(records, now: noonBeijing).done, 0);
    });

    test('按东八区切日：UTC 前一天 16:00 之后的算今天', () {
      final records = <LedgerRecord>[
        // 2026-10-16T15:59Z = 北京 10/16 23:59 → 昨天
        record(taskId: 'a', at: DateTime.utc(2026, 10, 16, 15, 59)),
        // 2026-10-16T16:00Z = 北京 10/17 00:00 → 今天
        record(taskId: 'b', at: DateTime.utc(2026, 10, 16, 16)),
        // 2026-10-17T15:59Z = 北京 10/17 23:59 → 今天
        record(taskId: 'c', at: DateTime.utc(2026, 10, 17, 15, 59)),
        // 2026-10-17T16:00Z = 北京 10/18 00:00 → 明天
        record(taskId: 'd', at: DateTime.utc(2026, 10, 17, 16)),
      ];
      final completion = countDayCompletions(records, now: noonBeijing);
      expect(completion.done, 2);
      expect(completion.dayKey, '2026-10-17');
    });

    test('差几个 / 是否达标', () {
      final records = <LedgerRecord>[
        for (final String id in <String>['a', 'b', 'c']) record(taskId: id),
      ];
      final completion = countDayCompletions(records, now: noonBeijing);
      expect(completion.remaining, 2);
      expect(completion.isComplete, isFalse);
    });

    test('文案与服务端一致', () {
      final two = countDayCompletions(
        <LedgerRecord>[record(taskId: 'a'), record(taskId: 'b')],
        now: noonBeijing,
      );
      final text = reminderTextFor(two);
      expect(text.title, '今天还差 3 个任务');
      expect(text.body, contains('已完成 2/5'));
      expect(text.body, contains('扣 10 分'));
      expect(text.body, contains('扣 20 分'));

      final done = countDayCompletions(
        <LedgerRecord>[for (final String id in <String>['a', 'b', 'c', 'd', 'e']) record(taskId: id)],
        now: noonBeijing,
      );
      expect(reminderTextFor(done), ReminderText.allDone);
    });
  });

  group('LocalNotifyState', () {
    late FakeSink sink;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      sink = FakeSink();
    });

    Future<LocalNotifyState> build({
      bool supported = true,
      bool permission = true,
      DateTime? at,
    }) async {
      sink = FakeSink(supported: supported, permission: permission);
      final prefs = await SharedPreferences.getInstance();
      // 把「现在」钉住：默认北京 10/17 12:00（21:30 之前，应该排今天）
      final DateTime ref = at ?? noonBeijing;
      final state = LocalNotifyState(prefs: prefs, sink: sink, clock: () => ref);
      await state.init();
      return state;
    }

    test('不支持的平台：开关点不动，并说明去用浏览器推送', () async {
      final state = await build(supported: false);
      expect(state.supported, isFalse);
      expect(await state.enable(), isFalse);
      expect(state.enabled, isFalse);
      expect(state.message, contains('网页版'));
    });

    test('没给权限：不开启，并提示去系统设置里开', () async {
      final state = await build(permission: false);
      expect(await state.enable(), isFalse);
      expect(state.enabled, isFalse);
      expect(sink.permissionRequests, 1);
      expect(state.message, contains('通知权限'));
    });

    test('21:30 之前开启 → 排在今天 21:30，文案按当前完成数', () async {
      final state = await build();
      await state.syncFromRecords(
        <LedgerRecord>[record(taskId: 'a'), record(taskId: 'b')],
        now: noonBeijing,
      );
      expect(await state.enable(), isTrue);
      expect(state.enabled, isTrue);
      expect(sink.scheduled.single, DateTime(2026, 10, 17, 21, 30));
      expect(sink.scheduledTitles.single, '今天还差 3 个任务');
      expect(state.nextFireAt, DateTime(2026, 10, 17, 21, 30));
    });

    test('21:30 之后开启 → 排到明天 21:30', () async {
      // 北京 22:10 = UTC 14:10
      final state = await build(at: DateTime.utc(2026, 10, 17, 14, 10));
      await state.enable();
      expect(sink.scheduled.single, DateTime(2026, 10, 18, 21, 30));
    });

    test('任务做完了：撤掉提醒，不再排程', () async {
      final state = await build();
      await state.enable();
      final before = sink.cancelCount;
      await state.syncFromRecords(
        <LedgerRecord>[for (final String id in <String>['a', 'b', 'c', 'd', 'e']) record(taskId: id)],
        now: noonBeijing,
      );
      expect(sink.cancelCount, before + 1);
      expect(state.nextFireAt, isNull);
      expect(state.scheduledBody, isNull);
    });

    test('关掉开关：撤销排程并落盘', () async {
      final state = await build();
      await state.enable();
      await state.disable();
      expect(state.enabled, isFalse);
      expect(sink.cancelCount, greaterThan(0));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppConstants.keyLocalNotifyEnabled), isFalse);
      expect(prefs.getString(AppConstants.keyLocalNotifyNext), isNull);
    });

    test('开启状态会落盘，重启后 init 能恢复', () async {
      final state = await build();
      await state.enable();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppConstants.keyLocalNotifyEnabled), isTrue);

      final restored = LocalNotifyState(prefs: prefs, sink: sink);
      await restored.init();
      expect(restored.enabled, isTrue);
      expect(restored.nextFireAt, isNotNull);
    });

    test('权限被系统关掉时给出提示（但开关留着）', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.keyLocalNotifyEnabled, true);
      final state = LocalNotifyState(prefs: prefs, sink: FakeSink(permission: false));
      await state.init();
      expect(state.enabled, isTrue);
      expect(state.permissionGranted, isFalse);
      expect(state.message, contains('通知权限'));
    });

    test('测试按钮：立刻弹一条，且会申请权限', () async {
      final state = await build();
      expect(await state.sendTest(), isTrue);
      expect(sink.shownTitles.single, 'SekaiNook 测试通知');
      expect(sink.permissionRequests, 1);
      expect(state.message, contains('测试通知'));
    });

    test('nextFireTime：过了 21:30 就是明天', () {
      expect(
        LocalNotifyState.nextFireTime(now: DateTime.utc(2026, 10, 17, 4)),
        DateTime(2026, 10, 17, 21, 30),
      );
      expect(
        LocalNotifyState.nextFireTime(now: DateTime.utc(2026, 10, 17, 13, 30)),
        DateTime(2026, 10, 18, 21, 30),
      );
    });
  });
}

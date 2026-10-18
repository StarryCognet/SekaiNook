import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sekainook_app/config/app_constants.dart';
import 'package:sekainook_app/core/day_completion.dart';
import 'package:sekainook_app/core/local_notifications.dart';
import 'package:sekainook_app/data/models/ledger_record.dart';
import 'package:sekainook_app/data/models/local_reminder.dart';
import 'package:sekainook_app/data/models/task_config.dart';
import 'package:sekainook_app/state/local_notify_state.dart';

/// 可控的假通道：只记下被要求做了什么，不碰平台。
class FakeSink implements NotificationSink {
  FakeSink({this.supported = true, this.permission = true, this.exact = true});

  final bool supported;
  bool permission;
  bool exact;

  int initCount = 0;
  int permissionRequests = 0;
  int exactRequests = 0;
  int cancelAllCount = 0;
  final List<String> cancelled = <String>[];
  final List<FakeSchedule> schedules = <FakeSchedule>[];
  final List<String> shownTitles = <String>[];
  final List<ReminderStyle> shownStyles = <ReminderStyle>[];

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
  Future<bool> ensureExactAlarmPermission() async {
    exactRequests += 1;
    return exact;
  }

  @override
  Future<bool> hasExactAlarmPermission() async => exact;

  @override
  Future<void> schedule({
    required LocalReminder reminder,
    required DateTime beijingWallClock,
    required String title,
    required String body,
    required String payload,
    required bool exact,
  }) async {
    schedules.add(FakeSchedule(
      reminderId: reminder.id,
      repeat: reminder.repeat,
      style: reminder.style,
      at: beijingWallClock,
      title: title,
      body: body,
      exact: exact,
    ));
  }

  @override
  Future<void> cancel(LocalReminder reminder) async {
    cancelled.add(reminder.id);
    schedules.removeWhere((item) => item.reminderId == reminder.id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount += 1;
    schedules.clear();
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required String payload,
    required ReminderStyle style,
  }) async {
    shownTitles.add(title);
    shownStyles.add(style);
  }

  FakeSchedule? scheduleOf(String reminderId) {
    for (final item in schedules) {
      if (item.reminderId == reminderId) return item;
    }
    return null;
  }
}

class FakeSchedule {
  FakeSchedule({
    required this.reminderId,
    required this.repeat,
    required this.style,
    required this.at,
    required this.title,
    required this.body,
    required this.exact,
  });

  final String reminderId;
  final ReminderRepeat repeat;
  final ReminderStyle style;
  final DateTime at;
  final String title;
  final String body;
  final bool exact;
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
        record(taskId: 'a', at: DateTime.utc(2026, 10, 16, 15, 59)),
        record(taskId: 'b', at: DateTime.utc(2026, 10, 16, 16)),
        record(taskId: 'c', at: DateTime.utc(2026, 10, 17, 15, 59)),
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
        <LedgerRecord>[
          for (final String id in <String>['a', 'b', 'c', 'd', 'e']) record(taskId: id),
        ],
        now: noonBeijing,
      );
      expect(reminderTextFor(done), ReminderText.allDone);
    });
  });

  group('提醒项数据（消息类型 / 重复 / 表现 / 占位符）', () {
    test('出厂两条内置：任务提醒 21:30 + 睡觉提醒 22:00', () {
      final defaults = LocalReminder.defaults();
      expect(defaults.length, 2);
      expect(defaults.every((item) => item.builtin), isTrue);
      expect(defaults.first.timeLabel, '21:30');
      expect(defaults.first.kind, ReminderKind.taskProgress);
      expect(defaults.last.timeLabel, '22:00');
      expect(defaults.last.kind, ReminderKind.sleep);
      // 通知 id 段不重叠
      expect(
        defaults.first.notificationIds
            .toSet()
            .intersection(defaults.last.notificationIds.toSet()),
        isEmpty,
      );
    });

    test('占位符渲染：{done}/{remaining}/{total}', () {
      const reminder = LocalReminder(
        slot: 1,
        id: 'x',
        name: 'x',
        kind: ReminderKind.taskProgress,
        hour: 21,
        minute: 30,
        title: '还差 {remaining} 个（{done}/{total}）',
        body: '{day}',
      );
      final vars = <String, String>{
        'done': '2',
        'remaining': '3',
        'total': '5',
        'day': '2026-10-17',
      };
      expect(reminder.renderTitle(vars), '还差 3 个（2/5）');
      expect(reminder.renderBody(vars), '2026-10-17');
    });

    test('表现编进通知渠道 id（安卓渠道不可改，改设置=新渠道）', () {
      const all = ReminderStyle();
      expect(all.channelId, 'sekainook_banner_sound_vibrate');
      expect(all.channelId, ReminderStyle().channelId, reason: '同设置必须同渠道');
      expect(all.summary, contains('悬浮'));
      expect(all.isSilent, isFalse);

      const quiet = ReminderStyle(sound: false, vibrate: false, headsUp: false);
      expect(quiet.isSilent, isTrue);
      expect(quiet.channelId, 'sekainook_quiet');
      expect(quiet.channelName, contains('静默'));

      const privateLock = ReminderStyle(lockscreenVisible: false);
      expect(privateLock.channelId, contains('_private'));
      expect(privateLock.summary, contains('锁屏隐藏'));
      expect(privateLock.channelId, isNot(all.channelId));
    });

    test('JSON 往返不丢字段', () {
      const original = LocalReminder(
        slot: 7,
        id: 'custom-1',
        name: '喝水',
        kind: ReminderKind.checkin,
        hour: 15,
        minute: 5,
        repeat: ReminderRepeat.once,
        enabled: false,
        title: '喝点水',
        body: '下午了，喝口水',
        style: ReminderStyle(sound: false),
        onceDay: '2026-10-18',
      );
      final restored = LocalReminder.fromJson(original.toJson());
      expect(restored.slot, 7);
      expect(restored.id, 'custom-1');
      expect(restored.kind, ReminderKind.checkin);
      expect(restored.repeat, ReminderRepeat.once);
      expect(restored.enabled, isFalse);
      expect(restored.style, original.style);
      expect(restored.onceDay, '2026-10-18');
      expect(restored.notificationIds, original.notificationIds);
    });

    test('坏数据不炸：字段缺失/类型不对时回落到安全值', () {
      final restored = LocalReminder.fromJson(<String, Object?>{
        'id': 'x',
        'hour': '25',
        'minute': 61,
        'kind': '不认识的类型',
        'repeat': 42,
        'enabled': 'yes',
      });
      expect(restored.hour, 23);
      expect(restored.minute, 59);
      expect(restored.kind, ReminderKind.custom);
      expect(restored.repeat, ReminderRepeat.daily);
      expect(restored.enabled, isTrue);
      expect(restored.style, const ReminderStyle());
    });

    test('工作日占 5 个通知 id，每天只占 1 个', () {
      const daily = LocalReminder(
        slot: 3,
        id: 'd',
        name: 'd',
        kind: ReminderKind.custom,
        hour: 8,
        minute: 0,
        title: 't',
        body: '',
      );
      expect(daily.notificationIds, <int>[2130]);
      expect(
        daily.copyWith(repeat: ReminderRepeat.weekdays).notificationIds,
        <int>[2131, 2132, 2133, 2134, 2135],
      );
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
      bool exact = true,
      DateTime? at,
    }) async {
      sink = FakeSink(supported: supported, permission: permission, exact: exact);
      final prefs = await SharedPreferences.getInstance();
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

    test('开启后两条内置都排上：任务 21:30 今天、睡觉 22:00 今天', () async {
      final state = await build();
      await state.syncFromRecords(
        <LedgerRecord>[record(taskId: 'a'), record(taskId: 'b')],
        now: noonBeijing,
      );
      expect(await state.enable(), isTrue);
      expect(state.enabled, isTrue);

      final task = sink.scheduleOf(LocalReminder.taskProgressId);
      expect(task, isNotNull);
      expect(task!.at, DateTime(2026, 10, 17, 21, 30));
      expect(task.title, '今天还差 3 个任务');
      expect(task.repeat, ReminderRepeat.daily);
      expect(task.exact, isFalse, reason: '默认省电模式');

      final sleep = sink.scheduleOf(LocalReminder.sleepId);
      expect(sleep!.at, DateTime(2026, 10, 17, 22, 0));
      expect(sleep.title, '该睡觉啦');

      expect(state.nextFireAt, DateTime(2026, 10, 17, 21, 30));
      expect(state.activeReminders.length, 2);
    });

    test('过了 21:30 开启：任务提醒排到明天，睡觉提醒排今天', () async {
      // 北京 22:10 = UTC 14:10
      final state = await build(at: DateTime.utc(2026, 10, 17, 14, 10));
      await state.enable();
      expect(
        sink.scheduleOf(LocalReminder.taskProgressId)!.at,
        DateTime(2026, 10, 18, 21, 30),
      );
      // 22:00 也过了 → 睡觉提醒同样到明天
      expect(
        sink.scheduleOf(LocalReminder.sleepId)!.at,
        DateTime(2026, 10, 18, 22, 0),
      );
    });

    test('任务做完了：撤掉任务提醒，睡觉提醒照排', () async {
      final state = await build();
      await state.enable();
      await state.syncFromRecords(
        <LedgerRecord>[
          for (final String id in <String>['a', 'b', 'c', 'd', 'e']) record(taskId: id),
        ],
        now: noonBeijing,
      );
      expect(sink.scheduleOf(LocalReminder.taskProgressId), isNull);
      expect(state.nextFireAtFor(state.reminderById(LocalReminder.taskProgressId)!),
          isNull);
      expect(sink.scheduleOf(LocalReminder.sleepId), isNotNull);
      expect(state.nextFireAt, DateTime(2026, 10, 17, 22, 0));
    });

    test('重排前先 cancelAll（否则改时间会「老时间也响」）', () async {
      final state = await build();
      await state.enable();
      final before = sink.cancelAllCount;
      await state.syncFromRecords(const <LedgerRecord>[], now: noonBeijing);
      expect(sink.cancelAllCount, greaterThan(before));
    });

    test('关掉开关：撤掉全部并落盘', () async {
      final state = await build();
      await state.enable();
      await state.disable();
      expect(state.enabled, isFalse);
      expect(sink.cancelAllCount, greaterThan(0));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppConstants.keyLocalNotifyEnabled), isFalse);
      expect(prefs.getString(AppConstants.keyLocalNotifyNext), isNull);
    });

    test('开关与提醒项都会落盘，重启后 init 能恢复', () async {
      final state = await build();
      await state.enable();
      await state.addReminder(name: '喝水', hour: 15, minute: 5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppConstants.keyLocalNotifyEnabled), isTrue);
      expect(prefs.getString(AppConstants.keyLocalNotifyReminders), isNotNull);

      final restored = LocalNotifyState(prefs: prefs, sink: sink);
      await restored.init();
      expect(restored.enabled, isTrue);
      expect(restored.reminders.length, 3);
      expect(restored.reminders.last.name, '喝水');
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

    test('按某一条测试：用它的文案与表现', () async {
      final state = await build();
      await state.addReminder(
        name: '喝水',
        hour: 15,
        minute: 5,
        title: '还差 {remaining} 个，喝口水',
        body: '今天已完成 {done}/{total}',
        style: const ReminderStyle(sound: false, headsUp: false),
      );
      await state.syncFromRecords(
        <LedgerRecord>[record(taskId: 'a')],
        now: noonBeijing,
      );
      final reminder = state.reminders.last;
      expect(await state.sendTest(reminder: reminder), isTrue);
      expect(sink.shownTitles.single, '还差 4 个，喝口水');
      expect(sink.shownStyles.single.sound, isFalse);
      expect(sink.shownStyles.single.headsUp, isFalse);
    });

    test('加一条：分配新槽位、落盘、立刻排上', () async {
      final state = await build();
      await state.enable();
      final added = await state.addReminder(
        name: '喝水',
        kind: ReminderKind.checkin,
        hour: 15,
        minute: 5,
      );
      expect(added.slot, 3);
      expect(state.reminders.length, 3);
      expect(state.nextFireAtFor(added), DateTime(2026, 10, 17, 15, 5));
      expect(sink.scheduleOf(added.id), isNotNull);
    });

    test('改时间后按新时间重排', () async {
      final state = await build();
      await state.enable();
      final sleep = state.reminderById(LocalReminder.sleepId)!;
      await state.updateReminder(sleep.copyWith(hour: 21, minute: 0));
      expect(
        sink.scheduleOf(LocalReminder.sleepId)!.at,
        DateTime(2026, 10, 17, 21, 0),
      );
    });

    test('关掉某一条：不再排它，但别的照排', () async {
      final state = await build();
      await state.enable();
      final sleep = state.reminderById(LocalReminder.sleepId)!;
      await state.setReminderEnabled(sleep, false);
      expect(sink.scheduleOf(LocalReminder.sleepId), isNull);
      expect(sink.scheduleOf(LocalReminder.taskProgressId), isNotNull);
    });

    test('内置提醒删不掉，自定义的能删', () async {
      final state = await build();
      final builtin = state.reminderById(LocalReminder.taskProgressId)!;
      await state.removeReminder(builtin);
      expect(state.reminderById(LocalReminder.taskProgressId), isNotNull);
      expect(state.message, contains('内置'));

      final custom = await state.addReminder(name: '喝水');
      await state.removeReminder(custom);
      expect(state.reminderById(custom.id), isNull);
      expect(sink.cancelled, contains(custom.id));
    });

    test('恢复内置：把改过的内置项拉回默认，自定义的留着', () async {
      final state = await build();
      await state.updateReminder(
        state.reminderById(LocalReminder.taskProgressId)!.copyWith(hour: 20),
      );
      await state.addReminder(name: '喝水');
      await state.restoreBuiltins();
      expect(state.reminderById(LocalReminder.taskProgressId)!.hour, 21);
      expect(state.reminders.length, 3);
      expect(state.reminders.where((item) => !item.builtin).length, 1);
    });

    test('准时模式：拿到权限就用精确闹钟排', () async {
      final state = await build();
      await state.enable();
      await state.setExactMode(true);
      expect(state.exactMode, isTrue);
      expect(sink.schedules.every((item) => item.exact), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppConstants.keyLocalNotifyExact), isTrue);
    });

    test('准时模式拿不到权限：保持关闭并说明去哪开', () async {
      final state = await build(exact: false);
      await state.setExactMode(true);
      expect(state.exactMode, isFalse);
      expect(state.message, contains('闹钟和提醒'));
      expect(sink.schedules, isEmpty, reason: '没拿到权限就不该重排');
    });

    test('只提醒一次：过期的自动关掉，不会留个永远不响的开关', () async {
      final state = await build();
      await state.enable();
      final added = await state.addReminder(
        name: '过期提醒',
        repeat: ReminderRepeat.once,
      );
      await state.updateReminder(
        added.copyWith(onceDay: '2026-10-16'), // 昨天
      );
      expect(state.reminderById(added.id)!.enabled, isFalse);
      expect(sink.scheduleOf(added.id), isNull);
    });

    test('nextFireTimeFor：每天 / 工作日 / 一次', () {
      const daily = LocalReminder(
        slot: 1,
        id: 'd',
        name: 'd',
        kind: ReminderKind.custom,
        hour: 21,
        minute: 30,
        title: 't',
        body: '',
      );
      expect(
        LocalNotifyState.nextFireTimeFor(daily, now: DateTime.utc(2026, 10, 17, 4)),
        DateTime(2026, 10, 17, 21, 30),
      );
      expect(
        LocalNotifyState.nextFireTimeFor(daily, now: DateTime.utc(2026, 10, 17, 13, 30)),
        DateTime(2026, 10, 18, 21, 30),
      );

      // 2026-10-17 是周六：工作日提醒下一次是周一 10/19
      final weekdays = daily.copyWith(repeat: ReminderRepeat.weekdays);
      expect(
        LocalNotifyState.nextFireTimeFor(weekdays,
            now: DateTime.utc(2026, 10, 17, 4)),
        DateTime(2026, 10, 19, 21, 30),
      );

      final once = daily.copyWith(repeat: ReminderRepeat.once, onceDay: '2026-10-20');
      expect(
        LocalNotifyState.nextFireTimeFor(once, now: DateTime.utc(2026, 10, 17, 4)),
        DateTime(2026, 10, 20, 21, 30),
      );
      final past = daily.copyWith(repeat: ReminderRepeat.once, onceDay: '2026-10-01');
      expect(LocalNotifyState.nextFireTimeFor(past, now: DateTime.utc(2026, 10, 17, 4)),
          isNull);
    });

    test('任务提醒：今天已完成时不再排它（别的类型照排）', () {
      final done = countDayCompletions(
        <LedgerRecord>[
          for (final String id in <String>['a', 'b', 'c', 'd', 'e']) record(taskId: id),
        ],
        now: noonBeijing,
      );
      final task = LocalReminder.defaults().first;
      expect(
        LocalNotifyState.nextFireTimeFor(task,
            now: noonBeijing, completion: done),
        isNull,
      );
      expect(
        LocalNotifyState.nextFireTimeFor(task, now: noonBeijing),
        isNotNull,
        reason: '不知道完成数时不能凭空空掉提醒',
      );
    });

    test('落盘坏数据回落默认两条，不会整份配置作废', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppConstants.keyLocalNotifyReminders: '[{"id":"x"}, 这不是 JSON 的一部分]',
      });
      final prefs = await SharedPreferences.getInstance();
      final state = LocalNotifyState(prefs: prefs, sink: FakeSink());
      await state.init();
      expect(state.reminders.length, 2);
      expect(state.reminders.first.id, LocalReminder.taskProgressId);
    });
  });
}

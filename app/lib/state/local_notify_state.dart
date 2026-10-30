import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../core/day_completion.dart';
import '../core/local_notifications.dart';
import '../core/week.dart';
import '../data/models/ledger_record.dart';
import '../data/models/local_reminder.dart';

/// App 本地提醒（安卓系统通知栏）的状态机。
///
/// 职责：把「提醒项列表」翻译成系统定时通知，并在每次账本刷新后用最新数据
/// 重排一遍 —— 任务做完了就撤掉那条，没做完就把「还差几个」改准。
///
/// 文案里的数字口径走 [countDayCompletions]（与服务端提醒 Worker 一致），
/// **不用首页那个 `todayProgress`** —— 两者分母不同，说错了比不说更糟。
class LocalNotifyState extends ChangeNotifier {
  LocalNotifyState({
    required SharedPreferences prefs,
    NotificationSink? sink,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        _sink = sink ?? LocalNotificationSink(),
        _clock = clock ?? DateTime.now;

  /// 点通知后跳到哪一页
  static const String tapPayload = '/home';

  final SharedPreferences _prefs;
  final NotificationSink _sink;

  /// 「现在」的来源。抽出来是为了能在测试里把时间钉住 ——
  /// 提醒这套逻辑全是时间敏感的（21:30 前/后、东八区切日），
  /// 用真实时钟写断言等于在赌跑测试的时刻。
  final DateTime Function() _clock;

  bool _enabled = false;
  bool _permissionGranted = false;
  bool _exactMode = false;
  bool _exactGranted = false;
  bool _busy = false;
  String? _message;
  List<LedgerRecord> _lastRecords = const [];
  List<LocalReminder> _reminders = const [];
  final Map<String, DateTime> _nextFire = <String, DateTime>{};
  final Map<String, String> _scheduledText = <String, String>{};
  void Function(String payload)? _onTap;

  /// 当前平台支不支持本地通知（网页版不支持，走浏览器推送那条路）
  bool get supported => _sink.isSupported;

  bool get enabled => _enabled;
  bool get permissionGranted => _permissionGranted;
  bool get busy => _busy;

  /// 准时模式：用精确闹钟（安卓 12+ 要用户在系统里允许「闹钟和提醒」）
  bool get exactMode => _exactMode;
  bool get exactGranted => _exactGranted;

  /// 提醒项列表（内置两条 + 用户自己加的）
  List<LocalReminder> get reminders => List<LocalReminder>.unmodifiable(_reminders);

  /// 真正排上的提醒项（开着的）
  List<LocalReminder> get activeReminders =>
      _reminders.where((reminder) => reminder.enabled).toList(growable: false);

  /// 最近一次操作的结果，供 UI 弹提示
  String? get message => _message;

  /// 某条提醒下一次会响的时刻（北京墙钟时间）；没排上时为 null
  DateTime? nextFireAtFor(LocalReminder reminder) => _nextFire[reminder.id];

  /// 某条提醒下一次会说什么（给设置页预览用）
  String? scheduledTextFor(LocalReminder reminder) => _scheduledText[reminder.id];

  /// 最早会响的那一条的时刻（卡片上「下一次提醒」用）
  DateTime? get nextFireAt {
    DateTime? earliest;
    for (final at in _nextFire.values) {
      if (earliest == null || at.isBefore(earliest)) earliest = at;
    }
    return earliest;
  }

  /// 内置两条（任务提醒 / 睡觉提醒）在不在
  LocalReminder? reminderById(String id) {
    for (final reminder in _reminders) {
      if (reminder.id == id) return reminder;
    }
    return null;
  }

  void clearMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  /// 点通知后由 app 注册跳转
  void bindTapHandler(void Function(String payload) handler) => _onTap = handler;

  Future<void> init() async {
    _reminders = _readReminders();
    _exactMode = _prefs.getBool(AppConstants.keyLocalNotifyExact) ?? false;
    if (!supported) {
      notifyListeners();
      return;
    }

    await _sink.init(onTap: (payload) {
      if (payload != null && payload.isNotEmpty) _onTap?.call(payload);
    });

    _enabled = _prefs.getBool(AppConstants.keyLocalNotifyEnabled) ?? false;
    _permissionGranted = await _sink.hasPermission();
    _exactGranted = await _sink.hasExactAlarmPermission();

    if (_enabled && !_permissionGranted) {
      // 权限被系统里关掉了：提醒不会响，但开关还留着（用户去系统里开回来即可）
      _message = '系统里把通知权限关了，提醒不会响 —— 去手机「设置 → 应用 → SekaiNook → 通知」里打开';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- 开关

  /// 开启：先要权限，再按当前账本把所有提醒项排上
  Future<bool> enable() async {
    if (!supported) {
      _message = '这个平台不支持本地通知；装上安卓 App 之后才能用';
      notifyListeners();
      return false;
    }

    _busy = true;
    notifyListeners();

    final granted = await _sink.ensurePermission();
    _permissionGranted = granted;
    if (!granted) {
      _busy = false;
      _message = '没拿到通知权限 —— 去手机「设置 → 应用 → SekaiNook → 通知」里打开，再回来开启';
      notifyListeners();
      return false;
    }

    _enabled = true;
    await _prefs.setBool(AppConstants.keyLocalNotifyEnabled, true);
    _busy = false;
    await rescheduleAll(_lastRecords);

    final count = activeReminders.length;
    _message = count == 0
        ? '本地提醒已开启：现在一条都没启用，去下面打开一条'
        : '本地提醒已开启：$count 条提醒会按你设的时间响';
    notifyListeners();
    return true;
  }

  Future<void> disable() async {
    _enabled = false;
    // 队列里还挂着一轮待重排也一并作废：否则关闭后它还会把通知排回来（审计 S-1）。
    _rescheduleNext = null;
    _nextFire.clear();
    _scheduledText.clear();
    await _prefs.setBool(AppConstants.keyLocalNotifyEnabled, false);
    await _prefs.remove(AppConstants.keyLocalNotifyNext);
    await _prefs.remove(AppConstants.keyLocalNotifyDay);
    await _sink.cancelAll();
    _message = '本地提醒已关闭（排好的都撤掉了）';
    notifyListeners();
  }

  /// 准时模式开关：打开时申请精确闹钟权限，拿不到就保持关闭并说明
  Future<void> setExactMode(bool value) async {
    // 以前这里直接 return：网页版点了开关毫无反应，也没有一句解释（死开关）
    if (!supported) {
      _message = '这个平台排不了系统闹钟，准时模式只有在安卓 App 里才能开';
      notifyListeners();
      return;
    }
    _busy = true;
    notifyListeners();

    if (value) {
      final granted = await _sink.ensureExactAlarmPermission();
      _exactGranted = granted;
      if (!granted) {
        _busy = false;
        _exactMode = false;
        await _prefs.setBool(AppConstants.keyLocalNotifyExact, false);
        _message = '没拿到「闹钟和提醒」权限 —— 去手机「设置 → 应用 → 特殊权限」里允许，再回来打开';
        notifyListeners();
        return;
      }
    }

    _exactMode = value;
    await _prefs.setBool(AppConstants.keyLocalNotifyExact, value);
    _busy = false;
    await rescheduleAll(_lastRecords);
    _message = value ? '已改成准时模式：到点就响（更耗电一点点）' : '已改成省电模式：到点可能晚几分钟';
    notifyListeners();
  }

  // ---------------------------------------------------------------- 提醒项增删改

  /// 加一条自定义提醒（返回新那条）
  Future<LocalReminder> addReminder({
    String? name,
    ReminderKind kind = ReminderKind.custom,
    int hour = 20,
    int minute = 0,
    ReminderRepeat repeat = ReminderRepeat.daily,
    String? title,
    String body = '',
    ReminderStyle style = const ReminderStyle(),
    String? onceDay,
  }) async {
    final slot = _nextSlot();
    final now = _clock();
    final reminder = LocalReminder(
      slot: slot,
      id: 'custom-${now.millisecondsSinceEpoch}',
      name: name?.trim().isNotEmpty == true ? name!.trim() : '自定义提醒',
      kind: kind,
      hour: hour,
      minute: minute,
      repeat: repeat,
      title: title?.trim().isNotEmpty == true ? title!.trim() : 'SekaiNook 提醒',
      body: body,
      style: style,
      // 「只提醒一次」要带日期；没给就默认今天（今天已过则该条不会响，用户会在列表里看到）
      onceDay: repeat == ReminderRepeat.once
          ? (onceDay ?? WeekUtil.beijingDayKey(now))
          : onceDay,
    );
    _reminders = <LocalReminder>[..._reminders, reminder];
    await _persist();
    await rescheduleAll(_lastRecords);
    _message = '加了一条提醒：${reminder.name}（${reminder.scheduleLabel}）';
    notifyListeners();
    return reminder;
  }

  /// 改一条（内置项也能改时间/文案/表现，只是删不掉）
  Future<void> updateReminder(LocalReminder updated) async {
    _reminders = <LocalReminder>[
      for (final reminder in _reminders)
        if (reminder.id == updated.id) updated else reminder,
    ];
    await _persist();
    await rescheduleAll(_lastRecords);
    _message = '已保存：${updated.name}';
    notifyListeners();
  }

  /// 开/关一条
  Future<void> setReminderEnabled(LocalReminder reminder, bool value) =>
      updateReminder(reminder.copyWith(enabled: value));

  /// 删一条（内置项拒绝）
  Future<void> removeReminder(LocalReminder reminder) async {
    if (reminder.builtin) {
      _message = '「${reminder.name}」是内置提醒，可以关掉或改时间，但删不掉';
      notifyListeners();
      return;
    }
    _reminders =
        _reminders.where((item) => item.id != reminder.id).toList(growable: false);
    _nextFire.remove(reminder.id);
    _scheduledText.remove(reminder.id);
    await _sink.cancel(reminder);
    await _persist();
    _message = '删掉了「${reminder.name}」';
    notifyListeners();
  }

  /// 恢复出厂的两条内置提醒（自定义的留着）
  ///
  /// 注意：内置那两条会被**整体覆盖**回默认值，改过的时间/文案都会丢 —— 调用方
  /// 必须先把这句告诉用户再问一次。
  Future<void> restoreBuiltins() async {
    final builtins = LocalReminder.defaults();
    final customs =
        _reminders.where((reminder) => !reminder.builtin).toList(growable: false);
    _reminders = <LocalReminder>[...builtins, ...customs];
    await _persist();
    await rescheduleAll(_lastRecords);
    _message = '内置的两条已恢复默认（改过的地方被覆盖了，自己加的没动）';
    notifyListeners();
  }

  int _nextSlot() {
    // 先找第一个空闲的 1..99（M-9）：以前是 (max+1).clamp(1,99)，
    // 顶到 99 之后新提醒全挤在同一个槽位 → 通知 id 相同，后一条覆盖前一条。
    final Set<int> used = <int>{for (final reminder in _reminders) reminder.slot};
    for (int slot = 1; slot <= 99; slot++) {
      if (!used.contains(slot)) return slot;
    }
    return 99;
  }

  // ---------------------------------------------------------------- 排程

  /// 立刻弹一条（设置页的测试按钮）—— 不等时间，装完就能验通道。
  ///
  /// 传 [reminder] 就按那条的表现（声音/震动/悬浮/锁屏）和文案来弹，
  /// 不传就用默认表现 + 一句通用文案。
  Future<bool> sendTest({LocalReminder? reminder}) async {
    if (!supported) {
      _message = '这个平台不支持本地通知；装上安卓 App 之后才能用';
      notifyListeners();
      return false;
    }

    _busy = true;
    notifyListeners();

    final granted = await _sink.ensurePermission();
    _permissionGranted = granted;
    if (!granted) {
      _busy = false;
      _message = '没拿到通知权限 —— 去手机「设置 → 应用 → SekaiNook → 通知」里打开';
      notifyListeners();
      return false;
    }

    final completion = countDayCompletions(_lastRecords, now: _clock());
    final vars = templateVars(completion);

    await _sink.showNow(
      id: LocalNotificationSink.testId,
      title: reminder?.renderTitle(vars) ?? 'SekaiNook 测试通知',
      body: reminder?.renderBody(vars).isNotEmpty == true
          ? reminder!.renderBody(vars)
          : '本地通知通了。装好 App 后，划掉后台也会按你设的时间提醒。',
      payload: tapPayload,
      style: reminder?.style ?? const ReminderStyle(),
    );

    _busy = false;
    _message = reminder == null
        ? '已发一条测试通知，看一下通知栏'
        : '已按「${reminder.name}」的设置发了一条，看一下通知栏';
    notifyListeners();
    return true;
  }

  /// 账本刷新后重排：任务做完了撤掉任务提醒，没做完就把数字改准
  Future<void> syncFromRecords(List<LedgerRecord> records, {DateTime? now}) =>
      rescheduleAll(records, now: now);

  /// 重排串行队列：并发调用会排队执行，且只保留最后一次请求的参数。
  ///
  /// 为什么必须串行：整段流程是「cancelAll → 逐条 schedule」，
  /// 两轮交错时后一轮的 cancelAll 会把前一轮刚排好的通知撤掉，最后少排几条。
  Future<void>? _rescheduleRun;
  ({List<LedgerRecord> records, DateTime? now})? _rescheduleNext;

  /// 把所有开着的提醒项重新排一遍（串行化入口，见 [_rescheduleRun]）。
  Future<void> rescheduleAll(List<LedgerRecord> records, {DateTime? now}) {
    _rescheduleNext = (records: records, now: now);
    return _rescheduleRun ??= _drainReschedule();
  }

  Future<void> _drainReschedule() async {
    try {
      while (true) {
        final args = _rescheduleNext;
        _rescheduleNext = null;
        if (args == null) break;
        await _doReschedule(args.records, now: args.now);
      }
    } finally {
      _rescheduleRun = null;
    }
  }

  /// 真正的重排实现。
  ///
  /// 先 [NotificationSink.cancelAll] 再逐条排 —— 提醒项被删/被改时间以后，
  /// 上一次排的通知必须撤掉，否则会「改了时间还在老时间响」。
  ///
  /// S-1：整个流程里有多个 await（cancelAll / schedule），用户随时可能点「关闭」。
  /// 旧实现只在入口看一次 `_enabled`，关掉开关后仍在飞行中的这一轮会继续把通知
  /// 排回去（`disable()` 的 cancelAll 先执行、这轮的 schedule 后执行，最后通知还在）。
  /// 所以这里每个 await 之后都复查 `_enabled`，中途关闭就再撤一次并丢弃半截状态。
  Future<void> _doReschedule(List<LedgerRecord> records, {DateTime? now}) async {
    _lastRecords = records;
    if (!supported) return;

    // 先攒在局部，整轮排完再一次性写回，中途失败/关闭不会留下半截 _nextFire。
    final Map<String, DateTime> nextFire = <String, DateTime>{};
    final Map<String, String> scheduledText = <String, String>{};

    if (!_enabled) {
      _nextFire.clear();
      _scheduledText.clear();
      notifyListeners();
      return;
    }

    final DateTime ref = now ?? _clock();
    final completion = countDayCompletions(records, now: ref);
    final vars = templateVars(completion);

    await _sink.cancelAll();
    if (!_enabled) {
      // 用户在这条 await 期间关了开关：撤掉刚排的一切并放弃本轮。
      await _sink.cancelAll();
      _nextFire.clear();
      _scheduledText.clear();
      notifyListeners();
      return;
    }

    var cancelled = false;

    for (final reminder in activeReminders) {
      if (!_enabled) {
        cancelled = true;
        break;
      }

      final when = nextFireTimeFor(reminder, now: ref, completion: completion);
      if (when == null) {
        // 只提醒一次且已经过了 —— 自动关掉，免得留个永远不响的开关
        _reminders = <LocalReminder>[
          for (final item in _reminders)
            if (item.id == reminder.id) item.copyWith(enabled: false) else item,
        ];
        continue;
      }

      final title = reminder.renderTitle(vars);
      final body = reminder.renderBody(vars);

      await _sink.schedule(
        reminder: reminder,
        beijingWallClock: when,
        title: title,
        body: body,
        payload: tapPayload,
        exact: _exactMode,
      );

      if (!_enabled) {
        // schedule 期间被关闭：这一条已经排上去了，得再撤一次。
        cancelled = true;
        break;
      }

      nextFire[reminder.id] = when;
      scheduledText[reminder.id] = body.isEmpty ? title : '$title\n$body';
    }

    if (cancelled) {
      await _sink.cancelAll();
      _nextFire.clear();
      _scheduledText.clear();
      notifyListeners();
      return;
    }

    _nextFire
      ..clear()
      ..addAll(nextFire);
    _scheduledText
      ..clear()
      ..addAll(scheduledText);

    await _persist();
    final earliest = nextFireAt;
    if (earliest == null) {
      await _prefs.remove(AppConstants.keyLocalNotifyNext);
    } else {
      await _prefs.setString(
          AppConstants.keyLocalNotifyNext, earliest.toIso8601String());
    }
    await _prefs.setString(AppConstants.keyLocalNotifyDay, completion.dayKey);
    notifyListeners();
  }

  /// 某条提醒下一次会响的时刻（北京墙钟时间）；不会再响就返回 null
  static DateTime? nextFireTimeFor(
    LocalReminder reminder, {
    DateTime? now,
    DayCompletion? completion,
  }) {
    final shifted = WeekUtil.beijingNow(now);
    // 统一成「本地标记 + 北京墙钟字段」再比较：下面全是字段对字段的比较。
    // 直接用 WeekUtil.beijingNow 的结果（UTC 标记）去比 DateTime(...) 的候选，
    // 比的是「瞬间」而不是「墙钟」，会整整差出一个时区（UTC+8 的手机上，
    // 12:00 设的 15:05 提醒会被算成「已经过了」而排到明天）。
    final beijing = DateTime(shifted.year, shifted.month, shifted.day,
        shifted.hour, shifted.minute);

    if (reminder.repeat == ReminderRepeat.once) {
      final day = reminder.onceDay;
      if (day == null) return null;
      final parsed = DateTime.tryParse(day);
      if (parsed == null) return null;
      final at = DateTime(parsed.year, parsed.month, parsed.day, reminder.hour,
          reminder.minute);
      return at.isAfter(beijing) ? at : null;
    }

    // 任务提醒：今天已经做完了就不用再提醒（其它类型照响）
    if (reminder.kind == ReminderKind.taskProgress &&
        completion != null &&
        completion.isComplete) {
      return null;
    }

    if (reminder.repeat == ReminderRepeat.weekdays) {
      if (beijing.weekday > DateTime.friday) {
        // 周末：下一次是下周一
        final daysToMonday = 8 - beijing.weekday;
        final next = beijing.add(Duration(days: daysToMonday));
        return DateTime(
            next.year, next.month, next.day, reminder.hour, reminder.minute);
      }
    }

    var candidate = DateTime(
      beijing.year,
      beijing.month,
      beijing.day,
      reminder.hour,
      reminder.minute,
    );
    if (!candidate.isAfter(beijing)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    if (reminder.repeat == ReminderRepeat.weekdays && candidate.weekday > 5) {
      final daysToMonday = 8 - candidate.weekday;
      candidate = candidate.add(Duration(days: daysToMonday));
    }
    return candidate;
  }

  /// 模板变量：`{done}` `{remaining}` `{total}` `{day}`
  static Map<String, String> templateVars(DayCompletion completion) =>
      <String, String>{
        'done': '${completion.done}',
        'remaining': '${completion.remaining}',
        'total': '${completion.target}',
        'day': completion.dayKey,
      };

  // ---------------------------------------------------------------- 落盘

  List<LocalReminder> _readReminders() {
    final raw = _prefs.getString(AppConstants.keyLocalNotifyReminders);
    if (raw == null || raw.isEmpty) return LocalReminder.defaults();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return LocalReminder.defaults();
      final parsed = <LocalReminder>[];
      for (final item in decoded) {
        try {
          parsed.add(LocalReminder.fromJson(item));
        } catch (_) {
          // 单条坏数据不该让整份配置作废
        }
      }
      return parsed.isEmpty ? LocalReminder.defaults() : parsed;
    } catch (_) {
      return LocalReminder.defaults();
    }
  }

  Future<void> _persist() async {
    final payload = jsonEncode(<Object?>[
      for (final reminder in _reminders) reminder.toJson(),
    ]);
    await _prefs.setString(AppConstants.keyLocalNotifyReminders, payload);
  }
}

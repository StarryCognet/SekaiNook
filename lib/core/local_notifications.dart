import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models/local_reminder.dart';

/// App 自己的系统通知（安卓通知栏）—— 与网站那条 Web Push 是两条独立通道：
///
/// * Web Push：由服务端 Worker 在 21:30 推给**浏览器**（孩子安卓 Chrome /
///   妈妈 iPhone 加到主屏幕的网站）。App 收不到，卸载 App 也照样收。
/// * 本地通知（本文件）：由 App 自己交给**系统闹钟**排程，不依赖网络、
///   不依赖服务端，划掉后台、重启手机都会响（重启后由插件的 boot receiver
///   恢复）；代价是文案里的数字是「最后一次打开 App 时」算出来的。
///
/// 两条通道同时开着的设备会各响一次，所以 UI 上写清楚了：装了 App 就用这个，
/// 只用网站就用上面那张卡的浏览器推送。
abstract interface class NotificationSink {
  /// 当前平台支不支持（网页版与桌面端返回 false）
  bool get isSupported;

  Future<void> init({void Function(String? payload)? onTap});

  /// 申请通知权限（安卓 13+ / iOS 会弹系统框）；已授权时直接返回 true
  Future<bool> ensurePermission();

  Future<bool> hasPermission();

  /// 精确闹钟权限（安卓 12+ 要用户去系统设置里允许「闹钟和提醒」）。
  /// 拿不到也不影响提醒，只是到点可能晚几分钟。
  Future<bool> ensureExactAlarmPermission();

  Future<bool> hasExactAlarmPermission();

  /// 排一条提醒。
  ///
  /// [beijingWallClock] 是**北京墙钟时间**（字段即所见：21:30 就传 21:30），
  /// 由实现按 `Asia/Shanghai` 解释 —— 手机时区设成别的也不影响。
  ///
  /// [repeat] 决定排几条：[ReminderRepeat.daily] 一条每天重复、
  /// [ReminderRepeat.weekdays] 五条（周一到周五各一条）、
  /// [ReminderRepeat.once] 一条只响一次。
  Future<void> schedule({
    required LocalReminder reminder,
    required DateTime beijingWallClock,
    required String title,
    required String body,
    required String payload,
    required bool exact,
  });

  /// 撤掉某条提醒占用的全部通知
  Future<void> cancel(LocalReminder reminder);

  /// 撤掉本 App 排过的所有通知（改设置后整体重排前用）
  Future<void> cancelAll();

  /// 立刻弹一条（测试用）
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required String payload,
    required ReminderStyle style,
  });
}

/// 真家伙：`flutter_local_notifications` + `Asia/Shanghai` 时区
class LocalNotificationSink implements NotificationSink {
  LocalNotificationSink({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// 测试通知的通知 id（不与提醒项的 id 段冲突）
  static const int testId = 2999;

  /// 打卡提醒固定按东八区算（全家都在东八区，与后端结算口径一致）
  static const String timezoneName = 'Asia/Shanghai';

  static const String _androidIcon = '@mipmap/ic_launcher';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {
    if (!isSupported || _ready) return;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(timezoneName));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_androidIcon),
        iOS: DarwinInitializationSettings(
          // 权限单独申请（点「开启本地提醒」时才弹），初始化时不打扰
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap?.call(response.payload),
    );
    _ready = true;
  }

  @override
  Future<bool> ensurePermission() async {
    if (!isSupported) return false;
    if (await hasPermission()) return true;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _android();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final granted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return granted ?? false;
  }

  @override
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _android()?.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final permissions = await ios?.checkPermissions();
    return permissions?.isEnabled ?? false;
  }

  @override
  Future<bool> ensureExactAlarmPermission() async {
    if (!isSupported) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    if (await hasExactAlarmPermission()) return true;
    final granted = await _android()?.requestExactAlarmsPermission();
    return granted ?? false;
  }

  @override
  Future<bool> hasExactAlarmPermission() async {
    if (!isSupported) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await _android()?.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<void> schedule({
    required LocalReminder reminder,
    required DateTime beijingWallClock,
    required String title,
    required String body,
    required String payload,
    required bool exact,
  }) async {
    if (!isSupported) return;
    await init();

    final details = _details(reminder.style);
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    switch (reminder.repeat) {
      case ReminderRepeat.daily:
        await _zoned(
          id: reminder.notificationId,
          at: beijingWallClock,
          title: title,
          body: body,
          payload: payload,
          details: details,
          mode: mode,
          match: DateTimeComponents.time,
        );
      case ReminderRepeat.once:
        await _zoned(
          id: reminder.notificationId,
          at: beijingWallClock,
          title: title,
          body: body,
          payload: payload,
          details: details,
          mode: mode,
        );
      case ReminderRepeat.weekdays:
        // 周一到周五各排一条：`dayOfWeekAndTime` 是「每周这一天的这个点」
        for (var weekday = 1; weekday <= 5; weekday++) {
          await _zoned(
            id: reminder.notificationId + weekday,
            at: _nextWeekday(beijingWallClock, weekday),
            title: title,
            body: body,
            payload: payload,
            details: details,
            mode: mode,
            match: DateTimeComponents.dayOfWeekAndTime,
          );
        }
    }
  }

  @override
  Future<void> cancel(LocalReminder reminder) async {
    if (!isSupported) return;
    await init();
    for (final id in reminder.notificationIds) {
      await _plugin.cancel(id: id);
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!isSupported) return;
    await init();
    await _plugin.cancelAll();
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required String payload,
    required ReminderStyle style,
  }) async {
    if (!isSupported) return;
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details(style),
      payload: payload,
    );
  }

  AndroidFlutterLocalNotificationsPlugin? _android() => _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _zoned({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
    required NotificationDetails details,
    required AndroidScheduleMode mode,
    DateTimeComponents? match,
  }) {
    final when = tz.TZDateTime(
      tz.local,
      at.year,
      at.month,
      at.day,
      at.hour,
      at.minute,
    );
    return _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: mode,
      matchDateTimeComponents: match,
      payload: payload,
    );
  }

  /// 下一个「星期 [weekday] 的 hh:mm」（weekday: 1=周一 … 7=周日）
  static DateTime _nextWeekday(DateTime from, int weekday) {
    var candidate = DateTime(from.year, from.month, from.day, from.hour, from.minute);
    var guard = 0;
    while (candidate.weekday != weekday && guard < 7) {
      candidate = candidate.add(const Duration(days: 1));
      guard++;
    }
    return candidate;
  }

  /// 通知表现 → 通知详情。
  ///
  /// 安卓 8 以后声音/震动/重要性都属于**渠道**，渠道建好不能改；
  /// [ReminderStyle.channelId] 把四个开关编进 id，所以改设置 = 新渠道，能生效。
  NotificationDetails _details(ReminderStyle style) {
    final importance = style.headsUp
        ? Importance.max
        : (style.sound || style.vibrate ? Importance.high : Importance.low);
    final priority = style.headsUp
        ? Priority.max
        : (style.sound || style.vibrate ? Priority.high : Priority.low);

    return NotificationDetails(
      android: AndroidNotificationDetails(
        style.channelId,
        style.channelName,
        channelDescription: 'SekaiNook 的本地提醒（${style.summary}）',
        importance: importance,
        priority: priority,
        playSound: style.sound,
        enableVibration: style.vibrate,
        // 悬浮横幅（heads-up）在安卓 8+ 由渠道重要性决定；high/max 才会弹出来
        visibility: style.lockscreenVisible
            ? NotificationVisibility.public
            : NotificationVisibility.secret,
        category: AndroidNotificationCategory.reminder,
        ticker: style.headsUp ? 'SekaiNook 提醒' : null,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: style.headsUp,
        presentSound: style.sound,
        presentBadge: true,
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// App 自己的系统通知（安卓通知栏）—— 与网站那条 Web Push 是两条独立通道：
///
/// * Web Push：由服务端 Worker 在 21:30 推给**浏览器**（孩子安卓 Chrome /
///   妈妈 iPhone 加到主屏幕的网站）。App 收不到。
/// * 本地通知（本文件）：由 App 自己用系统的定时通知排程，**不依赖网络、
///   不依赖服务端**，代价是文案是「最后一次打开 App 时」算出来的。
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

  /// 每天固定时刻重复的提醒。
  ///
  /// [beijingWallClock] 是**北京墙钟时间**（字段即所见：21:30 就传 21:30），
  /// 由实现按 `Asia/Shanghai` 解释 —— 手机时区设成别的也不影响。
  Future<void> scheduleDaily({
    required DateTime beijingWallClock,
    required String title,
    required String body,
    required String payload,
  });

  Future<void> cancelDaily();

  /// 立刻弹一条（测试按钮用）
  Future<void> showNow({
    required String title,
    required String body,
    required String payload,
  });
}

/// 真家伙：`flutter_local_notifications` + `Asia/Shanghai` 时区
class LocalNotificationSink implements NotificationSink {
  LocalNotificationSink({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// 每日提醒的通知 id（固定，重排时覆盖同一条）
  static const int reminderId = 2100;

  /// 测试通知的通知 id
  static const int testId = 2101;

  static const String channelId = 'sekainook_reminder';
  static const String channelName = '任务提醒';
  static const String channelDescription = '每天 21:30 提醒今天还差几个任务';

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
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
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
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final permissions = await ios?.checkPermissions();
    return permissions?.isEnabled ?? false;
  }

  @override
  Future<void> scheduleDaily({
    required DateTime beijingWallClock,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!isSupported) return;
    await init();

    final when = tz.TZDateTime(
      tz.local,
      beijingWallClock.year,
      beijingWallClock.month,
      beijingWallClock.day,
      beijingWallClock.hour,
      beijingWallClock.minute,
    );

    await _plugin.zonedSchedule(
      id: reminderId,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _details(),
      // 不用精确闹钟权限（SCHEDULE_EXACT_ALARM 在国产 ROM 上还要用户去系统设置里开）；
      // 系统在打盹时可能晚几分钟到十几分钟，对「提前半小时提醒」够用。
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // 每天同一时刻重复；重排时同 id 覆盖，所以「文案随数据刷新」不会堆通知
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  @override
  Future<void> cancelDaily() async {
    if (!isSupported) return;
    await init();
    await _plugin.cancel(id: reminderId);
  }

  @override
  Future<void> showNow({
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!isSupported) return;
    await init();
    await _plugin.show(
      id: testId,
      title: title,
      body: body,
      notificationDetails: _details(),
      payload: payload,
    );
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      );
}

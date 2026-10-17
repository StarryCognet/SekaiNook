import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../core/day_completion.dart';
import '../core/local_notifications.dart';
import '../core/week.dart';
import '../data/models/ledger_record.dart';

/// App 本地提醒（安卓系统通知栏）的状态机。
///
/// 职责：把「今天还差几个任务」翻译成一条每天 21:30 重复的系统通知，
/// 并在每次账本刷新后用最新数据重排一次（同 id 覆盖，不会堆通知）。
///
/// 文案口径走 [countDayCompletions]（与服务端一致），**不用首页那个
/// `todayProgress`** —— 两者分母不同，说错了比不说更糟。
class LocalNotifyState extends ChangeNotifier {
  LocalNotifyState({
    required SharedPreferences prefs,
    NotificationSink? sink,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        _sink = sink ?? LocalNotificationSink(),
        _clock = clock ?? DateTime.now;

  /// 提醒时刻：21:30（北京），与服务端 Worker 的 cron `30 13 * * *` 同一时刻
  static const int reminderHour = 21;
  static const int reminderMinute = 30;

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
  bool _busy = false;
  DateTime? _nextFireAt;
  String? _scheduledTitle;
  String? _scheduledBody;
  String? _message;
  List<LedgerRecord> _lastRecords = const [];
  void Function(String payload)? _onTap;

  /// 当前平台支不支持本地通知（网页版不支持，走浏览器推送那条路）
  bool get supported => _sink.isSupported;

  bool get enabled => _enabled;
  bool get permissionGranted => _permissionGranted;
  bool get busy => _busy;

  /// 下一次会响的时刻（北京墙钟时间）；没有排程时为 null
  DateTime? get nextFireAt => _nextFireAt;

  /// 下一次通知会说什么（给设置页预览用）
  String? get scheduledTitle => _scheduledTitle;
  String? get scheduledBody => _scheduledBody;

  /// 最近一次操作的结果，供 UI 弹提示
  String? get message => _message;

  void clearMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  /// 点通知后由 app 注册跳转
  void bindTapHandler(void Function(String payload) handler) => _onTap = handler;

  Future<void> init() async {
    if (!supported) return;

    await _sink.init(onTap: (payload) {
      if (payload != null && payload.isNotEmpty) _onTap?.call(payload);
    });

    _enabled = _prefs.getBool(AppConstants.keyLocalNotifyEnabled) ?? false;
    _permissionGranted = await _sink.hasPermission();

    final storedNext = _prefs.getString(AppConstants.keyLocalNotifyNext);
    if (storedNext != null) _nextFireAt = DateTime.tryParse(storedNext);

    if (_enabled && !_permissionGranted) {
      // 权限被系统里关掉了：提醒不会响，但开关还留着（用户去系统里开回来即可）
      _message = '系统里把通知权限关了，提醒不会响 —— 去手机「设置 → 应用 → SekaiNook → 通知」里打开';
    }
    notifyListeners();
  }

  /// 开启：先要权限，再按当前账本排上今天的提醒
  Future<bool> enable() async {
    if (!supported) {
      _message = '这个平台不支持本地通知；网页版请用上面的浏览器推送';
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
    await syncFromRecords(_lastRecords);

    _message = _nextFireAt == null
        ? '本地提醒已开启：今天任务已经做完，明天再提醒'
        : '本地提醒已开启：每天 21:30 提醒今天还差几个任务';
    notifyListeners();
    return true;
  }

  Future<void> disable() async {
    _enabled = false;
    _nextFireAt = null;
    _scheduledTitle = null;
    _scheduledBody = null;
    await _prefs.setBool(AppConstants.keyLocalNotifyEnabled, false);
    await _prefs.remove(AppConstants.keyLocalNotifyNext);
    await _prefs.remove(AppConstants.keyLocalNotifyDay);
    await _sink.cancelDaily();
    _message = '本地提醒已关闭';
    notifyListeners();
  }

  /// 立刻弹一条（设置页的测试按钮）—— 不等 21:30，装完就能验通道
  Future<bool> sendTest() async {
    if (!supported) {
      _message = '这个平台不支持本地通知；网页版请用上面的浏览器推送';
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

    await _sink.showNow(
      title: 'SekaiNook 测试通知',
      body: '本地通知通了。以后每天 21:30 会提醒今天还差几个任务。',
      payload: tapPayload,
    );

    _busy = false;
    _message = '已发一条本地测试通知，看一下通知栏';
    notifyListeners();
    return true;
  }

  /// 账本刷新后重排提醒：任务做完了就撤掉，没做完就按最新数字改文案
  Future<void> syncFromRecords(List<LedgerRecord> records, {DateTime? now}) async {
    _lastRecords = records;
    if (!supported || !_enabled) return;

    final DateTime ref = now ?? _clock();
    final completion = countDayCompletions(records, now: ref);

    if (completion.isComplete) {
      await _sink.cancelDaily();
      _nextFireAt = null;
      _scheduledTitle = null;
      _scheduledBody = null;
      await _prefs.remove(AppConstants.keyLocalNotifyNext);
      await _prefs.setString(AppConstants.keyLocalNotifyDay, completion.dayKey);
      notifyListeners();
      return;
    }

    final text = reminderTextFor(completion);
    final when = nextFireTime(now: ref);

    await _sink.scheduleDaily(
      beijingWallClock: when,
      title: text.title,
      body: text.body,
      payload: tapPayload,
    );

    _nextFireAt = when;
    _scheduledTitle = text.title;
    _scheduledBody = text.body;
    await _prefs.setString(AppConstants.keyLocalNotifyNext, when.toIso8601String());
    await _prefs.setString(AppConstants.keyLocalNotifyDay, completion.dayKey);
    notifyListeners();
  }

  /// 下一次提醒的时刻（北京墙钟）：今天 21:30 还没到就是今天，过了就明天
  static DateTime nextFireTime({DateTime? now}) {
    final beijing = WeekUtil.beijingNow(now);
    var candidate = DateTime(
      beijing.year,
      beijing.month,
      beijing.day,
      reminderHour,
      reminderMinute,
    );
    if (!candidate.isAfter(beijing)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_constants.dart';
import '../../../config/family_rules.dart';
import '../../../config/garden_config.dart';
import '../../../core/api_client.dart';
import '../../../core/api_exception.dart';
import '../../../core/image_compress.dart';
import '../../../core/task_rules.dart';
import '../../../core/week.dart';
import '../../../data/api/ledger_api.dart';
import '../../../data/api/upload_api.dart';
import '../../../data/models/custom_task.dart';
import '../../../data/models/garden.dart' as garden_models;
import '../../../data/models/ledger_record.dart';
import '../../../data/models/notification_record.dart';
import '../../../data/models/task_config.dart';
import '../../../state/custom_tasks_state.dart';
import '../../../state/family_state.dart';
import '../../../state/garden_state.dart';
import '../../../state/notification_state.dart';
import '../../../state/settings_state.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/state_views.dart';

/// 花园图标 key → Material 图标（与 `garden_page.dart` 的映射一致，
/// 对应 Web 版 `components/garden/GardenIcon.tsx`，未知 key 回退星形）。
IconData _gardenIcon(String key) => switch (key) {
      'book' => Icons.menu_book_outlined,
      'read' => Icons.chrome_reader_mode_outlined,
      'book-open' => Icons.chrome_reader_mode_outlined,
      'calc' => Icons.calculate_outlined,
      'pen' => Icons.edit_outlined,
      'feather' => Icons.edit_outlined,
      'eye' => Icons.visibility_outlined,
      'sport' => Icons.bolt_outlined,
      'home' => Icons.home_outlined,
      'sun' => Icons.wb_sunny_outlined,
      'flower' => Icons.local_florist_outlined,
      'leaf' => Icons.eco_outlined,
      'calendar' => Icons.calendar_today_outlined,
      'trophy' => Icons.emoji_events_outlined,
      'coin' => Icons.monetization_on_outlined,
      'dashboard' => Icons.dashboard_outlined,
      'check' => Icons.check_circle_outline,
      'shop' => Icons.storefront_outlined,
      'history' => Icons.history,
      'star' => Icons.star_outline,
      _ => Icons.star_outline,
    };

/// 首页先摆这几个打卡按钮（顺序按妹妹最常用的排）
const List<String> _quickTaskIds = <String>[
  'finish_homework',
  'read_book',
  'clean_room',
  'take_out_trash',
  'sleep_on_time',
  'wash_dishes',
];

/// 被妈妈退回的申请看过就记在本机，最多留这么多条
const int _seenRejectsMax = 50;

/// 一周七天中文（对应 Web 版 `homeUtils.WEEK_TEXT`）
const List<String> _weekText = <String>[
  '星期日',
  '星期一',
  '星期二',
  '星期三',
  '星期四',
  '星期五',
  '星期六',
];

const Widget _gapXs = SizedBox(height: AppSpacing.xs);
const Widget _gapSm = SizedBox(height: AppSpacing.sm);
const Widget _gapMd = SizedBox(height: AppSpacing.md);

/// 问候语（对应 Web 版 `greetingText`）
String _greetingText(DateTime now) {
  final int hour = now.hour;
  if (hour < 6) return '还没睡呀';
  if (hour < 11) return '早上好';
  if (hour < 14) return '中午好';
  if (hour < 18) return '下午好';
  return '晚上好';
}

/// 日期文案（对应 Web 版 `dateText`）
String _dateText(DateTime now) =>
    '${now.month}月${now.day}日 ${_weekText[now.weekday % 7]}';

/// 本地日历天键（对应 Web 版 `dayKey`，**不用 toIso8601String**）
String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

/// 今天的流水（对应 Web 版 `todayRecords`：按本地日历天筛，只筛不改序）
List<LedgerRecord> _todayRecords(List<LedgerRecord> records, DateTime now) {
  final String today = _dayKey(now);
  return records.where((LedgerRecord r) => _dayKey(r.createdAt) == today).toList();
}

/// 最近 N 天小结（对应 Web 版 `recentSummary`：滚动窗口，只算已入账）
({int income, int expense, int net, int count, int checkins}) _recentSummary(
  List<LedgerRecord> records,
  int days,
  DateTime now,
) {
  final DateTime start = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: days - 1));
  final String startKey = _dayKey(start);
  final String endKey = _dayKey(now);

  var income = 0;
  var expense = 0;
  var count = 0;
  var checkins = 0;
  for (final LedgerRecord r in records) {
    if (!r.isCredited) continue;
    final String key = _dayKey(r.createdAt);
    if (key.compareTo(startKey) < 0 || key.compareTo(endKey) > 0) continue;
    count += 1;
    if (r.amount > 0) {
      income += r.amount;
      checkins += 1;
    } else {
      expense += r.amount;
    }
  }
  return (income: income, expense: expense, net: income + expense, count: count, checkins: checkins);
}

/// 相对时间（对应 Web 版 `relativeTime`）
String _relativeTime(DateTime at, DateTime now) {
  final String hh = at.hour.toString().padLeft(2, '0');
  final String mm = at.minute.toString().padLeft(2, '0');
  final String day = _dayKey(at);
  if (day == _dayKey(now)) return '今天 $hh:$mm';
  if (day == _dayKey(now.subtract(const Duration(days: 1)))) return '昨天 $hh:$mm';
  return '${at.month}月${at.day}日 $hh:$mm';
}

/// 带符号金额（与 `LedgerRecord.signedAmount` 同口径）
String _signed(int amount) => amount > 0 ? '+$amount' : '$amount';

/// 主题色的浅底（妹妹版的「发光」= 主色浅底 + 柔和阴影，不用硬编码色值）
Color _accentTint(Color color) => Color.alphaBlend(color.withValues(alpha: 0.14), Colors.transparent);

/// 妹妹版首页：一眼看到「今天要做什么、我赚了多少、妈妈说了什么」。
///
/// 对应 Web 版 `src/views/home/KidHome.tsx`。数据来自 [FamilyState]（家庭账本）、
/// [GardenState]（阳光花园）、[CustomTasksState]（本机任务列表）、
/// [NotificationState]（妈妈的话）与 [SettingsState]（称呼）。
class KidHomePage extends StatefulWidget {
  const KidHomePage({super.key});

  @override
  State<KidHomePage> createState() => _KidHomePageState();
}

class _KidHomePageState extends State<KidHomePage> {
  /// 拉取失败时页面要说话：不能把「没拉到」显示成「这周一分没赚」
  bool _loadFailed = false;

  /// 日结算补记的提示（进入页面时补一次，只在本次进入提醒一次）
  String? _settleNotice;

  /// 被妈妈退回、已经点过「知道了」的流水 id（本机存档）
  List<String> _seenRejects = <String>[];

  /// 刚解锁的勋章：有一个就弹一次（仪式感），点掉就没了
  garden_models.Badge? _newBadge;

  /// 正在打卡的「我的任务」id：防连点
  String? _checkingId;

  Timer? _timer;
  bool _refreshing = false;

  static const BoxShadow _glowSoft = BoxShadow(
    color: Color(0x3374A7FF),
    blurRadius: AppSpacing.xl,
    spreadRadius: AppSpacing.xs,
  );
  static const Widget _fireIcon = Icon(Icons.local_fire_department_outlined, size: AppFontSize.sm);
  static const Widget _trophyIcon = Icon(Icons.emoji_events_outlined, size: AppFontSize.sm);
  static const Widget _rightIcon = Icon(Icons.chevron_right, size: AppFontSize.md);

  /// 打卡弹窗用的上传接口。
  ///
  /// [FamilyState] 只公开 `LedgerApi`，没有暴露内部的 `ApiClient`，
  /// 而页面不允许改状态层，所以这里自建一个（与账本接口同一套 baseUrl / 超时）。
  static final UploadApi _uploadApi = UploadApi(ApiClient());

  @override
  void initState() {
    super.initState();
    // 花园存档原来只有花园页会 init —— 首页要用它，就得自己装一次（幂等）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GardenState>().init();
      context.read<CustomTasksState>().ensurePresets();
      unawaited(_bootstrap());
    });
    // 「我交的那条批了没有」是孩子最想知道的：20 秒问一次
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      unawaited(_refresh());
    });
  }

  /// 首屏的异步准备：本机存档（看过的驳回、已庆祝的勋章）+ 拉一次账本
  Future<void> _bootstrap() async {
    final List<String> seen = await _readSeenRejects();
    if (!mounted) return;
    setState(() => _seenRejects = seen);
    await _refresh();
    if (!mounted) return;
    await _checkNewBadge();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ---- 本地存档 ----
  //
  // 两个键（看过的驳回 / 已庆祝的勋章）都是**纯本机视角**的存档，
  // 与账本无关，所以直接读设备上的 SharedPreferences（与 main.dart 同一实例）。

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// 读「已经点过知道了」的退回记录；存档坏了当作没记过
  Future<List<String>> _readSeenRejects() async {
    final String? raw = (await _prefs()).getString(AppConstants.keyKidSeenRejects);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final dynamic parsed = jsonDecode(raw);
      if (parsed is List) return parsed.whereType<String>().toList();
    } catch (_) {
      // 存档坏了：当作没记过，最多多看一次提醒
    }
    return <String>[];
  }

  Future<void> _writeSeenRejects(List<String> ids) async {
    try {
      await (await _prefs()).setString(AppConstants.keyKidSeenRejects, jsonEncode(ids));
    } catch (_) {
      // 本机存储不可用：退化成「这次不记」
    }
  }

  /// 读「已经庆祝过的勋章」；本机从来没记过时返回 null（= 第一次在这台设备上打开）
  Future<List<String>?> _readCelebratedBadges() async {
    final String? raw = (await _prefs()).getString(AppConstants.keyBadgesCelebrated);
    if (raw == null || raw.isEmpty) return null;
    try {
      final dynamic parsed = jsonDecode(raw);
      if (parsed is List) return parsed.whereType<String>().toList();
    } catch (_) {
      // 存档坏了就当作第一次打开：只记不弹，总比每次刷新弹一堆好
      return null;
    }
    return null;
  }

  Future<void> _writeCelebratedBadges(List<String> ids) async {
    try {
      await (await _prefs()).setString(AppConstants.keyBadgesCelebrated, jsonEncode(ids));
    } catch (_) {
      // 本机存储不可用：退化成「不弹」
    }
  }

  // ---- 轻提示 ----

  /// 统一的轻提示（对应 Web 版的 antd `message`）
  void _toast(String message, {bool success = false, bool error = false, bool warning = false}) {
    final AppPalette palette = context.palette;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: error
            ? palette.danger
            : success
                ? palette.success
                : warning
                    ? palette.warning
                    : null,
      ),
    );
  }

  // ---- 数据刷新 ----

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final FamilyState family = context.read<FamilyState>();
      try {
        await family.loadLedger();
        if (mounted) setState(() => _loadFailed = false);
      } catch (_) {
        if (mounted) setState(() => _loadFailed = true);
        return;
      }
      // 日结算（开户礼金 / 那天完成的任务不够 5 个 / 到 22:00 没打卡睡觉）：
      // 正确性由服务端幂等 id 保证，本地只按「被结算的那一天」节流，纯粹为了省流量。
      final LedgerSettleResult? settled = await family.settleLedgerOncePerDay();
      if (settled == null || settled.applied.isEmpty) return;
      try {
        await family.loadLedger();
      } catch (_) {
        // 结算已入账，刷新失败不该把页面变成「加载失败」
      }
      if (!mounted) return;
      setState(() => _settleNotice = '账本更新：${describeSettleApplied(settled.applied)}');
      _toast('账本更新：${describeSettleApplied(settled.applied)}', warning: true);
    } finally {
      _refreshing = false;
    }
  }

  /// 解锁新勋章要有仪式感，但同一枚不能每次打开都弹：
  /// 本机记一份「已经庆祝过」的，第一次打开时把当时已有的都算作早就知道。
  Future<void> _checkNewBadge() async {
    final List<garden_models.Badge> badges = context.read<GardenState>().badges;
    final List<String> earnedIds =
        badges.where((garden_models.Badge b) => b.earned).map((garden_models.Badge b) => b.id).toList();
    final List<String>? stored = await _readCelebratedBadges();
    if (!mounted) return;
    if (stored == null) {
      await _writeCelebratedBadges(earnedIds);
      return;
    }
    for (final garden_models.Badge badge in badges) {
      if (!badge.earned || stored.contains(badge.id)) continue;
      await _writeCelebratedBadges(<String>[...stored, badge.id]);
      if (!mounted) return;
      setState(() => _newBadge = badge);
      return;
    }
  }

  // ---- 动作 ----

  /// 花园任务完成（阳光奖励，与家庭账本分开的两本账）
  void _completeGardenTask(garden_models.GardenTask task) {
    final GardenState garden = context.read<GardenState>();
    garden.completeTask(task.id);
    // store 会挡下重复打卡（含连点两次）：这时不能报喜，
    // 不然孩子以为又赚了一份阳光，翻过去数字却没变
    final bool done = garden.tasks.any((garden_models.GardenTask item) => item.id == task.id && item.done);
    if (!done) {
      _toast('「${task.name}」今天已经完成过啦');
      return;
    }
    _toast('+${task.reward} 积分，${task.name}完成啦', success: true);
  }

  /// 「知道了」：这条退回不再提醒（下次退回的是新的一条，照样会提醒）
  void _dismissReject(String id) {
    final List<String> next = <String>[..._seenRejects, id];
    final List<String> trimmed =
        next.length > _seenRejectsMax ? next.sublist(next.length - _seenRejectsMax) : next;
    setState(() => _seenRejects = trimmed);
    unawaited(_writeSeenRejects(trimmed));
  }

  /// 点快捷打卡按钮：先过本地规则（时间窗 / 日限），再打开打卡弹窗
  void _startCheckIn(TaskConfig task) {
    final String? reason = checkTask(
      task,
      context.read<FamilyState>().records,
      now: DateTime.now(),
    );
    if (reason != null) {
      _toast(reason, warning: true);
      return;
    }
    unawaited(_openCheckInSheet(task));
  }

  /// 我的任务打卡：写一条 `user_task_exec` 流水（预置任务用服务端登记的 id）。
  ///
  /// ⚠️ 绝不自造 `custom_<ts>` 之类的 id 去写账本 —— 服务端对未知 task_id 一律 403。
  /// 妈妈加的任务打完卡直接入账；我自己加的要走 pending 等妈妈批，
  /// 否则就成了「自己加任务自己发钱」，是刷分口子。
  Future<void> _checkInMyTask(CustomTask task) async {
    if (_checkingId != null) return;
    setState(() => _checkingId = task.id);
    final String momName = context.read<SettingsState>().momName;
    final FamilyState family = context.read<FamilyState>();
    // 先把 store 引用取出来：下面有 await，之后再碰 context 会踩 async-gap 警告。
    final CustomTasksState customTasks = context.read<CustomTasksState>();
    try {
      final TaskConfig execTask = task.toExecTask(userTaskExecId: CustomTasksState.userTaskExecId);
      await family.api.addLedgerRecord(
        execTask,
        autoApprove: task.createdBy == TaskCreator.parent,
      );
      customTasks.markDone(task.id);
      try {
        await family.loadLedger();
      } catch (_) {
        // 打卡已经成功，刷新失败不该报成「打卡失败」
      }
      if (!mounted) return;
      _toast(
        task.createdBy == TaskCreator.parent
            ? '「${task.name}」打卡成功'
            : '「${task.name}」已提交，等$momName审批',
        success: true,
      );
    } on LedgerApprovalException {
      // 账其实已经记上了，只是「立即入账」那一步没成功：这条以 pending 躺在待审批里，
      // 所以本地也要算今天已完成 —— 不然孩子再点一次，只会撞上服务端的同名日限。
      customTasks.markDone(task.id);
      try {
        await family.loadLedger();
      } catch (_) {
        // 刷新失败不影响下面的提示
      }
      if (!mounted) return;
      _toast(LedgerApprovalException.message, warning: true);
    } on ApiException catch (e) {
      // 服务端的三层日限闸门（同名当日重复 / 当日条数 ≥20 / 当日正分累计 ≥50）都返回 409，
      // 文案照实提示 —— 本地置灰只是省一次白跑的请求，权威永远在服务端。
      if (mounted) _toast(e.message, error: true);
    } catch (_) {
      if (mounted) _toast('打卡失败，请重试', error: true);
    } finally {
      if (mounted) setState(() => _checkingId = null);
    }
  }

  /// 打开打卡弹窗（拍照 / 备注 → 压缩 → 上传 → 记账）
  Future<void> _openCheckInSheet(TaskConfig task) async {
    final bool? submitted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _CheckInSheet(
        task: task,
        isParent: false,
        upload: _uploadApi,
        onSubmitted: (TaskConfig submittedTask, {String? note, String? imageUrl}) =>
            context.read<FamilyState>().api.addLedgerRecord(
                  submittedTask,
                  note: note,
                  imageUrl: imageUrl,
                ),
      ),
    );
    if (submitted != true || !mounted) return;
    try {
      await context.read<FamilyState>().loadLedger();
    } catch (_) {
      // 打卡已经成功，刷新失败不该把成功说成失败
    }
    if (!mounted) return;
    _toast('已提交，等${context.read<SettingsState>().momName}审批', success: true);
  }

  // ---- 派生值 ----

  /// 最近一条「妈妈退回来了」：按时间倒序取第一条还没点过「知道了」的
  LedgerRecord? _latestRejected(FamilyState family) {
    final List<LedgerRecord> rejected = family.records
        .where((LedgerRecord r) => r.isRejected && !_seenRejects.contains(r.id))
        .toList()
      ..sort((LedgerRecord a, LedgerRecord b) => b.createdAt.compareTo(a.createdAt));
    return rejected.isEmpty ? null : rejected.first;
  }

  /// 退回的那条还能不能重交：得还认得出是哪个任务
  TaskConfig? _taskForRecord(LedgerRecord record) {
    for (final TaskConfig task in FamilyRules.taskRules) {
      if (task.id == record.taskId) return task;
    }
    return null;
  }

  List<garden_models.GardenTask> _todoGardenTasks(List<garden_models.GardenTask> tasks) =>
      tasks.where((garden_models.GardenTask task) => !task.done).take(4).toList();

  List<TaskConfig> _quickTasks() {
    final List<TaskConfig> earning = FamilyRules.tasksByType(TaskType.earning);
    return <TaskConfig>[
      for (final String id in _quickTaskIds)
        for (final TaskConfig task in earning)
          if (task.id == id) task,
    ];
  }


  // ---- 页面骨架 ----

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final DateTime now = DateTime.now();
    final FamilyState family = context.watch<FamilyState>();
    final GardenState garden = context.watch<GardenState>();
    final CustomTasksState customTasks = context.watch<CustomTasksState>();
    final NotificationState notices = context.watch<NotificationState>();
    final SettingsState settings = context.watch<SettingsState>();

    final String kidName = settings.kidName;
    final String momName = settings.momName;
    if (kidName.isEmpty && momName.isEmpty) return const LoadingView(message: '正在加载…');

    // 花园进度（分子分母同口径，都来自 garden.tasks）
    final int gardenTotal = garden.tasks.length;
    final int gardenDone = garden.completedCount;
    final int gardenPercent = gardenTotal > 0 ? (gardenDone / gardenTotal * 100).round() : 0;
    final int learningLeft = gardenTotal - gardenDone;
    final int earnedBadges = garden.badges.where((garden_models.Badge b) => b.earned).length;

    // 今日任务进度（只统计设了日限的任务，与账本页同口径）
    final TaskProgress progress = todayProgress(FamilyRules.taskRules, family.records, now: now);
    final int progressDone = progress.done;
    final int progressTotal = progress.total;

    final ({int income, int expense, int net, int count, int checkins}) week =
        _recentSummary(family.records, 7, now);
    final int todayCount = _todayRecords(family.records, now).length;
    final bool showLateAlert = WeekUtil.beijingHour(now) >= 22 && learningLeft > 0;

    final List<garden_models.GardenTask> todoTasks = _todoGardenTasks(garden.tasks);
    final List<TaskConfig> quickTasks = _quickTasks();
    final LedgerRecord? rejected = _latestRejected(family);
    final TaskConfig? rejectedTask = rejected == null ? null : _taskForRecord(rejected);
    final NotificationRecord? latestNotice = notices.items.isEmpty ? null : notices.items.first;
    final SleepTask? sleepTask = _sleepTask(family, now);

    // 新勋章：整屏庆祝一次（点掉即收下）
    final garden_models.Badge? celebrating = _newBadge;
    if (celebrating != null) {
      _newBadge = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_celebrate(celebrating));
      });
    }

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: <Widget>[
            _hero(palette, now, kidName, garden, earnedBadges),
            if (_settleNotice != null) ...<Widget>[
              _gapSm,
              _noticeBar(palette, _settleNotice!, Icons.receipt_long_outlined),
            ],
            if (rejected != null) ...<Widget>[
              _gapSm,
              _rejectCard(palette, momName, rejected, rejectedTask),
            ],
            if (family.pendingCount > 0) ...<Widget>[
              _gapSm,
              _pendingCard(palette, now, momName, family),
            ],
            if (_loadFailed) ...<Widget>[
              _gapSm,
              AppCard(
                highlight: true,
                onTap: () => unawaited(_refresh()),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.cloud_off, size: AppFontSize.md, color: palette.danger),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '没拉到最新数据，点一下重试',
                        style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                      ),
                    ),
                    Text(
                      '重试',
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w700,
                        color: palette.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (showLateAlert) ...<Widget>[
              _gapSm,
              _noticeBar(palette, '已经 22:00 啦，还有 $learningLeft 个学习任务没完成',
                  Icons.nightlight_outlined, onTap: () => context.go('/garden')),
            ],
            if (sleepTask != null) ...<Widget>[
              _gapSm,
              _noticeBar(
                palette,
                '「${sleepTask.task.name}」${sleepTask.windowText}，别忘啦',
                Icons.bedtime_outlined,
                onTap: () => _startCheckIn(sleepTask.task),
              ),
            ],
            _gapSm,
            _gardenTaskCard(palette, garden, gardenDone, gardenTotal, gardenPercent, todoTasks),
            _gapSm,
            _moneyCard(palette, momName, family.balance, week, todayCount, progressDone,
                progressTotal, quickTasks, family.records, now),
            _gapSm,
            _myTasksCard(palette, momName, customTasks, family.records, now),
            if (latestNotice != null) ...<Widget>[
              _gapSm,
              _noticeCard(palette, now, momName, latestNotice),
            ],
            _gapSm,
            _grid(palette, momName, notices.unreadCount),
          ],
        ),
      ),
    );
  }

  /// 22:00 前、睡觉任务还没打卡时给一条能直接点走的提醒
  SleepTask? _sleepTask(FamilyState family, DateTime now) {
    final TaskConfig? task = FamilyRules.taskById('sleep_on_time');
    if (task == null) return null;
    if (WeekUtil.beijingHour(now) >= 22) return null;
    final String? reason = checkTask(task, family.records, now: now);
    if (reason != null) return null;
    final String from = task.window?.start ?? '';
    final String to = task.window?.end ?? '';
    return SleepTask(task, '$from-$to');
  }

  // ---- 1. 顶部（问候 + 阳光大数字）----

  Widget _hero(
    AppPalette palette,
    DateTime now,
    String kidName,
    GardenState garden,
    int earnedBadges,
  ) {
    final garden_models.GardenShopItem? avatarItem = _shopItem(garden.equippedAvatar);
    final garden_models.GardenShopItem? titleItem = _shopItem(garden.equippedTitle);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[palette.primarySoft, palette.cardColor(hasBackground: false)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.primary),
        boxShadow: const <BoxShadow>[_glowSoft],
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            '${_greetingText(now)}，$kidName',
                            style: TextStyle(
                              fontSize: AppFontSize.lg,
                              fontWeight: FontWeight.w700,
                              color: palette.text,
                            ),
                          ),
                        ),
                        if (titleItem != null) ...<Widget>[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: palette.warning.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(AppRadius.full),
                              border: Border.all(color: palette.warning),
                            ),
                            child: Text(
                              titleItem.shortName,
                              style: TextStyle(
                                fontSize: AppFontSize.xs,
                                fontWeight: FontWeight.w600,
                                color: palette.warning,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    _gapXs,
                    Text(
                      _dateText(now),
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              InkWell(
                onTap: () => context.go('/garden'),
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      width: AppSpacing.xl + AppSpacing.md,
                      height: AppSpacing.xl + AppSpacing.md,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.cardColor(hasBackground: false),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color: avatarItem == null ? palette.border : palette.primary,
                          width: avatarItem == null ? 1 : 2,
                        ),
                      ),
                      child: const Text('🏅', style: TextStyle(fontSize: AppFontSize.lg)),
                    ),
                    if (avatarItem != null)
                      Positioned(
                        right: -AppSpacing.xs,
                        bottom: -AppSpacing.xs,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: palette.cardColor(hasBackground: false),
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(color: palette.primary),
                          ),
                          child: Icon(
                            _gardenIcon(avatarItem.icon),
                            size: AppFontSize.sm,
                            color: palette.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _gapSm,
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Icon(Icons.wb_sunny_outlined, size: AppFontSize.lg, color: palette.warning),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${garden.balance}',
                style: TextStyle(
                  fontSize: AppFontSize.num,
                  fontWeight: FontWeight.w800,
                  color: palette.warning,
                  fontFeatures: kTabularNumbers,
                  shadows: <Shadow>[
                    Shadow(color: palette.warning.withValues(alpha: 0.35), blurRadius: AppSpacing.md),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '积分',
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          Text(
            '花园里的阳光，会存进家里的账本，换手机也在',
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
          ),
          _gapSm,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _chip(palette, _fireIcon, '连续 ${garden.streakDays} 天'),
              _chip(palette, _trophyIcon, '勋章 $earnedBadges/${garden.badges.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(AppPalette palette, Widget icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: palette.softColor(hasBackground: false),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconTheme.merge(
            data: IconThemeData(color: palette.primary),
            child: icon,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.xs,
              fontWeight: FontWeight.w600,
              color: palette.text,
              fontFeatures: kTabularNumbers,
            ),
          ),
        ],
      ),
    );
  }

  garden_models.GardenShopItem? _shopItem(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final garden_models.GardenShopItem item in GardenConfig.shopItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  // ---- 通用条 / 卡片 ----

  Widget _noticeBar(AppPalette palette, String text, IconData icon, {VoidCallback? onTap}) {
    return AppCard(
      highlight: true,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(icon, size: AppFontSize.md, color: palette.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right, size: AppFontSize.md, color: palette.primary),
        ],
      ),
    );
  }

  /// 妈妈退回来的：把她的那句话摆在最上面，点一下就能重交
  Widget _rejectCard(
    AppPalette palette,
    String momName,
    LedgerRecord rejected,
    TaskConfig? rejectedTask,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$momName退回了一条',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.danger,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _dismissReject(rejected.id),
                style: TextButton.styleFrom(
                  foregroundColor: palette.textSecondary,
                  textStyle: const TextStyle(fontSize: AppFontSize.xs),
                ),
                child: const Text('知道了'),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  rejected.taskName,
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                _signed(rejected.amount),
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w700,
                  color: palette.danger,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
          _gapXs,
          Text(
            (rejected.note == null || rejected.note!.isEmpty)
                ? '看看哪里不对，改好可以再提交一次'
                : rejected.note!,
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
          ),
          if (rejectedTask != null) ...<Widget>[
            _gapSm,
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  _dismissReject(rejected.id);
                  _startCheckIn(rejectedTask);
                },
                style: TextButton.styleFrom(foregroundColor: palette.primary),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[Text('重新交一次'), _rightIcon],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 等妈妈看：交上去的申请现在到哪一步了，孩子不用瞎猜
  Widget _pendingCard(AppPalette palette, DateTime now, String momName, FamilyState family) {
    final List<LedgerRecord> head = family.pendingRecords.take(3).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '等$momName看',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                '还有 ${family.pendingCount} 条没批',
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: palette.textSecondary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
          _gapXs,
          for (final LedgerRecord record in head)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      record.taskName,
                      style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                    ),
                  ),
                  Text(
                    _signed(record.amount),
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w700,
                      color: palette.primary,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _relativeTime(record.createdAt, now),
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.textTertiary,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                ],
              ),
            ),
          _gapXs,
          Text(
            '$momName有空就会看，批了会自动加进我的积分',
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go('/family'),
              style: TextButton.styleFrom(foregroundColor: palette.primary),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[Text('看看我交了什么'), _rightIcon],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 2. 今日学习任务 ----

  Widget _gardenTaskCard(
    AppPalette palette,
    GardenState garden,
    int done,
    int total,
    int percent,
    List<garden_models.GardenTask> todoTasks,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '今日学习任务',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                '$done/$total',
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
          _gapSm,
          _progress(palette, percent / 100),
          _gapSm,
          if (todoTasks.isEmpty)
            Text(
              '🎉 今天的任务全做完啦，去花园逛逛吧',
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
            )
          else
            for (final garden_models.GardenTask task in todoTasks)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: InkWell(
                  onTap: () => _completeGardenTask(task),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: AppSpacing.xl,
                          height: AppSpacing.xl,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _accentTint(palette.primary),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(
                            _gardenIcon(task.icon),
                            size: AppFontSize.md,
                            color: palette.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                task.name,
                                style: TextStyle(
                                  fontSize: AppFontSize.sm,
                                  fontWeight: FontWeight.w600,
                                  color: palette.text,
                                ),
                              ),
                              Text(
                                '${task.duration} 分钟 · +${task.reward} 积分',
                                style: TextStyle(
                                  fontSize: AppFontSize.xs,
                                  color: palette.textTertiary,
                                  fontFeatures: kTabularNumbers,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '完成',
                          style: TextStyle(
                            fontSize: AppFontSize.sm,
                            fontWeight: FontWeight.w700,
                            color: palette.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go('/garden'),
              style: TextButton.styleFrom(foregroundColor: palette.primary),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[Text('去花园看全部任务'), _rightIcon],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 3. 我的积分 ----

  Widget _moneyCard(
    AppPalette palette,
    String momName,
    num balance,
    ({int income, int expense, int net, int count, int checkins}) week,
    int todayCount,
    int progressDone,
    int progressTotal,
    List<TaskConfig> quickTasks,
    List<LedgerRecord> records,
    DateTime now,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '我的积分',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
            ],
          ),
          Text(
            '攒够可以跟$momName兑现 · 今日任务 $progressDone/$progressTotal · '
            '今天打卡 $todayCount 次',
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: palette.textSecondary,
              fontFeatures: kTabularNumbers,
            ),
          ),
          _gapSm,
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                '$balance',
                style: TextStyle(
                  fontSize: AppFontSize.num,
                  fontWeight: FontWeight.w800,
                  color: palette.primary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '积分',
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: '这一周赚了 '),
                        TextSpan(
                          text: '+${week.income}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: palette.success,
                            fontFeatures: kTabularNumbers,
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                  ),
                  _gapXs,
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: '花掉 '),
                        TextSpan(
                          text: '${week.expense}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: palette.danger,
                            fontFeatures: kTabularNumbers,
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          _gapSm,
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = (constraints.maxWidth - AppSpacing.sm * 2) / 3;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final TaskConfig task in quickTasks)
                    SizedBox(
                      width: width,
                      child: _checkInButton(palette, task, records, now),
                    ),
                ],
              );
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go('/family'),
              style: TextButton.styleFrom(foregroundColor: palette.primary),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[Text('全部打卡任务'), _rightIcon],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkInButton(
    AppPalette palette,
    TaskConfig task,
    List<LedgerRecord> records,
    DateTime now,
  ) {
    final bool done = isTaskDone(task, records, now: now);
    return Material(
      color: done ? palette.softColor(hasBackground: false) : _accentTint(palette.primary),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: done ? null : () => _startCheckIn(task),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: done ? palette.border : palette.primary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                task.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  fontWeight: FontWeight.w600,
                  color: done ? palette.textTertiary : palette.text,
                ),
              ),
              _gapXs,
              Text(
                done ? '✓' : '+${task.value}',
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w700,
                  color: done ? palette.success : palette.primary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 4. 我的任务 ----

  Widget _myTasksCard(
    AppPalette palette,
    String momName,
    CustomTasksState customTasks,
    List<LedgerRecord> records,
    DateTime now,
  ) {
    final List<CustomTask> tasks = customTasks.tasks;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '我的任务',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                '完成一个打一次卡',
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
              ),
            ],
          ),
          _gapSm,
          if (tasks.isEmpty)
            Text(
              '还没有任务，让${momName}加一个，或者自己加一个',
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
            )
          else
            for (final CustomTask task in tasks) ...<Widget>[
              _myTaskRow(palette, momName, task, customTasks, records, now),
              _gapXs,
            ],
          _WishForm(momName: momName, onAdd: _addWish),
          _gapXs,
          Text(
            '自己加的任务不会马上加分：完成时提交，${momName}批了才进账本',
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _myTaskRow(
    AppPalette palette,
    String momName,
    CustomTask task,
    CustomTasksState customTasks,
    List<LedgerRecord> records,
    DateTime now,
  ) {
    // 服务端才是权威：这里置灰只是省一次注定 409 的请求
    final bool done = isRecordedToday(task, records, now: now) || customTasks.isDoneToday(task.id);
    final bool checking = _checkingId == task.id;
    final String meta = task.kind == CustomTaskKind.preset
        ? '每天可以做一次'
        : task.createdBy == TaskCreator.child
            ? '我加的 · 要${momName}批'
            : '${momName}加的';

    return Material(
      color: palette.softColor(hasBackground: false),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: done || checking ? null : () => unawaited(_checkInMyTask(task)),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      task.name,
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w600,
                        color: done ? palette.textTertiary : palette.text,
                      ),
                    ),
                    Text(
                      meta,
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (checking)
                const SizedBox(
                  width: AppFontSize.md,
                  height: AppFontSize.md,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  done ? '✓' : _signed(task.value),
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: done
                        ? palette.success
                        : task.value > 0
                            ? palette.primary
                            : palette.danger,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 自己加一个任务：只写进任务列表，**不入账**；完成时提交，等妈妈批了才加分
  void _addWish(String name, int value) {
    final String momName = context.read<SettingsState>().momName;
    context.read<CustomTasksState>().addTask(
          CustomTaskInput(
            name: name,
            value: value,
            type: TaskType.earning,
            createdBy: TaskCreator.child,
            kind: CustomTaskKind.custom,
          ),
        );
    _toast('「$name」加好啦，完成时点一下，等${momName}批了就有分', success: true);
  }

  // ---- 5. 妈妈说的话 ----

  Widget _noticeCard(
    AppPalette palette,
    DateTime now,
    String momName,
    NotificationRecord notice,
  ) {
    return AppCard(
      onTap: () => context.go('/home/notifications'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.notifications_outlined, size: AppFontSize.sm, color: palette.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '$momName说的话',
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                _relativeTime(notice.createdAt, now),
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: palette.textTertiary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
          _gapXs,
          Text(
            notice.title,
            style: TextStyle(
              fontSize: AppFontSize.md,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          if (notice.body != null && notice.body!.isNotEmpty) ...<Widget>[
            _gapXs,
            Text(
              notice.body!,
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  // ---- 6. 宫格入口 ----

  Widget _grid(AppPalette palette, String momName, int unreadCount) {
    final List<_GridEntry> entries = <_GridEntry>[
      _GridEntry('去打卡', Icons.check_circle_outline, () => context.go('/family')),
      _GridEntry('背古诗', Icons.menu_book_outlined, () => context.go('/garden')),
      _GridEntry('我的花园', Icons.wb_sunny_outlined, () => context.go('/garden')),
      _GridEntry(
        '$momName的话',
        Icons.notifications_outlined,
        () => context.go('/home/notifications'),
        badge: unreadCount,
      ),
      _GridEntry('本周计划', Icons.calendar_today_outlined, () => context.go('/family/plan')),
      _GridEntry('我的账本', Icons.account_balance_wallet_outlined, () => context.go('/family')),
      _GridEntry('我的勋章', Icons.emoji_events_outlined, () => context.go('/garden')),
      _GridEntry('设置', Icons.settings_outlined, () => context.go('/settings')),
    ];

    return AppCard(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = (constraints.maxWidth - AppSpacing.sm * 3) / 4;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final _GridEntry entry in entries)
                SizedBox(
                  width: width,
                  child: InkWell(
                    onTap: entry.onTap,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Column(
                        children: <Widget>[
                          Stack(
                            clipBehavior: Clip.none,
                            children: <Widget>[
                              Container(
                                width: AppSpacing.xl + AppSpacing.sm,
                                height: AppSpacing.xl + AppSpacing.sm,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _accentTint(palette.primary),
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                ),
                                child: Icon(
                                  entry.icon,
                                  size: AppFontSize.md,
                                  color: palette.primary,
                                ),
                              ),
                              if (entry.badge > 0)
                                Positioned(
                                  right: -AppSpacing.xs,
                                  top: -AppSpacing.xs,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.danger,
                                      borderRadius: BorderRadius.circular(AppRadius.full),
                                    ),
                                    child: Text(
                                      entry.badge > 99 ? '99+' : '${entry.badge}',
                                      style: TextStyle(
                                        fontSize: AppFontSize.xs,
                                        fontWeight: FontWeight.w700,
                                        color: palette.surface,
                                        fontFeatures: kTabularNumbers,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          _gapXs,
                          Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: AppFontSize.xs, color: palette.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _progress(AppPalette palette, double value) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: AppSpacing.sm,
        backgroundColor: palette.surfaceSoft,
        valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
      ),
    );
  }

  // ---- 弹窗 ----

  /// 解锁新勋章的仪式感：压暗整屏，中间弹一张卡，点掉即收下
  Future<void> _celebrate(garden_models.Badge badge) async {
    final AppPalette palette = context.palette;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: palette.text.withValues(alpha: 0.6),
      builder: (BuildContext dialogContext) => Dialog(
        backgroundColor: palette.cardColor(hasBackground: false),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: AppSpacing.xl + AppSpacing.lg,
                height: AppSpacing.xl + AppSpacing.lg,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accentTint(palette.warning),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  boxShadow: const <BoxShadow>[_glowSoft],
                ),
                child: Icon(
                  _gardenIcon(badge.icon),
                  size: AppFontSize.xl,
                  color: palette.warning,
                ),
              ),
              _gapMd,
              Text(
                '解锁新勋章',
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
              _gapXs,
              Text(
                badge.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFontSize.xl,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
              _gapXs,
              Text(
                badge.description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
              _gapMd,
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('好耶，收下啦'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 宫格入口的一条
class _GridEntry {
  const _GridEntry(this.label, this.icon, this.onTap, {this.badge = 0});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
}

/// 22:00 前的睡觉提醒
class SleepTask {
  const SleepTask(this.task, this.windowText);

  final TaskConfig task;
  final String windowText;
}

/// 「自己加一个任务」的小表单（只写进任务列表，不入账）
class _WishForm extends StatefulWidget {
  const _WishForm({required this.momName, required this.onAdd});

  final String momName;
  final void Function(String name, int value) onAdd;

  @override
  State<_WishForm> createState() => _WishFormState();
}

class _WishFormState extends State<_WishForm> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _value = TextEditingController(text: '5');

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先写一个任务名吧'), duration: Duration(seconds: 2)),
      );
      return;
    }
    final int parsed = int.tryParse(_value.text.trim()) ?? 5;
    widget.onAdd(name, parsed.clamp(1, CustomTasksState.maxTaskValue));
    _name.clear();
    _value.text = '5';
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _name,
                maxLength: 20,
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: '我想做的任务',
                  hintStyle: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                  filled: true,
                  fillColor: palette.softColor(hasBackground: false),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: AppSpacing.xl * 3,
              child: TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  color: palette.text,
                  fontFeatures: kTabularNumbers,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '积分',
                  hintStyle: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                  filled: true,
                  fillColor: palette.softColor(hasBackground: false),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(onPressed: _submit, child: const Text('加一个')),
          ],
        ),
      ],
    );
  }
}

/// 打卡弹窗（对应 Web 版 `components/CheckInModal.tsx`）。
///
/// 妹妹版：提交申请，等妈妈审批；扣分任务必须写清原因（妈妈会看到）。
class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet({
    required this.task,
    required this.isParent,
    required this.upload,
    required this.onSubmitted,
  });

  final TaskConfig task;
  final bool isParent;
  final UploadApi upload;
  final Future<void> Function(TaskConfig task, {String? note, String? imageUrl}) onSubmitted;

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  static final ImagePicker _picker = ImagePicker();

  final TextEditingController _note = TextEditingController();
  Uint8List? _photo;
  String? _photoUrl;
  bool _uploading = false;
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _isDeduct => widget.task.value < 0;

  Future<void> _pick(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source, imageQuality: 90);
      if (picked == null) return;
      final Uint8List raw = await picked.readAsBytes();
      final Uint8List compressed = compressImage(raw) ?? raw;
      if (!mounted) return;
      setState(() {
        _photo = compressed;
        _photoUrl = null;
      });
      await _uploadPhoto();
    } catch (_) {
      if (mounted) _toast('照片选不了，换一张试试');
    }
  }

  Future<void> _uploadPhoto() async {
    final Uint8List? bytes = _photo;
    if (bytes == null) return;
    setState(() => _uploading = true);
    try {
      final UploadResult result = await widget.upload.upload(bytes);
      if (!mounted) return;
      setState(() => _photoUrl = result.url);
    } catch (e) {
      if (mounted) _toast('照片没传上去：$e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    final String note = _note.text.trim();
    if (_isDeduct && note.isEmpty) {
      _toast('写一句原因，让女儿知道为什么扣分', warning: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmitted(
        widget.task,
        note: note.isEmpty ? null : note,
        imageUrl: _photoUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(
        e is LedgerApprovalException ? LedgerApprovalException.message : '$e',
        error: true,
      );
    }
  }

  void _toast(String message, {bool error = false, bool warning = false}) {
    final AppPalette palette = context.palette;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: error
            ? palette.danger
            : warning
                ? palette.warning
                : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TaskConfig task = widget.task;
    final String unit = task.unit;

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      backgroundColor: palette.cardColor(hasBackground: false),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - AppSpacing.xl * 2,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '打卡/申请打卡：${task.name}',
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              _gapSm,
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: _accentTint(_isDeduct ? palette.danger : palette.success),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '本次${_isDeduct ? '扣' : '获得'} ${task.value.abs()} $unit',
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w700,
                        color: _isDeduct ? palette.danger : palette.success,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                    if (task.description != null && task.description!.isNotEmpty) ...<Widget>[
                      _gapXs,
                      Text(
                        task.description!,
                        style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              _gapSm,
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : () => unawaited(_pick(ImageSource.camera)),
                    icon: const Icon(Icons.photo_camera_outlined, size: AppFontSize.md),
                    label: const Text('拍照'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : () => unawaited(_pick(ImageSource.gallery)),
                    icon: const Icon(Icons.photo_library_outlined, size: AppFontSize.md),
                    label: const Text('从相册选'),
                  ),
                ],
              ),
              if (_photo != null) ...<Widget>[
                _gapSm,
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Stack(
                    children: <Widget>[
                      Image.memory(
                        _photo!,
                        width: double.infinity,
                        height: AppSpacing.xl * 4,
                        fit: BoxFit.cover,
                      ),
                      if (_uploading)
                        const Positioned.fill(
                          child: Center(
                            child: SizedBox(
                              width: AppFontSize.lg,
                              height: AppFontSize.lg,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _photo = null;
                              _photoUrl = null;
                            }),
                    style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
                    child: const Text('移除'),
                  ),
                ),
              ],
              _gapXs,
              TextField(
                controller: _note,
                maxLines: 3,
                maxLength: 200,
                enabled: !_submitting,
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  labelText: _isDeduct ? '为什么扣分（必填，女儿会看到）' : '备注',
                  labelStyle: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                  hintText: _isDeduct
                      ? '写清原因，例如：说好只看 30 分钟却看了一下午'
                      : '填写任务备注（可选）',
                  hintStyle: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                  filled: true,
                  fillColor: palette.softColor(hasBackground: false),
                  contentPadding: const EdgeInsets.all(AppSpacing.sm),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
              _gapSm,
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _submitting ? null : () => unawaited(_submit()),
                    child: Text(
                      _submitting
                          ? '提交中…'
                          : widget.isParent
                              ? (_isDeduct ? '确认扣 ${task.value.abs()} $unit' : '确认打卡')
                              : '提交申请',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

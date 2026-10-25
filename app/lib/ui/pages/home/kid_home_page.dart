import 'package:sekainook_app/fl_ui/dialog.dart';
import 'package:sekainook_app/ui/icons/icons.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sekainook_app/ui/widgets/app_toast.dart';
import 'package:sekainook_app/ui/widgets/app_loading.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_constants.dart';
import '../../../config/family_rules.dart';
import '../../../config/garden_config.dart';
import '../../../core/api_client.dart';
import '../../../core/image_compress.dart';
import '../../../core/task_rules.dart';
import '../../../core/time_text.dart';
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
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../shell/app_nav_bar.dart';
import '../../shell/app_top_bar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/motion_widgets.dart';
import '../../widgets/state_views.dart';
import '../../widgets/motion/app_buttons.dart';

/// 花园图标 key → Material 图标（与 `garden_page.dart` 的映射一致，
/// 对应 Web 版 `components/garden/GardenIcon.tsx`，未知 key 回退星形）。
Glyph _gardenIcon(String key) => switch (key) {
      'book' => AppIcons.book,
      'read' => AppIcons.book,
      'book-open' => AppIcons.book,
      'calc' => AppIcons.calculate,
      'pen' => AppIcons.edit,
      'feather' => AppIcons.edit,
      'eye' => AppIcons.eye,
      'sport' => AppIcons.bolt,
      'home' => AppIcons.home,
      'sun' => AppIcons.sun,
      'flower' => AppIcons.flower,
      'leaf' => AppIcons.leaf,
      'calendar' => AppIcons.calendar,
      'trophy' => AppIcons.trophy,
      'coin' => AppIcons.savings,
      'dashboard' => AppIcons.dashboard,
      'check' => AppIcons.checkCircle,
      'shop' => AppIcons.store,
      'history' => AppIcons.history,
      'star' => AppIcons.star,
      _ => AppIcons.star,
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

/// 带符号金额（与 `LedgerRecord.signedAmount` 同口径）
String _signed(int amount) => amount > 0 ? '+$amount' : '$amount';

/// 账本分页在路由里的查询参数名。
///
/// 对应 Web 版 `goLedger(tab)` 的 `setViewState('family.activeTab', ...)` 搬到地址栏：
/// `/family?tab=<tasks|pending|history>`（缺省 `tasks`）。
const String _familyTabParam = 'tab';

/// 去花园的某个菜单（对应 Web 版 `goGarden(menu)`：先把菜单选好，落地就是那一页）。
///
/// 菜单 key 来自 `GardenConfig.menus`（`poem`=古诗背诵、`garden`=阳光花园、
/// `rewards`=我的奖励、`tasks`=今日任务…），参数名用 [GardenConfig.menuParam]。
/// 用 URL 承载菜单是为了让系统返回键沿菜单回退，而不是直接退出花园。
String _gardenPath(String menu) => '/garden?${GardenConfig.menuParam}=$menu';

/// 去账本的某一页：打卡任务（`tasks`）/ 待审批（`pending`）/ 历史记录（`history`）。
///
/// 对应 Web 版 `goLedger(tab)`：Web 内部第三个 Tab 叫 `records`，URL 契约里统一叫 `history`。
String _familyPath(String tab) => '/family?$_familyTabParam=$tab';

/// 主题色的浅底（妹妹版的「发光」= 主色浅底 + 柔和阴影，不用硬编码色值）
Color _accentTint(Color color) => Color.alphaBlend(color.withValues(alpha: 0.14), Colors.transparent);

/// 「14% 有色浅底」（[_accentTint] 那种图标盒）上该用的图标 / 文字色。
///
/// [_accentTint] 给的是半透明色、实际合成在卡片底上，所以这里拿卡片底当合成基色
/// 判断明暗 —— 深底配亮字、浅底配深字（见 [AppPalette.onColor]）。直接把主色当字色，
/// 在午夜蓝这类深色主题里会和深底糊在一起。
Color _onAccentTint(AppPalette palette, Color color) => palette.onColor(
  Color.alphaBlend(color.withValues(alpha: 0.14), palette.cardColor(hasBackground: false)),
);

/// 「14% 有色浅底」上的次要文字色（说明、备注这种）
Color _onAccentTintSoft(AppPalette palette, Color color) => palette.onColorSoft(
  Color.alphaBlend(color.withValues(alpha: 0.14), palette.cardColor(hasBackground: false)),
);

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

class _KidHomePageState extends State<KidHomePage> with WidgetsBindingObserver {
  /// 拉取失败时页面要说话：不能把「没拉到」显示成「这周一分没赚」
  bool _loadFailed = false;

  /// 日结算补记的提示（进入页面时补一次，只在本次进入提醒一次）
  String? _settleNotice;

  /// 被妈妈退回、已经点过「知道了」的流水 id（本机存档）
  List<String> _seenRejects = <String>[];

  /// 刚解锁的勋章：有一个就弹一次（仪式感），点掉就没了
  garden_models.Badge? _newBadge;

  Timer? _timer;
  bool _refreshing = false;

  static const BoxShadow _glowSoft = BoxShadow(
    color: Color(0x3374A7FF),
    blurRadius: AppSpacing.xl,
    spreadRadius: AppSpacing.xs,
  );
  static const Widget _fireIcon = GlyphIcon(AppIcons.fire, size: AppFontSize.sm);
  static const Widget _trophyIcon = GlyphIcon(AppIcons.trophy, size: AppFontSize.sm);
  static const Widget _rightIcon = GlyphIcon(AppIcons.chevronForward, size: AppFontSize.md);

  /// 打卡弹窗用的上传接口。
  ///
  /// [FamilyState] 只公开 `LedgerApi`，没有暴露内部的 `ApiClient`，
  /// 而页面不允许改状态层，所以这里自建一个（与账本接口同一套 baseUrl / 超时）。
  static final UploadApi _uploadApi = UploadApi(ApiClient.shared);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      // 后台不问（对应 Web 版轮询里的 document.hidden 判断），回前台时补一次
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
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
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// 回到前台立刻补一次：后台期间跳过的轮询不用再等下一个 20 秒
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(_refresh());
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
    AppToast.show(
      context,
      message,
      tone: error
          ? AppToastTone.error
          : success
              ? AppToastTone.success
              : warning
                  ? AppToastTone.warning
                  : AppToastTone.neutral,
      duration: const Duration(seconds: 2),
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
      LedgerSettleResult? settled;
      try {
        settled = await family.settleLedgerOncePerDay();
      } catch (_) {
        // 结算失败不挡首页（P-5）：账本上面已经刷新过了，下次进来再结算
        return;
      }
      if (settled == null || settled.applied.isEmpty) return;
      // 提到闭包外取一次：在 setState 回调里访问会丢掉非空提升
      final applied = settled.applied;
      try {
        await family.loadLedger();
      } catch (_) {
        // 结算已入账，刷新失败不该把页面变成「加载失败」
      }
      if (!mounted) return;
      setState(() => _settleNotice = '账本更新：${describeSettleApplied(applied)}');
      _toast('账本更新：${describeSettleApplied(applied)}', warning: true);
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
    // 真完成了才报喜：整页盖一次对勾光环
    showBurst(context);
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

  /// 打开打卡弹窗（拍照 / 备注 → 压缩 → 上传 → 记账）。
  ///
  /// 「我的任务」与上面的快捷按钮都走这里。`custom` 传进来表示这次打卡来自
  /// 一条本地任务：妈妈加的 / 两条预置任务即时到账，我自己加的要等妈妈批；
  /// 提交成功后还要把它标成「今天做过」。
  Future<void> _openCheckInSheet(TaskConfig task, {CustomTask? custom}) async {
    // 妈妈加的任务与预置任务走即时到账（与以前 `_checkInMyTask` 的判据一致）
    final bool isParent = custom?.createdBy == TaskCreator.parent;
    final bool? submitted = await showAppSheet<bool>(
      context: context,
      builder: (BuildContext sheetContext) => _CheckInSheet(
        task: task,
        isParent: isParent,
        upload: _uploadApi,
        onSubmitted: (TaskConfig submittedTask, {String? note, String? imageUrl}) =>
            context.read<FamilyState>().api.addLedgerRecord(
                  submittedTask,
                  note: note,
                  imageUrl: imageUrl,
                  autoApprove: isParent,
                ),
      ),
    );
    if (submitted != true || !mounted) return;
    // 自定义任务要标「今天做过」：它提交时用的是 user_task_exec，
    // 账本流水对不上本地 id，少了这一笔标记按钮就一直是可点的
    if (custom != null) {
      context.read<CustomTasksState>().markDone(custom.id);
    }
    // 弹窗里提交真的成功了才报喜
    showBurst(context);
    try {
      await context.read<FamilyState>().loadLedger();
    } catch (_) {
      // 打卡已经成功，刷新失败不该把成功说成失败
    }
    if (!mounted) return;
    final String momName = context.read<SettingsState>().momName;
    _toast(
      isParent ? '「${task.name}」打卡成功' : '「${task.name}」已提交，等$momName审批',
      success: true,
    );
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
    if (kidName.isEmpty && momName.isEmpty) {
      // 首屏还没拿到称呼：铺骨架屏，不要整页转圈（LoadingView 留给局部）
      return const SafeArea(child: _HomeSkeleton());
    }

    // 花园进度（分子分母同口径，都来自 garden.tasks）
    final int gardenTotal = garden.tasks.length;
    final int gardenDone = garden.completedCount;
    final int gardenPercent = gardenTotal > 0 ? (gardenDone / gardenTotal * 100).round() : 0;
    final int learningLeft = gardenTotal - gardenDone;
    final int earnedBadges = garden.badges.where((garden_models.Badge b) => b.earned).length;

    final ({int income, int expense, int net, int count, int checkins}) week =
        _recentSummary(family.records, 7, now);
    final int todayCount = _todayRecords(family.records, now).length;
    // 22:00 后还没做完学习任务就提醒：与 Web 版 KidHome 的 now.getHours() 同口径，
    // 用**设备本地时间**（不是东八区，那套只服务 /api/ledger/settle 的日结算）
    final bool showLateAlert = now.hour >= 22 && learningLeft > 0;

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
      body: SafeArea(
        child: ListView(
          // 底部让出底栏胶囊（MainShell 开了 extendBody，它浮在内容之上）
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md + AppTopBar.contentInset(context),
            AppSpacing.md,
            AppSpacing.xl + AppNavBar.contentInset(context),
          ),
          children: <Widget>[
            EnterBox(index: 0, child: _hero(palette, now, kidName, garden, earnedBadges)),
            if (_settleNotice != null) ...<Widget>[
              _gapSm,
              EnterBox(
                index: 1,
                child: _noticeBar(palette, _settleNotice!, AppIcons.receipt),
              ),
            ],
            if (rejected != null) ...<Widget>[
              _gapSm,
              EnterBox(index: 2, child: _rejectCard(palette, momName, rejected, rejectedTask)),
            ],
            if (family.pendingCount > 0) ...<Widget>[
              _gapSm,
              EnterBox(index: 3, child: _pendingCard(palette, now, momName, family)),
            ],
            if (_loadFailed) ...<Widget>[
              _gapSm,
              EnterBox(
                index: 4,
                child: AppCard(
                  highlight: true,
                  onTap: () => unawaited(_refresh()),
                  child: Row(
                    children: <Widget>[
                      GlyphIcon(AppIcons.cloudOff, size: AppFontSize.md, color: palette.danger),
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
              ),
            ],
            if (showLateAlert) ...<Widget>[
              _gapSm,
              EnterBox(
                index: 5,
                child: _noticeBar(
                  palette,
                  '已经 22:00 啦，还有 $learningLeft 个学习任务没完成',
                  AppIcons.moon,
                  pulseColor: palette.warning,
                  onTap: () => context.go(_gardenPath('tasks')),
                ),
              ),
            ],
            if (sleepTask != null) ...<Widget>[
              _gapSm,
              EnterBox(
                index: 6,
                child: _noticeBar(
                  palette,
                  '「${sleepTask.task.name}」${sleepTask.windowText}，别忘啦',
                  AppIcons.moon,
                  onTap: () => _startCheckIn(sleepTask.task),
                ),
              ),
            ],
            _gapSm,
            EnterBox(
              index: 7,
              child:
                  _gardenTaskCard(palette, garden, gardenDone, gardenTotal, gardenPercent, todoTasks),
            ),
            _gapSm,
            EnterBox(
              index: 8,
              child: _moneyCard(palette, momName, family.balance, week, todayCount,
                  quickTasks, family.records, now),
            ),
            _gapSm,
            EnterBox(
              index: 9,
              child: _myTasksCard(palette, momName, customTasks, family.records, now),
            ),
            if (latestNotice != null) ...<Widget>[
              _gapSm,
              EnterBox(index: 10, child: _noticeCard(palette, now, momName, latestNotice)),
            ],
            _gapSm,
            EnterBox(index: 10, child: _grid(palette, momName, notices.unreadCount)),
          ],
        ),
      ),
    );
  }

  /// 22:00 前、睡觉任务还没打卡时给一条能直接点走的提醒
  SleepTask? _sleepTask(FamilyState family, DateTime now) {
    final TaskConfig? task = FamilyRules.taskById('sleep_on_time');
    if (task == null) return null;
    if (now.hour >= 22) return null;
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
    final TextStyle chipStyle = _chipStyle(palette);
    // hero 是一整块「有色底」：这里的字 / 图标一律取 onSoft / onColorSoft 派生色，不取 text*。
    // 原来的渐变是 `primarySoft → 卡片底`，跨了「深半 / 浅半」两段（原始主题 #2A2A4A → 白），
    // 任何单一字色都会在其中一半上糊掉；收成同族的 `主色 → 主色浅调` 后整块底才是一个色系。
    final Color heroText = palette.onSoft;
    final Color heroSoft = palette.onColorSoft(palette.primarySoft);
    // 称号小药丸：原来「16% 警告色盖在渐变上」，合成结果随位置变、算不出前景色；
    // 换成实色警告底，底色确定，字色就能确定地取 onColor。
    final Color titleChipText = palette.onColor(palette.warning);

    return Container(
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[palette.primary, palette.primarySoft],
        ),
        shadows: const <BoxShadow>[_glowSoft],
        shape: AppShape.all(AppRadius.lg, side: BorderSide(color: palette.primary)),
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
                              color: heroText,
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
                            decoration: ShapeDecoration(
                              color: palette.warning,
                              shape: AppShape.all(AppRadius.full, side: BorderSide(color: palette.warning)),
                            ),
                            child: Text(
                              titleItem.shortName,
                              style: TextStyle(
                                fontSize: AppFontSize.xs,
                                fontWeight: FontWeight.w600,
                                color: titleChipText,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    _gapXs,
                    Text(
                      _dateText(now),
                      style: TextStyle(fontSize: AppFontSize.xs, color: heroSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              PressInkWell(
                onTap: () => context.go(_gardenPath('rewards')),
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      width: AppSpacing.xl + AppSpacing.md,
                      height: AppSpacing.xl + AppSpacing.md,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: palette.cardColor(hasBackground: false),
                        shape: AppShape.all(AppRadius.full, side: BorderSide(color: avatarItem == null ? palette.border : palette.primary, width: avatarItem == null ? 1 : 2)),
                      ),
                      child: const Text('🏅', style: TextStyle(fontSize: AppFontSize.lg)),
                    ),
                    if (avatarItem != null)
                      Positioned(
                        right: -AppSpacing.xs,
                        bottom: -AppSpacing.xs,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: ShapeDecoration(
                            color: palette.cardColor(hasBackground: false),
                            shape: AppShape.all(AppRadius.full, side: BorderSide(color: palette.primary)),
                          ),
                          child: GlyphIcon(
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
              GlyphIcon(AppIcons.sun, size: AppFontSize.lg, color: heroText),
              const SizedBox(width: AppSpacing.xs),
              AnimatedCount(
                value: garden.balance,
                style: TextStyle(
                  fontSize: AppFontSize.num,
                  fontWeight: FontWeight.w800,
                  color: heroText,
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
                  color: heroSoft,
                ),
              ),
            ],
          ),
          Text(
            '花园里的阳光，会存进家里的账本，换手机也在',
            style: TextStyle(fontSize: AppFontSize.xs, color: heroSoft),
          ),
          _gapSm,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _chip(
                palette,
                _fireIcon,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('连续 ', style: chipStyle),
                    AnimatedCount(value: garden.streakDays, style: chipStyle),
                    Text(' 天', style: chipStyle),
                  ],
                ),
              ),
              _chip(
                palette,
                _trophyIcon,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('勋章 ', style: chipStyle),
                    AnimatedCount(value: earnedBadges, style: chipStyle),
                    Text('/${garden.badges.length}', style: chipStyle),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 胶囊里的文字样式（等宽数字，数字滚动时宽度不跳）
  TextStyle _chipStyle(AppPalette palette) => TextStyle(
        fontSize: AppFontSize.xs,
        fontWeight: FontWeight.w600,
        color: palette.text,
        fontFeatures: kTabularNumbers,
      );

  Widget _chip(AppPalette palette, Widget icon, Widget label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: ShapeDecoration(
        color: palette.softColor(hasBackground: false),
        shape: AppShape.all(AppRadius.full, side: BorderSide(color: palette.border)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconTheme.merge(
            data: IconThemeData(color: palette.primary),
            child: icon,
          ),
          const SizedBox(width: AppSpacing.xs),
          DefaultTextStyle.merge(style: _chipStyle(palette), child: label),
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

  /// [pulseColor] 给了就在最前面点一颗呼吸的小圆点（22 点提醒这类「注意我」的信号）
  Widget _noticeBar(
    AppPalette palette,
    String text,
    Glyph icon, {
    VoidCallback? onTap,
    Color? pulseColor,
  }) {
    return AppCard(
      highlight: true,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          if (pulseColor != null) ...<Widget>[
            PulseDot(color: pulseColor),
            const SizedBox(width: AppSpacing.xs),
          ],
          GlyphIcon(icon, size: AppFontSize.md, color: palette.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          GlyphIcon(AppIcons.chevronForward, size: AppFontSize.md, color: palette.primary),
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
              PulseDot(color: palette.danger),
              const SizedBox(width: AppSpacing.xs),
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
              AppTextButton(
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
              child: AppTextButton(
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
              PulseDot(color: palette.primary),
              const SizedBox(width: AppSpacing.xs),
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
                    relativeDayTime(record.createdAt, now: now),
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
            child: AppTextButton(
              onPressed: () => context.go(_familyPath('pending')),
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
              // 已完成 / 总数：数字会滚，基线对齐保住排版
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  AnimatedCount(
                    value: done,
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                  Text(
                    '/$total',
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                ],
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
            for (final MapEntry<int, garden_models.GardenTask> entry in todoTasks.asMap().entries)
              EnterBox(index: entry.key, child: _gardenTodoRow(palette, entry.value)),
          Align(
            alignment: Alignment.centerRight,
            child: AppTextButton(
              onPressed: () => context.go(_gardenPath('tasks')),
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

  /// 花园待办里的一行：按下去有回弹（点击后照旧去完成任务）
  Widget _gardenTodoRow(AppPalette palette, garden_models.GardenTask task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: PressInkWell(
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
                decoration: ShapeDecoration(
                  color: _accentTint(palette.primary),
                  shape: AppShape.all(AppRadius.md),
                ),
                child: GlyphIcon(
                  _gardenIcon(task.icon),
                  size: AppFontSize.md,
                  color: _onAccentTint(palette, palette.primary),
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
    );
  }

  // ---- 3. 我的积分 ----

  Widget _moneyCard(
    AppPalette palette,
    String momName,
    num balance,
    ({int income, int expense, int net, int count, int checkins}) week,
    int todayCount,
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
            '攒够可以跟$momName兑现 · 今天打卡 $todayCount 次',
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
              AnimatedCount(
                value: balance,
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
                  // 三个快速打卡按钮错峰入场
                  for (int i = 0; i < quickTasks.length; i++)
                    EnterBox(
                      index: i,
                      child: SizedBox(
                        width: width,
                        child: _checkInButton(palette, quickTasks[i], records, now),
                      ),
                    ),
                ],
              );
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppTextButton(
              onPressed: () => context.go(_familyPath('tasks')),
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
      child: PressInkWell(
        onTap: done ? null : () => _startCheckIn(task),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: ShapeDecoration(
              shape: AppShape.all(AppRadius.md, side: BorderSide(color: done ? palette.border : palette.primary)),
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
                  color: done ? palette.textTertiary : _onAccentTint(palette, palette.primary),
                ),
              ),
              _gapXs,
              Text(
                done ? '✓' : '+${task.value}',
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w700,
                  color: done ? palette.success : _onAccentTint(palette, palette.primary),
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
            // 任务条目逐条淡入上浮
            for (final MapEntry<int, CustomTask> entry in tasks.asMap().entries) ...<Widget>[
              EnterBox(
                index: entry.key,
                child: _myTaskRow(palette, momName, entry.value, customTasks, records, now),
              ),
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
    final String baseMeta = task.kind == CustomTaskKind.preset
        ? '每天可以做一次'
        : task.createdBy == TaskCreator.child
            ? '我加的 · 要${momName}批'
            : '${momName}加的';
    // 要照片的任务提前说一声，别等点了进去才发现交不了
    final String meta = task.requirePhoto ? '$baseMeta · 要拍照' : baseMeta;

    return Material(
      color: palette.softColor(hasBackground: false),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: PressInkWell(
        // 点一下先开打卡弹窗（拍照 / 备注），不再直接写流水
        onTap: done
            ? null
            : () => unawaited(_openCheckInSheet(
                  task.toExecTask(userTaskExecId: CustomTasksState.userTaskExecId),
                  custom: task,
                )),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: ShapeDecoration(
              shape: AppShape.all(AppRadius.md, side: BorderSide(color: palette.border)),
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
              // 提交态在弹窗里（弹窗自带转圈 / 置灰），这一行只显示结果
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
              GlyphIcon(AppIcons.bell, size: AppFontSize.sm, color: palette.primary),
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
                relativeDayTime(notice.createdAt, now: now),
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
      _GridEntry('去打卡', AppIcons.checkCircle, () => context.go(_familyPath('tasks'))),
      _GridEntry('背古诗', AppIcons.book, () => context.go(_gardenPath('poem'))),
      _GridEntry('我的花园', AppIcons.sun, () => context.go(_gardenPath('garden'))),
      _GridEntry(
        '$momName的话',
        AppIcons.bell,
        () => context.go('/home/notifications'),
        badge: unreadCount,
      ),
      _GridEntry('本周计划', AppIcons.calendar, () => context.go('/family/plan')),
      _GridEntry('我的账本', AppIcons.wallet, () => context.go(_familyPath('history'))),
      _GridEntry('我的勋章', AppIcons.trophy, () => context.go(_gardenPath('rewards'))),
      _GridEntry('设置', AppIcons.settings, () => context.go('/settings')),
    ];

    return AppCard(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = (constraints.maxWidth - AppSpacing.sm * 3) / 4;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              // 宫格逐格冒出来
              for (final MapEntry<int, _GridEntry> entry in entries.asMap().entries)
                EnterBox(
                  index: entry.key,
                  child: SizedBox(width: width, child: _gridTile(palette, entry.value)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 宫格里的一个入口：按下去回弹，图标块仍用主色的浅色底
  Widget _gridTile(AppPalette palette, _GridEntry entry) {
    return PressInkWell(
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
                  decoration: ShapeDecoration(
                    color: _accentTint(palette.primary),
                    shape: AppShape.all(AppRadius.md),
                  ),
                  child: GlyphIcon(
                    entry.icon,
                    size: AppFontSize.md,
                    color: _onAccentTint(palette, palette.primary),
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
                      decoration: ShapeDecoration(
                        color: palette.danger,
                        shape: AppShape.all(AppRadius.full),
                      ),
                      child: Text(
                        entry.badge > 99 ? '99+' : '${entry.badge}',
                        style: TextStyle(
                          fontSize: AppFontSize.xs,
                          fontWeight: FontWeight.w700,
                          color: palette.onColor(palette.danger),
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
    );
  }

  /// 会「长」的进度条（今日学习任务进度）
  Widget _progress(AppPalette palette, double value) {
    return AnimatedProgressBar(
      value: value,
      color: palette.primary,
      trackColor: palette.surfaceSoft,
      height: AppSpacing.sm,
    );
  }

  // ---- 弹窗 ----

  /// 解锁新勋章的仪式感：压暗整屏，中间弹一张卡，点掉即收下
  Future<void> _celebrate(garden_models.Badge badge) async {
    final AppPalette palette = context.palette;
    await showFloatingDialog<void>(
      context: context,
      dismissible: false,
      child: Dialog(
        backgroundColor: palette.cardColor(hasBackground: false),
        shape: AppShape.dialog(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 解锁那一下：光环扩散 + 火花 + 勋章图标弹入
              SuccessBurst(
                size: AppSpacing.xl * 3,
                color: palette.warning,
                icon: _gardenIcon(badge.icon),
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
                child: AppFilledButton(
                  onPressed: () => Navigator.of(context).pop(),
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
  final Glyph icon;
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
      AppToast.show(
        context,
        '先写一个任务名吧',
        duration: const Duration(seconds: 2),
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
            AppFilledButton(onPressed: _submit, child: const Text('加一个')),
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

  /// 照片是不是硬门槛：赚钱类必须（含家长勾了「必须添加照片」的自定义任务），
  /// 消费 / 罚款写清原因即可。判定与网页版共用 core/task_rules.dart。
  bool get _needPhoto => taskRequiresPhoto(widget.task);

  Future<void> _pick(ImageSource source) async {
    try {
      final Uint8List? compressed =
          await pickCompressedImage(_picker, source: source);
      if (compressed == null) return;
      if (!mounted) return;
      setState(() {
        _photo = compressed;
        _photoUrl = null;
      });
    } on ImageUnreadableException {
      if (mounted) _toast('这张图读不出来，换一张试试');
    } catch (_) {
      if (mounted) _toast('照片选不了，换一张试试');
    }
  }

  /// 上传当前选中的照片，成功返回它的地址（没选照片则返回 null）。
  ///
  /// **只在提交那一刻调用**（对应 Web 版 `CheckInModal`）：选完图就上传的话，
  /// 用户选了又取消就会在图床上留下永远没人引用的孤儿图片 ——
  /// 那正是设置页里「打卡照片清理」要扫的东西。
  Future<String?> _uploadPhoto() async {
    final Uint8List? bytes = _photo;
    if (bytes == null) return null;
    setState(() => _uploading = true);
    try {
      final UploadResult result = await widget.upload.upload(bytes);
      if (!mounted) return null;
      setState(() => _photoUrl = result.url);
      return result.url;
    } catch (e) {
      if (mounted) _toast('照片没传上去：$e', error: true);
      return null;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    final String note = _note.text.trim();
    if (_isDeduct && note.isEmpty) {
      _toast('写一句原因，好让家长知道为什么扣分', warning: true);
      return;
    }
    if (_needPhoto && _photo == null) {
      _toast('这项任务要拍一张照片，或者从相册选一张，才能提交', warning: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      // 照片到这一步才上传（对应 Web 版 CheckInModal）：选了又取消不会在图床留孤儿图
      String? imageUrl = _photoUrl;
      if (_photo != null && imageUrl == null) {
        imageUrl = await _uploadPhoto();
        if (imageUrl == null) {
          // 失败的提示已经由 _uploadPhoto 报过，这里只把按钮解冻
          if (mounted) setState(() => _submitting = false);
          return;
        }
      }
      await widget.onSubmitted(
        widget.task,
        note: note.isEmpty ? null : note,
        imageUrl: imageUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // 记账可能已经成功了，只是审批那一步没走通（LedgerApprovalException）。
      // 这种情况也要把账本拉一次，否则孩子看不到自己刚交的申请，
      // 会以为没交上而重复提交（对应 Web 版 CheckInModal 的处理）。
      if (e is LedgerApprovalException) {
        unawaited(context.read<FamilyState>().loadLedger());
      }
      _toast(
        e is LedgerApprovalException ? LedgerApprovalException.message : '$e',
        error: true,
      );
    }
  }

  void _toast(String message, {bool error = false, bool warning = false}) {
    AppToast.show(
      context,
      message,
      tone: error
          ? AppToastTone.error
          : warning
              ? AppToastTone.warning
              : AppToastTone.neutral,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TaskConfig task = widget.task;
    final String unit = task.unit;
    // 摘要盒是一层「有色浅底」：底色和它上面的字色都由同一个值派生，才不会各算各的
    final Color summaryColor = _isDeduct ? palette.danger : palette.success;
    final Color summaryTint = Color.alphaBlend(
      summaryColor.withValues(alpha: 0.14),
      palette.cardColor(hasBackground: false),
    );

    // 内容直接铺在 SnapSheet 里（不要再套 Dialog）：底部圆角、拖拽把手、
    // 遮罩与关闭手势都由 showAppSheet 的 SnapSheetRoute 负责。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
              Text(
                '${widget.isParent ? '打卡' : '申请打卡'}：${task.name}',
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
                decoration: ShapeDecoration(
                  color: summaryTint,
                  shape: AppShape.all(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '本次${_isDeduct ? '扣' : '获得'} ${task.value.abs()} $unit',
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w700,
                        color: palette.onColor(summaryTint),
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                    if (task.description != null && task.description!.isNotEmpty) ...<Widget>[
                      _gapXs,
                      Text(
                        task.description!,
                        style: TextStyle(fontSize: AppFontSize.xs, color: _onAccentTintSoft(palette, summaryColor)),
                      ),
                    ],
                  ],
                ),
              ),
              _gapSm,
              Text(
                _needPhoto ? '照片（必填）' : '照片（可选）',
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  color: _needPhoto ? palette.danger : palette.textSecondary,
                ),
              ),
              _gapXs,
              Row(
                children: <Widget>[
                  AppOutlinedButton.icon(
                    onPressed: _submitting ? null : () => unawaited(_pick(ImageSource.camera)),
                    icon: const GlyphIcon(AppIcons.camera, size: AppFontSize.md),
                    label: const Text('拍照'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppOutlinedButton.icon(
                    onPressed: _submitting ? null : () => unawaited(_pick(ImageSource.gallery)),
                    icon: const GlyphIcon(AppIcons.photos, size: AppFontSize.md),
                    label: const Text('从相册选'),
                  ),
                ],
              ),
              // 必填照片还没选：把「为什么按钮点不动」写在这儿
              if (_needPhoto && _photo == null) ...<Widget>[
                _gapXs,
                Text(
                  '这项任务要拍一张照片，或者从相册选一张，才能提交',
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.danger),
                ),
              ],
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
                              child: AppLoading(size: 20),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppTextButton(
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
                  AppTextButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppFilledButton(
                    onPressed: _submitting || (_needPhoto && _photo == null)
                        ? null
                        : () => unawaited(_submit()),
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
        );
  }
}

/// 首屏骨架屏：形状贴着真实内容铺（顶部 hero + 中间几张卡 + 底部宫格），
/// 与加载完成后逐块浮入的 [EnterBox] 一脉相承（对应 `docs/motion-kit.md` 第五节）。
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md + AppTopBar.contentInset(context),
        AppSpacing.md,
        AppSpacing.xl + AppNavBar.contentInset(context),
      ),
      children: const <Widget>[
        // 顶部 hero：问候 + 日期 + 大数字 + 一行说明
        EnterBox(
          index: 0,
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonLine(widthFactor: 0.5, height: AppFontSize.lg),
                SizedBox(height: AppSpacing.sm),
                SkeletonLine(widthFactor: 0.26, height: AppFontSize.xs),
                SizedBox(height: AppSpacing.xl),
                SkeletonBox(width: AppSpacing.xl * 4, height: AppFontSize.xl),
                SizedBox(height: AppSpacing.sm),
                SkeletonLine(widthFactor: 0.78, height: AppFontSize.xs),
              ],
            ),
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        // 中间几张卡：图标 + 两行文字
        SkeletonList(
          count: 3,
          lines: 2,
          padding: EdgeInsets.only(top: AppSpacing.sm),
        ),
        SizedBox(height: AppSpacing.sm),
        // 底部宫格：四列入口
        Row(
          children: <Widget>[
            Expanded(child: SkeletonBox(height: AppSpacing.xl + AppSpacing.md)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonBox(height: AppSpacing.xl + AppSpacing.md)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonBox(height: AppSpacing.xl + AppSpacing.md)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonBox(height: AppSpacing.xl + AppSpacing.md)),
          ],
        ),
      ],
    );
  }
}

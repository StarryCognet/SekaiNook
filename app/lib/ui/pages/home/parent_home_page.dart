import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:sekainook_app/ui/widgets/app_toast.dart';
import 'package:sekainook_app/ui/widgets/app_loading.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../config/family_rules.dart';
import '../../../core/ledger_csv.dart';
import '../../../core/ledger_export.dart';
import '../../../core/time_text.dart';
import '../../../data/models/ledger_record.dart';
import '../../../data/models/task_config.dart';
import '../../../state/family_state.dart';
import '../../../state/garden_state.dart';
import '../../../state/notification_state.dart';
import '../../../state/settings_state.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';
import '../../shell/app_nav_bar.dart';
import '../../shell/app_top_bar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_widgets.dart';
import '../../widgets/state_views.dart';
import '../../widgets/motion/app_buttons.dart';

/// 趋势图天数（对应 Web 版 `BalanceTrend.tsx` 的 `TREND_DAYS`）
const int _trendDays = 14;

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
const Widget _rightIcon = Icon(Icons.chevron_right, size: AppFontSize.md);

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

/// 本地日历天键（对应 Web 版 `dayKey`）
String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

/// 实时时钟文案（HH:mm:ss）
String _clockText(DateTime now) =>
    '${now.hour.toString().padLeft(2, '0')}:'
    '${now.minute.toString().padLeft(2, '0')}:'
    '${now.second.toString().padLeft(2, '0')}';

/// 今天的流水（对应 Web 版 `todayRecords`，按设备本地日期比较）
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

/// 「14% 有色浅底」上该用的图标 / 文字色。
///
/// 图标盒那种底色是半透明的（`alphaBlend(色 14%, transparent)`），实际合成在卡片底上，
/// 所以这里拿卡片底当合成基色判断明暗 —— 深底配亮字、浅底配深字（见 [AppPalette.onColor]）。
/// 直接拿 `palette.primary` / `palette.success` 当图标色，在午夜蓝这类深色主题里会糊在底上。
Color _tintOn(AppPalette palette, Color color) => palette.onColor(
  Color.alphaBlend(color.withValues(alpha: 0.14), palette.cardColor(hasBackground: false)),
);

/// 账本分页在路由里的查询参数名。
///
/// 对应 Web 版 `goLedger(tab)` 的 `setViewState('family.activeTab', ...)` 搬到地址栏：
/// `/family?tab=<tasks|pending|history>`（缺省 `tasks`）。
const String _familyTabParam = 'tab';

/// 去账本的某一页：打卡任务（`tasks`）/ 待审批（`pending`）/ 历史记录（`history`）。
///
/// 对应 Web 版 `goLedger(tab)`：Web 内部第三个 Tab 叫 `records`，URL 契约里统一叫 `history`。
String _familyPath(String tab) => '/family?$_familyTabParam=$tab';

/// 金额文案（保留两位小数）
String _yuanText(double value) => value.toStringAsFixed(2);

/// 按天净额（对应 Web 版 `BalanceTrend.buildTrend`：**单柱按天净额**，不是收入/支出双柱）
List<int> _buildTrend(List<LedgerRecord> records, DateTime now) {
  final List<int> values = List<int>.filled(_trendDays, 0);
  for (final LedgerRecord record in records) {
    if (!record.isCredited) continue;
    final int days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(
          record.createdAt.year,
          record.createdAt.month,
          record.createdAt.day,
        ))
        .inDays;
    if (days < 0 || days >= _trendDays) continue;
    values[_trendDays - 1 - days] += record.amount;
  }
  return values;
}

/// 妈妈版首页：一眼看到「谁在等我批、家里还剩多少、这周怎么样」。
///
/// 对应 Web 版 `src/views/home/ParentHome.tsx`。数据来自 [FamilyState]（家庭账本）、
/// [GardenState]（花园阳光）、[NotificationState]（未读通知）与 [SettingsState]（称呼）。
class ParentHomePage extends StatefulWidget {
  const ParentHomePage({super.key});

  @override
  State<ParentHomePage> createState() => _ParentHomePageState();
}

class _ParentHomePageState extends State<ParentHomePage> with WidgetsBindingObserver {
  /// 顶部实时时钟：每秒刷新一次
  DateTime _now = DateTime.now();

  /// 拉取失败时页面要说话：不能把「没拉到」显示成「家里没钱了」
  bool _loadFailed = false;

  /// 正在处理的待审批 id（防连点）
  String? _busyId;

  /// 正在兑换（按钮置灰）
  bool _settling = false;

  Timer? _clock;
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refresh());
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    // 「有没有新申请」要跟上孩子的提交：20 秒问一次
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      // 后台不问（对应 Web 版轮询里的 document.hidden 判断），回前台时补一次
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 回到前台立刻补一次：后台期间跳过的轮询不用再等下一个 20 秒
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await context.read<FamilyState>().loadLedger();
      if (mounted) setState(() => _loadFailed = false);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      _refreshing = false;
    }
  }

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

  // ---- 动作 ----

  Future<void> _approve(LedgerRecord record) async {
    if (_busyId != null) return;
    setState(() => _busyId = record.id);
    try {
      await context.read<FamilyState>().approve(record.id);
      await _refresh();
      if (mounted) {
        // 通过那一下给一整页的「做成了」反馈（不挡点击，自己消失）
        showBurst(context);
        _toast('「${record.taskName}」已通过', success: true);
      }
    } catch (e) {
      if (mounted) _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(LedgerRecord record) async {
    if (_busyId != null) return;
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _RejectDialog(taskName: record.taskName),
    );
    if (reason == null || !mounted) return;
    setState(() => _busyId = record.id);
    try {
      await context.read<FamilyState>().reject(
            record.id,
            reason: reason.trim().isEmpty ? null : reason.trim(),
          );
      await _refresh();
      if (mounted) _toast('「${record.taskName}」已驳回', success: true);
    } catch (e) {
      if (mounted) _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// 积分兑换现金：记一条「现金兑现」支出并立即入账（家长自己记的账不用审批）
  Future<void> _settle() async {
    final FamilyState family = context.read<FamilyState>();
    final num balance = family.balance;
    if (balance <= 0 || _settling) return;

    final double yuan = FamilyRules.pointsToYuan(balance);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _ConfirmDialog(
        title: '兑换 $balance 积分 = ${_yuanText(yuan)} 元？',
        message: '会记一条「现金兑现」支出，积分全部扣掉；想只兑换一部分请去账本页',
        okText: '确认兑换',
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _settling = true);
    try {
      await family.api.addLedgerRecord(
        TaskConfig(
          id: 'payout',
          name: '现金兑现',
          type: TaskType.spending,
          value: -balance.round(),
        ),
        note: '积分兑换现金：$balance 积分 = ${_yuanText(yuan)} 元',
        autoApprove: true,
      );
      await _refresh();
      if (mounted) {
        // 到账那一下同样放一个光环
        showBurst(context);
        _toast('已兑换 ${_yuanText(yuan)} 元，扣掉 $balance 积分', success: true);
      }
    } on LedgerApprovalException {
      await _refresh();
      if (mounted) {
        _toast(
          '已记账，但审批没成功 —— $balance 积分还没扣掉，记录在待审批里，去点一下通过',
          warning: true,
        );
      }
    } catch (e) {
      if (mounted) _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _settling = false);
    }
  }

  /// 导出流水：把 CSV 落成真文件 —— 安卓/iOS 交给系统分享面板（用户自己挑存哪 / 发给谁），
  /// Web 触发浏览器下载。为什么不是直接写「下载」目录，见 `core/ledger_export_io.dart` 开头。
  ///
  /// 详细分流见 `core/ledger_export.dart`。这里只负责三件事：空账本别导、
  /// 成功说清文件在哪、失败如实报错（不静默吞）。
  Future<void> _export(List<LedgerRecord> records) async {
    if (records.isEmpty) {
      _toast('还没有流水可以导出');
      return;
    }
    try {
      final LedgerExportResult result = await saveLedgerCsv(buildLedgerCsv(records));
      if (mounted) {
        _toast(ledgerExportToastText(records.length, result), success: true);
      }
    } catch (e) {
      if (mounted) _toast('导出失败：$e', error: true);
    }
  }

  // ---- 页面骨架 ----

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final FamilyState family = context.watch<FamilyState>();
    final GardenState garden = context.watch<GardenState>();
    final NotificationState notices = context.watch<NotificationState>();
    final SettingsState settings = context.watch<SettingsState>();

    final String momName = settings.momName;
    final String kidName = settings.kidName;
    // 称呼还没到位时用骨架屏占住首屏（判定逻辑不变，只换「加载中」的样子）
    if (momName.isEmpty && kidName.isEmpty) {
      return const SafeArea(child: _HomeSkeleton());
    }

    final DateTime now = _now;
    final ({int income, int expense, int net, int count, int checkins}) week =
        _recentSummary(family.records, 7, now);
    final List<LedgerRecord> today = _todayRecords(family.records, now);

    // 首屏卡片按顺序错峰进场（对应 `docs/motion-kit.md` 第四节第 1 条）。
    // 带稳定 key：中途多出一张卡（比如来了新的待审批）时它单独淡入，
    // 已经在场的卡片不会重播。
    final List<({String key, Widget card})> cards = <({String key, Widget card})>[
      (key: 'hero', card: _hero(palette, now, momName, family)),
      (key: 'todo', card: _todoCard(palette, momName, kidName, family, notices.unreadCount)),
      if (family.pendingRecords.isNotEmpty) (key: 'pending', card: _pendingCard(palette, family)),
      (key: 'overview', card: _overviewCard(palette, week, family.records, now)),
      (key: 'today', card: _todayCard(palette, now, kidName, today)),
      (key: 'grid', card: _grid(palette, family, garden, notices.unreadCount)),
    ];
    // 顶上先插了一张「重试」卡时，后面的卡片整体顺延一位
    final int leadIndex = _loadFailed ? 1 : 0;

    return Scaffold(
      body: SafeArea(
        child: family.loading && family.records.isEmpty && !_loadFailed
            ? const _HomeSkeleton()
            : ListView(
                // 底部让出底栏胶囊（MainShell 开了 extendBody，它浮在内容之上）
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md + AppTopBar.contentInset(context),
                  AppSpacing.md,
                  AppSpacing.xl + AppNavBar.contentInset(context),
                ),
                children: <Widget>[
                  if (_loadFailed) ...<Widget>[
                    EnterBox(
                      index: 0,
                      child: AppCard(
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
                    ),
                    _gapSm,
                  ],
                  for (int i = 0; i < cards.length; i++) ...<Widget>[
                    if (i > 0) _gapSm,
                    EnterBox(
                      key: ValueKey<String>(cards[i].key),
                      index: i + leadIndex,
                      child: cards[i].card,
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  // ---- 1. 顶部（实时时钟 + 两个统计）----

  Widget _hero(AppPalette palette, DateTime now, String momName, FamilyState family) {
    return AppCard(
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
                    Text(
                      '${_greetingText(now)}，$momName',
                      style: TextStyle(
                        fontSize: AppFontSize.lg,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: ShapeDecoration(
                  color: palette.softColor(hasBackground: false),
                  shape: AppShape.all(AppRadius.md, side: BorderSide(color: palette.border)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.access_time, size: AppFontSize.sm, color: palette.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _clockText(now),
                      style: TextStyle(
                        fontSize: AppFontSize.lg,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _gapSm,
          Row(
            children: <Widget>[
              Expanded(
                child: PressInkWell(
                  onTap: () => context.go(_familyPath('pending')),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '待审批',
                          style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                        ),
                        _gapXs,
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            AnimatedCount(
                              value: family.pendingCount,
                              // 基线对齐的行里不要「脉冲」那层 Transform，
                              // 否则会和右边的「条」错开半行；滚动数字本身已经够看
                              pulse: false,
                              style: TextStyle(
                                fontSize: AppFontSize.xl,
                                fontWeight: FontWeight.w800,
                                color: family.pendingCount > 0 ? palette.warningInk : palette.text,
                                fontFeatures: kTabularNumbers,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '条',
                              style: TextStyle(
                                fontSize: AppFontSize.xs,
                                color: palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: AppSpacing.xl, color: palette.border),
              Expanded(
                child: PressInkWell(
                  onTap: () => context.go(_familyPath('history')),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm, top: AppSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '当前余额（元）',
                          style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                        ),
                        _gapXs,
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            AnimatedCount(
                              value: FamilyRules.pointsToYuan(family.balance),
                              formatter: (num value) => _yuanText(value.toDouble()),
                              pulse: false,
                              style: TextStyle(
                                fontSize: AppFontSize.xl,
                                fontWeight: FontWeight.w800,
                                color: palette.success,
                                fontFeatures: kTabularNumbers,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '元',
                              style: TextStyle(
                                fontSize: AppFontSize.xs,
                                color: palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 2. 需要我处理 ----

  Widget _todoCard(
    AppPalette palette,
    String momName,
    String kidName,
    FamilyState family,
    int unreadCount,
  ) {
    final List<Widget> todos = <Widget>[];
    if (family.pendingCount > 0) {
      final String hint = family.pendingRecords.isNotEmpty
          ? '最近：${family.pendingRecords.first.taskName}'
          : '点一下去处理';
      todos.add(_todoRow(
        palette,
        Icons.fact_check_outlined,
        '有 ${family.pendingCount} 条打卡等你审批',
        hint,
        onTap: () => context.go(_familyPath('pending')),
        trailing: const Text('去审批'),
      ));
    }
    if (family.balance > 0) {
      todos.add(_todoRow(
        palette,
        Icons.savings_outlined,
        '$kidName攒了 ${family.balance} 积分，可以兑换成钱了',
        '全部兑换可得 ${_yuanText(FamilyRules.pointsToYuan(family.balance))} 元'
        '（${FamilyRules.exchangeRateText}）',
        onTap: () => unawaited(_settle()),
        trailing: Text(_settling ? '处理中…' : '去兑换'),
      ));
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 「有活等着你」的呼吸信号：有待审批偏警示色，只有未读通知走主色
              if (family.pendingCount > 0 || unreadCount > 0) ...<Widget>[
                PulseDot(color: family.pendingCount > 0 ? palette.warning : palette.primary),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  '需要我处理',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              if (unreadCount > 0)
                AppTextButton(
                  onPressed: () => context.go('/home/notifications'),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.primary,
                    textStyle: const TextStyle(fontSize: AppFontSize.xs),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[Text('还有 $unreadCount 条新通知'), _rightIcon],
                  ),
                ),
            ],
          ),
          if (todos.isEmpty)
            Text(
              '都处理完了，今天很顺利 🎉',
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
            )
          else
            ...todos,
        ],
      ),
    );
  }

  Widget _todoRow(
    AppPalette palette,
    IconData icon,
    String text,
    String hint, {
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: PressInkWell(
        onTap: onTap,
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
                  color: Color.alphaBlend(
                    palette.primary.withValues(alpha: 0.14),
                    Colors.transparent,
                  ),
                  shape: AppShape.all(AppRadius.md),
                ),
                child: Icon(icon, size: AppFontSize.md, color: _tintOn(palette, palette.primary)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    Text(
                      hint,
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (trailing != null)
                DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                  child: trailing,
                ),
              Icon(Icons.chevron_right, size: AppFontSize.md, color: palette.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 3. 待审批流水（逐条通过 / 驳回）----

  Widget _pendingCard(AppPalette palette, FamilyState family) {
    final List<LedgerRecord> pending = family.pendingRecords;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '待审批',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                '共 ${pending.length} 条',
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: palette.textSecondary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '暂时没有待审批的打卡',
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
            )
          else
            for (final LedgerRecord record in pending) ...<Widget>[
              _pendingRow(palette, record),
              _gapXs,
            ],
        ],
      ),
    );
  }

  Widget _pendingRow(AppPalette palette, LedgerRecord record) {
    final bool busy = _busyId == record.id;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: ShapeDecoration(
        color: palette.softColor(hasBackground: false),
        shape: AppShape.all(AppRadius.md, side: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        record.taskName,
                        style: TextStyle(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                    ),
                    Text(
                      _signed(record.amount),
                      style: TextStyle(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w700,
                        color: record.amount >= 0 ? palette.success : palette.danger,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                  ],
                ),
                if (record.note != null && record.note!.isNotEmpty) ...<Widget>[
                  _gapXs,
                  Text(
                    record.note!,
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (busy)
            const SizedBox(
              width: AppFontSize.md,
              height: AppFontSize.md,
              child: AppLoading(size: 20),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppTextButton(
                  onPressed: () => unawaited(_reject(record)),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.danger,
                    textStyle: const TextStyle(fontSize: AppFontSize.sm),
                  ),
                  child: const Text('驳回'),
                ),
                AppFilledButton(
                  onPressed: () => unawaited(_approve(record)),
                  child: const Text('通过'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ---- 4. 最近 7 天概览 + 14 天趋势 ----

  Widget _overviewCard(
    AppPalette palette,
    ({int income, int expense, int net, int count, int checkins}) week,
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
                  '最近 7 天概览',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                '截至现在',
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
              ),
            ],
          ),
          _gapSm,
          Row(
            children: <Widget>[
              _statCell(
                palette,
                '收入',
                week.income,
                palette.successInk,
                formatter: (num value) => '+${value.round()}',
              ),
              // 这几格是「中性卡片底上的彩色数字」：得用 ink 家族（保住涨红跌绿的含义，
              // 同时压到 4.5:1）。直接拿 warning #F5A623 当字色在白卡上只有 1.7:1。
              _statCell(palette, '支出', week.expense, palette.dangerInk),
              _statCell(palette, '净额', week.net, palette.primaryInk),
              _statCell(palette, '打卡次数', week.checkins, palette.warningInk),
            ],
          ),
          _gapMd,
          Text(
            '近 14 天积分趋势',
            style: TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
          _gapSm,
          _BalanceTrend(records: records, now: now),
        ],
      ),
    );
  }

  Widget _statCell(
    AppPalette palette,
    String label,
    num value,
    Color color, {
    String Function(num value)? formatter,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
          ),
          _gapXs,
          AnimatedCount(
            value: value,
            formatter: formatter,
            style: TextStyle(
              fontSize: AppFontSize.md,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: kTabularNumbers,
            ),
          ),
        ],
      ),
    );
  }

  // ---- 5. 孩子今天 ----

  Widget _todayCard(AppPalette palette, DateTime now, String kidName, List<LedgerRecord> today) {
    final List<LedgerRecord> head = today.take(5).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$kidName今天',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              if (today.length > 5)
                AppTextButton(
                  onPressed: () => context.go(_familyPath('history')),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.primary,
                    textStyle: const TextStyle(fontSize: AppFontSize.xs),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('先看这 5 条，还有 ${today.length - 5} 条'),
                      _rightIcon,
                    ],
                  ),
                )
              else
                Text(
                  '${today.length} 条',
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: palette.textSecondary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
            ],
          ),
          if (today.isEmpty)
            Text(
              '今天还没有新记录',
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
            )
          else
            for (final LedgerRecord record in head)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            record.taskName,
                            style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                          ),
                          Text(
                            '${relativeDayTime(record.createdAt, now: now)}${_statusSuffix(record)}',
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
                      _signed(record.amount),
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w700,
                        color: record.amount >= 0 ? palette.success : palette.danger,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                  ],
                ),
              ),
          Align(
            alignment: Alignment.centerRight,
            child: AppTextButton(
              onPressed: () => context.go(_familyPath('history')),
              style: TextButton.styleFrom(foregroundColor: palette.primary),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[Text('看全部流水'), _rightIcon],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusSuffix(LedgerRecord record) {
    if (record.isPending) return ' · 待审批';
    if (record.isRejected) return ' · 已驳回';
    return '';
  }

  // ---- 6. 宫格入口 ----

  Widget _grid(
    AppPalette palette,
    FamilyState family,
    GardenState garden,
    int unreadCount,
  ) {
    final List<_GridEntry> entries = <_GridEntry>[
      _GridEntry(
        '去审批',
        Icons.fact_check_outlined,
        () => context.go(_familyPath('pending')),
        badge: family.pendingCount,
      ),
      _GridEntry(
        '家庭账本',
        Icons.account_balance_wallet_outlined,
        () => context.go(_familyPath('history')),
      ),
      _GridEntry('学习计划', Icons.calendar_today_outlined, () => context.go('/family/plan')),
      _GridEntry('阳光花园', Icons.wb_sunny_outlined, () => context.go('/garden')),
      _GridEntry(
        '通知',
        Icons.notifications_outlined,
        () => context.go('/home/notifications'),
        badge: unreadCount,
      ),
      _GridEntry('导出流水', Icons.file_download_outlined, () => _export(family.records)),
      _GridEntry('设置', Icons.settings_outlined, () => context.go('/settings')),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = (constraints.maxWidth - AppSpacing.sm * 3) / 4;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final _GridEntry entry in entries)
                    SizedBox(
                      width: width,
                      child: _gridTile(palette, entry),
                    ),
                ],
              );
            },
          ),
          _gapSm,
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: ShapeDecoration(
              color: palette.softColor(hasBackground: false),
              shape: AppShape.all(AppRadius.md, side: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: AppSpacing.xl,
                  height: AppSpacing.xl,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: Color.alphaBlend(
                      palette.success.withValues(alpha: 0.14),
                      Colors.transparent,
                    ),
                    shape: AppShape.all(AppRadius.full),
                  ),
                  child: Icon(
                    Icons.savings_outlined,
                    size: AppFontSize.md,
                    color: _tintOn(palette, palette.success),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '积分兑换',
                        style: TextStyle(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                      Text(
                        family.balance > 0
                            ? '${family.balance} 积分 = '
                                '${_yuanText(FamilyRules.pointsToYuan(family.balance))} 元'
                            : '现在还没有可兑换的积分',
                        style: TextStyle(
                          fontSize: AppFontSize.xs,
                          color: palette.textTertiary,
                          fontFeatures: kTabularNumbers,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppFilledButton(
                  onPressed: family.balance > 0 && !_settling
                      ? () => unawaited(_settle())
                      : null,
                  child: const Text('兑换'),
                ),
              ],
            ),
          ),
          _gapXs,
          Text(
            '花园阳光 ${family.sunBalance}',
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: palette.textTertiary,
              fontFeatures: kTabularNumbers,
            ),
          ),
        ],
      ),
    );
  }

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
                    color: palette.softColor(hasBackground: false),
                    shape: AppShape.all(AppRadius.md, side: BorderSide(color: palette.border)),
                  ),
                  child: Icon(entry.icon, size: AppFontSize.md, color: palette.primary),
                ),
                if (entry.badge > 0)
                  Positioned(
                    right: -AppSpacing.xs,
                    top: -AppSpacing.xs,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
}

/// 宫格入口的一条
class _GridEntry {
  const _GridEntry(this.label, this.icon, this.onTap, {this.badge = 0});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
}

/// 近 14 天积分趋势（对应 Web 版 `components/BalanceTrend.tsx`）。
///
/// 口径：**按天净额单柱**（当天所有已入账流水求和），正数用 success、负数用 danger，
/// 不是「收入 / 支出双柱」。
class _BalanceTrend extends StatelessWidget {
  const _BalanceTrend({required this.records, required this.now});

  final List<LedgerRecord> records;
  final DateTime now;

  static const double _chartHeight = AppSpacing.xl * 8;

  String _label(int index) {
    final DateTime day = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _trendDays - 1 - index));
    return '${day.month}/${day.day}';
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final List<int> values = _buildTrend(records, now);
    final bool hasData = values.any((int value) => value != 0);
    if (!hasData) {
      return SizedBox(
        height: _chartHeight,
        child: const EmptyView(
          message: '最近 14 天还没有积分记录',
          icon: Icons.show_chart,
        ),
      );
    }

    return SizedBox(
      height: _chartHeight,
      child: BarChart(
        // fl_chart 自带的 swap 动画：数据一变就重新「长」一次柱子
        duration: AppMotion.slower,
        curve: AppMotion.emphasized,
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _maxY(values),
          minY: _minY(values),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (BarChartGroupData group) => palette.text.withValues(alpha: 0.85),
              getTooltipItem: (
                BarChartGroupData group,
                int groupIndex,
                BarChartRodData rod,
                int rodIndex,
              ) =>
                  BarTooltipItem(
                '${_label(group.x)}  ${_signed(rod.toY.round())}',
                TextStyle(
                  color: palette.onColor(palette.text),
                  fontSize: AppFontSize.xs,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                // 14 根柱子全画标签会糊成一片：每 3 天留一个（0/3/6/9/12 共 5 个），
                // 写法与 `family_dashboard_page.dart` 里的同类图一致。
                reservedSize: AppSpacing.lg,
                interval: 1,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.round();
                  if (index < 0 || index >= _trendDays) return const SizedBox.shrink();
                  if (index % 3 != 0) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      _label(index),
                      style: TextStyle(
                        fontSize: AppFontSize.xs,
                        color: palette.textSecondary,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(
            show: true,
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          barGroups: <BarChartGroupData>[
            for (int index = 0; index < values.length; index++)
              BarChartGroupData(
                x: index,
                barRods: <BarChartRodData>[
                  BarChartRodData(
                    toY: values[index].toDouble(),
                    color: values[index] >= 0 ? palette.success : palette.danger,
                    width: AppSpacing.sm + AppSpacing.xs,
                    borderRadius: values[index] >= 0
                        ? const BorderRadius.vertical(top: Radius.circular(AppRadius.sm))
                        : const BorderRadius.vertical(bottom: Radius.circular(AppRadius.sm)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  double _maxY(List<int> values) {
    final int top = values.fold<int>(0, (int max, int value) => value > max ? value : max);
    return top <= 0 ? 1 : top.toDouble();
  }

  double _minY(List<int> values) {
    final int bottom = values.fold<int>(0, (int min, int value) => value < min ? value : min);
    return bottom >= 0 ? 0 : bottom.toDouble();
  }
}

/// 驳回理由输入（对应 Web 版驳回时那句「跟女儿说一句」）
class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.taskName});

  final String taskName;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AlertDialog(
      backgroundColor: palette.cardColor(hasBackground: false),
      title: Text(
        '驳回「${widget.taskName}」',
        style: TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: _reason,
        maxLines: 3,
        maxLength: 100,
        style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          hintText: '写一句给女儿的话（可选）',
          hintStyle: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: palette.border),
          ),
        ),
      ),
      actions: <Widget>[
        AppTextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
          child: const Text('取消'),
        ),
        AppFilledButton(
          onPressed: () => Navigator.of(context).pop(_reason.text),
          child: const Text('确认驳回'),
        ),
      ],
    );
  }
}

/// 二次确认（积分兑换现金）
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.okText,
  });

  final String title;
  final String message;
  final String okText;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AlertDialog(
      backgroundColor: palette.cardColor(hasBackground: false),
      title: Text(
        title,
        style: TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w700),
      ),
      content: Text(
        message,
        style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
      ),
      actions: <Widget>[
        AppTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
          child: const Text('取消'),
        ),
        AppFilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(okText),
        ),
      ],
    );
  }
}

/// 首屏骨架屏：形状贴着真实内容铺（顶部 hero 卡 + 下面几张卡片），
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
        // 顶部那张：问候 + 日期 + 左右两格统计
        EnterBox(
          index: 0,
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonLine(widthFactor: 0.44, height: AppFontSize.lg),
                SizedBox(height: AppSpacing.sm),
                SkeletonLine(widthFactor: 0.28, height: AppFontSize.xs),
                SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(child: SkeletonBox(height: AppFontSize.xl)),
                    SizedBox(width: AppSpacing.md),
                    Expanded(child: SkeletonBox(height: AppFontSize.xl)),
                  ],
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        // 下面几张：图标 + 两行文字的卡片
        SkeletonList(
          count: 3,
          lines: 2,
          padding: EdgeInsets.only(top: AppSpacing.sm),
        ),
      ],
    );
  }
}

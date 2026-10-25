import 'package:sekainook_app/fl_ui/dialog.dart';
import 'package:sekainook_app/fl_ui/null_status.dart';
import 'package:sekainook_app/ui/icons/icons.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sekainook_app/ui/widgets/app_toast.dart';
import 'package:sekainook_app/ui/widgets/app_loading.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../config/family_rules.dart';
import '../../../core/api_client.dart';
import '../../../core/api_exception.dart';
import '../../../core/image_compress.dart';
import '../../../core/ledger_csv.dart';
import '../../../core/ledger_export.dart';
import '../../../core/task_rules.dart';
import '../../../data/api/upload_api.dart';
import '../../../data/models/custom_task.dart';
import '../../../data/models/ledger_record.dart';
import '../../../data/models/task_config.dart';
import '../../../state/custom_tasks_state.dart';
import '../../../state/family_state.dart';
import '../../../state/theme_state.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';
import '../../shell/app_nav_bar.dart';
import '../../shell/app_top_bar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/motion_widgets.dart';
import '../../widgets/state_views.dart';
import '../../widgets/task_row.dart';
import '../../widgets/motion/app_buttons.dart';

/// 历史记录每页条数（手机端长列表一次性渲染会卡，改为「加载更多」分页）
const int _recordsPageSize = 20;

/// 历史记录状态筛选值：全部 / 待审批 / 已入账 / 已驳回
enum _RecordFilter {
  all('all', '全部'),
  pending('pending', '待审批'),
  approved('approved', '已入账'),
  rejected('rejected', '已驳回');

  const _RecordFilter(this.wire, this.label);

  final String wire;
  final String label;
}

/// 任务区里一行要渲染的全部信息。
///
/// 内置任务与自定义任务在「做完没有 / 能不能点」上口径不同（自定义任务走
/// `isRecordedToday`，内置任务走 `isTaskDone`），先在这里归一，
/// 渲染时按「能做 / 没到时间 / 已做满」三分区排，就不用再逐行分支。
class _TaskEntry {
  const _TaskEntry({
    required this.config,
    required this.custom,
    required this.done,
    required this.windowOpen,
    required this.submitting,
  });

  /// 交给 `_startCheckIn` 的任务；自定义任务是它的 `user_task_exec` 版本
  final TaskConfig config;

  /// 自定义任务本体；内置任务为 null
  final CustomTask? custom;

  /// 今天已经做满（含待审批：孩子提交了家长还没批，也算用掉机会）
  final bool done;

  /// 时间窗开着（没有时间窗的任务恒为 true）
  final bool windowOpen;

  /// 这一条正在提交
  final bool submitting;
}

/// 核心仪表盘：积分银行 + 任务区 / 待审批区 / 历史记录区
/// （对应 Web 版 `src/views/family/FamilyDashboard.tsx`）。
class FamilyDashboardPage extends StatefulWidget {
  const FamilyDashboardPage({super.key});

  @override
  State<FamilyDashboardPage> createState() => _FamilyDashboardPageState();
}

class _FamilyDashboardPageState extends State<FamilyDashboardPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ---- 账本状态 ----
  String? _error;

  /// 错误页上有人点了重试：给一个「正在重试」的反馈
  bool _retrying = false;

  /// 日结算：并发保护（结算会写流水，不能重入）
  bool _settling = false;

  /// 每秒钟刷新一次「现在」，用于作息判断（22:00 之后提示罚款）
  late DateTime _now;

  // ---- 驳回弹窗 ----
  bool _rejecting = false;

  // ---- 审批 ----
  bool _approvingAll = false;

  /// 正在审批的记录 id（按条加 loading，防止连点重复提交）
  final Set<String> _approvingIds = <String>{};

  // ---- 打卡弹窗 ----
  /// 正在提交的任务 id（防止手机连点重复入账）
  String? _submittingId;

  /// 历史记录状态筛选 + 已渲染条数（分页）
  _RecordFilter _recordFilter = _RecordFilter.all;
  int _visibleCount = _recordsPageSize;

  /// 任务区的类型切换：赚钱任务 / 消费·罚款。
  ///
  /// 只留一组在屏幕上：一屏 12 条按节奏分完区之后本来就要滚，再把两组叠一起
  /// 等于让「现在能做什么」重新变模糊。
  TaskType _taskFilter = TaskType.earning;

  /// 任务区「今天已经做满」是否展开 —— 默认收起，列表才短
  bool _completedExpanded = false;

  /// 「特殊加分」（参赛 / 获奖 / 奖状）是否展开 —— 一周才一两次，默认收起不占首屏
  bool _specialExpanded = false;

  /// 家长端「自定义任务」管理区是否展开（默认收起，避免常驻表单压住任务列表）
  bool _customManagerExpanded = false;

  Timer? _clockTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    // 预置的两条学习任务（十个英语单词 / 两首古诗）默认出现在任务列表里。
    // ensurePresets 幂等：重复调用不产生重复项，也不会覆盖家长改过 / 删过的任务。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CustomTasksState>().ensurePresets();
      void reload() => unawaited(_reloadLedger());
      reload();
    });
    // 秒级跳动交给卡片里的 _LiveClock 自己重建；这里只在跨分钟/跨天时
    // 整页 setState（任务窗口、签到判定都只到分钟粒度）。
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.minute != _now.minute ||
          now.hour != _now.hour ||
          now.day != _now.day) {
        setState(() => _now = now);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 回到前台立刻补一次：后台期间跳过的轮询不用再等下一个周期
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _pollOnce();
  }

  bool get _isParent => context.read<FamilyState>().role == FamilyRole.parent;

  /// 地址栏口径（`tasks` / `pending` / `history`）→ 页面内分区键（`tasks` / `pending` / `records`）。
  ///
  /// 「待审批」只对家长存在，孩子端若停在那一页要回落到任务区 —— 与 Web 版一致：
  /// 只回落**显示**，不改地址栏（免得把用户手输的链接改掉）。
  static String _areaFor(String tab, {required bool isParent}) {
    if (!isParent && tab == 'pending') return 'tasks';
    return tab == 'history' ? 'records' : tab;
  }

  /// 分区键 → 地址栏口径（反向映射，用于切换时导航）
  static String _tabParamFor(String area) => area == 'records' ? 'history' : area;

  /// 轮询：家长 10s 刷待审批（角标实时性），孩子 15s 刷流水（感知审批结果）。
  /// 身份切换时按新间隔重建 —— 与 Web 版两个 useEffect 的分工一致。
  void _ensurePolling(bool isParent) {
    final want = isParent ? const Duration(seconds: 10) : const Duration(seconds: 15);
    if (_pollInterval == want && (_pollTimer?.isActive ?? false)) return;
    _pollTimer?.cancel();
    _pollInterval = want;
    _pollTimer = Timer.periodic(want, (_) {
      if (!mounted) return;
      // 后台不问（对应 Web 版轮询里的 document.hidden 判断），回前台时补一次
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      _pollOnce();
    });
  }

  /// 一次轮询：家长只刷待审批，孩子刷整本流水（与 Web 版两个 useEffect 一致）
  void _pollOnce() {
    if (!mounted) return;
    if (_isParent) {
      unawaited(context.read<FamilyState>().refreshPending().catchError((Object _) {}));
    } else {
      unawaited(context.read<FamilyState>().loadLedger().catchError((Object _) {}));
    }
  }

  Duration? _pollInterval;

  /// 拉账本：**成功才清掉 error** —— 否则点「重试」就算成功也会一直停在错误页。
  /// 重试期间用 [_retrying] 给出反馈。
  Future<void> _reloadLedger() async {
    final state = context.read<FamilyState>();
    setState(() => _retrying = true);
    try {
      await state.loadLedger();
      if (!mounted) return;
      setState(() => _error = null);
      // 日结算（开户礼金 / 那天完成的任务不够 5 个 / 到 22:00 没打卡睡觉）：
      // 正确性由服务端幂等 id 保证，本地按「被结算的那一天」节流，纯粹为了省流量。
      await _settleOnce();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.message : '加载失败');
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _settleOnce() async {
    if (_settling) return;
    final state = context.read<FamilyState>();
    _settling = true;
    try {
      final settled = await state.settleLedgerOncePerDay(now: _now);
      if (settled != null && settled.applied.isNotEmpty) {
        await state.loadLedger().catchError((Object _) {});
        if (!mounted) return;
        _toast(
          '账本更新：${describeSettleApplied(settled.applied)}',
          warning: true,
        );
      }
    } catch (_) {
      // 结算失败不挡页面：下次进页面再来
    } finally {
      _settling = false;
    }
  }

  // ---- 提示 ----

  void _toast(String text, {bool warning = false}) {
    if (!mounted) return;
    AppToast.show(
      context,
      text,
      tone: warning ? AppToastTone.warning : AppToastTone.neutral,
    );
  }

  /// 成功那一下的整页反馈：光环 + 对勾，不挡点击、播完自动消失。
  ///
  /// 包一层 mounted 判断，异步回调里就不用直接碰 context。
  /// **只在真正成功时调**（打卡入账、审批通过、兑换到账）。
  void _burst() {
    if (!mounted) return;
    showBurst(context);
  }

  /// 打卡成功提示：5 秒内可撤销（手机误触兜底）
  void _notifySuccess(TaskConfig task, String recordId, bool isParent) {
    final sign = task.value > 0 ? '+' : '';
    final text = isParent
        ? '$sign${task.value} 积分！${task.name}'
        : '已提交「${task.name}」，等家长审批';
    if (!mounted) return;
    AppToast.show(
      context,
      text,
      actionLabel: '撤销',
      onAction: () => unawaited(_undo(recordId)),
    );
  }

  /// 撤销刚才的打卡
  Future<void> _undo(String recordId) async {
    try {
      await context.read<FamilyState>().removeRecord(recordId);
      _toast('已撤销刚才的打卡');
    } catch (_) {
      _toast('撤销失败，请到「历史记录」里删除', warning: true);
    }
  }

  /// 记账失败的处理：账已经记上了、只是自动审批那一步没成功 ——
  /// 这笔钱并没有入账，记录正以 pending 躺在待审批里，必须让家长看见。
  Future<void> _handleWriteError(Object e, String fallback) async {
    if (e is LedgerApprovalException) {
      await context.read<FamilyState>().loadLedger().catchError((Object _) {});
      _toast(LedgerApprovalException.message, warning: true);
      return;
    }
    _toast(e is ApiException ? e.message : fallback, warning: true);
  }

  // ---- 打卡 ----

  String? _checkTask(TaskConfig task, List<LedgerRecord> records) =>
      checkTask(task, records, now: _now);

  /// 今日各任务提交次数缓存：任务区要逐个任务判断「还能不能做」，
  /// 逐个扫全量账本是 O(任务数 × 流水数)，页面一重建就白跑一遍。
  /// 账本实例没变（P1 之后内容不变会复用同一个 List）且还是同一天时直接查表。
  List<LedgerRecord>? _todayCountsFrom;
  String? _todayCountsDay;
  Map<String, int> _todayCounts = const <String, int>{};

  Map<String, int> _todayCountsFor(List<LedgerRecord> records) {
    final String day = '${_now.year}-${_now.month}-${_now.day}';
    if (identical(records, _todayCountsFrom) && day == _todayCountsDay) {
      return _todayCounts;
    }
    final counts = countTodaySubmissionsByTask(records, now: _now);
    _todayCountsFrom = records;
    _todayCountsDay = day;
    _todayCounts = counts;
    return counts;
  }

  bool _isDone(TaskConfig task, List<LedgerRecord> records) {
    final limit = task.dailyLimit;
    if (limit == null) return false;
    if (task.id.isEmpty) return false;
    return (_todayCountsFor(records)[task.id] ?? 0) >= limit;
  }

  /// 自定义任务在服务端要有对应的「执行 id」：预置两条各走自己的 id
  /// （日限 1、即时到账），其余全部写 `user_task_exec`，服务端按任务名判重。
  TaskConfig _toExecTask(CustomTask task) => TaskConfig(
        id: task.kind == CustomTaskKind.preset
            ? task.id
            : CustomTasksState.userTaskExecId,
        name: task.name,
        type: task.type,
        value: task.value,
      );

  /// 打卡入口：先过本地规则闸门（不通过就提示，不开弹窗），再开弹窗收集照片 / 备注。
  ///
  /// 内置任务与自定义任务共用同一个弹窗 —— 自定义任务不再「点一下就立刻加积分」。
  Future<void> _startCheckIn(
    TaskConfig task, {
    CustomTask? custom,
    required List<LedgerRecord> records,
  }) async {
    final blocked = _checkTask(task, records);
    if (blocked != null) {
      _toast(blocked, warning: true);
      return;
    }
    if (_submittingId != null) return; // 提交中忽略重复点击
    final result = await _showCheckInDialog(task);
    if (!mounted || result == null) return;
    await _handleTask(
      task,
      note: result.note,
      imageUrl: result.imageUrl,
      custom: custom,
    );
  }

  /// 打卡：写入流水（小孩端为待审批申请）并刷新余额
  Future<void> _handleTask(
    TaskConfig task, {
    String? note,
    String? imageUrl,
    CustomTask? custom,
  }) async {
    if (_submittingId != null) return; // 提交中忽略重复点击
    final isParent = _isParent;
    final state = context.read<FamilyState>();
    final customTasks = context.read<CustomTasksState>();
    setState(() => _submittingId = task.id);
    try {
      final recordId = await state.api.addLedgerRecord(
            task,
            note: note,
            imageUrl: imageUrl,
            // 家长自己记的账让服务端立刻入账，女儿提交的一律进待审批
            autoApprove: isParent,
          );
      await state.loadLedger();
      if (!mounted) return;
      // 从自定义任务按钮进来的：把那条标成「今天做过」，按钮立刻置灰
      // （服务端还会再判一次重）
      if (custom != null) {
        customTasks.markDone(custom.id);
      }
      _notifySuccess(task, recordId, isParent);
      _burst();
    } catch (e) {
      await _handleWriteError(e, '操作失败，请重试');
    } finally {
      if (mounted) setState(() => _submittingId = null);
    }
  }

  // ---- 自定义任务 ----

  /// 添加自定义任务。`requirePhoto` 来自表单里的「必须添加照片」开关
  /// （默认开）—— 消费 / 罚款类不渲染那个开关，这里传 false 进来即可。
  Future<void> _addCustomTask(
    TaskType type,
    int value,
    String name,
    bool requirePhoto,
  ) async {
    final created = context.read<CustomTasksState>().addTask(
          CustomTaskInput(
            name: name,
            value: value,
            type: type,
            createdBy: TaskCreator.parent,
            requirePhoto: requirePhoto,
          ),
        );
    _toast(
      type == TaskType.earning && requirePhoto
          ? '「${created.name}」已加进快捷任务，提交时要拍照'
          : '「${created.name}」已加进快捷任务，点一下就能打卡',
    );
  }

  // ---- 审批 ----

  /// 审批通过：按条记 loading，连点不会重复提交（审批写操作不可重入）
  Future<void> _approve(String id) async {
    if (_approvingIds.contains(id)) return;
    setState(() => _approvingIds.add(id));
    try {
      await context.read<FamilyState>().approve(id);
      _toast('已审批通过，积分已入账');
      _burst();
    } catch (_) {
      _toast('操作失败，请重试', warning: true);
    } finally {
      if (mounted) setState(() => _approvingIds.remove(id));
    }
  }

  /// 批量通过：一次把待审批全部入账（孩子一口气交好几条时最省事）
  Future<void> _approveAll(List<LedgerRecord> pending) async {
    setState(() => _approvingAll = true);
    try {
      await context.read<FamilyState>().approveMany(
            pending.map((record) => record.id).toList(growable: false),
          );
      _toast('已通过 ${pending.length} 条');
      _burst();
    } catch (e) {
      _toast(e is StateError ? e.message : '操作失败，请重试', warning: true);
    } finally {
      if (mounted) setState(() => _approvingAll = false);
    }
  }

  /// 审批驳回：先让家长写一句原因，这句话会进女儿的通知
  Future<void> _confirmReject(LedgerRecord target, String reason) async {
    setState(() => _rejecting = true);
    try {
      await context
          .read<FamilyState>()
          .reject(target.id, reason: reason.isEmpty ? null : reason);
      _toast('已驳回，孩子会看到你的话');
    } catch (_) {
      _toast('操作失败，请重试', warning: true);
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  /// 驳回后重新提交（孩子对自己申请的补救动作）
  Future<void> _resubmit(String id) async {
    try {
      await context.read<FamilyState>().resubmit(id);
      _toast('已重新提交，等待家长审批');
    } catch (_) {
      _toast('操作失败，请重试', warning: true);
    }
  }

  /// 小孩撤回自己还没被审批的申请（删掉记录，不再占用今日次数）
  Future<void> _withdraw(String id) async {
    try {
      await context.read<FamilyState>().removeRecord(id);
      _toast('已撤回该申请');
    } catch (_) {
      _toast('撤回失败，请重试', warning: true);
    }
  }

  /// 删除流水（仅家长），含图片时后端会一并删除 R2 中的图片
  Future<void> _delete(String id) async {
    try {
      await context.read<FamilyState>().removeRecord(id);
      _toast('已删除该记录');
    } catch (_) {
      _toast('删除失败，请重试', warning: true);
    }
  }

  // ---- 导出 CSV ----

  /// 导出 CSV（仅家长）：按当前筛选导出全部记录。
  ///
  /// 落成真文件（安卓/iOS 走系统分享面板，Web 触发浏览器下载），
  /// 详细分流见 `core/ledger_export.dart`。
  Future<void> _exportCsv(List<LedgerRecord> records) async {
    if (records.isEmpty) return;
    try {
      final LedgerExportResult result = await saveLedgerCsv(buildLedgerCsv(records));
      if (!mounted) return;
      _toast(ledgerExportToastText(records.length, result));
    } catch (e) {
      if (!mounted) return;
      _toast('导出失败：$e', warning: true);
    }
  }

  // ---- 展示辅助 ----

  /// 格式化流水时间：今天显示「今天 HH:mm」，更早显示「M/d HH:mm」
  String _formatTime(DateTime date) {
    final local = date.toLocal();
    final now = _now;
    final sameDay =
        local.year == now.year && local.month == now.month && local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return sameDay ? '今天 $hh:$mm' : '${local.month}/${local.day} $hh:$mm';
  }

  @override
  // 主页四个 tab 里只有这一页没有自己的 Scaffold —— 顶部要留出状态栏，否则第一张卡被系统栏压住
  Widget build(BuildContext context) => SafeArea(child: _buildBody(context));

  Widget _buildBody(BuildContext context) {
    final state = context.watch<FamilyState>();
    final isParent = state.role == FamilyRole.parent;
    // 分区状态的唯一真相：地址栏 `/family?tab=tasks|pending|history`（缺省 tasks）。
    // 非法的值（手输 / 旧链接）一律回落到任务区。
    final String rawTab = GoRouterState.of(context).uri.queryParameters['tab'] ?? '';
    final String tab =
        const <String>{'tasks', 'pending', 'history'}.contains(rawTab) ? rawTab : 'tasks';
    final String area = _areaFor(tab, isParent: isParent);
    _ensurePolling(isParent);

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ErrorView(message: _error!, onRetry: () => unawaited(_reloadLedger())),
            if (_retrying) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              const LoadingView(message: '正在重试…'),
            ],
          ],
        ),
      );
    }

    // 首屏加载改骨架屏（加载 / 失败 / 空的判定逻辑不变，只换「加载中」的视觉）：
    // 按账本页的形状铺 —— 余额大卡 + 今日卡 + 一张流水列表卡
    if (state.loading && state.records.isEmpty) {
      return const _LedgerSkeleton();
    }

    return RefreshIndicator(
      onRefresh: _reloadLedger,
      // 卡片顺序可拖：平时是普通 ListView，编辑态换成 ReorderableListView
      // （顺序存本机偏好，孩子和家长各拖各的）
      child: _buildCardList(state, isParent, area),
    );
  }

  // ---- ① 余额大卡片 ----



  /// 页面主体：任务（默认）/ 待审批 / 历史记录。
  ///
  /// 2.9.4 起这里不再有「余额 / 趋势」卡片 —— 钱的部分全部搬到首页，
  /// 任务页只留「今天要干的活」：顶部一条必须任务细条 + 任务列表，
  /// 第一个任务行从 456dp 提到 ~200dp，打开 App 抬手就能点。
  Widget _buildCardList(FamilyState state, bool isParent, String area) {
    final EdgeInsets padding = EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md + AppTopBar.contentInset(context),
      AppSpacing.md,
      AppSpacing.xl + AppNavBar.contentInset(context),
    );
    final Widget body = switch (area) {
      'pending' => _buildLedgerSubPage(
          title: '待审批',
          count: state.pendingCount,
          child: _buildPendingArea(state),
        ),
      'records' => _buildLedgerSubPage(
          title: '历史记录',
          child: _buildRecordsArea(state, isParent),
        ),
      _ => _buildTasksArea(state, isParent),
    };
    return ListView(
      padding: padding,
      children: <Widget>[body],
    );
  }

  /// 「待审批 / 历史记录」现在是独立页（入口在任务页细条右侧那两颗图标），
  /// 顶部给一条返回，避免进来之后找不到回头路。
  Widget _buildLedgerSubPage({
    required String title,
    required Widget child,
    int count = 0,
  }) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PressInkWell(
          onTap: () => context.go('/family'),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                GlyphIcon(AppIcons.chevronBack, size: 18, color: palette.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                if (count > 0) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '$count',
                    style: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
                  ),
                ],
                const Spacer(),
                Text(
                  '返回任务',
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }


  // ---- ④ 分页：任务区 / 待审批 / 历史记录 ----

  /// 跳到「待审批 / 历史记录」子页（入口在任务页细条右侧的两颗图标）。
  ///
  /// `context.go` 是 replace 语义，不堆历史；页面内容由 URL 派生，不再 setState。
  void _goTab(String area) => context.go('/family?tab=${_tabParamFor(area)}');

  // ---- ④-0 必须任务细条（任务页顶部，约 28dp）----

  /// 任务页顶部那条细条：必须任务进度 + 倒计时 + 待审批/历史两个入口。
  ///
  /// 原「状态条」200dp 里每天真正要看的只有这一行 —— 积分和兑换搬去首页后，
  /// 这里只剩「今天还剩几件必须任务」和「没做要扣多少」。
  Widget _mustStrip({
    required TaskProgress progress,
    required int pendingCount,
  }) {
    final palette = context.palette;
    final int total = progress.total;
    final int done = progress.done;
    final bool allDone = total > 0 && done >= total;
    final Color accent = allDone ? palette.success : palette.danger;
    final String hint = allDone ? '今天必须的都做完了' : _mustCountdownHint();
    return Row(
      children: <Widget>[
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            value: total == 0 ? 0 : (done / total).clamp(0.0, 1.0),
            strokeWidth: 2.4,
            strokeCap: StrokeCap.round,
            backgroundColor: palette.border,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '必须 $done/$total',
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: allDone ? palette.textTertiary : palette.ink(palette.danger),
            ),
          ),
        ),
        _ledgerEntryIcon(
          glyph: AppIcons.inbox,
          count: pendingCount,
          tooltip: '待审批',
          onTap: () => _goTab('pending'),
        ),
        const SizedBox(width: AppSpacing.xs),
        _ledgerEntryIcon(
          glyph: AppIcons.history,
          tooltip: '历史记录',
          onTap: () => _goTab('history'),
        ),
      ],
    );
  }

  /// 必须任务的「正在发生」文案（优化 4）。
  ///
  /// 21:00 前说规则（`22:00 前没打卡 · 每件 −10`），21:00 之后改说剩余时间，
  /// 22:00 之后改说已经发生 —— 同一句话在不同时刻给的信息不一样，
  /// 才有「现在该动手」的紧迫感，而不是一条永远不动的说明书。
  String _mustCountdownHint() {
    const int deadlineMinutes = 22 * 60;
    final int nowMinutes = _now.hour * 60 + _now.minute;
    final int perTask = FamilyRules.mandatoryPenaltyPerTask;
    if (nowMinutes >= deadlineMinutes) {
      return '已过 22:00 · 每件 −$perTask';
    }
    if (nowMinutes >= 21 * 60) {
      final int left = deadlineMinutes - nowMinutes;
      final int hour = left ~/ 60;
      final int minute = left % 60;
      final String text = hour > 0 ? '$hour 小时 $minute 分' : '$minute 分钟';
      return '还剩 $text · 每件 −$perTask';
    }
    return '22:00 前没打卡 · 每件 −$perTask';
  }

  /// 任务页右上角的小圆图标（待审批 / 历史记录）。
  Widget _ledgerEntryIcon({
    required Glyph glyph,
    required VoidCallback onTap,
    required String tooltip,
    int count = 0,
  }) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: PressInkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: palette.surfaceSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: GlyphIcon(glyph, size: 16, color: palette.textSecondary),
              ),
              if (count > 0)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 15),
                    decoration: BoxDecoration(
                      color: palette.danger,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: palette.onColor(palette.danger),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- ④-a 任务区 ----

  Widget _buildTasksArea(FamilyState state, bool isParent) {
    final palette = context.palette;
    final records = state.records;
    final customTasks = context.watch<CustomTasksState>();
    final filter = _taskFilter;
    final bool earning = filter == TaskType.earning;

    // 内置任务与自定义任务先归一成同一批 entries，再按「此刻能不能做」三分区。
    // 这样「时间窗 / 日限」这些规则第一次变成看得见的信息，而不是点了才弹 toast。
    final entries = <_TaskEntry>[
      for (final task in FamilyRules.tasksByType(filter))
        _TaskEntry(
          config: task,
          custom: null,
          done: _isDone(task, records),
          windowOpen: task.window == null || task.window!.contains(_now),
          submitting: _submittingId == task.id,
        ),
      for (final task in customTasks.tasks.where((task) => task.type == filter))
        _TaskEntry(
          config: _toExecTask(task),
          custom: task,
          done: isRecordedToday(task, records, now: _now) ||
              customTasks.isDoneToday(task.id),
          windowOpen: true,
          submitting: _submittingId == CustomTasksState.userTaskExecId,
        ),
    ];

    final ready = entries.where((entry) => !entry.done && entry.windowOpen).toList(growable: false);
    final later = entries.where((entry) => !entry.done && !entry.windowOpen).toList(growable: false);
    final completed = entries.where((entry) => entry.done).toList(growable: false);
    final progress = todayProgress(FamilyRules.taskRules, records, now: _now);
    final bool busy = _submittingId != null;

    // v2.10 分类：赚钱任务按「今天必须完成 / 日常任务 / 本周任务 / 特殊加分」四组渲染。
    // 分组只作用于赚钱任务 —— 消费罚款那边是「花掉多少」的流水，分类只会让罚款更难找。
    // 已完成的不进任何一组，统一收进底部「今天已经做满」折叠。
    final pending = <_TaskEntry>[...ready, ...later];
    final mustEntries = pending
        .where((entry) => entry.config.mandatory && entry.config.group == TaskGroup.daily)
        .toList(growable: false);
    final dailyEntries = pending
        .where((entry) => !entry.config.mandatory && entry.config.group == TaskGroup.daily)
        .toList(growable: false);
    final weekEntries = pending
        .where((entry) => entry.config.group == TaskGroup.weekly)
        .toList(growable: false);
    final specialEntries = pending
        .where((entry) => entry.config.group == TaskGroup.special)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _mustStrip(progress: progress, pendingCount: state.pendingCount),
              const SizedBox(height: AppSpacing.md),
              _taskTypeSegment(),
              const SizedBox(height: AppSpacing.md),
              if (ready.isEmpty && later.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    earning ? '今天要赚的积分都拿到了 🎉' : '今天没有要记的账 🎉',
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      color: palette.textSecondary,
                    ),
                  ),
                )
              else if (earning) ...<Widget>[
                // ① 今天必须完成：没做会扣钱的那几件，永远排最上面
                if (mustEntries.isNotEmpty) ...<Widget>[
                  _taskGroupHeader(
                    icon: AppIcons.warning,
                    color: palette.ink(palette.danger),
                    text: '今天必须完成',
                    count: mustEntries.length,
                  ),
                  _mustPenaltyHint(),
                  for (final (i, entry) in mustEntries.indexed)
                    _taskEntrySlot(
                      index: i,
                      earning: earning,
                      entry: entry,
                      busy: busy,
                      records: records,
                    ),
                ],
                // ② 日常任务：做一件赚一件，不做也不扣
                if (dailyEntries.isNotEmpty) ...<Widget>[
                  if (mustEntries.isNotEmpty) const SizedBox(height: AppSpacing.md),
                  _taskGroupHeader(
                    icon: AppIcons.radioOn,
                    color: palette.ink(palette.success),
                    text: '日常任务',
                    count: dailyEntries.length,
                  ),
                  for (final (i, entry) in dailyEntries.indexed)
                    _taskEntrySlot(
                      index: i,
                      earning: earning,
                      entry: entry,
                      busy: busy,
                      records: records,
                    ),
                ],
                // ③ 本周任务：按自然周（周一–周日）算，行尾画次数圆点
                if (weekEntries.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  _taskGroupHeader(
                    icon: AppIcons.calendar,
                    color: palette.ink(palette.primary),
                    text: '本周任务',
                    count: weekEntries.length,
                  ),
                  for (final (i, entry) in weekEntries.indexed)
                    _taskEntrySlot(
                      index: i,
                      earning: earning,
                      entry: entry,
                      busy: busy,
                      records: records,
                    ),
                ],
                // ④ 特殊加分：一周才一两次，默认收起，不占首屏
                if (specialEntries.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  _foldRow(
                    icon: AppIcons.trophy,
                    label: '特殊加分',
                    count: specialEntries.length,
                    expanded: _specialExpanded,
                    onTap: () => setState(() => _specialExpanded = !_specialExpanded),
                  ),
                  if (_specialExpanded) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    for (final (i, entry) in specialEntries.indexed)
                      _taskEntrySlot(
                        index: i,
                        earning: earning,
                        entry: entry,
                        busy: busy,
                        records: records,
                      ),
                  ],
                ],
              ] else ...<Widget>[
                // 消费罚款：不分组，保持原来的平铺（那是「花掉多少」，分类只会更难找）
                if (ready.isNotEmpty) ...<Widget>[
                  _taskGroupHeader(
                    icon: AppIcons.radioOn,
                    color: palette.ink(palette.success),
                    text: '现在可以记',
                    count: ready.length,
                  ),
                  for (final (i, entry) in ready.indexed)
                    _taskEntrySlot(
                      index: i,
                      earning: earning,
                      entry: entry,
                      busy: busy,
                      records: records,
                    ),
                ],
                if (later.isNotEmpty) ...<Widget>[
                  if (ready.isNotEmpty) const SizedBox(height: AppSpacing.md),
                  _taskGroupHeader(
                    icon: AppIcons.clock,
                    color: palette.textSecondary,
                    text: '还没到时间',
                    count: later.length,
                  ),
                  for (final (i, entry) in later.indexed)
                    _taskEntrySlot(
                      index: i,
                      earning: earning,
                      entry: entry,
                      busy: busy,
                      records: records,
                    ),
                ],
              ],
              if (completed.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _foldRow(
                  icon: AppIcons.checkCircle,
                  label: '今天已经做满',
                  count: completed.length,
                  expanded: _completedExpanded,
                  onTap: () => setState(() => _completedExpanded = !_completedExpanded),
                ),
                if (_completedExpanded)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Column(
                      children: <Widget>[
                        for (final (i, entry) in completed.indexed)
                          _taskEntrySlot(
                            index: i,
                            earning: earning,
                            entry: entry,
                            busy: busy,
                            records: records,
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        // 自定义任务（仅家长：任务由家长定义，小孩只需打卡）
        if (isParent) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _buildCustomTaskCard(customTasks),
        ],
      ],
    );
  }

  /// 任务类型切换（赚钱任务 / 消费·罚款）。
  ///
  /// 视觉与上面 TabBar 的高亮一致：选中项是 `segmentedSelected` 实底 + 主色细边，
  /// 字色按这层底色取 —— 石墨黑下直接写 primary 只有 2.5:1，会糊在一起。
  Widget _taskTypeSegment() {
    final palette = context.palette;
    final bool hasBackground =
        context.select<ThemeState, bool>((state) => state.background.isNotEmpty);
    const List<(TaskType, String, Glyph)> items = <(TaskType, String, Glyph)>[
      (TaskType.earning, '赚钱任务', AppIcons.trendUp),
      (TaskType.spending, '消费 / 罚款', AppIcons.trendDown),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: ShapeDecoration(
        color: palette.softColor(hasBackground: hasBackground),
        shape: AppShape.all(AppRadius.full),
      ),
      child: Row(
        children: <Widget>[
          for (final (type, label, icon) in items)
            Expanded(
              child: PressInkWell(
                onTap: () {
                  if (_taskFilter == type) return;
                  setState(() {
                    _taskFilter = type;
                    _completedExpanded = false;
                  });
                },
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: ShapeDecoration(
                    color: _taskFilter == type ? palette.segmentedSelected : Colors.transparent,
                    shape: AppShape.all(AppRadius.full, side: BorderSide(color: _taskFilter == type
                          ? palette.primary.withValues(alpha: 0.35)
                          : Colors.transparent)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      GlyphIcon(
                        icon,
                        size: 14,
                        color: _taskFilter == type
                            ? palette.onColor(palette.segmentedSelected)
                            : palette.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: AppFontSize.sm,
                          fontWeight:
                              _taskFilter == type ? FontWeight.w600 : FontWeight.w500,
                          color: _taskFilter == type
                              ? palette.onColor(palette.segmentedSelected)
                              : palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 分区标题（现在可以打卡 / 还没到时间），右侧跟一个计数
  Widget _taskGroupHeader({
    required Glyph icon,
    required Color color,
    required String text,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          GlyphIcon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            text,
            style: TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$count',
            style: TextStyle(
              fontSize: AppFontSize.xs,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.7),
              fontFeatures: kTabularNumbers,
            ),
          ),
        ],
      ),
    );
  }

  /// 一个任务的列表行（含入场动画与行间距）
  Widget _taskEntrySlot({
    required int index,
    required bool earning,
    required _TaskEntry entry,
    required bool busy,
    required List<LedgerRecord> records,
  }) {
    final task = entry.config;
    final TaskRowState rowState = entry.done
        ? TaskRowState.done
        : entry.windowOpen
            ? TaskRowState.ready
            : TaskRowState.later;
    final bool tappable = !entry.done && !busy && !entry.submitting;
    // 周任务：行尾画「本周做了几次」的圆点（洗头 1/3、剪指甲 0/1）
    final int? weekTarget = task.weeklyTarget;
    final int? weekDone =
        weekTarget == null ? null : countWeekSubmissions(records, task.id, now: _now);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: EnterBox(
        index: index,
        // 长按看这条的规则（分值 / 频率 / 时间窗 / 没做扣多少）—— 规则变复杂后需要一个不占版面的出口
        child: GestureDetector(
          onLongPress: entry.custom != null ? null : () => unawaited(_showTaskRule(entry)),
          child: TaskRow(
          name: task.name,
          icon: taskIconFor(task.id, earning: earning),
          earning: earning,
          state: rowState,
          value: task.value > 0 ? '+${task.value}' : '${task.value}',
          meta: _taskEntryMeta(entry, records),
          // 「必须」红标只给没做会扣钱的任务；纯加分的参赛/获奖不挂，否则标就没有分量了
          mustBadge: task.mandatory,
          metaDanger: task.mandatory && !entry.done,
          weekDone: weekDone,
          weekTarget: weekTarget,
          onTap: tappable
              ? () => _startCheckIn(
                    task,
                    custom: entry.custom,
                    records: records,
                  )
              : null,
          ),
        ),
      ),
    );
  }

  /// 长按任务行：把这件的规则摊开说清楚。
  ///
  /// 列点：分值 / 频率 / 时间窗 / 必须完成与扣分 / 说明。
  /// 自定义任务没有固定规则，长按时不弹（`custom` 为 true 时 onLongPress 直接是 null）。
  Future<void> _showTaskRule(_TaskEntry entry) async {
    final task = entry.config;
    final palette = context.palette;
    final lines = <String>[
      task.value >= 0 ? '+${task.value} 分' : '${task.value} 分',
      if (task.isWeekly)
        '本周 ${task.weeklyGoal} 次'
      else if (task.dailyLimit != null)
        '每天最多 ${task.dailyLimit} 次'
      else
        '不限次数',
      if (task.window != null) '${task.window!.start}–${task.window!.end} 之间打卡',
      if (task.mandatory)
        '必须完成 · 22:00 结算，没做 −${_missPenaltyOf(task)}',
      if (task.description != null) task.description!,
    ];
    await showFloatingDialog<void>(
      context: context,
      child: AlertDialog(
        title: Row(
          children: <Widget>[
            GlyphIcon(taskIconFor(task.id), size: 20, color: task.value >= 0 ? palette.success : palette.danger),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(task.name)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '· $line',
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    height: 1.4,
                    color: palette.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        actions: <Widget>[
          AppTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 这条必须任务「没做会扣多少分」（正数）；规则没写就退回统一值
  int _missPenaltyOf(TaskConfig task) =>
      task.missPenalty?.abs() ?? FamilyRules.mandatoryPenaltyPerTask;

  /// 一行的元信息：时间窗优先，其次日限，再次说明。
  ///
  /// 时间窗文案分「还没到」和「已经过了」两种 —— `checkTask()` 的提示语只说
  /// 「只能在 19:00-22:00 之间打卡」，23 点看到这句会以为还得等。
  String _taskEntryMeta(_TaskEntry entry, List<LedgerRecord> records) {
    final task = entry.config;
    final window = task.window;
    final limit = task.dailyLimit;
    final int used = countTodaySubmissions(records, task.id, now: _now);

    if (entry.done) {
      if (limit != null) return '今天 $used/$limit 次';
      return '今天已经做过';
    }
    final int missPenalty = _missPenaltyOf(task);
    // ① 每天必须的任务：把「不做会怎样」直接写在行里，别让人去设置页翻规则
    if (task.mandatory && task.group == TaskGroup.daily) {
      if (window != null) {
        final int minutes = _now.hour * 60 + _now.minute;
        if (minutes < window.startMinutes) {
          return '${window.start} 之后打卡 · 没做 −$missPenalty';
        }
        if (minutes > window.endMinutes) {
          return '已过 ${window.end} · 没做 −$missPenalty';
        }
        return '${window.start}-${window.end} 打卡 · 没做 −$missPenalty';
      }
      return '每天必须 · 没做 −$missPenalty';
    }
    // ② 周任务：显示本周进度；必须类的再带上「缺一次扣多少」
    final int? weeklyTarget = task.weeklyTarget;
    if (weeklyTarget != null) {
      final int doneThisWeek = countWeekSubmissions(records, task.id, now: _now);
      final String progress = '本周 $doneThisWeek/$weeklyTarget 次';
      return task.mandatory ? '$progress · 缺一次 −$missPenalty' : progress;
    }
    if (window != null) {
      final int minutes = _now.hour * 60 + _now.minute;
      if (minutes < window.startMinutes) return '${window.start} 开始可以打卡';
      if (minutes > window.endMinutes) return '${window.start}-${window.end} 已经过了';
      return '${window.start}-${window.end} 可以打卡';
    }
    if (entry.custom != null) return '家长添加的自定义任务';
    if (limit != null) {
      if (limit > 1) return '每天 $limit 次 · 今天 $used/$limit';
      return '每天 $limit 次';
    }
    final description = task.description;
    if (description != null && description.isNotEmpty) return description;
    return '随时可以打卡';
  }

  /// 必须任务组下面那条罚分提示：把「不做会怎样」放在任务旁边，而不是藏在规则页里
  Widget _mustPenaltyHint() {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: ShapeDecoration(
        color: Color.alphaBlend(palette.danger.withValues(alpha: 0.08), palette.surface),
        shape: AppShape.all(AppRadius.sm),
      ),
      child: Row(
        children: <Widget>[
          GlyphIcon(AppIcons.warning, size: 13, color: palette.ink(palette.danger)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '22:00 前没打卡 · 每件 −${FamilyRules.mandatoryPenaltyPerTask}',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.ink(palette.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 可折叠的一行（「今天已经做满 N 项」/「自定义任务」）
  Widget _foldRow({
    required Glyph icon,
    required String label,
    required int? count,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadius.md);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: PressInkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              GlyphIcon(icon, size: 18, color: palette.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
              if (count != null) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w700,
                    color: palette.textSecondary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
              const Spacer(),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: AppMotion.fast,
                child: GlyphIcon(AppIcons.chevronDown, size: 20, color: palette.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 自定义任务（家长端管理区）：默认收起成一行，点开才出现表单与列表。
  ///
  /// 原来「SectionHeader + 三选一表单 + 任务列表」常驻在任务区底部，把「快捷任务」
  /// 挤到首屏之外；而加/删任务的频次远低于打卡，所以收成一行折叠项。
  Widget _buildCustomTaskCard(CustomTasksState customTasks) {
    final palette = context.palette;
    final int count = customTasks.tasks.length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _foldRow(
            icon: AppIcons.sliders,
            label: count == 0 ? '自定义任务 · 还没有任务' : '自定义任务',
            count: count == 0 ? null : count,
            expanded: _customManagerExpanded,
            onTap: () => setState(() => _customManagerExpanded = !_customManagerExpanded),
          ),
          if (_customManagerExpanded) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '「添加任务」本身不入账，打卡完成才给积分',
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
            ),
            const SizedBox(height: AppSpacing.sm),
            _CustomTaskForm(onSubmit: _addCustomTask),
            if (customTasks.tasks.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              ...customTasks.tasks.map((task) {
                final tag = task.kind == CustomTaskKind.preset
                    ? '预置'
                    : task.createdBy == TaskCreator.child
                        ? '孩子提的'
                        : '自定义';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          task.name,
                          style: TextStyle(fontSize: AppFontSize.sm, color: palette.text),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _pill(text: tag, color: palette.primary),
                      // 要照片的任务多一枚淡色小标：一眼看出哪条提交时要拍图
                      if (task.requirePhoto) ...<Widget>[
                        const SizedBox(width: AppSpacing.xs),
                        _pill(text: '需照片', color: palette.textTertiary),
                      ],
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        task.value > 0 ? '+${task.value}' : '${task.value}',
                        style: TextStyle(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w600,
                          color: task.value > 0 ? palette.success : palette.danger,
                          fontFeatures: kTabularNumbers,
                        ),
                      ),
                      AppIconButton(
                        tooltip: '删除任务',
                        iconSize: 18,
                        color: palette.danger,
                        onPressed: () => _confirmRemoveTask(task),
                        icon: const GlyphIcon(AppIcons.delete),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  void _confirmRemoveTask(CustomTask task) {
    final store = context.read<CustomTasksState>();
    showFloatingDialog<void>(
      context: context,
      child: AlertDialog(
        title: const Text('删掉这个任务？'),
        content: Text('「${task.name}」会从快捷任务里移除，已有的流水不受影响。'),
        actions: <Widget>[
          AppTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          AppTextButton(
            onPressed: () {
              Navigator.of(context).pop();
              store.removeTask(task.id);
            },
            child: const Text('删掉'),
          ),
        ],
      ),
    );
  }

  // ---- ④-b 待审批区（仅家长） ----

  Widget _buildPendingArea(FamilyState state) {
    final palette = context.palette;
    final pending = state.pendingRecords;
    if (pending.isEmpty) {
      return AppCard(
        // FlClash 空态：带插画与入场动画，比一行灰字有存在感。
        // NullStatus 自带滚动容器，塞进卡片里要给个确定高度。
        child: const SizedBox(
          height: 280,
          child: NullStatus(
            label: '暂无待审批申请',
            description: '孩子提交打卡后，会在这里等你确认',
            illustration: NullStatusIllustration.logs,
          ),
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '共 ${pending.length} 条待审批',
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  color: palette.textSecondary,
                  fontFeatures: kTabularNumbers,
                ),
              ),
              const Spacer(),
              AppFilledButton.icon(
                onPressed: _approvingAll ? null : () => _confirmApproveAll(pending),
                icon: const GlyphIcon(AppIcons.checkCircle, size: 18),
                label: const Text('全部通过'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, record) in pending.indexed)
            EnterBox(index: i, child: _pendingRow(record)),
        ],
      ),
    );
  }

  void _confirmApproveAll(List<LedgerRecord> pending) {
    showFloatingDialog<void>(
      context: context,
      child: AlertDialog(
        title: Text('一次通过全部 ${pending.length} 条？'),
        content: const Text('确认后才入账；要驳回的请单独处理'),
        actions: <Widget>[
          AppTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('再想想'),
          ),
          AppFilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_approveAll(pending));
            },
            child: const Text('全部通过'),
          ),
        ],
      ),
    );
  }

  Widget _pendingRow(LedgerRecord record) {
    final palette = context.palette;
    final positive = record.amount >= 0;
    final approving = _approvingIds.contains(record.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: palette.primarySoft,
              shape: AppShape.all(AppRadius.md),
            ),
            // primarySoft 是实色有色底：原始主题里 primary 与它是同一族的深 navy
            // （#1A1A2E 写 #2A2A4A 上），这个图标原来等于看不见（约 1.1:1）
            child: GlyphIcon(
              AppIcons.checklist,
              size: 16,
              color: palette.onColor(palette.primarySoft),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.taskName,
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                Text(
                  _formatTime(record.createdAt),
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
                if (record.note != null && record.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      record.note!,
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                    ),
                  ),
                if (record.imageUrl != null && record.imageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: _RecordThumb(url: record.imageUrl!),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    AppFilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: positive ? palette.success : palette.danger,
                        foregroundColor: palette.onColor(
                          positive ? palette.success : palette.danger,
                        ),
                      ),
                      onPressed: approving ? null : () => _approve(record.id),
                      icon: approving
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              // 转圈也算按钮上的「前景」：默认的 primary 写在
                              // success / danger 实心底上会跟底色撞
                              child: AppLoading(
                                size: 14,
                                color: palette.onColor(
                                  positive ? palette.success : palette.danger,
                                ),
                              ),
                            )
                          : const GlyphIcon(AppIcons.checkCircle, size: 16),
                      label: const Text('通过'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppOutlinedButton.icon(
                      onPressed: () => unawaited(_startReject(record)),
                      icon: const GlyphIcon(AppIcons.close, size: 16),
                      label: const Text('驳回'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${positive ? '+' : ''}${record.amount}',
            style: TextStyle(
              fontSize: AppFontSize.md,
              fontWeight: FontWeight.w700,
              color: positive ? palette.success : palette.danger,
              fontFeatures: kTabularNumbers,
            ),
          ),
        ],
      ),
    );
  }

  // ---- ④-c 历史记录区 ----

  /// 历史记录的状态筛选结果缓存：账本实例与筛选口径都没变就不用重新过滤
  /// （最大 500 条的 where + toList，页面每次重建都跑一遍太浪费）。
  List<LedgerRecord>? _filteredFrom;
  _RecordFilter? _filteredBy;
  List<LedgerRecord> _filteredCache = const <LedgerRecord>[];

  List<LedgerRecord> _filteredRecords(List<LedgerRecord> records) {
    if (identical(records, _filteredFrom) && _recordFilter == _filteredBy) {
      return _filteredCache;
    }
    final filtered = _recordFilter == _RecordFilter.all
        ? records
        : records
            .where(
              (record) => (record.status ?? LedgerStatus.approved).wire == _recordFilter.wire,
            )
            .toList(growable: false);
    _filteredFrom = records;
    _filteredBy = _recordFilter;
    _filteredCache = filtered;
    return filtered;
  }

  Widget _buildRecordsArea(FamilyState state, bool isParent) {
    final palette = context.palette;
    final filtered = _filteredRecords(state.records);
    final visible = filtered.take(_visibleCount).toList(growable: false);
    final remaining = filtered.length - visible.length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 状态筛选 + 导出（导出仅家长）
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final filter in _RecordFilter.values)
                ChoiceChip(
                  label: Text(filter.label),
                  selected: _recordFilter == filter,
                  onSelected: (_) => _onFilterChanged(filter),
                ),
              if (isParent && filtered.isNotEmpty)
                AppOutlinedButton.icon(
                  onPressed: () => unawaited(_exportCsv(filtered)),
                  icon: const GlyphIcon(AppIcons.download, size: 16),
                  label: const Text('导出 CSV'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // 筛选切换：整块内容横向滑入淡出（childKey 就是筛选的口径）
          SlideFadeSwitcher(
            childKey: ValueKey<String>(_recordFilter.wire),
            axis: Axis.horizontal,
            child: filtered.isEmpty
                ? SizedBox(
                    height: 300,
                    child: NullStatus(
                      label: _recordFilter == _RecordFilter.all
                          ? '暂无流水记录'
                          : '该状态下暂无记录',
                      description: _recordFilter == _RecordFilter.all
                          ? '打卡、加餐、罚款这些都会记在这里'
                          : '换个筛选条件看看',
                      illustration: NullStatusIllustration.logs,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 按周分组：同周记录归到一个标题下，翻历史时先看「这周花了多少」
                      ..._groupedRecordRows(visible, isParent),
                      if (remaining > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: SizedBox(
                            width: double.infinity,
                            child: AppOutlinedButton(
                              onPressed: () => setState(() => _visibleCount += _recordsPageSize),
                              child: Text(
                                '加载更多（还有 $remaining 条）',
                                style: TextStyle(
                                  fontFeatures: kTabularNumbers,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ---- 历史记录：按周分组 ----

  /// 把流水按「自然周（周一 00:00 起）」切成若干段，每段前面插一行周标题 + 本周合计。
  ///
  /// 流水本身按时间倒序返回，所以同一周的记录一定连续，只需比较上一周即可；
  /// 万一后端换了排序口径，最坏情况也只是同一个周标题出现两次（不会串周）。
  List<Widget> _groupedRecordRows(List<LedgerRecord> records, bool isParent) {
    final rows = <Widget>[];
    DateTime? lastWeek;
    for (final (i, record) in records.indexed) {
      final week = _weekStartOf(record.createdAt);
      if (lastWeek == null || week != lastWeek) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : AppSpacing.md,
              bottom: AppSpacing.xs,
            ),
            child: _weekHeader(week, records),
          ),
        );
        lastWeek = week;
      }
      // index 取模：首屏 0..19 错峰，之后「加载更多」追加的条目也从头错峰
      rows.add(EnterBox(index: i % _recordsPageSize, child: _recordRow(record, isParent)));
    }
    return rows;
  }

  /// 周标题：左边「本周 / 上周 / M月d日那周」，右边本周净变化。
  Widget _weekHeader(DateTime week, List<LedgerRecord> records) {
    final palette = context.palette;
    var total = 0;
    for (final record in records) {
      if (_weekStartOf(record.createdAt) == week && record.status != LedgerStatus.rejected) {
        total += record.amount;
      }
    }
    return Row(
      children: <Widget>[
        Text(
          _weekLabel(week),
          style: TextStyle(
            fontSize: AppFontSize.xs,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          '${total >= 0 ? '+' : ''}$total',
          style: TextStyle(
            fontSize: AppFontSize.xs,
            fontWeight: FontWeight.w600,
            fontFeatures: kTabularNumbers,
            color: total >= 0 ? palette.success : palette.danger,
          ),
        ),
      ],
    );
  }

  static DateTime _weekStartOf(DateTime at) {
    final day = DateTime(at.year, at.month, at.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  String _weekLabel(DateTime week) {
    final now = _now;
    final thisWeek = _weekStartOf(now);
    final diff = thisWeek.difference(week).inDays;
    if (diff == 0) return '本周';
    if (diff == 7) return '上周';
    return '${week.month} 月 ${week.day} 日那周';
  }

  /// 切换筛选条件后回到第一页，避免出现「筛完还剩 40 条已渲染」
  void _onFilterChanged(_RecordFilter filter) {
    setState(() {
      _recordFilter = filter;
      _visibleCount = _recordsPageSize;
    });
  }

  /// 单条流水
  Widget _recordRow(LedgerRecord record, bool isParent) {
    final palette = context.palette;
    final positive = record.amount >= 0;
    final status = record.status;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: (positive ? palette.success : palette.danger).withValues(alpha: 0.12),
              shape: AppShape.all(AppRadius.md),
            ),
            child: GlyphIcon(
              positive ? AppIcons.trendUp : AppIcons.trendDown,
              size: 16,
              color: positive ? palette.success : palette.danger,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.taskName,
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                Text(
                  _formatTime(record.createdAt),
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
                if (record.note != null && record.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      record.note!,
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                    ),
                  ),
                if (record.imageUrl != null && record.imageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: _RecordThumb(url: record.imageUrl!),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    // 小孩撤回自己待审批的申请
                    if (!isParent && status == LedgerStatus.pending)
                      AppOutlinedButton.icon(
                        onPressed: () => _confirmWithdraw(record),
                        icon: const GlyphIcon(AppIcons.undo, size: 16),
                        label: const Text('撤回'),
                      ),
                    // 驳回后重新提交：孩子对自己申请的补救动作 ——
                    // 家长端不给这个按钮，只留一句只读说明
                    if (!isParent && status == LedgerStatus.rejected)
                      AppOutlinedButton(
                        onPressed: () => unawaited(_resubmit(record.id)),
                        child: const Text('重新提交'),
                      ),
                    if (isParent && status == LedgerStatus.rejected)
                      Text(
                        '已驳回 · 孩子可重新提交',
                        style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                      ),
                    // 删除（仅家长）：含图片时后端一并删除 R2 图片
                    if (isParent)
                      AppOutlinedButton.icon(
                        onPressed: () => _confirmDelete(record),
                        style: OutlinedButton.styleFrom(foregroundColor: palette.danger),
                        icon: const GlyphIcon(AppIcons.delete, size: 16),
                        label: const Text('删除'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _statusPill(record),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${positive ? '+' : ''}${record.amount}',
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w700,
                  color: positive ? palette.success : palette.danger,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 流水状态标签
  Widget _statusPill(LedgerRecord record) {
    final palette = context.palette;
    return switch (record.status) {
      LedgerStatus.pending => _pill(text: '待审批', color: palette.warning),
      LedgerStatus.rejected => _pill(text: '已驳回', color: palette.danger),
      _ => _pill(text: '已入账', color: palette.success),
    };
  }

  void _confirmWithdraw(LedgerRecord record) {
    showFloatingDialog<void>(
      context: context,
      child: AlertDialog(
        title: const Text('撤回这条申请？'),
        content: const Text('撤回后记录会被删除，可以重新打卡'),
        actions: <Widget>[
          AppTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          AppFilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_withdraw(record.id));
            },
            child: const Text('撤回'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(LedgerRecord record) {
    final hasImage = record.imageUrl != null && record.imageUrl!.isNotEmpty;
    showFloatingDialog<void>(
      context: context,
      child: AlertDialog(
        title: const Text('确认删除该记录？'),
        content: Text(hasImage ? '关联图片也会一并删除，且不可恢复' : '删除后不可恢复'),
        actions: <Widget>[
          AppTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          AppFilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              // 实色红底上的字按这层底色取，而不是主题给主色配的 onPrimary
              foregroundColor: context.palette.onColor(
                Theme.of(context).colorScheme.error,
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_delete(record.id));
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 小圆角标签（状态 / 身份）
  ///
  /// 底色是「语义色 12% 盖在卡片底上」的合成色 —— 它也是一层有色底，所以字和图标
  /// 取这层实际颜色的 onColor。原来字色直接用语义色本身：原始主题下 warning 色写在自己
  /// 的 12% 淡底上只有 1.9:1（状态标签基本读不出来），success/danger 也只有 3.1/3.3。
  /// 底色与描边不动。
  Widget _pill({required String text, required Color color, Glyph? icon}) {
    final palette = context.palette;
    final Color pillFill = Color.alphaBlend(
      color.withValues(alpha: 0.12),
      palette.cardColor(
        hasBackground:
            context.select<ThemeState, bool>((state) => state.background.isNotEmpty),
      ),
    );
    final Color onPill = palette.onColor(pillFill);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.12),
        shape: AppShape.all(AppRadius.full, side: BorderSide(color: color.withValues(alpha: 0.4))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            GlyphIcon(icon, size: 12, color: onPill),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(text, style: TextStyle(fontSize: AppFontSize.xs, color: onPill)),
        ],
      ),
    );
  }

  /// 驳回弹窗：写一句话给女儿，而不是点一下就走
  Future<void> _startReject(LedgerRecord target) async {
    final controller = TextEditingController();
    final reason = await showAppSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '驳回「${target.taskName}」',
                style: TextStyle(
                  fontSize: AppFontSize.lg,
                  fontWeight: FontWeight.w600,
                  color: builderContext.palette.text,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '写一句为什么不行 —— 女儿会收到这句话；不写的话她只看到「已驳回」。',
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  color: builderContext.palette.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                maxLines: 3,
                maxLength: 60,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '例如：照片看不清，重新拍一张',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  const Spacer(),
                  AppTextButton(
                    onPressed: _rejecting
                        ? null
                        : () => Navigator.of(builderContext).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppFilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(builderContext).colorScheme.error,
                      // 同上：实色红底上的字按这层底色取
                      foregroundColor: builderContext.palette.onColor(
                        Theme.of(builderContext).colorScheme.error,
                      ),
                    ),
                    onPressed: _rejecting
                        ? null
                        : () {
                            setDialogState(() {});
                            Navigator.of(builderContext)
                                .pop(controller.text.trim());
                          },
                    child: const Text('确认驳回'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (!mounted || reason == null) return;
    await _confirmReject(target, reason);
  }

  /// 打卡弹窗（照片 + 备注）—— 内置任务与自定义任务共用。
  /// 屏幕正中的居中弹窗：底部悬浮导航栏不会盖住下面的提交按钮。
  /// 返回 null 表示用户取消。
  Future<_CheckInResult?> _showCheckInDialog(TaskConfig task) async {
    final isParent = _isParent;
    final noteController = TextEditingController();
    Uint8List? photo;
    var uploading = false;
    var picking = false;
    String? photoError;
    // 照片是不是硬门槛：赚钱类（含家长勾了「必须添加照片」的自定义任务）必须，
    // 消费 / 罚款只要写清原因。判定与网页版共用 core/task_rules.dart。
    final bool needPhoto = taskRequiresPhoto(task);

    final result = await showAppSheet<_CheckInResult>(
      context: context,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          final palette = builderContext.palette;
          Future<void> pick(ImageSource source) async {
            if (picking) return;
            setDialogState(() => picking = true);
            try {
              final compressed =
                  await pickCompressedImage(ImagePicker(), source: source);
              if (compressed == null) return;
              setDialogState(() {
                photo = compressed;
                photoError = null;
              });
            } on ImageUnreadableException {
              setDialogState(() => photoError = '这张图读不出来，换一张试试');
            } catch (_) {
              setDialogState(() => photoError = '选图失败，请重试');
            } finally {
              setDialogState(() => picking = false);
            }
          }

          final positive = task.value >= 0;
          // 表单内容偏高（照片 160 + 备注三行）：交给 SnapSheet 的高度自适应，
          // 内部再套一层滚动兜住窄屏与弹出键盘的情况。
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  task.name,
                  style: TextStyle(
                    fontSize: AppFontSize.lg,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                  Row(
                    children: <Widget>[
                      Text(
                        task.value > 0 ? '+${task.value}' : '${task.value}',
                        style: TextStyle(
                          fontSize: AppFontSize.lg,
                          fontWeight: FontWeight.w700,
                          color: positive ? palette.success : palette.danger,
                          fontFeatures: kTabularNumbers,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        task.unit,
                        style: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
                      ),
                    ],
                  ),
                  if (!isParent)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        '提交后要等家长审批，通过了积分才会入账',
                        style: TextStyle(fontSize: AppFontSize.xs, color: palette.warning),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    needPhoto ? '照片（必填）' : '照片（可选）',
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      color: needPhoto ? palette.danger : palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (photo != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.memory(
                        photo!,
                        width: double.infinity,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppOutlinedButton.icon(
                          onPressed: picking ? null : () => pick(ImageSource.camera),
                          icon: const GlyphIcon(AppIcons.camera, size: 18),
                          label: const Text('拍照'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppOutlinedButton.icon(
                          onPressed: picking ? null : () => pick(ImageSource.gallery),
                          icon: const GlyphIcon(AppIcons.photos, size: 18),
                          label: const Text('从相册选'),
                        ),
                      ),
                    ],
                  ),
                  if (photoError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        photoError!,
                        style: TextStyle(fontSize: AppFontSize.xs, color: palette.danger),
                      ),
                    )
                  // 必填照片还没选：把「为什么按钮点不动」写在这儿
                  else if (needPhoto && photo == null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        '这项任务要拍一张照片，或者从相册选一张，才能提交',
                        style: TextStyle(fontSize: AppFontSize.xs, color: palette.danger),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '备注（可选）',
                    style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    maxLength: 60,
                    decoration: const InputDecoration(hintText: '写点什么，例如：客厅和书桌都收拾好了'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
              children: <Widget>[
                const Spacer(),
                AppTextButton(
                  onPressed: uploading ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppFilledButton(
                  // 必填照片没选时按钮直接置灰：先选照片，再谈提交
                  onPressed: uploading || (needPhoto && photo == null)
                      ? null
                      : () async {
                          setDialogState(() => uploading = true);
                          String? imageUrl;
                          try {
                            if (photo != null) {
                              final uploaded =
                                  await UploadApi(ApiClient.shared).upload(photo!);
                              imageUrl = uploaded.url;
                            }
                          } catch (_) {
                            setDialogState(() {
                              uploading = false;
                              photoError = '图片上传失败，请重试';
                            });
                            return;
                          }
                          final note = noteController.text.trim();
                          if (mounted) {
                            Navigator.of(context).pop(
                              _CheckInResult(
                                note: note.isEmpty ? null : note,
                                imageUrl: imageUrl,
                              ),
                            );
                          }
                        },
                  child: uploading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          // 主色实心按钮上的转圈：默认也是 primary，会跟底撞成一片
                          child: AppLoading(
                            size: 18,
                            color: palette.onPrimary,
                          ),
                        )
                      : Text(isParent ? '确认记账' : '提交申请'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    noteController.dispose();
    return result;
  }
}

/// 打卡弹窗返回的提交内容
class _CheckInResult {
  const _CheckInResult({this.note, this.imageUrl});

  final String? note;
  final String? imageUrl;
}

/// 自定义任务表单（类型 / 价格 / 名称）—— 表单本身不入账
class _CustomTaskForm extends StatefulWidget {
  const _CustomTaskForm({required this.onSubmit});

  final Future<void> Function(TaskType type, int value, String name, bool requirePhoto) onSubmit;

  @override
  State<_CustomTaskForm> createState() => _CustomTaskFormState();
}

class _CustomTaskFormState extends State<_CustomTaskForm> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  TaskType _type = TaskType.earning;
  /// 「必须添加照片」：默认开（孩子交的任务大多得看见东西才算数）
  bool _requirePhoto = true;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final value = int.tryParse(_valueController.text.trim());
    if (name.isEmpty) {
      setState(() => _error = '请输入任务名称');
      return;
    }
    if (value == null || value < 1) {
      setState(() => _error = '请输入价格（至少 1 积分）');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    await widget.onSubmit(_type, value, name, _type == TaskType.earning && _requirePhoto);
    if (!mounted) return;
    setState(() => _submitting = false);
    _nameController.clear();
    _valueController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('类型', style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary)),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            for (final type in TaskType.values) ...<Widget>[
              ChoiceChip(
                label: Text(type == TaskType.earning ? '赚钱' : '消费 / 罚款'),
                selected: _type == type,
                onSelected: (_) => setState(() => _type = type),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // 价格 + 名称压成一行两列（方案 D）：表单矮一截，视线只走两行
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '价格',
                    style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: _valueController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(isDense: true, hintText: '积分'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '名称',
                    style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: _nameController,
                    maxLength: 20,
                    // 窄列里放不下「0/20」计数器；长度限制仍在
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '例如：帮忙浇花',
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // 「必须添加照片」：只对赚钱类有意义（扣分只要写清原因），
        // 所以跟着类型切换出现 / 消失，默认开。
        if (_type == TaskType.earning) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '必须添加照片',
                      style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '开启后，提交这条任务要先拍照或从相册选一张；关闭则可以直接提交',
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _requirePhoto,
                onChanged: _submitting
                    ? null
                    : (bool value) => setState(() => _requirePhoto = value),
              ),
            ],
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              _error!,
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.danger),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: AppFilledButton(
            onPressed: _submitting ? null : _submit,
            child: const Text('添加任务'),
          ),
        ),
      ],
    );
  }
}

/// 流水 / 待审批条目上的图片缩略图（点击看大图）
class _RecordThumb extends StatelessWidget {
  const _RecordThumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PressInkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => showFloatingDialog<void>(
        context: context,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(AppSpacing.md),
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => GlyphIcon(
                AppIcons.imageBroken,
                color: palette.textTertiary,
              ),
            ),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Image.network(
          url,
          width: 48,
          height: 48,
          // 只按显示尺寸解码：48 逻辑像素 × 3 倍屏，别把整张打卡照片解码进内存
          cacheWidth: 144,
          cacheHeight: 144,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            color: palette.softColor(
              hasBackground:
                  context.select<ThemeState, bool>((state) => state.background.isNotEmpty),
            ),
            child: GlyphIcon(AppIcons.photos, size: 18, color: palette.textTertiary),
          ),
        ),
      ),
    );
  }
}

/// 账本页的骨架屏：余额大卡 + 今日卡 + 一张流水列表卡（左图标块 / 两行文字 / 右侧数字），
/// 形状照着余额卡、今日卡、流水行摆 —— 加载完换成真内容时不会「跳」一下。
class _LedgerSkeleton extends StatelessWidget {
  const _LedgerSkeleton();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md + AppTopBar.contentInset(context),
        AppSpacing.md,
        AppSpacing.xl + AppNavBar.contentInset(context),
      ),
      children: <Widget>[
        EnterBox(
          index: 0,
          child: _skeletonCard(palette, <Widget>[
            const SkeletonLine(widthFactor: 0.34),
            const SizedBox(height: AppSpacing.md),
            const SkeletonBox(width: 132, height: 40, radius: AppRadius.sm),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonLine(widthFactor: 0.2, height: 12),
          ]),
        ),
        const SizedBox(height: AppSpacing.md),
        EnterBox(
          index: 1,
          child: _skeletonCard(palette, <Widget>[
            const SkeletonLine(widthFactor: 0.42),
            const SizedBox(height: AppSpacing.md),
            const SkeletonLine(widthFactor: 0.3, height: 24),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonLine(widthFactor: 0.5, height: 12),
            const SizedBox(height: AppSpacing.md),
            const SkeletonLine(widthFactor: 1.0, height: 6),
          ]),
        ),
        const SizedBox(height: AppSpacing.md),
        EnterBox(
          index: 2,
          child: _skeletonCard(palette, <Widget>[
            const SkeletonLine(widthFactor: 0.3),
            const SizedBox(height: AppSpacing.md),
            for (int i = 0; i < 4; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SkeletonBox(width: 32, height: 32, radius: AppRadius.md),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SkeletonLine(widthFactor: 0.45),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonLine(widthFactor: 0.7, height: 12),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  SkeletonBox(width: 44, height: 18, radius: AppRadius.sm),
                ],
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

/// 骨架屏的卡壳（与 AppCard 同形：实色卡底 + 描边 + lg 圆角）
Widget _skeletonCard(AppPalette palette, List<Widget> children) {
  return Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: ShapeDecoration(
      color: palette.surface,
      shape: AppShape.all(AppRadius.lg, side: BorderSide(color: palette.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

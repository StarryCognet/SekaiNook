import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../config/family_rules.dart';
import '../../../core/api_client.dart';
import '../../../core/api_exception.dart';
import '../../../core/image_compress.dart';
import '../../../core/ledger_csv.dart';
import '../../../core/task_rules.dart';
import '../../../data/api/upload_api.dart';
import '../../../data/models/custom_task.dart';
import '../../../data/models/ledger_record.dart';
import '../../../data/models/task_config.dart';
import '../../../state/custom_tasks_state.dart';
import '../../../state/family_state.dart';
import '../../../state/theme_state.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_widgets.dart';
import '../../widgets/state_views.dart';

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

  /// 只负责 TabBar 的高亮动画；**分区状态的唯一真相是地址栏的 `tab` 查询参数**
  /// （见 `build` 里的派生逻辑），因此这里不再存「当前分页」字段。
  TabController? _tabController;

  // ---- 驳回弹窗 ----
  bool _rejecting = false;

  // ---- 审批 ----
  bool _approvingAll = false;

  /// 正在审批的记录 id（按条加 loading，防止连点重复提交）
  final Set<String> _approvingIds = <String>{};

  // ---- 打卡弹窗 ----
  /// 正在提交的任务 id（防止手机连点重复入账）
  String? _submittingId;

  /// 兑换区输入框里的积分数（null = 还没填，视为 0）
  int? _exchangePoints;

  /// 历史记录状态筛选 + 已渲染条数（分页）
  _RecordFilter _recordFilter = _RecordFilter.all;
  int _visibleCount = _recordsPageSize;

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
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _pollTimer?.cancel();
    _tabController?.dispose();
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

  List<String> _tabsFor(bool isParent) => <String>[
        'tasks',
        if (isParent) 'pending',
        'records',
      ];

  /// 分页控制器：随身份变化重建（孩子端没有「待审批」页），
  /// 并把索引对齐到 URL 派生出来的分区 —— TabBar 的高亮和内容分支都用同一个值，
  /// 不会出现「高亮在 A、内容显示 B」。
  void _ensureTabController(bool isParent, int index) {
    final keys = _tabsFor(isParent);
    final current = _tabController;
    if (current == null || current.length != keys.length) {
      current?.dispose();
      _tabController = TabController(length: keys.length, vsync: this, initialIndex: index);
      return;
    }
    // TabBar 是本页面的子孙：在 build 里改索引只会把子孙标脏，
    // 同一帧内 TabBar 就会按新索引重画，不会残留一帧的错位。
    if (current.index != index) current.index = index;
  }

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
    final palette = context.palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: warning ? palette.warning : null,
        duration: Duration(seconds: warning ? 6 : 3),
      ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: '撤销', onPressed: () => unawaited(_undo(recordId))),
      ),
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

  bool _isDone(TaskConfig task, List<LedgerRecord> records) =>
      isTaskDone(task, records, now: _now);

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

  Future<void> _addCustomTask(TaskType type, int value, String name) async {
    final created = context.read<CustomTasksState>().addTask(
          CustomTaskInput(
            name: name,
            value: value,
            type: type,
            createdBy: TaskCreator.parent,
          ),
        );
    _toast('「${created.name}」已加进快捷任务，点一下就能打卡');
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
      _toast('已驳回，女儿会看到你的话');
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

  // ---- 兑换现金 ----

  /// 兑换现金（仅家长）：把指定积分数按 100 积分 = 10 元换成钱，
  /// 记一条「现金兑现」支出 —— 积分→钱的闭环留在同一本流水里。
  Future<void> _settle(int points) async {
    final amount = points;
    final state = context.read<FamilyState>();
    final balance = state.balance;
    if (amount <= 0 || amount > balance) return;
    final yuan = FamilyRules.pointsToYuan(amount);
    final task = TaskConfig(
      id: 'payout',
      name: '现金兑现',
      type: TaskType.spending,
      value: -amount,
    );
    try {
      await state.api.addLedgerRecord(
            task,
            note: '积分兑换现金：$amount 积分 = $yuan 元',
            autoApprove: true,
          );
      await state.loadLedger();
      if (!mounted) return;
      setState(() => _exchangePoints = null);
      _toast('已兑换 $yuan 元，扣掉 $amount 积分');
      _burst();
    } catch (e) {
      // 账记上了但自动审批失败：积分没扣掉，那笔在待审批里 —— 不能说「已兑换」
      if (e is LedgerApprovalException) {
        await state.loadLedger().catchError((Object _) {});
        _toast('已记账，但审批没成功 —— $amount 积分还没扣掉，记录在待审批里，去点一下通过',
            warning: true);
      } else {
        _toast(e is ApiException ? e.message : '兑换失败，请重试', warning: true);
      }
    }
  }

  // ---- 导出 CSV ----

  /// 导出 CSV（仅家长）：按当前筛选导出全部记录。
  ///
  /// Web 版走浏览器下载；移动端没有 share_plus / path_provider（不允许新增依赖），
  /// 因此把同一份 CSV 内容放进剪贴板，家长粘到表格软件里即可。
  Future<void> _exportCsv(List<LedgerRecord> records) async {
    if (records.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: buildLedgerCsv(records)));
    _toast(exportToastText(records.length));
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

  /// 今天的日期文案（对应 `toLocaleDateString('zh-CN', {month:'long', day:'numeric', weekday:'long'})`）
  String _formatDate(DateTime now) {
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 星期${weekdays[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FamilyState>();
    final isParent = state.role == FamilyRole.parent;
    // 分区状态的唯一真相：地址栏 `/family?tab=tasks|pending|history`（缺省 tasks）。
    // 非法的值（手输 / 旧链接）一律回落到任务区。
    final String rawTab = GoRouterState.of(context).uri.queryParameters['tab'] ?? '';
    final String tab =
        const <String>{'tasks', 'pending', 'history'}.contains(rawTab) ? rawTab : 'tasks';
    final String area = _areaFor(tab, isParent: isParent);
    final int tabIndex = math.max(0, _tabsFor(isParent).indexOf(area));
    _ensureTabController(isParent, tabIndex);
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: <Widget>[
          // 首屏四块按序号错峰进场
          EnterBox(index: 0, child: _buildBalanceCard(state, isParent)),
          const SizedBox(height: AppSpacing.md),
          EnterBox(index: 1, child: _buildTodayCard(state, isParent)),
          const SizedBox(height: AppSpacing.md),
          EnterBox(index: 2, child: _buildTrendCard(state.records)),
          const SizedBox(height: AppSpacing.md),
          EnterBox(index: 3, child: _buildTabs(state, isParent, area)),
        ],
      ),
    );
  }

  // ---- ① 余额大卡片 ----

  Widget _buildBalanceCard(FamilyState state, bool isParent) {
    final palette = context.palette;
    final balance = state.balance;
    final isPositive = balance >= 0;
    final balanceColor = isPositive ? palette.success : palette.danger;
    final exchangeValue = _exchangePoints ?? 0;
    final exchangeYuan = FamilyRules.pointsToYuan(exchangeValue);
    final canExchange = exchangeValue > 0 && exchangeValue <= balance;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.account_balance_wallet_outlined, size: 16, color: palette.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '当前总积分',
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
              const Spacer(),
              _pill(
                text: isPositive ? '盈余' : '透支',
                color: isPositive ? palette.success : palette.danger,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedCount(
            value: balance,
            style: TextStyle(
              fontSize: AppFontSize.num,
              fontWeight: FontWeight.w700,
              color: balanceColor,
              fontFeatures: kTabularNumbers,
            ),
          ),
          Text(
            '可用积分',
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
          ),
          if (isParent && state.pendingCount > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Icon(Icons.fact_check_outlined, size: 14, color: palette.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '待审批 ',
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    color: palette.primary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
                AnimatedCount(
                  value: state.pendingCount,
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    color: palette.primary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
                Text(
                  ' 项',
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    color: palette.primary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
            ),
          ],
          // 积分兑换现金：100 积分 = 10 元，可以只兑换一部分（仅家长、余额为正时）
          if (isParent && balance > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: palette.border),
            const SizedBox(height: AppSpacing.md),
            Text(
              '积分兑换现金 · ${FamilyRules.exchangeRateText}',
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) {
                setState(() => _exchangePoints = int.tryParse(value));
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: '想兑换多少积分（最多 $balance）',
                suffixText: '积分',
                hintStyle: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canExchange
                    ? () => _confirmExchange(exchangeValue, exchangeYuan)
                    : null,
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: Text('兑换 $exchangeYuan 元现金'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmExchange(int points, double yuan) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('兑换 $points 积分 = $yuan 元？'),
        content: const Text('会记一条「现金兑现」支出，剩下的积分留在账上；如需回退请删除该记录'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_settle(points));
            },
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );
  }

  // ---- ② 今日任务与作息 ----

  Widget _buildTodayCard(FamilyState state, bool isParent) {
    final palette = context.palette;
    final records = state.records;
    final hour = _now.hour;
    // 22:00 后仍未打卡睡觉：服务端会按 settleDay 自动记一笔 -20「未按时作息(晚于22:00)」
    final isLate = hour >= 22;
    final earningTasks = FamilyRules.tasksByType(TaskType.earning);
    TaskConfig? byId(String id) {
      for (final task in earningTasks) {
        if (task.id == id) return task;
      }
      return null;
    }

    final homeworkTask = byId('finish_homework');
    final sleepTask = byId('sleep_on_time');
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final ss = _now.second.toString().padLeft(2, '0');
    // 今日两项内置打卡（作业 / 睡觉）的完成度 —— 底部那条进度条
    final todayTasks =
        <TaskConfig?>[homeworkTask, sleepTask].whereType<TaskConfig>().toList(growable: false);
    final todayDone = todayTasks.where((task) => _isDone(task, records)).length;
    final todayProgress = todayTasks.isEmpty ? 0.0 : todayDone / todayTasks.length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.schedule_outlined, size: 16, color: palette.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '今日任务与作息',
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$hh:$mm:$ss',
            style: TextStyle(
              fontSize: AppFontSize.xl,
              fontWeight: FontWeight.w700,
              color: palette.text,
              fontFeatures: kTabularNumbers,
            ),
          ),
          Text(
            _formatDate(_now),
            style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (isLate)
            _pill(
              text: '已过 22:00，未打卡睡觉会记一次罚款',
              color: palette.danger,
              icon: Icons.nightlight_outlined,
            )
          else
            _pill(
              text: '作息正常',
              color: palette.success,
              icon: Icons.check_circle_outline,
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  // 实色底上的字 / 图标要按这层底色取，不能沿用主题给「主色」配的 onPrimary
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.success,
                    foregroundColor: palette.onColor(palette.success),
                  ),
                  onPressed: homeworkTask == null || _isDone(homeworkTask, records)
                      ? null
                      : () => _startCheckIn(homeworkTask, records: records),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('按时完成作业'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: palette.primary),
                  onPressed: sleepTask == null || _isDone(sleepTask, records)
                      ? null
                      : () => _startCheckIn(sleepTask, records: records),
                  icon: const Icon(Icons.nightlight_outlined, size: 18),
                  label: const Text('按时睡觉'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedProgressBar(
            value: todayProgress,
            color: palette.success,
            trackColor: palette.surfaceSoft,
            height: 6,
          ),
        ],
      ),
    );
  }

  // ---- ③ 近 14 天积分趋势 ----

  Widget _buildTrendCard(List<LedgerRecord> records) {
    final palette = context.palette;
    const trendDays = 14;
    final today = DateTime(_now.year, _now.month, _now.day);
    final labels = <String>[];
    final values = <int>[];
    for (var offset = trendDays - 1; offset >= 0; offset -= 1) {
      final day = today.subtract(Duration(days: offset));
      labels.add('${day.month}/${day.day}');
      var sum = 0;
      for (final record in records) {
        if (record.status != null && record.status != LedgerStatus.approved) continue;
        final at = record.createdAt.toLocal();
        if (at.year == day.year && at.month == day.month && at.day == day.day) {
          sum += record.amount;
        }
      }
      values.add(sum);
    }
    final hasData = values.any((value) => value != 0);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: '近 $trendDays 天积分趋势'),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text(
                  '最近 $trendDays 天还没有积分记录',
                  style: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
                ),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      // fl_chart 的 tooltip 底色默认是写死的深蓝灰（不是 palette 派生的），
                      // 深色主题下 palette.surface 也是深色，字会埋进底里。这里按全站
                      // tooltipTheme 的同一口径反着来：底 = 正文色，字 = 它的 onColor。
                      getTooltipColor: (BarChartGroupData group) => palette.text,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                          BarTooltipItem(
                        '${labels[group.x]}\n${rod.toY.toInt()} 积分',
                        TextStyle(
                          color: palette.onColor(palette.text),
                          fontSize: AppFontSize.xs,
                        ),
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: palette.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            value.toInt().toString(),
                            style: TextStyle(
                              fontSize: AppFontSize.xs,
                              color: palette.textSecondary,
                              fontFeatures: kTabularNumbers,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        // 对应 Web 版的 axisLabel.interval = 1（隔一个显示一个）
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= labels.length || index.isOdd) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              labels[index],
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
                  barGroups: <BarChartGroupData>[
                    for (var index = 0; index < values.length; index += 1)
                      BarChartGroupData(
                        x: index,
                        barRods: <BarChartRodData>[
                          BarChartRodData(
                            toY: values[index].toDouble(),
                            width: 18,
                            color: values[index] >= 0 ? palette.success : palette.danger,
                            borderRadius: values[index] >= 0
                                ? const BorderRadius.vertical(
                                    top: Radius.circular(AppRadius.sm),
                                  )
                                : const BorderRadius.vertical(
                                    bottom: Radius.circular(AppRadius.sm),
                                  ),
                          ),
                        ],
                      ),
                  ],
                ),
                duration: AppMotion.slower,
                curve: AppMotion.emphasized,
              ),
            ),
        ],
      ),
    );
  }

  // ---- ④ 分页：任务区 / 待审批 / 历史记录 ----

  /// 页面内切换分区：写回地址栏（`context.go` 是 replace 语义，不堆历史），
  /// 页面内容由 URL 派生，所以这里不再 setState。
  void _goTab(String area) {
    context.go('/family?tab=${_tabParamFor(area)}');
  }

  Widget _buildTabs(FamilyState state, bool isParent, String area) {
    final palette = context.palette;
    final controller = _tabController;
    if (controller == null) return const SizedBox.shrink();
    final labels = _tabsFor(isParent);
    // 内容分支跟着 URL 派生出来的分区走（不是 TabController.index）
    final index = math.max(0, labels.indexOf(area));
    final areas = <Widget>[
      _buildTasksArea(state, isParent),
      if (isParent) _buildPendingArea(state),
      _buildRecordsArea(state, isParent),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TabBar(
          controller: controller,
          onTap: (tapped) => _goTab(labels[tapped]),
          // 选中项的底是实色的 segmentedSelected，字色必须按它算 ——
          // 石墨黑下 primary 写在这个底上只有 2.5:1，几乎糊在一起
          labelColor: palette.onColor(palette.segmentedSelected),
          unselectedLabelColor: palette.textSecondary,
          // 高亮块在选项之间滑动 —— 仍由 URL 派生出来的 controller 驱动，没有自持状态
          indicator: BoxDecoration(
            color: palette.segmentedSelected,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: palette.primary.withValues(alpha: 0.35)),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          splashBorderRadius: BorderRadius.circular(AppRadius.full),
          tabs: <Widget>[
            Tab(text: '任务区'),
            if (isParent)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('待审批'),
                    if (state.pendingCount > 0) ...<Widget>[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: palette.danger,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          '${state.pendingCount}',
                          style: TextStyle(
                            fontSize: AppFontSize.xs,
                            // 实色红底上的数字：surface 在深色主题里也是深色，会看不见
                            color: palette.onColor(palette.danger),
                            fontFeatures: kTabularNumbers,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const Tab(text: '历史记录'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // 内容切换：横向滑入淡出（childKey 就是地址栏的 tab 口径）
        SlideFadeSwitcher(
          childKey: ValueKey<String>(_tabParamFor(area)),
          axis: Axis.horizontal,
          child: areas[index],
        ),
      ],
    );
  }

  // ---- ④-a 任务区 ----

  Widget _buildTasksArea(FamilyState state, bool isParent) {
    final palette = context.palette;
    final records = state.records;
    final customTasks = context.watch<CustomTasksState>();
    final earningTasks = FamilyRules.tasksByType(TaskType.earning);
    final spendingTasks = FamilyRules.tasksByType(TaskType.spending);
    final customEarning = customTasks.tasks
        .where((task) => task.type == TaskType.earning)
        .toList(growable: false);
    final customSpending = customTasks.tasks
        .where((task) => task.type == TaskType.spending)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(title: '快捷任务'),
              _groupLabel(
                palette.success,
                Icons.trending_up,
                '赚钱任务',
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final (i, task) in earningTasks.indexed)
                EnterBox(
                  index: i,
                  child: _taskButton(
                    task: task,
                    earning: true,
                    disabled: _isDone(task, records),
                    onTap: () => _startCheckIn(task, records: records),
                  ),
                ),
              // 自定义任务：同样摆在快捷任务区，点开走打卡弹窗（可传照片 / 写备注）
              for (final (i, task) in customEarning.indexed)
                EnterBox(
                  index: i,
                  child: _taskButton(
                    task: _toExecTask(task),
                    earning: true,
                    disabled: isRecordedToday(task, records, now: _now) ||
                        customTasks.isDoneToday(task.id),
                    onTap: () => _startCheckIn(
                      _toExecTask(task),
                      custom: task,
                      records: records,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              _groupLabel(
                palette.danger,
                Icons.trending_down,
                '消费 / 罚款',
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final (i, task) in spendingTasks.indexed)
                EnterBox(
                  index: i,
                  child: _taskButton(
                    task: task,
                    earning: false,
                    disabled: _isDone(task, records),
                    onTap: () => _startCheckIn(task, records: records),
                  ),
                ),
              for (final (i, task) in customSpending.indexed)
                EnterBox(
                  index: i,
                  child: _taskButton(
                    task: _toExecTask(task),
                    earning: false,
                    disabled: isRecordedToday(task, records, now: _now) ||
                        customTasks.isDoneToday(task.id),
                    onTap: () => _startCheckIn(
                      _toExecTask(task),
                      custom: task,
                      records: records,
                    ),
                  ),
                ),
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

  Widget _groupLabel(Color color, IconData icon, String text) => Row(
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            text,
            style: TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              color: context.palette.textSecondary,
            ),
          ),
        ],
      );

  Widget _taskButton({
    required TaskConfig task,
    required bool earning,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    final color = earning ? palette.success : palette.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            // 实色底上的字 / 图标：按这层底色取（success / danger 都不是主色）
            foregroundColor: palette.onColor(color),
            disabledBackgroundColor: palette.softColor(
              hasBackground:
                  context.select<ThemeState, bool>((state) => state.background.isNotEmpty),
            ),
            disabledForegroundColor: palette.textTertiary,
            alignment: Alignment.centerLeft,
          ),
          onPressed: disabled || _submittingId != null ? null : onTap,
          child: Row(
            children: <Widget>[
              Icon(earning ? Icons.add : Icons.remove, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(task.name, overflow: TextOverflow.ellipsis),
              ),
              Text(
                task.value > 0 ? '+${task.value}' : '${task.value}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: kTabularNumbers,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 自定义任务表单（类型 / 价格 / 名称）+ 任务列表
  Widget _buildCustomTaskCard(CustomTasksState customTasks) {
    final palette = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: '自定义任务',
            subtitle: '「添加任务」本身不入账，打卡完成才给积分',
          ),
          _CustomTaskForm(onSubmit: _addCustomTask),
          const SizedBox(height: AppSpacing.md),
          if (customTasks.tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                '还没有任务，添加一个吧',
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
              ),
            )
          else
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
                    IconButton(
                      tooltip: '删除任务',
                      iconSize: 18,
                      color: palette.danger,
                      onPressed: () => _confirmRemoveTask(task),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _confirmRemoveTask(CustomTask task) {
    final store = context.read<CustomTasksState>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删掉这个任务？'),
        content: Text('「${task.name}」会从快捷任务里移除，已有的流水不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
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
        child: EmptyView(message: '暂无待审批申请', icon: Icons.fact_check_outlined),
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
              FilledButton.icon(
                onPressed: _approvingAll ? null : () => _confirmApproveAll(pending),
                icon: const Icon(Icons.check_circle_outline, size: 18),
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('一次通过全部 ${pending.length} 条？'),
        content: const Text('确认后才入账；要驳回的请单独处理'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
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
            decoration: BoxDecoration(
              color: palette.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            // primarySoft 是实色有色底：原始主题里 primary 与它是同一族的深 navy
            // （#1A1A2E 写 #2A2A4A 上），这个图标原来等于看不见（约 1.1:1）
            child: Icon(
              Icons.fact_check_outlined,
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
                    FilledButton.icon(
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.onColor(
                                  positive ? palette.success : palette.danger,
                                ),
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('通过'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_startReject(record)),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
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

  Widget _buildRecordsArea(FamilyState state, bool isParent) {
    final palette = context.palette;
    final records = state.records;
    final filtered = _recordFilter == _RecordFilter.all
        ? records
        : records
            .where(
              (record) => (record.status ?? LedgerStatus.approved).wire == _recordFilter.wire,
            )
            .toList(growable: false);
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
                OutlinedButton.icon(
                  onPressed: () => unawaited(_exportCsv(filtered)),
                  icon: const Icon(Icons.download_outlined, size: 16),
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
                ? EmptyView(
                    message: _recordFilter == _RecordFilter.all ? '暂无流水记录' : '该状态下暂无记录',
                    icon: Icons.history,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // index 取模：首屏 0..19 错峰，之后「加载更多」追加的条目也从头错峰
                      for (final (i, record) in visible.indexed)
                        EnterBox(
                          index: i % _recordsPageSize,
                          child: _recordRow(record, isParent),
                        ),
                      if (remaining > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
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
            decoration: BoxDecoration(
              color: (positive ? palette.success : palette.danger).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              positive ? Icons.trending_up : Icons.trending_down,
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
                      OutlinedButton.icon(
                        onPressed: () => _confirmWithdraw(record),
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text('撤回'),
                      ),
                    // 驳回后重新提交：孩子对自己申请的补救动作 ——
                    // 家长端不给这个按钮，只留一句只读说明
                    if (!isParent && status == LedgerStatus.rejected)
                      OutlinedButton(
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
                      OutlinedButton.icon(
                        onPressed: () => _confirmDelete(record),
                        style: OutlinedButton.styleFrom(foregroundColor: palette.danger),
                        icon: const Icon(Icons.delete_outline, size: 16),
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('撤回这条申请？'),
        content: const Text('撤回后记录会被删除，可以重新打卡'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认删除该记录？'),
        content: Text(hasImage ? '关联图片也会一并删除，且不可恢复' : '删除后不可恢复'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              // 实色红底上的字按这层底色取，而不是主题给主色配的 onPrimary
              foregroundColor: dialogContext.palette.onColor(
                Theme.of(dialogContext).colorScheme.error,
              ),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
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
  Widget _pill({required String text, required Color color, IconData? icon}) {
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: onPill),
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
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) => AlertDialog(
          title: Text('驳回「${target.taskName}」'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('写一句为什么不行 —— 女儿会收到这句话；不写的话她只看到「已驳回」。'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: controller,
                maxLines: 3,
                maxLength: 60,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '例如：照片看不清，重新拍一张',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: _rejecting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
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
                      Navigator.of(dialogContext).pop(controller.text.trim());
                    },
              child: const Text('确认驳回'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (!mounted || reason == null) return;
    await _confirmReject(target, reason);
  }

  /// 打卡弹窗（照片 + 备注）—— 内置任务与自定义任务共用。
  /// 返回 null 表示用户取消。
  Future<_CheckInResult?> _showCheckInDialog(TaskConfig task) async {
    final isParent = _isParent;
    final noteController = TextEditingController();
    Uint8List? photo;
    var uploading = false;
    var picking = false;
    String? photoError;

    final result = await showModalBottomSheet<_CheckInResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (builderContext, setSheetState) {
          final palette = builderContext.palette;
          Future<void> pick(ImageSource source) async {
            if (picking) return;
            setSheetState(() => picking = true);
            try {
              final picked = await ImagePicker().pickImage(source: source);
              if (picked == null) return;
              final raw = await picked.readAsBytes();
              final compressed = compressImage(raw);
              if (compressed == null) {
                setSheetState(() => photoError = '这张图读不出来，换一张试试');
                return;
              }
              setSheetState(() {
                photo = compressed;
                photoError = null;
              });
            } catch (_) {
              setSheetState(() => photoError = '选图失败，请重试');
            } finally {
              setSheetState(() => picking = false);
            }
          }

          final positive = task.value >= 0;
          return Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              top: AppSpacing.md,
              bottom: MediaQuery.of(builderContext).viewInsets.bottom + AppSpacing.md,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SectionHeader(title: task.name),
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
                    '照片（可选）',
                    style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
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
                        child: OutlinedButton.icon(
                          onPressed: picking ? null : () => pick(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: const Text('拍照'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: picking ? null : () => pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
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
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: uploading
                          ? null
                          : () async {
                              setSheetState(() => uploading = true);
                              String? imageUrl;
                              try {
                                if (photo != null) {
                                  final uploaded =
                                      await UploadApi(ApiClient()).upload(photo!);
                                  imageUrl = uploaded.url;
                                }
                              } catch (_) {
                                setSheetState(() {
                                  uploading = false;
                                  photoError = '图片上传失败，请重试';
                                });
                                return;
                              }
                              final note = noteController.text.trim();
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop(
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.onPrimary,
                              ),
                            )
                          : Text(isParent ? '确认记账' : '提交申请'),
                    ),
                  ),
                ],
              ),
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

  final Future<void> Function(TaskType type, int value, String name) onSubmit;

  @override
  State<_CustomTaskForm> createState() => _CustomTaskFormState();
}

class _CustomTaskFormState extends State<_CustomTaskForm> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  TaskType _type = TaskType.earning;
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
    await widget.onSubmit(_type, value, name);
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
        Text('价格', style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary)),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _valueController,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(isDense: true, hintText: '积分'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('名称', style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary)),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _nameController,
          maxLength: 20,
          decoration: const InputDecoration(isDense: true, hintText: '例如：帮忙浇花'),
        ),
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
          child: FilledButton(
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
      onTap: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(AppSpacing.md),
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => Icon(
                Icons.broken_image_outlined,
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
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            color: palette.softColor(
              hasBackground:
                  context.select<ThemeState, bool>((state) => state.background.isNotEmpty),
            ),
            child: Icon(Icons.image_outlined, size: 18, color: palette.textTertiary),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
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
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: palette.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/family_rules.dart';
import '../../../core/api_client.dart';
import '../../../core/api_exception.dart';
import '../../../core/week.dart';
import '../../../data/api/plans_api.dart';
import '../../../data/models/weekly_plan.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_widgets.dart';
import '../../widgets/state_views.dart';

/// 每个科目的图标（与 Web 版 SUBJECT_ICONS 一致）
const Map<String, IconData> _subjectIcons = <String, IconData>{
  '英语': Icons.menu_book_outlined,
  '语文': Icons.auto_stories_outlined,
  '数学': Icons.calculate_outlined,
  '日常': Icons.home_outlined,
};

/// 每周学习计划：按固定模板把这一周的分组计划铺开，家长/孩子都能直接推进度。
///
/// 与 Web 版 `src/views/family/WeeklyPlan.tsx` 一致：
/// - 进页面用 `POST /api/plans` 幂等初始化整周（服务端已存在就原样回）；
/// - 进度改动走 `PATCH /api/plans/:id`，**服务端会把超出目标的数夹回去**，
///   所以每次都要把返回值回写本地（否则界面 60、库里 50）。
class WeeklyPlanPage extends StatefulWidget {
  const WeeklyPlanPage({super.key});

  @override
  State<WeeklyPlanPage> createState() => _WeeklyPlanPageState();
}

class _WeeklyPlanPageState extends State<WeeklyPlanPage> {
  final PlansApi _api = PlansApi(ApiClient());

  List<WeeklyPlan> _plans = const <WeeklyPlan>[];
  bool _loading = true;
  String? _error;

  /// 每行的输入框内容（key = plan.id）；提交前的草稿值
  final Map<String, int> _inputs = <String, int>{};

  Timer? _ticker;
  String _weekLabel = WeekUtil.currentWeekLabel();

  /// 正在提交的行（防连点）
  final Set<String> _pending = <String>{};

  @override
  void initState() {
    super.initState();
    // 每分钟走一次：周日晚上挂着页面跨周，周标签要跟着变
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final next = WeekUtil.currentWeekLabel();
      if (next == _weekLabel) return;
      setState(() => _weekLabel = next);
      unawaited(_init());
    });
    unawaited(_init());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 幂等初始化整周计划（对应 Web 的 ensureWeeklyPlans）
  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final seeds = FamilyRules.weeklyPlanTemplate
          .map((t) => PlanSeed(subject: t.subject, taskName: t.taskName, target: t.target))
          .toList(growable: false);
      final data = await _api.createPlans(_weekLabel, seeds);
      if (!mounted) return;
      setState(() {
        _plans = data;
        for (final plan in data) {
          _inputs[plan.id] = plan.current;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageOf(e);
        _loading = false;
      });
    }
  }

  /// 按模板科目顺序分组（模板里没有的科目排到最后）
  List<MapEntry<String, List<WeeklyPlanTemplate>>> get _grouped {
    final Map<String, List<WeeklyPlanTemplate>> grouped =
        <String, List<WeeklyPlanTemplate>>{};
    for (final subject in FamilyRules.planSubjects) {
      grouped[subject] = <WeeklyPlanTemplate>[];
    }
    for (final tpl in FamilyRules.weeklyPlanTemplate) {
      grouped.putIfAbsent(tpl.subject, () => <WeeklyPlanTemplate>[]).add(tpl);
    }
    return grouped.entries.where((e) => e.value.isNotEmpty).toList(growable: false);
  }

  /// task_name → 计划（同名的只取第一个）
  Map<String, WeeklyPlan> get _planByTask {
    final Map<String, WeeklyPlan> map = <String, WeeklyPlan>{};
    for (final plan in _plans) {
      map.putIfAbsent(plan.taskName, () => plan);
    }
    return map;
  }

  int get _totalTarget => _plans.fold(0, (sum, p) => sum + p.target);

  int get _totalCurrent => _plans.fold(0, (sum, p) => sum + p.current);

  int get _overallPercent =>
      _totalTarget > 0 ? (_totalCurrent / _totalTarget * 100).round() : 0;

  String _messageOf(Object e) {
    if (e is ApiException) return e.message;
    return '加载失败';
  }

  /// 落库并回写服务端夹取后的真实值
  Future<void> _persistPlan(WeeklyPlan plan, num value) async {
    final next = math.max(0, value.floor());
    if (next == plan.current) {
      setState(() => _inputs[plan.id] = plan.current);
      return;
    }
    setState(() => _pending.add(plan.id));
    try {
      final applied = await _api.updateCurrent(plan.id, next);
      if (!mounted) return;
      setState(() {
        _inputs[plan.id] = applied;
        _plans = _plans
            .map((p) => p.id == plan.id ? p.copyWith(current: applied) : p)
            .toList(growable: false);
      });
      _toast(applied == next ? '进度已更新' : '已记到上限 $applied');
      _burst();
    } catch (_) {
      if (!mounted) return;
      setState(() => _inputs[plan.id] = plan.current);
      _toast('更新失败');
    } finally {
      if (mounted) setState(() => _pending.remove(plan.id));
    }
  }

  void _handleAdd(WeeklyPlan plan) {
    unawaited(_persistPlan(plan, (_inputs[plan.id] ?? plan.current) + 1));
  }

  void _handleCommit(WeeklyPlan plan) {
    unawaited(_persistPlan(plan, _inputs[plan.id] ?? plan.current));
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 保存成功那一下的整页反馈：光环 + 对勾，不挡点击、播完自动消失。
  ///
  /// 包一层 mounted 判断，异步回调里就不用直接碰 context。
  void _burst() {
    if (!mounted) return;
    showBurst(context);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: () => unawaited(_init()));
    }
    if (_loading) {
      // 首屏加载改骨架屏；原来的加载文案保留在旁边
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SkeletonList(count: 3),
            const SizedBox(height: AppSpacing.md),
            Text(
              '正在翻开这周的学习计划…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _init,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: <Widget>[
            // 顶部卡与四类计划卡按序号错峰进场
            EnterBox(index: 0, child: _buildHeader(palette)),
            if (_plans.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xl),
                child: EmptyView(
                  message: '本周暂无学习计划',
                  icon: Icons.event_note_outlined,
                ),
              )
            else
              for (final (i, card) in _buildGroups(palette).indexed)
                EnterBox(index: i + 1, child: card),
          ],
        ),
      ),
    );
  }

  /// 顶部卡：周标签 + 总体完成度
  Widget _buildHeader(AppPalette palette) {
    final percent = _overallPercent;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _weekLabel,
                  style: TextStyle(
                    fontSize: AppFontSize.lg,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '本周学习计划',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '总体完成度',
                  style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: <Widget>[
                    AnimatedCount(
                      value: percent,
                      style: TextStyle(
                        fontSize: AppFontSize.xl,
                        fontWeight: FontWeight.w700,
                        color: palette.success,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                    Text(
                      '%',
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        color: palette.textSecondary,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          AnimatedCount(
                            value: _totalCurrent,
                            style: TextStyle(
                              fontSize: AppFontSize.sm,
                              color: palette.textTertiary,
                              fontFeatures: kTabularNumbers,
                            ),
                          ),
                          Text(
                            ' / $_totalTarget',
                            style: TextStyle(
                              fontSize: AppFontSize.sm,
                              color: palette.textTertiary,
                              fontFeatures: kTabularNumbers,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 76,
            height: 76,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: (percent / 100).clamp(0.0, 1.0)),
              duration: AppMotion.slower,
              builder: (_, value, _) => Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CircularProgressIndicator(
                    value: value,
                    strokeWidth: 6,
                    backgroundColor: palette.surfaceSoft,
                    valueColor: AlwaysStoppedAnimation<Color>(palette.success),
                  ),
                  Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                      fontFeatures: kTabularNumbers,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 按科目分组铺开
  List<Widget> _buildGroups(AppPalette palette) {
    final planByTask = _planByTask;
    final widgets = <Widget>[];
    for (final entry in _grouped) {
      final subject = entry.key;
      final icon = _subjectIcons[subject] ?? Icons.checklist_outlined;
      final rows = entry.value;
      final doneCount = rows
          .where((tpl) {
            final plan = planByTask[tpl.taskName];
            return plan != null && plan.target > 0 && plan.current >= plan.target;
          })
          .length;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(icon, size: 18, color: palette.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      subject,
                      style: TextStyle(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const Spacer(),
                    AnimatedCount(
                      value: doneCount,
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        color: palette.textTertiary,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                    Text(
                      '/${rows.length}',
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        color: palette.textTertiary,
                        fontFeatures: kTabularNumbers,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (var i = 0; i < rows.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(height: AppSpacing.md, color: palette.border, thickness: 0.5),
                  _buildRow(palette, rows[i], planByTask[rows[i].taskName]),
                ],
              ],
            ),
          ),
        ),
      );
    }
    widgets.add(const SizedBox(height: AppSpacing.xl));
    return widgets;
  }

  Widget _buildRow(AppPalette palette, WeeklyPlanTemplate tpl, WeeklyPlan? plan) {
    final current = plan?.current ?? 0;
    final target = tpl.target;
    final done = plan != null && target > 0 && current >= target;
    final percent =
        plan == null || target <= 0 ? 0 : math.min(100, (current / target * 100).round());
    final accent = done ? palette.success : palette.primary;
    final submitting = plan != null && _pending.contains(plan.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
                            tpl.taskName,
                            style: TextStyle(
                              fontSize: AppFontSize.sm,
                              fontWeight: FontWeight.w600,
                              color: done ? palette.success : palette.text,
                            ),
                          ),
                        ),
                        if (done) ...<Widget>[
                          const SizedBox(width: AppSpacing.xs),
                          Icon(Icons.check_circle, size: 14, color: palette.success),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: <Widget>[
                        AnimatedCount(
                          value: current,
                          style: TextStyle(
                            fontSize: AppFontSize.sm,
                            fontWeight: FontWeight.w700,
                            color: palette.text,
                            fontFeatures: kTabularNumbers,
                          ),
                        ),
                        Text(
                          ' / ',
                          style: TextStyle(fontSize: AppFontSize.sm, color: palette.textTertiary),
                        ),
                        AnimatedCount(
                          value: target,
                          style: TextStyle(
                            fontSize: AppFontSize.sm,
                            color: palette.textSecondary,
                            fontFeatures: kTabularNumbers,
                          ),
                        ),
                        if (plan == null) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surfaceSoft,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              '未初始化',
                              style: TextStyle(
                                fontSize: AppFontSize.xs,
                                color: palette.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (done) ...<Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    '已完成',
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.success),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (plan != null) ...<Widget>[
                _PlanInput(
                  value: _inputs[plan.id] ?? plan.current,
                  onChanged: (parsed) => _inputs[plan.id] = parsed,
                  onCommit: () => _handleCommit(plan),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(
                  onPressed: submitting ? null : () => _handleAdd(plan),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.add, size: 16),
                            SizedBox(width: 2),
                            Text('增加'),
                          ],
                        ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedProgressBar(
            value: percent / 100,
            color: accent,
            trackColor: palette.surfaceSoft,
            height: 4,
          ),
        ],
      ),
    );
  }
}

/// 单个计划的输入框：自己持有 controller（否则每次 build 换一个，
/// 光标会跳、旧 controller 还会泄漏），失焦 / 回车时提交。
class _PlanInput extends StatefulWidget {
  const _PlanInput({
    required this.value,
    required this.onChanged,
    required this.onCommit,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final VoidCallback onCommit;

  @override
  State<_PlanInput> createState() => _PlanInputState();
}

class _PlanInputState extends State<_PlanInput> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant _PlanInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 服务端夹取后回写的真实值要同步进来；值没变就不碰（正在输入时不打断光标）
    if (oldWidget.value == widget.value) return;
    _controller.text = '${widget.value}';
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 64,
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        style: TextStyle(
          fontSize: AppFontSize.sm,
          color: palette.text,
          fontFeatures: kTabularNumbers,
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
        ),
        onChanged: (raw) {
          final parsed = int.tryParse(raw);
          if (parsed == null) return;
          widget.onChanged(math.max(0, parsed));
        },
        onEditingComplete: widget.onCommit,
        onSubmitted: (_) => widget.onCommit(),
        onTapOutside: (_) => widget.onCommit(),
      ),
    );
  }
}

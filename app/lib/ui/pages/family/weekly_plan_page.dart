import 'package:sekainook_app/ui/icons/icons.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sekainook_app/ui/widgets/app_toast.dart';
import 'package:sekainook_app/ui/widgets/app_loading.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../config/family_rules.dart';
import '../../../core/api_client.dart';
import '../../../core/api_exception.dart';
import '../../../core/app_foreground.dart';
import '../../../core/week.dart';
import '../../../data/api/plans_api.dart';
import '../../../data/models/weekly_plan.dart';
import '../../../state/theme_state.dart';
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

/// 每个科目的图标（与 Web 版 SUBJECT_ICONS 一致）
const Map<String, Glyph> _subjectIcons = <String, Glyph>{
  '英语': AppIcons.book,
  '语文': AppIcons.book,
  '数学': AppIcons.calculate,
  '日常': AppIcons.home,
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

class _WeeklyPlanPageState extends State<WeeklyPlanPage> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    // 每分钟走一次：周日晚上挂着页面跨周，周标签要跟着变
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // 后台不问（对应 Web 版轮询里的 document.hidden 判断），回前台时补一次
      if (!isAppInForeground) return;
      _tick();
    });
    unawaited(_init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  /// 回到前台立刻补一次：后台期间跳过的 tick 不用再等下一分钟
  /// （周日晚上退在后台、周一早上打开，这一下就把周标签和新一周的计划补上）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _tick();
  }

  /// 一分钟一跳要做的事：周标签没跨周就到此为止。
  ///
  /// 跨周才重新拉（`_init` 是 `POST /api/plans`，幂等但终究是写请求，
  /// 不值得每次切回前台都打一次；本页数据也只在跨周时才是旧的）。
  void _tick() {
    final next = WeekUtil.currentWeekLabel();
    if (next == _weekLabel) return;
    setState(() => _weekLabel = next);
    unawaited(_init());
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
    AppToast.show(context, message);
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
      // 首屏加载改骨架屏：形状照着「周标签 / 总进度卡 + 科目卡」铺；
      // 原来的加载文案保留在下面（只换「加载中」的视觉，判定逻辑不动）
      return SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Expanded(child: _WeeklySkeleton()),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Text(
                '正在翻开这周的学习计划…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _init,
        child: ListView(
          // 底部让出底栏胶囊（MainShell 开了 extendBody，它浮在内容之上）
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md + AppTopBar.contentInset(context),
            AppSpacing.md,
            AppSpacing.md + AppNavBar.contentInset(context),
          ),
          children: <Widget>[
            // 顶部卡与四类计划卡按序号错峰进场
            EnterBox(index: 0, child: _buildHeader(palette)),
            if (_plans.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xl),
                child: EmptyView(
                  message: '本周暂无学习计划',
                  icon: AppIcons.calendar,
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
      final icon = _subjectIcons[subject] ?? AppIcons.checklist;
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
                    GlyphIcon(icon, size: 18, color: palette.primary),
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

  /// AppCard 当前的实色卡底（「有没有设背景图」决定）—— 淡色块要合到它上面算字色
  Color get _cardBase => context.palette.cardColor(
        hasBackground: context.select<ThemeState, bool>(
          (state) => state.background.isNotEmpty,
        ),
      );

  /// 把「语义色 + 透明度」的淡色块合到它铺着的那层底上 —— 得到的是眼睛看到的背景色，
  /// 再交给 [AppPalette.onColor] 取字色。淡色块 alpha 只有 12%，合成底基本等于卡片底。
  static Color _tinted(Color color, Color base, [double alpha = 0.12]) =>
      Color.alphaBlend(color.withValues(alpha: alpha), base);

  Widget _buildRow(AppPalette palette, WeeklyPlanTemplate tpl, WeeklyPlan? plan) {
    final current = plan?.current ?? 0;
    final target = tpl.target;
    final done = plan != null && target > 0 && current >= target;
    // 「已完成」标签的底 = 12% 的 success 合到卡片底上（有色底），字色按这层实际颜色取：
    // 原来把 success 本色写在自己的淡底上，浅色主题下只有约 3:1，xs 号字偏糊
    final Color doneChipFill = _tinted(palette.success, _cardBase);
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
                          GlyphIcon(AppIcons.checkCircle, size: 14, color: palette.success),
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
                            decoration: ShapeDecoration(
                              color: palette.surfaceSoft,
                              shape: AppShape.all(AppRadius.sm),
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
                  decoration: ShapeDecoration(
                    color: palette.success.withValues(alpha: 0.12),
                    shape: AppShape.all(AppRadius.sm),
                  ),
                  child: Text(
                    '已完成',
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.onColor(doneChipFill),
                    ),
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
                AppFilledButton(
                  onPressed: submitting ? null : () => _handleAdd(plan),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    // 实色底上的字 / 图标：按这层底色取（原来写死 Colors.white）
                    foregroundColor: palette.onColor(accent),
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: submitting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          // 转圈也按底色取色，默认的 primary 写在实色底上会跟底撞
                          child: AppLoading(
                            size: 14,
                            color: palette.onColor(accent),
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            GlyphIcon(AppIcons.add, size: 16),
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

/// 周计划页的骨架屏：一张「周标签 / 总进度」卡 + 三张科目卡
/// （科目名 + 每行「任务名 / 目标」+ 右侧增加按钮），
/// 形状照着周标签卡与科目卡摆 —— 加载完换成真内容时不会「跳」一下。
class _WeeklySkeleton extends StatelessWidget {
  const _WeeklySkeleton();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        EnterBox(
          index: 0,
          child: _skeletonCard(palette, <Widget>[
            const SkeletonLine(widthFactor: 0.3, height: 20),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonLine(widthFactor: 0.42),
            const SizedBox(height: AppSpacing.md),
            const SkeletonLine(widthFactor: 0.25, height: 12),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonLine(widthFactor: 0.55, height: 18),
          ]),
        ),
        for (int card = 0; card < 3; card++)
          EnterBox(
            index: card + 1,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: _skeletonCard(palette, <Widget>[
                const Row(
                  children: <Widget>[
                    SkeletonBox(width: 18, height: 18, radius: AppRadius.sm),
                    SizedBox(width: AppSpacing.xs),
                    Expanded(child: SkeletonLine(widthFactor: 0.3)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                for (int row = 0; row < 3; row++) ...<Widget>[
                  if (row > 0) const SizedBox(height: AppSpacing.md),
                  const Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SkeletonLine(widthFactor: 0.5),
                            SizedBox(height: AppSpacing.sm),
                            SkeletonLine(widthFactor: 0.28, height: 12),
                          ],
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      SkeletonBox(width: 72, height: 34, radius: AppRadius.sm),
                    ],
                  ),
                ],
              ]),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
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

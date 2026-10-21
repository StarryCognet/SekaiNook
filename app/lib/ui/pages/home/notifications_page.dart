import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sekainook_app/ui/widgets/app_toast.dart';
import 'package:sekainook_app/ui/widgets/app_loading.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_constants.dart';
import '../../../core/time_text.dart';
import '../../../data/models/notification_record.dart';
import '../../../state/family_state.dart';
import '../../../state/notification_state.dart';
import '../../../state/settings_state.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';
import '../../shell/app_nav_bar.dart';
import '../../shell/app_top_bar.dart';
import '../../shell/main_shell.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_widgets.dart';
import '../../widgets/state_views.dart';
import '../../widgets/motion/app_buttons.dart';
import '../../widgets/motion/press_scale.dart';

/// 通知收件箱（对应 Web 版 `src/views/home/NotificationsPage.tsx`）。
///
/// 一格信箱 = 一个人：家长看「孩子的打卡动态」，孩子看「妈妈说的话」。
/// 服务端通知表还没迁移好（`ready == false`）时**按空信箱显示，不报错**。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  /// 地址栏的 `?filter=` 仍是落地时的唯一真相（在 `build` 里派生，见 [_goFilter] 的写入侧）；
  /// 这个字段只是**设备记忆**：从铃铛 / 首页宫格进来时那些入口不带 query，
  /// 用它兜底，省得每次都要重选一遍（对应 Web 版的 `useViewState('home.noticeFilter')`）。
  String? _rememberedFilter;

  /// 已经发起过加载的信箱 —— 身份变了要换一格重新拉
  NotifyAudience? _loadedAudience;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRememberedFilter());
  }

  Future<void> _loadRememberedFilter() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(AppConstants.keyNoticeFilter);
      if (!mounted || saved == null) return;
      if (saved != 'all' && saved != 'unread') return;
      setState(() => _rememberedFilter = saved);
    } catch (_) {
      // 读不到就当没记过，按「全部」显示
    }
  }

  bool _markingAll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final audience = audienceOf(context.read<FamilyState>().role);
    if (_loadedAudience == audience) return;
    _loadedAudience = audience;
    // load() 一进门就 notifyListeners()，必须等这一帧画完再发起，
    // 否则就是「build 期间 markNeedsBuild」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<NotificationState>().load(audience));
    });
  }

  // ---- 动作 ----

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _reload() {
    unawaited(context.read<NotificationState>().load(audienceOf(context.read<FamilyState>().role)));
  }

  Future<void> _handleOpen(NotificationRecord item) async {
    final notifications = context.read<NotificationState>();
    if (item.isUnread) {
      // 不 await：角标先变小，失败由 store 内部拉真实数据兜底
      unawaited(notifications.markRead(item.id));
    }
    final link = item.link;
    if (link != null && link.isNotEmpty && mounted) {
      context.go(link);
    }
  }

  Future<void> _handleMarkAll() async {
    final notifications = context.read<NotificationState>();
    setState(() => _markingAll = true);
    try {
      await notifications.markAllRead();
      if (!mounted) return;
      showBurst(context);
      _toast('已全部标记为已读');
    } catch (_) {
      if (!mounted) return;
      _toast('没能全部已读，请稍后重试', error: true);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    AppToast.show(
      context,
      message,
      tone: error ? AppToastTone.error : AppToastTone.neutral,
    );
  }

  // ---- 渲染 ----

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // watch 整个 FamilyState：身份一变 didChangeDependencies 就会重跑，换一格信箱
    final family = context.watch<FamilyState>();
    final state = context.watch<NotificationState>();
    final settings = context.watch<SettingsState>();

    final audience = audienceOf(family.role);
    final items = state.items;

    // 筛选状态的唯一真相：地址栏 `/home/notifications?filter=all|unread`。
    // 地址栏没带（铃铛 / 首页宫格这些入口都不带）才回落到设备记忆，再没有就是 all；
    // 非法值（手输 / 旧链接）同样回落到 all。
    final String rawFilter = GoRouterState.of(context).uri.queryParameters['filter'] ?? '';
    final String effective = rawFilter.isEmpty ? (_rememberedFilter ?? 'all') : rawFilter;
    final String filter =
        const <String>{'all', 'unread'}.contains(effective) ? effective : 'all';
    final bool unreadOnly = filter == 'unread';

    final visible = unreadOnly
        ? items.where((item) => item.isUnread).toList(growable: false)
        : items;

    final who = audience == NotifyAudience.parent
        ? '${settings.kidName}的打卡动态'
        : '${settings.momName}说的话';

    // 返回键交给主壳统一处理：进通知页时外壳记下了「首页」这一步，按返回就回首页
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(palette, who, state.unreadCount),
            if (!state.ready && !state.loading)
              _buildNotice(
                palette,
                '通知功能还没就绪（服务端通知表尚未创建），等家长执行一次数据库迁移就会出现。',
              ),
            if (state.error != null && items.isNotEmpty) _buildRefreshFailedBar(palette),
            if (items.isNotEmpty) _buildFilter(palette, state.unreadCount, unreadOnly),
            Expanded(
              // 筛选切换走 SlideFadeSwitcher：key 就是地址栏派生出来的 filter 值
              child: SlideFadeSwitcher(
                childKey: ValueKey<String>(filter),
                child: _buildBody(palette, state, visible, unreadOnly),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppPalette palette, String who, int unreadCount) {
    final TextStyle subtitleStyle = TextStyle(
      fontSize: AppFontSize.xs,
      color: palette.textSecondary,
      fontFeatures: kTabularNumbers,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          AppIconButton(
            onPressed: _goBack,
            tooltip: '返回',
            icon: Icon(Icons.arrow_back, color: palette.text),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '通知',
                  style: TextStyle(
                    fontSize: AppFontSize.lg,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(text: who),
                      if (unreadCount > 0) ...<InlineSpan>[
                        const TextSpan(text: ' · '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: AnimatedCount(value: unreadCount, style: subtitleStyle),
                        ),
                        const TextSpan(text: ' 条未读'),
                      ] else
                        const TextSpan(text: ' · 都看过了'),
                    ],
                  ),
                  style: subtitleStyle,
                ),
              ],
            ),
          ),
          AppTextButton(
            onPressed: unreadCount == 0 || _markingAll ? null : _handleMarkAll,
            child: _markingAll
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: AppLoading(size: 20, color: palette.primary),
                  )
                : const Text('全部已读'),
          ),
        ],
      ),
    );
  }

  /// 把「语义色 + 透明度」的淡色块合到它实际铺着的那层底上 —— 得到的就是眼睛看到的
  /// 背景色，再交给 [AppPalette.onColor] / [AppPalette.onColorSoft] 取字色。
  ///
  /// 淡色块的 alpha 只有 10%～12%，所以合成底基本等于它下面那层（页面底 / 卡片底）；
  /// 设了背景图时底下是照片 + 薄纱，拿 palette.bg 当近似值，量级上足够判断亮暗。
  static Color _tinted(Color color, Color base, [double alpha = 0.12]) =>
      Color.alphaBlend(color.withValues(alpha: alpha), base);

  Widget _buildNotice(AppPalette palette, String message) {
    // 12% 的警示色盖在页面底上 —— 这层淡色块本身就是「有色底」：
    // 字和图标都要取它合成后的实际颜色的 onColor（原始主题下 amber 色写在 amber 淡底
    // 上只有 1.7:1，图标和说明都会看不清）。
    final Color noticeFill = _tinted(palette.warning, palette.bg);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: ShapeDecoration(
        color: palette.warning.withValues(alpha: 0.12),
        shape: AppShape.all(AppRadius.md, side: BorderSide(color: palette.warning.withValues(alpha: 0.4))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: palette.onColor(noticeFill)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.onColorSoft(noticeFill),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshFailedBar(AppPalette palette) {
    // 同样的道理：10% 的危险色淡底上，文字取合成底的 onColorSoft
    final Color barFill = _tinted(palette.danger, palette.bg, 0.1);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: ShapeDecoration(
        color: palette.danger.withValues(alpha: 0.1),
        shape: AppShape.all(AppRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off, size: 14, color: palette.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '通知没刷新成功，下面是上次看到的内容',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.onColorSoft(barFill),
              ),
            ),
          ),
          AppTextButton(
            onPressed: _reload,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 切换筛选：写回地址栏（`context.go` 是 replace 语义，不堆历史），
  /// 选中态由 URL 派生；同时记进设备，下次从铃铛进来还认这个选择。
  void _goFilter(String filter) {
    unawaited(_rememberFilter(filter));
    context.go('/home/notifications?filter=$filter');
  }

  Future<void> _rememberFilter(String filter) async {
    if (mounted) setState(() => _rememberedFilter = filter);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyNoticeFilter, filter);
    } catch (_) {
      // 存不住不影响这次切换
    }
  }

  Widget _buildFilter(AppPalette palette, int unreadCount, bool unreadOnly) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          _filterChip(
            palette,
            label: '全部',
            selected: !unreadOnly,
            onTap: () => _goFilter('all'),
          ),
          const SizedBox(width: AppSpacing.sm),
          _filterChip(
            palette,
            label: unreadCount > 0 ? '未读 ($unreadCount)' : '未读',
            selected: unreadOnly,
            onTap: () => _goFilter('unread'),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    AppPalette palette, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      decoration: ShapeDecoration(
        color: selected ? palette.segmentedSelected : palette.surfaceSoft,
        shape: AppShape.all(AppRadius.full, side: BorderSide(color: selected ? palette.primary : palette.border)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: PressInkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                // 选中态的底是实色的 palette.segmentedSelected（有色底），
                // 字色按它算：午夜蓝 / 石墨黑下 primary 写在这个底上会发闷
                color: selected
                    ? palette.onColor(palette.segmentedSelected)
                    : palette.textSecondary,
                fontFeatures: kTabularNumbers,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    AppPalette palette,
    NotificationState state,
    List<NotificationRecord> visible,
    bool unreadOnly,
  ) {
    if (state.loading && state.items.isEmpty) {
      // 首屏骨架屏：形状照着通知卡摆（图标块 + 标题 / 正文 / 时间三行）
      return const _NotifySkeleton();
    }
    if (state.error != null && state.items.isEmpty) {
      return ErrorView(message: state.error!, onRetry: _reload);
    }
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<NotificationState>().refresh(),
        child: _scrollable(
          EmptyView(
            message: unreadOnly ? '没有未读通知' : '暂时没有通知',
            hint: unreadOnly ? '下拉可以刷新' : null,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<NotificationState>().refresh(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        // 底部让出底栏胶囊（MainShell 开了 extendBody，它浮在内容之上）
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppTopBar.contentInset(context),
          AppSpacing.md,
          AppSpacing.lg + AppNavBar.contentInset(context),
        ),
        itemCount: visible.length,
        // 每条错峰进场。这里刻意不加 key：靠位置复用，
        // 10 秒轮询刷新时不会重播（新通知插队也不会让整表闪一遍）。
        itemBuilder: (context, index) =>
            EnterBox(index: index, child: _buildItem(palette, visible[index])),
      ),
    );
  }

  /// 空态 / 错误态也要能下拉刷新：撑满一屏 + AlwaysScrollable
  Widget _scrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }

  Widget _buildItem(AppPalette palette, NotificationRecord item) {
    final color = _colorFor(palette, item.type);
    // 未读卡的底是 AppCard.highlight 的填充色 palette.primarySoft —— 那是有色底：
    // 正文 / 副文字必须走 onColor / onColorSoft，否则原始主题（深 navy 底写深 navy 字，
    // primary 和 text 是同一个 #1A1A2E）与午夜蓝都会糊成一片。
    // 已读卡是中性卡底，沿用 text / textSecondary / textTertiary。
    final Color? unreadFill = item.isUnread ? palette.primarySoft : null;
    final Color titleColor =
        unreadFill == null ? palette.text : palette.onColor(unreadFill);
    final Color bodyColor =
        unreadFill == null ? palette.textSecondary : palette.onColorSoft(unreadFill);
    final Color metaColor =
        unreadFill == null ? palette.textTertiary : palette.onColorSoft(unreadFill);
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      highlight: item.isUnread,
      onTap: () => _handleOpen(item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: color.withValues(alpha: 0.12),
              shape: AppShape.all(AppRadius.md),
            ),
            child: Icon(_iconFor(item.type), size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: item.isUnread ? FontWeight.w600 : FontWeight.w400,
                    color: titleColor,
                  ),
                ),
                if (item.body != null && item.body!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.body!,
                    style: TextStyle(fontSize: AppFontSize.xs, color: bodyColor),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  relativeDayTime(item.createdAt),
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: metaColor,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
            ),
          ),
          if (item.isUnread) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: PulseDot(color: palette.danger),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(NotifyType? type) {
    switch (type) {
      case NotifyType.checkinPending:
        return Icons.schedule;
      case NotifyType.approved:
        return Icons.check_circle_outline;
      case NotifyType.rejected:
        return Icons.cancel_outlined;
      case NotifyType.resubmitted:
        return Icons.refresh;
      case NotifyType.recorded:
        return Icons.edit_outlined;
      case NotifyType.payout:
        return Icons.card_giftcard;
      case null:
        return Icons.notifications_none;
    }
  }

  static Color _colorFor(AppPalette palette, NotifyType? type) {
    switch (type) {
      case NotifyType.approved:
      case NotifyType.recorded:
      case NotifyType.payout:
        return palette.success;
      case NotifyType.rejected:
        return palette.danger;
      case NotifyType.checkinPending:
      case NotifyType.resubmitted:
        return palette.warning;
      case null:
        return palette.textSecondary;
    }
  }
}

/// 通知列表的骨架屏：一张卡 = 32×32 图标块 + 「标题 / 正文 / 时间」三行，
/// 形状照着 [_NotificationsPageState._buildItem] 摆 —— 加载完不会「跳」一下。
class _NotifySkeleton extends StatelessWidget {
  const _NotifySkeleton();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppTopBar.contentInset(context),
        AppSpacing.md,
        AppSpacing.lg + AppNavBar.contentInset(context),
      ),
      children: <Widget>[
        for (int i = 0; i < 4; i++)
          EnterBox(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: ShapeDecoration(
                  // 骨架屏只在加载的那一两秒出现，用实色卡底即可
                  color: palette.surface,
                  shape: AppShape.all(AppRadius.lg, side: BorderSide(color: palette.border)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SkeletonBox(width: 32, height: 32, radius: AppRadius.md),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SkeletonLine(widthFactor: 0.5),
                          SizedBox(height: AppSpacing.sm),
                          SkeletonLine(widthFactor: 0.86, height: 12),
                          SizedBox(height: AppSpacing.sm),
                          SkeletonLine(widthFactor: 0.26, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

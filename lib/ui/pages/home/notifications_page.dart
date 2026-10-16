import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/models/notification_record.dart';
import '../../../state/family_state.dart';
import '../../../state/notification_state.dart';
import '../../../state/settings_state.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../shell/main_shell.dart';
import '../../widgets/app_card.dart';
import '../../widgets/state_views.dart';

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
  /// 筛选（全部 / 未读）**不存字段** —— 唯一真相是地址栏的 `filter` 查询参数，
  /// 在 `build` 里派生（见 [_goFilter] 的写入侧）。

  /// 已经发起过加载的信箱 —— 身份变了要换一格重新拉
  NotifyAudience? _loadedAudience;

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
      _toast('已全部标记为已读');
    } catch (_) {
      if (!mounted) return;
      _toast('没能全部已读，请稍后重试', error: true);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    final palette = context.palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? palette.danger : null,
      ),
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

    // 筛选状态的唯一真相：地址栏 `/home/notifications?filter=all|unread`（缺省 all）。
    // 非法值（手输 / 旧链接）一律回落到 all。
    final String rawFilter = GoRouterState.of(context).uri.queryParameters['filter'] ?? '';
    final String filter =
        const <String>{'all', 'unread'}.contains(rawFilter) ? rawFilter : 'all';
    final bool unreadOnly = filter == 'unread';

    final visible = unreadOnly
        ? items.where((item) => item.isUnread).toList(growable: false)
        : items;

    final who = audience == NotifyAudience.parent
        ? '${settings.kidName}的打卡动态'
        : '${settings.momName}说的话';
    final suffix = state.unreadCount > 0 ? ' · ${state.unreadCount} 条未读' : ' · 都看过了';

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(palette, who + suffix, state.unreadCount),
            if (!state.ready && !state.loading)
              _buildNotice(
                palette,
                '通知功能还没就绪（服务端通知表尚未创建），等家长执行一次数据库迁移就会出现。',
              ),
            if (state.error != null && items.isNotEmpty) _buildRefreshFailedBar(palette),
            if (items.isNotEmpty) _buildFilter(palette, state.unreadCount, unreadOnly),
            Expanded(child: _buildBody(palette, state, visible, unreadOnly)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppPalette palette, String subtitle, int unreadCount) {
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
          IconButton(
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
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: palette.textSecondary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: unreadCount == 0 || _markingAll ? null : _handleMarkAll,
            child: _markingAll
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
                  )
                : const Text('全部已读'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice(AppPalette palette, String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: palette.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshFailedBar(AppPalette palette) {
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
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off, size: 14, color: palette.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '通知没刷新成功，下面是上次看到的内容',
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
            ),
          ),
          TextButton(
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
  /// 选中态由 URL 派生，所以这里不再 setState。
  void _goFilter(String filter) {
    context.go('/home/notifications?filter=$filter');
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
    return Material(
      color: selected ? palette.segmentedSelected : palette.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: selected ? palette.primary : palette.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.xs,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? palette.primary : palette.textSecondary,
              fontFeatures: kTabularNumbers,
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
      return const LoadingView(message: '正在读取通知…');
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        itemCount: visible.length,
        itemBuilder: (context, index) => _buildItem(palette, visible[index]),
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
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
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
                    color: palette.text,
                  ),
                ),
                if (item.body != null && item.body!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.body!,
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _relativeTime(item.createdAt),
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: palette.textTertiary,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
            ),
          ),
          if (item.isUnread) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              decoration: BoxDecoration(color: palette.danger, shape: BoxShape.circle),
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

  /// 相对时间（对着 Web 版的时间显示口径；超过一周就直接写日期）
  static String _relativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}

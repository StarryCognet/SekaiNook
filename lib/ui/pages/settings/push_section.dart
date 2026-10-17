import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_constants.dart';
import '../../../core/api_exception.dart';
import '../../../data/api/push_api.dart';
import '../../../data/models/notification_record.dart';
import '../../../state/family_state.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_widgets.dart';

/// 「设置 → 手机提醒」区块（对应 Web 版设置页里的同一块）。
///
/// 这块只讲清两件事，再留一个动作：
/// - 想收到提醒，得先在**网站 / PWA** 里订阅一次（iPhone 还要先「添加到主屏幕」）；
/// - 这个 App 还不能直接收 Web Push（本地通知没接），所以按钮的作用是
///   「给已经订阅过的手机发一条测试通知」，确认提醒通道通不通。
///
/// 提示样式不在本文件里另起一套：[onToast] 由设置页把它自己的 SnackBar
/// （`_toast`）传进来，全页只有一种提示。
class PushSection extends StatefulWidget {
  const PushSection({super.key, required this.onToast});

  /// 结果提示；[error] 为真时按危险色显示（发送失败、以及「一台都没订阅」都走它）
  final void Function(String message, bool error) onToast;

  @override
  State<PushSection> createState() => _PushSectionState();
}

class _PushSectionState extends State<PushSection> {
  late final PushApi _api = PushApi();

  /// 正在发：按钮置灰防连点（服务端有冷却，连点只会再换回一条 429）
  bool _sending = false;

  /// 身份 → 订阅分组。[FamilyRole] 只有家长 / 小孩两种，身份还没选出来时返回
  /// null —— 那时**不传** `audience`，等于发给所有已订阅设备。
  NotifyAudience? _audienceOf(FamilyRole? role) {
    switch (role) {
      case FamilyRole.parent:
        return NotifyAudience.parent;
      case FamilyRole.child:
        return NotifyAudience.child;
      case null:
        return null;
    }
  }

  /// 这一次会发给谁（只用于说明文案，与 [_audienceOf] 同一套口径）
  String _targetLabel(FamilyRole? role) {
    switch (role) {
      case FamilyRole.parent:
        return '已订阅的家长手机';
      case FamilyRole.child:
        return '已订阅的孩子手机';
      case null:
        return '所有已订阅的手机';
    }
  }

  Future<void> _send() async {
    final NotifyAudience? audience = _audienceOf(context.read<FamilyState>().role);
    setState(() => _sending = true);
    try {
      final PushTestResult result = await _api.sendTest(audience: audience);
      if (!mounted) return;
      // 正文直接用服务端的 detail：它把「送达几台、清理几条」写清楚了
      final String message = result.detail.isEmpty
          ? (result.sent ? '测试通知已经发出去了' : '还没有手机订阅，一条都没发出去')
          : result.detail;
      // sent == false 是「还没有设备订阅」这类要用户去处理的状态，按提醒显示
      widget.onToast(message, !result.sent);
    } on ApiException catch (error) {
      if (!mounted) return;
      widget.onToast(pushTestErrorMessage(error), true);
    } finally {
      // 成功、失败、或者中途没了 context：按钮都不能一直停在「发送中…」
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final FamilyRole? role = context.watch<FamilyState>().role;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: '手机提醒', subtitle: '任务没做完时，提前半小时提醒。'),
        EnterBox(
          index: 0,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _PushHead(
                  title: '怎么才能收到',
                  description: '提醒走的是浏览器推送，得先在手机上订阅一次；订阅入口在网站上，不在这个 App 里。',
                ),
                const SizedBox(height: AppSpacing.sm),
                _PushBullet(text: '在手机上打开 ${AppConstants.apiBase}，进「设置 → 手机提醒」，把开关打开。'),
                const _PushBullet(
                  text: 'iPhone 要先在 Safari 里点「分享 → 添加到主屏幕」，再从主屏上那个图标进去开（Safari 标签页里开不了）。',
                ),
                const _PushBullet(text: '订阅过的手机，任务没做完时会提前半小时收到提醒。'),
              ],
            ),
          ),
        ),
        EnterBox(
          index: 1,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _PushHead(
                  title: '发一条测试通知',
                  description:
                      '这个 App 还不能直接收 Web Push（本地通知没接），所以这里只替已经订阅过的手机试一下通道：手机真收到了，就说明提醒是通的。',
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '这次会发给${_targetLabel(role)}；刚发过要等一会儿才能再发。',
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: Text(_sending ? '发送中…' : '发一条测试通知'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 卡片小标题：字号 / 颜色与设置页其它卡片一致（那边的同名件是页面私有件）
class _PushHead extends StatelessWidget {
  const _PushHead({required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: AppFontSize.md,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
        if (description != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            description!,
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// 一条带圆点的说明。圆点尺寸就是 [AppSpacing.xs]，不另写 px。
class _PushBullet extends StatelessWidget {
  const _PushBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, right: AppSpacing.sm),
            child: Container(
              width: AppSpacing.xs,
              height: AppSpacing.xs,
              decoration: BoxDecoration(color: palette.textTertiary, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

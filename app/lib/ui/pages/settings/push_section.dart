import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_constants.dart';
import '../../../core/api_exception.dart';
import '../../../data/api/push_api.dart';
import '../../../data/models/local_reminder.dart';
import '../../../data/models/notification_record.dart';
import '../../../state/family_state.dart';
import '../../../state/local_notify_state.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_widgets.dart';
import 'reminder_list.dart';

/// 「设置 → 手机提醒」区块。
///
/// 提醒有**两条独立通道**，这块把两条都摆出来，别让用户以为只有一种：
///
/// 1. **App 自己提醒（本地通知）**：装了 App 的手机由 App 排程系统通知，
///    不依赖网络、不依赖订阅 —— 安卓上就是这个。
/// 2. **浏览器推送（Web Push）**：由服务端 Worker 在 21:30 推给网站 / PWA，
///    手机得先在网站上订阅一次（iPhone 还要先「添加到主屏幕」）。
///
/// 两条都开着的设备会各响一次，所以文案里写明了「装了 App 就用上面这个」。
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

  /// 正在发（服务端推送）：按钮置灰防连点（服务端有冷却，连点只会再换回一条 429）
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

  /// 把状态层刚写下的结果提示捞出来显示，然后清掉（避免下次进页面又弹一遍）
  void _flushMessage(LocalNotifyState state) {
    final String? message = state.message;
    if (message == null) return;
    widget.onToast(message, !state.enabled && !state.permissionGranted);
    state.clearMessage();
  }

  Future<void> _localEnable() async {
    final LocalNotifyState state = context.read<LocalNotifyState>();
    await state.enable();
    if (!mounted) return;
    setState(() {});
    _flushMessage(state);
  }

  Future<void> _localDisable() async {
    final LocalNotifyState state = context.read<LocalNotifyState>();
    await state.disable();
    if (!mounted) return;
    setState(() {});
    _flushMessage(state);
  }

  Future<void> _localTest() async {
    final LocalNotifyState state = context.read<LocalNotifyState>();
    await state.sendTest();
    if (!mounted) return;
    setState(() {});
    _flushMessage(state);
  }

  Future<void> _setExact(bool value) async {
    final LocalNotifyState state = context.read<LocalNotifyState>();
    await state.setExactMode(value);
    if (!mounted) return;
    setState(() {});
    _flushMessage(state);
  }

  /// 通知预览挑哪一条：开着、有排上、且最快会响的那条（列表里各有各的，
  /// 这张卡只展示「下一条要弹的通知长什么样」）
  LocalReminder? _previewReminder(LocalNotifyState local) {
    LocalReminder? best;
    DateTime? earliest;
    for (final LocalReminder reminder in local.activeReminders) {
      if (local.scheduledTextFor(reminder) == null) continue;
      final DateTime? at = local.nextFireAtFor(reminder);
      final bool earlier = at != null && (earliest == null || at.isBefore(earliest));
      if (best == null || earlier) {
        best = reminder;
        if (at != null) earliest = at;
      }
    }
    return best;
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
    final LocalNotifyState local = context.watch<LocalNotifyState>();
    final LocalReminder? preview = _previewReminder(local);
    // 状态层把文案拼成「标题\n正文」，这里拆开按通知栏的两级样式显示
    final String previewText =
        preview == null ? '' : (local.scheduledTextFor(preview) ?? '');
    final int previewCut = previewText.indexOf('\n');

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
                  title: '这个 App 自己提醒（本地通知）',
                  description: '装了 App 的手机由 App 自己排系统通知：不用开网页、不用订阅，'
                      '每天 21:30 提醒今天还差几个任务。',
                ),
                const SizedBox(height: AppSpacing.sm),
                _StatusRow(
                  palette: palette,
                  label: '当前状态',
                  value: _localStatusText(local),
                  tone: local.enabled ? _Tone.good : _Tone.plain,
                ),
                if (local.enabled && local.nextFireAt != null)
                  _StatusRow(
                    palette: palette,
                    label: '下次提醒',
                    value: _fireAtText(local.nextFireAt!),
                    tone: _Tone.plain,
                  ),
                if (local.enabled && preview != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  _PreviewBox(
                    palette: palette,
                    title: previewCut < 0
                        ? previewText
                        : previewText.substring(0, previewCut),
                    body: previewCut < 0 ? '' : previewText.substring(previewCut + 1),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                if (!local.supported)
                  Text(
                    '网页版不支持这个（网页请用下面那张卡的浏览器推送）。'
                    '装安卓 App 之后，这里就能直接开。',
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.textSecondary,
                      height: 1.5,
                    ),
                  )
                else ...<Widget>[
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      if (!local.enabled)
                        FilledButton(
                          onPressed: local.busy ? null : _localEnable,
                          child: const Text('开启本地提醒'),
                        )
                      else
                        OutlinedButton(
                          onPressed: local.busy ? null : _localDisable,
                          child: const Text('关掉本地提醒'),
                        ),
                      OutlinedButton(
                        onPressed: local.busy ? null : _localTest,
                        child: const Text('发一条本地测试通知'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '文案按「最后一次打开 App 时」的完成数算；做完 5 个任务后这条提醒会自动撤掉。',
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.textTertiary,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        ReminderList(onToast: widget.onToast, index: 1),
        EnterBox(
          index: 2,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: _PushHead(
                        title: '准时模式',
                        description: '提醒是交给系统闹钟排的，响得准不准就看这个开关。',
                      ),
                    ),
                    Switch.adaptive(
                      value: local.exactMode,
                      onChanged: local.busy ? null : _setExact,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _ModeLine(
                  text: '关（默认）：省电，到点可能晚几分钟',
                  active: !local.exactMode,
                ),
                _ModeLine(
                  text: '开：到点就响，更耗电；安卓 12+ 需要你在系统里允许「闹钟和提醒」',
                  active: local.exactMode,
                ),
                if (local.exactMode && !local.exactGranted) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '系统里没给「闹钟和提醒」权限 —— 现在还是按省电的方式排，到点可能晚几分钟。'
                    '去手机「设置 → 应用 → 特殊权限」里允许一下。',
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: palette.warningInk,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        EnterBox(
          index: 3,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _PushHead(
                  title: '划掉后台也会响吗？',
                  description: '会 —— 但有两种情况例外，先看清楚，免得以为没排上。',
                ),
                const SizedBox(height: AppSpacing.sm),
                const _PushBullet(
                  text: '提醒不是 App 自己盯着时间弹的，是交给系统闹钟排的：划掉后台、锁屏、甚至重启手机都照样响（重启后由系统恢复）。',
                ),
                const _PushBullet(
                  text: '在系统设置里对 App 点过「强行停止」，或者卸载重装，排好的提醒会被清掉 —— 重新打开一次 App 就会自动重排。',
                ),
                const _PushBullet(
                  text: '想让卸载 App 之后也照样收到，只能用上面那张卡的浏览器推送（网站订阅），本地通知做不到。',
                ),
              ],
            ),
          ),
        ),
        EnterBox(
          index: 4,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _PushHead(
                  title: '在网站上订阅（浏览器推送）',
                  description: '不想装 App 的手机（比如 iPhone）走这条：提醒由服务器推给浏览器，'
                      '得先在手机上订阅一次，订阅入口在网站上。',
                ),
                const SizedBox(height: AppSpacing.sm),
                _PushBullet(text: '在手机上打开 ${AppConstants.apiBase}，进「设置 → 手机提醒」，把开关打开。'),
                const _PushBullet(
                  text: 'iPhone 要先在 Safari 里点「分享 → 添加到主屏幕」，再从主屏上那个图标进去开（Safari 标签页里开不了）。',
                ),
                const _PushBullet(
                  text: '两条通道同时开着的手机，到点会各响一次 —— 装了 App 的安卓机建议只留上面那条。',
                ),
              ],
            ),
          ),
        ),
        EnterBox(
          index: 5,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _PushHead(
                  title: '给已订阅的手机发一条测试通知',
                  description: '这条走服务端推送，测的是网站订阅那条通道：手机真收到了，说明浏览器推送是通的。',
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

  String _localStatusText(LocalNotifyState local) {
    if (!local.supported) return '这个平台不支持';
    if (!local.enabled) return '还没开启';
    if (!local.permissionGranted) return '已开启，但系统里通知权限是关的';
    if (local.nextFireAt == null) return '已开启 · 今天任务已做完，不再提醒';
    return '已开启 · 每天 21:30';
  }

  /// 「下次提醒」显示成 `10/17 21:30`（北京墙钟时间，不带时区后缀）
  String _fireAtText(DateTime when) {
    final String mm = when.month.toString().padLeft(2, '0');
    final String dd = when.day.toString().padLeft(2, '0');
    final String hh = when.hour.toString().padLeft(2, '0');
    final String mi = when.minute.toString().padLeft(2, '0');
    return '$mm/$dd $hh:$mi';
  }
}

/// 状态行的语气：正常 / 已完成（绿）/ 中性
enum _Tone { plain, good }

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.palette,
    required this.label,
    required this.value,
    required this.tone,
  });

  final AppPalette palette;
  final String label;
  final String value;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                fontWeight: FontWeight.w600,
                color: tone == _Tone.good ? palette.successInk : palette.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 下次通知的文案预览（用通知栏的样式：粗标题 + 细正文）
class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.palette, required this.title, required this.body});

  final AppPalette palette;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: ShapeDecoration(
        color: palette.softColor(hasBackground: false),
        shape: AppShape.all(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '通知会长这样',
            style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            style: TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
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

/// 准时模式的两行代价说明：当前生效的那行点亮，另一行灰着
class _ModeLine extends StatelessWidget {
  const _ModeLine({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color color = active ? palette.primaryInk : palette.textTertiary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs, right: AppSpacing.sm),
            child: Icon(
              active ? Icons.check_circle : Icons.radio_button_unchecked,
              size: AppFontSize.sm,
              color: color,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: color,
                height: 1.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

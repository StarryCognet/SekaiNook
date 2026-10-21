import 'package:sekainook_app/ui/icons/icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/local_reminder.dart';
import '../../../state/local_notify_state.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/motion_widgets.dart';
import 'reminder_editor_sheet.dart';
import '../../widgets/motion/app_buttons.dart';

/// 「设置 → 手机提醒」里的**提醒项列表**卡片。
///
/// 一行一条：名字 + 消息类型 + `每天 21:30` + 表现摘要 + 开关，
/// 下面挂「试一下 / 编辑 / 删除」；底部是「加一条提醒」与「恢复内置提醒」。
///
/// 提示不自己造一套：[onToast] 由 [PushSection] 把设置页的 SnackBar 传进来，
/// 每个操作完就看一眼 `state.message`（非空就弹一次并清掉）——与页面上其它
/// 按钮同一套口径。
class ReminderList extends StatefulWidget {
  const ReminderList({super.key, required this.onToast, this.index = 1});

  /// 结果提示；[error] 为真时按危险色显示
  final void Function(String message, bool error) onToast;

  /// 入场错峰的序号（卡片在整页里的位置）
  final int index;

  @override
  State<ReminderList> createState() => _ReminderListState();
}

class _ReminderListState extends State<ReminderList> {
  /// 把状态层刚写下的结果提示捞出来显示，然后清掉
  void _flush(LocalNotifyState state) {
    final String? message = state.message;
    if (message == null) return;
    widget.onToast(message, !state.enabled && !state.permissionGranted);
    state.clearMessage();
  }

  Future<void> _run(Future<void> Function(LocalNotifyState state) action) async {
    final LocalNotifyState state = context.read<LocalNotifyState>();
    await action(state);
    if (!mounted) return;
    _flush(state);
  }

  /// 新增（传 null）或编辑一条；面板关掉后统一弹它的回执
  Future<void> _edit(LocalReminder? reminder) async {
    final LocalNotifyState state = context.read<LocalNotifyState>();
    await showReminderEditorSheet(context, reminder: reminder);
    if (!mounted) return;
    _flush(state);
  }

  /// `10/18 21:30`（北京墙钟时间，不带时区后缀）
  static String _fireText(DateTime when) =>
      '${when.month.toString().padLeft(2, '0')}/${when.day.toString().padLeft(2, '0')} '
      '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';

  /// 这一条下次还响不响
  String _nextLabel(LocalNotifyState state, LocalReminder reminder) {
    if (!reminder.enabled) return '已关掉';
    final DateTime? at = state.nextFireAtFor(reminder);
    if (at == null) return '今天不会响（已完成 / 已过）';
    return '下一次 ${_fireText(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final LocalNotifyState state = context.watch<LocalNotifyState>();
    final List<LocalReminder> reminders = state.reminders;

    return EnterBox(
      index: widget.index,
      child: AppCard(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '我的提醒',
              style: TextStyle(
                fontSize: AppFontSize.md,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              state.supported
                  ? '提醒交给系统闹钟排：划掉后台、锁屏、重启手机都会响。每条可以单独设时间、文案和弹法。'
                  : '网页版不支持本地通知 —— 这里只存设置，装了安卓 App 之后才会响。',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (reminders.isEmpty)
              Text(
                '现在一条都没有，点下面加一条。',
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
              )
            else
              for (final LocalReminder reminder in reminders)
                _tile(state, reminder),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: AppOutlinedButton.icon(
                onPressed: state.busy ? null : () => _edit(null),
                icon: const GlyphIcon(AppIcons.add, size: AppFontSize.sm),
                label: const Text('加一条提醒'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '内置的两条（任务提醒 / 睡觉提醒）被改乱了可以恢复默认；你自己加的那几条不会被动。',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.textTertiary,
                height: 1.5,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton(
                onPressed: state.busy ? null : () => _run((s) => s.restoreBuiltins()),
                child: const Text('恢复内置提醒'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(LocalNotifyState state, LocalReminder reminder) {
    final AppPalette palette = context.palette;
    final bool canAct = !state.busy;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                            reminder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppFontSize.sm,
                              fontWeight: FontWeight.w600,
                              color: palette.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _KindTag(kind: reminder.kind),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${reminder.scheduleLabel} · ${_nextLabel(state, reminder)}',
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      reminder.style.summary,
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: reminder.enabled,
                onChanged: canAct
                    ? (bool value) => _run((s) => s.setReminderEnabled(reminder, value))
                    : null,
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              AppTextButton(
                onPressed: !canAct || !state.supported
                    ? null
                    : () => _run((s) => s.sendTest(reminder: reminder)),
                child: const Text('试一下'),
              ),
              AppTextButton(
                onPressed: canAct ? () => _edit(reminder) : null,
                child: const Text('编辑'),
              ),
              if (reminder.builtin)
                Text(
                  '内置提醒：可以关掉或改时间，删不掉',
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                )
              else
                AppTextButton(
                  onPressed: canAct ? () => _run((s) => s.removeReminder(reminder)) : null,
                  style: TextButton.styleFrom(foregroundColor: palette.dangerInk),
                  child: const Text('删除'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 消息类型标签（小胶囊）
class _KindTag extends StatelessWidget {
  const _KindTag({required this.kind});

  final ReminderKind kind;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: ShapeDecoration(
        color: palette.softColor(hasBackground: false),
        shape: AppShape.all(AppRadius.full),
      ),
      child: Text(
        kind.label,
        style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
      ),
    );
  }
}

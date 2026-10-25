import 'package:sekainook_app/fl_ui/dialog.dart';
import 'package:sekainook_app/ui/icons/icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/local_reminder.dart';
import '../../../state/local_notify_state.dart';
import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/format.dart';
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

  /// 危险动作的二次确认：与设置页同一个浮动弹窗（别处不要再拼一套 AlertDialog）
  Future<bool> _confirm({
    required String title,
    required String description,
    required String okText,
  }) async {
    final bool? result = await showFloatingDialog<bool>(
      context: context,
      child: Builder(
        builder: (BuildContext dialogContext) => CommonDialog(
          title: title,
          destructive: true,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(okText),
            ),
          ],
          child: Text(description),
        ),
      ),
    );
    return result ?? false;
  }

  /// 删一条：先问一句（以前点了就没了）
  Future<void> _remove(LocalReminder reminder) async {
    final bool ok = await _confirm(
      title: '删掉「${reminder.name}」？',
      description: '删掉之后这条就不会再响了；想再要得重新加一条。',
      okText: '删掉',
    );
    if (!ok || !mounted) return;
    await _run((s) => s.removeReminder(reminder));
  }

  /// 恢复内置两条：说清楚会覆盖改过的内置项
  Future<void> _restoreBuiltins() async {
    final bool ok = await _confirm(
      title: '恢复内置提醒？',
      description: '内置的两条会变回默认的时间与文案，你改过的地方会被覆盖。自己加的那几条不受影响。',
      okText: '恢复默认',
    );
    if (!ok || !mounted) return;
    await _run((s) => s.restoreBuiltins());
  }

  /// 时间走全站统一的格式（今天 / 昨天 / MM-dd HH:mm）
  static String _fireText(DateTime when) => formatDateTime(when);

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
              '提醒交给系统闹钟排：划掉后台、锁屏、重启手机都会响。每条可以单独设时间、文案和弹法。',
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
                onPressed: state.busy ? null : _restoreBuiltins,
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
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
                  onPressed: canAct ? () => _remove(reminder) : null,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.dangerInk,
                    minimumSize: const Size(0, 44),
                  ),
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

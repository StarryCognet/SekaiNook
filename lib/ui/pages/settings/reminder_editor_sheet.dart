import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/week.dart';
import '../../../data/models/local_reminder.dart';
import '../../../state/local_notify_state.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../widgets/motion_widgets.dart';

/// 打开「提醒」编辑面板（新增 / 编辑共用）。
///
/// 面板只负责**收集字段**，落盘与排程全交给 [LocalNotifyState]：
/// 保存后消息留在 `state.message` 里，由调用方按全页统一的口径弹出来
/// （见 `reminder_list.dart` 的 `_flush`）。
Future<void> showReminderEditorSheet(BuildContext context, {LocalReminder? reminder}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _ReminderEditorSheet(initial: reminder),
  );
}

class _ReminderEditorSheet extends StatefulWidget {
  const _ReminderEditorSheet({this.initial});

  /// 传了就是编辑这一条；不传是新增
  final LocalReminder? initial;

  @override
  State<_ReminderEditorSheet> createState() => _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends State<_ReminderEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _title =
      TextEditingController(text: widget.initial?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.initial?.body ?? '');

  late ReminderKind _kind = widget.initial?.kind ?? ReminderKind.custom;
  late int _hour = widget.initial?.hour ?? 20;
  late int _minute = widget.initial?.minute ?? 0;
  late ReminderRepeat _repeat = widget.initial?.repeat ?? ReminderRepeat.daily;
  late String? _onceDay = widget.initial?.onceDay;
  late ReminderStyle _style = widget.initial?.style ?? const ReminderStyle();

  /// 面板内的一次性回执（「试一下」的结果）——
  /// 底部弹层盖在页面上，SnackBar 会被挡在下面，所以就地显示。
  String? _note;

  /// 防连点：保存/测试按钮在跑的时候置灰
  bool _busy = false;

  bool get _isNew => widget.initial == null;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  String get _timeLabel =>
      '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

  /// 当前编辑中的值临时拼一条 [LocalReminder]，只用于「试一下」
  LocalReminder _draft() {
    final String name = _name.text.trim();
    final String title = _title.text.trim();
    return LocalReminder(
      slot: widget.initial?.slot ?? 99,
      id: widget.initial?.id ?? 'preview',
      name: name.isEmpty ? '试一下' : name,
      kind: _kind,
      hour: _hour,
      minute: _minute,
      repeat: _repeat,
      title: title.isEmpty ? 'SekaiNook 提醒' : title,
      body: _body.text.trim(),
      style: _style,
      onceDay: _repeat == ReminderRepeat.once ? _onceDay : null,
      builtin: widget.initial?.builtin ?? false,
    );
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _hour = picked.hour;
      _minute = picked.minute;
    });
  }

  /// 日期键固定成东八区口径的 `yyyy-MM-dd` —— 与 [LocalNotifyState.nextFireTimeFor]
  /// 解析 `onceDay` 的方式一致。这里**不能**用 [WeekUtil.beijingDayKey]：
  /// 那是拿「此刻」换算的，喂进一个选中的日期会被时区偏移推错一天。
  static String _dayKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Future<void> _pickDay() async {
    final DateTime beijing = WeekUtil.beijingNow();
    final DateTime today = DateTime(beijing.year, beijing.month, beijing.day);
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_onceDay ?? '') ?? today,
      firstDate: today,
      lastDate: DateTime(today.year + 1, today.month, today.day),
    );
    if (selected == null || !mounted) return;
    setState(() => _onceDay = _dayKey(selected));
  }

  Future<void> _test() async {
    final LocalNotifyState state = context.read<LocalNotifyState>();
    setState(() => _busy = true);
    await state.sendTest(reminder: _draft());
    if (!mounted) return;
    setState(() {
      _note = state.message;
      _busy = false;
    });
    state.clearMessage();
  }

  Future<void> _save() async {
    final LocalNotifyState state = context.read<LocalNotifyState>();
    final String name = _name.text.trim();
    final String title = _title.text.trim();
    final String? onceDay = _repeat == ReminderRepeat.once ? _onceDay : null;
    final LocalReminder? initial = widget.initial;

    setState(() => _busy = true);
    if (initial == null) {
      await state.addReminder(
        name: name.isEmpty ? null : name,
        kind: _kind,
        hour: _hour,
        minute: _minute,
        repeat: _repeat,
        title: title.isEmpty ? null : title,
        body: _body.text.trim(),
        style: _style,
        onceDay: onceDay,
      );
    } else {
      await state.updateReminder(initial.copyWith(
        name: name.isEmpty ? initial.name : name,
        kind: _kind,
        hour: _hour,
        minute: _minute,
        repeat: _repeat,
        title: title.isEmpty ? initial.title : title,
        body: _body.text.trim(),
        style: _style,
        onceDay: onceDay,
        // 从「只提醒一次」改成别的：把上一次选的日期清掉
        clearOnceDay: onceDay == null,
      ));
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.xs,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _isNew ? '加一条提醒' : '编辑提醒',
              style: TextStyle(
                fontSize: AppFontSize.lg,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '时间按你自己的手机算；到点由系统闹钟弹出来，划掉后台也会响。',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.textTertiary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _FieldLabel(text: '名称（最多 20 字）'),
            TextField(
              controller: _name,
              inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(20)],
              decoration: const InputDecoration(isDense: true, hintText: '比如：睡前收书包'),
            ),
            const SizedBox(height: AppSpacing.md),
            const _FieldLabel(text: '消息类型'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final ReminderKind kind in ReminderKind.values)
                  ChoiceChip(
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (bool selected) {
                      if (!selected) return;
                      setState(() => _kind = kind);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SlideFadeSwitcher(
              childKey: ValueKey<String>(_kind.wire),
              axis: Axis.vertical,
              child: Text(
                _kind.hint,
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _FieldLabel(text: '时间'),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickTime,
                icon: const Icon(Icons.schedule_outlined, size: AppFontSize.sm),
                label: Text(_timeLabel),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _FieldLabel(text: '重复'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final ReminderRepeat repeat in ReminderRepeat.values)
                  ChoiceChip(
                    label: Text(repeat.label),
                    selected: _repeat == repeat,
                    onSelected: (bool selected) {
                      if (!selected) return;
                      setState(() {
                        _repeat = repeat;
                        // 第一次切到「只提醒一次」：默认给今天（东八区）
                        if (repeat == ReminderRepeat.once && _onceDay == null) {
                          _onceDay = _dayKey(WeekUtil.beijingNow());
                        }
                      });
                    },
                  ),
              ],
            ),
            if (_repeat == ReminderRepeat.once) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickDay,
                    icon: const Icon(Icons.event_outlined, size: AppFontSize.sm),
                    label: Text(_onceDay ?? '选日期'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '只在这一天响一次，响完自动关掉。',
                      style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const _FieldLabel(text: '标题（最多 40 字）'),
            TextField(
              controller: _title,
              inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(40)],
              decoration: const InputDecoration(isDense: true, hintText: '通知上那行粗字'),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _FieldLabel(text: '正文（最多 120 字）'),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 5,
              inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(120)],
              decoration: const InputDecoration(hintText: '通知里那句话，可以换行'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '可用占位符：{done} 已完成数、{remaining} 还差几个、{total} 目标数、{day} 日期',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: palette.textTertiary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _FieldLabel(text: '弹出来的时候'),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _StyleToggle(
                label: '声音',
                desc: '有提示音',
                value: _style.sound,
                onChanged: (bool value) => setState(() => _style = _style.copyWith(sound: value)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _StyleToggle(
                label: '震动',
                desc: '手机会震一下',
                value: _style.vibrate,
                onChanged: (bool value) =>
                    setState(() => _style = _style.copyWith(vibrate: value)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _StyleToggle(
                label: '悬浮横幅',
                desc: '顶部弹出来那一条；关掉就只进通知栏',
                value: _style.headsUp,
                onChanged: (bool value) =>
                    setState(() => _style = _style.copyWith(headsUp: value)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _StyleToggle(
                label: '锁屏显示内容',
                desc: '关掉的话，锁屏上只显示「有一条通知」',
                value: _style.lockscreenVisible,
                onChanged: (bool value) =>
                    setState(() => _style = _style.copyWith(lockscreenVisible: value)),
              ),
            ),
            if (_note != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _note!,
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: palette.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                OutlinedButton(
                  onPressed: _busy ? null : _test,
                  child: const Text('试一下这条'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_isNew ? '保存' : '保存修改'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 字段小标题（字号 / 颜色与设置页其它小字一致）
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
      ),
    );
  }
}

/// 一个「表现」开关：左边标签 + 一句说明，右边开关
class _StyleToggle extends StatelessWidget {
  const _StyleToggle({
    required this.label,
    required this.desc,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: TextStyle(fontSize: AppFontSize.sm, color: palette.text)),
              Text(
                desc,
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: palette.textTertiary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}

import 'package:sekainook_app/ui/icons/icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/theme_state.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'motion_widgets.dart';

/// 任务行在列表里的三种状态（对应 `docs/task-area-layout.html` 的「四状态」，
/// 其中「待做」与「现在可做」在这里合成 [ready]，靠配色强弱区分）。
enum TaskRowState {
  /// 能做：时间窗内、又没做满（不限次的任务永远是这个）
  ready,

  /// 此刻不能做：还没到时间窗 / 已经过了时间窗，原因写在 `meta` 里
  later,

  /// 今天已经做满
  done,
}

/// 全站统一的任务行：图标块 + 名称 + 一行元信息 + 分值 + 状态圈。
///
/// **为什么不是按钮**：任务区一屏十几条，用实色 [FilledButton] 会把它们喊成同一音量
/// （12 个平级动作），颜色也就从「信息」退化成「块的形状」。清单语法里动作由
/// 「整行可点 + 状态圈」承担，颜色只负责标注语义 —— 红涨绿跌的含义反而更清楚了。
///
/// 三种状态共用一套骨架，差异只在底色 / 描边 / 状态圈 / 文字深浅。
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.name,
    required this.icon,
    required this.earning,
    required this.state,
    this.value,
    this.meta,
    this.metaIcon,
    this.onTap,
    this.compact = false,
  });

  /// 任务名（一行，放不下就省略号）
  final String name;

  final Glyph icon;

  /// 赚积分（true）/ 扣积分（false）—— 决定这一行用绿还是红
  final bool earning;

  final TaskRowState state;

  /// 分值文案，如 `+10` / `-10`；null = 不显示
  final String? value;

  /// 元信息（时间窗 / 日限 / 说明），最多一行
  final String? meta;

  /// 元信息前的小图标
  final Glyph? metaIcon;

  /// 整行可点；null = 这一行现在点不动（已做满 / 没到时间窗 / 正在提交）
  final VoidCallback? onTap;

  /// 紧凑版：家长端管理列表里用，行高矮一点
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bool hasBackground =
        context.select<ThemeState, bool>((state) => state.background.isNotEmpty);
    final Color accent = earning ? palette.success : palette.danger;
    final Color cardFill = palette.cardColor(hasBackground: hasBackground);
    final Color softFill = palette.softColor(hasBackground: hasBackground);

    final bool tappable = onTap != null;
    final bool emphasize = state == TaskRowState.ready && tappable;
    final bool dimmed = state != TaskRowState.ready;
    final bool filled = state == TaskRowState.ready;

    final Color fill = filled
        ? Color.alphaBlend(accent.withValues(alpha: 0.07), cardFill)
        : softFill;
    final Color borderColor = emphasize
        ? accent.withValues(alpha: 0.35)
        : state == TaskRowState.done
            ? Colors.transparent
            : palette.border;

    // 图标块底 = 语义色 12% 盖在这一行的底色上；图标本身走 ink()：
    // 直接拿 success / danger 当字色在浅底上对比度不够（出厂 warning 只有 1.7:1）
    final Color iconFill = Color.alphaBlend(accent.withValues(alpha: 0.12), fill);
    final Color iconColor = palette.ink(accent, iconFill);
    final Color titleColor = dimmed ? palette.textSecondary : palette.text;
    final Color valueColor = dimmed ? palette.textTertiary : palette.ink(accent, fill);

    // 超椭圆（不是普通圆角）：这里半径只有 12，普通圆角在直线与圆弧的相接处
    // 会有一个能看出来的折点，超椭圆整条边曲率连续。
    final RoundedSuperellipseBorder shape = AppShape.all(AppRadius.md);

    return Material(
      color: fill,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      // 底色在 Material 上、描边在内层容器上 —— 与 AppCard 同一套分工，
      // 否则水波纹会被底色压住看不见
      child: PressInkWell(
        onTap: tappable ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          constraints: BoxConstraints(minHeight: compact ? 48 : 56),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: ShapeDecoration(
            shape: AppShape.all(AppRadius.md, side: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: ShapeDecoration(
                  color: iconFill,
                  shape: AppShape.all(AppRadius.sm),
                ),
                child: GlyphIcon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    if (meta != null && meta!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Row(
                          children: <Widget>[
                            if (metaIcon != null) ...<Widget>[
                              GlyphIcon(metaIcon!, size: 12, color: palette.textTertiary),
                              const SizedBox(width: AppSpacing.xs),
                            ],
                            Flexible(
                              child: Text(
                                meta!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppFontSize.xs,
                                  color: palette.textTertiary,
                                  fontFeatures: kTabularNumbers,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  value!,
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                    fontFeatures: kTabularNumbers,
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.sm),
              _statusDot(palette: palette, accent: accent, hasBackground: hasBackground),
            ],
          ),
        ),
      ),
    );
  }

  /// 右侧状态圈：空圈 = 可以打卡；时钟 = 没到时间；对勾 = 今天做满了。
  Widget _statusDot({
    required AppPalette palette,
    required Color accent,
    required bool hasBackground,
  }) {
    const double size = 24;
    switch (state) {
      case TaskRowState.ready:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
          ),
        );
      case TaskRowState.later:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.alphaBlend(
              palette.textTertiary.withValues(alpha: 0.12),
              palette.surface,
            ),
          ),
          child: GlyphIcon(AppIcons.clock, size: 14, color: palette.textTertiary),
        );
      case TaskRowState.done:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.alphaBlend(
              accent.withValues(alpha: 0.15),
              palette.cardColor(hasBackground: hasBackground),
            ),
          ),
          child: GlyphIcon(AppIcons.check, size: 16, color: palette.ink(accent)),
        );
    }
  }
}

/// 任务图标：按任务 id 给一个能看懂的图标。
///
/// 原来 12 条任务共用 `AppIcons.add` / `AppIcons.remove` 两个图标，扫一眼分不出哪条是哪条；
/// 图标本身也是「这是什么事」的最快线索。
Glyph taskIconFor(String taskId, {bool earning = true}) {
  switch (taskId) {
    case 'clean_room':
      return AppIcons.broom;
    case 'wash_dishes':
      return AppIcons.meal;
    case 'do_laundry':
      return AppIcons.laundry;
    case 'take_out_trash':
      return AppIcons.delete;
    case 'finish_homework':
      return AppIcons.compose;
    case 'read_book':
      return AppIcons.book;
    case 'sleep_on_time':
      return AppIcons.moon;
    case 'ipad_time':
      return AppIcons.devices;
    case 'phone_time':
      return AppIcons.devices;
    case 'eye_penalty':
      return AppIcons.eyeOff;
    case 'sleep_penalty':
      return AppIcons.alarmOff;
    case 'homework_incomplete':
      return AppIcons.assignment;
    default:
      return earning ? AppIcons.star : AppIcons.removeCircle;
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/theme_state.dart';
import '../../theme/app_shape.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'motion_widgets.dart';

/// 全站统一的卡片。
///
/// 有全局背景图时用半透明玻璃底（[AppPalette.surfaceGlass]），
/// 没有背景图时用实色（[AppPalette.surface]）—— 由 [ThemeState.background] 决定。
///
/// 可点的卡片带按压缩放（[PressInkWell]）与描边高亮：按下时边框转主色，
/// 松手弹回原状 —— 手机上「点得动」比水波纹更明确。
///
/// 底色画在 [Material] 上、边框画在里面的 [AnimatedContainer] 上：
/// 水波纹属于 Material，若底色压在它上面就看不见了。
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.onLongPress,
    this.margin,
    this.borderRadius,
    this.highlight = false,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  /// 强调卡片（主色细边 + 淡主色底），用于「今天最该做的那件事」
  final bool highlight;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasBackground = context.select<ThemeState, bool>((state) => state.background.isNotEmpty);
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadius.lg);
    final bool emphasize = widget.highlight || _pressed;

    final Color fill = widget.highlight
        ? palette.primarySoft
        : palette.cardColor(hasBackground: hasBackground);

    // 只画边框与内边距；底色交给外层 Material（水波纹要浮在底色之上）
    final Widget inner = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      padding: widget.padding,
      // 超椭圆描边：ShapeDecoration 而不是 BoxDecoration —— 后者只吃
      // BorderRadius，画出来是普通圆角，和全站其余形状对不上。
      decoration: ShapeDecoration(
        shape: AppShape.of(
          radius,
          side: BorderSide(
            color: emphasize ? palette.primary : palette.border,
            width: widget.highlight ? 1.5 : 1,
          ),
        ),
      ),
      child: widget.child,
    );

    final bool tappable = widget.onTap != null || widget.onLongPress != null;

    return Padding(
      padding: widget.margin ?? EdgeInsets.zero,
      child: Material(
        color: fill,
        shape: AppShape.of(radius),
        clipBehavior: Clip.antiAlias,
        child: !tappable
            ? inner
            : PressInkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                borderRadius: radius,
                onHighlightChanged: (bool value) => setState(() => _pressed = value),
                child: inner,
              ),
      ),
    );
  }
}

/// 区块标题（左标题 + 右附加信息）
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 3,
            height: 16,
            margin: const EdgeInsets.only(right: AppSpacing.sm),
            decoration: ShapeDecoration(
              color: palette.primary,
              shape: AppShape.all(AppRadius.full),
            ),
          ),
          Expanded(
            child: Column(
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
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 带数字的统计块（积分、天数这类）
///
/// 传 [number] 时数字会滚动（[AnimatedCount]），传 [value] 则原样显示文字。
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.label,
    this.value,
    this.number,
    this.formatter,
    this.unit,
    this.color,
    this.icon,
  });

  final String label;
  final String? value;

  /// 会滚动的数值（优先级高于 [value]）
  final num? number;
  final String Function(num value)? formatter;
  final String? unit;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final TextStyle numberStyle = TextStyle(
      fontSize: AppFontSize.xl,
      fontWeight: FontWeight.w700,
      color: color ?? palette.text,
      fontFeatures: kTabularNumbers,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: palette.textTertiary),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            if (number != null)
              AnimatedCount(value: number!, style: numberStyle, formatter: formatter)
            else
              Text(value ?? '', style: numberStyle),
            if (unit != null) ...<Widget>[
              const SizedBox(width: 2),
              Text(
                unit!,
                style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

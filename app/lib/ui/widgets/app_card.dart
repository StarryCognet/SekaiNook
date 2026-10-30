import 'package:sekainook_app/ui/icons/icons.dart';
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
    // P5R 的卡片是方角纸片（[P5rSkin]）；其它主题保持 lg 超椭圆圆角。
    final P5rSkin? p5r = Theme.of(context).extension<P5rSkin>();
    final radius =
        widget.borderRadius ?? BorderRadius.circular(p5r == null ? AppRadius.lg : P5rSkin.corner);
    final double edgeWidth = p5r == null ? 1 : P5rSkin.edge;
    final Color edgeColor = p5r == null ? palette.border : p5r.edgeColor;
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
            color: emphasize ? palette.primary : edgeColor,
            width: widget.highlight ? edgeWidth + 0.5 : edgeWidth,
          ),
        ),
      ),
      child: widget.child,
    );

    final bool tappable = widget.onTap != null || widget.onLongPress != null;

    final Widget card = Material(
      color: fill,
      shape: AppShape.of(radius),
      // **不要裁剪**：按压缩放（[PressInkWell] 的 AnimatedScale）会把描边胀到
      // 卡片边界之外几个像素，`Clip.antiAlias` 会把那一圈切掉 —— 表现出来就是
      // 「按下时看不出描边转主色」。水波纹已在 `app_theme.dart` 里关掉
      // （`NoSplash.splashFactory`），所以不需要靠这里裁 splash。
      clipBehavior: Clip.none,
      child: !tappable
          ? inner
          : PressInkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              borderRadius: radius,
              onHighlightChanged: (bool value) => setState(() => _pressed = value),
              child: inner,
            ),
    );

    // P5R：纸片是「叠」在底上的 —— 右下 4px 无模糊硬投影。阴影会画到卡片边界外，
    // 所以留 4px 内边距，免得被外层 Column/ListView 裁掉。
    final Widget body = p5r == null
        ? card
        : Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 4),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: AppShape.of(radius),
                shadows: p5r.hardShadow,
              ),
              child: card,
            ),
          );

    return Padding(padding: widget.margin ?? EdgeInsets.zero, child: body);
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
  final Glyph? icon;

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
              GlyphIcon(icon!, size: 14, color: palette.textTertiary),
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

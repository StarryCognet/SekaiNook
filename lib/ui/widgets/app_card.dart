import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/theme_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// 全站统一的卡片。
///
/// 有全局背景图时用半透明玻璃底（[AppPalette.surfaceGlass]），
/// 没有背景图时用实色（[AppPalette.surface]）—— 由 [ThemeState.background] 决定。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.margin,
    this.borderRadius,
    this.highlight = false,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  /// 强调卡片（主色细边 + 淡主色底），用于「今天最该做的那件事」
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasBackground = context.select<ThemeState, bool>((state) => state.background.isNotEmpty);
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.lg);

    final decoration = BoxDecoration(
      color: highlight ? palette.primarySoft : palette.cardColor(hasBackground: hasBackground),
      borderRadius: radius,
      border: Border.all(
        color: highlight ? palette.primary : palette.border,
        width: highlight ? 1.5 : 1,
      ),
    );

    final content = Container(
      decoration: decoration,
      padding: padding,
      child: child,
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: content,
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
            decoration: BoxDecoration(
              color: palette.primary,
              borderRadius: BorderRadius.circular(AppRadius.full),
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
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.color,
    this.icon,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
            Text(
              value,
              style: TextStyle(
                fontSize: AppFontSize.xl,
                fontWeight: FontWeight.w700,
                color: color ?? palette.text,
                fontFeatures: kTabularNumbers,
              ),
            ),
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

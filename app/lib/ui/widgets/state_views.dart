import 'package:sekainook_app/ui/icons/icons.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'motion/empty_illustration.dart';
import 'motion/shape_loader.dart';
import 'motion_widgets.dart';
import './motion/app_buttons.dart';

/// 加载中（小范围用，比如按钮旁边、列表尾部）
///
/// 图形是 FlClash 那种「会变形的块」（[ShapeLoader]），不是 Material 的转圈：
/// 转圈是匀速圆周运动，看久了像卡住；变形块每 650ms 换一个形状，
/// 有明确的「还在推进」的节奏。
///
/// 整页加载优先用 [SkeletonList] —— 骨架屏比转圈更不打断视线。
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EnterBox(
      duration: AppMotion.fast,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ShapeLoader(size: 30, color: palette.primary),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                message!,
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 骨架屏列表：按真实卡片的形状铺几张占位，逐张错峰浮现。
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 3,
    this.lines = 2,
    this.showLeading = true,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
  });

  final int count;
  final int lines;
  final bool showLeading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < count; i++)
            EnterBox(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: SkeletonCard(lines: lines, showLeading: showLeading),
              ),
            ),
        ],
      ),
    );
  }
}

/// 出错了（带重试）
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.icon = AppIcons.cloudOff});

  final String message;
  final VoidCallback? onRetry;
  final Glyph icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _StateHint(
      icon: icon,
      iconColor: palette.danger,
      message: message,
      action: onRetry == null
          ? null
          : AppOutlinedButton.icon(
              onPressed: onRetry,
              icon: const GlyphIcon(AppIcons.refresh, size: 18),
              label: const Text('再试一次'),
            ),
    );
  }
}

/// 空状态
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon = AppIcons.inbox,
    this.hint,
  });

  final String message;
  final String? hint;
  final Glyph icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _StateHint(
      icon: icon,
      iconColor: palette.textTertiary,
      message: message,
      hint: hint,
    );
  }
}

/// 出错 / 空状态共用的版式：圆形软底图标 + 文案 + 可选操作，
/// 整体从下方轻轻浮上来（[EnterBox]）。
class _StateHint extends StatelessWidget {
  const _StateHint({
    required this.icon,
    required this.iconColor,
    required this.message,
    this.hint,
    this.action,
  });

  final Glyph icon;
  final Color iconColor;
  final String message;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EnterBox(
      distance: 18,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              EmptyIllustration(
                icon: icon,
                color: iconColor,
                background: palette.surfaceSoft,
                size: 96,
                accent: palette.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppFontSize.sm, color: palette.textSecondary),
              ),
              if (hint != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppFontSize.xs, color: palette.textTertiary),
                ),
              ],
              if (action != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

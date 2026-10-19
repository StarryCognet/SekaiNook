import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';

/// 骨架块的呼吸动画：0.75 → 1.0 余弦呼吸，[AppMotion.skeleton] 一个周期。
///
/// 相位取自壁钟而不是控制器起点 —— 多个骨架块同时挂载时呼吸是齐的，
/// 也不会因为页面重建各喘各的。
class _SkeletonPulse extends StatefulWidget {
  const _SkeletonPulse({required this.child});

  final Widget child;

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _pump = AnimationController(
    vsync: this,
    duration: AppMotion.skeleton,
  )..repeat();

  @override
  void dispose() {
    _pump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return widget.child;

    final int period = AppMotion.skeleton.inMilliseconds;
    return AnimatedBuilder(
      animation: _pump,
      builder: (BuildContext context, Widget? child) {
        final double phase = (DateTime.now().millisecondsSinceEpoch % period) / period;
        final double opacity = 0.75 + 0.25 * math.cos(2 * math.pi * phase);
        return Opacity(opacity: opacity, child: child);
      },
      child: widget.child,
    );
  }
}

/// 一块占位色块（骨架屏的基本单位）。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
    this.shape = BoxShape.rectangle,
  });

  /// 圆形头像占位用它
  const SkeletonBox.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = AppRadius.full,
        shape = BoxShape.circle;

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final Color color = context.palette.surfaceSoft;
    return _SkeletonPulse(
      child: Container(
        width: width,
        height: height,
        decoration: ShapeDecoration(
          color: color,
          // 正圆用 CircleBorder（超椭圆在正圆上没区别），其余一律超椭圆
          shape: shape == BoxShape.circle ? const CircleBorder() : AppShape.all(radius),
        ),
      ),
    );
  }
}

/// 一行文字占位（宽度可按比例给，最后一行短一点更像文字）。
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.width, this.height = 14, this.widthFactor});

  final double? width;
  final double height;
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final Widget bar = SkeletonBox(width: width, height: height, radius: AppRadius.sm);
    if (widthFactor == null) return bar;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: bar,
    );
  }
}

/// 一张卡片形状的骨架屏（列表加载时铺几张）。
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2, this.showLeading = true, this.padding});

  final int lines;
  final bool showLeading;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      decoration: ShapeDecoration(
        // 骨架屏只在加载的那一两秒出现，用实色底即可，不必依赖全局背景图状态
        color: palette.surface,
        shape: AppShape.all(AppRadius.md, side: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showLeading) ...<Widget>[
            const SkeletonBox.circle(size: 40),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int i = 0; i < lines; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  SkeletonLine(widthFactor: i == lines - 1 ? 0.55 : 0.9),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

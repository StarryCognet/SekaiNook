import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_shape.dart';
import '../../../theme/tokens.dart';

/// 空态 / 错误态的程序化插画（移植 FlClash `widgets/null_status.dart` 的入场编排）。
///
/// FlClash 不用骨架屏，也不放静态图标：一个几何主轴从斜上方转着落位
/// （-150° → 0°，约 620ms），三颗强调色小圆晚一步逐个入场绕到它旁边。
/// **只跑一次**（900ms）不循环 —— 空态是「这一页没东西」，不该看起来像在加载。
class EmptyIllustration extends StatefulWidget {
  const EmptyIllustration({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    this.size = 96,
    this.accent,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;
  final Color? accent;

  @override
  State<EmptyIllustration> createState() => _EmptyIllustrationState();
}

class _EmptyIllustrationState extends State<EmptyIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.size;
    final Color accent = widget.accent ?? widget.color;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        // 主轴：前 69% 的时间转着落位（≈620ms），剩下的留给小圆收尾
        final double main = Curves.easeOutCubic.transform((t / 0.69).clamp(0.0, 1.0));
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: <Widget>[
              for (int i = 0; i < 3; i++) _satellite(i, t, size, accent),
              Transform.rotate(
                angle: (1 - main) * (-150 * math.pi / 180),
                child: Transform.scale(
                  scale: 0.55 + 0.45 * main,
                  child: Opacity(
                    opacity: math.min(1, t * 4),
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: Container(
        width: size * 0.72,
        height: size * 0.72,
        decoration: ShapeDecoration(
          color: widget.background,
          shape: AppShape.all(size * 0.36),
        ),
        child: Icon(widget.icon, size: size * 0.34, color: widget.color),
      ),
    );
  }

  /// 第 [i] 颗强调小圆：晚 120ms×i 登场，从中心往外弹到固定角位。
  Widget _satellite(int i, double t, double size, Color color) {
    final double delay = 0.16 + i * 0.12;
    final double local = ((t - delay) / 0.34).clamp(0.0, 1.0);
    if (local <= 0) return const SizedBox.shrink();
    final double e = Curves.easeOutBack.transform(local);
    final double angle = -math.pi / 2 + i * (2 * math.pi / 3) + 0.6;
    final double radius = size * 0.42 * e;
    final double dot = AppSpacing.sm + AppSpacing.xs * e;
    return Transform.translate(
      offset: Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      child: Container(
        width: dot,
        height: dot,
        decoration: ShapeDecoration(
          color: color.withValues(alpha: 0.5 + 0.4 * e),
          shape: AppShape.all(dot),
        ),
      ),
    );
  }
}

import 'package:sekainook_app/ui/icons/icons.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';

/// 成功那一下：光环扩散 + 对勾弹入。
///
/// 用在打卡成功、审批通过、兑换到账这类「做成了」的瞬间。
/// 单个组件只负责画，什么时候出现由调用方决定（对话里、列表项里、或 [showBurst] 盖在整页上）。
class SuccessBurst extends StatefulWidget {
  const SuccessBurst({
    super.key,
    this.size = 112,
    this.color,
    this.icon = AppIcons.check,
    this.autoPlay = true,
    this.onCompleted,
  });

  final double size;

  /// 默认取当前主题主色
  final Color? color;
  final Glyph icon;

  /// 挂载后自动播一次；设 false 时靠 [GlobalKey] 调 state.play() 手动触发
  final bool autoPlay;
  final VoidCallback? onCompleted;

  @override
  State<SuccessBurst> createState() => SuccessBurstState();
}

class SuccessBurstState extends State<SuccessBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.celebrate,
  );

  late final Animation<double> _ringScale = Tween<double>(begin: 0.45, end: 1.45).animate(
    CurvedAnimation(parent: _controller, curve: const Interval(0, 0.8, curve: AppMotion.decelerate)),
  );
  late final Animation<double> _ringFade = Tween<double>(begin: 0.9, end: 0).animate(
    CurvedAnimation(parent: _controller, curve: const Interval(0, 0.8, curve: AppMotion.standard)),
  );
  late final Animation<double> _iconScale = Tween<double>(begin: 0.2, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: const Interval(0.05, 0.5, curve: AppMotion.overshoot)),
  );
  late final Animation<double> _sparkT = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.15, 1, curve: AppMotion.decelerate),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.autoPlay) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _controller.value = 1;
      } else {
        play();
      }
    }
  }

  /// 播一次（再调用会从头播）
  void play() {
    _controller.forward(from: 0).whenComplete(() => widget.onCompleted?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.color ?? context.palette.primary;
    final double ringSize = widget.size * 0.82;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) => Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // 扩散的光环
            Opacity(
              opacity: _ringFade.value,
              child: Transform.scale(
                scale: _ringScale.value,
                child: Container(
                  width: ringSize,
                  height: ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.55), width: 3),
                  ),
                ),
              ),
            ),
            // 飞出去的小火花
            CustomPaint(
              size: Size.square(widget.size),
              painter: _SparkPainter(progress: _sparkT.value, color: color),
            ),
            // 本体圆底 + 对勾
            Transform.scale(
              scale: _iconScale.value,
              child: Container(
                width: widget.size * 0.54,
                height: widget.size * 0.54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: GlyphIcon(
                  widget.icon,
                  color: Colors.white,
                  size: widget.size * 0.32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const int _count = 8;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double baseRadius = size.width * 0.3;
    final Paint paint = Paint()
      ..color = color.withValues(alpha: (1 - progress).clamp(0, 1) * 0.8)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;

    for (int i = 0; i < _count; i++) {
      final double angle = (math.pi * 2 / _count) * i - math.pi / 2;
      final double distance = baseRadius + size.width * 0.16 * progress;
      final Offset from = center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final Offset to = from + Offset(math.cos(angle), math.sin(angle)) * (size.width * 0.06);
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// 在整页上盖一次成功动画，不挡点击、自动消失。
///
/// 打卡成功、审批通过这种「不想被对话框打断」的反馈用它。
void showBurst(BuildContext context, {Color? color, Duration? duration}) {
  final OverlayState? overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late final OverlayEntry entry;
  // 动画播完与兜底延时都会来收一次，必须幂等 —— OverlayEntry 重复 remove 会断言失败
  bool removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (BuildContext context) => IgnorePointer(
      child: Center(
        child: SuccessBurst(
          color: color,
          onCompleted: remove,
        ),
      ),
    ),
  );
  overlay.insert(entry);
  // 兜底：动画被打断（页面销毁）时也要收掉，别留孤儿
  Future<void>.delayed(
    duration ?? AppMotion.celebrate + const Duration(milliseconds: 120),
  ).then((_) => remove());
}

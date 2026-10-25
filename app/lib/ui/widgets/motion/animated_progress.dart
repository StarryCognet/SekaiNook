import 'package:flutter/material.dart';

import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';

/// 会「长」的进度条。
///
/// 宽度用 [TweenAnimationBuilder] 插值，避免 `LinearProgressIndicator` 那种
/// 每次 setState 都从零重画、看起来像闪一下。
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.color,
    this.trackColor,
    this.height = 10,
    this.duration = AppMotion.slower,
    this.radius,
  });

  /// 0.0 ~ 1.0，超出会被夹住
  final double value;
  final Color? color;
  final Color? trackColor;
  final double height;
  final Duration duration;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final BorderRadius shape = radius ?? BorderRadius.circular(AppRadius.full);
    final Color barColor = color ?? palette.primary;
    final Color track = trackColor ?? palette.surfaceSoft;
    final double target = value.isNaN ? 0 : value.clamp(0.0, 1.0);

    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return _build(track, shape, barColor, target);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: duration,
      curve: AppMotion.emphasized,
      builder: (BuildContext context, double animated, Widget? _) =>
          _build(track, shape, barColor, animated),
    );
  }

  Widget _build(Color track, BorderRadius shape, Color barColor, double factor) {
    // 裁剪也走超椭圆：ClipRRect 只切普通圆角，进度条两头会露折点
    return ClipPath(
      clipper: ShapeBorderClipper(shape: AppShape.of(shape)),
      child: Container(
        height: height,
        color: track,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: factor,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: AppShape.of(shape),
                gradient: LinearGradient(
                  colors: <Color>[barColor.withValues(alpha: 0.72), barColor],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 会呼吸的圆点 —— 未读角标、22 点提醒、「正在同步」这类「注意我」的信号。
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8, this.ring = true});

  final Color color;
  final double size;

  /// 是否在外面套一圈扩散的光环
  final bool ring;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

/// 圆点呼吸一个来回的时长。
///
/// ⚠️ `AppMotion` 里还没有这一档（最接近的是 `skeleton` 的 1600ms，节奏偏快）。
/// 待 Lead 加 `AppMotion.pulse` 后换掉这里的字面量，见交付说明的跨域待办。
const Duration _pulsePeriod = Duration(milliseconds: 1800);

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _pulsePeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery 只能在 didChangeDependencies 之后读；每次变化都重判，
    // 用户在设置里开关「移除动态效果」时不用重进页面。
    _syncMotion();
  }

  void _syncMotion() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      // 静态停在「刚散开」的一帧：环还在，只是不动。
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.ring) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        return SizedBox(
          width: widget.size * 2.6,
          height: widget.size * 2.6,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Opacity(
                  opacity: (1 - t) * 0.45,
                  child: Container(
                    width: widget.size + widget.size * 1.6 * t,
                    height: widget.size + widget.size * 1.6 * t,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                child!,
              ],
            ),
          ),
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

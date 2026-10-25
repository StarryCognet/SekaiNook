import 'dart:math' as math;

import 'package:sekainook_app/fl_ui/context.dart';
import 'package:sekainook_app/fl_ui/shape.dart';
import 'package:sekainook_app/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A pulsing bar that holds the place of one line of [style] text.
class SkeletonText extends StatelessWidget {
  const SkeletonText({super.key, required this.width, this.style});

  final double width;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        child: Stack(
          children: [
            Text(' ', style: style),
            Positioned.fill(
              child: Center(
                child: SkeletonPill(
                  width: double.infinity,
                  height: MediaQuery.textScalerOf(
                    context,
                  ).scale(style.fontSize ?? 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pulsing pill that holds the place of a block of a known size.
class SkeletonPill extends StatefulWidget {
  const SkeletonPill({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<SkeletonPill> createState() => _SkeletonPillState();
}

class _SkeletonPillState extends State<SkeletonPill> {
  final _SkeletonPulse _pulse = _SkeletonPulse.instance;

  bool _attached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // didChangeDependencies 每次 MediaQuery 变化都会再来一遍，挂载只做一次。
    if (!_attached) {
      _attached = true;
      _pulse.attach();
    }
    _pulse.setStill(context.disableAnimations);
  }

  @override
  void dispose() {
    if (_attached) {
      _pulse.detach();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = DecoratedBox(
      decoration: ShapeDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        shape: AppShape.full,
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: context.disableAnimations
            ? bar
            : ValueListenableBuilder<double>(
                valueListenable: _pulse.phase,
                builder: (context, phase, child) => Opacity(
                  opacity: _SkeletonPulse.opacityAt(phase),
                  child: child,
                ),
                child: bar,
              ),
      ),
    );
  }
}

/// 全站骨架共用一个 ticker。
///
/// 原来每个骨架块自己开一个 `AnimationController`，还要用 `DateTime.now()`
/// 取相位让它们看起来同步 —— 通知页一屏 16 个块就是 16 个常驻 ticker。
/// 现在一个 [Ticker] 推进 0..1 的相位，所有块共用，也就天然同拍。
class _SkeletonPulse {
  _SkeletonPulse._();

  static final _SkeletonPulse instance = _SkeletonPulse._();

  /// One breath of the skeleton, shared with the rest of the app.
  static const Duration _period = AppMotion.skeleton;

  /// Where a pill rests when motion is off: half a breath, so it still reads
  /// as a placeholder rather than as empty space.
  static const double stillPhase = 0.5;

  /// 0.75..1.0，和原来 `FadeTransition` 的呼吸幅度一致。
  static double opacityAt(double phase) =>
      0.75 + 0.25 * math.cos(2 * math.pi * phase);

  final ValueNotifier<double> phase = ValueNotifier<double>(0);

  Ticker? _ticker;
  int _users = 0;
  bool _still = false;

  void attach() {
    _users++;
    _sync();
  }

  void detach() {
    if (_users > 0) {
      _users--;
    }
    _sync();
  }

  void setStill(bool still) {
    if (still == _still) {
      return;
    }
    _still = still;
    _sync();
  }

  void _sync() {
    if (_users > 0 && !_still) {
      final ticker = _ticker ??= Ticker(_tick, debugLabel: 'SkeletonPulse');
      if (!ticker.isActive) {
        ticker.start();
      }
      return;
    }
    _ticker?.stop();
    phase.value = _still ? stillPhase : 0;
  }

  void _tick(Duration elapsed) {
    phase.value =
        elapsed.inMicroseconds % _period.inMicroseconds /
        _period.inMicroseconds;
  }
}

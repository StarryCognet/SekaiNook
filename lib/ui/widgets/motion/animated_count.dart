import 'package:flutter/material.dart';

import '../../../theme/motion.dart';

/// 会「滚」的数字。首次出现从 [from] 数到 [value]，之后每次变化都从当前值滚到新值，
/// 并且轻轻弹一下（[pulse]）—— 余额、积分、统计数用它。
///
/// 等宽数字由调用方在 [style] 里带上 `fontFeatures: kTabularNumbers`，
/// 滚动过程中整行才不会左右抖。
class AnimatedCount extends StatefulWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    this.style,
    this.duration = AppMotion.slower,
    this.formatter,
    this.from = 0,
    this.pulse = true,
  });

  final num value;
  final TextStyle? style;
  final Duration duration;

  /// 自定义渲染（金额保留两位小数之类）。默认四舍五入取整。
  final String Function(num value)? formatter;

  /// 首次出现时的起点
  final num from;

  /// 数值变化时是否弹一下
  final bool pulse;

  @override
  State<AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<AnimatedCount> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );

  late final Animation<double> _pulseAnim = TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 1, end: 1.07).chain(CurveTween(curve: AppMotion.decelerate)),
      weight: 35,
    ),
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 1.07, end: 1).chain(CurveTween(curve: AppMotion.overshoot)),
      weight: 65,
    ),
  ]).animate(_pulseController);

  @override
  void didUpdateWidget(AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && widget.pulse) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _format(num value) => widget.formatter?.call(value) ?? value.round().toString();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Text(_format(widget.value), style: widget.style);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: widget.from.toDouble(), end: widget.value.toDouble()),
      duration: widget.duration,
      curve: AppMotion.emphasized,
      builder: (BuildContext context, double animated, Widget? _) {
        final Widget text = Text(
          _format(animated),
          style: widget.style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        );
        if (!widget.pulse) return text;
        return AnimatedBuilder(
          animation: _pulseAnim,
          builder: (BuildContext context, Widget? child) =>
              Transform.scale(scale: _pulseAnim.value, child: child),
          child: text,
        );
      },
    );
  }
}

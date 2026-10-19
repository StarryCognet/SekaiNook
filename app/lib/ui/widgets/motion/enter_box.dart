import 'package:flutter/material.dart';

import '../../../theme/motion.dart';

/// 入场动画：淡入 + 自下而上滑入（可选轻微放大）。
///
/// 一次 [AnimationController] 里同时编码「延迟」与「动画本体」——
/// 总时长 = 延迟 + 时长，延迟那段用 [Interval] 挖掉。
/// 这样不用 Timer，组件被提前 dispose 也不会回调到已死的 State。
///
/// 列表里用它做错峰入场：
/// ```dart
/// ListView.builder(itemBuilder: (_, i) => EnterBox(index: i, child: Card(...)))
/// ```
/// 第 n 项的延迟是 `42ms * n`，超过第 10 项不再叠加（见 [AppMotion.stagger]）。
class EnterBox extends StatefulWidget {
  const EnterBox({
    super.key,
    required this.child,
    this.index = 0,
    this.delay,
    this.distance = AppMotion.enterOffset,
    this.duration = AppMotion.normal,
    this.scaleFrom,
    this.axis = Axis.vertical,
  });

  final Widget child;

  /// 列表中的序号，决定错峰延迟。显式给了 [delay] 时以 [delay] 为准。
  final int index;

  /// 显式延迟（不传则按 [index] 错峰）
  final Duration? delay;

  /// 入场位移距离
  final double distance;

  /// 位移与淡入的时长（不含延迟）
  final Duration duration;

  /// 若给了值，则从该缩放比例放大到 1.0
  final double? scaleFrom;

  final Axis axis;

  @override
  State<EnterBox> createState() => _EnterBoxState();
}

class _EnterBoxState extends State<EnterBox> with SingleTickerProviderStateMixin {
  late final Duration _delay = widget.delay ?? AppMotion.stagger(widget.index);
  late final Duration _total = _delay + widget.duration;

  late final AnimationController _controller = AnimationController(vsync: this, duration: _total);
  late final double _start =
      _total.inMicroseconds == 0 ? 0 : _delay.inMicroseconds / _total.inMicroseconds;
  late final double _span = 1 - _start;

  /// 透明度走得快一些：先看清楚内容，位移再慢慢收尾
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Interval(_start, _start + _span * 0.55, curve: AppMotion.standard),
  );
  late final Animation<double> _move = CurvedAnimation(
    parent: _controller,
    curve: Interval(_start, 1, curve: AppMotion.decelerate),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // MediaQuery 只能在 didChangeDependencies 之后读，不能在 initState 里读
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double move = _move.value;
        final double shift = widget.distance * (1 - move);
        Widget result = Transform.translate(
          offset: widget.axis == Axis.vertical ? Offset(0, shift) : Offset(shift, 0),
          child: child,
        );
        final double? scaleFrom = widget.scaleFrom;
        if (scaleFrom != null) {
          result = Transform.scale(scale: scaleFrom + (1 - scaleFrom) * move, child: result);
        }
        return Opacity(opacity: _fade.value.clamp(0.0, 1.0), child: result);
      },
      child: widget.child,
    );
  }
}

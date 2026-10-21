import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/motion.dart';
import 'spring_driver.dart';

/// 拖拽相关物理常量，全部照搬 FlClash `lib/widgets/navigation_dock.dart:36-47`。
const double _pullLimit = 7 / 32; // 最多能拉出最短边的 7/32
const double _pullStretch = 0.5; // 拉出去时在拉的方向上再拉伸一半
const double _pressGrowth = 1 / 8; // 按压膨胀 = 最短边 1/8 …
const double _maxPressGrowth = 16; // … 但绝对不超过 16px
const Duration _longPressDelay = Duration(milliseconds: 500);

/// FlClash 式「按下去会胀、还能被拽着走」的按压容器。
///
/// 与 [PressScale] 的区别：那个只会「按下去放大一点」，**手指拖动时它不跟**；
/// 这个把拖拽位移也接进弹簧（`_trackSpring` 120ms 无回弹），
/// 手指往哪儿拉控件就往哪儿被拽出去，并在拉拽方向上再拉伸 [_pullStretch]，
/// 松手用 `_settleSpring`(500ms / bounce .32) 弹回。
///
/// 移植自 `navigation_dock.dart:466-552`(ElasticPress) 与 `:617-653`(_RenderPressTransform)。
/// 注意：**不做水波纹**（splashFactory 走 NoSplash），按下反馈只有形变 + 一次 selectionClick。
class ElasticPress extends StatefulWidget {
  const ElasticPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onPressedChanged,
    this.enabled = true,
    this.haptic = true,
    this.pullLimit = _pullLimit,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按下态变化（给需要跟着换底色的调用方用，替代 InkWell 的 onHighlightChanged）
  final ValueChanged<bool>? onPressedChanged;
  final bool enabled;
  final bool haptic;

  /// 拖拽能拉出去多远（相对控件最短边的比例）
  final double pullLimit;

  @override
  State<ElasticPress> createState() => _ElasticPressState();
}

class _ElasticPressState extends State<ElasticPress> with TickerProviderStateMixin {
  late final SpringDriver _lift = SpringDriver(this, 0);
  late final SpringDriver _pullX = SpringDriver(this, 0);
  late final SpringDriver _pullY = SpringDriver(this, 0);
  late final Listenable _motion = Listenable.merge(<Listenable>[_lift, _pullX, _pullY]);

  Size _size = Size.zero;
  bool _pressed = false;
  Offset _downAt = Offset.zero;
  bool _reduceMotion = false;
  Timer? _longPressTimer;
  bool _longPressFired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  void _spring(SpringDriver driver, double target, SpringDescription spring) {
    if (_reduceMotion) {
      driver.jumpTo(target);
    } else {
      driver.springTo(target, spring);
    }
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    _pressed = value;
    widget.onPressedChanged?.call(value);
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    // 尺寸在按下时现取：用 LayoutBuilder 会破坏 AlertDialog / Table 这类
    // 需要计算 intrinsic dimensions 的父级（LayoutBuilder 不支持 intrinsic）。
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) _size = box.size;
    _setPressed(true);
    _downAt = event.localPosition;
    _longPressFired = false;
    _spring(_lift, 1, AppMotion.springPress);
    if (widget.haptic) HapticFeedback.selectionClick();
    if (widget.onLongPress != null) {
      _longPressTimer = Timer(_longPressDelay, () {
        if (!_pressed) return;
        _longPressFired = true;
        if (widget.haptic) HapticFeedback.selectionClick();
        widget.onLongPress!();
      });
    }
  }

  void _move(PointerMoveEvent event) {
    if (!_pressed) return;
    final Offset delta = event.localPosition - _downAt;
    if (delta.distance > kTouchSlop) _cancelLongPress();
    final double limit = math.max(6, _size.shortestSide * widget.pullLimit);
    _spring(_pullX, _rubberBand(delta.dx, limit), AppMotion.springTrack);
    _spring(_pullY, _rubberBand(delta.dy, limit), AppMotion.springTrack);
  }

  void _release() {
    _cancelLongPress();
    _setPressed(false);
    _spring(_lift, 0, AppMotion.springSettle);
    _spring(_pullX, 0, AppMotion.springSettle);
    _spring(_pullY, 0, AppMotion.springSettle);
  }

  void _up(PointerUpEvent event) {
    if (!_pressed) return;
    final bool isTap = (event.localPosition - _downAt).distance < kTouchSlop * 1.5;
    final bool fireTap = isTap && !_longPressFired && widget.onTap != null;
    _release();
    // 松手时再给一次轻触 —— 只在「真的点中了」时响，拖拽后撒手不响。
    if (widget.haptic && fireTap && !_reduceMotion) HapticFeedback.selectionClick();
    if (fireTap) widget.onTap!();
    _longPressFired = false;
  }

  void _cancel(PointerCancelEvent event) {
    if (!_pressed) return;
    _release();
    _longPressFired = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (BuildContext context, Widget? child) {
              final double lift = _lift.value;
              final double longest = math.max(1, _size.longestSide);
              final double swell =
                  1 + lift * math.min(_pressGrowth * 2, _maxPressGrowth / longest);
              final double sx = swell * (1 + _pullX.value.abs() / math.max(1, _size.width) * _pullStretch);
              final double sy = swell * (1 + _pullY.value.abs() / math.max(1, _size.height) * _pullStretch);
              final Offset center = _size.center(Offset.zero);
              return Transform(
                transform: Matrix4.diagonal3Values(sx, sy, 1)
                  ..setTranslationRaw(
                    center.dx * (1 - sx) + _pullX.value,
                    center.dy * (1 - sy) + _pullY.value,
                    0,
                  ),
                child: child,
              );
            },
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _cancelLongPress();
    _lift.dispose();
    _pullX.dispose();
    _pullY.dispose();
    super.dispose();
  }
}

/// 越界橡皮筋：拉得越远收益越小，永远到不了 [limit]。
/// 与 FlClash `navigation_dock.dart:81-84` 同式。
double _rubberBand(double overshoot, double limit) {
  if (limit <= 0) return 0;
  return limit * (1 - 1 / (overshoot.abs() * 0.55 / limit + 1)) * overshoot.sign;
}

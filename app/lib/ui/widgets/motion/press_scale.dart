import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/motion.dart';

/// 按压反馈的尺寸归一化膨胀量 —— 与 FlClash 的 `ElasticPress` 同源。
///
/// 公式 `grow = min(cap, room / 长边)` 的意义：**绝对膨胀量恒定**。
/// 56px 的圆钮胀 25%（每边 +7px），300px 的卡片只胀 5.3%（每边 +8px），
/// 观感一致；如果所有尺寸都用同一个百分比，小控件会「没反应」，
/// 大卡片则会胀到压住邻居。
double pressGrowthFor(BoxConstraints constraints) {
  final Size size = constraints.biggest;
  final double longest = size.longestSide;
  if (!longest.isFinite || longest <= 0) return AppMotion.pressGrow;
  return math.min(AppMotion.pressGrowCap, AppMotion.pressGrowRoom / longest);
}

/// 按压缩放反馈：按下鼓起来，松手用弹簧回位。
///
/// **放大而不是缩小**：缩小是「陷进页面」，FlClash 的按压是「浮起来」。
/// 全站无例外（水波纹已在 `app_theme.dart` 的 `splashFactory` 里关掉）。
///
/// ```dart
/// Material(
///   color: Colors.transparent,
///   child: PressScale(onTap: onTap, child: content),
/// )
/// ```
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.scale = 1,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  /// 额外倍率（默认 1 = 只走尺寸归一化的膨胀量）
  final double scale;

  /// 按下时是否给一次轻触觉反馈（Web 上会被忽略）
  final bool haptic;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    // 触觉只在「真的触发动作」时给一次，且用最轻的 selectionClick。
    // 每点一下都 lightImpact 会让人去关掉系统触感。
    if (widget.haptic) HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool interactive = widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    if (!interactive) return widget.child;

    final bool animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double grow = pressGrowthFor(constraints);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: _handleTap,
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  if (widget.haptic) HapticFeedback.selectionClick();
                  widget.onLongPress!.call();
                },
          child: AnimatedScale(
            scale: _pressed && animate ? (1 + grow) * widget.scale : 1,
            duration: _pressed ? AppMotion.instant : AppMotion.normal,
            curve: _pressed ? AppMotion.standard : AppMotion.spring,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// 可点区域 + 按压缩放二合一（卡片、列表项用这个）。
///
/// 关键在于用 [InkWell.onHighlightChanged] 拿按压状态，
/// 而不是再套一层 [GestureDetector] —— 后者会在手势竞技场里把 InkWell 的 onTap 吃掉。
class PressInkWell extends StatefulWidget {
  const PressInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.scale = 1,
    this.enabled = true,
    this.onHighlightChanged,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final double scale;
  final bool enabled;

  /// 按压态回调（按下 true / 松手 false）——卡片拿它同时改描边颜色
  final ValueChanged<bool>? onHighlightChanged;
  final bool haptic;

  @override
  State<PressInkWell> createState() => _PressInkWellState();
}

class _PressInkWellState extends State<PressInkWell> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    widget.onHighlightChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final bool interactive = widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    final bool animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double grow = pressGrowthFor(constraints);
        return AnimatedScale(
          scale: _pressed && animate ? (1 + grow) * widget.scale : 1,
          duration: _pressed ? AppMotion.instant : AppMotion.normal,
          curve: AppMotion.spring,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: interactive
                  ? () {
                      if (widget.haptic) HapticFeedback.selectionClick();
                      widget.onTap?.call();
                    }
                  : null,
              onLongPress: interactive && widget.onLongPress != null
                  ? () {
                      if (widget.haptic) HapticFeedback.selectionClick();
                      widget.onLongPress!.call();
                    }
                  : null,
              onHighlightChanged: interactive ? _setPressed : null,
              borderRadius: widget.borderRadius,
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

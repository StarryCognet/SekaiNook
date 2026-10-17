import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/motion.dart';

/// 按压缩放反馈：按下缩到 [AppMotion.pressScale]，松手用弹簧回位。
///
/// 与 [InkWell] 的分工：水波纹负责「点到了」，缩放负责「点得动」。
/// 想两个都要就把它套在 [InkWell] **里面**（这样水波纹不会被一起缩放掉）。
///
/// ```dart
/// Material(
///   color: Colors.transparent,
///   child: InkWell(
///     onTap: onTap,
///     child: PressScale(onTap: onTap, child: content),
///   ),
/// )
/// ```
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.scale = AppMotion.pressScale,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  /// 按下时缩放到的比例
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
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool interactive = widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    if (!interactive) return widget.child;

    final bool animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: _handleTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!.call();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: _pressed ? AppMotion.instant : AppMotion.normal,
        curve: _pressed ? AppMotion.standard : (animate ? AppMotion.spring : AppMotion.standard),
        child: widget.child,
      ),
    );
  }
}

/// 水波纹 + 按压缩放二合一（卡片、列表项用这个）。
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
    this.scale = AppMotion.pressScale,
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

    return AnimatedScale(
      scale: _pressed && animate ? widget.scale : 1,
      duration: _pressed ? AppMotion.instant : AppMotion.normal,
      curve: AppMotion.spring,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: interactive
              ? () {
                  if (widget.haptic) HapticFeedback.lightImpact();
                  widget.onTap?.call();
                }
              : null,
          onLongPress: interactive && widget.onLongPress != null
              ? () {
                  if (widget.haptic) HapticFeedback.mediumImpact();
                  widget.onLongPress!.call();
                }
              : null,
          onHighlightChanged: interactive ? _setPressed : null,
          borderRadius: widget.borderRadius,
          child: widget.child,
        ),
      ),
    );
  }
}

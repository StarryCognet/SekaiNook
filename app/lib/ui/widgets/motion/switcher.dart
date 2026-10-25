import 'package:flutter/material.dart';

import '../../../theme/app_shape.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../theme/tokens.dart';

/// 内容切换的默认转场：淡入 + 轻微位移，旧内容快速淡出。
///
/// 用法 —— 换 [childKey] 就播一次动画（Tab 切换、菜单切换、筛选切换）：
///
/// ```dart
/// SlideFadeSwitcher(
///   childKey: ValueKey<String>(_tab),
///   child: _buildTab(_tab),
/// )
/// ```
class SlideFadeSwitcher extends StatelessWidget {
  const SlideFadeSwitcher({
    super.key,
    required this.childKey,
    required this.child,
    this.offset = 12,
    this.duration = AppMotion.fast,
    this.axis = Axis.horizontal,
    this.alignment = Alignment.topCenter,
    this.direction = 1,
  });

  final Key childKey;
  final Widget child;

  /// 进场位移距离（逻辑像素）
  final double offset;
  final Duration duration;

  /// 滑动方向：横向（左右 Tab）或纵向（上下菜单）
  final Axis axis;

  /// 切换时两层的对齐方式，默认顶部对齐，避免高度不同时上下跳
  final Alignment alignment;

  /// 方向感：`1` = 新内容从右（横）/从下滑入、旧内容往左/上走（默认）；
  /// `-1` 则反过来。
  ///
  /// 调用方按「目标 tab 在当前 tab 的左边还是右边」算出来传，切换才有空间感 ——
  /// 从「任务区」点到「历史记录」应该往左翻页，而不是每次都从右边挤进来。
  final int direction;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return KeyedSubtree(key: childKey, child: child);
    }

    final double sign = direction >= 0 ? 1 : -1;
    final Offset base = axis == Axis.horizontal ? Offset(offset * sign, 0) : Offset(0, offset * sign);
    final Offset begin = base;
    final Offset end = -base;

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: AppMotion.instant,
      switchInCurve: AppMotion.decelerate,
      switchOutCurve: AppMotion.accelerate,
      // 两层都参与布局（Stack + 顶对齐），避免高度差导致整页抖一下
      layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
        alignment: alignment,
        children: <Widget>[
          ...previous,
          ?current,
        ],
      ),
      transitionBuilder: (Widget child, Animation<double> animation) {
        // 进场的 key 与当前 childKey 相同；退场的是旧 key
        final bool incoming = child.key == childKey;
        final Tween<Offset> tween = Tween<Offset>(
          begin: incoming ? begin : Offset.zero,
          end: incoming ? Offset.zero : end,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: tween.animate(CurvedAnimation(parent: animation, curve: AppMotion.standard)),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: childKey, child: child),
    );
  }
}

/// 高亮块的「滑块」：在若干等宽选项之间滑动（分段控件、Tab 下划线）。
///
/// 与 [SlideFadeSwitcher] 的区别是它不换内容，只移动一个背景块，
/// 并且用弹簧曲线让连续点击有跟手感。
class SlidingHighlight extends StatelessWidget {
  const SlidingHighlight({
    super.key,
    required this.index,
    required this.count,
    required this.height,
    this.color,
    this.padding = AppSpacing.xs,
    this.radius = AppRadius.sm,
  });

  final int index;
  final int count;
  final double height;
  final Color? color;
  final double padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    if (count <= 0) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: index.toDouble()),
      duration: AppMotion.fast,
      curve: AppMotion.spring,
      builder: (BuildContext context, double animated, Widget? _) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double slot = constraints.maxWidth / count;
          return Transform.translate(
            offset: Offset(slot * animated, 0),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Container(
                width: slot - padding * 2,
                height: height - padding * 2,
                decoration: ShapeDecoration(
                  color: color ?? palette.surface,
                  shape: AppShape.all(radius),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme/motion.dart';
import '../../../theme/tab_transition.dart';

/// 换 Tab 时的内容转场，按 [TabTransition] 分派。
///
/// 与 [SlideFadeSwitcher] 的分工：
/// - [SlideFadeSwitcher] 是**局部内容**切换（筛选、分段、子页签），所有地方都用它，
///   观感必须统一 —— 别拿这个设置去改它，否则设置页选「3D 翻转」会把通知筛选也翻起来。
/// - 这个类是**整页**切换（底部五个 Tab 之间），可以换着玩法，由用户自己选。
///
/// 之所以全部用 [AnimatedSwitcher] 一条路子实现：它在过渡期间把新旧两页同时放在
/// 一个 Stack 里（旧的下、新的上），退场那一页的动画是反向的 —— 这正是「两页都在」
/// 类转场（滑动、视差、擦除、3D 翻转）需要的结构。代价是每个候选都得自己算
/// 位移/缩放/裁剪，不能像 AnimatedSwitcher 默认那样只套一个 FadeTransition。
class TabTransitionSwitcher extends StatelessWidget {
  const TabTransitionSwitcher({
    super.key,
    required this.childKey,
    required this.transition,
    required this.child,
    this.direction = 1,
  });

  /// 换它就播一次动画（通常就是路由地址）
  final Key childKey;

  /// 用哪套转场
  final TabTransition transition;

  final Widget child;

  /// 方向感：`1` = 往右翻（新页从右边来）、`-1` 反过来。
  ///
  /// 由调用方按「目标 Tab 在当前 Tab 的哪一侧」算好传进来 —— 从「首页」跳到
  /// 「设置」应该是往左翻页，而不是每次新页都从右边挤进来。
  final int direction;

  @override
  Widget build(BuildContext context) {
    // 系统开了「减少动态效果」：直接换，不给任何位移（无障碍要求，别绕过）
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return KeyedSubtree(key: childKey, child: child);
    }

    final double sign = direction >= 0 ? 1 : -1;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 整屏级转场要按「页面多大」算位移：宽屏上版心比屏幕窄，
        // 拿 MediaQuery 的屏宽会让整屏滑动多滑出去一截（右侧露底色）。
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final double height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;

        return AnimatedSwitcher(
          duration: transition.duration,
          reverseDuration: transition.reverseDuration,
          switchInCurve: _inCurveOf(transition),
          switchOutCurve: _outCurveOf(transition),
          // 两层都参与布局（Stack + 顶对齐）：
          // 页面高度不一样时，用默认 layoutBuilder 会让整页在切换中抖一下。
          layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              ...previous,
              ?current,
            ],
          ),
          transitionBuilder: (Widget child, Animation<double> animation) {
            final bool incoming = child.key == childKey;
            // 进场用 animation 本身（0→1），退场它是反向的（1→0）：
            // 统一成同一个 0→1 的进度，下面每个候选手感公式就只写一遍。
            final Animation<double> progress =
                incoming ? animation : ReverseAnimation(animation);
            return _buildTransition(
              context: context,
              child: child,
              progress: progress,
              incoming: incoming,
              sign: sign,
              width: width,
              height: height,
            );
          },
          child: KeyedSubtree(key: childKey, child: child),
        );
      },
    );
  }

  Widget _buildTransition({
    required BuildContext context,
    required Widget child,
    required Animation<double> progress,
    required bool incoming,
    required double sign,
    required double width,
    required double height,
  }) {
    return AnimatedBuilder(
      animation: progress,
      // 先算好 layout 再按参数包一层，避免每帧重建整棵页面
      child: child,
      builder: (BuildContext context, Widget? built) {
        final double t = progress.value.clamp(0.0, 1.0);
        final Widget page = built!;
        switch (transition) {
          case TabTransition.slideFade:
            // 基准：位移 16px + 淡入淡出。数值与 SlideFadeSwitcher 默认档一致，
            // 选它等于「回到以前的样子」。
            final double dx = incoming ? (1 - t) * 16 * sign : -t * 16 * sign;
            return _translate(
              dx: dx,
              opacity: incoming ? t : 1 - t,
              child: page,
            );

          case TabTransition.paging:
            // 整屏滑动：新旧两页都按整页宽平移 —— iOS 分页那种「一页推走另一页」。
            // 不做淡入：两页本来就是拼在一起的两张纸，中途透明会看到底下。
            final double dx = incoming ? (1 - t) * width * sign : -t * width * sign;
            return _translate(dx: dx, opacity: 1, child: page);

          case TabTransition.parallax:
            // 视差：旧页只退 34% 再微微缩小（像被推远），新页全速盖上来。
            if (incoming) {
              return _translate(
                dx: (1 - t) * width * 0.34 * sign,
                opacity: 1,
                child: page,
              );
            }
            return _translate(
              dx: -t * width * 0.34 * sign,
              scale: 1 - 0.035 * t,
              opacity: 1,
              child: page,
            );

          case TabTransition.scaleFade:
            if (incoming) {
              return _transform(
                scale: 0.92 + 0.08 * t,
                opacity: t,
                child: page,
              );
            }
            return _transform(scale: 1 + 0.05 * t, opacity: 1 - t, child: page);

          case TabTransition.zoomThrough:
            // 穿越：新页从更近的地方（1.08）压进来，旧页缩到 0.9 退走 ——
            // 两页缩放方向相反，才有「穿过去」的纵深感。
            if (incoming) {
              return _transform(scale: 1.08 - 0.08 * t, opacity: t, child: page);
            }
            return _transform(scale: 1 - 0.1 * t, opacity: 1 - t, child: page);

          case TabTransition.blurSlide:
            // 模糊 + 位移：模糊量随落定时收干。只在过渡期间存在这层
            // ImageFiltered，动画一结束就销毁 —— 不是常驻毛玻璃（那种真机会卡）。
            if (incoming) {
              return _blur(
                sigma: 8 * (1 - t),
                dx: (1 - t) * 16 * sign,
                opacity: t,
                child: page,
              );
            }
            return _blur(sigma: 8 * t, dx: -t * 16 * sign, opacity: 1 - t, child: page);

          case TabTransition.wipe:
            // 擦除：不做位移，新页从翻页来的那一侧把旧页盖掉。
            // 旧页保持原样（下层），新页上层按进度展开 —— 这就是 clip 的方向意义。
            if (incoming) {
              return ClipRect(
                clipper: _WipeClipper(
                  fromLeft: sign > 0,
                  progress: t,
                ),
                child: page,
              );
            }
            return page;

          case TabTransition.springSlide:
            // 弹簧位移：t 带 SpringCurve，会越过 1 —— 位移因此会冲过头再回来。
            if (incoming) {
              return _translate(dx: (1 - t) * 56 * sign, opacity: 1, child: page);
            }
            return _translate(dx: -t * 16 * sign, opacity: 1 - t, child: page);

          case TabTransition.popScale:
            // 弹性缩放：t 过冲时 scale 会短暂 > 1，正是「弹一下」的来源。
            if (incoming) {
              return _transform(scale: 0.86 + 0.14 * t, opacity: 1, child: page);
            }
            return _transform(scale: 1, opacity: 1 - t, child: page);

          case TabTransition.stagger:
            // 逐层揭开：新页从上往下露出来，同时轻轻上移；旧页快速淡出。
            // 真「卡片逐张」需要页面自己用 EnterBox 配错峰（各页已经在用），
            // 这里是页面级的近似 —— 整页一层层揭开，比整体淡入更有层次。
            if (incoming) {
              return ClipRect(
                clipper: _RevealClipper(progress: t),
                child: _translate(
                  dy: (1 - t) * 14,
                  opacity: math.min(1, t * 2.5),
                  child: page,
                ),
              );
            }
            return Opacity(opacity: 1 - t, child: page);

          case TabTransition.dockFirst:
            // 底栏先行：点击立刻有反馈（底栏自己动），内容延后 70ms 再进场。
            // 延迟用进度区间表达：总时长是 normal(240ms)，70/240 ≈ 0.29 之后才动。
            const double delay = 70 / 240;
            if (incoming) {
              final double local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
              return _translate(
                dy: (1 - local) * 8,
                opacity: local,
                child: page,
              );
            }
            return Opacity(opacity: 1 - t, child: page);

          case TabTransition.flip3d:
            // 3D 翻转：沿竖轴转 18°。轴心放在「来的那一侧」，
            // 否则页面会绕着屏幕中线翻，像一块贴纸在转。
            if (incoming) {
              return _flip(
                angle: (1 - t) * 18 * sign,
                opacity: t,
                alignment: sign > 0 ? Alignment.centerRight : Alignment.centerLeft,
                child: page,
              );
            }
            return _flip(
              angle: -t * 18 * sign,
              opacity: 1 - t,
              alignment: sign > 0 ? Alignment.centerRight : Alignment.centerLeft,
              child: page,
            );

          case TabTransition.sharedAxisY:
            // SharedAxis 的竖直版：纵向 30% 位移 + 淡入，新旧页面朝相反方向走。
            if (incoming) {
              return _translate(
                dy: (1 - t) * height * 0.30,
                opacity: t,
                child: page,
              );
            }
            return _translate(
              dy: -t * height * 0.30,
              opacity: 1 - t,
              child: page,
            );
        }
      },
    );
  }

  // ------------------------------------------------------------------
  // 组合小工具：把「位移 / 缩放 / 透明度 / 模糊」拼成一次包装
  // ------------------------------------------------------------------

  Widget _translate({
    required double opacity,
    required Widget child,
    double dx = 0,
    double dy = 0,
    double scale = 1,
  }) =>
      _transform(dx: dx, dy: dy, scale: scale, opacity: opacity, child: child);

  Widget _transform({
    required double opacity,
    required Widget child,
    double dx = 0,
    double dy = 0,
    double scale = 1,
    Alignment alignment = Alignment.center,
  }) {
    Widget result = child;
    if (scale != 1) {
      result = Transform.scale(scale: scale, alignment: alignment, child: result);
    }
    if (dx != 0 || dy != 0) {
      result = Transform.translate(offset: Offset(dx, dy), child: result);
    }
    return _opacity(opacity, result);
  }

  Widget _opacity(double value, Widget child) {
    // 1 和 0 之外都要走 Opacity；正好是 1 时省掉一层 saveLayer
    if (value >= 1) return child;
    return Opacity(opacity: value.clamp(0.0, 1.0), child: child);
  }

  Widget _blur({
    required double sigma,
    required double dx,
    required double opacity,
    required Widget child,
  }) {
    Widget result = child;
    // sigma 小到看不见就不加这层：ImageFiltered 每帧都要重建滤镜，白花钱
    if (sigma > 0.05) {
      result = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: result,
      );
    }
    if (dx != 0) {
      result = Transform.translate(offset: Offset(dx, 0), child: result);
    }
    return _opacity(opacity, result);
  }

  Widget _flip({
    required double angle,
    required double opacity,
    required Alignment alignment,
    required Widget child,
  }) {
    // setEntry(3, 2, …) 是透视：不给的话旋转看起来是「压扁」而不是「转过去」
    final Matrix4 matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateY(angle * math.pi / 180);
    return _opacity(
      opacity,
      Transform(
        alignment: alignment,
        transform: matrix,
        child: child,
      ),
    );
  }

  // ------------------------------------------------------------------
  // 曲线：进场统一「减速进入」，退场统一「加速离开」；弹簧类单独给
  // ------------------------------------------------------------------

  static Curve _inCurveOf(TabTransition value) => switch (value) {
        // 弹簧类：曲线本身带过冲，落点会冲过头，这正是要的效果
        TabTransition.springSlide || TabTransition.popScale => AppMotion.spring,
        TabTransition.dockFirst => AppMotion.standard,
        TabTransition.sharedAxisY => AppMotion.emphasized,
        TabTransition.paging || TabTransition.parallax => AppMotion.standard,
        _ => AppMotion.decelerate,
      };

  static Curve _outCurveOf(TabTransition value) => switch (value) {
        // 两页一起平移的那几个：退场也用标准曲线，否则一快一慢会「错位」
        TabTransition.paging || TabTransition.parallax => AppMotion.standard,
        _ => AppMotion.accelerate,
      };
}

/// 「方向擦除」的裁切：新页从一侧按进度展开。
class _WipeClipper extends CustomClipper<Rect> {
  const _WipeClipper({required this.fromLeft, required this.progress});

  /// true = 从左侧开始（新页从左边来）；false = 从右侧开始
  final bool fromLeft;
  final double progress;

  @override
  Rect getClip(Size size) {
    final double w = size.width * progress.clamp(0.0, 1.0);
    return Rect.fromLTWH(fromLeft ? 0 : size.width - w, 0, w, size.height);
  }

  @override
  bool shouldReclip(_WipeClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.fromLeft != fromLeft;
}

/// 「逐层揭开」的裁切：新页从上往下露出。
class _RevealClipper extends CustomClipper<Rect> {
  const _RevealClipper({required this.progress});

  final double progress;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width, size.height * progress.clamp(0.0, 1.0));

  @override
  bool shouldReclip(_RevealClipper oldClipper) => oldClipper.progress != progress;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// FlClash 的加载指示器：不是转圈，是一坨**会变形的块**。
///
/// 素材来自 FlClash `lib/widgets/loading.dart` 的 `CommonCircleLoading`：
///
/// * 一个 4666ms 的大周期里，图形一直在慢慢转（一圈）；
/// * 每 650ms 换一个形状 —— 7 个形状首尾相接，所以形变是**连续的**，
///   中间靠一条过冲曲线（`easeOutBack`）推过去，看起来像有弹性；
/// * 7 × 650 = 4550ms，**故意不等于** 4666ms：两个节奏若对齐，
///   几秒后就会看出一个可预期的循环，反而显得机械。
///
/// 形状本身用极坐标半径函数描述（超椭圆 / 正多边形 / 星形），
/// 两两之间直接对半径做插值，所以任意形状组合都能变形，不必手写路径。
///
/// 和骨架屏（[SkeletonList]）的分工不变：整页优先骨架屏，这里管小范围等待
/// （按钮旁、列表尾部、下拉刷新）。
class ShapeLoader extends StatefulWidget {
  const ShapeLoader({super.key, this.size = 28, this.color});

  /// 外框边长。图形本身只占短边的约 76%（FlClash 是 38/48），
  /// 留出的余量给「形变过冲」和旋转，免得贴边被裁。
  final double size;

  final Color? color;

  @override
  State<ShapeLoader> createState() => _ShapeLoaderState();
}

class _ShapeLoaderState extends State<ShapeLoader>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 4666);
  static const double _morphMs = 650;

  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 「减少动态效果」时不做形变，退化成一颗静态圆点。
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _controller?.dispose();
      _controller = null;
    } else {
      _controller ??= AnimationController(vsync: this, duration: _period)..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '加载中',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _controller == null
            ? CustomPaint(painter: _ShapeLoaderPainter(elapsedMs: 0, color: color))
            : AnimatedBuilder(
                animation: _controller!,
                builder: (BuildContext context, Widget? _) => CustomPaint(
                  painter: _ShapeLoaderPainter(
                    elapsedMs: _controller!.value * _period.inMilliseconds,
                    color: color,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ShapeLoaderPainter extends CustomPainter {
  _ShapeLoaderPainter({required this.elapsedMs, required this.color});

  final double elapsedMs;
  final Color color;

  /// 7 个形状首尾相接：最后一个形变回第一个，所以循环是闭合的。
  static const List<int> _sequence = <int>[0, 1, 2, 3, 4, 5, 6];
  static const int _samples = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = elapsedMs / _ShapeLoaderState._morphMs;
    final int step = t.floor();
    final double local = (t - step).clamp(0.0, 1.0);
    final double eased = Curves.easeOutBack.transform(local);
    final int from = _sequence[step % _sequence.length];
    final int to = _sequence[(step + 1) % _sequence.length];

    final double radius = size.shortestSide / 2 * 0.76;
    final Path path = Path();
    for (int i = 0; i <= _samples; i++) {
      final double angle = i / _samples * 2 * math.pi;
      final double r = _lerp(
        _radiusAt(from, angle),
        _radiusAt(to, angle),
        eased,
      );
      final Offset point = Offset(math.cos(angle), math.sin(angle)) * (r * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      // 一整圈正好走完一个 4666ms 周期 —— 和形变节奏错开
      ..rotate(2 * math.pi * (elapsedMs / 4666))
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..isAntiAlias = true,
      )
      ..restore();
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// 极坐标半径函数：角度 → 归一化半径（1 = 外接圆）。
  static double _radiusAt(int kind, double angle) {
    switch (kind) {
      case 0:
        return _superellipse(angle, 3.2); // 圆角方（squircle）
      case 1:
        return _polygon(angle, 9); // 九边饼干
      case 2:
        return _polygon(angle, 5); // 五边形
      case 3:
        return _superellipse(angle, 2.0); // 正圆
      case 4:
        return _star(angle, 8, 0.74); // 八角太阳
      case 5:
        return _superellipse(angle, 6.5); // 近乎正方
      default:
        return _superellipse(angle, 1.55); // 椭圆
    }
  }

  /// |x/a|^n + |y/b|^n = 1 的极坐标形式。n=2 是圆，n 越大越方，n<2 变尖。
  static double _superellipse(double angle, double n) {
    final double c = math.cos(angle).abs();
    final double s = math.sin(angle).abs();
    return 1 / math.pow(math.pow(c, n) + math.pow(s, n), 1 / n).toDouble();
  }

  /// 正 [sides] 边形：任何角度都落在「该边中垂线距离」上。
  static double _polygon(double angle, int sides) {
    final double seg = 2 * math.pi / sides;
    final double m = angle % seg;
    return math.cos(seg / 2) / math.cos(m - seg / 2);
  }

  /// [points] 个瓣的星形。[inner] 是凹谷相对外接圆的半径。
  static double _star(double angle, int points, double inner) {
    final double wave = 0.5 + 0.5 * math.cos(points * angle);
    return 1 - (1 - inner) * wave;
  }

  @override
  bool shouldRepaint(_ShapeLoaderPainter oldDelegate) =>
      oldDelegate.elapsedMs != elapsedMs || oldDelegate.color != color;
}

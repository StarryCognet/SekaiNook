import 'dart:math' as math;
import 'dart:ui' show ClipOp, lerpDouble;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// 全站形状（超椭圆圆角）—— 唯一数据源。
///
/// ## 为什么要换掉 [RoundedRectangleBorder]
///
/// 普通圆角是「四条直线 + 四段圆弧」拼出来的，直线与圆弧的相接处曲率
/// 从 0 突然跳到 1/r，眼睛能看出那个折点。超椭圆（superellipse）用
/// `|x/a|^n + |y/b|^n = 1` 的曲线代替，曲率沿整段连续变化，所以同一个
/// 半径下看起来更「鼓」、更软，边角不会显得发尖。
///
/// FlClash 把这一点当成全站基础（`lib/common/shape.dart` 的 `AppShape`），
/// 从卡片、弹层、按钮到导航指示器一律用 [RoundedSuperellipseBorder]。
///
/// 用法：**能用 ShapeBorder 的地方就用这里的工厂**；只能吃 [BorderRadius]
/// 的旧 API（如 [BoxDecoration]）应改用 [ShapeDecoration] 配这里的形状。
abstract final class AppShape {
  /// 四角同半径
  static RoundedSuperellipseBorder all(
    double radius, {
    BorderSide side = BorderSide.none,
  }) {
    return RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side,
    );
  }

  /// 只切顶部两角（底部弹层用，底部要贴屏幕边）
  static RoundedSuperellipseBorder top(
    double radius, {
    BorderSide side = BorderSide.none,
  }) {
    return RoundedSuperellipseBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      side: side,
    );
  }

  /// 只切底部两角
  static RoundedSuperellipseBorder bottom(
    double radius, {
    BorderSide side = BorderSide.none,
  }) {
    return RoundedSuperellipseBorder(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      side: side,
    );
  }

  /// 胶囊：半径给足（超过短边一半会自动退化成胶囊）
  static RoundedSuperellipseBorder pill({BorderSide side = BorderSide.none}) {
    return all(AppRadius.full, side: side);
  }

  /// 卡片：lg 圆角 + 1px 描边
  static RoundedSuperellipseBorder card(Color border) {
    return all(AppRadius.lg, side: BorderSide(color: border));
  }

  /// 对话框
  static RoundedSuperellipseBorder dialog({BorderSide side = BorderSide.none}) {
    return all(AppRadius.xxl, side: side);
  }

  /// 底部弹层（顶部圆角，底部贴边）
  static RoundedSuperellipseBorder sheet({BorderSide side = BorderSide.none}) {
    return top(AppRadius.xxl, side: side);
  }

  /// 输入框
  static RoundedSuperellipseBorder input(Color border) {
    return all(AppRadius.md, side: BorderSide(color: border));
  }

  /// 从现成 [BorderRadius] 升级（保留调用方给的半径 / 单边圆角）
  static RoundedSuperellipseBorder of(
    BorderRadius radius, {
    BorderSide side = BorderSide.none,
  }) {
    return RoundedSuperellipseBorder(borderRadius: radius, side: side);
  }
}


/// 超椭圆输入框边框。
///
/// [InputDecorationTheme.border] 要求 `InputBorder`，而
/// [RoundedSuperellipseBorder] 只是 `OutlinedBorder` —— 所以要包一层。
/// `preferPaintInterior = true` 让填充色也走超椭圆（否则底色会被单独按矩形裁）。
///
/// `gap` 那段是给浮动 label 开口的：文字浮到边框线上时，把线在那一段挖掉，
/// FlClash 的写法是 `clipRect(clipOp: ClipOp.difference)` 再画整圈。
class AppInputBorder extends InputBorder {
  const AppInputBorder({
    super.borderSide = const BorderSide(),
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.md)),
    this.gapPadding = 4,
  });

  final BorderRadius borderRadius;
  final double gapPadding;

  RoundedSuperellipseBorder get _shape =>
      RoundedSuperellipseBorder(borderRadius: borderRadius, side: borderSide);

  @override
  bool get isOutline => true;

  @override
  bool get preferPaintInterior => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  AppInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) {
    return AppInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
    );
  }

  @override
  AppInputBorder scale(double t) {
    return AppInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      gapPadding: gapPadding * t,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect, textDirection: textDirection);

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => _shape.paintInterior(canvas, rect, paint, textDirection: textDirection);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is AppInputBorder) {
      return AppInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: a.gapPadding,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is AppInputBorder) {
      return AppInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        gapPadding: b.gapPadding,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final Rect outline = rect.deflate(borderSide.width / 2);
    if (gapStart == null || gapExtent <= 0.0 || gapPercentage == 0.0) {
      _shape.paint(canvas, outline, textDirection: textDirection);
      return;
    }
    final double extent = lerpDouble(0.0, gapExtent + gapPadding * 2.0, gapPercentage)!;
    final double start = switch (textDirection ?? TextDirection.ltr) {
      TextDirection.rtl => gapStart + gapPadding - extent,
      TextDirection.ltr => gapStart - gapPadding,
    };
    final BorderRadius radii = borderRadius;
    final double left = outline.left + math.max(0.0, start);
    final double depth = math.max(radii.topLeft.y, radii.topRight.y) + borderSide.width;
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTRB(
          left,
          outline.top - borderSide.width,
          left + extent,
          outline.top + depth,
        ),
        clipOp: ClipOp.difference,
      );
    _shape.paint(canvas, outline, textDirection: textDirection);
    canvas.restore();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppInputBorder &&
        other.borderSide == borderSide &&
        other.borderRadius == borderRadius &&
        other.gapPadding == gapPadding;
  }

  @override
  int get hashCode => Object.hash(borderSide, borderRadius, gapPadding);
}

import 'package:flutter/material.dart';
import 'package:sekainook_app/fl_ui/loading.dart';

/// 全站长等待的转圈 —— FlClash 的彗星环，替代 [CircularProgressIndicator]。
///
/// 颜色不给时走主题 primary；[CommonCircleLoading] 内部还带一圈淡色轨道和拖尾，
/// 比 Material 的旋转弧线更"有分量"，也是 FlClash 全站的统一等待语言。
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.size = 20, this.color, this.semanticLabel});

  /// 侧边像素。列表行内的小圈用 18–20，独立等待态用 [CommonCircleLoading.page] 的 48。
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return CommonCircleLoading(
      size: size,
      color: color,
      semanticLabel: semanticLabel,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:sekainook_app/fl_ui/loading.dart';

/// 全站长等待的转圈 —— FlClash 的彗星环，替代 [CircularProgressIndicator]。
///
/// 颜色不给时走主题 primary；[CommonCircleLoading] 内部还带一圈淡色轨道和拖尾，
/// 比 Material 的旋转弧线更"有分量"，也是 FlClash 全站的统一等待语言。
///
/// **这就是默认的加载语汇**：新代码引它，别再造第二个转圈；`state_views.dart`
/// 里那套变形块 `LoadingView` 只留给预览页这类特殊场景。
class AppLoading extends StatelessWidget {
  const AppLoading({
    super.key,
    this.size = 20,
    this.color,
    this.semanticLabel = '加载中',
  });

  /// 侧边像素。列表行内的小圈用 18–20，独立等待态用 [CommonCircleLoading.page] 的 48。
  final double? size;
  final Color? color;

  /// 读屏念的话。默认给「加载中」—— 调用方不传也能被念出来；
  /// 显式传 null 才是不念（外层已经有等价播报时）。
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

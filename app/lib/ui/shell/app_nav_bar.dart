import 'package:flutter/material.dart';

import '../../fl_ui/navigation_dock.dart';
import '../../theme/tokens.dart';

/// 底部导航的**兼容垫片**。
///
/// 实际渲染的底栏是 `fl_ui/navigation_dock.dart` 里的 [NavigationDock]
/// （弹簧透镜跟手 + 按下膨胀），由 `main_shell.dart` 直接使用。
/// 这里只保留各页面算「底部让位」时用的 [contentInset] —— 8 个页面都
/// `import '../shell/app_nav_bar.dart'` 只为取这一个静态方法。
///
/// 2026-10 清理：原来这套自绘的 `AppNavBar`（753 行）在切换到 NavigationDock
/// 之后**没有任何地方实例化它**，属于纯死代码（连同它的透镜物理、拖拽手势、
/// 按下膨胀实现）。删掉之后页面 API 不变，只留下这一份让位计算 —— 底栏的
/// 高度真源在 [NavigationDock]，这里不重复写数字。
abstract final class AppNavBar {
  /// 页面内容底部要为悬浮底栏 + 手势条让出的高度。
  ///
  /// 读 `viewPadding` 而不是 `padding`：外壳会把 body 的 `padding.bottom`
  /// 抹成 0，只有 `viewPadding` 始终是屏幕自己的安全区原值。
  static double contentInset(BuildContext context) =>
      NavigationDock.contentInsetOf(context) + AppSpacing.sm;
}

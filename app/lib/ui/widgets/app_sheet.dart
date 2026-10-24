import 'package:flutter/material.dart';

import '../../fl_ui/sheet.dart';

/// 用 FlClash 的 SnapSheet 从底部弹出一个内容面板。
///
/// 与旧的 [showFloatingDialog]（居中卡片）相比：
/// - 走 `SnapSheetRoute`，挂在 root Navigator 上，**天生盖住主壳的悬浮
///   NavigationDock** —— 底部那条胶囊是 MainShell 的 `bottomNavigationBar`，
///   而 sheet 是 Navigator 栈上更高的一层；
/// - 自带 FlClash 的弹簧跟手、拖拽下压关闭、背景模糊遮罩；
/// - `fitsContent: true`，面板高度跟着内容走（内容超过最高档位时内部滚动）。
///
/// 内容只负责自己的排版，不要再套 `Dialog` / `Scaffold`。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showSheet<T>(
    context: context,
    builder: (sheetContext) => SafeArea(top: false, child: builder(sheetContext)),
  );
}

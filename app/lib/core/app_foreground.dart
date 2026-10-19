import 'package:flutter/widgets.dart';

/// 应用当前是否在前台（可安全发起网络刷新）。
///
/// 对应 Web 版每个页面轮询里的 `if (document.hidden) return;`：
/// 页面级定时器在后台空转只是白打后端，所以退到后台就跳过这一跳，
/// 回到前台再由 `didChangeAppLifecycleState` 立刻补一次（等价 `visibilitychange`）。
///
/// `lifecycleState` 为 `null` 时算**前台**：App 刚起来还没收到第一次生命周期回调时
/// 它就是 null，这时若当成后台，会把首屏那次刷新一起吞掉 —— 页面就一直停在空状态。
bool get isAppInForeground {
  final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

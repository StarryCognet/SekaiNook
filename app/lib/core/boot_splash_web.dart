// Web 构建里的实现：撤掉 index.html 里的启动动画。
//
// 非 Web 平台走 `boot_splash_stub.dart`（空实现），所以这个文件可以放心被
// `lib/main.dart` 无条件 import。

import 'dart:js_interop';

@JS('window.__sekainookBootDone')
external JSAny? get _bootDoneHandle;

@JS('window.__sekainookBootDone')
external void _bootDone();

/// 调一次 `window.__sekainookBootDone()`（index.html 里定义）。
///
/// 没定义时（老 index.html 缓存、被 CSP 拦掉）静默跳过 —— 启动动画那边还有
/// 8 秒兜底自动撤除，不会挡住页面。
void removeHtmlBootSplash() {
  if (_bootDoneHandle == null) return;
  _bootDone();
}

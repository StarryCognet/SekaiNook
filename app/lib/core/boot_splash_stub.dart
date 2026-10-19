// 非 Web 平台的空实现（Android 上没有 HTML 启动动画这回事）。
//
// 与 `boot_splash_web.dart` 成对，由 `boot_splash.dart` 条件导入 —— 所以
// `lib/main.dart` 可以无条件调用 `removeHtmlBootSplash()`。
void removeHtmlBootSplash() {}

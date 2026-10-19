// 撤掉 `web/index.html` 里那段 HTML 启动动画（种子里呼吸 + 进度条扫光）。
//
// 为什么要有它：Flutter Web 首帧之前，页面上是一块空白 canvas；`index.html` 里
// 先铺一层纯 HTML/CSS 的启动动画把这段空窗盖住，等 Dart 侧第一帧画好了再由这里
// 调 `window.__sekainookBootDone()` 淡出撤除（HTML 侧还有 8 秒兜底，见 index.html）。
//
// 平台分支走条件导入：Web 用 `boot_splash_web.dart`，其它平台是空实现。
import 'boot_splash_stub.dart' if (dart.library.js_interop) 'boot_splash_web.dart'
    as impl;

/// Web：淡出并移除启动动画；其它平台：什么都不做。
void removeHtmlBootSplash() => impl.removeHtmlBootSplash();

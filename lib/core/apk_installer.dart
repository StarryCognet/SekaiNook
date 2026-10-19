import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../data/models/app_update.dart';
import 'apk_installer_stub.dart' if (dart.library.io) 'apk_installer_io.dart' as impl;

/// 这台设备走不走「应用内下载安装」这条路。
///
/// 只有安卓能装 APK：网页版刷新页面就是最新版，桌面端本来也不在这份交付里。
bool get canInstallAppUpdate =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 更新的原生半场：下载 → 校验 sha256 → 交给系统安装器。
///
/// 分流走条件导入：安卓/桌面编 [apk_installer_io.dart]，Web 编 [apk_installer_stub.dart]。
/// 这么绕一下是为了 `dart:io` 不进 Web 构建 —— 否则 `flutter build web` 直接编不过。
abstract final class ApkInstaller {
  /// 有没有「安装未知应用」的权限（安卓 8+ 首次装必须由用户手动允许）
  static Future<bool> hasPermission() => impl.hasInstallPermission();

  /// 下载并校验。成功返回本机路径；sha256 对不上会删掉文件并抛 [FormatException]。
  static Future<String> download(
    AppUpdateInfo info, {
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) =>
      impl.downloadApk(info, onProgress: onProgress, cancelToken: cancelToken);

  /// 调起系统安装器。
  ///
  /// * `true` = 安装器已经拉起，接下来由用户在系统界面上确认；
  /// * `false` = 没有「安装未知应用」权限，**已经把他送到系统授权页**，
  ///   允许之后回来再点一次「下载安装」即可（包还在，不会重下）。
  static Future<bool> startInstall(String path) => impl.startSystemInstall(path);
}

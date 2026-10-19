import 'package:dio/dio.dart';

import '../data/models/app_update.dart';

/// 网页版实现：浏览器里「下载安装 APK」这件事没有意义（刷新页面就是最新版），
/// 所以全部按不支持返回。存在的唯一理由是让 `dart:io` 不进 Web 构建 ——
/// 少了这份桩，`flutter build web` 会直接编不过。
Future<bool> hasInstallPermission() async => false;

Future<String> downloadApk(
  AppUpdateInfo info, {
  required void Function(double progress) onProgress,
  CancelToken? cancelToken,
}) async {
  throw UnsupportedError('网页版不支持下载安装包');
}

Future<bool> startSystemInstall(String path) async => false;

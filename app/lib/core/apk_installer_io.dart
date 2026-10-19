import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/app_update.dart';

/// 与 android/app/src/main/kotlin/com/sekainook/sekainook_app/MainActivity.kt 里的 channel 名一致
const MethodChannel _channel = MethodChannel('com.sekainook.sekainook_app/install');

/// 安装包的落点（相对临时目录）。必须和 android/app/src/main/res/xml/file_paths.xml
/// 里放出来的那个子目录同名，否则系统安装器读不到这个文件。
const String _updateDirName = 'updates';

Future<bool> hasInstallPermission() async =>
    await _channel.invokeMethod<bool>('canInstall') ?? false;

/// 把 APK 下到本机临时目录并校验 sha256。
///
/// 不做断点续传：家里 Wi-Fi 下 60MB 重来一次的代价，比养一套续传状态机便宜得多。
Future<String> downloadApk(
  AppUpdateInfo info, {
  required void Function(double progress) onProgress,
  CancelToken? cancelToken,
}) async {
  final Directory dir = await _updateDir();
  // 先清掉上一次留下的包：一个 60MB，攒两次就很显眼了
  _clear(dir);

  final File file = File('${dir.path}/${info.fileName}');
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      // 60MB 走移动网络可能要好几分钟，别用默认的接收超时把它掐了
      receiveTimeout: const Duration(minutes: 15),
      validateStatus: (int? status) => status != null && status >= 200 && status < 300,
    ),
  );
  await dio.download(
    info.url,
    file.path,
    cancelToken: cancelToken,
    onReceiveProgress: (int received, int total) {
      // total 有时是 -1（服务端没给 Content-Length），那就用清单里写的大小兜底
      final int all = total > 0 ? total : info.size;
      if (all > 0) onProgress((received / all).clamp(0.0, 1.0));
    },
  );

  // 一定要校：包和清单都放在公网静态存储上，中间被换过必须当场拒绝，不能装上去
  final String actual = await _sha256Of(file);
  if (actual.toLowerCase() != info.sha256.toLowerCase()) {
    await deleteFile(file.path);
    throw const FormatException('安装包校验没通过，已经丢弃（可能是下载不完整）');
  }
  return file.path;
}

Future<bool> startSystemInstall(String path) async =>
    await _channel.invokeMethod<bool>('installApk', <String, dynamic>{
      'path': path,
    }) ??
    false;

Future<void> deleteFile(String path) async {
  final File file = File(path);
  if (!file.existsSync()) return;
  try {
    file.deleteSync();
  } on FileSystemException {
    // 删不掉不算事故：下次下载会覆盖同名文件，换个版本也会先清目录
  }
}

Future<Directory> _updateDir() async {
  final Directory base = await getTemporaryDirectory();
  final Directory dir = Directory('${base.path}/$_updateDirName');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// 清空下载目录。目录不存在 / 单个文件删不掉都不当错误 —— 这里只是打扫卫生。
void _clear(Directory dir) {
  if (!dir.existsSync()) return;
  for (final FileSystemEntity entity in dir.listSync()) {
    try {
      entity.deleteSync(recursive: true);
    } on FileSystemException {
      continue;
    }
  }
}

Future<String> _sha256Of(File file) async {
  final Digest digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

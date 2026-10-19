import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/app_constants.dart';
import '../models/app_update.dart';

/// 读更新清单：R2 上的静态 `latest.json`（见 docs/android-update.md）。
///
/// 为什么不复用 [ApiClient]：那份 client 打的是自家 API，12 秒超时 + 失败重试两次。
/// 清单在另一个域上，而且**检查更新失败本来就应该静默算了** —— 重试两次只会让
/// 打开 App 慢两秒，换不来任何东西。
class AppUpdateApi {
  AppUpdateApi({String? manifestUrl, Dio? dio})
      : _manifestUrl = manifestUrl ?? AppConstants.appUpdateManifestUrl,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 6),
                // 自己判状态码：404（桶里还没有清单）跟断网一样，都只是「没有新版本」
                validateStatus: (int? _) => true,
              ),
            );

  final String _manifestUrl;
  final Dio _dio;

  /// 拉清单。断网 / 域名不通 / 还没发布（404）/ 内容坏了，一律返回 null。
  ///
  /// 请求头带 `Cache-Control: no-cache`：清单是「当前最新版本」的指针，
  /// 读到 24 小时前的旧副本等于假装没有新版本（发布时那份的 cache-control 也只有 60 秒）。
  Future<AppUpdateInfo?> fetchLatest() async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        _manifestUrl,
        options: Options(
          responseType: ResponseType.json,
          headers: const <String, String>{'Cache-Control': 'no-cache'},
        ),
      );
      if (response.statusCode != 200) return null;
      return AppUpdateInfo.fromJson(_decode(response.data));
    } on DioException {
      return null;
    }
  }

  /// 服务端没写 `application/json` 时 dio 会把 body 原样交出来（String），
  /// 自己再解一次，免得因为一个响应头就把新版本漏掉。
  dynamic _decode(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    return data;
  }
}
